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
const DEFAULT_MOVEMENT_HOLD_SEC := 0.8

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
	var timeout_sec := _get_timeout_sec()
	if not await _wait_for_world_ready(timeout_sec):
		_write_json_file(_path_in_dir("error.json"), {"role": _get_role(), "error": "world_not_ready"})
		get_tree().quit(6)
		return

	var scenario := String(_cfg.get("scenario", "shared-chest"))
	match scenario:
		"shared-chest":
			await _run_shared_chest_verification()
		"spawn-floor-stability":
			await _run_spawn_floor_stability_verification()
		"player-replication":
			await _run_player_replication_verification()
		"player-health-replication":
			await _run_player_health_replication_verification()
		"client-disconnect":
			await _run_client_disconnect_verification()
		"door-replication":
			await _run_door_replication_verification()
		"weapon-state-sync":
			await _run_weapon_state_sync_verification()
		"weapon-visual-replication":
			await _run_weapon_visual_replication_verification()
		"projectile-damage-replication":
			await _run_projectile_damage_replication_verification()
		"enemy-damage-replication":
			await _run_enemy_damage_replication_verification()
		"enemy-death-replication":
			await _run_enemy_death_replication_verification()
		"enemy-loot-replication":
			await _run_enemy_loot_replication_verification()
		"loot-pickup-sync":
			await _run_loot_pickup_sync_verification()
		"enemy-animation-replication":
			await _run_enemy_animation_replication_verification()
		"mobility-dash-replication":
			await _run_mobility_dash_replication_verification()
		"mobility-grapple-replication":
			await _run_mobility_grapple_replication_verification()
		"mobility-jetpack-replication":
			await _run_mobility_jetpack_replication_verification()
		"long-run-soak":
			await _run_long_run_soak_verification()
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
	call_deferred("_hold_player_position_window", local_player, client_target, DEFAULT_MOVEMENT_HOLD_SEC)
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
	var remote_peer_id := _get_player_peer_id(remote_player)

	var synced := await _wait_for_peer_position(remote_peer_id, expected_host_target, timeout_sec)
	remote_player = _find_player_by_peer_id(remote_peer_id)
	var result := {
		"role": "client",
		"passed": synced,
		"expected_host_position": _vec3_to_dict(expected_host_target),
		"remote_player_present": remote_player != null,
		"actual_remote_position": _vec3_to_dict(remote_player.global_position) if remote_player != null else {},
		"distance_to_expected": remote_player.global_position.distance_to(expected_host_target) if remote_player != null else -1.0,
	}
	_write_json_file(_path_in_dir("client_host_replication.json"), result)
	_touch_file(_path_in_dir("client_host_replication_done.flag"))

	if synced:
		get_tree().quit(0)
		return
	if remote_player == null:
		_write_json_file(_path_in_dir("client_player_replication_error.json"), {"role": "client", "error": "remote_player_lost"})
		get_tree().quit(36)
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
	var remote_peer_id := _get_player_peer_id(remote_player)

	var synced_client := await _wait_for_peer_position(remote_peer_id, expected_client_target, timeout_sec)
	remote_player = _find_player_by_peer_id(remote_peer_id)
	var host_result := {
		"role": "host",
		"passed": synced_client,
		"expected_client_position": _vec3_to_dict(expected_client_target),
		"remote_player_present": remote_player != null,
		"actual_remote_position": _vec3_to_dict(remote_player.global_position) if remote_player != null else {},
		"distance_to_expected": remote_player.global_position.distance_to(expected_client_target) if remote_player != null else -1.0,
	}
	_write_json_file(_path_in_dir("host_client_replication.json"), host_result)
	_touch_file(_path_in_dir("host_client_replication_done.flag"))
	if not synced_client:
		if remote_player == null:
			_write_json_file(_path_in_dir("host_player_replication_error.json"), {"role": "host", "error": "remote_player_lost"})
			get_tree().quit(39)
			return
		get_tree().quit(40)
		return

	var host_target: Vector3 = local_player.global_position + Vector3(0.0, 0.0, DEFAULT_MOVEMENT_DELTA.x)
	_force_player_position(local_player, host_target)
	call_deferred("_hold_player_position_window", local_player, host_target, DEFAULT_MOVEMENT_HOLD_SEC)
	_write_json_file(_path_in_dir("host_movement_target.json"), {"target_position": _vec3_to_dict(host_target)})

	if not await _wait_for_file(_path_in_dir("client_host_replication_done.flag"), timeout_sec):
		_write_json_file(_path_in_dir("host_player_replication_error.json"), {"role": "host", "error": "client_host_validation_missing"})
		get_tree().quit(41)
		return

	get_tree().quit(0)

func _run_player_health_replication_verification() -> void:
	var role := _get_role()
	var timeout_sec := _get_timeout_sec()
	var local_player: Node = await _wait_for_local_player(timeout_sec)
	if local_player == null:
		_write_json_file(_path_in_dir("%s_player_health_error.json" % role), {"role": role, "error": "local_player_not_found"})
		get_tree().quit(110)
		return
	var remote_player: Node = await _wait_for_remote_player(timeout_sec)
	if remote_player == null:
		_write_json_file(_path_in_dir("%s_player_health_error.json" % role), {"role": role, "error": "remote_player_not_found"})
		get_tree().quit(111)
		return
	_touch_file(_path_in_dir("%s_player_health_ready.flag" % role))
	var other_role := "client" if role == "host" else "host"
	if not await _wait_for_file(_path_in_dir("%s_player_health_ready.flag" % other_role), timeout_sec):
		_write_json_file(_path_in_dir("%s_player_health_error.json" % role), {"role": role, "error": "peer_ready_missing"})
		get_tree().quit(112)
		return

	match role:
		"host":
			await _run_player_health_replication_host(remote_player, timeout_sec)
		"client":
			await _run_player_health_replication_client(local_player, remote_player, timeout_sec)
		_:
			_write_json_file(_path_in_dir("error.json"), {"role": role, "error": "invalid_role"})
			get_tree().quit(5)

func _run_player_health_replication_host(remote_player: Node, timeout_sec: float) -> void:
	var damage_timeout := minf(timeout_sec, 8.0)
	var client_timeout := minf(timeout_sec, 20.0)
	var initial_health := int(remote_player.get("current_health"))
	var damage_amount := mini(12, maxi(1, initial_health - 1))
	if damage_amount <= 0:
		_write_json_file(_path_in_dir("host_player_health_error.json"), {"role": "host", "error": "invalid_initial_health", "initial_health": initial_health})
		get_tree().quit(113)
		return
	remote_player.call("take_damage", damage_amount)
	var expected_health := maxi(0, initial_health - damage_amount)
	var host_seen := await _wait_for_condition(func() -> bool:
		return int(remote_player.get("current_health")) == expected_health
	, damage_timeout)
	_write_json_file(_path_in_dir("host_player_health.json"), {
		"role": "host",
		"passed": host_seen,
		"initial_health": initial_health,
		"damage_amount": damage_amount,
		"expected_health": expected_health,
		"observed_health": int(remote_player.get("current_health")),
	})
	_touch_file(_path_in_dir("host_player_health.flag"))
	await _wait_for_file(_path_in_dir("client_player_health_done.flag"), client_timeout)
	if host_seen:
		get_tree().quit(0)
		return
	get_tree().quit(114)

func _run_player_health_replication_client(local_player: Node, remote_player: Node, timeout_sec: float) -> void:
	var phase_timeout := minf(timeout_sec, 8.0)
	var initial_local_health := int(local_player.get("current_health"))
	var initial_remote_health := int(remote_player.get("current_health"))
	if not await _wait_for_file(_path_in_dir("host_player_health.flag"), phase_timeout):
		_write_json_file(_path_in_dir("client_player_health_error.json"), {"role": "client", "error": "host_result_missing"})
		get_tree().quit(116)
		return
	var host_result := _read_json_file(_path_in_dir("host_player_health.json"))
	var expected_health := int(host_result.get("expected_health", initial_local_health))
	var local_converged := await _wait_for_condition(func() -> bool:
		return int(local_player.get("current_health")) == expected_health
	, phase_timeout)
	var remote_unchanged := int(remote_player.get("current_health")) == initial_remote_health
	_write_json_file(_path_in_dir("client_player_health.json"), {
		"role": "client",
		"passed": bool(host_result.get("passed", false)) and local_converged and remote_unchanged,
		"initial_local_health": initial_local_health,
		"expected_local_health": expected_health,
		"observed_local_health": int(local_player.get("current_health")),
		"initial_remote_health": initial_remote_health,
		"observed_remote_health": int(remote_player.get("current_health")),
		"remote_unchanged": remote_unchanged,
	})
	_touch_file(_path_in_dir("client_player_health_done.flag"))
	if bool(host_result.get("passed", false)) and local_converged and remote_unchanged:
		get_tree().quit(0)
		return
	get_tree().quit(117)

func _run_client_disconnect_verification() -> void:
	var role := _get_role()
	var timeout_sec := _get_timeout_sec()
	var local_player: Node = await _wait_for_local_player(timeout_sec)
	if local_player == null:
		_write_json_file(_path_in_dir("%s_client_disconnect_error.json" % role), {"role": role, "error": "local_player_not_found"})
		get_tree().quit(118)
		return
	if not await _wait_for_condition(func() -> bool:
		return _find_remote_player() != null
	, timeout_sec):
		_write_json_file(_path_in_dir("%s_client_disconnect_error.json" % role), {"role": role, "error": "remote_player_not_found"})
		get_tree().quit(119)
		return
	_touch_file(_path_in_dir("%s_client_disconnect_ready.flag" % role))
	var other_role := "client" if role == "host" else "host"
	if not await _wait_for_file(_path_in_dir("%s_client_disconnect_ready.flag" % other_role), timeout_sec):
		_write_json_file(_path_in_dir("%s_client_disconnect_error.json" % role), {"role": role, "error": "peer_ready_missing"})
		get_tree().quit(120)
		return

	match role:
		"host":
			await _run_client_disconnect_host(timeout_sec)
		"client":
			await _run_client_disconnect_client(timeout_sec)
		_:
			_write_json_file(_path_in_dir("error.json"), {"role": role, "error": "invalid_role"})
			get_tree().quit(5)

