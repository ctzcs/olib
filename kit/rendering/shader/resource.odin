package shader

// 材质资源复用 Schema/Value；字节编解码无编辑器或文件系统依赖。
// 分区：格式 / 校验与实例覆盖 / 字节编解码。
import "core:encoding/json"
import "core:fmt"
import "core:math"
import "core:strings"

// 单个材质文件的字节数与字段数上限，防止异常资源占满内存。
MAX_RESOURCE_BYTES :: 1024*1024
MAX_RESOURCE_FIELDS :: 256

Resource_Field :: struct {
	id: string,
	kind: Kind,
	number: [4]f32,
	texture: string,
}

// version=1 与既有 Shader Lab 预设兼容。group 是稳定 Schema.name，不是 HLSL 路径。
Resource :: struct {
	version: int,
	group: string,
	fields: []Resource_Field,
}

field_index :: proc(schema: Schema, id: string) -> int {
	for f, i in schema.fields {
		if f.id == id do return i
	}
	return -1
}

// 返回独立拥有的值；只按字段覆盖，不修改共享 base。失败返回 nil，原实例不变。
values_overlay :: proc(schema: Schema, base: []Value, fields: []Resource_Field) -> ([]Value, string) {
	if len(base) != len(schema.fields) do return nil, "Material value count differs from schema"
	if len(fields) > MAX_RESOURCE_FIELDS do return nil, "Too many material fields"
	for saved, i in fields {
		if saved.id == "" do return nil, "Empty material field ID"
		for prior in fields[:i] {
			if prior.id == saved.id do return nil, fmt.tprintf("Duplicate material field: %s", saved.id)
		}
		if saved.kind < .Scalar || saved.kind > .Texture do return nil, "Invalid material field kind"
		for number in saved.number {
			if math.is_nan(number) || math.is_inf(number) do return nil, "Non-finite material value"
		}
		j := field_index(schema, saved.id)
		if j < 0 do continue // 删除的字段忽略；新增字段由默认值提供。
		f := schema.fields[j]
		if f.kind != saved.kind do return nil, fmt.tprintf("Material field type differs: %s", f.id)
		for c in 0..<components(f.kind) {
			if saved.number[c] < f.minimum || saved.number[c] > f.maximum {
				return nil, fmt.tprintf("Material field out of range: %s", f.id)
			}
		}
	}
	result := values_make(schema, schema, base)
	for saved in fields {
		i := field_index(schema, saved.id)
		if i < 0 do continue
		delete(result[i].texture)
		result[i] = {saved.number, strings.clone(saved.texture)}
	}
	return result, ""
}

// 结果由调用方 context.allocator 持有；诊断字符串仅在本帧有效。
resource_decode :: proc(schema: Schema, bytes: []u8) -> ([]Value, string) {
	if len(bytes) > MAX_RESOURCE_BYTES do return nil, "Material resource exceeds 1 MiB"
	resource: Resource
	if json.unmarshal(bytes, &resource, allocator = context.temp_allocator) != nil {
		return nil, "Invalid material JSON"
	}
	if resource.version != 1 do return nil, "Unsupported material resource version"
	if resource.group != schema.name do return nil, "Material shader group differs from schema"
	defaults := values_make(schema)
	defer values_dispose(defaults)
	return values_overlay(schema, defaults, resource.fields)
}

// 返回拥有的 JSON 字节；贴图路径保持传入值，路径转换由资源宿主负责。
resource_encode :: proc(schema: Schema, values: []Value) -> ([]u8, string) {
	if len(values) != len(schema.fields) do return nil, "Material value count differs from schema"
	resource := Resource{version = 1, group = schema.name,
		fields = make([]Resource_Field, len(values), context.temp_allocator)}
	for f, i in schema.fields do resource.fields[i] = {f.id, f.kind, values[i].number, values[i].texture}
	validated, reason := values_overlay(schema, values, resource.fields)
	defer values_dispose(validated)
	if reason != "" do return nil, reason
	bytes, err := json.marshal(resource, {pretty = true})
	if err != nil do return nil, "Cannot encode material resource"
	return bytes, ""
}
