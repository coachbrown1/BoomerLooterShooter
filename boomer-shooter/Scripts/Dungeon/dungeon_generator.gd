extends RefCounted
class_name DungeonGenerator

# ---- Tile types ----
const TILE_WALL: int = 0
const TILE_FLOOR: int = 1
const OWNER_NONE: int = -1
const DEFAULT_DEBUG_GENERATION_METRICS: bool = true

# ---- Output ----
var GRID_W: int = 60
var GRID_H: int = 60
var tile_grid: Array = []		# [x][z] -> TILE_WALL / TILE_FLOOR
var rooms: Array = []			# Array of RoomData
var corridors: Array = []		# Array of { "id", "room_a_id", "room_b_id", "tiles", "width_tiles", "doorway_a_id", "doorway_b_id" }
var doorways: Array = []		# Array of { "id", "tile", "orientation", "room_id", "corridor_id", ... }
var rng: RandomNumberGenerator

# ---- Config ----
var grid_size_min: int = 10
var grid_size_max: int = 10
var min_start_end_distance_rooms: int = 3
var room_size_tiles: int = 20
var corridor_width_tiles: int = 4
var corridor_length_tiles: int = 10
var layout_margin_tiles: int = 2

# Runtime metadata
var sampled_grid_size: int = 10

var debug_generation_metrics_enabled: bool = DEFAULT_DEBUG_GENERATION_METRICS

var _current_biome: String = "crypt"
var _room_tile_owner := {}		# "x:z" -> room_id
var _corridor_tile_owner := {}	# "x:z" -> corridor_id
var _corridor_next_id: int = 0
var _doorway_next_id: int = 0
var _edge_keys := {}			# "a:b" -> true
var _adjacency := {}			# room_id -> Array of neighbor room IDs
var _room_lookup := {}			# room_id -> RoomData
const DOORWAY_SPAN_TILES: int = 2


# -------------------------------------------------------
# Public entry point
# -------------------------------------------------------
func generate(floor_num: int, seed_val: int = 0) -> void:
	rng = RandomNumberGenerator.new()
	rng.seed = seed_val if seed_val != 0 else int(Time.get_unix_time_from_system())

	var biomes: PackedStringArray = ["castle", "crypt", "fungal", "lava"]
	_current_biome = biomes[maxi(0, floor_num - 1) % biomes.size()]

	_normalize_config()
	sampled_grid_size = rng.randi_range(grid_size_min, grid_size_max)
	_resize_grid_for_layout(sampled_grid_size)
	_init_grid()
	_reset_outputs()

	_create_lattice_rooms(sampled_grid_size)

	var start_room_id := int(rng.randi() % rooms.size()) if rooms.size() > 0 else OWNER_NONE
	_prune_room_to_single_connection(start_room_id)

	var start_distances := _bfs_distances(start_room_id)
	var end_room_id := _pick_end_room(start_room_id, start_distances)
	_prune_room_to_single_connection(end_room_id)

	_assign_room_types(start_room_id, end_room_id)
	_carve_all_rooms()
	_build_corridors_and_doorways()
	_apply_room_biomes()

	_log_generation_metrics(start_room_id, end_room_id)


# -------------------------------------------------------
# Layout generation
# -------------------------------------------------------
func _normalize_config() -> void:
	grid_size_min = maxi(2, grid_size_min)
	grid_size_max = maxi(grid_size_min, grid_size_max)
	min_start_end_distance_rooms = maxi(0, min_start_end_distance_rooms)
	room_size_tiles = maxi(3, room_size_tiles)
	corridor_length_tiles = maxi(1, corridor_length_tiles)
	layout_margin_tiles = maxi(1, layout_margin_tiles)
	corridor_width_tiles = maxi(1, corridor_width_tiles)

func _resize_grid_for_layout(grid_size: int) -> void:
	var n := maxi(1, grid_size)
	var total_w := layout_margin_tiles * 2 + n * room_size_tiles + (n - 1) * corridor_length_tiles
	var total_h := layout_margin_tiles * 2 + n * room_size_tiles + (n - 1) * corridor_length_tiles
	GRID_W = maxi(3, total_w)
	GRID_H = maxi(3, total_h)

