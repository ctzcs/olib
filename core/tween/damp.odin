// 目标追随：不建 Tween 节点、每帧直接追向可能随时变化的目标。
// 适合拖动归位、悬停抬起、容器伸缩这类目标随状态变化、无需时间轴的动画；
// 有固定时长和编排需求时仍用 Tween / Sequence。
package tween

@(require) import "core:math"

// 指数逼近：每秒剩余差距按 exp(-rate) 衰减，帧率无关、不会过冲。
// T 可为 f32 或 [N]f32（如 foster.Vec2）；rate 越大越快，约 4/rate 秒基本到位。
approach :: proc(current, target: $T, rate, dt: f32) -> T {
	return current + (target - current) * (1 - math.exp(-rate * dt))
}

// 临界阻尼弹簧（同 Unity SmoothDamp）：保留速度，目标移动时平滑转向，任意 dt 下稳定。
// smooth_time 约为到达目标所需时间；velocity 由调用方跨帧保存。dt <= 0 时原样返回。
smooth_damp :: proc(current, velocity, target: $T, smooth_time, dt: f32) -> (value: T, next_velocity: T) {
	if dt <= 0 || smooth_time <= 0 {
		return smooth_time <= 0 ? target : current, smooth_time <= 0 ? T{} : velocity
	}
	omega := 2 / smooth_time
	x := omega * dt
	decay := 1 / (1 + x + 0.48 * x * x + 0.235 * x * x * x)
	change := current - target
	temp := (velocity + omega * change) * dt
	return target + (change + temp) * decay, (velocity - omega * temp) * decay
}
