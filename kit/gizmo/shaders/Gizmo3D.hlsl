// 三维手柄：顶点为世界位置与颜色；遮挡通道只改变透明度。
cbuffer CameraBlock : register(b0, space1) { float4x4 ViewProjection; };
cbuffer StyleBlock : register(b0, space3) { float4 Tint; };
struct VsInput { float3 Position : TEXCOORD0; float4 Color : TEXCOORD1; };
struct VsOutput { float4 Position : SV_Position; float4 Color : TEXCOORD0; };
VsOutput vertex_main(VsInput input)
{
    VsOutput output;
    output.Position = mul(float4(input.Position, 1), ViewProjection);
    output.Color = input.Color;
    return output;
}
float4 fragment_main(VsOutput input) : SV_Target0 { return input.Color * Tint; }
