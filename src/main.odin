package main

import "base:runtime"

import "core:encoding/json"
import "core:log"
import "core:math"
import "core:math/linalg"
import "core:mem"
import "core:strings"
import "core:path/filepath"
import "core:os"

import sdl "vendor:sdl3"

sdl_log_context: runtime.Context

WINDOW_WIDTH :: 1920
WINDOW_HEIGHT :: 1080
WINDOW_TITLE :: "Fenrir"

init :: proc() {

    // Init SDL Log Context
    init_sdl_logging()

    // Initialize SDL
    ok := sdl.Init({.VIDEO}); sdl_assert(ok)

    // Initialize Window
    g.window = sdl.CreateWindow(WINDOW_TITLE, WINDOW_WIDTH, WINDOW_HEIGHT, {}); sdl_assert(g.window != nil)

    // Initialize the GPU device
    g.gpu = sdl.CreateGPUDevice({.SPIRV, .DXIL, .MSL}, true, nil); sdl_assert(g.gpu != nil)

    // Claim window for the GPU device
    ok = sdl.ClaimWindowForGPUDevice(g.gpu, g.window); sdl_assert(ok)

    // Set the Swapchain to SDR Linear
    ok = sdl.SetGPUSwapchainParameters(g.gpu, g.window, .SDR_LINEAR, .VSYNC); sdl_assert(ok)

    // Get the Swapchain Texture Format
    g.swapchain_texture_format = sdl.GetGPUSwapchainTextureFormat(g.gpu, g.window)

    // Get the Window Size
    ok = sdl.GetWindowSize(g.window, &g.window_size.x, &g.window_size.y); sdl_assert(ok)
    
    // Try to get the depth texture format
    try_depth_format :: proc(format: sdl.GPUTextureFormat) {
        if sdl.GPUTextureSupportsFormat(g.gpu, format, .D2, {.DEPTH_STENCIL_TARGET}) {
            g.depth_texture_format = format
        }
    }

    try_depth_format(.D16_UNORM)
    try_depth_format(.D24_UNORM)

    // Create a Depth Texture
    g.depth_texture = sdl.CreateGPUTexture(g.gpu, {
        format = g.depth_texture_format,
        usage = {.DEPTH_STENCIL_TARGET},
        width = u32(g.window_size.x),
        height = u32(g.window_size.y),
        layer_count_or_depth = 1,
        num_levels = 1,
    }); sdl_assert(g.depth_texture != nil)


    // Set Window Relative Mouse Mode 
    ok = sdl.SetWindowRelativeMouseMode(g.window, true); sdl_assert(ok)

}

init_sdl_logging :: proc() {
    
    @static sdl_log_context: runtime.Context
    
    sdl_log_context = context
    sdl_log_context.logger.options = {.Short_File_Path, .Line, .Procedure}
    
    sdl.SetLogPriorities(.VERBOSE)
    sdl.SetLogOutputFunction(sdl_log, &sdl_log_context)

}

sdl_log :: proc "c" (userdata: rawptr, category: sdl.LogCategory, priority: sdl.LogPriority, message: cstring) {
    
    // Set the Context
    context = (transmute(^runtime.Context)userdata)^

    // Set the Log Level
    level: log.Level

    // Set the Log Level
    switch priority {
    case .INVALID, .TRACE, .VERBOSE, .DEBUG: level = .Debug
    case .INFO: level = .Info
    case .WARN: level = .Warning
    case .ERROR: level = .Error
    case .CRITICAL: level = .Fatal
    }

    // Log the Message
    log.logf(level, "SDL {}: {}", category, message)   
}

