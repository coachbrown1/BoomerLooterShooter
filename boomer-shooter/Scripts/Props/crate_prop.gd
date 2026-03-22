@tool
extends PropBase
class_name CrateProp

func _ready() -> void:
	placement_kind = PlacementKind.WALL_OFFSET
	random_y_rotation = true
	random_y_rotation_min = 0.0
	random_y_rotation_max = 270.0

func _on_placed(rng: RandomNumberGenerator) -> void:
	rotation_degrees.y = float(rng.randi() % 4) * 90.0
