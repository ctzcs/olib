// olib 生成器内部：Draw Sprite 的统一顶点接口 OlibSpriteInput / olib_sprite。每个 Sprite Pass 的生成代码 include，
// 作者不直接 include（引擎块仍由作者 include olib/sprite.hlsli）。须在 olib/instance.hlsli 之后。
// 作者写 struct Input { OlibSpriteInput Sprite; };，顶点里 OlibSprite s = olib_sprite(v.Sprite); 得到目标像素位置、UV、
// 传给片元的 OlibInstance，以及 axis_x / axis_y：精灵局部 1 像素在目标像素空间里的两条轴（含变换栈）。
// 两种变体只有这里不同，position 与轴都在目标像素空间，片元代码完全相同：
// - OLIB_SPRITE_BATCH：顶点是 foster BatcherVertex（位置、UV、颜色、mode），颜色即 tint；mode 的 4 个字节是该精灵记录
//   在 OlibInstanceValues（顶点 storage buffer，t0 space0）里的 float4 偏移：记录首项是两条轴，之后是各 Pass 的
//   [Instance] 字段。位置与轴已在 CPU 上套用变换栈。
// - OLIB_INSTANCE_SPRITE：实例记录 + 单位四边形角点，供常驻 Sprite_Buffer 实例化绘制。实例在变换栈之前的坐标里，
//   olib_sprite 用 b1/space1 的变换栈 2D 仿射部分换算到目标像素。
#ifndef OLIB_SPRITE_VERTEX_HLSLI
#define OLIB_SPRITE_VERTEX_HLSLI

struct OlibSprite {
    float2 position;
    float2 uv;
    float2 axis_x;
    float2 axis_y;
    OlibInstance instance;
};

#ifdef OLIB_INSTANCE_SPRITE
struct OlibSpriteInput {
    OlibInstanceInput Instance;
    float2 Corner : TEXCOORD0;
};

// 变换栈的 2D 仿射部分（行向量约定）：axes = (m11,m12,m21,m22)，origin.xy = (m31,m32)。
cbuffer OlibSpriteView : register(b1, space1) { float4 _olib_view_axes; float4 _olib_view_origin; };

OlibSprite olib_sprite(OlibSpriteInput i) {
    OlibSprite s;
    float2 p;
    olib_sprite_vertex(i.Instance, i.Corner, p, s.uv);
    s.position = p.x * _olib_view_axes.xy + p.y * _olib_view_axes.zw + _olib_view_origin.xy;
    s.axis_x = i.Instance.sprite0.x * _olib_view_axes.xy + i.Instance.sprite0.y * _olib_view_axes.zw;
    s.axis_y = i.Instance.sprite0.z * _olib_view_axes.xy + i.Instance.sprite0.w * _olib_view_axes.zw;
    s.instance = olib_instance_from(i.Instance);
    return s;
}
#else
struct OlibSpriteInput {
    float2 Position : TEXCOORD0;
    float2 Uv : TEXCOORD1;
    float4 Color : TEXCOORD2;
    float4 Mode : TEXCOORD3;
};

StructuredBuffer<float4> OlibInstanceValues : register(t0, space0);
cbuffer OlibSpritePass : register(b1, space1) { uint _olib_pass_offset; };

#define OLIB_SPRITE_READ(n, input, varying) s.instance.data##n = OlibInstanceValues[offset + n];
OlibSprite olib_sprite(OlibSpriteInput i) {
    OlibSprite s;
    s.position = i.Position;
    s.uv = i.Uv;
    s.instance.tint = i.Color;
    uint4 bytes = (uint4)round(i.Mode * 255.0);
    uint offset = bytes.x | (bytes.y << 8) | (bytes.z << 16) | (bytes.w << 24);
    float4 axes = OlibInstanceValues[offset];
    s.axis_x = axes.xy;
    s.axis_y = axes.zw;
#if OLIB_INSTANCE_SLOTS > 0
    offset += 1 + _olib_pass_offset;
    OLIB_INSTANCE_DATA(OLIB_SPRITE_READ)
#endif
    return s;
}
#endif

#endif
