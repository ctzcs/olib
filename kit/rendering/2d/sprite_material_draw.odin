package rendering2d

// 精灵材质绘制的实现与 ShaderLab 集成：几何生成、合批提交、sprite_material_draw。
// 业务通常使用 sprite_draw.odin 的 sprite_draw；本文件的 Sprite_Material_Draw 供工具借用 GPU 绑定。
// 分区：渲染器集成 / 合批与几何 / per-instance 顶点（instanced 效果）。
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

// instanced 效果的顶点：基础几何 + tint + 最多 MAX_INSTANCE_FIELDS 个 [Instance] 字段。
// Shader 通过 OlibInstance 读取（TEXCOORD2 为 tint，TEXCOORD3.. 为字段）；
// 网格格式只声明实际用到的前 1+字段数 个 float4，步长固定。
@(private)
Sprite_Instance_Vertex :: struct {
	position, uv: [2]f32,
	tint: [4]f32,
	data: [mat.MAX_INSTANCE_FIELDS][4]f32,
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
	// 顶点布局：0 为 Sprite_Vertex；n+1 为带 tint 和 n 个实例字段的 Sprite_Instance_Vertex。
	layout: int,
}

@(private)
Sprite_Submission :: struct {
	renderer: ^Sprite_Renderer,
	vertices: [4]Sprite_Vertex,
	tint: [4]f32,
	layout: int,
	mesh: ^foster.Mesh, // 非合批的 instanced 绘制：逐 Pass 上传顶点的网格
	user: mat.Draw_Options, // 调用方原本的回调，包装回调转发给它
}

@(private)
sprite_batch_matches :: proc(renderer: ^Sprite_Renderer, state: Sprite_Batch_State,
	material: ^foster.Material) -> bool {
	return renderer.batch_state == state && foster.MaterialEqualTo(&renderer.batch_material, material)
}

// 每批最多 SPRITE_BATCH_QUADS 个四边形，限制长期容量；uniform 按值保存，纹理和 Shader 仍借用。
@(private)
SPRITE_BATCH_QUADS :: 4096

