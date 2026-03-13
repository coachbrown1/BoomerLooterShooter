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

@export_group("2D Viewmodel")
@export var muzzle_2d_offset: Vector2 = Vector2(-20, -110)
@export var muzzle_2d_scale: float = 1.5

@onready var sprite: Sprite3D = $WeaponSprite
@onready var muzzle_flash: Node3D = $MuzzleFlash
@onready var tracer: MeshInstance3D = $BulletTracer
@onready var ejection_port: Node3D = $EjectionPort

var can_fire: bool = true
var fire_timer: float = 0.0
var sprite_origin_z: float = 0.0
var weapon_manager: WeaponManager = null

var _cached_player: CharacterBody3D = null

# 2D Viewmodel elements
var _canvas_layer: CanvasLayer
var _viewmodel_2d: Sprite2D
var _emissive_2d: Sprite2D
var _muzzle_2d: Sprite2D
var _viewmodel_enabled: bool = true

signal fired
signal hit_target(target, dmg)

const BULLET_HOLE_SCENE = preload("res://Scenes/Effects/bullet_hole.tscn")
const BLOOD_SPLATTER_SCENE = preload("res://Scenes/Effects/blood_splatter.tscn")
const BLOOD_PARTICLES_SCENE = preload("res://Scenes/Effects/blood_particles.tscn")
const CASING_SCENE = preload("res://Scenes/Effects/shell_casing.tscn")

func _ready() -> void:
	muzzle_flash.visible = false
	tracer.visible = false
	current_mag = mag_size
	
	# Hide the 3D sprite as we'll use a 2D overlay
	if sprite:
		sprite.visible = false
		_setup_2d_viewmodel()

func _setup_2d_viewmodel() -> void:
	# Create a CanvasLayer to keep the weapon fixed on screen
	_canvas_layer = CanvasLayer.new()
	_canvas_layer.layer = 5 # Below ScreenFX/HUD (10), above world (0)
	add_child(_canvas_layer)
	
	_viewmodel_2d = Sprite2D.new()
	_viewmodel_2d.texture = sprite.texture
	_viewmodel_2d.hframes = sprite.hframes
	_viewmodel_2d.vframes = sprite.vframes
	_viewmodel_2d.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	
	# Handle Emissive/Glow for 2D
	if sprite.texture:
		var em_path = sprite.texture.resource_path.replace(".png", "_e.png")
		if ResourceLoader.exists(em_path):
			_emissive_2d = Sprite2D.new()
			_emissive_2d.texture = load(em_path)
			_emissive_2d.hframes = sprite.hframes
			_emissive_2d.vframes = sprite.vframes
			_emissive_2d.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			# Use additive blending for the glow, like the 3D shader
			var mat = CanvasItemMaterial.new()
			mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
			mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
			_emissive_2d.material = mat
			_emissive_2d.modulate = Color(1.5, 1.5, 1.5, 1.0) 
			_viewmodel_2d.add_child(_emissive_2d)
	
	_canvas_layer.add_child(_viewmodel_2d)
	
	# Setup 2D Muzzle Flash
	var flash_3d = muzzle_flash.get_node_or_null("FlashSprite")
	if flash_3d:
		_muzzle_2d = Sprite2D.new()
		_muzzle_2d.texture = flash_3d.texture
		_muzzle_2d.hframes = flash_3d.hframes
		_muzzle_2d.vframes = flash_3d.vframes
		_muzzle_2d.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_muzzle_2d.visible = false
		
		var mat = CanvasItemMaterial.new()
		mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
		_muzzle_2d.material = mat
		
		_canvas_layer.add_child(_muzzle_2d)
		flash_3d.visible = false
	
	_update_viewmodel_position()
	get_viewport().size_changed.connect(_update_viewmodel_position)

