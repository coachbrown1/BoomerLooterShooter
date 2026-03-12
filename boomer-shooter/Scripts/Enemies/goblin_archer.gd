extends EnemyBase
class_name GoblinArcher

@export var projectile_scene: PackedScene = preload("res://Scenes/Projectiles/projectile.tscn")
@export var min_distance: float = 7.0
@export var optimal_distance: float = 12.0
@export var strafe_speed: float = 2.0
@export var flee_health_threshold: int = 20
@export var min_strafe_time_before_shot: float = 0.7

var strafe_dir: float = 1.0
var strafe_timer: float = 0.0
var current_strafe_duration: float = 2.0
var attack_ready_timer: float = 0.0

func _ready() -> void:
	super._ready()
	strafe_dir = 1.0 if randf() > 0.5 else -1.0
	current_strafe_duration = randf_range(2.0, 4.0)

func _move_towards_player() -> void:
	if not player: return
	attack_ready_timer += get_physics_process_delta_time()

	var dist_squared = global_position.distance_squared_to(player.global_position)
	var dir_to_player = global_position.direction_to(player.global_position)
	dir_to_player.y = 0
	dir_to_player = dir_to_player.normalized()

	var current_health = health_component.current_health if health_component else 100

	if current_health <= flee_health_threshold:
		# Flee away from player
		var flee_dir = -dir_to_player
		velocity.x = flee_dir.x * move_speed * 1.2
		velocity.z = flee_dir.z * move_speed * 1.2
		return

	strafe_timer += get_physics_process_delta_time()
	if strafe_timer > current_strafe_duration:
		strafe_timer = 0.0
		strafe_dir *= -1.0
		current_strafe_duration = randf_range(2.0, 4.0)

	var right_dir = dir_to_player.cross(Vector3.UP).normalized()

	if dist_squared < min_distance * min_distance:
		# Back up and strafe
		var flee_dir = -dir_to_player
		var move_dir = (flee_dir + (right_dir * strafe_dir * 0.5)).normalized()
		velocity.x = move_dir.x * move_speed
		velocity.z = move_dir.z * move_speed
	elif dist_squared > optimal_distance * optimal_distance:
		# Move closer and strafe
		nav_agent.target_position = player.global_position
		var next_nav_point = nav_agent.get_next_path_position()
		var move_dir = global_position.direction_to(next_nav_point)
		move_dir.y = 0
		move_dir = (move_dir.normalized() + (right_dir * strafe_dir * 0.3)).normalized()
		velocity.x = move_dir.x * move_speed
		velocity.z = move_dir.z * move_speed
	else:
		# Just strafe
		var move_dir = right_dir * strafe_dir
		velocity.x = move_dir.x * strafe_speed
		velocity.z = move_dir.z * strafe_speed

func _start_windup() -> void:
	# Line of sight check before attacking
	if not _has_line_of_sight():
		# Try to move slightly if no line of sight, continue chasing
		current_state = State.CHASE
		return

	attack_ready_timer = 0.0
	super._start_windup()

func _should_start_windup(dist_to_player: float) -> bool:
	if player == null:
		return false

	var current_health = health_component.current_health if health_component else 100
	if current_health <= flee_health_threshold:
		return false

	if dist_to_player < min_distance * 0.9:
		return false

	if attack_ready_timer < min_strafe_time_before_shot:
		return false

	if not _has_line_of_sight():
		return false

	return dist_to_player <= _get_windup_start_range()

func _has_line_of_sight() -> bool:
	if not player: return false

	var space_state = get_world_3d().direct_space_state
	var origin = global_position + Vector3(0, actual_height * 0.75, 0)
	var target = player.global_position + Vector3(0, 1.0, 0)

	var query = PhysicsRayQueryParameters3D.create(origin, target)
	# Only world / prop geometry should block LOS.
	query.exclude = [self.get_rid()]
	query.collision_mask = 1

	var result = space_state.intersect_ray(query)
	return result.is_empty()

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
