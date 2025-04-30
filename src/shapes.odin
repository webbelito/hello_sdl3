package main

import sdl "vendor:sdl3"

// Context to hold temporary vertex/index data during shape generation.
@(private)
Shape_Context :: struct {
	vertices:       []Vertex_Data,
	indices:        []u16,
	next_vertex_id: int,
	next_index_id:  int,
}

// Defines parameters for generating one side (row or column) of a plane.
@(private)
Plane_Side :: struct {
	segments:      int,  // Number of subdivisions along this side.
	position_step: Vec3, // 3D vector to move for each segment step.
	uv_step:       Vec2, // 2D texture coordinate vector for each segment step.
}

// Generates a flat plane mesh on the XZ plane.
shapes_generate_plane_mesh :: proc(copy_pass: ^sdl.GPUCopyPass, width: f32, depth: f32, segments_x: int = 1, segments_z: int = 1) -> Mesh {

	num_vertices := get_plane_num_vertices(segments_x, segments_z)
	num_indices := get_plane_num_indices(segments_x, segments_z)

	vertices := make([]Vertex_Data, num_vertices)
	indices := make([]u16, num_indices)

	defer {
		delete(vertices)
		delete(indices)
	}

	xLeft := -width * 0.5
	xRight := width * 0.5
	zFront := depth * 0.5
	zBack := -depth * 0.5

	dx := width / f32(segments_x)
	dz := depth / f32(segments_z)

	ctx := Shape_Context {
		vertices = vertices,
		indices = indices,
	}

	// Build the plane geometry.
	build_plane(&ctx,
		start_position = {xLeft, 0, zFront},
		start_uv = {0, 0}, // Assuming (0,0) is Top-Left UV
		normal = {0, 1, 0}, // Normal points up (Y+)
		row = {segments_x, {dx, 0, 0}, {1 / f32(segments_x), 0}}, // Row along X+
		col = {segments_z, {0, 0, dz}, {0, 1 / f32(segments_z)}}, // Col along Z+ -> Maps to V+
	)

	return gpu_upload_mesh(copy_pass, vertices, indices)
}

// Generates a cube mesh composed of 6 planes.
shapes_generate_cube_mesh :: proc(copy_pass: ^sdl.GPUCopyPass, width: f32, height: f32, depth: f32, segments_x: int = 1, segments_y: int = 1, segments_z: int = 1) -> Mesh {

	// Calculate total vertices and indices needed.
	num_vertices := (
		get_plane_num_vertices(segments_x, segments_z) * 2 + // Top/Bottom
		get_plane_num_vertices(segments_x, segments_y) * 2 + // Front/Back
		get_plane_num_vertices(segments_y, segments_z) * 2)  // Left/Right

	num_indices := (
		get_plane_num_indices(segments_x, segments_z) * 2 + // Top/Bottom
		get_plane_num_indices(segments_x, segments_y) * 2 + // Front/Back
		get_plane_num_indices(segments_y, segments_z) * 2)  // Left/Right

	// Allocate temporary buffers.
	vertices := make([]Vertex_Data, num_vertices)
	indices := make([]u16, num_indices)

	// Ensure buffers are deleted upon exit.
	defer {
		delete(vertices)
		delete(indices)
	}

	// Define cube corner coordinates.
	xLeft := -width * 0.5
	xRight := width * 0.5
	yTop := height * 0.5
	yBottom := -height * 0.5
	zFront := depth * 0.5
	zBack := -depth * 0.5

	// Calculate positive step distances per segment.
	dx := width / f32(segments_x)
	dy := height / f32(segments_y)
	dz := depth / f32(segments_z)

	// Calculate positive UV step sizes per segment.
	sx := f32(max(1, segments_x))
	sy := f32(max(1, segments_y))
	sz := f32(max(1, segments_z))
	u_step_x := 1 / sx
	v_step_y := 1 / sy
	u_step_z := 1 / sz
	v_step_z := 1 / sz
	v_step_x := 1 / sx

	// Initialize generation context.
	ctx := Shape_Context {
		vertices = vertices,
		indices = indices,
	}

	// Build Left face (-X)
	build_plane(&ctx,
		start_position = {xLeft, yTop, zBack},
		start_uv = {0, 0},
		normal = {-1, 0, 0},
		row = {segments_y, {0, -dy, 0}, {0, v_step_y}},
		col = {segments_z, {0, 0, dz}, {u_step_z, 0}},
	)

	// Build Right face (+X)
	build_plane(&ctx,
		start_position = {xRight, yTop, zFront},
		start_uv = {0, 0},
		normal = {1, 0, 0},
		row = {segments_y, {0, -dy, 0}, {0, v_step_y}},
		col = {segments_z, {0, 0, -dz}, {u_step_z, 0}},
	)

	// Build Top face (+Y)
	build_plane(&ctx,
		start_position = {xLeft, yTop, zFront},
		start_uv = {0, 0},
		normal = {0, 1, 0},
		row = {segments_x, {dx, 0, 0}, {u_step_x, 0}},
		col = {segments_z, {0, 0, -dz}, {0, v_step_z}},
	)

	// Build Bottom face (-Y)
	build_plane(&ctx,
		start_position = {xLeft, yBottom, zBack},
		start_uv = {0, 0},
		normal = {0, -1, 0},
		row = {segments_x, {dx, 0, 0}, {u_step_x, 0}},
		col = {segments_z, {0, 0, dz}, {0, v_step_z}},
	)

	// Build Front face (+Z)
	build_plane(&ctx,
		start_position = {xRight, yTop, zFront},
		start_uv = {1, 0}, // Adjusted UV start/step for orientation
		normal = {0, 0, 1},
		row = {segments_x, {-dx, 0, 0}, {-u_step_x, 0}},
		col = {segments_y, {0, -dy, 0}, {0, v_step_y}},
	)

	// Build Back face (-Z)
	build_plane(&ctx,
		start_position = {xLeft, yTop, zBack},
		start_uv = {1, 0}, // Adjusted UV start/step for orientation
		normal = {0, 0, -1},
		row = {segments_x, {dx, 0, 0}, {-u_step_x, 0}},
		col = {segments_y, {0, -dy, 0}, {0, v_step_y}},
	)

	// Upload generated data to GPU.
	return gpu_upload_mesh(copy_pass, vertices, indices)
}