func _update_viewmodel_position() -> void:
	if not _viewmodel_2d: return
	
	var screen_size = get_viewport().get_visible_rect().size
	
	# Scale based on screen height, but more conservatively
	# If textures are 512x256, and screen is 1080p:
	# scale_factor = 1080 / 540 = 2.0. Resulting weapon height = 256 * 2 = 512 (about half the screen)
	# Scale: 640p base height seems good for 1080p, but let's make it slightly larger
	var scale_factor = screen_size.y / 540.0 
	_viewmodel_2d.scale = Vector2(scale_factor, scale_factor)
	
	# Position: Slightly more to the right and exactly at the bottom
	_viewmodel_2d.position = Vector2(screen_size.x * 0.75, screen_size.y)
	
	_viewmodel_2d.centered = true
	# Offset so the bottom of the texture is at the bottom of the screen
	_viewmodel_2d.offset.y = -_viewmodel_2d.texture.get_height() / 2.0
	
	if _emissive_2d:
		_emissive_2d.position = Vector2.ZERO
		_emissive_2d.centered = true
		_emissive_2d.offset = _viewmodel_2d.offset

	if _muzzle_2d:
		_muzzle_2d.position = _viewmodel_2d.position + (muzzle_2d_offset * scale_factor)
		_muzzle_2d.scale = Vector2(scale_factor * muzzle_2d_scale, scale_factor * muzzle_2d_scale)

func show_weapon() -> void:
	visible = true
	set_process(true)
	set_physics_process(true)
	if _canvas_layer:
		_canvas_layer.visible = _viewmodel_enabled

	# Reset animations and timers when drawn
	can_fire = true
	fire_timer = 0.0
	is_reloading = false
	if _viewmodel_2d:
		_viewmodel_2d.position.y = get_viewport().get_visible_rect().size.y

func hide_weapon() -> void:
	visible = false
	set_process(false)
	set_physics_process(false)
	if _canvas_layer:
		_canvas_layer.visible = false
	is_reloading = false

func set_viewmodel_enabled(enabled: bool) -> void:
	_viewmodel_enabled = enabled
	if _canvas_layer:
		_canvas_layer.visible = visible and _viewmodel_enabled

func can_reload() -> bool:
	if ammo_type == "none" or is_reloading or current_mag == mag_size:
		return false
	if weapon_manager and weapon_manager.get_ammo(ammo_type) <= 0:
		return false
	return true

func reload() -> void:
	if not can_reload(): return

	is_reloading = true

	if _viewmodel_2d:
		var tween = create_tween()
		var orig_y = _viewmodel_2d.position.y
		var hidden_y = orig_y + _viewmodel_2d.texture.get_height() * _viewmodel_2d.scale.y

		# Move gun down
		tween.tween_property(_viewmodel_2d, "position:y", hidden_y, 0.2)

		# Wait
		tween.tween_interval(max(0.1, reload_time - 0.4))

		# Perform ammo math
		tween.tween_callback(func():
			var ammo_needed = mag_size - current_mag
			var reserve = weapon_manager.get_ammo(ammo_type)
			var ammo_to_take = min(ammo_needed, reserve)

			weapon_manager.consume_ammo(ammo_type, ammo_to_take)
			current_mag += ammo_to_take

			# Force HUD update
			if weapon_manager: weapon_manager._update_hud()
		)

		# Move gun up
		tween.tween_property(_viewmodel_2d, "position:y", orig_y, 0.2)

		tween.finished.connect(func():
			is_reloading = false
			can_fire = true
		)

func perform_authoritative_reload() -> bool:
	if not can_reload():
		return false
	is_reloading = false
	var ammo_needed = mag_size - current_mag
	var reserve = weapon_manager.get_ammo(ammo_type)
	var ammo_to_take = min(ammo_needed, reserve)
	weapon_manager.consume_ammo(ammo_type, ammo_to_take)
	current_mag += ammo_to_take
	can_fire = true
	return true

func _physics_process(delta: float) -> void:
	if weapon_manager and weapon_manager.has_method("is_input_blocked") and weapon_manager.is_input_blocked():
		return
	if is_reloading: return

	if not can_fire:
		fire_timer += delta
		if fire_timer >= fire_rate:
			can_fire = true
			fire_timer = 0.0

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
	var cam: Camera3D = get_viewport().get_camera_3d()
	if not cam:
		return
	_fire_with_aim(cam.global_position, -cam.global_transform.basis.z.normalized(), true, true, _get_player())

