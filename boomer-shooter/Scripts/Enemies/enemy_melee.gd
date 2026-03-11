extends EnemyBase
class_name EnemyMelee

func _execute_attack() -> void:
	# End of windup: Check if player is still in range
	if player:
		var dist = global_position.distance_to(player.global_position)
		if dist <= attack_range + 0.5: # Small buffer
			if player.has_method("take_damage"):
				player.take_damage(attack_damage)
			# Visual bite/slash effect could go here
			
	super._execute_attack()
