// Sequence 托管：把多个 tween/callback/interval 排上同一条本地时间轴。
package tween

// 分区：
//   数据与查询 —— Managed_Sequence_Data / 取 payload / 祖先检查
//   时长计算 —— recompute / sync / child 总时长
//   子节点挂接 —— prepare / attach（创建即挂接的内部通道）
//   vtable 实现 —— update / reset / kill
//   创建 —— manager_add_sequence
//   时间轴组装 —— append / join / insert / prepend（各带 _tween 便捷版）

@(private)
Managed_Sequence_Data :: struct {
	manager: ^Tween_Manager,
	runtime: Sequence_Runtime,
}

// ------------------------------------------------------------------------------
// 数据与查询 —— Managed_Sequence_Data / 取 payload / 祖先检查
// ------------------------------------------------------------------------------

@(private)
Sequence_Attach_Proc :: #type proc(manager: ^Tween_Manager, seq: Tween_Handle, child: Tween_Handle) -> bool

@(private)
sequence_get_data :: proc(node: ^Tween_Node) -> ^Managed_Sequence_Data {
	if node == nil || node.kind != .Sequence || node.payload == nil do return nil
	return cast(^Managed_Sequence_Data)node.payload
}

@(private)
sequence_get_data_by_handle :: proc(manager: ^Tween_Manager, handle: Tween_Handle) -> ^Managed_Sequence_Data {
	node := manager_get_node_ptr(manager^, handle)
	if node == nil || node.kind != .Sequence do return nil
	return sequence_get_data(node)
}

@(private)
sequence_is_ancestor :: proc(manager: ^Tween_Manager, ancestor: Tween_Handle, child: Tween_Handle) -> bool {
	current := child
	for current != TWEEN_HANDLE_NONE {
		if current == ancestor do return true
		node := manager_get_node_ptr(manager^, current)
		if node == nil do return false
		current = node.parent
	}
	return false
}

// ------------------------------------------------------------------------------
// 时长计算 —— recompute / sync / child 总时长
// ------------------------------------------------------------------------------

@(private)
sequence_recompute_duration :: proc(data: ^Managed_Sequence_Data) -> f32 {
	if data == nil do return 0

	duration: f32 = 0
	for i := 0; i < len(data.runtime.entries); i += 1 {
		entry := data.runtime.entries[i]
		end_at := entry.start_at + entry.duration
		if end_at > duration do duration = end_at
	}
	data.runtime.duration = duration
	return duration
}

@(private)
sequence_sync_duration :: proc(manager: ^Tween_Manager, seq: Tween_Handle, data: ^Managed_Sequence_Data) {
	if data == nil do return
	seq_node := manager_get_node_ptr(manager^, seq)
	if seq_node == nil do return

	duration := sequence_recompute_duration(data)
	seq_node.timing.duration = duration

	if seq_node.parent == TWEEN_HANDLE_NONE do return

	parent_data := sequence_get_data_by_handle(manager, seq_node.parent)
	if parent_data == nil do return

	for i := 0; i < len(parent_data.runtime.entries); i += 1 {
		entry := &parent_data.runtime.entries[i]
		if entry.kind == .Tween && entry.child == seq {
			entry.duration = duration
			break
		}
	}

	sequence_sync_duration(manager, seq_node.parent, parent_data)
}

@(private)
sequence_child_total_duration :: proc(node: ^Tween_Node) -> (duration: f32, ok: bool) {
	if node == nil do return

	if node.loops.count < 0 {
		return 0, false
	}

	loop_count: i32 = 1
	if node.loops.count > 0 {
		loop_count = node.loops.count
	}

	duration = node.timing.delay + node.timing.duration * f32(loop_count)
	ok = true
	return
}

// ------------------------------------------------------------------------------
// 子节点挂接 —— prepare / attach（创建即挂接的内部通道）
// ------------------------------------------------------------------------------

