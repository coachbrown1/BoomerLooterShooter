extends RefCounted
class_name DungeonBuilder

# World scale
const TILE_SIZE: float = 3.0		# meters per tile
const WALL_HEIGHT: float = 4.0
const DOOR_WIDTH: float = 2.7
const DOOR_HEIGHT: float = 3.6
const DOOR_THICKNESS: float = 0.2

# Tile types (must match DungeonGenerator)
const TILE_WALL: int = 0
const TILE_FLOOR: int = 1

# -------------------------------------------------------
# Default biome texture paths (fallback when biome data table is missing)
# -------------------------------------------------------
const DEFAULT_BIOME_TEXTURES := {
	"crypt": {
		"floor":   ["res://Assets/Environment/Crypt/crypt_floor_v1.png", "res://Assets/Environment/Crypt/crypt_floor_v2.png", "res://Assets/Environment/Crypt/crypt_floor_v3.png"],
		"wall":    ["res://Assets/Environment/Crypt/crypt_wall_v1.png", "res://Assets/Environment/Crypt/crypt_wall_v2.png", "res://Assets/Environment/Crypt/crypt_wall_v3.png"],
		"ceiling": ["res://Assets/Environment/Crypt/crypt_ceiling_v1.png", "res://Assets/Environment/Crypt/crypt_ceiling_v2.png", "res://Assets/Environment/Crypt/crypt_ceiling_v3.png"],
	},
	"fungal": {
		"floor":   ["res://Assets/Environment/Fungal/fungal_floor_v1.png", "res://Assets/Environment/Fungal/fungal_floor_v2.png", "res://Assets/Environment/Fungal/fungal_floor_v3.png"],
		"wall":    ["res://Assets/Environment/Fungal/fungal_wall_v1.png", "res://Assets/Environment/Fungal/fungal_wall_v2.png", "res://Assets/Environment/Fungal/fungal_wall_v3.png"],
		"ceiling": ["res://Assets/Environment/Fungal/fungal_ceiling_v1.png", "res://Assets/Environment/Fungal/fungal_ceiling_v2.png", "res://Assets/Environment/Fungal/fungal_ceiling_v3.png"],
	},
	"lava": {
		"floor":   ["res://Assets/Environment/Lava/lava_floor_v1.png", "res://Assets/Environment/Lava/lava_floor_v2.png", "res://Assets/Environment/Lava/lava_floor_v3.png"],
		"wall":    ["res://Assets/Environment/Lava/lava_wall_v1.png", "res://Assets/Environment/Lava/lava_wall_v2.png", "res://Assets/Environment/Lava/lava_wall_v3.png"],
		"ceiling": ["res://Assets/Environment/Lava/lava_ceiling_v1.png", "res://Assets/Environment/Lava/lava_ceiling_v2.png", "res://Assets/Environment/Lava/lava_ceiling_v3.png"],
	},
}

# Cached materials per biome
var _mat_cache := {}

