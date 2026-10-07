// rendering3d 包单元测试（CPU：材质状态推导 + 队列排序 + 格式步长）。
#+test
package rendering3d

import "core:math"
import "core:testing"

import dasset "olib:core/dasset"
import world "olib:engine/world"
import foster "olib:foster"

@(test)
material_render_state_dispatch :: proc(t: ^testing.T) {
	opaque := dasset.DASSET_MATERIAL_DEFAULT
	testing.expect(t, material_render_state(&opaque) == (RENDER_STATE_OPAQUE))

	mask := dasset.DASSET_MATERIAL_DEFAULT
	mask.alpha_mode = .Mask
	state := material_render_state(&mask)
	testing.expect(t, !state.transparent) // Mask 留在不透明队列

	blend := dasset.DASSET_MATERIAL_DEFAULT
	blend.alpha_mode = .Blend
	blend.double_sided = true
	state2 := material_render_state(&blend)
	testing.expect(t, state2.transparent && state2.cull_none)

	mat := standard_material_from_dasset(&blend)
	testing.expect(t, mat.state.transparent && mat.albedo_texture == -1 && !material_has_normal_map(&mat))
}

@(test)
mesh3d_format_strides :: proc(t: ^testing.T) {
	static := mesh3d_static_format()
	defer foster.vertex_format_dispose(&static)
	testing.expect(t, static.Stride == 48 && len(static.Elements) == 4)

	skin := mesh3d_skin_format()
	defer foster.vertex_format_dispose(&skin)
	testing.expect(t, skin.Stride == 68 && len(skin.Elements) == 6)
}

@(private)
make_item :: proc(depth: f32, transparent: bool) -> Render_Item {
	item: Render_Item
	item.view_depth = depth
	item.material.state.transparent = transparent
	item.world = world.MATRIX4_IDENTITY
	return item
}

@(test)
queue_sort_buckets_and_depth :: proc(t: ^testing.T) {
	q: Render_Queue
	defer queue_dispose(&q)

	// 提交乱序：透明(5)、不透明(10)、透明(1)、不透明(2)
	queue_submit(&q, nil, material_of(make_item(5, true)), world.MATRIX4_IDENTITY, 5)
	queue_submit(&q, nil, material_of(make_item(10, false)), world.MATRIX4_IDENTITY, 10)
	queue_submit(&q, nil, material_of(make_item(1, true)), world.MATRIX4_IDENTITY, 1)
	queue_submit(&q, nil, material_of(make_item(2, false)), world.MATRIX4_IDENTITY, 2)

	queue_sort(&q)

	// 不透明在前（前到后 2,10），透明在后（后到前 5,1）
	testing.expect(t, len(q.items) == 4)
	testing.expectf(t, !q.items[0].material.state.transparent && q.items[0].view_depth == 2, "0")
	testing.expectf(t, !q.items[1].material.state.transparent && q.items[1].view_depth == 10, "1")
	testing.expectf(t, q.items[2].material.state.transparent && q.items[2].view_depth == 5, "2")
	testing.expectf(t, q.items[3].material.state.transparent && q.items[3].view_depth == 1, "3")

	queue_clear(&q)
	testing.expect(t, len(q.items) == 0)
}

@(private)
material_of :: proc(item: Render_Item) -> Standard_Material_3D {
	return item.material
}

// ---------------------------------------------------------------------------
// 着色器管线 —— uniform 打包 / 驱动分发 / 内嵌 blob
// ---------------------------------------------------------------------------

