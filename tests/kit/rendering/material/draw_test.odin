#+test
package material

import "base:runtime"
import "core:encoding/json"
import "core:testing"

import foster "olib:foster"
import sh "olib:kit/rendering/shader"

// 这些用例都在提交任何 Draw 之前返回，不需要真实 GPU：设备/网格只当作非空指针。
@(private)
model_shader :: proc() -> sh.Shader_Desc {
	passes := make([]sh.Pass_Desc, 2, context.temp_allocator)
	passes[0] = {id = "body", params = "Body", draw = .Model, output = "color"}
	passes[1] = {id = "outline", params = "Body", draw = .Model, output = "color", disabled = true}
	return {name = "E", output = "color", passes = passes}
}

// 选择阶段：未知 ID、Pass 过多；绑定阶段：种类不符、缺绑定、绑定不完整。
@(test)
material_select_reports_why_it_refused :: proc(t: ^testing.T) {
	shader := model_shader()
	selection: Pass_Selection
	testing.expect_value(t, material_select(shader, nil, .Model, "ghost", nil, &selection), Draw_Error.Unknown_Pass)
	crowded := shader
	crowded.passes = make([]sh.Pass_Desc, sh.MAX_PASSES+1, context.temp_allocator)
	for &pass in crowded.passes do pass = {id = "p", params = "Body", draw = .Model, output = "color"}
	testing.expect_value(t, material_select(crowded, nil, .Model, "", nil, &selection), Draw_Error.Too_Many_Passes)
	testing.expect_value(t, material_select(shader, nil, .Sprite, "", nil, &selection), Draw_Error.Wrong_Pass_Kind)
	testing.expect_value(t, material_select(shader, nil, .Model, "", nil, &selection), Draw_Error.Missing_Binding)
	broken := []Material_Binding{{schema = {name = "Body"}}}
	testing.expect_value(t, material_select(shader, broken, .Model, "", nil, &selection), Draw_Error.Invalid_Binding)
	// outline 被声明禁用：按 ID 选中它成功，但不选出任何 Pass，也不需要绑定。
	testing.expect_value(t, material_select(shader, nil, .Model, "outline", nil, &selection), Draw_Error.None)
	testing.expect_value(t, selection.count, 0)
}

// 视图块整块补零，超长拒绝且不改动；Model 比 Sprite 多出顶点 b1 / 片元 b2 两个槽。
@(test)
view_globals_padding_and_slot_counts :: proc(t: ^testing.T) {
	block: [VIEW_GLOBALS_SIZE]u8
	block[VIEW_GLOBALS_SIZE - 1] = 9
	testing.expect(t, view_globals_pack(&block, []u8{1, 2, 3}))
	testing.expect(t, block[2] == 3 && block[3] == 0 && block[VIEW_GLOBALS_SIZE - 1] == 0)
	too_long := make([]u8, VIEW_GLOBALS_SIZE + 16, context.temp_allocator)
	testing.expect(t, !view_globals_pack(&block, too_long))
	testing.expect_value(t, block[0], u8(1)) // 失败不改 block

	vertex, fragment := material_uniform_counts(model_shader())
	testing.expect(t, vertex == 2 && fragment == 3)
	sprite := sh.Shader_Desc{passes = []sh.Pass_Desc{{draw = .Sprite}}}
	vertex, fragment = material_uniform_counts(sprite)
	testing.expect(t, vertex == 2 && fragment == 2)
	sprite.uniforms = .Foster
	vertex, fragment = material_uniform_counts(sprite)
	testing.expect(t, vertex == 1 && fragment == 1)
}

// 每种 ZTest 都映射到 foster 的比较；Off 关闭测试，Default 不改调用方状态。
@(test)
pass_depth_maps_every_compare :: proc(t: ^testing.T) {
	expected := [sh.Pass_Depth]foster.DepthCompare{
		.Default = .Equal, .Off = .Equal, .Less = .Less, .Less_Equal = .LessOrEqual, .Equal = .Equal,
		.Always = .Always, .Greater = .Greater, .Greater_Equal = .GreatorOrEqual, .Not_Equal = .NotEqual, .Never = .Never,
	}
	for depth in sh.Pass_Depth {
		// 起始状态用 Equal、测试开启，便于看出 Default 不改、Off 只关测试。
		command := foster.DrawCommand{DepthTestEnabled = true, DepthCompare = .Equal}
		pass_state_apply(&command, {depth = depth})
		testing.expectf(t, command.DepthCompare == expected[depth], "%v -> %v", depth, command.DepthCompare)
		testing.expectf(t, command.DepthTestEnabled == (depth != .Off), "%v test enabled", depth)
	}
}

