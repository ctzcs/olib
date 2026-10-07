// rendering3d —— 3D 前向渲染（对位 DragonLib Engine.Rendering 的 3D 部分）。
//
// 着色器管线（HLSL 源自 DragonLib，shaders/build_shaders.ps1 用 Vulkan SDK
// dxc 编译）：dxil/spv 已入库并 #load 内嵌，按驱动分发（ShaderCreateInfo
// 无格式字段，SDL 按字节码魔数识别）；.msl/.glsl 需在 Metal/Web 平台补编。
// 阴影 pass（DepthOnly 已备好着色器）、CSM、Tonemap 后处理是后续增量。
//
// 分区：
//   mesh3d.odin      dasset 顶点 -> Foster Mesh 上传（静态/蒙皮格式）
//   material3d.odin  StandardMaterial3D 数据 + 渲染状态推导
//   queue3d.odin     渲染项队列（不透明前到后 / 透明后到前）
//   shaders/         HLSL 源 + 编译脚本 + Compiled 二进制（入库）
//   shader3d.odin    着色器装载（#load 内嵌，按驱动分发）
//   uniforms3d.odin  cbuffer 对应的 std140 打包（CPU 可测）
//   renderer3d.odin  前向主 pass（公共槽一次 + 逐项 uniform + 发射）
package rendering3d
