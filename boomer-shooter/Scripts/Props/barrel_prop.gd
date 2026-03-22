@tool
extends PropBase
class_name BarrelProp

func _ready() -> void:
	placement_kind = PlacementKind.WALL_OFFSET
	random_y_rotation = true

func _on_placed(rng: RandomNumberGenerator) -> void:
	rotation_degrees.y = rng.randf_range(0, 360)