func _reset_outputs() -> void:
	rooms = []
	corridors = []
	doorways = []
	_room_tile_owner = {}
	_corridor_tile_owner = {}
	_corridor_next_id = 0
	_doorway_next_id = 0
	_edge_keys = {}
	_adjacency = {}
	_room_lookup = {}

func _create_lattice_rooms(grid_size: int) -> void:
	var room_id := 0
	var lattice_lookup := {}
	var step := room_size_tiles + corridor_length_tiles

	for gy in range(grid_size):
		for gx in range(grid_size):
			var room := RoomData.new()
			room.id = room_id
			room.lattice_coord = Vector2i(gx, gy)
			room.grid_rect = Rect2i(
				layout_margin_tiles + gx * step,
				layout_margin_tiles + gy * step,
				room_size_tiles,
				room_size_tiles
			)
			room.surface_profile = _make_room_surface_profile()
			rooms.append(room)
			_room_lookup[room.id] = room
			_adjacency[room.id] = []
			lattice_lookup[_lattice_key(gx, gy)] = room.id
			room_id += 1

	for room_variant in rooms:
		var room: RoomData = room_variant
		var c := room.lattice_coord
		var east_id := int(lattice_lookup.get(_lattice_key(c.x + 1, c.y), OWNER_NONE))
		var south_id := int(lattice_lookup.get(_lattice_key(c.x, c.y + 1), OWNER_NONE))
		if east_id >= 0:
			_add_edge(room.id, east_id)
		if south_id >= 0:
			_add_edge(room.id, south_id)

func _pick_end_room(start_room_id: int, distances: Dictionary) -> int:
	if rooms.is_empty():
		return OWNER_NONE
	if rooms.size() == 1:
		return rooms[0].id
	if start_room_id < 0:
		return int(rooms[rooms.size() - 1].id)

	var candidates: Array = []
	var farthest_rooms: Array = []
	var farthest_distance := -1

	for room_variant in rooms:
		var room: RoomData = room_variant
		if room.id == start_room_id:
			continue
		if not distances.has(room.id):
			continue
		var dist := int(distances[room.id])
		if dist >= min_start_end_distance_rooms:
			candidates.append(room.id)
		if dist > farthest_distance:
			farthest_distance = dist
			farthest_rooms = [room.id]
		elif dist == farthest_distance:
			farthest_rooms.append(room.id)

	if not candidates.is_empty():
		return candidates[rng.randi() % candidates.size()]
	if not farthest_rooms.is_empty():
		if debug_generation_metrics_enabled:
			print(
				"DungeonGenerator: distance constraint %d not feasible for grid %dx%d; using farthest reachable room."
				% [min_start_end_distance_rooms, sampled_grid_size, sampled_grid_size]
			)
		return farthest_rooms[rng.randi() % farthest_rooms.size()]

	for room_variant in rooms:
		var room: RoomData = room_variant
		if room.id != start_room_id:
			return room.id
	return start_room_id

func _assign_room_types(start_room_id: int, end_room_id: int) -> void:
	for room_variant in rooms:
		var room: RoomData = room_variant
		room.room_type = RoomData.RoomType.NORMAL

	var start_room: RoomData = _room_lookup.get(start_room_id, null)
	if start_room != null:
		start_room.room_type = RoomData.RoomType.START

	var end_room: RoomData = _room_lookup.get(end_room_id, null)
	if end_room != null and end_room != start_room:
		end_room.room_type = RoomData.RoomType.EXIT
	elif end_room != null and rooms.size() > 1:
		for room_variant in rooms:
			var room: RoomData = room_variant
			if room != start_room:
				room.room_type = RoomData.RoomType.EXIT
				break


# -------------------------------------------------------
# Carving
# -------------------------------------------------------
func _init_grid() -> void:
	tile_grid = []
	for x in range(GRID_W):
		var col := []
		for _z in range(GRID_H):
			col.append(TILE_WALL)
		tile_grid.append(col)

