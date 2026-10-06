// world:matrix4 —— System.Numerics 语义的 4x4 矩阵（3D 渲染组的地基）。
//
// 约定（与 DragonLib / Foster / ofoster 着色器一致，写死为本包规范）：
//   - 行向量变换：v' = v * M（Vector4.Transform 语义）；
//   - 存储为 4 个列向量 c0..c3，c_j 即输出分量 j 的系数向量
//     （对应 System.Numerics 的 M11/M21/M31/M41 一列）；
//   - 透视深度 [0,1]（D3D/Vulkan/Metal，SDL GPU 全系），近平面即 c2。
//
// 不用 core:math/linalg 的矩阵：它是列向量约定（M*v），与上面相反。
package world

import "core:math"

import foster "ofoster:."

// 分区：
//   类型 —— Vec4 / Matrix4
//   构造 —— translation / scaling / look_at / perspective
//   运算 —— multiply / inverse / transform
//   向量辅助 —— v3 点积/叉积/归一化

// ------------------------------------------------------------------------------
// 类型 —— Vec4 / Matrix4
// ------------------------------------------------------------------------------

Vec4 :: [4]f32

Matrix4 :: struct {
	c0, c1, c2, c3: Vec4, // 列向量：c_j = 输出分量 j 的系数
}

MATRIX4_IDENTITY :: Matrix4{
	{1, 0, 0, 0},
	{0, 1, 0, 0},
	{0, 0, 1, 0},
	{0, 0, 0, 1},
}

// ------------------------------------------------------------------------------
// 构造 —— translation / scaling / look_at / perspective
// ------------------------------------------------------------------------------

matrix4_translation :: proc(x, y, z: f32) -> Matrix4 {
	// 行向量约定：平移在 row4 -> 各列的第 4 分量
	return Matrix4{
		{1, 0, 0, x},
		{0, 1, 0, y},
		{0, 0, 1, z},
		{0, 0, 0, 1},
	}
}

matrix4_scaling :: proc(x, y, z: f32) -> Matrix4 {
	return Matrix4{
		{x, 0, 0, 0},
		{0, y, 0, 0},
		{0, 0, z, 0},
		{0, 0, 0, 1},
	}
}

// 右手系 look-at（System.Numerics CreateLookAt 语义）：
// 相机看向 -Z；z 轴 = normalize(eye - target)。
matrix4_look_at :: proc(eye, target, up: foster.Vec3) -> Matrix4 {
	z := v3_normalize(v3_sub(eye, target))
	if z == (foster.Vec3{0, 0, 0}) {
		return MATRIX4_IDENTITY
	}
	x := v3_normalize(v3_cross(up, z))
	if x == (foster.Vec3{0, 0, 0}) {
		// up 与视线平行：换一个不正交的基
		x = v3_normalize(v3_cross(foster.Vec3{0, 0, 1}, z))
		if x == (foster.Vec3{0, 0, 0}) {
			x = foster.Vec3{1, 0, 0}
		}
	}
	y := v3_cross(z, x)

	// 行向量约定：h_j = dot(v-eye, basis_j) -> 列 j = (basis_j, -dot(basis_j, eye))
	tx := -v3_dot(x, eye)
	ty := -v3_dot(y, eye)
	tz := -v3_dot(z, eye)
	return Matrix4{
		{x[0], x[1], x[2], tx},
		{y[0], y[1], y[2], ty},
		{z[0], z[1], z[2], tz},
		{0, 0, 0, 1},
	}
}

// 透视投影（垂直 FOV，D3D 深度 [0,1]）。
// fov 弧度钳到 (0.1, π-0.1)；near 钳到 >= 0.001；far >= near + 0.001。
matrix4_perspective_fov :: proc(fov_, aspect, near_, far_: f32) -> Matrix4 {
	fov := math.clamp(fov_, 0.1, math.PI - 0.1)
	near := max(near_, 0.001)
	far := max(far_, near + 0.001)

	sy := 1.0 / math.tan(fov * 0.5)
	sx := sy / aspect
	// 右手系（look_at 看 -Z，眼前 z<0）：h_w = -z，深度 [0,1]
	zz := -far / (far - near)
	zw := -near * far / (far - near)

	return Matrix4{
		{sx, 0, 0, 0},
		{0, sy, 0, 0},
		{0, 0, zz, zw},
		{0, 0, -1, 0},
	}
}

