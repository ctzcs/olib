// rendering3d 包单元测试（CPU：队列排序 + 格式步长 + 打包 + 调试线几何 + LOD）。
#+test
package rendering3d

import "core:math"
import "core:math/linalg"
import "core:testing"

import dasset "olib:core/dasset"
import world "olib:kit/world"
import foster "olib:foster"
import mat "olib:kit/rendering/material"

@(test)
mesh_format_strides :: proc(t: ^testing.T) {
	static := mesh_static_format()
	defer foster.VertexFormatDispose(&static)
	testing.expect(t, static.Stride == 48 && len(static.Elements) == 4)

	skin := mesh_skin_format()
	defer foster.VertexFormatDispose(&skin)
	testing.expect(t, skin.Stride == 68 && len(skin.Elements) == 6)
}

@(test)
queue_sort_buckets_and_depth :: proc(t: ^testing.T) {
	q: Render_Queue(int)
	defer queue_dispose(&q)

	// 提交乱序：透明(5)、不透明(10)、透明(1)、不透明(2)；payload 记提交序
	queue_submit(&q, 0, 5, true)
	queue_submit(&q, 1, 10, false)
	queue_submit(&q, 2, 1, true)
	queue_submit(&q, 3, 2, false)

	queue_sort(&q)

	// 不透明在前（前到后 2,10），透明在后（后到前 5,1）
	testing.expect(t, len(q.items) == 4)
	order := [4]int{q.items[0].payload, q.items[1].payload, q.items[2].payload, q.items[3].payload}
	testing.expectf(t, order == [4]int{3, 1, 0, 2}, "排序结果 %v", order)
	testing.expect(t, !q.items[0].transparent && q.items[3].transparent)

	queue_clear(&q)
	testing.expect(t, len(q.items) == 0)
	queue_submit(&q, 0, 20, false, 0)
	queue_submit(&q, 1, 4, false, 1)
	queue_submit(&q, 2, 2, false, 0)
	queue_submit(&q, 3, 8, true, 1)
	queue_submit(&q, 4, 12, true, 0)
	queue_submit(&q, 5, 12, true, 1)
	queue_sort(&q, grouped = true)
	expected := [6]int{2, 0, 1, 4, 5, 3}
	for item, i in q.items {
		testing.expect(t, item.payload == expected[i])
	}
}

@(test)
queue_view_depth_uses_object_position :: proc(t: ^testing.T) {
	camera: world.Camera3D
	world.camera3d_init(&camera, 1280, 720)
	world.camera3d_set_position(&camera, {0, 0, 10})
	world.camera3d_set_target(&camera, {0, 0, 0})

	near := queue_view_depth(&camera, world.matrix4_translation(0, 0, 5))
	far := queue_view_depth(&camera, world.matrix4_translation(0, 0, -5))
	testing.expectf(t, math.abs(near - 5) < 1e-4, "近处物体距离 5: %v", near)
	testing.expectf(t, math.abs(far - 15) < 1e-4, "远处物体距离 15: %v", far)
}

// ---------------------------------------------------------------------------
// 着色器管线 —— uniform 打包 / 驱动分发 / 内嵌 blob
// ---------------------------------------------------------------------------

@(test)
vertex_matrix_block_pack_layout :: proc(t: ^testing.T) {
	buf := make([]u8, 1024)
	defer delete(buf)

	// WVP 与 World 各占 64B，按 Matrix4 的 c0..c3 顺序写入
	wvp := world.matrix4_translation(1, 2, 3)
	w := world.matrix4_scaling(4, 5, 6)
	testing.expect(t, pack_vertex_matrix_block(buf, wvp, w))
	read_back := world.Matrix4{
		c0 = read_vec4(buf, 0),
		c1 = read_vec4(buf, 16),
		c2 = read_vec4(buf, 32),
		c3 = read_vec4(buf, 48),
	}
	testing.expect(t, read_back == (wvp))
	world_back := world.Matrix4{
		c0 = read_vec4(buf, 64),
		c1 = read_vec4(buf, 80),
		c2 = read_vec4(buf, 96),
		c3 = read_vec4(buf, 112),
	}
	testing.expect(t, world_back == (w))

	// 越界拒绝
	testing.expect(t, !pack_vertex_matrix_block(buf[:64], wvp, w))
}

@(private)
read_vec4 :: proc(buf: []u8, offset: int) -> [4]f32 {
	v: [4]f32
	for i in 0..<4 {
		bits := u32(buf[offset + i*4]) | u32(buf[offset + i*4 + 1]) << 8 |
		        u32(buf[offset + i*4 + 2]) << 16 | u32(buf[offset + i*4 + 3]) << 24
		v[i] = transmute(f32)bits
	}
	return v
}

