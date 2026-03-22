extends Node3D

const PLAYTEST_CONFIG_PATH := "res://.tmp/handcrafted_room_playtest.cfg"
const LOOT_PICKUP_SCENE: PackedScene = preload("res://Scenes/Props/loot_pickup.tscn")
const FALLBACK_SPAWN_POS := Vector3(0.0, 1.0, -8.0)

@onready var _nav_region: NavigationRegion3D = $NavigationRegion3D
@onready var _player: CharacterBody3D = $Player

func _ready() -> void:
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
	_nav_region.add_child(room_root)

	_prepare_room_for_playtest(room_root)
	await _bake_nav()
	_spawn_handcrafted_enemies(room_root)
	_place_player(room_root)

func _load_playtest_config() -> Dictionary:
	var cfg := ConfigFile.new()
	var err := cfg.load(PLAYTEST_CONFIG_PATH)
	if err != OK:
		return {}
	return {
		"room_scene_path": String(cfg.get_value("playtest", "room_scene_path", "")),
	}

func _prepare_room_for_playtest(room_root: Node3D) -> void:
	var debug_root := room_root.get_node_or_null("RoomBoundsDebug") as Node3D
	if debug_root != null:
		debug_root.visible = false

func _bake_nav() -> void:
	if _nav_region == null:
		return
	var nav_mesh := NavigationMesh.new()
	nav_mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nav_mesh.cell_size = 0.25
	nav_mesh.cell_height = 0.25
	nav_mesh.agent_height = 1.8
	nav_mesh.agent_radius = 0.4
	nav_mesh.agent_max_climb = 0.3
	nav_mesh.filter_walkable_low_height_spans = true
	_nav_region.navigation_mesh = nav_mesh
	await get_tree().process_frame
	_nav_region.bake_navigation_mesh(false)
	await get_tree().physics_frame

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

func spawn_network_item_pickup(item_payload: Dictionary, drop_origin: Vector3, launch_direction: Vector3) -> void:
	var pickup_variant: Variant = LOOT_PICKUP_SCENE.instantiate()
	if not (pickup_variant is LootPickup):
		if pickup_variant is Node:
			(pickup_variant as Node).queue_free()
		return
	var pickup: LootPickup = pickup_variant
	var item_data := InventoryItemData.from_dict(item_payload)
	if item_data == null:
		pickup.queue_free()
		return
	pickup.configure_item_pickup(item_data)
	add_child(pickup)
	pickup.launch(drop_origin, launch_direction)

func _yaw_from_basis(basis: Basis) -> float:
	var forward := basis * Vector3(0.0, 0.0, 1.0)
	forward.y = 0.0
	if forward.length_squared() <= 0.001:
		return 0.0
	forward = forward.normalized()
	return atan2(forward.x, forward.z)
