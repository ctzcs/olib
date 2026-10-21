// olib 标准引擎块：Draw Model（Render3D、model_material_draw、Shader Lab 3D 预览，也用于 3D 的 Preview_Model）。
// 宿主每次绘制填写这两个块；字节数与 kit/rendering/3d 的 MATERIAL_VERTEX_BLOCK_SIZE / MATERIAL_FRAME_BLOCK_SIZE
// 一致，由 tests/kit/rendering/3d 的布局测试检查。用法：#include "olib/model.hlsli"。
// 矩阵按行向量约定使用：mul(float4(position, 1), Wvp)。
#ifndef OLIB_MODEL_HLSLI
#define OLIB_MODEL_HLSLI

cbuffer OlibVertex : register(b0, space1) {
    float4x4 Wvp;                 // 非 instanced：World × ViewProjection；instanced：ViewProjection（World 为单位矩阵）
    float4x4 World;               // 非 instanced 的世界矩阵；instanced 时为单位矩阵，世界矩阵用 olib_world 从实例取
    float4 VertexClock;           // time, delta_time, frame, 0；与片元 Clock 的前三个分量同值
    float4 VertexCameraPosition;  // 相机世界坐标 xyz, 1；与片元 CameraPosition 同值
};

cbuffer OlibFrame : register(b0, space3) {
    float4 Clock;           // time, delta_time, frame, 0
    float4 Pointer;         // xy 指针（Render3D 为 0，Shader Lab 的 3D Preview_Model 为预览区域内的归一化位置），zw 目标像素尺寸
    float4 Tint;            // 非 instanced 时是该对象的 tint；instanced 时为白色，逐实例颜色用 InstanceTint
    float4 CameraPosition;  // 相机世界坐标 xyz, 1
};

#endif
