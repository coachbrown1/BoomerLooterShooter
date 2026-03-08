extends RefCounted
class_name EncounterSystem

# Threat budget per room = base + (floor * depth_scale) + (area * size_scale)
const THREAT_BASE: float = 3.0
const THREAT_DEPTH_SCALE: float = 2.0
const THREAT_SIZE_SCALE: float = 0.05

# Enemy definitions: { scene, cost, biomes[], min_floor }
const ENEMY_ROSTER: Array = [
	{
		"scene": "res://Scenes/Enemies/enemy_melee.tscn",
		"sprite": "res://Assets/Enemies/Skeleton/skeleton_spritesheet.png",
		"cost": 1.0,
		"biomes": ["crypt"],
		"min_floor": 1,
		"name": "Skeleton",
		"scale": 1.4,
	},
	{
		"scene": "res://Scenes/Enemies/enemy_melee.tscn",
		"sprite": "res://Assets/Enemies/GoblinForward/goblin_forward_spritesheet.png",
		"cost": 1.0,
		"biomes": ["fungal", "crypt"],
		"min_floor": 1,
		"name": "Goblin",
		"scale": 1.15,
		"hframes": 8,
	},
	{
		"scene": "res://Scenes/Enemies/enemy_ranged.tscn",
		"sprite": "res://Assets/Enemies/GoblinArcherForward/goblin_archer_forward_spritesheet.png",
		"cost": 1.5,
		"biomes": ["fungal", "crypt"],
		"min_floor": 1,
		"name": "GoblinArcher",
		"scale": 1.15,
		"hframes": 8,
	},
	{
		"scene": "res://Scenes/Enemies/enemy_melee.tscn",
		"sprite": "res://Assets/Enemies/Kobold/kobold_spritesheet.png",
		"cost": 1.0,
		"biomes": ["lava", "crypt"],
		"min_floor": 1,
		"name": "Kobold",
		"scale": 1.1,
	},
	{
		"scene": "res://Scenes/Enemies/enemy_melee.tscn",
		"sprite": "res://Assets/Enemies/Orc/orc_spritesheet.png",
		"cost": 2.0,
		"biomes": ["fungal", "crypt"],
		"min_floor": 2,
		"name": "Orc",
		"scale": 1.7,
	},
	{
		"scene": "res://Scenes/Enemies/enemy_ranged.tscn",
		"sprite": "res://Assets/Enemies/Cultist/cultist_spritesheet.png",
		"cost": 2.0,
		"biomes": ["crypt"],
		"min_floor": 2,
		"name": "Cultist",
		"scale": 1.4,
	},
	{
		"scene": "res://Scenes/Enemies/enemy_ranged.tscn",
		"sprite": "res://Assets/Enemies/FlamingSkull/flaming_skull_spritesheet.png",
		"cost": 2.0,
		"biomes": ["lava"],
		"min_floor": 2,
		"name": "FlamingSkull",
		"scale": 1.0,
	},
	{
		"scene": "res://Scenes/Enemies/enemy_melee.tscn",
		"sprite": "res://Assets/Enemies/DeathKnight/death_knight_spritesheet.png",
		"cost": 3.0,
		"biomes": ["crypt"],
		"min_floor": 3,
		"name": "DeathKnight",
		"scale": 1.8,
	},
	{
		"scene": "res://Scenes/Enemies/enemy_melee.tscn",
		"sprite": "res://Assets/Enemies/Gargoyle/gargoyle_spritesheet.png",
		"cost": 3.0,
		"biomes": ["crypt", "lava"],
		"min_floor": 3,
		"name": "Gargoyle",
		"scale": 1.5,
	},
	{
		"scene": "res://Scenes/Enemies/enemy_melee.tscn",
		"sprite": "res://Assets/Enemies/FungalCube/fungalcube_spritesheet.png",
		"cost": 3.0,
		"biomes": ["fungal"],
		"min_floor": 3,
		"name": "FungalCube",
		"scale": 2.2,
		"hframes": 8,
	},
	{
		"scene": "res://Scenes/Enemies/enemy_melee.tscn",
		"sprite": "res://Assets/Enemies/SporeHusk/sporehusk_spritesheet.png",
		"cost": 1.5,
		"biomes": ["fungal"],
		"min_floor": 1,
		"name": "SporeHusk",
		"scale": 1.5,
		"hframes": 8,
	},
]

