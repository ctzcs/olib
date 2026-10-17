// gizmo —— 移动、旋转与缩放工具；只返回交互结果，不持有对象、场景或存档。
package gizmo

import "core:math"

import foster "olib:foster"
import world "olib:kit/world"

// 分区：类型与默认样式 / 投影与命中 / 拖拽生命周期

// ==============================================================================
// 类型与默认样式
// ==============================================================================

// 零值可用，无堆资源；一套状态对应一个当前操作目标。目标改变时传 input.cancel。
Translation_Gizmo :: struct {
	dragging, captured: bool,
	axis: int, // dragging 时为 0/1/2，即世界 X/Y/Z。
	origin: foster.Vec3,
	plane_normal: foster.Vec3,
	start_distance: f32,
	viewport: foster.Rect,
	view_projection: world.Matrix4,
}

Translation_Input :: struct {
	pointer: foster.Vec2, // 最终输出像素，与 viewport 在同一坐标空间。
	pressed, down: bool, // 调用方提供按下边沿；同一个边沿只提交一次。
	enabled, allow_start: bool, // enabled=false 终止；allow_start=false 仅禁止开始。
	cancel: bool, // 取消只结束交互，不自动还原已应用的变换。
}

Translation_Result :: struct {
	position, delta: foster.Vec3, // delta 相对按下时原点；changed 时由调用方决定是否应用。
	axis: int,
	started, changed, ended, cancelled, captured: bool,
}

Translation_Geometry :: struct {
	origin: foster.Vec2,
	ends: [3]foster.Vec2,
	visible: [3]bool,
}

Axis_Label :: struct {
	visible: bool,
	position: foster.Vec2, // 文本中心位置；字号与字体由调用方选择。
	color: foster.Color,
}

Translation_Style :: struct {
	length, min_length, hit_radius: f32,
	line_width, outline_width, arrow_length, arrow_half_width, center_radius, label_gap: f32,
	colors: [3]foster.Color,
	highlight, outline, center: foster.Color,
}

DEFAULT_TRANSLATION_STYLE :: Translation_Style{
	length = 100, min_length = 18, hit_radius = 9,
	line_width = 3, outline_width = 6, arrow_length = 12, arrow_half_width = 5,
	center_radius = 4, label_gap = 8,
	colors = {{255, 105, 104, 255}, {114, 232, 146, 255}, {108, 167, 255, 255}},
	highlight = {255, 180, 97, 255}, outline = {13, 22, 29, 236}, center = {234, 237, 227, 255},
}

// ==============================================================================
// 投影与命中
// ==============================================================================

// Camera3D 的 viewport_size 必须匹配 rect 宽高；rect 允许非零偏移。
// 不改相机视口，不依赖场景内部渲染比例。无效尺寸、相机后方及裁剪范围外返回 false。
project :: proc(camera: ^world.Camera3D, point: foster.Vec3, viewport: foster.Rect) -> (foster.Vec2, bool) {
	if camera == nil || viewport.Width <= 0 || viewport.Height <= 0 do return {}, false
	if f32(camera.viewport_size.X) != viewport.Width || f32(camera.viewport_size.Y) != viewport.Height {
		return {}, false
	}
	h := world.matrix4_transform_vec4(world.camera3d_view_projection(camera),
		{point[0], point[1], point[2], 1})
	if !finite(h[3]) || h[3] <= 0.0001 || !(h[2] >= 0 && h[2] <= h[3]) do return {}, false
	p := foster.Vec2{viewport.X+(h[0]/h[3]+1)*0.5*viewport.Width,
		viewport.Y+(1-h[1]/h[3])*0.5*viewport.Height}
	return p, finite(p.x) && finite(p.y)
}

translation_geometry :: proc(
	camera: ^world.Camera3D, position: foster.Vec3, viewport: foster.Rect,
	scale: f32 = 1, style := DEFAULT_TRANSLATION_STYLE,
) -> Translation_Geometry {
	g: Translation_Geometry
	if !finite(scale) || scale <= 0 || style.length <= 0 do return g
	start, ok := project(camera, position, viewport)
	if !ok do return g
	g.origin = start
	depth := dot(position-camera.position, world.camera3d_forward(camera))
	length := depth*2*math.tan(camera.field_of_view*0.5)*style.length*scale/viewport.Height
	for axis in 0..<3 {
		end := position
		end[axis] += length
		g.ends[axis], ok = project(camera, end, viewport)
		d := g.ends[axis]-start
		// 接近视线方向的轴隐藏，避免退化拖拽；长度仍保留透视缩短。
		minimum := max(0.001, style.min_length)*scale
		g.visible[axis] = ok && d.x*d.x+d.y*d.y >= minimum*minimum
	}
	return g
}

