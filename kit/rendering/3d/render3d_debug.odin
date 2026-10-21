package rendering3d

import dasset "olib:core/dasset"
import world "olib:kit/world"

// 调试线：submit 后保留，clear 时一起清空。
// 线宽 / 深度测试可通过 r.debug.thickness / depth_test_enabled 设置。
line :: proc(r: ^Render3D, from, to: [3]f32, color: [4]f32) {
	debug_draw_line(&r.debug, from, to, color)
}

aabb :: proc(r: ^Render3D, bounds: dasset.Dasset_Bounds, color: [4]f32) {
	debug_draw_aabb(&r.debug, bounds, color)
}

sphere :: proc(r: ^Render3D, center: [3]f32, radius: f32, color: [4]f32, segments := 32) {
	debug_draw_sphere(&r.debug, center, radius, color, segments)
}

frustum :: proc(r: ^Render3D, view_projection: world.Matrix4, color: [4]f32) {
	debug_draw_frustum(&r.debug, view_projection, color)
}

axis :: proc(r: ^Render3D, transform: world.Matrix4, length: f32 = 1) {
	debug_draw_axis(&r.debug, transform, length)
}

grid :: proc(r: ^Render3D, half_lines: int, spacing: f32, color: [4]f32) {
	debug_draw_grid(&r.debug, half_lines, spacing, color)
}

skeleton :: proc(r: ^Render3D, skeleton: ^dasset.Dasset_Skeleton,
	matrices: []world.Matrix4, transform: world.Matrix4, color: [4]f32, is_palette := true) {
	debug_draw_skeleton(&r.debug, skeleton, matrices, transform, color, is_palette)
}
