@tool
extends Marker3D
class_name HandcraftedEnemySpawner

const PREVIEW_NODE_NAME := "_SpawnRadiusPreview"
const PREVIEW_SEGMENTS := 48

@export var enemy_scene: PackedScene
@export_range(1, 8, 1) var spawn_count: int = 1:
	set(value):
		spawn_count = value
		_rebuild_preview()
@export_range(0.0, 6.0, 0.1) var spawn_radius: float = 0.0:
	set(value):
		spawn_radius = value
		_rebuild_preview()
@export_range(0.0, 3.0, 0.1) var vertical_offset: float = 0.0:
	set(value):
		vertical_offset = value
		_rebuild_preview()

func _ready() -> void:
	set_notify_local_transform(true)
	_rebuild_preview()

func _notification(what: int) -> void:
	if what == NOTIFICATION_LOCAL_TRANSFORM_CHANGED and Engine.is_editor_hint():
		_rebuild_preview()

func get_spawn_position(index: int) -> Vector3:
	if spawn_count <= 1 or spawn_radius <= 0.0:
		return global_position + Vector3(0.0, vertical_offset, 0.0)
	var angle_step := TAU / float(spawn_count)
	var angle := angle_step * float(index)
	var offset := Vector3(cos(angle), 0.0, sin(angle)) * spawn_radius
	return global_position + offset + Vector3(0.0, vertical_offset, 0.0)

func _rebuild_preview() -> void:
	var preview := get_node_or_null(PREVIEW_NODE_NAME) as MeshInstance3D
	if not Engine.is_editor_hint():
		if preview != null:
			preview.queue_free()
		return
	if preview == null:
		preview = MeshInstance3D.new()
		preview.name = PREVIEW_NODE_NAME
		preview.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(preview)
		preview.owner = null

	if spawn_radius <= 0.0:
		preview.visible = false
		preview.mesh = null
		return

	preview.visible = true
	preview.position = Vector3(0.0, vertical_offset, 0.0)
	preview.mesh = _build_preview_mesh()

func _build_preview_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)
	var color := Color(0.95, 0.35, 0.2, 0.95)
	for index in range(PREVIEW_SEGMENTS):
		var t0 := TAU * float(index) / float(PREVIEW_SEGMENTS)
		var t1 := TAU * float(index + 1) / float(PREVIEW_SEGMENTS)
		var p0 := Vector3(cos(t0) * spawn_radius, 0.0, sin(t0) * spawn_radius)
		var p1 := Vector3(cos(t1) * spawn_radius, 0.0, sin(t1) * spawn_radius)
		st.set_color(color)
		st.add_vertex(p0)
		st.set_color(color)
		st.add_vertex(p1)

	if spawn_count > 1:
		var point_color := Color(1.0, 0.8, 0.2, 0.95)
		for index in range(spawn_count):
			var spawn_local := to_local(get_spawn_position(index))
			var tick_size := 0.18
			st.set_color(point_color)
			st.add_vertex(spawn_local + Vector3(-tick_size, 0.0, 0.0))
			st.set_color(point_color)
			st.add_vertex(spawn_local + Vector3(tick_size, 0.0, 0.0))
			st.set_color(point_color)
			st.add_vertex(spawn_local + Vector3(0.0, 0.0, -tick_size))
			st.set_color(point_color)
			st.add_vertex(spawn_local + Vector3(0.0, 0.0, tick_size))

	var mesh := st.commit()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.no_depth_test = true
	mesh.surface_set_material(0, material)
	return mesh
