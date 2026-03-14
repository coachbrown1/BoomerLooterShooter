extends RefCounted
class_name DungeonGraphUtils

var _gen

func _init(generator) -> void:
	_gen = generator

func is_floor_path_reachable(start: Vector2i, goal: Vector2i) -> bool:
	if start == goal:
		return true
	if start.x < 0 or start.x >= _gen.GRID_W or start.y < 0 or start.y >= _gen.GRID_H:
		return false
	if goal.x < 0 or goal.x >= _gen.GRID_W or goal.y < 0 or goal.y >= _gen.GRID_H:
		return false
	if _gen.tile_grid[start.x][start.y] != _gen.TILE_FLOOR or _gen.tile_grid[goal.x][goal.y] != _gen.TILE_FLOOR:
		return false

	var visited: Dictionary = {}
	var q: Array[Vector2i] = [start]
	visited[_gen._grid_key(start.x, start.y)] = true
	var idx: int = 0
	var dirs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	while idx < q.size():
		var cur: Vector2i = q[idx]
		idx += 1
		if cur == goal:
			return true
		for d: Vector2i in dirs:
			var nxt: Vector2i = cur + d
			if nxt.x < 0 or nxt.x >= _gen.GRID_W or nxt.y < 0 or nxt.y >= _gen.GRID_H:
				continue
			if _gen.tile_grid[nxt.x][nxt.y] != _gen.TILE_FLOOR:
				continue
			var key: String = _gen._grid_key(nxt.x, nxt.y)
			if visited.has(key):
				continue
			visited[key] = true
			q.append(nxt)
	return false

func get_farthest_room_id(from_id: int, room_lookup: Dictionary) -> int:
	if not room_lookup.has(from_id):
		return from_id

	var visited: Dictionary = {}
	var distance: Dictionary = {}
	var queue: Array[int] = [from_id]
	var q_idx: int = 0

	visited[from_id] = true
	distance[from_id] = 0

	var farthest_id: int = from_id
	var farthest_dist: int = 0

	while q_idx < queue.size():
		var current_id: int = queue[q_idx]
		q_idx += 1

		var current_dist: int = int(distance[current_id])
		if current_dist > farthest_dist:
			farthest_dist = current_dist
			farthest_id = current_id

		var room: RoomData = room_lookup.get(current_id, null)
		if room == null:
			continue

		for next_id_variant in room.connected_to:
			var next_id: int = int(next_id_variant)
			if visited.has(next_id):
				continue
			visited[next_id] = true
			distance[next_id] = current_dist + 1
			queue.append(next_id)

	return farthest_id

func collect_room_components(room_lookup: Dictionary) -> Array:
	var comps: Array = []
	var visited: Dictionary = {}
	for room in _gen.rooms:
		if visited.has(room.id):
			continue
		var comp: Array = []
		var queue: Array[int] = [room.id]
		visited[room.id] = true
		var q: int = 0
		while q < queue.size():
			var rid: int = queue[q]
			q += 1
			comp.append(rid)
			var r: RoomData = room_lookup.get(rid, null)
			if r == null:
				continue
			for nid_variant in r.connected_to:
				var nid: int = int(nid_variant)
				if visited.has(nid):
					continue
				visited[nid] = true
				queue.append(nid)
		comps.append(comp)
	return comps

func pick_closest_component_room_pair(components: Array, room_lookup: Dictionary) -> Dictionary:
	if components.size() < 2:
		return {}
	var best: Dictionary = {}
	var best_dist_sq: float = INF
	for i in range(components.size()):
		for j in range(i + 1, components.size()):
			var comp_a: Array = components[i]
			var comp_b: Array = components[j]
			for aid_variant in comp_a:
				var a_id: int = int(aid_variant)
				var room_a: RoomData = room_lookup.get(a_id, null)
				if room_a == null:
					continue
				var a_center: Vector2i = room_a.get_center_tile()
				for bid_variant in comp_b:
					var b_id: int = int(bid_variant)
					var room_b: RoomData = room_lookup.get(b_id, null)
					if room_b == null:
						continue
					var b_center: Vector2i = room_b.get_center_tile()
					var d_sq: float = Vector2(a_center).distance_squared_to(Vector2(b_center))
					if d_sq < best_dist_sq:
						best_dist_sq = d_sq
						best = {"a": room_a, "b": room_b}
	return best
