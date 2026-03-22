extends Area3D
class_name LootPickup

var item_data: InventoryItemData = null
var ammo_type: String = ""
var ammo_amount: int = 0
var ammo_display_name: String = ""
var ammo_icon_path: String = ""
var health_amount: int = 0
var health_display_name: String = ""
var health_icon_path: String = ""

const ROTATE_SPEED := 1.2
const LAUNCH_DURATION := 0.55
const FLOOR_ICON_CLEARANCE := 0.01
const FLOOR_SNAP_START_OFFSET := 0.25
const FLOOR_SNAP_DOWN_DISTANCE := 24.0
const FLOOR_NORMAL_MIN_DOT := 0.55
const FALL_GRAVITY := 24.0
const FALL_MAX_SPEED := 30.0
const FLOOR_LAND_CLEARANCE := 0.02
const BEACON_PULSE_SPEED := 3.4
const BEACON_MIN_ALPHA := 0.12
const BEACON_MAX_ALPHA := 0.24
const BEACON_MIN_LIGHT_ENERGY := 0.55
const BEACON_MAX_LIGHT_ENERGY := 1.05
const BEACON_HEIGHT := 10.0
const BEACON_WIDTH := 0.18
const BEACON_TEXTURE: Texture2D = preload("res://Assets/Effects/vfx_circle_fill.png")
const BEACON_RING_TEXTURE: Texture2D = preload("res://Assets/Effects/vfx_ring.png")

var _hover_time := 0.0
var _sprite: Sprite3D = null
var _picked_up := false
var _launching := false
var _falling := false
var _vertical_velocity := 0.0
var _beacon_column: MeshInstance3D = null
var _beacon_column_material: StandardMaterial3D = null
var _beacon_ring: MeshInstance3D = null
var _beacon_ring_material: StandardMaterial3D = null
var _beacon_light: OmniLight3D = null

func _ready() -> void:
	add_to_group("loot_pickup")
	_sprite = Sprite3D.new()
	_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_sprite.pixel_size = 0.001
	add_child(_sprite)
	_setup_beacon_nodes()

	var shape_node := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.3
	shape_node.shape = sphere
	add_child(shape_node)

	if item_data != null or _is_ammo_pickup() or _is_health_pickup():
		_apply_icon()

	# Health and ammo auto-collect on walk-over; gear stays as an interact-only pickup.
	if _is_health_pickup() or _is_ammo_pickup():
		collision_mask = 2  # player CharacterBody3D is on layer 2
		body_entered.connect(_on_body_entered)

func _apply_icon() -> void:
	if _sprite == null:
		return
	if _is_health_pickup():
		if not health_icon_path.is_empty() and ResourceLoader.exists(health_icon_path):
			_sprite.texture = load(health_icon_path)
		_update_sprite_floor_offset()
		_sprite.modulate = Color.WHITE
		_set_beacon_visible(false)
		return
	if _is_ammo_pickup():
		if not ammo_icon_path.is_empty() and ResourceLoader.exists(ammo_icon_path):
			_sprite.texture = load(ammo_icon_path)
		_update_sprite_floor_offset()
		_sprite.modulate = Color.WHITE
		_set_beacon_visible(false)
		return
	if item_data == null:
		_set_beacon_visible(false)
		return
	var tex: Texture2D = item_data.item_icon
	if tex == null and not item_data.item_icon_path.is_empty():
		if ResourceLoader.exists(item_data.item_icon_path):
			tex = load(item_data.item_icon_path)
	if tex != null:
		_sprite.texture = tex
	_update_sprite_floor_offset()
	_sprite.modulate = Color.WHITE
	_apply_rarity_beacon()

func launch(from_pos: Vector3, direction: Vector3) -> void:
	global_position = from_pos
	_launching = true
	_falling = false
	_vertical_velocity = 0.0
	var spread := Vector3(randf_range(-0.3, 0.3), 0.0, randf_range(-0.3, 0.3))
	var land_pos := from_pos + direction * randf_range(0.6, 1.4) + spread
	land_pos.y = from_pos.y
	var peak_y := from_pos.y + randf_range(0.7, 1.2)
	var half := LAUNCH_DURATION * 0.5

	# Horizontal: linear travel to landing spot
	var tx := create_tween()
	tx.tween_property(self, "global_position:x", land_pos.x, LAUNCH_DURATION)
	var tz := create_tween()
	tz.tween_property(self, "global_position:z", land_pos.z, LAUNCH_DURATION)

	# Vertical: arc up then fall down, then start hover
	var ty := create_tween()
	ty.tween_property(self, "global_position:y", peak_y, half).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	ty.tween_property(self, "global_position:y", land_pos.y, half).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	ty.tween_callback(_finish_launch)

