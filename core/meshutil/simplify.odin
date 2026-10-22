// meshutil:simplify —— 二次误差（QEM）边折叠简化，只改写索引，不生成新顶点。
//
// 思路对位 meshoptimizer 的 meshopt_simplify：顶点按位置分组并分类，
// 开放边界只沿边界收缩，属性缝两侧成对收缩，其余复杂顶点锁定；每轮按误差排序，
// 一个顶点每轮最多参与一次折叠，并拒绝会翻转三角形或产生非流形边的折叠。
package meshutil

import "core:math"
import "core:slice"

// 分区：
//   简化入口 —— simplify
//   顶点分类 —— 开放边 / 种类 / 可折叠方向
//   误差二次型 —— Quadric
//   边折叠 —— 翻转检查 / 连接条件 / 边界环更新

// ==============================================================================
// 简化入口
// ==============================================================================

// 把三角形索引简化到不超过 target_index_count（尽量接近），或直到下一步误差超过 max_error。
// max_error 与返回的 error 都是相对网格包围盒最长边的距离（0.01 ≈ 1%）。
// 结果引用原顶点数组，常配合 compact 去掉不再使用的顶点；返回切片使用 allocator。
// 输入索引越界或长度不是 3 的倍数时返回 nil, 0, false。
simplify :: proc(positions: [][3]f32, indices: []u32, target_index_count: int, max_error: f32 = 0.01,
	allocator := context.allocator) -> (result: []u32, error: f32, ok: bool) {
	if !indices_valid(positions, indices) do return nil, 0, false
	n := len(positions)
	target := max(target_index_count, 0)
	work := make([]u32, len(indices))
	defer delete(work)
	copy(work, indices)
	count := len(indices)

	// ---- 归一化：误差相对包围盒最长边，与模型尺寸无关 ----
	used := make([]bool, n)
	defer delete(used)
	for index in indices do used[index] = true
	low := [3]f32{math.INF_F32, math.INF_F32, math.INF_F32}
	high := -low
	for p, i in positions {
		if !used[i] do continue
		for axis in 0..<3 {
			low[axis] = min(low[axis], p[axis])
			high[axis] = max(high[axis], p[axis])
		}
	}
	extent := max(high[0]-low[0], high[1]-low[1], high[2]-low[2])
	if !(extent > 0) do extent = 1
	scaled := make([][3]f32, n)
	defer delete(scaled)
	for p, i in positions {
		if used[i] do scaled[i] = (p-low)/extent
	}

	// ---- 位置分组与环形同位链：wedge[i] 是下一个同位置顶点 ----
	remap := position_remap(positions, indices)
	defer delete(remap)
	wedge := make([]u32, n)
	defer delete(wedge)
	for &w, i in wedge do w = u32(i)
	for r, i in remap {
		if r == u32(i) do continue
		wedge[i] = wedge[r]
		wedge[r] = u32(i)
	}

	open_out := make([]u32, n)
	defer delete(open_out)
	open_in := make([]u32, n)
	defer delete(open_in)
	open_edges(work, open_out, open_in)
	kinds := make([]Vertex_Kind, n)
	defer delete(kinds)
	classify(kinds, used, remap, wedge, open_out, open_in)

	// ---- 误差二次型：面平面按面积加权，边界与缝再加垂直平面，阻止轮廓收缩 ----
	quadrics := make([]Quadric, n)
	defer delete(quadrics)
	for t := 0; t < count; t += 3 {
		p0 := scaled[work[t]]
		normal := cross(scaled[work[t+1]]-p0, scaled[work[t+2]]-p0)
		area := length(normal)
		if area <= 0 do continue
		normal /= area
		q := quadric_plane(normal, -dot(normal, p0), area)
		for k in 0..<3 do quadric_add(&quadrics[remap[work[t+k]]], q)
	}
	for t := 0; t < count; t += 3 {
		for e in 0..<3 {
			i0 := work[t+e]
			i1 := work[t+(e+1)%3]
			i2 := work[t+(e+2)%3]
			kind := kinds[i0]
			if kind != kinds[i1] || (kind != .Border && kind != .Seam) || open_out[i0] != i1 do continue
			p0 := scaled[i0]
			edge := scaled[i1]-p0
			edge_length := length(edge)
			if edge_length <= 0 do continue
			direction := edge/edge_length
			side := scaled[i2]-p0
			side -= direction*dot(side, direction)
			side_length := length(side)
			if side_length <= 0 do continue
			normal := side/side_length
			weight: f32 = kind == .Border ? 10 : 1
			q := quadric_plane(normal, -dot(normal, p0), edge_length*edge_length*weight)
			quadric_add(&quadrics[remap[i0]], q)
			quadric_add(&quadrics[remap[i1]], q)
		}
	}

	// ---- 逐轮折叠 ----
	error_limit := max_error*max_error
	result_error: f32
	collapse_remap := make([]u32, n)
	defer delete(collapse_remap)
	group_target := make([]u32, n)
	defer delete(group_target)
	locked := make([]bool, n)
	defer delete(locked)
	triangle_offsets := make([]u32, n+1)
	defer delete(triangle_offsets)
	triangle_list := make([]u32, len(indices))
	defer delete(triangle_list)
	candidates := make([dynamic]Collapse, 0, len(indices))
	defer delete(candidates)

	for count > target {
		// 位置分组 → 所在三角形，用于翻转检查。
		slice.zero(triangle_offsets)
		for k in 0..<count do triangle_offsets[remap[work[k]]+1] += 1
		for i in 0..<n do triangle_offsets[i+1] += triangle_offsets[i]
		for k in 0..<count {
			r := remap[work[k]]
			triangle_list[triangle_offsets[r]] = u32(k-k%3)
			triangle_offsets[r] += 1
		}
		for i := n; i > 0; i -= 1 do triangle_offsets[i] = triangle_offsets[i-1]
		triangle_offsets[0] = 0

		clear(&candidates)
		for t := 0; t < count; t += 3 {
			for e in 0..<3 {
				i0 := work[t+e]
				i1 := work[t+(e+1)%3]
				r0 := remap[i0]
				r1 := remap[i1]
				if r0 == r1 do continue
				forward := can_collapse(kinds, open_out, open_in, i0, i1)
				backward := can_collapse(kinds, open_out, open_in, i1, i0)
				if !forward && !backward do continue
				forward_error := forward ? quadric_error(quadrics[r0], scaled[i1]) : math.INF_F32
				backward_error := backward ? quadric_error(quadrics[r1], scaled[i0]) : math.INF_F32
				if forward_error <= backward_error {
					append(&candidates, Collapse{i0, i1, forward_error})
				} else {
					append(&candidates, Collapse{i1, i0, backward_error})
				}
			}
		}
		if len(candidates) == 0 do break
		slice.sort_by(candidates[:], proc(a, b: Collapse) -> bool {
			return a.error < b.error
		})

		for &r, i in collapse_remap do r = u32(i)
		for &r, i in group_target do r = u32(i)
		slice.zero(locked)
		triangle_goal := (count-target)/3
		// 很多候选会因共享顶点被锁住，按目标位置候选误差的 1.5 倍限制本轮。
		edge_goal := triangle_goal/2
		error_goal := edge_goal < len(candidates) ? 1.5*candidates[edge_goal].error : math.INF_F32
		collapsed_triangles := 0
		collapses := 0
		for c in candidates {
			if c.error > error_limit || collapsed_triangles >= triangle_goal do break
			if c.error > error_goal && collapsed_triangles > triangle_goal/6 do break
			r0 := remap[c.from]
			r1 := remap[c.to]
			if locked[r0] || locked[r1] do continue
			if has_flips(work, remap, scaled, group_target, triangle_offsets, triangle_list, r0, r1) do continue
			if breaks_link(work, remap, group_target, triangle_offsets, triangle_list, r0, r1) do continue
			kind := kinds[c.from]
			if kind == .Seam {
				// 缝的另一侧必须沿同一条缝一起折叠，否则两侧 UV 断开。
				s0 := wedge[c.from]
				s1 := wedge[c.to]
				if open_out[s0] != s1 && open_in[s0] != s1 do continue
				collapse_remap[s0] = s1
			}
			collapse_remap[c.from] = c.to
			quadric_add(&quadrics[r1], quadrics[r0])
			group_target[r0] = r1
			locked[r0] = true
			locked[r1] = true
			collapsed_triangles += kind == .Border ? 1 : 2
			collapses += 1
			result_error = max(result_error, c.error)
		}
		if collapses == 0 do break

		remap_loops(open_out, collapse_remap)
		remap_loops(open_in, collapse_remap)
		write := 0
		for t := 0; t < count; t += 3 {
			a := collapse_remap[work[t]]
			b := collapse_remap[work[t+1]]
			c := collapse_remap[work[t+2]]
			if remap[a] == remap[b] || remap[b] == remap[c] || remap[a] == remap[c] do continue
			work[write] = a
			work[write+1] = b
			work[write+2] = c
			write += 3
		}
		count = write
	}

	result = make([]u32, count, allocator)
	copy(result, work[:count])
	return result, math.sqrt(result_error), true
}