@(private)
sequence_prepare_child :: proc(manager: ^Tween_Manager, seq: Tween_Handle, child: Tween_Handle) -> bool {
	node := manager_get_node_ptr(manager^, child)
	if node == nil do return false
	if child == seq do return false
	if node.parent != TWEEN_HANDLE_NONE do return false
	if sequence_is_ancestor(manager, child, seq) do return false

	_ = manager_rewind(manager, child)

	node.parent = seq
	node.active = false
	node.control.use_manager_auto_kill = false
	node.control.auto_kill = false
	return true
}

@(private)
sequence_attach_created_handle :: proc(
	manager: ^Tween_Manager,
	seq: Tween_Handle,
	handle: Tween_Handle,
	attach: Sequence_Attach_Proc,
) -> (Tween_Handle, bool) {
	if !attach(manager, seq, handle) {
		_ = manager_remove_node(manager, handle)
		return TWEEN_HANDLE_NONE, false
	}
	return handle, true
}

@(private)
sequence_attach_created_handle_at :: proc(
	manager: ^Tween_Manager,
	seq: Tween_Handle,
	at: f32,
	handle: Tween_Handle,
) -> (Tween_Handle, bool) {
	if !sequence_insert(manager, seq, at, handle) {
		_ = manager_remove_node(manager, handle)
		return TWEEN_HANDLE_NONE, false
	}
	return handle, true
}

// ------------------------------------------------------------------------------
// vtable 实现 —— update / reset / kill
// ------------------------------------------------------------------------------

@(private)
sequence_update_proc :: proc(node: ^Tween_Node, dt: f32) {
	_ = dt

	data := sequence_get_data(node)
	if data == nil || data.manager == nil do return

	manager := data.manager
	prev_cursor := data.runtime.cursor
	curr_cursor := node.timing.elapsed

	for i := 0; i < len(data.runtime.entries); i += 1 {
		entry := &data.runtime.entries[i]

		switch entry.kind {
		case .Tween:
			if curr_cursor < entry.start_at do continue

			child := manager_get_node_ptr(manager^, entry.child)
			if child == nil do continue

			if !child.active {
				child.active = true
				if child.timing.delay > 0 {
					child.control.state = .Delayed
					child.timing.start_at = manager.now + child.timing.delay
				} else {
					child.control.state = .Idle
				}
			}

			child_prev := prev_cursor
			if child_prev < entry.start_at do child_prev = entry.start_at

			child_curr := curr_cursor
			child_end := entry.start_at + entry.duration
			if child_curr > child_end do child_curr = child_end

			child_dt := child_curr - child_prev
			if child_dt <= 0 do continue

			update_node(manager, child, child_dt)

		case .Callback:
			if !entry.triggered && curr_cursor >= entry.start_at {
				if entry.callback != nil do entry.callback()
				entry.triggered = true
			}

		case .Interval:
		}
	}

	data.runtime.cursor = curr_cursor
	data.runtime.duration = node.timing.duration
}

@(private)
sequence_reset_proc :: proc(node: ^Tween_Node) {
	data := sequence_get_data(node)
	if data == nil || data.manager == nil do return

	data.runtime.cursor = 0

	for i := 0; i < len(data.runtime.entries); i += 1 {
		entry := &data.runtime.entries[i]
		entry.triggered = false

		if entry.kind == .Tween {
			_ = manager_rewind(data.manager, entry.child)
		}
	}
}

@(private)
sequence_kill_proc :: proc(node: ^Tween_Node) {
	data := sequence_get_data(node)
	if data == nil do return

	if data.manager != nil {
		for i := 0; i < len(data.runtime.entries); i += 1 {
			entry := data.runtime.entries[i]
			if entry.kind != .Tween do continue

			child := manager_get_node_ptr(data.manager^, entry.child)
			if child == nil do continue

			child.parent = TWEEN_HANDLE_NONE
			_ = manager_kill(data.manager, entry.child)
		}
	}

	delete(data.runtime.entries)
	free(data)
	node.payload = nil
}