func _carve_all_rooms() -> void:
	for room_variant in rooms:
		var room: RoomData = room_variant
		_carve_rect(room.grid_rect, room.id)

func _build_corridors_and_doorways() -> void:
	for room_variant in rooms:
		var room: RoomData = room_variant
		room.connected_to = []
		room.corridor_ids = []
		room.doorway_ids = []

	var edge_list: Array = _edge_keys.keys()
	edge_list.sort()
	for edge_key_variant in edge_list:
		var edge_key := str(edge_key_variant)
		var parts := edge_key.split(":")
		if parts.size() != 2:
			continue
		var room_a_id := int(parts[0])
		var room_b_id := int(parts[1])
		var room_a: RoomData = _room_lookup.get(room_a_id, null)
		var room_b: RoomData = _room_lookup.get(room_b_id, null)
		if room_a == null or room_b == null:
			continue
		_create_corridor_between_rooms(room_a, room_b)

func _create_corridor_between_rooms(room_a: RoomData, room_b: RoomData) -> void:
	var delta := room_b.lattice_coord - room_a.lattice_coord
	var doorway_a: Dictionary = {}
	var doorway_b: Dictionary = {}

	if abs(delta.x) + abs(delta.y) != 1:
		return

	if delta.x == 1:
		doorway_a = _register_simple_doorway(room_a, "east", _corridor_next_id)
		doorway_b = _register_simple_doorway(room_b, "west", _corridor_next_id)
	elif delta.x == -1:
		doorway_a = _register_simple_doorway(room_a, "west", _corridor_next_id)
		doorway_b = _register_simple_doorway(room_b, "east", _corridor_next_id)
	elif delta.y == 1:
		doorway_a = _register_simple_doorway(room_a, "south", _corridor_next_id)
		doorway_b = _register_simple_doorway(room_b, "north", _corridor_next_id)
	else:
		doorway_a = _register_simple_doorway(room_a, "north", _corridor_next_id)
		doorway_b = _register_simple_doorway(room_b, "south", _corridor_next_id)

	if doorway_a.is_empty() or doorway_b.is_empty():
		return

	var doorway_a_id := int(doorway_a["id"])
	var doorway_b_id := int(doorway_b["id"])
	var tile_a: Vector2i = doorway_a["tile"]
	var tile_b: Vector2i = doorway_b["tile"]
	var corridor_tiles := _carve_corridor_line(tile_a, tile_b, _corridor_next_id)
	doorway_a["pinch_tiles"] = _enforce_doorway_side_walls(doorway_a)
	doorway_b["pinch_tiles"] = _enforce_doorway_side_walls(doorway_b)

	corridors.append({
		"id": _corridor_next_id,
		"room_a_id": room_a.id,
		"room_b_id": room_b.id,
		"tiles": corridor_tiles,
		"width_tiles": _effective_corridor_width(),
		"doorway_a_id": doorway_a_id,
		"doorway_b_id": doorway_b_id,
	})

	room_a.corridor_ids.append(_corridor_next_id)
	room_b.corridor_ids.append(_corridor_next_id)
	room_a.doorway_ids.append(doorway_a_id)
	room_b.doorway_ids.append(doorway_b_id)
	room_a.connected_to.append(room_b.id)
	room_b.connected_to.append(room_a.id)

	_corridor_next_id += 1

