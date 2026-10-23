// 目标追随：帧率无关、不过冲、零步长与非法参数不产生 NaN。
#+test
package tween

import "core:testing"

@(test)
approach_is_frame_rate_independent :: proc(t: ^testing.T) {
	a, b: f32 = 0, 0
	for _ in 0..<60 {
		a = approach(a, 10, 8, 1.0 / 60)
	}
	for _ in 0..<180 {
		b = approach(b, 10, 8, 1.0 / 180)
	}
	testing.expect(t, abs(a - b) < 0.001)
	testing.expect(t, a < 10 && a > 9.99)
	v := approach([2]f32{0, 0}, [2]f32{4, -4}, 1000, 1)
	testing.expect(t, v == [2]f32{4, -4}, "large rate lands exactly without overshoot")
}

@(test)
smooth_damp_settles_without_overshoot :: proc(t: ^testing.T) {
	pos, vel := [2]f32{0, 0}, [2]f32{}
	max_x: f32
	for _ in 0..<120 {
		pos, vel = smooth_damp(pos, vel, [2]f32{100, 50}, 0.1, 1.0 / 60)
		max_x = max(max_x, pos.x)
	}
	testing.expect(t, abs(pos.x - 100) < 0.01 && abs(pos.y - 50) < 0.01)
	testing.expect(t, max_x <= 100.001, "critically damped from rest must not overshoot")
	// 一次长帧也必须稳定。
	x, xv := smooth_damp(f32(0), f32(0), 1, 0.05, 1)
	testing.expect(t, x > 0.99 && x <= 1.001 && abs(xv) < 1)
	same, same_v := smooth_damp(f32(3), f32(2), 9, 0.1, 0)
	testing.expect(t, same == 3 && same_v == 2)
	snap, snap_v := smooth_damp(f32(3), f32(2), 9, 0, 1.0 / 60)
	testing.expect(t, snap == 9 && snap_v == 0)
}

@(test)
spring_settles_and_bounce_controls_overshoot :: proc(t: ^testing.T) {
	settle :: proc(bounce: f32, dt: f32) -> (final, peak: f32) {
		x, v: f32
		for _ in 0..<int(1 / dt) {
			x, v = spring(x, v, 1, 0.3, bounce, dt)
			peak = max(peak, x)
		}
		return x, peak
	}
	x, peak := settle(0, 1.0 / 60)
	testing.expect(t, abs(x - 1) < 0.001)
	testing.expectf(t, peak <= 1.0001, "bounce=0 from rest must not overshoot, peak=%v", peak)
	_, bouncy := settle(0.5, 1.0 / 60)
	testing.expectf(t, bouncy > 1.05, "bounce=0.5 must overshoot, peak=%v", bouncy)
	// 解析解与步长无关。
	a, _ := settle(0.5, 1.0 / 60)
	b, _ := settle(0.5, 1.0 / 240)
	testing.expectf(t, abs(a - b) < 0.001, "a=%v b=%v", a, b)
	// 约 time 秒内基本到位。
	y, yv: f32
	for _ in 0..<18 {
		y, yv = spring(y, yv, 1, 0.3, 0, 1.0 / 60)
	}
	testing.expectf(t, y > 0.97, "y=%v", y)
	// 长帧稳定，冲击速度会回到目标，[N]f32 可用。
	big, big_v := spring(f32(0), f32(0), 1, 0.1, 0.3, 5)
	testing.expect(t, abs(big - 1) < 0.001 && abs(big_v) < 0.01)
	p, pv := [2]f32{0, 0}, [2]f32{40, -40}
	for _ in 0..<120 {
		p, pv = spring(p, pv, [2]f32{0, 0}, 0.25, 0.4, 1.0 / 60)
	}
	testing.expect(t, abs(p.x) < 0.01 && abs(p.y) < 0.01)
	same, same_v := spring(f32(3), f32(2), 9, 0.2, 0, 0)
	testing.expect(t, same == 3 && same_v == 2)
	snap, snap_v := spring(f32(3), f32(2), 9, 0, 0.5, 1.0 / 60)
	testing.expect(t, snap == 9 && snap_v == 0)
}
