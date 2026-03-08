extends SpriteProp
class_name FloorDecalProp

func _ready() -> void:
	placement_kind = PlacementKind.FLOOR_DECAL
	random_y_rotation = true
	billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	sprite_y_offset = 0.0
	super()

func _resolve_position(base_pos: Vector3, _wall_offset: Vector3) -> Vector3:
	return Vector3(base_pos.x, 0.05, base_pos.z)

func _on_placed(rng: RandomNumberGenerator) -> void:
	super(rng)
	if _sprite:
		_sprite.rotation_degrees.x = -90.0
