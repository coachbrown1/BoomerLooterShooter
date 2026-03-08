extends RefCounted
class_name DungeonPortalValidator

var _gen

func _init(generator) -> void:
	_gen = generator

func can_use_portal_candidate(candidate: Dictionary) -> bool:
	return is_portal_valid(candidate, false, true, true, false)

func register_doorway(portal: Dictionary, room_id: int = -1, corridor_id: int = -1) -> int:
	_gen._doorway_register_attempts += 1
	if not portal.has("tile") or not portal.has("orientation"):
		return -1

	var tile: Vector2i = portal["tile"]
	if tile.x < 0 or tile.x >= _gen.GRID_W or tile.y < 0 or tile.y >= _gen.GRID_H:
		return -1
	if _gen.tile_grid[tile.x][tile.y] != _gen.TILE_FLOOR:
		return -1

	var orientation := str(portal["orientation"])
	if orientation != "east_west" and orientation != "north_south":
		return -1
	var wall_line_key := str(portal.get("wall_line_key", make_wall_line_key(tile, orientation)))

	var key: String = _gen._grid_key(tile.x, tile.y)
	if _gen._doorway_keys.has(key):
		return int(_gen._doorway_keys[key])

	if not is_portal_registration_valid(portal):
		return -1

	var opening_span_tiles: int = _gen.DOORWAY_SPAN_TILES
	var opening_offsets := build_opening_offsets(opening_span_tiles)
	var opening_center_offset_tiles := get_offsets_center(opening_offsets)

	var opening_tiles: Array[Vector2i] = []
	if orientation == "east_west":
		for dx in opening_offsets:
			_gen._set_floor(tile.x + dx, tile.y)
			opening_tiles.append(Vector2i(tile.x + dx, tile.y))
	else:
		for dz in opening_offsets:
			_gen._set_floor(tile.x, tile.y + dz)
			opening_tiles.append(Vector2i(tile.x, tile.y + dz))

	var pinch_tiles := enforce_threshold_wall(tile, orientation, opening_offsets)
	if pinch_tiles.is_empty():
		return -1

	var doorway_id: int = _gen._doorway_next_id
	_gen._doorway_next_id += 1
	_gen._doorway_keys[key] = doorway_id
	_gen.doorways.append({
		"id": doorway_id,
		"tile": tile,
		"orientation": orientation,
		"wall_line_key": wall_line_key,
		"biome": _gen._current_biome,
		"room_id": room_id,
		"corridor_id": corridor_id,
		"opening_tiles": opening_tiles,
		"pinch_tiles": pinch_tiles,
		"opening_span_tiles": opening_span_tiles,
		"opening_center_offset_tiles": opening_center_offset_tiles,
	})
	_gen._doorway_register_successes += 1
	return doorway_id

func build_opening_offsets(span_tiles: int) -> Array[int]:
	var span := maxi(1, span_tiles)
	var offsets: Array[int] = []
	if span % 2 == 1:
		var half := span / 2
		for i in range(-half, half + 1):
			offsets.append(i)
	else:
		for i in range(span):
			offsets.append(i)
	return offsets

func get_offsets_center(offsets: Array[int]) -> float:
	if offsets.is_empty():
		return 0.0
	var total := 0.0
	for o in offsets:
		total += float(o)
	return total / float(offsets.size())