// Adds a single vertex to the context buffers.
@(private)
add_vertex :: proc(ctx: ^Shape_Context, vertex: Vertex_Data) {
	ctx.vertices[ctx.next_vertex_id] = vertex
	ctx.next_vertex_id += 1
}

// Adds a single triangle (3 indices) to the context buffers.
@(private)
add_triangle :: proc(ctx: ^Shape_Context, a: u16, b: u16, c: u16) {
	// Uses CCW winding order (a, b, c) assuming default conventions.
	ctx.indices[ctx.next_index_id] = a
	ctx.indices[ctx.next_index_id + 1] = b
	ctx.indices[ctx.next_index_id + 2] = c
	ctx.next_index_id += 3
}

// Generates vertices and indices for a single rectangular plane based on parameters.
@(private)
build_plane :: proc(ctx: ^Shape_Context, start_position: Vec3, start_uv: Vec2, normal: Vec3, row: Plane_Side, col: Plane_Side) {

	start_index := u16(ctx.next_vertex_id) // Starting index for this plane's vertices.

	// Generate grid of vertices.
	row_position := start_position
	row_uv := start_uv
	for _ in 0 ..= row.segments {
		col_position := row_position
		col_uv := row_uv
		for _ in 0 ..= col.segments {
			add_vertex(ctx, Vertex_Data {
				position = col_position,
				uv = col_uv,
				normal = normal,
				color = WHITE, // Default color
			})
			// Step along the column.
			col_position += col.position_step
			col_uv += col.uv_step
		}
		// Step along the row.
		row_position += row.position_step
		row_uv += row.uv_step
	}

	// Generate indices for the triangles forming the plane.
	for r in 0..< u16(row.segments) {
		for c in 0..< u16(col.segments) {
			// Indices for the four corners of a quad within the grid.
			i00 := start_index + r * u16(col.segments + 1) + c
			i01 := i00 + u16(col.segments + 1)
			i10 := i00 + 1
			i11 := i01 + 1

			// Create two triangles for the quad.
			add_triangle(ctx, i00, i01, i10)
			add_triangle(ctx, i01, i11, i10)
		}
	}
}

// Helper to calculate vertex count for a plane.
@(private)
get_plane_num_vertices :: proc(row_segments: int, column_segments: int) -> int {
	return (row_segments + 1) * (column_segments + 1)
}

// Helper to calculate index count for a plane (2 triangles per quad).
@(private)
get_plane_num_indices :: proc(row_segments: int, column_segments: int) -> int {
	return row_segments * column_segments * 6
}