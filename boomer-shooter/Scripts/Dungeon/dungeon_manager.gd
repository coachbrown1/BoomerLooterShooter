@tool
extends Node3D
class_name DungeonManager

@export var floor_number: int = 1
@export var biome_database: Resource = preload("res://Data/biomes/biome_dungeon_database.tres")

# Lattice generation config
@export var grid_size_min: int = 10
@export var grid_size_max: int = 10
@export var min_start_end_distance_rooms: int = 3
@export var room_size_tiles: int = 20
@export var corridor_width_tiles: int = 4
@export var corridor_length_tiles: int = 10
@export var generation_seed: int = 0

@onready var nav_region: NavigationRegion3D = $NavigationRegion3D

const PLAYER_SCENE: PackedScene = preload("res://Scenes/Player/player.tscn")
const SNAPSHOT_INTERVAL: float = 0.05

var _generator: DungeonGenerator
var _builder: DungeonBuilder
var _encounter: EncounterSystem
var _rooms: Array = []
var _active_biome_data: Resource = null
var _room_lookup := {}
var _spawned_enemy_rooms := {}
var _last_player_room_id: int = -1

var _cached_player: Node3D = null
var _session_multiplayer: bool = false
var _session_host: bool = false
var _local_peer_id: int = 1
var _snapshot_timer: float = 0.0
var _local_player_state_timer: float = 0.0
var _player_by_peer_id: Dictionary = {}
var _enemy_by_network_id: Dictionary = {}
var _enemy_network_id_by_instance_id: Dictionary = {}
var _next_enemy_network_id: int = 1
var _player_spawn_points_by_peer: Dictionary = {}
var _chest_viewers_by_path: Dictionary = {}
var _leave_session_ui: CanvasLayer = null
var _floor_sync_in_progress := false
var _floor_sync_ready_by_peer: Dictionary = {}
var _pending_player_roster: Array = []
var _pending_enemy_spawns: Array = []

func _ready() -> void:
	add_to_group("dungeon_manager")
	if Engine.is_editor_hint():
		set_process(false)
		return

	_session_multiplayer = _is_network_multiplayer_active()
	_session_host = not _session_multiplayer or _is_network_host()
	_local_peer_id = _get_network_local_peer_id()
	_bind_network_signals()
	_prepare_player_nodes()
	if _session_multiplayer:
		_build_leave_session_ui()

	set_process(true)
	if _session_multiplayer and not _session_host:
		_remove_non_local_player_nodes()
		return

	generate_floor(floor_number)
	if _session_multiplayer and _session_host:
		_sync_floor_to_clients()
		_spawn_missing_network_players()

func _process(delta: float) -> void:
	if _session_multiplayer:
		if _session_host:
			_snapshot_timer += delta
			if _snapshot_timer >= SNAPSHOT_INTERVAL:
				_snapshot_timer = 0.0
				_broadcast_player_snapshots()
				_broadcast_enemy_snapshots()
		else:
			_local_player_state_timer += delta
			if _local_player_state_timer >= SNAPSHOT_INTERVAL:
				_local_player_state_timer = 0.0
				_send_local_player_snapshot_to_host()

	if _encounter == null or _rooms.is_empty():
		return

	if not _session_host:
		return

	var active_player := _get_authoritative_progress_player()
	if not is_instance_valid(active_player):
		return

	var room_id := _find_room_id_for_world_position(active_player.global_position)
	if room_id < 0 or room_id == _last_player_room_id:
		return

	_last_player_room_id = room_id
	_spawn_room_and_adjacent(room_id)

func generate_floor(floor_num: int, preview_mode: bool = false) -> void:
	floor_number = floor_num
	_floor_sync_in_progress = true

	# Clear old geometry + entities under nav region.
	for child in nav_region.get_children():
		child.queue_free()

	_room_lookup = {}
	_spawned_enemy_rooms = {}
	_last_player_room_id = -1
	_active_biome_data = null
	_chest_viewers_by_path.clear()
	_enemy_by_network_id.clear()
	_enemy_network_id_by_instance_id.clear()

	# Generate tile layout
	_generator = DungeonGenerator.new()
	_generator.grid_size_min = grid_size_min
	_generator.grid_size_max = grid_size_max
	_generator.min_start_end_distance_rooms = min_start_end_distance_rooms
	_generator.room_size_tiles = room_size_tiles
	_generator.corridor_width_tiles = corridor_width_tiles
	_generator.corridor_length_tiles = corridor_length_tiles
	_generator.generate(floor_num, generation_seed)
	generation_seed = int(_generator.rng.seed)
	_rooms = _generator.rooms

	var biome_id := "crypt"
	if _rooms.size() > 0:
		biome_id = _rooms[0].biome
	var biome_data = _get_biome_data(biome_id)
	_active_biome_data = biome_data
	_assign_handcrafted_layouts(biome_data)

	_update_environment(biome_data)

	# Build 3D geometry inside the NavigationRegion3D
	_builder = DungeonBuilder.new()
	_builder.build(_generator.tile_grid, _rooms, _generator.corridors, _generator.doorways, nav_region, biome_data)
	_spawn_handcrafted_room_overlays(nav_region)

	# Place props (static, not streamed)
	var prop_placer = PropPlacer.new()
	prop_placer.populate(nav_region, _rooms, _generator.tile_grid, _generator.rng, biome_data)

	# Bake navigation mesh
	var nav_mesh := NavigationMesh.new()
	nav_mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nav_mesh.cell_size = 0.25
	nav_mesh.cell_height = 0.25
	nav_mesh.agent_height = 1.8
	nav_mesh.agent_radius = 0.4
	nav_mesh.agent_max_climb = 0.3
	nav_mesh.filter_walkable_low_height_spans = true
	nav_region.navigation_mesh = nav_mesh

	# Wait a frame for physics to settle before baking
	await get_tree().process_frame
	nav_region.bake_navigation_mesh(false)
	await get_tree().physics_frame

	if preview_mode:
		_build_room_lookup()
		_encounter = null
		_floor_sync_in_progress = false
		print(
			"DungeonManager: Preview generated for floor %d with %d rooms (grid=%dx%d seed=%d)." % [
				floor_num,
				_rooms.size(),
				_generator.sampled_grid_size,
				_generator.sampled_grid_size,
				generation_seed,
			]
		)
		return

	_build_room_lookup()
	var host_authoritative_world := not _session_multiplayer or _session_host
	if host_authoritative_world:
		_encounter = EncounterSystem.new()
		if _session_multiplayer:
			_enemy_by_network_id.clear()
			_enemy_network_id_by_instance_id.clear()
			_next_enemy_network_id = 1

		# Place player at start room
		_place_player()

		# Place exit portal in exit room
		_place_exit(biome_data)

		# Spawn only the start-room neighborhood; expand as player progresses.
		_prime_progressive_enemy_spawning()
	else:
		_encounter = null
		_place_exit(biome_data)

	print(
		"DungeonManager: Floor %d generated with %d rooms (grid=%dx%d seed=%d)." % [
			floor_num,
			_rooms.size(),
			_generator.sampled_grid_size,
			_generator.sampled_grid_size,
			generation_seed,
		]
	)
	_floor_sync_in_progress = false
	_apply_pending_network_sync()

