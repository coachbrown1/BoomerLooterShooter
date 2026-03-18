extends Node
class_name PlayerMobilityController

const ABILITY_NONE: StringName = &""
const ABILITY_DASH: StringName = &"dash_pack"
const ABILITY_GRAPPLE: StringName = &"grapple_hook"
const ABILITY_JET: StringName = &"jet_pack"

@export var base_dash_speed: float = 18.0
@export var base_dash_distance: float = 6.0
@export var base_dash_duration: float = 0.22
@export var base_dash_cooldown: float = 1.1
@export var base_grapple_range: float = 18.0
@export var base_grapple_pull_speed: float = 15.0
@export var base_grapple_stop_distance: float = 1.2
@export var base_jet_thrust: float = 13.0
@export var base_jet_takeoff_burst: float = 5.5
@export var base_jet_fuel: float = 1.8
@export var base_jet_recharge_delay: float = 0.8
@export var base_jet_recharge_rate: float = 1.2

var player: CharacterBody3D = null
var head: Node3D = null
var visuals: Node3D = null
var _grapple_visual: MeshInstance3D = null
var _grapple_visual_material: StandardMaterial3D = null
var _input_enabled: bool = true
var _primary_ability: StringName = ABILITY_NONE
var _secondary_ability: StringName = ABILITY_NONE
var _active_ability: StringName = ABILITY_NONE
var _active_slot: StringName = &"utility_primary"
var _primary_item_name: String = ""
var _secondary_item_name: String = ""
var _active_item_name: String = ""
var _active_item_rarity: String = ""
var _dash_direction: Vector3 = Vector3.ZERO
var _dash_time_left: float = 0.0
var _dash_cooldown_left: float = 0.0
var _grapple_active: bool = false
var _grapple_anchor: Vector3 = Vector3.ZERO
var _jet_active: bool = false
var _jet_fuel_current: float = base_jet_fuel
var _jet_recharge_delay_left: float = 0.0
var _stats: Dictionary = {}

func setup(owner_player: CharacterBody3D, owner_head: Node3D, owner_visuals: Node3D) -> void:
	player = owner_player
	head = owner_head
	visuals = owner_visuals
	_ensure_grapple_visual()
	_update_grapple_visual()
	_refresh_hud()

func set_input_enabled(enabled: bool) -> void:
	_input_enabled = enabled

func apply_equipment(stats: Dictionary, primary_item: InventoryItemData, secondary_item: InventoryItemData = null) -> void:
	_stats = stats.duplicate(true)
	_primary_ability = _resolve_item_ability(primary_item)
	_secondary_ability = _resolve_item_ability(secondary_item)
	_primary_item_name = "" if primary_item == null else primary_item.display_name
	_secondary_item_name = "" if secondary_item == null else secondary_item.display_name
	if _active_ability == ABILITY_NONE or (_active_ability != _primary_ability and _active_ability != _secondary_ability):
		_set_active_utility_slot(&"utility_primary", primary_item)
	if _active_ability != ABILITY_JET:
		_jet_active = false
		_jet_fuel_current = get_max_jet_fuel()
	if _active_ability != ABILITY_GRAPPLE:
		_grapple_active = false
		_update_grapple_visual()
	if _active_ability != ABILITY_DASH:
		_dash_time_left = 0.0
		_dash_cooldown_left = 0.0
	_refresh_hud()

func physics_update(delta: float, input_dir: Vector2, can_process_input: bool, inventory_open: bool) -> void:
	if player == null:
		return
	_tick_resources(delta)
	if can_process_input and _input_enabled and not inventory_open:
		_process_input()
	_apply_active_state(delta, input_dir)
	_refresh_hud()

func get_air_control_multiplier() -> float:
	return maxf(0.2, 1.0 + float(_stats.get("air_control_mult", 0.0)))

func is_dash_active() -> bool:
	return _dash_time_left > 0.0

func is_grapple_active() -> bool:
	return _grapple_active

func is_jet_active() -> bool:
	return _jet_active

func get_dash_cooldown_ratio() -> float:
	var cooldown := get_dash_cooldown()
	if cooldown <= 0.0:
		return 0.0
	return clampf(_dash_cooldown_left / cooldown, 0.0, 1.0)

func get_max_jet_fuel() -> float:
	return maxf(0.4, base_jet_fuel + float(_stats.get("jet_fuel_add", 0.0)))

