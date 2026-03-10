extends Node3D
class_name Weapon

@export_group("General")
@export var weapon_name: String = "Weapon"
@export var damage: int = 15
@export var fire_rate: float = 0.15

@export_group("Ammo & Reload")
@export var ammo_type: String = "light" # "light", "shells", "energy", "arrows", "none"
@export var mag_size: int = 30
@export var reload_time: float = 1.0
var current_mag: int = 0
var is_reloading: bool = false

@export_group("Projectile Settings")
@export var is_projectile: bool = false
@export var projectile_scene: PackedScene = null
@export var ray_range: float = 200.0

@export_group("Recoil")
@export var fov_kick_amount: float = 2.0
@export var recoil_pitch: float = 0.05
@export var recoil_yaw: float = 0.02

@onready var sprite: Sprite3D = $WeaponSprite
@onready var muzzle_flash: Node3D = $MuzzleFlash
@onready var tracer: MeshInstance3D = $BulletTracer
@onready var ejection_port: Node3D = $EjectionPort

var can_fire: bool = true
var fire_timer: float = 0.0
var sprite_origin_z: float = 0.0
var weapon_manager: Node = null

# 2D Viewmodel elements
var _canvas_layer: CanvasLayer
var _viewmodel_2d: Sprite2D
var _emissive_2d: Sprite2D
var _muzzle_2d: Sprite2D

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
		# Position muzzle flash at the barrel end in 2D
		# For the 512-wide sheet (256 per frame), the barrel is roughly at the top-center
		_muzzle_2d.position = _viewmodel_2d.position + (Vector2(-20, -110) * scale_factor)
		_muzzle_2d.scale = Vector2(scale_factor * 1.5, scale_factor * 1.5)

func show_weapon() -> void:
	visible = true
	set_process(true)
	set_physics_process(true)
	if _canvas_layer:
		_canvas_layer.visible = true

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

func _physics_process(delta: float) -> void:
	if is_reloading: return

	if not can_fire:
		fire_timer += delta
		if fire_timer >= fire_rate:
			can_fire = true
			fire_timer = 0.0

	if Input.is_action_pressed("shoot") and can_fire:
		if current_mag <= 0 and ammo_type != "none":
			if can_reload():
				reload()
		else:
			fire()

func fire() -> void:
	can_fire = false

	if ammo_type != "none":
		current_mag -= 1

	fired.emit()

	# Recoil animation in 2D
	if _viewmodel_2d:
		_viewmodel_2d.frame = 1
		if _emissive_2d: _emissive_2d.frame = 1
		
		var tween = create_tween()
		var target_y = _viewmodel_2d.position.y + 20
		var orig_y = _viewmodel_2d.position.y
		tween.tween_property(_viewmodel_2d, "position:y", target_y, 0.05)
		tween.tween_property(_viewmodel_2d, "position:y", orig_y, 0.1)
		tween.finished.connect(func(): 
			if _viewmodel_2d: 
				_viewmodel_2d.frame = 0
				if _emissive_2d: _emissive_2d.frame = 0
		)

	_eject_shell()
	
	# FOV Kick & Pitch/Yaw Recoil
	var player = get_tree().get_first_node_in_group("player")
	if player:
		if player.has_method("apply_fov_kick"):
			player.apply_fov_kick(fov_kick_amount)
		if player.has_method("add_camera_recoil"):
			# Add some randomness to yaw
			var r_yaw = recoil_yaw * randf_range(-1.0, 1.0)
			player.add_camera_recoil(recoil_pitch, r_yaw)

	var cam: Camera3D = get_viewport().get_camera_3d()
	if not cam: return

	var cam_origin = cam.global_position
	var cam_forward = -cam.global_transform.basis.z.normalized()

	if is_projectile and projectile_scene:
		_fire_projectile(cam_origin, cam_forward)
		_show_muzzle_flash()
	else:
		_fire_hitscan(cam_origin, cam_forward)

func _fire_projectile(cam_origin: Vector3, cam_forward: Vector3) -> void:
	var proj = projectile_scene.instantiate() as Node3D
	var spawn_parent = get_tree().current_scene
	if not spawn_parent:
		return

	if proj is Projectile:
		proj.direction = cam_forward
		proj.damage = damage
		var shooter_node = get_tree().get_first_node_in_group("player")
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

func _fire_hitscan(cam_origin: Vector3, cam_forward: Vector3) -> void:
	var space_state = get_world_3d().direct_space_state
	var ray_end = cam_origin + cam_forward * ray_range

	var query = PhysicsRayQueryParameters3D.create(cam_origin, ray_end)
	query.collide_with_areas = true
	query.collision_mask = 0xFFFFFFFF

	var player_body = get_tree().get_first_node_in_group("player")
	if player_body:
		query.exclude = [player_body.get_rid()]

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
	_show_muzzle_flash()

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

func _find_hitbox(node: Node) -> HitboxComponent:
	var current = node
	while current != null and current != get_tree().root:
		if current is HitboxComponent: return current
		for child in current.get_children():
			if child is HitboxComponent: return child
		current = current.get_parent()
	return null

func _show_muzzle_flash() -> void:
	muzzle_flash.visible = true
	if _muzzle_2d:
		_muzzle_2d.visible = true
		_muzzle_2d.frame = randi() % 4
		_muzzle_2d.rotation = randf() * TAU
	
	await get_tree().create_timer(0.05).timeout
	
	muzzle_flash.visible = false
	if _muzzle_2d:
		_muzzle_2d.visible = false

func _show_tracer(from: Vector3, to: Vector3) -> void:
	tracer.visible = true
	tracer.global_position = (from + to) / 2.0
	tracer.scale = Vector3(0.01, 0.01, from.distance_to(to))
	tracer.look_at(to, Vector3.UP)
	tracer.rotate_object_local(Vector3.RIGHT, PI / 2.0)
	await get_tree().create_timer(0.05).timeout
	tracer.visible = false
