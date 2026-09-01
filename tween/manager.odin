package tween

import ha "olib:handle/handle_array"

// 对外暴露的节点句柄。
// 使用 distinct 与其他系统的 Handle 做类型隔离。
Tween_Handle :: distinct ha.Handle
TWEEN_HANDLE_NONE :: Tween_Handle {}

// 用于把节点分组，方便批量 Pause/Kill。
Tween_Group_Id :: distinct u32

// 播放状态机。
// manager 在 update 时主要依据这个状态决定节点是否推进。
Playback_State :: enum u8 {
	Idle,
	Delayed,
	Playing,
	Paused,
	Completed,
	Killed,
}

// manager 顶层统一管理的运行时节点类型。
// 按更接近 DOTween 的分层，这里只保留真正可播放的顶层对象。
Node_Kind :: enum u8 {
	Tween,
	Sequence,
}

// Sequence 内部时间轴条目类型。
// Callback/Interval 属于 sequence 的内部步骤，不属于 manager 顶层节点。
Sequence_Step_Kind :: enum u8 {
	Tween,
	Callback,
	Interval,
}

// 循环配置。
// count = -1 表示无限循环，mode 复用已有 Repeat_Mode。
Loop_Config :: struct {
	count: i32, // -1 表示无限循环
	mode:  Repeat_Mode,
}

// 生命周期回调签名。
// 这里只传节点句柄，避免 manager 层直接暴露具体 payload 类型。
Tween_Callback_Proc :: #type proc "contextless" (handle: Tween_Handle)

// Sequence 内部步骤回调签名。
Sequence_Callback_Proc :: #type proc "contextless" ()

// 节点生命周期回调集合。
Tween_Callbacks :: struct {
	on_start:         Tween_Callback_Proc,
	on_update:        Tween_Callback_Proc,
	on_step_complete: Tween_Callback_Proc,
	on_complete:      Tween_Callback_Proc,
	on_kill:          Tween_Callback_Proc,
}

// 纯时间数据。
// 把时间相关字段集中起来，后面 Sequence/Interval 也能复用。
Tween_Timing :: struct {
	created_at: f32, // 创建时刻
	start_at:   f32, // 真正开始播放的时刻（包含 delay 后）
	delay:      f32, // 启动前等待时间
	duration:   f32, // 单次播放时长
	elapsed:    f32, // 当前已经推进的本地时间
	time_scale: f32, // 节点级时间缩放
}

// 运行控制信息。
Tween_Control :: struct {
	state:                 Playback_State, // 当前播放状态
	started:               bool,           // on_start 是否已经触发过
	loops_done:            i32,            // 已完成循环次数
	auto_kill:             bool,           // 完成后是否自动销毁
	use_manager_auto_kill: bool,           // 是否沿用 manager 的全局自动清理策略
	is_relative:           bool,           // 目标值是否按相对量解释
	independent_update:    bool,           // 是否忽略 manager 的全局时间缩放
}

// 类型擦除后的行为入口。
// manager 不直接依赖具体 Tween(T) 类型，而是通过这些函数指针驱动节点。
Tween_Node_Update_Proc    :: #type proc(node: ^Tween_Node, dt: f32)
Tween_Node_Reset_Proc     :: #type proc(node: ^Tween_Node)
Tween_Node_Kill_Proc      :: #type proc(node: ^Tween_Node)
Tween_Node_Set_Loops_Proc :: #type proc(node: ^Tween_Node, count: i32, mode: Repeat_Mode)

// 每种节点自己的“虚表”。
Tween_Node_VTable :: struct {
	update:    Tween_Node_Update_Proc,
	reset:     Tween_Node_Reset_Proc,
	kill:      Tween_Node_Kill_Proc,
	set_loops: Tween_Node_Set_Loops_Proc,
}

// manager 内部统一管理的运行时节点。
Tween_Node :: struct {
	handle: Tween_Handle, // 节点自己的稳定句柄
	kind:   Node_Kind,

	group: Tween_Group_Id,
	tag:   string, // 便于按语义批量控制，如 "ui" / "camera"

	active: bool,
	parent: Tween_Handle, // 如果属于某个 Sequence，则指向父节点

	timing:    Tween_Timing,
	loops:     Loop_Config,
	control:   Tween_Control,
	callbacks: Tween_Callbacks,

	payload: rawptr,          // 指向真实 tween/sequence 数据
	vtable:  Tween_Node_VTable,
}

