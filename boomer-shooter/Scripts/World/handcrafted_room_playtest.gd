extends Node3D

const PLAYTEST_CONFIG_PATH := "res://.tmp/handcrafted_room_playtest.cfg"
const BIOME_DB_PATH := "res://Data/biomes/biome_dungeon_database.tres"

const FLOOR_HALF_EXTENT := 45.0
const FLOOR_THICKNESS := 1.0
const FALLBACK_SPAWN_POS := Vector3(0.0, 1.0, -8.0)

@onready var _floor_shape: CollisionShape3D = $NavigationRegion3D/Floor/CollisionShape3D
@onready var _floor_mesh: MeshInstance3D = $NavigationRegion3D/Floor/MeshInstance3D
@onready var _player: CharacterBody3D = $Player

func _ready() -> void:
	_configure_floor()
	var cfg := _load_playtest_config()
	if cfg.is_empty():
		push_error("HandcraftedRoomPlaytest: missing playtest config at %s." % PLAYTEST_CONFIG_PATH)
		return

	var room_scene_path := String(cfg.get("room_scene_path", ""))
	if room_scene_path.is_empty():
		push_error("HandcraftedRoomPlaytest: playtest config has no room_scene_path.")
		return

	var room_scene_variant := load(room_scene_path)
	if not (room_scene_variant is PackedScene):
		push_error("HandcraftedRoomPlaytest: could not load room scene '%s'." % room_scene_path)
		return
	var room_scene: PackedScene = room_scene_variant
	var room_variant: Variant = room_scene.instantiate()
	if not (room_variant is Node3D):
		if room_variant is Node:
			var cleanup: Node = room_variant
			cleanup.free()
		push_error("HandcraftedRoomPlaytest: room scene '%s' is not a Node3D root." % room_scene_path)
		return

	var room_root: Node3D = room_variant
	room_root.position = Vector3.ZERO
	add_child(room_root)

	var biome_data := _load_biome_resource(String(cfg.get("biome_resource_path", "")))
	_prepare_room_for_playtest(room_root, biome_data)
	_spawn_handcrafted_enemies(room_root)
	_place_player(room_root)

func _configure_floor() -> void:
	var shape := _floor_shape.shape as BoxShape3D
	if shape != null:
		shape.size = Vector3(FLOOR_HALF_EXTENT * 2.0, FLOOR_THICKNESS, FLOOR_HALF_EXTENT * 2.0)
	var mesh := _floor_mesh.mesh as BoxMesh
	if mesh != null:
		mesh.size = Vector3(FLOOR_HALF_EXTENT * 2.0, FLOOR_THICKNESS, FLOOR_HALF_EXTENT * 2.0)

func _load_playtest_config() -> Dictionary:
	var cfg := ConfigFile.new()
	var err := cfg.load(PLAYTEST_CONFIG_PATH)
	if err != OK:
		return {}
	return {
		"room_scene_path": String(cfg.get_value("playtest", "room_scene_path", "")),
		"biome_resource_path": String(cfg.get_value("playtest", "biome_resource_path", "")),
	}

func _load_biome_resource(path: String) -> Resource:
	if not path.is_empty():
		var direct := load(path)
		if direct is Resource:
			return direct
	var db_variant := load(BIOME_DB_PATH)
	if db_variant == null:
		return null
	var db: Resource = db_variant
	if not _resource_has_property(db, "biomes"):
		return null
	var biome_list: Variant = db.get("biomes")
	if typeof(biome_list) != TYPE_ARRAY:
		return null
	for biome_variant in biome_list:
		if biome_variant is Resource:
			return biome_variant
	return null

func _prepare_room_for_playtest(room_root: Node3D, biome_data: Resource) -> void:
	var debug_root := room_root.get_node_or_null("RoomBoundsDebug") as Node3D
	if debug_root != null:
		debug_root.visible = false

	if room_root is HandcraftedQuadrantCompositeRoom:
		var composite_room: HandcraftedQuadrantCompositeRoom = room_root
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		composite_room.populate_quadrants(_get_quadrant_scene_pool(biome_data), rng)

func _get_quadrant_scene_pool(biome_data: Resource) -> Array[PackedScene]:
	var out: Array[PackedScene] = []
	if biome_data == null or not _resource_has_property(biome_data, "handcrafted_quadrant_room_scenes"):
		return out
	var pool_variant: Variant = biome_data.get("handcrafted_quadrant_room_scenes")
	if typeof(pool_variant) != TYPE_ARRAY:
		return out
	for scene_variant in pool_variant:
		if scene_variant is PackedScene:
			out.append(scene_variant)
	return out

func _spawn_handcrafted_enemies(room_root: Node3D) -> void:
	for spawner_variant in _collect_spawners(room_root):
		if not (spawner_variant is HandcraftedEnemySpawner):
			continue
		var spawner: HandcraftedEnemySpawner = spawner_variant
		if spawner.enemy_scene == null:
			continue
		for index in range(maxi(1, spawner.spawn_count)):
			var enemy_variant: Variant = spawner.enemy_scene.instantiate()
			if not (enemy_variant is Node3D):
				if enemy_variant is Node:
					var cleanup: Node = enemy_variant
					cleanup.free()
				continue
			var enemy: Node3D = enemy_variant
			add_child(enemy)
			enemy.global_position = spawner.get_spawn_position(index)

func _collect_spawners(root: Node) -> Array:
	var out: Array = []
	if root == null:
		return out
	var stack: Array = [root]
	while not stack.is_empty():
		var current_variant: Variant = stack.pop_back()
		if not (current_variant is Node):
			continue
		var current: Node = current_variant
		if current is HandcraftedEnemySpawner:
			out.append(current)
		for child in current.get_children():
			stack.append(child)
	return out

func _place_player(room_root: Node3D) -> void:
	if _player == null:
		return
	var spawn_marker := room_root.get_node_or_null("PlayerSpawn") as Node3D
	if spawn_marker != null:
		_player.global_position = spawn_marker.global_position
		_player.rotation.y = _yaw_from_basis(spawn_marker.global_basis)
		return
	_player.global_position = FALLBACK_SPAWN_POS
	_player.rotation.y = 0.0

func _yaw_from_basis(basis: Basis) -> float:
	var forward := basis * Vector3(0.0, 0.0, 1.0)
	forward.y = 0.0
	if forward.length_squared() <= 0.001:
		return 0.0
	forward = forward.normalized()
	return atan2(forward.x, forward.z)

func _resource_has_property(resource: Resource, property_name: String) -> bool:
	if resource == null:
		return false
	for property_variant in resource.get_property_list():
		if typeof(property_variant) != TYPE_DICTIONARY:
			continue
		if str(property_variant.get("name", "")) == property_name:
			return true
	return false
