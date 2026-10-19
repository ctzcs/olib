package gizmo

import "core:math"

import foster "olib:foster"
import r2d "olib:kit/rendering/2d"
import world "olib:kit/world"

// 分区：二维变换 / 几何与命中 / 拖拽生命周期 / 覆盖层与坐标校验

// ==============================================================================
// 二维变换
// ==============================================================================

// 与 Camera2D 一致：Y 向下，正角度在未旋转的相机中顺时针；rotation 单位弧度。
Transform2D :: struct {
	position: foster.Vec2,
	rotation: f32,
	scale: foster.Vec2, // 必须为有限正值；单位变换显式传 {1, 1}。
}

// 零值可用，不持有对象、输入源或 GPU 资源。更换目标时由调用方传 cancel。
Transform_Gizmo2D :: struct {
	dragging, captured: bool,
	mode: Mode,
	axis: int, // 0/1 = X/Y；2 = Z 旋转；3 = 自由移动 / 等比缩放。
	start: Transform2D,
	pointer, world_pointer, direction: foster.Vec2,
	last_angle, angle, sensitivity, draw_scale: f32,
	viewport: foster.Rect,
	camera_matrix: foster.Matrix3x2,
}

Transform_Result2D :: struct {
	transform: Transform2D,
	axis: int,
	angle, factor: f32,
	started, changed, ended, cancelled, captured: bool,
}

Transform_Geometry2D :: struct {
	mode: Mode,
	axes: Translation_Geometry, // 仅前两根轴有效，屏幕像素坐标。
	valid: bool,
	radius: f32,
}

// ==============================================================================
// 几何与命中
// ==============================================================================

project2d :: proc(camera: ^world.Camera2D, position: foster.Vec2,
	viewport: foster.Rect) -> (foster.Vec2, bool) {
	if !camera2d_valid(camera, viewport) || !finite2(position) do return {}, false
	p := world.camera2d_world_to_screen(camera, position)+foster.Vec2{viewport.X, viewport.Y}
	return p, finite2(p)
}

transform2d_geometry :: proc(camera: ^world.Camera2D, value: Transform2D, viewport: foster.Rect,
	mode: Mode, scale: f32 = 1, style := DEFAULT_TRANSLATION_STYLE) -> Transform_Geometry2D {
	g := Transform_Geometry2D{mode = mode}
	if !transform2d_valid(value) || !finite(scale) || scale <= 0 ||
		!finite(style.length) || style.length <= 0 {
		return g
	}
	center, ok := project2d(camera, value.position, viewport)
	if !ok do return g
	g.valid = true
	g.axes.origin = center
	g.radius = style.length*scale*0.72
	if mode == .Rotate do return g
	// 移动使用世界轴；缩放轴随对象旋转。轴长度固定为最终输出像素，不随 zoom 改变。
	angle := camera.rotation+(mode == .Scale ? value.rotation : 0)
	x := foster.Vec2{math.cos(angle), math.sin(angle)}
	y := foster.Vec2{-x.y, x.x}
	g.axes.ends[0] = center+x*style.length*scale
	g.axes.ends[1] = center+y*style.length*scale
	g.axes.visible[0] = true
	g.axes.visible[1] = true
	return g
}

transform2d_hit :: proc(g: Transform_Geometry2D, pointer: foster.Vec2, scale: f32 = 1,
	style := DEFAULT_TRANSLATION_STYLE) -> int {
	if !g.valid || !finite2(pointer) || !finite(scale) || scale <= 0 do return -1
	d := pointer-g.axes.origin
	if g.mode == .Rotate {
		if abs(math.sqrt(dot2(d, d))-g.radius) < style.hit_radius*scale do return 2
		return -1
	}
	if abs(d.x) <= 8*scale && abs(d.y) <= 8*scale do return 3
	return translation_hit(g.axes, pointer, style.hit_radius*scale)
}

// ==============================================================================
// 拖拽生命周期
// ==============================================================================

