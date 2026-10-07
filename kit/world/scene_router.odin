// SceneRouter —— 轻量屏幕/场景路由（对位 DragonLib Engine.World.SceneRouter）。
//
// 只负责记录"当前是哪个屏幕"、切换、以及切换过程的计时进度；不携带屏幕的
// 业务逻辑，也不知道过渡该画成什么样（淡入淡出/滑动由调用方按 Progress 决定）。
// 具体有哪些屏幕由游戏自己定义 enum 传入。
package world

import "core:math"

// Scene_Router(Screen) —— Screen 用 enum（或任何可 == 比较的小值类型）。
// 注意：Screen 是泛型参数，调用处不能写隐式枚举选择子（.Title），
// 要用显式成员名（Screen.Title）。
// Progress 非过渡状态下恒为 1；过渡期间渲染代码可同时绘制 Previous 与
// Current 两屏做过渡效果。
Scene_Router :: struct($Screen: typeid) {
	Current:      Screen,
	Previous:     Screen,
	Transitioning: bool,
	Progress:     f32, // 0..1

	duration: f32,
	elapsed:  f32,
}

scene_router_init :: proc(r: ^Scene_Router($Screen), initial: Screen) {
	r^ = {
		Current  = initial,
		Previous = initial,
		Progress = 1,
	}
}

// 切换到目标屏幕。duration > 0 时进入过渡：Current 立即更新，Progress 从 0
// 随 scene_router_update 推进到 1，期间 Previous 保留切换前的屏幕。
// duration == 0 立即完成。切到当前屏幕是无操作。
scene_router_switch :: proc(r: ^Scene_Router($Screen), screen: Screen, duration: f32 = 0) {
	if r.Current == screen do return
	r.Previous = r.Current
	r.Current = screen

	if duration > 0 {
		r.duration = duration
		r.elapsed = 0
		r.Progress = 0
		r.Transitioning = true
	} else {
		r.Transitioning = false
		r.Progress = 1
	}
}

// 推进过渡计时；非过渡状态下无副作用。
scene_router_update :: proc(r: ^Scene_Router($Screen), dt: f32) {
	if !r.Transitioning do return
	r.elapsed += dt
	r.Progress = r.duration <= 0 ? 1 : math.clamp(r.elapsed / r.duration, 0, 1)
	if r.Progress >= 1 do r.Transitioning = false
}
