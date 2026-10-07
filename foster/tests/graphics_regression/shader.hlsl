struct VertexInput { float2 pos : TEXCOORD0; };
float4 vertex_main(VertexInput input) : SV_Position {
    return float4(input.pos, 0, 1);
}

// Valid shader, deliberately incompatible with the mesh's TEXCOORD0 input.
float4 incompatible_vertex(float2 pos : TEXCOORD7) : SV_Position {
    return float4(pos, 0, 1);
}

cbuffer Params : register(b0, space3) { float4 value; };
struct Outputs { float4 first : SV_Target0; float4 second : SV_Target1; };
Outputs fragment_main() {
    Outputs output;
    output.first = value;
    output.second = value * 2;
    return output;
}
