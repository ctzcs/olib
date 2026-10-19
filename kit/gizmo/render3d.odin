package gizmo

import "core:math"

import foster "olib:foster"
import r3d "olib:kit/rendering/3d"
import world "olib:kit/world"

// 分区：资源生命周期 / 世界空间网格 / 三维绘制
// CPU 顶点、Mesh、Shader、Material 由 Renderer3D 独占；宿主提供有场景深度的目标。
Vertex3D :: struct {
	position: foster.Vec3,
	color: [4]f32,
}
Renderer3D :: struct {
	mesh: foster.Mesh,
	vertex, fragment: foster.Shader,
	material: foster.Material,
	vertices: [dynamic]Vertex3D,
	ready: bool,
}

// ==============================================================================
// 资源生命周期
// ==============================================================================

renderer3d_init :: proc(r: ^Renderer3D, device: ^foster.GraphicsDevice) -> bool {
	if device == nil || !r3d.shader3d_driver_supported(device.Driver) do return false
	d := device.Driver
	foster.ShaderInit(&r.vertex, device, {Stage = .Vertex, EntryPoint = "vertex_main",
		UniformBufferCount = 1, Code = r3d.shader3d_pick_code(d,
			#load("shaders/Compiled/Gizmo3D.vertex.spv"), #load("shaders/Compiled/Gizmo3D.vertex.dxil"),
			#load("shaders/Compiled/Gizmo3D.vertex.msl"))}, "Gizmo3D vertex")
	foster.ShaderInit(&r.fragment, device, {Stage = .Fragment, EntryPoint = "fragment_main",
		UniformBufferCount = 1, Code = r3d.shader3d_pick_code(d,
			#load("shaders/Compiled/Gizmo3D.fragment.spv"), #load("shaders/Compiled/Gizmo3D.fragment.dxil"),
			#load("shaders/Compiled/Gizmo3D.fragment.msl"))}, "Gizmo3D fragment")
	if r.vertex.Resource == nil || r.fragment.Resource == nil {
		renderer3d_destroy(r)
		return false
	}
	format := foster.VertexFormatMake([]foster.VertexElement{{0, .Float3, false}, {1, .Float4, false}}, size_of(Vertex3D))
	defer foster.VertexFormatDispose(&format)
	foster.MeshInitWithFormat(&r.mesh, device, format, .ThirtyTwo, "Gizmo3D mesh")
	foster.MaterialInitWithShaders(&r.material, &r.vertex, &r.fragment)
	r.vertices = make([dynamic]Vertex3D, 0, 16000)
	r.ready = true
	return true
}

renderer3d_destroy :: proc(r: ^Renderer3D) {
	foster.MaterialDispose(&r.material)
	foster.MeshDispose(&r.mesh)
	foster.ShaderDispose(&r.vertex)
	foster.ShaderDispose(&r.fragment)
	delete(r.vertices)
	r^ = {}
}

// ==============================================================================
// 世界空间网格
// ==============================================================================

// 不读取 GPU，可供测试和自定义渲染器使用。顶点缓冲复用，标签只用于最终像素 UI。
transform_mesh :: proc(vertices: ^[dynamic]Vertex3D, camera: ^world.Camera3D, value: Transform,
	viewport: foster.Rect, mode: Mode, state: ^Transform_Gizmo, pointer: foster.Vec2,
	scale: f32 = 1, style := DEFAULT_TRANSLATION_STYLE) -> [3]Axis_Label {
	clear(vertices)
	labels: [3]Axis_Label
	if !finite(scale) || scale <= 0 || !finite(style.length) || style.length <= 0 do return labels
	_, ok := project(camera, value.position, viewport)
	if !ok do return labels
	for i in 0..<3 {
		if !finite(value.rotation[i]) || !finite(value.scale[i]) || value.scale[i] <= 0 do return labels
	}
	geometry := transform_geometry(camera, value, viewport, mode, scale, style)
	depth := dot(value.position-camera.position, world.camera3d_forward(camera))
	unit := depth*2*math.tan(camera.field_of_view*0.5)*scale/viewport.Height
	length := unit*style.length
	hover := state.dragging ? state.axis : transform_hit(geometry, pointer, scale, style)
	for axis in 0..<3 {
		color := hover == axis ? style.highlight : style.colors[axis]
		if mode == .Rotate {
			for i in 0..<RING_SEGMENTS {
				if !geometry.segments[axis][i] do continue
				a := f32(i)*2*math.PI/RING_SEGMENTS
				b := f32(i+1)*2*math.PI/RING_SEGMENTS
				p := value.position
				q := value.position
				p[(axis+1)%3] += math.cos(a)*length*0.72
				p[(axis+2)%3] += math.sin(a)*length*0.72
				q[(axis+1)%3] += math.cos(b)*length*0.72
				q[(axis+2)%3] += math.sin(b)*length*0.72
				tube(vertices, p, q, unit*style.line_width*0.5, unit*style.line_width*0.5, color)
				if i == axis*RING_SEGMENTS/3 do labels[axis] = {true, geometry.rings[axis][i], color}
			}
		} else if geometry.axes.visible[axis] {
			direction: foster.Vec3
			direction[axis] = 1
			if mode == .Scale do direction = rotate_xyz(direction, value.rotation)
			end := value.position+direction*length
			shaft_end := mode == .Translate ? end-direction*style.arrow_length*unit : end
			tube(vertices, value.position, shaft_end, unit*style.line_width*0.5, unit*style.line_width*0.5, color)
			if mode == .Translate {
				tube(vertices, shaft_end, end, style.arrow_half_width*unit, 0, color)
			} else {
				box(vertices, end, value.rotation, unit*5, color)
			}
			delta := geometry.axes.ends[axis]-geometry.axes.origin
			labels[axis] = {true, geometry.axes.ends[axis]+delta/math.sqrt(dot2(delta, delta))*style.label_gap*scale, color}
		}
	}
	if mode == .Scale && geometry.center_visible {
		box(vertices, value.position, value.rotation, unit*6, hover == 3 ? style.highlight : style.center)
	}
	return labels
}

@(private)
cross3 :: proc(a, b: foster.Vec3) -> foster.Vec3 {
	return {a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0]}
}

@(private)
triangle :: proc(v: ^[dynamic]Vertex3D, a, b, c: foster.Vec3, color: foster.Color) {
	n := cross3(b-a, c-a)
	magnitude := math.sqrt(dot(n, n))
	if magnitude <= 0 || !finite(magnitude) do return
	// 固定柔和明暗让圆柱和方块显出体积，不依赖项目的灯光材质。
	shade := 0.7+0.3*abs(dot(n/magnitude, {0.36, 0.8, 0.48}))
	col := [4]f32{f32(color.R)/255*shade, f32(color.G)/255*shade, f32(color.B)/255*shade, f32(color.A)/255}
	append(v, Vertex3D{a, col}, Vertex3D{b, col}, Vertex3D{c, col})
}

@(private)
tube :: proc(v: ^[dynamic]Vertex3D, a, b: foster.Vec3, radius_a, radius_b: f32, color: foster.Color) {
	d := b-a
	length := math.sqrt(dot(d, d))
	if length <= 0.0000001 do return
	d /= length
	reference := foster.Vec3{0, 1, 0}
	if abs(d[1]) > 0.9 do reference = {1, 0, 0}
	u := cross3(d, reference)
	u /= math.sqrt(dot(u, u))
	w := cross3(d, u)
	for i in 0..<8 {
		x := f32(i)*2*math.PI/8
		y := f32(i+1)*2*math.PI/8
		p := u*math.cos(x)+w*math.sin(x)
		q := u*math.cos(y)+w*math.sin(y)
		triangle(v, a+p*radius_a, b+p*radius_b, b+q*radius_b, color)
		triangle(v, a+p*radius_a, b+q*radius_b, a+q*radius_a, color)
		triangle(v, a, a+q*radius_a, a+p*radius_a, color)
		triangle(v, b, b+p*radius_b, b+q*radius_b, color)
	}
}

@(private)
box :: proc(v: ^[dynamic]Vertex3D, center, rotation: foster.Vec3, half: f32, color: foster.Color) {
	for axis in 0..<3 {
		for side in ([2]f32{-1, 1}) {
			points: [4]foster.Vec3
			for corner, i in ([4][2]f32{{-1, -1}, {1, -1}, {1, 1}, {-1, 1}}) {
				p: foster.Vec3
				p[axis] = side*half
				p[(axis+1)%3] = corner[0]*half
				p[(axis+2)%3] = corner[1]*half
				points[i] = center+rotate_xyz(p, rotation)
			}
			triangle(v, points[0], points[1], points[2], color)
			triangle(v, points[0], points[2], points[3], color)
		}
	}
}

// ==============================================================================
// 三维绘制
// ==============================================================================

// 目标必须已有与 camera/viewport 匹配的场景深度（标准 0..1 深度，近小远大）。
// 两通道都不写深度；被遮挡部分淡化，保留可操作提示。返回的标签交由 UI 绘制。
transform_draw :: proc(r: ^Renderer3D, target: foster.DrawableTarget, camera: ^world.Camera3D,
	value: Transform, viewport: foster.Rect, mode: Mode, state: ^Transform_Gizmo, pointer: foster.Vec2,
	scale: f32 = 1, style := DEFAULT_TRANSLATION_STYLE) -> [3]Axis_Label {
	if !r.ready do return {}
	labels := transform_mesh(&r.vertices, camera, value, viewport, mode, state, pointer, scale, style)
	if len(r.vertices) == 0 do return labels
	foster.MeshSetVertexCount(&r.mesh, len(r.vertices))
	foster.MeshSetVertices(&r.mesh, raw_data(r.vertices), len(r.vertices))
	matrix_bytes: [64]u8
	r3d.std140_write_matrix(matrix_bytes[:], 0, world.camera3d_view_projection(camera))
	foster.MaterialStageSetUniformBuffer(&r.material.Vertex, matrix_bytes[:], 0)
	command: foster.DrawCommand
	foster.DrawCommandFromMesh(&command, target, &r.mesh, &r.material)
	defer foster.DrawCommandDispose(&command)
	command.DepthTestEnabled = true
	command.DepthWriteEnabled = false
	command.CullMode = .None
	command.HasViewport = true
	command.Viewport = {int(viewport.X), int(viewport.Y), int(viewport.Width), int(viewport.Height)}
	command.HasScissor = true
	command.Scissor = command.Viewport
	command.BlendMode = {ColorOperation = .Add, ColorSource = .SrcAlpha, ColorDestination = .OneMinusSrcAlpha,
		AlphaOperation = .Add, AlphaSource = .One, AlphaDestination = .OneMinusSrcAlpha, Mask = .RGBA}
	for occluded in ([2]bool{true, false}) {
		tint: [16]u8
		r3d.std140_write_vec4(tint[:], 0, {1, 1, 1, occluded ? 0.12 : 1})
		foster.MaterialStageSetUniformBuffer(&r.material.Fragment, tint[:], 0)
		command.DepthCompare = occluded ? .Greater : .LessOrEqual
		foster.GraphicsDeviceDraw(r.mesh.GraphicsDevice, &command)
	}
	return labels
}

translation_draw :: proc(r: ^Renderer3D, target: foster.DrawableTarget, camera: ^world.Camera3D,
	position: foster.Vec3, viewport: foster.Rect, state: ^Translation_Gizmo, pointer: foster.Vec2,
	scale: f32 = 1, style := DEFAULT_TRANSLATION_STYLE) -> [3]Axis_Label {
	transform := Transform_Gizmo{dragging = state.dragging, axis = state.axis}
	return transform_draw(r, target, camera, {position = position, scale = {1, 1, 1}},
		viewport, .Translate, &transform, pointer, scale, style)
}
