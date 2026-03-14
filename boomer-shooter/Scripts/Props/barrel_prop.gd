@tool
extends PropBase
class_name BarrelProp

const BARREL_SIZE := Vector2(0.35, 0.9) # radius, height

@export var barrel_side_texture_path: String = "res://Assets/Environment/prop_barrel_side.png"
@export var barrel_top_texture_path: String = "res://Assets/Environment/prop_barrel_top.png"

func _ready() -> void:
	placement_kind = PlacementKind.WALL_OFFSET
	random_y_rotation = true
	_ensure_mesh()

func _on_placed(rng: RandomNumberGenerator) -> void:
	rotation_degrees.y = rng.randf_range(0, 360)

func _ensure_mesh() -> void:
	if get_node_or_null("MeshInstance3D"):
		return
	var side_tex = load(barrel_side_texture_path) as Texture2D
	var top_tex = load(barrel_top_texture_path) as Texture2D
	if not side_tex or not top_tex:
		return

	var side_mat := StandardMaterial3D.new()
	side_mat.albedo_texture = side_tex
	side_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	side_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	var top_mat := StandardMaterial3D.new()
	top_mat.albedo_texture = top_tex
	top_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	top_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(side_mat)

	var radius = BARREL_SIZE.x
	var height = BARREL_SIZE.y
	var segments = 12

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

		st.set_normal(n1); st.set_uv(Vector2(u1, 1)); st.add_vertex(v1_bottom)
		st.set_normal(n2); st.set_uv(Vector2(u2, 0)); st.add_vertex(v2_top)
		st.set_normal(n2); st.set_uv(Vector2(u2, 1)); st.add_vertex(v2_bottom)

		st.set_normal(n1); st.set_uv(Vector2(u1, 1)); st.add_vertex(v1_bottom)
		st.set_normal(n1); st.set_uv(Vector2(u1, 0)); st.add_vertex(v1_top)
		st.set_normal(n2); st.set_uv(Vector2(u2, 0)); st.add_vertex(v2_top)

	var mesh = st.commit()

	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(top_mat)

	for i in range(segments):
		var angle1 = float(i) / segments * PI * 2.0
		var angle2 = float(i + 1) / segments * PI * 2.0

		var x1 = cos(angle1) * radius
		var z1 = sin(angle1) * radius
		var x2 = cos(angle2) * radius
		var z2 = sin(angle2) * radius

		var uv1 = Vector2(0.5 + cos(angle1) * 0.5, 0.5 + sin(angle1) * 0.5)
		var uv2 = Vector2(0.5 + cos(angle2) * 0.5, 0.5 + sin(angle2) * 0.5)
		var uv_center = Vector2(0.5, 0.5)

		st.set_normal(Vector3.UP); st.set_uv(uv_center); st.add_vertex(Vector3(0, height/2, 0))
		st.set_normal(Vector3.UP); st.set_uv(uv2); st.add_vertex(Vector3(x2, height/2, z2))
		st.set_normal(Vector3.UP); st.set_uv(uv1); st.add_vertex(Vector3(x1, height/2, z1))

	st.commit(mesh)

	var mesh_inst := MeshInstance3D.new()
	mesh_inst.name = "MeshInstance3D"
	mesh_inst.mesh = mesh
	mesh_inst.position.y = height / 2.0
	add_child(mesh_inst)

	var col := CollisionShape3D.new()
	col.name = "CollisionShape3D"
	var cylinder_shape := CylinderShape3D.new()
	cylinder_shape.radius = radius
	cylinder_shape.height = height
	col.shape = cylinder_shape
	col.position.y = height / 2.0
	add_child(col)
