package gizmo

import "core:math"

import foster "olib:foster"
import world "olib:kit/world"

// 分区：变换与交互状态 / 几何与命中 / 拖拽生命周期 / 旋转数学

// ==============================================================================
// 变换与交互状态
// ==============================================================================

Mode :: enum {
	Translate,
	Rotate,
	Scale,
}

// rotation 为弧度，固定轴依次 X、Y、Z（Rz * Ry * Rx）；scale 必须为正。
Transform :: struct {
	position, rotation, scale: foster.Vec3,
}

// 零值可用，不持有对象或资源。拖拽中更换对象必须传 input.cancel。
Transform_Gizmo :: struct {
	dragging, captured: bool,
	mode: Mode,
	axis: int, // 0/1/2 对应 XYZ；3 为等比缩放。
	start: Transform,
	pointer, direction: foster.Vec2,
	normal: foster.Vec3,
	distance, last_angle, angle: f32,
	viewport: foster.Rect,
	view_projection: world.Matrix4,
}

Transform_Result :: struct {
	transform: Transform,
	axis: int,
	angle, factor: f32, // 本次拖拽累计弧度 / 比例；其余模式为 0 / 1。
	started, changed, ended, cancelled, captured: bool,
}

RING_SEGMENTS :: 64
Transform_Geometry :: struct {
	mode: Mode,
	axes: Translation_Geometry,
	center_visible: bool,
	rings: [3][RING_SEGMENTS+1]foster.Vec2,
	segments: [3][RING_SEGMENTS]bool,
}

// ==============================================================================
// 几何与命中
// ==============================================================================

transform_geometry :: proc(
	camera: ^world.Camera3D, value: Transform, viewport: foster.Rect, mode: Mode,
	scale: f32 = 1, style := DEFAULT_TRANSLATION_STYLE,
) -> Transform_Geometry {
	g := Transform_Geometry{mode = mode}
	if mode == .Translate {
		g.axes = translation_geometry(camera, value.position, viewport, scale, style)
		return g
	}
	if !finite(scale) || scale <= 0 || !finite(style.length) || style.length <= 0 do return g
	center, ok := project(camera, value.position, viewport)
	if !ok do return g
	g.axes.origin = center
	g.center_visible = true
	depth := dot(value.position-camera.position, world.camera3d_forward(camera))
	length := depth*2*math.tan(camera.field_of_view*0.5)*style.length*scale/viewport.Height
	if mode == .Scale {
		for axis in 0..<3 {
			v: foster.Vec3
			v[axis] = length
			g.axes.ends[axis], ok = project(camera, value.position+rotate_xyz(v, value.rotation), viewport)
			d := g.axes.ends[axis]-center
			g.axes.visible[axis] = ok && dot2(d, d) >= math.pow(style.min_length*scale, 2)
		}
		return g
	}
	for axis in 0..<3 {
		normal: foster.Vec3
		normal[axis] = 1
		// 近乎侧视的环无法稳定求交；飞行相机转向后自动恢复。
		view := value.position-camera.position
		if abs(dot(normal, view)) < 0.12*math.sqrt(dot(view, view)) do continue
		previous_ok := false
		for i in 0..=RING_SEGMENTS {
			a := f32(i)*2*math.PI/RING_SEGMENTS
			point := value.position
			point[(axis+1)%3] += math.cos(a)*length*0.72
			point[(axis+2)%3] += math.sin(a)*length*0.72
			g.rings[axis][i], ok = project(camera, point, viewport)
			if i > 0 do g.segments[axis][i-1] = ok && previous_ok
			previous_ok = ok
		}
	}
	return g
}

transform_hit :: proc(g: Transform_Geometry, pointer: foster.Vec2, scale: f32 = 1,
	style := DEFAULT_TRANSLATION_STYLE) -> int {
	if !finite(scale) || scale <= 0 do return -1
	if g.mode == .Translate do return translation_hit(g.axes, pointer, style.hit_radius*scale)
	if g.mode == .Scale {
		d := pointer-g.axes.origin
		if g.center_visible && abs(d.x) <= 8*scale && abs(d.y) <= 8*scale do return 3
		return translation_hit(g.axes, pointer, style.hit_radius*scale)
	}
	best := style.hit_radius*style.hit_radius*scale*scale
	hit := -1
	for ring, axis in g.rings {
		for i in 0..<RING_SEGMENTS {
			if !g.segments[axis][i] do continue
			d := ring[i+1]-ring[i]
			length := dot2(d, d)
			if length <= 0.0001 do continue
			p := pointer-ring[i]
			diff := p-d*math.clamp(dot2(p, d)/length, 0, 1)
			distance := dot2(diff, diff)
			if distance < best {
				best = distance
				hit = axis
			}
		}
	}
	return hit
}

