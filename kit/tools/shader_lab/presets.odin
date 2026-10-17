package shader_lab

// 预设是显式导入/导出的预览快照，不自动改写 Odin 或宿主材质文档。
// 分区：格式 / 原子应用与默认值 / 文件读写。
import "core:encoding/json"
import "core:fmt"
import "core:math"
import "core:os"
import "core:path/filepath"
import "core:strings"

import foster "olib:foster"
import mat "olib:kit/material"

Preset_Field :: struct {
	id: string,
	kind: mat.Kind,
	number: [4]f32,
	texture: string,
}

Preset :: struct {
	version: int,
	group: string,
	fields: []Preset_Field,
}

// 全部数值与纹理准备成功后一次切换；失败不改变旧值和 GPU 资源。
values_apply :: proc(s: ^Session, index: int, values: []mat.Value) -> bool {
	if index < 0 || index >= s.shader_count do return false
	p := &s.parameters[index]
	if !p.available || len(values) != len(p.live.fields) do return false
	for f, i in p.live.fields {
		for c in 0..<mat.components(f.kind) {
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
	owned := mat.values_make(p.live, p.live, values)
	color_picker_close(s, false)
	mat.values_dispose(p.values)
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
	values := mat.values_make(p.live)
	defer mat.values_dispose(values)
	if field >= 0 {
		for _, i in p.live.fields {
			if i == field do continue
			delete(values[i].texture)
			values[i] = {p.values[i].number, strings.clone(p.values[i].texture)}
		}
	}
	return values_apply(s, index, values)
}

save_preset :: proc(s: ^Session, index: int, path: string) -> bool {
	if index < 0 || index >= s.shader_count || path == "" do return false
	p := &s.parameters[index]
	if !p.available || len(p.live.fields) == 0 do return false
	color_picker_close(s, true)
	data := Preset{version = 1, group = p.name,
		fields = make([]Preset_Field, len(p.live.fields), context.temp_allocator)}
	directory, _ := filepath.abs(filepath.dir(path), context.temp_allocator)
	for f, i in p.live.fields {
		value := p.values[i]
		texture := value.texture
		if texture != "" {
			absolute, _ := filepath.abs(texture_path(s, texture), context.temp_allocator)
			relative, err := filepath.rel(directory, absolute, context.temp_allocator)
			texture = err == nil ? relative : absolute
		}
		data.fields[i] = {f.id, f.kind, value.number, texture}
	}
	bytes, err := json.marshal(data, allocator = context.temp_allocator)
	if err != nil {
		parameter_error(p, "Cannot encode preset")
		return false
	}
	if os.make_directory_all(directory) != nil {
		parameter_error(p, "Cannot create preset directory")
		return false
	}
	staging, stage_err := os.make_directory_temp(directory, ".preset_*", context.temp_allocator)
	if stage_err != nil {
		parameter_error(p, "Cannot stage preset")
		return false
	}
	temporary := fmt.tprintf("%s/preset.json", staging)
	defer {
		_ = os.remove(temporary)
		_ = os.remove(staging)
	}
	if os.write_entire_file(temporary, bytes) != nil || os.rename(temporary, path) != nil {
		parameter_error(p, "Preset save failed; previous file retained")
		return false
	}
	parameter_error(p, "")
	return true
}

load_preset :: proc(s: ^Session, index: int, path: string) -> bool {
	if index < 0 || index >= s.shader_count do return false
	p := &s.parameters[index]
	if !p.available do return false
	bytes, err := os.read_entire_file(path, context.temp_allocator)
	data: Preset
	if err != nil || json.unmarshal(bytes, &data, allocator = context.temp_allocator) != nil ||
		data.version != 1 || data.group != p.name {
		parameter_error(p, "Invalid preset or different shader group")
		return false
	}
	values := mat.values_make(p.live)
	defer mat.values_dispose(values)
	directory, _ := filepath.abs(filepath.dir(path), context.temp_allocator)
	seen := make(map[string]bool, context.temp_allocator)
	for saved in data.fields {
		if seen[saved.id] {
			parameter_error(p, "Duplicate field ID in preset")
			return false
		}
		seen[saved.id] = true
		for f, i in p.live.fields {
			if f.id != saved.id do continue
			if f.kind != saved.kind {
				parameter_error(p, "Preset field type differs from current shader")
				return false
			}
			values[i].number = saved.number
			delete(values[i].texture)
			texture := saved.texture
			if texture != "" && !filepath.is_abs(texture) do texture = fmt.tprintf("%s/%s", directory, texture)
			values[i].texture = strings.clone(texture)
		}
	}
	return values_apply(s, index, values)
}
