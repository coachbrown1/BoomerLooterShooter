extends Node

const DUNGEON_SCENE_PATH := "res://Scenes/World/dungeon.tscn"
const HUB_SCENE_PATH     := "res://Scenes/World/hub.tscn"
const DEFAULT_PORT_FALLBACK := 7000
const ARG_ROLE := "--net-role"
const ARG_HOST := "--net-host"
const ARG_PORT := "--net-port"
const ARG_AUTO_START := "--net-auto-start"
const ARG_VERIFY_SCENARIO := "--verify-scenario"
const VERSION_FALLBACK := "dev"
const PUBLIC_IP_URL := "https://api.ipify.org"

@onready var _status_label: Label = $CanvasLayer/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/StatusLabel
@onready var _connection_fields: VBoxContainer = $CanvasLayer/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/ConnectionFields
@onready var _connection_prompt_label: Label = $CanvasLayer/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/ConnectionFields/ConnectionPromptLabel
@onready var _ip_input: LineEdit = $CanvasLayer/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/ConnectionFields/IpInput
@onready var _port_input: LineEdit = $CanvasLayer/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/ConnectionFields/PortInput
@onready var _title_label: Label = $CanvasLayer/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/Title
@onready var _host_info_label: Label = $CanvasLayer/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/HostInfoLabel
@onready var _firewall_hint_label: Label = $CanvasLayer/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/FirewallHintLabel
@onready var _host_button: Button = $CanvasLayer/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/Buttons/HostButton
@onready var _join_button: Button = $CanvasLayer/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/Buttons/JoinButton
@onready var _single_button: Button = $CanvasLayer/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/Buttons/SingleButton
@onready var _start_button: Button = $CanvasLayer/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/Buttons/StartButton
@onready var _leave_button: Button = $CanvasLayer/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/Buttons/LeaveButton
@onready var _quit_button: Button = $CanvasLayer/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/Buttons/QuitButton
@onready var _public_ip_request: HTTPRequest = $PublicIpRequest

var _automation_cfg := {}
var _join_mode := false
var _public_ip_text := ""
var _public_ip_pending := false

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_apply_release_metadata()
	if _public_ip_request != null:
		var completed_cb := Callable(self, "_on_public_ip_request_completed")
		if not _public_ip_request.is_connected("request_completed", completed_cb):
			_public_ip_request.request_completed.connect(_on_public_ip_request_completed)
	_seed_default_join_fields()
	_automation_cfg = _parse_automation_args(OS.get_cmdline_user_args())
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
	_update_host_info_label()
	if not _automation_cfg.is_empty():
		$CanvasLayer.visible = false
		call_deferred("_run_automation")

func _on_single_button_pressed() -> void:
	if _is_multiplayer_active():
		_leave_game()
	_change_to_dungeon()

func _on_host_button_pressed() -> void:
	_join_mode = false
	var port := _parse_port()
	var session = _get_network_session()
	if session == null:
		_set_status("NetworkSession unavailable.")
		return
	if not bool(session.call("host_game", port)):
		return
	_fetch_public_ip()
	_set_status("")
	_update_ui_state()
	_update_host_info_label()

func _on_join_button_pressed() -> void:
	if not _is_multiplayer_active() and not _join_mode:
		_join_mode = true
		_set_status("")
		_update_ui_state()
		return
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
	_join_mode = false
	_public_ip_pending = false
	_public_ip_text = ""
	_set_status("Session closed.")
	_update_ui_state()
	_update_leave_button()
	_update_host_info_label()

func _on_quit_button_pressed() -> void:
	get_tree().quit()

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
		_join_mode = false
		_fetch_public_ip()
		_set_status("")
	else:
		_join_mode = false
		_set_status("")
	_update_ui_state()
	_update_host_info_label()

func _on_connection_failed(reason: String) -> void:
	_public_ip_pending = false
	_set_status(reason)
	_update_ui_state()
	_update_leave_button()
	_update_host_info_label()

func _on_session_ended(reason: String) -> void:
	_join_mode = false
	_public_ip_pending = false
	_public_ip_text = ""
	if reason == "server_disconnected":
		_set_status("Host disconnected.")
	else:
		_set_status("Session ended.")
	_update_ui_state()
	_update_leave_button()
	_update_host_info_label()

func _on_peer_joined(_peer_id: int) -> void:
	var session = _get_network_session()
	if session == null:
		return
	if bool(session.call("is_host")) and not bool(session.call("is_match_started")):
		if bool(_automation_cfg.get("auto_start", false)):
			call_deferred("_try_auto_start_match")
	_update_ui_state()
	_update_host_info_label()

func _on_peer_left(_peer_id: int) -> void:
	var session = _get_network_session()
	if session == null:
		return
	if bool(session.call("is_host")) and not bool(session.call("is_match_started")):
		_set_status("")
	_update_ui_state()
	_update_host_info_label()

func _on_match_started() -> void:
	_change_to_dungeon()

func _change_to_dungeon() -> void:
	var scene_path := HUB_SCENE_PATH
	# Keep verifier runs on the dungeon scene so the multiplayer harness can
	# exercise the existing debug node and dungeon-specific scenarios.
	if _is_verifier_run():
		scene_path = DUNGEON_SCENE_PATH
	var err := get_tree().change_scene_to_file(scene_path)
	if err != OK:
		_set_status("Failed to load scene (error %d)." % err)

func _apply_release_metadata() -> void:
	var version := String(ProjectSettings.get_setting("application/config/version", VERSION_FALLBACK))
	if _title_label != null:
		_title_label.text = "BoomerShooter - %s" % version
	DisplayServer.window_set_title("BoomerShooter %s" % version)