func _finish_launch() -> void:
	_launching = false
	_resolve_ground_support()

func settle_at(world_pos: Vector3) -> void:
	_launching = false
	_falling = false
	_vertical_velocity = 0.0
	global_position = world_pos
	_resolve_ground_support()

func _process(delta: float) -> void:
	_hover_time += delta
	if _sprite:
		_sprite.rotation.y += ROTATE_SPEED * delta
	_update_beacon_visuals()

func _physics_process(delta: float) -> void:
	if _launching or not _falling:
		return
	_vertical_velocity = maxf(_vertical_velocity - FALL_GRAVITY * delta, -FALL_MAX_SPEED)
	var target_y := global_position.y + _vertical_velocity * delta
	var support := _find_support_below(global_position, FLOOR_SNAP_START_OFFSET + absf(_vertical_velocity * delta) + FLOOR_LAND_CLEARANCE)
	if not support.is_empty():
		var support_y := float((support.get("position", global_position) as Vector3).y) + FLOOR_LAND_CLEARANCE
		if target_y <= support_y:
			global_position.y = support_y
			_falling = false
			_vertical_velocity = 0.0
			return
	global_position.y = target_y

func _on_body_entered(body: Node) -> void:
	if _picked_up:
		return
	if not body.is_in_group("player"):
		return
	# In multiplayer each machine runs its own physics, so remote player bodies
	# would trigger this on both host and client. Only let the locally-controlled
	# player fire the pickup; the existing request_interaction RPC path handles
	# authority and syncing.
	if body.has_method("is_local_controlled") and not body.call("is_local_controlled"):
		return
	_picked_up = true
	var interaction_manager := get_tree().get_first_node_in_group("world_item_drop_manager")
	if interaction_manager == null:
		interaction_manager = get_tree().get_first_node_in_group("dungeon_manager")
	if interaction_manager != null and interaction_manager.has_method("request_interaction"):
		interaction_manager.call("request_interaction", body, self)
	else:
		interact(body)


func interact(interactor: Node) -> void:
	if _is_health_pickup():
		if interactor == null or not interactor.has_method("heal"):
			return
		if int(interactor.get("current_health")) >= int(interactor.get("max_health")):
			return
		interactor.call("heal", health_amount)
		if interactor.has_method("show_hud_toast"):
			interactor.call("show_hud_toast", "+%d Health" % health_amount, "health")
		queue_free()
		return
	if _is_ammo_pickup():
		var manager: WeaponManager = interactor.get("weapon_manager") as WeaponManager
		if manager == null or ammo_type.is_empty() or ammo_amount <= 0:
			return
		manager.add_ammo(ammo_type, ammo_amount)
		if interactor.has_method("show_hud_toast"):
			interactor.call("show_hud_toast", "+%d %s" % [ammo_amount, _get_ammo_display_name()], "ammo")
		queue_free()
		return
	if item_data == null:
		queue_free()
		return
	var inv: InventorySystem = interactor.get("inventory_system") as InventorySystem
	if inv == null:
		return
	if inv.try_add_to_storage(item_data):
		if interactor.has_method("show_hud_toast"):
			interactor.call("show_hud_toast", "Picked up %s" % item_data.display_name, "loot")
		queue_free()
	elif interactor.has_method("show_hud_toast"):
		interactor.call("show_hud_toast", "Inventory Full", "loot")

func get_item_snapshot() -> Dictionary:
	if _is_health_pickup():
		return {
			"display_name": _get_health_display_name(),
			"category": "health",
			"health_amount": health_amount,
			"icon_path": health_icon_path,
			"rarity": ""
		}
	if _is_ammo_pickup():
		return {
			"display_name": _get_ammo_display_name(),
			"category": "ammo",
			"ammo_type": ammo_type,
			"ammo_amount": ammo_amount,
			"icon_path": ammo_icon_path,
			"rarity": ""
		}
	if item_data == null:
		return {}
	return item_data.to_dict()

