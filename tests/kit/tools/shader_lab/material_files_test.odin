#+build !js
#+test
package shader_lab

// 从 material 迁入的文件读写测试；不创建窗口或 GPU，编解码测试仍留在 material。
import "core:fmt"
import "core:mem"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"

import fx "olib:kit/rendering/shader/effect"

@(test)
preset_file_roundtrip_and_failed_save_retains_previous :: proc(t: ^testing.T) {
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	defer mem.tracking_allocator_destroy(&track)
	context.allocator = mem.tracking_allocator(&track)
	defer testing.expect_value(t, len(track.allocation_map), 0)
	schema := fx.Schema{name = "Surface", fields = {
		{id = "amount", kind = .Scalar, maximum = 1, initial = {0.7, 0, 0, 0}},
		{id = "image", kind = .Texture, texture = "edge.png"},
	}}
	values := fx.values_make(schema)
	defer fx.values_dispose(values)
	directory, dir_error := os.make_directory_temp("", "olib_shader_lab_", context.allocator)
	if !testing.expect(t, dir_error == nil) do return
	defer delete(directory)
	defer _ = os.remove(directory)
	path := fmt.tprintf("%s/preset.json", directory)
	defer _ = os.remove(path)
	testing.expect_value(t, preset_file_save(schema, values, path, directory), "")
	loaded, load_error := preset_file_load(schema, path)
	defer fx.values_dispose(loaded)
	if !testing.expect(t, load_error == "") do return
	testing.expect_value(t, loaded[0].number[0], 0.7)
	testing.expect(t, filepath.is_abs(loaded[1].texture) && strings.contains(loaded[1].texture, directory))
	testing.expect_value(t, values[1].texture, "edge.png")
	values[0].number[0] = 5
	testing.expect(t, preset_file_save(schema, values, path, directory) != "")
	retained, retained_error := preset_file_load(schema, path)
	defer fx.values_dispose(retained)
	testing.expect(t, retained_error == "" && retained[0].number[0] == 0.7)
	missing, missing_error := preset_file_load(schema, fmt.tprintf("%s-missing", path))
	testing.expect(t, missing == nil && missing_error != "")
}

@(test)
material_file_roundtrip_and_failed_save_retains_previous :: proc(t: ^testing.T) {
	schemas := []fx.Schema{
		{name = "Body", preview = "3d", fields = {{id = "amount", kind = .Scalar, maximum = 1}}},
		{name = "Outline", preview = "3d", fields = {{id = "image", kind = .Texture, texture = "edge.png"}}},
	}
	effect := fx.Effect_Desc{name = "Outlined", output = "color", passes = {
		{id = "body", draw = .Model, output = "color", params = "Body"},
		{id = "outline", draw = .Model, output = "color", params = "Outline"},
	}}
	instance, reason := fx.instance_make(effect, schemas)
	defer fx.instance_dispose(&instance)
	if !testing.expect_value(t, reason, "") do return
	instance.groups[0].values[0].number[0] = 0.75
	directory, dir_error := os.make_directory_temp("", "olib_shader_lab_", context.allocator)
	if !testing.expect(t, dir_error == nil) do return
	defer delete(directory)
	defer _ = os.remove(directory)
	path := fmt.tprintf("%s/material.json", directory)
	defer _ = os.remove(path)
	testing.expect_value(t, material_file_save(instance, path, directory), "")
	loaded, load_error := material_file_load(effect, schemas, path)
	defer fx.instance_dispose(&loaded)
	if !testing.expect(t, load_error == "") do return
	testing.expect_value(t, loaded.groups[0].values[0].number[0], 0.75)
	testing.expect(t, filepath.is_abs(loaded.groups[1].values[0].texture) &&
		strings.contains(loaded.groups[1].values[0].texture, directory))
	testing.expect_value(t, instance.groups[1].values[0].texture, "edge.png")
	instance.groups[0].values[0].number[0] = 5
	testing.expect(t, material_file_save(instance, path, directory) != "")
	retained, retained_error := material_file_load(effect, schemas, path)
	defer fx.instance_dispose(&retained)
	testing.expect(t, retained_error == "" && retained.groups[0].values[0].number[0] == 0.75)
}
