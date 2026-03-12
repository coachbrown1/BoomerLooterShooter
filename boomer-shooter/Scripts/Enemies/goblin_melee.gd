extends EnemyBase
class_name GoblinMelee

@export var lunge_speed_multiplier: float = 3.0

var _is_lunging: bool = false
var _lunge_dir: Vector3

func _process_state(delta: float) -> void:
	super._process_state(delta)

	if _is_lunging:
		velocity.x = _lunge_dir.x * move_speed * lunge_speed_multiplier
		velocity.z = _lunge_dir.z * move_speed * lunge_speed_multiplier

func _start_windup() -> void:
	if player:
		_lunge_dir = global_position.direction_to(player.global_position)
		_lunge_dir.y = 0
		_lunge_dir = _lunge_dir.normalized()
	else:
		_lunge_dir = Vector3.ZERO

	super._start_windup()

func _process_windup_effect() -> void:
	# Lunge forward during windup
	if _attack_timer >= windup_time * 0.5:
		_is_lunging = true
	else:
		_is_lunging = false

func _execute_attack() -> void:
	_is_lunging = false
	# End of windup: Check if player is still in range
	if player:
		var dist_squared = global_position.distance_squared_to(player.global_position)
		if dist_squared <= pow(attack_range + 0.5, 2): # Small buffer
			if player.has_method("take_damage"):
				player.take_damage(attack_damage)
			# Visual bite/slash effect could go here

	super._execute_attack()