func configure_ammo_pickup(new_ammo_type: String, new_ammo_amount: int, new_display_name: String, new_icon_path: String) -> void:
	ammo_type = new_ammo_type
	ammo_amount = new_ammo_amount
	ammo_display_name = new_display_name
	ammo_icon_path = new_icon_path
	if _sprite != null:
		_apply_icon()

func configure_health_pickup(new_health_amount: int, new_display_name: String, new_icon_path: String) -> void:
	health_amount = new_health_amount
	health_display_name = new_display_name
	health_icon_path = new_icon_path
	if _sprite != null:
		_apply_icon()

func configure_item_pickup(new_item_data: InventoryItemData) -> void:
	item_data = new_item_data
	ammo_type = ""
	ammo_amount = 0
	ammo_display_name = ""
	ammo_icon_path = ""
	health_amount = 0
	health_display_name = ""
	health_icon_path = ""
	if _sprite != null:
		_apply_icon()

func _is_ammo_pickup() -> bool:
	return not ammo_type.is_empty() and ammo_amount > 0

func _is_health_pickup() -> bool:
	return health_amount > 0

func _get_ammo_display_name() -> String:
	if not ammo_display_name.is_empty():
		return ammo_display_name
	return "%s Ammo" % ammo_type.capitalize()

func _get_health_display_name() -> String:
	if not health_display_name.is_empty():
		return health_display_name
	return "Health Pickup"

func _update_sprite_floor_offset() -> void:
	if _sprite == null:
		return
	if _sprite.texture == null:
		_sprite.position = Vector3(0.0, FLOOR_ICON_CLEARANCE, 0.0)
		return
	var sprite_height := float(_sprite.texture.get_height()) * _sprite.pixel_size
	var bottom_padding := _get_texture_bottom_padding(_sprite.texture)
	_sprite.position = Vector3(
		0.0,
		(sprite_height * 0.5) - (bottom_padding * _sprite.pixel_size) + FLOOR_ICON_CLEARANCE,
		0.0
	)

func _get_texture_bottom_padding(texture: Texture2D) -> int:
	if texture == null:
		return 0
	var image := texture.get_image()
	if image == null or image.is_empty():
		return 0
	var height := image.get_height()
	var width := image.get_width()
	for y in range(height - 1, -1, -1):
		for x in range(width):
			if image.get_pixel(x, y).a > 0.04:
				return (height - 1) - y
	return 0

func _resolve_ground_support() -> void:
	var support := _find_support_below(global_position, FLOOR_SNAP_DOWN_DISTANCE)
	if support.is_empty():
		_falling = true
		return
	var support_pos: Vector3 = support.get("position", global_position)
	if support_pos.y > global_position.y + FLOOR_LAND_CLEARANCE:
		_falling = true
		return
	global_position.y = support_pos.y + FLOOR_LAND_CLEARANCE
	_falling = false
	_vertical_velocity = 0.0

func _find_support_below(world_pos: Vector3, max_distance: float) -> Dictionary:
	var world := get_world_3d()
	if world == null:
		return {}
	var space_state := world.direct_space_state
	if space_state == null:
		return {}
	var query := PhysicsRayQueryParameters3D.create(
		world_pos + Vector3.UP * FLOOR_SNAP_START_OFFSET,
		world_pos + Vector3.DOWN * max_distance
	)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var result := space_state.intersect_ray(query)
	if result.is_empty():
		return {}
	var normal: Vector3 = result.get("normal", Vector3.UP)
	if normal.dot(Vector3.UP) < FLOOR_NORMAL_MIN_DOT:
		return {}
	var hit_pos: Vector3 = result.get("position", world_pos)
	if hit_pos.y > world_pos.y + FLOOR_LAND_CLEARANCE:
		return {}
	return result

