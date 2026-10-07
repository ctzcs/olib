// rendering3d:shader3d —— Standard3D/DepthOnly 着色器装载（按驱动分发）。
//
// 二进制由 shaders/build_shaders.ps1 用 Vulkan SDK dxc 编译（HLSL 源自
// DragonLib，语义标注齐全）；spv 给 Vulkan、dxil 给 D3D12。Metal/WebGL
// 目标需在各自平台补编 .msl/.glsl 后加入同一分发。
package rendering3d

import foster "olib:foster"

// 分区：
//   内嵌二进制 —— #load 编译期嵌入
//   装载 —— 按驱动选格式 init Shader/Material

// ------------------------------------------------------------------------------
// 内嵌二进制 —— #load 编译期嵌入
// ------------------------------------------------------------------------------

@(private)
standard3d_vertex_spv :: #load("shaders/Compiled/Standard3D.vertex.spv")
@(private)
standard3d_fragment_spv :: #load("shaders/Compiled/Standard3D.fragment.spv")
@(private)
standard3d_skinned_vertex_spv :: #load("shaders/Compiled/Standard3DSkinned.vertex.spv")
@(private)
standard3d_skinned_fragment_spv :: #load("shaders/Compiled/Standard3DSkinned.fragment.spv")

@(private)
standard3d_vertex_dxil :: #load("shaders/Compiled/Standard3D.vertex.dxil")
@(private)
standard3d_fragment_dxil :: #load("shaders/Compiled/Standard3D.fragment.dxil")
@(private)
standard3d_skinned_vertex_dxil :: #load("shaders/Compiled/Standard3DSkinned.vertex.dxil")
@(private)
standard3d_skinned_fragment_dxil :: #load("shaders/Compiled/Standard3DSkinned.fragment.dxil")

@(private)
depthonly_vertex_spv :: #load("shaders/Compiled/DepthOnly.vertex.spv")
@(private)
depthonly_fragment_spv :: #load("shaders/Compiled/DepthOnly.fragment.spv")
@(private)
depthonly_skinned_vertex_spv :: #load("shaders/Compiled/DepthOnlySkinned.vertex.spv")
@(private)
depthonly_skinned_fragment_spv :: #load("shaders/Compiled/DepthOnlySkinned.fragment.spv")

@(private)
debugline_vertex_spv :: #load("shaders/Compiled/DebugLine3D.vertex.spv")
@(private)
debugline_fragment_spv :: #load("shaders/Compiled/DebugLine3D.fragment.spv")

@(private)
debugline_vertex_dxil :: #load("shaders/Compiled/DebugLine3D.vertex.dxil")
@(private)
debugline_fragment_dxil :: #load("shaders/Compiled/DebugLine3D.fragment.dxil")

@(private)
depthonly_vertex_dxil :: #load("shaders/Compiled/DepthOnly.vertex.dxil")
@(private)
depthonly_fragment_dxil :: #load("shaders/Compiled/DepthOnly.fragment.dxil")
@(private)
depthonly_skinned_vertex_dxil :: #load("shaders/Compiled/DepthOnlySkinned.vertex.dxil")
@(private)
depthonly_skinned_fragment_dxil :: #load("shaders/Compiled/DepthOnlySkinned.fragment.dxil")

// ------------------------------------------------------------------------------
// 装载 —— 按驱动选格式 init Shader/Material
// ------------------------------------------------------------------------------

// 驱动支持判定（ShaderCreateInfo 无格式字段，SDL 按字节码魔数自动识别；
// Metal/WebGL 目标需先补编 .msl/.glsl，当前返回 false）。
shader3d_driver_supported :: proc(driver: foster.GraphicsDriver) -> bool {
	#partial switch driver {
	case .Vulkan, .Private, .D3D12:
		return true
	case:
		return false
	}
}

// 按驱动取 spv / dxil 字节码。
shader3d_pick_code :: proc(driver: foster.GraphicsDriver, spv, dxil: []u8) -> []u8 {
	return driver == .D3D12 ? dxil : spv
}

// Standard3D 一套（静态 + 蒙皮）：
// vertex 槽 0=矩阵块 / 1=阴影矩阵（蒙皮再加 2、3=palette 两块）；
// fragment 槽 0=光照 / 1=材质 / 2=阴影 / 3=点光，6 个 sampler。
Shader3D_Pair :: struct {
	static_vertex:    foster.Shader,
	static_fragment:  foster.Shader,
	skinned_vertex:   foster.Shader,
	skinned_fragment: foster.Shader,
}

