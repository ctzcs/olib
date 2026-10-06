// rendering3d 包单元测试（CPU：材质状态推导 + 队列排序 + 格式步长）。
#+test
package rendering3d

import "core:testing"

import dasset "olib:engine/dasset"
import foster "ofoster:."
import world "olib:engine/world"

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
	testing.expect(t, pack_point_light_block(buf, lights))
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
