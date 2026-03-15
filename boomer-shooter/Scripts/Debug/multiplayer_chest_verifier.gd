extends Node

const SlotRefScript = preload("res://Scripts/Inventory/slot_ref.gd")

const ARG_VERIFY := "--verify-shared-chest"
const ARG_SCENARIO := "--verify-scenario"
const ARG_ROLE := "--verify-role"
const ARG_DIR := "--verify-dir"
const ARG_TIMEOUT := "--verify-timeout"
const POLL_INTERVAL_SEC := 0.2
const DEFAULT_TIMEOUT_SEC := 30.0
const DEFAULT_SETTLE_TIME_SEC := 4.0
const DEFAULT_MAX_DROP := 3.0
const DEFAULT_FINAL_DROP := 1.5
const DEFAULT_POSITION_TOLERANCE := 0.45
const DEFAULT_MOVEMENT_DELTA := Vector3(0.75, 0.0, 0.0)

var _cfg := {}

func _ready() -> void:
	_cfg = _parse_args(OS.get_cmdline_user_args())
	if not bool(_cfg.get("enabled", false)):
		return
	call_deferred("_run_verification")

func _run_verification() -> void:
	var verify_dir := String(_cfg.get("dir", "")).strip_edges()
	if verify_dir.is_empty():
		push_error("MultiplayerVerifier: missing verify dir.")
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(verify_dir)

	var scenario := String(_cfg.get("scenario", "shared-chest"))
	match scenario:
		"shared-chest":
			await _run_shared_chest_verification()
		"spawn-floor-stability":
			await _run_spawn_floor_stability_verification()
		"player-replication":
			await _run_player_replication_verification()
		"door-replication":
			await _run_door_replication_verification()
		"weapon-state-sync":
			await _run_weapon_state_sync_verification()
		"weapon-visual-replication":
			await _run_weapon_visual_replication_verification()
		_:
			_write_json_file(_path_in_dir("error.json"), {"role": _get_role(), "error": "invalid_scenario", "scenario": scenario})
			get_tree().quit(5)

func _run_shared_chest_verification() -> void:
	var role := _get_role()
	var timeout_sec := _get_timeout_sec()
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
			await _run_shared_chest_host(chest, inventory_system, timeout_sec)
		"client":
			await _run_shared_chest_client(chest, inventory_system, timeout_sec)
		_:
			_write_json_file(_path_in_dir("error.json"), {"role": role, "error": "invalid_role"})
			get_tree().quit(5)

func _run_shared_chest_host(chest: Node, inventory_system: InventorySystem, timeout_sec: float) -> void:
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

func _run_shared_chest_client(chest: Node, inventory_system: InventorySystem, timeout_sec: float) -> void:
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

func _run_spawn_floor_stability_verification() -> void:
	var role := _get_role()
	var timeout_sec := _get_timeout_sec()
	var settle_time_sec := float(_cfg.get("settle_time_sec", DEFAULT_SETTLE_TIME_SEC))
	var player: Node = await _wait_for_local_player(timeout_sec)
	if player == null:
		_write_json_file(_path_in_dir("%s_spawn_floor.json" % role), {"role": role, "error": "local_player_not_found", "passed": false})
		get_tree().quit(21)
		return

	var started_on_floor := false
	if player is CharacterBody3D:
		started_on_floor = (player as CharacterBody3D).is_on_floor()
	var snapshot := await _capture_spawn_floor_snapshot(player, settle_time_sec)
	snapshot["role"] = role
	snapshot["scenario"] = "spawn-floor-stability"
	snapshot["started_on_floor"] = started_on_floor
	snapshot["passed"] = _is_spawn_floor_snapshot_passing(snapshot)
	var output_name := "%s_spawn_floor.json" % role
	_write_json_file(_path_in_dir(output_name), snapshot)

	match role:
		"host":
			if not await _wait_for_file(_path_in_dir("client_spawn_floor_done.flag"), timeout_sec):
				_write_json_file(_path_in_dir("host_spawn_floor_error.json"), {"role": role, "error": "client_spawn_floor_result_missing"})
				get_tree().quit(22)
				return
		"client":
			_touch_file(_path_in_dir("client_spawn_floor_done.flag"))
		_:
			_write_json_file(_path_in_dir("error.json"), {"role": role, "error": "invalid_role"})
			get_tree().quit(5)
			return

	if bool(snapshot.get("passed", false)):
		get_tree().quit(0)
		return
	get_tree().quit(23 if role == "client" else 24)

