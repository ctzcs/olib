// olib 标准引擎块：Draw Fullscreen 与 2D 的 Preview_Model（只在 Shader Lab 预览里绘制）。
// 宿主是 kit/tools/shader_lab 的 pass_uniforms。用法：#include "olib/fullscreen.hlsli"。
#ifndef OLIB_FULLSCREEN_HLSLI
#define OLIB_FULLSCREEN_HLSLI

cbuffer OlibVertex : register(b0, space1) {
    float4 View;  // x 横向缩放，y 纵向缩放（精灵预览模式按宽高比缩小），zw 为 0
};

cbuffer OlibFrame : register(b0, space3) {
    float4 Clock;    // time, delta_time, frame；w 为 1 时是 Shader Lab 的精灵预览模式
    float4 Pointer;  // xy 指针在预览区域内的归一化位置，zw 目标像素尺寸
    float4 Tint;     // 固定白色
};

#endif
