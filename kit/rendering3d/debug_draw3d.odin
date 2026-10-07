// rendering3d:debug_draw3d —— 立即模式调试线（对位 DragonLib DebugDraw3D）。
//
// 提供 Line/Aabb/Sphere/Frustum/Axis/Grid/Skeleton 的排队绘制，render 后清空。
// GPU 路径走"朝向相机的细四边形"：Foster 管线固定为三角列表（无线拓扑），
// 每段线扩成两个三角形仍用 DebugLine3D 着色器（位置+颜色顶点，拓扑无关），
// 深度测试可选、始终不写深度。厚度是世界单位。
package rendering3d

import "core:math"

import dasset "olib:core/dasset"
import world "olib:kit/world"
import foster "olib:foster"

// 分区：
//   类型 —— Debug_Draw_3D / 线顶点
//   几何生成 —— aabb / sphere / frustum / axis / grid / skeleton
//   顶点展开 —— 线段 -> 朝向相机的四边形
//   GPU 渲染 —— render

// ------------------------------------------------------------------------------
// 类型
// ------------------------------------------------------------------------------

// 调试线顶点：Float3 位置 + Float4 颜色（28B，与 DebugLine3D 着色器一致）。
Debug_Line_Vertex :: struct {
	position: [3]f32,
	color:    [4]f32,
}

DEBUG_LINE_VERTEX_STRIDE :: 28

Debug_Draw_3D :: struct {
	depth_test_enabled: bool, // 遮挡关系（默认开）；始终不写深度
	thickness:          f32, // 线宽（世界单位）

	vertices: [dynamic]Debug_Line_Vertex, // 每线段 2 个端点

	mesh:     foster.Mesh,
	shaders:  Shader3D_Debug_Line_Pair,
	material: foster.Material,
	has_gpu:  bool,
}

DEBUG_DRAW_DEFAULT_THICKNESS :: f32(0.02)

debug_draw_init :: proc(d: ^Debug_Draw_3D, device: ^foster.GraphicsDevice) -> bool {
	d^ = {
		depth_test_enabled = true,
		thickness          = DEBUG_DRAW_DEFAULT_THICKNESS,
	}
	if device == nil { return false }
	if !shader3d_debug_line_init(&d.shaders, device) { return false }

	format := debug_line_format()
	defer foster.vertex_format_dispose(&format)
	foster.mesh_init_with_format(&d.mesh, device, format, .ThirtyTwo, "Debug lines 3d")
	foster.material_init_with_shaders(&d.material, &d.shaders.vertex, &d.shaders.fragment)
	d.has_gpu = true
	return true
}

debug_draw_dispose :: proc(d: ^Debug_Draw_3D) {
	if d.has_gpu {
		foster.ShaderDispose(&d.shaders.vertex)
		foster.ShaderDispose(&d.shaders.fragment)
		foster.VertexBufferDispose(&d.mesh.VertexData)
		foster.IndexBufferDispose(&d.mesh.IndexData)
	}
	delete(d.vertices)
	d^ = {}
}

debug_draw_line_count :: proc(d: ^Debug_Draw_3D) -> int {
	return len(d.vertices) / 2
}

debug_draw_clear :: proc(d: ^Debug_Draw_3D) {
	clear(&d.vertices)
}

// ------------------------------------------------------------------------------
// 几何生成
// ------------------------------------------------------------------------------

debug_draw_line :: proc(d: ^Debug_Draw_3D, a, b: [3]f32, color: [4]f32) {
	append(&d.vertices, Debug_Line_Vertex{position = a, color = color})
	append(&d.vertices, Debug_Line_Vertex{position = b, color = color})
}

debug_draw_aabb :: proc(d: ^Debug_Draw_3D, bounds: dasset.Dasset_Bounds, color: [4]f32) {
	corners := aabb_corners(bounds)
	debug_draw_box_edges(d, corners, color)
}

debug_draw_sphere :: proc(d: ^Debug_Draw_3D, center: [3]f32, radius: f32, color: [4]f32, segments := 32) {
	if radius < 0 || segments < 3 { return }
	tau := f32(math.TAU)
	for plane in 0..<3 {
		for i in 0..<segments {
			a := f32(i) * tau / f32(segments)
			b := f32(i + 1) * tau / f32(segments)
			pa := sphere_point(plane, a)
			pb := sphere_point(plane, b)
			debug_draw_line(
				d,
				{center[0] + pa[0]*radius, center[1] + pa[1]*radius, center[2] + pa[2]*radius},
				{center[0] + pb[0]*radius, center[1] + pb[1]*radius, center[2] + pb[2]*radius},
				color,
			)
		}
	}
}

