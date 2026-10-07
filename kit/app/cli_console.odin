// app —— CLI 参数与后台调试控制台（对位 DragonLib CliConsole）。
//
// 后台线程读 stdin，命令经 Command_Queue 转到主线程——游戏每帧调一次
// cli_update（在 UpdateProc 里），handler 里可以安全读写游戏状态。
//
// 与 DragonLib 的差异：
//   - 不走 App.RunOnMainThread（Foster 的 AppCallback 无 userdata 参数），
//     改用 olib:messaging 的单消费者队列 + 每帧 drain，语义相同；
//   - cli_open / cli_register_quit 可把 quit 接到 foster.Exit；
//   - 单实例：thread.create 无 data 参数，控制台指针走包级 active 指针。
//
// 本文件还带包内的 CLI 参数判断（has_arg）。
package app

import "core:fmt"
import "core:os"
import "core:strings"
import "core:thread"

import msg "olib:core/messaging"
import foster "olib:foster"

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

// 分区：
//   类型与注册
//   生命周期 —— start / stop / dispose
//   主线程消费 —— cli_update
//   后台读取线程
//   行解析

// ------------------------------------------------------------------------------
// 类型与注册
// ------------------------------------------------------------------------------

// 命令处理函数：args 是命令名之后的剩余文本（已裁剪空白）。
Cli_Handler :: #type proc(args: string, userdata: rawptr)

Cli_Command :: struct {
	description: string,
	handler:     Cli_Handler,
	userdata:    rawptr,
}

// 一条待主线程执行的命令行；name/args 为队列拥有的克隆字符串，
// cli_update 执行完释放。
Cli_Line :: struct {
	name: string,
	args: string,
}

Cli_Console :: struct {
	commands: map[string]Cli_Command, // key 为小写命令名（克隆）

	queue:   msg.Command_Queue(Cli_Line),
	thread:  ^thread.Thread,
	running: bool,
}

cli_init :: proc(console: ^Cli_Console) {
	console^ = {
		commands = make(map[string]Cli_Command),
	}
	cli_register(console, "help", "列出全部命令", cli_builtin_help, console)
	cli_register(console, "quit", "退出程序（游戏应覆盖注册真正的退出）", cli_builtin_quit, nil)
}

// 一步开启控制台；quit_app 非 nil 时 quit 调用 foster.Exit。
// 开启前 console 应为零值或已 dispose；失败时释放资源，update / dispose 可安全调用。
cli_open :: proc(console: ^Cli_Console, quit_app: ^foster.App = nil) -> bool {
	cli_init(console)
	if quit_app != nil {
		cli_register_quit(console, quit_app)
	}
	if !cli_start(console) {
		cli_dispose(console)
		return false
	}
	return true
}

// 将 quit 命令接到 foster.Exit；app 必须在控制台使用期间保持有效。
cli_register_quit :: proc(console: ^Cli_Console, app: ^foster.App) {
	cli_register(console, "quit", "退出程序", cli_quit_app, app)
}

cli_dispose :: proc(console: ^Cli_Console) {
	cli_stop(console)
	msg.queue_clear(&console.queue) // 未执行的命令直接丢弃
	msg.queue_dispose(&console.queue)
	for key in console.commands {
		delete(key, context.allocator)
	}
	for _, cmd in console.commands {
		delete(cmd.description, context.allocator)
	}
	delete(console.commands)
	console^ = {}
}

// 注册命令（名字大小写不敏感，重复注册覆盖）。需在 cli_start 前或
// 主线程里调用（注册表无锁）。
cli_register :: proc(console: ^Cli_Console, name: string, description: string, handler: Cli_Handler, userdata: rawptr = nil) {
	lower, _ := strings.to_lower(name, context.allocator)
	if previous, had := console.commands[lower]; had {
		delete(previous.description, context.allocator)
		// 复用注册表持有的键，覆盖时不遗留旧键或新克隆。
		for key in console.commands {
			if key == lower {
				delete(lower, context.allocator)
				lower = key
				break
			}
		}
	}
	console.commands[lower] = Cli_Command{
		description = clone_owned(description),
		handler     = handler,
		userdata    = userdata,
	}
}

// ------------------------------------------------------------------------------
// 生命周期 —— start / stop
// ------------------------------------------------------------------------------

