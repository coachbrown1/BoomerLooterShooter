@tool
extends Resource
class_name BiomeDungeonDatabase

@export var biomes: Array = []

func get_biome(biome_id: String) -> Resource:
	for biome_data in biomes:
		if biome_data != null and biome_data.biome_id == biome_id:
			return biome_data
	if not biomes.is_empty():
		return biomes[0]
	return null