@(test)
draw_error_text_covers_every_error :: proc(t: ^testing.T) {
	testing.expect_value(t, draw_error_text(.None), "")
	for error in Draw_Error {
		if error == .None do continue
		testing.expectf(t, draw_error_text(error) != "", "%v has no text", error)
	}
}

@(test)
shader_pick_follows_driver :: proc(t: ^testing.T) {
	binaries := Shader_Binaries{spv = {1}, dxil = {2}, msl = {3}}
	// 原生 Private 驱动需要平台私有格式，olib 不提供。
	testing.expect_value(t, len(shader_pick(.Private, binaries)), 0)
	testing.expect(t, !shader_driver_supported(.Private))
	testing.expect_value(t, shader_pick(.Vulkan, binaries)[0], 1)
	testing.expect_value(t, shader_pick(.D3D12, binaries)[0], 2)
	testing.expect_value(t, shader_pick(.Metal, binaries)[0], 3)
	testing.expect_value(t, len(shader_pick(.Metal, {spv = {1}, dxil = {2}})), 0)
	testing.expect(t, shader_driver_supported(.Metal) && !shader_driver_supported(.None))
}

@(test)
material_register_manifest_selects_backend_and_validates :: proc(t: ^testing.T) {
	schemas := []sh.Schema{{name = "Body", preview = "3d"}}
	shader := sh.Shader_Desc{name = "E", output = "color", passes = []sh.Pass_Desc{
		{id = "body", params = "Body", draw = .Model, output = "color"},
	}}
	Manifest :: struct {version: int, schemas: []sh.Schema, shader: sh.Shader_Desc `json:"effect"`} // 与 tools/shaders 写出的键一致
	manifest, err := json.marshal(Manifest{MANIFEST_VERSION, schemas, shader})
	defer delete(manifest)
	testing.expect_value(t, err, nil)
	// 旧约定生成的清单不能登记，否则旧字节码按新布局读数据会无声画错。
	outdated, outdated_err := json.marshal(Manifest{MANIFEST_VERSION - 1, schemas, shader})
	defer delete(outdated)
	testing.expect_value(t, outdated_err, nil)
	passes := []Pass_Binaries{{
		vertex = {spv = {1}, dxil = {2}, msl = {3}},
		fragment = {spv = {4}, dxil = {5}, msl = {6}},
	}}

	library := Material_Library{}
	testing.expect_value(t, material_register_manifest(&library, manifest, passes), "Missing graphics device")

	device := foster.GraphicsDevice{Driver = .D3D12}
	library.device = &device
	defer material_library_dispose(&library)
	testing.expect_value(t, material_register_manifest(&library, []u8{'x'}, passes), "Invalid compiled shader manifest")
	testing.expect_value(t, material_register_manifest(&library, outdated, passes),
		"Compiled shader manifest is outdated; re-run tools/shaders")
	testing.expect_value(t, material_register_manifest(&library, manifest, nil),"Shader code count differs from schema count")
	testing.expect_value(t, material_register_manifest(&library, manifest, passes), "")
	testing.expect_value(t, len(library.shaders), 1)
	// D3D12 选 dxil：顶点 2、片元 5。
	testing.expect(t, library.shaders[0].code[0].vertex[0] == 2 && library.shaders[0].code[0].fragment[0] == 5)

	device.Driver = .None
	testing.expect_value(t, material_register_manifest(&library, manifest, passes), "Unsupported shader backend")
}

// tools/shaders 写出的清单 JSON；借用 temp_allocator。
@(private)
compiled_manifest_json :: proc(shader: sh.Shader_Desc, schemas: []sh.Schema, version := MANIFEST_VERSION) -> []u8 {
	data, _ := json.marshal(Compiled_Manifest{version, schemas, shader}, allocator = context.temp_allocator)
	return data
}