func fire_authoritative_from_network(cam_origin: Vector3, cam_forward: Vector3, shooter_node: Node3D) -> bool:
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

	var manager = get_tree().get_first_node_in_group("dungeon_manager")
	if manager == null or not manager.has_method("request_weapon_fire"):
		fire()
		return

	_fire_with_aim(cam.global_position, -cam.global_transform.basis.z.normalized(), true, false, current_player)
	manager.call(
		"request_weapon_fire",
		player_peer_id,
		weapon_manager.get_current_weapon_slot(),
		cam.global_position,
		-cam.global_transform.basis.z.normalized(),
		int(Time.get_ticks_msec())
	)

func _fire_with_aim(cam_origin: Vector3, cam_forward: Vector3, play_local_feedback: bool, apply_damage: bool, shooter_override: Node3D) -> void:
	can_fire = false

	if ammo_type != "none":
		current_mag -= 1

	fired.emit()

	var current_player: Node3D = shooter_override if shooter_override != null else _get_player()
	var player_rid = RID()
	if current_player:
		player_rid = current_player.get_rid()

	if play_local_feedback:
		_play_local_feedback(current_player)

	if not apply_damage:
		_show_muzzle_flash()
		return

	if is_projectile and projectile_scene:
		_fire_projectile(cam_origin, cam_forward, current_player)
		_show_muzzle_flash()
		return

	var cam_basis := _basis_from_forward(cam_forward)

	for _i in range(pellet_count):
		var final_dir = cam_forward
		if spread_angle > 0.0:
			var spread_rad = deg_to_rad(spread_angle)
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
		_fire_hitscan(cam_origin, final_dir, player_rid)
	_show_muzzle_flash()

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
	if _viewmodel_2d:
		_viewmodel_2d.frame = 1
		if _emissive_2d:
			_emissive_2d.frame = 1

		var tween = create_tween()
		var target_y = _viewmodel_2d.position.y + 20
		var orig_y = _viewmodel_2d.position.y
		tween.tween_property(_viewmodel_2d, "position:y", target_y, 0.05)
		tween.tween_property(_viewmodel_2d, "position:y", orig_y, 0.1)
		tween.finished.connect(func():
			if _viewmodel_2d:
				_viewmodel_2d.frame = 0
				if _emissive_2d:
					_emissive_2d.frame = 0
		)

	if ejects_shells:
		_eject_shell()

	var shooter = shooter_node
	if shooter == null:
		shooter = _get_player()
	if shooter:
		if shooter.has_method("apply_fov_kick"):
			shooter.apply_fov_kick(fov_kick_amount)
		if shooter.has_method("add_camera_recoil"):
			var r_yaw = recoil_yaw * randf_range(-1.0, 1.0)
			shooter.add_camera_recoil(recoil_pitch, r_yaw)

func _fire_projectile(cam_origin: Vector3, cam_forward: Vector3, shooter_node: Node) -> void:
	var proj = projectile_scene.instantiate() as Node3D
	var spawn_parent = get_tree().current_scene
	if not spawn_parent:
		return

	if proj is Projectile:
		proj.direction = cam_forward
		proj.damage = damage
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
		var dungeon_manager = get_tree().get_first_node_in_group("dungeon_manager")
		if dungeon_manager != null and dungeon_manager.has_method("broadcast_projectile_visual"):
			dungeon_manager.call("broadcast_projectile_visual", projectile_scene.resource_path, cam_origin, cam_forward)

func _fire_hitscan(cam_origin: Vector3, cam_forward: Vector3, player_rid: RID) -> void:
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
			hitbox.take_damage(damage)
			hit_target.emit(hitbox, damage)
			_splash_blood(hit_pos, cam_forward, hit_collider)
		else:
			_place_bullet_hole(hit_pos, result.normal, hit_collider)
	else:
		hit_pos = ray_end

	_show_tracer(muzzle_flash.global_position, hit_pos)

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
	if _muzzle_2d:
		_muzzle_2d.visible = true
		var frame_count = max(1, _muzzle_2d.hframes * _muzzle_2d.vframes)
		_muzzle_2d.frame = randi() % frame_count
		_muzzle_2d.rotation = randf() * TAU
	
	await get_tree().create_timer(0.05).timeout
	
	muzzle_flash.visible = false
	if _muzzle_2d:
		_muzzle_2d.visible = false

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
