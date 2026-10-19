package rendering3d

// 模型绘制入口：业务通过 model_draw 使用材质；与精灵共用材质资源和 Pass 执行器。
// ShaderLab 集成接口见 model_material_draw.odin。
// 分区：视图 / 绘制入口。
import foster "olib:foster"
import mat "olib:kit/rendering/material"
import world "olib:kit/world"

// ------------------------------------------------------------------------------
// 绘制入口 —— 业务只提供材质、网格、变换与当前视图。
// ------------------------------------------------------------------------------

// 用材质画一个静态网格。pass_id 为空画全部启用的 Pass；设置后只画该稳定 ID：未知 ID 返回 .Unknown_Pass，
// 被禁用的已知 Pass 返回 .None 但不绘制。返回 .None 表示成功；失败原因见 mat.draw_error_text。
model_draw :: proc(material: ^mat.Material, mesh: ^foster.Mesh, transform: world.Matrix4, view: View,
	pass_id: mat.Pass_Id = "") -> mat.Draw_Error {
	if material == nil || material.owner == nil || material.effect == nil do return .Missing_Material
	return model_material_draw(material.owner.device, material.effect.desc, material.bindings, {
		mesh = mesh, world_matrix = transform, view = view, options = {pass_id = pass_id},
	})
}

// instanced 效果：缓冲里前 count 个实例，每个 Pass 一次 Draw。实例数据（世界矩阵、tint、
// [Instance] 字段）来自调用方持有的 Model_Buffer；统一参数（非 [Instance]）来自材质，整批共用。
// 库不做剔除和排序：把可见的实例分块放进多个缓冲，按块调用即可。pass_id 同 model_draw，
// 便于“全部本体 → 全部描边”这类自选顺序。
model_draw_buffer :: proc(material: ^mat.Material, mesh: ^foster.Mesh, buf: ^Model_Buffer, count: int,
	view: View, pass_id: mat.Pass_Id = "") -> mat.Draw_Error {
	if material == nil || material.owner == nil || material.effect == nil do return .Missing_Material
	if buf == nil || buf.capacity <= 0 do return .Instance_Buffer_Required
	return model_material_draw(material.owner.device, material.effect.desc, material.bindings, {
		mesh = mesh, view = view, options = {pass_id = pass_id}, instances = buf, instance_count = count,
	})
}