func _run_player_replication_verification() -> void:
	var role := _get_role()
	var timeout_sec := _get_timeout_sec()
	var local_player: Node = await _wait_for_local_player(timeout_sec)
	if local_player == null:
		_write_json_file(_path_in_dir("%s_player_replication_error.json" % role), {"role": role, "error": "local_player_not_found"})
		get_tree().quit(31)
		return

	var roster_ok := await _wait_for_condition(func() -> bool:
		return _get_network_players().size() >= 2 and _find_remote_player() != null
	, timeout_sec)
	if not roster_ok:
		_write_json_file(_path_in_dir("%s_player_replication_error.json" % role), {"role": role, "error": "roster_incomplete"})
		get_tree().quit(32)
		return

	var roster_snapshot := _build_player_roster_snapshot()
	var roster_path := _path_in_dir("%s_player_roster.json" % role)
	_write_json_file(roster_path, roster_snapshot)
	_touch_file(_path_in_dir("%s_player_roster_ready.flag" % role))

	var other_role := "client" if role == "host" else "host"
	if not await _wait_for_file(_path_in_dir("%s_player_roster_ready.flag" % other_role), timeout_sec):
		_write_json_file(_path_in_dir("%s_player_replication_error.json" % role), {"role": role, "error": "peer_roster_missing"})
		get_tree().quit(33)
		return

	match role:
		"client":
			await _run_player_replication_client(local_player, timeout_sec)
		"host":
			await _run_player_replication_host(local_player, timeout_sec)
		_:
			_write_json_file(_path_in_dir("error.json"), {"role": role, "error": "invalid_role"})
			get_tree().quit(5)

func _run_player_replication_client(local_player: Node, timeout_sec: float) -> void:
	var client_target: Vector3 = local_player.global_position + DEFAULT_MOVEMENT_DELTA
	_force_player_position(local_player, client_target)
	_write_json_file(_path_in_dir("client_movement_target.json"), {"target_position": _vec3_to_dict(client_target)})

	if not await _wait_for_file(_path_in_dir("host_client_replication_done.flag"), timeout_sec):
		_write_json_file(_path_in_dir("client_player_replication_error.json"), {"role": "client", "error": "host_client_validation_missing"})
		get_tree().quit(34)
		return

	if not await _wait_for_file(_path_in_dir("host_movement_target.json"), timeout_sec):
		_write_json_file(_path_in_dir("client_player_replication_error.json"), {"role": "client", "error": "host_target_missing"})
		get_tree().quit(35)
		return

	var host_target_data := _read_json_file(_path_in_dir("host_movement_target.json"))
	var expected_host_target := _dict_to_vec3(host_target_data.get("target_position", {}))
	var remote_player: Node = _find_remote_player()
	if remote_player == null:
		_write_json_file(_path_in_dir("client_player_replication_error.json"), {"role": "client", "error": "remote_player_missing"})
		get_tree().quit(36)
		return

	var synced := await _wait_for_player_position(remote_player, expected_host_target, timeout_sec)
	var result := {
		"role": "client",
		"passed": synced,
		"expected_host_position": _vec3_to_dict(expected_host_target),
		"actual_remote_position": _vec3_to_dict(remote_player.global_position),
		"distance_to_expected": remote_player.global_position.distance_to(expected_host_target),
	}
	_write_json_file(_path_in_dir("client_host_replication.json"), result)
	_touch_file(_path_in_dir("client_host_replication_done.flag"))

	if synced:
		get_tree().quit(0)
		return
	get_tree().quit(37)

func _run_player_replication_host(local_player: Node, timeout_sec: float) -> void:
	if not await _wait_for_file(_path_in_dir("client_movement_target.json"), timeout_sec):
		_write_json_file(_path_in_dir("host_player_replication_error.json"), {"role": "host", "error": "client_target_missing"})
		get_tree().quit(38)
		return

	var client_target_data := _read_json_file(_path_in_dir("client_movement_target.json"))
	var expected_client_target := _dict_to_vec3(client_target_data.get("target_position", {}))
	var remote_player: Node = _find_remote_player()
	if remote_player == null:
		_write_json_file(_path_in_dir("host_player_replication_error.json"), {"role": "host", "error": "remote_player_missing"})
		get_tree().quit(39)
		return

	var synced_client := await _wait_for_player_position(remote_player, expected_client_target, timeout_sec)
	_write_json_file(_path_in_dir("host_client_replication.json"), {
		"role": "host",
		"passed": synced_client,
		"expected_client_position": _vec3_to_dict(expected_client_target),
		"actual_remote_position": _vec3_to_dict(remote_player.global_position),
		"distance_to_expected": remote_player.global_position.distance_to(expected_client_target),
	})
	_touch_file(_path_in_dir("host_client_replication_done.flag"))
	if not synced_client:
		get_tree().quit(40)
		return

	var host_target: Vector3 = local_player.global_position + Vector3(0.0, 0.0, DEFAULT_MOVEMENT_DELTA.x)
	_force_player_position(local_player, host_target)
	_write_json_file(_path_in_dir("host_movement_target.json"), {"target_position": _vec3_to_dict(host_target)})

	if not await _wait_for_file(_path_in_dir("client_host_replication_done.flag"), timeout_sec):
		_write_json_file(_path_in_dir("host_player_replication_error.json"), {"role": "host", "error": "client_host_validation_missing"})
		get_tree().quit(41)
		return

	get_tree().quit(0)