// 内存里的 #load_directory 结果：Model Shader、instanced Sprite Shader、只供预览的 Fullscreen Shader 和无关文件。
@(test)
material_register_directory_finds_compiled_files :: proc(t: ^testing.T) {
	hero := sh.Shader_Desc{name = "Hero", output = "color", passes = []sh.Pass_Desc{
		{id = "body", params = "Hero_body", draw = .Model, output = "color"},
	}}
	spark := sh.Shader_Desc{name = "Spark", output = "color", instanced = true, passes = []sh.Pass_Desc{
		{id = "main", params = "Spark_main", draw = .Sprite, output = "color"},
	}}
	trail := sh.Shader_Desc{name = "Trail", output = "color", passes = []sh.Pass_Desc{
		{id = "blur", params = "Trail_blur", draw = .Fullscreen, output = "color"},
	}}
	files := []runtime.Load_Directory_File{
		{"Hero.shader.json", compiled_manifest_json(hero, {{name = "Hero_body", preview = "3d"}})},
		{"Hero_body.vertex.dxil", {1}}, {"Hero_body.vertex.spv", {11}},
		{"Hero_body.fragment.dxil", {2}}, {"Hero_body.fragment.spv", {12}},
		{"Spark.shader.json", compiled_manifest_json(spark, {{name = "Spark_main", preview = "2d"}})},
		{"Spark_main.vertex.dxil", {3}}, {"Spark_main.fragment.dxil", {4}},
		{"Spark_main.instanced.vertex.dxil", {5}},
		{"Trail.shader.json", compiled_manifest_json(trail, {{name = "Trail_blur"}})},
		{"notes.txt", {0}},
	}
	device := foster.GraphicsDevice{Driver = .D3D12}
	library := Material_Library{device = &device}
	defer material_library_dispose(&library)
	testing.expect_value(t, material_register_directory(&library, files), "")
	// Trail 只供预览，跳过；D3D12 选 dxil，instanced 精灵带上缓冲变体顶点。
	testing.expect_value(t, len(library.shaders), 2)
	if len(library.shaders) == 2 {
		body := library.shaders[0].code[0]
		testing.expect(t, library.shaders[0].desc.name == "Hero" && body.vertex[0] == 1 && body.fragment[0] == 2)
		main := library.shaders[1].code[0]
		testing.expect(t, library.shaders[1].desc.name == "Spark" && main.vertex[0] == 3 && main.instanced_vertex[0] == 5)
	}

	// 换成 Vulkan 选 spv。
	vulkan_device := foster.GraphicsDevice{Driver = .Vulkan}
	vulkan := Material_Library{device = &vulkan_device}
	defer material_library_dispose(&vulkan)
	testing.expect_value(t, material_register_directory(&vulkan, files[:5]), "")
	testing.expect(t, len(vulkan.shaders) == 1 && vulkan.shaders[0].code[0].vertex[0] == 11 &&
		vulkan.shaders[0].code[0].fragment[0] == 12)
}

@(test)
material_register_directory_names_what_is_missing :: proc(t: ^testing.T) {
	hero := sh.Shader_Desc{name = "Hero", output = "color", passes = []sh.Pass_Desc{
		{id = "body", params = "Hero_body", draw = .Model, output = "color"},
	}}
	spark := sh.Shader_Desc{name = "Spark", output = "color", instanced = true, passes = []sh.Pass_Desc{
		{id = "main", params = "Spark_main", draw = .Sprite, output = "color"},
	}}
	hero_manifest := compiled_manifest_json(hero, {{name = "Hero_body", preview = "3d"}})
	device := foster.GraphicsDevice{Driver = .D3D12}
	library := Material_Library{device = &device}
	defer material_library_dispose(&library)

	no_fragment := []runtime.Load_Directory_File{{"Hero.shader.json", hero_manifest}, {"Hero_body.vertex.dxil", {1}}}
	testing.expect_value(t, material_register_directory(&library, no_fragment),
		"Hero_body.fragment.dxil: missing compiled shader; re-run tools/shaders")
	// 只有别的后端格式也算缺失。
	other_backend := []runtime.Load_Directory_File{{"Hero.shader.json", hero_manifest},
		{"Hero_body.vertex.spv", {1}}, {"Hero_body.fragment.spv", {2}}}
	testing.expect_value(t, material_register_directory(&library, other_backend),
		"Hero_body.vertex.dxil: missing compiled shader; re-run tools/shaders")
	no_instanced := []runtime.Load_Directory_File{{"Spark.shader.json", compiled_manifest_json(spark, {{name = "Spark_main", preview = "2d"}})},
		{"Spark_main.vertex.dxil", {3}}, {"Spark_main.fragment.dxil", {4}}}
	testing.expect_value(t, material_register_directory(&library, no_instanced),
		"Spark_main.instanced.vertex.dxil: missing compiled shader; re-run tools/shaders")
	outdated := []runtime.Load_Directory_File{{"Hero.shader.json", compiled_manifest_json(hero,
		{{name = "Hero_body", preview = "3d"}}, MANIFEST_VERSION - 1)}}
	testing.expect_value(t, material_register_directory(&library, outdated),
		"Hero.shader.json: Compiled shader manifest is outdated; re-run tools/shaders")
	testing.expect_value(t, material_register_directory(&library, []runtime.Load_Directory_File{{"Hero_body.vertex.dxil", {1}}}),
		"No compiled shader manifest (*.shader.json) in directory")
	testing.expect_value(t, len(library.shaders), 0)

	// 设备与后端检查与 material_register_manifest 的文本一致。
	empty: Material_Library
	testing.expect_value(t, material_register_directory(&empty, no_fragment), "Missing graphics device")
	device.Driver = .None
	testing.expect_value(t, material_register_directory(&library, no_fragment), "Unsupported shader backend")
}
