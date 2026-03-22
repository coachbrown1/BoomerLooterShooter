extends Node3D
class_name HubManager

const LOOT_PICKUP_SCENE: PackedScene = preload("res://Scenes/Props/loot_pickup.tscn")

@onready var _nav_region: NavigationRegion3D = $NavigationRegion3D

var _entering_dungeon: bool = false
var _loot_pickup_by_network_id: Dictionary = {}
var _next_loot_pickup_network_id: int = 1
var _war_table_menu: WarTableMenu = null
var _debug_network_visual_counts := {
	"hitscan": 0,
	"projectile": 0,
	"weapon_fire": 0,
}

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	add_to_group("world_item_drop_manager")
	_configure_chests()
	_connect_portal()
	_connect_war_table()
	_bake_nav()
	NetworkPlayerManager.players_ready.connect(_on_players_ready)
	NetworkPlayerManager.setup(_get_spawn_positions())
	_reset_debug_network_visual_counts()

# ─────────────────────────────────────────────────────────────────────────────
# Player spawning — fully delegated to NetworkPlayerManager
# ─────────────────────────────────────────────────────────────────────────────

func _get_spawn_positions() -> Array[Vector3]:
	var positions: Array[Vector3] = []
	for i in range(4):
		var m := get_node_or_null("PlayerSpawn_%d" % i) as Marker3D
		if m != null:
			positions.append(m.global_position)
	return positions

func _on_players_ready(_players: Dictionary) -> void:
	var local := NetworkPlayerManager.get_local_player()
	if not is_instance_valid(local):
		return
	if local.has_node("Head"):
		local.get_node("Head").rotation.x = 0.0
	if GameState.initialized and not GameState.player_inventory_snapshot.is_empty():
		var inv := local.get("inventory_system") as InventorySystem
		if inv != null:
			inv.apply_slot_snapshot(GameState.player_inventory_snapshot)

# ─────────────────────────────────────────────────────────────────────────────
# Chests
# ─────────────────────────────────────────────────────────────────────────────

func _configure_chests() -> void:
	for i in range(3):
		var chest_node = _nav_region.get_node_or_null("HubChest_%d" % i)
		if chest_node == null:
			push_warning("HubManager: HubChest_%d not found in scene." % i)
			continue
		chest_node.add_to_group("hub_chest")
		if "min_gear_items" in chest_node:
			chest_node.set("min_gear_items", 0)
			chest_node.set("max_gear_items", 0)
		if "chest_name" in chest_node:
			chest_node.set("chest_name", "Storage Chest %d" % (i + 1))
		var saved: Array = GameState.hub_chest_snapshots[i] if i < GameState.hub_chest_snapshots.size() else []
		if not saved.is_empty() and chest_node.has_method("set_storage_items"):
			chest_node.set_storage_items(saved)

# ─────────────────────────────────────────────────────────────────────────────
# Portal
# ─────────────────────────────────────────────────────────────────────────────

func _connect_portal() -> void:
	var portal := _nav_region.get_node_or_null("Portal") as Portal
	if portal == null:
		push_warning("HubManager: Portal node not found in NavigationRegion3D.")
		return
	portal.player_interacted.connect(_on_portal_interacted)

func _connect_war_table() -> void:
	for station_variant in get_tree().get_nodes_in_group("war_table_station"):
		if station_variant is WarTableStation:
			var station := station_variant as WarTableStation
			if not station.player_interacted.is_connected(_on_war_table_interacted):
				station.player_interacted.connect(_on_war_table_interacted)

func _on_portal_interacted(body: Node3D) -> void:
	if not body.is_in_group("player") or _entering_dungeon:
		return
	# Only show the menu for the local player.
	var local := NetworkPlayerManager.get_local_player()
	if not is_instance_valid(local) or body != local:
		return
	_show_dungeon_config_menu()

