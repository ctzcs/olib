#+test
package material

import "core:testing"

import foster "olib:foster"

// Pass 选择在提交前完成；不存在的 ID 不能退回“全部”。
@(test)
material_pass_selection_preserves_order_and_disabled_flags :: proc(t: ^testing.T) {
	effect := Effect_Desc{passes = {
		{id = "shadow"}, {id = "body"}, {id = "outline", disabled = true},
	}}
	indices: [MAX_PASSES]int
	count, error := material_pass_indices(effect, {}, &indices)
	testing.expect(t, error == .None && count == 2 && indices[0] == 0 && indices[1] == 1)
	count, error = material_pass_indices(effect, {options = {pass_id = "body"}}, &indices)
	testing.expect(t, error == .None && count == 1 && indices[0] == 1)
	count, error = material_pass_indices(effect, {options = {pass_id = "missing"}}, &indices)
	testing.expect(t, error == .Unknown_Pass && count == 0)
	count, error = material_pass_indices(effect, {options = {pass_id = "outline"}}, &indices)
	testing.expect(t, error == .None && count == 0)
	count, error = material_pass_indices(effect, {
		options = {pass_id = "outline", enabled = []bool{true, true, true}},
	}, &indices)
	testing.expect(t, error == .None && count == 1 && indices[0] == 2)
	count, error = material_pass_indices(effect, {pass_limit = 1, options = {pass_id = "body"}}, &indices)
	testing.expect(t, error == .None && count == 0)
	_, error = material_pass_indices(effect, {options = {enabled = []bool{true}}}, &indices)
	testing.expect(t, error == .Bad_Pass_Selection)
}

// 用真实 StorageContainer 内存条目验证文件 -> 效果解析，不创建窗口或伪造 GPU。
@(test)
material_library_resolves_effect_and_preserves_failed_reload :: proc(t: ^testing.T) {
	entries := make(map[string][dynamic]u8)
	defer delete(entries)
	json := `{"version":2,"effect":"Outlined","groups":[{"version":1,"group":"Body","fields":[{"id":"amount","kind":"Scalar","number":[0.7,0,0,0]}]}]}`
	bytes := make([dynamic]u8)
	append(&bytes, ..transmute([]u8)json)
	defer delete(bytes)
	entries["materials/left.json"] = bytes
	storage := foster.StorageContainer{ZipEntries = &entries}
	library := Material_Library{storage = &storage}
	defer material_library_dispose(&library)
	schemas := []Schema{
		{name = "Outline", preview = "3d"},
		{name = "Body", preview = "3d", fields = {{id = "amount", kind = .Scalar, maximum = 1}}},
	}
	effect := Effect_Desc{name = "Outlined", output = "color", passes = []Pass_Desc{
		{id = "body", params = "Body", draw = .Model, output = "color"},
		{id = "outline", params = "Outline", draw = .Model, output = "color"},
	}}
	code := []Material_Shader_Code{{vertex = []u8{1}, fragment = []u8{2}}, {vertex = []u8{3}, fragment = []u8{4}}}
	testing.expect_value(t, material_register(&library, effect, schemas, code), "")
	testing.expect(t, material_register(&library, effect, schemas, code) != "")
	testing.expect_value(t, len(library.effects), 1)
	a, selected, reason := material_read(&library, "materials/left.json")
	defer instance_dispose(&a)
	b, _, second_error := material_read(&library, "materials/left.json")
	defer instance_dispose(&b)
	testing.expect(t, reason == "" && second_error == "" && selected == library.effects[0])
	testing.expect_value(t, a.groups[0].schema.name, "Body")
	testing.expect_value(t, a.groups[0].values[0].number[0], 0.7)
	// 借用实例只用于无 GPU 的参数/失败测试，清理由 a 的所有者完成。
	material := Material{owner = &library, effect = selected, instance = a}
	testing.expect(t, material_set_number(&material, "Body", "amount", {0.2, 0, 0, 0}))
	testing.expect_value(t, b.groups[0].values[0].number[0], 0.7)
	testing.expect(t, !material_set_number(&material, "Body", "amount", {2, 0, 0, 0}))
	testing.expect(t, !material_set_number(&material, "Body", "missing", {}))
	testing.expect(t, material_reload(&library, &material, "missing.json") != "")
	testing.expect_value(t, material.instance.groups[0].values[0].number[0], 0.2)
	testing.expect(t, material_reload(&library, &material, "materials/left.json") != "") // 无 device，不发布半份 GPU 资源。
	testing.expect_value(t, material.instance.groups[0].values[0].number[0], 0.2)
	failed, load_error := material_load(&library, "materials/left.json")
	testing.expect(t, failed == nil && load_error != "" && len(library.instances) == 0)
	name := selected.desc.name
	selected.desc.name = "Different"
	missing, _, unknown_error := material_read(&library, "materials/left.json")
	selected.desc.name = name
	testing.expect(t, unknown_error != "" && missing.groups == nil)
}

@(test)
material_texture_paths_are_relative_and_canonical :: proc(t: ^testing.T) {
	resolved, reason := material_path("materials/characters/hero.json", "..\\..\\textures/./cloth.png")
	testing.expect(t, reason == "" && resolved == "textures/cloth.png")
	other, other_error := material_path("materials/hero.json", "../textures/cloth.png")
	testing.expect(t, other_error == "" && other == resolved)
	for invalid in ([]string{"", "/absolute.png", "C:\\absolute.png"}) {
		_, error := material_path("materials/hero.json", invalid)
		testing.expect(t, error != "")
	}
}
