extends Node3D
class_name HubManager

@onready var _nav_region: NavigationRegion3D = $NavigationRegion3D

var _entering_dungeon: bool = false

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_configure_chests()
	_connect_portal()
	_bake_nav()
	NetworkPlayerManager.players_ready.connect(_on_players_ready)
	NetworkPlayerManager.setup(_get_spawn_positions())

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

func _restore_player_input() -> void:
	var local := NetworkPlayerManager.get_local_player()
	if is_instance_valid(local) and local.has_method("set_gameplay_input_enabled"):
		local.call("set_gameplay_input_enabled", true)

func _on_dungeon_config_cancelled() -> void:
	_restore_player_input()

func _on_dungeon_config_confirmed(biome: String, grid_min: int, grid_max: int, seed_val: int) -> void:
	_restore_player_input()
	if _entering_dungeon:
		return
	GameState.dungeon_biome_override = biome
	GameState.dungeon_grid_min = grid_min
	GameState.dungeon_grid_max = grid_max
	GameState.dungeon_seed = seed_val

	if NetworkSession.is_multiplayer_active():
		if NetworkSession.is_host():
			_do_enter_dungeon()
		else:
			rpc_id(1, "rpc_hub_request_enter_with_config", biome, grid_min, grid_max, seed_val)
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
func rpc_hub_request_enter_with_config(biome: String, grid_min: int, grid_max: int, seed_val: int) -> void:
	if not NetworkSession.is_host() or _entering_dungeon:
		return
	GameState.dungeon_biome_override = biome
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
