// 创建器端到端回归：所有写入都在独占临时目录；不使用用户项目。
package main

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"

main :: proc() {
	root, _ := filepath.abs(#directory + "/../..", context.temp_allocator)
	temp, err := os.make_directory_temp("", "olib_new_game_", context.allocator)
	assert(err == nil)
	defer delete(temp)
	defer remove_private_tree(temp)
	exe := ODIN_OS == .Windows ? ".exe" : ""
	generator := fmt.tprintf("%s/generator%s", temp, exe)
	run(root, {"odin", "build", "tools/new-game", "-vet", "-vet-packages:main", fmt.tprintf("-out:%s", generator)}, true)
	project := fmt.tprintf("%s/Game With Spaces", temp)
	run(root, {generator, project, "TemplateTest"}, true)
	for path in ([]string{"src/editor/main.odin", "src/core_editor/editor.odin", "src/core_editor/module.odin", "src/core/services.odin"}) {
		assert(os.exists(fmt.tprintf("%s/%s", project, path)), "missing unified Editor layout")
	}
	for path in ([]string{"src/main.odin", "src/feedback.odin", "src/tools/editor", "src/editor/play", "src/editor/feedback.odin", "src/host", "src/editor/module.odin", "src/editor/editor.odin"}) {
		assert(!os.exists(fmt.tprintf("%s/%s", project, path)), "split Editor entry must not be generated")
	}
	readme := fmt.tprintf("%s/README.md", project)
	before, read_err := os.read_entire_file(readme, context.temp_allocator)
	assert(read_err == nil && strings.contains(string(before), "TemplateTest"))
	run(root, {generator, project, "Overwrite"}, false)
	after, _ := os.read_entire_file(readme, context.temp_allocator)
	assert(string(before) == string(after), "existing project must not be overwritten")
	for name in ([]string{"../Escape", "bad-name", "CON", "1Game"}) {
		run(root, {generator, fmt.tprintf("%s/rejected", temp), name}, false)
		assert(!os.exists(fmt.tprintf("%s/rejected", temp)))
	}
	run(root, {generator, fmt.tprintf("%s/build/forbidden_new_game", root), "InsideLibrary"}, false)
	run(project, {"odin", "run", "tools/check", fmt.tprintf("-out:%s/check%s", temp, exe)}, true)
	fmt.println("PASS: fresh template in spaced path, refusal safety, tests, layers, DLL, desktop and Web builds")
}

run :: proc(root: string, command: []string, success: bool) {
	state, out, errout, err := os.process_exec({working_dir = root, command = command}, context.temp_allocator)
	actual := err == nil && state.exited && state.exit_code == 0
	if actual != success {
		fmt.eprintln(command, err, string(out), string(errout))
		panic("unexpected template command result")
	}
	if success do fmt.println(string(out))
}

// 仅在 make_directory_temp 返回的独占目录中递归；不跟随链接。
remove_private_tree :: proc(path: string) {
	entries, err := os.read_all_directory_by_path(path, context.temp_allocator)
	if err == nil {
		for entry in entries {
			if entry.type == .Directory do remove_private_tree(entry.fullpath)
			else do assert(os.remove(entry.fullpath) == nil)
		}
	}
	assert(os.remove(path) == nil)
}
