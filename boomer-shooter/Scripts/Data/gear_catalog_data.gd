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
const WEAPON_DEFINITIONS := {
	"crossbow": {
		"display_name": "Crossbow",
		"icon_path": "res://Assets/Icons/Weapons/icon_crossbow.png",
		"rarities": {
			"Common": {},
			"Uncommon": {"weapon_damage_add": 4.0},
			"Rare": {"weapon_damage_add": 8.0, "reload_speed_mult": 0.08},
			"Epic": {"weapon_damage_add": 12.0, "crossbow_damage_mult": 0.08, "reload_speed_mult": 0.12},
			"Legendary": {"weapon_damage_add": 18.0, "crossbow_damage_mult": 0.14, "reload_speed_mult": 0.18}
		}
	},
	"rifle": {
		"display_name": "Rifle",
		"icon_path": "res://Assets/Icons/Weapons/icon_rifle.png",
		"rarities": {
			"Common": {},
			"Uncommon": {"weapon_damage_add": 1.0},
			"Rare": {"weapon_damage_add": 2.0, "mag_size_add": 2.0},
			"Epic": {"weapon_damage_add": 4.0, "rifle_damage_mult": 0.08, "mag_size_add": 4.0},
			"Legendary": {"weapon_damage_add": 6.0, "rifle_damage_mult": 0.14, "mag_size_add": 6.0}
		}
	},
	"shotgun": {
		"display_name": "Shotgun",
		"icon_path": "res://Assets/Icons/Weapons/icon_shotgun.png",
		"rarities": {
			"Common": {},
			"Uncommon": {"weapon_damage_add": 1.0},
			"Rare": {"weapon_damage_add": 3.0, "reload_speed_mult": 0.06},
			"Epic": {"weapon_damage_add": 5.0, "reload_speed_mult": 0.10, "shotgun_damage_mult": 0.08, "spread_reduction": 0.08},
			"Legendary": {"weapon_damage_add": 8.0, "reload_speed_mult": 0.14, "shotgun_damage_mult": 0.14, "spread_reduction": 0.12, "mag_size_add": 1.0}
		}
	},
	"fireball": {
		"display_name": "Fireball",
		"icon_path": "res://Assets/Icons/Weapons/icon_fireball.png",
		"rarities": {
			"Common": {},
			"Uncommon": {"weapon_damage_add": 5.0},
			"Rare": {"weapon_damage_add": 10.0, "reload_speed_mult": 0.08},
			"Epic": {"weapon_damage_add": 15.0, "fireball_damage_mult": 0.08, "reload_speed_mult": 0.12},
			"Legendary": {"weapon_damage_add": 20.0, "fireball_damage_mult": 0.14, "reload_speed_mult": 0.16, "fireball_mag_size_add": 1.0}
		}
	}
}
const WEAPON_AFFIX_POOLS := {
	"Uncommon": [
		{"affix_id": "weapon_uncommon_damage", "label": "of Impact", "stats": {"weapon_damage_add": 2.0}},
		{"affix_id": "weapon_uncommon_reload", "label": "of Readiness", "stats": {"reload_speed_mult": 0.08}},
		{"affix_id": "weapon_uncommon_capacity", "label": "of Capacity", "stats": {"mag_size_add": 1.0}},
		{"affix_id": "weapon_uncommon_precision", "label": "of Precision", "stats": {"spread_reduction": 0.10}}
	],
	"Rare": [
		{"affix_id": "weapon_rare_damage", "label": "of Force", "stats": {"weapon_damage_add": 4.0}},
		{"affix_id": "weapon_rare_mastery", "label": "of Mastery", "stats": {"weapon_damage_mult": 0.10}},
		{"affix_id": "weapon_rare_mag", "label": "of Overflow", "stats": {"mag_size_mult": 0.15}},
		{"affix_id": "weapon_rare_reload", "label": "of Quick Hands", "stats": {"reload_speed_mult": 0.12}}
	],
	"Epic": [
		{"affix_id": "weapon_epic_damage", "label": "of Ruin", "stats": {"weapon_damage_add": 6.0}},
		{"affix_id": "weapon_epic_mastery", "label": "of Carnage", "stats": {"weapon_damage_mult": 0.16}},
		{"affix_id": "weapon_epic_capacity", "label": "of Overflowing Chambers", "stats": {"mag_size_add": 1.0, "mag_size_mult": 0.10}},
		{"affix_id": "weapon_epic_precision", "label": "of Tight Grouping", "stats": {"spread_reduction": 0.16}}
	],
	"Legendary": [
		{"affix_id": "weapon_legendary_damage", "label": "of Cataclysm", "stats": {"weapon_damage_add": 8.0}},
		{"affix_id": "weapon_legendary_mastery", "label": "of Extermination", "stats": {"weapon_damage_mult": 0.22}},
		{"affix_id": "weapon_legendary_capacity", "label": "of Endless Payload", "stats": {"mag_size_add": 2.0}},
		{"affix_id": "weapon_legendary_reload", "label": "of Perfect Cycling", "stats": {"reload_speed_mult": 0.18}},
		{"affix_id": "weapon_legendary_precision", "label": "of Surgical Aim", "stats": {"spread_reduction": 0.22}}
	]
}

