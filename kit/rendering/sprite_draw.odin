package rendering

// 精灵绘制：全部或指定 Pass；begin/end 内按调用顺序合并相邻兼容绘制。
// 分区：业务数据与入口 / 生命周期与合批 / 渲染器集成与内部几何。
import "core:mem"
import foster "olib:foster"
import mat "olib:kit/material"

// 帧动画资源 Sprite 不保存对象状态；各绘制对象独立持有材质参数和当前帧。
Sprite_Instance :: struct {
	frame: foster.Subtexture,
	origin: foster.Vec2,
	material: ^Material,
}
Sprite_View :: struct {
	target: foster.DrawableTarget,
	time, delta_time: f32,
	frame: u64,
	pass_limit: int,
}
Sprite_Renderer :: struct {
	device: ^foster.GraphicsDevice,
	mesh: foster.Mesh,
	// 最近一次 begin/end 范围内的精灵 Pass 数与实际 Draw 数。
	sprite_passes, draw_calls: int,
	// 以下由渲染器维护；材质快照拥有 uniform，Shader/纹理借用至 flush/end。
	batching: bool,
	vertices: [dynamic]Sprite_Vertex,
	indices: [dynamic]u32,
	batch_material: foster.Material,
	batch_state: Sprite_Batch_State,
}
// 不在 begin/end 范围内时保持立即绘制；范围内排队，按对象声明顺序提交全部 Pass。
sprite_draw :: proc(renderer: ^Sprite_Renderer, sprite: Sprite_Instance,
	transform: foster.Matrix3x2, view: Sprite_View, tint: [4]f32 = {1, 1, 1, 1}) -> bool {
	return sprite_draw_selected(renderer, sprite, transform, view, tint, "")
}

// 指定稳定 Pass ID；未知或空 ID 返回 false，禁用的 Pass 成功但不绘制。
sprite_draw_pass :: proc(renderer: ^Sprite_Renderer, sprite: Sprite_Instance, pass_id: mat.Pass_Id,
	transform: foster.Matrix3x2, view: Sprite_View, tint: [4]f32 = {1, 1, 1, 1}) -> bool {
	if pass_id == "" do return false
	return sprite_draw_selected(renderer, sprite, transform, view, tint, pass_id)
}

@(private)
sprite_draw_selected :: proc(renderer: ^Sprite_Renderer, sprite: Sprite_Instance,
	transform: foster.Matrix3x2, view: Sprite_View, tint: [4]f32, pass_id: mat.Pass_Id) -> bool {
	material := sprite.material
	if material == nil || material.owner == nil || material.effect == nil ||
		material.owner.device != renderer.device {
		return false
	}
	return sprite_material_draw(renderer, material.effect.desc, material.bindings, {
		frame = sprite.frame, origin = sprite.origin, transform = transform, view = view, tint = tint,
		pass_id = pass_id,
	})
}

// ------------------------------------------------------------------------------
// 生命周期与合批 —— 只合并相邻兼容请求，不排序、不清屏。
// ------------------------------------------------------------------------------

// 不允许嵌套；成功后须在本帧内 end。不同 renderer、模型、Batcher 或清屏前先 flush。
sprite_begin :: proc(renderer: ^Sprite_Renderer) -> bool {
	if renderer.device == nil || renderer.batching do return false
	renderer.batching = true
	renderer.sprite_passes = 0
	renderer.draw_calls = 0
	return true
}

sprite_end :: proc(renderer: ^Sprite_Renderer) {
	sprite_flush(renderer)
	renderer.batching = false
}

// 提交待画批次但保留 begin/end 范围；不影响外部 Batcher。
sprite_flush :: proc(renderer: ^Sprite_Renderer) {
	if len(renderer.vertices) == 0 do return
	// MeshSet* 只扩大有效数量；每批先清计数，避免较小批次绘制上一批残留索引。
	foster.MeshClear(&renderer.mesh)
	foster.MeshSetVerticesTyped(Sprite_Vertex, &renderer.mesh, renderer.vertices[:])
	foster.MeshSetIndicesTyped(u32, &renderer.mesh, renderer.indices[:])
	command: foster.DrawCommand
	foster.DrawCommandFromMesh(&command, renderer.batch_state.target, &renderer.mesh, &renderer.batch_material)
	state := renderer.batch_state
	command.BlendMode = state.blend
	command.CullMode = state.cull
	command.DepthCompare = state.depth_compare
	command.DepthTestEnabled = state.depth_test
	command.DepthWriteEnabled = state.depth_write
	foster.GraphicsDeviceDraw(renderer.device, &command)
	foster.DrawCommandDispose(&command)
	renderer.draw_calls += 1
	clear(&renderer.vertices)
	clear(&renderer.indices)
}