// ==============================================================================
// 拖拽生命周期
// ==============================================================================

// 输入契约与 translation_update 相同。模式、相机、视口改变结束拖拽，捕获保持到释放。
// 缩放沿模型局部轴，中心手柄等比缩放；上下限共同约束比例，保留非均匀比例。
transform_update :: proc(
	g: ^Transform_Gizmo, camera: ^world.Camera3D, value: Transform, viewport: foster.Rect,
	mode: Mode, input: Translation_Input, scale: f32 = 1, style := DEFAULT_TRANSLATION_STYLE,
	min_scale: f32 = 0.001, max_scale: f32 = 10000,
) -> Transform_Result {
	r := Transform_Result{transform = value, axis = -1, factor = 1, captured = g.captured}
	if g.dragging {
		r.axis = g.axis
		r.angle = g.angle
		if g.mode == .Scale do r.factor = value.scale[g.axis%3]/g.start.scale[g.axis%3]
	}
	invalid := !input.enabled || input.cancel || camera == nil || !finite(scale) || scale <= 0 ||
		!finite(style.length) || style.length <= 0
	if !invalid {
		invalid = viewport.Width <= 0 || viewport.Height <= 0 ||
			f32(camera.viewport_size.X) != viewport.Width || f32(camera.viewport_size.Y) != viewport.Height
		for i in 0..<3 {
			invalid = invalid || !finite(value.position[i]) || !finite(value.rotation[i]) ||
				!finite(value.scale[i]) || value.scale[i] <= 0
		}
		invalid = invalid || !finite(min_scale) || !finite(max_scale) || min_scale <= 0 || max_scale < min_scale
	}
	if g.dragging && !invalid {
		invalid = mode != g.mode || viewport != g.viewport ||
			world.camera3d_view_projection(camera) != g.view_projection
	}
	if invalid || !input.down {
		r.ended = g.dragging
		r.cancelled = invalid && g.dragging
		g.dragging = false
		if !input.down do g.captured = false
		return r
	}
	if !finite(input.pointer.x) || !finite(input.pointer.y) do return r
	local := input.pointer-foster.Vec2{viewport.X, viewport.Y}
	ray, ray_ok := world.camera3d_screen_point_to_ray(camera, local)
	if g.dragging {
		candidate := g.start
		switch g.mode {
		case .Translate:
			if !ray_ok do return r
			d, ok := drag_distance(ray, g.start.position, g.normal, g.axis)
			if !ok do return r
			candidate.position[g.axis] += d-g.distance
		case .Rotate:
			if !ray_ok do return r
			a, ok := ring_angle(ray, g.start.position, g.axis)
			if !ok do return r
			g.angle += wrap_angle(a-g.last_angle)
			g.last_angle = a
			r.angle = g.angle
			if g.angle != 0 do candidate.rotation = rotate_world(g.start.rotation, g.axis, g.angle, value.rotation)
		case .Scale:
			factor := 1+dot2(input.pointer-g.pointer, g.direction)/(style.length*scale)
			low: f32 = 0
			high := f32(math.INF_F32)
			for i in 0..<3 {
				if g.axis != 3 && g.axis != i do continue
				low = max(low, min_scale/g.start.scale[i])
				high = min(high, max_scale/g.start.scale[i])
			}
			if low > high || !finite(factor) do return r
			r.factor = math.clamp(factor, low, high)
			for i in 0..<3 {
				if g.axis == 3 || g.axis == i {
					candidate.scale[i] = math.clamp(candidate.scale[i]*r.factor, min_scale, max_scale)
				}
			}
		}
		r.transform = candidate
		r.changed = candidate != value
		return r
	}
	if g.captured || !input.pressed || !input.allow_start || !ray_ok do return r
	if local.x < 0 || local.y < 0 || local.x > viewport.Width || local.y > viewport.Height do return r
	geometry := transform_geometry(camera, value, viewport, mode, scale, style)
	axis := transform_hit(geometry, input.pointer, scale, style)
	if axis < 0 do return r
	switch mode {
	case .Translate:
		normal := value.position-camera.position
		normal[axis] = 0
		length := math.sqrt(dot(normal, normal))
		if length <= 0.000001 do return r
		g.normal = normal/length
		d, ok := drag_distance(ray, value.position, g.normal, axis)
		if !ok do return r
		g.distance = d
	case .Rotate:
		a, ok := ring_angle(ray, value.position, axis)
		if !ok do return r
		g.last_angle = a
		g.angle = 0
	case .Scale:
		g.direction = {0.70710678, -0.70710678}
		if axis < 3 {
			d := geometry.axes.ends[axis]-geometry.axes.origin
			g.direction = d/math.sqrt(dot2(d, d))
		}
	}
	g.start = value
	g.angle = 0
	g.pointer = input.pointer
	g.axis = axis
	g.mode = mode
	g.viewport = viewport
	g.view_projection = world.camera3d_view_projection(camera)
	g.dragging = true
	g.captured = true
	r.axis = axis
	r.started = true
	r.captured = true
	return r
}

