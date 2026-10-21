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
	count, error := material_pass_indices(effect, "", &indices)
	testing.expect(t, error == .None && count == 2 && indices[0] == 0 && indices[1] == 1)
	count, error = material_pass_indices(effect, "body", &indices)
	testing.expect(t, error == .None && count == 1 && indices[0] == 1)
	count, error = material_pass_indices(effect, "missing", &indices)
	testing.expect(t, error == .Unknown_Pass && count == 0)
	// 声明为 disabled 的 Pass 按 ID 选中也不画。
	count, error = material_pass_indices(effect, "outline", &indices)
	testing.expect(t, error == .None && count == 0)
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
	testing.expect_value(t, material.revision, 1) // 成功修改才递增，绘制器据此让快照过期
	testing.expect_value(t, b.groups[0].values[0].number[0], 0.7)
	testing.expect(t, !material_set_number(&material, "Body", "amount", {2, 0, 0, 0}))
	testing.expect(t, !material_set_number(&material, "Body", "missing", {}))
	testing.expect(t, material_reload(&library, &material, "missing.json") != "")
	testing.expect_value(t, material.instance.groups[0].values[0].number[0], 0.2)
	testing.expect(t, material_reload(&library, &material, "materials/left.json") != "") // 无 device，不发布半份 GPU 资源。
	testing.expect_value(t, material.instance.groups[0].values[0].number[0], 0.2)
	testing.expect_value(t, material.revision, 1)
	failed, load_error := material_load(&library, "materials/left.json")
	testing.expect(t, failed == nil && load_error != "" && len(library.instances) == 0)
	name := selected.desc.name
	selected.desc.name = "Different"
	missing, _, unknown_error := material_read(&library, "materials/left.json")
	selected.desc.name = name
	testing.expect(t, unknown_error != "" && missing.groups == nil)
}

// 运行时贴图（阴影图等）绑到 Texture 字段：采样器取字段声明，非贴图字段、外设备贴图拒绝，nil 恢复白图。
@(test)
material_set_texture_binds_runtime_texture_with_field_sampler :: proc(t: ^testing.T) {
	device, other: foster.GraphicsDevice
	library := Material_Library{device = &device}
	schema := Schema{name = "Body", fields = {
		{id = "albedo", kind = .Texture},
		{id = "amount", kind = .Scalar, maximum = 1},
		{id = "shadow", kind = .Texture, filter = .Nearest, wrap = .Repeat}}}
	samplers := make([][MAX_TEXTURES]foster.BoundSampler, 1)
	defer delete(samplers)
	material := Material{owner = &library, instance = {groups = []Instance_Group{{schema = schema}}}, samplers = samplers}
	shadow := foster.Texture{GraphicsDevice = &device}
	shadow.Resource = cast(type_of(shadow.Resource))uintptr(1) // 仅验证绑定；不调用 GPU
	testing.expect(t, material_set_texture(&material, "Body", "shadow", &shadow))
	testing.expect(t, samplers[0][1].Texture == &shadow)
	testing.expect(t, samplers[0][1].Sampler == foster.TextureSamplerMake(.Nearest, .Repeat))
	testing.expect_value(t, material.revision, 1)
	testing.expect(t, !material_set_texture(&material, "Body", "amount", &shadow))
	testing.expect(t, !material_set_texture(&material, "Other", "shadow", &shadow))
	alien := foster.Texture{GraphicsDevice = &other, Resource = shadow.Resource}
	testing.expect(t, !material_set_texture(&material, "Body", "albedo", &alien))
	// 多采样深度附件没有解析纹理，不能采样；拒绝而不是交给 SDL 报错。
	msaa_depth := foster.Texture{GraphicsDevice = &device, Resource = shadow.Resource, Format = .Depth32,
		SampleCount = .Four, IsTargetAttachment = true}
	testing.expect(t, !material_set_texture(&material, "Body", "shadow", &msaa_depth))
	testing.expect_value(t, material.revision, 1)
	testing.expect(t, material_set_texture(&material, "Body", "albedo", nil))
	testing.expect(t, samplers[0][0].Texture == &library.white)
	testing.expect(t, samplers[0][0].Sampler == foster.TextureSamplerMake(.Linear, .Clamp)) // 字段零值即默认
	testing.expect(t, field_sampler({wrap = .Mirror}) == foster.TextureSamplerMake(.Linear, .MirroredRepeat))
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

// 借用调用方的 GPU 绑定组成 Material：拒绝非材质效果、绑定数或顺序不符、缺 Shader、别的设备；成功时能被 material_select 选中。
@(test)
material_from_bindings_borrows_tool_bindings :: proc(t: ^testing.T) {
	device, other: foster.GraphicsDevice
	library := Material_Library{device = &device}
	library.white.Resource = cast(type_of(library.white.Resource))uintptr(1) // 仅验证组装；不调用 GPU
	shader := foster.Shader{GraphicsDevice = &device}
	shader.Resource = cast(type_of(shader.Resource))uintptr(1)
	alien := foster.Shader{GraphicsDevice = &other}
	gpu := foster.Material{Vertex = {Shader = &shader}, Fragment = {Shader = &shader}}
	schemas := []Schema{{name = "Body", preview = "3d"}}
	effect := Material_Effect{desc = model_effect(), schemas = schemas}
	bindings := []Material_Binding{{schema = schemas[0], material = &gpu}}

	material, reason := material_from_bindings(&library, &effect, bindings)
	testing.expect_value(t, reason, "")
	testing.expect(t, material.owner == &library && material.effect == &effect && len(material.bindings) == 1)
	selection: Pass_Selection
	testing.expect_value(t, material_select(material.effect.desc, material.bindings, .Model, "", nil, &selection), Draw_Error.None)
	testing.expect_value(t, selection.count, 1) // outline 声明为禁用

	_, missing_device := material_from_bindings(&Material_Library{}, &effect, bindings)
	testing.expect_value(t, missing_device, "Missing graphics device")
	fullscreen := Material_Effect{desc = {name = "F", output = "color", passes = []Pass_Desc{{id = "main", params = "Body", output = "color"}}}, schemas = schemas}
	_, not_material := material_from_bindings(&library, &fullscreen, bindings)
	testing.expect_value(t, not_material, "Expected Model or Sprite material effect")
	_, count := material_from_bindings(&library, &effect, nil)
	testing.expect_value(t, count, "Binding count differs from schema count")
	_, order := material_from_bindings(&library, &effect, []Material_Binding{{schema = {name = "Other"}, material = &gpu}})
	testing.expect_value(t, order, "Bindings must follow the effect's schema order")
	no_shader := foster.Material{}
	_, missing_shader := material_from_bindings(&library, &effect, []Material_Binding{{schema = schemas[0], material = &no_shader}})
	testing.expect_value(t, missing_shader, "Missing compiled shader")
	elsewhere := foster.Material{Vertex = {Shader = &alien}, Fragment = {Shader = &shader}}
	_, other_device := material_from_bindings(&library, &effect, []Material_Binding{{schema = schemas[0], material = &elsewhere}})
	testing.expect_value(t, other_device, "Shader belongs to another graphics device")
}