func _run_door_replication_verification() -> void:
	var role := _get_role()
	var timeout_sec := _get_timeout_sec()
	var local_player: Node = await _wait_for_local_player(timeout_sec)
	if local_player == null:
		_write_json_file(_path_in_dir("%s_door_replication_error.json" % role), {"role": role, "error": "local_player_not_found"})
		get_tree().quit(42)
		return

	var door: DungeonDoor = await _wait_for_closed_door(timeout_sec)
	if door == null:
		_write_json_file(_path_in_dir("%s_door_replication_error.json" % role), {"role": role, "error": "closed_door_not_found"})
		get_tree().quit(43)
		return

	if role == "client":
		_write_json_file(_path_in_dir("client_door_selected.json"), {
			"role": role,
			"door_path": String(door.get_path()),
			"door_position": _vec3_to_dict(door.global_position),
		})
		_touch_file(_path_in_dir("client_door_selected.flag"))
		var dungeon_manager := get_parent()
		if dungeon_manager == null:
			_write_json_file(_path_in_dir("client_door_replication_error.json"), {"role": role, "error": "dungeon_manager_missing"})
			get_tree().quit(45)
			return
		dungeon_manager.call("request_interaction", local_player, door)
	else:
		if not await _wait_for_file(_path_in_dir("client_door_selected.flag"), timeout_sec):
			_write_json_file(_path_in_dir("host_door_replication_error.json"), {"role": role, "error": "client_door_selection_missing"})
			get_tree().quit(44)
			return
		var selected := _read_json_file(_path_in_dir("client_door_selected.json"))
		var selected_pos := _dict_to_vec3(selected.get("door_position", {}))
		var matched_door: DungeonDoor = _find_door_by_position(selected_pos)
		if matched_door == null:
			_write_json_file(_path_in_dir("host_door_replication_error.json"), {"role": role, "error": "host_door_match_missing", "selected_position": _vec3_to_dict(selected_pos)})
			get_tree().quit(49)
			return
		door = matched_door

	var opened := await _wait_for_condition(func() -> bool:
		return is_instance_valid(door) and door.is_open
	, timeout_sec)
	var result := {
		"role": role,
		"passed": opened,
		"door_path": String(door.get_path()),
		"door_position": _vec3_to_dict(door.global_position),
		"is_open": false if not is_instance_valid(door) else door.is_open,
	}
	_write_json_file(_path_in_dir("%s_door_replication.json" % role), result)
	_touch_file(_path_in_dir("%s_door_replication_done.flag" % role))

	if role == "host":
		if not await _wait_for_file(_path_in_dir("client_door_replication_done.flag"), timeout_sec):
			_write_json_file(_path_in_dir("host_door_replication_error.json"), {"role": role, "error": "client_door_result_missing"})
			get_tree().quit(46)
			return
	if opened:
		get_tree().quit(0)
		return
	get_tree().quit(47 if role == "client" else 48)

func _run_weapon_state_sync_verification() -> void:
	var role := _get_role()
	var timeout_sec := _get_timeout_sec()
	var local_player: Node = await _wait_for_local_player(timeout_sec)
	if local_player == null:
		_write_json_file(_path_in_dir("%s_weapon_state_error.json" % role), {"role": role, "error": "local_player_not_found"})
		get_tree().quit(50)
		return

	var roster_ok := await _wait_for_condition(func() -> bool:
		return _find_remote_player() != null
	, timeout_sec)
	if not roster_ok:
		_write_json_file(_path_in_dir("%s_weapon_state_error.json" % role), {"role": role, "error": "remote_player_not_found"})
		get_tree().quit(51)
		return

	var manager: WeaponManager = local_player.get("weapon_manager")
	if manager == null or manager.get_current_weapon() == null:
		_write_json_file(_path_in_dir("%s_weapon_state_error.json" % role), {"role": role, "error": "local_weapon_missing"})
		get_tree().quit(52)
		return

	_touch_file(_path_in_dir("%s_weapon_ready.flag" % role))
	var other_role := "client" if role == "host" else "host"
	if not await _wait_for_file(_path_in_dir("%s_weapon_ready.flag" % other_role), timeout_sec):
		_write_json_file(_path_in_dir("%s_weapon_state_error.json" % role), {"role": role, "error": "peer_weapon_ready_missing"})
		get_tree().quit(53)
		return

	match role:
		"client":
			await _run_weapon_state_sync_client(local_player, manager, timeout_sec)
		"host":
			await _run_weapon_state_sync_host(local_player, timeout_sec)
		_:
			_write_json_file(_path_in_dir("error.json"), {"role": role, "error": "invalid_role"})
			get_tree().quit(5)