// Sequence 中的一条时间轴步骤。
// Tween/Callback/Interval 都通过同一种 entry 排到 sequence 本地时间线上。
Sequence_Entry :: struct {
	kind:      Sequence_Step_Kind,
	child:     Tween_Handle,
	callback:  Sequence_Callback_Proc,
	start_at:  f32,  // 在 sequence 本地时间轴中的起始位置
	duration:  f32,  // 该步骤占用时长；callback 通常为 0
	triggered: bool, // callback 是否已经触发过
}

// Sequence 的运行时数据。
Sequence_Runtime :: struct {
	cursor:   f32,
	duration: f32,
	entries:  [dynamic]Sequence_Entry,
}

// manager 的全局配置。
Tween_Manager_Config :: struct {
	default_time_scale: f32,
	auto_kill_finished: bool,
	auto_compact:       bool,
}

// 运行时统计信息，主要用于调试和观察系统状态。
Tween_Manager_Stats :: struct {
	total_nodes:     int,
	active_nodes:    int,
	playing_nodes:   int,
	paused_nodes:    int,
	completed_nodes: int,
	killed_nodes:    int,
}

// Tween 系统总入口。
// 负责持有所有节点、推进时间、分发 update、清理已完成节点。
Tween_Manager :: struct {
	now:        f32,
	delta_time: f32,
	time_scale: f32,

	nodes: ha.Pool(Tween_Node, Tween_Handle),
	_cleanup_scratch: [dynamic]Tween_Handle,

	config: Tween_Manager_Config,
	stats:  Tween_Manager_Stats,
}

manager_make :: proc() -> Tween_Manager {
	return Tween_Manager{
		time_scale = 1,
		config = Tween_Manager_Config{
			default_time_scale = 1,
			auto_kill_finished = true,
			auto_compact = true,
		},
	}
}

manager_get_node_ptr :: proc(manager: Tween_Manager, handle: Tween_Handle) -> ^Tween_Node {
	return ha.get(manager.nodes, handle)
}

manager_is_handle_valid :: proc(manager: Tween_Manager, handle: Tween_Handle) -> bool {
	return manager_get_node_ptr(manager, handle) != nil
}

@(private)
recount_stats :: proc(manager: ^Tween_Manager) {
	stats := Tween_Manager_Stats{}
	stats.total_nodes = manager.nodes.num

	for it := ha.begin(&manager.nodes); node, _ in ha.next(&it) {
		if node.active do stats.active_nodes += 1
		switch node.control.state {
		case .Idle, .Delayed:
		case .Playing:   stats.playing_nodes += 1
		case .Paused:    stats.paused_nodes += 1
		case .Completed: stats.completed_nodes += 1
		case .Killed:    stats.killed_nodes += 1
		}
	}

	manager.stats = stats
}

@(private)
manager_add_node :: proc(manager: ^Tween_Manager, node: Tween_Node) -> Tween_Handle {
	node := node
	if node.timing.time_scale == 0 {
		node.timing.time_scale = manager.config.default_time_scale
		if node.timing.time_scale == 0 do node.timing.time_scale = 1
	}
	if node.control.state == .Idle {
		if node.timing.delay > 0 {
			node.control.state = .Delayed
		} else {
			node.control.state = .Playing
		}
	}
	if node.parent == TWEEN_HANDLE_NONE do node.parent = TWEEN_HANDLE_NONE
	if node.handle == TWEEN_HANDLE_NONE do node.handle = TWEEN_HANDLE_NONE
	if !node.active do node.active = true
	node.control.use_manager_auto_kill = true
	node.timing.created_at = manager.now
	node.timing.start_at = manager.now + node.timing.delay

	handle := ha.add(&manager.nodes, node)
	if node_ptr := ha.get(manager.nodes, handle); node_ptr != nil {
		node_ptr.handle = handle
	}
	recount_stats(manager)
	return handle
}

@(private)
destroy_node :: proc(node: ^Tween_Node) {
	if node.vtable.kill != nil {
		node.vtable.kill(node)
	}
	node^ = {}
}

@(private)
manager_remove_node_internal :: proc(manager: ^Tween_Manager, handle: Tween_Handle, refresh_stats: bool) -> bool {
	if !manager_is_handle_valid(manager^, handle) do return false
	ha.remove(&manager.nodes, handle, destroy_node)
	if refresh_stats {
		recount_stats(manager)
	}
	return true
}

manager_remove_node :: proc(manager: ^Tween_Manager, handle: Tween_Handle) -> bool {
	return manager_remove_node_internal(manager, handle, true)
}

