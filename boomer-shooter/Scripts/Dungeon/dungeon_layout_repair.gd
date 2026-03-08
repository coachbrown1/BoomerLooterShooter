extends RefCounted
class_name DungeonLayoutRepair

var _gen
var _portal_validator
var _graph_utils

func _init(generator, portal_validator, graph_utils) -> void:
	_gen = generator
	_portal_validator = portal_validator
	_graph_utils = graph_utils

func validate_and_repair_layout() -> void:
	_sanitize_layout_records()
	var repaired: bool = repair_disconnected_room_graph()
	if repaired:
		_sanitize_layout_records()

func _sanitize_layout_records() -> void:
	prune_invalid_doorways()
	prune_invalid_corridors()
	rebuild_room_links_from_records()

func prune_invalid_doorways() -> void:
	var room_lookup: Dictionary = _gen._build_room_lookup()
	var valid: Array = []
	var seen: Dictionary = {}
	for doorway in _gen.doorways:
		if typeof(doorway) != TYPE_DICTIONARY:
			continue
		if not doorway.has("id") or not doorway.has("tile") or not doorway.has("orientation"):
			continue
		var id := int(doorway["id"])
		if seen.has(id):
			continue
		var room_id := int(doorway.get("room_id", -1))
		if room_id >= 0 and not room_lookup.has(room_id):
			continue
		if not _portal_validator.is_portal_valid(doorway, false, false):
			continue
		if not _portal_validator.doorway_opening_has_passage(doorway):
			continue
		seen[id] = true
		valid.append(doorway)

	_gen.doorways = valid
	_gen._doorway_keys = {}
	var max_id := -1
	for doorway in _gen.doorways:
		var id := int(doorway.get("id", -1))
		var tile: Vector2i = doorway["tile"]
		_gen._doorway_keys[_gen._grid_key(tile.x, tile.y)] = id
		max_id = maxi(max_id, id)
	_gen._doorway_next_id = max_id + 1

func prune_invalid_corridors() -> void:
	var room_lookup: Dictionary = _gen._build_room_lookup()
	var doorway_id_set: Dictionary = {}
	for doorway in _gen.doorways:
		doorway_id_set[int(doorway.get("id", -1))] = true

	var valid: Array = []
	var max_id := -1
	for corridor in _gen.corridors:
		if typeof(corridor) != TYPE_DICTIONARY:
			continue
		var id := int(corridor.get("id", -1))
		var room_a_id := int(corridor.get("room_a_id", -1))
		var room_b_id := int(corridor.get("room_b_id", -1))
		var doorway_a_id := int(corridor.get("doorway_a_id", -1))
		var doorway_b_id := int(corridor.get("doorway_b_id", -1))
		if id < 0 or room_a_id < 0 or room_b_id < 0:
			continue
		if not room_lookup.has(room_a_id) or not room_lookup.has(room_b_id):
			continue
		if not doorway_id_set.has(doorway_a_id) or not doorway_id_set.has(doorway_b_id):
			continue
		var tiles: Array = corridor.get("tiles", [])
		if tiles.is_empty():
			continue
		var has_floor := false
		for t in tiles:
			if typeof(t) != TYPE_VECTOR2I:
				continue
			var v: Vector2i = t
			if v.x >= 0 and v.x < _gen.GRID_W and v.y >= 0 and v.y < _gen.GRID_H and _gen.tile_grid[v.x][v.y] == _gen.TILE_FLOOR:
				has_floor = true
				break
		if not has_floor:
			continue
		valid.append(corridor)
		max_id = maxi(max_id, id)

	_gen.corridors = valid
	_gen._corridor_next_id = max_id + 1
	_gen._rebuild_corridor_tile_owner_map()

func rebuild_room_links_from_records() -> void:
	var room_lookup: Dictionary = _gen._build_room_lookup()
	for room in _gen.rooms:
		room.connected_to = []
		room.corridor_ids = []
		room.doorway_ids = []

	for corridor in _gen.corridors:
		var room_a_id := int(corridor.get("room_a_id", -1))
		var room_b_id := int(corridor.get("room_b_id", -1))
		var corridor_id := int(corridor.get("id", -1))
		var room_a: RoomData = room_lookup.get(room_a_id, null)
		var room_b: RoomData = room_lookup.get(room_b_id, null)
		if room_a == null or room_b == null:
			continue
		if not (room_b_id in room_a.connected_to):
			room_a.connected_to.append(room_b_id)
		if not (room_a_id in room_b.connected_to):
			room_b.connected_to.append(room_a_id)
		if corridor_id >= 0:
			room_a.corridor_ids.append(corridor_id)
			room_b.corridor_ids.append(corridor_id)

	for doorway in _gen.doorways:
		var doorway_id := int(doorway.get("id", -1))
		var room_id := int(doorway.get("room_id", -1))
		if doorway_id < 0:
			continue
		var room: RoomData = room_lookup.get(room_id, null)
		if room != null:
			room.doorway_ids.append(doorway_id)

func repair_disconnected_room_graph() -> bool:
	var room_lookup: Dictionary = _gen._build_room_lookup()
	var components: Array = _graph_utils.collect_room_components(room_lookup)
	if components.size() <= 1:
		return false

	var attempts: int = 0
	var max_attempts: int = maxi(8, _gen.rooms.size() * 4)
	var repaired_any: bool = false
	while components.size() > 1 and attempts < max_attempts:
		attempts += 1
		var pair: Dictionary = _graph_utils.pick_closest_component_room_pair(components, room_lookup)
		if pair.is_empty():
			break
		var room_a: RoomData = pair.get("a", null)
		var room_b: RoomData = pair.get("b", null)
		if room_a == null or room_b == null:
			break
		if _gen._try_connect_rooms(room_a, room_b):
			repaired_any = true
			components = _graph_utils.collect_room_components(room_lookup)
	return repaired_any

func collect_room_components(room_lookup: Dictionary) -> Array:
	return _graph_utils.collect_room_components(room_lookup)

func pick_closest_component_room_pair(components: Array, room_lookup: Dictionary) -> Dictionary:
	return _graph_utils.pick_closest_component_room_pair(components, room_lookup)
