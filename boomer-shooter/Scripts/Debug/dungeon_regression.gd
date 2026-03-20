extends RefCounted
class_name DungeonRegression

const DungeonGeneratorScript = preload("res://Scripts/Dungeon/dungeon_generator.gd")
const RoomDataScript = preload("res://Scripts/Dungeon/room_data.gd")

func run(runs: int = 100, floor_num: int = 1, seed_base: int = 1000) -> Dictionary:
	var failures: Array = []
	for i in range(runs):
		var seed := seed_base + i
		var result := check_seed(floor_num, seed)
		if not result.is_empty():
			failures.append(result)

	return {
		"runs": runs,
		"floor": floor_num,
		"seed_base": seed_base,
		"failures": failures,
	}

func check_seed(floor_num: int, seed: int) -> Dictionary:
	var gen = DungeonGeneratorScript.new()
	gen.debug_generation_metrics_enabled = false
	gen.generate(floor_num, seed)

	var reasons: Array = []
	var start_room: RoomData = _get_room_by_type(gen.rooms, RoomDataScript.RoomType.START)
	var exit_room: RoomData = _get_room_by_type(gen.rooms, RoomDataScript.RoomType.EXIT)

	if gen.rooms.is_empty():
		reasons.append("no_rooms")
	if gen.corridors.size() <= 0:
		reasons.append("no_corridors")
	if gen.doorways.size() <= 0:
		reasons.append("no_doorways")
	if not _room_count_matches_square_grid(gen.rooms):
		reasons.append("room_count_not_square")
	if not _start_exit_roles_valid(start_room, exit_room):
		reasons.append("start_or_exit_missing")
	if not _start_exit_degree_valid(start_room, exit_room, gen.rooms.size()):
		reasons.append("start_or_exit_degree_invalid")
	if not _connections_bidirectional(gen.rooms):
		reasons.append("connections_not_bidirectional")
	if not _lattice_adjacency_rule_valid(gen.rooms, start_room, exit_room):
		reasons.append("lattice_adjacency_rule_invalid")
	if not _start_exit_distance_valid(gen.rooms, start_room, exit_room, int(gen.min_start_end_distance_rooms)):
		reasons.append("start_exit_distance_invalid")
	if not _is_start_exit_reachable(gen.tile_grid, start_room, exit_room):
		reasons.append("start_exit_unreachable")
	if not _doorway_corridor_references_valid(gen.corridors, gen.doorways):
		reasons.append("doorway_corridor_reference_invalid")
	if not _doorway_span_valid(gen.doorways):
		reasons.append("doorway_span_invalid")
	if not _corridor_doorway_orientation_valid(gen.corridors, gen.doorways):
		reasons.append("doorway_orientation_mismatch")
	if not _rooms_do_not_overlap(gen.rooms):
		reasons.append("room_overlap")

	if reasons.is_empty():
		return {}
	return {
		"seed": seed,
		"reasons": reasons,
		"rooms": gen.rooms.size(),
		"corridors": gen.corridors.size(),
		"doorways": gen.doorways.size(),
		"grid_size": int(gen.sampled_grid_size),
	}

func _get_room_by_type(rooms: Array, room_type: int) -> RoomData:
	for room_variant in rooms:
		var room: RoomData = room_variant
		if room.room_type == room_type:
			return room
	return null

func _room_count_matches_square_grid(rooms: Array) -> bool:
	var count := rooms.size()
	if count <= 0:
		return false
	var n := int(round(sqrt(float(count))))
	return n * n == count

func _start_exit_roles_valid(start_room: RoomData, exit_room: RoomData) -> bool:
	return start_room != null and exit_room != null and start_room != exit_room

func _start_exit_degree_valid(start_room: RoomData, exit_room: RoomData, room_count: int) -> bool:
	if start_room == null or exit_room == null:
		return false
	if room_count <= 1:
		return start_room.connected_to.is_empty() and exit_room.connected_to.is_empty()
	return start_room.connected_to.size() == 1 and exit_room.connected_to.size() == 1

func _connections_bidirectional(rooms: Array) -> bool:
	var room_lookup := _build_room_lookup(rooms)
	for room_variant in rooms:
		var room: RoomData = room_variant
		for neighbor_id_variant in room.connected_to:
			var neighbor_id := int(neighbor_id_variant)
			var neighbor: RoomData = room_lookup.get(neighbor_id, null)
			if neighbor == null:
				return false
			if not (room.id in neighbor.connected_to):
				return false
	return true

