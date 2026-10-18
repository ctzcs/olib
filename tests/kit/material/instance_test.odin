#+test
package material

import "core:testing"
import "core:strings"
import "core:fmt"
import "core:os"

@(test)
sprite_material_contract_and_roundtrip :: proc(t: ^testing.T) {
	schemas := []Schema{{name = "Sprite", preview = "2d", fields = {
		{id = "mask", kind = .Texture}, {id = "frame", kind = .Texture},
	}}}
	effect := Effect_Desc{name = "Sprite", output = "color", passes = []Pass_Desc{
		{id = "shadow", params = "Sprite", draw = .Sprite, output = "color", sprite_texture = "frame"},
		{id = "body", params = "Sprite", draw = .Sprite, output = "color", sprite_texture = "frame"},
	}}
	instance, reason := instance_make(effect, schemas)
	defer instance_dispose(&instance)
	testing.expect(t, reason == "" && len(instance.groups) == 1)
	bytes, encode_error := instance_encode(instance)
	defer delete(bytes)
	loaded, decode_error := instance_decode(effect, schemas, bytes)
	defer instance_dispose(&loaded)
	testing.expect(t, encode_error == "" && decode_error == "")
	copy := effect_clone(effect)
	defer effect_dispose(&copy)
	testing.expect_value(t, copy.passes[0].sprite_texture, "frame")
	for invalid in ([]Pass_Desc{
		{id = "body", params = "Sprite", draw = .Model, output = "color"},
		{id = "body", params = "Sprite", draw = .Fullscreen, output = "color"},
		{id = "body", params = "Sprite", draw = .Sprite, output = "color", sprite_texture = "missing"},
	}) {
		effect.passes[1] = invalid
		order, error := effect_order(effect, schemas)
		delete(order)
		testing.expect(t, error != "")
	}
	effect.passes[1] = effect.passes[0]
	effect.passes[1].id = "body"
	schemas[0].preview = "3d"
	order, error := effect_order(effect, schemas)
	delete(order)
	testing.expect(t, error != "")
}

@(test)
model_passes_share_depth_target_without_relaxing_image_graph :: proc(t: ^testing.T) {
	schemas := []Schema{{name = "Surface", preview = "3d"}}
	e := Effect_Desc{name = "Outline", output = "scene", passes = []Pass_Desc{
		{id = "body", params = "Surface", draw = .Model, output = "scene"},
		{id = "outline", params = "Surface", draw = .Model, output = "scene", state = {cull = .Front, depth_write = .Off}},
	}}
	order, reason := effect_order(e, schemas)
	defer delete(order)
	testing.expect(t, reason == "" && len(order) == 2 && order[0] == 0 && order[1] == 1)
	copy := effect_clone(e)
	defer effect_dispose(&copy)
	testing.expect_value(t, copy.passes[1].state.cull, .Front)
	copy.passes[1].draw = .Preview_Model
	bad, mix_error := effect_order(copy, schemas)
	delete(bad)
	testing.expect(t, mix_error != "")
	copy.passes[0].draw = .Preview_Model
	duplicate, duplicate_error := effect_order(copy, schemas)
	delete(duplicate)
	testing.expect(t, strings.contains(duplicate_error, "unique"))
	copy.passes[0].draw, copy.passes[1].draw = .Model, .Model
	copy.passes[1].target.samples = 4
	target, target_error := effect_order(copy, schemas)
	delete(target)
	testing.expect(t, target_error != "")
}

@(test)
model_instance_roundtrip_groups_and_reject_partial_decode :: proc(t: ^testing.T) {
	schemas := []Schema{
		{name = "Body", preview = "3d", fields = {{id = "amount", kind = .Scalar, maximum = 1, initial = {0.3,0,0,0}}}},
		{name = "Outline", preview = "3d", fields = {{id = "image", kind = .Texture, texture = "edge.png"}}},
	}
	e := Effect_Desc{name = "Outlined", output = "color", passes = []Pass_Desc{
		{id = "body", draw = .Model, output = "color", params = "Body"},
		{id = "outline", draw = .Model, output = "color", params = "Outline"},
	}}
	a, reason := instance_make(e, schemas)
	defer instance_dispose(&a)
	testing.expect_value(t, reason, "")
	a.groups[0].values[0].number[0] = 0.75
	bytes, encode_error := instance_encode(a)
	defer delete(bytes)
	b, decode_error := instance_decode(e, schemas, bytes)
	defer instance_dispose(&b)
	testing.expect(t, encode_error == "" && decode_error == "" && b.groups[0].values[0].number[0] == 0.75)
	b.groups[0].values[0].number[0] = 0.1
	testing.expect_value(t, a.groups[0].values[0].number[0], 0.75)
	// 整材质原子保存、相对贴图恢复、失败保留文件。
	directory, dir_error := os.make_directory_temp("", "olib_model_material_", context.allocator)
	testing.expect(t, dir_error == nil)
	defer delete(directory)
	defer _ = os.remove(directory)
	path := fmt.tprintf("%s/material.json", directory)
	defer _ = os.remove(path)
	testing.expect_value(t, instance_save(a, path, directory), "")
	loaded, load_error := instance_load(e, schemas, path)
	defer instance_dispose(&loaded)
	testing.expect(t, load_error == "" && loaded.groups[0].values[0].number[0] == 0.75)
	testing.expect(t, strings.contains(loaded.groups[1].values[0].texture, directory))
	a.groups[0].values[0].number[0] = 5
	testing.expect(t, instance_save(a, path, directory) != "")
	retained, retained_error := instance_load(e, schemas, path)
	defer instance_dispose(&retained)
	testing.expect(t, retained_error == "" && retained.groups[0].values[0].number[0] == 0.75)
	a.groups[0].values[0].number[0] = 0.75
	testing.expect(t, raw_data(b.groups[1].values[0].texture) != raw_data(a.groups[1].values[0].texture))
	for bad in ([]string{
		`{"version":2,"effect":"Other"}`,
		`{"version":2,"effect":"Outlined","groups":[{"version":1,"group":"Body"},{"version":1,"group":"Body"}]}`,
		`{"version":2,"effect":"Outlined","groups":[{"version":1,"group":"Body"},{"version":1,"group":"Outline","fields":[{"id":"image","kind":"Scalar"}]}]}`,
	}) {
		invalid, message := instance_decode(e, schemas, transmute([]u8)bad)
		testing.expect(t, invalid.groups == nil && message != "")
	}
	testing.expect_value(t, a.groups[0].values[0].number[0], 0.75)
}