// 视锥线框：由 ViewProjection 逆变换回世界空间的 8 角点。
debug_draw_frustum :: proc(d: ^Debug_Draw_3D, view_projection: world.Matrix4, color: [4]f32) {
	inverse, ok := world.matrix4_inverse(view_projection)
	if !ok { return }

	corners: [8][3]f32
	for i in 0..<8 {
		h := world.matrix4_transform_vec4(inverse, world.Vec4{
			(i & 1) == 0 ? -1 : 1,
			(i & 2) == 0 ? -1 : 1,
			(i & 4) == 0 ? 0 : 1,
			1,
		})
		if math.abs(h[3]) < 1e-8 { return }
		corners[i] = {h[0] / h[3], h[1] / h[3], h[2] / h[3]}
	}
	debug_draw_box_edges(d, corners, color)
}

// 坐标轴：X 红 / Y 绿 / Z 蓝（按 world 变换）。
debug_draw_axis :: proc(d: ^Debug_Draw_3D, world_matrix: world.Matrix4, length: f32 = 1) {
	origin_h := world.matrix4_transform_vec4(world_matrix, world.Vec4{0, 0, 0, 1})
	origin := [3]f32{origin_h[0], origin_h[1], origin_h[2]}
	for axis in 0..<3 {
		dir := [3]f32{axis == 0 ? 1 : 0, axis == 1 ? 1 : 0, axis == 2 ? 1 : 0}
		tip := [3]f32{
			origin[0] + dir[0] * length,
			origin[1] + dir[1] * length,
			origin[2] + dir[2] * length,
		}
		color := axis == 0 ? ([4]f32{1, 0.2, 0.2, 1}) : axis == 1 ? ([4]f32{0.2, 1, 0.2, 1}) : [4]f32{0.2, 0.4, 1, 1}
		debug_draw_line(d, origin, tip, color)
	}
}

// XZ 平面网格。
debug_draw_grid :: proc(d: ^Debug_Draw_3D, half_lines: int, spacing: f32, color: [4]f32) {
	if half_lines < 0 || spacing <= 0 { return }
	extent := f32(half_lines) * spacing
	for i := -half_lines; i <= half_lines; i += 1 {
		t := f32(i) * spacing
		debug_draw_line(d, {t, 0, -extent}, {t, 0, extent}, color)
		debug_draw_line(d, {-extent, 0, t}, {extent, 0, t}, color)
	}
}

// 骨架线：is_palette=true 时矩阵是 palette（需经 inverse IBM 重建 global）。
debug_draw_skeleton :: proc(
	d:        ^Debug_Draw_3D,
	skeleton: ^dasset.Dasset_Skeleton,
	matrices: []world.Matrix4,
	world_matrix: world.Matrix4,
	color:    [4]f32,
	is_palette := true,
) {
	count := min(len(skeleton.joints), len(matrices))
	positions := make([][3]f32, count)
	defer delete(positions)

	for i in 0..<count {
		global := matrices[i]
		if is_palette {
			bind, ok := world.matrix4_inverse(world.matrix4_from_row_major(skeleton.joints[i].inverse_bind_matrix))
			if ok {
				global = world.matrix4_multiply(bind, global)
			}
		}
		h := world.matrix4_transform_vec4(world.matrix4_multiply(global, world_matrix), world.Vec4{0, 0, 0, 1})
		if math.abs(h[3]) < 1e-8 {
			positions[i] = {0, 0, 0}
			continue
		}
		positions[i] = {h[0] / h[3], h[1] / h[3], h[2] / h[3]}
	}
	for i in 0..<count {
		parent := skeleton.joints[i].parent_index
		if parent >= 0 && int(parent) < count {
			debug_draw_line(d, positions[parent], positions[i], color)
		}
	}
}

// ------------------------------------------------------------------------------
// 顶点展开 —— 线段 -> 朝向相机的四边形（两个三角形）
// ------------------------------------------------------------------------------

// 把已排队的线段展开为四边形顶点（不改变 d.vertices；输出追加到 out）。
// 每段 4 顶点 6 索引的扇形展开；侧面向量 = normalize(cross(线方向, 视线)) * 半厚。
debug_draw_expand :: proc(d: ^Debug_Draw_3D, camera_position: [3]f32, out: ^[dynamic]Debug_Line_Vertex) {
	half := d.thickness * 0.5
	for i in 0..<len(d.vertices) / 2 {
		a := d.vertices[i*2]
		b := d.vertices[i*2 + 1]

		// 线方向与视线叉积得侧面方向
		dir := v3_sub(b.position, a.position)
		mid := [3]f32{
			(a.position[0] + b.position[0]) * 0.5,
			(a.position[1] + b.position[1]) * 0.5,
			(a.position[2] + b.position[2]) * 0.5,
		}
		to_cam := v3_sub(camera_position, mid)
		side := v3_cross(dir, to_cam)
		length2 := dot3(side, side)
		if length2 > 1e-12 {
			inv := 1.0 / math.sqrt(length2)
			side = [3]f32{side[0]*inv*half, side[1]*inv*half, side[2]*inv*half}
		} else {
			// 线与视线平行：任选一个正交向量
			side = [3]f32{half, 0, 0}
		}

		a0 := v3_sub(a.position, side)
		a1 := v3_add(a.position, side)
		b0 := v3_sub(b.position, side)
		b1 := v3_add(b.position, side)

		// 两个三角形：a0 b0 b1 / a0 b1 a1
		append(out, Debug_Line_Vertex{position = a0, color = a.color})
		append(out, Debug_Line_Vertex{position = b0, color = b.color})
		append(out, Debug_Line_Vertex{position = b1, color = b.color})
		append(out, Debug_Line_Vertex{position = a0, color = a.color})
		append(out, Debug_Line_Vertex{position = b1, color = b.color})
		append(out, Debug_Line_Vertex{position = a1, color = a.color})
	}
}

