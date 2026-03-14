extends Resource
class_name GearCatalogData

@export var lines: Array[GearLineData] = []

const RARITY_ORDER := ["Common", "Uncommon", "Rare", "Epic", "Legendary"]
const RARITY_AFFIX_COUNTS := {
	"Common": 0,
	"Uncommon": 1,
	"Rare": 2,
	"Epic": 3,
	"Legendary": 4
}

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
			var template := item.duplicate(true) as InventoryItemData
			var rng := RandomNumberGenerator.new()
			rng.seed = hash(String(item_id))
			return _instantiate_generated_item(template, rng)
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

		var template := pool[chosen_index].duplicate(true) as InventoryItemData
		results.append(_instantiate_generated_item(template, rng))
		pool.remove_at(chosen_index)

	return results

func _instantiate_generated_item(template: InventoryItemData, rng: RandomNumberGenerator) -> InventoryItemData:
	if template == null:
		return null
	var generated_item := template.duplicate(true) as InventoryItemData
	if generated_item == null:
		return null

	var rarity := String(template.stats.get("rarity", "Common"))
	var implicit_stats := _get_implicit_stats_for_item(template)
	var affixes := _roll_affixes_for_item(template, rarity, rng)
	generated_item.set_generated_modifiers(rarity, implicit_stats, affixes)
	_apply_defaults_to_item(generated_item)
	return generated_item

func _get_implicit_stats_for_item(item: InventoryItemData) -> Dictionary:
	var line := _find_line_for_item(item)
	if line == null:
		var fallback := item.stats.duplicate(true)
		fallback.erase("rarity")
		return fallback
	return line.get_implicit_stats()

func _roll_affixes_for_item(item: InventoryItemData, rarity: String, rng: RandomNumberGenerator) -> Array[Dictionary]:
	var affixes: Array[Dictionary] = []
	var line := _find_line_for_item(item)
	if line == null:
		return affixes

	var affix_count := int(RARITY_AFFIX_COUNTS.get(rarity, 0))
	for rarity_step in RARITY_ORDER:
		if affixes.size() >= affix_count:
			break
		if rarity_step == "Common":
			continue
		var step_index := RARITY_ORDER.find(rarity_step)
		var rarity_index := RARITY_ORDER.find(rarity)
		if step_index == -1 or rarity_index == -1 or step_index > rarity_index:
			continue
		var pool := _get_affix_pool_for_slot(line.slot_name, rarity_step)
		if pool.is_empty():
			continue
		var chosen_affix: Dictionary = pool[rng.randi_range(0, pool.size() - 1)].duplicate(true)
		affixes.append(chosen_affix)
	return affixes

func _get_affix_pool_for_slot(slot_name: StringName, rarity_step: String) -> Array[Dictionary]:
	var pool: Array[Dictionary] = []
	for line in lines:
		if line == null or line.slot_name != slot_name:
			continue
		var affix_package := line.get_affix_package_for_step(rarity_step)
		if affix_package.is_empty():
			continue
		pool.append(affix_package)
	return pool

func _find_line_for_item(item: InventoryItemData) -> GearLineData:
	if item == null:
		return null
	var item_id_text := String(item.item_id)
	for line in lines:
		if line == null:
			continue
		for variant in line.variants:
			if variant == null:
				continue
			if String(variant.item_id) == item_id_text:
				return line
	return null

func _apply_defaults_to_item(item: InventoryItemData) -> void:
	if item == null:
		return
	item.ensure_runtime_defaults()
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