func _run_client_disconnect_host(timeout_sec: float) -> void:
	var initial_roster := _build_player_roster_snapshot()
	var initial_count := _get_network_players().size()
	var remote_player: Node = _find_remote_player()
	var remote_peer_id := _get_player_peer_id(remote_player)
	if not await _wait_for_file(_path_in_dir("client_disconnect_requested.flag"), timeout_sec):
		_write_json_file(_path_in_dir("host_client_disconnect_error.json"), {"role": "host", "error": "client_request_missing"})
		get_tree().quit(121)
		return
	var removed := await _wait_for_condition(func() -> bool:
		return _find_remote_player() == null and _get_network_players().size() == 1
	, timeout_sec)
	var final_roster := _build_player_roster_snapshot()
	_write_json_file(_path_in_dir("host_client_disconnect.json"), {
		"role": "host",
		"passed": removed,
		"initial_player_count": initial_count,
		"final_player_count": _get_network_players().size(),
		"disconnected_peer_id": remote_peer_id,
		"initial_roster": initial_roster.get("players", []),
		"final_roster": final_roster.get("players", []),
	})
	if removed:
		get_tree().quit(0)
		return
	get_tree().quit(122)

func _run_client_disconnect_client(timeout_sec: float) -> void:
	var session := get_node_or_null("/root/NetworkSession")
	if session == null:
		_write_json_file(_path_in_dir("client_client_disconnect_error.json"), {"role": "client", "error": "session_missing"})
		get_tree().quit(123)
		return
	_write_json_file(_path_in_dir("client_client_disconnect.json"), {
		"role": "client",
		"local_peer_id": _get_local_peer_id(),
		"requested": true,
	})
	_touch_file(_path_in_dir("client_disconnect_requested.flag"))
	session.call("leave_game")
	# Leaving the session transitions back to bootstrap and may not terminate immediately.
	await get_tree().create_timer(minf(timeout_sec, 5.0)).timeout
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
	var weapon_fire_seen := int(counts.get("weapon_fire", 0)) >= 2
	result["weapon_fire_seen"] = weapon_fire_seen
	result["passed"] = hitscan_seen and projectile_seen and weapon_fire_seen
	_write_json_file(_path_in_dir("client_weapon_visuals.json"), result)
	_touch_file(_path_in_dir("client_weapon_visual_done.flag"))
	if bool(result.get("passed", false)):
		get_tree().quit(0)
		return
	get_tree().quit(77)

func _run_projectile_damage_replication_verification() -> void:
	var role := _get_role()
	var timeout_sec := _get_timeout_sec()
	var local_player: Node = await _wait_for_local_player(timeout_sec)
	if local_player == null:
		_write_json_file(_path_in_dir("%s_projectile_damage_error.json" % role), {"role": role, "error": "local_player_not_found"})
		get_tree().quit(124)
		return
	var dungeon_manager := get_parent()
	if dungeon_manager == null:
		_write_json_file(_path_in_dir("%s_projectile_damage_error.json" % role), {"role": role, "error": "dungeon_manager_missing"})
		get_tree().quit(125)
		return
	var manager: WeaponManager = local_player.get("weapon_manager")
	if manager == null:
		_write_json_file(_path_in_dir("%s_projectile_damage_error.json" % role), {"role": role, "error": "weapon_manager_missing"})
		get_tree().quit(126)
		return
	_touch_file(_path_in_dir("%s_projectile_damage_ready.flag" % role))
	var other_role := "client" if role == "host" else "host"
	if not await _wait_for_file(_path_in_dir("%s_projectile_damage_ready.flag" % other_role), timeout_sec):
		_write_json_file(_path_in_dir("%s_projectile_damage_error.json" % role), {"role": role, "error": "peer_ready_missing"})
		get_tree().quit(127)
		return

	match role:
		"client":
			await _run_projectile_damage_replication_client(local_player, manager, dungeon_manager, timeout_sec)
		"host":
			await _run_projectile_damage_replication_host(dungeon_manager, timeout_sec)
		_:
			_write_json_file(_path_in_dir("error.json"), {"role": role, "error": "invalid_role"})
			get_tree().quit(5)

func _run_enemy_damage_replication_verification() -> void:
	var role := _get_role()
	var timeout_sec := _get_timeout_sec()
	var local_player: Node = await _wait_for_local_player(timeout_sec)
	if local_player == null:
		_write_json_file(_path_in_dir("%s_enemy_damage_error.json" % role), {"role": role, "error": "local_player_not_found"})
		get_tree().quit(78)
		return
	var dungeon_manager := get_parent()
	if dungeon_manager == null:
		_write_json_file(_path_in_dir("%s_enemy_damage_error.json" % role), {"role": role, "error": "dungeon_manager_missing"})
		get_tree().quit(79)
		return
	var manager: WeaponManager = local_player.get("weapon_manager")
	if manager == null:
		_write_json_file(_path_in_dir("%s_enemy_damage_error.json" % role), {"role": role, "error": "weapon_manager_missing"})
		get_tree().quit(80)
		return
	_touch_file(_path_in_dir("%s_enemy_damage_ready.flag" % role))
	var other_role := "client" if role == "host" else "host"
	if not await _wait_for_file(_path_in_dir("%s_enemy_damage_ready.flag" % other_role), timeout_sec):
		_write_json_file(_path_in_dir("%s_enemy_damage_error.json" % role), {"role": role, "error": "peer_ready_missing"})
		get_tree().quit(81)
		return

	match role:
		"client":
			await _run_enemy_damage_replication_client(local_player, manager, dungeon_manager, timeout_sec)
		"host":
			await _run_enemy_damage_replication_host(dungeon_manager, timeout_sec)
		_:
			_write_json_file(_path_in_dir("error.json"), {"role": role, "error": "invalid_role"})
			get_tree().quit(5)

func _run_enemy_animation_replication_verification() -> void:
	var role := _get_role()
	var timeout_sec := _get_timeout_sec()
	var local_player: Node = await _wait_for_local_player(timeout_sec)
	if local_player == null:
		_write_json_file(_path_in_dir("%s_enemy_animation_error.json" % role), {"role": role, "error": "local_player_not_found"})
		get_tree().quit(128)
		return
	var dungeon_manager := get_parent()
	if dungeon_manager == null:
		_write_json_file(_path_in_dir("%s_enemy_animation_error.json" % role), {"role": role, "error": "dungeon_manager_missing"})
		get_tree().quit(129)
		return
	_touch_file(_path_in_dir("%s_enemy_animation_ready.flag" % role))
	var other_role := "client" if role == "host" else "host"
	if not await _wait_for_file(_path_in_dir("%s_enemy_animation_ready.flag" % other_role), timeout_sec):
		_write_json_file(_path_in_dir("%s_enemy_animation_error.json" % role), {"role": role, "error": "peer_ready_missing"})
		get_tree().quit(130)
		return

	match role:
		"host":
			await _run_enemy_animation_replication_host(local_player, dungeon_manager, timeout_sec)
		"client":
			await _run_enemy_animation_replication_client(dungeon_manager, timeout_sec)
		_:
			_write_json_file(_path_in_dir("error.json"), {"role": role, "error": "invalid_role"})
			get_tree().quit(5)

func _run_mobility_dash_replication_verification() -> void:
	await _run_mobility_replication_verification("dash")

func _run_mobility_grapple_replication_verification() -> void:
	await _run_mobility_replication_verification("grapple")

func _run_mobility_jetpack_replication_verification() -> void:
	await _run_mobility_replication_verification("jetpack")

func _run_mobility_replication_verification(mode: String) -> void:
	var role := _get_role()
	var timeout_sec := _get_timeout_sec()
	var local_player: Node = await _wait_for_local_player(timeout_sec)
	if local_player == null:
		_write_json_file(_path_in_dir("%s_%s_mobility_error.json" % [role, mode]), {"role": role, "error": "local_player_not_found"})
		get_tree().quit(91)
		return
	if not await _wait_for_condition(func() -> bool:
		return _find_remote_player() != null
	, timeout_sec):
		_write_json_file(_path_in_dir("%s_%s_mobility_error.json" % [role, mode]), {"role": role, "error": "remote_player_not_found"})
		get_tree().quit(92)
		return
	_touch_file(_path_in_dir("%s_%s_mobility_ready.flag" % [role, mode]))
	var other_role := "client" if role == "host" else "host"
	if not await _wait_for_file(_path_in_dir("%s_%s_mobility_ready.flag" % [other_role, mode]), timeout_sec):
		_write_json_file(_path_in_dir("%s_%s_mobility_error.json" % [role, mode]), {"role": role, "error": "peer_ready_missing"})
		get_tree().quit(93)
		return

	match role:
		"client":
			await _run_client_mobility_replication(mode, local_player, timeout_sec)
		"host":
			await _run_host_mobility_replication(mode, timeout_sec)
		_:
			_write_json_file(_path_in_dir("error.json"), {"role": role, "error": "invalid_role"})
			get_tree().quit(5)

func _run_client_mobility_replication(mode: String, local_player: Node, timeout_sec: float) -> void:
	var start_pos: Vector3 = local_player.global_position
	var action_payload: Dictionary = _build_mobility_request_payload(mode, local_player)
	_write_json_file(_path_in_dir("client_%s_mobility_start.json" % mode), {
		"mode": mode,
		"start_position": _vec3_to_dict(start_pos),
	})
	var action := &"dash"
	match mode:
		"grapple":
			action = &"grapple_start"
		"jetpack":
			action = &"jet_start"
	NetworkPlayerManager.request_mobility_action(action, action_payload)
	if mode == "jetpack":
		await get_tree().create_timer(0.7).timeout
		NetworkPlayerManager.request_mobility_action(&"jet_stop", {})
	var moved := await _wait_for_condition(func() -> bool:
		return local_player.global_position.distance_to(start_pos) >= 1.0
	, timeout_sec)
	if mode == "dash":
		await get_tree().create_timer(0.4).timeout
	var debug_state: Dictionary = local_player.call("get_mobility_debug_state") if local_player.has_method("get_mobility_debug_state") else {}
	_write_json_file(_path_in_dir("client_%s_mobility.json" % mode), {
		"mode": mode,
		"passed": moved,
		"start_position": _vec3_to_dict(start_pos),
		"end_position": _vec3_to_dict(local_player.global_position),
		"debug_state": debug_state,
	})
	if moved:
		get_tree().quit(0)
		return
	get_tree().quit(94)

