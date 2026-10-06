// world —— 相机与屏幕路由（对位 DragonLib Engine.World 的 2D 部分）。
package world

import "core:math"

import foster "ofoster:."

// -----------------------------------------------------------------------------
// Camera2D —— 屏幕空间 = 相机空间、y 向下的 2D 相机
// -----------------------------------------------------------------------------

// Camera2D 组合：World →(平移 -position)→(旋转 rotation)→(缩放 ppu*zoom)→
// (平移 viewport/2)→ Screen。矩阵惰性重建；直接改字段后请调 camera2d_set_dirty，
// 或一律使用 camera2d_set_* 设值（值未变化不会弄脏矩阵）。
Camera2D :: struct {
	position:      foster.Vec2, // 相机中心（世界单位）
	zoom:          f32,         // 相对 ppu 的额外缩放
	rotation:      f32,         // 弧度
	ppu:           f32,         // pixels per unit（32 = 一个世界单位 32 像素）
	viewport_size: foster.Point2, // 像素

	dirty:      	bool,
	cached_matrix:  foster.Matrix3x2,
	cached_inverse: foster.Matrix3x2,
	inverse_ok:     bool,
}

// 初始化。zoom=1、ppu=32、相机在原点。之后每帧用 camera2d_set_viewport
// 同步窗口尺寸（值没变不会弄脏矩阵）。
camera2d_init :: proc(cam: ^Camera2D, viewport_w, viewport_h: int) {
	cam^ = {
		zoom          = 1,
		ppu           = 32,
		viewport_size = foster.Point2{viewport_w, viewport_h},
		dirty         = true,
	}
}

camera2d_set_dirty :: proc(cam: ^Camera2D) {
	cam.dirty = true
}

camera2d_set_position :: proc(cam: ^Camera2D, position: foster.Vec2) {
	if cam.position != position {
		cam.position = position
		cam.dirty = true
	}
}

camera2d_set_zoom :: proc(cam: ^Camera2D, zoom: f32) {
	if cam.zoom != zoom {
		cam.zoom = zoom
		cam.dirty = true
	}
}

camera2d_set_rotation :: proc(cam: ^Camera2D, radians: f32) {
	if cam.rotation != radians {
		cam.rotation = radians
		cam.dirty = true
	}
}

camera2d_set_ppu :: proc(cam: ^Camera2D, ppu: f32) {
	if cam.ppu != ppu {
		cam.ppu = ppu
		cam.dirty = true
	}
}

camera2d_set_viewport :: proc(cam: ^Camera2D, w, h: int) {
	if cam.viewport_size.X != w || cam.viewport_size.Y != h {
		cam.viewport_size = foster.Point2{w, h}
		cam.dirty = true
	}
}

// 状态变化时重建矩阵/逆矩阵；无变化是空操作。每帧调用也无所谓。
camera2d_update :: proc(cam: ^Camera2D) {
	if !cam.dirty do return

	// World -> View -> Screen（行向量约定：左结合 = 先应用）
	world_to_view := foster.Matrix3x2Multiply(
		foster.Matrix3x2Translation(-cam.position[0], -cam.position[1]),
		foster.Matrix3x2Rotation(cam.rotation),
	)
	view_to_screen := foster.Matrix3x2Multiply(
		foster.Matrix3x2Scaling(cam.ppu * cam.zoom, cam.ppu * cam.zoom),
		foster.Matrix3x2Translation(f32(cam.viewport_size.X) * 0.5, f32(cam.viewport_size.Y) * 0.5),
	)
	cam.cached_matrix = foster.Matrix3x2Multiply(world_to_view, view_to_screen)
	cam.cached_inverse, cam.inverse_ok = foster.Matrix3x2Inverse(cam.cached_matrix)
	cam.dirty = false
}

// 世界→屏幕矩阵（惰性更新）。
camera2d_matrix :: proc(cam: ^Camera2D) -> foster.Matrix3x2 {
	camera2d_update(cam)
	return cam.cached_matrix
}

camera2d_world_to_screen :: proc(cam: ^Camera2D, world: foster.Vec2) -> foster.Vec2 {
	return foster.Matrix3x2TransformPoint(camera2d_matrix(cam), world)
}

// 屏幕→世界。矩阵不可逆（如 zoom=0）返回 false。
camera2d_screen_to_world :: proc(cam: ^Camera2D, screen: foster.Vec2) -> (foster.Vec2, bool) {
	camera2d_update(cam)
	if !cam.inverse_ok do return {}, false
	return foster.Matrix3x2TransformPoint(cam.cached_inverse, screen), true
}