func _register_simple_doorway(room: RoomData, wall: String, corridor_id: int) -> Dictionary:
	if room == null:
		return {}

	var rect := room.grid_rect
	var tile := Vector2i.ZERO
	var orientation := ""
	var wall_line_key := ""
	var opening_tiles: Array = []
	var opening_span_tiles := DOORWAY_SPAN_TILES
	var opening_center_offset_tiles := _opening_center_offset_tiles(opening_span_tiles)

	match wall:
		"west":
			var start_z_west := _centered_opening_start(rect.position.y, rect.size.y, opening_span_tiles)
			tile = Vector2i(rect.position.x, start_z_west)
			orientation = "north_south"
			wall_line_key = "v:%d" % tile.x
			for dz in range(opening_span_tiles):
				opening_tiles.append(Vector2i(tile.x, start_z_west + dz))
		"east":
			var start_z_east := _centered_opening_start(rect.position.y, rect.size.y, opening_span_tiles)
			tile = Vector2i(rect.position.x + rect.size.x - 1, start_z_east)
			orientation = "north_south"
			wall_line_key = "v:%d" % tile.x
			for dz in range(opening_span_tiles):
				opening_tiles.append(Vector2i(tile.x, start_z_east + dz))
		"north":
			var start_x_north := _centered_opening_start(rect.position.x, rect.size.x, opening_span_tiles)
			tile = Vector2i(start_x_north, rect.position.y)
			orientation = "east_west"
			wall_line_key = "h:%d" % tile.y
			for dx in range(opening_span_tiles):
				opening_tiles.append(Vector2i(start_x_north + dx, tile.y))
		"south":
			var start_x_south := _centered_opening_start(rect.position.x, rect.size.x, opening_span_tiles)
			tile = Vector2i(start_x_south, rect.position.y + rect.size.y - 1)
			orientation = "east_west"
			wall_line_key = "h:%d" % tile.y
			for dx in range(opening_span_tiles):
				opening_tiles.append(Vector2i(start_x_south + dx, tile.y))
		_:
			return {}

	for opening_tile_variant in opening_tiles:
		var opening_tile: Vector2i = opening_tile_variant
		_set_floor(opening_tile.x, opening_tile.y)

	var doorway := {
		"id": _doorway_next_id,
		"tile": tile,
		"orientation": orientation,
		"wall_line_key": wall_line_key,
		"biome": _current_biome,
		"room_id": room.id,
		"corridor_id": corridor_id,
		"opening_tiles": opening_tiles,
		"pinch_tiles": [],
		"opening_span_tiles": opening_span_tiles,
		"opening_center_offset_tiles": opening_center_offset_tiles,
	}
	doorways.append(doorway)
	_doorway_next_id += 1
	return doorway

func _carve_corridor_line(tile_a: Vector2i, tile_b: Vector2i, corridor_id: int) -> Array:
	var offsets := _corridor_width_offsets()
	var out: Array = []
	var seen := {}

	if tile_a.y == tile_b.y:
		var x0 := mini(tile_a.x, tile_b.x)
		var x1 := maxi(tile_a.x, tile_b.x)
		for x in range(x0, x1 + 1):
			for dz in offsets:
				_carve_corridor_tile(x, tile_a.y + dz, corridor_id, out, seen)
	elif tile_a.x == tile_b.x:
		var z0 := mini(tile_a.y, tile_b.y)
		var z1 := maxi(tile_a.y, tile_b.y)
		for z in range(z0, z1 + 1):
			for dx in offsets:
				_carve_corridor_tile(tile_a.x + dx, z, corridor_id, out, seen)
	else:
		# Fallback L path; this should not happen with strict lattice neighbors.
		var corner := Vector2i(tile_b.x, tile_a.y)
		var first_leg := _carve_corridor_line(tile_a, corner, corridor_id)
		var second_leg := _carve_corridor_line(corner, tile_b, corridor_id)
		for t in first_leg:
			var key := _grid_key(t.x, t.y)
			if seen.has(key):
				continue
			seen[key] = true
			out.append(t)
		for t in second_leg:
			var key := _grid_key(t.x, t.y)
			if seen.has(key):
				continue
			seen[key] = true
			out.append(t)
	return out

func _carve_corridor_tile(x: int, z: int, corridor_id: int, out_tiles: Array, seen: Dictionary) -> void:
	if not _is_in_bounds(x, z):
		return
	_set_floor(x, z)
	var key := _grid_key(x, z)
	_corridor_tile_owner[key] = corridor_id
	if seen.has(key):
		return
	seen[key] = true
	out_tiles.append(Vector2i(x, z))

