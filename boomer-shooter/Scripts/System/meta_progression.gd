extends Node

const SAVE_PATH := "user://meta_progression.json"
const SAVE_VERSION := 1

const STATION_WAR_TABLE := "war_table"
const STATION_DRILL_HALL := "drill_hall"
const CURRENCY_WAR_TABLE := "war_table"

const NODE_ORDER := [
	"campaign_root_a",
	"campaign_root_b",
	"doctrine_primer",
	"unlock_drill_hall",
	"contracts_placeholder",
	"black_market_placeholder",
	"pacts_placeholder",
	"forgecraft_placeholder",
	"relics_placeholder",
	"roll_credits"
]

const NODE_DEFS := {
	"campaign_root_a": {
		"title": "Campaign Charter",
		"branch": "Campaign",
		"cost": 1,
		"visible_at_start": true,
		"prerequisites": [],
		"revealed_by": [],
		"permanent_lock": false,
		"station_unlock": "",
		"placeholder": false
	},
	"campaign_root_b": {
		"title": "Castle Supply Lines",
		"branch": "Campaign",
		"cost": 1,
		"visible_at_start": true,
		"prerequisites": ["campaign_root_a"],
		"revealed_by": [],
		"permanent_lock": false,
		"station_unlock": "",
		"placeholder": false
	},
	"doctrine_primer": {
		"title": "Doctrine Primer",
		"branch": "Doctrine",
		"cost": 1,
		"visible_at_start": true,
		"prerequisites": ["campaign_root_a"],
		"revealed_by": [],
		"permanent_lock": false,
		"station_unlock": "",
		"placeholder": false
	},
	"unlock_drill_hall": {
		"title": "Unlock Drill Hall",
		"branch": "Doctrine",
		"cost": 2,
		"visible_at_start": false,
		"prerequisites": ["doctrine_primer"],
		"revealed_by": ["doctrine_primer"],
		"permanent_lock": false,
		"station_unlock": STATION_DRILL_HALL,
		"placeholder": false
	},
	"contracts_placeholder": {
		"title": "Contracts",
		"branch": "Contracts",
		"cost": 0,
		"visible_at_start": false,
		"prerequisites": [],
		"revealed_by": ["campaign_root_b"],
		"permanent_lock": true,
		"station_unlock": "",
		"placeholder": true
	},
	"black_market_placeholder": {
		"title": "Black Market",
		"branch": "Black Market",
		"cost": 0,
		"visible_at_start": false,
		"prerequisites": [],
		"revealed_by": ["campaign_root_b"],
		"permanent_lock": true,
		"station_unlock": "",
		"placeholder": true
	},
	"pacts_placeholder": {
		"title": "Pacts",
		"branch": "Pacts",
		"cost": 0,
		"visible_at_start": false,
		"prerequisites": [],
		"revealed_by": ["campaign_root_b"],
		"permanent_lock": true,
		"station_unlock": "",
		"placeholder": true
	},
	"forgecraft_placeholder": {
		"title": "Forgecraft",
		"branch": "Forgecraft",
		"cost": 0,
		"visible_at_start": false,
		"prerequisites": [],
		"revealed_by": ["campaign_root_b"],
		"permanent_lock": true,
		"station_unlock": "",
		"placeholder": true
	},
	"relics_placeholder": {
		"title": "Relics",
		"branch": "Relics",
		"cost": 0,
		"visible_at_start": false,
		"prerequisites": [],
		"revealed_by": ["campaign_root_b"],
		"permanent_lock": true,
		"station_unlock": "",
		"placeholder": true
	},
	"roll_credits": {
		"title": "Roll Credits",
		"branch": "Endgame",
		"cost": 0,
		"visible_at_start": true,
		"prerequisites": [],
		"revealed_by": [],
		"permanent_lock": true,
		"station_unlock": "",
		"placeholder": false
	}
}

var save_path: String = SAVE_PATH

var _currencies: Dictionary = {CURRENCY_WAR_TABLE: 0}
var _unlocked_nodes: Dictionary = {}
var _discovered_nodes: Dictionary = {}
var _hub_station_unlocks: Dictionary = {
	STATION_WAR_TABLE: true,
	STATION_DRILL_HALL: false
}
var _castle_xp_total: int = 0
var _castle_level: int = 0
var _castle_unspent_points: int = 0
var _milestones: Dictionary = {}
var _loaded_once: bool = false

func _ready() -> void:
	load_progression()

func _exit_tree() -> void:
	if _loaded_once:
		save_progression()

func set_save_path(path: String) -> void:
	save_path = path if not path.strip_edges().is_empty() else SAVE_PATH

func reset_progression() -> void:
	_currencies = {CURRENCY_WAR_TABLE: 0}
	_unlocked_nodes = {}
	_discovered_nodes = {}
	_hub_station_unlocks = {
		STATION_WAR_TABLE: true,
		STATION_DRILL_HALL: false
	}
	_castle_xp_total = 0
	_castle_level = 0
	_castle_unspent_points = 0
	_milestones = {}
	_refresh_discovery_cache()

