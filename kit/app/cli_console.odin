// app —— CLI 参数与后台调试控制台（对位 DragonLib CliConsole）。
//
// 后台线程读 stdin，原始行经加锁的待处理列表转到主线程——游戏每帧调一次
// cli_update（在 UpdateProc 里），handler 里可以安全读写游戏状态。
//
// 线程边界：读取线程只做"克隆一行、加锁入列"，不读命令表；查找命令、
// 转小写和未知命令提示都在主线程。跨线程的字符串与列表固定用 init 时记下的
// runtime.heap_allocator（线程安全），不用任一侧的 context.allocator——
// 调用方的 Tracking_Allocator 等不是线程安全的，也不认另一线程分配的内存。
//
// 与 DragonLib 的差异：
//   - 不走 App.RunOnMainThread（Foster 的 AppCallback 无 userdata 参数），
//     改用互斥锁保护的待处理列表 + 每帧取出执行，语义相同；
//   - cli_open / cli_register_quit 可把 quit 接到 foster.Exit。
//
// 本文件还带包内的 CLI 参数判断（has_arg）。
package app

import "base:runtime"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:sync"
import "core:thread"

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

Cli_Console :: struct {
	commands: map[string]Cli_Command, // key 为小写命令名（克隆）；只在主线程读写

	// 以下四项跨线程，由 mutex 保护；pending 及其字符串归 allocator。
	mutex:     sync.Mutex,
	allocator: runtime.Allocator, // 零值表示未初始化或已 dispose，入列直接丢弃
	pending:   [dynamic]string,   // 读取线程送来、尚未执行的原始行
	accepting: bool,              // cli_stop 后不再接收，读取线程随下一行退出

	executing: [dynamic]string, // 主线程独占：cli_update 与 pending 交换后逐条执行
	started:   bool,            // 读取线程已启动（线程自清理，不 join）
}

cli_init :: proc(console: ^Cli_Console) {
	heap := runtime.heap_allocator()
	console.commands = make(map[string]Cli_Command)
	console.allocator = heap
	console.pending = make([dynamic]string, heap)
	console.executing = make([dynamic]string, heap)
	console.accepting = true
	console.started = false
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

// 释放全部资源。读取线程可能仍阻塞在 stdin 上：它之后送来的行被丢弃，
// 线程随即退出。mutex 不清零，console 须保持地址有效直到进程退出或线程结束。
cli_dispose :: proc(console: ^Cli_Console) {
	sync.mutex_lock(&console.mutex)
	allocator := console.allocator
	for line in console.pending {
		delete(line, allocator)
	}
	delete(console.pending)
	console.pending = nil
	console.allocator = {}
	console.accepting = false
	sync.mutex_unlock(&console.mutex)

	delete(console.executing)
	console.executing = nil
	for key, cmd in console.commands {
		delete(key, context.allocator)
		delete(cmd.description, context.allocator)
	}
	delete(console.commands)
	console.commands = nil
	console.started = false
}

// 注册命令（名字大小写不敏感，重复注册覆盖）。只在主线程调用。
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

// 启动后台读取线程（幂等）。stdin 不可用或未 init 时返回 false。
cli_start :: proc(console: ^Cli_Console) -> bool {
	if console.started do return true
	if os.stdin == nil || console.allocator.procedure == nil do return false
	// 自清理：线程退出时释放自身，dispose 不必 join 阻塞中的 stdin 读取。
	if thread.create_and_start_with_data(console, cli_reader_loop, self_cleanup = true) == nil {
		return false
	}
	console.started = true
	fmt.println("[cli] CLI 调试控制台已启动，输入 help 查看命令")
	return true
}

// 停止接收输入。阻塞中的 stdin 读取要等到下一行输入或 EOF 才返回，
// 那一行被丢弃，线程随即退出；进程退出时线程随进程结束。
cli_stop :: proc(console: ^Cli_Console) {
	sync.mutex_lock(&console.mutex)
	console.accepting = false
	sync.mutex_unlock(&console.mutex)
}

// ------------------------------------------------------------------------------
// 主线程消费 —— cli_update
// ------------------------------------------------------------------------------

// 每帧调用：取出读取线程送来的行，在主线程逐条执行。
// 只处理本次开始时已送达的行；handler 期间新到的留到下一次。
cli_update :: proc(console: ^Cli_Console) {
	sync.mutex_lock(&console.mutex)
	allocator := console.allocator
	console.pending, console.executing = console.executing, console.pending
	sync.mutex_unlock(&console.mutex)

	for line in console.executing {
		cli_execute(console, line)
		delete(line, allocator)
	}
	clear(&console.executing)
}

// 主线程：解析一行，查找命令并执行；未知命令提示。
@(private)
cli_execute :: proc(console: ^Cli_Console, line: string) {
	trimmed := strings.trim_space(line)
	if len(trimmed) == 0 do return
	name, args, ok := cli_parse_line(trimmed)
	if !ok do return

	lower, _ := strings.to_lower(name, context.allocator)
	defer delete(lower, context.allocator)
	cmd, known := console.commands[lower]
	if !known {
		fmt.eprintf("[cli] 未知命令 '%s'，输入 help 查看命令列表\n", name)
		return
	}
	if cmd.handler != nil {
		cmd.handler(args, cmd.userdata)
	}
}

// ------------------------------------------------------------------------------
// 后台读取线程
// ------------------------------------------------------------------------------

// 任意线程：克隆一行送给主线程（line 只借用）。控制台未初始化、已 stop
// 或已 dispose 时丢弃并返回 false。
cli_enqueue_line :: proc(console: ^Cli_Console, line: string) -> bool {
	sync.mutex_lock(&console.mutex)
	defer sync.mutex_unlock(&console.mutex)
	if !console.accepting || console.allocator.procedure == nil do return false
	owned, _ := strings.clone(line, console.allocator)
	append(&console.pending, owned)
	return true
}

@(private)
cli_reader_loop :: proc(data: rawptr) {
	console := (^Cli_Console)(data)

	// 行缓冲只在本线程使用，走本线程默认的 context.allocator。
	buf: [256]u8
	pending: [dynamic]u8
	defer delete(pending)

	for {
		n, err := os.read(os.stdin, buf[:])
		if err != nil || n <= 0 {
			return // stdin 关闭（管道结束 / 无控制台）
		}
		for i in 0..<n {
			if buf[i] == '\n' {
				if !cli_enqueue_line(console, string(pending[:])) do return
				clear(&pending)
				continue
			}
			if buf[i] != '\r' {
				append(&pending, buf[i])
			}
		}
	}
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
