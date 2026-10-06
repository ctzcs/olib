// rendering3d —— 3D 渲染的数据与队列层（对位 DragonLib Engine.Rendering 的 3D 部分）。
//
// 分层边界（诚实声明）：本包提供 Mesh 上传、材质数据、渲染项排序——
// 全部 CPU 可测。真正的 GPU 输出还差着色器二进制管线（DragonLib 用
// Tools/ShaderCompiler 把 HLSL 离线交叉编译成 dxil/spv，olib 侧等价物
// 未建）；ofoster 的 ShaderCreateInfo/Mesh/深度/混合 API 已就绪，管线
// 建好后接入本包的队列即可。
//
// 分区：
//   mesh3d.odin      dasset 顶点 -> ofoster Mesh 上传
//   material3d.odin  StandardMaterial3D 数据 + 渲染状态推导
//   queue3d.odin     渲染项队列（不透明前到后 / 透明后到前）
package rendering3d
