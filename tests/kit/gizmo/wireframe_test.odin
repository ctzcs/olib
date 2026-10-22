#+test
package gizmo

import "core:testing"

import meshutil "olib:core/meshutil"
import foster "olib:foster"
import world "olib:kit/world"

// 分区：线框网格

// ==============================================================================
// 线框网格
// ==============================================================================

@(test)
wireframe_mesh_pixel_width_and_kinds :: proc(t: ^testing.T) {
	c: world.Camera3D
	world.camera3d_init(&c, 960, 600)
	world.camera3d_set_position(&c, {0, 0, 6})
	world.camera3d_set_target(&c, {})
	viewport := foster.Rect{80, 40, 960, 600}
	// 两个三角形组成的四边形：对角线为内部边，四周为边界。
	positions := [][3]f32{{-1, -1, 0}, {1, -1, 0}, {1, 1, 0}, {-1, 1, 0}}
	indices := []u32{0, 1, 2, 0, 2, 3}
	edges, ok := meshutil.edges(positions, indices)
	defer delete(edges)
	testing.expect(t, ok && len(edges) == 5)
	vertices: [dynamic]Vertex3D
	defer delete(vertices)

	for scale in ([]f32{1, 2}) {
		wireframe_mesh(&vertices, &c, positions, edges, world.MATRIX4_IDENTITY, viewport, scale)
		testing.expect_value(t, len(vertices), 30)
		// 底边 0→1 水平：四边形两侧在屏幕上相距 line_width*scale 像素。
		for edge, i in edges {
			if !((edge.a == 0 && edge.b == 1) || (edge.a == 1 && edge.b == 0)) do continue
			low, low_ok := project(&c, vertices[i*6].position, viewport)
			high, high_ok := project(&c, vertices[i*6+5].position, viewport)
			testing.expect(t, low_ok && high_ok)
			width := abs(high.y-low.y)
			expected := DEFAULT_WIREFRAME_STYLE.line_width*scale
			testing.expectf(t, abs(width-expected) < expected*0.05, "width %v, expected %v", width, expected)
		}
	}
	default_style := DEFAULT_WIREFRAME_STYLE
	for edge, i in edges {
		color := default_style.colors[edge.kind]
		testing.expect(t, vertices[i*6].color[3] == f32(color.A)/255)
		testing.expect(t, edge.kind == .Border || edge.kind == .Interior)
	}

	// 只看边界：内部边颜色透明即跳过。
	style := DEFAULT_WIREFRAME_STYLE
	style.colors[.Interior].A = 0
	wireframe_mesh(&vertices, &c, positions, edges, world.MATRIX4_IDENTITY, viewport, 1, style)
	testing.expect_value(t, len(vertices), 24)

	// 模型矩阵生效：平移到相机后方时全部丢弃，跨过近裁面的边被截断。
	wireframe_mesh(&vertices, &c, positions, edges, world.matrix4_translation(0, 0, 10), viewport)
	testing.expect_value(t, len(vertices), 0)
	crossing := []meshutil.Edge{{0, 1, .Border}}
	through := [][3]f32{{0.5, 0, 0}, {0.5, 0, 10}}
	wireframe_mesh(&vertices, &c, through, crossing, world.MATRIX4_IDENTITY, viewport)
	testing.expect_value(t, len(vertices), 6)
	for v in vertices {
		depth := dot(v.position-c.position, world.camera3d_forward(&c))
		testing.expect(t, depth > c.near_clip*0.99)
	}

	// 越界边、相机视口不匹配直接忽略。
	bad := []meshutil.Edge{{0, 9, .Border}}
	wireframe_mesh(&vertices, &c, positions, bad, world.MATRIX4_IDENTITY, viewport)
	testing.expect_value(t, len(vertices), 0)
	wireframe_mesh(&vertices, &c, positions, edges, world.MATRIX4_IDENTITY, {0, 0, 480, 300})
	testing.expect_value(t, len(vertices), 0)
}
