#+test
package gizmo

import "core:math"
import "core:testing"

import foster "olib:foster"
import world "olib:kit/world"

// 分区：投影与命中 / 拖拽结果 / 中断与捕获 / 旋转与缩放 / 二维工具

// ==============================================================================
// 投影与命中
// ==============================================================================

@(private)
test_camera :: proc(width, height: int) -> world.Camera3D {
	c: world.Camera3D
	world.camera3d_init(&c, width, height)
	world.camera3d_set_position(&c, {3, 3, 6})
	world.camera3d_set_target(&c, {})
	return c
}

@(test)
translation_viewport_and_projection :: proc(t: ^testing.T) {
	c := test_camera(960, 600)
	viewport := foster.Rect{80, 40, 960, 600}
	center, ok := project(&c, {}, viewport)
	testing.expect(t, ok && abs(center.x-560) < 0.001 && abs(center.y-340) < 0.001)
	g := translation_geometry(&c, {}, viewport, 1.25)
	for end, axis in g.ends {
		testing.expect(t, g.visible[axis])
		testing.expect(t, translation_hit(g, g.origin+(end-g.origin)*0.8, 9*1.25) == axis)
	}
	testing.expect(t, translation_hit(g, center, 9) == -1, "center gap prevents ambiguous axis selection")
	_, behind := project(&c, c.position*2, viewport)
	testing.expect(t, !behind)
	_, invalid := project(&c, {}, {0, 0, 480, 300})
	testing.expect(t, !invalid, "camera viewport mismatch cannot silently offset handles")
	_, invalid = project(&c, {}, {})
	testing.expect(t, !invalid)
	world.camera3d_set_position(&c, {0, 0, 6})
	g = translation_geometry(&c, {}, viewport)
	testing.expect(t, g.visible[0] && g.visible[1] && !g.visible[2], "view-aligned axis is hidden")
}

// ==============================================================================
// 拖拽结果
// ==============================================================================

@(test)
translation_drag_all_axes :: proc(t: ^testing.T) {
	sizes := [2][2]int{{1280, 720}, {960, 600}}
	for size in sizes {
		c := test_camera(size[0], size[1])
		viewport := foster.Rect{30, 55, f32(size[0]), f32(size[1])}
		origin := foster.Vec3{0.2, -0.1, 0.3}
		geometry := translation_geometry(&c, origin, viewport)
		for axis in 0..<3 {
			g: Translation_Gizmo
			p := geometry.origin+(geometry.ends[axis]-geometry.origin)*0.8
			r := translation_update(&g, &c, origin, viewport,
				{pointer = p, pressed = true, down = true, enabled = true, allow_start = true})
			testing.expect(t, r.started && !r.changed && r.captured && r.axis == axis)
			testing.expect(t, r.position == origin, "grabbing handle must not jump")
			ray, _ := world.camera3d_screen_point_to_ray(&c, p-foster.Vec2{viewport.X, viewport.Y})
			n := origin-c.position
			n[axis] = 0
			d, hit := world.ray3d_hit_plane(ray, origin, n)
			point := world.ray3d_at(ray, d)
			point[axis] += 0.75
			end, ok := project(&c, point, viewport)
			testing.expect(t, hit && ok)
			r = translation_update(&g, &c, origin, viewport,
				{pointer = end, down = true, enabled = true, allow_start = false})
			testing.expect(t, r.changed && r.captured && !r.started && !r.ended,
				"capture continues while pointer crosses UI")
			for component in 0..<3 {
				expected := component == axis ? f32(0.75) : f32(0)
				testing.expect(t, abs(r.delta[component]-expected) < 0.001)
			}
			position := r.position
			r = translation_update(&g, &c, position, viewport, {enabled = true})
			testing.expect(t, r.ended && !r.cancelled && r.captured && !g.dragging && !g.captured)
			testing.expect(t, abs(r.delta[axis]-0.75) < 0.001, "release reports accepted total displacement")
			r = translation_update(&g, &c, position, viewport, {enabled = true})
			testing.expect(t, !r.captured && !r.ended, "release event is emitted once")
		}
	}
}

// ==============================================================================
// 中断与捕获
// ==============================================================================