// 启动后台读取线程（幂等）。stdin 不可用的环境直接返回 false。
cli_start :: proc(console: ^Cli_Console) -> bool {
	if console.thread != nil do return true
	if os.stdin == nil do return false

	active_cli_console = console
	console.running = true
	console.thread = thread.create(cli_reader_loop)
	if console.thread == nil {
		console.running = false
		active_cli_console = nil
		return false
	}
	thread.start(console.thread)
	fmt.println("[cli] CLI 调试控制台已启动，输入 help 查看命令")
	return true
}

// 停止读取线程。注意：阻塞中的 stdin 读取要等到下一行输入或 EOF 才返回；
// 进程退出时线程随进程结束。
cli_stop :: proc(console: ^Cli_Console) {
	console.running = false
}

// ------------------------------------------------------------------------------
// 主线程消费 —— cli_update
// ------------------------------------------------------------------------------

// 每帧调用：执行已入队的命令（执行完释放条目的字符串）。
cli_update :: proc(console: ^Cli_Console) {
	_ = msg.queue_drain(&console.queue, cli_execute, console)
}

@(private)
cli_execute :: proc(line: Cli_Line, ud: rawptr) {
	console := (^Cli_Console)(ud)
	if cmd, ok := console.commands[line.name]; ok {
		if cmd.handler != nil {
			cmd.handler(line.args, cmd.userdata)
		}
	}
	delete(line.name, context.allocator)
	delete(line.args, context.allocator)
}

// ------------------------------------------------------------------------------
// 后台读取线程
// ------------------------------------------------------------------------------

// thread.create 无 data 参数，控制台指针走包级 active 指针（单实例）。
@(private)
active_cli_console: ^Cli_Console

@(private)
cli_reader_loop :: proc(t: ^thread.Thread) {
	console := active_cli_console

	buf: [256]u8
	pending: [dynamic]u8
	defer delete(pending)

	for console.running {
		n, err := os.read(os.stdin, buf[:])
		if err != nil || n <= 0 {
			break // stdin 关闭（管道结束 / 无控制台）
		}
		for i in 0..<n {
			if buf[i] == '\n' {
				line := clone_owned(string(pending[:]))
				cli_dispatch_line(console, line)
				clear(&pending)
				continue
			}
			if buf[i] != '\r' {
				append(&pending, buf[i])
			}
		}
	}
}

// 解析一行输入：已知命令克隆入队，未知命令当场提示（读取线程侧）。
@(private)
cli_dispatch_line :: proc(console: ^Cli_Console, line: string) {
	defer delete(line)
	trimmed := strings.trim_space(line)
	if len(trimmed) == 0 do return

	name, args, ok := cli_parse_line(trimmed)
	if !ok do return

	lower, _ := strings.to_lower(name, context.allocator)
	if _, known := console.commands[lower]; !known {
		fmt.eprintf("[cli] 未知命令 '%s'，输入 help 查看命令列表\n", name)
		delete(lower, context.allocator)
		return
	}

	// 入队存小写名（注册表的键即小写），所有权转移给队列条目
	msg.queue_enqueue(&console.queue, Cli_Line{
		name = lower,
		args = clone_owned(args),
	})
}

// ------------------------------------------------------------------------------
// 行解析
// ------------------------------------------------------------------------------

// "cmd rest of line" -> ("cmd", "rest of line")；输入保证非空。
cli_parse_line :: proc(line_: string) -> (name: string, args: string, ok: bool) {
	line := strings.trim_space(line_)
	sep := strings.index(line, " ")
	if sep < 0 {
		return line, "", true
	}
	name = strings.trim_space(line[:sep])
	args = strings.trim_space(line[sep + 1:])
	if len(name) == 0 do return "", "", false
	return name, args, true
}

// ------------------------------------------------------------------------------
// 内建命令
// ------------------------------------------------------------------------------

@(private)
cli_builtin_help :: proc(args: string, ud: rawptr) {
	console := (^Cli_Console)(ud)
	fmt.println("[cli] 命令列表:")
	for name, cmd in console.commands {
		fmt.printfln("  %-12s %s", name, cmd.description)
	}
}

@(private)
cli_builtin_quit :: proc(args: string, ud: rawptr) {
	fmt.println("[cli] （默认 quit：请用 cli_register_quit 接入 foster.App）")
}

@(private)
cli_quit_app :: proc(args: string, ud: rawptr) {
	app := (^foster.App)(ud)
	if app != nil {
		foster.Exit(app)
	}
}

// ------------------------------------------------------------------------------
// 内部
// ------------------------------------------------------------------------------

@(private)
clone_owned :: proc(s: string) -> string {
	out, _ := strings.clone(s, context.allocator)
	return out
}
