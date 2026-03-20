@tool
extends HandcraftedRoomLayout
class_name HandcraftedQuadrantCompositeRoom

const ROOM_SIZE_TILES := 20
const TILE_SIZE := 3.0
const ROOM_HALF_EXTENT := ROOM_SIZE_TILES * TILE_SIZE * 0.5
const CROSS_HALF_WIDTH := TILE_SIZE
const QUADRANT_CENTER_OFFSET := 16.5
const GUIDE_EDGE_THICKNESS := 0.25
const GUIDE_HEIGHT := 0.2
const GUIDE_CROSS_HEIGHT := 0.12

const QUADRANT_ROTATIONS := {
	"NWAnchor": 0.0,
	"NEAnchor": -90.0,
	"SEAnchor": 180.0,
	"SWAnchor": 90.0,
}
const QUADRANT_ORDER: Array[String] = ["NWAnchor", "NEAnchor", "SWAnchor", "SEAnchor"]
const QUADRANT_ANCHOR_POSITIONS := {
	"NWAnchor": Vector3(-QUADRANT_CENTER_OFFSET, 0.0, -QUADRANT_CENTER_OFFSET),
	"NEAnchor": Vector3(QUADRANT_CENTER_OFFSET, 0.0, -QUADRANT_CENTER_OFFSET),
	"SWAnchor": Vector3(-QUADRANT_CENTER_OFFSET, 0.0, QUADRANT_CENTER_OFFSET),
	"SEAnchor": Vector3(QUADRANT_CENTER_OFFSET, 0.0, QUADRANT_CENTER_OFFSET),
}

@export var wall_tile_scene: PackedScene
@export var wall_material_override: Material
@export var torch_scene: PackedScene
@export var show_room_guides: bool = true
@export var wall_height: float = 12.0
@export var wall_thickness: float = 0.4
@export var wall_uv_scale: Vector3 = Vector3(10.0, 3.0, 2.0)

var _quadrants_populated: bool = false
var _layout_built: bool = false

func _ready() -> void:
	_ensure_layout()

func populate_quadrants(quadrant_scene_pool: Array[PackedScene], rng: RandomNumberGenerator) -> void:
	_ensure_layout()
	if _quadrants_populated:
		return
	if quadrant_scene_pool.is_empty():
		push_warning("%s: handcrafted quadrant pool is empty." % name)
		return
	if rng == null:
		push_warning("%s: cannot populate handcrafted quadrants without an RNG." % name)
		return
	var quadrants_root := get_node_or_null("Quadrants")
	if not (quadrants_root is Node3D):
		push_warning("%s: missing Quadrants root." % name)
		return

	for anchor_name in QUADRANT_ORDER:
		var anchor := quadrants_root.get_node_or_null(anchor_name) as Node3D
		if anchor == null:
			push_warning("%s: missing quadrant anchor '%s'." % [name, anchor_name])
			continue
		_clear_anchor(anchor)
		var scene: PackedScene = quadrant_scene_pool[rng.randi() % quadrant_scene_pool.size()]
		var module_variant: Variant = scene.instantiate()
		if not (module_variant is Node3D):
			if module_variant is Node:
				var cleanup: Node = module_variant
				cleanup.free()
			push_warning("%s: quadrant scene '%s' is not a Node3D root." % [name, scene.resource_path])
			continue
		var module: Node3D = module_variant
		module.name = "QuadrantModule"
		module.rotation_degrees.y = QUADRANT_ROTATIONS[anchor_name]
		module.set_meta("quadrant_scene_path", scene.resource_path)
		anchor.add_child(module)
		anchor.set_meta("quadrant_scene_path", scene.resource_path)

	_quadrants_populated = true

func _ensure_layout() -> void:
	if _layout_built:
		return
	_rebuild_layout()

func _rebuild_layout() -> void:
	_remove_generated_child("ShellGenerated")
	_remove_generated_child("Quadrants")
	_remove_generated_child("RoomBoundsDebug")

	var shell := Node3D.new()
	shell.name = "ShellGenerated"
	add_child(shell)
	shell.owner = self if Engine.is_editor_hint() else null

	_build_outer_walls(shell)
	_build_torches(shell)
	_build_quadrant_anchors()
	if Engine.is_editor_hint() and show_room_guides:
		_build_room_guides()

	_layout_built = true

