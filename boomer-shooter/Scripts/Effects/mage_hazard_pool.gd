extends Area3D
class_name MageHazardPool

@export var damage_per_tick: int = 6
@export var tick_interval: float = 0.4
@export var lifetime: float = 3.5

var _tick_timer: float = 0.0
var _life_timer: float = 0.0
var _mesh_instance: MeshInstance3D = null
var _light: OmniLight3D = null

func _ready() -> void:
	_mesh_instance = get_node_or_null("MeshInstance3D")
	_light = get_node_or_null("OmniLight3D")

	# Pulse the light using a repeating tween
	if _light:
		var tween := create_tween().set_loops()
		tween.tween_property(_light, "light_energy", 2.2, 0.35).set_trans(Tween.TRANS_SINE)
		tween.tween_property(_light, "light_energy", 1.0, 0.35).set_trans(Tween.TRANS_SINE)

func _process(delta: float) -> void:
	_life_timer += delta

	# Fade out in the last 0.6 seconds
	var remaining := lifetime - _life_timer
	if remaining < 0.6 and _mesh_instance:
		var alpha := clampf(remaining / 0.6, 0.0, 1.0)
		var mat := _mesh_instance.get_active_material(0)
		if mat is StandardMaterial3D:
			mat.albedo_color.a = alpha
		if _light:
			_light.light_energy = alpha * 1.5

	if _life_timer >= lifetime:
		queue_free()
		return

	_tick_timer += delta
	if _tick_timer >= tick_interval:
		_tick_timer -= tick_interval
		_damage_players_inside()

func _damage_players_inside() -> void:
	for body in get_overlapping_bodies():
		if body.is_in_group("player") and body.has_method("take_damage"):
			body.take_damage(damage_per_tick)
