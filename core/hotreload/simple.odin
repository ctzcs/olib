package hotreload

// 游戏侧的最简入口：游戏写一个 State 和几个回调（Game_Hooks），库负责导出、保存和交接。
// 热重载时 State 整体交给新版本（按字节原样搬过去，不复制它指向的内存），所以 State 里可以放
// 动态数组、map、字符串、堆上的对象，以及 Batcher 这类需要重新创建的资源。
// 分区：回调与规则 / 槽 / 入口。

// State 里可以放：
//   - 普通数据；
//   - 用宿主分配器分配的堆数据（回调里的 context.allocator 就是宿主的）：动态数组、map、
//     strings.clone 出来的字符串、new 出来的对象。它们在新旧版本之间共用同一份内存；
//   - 资源字段（Batcher 等）：在 start 里重新创建（会覆盖整个字段），在 stop 里释放。
// State 里不能放：字符串字面量、函数指针、指向 DLL 包级变量或常量的指针——旧 DLL 卸载后它们就失效，
//   新版本再用会崩溃。需要字符串就 strings.clone；需要回调就存 ID。
// State 的字段布局改变（大小不同）时新版本会被拒绝，须提高 state_version 并重开，或改用完整接口自己编码。
Game_Hooks :: struct($State: typeid, $Services: typeid) {
	// 新局初始化（必填）：第一次启动时调用；热重载时不调用，State 由旧版本交接。
	reset: proc(state: ^State, services: ^Services),
	update: proc(state: ^State, services: ^Services, dt: f64), // 必填
	render: proc(state: ^State, services: ^Services, dt: f64), // 必填
	// 每次加载版本后调用（含第一次）：创建资源。可为 nil。
	start: proc(state: ^State, services: ^Services),
	// 每次卸载版本前调用（含热重载换掉旧版本）：释放这个版本的资源。可为 nil。
	stop: proc(state: ^State, services: ^Services),
	// 游戏真正结束（宿主退出）时调用：释放 State 拥有的堆数据。热重载换版本时不调用。可为 nil。
	drop: proc(state: ^State, services: ^Services),
	host_version: u64, // 宿主协议版本，0 视为 1
	state_version: u64, // State 格式版本，0 视为 1
}

// 模块私有实例。handed_off：save 被调用过，State 已交给下一个版本，卸载时不再 drop。
Simple_Slot :: struct($State: typeid) {
	state: State,
	started: bool,
	handed_off: bool,
}

// 当前 DLL 的回调表：每个 State / Services 组合各有一份静态存储（每个 DLL 也各有自己的一份），
// 导出的 "c" 回调无法携带闭包，从这里取回。
@(private)
simple_store :: proc "contextless" ($State: typeid, $Services: typeid,
	set: ^Game_Hooks(State, Services) = nil) -> ^Game_Hooks(State, Services) {
	@(static) hooks: ^Game_Hooks(State, Services)
	if set != nil do hooks = set
	return hooks
}

// 在导出函数里直接返回它；hooks 须在整个模块生命周期内有效（用包级变量）：
//
//	hooks := reload.Game_Hooks(State, Services){reset = reset, update = update, render = render,
//		start = start, stop = stop, drop = drop, host_version = HOST_VERSION}
//
//	@(export)
//	olib_game_api :: proc "c" (version: u32, size: int, api: ^reload.API) -> bool {
//		return reload.simple_api(version, size, api, &hooks)
//	}
simple_api :: proc "contextless" (version: u32, size: int, api: ^API, hooks: ^Game_Hooks($State, $Services)) -> bool {
	if version != API_VERSION || size != size_of(API) do return false
	if hooks == nil || hooks.reset == nil || hooks.update == nil || hooks.render == nil do return false
	simple_store(State, Services, hooks)

	load :: proc "c" (call: ^Call, snapshot: Snapshot) -> bool {
		context = call.host_context^
		hooks := simple_store(State, Services)
		slot := new(Simple_Slot(State))
		call.instance = slot
		services := cast(^Services)call.services
		if snapshot.version == 0 {
			hooks.reset(&slot.state, services)
		} else {
			if len(snapshot.data) != size_of(State) do return false
			copy(([^]u8)(&slot.state)[:size_of(State)], snapshot.data)
		}
		if hooks.start != nil do hooks.start(&slot.state, services)
		slot.started = true
		return true
	}
	unload :: proc "c" (call: ^Call) {
		context = call.host_context^
		hooks := simple_store(State, Services)
		slot := cast(^Simple_Slot(State))call.instance
		if slot == nil do return
		services := cast(^Services)call.services
		if slot.started {
			if hooks.stop != nil do hooks.stop(&slot.state, services)
			if hooks.drop != nil && !slot.handed_off do hooks.drop(&slot.state, services)
		}
		free(slot)
	}
	snapshot_size :: proc "c" (call: ^Call) -> int {
		return size_of(State)
	}
	// 交接：把 State 的字节交给下一个版本，不复制它指向的内存，所以旧版本卸载时不能释放它们。
	save :: proc "c" (call: ^Call, destination: []u8) -> bool {
		slot := cast(^Simple_Slot(State))call.instance
		if slot == nil || len(destination) != size_of(State) do return false
		copy(destination, ([^]u8)(&slot.state)[:size_of(State)])
		slot.handed_off = true
		return true
	}
	on_update :: proc "c" (call: ^Call, dt: f64) {
		context = call.host_context^
		hooks := simple_store(State, Services)
		slot := cast(^Simple_Slot(State))call.instance
		slot.handed_off = false // 仍在运行说明交接没有发生（新版本被拒绝），State 仍归本版本
		hooks.update(&slot.state, cast(^Services)call.services, dt)
	}
	on_render :: proc "c" (call: ^Call, dt: f64) {
		context = call.host_context^
		hooks := simple_store(State, Services)
		hooks.render(&(cast(^Simple_Slot(State))call.instance).state, cast(^Services)call.services, dt)
	}

	api^ = {
		host_version = hooks.host_version == 0 ? 1 : hooks.host_version,
		state_version = hooks.state_version == 0 ? 1 : hooks.state_version,
		load = load, unload = unload, snapshot_size = snapshot_size, save = save,
		update = on_update, render = on_render,
	}
	return true
}
