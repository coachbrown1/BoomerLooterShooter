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
	var has_universal_scenes := false
	if _has_property(biome_data, "universal_prop_scenes"):
		var universal_variant: Variant = biome_data.get("universal_prop_scenes")
		has_universal_scenes = typeof(universal_variant) == TYPE_ARRAY and universal_variant.size() > 0
	if not has_universal_scenes:
		push_error("PropPlacer: biome data must define non-empty universal_prop_scenes.")
		return

	for room_variant in rooms:
		var room: RoomData = room_variant
		if room == null:
			continue
		if room.has_handcrafted_layout or room.handcrafted_scene != null or room.handcrafted_scene_path != "":
			continue

		var area: int = room.grid_rect.size.x * room.grid_rect.size.y
		var prop_count: int = mini(8, max(3, area / 15))

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
			var packed: PackedScene = pool[rng.randi() % pool.size()]
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
			var scenes: Array = []
			for value in from_data:
				if value is PackedScene:
					scenes.append(value)
				elif value is String:
					var loaded := load(str(value))
					if loaded is PackedScene:
						scenes.append(loaded)
			return scenes
	return []

func _get_biome_prop_scenes(biome_data: Resource = null) -> Array:
	if _has_property(biome_data, "biome_prop_scenes"):
		var from_data: Variant = biome_data.get("biome_prop_scenes")
		if typeof(from_data) == TYPE_ARRAY and from_data.size() > 0:
			var scenes: Array = []
			for value in from_data:
				if value is PackedScene:
					scenes.append(value)
				elif value is String:
					var loaded := load(str(value))
					if loaded is PackedScene:
						scenes.append(loaded)
			return scenes
	return []

func _has_property(resource: Resource, property_name: String) -> bool:
	if resource == null:
		return false
	for p in resource.get_property_list():
		if typeof(p) == TYPE_DICTIONARY and str(p.get("name", "")) == property_name:
			return true
	return false
