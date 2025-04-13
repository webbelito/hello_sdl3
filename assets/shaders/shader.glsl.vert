#version 460

layout(set=1, binding=0) uniform UBO {
    mat4 material_view_projection;
} ubo;

layout(location = 0) in vec3 position;
layout(location = 1) in vec4 color;
layout(location = 2) in vec2 uv;

layout(location = 0) out vec4 out_color;
layout(location = 1) out vec2 out_uv;

void main() {
    // Set the position
    gl_Position = ubo.material_view_projection * vec4(position, 1.0);

    // Set the color
    out_color = color;

    // Set the uv
    out_uv = uv;
}
