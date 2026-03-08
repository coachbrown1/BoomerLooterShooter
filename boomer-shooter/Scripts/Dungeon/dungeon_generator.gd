extends RefCounted
class_name DungeonGenerator

const PortalValidatorScript = preload("res://Scripts/Dungeon/dungeon_portal_validator.gd")
const LayoutRepairScript = preload("res://Scripts/Dungeon/dungeon_layout_repair.gd")
const GraphUtilsScript = preload("res://Scripts/Dungeon/dungeon_graph_utils.gd")
const CarvingScript = preload("res://Scripts/Dungeon/dungeon_carving.gd")

# ---- Constants ----
const GRID_W: int = 60
const GRID_H: int = 60
const MIN_LEAF: int = 10		# minimum BSP leaf size in tiles
const MIN_ROOM: int = 6			# minimum room dimension in tiles
const CORRIDOR_HALF: int = 1	# corridor half-width in tiles (total = 3)

# ---- Tile types ----
const TILE_WALL: int = 0
const TILE_FLOOR: int = 1

# ---- Output ----
var tile_grid: Array = []		# [x][z] -> TILE_WALL / TILE_FLOOR
var rooms: Array = []			# Array of RoomData
var corridors: Array = []		# Array of { "id", "room_a_id", "room_b_id", "tiles", "width_tiles", "doorway_a_id", "doorway_b_id" }
var doorways: Array = []		# Array of { "id", "tile", "orientation", "room_id", "corridor_id", ... }
var rng: RandomNumberGenerator

var _doorway_keys := {}
var _protected_wall_keys := {}
var _room_tile_owner := {}		# "x:z" -> room_id
var _corridor_tile_owner := {}	# "x:z" -> corridor_id
var _corridor_next_id: int = 0
var _doorway_next_id: int = 0
var _current_biome: String = "crypt"
const DOORWAY_SPAN_TILES: int = 2
const MIN_SAME_WALL_DOORWAY_SPACING: int = 4
const MAX_DOORWAY_WALL_SPAN: int = 10
const OWNER_NONE: int = -1
const MIN_ROOM_GRAPH_DEGREE: int = 2
const DEFAULT_DEBUG_GENERATION_METRICS: bool = true
var debug_generation_metrics_enabled: bool = DEFAULT_DEBUG_GENERATION_METRICS

var _connect_attempts: int = 0
var _connect_successes: int = 0
var _doorway_register_attempts: int = 0
var _doorway_register_successes: int = 0
var _portal_reject_counts := {}
var _portal_validator: DungeonPortalValidator
var _layout_repair: DungeonLayoutRepair
var _graph_utils: DungeonGraphUtils
var _carving: DungeonCarving

# -------------------------------------------------------
# Public entry point
# -------------------------------------------------------
func generate(floor_num: int, seed_val: int = 0) -> void:
	if _portal_validator == null:
		_portal_validator = PortalValidatorScript.new(self)
	if _graph_utils == null:
		_graph_utils = GraphUtilsScript.new(self)
	if _carving == null:
		_carving = CarvingScript.new(self)
	if _layout_repair == null:
		_layout_repair = LayoutRepairScript.new(self, _portal_validator, _graph_utils)

	rng = RandomNumberGenerator.new()
	rng.seed = seed_val if seed_val != 0 else int(Time.get_unix_time_from_system())

	var biomes: PackedStringArray = ["crypt", "fungal", "lava"]
	_current_biome = biomes[floor_num % biomes.size()]

	_init_grid()
	rooms = []
	corridors = []
	doorways = []
	_doorway_keys = {}
	_protected_wall_keys = {}
	_room_tile_owner = {}
	_corridor_tile_owner = {}
	_corridor_next_id = 0
	_doorway_next_id = 0
	_reset_debug_metrics()

	# BSP split
	var root := _BSPLeaf.new(Rect2i(1, 1, GRID_W - 2, GRID_H - 2))
	_split_leaf(root)

	# Carve rooms from leaves
	var room_id := 0
	_carve_rooms(root, room_id)

	# Connect sibling rooms with L-shaped corridors
	_connect_leaves(root)

	# Add extra loop corridors to eliminate dead ends
	_add_loop_corridors()
	_enforce_min_room_degree(MIN_ROOM_GRAPH_DEGREE)

	# Validate and repair semantic records before assigning roles.
	_validate_and_repair_layout()

	# Assign start/exit using room-graph distance
	_assign_start_and_exit()

	# Last-resort floor-path guarantee for playability.
	_ensure_start_exit_floor_path()

	# Assign biome (one per floor, cycles through 3)
	for r in rooms:
		r.biome = _current_biome

	_log_generation_metrics()

