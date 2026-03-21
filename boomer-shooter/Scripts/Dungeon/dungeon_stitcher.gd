extends RefCounted
class_name DungeonStitcher

const TILE_SIZE: float = 3.0
const DOORWAY_ASSEMBLY_FORWARD_OFFSET: float = 0.35
const FALLBACK_DOOR_SCENE := preload("res://Scenes/World/door.tscn")

var _room_instances := {}	# room_id -> Node3D (room scene instance)
var _corridor_instances := []	# Array of Node3D (corridor scene instances)
var _room_lookup := {}		# room_id -> RoomData


func stitch(
	rooms: Array,
	corridors: Array,
	doorways: Array,
	parent: Node3D,
	dungeon_content: Resource
) -> void:
	_room_lookup.clear()
	_room_instances.clear()
	_corridor_instances.clear()

	for room_variant in rooms:
		var room: RoomData = room_variant
		_room_lookup[room.id] = room

	_stitch_rooms(rooms, parent)
	_stitch_corridors(corridors, parent, dungeon_content)
	_stitch_doorways(doorways, parent, dungeon_content)


func get_room_instance(room_id: int) -> Node3D:
	return _room_instances.get(room_id, null)


func get_room_instances() -> Dictionary:
	return _room_instances


# -------------------------------------------------------
# Rooms
# -------------------------------------------------------
func _stitch_rooms(rooms: Array, parent: Node3D) -> void:
	var rooms_container := Node3D.new()
	rooms_container.name = "DungeonRooms"
	parent.add_child(rooms_container)

	for room_variant in rooms:
		var room: RoomData = room_variant
		var scene: PackedScene = room.assigned_scene
		if scene == null:
			push_warning("DungeonStitcher: no scene for room %d" % room.id)
			continue

		var instance := scene.instantiate()
		if not (instance is Node3D):
			if instance is Node:
				(instance as Node).queue_free()
			push_warning("DungeonStitcher: room scene for room %d is not a Node3D." % room.id)
			continue
		var world_center := room.get_world_center(TILE_SIZE)
		instance.rotation_degrees.y = float(room.chosen_rotation_degrees)
		instance.position = world_center + _get_room_stitch_offset(instance, room)

		rooms_container.add_child(instance)
		_room_instances[room.id] = instance

		# Configure doorway openings
		_configure_room_doorways(instance, room)


func _configure_room_doorways(instance: Node3D, room: RoomData) -> void:
	if instance == null:
		return
	if not _should_configure_runtime_doorways(instance):
		return
	if instance.has_method("configure_doorways"):
		instance.call("configure_doorways", room.doorway_walls)
	else:
		# Fallback: try individual set_doorway_open calls
		if instance.has_method("set_doorway_open"):
			var all_walls := ["north", "south", "east", "west"]
			for wall in all_walls:
				instance.call("set_doorway_open", wall, wall in room.doorway_walls)


func _should_configure_runtime_doorways(instance: Node3D) -> bool:
	if instance is StandardDungeonRoom:
		return true
	if instance.has_method("supports_runtime_doorway_configuration"):
		return bool(instance.call("supports_runtime_doorway_configuration"))
	return instance.has_method("configure_doorways") or instance.has_method("set_doorway_open")


func _get_room_stitch_offset(instance: Node3D, room: RoomData) -> Vector3:
	if room == null or room.assigned_scene_role != "start":
		return Vector3.ZERO
	if room.doorway_walls.size() != 1:
		return Vector3.ZERO

	var bounds := _compute_node_bounds(instance)
	if not bool(bounds.get("valid", false)):
		return Vector3.ZERO

	var open_wall := String(room.doorway_walls[0]).to_lower()
	var cell_half_extents := Vector2(
		float(room.grid_rect.size.x) * TILE_SIZE * 0.5,
		float(room.grid_rect.size.y) * TILE_SIZE * 0.5
	)

	match open_wall:
		"north":
			var north_extent := absf(float(bounds.get("min_z", 0.0)))
			return Vector3(0.0, 0.0, -maxf(0.0, cell_half_extents.y - north_extent))
		"south":
			var south_extent := float(bounds.get("max_z", 0.0))
			return Vector3(0.0, 0.0, maxf(0.0, cell_half_extents.y - south_extent))
		"west":
			var west_extent := absf(float(bounds.get("min_x", 0.0)))
			return Vector3(-maxf(0.0, cell_half_extents.x - west_extent), 0.0, 0.0)
		"east":
			var east_extent := float(bounds.get("max_x", 0.0))
			return Vector3(maxf(0.0, cell_half_extents.x - east_extent), 0.0, 0.0)
		_:
			return Vector3.ZERO


func _compute_node_bounds(root: Node3D) -> Dictionary:
	var bounds := {
		"valid": false,
		"min_x": 0.0,
		"max_x": 0.0,
		"min_z": 0.0,
		"max_z": 0.0,
	}
	if root == null:
		return bounds

	_accumulate_node_bounds(root, root.transform, bounds)
	return bounds


func _accumulate_node_bounds(node: Node, accumulated_transform: Transform3D, bounds: Dictionary) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh != null:
			_include_transformed_aabb(mesh_instance.mesh.get_aabb(), accumulated_transform, bounds)

	for child in node.get_children():
		if not (child is Node3D):
			continue
		var child_node := child as Node3D
		_accumulate_node_bounds(child_node, accumulated_transform * child_node.transform, bounds)


func _include_transformed_aabb(aabb: AABB, transform: Transform3D, bounds: Dictionary) -> void:
	for corner in _get_aabb_corners(aabb):
		var point := transform * corner
		_include_bound_point(point, bounds)


