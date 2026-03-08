extends Node3D
class_name DungeonManager

@export var floor_number: int = 1

@onready var nav_region: NavigationRegion3D = $NavigationRegion3D

var _generator: DungeonGenerator
var _builder: DungeonBuilder
var _encounter: EncounterSystem
var _rooms: Array = []

func _ready() -> void:
	generate_floor(floor_number)

func generate_floor(floor_num: int) -> void:
	# Clear old geometry
	for child in nav_region.get_children():
		child.queue_free()

	# Generate tile layout
	_generator = DungeonGenerator.new()
	_generator.generate(floor_num)
	_rooms = _generator.rooms
	
	_update_environment()

	# Build 3D geometry inside the NavigationRegion3D
	_builder = DungeonBuilder.new()
	_builder.build(_generator.tile_grid, _rooms, _generator.corridors, _generator.doorways, nav_region)

	# Place props
	var prop_placer = PropPlacer.new()
	prop_placer.populate(nav_region, _rooms, _generator.tile_grid, _generator.rng)

	# Bake navigation mesh
	var nav_mesh := NavigationMesh.new()
	nav_mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nav_mesh.cell_size = 0.25
	nav_mesh.cell_height = 0.25
	nav_mesh.agent_height = 1.8
	nav_mesh.agent_radius = 0.4
	nav_mesh.agent_max_climb = 0.3
	nav_mesh.filter_walkable_low_height_spans = true
	nav_region.navigation_mesh = nav_mesh

	# Wait a frame for physics to settle before baking
	await get_tree().process_frame
	nav_region.bake_navigation_mesh(false)

	# Spawn enemies in each room
	_encounter = EncounterSystem.new()
	for room in _rooms:
		_encounter.populate_room(room, floor_num, nav_region)

	# Place player at start room
	_place_player()

	# Place exit portal in exit room
	_place_exit()

	print("DungeonManager: Floor %d generated with %d rooms." % [floor_num, _rooms.size()])

func _update_environment() -> void:
	if _rooms.size() == 0:
		return
		
	var env = $WorldEnvironment.environment
	if not env: return
	
	var biome = _rooms[0].biome
	if biome == "crypt":
		env.fog_light_color = Color(0.05, 0.03, 0.08)
	elif biome == "fungal":
		env.fog_light_color = Color(0.02, 0.06, 0.03)
	elif biome == "lava":
		env.fog_light_color = Color(0.08, 0.02, 0.01)

func _place_player() -> void:
	var player = get_tree().get_first_node_in_group("player")
	if not player:
		return
	var start_room: RoomData = null
	for r in _rooms:
		if r.room_type == RoomData.RoomType.START:
			start_room = r
			break
	if start_room:
		var pos = start_room.get_world_center(DungeonBuilder.TILE_SIZE)
		pos.y = 1.0
		player.global_position = pos

func _place_exit() -> void:
	var exit_room: RoomData = null
	for r in _rooms:
		if r.room_type == RoomData.RoomType.EXIT:
			exit_room = r
			break
	if not exit_room:
		return

	# Load and instance the exit portal scene
	var portal_tex = load("res://Assets/Environment/exit_portal.png")
	if not portal_tex:
		return

	var portal_body := Area3D.new()
	portal_body.name = "ExitPortal"
	var col := CollisionShape3D.new()
	col.shape = SphereShape3D.new()
	col.shape.radius = 1.5
	portal_body.add_child(col)

	var sprite := Sprite3D.new()
	sprite.texture = portal_tex
	sprite.pixel_size = 0.006
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	portal_body.add_child(sprite)

	var pos = exit_room.get_world_center(DungeonBuilder.TILE_SIZE)
	pos.y = 1.2
	nav_region.add_child(portal_body)
	portal_body.global_position = pos
	portal_body.body_entered.connect(_on_exit_entered)

func _on_exit_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		floor_number += 1
		print("Descending to floor %d..." % floor_number)
		generate_floor(floor_number)