@(test)
uniform_blocks_pack_layouts :: proc(t: ^testing.T) {
	buf := make([]u8, 1024)
	defer delete(buf)

	// 槽 0：矩阵块——WVP 与 World 各占 64B（列主序）
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

	// 光照块：80B、5 个 vec4
	light := make_light_block({0, -1, 0}, {0.1, 0.1, 0.1}, {1, 1, 1}, {1, 2, 3}, 1)
	testing.expect(t, pack_light_block(buf, &light))
	testing.expect(t, read_vec4(buf, 48) == ([4]f32{1, 2, 3, 0}))
	testing.expect(t, read_vec4(buf, 64)[0] == 1) // hdr

	// 材质块：96B
	mat := dasset.DASSET_MATERIAL_DEFAULT
	mat.base_color_factor = {1, 0, 0, 1}
	mat.metallic = 0.5
	std_mat := standard_material_from_dasset(&mat)
	mat_block := material_block_from(&std_mat)
	testing.expect(t, pack_material_block(buf, &mat_block))
	testing.expect(t, read_vec4(buf, 0) == ([4]f32{1, 0, 0, 1}))
	testing.expect(t, read_vec4(buf, 48)[0] == 0.5)
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
point_light_block_meta_and_slots :: proc(t: ^testing.T) {
	buf := make([]u8, POINT_LIGHT_BLOCK_SIZE)
	defer delete(buf)

	lights := []Point_Light{
		{position = {1, 2, 3}, range = 10, color = {1, 0, 0}, intensity = 2},
	}
	defer delete(lights)
	testing.expect(t, pack_point_light_block(buf, lights, nil))
	testing.expect(t, read_vec4(buf, 0)[0] == 1) // count
	testing.expect(t, read_vec4(buf, 16) == ([4]f32{1, 2, 3, 10}))
	testing.expect(t, read_vec4(buf, 16 + 16*16) == ([4]f32{1, 0, 0, 2}))
	testing.expect(t, read_vec4(buf, 16 + 16*17) == ([4]f32{0, 0, 0, 0})) // 第二盏为空
}

@(test)
shader_blobs_embedded_and_driver_pick :: proc(t: ^testing.T) {
	// 内嵌 blob 编译期存在且非空（#load 保证，运行时兜底断言）
	testing.expect(t, len(standard3d_vertex_spv) > 4)
	testing.expect(t, len(standard3d_vertex_dxil) > 4)
	testing.expect(t, len(depthonly_skinned_vertex_spv) > 4)
	// SPIR-V 魔数 0x07230203（小端 03 02 23 07）
	spv := standard3d_vertex_spv
	testing.expect(t, spv[0] == 0x03 && spv[1] == 0x02 && spv[2] == 0x23 && spv[3] == 0x07)
	// DXIL 容器魔数 "DXBC"
	dxil := standard3d_vertex_dxil
	testing.expect(t, dxil[0] == 'D' && dxil[1] == 'X' && dxil[2] == 'B' && dxil[3] == 'C')

	// 驱动分发
	testing.expect(t, shader3d_driver_supported(.Vulkan))
	testing.expect(t, shader3d_driver_supported(.D3D12))
	testing.expect(t, !shader3d_driver_supported(.Metal))
	d3d_pick := shader3d_pick_code(.D3D12, standard3d_vertex_spv, standard3d_vertex_dxil)
	testing.expect(t, len(d3d_pick) == len(standard3d_vertex_dxil) && d3d_pick[0] == standard3d_vertex_dxil[0])
	vk_pick := shader3d_pick_code(.Vulkan, standard3d_vertex_spv, standard3d_vertex_dxil)
	testing.expect(t, len(vk_pick) == len(standard3d_vertex_spv) && vk_pick[0] == standard3d_vertex_spv[0])
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
// 聚光灯打包
// ---------------------------------------------------------------------------

@(test)
spot_light_pack_layout :: proc(t: ^testing.T) {
	buf := make([]u8, POINT_LIGHT_BLOCK_SIZE)
	defer delete(buf)

	spots := []Spot_Light{
		{
			position = {0, 5, 0},
			direction = {0, -1, 0},
			range = 10,
			color = {1, 0.5, 0.2},
			intensity = 3,
			inner_angle = math.PI / 12,
			outer_angle = math.PI / 6,
		},
	}
	defer delete(spots)

	testing.expect(t, pack_point_light_block(buf, nil, spots))
	// 聚光 meta 在 33 号 vec4
	testing.expect(t, read_vec4(buf, 33*16)[0] == 1)
	// position/range
	testing.expect(t, read_vec4(buf, 34*16) == ([4]f32{0, 5, 0, 10}))
	// color/intensity
	testing.expect(t, read_vec4(buf, 50*16) == ([4]f32{1, 0.5, 0.2, 3}))
	// direction/cosOuter（30°半角）
	dir := read_vec4(buf, 66*16)
	testing.expect(t, dir[0] == 0 && dir[1] == -1 && dir[2] == 0)
	testing.expectf(t, math.abs(dir[3] - math.cos(f32(math.PI / 6))) < 1e-6, "cosOuter")
	// cosInner（15°）
	inner := read_vec4(buf, 82*16)
	testing.expectf(t, math.abs(inner[0] - math.cos(f32(math.PI / 12))) < 1e-6, "cosInner")

	// 越界角度钳制：outer > pi/2
	bad := []Spot_Light{{outer_angle = 3, inner_angle = 5}}
	defer delete(bad)
	testing.expect(t, pack_point_light_block(buf, nil, bad))
	clamped := read_vec4(buf, 66*16)
	testing.expectf(t, math.abs(clamped[3] - math.cos(f32(math.PI / 2))) < 1e-6, "outer 钳到 pi/2")
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
