package rendering2d

// 精灵材质绘制的实现与 ShaderLab 集成：几何生成、合批提交、sprite_material_draw。
// 业务通常使用 sprite_draw.odin 的 sprite_draw；本文件的 Sprite_Material_Draw 供工具借用 GPU 绑定。
// 分区：渲染器集成 / 合批与几何 / instanced 效果（实例记录、角点网格与实例流）。
import "core:mem"

import foster "olib:foster"
import mat "olib:kit/rendering/material"

// ------------------------------------------------------------------------------
// 渲染器集成 —— ShaderLab 借用 GPU 绑定绘制；业务使用 sprite_draw.odin。
// ------------------------------------------------------------------------------

@(private)
Sprite_Vertex :: struct {
	position, uv: [2]f32,
}

Sprite_Material_Draw :: struct {
	frame: foster.Subtexture,
	origin: foster.Vec2,
	transform: foster.Matrix3x2,
	view: Sprite_View,
	tint: [4]f32,
	pointer: [2]f32,
	options: mat.Draw_Options,
}

@(private)
Sprite_Batch_State :: struct {
	target: foster.DrawableTarget,
	blend: foster.BlendMode,
	cull: foster.CullMode,
	depth_compare: foster.DepthCompare,
	depth_test, depth_write: bool,
	// 批次布局：0 为逐顶点的 Sprite_Vertex（普通效果）；n+1 为 instanced 效果、n 个实例字段的实例记录。
	layout: int,
}

@(private)
Sprite_Submission :: struct {
	renderer: ^Sprite_Renderer,
	vertices: [4]Sprite_Vertex, // 普通效果的四个顶点
	item: Sprite_Item, // instanced 效果的实例记录（字段数值在提交时按 Pass 写入）
	layout: int,
	stream: ^foster.VertexBuffer, // 非合批的 instanced 绘制：逐 Pass 写入单个实例记录的缓冲
	user: mat.Draw_Options, // 调用方原本的回调，包装回调转发给它
}

@(private)
sprite_batch_matches :: proc(renderer: ^Sprite_Renderer, state: Sprite_Batch_State,
	material: ^foster.Material) -> bool {
	return renderer.batch_state == state && foster.MaterialEqualTo(&renderer.batch_material, material)
}

// 每批的容量上限，限制长期占用的内存；uniform 按值保存，纹理和 Shader 仍借用。
// 普通效果每批 SPRITE_BATCH_QUADS 个四边形；instanced 效果每批 SPRITE_BATCH_INSTANCES 个实例记录。
@(private)
SPRITE_BATCH_QUADS :: 4096
@(private)
SPRITE_BATCH_INSTANCES :: 65536

@(private)
sprite_batch_submit :: proc(user_data: rawptr, _: int, command: ^foster.DrawCommand,
	values: ^mat.Instance_Values) {
	submission := cast(^Sprite_Submission)user_data
	renderer := submission.renderer
	state := Sprite_Batch_State{command.Target, command.BlendMode, command.CullMode,
		command.DepthCompare, command.DepthTestEnabled, command.DepthWriteEnabled, submission.layout}
	pending := len(renderer.vertices) + renderer.instance_pending
	if pending > 0 && (len(renderer.vertices) >= SPRITE_BATCH_QUADS*4 ||
		renderer.instance_pending >= SPRITE_BATCH_INSTANCES ||
		!sprite_batch_matches(renderer, state, command.Material)) {
		sprite_flush(renderer)
		pending = 0
	}
	if pending == 0 {
		foster.MaterialCopyTo(command.Material, &renderer.batch_material)
		renderer.batch_state = state
	}
	if submission.layout == 0 {
		base := u32(len(renderer.vertices))
		append(&renderer.vertices, ..submission.vertices[:])
		append(&renderer.indices, base, base+1, base+2, base, base+2, base+3)
	} else {
		slots := submission.layout - 1
		own: [][4]f32
		if values != nil do own = values.numbers[:slots]
		stride := sprite_stride(slots)
		offset := len(renderer.instance_bytes)
		resize(&renderer.instance_bytes, offset+stride)
		sprite_item_pack(renderer.instance_bytes[offset:], submission.item, slots, own)
		renderer.instance_pending += 1
	}
	renderer.sprite_passes += 1
}

