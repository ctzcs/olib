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
