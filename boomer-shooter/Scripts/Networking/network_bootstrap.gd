extends Node

const DUNGEON_SCENE_PATH := "res://Scenes/World/dungeon.tscn"
const DEFAULT_PORT_FALLBACK := 7000

@onready var _status_label: Label = $CanvasLayer/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/StatusLabel
@onready var _ip_input: LineEdit = $CanvasLayer/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/IpInput
@onready var _port_input: LineEdit = $CanvasLayer/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/PortInput
@onready var _host_button: Button = $CanvasLayer/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/Buttons/HostButton
@onready var _join_button: Button = $CanvasLayer/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/Buttons/JoinButton
@onready var _single_button: Button = $CanvasLayer/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/Buttons/SingleButton
@onready var _start_button: Button = $CanvasLayer/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/Buttons/StartButton
@onready var _leave_button: Button = $CanvasLayer/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/Buttons/LeaveButton

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	var session = _get_network_session()
	if session == null:
		_set_status("NetworkSession autoload missing.")
	else:
		var started_cb := Callable(self, "_on_session_started")
		if not session.is_connected("session_started", started_cb):
			session.connect("session_started", started_cb)
		var failed_cb := Callable(self, "_on_connection_failed")
		if not session.is_connected("connection_failed", failed_cb):
			session.connect("connection_failed", failed_cb)
		var ended_cb := Callable(self, "_on_session_ended")
		if not session.is_connected("session_ended", ended_cb):
			session.connect("session_ended", ended_cb)
		var joined_cb := Callable(self, "_on_peer_joined")
		if not session.is_connected("peer_joined", joined_cb):
			session.connect("peer_joined", joined_cb)
		var left_cb := Callable(self, "_on_peer_left")
		if not session.is_connected("peer_left", left_cb):
			session.connect("peer_left", left_cb)
		var match_cb := Callable(self, "_on_match_started")
		if not session.is_connected("match_started", match_cb):
			session.connect("match_started", match_cb)
	_update_ui_state()
	_update_leave_button()

func _on_single_button_pressed() -> void:
	if _is_multiplayer_active():
		_leave_game()
	_change_to_dungeon()

func _on_host_button_pressed() -> void:
	_set_status("Hosting...")
	var port := _parse_port()
	var session = _get_network_session()
	if session == null:
		_set_status("NetworkSession unavailable.")
		return
	if not bool(session.call("host_game", port)):
		return
	_set_status("Hosting on port %d. Waiting for client..." % port)
	_update_ui_state()

func _on_join_button_pressed() -> void:
	var host := _ip_input.text.strip_edges()
	if host.is_empty():
		_set_status("Enter host IP.")
		return
	_set_status("Joining %s..." % host)
	var port := _parse_port()
	var session = _get_network_session()
	if session == null:
		_set_status("NetworkSession unavailable.")
		return
	session.call("join_game", host, port)
	_update_ui_state()

func _on_leave_button_pressed() -> void:
	_leave_game()
	_set_status("Session closed.")
	_update_ui_state()
	_update_leave_button()

func _on_start_button_pressed() -> void:
	var session = _get_network_session()
	if session == null:
		_set_status("NetworkSession unavailable.")
		return
	if not bool(session.call("start_match")):
		return
	_set_status("Starting match...")
	_update_ui_state()

func _on_session_started(is_host: bool) -> void:
	if is_host:
		_set_status("Hosting. Waiting for client...")
	else:
		_set_status("Connected. Waiting for host to start...")
	_update_ui_state()

func _on_connection_failed(reason: String) -> void:
	_set_status(reason)
	_update_ui_state()
	_update_leave_button()

func _on_session_ended(reason: String) -> void:
	if reason == "server_disconnected":
		_set_status("Host disconnected.")
	else:
		_set_status("Session ended.")
	_update_ui_state()
	_update_leave_button()

func _on_peer_joined(_peer_id: int) -> void:
	var session = _get_network_session()
	if session == null:
		return
	if bool(session.call("is_host")) and not bool(session.call("is_match_started")):
		_set_status("Client joined. Press Start Game.")
	_update_ui_state()

func _on_peer_left(_peer_id: int) -> void:
	var session = _get_network_session()
	if session == null:
		return
	if bool(session.call("is_host")) and not bool(session.call("is_match_started")):
		_set_status("Client left. Waiting for client...")
	_update_ui_state()

func _on_match_started() -> void:
	_change_to_dungeon()

func _change_to_dungeon() -> void:
	var err := get_tree().change_scene_to_file(DUNGEON_SCENE_PATH)
	if err != OK:
		_set_status("Failed to load dungeon (error %d)." % err)

func _parse_port() -> int:
	var text := _port_input.text.strip_edges()
	if text.is_empty():
		return DEFAULT_PORT_FALLBACK
	var value := int(text)
	if value <= 0:
		return DEFAULT_PORT_FALLBACK
	return value

func _set_status(text: String) -> void:
	_status_label.text = text

func _update_leave_button() -> void:
	_leave_button.visible = _is_multiplayer_active()

func _update_ui_state() -> void:
	var session = _get_network_session()
	if session == null:
		return

	var active := bool(session.call("is_multiplayer_active"))
	var host := bool(session.call("is_host"))
	var started := bool(session.call("is_match_started"))
	var peers: PackedInt32Array = session.call("get_connected_peer_ids")
	var has_client := peers.size() > 0

	_single_button.disabled = active
	_host_button.disabled = active
	_join_button.disabled = active
	_ip_input.editable = not active
	_port_input.editable = not active
	_start_button.visible = active and host and not started
	_start_button.disabled = not has_client

func _get_network_session():
	if is_inside_tree():
		return get_node_or_null("/root/NetworkSession")
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		var tree: SceneTree = loop
		if tree.root != null:
			return tree.root.get_node_or_null("NetworkSession")
	return null

func _is_multiplayer_active() -> bool:
	var session = _get_network_session()
	if session == null:
		return false
	return bool(session.call("is_multiplayer_active"))

func _leave_game() -> void:
	var session = _get_network_session()
	if session == null:
		return
	session.call("leave_game")