# -------------------------------------------------------
# Main build entry
# -------------------------------------------------------
func build(
	tile_grid: Array,
	rooms: Array,
	corridors: Array,
	doorways: Array,
	parent: Node3D,
	biome_data: Resource = null
) -> void:
	var grid_w: int = tile_grid.size()
	var grid_h: int = tile_grid[0].size() if grid_w > 0 else 0

	# Determine dominant biome from rooms
	var biome := "crypt"
	if rooms.size() > 0:
		biome = rooms[0].biome

	var mats_floor   := _get_materials(biome, "floor", biome_data)
	var mats_wall    := _get_materials(biome, "wall", biome_data)
	var mats_ceiling := _get_materials(biome, "ceiling", biome_data)
	var room_tile_owner := _build_room_tile_owner(rooms)
	var corridor_tile_owner := _build_corridor_tile_owner(corridors)
	var doorway_opening_owner := _build_doorway_opening_owner(doorways)
	var fungal_corridor_profile := _make_fungal_corridor_profile(
		mats_floor.size(),
		mats_wall.size(),
		mats_ceiling.size()
	)

	# Container for all static geometry
	var geo_root := StaticBody3D.new()
	geo_root.name = "DungeonGeometry"
	parent.add_child(geo_root)

	var floor_mesh_inst := MeshInstance3D.new()
	var wall_mesh_inst  := MeshInstance3D.new()
	var ceil_mesh_inst  := MeshInstance3D.new()

	floor_mesh_inst.name = "Floors"
	wall_mesh_inst.name  = "Walls"
	ceil_mesh_inst.name  = "Ceilings"

	geo_root.add_child(floor_mesh_inst)
	geo_root.add_child(wall_mesh_inst)
	geo_root.add_child(ceil_mesh_inst)

	# Build surface arrays (one SurfaceTool per material variant)
	var floor_sts := []
	for m in mats_floor:
		var st = SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.set_material(m)
		floor_sts.append(st)
		
	var wall_sts := []
	for m in mats_wall:
		var st = SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.set_material(m)
		wall_sts.append(st)
		
	var ceil_sts := []
	for m in mats_ceiling:
		var st = SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.set_material(m)
		ceil_sts.append(st)

	for x in range(grid_w):
		for z in range(grid_h):
			if tile_grid[x][z] != TILE_FLOOR:
				continue

			var wx := x * TILE_SIZE
			var wz := z * TILE_SIZE

			var rand_val = randi()
			var floor_idx = rand_val % floor_sts.size()
			var ceil_idx = (rand_val >> 2) % ceil_sts.size()
			var room: RoomData = room_tile_owner.get(_tile_key(x, z), null)
			var corridor: Dictionary = corridor_tile_owner.get(_tile_key(x, z), {})
			var is_doorway_opening := doorway_opening_owner.has(_tile_key(x, z))
			var wall_idx = randi() % wall_sts.size()

			# Fungal uses semantic ownership: room profile, corridor profile, doorway opening profile.
			if biome == "fungal":
				if is_doorway_opening:
					floor_idx = fungal_corridor_profile["floor_variant"]
					ceil_idx = fungal_corridor_profile["ceiling_variant"]
					wall_idx = fungal_corridor_profile["wall_variant"]
				elif room != null:
					floor_idx = _get_room_surface_variant(room, "floor_variant", floor_sts.size(), floor_idx)
					ceil_idx = _get_room_surface_variant(room, "ceiling_variant", ceil_sts.size(), ceil_idx)
					wall_idx = _get_room_surface_variant(room, "wall_variant", wall_sts.size(), wall_idx)
				elif typeof(corridor) == TYPE_DICTIONARY and not corridor.is_empty():
					floor_idx = fungal_corridor_profile["floor_variant"]
					ceil_idx = fungal_corridor_profile["ceiling_variant"]
					wall_idx = fungal_corridor_profile["wall_variant"]

			# Floor quad
			_add_floor_quad(floor_sts[floor_idx], wx, wz, TILE_SIZE)

			# Ceiling quad
			_add_ceil_quad(ceil_sts[ceil_idx], wx, wz, TILE_SIZE, WALL_HEIGHT)

			# Walls — pick random per wall quad
			if x == 0               or tile_grid[x - 1][z] == TILE_WALL:
				_add_wall_quad(wall_sts[wall_idx], wx, wz, TILE_SIZE, WALL_HEIGHT, Vector3(-1, 0, 0))
			if x == grid_w - 1      or tile_grid[x + 1][z] == TILE_WALL:
				_add_wall_quad(wall_sts[wall_idx], wx, wz, TILE_SIZE, WALL_HEIGHT, Vector3(1, 0, 0))
			if z == 0               or tile_grid[x][z - 1] == TILE_WALL:
				_add_wall_quad(wall_sts[wall_idx], wx, wz, TILE_SIZE, WALL_HEIGHT, Vector3(0, 0, -1))
			if z == grid_h - 1      or tile_grid[x][z + 1] == TILE_WALL:
				_add_wall_quad(wall_sts[wall_idx], wx, wz, TILE_SIZE, WALL_HEIGHT, Vector3(0, 0, 1))

	var floor_mesh = ArrayMesh.new()
	for st in floor_sts:
		st.generate_normals()
		st.commit(floor_mesh)
	floor_mesh_inst.mesh = floor_mesh

	var wall_mesh = ArrayMesh.new()
	for st in wall_sts:
		st.generate_normals()
		st.commit(wall_mesh)
	wall_mesh_inst.mesh = wall_mesh

	var ceil_mesh = ArrayMesh.new()
	for st in ceil_sts:
		st.generate_normals()
		st.commit(ceil_mesh)
	ceil_mesh_inst.mesh = ceil_mesh

	# Single trimesh collision for the whole geometry
	var collision := CollisionShape3D.new()
	var merged := MeshInstance3D.new()
	merged.mesh = floor_mesh_inst.mesh  # floor is the walkable surface
	var shape := merged.mesh.create_trimesh_shape()
	collision.shape = shape
	geo_root.add_child(collision)

	# Separate collision for walls
	var wall_col := CollisionShape3D.new()
	wall_col.shape = wall_mesh_inst.mesh.create_trimesh_shape()
	geo_root.add_child(wall_col)

	# Post-processing: Place doorways and lights
	_place_generated_doorway_assemblies(geo_root, doorways, biome_data)
	_place_lights(geo_root, rooms, tile_grid, biome, doorway_opening_owner, biome_data)

