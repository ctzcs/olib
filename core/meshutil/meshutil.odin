// meshutil —— 三角网格的 CPU 工具：统计、拓扑边、焊接、压缩与简化，不依赖 GPU。
//
// 输入统一为位置 [][3]f32 + 三角形索引 []u32（每 3 个一组，与 dasset 一致）。
// 位置相同的顶点视为同一几何点：UV/法线拆分产生的“缝”不算破洞。
package meshutil

import "core:hash"
import "core:mem"

import dasset "olib:core/dasset"

// 分区：
//   类型 —— Stats / Edge
//   查询 —— stats / edges / primitive_positions
//   顶点整理 —— weld / compact / remove_degenerate
//   内部 —— 索引校验 / 位置分组

// ==============================================================================
// 类型
// ==============================================================================

// 网格质量概况，用于判断顶点浪费、破洞和退化三角形。
Stats :: struct {
	vertices: int, // 顶点数组长度
	used_vertices: int, // 被索引引用的顶点数；少于 vertices 说明有闲置顶点（compact 可去除）
	unique_positions: int, // 被引用顶点中的不同位置数；与 used_vertices 的差距来自 UV/法线拆分
	triangles: int,
	degenerate_triangles: int, // 重复索引或重合位置的三角形（remove_degenerate 可去除）
	invalid_indices: int, // 越界索引；非零时其余拓扑数据不完整
	edges: int, // 按位置焊接后的唯一边
	border_edges: int, // 只属于一个三角形：破洞或开放边界
	seam_edges: int, // 两侧三角形使用不同顶点（UV/法线拆分）
	non_manifold_edges: int, // 属于三个及以上三角形
	bounds: dasset.Dasset_Bounds, // 被引用顶点的包围盒；无三角形时为 DASSET_BOUNDS_EMPTY
}

Edge_Kind :: enum u8 {
	Interior, // 两个三角形共享且使用相同顶点
	Seam, // 两个三角形共享位置，但顶点不同（属性缝）
	Border, // 只有一个三角形
	Non_Manifold, // 三个及以上三角形
}

// a、b 为第一次出现该边时三角形使用的顶点下标。
Edge :: struct {
	a, b: u32,
	kind: Edge_Kind,
}

// ==============================================================================
// 查询
// ==============================================================================

// 统计网格；只读，临时内存在返回前释放。
stats :: proc(positions: [][3]f32, indices: []u32) -> Stats {
	s := Stats{vertices = len(positions), triangles = len(indices)/3, bounds = dasset.DASSET_BOUNDS_EMPTY}
	for index in indices {
		if int(index) >= len(positions) do s.invalid_indices += 1
	}
	used := make([]bool, len(positions))
	defer delete(used)
	for index in indices {
		if int(index) < len(positions) do used[index] = true
	}
	for u, i in used {
		if !u do continue
		s.used_vertices += 1
		for axis in 0..<3 {
			s.bounds.min[axis] = min(s.bounds.min[axis], positions[i][axis])
			s.bounds.max[axis] = max(s.bounds.max[axis], positions[i][axis])
		}
	}
	if s.invalid_indices > 0 do return s

	remap := position_remap(positions, indices)
	defer delete(remap)
	for r, i in remap {
		if used[i] && r == u32(i) do s.unique_positions += 1
	}
	for t := 0; t+2 < len(indices); t += 3 {
		a := remap[indices[t]]
		b := remap[indices[t+1]]
		c := remap[indices[t+2]]
		if a == b || b == c || a == c do s.degenerate_triangles += 1
	}
	list, _ := edges(positions, indices)
	defer delete(list)
	s.edges = len(list)
	for e in list {
		switch e.kind {
		case .Interior:
		case .Seam:
			s.seam_edges += 1
		case .Border:
			s.border_edges += 1
		case .Non_Manifold:
			s.non_manifold_edges += 1
		}
	}
	return s
}

// 按位置焊接后的唯一边列表，用于线框显示与拓扑检查。退化边（两端同一位置）被忽略。
// 索引越界或长度不是 3 的倍数时返回 nil, false。
edges :: proc(positions: [][3]f32, indices: []u32, allocator := context.allocator) -> ([]Edge, bool) {
	if !indices_valid(positions, indices) do return nil, false
	remap := position_remap(positions, indices)
	defer delete(remap)

	Entry :: struct {
		a, b: u32, // 第一次出现的有向边（原始顶点）
		faces: int,
		seam: bool,
	}
	table := make(map[u64]int, len(indices))
	defer delete(table)
	entries := make([dynamic]Entry, 0, len(indices)/2)
	defer delete(entries)
	for t := 0; t < len(indices); t += 3 {
		for e in 0..<3 {
			i0 := indices[t+e]
			i1 := indices[t+(e+1)%3]
			r0 := remap[i0]
			r1 := remap[i1]
			if r0 == r1 do continue
			key := u64(min(r0, r1))<<32 | u64(max(r0, r1))
			slot, found := table[key]
			if !found {
				table[key] = len(entries)
				append(&entries, Entry{a = i0, b = i1, faces = 1})
				continue
			}
			entry := &entries[slot]
			entry.faces += 1
			// 共享边的另一侧按相反方向使用同一对顶点；顶点不同说明属性在此拆开。
			if !(entry.a == i1 && entry.b == i0) && !(entry.a == i0 && entry.b == i1) do entry.seam = true
		}
	}
	result := make([]Edge, len(entries), allocator)
	for entry, i in entries {
		kind := Edge_Kind.Interior
		if entry.faces == 1 {
			kind = .Border
		} else if entry.faces > 2 {
			kind = .Non_Manifold
		} else if entry.seam {
			kind = .Seam
		}
		result[i] = {entry.a, entry.b, kind}
	}
	return result, true
}

