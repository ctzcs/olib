// 目标追随：不建 Tween 节点、每帧直接追向可能随时变化的目标。
// 适合拖动归位、悬停抬起、按压回弹、容器伸缩这类目标随状态变化、无需时间轴的动画；
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

// 阻尼弹簧（解析解，任意 dt 稳定）：time 约为到位所需秒数，bounce 0 为临界阻尼不过冲，
// 越接近 1 越弹（阻尼比 = 1 - bounce，上限按 0.95 处理，负值按 0）。
// 与 smooth_damp 同样由调用方跨帧保存 velocity；time <= 0 时立即到位，dt <= 0 时原样返回。
spring :: proc(current, velocity, target: $T, time, bounce, dt: f32) -> (value: T, next_velocity: T) {
	if time <= 0 {
		return target, T{}
	}
	if dt <= 0 {
		return current, velocity
	}
	omega := 2 * math.PI / time
	zeta := 1 - math.clamp(bounce, 0, 0.95)
	x := current - target
	decay := math.exp(-zeta * omega * dt)
	if zeta >= 1 {
		c := velocity + x * omega
		return target + (x + c * dt) * decay, (velocity - c * (omega * dt)) * decay
	}
	wd := omega * math.sqrt(1 - zeta * zeta)
	cs := math.cos(wd * dt)
	sn := math.sin(wd * dt)
	b := (velocity + x * (zeta * omega)) / wd
	value = target + (x * cs + b * sn) * decay
	next_velocity = (velocity * cs - (velocity * (zeta * omega) + x * (omega * omega)) * (sn / wd)) * decay
	return
}