func build_state_snapshot() -> Dictionary:
	return {
		"ability": String(_active_ability),
		"active_slot": String(_active_slot),
		"item_name": _active_item_name,
		"item_rarity": _active_item_rarity,
		"primary_ability": String(_primary_ability),
		"primary_item_name": _primary_item_name,
		"secondary_ability": String(_secondary_ability),
		"secondary_item_name": _secondary_item_name,
		"dash_time_left": _dash_time_left,
		"dash_cooldown_left": _dash_cooldown_left,
		"grapple_active": _grapple_active,
		"grapple_anchor": _grapple_anchor,
		"jet_active": _jet_active,
		"jet_fuel_current": _jet_fuel_current,
		"jet_recharge_delay_left": _jet_recharge_delay_left,
	}

func apply_remote_state(snapshot: Dictionary) -> void:
	if snapshot.is_empty():
		return
	_active_ability = StringName(snapshot.get("ability", ""))
	_active_slot = StringName(snapshot.get("active_slot", String(_active_slot)))
	_active_item_name = String(snapshot.get("item_name", ""))
	_active_item_rarity = String(snapshot.get("item_rarity", ""))
	_primary_ability = StringName(snapshot.get("primary_ability", String(_primary_ability)))
	_primary_item_name = String(snapshot.get("primary_item_name", _primary_item_name))
	_secondary_ability = StringName(snapshot.get("secondary_ability", String(_secondary_ability)))
	_secondary_item_name = String(snapshot.get("secondary_item_name", _secondary_item_name))
	_dash_time_left = maxf(0.0, float(snapshot.get("dash_time_left", _dash_time_left)))
	_dash_cooldown_left = maxf(0.0, float(snapshot.get("dash_cooldown_left", _dash_cooldown_left)))
	_grapple_active = bool(snapshot.get("grapple_active", _grapple_active))
	_grapple_anchor = snapshot.get("grapple_anchor", _grapple_anchor)
	_jet_active = bool(snapshot.get("jet_active", _jet_active))
	_jet_fuel_current = clampf(float(snapshot.get("jet_fuel_current", _jet_fuel_current)), 0.0, get_max_jet_fuel())
	_jet_recharge_delay_left = maxf(0.0, float(snapshot.get("jet_recharge_delay_left", _jet_recharge_delay_left)))
	_update_grapple_visual()
	_refresh_hud()

func handle_authoritative_action(action: StringName, payload: Dictionary) -> void:
	match action:
		&"dash":
			_start_dash(payload.get("direction", Vector3.ZERO))
		&"grapple_start":
			_start_grapple(payload.get("origin", Vector3.ZERO), payload.get("direction", Vector3.ZERO))
		&"grapple_stop":
			_stop_grapple()
		&"jet_start":
			_start_jet()
		&"jet_stop":
			_stop_jet()

func get_debug_state() -> Dictionary:
	return {
		"ability": String(_active_ability),
		"active_slot": String(_active_slot),
		"primary_ability": String(_primary_ability),
		"secondary_ability": String(_secondary_ability),
		"dash_active": is_dash_active(),
		"dash_cooldown_left": _dash_cooldown_left,
		"grapple_active": _grapple_active,
		"grapple_anchor": _grapple_anchor,
		"jet_active": _jet_active,
		"jet_fuel_current": _jet_fuel_current,
		"jet_fuel_max": get_max_jet_fuel(),
	}

