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
