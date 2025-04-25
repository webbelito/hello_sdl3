package main

import "core:strings"
import "core:path/filepath"
import "core:mem"

import sdl "vendor:sdl3"
import stbi "vendor:stb/image"

Vertex_Data :: struct {
    position: Vec3,
    color: sdl.FColor,
    uv: Vec2,
}

UBO :: struct {
    material_view_projection: matrix[4, 4]f32,
}

Model :: struct {
    vertex_buf: ^sdl.GPUBuffer,
    index_buf: ^sdl.GPUBuffer,
    num_indicies: u32,
    texture: ^sdl.GPUTexture,
}

model_load :: proc(mesh_file: string, texture_file: string) -> Model {


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