// ------------------------------------------------------------------------------
// 创建 —— manager_add_sequence
// ------------------------------------------------------------------------------

// Sequence 创建入口。
// 外部通过它创建一个可继续 Append/Join/Insert/Prepend 的 sequence 节点。
manager_add_sequence :: proc(manager: ^Tween_Manager) -> Tween_Handle {
	data := new(Managed_Sequence_Data)
	data^ = {
		manager = manager,
	}

	node := Tween_Node{
		kind = .Sequence,
		active = true,
		parent = TWEEN_HANDLE_NONE,

		timing = Tween_Timing{
			duration = 0,
			time_scale = 1,
		},

		loops = Loop_Config{
			count = 1,
			mode = .Once,
		},

		control = Tween_Control{
			state = .Idle,
			auto_kill = true,
		},

		payload = data,
		vtable = Tween_Node_VTable{
			update = sequence_update_proc,
			reset  = sequence_reset_proc,
			kill   = sequence_kill_proc,
		},
	}

	return manager_add_node(manager, node)
}

// ------------------------------------------------------------------------------
// 时间轴组装 —— append / join / insert / prepend（各带 _tween 便捷版）
// ------------------------------------------------------------------------------

// 将一个已注册到 manager 的 child 节点追加到 sequence 末尾。
sequence_append :: proc(manager: ^Tween_Manager, seq: Tween_Handle, child: Tween_Handle) -> bool {
	data := sequence_get_data_by_handle(manager, seq)
	if data == nil do return false

	child_node := manager_get_node_ptr(manager^, child)
	if child_node == nil do return false

	duration, ok := sequence_child_total_duration(child_node)
	if !ok do return false
	if !sequence_prepare_child(manager, seq, child) do return false

	entry := Sequence_Entry{
		kind = .Tween,
		child = child,
		start_at = data.runtime.duration,
		duration = duration,
	}

	append(&data.runtime.entries, entry)

	sequence_sync_duration(manager, seq, data)

	return true
}

// 便捷版本：内部自动创建 tween 节点并追加到 sequence 末尾。
sequence_append_tween :: proc(
	manager: ^Tween_Manager,
	seq: Tween_Handle,
	tween: Tween($T),
	setter: proc "contextless" (value: T),
) -> (handle: Tween_Handle, ok: bool) {
	handle = manager_add_tween(manager, tween, setter)
	return sequence_attach_created_handle(manager, seq, handle, sequence_append)
}

// 便捷属性绑定版本：内部自动创建 tween 节点并把结果直接写入目标指针。
sequence_append_tween_to :: proc(
	manager: ^Tween_Manager,
	seq: Tween_Handle,
	tween: Tween($T),
	target: ^T,
) -> (handle: Tween_Handle, ok: bool) {
	handle = manager_add_tween_to(manager, tween, target)
	return sequence_attach_created_handle(manager, seq, handle, sequence_append)
}

// 属性绑定版本：通过 getter 读取当前值，再通过 setter 写回目标。
sequence_append_property_tween :: proc(
	manager: ^Tween_Manager,
	seq: Tween_Handle,
	getter: proc "contextless" () -> $T,
	setter: proc "contextless" (value: T),
	finish: T,
	config: Tween_Config,
	lerp: proc "contextless" (a, b: T, ratio: f32) -> T,
) -> (handle: Tween_Handle, ok: bool) {
	start := getter()
	tween := make_ex(start, finish, 0, config, lerp)
	return sequence_append_tween(manager, seq, tween, setter)
}