# -------------------------------------------------------
# Quad helpers
# -------------------------------------------------------
func _add_floor_quad(st: SurfaceTool, wx: float, wz: float, size: float) -> void:
	# Vertices: counter-clockwise from above
	var v0 := Vector3(wx,        0.0, wz)
	var v1 := Vector3(wx + size, 0.0, wz)
	var v2 := Vector3(wx + size, 0.0, wz + size)
	var v3 := Vector3(wx,        0.0, wz + size)
	var n   := Vector3.UP

	st.set_normal(n); st.set_uv(Vector2(0, 0)); st.add_vertex(v0)
	st.set_normal(n); st.set_uv(Vector2(1, 0)); st.add_vertex(v1)
	st.set_normal(n); st.set_uv(Vector2(1, 1)); st.add_vertex(v2)

	st.set_normal(n); st.set_uv(Vector2(0, 0)); st.add_vertex(v0)
	st.set_normal(n); st.set_uv(Vector2(1, 1)); st.add_vertex(v2)
	st.set_normal(n); st.set_uv(Vector2(0, 1)); st.add_vertex(v3)

func _add_ceil_quad(st: SurfaceTool, wx: float, wz: float, size: float, height: float) -> void:
	var y   := height
	var v0  := Vector3(wx,        y, wz)
	var v1  := Vector3(wx,        y, wz + size)
	var v2  := Vector3(wx + size, y, wz + size)
	var v3  := Vector3(wx + size, y, wz)
	var n   := Vector3.DOWN

	st.set_normal(n); st.set_uv(Vector2(0, 0)); st.add_vertex(v0)
	st.set_normal(n); st.set_uv(Vector2(0, 1)); st.add_vertex(v1)
	st.set_normal(n); st.set_uv(Vector2(1, 1)); st.add_vertex(v2)

	st.set_normal(n); st.set_uv(Vector2(0, 0)); st.add_vertex(v0)
	st.set_normal(n); st.set_uv(Vector2(1, 1)); st.add_vertex(v2)
	st.set_normal(n); st.set_uv(Vector2(1, 0)); st.add_vertex(v3)

func _add_wall_quad(
		st: SurfaceTool, wx: float, wz: float,
		size: float, height: float, normal: Vector3
) -> void:
	# Build a quad on the face indicated by `normal`
	var v0: Vector3
	var v1: Vector3
	var v2: Vector3
	var v3: Vector3

	if normal == Vector3(-1, 0, 0):   # West face
		v0 = Vector3(wx, 0,      wz)
		v1 = Vector3(wx, 0,      wz + size)
		v2 = Vector3(wx, height, wz + size)
		v3 = Vector3(wx, height, wz)
	elif normal == Vector3(1, 0, 0):  # East face
		v0 = Vector3(wx + size, 0,      wz + size)
		v1 = Vector3(wx + size, 0,      wz)
		v2 = Vector3(wx + size, height, wz)
		v3 = Vector3(wx + size, height, wz + size)
	elif normal == Vector3(0, 0, -1): # North face
		v0 = Vector3(wx + size, 0,      wz)
		v1 = Vector3(wx,        0,      wz)
		v2 = Vector3(wx,        height, wz)
		v3 = Vector3(wx + size, height, wz)
	else:                              # South face
		v0 = Vector3(wx,        0,      wz + size)
		v1 = Vector3(wx + size, 0,      wz + size)
		v2 = Vector3(wx + size, height, wz + size)
		v3 = Vector3(wx,        height, wz + size)

	st.set_normal(normal); st.set_uv(Vector2(0, 1)); st.add_vertex(v0)
	st.set_normal(normal); st.set_uv(Vector2(1, 1)); st.add_vertex(v1)
	st.set_normal(normal); st.set_uv(Vector2(1, 0)); st.add_vertex(v2)

	st.set_normal(normal); st.set_uv(Vector2(0, 1)); st.add_vertex(v0)
	st.set_normal(normal); st.set_uv(Vector2(1, 0)); st.add_vertex(v2)
	st.set_normal(normal); st.set_uv(Vector2(0, 0)); st.add_vertex(v3)