func _lattice_adjacency_rule_valid(rooms: Array, start_room: RoomData, exit_room: RoomData) -> bool:
	if start_room == null or exit_room == null:
		return false
	var start_id := start_room.id
	var exit_id := exit_room.id
	var by_coord := _build_lattice_lookup(rooms)

	for room_variant in rooms:
		var room: RoomData = room_variant
		if room.id == start_id or room.id == exit_id:
			continue
		var c := room.lattice_coord
		var neighbor_coords := [
			Vector2i(c.x + 1, c.y),
			Vector2i(c.x - 1, c.y),
			Vector2i(c.x, c.y + 1),
			Vector2i(c.x, c.y - 1),
		]
		for coord_variant in neighbor_coords:
			var nc: Vector2i = coord_variant
			var neighbor_id := int(by_coord.get(_key(nc), -1))
			if neighbor_id < 0:
				continue
			var has_edge := neighbor_id in room.connected_to
			if neighbor_id == start_id:
				var expected := room.id in start_room.connected_to
				if has_edge != expected:
					return false
			elif neighbor_id == exit_id:
				var expected := room.id in exit_room.connected_to
				if has_edge != expected:
					return false
			else:
				if not has_edge:
					return false
	return true

func _start_exit_distance_valid(rooms: Array, start_room: RoomData, exit_room: RoomData, min_distance: int) -> bool:
	if start_room == null or exit_room == null:
		return false
	var distances := _bfs_room_distances(rooms, start_room.id)
	if not distances.has(exit_room.id):
		return false
	return int(distances[exit_room.id]) >= min_distance

func _bfs_room_distances(rooms: Array, start_room_id: int) -> Dictionary:
	var out := {}
	var room_lookup := _build_room_lookup(rooms)
	if not room_lookup.has(start_room_id):
		return out

	var queue: Array = [start_room_id]
	var index := 0
	out[start_room_id] = 0

	while index < queue.size():
		var room_id := int(queue[index])
		index += 1
		var distance := int(out.get(room_id, 0))
		var room: RoomData = room_lookup.get(room_id, null)
		if room == null:
			continue
		for neighbor_id_variant in room.connected_to:
			var neighbor_id := int(neighbor_id_variant)
			if out.has(neighbor_id):
				continue
			out[neighbor_id] = distance + 1
			queue.append(neighbor_id)
	return out

func _is_start_exit_reachable(tile_grid: Array, start_room: RoomData, exit_room: RoomData) -> bool:
	if start_room == null or exit_room == null:
		return false
	return _is_floor_path_reachable(tile_grid, start_room.get_center_tile(), exit_room.get_center_tile())

func _is_floor_path_reachable(tile_grid: Array, start: Vector2i, goal: Vector2i) -> bool:
	var grid_w: int = tile_grid.size()
	if grid_w <= 0:
		return false
	var grid_h: int = tile_grid[0].size()
	if start == goal:
		return true
	if start.x < 0 or start.x >= grid_w or start.y < 0 or start.y >= grid_h:
		return false
	if goal.x < 0 or goal.x >= grid_w or goal.y < 0 or goal.y >= grid_h:
		return false
	if int(tile_grid[start.x][start.y]) != 1 or int(tile_grid[goal.x][goal.y]) != 1:
		return false

	var visited := {}
	var q: Array = [start]
	visited[_key(start)] = true
	var dirs: Array = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	var idx := 0
	while idx < q.size():
		var cur: Vector2i = q[idx]
		idx += 1
		if cur == goal:
			return true
		for d: Vector2i in dirs:
			var nxt: Vector2i = cur + d
			if nxt.x < 0 or nxt.x >= grid_w or nxt.y < 0 or nxt.y >= grid_h:
				continue
			if int(tile_grid[nxt.x][nxt.y]) != 1:
				continue
			var next_key := _key(nxt)
			if visited.has(next_key):
				continue
			visited[next_key] = true
			q.append(nxt)
	return false

func _doorway_span_valid(doorways: Array) -> bool:
	for doorway_variant in doorways:
		if typeof(doorway_variant) != TYPE_DICTIONARY:
			return false
		var doorway: Dictionary = doorway_variant
		var orientation := str(doorway.get("orientation", ""))
		if orientation != "east_west" and orientation != "north_south":
			return false
		var opening_span := int(doorway.get("opening_span_tiles", -1))
		if opening_span != 4:
			return false
		var center_offset := float(doorway.get("opening_center_offset_tiles", -99.0))
		if abs(center_offset - 1.5) > 0.001:
			return false
		var opening_tiles: Array = doorway.get("opening_tiles", [])
		if opening_tiles.size() != 4:
			return false
		var min_axis := 999999
		var max_axis := -999999
		var fixed_axis := 999999
		for tile_variant in opening_tiles:
			if typeof(tile_variant) != TYPE_VECTOR2I:
				return false
			var tile: Vector2i = tile_variant
			if orientation == "east_west":
				if fixed_axis == 999999:
					fixed_axis = tile.y
				elif tile.y != fixed_axis:
					return false
				min_axis = mini(min_axis, tile.x)
				max_axis = maxi(max_axis, tile.x)
			else:
				if fixed_axis == 999999:
					fixed_axis = tile.x
				elif tile.x != fixed_axis:
					return false
				min_axis = mini(min_axis, tile.y)
				max_axis = maxi(max_axis, tile.y)
		if orientation == "east_west":
			if max_axis - min_axis != 3:
				return false
		elif max_axis - min_axis != 3:
			return false
	return true

