// world 包单元测试。
#+test
package world

import "core:math"
import "core:testing"

import foster "ofoster:."

// ---------------------------------------------------------------------------
// Camera2D
// ---------------------------------------------------------------------------

@(test)
camera2d_identity_centering :: proc(t: ^testing.T) {
	cam: Camera2D
	camera2d_init(&cam, 1280, 720)

	// 默认 zoom=1 ppu=32：原点在屏幕中心，一个世界单位 = 32 像素
	s := camera2d_world_to_screen(&cam, {0, 0})
	testing.expectf(t, s[0] == 640 && s[1] == 360, "原点应在屏幕中心: %v", s)
	s1 := camera2d_world_to_screen(&cam, {1, 0})
	testing.expectf(t, s1[0] == 640 + 32 && s1[1] == 360, "(1,0) 应右移 32px: %v", s1)
}

@(test)
camera2d_roundtrip :: proc(t: ^testing.T) {
	cam: Camera2D
	camera2d_init(&cam, 1920, 1080)
	camera2d_set_position(&cam, {12.5, -3.25})
	camera2d_set_rotation(&cam, 0.7)
	camera2d_set_zoom(&cam, 2.5)

	world := foster.Vec2{4.2, -9.8}
	screen := camera2d_world_to_screen(&cam, world)
	back, ok := camera2d_screen_to_world(&cam, screen)
	testing.expect(t, ok)
	testing.expectf(t, math.abs(back[0] - world[0]) < 1e-3 && math.abs(back[1] - world[1]) < 1e-3,
		"roundtrip 应还原: got %v want %v", back, world)

	// 旋转后的轴对齐检查：相机自身位置的屏幕投影仍是中心
	center := camera2d_world_to_screen(&cam, cam.position)
	testing.expectf(t, math.abs(center[0] - 960) < 1e-3 && math.abs(center[1] - 540) < 1e-3,
		"相机中心应投影到视口中心: %v", center)
}

@(test)
camera2d_dirty_tracking :: proc(t: ^testing.T) {
	cam: Camera2D
	camera2d_init(&cam, 800, 600)

	m1 := camera2d_matrix(&cam)
	m2 := camera2d_matrix(&cam)
	testing.expect(t, m1 == m2) // 无变化不重建（dirty 已清）

	camera2d_set_zoom(&cam, 2)
	m3 := camera2d_matrix(&cam)
	testing.expect(t, m3 != m1)

	camera2d_set_viewport(&cam, 800, 600) // 同值不弄脏
	testing.expect(t, !cam.dirty)
}

@(test)
camera2d_singular_rejected :: proc(t: ^testing.T) {
	cam: Camera2D
	camera2d_init(&cam, 800, 600)
	camera2d_set_zoom(&cam, 0) // 缩放为零 → 矩阵不可逆

	_, ok := camera2d_screen_to_world(&cam, {400, 300})
	testing.expectf(t, !ok, "zoom=0 时 screen_to_world 应失败")
}

// ---------------------------------------------------------------------------
// SceneRouter
// ---------------------------------------------------------------------------

@(private)
Screen :: enum { Title, Menu, Game }

@(test)
scene_router_transitions :: proc(t: ^testing.T) {
	r: Scene_Router(Screen)
	scene_router_init(&r, Screen.Title)
	testing.expect(t, r.Current == .Title && !r.Transitioning && r.Progress == 1)

	// duration=0：立即切换
	scene_router_switch(&r, Screen.Menu)
	testing.expect(t, r.Current == .Menu && r.Previous == .Title && !r.Transitioning && r.Progress == 1)

	// duration=0.5：进入过渡，Current 立即更新、Progress 从 0 推进
	scene_router_switch(&r, Screen.Game, 0.5)
	testing.expect(t, r.Current == .Game && r.Previous == .Menu && r.Transitioning && r.Progress == 0)

	scene_router_update(&r, 0.25)
	testing.expect(t, r.Transitioning && r.Progress == 0.5)

	scene_router_update(&r, 0.25)
	testing.expect(t, !r.Transitioning && r.Progress == 1)

	// 过渡结束后 update 无副作用；切到当前屏幕无操作
	scene_router_update(&r, 10)
	testing.expect(t, r.Current == .Game && r.Progress == 1)
	scene_router_switch(&r, Screen.Game, 1.0)
	testing.expect(t, !r.Transitioning && r.Previous == .Menu)
}

