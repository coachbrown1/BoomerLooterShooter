## NetworkPlayerManager — AutoLoad
##
## Handles player spawning and roster sync for every level.
## Usage (from any level manager's _ready()):
##
##   NetworkPlayerManager.players_ready.connect(_on_players_ready)
##   NetworkPlayerManager.setup([ spawn_pos_0, spawn_pos_1, ... ])
##
##   func _on_players_ready(players: Dictionary) -> void:
##       var local := NetworkPlayerManager.get_local_player()
##
## spawn_positions[0] = host / single-player
## spawn_positions[1] = first remote peer, [2] = second, etc.

extends Node

const PLAYER_SCENE: PackedScene = preload("res://Scenes/Player/player.tscn")

## Emitted once all players are placed.  Key = peer_id (0 in single-player).
signal players_ready(player_by_peer_id: Dictionary)

var _player_by_peer_id: Dictionary = {}
var _spawn_positions: Array[Vector3] = []

func _ready() -> void:
	_bind_session_signals()

# ─────────────────────────────────────────────────────────────────────────────
# Public API
# ─────────────────────────────────────────────────────────────────────────────

## Call from any level manager's _ready() after the scene tree is ready.
func setup(spawn_positions: Array[Vector3]) -> void:
	_bind_session_signals()
	_spawn_positions = spawn_positions.duplicate()
	_prune_invalid_players()
	if not NetworkSession.is_multiplayer_active():
		_setup_singleplayer(spawn_positions)
	elif NetworkSession.is_host():
		_setup_host(spawn_positions)
	else:
		_setup_client(spawn_positions)

## Returns the locally-controlled player node, or null.
func get_local_player() -> Node3D:
	_prune_invalid_players()
	var key := NetworkSession.get_local_peer_id() if NetworkSession.is_multiplayer_active() else 0
	return _player_by_peer_id.get(key, null)

## Returns the player node for a specific peer, or null.
func get_player(peer_id: int) -> Node3D:
	_prune_invalid_players()
	return _player_by_peer_id.get(peer_id, null)

## Returns a copy of the full peer_id → player dictionary.
func get_all_players() -> Dictionary:
	_prune_invalid_players()
	return _player_by_peer_id.duplicate()

## Returns the current peer roster payload used by roster sync.
func get_roster_payload() -> Array:
	_prune_invalid_players()
	var roster: Array = []
	for pid in _player_by_peer_id.keys():
		var player = _player_by_peer_id[pid]
		if _is_live_player_node(player):
			roster.append({ "peer_id": int(pid), "position": player.global_position })
	return roster

func clear_players() -> void:
	_clear_known_players()

func remove_peer(peer_id: int) -> void:
	if peer_id < 0:
		return
	var player = _player_by_peer_id.get(peer_id, null)
	if is_instance_valid(player):
		player.queue_free()
	_player_by_peer_id.erase(peer_id)
	_emit_players_ready()

func sync_roster_to(peer_id: int) -> void:
	if not NetworkSession.is_multiplayer_active():
		return
	rpc_id(peer_id, "rpc_npm_sync_roster", get_roster_payload())

func sync_roster_to_all() -> void:
	if not NetworkSession.is_multiplayer_active() or not NetworkSession.is_host():
		return
	for peer_id in NetworkSession.get_connected_peer_ids():
		sync_roster_to(peer_id)

func apply_roster(roster: Array, preserve_local: bool = true) -> void:
	_prune_invalid_players()
	var roster_peer_ids := {}
	for entry_variant in roster:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		var peer_id := int(entry.get("peer_id", -1))
		if peer_id < 0:
			continue
		roster_peer_ids[peer_id] = true
		var pos: Vector3 = entry.get("position", Vector3.ZERO)
		_spawn_for_peer(peer_id, pos)

	var local_id := NetworkSession.get_local_peer_id() if NetworkSession.is_multiplayer_active() else 0
	var to_remove: Array[int] = []
	for peer_id_variant in _player_by_peer_id.keys():
		var peer_id := int(peer_id_variant)
		if preserve_local and peer_id == local_id:
			continue
		if roster_peer_ids.has(peer_id):
			continue
		to_remove.append(peer_id)
	for peer_id in to_remove:
		remove_peer(peer_id)
	_emit_players_ready()

# ─────────────────────────────────────────────────────────────────────────────
# Internal setup paths
# ─────────────────────────────────────────────────────────────────────────────

