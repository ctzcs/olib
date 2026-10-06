// app —— 启动模板与 CLI 辅助（对位 DragonLib GameApp）。
//
// ofoster 的 App 已经承担 Foster 的生命周期；本包在其上补：
//   - Game_App：using 嵌入 foster.App（字段全提升），回调升级为
//     proc(^Game_App)（桥接靠"using 字段在首位 => 地址相同"），
//     并自动接好 CLI 控制台（quit/每帧消费）与 userdata 挂载；
//   - has_arg：命令行参数判断（大小写不敏感）；
//   - Cli_Console：后台读 stdin 的调试控制台（命令转到主线程执行）。
//
// 分区：
//   CLI 参数 —— has_arg
//   调试控制台 —— 见 cli_console.odin
//   游戏模板 —— 见 game_app.odin
package app

import "core:strings"

// ------------------------------------------------------------------------------
// CLI 参数 —— has_arg
// ------------------------------------------------------------------------------

// 判断命令行参数里是否存在 name（--flag / -f / 裸词均可，大小写不敏感）。
has_arg :: proc(args: []string, name: string) -> bool {
	for arg in args {
		if eq_ignore_case(trim_leading_dashes(arg), name) {
			return true
		}
	}
	return false
}

@(private)
eq_ignore_case :: proc(a, b: string) -> bool {
	if len(a) != len(b) do return false
	for i in 0..<len(a) {
		ca := a[i] >= 'A' && a[i] <= 'Z' ? a[i] + ('a' - 'A') : a[i]
		cb := b[i] >= 'A' && b[i] <= 'Z' ? b[i] + ('a' - 'A') : b[i]
		if ca != cb do return false
	}
	return true
}

@(private)
trim_leading_dashes :: proc(s: string) -> string {
	i := 0
	for i < len(s) && (s[i] == '-' || s[i] == '/') {
		i += 1
	}
	return s[i:]
}
