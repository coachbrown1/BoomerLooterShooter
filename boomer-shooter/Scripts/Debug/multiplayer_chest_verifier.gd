extends Node

const SlotRefScript = preload("res://Scripts/Inventory/slot_ref.gd")

const ARG_VERIFY := "--verify-shared-chest"
const ARG_ROLE := "--verify-role"
const ARG_DIR := "--verify-dir"
const ARG_TIMEOUT := "--verify-timeout"
const POLL_INTERVAL_SEC := 0.2
const DEFAULT_TIMEOUT_SEC := 30.0

var _cfg := {}

func _ready() -> void:
	_cfg = _parse_args(OS.get_cmdline_user_args())
	if not bool(_cfg.get("enabled", false)):
		return
	call_deferred("_run_verification")

func _run_verification() -> void:
	var verify_dir := String(_cfg.get("dir", "")).strip_edges()
	if verify_dir.is_empty():
		push_error("MultiplayerChestVerifier: missing verify dir.")
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(verify_dir)

	var role := String(_cfg.get("role", ""))
	var timeout_sec := float(_cfg.get("timeout_sec", DEFAULT_TIMEOUT_SEC))
	var chest: Node = await _wait_for_chest(timeout_sec)
	if chest == null:
		_write_json_file(_path_in_dir("error.json"), {"role": role, "error": "chest_not_found"})
		get_tree().quit(3)
		return

	var inventory_system: InventorySystem = await _wait_for_inventory_system(timeout_sec)
	if inventory_system == null:
		_write_json_file(_path_in_dir("error.json"), {"role": role, "error": "inventory_not_found"})
		get_tree().quit(4)
		return

	match role:
		"host":
			await _run_host(chest, inventory_system, timeout_sec)
		"client":
			await _run_client(chest, inventory_system, timeout_sec)
		_:
			_write_json_file(_path_in_dir("error.json"), {"role": role, "error": "invalid_role"})
			get_tree().quit(5)

func _run_host(chest: Node, inventory_system, timeout_sec: float) -> void:
	var opened: bool = await _open_chest_and_wait(chest, inventory_system, timeout_sec)
	if not opened:
		_write_json_file(_path_in_dir("host_error.json"), _build_open_failure_payload("host_failed_to_open_chest", chest, inventory_system))
		get_tree().quit(6)
		return

	var initial_ids := _get_chest_item_ids(inventory_system)
	_write_json_file(_path_in_dir("host_initial.json"), {"items": initial_ids})

	if not await _wait_for_file(_path_in_dir("client_ready.flag"), timeout_sec):
		_write_json_file(_path_in_dir("host_error.json"), {"error": "client_not_ready"})
		get_tree().quit(7)
		return

	var chest_index := _find_first_non_empty_chest_index(inventory_system)
	var storage_index := _find_first_empty_storage_index(inventory_system)
	if chest_index < 0 or storage_index < 0:
		_write_json_file(_path_in_dir("host_error.json"), {"error": "no_transfer_slot", "chest_index": chest_index, "storage_index": storage_index})
		get_tree().quit(8)
		return

	var moved: bool = inventory_system.try_move_item(SlotRefScript.chest(chest_index), SlotRefScript.storage(storage_index))
	if not moved:
		_write_json_file(_path_in_dir("host_error.json"), {"error": "move_failed", "chest_index": chest_index, "storage_index": storage_index})
		get_tree().quit(9)
		return

	await get_tree().create_timer(1.0).timeout
	var after_ids := _get_chest_item_ids(inventory_system)
	_write_json_file(_path_in_dir("host_after.json"), {"items": after_ids})

	if not await _wait_for_file(_path_in_dir("client_after.json"), timeout_sec):
		_write_json_file(_path_in_dir("host_error.json"), {"error": "client_after_missing"})
		get_tree().quit(10)
		return

	get_tree().quit(0)

func _run_client(chest: Node, inventory_system, timeout_sec: float) -> void:
	if not await _wait_for_file(_path_in_dir("host_initial.json"), timeout_sec):
		_write_json_file(_path_in_dir("client_error.json"), {"error": "host_initial_missing"})
		get_tree().quit(11)
		return

	var opened: bool = await _open_chest_and_wait(chest, inventory_system, timeout_sec)
	if not opened:
		_write_json_file(_path_in_dir("client_error.json"), _build_open_failure_payload("client_failed_to_open_chest", chest, inventory_system))
		get_tree().quit(12)
		return

	var initial_ids := _get_chest_item_ids(inventory_system)
	_write_json_file(_path_in_dir("client_initial.json"), {"items": initial_ids})
	_touch_file(_path_in_dir("client_ready.flag"))

	if not await _wait_for_file(_path_in_dir("host_after.json"), timeout_sec):
		_write_json_file(_path_in_dir("client_error.json"), {"error": "host_after_missing"})
		get_tree().quit(13)
		return

	var host_after: Dictionary = _read_json_file(_path_in_dir("host_after.json"))
	var expected_after: Array = host_after.get("items", [])
	var synced: bool = await _wait_for_chest_ids(inventory_system, expected_after, timeout_sec)
	if not synced:
		_write_json_file(_path_in_dir("client_error.json"), {"error": "client_sync_timeout", "expected": expected_after, "actual": _get_chest_item_ids(inventory_system)})
		get_tree().quit(14)
		return

	_write_json_file(_path_in_dir("client_after.json"), {"items": _get_chest_item_ids(inventory_system)})
	get_tree().quit(0)

