extends EnemyBase
class_name EnemyRanged

@export var projectile_scene: PackedScene = preload("res://Scenes/Projectiles/projectile.tscn")
@export var min_distance: float = 7.0

func _move_towards_player() -> void:
	if not player: return
	
	var dist_squared = global_position.distance_squared_to(player.global_position)
	if dist_squared < min_distance * min_distance:
		# Simple: Backup away slightly if too close
		var flee_dir = player.global_position.direction_to(global_position)
		flee_dir.y = 0
		velocity.x = flee_dir.x * move_speed * 0.5
		velocity.z = flee_dir.z * move_speed * 0.5
	else:
		super._move_towards_player()

func _process_windup_effect() -> void:
	pass

func _execute_attack() -> void:
	# Release the "arrow"
	if player and projectile_scene:
		var proj = projectile_scene.instantiate()
		get_parent().add_child(proj)
		
		# Offset slightly for eye level
		proj.global_position = global_position + Vector3(0, actual_height * 0.75, 0)
		
		var dir = (player.global_position + Vector3(0, 1.0, 0) - proj.global_position).normalized()
		proj.direction = dir
		proj.look_at(proj.global_position + dir) # if it had a mesh that mattered for alignment
		
	billboard_sprite.modulate = Color(1.0, 1.0, 1.0, 1.0)
	super._execute_attack()