func _process_input() -> void:
	if player == null:
		return
	if _grapple_active and Input.is_action_just_pressed("jump"):
		_request_action(&"grapple_stop", {})
		return
	if Input.is_action_just_pressed("mobility_cancel"):
		_request_action(&"grapple_stop", {})
		_request_action(&"jet_stop", {})
	var wants_primary := Input.is_action_just_pressed("mobility_activate")
	var wants_secondary := Input.is_action_just_pressed("mobility_secondary_activate")
	if not wants_primary and not wants_secondary:
		var active_action_name := "mobility_activate" if _active_slot == &"utility_primary" else "mobility_secondary_activate"
		if _active_ability == ABILITY_JET and _jet_active and not Input.is_action_pressed(active_action_name):
			_request_action(&"jet_stop", {})
		return
	var requested_slot: StringName = &"utility_primary" if wants_primary else &"utility_secondary"
	var requested_ability: StringName = _primary_ability if wants_primary else _secondary_ability
	var requested_item_name: String = _primary_item_name if wants_primary else _secondary_item_name
	var pressed_action_name := "mobility_activate" if wants_primary else "mobility_secondary_activate"
	if requested_ability == ABILITY_NONE:
		return
	_set_active_utility_slot(requested_slot, null, requested_ability, requested_item_name)
	match requested_ability:
		ABILITY_DASH:
			_request_action(&"dash", {"direction": _get_requested_direction()})
		ABILITY_GRAPPLE:
			if _grapple_active:
				_request_action(&"grapple_stop", {})
			else:
				_request_action(&"grapple_start", {
					"origin": _get_aim_origin(),
					"direction": _get_aim_direction(),
				})
		ABILITY_JET:
			_request_action(&"jet_start", {})
	if requested_ability == ABILITY_JET and not Input.is_action_pressed(pressed_action_name):
		_request_action(&"jet_stop", {})

func _tick_resources(delta: float) -> void:
	_dash_cooldown_left = maxf(0.0, _dash_cooldown_left - delta)
	if _dash_time_left > 0.0:
		_dash_time_left = maxf(0.0, _dash_time_left - delta)
	if _jet_active:
		_jet_fuel_current = maxf(0.0, _jet_fuel_current - delta)
		_jet_recharge_delay_left = get_jet_recharge_delay()
		if _jet_fuel_current <= 0.0:
			_stop_jet()
	else:
		_jet_recharge_delay_left = maxf(0.0, _jet_recharge_delay_left - delta)
		if _jet_recharge_delay_left <= 0.0:
			_jet_fuel_current = minf(get_max_jet_fuel(), _jet_fuel_current + get_jet_recharge_rate() * delta)

func _apply_active_state(delta: float, input_dir: Vector2) -> void:
	if player == null:
		return
	if _dash_time_left > 0.0:
		player.velocity.x = _dash_direction.x * get_dash_speed()
		player.velocity.z = _dash_direction.z * get_dash_speed()
		player.velocity.y = maxf(player.velocity.y, 0.0)
	if _grapple_active:
		var toward := _grapple_anchor - player.global_position
		var distance := toward.length()
		if distance <= base_grapple_stop_distance:
			_stop_grapple()
		else:
			var dir := toward / maxf(distance, 0.001)
			var pull_speed := get_grapple_pull_speed()
			player.velocity.x = dir.x * pull_speed
			player.velocity.y = dir.y * pull_speed
			player.velocity.z = dir.z * pull_speed
	if _jet_active:
		player.velocity.y += get_jet_thrust() * delta
		if input_dir.length() > 0.05:
			var flat_direction := (player.transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
			player.velocity.x = move_toward(player.velocity.x, flat_direction.x * player.move_speed, player.move_speed * delta * 4.0)
			player.velocity.z = move_toward(player.velocity.z, flat_direction.z * player.move_speed, player.move_speed * delta * 4.0)
	_update_grapple_visual()

func _request_action(action: StringName, payload: Dictionary) -> void:
	if player == null:
		return
	if _is_multiplayer_active() and not _is_network_host():
		NetworkPlayerManager.request_mobility_action(action, payload)
		return
	handle_authoritative_action(action, payload)

func _start_dash(direction: Vector3) -> void:
	if _active_ability != ABILITY_DASH or _dash_cooldown_left > 0.0:
		return
	var dash_dir := direction
	if dash_dir.length_squared() <= 0.0001:
		dash_dir = _get_requested_direction()
	if dash_dir.length_squared() <= 0.0001:
		dash_dir = -player.global_transform.basis.z
	dash_dir.y = 0.0
	dash_dir = dash_dir.normalized()
	if dash_dir.length_squared() <= 0.0001:
		return
	_dash_direction = dash_dir
	_dash_time_left = get_dash_duration()
	_dash_cooldown_left = get_dash_cooldown()
	_stop_grapple()
	_stop_jet()

func _start_grapple(origin: Vector3, direction: Vector3) -> void:
	if _active_ability != ABILITY_GRAPPLE:
		return
	var space_state := player.get_world_3d().direct_space_state
	var max_range := get_grapple_range()
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction.normalized() * max_range)
	query.exclude = [player.get_rid()]
	query.collide_with_areas = true
	query.collide_with_bodies = true
	var hit := space_state.intersect_ray(query)
	if hit.is_empty():
		return
	_grapple_anchor = hit.get("position", Vector3.ZERO)
	_grapple_active = true
	_stop_jet()
	_update_grapple_visual()

