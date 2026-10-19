#+test
package main

import "core:fmt"
import "core:mem/virtual"
import "core:os"
import "core:strings"
import "core:testing"

// AST 解析、诊断和实际文件更新的回归；文件夹由测试独占创建并逐文件清理。
@(test)
collect_tags_and_ignore_nested_text :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == nil)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)
	options := Options{tag = "component", enum_name = "Component_Kind"}
	catalog: Catalog
	source := `package game_core
// @(tag = "component") Fake :: struct {}
TEXT :: "@(tag = \"component\") Fake_String :: struct {}"
@(tag = "component-other") Unrelated :: struct {}
@(tag = "compo\u006eent") Follow :: struct { speed: f32 }
@(tag = "component")
@(private)
Lifetime :: struct { remaining: f32 }
@(tag = "component")
alpha, beta :: 1, 2
helper :: proc() {
    @(tag = "component") Local :: struct {}
}
`
	error := collect_source(&catalog, source, "fixture.odin", options)
	testing.expect_value(t, error, "")
	testing.expect_value(t, len(catalog.names), 4)
	testing.expect(t, "Follow" in catalog.locations)
	testing.expect(t, "Lifetime" in catalog.locations)
	testing.expect(t, "alpha" in catalog.locations)
	testing.expect(t, "beta" in catalog.locations)
	// 原始字符串标签和函数声明也可识别。
	error = collect_source(&catalog,
		"package game_core\n@(tag = `component`)\nact :: proc() {}\n", "raw.odin", options)
	testing.expect_value(t, error, "")
	testing.expect(t, "act" in catalog.locations)
}

@(test)
reject_ambiguous_declarations :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == nil)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)
	options := Options{tag = "component", enum_name = "Kind"}
	cases := []struct { source, expected: string }{
		{"@(tag = \"component\") A :: struct {}\n@(tag = \"component\") A :: struct {}", "重复成员"},
		{"when true { @(tag = \"component\") A :: struct {} }", "条件编译"},
		{"when false {} else { @(tag = \"component\") A :: struct {} }", "条件编译"},
		{"@(tag = TAG) A :: struct {}", "字符串字面量"},
		{"Kind :: struct {}", "冲突"},
		{"@(tag = \"component\") _ :: 1", "声明名"},
	}
	for item in cases {
		catalog: Catalog
		source := fmt.aprintf("package game_core\n%s\n", item.source)
		error := collect_source(&catalog, source, "bad.odin", options)
		testing.expectf(t, strings.contains(error, item.expected), "%s: %s", item.expected, error)
	}
	catalog: Catalog
	error := collect_source(&catalog,
		"#+build windows\npackage game_core\n@(tag = \"component\") A :: struct {}\n",
		"build.odin", options)
	testing.expectf(t, strings.contains(error, "条件编译"), "%s", error)
	catalog = {}
	error = collect_source(&catalog,
		"#+test\npackage game_core\n@(tag = \"component\") Test :: struct {}\n", "test.odin", options)
	testing.expect_value(t, error, "")
	testing.expect_value(t, len(catalog.names), 0)
	for path in ([]string{"effect_windows.odin", "effect_linux_amd64.odin"}) {
		catalog = {}
		error = collect_source(&catalog,
			"package game_core\n@(tag = \"component\") A :: struct {}\n", path, options)
		testing.expect(t, strings.contains(error, "条件编译"))
	}
	catalog = {}
	testing.expect_value(t, collect_source(&catalog, "package first\n", "a.odin", options), "")
	error = collect_source(&catalog, "package second\n", "b.odin", options)
	testing.expect(t, strings.contains(error, "包名不一致"))
}

