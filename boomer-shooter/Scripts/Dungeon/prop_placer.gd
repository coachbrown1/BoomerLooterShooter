extends RefCounted
class_name PropPlacer

const TILE_SIZE: float = 3.0

# -------------------------------------------------------
# Prop Asset Sets
# -------------------------------------------------------
const OUTLINE_MAT = preload("res://Materials/prop_outline_material.tres")

const CRATE_TEX := "res://Assets/Environment/prop_crate.png"
const CRATE_SIZE := Vector3(0.85, 0.85, 0.85)

const BARREL_SIDE_TEX := "res://Assets/Environment/prop_barrel_side.png"
const BARREL_TOP_TEX := "res://Assets/Environment/prop_barrel_top.png"
const BARREL_SIZE := Vector2(0.35, 0.9) # Radius, Height

const UNIVERSAL_PROPS := [
	BARREL_SIDE_TEX,
	CRATE_TEX,
	"res://Assets/Environment/prop_skull_pile.png",
	"res://Assets/Environment/prop_broken_pillar.png",
]

const BIOME_PROPS := {
	"crypt": [
		"res://Assets/Environment/Crypt/prop_crypt_coffin.png",
		"res://Assets/Environment/Crypt/prop_crypt_tombstone.png",
		"res://Assets/Environment/Crypt/prop_crypt_iron_maiden.png",
		"res://Assets/Environment/Crypt/prop_crypt_candelabra.png",
		"res://Assets/Environment/Crypt/prop_crypt_banner.png",
		"res://Assets/Environment/Crypt/prop_crypt_bone_pile.png",
	],
	"fungal": [
		"res://Assets/Environment/Fungal/prop_fungal_slime_pool.png",
		"res://Assets/Environment/Fungal/prop_fungal_vines.png",
		"res://Assets/Environment/Fungal/prop_fungal_pods.png",
		"res://Assets/Environment/Fungal/prop_fungal_moss_rock.png",
	],
	"lava": [
		"res://Assets/Environment/Lava/prop_lava_crack.png",
		"res://Assets/Environment/Lava/prop_lava_spike.png",
		"res://Assets/Environment/Lava/prop_lava_brazier.png",
		"res://Assets/Environment/Lava/prop_lava_charred_bones.png",
		"res://Assets/Environment/Lava/prop_lava_magma_rock.png",
		"res://Assets/Environment/Lava/prop_lava_sulfur_vent.png",
	]
}

# -------------------------------------------------------
# Placement Logic
# -------------------------------------------------------
func populate(parent: Node3D, rooms: Array, tile_grid: Array, rng: RandomNumberGenerator) -> void:
	var grid_w: int = tile_grid.size()
	var grid_h: int = tile_grid[0].size() if grid_w > 0 else 0

	for room in rooms:
		var area = room.grid_rect.size.x * room.grid_rect.size.y
		var prop_count = mini(8, max(3, area / 15))
		
		var pool: Array = UNIVERSAL_PROPS.duplicate()
		if BIOME_PROPS.has(room.biome):
			pool.append_array(BIOME_PROPS[room.biome])
			
		for i in range(prop_count):
			var rx = room.grid_rect.position.x + 1 + rng.randi() % maxi(1, room.grid_rect.size.x - 2)
			var rz = room.grid_rect.position.y + 1 + rng.randi() % maxi(1, room.grid_rect.size.y - 2)
			
			if tile_grid[rx][rz] != 1:
				continue
				
			# Wall-hug offset
			var wall_offset = Vector3.ZERO
			if tile_grid[rx - 1][rz] == 0: wall_offset = Vector3(-0.3, 0, 0)
			elif tile_grid[rx + 1][rz] == 0: wall_offset = Vector3(0.3, 0, 0)
			elif tile_grid[rx][rz - 1] == 0: wall_offset = Vector3(0, 0, -0.3)
			elif tile_grid[rx][rz + 1] == 0: wall_offset = Vector3(0, 0, 0.3)
			
			var world_x = rx * TILE_SIZE + TILE_SIZE / 2.0
			var world_z = rz * TILE_SIZE + TILE_SIZE / 2.0
			var prop_tex_path = pool[rng.randi() % pool.size()]
			
			if prop_tex_path == CRATE_TEX:
				_place_crate(parent, Vector3(world_x, 0.0, world_z) + wall_offset, rng)
			elif prop_tex_path == BARREL_SIDE_TEX:
				_place_barrel(parent, Vector3(world_x, 0.0, world_z) + wall_offset, rng)
			else:
				_place_sprite_prop(parent, prop_tex_path, Vector3(world_x, 0.0, world_z), wall_offset)