@(private)
sprite_batch_submit :: proc(user_data: rawptr, _: int, command: ^foster.DrawCommand,
	values: ^mat.Instance_Values) {
	submission := cast(^Sprite_Submission)user_data
	renderer := submission.renderer
	state := Sprite_Batch_State{command.Target, command.BlendMode, command.CullMode,
		command.DepthCompare, command.DepthTestEnabled, command.DepthWriteEnabled, submission.layout}
	pending := len(renderer.vertices) + len(renderer.instance_vertices)
	if pending > 0 && (pending >= SPRITE_BATCH_QUADS*4 ||
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
		base := u32(len(renderer.instance_vertices))
		instance_vertices := sprite_instance_vertices(submission.vertices, submission.tint, values)
		append(&renderer.instance_vertices, ..instance_vertices[:])
		append(&renderer.indices, base, base+1, base+2, base, base+2, base+3)
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

// 屏幕像素坐标：左上原点、向右/下为正；相机可先乘入 transform。
// Vertex b0 为 64 字节列主序投影，Fragment b0 为 Clock / Pointer / Tint，b1 为参数。
// instanced 效果的 tint 与 [Instance] 字段改走顶点，Fragment b0 的 Tint 固定为白色。
sprite_material_draw :: proc(renderer: ^Sprite_Renderer, effect: mat.Effect_Desc,
	bindings: []mat.Material_Binding, draw: Sprite_Material_Draw) -> mat.Draw_Error {
	if renderer.device == nil do return .Missing_Device
	if !mat.effect_is_sprite(effect) do return .Not_Material_Effect
	w, h := draw.view.target.WidthInPixels, draw.view.target.HeightInPixels
	if w <= 0 || h <= 0 do return .Invalid_Target
	vertices := sprite_vertices(draw.frame, draw.origin, draw.transform)
	batch := renderer.batching && !mat.draw_has_hooks(draw.options)
	mesh := &renderer.mesh
	layout := 0
	if effect.instanced {
		slots := 0
		for binding in bindings do slots = max(slots, mat.instance_count(binding.schema))
		mesh = sprite_instance_mesh(renderer, slots)
		if mesh == nil do return .Missing_Device
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
	projection := [16]f32{2/f32(w), 0, 0, 0, 0, -2/f32(h), 0, 0,
		0, 0, 1, 0, -1, 1, 0, 1}
	frame_tint := effect.instanced ? [4]f32{1, 1, 1, 1} : draw.tint
	frame := [12]f32{draw.view.time, draw.view.delta_time, f32(draw.view.frame), 1,
		draw.pointer[0], draw.pointer[1], f32(w), f32(h),
		frame_tint[0], frame_tint[1], frame_tint[2], frame_tint[3]}
	submission := Sprite_Submission{renderer, vertices, draw.tint, layout, mesh, draw.options}
	request := mat.Material_Draw{
		mesh = mesh, target = draw.view.target, kind = .Sprite,
		vertex_uniform = mem.slice_to_bytes(projection[:]), frame_uniform = mem.slice_to_bytes(frame[:]),
		sprite_texture = draw.frame.Texture, pass_limit = draw.view.pass_limit,
		options = draw.options,
	}
	if batch {
		request.options.user_data = &submission
		request.options.submit = sprite_batch_submit
	} else if effect.instanced {
		// 每个 Pass 的实例数值不同：先把本 Pass 的顶点写进网格，再转交调用方的回调。
		request.options.user_data = &submission
		request.options.prepare = sprite_instance_prepare
		request.options.submit = draw.options.submit != nil ? sprite_instance_submit : nil
	}
	return mat.material_draw(renderer.device, effect, bindings, request)
}

// ------------------------------------------------------------------------------
// per-instance 顶点 —— instanced 效果的网格、顶点生成与回调包装
// ------------------------------------------------------------------------------

@(private)
sprite_instance_vertices :: proc(vertices: [4]Sprite_Vertex, tint: [4]f32,
	values: ^mat.Instance_Values) -> [4]Sprite_Instance_Vertex {
	result: [4]Sprite_Instance_Vertex
	for &vertex, i in result {
		vertex.position = vertices[i].position
		vertex.uv = vertices[i].uv
		vertex.tint = tint
		if values != nil do vertex.data = values.numbers
	}
	return result
}

// 带 slots 个实例字段的网格，首次使用时创建：4 个顶点、固定的两三角形索引。
@(private)
sprite_instance_mesh :: proc(renderer: ^Sprite_Renderer, slots: int) -> ^foster.Mesh {
	if slots < 0 || slots > mat.MAX_INSTANCE_FIELDS || renderer.device == nil do return nil
	mesh := &renderer.instance_meshes[slots]
	if renderer.instance_ready[slots] do return mesh
	elements := make([]foster.VertexElement, 3+slots, context.temp_allocator)
	elements[0] = {0, .Float2, false}
	elements[1] = {1, .Float2, false}
	for i in 2..<len(elements) do elements[i] = {i, .Float4, false}
	format := foster.VertexFormatMake(elements, size_of(Sprite_Instance_Vertex))
	defer foster.VertexFormatDispose(&format)
	foster.MeshInitWithFormat(mesh, renderer.device, format, .ThirtyTwo, "material sprite instanced")
	indices := [6]u32{0, 1, 2, 0, 2, 3}
	foster.MeshSetIndicesTyped(u32, mesh, indices[:])
	vertices: [4]Sprite_Instance_Vertex
	foster.MeshSetVerticesTyped(Sprite_Instance_Vertex, mesh, vertices[:])
	renderer.instance_ready[slots] = true
	return mesh
}

@(private)
sprite_instance_prepare :: proc(user_data: rawptr, pass_index: int, command: ^foster.DrawCommand,
	values: ^mat.Instance_Values) {
	submission := cast(^Sprite_Submission)user_data
	vertices := sprite_instance_vertices(submission.vertices, submission.tint, values)
	foster.MeshSetVerticesTyped(Sprite_Instance_Vertex, submission.mesh, vertices[:])
	user := submission.user
	if user.prepare != nil do user.prepare(user.user_data, pass_index, command, values)
}

@(private)
sprite_instance_submit :: proc(user_data: rawptr, pass_index: int, command: ^foster.DrawCommand,
	values: ^mat.Instance_Values) {
	user := (cast(^Sprite_Submission)user_data).user
	user.submit(user.user_data, pass_index, command, values)
}
