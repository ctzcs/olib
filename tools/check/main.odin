// tools/check —— olib 提交前一键检查（Odin 实现，跨平台）。
//
// 用法（任意目录；olib 根目录由编译期的 #directory 推出）：
//   odin run tools/check                     全部检查
//   odin run tools/check -- -no-samples      跳过同级 olib_sample 示例的编译与测试
//   odin run tools/check -- -only:<子串>     只运行名称含该子串的检查项（如 -only:local）
//
// 每项通过打印 `ok    <名称>`，失败打印 `FAIL  <名称>` 及该项完整输出；
// 任一项失败时退出码为 1。产物写到 build/check/。
// 只依赖 core:*，不 import olib 自己的包，避免工具被它要检查的代码弄坏。
package main

import "core:fmt"
import tokenizer "core:odin/tokenizer"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strings"

// 分区：
//   入口 —— 参数解析 / 检查顺序 / 汇总
//   检查项执行 —— 子进程运行 / 过滤 / 结果打印（LOCAL_CHANGES 校验见 local_changes.odin）
//   包发现 —— core/ kit/ tools/ 与 olib_sample/src
//   路径 —— join / clean 的单返回值包装

EXE :: ".exe" when ODIN_OS == .Windows else ""

// ==============================================================================
// 入口
// ==============================================================================

Checker :: struct {
	root:   string, // olib 根目录（绝对路径），所有子进程的工作目录
	out:    string, // build/check 绝对路径
	only:   string, // 非空时只运行名称含此子串的检查项
	passed: int,
	failed: [dynamic]string,
}

