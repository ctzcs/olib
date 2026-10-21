// olib 生成器内部：[Instance] 字段、实例颜色与实例顶点输入。每个 Pass 的生成代码按需 include，作者不直接 include。
// 生成器先定义：
//   OLIB_INSTANCE_SLOTS        [Instance] 字段数
//   OLIB_INSTANCE_DATA(X)      按槽位展开 X(槽位, 顶点输入语义号, 传给片元的语义号)
//   OLIB_INSTANCE_MODEL        模型实例：OlibInstanceInput 带世界矩阵，提供 olib_world
//   OLIB_INSTANCE_SPRITE       精灵常驻缓冲：OlibInstanceInput 带精灵变换与矩形，提供 olib_sprite_vertex
// 两者都没定义时（精灵批量变体）只声明传给片元的 OlibInstance。
// 固定成员的语义号与 kit/rendering/shader 的 INSTANCE_SEMANTIC_BASE（6）/ INSTANCE_VARYING_BASE（8）一致。
#ifndef OLIB_INSTANCE_HLSLI
#define OLIB_INSTANCE_HLSLI

// 传给片元的 tint 与 [Instance] 字段，不插值。片元里先 olib_instance = v.Instance，之后 _name 与 InstanceTint 可用。
#define OLIB_INSTANCE_VARYING(n, input, varying) nointerpolation float4 data##n : TEXCOORD##varying;
struct OlibInstance {
    nointerpolation float4 tint : TEXCOORD8;
    OLIB_INSTANCE_DATA(OLIB_INSTANCE_VARYING)
};
static OlibInstance olib_instance;
#define InstanceTint (olib_instance.tint)

#if defined(OLIB_INSTANCE_MODEL) || defined(OLIB_INSTANCE_SPRITE)
// 顶点输入：必须是 Input 的第一个成员（网格属性随后）。属性位置由声明顺序决定，语义号只需互不相同。
#define OLIB_INSTANCE_INPUT(n, input, varying) float4 data##n : TEXCOORD##input;
struct OlibInstanceInput {
#ifdef OLIB_INSTANCE_MODEL
    // 世界矩阵的四列，与 CPU 写入 uniform 的 Matrix4 同一约定（行向量 v * M）。
    float4 world0 : TEXCOORD6;
    float4 world1 : TEXCOORD7;
    float4 world2 : TEXCOORD8;
    float4 world3 : TEXCOORD9;
#else
    // sprite0 = (m11,m12,m21,m22)，sprite1 = (m31,m32, 局部矩形 x0,y0)，sprite2 = (局部矩形 宽,高, uv0.xy)，sprite3 = (uv 宽,高)。
    float4 sprite0 : TEXCOORD6;
    float4 sprite1 : TEXCOORD7;
    float4 sprite2 : TEXCOORD8;
    float4 sprite3 : TEXCOORD9;
#endif
    float4 tint : TEXCOORD10;
    OLIB_INSTANCE_DATA(OLIB_INSTANCE_INPUT)
};

#ifdef OLIB_INSTANCE_MODEL
float4x4 olib_world(OlibInstanceInput i) {
    return transpose(float4x4(i.world0, i.world1, i.world2, i.world3));
}
#else
// 由单位四边形的角点 (0,0)(1,0)(1,1)(0,1) 得到位置与 UV；变换沿用 Matrix3x2 的行向量约定。
void olib_sprite_vertex(OlibInstanceInput i, float2 corner, out float2 position, out float2 uv) {
    float2 local = i.sprite1.zw + corner * i.sprite2.xy;
    position = float2(local.x * i.sprite0.x + local.y * i.sprite0.z + i.sprite1.x,
                      local.x * i.sprite0.y + local.y * i.sprite0.w + i.sprite1.y);
    uv = i.sprite2.zw + corner * i.sprite3.xy;
}
#endif

#define OLIB_INSTANCE_COPY(n, input, varying) o.data##n = i.data##n;
OlibInstance olib_instance_from(OlibInstanceInput i) {
    OlibInstance o;
    o.tint = i.tint;
    OLIB_INSTANCE_DATA(OLIB_INSTANCE_COPY)
    return o;
}
#endif

#endif