func has_required_side_walls(
	tile: Vector2i,
	orientation: String,
	opening_offsets: Array[int],
	portal: Dictionary,
	require_dual_passage: bool = true
) -> bool:
	var room_id := int(portal.get("room_id", _gen.OWNER_NONE))
	var corridor_id := int(portal.get("corridor_id", _gen.OWNER_NONE))
	var enforce_boundary := room_id >= 0 and corridor_id >= 0

	for offset in opening_offsets:
		if orientation == "east_west":
			var open_x := tile.x + offset
			if open_x < 0 or open_x >= _gen.GRID_W or tile.y - 1 < 0 or tile.y + 1 >= _gen.GRID_H:
				return false
			var north_floor: bool = _gen.tile_grid[open_x][tile.y - 1] == _gen.TILE_FLOOR
			var south_floor: bool = _gen.tile_grid[open_x][tile.y + 1] == _gen.TILE_FLOOR
			if require_dual_passage:
				if not north_floor or not south_floor:
					return false
			else:
				if not north_floor and not south_floor:
					return false
			if enforce_boundary and not is_room_corridor_boundary(
				Vector2i(open_x, tile.y - 1),
				Vector2i(open_x, tile.y + 1),
				room_id,
				corridor_id
			):
				return false
		else:
			var open_z := tile.y + offset
			if open_z < 0 or open_z >= _gen.GRID_H or tile.x - 1 < 0 or tile.x + 1 >= _gen.GRID_W:
				return false
			var west_floor: bool = _gen.tile_grid[tile.x - 1][open_z] == _gen.TILE_FLOOR
			var east_floor: bool = _gen.tile_grid[tile.x + 1][open_z] == _gen.TILE_FLOOR
			if require_dual_passage:
				if not west_floor or not east_floor:
					return false
			else:
				if not west_floor and not east_floor:
					return false
			if enforce_boundary and not is_room_corridor_boundary(
				Vector2i(tile.x - 1, open_z),
				Vector2i(tile.x + 1, open_z),
				room_id,
				corridor_id
			):
				return false
	return true

func is_portal_registration_valid(portal: Dictionary) -> bool:
	return is_portal_valid(portal, true, true, true, true)

func is_portal_valid(
	portal: Dictionary,
	require_threshold_wall: bool,
	check_spacing: bool,
	track_metrics: bool = false,
	require_dual_passage: bool = true
) -> bool:
	if typeof(portal) != TYPE_DICTIONARY:
		_gen._track_portal_reject("invalid_type", track_metrics)
		return false
	if not portal.has("tile") or not portal.has("orientation"):
		_gen._track_portal_reject("missing_fields", track_metrics)
		return false
	var tile: Vector2i = portal["tile"]
	if tile.x < 0 or tile.x >= _gen.GRID_W or tile.y < 0 or tile.y >= _gen.GRID_H:
		_gen._track_portal_reject("out_of_bounds", track_metrics)
		return false
	if _gen.tile_grid[tile.x][tile.y] != _gen.TILE_FLOOR:
		_gen._track_portal_reject("not_floor_tile", track_metrics)
		return false

	var orientation := str(portal["orientation"])
	if orientation != "east_west" and orientation != "north_south":
		_gen._track_portal_reject("invalid_orientation", track_metrics)
		return false
	var wall_line_key := str(portal.get("wall_line_key", make_wall_line_key(tile, orientation)))
	var opening_offsets := build_opening_offsets(_gen.DOORWAY_SPAN_TILES)
	if check_spacing and is_doorway_too_close_same_wall(tile, orientation, wall_line_key):
		_gen._track_portal_reject("spacing_too_close", track_metrics)
		return false
	if not has_required_side_walls(tile, orientation, opening_offsets, portal, require_dual_passage):
		_gen._track_portal_reject("missing_side_walls_or_passage", track_metrics)
		return false
	if require_threshold_wall and not can_form_threshold_wall(tile, orientation, opening_offsets):
		_gen._track_portal_reject("threshold_span_invalid", track_metrics)
		return false
	return true