func _run_weapon_visual_replication_verification() -> void:
	var role := _get_role()
	var timeout_sec := _get_timeout_sec()
	var local_player: Node = await _wait_for_local_player(timeout_sec)
	if local_player == null:
		_write_json_file(_path_in_dir("%s_weapon_visual_error.json" % role), {"role": role, "error": "local_player_not_found"})
		get_tree().quit(68)
		return
	var dungeon_manager := get_parent()
	if dungeon_manager == null:
		_write_json_file(_path_in_dir("%s_weapon_visual_error.json" % role), {"role": role, "error": "dungeon_manager_missing"})
		get_tree().quit(69)
		return
	_touch_file(_path_in_dir("%s_weapon_visual_ready.flag" % role))
	var other_role := "client" if role == "host" else "host"
	if not await _wait_for_file(_path_in_dir("%s_weapon_visual_ready.flag" % other_role), timeout_sec):
		_write_json_file(_path_in_dir("%s_weapon_visual_error.json" % role), {"role": role, "error": "peer_ready_missing"})
		get_tree().quit(70)
		return

	if role == "host":
		var manager: WeaponManager = local_player.get("weapon_manager")
		if manager == null:
			_write_json_file(_path_in_dir("host_weapon_visual_error.json"), {"role": role, "error": "weapon_manager_missing"})
			get_tree().quit(71)
			return
		if not _switch_weapon_by_key(manager, "rifle"):
			_write_json_file(_path_in_dir("host_weapon_visual_error.json"), {"role": role, "error": "rifle_missing"})
			get_tree().quit(72)
			return
		var rifle: Weapon = manager.get_current_weapon()
		rifle.fire()
		_touch_file(_path_in_dir("host_hitscan_fired.flag"))

		await get_tree().create_timer(0.3).timeout
		if not _switch_weapon_by_key(manager, "fireball"):
			_write_json_file(_path_in_dir("host_weapon_visual_error.json"), {"role": role, "error": "fireball_missing"})
			get_tree().quit(73)
			return
		var fireball: Weapon = manager.get_current_weapon()
		fireball.fire()
		_touch_file(_path_in_dir("host_projectile_fired.flag"))

		if not await _wait_for_file(_path_in_dir("client_weapon_visual_done.flag"), timeout_sec):
			_write_json_file(_path_in_dir("host_weapon_visual_error.json"), {"role": role, "error": "client_result_missing"})
			get_tree().quit(74)
			return
		get_tree().quit(0)
		return

	if not await _wait_for_file(_path_in_dir("host_hitscan_fired.flag"), timeout_sec):
		_write_json_file(_path_in_dir("client_weapon_visual_error.json"), {"role": role, "error": "host_hitscan_missing"})
		get_tree().quit(75)
		return
	var hitscan_seen := await _wait_for_network_visual_count(dungeon_manager, "hitscan", 1, timeout_sec)
	if not await _wait_for_file(_path_in_dir("host_projectile_fired.flag"), timeout_sec):
		_write_json_file(_path_in_dir("client_weapon_visual_error.json"), {"role": role, "error": "host_projectile_missing"})
		get_tree().quit(76)
		return
	var projectile_seen := await _wait_for_network_visual_count(dungeon_manager, "projectile", 1, timeout_sec)
	var counts := {}
	if dungeon_manager.has_method("get_debug_network_visual_counts"):
		counts = dungeon_manager.call("get_debug_network_visual_counts")
	var result := {
		"role": role,
		"passed": hitscan_seen and projectile_seen,
		"hitscan_seen": hitscan_seen,
		"projectile_seen": projectile_seen,
		"counts": counts,
	}
	_write_json_file(_path_in_dir("client_weapon_visuals.json"), result)
	_touch_file(_path_in_dir("client_weapon_visual_done.flag"))
	if hitscan_seen and projectile_seen:
		get_tree().quit(0)
		return
	get_tree().quit(77)

