// animation 包单元测试：采样/clamp/插值、palette 恒等性、时间推进、混合。
#+test
package animation

import "core:math"
import "core:testing"

import dasset "olib:core/dasset"
import world "olib:engine/world"

// 两关节链：root(bind 平移 1,0,0) -> child(bind 平移 0,2,0)，均单位逆绑定。
@(private)
make_chain :: proc() -> dasset.Dasset_Skeleton {
	skel: dasset.Dasset_Skeleton
	root := dasset.Dasset_Joint{
		name = "root",
		parent_index = -1,
		bind_translation = {1, 0, 0},
		bind_rotation = {0, 0, 0, 1},
		bind_scale = {1, 1, 1},
	}
	root.inverse_bind_matrix = translation16(-1, 0, 0) // bind 全局 T(1,0,0) 的逆
	append(&skel.joints, root)

	child := dasset.Dasset_Joint{
		name = "child",
		parent_index = 0,
		bind_translation = {0, 2, 0},
		bind_rotation = {0, 0, 0, 1},
		bind_scale = {1, 1, 1},
	}
	child.inverse_bind_matrix = translation16(-1, -2, 0) // bind 全局 T(1,2,0) 的逆
	append(&skel.joints, child)
	return skel
}

@(private)
translation16 :: proc(x, y, z: f32) -> [16]f32 {
	// System.Numerics 行主序：平移在 row4（下标 12/13/14）
	m: [16]f32
	m[0] = 1
	m[5] = 1
	m[10] = 1
	m[15] = 1
	m[12] = x
	m[13] = y
	m[14] = z
	return m
}

@(test)
sample_pose_bind_and_override :: proc(t: ^testing.T) {
	skel := make_chain()
	defer {
		for &j in skel.joints { if len(j.name) > 0 { /* 名为字面量借用 */ } }
		delete(skel.joints)
	}

	pose := make([]Joint_Pose, 2)
	defer delete(pose)

	// 无 clip：纯 bind pose
	sample_pose(&skel, nil, 0, pose)
	testing.expect(t, pose[0].translation == ({1, 0, 0}))
	testing.expect(t, pose[1].translation == ({0, 2, 0}))

	// clip：root 的平移 channel，两键 0s(0,0,0) -> 1s(10,0,0)
	clip: dasset.Dasset_Animation_Clip
	clip.duration = 1
	ch: dasset.Dasset_Animation_Channel
	ch.joint_index = 0
	ch.path = .Translation
	ch.interpolation = .Linear
	ch.times = make([]f32, 2)
	ch.times[1] = 1
	ch.values = make([][4]f32, 2)
	ch.values[1] = {10, 0, 0, 0}
	defer {
		delete(ch.times)
		delete(ch.values)
		delete(clip.channels)
	}
	append(&clip.channels, ch)

	sample_pose(&skel, &clip, 0.25, pose)
	testing.expectf(t, math.abs(pose[0].translation[0] - 2.5) < 1e-5, "线性插值 25%%: %v", pose[0].translation)

	// 越界 clamp 到端点
	sample_pose(&skel, &clip, 99, pose)
	testing.expect(t, pose[0].translation[0] == 10)
	sample_pose(&skel, &clip, -1, pose)
	testing.expect(t, pose[0].translation[0] == 0)
}

@(test)
compute_palette_identity_when_pose_matches_bind :: proc(t: ^testing.T) {
	skel := make_chain()
	defer delete(skel.joints)

	palette := make([]world.Matrix4, 2)
	defer delete(palette)
	n := compute_palette_sampled(&skel, nil, 0, palette)
	testing.expect(t, n == 2)

	// bind pose 采样 + 单位逆绑定 => 每个 palette 都应是单位阵
	for i in 0..<2 {
		expect_identity(t, palette[i])
	}
}

@(private)
expect_identity :: proc(t: ^testing.T, m: world.Matrix4) {
	for col in 0..<4 {
		for row in 0..<4 {
			want: f32 = col == row ? 1 : 0
			got := world.matrix4_column(m, col)[row]
			testing.expectf(t, math.abs(got - want) < 1e-5, "(%d,%d) %v != %v", row, col, got, want)
		}
	}
}

