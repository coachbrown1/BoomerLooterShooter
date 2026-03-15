extends EnemyRanged
class_name CourtMageRanged

# Match the orb's exported values in mage_energy_orb.tscn
const _ORB_SPEED: float = 11.0
const _ORB_GRAVITY: float = 5.0

func _start_windup() -> void:
	super._start_windup()
	# Show first frame of the cast row (row 1, hframes=6 → frame 6)
	billboard_sprite.animate = false
	billboard_sprite.frame = 6

func _process_windup_effect() -> void:
	# Advance through cast row (frames 6–11) over the windup duration
	var progress := clampf(_attack_timer / windup_time, 0.0, 1.0)
	billboard_sprite.frame = 6 + clampi(int(progress * 6.0), 0, 5)

func _execute_attack() -> void:
	if player and projectile_scene:
		var proj := projectile_scene.instantiate()

		# Aim upward to compensate for gravity so the orb arcs onto the target
		var spawn_pos: Vector3 = global_position + Vector3(0, actual_height * 0.75, 0)
		var target_pos: Vector3 = player.global_position + Vector3(0, 1.0, 0)
		var dist: float = spawn_pos.distance_to(target_pos)
		var time_of_flight: float = dist / _ORB_SPEED
		var arc_up: float = 0.5 * _ORB_GRAVITY * time_of_flight * time_of_flight
		var aim_target: Vector3 = target_pos + Vector3(0, arc_up, 0)
		var dir: Vector3 = (aim_target - spawn_pos).normalized()

		# Projectile._ready() derives velocity from direction, so set launch state
		# before adding it to the tree.
		proj.direction = dir
		proj.shooter = self
		get_parent().add_child(proj)
		proj.global_position = spawn_pos
		proj.look_at(spawn_pos + dir)

	billboard_sprite.modulate = Color(1, 1, 1, 1)
	# Replicate EnemyBase._execute_attack state transition (skip EnemyRanged super
	# to avoid it firing a second projectile with wrong aim)
	current_state = State.ATTACK
	billboard_sprite.animate = true
