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


asset_load_texture_file :: proc(copy_pass: ^sdl.GPUCopyPass, texture_file: string) -> ^sdl.GPUTexture {

    // Get the Texture Path
    texture_path := filepath.join({ASSETS_DIR, "textures", texture_file}, context.temp_allocator)

    // Clone the Texture Path
    texture_file := strings.clone_to_cstring(texture_path, context.temp_allocator)
    
    // Load the image
    image_size: Vec2i
    
    pixels := stbi.load(texture_file, &image_size.x, &image_size.y, nil, 4); sdl_assert(pixels != nil)
    pixles_byte_size := image_size.x * image_size.y * 4

    // Upload the Texture Data to the Texture Buffer
    texture := gpu_upload_texture(copy_pass, slice.bytes_from_ptr(pixels, int(pixles_byte_size)), u32(image_size.x), u32(image_size.y))

    // Release the Image Pixels
    stbi.image_free(pixels)

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

asset_load_model :: proc(copy_pass: ^sdl.GPUCopyPass, mesh_file: string, diffuse_texture_file: string, specular_color: Vec3, specular_shininess: f32) -> Model {

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