package main

// shader 产物新鲜度：含 Compiled/ 的 shader 目录，若有 tools/shaders 写的 Compiled/sources.json，
// 就运行 tools/shaders -check 比对源码指纹（不需要 shadercross）；没有记录的目录只提示跳过。
// 指纹规则只在 tools/shaders 里实现，这里只发现目录并调用它，不 import olib 的包。
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strings"

Shader_Dir :: struct {
	path:     string, // 绝对路径
	name:     string, // 相对 base（olib 的上级目录），/ 分隔，用作检查项名称
	recorded: bool,   // Compiled/sources.json 存在
}

// 在 roots 下递归找出含 Compiled/ 的目录，跳过隐藏目录、build 与 library，按名称排序。
// 结果分配在 context.allocator：report 每次都会清空 temp_allocator。
discover_shader_dirs :: proc(base: string, roots: []string) -> []Shader_Dir {
	result: [dynamic]Shader_Dir
	for root in roots {
		if os.is_dir(root) do collect_shader_dirs(base, root, &result)
	}
	slice.sort_by(result[:], proc(a, b: Shader_Dir) -> bool { return a.name < b.name })
	return result[:]
}

@(private = "file")
collect_shader_dirs :: proc(base, dir: string, result: ^[dynamic]Shader_Dir) {
	entries, err := os.read_all_directory_by_path(dir, context.allocator)
	if err != nil do return
	for e in entries {
		if e.type != .Directory do continue
		if strings.has_prefix(e.name, ".") || e.name == "build" || e.name == "library" do continue
		if e.name == "Compiled" {
			rel, rel_err := filepath.rel(base, dir)
			if rel_err != nil do rel = strings.clone(dir)
			name, _ := strings.replace_all(rel, "\\", "/")
			append(result, Shader_Dir{strings.clone(dir), name, os.is_file(path_join(e.fullpath, "sources.json"))})
			continue
		}
		collect_shader_dirs(base, e.fullpath, result)
	}
}

// 构建一次 tools/shaders，再对每个有记录的目录运行 -check。
check_shader_outputs :: proc(c: ^Checker, roots: []string) {
	base := path_clean(path_join(c.root, ".."))
	checked: [dynamic]Shader_Dir
	defer delete(checked)
	for d in discover_shader_dirs(base, roots) {
		name := fmt.tprintf("shader %s", d.name)
		if !selected(c, name) do continue
		if !d.recorded {
			fmt.printfln("skip   %s（Compiled 没有源码记录，用 tools/shaders 重新生成后才检查）", name)
			continue
		}
		append(&checked, d)
	}
	if len(checked) == 0 do return

	exe := path_join(c.out, fmt.tprintf("shaders%s", EXE))
	state, stdout, stderr, err := os.process_exec(
		{working_dir = c.root, command = {"odin", "build", "tools/shaders", fmt.tprintf("-out:%s", exe)}},
		context.temp_allocator,
	)
	built := err == nil && state.exited && state.exit_code == 0
	report(c, "build  tools/shaders", built, strings.concatenate({string(stdout), string(stderr)}, context.temp_allocator))
	if !built do return
	for d in checked {
		run(c, fmt.tprintf("shader %s", d.name), exe, "-check", fmt.tprintf("-dir:%s", d.path))
	}
}
