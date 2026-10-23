package ui

import tween "olib:core/tween"
import clay "olib:thirdparty/clay-odin"

// 分区：
//   参数 —— UI_Motion
//   追随与冲击 —— 每帧声明目标，状态按 ID 保存在 UI_Context
//   进出场 —— presence 进度与退场输入隔离
//   帧末回收 —— 本帧未声明的 ID 删除状态
//
// 便利层，建立在 ui_set_visual 之上：自算 UI_Visual、Tween/Sequence 与自绘照常可用，
// 同一 ID 本帧后续的 ui_set_visual 仍按最后一次注册覆盖，嵌套元素的变换照常合成。

// ------------------------------------------------------------------------------
// 参数
// ------------------------------------------------------------------------------

// time 约为到位所需秒数，0 为立即到位；bounce 0 为不过冲，越接近 1 越弹（见 tween.spring）。
// 游戏把参数写成具名常量集中放置，配合热重载调手感。
UI_Motion :: struct {
	time: f32,
	bounce: f32,
}

@(private)
UI_Motion_State :: struct {
	value, velocity: UI_Visual,
	seen: bool,
}

@(private)
UI_Presence_State :: struct {
	t, velocity: f32,
	seen: bool,
}

// ------------------------------------------------------------------------------
// 追随与冲击
// ------------------------------------------------------------------------------

// 按 ui_begin 的 dt 把该 ID 的当前值推向 target，注册为本帧视觉并返回当前值。
// 首次出现的 ID 直接取 target（入场用 ui_presence）；目标中途改变时保留速度，无需打断。
ui_motion :: proc(ctx: ^UI_Context, id: string, target: UI_Visual, motion: UI_Motion) -> UI_Visual {
	key := clay.ID(id).id
	state, found := &ctx.motions[key]
	if !found {
		ctx.motions[key] = UI_Motion_State{value = target, seen = true}
		ui_set_visual(ctx, id, target)
		return target
	}
	if !state.seen {
		state.value, state.velocity = ui_motion_step(state.value, state.velocity, target, motion, ctx.delta_time)
		state.seen = true
	}
	ui_set_visual(ctx, id, state.value)
	return state.value
}

// 给已有状态叠加速度（各字段单位/秒，零值字段无冲击），下一次推进生效并由弹簧回到目标。
// 例如按压回弹 {scale = {-2, -2}}。ID 尚未经 ui_motion 声明时忽略。
ui_motion_kick :: proc(ctx: ^UI_Context, id: string, velocity: UI_Visual) {
	if state, found := &ctx.motions[clay.ID(id).id]; found {
		state.velocity = ui_visual_add(state.velocity, velocity)
	}
}

// 读取当前值与速度，供定制动画在原语结果上加工；ID 没有状态时 ok=false。
ui_motion_state :: proc(ctx: ^UI_Context, id: string) -> (value, velocity: UI_Visual, ok: bool) {
	state, found := ctx.motions[clay.ID(id).id]
	return state.value, state.velocity, found
}

@(private)
ui_motion_step :: proc(value, velocity, target: UI_Visual, motion: UI_Motion, dt: f32) -> (UI_Visual, UI_Visual) {
	next, next_velocity: UI_Visual
	next.offset, next_velocity.offset = tween.spring(value.offset, velocity.offset, target.offset, motion.time, motion.bounce, dt)
	next.scale, next_velocity.scale = tween.spring(value.scale, velocity.scale, target.scale, motion.time, motion.bounce, dt)
	next.rotation, next_velocity.rotation = tween.spring(value.rotation, velocity.rotation, target.rotation, motion.time, motion.bounce, dt)
	next.pivot, next_velocity.pivot = tween.spring(value.pivot, velocity.pivot, target.pivot, motion.time, motion.bounce, dt)
	next.opacity, next_velocity.opacity = tween.spring(value.opacity, velocity.opacity, target.opacity, motion.time, motion.bounce, dt)
	return next, next_velocity
}

@(private)
ui_visual_add :: proc "contextless" (a, b: UI_Visual) -> UI_Visual {
	return {a.offset + b.offset, a.scale + b.scale, a.rotation + b.rotation, a.pivot + b.pivot, a.opacity + b.opacity}
}

// ------------------------------------------------------------------------------
// 进出场
// ------------------------------------------------------------------------------

// open 为 true 时进度 t 向 1 推进（enter），false 时向 0 退回（exit）；弹性参数下 t 可能过冲。
// t 怎样映射成画面由调用方决定（如 ui_visual_lerp 或自算）。alive 为 false 时不再声明该元素。
// 退场期间该 ID 的子树从下一帧起不接受指针命中、不参与键盘导航；同名元素须在本帧声明。
ui_presence :: proc(ctx: ^UI_Context, id: string, open: bool, enter, exit: UI_Motion) -> (alive: bool, t: f32) {
	key := clay.ID(id).id
	state, found := &ctx.presences[key]
	if !found {
		if !open {
			return false, 0
		}
		ctx.presences[key] = {}
		state = &ctx.presences[key]
	}
	if !state.seen {
		motion := open ? enter : exit
		state.t, state.velocity = tween.spring(state.t, state.velocity, open ? 1 : 0, motion.time, motion.bounce, ctx.delta_time)
		state.seen = true
	}
	if !open && state.t <= UI_PRESENCE_EPSILON {
		delete_key(&ctx.presences, key)
		return false, 0
	}
	if !open {
		ctx.inert[key] = {}
	}
	return true, state.t
}

@(private)
UI_PRESENCE_EPSILON :: 0.001

// 上一帧布局中该元素位于退场子树内。
@(private)
ui_visual_inert :: proc "contextless" (ctx: ^UI_Context, id: u32) -> bool {
	e, found := ctx.visual_elements[id]
	return found && e.inert
}

// ------------------------------------------------------------------------------
// 帧末回收
// ------------------------------------------------------------------------------

@(private)
ui_motion_end :: proc(ctx: ^UI_Context) {
	ui_motion_prune(&ctx.motions)
	ui_motion_prune(&ctx.presences)
}

// 遍历中不删键：先收集再删。
@(private)
ui_motion_prune :: proc(states: ^map[u32]$T) {
	stale := make([dynamic]u32, context.temp_allocator)
	for key, &state in states {
		if !state.seen {
			append(&stale, key)
		}
		state.seen = false
	}
	for key in stale {
		delete_key(states, key)
	}
}
