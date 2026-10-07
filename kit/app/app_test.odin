// app 包单元测试（不启动真实 stdin 线程；读取线程逻辑靠 dispatch/parse 直测）。
#+test
package app

import "core:testing"

import msg "olib:core/messaging"
import foster "olib:foster"

@(test)
has_arg_matches_flags :: proc(t: ^testing.T) {
	args := []string{"game.exe", "--Verbose", "-nofocus", "level1"}

	testing.expect(t, has_arg(args, "verbose"))       // -- 前缀 + 大小写
	testing.expect(t, has_arg(args, "nofocus"))       // - 前缀
	testing.expect(t, has_arg(args, "level1"))        // 裸词
	testing.expect(t, !has_arg(args, "missing"))
	testing.expect(t, !has_arg(args, "level")) // 前缀匹配不算
}

@(test)
cli_parse_line_splits :: proc(t: ^testing.T) {
	name, args, ok := cli_parse_line("spawn goblin 3 4")
	testing.expect(t, ok && name == "spawn" && args == "goblin 3 4")

	name2, args2, ok2 := cli_parse_line("help")
	testing.expect(t, ok2 && name2 == "help" && args2 == "")

	name3, args3, ok3 := cli_parse_line("  cmd   spaced  ")
	testing.expect(t, ok3 && name3 == "cmd" && args3 == "spaced")
}

@(private)
Echo_State :: struct {
	console: ^Cli_Console,
	got:     string,
}

@(private)
echo_handler :: proc(args: string, ud: rawptr) {
	state := (^Echo_State)(ud)
	delete(state.got)
	state.got = clone_owned(args)
}

@(test)
cli_dispatch_and_update_roundtrip :: proc(t: ^testing.T) {
	console: Cli_Console
	cli_init(&console)
	defer cli_dispose(&console)

	state: Echo_State
	defer delete(state.got)
	state.console = &console
	cli_register(&console, "Echo", "回显参数", echo_handler, &state)

	// 模拟读取线程收到一行：未知名报错不入队；已知名入队
	cli_dispatch_line(&console, clone_owned("echo hello world"))
	if !testing.expect(t, msg.queue_count(&console.queue) == 1) { return }

	// 主线程消费前不可见
	testing.expect(t, state.got == "")

	cli_update(&console)
	testing.expectf(t, state.got == "hello world", "执行后可见: %q", state.got)
	testing.expect(t, msg.queue_count(&console.queue) == 0)

	// 大小写不敏感注册键
	cli_dispatch_line(&console, clone_owned("ECHO again"))
	cli_update(&console)
	testing.expect(t, state.got == "again")
}

// ---------------------------------------------------------------------------
// CLI 接入 foster.App 与零值生命周期
// ---------------------------------------------------------------------------

@(test)
cli_quit_exits_foster_app :: proc(t: ^testing.T) {
	console: Cli_Console
	cli_init(&console)
	defer cli_dispose(&console)

	a: foster.App
	a.Running = true
	cli_register_quit(&console, &a)
	cli_dispatch_line(&console, clone_owned("quit"))
	testing.expect(t, !a.Exiting)
	cli_update(&console)
	testing.expect(t, a.Exiting)
}

@(test)
cli_zero_value_lifecycle :: proc(t: ^testing.T) {
	console: Cli_Console
	cli_update(&console)
	cli_dispose(&console)
	cli_dispose(&console)
	testing.expect(t, console.commands == nil && !console.running)
	testing.expect(t, console.thread == nil && msg.queue_count(&console.queue) == 0)
}
