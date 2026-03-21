extends Node3D
class_name Weapon

@export_group("General")
@export var weapon_name: String = "Weapon"
@export var damage: int = 15
@export var fire_rate: float = 0.15
@export var weapon_icon: Texture2D = null

@export_group("Ammo & Reload")
@export var ammo_type: String = "light" # "light", "shells", "energy", "arrows", "none"
@export var mag_size: int = 30
@export var reload_time: float = 1.0
@export var infinite_reserve_ammo: bool = false
var current_mag: int = 0
var is_reloading: bool = false

@export_group("Projectile Settings")
@export var is_projectile: bool = false
@export var projectile_scene: PackedScene = null
@export var pellet_count: int = 1
@export var spread_angle: float = 0.0
@export var ray_range: float = 200.0
@export var ejects_shells: bool = true

@export_group("Recoil")
@export var fov_kick_amount: float = 2.0
@export var recoil_pitch: float = 0.05
@export var recoil_yaw: float = 0.02

@export_group("3D Viewmodel")
@export var viewmodel_position: Vector3 = Vector3(0.25, -0.25, -0.42)
@export var viewmodel_rotation_degrees: Vector3 = Vector3.ZERO
@export var fire_kick_offset: Vector3 = Vector3(0.0, 0.015, 0.06)
@export var reload_lower_offset: Vector3 = Vector3(0.0, -0.18, 0.10)

@export_group("World Presentation")
@export var world_position: Vector3 = Vector3(0.36, -0.22, 0.10)
@export var world_rotation_degrees: Vector3 = Vector3.ZERO

@onready var muzzle_flash: Node3D = $MuzzleFlash
@onready var tracer: MeshInstance3D = $BulletTracer
@onready var ejection_port: Node3D = $EjectionPort
@onready var mesh_root: Node3D = get_node_or_null("WeaponMesh") as Node3D

var can_fire: bool = true
var fire_timer: float = 0.0
var _next_fire_ready_time: float = 0.0
var weapon_manager: WeaponManager = null
var _equipment_stats: Dictionary = {}
var _weapon_item_stats: Dictionary = {}
var _base_damage: int = 0
var _base_reload_time: float = 0.0
var _base_spread_angle: float = 0.0
var _base_fov_kick_amount: float = 0.0
var _base_recoil_pitch: float = 0.0
var _base_recoil_yaw: float = 0.0

var _cached_player: CharacterBody3D = null
var _viewmodel_enabled: bool = true
var _world_transform: Transform3D = Transform3D.IDENTITY

signal fired
signal hit_target(target, dmg)

const BULLET_HOLE_SCENE = preload("res://Scenes/Effects/bullet_hole.tscn")
const BLOOD_SPLATTER_SCENE = preload("res://Scenes/Effects/blood_splatter.tscn")
const BLOOD_PARTICLES_SCENE = preload("res://Scenes/Effects/blood_particles.tscn")
const CASING_SCENE = preload("res://Scenes/Effects/shell_casing.tscn")

func _ready() -> void:
	_world_transform = _build_world_transform()
	_capture_base_stats()
	muzzle_flash.visible = false
	tracer.visible = false
	current_mag = _get_effective_mag_size()
	set_viewmodel_enabled(_viewmodel_enabled)

func show_weapon() -> void:
	visible = true
	set_process(true)
	set_physics_process(true)

	# Reset animations and timers when drawn
	can_fire = true
	fire_timer = 0.0
	_next_fire_ready_time = 0.0
	is_reloading = false
	_apply_presentation_mode()

func hide_weapon() -> void:
	visible = false
	set_process(false)
	set_physics_process(false)
	is_reloading = false
	transform = _world_transform

func set_viewmodel_enabled(enabled: bool) -> void:
	_viewmodel_enabled = enabled
	_apply_presentation_mode()
	if muzzle_flash != null:
		var flash_sprite := muzzle_flash.get_node_or_null("FlashSprite")
		if flash_sprite:
			flash_sprite.visible = true

func _apply_presentation_mode() -> void:
	_world_transform = _build_world_transform()
	transform = _build_viewmodel_transform() if _viewmodel_enabled else _world_transform
	if mesh_root:
		mesh_root.visible = visible

func _build_viewmodel_transform() -> Transform3D:
	return Transform3D(_basis_from_degrees(viewmodel_rotation_degrees), viewmodel_position)