func _run_weapon_state_sync_client(local_player: Node, manager: WeaponManager, timeout_sec: float) -> void:
	var local_weapon: Weapon = _select_finite_ammo_weapon(manager)
	if local_weapon == null:
		_write_json_file(_path_in_dir("client_weapon_state_error.json"), {"role": "client", "error": "finite_ammo_weapon_missing"})
		get_tree().quit(54)
		return
	var initial_mag := local_weapon.current_mag
	var shot_count := mini(1, initial_mag)
	if shot_count <= 0:
		_write_json_file(_path_in_dir("client_weapon_state_error.json"), {"role": "client", "error": "no_ammo_to_fire"})
		get_tree().quit(55)
		return
	_write_json_file(_path_in_dir("client_weapon_selected.json"), {
		"role": "client",
		"weapon_key": manager.get_current_weapon_key(),
		"initial_mag": initial_mag,
		"shot_count": shot_count,
		"expected_fire_mag": initial_mag - shot_count,
		"expected_reload_mag": local_weapon.get_effective_mag_size() if local_weapon.has_method("get_effective_mag_size") else local_weapon.mag_size,
	})
	_touch_file(_path_in_dir("client_weapon_selected.flag"))
	for i in range(shot_count):
		local_weapon.call("_request_host_fire")
		await get_tree().create_timer(0.25).timeout
	_touch_file(_path_in_dir("client_weapon_fire_sent.flag"))

	var expected_after_fire := initial_mag - shot_count
	var fire_result := await _wait_for_weapon_fire_result(manager, expected_after_fire, timeout_sec)
	var fire_synced := bool(fire_result.get("passed", false))
	_write_json_file(_path_in_dir("client_weapon_after_fire.json"), {
		"role": "client",
		"passed": fire_synced,
		"initial_mag": initial_mag,
		"shot_count": shot_count,
		"expected_mag": expected_after_fire,
		"actual_mag": -1 if manager.get_current_weapon() == null else manager.get_current_weapon().current_mag,
		"host_observed_mag": int(fire_result.get("host_observed_mag", -1)),
		"host_passed": bool(fire_result.get("host_passed", false)),
	})
	_touch_file(_path_in_dir("client_weapon_after_fire.flag"))
	if not fire_synced:
		get_tree().quit(56)
		return
	if not await _wait_for_file(_path_in_dir("host_weapon_after_fire.flag"), timeout_sec):
		_write_json_file(_path_in_dir("client_weapon_state_error.json"), {"role": "client", "error": "host_fire_result_missing"})
		get_tree().quit(66)
		return
	var host_fire := _read_json_file(_path_in_dir("host_weapon_after_fire.json"))
	if not bool(host_fire.get("passed", false)):
		_write_json_file(_path_in_dir("client_weapon_state_error.json"), {
			"role": "client",
			"error": "host_fire_result_failed",
			"host_actual_mag": int(host_fire.get("actual_mag", -1)),
			"host_expected_mag": int(host_fire.get("expected_mag", -1)),
		})
		get_tree().quit(67)
		return

	local_weapon.reload()
	var full_mag := local_weapon.get_effective_mag_size() if local_weapon.has_method("get_effective_mag_size") else local_weapon.mag_size
	var reload_synced := await _wait_for_condition(func() -> bool:
		return manager.get_current_weapon() != null and manager.get_current_weapon().current_mag == full_mag
	, timeout_sec)
	_write_json_file(_path_in_dir("client_weapon_after_reload.json"), {
		"role": "client",
		"passed": reload_synced,
		"expected_mag": full_mag,
		"actual_mag": -1 if manager.get_current_weapon() == null else manager.get_current_weapon().current_mag,
	})
	_touch_file(_path_in_dir("client_weapon_after_reload.flag"))
	if not await _wait_for_file(_path_in_dir("host_weapon_after_reload.flag"), timeout_sec):
		_write_json_file(_path_in_dir("client_weapon_state_error.json"), {"role": "client", "error": "host_reload_result_missing"})
		get_tree().quit(65)
		return

	if reload_synced:
		get_tree().quit(0)
		return
	get_tree().quit(57)