translation_hit :: proc(g: Translation_Geometry, pixel: foster.Vec2, radius: f32) -> int {
	if !finite(radius) || radius <= 0 do return -1
	best := radius*radius
	result := -1
	for end, axis in g.ends {
		if !g.visible[axis] do continue
		d := end-g.origin
		p := pixel-g.origin
		length_sq := d.x*d.x+d.y*d.y
		if length_sq <= 0 do continue
		t := math.clamp((p.x*d.x+p.y*d.y)/length_sq, 0, 1)
		if t*math.sqrt(length_sq) < radius*1.5 do continue
		diff := p-d*t
		distance := diff.x*diff.x+diff.y*diff.y
		if distance < best {
			best = distance
			result = axis
		}
	}
	return result
}

// ==============================================================================
// 拖拽生命周期
// ==============================================================================

// 每帧调用，包括释放、离焦或停用帧。相机/视口改变会结束拖动；按住期间保持捕获到松开。
// allow_start 由调用方根据 UI、对象选择等决定，开始后穿过 UI 不会丢失捕获。
translation_update :: proc(
	g: ^Translation_Gizmo, camera: ^world.Camera3D, position: foster.Vec3,
	viewport: foster.Rect, input: Translation_Input,
	scale: f32 = 1, style := DEFAULT_TRANSLATION_STYLE,
) -> Translation_Result {
	r := Translation_Result{position = position, axis = -1, captured = g.captured}
	if g.dragging {
		r.axis = g.axis
		r.delta = position-g.origin
	}
	invalid := !input.enabled || input.cancel || camera == nil
	if !invalid {
		invalid = !finite(scale) || scale <= 0 || viewport.Width <= 0 || viewport.Height <= 0 ||
			f32(camera.viewport_size.X) != viewport.Width || f32(camera.viewport_size.Y) != viewport.Height
	}
	if g.dragging && !invalid {
		invalid = viewport != g.viewport || world.camera3d_view_projection(camera) != g.view_projection
	}
	if invalid {
		r.ended = g.dragging
		r.cancelled = g.dragging
		g.dragging = false
		if !input.down do g.captured = false
		return r
	}
	if !input.down {
		r.ended = g.dragging
		g.dragging = false
		g.captured = false
		return r
	}
	if !finite(input.pointer.x) || !finite(input.pointer.y) do return r
	local := input.pointer-foster.Vec2{viewport.X, viewport.Y}
	ray, ray_ok := world.camera3d_screen_point_to_ray(camera, local)
	if g.dragging {
		if ray_ok {
			d, ok := drag_distance(ray, g.origin, g.plane_normal, g.axis)
			if ok {
				r.position = g.origin
				r.position[g.axis] += d-g.start_distance
				r.delta = r.position-g.origin
				r.changed = r.position != position
			}
		}
		return r
	}
	if g.captured || !input.pressed || !input.allow_start || !ray_ok do return r
	if local.x < 0 || local.y < 0 || local.x > viewport.Width || local.y > viewport.Height do return r
	geometry := translation_geometry(camera, position, viewport, scale, style)
	axis := translation_hit(geometry, input.pointer, style.hit_radius*scale)
	if axis < 0 do return r
	normal := position-camera.position
	normal[axis] = 0
	length := math.sqrt(dot(normal, normal))
	if length <= 0.000001 do return r
	normal /= length
	d, ok := drag_distance(ray, position, normal, axis)
	if !ok do return r
	g.dragging = true
	g.captured = true
	g.axis = axis
	g.origin = position
	g.plane_normal = normal
	g.start_distance = d
	g.viewport = viewport
	g.view_projection = world.camera3d_view_projection(camera)
	r.axis = axis
	r.started = true
	r.captured = true
	return r
}

@(private)
drag_distance :: proc(ray: world.Ray3D, origin, normal: foster.Vec3, axis: int) -> (f32, bool) {
	distance, ok := world.ray3d_hit_plane(ray, origin, normal)
	if !ok do return 0, false
	d := world.ray3d_at(ray, distance)[axis]-origin[axis]
	return d, finite(d)
}

@(private)
dot :: proc(a, b: foster.Vec3) -> f32 {
	return a[0]*b[0]+a[1]*b[1]+a[2]*b[2]
}

@(private)
finite :: proc(v: f32) -> bool {
	return !math.is_nan(v) && !math.is_inf(v)
}