manager_reset :: proc(manager: ^Tween_Manager) {
	ha.reset(&manager.nodes, destroy_node)
	clear(&manager._cleanup_scratch)
	manager.now = 0
	manager.delta_time = 0
	manager.stats = {}
}

manager_delete :: proc(manager: ^Tween_Manager) {
	ha.delete(&manager.nodes, destroy_node)
	delete(manager._cleanup_scratch)
	manager^ = {}
}

@(private)
call_callback :: proc(callback: Tween_Callback_Proc, handle: Tween_Handle) {
	if callback != nil do callback(handle)
}

manager_play :: proc(manager: ^Tween_Manager, handle: Tween_Handle) -> bool {
	node := manager_get_node_ptr(manager^, handle)
	if node == nil do return false
	if node.control.state == .Killed || node.control.state == .Completed do return false
	if node.timing.delay > 0 && node.timing.elapsed <= 0 {
		node.control.state = .Delayed
		node.timing.start_at = manager.now + node.timing.delay
	} else {
		node.control.state = .Playing
	}
	node.active = true
	recount_stats(manager)
	return true
}

manager_pause :: proc(manager: ^Tween_Manager, handle: Tween_Handle) -> bool {
	node := manager_get_node_ptr(manager^, handle)
	if node == nil do return false
	if node.control.state == .Killed || node.control.state == .Completed do return false
	node.control.state = .Paused
	recount_stats(manager)
	return true
}

manager_set_callbacks :: proc(manager: ^Tween_Manager, handle: Tween_Handle, callbacks: Tween_Callbacks) -> bool {
	node := manager_get_node_ptr(manager^, handle)
	if node == nil do return false
	node.callbacks = callbacks
	return true
}

manager_on_start :: proc(manager: ^Tween_Manager, handle: Tween_Handle, callback: Tween_Callback_Proc) -> bool {
	node := manager_get_node_ptr(manager^, handle)
	if node == nil do return false
	node.callbacks.on_start = callback
	return true
}

manager_on_update :: proc(manager: ^Tween_Manager, handle: Tween_Handle, callback: Tween_Callback_Proc) -> bool {
	node := manager_get_node_ptr(manager^, handle)
	if node == nil do return false
	node.callbacks.on_update = callback
	return true
}

manager_on_step_complete :: proc(manager: ^Tween_Manager, handle: Tween_Handle, callback: Tween_Callback_Proc) -> bool {
	node := manager_get_node_ptr(manager^, handle)
	if node == nil do return false
	node.callbacks.on_step_complete = callback
	return true
}

manager_on_complete :: proc(manager: ^Tween_Manager, handle: Tween_Handle, callback: Tween_Callback_Proc) -> bool {
	node := manager_get_node_ptr(manager^, handle)
	if node == nil do return false
	node.callbacks.on_complete = callback
	return true
}

manager_on_kill :: proc(manager: ^Tween_Manager, handle: Tween_Handle, callback: Tween_Callback_Proc) -> bool {
	node := manager_get_node_ptr(manager^, handle)
	if node == nil do return false
	node.callbacks.on_kill = callback
	return true
}

manager_clear_callbacks :: proc(manager: ^Tween_Manager, handle: Tween_Handle) -> bool {
	node := manager_get_node_ptr(manager^, handle)
	if node == nil do return false
	node.callbacks = {}
	return true
}

manager_set_loops :: proc(manager: ^Tween_Manager, handle: Tween_Handle, count: i32, mode: Repeat_Mode) -> bool {
	node := manager_get_node_ptr(manager^, handle)
	if node == nil do return false
	node.loops.count = count
	node.loops.mode = mode
	node.control.use_manager_auto_kill = false
	node.control.auto_kill = count > 0
	if node.vtable.set_loops != nil {
		node.vtable.set_loops(node, count, mode)
	}
	recount_stats(manager)
	return true
}

manager_set_auto_kill :: proc(manager: ^Tween_Manager, handle: Tween_Handle, enabled: bool) -> bool {
	node := manager_get_node_ptr(manager^, handle)
	if node == nil do return false
	node.control.use_manager_auto_kill = false
	node.control.auto_kill = enabled
	recount_stats(manager)
	return true
}

manager_rewind :: proc(manager: ^Tween_Manager, handle: Tween_Handle) -> bool {
	node := manager_get_node_ptr(manager^, handle)
	if node == nil do return false
	if node.vtable.reset != nil {
		node.vtable.reset(node)
	}
	node.timing.elapsed = 0
	node.control.started = false
	node.control.loops_done = 0
	node.control.state = .Paused
	node.active = false
	node.timing.start_at = manager.now + node.timing.delay
	recount_stats(manager)
	return true
}

