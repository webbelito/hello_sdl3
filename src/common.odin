package main

import "core:log"

import sdl "vendor:sdl3"

// Common Structures

Globals :: struct {
    gpu: ^sdl.GPUDevice,
    window: ^sdl.Window,
    window_size: Vec2i,
    depth_texture: ^sdl.GPUTexture,
    depth_texture_format: sdl.GPUTextureFormat,
    swapchain_texture: ^sdl.GPUTexture,
    swapchain_texture_format: sdl.GPUTextureFormat,
    key_down: #sparse[sdl.Scancode]bool,
    mouse_movement: Vec2,
    using game: Game_State,
}

// Common Constants

ASSETS_DIR :: "assets"
WHITE :: sdl.FColor { 1, 1, 1, 1 }

// Common Types

Vec2 :: [2]f32
Vec2i :: [2]i32

Vec3 :: [3]f32
Vec3i :: [3]i32

Mat4 :: matrix[4, 4]f32

Quat :: quaternion128

// Common Variables

g: Globals

// Common Procedures

sdl_assert :: proc(ok: bool) {
    if !ok do log.panicf("SDL Error: {}", sdl.GetError())
}
