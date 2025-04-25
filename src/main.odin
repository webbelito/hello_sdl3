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

import im "shared:imgui"
import im_sdl "shared:imgui/imgui_impl_sdl3"
import im_sdlgpu "shared:imgui/imgui_impl_sdlgpu3"

import sdl "vendor:sdl3"
import stbi "vendor:stb/image"

sdl_log_context: runtime.Context

Globals :: struct {
    gpu: ^sdl.GPUDevice,
    window: ^sdl.Window,
    window_size: Vec2i,
    depth_texture: ^sdl.GPUTexture,
    depth_texture_format: sdl.GPUTextureFormat,
    swapchain_texture: ^sdl.GPUTexture,
    swapchain_texture_format: sdl.GPUTextureFormat,
    pipeline: ^sdl.GPUGraphicsPipeline,
    sampler: ^sdl.GPUSampler,
    camera: Camera,
    look: Look,
    key_down: #sparse[sdl.Scancode]bool,
    mouse_movement: Vec2,
}

Vec2 :: [2]f32
Vec3 :: [3]f32

Vec2i :: [2]i32
Vec3i :: [3]i32

Vertex_Data :: struct {
    position: Vec3,
    color: sdl.FColor,
    uv: Vec2,
}

Model :: struct {
    vertex_buf: ^sdl.GPUBuffer,
    index_buf: ^sdl.GPUBuffer,
    num_indicies: u32,
    texture: ^sdl.GPUTexture,
}

Camera :: struct {
    position: Vec3,
    target: Vec3,
}

Look :: struct {
    yaw: f32,
    pitch: f32,
}

UBO :: struct {
    material_view_projection: matrix[4, 4]f32,
}

WINDOW_WIDTH :: 1920
WINDOW_HEIGHT :: 1080
WINDOW_TITLE :: "Hello SDL"

ASSETS_DIR :: "assets"

PLAYER_HEIGHT :: 1
PLAYER_MOVEMENT_SPEED :: 5

MOUSE_SENSITIVITY :: 3
MOUSE_SENSITIVITY_FACTOR :: 100

WHITE :: sdl.FColor { 1, 1, 1, 1 }

g: Globals

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

    // Create a Camera
    g.camera = {
        position = {0, PLAYER_HEIGHT, 3},
        target = {0, PLAYER_HEIGHT, 0},
    }

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

