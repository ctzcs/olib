// world:frustum3d —— 视锥（对位 DragonLib World.Frustum3D）。
//
// 6 个归一化平面，xyz 为朝内法线、w 为距离项。
// 点 p 在视锥内 ⟺ 对所有平面 dot(n, p) + w >= 0。
package world

import "core:math"

import foster "olib:foster"

// 分区：
//   提取 —— 从 ViewProjection 得 6 平面
//   相交测试 —— 点 / AABB

// ------------------------------------------------------------------------------
// 提取 —— 从 ViewProjection 得 6 平面
// ------------------------------------------------------------------------------

Frustum3D :: struct {
	left, right, bottom, top, near, far: Vec4,
}

// Gribb-Hartmann 提取：行向量约定（v*M）下平面来自矩阵列的组合；
// 深度范围 [0,1]（D3D/Vulkan/Metal，SDL GPU 全系），近平面即 c2。
frustum_from_view_projection :: proc(m: Matrix4) -> Frustum3D {
	return Frustum3D{
		left   = frustum_normalize_plane(vec4_add(m.c3, m.c0)),
		right  = frustum_normalize_plane(vec4_sub(m.c3, m.c0)),
		bottom = frustum_normalize_plane(vec4_add(m.c3, m.c1)),
		top    = frustum_normalize_plane(vec4_sub(m.c3, m.c1)),
		near   = frustum_normalize_plane(m.c2),
		far    = frustum_normalize_plane(vec4_sub(m.c3, m.c2)),
	}
}

// ------------------------------------------------------------------------------
// 相交测试 —— 点 / AABB
// ------------------------------------------------------------------------------

frustum_contains_point :: proc(f: Frustum3D, p: foster.Vec3) -> bool {
	return plane_distance(f.left, p) >= 0 &&
	       plane_distance(f.right, p) >= 0 &&
	       plane_distance(f.bottom, p) >= 0 &&
	       plane_distance(f.top, p) >= 0 &&
	       plane_distance(f.near, p) >= 0 &&
	       plane_distance(f.far, p) >= 0
}

// AABB 相交测试（保守正确）：逐平面取法线方向上的正顶点，正顶点落在平面
// 外侧才判整体不可见；跨平面边界的盒子一律算可见。
frustum_intersects_aabb :: proc(f: Frustum3D, min, max: foster.Vec3) -> bool {
	return frustum_test_plane(f.left, min, max) &&
	       frustum_test_plane(f.right, min, max) &&
	       frustum_test_plane(f.bottom, min, max) &&
	       frustum_test_plane(f.top, min, max) &&
	       frustum_test_plane(f.near, min, max) &&
	       frustum_test_plane(f.far, min, max)
}

// ------------------------------------------------------------------------------
// 内部
// ------------------------------------------------------------------------------

@(private)
plane_distance :: proc(plane: Vec4, p: foster.Vec3) -> f32 {
	return plane[0]*p[0] + plane[1]*p[1] + plane[2]*p[2] + plane[3]
}

@(private)
frustum_test_plane :: proc(plane: Vec4, min, max: foster.Vec3) -> bool {
	px := plane[0] >= 0 ? max[0] : min[0]
	py := plane[1] >= 0 ? max[1] : min[1]
	pz := plane[2] >= 0 ? max[2] : min[2]
	return plane[0]*px + plane[1]*py + plane[2]*pz + plane[3] >= 0
}

@(private)
frustum_normalize_plane :: proc(plane: Vec4) -> Vec4 {
	length := math.sqrt(plane[0]*plane[0] + plane[1]*plane[1] + plane[2]*plane[2])
	if length <= 1e-8 do return plane
	return Vec4{plane[0] / length, plane[1] / length, plane[2] / length, plane[3] / length}
}

@(private)
vec4_add :: proc(a, b: Vec4) -> Vec4 {
	return Vec4{a[0] + b[0], a[1] + b[1], a[2] + b[2], a[3] + b[3]}
}

@(private)
vec4_sub :: proc(a, b: Vec4) -> Vec4 {
	return Vec4{a[0] - b[0], a[1] - b[1], a[2] - b[2], a[3] - b[3]}
}
