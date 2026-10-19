#+build !js
package hotreload

import "core:fmt"

// 宿主侧的一站式入口：把 Session、Watch 和"检查编译 → 等 GPU → 替换 → 转发 update/render"收成四个调用。
// 需要自定义编译命令、替换策略或更细的控制时，直接用 Session / Watch。
// 分区：配置与状态 / 生命周期 / 每帧。

Hot_Config :: struct {
	source: string, // 游戏 DLL 的 Odin 包目录，相对 working_directory
	collections: []string, // "名字=路径"，如 {"olib=../olib"}，传给 -collection:
	args: []string, // 额外的 odin build 参数，如 {"-vet"}
	roots: []string, // 除 source 外还要监听的目录或文件（#load 的数据、共享包等）
	working_directory: string, // 空为当前目录
	services: rawptr, // 宿主服务，原样交给游戏模块；地址必须稳定
	host_version: u64, // 宿主协议版本，0 视为 1；协议或共享类型变化时加一
	// 新版本替换旧版本之前调用（帧开始，旧模块尚在）：通常在这里等 GPU 空闲。
	before_swap: proc(user_data: rawptr),
	user_data: rawptr,
	quiet: bool, // true 时不向终端输出 LIVE 版本号和编译错误
}

// 地址必须稳定（放在宿主堆分配状态中），不要复制。
Hot :: struct {
	session: Session,
	watch: Watch,
	version: u64, // 当前已加载的模块版本，0 表示还没有成功加载
	before_swap: proc(user_data: rawptr),
	user_data: rawptr,
	quiet: bool,
	last_status: Build_Status,
}

// 失败时保持 h 未初始化。
hot_init :: proc(h: ^Hot, config: Hot_Config) -> bool {
	if h.session.initialized || config.source == "" do return false
	version := config.host_version == 0 ? 1 : config.host_version
	if !init(&h.session, version, config.services) do return false
	roots := make([dynamic]string, context.temp_allocator)
	append(&roots, config.source)
	append(&roots, ..config.roots)
	if !watch_init(&h.watch, {
		command = hot_command(config),
		working_directory = config.working_directory,
		roots = roots[:],
	}) {
		_ = dispose(&h.session)
		return false
	}
	h.before_swap, h.user_data, h.quiet = config.before_swap, config.user_data, config.quiet
	if !h.quiet do fmt.printfln("hotreload: compiling %s ... edit and save to reload", config.source)
	return true
}

// 先卸载游戏模块，再等待编译任务结束。
hot_dispose :: proc(h: ^Hot) {
	_ = dispose(&h.session)
	watch_dispose(&h.watch)
	h^ = {}
}

// 放在宿主 UpdateProc 的开头：检查编译结果，成功就替换模块，然后转发游戏的 update。
hot_update :: proc(h: ^Hot, dt: f64, frame: rawptr = nil) {
	watch_update(&h.watch, dt)
	if h.watch.status == .Ready {
		if h.before_swap != nil do h.before_swap(h.user_data)
		result := watch_apply(&h.watch, &h.session)
		h.last_status = h.watch.status
		if result == .Success {
			h.version = h.session.revision
			if !h.quiet do fmt.printfln("hotreload: LIVE version %d", h.version)
		} else if !h.quiet && result != .Busy {
			fmt.eprintln(h.session.diagnostic)
		}
	}
	if h.watch.status == .Error && h.last_status != .Error && !h.quiet {
		fmt.eprintln(h.watch.diagnostic)
	}
	h.last_status = h.watch.status
	update(&h.session, dt, frame)
}

// 放在宿主 RenderProc：转发游戏的 render。
hot_render :: proc(h: ^Hot, dt: f64, frame: rawptr = nil) {
	render(&h.session, dt, frame)
}

// 最近一次失败的原因（编译错误或加载被拒）；没有失败时为空。借用，下一次 hot_update 后失效。
hot_error :: proc(h: ^Hot) -> string {
	return h.watch.status == .Error ? h.watch.diagnostic : ""
}

// 重新尝试编译当前源码（例如修好了编译环境而源码没有变）。
hot_retry :: proc(h: ^Hot) {
	watch_retry(&h.watch)
}

// 返回的切片分配在临时分配器上，watch_init 会复制它。
@(private)
hot_command :: proc(config: Hot_Config) -> []string {
	args := make([dynamic]string, context.temp_allocator)
	append(&args, "odin", "build", config.source, "-build-mode:dll")
	for collection in config.collections do append(&args, fmt.tprintf("-collection:%s", collection))
	append(&args, ..config.args)
	append(&args, "-out:{output}")
	return args[:]
}
