extends Node
class_name FlickerLight

enum Mode {
	FLICKER,	# Random jumps, good for torches/broken lights
	PULSE,		# Smooth sine wave, good for bio-tech/magic
	STROBE		# Fast on/off, good for alarms
}

@export var light_node: Light3D
@export var sprite_node: Sprite3D # Optional: to pulse the sprite visuals too
@export var mode: Mode = Mode.FLICKER
@export var base_energy: float = 1.0		# The average/intended brightness
@export var max_variation: float = 0.5		# Increased for visibility
@export var speed: float = 1.0

var _timer: float = 0.0
var _offset: float = 0.0
var _base_modulate: Color = Color.WHITE

func _ready() -> void:
	if not light_node:
		var p = get_parent()
		if p is Light3D:
			light_node = p
		elif p.get_parent() is Light3D:
			light_node = p.get_parent()
			
	if not sprite_node:
		# Look for a sprite sibling or parent
		var p = get_parent()
		if p is Sprite3D:
			sprite_node = p
		else:
			sprite_node = _find_sprite_recursive(p)

func _find_sprite_recursive(node: Node) -> Sprite3D:
	for child in node.get_children():
		if child is Sprite3D:
			return child
		var res = _find_sprite_recursive(child)
		if res:
			return res
	return null
	
	if light_node:
		base_energy = light_node.light_energy
	if sprite_node:
		_base_modulate = sprite_node.modulate
	
	_offset = randf() * 100.0

func _process(delta: float) -> void:
	_timer += delta * speed
	var factor: float = 1.0
	
	match mode:
		Mode.FLICKER:
			factor = 1.0 + (randf_range(-1.0, 1.0) * max_variation)
		Mode.PULSE:
			var sine = sin(_timer + _offset)
			factor = 1.0 + (sine * max_variation)
		Mode.STROBE:
			factor = 1.0 if floor(fmod(_timer * 10.0, 2.0)) > 0.5 else 0.0
			
	if light_node:
		light_node.light_energy = base_energy * factor
	
	if sprite_node:
		# Pulse the sprite's brightness by scaling its modulate color
		# We go slightly above 1.0 (overbright) for a "glow" look
		sprite_node.modulate = _base_modulate * (0.7 + factor * 0.6)