@(test)
translation_cancel_and_reacquire :: proc(t: ^testing.T) {
	c := test_camera(1280, 720)
	viewport := foster.Rect{0, 0, 1280, 720}
	geometry := translation_geometry(&c, {}, viewport)
	p := geometry.origin+(geometry.ends[0]-geometry.origin)*0.8
	g: Translation_Gizmo
	input := Translation_Input{pointer = p, down = true, pressed = true, enabled = true, allow_start = false}
	r := translation_update(&g, &c, {}, viewport, input)
	testing.expect(t, !r.captured && !r.started, "UI can prevent capture")
	input.allow_start = true
	r = translation_update(&g, &c, {}, viewport, input)
	testing.expect(t, r.started)
	input.cancel = true
	r = translation_update(&g, &c, {}, viewport, input)
	testing.expect(t, r.ended && r.cancelled && r.captured && !r.changed)
	input.cancel = false
	r = translation_update(&g, &c, {}, viewport, input)
	testing.expect(t, !r.started && r.captured, "changing target cannot reacquire while held")
	translation_update(&g, &c, {}, viewport, {enabled = true})
	r = translation_update(&g, &c, {}, viewport, input)
	testing.expect(t, r.started)
	input.enabled = false
	r = translation_update(&g, &c, {}, viewport, input)
	testing.expect(t, r.ended && r.cancelled && !r.changed, "focus loss ends without reverting object")
}

@(test)
translation_camera_resize_and_invalid_pointer :: proc(t: ^testing.T) {
	c := test_camera(1280, 720)
	viewport := foster.Rect{0, 0, 1280, 720}
	geometry := translation_geometry(&c, {}, viewport)
	p := geometry.origin+(geometry.ends[0]-geometry.origin)*0.8
	input := Translation_Input{pointer = p, down = true, pressed = true, enabled = true, allow_start = true}
	g: Translation_Gizmo
	translation_update(&g, &c, {}, viewport, input)
	input.pointer.x = math.INF_F32
	r := translation_update(&g, &c, {}, viewport, input)
	testing.expect(t, !r.changed && g.dragging, "invalid pointer never produces invalid positions")
	world.camera3d_set_position(&c, {4, 3, 6})
	r = translation_update(&g, &c, {}, viewport, input)
	testing.expect(t, r.cancelled && r.ended && !r.changed, "moving camera ends drag instead of jumping")
	g = {}
	geometry = translation_geometry(&c, {}, viewport)
	input.pointer = geometry.origin+(geometry.ends[0]-geometry.origin)*0.8
	translation_update(&g, &c, {}, viewport, input)
	world.camera3d_set_viewport(&c, 640, 360)
	r = translation_update(&g, &c, {}, {0, 0, 640, 360}, input)
	testing.expect(t, r.cancelled && r.ended && !r.changed, "resize ends drag")
	_, parallel := drag_distance({origin = {0, 0, -2}, direction = {1, 0, 0}}, {}, {0, 0, 1}, 0)
	testing.expect(t, !parallel)
}

// ==============================================================================
// 旋转与缩放
// ==============================================================================

@(test)
rotation_world_composition :: proc(t: ^testing.T) {
	// 混合姿态与 ±90° 万向锁，验证旋转后的基向量，不要求唯一 Euler 表达。
	initials := [4]foster.Vec3{{0.4, -0.7, 1.1}, {0.6, math.PI/2, 0.2},
		{0.6, -math.PI/2, 0.2}, {3.1, 1.5, -2.9}}
	for initial in initials {
		for axis in 0..<3 {
			for angle in ([4]f32{0, 0.3, -1.2, 3.4}) {
				result := rotate_world(initial, axis, angle, initial)
				for component in 0..<3 {
					basis: foster.Vec3
					basis[component] = 1
					before := rotate_xyz(basis, initial)
					// Rodrigues 公式独立验证世界轴左乘，不能把 world angle 加进 Euler 分量。
					normal: foster.Vec3
					normal[axis] = 1
					cross := foster.Vec3{normal[1]*before[2]-normal[2]*before[1],
						normal[2]*before[0]-normal[0]*before[2], normal[0]*before[1]-normal[1]*before[0]}
					expected := before*math.cos(angle)+cross*math.sin(angle)+
						normal*dot(normal, before)*(1-math.cos(angle))
					diff := rotate_xyz(basis, result)-expected
					testing.expect(t, dot(diff, diff) < 0.000001, "world rotation preserves orientation at Euler singularities")
				}
			}
		}
	}
}