func _run_weapon_state_sync_host(_local_player: Node, timeout_sec: float) -> void:
	var remote_player: Node = _find_remote_player()
	if remote_player == null:
		_write_json_file(_path_in_dir("host_weapon_state_error.json"), {"role": "host", "error": "remote_player_missing"})
		get_tree().quit(58)
		return
	var remote_manager: WeaponManager = remote_player.get("weapon_manager")
	if remote_manager == null or remote_manager.get_current_weapon() == null:
		_write_json_file(_path_in_dir("host_weapon_state_error.json"), {"role": "host", "error": "remote_weapon_missing"})
		get_tree().quit(59)
		return

	if not await _wait_for_file(_path_in_dir("client_weapon_selected.flag"), timeout_sec):
		_write_json_file(_path_in_dir("host_weapon_state_error.json"), {"role": "host", "error": "client_weapon_selection_missing"})
		get_tree().quit(64)
		return
	var selected_weapon := _read_json_file(_path_in_dir("client_weapon_selected.json"))
	var initial_mag := int(selected_weapon.get("initial_mag", remote_manager.get_current_weapon().current_mag))
	if not await _wait_for_file(_path_in_dir("client_weapon_fire_sent.flag"), timeout_sec):
		_write_json_file(_path_in_dir("host_weapon_state_error.json"), {"role": "host", "error": "client_fire_sent_missing"})
		get_tree().quit(60)
		return

	var expected_after_fire := int(selected_weapon.get("expected_fire_mag", initial_mag))
	var fire_synced := await _wait_for_condition(func() -> bool:
		return remote_manager.get_current_weapon() != null and remote_manager.get_current_weapon().current_mag == expected_after_fire
	, timeout_sec)
	_write_json_file(_path_in_dir("host_weapon_after_fire.json"), {
		"role": "host",
		"passed": fire_synced,
		"initial_mag": initial_mag,
		"expected_mag": expected_after_fire,
		"actual_mag": -1 if remote_manager.get_current_weapon() == null else remote_manager.get_current_weapon().current_mag,
	})
	_touch_file(_path_in_dir("host_weapon_after_fire.flag"))
	if not fire_synced:
		get_tree().quit(61)
		return

	if not await _wait_for_file(_path_in_dir("client_weapon_after_reload.flag"), timeout_sec):
		_write_json_file(_path_in_dir("host_weapon_state_error.json"), {"role": "host", "error": "client_reload_result_missing"})
		get_tree().quit(62)
		return

	var client_reload := _read_json_file(_path_in_dir("client_weapon_after_reload.json"))
	var expected_after_reload := int(client_reload.get("expected_mag", int(selected_weapon.get("expected_reload_mag", expected_after_fire))))
	var reload_synced := await _wait_for_condition(func() -> bool:
		return remote_manager.get_current_weapon() != null and remote_manager.get_current_weapon().current_mag == expected_after_reload
	, timeout_sec)
	_write_json_file(_path_in_dir("host_weapon_after_reload.json"), {
		"role": "host",
		"passed": reload_synced,
		"expected_mag": expected_after_reload,
		"actual_mag": -1 if remote_manager.get_current_weapon() == null else remote_manager.get_current_weapon().current_mag,
	})
	_touch_file(_path_in_dir("host_weapon_after_reload.flag"))

	if reload_synced:
		get_tree().quit(0)
		return
	get_tree().quit(63)

func _capture_spawn_floor_snapshot(player: Node, duration_sec: float) -> Dictionary:
	var sample_count := 0
	var initial_pos: Vector3 = player.global_position
	var min_y: float = initial_pos.y
	var max_y: float = initial_pos.y
	var final_pos: Vector3 = initial_pos
	var any_on_floor := false
	var max_downward_velocity := 0.0
	var floor_contact_samples := 0
	var last_velocity_y := 0.0
	var start_ms := Time.get_ticks_msec()

	while float(Time.get_ticks_msec() - start_ms) * 0.001 <= duration_sec:
		if not is_instance_valid(player):
			return {
				"error": "player_freed_during_sampling",
				"sample_count": sample_count,
			}
		final_pos = player.global_position
		min_y = minf(min_y, final_pos.y)
		max_y = maxf(max_y, final_pos.y)
		sample_count += 1

		if player is CharacterBody3D:
			var body := player as CharacterBody3D
			last_velocity_y = body.velocity.y
			max_downward_velocity = minf(max_downward_velocity, body.velocity.y)
			if body.is_on_floor():
				any_on_floor = true
				floor_contact_samples += 1

		await get_tree().create_timer(POLL_INTERVAL_SEC).timeout

	return {
		"sample_count": sample_count,
		"initial_position": _vec3_to_dict(initial_pos),
		"final_position": _vec3_to_dict(final_pos),
		"min_y": min_y,
		"max_y": max_y,
		"drop_distance": initial_pos.y - min_y,
		"final_drop_distance": initial_pos.y - final_pos.y,
		"any_on_floor": any_on_floor,
		"floor_contact_samples": floor_contact_samples,
		"last_velocity_y": last_velocity_y,
		"max_downward_velocity": max_downward_velocity,
		"duration_sec": duration_sec,
		"local_peer_id": _get_local_peer_id(),
		"player_peer_id": _get_player_peer_id(player),
	}

