package main

import "core:math"
import "core:math/linalg"
import "core:slice"

import sdl "vendor:sdl3"
ROTATION_SPEED :: f32(90) * linalg.RAD_PER_DEG


Game_State :: struct {
    default_sampler: ^sdl.GPUSampler,
    entity_pipeline: ^sdl.GPUGraphicsPipeline,
    
    skybox_pipeline: ^sdl.GPUGraphicsPipeline,
    skybox_mesh: Mesh,
    skybox_texture: ^sdl.GPUTexture,
    skybox_texture_single: ^sdl.GPUTexture,
    skybox_use_multi_image: bool,

    camera: Camera,
    projection_matrix: Mat4,
    look: Look,

    clear_color: sdl.FColor,
    should_rotate: bool,

    models: []Model,
    entities: []Entity,

    light_shape_pipeline: ^sdl.GPUGraphicsPipeline,
    light_shape_mesh: Mesh,
    light_position: Vec3,
    light_color: Vec3,
    light_intensity: f32,
    ambient_light_color: Vec3,

    ui_input_mode: bool,
}

game_init :: proc() {

    // Setup the Pipelines
    game_setup_pipeline()
    game_setup_light_shape_pipeline()
    game_setup_skybox_pipeline()

    // Configure Default Sampler
    g.default_sampler = sdl.CreateGPUSampler(g.gpu, {
        min_filter = .LINEAR,
        mag_filter = .LINEAR,
    })

    // Create a Copy Command Buffer
    copy_command_buf := sdl.AcquireGPUCommandBuffer(g.gpu); sdl_assert(copy_command_buf != nil)

    // Begin a Copy Pass
    copy_pass := sdl.BeginGPUCopyPass(copy_command_buf); sdl_assert(copy_pass != nil)
    
    // Create Light Shape Mesh
    g.light_shape_mesh = shapes_generate_cube_mesh(copy_pass, 0.2, 0.2, 0.2)

    // Load the Models
    g.models = slice.clone([]Model {
        asset_load_model_from_obj_file(copy_pass, "tractor-police.obj", "colormap.png", 0, 1),
        asset_load_model_from_obj_file(copy_pass, "sedan-sports.obj", "colormap.png", 1, 160),
        asset_load_model_from_obj_file(copy_pass, "ambulance.obj", "colormap.png", {1,0,0}, 80),
        asset_load_model_from_mesh(copy_pass, shapes_generate_plane_mesh(copy_pass, 10, 10), "cobblestone_1.png", specular_color = 0, specular_shininess = 1),
        asset_load_model_from_mesh(copy_pass, shapes_generate_cube_mesh(copy_pass, 1, 1, 1), "wall_prototype_texture_01.png", specular_color = 1, specular_shininess = 100),
    })
    
    // Load the Cubemap Texture
    g.skybox_mesh = shapes_generate_cube_mesh(copy_pass, 2, 2, 2)
    g.skybox_texture = assets_load_cubemap_texture_file(copy_pass, {
        .POSITIVEX = "skyboxes/right.png",
        .NEGATIVEX = "skyboxes/left.png",
        .POSITIVEY = "skyboxes/top.png",
        .NEGATIVEY = "skyboxes/bottom.png",
        .POSITIVEZ = "skyboxes/front.png",
        .NEGATIVEZ = "skyboxes/back.png",
    })

    g.skybox_texture_single = assets_load_cubemap_texture_single(copy_pass, "skyboxes/cubemap.png")
    
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
        {
            id = 3,
            model_id = 3,
        },
        {
            id = 4,
            model_id = 4,
            position = {3, 0.5, 3},
        },
        
    })

    // Initialize the Should Rotate Flag
    g.should_rotate = true

    // Initialize the Light
    g.light_position = {3, 3, 3}
    g.light_color = {1, 1, 1}
    g.light_intensity = 1

    // Initialize the Ambient Light
    g.ambient_light_color = 0.01
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

    // Create a UBO for the Vertex Shader
    ubo_vertex_global := UBO_Vertex_Global {
        view_projection_matrix = g.projection_matrix * view_matrix,
        inverse_view_matrix = linalg.inverse(view_matrix),
        inverse_projection_matrix = linalg.inverse(g.projection_matrix),
    }

    // Push the UBO for the Vertex Shader
    sdl.PushGPUVertexUniformData(command_buf, 0, &ubo_vertex_global, size_of(ubo_vertex_global))

    // Create a UBO for the Fragment Shader
    ubo_frag_global := UBO_Frag_Global {
        light_position = g.light_position,
        light_color = g.light_color,
        light_intensity = g.light_intensity,
        view_position = g.camera.position,
        ambient_light_color = g.ambient_light_color,
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

    // *
    // * Bind Pipelines
    // *

    // Light Shape Pipeline
    {

        // Bind the Graphics Pipeline
        sdl.BindGPUGraphicsPipeline(render_pass, g.light_shape_pipeline)

        // Create a Model Matrix
        model_matrix := linalg.matrix4_translate_f32(g.light_position)
    
        // Push the Model Matrix Vertex Uniform Data
        sdl.PushGPUVertexUniformData(command_buf, 1, &model_matrix, size_of(model_matrix))
    
        // Bind the Light Shape Vertex Buffer
        sdl.BindGPUVertexBuffers(render_pass, 0, &(sdl.GPUBufferBinding { buffer = g.light_shape_mesh.vertex_buf }), 1)

        // Bind the Light Shape Index Buffer
        sdl.BindGPUIndexBuffer(render_pass, { buffer = g.light_shape_mesh.index_buf }, ._16BIT)
        
        // Draw the Light Shape
        sdl.DrawGPUIndexedPrimitives(render_pass, g.light_shape_mesh.num_indicies, 1, 0, 0, 0)
        
    }

    // Entity Pipeline
    {

        // Bind the Graphics Pipeline
        sdl.BindGPUGraphicsPipeline(render_pass, g.entity_pipeline)

        for entity in g.entities {
        
            // Create a Model Matrix
            model_matrix := linalg.matrix4_from_trs_f32(entity.position, entity.rotation, 1)

            // Create a Normal Matrix
            normal_matrix := linalg.inverse_transpose(model_matrix)

            // Create a UBO
            ubo_vertex_local := UBO_Vertex_Local {
                model_matrix = model_matrix,
                normal_matrix = normal_matrix,
            }

            // Push the Vertex Uniform Data
            sdl.PushGPUVertexUniformData(command_buf, 1, &ubo_vertex_local, size_of(ubo_vertex_local))
            
            // Bind the Graphics Pipeline
            sdl.BindGPUGraphicsPipeline(render_pass, g.entity_pipeline)

            model := g.models[entity.model_id]

            // Create the material
            material := model.material

            // Create UBO for the Fragment Shader
            ubo_frag_local := UBO_Frag_Local {
                material_specular_color = material.specular_color,
                material_shininess = material.specular_shininess,
            }

            // Push the Fragment Uniform Data
            sdl.PushGPUFragmentUniformData(command_buf, 1, &ubo_frag_local, size_of(ubo_frag_local))
            
            // Bind the Vertex Buffer
            sdl.BindGPUVertexBuffers(render_pass, 0, &(sdl.GPUBufferBinding { buffer = model.vertex_buf }), 1)

            // Bind the Index Buffer
            sdl.BindGPUIndexBuffer(render_pass, { buffer = model.index_buf }, ._16BIT)

            // Bind the Fragment Sampler
            sdl.BindGPUFragmentSamplers(render_pass, 0, &(sdl.GPUTextureSamplerBinding { texture = material.diffuse_texture, sampler = g.default_sampler }), 1)

            // Draw the Indexed Primitives
            sdl.DrawGPUIndexedPrimitives(render_pass, model.num_indicies, 1, 0, 0, 0)

        }

    }

    // Skybox Pipeline
    {

        skybox_active_texture := g.skybox_use_multi_image ? g.skybox_texture : g.skybox_texture_single

        // Bind the Graphics Pipeline
        sdl.BindGPUGraphicsPipeline(render_pass, g.skybox_pipeline)
 
        // Bind the Fragment Sampler
        sdl.BindGPUFragmentSamplers(render_pass, 0, &(sdl.GPUTextureSamplerBinding { texture = skybox_active_texture, sampler = g.default_sampler }), 1)

        // Draw the Cubemap
        sdl.DrawGPUPrimitives(render_pass, 3, 1, 0, 0)

        
    }

    // End the main render pass
    sdl.EndGPURenderPass(render_pass)

}

