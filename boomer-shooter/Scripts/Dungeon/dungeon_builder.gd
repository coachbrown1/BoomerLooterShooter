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
# Biome texture paths
# -------------------------------------------------------
const BIOME_TEXTURES := {
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

const DOORWAY_ASSEMBLY_SCENE := "res://Scenes/Dungeon/doorway_assembly.tscn"
const FUNGAL_MUSHROOM_SCENE := "res://Scenes/Dungeon/fungal_mushroom.tscn"
const FUNGAL_CRYSTAL_SCENE := "res://Scenes/Dungeon/fungal_crystal.tscn"

# Cached materials per biome
var _mat_cache := {}

# -------------------------------------------------------
# Main build entry
# -------------------------------------------------------
func build(tile_grid: Array, rooms: Array, corridors: Array, doorways: Array, parent: Node3D) -> void:
	var grid_w: int = tile_grid.size()
	var grid_h: int = tile_grid[0].size() if grid_w > 0 else 0

	# Determine dominant biome from rooms
	var biome := "crypt"
	if rooms.size() > 0:
		biome = rooms[0].biome

	var mats_floor   := _get_materials(biome, "floor")
	var mats_wall    := _get_materials(biome, "wall")
	var mats_ceiling := _get_materials(biome, "ceiling")
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
	_place_generated_doorway_assemblies(geo_root, doorways)
	_place_lights(geo_root, rooms, tile_grid, biome, doorway_opening_owner)

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
func _get_materials(biome: String, surface: String) -> Array:
	var key := biome + "_" + surface
	if _mat_cache.has(key):
		return _mat_cache[key]

	var mats = []
	var paths: Dictionary = BIOME_TEXTURES.get(biome, BIOME_TEXTURES["crypt"])
	var tex_paths: Array = paths.get(surface, [])
	
	if typeof(tex_paths) != TYPE_ARRAY:
		tex_paths = [tex_paths] # fallback if it was a single string earlier
		
	for tex_path in tex_paths:
		var mat := StandardMaterial3D.new()
		if tex_path != "":
			var tex = load(tex_path)
			if tex:
				mat.albedo_texture = tex
				if biome == "fungal":
					mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
					mat.uv1_scale = Vector3(1.0, 1.0, 1.0)
				else:
					mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
					mat.uv1_scale = Vector3(2.0, 2.0, 2.0)
		mats.append(mat)

	if mats.is_empty():
		mats.append(StandardMaterial3D.new())

	_mat_cache[key] = mats
	return mats

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
func _place_lights(parent: Node3D, rooms: Array, tile_grid: Array, biome: String, doorway_owner: Dictionary) -> void:
	var room_color: Color
	if biome == "crypt":
		room_color = Color(0.9, 0.75, 0.5)
	elif biome == "fungal":
		room_color = Color(0.4, 0.9, 0.5)
	else: # lava
		room_color = Color(1.0, 0.4, 0.15)
		
	# Room center lights
	for r in rooms:
		var pos = r.get_world_center(TILE_SIZE)

		if biome == "fungal":
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
			var tex_path = "res://Assets/Environment/Fungal/prop_fungal_crystal.png" if use_crystal else "res://Assets/Environment/Fungal/prop_fungal_mushroom.png"
			if load(tex_path):
				_add_3d_mushroom(holder, ry if use_crystal else 0.0, use_crystal)
			var light := OmniLight3D.new()
			light.light_color = Color(0.2, 0.6, 1.0) if use_crystal else Color(0.3, 1.0, 0.3)
			light.light_energy = 1.2
			light.omni_range = 15.0
			light.shadow_enabled = true
			light.position.y = 1.4
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
				
				var cookie = load("res://Assets/Effects/cookie_grate.png")
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
	if biome == "fungal":
		var fungal_light_sources := [
			{
				"tex": "res://Assets/Environment/Fungal/prop_fungal_crystal.png",
				"color": Color(0.4, 0.3, 0.9),   # purple crystal glow
				"energy": 0.9,
				"range": 7.0,
				"height": 0.8,
				"pixel_size": 0.004,
			},
			{
				"tex": "res://Assets/Environment/Fungal/prop_fungal_mushroom.png",
				"color": Color(0.2, 1.0, 0.5),   # green mushroom glow
				"energy": 0.6,
				"range": 5.0,
				"height": 0.9,
				"pixel_size": 0.0035,
			},
		]
		
		for x in range(2, grid_w - 2, 5):
			for z in range(2, grid_h - 2, 5):
				if tile_grid[x][z] == TILE_FLOOR and randf() < 0.3:
					var src = fungal_light_sources[randi() % fungal_light_sources.size()]
					
					# Container node so the sprite and light share a transform
					var holder := Node3D.new()
					var wx = x * TILE_SIZE + TILE_SIZE / 2.0
					var wz = z * TILE_SIZE + TILE_SIZE / 2.0
					# If crystal, shift to wall
					var crystal_ry: float = 0.0
					var is_wall_crystal: bool = false
					if "crystal" in src["tex"]:
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
					if "crystal" in src["tex"]:
						if not is_wall_crystal:
							holder.queue_free()
							continue
						sprite = Sprite3D.new()
						sprite.texture = load(src["tex"])
						sprite.billboard = BaseMaterial3D.BILLBOARD_DISABLED
						sprite.rotation_degrees.y = crystal_ry
						sprite.pixel_size = src["pixel_size"]
						sprite.position.y = src["height"]
						sprite.modulate = src["color"].lightened(0.3)
						holder.add_child(sprite)
					else:
						# It's a mushroom, use the 3D mesh
						_add_3d_mushroom(holder, 0.0, false)
					
					# Light
					var light := OmniLight3D.new()
					light.light_color = src["color"]
					light.light_energy = src["energy"]
					light.omni_range = src["range"]
					light.shadow_enabled = false
					light.position.y = src["height"] + 0.2
					holder.add_child(light)

					# Give bio-lights a nice pulsing effect
					var flicker := FlickerLight.new()
					flicker.mode = FlickerLight.Mode.PULSE
					flicker.base_energy = src["energy"]
					flicker.max_variation = 0.5 # Substantial pulse
					flicker.speed = 1.0 + randf() * 1.5
					flicker.light_node = light
					if sprite:
						flicker.sprite_node = sprite
					holder.add_child(flicker)
					
					parent.add_child(holder)
	else:
		# Other biomes: plain invisible torchlight
		var corridor_color = Color(1.0, 0.6, 0.2) if biome == "crypt" else Color(1.0, 0.35, 0.1)
		for x in range(2, grid_w - 2, 4):
			for z in range(2, grid_h - 2, 4):
				if tile_grid[x][z] == TILE_FLOOR and randf() < 0.3:
					var light = OmniLight3D.new()
					light.light_color = corridor_color
					light.light_energy = 0.5
					light.omni_range = 6.0
					light.shadow_enabled = false
					
					var wx = x * TILE_SIZE + TILE_SIZE/2.0
					var wz = z * TILE_SIZE + TILE_SIZE/2.0
					light.position = Vector3(wx, WALL_HEIGHT * 0.6, wz)
					parent.add_child(light)

					# Add flickering for torches
					var flicker := FlickerLight.new()
					flicker.mode = FlickerLight.Mode.FLICKER
					flicker.base_energy = 0.5
					flicker.max_variation = 0.3 # Punchier flicker
					light.add_child(flicker)





func _place_generated_doors(parent: Node3D, doorways: Array) -> void:
	var door_scene = load("res://Scenes/World/door.tscn")
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

func _place_generated_doorway_assemblies(parent: Node3D, doorways: Array) -> void:
	var assembly_scene = load(DOORWAY_ASSEMBLY_SCENE)
	var fallback_door_scene = load("res://Scenes/World/door.tscn")
	if assembly_scene == null:
		# Fallback to legacy door placement if assembly scene is unavailable.
		_place_generated_doors(parent, doorways)
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

		var biome := str(doorway.get("biome", "crypt"))
		if biome != "fungal":
			# Non-fungal biomes currently use door-only until dedicated assembly art exists.
			if fallback_door_scene:
				var door = fallback_door_scene.instantiate()
				door.position = Vector3(wx, 0.0, wz)
				if orientation == "north_south":
					door.rotation_degrees.y = 90.0
				parent.add_child(door)
			continue

		var doorway_assembly = assembly_scene.instantiate()
		doorway_assembly.position = Vector3(wx, 0.0, wz)
		if orientation == "north_south":
			doorway_assembly.rotation_degrees.y = 90.0
		parent.add_child(doorway_assembly)

func _add_3d_mushroom(parent: Node3D, ry: float, is_crystal: bool) -> void:
	var scene_path = FUNGAL_CRYSTAL_SCENE if is_crystal else FUNGAL_MUSHROOM_SCENE
	var scene = load(scene_path)
	if scene:
		var inst = scene.instantiate()
		parent.add_child(inst)
		if is_crystal:
			inst.rotation_degrees.y = ry

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