func _setup_beacon_nodes() -> void:
	var column_mesh := QuadMesh.new()
	column_mesh.size = Vector2(BEACON_WIDTH, BEACON_HEIGHT)
	_beacon_column = MeshInstance3D.new()
	_beacon_column.name = "RarityBeaconColumn"
	_beacon_column.mesh = column_mesh
	_beacon_column.position = Vector3(0.0, BEACON_HEIGHT * 0.5, 0.0)
	_beacon_column.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_beacon_column)

	_beacon_column_material = StandardMaterial3D.new()
	_beacon_column_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_beacon_column_material.blend_mode = StandardMaterial3D.BLEND_MODE_ADD
	_beacon_column_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_beacon_column_material.albedo_texture = BEACON_TEXTURE
	_beacon_column_material.albedo_color = Color(1.0, 1.0, 1.0, BEACON_MIN_ALPHA)
	_beacon_column_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_beacon_column_material.no_depth_test = true
	_beacon_column_material.uv1_scale = Vector3(1.0, 3.5, 1.0)
	_beacon_column.material_override = _beacon_column_material

	var ring_mesh := QuadMesh.new()
	ring_mesh.size = Vector2(0.95, 0.95)
	_beacon_ring = MeshInstance3D.new()
	_beacon_ring.name = "RarityBeaconRing"
	_beacon_ring.mesh = ring_mesh
	_beacon_ring.position = Vector3(0.0, 0.12, 0.0)
	_beacon_ring.rotation_degrees.x = -90.0
	_beacon_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_beacon_ring)

	_beacon_ring_material = StandardMaterial3D.new()
	_beacon_ring_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_beacon_ring_material.blend_mode = StandardMaterial3D.BLEND_MODE_ADD
	_beacon_ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_beacon_ring_material.albedo_texture = BEACON_RING_TEXTURE
	_beacon_ring_material.albedo_color = Color(1.0, 1.0, 1.0, 0.3)
	_beacon_ring_material.no_depth_test = true
	_beacon_ring.material_override = _beacon_ring_material

	_beacon_light = OmniLight3D.new()
	_beacon_light.name = "RarityBeaconLight"
	_beacon_light.position = Vector3(0.0, 0.55, 0.0)
	_beacon_light.omni_range = 3.0
	_beacon_light.light_energy = BEACON_MIN_LIGHT_ENERGY
	_beacon_light.shadow_enabled = false
	add_child(_beacon_light)

	_set_beacon_visible(false)

func _apply_rarity_beacon() -> void:
	var color: Color = _get_rarity_color()
	if color.a <= 0.0:
		_set_beacon_visible(false)
		return
	_set_beacon_visible(true)
	_beacon_column_material.albedo_color = Color(color.r, color.g, color.b, BEACON_MIN_ALPHA)
	_beacon_ring_material.albedo_color = Color(color.r, color.g, color.b, 0.28)
	_beacon_light.light_color = color
	_beacon_light.light_energy = BEACON_MIN_LIGHT_ENERGY

func _update_beacon_visuals() -> void:
	if _beacon_column == null or not _beacon_column.visible:
		return
	var pulse := 0.5 + 0.5 * sin(_hover_time * BEACON_PULSE_SPEED)
	var alpha := lerpf(BEACON_MIN_ALPHA, BEACON_MAX_ALPHA, pulse)
	var ring_alpha := lerpf(0.18, 0.34, pulse)
	var color: Color = _get_rarity_color()
	if color.a <= 0.0:
		return
	_beacon_column_material.albedo_color = Color(color.r, color.g, color.b, alpha)
	_beacon_ring_material.albedo_color = Color(color.r, color.g, color.b, ring_alpha)
	_beacon_ring.rotation_degrees.z = fmod(_hover_time * -42.0, 360.0)
	var ring_scale := lerpf(0.92, 1.08, pulse)
	_beacon_ring.scale = Vector3.ONE * ring_scale
	_beacon_column.scale = Vector3(lerpf(0.92, 1.08, pulse), 1.0, 1.0)
	_beacon_light.light_energy = lerpf(BEACON_MIN_LIGHT_ENERGY, BEACON_MAX_LIGHT_ENERGY, pulse)

func _set_beacon_visible(is_visible: bool) -> void:
	if _beacon_column != null:
		_beacon_column.visible = is_visible
	if _beacon_ring != null:
		_beacon_ring.visible = is_visible
	if _beacon_light != null:
		_beacon_light.visible = is_visible

func _get_rarity_color() -> Color:
	if item_data == null or _is_ammo_pickup() or _is_health_pickup():
		return Color(0.0, 0.0, 0.0, 0.0)
	var rarity := item_data.rarity_name
	if rarity.is_empty():
		rarity = String(item_data.stats.get("rarity", ""))
	match rarity:
		"Legendary":
			return Color("ff9f2f")
		"Epic":
			return Color("b05cff")
		"Rare":
			return Color("4d7dff")
		"Uncommon":
			return Color("49b36a")
		"Common":
			return Color("d7dce4")
	return Color(0.0, 0.0, 0.0, 0.0)
