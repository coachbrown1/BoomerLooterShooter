extends CharacterBody3D
class_name EnemyBase

enum State { IDLE, CHASE, WINDUP, ATTACK, COOLDOWN, DEAD }
var current_state: State = State.IDLE

@export var move_speed: float = 3.0
@export var attack_damage: int = 10
@export var attack_range: float = 1.5
@export var windup_start_range: float = -1.0
@export var aggro_range: float = 15.0
@export var windup_time: float = 0.5
@export var cooldown_time: float = 1.0
@export var base_max_health: int = 100
@export var base_start_health: int = -1
@export var spawn_cost: float = 1.0
@export var spawn_min_floor: int = 1

@onready var health_component: HealthComponent = $HealthComponent
@onready var hitbox_component: HitboxComponent = $HitboxComponent
@onready var billboard_sprite: BillboardSprite = $Sprite3D
@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D

var player: Node3D = null
var _dungeon_manager: Node = null
var _flash_active: bool = false
var _hitstop_active: bool = false
var _attack_timer: float = 0.0
var actual_height: float = 1.0

signal enemy_died

func _ready() -> void:
	if health_component:
		health_component.max_health = max(1, base_max_health)
		if base_start_health > 0:
			health_component.current_health = clamp(base_start_health, 1, health_component.max_health)
		else:
			health_component.current_health = health_component.max_health

	health_component.died.connect(_on_died)
	health_component.health_changed.connect(_on_health_changed)
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		player = players[0]
	_dungeon_manager = get_tree().get_first_node_in_group("dungeon_manager")
	
	# Align sprite to ground and adjust collision
	if billboard_sprite and billboard_sprite.texture:
		var frame_h = float(billboard_sprite.texture.get_height()) / billboard_sprite.vframes
		actual_height = frame_h * billboard_sprite.pixel_size * billboard_sprite.scale.y
		var actual_h = actual_height
		
		# Position sprite so its bottom is at Y=0
		billboard_sprite.position.y = actual_h / 2.0
		if "base_y" in billboard_sprite:
			billboard_sprite.base_y = billboard_sprite.position.y
		
		# Resize first CollisionShape3D (body)
		var main_col = get_node_or_null("CollisionShape3D")
		if main_col and main_col.shape is CapsuleShape3D:
			# Make shape unique so we don't affect other enemies
			main_col.shape = main_col.shape.duplicate()
			main_col.shape.height = actual_h
			# Keep radius within bounds (don't make it wider than tall)
			main_col.shape.radius = min(0.6, actual_h * 0.4)
			main_col.position.y = actual_h / 2.0
		
		# Resize HitboxCollision
		if hitbox_component:
			var hb_col = hitbox_component.get_node_or_null("CollisionShape3D")
			if hb_col and hb_col.shape is CapsuleShape3D:
				hb_col.shape = hb_col.shape.duplicate()
				hb_col.shape.height = actual_h + 0.1
				hb_col.shape.radius = min(0.75, actual_h * 0.5)
				hb_col.position.y = actual_h / 2.0

func take_damage(amount: int) -> void:
	if health_component:
		health_component.take_damage(amount)

func _physics_process(delta: float) -> void:
	if current_state == State.DEAD or _hitstop_active:
		return

	if not is_on_floor():
		velocity.y -= 9.8 * delta

	_process_state(delta)
	move_and_slide()

func _process_state(delta: float) -> void:
	if not player:
		return

	var dist_squared_to_player = global_position.distance_squared_to(player.global_position)
	var player_in_same_room := _is_player_in_same_room()

	match current_state:
		State.IDLE:
			if player_in_same_room and dist_squared_to_player <= pow(aggro_range, 2):
				current_state = State.CHASE
			else:
				if billboard_sprite.animate:
					billboard_sprite.animate = false
					billboard_sprite.frame = 0
				velocity.x = 0
				velocity.z = 0

		State.CHASE:
			if not player_in_same_room:
				current_state = State.IDLE
				velocity.x = 0
				velocity.z = 0
			elif _should_start_windup(dist_squared_to_player):
				_start_windup()
			elif dist_squared_to_player > pow(aggro_range * 2.0, 2):
				current_state = State.IDLE
			else:
				if not billboard_sprite.animate:
					billboard_sprite.animate = true
				_move_towards_player()

		State.WINDUP:
			if not player_in_same_room:
				current_state = State.IDLE
				_attack_timer = 0.0
				velocity.x = 0
				velocity.z = 0
				return
			velocity.x = 0
			velocity.z = 0
			_attack_timer += delta

			if billboard_sprite.hframes == 8:
				var frame_idx: int = int((_attack_timer / windup_time) * 4.0)
				frame_idx = maxi(0, mini(frame_idx, 3))
				billboard_sprite.frame = 2 + frame_idx

			_process_windup_effect()
			if _attack_timer >= windup_time:
				_attack_timer = 0.0
				_execute_attack()

		State.ATTACK:
			# Moment of attack, then immediately to cooldown
			current_state = State.COOLDOWN

		State.COOLDOWN:
			velocity.x = 0
			velocity.z = 0
			_attack_timer += delta
			if _attack_timer >= cooldown_time:
				_attack_timer = 0.0
				current_state = State.CHASE if player_in_same_room else State.IDLE