@(test)
joint_palette_fills_identity_beyond_count :: proc(t: ^testing.T) {
	buf0 := make([]u8, 64 * 64)
	defer delete(buf0)
	buf1 := make([]u8, 64 * 64)
	defer delete(buf1)

	palette := make([]world.Matrix4, 2)
	defer delete(palette)
	palette[1] = world.matrix4_translation(9, 9, 9)

	testing.expect(t, pack_joint_palette(buf0, buf1, palette))
	// 0、1 号来自 palette；2..63 与第二块全部是单位阵
	m1 := world.Matrix4{c0 = read_vec4(buf0, 64), c1 = read_vec4(buf0, 80), c2 = read_vec4(buf0, 96), c3 = read_vec4(buf0, 112)}
	testing.expect(t, m1 == (world.matrix4_translation(9, 9, 9)))
	id_at := proc(buf: []u8, index: int) -> bool {
		m := world.Matrix4{c0 = read_vec4(buf, index*64), c1 = read_vec4(buf, index*64 + 16), c2 = read_vec4(buf, index*64 + 32), c3 = read_vec4(buf, index*64 + 48)}
		return m == (world.MATRIX4_IDENTITY)
	}
	testing.expect(t, id_at(buf0, 2) && id_at(buf0, 63) && id_at(buf1, 0) && id_at(buf1, 63))
}

@(test)
shader_blobs_embedded :: proc(t: ^testing.T) {
	// 内嵌 blob 编译期存在且非空（#load 保证，运行时兜底断言）
	testing.expect(t, len(debugline_vertex_spv) > 4 && len(debugline_vertex_dxil) > 4)
	// SPIR-V 魔数 0x07230203（小端 03 02 23 07）
	spv := debugline_vertex_spv
	testing.expect(t, spv[0] == 0x03 && spv[1] == 0x02 && spv[2] == 0x23 && spv[3] == 0x07)
	// DXIL 容器魔数 "DXBC"
	dxil := debugline_vertex_dxil
	testing.expect(t, dxil[0] == 'D' && dxil[1] == 'X' && dxil[2] == 'B' && dxil[3] == 'C')
	// MSL 是源码，以 #include 开头
	testing.expect(t, len(debugline_vertex_msl) > 0 && debugline_vertex_msl[0] == '#')
}

// ---------------------------------------------------------------------------
// DebugDraw3D —— 几何生成计数与四边形展开
// ---------------------------------------------------------------------------

@(test)
debug_draw_geometry_counts :: proc(t: ^testing.T) {
	d: Debug_Draw_3D
	defer debug_draw_dispose(&d) // 无 GPU：只清 vertices

	// 盒：12 条棱 = 24 端点
	debug_draw_aabb(&d, {min = {-1, -1, -1}, max = {1, 1, 1}}, {1, 1, 1, 1})
	testing.expect(t, debug_draw_line_count(&d) == 12)
	debug_draw_clear(&d)

	// 球：3 平面 × segments 条
	debug_draw_sphere(&d, {0, 0, 0}, 2, {1, 1, 1, 1}, segments = 8)
	testing.expect(t, debug_draw_line_count(&d) == 3 * 8)
	debug_draw_clear(&d)

	// 网格：half=2 -> 5 条 × 2 方向 = 10 条
	debug_draw_grid(&d, 2, 1, {0.5, 0.5, 0.5, 1})
	testing.expect(t, debug_draw_line_count(&d) == 10)
	debug_draw_clear(&d)

	// 视锥：默认相机（可逆矩阵）12 条棱
	world_test_camera: world.Camera3D
	world.camera3d_init(&world_test_camera, 1280, 720)
	debug_draw_frustum(&d, world.camera3d_view_projection(&world_test_camera), {1, 1, 1, 1})
	testing.expect(t, debug_draw_line_count(&d) == 12)
}

@(test)
debug_draw_expand_builds_quads :: proc(t: ^testing.T) {
	d: Debug_Draw_3D
	defer debug_draw_dispose(&d)
	d.thickness = 0.1

	debug_draw_line(&d, {0, 0, 0}, {1, 0, 0}, {1, 1, 1, 1}) // 沿 X
	testing.expect(t, debug_draw_line_count(&d) == 1)

	expanded: [dynamic]Debug_Line_Vertex
	defer delete(expanded)
	debug_draw_expand(&d, {0, 5, 0}, &expanded) // 相机在 +Y 上看 X 线

	// 1 条线 -> 6 顶点（两个三角形）
	testing.expect(t, len(expanded) == 6)
	// 侧向在 Z（cross(X, toCam) = Z），半厚 0.05：X 线在 XZ 平面内展开
	a0 := expanded[0].position
	a1 := expanded[5].position
	testing.expectf(t, math.abs(a0[0]) < 1e-6 && math.abs(a0[1]) < 1e-6, "a0 无 X/Y 偏移: %v", a0)
	testing.expectf(t, math.abs(math.abs(a0[2] - a1[2]) - 0.1) < 1e-5, "厚度 0.1: %v", math.abs(a0[2] - a1[2]))
	// 颜色透传
	testing.expect(t, expanded[0].color == ([4]f32{1, 1, 1, 1}))
}