func doorway_opening_has_passage(doorway: Dictionary) -> bool:
	var orientation := str(doorway.get("orientation", ""))
	if orientation != "east_west" and orientation != "north_south":
		return false
	var opening_tiles: Array = doorway.get("opening_tiles", [])
	if opening_tiles.is_empty():
		var tile: Vector2i = doorway.get("tile", Vector2i(-1, -1))
		opening_tiles = [tile]
	for t in opening_tiles:
		if typeof(t) != TYPE_VECTOR2I:
			return false
		var tile: Vector2i = t
		if tile.x < 0 or tile.x >= _gen.GRID_W or tile.y < 0 or tile.y >= _gen.GRID_H:
			return false
		if _gen.tile_grid[tile.x][tile.y] != _gen.TILE_FLOOR:
			return false
		if orientation == "east_west":
			if tile.y - 1 < 0 or tile.y + 1 >= _gen.GRID_H:
				return false
			if _gen.tile_grid[tile.x][tile.y - 1] != _gen.TILE_FLOOR or _gen.tile_grid[tile.x][tile.y + 1] != _gen.TILE_FLOOR:
				return false
		else:
			if tile.x - 1 < 0 or tile.x + 1 >= _gen.GRID_W:
				return false
			if _gen.tile_grid[tile.x - 1][tile.y] != _gen.TILE_FLOOR or _gen.tile_grid[tile.x + 1][tile.y] != _gen.TILE_FLOOR:
				return false
	return true

func can_form_threshold_wall(tile: Vector2i, orientation: String, opening_offsets: Array[int]) -> bool:
	if opening_offsets.is_empty():
		return false
	var min_offset := opening_offsets[0]
	var max_offset := opening_offsets[opening_offsets.size() - 1]
	if orientation == "east_west":
		var row := tile.y
		var left_wall := scan_to_wall_x(tile.x + min_offset - 1, row, -1)
		var right_wall := scan_to_wall_x(tile.x + max_offset + 1, row, 1)
		if left_wall == -1 or right_wall == -1:
			return false
		return (right_wall - left_wall - 1) <= _gen.MAX_DOORWAY_WALL_SPAN
	else:
		var col := tile.x
		var top_wall := scan_to_wall_z(col, tile.y + min_offset - 1, -1)
		var bottom_wall := scan_to_wall_z(col, tile.y + max_offset + 1, 1)
		if top_wall == -1 or bottom_wall == -1:
			return false
		return (bottom_wall - top_wall - 1) <= _gen.MAX_DOORWAY_WALL_SPAN

func enforce_threshold_wall(tile: Vector2i, orientation: String, opening_offsets: Array[int]) -> Array:
	var placed: Array = []
	if opening_offsets.is_empty():
		return placed

	var open_map: Dictionary = {}
	var min_offset := opening_offsets[0]
	var max_offset := opening_offsets[opening_offsets.size() - 1]
	if orientation == "east_west":
		for dx in opening_offsets:
			open_map[_gen._grid_key(tile.x + dx, tile.y)] = true
		var left_wall := scan_to_wall_x(tile.x + min_offset - 1, tile.y, -1)
		var right_wall := scan_to_wall_x(tile.x + max_offset + 1, tile.y, 1)
		if left_wall == -1 or right_wall == -1:
			return []
		if (right_wall - left_wall - 1) > _gen.MAX_DOORWAY_WALL_SPAN:
			return []
		for x in range(left_wall + 1, right_wall):
			var k: String = _gen._grid_key(x, tile.y)
			if open_map.has(k):
				continue
			_gen._set_wall(x, tile.y)
			_gen._protected_wall_keys[k] = true
			placed.append(Vector2i(x, tile.y))
	else:
		for dz in opening_offsets:
			open_map[_gen._grid_key(tile.x, tile.y + dz)] = true
		var top_wall := scan_to_wall_z(tile.x, tile.y + min_offset - 1, -1)
		var bottom_wall := scan_to_wall_z(tile.x, tile.y + max_offset + 1, 1)
		if top_wall == -1 or bottom_wall == -1:
			return []
		if (bottom_wall - top_wall - 1) > _gen.MAX_DOORWAY_WALL_SPAN:
			return []
		for z in range(top_wall + 1, bottom_wall):
			var k: String = _gen._grid_key(tile.x, z)
			if open_map.has(k):
				continue
			_gen._set_wall(tile.x, z)
			_gen._protected_wall_keys[k] = true
			placed.append(Vector2i(tile.x, z))

	return placed

