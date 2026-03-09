extends CharacterBody3D

@export var move_speed: float = 6.0
@export var sprint_multiplier: float = 1.5
@export var jump_velocity: float = 5.0
@export var mouse_sensitivity: float = 0.002
@export var gravity: float = 12.0

@export_group("FOV Settings")
@export var base_fov: float = 75.0
@export var sprint_fov: float = 90.0
@export var fov_change_speed: float = 8.0
var _target_fov: float = base_fov
var _fov_kick: float = 0.0

@export_group("Recoil Settings")
var current_recoil: Vector2 = Vector2.ZERO
var target_recoil: Vector2 = Vector2.ZERO
@export var recoil_recovery_speed: float = 8.0
@export var recoil_smoothness: float = 12.0

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var weapon_mount: Node3D = $Head/WeaponMount
@onready var weapon_manager: Node = $Head/WeaponMount


@export var max_health: int = 100
var current_health: int = max_health

func _ready() -> void:
	add_to_group("player")
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	current_health = max_health
	if camera:
		camera.fov = base_fov
	call_deferred("_init_hud")

func _init_hud() -> void:
	var hud = _get_hud()
	if hud:
		hud.update_health(current_health)

func _get_hud() -> Node:
	var huds = get_tree().get_nodes_in_group("hud")
	if huds.size() > 0:
		return huds[0]
	return null

func take_damage(amount: int) -> void:
	if current_health <= 0:
		return
	current_health -= amount
	current_health = max(0, current_health)
	var hud = _get_hud()
	if hud:
		hud.update_health(current_health)
	if current_health <= 0:
		print("Player Died!")


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		# Apply mouse input minus current recoil, so recoil adds to pitch/yaw
		rotate_y(-event.relative.x * mouse_sensitivity)
		head.rotate_x(-event.relative.y * mouse_sensitivity)

		# Clamp head pitch
		head.rotation.x = clamp(head.rotation.x, -deg_to_rad(85), deg_to_rad(85))

	if event.is_action_pressed("ui_cancel"):
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _physics_process(delta: float) -> void:
	_handle_recoil(delta)

	if not is_on_floor():
		velocity.y -= gravity * delta

	if Input.is_action_just_pressed("interact"):
		_try_interact()

	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	var current_speed = move_speed
	if Input.is_action_pressed("sprint"):
		current_speed *= sprint_multiplier
		
	if direction:
		velocity.x = direction.x * current_speed
		velocity.z = direction.z * current_speed
	else:
		velocity.x = move_toward(velocity.x, 0, current_speed)
		velocity.z = move_toward(velocity.z, 0, current_speed)

	_update_fov(delta, input_dir.length() > 0.1 and Input.is_action_pressed("sprint"))
	move_and_slide()

func _update_fov(delta: float, is_sprinting: bool) -> void:
	# Calculate target base FOV
	var target = sprint_fov if is_sprinting else base_fov
	_target_fov = lerp(_target_fov, target, delta * fov_change_speed)
	
	# Apply FOV kick decay
	_fov_kick = lerp(_fov_kick, 0.0, delta * 15.0)
	
	camera.fov = _target_fov + _fov_kick

func apply_fov_kick(amount: float) -> void:
	_fov_kick = amount

func add_camera_recoil(pitch: float, yaw: float) -> void:
	target_recoil += Vector2(yaw, pitch)

func _handle_recoil(delta: float) -> void:
	# Recovery: constantly lerp target recoil back to zero
	target_recoil = target_recoil.lerp(Vector2.ZERO, recoil_recovery_speed * delta)

	# Smoothly apply the target recoil to current recoil
	var prev_recoil = current_recoil
	current_recoil = current_recoil.lerp(target_recoil, recoil_smoothness * delta)

	var recoil_diff = current_recoil - prev_recoil

	# Apply diff to actual rotation
	rotate_y(-recoil_diff.x)
	head.rotate_x(recoil_diff.y)

	# Clamp head rotation
	head.rotation.x = clamp(head.rotation.x, -deg_to_rad(85), deg_to_rad(85))

func _try_interact() -> void:
	var space_state = get_world_3d().direct_space_state
	var origin = camera.global_position
	var forward = -camera.global_transform.basis.z.normalized()
	var ray_end = origin + forward * 3.0

	var query = PhysicsRayQueryParameters3D.create(origin, ray_end)
	query.exclude = [self.get_rid()]

	var result = space_state.intersect_ray(query)
	if result:
		var collider = result.collider
		if collider is DungeonDoor:
			collider.open()