# -------------------------------------------------------
# 3D Crate — manually built so each face gets full 0–1 UVs
# -------------------------------------------------------
func _place_crate(parent: Node3D, base_pos: Vector3, rng: RandomNumberGenerator) -> void:
	var tex = load(CRATE_TEX) as Texture2D
	if not tex:
		return

	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	var body := StaticBody3D.new()
	body.name = "Crate"

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(mat)

	var s := CRATE_SIZE * 0.5

	_add_box_face(st, Vector3(-s.x, s.y, -s.z), Vector3( s.x, s.y, -s.z), Vector3( s.x, s.y,  s.z), Vector3(-s.x, s.y,  s.z), Vector3.UP)
	_add_box_face(st, Vector3(-s.x, -s.y,  s.z), Vector3( s.x, -s.y,  s.z), Vector3( s.x, -s.y, -s.z), Vector3(-s.x, -s.y, -s.z), Vector3.DOWN)
	_add_box_face(st, Vector3(-s.x, -s.y, s.z), Vector3( s.x, -s.y, s.z), Vector3( s.x,  s.y, s.z), Vector3(-s.x,  s.y, s.z), Vector3(0,0,1))
	_add_box_face(st, Vector3( s.x, -s.y, -s.z), Vector3(-s.x, -s.y, -s.z), Vector3(-s.x,  s.y, -s.z), Vector3( s.x,  s.y, -s.z), Vector3(0,0,-1))
	_add_box_face(st, Vector3(s.x, -s.y,  s.z), Vector3(s.x, -s.y, -s.z), Vector3(s.x,  s.y, -s.z), Vector3(s.x,  s.y,  s.z), Vector3(1,0,0))
	_add_box_face(st, Vector3(-s.x, -s.y, -s.z), Vector3(-s.x, -s.y,  s.z), Vector3(-s.x,  s.y,  s.z), Vector3(-s.x,  s.y, -s.z), Vector3(-1,0,0))

	st.generate_normals()
	var mesh_inst := MeshInstance3D.new()
	mesh_inst.mesh = st.commit()
	mesh_inst.position.y = CRATE_SIZE.y / 2.0
	body.add_child(mesh_inst)

	var col := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = CRATE_SIZE
	col.shape = box_shape
	col.position.y = CRATE_SIZE.y / 2.0
	body.add_child(col)

	body.rotation_degrees.y = float(rng.randi() % 4) * 90.0
	body.position = base_pos
	parent.add_child(body)

func _add_box_face(st: SurfaceTool, v0: Vector3, v1: Vector3, v2: Vector3, v3: Vector3, n: Vector3) -> void:
	st.set_normal(n); st.set_uv(Vector2(0, 0)); st.add_vertex(v0)
	st.set_normal(n); st.set_uv(Vector2(1, 0)); st.add_vertex(v3)
	st.set_normal(n); st.set_uv(Vector2(1, 1)); st.add_vertex(v2)
	st.set_normal(n); st.set_uv(Vector2(0, 0)); st.add_vertex(v0)
	st.set_normal(n); st.set_uv(Vector2(1, 1)); st.add_vertex(v2)
	st.set_normal(n); st.set_uv(Vector2(0, 1)); st.add_vertex(v1)

