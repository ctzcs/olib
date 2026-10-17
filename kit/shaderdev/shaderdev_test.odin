#+test
package shaderdev

import "core:fmt"
import "core:os"
import "core:strings"
import "core:testing"

import foster "olib:foster"
import mat "olib:kit/material"

@(test)
source_changes_include_same_length_and_deletion :: proc(t: ^testing.T) {
	root, err := os.make_directory_temp("", "olib_shaderdev_test_*", context.temp_allocator)
	if !testing.expect(t, err == nil) do return
	sub := fmt.tprintf("%s/include", root)
	file := fmt.tprintf("%s/math.hlsli", sub)
	ignored := fmt.tprintf("%s/notes.txt", root)
	defer {
		_ = os.remove(file)
		_ = os.remove(ignored)
		_ = os.remove(sub)
		_ = os.remove(root)
	}
	testing.expect(t, os.make_directory(sub) == nil)
	testing.expect(t, os.write_entire_file(file, string("AAA")) == nil)
	a, ok := source_fingerprint(root)
	testing.expect(t, ok)
	testing.expect(t, os.write_entire_file(file, string("BBB")) == nil)
	b, _ := source_fingerprint(root)
	testing.expect(t, a != b)
	testing.expect(t, os.write_entire_file(ignored, string("ignored")) == nil)
	c, _ := source_fingerprint(root)
	testing.expect(t, b == c)
	testing.expect(t, os.remove(file) == nil)
	d, _ := source_fingerprint(root)
	testing.expect(t, c != d)
}

@(test)
reject_stale_candidate_without_touching_live_state :: proc(t: ^testing.T) {
	s: Session
	testing.expect(t, init(&s, "missing/shader.hlsl", .Vulkan, {}, {}))
	defer dispose(&s)
	s.status = .Ready
	s.revision = 7
	s.has_attempted = true
	testing.expect(t, !apply(&s, nil, nil))
	testing.expect(t, s.status == .Waiting && s.revision == 7 && !s.has_attempted)
}

@(test)
safe_creation_reports_errors_without_gpu :: proc(t: ^testing.T) {
	shader: foster.Shader
	ok, error := foster.ShaderTryInit(&shader, nil, {})
	testing.expect(t, !ok && error != "" && shader.Resource == nil)
	s: Session
	testing.expect(t, !init(&s, "shader.hlsl", .None, {}, {}))
	defer dispose(&s)
	testing.expect(t, strings.contains(s.diagnostic, "requires"))
}

@(test)
parameter_package_generates_multiple_schemas_and_rejects_invalid_tags :: proc(t: ^testing.T) {
	root, err := os.make_directory_temp("", "olib_parameters_test_*", context.temp_allocator)
	if !testing.expect(t, err == nil) do return
	defer remove_workspace(root)
	first := "package params\nWater_Shader :: \"water.hlsl\"\nWater_Params :: struct { speed: f32 `ui:\"slider\" min:\"0\" max:\"5\"`, }\nwater_defaults :: proc() -> Water_Params { return {speed=2} }"
	// 同一个生成程序同时接收旧声明与专用类型，经过 JSON 清单再恢复类型化连线。
	second := "package params\nimport mat \"olib:kit/material\"\n" +
		"Other_Shader :: mat.Shader_Path(\"other.hlsl\")\nOther_Preview :: mat.Preview_Mode.Two_D\n" +
		"Other_Ref :: mat.Params_Ref(\"Other\")\nOther_Output :: mat.Target_Ref(\"color\")\n" +
		"Image_Field :: mat.Field_Ref(\"image\")\n" +
		"Other_Params :: struct { image: mat.Texture_Path, }\n" +
		"other_defaults :: proc() -> Other_Params { return {image = \"noise.png\"} }\n" +
		"Other_Passes := []mat.Pass_Desc{{id = \"main\", params = Other_Ref, output = Other_Output, " +
		"inputs = {{field = Image_Field, target = Other_Output, frame = .Previous}}}}\n"
	testing.expect(t, os.write_entire_file(fmt.tprintf("%s/water.odin", root), first) == nil)
	testing.expect(t, os.write_entire_file(fmt.tprintf("%s/other.odin", root), second) == nil)
	build := parameters_compile(root)
	defer parameter_build_dispose(&build)
	if !testing.expectf(t, build.error == "", "%s", build.error) do return
	testing.expect(t, len(build.schemas) == 2)
	testing.expect(t, build.schemas[0].shader == "other.hlsl" && build.schemas[0].preview == "2d" &&
		build.schemas[0].fields[0].kind == .Texture && build.schemas[0].fields[0].texture == "noise.png")
	if testing.expect(t, len(build.effects) == 1 && len(build.effects[0].passes) == 1) {
		pass := build.effects[0].passes[0]
		testing.expect(t, pass.params == "Other" && pass.output == "color" &&
			pass.inputs[0].field == "image" && pass.inputs[0].frame == .Previous)
	}
	testing.expectf(t, build.schemas[1].name == "Water" && build.schemas[1].fields[0].initial[0] == 2, "%v", build.schemas)
	text := mat.hlsl(build.schemas[1])
	defer delete(text)
	testing.expect(t, strings.contains(text, "#define _speed") && strings.contains(text, "b1, space3"))
	bad, _ := strings.replace_all(first, "max:\"5\"", "max:\"wrong\"", context.temp_allocator)
	testing.expect(t, os.write_entire_file(fmt.tprintf("%s/water.odin", root), bad) == nil)
	failed := parameters_compile(root)
	defer parameter_build_dispose(&failed)
	testing.expect(t, failed.error != "" && len(failed.schemas) == 0)
}
