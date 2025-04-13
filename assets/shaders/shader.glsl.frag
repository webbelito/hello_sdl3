#version 460

layout(location = 0) in vec4 color;
layout(location = 1) in vec2 uv;

layout(location = 0) out vec4 fragment_color;

layout(set = 2, binding = 0) uniform sampler2D texture_sampler;

void main() {
    // Set the fragment color, using the texture and the color
    fragment_color = texture(texture_sampler, uv) * color;
}