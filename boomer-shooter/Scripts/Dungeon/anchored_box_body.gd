@tool
extends StaticBody3D
class_name AnchoredBoxBody

enum AnchorMode {
	MIN,
	CENTER,
	MAX,
}

@export var base_size: Vector3 = Vector3(1.0, 1.0, 1.0):
	set(value):
		base_size = Vector3(maxf(value.x, 0.01), maxf(value.y, 0.01), maxf(value.z, 0.01))
		_rebuild()

@export var anchor_x: AnchorMode = AnchorMode.MIN:
	set(value):
		anchor_x = value
		_rebuild()

@export var anchor_y: AnchorMode = AnchorMode.MIN:
	set(value):
		anchor_y = value
		_rebuild()

@export var anchor_z: AnchorMode = AnchorMode.MIN:
	set(value):
		anchor_z = value
		_rebuild()

@export var material_override: Material:
	set(value):
		material_override = value
		_rebuild()

@onready var _collision: CollisionShape3D = $CollisionShape3D
@onready var _mesh_instance: MeshInstance3D = $MeshInstance3D

func _ready() -> void:
	_ensure_local_resources()
	_rebuild()

func _notification(what: int) -> void:
	if what == NOTIFICATION_LOCAL_TRANSFORM_CHANGED and Engine.is_editor_hint():
		_rebuild()

func _rebuild() -> void:
	if _collision == null or _mesh_instance == null:
		return
	_ensure_local_resources()

	var shape := _collision.shape as BoxShape3D
	if shape == null:
		shape = BoxShape3D.new()
		shape.resource_local_to_scene = true
		_collision.shape = shape
	shape.size = base_size

	var mesh := _mesh_instance.mesh as BoxMesh
	if mesh == null:
		mesh = BoxMesh.new()
		mesh.resource_local_to_scene = true
		_mesh_instance.mesh = mesh
	mesh.size = base_size
	mesh.material = material_override

	var half := base_size * 0.5
	var offset := Vector3(
		_resolve_anchor_offset(half.x, anchor_x),
		_resolve_anchor_offset(half.y, anchor_y),
		_resolve_anchor_offset(half.z, anchor_z)
	)
	_collision.position = offset
	_mesh_instance.position = offset

func _ensure_local_resources() -> void:
	if _collision != null and _collision.shape != null and not _collision.shape.resource_local_to_scene:
		_collision.shape = _collision.shape.duplicate()
		_collision.shape.resource_local_to_scene = true

	if _mesh_instance != null and _mesh_instance.mesh != null and not _mesh_instance.mesh.resource_local_to_scene:
		_mesh_instance.mesh = _mesh_instance.mesh.duplicate()
		_mesh_instance.mesh.resource_local_to_scene = true

func _resolve_anchor_offset(half_extent: float, anchor: AnchorMode) -> float:
	match anchor:
		AnchorMode.CENTER:
			return 0.0
		AnchorMode.MAX:
			return -half_extent
		_:
			return half_extent
