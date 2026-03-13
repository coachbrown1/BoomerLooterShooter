extends RefCounted
class_name EncounterSystem

# Threat budget per room = base + (floor * depth_scale) + (area * size_scale)
const THREAT_BASE: float = 3.0
const THREAT_DEPTH_SCALE: float = 2.0
const THREAT_SIZE_SCALE: float = 0.05

const FALLBACK_ROSTER_DATA: EnemyRosterData = preload("res://Data/enemies/fallback_enemy_roster.tres")

var rng: RandomNumberGenerator

func _init() -> void:
	rng = RandomNumberGenerator.new()
	rng.randomize()

# Populate a room with enemies — returns Array of instanced nodes (not yet added to tree)
func populate_room(room: RoomData, floor_num: int, parent: Node3D, biome_data: Resource = null) -> Array:
	var spawned: Array = []
	# Skip start room
	if room.room_type == RoomData.RoomType.START:
		return spawned

	var room_area: float = room.grid_rect.size.x * room.grid_rect.size.y
	var budget: float = THREAT_BASE + (floor_num * THREAT_DEPTH_SCALE) + (room_area * THREAT_SIZE_SCALE)

	# Exit room gets fewer enemies
	if room.room_type == RoomData.RoomType.EXIT:
		budget = ceil(budget * 0.5)

	var roster_scenes := _get_roster_scenes(biome_data)
	if roster_scenes.is_empty():
		push_error("EncounterSystem: No enemy_scenes resolved for biome '%s' on floor %d." % [room.biome, floor_num])
		return spawned

	var valid: Array = []
	for packed_variant in roster_scenes:
		if not (packed_variant is PackedScene):
			continue
		var packed: PackedScene = packed_variant
		var spawn_def := _build_spawn_definition(packed)
		if spawn_def.is_empty():
			continue
		if floor_num >= int(spawn_def.get("min_floor", 1)):
			valid.append(spawn_def)

	if valid.is_empty():
		push_warning("EncounterSystem: no eligible enemy scenes for floor %d in biome '%s'." % [floor_num, room.biome])
		return spawned

	# Spend budget
	while budget > 0.5:
		var affordable: Array = []
		for def_variant in valid:
			if typeof(def_variant) != TYPE_DICTIONARY:
				continue
			var spawn_def: Dictionary = def_variant
			if float(spawn_def.get("cost", 1.0)) <= budget:
				affordable.append(spawn_def)
		if affordable.is_empty():
			break

		var pick: Dictionary = affordable[rng.randi() % affordable.size()]
		budget -= float(pick.get("cost", 1.0))

		var packed_variant: Variant = pick.get("scene", null)
		if not (packed_variant is PackedScene):
			continue
		var packed: PackedScene = packed_variant

		var enemy_variant: Variant = packed.instantiate()
		if not (enemy_variant is Node3D):
			if enemy_variant is Node:
				var cleanup_node: Node = enemy_variant
				cleanup_node.free()
			continue
		var enemy: Node3D = enemy_variant

		parent.add_child(enemy)
		spawned.append(enemy)

		# Random position within the room
		var spawn_pos := _random_room_pos(room)
		enemy.global_position = spawn_pos

	return spawned

func _get_roster_scenes(biome_data: Resource) -> Array:
	if _has_biome_data(biome_data):
		var from_biome: Variant = biome_data.get("enemy_scenes")
		var from_biome_scenes := _to_packed_scene_array(from_biome)
		if not from_biome_scenes.is_empty():
			return from_biome_scenes

	if FALLBACK_ROSTER_DATA != null:
		return _to_packed_scene_array(FALLBACK_ROSTER_DATA.enemy_scenes)
	return []

func _to_packed_scene_array(value: Variant) -> Array:
	if typeof(value) != TYPE_ARRAY:
		return []
	var scenes: Array = []
	for entry in value:
		if entry is PackedScene:
			scenes.append(entry)
		elif entry is String:
			var loaded := load(str(entry))
			if loaded is PackedScene:
				scenes.append(loaded)
	return scenes

func _build_spawn_definition(scene: PackedScene) -> Dictionary:
	if scene == null:
		return {}
	var cost := 1.0
	var min_floor := 1
	var preview_variant: Variant = scene.instantiate()
	if preview_variant is EnemyBase:
		var enemy_preview: EnemyBase = preview_variant
		cost = maxf(0.1, enemy_preview.spawn_cost)
		min_floor = maxi(1, enemy_preview.spawn_min_floor)
	if preview_variant is Node:
		var preview_node: Node = preview_variant
		preview_node.free()
	return {
		"scene": scene,
		"cost": cost,
		"min_floor": min_floor,
	}

func _has_biome_data(biome_data: Resource) -> bool:
	if biome_data == null:
		return false
	for p in biome_data.get_property_list():
		if typeof(p) == TYPE_DICTIONARY and str(p.get("name", "")) == "enemy_scenes":
			return true
	return false

func _random_room_pos(room: RoomData) -> Vector3:
	const TILE_SIZE := 3.0
	const MARGIN := 1  # tile margin from walls

	var rx := room.grid_rect.position.x + MARGIN + rng.randi() % maxi(1, room.grid_rect.size.x - MARGIN * 2)
	var rz := room.grid_rect.position.y + MARGIN + rng.randi() % maxi(1, room.grid_rect.size.y - MARGIN * 2)
	return Vector3(rx * TILE_SIZE + TILE_SIZE/2.0, 0.0, rz * TILE_SIZE + TILE_SIZE/2.0)