func clear_editor_preview() -> void:
	for child in nav_region.get_children():
		child.queue_free()
	_rooms = []
	_room_lookup = {}
	_spawned_enemy_rooms = {}
	_last_player_room_id = -1
	_encounter = null

func get_editor_preview_room_targets() -> Array:
	var targets: Array = []
	for room_variant in _rooms:
		var room: RoomData = room_variant
		if room == null:
			continue
		var is_start := room.room_type == RoomData.RoomType.START
		var is_exit := room.room_type == RoomData.RoomType.EXIT
		var include := is_start or is_exit or room.has_handcrafted_layout
		if not include:
			continue

		var type_name := _room_type_name(room.room_type)
		var handcrafted_tag := " [custom]" if room.has_handcrafted_layout else ""
		var label := "%s%s | room %d | lattice (%d,%d)" % [
			type_name,
			handcrafted_tag,
			room.id,
			room.lattice_coord.x,
			room.lattice_coord.y,
		]
		targets.append({
			"id": room.id,
			"label": label,
			"room_type": int(room.room_type),
			"lattice_coord": room.lattice_coord,
			"world_position": room.get_world_center(DungeonBuilder.TILE_SIZE),
			"is_handcrafted": room.has_handcrafted_layout,
			"handcrafted_scene_path": room.handcrafted_scene_path,
		})

	targets.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_priority := _room_type_priority(int(a.get("room_type", RoomData.RoomType.NORMAL)))
		var b_priority := _room_type_priority(int(b.get("room_type", RoomData.RoomType.NORMAL)))
		if a_priority == b_priority:
			return int(a.get("id", 0)) < int(b.get("id", 0))
		return a_priority < b_priority
	)

	return targets

func _room_type_name(room_type: int) -> String:
	match room_type:
		RoomData.RoomType.START:
			return "START"
		RoomData.RoomType.EXIT:
			return "EXIT"
		RoomData.RoomType.SPECIAL:
			return "SPECIAL"
		_:
			return "NORMAL"

func _room_type_priority(room_type: int) -> int:
	match room_type:
		RoomData.RoomType.START:
			return 0
		RoomData.RoomType.EXIT:
			return 1
		_:
			return 2

func _update_environment(biome_data: Resource = null) -> void:
	if _rooms.size() == 0:
		return

	var env = $WorldEnvironment.environment
	if not env:
		return
	var biome = _rooms[0].biome
	if biome_data and biome_data.has_method("get"):
		var fog_color: Variant = biome_data.get("fog_light_color")
		if typeof(fog_color) == TYPE_COLOR:
			env.fog_light_color = fog_color
			return
	if biome == "crypt":
		env.fog_light_color = Color(0.05, 0.03, 0.08)
	elif biome == "fungal":
		env.fog_light_color = Color(0.02, 0.06, 0.03)
	elif biome == "lava":
		env.fog_light_color = Color(0.08, 0.02, 0.01)

func _place_player() -> void:
	var start_room := _get_room_by_type(RoomData.RoomType.START)
	if start_room == null:
		return
	var base_pos := start_room.get_world_center(DungeonBuilder.TILE_SIZE)
	base_pos.y = 1.0

	if not _session_multiplayer:
		if not is_instance_valid(_cached_player):
			_cached_player = get_tree().get_first_node_in_group("player") as Node3D
		if is_instance_valid(_cached_player):
			_cached_player.global_position = base_pos
		return

	if not _session_host:
		return

	_player_spawn_points_by_peer.clear()
	var peer_ids := _player_by_peer_id.keys()
	peer_ids.sort()
	var index := 0
	for peer_key in peer_ids:
		var peer_id := int(peer_key)
		var player_node = _player_by_peer_id.get(peer_id, null)
		if not is_instance_valid(player_node):
			continue
		var spawn_pos := _offset_spawn_position(base_pos, index)
		player_node.global_position = spawn_pos
		_player_spawn_points_by_peer[peer_id] = spawn_pos
		index += 1

func _place_exit(biome_data: Resource = null) -> void:
	var exit_room := _get_room_by_type(RoomData.RoomType.EXIT)
	if exit_room == null:
		return

	# Load and instance the exit portal scene
	var portal_tex: Texture2D = preload("res://Assets/Environment/exit_portal.png")
	if biome_data and biome_data.has_method("get"):
		var candidate: Variant = biome_data.get("exit_portal_texture")
		if candidate is Texture2D:
			portal_tex = candidate
	if portal_tex == null:
		return

	var portal_body := Area3D.new()
	portal_body.name = "ExitPortal"
	var col := CollisionShape3D.new()
	col.shape = SphereShape3D.new()
	col.shape.radius = 1.5
	portal_body.add_child(col)

	var sprite := Sprite3D.new()
	sprite.texture = portal_tex
	sprite.pixel_size = 0.006
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	portal_body.add_child(sprite)

	var pos = exit_room.get_world_center(DungeonBuilder.TILE_SIZE)
	pos.y = 1.2
	nav_region.add_child(portal_body)
	portal_body.global_position = pos
	portal_body.body_entered.connect(_on_exit_entered)

func _on_exit_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		if _session_multiplayer and not _session_host:
			return

		# Emit global event for floor completion before advancing
		if has_node("/root/GlobalEventBus"):
			var event_bus = get_node("/root/GlobalEventBus")
			if event_bus.has_signal("floor_completed"):
				event_bus.emit_signal("floor_completed", floor_number)

		floor_number += 1
		print("Descending to floor %d..." % floor_number)
		generate_floor(floor_number)
		if _session_multiplayer and _session_host:
			_sync_floor_to_clients()

func _get_biome_data(biome_id: String) -> Resource:
	if biome_database == null:
		return null
	if biome_database.has_method("get_biome"):
		return biome_database.call("get_biome", biome_id)
	return null

func _build_room_lookup() -> void:
	_room_lookup = {}
	for room_variant in _rooms:
		var room: RoomData = room_variant
		_room_lookup[room.id] = room

func _get_room_by_type(room_type: int) -> RoomData:
	for room_variant in _rooms:
		var room: RoomData = room_variant
		if room.room_type == room_type:
			return room
	return null

