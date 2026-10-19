package rendering2d

// 精灵绘制的业务入口：全部或指定 Pass；begin/end 内按调用顺序合并相邻兼容绘制。
// 最简调用是 sprite_draw / sprite_draw_texture：一个共享材质 + 一张图，不需要预先创建对象。
// 合批提交、几何与 ShaderLab 集成接口见 sprite_material_draw.odin。
// 分区：业务数据与入口 / 生命周期与合批。
import foster "olib:foster"
import mat "olib:kit/rendering/material"

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
	// instanced 效果的批次：实例记录的字节与条数（与 vertices 不会同时非空）。
	instance_bytes: [dynamic]u8,
	instance_pending: int,
	batch_material: foster.Material,
	batch_state: Sprite_Batch_State,
	// instanced 效果首次用到时创建：单位四边形的角点网格，以及带 n 个实例字段的实例流；dispose 释放已创建的。
	corner_mesh: foster.Mesh,
	corner_ready: bool,
	streams: [mat.MAX_INSTANCE_FIELDS+1]foster.VertexBuffer,
	stream_ready: [mat.MAX_INSTANCE_FIELDS+1]bool,
}
// 最简调用：共享材质 + 子图 + 变换。origin 是子图上的锚点像素；values 设置这个精灵的 [Instance] 字段，
// 不修改共享材质，取值不同的精灵仍可合批。动画帧可直接传 sprite_get_frame_at 取得的 subtexture。
// 不在 begin/end 范围内时立即绘制；范围内排队，按声明顺序提交全部 Pass。
// pass_id 为空画全部启用的 Pass；设置后只画该稳定 ID：未知 ID 返回 .Unknown_Pass，
// 被禁用的已知 Pass 返回 .None 但不绘制。返回 .None 表示成功；失败原因见 mat.draw_error_text。
sprite_draw :: proc(renderer: ^Sprite_Renderer, material: ^mat.Material, frame: foster.Subtexture,
	transform: foster.Matrix3x2, view: Sprite_View, tint: [4]f32 = {1, 1, 1, 1},
	origin: foster.Vec2 = {}, values: ^mat.Instance_Values = nil,
	pass_id: mat.Pass_Id = "") -> mat.Draw_Error {
	if material == nil || material.owner == nil || material.effect == nil do return .Missing_Material
	if material.owner.device != renderer.device do return .Device_Mismatch
	return sprite_material_draw(renderer, material.effect.desc, material.bindings, {
		frame = frame, origin = origin, transform = transform, view = view, tint = tint,
		options = {pass_id = pass_id, instance_values = values},
	})
}

// 直接画一张贴图（整张作为一帧）。texture 须在绘制/flush 期间保持有效。
sprite_draw_texture :: proc(renderer: ^Sprite_Renderer, material: ^mat.Material, texture: ^foster.Texture,
	transform: foster.Matrix3x2, view: Sprite_View, tint: [4]f32 = {1, 1, 1, 1},
	origin: foster.Vec2 = {}, values: ^mat.Instance_Values = nil,
	pass_id: mat.Pass_Id = "") -> mat.Draw_Error {
	if texture == nil || texture.Resource == nil do return .Missing_Sprite_Texture
	return sprite_draw(renderer, material, foster.SubtextureFromTexture(texture),
		transform, view, tint, origin, values, pass_id)
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
	if len(renderer.vertices) == 0 && renderer.instance_pending == 0 do return
	state := renderer.batch_state
	if state.layout > 0 {
		sprite_flush_instances(renderer, state.layout-1)
	} else {
		// MeshSet* 只扩大有效数量；每批先清计数，避免较小批次绘制上一批残留索引。
		foster.MeshClear(&renderer.mesh)
		foster.MeshSetVerticesTyped(Sprite_Vertex, &renderer.mesh, renderer.vertices[:])
		foster.MeshSetIndicesTyped(u32, &renderer.mesh, renderer.indices[:])
		command: foster.DrawCommand
		foster.DrawCommandFromMesh(&command, state.target, &renderer.mesh, &renderer.batch_material)
		sprite_flush_draw(renderer, &command)
	}
	clear(&renderer.vertices)
	clear(&renderer.indices)
	clear(&renderer.instance_bytes)
	renderer.instance_pending = 0
}

// instanced 批次：把累积的实例记录一次上传到实例流，用角点网格实例化绘制。
@(private)
sprite_flush_instances :: proc(renderer: ^Sprite_Renderer, slots: int) {
	mesh := sprite_corner_mesh(renderer)
	stream := sprite_stream(renderer, slots)
	if mesh == nil || stream == nil do return
	foster.VertexBufferUpload(stream, raw_data(renderer.instance_bytes), renderer.instance_pending, 0)
	command: foster.DrawCommand
	foster.DrawCommandFromMesh(&command, renderer.batch_state.target, mesh, &renderer.batch_material)
	// 角点网格的属性后移，让实例属性占据 0..4+slots；浅拷贝只换格式，共享 GPU 资源。
	shifted := mesh.VertexData
	shifted.Format = foster.VertexFormatClone(mesh.VertexData.Format)
	defer foster.VertexFormatDispose(&shifted.Format)
	for &element in shifted.Format.Elements do element.Index += mat.INSTANCE_FIXED_ATTRIBUTES + slots
	command.VertexBuffers[0].Buffer = &shifted
	append(&command.VertexBuffers, foster.VertexBufferBinding{Buffer = stream, InstanceInputRate = true})
	command.InstanceCount = renderer.instance_pending
	sprite_flush_draw(renderer, &command)
}

@(private)
sprite_flush_draw :: proc(renderer: ^Sprite_Renderer, command: ^foster.DrawCommand) {
	state := renderer.batch_state
	command.BlendMode = state.blend
	command.CullMode = state.cull
	command.DepthCompare = state.depth_compare
	command.DepthTestEnabled = state.depth_test
	command.DepthWriteEnabled = state.depth_write
	foster.GraphicsDeviceDraw(renderer.device, command)
	foster.DrawCommandDispose(command)
	renderer.draw_calls += 1
}

// renderer 不得搬动；借用 device，所有材质 Sprite 可共用一份，dispose 释放网格。
sprite_renderer_init :: proc(renderer: ^Sprite_Renderer, device: ^foster.GraphicsDevice) {
	renderer.device = device
	renderer.vertices = make([dynamic]Sprite_Vertex)
	renderer.indices = make([dynamic]u32)
	renderer.instance_bytes = make([dynamic]u8)
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
	delete(renderer.instance_bytes)
	foster.MaterialDispose(&renderer.batch_material)
	foster.MeshDispose(&renderer.mesh)
	if renderer.corner_ready do foster.MeshDispose(&renderer.corner_mesh)
	for ready, i in renderer.stream_ready {
		if ready do foster.VertexBufferDispose(&renderer.streams[i])
	}
	renderer^ = {}
}
