// rendering3d:shader3d —— 着色器字节码按驱动选择 + DebugLine3D 装载。
//
// foster.ShaderInit 按驱动决定格式（Vulkan→SPIRV、D3D12→DXIL、Metal→MSL），
// 调用方只需交给它对应格式的字节码：shader3d_pick_code 负责这一步。
// 字节码由 olib 根目录的 tools/shaders（SDL_shadercross）编译后入库、#load 内嵌；
// 游戏自己的着色器用同一个工具（-dir: 指向自己的目录）编译，再用 shader3d_pick_code 选择。
// Web 后端走 WebGL + 手写 GLSL，不在这里。
package rendering3d

import foster "olib:foster"

// 分区：
//   内嵌二进制 —— DebugLine3D（#load 编译期嵌入）
//   字节码选择 —— 驱动支持判定 / 按驱动取字节码
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
// 字节码选择
// ------------------------------------------------------------------------------

// 驱动是否走预编译字节码（SPIR-V / DXIL / MSL）。Web 走手写 GLSL，不在此列。
shader3d_driver_supported :: proc(driver: foster.GraphicsDriver) -> bool {
	#partial switch driver {
	case .Vulkan, .Private, .D3D12, .Metal:
		return true
	case:
		return false
	}
}

// 按驱动取 spv / dxil / msl 字节码。没给 msl 时 Metal 驱动返回空切片，
// 调用方应检查长度（foster.ShaderInit 不接受空字节码）。
shader3d_pick_code :: proc(driver: foster.GraphicsDriver, spv, dxil: []u8, msl: []u8 = nil) -> []u8 {
	#partial switch driver {
	case .D3D12:
		return dxil
	case .Metal:
		return msl
	case:
		return spv
	}
}

// ------------------------------------------------------------------------------
// 装载 —— DebugLine3D
// ------------------------------------------------------------------------------

// DebugLine3D（调试线）：vertex 1 个 UBO（ViewProjection），fragment 无。
Shader3D_Debug_Line_Pair :: struct {
	vertex:   foster.Shader,
	fragment: foster.Shader,
}

shader3d_debug_line_init :: proc(pair: ^Shader3D_Debug_Line_Pair, device: ^foster.GraphicsDevice) -> bool {
	if !shader3d_driver_supported(device.Driver) { return false }

	vs_code := shader3d_pick_code(device.Driver, debugline_vertex_spv, debugline_vertex_dxil, debugline_vertex_msl)
	fs_code := shader3d_pick_code(device.Driver, debugline_fragment_spv, debugline_fragment_dxil, debugline_fragment_msl)

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
