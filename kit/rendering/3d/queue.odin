// rendering3d:queue —— 渲染项队列与排序（对位 DragonLib Renderer3D 的提交/分桶逻辑）。
//
// 每帧：clear -> 提交（payload + 视深度 + 是否透明）->
// queue_sort（不透明前到后省 early-z，透明后到前保正确混合）->
// 调用侧按序发射 GPU 命令。payload 由游戏定义（Mesh、材质、world 矩阵等），
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
	group:       int,  // 可选的不透明分组；同深度组按此键排序
}

Render_Queue :: struct($T: typeid) {
	items: [dynamic]Render_Item(T),
	scratch: [dynamic]Render_Item(T),
	group_depths: map[int]f32,
}

// ------------------------------------------------------------------------------
// 提交与排序
// ------------------------------------------------------------------------------

queue_submit :: proc(q: ^Render_Queue($T), payload: T, view_depth: f32, transparent: bool,
	group: int = 0) {
	append(&q.items, Render_Item(T){
		payload     = payload,
		view_depth  = view_depth,
		transparent = transparent,
		group       = group,
	})
}

// 稳定 O(n log n) 归并；工作区跨帧复用。默认仍是不透明前到后、透明后到前。
// grouped 时不透明组按最近深度排列，组内前到后；透明始终全局后到前。
queue_sort :: proc(q: ^Render_Queue($T), grouped: bool = false) {
	clear(&q.group_depths)
	if grouped {
		for item in q.items {
			if item.transparent do continue
			depth, exists := q.group_depths[item.group]
			if !exists || item.view_depth < depth do q.group_depths[item.group] = item.view_depth
		}
	}
	resize(&q.scratch, len(q.items))
	for width := 1; width < len(q.items); width *= 2 {
		for start := 0; start < len(q.items); start += 2 * width {
			mid := min(start + width, len(q.items))
			end := min(start + 2 * width, len(q.items))
			a, b := start, mid
			for i in start..<end {
				if a < mid && (b == end || !render_item_less(q.items[b], q.items[a],
					q.group_depths, grouped)) {
					q.scratch[i] = q.items[a]
					a += 1
				} else {
					q.scratch[i] = q.items[b]
					b += 1
				}
			}
		}
		copy(q.items[:], q.scratch[:])
	}
}

queue_clear :: proc(q: ^Render_Queue($T)) {
	clear(&q.items)
}

queue_dispose :: proc(q: ^Render_Queue($T)) {
	delete(q.items)
	delete(q.scratch)
	delete(q.group_depths)
	q^ = {}
}

// 便利：world 矩阵平移点在相机前方的距离（排序键，越大越远）。
// look_at 是右手系，视空间前方为 -Z，这里取反成正数。
queue_view_depth :: proc(camera: ^world.Camera3D, world_matrix: world.Matrix4) -> f32 {
	view := world.camera3d_view(camera)
	// 行向量约定：平移在各列的第 4 分量
	position := world.Vec4{world_matrix.c0[3], world_matrix.c1[3], world_matrix.c2[3], 1}
	p := world.matrix4_transform_vec4(view, position)
	if math.abs(p[3]) < 1e-8 do return 0
	return -p[2] / p[3]
}

@(private)
render_item_less :: proc(a, b: Render_Item($T), depths: map[int]f32, grouped: bool) -> bool {
	if a.transparent != b.transparent {
		return !a.transparent // 不透明排前面
	}
	if a.transparent {
		return a.view_depth > b.view_depth // 透明：远者先画（后到前）
	}
	if grouped && a.group != b.group {
		if depths[a.group] != depths[b.group] do return depths[a.group] < depths[b.group]
		return a.group < b.group
	}
	return a.view_depth < b.view_depth // 不透明：近者先画（前到后）
}
