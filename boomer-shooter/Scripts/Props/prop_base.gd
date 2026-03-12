extends Node3D
class_name PropBase

enum PlacementKind {
	CENTER,
	WALL_OFFSET,
	FLOOR_DECAL,
	CEILING_HANG,
}

@export var placement_kind: PlacementKind = PlacementKind.CENTER
@export var random_y_rotation: bool = true
@export var random_y_rotation_min: float = 0.0
@export var random_y_rotation_max: float = 360.0

func place(base_pos: Vector3, wall_offset: Vector3, rng: RandomNumberGenerator) -> void:
	position = _resolve_position(base_pos, wall_offset)
	if random_y_rotation:
		rotation_degrees.y = rng.randf_range(random_y_rotation_min, random_y_rotation_max)
	if has_method("_on_placed"):
		call("_on_placed", rng)

func _resolve_position(base_pos: Vector3, wall_offset: Vector3) -> Vector3:
	match placement_kind:
		PlacementKind.WALL_OFFSET:
			return base_pos + wall_offset
		PlacementKind.FLOOR_DECAL:
			return Vector3(base_pos.x, 0.05, base_pos.z)
		PlacementKind.CEILING_HANG:
			return base_pos + wall_offset
		_:
			return base_pos + wall_offset