func _show_dungeon_config_menu() -> void:
	var menu := DungeonConfigMenu.new()
	add_child(menu)
	menu.confirmed.connect(_on_dungeon_config_confirmed)
	menu.cancelled.connect(_on_dungeon_config_cancelled)
	var local := NetworkPlayerManager.get_local_player()
	if is_instance_valid(local) and local.has_method("set_gameplay_input_enabled"):
		local.call("set_gameplay_input_enabled", false)

func _on_war_table_interacted(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return
	var local := NetworkPlayerManager.get_local_player()
	if not is_instance_valid(local) or body != local:
		return
	_show_war_table_menu()

func _show_war_table_menu() -> void:
	if is_instance_valid(_war_table_menu):
		return
	_war_table_menu = WarTableMenu.new()
	add_child(_war_table_menu)
	_war_table_menu.closed.connect(_on_war_table_menu_closed)
	var local := NetworkPlayerManager.get_local_player()
	if is_instance_valid(local) and local.has_method("set_gameplay_input_enabled"):
		local.call("set_gameplay_input_enabled", false)

func _on_war_table_menu_closed() -> void:
	_war_table_menu = null
	_restore_player_input()

func _restore_player_input() -> void:
	var local := NetworkPlayerManager.get_local_player()
	if is_instance_valid(local) and local.has_method("set_gameplay_input_enabled"):
		local.call("set_gameplay_input_enabled", true)

func _on_dungeon_config_cancelled() -> void:
	_restore_player_input()

func _on_dungeon_config_confirmed(grid_min: int, grid_max: int, seed_val: int) -> void:
	_restore_player_input()
	if _entering_dungeon:
		return
	GameState.dungeon_grid_min = grid_min
	GameState.dungeon_grid_max = grid_max
	GameState.dungeon_seed = seed_val

	if NetworkSession.is_multiplayer_active():
		if NetworkSession.is_host():
			_do_enter_dungeon()
		else:
			rpc_id(1, "rpc_hub_request_enter_with_config", grid_min, grid_max, seed_val)
	else:
		_do_enter_dungeon()

func _do_enter_dungeon() -> void:
	_entering_dungeon = true
	var local := NetworkPlayerManager.get_local_player()
	if is_instance_valid(local):
		var inv := local.get("inventory_system") as InventorySystem
		if inv != null:
			GameState.player_inventory_snapshot = inv.get_slot_snapshot()
	_save_hub_chests()
	GameState.initialized = true
	if NetworkSession.is_multiplayer_active():
		rpc("rpc_hub_enter_dungeon")
	else:
		get_tree().change_scene_to_file("res://Scenes/World/dungeon.tscn")

@rpc("any_peer", "reliable")
func rpc_hub_request_enter_with_config(grid_min: int, grid_max: int, seed_val: int) -> void:
	if not NetworkSession.is_host() or _entering_dungeon:
		return
	GameState.dungeon_grid_min = grid_min
	GameState.dungeon_grid_max = grid_max
	GameState.dungeon_seed = seed_val
	_do_enter_dungeon()

@rpc("authority", "call_local", "reliable")
func rpc_hub_enter_dungeon() -> void:
	get_tree().call_deferred("change_scene_to_file", "res://Scenes/World/dungeon.tscn")

func _save_hub_chests() -> void:
	for chest_variant in get_tree().get_nodes_in_group("hub_chest"):
		var i := int(chest_variant.name.get_slice("_", 2))
		if i < GameState.hub_chest_snapshots.size() and chest_variant.has_method("get_storage_payload"):
			GameState.hub_chest_snapshots[i] = chest_variant.call("get_storage_payload")

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

func request_interaction(interactor: Node, target: Node) -> void:
	if target == null:
		return
	if not NetworkSession.is_multiplayer_active() or NetworkSession.is_host():
		_apply_loot_interaction(interactor, target)
		return
	var target_pos := Vector3.ZERO
	if target is Node3D:
		target_pos = (target as Node3D).global_position
	rpc_id(1, "rpc_request_loot_interaction", NetworkSession.get_local_peer_id(), String(target.get_path()), target_pos)

func request_drop_inventory_item(peer_id: int, slot_payload: Dictionary, drop_origin: Vector3, launch_direction: Vector3) -> void:
	if not NetworkSession.is_multiplayer_active() or NetworkSession.is_host():
		_handle_drop_inventory_item_request(peer_id, slot_payload, drop_origin, launch_direction)
		return
	rpc_id(1, "rpc_request_drop_inventory_item", peer_id, slot_payload, drop_origin, launch_direction)

func spawn_network_item_pickup(item_payload: Dictionary, drop_origin: Vector3, launch_direction: Vector3) -> void:
	if NetworkSession.is_multiplayer_active() and not NetworkSession.is_host():
		return
	var payload := {
		"kind": "item",
		"item_data": item_payload.duplicate(true),
		"drop_origin": drop_origin,
		"launch_direction": launch_direction,
	}
	_spawn_network_loot_pickup(payload, true)

func _apply_loot_interaction(interactor: Node, target: Node) -> void:
	var resolved_target := _resolve_loot_interaction_target(target)
	if not (resolved_target is LootPickup):
		return
	var pickup := resolved_target as LootPickup
	var loot_id := int(pickup.get_meta("network_loot_id", -1))
	var interactor_peer := NetworkSession.get_local_peer_id() if NetworkSession.is_multiplayer_active() else 0
	if interactor != null and interactor.has_method("get_network_peer_id"):
		interactor_peer = int(interactor.call("get_network_peer_id"))
	pickup.interact(interactor)
	if NetworkSession.is_multiplayer_active() and NetworkSession.is_host() and interactor_peer != NetworkSession.get_local_peer_id():
		_sync_pickup_state_to_peer(interactor_peer, interactor)
	if loot_id >= 0 and (not is_instance_valid(pickup) or pickup.is_queued_for_deletion()):
		_loot_pickup_by_network_id.erase(loot_id)
		if NetworkSession.is_multiplayer_active() and NetworkSession.is_host():
			rpc("rpc_despawn_loot_pickup", loot_id)

func _resolve_loot_interaction_target(target: Node) -> Node:
	var current := target
	while current != null:
		if current is LootPickup:
			return current
		current = current.get_parent()
	return null

func _find_loot_pickup_by_position(world_pos: Vector3, max_distance: float = 2.0) -> LootPickup:
	var closest: LootPickup = null
	var closest_dist_sq := max_distance * max_distance
	for pickup_variant in get_tree().get_nodes_in_group("loot_pickup"):
		if not (pickup_variant is LootPickup):
			continue
		var pickup: LootPickup = pickup_variant
		if not is_instance_valid(pickup):
			continue
		var dist_sq := pickup.global_position.distance_squared_to(world_pos)
		if dist_sq <= closest_dist_sq:
			closest = pickup
			closest_dist_sq = dist_sq
	return closest

func _spawn_network_loot_pickup(payload: Dictionary, play_launch: bool) -> void:
	var pickup := _instantiate_loot_pickup_from_payload(payload, play_launch)
	if pickup == null:
		return
	var loot_id := _register_network_loot_pickup(pickup)
	var sync_payload := _build_loot_pickup_payload(pickup)
	if NetworkSession.is_multiplayer_active() and NetworkSession.is_host():
		for peer_id in NetworkSession.get_connected_peer_ids():
			rpc_id(peer_id, "rpc_spawn_loot_pickup", loot_id, sync_payload, play_launch)

func _instantiate_loot_pickup_from_payload(payload: Dictionary, play_launch: bool) -> LootPickup:
	var pickup_variant: Variant = LOOT_PICKUP_SCENE.instantiate()
	if not (pickup_variant is LootPickup):
		if pickup_variant is Node:
			(pickup_variant as Node).queue_free()
		return null
	var pickup: LootPickup = pickup_variant
	var item_payload: Dictionary = payload.get("item_data", {})
	var item_data := InventoryItemData.from_dict(item_payload)
	if item_data == null:
		pickup.queue_free()
		return null
	pickup.configure_item_pickup(item_data)
	var scene_root := get_tree().current_scene
	if scene_root == null:
		pickup.queue_free()
		return null
	scene_root.add_child(pickup)
	if play_launch:
		pickup.launch(
			payload.get("drop_origin", Vector3.ZERO),
			payload.get("launch_direction", Vector3.ZERO)
		)
	else:
		pickup.settle_at(payload.get("settled_position", Vector3.ZERO))
	return pickup

func _register_network_loot_pickup(pickup: LootPickup, forced_loot_id: int = -1) -> int:
	if pickup == null:
		return -1
	var loot_id := forced_loot_id
	if loot_id < 0:
		loot_id = _next_loot_pickup_network_id
		_next_loot_pickup_network_id += 1
	else:
		_next_loot_pickup_network_id = maxi(_next_loot_pickup_network_id, loot_id + 1)
	_loot_pickup_by_network_id[loot_id] = pickup
	pickup.set_meta("network_loot_id", loot_id)
	pickup.name = "HubLootPickup_%d" % loot_id
	return loot_id

func _build_loot_pickup_payload(pickup: LootPickup) -> Dictionary:
	if pickup == null:
		return {}
	return {
		"kind": "item",
		"item_data": pickup.get_item_snapshot(),
		"drop_origin": pickup.global_position,
		"launch_direction": Vector3.ZERO,
		"settled_position": pickup.global_position,
	}

func _find_new_inventory_item_name(previous_snapshot: Dictionary, current_snapshot: Dictionary) -> String:
	for section_key in ["storage", "weapons", "equipment"]:
		var previous_section: Variant = previous_snapshot.get(section_key, [] if section_key != "equipment" else {})
		var current_section: Variant = current_snapshot.get(section_key, [] if section_key != "equipment" else {})
		if section_key == "equipment":
			for slot_key_variant in current_section.keys():
				var slot_key := String(slot_key_variant)
				var previous_item = previous_section.get(slot_key, null)
				var current_item = current_section.get(slot_key, null)
				if previous_item == null and current_item != null:
					return String(current_item.get("display_name", "Item"))
			continue
		var previous_array: Array = previous_section
		var current_array: Array = current_section
		for i in range(current_array.size()):
			var previous_item = previous_array[i] if i < previous_array.size() else null
			var current_item = current_array[i]
			if previous_item == null and current_item != null:
				return String(current_item.get("display_name", "Item"))
	return ""

func _emit_pickup_sync_feedback(local_player: Node, previous_inventory_snapshot: Dictionary, current_inventory_snapshot: Dictionary, previous_health: int, current_health: int, previous_ammo_snapshot: Dictionary, current_ammo_snapshot: Dictionary) -> void:
	if local_player == null or not local_player.has_method("show_hud_toast"):
		return
	if current_health > previous_health:
		local_player.call("show_hud_toast", "+%d Health" % (current_health - previous_health), "health")
	for ammo_type_variant in current_ammo_snapshot.keys():
		var ammo_type := String(ammo_type_variant)
		var previous_amount := int(previous_ammo_snapshot.get(ammo_type, 0))
		var current_amount := int(current_ammo_snapshot.get(ammo_type, previous_amount))
		if current_amount > previous_amount:
			local_player.call("show_hud_toast", "+%d %s" % [current_amount - previous_amount, _get_ammo_pickup_toast_name(ammo_type)], ammo_type)
	var item_name := _find_new_inventory_item_name(previous_inventory_snapshot, current_inventory_snapshot)
	if not item_name.is_empty():
		local_player.call("show_hud_toast", "Picked up %s" % item_name, "loot")

func _get_ammo_pickup_toast_name(ammo_type: String) -> String:
	match ammo_type:
		"light":
			return "Rifle Ammo"
		"shells":
			return "Shotgun Shells"
		"energy":
			return "Energy Cells"
		"arrows":
			return "Bolts"
		_:
			return "%s Ammo" % ammo_type.capitalize()

func _sync_pickup_state_to_peer(peer_id: int, interactor: Node) -> void:
	if peer_id <= 0 or not NetworkSession.is_multiplayer_active() or not NetworkSession.is_host():
		return
	if interactor == null:
		return
	var inventory_snapshot := {}
	var inventory_system: InventorySystem = interactor.get("inventory_system") as InventorySystem
	if inventory_system != null:
		inventory_snapshot = inventory_system.get_slot_snapshot()
	var health := -1
	if interactor.has_method("apply_authoritative_health") or interactor.has_method("heal"):
		health = int(interactor.get("current_health"))
	var weapon_slot := -1
	var current_mag := -1
	var ammo_snapshot := {}
	var weapon_key := ""
	var weapon_manager: WeaponManager = interactor.get("weapon_manager") as WeaponManager
	if weapon_manager != null:
		weapon_slot = weapon_manager.get_current_weapon_slot()
		var weapon := weapon_manager.get_current_weapon()
		current_mag = weapon.current_mag if weapon != null else -1
		ammo_snapshot = weapon_manager.get_ammo_snapshot()
		weapon_key = weapon_manager.get_current_weapon_key()
	rpc_id(peer_id, "rpc_sync_pickup_state", peer_id, inventory_snapshot, health, weapon_slot, current_mag, ammo_snapshot, weapon_key)

func _handle_drop_inventory_item_request(peer_id: int, slot_payload: Dictionary, drop_origin: Vector3, launch_direction: Vector3) -> void:
	var player := NetworkPlayerManager.get_player(peer_id)
	if not is_instance_valid(player):
		return
	var inventory_system: InventorySystem = player.get("inventory_system") as InventorySystem
	if inventory_system == null:
		return
	var slot_ref: SlotRef = inventory_system.call("_slot_ref_from_payload", slot_payload)
	if slot_ref == null:
		return
	var show_toast := not NetworkSession.is_multiplayer_active() or peer_id == NetworkSession.get_local_peer_id()
	var dropped: bool = bool(inventory_system.call("_drop_item_to_world", slot_ref, drop_origin, launch_direction, show_toast))
	if not dropped:
		return
	if NetworkSession.is_multiplayer_active() and NetworkSession.is_host() and peer_id != NetworkSession.get_local_peer_id():
		_sync_pickup_state_to_peer(peer_id, player)

@rpc("authority", "call_remote", "reliable")
func rpc_spawn_loot_pickup(loot_id: int, payload: Dictionary, play_launch: bool = true) -> void:
	if NetworkSession.is_host():
		return
	var existing = _loot_pickup_by_network_id.get(loot_id, null)
	if is_instance_valid(existing):
		existing.queue_free()
	_loot_pickup_by_network_id.erase(loot_id)
	var pickup := _instantiate_loot_pickup_from_payload(payload, play_launch)
	if pickup == null:
		return
	_register_network_loot_pickup(pickup, loot_id)

@rpc("authority", "call_remote", "reliable")
func rpc_despawn_loot_pickup(loot_id: int) -> void:
	var pickup = _loot_pickup_by_network_id.get(loot_id, null)
	if is_instance_valid(pickup):
		pickup.queue_free()
	_loot_pickup_by_network_id.erase(loot_id)

@rpc("authority", "call_remote", "reliable")
func rpc_sync_pickup_state(peer_id: int, inventory_snapshot: Dictionary, health: int, weapon_slot: int, current_mag: int, ammo_snapshot: Dictionary, weapon_key: String = "") -> void:
	if NetworkSession.get_local_peer_id() != peer_id:
		return
	var local_player = NetworkPlayerManager.get_local_player()
	if not is_instance_valid(local_player):
		return
	var inventory_system: InventorySystem = local_player.get("inventory_system") as InventorySystem
	var previous_inventory_snapshot := inventory_system.get_slot_snapshot() if inventory_system != null else {}
	var previous_health := int(local_player.get("current_health"))
	var previous_ammo_snapshot := {}
	var previous_manager: WeaponManager = local_player.get("weapon_manager")
	if previous_manager != null:
		previous_ammo_snapshot = previous_manager.get_ammo_snapshot()
	if inventory_system != null and not inventory_snapshot.is_empty():
		inventory_system.apply_slot_snapshot(inventory_snapshot)
	if health >= 0 and local_player.has_method("apply_authoritative_health"):
		local_player.call("apply_authoritative_health", health)
	var manager: WeaponManager = local_player.get("weapon_manager")
	if manager != null and not ammo_snapshot.is_empty():
		manager.apply_authoritative_weapon_state(weapon_slot, current_mag, ammo_snapshot, weapon_key)
	_emit_pickup_sync_feedback(local_player, previous_inventory_snapshot, inventory_snapshot, previous_health, health, previous_ammo_snapshot, ammo_snapshot)

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
	if NetworkSession.get_local_peer_id() != peer_id:
		return
	var local_player = NetworkPlayerManager.get_local_player()
	if not is_instance_valid(local_player):
		return
	var manager: WeaponManager = local_player.get("weapon_manager")
	if manager == null:
		return
	manager.apply_authoritative_weapon_state(slot_index, current_mag, ammo_snapshot, weapon_key)

@rpc("any_peer", "reliable")
func rpc_request_loot_interaction(peer_id: int, target_path: String, target_pos: Vector3 = Vector3.ZERO) -> void:
	if not NetworkSession.is_host():
		return
	if multiplayer.get_remote_sender_id() != peer_id:
		return
	var interactor = NetworkPlayerManager.get_player(peer_id)
	var target := get_node_or_null(NodePath(target_path))
	target = _resolve_loot_interaction_target(target)
	if target == null:
		target = _find_loot_pickup_by_position(target_pos)
	if target == null:
		return
	_apply_loot_interaction(interactor, target)

@rpc("any_peer", "reliable")
func rpc_request_drop_inventory_item(peer_id: int, slot_payload: Dictionary, drop_origin: Vector3, launch_direction: Vector3) -> void:
	if not NetworkSession.is_host():
		return
	if multiplayer.get_remote_sender_id() != peer_id:
		return
	_handle_drop_inventory_item_request(peer_id, slot_payload, drop_origin, launch_direction)

@rpc("authority", "call_local", "reliable")
func rpc_spawn_projectile_visual(shooter_peer_id: int, scene_path: String, origin: Vector3, cam_forward: Vector3) -> void:
	if shooter_peer_id == NetworkSession.get_local_peer_id():
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
	if shooter_peer_id == NetworkSession.get_local_peer_id():
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
	if shooter_peer_id == NetworkSession.get_local_peer_id():
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
	get_tree().current_scene.add_child(tracer)
	tracer.global_position = (from + to) / 2.0
	if length > 0.01:
		tracer.look_at(to, Vector3.UP)
		tracer.rotate_object_local(Vector3.RIGHT, -PI / 2.0)
	_debug_network_visual_counts["hitscan"] = int(_debug_network_visual_counts.get("hitscan", 0)) + 1
	await get_tree().create_timer(0.05).timeout
	if is_instance_valid(tracer):
		tracer.queue_free()

func _reset_debug_network_visual_counts() -> void:
	_debug_network_visual_counts["hitscan"] = 0
	_debug_network_visual_counts["projectile"] = 0
	_debug_network_visual_counts["weapon_fire"] = 0

func get_debug_network_visual_counts() -> Dictionary:
	return _debug_network_visual_counts.duplicate(true)

# ─────────────────────────────────────────────────────────────────────────────
# Navigation
# ─────────────────────────────────────────────────────────────────────────────

func _bake_nav() -> void:
	var nav_mesh := NavigationMesh.new()
	nav_mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nav_mesh.cell_size   = 0.25
	nav_mesh.cell_height = 0.25
	nav_mesh.agent_height    = 1.8
	nav_mesh.agent_radius    = 0.4
	nav_mesh.agent_max_climb = 0.3
	nav_mesh.filter_walkable_low_height_spans = true
	_nav_region.navigation_mesh = nav_mesh
	await get_tree().process_frame
	_nav_region.bake_navigation_mesh(false)
