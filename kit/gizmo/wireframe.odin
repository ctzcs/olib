// gizmo:wireframe —— 网格线框查看：画 meshutil.edges 给出的拓扑边，线宽按最终像素保持，
// 边界 / 属性缝 / 非流形边分色，用于检查和优化模型。与手柄共用 Renderer3D，不持有网格数据。
package gizmo

import "core:math"

import meshutil "olib:core/meshutil"
import foster "olib:foster"
import world "olib:kit/world"

// 分区：样式 / 线框网格 / 绘制

// ==============================================================================
// 样式
// ==============================================================================

Wireframe_Style :: struct {
	line_width: f32, // 最终输出像素，再乘 UI scale
	depth_offset: f32, // 沿视线朝相机推近的像素量，避免线与模型表面深度冲突
	hidden_alpha: f32, // 被场景深度遮挡的线的透明度：0 不画，1 即透视全部线
	colors: [meshutil.Edge_Kind]foster.Color, // A=0 的种类直接跳过，可只看边界或缝
}

DEFAULT_WIREFRAME_STYLE :: Wireframe_Style{
	line_width = 1.25, depth_offset = 3, hidden_alpha = 0.15,
	colors = {
		.Interior = {205, 214, 222, 200},
		.Seam = {108, 167, 255, 255},
		.Border = {255, 180, 97, 255},
		.Non_Manifold = {255, 80, 96, 255},
	},
}

// ==============================================================================
// 线框网格
// ==============================================================================

// 生成世界空间线框三角列表（每条边 6 个顶点，朝向相机的细四边形），不读取 GPU。
// positions 与 edges 为模型局部数据，transform 为模型世界矩阵；越界边、近裁面后的部分被丢弃。
// 相机 viewport_size 必须与 viewport 宽高一致。
wireframe_mesh :: proc(vertices: ^[dynamic]Vertex3D, camera: ^world.Camera3D, positions: [][3]f32,
	edges: []meshutil.Edge, transform: world.Matrix4, viewport: foster.Rect, scale: f32 = 1,
	style := DEFAULT_WIREFRAME_STYLE) {
	clear(vertices)
	if camera == nil || viewport.Width <= 0 || viewport.Height <= 0 do return
	if f32(camera.viewport_size.X) != viewport.Width || f32(camera.viewport_size.Y) != viewport.Height do return
	if !finite(scale) || scale <= 0 || !finite(style.line_width) || style.line_width <= 0 do return
	forward := world.camera3d_forward(camera)
	eye := camera.position
	// 深度为 1 处一个像素对应的世界长度。
	pixel := 2*math.tan(camera.field_of_view*0.5)/viewport.Height
	near := max(camera.near_clip, 0.0001)*1.01
	half_width := style.line_width*scale*0.5
	offset := finite(style.depth_offset) ? max(style.depth_offset, 0)*scale : 0
	for e in edges {
		color := style.colors[e.kind]
		if color.A == 0 || int(e.a) >= len(positions) || int(e.b) >= len(positions) do continue
		a, a_ok := world.matrix4_transform_point(transform, positions[e.a])
		b, b_ok := world.matrix4_transform_point(transform, positions[e.b])
		if !a_ok || !b_ok do continue
		depth_a := dot(a-eye, forward)
		depth_b := dot(b-eye, forward)
		if !finite(depth_a) || !finite(depth_b) || (depth_a < near && depth_b < near) do continue
		if depth_a < near {
			a += (b-a)*((near-depth_a)/(depth_b-depth_a))
			depth_a = near
		} else if depth_b < near {
			b += (a-b)*((near-depth_b)/(depth_a-depth_b))
			depth_b = near
		}
		// 沿视线推近不改变屏幕位置，只让线稳定通过模型自身的深度测试。
		a = toward(a, eye, depth_a*pixel*offset)
		b = toward(b, eye, depth_b*pixel*offset)
		side := cross3(b-a, eye-(a+b)*0.5)
		side_length := math.sqrt(dot(side, side))
		if !(side_length > 0) do continue
		side /= side_length
		wa := side*depth_a*pixel*half_width
		wb := side*depth_b*pixel*half_width
		c := [4]f32{f32(color.R)/255, f32(color.G)/255, f32(color.B)/255, f32(color.A)/255}
		append(vertices, Vertex3D{a-wa, c}, Vertex3D{b-wb, c}, Vertex3D{b+wb, c},
			Vertex3D{a-wa, c}, Vertex3D{b+wb, c}, Vertex3D{a+wa, c})
	}
}

@(private)
toward :: proc(p, eye: foster.Vec3, distance: f32) -> foster.Vec3 {
	d := eye-p
	length := math.sqrt(dot(d, d))
	if !(length > 0) do return p
	return p+d*(min(distance, length*0.5)/length)
}

// ==============================================================================
// 绘制
// ==============================================================================

// 目标深度规则同 transform_draw：先画模型（写深度）再画线框，背面和被挡住的边按 hidden_alpha 淡化；
// 不画模型时深度为清除值，全部边可见。大网格每帧上传 6×边数个顶点，查看完毕应停止调用。
wireframe_draw :: proc(r: ^Renderer3D, target: foster.DrawableTarget, camera: ^world.Camera3D,
	positions: [][3]f32, edges: []meshutil.Edge, transform: world.Matrix4, viewport: foster.Rect,
	scale: f32 = 1, style := DEFAULT_WIREFRAME_STYLE) {
	if !r.ready do return
	wireframe_mesh(&r.vertices, camera, positions, edges, transform, viewport, scale, style)
	draw_vertices(r, target, camera, viewport, style.hidden_alpha)
}
