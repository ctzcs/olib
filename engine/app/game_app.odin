// app —— 启动模板与 CLI 辅助（对位 DragonLib GameApp）。
//
// ofoster 的 App 已经承担 Foster 的生命周期；本包在其上补：
//   - Game_App：using 嵌入 foster.App（字段全提升），回调使用
//     foster.AppCallback，游戏状态统一挂在 App.UserData；
//     可选 CLI 控制台自动接好 quit、每帧消费与退出时停止；
//   - Cli_Console：后台读 stdin 的调试控制台（命令转到主线程执行），
//     附 CLI 参数判断（has_arg）。
//
// 分区（按文件）：
//   game_app.odin    Game_App 模板与生命周期 / 桥接 trampoline
//   cli_console.odin 调试控制台 + has_arg
package app

import foster "ofoster:."

// 分区：
//   类型 —— Game_App / App 视图转换
//   生命周期 —— init / run / dispose / exit
//   CLI —— enable / update 与 shutdown trampoline

// ------------------------------------------------------------------------------
// 类型
// ------------------------------------------------------------------------------

Game_App :: struct {
	// using 字段必须在首位：^foster.App 与 ^Game_App 地址相同（桥接依赖此布局）。
	using App: foster.App,

	update:   foster.AppCallback,
	shutdown: foster.AppCallback,

	console:     Cli_Console,
	has_console: bool,
}

// 从 ofoster 回调里的 ^foster.App 取回外层 Game_App。
// 仅对 game_app_init 建立的、经 game_app_run 桥接的实例有效。
// 只做布局转换，不验证 a 的来源；普通 foster.App 不可传入。
game_app_from :: proc(a: ^foster.App) -> ^Game_App {
	return cast(^Game_App)a
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

// 启动主循环。回调接收 ^foster.App，通过 UserData 访问游戏状态。
// 用户回调任意一个可为 nil；CLI 可在运行前用 game_app_enable_cli 开启。
game_app_run :: proc(
	g:        ^Game_App,
	startup:  foster.AppCallback,
	update:   foster.AppCallback,
	render:   foster.AppCallback,
	shutdown: foster.AppCallback,
) {
	g.update = update
	g.shutdown = shutdown

	g.App.StartupProc = startup
	g.App.UpdateProc = trampoline_update
	g.App.RenderProc = render
	g.App.ShutdownProc = trampoline_shutdown
	foster.Run(&g.App)
}

// ------------------------------------------------------------------------------
// CLI —— 开启 / 每帧消费 / 退出时停止
// ------------------------------------------------------------------------------

// 开启调试控制台（幂等），自动注册 quit。无 stdin 时释放初始化资源。
game_app_enable_cli :: proc(g: ^Game_App) {
	if g.has_console do return
	cli_init(&g.console)
	cli_register(&g.console, "quit", "退出程序", cli_builtin_game_quit, g)
	g.has_console = cli_start(&g.console)
	if !g.has_console {
		cli_dispose(&g.console)
	}
}

@(private)
trampoline_update :: proc(a: ^foster.App) {
	g := game_app_from(a)
	if g == nil do return
	if g.has_console {
		cli_update(&g.console) // 每帧消费命令（主线程执行）
	}
	if g.update != nil {
		g.update(a)
	}
}

@(private)
trampoline_shutdown :: proc(a: ^foster.App) {
	g := game_app_from(a)
	if g == nil do return
	if g.shutdown != nil {
		g.shutdown(a)
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