// ---------------------------------------------------------------------------
// Matrix4
// ---------------------------------------------------------------------------

@(test)
matrix4_inverse_roundtrip :: proc(t: ^testing.T) {
	m := matrix4_multiply(
		matrix4_look_at({1, 2, 5}, {0, 0, 0}, {0, 1, 0}),
		matrix4_multiply(
			matrix4_translation(3, -2, 1),
			matrix4_scaling(2, 2, 2),
		),
	)
	inv, ok := matrix4_inverse(m)
	testing.expectf(t, ok, "可逆矩阵应求逆成功")

	roundtrip := matrix4_multiply(m, inv)
	expect_identity(t, roundtrip)

	// 平移矩阵的逆恰好是反向平移
	tm := matrix4_translation(1, 2, 3)
	ti, ok2 := matrix4_inverse(tm)
	testing.expect(t, ok2)
	expect_identity(t, matrix4_multiply(tm, ti))

	// 零缩放不可逆
	_, ok3 := matrix4_inverse(matrix4_scaling(1, 0, 1))
	testing.expect(t, !ok3)
}

@(private)
expect_identity :: proc(t: ^testing.T, m: Matrix4) {
	for col in 0..<4 {
		for row in 0..<4 {
			want: f32 = col == row ? 1 : 0
			got := matrix4_c(m, col)[row]
			testing.expectf(t, math.abs(got - want) < 1e-4,
				"(%d,%d) 应为 %v, 实际 %v", row, col, want, got)
		}
	}
}

@(test)
matrix4_look_at_maps_eye_to_origin :: proc(t: ^testing.T) {
	eye := foster.Vec3{0, 2, 8}
	view := matrix4_look_at(eye, {0, 0, 0}, {0, 1, 0})

	p, ok := matrix4_transform_point(view, eye)
	testing.expect(t, ok)
	testing.expectf(t, math.abs(p[0]) < 1e-5 && math.abs(p[1]) < 1e-5 && math.abs(p[2]) < 1e-5,
		"eye 应映射到视空间原点: %v", p)

	// 视线上的点（eye 向 target 走一半）应在 -Z 轴上
	eye_target := foster.Vec3{0, -1, -4} // target-eye 的一半
	ahead_pt := foster.Vec3{eye[0] + eye_target[0], eye[1] + eye_target[1], eye[2] + eye_target[2]}
	ahead, ok2 := matrix4_transform_point(view, ahead_pt)
	testing.expect(t, ok2 && math.abs(ahead[0]) < 1e-5 && math.abs(ahead[1]) < 1e-5 && ahead[2] < 0)
}

@(test)
matrix4_perspective_depth_range :: proc(t: ^testing.T) {
	proj := matrix4_perspective_fov(math.PI / 3, 16.0 / 9.0, 0.05, 250)

	// RH：眼前 z 为负。近平面 z=-near 处 NDC≈0，far 平面 NDC≈1（w=-z）
	near_h := matrix4_transform_vec4(proj, {0, 0, -0.05, 1})
	far_h := matrix4_transform_vec4(proj, {0, 0, -250, 1})
	testing.expect(t, math.abs(near_h[2] / near_h[3]) < 1e-4)
	testing.expect(t, math.abs(far_h[2] / far_h[3] - 1) < 1e-4)
}

// ---------------------------------------------------------------------------
// Camera3D / Frustum3D
// ---------------------------------------------------------------------------

