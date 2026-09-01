# tween

`olib/tween` 现在包含三层能力：

- 基础补间：单条 `Tween(T)` 的插值、delay、loop、pingpong
- 运行时管理：`Tween_Manager` 统一驱动、暂停、重播、回收
- 编排：`Sequence` 支持 `Append / Join / Insert / Prepend / Callback / Interval`

这份文档只介绍当前已经实现并验证过的 API 和最小用法。

## 结构

- `tween.odin`
  - 单条 tween 的核心插值逻辑
- `interpolated.odin`
  - easing 与插值辅助
- `manager.odin`
  - 运行时节点、句柄、统一调度
- `managed_tween.odin`
  - 把 `Tween(T)` 接入 `Tween_Manager`
- `managed_sequence.odin`
  - Sequence 编排和便捷接口
- `test.odin`
  - 当前最小可运行示例

## 基础概念

### Tween

`Tween(T)` 是单条补间，负责：

- 从起始值插到目标值
- 处理 easing
- 处理 delay
- 处理 `Once / Loop / PingPong`

如果你只想手动按时间采样，不需要 manager，也可以直接用它。

### Tween_Manager

`Tween_Manager` 是统一运行时，负责：

- 持有所有活跃 tween / sequence 节点
- `update(dt)` 推进时间
- `play / pause / rewind / restart / kill`
- 自动清理已完成节点

### Sequence

`Sequence` 是编排容器，负责：

- 顺序执行多个 tween
- 并行执行多个 tween
- 在时间轴上插入 callback
- 在时间轴上插入 interval

## 已实现能力

- `Tween(T)` 手动采样
- `Tween_Manager` 驱动单条 tween
- `delay`
- `rewind / restart`
- `Loop`
- 有限 loop 次数
- `Sequence Append`
- `Sequence Join`
- `Sequence Insert`
- `Sequence Prepend`
- `Sequence AppendCallback`
- `Sequence AppendInterval`
- `Sequence` 嵌套 `Sequence`

## 未完成或暂未整理

- `Sequence` 自己的 loop
- 更丰富的属性绑定 helper
- 更完整的调试接口
- `From / Relative`

## 基础 Tween 用法

推荐优先使用 `make_ex(...)`，把常见配置一次写完：

```odin
tw := make_ex(f32(0), f32(10), 0, Tween_Config{
	duration = 1.0,
	delay = 0.25,
	repeat_mode = .Once,
	transition = .Linear,
}, lerp_f32)

value := tween_get_value(&tw, 0.5)
finished := tween_is_finished(&tw, 0.5)
```

底层场景下也可以继续用 `make(...) + setter`：

```odin
tw := make(f32(0), f32(10), 0, .Linear, lerp_f32)
tween_set_duration(&tw, 1.0)
tween_set_delay(&tw, 0.25)
```

常用补充设置：

- `tween_set_duration(&tw, seconds)`
- `tween_set_delay(&tw, seconds)`
- `tween_set_repeat_mode(&tw, .Once/.Loop/.PingPong)`

## Manager 用法

### 1. 创建 manager

```odin
mgr := manager_make()
```

### 2. 创建 tween 并接入 manager

`manager_add_tween` 需要一个 `setter`。  
manager 每帧算出当前值后，会通过 `setter` 把值写回目标。

推荐优先级：

- 首选：`manager_add_tween_to`
- 其次：`manager_add_property_tween`
- 底层场景：`manager_add_tween`

```odin
value_x: f32

set_value_x :: proc "contextless" (value: f32) {
	value_x = value
}

tw := make_ex(f32(0), f32(10), 0, Tween_Config{
	duration = 1.0,
	transition = .Linear,
}, lerp_f32)

h := manager_add_tween(&mgr, tw, set_value_x)
```

如果你只是想直接把结果写回某个变量或字段，推荐用指针绑定版本：

```odin
value_x: f32

tw := make_ex(f32(0), f32(10), 0, Tween_Config{
	duration = 1.0,
	transition = .Linear,
}, lerp_f32)

h := manager_add_tween_to(&mgr, tw, &value_x)
```

如果你更想要“读当前值 + 写回目标”的属性风格，可以用 getter + setter 版本：

```odin
get_value_x :: proc "contextless" () -> f32 {
	return value_x
}

set_value_x :: proc "contextless" (value: f32) {
	value_x = value
}

h := manager_add_property_tween(&mgr, get_value_x, set_value_x, f32(10), Tween_Config{
	duration = 1.0,
	transition = .Linear,
}, lerp_f32)
```

### 3. 每帧 update

```odin
manager_update(&mgr, dt)
```

### 4. 控制接口

当前对外可用的 manager API：