func _run_host_mobility_replication(mode: String, timeout_sec: float) -> void:
	if not await _wait_for_file(_path_in_dir("client_%s_mobility_start.json" % mode), timeout_sec):
		_write_json_file(_path_in_dir("host_%s_mobility_error.json" % mode), {"role": "host", "error": "client_start_missing"})
		get_tree().quit(95)
		return
	var remote_player: Node = _find_remote_player()
	if remote_player == null:
		_write_json_file(_path_in_dir("host_%s_mobility_error.json" % mode), {"role": "host", "error": "remote_player_missing"})
		get_tree().quit(96)
		return
	var start_pos: Vector3 = remote_player.global_position
	var moved := await _wait_for_condition(func() -> bool:
		var live_remote: Node = _refresh_player_reference(remote_player)
		return live_remote != null and live_remote.global_position.distance_to(start_pos) >= 1.0
	, timeout_sec)
	var live_remote: Node = _refresh_player_reference(remote_player)
	var debug_state: Dictionary = live_remote.call("get_mobility_debug_state") if live_remote != null and live_remote.has_method("get_mobility_debug_state") else {}
	var end_pos: Vector3 = start_pos if live_remote == null else live_remote.global_position
	_write_json_file(_path_in_dir("host_%s_mobility.json" % mode), {
		"mode": mode,
		"passed": moved,
		"start_position": _vec3_to_dict(start_pos),
		"end_position": _vec3_to_dict(end_pos),
		"debug_state": debug_state,
	})
	if not await _wait_for_file(_path_in_dir("client_%s_mobility.json" % mode), timeout_sec):
		_write_json_file(_path_in_dir("host_%s_mobility_error.json" % mode), {"role": "host", "error": "client_result_missing"})
		get_tree().quit(97)
		return
	if moved:
		get_tree().quit(0)
		return
	get_tree().quit(98)

func _build_mobility_request_payload(mode: String, player: Node) -> Dictionary:
	match mode:
		"dash":
			return {"direction": -player.global_transform.basis.z.normalized()}
		"grapple":
			var basis: Basis = player.global_transform.basis
			var direction: Vector3 = (-basis.z + Vector3.DOWN * 0.35).normalized()
			var origin: Vector3 = player.global_position + Vector3.UP * 1.4
			return {"origin": origin, "direction": direction}
		"jetpack":
			return {}
		_:
			return {}

func _run_long_run_soak_verification() -> void:
	var role := _get_role()
	var timeout_sec := _get_timeout_sec()
	var local_player: Node = await _wait_for_local_player(timeout_sec)
	if local_player == null:
		_write_json_file(_path_in_dir("%s_soak_error.json" % role), {"role": role, "error": "local_player_not_found"})
		get_tree().quit(131)
		return
	var dungeon_manager := get_parent()
	if dungeon_manager == null:
		_write_json_file(_path_in_dir("%s_soak_error.json" % role), {"role": role, "error": "dungeon_manager_missing"})
		get_tree().quit(132)
		return
	if not await _wait_for_condition(func() -> bool:
		return _find_remote_player() != null and _get_debug_network_enemy_states(dungeon_manager).size() > 0
	, timeout_sec):
		_write_json_file(_path_in_dir("%s_soak_error.json" % role), {"role": role, "error": "initial_replication_not_ready"})
		get_tree().quit(133)
		return
	_touch_file(_path_in_dir("%s_soak_ready.flag" % role))
	var other_role := "client" if role == "host" else "host"
	if not await _wait_for_file(_path_in_dir("%s_soak_ready.flag" % other_role), timeout_sec):
		_write_json_file(_path_in_dir("%s_soak_error.json" % role), {"role": role, "error": "peer_ready_missing"})
		get_tree().quit(134)
		return

	match role:
		"host":
			await _run_long_run_soak_host(local_player, dungeon_manager, timeout_sec)
		"client":
			await _run_long_run_soak_client(local_player, dungeon_manager, timeout_sec)
		_:
			_write_json_file(_path_in_dir("error.json"), {"role": role, "error": "invalid_role"})
			get_tree().quit(5)

func _run_enemy_death_replication_verification() -> void:
	var role := _get_role()
	var timeout_sec := _get_timeout_sec()
	var local_player: Node = await _wait_for_local_player(timeout_sec)
	if local_player == null:
		_write_json_file(_path_in_dir("%s_enemy_death_error.json" % role), {"role": role, "error": "local_player_not_found"})
		get_tree().quit(94)
		return
	var dungeon_manager := get_parent()
	if dungeon_manager == null:
		_write_json_file(_path_in_dir("%s_enemy_death_error.json" % role), {"role": role, "error": "dungeon_manager_missing"})
		get_tree().quit(95)
		return
	var manager: WeaponManager = local_player.get("weapon_manager")
	if manager == null:
		_write_json_file(_path_in_dir("%s_enemy_death_error.json" % role), {"role": role, "error": "weapon_manager_missing"})
		get_tree().quit(96)
		return
	_touch_file(_path_in_dir("%s_enemy_death_ready.flag" % role))
	var other_role := "client" if role == "host" else "host"
	if not await _wait_for_file(_path_in_dir("%s_enemy_death_ready.flag" % other_role), timeout_sec):
		_write_json_file(_path_in_dir("%s_enemy_death_error.json" % role), {"role": role, "error": "peer_ready_missing"})
		get_tree().quit(97)
		return

	match role:
		"client":
			await _run_enemy_death_replication_client(local_player, manager, dungeon_manager, timeout_sec)
		"host":
			await _run_enemy_death_replication_host(dungeon_manager, timeout_sec)
		_:
			_write_json_file(_path_in_dir("error.json"), {"role": role, "error": "invalid_role"})
			get_tree().quit(5)

func _run_enemy_damage_replication_client(local_player: Node, manager: WeaponManager, dungeon_manager: Node, timeout_sec: float) -> void:
	if not _switch_weapon_by_key(manager, "rifle"):
		_write_json_file(_path_in_dir("client_enemy_damage_error.json"), {"role": "client", "error": "rifle_missing"})
		get_tree().quit(82)
		return
	var weapon: Weapon = manager.get_current_weapon()
	if weapon == null:
		_write_json_file(_path_in_dir("client_enemy_damage_error.json"), {"role": "client", "error": "weapon_missing_after_switch"})
		get_tree().quit(83)
		return
	var shot_damage := weapon.damage
	if weapon.has_method("_get_effective_damage"):
		shot_damage = int(weapon.call("_get_effective_damage"))
	_write_json_file(_path_in_dir("client_enemy_damage_weapon.json"), {
		"role": "client",
		"weapon_key": manager.get_current_weapon_key(),
		"weapon_slot": manager.get_current_weapon_slot(),
		"shot_damage": shot_damage,
	})
	_touch_file(_path_in_dir("client_enemy_damage_weapon.flag"))

	if not await _wait_for_file(_path_in_dir("host_enemy_target.flag"), timeout_sec):
		_write_json_file(_path_in_dir("client_enemy_damage_error.json"), {"role": "client", "error": "host_target_missing"})
		get_tree().quit(84)
		return
	var target := _read_json_file(_path_in_dir("host_enemy_target.json"))
	var enemy_id := int(target.get("enemy_id", -1))
	if enemy_id < 0:
		_write_json_file(_path_in_dir("client_enemy_damage_error.json"), {"role": "client", "error": "invalid_enemy_id", "target": target})
		get_tree().quit(85)
		return
	var expected_initial_health := int(target.get("initial_health", -1))
	if not await _wait_for_condition(func() -> bool:
		var enemy_state := _get_debug_network_enemy_state(dungeon_manager, enemy_id)
		if enemy_state.is_empty():
			return false
		return int(enemy_state.get("health", -1)) == expected_initial_health
	, timeout_sec):
		_write_json_file(_path_in_dir("client_enemy_damage_error.json"), {
			"role": "client",
			"error": "enemy_proxy_not_ready",
			"enemy_id": enemy_id,
			"expected_initial_health": expected_initial_health,
			"observed_state": _get_debug_network_enemy_state(dungeon_manager, enemy_id),
		})
		get_tree().quit(86)
		return

	var aim_target := _dict_to_vec3(target.get("aim_target", {}))
	var fire_offsets := [
		Vector3(0.0, 0.3, 2.5),
		Vector3(0.0, 0.3, -2.5),
		Vector3(2.5, 0.3, 0.0),
		Vector3(-2.5, 0.3, 0.0),
	]
	var local_peer_id := _get_player_peer_id(local_player)
	for i in range(fire_offsets.size()):
		var fire_origin: Vector3 = aim_target + fire_offsets[i]
		var fire_direction: Vector3 = (aim_target - fire_origin).normalized()
		dungeon_manager.call(
			"request_weapon_fire",
			local_peer_id,
			manager.get_current_weapon_slot(),
			manager.get_current_weapon_key(),
			fire_origin,
			fire_direction,
			int(Time.get_ticks_msec()) + i
		)
		await get_tree().create_timer(0.35).timeout
	_touch_file(_path_in_dir("client_enemy_damage_sent.flag"))

	if not await _wait_for_file(_path_in_dir("host_enemy_damage.flag"), timeout_sec):
		_write_json_file(_path_in_dir("client_enemy_damage_error.json"), {"role": "client", "error": "host_result_missing", "enemy_id": enemy_id})
		get_tree().quit(87)
		return
	var host_result := _read_json_file(_path_in_dir("host_enemy_damage.json"))
	var expected_dead := bool(host_result.get("enemy_missing", false))
	var expected_health := int(host_result.get("final_health", expected_initial_health))
	var client_converged := await _wait_for_condition(func() -> bool:
		var enemy_state := _get_debug_network_enemy_state(dungeon_manager, enemy_id)
		if expected_dead:
			return enemy_state.is_empty()
		if enemy_state.is_empty():
			return false
		return int(enemy_state.get("health", expected_initial_health)) == expected_health
	, timeout_sec)
	var client_state := _get_debug_network_enemy_state(dungeon_manager, enemy_id)
	_write_json_file(_path_in_dir("client_enemy_damage.json"), {
		"role": "client",
		"passed": client_converged and bool(host_result.get("passed", false)),
		"enemy_id": enemy_id,
		"expected_health": expected_health,
		"expected_dead": expected_dead,
		"observed_health": -1 if client_state.is_empty() else int(client_state.get("health", -1)),
		"enemy_missing": client_state.is_empty(),
		"host_passed": bool(host_result.get("passed", false)),
	})
	_touch_file(_path_in_dir("client_enemy_damage_done.flag"))
	if client_converged and bool(host_result.get("passed", false)):
		get_tree().quit(0)
		return
	get_tree().quit(88)