shader3d_standard_init :: proc(pair: ^Shader3D_Pair, device: ^foster.GraphicsDevice) -> bool {
	if !shader3d_driver_supported(device.Driver) { return false }

	vs_code_static := shader3d_pick_code(device.Driver, standard3d_vertex_spv, standard3d_vertex_dxil)
	fs_code_static := shader3d_pick_code(device.Driver, standard3d_fragment_spv, standard3d_fragment_dxil)
	vs_code_skin := shader3d_pick_code(device.Driver, standard3d_skinned_vertex_spv, standard3d_skinned_vertex_dxil)
	fs_code_skin := shader3d_pick_code(device.Driver, standard3d_skinned_fragment_spv, standard3d_skinned_fragment_dxil)

	foster.shader_init(&pair.static_vertex, device, foster.ShaderCreateInfo{
		Stage              = .Vertex,
		Code               = vs_code_static,
		SamplerCount       = 0,
		UniformBufferCount = 2, // b0 矩阵块 / b1 阴影矩阵
		EntryPoint         = "vertex_main",
	}, "Standard3DVertex")
	foster.shader_init(&pair.static_fragment, device, foster.ShaderCreateInfo{
		Stage              = .Fragment,
		Code               = fs_code_static,
		SamplerCount       = 6, // albedo/normal/shadow/MR/AO/emissive
		UniformBufferCount = 4, // b0 光照 / b1 材质 / b2 阴影 / b3 点光
		EntryPoint         = "fragment_main",
	}, "Standard3DFragment")
	foster.shader_init(&pair.skinned_vertex, device, foster.ShaderCreateInfo{
		Stage              = .Vertex,
		Code               = vs_code_skin,
		SamplerCount       = 0,
		UniformBufferCount = 4, // 再加 b2/b3 palette 两块
		EntryPoint         = "vertex_main",
	}, "Standard3DSkinnedVertex")
	foster.shader_init(&pair.skinned_fragment, device, foster.ShaderCreateInfo{
		Stage              = .Fragment,
		Code               = fs_code_skin,
		SamplerCount       = 6,
		UniformBufferCount = 4,
		EntryPoint         = "fragment_main",
	}, "Standard3DSkinnedFragment")

	return pair.static_vertex.Resource != nil && pair.static_fragment.Resource != nil &&
	       pair.skinned_vertex.Resource != nil && pair.skinned_fragment.Resource != nil
}

// DebugLine3D（调试线）：vertex 1 个 UBO（ViewProjection），fragment 无。
// 材质两阶段共用同一 Shader 资源（着色器对 stage 不敏感的部分由
// material_init_with_shaders 区分，这里 vertex/fragment 各需实例）。
Shader3D_Debug_Line_Pair :: struct {
	vertex:   foster.Shader,
	fragment: foster.Shader,
}

shader3d_debug_line_init :: proc(pair: ^Shader3D_Debug_Line_Pair, device: ^foster.GraphicsDevice) -> bool {
	if !shader3d_driver_supported(device.Driver) { return false }

	vs_code := shader3d_pick_code(device.Driver, debugline_vertex_spv, debugline_vertex_dxil)
	fs_code := shader3d_pick_code(device.Driver, debugline_fragment_spv, debugline_fragment_dxil)

	foster.shader_init(&pair.vertex, device, foster.ShaderCreateInfo{
		Stage              = .Vertex,
		Code               = vs_code,
		SamplerCount       = 0,
		UniformBufferCount = 1,
		EntryPoint         = "vertex_main",
	}, "DebugLine3DVertex")
	foster.shader_init(&pair.fragment, device, foster.ShaderCreateInfo{
		Stage      = .Fragment,
		Code       = fs_code,
		EntryPoint = "fragment_main",
	}, "DebugLine3DFragment")
	return pair.vertex.Resource != nil && pair.fragment.Resource != nil
}

shader3d_dispose :: proc(pair: ^Shader3D_Pair) {
	foster.ShaderDispose(&pair.static_vertex)
	foster.ShaderDispose(&pair.static_fragment)
	foster.ShaderDispose(&pair.skinned_vertex)
	foster.ShaderDispose(&pair.skinned_fragment)
	pair^ = {}
}

// DepthOnly 一套（阴影 pass 预留：vertex 1 个 UBO，fragment 0）。
Shader3D_Depth_Pair :: struct {
	static_vertex:    foster.Shader,
	static_fragment:  foster.Shader,
	skinned_vertex:   foster.Shader,
	skinned_fragment: foster.Shader,
}

shader3d_depth_init :: proc(pair: ^Shader3D_Depth_Pair, device: ^foster.GraphicsDevice) -> bool {
	if !shader3d_driver_supported(device.Driver) { return false }

	vs_static := shader3d_pick_code(device.Driver, depthonly_vertex_spv, depthonly_vertex_dxil)
	fs_static := shader3d_pick_code(device.Driver, depthonly_fragment_spv, depthonly_fragment_dxil)
	vs_skin := shader3d_pick_code(device.Driver, depthonly_skinned_vertex_spv, depthonly_skinned_vertex_dxil)
	fs_skin := shader3d_pick_code(device.Driver, depthonly_skinned_fragment_spv, depthonly_skinned_fragment_dxil)

	foster.shader_init(&pair.static_vertex, device, foster.ShaderCreateInfo{
		Stage              = .Vertex,
		Code               = vs_static,
		UniformBufferCount = 2,
		EntryPoint         = "vertex_main",
	}, "DepthOnlyVertex")
	foster.shader_init(&pair.static_fragment, device, foster.ShaderCreateInfo{
		Stage      = .Fragment,
		Code       = fs_static,
		EntryPoint = "fragment_main",
	}, "DepthOnlyFragment")
	foster.shader_init(&pair.skinned_vertex, device, foster.ShaderCreateInfo{
		Stage              = .Vertex,
		Code               = vs_skin,
		UniformBufferCount = 4,
		EntryPoint         = "vertex_main",
	}, "DepthOnlySkinnedVertex")
	foster.shader_init(&pair.skinned_fragment, device, foster.ShaderCreateInfo{
		Stage      = .Fragment,
		Code       = fs_skin,
		EntryPoint = "fragment_main",
	}, "DepthOnlySkinnedFragment")

	return pair.static_vertex.Resource != nil && pair.static_fragment.Resource != nil &&
	       pair.skinned_vertex.Resource != nil && pair.skinned_fragment.Resource != nil
}