// ------------------------------------------------------------------------------
// GPU 渲染
// ------------------------------------------------------------------------------

// 上传展开后的四边形并发射（渲染后清空队列）。无 GPU 初始化时只清空。
debug_draw_render :: proc(d: ^Debug_Draw_3D, target: foster.DrawableTarget, camera: ^world.Camera3D) {
	defer debug_draw_clear(d)
	if !d.has_gpu || len(d.vertices) == 0 { return }

	world.camera3d_set_viewport(camera, target.WidthInPixels, target.HeightInPixels)

	expanded: [dynamic]Debug_Line_Vertex
	defer delete(expanded)
	debug_draw_expand(d, camera.position, &expanded)
	if len(expanded) == 0 { return }

	foster.mesh_set_vertex_count(&d.mesh, len(expanded))
	foster.mesh_set_vertices(&d.mesh, raw_data(expanded), len(expanded))

	vp_buf: [64]u8
	if pack_shadow_matrix_block(vp_buf[:], world.camera3d_view_projection(camera)) {
		foster.MaterialStageSetUniformBuffer(&d.material.Vertex, vp_buf[:], 0)
	}

	command: foster.DrawCommand
	foster.DrawCommandFromMesh(&command, target, &d.mesh, &d.material)
	command.DepthTestEnabled = d.depth_test_enabled
	command.DepthWriteEnabled = false
	command.DepthCompare = .LessOrEqual
	command.CullMode = .None
	command.BlendMode = foster.BlendMode{
		ColorOperation   = .Add,
		ColorSource      = .SrcAlpha,
		ColorDestination = .OneMinusSrcAlpha,
		AlphaOperation   = .Add,
		AlphaSource      = .One,
		AlphaDestination = .OneMinusSrcAlpha,
	}
	foster.GraphicsDeviceDraw(d.mesh.GraphicsDevice, &command)
	foster.DrawCommandDispose(&command)
}

// ------------------------------------------------------------------------------
// 内部
// ------------------------------------------------------------------------------

// 调试线顶点格式（Float3 + Float4，28B）。
debug_line_format :: proc() -> foster.VertexFormat {
	return foster.vertex_format_make(
		[]foster.VertexElement{
			{0, .Float3, false},
			{1, .Float4, false},
		},
		DEBUG_LINE_VERTEX_STRIDE,
	)
}

@(private)
aabb_corners :: proc(bounds: dasset.Dasset_Bounds) -> [8][3]f32 {
	corners: [8][3]f32
	for i in 0..<8 {
		corners[i] = [3]f32{
			(i & 1) == 0 ? bounds.min[0] : bounds.max[0],
			(i & 2) == 0 ? bounds.min[1] : bounds.max[1],
			(i & 4) == 0 ? bounds.min[2] : bounds.max[2],
		}
	}
	return corners
}

// 8 角点的 12 条棱：bit 位相邻连接。
@(private)
debug_draw_box_edges :: proc(d: ^Debug_Draw_3D, corners: [8][3]f32, color: [4]f32) {
	for i in 0..<8 {
		bits := [3]u32{1, 2, 4}
	for bit in bits {
			if i & int(bit) == 0 {
				debug_draw_line(d, corners[i], corners[i | int(bit)], color)
			}
		}
	}
}

@(private)
sphere_point :: proc(plane: int, angle: f32) -> [3]f32 {
	switch plane {
	case 0: return {math.cos(angle), math.sin(angle), 0}
	case 1: return {0, math.cos(angle), math.sin(angle)}
	case:   return {math.sin(angle), 0, math.cos(angle)}
	}
}

@(private)
v3_sub :: proc(a, b: [3]f32) -> [3]f32 {
	return {a[0] - b[0], a[1] - b[1], a[2] - b[2]}
}

@(private)
v3_add :: proc(a, b: [3]f32) -> [3]f32 {
	return {a[0] + b[0], a[1] + b[1], a[2] + b[2]}
}

@(private)
v3_cross :: proc(a, b: [3]f32) -> [3]f32 {
	return {
		a[1]*b[2] - a[2]*b[1],
		a[2]*b[0] - a[0]*b[2],
		a[0]*b[1] - a[1]*b[0],
	}
}

@(private)
dot3 :: proc(a, b: [3]f32) -> f32 {
	return a[0]*b[0] + a[1]*b[1] + a[2]*b[2]
}
