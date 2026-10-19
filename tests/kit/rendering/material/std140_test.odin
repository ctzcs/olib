#+test
package material

import "core:testing"

import world "olib:kit/world"

@(test)
std140_writes_little_endian_and_skips_out_of_range :: proc(t: ^testing.T) {
	buf: [80]u8
	m := world.matrix4_translation(1, 2, 3)
	std140_write_matrix(buf[:], 0, m)
	std140_write_vec4(buf[:], 64, {1, -2, 0.5, 8})
	read := proc(buf: []u8, offset: int) -> [4]f32 {
		v: [4]f32
		for i in 0..<4 {
			b := buf[offset + i*4:]
			v[i] = transmute(f32)(u32(b[0]) | u32(b[1]) << 8 | u32(b[2]) << 16 | u32(b[3]) << 24)
		}
		return v
	}
	testing.expect(t, world.Matrix4{read(buf[:], 0), read(buf[:], 16), read(buf[:], 32), read(buf[:], 48)} == m)
	testing.expect(t, read(buf[:], 64) == [4]f32{1, -2, 0.5, 8})

	// 越界的 vec4 不写，矩阵只写放得下的列
	std140_write_vec4(buf[:8], 0, {9, 9, 9, 9})
	std140_write_vec4(buf[:], -16, {9, 9, 9, 9})
	testing.expect(t, read(buf[:], 0) == m.c0)
	std140_write_matrix(buf[:40], 0, world.MATRIX4_IDENTITY)
	testing.expect(t, read(buf[:], 0) == world.MATRIX4_IDENTITY.c0 && read(buf[:], 32) == m.c2)
}
