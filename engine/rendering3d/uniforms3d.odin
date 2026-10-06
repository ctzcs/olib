// rendering3d:uniforms3d —— 与 Standard3D 着色器 cbuffer 对应的 CPU 侧打包。
//
// 布局按 SDL std140 规则手排（全 vec4，无 padding 陷阱）；矩阵为列主序
// 16×f32（engine/world 的 Matrix4 列存储直接推送即可——mul(M,v) 语义下
// 无需转置）。槽位号与 HLSL 的 register(bN) 一致。
package rendering3d

import "core:math"
import "core:mem"

import world "olib:engine/world"

// 分区：
//   顶点槽 —— 矩阵块（槽 0）/ 阴影矩阵（槽 1）/ 骨骼 palette（槽 2、3）
//   片元槽 —— 光照（槽 0）/ 材质（槽 1）/ 阴影（槽 2）/ 点光（槽 3）
//   打包辅助 —— 矩阵/vec4 写入

// ------------------------------------------------------------------------------
// 顶点槽 —— 矩阵块（槽 0）/ 阴影矩阵（槽 1）
// ------------------------------------------------------------------------------

// VertexMatrixBlock（128B）：WVP + World。
Vertex_Matrix_Block :: struct {
	world_view_projection: world.Matrix4,
	world:                world.Matrix4,
}

VERTEX_MATRIX_BLOCK_SIZE :: 128
SHADOW_MATRIX_BLOCK_SIZE :: 64 // 单矩阵

// 打包槽 0（WVP/World）。buf 长度不足返回 false。
pack_vertex_matrix_block :: proc(buf: []u8, wvp, world_matrix: world.Matrix4) -> bool {
	if len(buf) < VERTEX_MATRIX_BLOCK_SIZE { return false }
	write_matrix(buf, 0, wvp)
	write_matrix(buf, 64, world_matrix)
	return true
}

// 打包槽 1（阴影 LightViewProjection，单矩阵 64B）。
pack_shadow_matrix_block :: proc(buf: []u8, light_view_projection: world.Matrix4) -> bool {
	if len(buf) < SHADOW_MATRIX_BLOCK_SIZE { return false }
	write_matrix(buf, 0, light_view_projection)
	return true
}

// ------------------------------------------------------------------------------
// 顶点槽 —— 骨骼 palette（槽 2、3，各 64 关节 = 4KB）
// ------------------------------------------------------------------------------

// SDL 3.4 Vulkan 每槽 UBO 上限 4KB：128 关节拆两块（0-63 / 64-127）。
// palette 少于 64 个时两块都各写一个单位阵兜底（着色器端下标越界防护）。
pack_joint_palette :: proc(
	buf0, buf1: []u8,
	palette: []world.Matrix4,
) -> bool {
	if len(buf0) < 64 * 64 || len(buf1) < 64 * 64 { return false }

	for i in 0..<64 {
		if i < len(palette) {
			write_matrix(buf0, i * 64, palette[i])
		} else {
			write_matrix(buf0, i * 64, world.MATRIX4_IDENTITY)
		}
		if i + 64 < len(palette) {
			write_matrix(buf1, i * 64, palette[i + 64])
		} else {
			write_matrix(buf1, i * 64, world.MATRIX4_IDENTITY)
		}
	}
	return true
}

// ------------------------------------------------------------------------------
// 片元槽 —— 光照（槽 0）/ 材质（槽 1）/ 阴影（槽 2）/ 点光（槽 3）
// ------------------------------------------------------------------------------

MAX_POINT_LIGHTS :: 16

// Standard3DLightBlock（80B = 5 个 vec4）。Direction 指向光源传播方向（着色器取负）。
Light_Block :: struct {
	light_direction: [4]f32,
	ambient:         [4]f32,
	diffuse:         [4]f32,
	camera_position: [4]f32, // xyz 相机世界位置（w 未用）
	color_pipeline:  [4]f32, // x: HDR 开关
}

LIGHT_BLOCK_SIZE :: 80