func _seed_default_join_fields() -> void:
	if _ip_input != null:
		_ip_input.text = ""
	if _port_input != null:
		_port_input.text = str(DEFAULT_PORT_FALLBACK)

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
	_status_label.visible = not text.is_empty()

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
	var show_join_fields := not active and _join_mode

	_single_button.disabled = active
	_host_button.disabled = active
	_join_button.disabled = active
	_join_button.text = "Connect" if show_join_fields and not active else "Join"
	_connection_fields.visible = show_join_fields
	_connection_prompt_label.visible = show_join_fields
	_ip_input.editable = show_join_fields and not active
	_port_input.editable = show_join_fields and not active
	_start_button.visible = active and host and not started
	_start_button.disabled = not has_client
	_quit_button.visible = not active
	_host_info_label.visible = active and host
	_firewall_hint_label.visible = active and host
	if show_join_fields:
		_connection_prompt_label.text = "Enter the host's IP and port, then click CONNECT."

func _update_host_info_label() -> void:
	if _host_info_label == null:
		return

	var session = _get_network_session()
	if session == null or not bool(session.call("is_multiplayer_active")):
		_host_info_label.text = ""
		return

	if not bool(session.call("is_host")):
		_host_info_label.text = ""
		return

	var addresses := _get_local_ipv4_addresses()
	var port := _parse_port()
	var lan_text := "No non-loopback IPv4 address detected on this machine."
	if not addresses.is_empty():
		lan_text = ", ".join(addresses)
	var public_text := "Fetching public IP..."
	if not _public_ip_pending:
		public_text = "Unavailable"
	if not _public_ip_text.is_empty():
		public_text = _public_ip_text
	_host_info_label.text = "Share your LAN/public IP and port with your guest\nLAN IP: %s\nPublic IP: %s\nPort: %d" % [lan_text, public_text, port]
	_firewall_hint_label.text = "If players can't connect, ensure port %d UDP is allowed\nthrough your firewall (Windows: search 'Allow an app through Windows Firewall')." % port

func _fetch_public_ip() -> void:
	if _public_ip_request == null:
		return
	if _public_ip_pending:
		return
	_public_ip_pending = true
	_public_ip_text = ""
	_update_host_info_label()
	var err := _public_ip_request.request(PUBLIC_IP_URL)
	if err != OK:
		_public_ip_pending = false
		_public_ip_text = "Unavailable"
		_update_host_info_label()

func _on_public_ip_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_public_ip_pending = false
	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
		_public_ip_text = "Unavailable"
		_update_host_info_label()
		return
	_public_ip_text = body.get_string_from_utf8().strip_edges()
	if _public_ip_text.is_empty():
		_public_ip_text = "Unavailable"
	_update_host_info_label()

func _get_local_ipv4_addresses() -> Array[String]:
	var addresses: Array[String] = []
	for address_variant in IP.get_local_addresses():
		var address := String(address_variant)
		if address.contains(":"):
			continue
		if address.begins_with("127."):
			continue
		if address == "0.0.0.0":
			continue
		addresses.append(address)
	addresses.sort_custom(func(a: String, b: String) -> bool:
		return _ip_priority(a) < _ip_priority(b)
	)
	return addresses

func _get_preferred_local_ipv4() -> String:
	var addresses := _get_local_ipv4_addresses()
	if addresses.is_empty():
		return ""
	return addresses[0]

func _ip_priority(address: String) -> int:
	if address.begins_with("192.168."):
		return 0
	if address.begins_with("10."):
		return 1
	if address.begins_with("172."):
		var octets := address.split(".")
		if octets.size() >= 2:
			var second_octet := int(octets[1])
			if second_octet >= 16 and second_octet <= 31:
				return 2
	return 3

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

func _run_automation() -> void:
	var role := String(_automation_cfg.get("role", ""))
	var host := String(_automation_cfg.get("host", "127.0.0.1"))
	var port := int(_automation_cfg.get("port", DEFAULT_PORT_FALLBACK))
	match role:
		"single":
			_on_single_button_pressed()
		"host":
			_port_input.text = str(port)
			_on_host_button_pressed()
		"client":
			_ip_input.text = host
			_port_input.text = str(port)
			_join_mode = true
			_on_join_button_pressed()

func _try_auto_start_match() -> void:
	var session = _get_network_session()
	if session == null:
		return
	if not bool(session.call("is_host")):
		return
	if bool(session.call("is_match_started")):
		return
	if session.call("get_connected_peer_ids").size() <= 0:
		return
	_on_start_button_pressed()

func _parse_automation_args(args: PackedStringArray) -> Dictionary:
	var out := {}
	var i := 0
	while i < args.size():
		var key := String(args[i])
		match key:
			ARG_ROLE, ARG_HOST, ARG_PORT, ARG_AUTO_START:
				if i + 1 >= args.size():
					break
				var value := String(args[i + 1])
				match key:
					ARG_ROLE:
						out["role"] = value.to_lower()
					ARG_HOST:
						out["host"] = value
					ARG_PORT:
						out["port"] = int(value)
					ARG_AUTO_START:
						out["auto_start"] = value == "1" or value.to_lower() == "true"
				i += 2
			_:
				i += 1
	if not out.has("role"):
		return {}
	if not out.has("host"):
		out["host"] = "127.0.0.1"
	if not out.has("port") or int(out["port"]) <= 0:
		out["port"] = DEFAULT_PORT_FALLBACK
	if not out.has("auto_start"):
		out["auto_start"] = false
	return out

func _is_verifier_run() -> bool:
	return OS.get_cmdline_user_args().has(ARG_VERIFY_SCENARIO)