// 将一个已注册到 manager 的 child 节点并入 sequence 当前最后一段的起始时间。
sequence_join :: proc(manager: ^Tween_Manager, seq: Tween_Handle, child: Tween_Handle) -> bool {
	data := sequence_get_data_by_handle(manager, seq)
	if data == nil do return false

	child_node := manager_get_node_ptr(manager^, child)
	if child_node == nil do return false

	duration, ok := sequence_child_total_duration(child_node)
	if !ok do return false
	if !sequence_prepare_child(manager, seq, child) do return false

	start_at: f32 = 0
	if len(data.runtime.entries) > 0 {
		start_at = data.runtime.entries[len(data.runtime.entries)-1].start_at
	}

	entry := Sequence_Entry{
		kind = .Tween,
		child = child,
		start_at = start_at,
		duration = duration,
	}

	append(&data.runtime.entries, entry)

	sequence_sync_duration(manager, seq, data)

	return true
}

// 便捷版本：内部自动创建 tween 节点并 Join 到当前最后一段。
sequence_join_tween :: proc(
	manager: ^Tween_Manager,
	seq: Tween_Handle,
	tween: Tween($T),
	setter: proc "contextless" (value: T),
) -> (handle: Tween_Handle, ok: bool) {
	handle = manager_add_tween(manager, tween, setter)
	return sequence_attach_created_handle(manager, seq, handle, sequence_join)
}

// 便捷属性绑定版本：内部自动创建 tween 节点并 Join 到当前最后一段。
sequence_join_tween_to :: proc(
	manager: ^Tween_Manager,
	seq: Tween_Handle,
	tween: Tween($T),
	target: ^T,
) -> (handle: Tween_Handle, ok: bool) {
	handle = manager_add_tween_to(manager, tween, target)
	return sequence_attach_created_handle(manager, seq, handle, sequence_join)
}

// 属性绑定版本：通过 getter 读取当前值，再通过 setter 写回目标。
sequence_join_property_tween :: proc(
	manager: ^Tween_Manager,
	seq: Tween_Handle,
	getter: proc "contextless" () -> $T,
	setter: proc "contextless" (value: T),
	finish: T,
	config: Tween_Config,
	lerp: proc "contextless" (a, b: T, ratio: f32) -> T,
) -> (handle: Tween_Handle, ok: bool) {
	start := getter()
	tween := make_ex(start, finish, 0, config, lerp)
	return sequence_join_tween(manager, seq, tween, setter)
}

// 将一个已注册到 manager 的 child 节点插入到 sequence 本地时间轴的指定位置。
sequence_insert :: proc(manager: ^Tween_Manager, seq: Tween_Handle, at: f32, child: Tween_Handle) -> bool {
	data := sequence_get_data_by_handle(manager, seq)
	if data == nil do return false
	if at < 0 do return false

	child_node := manager_get_node_ptr(manager^, child)
	if child_node == nil do return false

	duration, ok := sequence_child_total_duration(child_node)
	if !ok do return false
	if !sequence_prepare_child(manager, seq, child) do return false

	entry := Sequence_Entry{
		kind = .Tween,
		child = child,
		start_at = at,
		duration = duration,
	}

	append(&data.runtime.entries, entry)
	sequence_sync_duration(manager, seq, data)
	return true
}

// 便捷版本：内部自动创建 tween 节点并插入到指定位置。
sequence_insert_tween :: proc(
	manager: ^Tween_Manager,
	seq: Tween_Handle,
	at: f32,
	tween: Tween($T),
	setter: proc "contextless" (value: T),
) -> (handle: Tween_Handle, ok: bool) {
	handle = manager_add_tween(manager, tween, setter)
	return sequence_attach_created_handle_at(manager, seq, at, handle)
}

// 便捷属性绑定版本：内部自动创建 tween 节点并插入到指定位置。
sequence_insert_tween_to :: proc(
	manager: ^Tween_Manager,
	seq: Tween_Handle,
	at: f32,
	tween: Tween($T),
	target: ^T,
) -> (handle: Tween_Handle, ok: bool) {
	handle = manager_add_tween_to(manager, tween, target)
	return sequence_attach_created_handle_at(manager, seq, at, handle)
}

