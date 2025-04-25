package main

import "core:encoding/json"
import "core:log"
import "core:os"
import "core:path/filepath"
import "core:strings"

import sdl "vendor:sdl3"

Shader_Info :: struct {
    samplers: u32,
    storage_textures: u32,
    storage_buffers: u32,
    uniform_buffers: u32,
}

// Creates and returns a GPU shader from a shader file.
// The shader stage is determined by the file extension (.vert for vertex, .frag for fragment).
// The shader format is automatically selected based on device support (SPIR-V, DXIL, or MSL).
// 
// device: The GPU device to create the shader for
// shader_file: The name of the shader file (without extension) to load
// 
// Returns a pointer to the created GPU shader, or nil if creation fails
shader_load :: proc(device: ^sdl.GPUDevice, shader_file: string) -> ^sdl.GPUShader {

    // Determine shader stage
    stage: sdl.GPUShaderStage
    
    switch filepath.ext(shader_file) {
    case ".vert":
        stage = .VERTEX
    case ".frag":
        stage = .FRAGMENT
    }

    // Format flag
    format: sdl.GPUShaderFormat
    format_ext: string 
    
    // Entrypoint
    entrypoint: string

    // Get the supported formats
    supported_formats := sdl.GetGPUShaderFormats(device)

    if .SPIRV in supported_formats {
        format = {.SPIRV}
        format_ext = ".spv"
        entrypoint = "main"
    } else if .DXIL in supported_formats {
        format = {.DXIL}
        format_ext = ".dxil"
        entrypoint = "main"
    } else if .MSL in supported_formats {
        format = {.MSL}
        format_ext = ".msl"
        entrypoint = "main0"
    } else {
        log.errorf("No supported shader format found: {}", supported_formats)
        os.exit(1)
    }

    // Load the shader code
    shaderfile := filepath.join({ASSETS_DIR, "shaders", "bin", shader_file}, context.temp_allocator);
    filename := strings.concatenate({shaderfile, format_ext}, context.temp_allocator); sdl_assert(os.exists(filename))
    code, ok := os.read_entire_file_from_filename(filename, context.temp_allocator); sdl_assert(ok)

    // Load the shader info from the Shader json file
    shader_info := shader_load_info(shaderfile)

    // Create a shader
    return sdl.CreateGPUShader(device, {
        code_size = len(code),
        code = raw_data(code),
        entrypoint = strings.clone_to_cstring(entrypoint, context.temp_allocator),
        format = format,
        stage = stage, 
        num_uniform_buffers = shader_info.uniform_buffers,
        num_samplers = shader_info.samplers,
        num_storage_textures = shader_info.storage_textures,
        num_storage_buffers = shader_info.storage_buffers,
    })

}

// Loads and parses shader metadata from a JSON file.
// The JSON file should contain information about the shader's resource requirements.
// 
// shader_file: The base path to the shader file (without extension)
// 
// Returns a Shader_Info struct containing the number of:
// - samplers
// - storage textures
// - storage buffers
// - uniform buffers
shader_load_info :: proc(shader_file: string) -> Shader_Info {

    // Get the JSON file name
    json_filename := strings.concatenate({shader_file, ".json"}, context.temp_allocator)

    // Read the JSON file
    json_data, ok := os.read_entire_file_from_filename(json_filename, context.temp_allocator); sdl_assert(ok)

    // Unmarshal the JSON data
    shader_info: Shader_Info
    err := json.unmarshal(json_data, &shader_info, allocator = context.temp_allocator); sdl_assert(err == nil)

    return shader_info
}