func _get_aabb_corners(aabb: AABB) -> Array[Vector3]:
	var position := aabb.position
	var size := aabb.size
	return [
		position,
		position + Vector3(size.x, 0.0, 0.0),
		position + Vector3(0.0, size.y, 0.0),
		position + Vector3(0.0, 0.0, size.z),
		position + Vector3(size.x, size.y, 0.0),
		position + Vector3(size.x, 0.0, size.z),
		position + Vector3(0.0, size.y, size.z),
		position + size,
	]


func _include_bound_point(point: Vector3, bounds: Dictionary) -> void:
	if not bool(bounds.get("valid", false)):
		bounds["valid"] = true
		bounds["min_x"] = point.x
		bounds["max_x"] = point.x
		bounds["min_z"] = point.z
		bounds["max_z"] = point.z
		return

	bounds["min_x"] = minf(float(bounds["min_x"]), point.x)
	bounds["max_x"] = maxf(float(bounds["max_x"]), point.x)
	bounds["min_z"] = minf(float(bounds["min_z"]), point.z)
	bounds["max_z"] = maxf(float(bounds["max_z"]), point.z)


# -------------------------------------------------------
# Corridors
# -------------------------------------------------------
func _stitch_corridors(corridors: Array, parent: Node3D, dungeon_content: Resource) -> void:
	var corridor_scene: PackedScene = null
	if dungeon_content != null:
		corridor_scene = _get_resource_packed_scene(dungeon_content, "corridor_scene")

	if corridor_scene == null:
		push_warning("DungeonStitcher: no corridor scene in default dungeon content")
		return

	var corridors_container := Node3D.new()
	corridors_container.name = "DungeonCorridors"
	parent.add_child(corridors_container)

	for corridor_variant in corridors:
		var corridor: Dictionary = corridor_variant
		var room_a_id: int = corridor.get("room_a_id", -1)
		var room_b_id: int = corridor.get("room_b_id", -1)
		var room_a: RoomData = _room_lookup.get(room_a_id, null)
		var room_b: RoomData = _room_lookup.get(room_b_id, null)
		if room_a == null or room_b == null:
			continue

		var center_a := room_a.get_world_center(TILE_SIZE)
		var center_b := room_b.get_world_center(TILE_SIZE)
		var midpoint := (center_a + center_b) / 2.0

		var instance := corridor_scene.instantiate()
		instance.position = midpoint

		# Determine corridor direction and rotate if east-west
		var delta := room_b.lattice_coord - room_a.lattice_coord
		if abs(delta.x) > 0 and delta.y == 0:
			# East-west corridor: rotate 90 degrees
			instance.rotation_degrees.y = 90.0

		corridors_container.add_child(instance)
		_corridor_instances.append(instance)


# -------------------------------------------------------
# Doorways
# -------------------------------------------------------
func _stitch_doorways(doorways: Array, parent: Node3D, dungeon_content: Resource) -> void:
	var doorway_scene := _get_resource_packed_scene(dungeon_content, "doorway_assembly_scene")
	if doorway_scene == null:
		doorway_scene = FALLBACK_DOOR_SCENE

	if doorway_scene == null:
		push_warning("DungeonStitcher: no doorway scene available")
		return

	var doorway_container := Node3D.new()
	doorway_container.name = "DungeonDoorways"
	parent.add_child(doorway_container)

	for doorway_variant in doorways:
		if typeof(doorway_variant) != TYPE_DICTIONARY:
			continue
		var doorway: Dictionary = doorway_variant
		if not doorway.has("tile"):
			continue

		var orientation := _get_doorway_orientation(doorway)
		if orientation == "":
			continue

		var tile: Vector2i = doorway.get("tile", Vector2i.ZERO)
		var center_offset_tiles := float(doorway.get("opening_center_offset_tiles", 0.0))
		var outward_normal := _get_generated_doorway_wall_normal(doorway)
		var wx := tile.x * TILE_SIZE + TILE_SIZE / 2.0
		var wz := tile.y * TILE_SIZE + TILE_SIZE / 2.0
		if orientation == "east_west":
			wx += center_offset_tiles * TILE_SIZE
		else:
			wz += center_offset_tiles * TILE_SIZE

		var doorway_instance := doorway_scene.instantiate()
		if not (doorway_instance is Node3D):
			if doorway_instance is Node:
				(doorway_instance as Node).queue_free()
			continue
		(doorway_instance as Node3D).position = Vector3(wx, 0.0, wz) + outward_normal * DOORWAY_ASSEMBLY_FORWARD_OFFSET
		if orientation == "north_south":
			(doorway_instance as Node3D).rotation_degrees.y = 90.0
		doorway_container.add_child(doorway_instance)


func _get_generated_doorway_wall_normal(doorway: Dictionary) -> Vector3:
	var room_id := int(doorway.get("room_id", -1))
	var room: RoomData = _room_lookup.get(room_id, null)
	if room == null:
		return Vector3.ZERO
	var tile: Vector2i = doorway.get("tile", Vector2i(-1, -1))
	var rect: Rect2i = room.grid_rect
	if tile.x == rect.position.x:
		return Vector3(-1, 0, 0)
	if tile.x == rect.position.x + rect.size.x - 1:
		return Vector3(1, 0, 0)
	if tile.y == rect.position.y:
		return Vector3(0, 0, -1)
	if tile.y == rect.position.y + rect.size.y - 1:
		return Vector3(0, 0, 1)
	return Vector3.ZERO


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


func _get_resource_packed_scene(resource: Resource, property_name: String) -> PackedScene:
	if resource == null:
		return null
	for property_variant in resource.get_property_list():
		if typeof(property_variant) != TYPE_DICTIONARY:
			continue
		if str(property_variant.get("name", "")) != property_name:
			continue
		var value: Variant = resource.get(property_name)
		if value is PackedScene:
			return value
		return null
	return null
