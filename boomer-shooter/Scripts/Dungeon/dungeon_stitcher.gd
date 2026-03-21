extends RefCounted
class_name DungeonStitcher

const TILE_SIZE: float = 3.0

var _room_instances := {}	# room_id -> Node3D (room scene instance)
var _corridor_instances := []	# Array of Node3D (corridor scene instances)
var _room_lookup := {}		# room_id -> RoomData


func stitch(
	rooms: Array,
	corridors: Array,
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
		instance.position = world_center
		instance.rotation_degrees.y = float(room.chosen_rotation_degrees)

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


# -------------------------------------------------------
# Corridors
# -------------------------------------------------------
func _stitch_corridors(corridors: Array, parent: Node3D, dungeon_content: Resource) -> void:
	var corridor_scene: PackedScene = null
	if dungeon_content != null:
		var scene_candidate: Variant = dungeon_content.get("corridor_scene")
		if scene_candidate is PackedScene:
			corridor_scene = scene_candidate

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
