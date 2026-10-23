// rendering3d 包单元测试（CPU：队列排序 + 格式步长 + 打包 + 调试线几何 + LOD）。
#+test
package rendering3d

import "core:math"
import "core:math/linalg"
import "core:testing"

import dasset "olib:core/dasset"
import sh "olib:kit/rendering/shader"
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

	// 两组最近深度相同（都是 3）时按 group 键排列，组内仍前到后；组深度写进了各项。
	queue_clear(&q)
	queue_submit(&q, 0, 9, false, 7)
	queue_submit(&q, 1, 3, false, 7)
	queue_submit(&q, 2, 5, false, 2)
	queue_submit(&q, 3, 3, false, 2)
	queue_submit(&q, 4, 1, false, 9) // 最近深度 1 的组排最前
	queue_sort(&q, grouped = true)
	tied := [5]int{4, 3, 2, 1, 0}
	for item, i in q.items do testing.expectf(t, item.payload == tied[i], "第 %d 项是 %d", i, item.payload)
	testing.expect_value(t, q.items[1].group_depth, f32(3))
	testing.expect_value(t, q.items[0].group_depth, f32(1))
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
	testing.expect(t, mat.instance_array_set(values, 2, 2, {1, true}, 0.5))
	testing.expect_value(t, values[5], [4]f32{0.5, 0, 0, 0}) // 实例 2 的槽 1
	testing.expect(t, mat.instance_array_set(values, 2, 1, {0, true}, 1, 2, 3)) // Vector3 只写三个分量
	testing.expect_value(t, values[2], [4]f32{1, 2, 3, 0})
	testing.expect(t, !mat.instance_array_set(values, 2, 0, {}, 1)) // 句柄无效
	testing.expect(t, !mat.instance_array_set(values, 2, 0, {2, true}, 1)) // 槽位越界
	testing.expect(t, !mat.instance_array_set(values, 2, 3, {0, true}, 1)) // 实例越界
	testing.expect(t, !mat.instance_array_set(values, 2, 0, {0, true}, 1, 2, 3, 4, 5)) // 超过 4 个分量
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
render3d_views_preserve_records :: proc(t: ^testing.T) {
	device: foster.GraphicsDevice
	library := mat.Material_Library{device = &device}
	r := Render3D{library = &library}
	defer dispose(&r)
	program: foster.Shader
	program.Resource = cast(type_of(program.Resource))uintptr(1) // 仅验证绑定；不调用 GPU
	fragment := program
	fragment.Stage = .Fragment
	gpu: foster.Material
	foster.MaterialInitWithShaders(&gpu, &program, &fragment)
	defer foster.MaterialDispose(&gpu)
	shader := mat.Material_Shader{desc = {passes = []sh.Pass_Desc{
		{id = "body", params = "Body", draw = .Model},
		{id = "off", params = "Body", draw = .Model, disabled = true}}}}
	material := mat.Material{owner = &library, shader = &shader,
		bindings = []mat.Material_Binding{{schema = {name = "Body"}, material = &gpu}}}
	mesh := foster.Mesh{GraphicsDevice = &device}
	mesh.VertexData.Format.Stride = dasset.DASSET_VERTEX_STRIDE_STATIC
	bounds := dasset.Dasset_Bounds{min = {-0.1, -0.1, -0.1}, max = {0.1, 0.1, 0.1}}
	positions := []f32{0, 4}
	for x in positions {
		testing.expect_value(t, model(&r, &mesh, &material,
			world.matrix4_translation(x, 0, 0.5), &bounds), mat.Draw_Error.None)
	}
	bounds.max = {} // 调用者改原数据不影响记录
	view := View{view_projection = world.MATRIX4_IDENTITY, view_matrix = world.MATRIX4_IDENTITY}
	testing.expect_value(t, render3d_prepare(&r, view, "body"), mat.Draw_Error.None)
	testing.expect_value(t, len(r.queue.items), 1)
	testing.expect_value(t, r.queue.items[0].payload, 0)
	view.view_projection = world.matrix4_translation(-4, 0, 0)
	testing.expect_value(t, render3d_prepare(&r, view, "body"), mat.Draw_Error.None)
	testing.expect_value(t, len(r.queue.items), 1)
	testing.expect_value(t, r.queue.items[0].payload, 1)
	testing.expect_value(t, len(r.records), 2)
	testing.expect_value(t, render3d_prepare(&r, view, "off"), mat.Draw_Error.None)
	testing.expect_value(t, len(r.queue.items), 0)
	testing.expect_value(t, render3d_prepare(&r, view, "typo"), mat.Draw_Error.Unknown_Pass)
	testing.expect_value(t, submit(&r, view), mat.Draw_Error.Invalid_Target)
	// 零视矩阵不当成单位矩阵：有记录时明确报错，记录保留。
	missing := view
	missing.target.WidthInPixels, missing.target.HeightInPixels = 4, 4
	missing.view_matrix = {}
	testing.expect_value(t, submit(&r, missing), mat.Draw_Error.Missing_View_Matrix)
	testing.expect_value(t, len(r.records), 2)
	// 视图块超长同样在发 Draw 之前报错，记录保留。
	oversized := missing
	oversized.view_matrix = world.MATRIX4_IDENTITY
	oversized.globals = make([]u8, mat.VIEW_GLOBALS_SIZE + 16, context.temp_allocator)
	testing.expect_value(t, submit(&r, oversized), mat.Draw_Error.View_Globals_Too_Large)
	testing.expect_value(t, len(r.records), 2)
	clear(&r)
	testing.expect_value(t, len(r.records), 0)
	testing.expect_value(t, submit(&r, view, "body"), mat.Draw_Error.None)
}

