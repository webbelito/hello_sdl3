package main


Entity :: struct {
    id: Entity_Id,
    model_id: Model_Id,
    position: Vec3,
    rotation: Quat,
}

Model_Id :: distinct int

Entity_Id :: distinct int