# -------------------------------------------------------
# 3D Barrel
# -------------------------------------------------------
func _place_barrel(parent: Node3D, base_pos: Vector3, rng: RandomNumberGenerator) -> void:
	var side_tex = load(BARREL_SIDE_TEX) as Texture2D
	var top_tex = load(BARREL_TOP_TEX) as Texture2D
	if not side_tex or not top_tex:
		return

	var side_mat := StandardMaterial3D.new()
	side_mat.albedo_texture = side_tex
	side_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	
	var top_mat := StandardMaterial3D.new()
	top_mat.albedo_texture = top_tex
	top_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR

	var body := StaticBody3D.new()
	body.name = "Barrel"

	var mesh_inst := MeshInstance3D.new()
	var cylinder_mesh := CylinderMesh.new()
	cylinder_mesh.top_radius = BARREL_SIZE.x
	cylinder_mesh.bottom_radius = BARREL_SIZE.x
	cylinder_mesh.height = BARREL_SIZE.y
	cylinder_mesh.radial_segments = 12
	
	# CylinderMesh by default has 3 surfaces: bottom, side, top if I recall correctly.
	# Or sometimes it's just one surface with an atlas.
	# Actually, CylinderMesh is a primitive with one surface usually.
	# Let's check how many surfaces it has. If it has one, I'll need a shader or an atlas.
	# Alternatively, I can build it with SurfaceTool.
	
	# Let's build it with SurfaceTool to be safe and have full control over UVs.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	var radius = BARREL_SIZE.x
	var height = BARREL_SIZE.y
	var segments = 12
	
	# Side
	side_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	st.set_material(side_mat)
	for i in range(segments):
		var angle1 = float(i) / segments * PI * 2.0
		var angle2 = float(i + 1) / segments * PI * 2.0
		
		var x1 = cos(angle1) * radius
		var z1 = sin(angle1) * radius
		var x2 = cos(angle2) * radius
		var z2 = sin(angle2) * radius
		
		var v1_bottom = Vector3(x1, -height/2, z1)
		var v1_top = Vector3(x1, height/2, z1)
		var v2_bottom = Vector3(x2, -height/2, z2)
		var v2_top = Vector3(x2, height/2, z2)
		
		var u1 = float(i) / segments
		var u2 = float(i + 1) / segments
		
		var n1 = Vector3(cos(angle1), 0, sin(angle1))
		var n2 = Vector3(cos(angle2), 0, sin(angle2))
		
		# Triangle 1
		st.set_normal(n1); st.set_uv(Vector2(u1, 1)); st.add_vertex(v1_bottom)
		st.set_normal(n2); st.set_uv(Vector2(u2, 0)); st.add_vertex(v2_top)
		st.set_normal(n2); st.set_uv(Vector2(u2, 1)); st.add_vertex(v2_bottom)
		
		# Triangle 2
		st.set_normal(n1); st.set_uv(Vector2(u1, 1)); st.add_vertex(v1_bottom)
		st.set_normal(n1); st.set_uv(Vector2(u1, 0)); st.add_vertex(v1_top)
		st.set_normal(n2); st.set_uv(Vector2(u2, 0)); st.add_vertex(v2_top)


	# Commit the side surface
	var mesh = st.commit()
	
	# Top
	top_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(top_mat)

	for i in range(segments):
		var angle1 = float(i) / segments * PI * 2.0
		var angle2 = float(i + 1) / segments * PI * 2.0
		
		var x1 = cos(angle1) * radius
		var z1 = sin(angle1) * radius
		var x2 = cos(angle2) * radius
		var z2 = sin(angle2) * radius
		
		# UVs for top: map (x,z) to (0.5+x/2r, 0.5+z/2r)
		var uv1 = Vector2(0.5 + cos(angle1)*0.5, 0.5 + sin(angle1)*0.5)
		var uv2 = Vector2(0.5 + cos(angle2)*0.5, 0.5 + sin(angle2)*0.5)
		var uv_center = Vector2(0.5, 0.5)
		
		st.set_normal(Vector3.UP); st.set_uv(uv_center); st.add_vertex(Vector3(0, height/2, 0))
		st.set_normal(Vector3.UP); st.set_uv(uv2); st.add_vertex(Vector3(x2, height/2, z2))
		st.set_normal(Vector3.UP); st.set_uv(uv1); st.add_vertex(Vector3(x1, height/2, z1))

	# Commit top surface to the same ArrayMesh
	st.commit(mesh)
	
	mesh_inst.mesh = mesh
	mesh_inst.position.y = height / 2.0
	body.add_child(mesh_inst)

	var col := CollisionShape3D.new()
	var cylinder_shape := CylinderShape3D.new()
	cylinder_shape.radius = radius
	cylinder_shape.height = height
	col.shape = cylinder_shape
	col.position.y = height / 2.0
	body.add_child(col)

	body.rotation_degrees.y = rng.randf_range(0, 360)
	body.position = base_pos
	parent.add_child(body)

const WALL_HEIGHT: float = 4.0

# -------------------------------------------------------
# Billboard Sprite Prop
# -------------------------------------------------------
func _place_sprite_prop(parent: Node3D, tex_path: String, base_pos: Vector3, wall_offset: Vector3) -> void:
	var tex = load(tex_path)
	if not tex:
		return

	var sprite := Sprite3D.new()
	sprite.texture = tex
	sprite.material_override = OUTLINE_MAT.duplicate()
	sprite.material_override.set_shader_parameter("texture_albedo", tex)
	sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	sprite.pixel_size = 0.015

	if "crack" in tex_path or "pool" in tex_path:
		sprite.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		sprite.rotation_degrees.x = -90
		sprite.position = Vector3(base_pos.x, 0.05, base_pos.z)
	elif "vines" in tex_path:
		# Place at ceiling
		var height = tex.get_height() * sprite.pixel_size
		sprite.position = Vector3(base_pos.x, WALL_HEIGHT - (height / 2.0), base_pos.z) + wall_offset
	else:
		sprite.position = Vector3(base_pos.x, 1.0, base_pos.z) + wall_offset

	parent.add_child(sprite)