@(test)
generate_and_update_files :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == nil)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)
	directory, temp_error := os.make_directory_temp("", "olib_auto_gen_", context.allocator)
	assert(temp_error == nil)
	defer cleanup_auto_gen_test(directory)
	output := fmt.aprintf("%s/kinds_generated.odin", directory)
	options, parse_error := parse_options({"-source", directory, "-tag", "component",
		"-enum", "Kind", "-out", output})
	testing.expect_value(t, parse_error, "")
	a := fmt.aprintf("%s/a.odin", directory)
	b := fmt.aprintf("%s/b.odin", directory)
	assert(os.write_entire_file(a, "package demo\n@(tag = \"component\") Zebra :: struct {}\n") == nil)
	assert(os.write_entire_file(b, "package demo\n@(tag = \"component\") Apple :: struct {}\n") == nil)
	assert(os.write_entire_file(fmt.aprintf("%s/ignored_test.odin", directory),
		"#+test\npackage demo\n@(tag = \"component\") Apple :: struct {}\n") == nil)
	content, error := generate(options)
	testing.expect_value(t, error, "")
	testing.expect(t, strings.contains(content, "Kind :: enum {\n\tApple,\n\tZebra,\n}"))
	_, error = update_output(options.output, content, true)
	testing.expect(t, error != "")
	testing.expect(t, !os.exists(output))
	changed: bool
	changed, error = update_output(options.output, content, false)
	testing.expect_value(t, error, "")
	testing.expect(t, changed)
	// 编译真实生成结果，覆盖格式串转义、包声明和枚举成员语法。
	state, stdout, stderr, compile_error := os.process_exec(
		{command = {"odin", "check", directory, "-no-entry-point", "-vet"}}, context.allocator)
	testing.expectf(t, compile_error == nil && state.exited && state.exit_code == 0,
		"%v\n%s\n%s", compile_error, string(stdout), string(stderr))
	before, _ := os.stat(output, context.allocator)
	// 再扫描时排除目标文件，生成文本和修改时间都保持不变。
	again, again_error := generate(options)
	testing.expect_value(t, again_error, "")
	testing.expect_value(t, again, content)
	changed, error = update_output(options.output, again, false)
	testing.expect_value(t, error, "")
	testing.expect(t, !changed)
	after, _ := os.stat(output, context.allocator)
	testing.expect_value(t, after.modification_time, before.modification_time)
	_, error = update_output(options.output, again, true)
	testing.expect_value(t, error, "")
	crlf, _ := strings.replace_all(content, "\n", "\r\n", context.allocator)
	assert(os.write_entire_file(output, crlf) == nil)
	changed, error = update_output(options.output, content, false)
	testing.expect_value(t, error, "")
	testing.expect(t, !changed)
	_, error = update_output(options.output, content, true)
	testing.expect_value(t, error, "")
	assert(os.write_entire_file(b, "package demo\n@(tag = \"component\") Bee :: struct {}\n") == nil)
	new_content, _ := generate(options)
	_, error = update_output(options.output, new_content, true)
	testing.expect(t, error != "")
	stored, _ := os.read_entire_file(output, context.allocator)
	testing.expect_value(t, string(stored), crlf)
	changed, error = update_output(options.output, new_content, false)
	testing.expect_value(t, error, "")
	testing.expect(t, changed)
	// 解析失败应在写入前结束，保留上一份有效输出。
	assert(os.write_entire_file(b, "package demo\nBroken :: struct {\n") == nil)
	cli_result := run_cli({"-source", directory, "-tag", "component",
		"-enum", "Kind", "-out", output})
	testing.expect_value(t, cli_result, 1)
	stored, _ = os.read_entire_file(output, context.allocator)
	testing.expect_value(t, string(stored), new_content)
	assert(os.write_entire_file(b, "package demo\n") == nil)
	assert(os.write_entire_file(output, "package demo\n// hand written\n") == nil)
	_, error = update_output(options.output, new_content, false)
	testing.expect(t, strings.contains(error, "拒绝覆盖"))
	options.tag = "absent"
	_, error = generate(options)
	testing.expect(t, strings.contains(error, "未找到"))
}

@(test)
validate_arguments :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == nil)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)
	for name in ([]string{"", "_", "enum", "123", "A B", "Name\nInjected"}) {
		testing.expectf(t, !valid_identifier(name), "%q", name)
	}
	testing.expect(t, valid_identifier("Component_Kind"))
	for args in ([][]string{
		{}, {"-tag"}, {"-unknown", "x"}, {"-tag", "x", "-tag", "x"},
		{"-source", ".", "-tag", "x", "-enum", "Kind", "-out", "../outside.odin"},
		{"-source", ".", "-tag", "x", "-enum", "Kind", "-out", "kind_test.odin"},
		{"-source", ".", "-tag", "x", "-enum", "Kind", "-out", "kind_windows.odin"},
	}) {
		_, error := parse_options(args)
		testing.expectf(t, error != "", "%v", args)
	}
}

cleanup_auto_gen_test :: proc(directory: string) {
	entries, error := os.read_all_directory_by_path(directory, context.allocator)
	assert(error == nil)
	for entry in entries {
		assert(entry.type == .Regular)
		assert(os.remove(entry.fullpath) == nil)
	}
	assert(os.remove(directory) == nil)
}