# -------------------------------------------------------
# Grid helpers
# -------------------------------------------------------
func _init_grid() -> void:
	tile_grid = []
	for x in range(GRID_W):
		var col := []
		for _z in range(GRID_H):
			col.append(TILE_WALL)
		tile_grid.append(col)

func _set_floor(x: int, z: int) -> void:
	if x >= 0 and x < GRID_W and z >= 0 and z < GRID_H:
		var key := "%d:%d" % [x, z]
		if _protected_wall_keys.has(key):
			return
		tile_grid[x][z] = TILE_FLOOR

func _set_floor_force(x: int, z: int) -> void:
	if x >= 0 and x < GRID_W and z >= 0 and z < GRID_H:
		tile_grid[x][z] = TILE_FLOOR

func _set_wall(x: int, z: int) -> void:
	if x >= 0 and x < GRID_W and z >= 0 and z < GRID_H:
		tile_grid[x][z] = TILE_WALL
		_corridor_tile_owner.erase(_grid_key(x, z))

func _carve_rect(rect: Rect2i, room_id: int = OWNER_NONE) -> void:
	for x in range(rect.position.x, rect.position.x + rect.size.x):
		for z in range(rect.position.y, rect.position.y + rect.size.y):
			_set_floor(x, z)
			if room_id >= 0:
				_room_tile_owner[_grid_key(x, z)] = room_id

func _carve_corridor(ax: int, az: int, bx: int, bz: int, corridor_id: int = OWNER_NONE) -> Dictionary:
	return _carving.carve_corridor(ax, az, bx, bz, corridor_id)

# -------------------------------------------------------
# BSP
# -------------------------------------------------------
class _BSPLeaf:
	var rect: Rect2i
	var left: _BSPLeaf
	var right: _BSPLeaf
	var room: RoomData	# only on terminal leaves

	func _init(r: Rect2i) -> void:
		rect = r

func _split_leaf(leaf: _BSPLeaf) -> void:
	if leaf.left != null or leaf.right != null:
		return	# already split

	var can_h := leaf.rect.size.x >= MIN_LEAF * 2
	var can_v := leaf.rect.size.y >= MIN_LEAF * 2

	if not can_h and not can_v:
		return	# too small

	var split_h: bool
	if can_h and can_v:
		split_h = rng.randi() % 2 == 0
	else:
		split_h = can_h

	if split_h:
		var split := rng.randi_range(MIN_LEAF, leaf.rect.size.x - MIN_LEAF)
		leaf.left  = _BSPLeaf.new(Rect2i(leaf.rect.position, Vector2i(split, leaf.rect.size.y)))
		leaf.right = _BSPLeaf.new(Rect2i(
			Vector2i(leaf.rect.position.x + split, leaf.rect.position.y),
			Vector2i(leaf.rect.size.x - split, leaf.rect.size.y)
		))
	else:
		var split := rng.randi_range(MIN_LEAF, leaf.rect.size.y - MIN_LEAF)
		leaf.left  = _BSPLeaf.new(Rect2i(leaf.rect.position, Vector2i(leaf.rect.size.x, split)))
		leaf.right = _BSPLeaf.new(Rect2i(
			Vector2i(leaf.rect.position.x, leaf.rect.position.y + split),
			Vector2i(leaf.rect.size.x, leaf.rect.size.y - split)
		))

	_split_leaf(leaf.left)
	_split_leaf(leaf.right)

