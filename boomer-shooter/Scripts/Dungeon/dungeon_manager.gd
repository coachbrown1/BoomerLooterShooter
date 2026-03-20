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

const SNAPSHOT_INTERVAL: float = 0.05
const CASTLE_INNER_CHAMBER_SCENE_PATH := "res://Scenes/Dungeon/Handcrafted/Castle_InnerChamber.tscn"
const LOOT_PICKUP_SCENE: PackedScene = preload("res://Scenes/Props/loot_pickup.tscn")
const VERIFIER_DEFAULT_DUNGEON_SEED := 1773666431

var _generator: DungeonGenerator
var _builder: DungeonBuilder
var _encounter: EncounterSystem
var _rooms: Array = []
var _active_biome_data: Resource = null
var _room_lookup := {}
var _room_tile_owner := {}
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
var _handcrafted_room_overlays_by_id := {}
var _suppressed_enemies_by_room_id := {}
var _players_ready_callback: Callable = Callable()
var _pending_inventory_restore: bool = false
var _debug_network_visual_counts := {
	"hitscan": 0,
	"projectile": 0,
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
	_room_tile_owner = {}
	_spawned_enemy_rooms = {}
	_last_player_room_id = -1
	_active_biome_data = null
	_chest_viewers_by_path.clear()
	_enemy_by_network_id.clear()
	_enemy_network_id_by_instance_id.clear()
	_next_enemy_network_id = 1
	_loot_pickup_by_network_id.clear()
	_next_loot_pickup_network_id = 1
	_handcrafted_room_overlays_by_id.clear()
	_suppressed_enemies_by_room_id.clear()
	_reset_debug_network_visual_counts()

	# Generate tile layout
	_generator = DungeonGenerator.new()
	_generator.biome_override = GameState.dungeon_biome_override
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
	_room_tile_owner = _generator._room_tile_owner

	var biome_id := "crypt"
	if _rooms.size() > 0:
		biome_id = _rooms[0].biome
	var biome_data = _get_biome_data(biome_id)
	_active_biome_data = biome_data
	_assign_handcrafted_layouts(biome_data)

	_update_environment(biome_data)

	# Build 3D geometry inside the NavigationRegion3D
	_builder = DungeonBuilder.new()
	_builder.build(
		_generator.tile_grid,
		_rooms,
		_generator.corridors,
		_generator.doorways,
		nav_region,
		biome_data,
		_generator._room_tile_owner,
		_generator._corridor_tile_owner,
		generation_seed
	)
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
	_room_tile_owner = {}
	_spawned_enemy_rooms = {}
	_last_player_room_id = -1
	_encounter = null
	_handcrafted_room_overlays_by_id.clear()
	_suppressed_enemies_by_room_id.clear()

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
		var scene_tag := ""
		if room.has_handcrafted_layout and room.handcrafted_scene_path != "":
			var scene_name := room.handcrafted_scene_path.get_file().get_basename()
			scene_tag = " | %s" % scene_name
		var label := "%s%s%s | room %d | lattice (%d,%d)" % [
			type_name,
			handcrafted_tag,
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
	var spawn_data := _get_start_player_spawn_data(start_room)
	var base_pos: Vector3 = spawn_data.get("position", start_room.get_world_center(DungeonBuilder.TILE_SIZE)) as Vector3
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
	var fallback_pos := start_room.get_world_center(DungeonBuilder.TILE_SIZE)
	var fallback_look_target := fallback_pos + Vector3(0.0, 0.0, 1.0)
	var room_overlay = _handcrafted_room_overlays_by_id.get(start_room.id, null)
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
	var look_target: Vector3 = spawn_pos + room_overlay.global_basis * Vector3(0.0, 0.0, 1.0)
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

func _place_exit(_biome_data: Resource = null) -> void:
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
	var tile_size: float = DungeonBuilder.TILE_SIZE
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
		_configure_runtime_handcrafted_room(room, room_overlay)
		_convert_handcrafted_wall_tiles_to_sections(room_overlay)
		room_overlay.position = room.get_world_center(DungeonBuilder.TILE_SIZE)
		room_overlay.position.y = 0.0
		_apply_handcrafted_room_orientation(room, room_overlay)
		_apply_handcrafted_room_position_offset(room, room_overlay)
		room_overlay.set_meta("room_id", room.id)
		room_overlay.set_meta("room_type", room.room_type)
		room_overlay.set_meta("lattice_coord", room.lattice_coord)
		root.add_child(room_overlay)
		_handcrafted_room_overlays_by_id[room.id] = room_overlay
		_configure_handcrafted_room_overlay(room, room_overlay)

func _configure_runtime_handcrafted_room(room: RoomData, room_overlay: Node3D) -> void:
	if room == null or room_overlay == null:
		return
	if not (room_overlay is HandcraftedQuadrantCompositeRoom):
		return
	var quadrant_pool := _get_handcrafted_quadrant_scene_pool(_active_biome_data)
	var composite_room: HandcraftedQuadrantCompositeRoom = room_overlay
	composite_room.populate_quadrants(quadrant_pool, _generator.rng)

func _convert_handcrafted_wall_tiles_to_sections(room_overlay: Node3D) -> void:
	if room_overlay == null:
		return

	var pending: Array[Node] = [room_overlay]
	while not pending.is_empty():
		var current_variant: Variant = pending.pop_back()
		if not (current_variant is Node):
			continue
		var current: Node = current_variant
		if current is Node3D and _should_convert_handcrafted_wall_container(current.name):
			_convert_handcrafted_wall_container(current as Node3D)
		for child in current.get_children():
			pending.append(child)

func _should_convert_handcrafted_wall_container(node_name: String) -> bool:
	return node_name == "Walls" or node_name == "CompactWalls" or node_name == "RoomShell"

func _convert_handcrafted_wall_container(container: Node3D) -> void:
	if container == null:
		return

	var groups := {}
	for child in container.get_children():
		var wall_tile := child as StaticBody3D
		if wall_tile == null or not _is_handcrafted_wall_tile(wall_tile):
			continue

		var wall_size := _get_handcrafted_wall_tile_size(wall_tile)
		if wall_size == Vector3.ZERO:
			continue

		var tile_length := maxf(wall_size.x, wall_size.z)
		var tile_thickness := minf(wall_size.x, wall_size.z)
		var axis_key := _get_handcrafted_wall_axis(wall_tile)
		var line_coord := wall_tile.position.z
		if axis_key == "z":
			line_coord = wall_tile.position.x

		var group_key := "%s:%.3f" % [axis_key, snappedf(line_coord, 0.001)]
		if not groups.has(group_key):
			groups[group_key] = []
		groups[group_key].append({
			"node": wall_tile,
			"axis": axis_key,
			"line": line_coord,
			"length": tile_length,
			"thickness": tile_thickness,
			"size": wall_size,
			"position": wall_tile.position,
		})

	for group_variant in groups.values():
		var entries: Array = group_variant
		entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			var axis: String = a["axis"]
			var pos_a: Vector3 = a["position"]
			var pos_b: Vector3 = b["position"]
			return pos_a.x < pos_b.x if axis == "x" else pos_a.z < pos_b.z
		)

		var run: Array = []
		var previous_center := 0.0
		var expected_step := 0.0
		for entry_variant in entries:
			var entry: Dictionary = entry_variant
			var axis: String = entry["axis"]
			var position: Vector3 = entry["position"]
			var center := position.x if axis == "x" else position.z
			var length := float(entry["length"])
			if run.is_empty():
				run = [entry]
				previous_center = center
				expected_step = length
				continue
			if absf(center - previous_center - expected_step) <= 0.15:
				run.append(entry)
				previous_center = center
				continue
			_emit_handcrafted_wall_run(container, run)
			run = [entry]
			previous_center = center
			expected_step = length
		if not run.is_empty():
			_emit_handcrafted_wall_run(container, run)

	for group_variant in groups.values():
		for entry_variant in group_variant:
			var entry: Dictionary = entry_variant
			var wall_tile := entry["node"] as Node
			if wall_tile != null:
				wall_tile.queue_free()

func _emit_handcrafted_wall_run(container: Node3D, run: Array) -> void:
	if container == null or run.is_empty():
		return

	var first: Dictionary = run[0]
	var last: Dictionary = run[run.size() - 1]
	var axis: String = first["axis"]
	var height := float((first["size"] as Vector3).y)
	var length := float(first["length"])
	var thickness := float(first["thickness"])
	var first_pos: Vector3 = first["position"]
	var last_pos: Vector3 = last["position"]
	var line := float(first["line"])
	var material := _tuned_handcrafted_wall_material(_get_handcrafted_wall_tile_material(first["node"]))

	var segment := StaticBody3D.new()
	var segment_size := Vector3(length, height, thickness)
	var segment_pos := first_pos
	var y_center := first_pos.y + height * 0.5
	if axis == "x":
		segment_size.x = absf(last_pos.x - first_pos.x) + length
		segment_pos = Vector3((first_pos.x + last_pos.x) * 0.5, y_center, line)
	else:
		segment_size = Vector3(thickness, height, absf(last_pos.z - first_pos.z) + length)
		segment_pos = Vector3(line, y_center, (first_pos.z + last_pos.z) * 0.5)

	segment.position = segment_pos

	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = segment_size
	collider.shape = shape
	segment.add_child(collider)

	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = segment_size
	mesh.material = material
	mesh_instance.mesh = mesh
	segment.add_child(mesh_instance)

	container.add_child(segment)

func _is_handcrafted_wall_tile(node: StaticBody3D) -> bool:
	if node == null:
		return false
	var mesh_instance := node.get_node_or_null("MeshInstance3D") as MeshInstance3D
	var collision := node.get_node_or_null("CollisionShape3D") as CollisionShape3D
	return mesh_instance != null and collision != null and collision.shape is BoxShape3D

func _get_handcrafted_wall_tile_size(node: StaticBody3D) -> Vector3:
	var collision := node.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision == null or not (collision.shape is BoxShape3D):
		return Vector3.ZERO
	var shape := collision.shape as BoxShape3D
	return shape.size

func _get_handcrafted_wall_axis(node: StaticBody3D) -> String:
	if node == null:
		return "x"
	var local_x := node.transform.basis.x
	return "x" if absf(local_x.x) >= absf(local_x.z) else "z"

func _get_handcrafted_wall_tile_material(node: Node) -> Material:
	if node == null:
		return null
	var mesh_instance := node.get_node_or_null("MeshInstance3D") as MeshInstance3D
	if mesh_instance == null:
		return null
	if mesh_instance.material_override != null:
		return mesh_instance.material_override
	if mesh_instance.mesh != null and mesh_instance.mesh.get_surface_count() > 0:
		return mesh_instance.mesh.surface_get_material(0)
	return null

func _tuned_handcrafted_wall_material(material: Material) -> Material:
	if material is StandardMaterial3D:
		var tuned := (material as StandardMaterial3D).duplicate() as StandardMaterial3D
		var uv_scale := Vector3(10.0, 3.0, 2.0)
		var use_world_triplanar := false
		if _active_biome_data != null:
			uv_scale = _active_biome_data.wall_uv_scale
			use_world_triplanar = _active_biome_data.wall_use_world_triplanar
		tuned.uv1_scale = uv_scale
		tuned.uv1_triplanar = use_world_triplanar
		tuned.uv1_world_triplanar = use_world_triplanar
		if use_world_triplanar:
			tuned.heightmap_enabled = false
		return tuned
	return material

func _get_handcrafted_quadrant_scene_pool(biome_data: Resource) -> Array[PackedScene]:
	var quadrant_scene_pool: Array[PackedScene] = []
	if biome_data == null:
		return quadrant_scene_pool
	if not _resource_has_property(biome_data, "handcrafted_quadrant_room_scenes"):
		return quadrant_scene_pool
	var pool_variant: Variant = biome_data.get("handcrafted_quadrant_room_scenes")
	if typeof(pool_variant) != TYPE_ARRAY:
		return quadrant_scene_pool
	for scene_variant in pool_variant:
		if scene_variant is PackedScene:
			quadrant_scene_pool.append(scene_variant)
	return quadrant_scene_pool

func _apply_handcrafted_room_orientation(room: RoomData, room_overlay: Node3D) -> void:
	if room == null or room_overlay == null:
		return
	if room.room_type == RoomData.RoomType.START:
		var doorway_side := _get_room_primary_doorway_side(room)
		if doorway_side != "":
			room_overlay.rotation_degrees.y = _rotation_for_start_room_doorway_side(doorway_side)
			return
	if room_overlay is HandcraftedRoomLayout:
		var handcrafted_layout: HandcraftedRoomLayout = room_overlay
		handcrafted_layout.rotation.y = handcrafted_layout.get_random_y_rotation_radians(_generator.rng)

func _get_room_primary_doorway_side(room: RoomData) -> String:
	if room == null:
		return ""
	var rect := room.grid_rect
	for doorway_id_variant in room.doorway_ids:
		var doorway_id := int(doorway_id_variant)
		for doorway_variant in _generator.doorways:
			if typeof(doorway_variant) != TYPE_DICTIONARY:
				continue
			var doorway: Dictionary = doorway_variant
			if int(doorway.get("id", -1)) != doorway_id:
				continue
			var tile: Vector2i = doorway.get("tile", Vector2i(-1, -1))
			if tile.x == rect.position.x:
				return "west"
			if tile.x == rect.position.x + rect.size.x - 1:
				return "east"
			if tile.y == rect.position.y:
				return "north"
			if tile.y == rect.position.y + rect.size.y - 1:
				return "south"
	return ""

func _rotation_for_start_room_doorway_side(doorway_side: String) -> float:
	match doorway_side:
		"east":
			return 90.0
		"north":
			return 180.0
		"west":
			return -90.0
		_:
			return 0.0

func _apply_handcrafted_room_position_offset(room: RoomData, room_overlay: Node3D) -> void:
	if room == null or room_overlay == null:
		return
	if room.room_type != RoomData.RoomType.START:
		return
	var doorway_side := _get_room_primary_doorway_side(room)
	if doorway_side == "":
		return
	# Compact start layouts are authored with their doorway on the local +Z edge.
	# Shift the whole overlay toward the procedural doorway so the room opening
	# lines up with the actual room exit instead of using an internal corridor.
	room_overlay.position += room_overlay.basis * Vector3(0.0, 0.0, 20.0)

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
	var room_overlay = _handcrafted_room_overlays_by_id.get(room_id, null)
	var handcrafted_spawners := _collect_handcrafted_enemy_spawners(room_overlay)
	if not handcrafted_spawners.is_empty():
		spawned_enemies = _encounter.populate_handcrafted_spawners(
			room,
			floor_number,
			nav_region,
			_active_biome_data,
			handcrafted_spawners
		)
	else:
		spawned_enemies = _encounter.populate_room(room, floor_number, nav_region, _active_biome_data)
	_configure_handcrafted_room_enemy_behavior(room, spawned_enemies)
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
	return int(_room_tile_owner.get("%d:%d" % [tx, tz], -1))

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
		"biome_override": GameState.dungeon_biome_override,
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
	GameState.dungeon_biome_override = String(floor_cfg.get("biome_override", GameState.dungeon_biome_override))
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
	if room.handcrafted_scene_path != CASTLE_INNER_CHAMBER_SCENE_PATH:
		return
	var door := room_overlay.get_node_or_null("InnerDoorway/Door") as DungeonDoor
	if door == null:
		push_warning("DungeonManager: castle inner chamber missing InnerDoorway/Door for room %d." % room.id)
		return
	var open_cb := Callable(self, "_on_inner_chamber_door_opened").bind(room.id)
	if not door.is_connected("door_opened", open_cb):
		door.connect("door_opened", open_cb)

func _configure_handcrafted_room_enemy_behavior(room: RoomData, spawned_enemies: Array) -> void:
	if room == null or room.handcrafted_scene_path != CASTLE_INNER_CHAMBER_SCENE_PATH:
		return
	var room_overlay = _handcrafted_room_overlays_by_id.get(room.id, null)
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

func broadcast_projectile_visual(scene_path: String, cam_origin: Vector3, cam_forward: Vector3) -> void:
	if not _session_multiplayer or not _session_host:
		return
	if scene_path.is_empty():
		return
	rpc("rpc_spawn_projectile_visual", scene_path, cam_origin, cam_forward)

func _handle_weapon_fire_request(peer_id: int, weapon_slot: int, weapon_key: String, cam_origin: Vector3, cam_forward: Vector3, _shot_id: int) -> void:
	var player_node = _get_player_node_for_peer(peer_id)
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
	var player_node = _get_player_node_for_peer(peer_id)
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
	var weapon_manager: WeaponManager = interactor.get("weapon_manager") as WeaponManager
	if weapon_manager != null:
		weapon_slot = weapon_manager.get_current_weapon_slot()
		var weapon := weapon_manager.get_current_weapon()
		current_mag = weapon.current_mag if weapon != null else -1
		ammo_snapshot = weapon_manager.get_ammo_snapshot()
	rpc_id(peer_id, "rpc_sync_pickup_state", peer_id, inventory_snapshot, health, weapon_slot, current_mag, ammo_snapshot)

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
	var local_player = NetworkPlayerManager.get_local_player()
	if not is_instance_valid(local_player):
		return
	var manager: WeaponManager = local_player.get("weapon_manager")
	if manager == null:
		return
	manager.apply_authoritative_weapon_state(slot_index, current_mag, ammo_snapshot)

@rpc("authority", "call_remote", "reliable")
func rpc_sync_pickup_state(peer_id: int, inventory_snapshot: Dictionary, health: int, weapon_slot: int, current_mag: int, ammo_snapshot: Dictionary) -> void:
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
		manager.apply_authoritative_weapon_state(weapon_slot, current_mag, ammo_snapshot)
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
	projectile.add_to_group("network_replicated_projectile_visual")
	_debug_network_visual_counts["projectile"] = int(_debug_network_visual_counts.get("projectile", 0)) + 1
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
