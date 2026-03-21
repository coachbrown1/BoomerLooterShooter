extends Node

var _debug_network_visual_counts := {
	"hitscan": 0,
	"projectile": 0,
	"weapon_fire": 0,
}

func _ready() -> void:
	if not NetworkSession.session_ended.is_connected(_on_network_session_ended):
		NetworkSession.session_ended.connect(_on_network_session_ended)
	if not NetworkSession.match_started.is_connected(_on_match_started):
		NetworkSession.match_started.connect(_on_match_started)
	_reset_debug_network_visual_counts()

func request_weapon_fire(peer_id: int, weapon_slot: int, weapon_key: String, cam_origin: Vector3, cam_forward: Vector3, shot_id: int) -> void:
	if not NetworkSession.is_multiplayer_active():
		return
	if NetworkSession.is_host():
		_handle_weapon_fire_request(peer_id, weapon_slot, weapon_key, cam_origin, cam_forward, shot_id)
	else:
		rpc_id(1, "rpc_request_weapon_fire", peer_id, weapon_slot, weapon_key, cam_origin, cam_forward, shot_id)

func request_weapon_reload(peer_id: int, weapon_slot: int, weapon_key: String) -> void:
	if not NetworkSession.is_multiplayer_active():
		return
	if NetworkSession.is_host():
		_handle_weapon_reload_request(peer_id, weapon_slot, weapon_key)
	else:
		rpc_id(1, "rpc_request_weapon_reload", peer_id, weapon_slot, weapon_key)

func request_weapon_switch(peer_id: int, weapon_slot: int, weapon_key: String) -> void:
	if not NetworkSession.is_multiplayer_active():
		return
	if NetworkSession.is_host():
		_handle_weapon_switch_request(peer_id, weapon_slot, weapon_key)
	else:
		rpc_id(1, "rpc_request_weapon_switch", peer_id, weapon_slot, weapon_key)

func broadcast_projectile_visual(scene_path: String, shooter_peer_id: int, origin: Vector3, cam_forward: Vector3) -> void:
	if not NetworkSession.is_multiplayer_active() or not NetworkSession.is_host():
		return
	if scene_path.is_empty() or shooter_peer_id <= 0:
		return
	rpc("rpc_spawn_projectile_visual", shooter_peer_id, scene_path, origin, cam_forward)

func broadcast_weapon_fire_visual(peer_id: int, muzzle_pos: Vector3) -> void:
	if not NetworkSession.is_multiplayer_active() or not NetworkSession.is_host():
		return
	if peer_id <= 0:
		return
	rpc("rpc_spawn_weapon_fire_visual", peer_id, muzzle_pos)

func broadcast_hitscan_visual(shooter_peer_id: int, from: Vector3, to: Vector3) -> void:
	if not NetworkSession.is_multiplayer_active() or not NetworkSession.is_host():
		return
	if shooter_peer_id <= 0:
		return
	rpc("rpc_spawn_hitscan_visual", shooter_peer_id, from, to)

func get_debug_network_visual_counts() -> Dictionary:
	return _debug_network_visual_counts.duplicate(true)

func reset_debug_network_visual_counts() -> void:
	_reset_debug_network_visual_counts()

func _handle_weapon_fire_request(peer_id: int, weapon_slot: int, weapon_key: String, cam_origin: Vector3, cam_forward: Vector3, _shot_id: int) -> void:
	var player_node := _get_player_node_for_peer(peer_id)
	if not is_instance_valid(player_node):
		return
	var manager: WeaponManager = player_node.get("weapon_manager")
	if manager == null:
		return
	if not weapon_key.is_empty() and manager.has_method("switch_to_weapon_by_key"):
		manager.call("switch_to_weapon_by_key", weapon_key, false)
	else:
		manager.switch_to_weapon(weapon_slot, false)
	var weapon := manager.get_current_weapon()
	if weapon == null and not weapon_key.is_empty() and manager.has_method("switch_to_weapon_by_key"):
		var switched := bool(manager.call("switch_to_weapon_by_key", weapon_key, false))
		if switched:
			weapon = manager.get_current_weapon()
	if weapon == null or not weapon.has_method("fire_authoritative_from_network"):
		return
	var fired := bool(weapon.call("fire_authoritative_from_network", cam_origin, cam_forward, player_node))
	if not fired:
		return
	rpc_id(
		peer_id,
		"rpc_sync_weapon_state",
		peer_id,
		manager.get_current_weapon_slot(),
		weapon.current_mag,
		manager.get_ammo_snapshot(),
		manager.get_current_weapon_key()
	)

