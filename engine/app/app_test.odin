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
// Game_App —— 桥接与字段提升（不开窗口，直测 trampoline）
// ---------------------------------------------------------------------------

@(private)
Bridge_State :: struct {
	startups:                    int,
	updates:                     int,
	shutdowns:                   int,
	console_running_on_shutdown: bool,
}

@(private)
bridge_startup :: proc(a: ^foster.App) {
	s := (^Bridge_State)(a.UserData)
	if s != nil {
		s.startups += 1
	}
}

@(private)
bridge_update :: proc(a: ^foster.App) {
	s := (^Bridge_State)(a.UserData)
	if s != nil {
		s.updates += 1
	}
}

@(private)
bridge_shutdown :: proc(a: ^foster.App) {
	s := (^Bridge_State)(a.UserData)
	if s != nil {
		s.shutdowns += 1
		s.console_running_on_shutdown = game_app_from(a).console.running
	}
}

@(test)
game_app_trampoline_bridge :: proc(t: ^testing.T) {
	g: Game_App
	state: Bridge_State

	g.StartupProc = bridge_startup
	g.update = bridge_update

	// 桥接：^foster.App 视图 -> ^Game_App（using 字段在首位，地址相同）
	app_view := &g.App
	back := game_app_from(app_view)
	testing.expect(t, back == (&g))

	// 未挂 UserData：用户回调安全空转
	g.StartupProc(&g.App)
	trampoline_update(&g.App)
	testing.expect(t, state.startups == 0 && state.updates == 0)

	// 挂上后回调可达
	g.UserData = &state
	g.StartupProc(&g.App)
	trampoline_update(&g.App)
	testing.expect(t, state.startups == 1 && state.updates == 1)

	// 字段提升：Game_App 直接看到 App 的字段（Window/Time/GraphicsDevice）
	_ = g.Window
	_ = g.Time
	_ = g.GraphicsDevice
	testing.expect(t, g.has_console == false)

	// 不启动 stdin 线程，验证 CLI 消费和 shutdown 后停止。
	cli_init(&g.console)
	defer cli_dispose(&g.console)
	g.has_console = true
	g.console.running = true
	echo: Echo_State
	defer delete(echo.got)
	cli_register(&g.console, "echo", "回显参数", echo_handler, &echo)
	cli_dispatch_line(&g.console, clone_owned("echo bridge"))
	trampoline_update(&g.App)
	testing.expect(t, echo.got == "bridge" && state.updates == 2)

	g.shutdown = bridge_shutdown
	trampoline_shutdown(&g.App)
	testing.expect(t, state.shutdowns == 1 && state.console_running_on_shutdown)
	testing.expect(t, !g.console.running)
	testing.expect(t, g.UserData == rawptr(&state))

	// nil 回调安全
	g.update = nil
	g.shutdown = nil
	trampoline_update(&g.App)
	trampoline_shutdown(&g.App)
	testing.expect(t, state.updates == 2 && state.shutdowns == 1)
}