// ==============================================================================
// 顶点分类
// ==============================================================================

@(private)
Vertex_Kind :: enum u8 {
	Locked, // 未使用、非流形或多重属性拆分：保持不动
	Manifold, // 内部顶点：可折向任意相邻顶点
	Border, // 位于开放边界：只能沿边界折向边界顶点
	Seam, // 两份属性拆分的缝：只能沿缝折叠，另一侧同步
}

@(private)
Collapse :: struct {
	from, to: u32,
	error: f32,
}

@(private)
NO_EDGE :: ~u32(0)
@(private)
MANY_EDGES :: ~u32(0)-1

// 原始顶点空间中没有反向边的有向边：open_out[a] = b、open_in[b] = a；多于一条记为 MANY_EDGES。
@(private)
open_edges :: proc(indices: []u32, open_out, open_in: []u32) {
	n := len(open_out)
	offsets := make([]u32, n+1)
	defer delete(offsets)
	targets := make([]u32, len(indices))
	defer delete(targets)
	for index in indices do offsets[index+1] += 1
	for i in 0..<n do offsets[i+1] += offsets[i]
	cursor := make([]u32, n)
	defer delete(cursor)
	copy(cursor, offsets[:n])
	for t := 0; t < len(indices); t += 3 {
		for e in 0..<3 {
			a := indices[t+e]
			targets[cursor[a]] = indices[t+(e+1)%3]
			cursor[a] += 1
		}
	}
	for &v in open_out do v = NO_EDGE
	for &v in open_in do v = NO_EDGE
	for a in 0..<n {
		for k in offsets[a]..<offsets[a+1] {
			b := targets[k]
			reverse := false
			for j in offsets[b]..<offsets[b+1] {
				if targets[j] == u32(a) {
					reverse = true
					break
				}
			}
			if reverse do continue
			set_loop(&open_out[a], b)
			set_loop(&open_in[b], u32(a))
		}
	}
}