@(test)
advance_time_loop_and_clamp :: proc(t: ^testing.T) {
	testing.expect(t, math.abs(advance_time(0.75, 0.5, 1, true, 1) - 0.25) < 1e-6) // 回绕
	testing.expect(t, math.abs(advance_time(0.2, 1, 1, false, 1) - 1) < 1e-6) // 钳到末尾
	testing.expect(t, math.abs(advance_time(0, 1, -0.3, true, 1) - 0.7) < 1e-6) // 负速度回绕
	testing.expect(t, math.abs(advance_time(0, 5, 1, false, 0) - 5) < 1e-6) // 零时长不动
}

@(test)
sample_channel_interpolations :: proc(t: ^testing.T) {
	// 平移线性
	lin: dasset.Dasset_Animation_Channel
	lin.path = .Translation
	lin.interpolation = .Linear
	lin.times = make([]f32, 3)
	lin.times[1] = 1
	lin.times[2] = 2
	lin.values = make([][4]f32, 3)
	lin.values[1] = {10, 0, 0, 0}
	lin.values[2] = {20, 0, 0, 0}
	defer {
		delete(lin.times)
		delete(lin.values)
	}

	v := sample_channel(&lin, 1.5)
	testing.expect(t, math.abs(v[0] - 15) < 1e-5)

	// Step 保持前键
	lin.interpolation = .Step
	vs := sample_channel(&lin, 1.9)
	testing.expect(t, vs[0] == 10)

	// 旋转走最短弧：180° 绕 Z 的两键，t=0.5 应得到 ~127°（不是绕远路）
	rot: dasset.Dasset_Animation_Channel
	rot.path = .Rotation
	rot.interpolation = .Linear
	rot.times = make([]f32, 2)
	rot.times[1] = 1
	rot.values = make([][4]f32, 2)
	rot.values[1] = {0, 0, 0.70710678, 0.70710678} // 90° 绕 Z
	defer {
		delete(rot.times)
		delete(rot.values)
	}
	vr := sample_channel(&rot, 0.5)
	half: f32 = 0.38268343 // sin(22.5°)：0->90° 绕 Z 的半程
	testing.expectf(t, math.abs(math.abs(vr[2]) - half) < 1e-4, "半程应约 45°: %v", vr)
	testing.expect(t, math.abs(quat_len(vr) - 1) < 1e-5) // 已归一化

	// 翻转分支：b 取负四元数应走同一弧
	rot.values[1] = {0, 0, -0.70710678, -0.70710678}
	vf := sample_channel(&rot, 0.5)
	testing.expect(t, math.abs(math.abs(vf[2]) - half) < 1e-4)
}

@(private)
quat_len :: proc(q: [4]f32) -> f32 {
	return math.sqrt(q[0]*q[0] + q[1]*q[1] + q[2]*q[2] + q[3]*q[3])
}

@(test)
blend_poses_and_bounds :: proc(t: ^testing.T) {
	a := make([]Joint_Pose, 1)
	b := make([]Joint_Pose, 1)
	r := make([]Joint_Pose, 1)
	defer delete(a)
	defer delete(b)
	defer delete(r)
	a[0].translation = {0, 0, 0}
	b[0].translation = {10, 0, 0}
	a[0].scale = {1, 1, 1}
	b[0].scale = {1, 1, 1}
	a[0].rotation = {0, 0, 0, 1}
	b[0].rotation = {0, 0, 0, 1}

	blend_poses(a, b, 0.25, r)
	testing.expect(t, math.abs(r[0].translation[0] - 2.5) < 1e-5)

	// 蒙皮包围盒：bind 盒 {0..1} 经单位 palette 变换不变
	bb := dasset.Dasset_Bounds{min = {0, 0, 0}, max = {1, 1, 1}}
	palette := make([]world.Matrix4, 1)
	defer delete(palette)
	palette[0] = world.MATRIX4_IDENTITY
	sb := skinned_bounds(bb, palette)
	testing.expect(t, sb.min == bb.min && sb.max == bb.max)

	empty := skinned_bounds(bb, nil)
	testing.expect(t, empty.min == bb.min)
}
