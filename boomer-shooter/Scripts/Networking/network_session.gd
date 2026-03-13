extends Node

signal session_started(is_host: bool)
signal peer_joined(peer_id: int)
signal peer_left(peer_id: int)
signal match_started
signal session_ended(reason: String)
signal connection_failed(reason: String)

const DEFAULT_PORT: int = 7000
const MAX_PLAYERS: int = 2

var _peer: ENetMultiplayerPeer = null
var _host: bool = false
var _active: bool = false
var _match_started: bool = false

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

func host_game(port: int = DEFAULT_PORT) -> bool:
	_leave_internal(false)
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PLAYERS)
	if err != OK:
		connection_failed.emit("Failed to host on port %d (error %d)." % [port, err])
		return false

	_peer = peer
	multiplayer.multiplayer_peer = _peer
	_host = true
	_active = true
	_match_started = false
	session_started.emit(true)
	return true

func join_game(address: String, port: int = DEFAULT_PORT) -> bool:
	_leave_internal(false)
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address.strip_edges(), port)
	if err != OK:
		connection_failed.emit("Failed to connect to %s:%d (error %d)." % [address, port, err])
		return false

	_peer = peer
	multiplayer.multiplayer_peer = _peer
	_host = false
	_active = false
	_match_started = false
	return true

func leave_game() -> void:
	_leave_internal(true, "left_session")

func is_host() -> bool:
	return _active and _host

func is_multiplayer_active() -> bool:
	return _active

func is_match_started() -> bool:
	return _match_started

func start_match() -> bool:
	if not _active:
		connection_failed.emit("Session is not active.")
		return false
	if not _host:
		connection_failed.emit("Only host can start the match.")
		return false
	if _match_started:
		return true
	if multiplayer.get_peers().is_empty():
		connection_failed.emit("Waiting for a client to join.")
		return false

	_match_started = true
	match_started.emit()
	rpc("rpc_begin_match")
	return true

func get_local_peer_id() -> int:
	if multiplayer.multiplayer_peer == null:
		return 1
	return multiplayer.get_unique_id()

func get_connected_peer_ids() -> PackedInt32Array:
	if multiplayer.multiplayer_peer == null:
		return PackedInt32Array()
	return multiplayer.get_peers()

func _leave_internal(emit_ended: bool, reason: String = "") -> void:
	var had_peer := multiplayer.multiplayer_peer != null
	var had_active := _active

	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null

	_peer = null
	_host = false
	_active = false
	_match_started = false

	if emit_ended and (had_peer or had_active):
		session_ended.emit(reason)

func _on_connected_to_server() -> void:
	_active = true
	session_started.emit(false)

func _on_connection_failed() -> void:
	_leave_internal(false)
	connection_failed.emit("Unable to reach host.")

func _on_server_disconnected() -> void:
	_leave_internal(false)
	session_ended.emit("server_disconnected")

func _on_peer_connected(peer_id: int) -> void:
	if _host and _match_started and _peer != null:
		_peer.disconnect_peer(peer_id, true)
		return
	if _active:
		peer_joined.emit(peer_id)

func _on_peer_disconnected(peer_id: int) -> void:
	if _active:
		peer_left.emit(peer_id)

@rpc("authority", "call_remote", "reliable")
func rpc_begin_match() -> void:
	if _match_started:
		return
	_match_started = true
	match_started.emit()