@(test)
instance_buffer_layout_and_guards :: proc(t: ^testing.T) {
	testing.expect_value(t, model_stride(0), 80)
	testing.expect_value(t, model_stride(2), 112)
	testing.expect_value(t, size_of(Model_Item), model_stride(0))
	// 槽数取自材质：没有材质、不是 instanced Shader、各参数组字段数不一致、容量为 0 都拒绝（不碰 GPU）。
	device: foster.GraphicsDevice
	library := mat.Material_Library{device = &device}
	fields := []sh.Field{{id = "hue", instance = true}, {id = "glow", instance = true}}
	plain := mat.Material_Shader{schemas = []sh.Schema{{fields = fields}}}
	instanced := mat.Material_Shader{desc = {instanced = true}, schemas = []sh.Schema{{fields = fields}, {fields = fields[:1]}}}
	buffer: Model_Buffer
	testing.expect(t, model_buffer_init(&buffer, nil, 10) != "")
	plain_material := mat.Material{owner = &library, shader = &plain}
	testing.expect(t, model_buffer_init(&buffer, &plain_material, 10) != "")
	material := mat.Material{owner = &library, shader = &instanced}
	testing.expect(t, model_buffer_init(&buffer, &material, 10) != "")
	instanced.schemas = instanced.schemas[:1]
	testing.expect(t, model_buffer_init(&buffer, &material, 0) != "")
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

// 同一组记录验证：实例数值不拆批、参数快照拆批、透明顺序屏障、多 Pass 独立覆盖。
@(test)
render3d_instances_snapshots_and_order :: proc(t: ^testing.T) {
	device: foster.GraphicsDevice
	library := mat.Material_Library{device = &device}
	r := Render3D{library = &library}
	defer dispose(&r)
	vertex: foster.Shader
	vertex.Resource = cast(type_of(vertex.Resource))uintptr(1)
	fragment := vertex
	fragment.Stage = .Fragment
	gpu: foster.Material
	foster.MaterialInitWithShaders(&gpu, &vertex, &fragment)
	defer foster.MaterialDispose(&gpu)
	schema := sh.Schema{name = "Body", fields = []sh.Field{
		{id = "hue", kind = .Scalar, instance = true, maximum = 1},
		{id = "gain", kind = .Scalar, maximum = 1},
		{id = "albedo", kind = .Texture}}}
	shader := mat.Material_Shader{schemas = []sh.Schema{schema}, desc = {
		instanced = true, passes = []sh.Pass_Desc{
			{id = "body", params = "Body", draw = .Model},
			{id = "shadow", params = "Body", draw = .Model,
				values = []sh.Pass_Value{{field = "hue", number = {0.9, 0, 0, 0}}}},
			{id = "glass", params = "Body", draw = .Model, state = {blend = .Alpha}}}}}
	texture: foster.Texture
	texture.Resource = cast(type_of(texture.Resource))uintptr(1)
	other_texture := texture
	values := []sh.Value{{number = {0.2, 0, 0, 0}}, {number = {0.5, 0, 0, 0}}, {}}
	samplers := []foster.BoundSampler{{Texture = &texture}}
	m := mat.Material{owner = &library, shader = &shader,
		bindings = []mat.Material_Binding{{schema, values, &gpu, samplers}}}
	mesh := foster.Mesh{GraphicsDevice = &device}
	mesh.VertexData.Format.Stride = dasset.DASSET_VERTEX_STRIDE_STATIC
	other_mesh := mesh
	flat := [][4]f32{{0.4, 0, 0, 0}, {0.6, 0, 0, 0}}
	items := []Model_Item{{world.matrix4_translation(0, 0, -5), {1, 1, 1, 1}},
		{world.matrix4_translation(0, 0, -4), {1, 1, 1, 1}}}
	testing.expect_value(t, models(&r, &mesh, &m, items, values = flat), mat.Draw_Error.None)
	testing.expect_value(t, r.values[0][0], f32(0.4))
	testing.expect_value(t, r.values[1][0], f32(0.9))
	testing.expect_value(t, r.values[3][0], f32(0.6))
	flat[0] = {}
	items[0].world = world.MATRIX4_IDENTITY
	testing.expect_value(t, model(&r, &other_mesh, &m, world.matrix4_translation(0, 0, -7)), mat.Draw_Error.None)
	testing.expect_value(t, model(&r, &mesh, &m, world.matrix4_translation(0, 0, -10)), mat.Draw_Error.None)
	testing.expect_value(t, len(r.sources), 1) // 实例值不进入合批键
	testing.expect_value(t, r.values[6][0], f32(0.2)) // nil 使用材质默认值
	line(&r, {0, 0, 0}, {1, 0, 0}, {1, 1, 1, 1})
	view := View{view_projection = world.MATRIX4_IDENTITY, view_matrix = world.MATRIX4_IDENTITY}
	testing.expect_value(t, render3d_prepare(&r, view, "body"), mat.Draw_Error.None)
	testing.expect_value(t, render3d_batch_end(&r, 0), 2)
	testing.expect_value(t, render3d_prepare(&r, view, "glass"), mat.Draw_Error.None)
	expected := [4]int{3, 2, 0, 1}
	for item, i in r.queue.items do testing.expect_value(t, item.payload, expected[i])
	testing.expect_value(t, render3d_batch_end(&r, 0), 1)
	testing.expect_value(t, render3d_batch_end(&r, 2), 4)
	testing.expect_value(t, render3d_prepare(&r, view, ""), mat.Draw_Error.None)
	testing.expect_value(t, render3d_batch_end(&r, 2), 3) // 透明多 Pass 不跨对象
	testing.expect_value(t, debug_draw_line_count(&r.debug), 1)
	// 修改参数或贴图必须新建快照；原记录仍保留先前值。这里直接改数值并像
	// material_set_number / material_set_texture 一样递增 revision。
	values[1].number[0] = 0.8
	m.revision += 1
	testing.expect_value(t, model(&r, &mesh, &m, world.MATRIX4_IDENTITY), mat.Draw_Error.None)
	testing.expect_value(t, len(r.sources), 2)
	samplers[0].Texture = &other_texture
	m.revision += 1
	testing.expect_value(t, model(&r, &mesh, &m, world.MATRIX4_IDENTITY), mat.Draw_Error.None)
	testing.expect_value(t, len(r.sources), 3)
	testing.expect(t, r.snapshots[0].Fragment.Samplers[0].Texture == &texture)
	testing.expect_value(t, read_vec4(r.snapshots[0].Fragment.UniformBuffers[1][:], 0)[0], f32(0.5))
	clear(&r)
	testing.expect_value(t, debug_draw_line_count(&r.debug), 0)
	testing.expect_value(t, len(r.prepared), 0)
}

// 同一材质在 revision 与 Shader 不变时复用准备结果：不重新打包参数（直接改数值而不递增 revision 不会被发现，
// 这正是文档要求只经 material_set_number 等接口修改的原因）；revision、Shader 变化或 clear 后重新准备。
@(test)
render3d_prepared_follows_revision :: proc(t: ^testing.T) {
	device: foster.GraphicsDevice
	library := mat.Material_Library{device = &device}
	r := Render3D{library = &library}
	defer dispose(&r)
	vertex: foster.Shader
	vertex.Resource = cast(type_of(vertex.Resource))uintptr(1) // 仅验证绑定；不调用 GPU
	fragment := vertex
	fragment.Stage = .Fragment
	gpu: foster.Material
	foster.MaterialInitWithShaders(&gpu, &vertex, &fragment)
	defer foster.MaterialDispose(&gpu)
	schema := sh.Schema{name = "Body", fields = []sh.Field{
		{id = "hue", kind = .Scalar, instance = true, maximum = 1},
		{id = "gain", kind = .Scalar, maximum = 1}}}
	shader := mat.Material_Shader{schemas = []sh.Schema{schema}, desc = {instanced = true, passes = []sh.Pass_Desc{
		{id = "body", params = "Body", draw = .Model}}}}
	values := []sh.Value{{number = {0.2, 0, 0, 0}}, {number = {0.5, 0, 0, 0}}}
	m := mat.Material{owner = &library, shader = &shader,
		bindings = []mat.Material_Binding{{schema, values, &gpu, nil}}}
	mesh := foster.Mesh{GraphicsDevice = &device}
	mesh.VertexData.Format.Stride = dasset.DASSET_VERTEX_STRIDE_STATIC
	for _ in 0..<3 do testing.expect_value(t, model(&r, &mesh, &m, world.MATRIX4_IDENTITY), mat.Draw_Error.None)
	testing.expect_value(t, len(r.sources), 1)
	testing.expect_value(t, len(r.tables), 1) // 只准备一次
	values[1].number[0] = 0.9 // 绕过接口直接改：沿用缓存
	testing.expect_value(t, model(&r, &mesh, &m, world.MATRIX4_IDENTITY), mat.Draw_Error.None)
	testing.expect_value(t, len(r.sources), 1)
	m.revision += 1 // 经接口修改后重新准备，新参数进入新快照
	testing.expect_value(t, model(&r, &mesh, &m, world.MATRIX4_IDENTITY), mat.Draw_Error.None)
	testing.expect_value(t, len(r.sources), 2)
	testing.expect_value(t, read_vec4(r.snapshots[1].Fragment.UniformBuffers[1][:], 0)[0], f32(0.9))
	values[1].number[0] = 0.5
	m.revision += 1 // 改回原值：重新准备时按内容找到已有快照
	testing.expect_value(t, model(&r, &mesh, &m, world.MATRIX4_IDENTITY), mat.Draw_Error.None)
	testing.expect_value(t, len(r.sources), 2)
	testing.expect_value(t, r.records[len(r.records)-1].source, 0)
	other := shader // Shader 指针变化（reload 换了 Shader）也重新准备
	m.shader = &other
	testing.expect_value(t, model(&r, &mesh, &m, world.MATRIX4_IDENTITY), mat.Draw_Error.None)
	testing.expect_value(t, len(r.sources), 3)
	clear(&r)
	testing.expect_value(t, model(&r, &mesh, &m, world.MATRIX4_IDENTITY), mat.Draw_Error.None)
	testing.expect_value(t, len(r.sources), 1)
	testing.expect_value(t, len(r.tables), 1)
}

// 绘制入口的错误码：都在提交 Draw 之前返回，不需要真实 GPU。
@(test)
render3d_reports_errors_before_gpu :: proc(t: ^testing.T) {
	device: foster.GraphicsDevice
	library := mat.Material_Library{device = &device}
	shader := mat.Material_Shader{desc = {instanced = true, passes = []sh.Pass_Desc{{draw = .Model}}}}
	material := mat.Material{owner = &library, shader = &shader}
	r := Render3D{library = &library}
	defer dispose(&r)
	testing.expect_value(t, model(&r, nil, nil, world.MATRIX4_IDENTITY), mat.Draw_Error.Missing_Material)
	testing.expect_value(t, model(&r, nil, &material, world.MATRIX4_IDENTITY), mat.Draw_Error.Missing_Mesh)
	mesh := foster.Mesh{GraphicsDevice = &device}
	mesh.VertexData.Format.Stride = dasset.DASSET_VERTEX_STRIDE_STATIC
	testing.expect_value(t, buffer(&r, &mesh, &material, nil, 1), mat.Draw_Error.Instance_Buffer_Required)
	testing.expect_value(t, buffer(&r, &mesh, &material, &Model_Buffer{}, 1), mat.Draw_Error.Instance_Buffer_Required)
	// 蒙皮网格（68B 顶点）不在材质路径内，明确报错
	skinned := mesh
	skinned.VertexData.Format.Stride = dasset.DASSET_VERTEX_STRIDE_SKIN
	testing.expect_value(t, model(&r, &skinned, &material, world.MATRIX4_IDENTITY), mat.Draw_Error.Unsupported_Mesh)
	testing.expect_value(t, buffer(&r, &skinned, &material, nil, 1), mat.Draw_Error.Unsupported_Mesh)
}

// 每次 submit 先排好全部自动实例化数据：同网格同快照合批，同一批的各 Pass 连续存放，按槽数分段，
// 绘制时只按偏移取段，不再逐批上传。
@(test)
render3d_plan_packs_every_batch_once :: proc(t: ^testing.T) {
	device: foster.GraphicsDevice
	library := mat.Material_Library{device = &device}
	r := Render3D{library = &library}
	defer dispose(&r)
	vertex: foster.Shader
	vertex.Resource = cast(type_of(vertex.Resource))uintptr(1) // 仅验证布局；不调用 GPU
	fragment := vertex
	fragment.Stage = .Fragment
	gpu: foster.Material
	foster.MaterialInitWithShaders(&gpu, &vertex, &fragment)
	defer foster.MaterialDispose(&gpu)
	schema := sh.Schema{name = "Body", fields = []sh.Field{{id = "hue", kind = .Scalar, instance = true, maximum = 1}}}
	shader := mat.Material_Shader{schemas = []sh.Schema{schema}, desc = {instanced = true, passes = []sh.Pass_Desc{
		{id = "body", params = "Body", draw = .Model},
		{id = "shadow", params = "Body", draw = .Model, values = []sh.Pass_Value{{field = "hue", number = {0.9, 0, 0, 0}}}}}}}
	m := mat.Material{owner = &library, shader = &shader,
		bindings = []mat.Material_Binding{{schema, []sh.Value{{number = {0.2, 0, 0, 0}}}, &gpu, nil}}}
	plain_shader := mat.Material_Shader{desc = {passes = []sh.Pass_Desc{{id = "body", params = "Plain", draw = .Model}}}}
	plain := mat.Material{owner = &library, shader = &plain_shader,
		bindings = []mat.Material_Binding{{schema = {name = "Plain"}, material = &gpu}}}
	mesh := foster.Mesh{GraphicsDevice = &device}
	mesh.VertexData.Format.Stride = dasset.DASSET_VERTEX_STRIDE_STATIC
	other_mesh := mesh
	items := []Model_Item{{world.matrix4_translation(0, 0, -1), {1, 1, 1, 1}},
		{world.matrix4_translation(0, 0, -2), {1, 1, 1, 1}}}
	testing.expect_value(t, models(&r, &mesh, &m, items, values = [][4]f32{{0.4, 0, 0, 0}, {0.6, 0, 0, 0}}), mat.Draw_Error.None)
	testing.expect_value(t, model(&r, &other_mesh, &m, world.matrix4_translation(0, 0, -3)), mat.Draw_Error.None)
	testing.expect_value(t, model(&r, &mesh, &plain, world.matrix4_translation(0, 0, -0.5)), mat.Draw_Error.None)
	view := View{view_projection = world.MATRIX4_IDENTITY, view_matrix = world.MATRIX4_IDENTITY}
	testing.expect_value(t, render3d_prepare(&r, view, ""), mat.Draw_Error.None)
	// 普通材质组离得最近排在前面；实例组内前到后，换网格断批。
	counts := render3d_plan(&r)
	testing.expect_value(t, len(r.batches), 3)
	testing.expect_value(t, r.batches[1], Render3D_Batch{start = 1, end = 3, first = 0})
	testing.expect_value(t, r.batches[2], Render3D_Batch{start = 3, end = 4, first = 4})
	testing.expect_value(t, counts[1], 6) // (2 + 1) 个实例 × 2 个 Pass
	testing.expect_value(t, counts[0], 0)
	bases := render3d_pack(&r, counts)
	stride := model_stride(1)
	testing.expect_value(t, bases[1], 0)
	testing.expect_value(t, len(r.upload), 6 * stride)
	// 每个位置的 hue：body 用各自的值或材质默认值，shadow 用 Pass 固定值。
	hues := [6]f32{0.4, 0.6, 0.9, 0.9, 0.2, 0.9}
	for hue, i in hues do testing.expect_value(t, read_vec4(r.upload[:], i*stride + MODEL_BASE_BYTES)[0], hue)
	testing.expect_value(t, read_vec4(r.upload[:], 1*stride + 32)[3], f32(-2)) // 世界矩阵第 3 列的平移 z
	testing.expect_value(t, read_vec4(r.upload[:], 4*stride + 32)[3], f32(-3))
}

// 调试线默认只随画全部 Pass 的提交：分阶段的 shadow/body/outline 不重复叠加，需要时显式开启。
@(test)
render3d_debug_lines_follow_pass_selection :: proc(t: ^testing.T) {
	device: foster.GraphicsDevice
	library := mat.Material_Library{device = &device}
	r: Render3D
	testing.expect_value(t, init(&r, &library), "")
	defer dispose(&r)
	line(&r, {0, 0, 0}, {1, 0, 0}, {1, 1, 1, 1})
	view := View{view_projection = world.MATRIX4_IDENTITY, view_matrix = world.MATRIX4_IDENTITY} // 目标无效
	testing.expect_value(t, submit(&r, view, "shadow"), mat.Draw_Error.None) // 不画线，无事可做
	testing.expect_value(t, submit(&r, view), mat.Draw_Error.Invalid_Target) // 要画线，才检查目标
	view.draw_debug = true
	testing.expect_value(t, submit(&r, view, "shadow"), mat.Draw_Error.Invalid_Target)
	view.draw_debug = false
	testing.expect_value(t, submit(&r, view), mat.Draw_Error.None)
}

// 记录保存当时的 Shader 与槽数：之后 reload 换了 Shader（Pass 更少），已记录的快照仍按原布局准备，不越界。
@(test)
render3d_records_survive_material_reload :: proc(t: ^testing.T) {
	device: foster.GraphicsDevice
	library := mat.Material_Library{device = &device}
	r := Render3D{library = &library}
	defer dispose(&r)
	vertex: foster.Shader
	vertex.Resource = cast(type_of(vertex.Resource))uintptr(1)
	fragment := vertex
	fragment.Stage = .Fragment
	gpu: foster.Material
	foster.MaterialInitWithShaders(&gpu, &vertex, &fragment)
	defer foster.MaterialDispose(&gpu)
	two := mat.Material_Shader{desc = {passes = []sh.Pass_Desc{
		{id = "body", params = "A", draw = .Model}, {id = "outline", params = "B", draw = .Model}}}}
	one := mat.Material_Shader{desc = {passes = []sh.Pass_Desc{{id = "body", params = "C", draw = .Model}}}}
	m := mat.Material{owner = &library, shader = &two, bindings = []mat.Material_Binding{
		{schema = {name = "A"}, material = &gpu}, {schema = {name = "B"}, material = &gpu}}}
	mesh := foster.Mesh{GraphicsDevice = &device}
	mesh.VertexData.Format.Stride = dasset.DASSET_VERTEX_STRIDE_STATIC
	testing.expect_value(t, model(&r, &mesh, &m, world.MATRIX4_IDENTITY), mat.Draw_Error.None)
	// 模拟 material_reload：同一指针换成单 Pass Shader 和新的参数组。
	m.shader = &one
	m.bindings = []mat.Material_Binding{{schema = {name = "C"}, material = &gpu}}
	m.revision += 1
	view := View{view_projection = world.MATRIX4_IDENTITY, view_matrix = world.MATRIX4_IDENTITY}
	testing.expect_value(t, render3d_prepare(&r, view, "outline"), mat.Draw_Error.None)
	testing.expect_value(t, len(r.queue.items), 1)
	testing.expect_value(t, r.sources[0].count, 1)
	testing.expect_value(t, model(&r, &mesh, &m, world.MATRIX4_IDENTITY), mat.Draw_Error.None)
	testing.expect_value(t, len(r.sources), 2) // 新 Shader 的记录不复用旧快照
}

// CameraPosition 由视矩阵求逆得到，顶点 b0 与片元 b0 写同一个值。
@(test)
camera_position_and_material_blocks :: proc(t: ^testing.T) {
	camera: world.Camera3D
	world.camera3d_init(&camera, 64, 64)
	world.camera3d_set_position(&camera, {1, 2, 3})
	world.camera3d_set_target(&camera, {0, 0, 0})
	position := camera_position(world.camera3d_view(&camera))
	for expected, i in ([4]f32{1, 2, 3, 1}) {
		testing.expectf(t, math.abs(position[i] - expected) < 1e-4, "camera[%d] = %f", i, position[i])
	}
	testing.expect_value(t, camera_position({}), [4]f32{0, 0, 0, 1}) // 不可逆时退回原点
	vertex: [MATERIAL_VERTEX_BLOCK_SIZE]u8
	frame: [MATERIAL_FRAME_BLOCK_SIZE]u8
	view := View{time = 2, delta_time = 0.5, frame = 7}
	view.target.WidthInPixels, view.target.HeightInPixels = 320, 240
	pack_material_blocks(vertex[:], frame[:], world.MATRIX4_IDENTITY, world.MATRIX4_IDENTITY, view,
		{1, 2, 3, 1}, {0.25, 0.75}, {1, 0.5, 0, 1})
	testing.expect_value(t, read_vec4(vertex[:], VERTEX_MATRIX_BLOCK_SIZE), [4]f32{2, 0.5, 7, 0})
	testing.expect_value(t, read_vec4(vertex[:], VERTEX_MATRIX_BLOCK_SIZE + 16), [4]f32{1, 2, 3, 1})
	testing.expect_value(t, read_vec4(frame[:], 16), [4]f32{0.25, 0.75, 320, 240})
	testing.expect_value(t, read_vec4(frame[:], 32), [4]f32{1, 0.5, 0, 1})
	testing.expect_value(t, read_vec4(frame[:], 48), [4]f32{1, 2, 3, 1})
}

// 3D 材质块只在 pack_material_blocks 写：顶点 WVP、World、Clock、CameraPosition，片元 Clock、Pointer、Tint、CameraPosition。
@(test)
material_blocks_follow_model_include_layout :: proc(t: ^testing.T) {
	vertex: [MATERIAL_VERTEX_BLOCK_SIZE]u8
	frame: [MATERIAL_FRAME_BLOCK_SIZE]u8
	wvp := world.matrix4_translation(1, 2, 3)
	view := View{target = {WidthInPixels = 640, HeightInPixels = 360}, time = 1.5, delta_time = 0.25, frame = 7}
	pack_material_blocks(vertex[:], frame[:], wvp, world.MATRIX4_IDENTITY, view, {4, 5, 6, 1}, {0.25, 0.75}, {0.5, 0.5, 0.5, 1})
	floats :: proc(bytes: []u8, offset: int) -> [4]f32 {
		return (cast(^[4]f32)&bytes[offset])^
	}
	testing.expect_value(t, floats(vertex[:], VERTEX_MATRIX_BLOCK_SIZE), [4]f32{1.5, 0.25, 7, 0})
	testing.expect_value(t, floats(vertex[:], VERTEX_MATRIX_BLOCK_SIZE + 16), [4]f32{4, 5, 6, 1})
	testing.expect_value(t, floats(frame[:], 0), [4]f32{1.5, 0.25, 7, 0})
	testing.expect_value(t, floats(frame[:], 16), [4]f32{0.25, 0.75, 640, 360})
	testing.expect_value(t, floats(frame[:], 32), [4]f32{0.5, 0.5, 0.5, 1})
	testing.expect_value(t, floats(frame[:], 48), [4]f32{4, 5, 6, 1})
}

// 仿射矩阵的包围盒走中心/半长快速路径，结果与 8 个角点的外包盒一致；非仿射矩阵仍逐角点变换。
@(test)
world_bounds_affine_matches_corners :: proc(t: ^testing.T) {
	corners_bounds :: proc(bounds: dasset.Dasset_Bounds, m: world.Matrix4) -> (result: dasset.Dasset_Bounds) {
		for corner, i in aabb_corners(bounds) {
			p, _ := world.matrix4_transform_point(m, corner)
			if i == 0 {
				result.min, result.max = p, p
			} else {
				for axis in 0..<3 {
					result.min[axis] = min(result.min[axis], p[axis])
					result.max[axis] = max(result.max[axis], p[axis])
				}
			}
		}
		return
	}
	boxes := []dasset.Dasset_Bounds{
		{min = {-1, -1, -1}, max = {1, 1, 1}},
		{min = {0.2, -3, 4}, max = {2.5, 1, 9}},
		{min = {1, 1, 1}, max = {-1, -2, -3}}, // 反向的盒
	}
	for i in 0..<40 {
		a := f32(i) * 0.37
		q := [4]f32{math.sin(a) * 0.6, math.cos(a*1.3) * 0.5, math.sin(a*0.7) * 0.4, math.cos(a)}
		length := math.sqrt(q[0]*q[0] + q[1]*q[1] + q[2]*q[2] + q[3]*q[3])
		q /= length
		scale := world.matrix4_scaling(0.5 + f32(i % 3), 2 - f32(i % 2), 0.25 + f32(i % 5))
		m := world.matrix4_multiply(world.matrix4_multiply(scale, world.matrix4_from_quaternion(q)),
			world.matrix4_translation(f32(i) - 20, f32(i % 7), -f32(i) * 0.5))
		for box in boxes {
			got, ok := render3d_world_bounds(box, m)
			expected := corners_bounds(box, m)
			testing.expect(t, ok)
			for axis in 0..<3 {
				testing.expectf(t, math.abs(got.min[axis] - expected.min[axis]) < 1e-4 &&
					math.abs(got.max[axis] - expected.max[axis]) < 1e-4, "matrix %d axis %d: %v vs %v", i, axis, got, expected)
			}
		}
	}
	// 非仿射（透视）矩阵仍按角点变换，结果不变。
	perspective := world.matrix4_multiply(world.matrix4_translation(0, 0, -10), world.matrix4_perspective_fov(1, 1.5, 0.1, 100))
	got, ok := render3d_world_bounds(boxes[0], perspective)
	testing.expect(t, ok && got == corners_bounds(boxes[0], perspective))
	nan := transmute(f32)u32(0x7fc00000)
	_, finite := render3d_world_bounds({min = {nan, 0, 0}, max = {1, 1, 1}}, world.MATRIX4_IDENTITY)
	testing.expect(t, !finite) // 非有限的盒保守保留
}