func _carve_rooms(leaf: _BSPLeaf, id: int) -> int:
	if leaf.left == null and leaf.right == null:
		# Terminal leaf — place a room
		var pad_x := rng.randi_range(1, maxi(1, (leaf.rect.size.x - MIN_ROOM) / 2))
		var pad_z := rng.randi_range(1, maxi(1, (leaf.rect.size.y - MIN_ROOM) / 2))
		var rx := leaf.rect.position.x + pad_x
		var rz := leaf.rect.position.y + pad_z
		var rw := leaf.rect.size.x - pad_x * 2
		var rh := leaf.rect.size.y - pad_z * 2
		rw = maxi(rw, MIN_ROOM)
		rh = maxi(rh, MIN_ROOM)

		var room := RoomData.new()
		room.id = id
		room.grid_rect = Rect2i(rx, rz, rw, rh)
		room.biome = _current_biome
		room.surface_profile = _make_room_surface_profile()
		room.doorway_candidates = _build_room_doorway_candidates(room)
		leaf.room = room
		rooms.append(room)
		_carve_rect(room.grid_rect, room.id)
		return id + 1
	else:
		if leaf.left:
			id = _carve_rooms(leaf.left, id)
		if leaf.right:
			id = _carve_rooms(leaf.right, id)
		return id

func _connect_leaves(leaf: _BSPLeaf) -> void:
	if leaf.left == null or leaf.right == null:
		return

	_connect_leaves(leaf.left)
	_connect_leaves(leaf.right)

	var a_room := _get_any_room(leaf.left)
	var b_room := _get_any_room(leaf.right)
	if a_room == null or b_room == null:
		return

	_try_connect_rooms(a_room, b_room)

func _get_any_room(leaf: _BSPLeaf) -> RoomData:
	if leaf == null:
		return null
	if leaf.room != null:
		return leaf.room
	var r := _get_any_room(leaf.left)
	if r:
		return r
	return _get_any_room(leaf.right)

func _add_loop_corridors() -> void:
	if rooms.size() < 3:
		return
	var loop_chance := 0.6  # 60% chance to connect nearby unconnected rooms
	var max_dist := 18.0    # maximum distance in tiles to consider "nearby"

	for i in range(rooms.size()):
		var room_a: RoomData = rooms[i]
		var c_a := room_a.get_center_tile()
		for j in range(i + 1, rooms.size()):
			var room_b: RoomData = rooms[j]
			if room_b.id in room_a.connected_to:
				continue
			var c_b := room_b.get_center_tile()
			var dist := Vector2(c_a).distance_to(Vector2(c_b))

			if dist <= max_dist and rng.randf() <= loop_chance:
				_try_connect_rooms(room_a, room_b)

func _enforce_min_room_degree(min_degree: int) -> void:
	if min_degree <= 0:
		return
	if rooms.size() < 3:
		return

	var max_iterations := maxi(16, rooms.size() * min_degree * 4)
	var iterations := 0
	while iterations < max_iterations:
		iterations += 1

		var target_room: RoomData = null
		var target_degree := 999999
		for room_variant in rooms:
			var room: RoomData = room_variant
			var deg := room.connected_to.size()
			if deg >= min_degree:
				continue
			if deg < target_degree:
				target_degree = deg
				target_room = room
		if target_room == null:
			return

		var candidate_rooms := _get_connection_candidates_for_room(target_room)
		if candidate_rooms.is_empty():
			# Can't increase this room's degree; stop trying to avoid churn.
			return

		var connected := false
		for cand_variant in candidate_rooms:
			var candidate: RoomData = cand_variant
			if candidate == null:
				continue
			if _try_connect_rooms(target_room, candidate):
				connected = true
				break
		if not connected:
			# No viable portal pair for this target in current state.
			return