func _run_projectile_damage_replication_client(local_player: Node, manager: WeaponManager, dungeon_manager: Node, timeout_sec: float) -> void:
	if not _switch_weapon_by_key(manager, "fireball"):
		_write_json_file(_path_in_dir("client_projectile_damage_error.json"), {"role": "client", "error": "fireball_missing"})
		get_tree().quit(135)
		return
	var weapon: Weapon = manager.get_current_weapon()
	if weapon == null:
		_write_json_file(_path_in_dir("client_projectile_damage_error.json"), {"role": "client", "error": "weapon_missing_after_switch"})
		get_tree().quit(136)
		return
	var shot_damage := weapon.damage
	if weapon.has_method("_get_effective_damage"):
		shot_damage = int(weapon.call("_get_effective_damage"))
	_write_json_file(_path_in_dir("client_projectile_damage_weapon.json"), {
		"role": "client",
		"weapon_key": manager.get_current_weapon_key(),
		"weapon_slot": manager.get_current_weapon_slot(),
		"shot_damage": shot_damage,
	})
	_touch_file(_path_in_dir("client_projectile_damage_weapon.flag"))

	if not await _wait_for_file(_path_in_dir("host_projectile_target.flag"), timeout_sec):
		_write_json_file(_path_in_dir("client_projectile_damage_error.json"), {"role": "client", "error": "host_target_missing"})
		get_tree().quit(137)
		return
	var target := _read_json_file(_path_in_dir("host_projectile_target.json"))
	var enemy_id := int(target.get("enemy_id", -1))
	var expected_initial_health := int(target.get("initial_health", -1))
	if enemy_id < 0:
		_write_json_file(_path_in_dir("client_projectile_damage_error.json"), {"role": "client", "error": "invalid_enemy_id"})
		get_tree().quit(138)
		return
	if not await _wait_for_condition(func() -> bool:
		var enemy_state := _get_debug_network_enemy_state(dungeon_manager, enemy_id)
		return not enemy_state.is_empty() and int(enemy_state.get("health", -1)) == expected_initial_health
	, timeout_sec):
		_write_json_file(_path_in_dir("client_projectile_damage_error.json"), {"role": "client", "error": "enemy_proxy_not_ready", "enemy_id": enemy_id})
		get_tree().quit(139)
		return
	var aim_target := _dict_to_vec3(target.get("aim_target", {}))
	await _fire_network_weapon_requests(dungeon_manager, local_player, manager, aim_target, 1, 3000)
	_touch_file(_path_in_dir("client_projectile_damage_sent.flag"))
	if not await _wait_for_file(_path_in_dir("host_projectile_damage.flag"), timeout_sec):
		_write_json_file(_path_in_dir("client_projectile_damage_error.json"), {"role": "client", "error": "host_result_missing", "enemy_id": enemy_id})
		get_tree().quit(140)
		return
	var host_result := _read_json_file(_path_in_dir("host_projectile_damage.json"))
	var expected_health := int(host_result.get("final_health", expected_initial_health))
	var expected_dead := bool(host_result.get("enemy_missing", false)) or expected_health <= 0
	var client_converged := await _wait_for_condition(func() -> bool:
		var enemy_state := _get_debug_network_enemy_state(dungeon_manager, enemy_id)
		if expected_dead:
			return enemy_state.is_empty() or int(enemy_state.get("health", 1)) <= 0
		return not enemy_state.is_empty() and int(enemy_state.get("health", expected_initial_health)) == expected_health
	, timeout_sec)
	var final_state := _get_debug_network_enemy_state(dungeon_manager, enemy_id)
	_write_json_file(_path_in_dir("client_projectile_damage.json"), {
		"role": "client",
		"passed": bool(host_result.get("passed", false)) and client_converged,
		"enemy_id": enemy_id,
		"expected_health": expected_health,
		"observed_health": -1 if final_state.is_empty() else int(final_state.get("health", -1)),
		"enemy_missing": final_state.is_empty(),
	})
	_touch_file(_path_in_dir("client_projectile_damage_done.flag"))
	if bool(host_result.get("passed", false)) and client_converged:
		get_tree().quit(0)
		return
	get_tree().quit(141)

func _run_enemy_damage_replication_host(dungeon_manager: Node, timeout_sec: float) -> void:
	if not await _wait_for_file(_path_in_dir("client_enemy_damage_weapon.flag"), timeout_sec):
		_write_json_file(_path_in_dir("host_enemy_damage_error.json"), {"role": "host", "error": "client_weapon_missing"})
		get_tree().quit(89)
		return
	var weapon_data := _read_json_file(_path_in_dir("client_enemy_damage_weapon.json"))
	var minimum_target_health := maxi(2, int(weapon_data.get("shot_damage", 1)) + 1)
	var target_state := await _wait_for_enemy_state(dungeon_manager, func(state: Dictionary) -> bool:
		return not bool(state.get("is_proxy", true)) and int(state.get("health", 0)) >= minimum_target_health
	, timeout_sec)
	if target_state.is_empty():
		_write_json_file(_path_in_dir("host_enemy_damage_error.json"), {
			"role": "host",
			"error": "target_enemy_missing",
			"minimum_target_health": minimum_target_health,
		})
		get_tree().quit(90)
		return
	var enemy_id := int(target_state.get("id", -1))
	var target_position: Vector3 = target_state.get("position", Vector3.ZERO)
	var aim_target := target_position + Vector3(0.0, 0.9, 0.0)
	_write_json_file(_path_in_dir("host_enemy_target.json"), {
		"role": "host",
		"enemy_id": enemy_id,
		"initial_health": int(target_state.get("health", 0)),
		"aim_target": _vec3_to_dict(aim_target),
	})
	_touch_file(_path_in_dir("host_enemy_target.flag"))

	if not await _wait_for_file(_path_in_dir("client_enemy_damage_sent.flag"), timeout_sec):
		_write_json_file(_path_in_dir("host_enemy_damage_error.json"), {"role": "host", "error": "client_fire_missing", "enemy_id": enemy_id})
		get_tree().quit(91)
		return
	var initial_health := int(target_state.get("health", 0))
	var host_damage_seen := await _wait_for_condition(func() -> bool:
		var enemy_state := _get_debug_network_enemy_state(dungeon_manager, enemy_id)
		return enemy_state.is_empty() or int(enemy_state.get("health", initial_health)) < initial_health
	, timeout_sec)
	var final_state := _get_debug_network_enemy_state(dungeon_manager, enemy_id)
	var enemy_missing := final_state.is_empty()
	var final_health := 0 if enemy_missing else int(final_state.get("health", initial_health))
	var passed := host_damage_seen and (enemy_missing or final_health < initial_health)
	_write_json_file(_path_in_dir("host_enemy_damage.json"), {
		"role": "host",
		"passed": passed,
		"enemy_id": enemy_id,
		"initial_health": initial_health,
		"final_health": final_health,
		"enemy_missing": enemy_missing,
	})
	_touch_file(_path_in_dir("host_enemy_damage.flag"))
	if not await _wait_for_file(_path_in_dir("client_enemy_damage_done.flag"), timeout_sec):
		_write_json_file(_path_in_dir("host_enemy_damage_error.json"), {"role": "host", "error": "client_result_missing", "enemy_id": enemy_id})
		get_tree().quit(92)
		return
	if passed:
		get_tree().quit(0)
		return
	get_tree().quit(93)

func _run_projectile_damage_replication_host(dungeon_manager: Node, timeout_sec: float) -> void:
	if not await _wait_for_file(_path_in_dir("client_projectile_damage_weapon.flag"), timeout_sec):
		_write_json_file(_path_in_dir("host_projectile_damage_error.json"), {"role": "host", "error": "client_weapon_missing"})
		get_tree().quit(142)
		return
	var target_state := await _wait_for_enemy_state(dungeon_manager, func(state: Dictionary) -> bool:
		return not bool(state.get("is_proxy", true)) and int(state.get("health", 0)) > 0
	, timeout_sec)
	if target_state.is_empty():
		_write_json_file(_path_in_dir("host_projectile_damage_error.json"), {"role": "host", "error": "target_enemy_missing"})
		get_tree().quit(143)
		return
	var enemy_id := int(target_state.get("id", -1))
	var target_position: Vector3 = target_state.get("position", Vector3.ZERO)
	var aim_target := target_position + Vector3(0.0, 0.9, 0.0)
	_write_json_file(_path_in_dir("host_projectile_target.json"), {
		"role": "host",
		"enemy_id": enemy_id,
		"initial_health": int(target_state.get("health", 0)),
		"aim_target": _vec3_to_dict(aim_target),
	})
	_touch_file(_path_in_dir("host_projectile_target.flag"))
	if not await _wait_for_file(_path_in_dir("client_projectile_damage_sent.flag"), timeout_sec):
		_write_json_file(_path_in_dir("host_projectile_damage_error.json"), {"role": "host", "error": "client_fire_missing", "enemy_id": enemy_id})
		get_tree().quit(144)
		return
	var initial_health := int(target_state.get("health", 0))
	var damaged := await _wait_for_condition(func() -> bool:
		var enemy_state := _get_debug_network_enemy_state(dungeon_manager, enemy_id)
		return enemy_state.is_empty() or int(enemy_state.get("health", initial_health)) < initial_health
	, timeout_sec)
	var final_state := _get_debug_network_enemy_state(dungeon_manager, enemy_id)
	var enemy_missing := final_state.is_empty()
	var final_health := 0 if enemy_missing else int(final_state.get("health", initial_health))
	_write_json_file(_path_in_dir("host_projectile_damage.json"), {
		"role": "host",
		"passed": damaged and (enemy_missing or final_health < initial_health),
		"enemy_id": enemy_id,
		"initial_health": initial_health,
		"final_health": final_health,
		"enemy_missing": enemy_missing,
	})
	_touch_file(_path_in_dir("host_projectile_damage.flag"))
	await _wait_for_file(_path_in_dir("client_projectile_damage_done.flag"), minf(timeout_sec, 8.0))
	if damaged:
		get_tree().quit(0)
		return
	get_tree().quit(145)

