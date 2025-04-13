package main

import "base:runtime"

import "core:log"
import "core:math/linalg"
import "core:mem"

import sdl "vendor:sdl3"

default_context : runtime.Context

Vec3 :: distinct [3]f32

Vertex_Data :: struct {
    position: Vec3,
    color: sdl.FColor,
}

UBO :: struct {
    material_view_projection: matrix[4, 4]f32,
}

WINDOW_WIDTH :: 1920
WINDOW_HEIGHT :: 1080
WINDOW_TITLE :: "Hello SDL"

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
    vertex_shader := load_shader(gpu, vertex_shader_code, .VERTEX, 1)
    fragment_shader := load_shader(gpu, fragment_shader_code, .FRAGMENT, 0)

    // *
    // * Vertex Data
    // *

    // Create Vertex Data
    verticies := []Vertex_Data {
        { position = {-0.5, -0.5, 0}, color = {1, 0, 0, 1} },
        { position = {   0,  0.5, 0}, color = {0, 1, 0, 1} },
        { position = { 0.5, -0.5, 0}, color = {0, 0, 1, 1} },
    }

    // Calculate the size of the vertex data
    verticies_byte_size := len(verticies) * size_of(Vertex_Data)

    // Create a Vertex Buffer
    vertex_buf := sdl.CreateGPUBuffer(gpu, {
        usage = {.VERTEX},
        size = u32(verticies_byte_size),
    }); assert(vertex_buf != nil)

    // Create a Transfer Buffer
    transfer_buf := sdl.CreateGPUTransferBuffer(gpu, {
        usage = .UPLOAD,
        size = u32(verticies_byte_size),
    }); assert(transfer_buf != nil)

    // Map the Transfer Buffer
    transfer_mem := sdl.MapGPUTransferBuffer(gpu, transfer_buf, false); assert(transfer_mem != nil)

    // Copy the Vertex Data to the Transfer Buffer
    mem.copy(transfer_mem, raw_data(verticies), verticies_byte_size)

    // Unmap the Transfer Buffer
    sdl.UnmapGPUTransferBuffer(gpu, transfer_buf)

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

    // End the Copy Pass
    sdl.EndGPUCopyPass(copy_pass)

    // Submit the Copy Command Buffer
    ok = sdl.SubmitGPUCommandBuffer(copy_command_buf); assert(ok)

    // Release the Copy Command Buffer
    sdl.ReleaseGPUTransferBuffer(gpu, transfer_buf)

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
        target_info = {
            num_color_targets = 1,
            color_target_descriptions = &(sdl.GPUColorTargetDescription {
                format = sdl.GetGPUSwapchainTextureFormat(gpu ,window),
            }),
        },
    }); assert(pipeline != nil)

    // Release the shaders
    sdl.ReleaseGPUShader(gpu, vertex_shader)
    sdl.ReleaseGPUShader(gpu, fragment_shader)

    // Get the Window Size
    window_size: [2]i32
    ok = sdl.GetWindowSize(window, &window_size.x, &window_size.y); assert(ok)

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
        model_matrix := linalg.matrix4_translate_f32({0, 0, -5}) * linalg.matrix4_rotate_f32(rotation, {0, 1, 0})

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

            // Begin a render pass
            render_pass := sdl.BeginGPURenderPass(command_buf, &color_target, 1, nil); assert(render_pass != nil)

            // Bind the Graphics Pipeline
            sdl.BindGPUGraphicsPipeline(render_pass, pipeline)

            // Bind the Vertex Buffer
            sdl.BindGPUVertexBuffers(render_pass, 0, &(sdl.GPUBufferBinding { buffer = vertex_buf }), 1)

            // Push the Vertex Uniform Data
            sdl.PushGPUVertexUniformData(command_buf, 0, &ubo, size_of(UBO))

            // Draw a triangle
            sdl.DrawGPUPrimitives(render_pass, 3, 1, 0, 0)

            // End the render pass
            sdl.EndGPURenderPass(render_pass)

        }

        // Submit the command buffer
        ok = sdl.SubmitGPUCommandBuffer(command_buf); assert(ok)
    }

}


load_shader :: proc(device: ^sdl.GPUDevice, code: []u8, stage: sdl.GPUShaderStage, num_uniform_buffers: u32) -> ^sdl.GPUShader {

    // Create a shader
    shader := sdl.CreateGPUShader(device, {
        code_size = len(code),
        code = raw_data(code),
        entrypoint = "main",
        format = {.SPIRV},
        stage = stage,
        num_uniform_buffers = num_uniform_buffers,
    }); assert(shader != nil)

    return shader

}

