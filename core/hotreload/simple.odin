package hotreload

// 游戏侧的最简入口：状态是一个纯数据结构 State，库负责保存、恢复和 API 导出，
// 游戏只写 reset / update / render（以及可选的 start / stop）。
// 状态含指针、切片、字符串、动态数组时不能用它——改用完整的 API（见 README）自己编码快照。
// 分区：槽 / 入口。

// 模块私有实例：State 随热重载按字节保存和恢复，started 记录 start 是否执行过。
Simple_Slot :: struct($State: typeid) {
	state: State,
	started: bool,
}

// 在导出函数里直接返回它：
//
//	@(export)
//	olib_game_api :: proc "c" (version: u32, size: int, api: ^reload.API) -> bool {
//		return reload.simple_api(version, size, api, State, Services,
//			reset, start, stop, update, render, host_version = HOST_VERSION)
//	}
//
// reset：新局时给 State 填初值（热重载时不调用，State 由快照恢复）。
// start / stop：每次加载 / 卸载时调用，创建和释放 GPU、UI 等不属于快照的资源；没有这类资源就用不带它们的重载。
// 这些资源放在 DLL 的包级变量里即可：每个版本的 DLL 有自己的一份全局变量。
// update / render：每帧调用。state_version：State 的格式变了就加一，新旧不同时默认拒绝替换。
simple_api_full :: proc "contextless" (version: u32, size: int, api: ^API,
	$State: typeid, $Services: typeid,
	$reset: proc(state: ^State, services: ^Services),
	$start: proc(state: ^State, services: ^Services),
	$stop: proc(state: ^State, services: ^Services),
	$update: proc(state: ^State, services: ^Services, dt: f64),
	$render: proc(state: ^State, services: ^Services, dt: f64),
	host_version: u64 = 1, state_version: u64 = 1) -> bool {
	if version != API_VERSION || size != size_of(API) do return false

	load :: proc "c" (call: ^Call, snapshot: Snapshot) -> bool {
		context = call.host_context^
		slot := new(Simple_Slot(State))
		call.instance = slot
		services := cast(^Services)call.services
		if snapshot.version == 0 {
			reset(&slot.state, services)
		} else {
			if len(snapshot.data) != size_of(State) do return false
			copy(([^]u8)(&slot.state)[:size_of(State)], snapshot.data)
		}
		start(&slot.state, services)
		slot.started = true
		return true
	}
	unload :: proc "c" (call: ^Call) {
		context = call.host_context^
		slot := cast(^Simple_Slot(State))call.instance
		if slot == nil do return
		if slot.started do stop(&slot.state, cast(^Services)call.services)
		free(slot)
	}
	snapshot_size :: proc "c" (call: ^Call) -> int {
		return size_of(State)
	}
	save :: proc "c" (call: ^Call, destination: []u8) -> bool {
		slot := cast(^Simple_Slot(State))call.instance
		if slot == nil || len(destination) != size_of(State) do return false
		copy(destination, ([^]u8)(&slot.state)[:size_of(State)])
		return true
	}
	on_update :: proc "c" (call: ^Call, dt: f64) {
		context = call.host_context^
		update(&(cast(^Simple_Slot(State))call.instance).state, cast(^Services)call.services, dt)
	}
	on_render :: proc "c" (call: ^Call, dt: f64) {
		context = call.host_context^
		render(&(cast(^Simple_Slot(State))call.instance).state, cast(^Services)call.services, dt)
	}

	api^ = {
		host_version = host_version, state_version = state_version,
		load = load, unload = unload, snapshot_size = snapshot_size, save = save,
		update = on_update, render = on_render,
	}
	return true
}

// 没有 start / stop 资源的游戏：只写 reset / update / render。
simple_api_basic :: proc "contextless" (version: u32, size: int, api: ^API,
	$State: typeid, $Services: typeid,
	$reset: proc(state: ^State, services: ^Services),
	$update: proc(state: ^State, services: ^Services, dt: f64),
	$render: proc(state: ^State, services: ^Services, dt: f64),
	host_version: u64 = 1, state_version: u64 = 1) -> bool {
	nothing :: proc(state: ^State, services: ^Services) {}
	return simple_api_full(version, size, api, State, Services, reset, nothing, nothing, update, render,
		host_version, state_version)
}

// 两种写法：reset, start, stop, update, render 五个函数；或没有资源时只给 reset, update, render。
simple_api :: proc{simple_api_full, simple_api_basic}
