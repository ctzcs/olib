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
