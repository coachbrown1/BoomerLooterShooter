extends EnemyBase
class_name SporeHusk

@export var aoe_radius: float = 3.5

func _ready() -> void:
	super._ready()
	# Spore Husk has more health
	if health_component:
		health_component.max_health = 150
		health_component.current_health = 150

func _process_windup_effect() -> void:
	# Pulse slightly during windup to indicate an explosion
	var pulse = 1.0 + sin(_attack_timer * 20.0) * 0.1
	billboard_sprite.scale = Vector3(pulse, pulse, pulse)

func _execute_attack() -> void:
	# Reset scale
	billboard_sprite.scale = Vector3.ONE

	# AoE Damage
	if player:
		var dist = global_position.distance_to(player.global_position)
		if dist <= aoe_radius:
			if player.has_method("take_damage"):
				player.take_damage(attack_damage)

	# TODO: Spawn a visual spore cloud effect here

	# Transition to COOLDOWN state since we're bypassing super._execute_attack()
	current_state = State.COOLDOWN
	billboard_sprite.animate = true
