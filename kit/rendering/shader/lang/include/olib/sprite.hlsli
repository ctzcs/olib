// olib 标准引擎块：Draw Sprite（Render2D 的 submit 与 Shader Lab 精灵预览）。
// 宿主每次绘制填写这两个块；字节数与 kit/rendering/2d 的 SPRITE_VERTEX_BLOCK_SIZE / SPRITE_FRAME_BLOCK_SIZE
// 一致，由 tests/kit/rendering/2d 的布局测试检查。用法：#include "olib/sprite.hlsli"。
#ifndef OLIB_SPRITE_HLSLI
#define OLIB_SPRITE_HLSLI

cbuffer OlibVertex : register(b0, space1) {
    float4x4 Projection;  // 目标像素 → 裁剪空间：mul(Projection, float4(s.position, 0, 1))
    float4 VertexClock;   // time, delta_time, frame, 0；与片元 Clock 的前三个分量同值
};

cbuffer OlibFrame : register(b0, space3) {
    float4 Clock;    // time, delta_time, frame；w 各宿主不同，不要依赖
    float4 Pointer;  // xy 为 View.pointer，zw 目标像素尺寸
    float4 Tint;     // 固定白色；每个精灵的颜色用 InstanceTint
};

#endif
