// animation —— 骨骼动画的采样与 palette 计算（对位 DragonLib Engine.Animation.SkeletonAnimator）。
//
// 纯计算，无 GPU/ECS 依赖（可单测）。矩阵为行向量约定（v*M，同 engine/world）：
// 本地姿态 -> 沿拓扑序传播全局矩阵（global = local * parent_global）->
// palette[i] = InverseBind[i] * global[i]。
//
// 多剪辑状态机、morph target 和根运动由游戏层另行实现。
//
// 分区：
//   类型 —— Joint_Pose
//   采样 —— sample_pose / sample_channel
//   palette —— compute_palette
//   时间与混合 —— advance_time / blend_poses
//   蒙皮包围盒 —— skinned_bounds
package animation

import "core:math"

import dasset "olib:core/dasset"
import world "olib:engine/world"

// shader 侧 joint palette 的容量上限（skinned shader 的 MAX_JOINTS）。
ANIMATION_MAX_JOINTS :: 128

// ------------------------------------------------------------------------------
// 类型
// ------------------------------------------------------------------------------

// 一个关节某一帧的本地姿态（TRS）。
Joint_Pose :: struct {
	translation: [3]f32,
	rotation:    [4]f32, // 四元数 xyzw
	scale:       [3]f32,
}

// ------------------------------------------------------------------------------
// 采样
// ------------------------------------------------------------------------------

// 采样剪辑得到逐关节本地姿态：先填 bind pose，再按 channel 覆盖（时间越界
// clamp 到端点）。循环回绕由调用侧处理（time 先对 duration 取模）。
// clip 为 nil 时输出纯 bind pose。
sample_pose :: proc(skeleton: ^dasset.Dasset_Skeleton, clip: ^dasset.Dasset_Animation_Clip, time: f32, pose: []Joint_Pose) {
	if pose == nil { return }
	for i in 0..<len(skeleton.joints) {
		if i >= len(pose) { break }
		joint := &skeleton.joints[i]
		pose[i] = Joint_Pose{
			translation = joint.bind_translation,
			rotation    = joint.bind_rotation,
			scale       = joint.bind_scale,
		}
	}
	if clip == nil { return }

	for &channel in clip.channels {
		if channel.joint_index < 0 || int(channel.joint_index) >= len(skeleton.joints) { continue }
		if int(channel.joint_index) >= len(pose) { continue }
		value := sample_channel(&channel, time)
		joint_pose := &pose[channel.joint_index]
		switch channel.path {
		case .Translation:
			joint_pose.translation = {value[0], value[1], value[2]}
		case .Rotation:
			joint_pose.rotation = value
		case .Scale:
			joint_pose.scale = {value[0], value[1], value[2]}
		}
	}
}

// 采样一条 channel。STEP 保持前键；cubic 切线按区间秒数缩放；
// 四元数按 glTF 要求插值后归一化。
sample_channel :: proc(channel: ^dasset.Dasset_Animation_Channel, time: f32) -> [4]f32 {
	times := channel.times
	values := channel.values
	if len(times) == 0 {
		return channel.path == .Rotation ? {0, 0, 0, 1} : {0, 0, 0, 0}
	}

	finish :: proc(v: [4]f32, is_rotation: bool) -> [4]f32 {
		if !is_rotation { return v }
		q := quat_normalize(v)
		return q
	}

	if len(times) == 1 || time <= times[0] { return finish(values[0], channel.path == .Rotation) }
	last := len(times) - 1
	if time >= times[last] { return finish(values[last], channel.path == .Rotation) }

	segment := 0
	for segment + 1 < len(times) && times[segment + 1] <= time {
		segment += 1
	}
	dt := times[segment + 1] - times[segment]
	t := dt > 0 ? (time - times[segment]) / dt : 0.0

	#partial switch channel.interpolation {
	case .Step:
		return finish(values[segment], channel.path == .Rotation)
	case .Cubic_Spline:
		// glTF cubic-spline hermite：切线按区间秒数缩放
		t2 := t * t
		t3 := t2 * t
		h00 := 2*t3 - 3*t2 + 1
		h10 := t3 - 2*t2 + t
		h01 := -2*t3 + 3*t2
		h11 := t3 - t2
		res: [4]f32
		for c in 0..<4 {
			res[c] = h00*values[segment][c] +
				h10*dt*channel.out_tangents[segment][c] +
				h01*values[segment + 1][c] +
				h11*dt*channel.in_tangents[segment + 1][c]
		}
		return finish(res, channel.path == .Rotation)
	case:
	}

	if channel.path == .Rotation {
		return quat_shortest_slerp(values[segment], values[segment + 1], t)
	}
	// 线性
	res: [4]f32
	for c in 0..<4 {
		res[c] = values[segment][c] * (1 - t) + values[segment + 1][c] * t
	}
	return res
}

