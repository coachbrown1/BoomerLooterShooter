extends "res://addons/gut/test.gd"

const InventorySystemScript = preload("res://Scripts/Inventory/inventory_system.gd")
const WeaponManagerScript = preload("res://Scripts/Weapons/weapon_manager.gd")

const CATALOG_PATH := "res://Data/gear/gear_catalog.tres"
const EXPECTED_RARITIES := ["Common", "Uncommon", "Rare", "Epic", "Legendary"]
const EXPECTED_WEAPON_KEYS := ["rifle", "shotgun", "crossbow", "fireball"]
const EXPECTED_AMMO_KEYS := ["shells", "arrows", "energy"]
const EXPECTED_ARMOR_ITEM_COUNT := 75
const EXPECTED_WEAPON_ITEM_COUNT := 20
const EXPECTED_UTILITY_ITEM_COUNT := 15
const EXPECTED_UTILITY_ABILITIES := ["dash_pack", "grapple_hook", "jet_pack"]
const LOWER_IS_BETTER_STATS := ["dash_cooldown_mult", "jet_recharge_mult"]

func test_gear_catalog_loads_with_expected_item_count() -> void:
	var catalog = load(CATALOG_PATH)
	assert_not_null(catalog)
	assert_eq(catalog.lines.size(), 18)
	assert_eq(catalog.get_all_items().size(), EXPECTED_ARMOR_ITEM_COUNT + EXPECTED_WEAPON_ITEM_COUNT + EXPECTED_UTILITY_ITEM_COUNT)

func test_every_item_uses_valid_slot_and_category() -> void:
	var catalog = load(CATALOG_PATH)
	var valid_slots: Array = InventorySystemScript.EQUIPMENT_SLOT_NAMES
	for line in catalog.lines:
		assert_not_null(line)
		assert_true(valid_slots.has(line.slot_name), "Unexpected line slot on %s" % line.piece_name)
		assert_eq(line.variants.size(), EXPECTED_RARITIES.size())
	var weapon_count := 0
	for item in catalog.get_all_items():
		assert_not_null(item)
		if item.category == &"armor":
			assert_true(valid_slots.has(item.equipment_slot), "Unexpected slot on %s" % item.display_name)
		elif item.category == &"utility":
			assert_true(valid_slots.has(item.equipment_slot), "Unexpected utility slot on %s" % item.display_name)
			assert_true(EXPECTED_UTILITY_ABILITIES.has(String(item.active_ability)), "Unexpected utility ability on %s" % item.display_name)
		elif item.category == &"weapon":
			weapon_count += 1
			assert_true(EXPECTED_WEAPON_KEYS.has(String(item.weapon_key)), "Unexpected weapon key on %s" % item.display_name)
			assert_eq(item.equipment_slot, StringName(""))
		else:
			fail_test("Unexpected category on %s: %s" % [item.display_name, String(item.category)])
		assert_true(item.stats.has("rarity"), "Missing rarity on %s" % item.display_name)
		assert_ne(String(item.to_dict().get("icon_path", "")), "", "Missing icon path on %s" % item.display_name)
	assert_eq(weapon_count, EXPECTED_WEAPON_ITEM_COUNT)

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
				if LOWER_IS_BETTER_STATS.has(String(stat_key)):
					assert_true(current_value <= previous_value, "%s regressed from %s to %s on %s" % [stat_key, previous_value, current_value, item.display_name])
				else:
					assert_true(current_value >= previous_value, "%s regressed from %s to %s on %s" % [stat_key, previous_value, current_value, item.display_name])
			previous_stats = current_stats