# -------------------------------------------------------
# Material cache
# -------------------------------------------------------
func _get_materials(biome: String, surface: String, biome_data: Resource = null) -> Array:
	var tex_paths: Array = _get_surface_texture_paths(biome, surface, biome_data)
	var key := biome + "_" + surface + "_" + "|".join(tex_paths)
	if _mat_cache.has(key):
		return _mat_cache[key]

	var mats = []
	for tex_path in tex_paths:
		var mat := StandardMaterial3D.new()
		if tex_path != "":
			var tex = load(tex_path)
			if tex:
				mat.albedo_texture = tex
				
				# Enable emission to make the brightest parts of the tiles 'pop'
				mat.emission_enabled = true
				mat.emission_texture = tex
				mat.emission_operator = StandardMaterial3D.EMISSION_OP_MULTIPLY
				
				var emission_energy := 0.1
				if biome == "fungal":
					emission_energy = 0.2
					mat.emission = Color(0.3, 0.6, 0.4) # Even subtler green
					mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
					mat.uv1_scale = Vector3(1.0, 1.0, 1.0)
				elif biome == "lava":
					emission_energy = 0.4
					mat.emission = Color(0.8, 0.15, 0.0)
					mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
					mat.uv1_scale = Vector3(2.0, 2.0, 2.0)
				elif biome == "crypt":
					emission_energy = 0.08
					mat.emission = Color(0.15, 0.25, 0.5)
					mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
					mat.uv1_scale = Vector3(2.0, 2.0, 2.0)
				else:
					mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
					mat.uv1_scale = Vector3(2.0, 2.0, 2.0)
				
				mat.emission_energy_multiplier = emission_energy
		mats.append(mat)

	if mats.is_empty():
		mats.append(StandardMaterial3D.new())

	_mat_cache[key] = mats
	return mats

func _get_surface_texture_paths(biome: String, surface: String, biome_data: Resource = null) -> Array:
	if _has_biome_data(biome_data):
		match surface:
			"floor":
				if biome_data.floor_textures.size() > 0:
					return biome_data.floor_textures
			"wall":
				if biome_data.wall_textures.size() > 0:
					return biome_data.wall_textures
			"ceiling":
				if biome_data.ceiling_textures.size() > 0:
					return biome_data.ceiling_textures
	var paths: Dictionary = DEFAULT_BIOME_TEXTURES.get(biome, DEFAULT_BIOME_TEXTURES["crypt"])
	return paths.get(surface, [])

func _build_room_tile_owner(rooms: Array) -> Dictionary:
	var owner := {}
	for room in rooms:
		if room == null:
			continue
		var rect: Rect2i = room.grid_rect
		for x in range(rect.position.x, rect.position.x + rect.size.x):
			for z in range(rect.position.y, rect.position.y + rect.size.y):
				owner[_tile_key(x, z)] = room
	return owner

func _build_corridor_tile_owner(corridors: Array) -> Dictionary:
	var owner := {}
	for corridor_variant in corridors:
		if typeof(corridor_variant) != TYPE_DICTIONARY:
			continue
		var tiles: Array = corridor_variant.get("tiles", [])
		for tile_variant in tiles:
			if typeof(tile_variant) != TYPE_VECTOR2I:
				continue
			var tile: Vector2i = tile_variant
			owner[_tile_key(tile.x, tile.y)] = corridor_variant
	return owner

func _build_doorway_opening_owner(doorways: Array) -> Dictionary:
	var owner := {}
	for doorway_variant in doorways:
		if typeof(doorway_variant) != TYPE_DICTIONARY:
			continue
		var opening_tiles: Array = doorway_variant.get("opening_tiles", [])
		for tile_variant in opening_tiles:
			if typeof(tile_variant) != TYPE_VECTOR2I:
				continue
			var tile: Vector2i = tile_variant
			owner[_tile_key(tile.x, tile.y)] = true
	return owner

func _tile_key(x: int, z: int) -> String:
	return "%d:%d" % [x, z]