// 与三维工具共用 Mode、Translation_Input 和样式。每帧调用，包括释放/停用帧。
// 相机、视口、模式、UI 比例改变时中断，已经应用的结果不回滚，捕获保持至松开。
transform2d_update :: proc(g: ^Transform_Gizmo2D, camera: ^world.Camera2D,
	value: Transform2D, viewport: foster.Rect, mode: Mode, input: Translation_Input,
	scale: f32 = 1, style := DEFAULT_TRANSLATION_STYLE,
	min_scale: f32 = 0.001, max_scale: f32 = 10000) -> Transform_Result2D {
	r := Transform_Result2D{transform = value, axis = -1, factor = 1, captured = g.captured}
	if g.dragging {
		r.axis = g.axis
		r.angle = g.angle
		if g.mode == .Scale do r.factor = value.scale[g.axis == 3 ? 0 : g.axis]/
			g.start.scale[g.axis == 3 ? 0 : g.axis]
	}
	invalid := !input.enabled || input.cancel || !transform2d_valid(value) ||
		!finite(scale) || scale <= 0 || !finite(style.length) || style.length <= 0 ||
		!finite(min_scale) || !finite(max_scale) || min_scale <= 0 || max_scale < min_scale ||
		!camera2d_valid(camera, viewport)
	if g.dragging && !invalid {
		invalid = g.mode != mode || g.viewport != viewport || g.draw_scale != scale ||
			g.camera_matrix != world.camera2d_matrix(camera)
	}
	if invalid || !input.down {
		r.ended = g.dragging
		r.cancelled = invalid && g.dragging
		g.dragging = false
		if !input.down do g.captured = false
		return r
	}
	if !finite2(input.pointer) do return r
	local := input.pointer-foster.Vec2{viewport.X, viewport.Y}
	p, ok := world.camera2d_screen_to_world(camera, local)
	if !ok || !finite2(p) do return r
	if g.dragging {
		candidate := g.start
		switch g.mode {
		case .Translate:
			delta := p-g.world_pointer
			if g.axis == 3 {
				candidate.position += delta
			} else {
				candidate.position[g.axis] += delta[g.axis]
			}
		case .Rotate:
			d := p-g.start.position
			// 指针经过圆心时角度没有定义，保留最后有效采样。
			if dot2(d, d) < 0.0000001 do return r
			a := math.atan2(d.y, d.x)
			g.angle += wrap_angle(a-g.last_angle)
			g.last_angle = a
			r.angle = g.angle
			candidate.rotation += g.angle
		case .Scale:
			factor := 1+dot2(input.pointer-g.pointer, g.direction)/g.sensitivity
			if !finite(factor) do return r
			low: f32 = 0
			high := f32(math.INF_F32)
			for i in 0..<2 {
				if g.axis != 3 && g.axis != i do continue
				low = max(low, min_scale/g.start.scale[i])
				high = min(high, max_scale/g.start.scale[i])
			}
			if low > high do return r
			// 按下后不动指针，不夹断从外部载入的超范围值。
			if input.pointer != g.pointer {
				r.factor = math.clamp(factor, low, high)
				for i in 0..<2 {
					if g.axis == 3 || g.axis == i {
						candidate.scale[i] = math.clamp(g.start.scale[i]*r.factor, min_scale, max_scale)
					}
				}
			}
		}
		if !transform2d_valid(candidate) do return r
		r.transform = candidate
		r.changed = candidate != value
		return r
	}
	if g.captured || !input.pressed || !input.allow_start do return r
	if local.x < 0 || local.y < 0 || local.x > viewport.Width || local.y > viewport.Height do return r
	geometry := transform2d_geometry(camera, value, viewport, mode, scale, style)
	axis := transform2d_hit(geometry, input.pointer, scale, style)
	if axis < 0 do return r
	g.start = value
	g.pointer = input.pointer
	g.world_pointer = p
	g.axis = axis
	g.mode = mode
	g.angle = 0
	g.last_angle = math.atan2(p.y-value.position.y, p.x-value.position.x)
	g.direction = {0.70710678, -0.70710678}
	if mode == .Scale && axis < 2 {
		d := geometry.axes.ends[axis]-geometry.axes.origin
		g.direction = d/math.sqrt(dot2(d, d))
	}
	g.sensitivity = style.length*scale
	g.draw_scale = scale
	g.viewport = viewport
	g.camera_matrix = world.camera2d_matrix(camera)
	g.dragging = true
	g.captured = true
	r.axis = axis
	r.started = true
	r.captured = true
	return r
}

// ==============================================================================
// 覆盖层与坐标校验
// ==============================================================================