main :: proc() {
	c: Checker
	no_samples := false
	// PowerShell 会把 `-only:x` 拆成 `-only:` 与 `x` 两个参数传给原生程序，
	// 所以值为空时取下一个参数；`-only x` 写法同样接受。
	args := os.args[1:]
	for i := 0; i < len(args); i += 1 {
		arg := args[i]
		switch {
		case arg == "-no-samples":
			no_samples = true
		case arg == "-only" || strings.has_prefix(arg, "-only:"):
			c.only = strings.trim_prefix(strings.trim_prefix(arg, "-only"), ":")
			if len(c.only) == 0 && i + 1 < len(args) {
				i += 1
				c.only = args[i]
			}
		case:
			fmt.eprintfln("未知参数: %s", arg)
			fmt.eprintln("用法: odin run tools/check [-- -no-samples] [-- -only:<子串>]")
			os.exit(2)
		}
	}

	c.root = path_clean(path_join(#directory, "..", ".."))
	c.out = path_join(c.root, "build", "check")
	if err := os.make_directory_all(c.out); err != nil {
		fmt.eprintfln("无法创建 %s: %v", c.out, err)
		os.exit(1)
	}

	// ---- 包检查：core/ 与 kit/ 下所有包（含没有测试的包），以及 tools/ 下的工具 ----
	packages := discover_packages(c.root, {"core", "kit"})
	for p in packages {
		if p.has_tests {
			report(&c, fmt.tprintf("layout %s", p.path), false,
				"Move package tests into tests/<package path>; source packages must not contain @(test).")
		}
		run(&c, fmt.tprintf("check  %s", p.path),
			"odin", "check", p.path, "-collection:olib=.", "-no-entry-point", "-vet",
			fmt.tprintf("-vet-packages:%s", p.name))
	}
	for p in discover_packages(c.root, {"tools"}) {
		// 工具是 package main，有入口，不加 -no-entry-point
		run(&c, fmt.tprintf("check  %s", p.path),
			"odin", "check", p.path, "-vet", fmt.tprintf("-vet-packages:%s", p.name))
	}

	// ---- 集中单元测试：tests/core、tests/kit，与对应生产包在隔离目录中编译 ----
	for p in discover_packages(c.root, {"tests/core", "tests/kit", "tests/tools"}) {
		if p.has_tests do run_unit(&c, p)
	}

	// ---- 新游戏模板：全新生成、覆盖保护、游戏三种入口编译 ----
	run(&c, "test   new-game template generation and builds",
		"odin", "run", "tests/new_game", "-vet", "-vet-packages:main",
		fmt.tprintf("-out:%s/new_game_regression%s", c.out, EXE))

	// ---- foster：包检查 + 自带回归程序编译 ----
	// foster/ 的实际 package 声明为 foster_framework，vet 必须按包名选择。
	run(&c, "check  foster",
		"odin", "check", "foster", "-collection:olib=.", "-no-entry-point", "-vet",
		"-vet-packages:foster_framework")
	for t in ([]string{"port_regression", "graphics_regression", "webtest"}) {
		run(&c, fmt.tprintf("build  foster/tests/%s", t),
			"odin", "build", fmt.tprintf("foster/tests/%s", t), "-collection:olib=.",
			fmt.tprintf("-out:%s/%s%s", c.out, t, EXE))
	}
	if selected(&c, "local  foster LOCAL_CHANGES") {
		ok, log := check_local_changes(c.root)
		report(&c, "local  foster LOCAL_CHANGES", ok, log)
	}

	// ---- thirdparty 中依赖 foster 的绑定示例 ----
	run(&c, "check  clay pure Odin",
		"odin", "check", "thirdparty/clay-odin", "-no-entry-point", "-vet",
		"-vet-packages:clay")
	run(&c, "test   clay C v0.14 parity",
		"odin", "test", "thirdparty/clay-odin/tests", "-vet",
		"-vet-packages:clay,clay_tests",
		fmt.tprintf("-out:%s/test_clay%s", c.out, EXE))
	run(&c, "build  odin-imgui ofoster example",
		"odin", "build", "thirdparty/odin-imgui/examples/ofoster", "-collection:olib=.",
		fmt.tprintf("-out:%s/imgui_ofoster%s", c.out, EXE))

	// ---- 同级示例仓库（存在时） ----
	if !no_samples {
		samples := path_clean(path_join(c.root, "..", "olib_sample"))
		src := path_join(samples, "src")
		if os.is_dir(src) {
			for s in discover_samples(src) {
				run(&c, fmt.tprintf("sample %s", s.name),
					"odin", "build", s.path, fmt.tprintf("-collection:olib=%s", c.root),
					fmt.tprintf("-out:%s/sample_%s%s", c.out, s.name, EXE))
				if s.name == "hotreload" {
					extension := ODIN_OS == .Windows ? "dll" : ODIN_OS == .Darwin ? "dylib" : "so"
					run(&c, "sample hotreload game DLL",
						"odin", "build", path_join(s.path, "game"), "-build-mode:dll",
						fmt.tprintf("-collection:olib=%s", c.root), "-vet",
						"-vet-packages:game,contract",
						fmt.tprintf("-out:%s/sample_hotreload_game.%s", c.out, extension))
				}
				if s.has_tests {
					run(&c, fmt.tprintf("test   sample %s", s.name),
						"odin", "test", s.path, fmt.tprintf("-collection:olib=%s", c.root),
						fmt.tprintf("-out:%s/test_sample_%s%s", c.out, s.name, EXE))
				}
			}
		} else {
			fmt.printfln("skip   olib_sample（未在 %s 找到）", samples)
		}
	}

	// ---- 汇总 ----
	fmt.println()
	if len(c.failed) > 0 {
		fmt.printfln("%d 项失败，%d 项通过：", len(c.failed), c.passed)
		for name in c.failed {
			fmt.printfln("  %s", name)
		}
		os.exit(1)
	}
	fmt.printfln("全部 %d 项通过", c.passed)
}

// ==============================================================================
// 检查项执行
// ==============================================================================

// 在 olib 根目录运行一条命令作为一个检查项。
run :: proc(c: ^Checker, name: string, command: ..string) {
	if !selected(c, name) do return

	state, stdout, stderr, err := os.process_exec(
		{working_dir = c.root, command = command},
		context.temp_allocator,
	)
	log := strings.concatenate({string(stdout), string(stderr)}, context.temp_allocator)
	if err != nil {
		log = fmt.tprintf("无法运行 %s: %v\n%s", command[0], err, log)
	}
	report(c, name, err == nil && state.exited && state.exit_code == 0, log)
}

// -only 过滤：未指定时全部运行。
selected :: proc(c: ^Checker, name: string) -> bool {
	return len(c.only) == 0 || strings.contains(name, c.only)
}

// 记录一项结果。日志只在失败时打印，避免淹没结果；之后释放临时分配器
//（名称、参数、日志都分配在其中）。
report :: proc(c: ^Checker, name: string, ok: bool, log: string) {
	defer free_all(context.temp_allocator)
	if ok {
		fmt.printfln("ok    %s", name)
		c.passed += 1
		return
	}
	fmt.printfln("FAIL  %s", name)
	if trimmed := strings.trim_right_space(log); len(trimmed) > 0 {
		fmt.println(trimmed)
	}
	append(&c.failed, strings.clone(name))
}

// ==============================================================================
// 包发现
// ==============================================================================

Package :: struct {
	path:      string, // 相对 olib 根目录，用 / 分隔（示例为绝对路径）
	name:      string, // 源码 package 声明，即 -vet-packages 的包名（示例为目录名）
	has_tests: bool,   // core/kit 包：含 @(test)；示例：含 *_test.odin
}

// 递归找出 dirs 下所有含 .odin 文件的目录，按路径不区分大小写排序。
discover_packages :: proc(root: string, dirs: []string) -> []Package {
	result: [dynamic]Package
	for dir in dirs {
		collect_packages(root, dir, &result)
	}
	slice.sort_by(result[:], proc(a, b: Package) -> bool {
		return strings.to_lower(a.path, context.temp_allocator) < strings.to_lower(b.path, context.temp_allocator)
	})
	return result[:]
}

@(private = "file")
collect_packages :: proc(root, rel: string, result: ^[dynamic]Package) {
	entries, err := os.read_all_directory_by_path(path_join(root, rel), context.allocator)
	if err != nil do return

	has_odin, has_tests := false, false
	name := ""
	for e in entries {
		if e.type == .Directory {
			collect_packages(root, strings.concatenate({rel, "/", e.name}), result)
			continue
		}
		if !strings.has_suffix(e.name, ".odin") do continue
		has_odin = true
		if !has_tests || name == "" {
			data, read_err := os.read_entire_file(e.fullpath, context.temp_allocator)
			if read_err == nil {
				has_tests = has_tests || strings.contains(string(data), "@(test)")
				if name == "" do name = source_package_name(string(data), e.fullpath)
			}
		}
	}
	if has_odin {
		append(result, Package{path = rel, name = strings.clone(name), has_tests = has_tests})
	}
}

// 目录名可以是 2d/3d，工具目录也不一定叫 main；vet 始终使用实际包名。
@(private)
source_package_name :: proc(source, path: string) -> string {
	lexer: tokenizer.Tokenizer
	tokenizer.init(&lexer, source, path)
	found := false
	for {
		token := tokenizer.scan(&lexer)
		if token.kind == .EOF do return ""
		if token.kind == .Comment do continue
		if found {
			if token.kind == .Ident do return token.text
			return ""
		}
		if token.kind == .Package do found = true
	}
}

// olib_sample/src 下每个子目录是一个示例；含 *_test.odin 的额外跑单元测试。
discover_samples :: proc(src: string) -> []Package {
	entries, err := os.read_all_directory_by_path(src, context.allocator)
	if err != nil do return nil

	result: [dynamic]Package
	for e in entries {
		if e.type != .Directory do continue
		files, _ := os.read_all_directory_by_path(e.fullpath, context.temp_allocator)
		has_tests := false
		for f in files {
			if f.type != .Directory && strings.has_suffix(f.name, "_test.odin") {
				has_tests = true
				break
			}
		}
		append(&result, Package{path = strings.clone(e.fullpath), name = strings.clone(e.name), has_tests = has_tests})
	}
	slice.sort_by(result[:], proc(a, b: Package) -> bool {
		return strings.to_lower(a.name, context.temp_allocator) < strings.to_lower(b.name, context.temp_allocator)
	})
	return result[:]
}

// ==============================================================================
// 路径
// ==============================================================================

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