func _build_world_transform() -> Transform3D:
	return Transform3D(_basis_from_degrees(world_rotation_degrees), world_position)

func _basis_from_degrees(rotation_degrees_vector: Vector3) -> Basis:
	var rotation_radians := Vector3(
		deg_to_rad(rotation_degrees_vector.x),
		deg_to_rad(rotation_degrees_vector.y),
		deg_to_rad(rotation_degrees_vector.z)
	)
	return Basis.from_euler(rotation_radians)

func set_equipment_stats(stats: Dictionary) -> void:
	_equipment_stats = stats.duplicate(true)
	current_mag = mini(current_mag, _get_effective_mag_size())

func set_weapon_item_stats(stats: Dictionary) -> void:
	_weapon_item_stats = stats.duplicate(true)
	current_mag = mini(current_mag, _get_effective_mag_size())

func has_infinite_reserve_ammo() -> bool:
	return infinite_reserve_ammo

func _capture_base_stats() -> void:
	_base_damage = damage
	_base_reload_time = reload_time
	_base_spread_angle = spread_angle
	_base_fov_kick_amount = fov_kick_amount
	_base_recoil_pitch = recoil_pitch
	_base_recoil_yaw = recoil_yaw

func can_reload() -> bool:
	if ammo_type == "none" or is_reloading or current_mag >= _get_effective_mag_size():
		return false
	if not infinite_reserve_ammo and weapon_manager and weapon_manager.get_ammo(ammo_type) <= 0:
		return false
	return true

func reload(request_authority: bool = true) -> void:
	if not can_reload(): return

	if request_authority and _is_network_multiplayer_active() and not _is_network_host():
		var current_player := _get_player()
		var player_peer_id := 1
		if current_player != null and current_player.has_method("get_network_peer_id"):
			player_peer_id = int(current_player.call("get_network_peer_id"))
		var combat_manager = _get_combat_network_manager()
		if combat_manager != null and combat_manager.has_method("request_weapon_reload") and weapon_manager != null:
			combat_manager.call(
				"request_weapon_reload",
				player_peer_id,
				weapon_manager.get_current_weapon_slot(),
				weapon_manager.get_current_weapon_key()
			)

	is_reloading = true

	var tween = create_tween()
	if _viewmodel_enabled:
		var base_transform := _build_viewmodel_transform()
		var lowered_transform := base_transform
		lowered_transform.origin += reload_lower_offset
		tween.tween_property(self, "transform", lowered_transform, 0.2)
		tween.tween_interval(max(0.0, _get_effective_reload_time() - 0.4))
		tween.tween_callback(_complete_reload_ammo)
		tween.tween_property(self, "transform", base_transform, 0.2)
	else:
		tween.tween_interval(_get_effective_reload_time())
		tween.tween_callback(_complete_reload_ammo)

	tween.finished.connect(func():
		is_reloading = false
		can_fire = true
		_apply_presentation_mode()
	)

func _complete_reload_ammo() -> void:
	var ammo_needed = _get_effective_mag_size() - current_mag
	var reserve = INF if infinite_reserve_ammo else weapon_manager.get_ammo(ammo_type)
	var ammo_to_take = ammo_needed if infinite_reserve_ammo else min(ammo_needed, int(reserve))

	if not infinite_reserve_ammo:
		weapon_manager.consume_ammo(ammo_type, ammo_to_take)
	current_mag += ammo_to_take

	if weapon_manager:
		weapon_manager._update_hud()

func perform_authoritative_reload() -> bool:
	if not can_reload():
		return false
	is_reloading = false
	var ammo_needed = _get_effective_mag_size() - current_mag
	var reserve = INF if infinite_reserve_ammo else weapon_manager.get_ammo(ammo_type)
	var ammo_to_take = ammo_needed if infinite_reserve_ammo else min(ammo_needed, int(reserve))
	if not infinite_reserve_ammo:
		weapon_manager.consume_ammo(ammo_type, ammo_to_take)
	current_mag += ammo_to_take
	can_fire = true
	return true

