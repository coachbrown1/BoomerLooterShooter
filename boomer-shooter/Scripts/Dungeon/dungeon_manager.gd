@tool
extends Node3D
class_name DungeonManager

@export var floor_number: int = 1
@export var dungeon_content: Resource = preload("res://Data/dungeons/default_dungeon_content.tres")

# Lattice generation config
@export var grid_size_min: int = 10
@export var grid_size_max: int = 10
@export var min_start_end_distance_rooms: int = 3
@export var room_size_tiles: int = 20
@export var corridor_width_tiles: int = 4
@export var corridor_length_tiles: int = 10
@export var generation_seed: int = 0

@onready var nav_region: NavigationRegion3D = $NavigationRegion3D

const SNAPSHOT_INTERVAL: float = 0.05
const CASTLE_INNER_CHAMBER_SCENE_PATH := "res://Scenes/Dungeon/Handcrafted/Castle_InnerChamber.tscn"
const LOOT_PICKUP_SCENE: PackedScene = preload("res://Scenes/Props/loot_pickup.tscn")
const VERIFIER_DEFAULT_DUNGEON_SEED := 1773666431

const TILE_SIZE: float = 3.0

var _generator: DungeonGenerator
var _stitcher: DungeonStitcher
var _encounter: EncounterSystem
var _rooms: Array = []
var _active_dungeon_content: Resource = null
var _room_lookup := {}
var _spawned_enemy_rooms := {}
var _last_player_room_id: int = -1

var _session_multiplayer: bool = false
var _session_host: bool = false
var _local_peer_id: int = 1
var _snapshot_timer: float = 0.0
var _enemy_by_network_id: Dictionary = {}
var _enemy_network_id_by_instance_id: Dictionary = {}
var _next_enemy_network_id: int = 1
var _loot_pickup_by_network_id: Dictionary = {}
var _next_loot_pickup_network_id: int = 1
var _chest_viewers_by_path: Dictionary = {}
var _leave_session_ui: CanvasLayer = null
var _floor_sync_in_progress := false
var _floor_sync_ready_by_peer: Dictionary = {}
var _pending_player_roster: Array = []
var _pending_enemy_spawns: Array = []
var _room_instances_by_id := {}
var _suppressed_enemies_by_room_id := {}
var _players_ready_callback: Callable = Callable()
var _pending_inventory_restore: bool = false
var _room_scene_contract_cache := {}
var _debug_network_visual_counts := {
	"hitscan": 0,
	"projectile": 0,
	"weapon_fire": 0,
}

func _ready() -> void:
	add_to_group("dungeon_manager")
	if Engine.is_editor_hint():
		set_process(false)
		return

	_session_multiplayer = _is_network_multiplayer_active()
	_session_host = not _session_multiplayer or _is_network_host()
	_local_peer_id = _get_network_local_peer_id()
	_bind_network_signals()
	if _session_multiplayer:
		_build_leave_session_ui()

	set_process(true)
	if _session_multiplayer and not _session_host:
		return

	# Apply hub portal config overrides from GameState.
	grid_size_min = GameState.dungeon_grid_min
	grid_size_max = maxi(GameState.dungeon_grid_max, grid_size_min)
	generation_seed = GameState.dungeon_seed
	if _is_verifier_run() and generation_seed == 0:
		generation_seed = VERIFIER_DEFAULT_DUNGEON_SEED
		GameState.dungeon_seed = generation_seed

	generate_floor(floor_number)
	if _session_multiplayer and _session_host:
		_sync_floor_to_clients()

func _process(delta: float) -> void:
	if _session_multiplayer:
		if _session_host:
			_snapshot_timer += delta
			if _snapshot_timer >= SNAPSHOT_INTERVAL:
				_snapshot_timer = 0.0
				_broadcast_enemy_snapshots()

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
	_active_dungeon_content = null
	_chest_viewers_by_path.clear()
	_enemy_by_network_id.clear()
	_enemy_network_id_by_instance_id.clear()
	_next_enemy_network_id = 1
	_loot_pickup_by_network_id.clear()
	_next_loot_pickup_network_id = 1
	_room_instances_by_id.clear()
	_suppressed_enemies_by_room_id.clear()
	_reset_debug_network_visual_counts()

	# Generate tile layout
	_generator = DungeonGenerator.new()
	_generator.grid_size_min = grid_size_min
	_generator.grid_size_max = grid_size_max
	_generator.min_start_end_distance_rooms = min_start_end_distance_rooms
	_generator.room_size_tiles = room_size_tiles
	_generator.corridor_width_tiles = corridor_width_tiles
	_generator.corridor_length_tiles = corridor_length_tiles
	var requested_seed := generation_seed
	if _should_use_packaged_runtime_random_seed(preview_mode):
		requested_seed = 0
	_generator.generate(floor_num, requested_seed)
	generation_seed = int(_generator.rng.seed)
	_rooms = _generator.rooms
	_build_room_lookup()

	_active_dungeon_content = dungeon_content
	_assign_room_scenes_and_fit_topology(_active_dungeon_content)

	_update_environment(_active_dungeon_content)

	# Stitch room and corridor scenes inside the NavigationRegion3D
	_stitcher = DungeonStitcher.new()
	_stitcher.stitch(
		_rooms,
		_generator.corridors,
		nav_region,
		_active_dungeon_content
	)
	_post_process_stitched_rooms()

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
	_place_player()
	var host_authoritative_world := not _session_multiplayer or _session_host
	if host_authoritative_world:
		_encounter = EncounterSystem.new()
		if _session_multiplayer:
			_enemy_by_network_id.clear()
			_enemy_network_id_by_instance_id.clear()
			_next_enemy_network_id = 1
			_loot_pickup_by_network_id.clear()
			_next_loot_pickup_network_id = 1

		# Place exit portal in exit room
		_place_exit()

		# Spawn only the start-room neighborhood; expand as player progresses.
		_prime_progressive_enemy_spawning()
	else:
		_encounter = null
		_place_exit()

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

func _should_use_packaged_runtime_random_seed(preview_mode: bool) -> bool:
	if preview_mode:
		return false
	if OS.has_feature("editor"):
		return false
	return not _session_multiplayer or _session_host

func clear_editor_preview() -> void:
	for child in nav_region.get_children():
		child.queue_free()
	_rooms = []
	_room_lookup = {}

	_spawned_enemy_rooms = {}
	_last_player_room_id = -1
	_encounter = null
	_room_instances_by_id.clear()
	_suppressed_enemies_by_room_id.clear()