@(test)
rotation_drag_wrap_and_capture :: proc(t: ^testing.T) {
	c := test_camera(960, 600)
	viewport := foster.Rect{41, 73, 960, 600}
	initial := Transform{rotation = {0.4, -0.7, 1.1}, scale = {1, 2, 3}}
	geometry := transform_geometry(&c, initial, viewport, .Rotate, 1.25)
	for axis in 0..<3 {
		start: foster.Vec2
		found := false
		for i in 0..<RING_SEGMENTS {
			p := geometry.rings[axis][i]
			if geometry.segments[axis][i] && transform_hit(geometry, p, 1.25) == axis {
				start = p
				found = true
				break
			}
		}
		testing.expect(t, found, "each visible ring has a selectable segment")
		if !found do continue
		g: Transform_Gizmo
		r := transform_update(&g, &c, initial, viewport, .Rotate,
			{pointer = start, pressed = true, down = true, enabled = true, allow_start = true}, 1.25)
		testing.expect(t, r.started && !r.changed && r.transform == initial && g.axis == axis)
		ray, _ := world.camera3d_screen_point_to_ray(&c, start-foster.Vec2{viewport.X, viewport.Y})
		normal: foster.Vec3
		normal[axis] = 1
		d, _ := world.ray3d_hit_plane(ray, initial.position, normal)
		p := world.ray3d_at(ray, d)-initial.position
		base_angle := g.last_angle
		radius := math.sqrt(dot(p, p))
		value := initial
		for step in 1..=80 {
			a := base_angle+f32(step)*0.1
			point := initial.position
			point[(axis+1)%3] += math.cos(a)*radius
			point[(axis+2)%3] += math.sin(a)*radius
			pixel, ok := project(&c, point, viewport)
			testing.expect(t, ok)
			r = transform_update(&g, &c, value, viewport, .Rotate,
				{pointer = pixel, down = true, enabled = true}, 1.25)
			testing.expect(t, r.captured && r.changed && abs(r.angle-f32(step)*0.1) < 0.001,
				"unwrapped angle crosses ±PI and multiple turns without jumping")
			testing.expect(t, r.transform.position == initial.position && r.transform.scale == initial.scale)
			value = r.transform
		}
		r = transform_update(&g, &c, value, viewport, .Rotate, {enabled = true}, 1.25)
		testing.expect(t, r.ended && !r.cancelled && r.captured)
	}
}

@(test)
scale_local_axes_uniform_and_bounds :: proc(t: ^testing.T) {
	c := test_camera(1280, 720)
	viewport := foster.Rect{30, 50, 1280, 720}
	initial := Transform{position = {0.1, 0.2, 0}, rotation = {0.2, 0.4, 0.3}, scale = {1, 2, 3}}
	geometry := transform_geometry(&c, initial, viewport, .Scale)
	for axis in 0..<4 {
		start := geometry.axes.origin
		if axis < 3 {
			testing.expect(t, geometry.axes.visible[axis])
			start = geometry.axes.ends[axis]
		}
		testing.expect(t, transform_hit(geometry, start) == axis)
		g: Transform_Gizmo
		r := transform_update(&g, &c, initial, viewport, .Scale,
			{pointer = start, pressed = true, down = true, enabled = true, allow_start = true})
		testing.expect(t, r.started && !r.changed)
		for distance in ([3]f32{50, -1000, 10000000}) {
			r = transform_update(&g, &c, initial, viewport, .Scale,
				{pointer = start+g.direction*distance, down = true, enabled = true})
			testing.expect(t, r.transform.position == initial.position && r.transform.rotation == initial.rotation)
			for component in 0..<3 {
				v := r.transform.scale[component]
				testing.expect(t, v >= 0.001 && v <= 10000)
				if axis != 3 && component != axis do testing.expect(t, v == initial.scale[component])
				if distance == 50 && (axis == 3 || component == axis) {
					testing.expect(t, abs(v-initial.scale[component]*1.5) < 0.001)
				}
			}
			if axis == 3 do testing.expect(t, abs(r.transform.scale[2]/r.transform.scale[0]-3) < 0.001)
		}
		// 回到原始指针恢复原值，不以逐帧乘法累积误差。
		r = transform_update(&g, &c, r.transform, viewport, .Scale,
			{pointer = start, down = true, enabled = true})
		testing.expect(t, r.transform == initial)
	}
}