main :: proc() {

    // *
    // * Initialize
    // *

    init()
    game_init()
    camera_init()

    // Delta Time
    last_tick := sdl.GetTicks()

    // Clear Color
    g.clear_color = {0, 0.0312, 0.1276, 1}

    // *
    // * Main Loop
    // *

    main_loop: for {

        free_all(context.temp_allocator)

        g.mouse_movement = {}

        // Calculate Delta Time
        new_tick := sdl.GetTicks()
        delta_time := f32(new_tick - last_tick) / 1000
        
        // Set the last tick
        last_tick = new_tick

        ui_input_mode := !sdl.GetWindowRelativeMouseMode(g.window)

        // Process SDL events
        event: sdl.Event
        for sdl.PollEvent(&event) {
            
            // ImGui Events
            if ui_input_mode do imgui_process_event(&event)
            
            #partial switch event.type {
                case .QUIT:
                    break main_loop
                case .KEY_DOWN:

                    // Escape will Exit when not in UI Input Mode
                    if !ui_input_mode {
                        if event.key.scancode == .ESCAPE do break main_loop
                    }
                    
                    // Tab will Toggle UI Input Mode
                    if event.key.scancode == .F1 {
                        ok := sdl.SetWindowRelativeMouseMode(g.window, ui_input_mode); sdl_assert(ok)
                        ui_input_mode = !ui_input_mode
                    }

                    // Set the Key Down
                    g.key_down[event.key.scancode] = true

                case .KEY_UP:
                    if !ui_input_mode {
                        g.key_down[event.key.scancode] = false
                    }
                case .MOUSE_MOTION:
                    if !ui_input_mode {
                        g.mouse_movement = {f32(event.motion.xrel), f32(event.motion.yrel)}
                    }
            }
        }

        
        // *
        // * Update Game State
        // *

        game_update(delta_time)

        // *
        // * Update ImGui
        // *

        imgui_update(delta_time)
        
        // *
        // * Render
        // *

        // Create Command Buffer
        command_buf := sdl.AcquireGPUCommandBuffer(g.gpu); sdl_assert(command_buf != nil)

        // Create a Swapchain Texture
        swapchain_texture: ^sdl.GPUTexture

        // Wait for the swapchain texture and acquire it
        ok := sdl.WaitAndAcquireGPUSwapchainTexture(command_buf, g.window, &swapchain_texture, nil, nil); sdl_assert(ok)

        // Create a View Matrix
        view_matrix := linalg.matrix4_look_at_f32(g.camera.position, g.camera.target, {0, 1, 0})

        // Create a Model Matrix
        model_matrix := linalg.matrix4_translate_f32({0, 0, 0}) * linalg.matrix4_rotate_f32(g.rotation, {0, 1, 0})

        // Create a UBO
        ubo := UBO {
            material_view_projection = g.projection_matrix * view_matrix * model_matrix,
        }

        // Draw if we have a swapchain texture
        if swapchain_texture != nil {
        
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


            // Push the Vertex Uniform Data
            sdl.PushGPUVertexUniformData(command_buf, 0, &ubo, size_of(ubo))
            
            // Bind the Graphics Pipeline
            sdl.BindGPUGraphicsPipeline(render_pass, g.pipeline)

            // Bind the Vertex Buffer
            sdl.BindGPUVertexBuffers(render_pass, 0, &(sdl.GPUBufferBinding { buffer = g.model.vertex_buf }), 1)

            // Bind the Index Buffer
            sdl.BindGPUIndexBuffer(render_pass, { buffer = g.model.index_buf }, ._16BIT)

            // Bind the Fragment Sampler
            sdl.BindGPUFragmentSamplers(render_pass, 0, &(sdl.GPUTextureSamplerBinding { texture = g.model.texture, sampler = g.sampler }), 1)

            // Draw the Indexed Primitives
            sdl.DrawGPUIndexedPrimitives(render_pass, g.model.num_indicies, 1, 0, 0, 0)

            // End the main render pass
            sdl.EndGPURenderPass(render_pass)

            // *
            // * ImGui
            // *
            imgui_render(command_buf, swapchain_texture)
            
        }

        // Submit the command buffer
        ok = sdl.SubmitGPUCommandBuffer(command_buf); sdl_assert(ok)
    }

}

update_camera :: proc(dt: f32) {


}