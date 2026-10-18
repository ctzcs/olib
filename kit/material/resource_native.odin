#+build !js
package material

// 桌面资源读写；Web/虚拟文件系统可用 resource_decode/encode 接自己的 IO。
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"

resource_load :: proc(schema: Schema, path: string) -> ([]Value, string) {
	bytes, err := os.read_entire_file(path, context.temp_allocator)
	if err != nil do return nil, fmt.tprintf("%s: cannot read material (%v)", path, err)
	values, reason := resource_decode(schema, bytes)
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
resource_save :: proc(schema: Schema, values: []Value, path: string, texture_root := "") -> string {
	if path == "" do return "Empty material path"
	checked, check_error := resource_encode(schema, values)
	delete(checked)
	if check_error != "" do return check_error
	owned := values_make(schema, schema, values)
	defer values_dispose(owned)
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
	bytes, reason := resource_encode(schema, owned)
	defer delete(bytes)
	if reason != "" do return reason
	return resource_write(path, bytes)
}

@(private)
resource_write :: proc(path: string, bytes: []u8) -> string {
	directory, _ := filepath.abs(filepath.dir(path), context.temp_allocator)
	if os.make_directory_all(directory) != nil do return "Cannot create material directory"
	file, err := os.create_temp_file(directory, ".material-*.tmp")
	if err != nil do return "Cannot stage material resource"
	temporary := strings.clone(os.name(file), context.temp_allocator)
	closed := false
	defer {
		if !closed do os.close(file)
		_ = os.remove(temporary)
	}
	written, write_err := os.write(file, bytes)
	if write_err != nil || written != len(bytes) do return "Cannot write complete material"
	if os.sync(file) != nil do return "Cannot sync material"
	close_err := os.close(file)
	closed = true
	if close_err != nil do return "Cannot close material"
	if os.rename(temporary, path) != nil do return "Cannot replace material; previous file retained"
	return ""
}

instance_load :: proc(effect: Effect_Desc, schemas: []Schema, path: string) -> (Instance, string) {
	bytes, err := os.read_entire_file(path, context.temp_allocator)
	if err != nil do return {}, "Cannot read material instance"
	result, reason := instance_decode(effect, schemas, bytes)
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

instance_save :: proc(instance: Instance, path: string, texture_root := "") -> string {
	if path == "" do return "Empty material path"
	checked, check_error := instance_encode(instance)
	delete(checked)
	if check_error != "" do return check_error
	// 临时副本只借用 Schema，独立拥有 Value；不改调用方的路径。
	copy_instance := Instance{instance.effect, make([]Instance_Group, len(instance.groups))}
	defer delete(copy_instance.groups)
	defer for group in copy_instance.groups do values_dispose(group.values)
	directory, _ := filepath.abs(filepath.dir(path), context.temp_allocator)
	for group, i in instance.groups {
		if len(group.values) != len(group.schema.fields) do return "Material value count differs from schema"
		copy_instance.groups[i] = {group.schema, values_make(group.schema, group.schema, group.values)}
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
	bytes, reason := instance_encode(copy_instance)
	defer delete(bytes)
	if reason != "" do return reason
	return resource_write(path, bytes)
}
