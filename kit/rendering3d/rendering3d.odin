// rendering3d —— 3D 渲染机制层（与画风无关的部分）。
//
// 只提供每个 3D 游戏都要的机制；光照模型、材质模型、阴影、后处理等外观
// 策略由游戏自己写。参考实现（Standard PBR 前向渲染器）在同级仓库
// olib_sample 的 src/forward3d，复制过去按需修改。
//
// 分区：
//   mesh3d.odin        dasset 顶点 -> Foster Mesh 上传（静态/蒙皮格式）
//   queue3d.odin       泛型渲染队列（不透明前到后 / 透明后到前）
//   shader3d.odin      字节码按驱动选择 + DebugLine3D 装载
//   shaders/           DebugLine3D HLSL 源 + 编译脚本 + Compiled 二进制（入库）
//   uniforms3d.odin    std140 写入 + 顶点矩阵块 + 骨骼 palette 打包
//   debug_draw3d.odin  立即模式调试线
//   lod3d.odin         屏幕高度 LOD 选择
package rendering3d