// ==============================================================================
// 旋转数学
// ==============================================================================

@(private)
dot2 :: proc(a, b: foster.Vec2) -> f32 {
	return a.x*b.x+a.y*b.y
}

@(private)
ring_angle :: proc(ray: world.Ray3D, origin: foster.Vec3, axis: int) -> (f32, bool) {
	normal: foster.Vec3
	normal[axis] = 1
	d, ok := world.ray3d_hit_plane(ray, origin, normal)
	if !ok do return 0, false
	p := world.ray3d_at(ray, d)-origin
	if dot(p, p) < 0.0000001 do return 0, false
	a := math.atan2(p[(axis+2)%3], p[(axis+1)%3])
	return a, finite(a)
}

@(private)
wrap_angle :: proc(a: f32) -> f32 {
	return a-2*math.PI*math.floor((a+math.PI)/(2*math.PI))
}

@(private)
rotate_xyz :: proc(v, angles: foster.Vec3) -> foster.Vec3 {
	r := v
	for axis in 0..<3 {
		a, b := (axis+1)%3, (axis+2)%3
		x := r[a]*math.cos(angles[axis])-r[b]*math.sin(angles[axis])
		r[b] = r[a]*math.sin(angles[axis])+r[b]*math.cos(angles[axis])
		r[a] = x
	}
	return r
}

// 左乘世界轴旋转；输出选择靠近 reference 的等价 Euler 分支，跨 ±π 时保持连续。
@(private)
rotate_world :: proc(initial: foster.Vec3, axis: int, angle: f32, reference: foster.Vec3) -> foster.Vec3 {
	delta: foster.Vec3
	delta[axis] = angle
	x := rotate_xyz(rotate_xyz({1, 0, 0}, initial), delta)
	y := rotate_xyz(rotate_xyz({0, 1, 0}, initial), delta)
	z := rotate_xyz(rotate_xyz({0, 0, 1}, initial), delta)
	cy := math.sqrt(x[0]*x[0]+x[1]*x[1])
	r := foster.Vec3{0, math.atan2(-x[2], cy), 0}
	if cy > 0.000001 {
		r[0] = math.atan2(y[2], z[2])
		r[2] = math.atan2(x[1], x[0])
	} else {
		// 万向锁处保留上一帧 Z，求出等价 X，避免强制归零导致面板跳变。
		r[2] = reference[2]
		r[0] = math.atan2(-z[1], y[1])+(r[1] > 0 ? r[2] : -r[2])
	}
	alternative := foster.Vec3{r[0]+math.PI, math.PI-r[1], r[2]+math.PI}
	for i in 0..<3 {
		r[i] = reference[i]+wrap_angle(r[i]-reference[i])
		alternative[i] = reference[i]+wrap_angle(alternative[i]-reference[i])
	}
	if dot(alternative-reference, alternative-reference) < dot(r-reference, r-reference) do return alternative
	return r
}
