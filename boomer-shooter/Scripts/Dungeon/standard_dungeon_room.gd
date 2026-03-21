@tool
extends Node3D
class_name StandardDungeonRoom

## Script for default room scenes used by the DungeonStitcher.
## Each wall has three sub-nodes: _Left, _Right, and _Fill.
## The _Fill segment is the center piece (doorway-width) that gets
## hidden when a doorway is open on that wall.

const WALL_NAMES := ["North", "South", "East", "West"]

@export var room_role_tags: PackedStringArray = ["default"]
@export var supported_doorway_profiles: PackedStringArray = ["*"]
@export var allowed_rotation_degrees: PackedInt32Array = [0]


func get_room_role_tags() -> PackedStringArray:
	return room_role_tags


func get_supported_doorway_profiles() -> PackedStringArray:
	return supported_doorway_profiles


func get_allowed_rotation_degrees() -> PackedInt32Array:
	return allowed_rotation_degrees


func set_doorway_open(wall: String, is_open: bool) -> void:
	var capitalized := wall.capitalize()
	var fill_path := "Walls/Wall%s/Wall%s_Fill" % [capitalized, capitalized]
	var fill_node := get_node_or_null(fill_path)
	if fill_node == null:
		push_warning("StandardDungeonRoom: fill node not found at '%s'" % fill_path)
		return
	fill_node.visible = not is_open
	_set_collision_disabled_recursive(fill_node, is_open)


func configure_doorways(open_walls: Array) -> void:
	for wall_name in WALL_NAMES:
		var wall_lower: String = wall_name.to_lower()
		set_doorway_open(wall_lower, wall_lower in open_walls)


func _set_collision_disabled_recursive(node: Node, disabled: bool) -> void:
	if node is CollisionShape3D:
		(node as CollisionShape3D).disabled = disabled
	for child in node.get_children():
		_set_collision_disabled_recursive(child, disabled)
