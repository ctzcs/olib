// world:camera3d —— 透视相机（对位 DragonLib World.Camera3D）。
//
// look-at 右手系（看 -Z）、垂直 FOV、D3D 深度 [0,1]，矩阵惰性重建。
// 直接 3D 渲染用；约定细节见 matrix4.odin 的包文档。
package world

import "core:math"

import foster "olib:foster"

// 分区：
//   类型与初始化
//   设值（值变化才弄脏）
//   矩阵与派生量（view/projection/view_projection/forward/right）
//   拾取（视锥 / 屏幕点射线）

// ------------------------------------------------------------------------------
// 类型与初始化
// ------------------------------------------------------------------------------

Camera3D :: struct {
	position: foster.Vec3,
	target:   foster.Vec3,
	up:       foster.Vec3,

	field_of_view: f32, // 垂直 FOV（弧度）
	near_clip:     f32,
	far_clip:      f32,
	viewport_size: foster.Point2,

	aspect_ratio: f32,

	dirty:            bool,
	view:             Matrix4,
	projection:       Matrix4,
	view_projection:  Matrix4,
}

camera3d_init :: proc(cam: ^Camera3D, viewport_w, viewport_h: int) {
	cam^ = {
		position     = foster.Vec3{0, 2, 8},
		target       = foster.Vec3{0, 0, 0},
		up           = foster.Vec3{0, 1, 0},
		field_of_view = math.PI / 3,
		near_clip    = 0.05,
		far_clip     = 250,
		viewport_size = foster.Point2{viewport_w, viewport_h},
		aspect_ratio = 16.0 / 9.0,
		dirty        = true,
	}
}

// ------------------------------------------------------------------------------
// 设值 —— 值变化才弄脏
// ------------------------------------------------------------------------------

camera3d_set_position :: proc(cam: ^Camera3D, position: foster.Vec3) {
	if cam.position != position {
		cam.position = position
		cam.dirty = true
	}
}

camera3d_set_target :: proc(cam: ^Camera3D, target: foster.Vec3) {
	if cam.target != target {
		cam.target = target
		cam.dirty = true
	}
}

camera3d_set_up :: proc(cam: ^Camera3D, up: foster.Vec3) {
	if cam.up != up {
		cam.up = up
		cam.dirty = true
	}
}

camera3d_set_field_of_view :: proc(cam: ^Camera3D, radians: f32) {
	if cam.field_of_view != radians {
		cam.field_of_view = radians
		cam.dirty = true
	}
}

camera3d_set_near_clip :: proc(cam: ^Camera3D, near: f32) {
	if cam.near_clip != near {
		cam.near_clip = near
		cam.dirty = true
	}
}

camera3d_set_far_clip :: proc(cam: ^Camera3D, far: f32) {
	if cam.far_clip != far {
		cam.far_clip = far
		cam.dirty = true
	}
}

camera3d_set_viewport :: proc(cam: ^Camera3D, w, h: int) {
	if cam.viewport_size.X != w || cam.viewport_size.Y != h {
		cam.viewport_size = foster.Point2{w, h}
		cam.dirty = true
	}
}

// ------------------------------------------------------------------------------
// 矩阵与派生量
// ------------------------------------------------------------------------------

// 状态变化时重建矩阵；视口无效（<=0）时保持原状。每帧调用也无所谓。
camera3d_update :: proc(cam: ^Camera3D) {
	if cam.viewport_size.X <= 0 || cam.viewport_size.Y <= 0 do return
	if !cam.dirty do return

	cam.aspect_ratio = f32(cam.viewport_size.X) / f32(cam.viewport_size.Y)
	cam.view = matrix4_look_at(cam.position, cam.target, cam.up)
	cam.projection = matrix4_perspective_fov(cam.field_of_view, cam.aspect_ratio, cam.near_clip, cam.far_clip)
	cam.view_projection = matrix4_multiply(cam.view, cam.projection)
	cam.dirty = false
}

camera3d_view :: proc(cam: ^Camera3D) -> Matrix4 {
	camera3d_update(cam)
	return cam.view
}

camera3d_projection :: proc(cam: ^Camera3D) -> Matrix4 {
	camera3d_update(cam)
	return cam.projection
}

camera3d_view_projection :: proc(cam: ^Camera3D) -> Matrix4 {
	camera3d_update(cam)
	return cam.view_projection
}

// 单位前向（position -> target）；退化时返回 -Z。
camera3d_forward :: proc(cam: ^Camera3D) -> foster.Vec3 {
	direction := v3_sub(cam.target, cam.position)
	if v3_dot(direction, direction) <= 1e-8 {
		return foster.Vec3{0, 0, -1}
	}
	return v3_normalize(direction)
}

camera3d_right :: proc(cam: ^Camera3D) -> foster.Vec3 {
	return v3_normalize(v3_cross(camera3d_forward(cam), cam.up))
}

// ------------------------------------------------------------------------------
// 拾取 —— 视锥 / 屏幕点射线
// ------------------------------------------------------------------------------

// 由当前 view_projection 提取的视锥（6 平面朝内），供视锥剔除使用。
camera3d_frustum :: proc(cam: ^Camera3D) -> Frustum3D {
	return frustum_from_view_projection(camera3d_view_projection(cam))
}

// 屏幕像素坐标 -> 世界射线（拾取用）。视口无效或矩阵不可逆返回 false。
camera3d_screen_point_to_ray :: proc(cam: ^Camera3D, pixel: foster.Vec2) -> (Ray3D, bool) {
	if cam.viewport_size.X <= 0 || cam.viewport_size.Y <= 0 do return {}, false
	inverse, ok := matrix4_inverse(camera3d_view_projection(cam))
	if !ok do return {}, false

	x := pixel[0] / f32(cam.viewport_size.X) * 2 - 1
	y := 1 - pixel[1] / f32(cam.viewport_size.Y) * 2

	near_h := matrix4_transform_vec4(inverse, Vec4{x, y, 0, 1})
	far_h := matrix4_transform_vec4(inverse, Vec4{x, y, 1, 1})
	if math.abs(near_h[3]) < 1e-8 || math.abs(far_h[3]) < 1e-8 do return {}, false

	a := foster.Vec3{near_h[0] / near_h[3], near_h[1] / near_h[3], near_h[2] / near_h[3]}
	b := foster.Vec3{far_h[0] / far_h[3], far_h[1] / far_h[3], far_h[2] / far_h[3]}
	return ray3d_make(a, v3_sub(b, a))
}
