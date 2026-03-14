extends Resource
class_name GearCatalogData

@export var lines: Array[GearLineData] = []

func get_all_items() -> Array[InventoryItemData]:
	var results: Array[InventoryItemData] = []
	for line in lines:
		if line == null:
			continue
		for item in line.variants:
			if item == null:
				continue
			results.append(item)
	return results

func get_items_for_slot(slot_name: StringName) -> Array[InventoryItemData]:
	var results: Array[InventoryItemData] = []
	for item in get_all_items():
		if item == null:
			continue
		if item.equipment_slot == slot_name:
			results.append(item)
	return results

func get_items_for_rarity(rarity: String) -> Array[InventoryItemData]:
	var results: Array[InventoryItemData] = []
	for item in get_all_items():
		if item == null:
			continue
		if String(item.stats.get("rarity", "")) == rarity:
			results.append(item)
	return results