// 最终像素覆盖层；调用方负责矩阵、材质和 viewport 裁剪。标签返回 XYZ 对应槽位。
transform2d_draw :: proc(batch: ^r2d.Render2D, state: ^Transform_Gizmo2D,
	g: Transform_Geometry2D, pointer: foster.Vec2, scale: f32 = 1,
	style := DEFAULT_TRANSLATION_STYLE) -> [3]Axis_Label {
	labels: [3]Axis_Label
	if !g.valid || !finite(scale) || scale <= 0 do return labels
	hover := state.dragging ? state.axis : transform2d_hit(g, pointer, scale, style)
	if g.mode == .Rotate {
		color := hover == 2 ? style.highlight : style.colors[2]
		// 先画完整描边再画前景，避免每段描边盖住相邻段的连接点。
		for pass in 0..<2 {
			for i in 0..<RING_SEGMENTS {
				a := f32(i)*2*math.PI/RING_SEGMENTS
				b := f32(i+1)*2*math.PI/RING_SEGMENTS
				start := g.axes.origin+foster.Vec2{math.cos(a), math.sin(a)}*g.radius
				end := g.axes.origin+foster.Vec2{math.cos(b), math.sin(b)}*g.radius
				r2d.line(batch, start, end,
					(pass == 0 ? style.outline_width : style.line_width)*scale,
					pass == 0 ? style.outline : color)
			}
		}
		labels[2] = {true, g.axes.origin+foster.Vec2{0, -g.radius-style.label_gap*scale}, color}
		return labels
	}
	if g.mode == .Translate {
		translation := Translation_Gizmo{dragging = state.dragging, axis = state.axis}
		labels = draw_projected_axes(batch, &translation, g.axes, pointer, scale, style)
	} else {
		for axis in 0..<2 {
			if !g.axes.visible[axis] do continue
			color := hover == axis ? style.highlight : style.colors[axis]
			end := g.axes.ends[axis]
			r2d.line(batch, g.axes.origin, end, style.outline_width*scale, style.outline)
			r2d.line(batch, g.axes.origin, end, style.line_width*scale, color)
			draw_square(batch, end, 5*scale, color, style.outline)
			d := end-g.axes.origin
			labels[axis] = {true, end+d/math.sqrt(dot2(d, d))*style.label_gap*scale, color}
		}
	}
	draw_square(batch, g.axes.origin, 6*scale,
		hover == 3 ? style.highlight : style.center, style.outline)
	return labels
}

@(private)
finite2 :: proc(v: foster.Vec2) -> bool {
	return finite(v.x) && finite(v.y)
}

@(private)
transform2d_valid :: proc(v: Transform2D) -> bool {
	return finite2(v.position) && finite(v.rotation) && finite2(v.scale) && v.scale.x > 0 && v.scale.y > 0
}

@(private)
camera2d_valid :: proc(camera: ^world.Camera2D, viewport: foster.Rect) -> bool {
	if camera == nil || !finite(viewport.X) || !finite(viewport.Y) ||
		viewport.Width <= 0 || viewport.Height <= 0 {
		return false
	}
	if f32(camera.viewport_size.X) != viewport.Width || f32(camera.viewport_size.Y) != viewport.Height ||
		!finite2(camera.position) || !finite(camera.rotation) || !finite(camera.zoom) ||
		!finite(camera.ppu) || camera.zoom <= 0 || camera.ppu <= 0 {
		return false
	}
	world.camera2d_update(camera)
	return camera.inverse_ok
}

// ==============================================================================
// 覆盖层绘制
// ==============================================================================

// 在最终像素目标上绘制。调用方提供单位像素矩阵、默认材质与目标裁剪；本函数不切换状态。
// 返回标签锚点，调用方用自己的字体/UI 渲染 X/Y/Z；不依赖 Clay，不创建 GPU 资源。
@(private)
draw_projected_axes :: proc(
	batch: ^r2d.Render2D, g: ^Translation_Gizmo, geometry: Translation_Geometry,
	pointer: foster.Vec2, scale: f32 = 1, style := DEFAULT_TRANSLATION_STYLE,
) -> [3]Axis_Label {
	labels: [3]Axis_Label
	if scale <= 0 || !finite(scale) do return labels
	hover := translation_hit(geometry, pointer, style.hit_radius*scale)
	any_visible := false
	for end, axis in geometry.ends {
		if !geometry.visible[axis] do continue
		delta := end-geometry.origin
		length := math.sqrt(delta.x*delta.x+delta.y*delta.y)
		if length <= 0 do continue
		any_visible = true
		color := style.colors[axis]
		if g.dragging ? g.axis == axis : hover == axis do color = style.highlight
		direction := delta/length
		base := end-direction*style.arrow_length*scale
		side := foster.Vec2{-direction.y, direction.x}*style.arrow_half_width*scale
		r2d.line(batch, geometry.origin, base, style.outline_width*scale, style.outline)
		r2d.line(batch, geometry.origin, base, style.line_width*scale, color)
		r2d.triangle(batch, end, base+side, base-side, color)
		labels[axis] = {true, end+direction*style.label_gap*scale, color}
	}
	if any_visible do r2d.circle(batch, geometry.origin, style.center_radius*scale, 12, style.center)
	return labels
}

@(private)
draw_square :: proc(batch: ^r2d.Render2D, center: foster.Vec2, half: f32, color, outline: foster.Color) {
	r2d.rect(batch, {center.x-half-1, center.y-half-1, 2*half+2, 2*half+2}, outline)
	r2d.rect(batch, {center.x-half, center.y-half, 2*half, 2*half}, color)
}