// 属性绑定版本：通过 getter 读取当前值，再通过 setter 写回目标。
sequence_insert_property_tween :: proc(
	manager: ^Tween_Manager,
	seq: Tween_Handle,
	at: f32,
	getter: proc "contextless" () -> $T,
	setter: proc "contextless" (value: T),
	finish: T,
	config: Tween_Config,
	lerp: proc "contextless" (a, b: T, ratio: f32) -> T,
) -> (handle: Tween_Handle, ok: bool) {
	start := getter()
	tween := make_ex(start, finish, 0, config, lerp)
	return sequence_insert_tween(manager, seq, at, tween, setter)
}

// 将一个已注册到 manager 的 child 节点前插到 sequence 起点，并整体后移原时间轴。
sequence_prepend :: proc(manager: ^Tween_Manager, seq: Tween_Handle, child: Tween_Handle) -> bool {
	data := sequence_get_data_by_handle(manager, seq)
	if data == nil do return false

	child_node := manager_get_node_ptr(manager^, child)
	if child_node == nil do return false

	duration, ok := sequence_child_total_duration(child_node)
	if !ok do return false
	if !sequence_prepare_child(manager, seq, child) do return false

	for i := 0; i < len(data.runtime.entries); i += 1 {
		data.runtime.entries[i].start_at += duration
	}

	entry := Sequence_Entry{
		kind = .Tween,
		child = child,
		start_at = 0,
		duration = duration,
	}

	append(&data.runtime.entries, entry)
	sequence_sync_duration(manager, seq, data)
	return true
}

// 便捷版本：内部自动创建 tween 节点并前插到 sequence 起点。
sequence_prepend_tween :: proc(
	manager: ^Tween_Manager,
	seq: Tween_Handle,
	tween: Tween($T),
	setter: proc "contextless" (value: T),
) -> (handle: Tween_Handle, ok: bool) {
	handle = manager_add_tween(manager, tween, setter)
	return sequence_attach_created_handle(manager, seq, handle, sequence_prepend)
}

// 便捷属性绑定版本：内部自动创建 tween 节点并前插到 sequence 起点。
sequence_prepend_tween_to :: proc(
	manager: ^Tween_Manager,
	seq: Tween_Handle,
	tween: Tween($T),
	target: ^T,
) -> (handle: Tween_Handle, ok: bool) {
	handle = manager_add_tween_to(manager, tween, target)
	return sequence_attach_created_handle(manager, seq, handle, sequence_prepend)
}

// 属性绑定版本：通过 getter 读取当前值，再通过 setter 写回目标。
sequence_prepend_property_tween :: proc(
	manager: ^Tween_Manager,
	seq: Tween_Handle,
	getter: proc "contextless" () -> $T,
	setter: proc "contextless" (value: T),
	finish: T,
	config: Tween_Config,
	lerp: proc "contextless" (a, b: T, ratio: f32) -> T,
) -> (handle: Tween_Handle, ok: bool) {
	start := getter()
	tween := make_ex(start, finish, 0, config, lerp)
	return sequence_prepend_tween(manager, seq, tween, setter)
}

// 在 sequence 尾部追加一个回调步骤。
sequence_append_callback :: proc(manager: ^Tween_Manager, seq: Tween_Handle, callback: Sequence_Callback_Proc) -> bool {
	data := sequence_get_data_by_handle(manager, seq)
	if data == nil do return false

	entry := Sequence_Entry{
		kind = .Callback,
		callback = callback,
		start_at = data.runtime.duration,
		duration = 0,
	}

	append(&data.runtime.entries, entry)

	sequence_sync_duration(manager, seq, data)

	return true
}

// 在 sequence 尾部追加一段纯等待时间。
sequence_append_interval :: proc(manager: ^Tween_Manager, seq: Tween_Handle, interval: f32) -> bool {
	data := sequence_get_data_by_handle(manager, seq)
	if data == nil do return false
	if interval < 0 do return false

	entry := Sequence_Entry{
		kind = .Interval,
		start_at = data.runtime.duration,
		duration = interval,
	}

	append(&data.runtime.entries, entry)

	sequence_sync_duration(manager, seq, data)

	return true
}