func _carve_rect(rect: Rect2i, room_id: int = OWNER_NONE) -> void:
	for x in range(rect.position.x, rect.position.x + rect.size.x):
		for z in range(rect.position.y, rect.position.y + rect.size.y):
			_set_floor(x, z)
			if room_id >= 0:
				_room_tile_owner[_grid_key(x, z)] = room_id

func _set_floor(x: int, z: int) -> void:
	if _is_in_bounds(x, z):
		tile_grid[x][z] = TILE_FLOOR

func _set_wall(x: int, z: int) -> void:
	if not _is_in_bounds(x, z):
		return
	tile_grid[x][z] = TILE_WALL
	var key := _grid_key(x, z)
	_corridor_tile_owner.erase(key)
	_room_tile_owner.erase(key)

func _is_in_bounds(x: int, z: int) -> bool:
	return x >= 0 and x < GRID_W and z >= 0 and z < GRID_H

func _effective_corridor_width() -> int:
	return maxi(1, corridor_width_tiles)

func _corridor_width_offsets() -> Array:
	var width := _effective_corridor_width()
	var offsets: Array = []
	if width % 2 == 1:
		var half := width / 2
		for v in range(-half, half + 1):
			offsets.append(v)
	else:
		# Even widths are centered between two tiles (doorway center at +0.5).
		var left := (width / 2) - 1
		var right := width / 2
		for v in range(-left, right + 1):
			offsets.append(v)
	return offsets

func _centered_opening_start(line_start: int, line_size: int, span: int) -> int:
	var safe_span := maxi(1, span)
	var safe_size := maxi(safe_span, line_size)
	var slack := safe_size - safe_span
	return line_start + int(floor(float(slack) / 2.0))

func _opening_center_offset_tiles(span: int) -> float:
	var safe_span := maxi(1, span)
	return float(safe_span - 1) / 2.0

func _enforce_doorway_side_walls(doorway: Dictionary) -> Array:
	var placed: Array = []
	var orientation := str(doorway.get("orientation", ""))
	var opening_tiles: Array = doorway.get("opening_tiles", [])
	if opening_tiles.is_empty():
		return placed

	if orientation == "east_west":
		if typeof(opening_tiles[0]) != TYPE_VECTOR2I:
			return placed
		var first_tile_ew: Vector2i = opening_tiles[0]
		var row := first_tile_ew.y
		var min_x := 999999
		var max_x := -999999
		for tile_variant in opening_tiles:
			if typeof(tile_variant) != TYPE_VECTOR2I:
				continue
			var tile: Vector2i = tile_variant
			min_x = mini(min_x, tile.x)
			max_x = maxi(max_x, tile.x)
		var left := Vector2i(min_x - 1, row)
		var right := Vector2i(max_x + 1, row)
		if _is_in_bounds(left.x, left.y):
			_set_wall(left.x, left.y)
			placed.append(left)
		if _is_in_bounds(right.x, right.y):
			_set_wall(right.x, right.y)
			placed.append(right)
	elif orientation == "north_south":
		if typeof(opening_tiles[0]) != TYPE_VECTOR2I:
			return placed
		var first_tile_ns: Vector2i = opening_tiles[0]
		var col := first_tile_ns.x
		var min_y := 999999
		var max_y := -999999
		for tile_variant in opening_tiles:
			if typeof(tile_variant) != TYPE_VECTOR2I:
				continue
			var tile: Vector2i = tile_variant
			min_y = mini(min_y, tile.y)
			max_y = maxi(max_y, tile.y)
		var top := Vector2i(col, min_y - 1)
		var bottom := Vector2i(col, max_y + 1)
		if _is_in_bounds(top.x, top.y):
			_set_wall(top.x, top.y)
			placed.append(top)
		if _is_in_bounds(bottom.x, bottom.y):
			_set_wall(bottom.x, bottom.y)
			placed.append(bottom)
	return placed


