package main

import "base:runtime"

import "core:log"
import "core:math/linalg"
import "core:mem"

import sdl "vendor:sdl3"
import stbi "vendor:stb/image"

default_context : runtime.Context

Vec2 :: distinct [2]f32
Vec3 :: distinct [3]f32

Vec2i :: distinct [2]i32
Vec3i :: distinct [3]i32

Vertex_Data :: struct {
    position: Vec3,
    color: sdl.FColor,
    uv: Vec2,
}

UBO :: struct {
    material_view_projection: matrix[4, 4]f32,
}

WINDOW_WIDTH :: 1920
WINDOW_HEIGHT :: 1080
WINDOW_TITLE :: "Hello SDL"

WHITE :: sdl.FColor { 1, 1, 1, 1 }

DEPTH_TEXTURE_FORMAT :: sdl.GPUTextureFormat.D24_UNORM

// Load Shader file as binary
vertex_shader_code := #load("../assets/shaders/bin/shader.spv.vert")
fragment_shader_code := #load("../assets/shaders/bin/shader.spv.frag")

main :: proc() {

    // *
    // * Initialize
    // *

    // Initialize logger
    context.logger = log.create_console_logger()
    default_context = context

    sdl.SetLogPriorities(.VERBOSE)
    sdl.SetLogOutputFunction(proc "c" (userdata: rawptr, category: sdl.LogCategory, priority: sdl.LogPriority, message: cstring) {
        context = default_context
        log.debugf("sdl: {} [{}]: {}", category, priority, message)
    }, nil)

    // Initialize SDL
    ok := sdl.Init({.VIDEO}); assert(ok)

    // Initialize Window
    window := sdl.CreateWindow(WINDOW_TITLE, WINDOW_WIDTH, WINDOW_HEIGHT, {}); assert(window != nil)

    // Initialize the GPU device
    gpu := sdl.CreateGPUDevice({.SPIRV}, true, nil); assert(gpu != nil)

    // Claim window for the GPU device
    ok = sdl.ClaimWindowForGPUDevice(gpu, window); assert(ok)

    // Load Shaders
    vertex_shader := load_shader(gpu, vertex_shader_code, .VERTEX, num_uniform_buffers = 1, num_samplers = 0)
    fragment_shader := load_shader(gpu, fragment_shader_code, .FRAGMENT, num_uniform_buffers = 0, num_samplers = 1)

    
    // Load the image
    image_size: Vec2i
    
    image_pixels := stbi.load("assets/textures/colormap.png", &image_size.x, &image_size.y, nil, 4); assert(image_pixels != nil)
    image_pixles_byte_size := image_size.x * image_size.y * 4
    
    // Create a Texture
    texture := sdl.CreateGPUTexture(gpu, {
        format = .R8G8B8A8_UNORM,
        usage = {.SAMPLER}, 
        width = u32(image_size.x),
        height = u32(image_size.y),
        layer_count_or_depth = 1,
        num_levels = 1,
    }); assert(texture != nil)

    window_size: Vec2i
    ok = sdl.GetWindowSize(window, &window_size.x, &window_size.y); assert(ok)

    depth_texture := sdl.CreateGPUTexture(gpu, {
        format = DEPTH_TEXTURE_FORMAT,
        usage = {.DEPTH_STENCIL_TARGET},
        width = u32(window_size.x),
        height = u32(window_size.y),
        layer_count_or_depth = 1,
        num_levels = 1,
    }); assert(depth_texture != nil)

    // *
    // * Vertex Data
    // *

    // Create Vertex Data
    obj_data := obj_load("assets/meshes/ambulance.obj")

    verticies := make([]Vertex_Data, len(obj_data.faces))
    indices := make([]u16, len(obj_data.faces))

    for face, i in obj_data.faces {
        uv := obj_data.uvs[face.uv]
        verticies[i] = Vertex_Data {
            position = obj_data.positions[face.position],
            color = WHITE,
            uv = {uv.x, 1 - uv.y},
        }
        indices[i] = u16(i)
    }

    obj_destroy(obj_data)

    // Calculate the number of indicies
    num_indicies := len(indices)

    // Calculate the size of the verticies
    verticies_byte_size := len(verticies) * size_of(verticies[0])

    // Calculate the size of the index data
    indices_byte_size := len(indices) * size_of(indices[0])

    // Create a Vertex Buffer
    vertex_buf := sdl.CreateGPUBuffer(gpu, {
        usage = {.VERTEX},
        size = u32(verticies_byte_size),
    }); assert(vertex_buf != nil)

    // Create an Index Buffer
    index_buf := sdl.CreateGPUBuffer(gpu, {
        usage = {.INDEX},
        size = u32(indices_byte_size),
    }); assert(index_buf != nil)

    // Create a Transfer Buffer
    transfer_buf := sdl.CreateGPUTransferBuffer(gpu, {
        usage = .UPLOAD,
        size = u32(verticies_byte_size + indices_byte_size),
    }); assert(transfer_buf != nil)

    // Map the Transfer Buffer
    transfer_mem := transmute([^]byte)sdl.MapGPUTransferBuffer(gpu, transfer_buf, false); assert(transfer_mem != nil)

    // Copy the Vertex Data to the Transfer Buffer
    mem.copy(transfer_mem, raw_data(verticies), verticies_byte_size)

    // Copy the Index Data to the Transfer Buffer
    mem.copy(transfer_mem[verticies_byte_size:], raw_data(indices), indices_byte_size)

    // Unmap the Transfer Buffer
    sdl.UnmapGPUTransferBuffer(gpu, transfer_buf)

    // Delete the Indices
    delete(indices)

    // Delete the Verticies
    delete(verticies)

    // Create a Texture Transfer Buffer
    texture_transfer_buf := sdl.CreateGPUTransferBuffer(gpu, {
        usage = .UPLOAD,
        size = u32(image_pixles_byte_size),
    }); assert(texture_transfer_buf != nil)

    // Map the Texture Transfer Buffer
    texture_transfer_mem := sdl.MapGPUTransferBuffer(gpu, texture_transfer_buf, false); assert(texture_transfer_mem != nil)

    // Copy the Texture Data to the Texture Transfer Buffer
    mem.copy(texture_transfer_mem, image_pixels, int(image_pixles_byte_size))

    // Unmap the Texture Transfer Buffer
    sdl.UnmapGPUTransferBuffer(gpu, texture_transfer_buf)

    // Create a Copy Command Buffer
    copy_command_buf := sdl.AcquireGPUCommandBuffer(gpu); assert(copy_command_buf != nil)

    // Begin a Copy Pass
    copy_pass := sdl.BeginGPUCopyPass(copy_command_buf); assert(copy_pass != nil)

    // Upload the Vertex Data to the Vertex Buffer
    sdl.UploadToGPUBuffer(copy_pass, 
        { transfer_buffer = transfer_buf },
        { buffer = vertex_buf, size = u32(verticies_byte_size)},
        false,
    )

    // Upload the Index Data to the Index Buffer
    sdl.UploadToGPUBuffer(copy_pass, 
        { transfer_buffer = transfer_buf, offset = u32(verticies_byte_size) },
        { buffer = index_buf, size = u32(indices_byte_size) },
        false,
    )

    // Upload the Texture Data to the Texture Buffer
    sdl.UploadToGPUTexture(copy_pass, 
        { transfer_buffer = texture_transfer_buf },
        { texture = texture, w = u32(image_size.x), h = u32(image_size.y), d = 1 },
        false,
    )

    // End the Copy Pass
    sdl.EndGPUCopyPass(copy_pass)

    // Submit the Copy Command Buffer
    ok = sdl.SubmitGPUCommandBuffer(copy_command_buf); assert(ok)

    // Release the Copy Command Buffer
    sdl.ReleaseGPUTransferBuffer(gpu, transfer_buf)
    sdl.ReleaseGPUTransferBuffer(gpu, texture_transfer_buf)

    // Create a Sampler
    sampler := sdl.CreateGPUSampler(gpu, {})

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
    pipeline := sdl.CreateGPUGraphicsPipeline(gpu, {
        vertex_shader = vertex_shader,
        fragment_shader = fragment_shader,
        primitive_type = .TRIANGLELIST,
        vertex_input_state = {
            vertex_buffer_descriptions = &(sdl.GPUVertexBufferDescription {
                slot = 0,
                pitch = size_of(Vertex_Data),
            }),
            num_vertex_buffers = 1,
            vertex_attributes = raw_data(vertex_attributes),
            num_vertex_attributes = u32(len(vertex_attributes)),
        },
        depth_stencil_state = {
            enable_depth_test = true,
            enable_depth_write = true,
            compare_op = .LESS,
        },
        target_info = {
            num_color_targets = 1,
            color_target_descriptions = &(sdl.GPUColorTargetDescription {
                format = sdl.GetGPUSwapchainTextureFormat(gpu ,window),
            }),
            has_depth_stencil_target = true,
            depth_stencil_format = DEPTH_TEXTURE_FORMAT,
        },
    }); assert(pipeline != nil)

    // Release the shaders
    sdl.ReleaseGPUShader(gpu, vertex_shader)
    sdl.ReleaseGPUShader(gpu, fragment_shader)

    // Rotation
    ROTATION_SPEED := linalg.to_radians(f32(90))
    rotation: f32

    // Create a Projection Matrix (Camera)
    projection_matrix := linalg.matrix4_perspective_f32(linalg.to_radians(f32(90)), f32(window_size.x) / f32(window_size.y), 0.0001, 1000)

    // Delta Time
    last_tick := sdl.GetTicks()

    // *
    // * Main Loop
    // *

    main_loop: for {

        // Calculate Delta Time
        new_tick := sdl.GetTicks()
        delta_time := f32(new_tick - last_tick) / 1000
        
        // Set the last tick
        last_tick = new_tick

        // Process SDL events
        event: sdl.Event
        for sdl.PollEvent(&event) {
            #partial switch event.type {
                case .QUIT:
                    break main_loop
                case .KEY_DOWN: 
                    if event.key.scancode == .ESCAPE do break main_loop
            }
        }

        // TODO Update Game State
        
        // *
        // * Render
        // *

        // Create Command Buffer
        command_buf := sdl.AcquireGPUCommandBuffer(gpu); assert(command_buf != nil)

        // Create a Swapchain Texture
        swapchain_texture: ^sdl.GPUTexture

        // Wait for the swapchain texture and acquire it
        ok := sdl.WaitAndAcquireGPUSwapchainTexture(command_buf, window, &swapchain_texture, nil, nil); assert(ok)

        // Update the Rotation
        rotation += ROTATION_SPEED * delta_time

        // Create a Model Matrix
        model_matrix := linalg.matrix4_translate_f32({0, -1, -3}) * linalg.matrix4_rotate_f32(rotation, {0, 1, 0})

        // Create a UBO
        ubo := UBO {
            material_view_projection = projection_matrix * model_matrix,
        }

        // Draw if we have a swapchain texture
        if swapchain_texture != nil {
        
            // Create a color target
            color_target  := sdl.GPUColorTargetInfo {
                texture = swapchain_texture,
                load_op = .CLEAR,
                clear_color = {0, 0.2, 0.4, 1},
                store_op = .STORE,
            }

            // Create a depth target info
            depth_target_info := sdl.GPUDepthStencilTargetInfo {
                texture = depth_texture,
                load_op = .CLEAR,
                clear_depth = 1,
                store_op = .DONT_CARE,
            }

            // Begin a render pass
            render_pass := sdl.BeginGPURenderPass(command_buf, &color_target, 1, &depth_target_info); assert(render_pass != nil)

            // Bind the Graphics Pipeline
            sdl.BindGPUGraphicsPipeline(render_pass, pipeline)

            // Bind the Vertex Buffer
            sdl.BindGPUVertexBuffers(render_pass, 0, &(sdl.GPUBufferBinding { buffer = vertex_buf }), 1)

            // Bind the Index Buffer
            sdl.BindGPUIndexBuffer(render_pass, { buffer = index_buf }, ._16BIT)

            // Push the Vertex Uniform Data
            sdl.PushGPUVertexUniformData(command_buf, 0, &ubo, size_of(ubo))

            // Bind the Fragment Sampler
            sdl.BindGPUFragmentSamplers(render_pass, 0, &(sdl.GPUTextureSamplerBinding { texture = texture, sampler = sampler }), 1)

            // Draw the Indexed Primitives
            sdl.DrawGPUIndexedPrimitives(render_pass, u32(num_indicies), 1, 0, 0, 0)

            // End the render pass
            sdl.EndGPURenderPass(render_pass)

        }

        // Submit the command buffer
        ok = sdl.SubmitGPUCommandBuffer(command_buf); assert(ok)
    }

}


load_shader :: proc(device: ^sdl.GPUDevice, code: []u8, stage: sdl.GPUShaderStage, num_uniform_buffers: u32, num_samplers: u32) -> ^sdl.GPUShader {

    // Create a shader
    shader := sdl.CreateGPUShader(device, {
        code_size = len(code),
        code = raw_data(code),
        entrypoint = "main",
        format = {.SPIRV},
        stage = stage,
        num_uniform_buffers = num_uniform_buffers,
        num_samplers = num_samplers,
    }); assert(shader != nil)

    return shader

}