func _physics_process(_delta: float) -> void:
	_update_fire_cooldown_gate()

	if weapon_manager and weapon_manager.has_method("is_input_blocked") and weapon_manager.is_input_blocked():
		return
	if is_reloading: return

	if weapon_manager and weapon_manager.has_method("is_input_enabled") and not weapon_manager.is_input_enabled():
		return

	if Input.is_action_pressed("shoot") and can_fire:
		if current_mag <= 0 and ammo_type != "none":
			if can_reload():
				reload()
		else:
			if _should_request_host_fire():
				_request_host_fire()
			else:
				fire()

func fire() -> void:
	_update_fire_cooldown_gate()
	var cam: Camera3D = get_viewport().get_camera_3d()
	if not cam:
		return
	_fire_with_aim(cam.global_position, -cam.global_transform.basis.z.normalized(), true, true, _get_player())

func fire_authoritative_from_network(cam_origin: Vector3, cam_forward: Vector3, shooter_node: Node3D) -> bool:
	_update_fire_cooldown_gate()
	if not can_fire:
		return false
	if ammo_type != "none" and current_mag <= 0:
		return false
	_fire_with_aim(cam_origin, cam_forward.normalized(), false, true, shooter_node)
	return true

func _request_host_fire() -> void:
	var cam: Camera3D = get_viewport().get_camera_3d()
	if not cam:
		return

	var current_player := _get_player()
	var player_peer_id := 1
	if current_player != null and current_player.has_method("get_network_peer_id"):
		player_peer_id = int(current_player.call("get_network_peer_id"))

	var manager = _get_combat_network_manager()
	if manager == null or not manager.has_method("request_weapon_fire"):
		fire()
		return

	_fire_with_aim(cam.global_position, -cam.global_transform.basis.z.normalized(), true, false, current_player)
	manager.call(
		"request_weapon_fire",
		player_peer_id,
		weapon_manager.get_current_weapon_slot(),
		weapon_manager.get_current_weapon_key(),
		cam.global_position,
		-cam.global_transform.basis.z.normalized(),
		int(Time.get_ticks_msec())
	)

func _fire_with_aim(cam_origin: Vector3, cam_forward: Vector3, play_local_feedback: bool, apply_damage: bool, shooter_override: Node3D) -> void:
	can_fire = false
	fire_timer = 0.0
	_next_fire_ready_time = (float(Time.get_ticks_msec()) * 0.001) + max(0.0, fire_rate)

	if ammo_type != "none":
		current_mag -= 1

	fired.emit()

	var current_player: Node3D = shooter_override if shooter_override != null else _get_player()
	var player_rid = RID()
	if current_player:
		player_rid = current_player.get_rid()
	var shooter_peer_id := _get_network_peer_id_for_node(current_player)

	if play_local_feedback:
		_play_local_feedback(current_player)

	_broadcast_remote_fire_visual(current_player)

	if not apply_damage:
		_show_muzzle_flash()
		return

	if is_projectile and projectile_scene:
		_fire_projectile(cam_origin, cam_forward, current_player, shooter_peer_id)
		_show_muzzle_flash()
		return

	var shot_damage := _get_effective_damage()
	var effective_spread_angle := _get_effective_spread_angle()
	var cam_basis := _basis_from_forward(cam_forward)

	for _i in range(pellet_count):
		var final_dir = cam_forward
		if effective_spread_angle > 0.0:
			var spread_rad = deg_to_rad(effective_spread_angle)
			var right = cam_basis.x
			var up = cam_basis.y
			var dx = randf_range(-1.0, 1.0)
			var dy = randf_range(-1.0, 1.0)
			if dx * dx + dy * dy > 1.0:
				var angle = atan2(dy, dx)
				var rad = randf()
				dx = cos(angle) * rad
				dy = sin(angle) * rad
			final_dir = (cam_forward + right * dx * spread_rad + up * dy * spread_rad).normalized()
		_fire_hitscan(cam_origin, final_dir, player_rid, shot_damage, shooter_peer_id)
	_show_muzzle_flash()

func play_remote_fire_visual() -> void:
	_show_muzzle_flash()

func _update_fire_cooldown_gate() -> void:
	if can_fire:
		return
	var now := float(Time.get_ticks_msec()) * 0.001
	if now >= _next_fire_ready_time:
		can_fire = true
		fire_timer = 0.0