var rng: RandomNumberGenerator

func _init() -> void:
	rng = RandomNumberGenerator.new()
	rng.randomize()

# Populate a room with enemies — returns Array of instanced nodes (not yet added to tree)
func populate_room(room: RoomData, floor_num: int, parent: Node3D, biome_data: Resource = null) -> void:
	# Skip start room
	if room.room_type == RoomData.RoomType.START:
		return

	var room_area: float = room.grid_rect.size.x * room.grid_rect.size.y
	var budget: float = THREAT_BASE + (floor_num * THREAT_DEPTH_SCALE) + (room_area * THREAT_SIZE_SCALE)

	# Exit room gets fewer enemies
	if room.room_type == RoomData.RoomType.EXIT:
		budget = ceil(budget * 0.5)

	# Filter valid enemies for this biome + floor
	var roster: Array = ENEMY_ROSTER
	if _has_biome_data(biome_data) and not biome_data.enemy_roster.is_empty():
		roster = biome_data.enemy_roster

	var valid: Array = []
	for entry in roster:
		if _entry_matches_room(entry, room.biome, floor_num):
			valid.append(entry)

	# Fallback: if no biome match, use anything available for this floor
	if valid.is_empty():
		for entry in roster:
			if floor_num >= int(entry.get("min_floor", 1)):
				valid.append(entry)

	if valid.is_empty():
		return

	# Spend budget
	var scene_cache: Dictionary = {}
	while budget > 0.5:
		var affordable: Array = []
		for entry in valid:
			if entry["cost"] <= budget:
				affordable.append(entry)
		if affordable.is_empty():
			break

		var pick: Dictionary = affordable[rng.randi() % affordable.size()]
		budget -= pick["cost"]

		# Load and instance the scene
		var scene_path: String = pick["scene"]
		if not scene_cache.has(scene_path):
			scene_cache[scene_path] = load(scene_path)
		var packed: PackedScene = scene_cache[scene_path]
		if not packed:
			continue

		var enemy: Node3D = packed.instantiate()

		# Swap the sprite texture and scale BEFORE adding to tree
		var sprite_node := enemy.get_node_or_null("Sprite3D")
		if sprite_node:
			var tex = load(pick["sprite"])
			if tex:
				sprite_node.texture = tex
				if sprite_node.material_override:
					sprite_node.material_override.set_shader_parameter("texture_albedo", tex)
				sprite_node.hframes = pick.get("hframes", 5)
				sprite_node.vframes = 1
				sprite_node.frame = 0
				
				var s = pick.get("scale", 1.0)
				sprite_node.scale = Vector3(s, s, s)

		parent.add_child(enemy)

		# Random position within the room
		var spawn_pos := _random_room_pos(room)
		enemy.global_position = spawn_pos

func _entry_matches_room(entry: Dictionary, room_biome: String, floor_num: int) -> bool:
	if floor_num < int(entry.get("min_floor", 1)):
		return false
	var biomes: Variant = entry.get("biomes", [])
	if typeof(biomes) == TYPE_ARRAY and biomes.size() > 0:
		return room_biome in biomes
	return true

func _has_biome_data(biome_data: Resource) -> bool:
	if biome_data == null:
		return false
	for p in biome_data.get_property_list():
		if typeof(p) == TYPE_DICTIONARY and str(p.get("name", "")) == "enemy_roster":
			return true
	return false

func _random_room_pos(room: RoomData) -> Vector3:
	const TILE_SIZE := 3.0
	const MARGIN := 1  # tile margin from walls

	var rx := room.grid_rect.position.x + MARGIN + rng.randi() % maxi(1, room.grid_rect.size.x - MARGIN * 2)
	var rz := room.grid_rect.position.y + MARGIN + rng.randi() % maxi(1, room.grid_rect.size.y - MARGIN * 2)
	return Vector3(rx * TILE_SIZE + TILE_SIZE/2.0, 0.0, rz * TILE_SIZE + TILE_SIZE/2.0)