func _get_connection_candidates_for_room(room: RoomData) -> Array:
	var scored: Array = []
	var room_center := room.get_center_tile()
	for other_variant in rooms:
		var other: RoomData = other_variant
		if other == room:
			continue
		if other.id in room.connected_to:
			continue
		var other_center := other.get_center_tile()
		var dist := Vector2(room_center).distance_to(Vector2(other_center))
		var degree_bias := float(other.connected_to.size()) * 0.75
		# Prefer nearby rooms and lower-degree peers to reduce linear chains.
		var score := dist + degree_bias
		scored.append({"room": other, "score": score})
	return _take_lowest_scored(scored, -1, "room")

func _try_connect_rooms(room_a: RoomData, room_b: RoomData) -> bool:
	_connect_attempts += 1
	if room_a == null or room_b == null:
		return false
	if room_b.id in room_a.connected_to:
		return false

	var portal_pairs := _pick_portal_pairs(room_a, room_b, 12)
	for portal_pair_variant in portal_pairs:
		var portal_pair: Dictionary = portal_pair_variant
		var a_portal: Dictionary = portal_pair.get("a", {})
		var b_portal: Dictionary = portal_pair.get("b", {})
		if a_portal.is_empty() or b_portal.is_empty():
			continue

		var corridor_id := _corridor_next_id
		a_portal["room_id"] = room_a.id
		a_portal["corridor_id"] = corridor_id
		b_portal["room_id"] = room_b.id
		b_portal["corridor_id"] = corridor_id

		var a_tile: Vector2i = a_portal["tile"]
		var b_tile: Vector2i = b_portal["tile"]
		var carve_result: Dictionary = _carve_corridor(a_tile.x, a_tile.y, b_tile.x, b_tile.y, corridor_id)
		var corridor_tiles: Array = carve_result.get("tiles", [])
		var previous_tiles: Dictionary = carve_result.get("previous", {})
		var previous_corridor_owner: Dictionary = carve_result.get("previous_corridor_owner", {})
		if not _corridor_respects_room_boundaries(corridor_tiles, room_a.id, room_b.id):
			_restore_tiles(previous_tiles)
			_restore_corridor_owner(previous_corridor_owner)
			continue

		# Validate both doorways after carve before mutating doorway state.
		if not _is_portal_registration_valid(a_portal):
			_restore_tiles(previous_tiles)
			_restore_corridor_owner(previous_corridor_owner)
			continue
		if not _is_portal_registration_valid(b_portal):
			_restore_tiles(previous_tiles)
			_restore_corridor_owner(previous_corridor_owner)
			continue

		_corridor_next_id += 1
		var doorway_a_id := _register_doorway(a_portal, room_a.id, corridor_id)
		var doorway_b_id := _register_doorway(b_portal, room_b.id, corridor_id)
		if doorway_a_id < 0 or doorway_b_id < 0:
			_restore_tiles(previous_tiles)
			_restore_corridor_owner(previous_corridor_owner)
			continue

		corridors.append({
			"id": corridor_id,
			"room_a_id": room_a.id,
			"room_b_id": room_b.id,
			"tiles": corridor_tiles,
			"width_tiles": CORRIDOR_HALF * 2 + 1,
			"doorway_a_id": doorway_a_id,
			"doorway_b_id": doorway_b_id,
		})
		room_a.corridor_ids.append(corridor_id)
		room_b.corridor_ids.append(corridor_id)
		room_a.doorway_ids.append(doorway_a_id)
		room_b.doorway_ids.append(doorway_b_id)
		room_a.connected_to.append(room_b.id)
		room_b.connected_to.append(room_a.id)
		_connect_successes += 1
		return true

	return false

func _corridor_respects_room_boundaries(corridor_tiles: Array, room_a_id: int, room_b_id: int) -> bool:
	for tile_variant in corridor_tiles:
		if typeof(tile_variant) != TYPE_VECTOR2I:
			continue
		var tile: Vector2i = tile_variant
		var owner_room_id := int(_room_tile_owner.get(_grid_key(tile.x, tile.y), OWNER_NONE))
		if owner_room_id == OWNER_NONE:
			continue
		if owner_room_id == room_a_id or owner_room_id == room_b_id:
			continue
		return false
	return true

