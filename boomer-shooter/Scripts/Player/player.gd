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

var _cached_hud: Node = null

@export_group("Recoil Settings")
var current_recoil: Vector2 = Vector2.ZERO
var target_recoil: Vector2 = Vector2.ZERO
@export var recoil_recovery_speed: float = 8.0
@export var recoil_smoothness: float = 12.0

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var weapon_mount: Node3D = $Head/WeaponMount
@onready var weapon_manager: WeaponManager = $Head/WeaponMount
@onready var inventory_system: InventorySystem = $InventorySystem
@onready var visuals: Node3D = $Visuals

var network_peer_id: int = 0
var _is_local_controlled: bool = true
var _network_target_position: Vector3 = Vector3.ZERO
var _network_target_velocity: Vector3 = Vector3.ZERO
var _network_target_yaw: float = 0.0
var _network_target_pitch: float = 0.0
var _has_network_snapshot: bool = false
var _local_setup_complete: bool = false
var _gameplay_input_enabled: bool = true

const FULLSCREEN_TOGGLE_KEYS: Array[Key] = [KEY_F11]
const WINDOWED_SIZE := Vector2i(1280, 720)
const WINDOWED_POSITION := Vector2i(80, 80)
const LOCAL_PLAYER_VISUAL_LAYER: int = 2
const REMOTE_PLAYER_VISUAL_LAYER: int = 1

@export var max_health: int = 100
var current_health: int = max_health
var _base_move_speed: float = 0.0
var _base_sprint_multiplier: float = 0.0
var _base_max_health: int = 0
var _base_recoil_recovery_speed: float = 0.0
var _fov_kick_reduction: float = 0.0
var _damage_reduction: float = 0.0

func _ready() -> void:
	add_to_group("player")
	_capture_base_stats()
	_ensure_inventory_input_action()
	current_health = max_health
	if camera:
		camera.fov = base_fov
	_configure_control_mode()
	_ensure_local_setup()

	if inventory_system:
		inventory_system.initialize_with_weapon_manager(weapon_manager)
		if not inventory_system.equipment_stats_changed.is_connected(_on_equipment_stats_changed):
			inventory_system.equipment_stats_changed.connect(_on_equipment_stats_changed)
	if weapon_manager:
		weapon_manager.set_inventory_system(inventory_system)
	if inventory_system:
		_on_equipment_stats_changed(inventory_system.get_equipped_stats())

func _init_hud() -> void:
	var hud = _get_hud()
	if hud:
		hud.update_health(current_health)
		if hud.has_method("set_inventory_system"):
			hud.set_inventory_system(inventory_system)

func _get_hud() -> Node:
	if not is_instance_valid(_cached_hud):
		var huds = get_tree().get_nodes_in_group("hud")
		if huds.size() > 0:
			_cached_hud = huds[0]
	return _cached_hud

func set_network_peer_id(peer_id: int) -> void:
	network_peer_id = max(1, peer_id)
	_configure_control_mode()
	_ensure_local_setup()

func get_network_peer_id() -> int:
	return network_peer_id

func set_gameplay_input_enabled(enabled: bool) -> void:
	_gameplay_input_enabled = enabled
	if weapon_manager:
		weapon_manager.set_input_enabled(enabled and _is_local_controlled)

func is_local_controlled() -> bool:
	return _is_local_controlled

func _configure_control_mode() -> void:
	var local_peer_id := _get_network_local_peer_id()
	var host_local_fallback := _is_network_host() and network_peer_id == 1
	_is_local_controlled = not _is_network_multiplayer_active() or (network_peer_id > 0 and (network_peer_id == local_peer_id or host_local_fallback))

	if weapon_manager:
		weapon_manager.set_input_enabled(_is_local_controlled)
		weapon_manager.set_viewmodel_enabled(_is_local_controlled)

	if camera:
		camera.current = _is_local_controlled

	_set_player_visual_layer(LOCAL_PLAYER_VISUAL_LAYER if _is_local_controlled else REMOTE_PLAYER_VISUAL_LAYER)

func _ensure_local_setup() -> void:
	if not _is_local_controlled or _local_setup_complete:
		return
	_local_setup_complete = true
	_ensure_inventory_input_action()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	call_deferred("_init_hud")

func _capture_base_stats() -> void:
	_base_move_speed = move_speed
	_base_sprint_multiplier = sprint_multiplier
	_base_max_health = max_health
	_base_recoil_recovery_speed = recoil_recovery_speed

