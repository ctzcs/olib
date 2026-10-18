package rendering3d

// 静态模型使用公共材质资源与 Pass 执行器；此处只处理 3D 顶点矩阵。
import foster "olib:foster"
import mat "olib:kit/material"
import rendering "olib:kit/rendering"
import world "olib:kit/world"

// 每个静态网格/primitive 一个材质槽；网格由模型/场景资源拥有。
Model :: struct {
	mesh: ^foster.Mesh,
	material: ^rendering.Material,
}
Model_View :: struct {
	target: foster.DrawableTarget,
	view_projection: world.Matrix4,
	time, delta_time: f32,
	frame: u64,
	// 预览可限制 Pass 数；0 为完整效果，业务通常无需设置。
	pass_limit: int,
}

Model_Material_Draw :: struct {
	mesh: ^foster.Mesh,
	target: foster.DrawableTarget,
	world_matrix: world.Matrix4,
	view_projection: world.Matrix4,
	time, delta_time: f32,
	frame: u64,
	pointer: [2]f32,
	// 可选预览覆盖：enabled 空值使用声明；pass_limit=0 绘制全部。
	enabled: []bool,
	pass_limit: int,
	user_data: rawptr,
	prepare: proc(user_data: rawptr, pass_index: int, command: ^foster.DrawCommand),
	submit: proc(user_data: rawptr, pass_index: int, command: ^foster.DrawCommand),
}

model_material_draw :: proc(device: ^foster.GraphicsDevice, effect: mat.Effect_Desc,
	bindings: []rendering.Material_Binding, draw: Model_Material_Draw) -> bool {
	matrices: [128]u8
	pack_vertex_matrix_block(matrices[:], world.matrix4_multiply(draw.world_matrix, draw.view_projection), draw.world_matrix)
	frame: [48]u8
	std140_write_vec4(frame[:], 0, {draw.time, draw.delta_time, f32(draw.frame), 0})
	std140_write_vec4(frame[:], 16, {draw.pointer[0], draw.pointer[1], f32(draw.target.WidthInPixels), f32(draw.target.HeightInPixels)})
	std140_write_vec4(frame[:], 32, {1, 1, 1, 1})
	return rendering.material_draw(device, effect, bindings, {
		mesh = draw.mesh, target = draw.target, kind = .Model,
		vertex_uniform = matrices[:], frame_uniform = frame[:],
		enabled = draw.enabled, pass_limit = draw.pass_limit,
		user_data = draw.user_data, prepare = draw.prepare, submit = draw.submit,
	})
}

// ------------------------------------------------------------------------------
// 模型绘制 —— 业务只提供模型、变换与当前视图。
// ------------------------------------------------------------------------------

model_draw :: proc(model: Model, transform: world.Matrix4, view: Model_View) -> bool {
	material := model.material
	if material == nil || material.owner == nil || material.effect == nil do return false
	return model_material_draw(material.owner.device, material.effect.desc, material.bindings, {
		mesh = model.mesh, target = view.target, world_matrix = transform,
		view_projection = view.view_projection, time = view.time, delta_time = view.delta_time,
		frame = view.frame, pass_limit = view.pass_limit,
	})
}