func _stop_grapple() -> void:
	_grapple_active = false
	_update_grapple_visual()

func _start_jet() -> void:
	if _active_ability != ABILITY_JET:
		return
	if _jet_fuel_current <= 0.05:
		return
	_stop_grapple()
	_jet_active = true
	_jet_recharge_delay_left = get_jet_recharge_delay()
	if player.is_on_floor():
		player.velocity.y = maxf(player.velocity.y, get_jet_takeoff_burst())

func _stop_jet() -> void:
	_jet_active = false

func _get_requested_direction() -> Vector3:
	if player == null:
		return Vector3.ZERO
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if input_dir.length_squared() <= 0.0001:
		return -player.global_transform.basis.z
	var direction := (player.transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
	direction.y = 0.0
	return direction.normalized()

func _get_aim_origin() -> Vector3:
	if head != null and head.has_node("Camera3D"):
		var camera := head.get_node("Camera3D") as Camera3D
		if camera != null:
			return camera.global_position
	return player.global_position + Vector3.UP

func _get_aim_direction() -> Vector3:
	if head != null and head.has_node("Camera3D"):
		var camera := head.get_node("Camera3D") as Camera3D
		if camera != null:
			return -camera.global_transform.basis.z.normalized()
	return -player.global_transform.basis.z.normalized()

func get_dash_speed() -> float:
	return base_dash_speed + float(_stats.get("dash_speed_add", 0.0))

func get_dash_duration() -> float:
	var duration := base_dash_duration + (float(_stats.get("dash_distance_add", 0.0)) / maxf(base_dash_speed, 0.001))
	return maxf(0.08, duration)

func get_dash_cooldown() -> float:
	return maxf(0.2, base_dash_cooldown * (1.0 + float(_stats.get("dash_cooldown_mult", 0.0))))

func get_grapple_range() -> float:
	return maxf(4.0, base_grapple_range + float(_stats.get("grapple_range_add", 0.0)))

func get_grapple_pull_speed() -> float:
	return maxf(4.0, base_grapple_pull_speed * (1.0 + float(_stats.get("grapple_pull_speed_mult", 0.0))))

func get_jet_thrust() -> float:
	return maxf(4.0, base_jet_thrust + float(_stats.get("jet_thrust_add", 0.0)))

func get_jet_takeoff_burst() -> float:
	return maxf(2.0, base_jet_takeoff_burst + float(_stats.get("jump_velocity_add", 0.0)))

func get_jet_recharge_delay() -> float:
	return maxf(0.1, base_jet_recharge_delay * (1.0 + float(_stats.get("jet_recharge_mult", 0.0))))

func get_jet_recharge_rate() -> float:
	return maxf(0.3, base_jet_recharge_rate * (1.0 + float(_stats.get("jet_recharge_rate_mult", 0.0))))

func _refresh_hud() -> void:
	if player == null or not player.has_method("is_local_controlled") or not player.call("is_local_controlled"):
		return
	var hud: Node = player.call("_get_hud")
	if hud != null and hud.has_method("update_mobility_status"):
		hud.call("update_mobility_status", {
			"ability": String(_active_ability),
			"item_name": _active_item_name,
			"item_rarity": _active_item_rarity,
			"primary_ability": String(_primary_ability),
			"primary_item_name": _primary_item_name,
			"secondary_ability": String(_secondary_ability),
			"secondary_item_name": _secondary_item_name,
			"dash_active": is_dash_active(),
			"dash_cooldown_ratio": get_dash_cooldown_ratio(),
			"grapple_active": _grapple_active,
			"jet_active": _jet_active,
			"jet_fuel_current": _jet_fuel_current,
			"jet_fuel_max": get_max_jet_fuel(),
		})

func _is_multiplayer_active() -> bool:
	return NetworkSession != null and NetworkSession.is_multiplayer_active()

func _is_network_host() -> bool:
	return NetworkSession != null and NetworkSession.is_host()

func _resolve_item_ability(item: InventoryItemData) -> StringName:
	if item == null:
		return ABILITY_NONE
	if item.active_ability != StringName(""):
		return item.active_ability
	var item_id_text := String(item.item_id)
	if item_id_text.contains("dash_pack"):
		return ABILITY_DASH
	if item_id_text.contains("grapple_hook"):
		return ABILITY_GRAPPLE
	if item_id_text.contains("jet_pack"):
		return ABILITY_JET
	var name_text := item.display_name.to_lower()
	if name_text.contains("dash"):
		return ABILITY_DASH
	if name_text.contains("grapple"):
		return ABILITY_GRAPPLE
	if name_text.contains("jet"):
		return ABILITY_JET
	return ABILITY_NONE

func _set_active_utility_slot(slot_name: StringName, item: InventoryItemData = null, ability: StringName = ABILITY_NONE, item_name: String = "") -> void:
	if item != null:
		ability = _resolve_item_ability(item)
		item_name = item.display_name
		_active_item_rarity = item.rarity_name
		if _active_item_rarity.is_empty():
			_active_item_rarity = String(item.stats.get("rarity", ""))
	else:
		_active_item_rarity = ""
	if slot_name == &"utility_secondary" and ability == ABILITY_NONE:
		ability = _secondary_ability
		item_name = _secondary_item_name
	if slot_name == &"utility_primary" and ability == ABILITY_NONE:
		ability = _primary_ability
		item_name = _primary_item_name
	_active_slot = slot_name
	_active_ability = ability
	_active_item_name = item_name

func _ensure_grapple_visual() -> void:
	if player == null or _grapple_visual != null:
		return
	_grapple_visual = MeshInstance3D.new()
	_grapple_visual.name = "GrappleTether"
	_grapple_visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.035
	cylinder.bottom_radius = 0.035
	cylinder.height = 1.0
	_grapple_visual.mesh = cylinder
	_grapple_visual_material = StandardMaterial3D.new()
	_grapple_visual_material.albedo_color = Color(0.85, 0.92, 1.0, 0.95)
	_grapple_visual_material.emission_enabled = true
	_grapple_visual_material.emission = Color(0.45, 0.75, 1.2, 1.0)
	_grapple_visual_material.emission_energy_multiplier = 1.2
	_grapple_visual_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_grapple_visual_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_grapple_visual.set_surface_override_material(0, _grapple_visual_material)
	player.add_child(_grapple_visual)

func _update_grapple_visual() -> void:
	if player == null:
		return
	_ensure_grapple_visual()
	if _grapple_visual == null:
		return
	if not _grapple_active:
		_grapple_visual.visible = false
		return
	var origin: Vector3 = _get_grapple_visual_origin()
	var toward: Vector3 = _grapple_anchor - origin
	var length: float = toward.length()
	if length <= 0.05:
		_grapple_visual.visible = false
		return
	_grapple_visual.visible = true
	_grapple_visual.global_position = origin + toward * 0.5
	_grapple_visual.look_at(_grapple_anchor, Vector3.UP)
	_grapple_visual.rotate_object_local(Vector3.RIGHT, deg_to_rad(90.0))
	_grapple_visual.scale = Vector3.ONE
	_grapple_visual.scale.y = length

func _get_grapple_visual_origin() -> Vector3:
	var weapon_origin := _get_weapon_grapple_origin()
	if weapon_origin != Vector3.ZERO:
		return weapon_origin
	if head != null and head.has_node("Camera3D"):
		var camera := head.get_node("Camera3D") as Camera3D
		if camera != null:
			var basis := camera.global_transform.basis
			return camera.global_position + (basis.x * 0.18) + (basis.y * -0.12) + (-basis.z * 0.28)
	return player.global_position + Vector3.UP * 1.35

func _get_weapon_grapple_origin() -> Vector3:
	if head == null or not head.has_node("WeaponMount"):
		return Vector3.ZERO
	var mount := head.get_node("WeaponMount") as Node3D
	if mount == null:
		return Vector3.ZERO
	var current_weapon: Node = mount.get("current_weapon")
	if current_weapon is Node3D:
		var weapon_node := current_weapon as Node3D
		if weapon_node.has_node("MuzzleFlash"):
			var muzzle := weapon_node.get_node("MuzzleFlash") as Node3D
			if muzzle != null:
				return muzzle.global_position
		return weapon_node.global_position
	return mount.global_position
