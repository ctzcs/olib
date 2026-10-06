// app —— 启动模板与 CLI 辅助（对位 DragonLib GameApp）。
//
// ofoster 的 App 已经承担 Foster 的生命周期；本包在其上补：
//   - Game_App：using 嵌入 foster.App（字段全提升），回调升级为
//     proc(^Game_App)（桥接靠"using 字段在首位 => 地址相同"），
//     并自动接好 CLI 控制台（quit/每帧消费）与 userdata 挂载；
//   - Cli_Console：后台读 stdin 的调试控制台（命令转到主线程执行），
//     附 CLI 参数判断（has_arg）。
//
// 分区（按文件）：
//   game_app.odin    Game_App 模板与生命周期 / 桥接 trampoline
//   cli_console.odin 调试控制台 + has_arg
package app

import foster "ofoster:."

// 分区：
//   类型 —— Game_App / 用户回调签名
//   生命周期 —— init / run / dispose / exit
//   桥接 —— ^foster.App <-> ^Game_App 转换与 trampoline

// ------------------------------------------------------------------------------
// 类型
// ------------------------------------------------------------------------------

// 游戏侧回调：收 ^Game_App（比 ^foster.App 多了 console 等扩展字段）。
Game_App_Proc :: #type proc(g: ^Game_App)

Game_App :: struct {
	// using 字段必须在首位：^foster.App 与 ^Game_App 地址相同（桥接依赖此布局）。
	using App:    foster.App,

	startup:  Game_App_Proc,
	update:   Game_App_Proc,
	render:   Game_App_Proc,
	shutdown: Game_App_Proc,

	console:     Cli_Console,
	has_console: bool,

	userdata:    rawptr, // 游戏侧自由挂载（回调经它带状态，Odin 无闭包）
}

// 从 ofoster 回调里的 ^foster.App 取回外层 Game_App。
// 仅对 game_app_init 建立的、经 game_app_run 桥接的实例有效。
game_app_from :: proc(a: ^foster.App) -> (g: ^Game_App, ok: bool) {
	g = cast(^Game_App)a
	return g, g != nil
}

// ------------------------------------------------------------------------------
// 生命周期
// ------------------------------------------------------------------------------

// 初始化（InitApp + 零值扩展）。视口尺寸等在 startup 回调里按窗口取。
game_app_init :: proc(g: ^Game_App, title: string, width, height: int) {
	g^ = {}
	foster.init_app(&g.App, foster.DefaultAppConfig(title, width, height))
}

game_app_dispose :: proc(g: ^Game_App) {
	if g.has_console {
		cli_dispose(&g.console)
	}
	foster.dispose_app(&g.App)
	g^ = {}
}

// 退出（可在任意回调里调）。
game_app_exit :: proc(g: ^Game_App) {
	foster.Exit(&g.App)
}

// 启动主循环。enable_cli 时初始化调试控制台（自动注册 quit、每帧消费
// 命令；无 stdin 的环境静默跳过）。用户回调任意一个可为 nil。
game_app_run :: proc(
	g:            ^Game_App,
	startup:  Game_App_Proc,
	update:   Game_App_Proc,
	render:   Game_App_Proc,
	shutdown: Game_App_Proc,
	enable_cli := false,
) {
	g.startup = startup
	g.update = update
	g.render = render
	g.shutdown = shutdown

	if enable_cli {
		cli_init(&g.console)
		// quit 默认接真正的退出（这里持有 Game_App，不用调用方再注册）
		cli_register(&g.console, "quit", "退出程序", cli_builtin_game_quit, g)
		g.has_console = cli_start(&g.console)
	}

	g.App.StartupProc = trampoline_startup
	g.App.UpdateProc = trampoline_update
	g.App.RenderProc = trampoline_render
	g.App.ShutdownProc = trampoline_shutdown
	foster.Run(&g.App)
}

// ------------------------------------------------------------------------------
// 桥接 —— trampoline：^foster.App -> ^Game_App -> 用户回调
// ------------------------------------------------------------------------------

@(private)
trampoline_startup :: proc(a: ^foster.App) {
	g, ok := game_app_from(a)
	if !ok || g.startup == nil { return }
	g.startup(g)
}

@(private)
trampoline_update :: proc(a: ^foster.App) {
	g, ok := game_app_from(a)
	if !ok { return }
	if g.has_console {
		cli_update(&g.console) // 每帧消费命令（主线程执行）
	}
	if g.update != nil {
		g.update(g)
	}
}

@(private)
trampoline_render :: proc(a: ^foster.App) {
	g, ok := game_app_from(a)
	if !ok || g.render == nil { return }
	g.render(g)
}

@(private)
trampoline_shutdown :: proc(a: ^foster.App) {
	g, ok := game_app_from(a)
	if !ok { return }
	if g.shutdown != nil {
		g.shutdown(g)
	}
	if g.has_console {
		cli_stop(&g.console)
	}
}

@(private)
cli_builtin_game_quit :: proc(args: string, ud: rawptr) {
	g := (^Game_App)(ud)
	game_app_exit(g)
}