func _handle_weapon_reload_request(peer_id: int, weapon_slot: int, weapon_key: String) -> void:
	var player_node := _get_player_node_for_peer(peer_id)
	if not is_instance_valid(player_node):
		return
	var manager: WeaponManager = player_node.get("weapon_manager")
	if manager == null:
		return
	if not weapon_key.is_empty() and manager.has_method("switch_to_weapon_by_key"):
		manager.call("switch_to_weapon_by_key", weapon_key, false)
	else:
		manager.switch_to_weapon(weapon_slot, false)
	var weapon := manager.get_current_weapon()
	if weapon == null and not weapon_key.is_empty() and manager.has_method("switch_to_weapon_by_key"):
		var switched := bool(manager.call("switch_to_weapon_by_key", weapon_key, false))
		if switched:
			weapon = manager.get_current_weapon()
	if weapon == null or not weapon.has_method("perform_authoritative_reload"):
		return
	var success := bool(weapon.call("perform_authoritative_reload"))
	if not success:
		return
	rpc_id(
		peer_id,
		"rpc_sync_weapon_state",
		peer_id,
		manager.get_current_weapon_slot(),
		weapon.current_mag,
		manager.get_ammo_snapshot(),
		manager.get_current_weapon_key()
	)

func _handle_weapon_switch_request(peer_id: int, weapon_slot: int, weapon_key: String) -> void:
	var player_node := _get_player_node_for_peer(peer_id)
	if not is_instance_valid(player_node):
		return
	var manager: WeaponManager = player_node.get("weapon_manager")
	if manager == null:
		return
	var switched := false
	if not weapon_key.is_empty() and manager.has_method("switch_to_weapon_by_key"):
		switched = bool(manager.call("switch_to_weapon_by_key", weapon_key, false))
	elif weapon_slot >= 0:
		var previous_slot := manager.get_current_weapon_slot()
		manager.switch_to_weapon(weapon_slot, false)
		switched = manager.get_current_weapon_slot() != previous_slot
	if not switched and manager.get_current_weapon() == null:
		return
	var weapon := manager.get_current_weapon()
	if weapon == null:
		return
	rpc_id(
		peer_id,
		"rpc_sync_weapon_state",
		peer_id,
		manager.get_current_weapon_slot(),
		weapon.current_mag,
		manager.get_ammo_snapshot(),
		manager.get_current_weapon_key()
	)

func _get_player_node_for_peer(peer_id: int) -> Node3D:
	var player = NetworkPlayerManager.get_player(peer_id)
	if player is Node3D and is_instance_valid(player):
		return player
	return null

func _get_local_peer_id() -> int:
	if not NetworkSession.is_multiplayer_active():
		return 1
	return NetworkSession.get_local_peer_id()

func _reset_debug_network_visual_counts() -> void:
	_debug_network_visual_counts["hitscan"] = 0
	_debug_network_visual_counts["projectile"] = 0
	_debug_network_visual_counts["weapon_fire"] = 0

func _on_network_session_ended(_reason: String) -> void:
	_reset_debug_network_visual_counts()

func _on_match_started() -> void:
	_reset_debug_network_visual_counts()

@rpc("any_peer", "reliable")
func rpc_request_weapon_fire(peer_id: int, weapon_slot: int, weapon_key: String, cam_origin: Vector3, cam_forward: Vector3, shot_id: int) -> void:
	if not NetworkSession.is_host():
		return
	if multiplayer.get_remote_sender_id() != peer_id:
		return
	_handle_weapon_fire_request(peer_id, weapon_slot, weapon_key, cam_origin, cam_forward, shot_id)

@rpc("any_peer", "reliable")
func rpc_request_weapon_switch(peer_id: int, weapon_slot: int, weapon_key: String) -> void:
	if not NetworkSession.is_host():
		return
	if multiplayer.get_remote_sender_id() != peer_id:
		return
	_handle_weapon_switch_request(peer_id, weapon_slot, weapon_key)

@rpc("any_peer", "reliable")
func rpc_request_weapon_reload(peer_id: int, weapon_slot: int, weapon_key: String) -> void:
	if not NetworkSession.is_host():
		return
	if multiplayer.get_remote_sender_id() != peer_id:
		return
	_handle_weapon_reload_request(peer_id, weapon_slot, weapon_key)

@rpc("authority", "call_remote", "reliable")
func rpc_sync_weapon_state(peer_id: int, slot_index: int, current_mag: int, ammo_snapshot: Dictionary, weapon_key: String = "") -> void:
	if _get_local_peer_id() != peer_id:
		return
	var local_player = NetworkPlayerManager.get_local_player()
	if not is_instance_valid(local_player):
		return
	var manager: WeaponManager = local_player.get("weapon_manager")
	if manager == null:
		return
	manager.apply_authoritative_weapon_state(slot_index, current_mag, ammo_snapshot, weapon_key)

