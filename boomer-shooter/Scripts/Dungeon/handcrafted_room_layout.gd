@tool
extends Node3D
class_name HandcraftedRoomLayout

@export var allow_random_orientation: bool = false

func get_random_y_rotation_radians(rng: RandomNumberGenerator) -> float:
	if not allow_random_orientation or rng == null:
		return 0.0
	return deg_to_rad(90.0 * float(rng.randi_range(0, 3)))