func _build_player_roster_snapshot() -> Dictionary:
	var players: Array = []
	for player_variant in _get_network_players():
		if not (player_variant is Node):
			continue
		var player: Node = player_variant
		players.append({
			"peer_id": _get_player_peer_id(player),
			"is_local_controlled": player.has_method("is_local_controlled") and bool(player.call("is_local_controlled")),
			"position": _vec3_to_dict(player.global_position),
		})
	players.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("peer_id", 0)) < int(b.get("peer_id", 0))
	)
	return {
		"role": _get_role(),
		"local_peer_id": _get_local_peer_id(),
		"players": players,
	}

func _is_spawn_floor_snapshot_passing(snapshot: Dictionary) -> bool:
	if snapshot.has("error"):
		return false
	if int(snapshot.get("sample_count", 0)) <= 0:
		return false
	if int(snapshot.get("player_peer_id", 0)) != int(snapshot.get("local_peer_id", 0)):
		return false
	if float(snapshot.get("drop_distance", 999.0)) > DEFAULT_MAX_DROP:
		return false
	if float(snapshot.get("final_drop_distance", 999.0)) > DEFAULT_FINAL_DROP:
		return false
	if not bool(snapshot.get("any_on_floor", false)):
		return false
	if float(snapshot.get("max_downward_velocity", 0.0)) < -25.0:
		return false
	return true

func _open_chest_and_wait(chest: Node, inventory_system: InventorySystem, timeout_sec: float) -> bool:
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

func _wait_for_local_player(timeout_sec: float):
	var found: bool = await _wait_for_condition(func() -> bool:
		var local_player: Node = _find_local_player()
		if local_player == null:
			return false
		return _get_player_peer_id(local_player) == _get_local_peer_id()
	, timeout_sec)
	if not found:
		return null
	return _find_local_player()

func _wait_for_player_position(player: Node, expected: Vector3, timeout_sec: float) -> bool:
	return await _wait_for_condition(func() -> bool:
		if not is_instance_valid(player):
			return false
		return player.global_position.distance_to(expected) <= DEFAULT_POSITION_TOLERANCE
	, timeout_sec)

func _wait_for_weapon_fire_result(manager: WeaponManager, expected_mag: int, timeout_sec: float) -> Dictionary:
	var start_ms := Time.get_ticks_msec()
	while float(Time.get_ticks_msec() - start_ms) * 0.001 <= timeout_sec:
		if manager.get_current_weapon() != null and manager.get_current_weapon().current_mag == expected_mag:
			return {
				"passed": true,
				"host_passed": false,
				"host_observed_mag": -1,
			}
		if FileAccess.file_exists(_path_in_dir("host_weapon_after_fire.flag")):
			var host_fire := _read_json_file(_path_in_dir("host_weapon_after_fire.json"))
			if not bool(host_fire.get("passed", false)):
				return {
					"passed": false,
					"host_passed": false,
					"host_observed_mag": int(host_fire.get("actual_mag", -1)),
				}
		await get_tree().create_timer(POLL_INTERVAL_SEC).timeout
	return {
		"passed": manager.get_current_weapon() != null and manager.get_current_weapon().current_mag == expected_mag,
		"host_passed": false,
		"host_observed_mag": -1,
	}

func _wait_for_network_visual_count(dungeon_manager: Node, key: String, expected_min: int, timeout_sec: float) -> bool:
	return await _wait_for_condition(func() -> bool:
		if dungeon_manager == null or not dungeon_manager.has_method("get_debug_network_visual_counts"):
			return false
		var counts: Dictionary = dungeon_manager.call("get_debug_network_visual_counts")
		return int(counts.get(key, 0)) >= expected_min
	, timeout_sec)

func _wait_for_closed_door(timeout_sec: float):
	var found: bool = await _wait_for_condition(func() -> bool:
		return _find_closed_door() != null
	, timeout_sec)
	if not found:
		return null
	return _find_closed_door()

func _find_local_player():
	for node_variant in get_tree().get_nodes_in_group("player"):
		if not (node_variant is Node):
			continue
		var player: Node = node_variant
		if player.has_method("is_local_controlled") and bool(player.call("is_local_controlled")):
			return player
	return null

func _find_remote_player():
	var local_peer_id := _get_local_peer_id()
	for node_variant in _get_network_players():
		if not (node_variant is Node):
			continue
		var player: Node = node_variant
		if _get_player_peer_id(player) == local_peer_id:
			continue
		return player
	return null

func _get_network_players() -> Array:
	return get_tree().get_nodes_in_group("player")

func _find_closed_door():
	var doors := get_tree().get_nodes_in_group("dungeon_door")
	doors.sort_custom(func(a, b): return String(a.get_path()) < String(b.get_path()))
	for node_variant in doors:
		if not (node_variant is DungeonDoor):
			continue
		var door: DungeonDoor = node_variant
		if not is_instance_valid(door):
			continue
		if door.is_open:
			continue
		return door
	return null