// ------------------------------------------------------------------------------
// palette
// ------------------------------------------------------------------------------

// 由本地姿态算 joint palette：joints 已按拓扑序（父先于子），一次线性扫描
// 传播。palette 长度不足关节数时只写前 len(palette) 个。
compute_palette :: proc(skeleton: ^dasset.Dasset_Skeleton, pose: []Joint_Pose, palette: []world.Matrix4) {
	count := min(len(skeleton.joints), len(palette))
	globals := make([dynamic]world.Matrix4, 0, len(skeleton.joints))
	defer delete(globals)

	for i in 0..<count {
		joint := &skeleton.joints[i]
		local := world.matrix4_multiply(
			world.matrix4_scaling(pose[i].scale[0], pose[i].scale[1], pose[i].scale[2]),
			world.matrix4_multiply(
				world.matrix4_from_quaternion(pose[i].rotation),
				world.matrix4_translation(pose[i].translation[0], pose[i].translation[1], pose[i].translation[2]),
			),
		)
		global := local
		if joint.parent_index >= 0 && int(joint.parent_index) < i {
			global = world.matrix4_multiply(local, globals[joint.parent_index])
		}
		append(&globals, global)
		palette[i] = world.matrix4_multiply(
			world.matrix4_from_row_major(joint.inverse_bind_matrix),
			global,
		)
	}
}

// 一步到位：采样 + 传播 + palette。返回实际写入的矩阵数。
compute_palette_sampled :: proc(
	skeleton: ^dasset.Dasset_Skeleton,
	clip:     ^dasset.Dasset_Animation_Clip,
	time:     f32,
	palette:  []world.Matrix4,
) -> int {
	pose := make([]Joint_Pose, len(skeleton.joints))
	defer delete(pose)
	sample_pose(skeleton, clip, time, pose)
	compute_palette(skeleton, pose, palette)
	return min(len(skeleton.joints), len(palette))
}

// ------------------------------------------------------------------------------
// 时间与混合
// ------------------------------------------------------------------------------

// 推进播放时间：循环回绕（负速度也落回 [0, duration)），
// 非循环钳到 [0, duration] 停住。
advance_time :: proc(time_, delta, speed: f32, loop: bool, duration: f32) -> f32 {
	time := time_
	time += delta * speed
	if duration <= 1e-6 { return time }
	if loop {
		return time - math.floor(time / duration) * duration
	}
	return math.clamp(time, 0, duration)
}

// 两姿态线性混合（旋转走最短弧 slerp）。t 钳到 [0,1]。
blend_poses :: proc(a_, b_: []Joint_Pose, t_: f32, result: []Joint_Pose) {
	if len(a_) != len(b_) || len(result) < len(a_) { return }
	t := math.clamp(t_, 0, 1)
	a, b := a_, b_
	for i in 0..<len(a) {
		result[i] = Joint_Pose{
			translation = v3_lerp(a[i].translation, b[i].translation, t),
			scale       = v3_lerp(a[i].scale, b[i].scale, t),
			rotation    = quat_shortest_slerp(a[i].rotation, b[i].rotation, t),
		}
	}
}