func _validate_and_repair_layout() -> void:
	_layout_repair.validate_and_repair_layout()

func _pick_portal_pairs(room_a: RoomData, room_b: RoomData, max_pairs: int = 8) -> Array:
	if room_a == null or room_b == null:
		return []
	if room_a.doorway_candidates.is_empty():
		room_a.doorway_candidates = _build_room_doorway_candidates(room_a)
	if room_b.doorway_candidates.is_empty():
		room_b.doorway_candidates = _build_room_doorway_candidates(room_b)
	if room_a.doorway_candidates.is_empty() or room_b.doorway_candidates.is_empty():
		return []

	var center_a := room_a.get_center_tile()
	var center_b := room_b.get_center_tile()
	var scored_pairs: Array = []

	for a in room_a.doorway_candidates:
		if not _can_use_portal_candidate(a):
			continue
		var a_tile: Vector2i = a["tile"]
		var score_a := Vector2(a_tile).distance_to(Vector2(center_b))
		for b in room_b.doorway_candidates:
			if not _can_use_portal_candidate(b):
				continue
			var b_tile: Vector2i = b["tile"]
			var score_b := Vector2(b_tile).distance_to(Vector2(center_a))
			var pair_score := score_a + score_b + Vector2(a_tile).distance_to(Vector2(b_tile)) * 0.2
			scored_pairs.append({
				"a": a,
				"b": b,
				"score": pair_score,
			})

	var best_pairs: Array = []
	var limit := maxi(1, max_pairs)
	var top_pairs := _take_lowest_scored(scored_pairs, limit)
	for p in top_pairs:
		var pair_dict: Dictionary = p
		best_pairs.append({
			"a": pair_dict.get("a", {}),
			"b": pair_dict.get("b", {}),
		})
	return best_pairs

func _can_use_portal_candidate(candidate: Dictionary) -> bool:
	return _portal_validator.can_use_portal_candidate(candidate)

func _register_doorway(portal: Dictionary, room_id: int = -1, corridor_id: int = -1) -> int:
	return _portal_validator.register_doorway(portal, room_id, corridor_id)

func _build_opening_offsets(span_tiles: int) -> Array[int]:
	return _portal_validator.build_opening_offsets(span_tiles)

func _get_offsets_center(offsets: Array[int]) -> float:
	return _portal_validator.get_offsets_center(offsets)

func _make_room_surface_profile() -> Dictionary:
	return {
		"floor_variant": rng.randi_range(0, 2),
		"wall_variant": rng.randi_range(0, 2),
		"ceiling_variant": rng.randi_range(0, 2),
	}

func _has_required_side_walls(
	tile: Vector2i,
	orientation: String,
	opening_offsets: Array[int],
	portal: Dictionary,
	require_dual_passage: bool = true
) -> bool:
	return _portal_validator.has_required_side_walls(
		tile,
		orientation,
		opening_offsets,
		portal,
		require_dual_passage
	)

func _is_portal_registration_valid(portal: Dictionary) -> bool:
	return _portal_validator.is_portal_registration_valid(portal)

func _is_portal_valid(
	portal: Dictionary,
	require_threshold_wall: bool,
	check_spacing: bool,
	track_metrics: bool = false,
	require_dual_passage: bool = true
) -> bool:
	return _portal_validator.is_portal_valid(
		portal,
		require_threshold_wall,
		check_spacing,
		track_metrics,
		require_dual_passage
	)

func _prune_invalid_doorways() -> void:
	_layout_repair.prune_invalid_doorways()

func _prune_invalid_corridors() -> void:
	_layout_repair.prune_invalid_corridors()

func _rebuild_room_links_from_records() -> void:
	_layout_repair.rebuild_room_links_from_records()

