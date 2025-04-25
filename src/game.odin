package main

import "core:math"
import "core:math/linalg"

import sdl "vendor:sdl3"

ROTATION_SPEED :: f32(90) * linalg.RAD_PER_DEG

game_init :: proc() {

    game_setup_pipeline()

    g.model = model_load("tractor-police.obj", "colormap.png")

    g.should_rotate = true

}

game_update :: proc(delta_time: f32) {

    // Rotate the Model
    if g.should_rotate do g.rotation += ROTATION_SPEED * delta_time

    // Update the Camera
    camera_update(delta_time)

}

game_render :: proc() {

}

game_setup_pipeline :: proc() {

    // Load Shaders
    vertex_shader := shader_load(g.gpu, "shader.vert")
    fragment_shader := shader_load(g.gpu, "shader.frag")

    // Create Vertex Attributes
    vertex_attributes := []sdl.GPUVertexAttribute {
        {
            location = 0,
            format = .FLOAT3,
            offset = u32(offset_of(Vertex_Data, position)),
        },
        {
            location = 1,
            format = .FLOAT4,
            offset = u32(offset_of(Vertex_Data, color)),
        },
        {
            location = 2,
            format = .FLOAT2,
            offset = u32(offset_of(Vertex_Data, uv)),
        },
    }
    
    // Create a Graphics Pipeline
    g.pipeline = sdl.CreateGPUGraphicsPipeline(g.gpu, {
        vertex_shader = vertex_shader,
        fragment_shader = fragment_shader,
        primitive_type = .TRIANGLELIST,
        vertex_input_state = {
            vertex_buffer_descriptions = &(sdl.GPUVertexBufferDescription {
                slot = 0,
                pitch = size_of(Vertex_Data),
            }),
            num_vertex_buffers = 1,
            num_vertex_attributes = u32(len(vertex_attributes)),
            vertex_attributes = raw_data(vertex_attributes),
        },
        depth_stencil_state = {
            enable_depth_test = true,
            enable_depth_write = true,
            compare_op = .LESS,
        },
        rasterizer_state = {
            cull_mode = .BACK,
        },
        target_info = {
            num_color_targets = 1,
            color_target_descriptions = &(sdl.GPUColorTargetDescription {
                format = sdl.GetGPUSwapchainTextureFormat(g.gpu, g.window),
            }),
            has_depth_stencil_target = true,
            depth_stencil_format = g.depth_texture_format,
        },
    }); sdl_assert(g.pipeline != nil)

    // Release the shaders
    sdl.ReleaseGPUShader(g.gpu, vertex_shader)
    sdl.ReleaseGPUShader(g.gpu, fragment_shader)
    
    // Create a Sampler
    g.sampler = sdl.CreateGPUSampler(g.gpu, {})

    // Initialize ImGui
    imgui_init()
}