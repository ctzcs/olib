package paramgen

// 单个项目生成程序的反射端；默认值由真实 Odin 代码求值，不解析表达式。
import "core:encoding/json"
import "core:fmt"
import "core:math"
import "core:mem"
import "core:os"
import "core:reflect"
import "core:strconv"
import "core:strings"

import mat "olib:kit/material"

// 仅接受能直接生成 HLSL 标识符的字段名。稳定 id 标签可以不同于字段名。
identifier :: proc(name: string) -> bool {
	if len(name) == 0 || strings.has_prefix(name, "_olib_") do return false
	for c, i in name {
		if (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_' do continue
		if i > 0 && c >= '0' && c <= '9' do continue
		return false
	}
	return true
}

describe :: proc(name: string, shader: mat.Shader_Path, preview: string, defaults: any) -> (schema: mat.Schema, error: string) {
	schema = {name = name, shader = string(shader), preview = preview}
	if shader == "" || (preview != "2d" && preview != "3d") {
		return {}, "Shader path is required; Preview must be 2d or 3d"
	}
	fields := reflect.struct_fields_zipped(defaults.id)
	if len(fields) == 0 do return {}, "Params must be a non-empty struct"
	schema.fields = make([]mat.Field, len(fields))
	for field, i in fields {
		f := &schema.fields[i]
		f.name = field.name
		f.id = reflect.struct_tag_get(field.tag, "id")
		if f.id == "" do f.id = f.name
		f.label = reflect.struct_tag_get(field.tag, "label")
		if f.label == "" do f.label = f.name
		if !identifier(f.name) do return {}, fmt.aprintf("%s: invalid HLSL field name", f.name)
		for previous in schema.fields[:i] {
			if previous.id == f.id do return {}, fmt.aprintf("%s: duplicate field id", f.id)
		}
		pointer := mem.ptr_offset(cast(^u8)defaults.data, int(field.offset))
		control := reflect.struct_tag_get(field.tag, "ui")
		expected_control: string
		implicit_control := false
		switch field.type.id {
		case f32, mat.Scalar:
			f.kind = .Scalar
			f.initial[0] = (cast(^f32)pointer)^
			expected_control = "slider"
			implicit_control = field.type.id == mat.Scalar
		case [2]f32, mat.Vector2:
			f.kind = .Vector2
			mem.copy(&f.initial, pointer, 8)
			expected_control = "vector"
			implicit_control = field.type.id == mat.Vector2
		case [3]f32, mat.Vector3:
			f.kind = .Vector3
			mem.copy(&f.initial, pointer, 12)
			expected_control = "vector"
			implicit_control = field.type.id == mat.Vector3
		case [4]f32, mat.Color:
			f.kind = .Color
			f.initial = (cast(^[4]f32)pointer)^
			expected_control = "color"
			implicit_control = field.type.id == mat.Color
		case string, mat.Texture_Path:
			f.kind = .Texture
			f.texture = (cast(^string)pointer)^
			expected_control = "texture"
			implicit_control = field.type.id == mat.Texture_Path
		case:
			return {}, fmt.aprintf("%s: unsupported parameter type %v", f.name, field.type.id)
		}
		if control != expected_control && !(implicit_control && control == "") {
			return {}, fmt.aprintf("%s: %v requires ui:%s%s", f.name, field.type.id,
				expected_control, implicit_control ? " (ui may be omitted)" : "")
		}
		f.minimum = 0
		f.maximum = 1
		f.step = 0.01
		for key, k in ([3]string{"min", "max", "step"}) {
			text, found := reflect.struct_tag_lookup(field.tag, key)
			if !found do continue
			value, ok := strconv.parse_f32(text)
			if !ok || math.is_nan(value) || math.is_inf(value) do return {}, fmt.aprintf("%s: invalid %s", f.name, key)
			switch k {
			case 0: f.minimum = value
			case 1: f.maximum = value
			case 2: f.step = value
			}
		}
		if f.maximum <= f.minimum || f.step <= 0 do return {}, fmt.aprintf("%s: invalid range/step", f.name)
		for c in 0..<mat.components(f.kind) {
			value := f.initial[c]
			if math.is_nan(value) || math.is_inf(value) || value < f.minimum || value > f.maximum {
				return {}, fmt.aprintf("%s: default outside range", f.name)
			}
		}
	}
	if mat.texture_count(schema) > 16 || mat.uniform_size(schema) > 16384 {
		return {}, "Parameters exceed GPU binding limits"
	}
	return schema, ""
}

// 生成入口在整个包内逐个调用，最终一次输出。错误终止，不发布部分参数描述。
add :: proc(schemas: ^[dynamic]mat.Schema, name: string, shader: mat.Shader_Path, preview: string, defaults: $T, label: string = "", folder: string = "") {
	schema, error := describe(name, shader, preview, defaults)
	schema.label = label
	schema.folder = folder
	if error != "" {
		fmt.eprintfln("%s: %s", name, error)
		os.exit(1)
	}
	for other in schemas {
		if other.shader == string(shader) {
			fmt.eprintfln("%s and %s reference the same shader", name, other.name)
			os.exit(1)
		}
	}
	append(schemas, schema)
}

add_effect :: proc(effects: ^[dynamic]mat.Effect_Desc, name: string,
	passes: []mat.Pass_Desc, output: mat.Target_Ref, schemas: []mat.Schema, label: string = "", preview: string = "") {
	effect := mat.Effect_Desc{name = name, output = output, passes = passes, label = label, preview = preview}
	order, error := mat.effect_order(effect, schemas)
	delete(order)
	if error != "" {
		fmt.eprintfln("%s: %s", name, error)
		os.exit(1)
	}
	append(effects, effect)
}

// 声明使用枚举；保留旧声明的字符串输入，运行时清单格式不变。
preview_name :: proc {preview_name_enum, preview_name_string}

@(private)
preview_name_enum :: proc(mode: mat.Preview_Mode) -> string {
	switch mode {
	case .Auto: return ""
	case .Two_D: return "2d"
	case .Three_D: return "3d"
	}
	return "invalid"
}

@(private)
preview_name_string :: proc(mode: string) -> string {
	return mode
}

write :: proc(schemas: []mat.Schema, effects: []mat.Effect_Desc = nil) {
	data := struct {schemas: []mat.Schema, effects: []mat.Effect_Desc}{schemas, effects}
	bytes, err := json.marshal(data)
	if err != nil || len(os.args) != 2 {
		fmt.eprintln("Cannot encode parameter descriptions / missing output path")
		os.exit(1)
	}
	if os.write_entire_file(os.args[1], bytes) != nil do os.exit(1)
}
