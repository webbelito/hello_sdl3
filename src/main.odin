package main

import "base:runtime"
import "core:log"

import sdl "vendor:sdl3"

default_context : runtime.Context

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
    vertex_shader := load_shader(gpu, vertex_shader_code, .VERTEX)
    fragment_shader := load_shader(gpu, fragment_shader_code, .FRAGMENT)

    // Create a Graphics Pipeline
    pipeline := sdl.CreateGPUGraphicsPipeline(gpu, {
        vertex_shader = vertex_shader,
        fragment_shader = fragment_shader,
        primitive_type = .TRIANGLELIST,
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

    // *
    // * Main Loop
    // *

    main_loop: for {

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

            // Draw a triangle
            sdl.DrawGPUPrimitives(render_pass, 3, 1, 0, 0)

            // End the render pass
            sdl.EndGPURenderPass(render_pass)

        }

        // Submit the command buffer
        ok = sdl.SubmitGPUCommandBuffer(command_buf); assert(ok)
    }

}


load_shader :: proc(device: ^sdl.GPUDevice, code: []u8, stage: sdl.GPUShaderStage) -> ^sdl.GPUShader {

    // Create a shader
    shader := sdl.CreateGPUShader(device, {
        code_size = len(code),
        code = raw_data(code),
        entrypoint = "main",
        format = {.SPIRV},
        stage = stage,
    }); assert(shader != nil)

    return shader

}