func _get_room_surface_variant(room: RoomData, key: String, variant_count: int, fallback: int) -> int:
	if variant_count <= 0:
		return 0
	if room == null:
		return fallback % variant_count

	var profile: Variant = room.surface_profile
	if typeof(profile) != TYPE_DICTIONARY:
		return fallback % variant_count

	var raw := int(profile.get(key, fallback))
	if raw < 0:
		return fallback % variant_count
	return raw % variant_count

func _make_fungal_corridor_profile(floor_count: int, wall_count: int, ceiling_count: int) -> Dictionary:
	var floor_variant := randi() % maxi(1, floor_count)
	var wall_variant := randi() % maxi(1, wall_count)
	var ceiling_variant := randi() % maxi(1, ceiling_count)
	return {
		"floor_variant": floor_variant,
		"wall_variant": wall_variant,
		"ceiling_variant": ceiling_variant,
	}

# -------------------------------------------------------
# Decorators: Doors and Lights
# -------------------------------------------------------
func _place_lights(
	parent: Node3D,
	rooms: Array,
	tile_grid: Array,
	biome: String,
	doorway_owner: Dictionary,
	biome_data: Resource = null
) -> void:
	var room_color: Color = Color(0.9, 0.75, 0.5)
	var room_cookie_path := "res://Assets/Effects/cookie_grate.png"
	var use_bioluminescent_props := biome == "fungal"
	var corridor_color := Color(1.0, 0.6, 0.2) if biome == "crypt" else Color(1.0, 0.35, 0.1)
	var corridor_energy := 0.5
	var corridor_range := 6.0
	var corridor_height_ratio := 0.6
	var corridor_step := 4
	var corridor_chance := 0.3
	var bioluminescent_sources: Array = []

	if _has_biome_data(biome_data):
		room_color = biome_data.room_light_color
		room_cookie_path = biome_data.room_light_cookie_texture
		use_bioluminescent_props = biome_data.use_bioluminescent_props_for_room_lights
		corridor_color = biome_data.corridor_light_color
		corridor_energy = biome_data.corridor_light_energy
		corridor_range = biome_data.corridor_light_range
		corridor_height_ratio = biome_data.corridor_light_height
		corridor_step = maxi(1, biome_data.corridor_light_step)
		corridor_chance = clampf(biome_data.corridor_light_chance, 0.0, 1.0)
		bioluminescent_sources = biome_data.bioluminescent_light_sources.duplicate()
	if bioluminescent_sources.is_empty():
		bioluminescent_sources = [
			{
				"tex": "res://Assets/Environment/Fungal/prop_fungal_crystal.png",
				"color": Color(0.4, 0.3, 0.9),
				"energy": 0.9,
				"range": 7.0,
				"height": 0.8,
				"pixel_size": 0.004,
				"requires_wall": true,
			},
			{
				"tex": "res://Assets/Environment/Fungal/prop_fungal_mushroom.png",
				"color": Color(0.2, 1.0, 0.5),
				"energy": 0.6,
				"range": 5.0,
				"height": 0.9,
				"pixel_size": 0.0035,
				"requires_wall": false,
			},
		]
		
	# Room center lights
	for r in rooms:
		var pos = r.get_world_center(TILE_SIZE)

		if use_bioluminescent_props:
			# Try to place a wall crystal, otherwise use a center mushroom
			var rect: Rect2i = r.grid_rect
			var candidates := []
			for x in range(rect.position.x, rect.position.x + rect.size.x):
				for z in [rect.position.y, rect.position.y + rect.size.y - 1]:
					var key := _tile_key(x, z)
					if doorway_owner.has(key): continue
					if x > rect.position.x and x < rect.position.x + rect.size.x - 1:
						candidates.append({"x": x, "z": z, "side": 2 if z == rect.position.y else 3})
			for z in range(rect.position.y, rect.position.y + rect.size.y):
				for x in [rect.position.x, rect.position.x + rect.size.x - 1]:
					var key := _tile_key(x, z)
					if doorway_owner.has(key): continue
					if z > rect.position.y and z < rect.position.y + rect.size.y - 1:
						candidates.append({"x": x, "z": z, "side": 0 if x == rect.position.x else 1})
			
			var wx: float
			var wz: float
			var ry: float = 0.0
			var use_crystal := not candidates.is_empty()
			if not use_crystal:
				wx = pos.x
				wz = pos.z
			else:
				var c = candidates[randi() % candidates.size()]
				match c.side:
					0: # West
						wx = c.x * TILE_SIZE + 0.05
						wz = c.z * TILE_SIZE + TILE_SIZE/2.0
						ry = -90.0
					1: # East
						wx = (c.x + 1) * TILE_SIZE - 0.05
						wz = c.z * TILE_SIZE + TILE_SIZE/2.0
						ry = 90.0
					2: # North
						wx = c.x * TILE_SIZE + TILE_SIZE/2.0
						wz = c.z * TILE_SIZE + 0.05
						ry = 180.0
					3: # South
						wx = c.x * TILE_SIZE + TILE_SIZE/2.0
						wz = (c.z + 1) * TILE_SIZE - 0.05
						ry = 0.0
			var holder := Node3D.new()
			holder.position = Vector3(wx, 0.0, wz)
			var crystal_src: Dictionary = _pick_light_source(bioluminescent_sources, true)
			var mushroom_src: Dictionary = _pick_light_source(bioluminescent_sources, false)
			var active_src: Dictionary = crystal_src if use_crystal else mushroom_src
			var tex_path := str(active_src.get("tex", ""))
			if load(tex_path):
				_add_3d_mushroom(holder, ry if use_crystal else 0.0, use_crystal, biome_data)
			var light := OmniLight3D.new()
			light.light_color = _as_color(active_src.get("color", Color(0.2, 0.6, 1.0) if use_crystal else Color(0.3, 1.0, 0.3)))
			light.light_energy = float(active_src.get("energy", 1.2))
			light.omni_range = float(active_src.get("range", 15.0))
			light.shadow_enabled = true
			light.position.y = float(active_src.get("height", 1.2)) + 0.2
			holder.add_child(light)
			
			# Add pulsing effect for crystals
			var flicker := FlickerLight.new()
			flicker.mode = FlickerLight.Mode.PULSE
			flicker.base_energy = 1.2
			flicker.max_variation = 0.4
			flicker.speed = 1.5 + randf() * 1.5
			light.add_child(flicker)

			parent.add_child(holder)
		else:
			var light: Light3D
			
			# 50% chance for a cookie projector in non-fungal rooms
			if randf() < 0.5:
				var spot = SpotLight3D.new()
				spot.spot_range = 25.0
				spot.spot_angle = 75.0
				
				var cookie = load(room_cookie_path) if room_cookie_path != "" else null
				if cookie:
					spot.light_projector = cookie
				
				# Point straight down from the ceiling
				spot.rotation_degrees.x = -90 
				pos.y = WALL_HEIGHT * 0.99
				
				light = spot
			else:
				var omni = OmniLight3D.new()
				omni.omni_range = 15.0
				pos.y = WALL_HEIGHT * 0.8
				light = omni

			light.light_color = room_color
			light.light_energy = 1.0
			light.shadow_enabled = true
			light.position = pos
			parent.add_child(light)
			
			# Give room lights a very subtle flicker
			var flicker := FlickerLight.new()
			flicker.mode = FlickerLight.Mode.FLICKER
			flicker.base_energy = 1.0
			flicker.max_variation = 0.15
			light.add_child(flicker)

		
	# Scattered lights along corridors / open floor
	var grid_w = tile_grid.size()
	var grid_h = tile_grid[0].size()
	
	# Fungal biome: use bioluminescent prop sprites as the light source
	if use_bioluminescent_props:
		for x in range(2, grid_w - 2, corridor_step):
			for z in range(2, grid_h - 2, corridor_step):
				if tile_grid[x][z] == TILE_FLOOR and randf() < corridor_chance:
					var src: Dictionary = bioluminescent_sources[randi() % bioluminescent_sources.size()]
					
					# Container node so the sprite and light share a transform
					var holder := Node3D.new()
					var wx = x * TILE_SIZE + TILE_SIZE / 2.0
					var wz = z * TILE_SIZE + TILE_SIZE / 2.0
					# If crystal, shift to wall
					var crystal_ry: float = 0.0
					var is_wall_crystal: bool = false
					var requires_wall: bool = bool(src.get("requires_wall", false))
					if requires_wall:
						var key := _tile_key(x, z)
						if not doorway_owner.has(key):
							# Check neighbors for a flat wall segment
							if x > 0 and tile_grid[x-1][z] == TILE_WALL and tile_grid[x-1][z-1] == TILE_WALL and tile_grid[x-1][z+1] == TILE_WALL:
								wx = x * TILE_SIZE + 0.05
								crystal_ry = -90.0
								is_wall_crystal = true
							elif x < grid_w - 1 and tile_grid[x+1][z] == TILE_WALL and tile_grid[x+1][z-1] == TILE_WALL and tile_grid[x+1][z+1] == TILE_WALL:
								wx = (x + 1) * TILE_SIZE - 0.05
								crystal_ry = 90.0
								is_wall_crystal = true
							elif z > 0 and tile_grid[x][z-1] == TILE_WALL and tile_grid[x-1][z-1] == TILE_WALL and tile_grid[x+1][z-1] == TILE_WALL:
								wz = z * TILE_SIZE + 0.05
								crystal_ry = 180.0
								is_wall_crystal = true
							elif z < grid_h - 1 and tile_grid[x][z+1] == TILE_WALL and tile_grid[x-1][z+1] == TILE_WALL and tile_grid[x+1][z+1] == TILE_WALL:
								wz = (z + 1) * TILE_SIZE - 0.05
								crystal_ry = 0.0
								is_wall_crystal = true
					holder.position = Vector3(wx, 0.0, wz)
					
					# Sprite / Mesh
					var sprite: Sprite3D = null
					if requires_wall:
						if not is_wall_crystal:
							holder.queue_free()
							continue
						sprite = Sprite3D.new()
						sprite.texture = load(str(src.get("tex", "")))
						sprite.billboard = BaseMaterial3D.BILLBOARD_DISABLED
						sprite.rotation_degrees.y = crystal_ry
						sprite.pixel_size = float(src.get("pixel_size", 0.004))
						sprite.position.y = float(src.get("height", 0.8))
						sprite.modulate = _as_color(src.get("color", Color(0.4, 0.3, 0.9))).lightened(0.3)
						holder.add_child(sprite)
					else:
						# It's a mushroom, use the 3D mesh
						_add_3d_mushroom(holder, 0.0, false, biome_data)
					
					# Light
					var light := OmniLight3D.new()
					light.light_color = _as_color(src.get("color", corridor_color))
					light.light_energy = float(src.get("energy", corridor_energy))
					light.omni_range = float(src.get("range", corridor_range))
					light.shadow_enabled = false
					light.position.y = float(src.get("height", 0.8)) + 0.2
					holder.add_child(light)

					# Give bio-lights a nice pulsing effect
					var flicker := FlickerLight.new()
					flicker.mode = FlickerLight.Mode.PULSE
					flicker.base_energy = float(src.get("energy", corridor_energy))
					flicker.max_variation = 0.5 # Substantial pulse
					flicker.speed = 1.0 + randf() * 1.5
					flicker.light_node = light
					if sprite:
						flicker.sprite_node = sprite
					holder.add_child(flicker)
					
					parent.add_child(holder)
	else:
		# Other biomes: plain invisible torchlight
		for x in range(2, grid_w - 2, corridor_step):
			for z in range(2, grid_h - 2, corridor_step):
				if tile_grid[x][z] == TILE_FLOOR and randf() < corridor_chance:
					var light = OmniLight3D.new()
					light.light_color = corridor_color
					light.light_energy = corridor_energy
					light.omni_range = corridor_range
					light.shadow_enabled = false
					
					var wx = x * TILE_SIZE + TILE_SIZE/2.0
					var wz = z * TILE_SIZE + TILE_SIZE/2.0
					light.position = Vector3(wx, WALL_HEIGHT * corridor_height_ratio, wz)
					parent.add_child(light)

					# Add flickering for torches
					var flicker := FlickerLight.new()
					flicker.mode = FlickerLight.Mode.FLICKER
					flicker.base_energy = corridor_energy
					flicker.max_variation = 0.3 # Punchier flicker
					light.add_child(flicker)





