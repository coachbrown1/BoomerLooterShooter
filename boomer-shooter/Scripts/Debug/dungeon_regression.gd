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

	var reasons: Array[String] = []
	if gen.corridors.size() <= 0:
		reasons.append("no_corridors")
	if gen.doorways.size() <= 0:
		reasons.append("no_doorways")
	if not _is_start_exit_reachable(gen.tile_grid, gen.rooms):
		reasons.append("start_exit_unreachable")
	if not _corridors_respect_room_boundaries(gen.corridors, gen.rooms):
		reasons.append("corridor_crosses_third_party_room")
	if not _doorway_corridor_references_valid(gen.corridors, gen.doorways):
		reasons.append("doorway_corridor_reference_invalid")

	if reasons.is_empty():
		return {}
	return {
		"seed": seed,
		"reasons": reasons,
		"rooms": gen.rooms.size(),
		"corridors": gen.corridors.size(),
		"doorways": gen.doorways.size(),
	}

func _is_start_exit_reachable(tile_grid: Array, rooms: Array) -> bool:
	var start: Vector2i = Vector2i(-1, -1)
	var exit: Vector2i = Vector2i(-1, -1)
	for room_variant in rooms:
		var room: RoomData = room_variant
		if room.room_type == RoomDataScript.RoomType.START:
			start = room.get_center_tile()
		elif room.room_type == RoomDataScript.RoomType.EXIT:
			exit = room.get_center_tile()

	if start.x < 0 or exit.x < 0:
		return false
	return _is_floor_path_reachable(tile_grid, start, exit)

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
	var q: Array[Vector2i] = [start]
	visited[_key(start)] = true
	var dirs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
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
			var key := _key(nxt)
			if visited.has(key):
				continue
			visited[key] = true
			q.append(nxt)
	return false

func _corridors_respect_room_boundaries(corridors: Array, rooms: Array) -> bool:
	var room_owner := _build_room_owner_map(rooms)
	for corridor_variant in corridors:
		if typeof(corridor_variant) != TYPE_DICTIONARY:
			continue
		var room_a_id := int(corridor_variant.get("room_a_id", -1))
		var room_b_id := int(corridor_variant.get("room_b_id", -1))
		var tiles: Array = corridor_variant.get("tiles", [])
		for tile_variant in tiles:
			if typeof(tile_variant) != TYPE_VECTOR2I:
				continue
			var tile: Vector2i = tile_variant
			var owner := int(room_owner.get(_key(tile), -1))
			if owner < 0:
				continue
			if owner == room_a_id or owner == room_b_id:
				continue
			return false
	return true

func _build_room_owner_map(rooms: Array) -> Dictionary:
	var out := {}
	for room_variant in rooms:
		var room: RoomData = room_variant
		var rect: Rect2i = room.grid_rect
		for x in range(rect.position.x, rect.position.x + rect.size.x):
			for z in range(rect.position.y, rect.position.y + rect.size.y):
				out["%d:%d" % [x, z]] = room.id
	return out

func _doorway_corridor_references_valid(corridors: Array, doorways: Array) -> bool:
	var doorway_by_id: Dictionary = {}
	for doorway_variant in doorways:
		if typeof(doorway_variant) != TYPE_DICTIONARY:
			continue
		var doorway: Dictionary = doorway_variant
		var doorway_id: int = int(doorway.get("id", -1))
		if doorway_id < 0:
			return false
		doorway_by_id[doorway_id] = doorway

	for corridor_variant in corridors:
		if typeof(corridor_variant) != TYPE_DICTIONARY:
			return false
		var corridor: Dictionary = corridor_variant
		var corridor_id: int = int(corridor.get("id", -1))
		var room_a_id: int = int(corridor.get("room_a_id", -1))
		var room_b_id: int = int(corridor.get("room_b_id", -1))
		var doorway_a_id: int = int(corridor.get("doorway_a_id", -1))
		var doorway_b_id: int = int(corridor.get("doorway_b_id", -1))
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

		var doorway_a_room: int = int(doorway_a.get("room_id", -1))
		var doorway_b_room: int = int(doorway_b.get("room_id", -1))
		var a_matches: bool = doorway_a_room == room_a_id or doorway_a_room == room_b_id
		var b_matches: bool = doorway_b_room == room_a_id or doorway_b_room == room_b_id
		if not a_matches or not b_matches:
			return false
	return true

func _key(v: Vector2i) -> String:
	return "%d:%d" % [v.x, v.y]
