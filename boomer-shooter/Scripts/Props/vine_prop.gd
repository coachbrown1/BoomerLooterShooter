@tool
extends SpriteProp
class_name VineProp

@export var ceiling_height: float = 4.0

func _ready() -> void:
	placement_kind = PlacementKind.CEILING_HANG
	random_y_rotation = false
	super()

func _resolve_position(base_pos: Vector3, wall_offset: Vector3) -> Vector3:
	return base_pos + wall_offset

func _on_placed(rng: RandomNumberGenerator) -> void:
	super(rng)
	if _sprite and _sprite.texture:
		var height := _sprite.texture.get_height() * _sprite.pixel_size
		_sprite.position.y = ceiling_height - (height / 2.0)
