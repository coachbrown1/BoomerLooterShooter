extends Resource
class_name GearLineData

@export var slot_name: StringName = &""
@export var piece_name: String = ""
@export_multiline var build_theme: String = ""
@export var variants: Array[InventoryItemData] = []

func get_variant_by_rarity(rarity: String) -> InventoryItemData:
	for item in variants:
		if item == null:
			continue
		if String(item.stats.get("rarity", "")) == rarity:
			return item
	return null