// TODO: Unify and abstract the pipeline setup
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
    g.entity_pipeline = sdl.CreateGPUGraphicsPipeline(g.gpu, {
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
    }); sdl_assert(g.entity_pipeline != nil)

    // Release the shaders
    sdl.ReleaseGPUShader(g.gpu, vertex_shader)
    sdl.ReleaseGPUShader(g.gpu, fragment_shader)
    
    // Create a Sampler
    g.default_sampler = sdl.CreateGPUSampler(g.gpu, {})

    // Initialize ImGui
    imgui_init()
}

game_setup_light_shape_pipeline :: proc() {

    // Load Shaders
    vertex_shader := shader_load(g.gpu, "lightshape.vert")
    fragment_shader := shader_load(g.gpu, "lightshape.frag")

    // Create Vertex Attributes
    vertex_attributes := []sdl.GPUVertexAttribute {
        {
            location = 0,
            format = .FLOAT3,
            offset = u32(offset_of(Vertex_Data, position)),
        },
    }
    
    // Create a Graphics Pipeline
    g.light_shape_pipeline = sdl.CreateGPUGraphicsPipeline(g.gpu, {
        vertex_shader = vertex_shader,
        fragment_shader = fragment_shader,
        primitive_type = .TRIANGLELIST,
        vertex_input_state = {
            num_vertex_buffers = 1,
            num_vertex_attributes = u32(len(vertex_attributes)),
            vertex_buffer_descriptions = &(sdl.GPUVertexBufferDescription {
                slot = 0,
                pitch = size_of(Vertex_Data),
            }),
          vertex_attributes = raw_data(vertex_attributes),
        },
        depth_stencil_state = {
            enable_depth_test = true,
            enable_depth_write = true,
            compare_op = .LESS,
        },
        rasterizer_state = {
            cull_mode = .BACK,
            // fill_mode = .LINE,
        },
        target_info = {
            num_color_targets = 1,
            color_target_descriptions = &(sdl.GPUColorTargetDescription {
                format = sdl.GetGPUSwapchainTextureFormat(g.gpu, g.window),
            }),
            has_depth_stencil_target = true,
            depth_stencil_format = g.depth_texture_format,
        },
    }); sdl_assert(g.light_shape_pipeline != nil)

    // Release the shaders
    sdl.ReleaseGPUShader(g.gpu, vertex_shader)
    sdl.ReleaseGPUShader(g.gpu, fragment_shader)
}

game_setup_skybox_pipeline :: proc() {

    // Load Shaders
    vertex_shader := shader_load(g.gpu, "skybox.vert")
    fragment_shader := shader_load(g.gpu, "skybox.frag")

    // Create a Graphics Pipeline
    g.skybox_pipeline = sdl.CreateGPUGraphicsPipeline(g.gpu, {
        vertex_shader = vertex_shader,
        fragment_shader = fragment_shader,
        primitive_type = .TRIANGLELIST,
        depth_stencil_state = {
            enable_depth_test = true,
            enable_depth_write = false,
            compare_op = .EQUAL,
        },
        rasterizer_state = {
            cull_mode = .BACK,
        },
        target_info = {
            num_color_targets = 1,
            color_target_descriptions = &(sdl.GPUColorTargetDescription {
                format = g.swapchain_texture_format,
            }),
            has_depth_stencil_target = true,
            depth_stencil_format = g.depth_texture_format,
        },
    }); sdl_assert(g.skybox_pipeline != nil)

    // Release the shaders
    sdl.ReleaseGPUShader(g.gpu, vertex_shader)
    sdl.ReleaseGPUShader(g.gpu, fragment_shader)
    
    

}
