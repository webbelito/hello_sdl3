#version 460

layout(location = 0) in vec4 color;
layout(location = 0) out vec4 fragment_color;

void main() {
    // Set the fragment color
    fragment_color = color;
}