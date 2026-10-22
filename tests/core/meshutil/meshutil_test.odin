#+test
package meshutil

import "core:math"
import "core:testing"

// 分区：测试网格 / 统计与边 / 顶点整理 / 简化

// ==============================================================================
// 测试网格
// ==============================================================================

// 每面独立 4 顶点的立方体（平直着色），外侧 CCW。
@(private)
test_cube :: proc() -> ([dynamic][3]f32, [dynamic]u32) {
	positions: [dynamic][3]f32
	indices: [dynamic]u32
	for axis in 0..<3 {
		for side in ([2]f32{-1, 1}) {
			base := u32(len(positions))
			corners := [4][2]f32{{-1, -1}, {1, -1}, {1, 1}, {-1, 1}}
			for corner in corners {
				p: [3]f32
				p[axis] = side
				p[(axis+1)%3] = corner[0]
				p[(axis+2)%3] = corner[1]
				append(&positions, p)
			}
			if side > 0 {
				append(&indices, base, base+1, base+2, base, base+2, base+3)
			} else {
				append(&indices, base, base+2, base+1, base, base+3, base+2)
			}
		}
	}
	return positions, indices
}

// XZ 平面上 cells×cells 的网格，带开放边界。
@(private)
test_plane :: proc(cells: int) -> ([dynamic][3]f32, [dynamic]u32) {
	positions: [dynamic][3]f32
	indices: [dynamic]u32
	for z in 0..=cells {
		for x in 0..=cells do append(&positions, [3]f32{f32(x), 0, f32(z)})
	}
	row := u32(cells+1)
	for z in 0..<cells {
		for x in 0..<cells {
			a := u32(z)*row+u32(x)
			append(&indices, a, a+row, a+1, a+1, a+row, a+row+1)
		}
	}
	return positions, indices
}

// UV 球：经线 0 与 2π 处重复顶点形成属性缝，两极也重复（退化三角形已移除）。
@(private)
test_sphere :: proc(segments, rings: int) -> ([dynamic][3]f32, [dynamic]u32) {
	positions: [dynamic][3]f32
	indices: [dynamic]u32
	for r in 0..=rings {
		phi := f32(r)*math.PI/f32(rings)
		for s in 0..=segments {
			theta := f32(s)*2*math.PI/f32(segments)
			if s == segments do theta = 0
			p := [3]f32{math.sin(phi)*math.cos(theta), math.cos(phi), math.sin(phi)*math.sin(theta)}
			if r == 0 || r == rings do p = {0, math.cos(phi), 0}
			append(&positions, p)
		}
	}
	row := u32(segments+1)
	for r in 0..<rings {
		for s in 0..<segments {
			a := u32(r)*row+u32(s)
			append(&indices, a, a+1, a+row, a+1, a+row+1, a+row)
		}
	}
	kept := remove_degenerate(positions[:], indices[:])
	resize(&indices, len(kept))
	return positions, indices
}

// ==============================================================================
// 统计与边
// ==============================================================================

@(test)
stats_cube_seams :: proc(t: ^testing.T) {
	positions, indices := test_cube()
	defer delete(positions)
	defer delete(indices)
	s := stats(positions[:], indices[:])
	testing.expect_value(t, s.vertices, 24)
	testing.expect_value(t, s.used_vertices, 24)
	testing.expect_value(t, s.unique_positions, 8)
	testing.expect_value(t, s.triangles, 12)
	testing.expect_value(t, s.edges, 18)
	testing.expect_value(t, s.seam_edges, 12) // 立方体棱：两面使用不同顶点
	testing.expect_value(t, s.border_edges, 0)
	testing.expect_value(t, s.non_manifold_edges, 0)
	testing.expect_value(t, s.degenerate_triangles, 0)
	testing.expect(t, s.bounds.min == [3]f32{-1, -1, -1} && s.bounds.max == [3]f32{1, 1, 1})
}

@(test)
edges_plane_border :: proc(t: ^testing.T) {
	positions, indices := test_plane(4)
	defer delete(positions)
	defer delete(indices)
	list, ok := edges(positions[:], indices[:])
	defer delete(list)
	testing.expect(t, ok)
	border := 0
	interior := 0
	for e in list {
		#partial switch e.kind {
		case .Border:
			border += 1
		case .Interior:
			interior += 1
		}
	}
	testing.expect_value(t, border, 16)
	testing.expect_value(t, interior, len(list)-16)
	_, bad := edges(positions[:], []u32{0, 1, 999})
	testing.expect(t, !bad, "out-of-range index rejected")
	s := stats(positions[:], []u32{0, 1, 999})
	testing.expect_value(t, s.invalid_indices, 1)
}

@(test)
edges_non_manifold :: proc(t: ^testing.T) {
	positions := [][3]f32{{0, 0, 0}, {1, 0, 0}, {0, 1, 0}, {0, -1, 0}, {0, 0, 1}}
	indices := []u32{0, 1, 2, 1, 0, 3, 0, 1, 4}
	s := stats(positions, indices)
	testing.expect_value(t, s.non_manifold_edges, 1)
	testing.expect_value(t, s.border_edges, 6)
}

