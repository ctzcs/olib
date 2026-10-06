// 托管 tween：把 Tween(T) 注册进 manager 变成可统一调度的节点。
// setter 版写回调、指针版直接写目标、属性版从 getter 现取起点。
package tween

// 分区：
//   数据类型 —— setter 版 / 指针版 payload
//   内部工具 —— 时长/终值/归一化/节点构造
//   注册 —— manager_add_tween / manager_add_tween_to / manager_add_property_tween

// ------------------------------------------------------------------------------
// 数据类型 —— setter 版 / 指针版 payload
// ------------------------------------------------------------------------------

Managed_Tween_Data :: struct($T: typeid) {
	tween:         Tween(T),
	initial_tween: Tween(T),
	setter:        proc "contextless" (value: T),
}

Managed_Ptr_Tween_Data :: struct($T: typeid) {
	tween:         Tween(T),
	initial_tween: Tween(T),
	target:        ^T,
}

// ------------------------------------------------------------------------------
// 内部工具 —— 时长/终值/归一化/节点构造
// ------------------------------------------------------------------------------

@(private)
managed_tween_get_duration :: proc(tween: Tween($T)) -> f32 {
	if tween.value.speed >= 1.0e20 {
		return 1.0e-30
	}
	return 1.0 / tween.value.speed
}

@(private)
managed_tween_terminal_value :: proc(start, finish: $T, repeat_mode: Repeat_Mode, loop_count: i32) -> T {
	switch repeat_mode {
	case .Once, .Loop:
		return finish
	case .PingPong:
		if loop_count % 2 == 0 {
			return start
		}
		return finish
	}
	return finish
}

@(private)
managed_tween_normalize :: proc(tween: ^Tween($T), initial_tween: ^Tween(T)) {
	tween.start_time = 0
	tween.delay = 0
	initial_tween.start_time = 0
	initial_tween.delay = 0
}

@(private)
managed_tween_loop_count :: proc(repeat_mode: Repeat_Mode) -> i32 {
	if repeat_mode == .Once {
		return 1
	}
	return -1
}

@(private)
managed_tween_make_node :: proc(
	payload: rawptr,
	tween: Tween($T),
	update_proc: Tween_Node_Update_Proc,
	reset_proc: Tween_Node_Reset_Proc,
	kill_proc: Tween_Node_Kill_Proc,
	set_loops_proc: Tween_Node_Set_Loops_Proc,
) -> Tween_Node {
	return Tween_Node{
		kind = .Tween,
		active = true,
		parent = TWEEN_HANDLE_NONE,

		timing = Tween_Timing{
			delay = tween.delay,
			duration = managed_tween_get_duration(tween),
			time_scale = 1,
		},

		loops = Loop_Config{
			count = managed_tween_loop_count(tween.repeat_mode),
			mode = tween.repeat_mode,
		},

		control = Tween_Control{
			state = .Idle,
			auto_kill = tween.repeat_mode == .Once,
		},

		payload = payload,
		vtable = Tween_Node_VTable{
			update = update_proc,
			reset = reset_proc,
			kill = kill_proc,
			set_loops = set_loops_proc,
		},
	}
}

// ------------------------------------------------------------------------------
// 注册 —— manager_add_tween / manager_add_tween_to / manager_add_property_tween
// ------------------------------------------------------------------------------

