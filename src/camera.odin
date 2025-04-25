package main

import "core:math"
import "core:math/linalg"

Camera :: struct {
    position: Vec3,
    target: Vec3,
}

Look :: struct {
    yaw: f32,
    pitch: f32,
}

MOUSE_SENSITIVITY :: 3
MOUSE_SENSITIVITY_FACTOR :: 100

PLAYER_HEIGHT :: 1
PLAYER_MOVEMENT_SPEED :: 5

camera_init :: proc() {

    // Create a Camera
    g.camera = {
        position = {0, PLAYER_HEIGHT, 3},
        target = {0, PLAYER_HEIGHT, 0},
    }

}

camera_update :: proc(delta_time: f32) {

    // Create Move Input
    move_input: Vec2

    // Check for Move Input
    if g.key_down[.W] do move_input.y += 1
    if g.key_down[.S] do move_input.y -= 1
    if g.key_down[.A] do move_input.x -= 1
    if g.key_down[.D] do move_input.x += 1
    
    // Create Look Input
    look_input := g.mouse_movement * (MOUSE_SENSITIVITY * MOUSE_SENSITIVITY_FACTOR) * delta_time

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
    movement_motion := linalg.normalize0(movement_direction) * PLAYER_MOVEMENT_SPEED * delta_time

    // Update Position
    g.camera.position += movement_motion

    // Update Target
    g.camera.target = g.camera.position + forward
}