func get_all_items() -> Array[InventoryItemData]:
	var results: Array[InventoryItemData] = []
	for line in lines:
		if line == null:
			continue
		for item in line.get_variants():
			_apply_defaults_to_item(item)
			results.append(item)
	for item in _get_weapon_templates():
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
	if _is_weapon_item(item):
		var fallback := item.stats.duplicate(true)
		fallback.erase("rarity")
		return fallback
	var line := _find_line_for_item(item)
	if line == null:
		var fallback := item.stats.duplicate(true)
		fallback.erase("rarity")
		return fallback
	return line.get_implicit_stats()

func _roll_affixes_for_item(item: InventoryItemData, rarity: String, rng: RandomNumberGenerator) -> Array[Dictionary]:
	if _is_weapon_item(item):
		return _roll_weapon_affixes(rarity, rng)
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
	if _is_weapon_item(item):
		return null
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
	if _is_weapon_item(item):
		var weapon_key := String(item.weapon_key)
		var definition: Dictionary = WEAPON_DEFINITIONS.get(weapon_key, {})
		return String(definition.get("icon_path", "res://Assets/Icons/Weapons/icon_%s.png" % weapon_key))
	var normalized_id := String(item.item_id)
	for rarity_name in ["_common", "_uncommon", "_rare", "_epic", "_legendary"]:
		if normalized_id.ends_with(rarity_name):
			normalized_id = normalized_id.trim_suffix(rarity_name)
			break
	return "res://Assets/Icons/Gear/%s.png" % normalized_id

func create_weapon_item(weapon_key: StringName, rarity: String = "Common", seed: int = -1) -> InventoryItemData:
	var key := String(weapon_key)
	for template in _get_weapon_templates():
		if String(template.weapon_key) != key:
			continue
		if String(template.stats.get("rarity", "")) != rarity:
			continue
		var rng := RandomNumberGenerator.new()
		rng.seed = seed if seed >= 0 else hash("%s|%s" % [key, rarity])
		return _instantiate_generated_item(template, rng)
	return null

func _get_weapon_templates() -> Array[InventoryItemData]:
	var results: Array[InventoryItemData] = []
	for weapon_key in WEAPON_DEFINITIONS.keys():
		var definition: Dictionary = WEAPON_DEFINITIONS.get(weapon_key, {})
		var rarity_defs: Dictionary = definition.get("rarities", {})
		for rarity in RARITY_ORDER:
			var item := InventoryItemData.new()
			item.item_id = StringName("weapon_%s_%s" % [weapon_key, rarity.to_lower()])
			item.display_name = String(definition.get("display_name", String(weapon_key).capitalize()))
			item.category = &"weapon"
			item.weapon_key = StringName(weapon_key)
			item.item_icon_path = String(definition.get("icon_path", ""))
			var stats: Dictionary = (rarity_defs.get(rarity, {}) as Dictionary).duplicate(true)
			stats["rarity"] = rarity
			item.stats = stats
			item.ensure_runtime_defaults()
			results.append(item)
	return results

func _roll_weapon_affixes(rarity: String, rng: RandomNumberGenerator) -> Array[Dictionary]:
	var affixes: Array[Dictionary] = []
	var used_affix_ids: Dictionary = {}
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
		var pool: Array = WEAPON_AFFIX_POOLS.get(rarity_step, [])
		if pool.is_empty():
			continue
		var candidates: Array[Dictionary] = []
		for affix_variant in pool:
			if typeof(affix_variant) != TYPE_DICTIONARY:
				continue
			var affix: Dictionary = affix_variant
			var affix_id := String(affix.get("affix_id", ""))
			if used_affix_ids.has(affix_id):
				continue
			candidates.append(affix)
		if candidates.is_empty():
			continue
		var chosen_affix: Dictionary = (candidates[rng.randi_range(0, candidates.size() - 1)] as Dictionary).duplicate(true)
		var chosen_affix_id := String(chosen_affix.get("affix_id", ""))
		if not chosen_affix_id.is_empty():
			used_affix_ids[chosen_affix_id] = true
		affixes.append(chosen_affix)
	return affixes

func _is_weapon_item(item: InventoryItemData) -> bool:
	return item != null and item.category == &"weapon"

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