func _run_enemy_death_replication_client(local_player: Node, manager: WeaponManager, dungeon_manager: Node, timeout_sec: float) -> void:
	if not _switch_weapon_by_key(manager, "rifle"):
		_write_json_file(_path_in_dir("client_enemy_death_error.json"), {"role": "client", "error": "rifle_missing"})
		get_tree().quit(98)
		return
	var weapon: Weapon = manager.get_current_weapon()
	if weapon == null:
		_write_json_file(_path_in_dir("client_enemy_death_error.json"), {"role": "client", "error": "weapon_missing_after_switch"})
		get_tree().quit(99)
		return
	var shot_damage := weapon.damage
	if weapon.has_method("_get_effective_damage"):
		shot_damage = int(weapon.call("_get_effective_damage"))
	_write_json_file(_path_in_dir("client_enemy_death_weapon.json"), {
		"role": "client",
		"weapon_key": manager.get_current_weapon_key(),
		"weapon_slot": manager.get_current_weapon_slot(),
		"shot_damage": shot_damage,
	})
	_touch_file(_path_in_dir("client_enemy_death_weapon.flag"))

	if not await _wait_for_file(_path_in_dir("host_enemy_death_target.flag"), timeout_sec):
		_write_json_file(_path_in_dir("client_enemy_death_error.json"), {"role": "client", "error": "host_target_missing"})
		get_tree().quit(100)
		return
	var target := _read_json_file(_path_in_dir("host_enemy_death_target.json"))
	var enemy_id := int(target.get("enemy_id", -1))
	if enemy_id < 0:
		_write_json_file(_path_in_dir("client_enemy_death_error.json"), {"role": "client", "error": "invalid_enemy_id", "target": target})
		get_tree().quit(101)
		return
	var expected_initial_health := int(target.get("initial_health", -1))
	if not await _wait_for_condition(func() -> bool:
		var enemy_state := _get_debug_network_enemy_state(dungeon_manager, enemy_id)
		if enemy_state.is_empty():
			return false
		return int(enemy_state.get("health", -1)) == expected_initial_health
	, timeout_sec):
		_write_json_file(_path_in_dir("client_enemy_death_error.json"), {
			"role": "client",
			"error": "enemy_proxy_not_ready",
			"enemy_id": enemy_id,
			"expected_initial_health": expected_initial_health,
			"observed_state": _get_debug_network_enemy_state(dungeon_manager, enemy_id),
		})
		get_tree().quit(102)
		return

	var aim_target := _dict_to_vec3(target.get("aim_target", {}))
	var shot_count := maxi(1, int(target.get("shot_count", 1)))
	await _fire_network_weapon_requests(dungeon_manager, local_player, manager, aim_target, shot_count, 2000)
	_touch_file(_path_in_dir("client_enemy_death_sent.flag"))

	var dead_state_seen := await _wait_for_condition(func() -> bool:
		var enemy_state := _get_debug_network_enemy_state(dungeon_manager, enemy_id)
		if enemy_state.is_empty():
			return false
		return int(enemy_state.get("state", -1)) == 5 or int(enemy_state.get("health", 1)) <= 0
	, timeout_sec)
	var despawn_seen := await _wait_for_condition(func() -> bool:
		return _get_debug_network_enemy_state(dungeon_manager, enemy_id).is_empty()
	, timeout_sec)
	if not await _wait_for_file(_path_in_dir("host_enemy_death.flag"), timeout_sec):
		_write_json_file(_path_in_dir("client_enemy_death_error.json"), {"role": "client", "error": "host_result_missing", "enemy_id": enemy_id})
		get_tree().quit(103)
		return
	var host_result := _read_json_file(_path_in_dir("host_enemy_death.json"))
	var final_state := _get_debug_network_enemy_state(dungeon_manager, enemy_id)
	_write_json_file(_path_in_dir("client_enemy_death.json"), {
		"role": "client",
		"passed": dead_state_seen and despawn_seen and bool(host_result.get("passed", false)),
		"enemy_id": enemy_id,
		"dead_state_seen": dead_state_seen,
		"despawn_seen": despawn_seen,
		"enemy_missing": final_state.is_empty(),
		"host_passed": bool(host_result.get("passed", false)),
	})
	_touch_file(_path_in_dir("client_enemy_death_done.flag"))
	if dead_state_seen and despawn_seen and bool(host_result.get("passed", false)):
		get_tree().quit(0)
		return
	get_tree().quit(104)

func _run_enemy_death_replication_host(dungeon_manager: Node, timeout_sec: float) -> void:
	if not await _wait_for_file(_path_in_dir("client_enemy_death_weapon.flag"), timeout_sec):
		_write_json_file(_path_in_dir("host_enemy_death_error.json"), {"role": "host", "error": "client_weapon_missing"})
		get_tree().quit(105)
		return
	var weapon_data := _read_json_file(_path_in_dir("client_enemy_death_weapon.json"))
	var shot_damage := maxi(1, int(weapon_data.get("shot_damage", 1)))
	var max_target_health := maxi(shot_damage * 100, 1000)
	var target_state := await _wait_for_enemy_state(dungeon_manager, func(state: Dictionary) -> bool:
		var health := int(state.get("health", 0))
		return not bool(state.get("is_proxy", true)) and health > 0 and health <= max_target_health
	, timeout_sec)
	if target_state.is_empty():
		_write_json_file(_path_in_dir("host_enemy_death_error.json"), {
			"role": "host",
			"error": "target_enemy_missing",
			"max_target_health": max_target_health,
		})
		get_tree().quit(106)
		return
	var enemy_id := int(target_state.get("id", -1))
	var initial_health := int(target_state.get("health", 0))
	var shot_count := maxi(1, int(ceil(float(initial_health) / float(shot_damage))))
	var target_position: Vector3 = target_state.get("position", Vector3.ZERO)
	var aim_target := target_position + Vector3(0.0, 0.9, 0.0)
	_write_json_file(_path_in_dir("host_enemy_death_target.json"), {
		"role": "host",
		"enemy_id": enemy_id,
		"initial_health": initial_health,
		"shot_count": shot_count,
		"aim_target": _vec3_to_dict(aim_target),
	})
	_touch_file(_path_in_dir("host_enemy_death_target.flag"))

	if not await _wait_for_file(_path_in_dir("client_enemy_death_sent.flag"), timeout_sec):
		_write_json_file(_path_in_dir("host_enemy_death_error.json"), {"role": "host", "error": "client_fire_missing", "enemy_id": enemy_id})
		get_tree().quit(107)
		return
	var death_seen := await _wait_for_condition(func() -> bool:
		var enemy_state := _get_debug_network_enemy_state(dungeon_manager, enemy_id)
		return enemy_state.is_empty() or int(enemy_state.get("state", -1)) == 5 or int(enemy_state.get("health", 1)) <= 0
	, timeout_sec)
	var despawn_seen := await _wait_for_condition(func() -> bool:
		return _get_debug_network_enemy_state(dungeon_manager, enemy_id).is_empty()
	, timeout_sec)
	_write_json_file(_path_in_dir("host_enemy_death.json"), {
		"role": "host",
		"passed": death_seen and despawn_seen,
		"enemy_id": enemy_id,
		"initial_health": initial_health,
		"death_seen": death_seen,
		"despawn_seen": despawn_seen,
	})
	_touch_file(_path_in_dir("host_enemy_death.flag"))
	if not await _wait_for_file(_path_in_dir("client_enemy_death_done.flag"), timeout_sec):
		_write_json_file(_path_in_dir("host_enemy_death_error.json"), {"role": "host", "error": "client_result_missing", "enemy_id": enemy_id})
		get_tree().quit(108)
		return
	if death_seen and despawn_seen:
		get_tree().quit(0)
		return
	get_tree().quit(109)

