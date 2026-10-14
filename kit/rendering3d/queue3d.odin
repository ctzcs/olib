// rendering3d:queue3d —— 渲染项队列与排序（对位 DragonLib Renderer3D 的提交/分桶逻辑）。
//
// 每帧：clear -> 提交（payload + 视深度 + 是否透明）->
// queue_sort（不透明前到后省 early-z，透明后到前保正确混合）->
// 调用侧按序发射 GPU 命令。payload 由游戏定义（Mesh、材质、world 矩阵等），
// 队列只认排序所需的两个字段。
package rendering3d

import "core:math"

import world "olib:kit/world"

// 分区：
//   类型 —— Render_Item / Render_Queue
//   提交与排序 —— submit / sort / clear

// ------------------------------------------------------------------------------
// 类型
// ------------------------------------------------------------------------------

Render_Item :: struct($T: typeid) {
	payload:     T,
	view_depth:  f32,  // 排序键：到相机的视空间深度（submit 时算好）
	transparent: bool, // true 进透明桶（后到前）
}

Render_Queue :: struct($T: typeid) {
	items: [dynamic]Render_Item(T),
}

// ------------------------------------------------------------------------------
// 提交与排序
// ------------------------------------------------------------------------------

queue_submit :: proc(q: ^Render_Queue($T), payload: T, view_depth: f32, transparent: bool) {
	append(&q.items, Render_Item(T){
		payload     = payload,
		view_depth  = view_depth,
		transparent = transparent,
	})
}

// 排序：不透明按视深度升序（前到后，省 early-z），透明按降序（后到前，
// 保混合正确），不透明整体排在透明之前。插入排序稳定，同深度保持提交序；
// 每帧数百项内比通用排序更快。
queue_sort :: proc(q: ^Render_Queue($T)) {
	for i in 1..<len(q.items) {
		item := q.items[i]
		j := i
		for j > 0 && render_item_less(item, q.items[j - 1]) {
			q.items[j] = q.items[j - 1]
			j -= 1
		}
		q.items[j] = item
	}
}

queue_clear :: proc(q: ^Render_Queue($T)) {
	clear(&q.items)
}

queue_dispose :: proc(q: ^Render_Queue($T)) {
	delete(q.items)
	q^ = {}
}

// 便利：world 矩阵平移点在相机前方的距离（排序键，越大越远）。
// look_at 是右手系，视空间前方为 -Z，这里取反成正数。
queue_view_depth :: proc(camera: ^world.Camera3D, world_matrix: world.Matrix4) -> f32 {
	view := world.camera3d_view(camera)
	// 行向量约定：平移在各列的第 4 分量
	position := world.Vec4{world_matrix.c0[3], world_matrix.c1[3], world_matrix.c2[3], 1}
	p := world.matrix4_transform_vec4(view, position)
	if math.abs(p[3]) < 1e-8 { return 0 }
	return -p[2] / p[3]
}

@(private)
render_item_less :: proc(a, b: Render_Item($T)) -> bool {
	if a.transparent != b.transparent {
		return !a.transparent // 不透明排前面
	}
	if a.transparent {
		return a.view_depth > b.view_depth // 透明：远者先画（后到前）
	}
	return a.view_depth < b.view_depth // 不透明：近者先画（前到后）
}
