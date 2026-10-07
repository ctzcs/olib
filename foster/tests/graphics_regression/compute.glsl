#version 450
layout(local_size_x = 4, local_size_y = 4) in;
layout(set = 0, binding = 0, rgba32f) readonly uniform image2D input_texture;
layout(set = 0, binding = 1) readonly buffer Input { vec4 values[]; } input_buffer;
layout(set = 1, binding = 0, rgba32f) uniform image2D output_texture;
layout(set = 1, binding = 1) buffer Output { vec4 values[]; } output_buffer;
layout(set = 2, binding = 0) uniform Params { vec4 offset; };
void main() {
    ivec2 id = ivec2(gl_GlobalInvocationID.xy);
    vec4 result = imageLoad(input_texture, id) + input_buffer.values[id.x + id.y * 8] + offset;
    imageStore(output_texture, id, result);
    output_buffer.values[id.x + id.y * 8] = result * 2;
}
