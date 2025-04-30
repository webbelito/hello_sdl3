package main

import "core:path/filepath"
import "core:slice"
import "core:strings"

import sdl "vendor:sdl3"
import stbi "vendor:stb/image"

Vertex_Data :: struct {
    position: Vec3,
    color: sdl.FColor,
    uv: Vec2,
    normal: Vec3,
}

UBO_Vertex_Global :: struct #packed {
    view_projection_matrix: Mat4,
}

UBO_Vertex_Local :: struct #packed {
    model_matrix: Mat4,
    normal_matrix: Mat4,
}


UBO_Frag_Global :: struct #packed {
    light_position: Vec3,
    _: f32,
    light_color: Vec3,
    light_intensity: f32,
    view_position: Vec3,
    _: f32,
    ambient_light_color: Vec3,
}

UBO_Frag_Local :: struct #packed {
    material_specular_color: Vec3,
    material_shininess: f32,
}

Mesh :: struct {
    vertex_buf: ^sdl.GPUBuffer,
    index_buf: ^sdl.GPUBuffer,
    num_indicies: u32,
}

Model :: struct {
    using mesh: Mesh, // TODO: Remove temporary using
    material: Material,
}

Material :: struct {
    diffuse_texture: ^sdl.GPUTexture,
    specular_color: Vec3,
    specular_shininess: f32,
}

asset_load_pixels :: proc(texture_file: string) -> (pixels: []byte, size: [2]u32) {

    texture_path := filepath.join({ASSETS_DIR, "textures", texture_file}, context.temp_allocator)
    texture_file := strings.clone_to_cstring(texture_path, context.temp_allocator)

    image_size: Vec2i

    pixels_data := stbi.load(texture_file, &image_size.x, &image_size.y, nil, 4); assert(pixels_data != nil)
    pixels_byte_size := image_size.x * image_size.y * 4

    pixels = slice.bytes_from_ptr(pixels_data, int(pixels_byte_size))
    size = {u32(image_size.x), u32(image_size.y)}
    
    return

}

assets_free_pixels :: proc(pixels: []byte) {
    stbi.image_free(raw_data(pixels))
}

asset_load_texture_file :: proc(copy_pass: ^sdl.GPUCopyPass, texture_file: string) -> ^sdl.GPUTexture {

    pixels, image_size := asset_load_pixels(texture_file)
    texture := gpu_upload_texture(copy_pass, pixels, image_size.x, image_size.y)
    assets_free_pixels(pixels)
    return texture

}

asset_load_obj_file :: proc(copy_pass: ^sdl.GPUCopyPass, mesh_file: string) -> Mesh {

    // Get the Mesh Path
    mesh_path := filepath.join({ASSETS_DIR, "meshes", mesh_file}, context.temp_allocator)

    // Create Vertex Data
    obj_data := obj_load(mesh_path)

    verticies := make([]Vertex_Data, len(obj_data.faces))
    indices := make([]u16, len(obj_data.faces))

    for face, i in obj_data.faces {
        uv := obj_data.uvs[face.uv]
        verticies[i] = Vertex_Data {
            position = obj_data.positions[face.position],
            normal = obj_data.normals[face.normal],
            color = WHITE,
            uv = {uv.x, 1 - uv.y},
        }
        indices[i] = u16(i)
    }

    obj_destroy(obj_data)

    // Upload the Mesh Data to the Mesh Buffer
    mesh := gpu_upload_mesh(copy_pass, verticies, indices)

    // Delete the Indices
    delete(indices)

    // Delete the Verticies
    delete(verticies)

    return mesh
}

asset_load_model_from_obj_file :: proc(copy_pass: ^sdl.GPUCopyPass, mesh_file: string, diffuse_texture_file: string, specular_color: Vec3, specular_shininess: f32) -> Model {

    // Load the texture
    diffuse_texture := asset_load_texture_file(copy_pass, diffuse_texture_file)

    material := Material {
        diffuse_texture = diffuse_texture,
        specular_color = specular_color,
        specular_shininess = specular_shininess,
    }

    // Load the mesh
    mesh := asset_load_obj_file(copy_pass, mesh_file)

    return {
        mesh = mesh,
        material = material,
    }
}

asset_load_model_from_mesh :: proc(copy_pass: ^sdl.GPUCopyPass, mesh: Mesh, diffuse_texture_file: string, specular_color: Vec3, specular_shininess: f32) -> Model {

    // Load the texture
    diffuse_texture := asset_load_texture_file(copy_pass, diffuse_texture_file)
    
    material := Material {
        diffuse_texture = diffuse_texture,
        specular_color = specular_color,
        specular_shininess = specular_shininess,
    }

    return {
        mesh = mesh,
        material = material,
    }
}

assets_load_cubemap_texture_file :: proc(copy_pass: ^sdl.GPUCopyPass, texture_files: [sdl.GPUCubeMapFace]string) -> ^sdl.GPUTexture {

    // Create a Pixels Array
    pixels: [sdl.GPUCubeMapFace][]byte
    size: u32

    // Load the Pixels
    for texture_file, side in texture_files {
        side_pixels, image_size := asset_load_pixels(texture_file)
        pixels[side] = side_pixels
        
        assert(image_size.x == image_size.y)

        if size == 0 {
            size = image_size.x
        } else {
            assert(size == image_size.x)
        }
    }

    // Upload the Pixels
    texture := gpu_upload_cubemap_texture_split(copy_pass, pixels, size)
    
    // Free the Pixels
    for side_pixels in pixels {
        assets_free_pixels(side_pixels)
    }

    return texture
}