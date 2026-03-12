@tool
extends Resource
class_name BiomeDungeonData

@export var biome_id: String = "crypt"

@export_file("*.png", "*.jpg", "*.jpeg", "*.webp", "*.tga", "*.bmp", "*.exr", "*.hdr") var floor_textures: Array[String] = []
@export_file("*.png", "*.jpg", "*.jpeg", "*.webp", "*.tga", "*.bmp", "*.exr", "*.hdr") var wall_textures: Array[String] = []
@export_file("*.png", "*.jpg", "*.jpeg", "*.webp", "*.tga", "*.bmp", "*.exr", "*.hdr") var ceiling_textures: Array[String] = []

@export_file("*.tscn") var door_scene: String = "res://Scenes/World/door.tscn"
@export_file("*.tscn") var doorway_assembly_scene: String = ""
@export var handcrafted_start_room_scene: PackedScene
@export var handcrafted_normal_room_scenes: Array[PackedScene] = []
@export_range(0.0, 1.0, 0.01) var handcrafted_normal_room_chance: float = 0.25

@export var room_light_color: Color = Color(0.9, 0.75, 0.5, 1.0)
@export_file("*.png", "*.jpg", "*.jpeg", "*.webp", "*.tga", "*.bmp", "*.exr", "*.hdr") var room_light_cookie_texture: String = "res://Assets/Effects/cookie_grate.png"
@export var corridor_light_color: Color = Color(1.0, 0.6, 0.2, 1.0)
@export var corridor_light_energy: float = 0.5
@export var corridor_light_range: float = 6.0
@export var corridor_light_height: float = 0.6
@export var corridor_light_step: int = 4
@export var corridor_light_chance: float = 0.3

@export var use_custom_prop_lights: bool = false
@export var custom_light_sources: Array[Dictionary] = []
@export_file("*.tscn") var floor_light_scene: String = ""
@export_file("*.tscn") var wall_light_scene: String = ""

@export var fog_light_color: Color = Color(0.05, 0.03, 0.08, 1.0)
@export_file("*.png", "*.jpg", "*.jpeg", "*.webp", "*.tga", "*.bmp", "*.exr", "*.hdr") var exit_portal_texture: String = "res://Assets/Environment/exit_portal.png"

@export_file("*.png", "*.jpg", "*.jpeg", "*.webp", "*.tga", "*.bmp", "*.exr", "*.hdr") var universal_prop_textures: Array[String] = []
@export_file("*.png", "*.jpg", "*.jpeg", "*.webp", "*.tga", "*.bmp", "*.exr", "*.hdr") var biome_prop_textures: Array[String] = []
@export_file("*.tscn") var universal_prop_scenes: Array[String] = []
@export_file("*.tscn") var biome_prop_scenes: Array[String] = []
@export_file("*.png", "*.jpg", "*.jpeg", "*.webp", "*.tga", "*.bmp", "*.exr", "*.hdr") var crate_texture: String = "res://Assets/Environment/prop_crate.png"
@export_file("*.png", "*.jpg", "*.jpeg", "*.webp", "*.tga", "*.bmp", "*.exr", "*.hdr") var barrel_side_texture: String = "res://Assets/Environment/prop_barrel_side.png"
@export_file("*.png", "*.jpg", "*.jpeg", "*.webp", "*.tga", "*.bmp", "*.exr", "*.hdr") var barrel_top_texture: String = "res://Assets/Environment/prop_barrel_top.png"

@export var enemy_roster: Array[Dictionary] = []