// renderer 不得搬动；借用 device，所有材质 Sprite 可共用一份，dispose 释放网格。
sprite_renderer_init :: proc(renderer: ^Sprite_Renderer, device: ^foster.GraphicsDevice) {
	renderer.device = device
	renderer.vertices = make([dynamic]Sprite_Vertex)
	renderer.indices = make([dynamic]u32)
	foster.MaterialInit(&renderer.batch_material)
	format := foster.VertexFormatMake([]foster.VertexElement{
		{0, .Float2, false}, {1, .Float2, false},
	}, size_of(Sprite_Vertex))
	defer foster.VertexFormatDispose(&format)
	foster.MeshInitWithFormat(&renderer.mesh, device, format, .ThirtyTwo, "material sprite")
	indices := [6]u32{0, 1, 2, 0, 2, 3}
	foster.MeshSetIndicesTyped(u32, &renderer.mesh, indices[:])
	vertices: [4]Sprite_Vertex
	foster.MeshSetVerticesTyped(Sprite_Vertex, &renderer.mesh, vertices[:])
}

sprite_renderer_dispose :: proc(renderer: ^Sprite_Renderer) {
	// 退出时丢弃未提交批次，不在 GPU 帧外尝试绘制。
	delete(renderer.vertices)
	delete(renderer.indices)
	foster.MaterialDispose(&renderer.batch_material)
	foster.MeshDispose(&renderer.mesh)
	renderer^ = {}
}

// ------------------------------------------------------------------------------
// 渲染器集成 —— ShaderLab 借用 GPU 绑定绘制；业务使用上面的 sprite_draw。
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
	enabled: []bool,
	pass_id: mat.Pass_Id,
	user_data: rawptr,
	prepare: proc(user_data: rawptr, pass_index: int, command: ^foster.DrawCommand),
	submit: proc(user_data: rawptr, pass_index: int, command: ^foster.DrawCommand),
}

@(private)
Sprite_Batch_State :: struct {
	target: foster.DrawableTarget,
	blend: foster.BlendMode,
	cull: foster.CullMode,
	depth_compare: foster.DepthCompare,
	depth_test, depth_write: bool,
}

@(private)
Sprite_Submission :: struct {
	renderer: ^Sprite_Renderer,
	vertices: [4]Sprite_Vertex,
}

@(private)
sprite_batch_matches :: proc(renderer: ^Sprite_Renderer, state: Sprite_Batch_State,
	material: ^foster.Material) -> bool {
	return renderer.batch_state == state && foster.MaterialEqualTo(&renderer.batch_material, material)
}

// 每批最多 4096 个四边形，限制长期容量；uniform 按值保存，纹理和 Shader 仍借用。
@(private)
sprite_batch_submit :: proc(user_data: rawptr, _: int, command: ^foster.DrawCommand) {
	submission := cast(^Sprite_Submission)user_data
	renderer := submission.renderer
	state := Sprite_Batch_State{command.Target, command.BlendMode, command.CullMode,
		command.DepthCompare, command.DepthTestEnabled, command.DepthWriteEnabled}
	if len(renderer.vertices) > 0 && (len(renderer.vertices) >= 4096*4 ||
		!sprite_batch_matches(renderer, state, command.Material)) {
		sprite_flush(renderer)
	}
	if len(renderer.vertices) == 0 {
		foster.MaterialCopyTo(command.Material, &renderer.batch_material)
		renderer.batch_state = state
	}
	base := u32(len(renderer.vertices))
	append(&renderer.vertices, ..submission.vertices[:])
	append(&renderer.indices, base, base+1, base+2, base, base+2, base+3)
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
sprite_material_draw :: proc(renderer: ^Sprite_Renderer, effect: mat.Effect_Desc,
	bindings: []Material_Binding, draw: Sprite_Material_Draw) -> bool {
	if renderer.device == nil || !mat.effect_is_sprite(effect) do return false
	w, h := draw.view.target.WidthInPixels, draw.view.target.HeightInPixels
	if w <= 0 || h <= 0 do return false
	vertices := sprite_vertices(draw.frame, draw.origin, draw.transform)
	batch := renderer.batching && draw.prepare == nil && draw.submit == nil
	if !batch {
		// 工具回调可以改变任意 DrawCommand 状态，独立提交作为合批边界。
		sprite_flush(renderer)
		foster.MeshClear(&renderer.mesh)
		foster.MeshSetVerticesTyped(Sprite_Vertex, &renderer.mesh, vertices[:])
		indices := [6]u32{0, 1, 2, 0, 2, 3}
		foster.MeshSetIndicesTyped(u32, &renderer.mesh, indices[:])
	}
	projection := [16]f32{2/f32(w), 0, 0, 0, 0, -2/f32(h), 0, 0,
		0, 0, 1, 0, -1, 1, 0, 1}
	frame := [12]f32{draw.view.time, draw.view.delta_time, f32(draw.view.frame), 1,
		draw.pointer[0], draw.pointer[1], f32(w), f32(h),
		draw.tint[0], draw.tint[1], draw.tint[2], draw.tint[3]}
	submission := Sprite_Submission{renderer, vertices}
	request := Material_Draw{
		mesh = &renderer.mesh, target = draw.view.target, kind = .Sprite,
		vertex_uniform = mem.slice_to_bytes(projection[:]), frame_uniform = mem.slice_to_bytes(frame[:]),
		sprite_texture = draw.frame.Texture, enabled = draw.enabled, pass_limit = draw.view.pass_limit,
		pass_id = draw.pass_id,
		user_data = draw.user_data, prepare = draw.prepare, submit = draw.submit,
	}
	if batch {
		request.user_data = &submission
		request.submit = sprite_batch_submit
	}
	return material_draw(renderer.device, effect, bindings, request)
}
