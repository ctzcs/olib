// tools/shaders —— 用 SDL_shadercross 编译一个目录下的 HLSL（Odin 实现，跨平台）。
//
// 用法：
//   odin run tools/shaders                         编译 kit/rendering/3d/shaders（DebugLine3D）
//   odin run <olib>/tools/shaders -- -dir:<目录>   编译游戏/示例自己的着色器目录（相对当前目录）
//   odin run tools/shaders -- -dir:foster/assets/shaders  重建 Foster 三组默认 shader
// 目录归属与源码/产物规则见同目录 README.md。
//
// 流程与上游 Foster 的 compile.sh 一致：目录下每个 *.hlsl（跳过 *.hlsli）的
// vertex / fragment 两个阶段，先 HLSL -> .spv，再 .spv -> .dxil 与 .spv -> .msl，
// 产物写到 <目录>/Compiled。入口函数固定为 vertex_main / fragment_main。
// shadercross 需在 PATH 上。Web（GLSL ES）是手写的，不在这里。
package main

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strings"

import lang "../../kit/rendering/shader/lang"

// 分区：
//   入口 —— 参数解析 / 逐文件编译
//   shadercross 调用

// ==============================================================================
// 入口
// ==============================================================================

main :: proc() {
	dir := ""
	// PowerShell 会把 `-dir:x` 拆成 `-dir:` 与 `x` 两个参数，值为空时取下一个参数。
	args := os.args[1:]
	for i := 0; i < len(args); i += 1 {
		arg := args[i]
		if arg == "-dir" || strings.has_prefix(arg, "-dir:") {
			dir = strings.trim_prefix(strings.trim_prefix(arg, "-dir"), ":")
			if len(dir) == 0 && i + 1 < len(args) {
				i += 1
				dir = args[i]
			}
			continue
		}
		fmt.eprintfln("未知参数: %s", arg)
		fmt.eprintln("用法: odin run tools/shaders [-- -dir:<着色器目录>]")
		os.exit(2)
	}

	if len(dir) == 0 {
		dir = path_join(#directory, "..", "..", "kit", "rendering", "3d", "shaders")
	} else if !filepath.is_abs(dir) {
		cwd, err := os.get_working_directory(context.allocator)
		assert(err == nil)
		dir = path_join(cwd, dir)
	}
	dir = path_clean(dir)

	entries, err := os.read_all_directory_by_path(dir, context.allocator)
	if err != nil {
		fmt.eprintfln("无法读取目录 %s: %v", dir, err)
		os.exit(1)
	}
	sources: [dynamic]string
	for e in entries {
		if e.type == .Regular && (strings.has_suffix(e.name, ".hlsl") || strings.has_suffix(e.name, ".oshader")) {
			append(&sources, e.name)
		}
	}
	if len(sources) == 0 {
		fmt.eprintfln("%s 下没有 .hlsl 或 .oshader 文件", dir)
		os.exit(1)
	}
	slice.sort(sources[:])
	// 在写任何产物之前检测命名冲突，禁止 .hlsl 和 .oshader 悄悄覆盖同一字节码。
	outputs := make(map[string]bool)
	for name in sources {
		if strings.has_suffix(name, ".hlsl") {
			reserve_output(&outputs, strings.trim_suffix(name, ".hlsl"))
		} else {
			doc := read_shader(path_join(dir, name))
			for schema in doc.schemas {
				reserve_output(&outputs, schema.name)
			}
			reserve_output(&outputs, fmt.tprintf("%s.shader.json", doc.effect.name))
			lang.dispose(&doc)
		}
	}

	out := path_join(dir, "Compiled")
	if mk_err := os.make_directory_all(out); mk_err != nil {
		fmt.eprintfln("无法创建 %s: %v", out, mk_err)
		os.exit(1)
	}

	for name in sources {
		src := path_join(dir, name)
		if strings.has_suffix(name, ".oshader") {
			if !compile_shader(src, dir, out) {
				os.exit(1)
			}
			continue
		}
		stem := strings.trim_suffix(name, ".hlsl")
		for stage in ([]string{"vertex", "fragment"}) {
			base := path_join(out, fmt.tprintf("%s.%s", stem, stage))
			entry := fmt.tprintf("%s_main", stage)
			spv := fmt.tprintf("%s.spv", base)
			if !shadercross(src, "-s", "HLSL", "-d", "SPIRV", "-t", stage, "-e", entry, "-I", dir, "-o", spv) ||
				!shadercross(spv, "-s", "SPIRV", "-d", "DXIL", "-t", stage, "-e", entry, "-o", fmt.tprintf("%s.dxil", base)) ||
				!shadercross(spv, "-s", "SPIRV", "-d", "MSL", "-t", stage, "-e", entry, "-o", fmt.tprintf("%s.msl", base)) {
				os.exit(1)
			}
		}
		fmt.printfln("compiled %s", name)
		free_all(context.temp_allocator)
	}
}

// ==============================================================================
// shadercross 调用
// ==============================================================================

// 运行一次 shadercross；失败返回 false，让调用方先清理临时文件再退出。
shadercross :: proc(args: ..string) -> bool {
	command := make([]string, len(args) + 1, context.temp_allocator)
	command[0] = "shadercross"
	copy(command[1:], args)

	state, stdout, stderr, err := os.process_exec({command = command}, context.temp_allocator)
	if err != nil {
		fmt.eprintfln("无法运行 shadercross（需要在 PATH 上）: %v", err)
		return false
	}
	if !state.exited || state.exit_code != 0 {
		fmt.eprintfln("shadercross 失败: %s", strings.join(command, " ", context.temp_allocator))
		fmt.eprint(string(stdout))
		fmt.eprint(string(stderr))
		return false
	}
	return true
}

// filepath.join / clean 额外返回 Allocator_Error；工具里分配失败直接视为致命。
path_join :: proc(elems: ..string) -> string {
	p, err := filepath.join(elems)
	assert(err == nil)
	return p
}

path_clean :: proc(path: string) -> string {
	p, err := filepath.clean(path)
	assert(err == nil)
	return p
}