func test_catalog_supports_generic_and_targeted_build_paths() -> void:
	var catalog = load(CATALOG_PATH)
	var saw_health_add := false
	var saw_health_mult := false
	var saw_damage_reduction := false
	var saw_move_speed_add := false
	var saw_move_speed_mult := false
	var saw_jump_velocity_add := false
	var saw_air_control_mult := false
	var saw_dash_distance_add := false
	var saw_grapple_range_add := false
	var saw_jet_fuel_add := false
	var saw_weapon_damage_add := false
	var saw_weapon_damage_mult := false
	var saw_mag_size_add := false
	var saw_mag_size_mult := false
	var exact_weapon_hits := {}
	var ammo_family_hits := {}
	var exact_weapon_mag_hits := {}
	var ammo_family_mag_hits := {}

	for weapon_key in EXPECTED_WEAPON_KEYS:
		exact_weapon_hits[weapon_key] = false
		exact_weapon_mag_hits[weapon_key] = false
	for ammo_key in EXPECTED_AMMO_KEYS:
		ammo_family_hits[ammo_key] = false
		ammo_family_mag_hits[ammo_key] = false

	for item in catalog.get_all_items():
		var stats: Dictionary = item.stats
		saw_health_add = saw_health_add or stats.has("health_add")
		saw_health_mult = saw_health_mult or stats.has("health_mult")
		saw_damage_reduction = saw_damage_reduction or stats.has("damage_reduction")
		saw_move_speed_add = saw_move_speed_add or stats.has("move_speed_add")
		saw_move_speed_mult = saw_move_speed_mult or stats.has("move_speed_mult")
		saw_jump_velocity_add = saw_jump_velocity_add or stats.has("jump_velocity_add")
		saw_air_control_mult = saw_air_control_mult or stats.has("air_control_mult")
		saw_dash_distance_add = saw_dash_distance_add or stats.has("dash_distance_add")
		saw_grapple_range_add = saw_grapple_range_add or stats.has("grapple_range_add")
		saw_jet_fuel_add = saw_jet_fuel_add or stats.has("jet_fuel_add")
		saw_weapon_damage_add = saw_weapon_damage_add or stats.has("weapon_damage_add")
		saw_weapon_damage_mult = saw_weapon_damage_mult or stats.has("weapon_damage_mult")
		saw_mag_size_add = saw_mag_size_add or stats.has("mag_size_add")
		saw_mag_size_mult = saw_mag_size_mult or stats.has("mag_size_mult")

		for weapon_key in EXPECTED_WEAPON_KEYS:
			if stats.has("%s_damage_add" % weapon_key) or stats.has("%s_damage_mult" % weapon_key):
				exact_weapon_hits[weapon_key] = true
			if stats.has("%s_mag_size_add" % weapon_key) or stats.has("%s_mag_size_mult" % weapon_key):
				exact_weapon_mag_hits[weapon_key] = true

		for ammo_key in EXPECTED_AMMO_KEYS:
			if stats.has("%s_damage_mult" % ammo_key):
				ammo_family_hits[ammo_key] = true
			if stats.has("%s_mag_size_add" % ammo_key) or stats.has("%s_mag_size_mult" % ammo_key):
				ammo_family_mag_hits[ammo_key] = true

	assert_true(saw_health_add)
	assert_true(saw_health_mult)
	assert_true(saw_damage_reduction)
	assert_true(saw_move_speed_add)
	assert_true(saw_move_speed_mult)
	assert_true(saw_jump_velocity_add)
	assert_true(saw_air_control_mult)
	assert_true(saw_dash_distance_add)
	assert_true(saw_grapple_range_add)
	assert_true(saw_jet_fuel_add)
	assert_true(saw_weapon_damage_add)
	assert_true(saw_weapon_damage_mult)
	assert_true(saw_mag_size_add)
	assert_true(saw_mag_size_mult)

	for weapon_key in EXPECTED_WEAPON_KEYS:
		assert_true(exact_weapon_hits[weapon_key], "Missing exact-weapon support for %s" % weapon_key)
	assert_true(exact_weapon_mag_hits["rifle"], "Missing exact-weapon magazine support for rifle")
	assert_true(exact_weapon_mag_hits["shotgun"], "Missing exact-weapon magazine support for shotgun")
	for ammo_key in EXPECTED_AMMO_KEYS:
		assert_true(ammo_family_hits[ammo_key], "Missing ammo-family support for %s" % ammo_key)
	assert_true(ammo_family_mag_hits["shells"], "Missing ammo-family magazine support for shells")

func test_catalog_can_duplicate_specific_and_random_items() -> void:
	var catalog = load(CATALOG_PATH)
	var starter_item = catalog.create_item_by_id(&"helmet_scout_visor_common")
	assert_not_null(starter_item)
	assert_eq(starter_item.item_id, &"helmet_scout_visor_common")
	assert_ne(String(starter_item.to_dict().get("icon_path", "")), "")
	assert_eq(String(starter_item.to_dict().get("rarity", "")), "Common")
	assert_eq((starter_item.to_dict().get("affixes", []) as Array).size(), 0)
	assert_false((starter_item.to_dict().get("implicit_stats", {}) as Dictionary).is_empty())

	var loot: Array = catalog.create_random_items(4, 1337)
	assert_eq(loot.size(), 4)
	var ids := {}
	for item in loot:
		assert_not_null(item)
		assert_false(ids.has(item.item_id), "Duplicate loot item %s" % item.item_id)
		ids[item.item_id] = true
		var snapshot: Dictionary = item.to_dict()
		var rarity_name := String(snapshot.get("rarity", ""))
		var affix_count := (snapshot.get("affixes", []) as Array).size()
		match rarity_name:
			"Legendary":
				assert_eq(affix_count, 4)
			"Epic":
				assert_eq(affix_count, 3)
			"Rare":
				assert_eq(affix_count, 2)
			"Uncommon":
				assert_eq(affix_count, 1)
			_:
				assert_eq(affix_count, 0)