func _assign_handcrafted_layouts(biome_data: Resource = null) -> void:
	for room_variant in _rooms:
		var room: RoomData = room_variant
		room.has_handcrafted_layout = false
		room.handcrafted_scene = null
		room.handcrafted_scene_path = ""

	if biome_data == null:
		return

	var biome_id := ""
	if _resource_has_property(biome_data, "biome_id"):
		biome_id = str(biome_data.get("biome_id"))

	var start_scene: PackedScene = null
	if _resource_has_property(biome_data, "handcrafted_start_room_scene"):
		var start_scene_variant: Variant = biome_data.get("handcrafted_start_room_scene")
		if start_scene_variant is PackedScene:
			start_scene = start_scene_variant

	if start_scene != null:
		var start_room := _get_room_by_type(RoomData.RoomType.START)
		_assign_handcrafted_scene_to_room(start_room, start_scene)
	else:
		push_warning("DungeonManager: biome '%s' has no handcrafted_start_room_scene; start room will be procedural." % biome_id)

	var chance := 0.25
	if _resource_has_property(biome_data, "handcrafted_normal_room_chance"):
		chance = clampf(float(biome_data.get("handcrafted_normal_room_chance")), 0.0, 1.0)
	if chance <= 0.0:
		return

	var normal_scene_pool: Array[PackedScene] = []
	if _resource_has_property(biome_data, "handcrafted_normal_room_scenes"):
		var normal_scene_variant: Variant = biome_data.get("handcrafted_normal_room_scenes")
		if typeof(normal_scene_variant) == TYPE_ARRAY:
			for scene_variant in normal_scene_variant:
				if scene_variant is PackedScene:
					normal_scene_pool.append(scene_variant)

	if normal_scene_pool.is_empty():
		return

	for room_variant in _rooms:
		var room: RoomData = room_variant
		if room.room_type != RoomData.RoomType.NORMAL:
			continue
		if _generator == null or _generator.rng == null:
			continue
		if _generator.rng.randf() >= chance:
			continue
		var scene: PackedScene = normal_scene_pool[_generator.rng.randi() % normal_scene_pool.size()]
		_assign_handcrafted_scene_to_room(room, scene)

func _assign_handcrafted_scene_to_room(room: RoomData, scene: PackedScene) -> void:
	if room == null or scene == null:
		return
	room.has_handcrafted_layout = true
	room.handcrafted_scene = scene
	room.handcrafted_scene_path = scene.resource_path

func _spawn_handcrafted_room_overlays(parent: Node3D) -> void:
	if parent == null:
		return

	var root := Node3D.new()
	root.name = "HandcraftedRooms"
	parent.add_child(root)

	for room_variant in _rooms:
		var room: RoomData = room_variant
		if not room.has_handcrafted_layout:
			continue
		if room.handcrafted_scene == null:
			continue

		var inst := room.handcrafted_scene.instantiate()
		if inst == null:
			push_warning("DungeonManager: failed to instantiate handcrafted room scene for room %d." % room.id)
			continue
		if not (inst is Node3D):
			push_warning(
				"DungeonManager: handcrafted scene '%s' is not a Node3D root; skipping room %d."
				% [room.handcrafted_scene_path, room.id]
			)
			inst.free()
			continue

		var room_overlay: Node3D = inst
		room_overlay.position = room.get_world_center(DungeonBuilder.TILE_SIZE)
		room_overlay.position.y = 0.0
		room_overlay.set_meta("room_id", room.id)
		room_overlay.set_meta("room_type", room.room_type)
		room_overlay.set_meta("lattice_coord", room.lattice_coord)
		root.add_child(room_overlay)

func _resource_has_property(resource: Resource, property_name: String) -> bool:
	if resource == null:
		return false
	for property_variant in resource.get_property_list():
		if typeof(property_variant) != TYPE_DICTIONARY:
			continue
		var property_dict: Dictionary = property_variant
		if str(property_dict.get("name", "")) == property_name:
			return true
	return false

func _prime_progressive_enemy_spawning() -> void:
	if _encounter == null:
		return
	var start_room := _get_room_by_type(RoomData.RoomType.START)
	if start_room == null:
		return
	_last_player_room_id = start_room.id
	_spawn_room_and_adjacent(start_room.id)

func _spawn_room_and_adjacent(room_id: int) -> void:
	_spawn_room_once(room_id)
	var room: RoomData = _room_lookup.get(room_id, null)
	if room == null:
		return
	for neighbor_variant in room.connected_to:
		_spawn_room_once(int(neighbor_variant))

func _spawn_room_once(room_id: int) -> void:
	if _spawned_enemy_rooms.has(room_id):
		return
	var room: RoomData = _room_lookup.get(room_id, null)
	if room == null:
		return
	_spawned_enemy_rooms[room_id] = true
	var spawned_enemies: Array = _encounter.populate_room(room, floor_number, nav_region, _active_biome_data)
	if not _session_multiplayer or not _session_host:
		return
	for enemy_variant in spawned_enemies:
		if not (enemy_variant is EnemyBase):
			continue
		var enemy: EnemyBase = enemy_variant
		_register_network_enemy(enemy)

func _find_room_id_for_world_position(world_pos: Vector3) -> int:
	var tx := int(floor(world_pos.x / DungeonBuilder.TILE_SIZE))
	var tz := int(floor(world_pos.z / DungeonBuilder.TILE_SIZE))
	for room_variant in _rooms:
		var room: RoomData = room_variant
		var rect: Rect2i = room.grid_rect
		if tx >= rect.position.x and tx < rect.position.x + rect.size.x and tz >= rect.position.y and tz < rect.position.y + rect.size.y:
			return room.id
	return -1

func get_room_id_for_world_position(world_pos: Vector3) -> int:
	return _find_room_id_for_world_position(world_pos)

func _bind_network_signals() -> void:
	if not _session_multiplayer:
		return
	var session = _get_network_session()
	if session == null:
		push_warning("DungeonManager: NetworkSession autoload missing.")
		return
	var joined_cb := Callable(self, "_on_network_peer_joined")
	if not session.is_connected("peer_joined", joined_cb):
		session.connect("peer_joined", joined_cb)
	var left_cb := Callable(self, "_on_network_peer_left")
	if not session.is_connected("peer_left", left_cb):
		session.connect("peer_left", left_cb)
	var ended_cb := Callable(self, "_on_network_session_ended")
	if not session.is_connected("session_ended", ended_cb):
		session.connect("session_ended", ended_cb)

func _build_leave_session_ui() -> void:
	if _leave_session_ui != null:
		return
	_leave_session_ui = CanvasLayer.new()
	_leave_session_ui.layer = 20
	add_child(_leave_session_ui)

	var leave_button := Button.new()
	leave_button.text = "Leave Session"
	leave_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	leave_button.anchor_left = 1.0
	leave_button.anchor_right = 1.0
	leave_button.anchor_top = 0.0
	leave_button.anchor_bottom = 0.0
	leave_button.offset_left = -170.0
	leave_button.offset_right = -20.0
	leave_button.offset_top = 20.0
	leave_button.offset_bottom = 56.0
	leave_button.pressed.connect(_leave_current_session)
	_leave_session_ui.add_child(leave_button)

func _leave_current_session() -> void:
	_leave_network_game()

func _prepare_player_nodes() -> void:
	_player_by_peer_id.clear()
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return

	if not _session_multiplayer:
		var player_node := players[0]
		if player_node is Node3D:
			_register_player_node(_local_peer_id, player_node)
		return

	if _session_host:
		var host_player := players[0]
		if host_player is Node3D:
			_register_player_node(_local_peer_id, host_player)
	else:
		for player_variant in players:
			if player_variant is Node3D:
				player_variant.queue_free()

func _remove_non_local_player_nodes() -> void:
	for player_variant in get_tree().get_nodes_in_group("player"):
		if not (player_variant is Node3D):
			continue
		var player_node: Node3D = player_variant
		player_node.queue_free()
	_player_by_peer_id.clear()
	_cached_player = null
	call_deferred("_request_host_sync")