@(private)
set_loop :: proc(slot: ^u32, value: u32) {
	if slot^ == NO_EDGE {
		slot^ = value
	} else if slot^ != value {
		slot^ = MANY_EDGES
	}
}

@(private)
classify :: proc(kinds: []Vertex_Kind, used: []bool, remap, wedge, open_out, open_in: []u32) {
	for i in 0..<len(kinds) {
		kinds[i] = .Locked
		if !used[i] do continue
		w := wedge[i]
		if w == u32(i) {
			if open_out[i] == NO_EDGE && open_in[i] == NO_EDGE {
				kinds[i] = .Manifold
			} else if open_out[i] < MANY_EDGES && open_in[i] < MANY_EDGES {
				kinds[i] = .Border
			}
		} else if wedge[w] == u32(i) {
			if open_out[i] >= MANY_EDGES || open_in[i] >= MANY_EDGES do continue
			if open_out[w] >= MANY_EDGES || open_in[w] >= MANY_EDGES do continue
			// 一侧 a→b 开放，另一侧以相同位置 b'→a' 开放，才是可成对折叠的缝。
			if remap[open_out[i]] == remap[open_in[w]] && remap[open_in[i]] == remap[open_out[w]] {
				kinds[i] = .Seam
			}
		}
	}
}

@(private)
can_collapse :: proc(kinds: []Vertex_Kind, open_out, open_in: []u32, from, to: u32) -> bool {
	switch kinds[from] {
	case .Manifold:
		return true
	case .Border, .Seam:
		return kinds[to] == kinds[from] && (open_out[from] == to || open_in[from] == to)
	case .Locked:
		return false
	}
	return false
}

// ==============================================================================
// 误差二次型
// ==============================================================================

// 对称矩阵 A（6 项）、向量 b、常数 c 与累计权重 w；误差按权重归一为平均平方距离。
@(private)
Quadric :: struct {
	a00, a11, a22, a10, a20, a21: f32,
	b0, b1, b2, c, w: f32,
}

@(private)
quadric_plane :: proc(n: [3]f32, d, weight: f32) -> Quadric {
	return {
		a00 = n[0]*n[0]*weight, a11 = n[1]*n[1]*weight, a22 = n[2]*n[2]*weight,
		a10 = n[1]*n[0]*weight, a20 = n[2]*n[0]*weight, a21 = n[2]*n[1]*weight,
		b0 = n[0]*d*weight, b1 = n[1]*d*weight, b2 = n[2]*d*weight,
		c = d*d*weight, w = weight,
	}
}