// ---------------------------------------------------------------------------
// LOD 选择
// ---------------------------------------------------------------------------

@(test)
lod_selector_thresholds_and_hysteresis :: proc(t: ^testing.T) {
	s: Lod_Selector
	testing.expect(t, lod_selector_init(&s, []f32{0.5, 0.2, 0}))
	defer lod_selector_dispose(&s)
	testing.expect(t, lod_selector_level_count(&s) == 3)

	// 非法阈值拒绝
	bad: Lod_Selector
	testing.expect(t, !lod_selector_init(&bad, []f32{0.5, 0.2})) // 末项非 0
	testing.expect(t, !lod_selector_init(&bad, []f32{0.2, 0.5, 0})) // 非降序
	testing.expect(t, !lod_selector_init(&bad, []f32{}))

	// 全量初选
	testing.expect(t, lod_selector_select(&s, 0.6) == 0)
	testing.expect(t, lod_selector_select(&s, 0.3) == 1)
	testing.expect(t, lod_selector_select(&s, 0.05) == 2)

	// 滞回：0.2 边界附近（0.19 不降级、0.17 降级，滞回 0.1）
	s.current_level = 1
	testing.expect(t, lod_selector_select(&s, 0.19) == 1) // 0.19 >= 0.2*(1-0.1)=0.18 保持
	testing.expect(t, lod_selector_select(&s, 0.17) == 2) // 0.17 < 0.18 降级

	s.current_level = 1
	testing.expect(t, lod_selector_select(&s, 0.53) == 1) // 0.53 < 0.5*1.1=0.55 -> 保持 1
	testing.expect(t, lod_selector_select(&s, 0.56) == 0) // 0.56 >= 0.55 -> 升级 0
}

@(test)
lod_screen_height_estimates :: proc(t: ^testing.T) {
	camera: world.Camera3D
	world.camera3d_init(&camera, 1280, 720)
	world.camera3d_set_position(&camera, {0, 0, 10})

	// 前方 1 单位立方体（中心距相机约 10）
	h := lod_screen_height(&camera, {min = {-0.5, -0.5, -0.5}, max = {0.5, 0.5, -1.5}})
	testing.expectf(t, h > 0.01 && h < 10, "合理的屏幕高度: %v", h)

	// 相机在盒内 -> 无穷大
	inside := lod_screen_height(&camera, {min = {-20, -20, -20}, max = {20, 20, 20}})
	testing.expect(t, inside == f32(math.INF_F32))
}

@(test)
instance_value_set_writes_flat_slots :: proc(t: ^testing.T) {
	values := make([][4]f32, 3*2, context.temp_allocator) // 3 个实例，每个 2 个槽
	testing.expect(t, mat.instance_array_set(values, 2, 2, {1, true}, {0.5, 0, 0, 0}))
	testing.expect_value(t, values[5], [4]f32{0.5, 0, 0, 0}) // 实例 2 的槽 1
	testing.expect(t, !mat.instance_array_set(values, 2, 0, {}, {1, 0, 0, 0})) // 句柄无效
	testing.expect(t, !mat.instance_array_set(values, 2, 0, {2, true}, {1, 0, 0, 0})) // 槽位越界
	testing.expect(t, !mat.instance_array_set(values, 2, 3, {0, true}, {1, 0, 0, 0})) // 实例越界
}

// 变换后的包围球：平移时半径不变；旋转后再非均匀缩放时，只变换 min/max 两个角会低估半径。
@(test)
lod_world_sphere_is_conservative :: proc(t: ^testing.T) {
	bounds := dasset.Dasset_Bounds{min = {-2, -0.5, -0.5}, max = {2, 0.5, 0.5}}
	center, radius, ok := lod_world_sphere(bounds, world.matrix4_translation(1, 2, 3))
	testing.expect(t, ok)
	testing.expect(t, linalg.length(center - [3]f32{1, 2, 3}) < 1e-5)
	testing.expect(t, math.abs(radius - linalg.length(bounds.max - bounds.min)*0.5) < 1e-5)

	// 绕 Z 转 ±45° 后沿 Y 拉长 3 倍：盒的轴不再正交，两条对角线长度不同；
	// 只变换 min/max 两个角在其中一个方向上取到短对角线，必然低估。
	underestimated := false
	for sign in ([2]f32{1, -1}) {
		half := sign * math.PI / 8
		m := world.matrix4_multiply(world.matrix4_from_quaternion({0, 0, math.sin(half), math.cos(half)}), world.matrix4_scaling(1, 3, 1))
		center, radius, ok = lod_world_sphere(bounds, m)
		testing.expect(t, ok)
		for corner in aabb_corners(bounds) {
			p, _ := world.matrix4_transform_point(m, corner)
			testing.expect(t, linalg.length(p - center) <= radius + 1e-4)
		}
		two_corners := linalg.length(world.matrix4_transform_vector(m, bounds.max - bounds.min)) * 0.5
		testing.expect(t, radius >= two_corners - 1e-4)
		underestimated ||= two_corners < radius - 0.5
	}
	testing.expect(t, underestimated)
}