func _request_host_sync() -> void:
	if _session_multiplayer and not _session_host:
		_floor_sync_in_progress = true
		_pending_player_roster.clear()
		_pending_enemy_spawns.clear()
		rpc_id(1, "rpc_client_ready_for_sync", _local_peer_id)

func _register_player_node(peer_id: int, player_node: Node3D) -> void:
	if player_node == null:
		return
	_player_by_peer_id[peer_id] = player_node
	player_node.name = "Player_%d" % peer_id
	if player_node.has_method("set_network_peer_id"):
		player_node.call("set_network_peer_id", peer_id)
	if peer_id == _local_peer_id:
		_cached_player = player_node

func _spawn_player_for_peer(peer_id: int, spawn_pos: Vector3) -> Node3D:
	var existing = _player_by_peer_id.get(peer_id, null)
	if existing is Node3D and is_instance_valid(existing):
		existing.global_position = spawn_pos
		return existing

	var player_variant := PLAYER_SCENE.instantiate()
	if not (player_variant is Node3D):
		return null
	var player_node: Node3D = player_variant
	if player_node.has_method("set_network_peer_id"):
		player_node.call("set_network_peer_id", peer_id)
	else:
		player_node.set("network_peer_id", peer_id)
	add_child(player_node)
	player_node.global_position = spawn_pos
	_register_player_node(peer_id, player_node)
	return player_node

func _spawn_missing_network_players() -> void:
	if not _session_multiplayer or not _session_host:
		return
	var base_pos := Vector3.ZERO
	if _player_spawn_points_by_peer.has(_local_peer_id):
		base_pos = _player_spawn_points_by_peer[_local_peer_id]
	var existing_peers := _get_network_connected_peer_ids()
	var offset_index := 1
	for peer_id in existing_peers:
		if _player_by_peer_id.has(peer_id):
			continue
		var spawn_pos := _offset_spawn_position(base_pos, offset_index)
		_spawn_player_for_peer(peer_id, spawn_pos)
		_player_spawn_points_by_peer[peer_id] = spawn_pos
		offset_index += 1
	_sync_player_roster_to_clients()

func _sync_player_roster_to_clients() -> void:
	if not _session_multiplayer or not _session_host:
		return
	var roster: Array = []
	for peer_key in _player_by_peer_id.keys():
		var peer_id := int(peer_key)
		var player_node = _player_by_peer_id[peer_id]
		if not is_instance_valid(player_node):
			continue
		roster.append({
			"peer_id": peer_id,
			"position": player_node.global_position,
		})
	for peer_id in _get_network_connected_peer_ids():
		if not _is_peer_floor_sync_ready(peer_id):
			continue
		rpc_id(peer_id, "rpc_sync_player_roster", roster)

func _mark_all_clients_floor_not_ready() -> void:
	_floor_sync_ready_by_peer.clear()
	for peer_id in _get_network_connected_peer_ids():
		_floor_sync_ready_by_peer[int(peer_id)] = false

func _set_peer_floor_sync_ready(peer_id: int, is_ready: bool) -> void:
	if peer_id <= 1:
		return
	_floor_sync_ready_by_peer[peer_id] = is_ready

func _is_peer_floor_sync_ready(peer_id: int) -> bool:
	return bool(_floor_sync_ready_by_peer.get(peer_id, false))

func _send_player_roster_to_peer(peer_id: int) -> void:
	if not _session_multiplayer or not _session_host:
		return
	if not _is_peer_floor_sync_ready(peer_id):
		return
	var roster: Array = []
	for peer_key in _player_by_peer_id.keys():
		var roster_peer_id := int(peer_key)
		var player_node = _player_by_peer_id[roster_peer_id]
		if not is_instance_valid(player_node):
			continue
		roster.append({
			"peer_id": roster_peer_id,
			"position": player_node.global_position,
		})
	rpc_id(peer_id, "rpc_sync_player_roster", roster)

func _send_all_enemies_to_peer(peer_id: int) -> void:
	if not _session_multiplayer or not _session_host:
		return
	if not _is_peer_floor_sync_ready(peer_id):
		return
	for enemy_id_variant in _enemy_by_network_id.keys():
		var enemy_id := int(enemy_id_variant)
		var enemy = _enemy_by_network_id[enemy_id]
		if not is_instance_valid(enemy):
			continue
		rpc_id(peer_id, "rpc_spawn_enemy", enemy_id, enemy.scene_file_path, enemy.global_position)

func _apply_pending_network_sync() -> void:
	if _floor_sync_in_progress:
		return
	if not _pending_player_roster.is_empty():
		var roster := _pending_player_roster.duplicate(true)
		_pending_player_roster.clear()
		_apply_remote_player_roster(roster)
	if _pending_enemy_spawns.is_empty():
		return
	var pending_spawns := _pending_enemy_spawns.duplicate(true)
	_pending_enemy_spawns.clear()
	for entry_variant in pending_spawns:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		_spawn_enemy_proxy(
			int(entry.get("enemy_id", -1)),
			String(entry.get("scene_path", "")),
			entry.get("enemy_position", Vector3.ZERO)
		)

func _apply_remote_player_roster(roster: Array) -> void:
	var roster_peer_ids := {}
	for entry_variant in roster:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		var peer_id := int(entry.get("peer_id", -1))
		if peer_id < 0:
			continue
		roster_peer_ids[peer_id] = true
		var spawn_pos: Vector3 = entry.get("position", Vector3.ZERO)
		var player_node = _spawn_player_for_peer(peer_id, spawn_pos)
		if player_node != null and player_node.has_method("set_network_peer_id"):
			player_node.call("set_network_peer_id", peer_id)

	var to_remove: Array = []
	for peer_key in _player_by_peer_id.keys():
		var peer_id := int(peer_key)
		if peer_id == _local_peer_id:
			# Avoid transient roster packets despawning the local client avatar.
			continue
		if roster_peer_ids.has(peer_id):
			continue
		var node = _player_by_peer_id[peer_id]
		if is_instance_valid(node):
			node.queue_free()
		to_remove.append(peer_id)
	for peer_id_variant in to_remove:
		_player_by_peer_id.erase(int(peer_id_variant))

func _spawn_enemy_proxy(enemy_id: int, scene_path: String, enemy_position: Vector3) -> void:
	if enemy_id < 0:
		return
	if _enemy_by_network_id.has(enemy_id):
		var existing_enemy = _enemy_by_network_id[enemy_id]
		if is_instance_valid(existing_enemy):
			existing_enemy.global_position = enemy_position
		return
	var packed := load(scene_path)
	if not (packed is PackedScene):
		return
	var enemy_scene: PackedScene = packed
	var enemy_variant: Variant = enemy_scene.instantiate()
	if not (enemy_variant is EnemyBase):
		if enemy_variant is Node:
			var cleanup: Node = enemy_variant
			cleanup.free()
		return
	var enemy: EnemyBase = enemy_variant
	nav_region.add_child(enemy)
	enemy.global_position = enemy_position
	enemy.set_network_proxy_mode(true)
	_enemy_by_network_id[enemy_id] = enemy

