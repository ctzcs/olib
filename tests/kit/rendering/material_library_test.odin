#+test
package rendering

import "core:testing"

import foster "olib:foster"
import mat "olib:kit/material"

// Pass 选择在提交前完成；不存在的 ID 不能退回“全部”。
@(test)
material_pass_selection_preserves_order_and_disabled_flags :: proc(t: ^testing.T) {
	effect := mat.Effect_Desc{passes = {
		{id = "shadow"}, {id = "body"}, {id = "outline", disabled = true},
	}}
	indices: [32]int
	count, ok := material_pass_indices(effect, {}, &indices)
	testing.expect(t, ok && count == 2 && indices[0] == 0 && indices[1] == 1)
	count, ok = material_pass_indices(effect, {pass_id = "body"}, &indices)
	testing.expect(t, ok && count == 1 && indices[0] == 1)
	count, ok = material_pass_indices(effect, {pass_id = "missing"}, &indices)
	testing.expect(t, !ok && count == 0)
	count, ok = material_pass_indices(effect, {pass_id = "outline"}, &indices)
	testing.expect(t, ok && count == 0)
	count, ok = material_pass_indices(effect, {
		pass_id = "outline", enabled = []bool{true, true, true},
	}, &indices)
	testing.expect(t, ok && count == 1 && indices[0] == 2)
	count, ok = material_pass_indices(effect, {pass_id = "body", pass_limit = 1}, &indices)
	testing.expect(t, ok && count == 0)
	_, ok = material_pass_indices(effect, {enabled = []bool{true}}, &indices)
	testing.expect(t, !ok)
}

// CPU 侧检查真实合批输入与快照，不创建窗口或伪造 GPU 句柄。
@(test)
sprite_batch_preserves_geometry_and_material_snapshot :: proc(t: ^testing.T) {
	renderer: Sprite_Renderer
	defer delete(renderer.vertices)
	defer delete(renderer.indices)
	defer foster.MaterialDispose(&renderer.batch_material)
	source: foster.Material
	foster.MaterialInit(&source)
	defer foster.MaterialDispose(&source)
	uniform := [4]u8{1, 2, 3, 4}
	foster.MaterialStageSetUniformBuffer(&source.Fragment, uniform[:])
	texture: foster.Texture
	source.Fragment.Samplers[0] = {&texture, foster.TextureSamplerMake(.Linear, .Clamp)}
	command: foster.DrawCommand
	foster.DrawCommandInit(&command)
	command.Material = &source
	command.Target = {WidthInPixels = 800, HeightInPixels = 600}
	first := Sprite_Submission{renderer = &renderer, vertices = {
		{{0, 0}, {0, 0}}, {{10, 0}, {0.5, 0}}, {{10, 10}, {0.5, 1}}, {{0, 10}, {0, 1}},
	}}
	sprite_batch_submit(&first, 0, &command)
	// 不同 Material 地址但 GPU 输入相同，也应合批。
	other := foster.MaterialClone(&source)
	defer foster.MaterialDispose(&other)
	command.Material = &other
	second := first
	for &vertex in second.vertices do vertex.position.x += 20
	sprite_batch_submit(&second, 0, &command)
	testing.expect(t, renderer.sprite_passes == 2 && renderer.draw_calls == 0)
	testing.expect(t, len(renderer.vertices) == 8 && len(renderer.indices) == 12)
	testing.expect_value(t, renderer.vertices[0].position, [2]f32{0, 0})
	testing.expect_value(t, renderer.vertices[4].position, [2]f32{20, 0})
	testing.expect_value(t, renderer.vertices[6].uv, [2]f32{0.5, 1})
	for value, i in ([12]u32{0, 1, 2, 0, 2, 3, 4, 5, 6, 4, 6, 7}) {
		testing.expect_value(t, renderer.indices[i], value)
	}
	testing.expect(t, sprite_batch_matches(&renderer, renderer.batch_state, &other))
	uniform[0] = 9
	foster.MaterialStageSetUniformBuffer(&other.Fragment, uniform[:])
	testing.expect(t, !sprite_batch_matches(&renderer, renderer.batch_state, &other))
	testing.expect_value(t, foster.MaterialStageGetUniformBuffer(&renderer.batch_material.Fragment)[0], 1)
	foster.MaterialCopyTo(&source, &other)
	other.Fragment.Samplers[0].Texture = nil
	testing.expect(t, !sprite_batch_matches(&renderer, renderer.batch_state, &other))
	state := renderer.batch_state
	state.depth_write = !state.depth_write
	testing.expect(t, !sprite_batch_matches(&renderer, state, &source))
	state = renderer.batch_state
	state.target.WidthInPixels += 1
	testing.expect(t, !sprite_batch_matches(&renderer, state, &source))
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
	defer materials_dispose(&library)
	schemas := []mat.Schema{
		{name = "Outline", preview = "3d"},
		{name = "Body", preview = "3d", fields = {{id = "amount", kind = .Scalar, maximum = 1}}},
	}
	effect := mat.Effect_Desc{name = "Outlined", output = "color", passes = []mat.Pass_Desc{
		{id = "body", params = "Body", draw = .Model, output = "color"},
		{id = "outline", params = "Outline", draw = .Model, output = "color"},
	}}
	code := []Material_Shader_Code{{[]u8{1}, []u8{2}}, {[]u8{3}, []u8{4}}}
	testing.expect_value(t, materials_register(&library, effect, schemas, code), "")
	testing.expect(t, materials_register(&library, effect, schemas, code) != "")
	testing.expect_value(t, len(library.effects), 1)
	a, selected, reason := material_read(&library, "materials/left.json")
	defer mat.instance_dispose(&a)
	b, _, second_error := material_read(&library, "materials/left.json")
	defer mat.instance_dispose(&b)
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