// 实例缓冲的布局约定：每实例 世界矩阵 + tint + 字段，没有字段时 Model_Item 与缓冲同一布局可直接上传。
@(test)
instance_buffer_layout_and_guards :: proc(t: ^testing.T) {
	testing.expect_value(t, model_stride(0), 80)
	testing.expect_value(t, model_stride(2), 112)
	testing.expect_value(t, size_of(Model_Item), model_stride(0))
	// 槽数取自材质：没有材质、不是 instanced 效果、各参数组字段数不一致、容量为 0 都拒绝（不碰 GPU）。
	device: foster.GraphicsDevice
	library := mat.Material_Library{device = &device}
	fields := []mat.Field{{id = "hue", instance = true}, {id = "glow", instance = true}}
	plain := mat.Material_Effect{schemas = []mat.Schema{{fields = fields}}}
	instanced := mat.Material_Effect{desc = {instanced = true}, schemas = []mat.Schema{{fields = fields}, {fields = fields[:1]}}}
	buffer: Model_Buffer
	testing.expect(t, !model_buffer_init(&buffer, nil, 10))
	plain_material := mat.Material{owner = &library, effect = &plain}
	testing.expect(t, !model_buffer_init(&buffer, &plain_material, 10))
	material := mat.Material{owner = &library, effect = &instanced}
	testing.expect(t, !model_buffer_init(&buffer, &material, 10))
	instanced.schemas = instanced.schemas[:1]
	testing.expect(t, !model_buffer_init(&buffer, &material, 0))
	testing.expect_value(t, buffer.capacity, 0)
	// 未创建的缓冲拒绝上传；越界被拒绝。
	instances := []Model_Item{{}, {}}
	testing.expect(t, !model_buffer_upload(&buffer, instances))
	buffer.capacity = 1
	testing.expect(t, !model_buffer_upload(&buffer, instances))
	testing.expect(t, !model_buffer_upload(&buffer, instances[:1], 1))
	buffer.capacity, buffer.slots = 2, 2
	testing.expect(t, !model_buffer_upload(&buffer, instances, 0, make([][4]f32, 3, context.temp_allocator))) // 应为 2×2
}

// 绘制入口的错误码：都在提交 Draw 之前返回，不需要真实 GPU。
@(test)
model_draw_reports_errors_before_gpu :: proc(t: ^testing.T) {
	device: foster.GraphicsDevice
	library := mat.Material_Library{device = &device}
	effect := mat.Material_Effect{desc = {instanced = true}}
	material := mat.Material{owner = &library, effect = &effect}
	view: View
	buffer := Model_Buffer{capacity = 4}
	testing.expect_value(t, model_draw(nil, nil, world.MATRIX4_IDENTITY, view), mat.Draw_Error.Missing_Material)
	testing.expect_value(t, model_draw_buffer(nil, nil, &buffer, 1, view, "outline"), mat.Draw_Error.Missing_Material)
	testing.expect_value(t, model_draw(&material, nil, world.MATRIX4_IDENTITY, view), mat.Draw_Error.Missing_Mesh)
	testing.expect_value(t, model_draw_buffer(&material, nil, nil, 1, view), mat.Draw_Error.Instance_Buffer_Required)
	testing.expect_value(t, model_draw_buffer(&material, nil, &Model_Buffer{}, 1, view), mat.Draw_Error.Instance_Buffer_Required)
	// 蒙皮网格（68B 顶点）不在材质路径内，明确报错
	skinned: foster.Mesh
	skinned.VertexData.Format.Stride = dasset.DASSET_VERTEX_STRIDE_SKIN
	testing.expect_value(t, model_draw(&material, &skinned, world.MATRIX4_IDENTITY, view), mat.Draw_Error.Unsupported_Mesh)
	testing.expect_value(t, model_draw_buffer(&material, &skinned, &buffer, 1, view), mat.Draw_Error.Unsupported_Mesh)
}
