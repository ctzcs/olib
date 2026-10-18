package material

// 由已有参数声明反射构造 Schema，供开发生成器与运行时共用。
import "core:fmt"
import "core:math"
import "core:mem"
import "core:reflect"
import "core:strconv"
import "core:strings"

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

describe :: proc(name: string, shader: Shader_Path, preview: string, defaults: any) -> (schema: Schema, error: string) {
	schema = {name = name, shader = string(shader), preview = preview}
	if shader == "" || (preview != "2d" && preview != "3d") {
		return {}, "Shader path is required; Preview must be 2d or 3d"
	}
	fields := reflect.struct_fields_zipped(defaults.id)
	if len(fields) == 0 do return {}, "Params must be a non-empty struct"
	schema.fields = make([]Field, len(fields), context.temp_allocator)
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
		case f32, Scalar:
			f.kind = .Scalar
			f.initial[0] = (cast(^f32)pointer)^
			expected_control = "slider"
			implicit_control = field.type.id == Scalar
		case [2]f32, Vector2:
			f.kind = .Vector2
			mem.copy(&f.initial, pointer, 8)
			expected_control = "vector"
			implicit_control = field.type.id == Vector2
		case [3]f32, Vector3:
			f.kind = .Vector3
			mem.copy(&f.initial, pointer, 12)
			expected_control = "vector"
			implicit_control = field.type.id == Vector3
		case [4]f32, Color:
			f.kind = .Color
			f.initial = (cast(^[4]f32)pointer)^
			expected_control = "color"
			implicit_control = field.type.id == Color
		case string, Texture_Path:
			f.kind = .Texture
			f.texture = (cast(^string)pointer)^
			expected_control = "texture"
			implicit_control = field.type.id == Texture_Path
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
		for c in 0..<components(f.kind) {
			value := f.initial[c]
			if math.is_nan(value) || math.is_inf(value) || value < f.minimum || value > f.maximum {
				return {}, fmt.aprintf("%s: default outside range", f.name)
			}
		}
	}
	if texture_count(schema) > 16 || uniform_size(schema) > 16384 {
		return {}, "Parameters exceed GPU binding limits"
	}
	return schema_clone(schema), ""
}
