// rendering3d:queue3d —— 渲染项队列与排序（对位 DragonLib Renderer3D 的提交/分桶逻辑）。
//
// 每帧：clear -> 提交 Render_Item（world 矩阵 + 视深度）->
// queue_sort（不透明前到后省 early-z，透明后到前保正确混合）->
// 按序发射 GPU 命令（发射端接 ofoster Mesh/Shader，属着色器管线侧）。
package rendering3d

import "core:math"

import world "olib:engine/world"
import foster "ofoster:."

// 分区：
//   类型 —— Render_Item / Render_Queue
//   提交与排序 —— submit / sort / clear

// ------------------------------------------------------------------------------
// 类型
// ------------------------------------------------------------------------------

Render_Item :: struct {
	mesh:     ^foster.Mesh, // ofoster Mesh（上传于 mesh3d_upload）
	material: Standard_Material_3D,
	world:    world.Matrix4,
	skinned:  bool, // 蒙皮走 palette 槽的材质变体

	view_depth: f32, // 排序键：到相机的视空间深度（submit 时算好）
}

Render_Queue :: struct {
	items: [dynamic]Render_Item,
}

// ------------------------------------------------------------------------------
// 提交与排序
// ------------------------------------------------------------------------------

queue_submit :: proc(q: ^Render_Queue, mesh: ^foster.Mesh, material: Standard_Material_3D, world_matrix: world.Matrix4, view_depth: f32, skinned := false) {
	append(&q.items, Render_Item{
		mesh       = mesh,
		material   = material,
		world      = world_matrix,
		skinned    = skinned,
		view_depth = view_depth,
	})
}

// 排序：不透明（transparent=false）按视深度升序（前到后，省 early-z），
// 透明按降序（后到前，保混合正确）。两类相对次序由 stable 排序保持
// 提交序（不透明整体先于/后于透明由发射端分桶决定，通常先不透明）。
// 插入排序——每帧数百项内比通用排序更快且稳定。
queue_sort :: proc(q: ^Render_Queue) {
	less :: proc(a, b: Render_Item) -> bool {
		if a.material.state.transparent != b.material.state.transparent {
			return !a.material.state.transparent // 不透明排前面
		}
		if a.material.state.transparent {
			return a.view_depth > b.view_depth // 透明：远者先画（后到前）
		}
		return a.view_depth < b.view_depth // 不透明：近者先画（前到后）
	}

	for i in 1..<len(q.items) {
		item := q.items[i]
		j := i
		for j > 0 && less(item, q.items[j - 1]) {
			q.items[j] = q.items[j - 1]
			j -= 1
		}
		q.items[j] = item
	}
}

queue_clear :: proc(q: ^Render_Queue) {
	clear(&q.items)
}

queue_dispose :: proc(q: ^Render_Queue) {
	delete(q.items)
	q^ = {}
}

// 便利：按相机与 world 平移算视深度（排序键）。
queue_view_depth :: proc(camera: ^world.Camera3D, world_matrix: world.Matrix4) -> f32 {
	view := world.camera3d_view(camera)
	origin := world.matrix4_transform_vec4(view, world.Vec4{0, 0, 0, 1})
	if math.abs(origin[3]) < 1e-8 { return 0 }
	return origin[2] / origin[3]
}