func _is_player_in_same_room() -> bool:
	if not is_instance_valid(player):
		return false

	if not is_instance_valid(_dungeon_manager):
		_dungeon_manager = get_tree().get_first_node_in_group("dungeon_manager")

	if not is_instance_valid(_dungeon_manager):
		return true
	if not _dungeon_manager.has_method("get_room_id_for_world_position"):
		return true

	var enemy_room_id := int(_dungeon_manager.call("get_room_id_for_world_position", global_position))
	var player_room_id := int(_dungeon_manager.call("get_room_id_for_world_position", player.global_position))
	if enemy_room_id < 0 or player_room_id < 0:
		return false
	return enemy_room_id == player_room_id

func _move_towards_player() -> void:
	nav_agent.target_position = player.global_position
	var next_nav_point = nav_agent.get_next_path_position()
	var dir = global_position.direction_to(next_nav_point)
	dir.y = 0
	dir = dir.normalized()
	velocity.x = dir.x * move_speed
	velocity.z = dir.z * move_speed

func _get_windup_start_range() -> float:
	if windup_start_range > 0.0:
		return windup_start_range
	return attack_range

func _should_start_windup(dist_squared_to_player: float) -> bool:
	return dist_squared_to_player <= pow(_get_windup_start_range(), 2)

func _start_windup() -> void:
	current_state = State.WINDUP
	_attack_timer = 0.0
	# Show attack frame during windup
	if billboard_sprite.hframes == 8:
		billboard_sprite.animate = false
		billboard_sprite.frame = 2
	elif billboard_sprite.hframes == 5:
		billboard_sprite.animate = false
		billboard_sprite.frame = 2

func _process_windup_effect() -> void:
	# Virtual: Overridden by children for visual windup
	pass

func _execute_attack() -> void:
	# Virtual: Overridden by children for actual attack logic
	current_state = State.ATTACK
	# Resume animation (will cycle walk in COOLDOWN/CHASE)
	billboard_sprite.animate = true

func _on_health_changed(_current: int, _max: int) -> void:
	if _flash_active or current_state == State.DEAD:
		return
	_flash_active = true
	
	background_damage_flash()
	
	await get_tree().create_timer(0.15).timeout
	_flash_active = false

func background_damage_flash() -> void:
	# Red hit flash
	billboard_sprite.modulate = Color(1, 0.1, 0.1, 1)
	
	# Pause anim and show hit (Hurt) frame (Index 3 for 5-frame sheets)
	var was_animating = billboard_sprite.animate
	if billboard_sprite.hframes == 8:
		billboard_sprite.animate = false
		billboard_sprite.frame = 6
	elif billboard_sprite.hframes == 5:
		billboard_sprite.animate = false
		billboard_sprite.frame = 3
	elif billboard_sprite.hframes == 4:
		billboard_sprite.animate = false
		billboard_sprite.frame = 2
		
	var tween = create_tween()
	tween.tween_property(billboard_sprite, "modulate", Color(1, 1, 1, 1), 0.15)
	
	_hitstop_active = true
	var prev_velocity = velocity
	velocity = Vector3.ZERO
	get_tree().create_timer(0.1).timeout.connect(func(): 
		_hitstop_active = false
		if current_state != State.DEAD:
			velocity = prev_velocity
	)
	
	await tween.finished
	if current_state != State.DEAD:
		billboard_sprite.animate = was_animating

const BLOOD_PARTICLES_SCENE = preload("res://Scenes/Effects/blood_particles.tscn")
const ENEMY_GIB_SCENE = preload("res://Scenes/Effects/enemy_gib.tscn")

func _on_died() -> void:
	current_state = State.DEAD
	hitbox_component.set_deferred("monitoring", false)
	hitbox_component.set_deferred("monitorable", false)
	set_deferred("collision_layer", 0)
	
	# Spawn messy debris
	_spawn_death_effects()
	
	# Set to death frame (last index) and stop animation
	if billboard_sprite:
		billboard_sprite.animate = false
		billboard_sprite.frame = billboard_sprite.hframes - 1
	
	var tween = create_tween()
	tween.tween_property(billboard_sprite, "modulate", Color(1, 0, 0, 0), 0.5)
	enemy_died.emit()
	await get_tree().create_timer(0.6).timeout
	queue_free()

func _spawn_death_effects() -> void:
	var spawn_pos = global_position + Vector3.UP * (actual_height / 2.0)
	
	# 1. Large blood burst
	var blood = BLOOD_PARTICLES_SCENE.instantiate()
	get_tree().current_scene.add_child(blood)
	blood.global_position = spawn_pos
	blood.amount = 30 # Extra juicy on death
	
	# 2. Physics Gibs (fleshy chunks)
	for i in range(randi_range(3, 6)):
		var gib = ENEMY_GIB_SCENE.instantiate()
		get_tree().current_scene.add_child(gib)
		gib.global_position = spawn_pos + Vector3(randf_range(-0.3, 0.3), randf_range(0.1, 0.5), randf_range(-0.3, 0.3))