func _build_outer_walls(parent: Node3D) -> void:
	var segment_length := ROOM_HALF_EXTENT - CROSS_HALF_WIDTH
	var segment_offset := (ROOM_HALF_EXTENT + CROSS_HALF_WIDTH) * 0.5
	var wall_material := _make_wall_material()

	_add_wall_segment(
		parent,
		Vector3(segment_offset, wall_height * 0.5, -ROOM_HALF_EXTENT),
		Vector3(segment_length, wall_height, wall_thickness),
		wall_material
	)
	_add_wall_segment(
		parent,
		Vector3(-segment_offset, wall_height * 0.5, -ROOM_HALF_EXTENT),
		Vector3(segment_length, wall_height, wall_thickness),
		wall_material
	)
	_add_wall_segment(
		parent,
		Vector3(segment_offset, wall_height * 0.5, ROOM_HALF_EXTENT),
		Vector3(segment_length, wall_height, wall_thickness),
		wall_material
	)
	_add_wall_segment(
		parent,
		Vector3(-segment_offset, wall_height * 0.5, ROOM_HALF_EXTENT),
		Vector3(segment_length, wall_height, wall_thickness),
		wall_material
	)
	_add_wall_segment(
		parent,
		Vector3(-ROOM_HALF_EXTENT, wall_height * 0.5, segment_offset),
		Vector3(wall_thickness, wall_height, segment_length),
		wall_material
	)
	_add_wall_segment(
		parent,
		Vector3(-ROOM_HALF_EXTENT, wall_height * 0.5, -segment_offset),
		Vector3(wall_thickness, wall_height, segment_length),
		wall_material
	)
	_add_wall_segment(
		parent,
		Vector3(ROOM_HALF_EXTENT, wall_height * 0.5, segment_offset),
		Vector3(wall_thickness, wall_height, segment_length),
		wall_material
	)
	_add_wall_segment(
		parent,
		Vector3(ROOM_HALF_EXTENT, wall_height * 0.5, -segment_offset),
		Vector3(wall_thickness, wall_height, segment_length),
		wall_material
	)

func _build_torches(parent: Node3D) -> void:
	if torch_scene == null:
		return
	_add_torch(parent, Vector3(-9.0, 0.0, -ROOM_HALF_EXTENT + 0.4), 180.0)
	_add_torch(parent, Vector3(9.0, 0.0, -ROOM_HALF_EXTENT + 0.4), 180.0)
	_add_torch(parent, Vector3(-9.0, 0.0, ROOM_HALF_EXTENT - 0.4), 0.0)
	_add_torch(parent, Vector3(9.0, 0.0, ROOM_HALF_EXTENT - 0.4), 0.0)

func _build_quadrant_anchors() -> void:
	var quadrants := Node3D.new()
	quadrants.name = "Quadrants"
	add_child(quadrants)
	quadrants.owner = self if Engine.is_editor_hint() else null

	for anchor_name in QUADRANT_ORDER:
		var anchor := Node3D.new()
		anchor.name = anchor_name
		anchor.position = QUADRANT_ANCHOR_POSITIONS[anchor_name]
		quadrants.add_child(anchor)
		anchor.owner = self if Engine.is_editor_hint() else null