func _setup_singleplayer(spawn_positions: Array[Vector3]) -> void:
	_spawn_for_peer(0, _get_pos(spawn_positions, 0))
	_remove_players_except([0])
	_emit_players_ready()

func _setup_host(spawn_positions: Array[Vector3]) -> void:
	var local_id := NetworkSession.get_local_peer_id()
	var expected_peer_ids: Array[int] = [local_id]
	_spawn_for_peer(local_id, _get_pos(spawn_positions, 0))
	var peers := NetworkSession.get_connected_peer_ids()
	for i in range(peers.size()):
		var peer_id := int(peers[i])
		expected_peer_ids.append(peer_id)
		_spawn_for_peer(peer_id, _get_pos(spawn_positions, i + 1))
	_remove_players_except(expected_peer_ids)
	_emit_players_ready()
	for peer_id in NetworkSession.get_connected_peer_ids():
		sync_roster_to(peer_id)

func _setup_client(spawn_positions: Array[Vector3]) -> void:
	var local_id := NetworkSession.get_local_peer_id()
	var local_index := 1 if spawn_positions.size() > 1 else 0
	_spawn_for_peer(local_id, _get_pos(spawn_positions, local_index))
	_emit_players_ready()
	await get_tree().process_frame
	rpc_id(1, "rpc_npm_client_ready", local_id)

# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────

func _spawn_for_peer(peer_id: int, pos: Vector3) -> Node3D:
	var existing = _player_by_peer_id.get(peer_id, null)
	if _is_live_player_node(existing) and existing is Node3D:
		existing.global_position = pos
		return existing
	if existing != null:
		_player_by_peer_id.erase(peer_id)
	var player := _find_existing_scene_player(peer_id)
	if not (player is Node3D):
		player = PLAYER_SCENE.instantiate()
		get_tree().current_scene.add_child(player)
	player.call("set_network_peer_id", peer_id)
	player.global_position = pos
	_player_by_peer_id[peer_id] = player
	return player

func _get_pos(positions: Array[Vector3], idx: int) -> Vector3:
	if idx < positions.size():
		return positions[idx]
	return _fallback_pos(positions, idx)

func _fallback_pos(positions: Array[Vector3], idx: int) -> Vector3:
	var base := positions[0] if positions.size() > 0 else Vector3.ZERO
	return base + Vector3(2.0 * idx, 0.0, 0.0)

func _send_roster_to(peer_id: int) -> void:
	sync_roster_to(peer_id)

# ─────────────────────────────────────────────────────────────────────────────
# Per-frame state sync
# ─────────────────────────────────────────────────────────────────────────────

func _process(_delta: float) -> void:
	_prune_invalid_players()
	if not NetworkSession.is_multiplayer_active() or _player_by_peer_id.is_empty():
		return
	if NetworkSession.is_host():
		_broadcast_snapshots()
	else:
		_send_local_snapshot()

func _send_local_snapshot() -> void:
	var local_id := NetworkSession.get_local_peer_id()
	var player = _player_by_peer_id.get(local_id, null)
	if not _is_live_player_node(player) or not player.has_method("build_network_snapshot"):
		return
	rpc_id(1, "rpc_npm_submit_state", local_id, player.call("build_network_snapshot"))

func _broadcast_snapshots() -> void:
	var snapshots: Array = []
	for peer_id in _player_by_peer_id.keys():
		var player = _player_by_peer_id[peer_id]
		if _is_live_player_node(player) and player.has_method("build_network_snapshot"):
			snapshots.append({ "peer_id": int(peer_id), "state": player.call("build_network_snapshot") })
	if snapshots.is_empty():
		return
	for peer_id in NetworkSession.get_connected_peer_ids():
		rpc_id(peer_id, "rpc_npm_receive_snapshots", snapshots)

# ─────────────────────────────────────────────────────────────────────────────
# RPCs — live on the autoload so they work identically from every scene
# ─────────────────────────────────────────────────────────────────────────────

@rpc("any_peer", "reliable")
func rpc_npm_client_ready(peer_id: int) -> void:
	if not NetworkSession.is_host():
		return
	if multiplayer.get_remote_sender_id() != peer_id:
		return
	# Ensure a slot exists for this client even if they connected after setup().
	if not _player_by_peer_id.has(peer_id):
		var pos := _get_pos(_spawn_positions, _player_by_peer_id.size())
		_spawn_for_peer(peer_id, pos)
	sync_roster_to(peer_id)