@(test)
transform_cancel_mode_focus_resize :: proc(t: ^testing.T) {
	for mode in ([3]Mode{.Translate, .Rotate, .Scale}) {
		for reason in 0..<5 {
			c := test_camera(1280, 720)
			viewport := foster.Rect{0, 0, 1280, 720}
			value := Transform{scale = {1, 1, 1}}
			geometry := transform_geometry(&c, value, viewport, mode)
			p := geometry.axes.origin
			if mode == .Translate do p = geometry.axes.ends[0]
			if mode == .Rotate {
				for i in 0..<RING_SEGMENTS {
					p = geometry.rings[2][i]
					if transform_hit(geometry, p) == 2 do break
				}
			}
			g: Transform_Gizmo
			input := Translation_Input{pointer = p, down = true, pressed = true, enabled = true, allow_start = true}
			r := transform_update(&g, &c, value, viewport, mode, input)
			testing.expect(t, r.started)
			input.pointer.x = math.INF_F32
			r = transform_update(&g, &c, value, viewport, mode, input)
			testing.expect(t, !r.changed && g.dragging)
			input.pointer = p
			next_mode := mode
			switch reason {
			case 0:
				next_mode = Mode((int(mode)+1)%3)
			case 1:
				input.enabled = false
			case 2:
				input.cancel = true
			case 3:
				world.camera3d_set_position(&c, {4, 3, 6})
			case 4:
				viewport.Width = 640
				world.camera3d_set_viewport(&c, 640, 720)
			}
			r = transform_update(&g, &c, value, viewport, next_mode, input)
			testing.expect(t, r.ended && r.cancelled && r.captured && !r.changed)
			input.cancel = false
			input.enabled = true
			r = transform_update(&g, &c, value, viewport, next_mode, input)
			testing.expect(t, !r.started && r.captured, "held mouse cannot capture new mode or target")
			r = transform_update(&g, &c, value, viewport, next_mode, {enabled = true})
			testing.expect(t, r.captured && !g.captured && !g.dragging)
		}
	}
}

// ==============================================================================
// 二维工具
// ==============================================================================

@(test)
transform2d_move_and_projection :: proc(t: ^testing.T) {
	c: world.Camera2D
	world.camera2d_init(&c, 960, 600)
	world.camera2d_set_position(&c, {2, -3})
	world.camera2d_set_zoom(&c, 1.8)
	world.camera2d_set_rotation(&c, 0.6)
	viewport := foster.Rect{70, 40, 960, 600}
	value := Transform2D{position = {3, -2}, rotation = 0.7, scale = {1, 2}}
	geometry := transform2d_geometry(&c, value, viewport, .Translate, 1.25)
	p, ok := project2d(&c, value.position, viewport)
	testing.expect(t, ok && p == geometry.axes.origin)
	for axis in ([3]int{0, 1, 3}) {
		g: Transform_Gizmo2D
		start := p
		if axis < 2 do start = geometry.axes.ends[axis]
		testing.expect(t, transform2d_hit(geometry, start, 1.25) == axis)
		r := transform2d_update(&g, &c, value, viewport, .Translate,
			{pointer = start, pressed = true, down = true, enabled = true, allow_start = true}, 1.25)
		testing.expect(t, r.started && !r.changed)
		world_start, _ := world.camera2d_screen_to_world(&c, start-foster.Vec2{viewport.X, viewport.Y})
		end, _ := project2d(&c, world_start+foster.Vec2{1.3, -0.8}, viewport)
		r = transform2d_update(&g, &c, value, viewport, .Translate,
			{pointer = end, down = true, enabled = true}, 1.25)
		expected := value.position
		if axis == 0 || axis == 3 do expected.x += 1.3
		if axis == 1 || axis == 3 do expected.y -= 0.8
		d := r.transform.position-expected
		testing.expect(t, r.changed && dot2(d, d) < 0.000001)
		testing.expect(t, r.transform.rotation == value.rotation && r.transform.scale == value.scale)
		value_after := r.transform
		r = transform2d_update(&g, &c, value_after, viewport, .Translate, {enabled = true}, 1.25)
		testing.expect(t, r.ended && !r.cancelled && r.captured && !g.captured)
	}
	world.camera2d_set_zoom(&c, 0)
	_, ok = project2d(&c, value.position, viewport)
	testing.expect(t, !ok, "singular camera cannot project or capture")
}

