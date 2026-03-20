@tool
extends Resource
class_name BiomeDungeonData

@export var biome_id: String = "crypt"

@export var floor_textures: Array = []
@export var wall_textures: Array = []
@export var ceiling_textures: Array = []

@export_group("Tile Material Settings")
@export var tile_emission_color: Color = Color(0, 0, 0, 1)
@export var tile_emission_energy: float = 0.05
@export var tile_emission_operator: StandardMaterial3D.EmissionOperator = StandardMaterial3D.EMISSION_OP_MULTIPLY
@export var tile_uv_scale: float = 2.0
@export var tile_texture_filter: BaseMaterial3D.TextureFilter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
@export var tile_use_world_triplanar: bool = true
@export var wall_uv_scale: Vector3 = Vector3(10.0, 3.0, 2.0)
@export var wall_use_world_triplanar: bool = false

@export var door_scene: PackedScene = preload("res://Scenes/World/door.tscn")
@export var doorway_assembly_scene: PackedScene
@export var doorway_support_material: Material
@export var handcrafted_start_room_scene: PackedScene
@export var handcrafted_normal_room_scenes: Array[PackedScene] = []
@export var handcrafted_quadrant_room_scenes: Array[PackedScene] = []
@export_range(0.0, 1.0, 0.01) var handcrafted_normal_room_chance: float = 0.25

@export var room_light_color: Color = Color(0.9, 0.75, 0.5, 1.0)
@export var room_light_cookie_texture: Texture2D = preload("res://Assets/Effects/cookie_grate.png")
@export var corridor_light_color: Color = Color(1.0, 0.6, 0.2, 1.0)
@export var corridor_light_energy: float = 0.5
@export var corridor_light_range: float = 6.0
@export var corridor_light_height: float = 0.6
@export var corridor_light_step: int = 4
@export var corridor_light_chance: float = 0.3

@export var use_prop_lights: bool = false
@export var wall_light_scene: PackedScene
@export var wall_light_color: Color = Color(0.5, 0.4, 1.0, 1.0)
@export var wall_light_energy: float = 2.5
@export var wall_light_range: float = 12.0
@export var wall_light_height: float = 0.8
@export var floor_light_scene: PackedScene
@export var floor_light_color: Color = Color(0.3, 1.0, 0.6, 1.0)
@export var floor_light_energy: float = 1.8
@export var floor_light_range: float = 9.0
@export var floor_light_height: float = 0.9

@export var fog_light_color: Color = Color(0.05, 0.03, 0.08, 1.0)
@export var exit_portal_texture: Texture2D = preload("res://Assets/Environment/exit_portal.png")

@export var universal_prop_scenes: Array = []
@export var biome_prop_scenes: Array = []

@export var enemy_scenes: Array = []