@rpc("any_peer", "unreliable")
func rpc_npm_submit_state(peer_id: int, snapshot: Dictionary) -> void:
	if not NetworkSession.is_host() or multiplayer.get_remote_sender_id() != peer_id:
		return
	var player = _player_by_peer_id.get(peer_id, null)
	if _is_live_player_node(player) and player.has_method("apply_network_snapshot"):
		var s := snapshot.duplicate(true)
		s.erase("health")  # host owns health authority
		player.call("apply_network_snapshot", s)

@rpc("authority", "call_remote", "unreliable")
func rpc_npm_receive_snapshots(snapshots: Array) -> void:
	var local_id := NetworkSession.get_local_peer_id()
	for entry_variant in snapshots:
		var entry: Dictionary = entry_variant
		var peer_id := int(entry.get("peer_id", -1))
		var player = _player_by_peer_id.get(peer_id, null)
		if not _is_live_player_node(player):
			continue
		var state: Dictionary = entry.get("state", {})
		if peer_id == local_id:
			if state.has("health") and player.has_method("apply_authoritative_health"):
				player.call("apply_authoritative_health", int(state.get("health", 0)))
			continue
		if player.has_method("apply_network_snapshot"):
			player.call("apply_network_snapshot", state)

@rpc("authority", "call_remote", "reliable")
func rpc_npm_sync_roster(roster: Array) -> void:
	apply_roster(roster)

func _find_existing_scene_player(peer_id: int) -> Node3D:
	if peer_id >= 0 and NetworkSession.is_multiplayer_active():
		var local_id := NetworkSession.get_local_peer_id()
		if peer_id != local_id:
			return null
	for player_variant in get_tree().get_nodes_in_group("player"):
		if not (player_variant is Node3D):
			continue
		var player: Node3D = player_variant
		if _player_by_peer_id.values().has(player):
			continue
		if not _is_live_player_node(player):
			continue
		return player
	return null

func _clear_known_players() -> void:
	for player_variant in _player_by_peer_id.values():
		if player_variant is Node and is_instance_valid(player_variant):
			var player: Node = player_variant
			player.queue_free()
	_player_by_peer_id.clear()

func _prune_invalid_players() -> void:
	var stale_peer_ids: Array[int] = []
	for peer_id_variant in _player_by_peer_id.keys():
		var peer_id := int(peer_id_variant)
		var player = _player_by_peer_id.get(peer_id, null)
		if not _is_live_player_node(player):
			stale_peer_ids.append(peer_id)
	for peer_id in stale_peer_ids:
		_player_by_peer_id.erase(peer_id)

func _remove_players_except(peer_ids: Array[int]) -> void:
	var to_remove: Array[int] = []
	for peer_id_variant in _player_by_peer_id.keys():
		var peer_id := int(peer_id_variant)
		if peer_ids.has(peer_id):
			continue
		to_remove.append(peer_id)
	for peer_id in to_remove:
		var player = _player_by_peer_id.get(peer_id, null)
		if _is_live_player_node(player):
			player.queue_free()
		_player_by_peer_id.erase(peer_id)

func _is_live_player_node(player: Variant) -> bool:
	if not (player is Node3D):
		return false
	var node: Node3D = player
	if not is_instance_valid(node):
		return false
	if not node.is_inside_tree():
		return false
	var current_scene := get_tree().current_scene
	if current_scene == null:
		return false
	return node == current_scene or current_scene.is_ancestor_of(node)

func _emit_players_ready() -> void:
	players_ready.emit(get_all_players())

func _bind_session_signals() -> void:
	var left_cb := Callable(self, "_on_session_peer_left")
	if not NetworkSession.is_connected("peer_left", left_cb):
		NetworkSession.peer_left.connect(_on_session_peer_left)
	var ended_cb := Callable(self, "_on_session_ended")
	if not NetworkSession.is_connected("session_ended", ended_cb):
		NetworkSession.session_ended.connect(_on_session_ended)

func _on_session_peer_left(peer_id: int) -> void:
	if not NetworkSession.is_host():
		return
	remove_peer(peer_id)
	sync_roster_to_all()

func _on_session_ended(_reason: String) -> void:
	_clear_known_players()