func scan_to_wall_x(start_x: int, z: int, dir: int) -> int:
	var x := start_x
	while x >= 0 and x < _gen.GRID_W:
		if _gen.tile_grid[x][z] == _gen.TILE_WALL:
			return x
		x += dir
	return -1

func scan_to_wall_z(x: int, start_z: int, dir: int) -> int:
	var z := start_z
	while z >= 0 and z < _gen.GRID_H:
		if _gen.tile_grid[x][z] == _gen.TILE_WALL:
			return z
		z += dir
	return -1

func tile_has_room_owner(tile: Vector2i, room_id: int) -> bool:
	if room_id < 0:
		return false
	return int(_gen._room_tile_owner.get(_gen._grid_key(tile.x, tile.y), _gen.OWNER_NONE)) == room_id

func tile_has_corridor_owner(tile: Vector2i, corridor_id: int) -> bool:
	if corridor_id < 0:
		return false
	return int(_gen._corridor_tile_owner.get(_gen._grid_key(tile.x, tile.y), _gen.OWNER_NONE)) == corridor_id

func is_room_corridor_boundary(side_a: Vector2i, side_b: Vector2i, room_id: int, corridor_id: int) -> bool:
	var a_room := tile_has_room_owner(side_a, room_id)
	var b_room := tile_has_room_owner(side_b, room_id)
	if a_room == b_room:
		return false
	if a_room:
		return tile_has_corridor_owner(side_b, corridor_id)
	return tile_has_corridor_owner(side_a, corridor_id)

func is_doorway_too_close_same_wall(tile: Vector2i, orientation: String, wall_line_key: String) -> bool:
	for doorway in _gen.doorways:
		if typeof(doorway) != TYPE_DICTIONARY:
			continue
		if str(doorway.get("orientation", "")) != orientation:
			continue
		if str(doorway.get("wall_line_key", "")) != wall_line_key:
			continue

		var other_tile: Vector2i = doorway.get("tile", Vector2i(-9999, -9999))
		if orientation == "east_west" and abs(other_tile.x - tile.x) < _gen.MIN_SAME_WALL_DOORWAY_SPACING:
			return true
		if orientation == "north_south" and abs(other_tile.y - tile.y) < _gen.MIN_SAME_WALL_DOORWAY_SPACING:
			return true
	return false

func build_room_doorway_candidates(room: RoomData) -> Array:
	var candidates: Array = []
	if room == null:
		return candidates

	var rect := room.grid_rect
	var left := rect.position.x
	var top := rect.position.y
	var right := rect.position.x + rect.size.x - 1
	var bottom := rect.position.y + rect.size.y - 1
	var opening_offsets := build_opening_offsets(_gen.DOORWAY_SPAN_TILES)
	var min_offset := opening_offsets[0]
	var max_offset := opening_offsets[opening_offsets.size() - 1]

	for z in range(top + 1, bottom):
		if offsets_fit_line(z, min_offset, max_offset, top + 1, bottom - 1):
			candidates.append({
				"tile": Vector2i(left, z),
				"orientation": "north_south",
				"wall_line_key": "v:%d" % left,
			})
			candidates.append({
				"tile": Vector2i(right, z),
				"orientation": "north_south",
				"wall_line_key": "v:%d" % right,
			})

	for x in range(left + 1, right):
		if offsets_fit_line(x, min_offset, max_offset, left + 1, right - 1):
			candidates.append({
				"tile": Vector2i(x, top),
				"orientation": "east_west",
				"wall_line_key": "h:%d" % top,
			})
			candidates.append({
				"tile": Vector2i(x, bottom),
				"orientation": "east_west",
				"wall_line_key": "h:%d" % bottom,
			})

	return candidates

func offsets_fit_line(anchor: int, min_offset: int, max_offset: int, min_line: int, max_line: int) -> bool:
	var from_val := anchor + min_offset
	var to_val := anchor + max_offset
	return from_val >= min_line and to_val <= max_line

func make_wall_line_key(tile: Vector2i, orientation: String) -> String:
	if orientation == "east_west":
		return "h:%d" % tile.y
	return "v:%d" % tile.x