pack_light_block :: proc(buf: []u8, light: ^Light_Block) -> bool {
	if len(buf) < LIGHT_BLOCK_SIZE { return false }
	write_vec4(buf, 0, light.light_direction)
	write_vec4(buf, 16, light.ambient)
	write_vec4(buf, 32, light.diffuse)
	write_vec4(buf, 48, light.camera_position)
	write_vec4(buf, 64, light.color_pipeline)
	return true
}

// 便捷：相机位置与 HDR 一起填（camera_position.w = hdr）。
make_light_block :: proc(
	light_direction, ambient, diffuse: [3]f32,
	camera_position: [3]f32,
	hdr: f32,
) -> Light_Block {
	return Light_Block{
		light_direction = {light_direction[0], light_direction[1], light_direction[2], 0},
		ambient         = {ambient[0], ambient[1], ambient[2], 0},
		diffuse         = {diffuse[0], diffuse[1], diffuse[2], 0},
		camera_position = {camera_position[0], camera_position[1], camera_position[2], 0},
		color_pipeline  = {hdr, 0, 0, 0},
	}
}

// Standard3DMaterialBlock（96B）。各 vec4 的语义见 Standard3DCommon.hlsli。
Material_Block :: struct {
	base_color: [4]f32,
	flags:      [4]f32, // x: has albedo, y: has normal map, z: normal strength, w: alpha mode
	alpha:      [4]f32, // x: cutoff
	pbr:        [4]f32, // x: metallic, y: roughness, z: albedo-srgb-decoded
	textures:   [4]f32, // x: MR, y: AO, z: emissive, w: emissive sRGB
	emissive:   [4]f32, // xyz: factor, w: AO strength
}

MATERIAL_BLOCK_SIZE :: 96

pack_material_block :: proc(buf: []u8, m: ^Material_Block) -> bool {
	if len(buf) < MATERIAL_BLOCK_SIZE { return false }
	write_vec4(buf, 0, m.base_color)
	write_vec4(buf, 16, m.flags)
	write_vec4(buf, 32, m.alpha)
	write_vec4(buf, 48, m.pbr)
	write_vec4(buf, 64, m.textures)
	write_vec4(buf, 80, m.emissive)
	return true
}

// 由 Standard_Material_3D 生成片元材质块（无贴图路径：全部 has*=0）。
material_block_from :: proc(m: ^Standard_Material_3D) -> Material_Block {
	alpha_mode := f32(0)
	if m.state.transparent { alpha_mode = 2 } else if m.alpha_cutoff < 1 && m.alpha_cutoff > 0 {
		alpha_mode = 1 // 近似：cutout 由调用侧显式指定更准
	}
	return Material_Block{
		base_color = m.base_color_factor,
		flags      = {0, 0, 1, alpha_mode},
		alpha      = {m.alpha_cutoff, 0, 0, 0},
		pbr        = {m.metallic, m.roughness, 0, 0},
		textures   = {0, 0, 0, 0},
		emissive   = {m.emissive_factor[0], m.emissive_factor[1], m.emissive_factor[2], m.occlusion_strength},
	}
}

// Standard3DShadowBlock（阴影关闭形态，160B）：ShadowSettings.x = 0 即可，
// 其余字段填安全值。CSM 启用后再补完整布局。
pack_shadow_block_disabled :: proc(buf: []u8) -> bool {
	if len(buf) < 160 { return false }
	for i in 0..<160 {
		buf[i] = 0
	}
	return true
}

// Standard3DPointLightBlock（b3）：点光 + 聚光灯同一块。
// meta(1) + 点光 position/color 各 16 + 聚光 meta(1) + 聚光 4 组 16 = 98 vec4 = 1568B。
POINT_LIGHT_BLOCK_SIZE :: 98 * 16

Point_Light :: struct {
	position: [3]f32,
	range:    f32,
	color:    [3]f32,
	intensity: f32,
}