@(test)
transform2d_rotation_and_scale :: proc(t: ^testing.T) {
	c: world.Camera2D
	world.camera2d_init(&c, 960, 600)
	world.camera2d_set_rotation(&c, -0.8)
	world.camera2d_set_zoom(&c, 2.5)
	viewport := foster.Rect{60, 20, 960, 600}
	initial := Transform2D{rotation = 0.4, scale = {2, 3}}
	geometry := transform2d_geometry(&c, initial, viewport, .Rotate)
	g: Transform_Gizmo2D
	start := geometry.axes.origin+foster.Vec2{geometry.radius, 0}
	r := transform2d_update(&g, &c, initial, viewport, .Rotate,
		{pointer = start, pressed = true, down = true, enabled = true, allow_start = true})
	testing.expect(t, r.started && r.axis == 2)
	value := initial
	for step in 1..=80 {
		a := f32(step)*0.1
		end := geometry.axes.origin+foster.Vec2{math.cos(a), math.sin(a)}*geometry.radius
		r = transform2d_update(&g, &c, value, viewport, .Rotate,
			{pointer = end, down = true, enabled = true})
		testing.expect(t, abs(r.transform.rotation-initial.rotation-a) < 0.001)
		testing.expect(t, r.transform.position == initial.position && r.transform.scale == initial.scale)
		value = r.transform
	}
	r = transform2d_update(&g, &c, value, viewport, .Rotate,
		{pointer = geometry.axes.origin, down = true, enabled = true})
	testing.expect(t, !r.changed, "center angle is undefined")
	geometry = transform2d_geometry(&c, initial, viewport, .Scale, 1.25)
	for axis in ([3]int{0, 1, 3}) {
		g = {}
		start = geometry.axes.origin
		if axis < 2 do start = geometry.axes.ends[axis]
		r = transform2d_update(&g, &c, initial, viewport, .Scale,
			{pointer = start, pressed = true, down = true, enabled = true, allow_start = true}, 1.25)
		testing.expect(t, r.started && r.axis == axis && !r.changed)
		for distance in ([3]f32{62.5, -10000, 10000000}) {
			r = transform2d_update(&g, &c, initial, viewport, .Scale,
				{pointer = start+g.direction*distance, down = true, enabled = true}, 1.25)
			for i in 0..<2 {
				testing.expect(t, r.transform.scale[i] >= 0.001 && r.transform.scale[i] <= 10000)
				if axis < 2 && axis != i do testing.expect(t, r.transform.scale[i] == initial.scale[i])
				if distance == 62.5 && (axis == 3 || axis == i) {
					testing.expect(t, abs(r.transform.scale[i]-initial.scale[i]*1.5) < 0.001)
				}
			}
			if axis == 3 do testing.expect(t, abs(r.transform.scale.y/r.transform.scale.x-1.5) < 0.001)
			testing.expect(t, r.transform.position == initial.position && r.transform.rotation == initial.rotation)
		}
		r = transform2d_update(&g, &c, r.transform, viewport, .Scale,
			{pointer = start, down = true, enabled = true}, 1.25)
		testing.expect(t, r.transform == initial, "returning pointer restores initial values")
	}
}