func _run_enemy_loot_replication_client(local_player: Node, manager: WeaponManager, dungeon_manager: Node, timeout_sec: float) -> void:
	if not _switch_weapon_by_key(manager, "rifle"):
		_write_json_file(_path_in_dir("client_enemy_loot_error.json"), {"role": "client", "error": "rifle_missing"})
		get_tree().quit(165)
		return
	var weapon: Weapon = manager.get_current_weapon()
	if weapon == null:
		_write_json_file(_path_in_dir("client_enemy_loot_error.json"), {"role": "client", "error": "weapon_missing_after_switch"})
		get_tree().quit(166)
		return
	var shot_damage := weapon.damage
	if weapon.has_method("_get_effective_damage"):
		shot_damage = int(weapon.call("_get_effective_damage"))
	_write_json_file(_path_in_dir("client_enemy_loot_weapon.json"), {
		"role": "client",
		"weapon_key": manager.get_current_weapon_key(),
		"weapon_slot": manager.get_current_weapon_slot(),
		"shot_damage": shot_damage,
	})
	_touch_file(_path_in_dir("client_enemy_loot_weapon.flag"))

	if not await _wait_for_file(_path_in_dir("host_enemy_loot_target.flag"), timeout_sec):
		_write_json_file(_path_in_dir("client_enemy_loot_error.json"), {"role": "client", "error": "host_target_missing"})
		get_tree().quit(167)
		return
	var target := _read_json_file(_path_in_dir("host_enemy_loot_target.json"))
	var enemy_id := int(target.get("enemy_id", -1))
	if enemy_id < 0:
		_write_json_file(_path_in_dir("client_enemy_loot_error.json"), {"role": "client", "error": "invalid_enemy_id", "target": target})
		get_tree().quit(168)
		return
	var expected_initial_health := int(target.get("initial_health", -1))
	if not await _wait_for_condition(func() -> bool:
		var enemy_state := _get_debug_network_enemy_state(dungeon_manager, enemy_id)
		if enemy_state.is_empty():
			return false
		return int(enemy_state.get("health", -1)) == expected_initial_health
	, timeout_sec):
		_write_json_file(_path_in_dir("client_enemy_loot_error.json"), {
			"role": "client",
			"error": "enemy_proxy_not_ready",
			"enemy_id": enemy_id,
			"expected_initial_health": expected_initial_health,
			"observed_state": _get_debug_network_enemy_state(dungeon_manager, enemy_id),
		})
		get_tree().quit(169)
		return

	var aim_target := _dict_to_vec3(target.get("aim_target", {}))
	var shot_count := maxi(1, int(target.get("shot_count", 1)))
	await _fire_network_weapon_requests(dungeon_manager, local_player, manager, aim_target, shot_count, 3000)
	_touch_file(_path_in_dir("client_enemy_loot_sent.flag"))

	var loot_seen := await _wait_for_condition(func() -> bool:
		return _get_loot_pickup_snapshots().size() > 0
	, timeout_sec)
	if not await _wait_for_file(_path_in_dir("host_enemy_loot_done.flag"), timeout_sec):
		_write_json_file(_path_in_dir("client_enemy_loot_error.json"), {"role": "client", "error": "host_result_missing", "enemy_id": enemy_id})
		get_tree().quit(170)
		return
	var host_result := _read_json_file(_path_in_dir("host_enemy_loot.json"))
	var loot_snapshots := _get_loot_pickup_snapshots()
	_write_json_file(_path_in_dir("client_enemy_loot.json"), {
		"role": "client",
		"passed": loot_seen and bool(host_result.get("passed", false)),
		"enemy_id": enemy_id,
		"loot_count": loot_snapshots.size(),
		"loot_seen": loot_seen,
		"loot": loot_snapshots,
		"host_passed": bool(host_result.get("passed", false)),
	})
	_touch_file(_path_in_dir("client_enemy_loot_done.flag"))
	if loot_seen and bool(host_result.get("passed", false)):
		get_tree().quit(0)
		return
	get_tree().quit(171)

func _run_enemy_loot_replication_host(dungeon_manager: Node, timeout_sec: float) -> void:
	if not await _wait_for_file(_path_in_dir("client_enemy_loot_weapon.flag"), timeout_sec):
		_write_json_file(_path_in_dir("host_enemy_loot_error.json"), {"role": "host", "error": "client_weapon_missing"})
		get_tree().quit(172)
		return
	var weapon_data := _read_json_file(_path_in_dir("client_enemy_loot_weapon.json"))
	var shot_damage := maxi(1, int(weapon_data.get("shot_damage", 1)))
	var max_target_health := maxi(shot_damage * 100, 1000)
	var target_state := await _wait_for_enemy_state(dungeon_manager, func(state: Dictionary) -> bool:
		var health := int(state.get("health", 0))
		return not bool(state.get("is_proxy", true)) and health > 0 and health <= max_target_health
	, timeout_sec)
	if target_state.is_empty():
		_write_json_file(_path_in_dir("host_enemy_loot_error.json"), {
			"role": "host",
			"error": "target_enemy_missing",
			"max_target_health": max_target_health,
		})
		get_tree().quit(173)
		return
	var enemy_id := int(target_state.get("id", -1))
	var initial_health := int(target_state.get("health", 0))
	var shot_count := maxi(1, int(ceil(float(initial_health) / float(shot_damage))))
	var target_position: Vector3 = target_state.get("position", Vector3.ZERO)
	var aim_target := target_position + Vector3(0.0, 0.9, 0.0)
	_write_json_file(_path_in_dir("host_enemy_loot_target.json"), {
		"role": "host",
		"enemy_id": enemy_id,
		"initial_health": initial_health,
		"shot_count": shot_count,
		"aim_target": _vec3_to_dict(aim_target),
	})
	_touch_file(_path_in_dir("host_enemy_loot_target.flag"))

	if not await _wait_for_file(_path_in_dir("client_enemy_loot_sent.flag"), timeout_sec):
		_write_json_file(_path_in_dir("host_enemy_loot_error.json"), {"role": "host", "error": "client_fire_missing", "enemy_id": enemy_id})
		get_tree().quit(174)
		return
	var loot_seen := await _wait_for_condition(func() -> bool:
		return _get_loot_pickup_snapshots().size() > 0
	, timeout_sec)
	var loot_snapshots := _get_loot_pickup_snapshots()
	_write_json_file(_path_in_dir("host_enemy_loot.json"), {
		"role": "host",
		"passed": loot_seen,
		"enemy_id": enemy_id,
		"loot_count": loot_snapshots.size(),
		"loot_seen": loot_seen,
		"loot": loot_snapshots,
	})
	_touch_file(_path_in_dir("host_enemy_loot_done.flag"))
	if not await _wait_for_file(_path_in_dir("client_enemy_loot_done.flag"), timeout_sec):
		_write_json_file(_path_in_dir("host_enemy_loot_error.json"), {"role": "host", "error": "client_result_missing", "enemy_id": enemy_id})
		get_tree().quit(175)
		return
	if loot_seen:
		get_tree().quit(0)
		return
	get_tree().quit(176)

func _run_enemy_loot_replication_verification() -> void:
	var role := _get_role()
	var timeout_sec := _get_timeout_sec()
	var local_player: Node = await _wait_for_local_player(timeout_sec)
	if local_player == null:
		_write_json_file(_path_in_dir("%s_enemy_loot_error.json" % role), {"role": role, "error": "local_player_not_found"})
		get_tree().quit(161)
		return
	var dungeon_manager := get_parent()
	if dungeon_manager == null:
		_write_json_file(_path_in_dir("%s_enemy_loot_error.json" % role), {"role": role, "error": "dungeon_manager_missing"})
		get_tree().quit(162)
		return
	var manager: WeaponManager = local_player.get("weapon_manager")
	if manager == null:
		_write_json_file(_path_in_dir("%s_enemy_loot_error.json" % role), {"role": role, "error": "weapon_manager_missing"})
		get_tree().quit(163)
		return
	_touch_file(_path_in_dir("%s_enemy_loot_ready.flag" % role))
	var other_role := "client" if role == "host" else "host"
	if not await _wait_for_file(_path_in_dir("%s_enemy_loot_ready.flag" % other_role), timeout_sec):
		_write_json_file(_path_in_dir("%s_enemy_loot_error.json" % role), {"role": role, "error": "peer_ready_missing"})
		get_tree().quit(164)
		return

	match role:
		"client":
			await _run_enemy_loot_replication_client(local_player, manager, dungeon_manager, timeout_sec)
		"host":
			await _run_enemy_loot_replication_host(dungeon_manager, timeout_sec)
		_:
			_write_json_file(_path_in_dir("error.json"), {"role": role, "error": "invalid_role"})
			get_tree().quit(5)

func _run_loot_pickup_sync_host(_local_player: Node, inventory_system: InventorySystem, dungeon_manager: Node, timeout_sec: float) -> void:
	var remote_player: Node = _find_remote_player()
	if remote_player == null:
		_write_json_file(_path_in_dir("host_loot_pickup_sync_error.json"), {"role": "host", "error": "remote_player_missing"})
		get_tree().quit(181)
		return
	var expected_item_id := "verify_network_loot_pickup"
	var item_payload := {
		"item_id": expected_item_id,
		"display_name": "Verifier Loot Pickup",
		"category": "misc",
		"equipment_slot": "",
		"weapon_key": "",
		"icon_path": "",
		"rarity": "Common",
		"implicit_stats": {},
		"affixes": [],
		"stats": {"rarity": "Common"},
	}
	var drop_origin: Vector3 = remote_player.global_position + Vector3(0.0, 0.6, 0.0)
	dungeon_manager.call("spawn_network_item_pickup", item_payload, drop_origin, Vector3(0.0, 0.0, 0.4))
	_write_json_file(_path_in_dir("host_loot_pickup_sync_target.json"), {
		"role": "host",
		"item_id": expected_item_id,
	})
	_touch_file(_path_in_dir("host_loot_pickup_sync_target.flag"))
	var host_inventory_synced := await _wait_for_condition(func() -> bool:
		var live_remote_player: Node = _find_remote_player()
		if live_remote_player == null:
			return false
		var live_remote_inventory: InventorySystem = live_remote_player.get("inventory_system") as InventorySystem
		return _get_storage_item_ids(live_remote_inventory).has(expected_item_id)
	, timeout_sec)
	var pickup_gone := await _wait_for_condition(func() -> bool:
		return _find_loot_pickup_with_item_id(expected_item_id) == null
	, timeout_sec)
	var live_remote_player: Node = _find_remote_player()
	var remote_inventory: InventorySystem = live_remote_player.get("inventory_system") as InventorySystem if live_remote_player != null else null
	var remote_storage_ids := _get_storage_item_ids(remote_inventory) if remote_inventory != null else []
	_write_json_file(_path_in_dir("host_loot_pickup_sync.json"), {
		"role": "host",
		"passed": host_inventory_synced and pickup_gone,
		"item_id": expected_item_id,
		"remote_storage_ids": remote_storage_ids,
		"pickup_gone": pickup_gone,
	})
	_touch_file(_path_in_dir("host_loot_pickup_sync_done.flag"))
	if not await _wait_for_file(_path_in_dir("client_loot_pickup_sync_done.flag"), timeout_sec):
		_write_json_file(_path_in_dir("host_loot_pickup_sync_error.json"), {"role": "host", "error": "client_result_missing"})
		get_tree().quit(182)
		return
	if host_inventory_synced and pickup_gone:
		get_tree().quit(0)
		return
	get_tree().quit(183)

