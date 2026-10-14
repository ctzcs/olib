// rendering3d:uniforms3d —— cbuffer 的 CPU 侧打包（与光照/材质模型无关的部分）。
//
// 布局按 SDL std140 规则手排（全 vec4，无 padding 陷阱）。矩阵按 kit/world
// Matrix4 的存储（c0..c3）依次写 64B，HLSL 默认 column_major 读到的就是同一个
// 矩阵；world 是行向量约定（v' = v * M），所以着色器里要写 mul(v, M)。
// 光照、材质等块的布局属于具体着色器，由游戏用 std140_write_* 自行打包
//（参考 olib_sample forward3d/uniforms.odin）。
package rendering3d

import world "olib:kit/world"

// 分区：
//   顶点矩阵块 —— WVP + World（顶点槽 0 的常用约定）
//   骨骼 palette —— 两块各 64 关节
//   std140 写入 —— 矩阵/vec4（公开，供游戏打包自己的 cbuffer）

// ------------------------------------------------------------------------------
// 顶点矩阵块 —— WVP + World
// ------------------------------------------------------------------------------

// VertexMatrixBlock（128B）：WVP + World。
Vertex_Matrix_Block :: struct {
	world_view_projection: world.Matrix4,
	world:                 world.Matrix4,
}

VERTEX_MATRIX_BLOCK_SIZE :: 128

// 打包 WVP/World。buf 长度不足返回 false。
pack_vertex_matrix_block :: proc(buf: []u8, wvp, world_matrix: world.Matrix4) -> bool {
	if len(buf) < VERTEX_MATRIX_BLOCK_SIZE { return false }
	std140_write_matrix(buf, 0, wvp)
	std140_write_matrix(buf, 64, world_matrix)
	return true
}

// ------------------------------------------------------------------------------
// 骨骼 palette —— 两块各 64 关节（各 4KB）
// ------------------------------------------------------------------------------

// SDL 3.4 Vulkan 每槽 UBO 上限 4KB：128 关节拆两块（0-63 / 64-127），
// 槽位由调用方决定。palette 不足的位置写单位阵兜底（着色器端下标越界防护）。
// buf0 与 buf1 必须是两块不重叠的内存。
pack_joint_palette :: proc(
	buf0, buf1: []u8,
	palette: []world.Matrix4,
) -> bool {
	if len(buf0) < 64 * 64 || len(buf1) < 64 * 64 { return false }

	for i in 0..<64 {
		if i < len(palette) {
			std140_write_matrix(buf0, i * 64, palette[i])
		} else {
			std140_write_matrix(buf0, i * 64, world.MATRIX4_IDENTITY)
		}
		if i + 64 < len(palette) {
			std140_write_matrix(buf1, i * 64, palette[i + 64])
		} else {
			std140_write_matrix(buf1, i * 64, world.MATRIX4_IDENTITY)
		}
	}
	return true
}

// ------------------------------------------------------------------------------
// std140 写入 —— 矩阵/vec4（小端，按 f32 位型直写）
// ------------------------------------------------------------------------------

// 在 offset 处写一个 Matrix4（c0..c3 依次 16B，共 64B）。越界的部分跳过。
std140_write_matrix :: proc(buf: []u8, offset: int, m: world.Matrix4) {
	std140_write_vec4(buf, offset, m.c0)
	std140_write_vec4(buf, offset + 16, m.c1)
	std140_write_vec4(buf, offset + 32, m.c2)
	std140_write_vec4(buf, offset + 48, m.c3)
}

// 在 offset 处写一个 vec4（16B）。越界时不写。
std140_write_vec4 :: proc(buf: []u8, offset: int, v: [4]f32) {
	if offset < 0 || offset + 16 > len(buf) { return }
	for i in 0..<4 {
		bits := transmute(u32)v[i]
		base := offset + i * 4
		buf[base] = u8(bits)
		buf[base + 1] = u8(bits >> 8)
		buf[base + 2] = u8(bits >> 16)
		buf[base + 3] = u8(bits >> 24)
	}
}