manager_add_tween :: proc(
	manager: ^Tween_Manager,
	tween: Tween($T),
	setter: proc "contextless" (value: T),
) -> Tween_Handle {
	data := new(Managed_Tween_Data(T))
	data^ = {
		tween = tween,
		initial_tween = tween,
		setter = setter,
	}

	// manager 负责 delay，所以这里把 tween 的内部起始时间和 delay 归一化。
	managed_tween_normalize(&data.tween, &data.initial_tween)

	update_proc :: proc(node: ^Tween_Node, dt: f32) {
		_ = dt
		data := cast(^Managed_Tween_Data(T))(node.payload)
		if data == nil do return

		if node.loops.count > 0 && node.control.loops_done >= node.loops.count {
			switch data.tween.repeat_mode {
			case .Once, .Loop:
				data.setter(data.tween.finish)
			case .PingPong:
				if node.loops.count % 2 == 0 {
					data.setter(data.tween.start)
				} else {
					data.setter(data.tween.finish)
				}
			}
			return
		}

		value := tween_get_value(&data.tween, node.timing.elapsed)
		data.setter(value)
	}

	reset_proc :: proc(node: ^Tween_Node) {
		data := cast(^Managed_Tween_Data(T))(node.payload)
		if data == nil do return
		data.tween = data.initial_tween
		data.setter(data.tween.start)
	}

	set_loops_proc :: proc(node: ^Tween_Node, count: i32, mode: Repeat_Mode) {
		_ = count
		data := cast(^Managed_Tween_Data(T))(node.payload)
		if data == nil do return
		data.tween.repeat_mode = mode
		data.initial_tween.repeat_mode = mode
	}

	kill_proc :: proc(node: ^Tween_Node) {
		data := cast(^Managed_Tween_Data(T))(node.payload)
		if data != nil {
			free(data)
		}
		node.payload = nil
	}

	node := managed_tween_make_node(data, tween, update_proc, reset_proc, kill_proc, set_loops_proc)

	// 注册后先把起始值推一次，避免等到第一帧 update 才生效。
	data.setter(data.tween.start)

	return manager_add_node(manager, node)
}

// 便捷属性绑定：直接把 tween 结果写入目标指针，不再需要额外定义 contextless setter。
manager_add_tween_to :: proc(
	manager: ^Tween_Manager,
	tween: Tween($T),
	target: ^T,
) -> Tween_Handle {
	data := new(Managed_Ptr_Tween_Data(T))
	data^ = {
		tween = tween,
		initial_tween = tween,
		target = target,
	}

	// manager 负责 delay，所以这里把 tween 的内部起始时间和 delay 归一化。
	managed_tween_normalize(&data.tween, &data.initial_tween)

	update_proc :: proc(node: ^Tween_Node, dt: f32) {
		_ = dt
		data := cast(^Managed_Ptr_Tween_Data(T))(node.payload)
		if data == nil || data.target == nil do return

		if node.loops.count > 0 && node.control.loops_done >= node.loops.count {
			data.target^ = managed_tween_terminal_value(data.tween.start, data.tween.finish, data.tween.repeat_mode, node.loops.count)
			return
		}

		value := tween_get_value(&data.tween, node.timing.elapsed)
		data.target^ = value
	}

	reset_proc :: proc(node: ^Tween_Node) {
		data := cast(^Managed_Ptr_Tween_Data(T))(node.payload)
		if data == nil do return
		data.tween = data.initial_tween
		if data.target != nil {
			data.target^ = data.tween.start
		}
	}

	set_loops_proc :: proc(node: ^Tween_Node, count: i32, mode: Repeat_Mode) {
		_ = count
		data := cast(^Managed_Ptr_Tween_Data(T))(node.payload)
		if data == nil do return
		data.tween.repeat_mode = mode
		data.initial_tween.repeat_mode = mode
	}

	kill_proc :: proc(node: ^Tween_Node) {
		data := cast(^Managed_Ptr_Tween_Data(T))(node.payload)
		if data != nil {
			free(data)
		}
		node.payload = nil
	}

	node := managed_tween_make_node(data, tween, update_proc, reset_proc, kill_proc, set_loops_proc)

	// 注册后先把起始值写入目标，避免等到第一帧 update 才生效。
	if data.target != nil {
		data.target^ = data.tween.start
	}

	return manager_add_node(manager, node)
}

// 属性绑定版本：通过 getter 读取当前值，再通过 setter 写回目标。
manager_add_property_tween :: proc(
	manager: ^Tween_Manager,
	getter: proc "contextless" () -> $T,
	setter: proc "contextless" (value: T),
	finish: T,
	config: Tween_Config,
	lerp: proc "contextless" (a, b: T, ratio: f32) -> T,
) -> Tween_Handle {
	start := getter()
	tween := make_ex(start, finish, 0, config, lerp)
	return manager_add_tween(manager, tween, setter)
}