@(private)
quadric_add :: proc(q: ^Quadric, o: Quadric) {
	q.a00 += o.a00
	q.a11 += o.a11
	q.a22 += o.a22
	q.a10 += o.a10
	q.a20 += o.a20
	q.a21 += o.a21
	q.b0 += o.b0
	q.b1 += o.b1
	q.b2 += o.b2
	q.c += o.c
	q.w += o.w
}

@(private)
quadric_error :: proc(q: Quadric, p: [3]f32) -> f32 {
	x := p[0]
	y := p[1]
	z := p[2]
	rx := q.b0+q.a00*x+q.a10*y+q.a20*z
	ry := q.b1+q.a10*x+q.a11*y+q.a21*z
	rz := q.b2+q.a20*x+q.a21*y+q.a22*z
	r := x*rx+y*ry+z*rz+q.b0*x+q.b1*y+q.b2*z+q.c
	return q.w > 0 ? abs(r)/q.w : 0
}

// ==============================================================================
// 边折叠
// ==============================================================================

// r0 移到 r1 后，r0 周围不含 r1 的三角形法线不能反向或退化。
// 本轮已折叠的邻居按目标位置计算。
@(private)
has_flips :: proc(work, remap: []u32, scaled: [][3]f32, group_target, offsets, list: []u32, r0, r1: u32) -> bool {
	p0 := scaled[r0]
	p1 := scaled[r1]
	for k in offsets[r0]..<offsets[r0+1] {
		t := list[k]
		a := remap[work[t]]
		b := remap[work[t+1]]
		c := remap[work[t+2]]
		// 旋转使 r0 位于首位，保持绕向。
		other_b := b
		other_c := c
		if b == r0 {
			other_b = c
			other_c = a
		} else if c == r0 {
			other_b = a
			other_c = b
		}
		if other_b == r1 || other_c == r1 do continue
		pb := scaled[group_target[other_b]]
		pc := scaled[group_target[other_c]]
		before := cross(pb-p0, pc-p0)
		after := cross(pb-p1, pc-p1)
		if dot(before, after) <= 0 do return true
	}
	return false
}

// 连接条件：r0 与 r1 的公共邻居只能是共享三角形的对角顶点，否则折叠会产生非流形边或重复面。
// 公共邻居超过 64 个时保守拒绝。
@(private)
breaks_link :: proc(work, remap, group_target, offsets, list: []u32, r0, r1: u32) -> bool {
	common: [64]u32
	common_count := 0
	shared := 0
	for k in offsets[r0]..<offsets[r0+1] {
		t := list[k]
		contains_r1 := false
		for j in 0..<3 {
			if group_target[remap[work[t+u32(j)]]] == r1 do contains_r1 = true
		}
		if contains_r1 do shared += 1
		for j in 0..<3 {
			x := group_target[remap[work[t+u32(j)]]]
			if x == r0 || x == r1 || !is_neighbor(work, remap, group_target, offsets, list, r1, x) do continue
			seen := false
			for c in common[:common_count] do seen ||= c == x
			if seen do continue
			if common_count == len(common) do return true
			common[common_count] = x
			common_count += 1
		}
	}
	return common_count > shared
}

@(private)
is_neighbor :: proc(work, remap, group_target, offsets, list: []u32, r, x: u32) -> bool {
	for k in offsets[r]..<offsets[r+1] {
		t := list[k]
		for j in 0..<3 {
			if group_target[remap[work[t+u32(j)]]] == x do return true
		}
	}
	return false
}

// 折叠后更新开放边环：邻居被折叠时改指向折叠目标；折向自身时跳过被吞并的顶点。
@(private)
remap_loops :: proc(loop, collapse_remap: []u32) {
	for &l, i in loop {
		if l >= MANY_EDGES do continue
		r := collapse_remap[l]
		l = r == u32(i) ? loop[l] : r
	}
}

@(private)
cross :: proc(a, b: [3]f32) -> [3]f32 {
	return {a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0]}
}

@(private)
dot :: proc(a, b: [3]f32) -> f32 {
	return a[0]*b[0]+a[1]*b[1]+a[2]*b[2]
}

@(private)
length :: proc(v: [3]f32) -> f32 {
	return math.sqrt(dot(v, v))
}