// ==============================================================================
// 顶点整理
// ==============================================================================

@(test)
weld_and_compact :: proc(t: ^testing.T) {
	Vertex :: struct {
		position: [3]f32,
		uv: [2]f32,
	}
	vertices := []Vertex{
		{{0, 0, 0}, {0, 0}}, {{1, 0, 0}, {1, 0}}, {{0, 1, 0}, {0, 1}},
		{{1, 0, 0}, {1, 0}}, {{0, 1, 0}, {0, 1}}, {{1, 1, 0}, {1, 1}},
		{{1, 0, 0}, {0.5, 0}}, // 位置重复但 UV 不同：保留
	}
	original := []u32{0, 1, 2, 3, 5, 4, 6, 5, 4}
	indices := make([]u32, len(original))
	defer delete(indices)
	copy(indices, original)
	welded, ok := weld(vertices, indices)
	defer delete(welded)
	testing.expect(t, ok)
	testing.expect_value(t, len(welded), 5)
	testing.expect(t, indices[3] == 1 && indices[5] == 2, "duplicates point at first occurrence")
	for index, i in indices do testing.expect(t, welded[index] == vertices[original[i]])

	unused := []Vertex{{{9, 9, 9}, {}}, {{0, 0, 0}, {}}, {{1, 0, 0}, {}}, {{0, 1, 0}, {}}}
	tri := []u32{3, 1, 2}
	compacted, compact_ok := compact(unused, tri)
	defer delete(compacted)
	testing.expect(t, compact_ok)
	testing.expect_value(t, len(compacted), 3)
	testing.expect(t, tri[0] == 0 && tri[1] == 1 && tri[2] == 2, "ordered by first use")
	testing.expect(t, compacted[0].position == [3]f32{0, 1, 0})
	_, bad := compact(unused, []u32{7})
	testing.expect(t, !bad)
}

@(test)
remove_degenerate_triangles :: proc(t: ^testing.T) {
	positions := [][3]f32{{0, 0, 0}, {1, 0, 0}, {0, 1, 0}, {0, 0, 0}}
	indices := []u32{0, 1, 2, 0, 0, 1, 3, 1, 0, 2, 1, 0}
	kept := remove_degenerate(positions, indices)
	testing.expect_value(t, len(kept), 6)
	testing.expect(t, kept[3] == 2 && kept[4] == 1 && kept[5] == 0)
}

// ==============================================================================
// 简化
// ==============================================================================

@(test)
simplify_flat_plane_keeps_corners :: proc(t: ^testing.T) {
	positions, indices := test_plane(16)
	defer delete(positions)
	defer delete(indices)
	result, error, ok := simplify(positions[:], indices[:], 6, 0.001)
	defer delete(result)
	testing.expect(t, ok)
	testing.expectf(t, len(result) <= 24, "flat plane collapses almost fully, got %d", len(result))
	testing.expect(t, error < 0.0001)
	corners := [4][3]f32{{0, 0, 0}, {16, 0, 0}, {0, 0, 16}, {16, 0, 16}}
	for corner in corners {
		found := false
		for index in result do found ||= positions[index] == corner
		testing.expect(t, found, "border corners are preserved")
	}
	s := stats(positions[:], result)
	testing.expect_value(t, s.degenerate_triangles, 0)
	testing.expect(t, s.bounds.min == [3]f32{0, 0, 0} && s.bounds.max == [3]f32{16, 0, 16})
}

@(test)
simplify_sphere_keeps_seam_closed :: proc(t: ^testing.T) {
	positions, indices := test_sphere(32, 16)
	defer delete(positions)
	defer delete(indices)
	before := stats(positions[:], indices[:])
	testing.expect_value(t, before.border_edges, 0)
	testing.expect(t, before.seam_edges > 0)
	target := len(indices)/4
	result, error, ok := simplify(positions[:], indices[:], target, 0.2)
	defer delete(result)
	testing.expect(t, ok)
	testing.expectf(t, len(result) <= len(indices)/2, "reduced %d -> %d", len(indices), len(result))
	testing.expect(t, error > 0 && error < 0.2)
	after := stats(positions[:], result)
	testing.expect_value(t, after.border_edges, 0) // 缝两侧成对折叠，不开裂
	testing.expect_value(t, after.non_manifold_edges, 0)
	testing.expect_value(t, after.degenerate_triangles, 0)

	// 误差上限阻止过度简化。
	strict, strict_error, _ := simplify(positions[:], indices[:], 0, 0.0001)
	defer delete(strict)
	testing.expect(t, len(strict) == len(indices) && strict_error == 0)
	_, _, bad := simplify(positions[:], []u32{0, 1}, 0)
	testing.expect(t, !bad)
}