manager_restart :: proc(manager: ^Tween_Manager, handle: Tween_Handle) -> bool {
	if !manager_rewind(manager, handle) do return false
	return manager_play(manager, handle)
}

manager_complete :: proc(manager: ^Tween_Manager, handle: Tween_Handle) -> bool {
	node := manager_get_node_ptr(manager^, handle)
	if node == nil do return false
	node.timing.elapsed = node.timing.duration
	node.control.state = .Completed
	node.active = false
	call_callback(node.callbacks.on_complete, node.handle)
	recount_stats(manager)
	return true
}

manager_kill :: proc(manager: ^Tween_Manager, handle: Tween_Handle) -> bool {
	node := manager_get_node_ptr(manager^, handle)
	if node == nil do return false
	if node.control.state == .Killed do return false
	node.control.state = .Killed
	node.active = false
	call_callback(node.callbacks.on_kill, node.handle)
	recount_stats(manager)
	return true
}

@(private)
update_node :: proc(manager: ^Tween_Manager, node: ^Tween_Node, dt: f32) {
	if !node.active do return

	play_dt := dt

	switch node.control.state {
	case .Paused, .Completed, .Killed:
		return
	case .Delayed:
		if manager.now < node.timing.start_at do return
		play_dt = manager.now - node.timing.start_at
		if play_dt < 0 do play_dt = 0
		node.control.state = .Playing
	case .Idle:
		node.control.state = .Playing
	case .Playing:
	}

	if !node.control.started {
		node.control.started = true
		call_callback(node.callbacks.on_start, node.handle)
	}

	local_dt := play_dt * node.timing.time_scale
	prev_elapsed := node.timing.elapsed
	new_elapsed := prev_elapsed + local_dt

	if node.timing.duration > 0 {
		prev_loop := i32(prev_elapsed / node.timing.duration)
		curr_loop := i32(new_elapsed / node.timing.duration)
		crossed := curr_loop - prev_loop
		if crossed > 0 {
			node.control.loops_done += crossed
			if node.callbacks.on_step_complete != nil {
				for i: i32 = 0; i < crossed; i += 1 {
					call_callback(node.callbacks.on_step_complete, node.handle)
				}
			}
		}
		if node.loops.count > 0 && node.control.loops_done >= node.loops.count {
			max_elapsed := f32(node.loops.count) * node.timing.duration
			if new_elapsed > max_elapsed do new_elapsed = max_elapsed
		}
	}

	applied_dt := new_elapsed - prev_elapsed
	if applied_dt < 0 do applied_dt = 0
	node.timing.elapsed = new_elapsed
	if node.vtable.update != nil {
		node.vtable.update(node, applied_dt)
	}
	call_callback(node.callbacks.on_update, node.handle)
	if node.loops.count > 0 && node.control.loops_done >= node.loops.count {
		node.control.state = .Completed
		node.active = false
		call_callback(node.callbacks.on_complete, node.handle)
	}
}

@(private)
cleanup_finished :: proc(manager: ^Tween_Manager) {
	clear(&manager._cleanup_scratch)

	for it := ha.begin(&manager.nodes); node, handle in ha.next(&it) {
		if node.parent != TWEEN_HANDLE_NONE do continue
		if node.control.state == .Killed {
			append(&manager._cleanup_scratch, handle)
			continue
		}
		should_auto_kill := node.control.auto_kill
		if node.control.use_manager_auto_kill {
			should_auto_kill = manager.config.auto_kill_finished
		}
		if node.control.state == .Completed && should_auto_kill {
			append(&manager._cleanup_scratch, handle)
		}
	}

	for i := 0; i < len(manager._cleanup_scratch); i += 1 {
		_ = manager_remove_node_internal(manager, manager._cleanup_scratch[i], false)
	}
}

manager_update :: proc(manager: ^Tween_Manager, dt: f32) {
	manager.delta_time = dt
	manager.now += dt * manager.time_scale

	for it := ha.begin(&manager.nodes); node, _ in ha.next(&it) {
		if node.parent != TWEEN_HANDLE_NONE do continue
		local_dt := dt
		if !node.control.independent_update do local_dt *= manager.time_scale
		update_node(manager, node, local_dt)
	}

	cleanup_finished(manager)
	recount_stats(manager)
}
