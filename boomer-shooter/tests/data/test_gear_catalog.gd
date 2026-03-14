extends "res://addons/gut/test.gd"

const InventorySystemScript = preload("res://Scripts/Inventory/inventory_system.gd")

const CATALOG_PATH := "res://Data/gear/gear_catalog.tres"
const EXPECTED_RARITIES := ["Common", "Uncommon", "Rare", "Epic", "Legendary"]
const EXPECTED_WEAPON_KEYS := ["rifle", "shotgun", "crossbow", "fireball"]
const EXPECTED_AMMO_KEYS := ["shells", "arrows", "energy"]

func test_gear_catalog_loads_with_expected_item_count() -> void:
	var catalog = load(CATALOG_PATH)
	assert_not_null(catalog)
	assert_eq(catalog.lines.size(), 15)
	assert_eq(catalog.get_all_items().size(), 75)

func test_every_item_uses_valid_slot_and_armor_category() -> void:
	var catalog = load(CATALOG_PATH)
	var valid_slots: Array = InventorySystemScript.EQUIPMENT_SLOT_NAMES
	for line in catalog.lines:
		assert_not_null(line)
		assert_true(valid_slots.has(line.slot_name), "Unexpected line slot on %s" % line.piece_name)
		assert_eq(line.variants.size(), EXPECTED_RARITIES.size())
	for item in catalog.get_all_items():
		assert_not_null(item)
		assert_eq(item.category, &"armor")
		assert_true(valid_slots.has(item.equipment_slot), "Unexpected slot on %s" % item.display_name)
		assert_true(item.stats.has("rarity"), "Missing rarity on %s" % item.display_name)
		assert_ne(String(item.to_dict().get("icon_path", "")), "", "Missing icon path on %s" % item.display_name)

func test_each_lineage_has_five_rarity_variants_with_non_decreasing_stats() -> void:
	var catalog = load(CATALOG_PATH)
	var lineages := {}
	for item in catalog.get_all_items():
		var rarity_name := String(item.stats.get("rarity", ""))
		var suffix := "_%s" % rarity_name.to_lower()
		var lineage_key := String(item.item_id)
		if lineage_key.ends_with(suffix):
			lineage_key = lineage_key.trim_suffix(suffix)
		var rarity_map: Dictionary = lineages.get(lineage_key, {})
		rarity_map[rarity_name] = item
		lineages[lineage_key] = rarity_map

	for lineage_key in lineages.keys():
		var rarity_map: Dictionary = lineages[lineage_key]
		assert_eq(rarity_map.size(), EXPECTED_RARITIES.size(), "Wrong rarity count for %s" % lineage_key)
		var previous_stats := {}
		for rarity_name in EXPECTED_RARITIES:
			assert_true(rarity_map.has(rarity_name), "Missing %s for %s" % [rarity_name, lineage_key])
			var item = rarity_map[rarity_name]
			var current_stats: Dictionary = item.stats
			var all_keys: Array = previous_stats.keys()
			for stat_key in current_stats.keys():
				if stat_key == "rarity":
					continue
				if not all_keys.has(stat_key):
					all_keys.append(stat_key)
			for stat_key in all_keys:
				var previous_value := float(previous_stats.get(stat_key, 0.0))
				var current_value := float(current_stats.get(stat_key, 0.0))
				assert_true(current_value >= previous_value, "%s regressed from %s to %s on %s" % [stat_key, previous_value, current_value, item.display_name])
			previous_stats = current_stats

func test_catalog_supports_generic_and_targeted_build_paths() -> void:
	var catalog = load(CATALOG_PATH)
	var saw_health_add := false
	var saw_health_mult := false
	var saw_move_speed_add := false
	var saw_move_speed_mult := false
	var saw_weapon_damage_add := false
	var saw_weapon_damage_mult := false
	var exact_weapon_hits := {}
	var ammo_family_hits := {}

	for weapon_key in EXPECTED_WEAPON_KEYS:
		exact_weapon_hits[weapon_key] = false
	for ammo_key in EXPECTED_AMMO_KEYS:
		ammo_family_hits[ammo_key] = false

	for item in catalog.get_all_items():
		var stats: Dictionary = item.stats
		saw_health_add = saw_health_add or stats.has("health_add")
		saw_health_mult = saw_health_mult or stats.has("health_mult")
		saw_move_speed_add = saw_move_speed_add or stats.has("move_speed_add")
		saw_move_speed_mult = saw_move_speed_mult or stats.has("move_speed_mult")
		saw_weapon_damage_add = saw_weapon_damage_add or stats.has("weapon_damage_add")
		saw_weapon_damage_mult = saw_weapon_damage_mult or stats.has("weapon_damage_mult")

		for weapon_key in EXPECTED_WEAPON_KEYS:
			if stats.has("%s_damage_add" % weapon_key) or stats.has("%s_damage_mult" % weapon_key):
				exact_weapon_hits[weapon_key] = true

		for ammo_key in EXPECTED_AMMO_KEYS:
			if stats.has("%s_damage_mult" % ammo_key):
				ammo_family_hits[ammo_key] = true

	assert_true(saw_health_add)
	assert_true(saw_health_mult)
	assert_true(saw_move_speed_add)
	assert_true(saw_move_speed_mult)
	assert_true(saw_weapon_damage_add)
	assert_true(saw_weapon_damage_mult)

	for weapon_key in EXPECTED_WEAPON_KEYS:
		assert_true(exact_weapon_hits[weapon_key], "Missing exact-weapon support for %s" % weapon_key)
	for ammo_key in EXPECTED_AMMO_KEYS:
		assert_true(ammo_family_hits[ammo_key], "Missing ammo-family support for %s" % ammo_key)

func test_catalog_can_duplicate_specific_and_random_items() -> void:
	var catalog = load(CATALOG_PATH)
	var starter_item = catalog.create_item_by_id(&"helmet_scout_visor_common")
	assert_not_null(starter_item)
	assert_eq(starter_item.item_id, &"helmet_scout_visor_common")
	assert_ne(String(starter_item.to_dict().get("icon_path", "")), "")

	var loot: Array = catalog.create_random_items(4, 1337)
	assert_eq(loot.size(), 4)
	var ids := {}
	for item in loot:
		assert_not_null(item)
		assert_false(ids.has(item.item_id), "Duplicate loot item %s" % item.item_id)
		ids[item.item_id] = true
