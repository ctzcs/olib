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
		if error = describe_field(f, field, defaults.data, schema.fields[:i]); error != "" do return {}, error
	}
	if texture_count(schema) > MAX_TEXTURES || uniform_size(schema) > MAX_UNIFORM_BYTES ||
		instance_count(schema) > MAX_INSTANCE_FIELDS {
		return {}, "Parameters exceed GPU binding limits"
	}
	return schema_clone(schema), ""
}

// 由一个结构体字段生成 Field：名字/ID/标签、类型与默认值、ui 控件匹配、范围标签。
@(private)
describe_field :: proc(f: ^Field, field: reflect.Struct_Field, base: rawptr, previous: []Field) -> string {
	f.name = field.name
	f.id = reflect.struct_tag_get(field.tag, "id")
	if f.id == "" do f.id = f.name
	f.label = reflect.struct_tag_get(field.tag, "label")
	if f.label == "" do f.label = f.name
	if !identifier(f.name) do return fmt.tprintf("%s: invalid HLSL field name", f.name)
	for prior in previous {
		if prior.id == f.id do return fmt.tprintf("%s: duplicate field id", f.id)
	}
	pointer := mem.ptr_offset(cast(^u8)base, int(field.offset))
	expected_control, implicit_control, supported := field_kind_read(f, field.type.id, pointer)
	if !supported do return fmt.tprintf("%s: unsupported parameter type %v", f.name, field.type.id)
	control := reflect.struct_tag_get(field.tag, "ui")
	if control != expected_control && !(implicit_control && control == "") {
		return fmt.tprintf("%s: %v requires ui:%s%s", f.name, field.type.id,
			expected_control, implicit_control ? " (ui may be omitted)" : "")
	}
	if reason := field_range_read(f, field.tag); reason != "" do return reason
	if reflect.struct_tag_get(field.tag, "instance") == "true" {
		if f.kind == .Texture do return fmt.tprintf("%s: Texture cannot be instance", f.name)
		f.instance = true
	}
	if reason := field_sampler_read(f, field.tag); reason != "" do return reason
	for c in 0..<components(f.kind) {
		value := f.initial[c]
		if math.is_nan(value) || math.is_inf(value) || value < f.minimum || value > f.maximum {
			return fmt.tprintf("%s: default outside range", f.name)
		}
	}
	return ""
}

// 按 Odin 类型决定 Kind，读出默认值。返回该类型要求的 ui 标签，以及专用类型是否允许省略 ui。
@(private)
field_kind_read :: proc(f: ^Field, type: typeid, pointer: rawptr) -> (control: string, implicit: bool, supported: bool) {
	switch type {
	case f32, Scalar:
		f.kind = .Scalar
		f.initial[0] = (cast(^f32)pointer)^
		return "slider", type == Scalar, true
	case [2]f32, Vector2:
		f.kind = .Vector2
		mem.copy(&f.initial, pointer, 8)
		return "vector", type == Vector2, true
	case [3]f32, Vector3:
		f.kind = .Vector3
		mem.copy(&f.initial, pointer, 12)
		return "vector", type == Vector3, true
	case [4]f32, Color:
		f.kind = .Color
		f.initial = (cast(^[4]f32)pointer)^
		return "color", type == Color, true
	case string, Texture_Path:
		f.kind = .Texture
		f.texture = (cast(^string)pointer)^
		return "texture", type == Texture_Path, true
	}
	return "", false, false
}

// 读取 min / max / step 标签（缺省 0..1、步长 0.01），并检查范围与步长有效。
@(private)
field_range_read :: proc(f: ^Field, tag: reflect.Struct_Tag) -> string {
	f.minimum = 0
	f.maximum = 1
	f.step = 0.01
	for key, k in ([3]string{"min", "max", "step"}) {
		text, found := reflect.struct_tag_lookup(tag, key)
		if !found do continue
		value, ok := strconv.parse_f32(text)
		if !ok || math.is_nan(value) || math.is_inf(value) do return fmt.tprintf("%s: invalid %s", f.name, key)
		switch k {
		case 0: f.minimum = value
		case 1: f.maximum = value
		case 2: f.step = value
		}
	}
	if f.maximum <= f.minimum || f.step <= 0 do return fmt.tprintf("%s: invalid range/step", f.name)
	return ""
}

// 读取贴图字段的 filter:"linear|nearest" 与 wrap:"clamp|repeat|mirror" 标签，缺省线性、钳制。
@(private)
field_sampler_read :: proc(f: ^Field, tag: reflect.Struct_Tag) -> string {
	filter, has_filter := reflect.struct_tag_lookup(tag, "filter")
	wrap, has_wrap := reflect.struct_tag_lookup(tag, "wrap")
	if !has_filter && !has_wrap do return ""
	if f.kind != .Texture do return fmt.tprintf("%s: filter/wrap apply only to textures", f.name)
	f.filter_declared, f.wrap_declared = has_filter, has_wrap
	if has_filter {
		switch filter {
		case "linear": f.filter = .Linear
		case "nearest": f.filter = .Nearest
		case: return fmt.tprintf("%s: filter must be linear or nearest", f.name)
		}
	}
	if has_wrap {
		switch wrap {
		case "clamp": f.wrap = .Clamp
		case "repeat": f.wrap = .Repeat
		case "mirror": f.wrap = .Mirror
		case: return fmt.tprintf("%s: wrap must be clamp, repeat or mirror", f.name)
		}
	}
	return ""
}
