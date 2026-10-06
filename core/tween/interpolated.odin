// 插值原语：start -> finish 的时间归一化采样与缓动曲线。
// Tween / Managed_Tween 都以它为基础；不含循环模式（那在 tween.odin）。
package tween

import math "core:math"

// 分区：
//   类型 —— Transition / Interpolated
//   缓动曲线 —— interp_get_ratio_internal
//   配置 —— interp_set_duration / interp_set_transition_proc
//   采样 —— interp_get_value / interp_get_elapsed_seconds / interp_set_value*

// ------------------------------------------------------------------------------
// 类型 —— Transition / Interpolated
// ------------------------------------------------------------------------------

// 缓动类型。.Custom 时使用 Interpolated.transition_proc。
Transition :: enum u8 {
	None,
	Linear,
	Custom,
	EaseIn,
	EaseInOut,
	EaseOut,
	EaseInBack,
	EaseOutElastic,
}

// 值语义插值器：speed = 1/duration（duration<=0 时为 1e30，即瞬时完成）。
Interpolated :: struct($T: typeid) {
	start:          T,
	finish:         T,
	start_time:     f32,
	speed:          f32,
	transition:     Transition,
	transition_proc: proc "contextless" (t: f32) -> f32,
	lerp:           proc "contextless" (a, b: T, ratio: f32) -> T,
}

// ------------------------------------------------------------------------------
// 缓动曲线 —— interp_get_ratio_internal
// ------------------------------------------------------------------------------

// t 为归一化进度（0..1，调用方已裁剪）；返回施加缓动后的比例。
interp_get_ratio_internal :: proc(interp: ^Interpolated($T), t: f32) -> f32 {
	time := math.clamp(t, 0, 1)

	switch interp.transition {
	case .None:
		return 1

	case .Linear:
		return time

	case .Custom:
		if interp.transition_proc != nil {
			return math.clamp(interp.transition_proc(time), 0, 1)
		}
		return time

	case .EaseIn:
		return time * time * time

	case .EaseInOut:
		if time < 0.5 {
			return 4 * time * time * time
		}
		x := -2 * time + 2
		return 1 - (x * x * x) * 0.5

	case .EaseOut:
		x := 1 - time
		return 1 - x * x * x

	case .EaseInBack:
		c1: f32 = 1.70158
		c3 := c1 + 1
		return c3 * time * time * time - c1 * time * time

	case .EaseOutElastic:
		if time <= 0 {
			return 0
		}
		if time >= 1 {
			return 1
		}
		c4: f32 = 2.0943952 // 2*pi/3
		return math.pow(2.0, -10.0 * time) * math.sin((time * 10.0 - 0.75) * c4) + 1.0
	}

	return time
}

// ------------------------------------------------------------------------------
// 配置 —— interp_set_duration / interp_set_transition_proc
// ------------------------------------------------------------------------------

interp_set_transition_proc :: proc(interp: ^Interpolated($T), transition_proc: proc "contextless" (t: f32) -> f32) {
	interp.transition = .Custom
	interp.transition_proc = transition_proc
}

// Set the duration of the interpolation.
interp_set_duration :: proc(interp: ^Interpolated($T), duration: f32) {
	if duration <= 0 {
		interp.speed = 1.0e30
		return
	}
	interp.speed = 1.0 / duration
}

// ------------------------------------------------------------------------------
// 采样 —— interp_get_value / interp_get_elapsed_seconds / interp_set_value*
// ------------------------------------------------------------------------------

interp_get_elapsed_seconds :: proc(interp: ^Interpolated($T), current_time: f32) -> f32 {
	return current_time - interp.start_time
}

// Get the value at the given time.
interp_get_value :: proc(interp: ^Interpolated($T), current_time: f32) -> T {
	t := interp_get_elapsed_seconds(interp, current_time) * interp.speed

	if t <= 0 {
		return interp.start
	}
	if t >= 1 {
		return interp.finish
	}

	ratio := interp_get_ratio_internal(interp, t)
	return interp.lerp(interp.start, interp.finish, ratio)
}

// 从当前插值结果继续插向新的目标值。
interp_set_value :: proc(interp: ^Interpolated($T), new_value: T, current_time: f32) {
	interp.start = interp_get_value(interp, current_time)
	interp.finish = new_value
	interp.start_time = current_time
}

// 从当前插值结果继续插向新的目标值，同时设置插值函数。
interp_set_value_full :: proc(
	interp: ^Interpolated($T),
	now_value, new_value: T,
	current_time: f32,
	transition: Transition,
	lerp: proc "contextless" (a, b: T, ratio: f32) -> T,
) {
	interp.start = now_value
	interp.finish = new_value
	interp.start_time = current_time
	interp.transition = transition
	interp.transition_proc = nil
	interp.lerp = lerp
}
