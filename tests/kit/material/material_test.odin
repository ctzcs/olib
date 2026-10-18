#+test
package material

import "core:mem"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:testing"

@(test)
pass_graph_orders_current_dependencies_and_owns_nested_data :: proc(t: ^testing.T) {
	schemas := []Schema{{name = "Image", preview = "2d", fields = []Field{{id = "source", kind = .Texture}}}}
	e := Effect_Desc{name = "Trail", output = "result", passes = []Pass_Desc{
		{id = "final", params = "Image", output = "result", inputs = {{field = "source", target = "scene"}}},
		{id = "seed", params = "Image", output = "scene", inputs = {{field = "source", target = "result", frame = .Previous}}},
	}}
	order, error := effect_order(e, schemas)
	defer delete(order)
	testing.expect(t, error == "" && len(order) == 2 && order[0] == 1 && order[1] == 0)
	owned := effect_clone(e)
	defer effect_dispose(&owned)
	testing.expect(t, raw_data(owned.passes[0].inputs) != raw_data(e.passes[0].inputs))
	owned.passes[1].inputs[0].frame = .Current
	bad, cycle := effect_order(owned, schemas)
	defer delete(bad)
	testing.expect(t, len(bad) == 0 && strings.contains(cycle, "cycle"))
	owned.passes[1].inputs[0].frame = .Previous
	delete(string(owned.passes[0].inputs[0].field))
	owned.passes[0].inputs[0].field = Field_Ref(strings.clone("missing"))
	missing_order, missing := effect_order(owned, schemas)
	defer delete(missing_order)
	testing.expect(t, strings.contains(missing, "Texture field"))
	testing.expect(t, e.passes[0].inputs[0].field == "source" && e.passes[1].inputs[0].frame == .Previous)
}

@(test)
migrate_ids_and_pack_independent_gpu_slots :: proc(t: ^testing.T) {
	before := Schema{fields = []Field{
		{id = "strength", name = "old_name", kind = .Scalar, maximum = 5, initial = {2, 0, 0, 0}},
		{id = "image", name = "image", kind = .Texture, texture = "old.png"},
		{id = "color", name = "color", kind = .Color, maximum = 1, initial = {1, 0.5, 0.25, 1}},
	}}
	previous := values_make(before)
	defer values_dispose(previous)
	after := Schema{fields = []Field{
		{id = "color", name = "tint", kind = .Color, maximum = 1},
		{id = "image", name = "albedo", kind = .Texture},
		{id = "strength", name = "strength", kind = .Scalar, maximum = 1},
		{id = "new", name = "offset", kind = .Vector2, minimum = -1, maximum = 1, initial = {0.2, -0.5, 0, 0}},
	}}
	values := values_make(after, before, previous)
	defer values_dispose(values)
	testing.expect(t, values[0].number == previous[2].number)
	testing.expect(t, values[1].texture == "old.png" && raw_data(values[1].texture) != raw_data(previous[1].texture))
	testing.expect(t, values[2].number[0] == 1 && values[3].number[1] == -0.5)
	bytes: [48]u8
	testing.expect(t, uniform_size(after) == 48 && texture_count(after) == 1)
	testing.expect(t, pack(after, values, bytes[:]))
	slots: [3][4]f32
	mem.copy(&slots, raw_data(bytes[:]), 48)
	testing.expect(t, slots[0] == values[0].number && slots[1][0] == 1 && slots[2][1] == -0.5)
	testing.expect(t, !pack(after, values, bytes[:16]))
	text := hlsl(after)
	defer delete(text)
	testing.expect(t, strings.contains(text, "Texture2D _albedo : register(t0, space2)"))
	testing.expect(t, strings.contains(text, "#define _offset (_olib_param_2.xy)"))
}

@(test)
changed_type_uses_defaults :: proc(t: ^testing.T) {
	old := Schema{fields = []Field{{id = "value", kind = .Scalar, maximum = 5, initial = {3, 0, 0, 0}}}}
	next := Schema{fields = []Field{{id = "value", kind = .Vector3, maximum = 1, initial = {0.1, 0.2, 0.3, 0}}}}
	previous := values_make(old)
	defer values_dispose(previous)
	values := values_make(next, old, previous)
	defer values_dispose(values)
	testing.expect(t, values[0].number == next.fields[0].initial)
}


@(test)
resource_roundtrip_isolation_validation_and_atomic_file :: proc(t: ^testing.T) {
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	defer mem.tracking_allocator_destroy(&track)
	context.allocator = mem.tracking_allocator(&track)
	defer testing.expect_value(t, len(track.allocation_map), 0)
	Params :: struct {
		metallic: Scalar,
		color: Color,
		image: Texture_Path,
	}
	schema, reason := describe("Standard", "surface.hlsl", "3d", Params{color = {1,1,1,1}})
	defer schema_dispose(&schema)
	testing.expect_value(t, reason, "")
	base := values_make(schema)
	defer values_dispose(base)
	base[0].number[0] = 0.7
	changed, error := values_overlay(schema, base,
		{{id = "color", kind = .Color, number = {0.1,0.8,0.3,1}}})
	defer values_dispose(changed)
	testing.expect(t, error == "" && base[1].number[0] == 1 && changed[1].number[0] == 0.1)
	bytes, encode_error := resource_encode(schema, changed)
	defer delete(bytes)
	loaded, decode_error := resource_decode(schema, bytes)
	defer values_dispose(loaded)
	testing.expect(t, encode_error == "" && decode_error == "" && loaded[0].number[0] == 0.7)
	packed: [32]u8
	testing.expect(t, pack(schema, loaded, packed[:]))
	for bad in ([]string{
		"broken", `{"version":2,"group":"Standard"}`, `{"version":1,"group":"Other"}`,
		`{"version":1,"group":"Standard","fields":[{"id":"metallic","kind":"Scalar","number":[2,0,0,0]}]}`,
		`{"version":1,"group":"Standard","fields":[{"id":"metallic"},{"id":"metallic"}]}`,
	}) {
		invalid, message := resource_decode(schema, transmute([]u8)bad)
		testing.expect(t, invalid == nil && message != "")
	}
	directory, dir_err := os.make_directory_temp("", "olib_material_", context.allocator)
	testing.expect(t, dir_err == nil)
	defer delete(directory)
	defer _ = os.remove(directory)
	path := fmt.tprintf("%s/material.json", directory)
	defer _ = os.remove(path)
	testing.expect_value(t, resource_save(schema, changed, path), "")
	file_values, file_error := resource_load(schema, path)
	defer values_dispose(file_values)
	testing.expect(t, file_error == "" && file_values[1].number == changed[1].number)
	changed[0].number[0] = 5
	testing.expect(t, resource_save(schema, changed, path) != "")
	again, again_error := resource_load(schema, path)
	defer values_dispose(again)
	testing.expect(t, again_error == "" && again[0].number[0] == 0.7)
	missing, missing_error := resource_load(schema, fmt.tprintf("%s-missing", path))
	testing.expect(t, missing == nil && missing_error != "")
}
