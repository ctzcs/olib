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
	// 本次绘制的数值覆盖，不修改共享材质；nil 表示不覆盖。须在绘制调用期间保持有效。
	properties: ^mat.Property_Block,
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

// 返回 .None 表示成功；失败原因见 mat.draw_error_text。
model_draw :: proc(model: Model, transform: world.Matrix4, view: Model_View) -> mat.Draw_Error {
	return model_draw_selected(model, transform, view, "")
}

// 指定稳定 Pass ID；空 ID 返回 .Empty_Pass_Id，未知 ID 返回 .Unknown_Pass，
// 禁用的 Pass 成功（.None）但不绘制。
model_draw_pass :: proc(model: Model, pass_id: mat.Pass_Id,
	transform: world.Matrix4, view: Model_View) -> mat.Draw_Error {
	if pass_id == "" do return .Empty_Pass_Id
	return model_draw_selected(model, transform, view, pass_id)
}

// instanced 效果：一个模型的 count 个实例，每个 Pass 一次 Draw。实例数据（世界矩阵、tint、
// [Instance] 字段）来自调用方持有的 instances；Model.properties 对 instanced 绘制无效。
// 库不做剔除和排序：把可见的实例分块放进多个缓冲，按块调用即可。
model_draw_instances :: proc(model: Model, instances: ^Instance_Buffer, count: int,
	view: Model_View) -> mat.Draw_Error {
	return model_draw_instances_selected(model, instances, count, view, "")
}

// 指定稳定 Pass ID，规则同 model_draw_pass；便于“全部本体 → 全部描边”这类自选顺序。
model_draw_instances_pass :: proc(model: Model, instances: ^Instance_Buffer, count: int,
	pass_id: mat.Pass_Id, view: Model_View) -> mat.Draw_Error {
	if pass_id == "" do return .Empty_Pass_Id
	return model_draw_instances_selected(model, instances, count, view, pass_id)
}

@(private)
model_draw_instances_selected :: proc(model: Model, instances: ^Instance_Buffer, count: int,
	view: Model_View, pass_id: mat.Pass_Id) -> mat.Draw_Error {
	material := model.material
	if material == nil || material.owner == nil || material.effect == nil do return .Missing_Material
	if instances == nil || instances.capacity <= 0 do return .Instance_Mismatch
	return model_material_draw(material.owner.device, material.effect.desc, material.bindings, {
		mesh = model.mesh, target = view.target, view_projection = view.view_projection,
		time = view.time, delta_time = view.delta_time, frame = view.frame, pass_limit = view.pass_limit,
		options = {pass_id = pass_id}, instances = instances, instance_count = count,
	})
}

@(private)
model_draw_selected :: proc(model: Model, transform: world.Matrix4,
	view: Model_View, pass_id: mat.Pass_Id) -> mat.Draw_Error {
	material := model.material
	if material == nil || material.owner == nil || material.effect == nil do return .Missing_Material
	return model_material_draw(material.owner.device, material.effect.desc, material.bindings, {
		mesh = model.mesh, target = view.target, world_matrix = transform,
		view_projection = view.view_projection, time = view.time, delta_time = view.delta_time,
		frame = view.frame, pass_limit = view.pass_limit,
		options = {pass_id = pass_id, properties = model.properties},
	})
}