func test_generated_items_use_implicits_and_random_affixes() -> void:
	var catalog = load(CATALOG_PATH)
	var first_roll = catalog.create_random_items(8, 111)
	var second_roll = catalog.create_random_items(8, 222)
	assert_eq(first_roll.size(), 8)
	assert_eq(second_roll.size(), 8)

	var saw_affixed_item := false
	var saw_different_rolls := false
	for i in range(min(first_roll.size(), second_roll.size())):
		var first_item: Dictionary = first_roll[i].to_dict()
		var second_item: Dictionary = second_roll[i].to_dict()
		var rarity_name := String(first_item.get("rarity", ""))
		if rarity_name != "Common":
			saw_affixed_item = saw_affixed_item or (first_item.get("affixes", []) as Array).size() > 0
		if first_item.get("affixes", []) != second_item.get("affixes", []):
			saw_different_rolls = true
		assert_false((first_item.get("implicit_stats", {}) as Dictionary).is_empty(), "Missing implicit stats on %s" % first_item.get("item_id", "item"))

	assert_true(saw_affixed_item)
	assert_true(saw_different_rolls)

func test_weapon_lineages_cover_all_rarities() -> void:
	var catalog = load(CATALOG_PATH)
	var weapon_items_by_key := {}
	for item in catalog.get_all_items():
		if item.category != &"weapon":
			continue
		var weapon_key := String(item.weapon_key)
		var rarity := String(item.stats.get("rarity", ""))
		var rarity_map: Dictionary = weapon_items_by_key.get(weapon_key, {})
		rarity_map[rarity] = item
		weapon_items_by_key[weapon_key] = rarity_map

	for weapon_key in EXPECTED_WEAPON_KEYS:
		assert_true(weapon_items_by_key.has(weapon_key), "Missing weapon lineage for %s" % weapon_key)
		var rarity_map: Dictionary = weapon_items_by_key.get(weapon_key, {})
		assert_eq(rarity_map.size(), EXPECTED_RARITIES.size(), "Wrong rarity count for weapon %s" % weapon_key)
		for rarity in EXPECTED_RARITIES:
			assert_true(rarity_map.has(rarity), "Missing %s weapon rarity for %s" % [rarity, weapon_key])

func test_random_loot_pool_includes_weapons() -> void:
	var catalog = load(CATALOG_PATH)
	var saw_weapon := false
	for item in catalog.create_random_items(20, 424242):
		if item != null and item.category == &"weapon":
			saw_weapon = true
			break
	assert_true(saw_weapon)

func test_utility_items_define_active_ability_metadata() -> void:
	var catalog = load(CATALOG_PATH)
	var utility_count := 0
	for item in catalog.get_all_items():
		if item.category != &"utility":
			continue
		utility_count += 1
		assert_true(EXPECTED_UTILITY_ABILITIES.has(String(item.active_ability)))
		assert_ne(item.active_ability_label, "")
		assert_eq(item.equipment_slot, &"utility_primary")
	assert_eq(utility_count, EXPECTED_UTILITY_ITEM_COUNT)

	var generated_dash = catalog.create_item_by_id(&"utility_dash_pack_common")
	assert_not_null(generated_dash)
	assert_eq(String(generated_dash.active_ability), "dash_pack")

	var generated_grapple = catalog.create_item_by_id(&"utility_grapple_hook_common")
	assert_not_null(generated_grapple)
	assert_eq(String(generated_grapple.active_ability), "grapple_hook")

	var generated_jet = catalog.create_item_by_id(&"utility_jet_pack_common")
	assert_not_null(generated_jet)
	assert_eq(String(generated_jet.active_ability), "jet_pack")

func test_inventory_starts_with_only_crossbow_equipped() -> void:
	var inventory = autofree(InventorySystemScript.new())
	var weapon_manager = autofree(WeaponManagerScript.new())
	inventory.gear_catalog = load(CATALOG_PATH)
	inventory._ready()
	inventory.initialize_with_weapon_manager(weapon_manager)

	assert_not_null(inventory.weapons[0])
	assert_eq(String(inventory.weapons[0].weapon_key), "crossbow")
	for i in range(1, inventory.weapons.size()):
		assert_null(inventory.weapons[i], "Unexpected starter weapon in slot %d" % i)
	assert_eq(String(inventory.storage[5].item_id), "utility_dash_pack_common")
	assert_eq(String(inventory.storage[5].active_ability), "dash_pack")
	assert_eq(String(inventory.storage[6].item_id), "utility_grapple_hook_common")
	assert_eq(String(inventory.storage[6].active_ability), "grapple_hook")
	assert_eq(String(inventory.storage[7].item_id), "utility_jet_pack_common")
	assert_eq(String(inventory.storage[7].active_ability), "jet_pack")
