Texture2D<float4> input_texture : register(t0, space0);
StructuredBuffer<float4> input_buffer : register(t1, space0);
RWTexture2D<float4> output_texture : register(u0, space1);
RWStructuredBuffer<float4> output_buffer : register(u1, space1);
cbuffer ComputeParams : register(b0, space2) { float4 offset; };

[numthreads(4, 4, 1)]
void compute_main(uint3 id : SV_DispatchThreadID) {
    float4 result = input_texture.Load(int3(id.xy, 0)) + input_buffer[id.x + id.y * 8] + offset;
    output_texture[id.xy] = result;
    output_buffer[id.x + id.y * 8] = result * 2;
}