func get_currency(currency_id: String) -> int:
	return int(_currencies.get(currency_id, 0))

func get_war_table_currency() -> int:
	return get_currency(CURRENCY_WAR_TABLE)

func grant_currency(currency_id: String, amount: int, save_now: bool = true) -> int:
	if amount == 0:
		return get_currency(currency_id)
	_currencies[currency_id] = max(0, get_currency(currency_id) + amount)
	if save_now:
		save_progression()
	return get_currency(currency_id)

func spend_currency(currency_id: String, amount: int, save_now: bool = true) -> bool:
	if amount <= 0:
		return true
	if get_currency(currency_id) < amount:
		return false
	_currencies[currency_id] = get_currency(currency_id) - amount
	if save_now:
		save_progression()
	return true

func get_castle_xp_state() -> Dictionary:
	return {
		"level": _castle_level,
		"xp": _castle_xp_total,
		"unspent_points": _castle_unspent_points,
		"next_level_xp": _xp_for_next_level(_castle_level)
	}

func can_award_castle_xp() -> bool:
	return bool(_hub_station_unlocks.get(STATION_DRILL_HALL, false))

func grant_castle_xp(amount: int, save_now: bool = true) -> bool:
	if amount <= 0 or not can_award_castle_xp():
		return false
	_apply_castle_xp(amount)
	if save_now:
		save_progression()
	return true

func unlock_node(node_id: String, save_now: bool = true) -> bool:
	if not can_unlock_node(node_id):
		return false
	var node_def := get_node_definition(node_id)
	var cost := int(node_def.get("cost", 0))
	if cost > 0 and not spend_currency(CURRENCY_WAR_TABLE, cost, false):
		return false
	_unlocked_nodes[node_id] = true
	var station_unlock := String(node_def.get("station_unlock", ""))
	if not station_unlock.is_empty():
		_hub_station_unlocks[station_unlock] = true
	_refresh_discovery_cache()
	if save_now:
		save_progression()
	return true

func can_unlock_node(node_id: String) -> bool:
	if not has_node_definition(node_id):
		return false
	if is_node_unlocked(node_id):
		return false
	var node_def := get_node_definition(node_id)
	if bool(node_def.get("permanent_lock", false)):
		return false
	if not is_node_visible(node_id):
		return false
	for prerequisite in _get_string_list(node_def.get("prerequisites", [])):
		if not is_node_unlocked(prerequisite):
			return false
	var cost := int(node_def.get("cost", 0))
	return get_war_table_currency() >= cost

func has_node_definition(node_id: String) -> bool:
	return NODE_DEFS.has(node_id)

func get_node_definition(node_id: String) -> Dictionary:
	if not NODE_DEFS.has(node_id):
		return {}
	return NODE_DEFS[node_id].duplicate(true)

func is_node_unlocked(node_id: String) -> bool:
	return bool(_unlocked_nodes.get(node_id, false))

func is_node_visible(node_id: String) -> bool:
	if not has_node_definition(node_id):
		return false
	if bool(_discovered_nodes.get(node_id, false)):
		return true
	var node_def := get_node_definition(node_id)
	if bool(node_def.get("visible_at_start", false)):
		return true
	for revealer in _get_string_list(node_def.get("revealed_by", [])):
		if is_node_unlocked(revealer):
			return true
	return false

func get_node_state(node_id: String) -> Dictionary:
	if not has_node_definition(node_id):
		return {}
	var node_def := get_node_definition(node_id)
	return {
		"id": node_id,
		"title": String(node_def.get("title", node_id)),
		"branch": String(node_def.get("branch", "")),
		"cost": int(node_def.get("cost", 0)),
		"visible": is_node_visible(node_id),
		"unlocked": is_node_unlocked(node_id),
		"placeholder": bool(node_def.get("placeholder", false)),
		"permanent_lock": bool(node_def.get("permanent_lock", false)),
		"station_unlock": String(node_def.get("station_unlock", "")),
		"prerequisites": _get_string_list(node_def.get("prerequisites", [])),
		"revealed_by": _get_string_list(node_def.get("revealed_by", []))
	}

func get_war_table_nodes() -> Array:
	var nodes: Array = []
	for node_id in NODE_ORDER:
		nodes.append(get_node_state(node_id))
	return nodes

func is_station_unlocked(station_id: String) -> bool:
	return bool(_hub_station_unlocks.get(station_id, false))

func get_station_unlocks() -> Dictionary:
	return _hub_station_unlocks.duplicate(true)

func set_milestone(milestone_id: String, value: bool = true, save_now: bool = true) -> void:
	_milestones[milestone_id] = value
	if save_now:
		save_progression()

func get_milestone(milestone_id: String) -> bool:
	return bool(_milestones.get(milestone_id, false))