- `manager_make() -> Tween_Manager`
- `manager_is_handle_valid(manager, handle) -> bool`
- `manager_play(&manager, handle) -> bool`
- `manager_pause(&manager, handle) -> bool`
- `manager_add_tween_to(&manager, tween, target) -> Tween_Handle`
- `manager_add_property_tween(&manager, getter, setter, finish, config, lerp) -> Tween_Handle`
- `manager_set_callbacks(&manager, handle, callbacks) -> bool`
- `manager_on_start(&manager, handle, callback) -> bool`
- `manager_on_update(&manager, handle, callback) -> bool`
- `manager_on_step_complete(&manager, handle, callback) -> bool`
- `manager_on_complete(&manager, handle, callback) -> bool`
- `manager_on_kill(&manager, handle, callback) -> bool`
- `manager_clear_callbacks(&manager, handle) -> bool`
- `manager_rewind(&manager, handle) -> bool`
- `manager_restart(&manager, handle) -> bool`
- `manager_complete(&manager, handle) -> bool`
- `manager_kill(&manager, handle) -> bool`
- `manager_set_loops(&manager, handle, count, mode) -> bool`
- `manager_set_auto_kill(&manager, handle, enabled) -> bool`
- `manager_update(&manager, dt)`
- `manager_clear(&manager)`
- `manager_delete(&manager)`

### 5. Loop 示例

```odin
tw := make_ex(f32(0), f32(1), 0, Tween_Config{
	duration = 0.5,
	repeat_mode = .Loop,
	transition = .Linear,
}, lerp_f32)

h := manager_add_tween(&mgr, tw, set_value_x)
_ = manager_set_loops(&mgr, h, 3, .Loop)
```

含义：

- `count = -1` 表示无限循环
- `count > 0` 表示有限循环次数

### 6. Callback 绑定

```odin
on_start :: proc "contextless" (_: Tween_Handle) {
	// 开始时触发
}

on_complete :: proc "contextless" (_: Tween_Handle) {
	// 完成时触发
}

_ = manager_on_start(&mgr, h, on_start)
_ = manager_on_complete(&mgr, h, on_complete)
```

如果想一次设置多种回调：

```odin
_ = manager_set_callbacks(&mgr, h, Tween_Callbacks{
	on_start = on_start,
	on_complete = on_complete,
})
```

如果想清空已有回调：

```odin
_ = manager_clear_callbacks(&mgr, h)
```

## Sequence 用法

### 1. 创建 sequence

```odin
seq := manager_add_sequence(&mgr)
```

### 2. 追加 tween

最推荐直接用便捷版本：

```odin
tw_a := make_ex(f32(0), f32(10), 0, Tween_Config{
	duration = 1.0,
	transition = .Linear,
}, lerp_f32)

tw_b := make_ex(f32(100), f32(200), 0, Tween_Config{
	duration = 1.0,
	transition = .Linear,
}, lerp_f32)

_, _ = sequence_append_tween(&mgr, seq, tw_a, set_value_a)
_, _ = sequence_append_tween(&mgr, seq, tw_b, set_value_b)
```

效果：

- A 先执行
- A 结束后 B 再执行

### 3. Join

```odin
_, _ = sequence_append_tween(&mgr, seq, tw_a, set_value_a)
_, _ = sequence_join_tween(&mgr, seq, tw_b, set_value_b)
```

或：

```odin
_, _ = sequence_append_tween_to(&mgr, seq, tw_a, &value_a)
_, _ = sequence_join_tween_to(&mgr, seq, tw_b, &value_b)
```

或：

```odin
_, _ = sequence_append_property_tween(&mgr, seq, get_value_a, set_value_a, f32(10), Tween_Config{
	duration = 1.0,
	transition = .Linear,
}, lerp_f32)
_, _ = sequence_join_property_tween(&mgr, seq, get_value_b, set_value_b, f32(200), Tween_Config{
	duration = 1.0,
	transition = .Linear,
}, lerp_f32)
```

效果：

- A 和 B 同时开始

### 4. Insert

```odin
_, _ = sequence_append_tween(&mgr, seq, tw_a, set_value_a)
_, _ = sequence_insert_tween(&mgr, seq, 0.5, tw_b, set_value_b)
```

效果：

- A 从 `0.0s` 开始
- B 从 sequence 本地时间 `0.5s` 开始

### 5. Prepend

```odin
_, _ = sequence_append_tween(&mgr, seq, tw_a, set_value_a)
_, _ = sequence_prepend_tween(&mgr, seq, tw_b, set_value_b)
```

也可以直接绑定到目标值：

```odin
_, _ = sequence_append_tween_to(&mgr, seq, tw_a, &value_a)
_, _ = sequence_append_tween_to(&mgr, seq, tw_b, &value_b)
```

如果你想按属性方式创建，也可以直接传 getter + setter：

