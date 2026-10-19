package shader_lab

// 程序化几何：示例没有模型资源，直接在代码里生成 dasset primitive，
// 再走与真实模型相同的 r3d.mesh_upload 路径。三角形从外侧看为 CCW（与 dasset 约定一致）。

import "core:math"

import dasset "olib:core/dasset"

// 分区：
//   立方体 / 球体 —— 生成
//   释放

// ==============================================================================
// 立方体 / 球体
// ==============================================================================

// 中心在原点、边长 size 的立方体：每面 4 个顶点（法线不共享）。
make_cube :: proc(size: f32, material: dasset.Dasset_Material) -> dasset.Dasset_Primitive {
	h := size * 0.5
	// 每面：法线 n 与面内两轴 u、v（u × v = n，保证外侧看 CCW）
	faces := [6][3][3]f32{
		{{1, 0, 0}, {0, 0, -1}, {0, 1, 0}},
		{{-1, 0, 0}, {0, 0, 1}, {0, 1, 0}},
		{{0, 1, 0}, {1, 0, 0}, {0, 0, -1}},
		{{0, -1, 0}, {1, 0, 0}, {0, 0, 1}},
		{{0, 0, 1}, {1, 0, 0}, {0, 1, 0}},
		{{0, 0, -1}, {-1, 0, 0}, {0, 1, 0}},
	}
	corners := [4][2]f32{{-1, -1}, {1, -1}, {1, 1}, {-1, 1}}

	p := dasset.Dasset_Primitive{
		vertices   = make([]dasset.Dasset_Vertex, 24),
		indices    = make([]u32, 36),
		skin_index = -1,
		material   = material,
		bounds     = {min = {-h, -h, -h}, max = {h, h, h}},
	}
	for face, f in faces {
		n := face[0]
		u := face[1]
		v := face[2]
		for c, i in corners {
			p.vertices[f*4 + i] = {
				position = (n + u*c[0] + v*c[1]) * h,
				normal   = n,
				uv       = {(c[0] + 1) * 0.5, (1 - c[1]) * 0.5},
				tangent  = {u[0], u[1], u[2], 1},
			}
		}
		base := u32(f * 4)
		copy(p.indices[f*6:], []u32{base, base + 1, base + 2, base, base + 2, base + 3})
	}
	return p
}

// 中心在原点、半径 radius 的经纬球：rings 条纬线带 × segments 条经线。
make_sphere :: proc(radius: f32, rings, segments: int, material: dasset.Dasset_Material) -> dasset.Dasset_Primitive {
	p := dasset.Dasset_Primitive{
		vertices   = make([]dasset.Dasset_Vertex, (rings + 1) * (segments + 1)),
		indices    = make([]u32, rings * segments * 6),
		skin_index = -1,
		material   = material,
		bounds     = {min = {-radius, -radius, -radius}, max = {radius, radius, radius}},
	}
	for ring in 0..=rings {
		theta := f32(ring) / f32(rings) * math.PI // 0 = 北极（+Y）
		for seg in 0..=segments {
			phi := f32(seg) / f32(segments) * 2 * math.PI
			n := [3]f32{math.sin(theta) * math.cos(phi), math.cos(theta), math.sin(theta) * math.sin(phi)}
			p.vertices[ring * (segments + 1) + seg] = {
				position = n * radius,
				normal   = n,
				uv       = {f32(seg) / f32(segments), f32(ring) / f32(rings)},
				tangent  = {-math.sin(phi), 0, math.cos(phi), 1},
			}
		}
	}
	i := 0
	for ring in 0..<rings {
		for seg in 0..<segments {
			a := u32(ring * (segments + 1) + seg) // a b  （ring 向下、seg 绕 +Y 转向 -Z 侧）
			b := a + 1                            // d c
			d := a + u32(segments + 1)
			c := d + 1
			copy(p.indices[i:], []u32{a, b, c, a, c, d})
			i += 6
		}
	}
	return p
}

// ==============================================================================
// 释放
// ==============================================================================

primitive_dispose :: proc(p: ^dasset.Dasset_Primitive) {
	delete(p.vertices)
	delete(p.indices)
	p^ = {}
}
