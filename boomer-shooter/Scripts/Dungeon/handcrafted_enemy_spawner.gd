@tool
extends Area3D
class_name HandcraftedEnemySpawner

const PREVIEW_NODE_NAME := "_SpawnVolumePreview"
const MIN_PREVIEW_THICKNESS := 0.1

@export var enemy_scene: PackedScene
@export_range(1, 8, 1) var spawn_count: int = 1:
	set(value):
		spawn_count = value
		_rebuild_preview()
@export var spawn_box_size: Vector3 = Vector3(4.0, 0.0, 4.0):
	set(value):
		spawn_box_size = Vector3(maxf(value.x, 0.0), maxf(value.y, 0.0), maxf(value.z, 0.0))
		_rebuild_preview()
@export_range(0.0, 3.0, 0.1) var vertical_offset: float = 0.0:
	set(value):
		vertical_offset = value
		_rebuild_preview()

var spawn_radius: float = 0.0

@onready var _collision_shape: CollisionShape3D = $CollisionShape3D

func _ready() -> void:
	monitoring = false
	monitorable = false
	collision_layer = 0
	collision_mask = 0
	_migrate_legacy_radius()
	set_notify_local_transform(true)
	_rebuild_preview()

func _notification(what: int) -> void:
	if what == NOTIFICATION_LOCAL_TRANSFORM_CHANGED and Engine.is_editor_hint():
		_rebuild_preview()

func get_spawn_position(index: int) -> Vector3:
	return to_global(_get_spawn_local_position(index))

func _get_spawn_local_position(index: int) -> Vector3:
	if spawn_count <= 1 and spawn_box_size == Vector3.ZERO:
		return Vector3(0.0, vertical_offset, 0.0)
	var rng := RandomNumberGenerator.new()
	var identity: String = String(get_path()) if is_inside_tree() else String(name)
	rng.seed = hash("%s|%d|%d" % [identity, index, spawn_count])
	var half_x := spawn_box_size.x * 0.5
	var half_z := spawn_box_size.z * 0.5
	var y_span := maxf(spawn_box_size.y, 0.0)
	return Vector3(
		rng.randf_range(-half_x, half_x),
		vertical_offset + (0.0 if y_span <= 0.0 else rng.randf_range(0.0, y_span)),
		rng.randf_range(-half_z, half_z)
	)

func _migrate_legacy_radius() -> void:
	if spawn_radius <= 0.0:
		return
	if spawn_box_size != Vector3(4.0, 0.0, 4.0):
		return
	spawn_box_size = Vector3(spawn_radius * 2.0, 0.0, spawn_radius * 2.0)
	spawn_radius = 0.0

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

	_sync_collision_shape()
	preview.visible = true
	preview.mesh = _build_preview_mesh()

func _sync_collision_shape() -> void:
	if _collision_shape == null:
		return
	var shape := _collision_shape.shape as BoxShape3D
	if shape == null:
		shape = BoxShape3D.new()
		_collision_shape.shape = shape
	var preview_size := _get_preview_box_size()
	shape.size = preview_size
	_collision_shape.position = Vector3(0.0, vertical_offset + preview_size.y * 0.5, 0.0)

func _build_preview_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)
	var color := Color(0.95, 0.35, 0.2, 0.95)
	var preview_size := _get_preview_box_size()
	var center := Vector3(0.0, vertical_offset + preview_size.y * 0.5, 0.0)
	var half := preview_size * 0.5
	var corners := [
		center + Vector3(-half.x, -half.y, -half.z),
		center + Vector3(half.x, -half.y, -half.z),
		center + Vector3(half.x, -half.y, half.z),
		center + Vector3(-half.x, -half.y, half.z),
		center + Vector3(-half.x, half.y, -half.z),
		center + Vector3(half.x, half.y, -half.z),
		center + Vector3(half.x, half.y, half.z),
		center + Vector3(-half.x, half.y, half.z),
	]
	var edges := [
		[0, 1], [1, 2], [2, 3], [3, 0],
		[4, 5], [5, 6], [6, 7], [7, 4],
		[0, 4], [1, 5], [2, 6], [3, 7],
	]
	for edge in edges:
		st.set_color(color)
		st.add_vertex(corners[edge[0]])
		st.set_color(color)
		st.add_vertex(corners[edge[1]])

	var point_color := Color(1.0, 0.8, 0.2, 0.95)
	for index in range(maxi(1, spawn_count)):
		var spawn_local := _get_spawn_local_position(index)
		var tick_size := 0.18
		st.set_color(point_color)
		st.add_vertex(spawn_local + Vector3(-tick_size, 0.0, 0.0))
		st.set_color(point_color)
		st.add_vertex(spawn_local + Vector3(tick_size, 0.0, 0.0))
		st.set_color(point_color)
		st.add_vertex(spawn_local + Vector3(0.0, -tick_size, 0.0))
		st.set_color(point_color)
		st.add_vertex(spawn_local + Vector3(0.0, tick_size, 0.0))
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

func _get_preview_box_size() -> Vector3:
	return Vector3(
		maxf(spawn_box_size.x, MIN_PREVIEW_THICKNESS),
		maxf(spawn_box_size.y, MIN_PREVIEW_THICKNESS),
		maxf(spawn_box_size.z, MIN_PREVIEW_THICKNESS)
	)
