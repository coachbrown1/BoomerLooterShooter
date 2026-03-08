extends RefCounted
class_name DungeonCarving

var _gen

func _init(generator) -> void:
	_gen = generator

func carve_corridor(ax: int, az: int, bx: int, bz: int, corridor_id: int = -1) -> Dictionary:
	var carved_tiles: Dictionary = {}
	var carved_order: Array = []
	var previous_tiles: Dictionary = {}
	var previous_corridor_owner: Dictionary = {}

	var x: int = ax
	while x != bx:
		for dz in range(-_gen.CORRIDOR_HALF, _gen.CORRIDOR_HALF + 1):
			var key_before: String = _gen._grid_key(x, az + dz)
			if not previous_tiles.has(key_before) and x >= 0 and x < _gen.GRID_W and az + dz >= 0 and az + dz < _gen.GRID_H:
				previous_tiles[key_before] = _gen.tile_grid[x][az + dz]
				previous_corridor_owner[key_before] = int(_gen._corridor_tile_owner.get(key_before, _gen.OWNER_NONE))
			_gen._set_floor(x, az + dz)
			if corridor_id >= 0 and x >= 0 and x < _gen.GRID_W and az + dz >= 0 and az + dz < _gen.GRID_H:
				_gen._corridor_tile_owner[key_before] = corridor_id
			var tile: Vector2i = Vector2i(x, az + dz)
			var key: String = _gen._grid_key(tile.x, tile.y)
			if not carved_tiles.has(key):
				carved_tiles[key] = true
				carved_order.append(tile)
		x += sign(bx - ax)

	var z: int = az
	while z != bz + sign(bz - az):
		for dx in range(-_gen.CORRIDOR_HALF, _gen.CORRIDOR_HALF + 1):
			var key_before: String = _gen._grid_key(bx + dx, z)
			if not previous_tiles.has(key_before) and bx + dx >= 0 and bx + dx < _gen.GRID_W and z >= 0 and z < _gen.GRID_H:
				previous_tiles[key_before] = _gen.tile_grid[bx + dx][z]
				previous_corridor_owner[key_before] = int(_gen._corridor_tile_owner.get(key_before, _gen.OWNER_NONE))
			_gen._set_floor(bx + dx, z)
			if corridor_id >= 0 and bx + dx >= 0 and bx + dx < _gen.GRID_W and z >= 0 and z < _gen.GRID_H:
				_gen._corridor_tile_owner[key_before] = corridor_id
			var tile: Vector2i = Vector2i(bx + dx, z)
			var key: String = _gen._grid_key(tile.x, tile.y)
			if not carved_tiles.has(key):
				carved_tiles[key] = true
				carved_order.append(tile)
		z += sign(bz - az)

	return {
		"tiles": carved_order,
		"previous": previous_tiles,
		"previous_corridor_owner": previous_corridor_owner,
	}

func restore_tiles(previous_tiles: Dictionary) -> void:
	for key_variant in previous_tiles.keys():
		var key: String = str(key_variant)
		var parts: PackedStringArray = key.split(":")
		if parts.size() != 2:
			continue
		var x: int = int(parts[0])
		var z: int = int(parts[1])
		if x < 0 or x >= _gen.GRID_W or z < 0 or z >= _gen.GRID_H:
			continue
		_gen.tile_grid[x][z] = int(previous_tiles[key_variant])

func restore_corridor_owner(previous_corridor_owner: Dictionary) -> void:
	for key_variant in previous_corridor_owner.keys():
		var key: String = str(key_variant)
		var prev_id: int = int(previous_corridor_owner[key_variant])
		if prev_id < 0:
			_gen._corridor_tile_owner.erase(key)
		else:
			_gen._corridor_tile_owner[key] = prev_id

func rebuild_corridor_tile_owner_map() -> void:
	_gen._corridor_tile_owner = {}
	for corridor_variant in _gen.corridors:
		if typeof(corridor_variant) != TYPE_DICTIONARY:
			continue
		var corridor: Dictionary = corridor_variant
		var corridor_id: int = int(corridor.get("id", _gen.OWNER_NONE))
		if corridor_id < 0:
			continue
		var tiles: Array = corridor.get("tiles", [])
		for tile_variant in tiles:
			if typeof(tile_variant) != TYPE_VECTOR2I:
				continue
			var tile: Vector2i = tile_variant
			if tile.x < 0 or tile.x >= _gen.GRID_W or tile.y < 0 or tile.y >= _gen.GRID_H:
				continue
			if _gen.tile_grid[tile.x][tile.y] != _gen.TILE_FLOOR:
				continue
			_gen._corridor_tile_owner[_gen._grid_key(tile.x, tile.y)] = corridor_id
