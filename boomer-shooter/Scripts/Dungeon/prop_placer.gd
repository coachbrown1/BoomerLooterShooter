extends RefCounted
class_name PropPlacer

const TILE_SIZE: float = 3.0

func populate(
	parent: Node3D,
	rooms: Array,
	tile_grid: Array,
	rng: RandomNumberGenerator,
	biome_data: Resource = null
) -> void:
	var scene_cache: Dictionary = {}
	var has_universal_scenes := false
	if _has_property(biome_data, "universal_prop_scenes"):
		var universal_variant: Variant = biome_data.get("universal_prop_scenes")
		has_universal_scenes = (typeof(universal_variant) == TYPE_ARRAY and universal_variant.size() > 0) or (typeof(universal_variant) == TYPE_PACKED_STRING_ARRAY and universal_variant.size() > 0)
	if not has_universal_scenes:
		push_error("PropPlacer: biome data must define non-empty universal_prop_scenes.")
		return

	for room_variant in rooms:
		var room: RoomData = room_variant
		if room == null:
			continue
		if room.has_handcrafted_layout:
			continue

		var area = room.grid_rect.size.x * room.grid_rect.size.y
		var prop_count = mini(8, max(3, area / 15))

		var pool: Array = _get_universal_prop_scenes(biome_data)
		var biome_pool: Array = _get_biome_prop_scenes(biome_data)
		if not biome_pool.is_empty():
			pool.append_array(biome_pool)
		if pool.is_empty():
			push_error("PropPlacer: no prop scenes resolved for biome '%s'." % room.biome)
			continue

		for _i in range(prop_count):
			var rx = room.grid_rect.position.x + 1 + rng.randi() % maxi(1, room.grid_rect.size.x - 2)
			var rz = room.grid_rect.position.y + 1 + rng.randi() % maxi(1, room.grid_rect.size.y - 2)

			if tile_grid[rx][rz] != 1:
				continue

			var wall_offset := Vector3.ZERO
			if tile_grid[rx - 1][rz] == 0:
				wall_offset = Vector3(-0.3, 0, 0)
			elif tile_grid[rx + 1][rz] == 0:
				wall_offset = Vector3(0.3, 0, 0)
			elif tile_grid[rx][rz - 1] == 0:
				wall_offset = Vector3(0, 0, -0.3)
			elif tile_grid[rx][rz + 1] == 0:
				wall_offset = Vector3(0, 0, 0.3)

			var world_x = rx * TILE_SIZE + TILE_SIZE / 2.0
			var world_z = rz * TILE_SIZE + TILE_SIZE / 2.0
			var scene_path: String = pool[rng.randi() % pool.size()]

			if not scene_cache.has(scene_path):
				scene_cache[scene_path] = load(scene_path)
			var packed: PackedScene = scene_cache.get(scene_path, null)
			if packed == null:
				continue

			var prop = packed.instantiate()
			if prop == null:
				continue

			parent.add_child(prop)
			if prop.has_method("place"):
				prop.call("place", Vector3(world_x, 0.0, world_z), wall_offset, rng)
			elif prop is Node3D:
				prop.position = Vector3(world_x, 0.0, world_z) + wall_offset

func _get_universal_prop_scenes(biome_data: Resource = null) -> Array:
	if _has_property(biome_data, "universal_prop_scenes"):
		var from_data: Variant = biome_data.get("universal_prop_scenes")
		if typeof(from_data) == TYPE_ARRAY and from_data.size() > 0:
			return from_data.duplicate()
		if typeof(from_data) == TYPE_PACKED_STRING_ARRAY and from_data.size() > 0:
			return Array(from_data)
	return []

func _get_biome_prop_scenes(biome_data: Resource = null) -> Array:
	if _has_property(biome_data, "biome_prop_scenes"):
		var from_data: Variant = biome_data.get("biome_prop_scenes")
		if typeof(from_data) == TYPE_ARRAY and from_data.size() > 0:
			return from_data.duplicate()
		if typeof(from_data) == TYPE_PACKED_STRING_ARRAY and from_data.size() > 0:
			return Array(from_data)
	return []

func _has_property(resource: Resource, property_name: String) -> bool:
	if resource == null:
		return false
	for p in resource.get_property_list():
		if typeof(p) == TYPE_DICTIONARY and str(p.get("name", "")) == property_name:
			return true
	return false