func _find_door_by_position(world_pos: Vector3, max_distance: float = 2.0):
	var closest: DungeonDoor = null
	var closest_dist_sq := max_distance * max_distance
	for node_variant in get_tree().get_nodes_in_group("dungeon_door"):
		if not (node_variant is DungeonDoor):
			continue
		var door: DungeonDoor = node_variant
		if not is_instance_valid(door):
			continue
		var dist_sq := door.global_position.distance_squared_to(world_pos)
		if dist_sq <= closest_dist_sq:
			closest = door
			closest_dist_sq = dist_sq
	return closest

func _force_player_position(player: Node, target: Vector3) -> void:
	if player == null:
		return
	player.global_position = target
	if player is CharacterBody3D:
		var body := player as CharacterBody3D
		body.velocity = Vector3.ZERO

func _select_finite_ammo_weapon(manager: WeaponManager) -> Weapon:
	if manager == null:
		return null
	for i in range(manager.weapons.size()):
		var candidate = manager.weapons[i]
		if not (candidate is Weapon):
			continue
		var weapon: Weapon = candidate
		if weapon.ammo_type == "none":
			continue
		manager.switch_to_weapon(i)
		return manager.get_current_weapon()
	return null

func _switch_weapon_by_key(manager: WeaponManager, key: String) -> bool:
	if manager == null:
		return false
	if not manager.has_method("switch_to_weapon_by_key"):
		return false
	return bool(manager.call("switch_to_weapon_by_key", key))

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

func _wait_for_chest_ids(inventory_system: InventorySystem, expected: Array, timeout_sec: float) -> bool:
	return await _wait_for_condition(func() -> bool:
		return _get_chest_item_ids(inventory_system) == expected
	, timeout_sec)

func _get_chest_item_ids(inventory_system: InventorySystem) -> Array:
	var snapshot: Dictionary = inventory_system.get_slot_snapshot()
	var ids: Array = []
	for item_variant in snapshot.get("chest", []):
		if item_variant == null:
			ids.append("")
			continue
		ids.append(String(item_variant.get("item_id", "")))
	return ids

func _find_first_non_empty_chest_index(inventory_system: InventorySystem) -> int:
	var snapshot: Dictionary = inventory_system.get_slot_snapshot()
	var chest_items: Array = snapshot.get("chest", [])
	for i in range(chest_items.size()):
		if chest_items[i] != null:
			return i
	return -1

func _find_first_empty_storage_index(inventory_system: InventorySystem) -> int:
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

func _get_role() -> String:
	return String(_cfg.get("role", ""))

func _get_timeout_sec() -> float:
	return float(_cfg.get("timeout_sec", DEFAULT_TIMEOUT_SEC))

func _get_local_peer_id() -> int:
	var session = get_node_or_null("/root/NetworkSession")
	if session == null:
		return 1
	return max(1, int(session.call("get_local_peer_id")))

func _get_player_peer_id(player: Node) -> int:
	if player == null:
		return 0
	if player.has_method("get_network_peer_id"):
		return int(player.call("get_network_peer_id"))
	return int(player.get("network_peer_id"))

func _vec3_to_dict(value: Vector3) -> Dictionary:
	return {
		"x": value.x,
		"y": value.y,
		"z": value.z,
	}

func _dict_to_vec3(value: Variant) -> Vector3:
	if typeof(value) != TYPE_DICTIONARY:
		return Vector3.ZERO
	var data: Dictionary = value
	return Vector3(
		float(data.get("x", 0.0)),
		float(data.get("y", 0.0)),
		float(data.get("z", 0.0))
	)


func _parse_args(args: PackedStringArray) -> Dictionary:
	var out := {
		"enabled": false,
		"scenario": "",
		"role": "",
		"dir": "",
		"timeout_sec": DEFAULT_TIMEOUT_SEC,
		"settle_time_sec": DEFAULT_SETTLE_TIME_SEC,
	}
	var i := 0
	while i < args.size():
		var key := String(args[i])
		if key == ARG_VERIFY:
			if i + 1 < args.size():
				var value := String(args[i + 1]).to_lower()
				out["enabled"] = value == "1" or value == "true"
				if String(out.get("scenario", "")).is_empty():
					out["scenario"] = "shared-chest"
				i += 2
				continue
		elif key == ARG_SCENARIO and i + 1 < args.size():
			out["enabled"] = true
			out["scenario"] = String(args[i + 1]).to_lower()
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
	if bool(out.get("enabled", false)) and String(out.get("scenario", "")).is_empty():
		out["scenario"] = "shared-chest"
	return out