func _get_authoritative_progress_player() -> Node3D:
	if _session_multiplayer:
		var local_player = _player_by_peer_id.get(_local_peer_id, null)
		if is_instance_valid(local_player):
			return local_player
	for player_variant in get_tree().get_nodes_in_group("player"):
		if player_variant is Node3D and is_instance_valid(player_variant):
			return player_variant
	return null

func _offset_spawn_position(base_pos: Vector3, index: int) -> Vector3:
	match index:
		0:
			return base_pos
		1:
			return base_pos + Vector3(2.0, 0.0, 0.0)
		2:
			return base_pos + Vector3(-2.0, 0.0, 0.0)
		3:
			return base_pos + Vector3(0.0, 0.0, 2.0)
		_:
			return base_pos + Vector3(0.0, 0.0, -2.0)

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

func _get_network_local_peer_id() -> int:
	var session = _get_network_session()
	if session == null:
		return 1
	return int(session.call("get_local_peer_id"))

func _get_network_connected_peer_ids() -> PackedInt32Array:
	var session = _get_network_session()
	if session == null:
		return PackedInt32Array()
	var peers_variant: Variant = session.call("get_connected_peer_ids")
	if peers_variant is PackedInt32Array:
		return peers_variant
	return PackedInt32Array()

func _leave_network_game() -> void:
	var session = _get_network_session()
	if session == null:
		return
	session.call("leave_game")

func _sync_floor_to_clients() -> void:
	if not _session_multiplayer or not _session_host:
		return
	_mark_all_clients_floor_not_ready()
	rpc("rpc_sync_floor_state", floor_number, generation_seed)

func _broadcast_player_snapshots() -> void:
	if not _session_multiplayer or not _session_host:
		return
	var snapshots: Array = []
	for peer_key in _player_by_peer_id.keys():
		var peer_id := int(peer_key)
		var player_node = _player_by_peer_id[peer_id]
		if not is_instance_valid(player_node):
			continue
		if player_node.has_method("build_network_snapshot"):
			snapshots.append({
				"peer_id": peer_id,
				"state": player_node.call("build_network_snapshot"),
			})
	rpc("rpc_receive_player_snapshots", snapshots)

func _send_local_player_snapshot_to_host() -> void:
	if not _session_multiplayer or _session_host:
		return
	var local_player = _player_by_peer_id.get(_local_peer_id, null)
	if not is_instance_valid(local_player):
		return
	if not local_player.has_method("build_network_snapshot"):
		return
	rpc_id(1, "rpc_submit_client_player_state", _local_peer_id, local_player.call("build_network_snapshot"))

func request_weapon_fire(peer_id: int, weapon_slot: int, weapon_key: String, cam_origin: Vector3, cam_forward: Vector3, shot_id: int) -> void:
	if not _session_multiplayer:
		return
	if _session_host:
		_handle_weapon_fire_request(peer_id, weapon_slot, weapon_key, cam_origin, cam_forward, shot_id)
	else:
		rpc_id(1, "rpc_request_weapon_fire", peer_id, weapon_slot, weapon_key, cam_origin, cam_forward, shot_id)

func request_weapon_reload(peer_id: int, weapon_slot: int, weapon_key: String) -> void:
	if not _session_multiplayer:
		return
	if _session_host:
		_handle_weapon_reload_request(peer_id, weapon_slot, weapon_key)
	else:
		rpc_id(1, "rpc_request_weapon_reload", peer_id, weapon_slot, weapon_key)

func broadcast_projectile_visual(scene_path: String, cam_origin: Vector3, cam_forward: Vector3) -> void:
	if not _session_multiplayer or not _session_host:
		return
	if scene_path.is_empty():
		return
	rpc("rpc_spawn_projectile_visual", scene_path, cam_origin, cam_forward)

func _handle_weapon_fire_request(peer_id: int, weapon_slot: int, weapon_key: String, cam_origin: Vector3, cam_forward: Vector3, _shot_id: int) -> void:
	var player_node = _player_by_peer_id.get(peer_id, null)
	if not is_instance_valid(player_node):
		return
	var manager: WeaponManager = player_node.get("weapon_manager")
	if manager == null:
		return
	if not weapon_key.is_empty() and manager.has_method("switch_to_weapon_by_key"):
		manager.call("switch_to_weapon_by_key", weapon_key)
	else:
		manager.switch_to_weapon(weapon_slot)
	var weapon := manager.get_current_weapon()
	if weapon == null and not weapon_key.is_empty() and manager.has_method("switch_to_weapon_by_key"):
		var switched := bool(manager.call("switch_to_weapon_by_key", weapon_key))
		if switched:
			weapon = manager.get_current_weapon()
	if weapon == null:
		return
	if not weapon.has_method("fire_authoritative_from_network"):
		return
	var fired := bool(weapon.call("fire_authoritative_from_network", cam_origin, cam_forward, player_node))
	if not fired:
		return
	rpc_id(peer_id, "rpc_sync_weapon_state", peer_id, manager.get_current_weapon_slot(), weapon.current_mag, manager.get_ammo_snapshot())

func _handle_weapon_reload_request(peer_id: int, weapon_slot: int, weapon_key: String) -> void:
	var player_node = _player_by_peer_id.get(peer_id, null)
	if not is_instance_valid(player_node):
		return
	var manager: WeaponManager = player_node.get("weapon_manager")
	if manager == null:
		return
	if not weapon_key.is_empty() and manager.has_method("switch_to_weapon_by_key"):
		manager.call("switch_to_weapon_by_key", weapon_key)
	else:
		manager.switch_to_weapon(weapon_slot)
	var weapon := manager.get_current_weapon()
	if weapon == null and not weapon_key.is_empty() and manager.has_method("switch_to_weapon_by_key"):
		var switched := bool(manager.call("switch_to_weapon_by_key", weapon_key))
		if switched:
			weapon = manager.get_current_weapon()
	if weapon == null:
		return
	if not weapon.has_method("perform_authoritative_reload"):
		return
	var success := bool(weapon.call("perform_authoritative_reload"))
	if not success:
		return
	rpc_id(peer_id, "rpc_sync_weapon_state", peer_id, manager.get_current_weapon_slot(), weapon.current_mag, manager.get_ammo_snapshot())

func request_interaction(interactor: Node, target: Node) -> void:
	if target == null:
		return
	if not _session_multiplayer or _session_host:
		_apply_interaction(interactor, target)
		return
	var target_pos := Vector3.ZERO
	if target is Node3D:
		target_pos = (target as Node3D).global_position
	rpc_id(1, "rpc_request_interaction", _local_peer_id, String(target.get_path()), target_pos)

func request_chest_view_closed(peer_id: int, chest_path: String) -> void:
	if chest_path.is_empty():
		return
	if not _session_multiplayer:
		return
	if _session_host:
		_handle_chest_view_closed(peer_id, chest_path)
	else:
		rpc_id(1, "rpc_request_close_chest_view", peer_id, chest_path)

func request_sync_active_chest_contents(peer_id: int, chest_path: String, chest_pos: Vector3, items: Array) -> void:
	if chest_path.is_empty():
		return
	if not _session_multiplayer:
		_apply_shared_chest_contents(chest_path, chest_pos, items)
		return
	if _session_host:
		_apply_shared_chest_contents(chest_path, chest_pos, items)
	else:
		rpc_id(1, "rpc_request_sync_chest_contents", peer_id, chest_path, chest_pos, items)