func _place_generated_doors(parent: Node3D, doorways: Array, biome_data: Resource = null) -> void:
	var door_scene_path := "res://Scenes/World/door.tscn"
	if biome_data != null:
		var candidate: String = str(biome_data.get("door_scene"))
		if candidate != "":
			door_scene_path = candidate
	var door_scene = load(door_scene_path)
	if not door_scene:
		return

	for doorway in doorways:
		if typeof(doorway) != TYPE_DICTIONARY:
			continue
		if not doorway.has("tile"):
			continue

		var tile: Vector2i = doorway["tile"]
		var orientation := _get_doorway_orientation(doorway)
		if orientation == "":
			continue
		var center_offset_tiles := float(doorway.get("opening_center_offset_tiles", 0.0))

		var door = door_scene.instantiate()
		var wx := tile.x * TILE_SIZE + TILE_SIZE / 2.0
		var wz := tile.y * TILE_SIZE + TILE_SIZE / 2.0
		if orientation == "east_west":
			wx += center_offset_tiles * TILE_SIZE
		else:
			wz += center_offset_tiles * TILE_SIZE
		door.position = Vector3(wx, 0.0, wz)
		if orientation == "north_south":
			door.rotation_degrees.y = 90.0

		parent.add_child(door)

func _place_generated_doorway_assemblies(parent: Node3D, doorways: Array, biome_data: Resource = null) -> void:
	var assembly_path := ""
	var door_scene_path := "res://Scenes/World/door.tscn"
	if biome_data != null:
		var assembly_candidate: String = str(biome_data.get("doorway_assembly_scene"))
		if assembly_candidate != "":
			assembly_path = assembly_candidate
		var door_candidate: String = str(biome_data.get("door_scene"))
		if door_candidate != "":
			door_scene_path = door_candidate

	var assembly_scene = load(assembly_path) if assembly_path != "" else null
	if assembly_scene == null:
		# Fallback to legacy door placement if assembly scene is unavailable.
		_place_generated_doors(parent, doorways, biome_data)
		return

	for doorway in doorways:
		if typeof(doorway) != TYPE_DICTIONARY:
			continue
		if not doorway.has("tile"):
			continue

		var tile: Vector2i = doorway["tile"]
		var orientation := _get_doorway_orientation(doorway)
		if orientation == "":
			continue
		var center_offset_tiles := float(doorway.get("opening_center_offset_tiles", 0.0))
		var wx := tile.x * TILE_SIZE + TILE_SIZE / 2.0
		var wz := tile.y * TILE_SIZE + TILE_SIZE / 2.0
		if orientation == "east_west":
			wx += center_offset_tiles * TILE_SIZE
		else:
			wz += center_offset_tiles * TILE_SIZE

		var doorway_assembly = assembly_scene.instantiate()
		doorway_assembly.position = Vector3(wx, 0.0, wz)
		if orientation == "north_south":
			doorway_assembly.rotation_degrees.y = 90.0
		parent.add_child(doorway_assembly)