// 无阴影聚光灯：Direction 指向光射出方向，锥角为弧度半角。
Spot_Light :: struct {
	position:    [3]f32,
	direction:   [3]f32,
	range:       f32,
	color:       [3]f32,
	intensity:   f32,
	inner_angle: f32, // 弧度半角
	outer_angle: f32,
}

SPOT_LIGHT_DEFAULT_INNER :: f32(math.PI / 12)
SPOT_LIGHT_DEFAULT_OUTER :: f32(math.PI / 6)

// 打包 b3：点光与聚光（各自钳制参数，越界方向兜底 -Y）。
pack_point_light_block :: proc(buf: []u8, lights: []Point_Light, spot_lights: []Spot_Light) -> bool {
	if len(buf) < POINT_LIGHT_BLOCK_SIZE { return false }

	count := min(len(lights), MAX_POINT_LIGHTS)
	write_vec4(buf, 0, {f32(count), 0, 0, 0})
	for i in 0..<MAX_POINT_LIGHTS {
		if i < count {
			l := lights[i]
			write_vec4(buf, 16 + i*16, {l.position[0], l.position[1], l.position[2], l.range})
			write_vec4(buf, 16 + (MAX_POINT_LIGHTS + i)*16, {l.color[0], l.color[1], l.color[2], l.intensity})
		} else {
			write_vec4(buf, 16 + i*16, {0, 0, 0, 0})
			write_vec4(buf, 16 + (MAX_POINT_LIGHTS + i)*16, {0, 0, 0, 0})
		}
	}

	// 聚光：meta 在 33 号 vec4，其后 4 组各 16
	base := 33 * 16
	spot_count := min(len(spot_lights), MAX_POINT_LIGHTS)
	write_vec4(buf, base, {f32(spot_count), 0, 0, 0})
	for i in 0..<MAX_POINT_LIGHTS {
		if i < spot_count {
			l := spot_lights[i]
			dx, dy, dz := l.direction[0], l.direction[1], l.direction[2]
			length2 := dx*dx + dy*dy + dz*dz
			if length2 > 1e-8 {
				inv := 1.0 / math.sqrt(length2)
				dx, dy, dz = dx*inv, dy*inv, dz*inv
			} else {
				dx, dy, dz = 0, -1, 0
			}
			outer := math.clamp(l.outer_angle, 0.001, math.PI / 2)
			inner := math.clamp(l.inner_angle, 0, outer)
			color := [3]f32{
				max(l.color[0], 0), max(l.color[1], 0), max(l.color[2], 0),
			}
			write_vec4(buf, base + 16 + i*16, {l.position[0], l.position[1], l.position[2], max(l.range, 0)})
			write_vec4(buf, base + 16 + (16 + i)*16, {color[0], color[1], color[2], max(l.intensity, 0)})
			write_vec4(buf, base + 16 + (32 + i)*16, {dx, dy, dz, math.cos(outer)})
			write_vec4(buf, base + 16 + (48 + i)*16, {math.cos(inner), 0, 0, 0})
		} else {
			for g in 0..<4 {
				write_vec4(buf, base + 16 + (g*16 + i)*16, {0, 0, 0, 0})
			}
		}
	}
	return true
}

// ------------------------------------------------------------------------------
// 打包辅助 —— 矩阵/vec4 写入（小端，按 f32 位型直写）
// ------------------------------------------------------------------------------

@(private)
write_matrix :: proc(buf: []u8, offset: int, m: world.Matrix4) {
	write_vec4(buf, offset, m.c0)
	write_vec4(buf, offset + 16, m.c1)
	write_vec4(buf, offset + 32, m.c2)
	write_vec4(buf, offset + 48, m.c3)
}

@(private)
write_vec4 :: proc(buf: []u8, offset: int, v: [4]f32) {
	if offset + 16 > len(buf) { return }
	for i in 0..<4 {
		bits := transmute(u32)v[i]
		base := offset + i * 4
		buf[base] = u8(bits)
		buf[base + 1] = u8(bits >> 8)
		buf[base + 2] = u8(bits >> 16)
		buf[base + 3] = u8(bits >> 24)
	}
}