func _on_equipment_stats_changed(stats: Dictionary) -> void:
	move_speed = _apply_add_mult(_base_move_speed, float(stats.get("move_speed_add", 0.0)), float(stats.get("move_speed_mult", 0.0)))
	sprint_multiplier = _base_sprint_multiplier + float(stats.get("sprint_multiplier", 0.0))
	recoil_recovery_speed = _base_recoil_recovery_speed * (1.0 + float(stats.get("recoil_recovery_mult", 0.0)))
	_fov_kick_reduction = float(stats.get("fov_kick_reduction", 0.0))
	_damage_reduction = clampf(float(stats.get("damage_reduction", 0.0)), 0.0, 0.9)

	var previous_max_health := max_health
	max_health = maxi(1, int(round(_apply_add_mult(float(_base_max_health), float(stats.get("health_add", 0.0)), float(stats.get("health_mult", 0.0))))))
	if max_health != previous_max_health:
		if max_health > previous_max_health:
			current_health += max_health - previous_max_health
		current_health = clampi(current_health, 0, max_health)
		var hud = _get_hud()
		if hud:
			hud.update_health(current_health)

	if weapon_manager and weapon_manager.has_method("apply_equipment_stats"):
		weapon_manager.apply_equipment_stats(stats)

func _apply_add_mult(base_value: float, additive_bonus: float, multiplicative_bonus: float) -> float:
	return (base_value + additive_bonus) * (1.0 + multiplicative_bonus)

func take_damage(amount: int) -> void:
	if current_health <= 0:
		return
	var reduced_amount := maxi(0, int(round(float(amount) * (1.0 - _damage_reduction))))
	current_health -= reduced_amount
	current_health = max(0, current_health)
	if _is_local_controlled:
		var hud = _get_hud()
		if hud:
			hud.update_health(current_health)
	if current_health <= 0:
		print("Player Died!")

func heal(amount: int) -> void:
	if current_health <= 0 or amount <= 0:
		return
	current_health = mini(max_health, current_health + amount)
	if _is_local_controlled:
		var hud = _get_hud()
		if hud:
			hud.update_health(current_health)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key_event := event as InputEventKey
		if _is_fullscreen_toggle_event(key_event):
			_toggle_window_mode()
			return

	if not _is_local_controlled or not _gameplay_input_enabled:
		return
	if event.is_action_pressed("inventory_toggle"):
		if event is InputEventKey and (event as InputEventKey).echo:
			return
		_toggle_inventory()
		return
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED and not _is_inventory_open():
		# Apply mouse input minus current recoil, so recoil adds to pitch/yaw
		rotate_y(-event.relative.x * mouse_sensitivity)
		head.rotate_x(-event.relative.y * mouse_sensitivity)

		# Clamp head pitch
		head.rotation.x = clamp(head.rotation.x, -deg_to_rad(85), deg_to_rad(85))

	if event.is_action_pressed("ui_cancel"):
		if _is_inventory_open() and inventory_system:
			inventory_system.set_inventory_open(false)
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
			return
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _physics_process(delta: float) -> void:
	if not _is_local_controlled and _is_network_host() and network_peer_id == 1:
		_is_local_controlled = true
		_configure_control_mode()
		_ensure_local_setup()

	if not _is_local_controlled:
		_apply_remote_motion(delta)
		return

	_handle_recoil(delta)
	_update_loot_tooltip()

	if not is_on_floor():
		velocity.y -= gravity * delta

	if _gameplay_input_enabled:
		if Input.is_action_just_pressed("interact") and not _is_inventory_open():
			_try_interact()

		if Input.is_action_just_pressed("jump") and is_on_floor() and not _is_inventory_open():
			velocity.y = jump_velocity

	var input_dir := Vector2.ZERO
	if _gameplay_input_enabled and not _is_inventory_open():
		input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	var current_speed = move_speed
	if _gameplay_input_enabled and Input.is_action_pressed("sprint") and not _is_inventory_open():
		current_speed *= sprint_multiplier

	if direction:
		velocity.x = direction.x * current_speed
		velocity.z = direction.z * current_speed
	else:
		velocity.x = move_toward(velocity.x, 0, current_speed)
		velocity.z = move_toward(velocity.z, 0, current_speed)

	_update_fov(delta, _gameplay_input_enabled and input_dir.length() > 0.1 and Input.is_action_pressed("sprint") and not _is_inventory_open())
	_update_visuals(delta, input_dir, current_speed)
	move_and_slide()