func _build_room_guides() -> void:
	var debug_root := Node3D.new()
	debug_root.name = "RoomBoundsDebug"
	add_child(debug_root)
	debug_root.owner = self if Engine.is_editor_hint() else null

	var guide_material := StandardMaterial3D.new()
	guide_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	guide_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	guide_material.albedo_color = Color(0.8, 0.7, 0.45, 0.55)

	_add_guide_mesh(debug_root, Vector3(ROOM_SIZE_TILES * TILE_SIZE, GUIDE_HEIGHT, GUIDE_EDGE_THICKNESS), Vector3(0.0, 0.1, -ROOM_HALF_EXTENT), guide_material)
	_add_guide_mesh(debug_root, Vector3(ROOM_SIZE_TILES * TILE_SIZE, GUIDE_HEIGHT, GUIDE_EDGE_THICKNESS), Vector3(0.0, 0.1, ROOM_HALF_EXTENT), guide_material)
	_add_guide_mesh(debug_root, Vector3(GUIDE_EDGE_THICKNESS, GUIDE_HEIGHT, ROOM_SIZE_TILES * TILE_SIZE), Vector3(-ROOM_HALF_EXTENT, 0.1, 0.0), guide_material)
	_add_guide_mesh(debug_root, Vector3(GUIDE_EDGE_THICKNESS, GUIDE_HEIGHT, ROOM_SIZE_TILES * TILE_SIZE), Vector3(ROOM_HALF_EXTENT, 0.1, 0.0), guide_material)
	_add_guide_mesh(debug_root, Vector3(CROSS_HALF_WIDTH * 2.0, GUIDE_CROSS_HEIGHT, ROOM_SIZE_TILES * TILE_SIZE), Vector3.ZERO + Vector3(0.0, 0.08, 0.0), guide_material)
	_add_guide_mesh(debug_root, Vector3(ROOM_SIZE_TILES * TILE_SIZE, GUIDE_CROSS_HEIGHT, CROSS_HALF_WIDTH * 2.0), Vector3.ZERO + Vector3(0.0, 0.08, 0.0), guide_material)

func _add_wall_segment(parent: Node3D, position: Vector3, size: Vector3, material: Material) -> void:
	var wall := StaticBody3D.new()
	wall.position = position

	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collider.shape = shape
	wall.add_child(collider)
	collider.owner = self if Engine.is_editor_hint() else null

	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	mesh_instance.mesh = mesh
	wall.add_child(mesh_instance)
	mesh_instance.owner = self if Engine.is_editor_hint() else null

	parent.add_child(wall)
	wall.owner = self if Engine.is_editor_hint() else null

func _make_wall_material() -> Material:
	var base_material := wall_material_override
	if base_material == null:
		base_material = _extract_wall_tile_material()
	if base_material is StandardMaterial3D:
		var tuned := (base_material as StandardMaterial3D).duplicate() as StandardMaterial3D
		tuned.uv1_scale = wall_uv_scale
		tuned.uv1_triplanar = false
		tuned.uv1_world_triplanar = false
		return tuned
	return base_material

func _extract_wall_tile_material() -> Material:
	if wall_tile_scene == null:
		return null
	var wall_variant: Variant = wall_tile_scene.instantiate()
	if not (wall_variant is Node3D):
		if wall_variant is Node:
			var cleanup: Node = wall_variant
			cleanup.free()
		return null
	var wall: Node3D = wall_variant
	var mesh_instance := wall.get_node_or_null("MeshInstance3D") as MeshInstance3D
	var material: Material = null
	if mesh_instance != null:
		if mesh_instance.material_override != null:
			material = mesh_instance.material_override
		elif mesh_instance.mesh != null:
			material = mesh_instance.mesh.surface_get_material(0)
	wall.free()
	return material

func _add_torch(parent: Node3D, position: Vector3, rotation_y: float) -> void:
	var torch_variant: Variant = torch_scene.instantiate()
	if not (torch_variant is Node3D):
		if torch_variant is Node:
			var cleanup: Node = torch_variant
			cleanup.free()
		return
	var torch: Node3D = torch_variant
	torch.position = position
	torch.rotation_degrees.y = rotation_y
	parent.add_child(torch)
	torch.owner = self if Engine.is_editor_hint() else null

func _add_guide_mesh(parent: Node3D, size: Vector3, position: Vector3, material: StandardMaterial3D) -> void:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh_instance.position = position
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	mesh_instance.mesh = mesh
	parent.add_child(mesh_instance)
	mesh_instance.owner = self if Engine.is_editor_hint() else null

func _remove_generated_child(child_name: String) -> void:
	var node := get_node_or_null(child_name)
	if node != null:
		node.free()

func _clear_anchor(anchor: Node3D) -> void:
	for child in anchor.get_children():
		child.free()