func _basis_from_forward(forward: Vector3) -> Basis:
	var forward_norm: Vector3 = forward.normalized()
	if forward_norm.length_squared() < 0.0001:
		return Basis.IDENTITY

	var up_ref: Vector3 = Vector3.UP
	if abs(forward_norm.dot(up_ref)) > 0.99:
		up_ref = Vector3.RIGHT

	var right: Vector3 = forward_norm.cross(up_ref).normalized()
	var up: Vector3 = right.cross(forward_norm).normalized()
	return Basis(right, up, -forward_norm)

func _play_local_feedback(shooter_node: Node3D) -> void:
	if _viewmodel_enabled:
		var tween = create_tween()
		var base_transform := _build_viewmodel_transform()
		var kicked_transform := base_transform
		kicked_transform.origin += fire_kick_offset
		tween.tween_property(self, "transform", kicked_transform, 0.04)
		tween.tween_property(self, "transform", base_transform, 0.09)

	if ejects_shells:
		_eject_shell()

	var shooter = shooter_node
	if shooter == null:
		shooter = _get_player()
	if shooter:
		if shooter.has_method("apply_fov_kick"):
			shooter.apply_fov_kick(_base_fov_kick_amount)
		if shooter.has_method("add_camera_recoil"):
			var r_yaw = _base_recoil_yaw * randf_range(-1.0, 1.0)
			shooter.add_camera_recoil(_base_recoil_pitch, r_yaw)

func _fire_projectile(cam_origin: Vector3, cam_forward: Vector3, shooter_node: Node, shooter_peer_id: int) -> void:
	var proj = projectile_scene.instantiate() as Node3D
	var spawn_parent = get_tree().current_scene
	if not spawn_parent:
		return

	if proj is Projectile:
		proj.direction = cam_forward
		proj.damage = _get_effective_damage()
		if shooter_node is Node3D:
			proj.shooter = shooter_node

	# Must add child AFTER setting properties so _ready has correct direction
	spawn_parent.add_child(proj)

	# Start projectile ahead of camera to avoid spawning inside the player collider.
	proj.global_position = cam_origin + cam_forward * 2.0

	if proj is Projectile:
		# Look in direction of travel
		if cam_forward.abs().is_equal_approx(Vector3(0, 1, 0)):
			proj.look_at(proj.global_position + cam_forward, Vector3.RIGHT)
		else:
			proj.look_at(proj.global_position + cam_forward, Vector3.UP)

	# Host replicates projectile visuals to clients so they can see travel/explosions.
	if _is_network_multiplayer_active() and _is_network_host():
		var combat_manager = _get_combat_network_manager()
		if combat_manager != null and combat_manager.has_method("broadcast_projectile_visual"):
			combat_manager.call(
				"broadcast_projectile_visual",
				projectile_scene.resource_path,
				shooter_peer_id,
				muzzle_flash.global_position,
				cam_forward
			)

func _fire_hitscan(cam_origin: Vector3, cam_forward: Vector3, player_rid: RID, shot_damage: int, shooter_peer_id: int) -> void:
	var space_state = get_world_3d().direct_space_state
	var ray_end = cam_origin + cam_forward * ray_range

	var query = PhysicsRayQueryParameters3D.create(cam_origin, ray_end)
	query.collide_with_areas = true
	query.collision_mask = 0xFFFFFFFF

	if player_rid.is_valid():
		query.exclude = [player_rid]

	var result = space_state.intersect_ray(query)

	var hit_pos: Vector3
	if result:
		hit_pos = result.position
		var hit_collider = result.collider
		var hitbox = _find_hitbox(hit_collider)
		
		if hitbox:
			hitbox.take_damage(shot_damage)
			hit_target.emit(hitbox, shot_damage)
			_splash_blood(hit_pos, cam_forward, hit_collider)
		else:
			_place_bullet_hole(hit_pos, result.normal, hit_collider)
	else:
		hit_pos = ray_end

	_show_tracer(muzzle_flash.global_position, hit_pos)
	if _is_network_multiplayer_active() and _is_network_host():
		var combat_manager = _get_combat_network_manager()
		if combat_manager != null and combat_manager.has_method("broadcast_hitscan_visual"):
			combat_manager.call("broadcast_hitscan_visual", shooter_peer_id, muzzle_flash.global_position, hit_pos)