// 保留图集裁剪后的 DrawCoords / TexCoords；origin 相对于未裁剪原图。
@(private)
sprite_vertices :: proc(frame: foster.Subtexture, origin: foster.Vec2,
	transform: foster.Matrix3x2) -> [4]Sprite_Vertex {
	vertices: [4]Sprite_Vertex
	for &vertex, i in vertices {
		point := foster.Matrix3x2TransformPoint(transform, frame.DrawCoords[i]-origin)
		vertex = {{point.x, point.y}, {frame.TexCoords[i].x, frame.TexCoords[i].y}}
	}
	return vertices
}

// Vertex b0 的 64 字节列主序投影（左上原点的像素坐标）与 Fragment b0 的 Clock / Pointer / Tint。
@(private)
sprite_uniforms :: proc(view: Sprite_View, pointer: [2]f32, tint: [4]f32) -> (projection: [16]f32, frame: [12]f32) {
	w, h := view.target.WidthInPixels, view.target.HeightInPixels
	projection = {2/f32(w), 0, 0, 0, 0, -2/f32(h), 0, 0, 0, 0, 1, 0, -1, 1, 0, 1}
	frame = {view.time, view.delta_time, f32(view.frame), 1, pointer[0], pointer[1], f32(w), f32(h),
		tint[0], tint[1], tint[2], tint[3]}
	return
}

// 屏幕像素坐标：左上原点、向右/下为正；相机可先乘入 transform。
// Vertex b0 为 64 字节列主序投影，Fragment b0 为 Clock / Pointer / Tint，b1 为参数。
// instanced 效果的 tint 与 [Instance] 字段改走实例记录，Fragment b0 的 Tint 固定为白色。
sprite_material_draw :: proc(renderer: ^Sprite_Renderer, effect: mat.Effect_Desc,
	bindings: []mat.Material_Binding, draw: Sprite_Material_Draw) -> mat.Draw_Error {
	if renderer.device == nil do return .Missing_Device
	if !mat.effect_is_sprite(effect) do return .Not_Material_Effect
	w, h := draw.view.target.WidthInPixels, draw.view.target.HeightInPixels
	if w <= 0 || h <= 0 do return .Invalid_Target
	vertices := sprite_vertices(draw.frame, draw.origin, draw.transform)
	batch := renderer.batching && !mat.draw_has_hooks(draw.options)
	mesh := &renderer.mesh
	layout, slots := 0, 0
	stream: ^foster.VertexBuffer
	if effect.instanced {
		for binding in bindings do slots = max(slots, mat.instance_count(binding.schema))
		mesh = sprite_corner_mesh(renderer)
		stream = sprite_stream(renderer, slots)
		if mesh == nil || stream == nil do return .Missing_Device
		layout = slots + 1
	}
	if !batch {
		// 工具回调可以改变任意 DrawCommand 状态，独立提交作为合批边界。
		sprite_flush(renderer)
		if !effect.instanced {
			foster.MeshClear(&renderer.mesh)
			foster.MeshSetVerticesTyped(Sprite_Vertex, &renderer.mesh, vertices[:])
			indices := [6]u32{0, 1, 2, 0, 2, 3}
			foster.MeshSetIndicesTyped(u32, &renderer.mesh, indices[:])
		}
	}
	projection, frame := sprite_uniforms(draw.view, draw.pointer, effect.instanced ? [4]f32{1, 1, 1, 1} : draw.tint)
	submission := Sprite_Submission{renderer, vertices, sprite_item_make(draw.frame, draw.origin, draw.transform, draw.tint),
		layout, stream, draw.options}
	request := mat.Material_Draw{
		mesh = mesh, target = draw.view.target, kind = .Sprite,
		vertex_uniform = mem.slice_to_bytes(projection[:]), frame_uniform = mem.slice_to_bytes(frame[:]),
		sprite_texture = draw.frame.Texture, pass_limit = draw.view.pass_limit,
		options = draw.options,
	}
	if effect.instanced {
		// 实例数据来自实例流：合批时只借它通过材质检查，真正的记录在 flush 时统一上传。
		request.instance_buffer = stream
		request.instance_count = 1
		request.instance_slots = slots
		request.mesh_location_offset = mat.INSTANCE_FIXED_ATTRIBUTES + slots
	}
	if batch {
		request.options.user_data = &submission
		request.options.submit = sprite_batch_submit
	} else if effect.instanced {
		// 每个 Pass 的实例数值不同：先把本 Pass 的记录写进实例流，再转交调用方的回调。
		request.options.user_data = &submission
		request.options.prepare = sprite_instance_prepare
		request.options.submit = draw.options.submit != nil ? sprite_instance_submit : nil
	}
	return mat.material_draw(renderer.device, effect, bindings, request)
}

