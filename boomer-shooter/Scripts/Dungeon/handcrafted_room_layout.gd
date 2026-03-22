@tool
extends Node3D
class_name HandcraftedRoomLayout

@export_group("Doorway Profiles")
## Check each wall that has a physical doorway opening in this room's geometry.
## The dungeon manager uses these to match the room against its required connections.
@export var doorway_north: bool = false:
	set(v):
		doorway_north = v
		_refresh_doorway_preview()
@export var doorway_south: bool = false:
	set(v):
		doorway_south = v
		_refresh_doorway_preview()
@export var doorway_east: bool = false:
	set(v):
		doorway_east = v
		_refresh_doorway_preview()
@export var doorway_west: bool = false:
	set(v):
		doorway_west = v
		_refresh_doorway_preview()
## Enable to accept any doorway combination at runtime. Requires all four
## Wall*_Fill nodes to be present so doorways can be toggled open/closed.
@export var doorway_wildcard: bool = false:
	set(v):
		doorway_wildcard = v
		_refresh_doorway_preview()

@export_group("Room")
@export var room_role_tags: PackedStringArray = []
@export var allowed_rotation_degrees: PackedInt32Array = [0, 90, 180, 270]

@export_group("Tooling")
@export_tool_button("Validate Doorways") var _btn_validate: Callable = _validate_doorways
@export_tool_button("Create Missing Fill Nodes") var _btn_create: Callable = _create_fill_nodes


func _ready() -> void:
	if Engine.is_editor_hint():
		_refresh_doorway_preview()


func prepare_runtime_layout() -> void:
	pass


func get_room_role_tags() -> PackedStringArray:
	return room_role_tags


func get_supported_doorway_profiles() -> PackedStringArray:
	if doorway_wildcard:
		return PackedStringArray(["*"])
	var walls: Array[String] = []
	if doorway_north: walls.append("north")
	if doorway_south: walls.append("south")
	if doorway_east:  walls.append("east")
	if doorway_west:  walls.append("west")
	if walls.is_empty():
		return PackedStringArray()
	return PackedStringArray([",".join(walls)])


func get_allowed_rotation_degrees() -> PackedInt32Array:
	return allowed_rotation_degrees


func set_doorway_open(wall: String, is_open: bool) -> void:
	var capitalized := wall.capitalize()
	var fill_path := "Walls/Wall%s/Wall%s_Fill" % [capitalized, capitalized]
	var fill_node := get_node_or_null(fill_path)
	if fill_node == null:
		return
	fill_node.visible = not is_open
	_set_collision_disabled_recursive(fill_node, is_open)


func configure_doorways(open_walls: Array) -> void:
	for wall_name in ["North", "South", "East", "West"]:
		var wall_lower: String = wall_name.to_lower()
		set_doorway_open(wall_lower, wall_lower in open_walls)


func supports_runtime_doorway_configuration() -> bool:
	return _has_doorway_fill_nodes()


# --- Editor tooling ---

func _refresh_doorway_preview() -> void:
	if not Engine.is_editor_hint():
		return
	if not is_inside_tree():
		return
	if doorway_wildcard:
		# Wildcard mode: show all walls closed so geometry is fully visible while editing.
		for wall_name in ["north", "south", "east", "west"]:
			set_doorway_open(wall_name, false)
		return
	set_doorway_open("north", doorway_north)
	set_doorway_open("south", doorway_south)
	set_doorway_open("east",  doorway_east)
	set_doorway_open("west",  doorway_west)


func _validate_doorways() -> void:
	var issues: Array[String] = []

	if get_node_or_null("Walls") == null:
		issues.append("Missing 'Walls' Node3D — needed for fill node lookup")
	else:
		for wall_name in ["North", "South", "East", "West"]:
			var path := "Walls/Wall%s/Wall%s_Fill" % [wall_name, wall_name]
			if get_node_or_null(path) == null:
				issues.append("Missing fill node: %s" % path)

	var profiles := get_supported_doorway_profiles()
	if profiles.is_empty():
		issues.append("No doorway profiles declared — dungeon manager will reject this room")

	if doorway_wildcard and not _has_doorway_fill_nodes():
		issues.append("Wildcard profile requires all four fill nodes (use 'Create Missing Fill Nodes')")

	if issues.is_empty():
		print("[HandcraftedRoomLayout] %s: OK  profiles=%s  fill_nodes=%s" % [
			name, str(Array(profiles)), str(_has_doorway_fill_nodes())])
	else:
		print("[HandcraftedRoomLayout] %s: %d issue(s):" % [name, issues.size()])
		for issue in issues:
			push_warning("[HandcraftedRoomLayout] %s — %s" % [name, issue])


func _create_fill_nodes() -> void:
	if not Engine.is_editor_hint():
		return
	var scene_root := get_tree().edited_scene_root
	var created := 0

	var walls_node := get_node_or_null("Walls")
	if walls_node == null:
		walls_node = Node3D.new()
		walls_node.name = "Walls"
		add_child(walls_node)
		walls_node.owner = scene_root
		created += 1
		print("[HandcraftedRoomLayout] Created 'Walls'")

	for wall_name in ["North", "South", "East", "West"]:
		var group_path := "Walls/Wall%s" % wall_name
		var wall_group := get_node_or_null(group_path)
		if wall_group == null:
			wall_group = Node3D.new()
			wall_group.name = "Wall%s" % wall_name
			walls_node.add_child(wall_group)
			wall_group.owner = scene_root
			created += 1
			print("[HandcraftedRoomLayout] Created '%s'" % group_path)

		var fill_path := "Walls/Wall%s/Wall%s_Fill" % [wall_name, wall_name]
		if get_node_or_null(fill_path) == null:
			var fill_node := Node3D.new()
			fill_node.name = "Wall%s_Fill" % wall_name
			wall_group.add_child(fill_node)
			fill_node.owner = scene_root
			created += 1
			print("[HandcraftedRoomLayout] Created '%s'  ← replace with fill geometry" % fill_path)

	if created == 0:
		print("[HandcraftedRoomLayout] %s: all fill nodes already present" % name)
	else:
		print("[HandcraftedRoomLayout] %s: created %d node(s) — add doorway fill geometry to Wall*_Fill nodes" % [name, created])


# --- Internals ---

func _set_collision_disabled_recursive(node: Node, disabled: bool) -> void:
	if node is CollisionShape3D:
		(node as CollisionShape3D).disabled = disabled
	for child in node.get_children():
		_set_collision_disabled_recursive(child, disabled)


func _has_shell_layout() -> bool:
	return get_node_or_null("ShellFloor") != null \
		and get_node_or_null("ShellCeiling") != null \
		and get_node_or_null("Walls") != null


func _has_doorway_fill_nodes() -> bool:
	for wall_name in ["North", "South", "East", "West"]:
		var fill_path := "Walls/Wall%s/Wall%s_Fill" % [wall_name, wall_name]
		if get_node_or_null(fill_path) == null:
			return false
	return true
