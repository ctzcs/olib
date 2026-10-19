// rendering3d:uniforms3d —— cbuffer 的 CPU 侧打包（与光照/材质模型无关的部分）。
//
// 布局按 SDL std140 规则手排（全 vec4，无 padding 陷阱）。矩阵按 kit/world
// Matrix4 的存储（c0..c3）依次写 64B，HLSL 默认 column_major 读到的就是同一个
// 矩阵；world 是行向量约定（v' = v * M），所以着色器里要写 mul(v, M)。
// 光照、材质等块的布局属于具体着色器，由游戏用 mat.std140_write_* 自行打包
//（参考 olib_sample forward3d/uniforms.odin）。
package rendering3d

import mat "olib:kit/rendering/material"
import world "olib:kit/world"

// 分区：
//   顶点矩阵块 —— WVP + World（顶点槽 0 的常用约定）
//   骨骼 palette —— 两块各 64 关节

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
	if len(buf) < VERTEX_MATRIX_BLOCK_SIZE do return false
	mat.std140_write_matrix(buf, 0, wvp)
	mat.std140_write_matrix(buf, 64, world_matrix)
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
	if len(buf0) < 64 * 64 || len(buf1) < 64 * 64 do return false

	for i in 0..<64 {
		if i < len(palette) {
			mat.std140_write_matrix(buf0, i * 64, palette[i])
		} else {
			mat.std140_write_matrix(buf0, i * 64, world.MATRIX4_IDENTITY)
		}
		if i + 64 < len(palette) {
			mat.std140_write_matrix(buf1, i * 64, palette[i + 64])
		} else {
			mat.std140_write_matrix(buf1, i * 64, world.MATRIX4_IDENTITY)
		}
	}
	return true
}
