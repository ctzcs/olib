package rendering2d

// 精灵绘制的业务入口：全部或指定 Pass；begin/end 内按调用顺序合并相邻兼容绘制。
// 最简调用是 sprite_draw_frame / sprite_draw_texture：一个共享材质 + 一张图，不需要预先创建对象。
// 合批提交、几何与 ShaderLab 集成接口见 sprite_material_draw.odin。
// 分区：业务数据与入口 / 生命周期与合批。
import foster "olib:foster"
import mat "olib:kit/rendering/material"

// 帧动画资源 Sprite 不保存对象状态；各绘制对象独立持有材质参数和当前帧。
Sprite_Instance :: struct {
	frame: foster.Subtexture,
	origin: foster.Vec2,
	material: ^mat.Material,
	// 本次绘制的数值覆盖，不修改共享材质；nil 表示不覆盖。须在绘制调用期间保持有效。
	properties: ^mat.Property_Block,
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
	instance_vertices: [dynamic]Sprite_Instance_Vertex, // instanced 效果的批次（与 vertices 不会同时非空）
	indices: [dynamic]u32,
	batch_material: foster.Material,
	batch_state: Sprite_Batch_State,
	// 带 n 个实例字段的网格，首次用到时创建；dispose 释放已创建的。
	instance_meshes: [mat.MAX_INSTANCE_FIELDS+1]foster.Mesh,
	instance_ready: [mat.MAX_INSTANCE_FIELDS+1]bool,
}
// 最简调用：共享材质 + 子图 + 变换。origin 是子图上的锚点像素；properties 可按次覆盖材质数值。
// 不需要创建 Sprite_Instance；动画帧可直接传 sprite_get_frame_at 取得的 subtexture。
sprite_draw_frame :: proc(renderer: ^Sprite_Renderer, material: ^mat.Material, frame: foster.Subtexture,
	transform: foster.Matrix3x2, view: Sprite_View, tint: [4]f32 = {1, 1, 1, 1},
	origin: foster.Vec2 = {}, properties: ^mat.Property_Block = nil) -> mat.Draw_Error {
	return sprite_draw_selected(renderer, {frame, origin, material, properties}, transform, view, tint, "")
}

// 直接画一张贴图（整张作为一帧）。texture 须在绘制/flush 期间保持有效。
sprite_draw_texture :: proc(renderer: ^Sprite_Renderer, material: ^mat.Material, texture: ^foster.Texture,
	transform: foster.Matrix3x2, view: Sprite_View, tint: [4]f32 = {1, 1, 1, 1},
	origin: foster.Vec2 = {}, properties: ^mat.Property_Block = nil) -> mat.Draw_Error {
	if texture == nil || texture.Resource == nil do return .Missing_Sprite_Texture
	return sprite_draw_frame(renderer, material, foster.SubtextureFromTexture(texture),
		transform, view, tint, origin, properties)
}

// 不在 begin/end 范围内时保持立即绘制；范围内排队，按对象声明顺序提交全部 Pass。
// 返回 .None 表示成功；失败原因见 mat.draw_error_text。
sprite_draw :: proc(renderer: ^Sprite_Renderer, sprite: Sprite_Instance,
	transform: foster.Matrix3x2, view: Sprite_View, tint: [4]f32 = {1, 1, 1, 1}) -> mat.Draw_Error {
	return sprite_draw_selected(renderer, sprite, transform, view, tint, "")
}

// 指定稳定 Pass ID；空 ID 返回 .Empty_Pass_Id，未知 ID 返回 .Unknown_Pass，
// 禁用的 Pass 成功（.None）但不绘制。
sprite_draw_pass :: proc(renderer: ^Sprite_Renderer, sprite: Sprite_Instance, pass_id: mat.Pass_Id,
	transform: foster.Matrix3x2, view: Sprite_View, tint: [4]f32 = {1, 1, 1, 1}) -> mat.Draw_Error {
	if pass_id == "" do return .Empty_Pass_Id
	return sprite_draw_selected(renderer, sprite, transform, view, tint, pass_id)
}

@(private)
sprite_draw_selected :: proc(renderer: ^Sprite_Renderer, sprite: Sprite_Instance,
	transform: foster.Matrix3x2, view: Sprite_View, tint: [4]f32, pass_id: mat.Pass_Id) -> mat.Draw_Error {
	material := sprite.material
	if material == nil || material.owner == nil || material.effect == nil do return .Missing_Material
	if material.owner.device != renderer.device do return .Device_Mismatch
	return sprite_material_draw(renderer, material.effect.desc, material.bindings, {
		frame = sprite.frame, origin = sprite.origin, transform = transform, view = view, tint = tint,
		options = {pass_id = pass_id, properties = sprite.properties},
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
	if len(renderer.vertices) == 0 && len(renderer.instance_vertices) == 0 do return
	state := renderer.batch_state
	mesh := &renderer.mesh
	if state.layout > 0 do mesh = sprite_instance_mesh(renderer, state.layout-1)
	if mesh != nil {
		// MeshSet* 只扩大有效数量；每批先清计数，避免较小批次绘制上一批残留索引。
		foster.MeshClear(mesh)
		if state.layout > 0 {
			foster.MeshSetVerticesTyped(Sprite_Instance_Vertex, mesh, renderer.instance_vertices[:])
		} else {
			foster.MeshSetVerticesTyped(Sprite_Vertex, mesh, renderer.vertices[:])
		}
		foster.MeshSetIndicesTyped(u32, mesh, renderer.indices[:])
		sprite_flush_mesh(renderer, mesh)
	}
	clear(&renderer.vertices)
	clear(&renderer.instance_vertices)
	clear(&renderer.indices)
}

@(private)
sprite_flush_mesh :: proc(renderer: ^Sprite_Renderer, mesh: ^foster.Mesh) {
	command: foster.DrawCommand
	foster.DrawCommandFromMesh(&command, renderer.batch_state.target, mesh, &renderer.batch_material)
	state := renderer.batch_state
	command.BlendMode = state.blend
	command.CullMode = state.cull
	command.DepthCompare = state.depth_compare
	command.DepthTestEnabled = state.depth_test
	command.DepthWriteEnabled = state.depth_write
	foster.GraphicsDeviceDraw(renderer.device, &command)
	foster.DrawCommandDispose(&command)
	renderer.draw_calls += 1
}

// renderer 不得搬动；借用 device，所有材质 Sprite 可共用一份，dispose 释放网格。
sprite_renderer_init :: proc(renderer: ^Sprite_Renderer, device: ^foster.GraphicsDevice) {
	renderer.device = device
	renderer.vertices = make([dynamic]Sprite_Vertex)
	renderer.instance_vertices = make([dynamic]Sprite_Instance_Vertex)
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
	delete(renderer.instance_vertices)
	delete(renderer.indices)
	foster.MaterialDispose(&renderer.batch_material)
	foster.MeshDispose(&renderer.mesh)
	for ready, i in renderer.instance_ready {
		if ready do foster.MeshDispose(&renderer.instance_meshes[i])
	}
	renderer^ = {}
}