func _open_chest_and_wait(chest: Node, inventory_system, timeout_sec: float) -> bool:
	var dungeon_manager := get_parent()
	if dungeon_manager == null:
		return false
	var local_player: Node = _find_local_player()
	if local_player == null:
		return false
	dungeon_manager.call("request_interaction", local_player, chest)
	return await _wait_for_condition(func() -> bool:
		return inventory_system.is_inventory_open() and inventory_system.get_active_chest_path() == String(chest.get_path()) and _find_first_non_empty_chest_index(inventory_system) >= 0
	, timeout_sec)

func _wait_for_chest(timeout_sec: float):
	var found: bool = await _wait_for_condition(func() -> bool:
		return get_tree().get_nodes_in_group("interactable_chest").size() > 0
	, timeout_sec)
	if not found:
		return null
	var chests := get_tree().get_nodes_in_group("interactable_chest")
	chests.sort_custom(func(a, b): return String(a.get_path()) < String(b.get_path()))
	return chests[0]

func _wait_for_inventory_system(timeout_sec: float):
	var found: bool = await _wait_for_condition(func() -> bool:
		var player: Node = _find_local_player()
		return player != null and player.get("inventory_system") != null
	, timeout_sec)
	if not found:
		return null
	var local_player: Node = _find_local_player()
	var inventory_variant: Variant = local_player.get("inventory_system")
	if inventory_variant is InventorySystem:
		return inventory_variant
	return null

func _find_local_player():
	for node_variant in get_tree().get_nodes_in_group("player"):
		if not (node_variant is Node):
			continue
		var player: Node = node_variant
		if player.has_method("is_local_controlled") and bool(player.call("is_local_controlled")):
			return player
	return null

func _wait_for_condition(predicate: Callable, timeout_sec: float) -> bool:
	var start_ms := Time.get_ticks_msec()
	while float(Time.get_ticks_msec() - start_ms) * 0.001 <= timeout_sec:
		if bool(predicate.call()):
			return true
		await get_tree().create_timer(POLL_INTERVAL_SEC).timeout
	return false

func _wait_for_file(path: String, timeout_sec: float) -> bool:
	return await _wait_for_condition(func() -> bool:
		return FileAccess.file_exists(path)
	, timeout_sec)

func _wait_for_chest_ids(inventory_system, expected: Array, timeout_sec: float) -> bool:
	return await _wait_for_condition(func() -> bool:
		return _get_chest_item_ids(inventory_system) == expected
	, timeout_sec)

func _get_chest_item_ids(inventory_system) -> Array:
	var snapshot: Dictionary = inventory_system.get_slot_snapshot()
	var ids: Array = []
	for item_variant in snapshot.get("chest", []):
		if item_variant == null:
			ids.append("")
			continue
		ids.append(String(item_variant.get("item_id", "")))
	return ids

func _find_first_non_empty_chest_index(inventory_system) -> int:
	var snapshot: Dictionary = inventory_system.get_slot_snapshot()
	var chest_items: Array = snapshot.get("chest", [])
	for i in range(chest_items.size()):
		if chest_items[i] != null:
			return i
	return -1

func _find_first_empty_storage_index(inventory_system) -> int:
	var snapshot: Dictionary = inventory_system.get_slot_snapshot()
	var storage_items: Array = snapshot.get("storage", [])
	for i in range(storage_items.size()):
		if storage_items[i] == null:
			return i
	return -1

func _path_in_dir(file_name: String) -> String:
	return "%s/%s" % [String(_cfg.get("dir", "")), file_name]

func _build_open_failure_payload(error_code: String, chest: Node, inventory_system: InventorySystem) -> Dictionary:
	var local_player: Node = _find_local_player()
	var snapshot: Dictionary = {}
	if inventory_system != null:
		snapshot = inventory_system.get_slot_snapshot()
	return {
		"error": error_code,
		"local_player_path": "" if local_player == null else String(local_player.get_path()),
		"expected_chest_path": "" if chest == null else String(chest.get_path()),
		"inventory_open": false if inventory_system == null else inventory_system.is_inventory_open(),
		"active_chest_path": "" if inventory_system == null else inventory_system.get_active_chest_path(),
		"chest_item_ids": [] if snapshot.is_empty() else _get_chest_item_ids(inventory_system),
	}

func _touch_file(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return
	file.store_string("ready")
	file.flush()
	file.close()

func _write_json_file(path: String, data: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(data))
	file.flush()
	file.close()

func _read_json_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed

func _parse_args(args: PackedStringArray) -> Dictionary:
	var out := {
		"enabled": false,
		"role": "",
		"dir": "",
		"timeout_sec": DEFAULT_TIMEOUT_SEC
	}
	var i := 0
	while i < args.size():
		var key := String(args[i])
		if key == ARG_VERIFY:
			if i + 1 < args.size():
				var value := String(args[i + 1]).to_lower()
				out["enabled"] = value == "1" or value == "true"
				i += 2
				continue
		elif key == ARG_ROLE and i + 1 < args.size():
			out["role"] = String(args[i + 1]).to_lower()
			i += 2
			continue
		elif key == ARG_DIR and i + 1 < args.size():
			out["dir"] = String(args[i + 1])
			i += 2
			continue
		elif key == ARG_TIMEOUT and i + 1 < args.size():
			out["timeout_sec"] = maxf(5.0, float(args[i + 1]))
			i += 2
			continue
		i += 1
	return out
