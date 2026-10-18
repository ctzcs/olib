// Shader 参数描述与实例值。无文件系统或编辑器依赖；生成的布局不依赖 Odin 结构体内存布局。
package material

// 分区：描述 / 生命周期与迁移 / GPU 布局。
import "core:fmt"
import "core:math"
import "core:mem"
import "core:strings"

Kind :: enum {
	Scalar,
	Vector2,
	Vector3,
	Color,
	Texture,
}

Field :: struct {
	id, name, label: string,
	kind: Kind,
	minimum, maximum, step: f32,
	initial: [4]f32,
	texture: string,
}

Schema :: struct {
	name, shader, preview: string,
	label, folder: string, // 仅用于显示；name 仍是绑定和迁移的稳定 ID。
	fields: []Field,
}

// 每个数字参数占一个 float4 槽；Texture 单独编号，不占 uniform 空间。
Value :: struct {
	number: [4]f32,
	texture: string,
}

components :: proc(kind: Kind) -> int {
	switch kind {
	case .Scalar: return 1
	case .Vector2: return 2
	case .Vector3: return 3
	case .Color: return 4
	case .Texture: return 0
	}
	return 0
}

// ==============================================================================
// 生命周期与迁移：所有字符串和切片由调用方 allocator 持有
// ==============================================================================

schema_dispose :: proc(s: ^Schema) {
	delete(s.name)
	delete(s.shader)
	delete(s.preview)
	delete(s.label)
	delete(s.folder)
	for f in s.fields {
		delete(f.id)
		delete(f.name)
		delete(f.label)
		delete(f.texture)
	}
	delete(s.fields)
	s^ = {}
}

schema_clone :: proc(s: Schema) -> Schema {
	r := s
	r.name = strings.clone(s.name)
	r.shader = strings.clone(s.shader)
	r.preview = strings.clone(s.preview)
	r.label = strings.clone(s.label)
	r.folder = strings.clone(s.folder)
	r.fields = make([]Field, len(s.fields))
	for f, i in s.fields {
		r.fields[i] = f
		r.fields[i].id = strings.clone(f.id)
		r.fields[i].name = strings.clone(f.name)
		r.fields[i].label = strings.clone(f.label)
		r.fields[i].texture = strings.clone(f.texture)
	}
	return r
}

schema_equal :: proc(a, b: Schema) -> bool {
	if a.name != b.name || a.shader != b.shader || a.preview != b.preview || len(a.fields) != len(b.fields) do return false
	if a.label != b.label || a.folder != b.folder do return false
	for f, i in a.fields {
		if f != b.fields[i] do return false
	}
	return true
}

values_dispose :: proc(values: []Value) {
	for value in values do delete(value.texture)
	delete(values)
}

// 字段 ID + 类型相同才迁移；新增/变更类型取默认值，范围收窄时钳制旧值。
values_make :: proc(schema: Schema, old: Schema = {}, previous: []Value = nil) -> []Value {
	values := make([]Value, len(schema.fields))
	for f, i in schema.fields {
		v := Value{number = f.initial, texture = f.texture}
		for prior, j in old.fields {
			if j < len(previous) && prior.id == f.id && prior.kind == f.kind {
				v = previous[j]
				break
			}
		}
		for c in 0..<components(f.kind) {
			v.number[c] = math.clamp(v.number[c], f.minimum, f.maximum)
		}
		v.texture = strings.clone(v.texture)
		values[i] = v
	}
	return values
}

// ==============================================================================
// GPU 布局：fragment b1/space3；引擎公共输入保留 b0
// ==============================================================================

uniform_size :: proc(schema: Schema) -> int {
	count := 0
	for f in schema.fields do count += int(f.kind != .Texture)
	return max(1, count)*16
}

texture_count :: proc(schema: Schema) -> int {
	count := 0
	for f in schema.fields do count += int(f.kind == .Texture)
	return count
}

pack :: proc(schema: Schema, values: []Value, buffer: []u8) -> bool {
	if len(values) != len(schema.fields) || len(buffer) != uniform_size(schema) do return false
	mem.zero_slice(buffer)
	offset := 0
	for f, i in schema.fields {
		if f.kind == .Texture do continue
		mem.copy(raw_data(buffer[offset:]), raw_data(values[i].number[:]), 16)
		offset += 16
	}
	return true
}

// 返回的字符串归调用方；由编译器以 params.generated.hlsli 加入候选源码快照。
hlsl :: proc(schema: Schema) -> string {
	b: strings.Builder
	strings.builder_init(&b)
	strings.write_string(&b, "// Generated from Odin; do not edit.\ncbuffer MaterialParams : register(b1, space3) {\n")
	index := 0
	for f in schema.fields {
		if f.kind == .Texture do continue
		fmt.sbprintf(&b, "    float4 _olib_param_%d;\n", index)
		index += 1
	}
	if index == 0 do strings.write_string(&b, "    float4 _olib_unused;\n")
	strings.write_string(&b, "};\n")
	index = 0
	slot := 0
	for f in schema.fields {
		if f.kind == .Texture {
			fmt.sbprintf(&b, "Texture2D _%s : register(t%d, space2);\n", f.name, slot)
			fmt.sbprintf(&b, "SamplerState _%sSampler : register(s%d, space2);\n", f.name, slot)
			slot += 1
		} else {
			swizzles := [4]string{"x", "xy", "xyz", "xyzw"}
			fmt.sbprintf(&b, "#define _%s (_olib_param_%d.%s)\n", f.name, index, swizzles[components(f.kind)-1])
			index += 1
		}
	}
	return strings.to_string(b)
}