func _run_loot_pickup_sync_client(local_player: Node, inventory_system: InventorySystem, timeout_sec: float) -> void:
	if not await _wait_for_file(_path_in_dir("host_loot_pickup_sync_target.flag"), timeout_sec):
		_write_json_file(_path_in_dir("client_loot_pickup_sync_error.json"), {"role": "client", "error": "host_target_missing"})
		get_tree().quit(184)
		return
	var target := _read_json_file(_path_in_dir("host_loot_pickup_sync_target.json"))
	var expected_item_id := String(target.get("item_id", ""))
	if expected_item_id.is_empty():
		_write_json_file(_path_in_dir("client_loot_pickup_sync_error.json"), {"role": "client", "error": "invalid_item_id"})
		get_tree().quit(185)
		return
	var pickup_ready := await _wait_for_condition(func() -> bool:
		return _find_loot_pickup_with_item_id(expected_item_id) != null
	, timeout_sec)
	if not pickup_ready:
		_write_json_file(_path_in_dir("client_loot_pickup_sync_error.json"), {"role": "client", "error": "pickup_missing", "item_id": expected_item_id})
		get_tree().quit(186)
		return
	var pickup := _find_loot_pickup_with_item_id(expected_item_id)
	if pickup == null:
		_write_json_file(_path_in_dir("client_loot_pickup_sync_error.json"), {"role": "client", "error": "pickup_lost_before_interact", "item_id": expected_item_id})
		get_tree().quit(187)
		return
	var before_storage_ids := _get_storage_item_ids(inventory_system)
	var dungeon_manager := get_parent()
	dungeon_manager.call("request_interaction", local_player, pickup)
	var inventory_synced := await _wait_for_condition(func() -> bool:
		return _get_storage_item_ids(inventory_system).has(expected_item_id)
	, timeout_sec)
	var pickup_gone := await _wait_for_condition(func() -> bool:
		return _find_loot_pickup_with_item_id(expected_item_id) == null
	, timeout_sec)
	var after_storage_ids := _get_storage_item_ids(inventory_system)
	_write_json_file(_path_in_dir("client_loot_pickup_sync.json"), {
		"role": "client",
		"passed": inventory_synced and pickup_gone,
		"item_id": expected_item_id,
		"before_storage_ids": before_storage_ids,
		"after_storage_ids": after_storage_ids,
		"pickup_gone": pickup_gone,
	})
	_touch_file(_path_in_dir("client_loot_pickup_sync_done.flag"))
	if inventory_synced and pickup_gone:
		get_tree().quit(0)
		return
	get_tree().quit(188)

func _run_loot_pickup_sync_verification() -> void:
	var role := _get_role()
	var timeout_sec := _get_timeout_sec()
	var local_player: Node = await _wait_for_local_player(timeout_sec)
	if local_player == null:
		_write_json_file(_path_in_dir("%s_loot_pickup_sync_error.json" % role), {"role": role, "error": "local_player_not_found"})
		get_tree().quit(177)
		return
	var dungeon_manager := get_parent()
	if dungeon_manager == null:
		_write_json_file(_path_in_dir("%s_loot_pickup_sync_error.json" % role), {"role": role, "error": "dungeon_manager_missing"})
		get_tree().quit(178)
		return
	var inventory_system: InventorySystem = local_player.get("inventory_system") as InventorySystem
	if inventory_system == null:
		_write_json_file(_path_in_dir("%s_loot_pickup_sync_error.json" % role), {"role": role, "error": "inventory_system_missing"})
		get_tree().quit(179)
		return
	_touch_file(_path_in_dir("%s_loot_pickup_sync_ready.flag" % role))
	var other_role := "client" if role == "host" else "host"
	if not await _wait_for_file(_path_in_dir("%s_loot_pickup_sync_ready.flag" % other_role), timeout_sec):
		_write_json_file(_path_in_dir("%s_loot_pickup_sync_error.json" % role), {"role": role, "error": "peer_ready_missing"})
		get_tree().quit(180)
		return

	match role:
		"client":
			await _run_loot_pickup_sync_client(local_player, inventory_system, timeout_sec)
		"host":
			await _run_loot_pickup_sync_host(local_player, inventory_system, dungeon_manager, timeout_sec)
		_:
			_write_json_file(_path_in_dir("error.json"), {"role": role, "error": "invalid_role"})
			get_tree().quit(5)

func _run_enemy_animation_replication_host(local_player: Node, dungeon_manager: Node, timeout_sec: float) -> void:
	var target_state := await _wait_for_enemy_state(dungeon_manager, func(state: Dictionary) -> bool:
		return not bool(state.get("is_proxy", true)) and int(state.get("state", 0)) != 5
	, timeout_sec)
	if target_state.is_empty():
		_write_json_file(_path_in_dir("host_enemy_animation_error.json"), {"role": "host", "error": "target_enemy_missing"})
		get_tree().quit(146)
		return
	var enemy_id := int(target_state.get("id", -1))
	var target_position: Vector3 = target_state.get("position", Vector3.ZERO)
	_force_player_position(local_player, target_position + Vector3(2.5, 0.0, 0.0))
	_write_json_file(_path_in_dir("host_enemy_animation_target.json"), {
		"role": "host",
		"enemy_id": enemy_id,
	})
	_touch_file(_path_in_dir("host_enemy_animation_target.flag"))
	var host_sample := await _sample_enemy_animation(dungeon_manager, enemy_id, 4.0)
	host_sample["role"] = "host"
	host_sample["passed"] = bool(host_sample.get("frame_changed", false)) or bool(host_sample.get("animating_seen", false))
	_write_json_file(_path_in_dir("host_enemy_animation.json"), host_sample)
	_touch_file(_path_in_dir("host_enemy_animation_done.flag"))
	await _wait_for_file(_path_in_dir("client_enemy_animation_done.flag"), minf(timeout_sec, 8.0))
	if bool(host_sample.get("passed", false)):
		get_tree().quit(0)
		return
	get_tree().quit(147)

func _run_enemy_animation_replication_client(dungeon_manager: Node, timeout_sec: float) -> void:
	if not await _wait_for_file(_path_in_dir("host_enemy_animation_target.flag"), timeout_sec):
		_write_json_file(_path_in_dir("client_enemy_animation_error.json"), {"role": "client", "error": "host_target_missing"})
		get_tree().quit(148)
		return
	var target := _read_json_file(_path_in_dir("host_enemy_animation_target.json"))
	var enemy_id := int(target.get("enemy_id", -1))
	if enemy_id < 0:
		_write_json_file(_path_in_dir("client_enemy_animation_error.json"), {"role": "client", "error": "invalid_enemy_id"})
		get_tree().quit(149)
		return
	if not await _wait_for_condition(func() -> bool:
		return not _get_debug_network_enemy_state(dungeon_manager, enemy_id).is_empty()
	, timeout_sec):
		_write_json_file(_path_in_dir("client_enemy_animation_error.json"), {"role": "client", "error": "enemy_proxy_missing", "enemy_id": enemy_id})
		get_tree().quit(150)
		return
	var client_sample := await _sample_enemy_animation(dungeon_manager, enemy_id, 4.0)
	client_sample["role"] = "client"
	if not await _wait_for_file(_path_in_dir("host_enemy_animation_done.flag"), timeout_sec):
		_write_json_file(_path_in_dir("client_enemy_animation_error.json"), {"role": "client", "error": "host_result_missing"})
		get_tree().quit(151)
		return
	var host_sample := _read_json_file(_path_in_dir("host_enemy_animation.json"))
	client_sample["host_passed"] = bool(host_sample.get("passed", false))
	client_sample["passed"] = bool(host_sample.get("passed", false)) and (bool(client_sample.get("frame_changed", false)) or bool(client_sample.get("animating_seen", false)))
	_write_json_file(_path_in_dir("client_enemy_animation.json"), client_sample)
	_touch_file(_path_in_dir("client_enemy_animation_done.flag"))
	if bool(client_sample.get("passed", false)):
		get_tree().quit(0)
		return
	get_tree().quit(152)

func _run_long_run_soak_host(local_player: Node, dungeon_manager: Node, timeout_sec: float) -> void:
	var soak_duration := minf(30.0, maxf(12.0, timeout_sec - 20.0))
	var start_ms := Time.get_ticks_msec()
	var remote_updates := 0
	var last_remote_pos := Vector3.ZERO
	var remote_initialized := false
	var enemy_samples := 0
	while float(Time.get_ticks_msec() - start_ms) * 0.001 <= soak_duration:
		var remote_player: Node = _find_remote_player()
		if remote_player == null or not is_instance_valid(local_player):
			_write_json_file(_path_in_dir("host_soak.json"), {"role": "host", "passed": false, "error": "player_missing_during_soak"})
			get_tree().quit(153)
			return
		if not remote_initialized:
			last_remote_pos = remote_player.global_position
			remote_initialized = true
		elif remote_player.global_position.distance_to(last_remote_pos) > 0.1:
			remote_updates += 1
			last_remote_pos = remote_player.global_position
		if _get_debug_network_enemy_states(dungeon_manager).size() > 0:
			enemy_samples += 1
		await get_tree().create_timer(1.0).timeout
	if not await _wait_for_file(_path_in_dir("client_soak_done.flag"), timeout_sec):
		_write_json_file(_path_in_dir("host_soak.json"), {"role": "host", "passed": false, "error": "client_result_missing"})
		get_tree().quit(154)
		return
	_write_json_file(_path_in_dir("host_soak.json"), {
		"role": "host",
		"passed": remote_updates >= 3 and enemy_samples >= 3,
		"remote_updates": remote_updates,
		"enemy_samples": enemy_samples,
		"duration_sec": soak_duration,
	})
	if remote_updates >= 3 and enemy_samples >= 3:
		get_tree().quit(0)
		return
	get_tree().quit(155)