func _add_3d_mushroom(parent: Node3D, ry: float, is_crystal: bool, biome_data: Resource = null) -> void:
	var scene_path := "res://Scenes/Dungeon/fungal_crystal.tscn" if is_crystal else "res://Scenes/Dungeon/fungal_mushroom.tscn"
	if _has_biome_data(biome_data):
		if is_crystal and biome_data.crystal_scene != "":
			scene_path = biome_data.crystal_scene
		elif not is_crystal and biome_data.mushroom_scene != "":
			scene_path = biome_data.mushroom_scene
	var scene = load(scene_path)
	if scene:
		var inst = scene.instantiate()
		parent.add_child(inst)
		if is_crystal:
			inst.rotation_degrees.y = ry

func _pick_light_source(sources: Array, requires_wall: bool) -> Dictionary:
	for src_variant in sources:
		if typeof(src_variant) != TYPE_DICTIONARY:
			continue
		var src: Dictionary = src_variant
		if bool(src.get("requires_wall", false)) == requires_wall:
			return src
	if not sources.is_empty() and typeof(sources[0]) == TYPE_DICTIONARY:
		return sources[0]
	return {}

func _has_biome_data(biome_data: Resource) -> bool:
	if biome_data == null:
		return false
	for p in biome_data.get_property_list():
		if typeof(p) == TYPE_DICTIONARY and str(p.get("name", "")) == "biome_id":
			return true
	return false

func _as_color(value: Variant) -> Color:
	if typeof(value) == TYPE_COLOR:
		return value
	return Color(1, 1, 1, 1)

func _get_doorway_orientation(doorway: Dictionary) -> String:
	if doorway.has("orientation"):
		var orientation := str(doorway["orientation"])
		if orientation == "east_west" or orientation == "north_south":
			return orientation
	if doorway.has("axis"):
		var axis := str(doorway["axis"])
		if axis == "x":
			return "north_south"
		if axis == "z":
			return "east_west"
	return ""
