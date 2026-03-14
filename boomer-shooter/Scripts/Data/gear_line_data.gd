extends Resource
class_name GearLineData

const RARITY_ORDER := ["Common", "Uncommon", "Rare", "Epic", "Legendary"]

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

func get_variants() -> Array[InventoryItemData]:
	var results: Array[InventoryItemData] = []
	for item in variants:
		if item == null:
			continue
		results.append(item)
	return results

func get_implicit_stats() -> Dictionary:
	var common_variant := get_variant_by_rarity("Common")
	if common_variant == null:
		return {}
	var implicit_stats := common_variant.stats.duplicate(true)
	implicit_stats.erase("rarity")
	return implicit_stats

func get_affix_package_for_step(rarity: String) -> Dictionary:
	var rarity_index := RARITY_ORDER.find(rarity)
	if rarity_index <= 0:
		return {}
	var current_variant := get_variant_by_rarity(rarity)
	var previous_variant := get_variant_by_rarity(RARITY_ORDER[rarity_index - 1])
	if current_variant == null or previous_variant == null:
		return {}

	var current_stats: Dictionary = current_variant.stats.duplicate(true)
	var previous_stats: Dictionary = previous_variant.stats.duplicate(true)
	current_stats.erase("rarity")
	previous_stats.erase("rarity")

	var delta_stats := {}
	for stat_key in current_stats.keys():
		var delta_value := float(current_stats.get(stat_key, 0.0)) - float(previous_stats.get(stat_key, 0.0))
		if delta_value > 0.0:
			delta_stats[stat_key] = delta_value

	if delta_stats.is_empty():
		return {}

	return {
		"affix_id": "%s_%s_upgrade" % [String(piece_name).to_lower().replace(" ", "_"), rarity.to_lower()],
		"rarity_step": rarity,
		"label": _build_affix_label(delta_stats),
		"stats": delta_stats
	}

func _build_affix_label(delta_stats: Dictionary) -> String:
	if delta_stats.is_empty():
		return "Modifier"
	var primary_key := String(delta_stats.keys()[0])
	var name_map := {
		"health_add": "of Vitality",
		"health_mult": "of Fortitude",
		"damage_reduction": "of Bulwark",
		"move_speed_add": "of Swiftness",
		"move_speed_mult": "of Haste",
		"sprint_multiplier": "of the Pursuit",
		"weapon_damage_add": "of Slaying",
		"weapon_damage_mult": "of Carnage",
		"mag_size_add": "of Capacity",
		"mag_size_mult": "of Overflow",
		"reload_speed_mult": "of Readiness",
		"recoil_recovery_mult": "of Control",
		"spread_reduction": "of Precision",
		"fov_kick_reduction": "of Steadiness",
		"light_damage_mult": "of Riflecraft",
		"shells_damage_mult": "of Buckshot",
		"arrows_damage_mult": "of Bolts",
		"energy_damage_mult": "of Embers",
		"rifle_damage_mult": "of the Rifle",
		"shotgun_damage_mult": "of the Shotgun",
		"crossbow_damage_mult": "of the Crossbow",
		"fireball_damage_mult": "of the Fireball"
	}
	return String(name_map.get(primary_key, "Modifier"))