func _run_long_run_soak_client(local_player: Node, dungeon_manager: Node, timeout_sec: float) -> void:
	var soak_duration := minf(30.0, maxf(12.0, timeout_sec - 20.0))
	var start_ms := Time.get_ticks_msec()
	var toggle := false
	var movement_updates := 0
	var enemy_samples := 0
	var base_pos: Vector3 = local_player.global_position
	while float(Time.get_ticks_msec() - start_ms) * 0.001 <= soak_duration:
		if not is_instance_valid(local_player) or _find_remote_player() == null:
			_write_json_file(_path_in_dir("client_soak.json"), {"role": "client", "passed": false, "error": "player_missing_during_soak"})
			get_tree().quit(156)
			return
		var offset := Vector3(0.4 if toggle else -0.4, 0.0, 0.25 if toggle else -0.25)
		toggle = not toggle
		_force_player_position(local_player, base_pos + offset)
		movement_updates += 1
		if _get_debug_network_enemy_states(dungeon_manager).size() > 0:
			enemy_samples += 1
		await get_tree().create_timer(1.0).timeout
	_touch_file(_path_in_dir("client_soak_done.flag"))
	_write_json_file(_path_in_dir("client_soak.json"), {
		"role": "client",
		"passed": movement_updates >= 3 and enemy_samples >= 3,
		"movement_updates": movement_updates,
		"enemy_samples": enemy_samples,
		"duration_sec": soak_duration,
	})
	if movement_updates >= 3 and enemy_samples >= 3:
		get_tree().quit(0)
		return
	get_tree().quit(157)

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
		"weapon_slot": manager.get_current_weapon_slot(),
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
	var expected_weapon_key := String(selected_weapon.get("weapon_key", ""))
	var expected_weapon_slot := int(selected_weapon.get("weapon_slot", remote_manager.get_current_weapon_slot()))
	var switch_synced := await _wait_for_condition(func() -> bool:
		return (
			remote_manager.get_current_weapon() != null
			and remote_manager.get_current_weapon_slot() == expected_weapon_slot
			and remote_manager.get_current_weapon_key() == expected_weapon_key
		)
	, timeout_sec)
	if not switch_synced:
		_write_json_file(_path_in_dir("host_weapon_after_fire.json"), {
			"role": "host",
			"passed": false,
			"error": "weapon_switch_not_synced",
			"expected_weapon_key": expected_weapon_key,
			"expected_weapon_slot": expected_weapon_slot,
			"actual_weapon_key": remote_manager.get_current_weapon_key(),
			"actual_weapon_slot": remote_manager.get_current_weapon_slot(),
		})
		_touch_file(_path_in_dir("host_weapon_after_fire.flag"))
		get_tree().quit(61)
		return
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

func _wait_for_remote_player(timeout_sec: float):
	var found := await _wait_for_condition(func() -> bool:
		return _find_remote_player() != null
	, timeout_sec)
	if not found:
		return null
	return _find_remote_player()

func _wait_for_player_position(player: Node, expected: Vector3, timeout_sec: float) -> bool:
	return await _wait_for_condition(func() -> bool:
		var resolved_player := _refresh_player_reference(player)
		if resolved_player == null:
			return false
		return resolved_player.global_position.distance_to(expected) <= DEFAULT_POSITION_TOLERANCE
	, timeout_sec)

func _wait_for_peer_position(peer_id: int, expected: Vector3, timeout_sec: float) -> bool:
	return await _wait_for_condition(func() -> bool:
		var player := _find_player_by_peer_id(peer_id)
		if player == null:
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

func _sample_enemy_animation(dungeon_manager: Node, enemy_id: int, duration_sec: float) -> Dictionary:
	var start_state := _get_debug_network_enemy_state(dungeon_manager, enemy_id)
	var start_pos: Vector3 = start_state.get("position", Vector3.ZERO)
	var start_frame := int(start_state.get("anim_frame", 0))
	var frame_changed := false
	var animating_seen := bool(start_state.get("animating", false))
	var max_distance := 0.0
	var start_ms := Time.get_ticks_msec()
	while float(Time.get_ticks_msec() - start_ms) * 0.001 <= duration_sec:
		var state := _get_debug_network_enemy_state(dungeon_manager, enemy_id)
		if state.is_empty():
			return {
				"enemy_missing": true,
				"position_changed": max_distance > 0.25,
				"frame_changed": frame_changed,
				"animating_seen": animating_seen,
			}
		var current_pos: Vector3 = state.get("position", start_pos)
		max_distance = maxf(max_distance, current_pos.distance_to(start_pos))
		frame_changed = frame_changed or int(state.get("anim_frame", start_frame)) != start_frame
		animating_seen = animating_seen or bool(state.get("animating", false))
		await get_tree().create_timer(POLL_INTERVAL_SEC).timeout
	return {
		"enemy_missing": false,
		"position_changed": max_distance > 0.25,
		"frame_changed": frame_changed,
		"animating_seen": animating_seen,
		"distance_moved": max_distance,
		"start_frame": start_frame,
	}

func _fire_network_weapon_requests(dungeon_manager: Node, local_player: Node, manager: WeaponManager, aim_target: Vector3, shot_count: int, shot_seed_offset: int) -> void:
	var fire_offsets := [
		Vector3(0.0, 0.3, 2.5),
		Vector3(0.0, 0.3, -2.5),
		Vector3(2.5, 0.3, 0.0),
		Vector3(-2.5, 0.3, 0.0),
	]
	var local_peer_id := _get_player_peer_id(local_player)
	for i in range(shot_count):
		var fire_origin: Vector3 = aim_target + fire_offsets[i % fire_offsets.size()]
		var fire_direction: Vector3 = (aim_target - fire_origin).normalized()
		dungeon_manager.call(
			"request_weapon_fire",
			local_peer_id,
			manager.get_current_weapon_slot(),
			manager.get_current_weapon_key(),
			fire_origin,
			fire_direction,
			int(Time.get_ticks_msec()) + shot_seed_offset + i
		)
		await get_tree().create_timer(0.35).timeout

func _wait_for_enemy_state(dungeon_manager: Node, predicate: Callable, timeout_sec: float) -> Dictionary:
	var start_ms := Time.get_ticks_msec()
	while float(Time.get_ticks_msec() - start_ms) * 0.001 <= timeout_sec:
		for state_variant in _get_debug_network_enemy_states(dungeon_manager):
			if typeof(state_variant) != TYPE_DICTIONARY:
				continue
			var state: Dictionary = state_variant
			if bool(predicate.call(state)):
				return state
		await get_tree().create_timer(POLL_INTERVAL_SEC).timeout
	return {}

func _get_debug_network_enemy_states(dungeon_manager: Node) -> Array:
	if dungeon_manager == null or not dungeon_manager.has_method("get_debug_network_enemy_states"):
		return []
	var states_variant: Variant = dungeon_manager.call("get_debug_network_enemy_states")
	if typeof(states_variant) != TYPE_ARRAY:
		return []
	return states_variant

func _get_debug_network_enemy_state(dungeon_manager: Node, enemy_id: int) -> Dictionary:
	for state_variant in _get_debug_network_enemy_states(dungeon_manager):
		if typeof(state_variant) != TYPE_DICTIONARY:
			continue
		var state: Dictionary = state_variant
		if int(state.get("id", -1)) == enemy_id:
			return state
	return {}

func _get_loot_pickup_snapshots() -> Array:
	var snapshots: Array = []
	for pickup_variant in get_tree().get_nodes_in_group("loot_pickup"):
		if not is_instance_valid(pickup_variant):
			continue
		if not (pickup_variant is Node3D):
			continue
		var pickup: Node3D = pickup_variant
		var item_snapshot := {}
		if pickup.has_method("get_item_snapshot"):
			item_snapshot = pickup.call("get_item_snapshot")
		snapshots.append({
			"position": _vec3_to_dict(pickup.global_position),
			"network_loot_id": int(pickup.get_meta("network_loot_id", -1)),
			"item": item_snapshot,
		})
	snapshots.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("network_loot_id", -1)) < int(b.get("network_loot_id", -1))
	)
	return snapshots

func _find_loot_pickup_with_item_id(item_id: String) -> Node3D:
	for pickup_variant in get_tree().get_nodes_in_group("loot_pickup"):
		if not is_instance_valid(pickup_variant):
			continue
		if not (pickup_variant is Node3D):
			continue
		var pickup: Node3D = pickup_variant
		if not pickup.has_method("get_item_snapshot"):
			continue
		var item_snapshot: Dictionary = pickup.call("get_item_snapshot")
		if String(item_snapshot.get("item_id", "")) == item_id:
			return pickup
	return null

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

func _wait_for_world_ready(timeout_sec: float) -> bool:
	return await _wait_for_condition(func() -> bool:
		var dungeon_manager: Node = get_parent()
		if dungeon_manager == null:
			return false
		if dungeon_manager.get("_floor_sync_in_progress"):
			return false
		var local_player: Node = _find_local_player()
		if local_player == null:
			return false
		if _get_player_peer_id(local_player) != _get_local_peer_id():
			return false
		if not _is_multiplayer_session_active():
			return true
		return _get_network_players().size() >= 2 and _find_remote_player() != null
	, timeout_sec)

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
	var players: Array = []
	for node_variant in get_tree().get_nodes_in_group("player"):
		if not (node_variant is Node):
			continue
		var player: Node = node_variant
		if not is_instance_valid(player) or not player.is_inside_tree():
			continue
		players.append(player)
	return players

func _find_player_by_peer_id(peer_id: int) -> Node:
	if peer_id < 0:
		return null
	for node_variant in _get_network_players():
		if not (node_variant is Node):
			continue
		var candidate: Node = node_variant
		if _get_player_peer_id(candidate) == peer_id:
			return candidate
	return null

func _refresh_player_reference(player: Variant) -> Node:
	if player is Node and is_instance_valid(player) and player.is_inside_tree():
		var live_player: Node = player
		return live_player
	if not (player is Node):
		return null
	return _find_player_by_peer_id(_get_player_peer_id(player))

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

func _hold_player_position_window(player: Node, target: Vector3, duration_sec: float) -> void:
	var start_ms := Time.get_ticks_msec()
	while float(Time.get_ticks_msec() - start_ms) * 0.001 <= duration_sec:
		if player == null or not is_instance_valid(player) or not player.is_inside_tree():
			return
		_force_player_position(player, target)
		await get_tree().create_timer(0.1).timeout

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

func _get_storage_item_ids(inventory_system: InventorySystem) -> Array:
	if inventory_system == null:
		return []
	var snapshot: Dictionary = inventory_system.get_slot_snapshot()
	var ids: Array = []
	for item_variant in snapshot.get("storage", []):
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

func _is_multiplayer_session_active() -> bool:
	var session = get_node_or_null("/root/NetworkSession")
	if session == null:
		return false
	return bool(session.call("is_multiplayer_active"))

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
