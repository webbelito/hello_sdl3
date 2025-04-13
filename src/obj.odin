package main

import "core:strings"
import "core:strconv"
import "core:os"
import "core:log"

Obj_Data :: struct {
    positions: []Vec3,
    uvs: []Vec2,
    faces: []Obj_FaceIndex,
}

Obj_FaceIndex :: struct {
    position: uint,
    uv: uint,
}

obj_load :: proc(filename: string) -> Obj_Data {
    data, ok := os.read_entire_file_from_filename(filename); assert(ok)
    defer delete(data)

    input_string := string(data)

    positions := make([dynamic]Vec3)
    uvs := make([dynamic]Vec2)
    faces := make([dynamic]Obj_FaceIndex)

    // Split the input string into lines
    for line in strings.split_lines_iterator(&input_string) {
        
        // Skip empty lines
        if len(line) == 0 do continue

        switch line[0] {
        case 'v':
            switch line[1] {
            case ' ':
                // Vertex position
                position := obj_parse_position(line[2:])
                append(&positions, position)
            case 't':
                // Vertex texture
                uv := obj_parse_uv(line[3:])
                append(&uvs, uv)
            }
        case 'f': 
            // Faces
            indicies := obj_parse_face(line[2:])
            append_elems(&faces, indicies[0], indicies[1], indicies[2])
        }
    }

    assert(len(positions) > 0 && len(uvs) > 0 && len(faces) > 0)

    return {
        positions = positions[:],
        uvs = uvs[:],
        faces = faces[:],
    }
}

obj_destroy :: proc(data: Obj_Data) {
    delete(data.positions)
    delete(data.uvs)
    delete(data.faces)
}

obj_extract_separated :: proc(value: ^string, separator: byte) -> string {
    sub, ok := strings.split_by_byte_iterator(value, separator); assert(ok)

    return sub
}

obj_parse_f32 :: proc(value: string) -> f32 {
    result, ok := strconv.parse_f32(value); assert(ok)

    return result
}

obj_parse_uint :: proc(value: string) -> uint {
    result, ok := strconv.parse_uint(value); assert(ok)

    return result
}

obj_parse_position :: proc(s: string) -> Vec3 {
    s := s

    return {
        obj_parse_f32(obj_extract_separated(&s, ' ')),
        obj_parse_f32(obj_extract_separated(&s, ' ')),
        obj_parse_f32(obj_extract_separated(&s, ' ')),
    }
}

obj_parse_uv :: proc(s: string) -> Vec2 {
    s := s

    return {
        obj_parse_f32(obj_extract_separated(&s, ' ')),
        obj_parse_f32(obj_extract_separated(&s, ' ')),
    }
}

obj_parse_face_index :: proc(s: string) -> Obj_FaceIndex {
    s := s
    
    return {
        position = obj_parse_uint(obj_extract_separated(&s, '/')) - 1,
        uv = obj_parse_uint(obj_extract_separated(&s, '/')) - 1,
    }
    
}

obj_parse_face :: proc(s: string) -> [3]Obj_FaceIndex {
    s := s
    
    return {
        obj_parse_face_index(obj_extract_separated(&s, ' ')),
        obj_parse_face_index(obj_extract_separated(&s, ' ')),
        obj_parse_face_index(obj_extract_separated(&s, ' ')),
    }
}