// 复制 dasset primitive（静态或蒙皮）的顶点位置，供本包和线框显示使用。
primitive_positions :: proc(p: ^dasset.Dasset_Primitive, allocator := context.allocator) -> [][3]f32 {
	if dasset.dasset_primitive_is_skinned(p) {
		result := make([][3]f32, len(p.skin_vertices), allocator)
		for v, i in p.skin_vertices do result[i] = v.position
		return result
	}
	result := make([][3]f32, len(p.vertices), allocator)
	for v, i in p.vertices do result[i] = v.position
	return result
}

// ==============================================================================
// 顶点整理
// ==============================================================================

// 合并按字节完全相同的顶点（T 不应含未初始化的填充字节），原地改写 indices，
// 返回新顶点数组（按原顺序保留首次出现者，包含未引用顶点）。索引越界返回 nil, false 且不修改。
weld :: proc(vertices: []$T, indices: []u32, allocator := context.allocator) -> ([]T, bool) {
	for index in indices {
		if int(index) >= len(vertices) do return nil, false
	}
	capacity := table_capacity(len(vertices))
	table := make([]u32, capacity)
	defer delete(table)
	remap := make([]u32, len(vertices))
	defer delete(remap)
	result := make([dynamic]T, 0, len(vertices), allocator)
	for &v, i in vertices {
		slot := bytes_hash(&v, size_of(T)) & u32(capacity-1)
		for {
			stored := table[slot]
			if stored == 0 {
				table[slot] = u32(len(result))+1
				remap[i] = u32(len(result))
				append(&result, v)
				break
			}
			other := &result[stored-1]
			if bytes_equal(other, &v, size_of(T)) {
				remap[i] = stored-1
				break
			}
			slot = (slot+1) & u32(capacity-1)
		}
	}
	for &index in indices do index = remap[index]
	shrink(&result)
	return result[:], true
}

// 删除未被引用的顶点，原地改写 indices，返回按首次引用顺序排列的新顶点数组。
// 按引用顺序排列同时改善 GPU 顶点读取的局部性。索引越界返回 nil, false 且不修改。
compact :: proc(vertices: []$T, indices: []u32, allocator := context.allocator) -> ([]T, bool) {
	for index in indices {
		if int(index) >= len(vertices) do return nil, false
	}
	NONE :: ~u32(0)
	remap := make([]u32, len(vertices))
	defer delete(remap)
	for &r in remap do r = NONE
	count: u32
	for &index in indices {
		if remap[index] == NONE {
			remap[index] = count
			count += 1
		}
		index = remap[index]
	}
	result := make([]T, int(count), allocator)
	for r, i in remap {
		if r != NONE do result[r] = vertices[i]
	}
	return result, true
}

// 原地删除退化三角形（重复索引，或两个顶点位置相同），返回 indices 的有效前缀。
// 不检查面积为零但三点不同的细长三角形。索引越界的三角形同样删除。
remove_degenerate :: proc(positions: [][3]f32, indices: []u32) -> []u32 {
	count := 0
	for t := 0; t+2 < len(indices); t += 3 {
		a := indices[t]
		b := indices[t+1]
		c := indices[t+2]
		n := u32(len(positions))
		if a >= n || b >= n || c >= n do continue
		if positions[a] == positions[b] || positions[b] == positions[c] || positions[a] == positions[c] do continue
		indices[count] = a
		indices[count+1] = b
		indices[count+2] = c
		count += 3
	}
	return indices[:count]
}

// ==============================================================================
// 内部
// ==============================================================================

@(private)
indices_valid :: proc(positions: [][3]f32, indices: []u32) -> bool {
	if len(indices)%3 != 0 do return false
	for index in indices {
		if int(index) >= len(positions) do return false
	}
	return true
}

@(private)
table_capacity :: proc(count: int) -> int {
	capacity := 16
	for capacity < count*2 do capacity *= 2
	return capacity
}

// 被引用顶点按位置分组：remap[i] 为同位置中下标最小的被引用顶点；未引用顶点映射到自身。
// 比较使用 ==，因此 -0 与 +0 视为同一点，NaN 各自独立。调用方保证索引有效。
@(private)
position_remap :: proc(positions: [][3]f32, indices: []u32, allocator := context.allocator) -> []u32 {
	remap := make([]u32, len(positions), allocator)
	for &r, i in remap do r = u32(i)
	used := make([]bool, len(positions))
	defer delete(used)
	for index in indices do used[index] = true
	capacity := table_capacity(len(positions))
	table := make([]u32, capacity)
	defer delete(table)
	for p, i in positions {
		if !used[i] do continue
		slot := position_hash(p) & u32(capacity-1)
		for {
			stored := table[slot]
			if stored == 0 {
				table[slot] = u32(i)+1
				break
			}
			if positions[stored-1] == p {
				remap[i] = stored-1
				break
			}
			slot = (slot+1) & u32(capacity-1)
		}
	}
	return remap
}

// 泛型 proc 未实例化时不算使用 import，字节比较放在普通 proc 里。
@(private)
bytes_hash :: proc(data: rawptr, size: int) -> u32 {
	return hash.fnv32a(mem.byte_slice(data, size))
}

@(private)
bytes_equal :: proc(a, b: rawptr, size: int) -> bool {
	return mem.compare_ptrs(a, b, size) == 0
}

@(private)
position_hash :: proc(p: [3]f32) -> u32 {
	// +0 消除 -0，使相等的坐标得到相同的位模式。
	x := transmute(u32)(p[0]+0)
	y := transmute(u32)(p[1]+0)
	z := transmute(u32)(p[2]+0)
	h := x*73856093 ~ y*19349663 ~ z*83492791
	return h ~ (h >> 16)
}