sdl_assert :: proc(ok: bool) {
    if !ok do log.panicf("SDL Error: {}", sdl.GetError())
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

setup_pipeline :: proc() {

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
    init_imgui()
}

init_imgui :: proc() {
    im.CHECKVERSION()
    im.CreateContext()
    im_sdl.InitForSDLGPU(g.window)
    im_sdlgpu.Init(&{
        Device = g.gpu,
        ColorTargetFormat = g.swapchain_texture_format,
    })

    style := im.GetStyle()
    for &color in style.Colors {
        color.rgb = linalg.pow(color.rgb, 2.2)
    }
}

main :: proc() {

    // *
    // * Initialize
    // *
    
    // Initialize logger
    context.logger = log.create_console_logger()
    sdl_log_context = context

    init()
    setup_pipeline()

    model := load_model("tractor-police.obj", "colormap.png")

    // Rotation
    ROTATION_SPEED := linalg.to_radians(f32(90))
    rotation: f32
    should_rotate: bool = true

    // Create a Projection Matrix (Camera)
    projection_matrix := linalg.matrix4_perspective_f32(linalg.to_radians(f32(90)), f32(g.window_size.x) / f32(g.window_size.y), 0.0001, 1000)

    // Delta Time
    last_tick := sdl.GetTicks()

    // Clear Color
    clear_color: sdl.FColor = {0, 0.0312, 0.1276, 1}

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
            if ui_input_mode do im_sdl.ProcessEvent(&event)
            
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
        // * ImGui
        // *

        im_sdlgpu.NewFrame()
        im_sdl.NewFrame()
        im.NewFrame()

        if im.Begin("Inspector") {
            im.Checkbox("Rotate", &should_rotate)
            im.ColorEdit3("Clear Color", transmute(^[3]f32)&clear_color, {.Float})
        }
        im.End()
        
        // *
        // * Update Game State
        // *

        if should_rotate do rotation += ROTATION_SPEED * delta_time
        update_camera(delta_time)
        
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
        model_matrix := linalg.matrix4_translate_f32({0, 0, 0}) * linalg.matrix4_rotate_f32(rotation, {0, 1, 0})

        // Create a UBO
        ubo := UBO {
            material_view_projection = projection_matrix * view_matrix * model_matrix,
        }

        // * ImGui Render
        im.Render()
        im_draw_data := im.GetDrawData()


        // Draw if we have a swapchain texture
        if swapchain_texture != nil {
        
            // Create a color target
            color_target  := sdl.GPUColorTargetInfo {
                texture = swapchain_texture,
                load_op = .CLEAR,
                clear_color = clear_color,
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
            sdl.BindGPUVertexBuffers(render_pass, 0, &(sdl.GPUBufferBinding { buffer = model.vertex_buf }), 1)

            // Bind the Index Buffer
            sdl.BindGPUIndexBuffer(render_pass, { buffer = model.index_buf }, ._16BIT)

            // Bind the Fragment Sampler
            sdl.BindGPUFragmentSamplers(render_pass, 0, &(sdl.GPUTextureSamplerBinding { texture = model.texture, sampler = g.sampler }), 1)

            // Draw the Indexed Primitives
            sdl.DrawGPUIndexedPrimitives(render_pass, model.num_indicies, 1, 0, 0, 0)

            // End the render pass
            sdl.EndGPURenderPass(render_pass)

            // Prepare ImGui Draw Data
            im_sdlgpu.PrepareDrawData(im_draw_data, command_buf)
            im_color_target := sdl.GPUColorTargetInfo {
                texture = swapchain_texture,
                load_op = .LOAD,
                store_op = .STORE,
            }

            // Begin a render pass
            im_render_pass := sdl.BeginGPURenderPass(command_buf, &im_color_target, 1, nil); sdl_assert(im_render_pass != nil)

            // Render the ImGui Draw Data
            im_sdlgpu.RenderDrawData(im_draw_data, command_buf, im_render_pass)

            // End the render pass
            sdl.EndGPURenderPass(im_render_pass)
            
        }

        // Submit the command buffer
        ok = sdl.SubmitGPUCommandBuffer(command_buf); sdl_assert(ok)
    }

}

update_camera :: proc(dt: f32) {

    // Create Move Input
    move_input: Vec2

    // Check for Move Input
    if g.key_down[.W] do move_input.y += 1
    if g.key_down[.S] do move_input.y -= 1
    if g.key_down[.A] do move_input.x -= 1
    if g.key_down[.D] do move_input.x += 1
    
    // Create Look Input
    look_input := g.mouse_movement * (MOUSE_SENSITIVITY * MOUSE_SENSITIVITY_FACTOR) * dt

    // Update Look
    g.look.yaw = math.wrap(g.look.yaw - look_input.x, 360)
    g.look.pitch = math.clamp(g.look.pitch - look_input.y, -89, 89)

    // Create Look Matrix
    look_matrix := linalg.matrix3_from_yaw_pitch_roll_f32(linalg.to_radians(g.look.yaw), linalg.to_radians(g.look.pitch), 0)

    // Create Forward and Right Vectors
    forward := look_matrix * Vec3 {0, 0, -1}
    right := look_matrix * Vec3 {1, 0, 0}

    // Create Movement Direction
    movement_direction := forward * move_input.y + right * move_input.x
    
    // Set the Y to 0
    movement_direction.y = 0

    // Create Movement Motion and Normalize
    movement_motion := linalg.normalize0(movement_direction) * PLAYER_MOVEMENT_SPEED * dt

    // Update Position
    g.camera.position += movement_motion

    // Update Target
    g.camera.target = g.camera.position + forward

}

load_model :: proc(mesh_file: string, texture_file: string) -> Model {


    mesh_path := filepath.join({ASSETS_DIR, "meshes", mesh_file}, context.temp_allocator)
    texture_path := filepath.join({ASSETS_DIR, "textures", texture_file}, context.temp_allocator)

    texture_file := strings.clone_to_cstring(texture_path, context.temp_allocator)

    // Load the image
    image_size: Vec2i
    
    image_pixels := stbi.load(texture_file, &image_size.x, &image_size.y, nil, 4); sdl_assert(image_pixels != nil)
    image_pixles_byte_size := image_size.x * image_size.y * 4
    
    // Create a Texture
    texture := sdl.CreateGPUTexture(g.gpu, {
        format = .R8G8B8A8_UNORM_SRGB,
        usage = {.SAMPLER}, 
        width = u32(image_size.x),
        height = u32(image_size.y),
        layer_count_or_depth = 1,
        num_levels = 1,
    }); sdl_assert(texture != nil)


    // *
    // * Vertex Data
    // *

    // Create Vertex Data
    obj_data := obj_load(mesh_path)

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
    vertex_buf := sdl.CreateGPUBuffer(g.gpu, {
        usage = {.VERTEX},
        size = u32(verticies_byte_size),
    }); sdl_assert(vertex_buf != nil)

    // Create an Index Buffer
    index_buf := sdl.CreateGPUBuffer(g.gpu, {
        usage = {.INDEX},
        size = u32(indices_byte_size),
    }); sdl_assert(index_buf != nil)

    // Create a Transfer Buffer
    transfer_buf := sdl.CreateGPUTransferBuffer(g.gpu, {
        usage = .UPLOAD,
        size = u32(verticies_byte_size + indices_byte_size),
    }); sdl_assert(transfer_buf != nil)

    // Map the Transfer Buffer
    transfer_mem := transmute([^]byte)sdl.MapGPUTransferBuffer(g.gpu, transfer_buf, false); sdl_assert(transfer_mem != nil)

    // Copy the Vertex Data to the Transfer Buffer
    mem.copy(transfer_mem, raw_data(verticies), verticies_byte_size)

    // Copy the Index Data to the Transfer Buffer
    mem.copy(transfer_mem[verticies_byte_size:], raw_data(indices), indices_byte_size)

    // Unmap the Transfer Buffer
    sdl.UnmapGPUTransferBuffer(g.gpu, transfer_buf)

    // Delete the Indices
    delete(indices)

    // Delete the Verticies
    delete(verticies)

    // Create a Texture Transfer Buffer
    texture_transfer_buf := sdl.CreateGPUTransferBuffer(g.gpu, {
        usage = .UPLOAD,
        size = u32(image_pixles_byte_size),
    }); sdl_assert(texture_transfer_buf != nil)

    // Map the Texture Transfer Buffer
    texture_transfer_mem := sdl.MapGPUTransferBuffer(g.gpu, texture_transfer_buf, false); sdl_assert(texture_transfer_mem != nil)

    // Copy the Texture Data to the Texture Transfer Buffer
    mem.copy(texture_transfer_mem, image_pixels, int(image_pixles_byte_size))

    // Unmap the Texture Transfer Buffer
    sdl.UnmapGPUTransferBuffer(g.gpu, texture_transfer_buf)

    // Create a Copy Command Buffer
    copy_command_buf := sdl.AcquireGPUCommandBuffer(g.gpu); sdl_assert(copy_command_buf != nil)

    // Begin a Copy Pass
    copy_pass := sdl.BeginGPUCopyPass(copy_command_buf); sdl_assert(copy_pass != nil)

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
    ok := sdl.SubmitGPUCommandBuffer(copy_command_buf); sdl_assert(ok)

    // Release the Copy Command Buffer
    sdl.ReleaseGPUTransferBuffer(g.gpu, transfer_buf)
    sdl.ReleaseGPUTransferBuffer(g.gpu, texture_transfer_buf)

    // Assert that the Model is not nil
    assert(vertex_buf != nil, "Failed to load model")
    assert(index_buf != nil, "Failed to load model")
    assert(texture != nil, "Failed to load model")

    // Return the Model
    return {
        vertex_buf = vertex_buf,
        index_buf = index_buf,
        num_indicies = u32(num_indicies),
        texture = texture,
    }

}