@rpc("authority", "call_local", "reliable")
func rpc_spawn_projectile_visual(shooter_peer_id: int, scene_path: String, origin: Vector3, cam_forward: Vector3) -> void:
	if shooter_peer_id == _get_local_peer_id():
		return
	var packed := load(scene_path)
	if not (packed is PackedScene):
		return
	var projectile_scene: PackedScene = packed
	var projectile_variant: Variant = projectile_scene.instantiate()
	if not (projectile_variant is Projectile):
		if projectile_variant is Node:
			(projectile_variant as Node).queue_free()
		return
	var projectile: Projectile = projectile_variant
	var spawn_parent := get_tree().current_scene
	if spawn_parent == null:
		projectile.queue_free()
		return
	projectile.network_visual_only = true
	projectile.direction = cam_forward.normalized()
	projectile.monitoring = false
	projectile.monitorable = false
	projectile.collision_layer = 0
	projectile.collision_mask = 0
	spawn_parent.add_child(projectile)
	projectile.add_to_group("network_replicated_projectile_visual")
	_debug_network_visual_counts["projectile"] = int(_debug_network_visual_counts.get("projectile", 0)) + 1
	projectile.global_position = origin + cam_forward.normalized() * 0.6
	if projectile.direction.abs().is_equal_approx(Vector3(0, 1, 0)):
		projectile.look_at(projectile.global_position + projectile.direction, Vector3.RIGHT)
	else:
		projectile.look_at(projectile.global_position + projectile.direction, Vector3.UP)

@rpc("authority", "call_local", "reliable")
func rpc_spawn_weapon_fire_visual(shooter_peer_id: int, muzzle_pos: Vector3) -> void:
	if shooter_peer_id == _get_local_peer_id():
		return
	_spawn_weapon_fire_visual(muzzle_pos)

func _spawn_weapon_fire_visual(muzzle_pos: Vector3) -> void:
	var current_scene := get_tree().current_scene
	if current_scene == null:
		return
	var flash_mesh := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.32, 0.32)
	flash_mesh.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = StandardMaterial3D.BLEND_MODE_ADD
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.albedo_color = Color(1.8, 1.2, 0.4, 0.85)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.65, 0.15, 1.0)
	mat.emission_energy_multiplier = 4.0
	flash_mesh.material_override = mat
	flash_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	current_scene.add_child(flash_mesh)
	flash_mesh.global_position = muzzle_pos
	var flash_light := OmniLight3D.new()
	flash_light.light_color = Color(1.0, 0.72, 0.28, 1.0)
	flash_light.light_energy = 2.4
	flash_light.omni_range = 4.5
	flash_mesh.add_child(flash_light)
	_debug_network_visual_counts["weapon_fire"] = int(_debug_network_visual_counts.get("weapon_fire", 0)) + 1
	await get_tree().create_timer(0.06).timeout
	if is_instance_valid(flash_mesh):
		flash_mesh.queue_free()

@rpc("authority", "call_local", "reliable")
func rpc_spawn_hitscan_visual(shooter_peer_id: int, from: Vector3, to: Vector3) -> void:
	if shooter_peer_id == _get_local_peer_id():
		return
	var length := from.distance_to(to)
	if length <= 0.01:
		return
	var t_mesh := CylinderMesh.new()
	t_mesh.top_radius = 0.01
	t_mesh.bottom_radius = 0.04
	t_mesh.height = length
	t_mesh.radial_segments = 4
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = StandardMaterial3D.BLEND_MODE_ADD
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(2.5, 2.5, 1.0, 0.8)
	var tracer := MeshInstance3D.new()
	tracer.mesh = t_mesh
	tracer.material_override = mat
	tracer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var current_scene := get_tree().current_scene
	if current_scene == null:
		tracer.queue_free()
		return
	current_scene.add_child(tracer)
	tracer.add_to_group("network_replicated_hitscan_visual")
	_debug_network_visual_counts["hitscan"] = int(_debug_network_visual_counts.get("hitscan", 0)) + 1
	tracer.global_position = (from + to) / 2.0
	tracer.look_at(to, Vector3.UP)
	tracer.rotate_object_local(Vector3.RIGHT, -PI / 2.0)
	await get_tree().create_timer(0.05).timeout
	if is_instance_valid(tracer):
		tracer.queue_free()
