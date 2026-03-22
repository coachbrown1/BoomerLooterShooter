@tool
extends Node3D
class_name SmartStairs

const BOX_SCENE: PackedScene = preload("res://Scenes/Dungeon/anchored_box_body.tscn")

const DEFAULT_COLLISION_ANGLE_DEGREES := 25.2590087130155

@export var stair_width: float = 16.0:
	set(value):
		stair_width = maxf(value, 0.1)
		_rebuild()

@export_range(1, 16, 1) var visual_step_count: int = 4:
	set(value):
		visual_step_count = maxi(1, value)
		_rebuild()

@export var total_drop: float = 4.0:
	set(value):
		total_drop = maxf(value, 0.1)
		_rebuild()

@export_range(1.0, 89.0, 0.01, "radians_as_degrees") var collision_angle_degrees: float = DEFAULT_COLLISION_ANGLE_DEGREES:
	set(value):
		collision_angle_degrees = clampf(value, 1.0, 89.0)
		_rebuild()

@export var collision_thickness: float = 0.6:
	set(value):
		collision_thickness = maxf(value, 0.05)
		_rebuild()

@export var material_override: Material:
	set(value):
		material_override = value
		_rebuild()

@onready var _visual_steps: Node3D = $VisualSteps
@onready var _ramp_body: StaticBody3D = $RampCollider
@onready var _ramp_shape_node: CollisionShape3D = $RampCollider/CollisionShape3D

var _is_rebuilding: bool = false


func _ready() -> void:
	_rebuild()


func _notification(what: int) -> void:
	if what == NOTIFICATION_CHILD_ORDER_CHANGED and Engine.is_editor_hint() and not _is_rebuilding:
		_rebuild()


func _rebuild() -> void:
	if _is_rebuilding:
		return
	if _visual_steps == null or _ramp_shape_node == null or _ramp_body == null:
		return
	_is_rebuilding = true
	_rebuild_visual_steps()
	_rebuild_ramp()
	_is_rebuilding = false


func _rebuild_visual_steps() -> void:
	for child in _visual_steps.get_children():
		child.free()

	var step_height := total_drop / float(visual_step_count)
	var horizontal_run := _get_horizontal_run()
	var step_depth := horizontal_run / float(visual_step_count)
	for index in range(visual_step_count):
		var step_variant := BOX_SCENE.instantiate()
		if not (step_variant is AnchoredBoxBody):
			if step_variant is Node:
				(step_variant as Node).free()
			continue
		var step := step_variant as AnchoredBoxBody
		step.name = "Step%02d" % [index + 1]
		step.collision_layer = 0
		step.collision_mask = 0
		step.base_size = Vector3(stair_width, step_height, step_depth)
		step.anchor_x = AnchoredBoxBody.AnchorMode.CENTER
		step.anchor_y = AnchoredBoxBody.AnchorMode.MAX
		step.anchor_z = AnchoredBoxBody.AnchorMode.CENTER
		step.material_override = material_override
		step.position = Vector3(
			0.0,
			-step_height * float(index + 1),
			step_depth * (float(index) + 0.5)
		)
		_visual_steps.add_child(step)
		step.owner = _get_scene_owner()


func _rebuild_ramp() -> void:
	var shape := _ramp_shape_node.shape as BoxShape3D
	if shape == null:
		shape = BoxShape3D.new()
		shape.resource_local_to_scene = true
		_ramp_shape_node.shape = shape

	var angle := deg_to_rad(collision_angle_degrees)
	var ramp_length := total_drop / sin(angle)
	var horizontal_run := total_drop / tan(angle)

	shape.size = Vector3(stair_width, collision_thickness, ramp_length)

	var half_length := ramp_length * 0.5
	var half_thickness := collision_thickness * 0.5
	var center_y := -(half_thickness * cos(angle) + half_length * sin(angle))
	var center_z := (horizontal_run * 0.5) - (half_thickness * sin(angle))

	_ramp_shape_node.position = Vector3(0.0, center_y, center_z)
	_ramp_shape_node.rotation = Vector3(angle, 0.0, 0.0)


func _get_horizontal_run() -> float:
	var angle := deg_to_rad(collision_angle_degrees)
	return total_drop / tan(angle)


func _get_scene_owner() -> Node:
	if Engine.is_editor_hint():
		var tree := get_tree()
		if tree != null and tree.edited_scene_root != null:
			return tree.edited_scene_root
	return self