func _doorway_corridor_references_valid(corridors: Array, doorways: Array) -> bool:
	var doorway_by_id := {}
	for doorway_variant in doorways:
		if typeof(doorway_variant) != TYPE_DICTIONARY:
			continue
		var doorway: Dictionary = doorway_variant
		var doorway_id := int(doorway.get("id", -1))
		if doorway_id < 0:
			return false
		doorway_by_id[doorway_id] = doorway

	for corridor_variant in corridors:
		if typeof(corridor_variant) != TYPE_DICTIONARY:
			return false
		var corridor: Dictionary = corridor_variant
		var corridor_id := int(corridor.get("id", -1))
		var room_a_id := int(corridor.get("room_a_id", -1))
		var room_b_id := int(corridor.get("room_b_id", -1))
		var doorway_a_id := int(corridor.get("doorway_a_id", -1))
		var doorway_b_id := int(corridor.get("doorway_b_id", -1))
		if corridor_id < 0 or room_a_id < 0 or room_b_id < 0 or doorway_a_id < 0 or doorway_b_id < 0:
			return false
		if not doorway_by_id.has(doorway_a_id) or not doorway_by_id.has(doorway_b_id):
			return false

		var doorway_a: Dictionary = doorway_by_id[doorway_a_id]
		var doorway_b: Dictionary = doorway_by_id[doorway_b_id]
		if int(doorway_a.get("corridor_id", -1)) != corridor_id:
			return false
		if int(doorway_b.get("corridor_id", -1)) != corridor_id:
			return false

		var doorway_a_room := int(doorway_a.get("room_id", -1))
		var doorway_b_room := int(doorway_b.get("room_id", -1))
		if doorway_a_room != room_a_id and doorway_a_room != room_b_id:
			return false
		if doorway_b_room != room_a_id and doorway_b_room != room_b_id:
			return false
	return true

func _corridor_doorway_orientation_valid(corridors: Array, doorways: Array) -> bool:
	var doorway_by_id := {}
	for doorway_variant in doorways:
		if typeof(doorway_variant) != TYPE_DICTIONARY:
			continue
		var doorway: Dictionary = doorway_variant
		doorway_by_id[int(doorway.get("id", -1))] = doorway

	for corridor_variant in corridors:
		if typeof(corridor_variant) != TYPE_DICTIONARY:
			return false
		var corridor: Dictionary = corridor_variant
		var doorway_a: Dictionary = doorway_by_id.get(int(corridor.get("doorway_a_id", -1)), {})
		var doorway_b: Dictionary = doorway_by_id.get(int(corridor.get("doorway_b_id", -1)), {})
		if doorway_a.is_empty() or doorway_b.is_empty():
			return false

		var tile_a: Vector2i = doorway_a.get("tile", Vector2i.ZERO)
		var tile_b: Vector2i = doorway_b.get("tile", Vector2i.ZERO)
		var expected_orientation := ""
		if tile_a.y == tile_b.y:
			expected_orientation = "north_south"
		elif tile_a.x == tile_b.x:
			expected_orientation = "east_west"
		else:
			return false

		if str(doorway_a.get("orientation", "")) != expected_orientation:
			return false
		if str(doorway_b.get("orientation", "")) != expected_orientation:
			return false
	return true

func _rooms_do_not_overlap(rooms: Array) -> bool:
	for i in range(rooms.size()):
		var a: RoomData = rooms[i]
		var ar: Rect2i = a.grid_rect
		for j in range(i + 1, rooms.size()):
			var b: RoomData = rooms[j]
			var br: Rect2i = b.grid_rect
			if _rects_overlap(ar, br):
				return false
	return true

func _rects_overlap(a: Rect2i, b: Rect2i) -> bool:
	if a.position.x + a.size.x <= b.position.x:
		return false
	if b.position.x + b.size.x <= a.position.x:
		return false
	if a.position.y + a.size.y <= b.position.y:
		return false
	if b.position.y + b.size.y <= a.position.y:
		return false
	return true

func _build_room_lookup(rooms: Array) -> Dictionary:
	var out := {}
	for room_variant in rooms:
		var room: RoomData = room_variant
		out[room.id] = room
	return out

func _build_lattice_lookup(rooms: Array) -> Dictionary:
	var out := {}
	for room_variant in rooms:
		var room: RoomData = room_variant
		out[_key(room.lattice_coord)] = room.id
	return out

func _key(v: Vector2i) -> String:
	return "%d:%d" % [v.x, v.y]