```odin
_, _ = sequence_append_property_tween(&mgr, seq, get_value_a, set_value_a, f32(10), Tween_Config{
	duration = 1.0,
	transition = .Linear,
}, lerp_f32)
```

效果：

- B 被插到最前面
- 原本的时间轴整体后移

### 6. Callback 和 Interval

```odin
on_done :: proc "contextless" () {
	// 自定义逻辑
}

_ = sequence_append_interval(&mgr, seq, 0.25)
_ = sequence_append_callback(&mgr, seq, on_done)
```

## Sequence 对外 API

当前对外可用的 Sequence API：

- `manager_add_sequence(&manager) -> Tween_Handle`
- `sequence_append(&manager, seq, child) -> bool`
- `sequence_append_tween(&manager, seq, tween, setter) -> (Tween_Handle, bool)`
- `sequence_append_tween_to(&manager, seq, tween, target) -> (Tween_Handle, bool)`
- `sequence_append_property_tween(&manager, seq, getter, setter, finish, config, lerp) -> (Tween_Handle, bool)`
- `sequence_join(&manager, seq, child) -> bool`
- `sequence_join_tween(&manager, seq, tween, setter) -> (Tween_Handle, bool)`
- `sequence_join_tween_to(&manager, seq, tween, target) -> (Tween_Handle, bool)`
- `sequence_join_property_tween(&manager, seq, getter, setter, finish, config, lerp) -> (Tween_Handle, bool)`
- `sequence_insert(&manager, seq, at, child) -> bool`
- `sequence_insert_tween(&manager, seq, at, tween, setter) -> (Tween_Handle, bool)`
- `sequence_insert_tween_to(&manager, seq, at, tween, target) -> (Tween_Handle, bool)`
- `sequence_insert_property_tween(&manager, seq, at, getter, setter, finish, config, lerp) -> (Tween_Handle, bool)`
- `sequence_prepend(&manager, seq, child) -> bool`
- `sequence_prepend_tween(&manager, seq, tween, setter) -> (Tween_Handle, bool)`
- `sequence_prepend_tween_to(&manager, seq, tween, target) -> (Tween_Handle, bool)`
- `sequence_prepend_property_tween(&manager, seq, getter, setter, finish, config, lerp) -> (Tween_Handle, bool)`
- `sequence_append_callback(&manager, seq, callback) -> bool`
- `sequence_append_interval(&manager, seq, interval) -> bool`

说明：

- `child` 版本用于你已经手动创建了 manager 节点的情况
- `*_tween` 版本是更顺手的外层 API，通常优先用它
- `*_tween_to` 版本适合直接绑定目标值，不用额外声明 `setter`
- `*_property_tween` 版本适合按 getter + setter 方式绑定对象属性，但通常不需要作为第一选择

## 最小完整示例

```odin
package demo

import tween "olib:tween"

value_a: f32
value_b: f32

set_a :: proc "contextless" (value: f32) {
	value_a = value
}

set_b :: proc "contextless" (value: f32) {
	value_b = value
}

main :: proc() {
	mgr := tween.manager_make()
	seq := tween.manager_add_sequence(&mgr)

	tw_a := tween.make_ex(f32(0), f32(10), 0, tween.Tween_Config{
		duration = 1.0,
		transition = .Linear,
	}, tween.lerp_f32)

	tw_b := tween.make_ex(f32(100), f32(200), 0, tween.Tween_Config{
		duration = 1.0,
		transition = .Linear,
	}, tween.lerp_f32)

	_, _ = tween.sequence_append_tween_to(&mgr, seq, tw_a, &value_a)
	_, _ = tween.sequence_join_tween_to(&mgr, seq, tw_b, &value_b)

	tween.manager_update(&mgr, 0.5)
	// 此时 value_a ~= 5, value_b ~= 150

	tween.manager_delete(&mgr)
}
```

## 当前建议

如果你是外部使用者，优先只记下面这几个入口：

- `make_ex`
- `manager_make`
- `manager_add_tween_to`
- `manager_add_property_tween`
- `manager_on_complete`
- `manager_update`
- `manager_add_sequence`
- `sequence_append_tween_to`
- `sequence_join_tween_to`
- `sequence_insert_tween_to`
- `sequence_prepend_tween_to`
- `sequence_append_callback`
- `sequence_append_interval`

补充入口：

- `manager_add_tween`
- `sequence_append_tween / sequence_join_tween / sequence_insert_tween / sequence_prepend_tween`
- `sequence_append_property_tween / sequence_join_property_tween`
- `sequence_insert_property_tween / sequence_prepend_property_tween`
- `tween_set_duration / tween_set_delay / tween_set_repeat_mode`

更底层的：

- `Tween_Node`
- `payload`
- `vtable`
- 内部 helper

这些现在都属于实现细节，不建议业务代码直接依赖。