// ------------------------------------------------------------------------------
// 蒙皮包围盒
// ------------------------------------------------------------------------------

// 保守包围当前蒙皮姿态：非负归一化混权是各关节变换点的凸组合，
// 落在联合 AABB 内。
skinned_bounds :: proc(bind_bounds: dasset.Dasset_Bounds, palette: []world.Matrix4) -> dasset.Dasset_Bounds {
	if len(palette) == 0 { return bind_bounds }
	result := dasset.DASSET_BOUNDS_EMPTY
	for &m in palette {
		result = bounds_encapsulate(result, bounds_transformed(bind_bounds, m))
	}
	return result
}

// ------------------------------------------------------------------------------
// 内部 —— 四元数 / 向量辅助
// ------------------------------------------------------------------------------

@(private)
quat_normalize :: proc(q: [4]f32) -> [4]f32 {
	l2 := q[0]*q[0] + q[1]*q[1] + q[2]*q[2] + q[3]*q[3]
	if l2 <= 1e-12 {
		return {0, 0, 0, 1}
	}
	l := math.sqrt(l2)
	return {q[0] / l, q[1] / l, q[2] / l, q[3] / l}
}

@(private)
quat_dot :: proc(a, b: [4]f32) -> f32 {
	return a[0]*b[0] + a[1]*b[1] + a[2]*b[2] + a[3]*b[3]
}

// 最短弧 slerp：先归一化，负点积翻转 b，再 slerp 后归一化。
@(private)
quat_shortest_slerp :: proc(a_, b_: [4]f32, t: f32) -> [4]f32 {
	a := quat_normalize(a_)
	b := quat_normalize(b_)
	if quat_dot(a, b) < 0 {
		b = {-b[0], -b[1], -b[2], -b[3]}
	}
	cos_theta := math.clamp(quat_dot(a, b), -1, 1)
	theta := math.acos(cos_theta)
	if theta < 1e-4 {
		// 角度极小走 nlerp，避免除零
		out := [4]f32{
			a[0] * (1 - t) + b[0] * t,
			a[1] * (1 - t) + b[1] * t,
			a[2] * (1 - t) + b[2] * t,
			a[3] * (1 - t) + b[3] * t,
		}
		return quat_normalize(out)
	}
	sin_theta := math.sin(theta)
	wa := math.sin((1 - t) * theta) / sin_theta
	wb := math.sin(t * theta) / sin_theta
	return quat_normalize({a[0]*wa + b[0]*wb, a[1]*wa + b[1]*wb, a[2]*wa + b[2]*wb, a[3]*wa + b[3]*wb})
}

@(private)
v3_lerp :: proc(a, b: [3]f32, t: f32) -> [3]f32 {
	return {a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t}
}

@(private)
bounds_encapsulate :: proc(a, b: dasset.Dasset_Bounds) -> dasset.Dasset_Bounds {
	return dasset.Dasset_Bounds{
		min = {min(a.min[0], b.min[0]), min(a.min[1], b.min[1]), min(a.min[2], b.min[2])},
		max = {max(a.max[0], b.max[0]), max(a.max[1], b.max[1]), max(a.max[2], b.max[2])},
	}
}

// 8 角点逐个变换后重新包围（保守正确，供视锥剔除用）。
@(private)
bounds_transformed :: proc(b: dasset.Dasset_Bounds, m: world.Matrix4) -> dasset.Dasset_Bounds {
	result := dasset.DASSET_BOUNDS_EMPTY
	for i in 0..<8 {
		corner := [3]f32{
			(i & 1) == 0 ? b.min[0] : b.max[0],
			(i & 2) == 0 ? b.min[1] : b.max[1],
			(i & 4) == 0 ? b.min[2] : b.max[2],
		}
		if p, ok := world.matrix4_transform_point(m, corner); ok {
			result = bounds_encapsulate(result, dasset.Dasset_Bounds{min = p, max = p})
		}
	}
	return result
}
