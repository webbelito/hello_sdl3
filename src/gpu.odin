package main

import "core:mem"
import "core:slice"

import sdl "vendor:sdl3"

gpu_upload_texture :: proc(copy_pass: ^sdl.GPUCopyPass, pixels: []u8, width: u32, height: u32) -> ^sdl.GPUTexture {

    // Create a Texture
    texture := sdl.CreateGPUTexture(g.gpu, {
        format = .R8G8B8A8_UNORM_SRGB,
        usage = {.SAMPLER}, 
        width = width,
        height = height,
        layer_count_or_depth = 1,
        num_levels = 1,
    }); sdl_assert(texture != nil)

    // Create a Texture Transfer Buffer
    texture_transfer_buf := sdl.CreateGPUTransferBuffer(g.gpu, {
        usage = .UPLOAD,
        size = u32(len(pixels)),
    }); sdl_assert(texture_transfer_buf != nil)

    // Map the Texture Transfer Buffer
    texture_transfer_mem := sdl.MapGPUTransferBuffer(g.gpu, texture_transfer_buf, false); sdl_assert(texture_transfer_mem != nil)

    // Copy the Texture Data to the Texture Transfer Buffer
    mem.copy(texture_transfer_mem, raw_data(pixels), len(pixels))

    // Unmap the Texture Transfer Buffer
    sdl.UnmapGPUTransferBuffer(g.gpu, texture_transfer_buf)
    
    // Upload the Texture Data to the Texture Buffer
    sdl.UploadToGPUTexture(copy_pass, 
        { transfer_buffer = texture_transfer_buf },
        { texture = texture, w = width, h = height, d = 1 },
        false,
    )

    // Release the Texture Transfer Buffer
    sdl.ReleaseGPUTransferBuffer(g.gpu, texture_transfer_buf)

    return texture
}

gpu_upload_mesh :: proc(copy_pass: ^sdl.GPUCopyPass, vertices: []$T, indices: []$S) -> Mesh {
    return gpu_upload_mesh_bytes(copy_pass, slice.to_bytes(vertices), slice.to_bytes(indices), len(indices))
}

gpu_upload_mesh_bytes :: proc(copy_pass: ^sdl.GPUCopyPass, vertices: []byte, indices: []byte, num_indices: int) -> Mesh {
    
    // Calculate the size of the verticies
    verticies_byte_size := len(vertices)

    // Calculate the size of the index data
    indices_byte_size := len(indices)

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
    mem.copy(transfer_mem, raw_data(vertices), verticies_byte_size)

    // Copy the Index Data to the Transfer Buffer
    mem.copy(transfer_mem[verticies_byte_size:], raw_data(indices), indices_byte_size)

    // Unmap the Transfer Buffer
    sdl.UnmapGPUTransferBuffer(g.gpu, transfer_buf)

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

    // Release the Transfer Buffer
    sdl.ReleaseGPUTransferBuffer(g.gpu, transfer_buf)

    return Mesh {
        vertex_buf = vertex_buf,
        index_buf = index_buf,
        num_indicies = u32(num_indices),
    }
}