extends EnemyBase
class_name EnemyChaser

var attack_cooldown: float = 1.0
var time_since_attack: float = 0.0

func _perform_attack() -> void:
	time_since_attack += get_physics_process_delta_time()

	if time_since_attack >= attack_cooldown:
		time_since_attack = 0.0
		if player and global_position.distance_to(player.global_position) <= attack_range:
			if player.has_method("take_damage"):
				player.take_damage(attack_damage)
