extends Resource
class_name GearCatalogData

@export var lines: Array[GearLineData] = []

func get_all_items() -> Array[InventoryItemData]:
	var results: Array[InventoryItemData] = []
	for line in lines:
		if line == null:
			continue
		for item in line.get_variants():
			_apply_defaults_to_item(item)
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

func create_item_by_id(item_id: StringName) -> InventoryItemData:
	for item in get_all_items():
		if item == null:
			continue
		if item.item_id == item_id:
			return item.duplicate(true) as InventoryItemData
	return null

func create_random_items(count: int, seed: int) -> Array[InventoryItemData]:
	var pool: Array[InventoryItemData] = get_all_items()
	var results: Array[InventoryItemData] = []
	if count <= 0 or pool.is_empty():
		return results

	var rng := RandomNumberGenerator.new()
	rng.seed = seed

	while results.size() < count and not pool.is_empty():
		var total_weight := 0.0
		for item in pool:
			total_weight += _get_rarity_weight(String(item.stats.get("rarity", "")))

		var roll := rng.randf_range(0.0, total_weight)
		var chosen_index := 0
		var running := 0.0
		for i in range(pool.size()):
			running += _get_rarity_weight(String(pool[i].stats.get("rarity", "")))
			if roll <= running:
				chosen_index = i
				break

		results.append(pool[chosen_index].duplicate(true) as InventoryItemData)
		pool.remove_at(chosen_index)

	return results

func _apply_defaults_to_item(item: InventoryItemData) -> void:
	if item == null:
		return
	var icon_path := _get_icon_path_for_item(item)
	if icon_path.is_empty():
		return
	if item.item_icon_path.is_empty():
		item.item_icon_path = icon_path
	if item.item_icon == null and ResourceLoader.exists(icon_path):
		item.item_icon = load(icon_path)

func _get_icon_path_for_item(item: InventoryItemData) -> String:
	if item == null or item.item_id == StringName(""):
		return ""
	var normalized_id := String(item.item_id)
	for rarity_name in ["_common", "_uncommon", "_rare", "_epic", "_legendary"]:
		if normalized_id.ends_with(rarity_name):
			normalized_id = normalized_id.trim_suffix(rarity_name)
			break
	return "res://Assets/Icons/Gear/%s.png" % normalized_id

func _get_rarity_weight(rarity: String) -> float:
	match rarity:
		"Legendary":
			return 1.0
		"Epic":
			return 2.0
		"Rare":
			return 3.0
		"Uncommon":
			return 6.0
		_:
			return 8.0
