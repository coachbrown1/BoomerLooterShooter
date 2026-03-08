extends Resource
class_name BiomeDungeonData

@export var biome_id: String = "crypt"

@export var floor_textures: PackedStringArray = PackedStringArray()
@export var wall_textures: PackedStringArray = PackedStringArray()
@export var ceiling_textures: PackedStringArray = PackedStringArray()

@export var door_scene: String = "res://Scenes/World/door.tscn"
@export var doorway_assembly_scene: String = ""

@export var room_light_color: Color = Color(0.9, 0.75, 0.5, 1.0)
@export var room_light_cookie_texture: String = "res://Assets/Effects/cookie_grate.png"
@export var corridor_light_color: Color = Color(1.0, 0.6, 0.2, 1.0)
@export var corridor_light_energy: float = 0.5
@export var corridor_light_range: float = 6.0
@export var corridor_light_height: float = 0.6
@export var corridor_light_step: int = 4
@export var corridor_light_chance: float = 0.3

@export var use_bioluminescent_props_for_room_lights: bool = false
@export var bioluminescent_light_sources: Array[Dictionary] = []
@export var mushroom_scene: String = ""
@export var crystal_scene: String = ""

@export var fog_light_color: Color = Color(0.05, 0.03, 0.08, 1.0)
@export var exit_portal_texture: String = "res://Assets/Environment/exit_portal.png"

@export var universal_prop_textures: PackedStringArray = PackedStringArray()
@export var biome_prop_textures: PackedStringArray = PackedStringArray()
@export var universal_prop_scenes: PackedStringArray = PackedStringArray()
@export var biome_prop_scenes: PackedStringArray = PackedStringArray()
@export var crate_texture: String = "res://Assets/Environment/prop_crate.png"
@export var barrel_side_texture: String = "res://Assets/Environment/prop_barrel_side.png"
@export var barrel_top_texture: String = "res://Assets/Environment/prop_barrel_top.png"

@export var enemy_roster: Array[Dictionary] = []