// ------------------------------------------------------------------------------
// 运算 —— multiply / inverse / transform
// ------------------------------------------------------------------------------

// 复合矩阵 a*b：行向量约定下先应用 a 再应用 b。
matrix4_multiply :: proc(a, b: Matrix4) -> Matrix4 {
	result: Matrix4
	for j in 0..<4 {
		for i in 0..<4 {
			sum: f32 = 0
			for k in 0..<4 {
				// a 的行 i = 各列 c_k 的第 i 分量；b 的列 j
				sum += matrix4_c(a, k)[i] * matrix4_c(b, j)[k]
			}
			matrix4_set(&result, j, i, sum)
		}
	}
	return result
}

// 一般 4x4 求逆（伴随法）。不可逆返回 identity + false。
matrix4_inverse :: proc(m: Matrix4) -> (Matrix4, bool) {
	// m[row][col]：行 r 列 c 的元素
	at :: proc(x: Matrix4, row, col: int) -> f32 {
		return matrix4_c(x, col)[row]
	}

	a00 := at(m, 0, 0); a01 := at(m, 0, 1); a02 := at(m, 0, 2); a03 := at(m, 0, 3)
	a10 := at(m, 1, 0); a11 := at(m, 1, 1); a12 := at(m, 1, 2); a13 := at(m, 1, 3)
	a20 := at(m, 2, 0); a21 := at(m, 2, 1); a22 := at(m, 2, 2); a23 := at(m, 2, 3)
	a30 := at(m, 3, 0); a31 := at(m, 3, 1); a32 := at(m, 3, 2); a33 := at(m, 3, 3)

	b00 := a00*a11 - a01*a10
	b01 := a00*a12 - a02*a10
	b02 := a00*a13 - a03*a10
	b03 := a01*a12 - a02*a11
	b04 := a01*a13 - a03*a11
	b05 := a02*a13 - a03*a12
	b06 := a20*a31 - a21*a30
	b07 := a20*a32 - a22*a30
	b08 := a20*a33 - a23*a30
	b09 := a21*a32 - a22*a31
	b10 := a21*a33 - a23*a31
	b11 := a22*a33 - a23*a32

	det := b00*b11 - b01*b10 + b02*b09 + b03*b08 - b04*b07 + b05*b06
	if math.abs(det) <= 1e-12 {
		return MATRIX4_IDENTITY, false
	}
	inv := 1.0 / det

	result: Matrix4
	// row 0
	matrix4_set(&result, 0, 0, f32((a11*b11 - a12*b10 + a13*b09) * inv))
	matrix4_set(&result, 1, 0, f32(-(a01*b11 - a02*b10 + a03*b09) * inv))
	matrix4_set(&result, 2, 0, f32((a31*b05 - a32*b04 + a33*b03) * inv))
	matrix4_set(&result, 3, 0, f32(-(a21*b05 - a22*b04 + a23*b03) * inv))
	// row 1
	matrix4_set(&result, 0, 1, f32(-(a10*b11 - a12*b08 + a13*b07) * inv))
	matrix4_set(&result, 1, 1, f32((a00*b11 - a02*b08 + a03*b07) * inv))
	matrix4_set(&result, 2, 1, f32(-(a30*b05 - a32*b02 + a33*b01) * inv))
	matrix4_set(&result, 3, 1, f32((a20*b05 - a22*b02 + a23*b01) * inv))
	// row 2
	matrix4_set(&result, 0, 2, f32((a10*b10 - a11*b08 + a13*b06) * inv))
	matrix4_set(&result, 1, 2, f32(-(a00*b10 - a01*b08 + a03*b06) * inv))
	matrix4_set(&result, 2, 2, f32((a30*b04 - a31*b02 + a33*b00) * inv))
	matrix4_set(&result, 3, 2, f32(-(a20*b04 - a21*b02 + a23*b00) * inv))
	// row 3
	matrix4_set(&result, 0, 3, f32(-(a10*b09 - a11*b07 + a12*b06) * inv))
	matrix4_set(&result, 1, 3, f32((a00*b09 - a01*b07 + a02*b06) * inv))
	matrix4_set(&result, 2, 3, f32(-(a30*b03 - a31*b01 + a32*b00) * inv))
	matrix4_set(&result, 3, 3, f32((a20*b03 - a21*b01 + a22*b00) * inv))
	return result, true
}

