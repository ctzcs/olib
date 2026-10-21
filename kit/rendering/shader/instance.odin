package shader

// 对象材质实例拥有参数和贴图路径；Shader 定义与 GPU 资源由资源管理器共享。
import "core:encoding/json"
import "core:strings"

Instance_Group :: struct {
	schema: Schema,
	values: []Value,
}
Instance :: struct {
	shader: string,
	groups: []Instance_Group,
}
Instance_Resource :: struct {
	version: int,
	shader: string `json:"effect"`, // 文件里的键仍是 "effect"
	groups: []Resource,
}

instance_dispose :: proc(instance: ^Instance) {
	for &group in instance.groups {
		values_dispose(group.values)
		schema_dispose(&group.schema)
	}
	delete(instance.groups)
	delete(instance.shader)
	instance^ = {}
}

instance_make :: proc(shader: Shader_Desc, schemas: []Schema) -> (Instance, string) {
	order, reason := shader_order(shader, schemas)
	defer delete(order)
	if reason != "" do return {}, reason
	if !shader_is_material(shader) do return {}, "Material instance requires Model or Sprite passes"
	groups := make([dynamic]Instance_Group)
	for p in shader.passes {
		found := false
		for group in groups do found = found || group.schema.name == string(p.params)
		if found do continue
		for schema in schemas {
			if schema.name != string(p.params) do continue
			append(&groups, Instance_Group{schema_clone(schema), values_make(schema)})
		}
	}
	result := Instance{strings.clone(shader.name), make([]Instance_Group, len(groups))}
	copy(result.groups, groups[:])
	delete(groups)
	return result, ""
}

// Decode 成功才交给调用方替换；缺少的新组/字段保留默认值。
instance_decode :: proc(shader: Shader_Desc, schemas: []Schema, bytes: []u8) -> (Instance, string) {
	if len(bytes) > MAX_RESOURCE_BYTES do return {}, "Material resource exceeds 1 MiB"
	resource: Instance_Resource
	if json.unmarshal(bytes, &resource, allocator = context.temp_allocator) != nil do return {}, "Invalid material JSON"
	if resource.version != 2 || resource.shader != shader.name do return {}, "Material version or shader differs"
	result, reason := instance_make(shader, schemas)
	if reason != "" do return {}, reason
	for saved, i in resource.groups {
		for prior in resource.groups[:i] {
			if prior.group == saved.group {
				instance_dispose(&result)
				return {}, "Duplicate material group"
			}
		}
		found := false
		for &group in result.groups {
			if group.schema.name != saved.group do continue
			found = true
			values, error := values_overlay(group.schema, group.values, saved.fields)
			if error != "" || saved.version != 1 {
				values_dispose(values)
				instance_dispose(&result)
				return {}, error != "" ? error : "Invalid material group version"
			}
			values_dispose(group.values)
			group.values = values
		}
		if !found {
			instance_dispose(&result)
			return {}, "Unknown material group"
		}
	}
	return result, ""
}

instance_encode :: proc(instance: Instance) -> ([]u8, string) {
	if instance.shader == "" || len(instance.groups) == 0 || len(instance.groups) > MAX_PASSES do return nil, "Invalid material instance"
	resource := Instance_Resource{version = 2, shader = instance.shader,
		groups = make([]Resource, len(instance.groups), context.temp_allocator)}
	for group, i in instance.groups {
		for prior in instance.groups[:i] {
			if prior.schema.name == group.schema.name do return nil, "Duplicate material group"
		}
		bytes, reason := resource_encode(group.schema, group.values)
		defer delete(bytes)
		if reason != "" do return nil, reason
		if json.unmarshal(bytes, &resource.groups[i], allocator = context.temp_allocator) != nil do return nil, "Cannot encode material group"
	}
	bytes, err := json.marshal(resource, {pretty = true})
	if err != nil do return nil, "Cannot encode material instance"
	return bytes, ""
}