func _apply_interaction(interactor: Node, target: Node) -> void:
	var resolved_target := _resolve_interaction_target(target)
	if resolved_target == null:
		return

	target = resolved_target
	if target is DungeonDoor:
		var door: DungeonDoor = target
		door.open()
		if _session_multiplayer and _session_host:
			rpc("rpc_sync_door_open", String(door.get_path()), door.global_position)
		return
	if target is InteractableChest:
		var chest: InteractableChest = target
		chest.ensure_loot_populated()
		if _session_multiplayer and _session_host:
			chest.open_visual_only()
		else:
			chest.interact(interactor)
		if _session_multiplayer and _session_host:
			var interactor_peer := _local_peer_id
			if interactor != null and interactor.has_method("get_network_peer_id"):
				interactor_peer = int(interactor.call("get_network_peer_id"))
			var chest_path := String(chest.get_path())
			var items := chest.get_storage_payload()
			var chest_pos: Vector3 = chest.global_position
			_add_chest_viewer(chest_path, interactor_peer)
			if interactor_peer == _local_peer_id:
				rpc_open_chest_for_local_player(chest_path, items, chest_pos)
			else:
				rpc_id(interactor_peer, "rpc_open_chest_for_local_player", chest_path, items, chest_pos)
		return
	if target.has_method("interact"):
		target.interact(interactor)

func _resolve_interaction_target(target: Node) -> Node:
	var current := target
	while current != null:
		if current is DungeonDoor or current is InteractableChest:
			return current
		if current.has_method("interact"):
			return current
		current = current.get_parent()
	return null

func _find_interaction_target_for_player(interactor: Node3D) -> Node:
	if interactor == null:
		return null

	var space_state := get_world_3d().direct_space_state
	if space_state == null:
		return null

	var origin := interactor.global_position + Vector3(0.0, 1.4, 0.0)
	var forward := -interactor.global_transform.basis.z.normalized()
	var head := interactor.get_node_or_null("Head")
	if head is Node3D:
		var head_node: Node3D = head
		origin = head_node.global_position
		forward = -head_node.global_transform.basis.z.normalized()

	var query := PhysicsRayQueryParameters3D.create(origin, origin + forward * 3.5)
	query.exclude = [interactor.get_rid()]
	query.collide_with_areas = true
	query.collide_with_bodies = true
	query.collision_mask = 0xFFFFFFFF

	var result := space_state.intersect_ray(query)
	if result.is_empty():
		return null
	return _resolve_interaction_target(result.get("collider", null))

func _find_interaction_target_by_position(world_pos: Vector3) -> Node:
	if world_pos == Vector3.ZERO:
		return null
	var chest := _find_chest_by_position(world_pos)
	if chest != null:
		return chest
	var door := _find_door_by_position(world_pos)
	if door != null:
		return door
	return null

func _find_door_by_position(world_pos: Vector3, max_distance: float = 4.0) -> DungeonDoor:
	var closest: DungeonDoor = null
	var closest_distance := max_distance
	var closest_dist_sq := closest_distance * closest_distance
	for node_variant in get_tree().get_nodes_in_group("dungeon_door"):
		if not (node_variant is DungeonDoor):
			continue
		var door: DungeonDoor = node_variant
		if not is_instance_valid(door):
			continue
		var dist_sq := door.global_position.distance_squared_to(world_pos)
		if dist_sq <= closest_dist_sq:
			closest = door
			closest_dist_sq = dist_sq
	return closest

func _add_chest_viewer(chest_path: String, peer_id: int) -> void:
	if chest_path.is_empty():
		return
	var viewers: Dictionary = _chest_viewers_by_path.get(chest_path, {})
	viewers[peer_id] = true
	_chest_viewers_by_path[chest_path] = viewers

func _handle_chest_view_closed(peer_id: int, chest_path: String) -> void:
	if not _session_host:
		return
	if chest_path.is_empty():
		return
	var viewers: Dictionary = _chest_viewers_by_path.get(chest_path, {})
	if viewers.is_empty():
		return
	viewers.erase(peer_id)
	if viewers.is_empty():
		_chest_viewers_by_path.erase(chest_path)
		_close_chest_for_all(chest_path)
	else:
		_chest_viewers_by_path[chest_path] = viewers

func _close_chest_for_all(chest_path: String) -> void:
	var chest_pos := Vector3.ZERO
	var chest_node = get_node_or_null(NodePath(chest_path))
	if chest_node is InteractableChest:
		var chest: InteractableChest = chest_node
		chest_pos = chest.global_position
		chest.close_chest()
	if _session_multiplayer and _session_host:
		rpc("rpc_sync_chest_closed", chest_path, chest_pos)

func _apply_shared_chest_contents(chest_path: String, chest_pos: Vector3, items: Array) -> void:
	if chest_path.is_empty():
		return
	var chest_node = get_node_or_null(NodePath(chest_path))
	if not (chest_node is InteractableChest):
		chest_node = _find_chest_by_position(chest_pos)
	if not (chest_node is InteractableChest):
		return
	var chest: InteractableChest = chest_node
	chest.set_storage_items(items)
	if _session_multiplayer and _session_host:
		rpc("rpc_sync_chest_contents", String(chest.get_path()), items, chest.global_position)
	_refresh_local_active_chest_view(chest_path, chest)

func _refresh_local_active_chest_view(chest_path: String, chest: InteractableChest) -> void:
	var local_player := _get_local_player_node()
	if not is_instance_valid(local_player):
		return
	var inventory_candidate: Variant = local_player.get("inventory_system")
	if not (inventory_candidate is InventorySystem):
		return
	var inventory_system: InventorySystem = inventory_candidate
	var active_path := inventory_system.get_active_chest_path()
	var local_chest_path := String(chest.get_path())
	if active_path != chest_path and active_path != local_chest_path:
		return
	inventory_system.refresh_active_chest_from_world()

func _remove_peer_from_chest_views(peer_id: int) -> void:
	if not _session_host:
		return
	var keys: Array = _chest_viewers_by_path.keys()
	for path_variant in keys:
		var chest_path := String(path_variant)
		var viewers: Dictionary = _chest_viewers_by_path.get(chest_path, {})
		if not viewers.has(peer_id):
			continue
		viewers.erase(peer_id)
		if viewers.is_empty():
			_chest_viewers_by_path.erase(chest_path)
			_close_chest_for_all(chest_path)
		else:
			_chest_viewers_by_path[chest_path] = viewers

func _find_chest_by_position(world_pos: Vector3, max_distance: float = 5.0) -> InteractableChest:
	var closest: InteractableChest = null
	var closest_distance := max_distance
	var closest_dist_sq := closest_distance * closest_distance
	for node_variant in get_tree().get_nodes_in_group("interactable_chest"):
		if not (node_variant is InteractableChest):
			continue
		var chest: InteractableChest = node_variant
		if not is_instance_valid(chest):
			continue
		var dist_sq := chest.global_position.distance_squared_to(world_pos)
		if dist_sq <= closest_dist_sq:
			closest = chest
			closest_dist_sq = dist_sq
	return closest

