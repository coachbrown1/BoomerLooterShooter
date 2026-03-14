extends Resource
class_name InventoryItemData

@export var item_id: StringName = &""
@export var display_name: String = ""
@export var category: StringName = &"misc" # weapon, armor, misc
@export var equipment_slot: StringName = &"" # helmet, chest, arms, legs, feet
@export var weapon_key: StringName = &""
@export var weapon_scene: PackedScene
@export var item_icon_path: String = ""
@export var item_icon: Texture2D
@export var stats: Dictionary = {}
@export var rarity_name: String = ""
@export var implicit_stats: Dictionary = {}
@export var affixes: Array[Dictionary] = []

func ensure_runtime_defaults() -> void:
	if rarity_name.is_empty():
		rarity_name = String(stats.get("rarity", ""))
	if implicit_stats.is_empty():
		var implicit_copy := stats.duplicate(true)
		implicit_copy.erase("rarity")
		implicit_stats = implicit_copy
	if stats.is_empty() or affixes.size() > 0 or not stats.has("rarity"):
		stats = _build_total_stats()

func set_generated_modifiers(new_rarity: String, new_implicit_stats: Dictionary, new_affixes: Array[Dictionary]) -> void:
	rarity_name = new_rarity
	implicit_stats = new_implicit_stats.duplicate(true)
	affixes = []
	for affix_variant in new_affixes:
		if typeof(affix_variant) != TYPE_DICTIONARY:
			continue
		affixes.append((affix_variant as Dictionary).duplicate(true))
	stats = get_total_stats()

func get_total_stats() -> Dictionary:
	ensure_runtime_defaults()
	return _build_total_stats()

func _build_total_stats() -> Dictionary:
	var combined := implicit_stats.duplicate(true)
	for affix in affixes:
		var affix_stats: Dictionary = affix.get("stats", {})
		for stat_key in affix_stats.keys():
			combined[stat_key] = float(combined.get(stat_key, 0.0)) + float(affix_stats[stat_key])
	combined["rarity"] = rarity_name
	return combined

func to_dict() -> Dictionary:
	ensure_runtime_defaults()
	return {
		"item_id": String(item_id),
		"display_name": display_name,
		"category": String(category),
		"equipment_slot": String(equipment_slot),
		"weapon_key": String(weapon_key),
		"icon_path": item_icon_path,
		"rarity": rarity_name,
		"implicit_stats": implicit_stats.duplicate(true),
		"affixes": affixes.duplicate(true),
		"stats": get_total_stats()
	}

static func from_dict(data: Dictionary) -> InventoryItemData:
	if data.is_empty():
		return null

	var item := InventoryItemData.new()
	item.item_id = StringName(data.get("item_id", ""))
	item.display_name = String(data.get("display_name", ""))
	item.category = StringName(data.get("category", "misc"))
	item.equipment_slot = StringName(data.get("equipment_slot", ""))
	item.weapon_key = StringName(data.get("weapon_key", ""))
	item.item_icon_path = String(data.get("icon_path", ""))
	if not item.item_icon_path.is_empty() and ResourceLoader.exists(item.item_icon_path):
		item.item_icon = load(item.item_icon_path)

	var rarity := String(data.get("rarity", ""))
	var implicit_stats: Dictionary = {}
	var implicit_variant: Variant = data.get("implicit_stats", {})
	if typeof(implicit_variant) == TYPE_DICTIONARY:
		implicit_stats = (implicit_variant as Dictionary).duplicate(true)
	var affixes: Array[Dictionary] = _coerce_affix_array(data.get("affixes", []))
	if rarity.is_empty():
		var fallback_stats: Dictionary = data.get("stats", {})
		rarity = String(fallback_stats.get("rarity", ""))
		implicit_stats = fallback_stats.duplicate(true)
		implicit_stats.erase("rarity")
		affixes = []

	item.set_generated_modifiers(rarity, implicit_stats, affixes)
	return item

static func _coerce_affix_array(value: Variant) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if typeof(value) != TYPE_ARRAY:
		return out
	for entry in value:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		out.append((entry as Dictionary).duplicate(true))
	return out