@(test)
transform2d_cancel_and_input_contract :: proc(t: ^testing.T) {
	for mode in ([3]Mode{.Translate, .Rotate, .Scale}) {
		for reason in 0..<7 {
			c: world.Camera2D
			world.camera2d_init(&c, 960, 600)
			viewport := foster.Rect{40, 20, 960, 600}
			value := Transform2D{scale = {1, 1}}
			geometry := transform2d_geometry(&c, value, viewport, mode)
			p := geometry.axes.origin
			if mode == .Rotate do p.x += geometry.radius
			g: Transform_Gizmo2D
			input := Translation_Input{pointer = p, down = true, pressed = true, enabled = true}
			r := transform2d_update(&g, &c, value, viewport, mode, input)
			testing.expect(t, !r.started, "UI prevents starting")
			input.allow_start = true
			r = transform2d_update(&g, &c, value, viewport, mode, input)
			testing.expect(t, r.started)
			input.pointer.x = math.INF_F32
			r = transform2d_update(&g, &c, value, viewport, mode, input)
			testing.expect(t, !r.changed && g.dragging)
			input.pointer = p
			next_mode := mode
			switch reason {
			case 0:
				input.cancel = true
			case 1:
				input.enabled = false
			case 2:
				next_mode = Mode((int(mode)+1)%3)
			case 3:
				world.camera2d_set_zoom(&c, 1.2)
			case 4:
				world.camera2d_set_rotation(&c, 0.3)
			case 5:
				world.camera2d_set_position(&c, {1, 2})
			case 6:
				viewport.X += 20
			}
			r = transform2d_update(&g, &c, value, viewport, next_mode, input)
			testing.expect(t, r.ended && r.cancelled && r.captured && !r.changed)
			input.enabled = true
			input.cancel = false
			r = transform2d_update(&g, &c, value, viewport, next_mode, input)
			testing.expect(t, r.captured && !r.started)
			r = transform2d_update(&g, &c, value, viewport, next_mode, {enabled = true})
			testing.expect(t, r.captured && !g.captured)
			r = transform2d_update(&g, &c, value, viewport, next_mode, {enabled = true})
			testing.expect(t, !r.captured && !r.ended)
		}
	}
}

// 三维绘制的世界顶点应与命中几何一致；不需要窗口或 GPU。
@(test)
transform_mesh_world_geometry :: proc(t: ^testing.T) {
	c := test_camera(960, 600)
	viewport := foster.Rect{80, 40, 960, 600}
	vertices: [dynamic]Vertex3D
	defer delete(vertices)
	value := Transform{rotation = {0.3, 0.5, -0.2}, scale = {2, 1, 3}}
	state: Transform_Gizmo
	for mode in Mode {
		labels := transform_mesh(&vertices, &c, value, viewport, mode, &state, {-100, -100}, 1.25)
		testing.expect(t, len(vertices) > 100 && len(vertices)%3 == 0)
		g := transform_geometry(&c, value, viewport, mode, 1.25)
		for v in vertices {
			for n in v.position do testing.expect(t, finite(n))
			for n in v.color do testing.expect(t, finite(n) && n >= 0 && n <= 1)
		}
		for label, axis in labels {
			if mode == .Rotate || !g.axes.visible[axis] do continue
			testing.expect(t, label.visible)
			nearest := f32(math.INF_F32)
			for v in vertices {
				p, ok := project(&c, v.position, viewport)
				if ok do nearest = min(nearest, dot2(p-g.axes.ends[axis], p-g.axes.ends[axis]))
			}
			testing.expect(t, nearest < 100, "solid mesh ends align with screen-space picking")
		}
	}
	// 深度翻倍，网格世界尺寸也翻倍；屏幕位置保持不变。
	value.rotation = {}
	transform_mesh(&vertices, &c, value, viewport, .Translate, &state, {})
	before := make([]Vertex3D, len(vertices))
	defer delete(before)
	copy(before, vertices[:])
	world.camera3d_set_position(&c, c.position*2)
	transform_mesh(&vertices, &c, value, viewport, .Translate, &state, {})
	testing.expect(t, len(vertices) == len(before))
	for v, i in vertices {
		difference := v.position-before[i].position*2
		testing.expect(t, dot(difference, difference) < 0.00001, "constant apparent handle size")
	}
	value.position = c.position*2
	transform_mesh(&vertices, &c, value, viewport, .Translate, &state, {})
	testing.expect(t, len(vertices) == 0, "behind-camera mesh is rejected")
	transform_mesh(&vertices, nil, value, viewport, .Translate, &state, {})
	testing.expect(t, len(vertices) == 0)
}