func _get_effective_damage() -> int:
	var exact_key := _get_exact_weapon_key()
	var family_key := _get_damage_family_key(exact_key)
	var additive_bonus := _get_stat_total("weapon_damage_add")
	var multiplicative_bonus := _get_stat_total("weapon_damage_mult")

	if not family_key.is_empty():
		additive_bonus += _get_stat_total("%s_damage_add" % family_key)
		multiplicative_bonus += _get_stat_total("%s_damage_mult" % family_key)
	if not exact_key.is_empty():
		additive_bonus += _get_stat_total("%s_damage_add" % exact_key)
		multiplicative_bonus += _get_stat_total("%s_damage_mult" % exact_key)

	return maxi(1, int(round((float(_base_damage) + additive_bonus) * (1.0 + multiplicative_bonus))))

func _get_effective_reload_time() -> float:
	var speed_bonus := maxf(0.0, _get_stat_total("reload_speed_mult"))
	return maxf(0.1, _base_reload_time / (1.0 + speed_bonus))

func _get_effective_spread_angle() -> float:
	var spread_reduction := clampf(_get_stat_total("spread_reduction"), 0.0, 0.95)
	return maxf(0.0, _base_spread_angle * (1.0 - spread_reduction))

func get_effective_mag_size() -> int:
	return _get_effective_mag_size()

func _get_effective_mag_size() -> int:
	var exact_key := _get_exact_weapon_key()
	var family_key := _get_damage_family_key(exact_key)
	var additive_bonus := _get_stat_total("mag_size_add")
	var multiplicative_bonus := _get_stat_total("mag_size_mult")

	if not family_key.is_empty():
		additive_bonus += _get_stat_total("%s_mag_size_add" % family_key)
		multiplicative_bonus += _get_stat_total("%s_mag_size_mult" % family_key)
	if not exact_key.is_empty():
		additive_bonus += _get_stat_total("%s_mag_size_add" % exact_key)
		multiplicative_bonus += _get_stat_total("%s_mag_size_mult" % exact_key)

	return maxi(1, int(round((float(mag_size) + additive_bonus) * (1.0 + multiplicative_bonus))))

func _get_stat_total(stat_key: String) -> float:
	return float(_equipment_stats.get(stat_key, 0.0)) + float(_weapon_item_stats.get(stat_key, 0.0))

func _get_exact_weapon_key() -> String:
	if weapon_manager != null:
		return weapon_manager.get_weapon_key_for_weapon(self)
	return weapon_name.strip_edges().to_lower().replace(" ", "_")

func _get_damage_family_key(exact_key: String) -> String:
	if ammo_type != "none":
		return ammo_type
	if exact_key == "rifle":
		return "light"
	return ""

func _eject_shell() -> void:
	var casing = CASING_SCENE.instantiate()
	get_tree().current_scene.add_child(casing)
	casing.global_position = ejection_port.global_position
	
	var cam = get_viewport().get_camera_3d()
	if cam:
		var right = cam.global_transform.basis.x
		var up = cam.global_transform.basis.y
		var back = cam.global_transform.basis.z
		var force = (right * 1.5) + (up * 0.8) + (back * 0.2)
		force += Vector3(randf(), randf(), randf()) * 0.4
		casing.apply_impulse(force)
		casing.apply_torque_impulse(Vector3(randf(), randf(), randf()) * 0.2)

func _splash_blood(pos: Vector3, dir: Vector3, exclude_node: Node) -> void:
	var particles = BLOOD_PARTICLES_SCENE.instantiate()
	get_tree().current_scene.add_child(particles)
	particles.global_position = pos
	var look_dir = dir + Vector3.UP * 0.4 + (Vector3(randf(), randf(), randf()) - Vector3(0.5, 0.5, 0.5)) * 0.3
	particles.look_at(pos + look_dir, Vector3.UP)
	
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(pos - dir * 0.2, pos + dir * 10.0)
	if exclude_node: query.exclude = [exclude_node.get_rid()]
	query.collision_mask = 1 
	
	var result = space_state.intersect_ray(query)
	if result and not _is_forbidden_surface(result.collider):
		_place_decal(BLOOD_SPLATTER_SCENE, result.position, result.normal)

func _is_forbidden_surface(node: Node) -> bool:
	if node is HitboxComponent or node is CharacterBody3D: return true
	var name_lower = node.name.to_lower()
	return name_lower.contains("hurtbox") or name_lower.contains("hitbox") or name_lower.contains("enemy")

func _place_bullet_hole(pos: Vector3, normal: Vector3, _parent: Node) -> void:
	_place_decal(BULLET_HOLE_SCENE, pos, normal)

