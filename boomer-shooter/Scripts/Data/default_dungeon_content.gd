@tool
extends Resource
class_name DefaultDungeonContent

@export var start_room_scene: PackedScene
@export var default_room_scene: PackedScene
@export var special_room_scenes: Array[PackedScene] = []
@export_range(0.0, 1.0, 0.01) var special_room_chance: float = 0.25
@export var corridor_scene: PackedScene
@export var doorway_assembly_scene: PackedScene

@export var fog_light_color: Color = Color(0.1, 0.1, 0.15, 1.0)
@export var enemy_scenes: Array[PackedScene] = []
