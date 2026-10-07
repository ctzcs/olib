// rendering3d:material3d —— Standard 材质数据与渲染状态推导（对位 DragonLib StandardMaterial3D / RenderState3D）。
package rendering3d

import dasset "olib:core/dasset"

// 分区：
//   渲染状态 —— 队列 / 剔除 / 深度写入
//   材质数据 —— StandardMaterial3D（对 dasset 材质的运行时包装）

// ------------------------------------------------------------------------------
// 渲染状态
// ------------------------------------------------------------------------------

// 一个 draw 的渲染状态：透明进透明队列（alpha 混合、不写深度），
// Mask 留在不透明队列（cutout 由 shader clip）；DoubleSided 关面剔除。
Render_State_3D :: struct {
	transparent: bool, // true = alpha 混合 + 不写深度
	cull_none:   bool, // true = 关闭背面剔除
}

RENDER_STATE_OPAQUE :: Render_State_3D{}
RENDER_STATE_TRANSPARENT :: Render_State_3D{transparent = true}

// 由 dasset 材质推导本次 draw 的渲染状态。
material_render_state :: proc(m: ^dasset.Dasset_Material) -> Render_State_3D {
	state := m.alpha_mode == .Blend ? RENDER_STATE_TRANSPARENT : RENDER_STATE_OPAQUE
	state.cull_none = m.double_sided
	return state
}

// ------------------------------------------------------------------------------
// 材质数据
// ------------------------------------------------------------------------------

// Standard PBR 材质的运行时形态：数值参数直接携带，贴图按索引引用
// 模型贴图表（GPU 纹理由调用侧按索引装配）。
Standard_Material_3D :: struct {
	base_color_factor: [4]f32,
	metallic:          f32,
	roughness:         f32,
	alpha_cutoff:      f32,
	normal_scale:      f32,
	occlusion_strength: f32,
	emissive_factor:   [3]f32,

	albedo_texture:    int, // -1 = 无
	normal_texture:    int,
	mr_texture:        int,
	occlusion_texture: int,
	emissive_texture:  int,

	state: Render_State_3D,
}

standard_material_from_dasset :: proc(m: ^dasset.Dasset_Material) -> Standard_Material_3D {
	return Standard_Material_3D{
		base_color_factor  = m.base_color_factor,
		metallic           = m.metallic,
		roughness          = m.roughness,
		alpha_cutoff       = m.alpha_cutoff,
		normal_scale       = m.normal_scale,
		occlusion_strength = m.occlusion_strength,
		emissive_factor    = m.emissive_factor,
		albedo_texture     = int(m.albedo_texture_index),
		normal_texture     = int(m.normal_texture_index),
		mr_texture         = int(m.metallic_roughness_texture_index),
		occlusion_texture  = int(m.occlusion_texture_index),
		emissive_texture   = int(m.emissive_texture_index),
		state              = material_render_state(m),
	}
}

material_has_normal_map :: proc(m: ^Standard_Material_3D) -> bool {
	return m.normal_texture >= 0
}