func _update_visuals(delta: float, input_dir: Vector2, _speed: float) -> void:
	if not visuals: return
	
	# Idle breathing/pulse
	var time = Time.get_ticks_msec() / 1000.0
	var breathe = sin(time * 1.5) * 0.02
	visuals.scale = Vector3(1.0 + breathe, 1.0 - breathe, 1.0 + breathe)
	
	# Tilt towards movement
	var target_rotation_z = -input_dir.x * 0.05
	var target_rotation_x = input_dir.y * 0.05
	
	visuals.rotation.z = lerp_angle(visuals.rotation.z, target_rotation_z, delta * 5.0)
	visuals.rotation.x = lerp_angle(visuals.rotation.x, target_rotation_x, delta * 5.0)

func _update_fov(delta: float, is_sprinting: bool) -> void:
	# Calculate target base FOV
	var target = sprint_fov if is_sprinting else base_fov
	_target_fov = lerp(_target_fov, target, delta * fov_change_speed)
	
	# Apply FOV kick decay
	_fov_kick = lerp(_fov_kick, 0.0, delta * 15.0)
	
	camera.fov = _target_fov + _fov_kick

func apply_fov_kick(amount: float) -> void:
	_fov_kick = amount * (1.0 - clampf(_fov_kick_reduction, 0.0, 0.9))

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

func build_network_snapshot(include_health: bool = true) -> Dictionary:
	var snapshot := {
		"position": global_position,
		"velocity": velocity,
		"yaw": rotation.y,
		"pitch": head.rotation.x,
	}
	if include_health:
		snapshot["health"] = current_health
	if weapon_manager:
		snapshot["current_weapon_index"] = weapon_manager.current_weapon_index
	return snapshot

func apply_network_snapshot(snapshot: Dictionary) -> void:
	if snapshot.is_empty():
		return
	_network_target_position = snapshot.get("position", global_position)
	_network_target_velocity = snapshot.get("velocity", velocity)
	_network_target_yaw = float(snapshot.get("yaw", rotation.y))
	_network_target_pitch = float(snapshot.get("pitch", head.rotation.x))
	if snapshot.has("health"):
		var synced_health: int = maxi(0, int(snapshot.get("health", current_health)))
		if synced_health != current_health:
			current_health = synced_health
			if _is_local_controlled:
				var hud = _get_hud()
				if hud:
					hud.update_health(current_health)

	if snapshot.has("current_weapon_index") and weapon_manager:
		var target_weapon_index: int = int(snapshot.get("current_weapon_index", -1))
		if target_weapon_index >= 0 and target_weapon_index != weapon_manager.current_weapon_index:
			weapon_manager.switch_to_weapon(target_weapon_index)

	_has_network_snapshot = true

func apply_authoritative_health(value: int) -> void:
	var synced_health: int = maxi(0, value)
	if synced_health == current_health:
		return
	current_health = synced_health
	if _is_local_controlled:
		var hud = _get_hud()
		if hud:
			hud.update_health(current_health)

func _apply_remote_motion(delta: float) -> void:
	if not _has_network_snapshot:
		return

	global_position = global_position.lerp(_network_target_position, min(1.0, delta * 12.0))
	velocity = velocity.lerp(_network_target_velocity, min(1.0, delta * 10.0))
	rotation.y = lerp_angle(rotation.y, _network_target_yaw, min(1.0, delta * 14.0))
	head.rotation.x = lerp_angle(head.rotation.x, _network_target_pitch, min(1.0, delta * 14.0))

func _update_loot_tooltip() -> void:
	if _is_inventory_open() or camera == null:
		var hud := _get_hud()
		if hud and hud.has_method("hide_world_item_tooltip"):
			hud.hide_world_item_tooltip()
		return
	var space_state := get_world_3d().direct_space_state
	var origin := camera.global_position
	var forward := -camera.global_transform.basis.z.normalized()
	var query := PhysicsRayQueryParameters3D.create(origin, origin + forward * 3.5)
	query.exclude = [self.get_rid()]
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var result := space_state.intersect_ray(query)
	var hud := _get_hud()
	if hud == null:
		return
	if result and result.collider.has_method("get_item_snapshot"):
		hud.show_world_item_tooltip(result.collider.get_item_snapshot())
	elif hud.has_method("hide_world_item_tooltip"):
		hud.hide_world_item_tooltip()