func _repair_disconnected_room_graph() -> void:
	_layout_repair.repair_disconnected_room_graph()

func _collect_room_components(room_lookup: Dictionary) -> Array:
	return _graph_utils.collect_room_components(room_lookup)

func _pick_closest_component_room_pair(components: Array, room_lookup: Dictionary) -> Dictionary:
	return _graph_utils.pick_closest_component_room_pair(components, room_lookup)

func _doorway_opening_has_passage(doorway: Dictionary) -> bool:
	return _portal_validator.doorway_opening_has_passage(doorway)

func _ensure_start_exit_floor_path() -> void:
	var start_room: RoomData = null
	var exit_room: RoomData = null
	for room in rooms:
		if room.room_type == RoomData.RoomType.START:
			start_room = room
		elif room.room_type == RoomData.RoomType.EXIT:
			exit_room = room
	if start_room == null or exit_room == null:
		return

	var start := start_room.get_center_tile()
	var goal := exit_room.get_center_tile()
	if _is_floor_path_reachable(start, goal):
		return
	_force_carve_corridor(start, goal)


func _is_floor_path_reachable(start: Vector2i, goal: Vector2i) -> bool:
	return _graph_utils.is_floor_path_reachable(start, goal)

func _force_carve_corridor(start: Vector2i, goal: Vector2i) -> void:
	var x := start.x
	while x != goal.x:
		for dz in range(-CORRIDOR_HALF, CORRIDOR_HALF + 1):
			_set_floor_force(x, start.y + dz)
		x += sign(goal.x - x)
	for dz in range(-CORRIDOR_HALF, CORRIDOR_HALF + 1):
		_set_floor_force(goal.x, start.y + dz)

	var z := start.y
	while z != goal.y:
		for dx in range(-CORRIDOR_HALF, CORRIDOR_HALF + 1):
			_set_floor_force(goal.x + dx, z)
		z += sign(goal.y - z)
	for dx in range(-CORRIDOR_HALF, CORRIDOR_HALF + 1):
		_set_floor_force(goal.x + dx, goal.y)

func _can_form_threshold_wall(tile: Vector2i, orientation: String, opening_offsets: Array[int]) -> bool:
	return _portal_validator.can_form_threshold_wall(tile, orientation, opening_offsets)

func _enforce_threshold_wall(tile: Vector2i, orientation: String, opening_offsets: Array[int]) -> Array:
	return _portal_validator.enforce_threshold_wall(tile, orientation, opening_offsets)

func _scan_to_wall_x(start_x: int, z: int, dir: int) -> int:
	return _portal_validator.scan_to_wall_x(start_x, z, dir)

func _scan_to_wall_z(x: int, start_z: int, dir: int) -> int:
	return _portal_validator.scan_to_wall_z(x, start_z, dir)

func _grid_key(x: int, z: int) -> String:
	return "%d:%d" % [x, z]

func _restore_tiles(previous_tiles: Dictionary) -> void:
	_carving.restore_tiles(previous_tiles)

func _restore_corridor_owner(previous_corridor_owner: Dictionary) -> void:
	_carving.restore_corridor_owner(previous_corridor_owner)

func _rebuild_corridor_tile_owner_map() -> void:
	_carving.rebuild_corridor_tile_owner_map()

func _tile_has_room_owner(tile: Vector2i, room_id: int) -> bool:
	return _portal_validator.tile_has_room_owner(tile, room_id)

func _tile_has_corridor_owner(tile: Vector2i, corridor_id: int) -> bool:
	return _portal_validator.tile_has_corridor_owner(tile, corridor_id)

func _is_room_corridor_boundary(side_a: Vector2i, side_b: Vector2i, room_id: int, corridor_id: int) -> bool:
	return _portal_validator.is_room_corridor_boundary(side_a, side_b, room_id, corridor_id)


func _is_doorway_too_close_same_wall(tile: Vector2i, orientation: String, wall_line_key: String) -> bool:
	return _portal_validator.is_doorway_too_close_same_wall(tile, orientation, wall_line_key)