func _get_local_player_node() -> Node3D:
	var local_player = _player_by_peer_id.get(_local_peer_id, null)
	if is_instance_valid(local_player) and local_player is Node3D:
		return local_player
	for player_variant in get_tree().get_nodes_in_group("player"):
		if not (player_variant is Node3D):
			continue
		var player_node: Node3D = player_variant
		if player_node.has_method("is_local_controlled") and bool(player_node.call("is_local_controlled")):
			return player_node
	return null

func _register_network_enemy(enemy: EnemyBase) -> void:
	if enemy == null:
		return
	var enemy_id := _next_enemy_network_id
	_next_enemy_network_id += 1
	_enemy_by_network_id[enemy_id] = enemy
	_enemy_network_id_by_instance_id[enemy.get_instance_id()] = enemy_id
	enemy.set_meta("network_id", enemy_id)
	enemy.enemy_died.connect(_on_network_enemy_died.bind(enemy_id), CONNECT_ONE_SHOT)
	for peer_id in _get_network_connected_peer_ids():
		if not _is_peer_floor_sync_ready(peer_id):
			continue
		rpc_id(peer_id, "rpc_spawn_enemy", enemy_id, enemy.scene_file_path, enemy.global_position)

func _on_network_enemy_died(enemy_id: int) -> void:
	rpc("rpc_mark_enemy_dead", enemy_id)
	await get_tree().create_timer(0.65).timeout
	_enemy_by_network_id.erase(enemy_id)
	rpc("rpc_despawn_enemy", enemy_id)

func _broadcast_enemy_snapshots() -> void:
	if not _session_multiplayer or not _session_host:
		return
	var snapshots: Array = []
	for enemy_id_variant in _enemy_by_network_id.keys():
		var enemy_id := int(enemy_id_variant)
		var enemy = _enemy_by_network_id[enemy_id]
		if not is_instance_valid(enemy):
			continue
		if enemy.has_method("get_network_state_snapshot"):
			snapshots.append({
				"id": enemy_id,
				"state": enemy.call("get_network_state_snapshot"),
			})
	rpc("rpc_receive_enemy_snapshots", snapshots)

func _on_network_peer_joined(peer_id: int) -> void:
	if not _session_host:
		return
	_set_peer_floor_sync_ready(peer_id, false)
	_spawn_missing_network_players()
	_sync_floor_to_clients()

func _on_network_peer_left(peer_id: int) -> void:
	if not _session_host:
		return
	_remove_peer_from_chest_views(peer_id)
	_floor_sync_ready_by_peer.erase(peer_id)
	var player_node = _player_by_peer_id.get(peer_id, null)
	if is_instance_valid(player_node):
		player_node.queue_free()
	_player_by_peer_id.erase(peer_id)
	_player_spawn_points_by_peer.erase(peer_id)
	_sync_player_roster_to_clients()

func _on_network_session_ended(_reason: String) -> void:
	if not _session_multiplayer:
		return
	_session_multiplayer = false
	_session_host = true
	get_tree().change_scene_to_file("res://Scenes/System/bootstrap.tscn")

@rpc("any_peer", "reliable")
func rpc_client_ready_for_sync(peer_id: int) -> void:
	if not _session_host:
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender != peer_id:
		return
	_set_peer_floor_sync_ready(peer_id, false)
	_spawn_missing_network_players()
	rpc_id(peer_id, "rpc_sync_floor_state", floor_number, generation_seed)

@rpc("authority", "call_remote", "reliable")
func rpc_sync_floor_state(remote_floor: int, remote_seed: int) -> void:
	if _session_host:
		return
	floor_number = remote_floor
	generation_seed = remote_seed
	_pending_player_roster.clear()
	_pending_enemy_spawns.clear()
	await generate_floor(floor_number)
	rpc_id(1, "rpc_client_finished_floor_sync", _local_peer_id)

@rpc("any_peer", "reliable")
func rpc_client_finished_floor_sync(peer_id: int) -> void:
	if not _session_host:
		return
	if multiplayer.get_remote_sender_id() != peer_id:
		return
	_set_peer_floor_sync_ready(peer_id, true)
	_send_player_roster_to_peer(peer_id)
	_send_all_enemies_to_peer(peer_id)

@rpc("authority", "call_remote", "reliable")
func rpc_sync_player_roster(roster: Array) -> void:
	if _session_host:
		return
	if _floor_sync_in_progress:
		_pending_player_roster = roster.duplicate(true)
		return
	_apply_remote_player_roster(roster)

@rpc("any_peer", "unreliable")
func rpc_submit_client_player_state(peer_id: int, snapshot: Dictionary) -> void:
	if not _session_host:
		return
	if multiplayer.get_remote_sender_id() != peer_id:
		return
	var player_node = _player_by_peer_id.get(peer_id, null)
	if is_instance_valid(player_node) and player_node.has_method("apply_network_snapshot"):
		player_node.call("apply_network_snapshot", snapshot)

@rpc("authority", "call_remote", "unreliable")
func rpc_receive_player_snapshots(snapshots: Array) -> void:
	if _session_host:
		return
	for entry_variant in snapshots:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		var peer_id := int(entry.get("peer_id", -1))
		var player_node = _player_by_peer_id.get(peer_id, null)
		if not is_instance_valid(player_node):
			continue
		var state: Dictionary = entry.get("state", {})
		if peer_id == _local_peer_id:
			if state.has("health") and player_node.has_method("apply_authoritative_health"):
				player_node.call("apply_authoritative_health", int(state.get("health", 0)))
			continue
		if player_node.has_method("apply_network_snapshot"):
			player_node.call("apply_network_snapshot", state)

@rpc("any_peer", "reliable")
func rpc_request_weapon_fire(peer_id: int, weapon_slot: int, weapon_key: String, cam_origin: Vector3, cam_forward: Vector3, shot_id: int) -> void:
	if not _session_host:
		return
	if multiplayer.get_remote_sender_id() != peer_id:
		return
	_handle_weapon_fire_request(peer_id, weapon_slot, weapon_key, cam_origin, cam_forward, shot_id)

func broadcast_hitscan_visual(from: Vector3, to: Vector3) -> void:
	if not _session_multiplayer or not _session_host:
		return
	rpc("rpc_spawn_hitscan_visual", from, to)

@rpc("any_peer", "reliable")
func rpc_request_weapon_reload(peer_id: int, weapon_slot: int, weapon_key: String) -> void:
	if not _session_host:
		return
	if multiplayer.get_remote_sender_id() != peer_id:
		return
	_handle_weapon_reload_request(peer_id, weapon_slot, weapon_key)

@rpc("authority", "call_remote", "reliable")
func rpc_sync_weapon_state(peer_id: int, slot_index: int, current_mag: int, ammo_snapshot: Dictionary) -> void:
	if _local_peer_id != peer_id:
		return
	var local_player = _player_by_peer_id.get(_local_peer_id, null)
	if not is_instance_valid(local_player):
		return
	var manager: WeaponManager = local_player.get("weapon_manager")
	if manager == null:
		return
	manager.apply_authoritative_weapon_state(slot_index, current_mag, ammo_snapshot)

