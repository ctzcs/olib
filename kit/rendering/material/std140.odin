package material

// std140 写入：手写 cbuffer 的 CPU 侧打包（游戏自己的光照/材质块、gizmo、ShaderLab 帧块）。
// 布局按 SDL std140 规则手排（全 vec4，无 padding 陷阱）。矩阵按 kit/world Matrix4 的存储
// （c0..c3）依次写 64B，HLSL 默认 column_major 读到的就是同一个矩阵；world 是行向量约定
// （v' = v * M），所以着色器里要写 mul(v, M)。
// 本包被 tools/shaders 以相对路径引用，不 import kit/world，矩阵参数接受任意 4×4 f32 类型。

// 在 offset 处写一个 4×4 f32 矩阵（如 world.Matrix4；按存储顺序每 16B 一列，共 64B）。越界的列跳过。
std140_write_matrix :: proc(buf: []u8, offset: int, m: $M) where size_of(M) == 64 {
	columns := transmute([4][4]f32)m
	for column, i in columns do std140_write_vec4(buf, offset + i*16, column)
}

// 在 offset 处写一个 vec4（16B，小端，按 f32 位型直写）。越界时不写。
std140_write_vec4 :: proc(buf: []u8, offset: int, v: [4]f32) {
	if offset < 0 || offset + 16 > len(buf) do return
	for i in 0..<4 {
		bits := transmute(u32)v[i]
		base := offset + i * 4
		buf[base] = u8(bits)
		buf[base + 1] = u8(bits >> 8)
		buf[base + 2] = u8(bits >> 16)
		buf[base + 3] = u8(bits >> 24)
	}
}