# -------------------------------------------------------
# Graph helpers
# -------------------------------------------------------
func _add_edge(room_a_id: int, room_b_id: int) -> void:
	if room_a_id < 0 or room_b_id < 0 or room_a_id == room_b_id:
		return
	var key := _edge_key(room_a_id, room_b_id)
	if _edge_keys.has(key):
		return
	_edge_keys[key] = true
	_append_unique_neighbor(room_a_id, room_b_id)
	_append_unique_neighbor(room_b_id, room_a_id)

func _remove_edge(room_a_id: int, room_b_id: int) -> void:
	var key := _edge_key(room_a_id, room_b_id)
	if not _edge_keys.has(key):
		return
	_edge_keys.erase(key)
	_remove_neighbor(room_a_id, room_b_id)
	_remove_neighbor(room_b_id, room_a_id)

func _prune_room_to_single_connection(room_id: int) -> void:
	if room_id < 0:
		return
	var neighbors: Array = _adjacency.get(room_id, [])
	if neighbors.size() <= 1:
		return
	var keep_neighbor: int = int(neighbors[rng.randi() % neighbors.size()])
	var to_remove: Array = neighbors.duplicate()
	for neighbor_variant in to_remove:
		var neighbor_id := int(neighbor_variant)
		if neighbor_id == keep_neighbor:
			continue
		_remove_edge(room_id, neighbor_id)

func _append_unique_neighbor(room_id: int, neighbor_id: int) -> void:
	var neighbors: Array = _adjacency.get(room_id, [])
	if neighbor_id in neighbors:
		return
	neighbors.append(neighbor_id)
	_adjacency[room_id] = neighbors

func _remove_neighbor(room_id: int, neighbor_id: int) -> void:
	var neighbors: Array = _adjacency.get(room_id, [])
	neighbors.erase(neighbor_id)
	_adjacency[room_id] = neighbors

func _bfs_distances(start_room_id: int) -> Dictionary:
	var out := {}
	if start_room_id < 0 or not _adjacency.has(start_room_id):
		return out
	var queue: Array = [start_room_id]
	var index := 0
	out[start_room_id] = 0

	while index < queue.size():
		var room_id := int(queue[index])
		index += 1
		var distance := int(out.get(room_id, 0))
		var neighbors: Array = _adjacency.get(room_id, [])
		for neighbor_variant in neighbors:
			var neighbor_id := int(neighbor_variant)
			if out.has(neighbor_id):
				continue
			out[neighbor_id] = distance + 1
			queue.append(neighbor_id)
	return out

func _edge_key(room_a_id: int, room_b_id: int) -> String:
	if room_a_id <= room_b_id:
		return "%d:%d" % [room_a_id, room_b_id]
	return "%d:%d" % [room_b_id, room_a_id]

func _lattice_key(x: int, y: int) -> String:
	return "%d:%d" % [x, y]

func _grid_key(x: int, z: int) -> String:
	return "%d:%d" % [x, z]


# -------------------------------------------------------
# Misc helpers
# -------------------------------------------------------
func _make_room_surface_profile() -> Dictionary:
	return {
		"floor_variant": rng.randi_range(0, 2),
		"wall_variant": rng.randi_range(0, 2),
		"ceiling_variant": rng.randi_range(0, 2),
	}

func _apply_room_biomes() -> void:
	for room_variant in rooms:
		var room: RoomData = room_variant
		room.biome = _current_biome

func _log_generation_metrics(start_room_id: int, end_room_id: int) -> void:
	if not debug_generation_metrics_enabled:
		return
	var start_neighbors: Array = _adjacency.get(start_room_id, [])
	var end_neighbors: Array = _adjacency.get(end_room_id, [])
	var start_degree := start_neighbors.size()
	var end_degree := end_neighbors.size()
	print(
		"DungeonGenerator lattice metrics: grid=%dx%d rooms=%d corridors=%d doorways=%d start=%d(deg=%d) end=%d(deg=%d) min_dist=%d" % [
			sampled_grid_size,
			sampled_grid_size,
			rooms.size(),
			corridors.size(),
			doorways.size(),
			start_room_id,
			start_degree,
			end_room_id,
			end_degree,
			min_start_end_distance_rooms,
		]
	)
