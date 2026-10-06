// app 包单元测试（不启动真实 stdin 线程；读取线程逻辑靠 dispatch/parse 直测）。
#+test
package app

import "core:testing"

import msg "olib:engine/messaging"

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
	state.got = args
}

@(test)
cli_dispatch_and_update_roundtrip :: proc(t: ^testing.T) {
	console: Cli_Console
	cli_init(&console)
	defer cli_dispose(&console)

	state: Echo_State
	state.console = &console
	cli_register(&console, "Echo", "回显参数", echo_handler, &state)

	// 模拟读取线程收到一行：未知名报错不入队；已知名入队
	cli_dispatch_line(&console, "echo hello world")
	if !testing.expect(t, msg.queue_count(&console.queue) == 1) { return }

	// 主线程消费前不可见
	testing.expect(t, state.got == "")

	cli_update(&console)
	testing.expectf(t, state.got == "hello world", "执行后可见: %q", state.got)
	testing.expect(t, msg.queue_count(&console.queue) == 0)

	// 大小写不敏感注册键
	cli_dispatch_line(&console, "ECHO again")
	cli_update(&console)
	testing.expect(t, state.got == "again")
}

// ---------------------------------------------------------------------------
// Game_App —— 桥接与字段提升（不开窗口，直测 trampoline）
// ---------------------------------------------------------------------------

@(private)
Bridge_State :: struct {
	startups: int,
	updates:  int,
}

@(private)
bridge_startup :: proc(g: ^Game_App) {
	s := (^Bridge_State)(g.userdata)
	if s != nil { s.startups += 1 }
}

@(private)
bridge_update :: proc(g: ^Game_App) {
	s := (^Bridge_State)(g.userdata)
	if s != nil { s.updates += 1 }
}

@(test)
game_app_trampoline_bridge :: proc(t: ^testing.T) {
	g: Game_App
	state: Bridge_State

	g.user_startup = bridge_startup
	g.user_update = bridge_update

	// 桥接：^foster.App 视图 -> ^Game_App（using 字段在首位，地址相同）
	app_view := &g.App
	back, ok := game_app_from(app_view)
	testing.expect(t, ok && back == (&g))

	// 未挂 userdata：trampoline 安全空转
	trampoline_startup(&g.App)
	trampoline_update(&g.App)
	testing.expect(t, state.startups == 0 && state.updates == 0)

	// 挂上后回调可达
	g.userdata = &state
	trampoline_startup(&g.App)
	trampoline_update(&g.App)
	testing.expect(t, state.startups == 1 && state.updates == 1)

	// 字段提升：Game_App 直接看到 App 的字段（Window/Time/GraphicsDevice）
	_ = g.Window
	_ = g.Time
	_ = g.GraphicsDevice
	testing.expect(t, g.has_console == false)

	// nil 回调安全
	g.user_startup = nil
	trampoline_startup(&g.App)
	testing.expect(t, state.startups == 1)
}