// ------------------------------------------------------------------------------
// instanced 效果 —— 角点网格、实例流与回调包装
// ------------------------------------------------------------------------------

// 单位四边形的四个角点，实例着色器用 olib_sprite_vertex 把它展开成屏幕上的矩形。
@(private)
sprite_corner_mesh :: proc(renderer: ^Sprite_Renderer) -> ^foster.Mesh {
	if renderer.device == nil do return nil
	mesh := &renderer.corner_mesh
	if renderer.corner_ready do return mesh
	format := foster.VertexFormatMake([]foster.VertexElement{{0, .Float2, false}}, size_of([2]f32))
	defer foster.VertexFormatDispose(&format)
	foster.MeshInitWithFormat(mesh, renderer.device, format, .ThirtyTwo, "material sprite corners")
	corners := [4][2]f32{{0, 0}, {1, 0}, {1, 1}, {0, 1}}
	foster.MeshSetVerticesTyped([2]f32, mesh, corners[:])
	indices := [6]u32{0, 1, 2, 0, 2, 3}
	foster.MeshSetIndicesTyped(u32, mesh, indices[:])
	renderer.corner_ready = true
	return mesh
}

// 渲染器内部、带 slots 个实例字段的实例流（合批 flush 与单个绘制共用），首次使用时创建。
@(private)
sprite_stream :: proc(renderer: ^Sprite_Renderer, slots: int) -> ^foster.VertexBuffer {
	if slots < 0 || slots > mat.MAX_INSTANCE_FIELDS || renderer.device == nil do return nil
	stream := &renderer.streams[slots]
	if renderer.stream_ready[slots] do return stream
	format := sprite_instance_format(slots)
	defer foster.VertexFormatDispose(&format)
	foster.VertexBufferInit(stream, renderer.device, format, "material sprite instances")
	renderer.stream_ready[slots] = true
	return stream
}

@(private)
sprite_instance_prepare :: proc(user_data: rawptr, pass_index: int, command: ^foster.DrawCommand,
	values: ^mat.Instance_Values) {
	submission := cast(^Sprite_Submission)user_data
	slots := submission.layout - 1
	own: [][4]f32
	if values != nil do own = values.numbers[:slots]
	record: [80 + 16*mat.MAX_INSTANCE_FIELDS]u8
	sprite_item_pack(record[:], submission.item, slots, own)
	foster.VertexBufferUpload(submission.stream, raw_data(record[:]), 1, 0)
	user := submission.user
	if user.prepare != nil do user.prepare(user.user_data, pass_index, command, values)
}

@(private)
sprite_instance_submit :: proc(user_data: rawptr, pass_index: int, command: ^foster.DrawCommand,
	values: ^mat.Instance_Values) {
	user := (cast(^Sprite_Submission)user_data).user
	user.submit(user.user_data, pass_index, command, values)
}