func _build_room_doorway_candidates(room: RoomData) -> Array:
	return _portal_validator.build_room_doorway_candidates(room)

func _offsets_fit_line(anchor: int, min_offset: int, max_offset: int, min_line: int, max_line: int) -> bool:
	return _portal_validator.offsets_fit_line(anchor, min_offset, max_offset, min_line, max_line)

func _make_wall_line_key(tile: Vector2i, orientation: String) -> String:
	return _portal_validator.make_wall_line_key(tile, orientation)

# -------------------------------------------------------
# Room role assignment
# -------------------------------------------------------
func _assign_start_and_exit() -> void:
	if rooms.is_empty():
		return

	for room in rooms:
		room.room_type = RoomData.RoomType.NORMAL

	if rooms.size() == 1:
		rooms[0].room_type = RoomData.RoomType.START
		return

	var room_lookup := _build_room_lookup()

	# Pick a random anchor, then find a farthest-pair (graph diameter approximation).
	var anchor_room: RoomData = rooms[rng.randi() % rooms.size()]
	var start_id := _get_farthest_room_id(anchor_room.id, room_lookup)
	var exit_id := _get_farthest_room_id(start_id, room_lookup)

	var start_room: RoomData = room_lookup.get(start_id, null)
	var exit_room: RoomData = room_lookup.get(exit_id, null)
	if start_room == null:
		start_room = rooms[0]
	if exit_room == null:
		exit_room = rooms[rooms.size() - 1]
	if exit_room == start_room and rooms.size() > 1:
		exit_room = rooms[1]

	start_room.room_type = RoomData.RoomType.START
	exit_room.room_type = RoomData.RoomType.EXIT

func _build_room_lookup() -> Dictionary:
	var lookup := {}
	for room in rooms:
		lookup[room.id] = room
	return lookup

func _get_farthest_room_id(from_id: int, room_lookup: Dictionary) -> int:
	return _graph_utils.get_farthest_room_id(from_id, room_lookup)

func _take_lowest_scored(scored: Array, limit: int = -1, value_key: String = "") -> Array:
	var out: Array = []
	var max_items: int = scored.size() if limit < 0 else mini(limit, scored.size())
	while out.size() < max_items and not scored.is_empty():
		var min_idx: int = 0
		var min_score: float = float(scored[0].get("score", INF))
		for i in range(1, scored.size()):
			var s: float = float(scored[i].get("score", INF))
			if s < min_score:
				min_score = s
				min_idx = i
		var picked: Dictionary = scored[min_idx]
		if value_key.is_empty():
			out.append(picked)
		else:
			out.append(picked.get(value_key, null))
		scored.remove_at(min_idx)
	return out

func _reset_debug_metrics() -> void:
	_connect_attempts = 0
	_connect_successes = 0
	_doorway_register_attempts = 0
	_doorway_register_successes = 0
	_portal_reject_counts = {}

func _track_portal_reject(reason: String, enabled: bool) -> void:
	if not enabled:
		return
	var current := int(_portal_reject_counts.get(reason, 0))
	_portal_reject_counts[reason] = current + 1

func _log_generation_metrics() -> void:
	if not debug_generation_metrics_enabled:
		return
	var reject_parts: Array[String] = []
	for k_variant in _portal_reject_counts.keys():
		var k := str(k_variant)
		reject_parts.append("%s=%d" % [k, int(_portal_reject_counts[k_variant])])
	reject_parts.sort()
	var reject_summary := ", ".join(reject_parts)
	if reject_summary.is_empty():
		reject_summary = "none"
	print(
		"DungeonGenerator metrics: rooms=%d corridors=%d doorways=%d connect=%d/%d doorway_reg=%d/%d rejects=[%s]" % [
			rooms.size(),
			corridors.size(),
			doorways.size(),
			_connect_successes,
			_connect_attempts,
			_doorway_register_successes,
			_doorway_register_attempts,
			reject_summary,
		]
	)