// ------------------------------------------------------------------------------
// transform
// ------------------------------------------------------------------------------

// 变换 Vec4（不做透视除法）。w' = 0 的方向向量同样适用。
// 行向量变换：h_j = dot(v, c_j)（列 j 即输出分量 j 的系数向量）。
matrix4_transform_vec4 :: proc(m: Matrix4, v: Vec4) -> Vec4 {
	return Vec4{
		v[0]*m.c0[0] + v[1]*m.c0[1] + v[2]*m.c0[2] + v[3]*m.c0[3],
		v[0]*m.c1[0] + v[1]*m.c1[1] + v[2]*m.c1[2] + v[3]*m.c1[3],
		v[0]*m.c2[0] + v[1]*m.c2[1] + v[2]*m.c2[2] + v[3]*m.c2[3],
		v[0]*m.c3[0] + v[1]*m.c3[1] + v[2]*m.c3[2] + v[3]*m.c3[3],
	}
}

// 变换点（w=1，含透视除法）。w≈0 时返回 false。
matrix4_transform_point :: proc(m: Matrix4, p: foster.Vec3) -> (foster.Vec3, bool) {
	h := matrix4_transform_vec4(m, Vec4{p[0], p[1], p[2], 1})
	if math.abs(h[3]) < 1e-8 {
		return {}, false
	}
	return foster.Vec3{h[0] / h[3], h[1] / h[3], h[2] / h[3]}, true
}

// 变换方向（w=0，不做透视除法）。
matrix4_transform_vector :: proc(m: Matrix4, v: foster.Vec3) -> foster.Vec3 {
	h := matrix4_transform_vec4(m, Vec4{v[0], v[1], v[2], 0})
	return foster.Vec3{h[0], h[1], h[2]}
}

// ------------------------------------------------------------------------------
// 向量辅助 —— v3 点积/叉积/归一化
// ------------------------------------------------------------------------------

v3_dot :: proc(a, b: foster.Vec3) -> f32 {
	return a[0]*b[0] + a[1]*b[1] + a[2]*b[2]
}

v3_cross :: proc(a, b: foster.Vec3) -> foster.Vec3 {
	return foster.Vec3{
		a[1]*b[2] - a[2]*b[1],
		a[2]*b[0] - a[0]*b[2],
		a[0]*b[1] - a[1]*b[0],
	}
}

v3_sub :: proc(a, b: foster.Vec3) -> foster.Vec3 {
	return foster.Vec3{a[0] - b[0], a[1] - b[1], a[2] - b[2]}
}

v3_normalize :: proc(v: foster.Vec3) -> foster.Vec3 {
	l := math.sqrt(v3_dot(v, v))
	if l <= 1e-10 {
		return foster.Vec3{0, 0, 0}
	}
	return foster.Vec3{v[0] / l, v[1] / l, v[2] / l}
}

// ------------------------------------------------------------------------------
// 内部 —— 取列 / 写元素
// ------------------------------------------------------------------------------

@(private)
matrix4_set :: proc(m: ^Matrix4, col, row: int, v: f32) {
	switch col {
	case 0: m.c0[row] = v
	case 1: m.c1[row] = v
	case 2: m.c2[row] = v
	case 3: m.c3[row] = v
	}
}

@(private)
matrix4_c :: proc(m: Matrix4, col: int) -> Vec4 {
	switch col {
	case 0: return m.c0
	case 1: return m.c1
	case 2: return m.c2
	case:   return m.c3
	}
}
