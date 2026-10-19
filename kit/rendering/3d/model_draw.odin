package rendering3d

// 模型绘制入口：业务通过 model_draw 使用材质；与精灵共用材质资源和 Pass 执行器。
// ShaderLab 集成接口见 model_material_draw.odin。
// 分区：业务数据与入口。
import foster "olib:foster"
import mat "olib:kit/rendering/material"
import world "olib:kit/world"

// 每个静态网格/primitive 一个材质槽；网格由模型/场景资源拥有。
Model :: struct {
	mesh: ^foster.Mesh,
	material: ^mat.Material,
}
Model_View :: struct {
	target: foster.DrawableTarget,
	view_projection: world.Matrix4,
	time, delta_time: f32,
	frame: u64,
	// 预览可限制 Pass 数；0 为完整效果，业务通常无需设置。
	pass_limit: int,
}

// ------------------------------------------------------------------------------
// 模型绘制 —— 业务只提供模型、变换与当前视图。
// ------------------------------------------------------------------------------

// pass_id 为空画全部启用的 Pass；设置后只画该稳定 ID：未知 ID 返回 .Unknown_Pass，
// 被禁用的已知 Pass 返回 .None 但不绘制。返回 .None 表示成功；失败原因见 mat.draw_error_text。
model_draw :: proc(model: Model, transform: world.Matrix4, view: Model_View,
	pass_id: mat.Pass_Id = "") -> mat.Draw_Error {
	material := model.material
	if material == nil || material.owner == nil || material.effect == nil do return .Missing_Material
	return model_material_draw(material.owner.device, material.effect.desc, material.bindings, {
		mesh = model.mesh, target = view.target, world_matrix = transform,
		view_projection = view.view_projection, time = view.time, delta_time = view.delta_time,
		frame = view.frame, pass_limit = view.pass_limit,
		options = {pass_id = pass_id},
	})
}

// instanced 效果：一个模型的 count 个实例，每个 Pass 一次 Draw。实例数据（世界矩阵、tint、
// [Instance] 字段）来自调用方持有的 Model_Buffer；统一参数（非 [Instance]）来自材质，整批共用。
// 库不做剔除和排序：把可见的实例分块放进多个缓冲，按块调用即可。pass_id 同 model_draw，
// 便于“全部本体 → 全部描边”这类自选顺序。
model_draw_buffer :: proc(model: Model, buf: ^Model_Buffer, count: int, view: Model_View,
	pass_id: mat.Pass_Id = "") -> mat.Draw_Error {
	material := model.material
	if material == nil || material.owner == nil || material.effect == nil do return .Missing_Material
	if buf == nil || buf.capacity <= 0 do return .Instance_Mismatch
	return model_material_draw(material.owner.device, material.effect.desc, material.bindings, {
		mesh = model.mesh, target = view.target, view_projection = view.view_projection,
		time = view.time, delta_time = view.delta_time, frame = view.frame, pass_limit = view.pass_limit,
		options = {pass_id = pass_id}, instances = buf, instance_count = count,
	})
}
