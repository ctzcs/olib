#+build !js
package shader_lab

// ShaderLab 的文件路径适配；数据编解码交给 material，读取与原子保存统一交给 Storage。
// 分区：预设文件 / Storage 保存 / 整材质文件。
import "core:fmt"
import "core:path/filepath"
import "core:strings"

import foster "olib:foster"
import sh "olib:kit/rendering/shader"

@(private)
preset_file_load :: proc(schema: sh.Schema, path: string) -> ([]sh.Value, string) {
	storage := foster.StorageContainer{Root = filepath.dir(path)}
	bytes := foster.ReadAllBytes(&storage, filepath.base(path), context.temp_allocator)
	if len(bytes) == 0 do return nil, fmt.tprintf("%s: cannot read material or file is empty", path)
	values, reason := sh.resource_decode(schema, bytes)
	if reason != "" do return nil, fmt.tprintf("%s: %s", path, reason)
	directory, _ := filepath.abs(filepath.dir(path), context.temp_allocator)
	for &value, i in values {
		if schema.fields[i].kind != .Texture || value.texture == "" do continue
		if !filepath.is_abs(value.texture) {
			joined := fmt.aprintf("%s/%s", directory, value.texture)
			delete(value.texture)
			value.texture = joined
		}
	}
	return values, ""
}

// 同目录临时文件完成后才替换；失败保留旧文件。texture_root 指定输入相对贴图的根。
@(private)
preset_file_save :: proc(schema: sh.Schema, values: []sh.Value, path: string, texture_root := "") -> string {
	if path == "" do return "Empty material path"
	checked, check_error := sh.resource_encode(schema, values)
	delete(checked)
	if check_error != "" do return check_error
	owned := sh.values_make(schema, schema, values)
	defer sh.values_dispose(owned)
	directory, _ := filepath.abs(filepath.dir(path), context.temp_allocator)
	for &value, i in owned {
		if schema.fields[i].kind != .Texture || value.texture == "" do continue
		texture := value.texture
		if !filepath.is_abs(texture) && texture_root != "" {
			texture = fmt.tprintf("%s/%s", texture_root, texture)
		}
		absolute, _ := filepath.abs(texture, context.temp_allocator)
		relative, err := filepath.rel(directory, absolute, context.temp_allocator)
		delete(value.texture)
		value.texture = strings.clone(err == nil ? relative : absolute)
	}
	bytes, reason := sh.resource_encode(schema, owned)
	defer delete(bytes)
	if reason != "" do return reason
	return material_file_write(path, bytes)
}

@(private)
material_file_write :: proc(path: string, bytes: []u8) -> string {
	storage := foster.StorageContainer{Root = filepath.dir(path), Writable = true}
	if !foster.WriteAllBytesAtomic(&storage, filepath.base(path), bytes) {
		return "Cannot save material; previous file retained"
	}
	return ""
}

@(private)
material_file_load :: proc(effect: sh.Shader_Desc, schemas: []sh.Schema, path: string) -> (sh.Instance, string) {
	storage := foster.StorageContainer{Root = filepath.dir(path)}
	bytes := foster.ReadAllBytes(&storage, filepath.base(path), context.temp_allocator)
	if len(bytes) == 0 do return {}, "Cannot read material instance or file is empty"
	result, reason := sh.instance_decode(effect, schemas, bytes)
	if reason != "" do return {}, reason
	directory, _ := filepath.abs(filepath.dir(path), context.temp_allocator)
	for &group in result.groups {
		for &value, i in group.values {
			if group.schema.fields[i].kind != .Texture || value.texture == "" || filepath.is_abs(value.texture) do continue
			joined := fmt.aprintf("%s/%s", directory, value.texture)
			delete(value.texture)
			value.texture = joined
		}
	}
	return result, ""
}

@(private)
material_file_save :: proc(instance: sh.Instance, path: string, texture_root := "") -> string {
	if path == "" do return "Empty material path"
	checked, check_error := sh.instance_encode(instance)
	delete(checked)
	if check_error != "" do return check_error
	// 临时副本只借用 sh.Schema，独立拥有 sh.Value；不改调用方的路径。
	copy_instance := sh.Instance{instance.effect, make([]sh.Instance_Group, len(instance.groups))}
	defer delete(copy_instance.groups)
	defer for group in copy_instance.groups do sh.values_dispose(group.values)
	directory, _ := filepath.abs(filepath.dir(path), context.temp_allocator)
	for group, i in instance.groups {
		if len(group.values) != len(group.schema.fields) do return "Material value count differs from schema"
		copy_instance.groups[i] = {group.schema, sh.values_make(group.schema, group.schema, group.values)}
		for &value, j in copy_instance.groups[i].values {
			if group.schema.fields[j].kind != .Texture || value.texture == "" do continue
			texture := value.texture
			if !filepath.is_abs(texture) && texture_root != "" do texture = fmt.tprintf("%s/%s", texture_root, texture)
			absolute, _ := filepath.abs(texture, context.temp_allocator)
			relative, err := filepath.rel(directory, absolute, context.temp_allocator)
			delete(value.texture)
			value.texture = strings.clone(err == nil ? relative : absolute)
		}
	}
	bytes, reason := sh.instance_encode(copy_instance)
	defer delete(bytes)
	if reason != "" do return reason
	return material_file_write(path, bytes)
}
