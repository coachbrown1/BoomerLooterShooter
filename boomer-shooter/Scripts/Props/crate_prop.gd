@tool
extends PropBase
class_name CrateProp

const CRATE_SIZE := Vector3(0.85, 0.85, 0.85)

@export var crate_texture_path: String = "res://Assets/Environment/prop_crate.png"

func _ready() -> void:
	placement_kind = PlacementKind.WALL_OFFSET
	random_y_rotation = true
	random_y_rotation_min = 0.0
	random_y_rotation_max = 270.0
	_ensure_mesh()

func _on_placed(rng: RandomNumberGenerator) -> void:
	rotation_degrees.y = float(rng.randi() % 4) * 90.0

func _ensure_mesh() -> void:
	if get_node_or_null("MeshInstance3D"):
		return
	var tex = load(crate_texture_path) as Texture2D
	if not tex:
		return

	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED

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
	mesh_inst.name = "MeshInstance3D"
	mesh_inst.mesh = st.commit()
	mesh_inst.position.y = CRATE_SIZE.y / 2.0
	add_child(mesh_inst)

	var col := CollisionShape3D.new()
	col.name = "CollisionShape3D"
	var box_shape := BoxShape3D.new()
	box_shape.size = CRATE_SIZE
	col.shape = box_shape
	col.position.y = CRATE_SIZE.y / 2.0
	add_child(col)

func _add_box_face(st: SurfaceTool, v0: Vector3, v1: Vector3, v2: Vector3, v3: Vector3, n: Vector3) -> void:
	st.set_normal(n); st.set_uv(Vector2(0, 0)); st.add_vertex(v0)
	st.set_normal(n); st.set_uv(Vector2(1, 0)); st.add_vertex(v3)
	st.set_normal(n); st.set_uv(Vector2(1, 1)); st.add_vertex(v2)
	st.set_normal(n); st.set_uv(Vector2(0, 0)); st.add_vertex(v0)
	st.set_normal(n); st.set_uv(Vector2(1, 1)); st.add_vertex(v2)
	st.set_normal(n); st.set_uv(Vector2(0, 1)); st.add_vertex(v1)