func _try_interact() -> void:
	var space_state = get_world_3d().direct_space_state
	var origin = camera.global_position
	var forward = -camera.global_transform.basis.z.normalized()
	var ray_end = origin + forward * 3.0

	var query = PhysicsRayQueryParameters3D.create(origin, ray_end)
	query.exclude = [self.get_rid()]
	query.collide_with_areas = true

	var result = space_state.intersect_ray(query)
	if result:
		var collider = result.collider
		var dungeon_manager = get_tree().get_first_node_in_group("dungeon_manager")
		if _is_network_multiplayer_active() and dungeon_manager != null and dungeon_manager.has_method("request_interaction"):
			dungeon_manager.call("request_interaction", self, collider)
			return
		if collider is DungeonDoor:
			collider.open()
		elif collider.has_method("interact"):
			collider.interact(self)
			if _is_inventory_open():
				Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _is_inventory_open() -> bool:
	return inventory_system != null and inventory_system.is_inventory_open()

func _ensure_inventory_input_action() -> void:
	if not InputMap.has_action("inventory_toggle"):
		InputMap.add_action("inventory_toggle")

	var has_tab := false
	for existing_event in InputMap.action_get_events("inventory_toggle"):
		if existing_event is InputEventKey:
			var key_event := existing_event as InputEventKey
			if key_event.keycode == KEY_TAB or key_event.physical_keycode == KEY_TAB:
				has_tab = true
				break

	if not has_tab:
		var tab_event := InputEventKey.new()
		tab_event.keycode = KEY_TAB
		InputMap.action_add_event("inventory_toggle", tab_event)

func _toggle_inventory() -> void:
	if inventory_system == null:
		return
	var was_open := inventory_system.is_inventory_open()
	var active_chest_path := ""
	if was_open and inventory_system.has_method("get_active_chest_path"):
		active_chest_path = String(inventory_system.call("get_active_chest_path"))

	inventory_system.set_inventory_open(not was_open)
	var hud = _get_hud()
	if hud and hud.has_method("set_inventory_panel_visible"):
		hud.call("set_inventory_panel_visible", inventory_system.is_inventory_open())
	if inventory_system.is_inventory_open():
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		if was_open and not active_chest_path.is_empty() and _is_network_multiplayer_active():
			var dungeon_manager = get_tree().get_first_node_in_group("dungeon_manager")
			if dungeon_manager != null and dungeon_manager.has_method("request_chest_view_closed"):
				dungeon_manager.call("request_chest_view_closed", network_peer_id, active_chest_path)

func _set_player_visual_layer(layer_number: int) -> void:
	if visuals == null:
		return
	var layer_mask: int = 1 << maxi(0, layer_number - 1)
	_apply_layer_to_children(visuals, layer_mask)

func _apply_layer_to_children(root: Node, layer_mask: int) -> void:
	if root is VisualInstance3D:
		var visual_node: VisualInstance3D = root
		visual_node.layers = layer_mask
	for child in root.get_children():
		if child is Node:
			_apply_layer_to_children(child, layer_mask)

func _is_fullscreen_toggle_event(event: InputEventKey) -> bool:
	if event.alt_pressed and (event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER):
		return true
	return FULLSCREEN_TOGGLE_KEYS.has(event.keycode)

func _toggle_window_mode() -> void:
	var mode := DisplayServer.window_get_mode()
	if mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(WINDOWED_SIZE)
		DisplayServer.window_set_position(WINDOWED_POSITION)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_ensure_inventory_input_action()

func _get_network_session():
	if is_inside_tree():
		return get_node_or_null("/root/NetworkSession")
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		var tree: SceneTree = loop
		if tree.root != null:
			return tree.root.get_node_or_null("NetworkSession")
	return null

func _is_network_multiplayer_active() -> bool:
	var session = _get_network_session()
	if session == null:
		return false
	return bool(session.call("is_multiplayer_active"))

func _get_network_local_peer_id() -> int:
	var session = _get_network_session()
	if session == null:
		return 1
	return max(1, int(session.call("get_local_peer_id")))

func _is_network_host() -> bool:
	var session = _get_network_session()
	if session == null:
		return true
	return bool(session.call("is_host"))
