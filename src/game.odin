package main

import "core:math"
import "core:math/linalg"
import "core:slice"

import sdl "vendor:sdl3"
ROTATION_SPEED :: f32(90) * linalg.RAD_PER_DEG

game_init :: proc() {

    game_setup_pipeline()

    // Create a Copy Command Buffer
    copy_command_buf := sdl.AcquireGPUCommandBuffer(g.gpu); sdl_assert(copy_command_buf != nil)

    // Begin a Copy Pass
    copy_pass := sdl.BeginGPUCopyPass(copy_command_buf); sdl_assert(copy_pass != nil)
    
    // Load the Models
    g.models = slice.clone([]Model {
        asset_load_model(copy_pass, "tractor-police.obj", "colormap.png"),
        asset_load_model(copy_pass, "sedan-sports.obj", "colormap.png"),
        asset_load_model(copy_pass, "ambulance.obj", "colormap.png"),
    })
    
    // End the Copy Pass
    sdl.EndGPUCopyPass(copy_pass)

    // Submit the Copy Command Buffer
    ok := sdl.SubmitGPUCommandBuffer(copy_command_buf); sdl_assert(ok)

    // Create the Entities
    g.entities = slice.clone([]Entity {
        {
            id = 0,
            model_id = 0,
            position = {0, 0, 0},
            rotation = 1,
        },
        {
            id = 1,
            model_id = 1,
            position = {-5, 0, 0},
            rotation = linalg.quaternion_from_euler_angle_y_f32(-15 * linalg.DEG_PER_RAD),
        },
        {
            id = 2,
            model_id = 2,
            position = {5, 0, 0},
            rotation = linalg.quaternion_from_euler_angle_y_f32(15 * linalg.DEG_PER_RAD),
        },
    })

    // Initialize the Should Rotate Flag
    g.should_rotate = true

    // Initialize the Clear Color
    g.clear_color = 0

    // Initialize the Light
    g.light_position = {3, 3, 3}
    g.light_color = {1, 1, 1}
    g.light_intensity = 1

    // Initialize the Camera
    camera_init()
}

game_update :: proc(delta_time: f32) {

    // Rotate the Model
    if g.should_rotate {

        // Rotate the first entity only
        g.entities[0].rotation *= linalg.quaternion_from_euler_angle_y_f32(ROTATION_SPEED * delta_time)
    }

    // Update the Camera
    camera_update(delta_time)

}

game_render :: proc(command_buf: ^sdl.GPUCommandBuffer, swapchain_texture: ^sdl.GPUTexture) {

    // Create a Projection Matrix (Camera)
    g.projection_matrix = linalg.matrix4_perspective_f32(linalg.to_radians(f32(90)), f32(g.window_size.x) / f32(g.window_size.y), 0.0001, 1000)

    // Create a View Matrix
    view_matrix := linalg.matrix4_look_at_f32(g.camera.position, g.camera.target, {0, 1, 0})

    // Create a UBO for the Fragment Shader
    ubo_frag_global := UBO_Frag_Global {
        light_position = g.light_position,
        light_color = g.light_color,
        light_intensity = g.light_intensity,
    }

    // Push the UBO for the Fragment Shader
    sdl.PushGPUFragmentUniformData(command_buf, 0, &ubo_frag_global, size_of(ubo_frag_global))
    
    // Create a color target
    color_target  := sdl.GPUColorTargetInfo {
        texture = swapchain_texture,
        load_op = .CLEAR,
        clear_color = g.clear_color,
        store_op = .STORE,
    }

    // Create a depth target info
    depth_target_info := sdl.GPUDepthStencilTargetInfo {
        texture = g.depth_texture,
        load_op = .CLEAR,
        clear_depth = 1,
        store_op = .DONT_CARE,
    }

    // Begin a render pass
    render_pass := sdl.BeginGPURenderPass(command_buf, &color_target, 1, &depth_target_info); sdl_assert(render_pass != nil)

    for entity in g.entities {
    
        // Create a Model Matrix
        model_matrix := linalg.matrix4_from_trs_f32(entity.position, entity.rotation, 1)


        // Create a UBO
        ubo := UBO {
            view_projection = g.projection_matrix * view_matrix,
            material = model_matrix,
        }

        // Push the Vertex Uniform Data
        sdl.PushGPUVertexUniformData(command_buf, 0, &ubo, size_of(ubo))
        
        // Bind the Graphics Pipeline
        sdl.BindGPUGraphicsPipeline(render_pass, g.pipeline)

        model := g.models[entity.model_id]

        // Bind the Vertex Buffer
        sdl.BindGPUVertexBuffers(render_pass, 0, &(sdl.GPUBufferBinding { buffer = model.vertex_buf }), 1)

        // Bind the Index Buffer
        sdl.BindGPUIndexBuffer(render_pass, { buffer = model.index_buf }, ._16BIT)

        // Bind the Fragment Sampler
        sdl.BindGPUFragmentSamplers(render_pass, 0, &(sdl.GPUTextureSamplerBinding { texture = model.texture, sampler = g.sampler }), 1)

        // Draw the Indexed Primitives
        sdl.DrawGPUIndexedPrimitives(render_pass, model.num_indicies, 1, 0, 0, 0)

    }

    // End the main render pass
    sdl.EndGPURenderPass(render_pass)

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
        {
            location = 3,
            format = .FLOAT3,
            offset = u32(offset_of(Vertex_Data, normal)),
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