@(test)
camera3d_frustum_culling :: proc(t: ^testing.T) {
	cam: Camera3D
	camera3d_init(&cam, 1280, 720) // eye (0,2,8) -> 原点

	f := camera3d_frustum(&cam)

	testing.expect(t, frustum_contains_point(f, {0, 0, 0}))    // 目标点在视锥内
	testing.expect(t, frustum_contains_point(f, {0, 2, 7.9}))  // 眼前
	testing.expect(t, !frustum_contains_point(f, {0, 0, 100})) // 身后（z 正方向远离视线）
	testing.expect(t, !frustum_contains_point(f, {500, 0, 0}))  // 远超右侧

	testing.expect(t, frustum_intersects_aabb(f, {-1, -1, -1}, {1, 1, 1}))
	testing.expect(t, !frustum_intersects_aabb(f, {-500, -10, -12}, {-490, 10, -8})) // 身后
}

@(test)
camera3d_screen_point_to_ray_center :: proc(t: ^testing.T) {
	cam: Camera3D
	camera3d_init(&cam, 1280, 720)

	ray, ok := camera3d_screen_point_to_ray(&cam, {640, 360}) // 屏幕中心
	testing.expect(t, ok)

	// 中心射线应穿过 target（原点）附近
	d, hit := ray3d_hit_sphere(ray, {0, 0, 0}, 0.5)
	testing.expectf(t, hit && d > 0 && d < 20, "中心射线应命中原点附近: hit=%v d=%v", hit, d)

	// 视口无效
	camera3d_set_viewport(&cam, 0, 0)
	_, ok2 := camera3d_screen_point_to_ray(&cam, {5, 5})
	testing.expect(t, !ok2)
}

// ---------------------------------------------------------------------------
// Ray3D
// ---------------------------------------------------------------------------

@(test)
ray3d_intersections :: proc(t: ^testing.T) {
	ray, _ := ray3d_make({0, 0, -5}, {0, 0, 1})

	// AABB：正前方盒子
	d, hit := ray3d_hit_aabb(ray, {-1, -1, 0}, {1, 1, 2})
	testing.expect(t, hit && math.abs(d - 5) < 1e-5)
	_, miss := ray3d_hit_aabb(ray, {10, 10, 10}, {11, 11, 11})
	testing.expect(t, !miss)

	// 三角形：XY 面上、朝向 -Z 的三角形，单面/双面
	tri_a, tri_b, tri_c := foster.Vec3{-1, -1, 0}, foster.Vec3{1, -1, 0}, foster.Vec3{0, 1, 0}
	td, thit := ray3d_hit_triangle(ray, tri_a, tri_b, tri_c)
	testing.expect(t, thit && math.abs(td - 5) < 1e-5)
	back, _ := ray3d_make({0, 0, 5}, {0, 0, 1})
	_, no_back := ray3d_hit_triangle(back, tri_a, tri_b, tri_c, double_sided = false)
	testing.expect(t, !no_back)

	// 球：正前方 r=1（origin z=-5，球面最近点 z=2，距离 7）
	sd, shit := ray3d_hit_sphere(ray, {0, 0, 3}, 1)
	testing.expect(t, shit && math.abs(sd - 7) < 1e-5)
	inside, ihit := ray3d_hit_sphere(ray, {0, 0, -5}, 2) // origin 在球内
	testing.expect(t, ihit && inside == 0)

	// 平面：z=0
	pd, phit := ray3d_hit_plane(ray, {0, 0, 0}, {0, 0, 1})
	testing.expect(t, phit && math.abs(pd - 5) < 1e-5)
	_, parallel := ray3d_hit_plane(ray, {0, 0, 0}, {1, 0, 0}) // 射线平行于平面
	testing.expect(t, !parallel)

	// at 采样与零方向拒绝
	p := ray3d_at(ray, 5)
	testing.expect(t, p == (foster.Vec3{0, 0, 0}))
	_, zero := ray3d_make({0, 0, 0}, {0, 0, 0})
	testing.expect(t, !zero)
}