func get_save_snapshot() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"currencies": _currencies.duplicate(true),
		"war_table": {
			"unlocked_nodes": _get_sorted_flag_keys(_unlocked_nodes),
			"discovered_nodes": _get_sorted_flag_keys(_discovered_nodes)
		},
		"hub_station_unlocks": _hub_station_unlocks.duplicate(true),
		"castle_xp": {
			"total": _castle_xp_total,
			"level": _castle_level,
			"unspent_points": _castle_unspent_points
		},
		"milestones": _milestones.duplicate(true)
	}

func apply_save_snapshot(snapshot: Dictionary) -> void:
	reset_progression()
	_currencies = _coerce_dictionary(snapshot.get("currencies", {}))
	if not _currencies.has(CURRENCY_WAR_TABLE):
		_currencies[CURRENCY_WAR_TABLE] = 0
	var war_table_snapshot := _coerce_dictionary(snapshot.get("war_table", {}))
	_unlocked_nodes = _flag_dictionary_from_list(war_table_snapshot.get("unlocked_nodes", []))
	_discovered_nodes = _flag_dictionary_from_list(war_table_snapshot.get("discovered_nodes", []))
	_hub_station_unlocks = _coerce_dictionary(snapshot.get("hub_station_unlocks", {}))
	if not _hub_station_unlocks.has(STATION_WAR_TABLE):
		_hub_station_unlocks[STATION_WAR_TABLE] = true
	if not _hub_station_unlocks.has(STATION_DRILL_HALL):
		_hub_station_unlocks[STATION_DRILL_HALL] = false
	var castle_snapshot := _coerce_dictionary(snapshot.get("castle_xp", {}))
	_castle_xp_total = max(0, int(castle_snapshot.get("total", castle_snapshot.get("xp", 0))))
	_castle_level = max(0, int(castle_snapshot.get("level", 0)))
	_castle_unspent_points = max(0, int(castle_snapshot.get("unspent_points", 0)))
	_milestones = _coerce_dictionary(snapshot.get("milestones", {}))
	_refresh_discovery_cache()

func save_progression(custom_path: String = "") -> bool:
	var target_path := custom_path if not custom_path.strip_edges().is_empty() else save_path
	var file := FileAccess.open(target_path, FileAccess.WRITE)
	if file == null:
		push_warning("MetaProgression: could not open save path %s" % target_path)
		return false
	file.store_string(JSON.stringify(get_save_snapshot()))
	file.close()
	return true

func load_progression(custom_path: String = "") -> bool:
	var target_path := custom_path if not custom_path.strip_edges().is_empty() else save_path
	if not FileAccess.file_exists(target_path):
		reset_progression()
		_loaded_once = true
		return false
	var file := FileAccess.open(target_path, FileAccess.READ)
	if file == null:
		push_warning("MetaProgression: could not read save path %s" % target_path)
		reset_progression()
		_loaded_once = true
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("MetaProgression: invalid save payload at %s" % target_path)
		reset_progression()
		_loaded_once = true
		return false
	apply_save_snapshot(parsed)
	_loaded_once = true
	return true

func record_castle_run_completion(base_currency_reward: int = 1, castle_xp_reward: int = 0, save_now: bool = true) -> Dictionary:
	var reward_summary := {
		"war_table_currency": 0,
		"castle_xp": 0
	}
	if base_currency_reward > 0:
		grant_currency(CURRENCY_WAR_TABLE, base_currency_reward, false)
		reward_summary["war_table_currency"] = base_currency_reward
	if castle_xp_reward > 0 and can_award_castle_xp():
		grant_castle_xp(castle_xp_reward, false)
		reward_summary["castle_xp"] = castle_xp_reward
	if save_now:
		save_progression()
	return reward_summary

func _apply_castle_xp(amount: int) -> void:
	var total_xp := _castle_xp_total + amount
	while total_xp >= _xp_for_next_level(_castle_level):
		total_xp -= _xp_for_next_level(_castle_level)
		_castle_level += 1
		_castle_unspent_points += 1
	_castle_xp_total = total_xp

func _xp_for_next_level(level: int) -> int:
	return 100 + (level * 50)

func _refresh_discovery_cache() -> void:
	for node_id in NODE_ORDER:
		if is_node_visible(node_id):
			_discovered_nodes[node_id] = true

func _flag_dictionary_from_list(values: Variant) -> Dictionary:
	var result: Dictionary = {}
	for item in _get_string_list(values):
		result[item] = true
	return result

func _get_sorted_flag_keys(flags: Dictionary) -> Array:
	var keys: Array = []
	for key in flags.keys():
		if bool(flags[key]):
			keys.append(String(key))
	keys.sort()
	return keys

func _get_string_list(values: Variant) -> Array:
	var result: Array = []
	if values is Array:
		for item in values:
			result.append(String(item))
	elif values is PackedStringArray:
		for item in values:
			result.append(String(item))
	return result

func _coerce_dictionary(value: Variant) -> Dictionary:
	if value is Dictionary:
		return value.duplicate(true)
	return {}
