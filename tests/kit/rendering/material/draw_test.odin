#+test
package material

import "core:encoding/json"
import "core:testing"

import foster "olib:foster"

// 这些用例都在提交任何 Draw 之前返回，不需要真实 GPU：设备/网格只当作非空指针。
@(private)
model_effect :: proc() -> Effect_Desc {
	passes := make([]Pass_Desc, 2, context.temp_allocator)
	passes[0] = {id = "body", params = "Body", draw = .Model, output = "color"}
	passes[1] = {id = "outline", params = "Body", draw = .Model, output = "color", disabled = true}
	return {name = "E", output = "color", passes = passes}
}

@(test)
material_draw_reports_why_it_refused :: proc(t: ^testing.T) {
	device: foster.GraphicsDevice
	mesh: foster.Mesh
	effect := model_effect()
	draw := Material_Draw{mesh = &mesh, kind = .Model}

	testing.expect_value(t, material_draw(nil, effect, nil, draw), Draw_Error.Missing_Device)
	testing.expect_value(t, material_draw(&device, effect, nil, Material_Draw{kind = .Model}), Draw_Error.Missing_Mesh)
	fullscreen := effect
	fullscreen.passes = []Pass_Desc{{id = "a", params = "Body", draw = .Fullscreen, output = "color"}}
	testing.expect_value(t, material_draw(&device, fullscreen, nil, draw), Draw_Error.Not_Material_Effect)

	// 选择阶段：未知 ID、enabled 太短、没有 Pass。
	draw.options.pass_id = "ghost"
	testing.expect_value(t, material_draw(&device, effect, nil, draw), Draw_Error.Unknown_Pass)
	draw.options = {enabled = []bool{true}}
	testing.expect_value(t, material_draw(&device, effect, nil, draw), Draw_Error.Bad_Pass_Selection)
	draw.options = {}
	crowded := effect
	crowded.passes = make([]Pass_Desc, MAX_PASSES+1, context.temp_allocator)
	for &pass in crowded.passes do pass = {id = "p", params = "Body", draw = .Model, output = "color"}
	testing.expect_value(t, material_draw(&device, crowded, nil, draw), Draw_Error.Too_Many_Passes)

	// 绑定阶段：种类不符、缺绑定、绑定不完整。
	sprite := draw
	sprite.kind = .Sprite
	testing.expect_value(t, material_draw(&device, effect, nil, sprite), Draw_Error.Wrong_Pass_Kind)
	testing.expect_value(t, material_draw(&device, effect, nil, draw), Draw_Error.Missing_Binding)
	broken := []Material_Binding{{schema = {name = "Body"}}}
	testing.expect_value(t, material_draw(&device, effect, broken, draw), Draw_Error.Invalid_Binding)
}

@(test)
material_draw_checks_instance_buffer_rules :: proc(t: ^testing.T) {
	device: foster.GraphicsDevice
	mesh: foster.Mesh
	buffer: foster.VertexBuffer
	schema := Schema{name = "Body", preview = "3d", fields = {{id = "hue", name = "hue", kind = .Scalar, maximum = 1, instance = true}}}
	passes := []Pass_Desc{{id = "body", params = "Body", draw = .Model, output = "color"}}
	instanced := Effect_Desc{name = "E", output = "color", passes = passes, instanced = true}
	plain := Effect_Desc{name = "E", output = "color", passes = passes}
	bindings := []Material_Binding{{schema = schema}}
	draw := Material_Draw{mesh = &mesh, kind = .Model}
	// instanced 模型效果必须带实例缓冲。
	testing.expect_value(t, material_draw(&device, instanced, bindings, draw), Draw_Error.Instance_Buffer_Required)
	// 普通效果不能带实例缓冲；缓冲字段数必须与 Schema 一致。
	draw.instance_buffer, draw.instance_count, draw.instance_slots = &buffer, 10, 1
	testing.expect_value(t, material_draw(&device, plain, bindings, draw), Draw_Error.Not_Instanced_Effect)
	draw.instance_slots = 0
	testing.expect_value(t, material_draw(&device, instanced, bindings, draw), Draw_Error.Instance_Mismatch)
	// 字段数一致后才进入绑定检查（这里没有可用 Shader）。
	draw.instance_slots = 1
	testing.expect_value(t, material_draw(&device, instanced, bindings, draw), Draw_Error.Invalid_Binding)
	// 精灵 instanced 效果既可用实例缓冲（缓冲变体），也可以逐个绘制（批量变体），不再要求缓冲。
	draw.kind = .Sprite
	sprite := instanced
	sprite.passes = []Pass_Desc{{id = "body", params = "Body", draw = .Sprite, output = "color"}}
	testing.expect_value(t, material_draw(&device, sprite, bindings, draw), Draw_Error.Invalid_Binding)
	draw.instance_buffer = nil
	testing.expect_value(t, material_draw(&device, sprite, bindings, draw), Draw_Error.Invalid_Binding)
}

@(test)
material_draw_treats_all_disabled_passes_as_success :: proc(t: ^testing.T) {
	device: foster.GraphicsDevice
	mesh: foster.Mesh
	effect := model_effect()
	// outline 被声明禁用：显式选择它成功但不提交任何 Draw，也不需要绑定。
	draw := Material_Draw{mesh = &mesh, kind = .Model, options = {pass_id = "outline"}}
	testing.expect_value(t, material_draw(&device, effect, nil, draw), Draw_Error.None)
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
	testing.expect_value(t, shader_pick(.Vulkan, binaries)[0], 1)
	testing.expect_value(t, shader_pick(.D3D12, binaries)[0], 2)
	testing.expect_value(t, shader_pick(.Metal, binaries)[0], 3)
	testing.expect_value(t, len(shader_pick(.Metal, {spv = {1}, dxil = {2}})), 0)
	testing.expect(t, shader_driver_supported(.Metal) && !shader_driver_supported(.None))
}

@(test)
material_register_manifest_selects_backend_and_validates :: proc(t: ^testing.T) {
	schemas := []Schema{{name = "Body", preview = "3d"}}
	effect := Effect_Desc{name = "E", output = "color", passes = []Pass_Desc{
		{id = "body", params = "Body", draw = .Model, output = "color"},
	}}
	manifest, err := json.marshal(struct {version: int, schemas: []Schema, effect: Effect_Desc}{1, schemas, effect})
	defer delete(manifest)
	testing.expect_value(t, err, nil)
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
	testing.expect_value(t, material_register_manifest(&library, manifest, nil), "Shader code count differs from schema count")
	testing.expect_value(t, material_register_manifest(&library, manifest, passes), "")
	testing.expect_value(t, len(library.effects), 1)
	// D3D12 选 dxil：顶点 2、片元 5。
	testing.expect(t, library.effects[0].code[0].vertex[0] == 2 && library.effects[0].code[0].fragment[0] == 5)

	device.Driver = .None
	testing.expect_value(t, material_register_manifest(&library, manifest, passes), "Unsupported shader backend")
}