func _place_decal(scene: PackedScene, pos: Vector3, normal: Vector3) -> void:
	var decal = scene.instantiate()
	get_tree().current_scene.add_child(decal)
	decal.global_position = pos
	var x_axis = normal.cross(Vector3.UP).normalized() if abs(normal.dot(Vector3.UP)) < 0.99 else normal.cross(Vector3.RIGHT).normalized()
	var z_axis = x_axis.cross(normal).normalized()
	decal.global_transform.basis = Basis(x_axis, normal, z_axis)
	decal.rotate_object_local(Vector3.UP, randf() * TAU)

func _should_request_host_fire() -> bool:
	if not _is_network_multiplayer_active() or _is_network_host():
		return false
	var shooter := _get_player()
	if shooter == null:
		return false
	if shooter.has_method("is_local_controlled"):
		return bool(shooter.call("is_local_controlled"))
	return true

func _get_player() -> CharacterBody3D:
	if weapon_manager and is_instance_valid(weapon_manager.player):
		return weapon_manager.player

	if not is_instance_valid(_cached_player):
		_cached_player = get_tree().get_first_node_in_group("player") as CharacterBody3D

	return _cached_player

func _find_hitbox(node: Node) -> HitboxComponent:
	var current = node
	while current != null and current != get_tree().root:
		if current.has_method("is_network_proxy_mode") and bool(current.call("is_network_proxy_mode")):
			return null
		if current is HitboxComponent: return current
		for child in current.get_children():
			if child is HitboxComponent:
				if current.has_method("is_network_proxy_mode") and bool(current.call("is_network_proxy_mode")):
					return null
				return child
		current = current.get_parent()
	return null

func _show_muzzle_flash() -> void:
	muzzle_flash.visible = true
	
	await get_tree().create_timer(0.05).timeout
	
	muzzle_flash.visible = false

func _show_tracer(from: Vector3, to: Vector3) -> void:
	if tracer == null: return
	
	var length = from.distance_to(to)
	var t_mesh := CylinderMesh.new()
	t_mesh.top_radius = 0.01   # Target side (thin)
	t_mesh.bottom_radius = 0.04 # Gun side (thick)
	t_mesh.height = length
	t_mesh.radial_segments = 4 # Diamond shape looks cool and retro
	
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = StandardMaterial3D.BLEND_MODE_ADD
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(2.5, 2.5, 1.0, 0.8) # High intensity yellow/white
	
	var temp_tracer = MeshInstance3D.new()
	temp_tracer.mesh = t_mesh
	temp_tracer.material_override = mat
	temp_tracer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	
	get_tree().current_scene.add_child(temp_tracer)
	
	temp_tracer.global_position = (from + to) / 2.0
	
	if length > 0.01:
		temp_tracer.look_at(to, Vector3.UP)
		# Cylinder is along Y. Rotate around X so Y lies along -Z
		temp_tracer.rotate_object_local(Vector3.RIGHT, -PI / 2.0)
	
	await get_tree().create_timer(0.05).timeout
	if is_instance_valid(temp_tracer):
		temp_tracer.queue_free()

func _get_network_session():
	return get_node_or_null("/root/NetworkSession")

func _is_network_multiplayer_active() -> bool:
	var session = _get_network_session()
	if session == null:
		return false
	return bool(session.call("is_multiplayer_active"))

func _is_network_host() -> bool:
	var session = _get_network_session()
	if session == null:
		return true
	return bool(session.call("is_host"))

func _broadcast_remote_fire_visual(shooter_node: Node3D) -> void:
	if not _is_network_multiplayer_active() or not _is_network_host():
		return
	var shooter_peer_id := _get_network_peer_id_for_node(shooter_node)
	if shooter_peer_id <= 0:
		return
	var combat_manager = _get_combat_network_manager()
	if combat_manager != null and combat_manager.has_method("broadcast_weapon_fire_visual"):
		combat_manager.call(
			"broadcast_weapon_fire_visual",
			shooter_peer_id,
			muzzle_flash.global_position
		)

func _get_network_peer_id_for_node(node: Node) -> int:
	if node == null or not node.has_method("get_network_peer_id"):
		return 0
	return int(node.call("get_network_peer_id"))

func _get_combat_network_manager() -> Node:
	return get_node_or_null("/root/CombatNetworkManager")
