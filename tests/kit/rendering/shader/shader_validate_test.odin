#+test
package shader

import "core:strings"
import "core:testing"

// 单 Pass 的合法基线；每个用例只改一处，确认 shader_validate 报告对应的错误。
@(private)
base_pass :: proc() -> Pass_Desc {
	return {id = "a", params = "Body", draw = .Fullscreen, output = "color"}
}

@(private)
single_pass_shader :: proc(pass: Pass_Desc) -> Shader_Desc {
	passes := make([]Pass_Desc, 1, context.temp_allocator)
	passes[0] = pass
	return {name = "E", output = "color", passes = passes}
}

@(private)
validate_schemas :: proc() -> []Schema {
	fields := make([]Field, 2, context.temp_allocator)
	fields[0] = {id = "image", name = "image", kind = .Texture}
	fields[1] = {id = "amount", name = "amount", kind = .Scalar, maximum = 1}
	schemas := make([]Schema, 1, context.temp_allocator)
	schemas[0] = {name = "Body", preview = "2d", fields = fields}
	return schemas
}

@(private)
expect_invalid :: proc(t: ^testing.T, shader: Shader_Desc, expected: string, loc := #caller_location) {
	reason := shader_validate(shader, validate_schemas())
	testing.expectf(t, strings.contains(reason, expected), "want %q in %q", expected, reason, loc = loc)
}

@(test)
shader_validate_accepts_baseline :: proc(t: ^testing.T) {
	testing.expect_value(t, shader_validate(single_pass_shader(base_pass()), validate_schemas()), "")
}

@(test)
shader_validate_rejects_bad_shader_header :: proc(t: ^testing.T) {
	shader := single_pass_shader(base_pass())
	shader.preview = "4d"
	expect_invalid(t, shader, "Preview must be 2d or 3d")
	shader = single_pass_shader(base_pass())
	shader.name = ""
	expect_invalid(t, shader, "requires a name")
	shader = single_pass_shader(base_pass())
	shader.passes = nil
	expect_invalid(t, shader, "requires a name")
	shader = single_pass_shader(base_pass())
	shader.output = "missing"
	expect_invalid(t, shader, "Shader output must name a pass target")
}

@(test)
shader_validate_rejects_bad_pass_declarations :: proc(t: ^testing.T) {
	pass := base_pass()
	pass.draw = Pass_Draw(9)
	expect_invalid(t, single_pass_shader(pass), "Invalid pass draw kind")
	pass = base_pass()
	pass.state.cull = Pass_Cull(9)
	expect_invalid(t, single_pass_shader(pass), "Invalid pass render state")
	pass = base_pass()
	pass.id = ""
	expect_invalid(t, single_pass_shader(pass), "cannot be empty")
	pass = base_pass()
	pass.params = "Nope"
	expect_invalid(t, single_pass_shader(pass), "unknown parameter group")

	twice := make([]Pass_Desc, 2, context.temp_allocator)
	twice[0], twice[1] = base_pass(), base_pass()
	expect_invalid(t, Shader_Desc{name = "E", output = "color", passes = twice}, "must be unique")
}

@(test)
shader_validate_rejects_bad_targets :: proc(t: ^testing.T) {
	pass := base_pass()
	pass.target.width = 10
	expect_invalid(t, single_pass_shader(pass), "invalid target")
	pass = base_pass()
	pass.target.samples = 3
	expect_invalid(t, single_pass_shader(pass), "invalid target")
	pass = base_pass()
	pass.target.width, pass.target.height = MAX_TARGET_SIZE+1, 8
	expect_invalid(t, single_pass_shader(pass), "invalid target")
	pass = base_pass()
	pass.target.clear = {2, 0, 0, 0}
	expect_invalid(t, single_pass_shader(pass), "clear color")
}

@(test)
shader_validate_rejects_bad_inputs_and_values :: proc(t: ^testing.T) {
	pass := base_pass()
	pass.inputs = []Pass_Input{{field = "nope", target = "color"}}
	expect_invalid(t, single_pass_shader(pass), "no Texture field")
	pass.inputs = []Pass_Input{{field = "image", target = "ghost"}}
	expect_invalid(t, single_pass_shader(pass), "unknown target")
	pass.inputs = []Pass_Input{{field = "image", target = "color"}, {field = "image", target = "color"}}
	expect_invalid(t, single_pass_shader(pass), "Duplicate pass texture binding")

	pass = base_pass()
	pass.values = []Pass_Value{{field = "amount", number = {5, 0, 0, 0}}}
	expect_invalid(t, single_pass_shader(pass), "outside field range")
	pass.values = []Pass_Value{{field = "amount"}, {field = "amount"}}
	expect_invalid(t, single_pass_shader(pass), "Duplicate pass value override")
	pass.values = []Pass_Value{{field = "image"}}
	expect_invalid(t, single_pass_shader(pass), "no numeric field")
}

@(test)
shader_sort_detects_current_frame_cycle :: proc(t: ^testing.T) {
	passes := make([]Pass_Desc, 2, context.temp_allocator)
	passes[0] = {id = "a", params = "Body", draw = .Fullscreen, output = "x",
		inputs = []Pass_Input{{field = "image", target = "y"}}}
	passes[1] = {id = "b", params = "Body", draw = .Fullscreen, output = "y",
		inputs = []Pass_Input{{field = "image", target = "x"}}}
	shader := Shader_Desc{name = "E", output = "x", passes = passes}
	// 各 Pass 单独合法：环只有排序才发现。
	testing.expect_value(t, shader_validate(shader, validate_schemas()), "")
	order, reason := shader_sort(shader)
	testing.expect(t, order == nil && strings.contains(reason, "cycle"))
	passes[1].inputs[0].frame = .Previous
	order, reason = shader_sort(shader)
	defer delete(order)
	testing.expect(t, reason == "" && len(order) == 2 && order[0] == 1 && order[1] == 0)
}
