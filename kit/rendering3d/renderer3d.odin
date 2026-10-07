// rendering3d:renderer3d —— 前向渲染主路径（对位 DragonLib Renderer3D 的主 pass）。
//
// 每帧：renderer3d_render —— 片元公共槽（光照/阴影关闭/点光）设一次，
// 逐项设顶点矩阵块 + 片元材质块后经 Foster DrawCommand 发射。
// 蒙皮项经 palette 槽（2、3）注入骨骼矩阵（animation.compute_palette 产出）。
// 阴影/CSM 与 Tonemap 后处理是后续增量（DepthOnly 着色器已备好）。
package rendering3d

import "core:mem"

import world "olib:kit/world"
import foster "olib:foster"

// 分区：
//   类型与生命周期 —— Renderer3D / init / dispose
//   帧渲染 —— render（公共槽 + 逐项发射）

// ------------------------------------------------------------------------------
// 类型与生命周期
// ------------------------------------------------------------------------------

Renderer3D :: struct {
	device: ^foster.GraphicsDevice,

	shaders: Shader3D_Pair,
	material_static:  foster.Material,
	material_skinned: foster.Material,

	scratch: [dynamic]u8, // uniform 打包临时
}

renderer3d_init :: proc(r: ^Renderer3D, device: ^foster.GraphicsDevice) -> bool {
	if device == nil { return false }
	r.device = device
	if !shader3d_standard_init(&r.shaders, device) {
		return false
	}
	foster.material_init_with_shaders(&r.material_static, &r.shaders.static_vertex, &r.shaders.static_fragment)
	foster.material_init_with_shaders(&r.material_skinned, &r.shaders.skinned_vertex, &r.shaders.skinned_fragment)
	return true
}

renderer3d_dispose :: proc(r: ^Renderer3D) {
	shader3d_dispose(&r.shaders)
	delete(r.scratch)
	r^ = {}
}

// ------------------------------------------------------------------------------
// 帧渲染
// ------------------------------------------------------------------------------

// 发射整个队列。camera 提供视矩阵；light 为方向光（阴影本轮关闭）；
// point_lights 可为空。palette 槽的骨骼矩阵由调用侧随蒙皮项提供
//（palette: []world.Matrix4，非蒙皮项传 nil）。
renderer3d_render :: proc(
	r: ^Renderer3D,
	camera:      ^world.Camera3D,
	light:       ^Light_Block,
	point_lights: []Point_Light,
	spot_lights: []Spot_Light,
	target:      foster.DrawableTarget,
	queue:       ^Render_Queue,
	palette:     []world.Matrix4,
) -> int {
	if r.device == nil { return 0 }

	// ---- 片元公共槽：光照(0) / 阴影关闭(2) / 点光(3) ----
	light_buf := scratch_reserve(&r.scratch, LIGHT_BLOCK_SIZE)
	if pack_light_block(light_buf, light) {
		foster.MaterialStageSetUniformBuffer(&r.material_static.Fragment, light_buf, 0)
		foster.MaterialStageSetUniformBuffer(&r.material_skinned.Fragment, light_buf, 0)
	}
	shadow_buf := scratch_reserve(&r.scratch, 160)
	if pack_shadow_block_disabled(shadow_buf) {
		foster.MaterialStageSetUniformBuffer(&r.material_static.Fragment, shadow_buf, 2)
		foster.MaterialStageSetUniformBuffer(&r.material_skinned.Fragment, shadow_buf, 2)
	}
	pl_buf := scratch_reserve(&r.scratch, POINT_LIGHT_BLOCK_SIZE)
	if pack_point_light_block(pl_buf, point_lights, spot_lights) {
		foster.MaterialStageSetUniformBuffer(&r.material_static.Fragment, pl_buf, 3)
		foster.MaterialStageSetUniformBuffer(&r.material_skinned.Fragment, pl_buf, 3)
	}

	// ---- 视矩阵（乘在各 item 的 world 前构成 WVP：行向量 v*W*VP）----
	view_projection := world.camera3d_view_projection(camera)

	drawn := 0
	for &item in queue.items {
		mesh := item.mesh
		if mesh == nil { continue }
		skinned := item.skinned
		material := skinned ? &r.material_skinned : &r.material_static

		// 顶点槽 0：WVP + World
		matrix_buf := scratch_reserve(&r.scratch, VERTEX_MATRIX_BLOCK_SIZE)
		wvp := world.matrix4_multiply(item.world, view_projection)
		if !pack_vertex_matrix_block(matrix_buf, wvp, item.world) { continue }
		foster.MaterialStageSetUniformBuffer(&material.Vertex, matrix_buf, 0)
		// 顶点槽 1：阴影矩阵（关闭形态也要给，着色器仍会乘）
		shadow_matrix_buf := scratch_reserve(&r.scratch, SHADOW_MATRIX_BLOCK_SIZE)
		if pack_shadow_matrix_block(shadow_matrix_buf, world.MATRIX4_IDENTITY) {
			foster.MaterialStageSetUniformBuffer(&material.Vertex, shadow_matrix_buf, 1)
		}
		// 蒙皮：palette 两块
		if skinned {
			p0 := scratch_reserve(&r.scratch, 64 * 64)
			p1 := scratch_reserve(&r.scratch, 64 * 64)
			if pack_joint_palette(p0, p1, palette) {
				foster.MaterialStageSetUniformBuffer(&material.Vertex, p0, 2)
				foster.MaterialStageSetUniformBuffer(&material.Vertex, p1, 3)
			}
		}

		// 片元槽 1：材质块
		mat_block := material_block_from(&item.material)
		mat_buf := scratch_reserve(&r.scratch, MATERIAL_BLOCK_SIZE)
		if !pack_material_block(mat_buf, &mat_block) { continue }
		foster.MaterialStageSetUniformBuffer(&material.Fragment, mat_buf, 1)

		// ---- 发射 ----
		command: foster.DrawCommand
		foster.DrawCommandFromMesh(&command, target, mesh, material)
		command.DepthTestEnabled = true
		command.DepthWriteEnabled = !item.material.state.transparent
		command.CullMode = item.material.state.cull_none ? .None : .Back
		if item.material.state.transparent {
			command.BlendMode = foster.BlendMode{
				ColorOperation   = .Add,
				ColorSource      = .SrcAlpha,
				ColorDestination = .OneMinusSrcAlpha,
				AlphaOperation   = .Add,
				AlphaSource      = .One,
				AlphaDestination = .OneMinusSrcAlpha,
			}
		}
		foster.GraphicsDeviceDraw(r.device, &command)
		foster.DrawCommandDispose(&command)
		drawn += 1
	}
	return drawn
}

// ------------------------------------------------------------------------------
// 内部
// ------------------------------------------------------------------------------

// 复用一块动态缓冲做 uniform 打包临时（每次调用重置，返回 len=size 的视图）。
@(private)
scratch_reserve :: proc(scratch: ^[dynamic]u8, size: int) -> []u8 {
	clear(scratch)
	resize(scratch, size)
	return scratch[:]
}
