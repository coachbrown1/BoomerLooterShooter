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

var _generator: DungeonGenerator
var _builder: DungeonBuilder
var _encounter: EncounterSystem
var _rooms: Array = []
var _active_biome_data: Resource = null
var _room_lookup := {}
var _spawned_enemy_rooms := {}
var _last_player_room_id: int = -1

func _ready() -> void:
	add_to_group("dungeon_manager")
	if Engine.is_editor_hint():
		set_process(false)
		return
	set_process(true)
	generate_floor(floor_number)

func _process(_delta: float) -> void:
	if _encounter == null or _rooms.is_empty():
		return
	var player := get_tree().get_first_node_in_group("player")
	if player == null or not (player is Node3D):
		return

	var room_id := _find_room_id_for_world_position(player.global_position)
	if room_id < 0 or room_id == _last_player_room_id:
		return

	_last_player_room_id = room_id
	_spawn_room_and_adjacent(room_id)

func generate_floor(floor_num: int, preview_mode: bool = false) -> void:
	floor_number = floor_num

	# Clear old geometry + entities under nav region.
	for child in nav_region.get_children():
		child.queue_free()

	_room_lookup = {}
	_spawned_enemy_rooms = {}
	_last_player_room_id = -1
	_active_biome_data = null

	# Generate tile layout
	_generator = DungeonGenerator.new()
	_generator.grid_size_min = grid_size_min
	_generator.grid_size_max = grid_size_max
	_generator.min_start_end_distance_rooms = min_start_end_distance_rooms
	_generator.room_size_tiles = room_size_tiles
	_generator.corridor_width_tiles = corridor_width_tiles
	_generator.corridor_length_tiles = corridor_length_tiles
	_generator.generate(floor_num, generation_seed)
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

	if preview_mode:
		_build_room_lookup()
		_encounter = null
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
	_encounter = EncounterSystem.new()

	# Place player at start room
	_place_player()

	# Place exit portal in exit room
	_place_exit(biome_data)

	# Spawn only the start-room neighborhood; expand as player progresses.
	_prime_progressive_enemy_spawning()

	print(
		"DungeonManager: Floor %d generated with %d rooms (grid=%dx%d seed=%d)." % [
			floor_num,
			_rooms.size(),
			_generator.sampled_grid_size,
			_generator.sampled_grid_size,
			generation_seed,
		]
	)

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
	var player = get_tree().get_first_node_in_group("player")
	if not player:
		return
	var start_room := _get_room_by_type(RoomData.RoomType.START)
	if start_room == null:
		return
	var pos = start_room.get_world_center(DungeonBuilder.TILE_SIZE)
	pos.y = 1.0
	player.global_position = pos

func _place_exit(biome_data: Resource = null) -> void:
	var exit_room := _get_room_by_type(RoomData.RoomType.EXIT)
	if exit_room == null:
		return

	# Load and instance the exit portal scene
	var portal_tex_path := "res://Assets/Environment/exit_portal.png"
	if biome_data and biome_data.has_method("get"):
		var candidate: String = str(biome_data.get("exit_portal_texture"))
		if candidate != "":
			portal_tex_path = candidate
	var portal_tex = load(portal_tex_path)
	if not portal_tex:
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
		floor_number += 1
		print("Descending to floor %d..." % floor_number)
		generate_floor(floor_number)

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

	if biome_id == "fungal" and start_scene != null:
		var start_room := _get_room_by_type(RoomData.RoomType.START)
		_assign_handcrafted_scene_to_room(start_room, start_scene)
	elif biome_id == "fungal":
		push_warning("DungeonManager: fungal biome has no handcrafted_start_room_scene; start room will be procedural.")

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
	_encounter.populate_room(room, floor_number, nav_region, _active_biome_data)

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
