@tool
extends PropBase
class_name SpriteProp

const OUTLINE_MAT = preload("res://Materials/prop_outline_material.tres")

@export var texture_path: String = ""
@export var pixel_size: float = 0.015
@export var sprite_y_offset: float = 1.0
@export var billboard_mode: BaseMaterial3D.BillboardMode = BaseMaterial3D.BILLBOARD_FIXED_Y
@export var use_outline_material: bool = true
@export var sprite_modulate: Color = Color(1, 1, 1, 1)

var _sprite: Sprite3D

func _ready() -> void:
	_ensure_sprite()

func _on_placed(_rng: RandomNumberGenerator) -> void:
	_ensure_sprite()
	if _sprite == null:
		return
	_sprite.position.y = sprite_y_offset

func _ensure_sprite() -> void:
	if _sprite == null:
		_sprite = get_node_or_null("Sprite3D")
		if _sprite == null:
			_sprite = Sprite3D.new()
			_sprite.name = "Sprite3D"
			add_child(_sprite)
	if texture_path != "":
		var tex := load(texture_path)
		if tex:
			_sprite.texture = tex
	_sprite.pixel_size = pixel_size
	_sprite.billboard = billboard_mode
	_sprite.modulate = sprite_modulate
	if use_outline_material and _sprite.texture:
		_sprite.material_override = OUTLINE_MAT.duplicate()
		_sprite.material_override.set_shader_parameter("texture_albedo", _sprite.texture)
	else:
		_sprite.material_override = null
