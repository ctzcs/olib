package rendering3d

// 模型材质绘制的实现与 ShaderLab 集成：打包顶点矩阵与帧 uniform，再交给材质 Pass 执行器。
// 业务通常使用 model_draw.odin 的 model_draw。
import foster "olib:foster"
import mat "olib:kit/rendering/material"
import world "olib:kit/world"

// ------------------------------------------------------------------------------
// 渲染器集成 —— ShaderLab 借用 GPU 绑定绘制；业务使用上面的 model_draw。
// ------------------------------------------------------------------------------

Model_Material_Draw :: struct {
	mesh: ^foster.Mesh,
	target: foster.DrawableTarget,
	world_matrix: world.Matrix4,
	view_projection: world.Matrix4,
	time, delta_time: f32,
	frame: u64,
	pointer: [2]f32,
	pass_limit: int, // 0 绘制全部，否则只绘制前 N 个 Pass。
	options: mat.Draw_Options,
	// instanced 效果：每实例数据与实例数（超出缓冲容量按容量截断）。此时 world_matrix 被忽略，
	// 顶点 b0 为 {ViewProjection, 单位矩阵}，世界矩阵来自实例缓冲。
	instances: ^Model_Buffer,
	instance_count: int,
}

model_material_draw :: proc(device: ^foster.GraphicsDevice, effect: mat.Effect_Desc,
	bindings: []mat.Material_Binding, draw: Model_Material_Draw) -> mat.Draw_Error {
	matrices: [128]u8
	if draw.instances != nil {
		pack_vertex_matrix_block(matrices[:], draw.view_projection, world.MATRIX4_IDENTITY)
	} else {
		pack_vertex_matrix_block(matrices[:], world.matrix4_multiply(draw.world_matrix, draw.view_projection), draw.world_matrix)
	}
	frame: [48]u8
	std140_write_vec4(frame[:], 0, {draw.time, draw.delta_time, f32(draw.frame), 0})
	std140_write_vec4(frame[:], 16, {draw.pointer[0], draw.pointer[1], f32(draw.target.WidthInPixels), f32(draw.target.HeightInPixels)})
	std140_write_vec4(frame[:], 32, {1, 1, 1, 1})
	request := mat.Material_Draw{
		mesh = draw.mesh, target = draw.target, kind = .Model,
		vertex_uniform = matrices[:], frame_uniform = frame[:],
		pass_limit = draw.pass_limit, options = draw.options,
	}
	if draw.instances != nil {
		request.mesh_location_offset = mat.INSTANCE_FIXED_ATTRIBUTES + draw.instances.slots
		request.instance_buffer = &draw.instances.buffer
		request.instance_count = clamp(draw.instance_count, 0, draw.instances.capacity)
		request.instance_slots = draw.instances.slots
	}
	return mat.material_draw(device, effect, bindings, request)
}