func get_editor_preview_room_targets() -> Array:
	var targets: Array = []
	for room_variant in _rooms:
		var room: RoomData = room_variant
		if room == null:
			continue
		var is_start := room.room_type == RoomData.RoomType.START
		var is_exit := room.room_type == RoomData.RoomType.EXIT
		var is_custom := room.assigned_scene_role != "default"
		var include := is_start or is_exit or is_custom
		if not include:
			continue

		var type_name := _room_type_name(room.room_type)
		var custom_tag := " [custom]" if is_custom else ""
		var scene_tag := ""
		if room.assigned_scene_path != "":
			var scene_name := room.assigned_scene_path.get_file().get_basename()
			scene_tag = " | %s" % scene_name
		var label := "%s%s%s | room %d | lattice (%d,%d)" % [
			type_name,
			custom_tag,
			scene_tag,
			room.id,
			room.lattice_coord.x,
			room.lattice_coord.y,
		]
		targets.append({
			"id": room.id,
			"label": label,
			"room_type": int(room.room_type),
			"lattice_coord": room.lattice_coord,
			"world_position": room.get_world_center(TILE_SIZE),
			"is_custom": is_custom,
			"assigned_scene_path": room.assigned_scene_path,
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
	if biome_data and biome_data.has_method("get"):
		var fog_color: Variant = biome_data.get("fog_light_color")
		if typeof(fog_color) == TYPE_COLOR:
			env.fog_light_color = fog_color
	return

func _place_player() -> void:
	var start_room := _get_room_by_type(RoomData.RoomType.START)
	if start_room == null:
		return
	var spawn_data := _get_start_player_spawn_data(start_room)
	var base_pos: Vector3 = spawn_data.get("position", start_room.get_world_center(TILE_SIZE)) as Vector3
	var look_target: Vector3 = spawn_data.get("look_target", base_pos + Vector3(0.0, 0.0, 1.0)) as Vector3
	base_pos.y = 1.0

	var player_count := 1
	if _session_multiplayer:
		player_count += _get_network_connected_peer_ids().size()
	var spawn_positions := _build_spawn_positions(base_pos, look_target, player_count)

	if _players_ready_callback.is_valid() and NetworkPlayerManager.players_ready.is_connected(_players_ready_callback):
		NetworkPlayerManager.players_ready.disconnect(_players_ready_callback)
	_players_ready_callback = Callable(self, "_on_players_ready_for_floor").bind(look_target)
	NetworkPlayerManager.players_ready.connect(_players_ready_callback)
	_pending_inventory_restore = GameState.initialized and not GameState.player_inventory_snapshot.is_empty()
	NetworkPlayerManager.setup(spawn_positions)
	_on_players_ready_for_floor(NetworkPlayerManager.get_all_players(), look_target)

func _get_start_player_spawn_data(start_room: RoomData) -> Dictionary:
	var fallback_pos := start_room.get_world_center(TILE_SIZE)
	var fallback_look_target := fallback_pos + Vector3(0.0, 0.0, 1.0)
	var room_overlay = _room_instances_by_id.get(start_room.id, null)
	if not is_instance_valid(room_overlay):
		return {
			"position": fallback_pos,
			"look_target": fallback_look_target,
		}
	var player_spawn := room_overlay.get_node_or_null("PlayerSpawn") as Node3D
	if player_spawn == null:
		return {
			"position": fallback_pos,
			"look_target": fallback_look_target,
		}
	var spawn_pos: Vector3 = player_spawn.global_position
	var look_target: Vector3 = spawn_pos + player_spawn.global_basis * Vector3(0.0, 0.0, 1.0)
	return {
		"position": spawn_pos,
		"look_target": look_target,
	}

func _orient_player_toward(player_node: Node3D, look_target: Vector3) -> void:
	if player_node == null:
		return
	# Only rotate around Y (yaw). look_at() also pitches the body when the
	# target is at a different elevation, which tilts the CharacterBody3D mesh.
	var dir := (look_target - player_node.global_position)
	dir.y = 0.0
	if dir.length_squared() > 0.001:
		player_node.rotation.y = atan2(dir.x, dir.z)
	if player_node.has_node("Head"):
		var head := player_node.get_node("Head") as Node3D
		if head != null:
			head.rotation.x = 0.0

func _on_players_ready_for_floor(_players: Dictionary, look_target: Vector3) -> void:
	for player_variant in NetworkPlayerManager.get_all_players().values():
		if player_variant is Node3D and is_instance_valid(player_variant):
			var player_node: Node3D = player_variant
			_orient_player_toward(player_node, look_target)
	var local_player := _get_local_player_node()
	if _pending_inventory_restore and is_instance_valid(local_player):
		var inv := local_player.get("inventory_system") as InventorySystem
		if inv != null:
			inv.apply_slot_snapshot(GameState.player_inventory_snapshot)
			_pending_inventory_restore = false

func _place_exit() -> void:
	var exit_room := _get_room_by_type(RoomData.RoomType.EXIT)
	if exit_room == null:
		return

	var portal_body := Area3D.new()
	portal_body.name = "ExitPortal"
	portal_body.collision_mask = 2  # player CharacterBody3D is on layer 2

	var col := CollisionShape3D.new()
	col.shape = SphereShape3D.new()
	col.shape.radius = 1.8
	portal_body.add_child(col)

	# Build animated sprite from spritesheet (4x4 grid, 160x160 px per frame)
	var sheet: Texture2D = load("res://Assets/Environment/portal_spritesheet.png")
	var sprite := AnimatedSprite3D.new()
	sprite.pixel_size = 0.020
	sprite.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	sprite.no_depth_test = false
	sprite.transparent = true
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD

	var frames := SpriteFrames.new()
	frames.add_animation("idle")
	frames.set_animation_loop("idle", true)
	frames.set_animation_speed("idle", 12.0)
	for row in range(4):
		for col_idx in range(4):
			var atlas := AtlasTexture.new()
			atlas.atlas = sheet
			atlas.region = Rect2(col_idx * 160, row * 160, 160, 160)
			frames.add_frame("idle", atlas)

	sprite.sprite_frames = frames
	portal_body.add_child(sprite)
	sprite.play("idle")

	# Place against an unoccupied wall
	var wall_t := _find_portal_wall_transform(exit_room)
	nav_region.add_child(portal_body)
	portal_body.global_transform = wall_t
	portal_body.body_entered.connect(_on_exit_entered)


func _find_portal_wall_transform(exit_room: RoomData) -> Transform3D:
	var tile_size: float = TILE_SIZE
	var center := exit_room.get_world_center(tile_size)
	var rect := exit_room.grid_rect

	# Find which cardinal directions lead to connected rooms
	var occupied := {}
	for room_variant in _rooms:
		var room: RoomData = room_variant as RoomData
		if room.id == exit_room.id:
			continue
		if exit_room.connected_to.has(room.id):
			var diff := room.get_world_center(tile_size) - center
			if abs(diff.x) >= abs(diff.z):
				occupied["east" if diff.x > 0.0 else "west"] = true
			else:
				occupied["south" if diff.z > 0.0 else "north"] = true

	# Wall candidates: [dir, world_pos, Y_rotation_radians]
	# Sprite3D faces +Z by default; we rotate so it faces into the room.
	var offset := 0.35
	# pixel_size=0.020, frame=160px → sprite height=3.2m → center at y=1.6 touches floor
	var y := 1.6
	var candidates: Array = [
		["north", Vector3(center.x, y, rect.position.y * tile_size + offset),  0.0],
		["south", Vector3(center.x, y, rect.end.y      * tile_size - offset),  PI],
		["west",  Vector3(rect.position.x * tile_size + offset, y, center.z),  -PI * 0.5],
		["east",  Vector3(rect.end.x      * tile_size - offset, y, center.z),   PI * 0.5],
	]

	for cand in candidates:
		if not occupied.has(cand[0]):
			var basis := Basis(Vector3.UP, cand[2] as float)
			return Transform3D(basis, cand[1] as Vector3)

	# Fallback: room centre
	return Transform3D(Basis(), Vector3(center.x, 1.4, center.z))

const HUB_SCENE_PATH := "res://Scenes/World/hub.tscn"

func _on_exit_entered(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return
	if _session_multiplayer and not _session_host:
		return

	# Snapshot the local player's inventory before leaving.
	var local_player := _get_local_player_node()
	if is_instance_valid(local_player):
		var inv := local_player.get("inventory_system") as InventorySystem
		if inv != null:
			GameState.player_inventory_snapshot = inv.get_slot_snapshot()
	GameState.initialized = true

	if _session_multiplayer:
		# Broadcast to all peers (including self) so everyone transitions together.
		rpc("rpc_dungeon_exit_to_hub")
	else:
		get_tree().call_deferred("change_scene_to_file", HUB_SCENE_PATH)

@rpc("authority", "call_local", "reliable")
func rpc_dungeon_exit_to_hub() -> void:
	get_tree().call_deferred("change_scene_to_file", HUB_SCENE_PATH)

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

func _assign_room_scenes_and_fit_topology(content: Resource) -> void:
	_reset_room_scene_assignments()
	if content == null:
		push_error("DungeonManager: default dungeon content is missing.")
		return

	var default_scene := _get_packed_scene_property(content, "default_room_scene")
	if default_scene == null:
		push_error("DungeonManager: default_room_scene is missing from dungeon content.")
		return
	var start_scene := _get_packed_scene_property(content, "start_room_scene")
	var start_room := _get_room_by_type(RoomData.RoomType.START)
	if start_room != null:
		var start_assignment := start_scene if start_scene != null else default_scene
		if not _assign_scene_to_room_with_fit(start_room, start_assignment, "start", false):
			push_error("DungeonManager: failed to fit the start room scene.")

	var special_room_scenes := _get_packed_scene_array_property(content, "special_room_scenes")
	var special_room_chance := 0.0
	if _resource_has_property(content, "special_room_chance"):
		special_room_chance = clampf(float(content.get("special_room_chance")), 0.0, 1.0)
	var rng := _generator.rng if _generator != null and _generator.rng != null else RandomNumberGenerator.new()
	if _generator == null or _generator.rng == null:
		rng.seed = generation_seed
	var normal_rooms: Array = []
	for room_variant in _rooms:
		var room: RoomData = room_variant
		if room.room_type == RoomData.RoomType.NORMAL:
			normal_rooms.append(room)
	_shuffle_array(normal_rooms, rng)
	for room_variant in normal_rooms:
		var room: RoomData = room_variant
		if special_room_scenes.is_empty():
			break
		if rng.randf() >= special_room_chance:
			continue
		var shuffled_specials := special_room_scenes.duplicate()
		_shuffle_array(shuffled_specials, rng)
		for scene_variant in shuffled_specials:
			if not (scene_variant is PackedScene):
				continue
			if _assign_scene_to_room_with_fit(room, scene_variant, "special", true):
				break

	for room_variant in _rooms:
		var room: RoomData = room_variant
		if room.assigned_scene != null:
			continue
		var role := "default"
		if room.room_type == RoomData.RoomType.EXIT:
			role = "exit"
		if not _assign_scene_to_room_with_fit(room, default_scene, role, false):
			push_error("DungeonManager: failed to assign a valid scene for room %d." % room.id)

	_rebuild_room_doorway_walls()

func _reset_room_scene_assignments() -> void:
	for room_variant in _rooms:
		var room: RoomData = room_variant
		room.assigned_scene = null
		room.assigned_scene_path = ""
		room.assigned_scene_role = "default"
		room.chosen_rotation_degrees = 0

func _assign_scene_to_room_with_fit(room: RoomData, scene: PackedScene, role: String, allow_pruning: bool) -> bool:
	if room == null or scene == null:
		return false
	var contract := _get_room_scene_contract(scene)
	if contract.is_empty():
		return false
	if role == "start" and not bool(contract.get("has_player_spawn", false)):
		push_error("DungeonManager: start room scene '%s' is missing PlayerSpawn." % scene.resource_path)
		return false
	if bool(contract.get("supports_any_profile", false)) and not bool(contract.get("supports_runtime_doorways", false)):
		push_error("DungeonManager: default room scene '%s' must support runtime doorway toggling." % scene.resource_path)
		return false

	var current_open_walls := _get_room_open_walls(room)
	if bool(contract.get("supports_any_profile", false)):
		_set_room_assignment(room, scene, role, int(contract.get("default_rotation_degrees", 0)), current_open_walls)
		return true

	var supported_profiles: Array = contract.get("supported_profiles", [])
	var allowed_rotations: Array = contract.get("allowed_rotations", [0])
	for profile_variant in supported_profiles:
		if typeof(profile_variant) != TYPE_ARRAY:
			continue
		var base_profile: Array = profile_variant
		for rotation_variant in allowed_rotations:
			var rotation_degrees := int(rotation_variant)
			var rotated_profile := _rotate_walls(base_profile, rotation_degrees)
			if not _is_wall_subset(rotated_profile, current_open_walls):
				continue
			var walls_to_prune := _subtract_wall_sets(current_open_walls, rotated_profile)
			if not allow_pruning and not walls_to_prune.is_empty():
				continue
			if not walls_to_prune.is_empty() and not _try_prune_room_walls(room.id, walls_to_prune):
				continue
			_set_room_assignment(room, scene, role, rotation_degrees, rotated_profile)
			return true
	return false

func _set_room_assignment(room: RoomData, scene: PackedScene, role: String, rotation_degrees: int, open_walls: Array) -> void:
	room.assigned_scene = scene
	room.assigned_scene_path = scene.resource_path
	room.assigned_scene_role = role
	room.chosen_rotation_degrees = rotation_degrees
	room.doorway_walls = _sort_wall_set(open_walls)

func _get_room_scene_contract(scene: PackedScene) -> Dictionary:
	if scene == null:
		return {}
	var cache_key := scene.resource_path if scene.resource_path != "" else str(scene.get_instance_id())
	if _room_scene_contract_cache.has(cache_key):
		return _room_scene_contract_cache[cache_key]

	var instance_variant: Variant = scene.instantiate()
	if not (instance_variant is Node3D):
		if instance_variant is Node:
			(instance_variant as Node).free()
		return {}
	var instance: Node3D = instance_variant
	var profile_strings := PackedStringArray()
	var role_tags := PackedStringArray()
	var rotation_values := PackedInt32Array([0])
	var has_player_spawn := instance.get_node_or_null("PlayerSpawn") != null
	var supports_runtime_doorways := false
	if instance.has_method("get_supported_doorway_profiles"):
		var profile_variant: Variant = instance.call("get_supported_doorway_profiles")
		if profile_variant is PackedStringArray:
			profile_strings = profile_variant
	if instance.has_method("get_room_role_tags"):
		var role_variant: Variant = instance.call("get_room_role_tags")
		if role_variant is PackedStringArray:
			role_tags = role_variant
	if instance.has_method("get_allowed_rotation_degrees"):
		var rotation_variant: Variant = instance.call("get_allowed_rotation_degrees")
		if rotation_variant is PackedInt32Array and not rotation_variant.is_empty():
			rotation_values = rotation_variant
	if instance is StandardDungeonRoom:
		supports_runtime_doorways = true
	elif instance.has_method("supports_runtime_doorway_configuration"):
		supports_runtime_doorways = bool(instance.call("supports_runtime_doorway_configuration"))
	else:
		supports_runtime_doorways = instance.has_method("configure_doorways") or instance.has_method("set_doorway_open")
	instance.free()
	if profile_strings.is_empty():
		push_error("DungeonManager: stitched room scene '%s' is missing supported doorway profile metadata." % scene.resource_path)
		return {}

	var contract := {
		"supports_any_profile": false,
		"supported_profiles": [],
		"allowed_rotations": [],
		"room_role_tags": role_tags,
		"default_rotation_degrees": 0,
		"has_player_spawn": has_player_spawn,
		"supports_runtime_doorways": supports_runtime_doorways,
	}
	var normalized_rotations: Array = []
	for rotation_variant in rotation_values:
		normalized_rotations.append(int(rotation_variant))
	if normalized_rotations.is_empty():
		normalized_rotations.append(0)
	contract["allowed_rotations"] = normalized_rotations
	contract["default_rotation_degrees"] = int(normalized_rotations[0])

	var parsed_profiles: Array = []
	for profile_string_variant in profile_strings:
		var profile_string := String(profile_string_variant).strip_edges().to_lower()
		if profile_string == "*":
			contract["supports_any_profile"] = true
			parsed_profiles.clear()
			break
		parsed_profiles.append(_parse_doorway_profile_string(profile_string))
	contract["supported_profiles"] = parsed_profiles
	_room_scene_contract_cache[cache_key] = contract
	return contract

func _parse_doorway_profile_string(profile_string: String) -> Array:
	if profile_string.is_empty():
		return []
	var walls: Array = []
	for part_variant in profile_string.split(","):
		var wall := String(part_variant).strip_edges().to_lower()
		if wall not in ["north", "south", "east", "west"]:
			continue
		if wall not in walls:
			walls.append(wall)
	return _sort_wall_set(walls)

func _get_room_open_walls(room: RoomData) -> Array:
	var walls: Array = []
	for neighbor_id_variant in room.connected_to:
		var neighbor_id := int(neighbor_id_variant)
		var neighbor: RoomData = _room_lookup.get(neighbor_id, null)
		if neighbor == null:
			continue
		var delta := neighbor.lattice_coord - room.lattice_coord
		if delta == Vector2i(0, -1):
			walls.append("north")
		elif delta == Vector2i(0, 1):
			walls.append("south")
		elif delta == Vector2i(1, 0):
			walls.append("east")
		elif delta == Vector2i(-1, 0):
			walls.append("west")
	return _sort_wall_set(walls)

func _rotate_walls(walls: Array, rotation_degrees: int) -> Array:
	var rotated: Array = []
	for wall_variant in walls:
		var rotated_wall := _rotate_wall_name(String(wall_variant), rotation_degrees)
		if rotated_wall not in rotated:
			rotated.append(rotated_wall)
	return _sort_wall_set(rotated)

func _rotate_wall_name(wall: String, rotation_degrees: int) -> String:
	var wall_order := ["north", "east", "south", "west"]
	var wall_index := wall_order.find(wall)
	if wall_index < 0:
		return wall
	var steps := int(posmod(rotation_degrees, 360) / 90)
	return wall_order[(wall_index + steps) % wall_order.size()]

func _is_wall_subset(candidate_walls: Array, current_open_walls: Array) -> bool:
	for wall_variant in candidate_walls:
		if String(wall_variant) not in current_open_walls:
			return false
	return true

func _subtract_wall_sets(source_walls: Array, walls_to_keep: Array) -> Array:
	var remainder: Array = []
	for wall_variant in source_walls:
		var wall := String(wall_variant)
		if wall not in walls_to_keep:
			remainder.append(wall)
	return _sort_wall_set(remainder)

func _sort_wall_set(walls: Array) -> Array:
	var order := {
		"north": 0,
		"east": 1,
		"south": 2,
		"west": 3,
	}
	var normalized: Array = []
	for wall_variant in walls:
		var wall := String(wall_variant)
		if wall == "" or wall in normalized:
			continue
		normalized.append(wall)
	normalized.sort_custom(func(a: String, b: String) -> bool:
		return int(order.get(a, 99)) < int(order.get(b, 99))
	)
	return normalized

func _try_prune_room_walls(room_id: int, walls_to_prune: Array) -> bool:
	if walls_to_prune.is_empty():
		return true
	var snapshot := _snapshot_topology_state()
	for wall_variant in walls_to_prune:
		if not _prune_room_wall(room_id, String(wall_variant)):
			_restore_topology_state(snapshot)
			return false
	if not _is_room_graph_connected():
		_restore_topology_state(snapshot)
		return false
	_rebuild_room_doorway_walls()
	return true

func _snapshot_topology_state() -> Dictionary:
	var room_state := {}
	for room_variant in _rooms:
		var room: RoomData = room_variant
		room_state[room.id] = {
			"connected_to": room.connected_to.duplicate(),
			"corridor_ids": room.corridor_ids.duplicate(),
			"doorway_ids": room.doorway_ids.duplicate(),
			"doorway_walls": room.doorway_walls.duplicate(),
		}
	return {
		"corridors": _generator.corridors.duplicate(true),
		"doorways": _generator.doorways.duplicate(true),
		"rooms": room_state,
	}

func _restore_topology_state(snapshot: Dictionary) -> void:
	if snapshot.is_empty():
		return
	_generator.corridors = snapshot.get("corridors", []).duplicate(true)
	_generator.doorways = snapshot.get("doorways", []).duplicate(true)
	var room_state: Dictionary = snapshot.get("rooms", {})
	for room_variant in _rooms:
		var room: RoomData = room_variant
		var state: Dictionary = room_state.get(room.id, {})
		room.connected_to = state.get("connected_to", []).duplicate()
		room.corridor_ids = state.get("corridor_ids", []).duplicate()
		room.doorway_ids = state.get("doorway_ids", []).duplicate()
		room.doorway_walls = state.get("doorway_walls", []).duplicate()

func _prune_room_wall(room_id: int, wall: String) -> bool:
	var room: RoomData = _room_lookup.get(room_id, null)
	if room == null:
		return false
	var neighbor_id := _get_neighbor_id_for_wall(room, wall)
	if neighbor_id < 0:
		return false
	var corridor_id := _find_corridor_id_between_rooms(room_id, neighbor_id)
	if corridor_id < 0:
		return false
	room.connected_to.erase(neighbor_id)
	room.corridor_ids.erase(corridor_id)
	var neighbor: RoomData = _room_lookup.get(neighbor_id, null)
	if neighbor != null:
		neighbor.connected_to.erase(room_id)
		neighbor.corridor_ids.erase(corridor_id)
	_generator.corridors = _generator.corridors.filter(func(entry: Dictionary) -> bool:
		return int(entry.get("id", -1)) != corridor_id
	)
	var removed_doorway_ids: Array = []
	_generator.doorways = _generator.doorways.filter(func(entry: Dictionary) -> bool:
		var keep := int(entry.get("corridor_id", -1)) != corridor_id
		if not keep:
			removed_doorway_ids.append(int(entry.get("id", -1)))
		return keep
	)
	for doorway_id_variant in removed_doorway_ids:
		var doorway_id := int(doorway_id_variant)
		room.doorway_ids.erase(doorway_id)
		if neighbor != null:
			neighbor.doorway_ids.erase(doorway_id)
	return true

func _get_neighbor_id_for_wall(room: RoomData, wall: String) -> int:
	for neighbor_id_variant in room.connected_to:
		var neighbor_id := int(neighbor_id_variant)
		var neighbor: RoomData = _room_lookup.get(neighbor_id, null)
		if neighbor == null:
			continue
		var delta := neighbor.lattice_coord - room.lattice_coord
		if wall == "north" and delta == Vector2i(0, -1):
			return neighbor_id
		if wall == "south" and delta == Vector2i(0, 1):
			return neighbor_id
		if wall == "east" and delta == Vector2i(1, 0):
			return neighbor_id
		if wall == "west" and delta == Vector2i(-1, 0):
			return neighbor_id
	return -1

func _find_corridor_id_between_rooms(room_a_id: int, room_b_id: int) -> int:
	for corridor_variant in _generator.corridors:
		if typeof(corridor_variant) != TYPE_DICTIONARY:
			continue
		var corridor: Dictionary = corridor_variant
		var a_id := int(corridor.get("room_a_id", -1))
		var b_id := int(corridor.get("room_b_id", -1))
		if (a_id == room_a_id and b_id == room_b_id) or (a_id == room_b_id and b_id == room_a_id):
			return int(corridor.get("id", -1))
	return -1

func _is_room_graph_connected() -> bool:
	if _rooms.is_empty():
		return true
	var visited := {}
	var start_room := _get_room_by_type(RoomData.RoomType.START)
	var start_id := start_room.id if start_room != null else int((_rooms[0] as RoomData).id)
	var queue: Array = [start_id]
	var index := 0
	visited[start_id] = true
	while index < queue.size():
		var room_id := int(queue[index])
		index += 1
		var room: RoomData = _room_lookup.get(room_id, null)
		if room == null:
			continue
		for neighbor_id_variant in room.connected_to:
			var neighbor_id := int(neighbor_id_variant)
			if visited.has(neighbor_id):
				continue
			visited[neighbor_id] = true
			queue.append(neighbor_id)
	return visited.size() == _rooms.size()

func _rebuild_room_doorway_walls() -> void:
	var doorway_walls_by_room := {}
	for doorway_variant in _generator.doorways:
		if typeof(doorway_variant) != TYPE_DICTIONARY:
			continue
		var doorway: Dictionary = doorway_variant
		var room_id := int(doorway.get("room_id", -1))
		var room: RoomData = _room_lookup.get(room_id, null)
		if room == null:
			continue
		var tile: Vector2i = doorway.get("tile", Vector2i.ZERO)
		var rect := room.grid_rect
		var wall := ""
		if tile.x <= rect.position.x:
			wall = "west"
		elif tile.x >= rect.position.x + rect.size.x - 1:
			wall = "east"
		elif tile.y <= rect.position.y:
			wall = "north"
		elif tile.y >= rect.position.y + rect.size.y - 1:
			wall = "south"
		if wall == "":
			continue
		if not doorway_walls_by_room.has(room_id):
			doorway_walls_by_room[room_id] = []
		if wall not in doorway_walls_by_room[room_id]:
			doorway_walls_by_room[room_id].append(wall)
	for room_variant in _rooms:
		var room: RoomData = room_variant
		room.doorway_walls = _sort_wall_set(doorway_walls_by_room.get(room.id, []))

func _get_packed_scene_property(resource: Resource, property_name: String) -> PackedScene:
	if resource == null or not _resource_has_property(resource, property_name):
		return null
	var value: Variant = resource.get(property_name)
	if value is PackedScene:
		return value
	return null

func _get_packed_scene_array_property(resource: Resource, property_name: String) -> Array:
	var scenes: Array = []
	if resource == null or not _resource_has_property(resource, property_name):
		return scenes
	var value: Variant = resource.get(property_name)
	if typeof(value) != TYPE_ARRAY:
		return scenes
	for scene_variant in value:
		if scene_variant is PackedScene:
			scenes.append(scene_variant)
	return scenes

func _shuffle_array(values: Array, rng: RandomNumberGenerator) -> void:
	if rng == null:
		return
	for index in range(values.size() - 1, 0, -1):
		var swap_index := rng.randi_range(0, index)
		var temp: Variant = values[index]
		values[index] = values[swap_index]
		values[swap_index] = temp

func _post_process_stitched_rooms() -> void:
	if _stitcher == null:
		return
	for room_variant in _rooms:
		var room: RoomData = room_variant
		var instance := _stitcher.get_room_instance(room.id)
		if not is_instance_valid(instance):
			continue
		_hide_room_debug_nodes(instance)
		_room_instances_by_id[room.id] = instance
		_configure_handcrafted_room_overlay(room, instance)

func _hide_room_debug_nodes(room_overlay: Node3D) -> void:
	if room_overlay == null or Engine.is_editor_hint():
		return
	var debug_root := room_overlay.get_node_or_null("RoomBoundsDebug") as Node3D
	if debug_root != null:
		debug_root.visible = false

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
	var spawned_enemies: Array = []
	var room_overlay = _room_instances_by_id.get(room_id, null)
	var handcrafted_spawners := _collect_handcrafted_enemy_spawners(room_overlay)
	if not handcrafted_spawners.is_empty():
		spawned_enemies = _encounter.populate_handcrafted_spawners(
			room,
			floor_number,
			nav_region,
			_active_dungeon_content,
			handcrafted_spawners
		)
	else:
		spawned_enemies = _encounter.populate_room(room, floor_number, nav_region, _active_dungeon_content)
	_configure_handcrafted_room_enemy_behavior(room, spawned_enemies)
	if not _session_multiplayer or not _session_host:
		return
	for enemy_variant in spawned_enemies:
		if not (enemy_variant is EnemyBase):
			continue
		var enemy: EnemyBase = enemy_variant
		_register_network_enemy(enemy)

func _find_room_id_for_world_position(world_pos: Vector3) -> int:
	var tx := int(floor(world_pos.x / TILE_SIZE))
	var tz := int(floor(world_pos.z / TILE_SIZE))
	for room_variant in _rooms:
		var room: RoomData = room_variant
		var rect := room.grid_rect
		if tx >= rect.position.x and tx < rect.position.x + rect.size.x \
			and tz >= rect.position.y and tz < rect.position.y + rect.size.y:
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

func _request_host_sync() -> void:
	if _session_multiplayer and not _session_host:
		_floor_sync_in_progress = true
		_pending_player_roster.clear()
		_pending_enemy_spawns.clear()
		rpc_id(1, "rpc_client_ready_for_sync", _local_peer_id)

func _sync_player_roster_to_clients() -> void:
	if not _session_multiplayer or not _session_host:
		return
	for peer_id in _get_network_connected_peer_ids():
		if not _is_peer_floor_sync_ready(peer_id):
			continue
		NetworkPlayerManager.sync_roster_to(peer_id)

func _mark_all_clients_floor_not_ready() -> void:
	_floor_sync_ready_by_peer.clear()
	for peer_id in _get_network_connected_peer_ids():
		_floor_sync_ready_by_peer[int(peer_id)] = false

func _build_floor_sync_config() -> Dictionary:
	return {
		"grid_size_min": grid_size_min,
		"grid_size_max": grid_size_max,
		"min_start_end_distance_rooms": min_start_end_distance_rooms,
		"room_size_tiles": room_size_tiles,
		"corridor_width_tiles": corridor_width_tiles,
		"corridor_length_tiles": corridor_length_tiles,
	}

func _apply_floor_sync_config(floor_cfg: Dictionary) -> void:
	if floor_cfg.is_empty():
		return
	grid_size_min = int(floor_cfg.get("grid_size_min", grid_size_min))
	grid_size_max = maxi(int(floor_cfg.get("grid_size_max", grid_size_max)), grid_size_min)
	min_start_end_distance_rooms = int(floor_cfg.get("min_start_end_distance_rooms", min_start_end_distance_rooms))
	room_size_tiles = int(floor_cfg.get("room_size_tiles", room_size_tiles))
	corridor_width_tiles = int(floor_cfg.get("corridor_width_tiles", corridor_width_tiles))
	corridor_length_tiles = int(floor_cfg.get("corridor_length_tiles", corridor_length_tiles))
	GameState.dungeon_grid_min = grid_size_min
	GameState.dungeon_grid_max = grid_size_max
	GameState.dungeon_seed = generation_seed

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
	NetworkPlayerManager.sync_roster_to(peer_id)

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
	NetworkPlayerManager.apply_roster(roster)

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
		var local_player = NetworkPlayerManager.get_local_player()
		if is_instance_valid(local_player):
			return local_player
	for player_variant in get_tree().get_nodes_in_group("player"):
		if player_variant is Node3D and is_instance_valid(player_variant):
			return player_variant
	return null

func _get_player_node_for_peer(peer_id: int) -> Node3D:
	var player = NetworkPlayerManager.get_player(peer_id)
	if player is Node3D and is_instance_valid(player):
		return player
	return null

func _configure_handcrafted_room_overlay(room: RoomData, room_overlay: Node3D) -> void:
	if room == null or room_overlay == null:
		return
	if room.assigned_scene_path != CASTLE_INNER_CHAMBER_SCENE_PATH:
		return
	var door := room_overlay.get_node_or_null("InnerDoorway/Door") as DungeonDoor
	if door == null:
		push_warning("DungeonManager: castle inner chamber missing InnerDoorway/Door for room %d." % room.id)
		return
	var open_cb := Callable(self, "_on_inner_chamber_door_opened").bind(room.id)
	if not door.is_connected("door_opened", open_cb):
		door.connect("door_opened", open_cb)

func _configure_handcrafted_room_enemy_behavior(room: RoomData, spawned_enemies: Array) -> void:
	if room == null or room.assigned_scene_path != CASTLE_INNER_CHAMBER_SCENE_PATH:
		return
	var room_overlay = _room_instances_by_id.get(room.id, null)
	if not is_instance_valid(room_overlay):
		return
	var door := room_overlay.get_node_or_null("InnerDoorway/Door") as DungeonDoor
	if door != null and door.is_open:
		return
	var suppressed: Array = _suppressed_enemies_by_room_id.get(room.id, [])
	for enemy_variant in spawned_enemies:
		if not (enemy_variant is EnemyBase):
			continue
		var enemy: EnemyBase = enemy_variant
		if not _is_inside_castle_inner_chamber(enemy.global_position, room_overlay):
			continue
		enemy.set_aggro_suppressed(true)
		suppressed.append(enemy)
	_suppressed_enemies_by_room_id[room.id] = suppressed

func _is_inside_castle_inner_chamber(enemy_world_pos: Vector3, room_overlay: Node3D) -> bool:
	if room_overlay == null:
		return false
	var local_pos := room_overlay.to_local(enemy_world_pos)
	return abs(local_pos.x) <= 11.5 and local_pos.z >= -11.5 and local_pos.z <= 11.5

func _collect_handcrafted_enemy_spawners(root: Node) -> Array:
	var spawners: Array = []
	if root == null or not is_instance_valid(root):
		return spawners
	var stack: Array = [root]
	while not stack.is_empty():
		var current_variant = stack.pop_back()
		if not (current_variant is Node):
			continue
		var current: Node = current_variant
		if current is HandcraftedEnemySpawner:
			spawners.append(current)
		for child in current.get_children():
			stack.append(child)
	return spawners

func _on_inner_chamber_door_opened(_door: DungeonDoor, room_id: int) -> void:
	var suppressed: Array = _suppressed_enemies_by_room_id.get(room_id, [])
	for enemy_variant in suppressed:
		if enemy_variant is EnemyBase and is_instance_valid(enemy_variant):
			var enemy: EnemyBase = enemy_variant
			enemy.set_aggro_suppressed(false)
	_suppressed_enemies_by_room_id.erase(room_id)

func _build_spawn_positions(base_pos: Vector3, _look_target: Vector3, player_count: int) -> Array[Vector3]:
	var positions: Array[Vector3] = []
	var desired_count := maxi(1, player_count)
	for index in range(desired_count):
		var candidate := _offset_spawn_position(base_pos, index)
		var snapped_candidate_variant: Variant = _snap_spawn_to_floor(candidate)
		var snapped_candidate: Vector3 = snapped_candidate_variant if snapped_candidate_variant is Vector3 else candidate
		positions.append(snapped_candidate)
	return positions

func _offset_spawn_position(base_pos: Vector3, player_index: int) -> Vector3:
	if player_index <= 0:
		return base_pos
	var offset_distance := 2.0
	match player_index:
		1:
			return base_pos + Vector3(offset_distance, 0.0, 0.0)
		2:
			return base_pos + Vector3(-offset_distance, 0.0, 0.0)
		3:
			return base_pos + Vector3(0.0, 0.0, offset_distance)
		4:
			return base_pos + Vector3(0.0, 0.0, -offset_distance)
		_:
			var ring := int(floor(float(player_index - 1) / 4.0)) + 1
			var lane := int((player_index - 1) % 4)
			var scaled_distance := offset_distance * float(ring)
			match lane:
				0:
					return base_pos + Vector3(scaled_distance, 0.0, 0.0)
				1:
					return base_pos + Vector3(-scaled_distance, 0.0, 0.0)
				2:
					return base_pos + Vector3(0.0, 0.0, scaled_distance)
				_:
					return base_pos + Vector3(0.0, 0.0, -scaled_distance)

func _snap_spawn_to_floor(candidate: Vector3) -> Variant:
	var space_state := get_world_3d().direct_space_state
	if space_state == null:
		return null
	var query := PhysicsRayQueryParameters3D.create(candidate + Vector3.UP * 4.0, candidate + Vector3.DOWN * 6.0)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var result := space_state.intersect_ray(query)
	if result.is_empty():
		return null
	var hit_pos: Vector3 = result.get("position", candidate)
	var hit_normal: Vector3 = result.get("normal", Vector3.UP)
	if hit_normal.dot(Vector3.UP) < 0.6:
		return null
	return Vector3(candidate.x, hit_pos.y + 1.0, candidate.z)

func _get_network_session():
	return get_node_or_null("/root/NetworkSession")

func _is_verifier_run() -> bool:
	return OS.get_cmdline_user_args().has("--verify-scenario")

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
	for peer_id in _get_network_connected_peer_ids():
		_sync_floor_to_peer(int(peer_id), false)

func _sync_floor_to_peer(peer_id: int, reset_ready: bool = true) -> void:
	if not _session_multiplayer or not _session_host:
		return
	if peer_id <= 1:
		return
	if reset_ready:
		_set_peer_floor_sync_ready(peer_id, false)
	rpc_id(peer_id, "rpc_sync_floor_state", floor_number, generation_seed, _build_floor_sync_config())

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

func request_weapon_switch(peer_id: int, weapon_slot: int, weapon_key: String) -> void:
	if not _session_multiplayer:
		return
	if _session_host:
		_handle_weapon_switch_request(peer_id, weapon_slot, weapon_key)
	else:
		rpc_id(1, "rpc_request_weapon_switch", peer_id, weapon_slot, weapon_key)

func broadcast_projectile_visual(scene_path: String, shooter_peer_id: int, origin: Vector3, cam_forward: Vector3) -> void:
	if not _session_multiplayer or not _session_host:
		return
	if scene_path.is_empty() or shooter_peer_id <= 0:
		return
	rpc("rpc_spawn_projectile_visual", shooter_peer_id, scene_path, origin, cam_forward)

func broadcast_weapon_fire_visual(peer_id: int, muzzle_pos: Vector3) -> void:
	if not _session_multiplayer or not _session_host:
		return
	if peer_id <= 0:
		return
	rpc("rpc_spawn_weapon_fire_visual", peer_id, muzzle_pos)

func _handle_weapon_fire_request(peer_id: int, weapon_slot: int, weapon_key: String, cam_origin: Vector3, cam_forward: Vector3, _shot_id: int) -> void:
	var player_node = _get_player_node_for_peer(peer_id)
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
	if weapon == null:
		return
	if not weapon.has_method("fire_authoritative_from_network"):
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
	var player_node = _get_player_node_for_peer(peer_id)
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
	if weapon == null:
		return
	if not weapon.has_method("perform_authoritative_reload"):
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
	var player_node = _get_player_node_for_peer(peer_id)
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

func request_drop_inventory_item(peer_id: int, slot_payload: Dictionary, drop_origin: Vector3, launch_direction: Vector3) -> void:
	if not _session_multiplayer or _session_host:
		_handle_drop_inventory_item_request(peer_id, slot_payload, drop_origin, launch_direction)
		return
	rpc_id(1, "rpc_request_drop_inventory_item", peer_id, slot_payload, drop_origin, launch_direction)

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
	if target is LootPickup:
		var loot_id := int(target.get_meta("network_loot_id", -1))
		var interactor_peer := _local_peer_id
		if interactor != null and interactor.has_method("get_network_peer_id"):
			interactor_peer = int(interactor.call("get_network_peer_id"))
		target.interact(interactor)
		if _session_multiplayer and _session_host and interactor_peer != _local_peer_id:
			_sync_pickup_state_to_peer(interactor_peer, interactor)
		if loot_id >= 0 and (not is_instance_valid(target) or target.is_queued_for_deletion()):
			_loot_pickup_by_network_id.erase(loot_id)
			if _session_multiplayer and _session_host:
				rpc("rpc_despawn_loot_pickup", loot_id)
		return
	if target.has_method("interact"):
		target.interact(interactor)

func _sync_pickup_state_to_peer(peer_id: int, interactor: Node) -> void:
	if peer_id <= 0 or not _session_multiplayer or not _session_host:
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
	var loot := _find_loot_pickup_by_position(world_pos)
	if loot != null:
		return loot
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
	var local_player = NetworkPlayerManager.get_local_player()
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

func spawn_network_item_pickup(item_payload: Dictionary, drop_origin: Vector3, launch_direction: Vector3) -> void:
	if _session_multiplayer and not _session_host:
		return
	var payload := {
		"kind": "item",
		"item_data": item_payload.duplicate(true),
		"drop_origin": drop_origin,
		"launch_direction": launch_direction,
	}
	_spawn_network_loot_pickup(payload, true)

func spawn_network_ammo_pickup(ammo_type: String, ammo_amount: int, display_name: String, icon_path: String, drop_origin: Vector3, launch_direction: Vector3) -> void:
	if _session_multiplayer and not _session_host:
		return
	var payload := {
		"kind": "ammo",
		"ammo_type": ammo_type,
		"ammo_amount": ammo_amount,
		"display_name": display_name,
		"icon_path": icon_path,
		"drop_origin": drop_origin,
		"launch_direction": launch_direction,
	}
	_spawn_network_loot_pickup(payload, true)

func spawn_network_health_pickup(health_amount: int, display_name: String, icon_path: String, drop_origin: Vector3, launch_direction: Vector3) -> void:
	if _session_multiplayer and not _session_host:
		return
	var payload := {
		"kind": "health",
		"health_amount": health_amount,
		"display_name": display_name,
		"icon_path": icon_path,
		"drop_origin": drop_origin,
		"launch_direction": launch_direction,
	}
	_spawn_network_loot_pickup(payload, true)

func _spawn_network_loot_pickup(payload: Dictionary, play_launch: bool) -> void:
	var pickup := _instantiate_loot_pickup_from_payload(payload, play_launch)
	if pickup == null:
		return
	var loot_id := _register_network_loot_pickup(pickup)
	var sync_payload := _build_loot_pickup_payload(pickup)
	if _session_multiplayer and _session_host:
		for peer_id in _get_network_connected_peer_ids():
			if not _is_peer_floor_sync_ready(peer_id):
				continue
			rpc_id(peer_id, "rpc_spawn_loot_pickup", loot_id, sync_payload, play_launch)

func _instantiate_loot_pickup_from_payload(payload: Dictionary, play_launch: bool) -> LootPickup:
	var pickup_variant: Variant = LOOT_PICKUP_SCENE.instantiate()
	if not (pickup_variant is LootPickup):
		if pickup_variant is Node:
			(pickup_variant as Node).queue_free()
		return null
	var pickup: LootPickup = pickup_variant
	var kind := String(payload.get("kind", ""))
	match kind:
		"item":
			var item_payload: Dictionary = payload.get("item_data", {})
			var item_data := InventoryItemData.from_dict(item_payload)
			if item_data == null:
				pickup.queue_free()
				return null
			pickup.configure_item_pickup(item_data)
		"ammo":
			pickup.configure_ammo_pickup(
				String(payload.get("ammo_type", "")),
				int(payload.get("ammo_amount", 0)),
				String(payload.get("display_name", "Ammo")),
				String(payload.get("icon_path", ""))
			)
		"health":
			pickup.configure_health_pickup(
				int(payload.get("health_amount", 0)),
				String(payload.get("display_name", "Health Pickup")),
				String(payload.get("icon_path", ""))
			)
		_:
			pickup.queue_free()
			return null
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
	pickup.name = "NetworkLootPickup_%d" % loot_id
	return loot_id

func _build_loot_pickup_payload(pickup: LootPickup) -> Dictionary:
	if pickup == null:
		return {}
	var payload := {
		"drop_origin": pickup.global_position,
		"launch_direction": Vector3.ZERO,
		"settled_position": pickup.global_position,
	}
	if pickup._is_health_pickup():
		payload["kind"] = "health"
		payload["health_amount"] = pickup.health_amount
		payload["display_name"] = pickup.health_display_name
		payload["icon_path"] = pickup.health_icon_path
	elif pickup._is_ammo_pickup():
		payload["kind"] = "ammo"
		payload["ammo_type"] = pickup.ammo_type
		payload["ammo_amount"] = pickup.ammo_amount
		payload["display_name"] = pickup.ammo_display_name
		payload["icon_path"] = pickup.ammo_icon_path
	else:
		payload["kind"] = "item"
		payload["item_data"] = pickup.get_item_snapshot()
	return payload

func _send_all_loot_pickups_to_peer(peer_id: int) -> void:
	for loot_id_variant in _loot_pickup_by_network_id.keys():
		var loot_id := int(loot_id_variant)
		var pickup = _loot_pickup_by_network_id.get(loot_id, null)
		if not is_instance_valid(pickup):
			continue
		rpc_id(peer_id, "rpc_spawn_loot_pickup", loot_id, _build_loot_pickup_payload(pickup), false)

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
	_sync_floor_to_peer(peer_id)

func _on_network_peer_left(peer_id: int) -> void:
	if not _session_host:
		return
	_remove_peer_from_chest_views(peer_id)
	_floor_sync_ready_by_peer.erase(peer_id)

func _on_network_session_ended(_reason: String) -> void:
	if not _session_multiplayer:
		return
	_session_multiplayer = false
	_session_host = true
	get_tree().change_scene_to_file("res://Scenes/System/bootstrap.tscn")

func _reset_debug_network_visual_counts() -> void:
	_debug_network_visual_counts["hitscan"] = 0
	_debug_network_visual_counts["projectile"] = 0
	_debug_network_visual_counts["weapon_fire"] = 0

func get_debug_network_visual_counts() -> Dictionary:
	return _debug_network_visual_counts.duplicate(true)

func get_debug_network_enemy_states() -> Array:
	var result: Array = []
	for enemy_id_variant in _enemy_by_network_id.keys():
		var enemy_id := int(enemy_id_variant)
		var enemy = _enemy_by_network_id.get(enemy_id, null)
		if not is_instance_valid(enemy):
			continue
		var snapshot: Dictionary = {}
		if enemy.has_method("get_network_state_snapshot"):
			snapshot = enemy.call("get_network_state_snapshot")
		result.append({
			"id": enemy_id,
			"position": snapshot.get("position", enemy.global_position),
			"velocity": snapshot.get("velocity", Vector3.ZERO),
			"health": int(snapshot.get("health", 0)),
			"state": int(snapshot.get("state", 0)),
			"anim_frame": int(snapshot.get("anim_frame", 0)),
			"animating": bool(snapshot.get("animating", false)),
			"is_proxy": enemy.has_method("is_network_proxy_mode") and bool(enemy.call("is_network_proxy_mode")),
			"path": String(enemy.get_path()),
		})
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("id", 0)) < int(b.get("id", 0))
	)
	return result

@rpc("any_peer", "reliable")
func rpc_client_ready_for_sync(peer_id: int) -> void:
	if not _session_host:
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender != peer_id:
		return
	_sync_floor_to_peer(peer_id)

@rpc("authority", "call_remote", "reliable")
func rpc_sync_floor_state(remote_floor: int, remote_seed: int, floor_cfg: Dictionary = {}) -> void:
	if _session_host:
		return
	floor_number = remote_floor
	generation_seed = remote_seed
	_apply_floor_sync_config(floor_cfg)
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
	_send_all_loot_pickups_to_peer(peer_id)

@rpc("any_peer", "reliable")
func rpc_request_weapon_fire(peer_id: int, weapon_slot: int, weapon_key: String, cam_origin: Vector3, cam_forward: Vector3, shot_id: int) -> void:
	if not _session_host:
		return
	if multiplayer.get_remote_sender_id() != peer_id:
		return
	_handle_weapon_fire_request(peer_id, weapon_slot, weapon_key, cam_origin, cam_forward, shot_id)

@rpc("any_peer", "reliable")
func rpc_request_weapon_switch(peer_id: int, weapon_slot: int, weapon_key: String) -> void:
	if not _session_host:
		return
	if multiplayer.get_remote_sender_id() != peer_id:
		return
	_handle_weapon_switch_request(peer_id, weapon_slot, weapon_key)

func broadcast_hitscan_visual(shooter_peer_id: int, from: Vector3, to: Vector3) -> void:
	if not _session_multiplayer or not _session_host:
		return
	if shooter_peer_id <= 0:
		return
	rpc("rpc_spawn_hitscan_visual", shooter_peer_id, from, to)

@rpc("any_peer", "reliable")
func rpc_request_weapon_reload(peer_id: int, weapon_slot: int, weapon_key: String) -> void:
	if not _session_host:
		return
	if multiplayer.get_remote_sender_id() != peer_id:
		return
	_handle_weapon_reload_request(peer_id, weapon_slot, weapon_key)

@rpc("authority", "call_remote", "reliable")
func rpc_sync_weapon_state(peer_id: int, slot_index: int, current_mag: int, ammo_snapshot: Dictionary, weapon_key: String = "") -> void:
	if _local_peer_id != peer_id:
		return
	var local_player = NetworkPlayerManager.get_local_player()
	if not is_instance_valid(local_player):
		return
	var manager: WeaponManager = local_player.get("weapon_manager")
	if manager == null:
		return
	manager.apply_authoritative_weapon_state(slot_index, current_mag, ammo_snapshot, weapon_key)

@rpc("authority", "call_remote", "reliable")
func rpc_sync_pickup_state(peer_id: int, inventory_snapshot: Dictionary, health: int, weapon_slot: int, current_mag: int, ammo_snapshot: Dictionary, weapon_key: String = "") -> void:
	if _local_peer_id != peer_id:
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
func rpc_request_interaction(peer_id: int, target_path: String, target_pos: Vector3 = Vector3.ZERO) -> void:
	if not _session_host:
		return
	if multiplayer.get_remote_sender_id() != peer_id:
		return
	var interactor = _get_player_node_for_peer(peer_id)
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
func rpc_request_drop_inventory_item(peer_id: int, slot_payload: Dictionary, drop_origin: Vector3, launch_direction: Vector3) -> void:
	if not _session_host:
		return
	if multiplayer.get_remote_sender_id() != peer_id:
		return
	_handle_drop_inventory_item_request(peer_id, slot_payload, drop_origin, launch_direction)

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

func _handle_drop_inventory_item_request(peer_id: int, slot_payload: Dictionary, drop_origin: Vector3, launch_direction: Vector3) -> void:
	var player = _get_player_node_for_peer(peer_id)
	if not is_instance_valid(player):
		return
	var inventory_system: InventorySystem = player.get("inventory_system") as InventorySystem
	if inventory_system == null:
		return
	var slot_ref: SlotRef = inventory_system.call("_slot_ref_from_payload", slot_payload)
	if slot_ref == null:
		return
	var show_toast := not _session_multiplayer or peer_id == _local_peer_id
	var dropped: bool = bool(inventory_system.call("_drop_item_to_world", slot_ref, drop_origin, launch_direction, show_toast))
	if not dropped:
		return
	if _session_multiplayer and _session_host and peer_id != _local_peer_id:
		_sync_pickup_state_to_peer(peer_id, player)

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

@rpc("authority", "call_local", "reliable")
func rpc_spawn_projectile_visual(shooter_peer_id: int, scene_path: String, origin: Vector3, cam_forward: Vector3) -> void:
	if shooter_peer_id == _local_peer_id:
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
	if shooter_peer_id == _local_peer_id:
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
	var cleanup_tree := get_tree()
	if cleanup_tree == null:
		return
	await cleanup_tree.create_timer(0.06).timeout
	if is_instance_valid(flash_mesh):
		flash_mesh.queue_free()

@rpc("authority", "call_local", "reliable")
func rpc_spawn_hitscan_visual(shooter_peer_id: int, from: Vector3, to: Vector3) -> void:
	if shooter_peer_id == _local_peer_id:
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

	var temp_tracer := MeshInstance3D.new()
	temp_tracer.mesh = t_mesh
	temp_tracer.material_override = mat
	temp_tracer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var current_scene := get_tree().current_scene
	if current_scene == null:
		temp_tracer.queue_free()
		return
	current_scene.add_child(temp_tracer)
	temp_tracer.add_to_group("network_replicated_hitscan_visual")
	_debug_network_visual_counts["hitscan"] = int(_debug_network_visual_counts.get("hitscan", 0)) + 1

	temp_tracer.global_position = (from + to) / 2.0
	temp_tracer.look_at(to, Vector3.UP)
	temp_tracer.rotate_object_local(Vector3.RIGHT, -PI / 2.0)

	await get_tree().create_timer(0.05).timeout
	if is_instance_valid(temp_tracer):
		temp_tracer.queue_free()

## Spawns the Death Knight beam visual on all remote clients.
## The host already spawns it inside death_knight_boss._fire_beam(), so
## this RPC uses call_remote (skips host) to avoid a duplicate beam.
@rpc("authority", "call_remote", "reliable")
func rpc_spawn_enemy_beam_visual(spawn_pos: Vector3, direction: Vector3, beam_length: float) -> void:
	if _session_host:
		return
	var beam_scene: PackedScene = load("res://Scenes/Projectiles/death_knight_beam.tscn")
	if beam_scene == null:
		return
	var beam: Node3D = beam_scene.instantiate()
	beam.set("beam_length", maxf(0.5, beam_length))
	var scene_root := get_tree().current_scene
	if scene_root == null:
		beam.queue_free()
		return
	scene_root.add_child(beam)
	beam.global_position = spawn_pos
	if not direction.is_zero_approx():
		beam.look_at(spawn_pos + direction, Vector3.UP)

@rpc("authority", "call_remote", "reliable")
func rpc_despawn_enemy(enemy_id: int) -> void:
	var enemy = _enemy_by_network_id.get(enemy_id, null)
	if is_instance_valid(enemy):
		enemy.queue_free()
	_enemy_by_network_id.erase(enemy_id)

@rpc("authority", "call_remote", "reliable")
func rpc_spawn_loot_pickup(loot_id: int, payload: Dictionary, play_launch: bool = true) -> void:
	if _session_host:
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
