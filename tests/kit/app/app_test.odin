// app 包单元测试（不启动真实 stdin 线程；读取线程逻辑靠 enqueue/parse 直测，跨线程用普通生产者线程）。
#+test
package app

import "core:mem"
import "core:os"
import "core:testing"
import "core:thread"

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
cli_enqueue_and_update_roundtrip :: proc(t: ^testing.T) {
	console: Cli_Console
	cli_init(&console)
	defer cli_dispose(&console)

	state: Echo_State
	defer delete(state.got)
	state.console = &console
	cli_register(&console, "Echo", "回显参数", echo_handler, &state)

	// 模拟读取线程收到一行：原样入列，主线程消费前不可见
	testing.expect(t, cli_enqueue_line(&console, "echo hello world"))
	testing.expect_value(t, len(console.pending), 1)
	testing.expect(t, state.got == "")

	cli_update(&console)
	testing.expectf(t, state.got == "hello world", "执行后可见: %q", state.got)
	testing.expect_value(t, len(console.pending), 0)

	// 大小写不敏感注册键；未知命令只提示、不执行
	testing.expect(t, cli_enqueue_line(&console, "ECHO again"))
	testing.expect(t, cli_enqueue_line(&console, "missing arg"))
	cli_update(&console)
	testing.expect(t, state.got == "again")

	// stop 后不再接收
	cli_stop(&console)
	testing.expect(t, !cli_enqueue_line(&console, "echo late"))
}

@(private)
CLI_THREAD_LINES :: 64

@(private)
cli_test_producer :: proc(data: rawptr) {
	// 本线程的 context.allocator 是默认堆，与主线程的 Tracking_Allocator 不同。
	console := (^Cli_Console)(data)
	for _ in 0..<CLI_THREAD_LINES {
		cli_enqueue_line(console, "count")
	}
}

@(private)
cli_test_count :: proc(_: string, ud: rawptr) {
	(^int)(ud)^ += 1
}

// 回归：读取线程分配的行由主线程释放；主线程开内存追踪时不得 bad free 或泄漏。
@(test)
cli_lines_from_another_thread_free_cleanly_under_tracking :: proc(t: ^testing.T) {
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	defer mem.tracking_allocator_destroy(&track)
	context.allocator = mem.tracking_allocator(&track)

	count: int
	{
		console: Cli_Console
		cli_init(&console)
		cli_register(&console, "count", "计数", cli_test_count, &count)
		producer := thread.create_and_start_with_data(&console, cli_test_producer)
		for !thread.is_done(producer) {
			cli_update(&console)
		}
		thread.destroy(producer)
		cli_update(&console)
		// 再送一行不执行，验证 dispose 释放未执行的行
		testing.expect(t, cli_enqueue_line(&console, "count"))
		cli_dispose(&console)
	}
	testing.expect_value(t, count, CLI_THREAD_LINES)
	testing.expect_value(t, len(track.bad_free_array), 0)
	testing.expect_value(t, len(track.allocation_map), 0)
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
	cli_enqueue_line(&console, "quit")
	testing.expect(t, !a.Exiting)
	cli_update(&console)
	testing.expect(t, a.Exiting)
}

@(test)
cli_zero_value_lifecycle :: proc(t: ^testing.T) {
	console: Cli_Console
	testing.expect(t, !cli_enqueue_line(&console, "help"))
	cli_update(&console)
	cli_dispose(&console)
	cli_dispose(&console)
	testing.expect(t, console.commands == nil && !console.started && !console.accepting)
	testing.expect(t, console.pending == nil && console.executing == nil)
}

@(test)
cli_open_without_stdin_cleans_up :: proc(t: ^testing.T) {
	previous_stdin := os.stdin
	os.stdin = nil
	defer os.stdin = previous_stdin
	console: Cli_Console
	a: foster.App
	testing.expect(t, !cli_open(&console, &a))
	cli_update(&console)
	cli_dispose(&console)
	testing.expect(t, console.commands == nil && !console.started && !console.accepting)
}
