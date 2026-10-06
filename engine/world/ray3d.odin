// world:ray3d —— 射线与 3D 相交测试（对位 DragonLib World.Ray3D / Intersections3D）。
//
// 方向归一化，所有相交距离以世界单位计。
// DassetPrimitive 的逐三角形拾取等模型格式落地后再补（见 ROADMAP P2）。
package world

import "core:math"

import foster "ofoster:."

// 分区：
//   Ray3D —— 构造与采样
//   相交测试 —— aabb / triangle / sphere / plane

// ------------------------------------------------------------------------------
// Ray3D —— 构造与采样
// ------------------------------------------------------------------------------

Ray3D :: struct {
	origin:    foster.Vec3,
	direction: foster.Vec3, // 单位向量
}

// 方向为零/非有限时返回 false。
ray3d_make :: proc(origin, direction: foster.Vec3) -> (Ray3D, bool) {
	l2 := v3_dot(direction, direction)
	if !(l2 >= 1e-20) { // 兼顾 NaN（NaN 比较全 false）
		return {}, false
	}
	l := math.sqrt(l2)
	return Ray3D{origin = origin, direction = foster.Vec3{
		direction[0] / l, direction[1] / l, direction[2] / l,
	}}, true
}

// 沿射线取距 origin 距离 d 的点。
ray3d_at :: proc(ray: Ray3D, d: f32) -> foster.Vec3 {
	return foster.Vec3{
		ray.origin[0] + ray.direction[0] * d,
		ray.origin[1] + ray.direction[1] * d,
		ray.origin[2] + ray.direction[2] * d,
	}
}

// ------------------------------------------------------------------------------
// 相交测试 —— aabb / triangle / sphere / plane
// ------------------------------------------------------------------------------

// AABB 相交（slab 法）。命中返回进入距离；min>max 的无效盒子返回 false。
ray3d_hit_aabb :: proc(ray: Ray3D, bmin, bmax: foster.Vec3) -> (f32, bool) {
	near: f32 = 0
	far:  f32 = math.INF_F32

	for axis in 0..<3 {
		o := ray.origin[axis]
		d := ray.direction[axis]
		if bmin[axis] > bmax[axis] do return 0, false
		if math.abs(d) < 1e-8 {
			if o < bmin[axis] || o > bmax[axis] do return 0, false
			continue
		}
		a := (bmin[axis] - o) / d
		b := (bmax[axis] - o) / d
		near = max(near, min(a, b))
		far = min(far, max(a, b))
		if near > far do return 0, false
	}
	return near, true
}

// 三角形相交（Möller–Trumbore）。double_sided=false 时只接受正面。
ray3d_hit_triangle :: proc(ray: Ray3D, a, b, c: foster.Vec3, double_sided := true) -> (f32, bool) {
	ab := v3_sub(b, a)
	ac := v3_sub(c, a)
	p := v3_cross(ray.direction, ac)
	det := v3_dot(ab, p)
	if double_sided ? math.abs(det) < 1e-8 : det < 1e-8 {
		return 0, false
	}
	t := v3_sub(ray.origin, a)
	u := v3_dot(t, p) / det
	if u < 0 || u > 1 do return 0, false
	q := v3_cross(t, ab)
	v := v3_dot(ray.direction, q) / det
	if v < 0 || u + v > 1 do return 0, false
	distance := v3_dot(ac, q) / det
	return distance, distance >= 0
}

// 球相交。origin 在球内时返回距离 0 命中。
ray3d_hit_sphere :: proc(ray: Ray3D, center: foster.Vec3, radius: f32) -> (f32, bool) {
	if radius < 0 do return 0, false
	offset := v3_sub(ray.origin, center)
	c := v3_dot(offset, offset) - radius * radius
	if c <= 0 do return 0, true
	b := v3_dot(offset, ray.direction)
	discriminant := b * b - c
	if discriminant < 0 do return 0, false
	distance := -b - math.sqrt(discriminant)
	return distance, distance >= 0
}

// 平面相交（point/normal 定义）。射线平行于平面返回 false。
ray3d_hit_plane :: proc(ray: Ray3D, point, normal: foster.Vec3) -> (f32, bool) {
	denominator := v3_dot(ray.direction, normal)
	if math.abs(denominator) < 1e-8 do return 0, false
	distance := v3_dot(v3_sub(point, ray.origin), normal) / denominator
	return distance, distance >= 0
}