@rpc("any_peer", "reliable")
func rpc_request_interaction(peer_id: int, target_path: String, target_pos: Vector3 = Vector3.ZERO) -> void:
	if not _session_host:
		return
	if multiplayer.get_remote_sender_id() != peer_id:
		return
	var interactor = _player_by_peer_id.get(peer_id, null)
	var target := get_node_or_null(NodePath(target_path))
	target = _resolve_interaction_target(target)
	if target == null:
		target = _find_interaction_target_by_position(target_pos)
	if target == null and interactor is Node3D:
		target = _find_interaction_target_for_player(interactor)
	if target == null:
		return
	_apply_interaction(interactor, target)

@rpc("any_peer", "reliable")
func rpc_request_close_chest_view(peer_id: int, chest_path: String) -> void:
	if not _session_host:
		return
	if multiplayer.get_remote_sender_id() != peer_id:
		return
	_handle_chest_view_closed(peer_id, chest_path)

@rpc("any_peer", "reliable")
func rpc_request_sync_chest_contents(peer_id: int, chest_path: String, chest_pos: Vector3, items: Array) -> void:
	if not _session_host:
		return
	if multiplayer.get_remote_sender_id() != peer_id:
		return
	_apply_shared_chest_contents(chest_path, chest_pos, items)

@rpc("authority", "call_remote", "reliable")
func rpc_sync_door_open(target_path: String, world_pos: Vector3) -> void:
	var door: DungeonDoor = null
	var node = get_node_or_null(NodePath(target_path))
	if node is DungeonDoor:
		door = node
	if door == null:
		door = _find_door_by_position(world_pos)
	if door != null:
		door.open()

@rpc("authority", "call_remote", "reliable")
func rpc_open_chest_for_local_player(chest_path: String, items: Array, chest_pos: Vector3) -> void:
	var chest: InteractableChest = null
	var chest_node = get_node_or_null(NodePath(chest_path))
	if chest_node is InteractableChest:
		chest = chest_node
	if chest == null:
		chest = _find_chest_by_position(chest_pos)
	if chest == null:
		return

	chest.set_storage_items(items)
	chest.open_visual_only()

	var local_player := _get_local_player_node()
	if is_instance_valid(local_player):
		var inventory_candidate: Variant = local_player.get("inventory_system")
		if inventory_candidate is InventorySystem:
			var inventory_system: InventorySystem = inventory_candidate
			inventory_system.open_chest(chest)
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

@rpc("authority", "call_remote", "reliable")
func rpc_sync_chest_closed(chest_path: String, chest_pos: Vector3) -> void:
	var chest: InteractableChest = null
	var chest_node = get_node_or_null(NodePath(chest_path))
	if chest_node is InteractableChest:
		chest = chest_node
	if chest == null:
		chest = _find_chest_by_position(chest_pos)
	if chest == null:
		return
	chest.close_chest()

@rpc("authority", "call_remote", "reliable")
func rpc_sync_chest_contents(chest_path: String, items: Array, chest_pos: Vector3) -> void:
	var chest: InteractableChest = null
	var chest_node = get_node_or_null(NodePath(chest_path))
	if chest_node is InteractableChest:
		chest = chest_node
	if chest == null:
		chest = _find_chest_by_position(chest_pos)
	if chest == null:
		return
	chest.set_storage_items(items)
	_refresh_local_active_chest_view(chest_path, chest)

@rpc("authority", "call_remote", "reliable")
func rpc_spawn_enemy(enemy_id: int, scene_path: String, enemy_position: Vector3) -> void:
	if _session_host:
		return
	if _floor_sync_in_progress:
		_pending_enemy_spawns.append({
			"enemy_id": enemy_id,
			"scene_path": scene_path,
			"enemy_position": enemy_position,
		})
		return
	_spawn_enemy_proxy(enemy_id, scene_path, enemy_position)

@rpc("authority", "call_remote", "reliable")
func rpc_mark_enemy_dead(enemy_id: int) -> void:
	var enemy = _enemy_by_network_id.get(enemy_id, null)
	if not is_instance_valid(enemy):
		return
	if enemy.has_method("force_network_dead_visual"):
		enemy.call("force_network_dead_visual")

@rpc("authority", "call_remote", "reliable")
func rpc_spawn_projectile_visual(scene_path: String, cam_origin: Vector3, cam_forward: Vector3) -> void:
	if _session_host:
		return
	var packed := load(scene_path)
	if not (packed is PackedScene):
		return
	var projectile_scene: PackedScene = packed
	var projectile_variant: Variant = projectile_scene.instantiate()
	if not (projectile_variant is Projectile):
		if projectile_variant is Node:
			var cleanup: Node = projectile_variant
			cleanup.queue_free()
		return

	var projectile: Projectile = projectile_variant
	var spawn_parent := get_tree().current_scene
	if spawn_parent == null:
		projectile.queue_free()
		return

	projectile.network_visual_only = true
	projectile.direction = cam_forward.normalized()
	spawn_parent.add_child(projectile)
	projectile.global_position = cam_origin + cam_forward.normalized() * 2.0
	if projectile.direction.abs().is_equal_approx(Vector3(0, 1, 0)):
		projectile.look_at(projectile.global_position + projectile.direction, Vector3.RIGHT)
	else:
		projectile.look_at(projectile.global_position + projectile.direction, Vector3.UP)

@rpc("authority", "call_remote", "unreliable")
func rpc_spawn_hitscan_visual(from: Vector3, to: Vector3) -> void:
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

	var temp_tracer := MeshInstance3D.new()
	temp_tracer.mesh = t_mesh
	temp_tracer.material_override = mat
	temp_tracer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var current_scene := get_tree().current_scene
	if current_scene == null:
		temp_tracer.queue_free()
		return
	current_scene.add_child(temp_tracer)

	temp_tracer.global_position = (from + to) / 2.0
	temp_tracer.look_at(to, Vector3.UP)
	temp_tracer.rotate_object_local(Vector3.RIGHT, -PI / 2.0)

	await get_tree().create_timer(0.05).timeout
	if is_instance_valid(temp_tracer):
		temp_tracer.queue_free()

@rpc("authority", "call_remote", "reliable")
func rpc_despawn_enemy(enemy_id: int) -> void:
	var enemy = _enemy_by_network_id.get(enemy_id, null)
	if is_instance_valid(enemy):
		enemy.queue_free()
	_enemy_by_network_id.erase(enemy_id)

@rpc("authority", "call_remote", "unreliable")
func rpc_receive_enemy_snapshots(snapshots: Array) -> void:
	if _session_host:
		return
	for entry_variant in snapshots:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		var enemy_id := int(entry.get("id", -1))
		if enemy_id < 0:
			continue
		var enemy = _enemy_by_network_id.get(enemy_id, null)
		if not is_instance_valid(enemy):
			continue
		var state: Dictionary = entry.get("state", {})
		if enemy.has_method("apply_network_state_snapshot"):
			enemy.call("apply_network_state_snapshot", state)
