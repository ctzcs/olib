package shader_lab

// 预设是显式导入/导出的预览快照，不自动改写 .oshader 或宿主材质文档。
// 分区：格式 / 原子应用与默认值 / 文件读写。
import "core:math"
import "core:strings"

import foster "olib:foster"
import fx "olib:kit/rendering/shader/effect"

// 兼容现有调用；持久格式现在由运行时可用的 material 包提供。
Preset_Field :: fx.Resource_Field
Preset :: fx.Resource

// 全部数值与纹理准备成功后一次切换；失败不改变旧值和 GPU 资源。
values_apply :: proc(s: ^Session, index: int, values: []fx.Value) -> bool {
	if index < 0 || index >= s.shader_count do return false
	p := &s.parameters[index]
	if !p.available || len(values) != len(p.live.fields) do return false
	for f, i in p.live.fields {
		for c in 0..<fx.components(f.kind) {
			if math.is_nan(values[i].number[c]) || math.is_inf(values[i].number[c]) {
				parameter_error(p, "Preset contains a non-finite value")
				return false
			}
		}
	}
	textures: [16]foster.Texture
	replaced: [16]bool
	slot := 0
	for f, i in p.live.fields {
		if f.kind != .Texture do continue
		// 单字段恢复不能因另一个纹理文件暂时丢失而失败，也不重建未变的 GPU 纹理。
		if values[i].texture == p.values[i].texture {
			textures[slot] = p.textures[slot]
			slot += 1
			continue
		}
		ok: bool
		textures[slot], ok = load_parameter_texture(s, s.device, values[i].texture)
		replaced[slot] = true
		if !ok {
			for &texture, j in textures {
				if replaced[j] do foster.TextureDispose(&texture)
			}
			parameter_error(p, "Cannot load preset texture; previous values retained")
			return false
		}
		slot += 1
	}
	owned := fx.values_make(p.live, p.live, values)
	color_picker_close(s, false)
	fx.values_dispose(p.values)
	p.values = owned
	for &texture, j in p.textures {
		if replaced[j] do parameter_texture_replace(s, &texture, textures[j])
	}
	texture_stamps_reset(s, p)
	parameter_error(p, "")
	return true
}

// field=-1 恢复整组；其他值只恢复该字段。
reset_defaults :: proc(s: ^Session, index: int, field: int = -1) -> bool {
	if index < 0 || index >= s.shader_count do return false
	p := &s.parameters[index]
	if !p.available || field < -1 || field >= len(p.live.fields) do return false
	color_picker_close(s, false)
	values := fx.values_make(p.live)
	defer fx.values_dispose(values)
	if field >= 0 {
		for _, i in p.live.fields {
			if i == field do continue
			delete(values[i].texture)
			values[i] = {p.values[i].number, strings.clone(p.values[i].texture)}
		}
	}
	return values_apply(s, index, values)
}

// 继续使用原有按钮与 API，保存结果同时是运行时材质资源。
save_preset :: proc(s: ^Session, index: int, path: string) -> bool {
	if index < 0 || index >= s.shader_count || path == "" do return false
	p := &s.parameters[index]
	if !p.available do return false
	color_picker_close(s, true)
	reason := preset_file_save(p.live, p.values, path, s.source_root)
	parameter_error(p, reason)
	return reason == ""
}

load_preset :: proc(s: ^Session, index: int, path: string) -> bool {
	if index < 0 || index >= s.shader_count do return false
	p := &s.parameters[index]
	if !p.available do return false
	values, reason := preset_file_load(p.live, path)
	defer fx.values_dispose(values)
	if reason != "" {
		parameter_error(p, reason)
		return false
	}
	return values_apply(s, index, values)
}
