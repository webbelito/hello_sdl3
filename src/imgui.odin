package main

import "core:fmt"
import "core:math/linalg"


import sdl "vendor:sdl3"

import im "shared:imgui"
import im_sdl "shared:imgui/imgui_impl_sdl3"
import im_sdlgpu "shared:imgui/imgui_impl_sdlgpu3"

imgui_init :: proc() {
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

imgui_update :: proc(delta_time: f32) {
    
    // Update ImGui
    im_sdlgpu.NewFrame()
    im_sdl.NewFrame()
    im.NewFrame()

    // Update the inspector
    imgui_update_inspector()
}

imgui_process_event :: proc(event: ^sdl.Event) {
    im_sdl.ProcessEvent(event)
}

imgui_render :: proc(command_buf: ^sdl.GPUCommandBuffer, swapchain_texture: ^sdl.GPUTexture) {

    im.Render()
    im_draw_data := im.GetDrawData()
    
    if im_draw_data.DisplaySize.x > 0 && im_draw_data.DisplaySize.y > 0 {
        im_sdlgpu.PrepareDrawData(im_draw_data, command_buf)

        // Create a color target info
        im_color_target := sdl.GPUColorTargetInfo {
            texture = swapchain_texture,
            load_op = .LOAD,
            store_op = .STORE,
        }

        // Begin a render pass
        im_render_pass := sdl.BeginGPURenderPass(command_buf, &im_color_target, 1, nil); sdl_assert(im_render_pass != nil)

        // Render the draw data
        im_sdlgpu.RenderDrawData(im_draw_data, command_buf, im_render_pass)

        // End the render pass
        sdl.EndGPURenderPass(im_render_pass)
    }
}

imgui_update_inspector :: proc() {

    if im.Begin("Inspector") {
        im.Checkbox("Rotate", &g.should_rotate)
        im.ColorEdit3("Clear Color", transmute(^[3]f32)&g.clear_color, {.Float})
        im.ColorEdit3("Ambient Light", &g.ambient_light_color, {.Float})

        im.SeparatorText("Light")
        im.DragFloat3("Position", &g.light_position, 0.1, -10, 10)
        im.ColorEdit3("Color", &g.light_color, {.Float})
        im.DragFloat("Intensity", &g.light_intensity, 0.01, 0, 1000)

        for entity in g.entities {
            im.PushIDInt(i32(entity.id))

            im.SeparatorText(fmt.ctprintf("Entity {}", entity.id))

            model := g.models[entity.model_id]
            im.ColorEdit3("Specular Color", &model.material.specular_color, {.Float})
            im.DragFloat("Shininess", &model.material.specular_shininess, 0.1, 0, 1000)

            im.PopID()
        }
    }
    im.End()
}

