// rendering3d:shader3d —— DebugLine3D 着色器装载。
//
// 字节码由 olib 根目录的 tools/shaders（SDL_shadercross）编译后入库、#load 内嵌，
// 按驱动选择格式用 mat.shader_pick。Web 后端走 WebGL + 手写 GLSL，不在这里。
package rendering3d

import foster "olib:foster"
import mat "olib:kit/rendering/material"

// 分区：
//   内嵌二进制 —— DebugLine3D（#load 编译期嵌入）
//   装载 —— DebugLine3D

// ------------------------------------------------------------------------------
// 内嵌二进制 —— DebugLine3D
// ------------------------------------------------------------------------------

@(private)
debugline_vertex_spv :: #load("shaders/Compiled/DebugLine3D.vertex.spv")
@(private)
debugline_fragment_spv :: #load("shaders/Compiled/DebugLine3D.fragment.spv")
@(private)
debugline_vertex_dxil :: #load("shaders/Compiled/DebugLine3D.vertex.dxil")
@(private)
debugline_fragment_dxil :: #load("shaders/Compiled/DebugLine3D.fragment.dxil")
@(private)
debugline_vertex_msl :: #load("shaders/Compiled/DebugLine3D.vertex.msl")
@(private)
debugline_fragment_msl :: #load("shaders/Compiled/DebugLine3D.fragment.msl")

// ------------------------------------------------------------------------------
// 装载 —— DebugLine3D
// ------------------------------------------------------------------------------

// DebugLine3D（调试线）：vertex 1 个 UBO（ViewProjection），fragment 无。
Shader3D_Debug_Line_Pair :: struct {
	vertex:   foster.Shader,
	fragment: foster.Shader,
}

shader3d_debug_line_init :: proc(pair: ^Shader3D_Debug_Line_Pair, device: ^foster.GraphicsDevice) -> bool {
	if !mat.shader_driver_supported(device.Driver) do return false

	vs_code := mat.shader_pick(device.Driver, {debugline_vertex_spv, debugline_vertex_dxil, debugline_vertex_msl})
	fs_code := mat.shader_pick(device.Driver, {debugline_fragment_spv, debugline_fragment_dxil, debugline_fragment_msl})

	foster.ShaderInit(&pair.vertex, device, foster.ShaderCreateInfo{
		Stage              = .Vertex,
		Code               = vs_code,
		SamplerCount       = 0,
		UniformBufferCount = 1,
		EntryPoint         = "vertex_main",
	}, "DebugLine3DVertex")
	foster.ShaderInit(&pair.fragment, device, foster.ShaderCreateInfo{
		Stage      = .Fragment,
		Code       = fs_code,
		EntryPoint = "fragment_main",
	}, "DebugLine3DFragment")
	return pair.vertex.Resource != nil && pair.fragment.Resource != nil
}
