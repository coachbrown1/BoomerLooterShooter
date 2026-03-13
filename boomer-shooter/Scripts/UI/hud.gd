extends CanvasLayer

@onready var screen_fx = $ScreenFX
@onready var _bottom_margin: MarginContainer = $MarginContainer
@onready var _bottom_row: BoxContainer = $MarginContainer/HBoxContainer
@onready var health_label = $MarginContainer/HBoxContainer/HealthLabel
@onready var ammo_label = $MarginContainer/HBoxContainer/AmmoLabel
const SLOT_BUTTON_SCRIPT = preload("res://Scripts/UI/inventory_slot_button.gd")

const EQUIPMENT_LABELS: Dictionary = {
	&"helmet": "Helmet",
	&"chest": "Chest",
	&"arms": "Arms",
	&"legs": "Legs",
	&"feet": "Feet"
}
const PANEL_DESIRED_SIZE := Vector2(980, 560)
const WEAPON_SLOT_UI_COUNT := 4
const STORAGE_SLOT_UI_COUNT := 10
const CHEST_SLOT_UI_COUNT := 16
const TEAMMATE_REFRESH_INTERVAL := 0.2

var _inventory_system: InventorySystem = null
var _inventory_panel: PanelContainer = null
var _feedback_label: Label = null
var _chest_panel: PanelContainer = null
var _chest_section_label: Label = null
var _chest_grid: GridContainer = null
var _slot_buttons: Dictionary = {}
var _slot_button_refs: Dictionary = {}
var _selected_slot: SlotRef = null
var _latest_snapshot: Dictionary = {}
var _teammate_health_label: Label = null
var _session_role_label: Label = null
var _teammate_refresh_timer: float = 0.0
var _cached_local_player: Node = null
var _cached_teammate: Node = null

func _ready() -> void:
	# Print out a message so the user knows about the debug key
	print("Debug: Press 'G' to toggle Screen Effects (Saturation/Vignette)")
	_ensure_session_role_label()
	_ensure_teammate_health_label()
	_configure_bottom_hud_layout()
	if not get_viewport().size_changed.is_connected(_configure_bottom_hud_layout):
		get_viewport().size_changed.connect(_configure_bottom_hud_layout)
	_build_inventory_ui()
	_update_session_role_label()
	_update_teammate_health_label()
	set_process(true)

func _process(delta: float) -> void:
	_teammate_refresh_timer += delta
	if _teammate_refresh_timer < TEAMMATE_REFRESH_INTERVAL:
		return
	_teammate_refresh_timer = 0.0
	_update_session_role_label()
	_update_local_health_label()
	_update_teammate_health_label()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_G:
		if screen_fx:
			screen_fx.visible = !screen_fx.visible
			print("Screen Effects: ", "ON" if screen_fx.visible else "OFF")

func update_health(health: int) -> void:
	if not is_node_ready():
		await ready
	if health_label:
		health_label.text = "Health: " + str(health)

func update_ammo(ammo: int, max_ammo: int) -> void:
	if not is_node_ready():
		await ready
	if ammo_label:
		ammo_label.text = "Ammo: " + str(ammo) + " / " + str(max_ammo)

func update_ammo_display(current_mag: int, mag_size: int, reserve: int, is_infinite: bool) -> void:
	if not is_node_ready():
		await ready
	if ammo_label:
		if is_infinite:
			ammo_label.text = "Ammo: \u221E / \u221E" # Infinity symbol
		else:
			ammo_label.text = "Ammo: " + str(current_mag) + " / " + str(reserve)
	_configure_bottom_hud_layout()

func _ensure_teammate_health_label() -> void:
	if _teammate_health_label != null:
		return
	if _bottom_row == null:
		return

	_teammate_health_label = Label.new()
	_teammate_health_label.name = "TeammateHealthLabel"
	_teammate_health_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_teammate_health_label.text = "Teammate: --"
	_teammate_health_label.visible = false
	if health_label and health_label.label_settings != null:
		_teammate_health_label.label_settings = health_label.label_settings

	var insert_index := _bottom_row.get_child_count()
	if ammo_label != null:
		insert_index = ammo_label.get_index()
	_bottom_row.add_child(_teammate_health_label)
	_bottom_row.move_child(_teammate_health_label, insert_index)

func _update_teammate_health_label() -> void:
	if _teammate_health_label == null:
		return
	if not _is_multiplayer_active():
		_teammate_health_label.visible = false
		_cached_teammate = null
		return

	var local_player = _find_local_player()
	var teammate = _find_teammate(local_player)
	if teammate == null:
		_teammate_health_label.visible = false
		return

	var teammate_health_variant: Variant = teammate.get("current_health")
	if teammate_health_variant == null:
		_teammate_health_label.text = "Teammate: --"
		_teammate_health_label.visible = true
		return

	var teammate_health: int = maxi(0, int(teammate_health_variant))
	_teammate_health_label.text = "Teammate: %d" % teammate_health
	_teammate_health_label.visible = true

func _update_local_health_label() -> void:
	var local_player = _find_local_player()
	if local_player == null:
		return
	var health_variant: Variant = local_player.get("current_health")
	if health_variant == null:
		return
	update_health(maxi(0, int(health_variant)))

func _find_local_player() -> Node:
	if is_instance_valid(_cached_local_player):
		if _is_player_local(_cached_local_player):
			return _cached_local_player
		_cached_local_player = null

	var local_peer_id := _get_local_peer_id()
	for player_variant in get_tree().get_nodes_in_group("player"):
		if not (player_variant is Node):
			continue
		var player: Node = player_variant
		if player.is_queued_for_deletion():
			continue
		if not _is_player_local(player):
			continue
		if local_peer_id > 0 and player.has_method("get_network_peer_id"):
			if int(player.call("get_network_peer_id")) != local_peer_id:
				continue
		_cached_local_player = player
		return player

	for player_variant in get_tree().get_nodes_in_group("player"):
		if not (player_variant is Node):
			continue
		var player: Node = player_variant
		if player.is_queued_for_deletion():
			continue
		if _is_player_local(player):
			_cached_local_player = player
			return player
	return null

func _find_teammate(local_player: Node) -> Node:
	if is_instance_valid(_cached_teammate):
		if _cached_teammate != local_player:
			return _cached_teammate
		_cached_teammate = null

	for player_variant in get_tree().get_nodes_in_group("player"):
		if not (player_variant is Node):
			continue
		var player: Node = player_variant
		if player.is_queued_for_deletion():
			continue
		if player == local_player:
			continue
		_cached_teammate = player
		return player
	return null

func _is_player_local(player: Node) -> bool:
	if player == null:
		return false
	if not player.has_method("is_local_controlled"):
		return false
	return bool(player.call("is_local_controlled"))

func _get_local_peer_id() -> int:
	var session = _get_network_session()
	if session == null:
		return 1
	return max(1, int(session.call("get_local_peer_id")))

func _ensure_session_role_label() -> void:
	if _session_role_label != null:
		return

	_session_role_label = Label.new()
	_session_role_label.name = "SessionRoleLabel"
	_session_role_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_session_role_label.anchor_left = 0.0
	_session_role_label.anchor_top = 0.0
	_session_role_label.anchor_right = 0.0
	_session_role_label.anchor_bottom = 0.0
	_session_role_label.offset_left = 14.0
	_session_role_label.offset_top = 10.0
	_session_role_label.text = "Net: Single"
	if health_label and health_label.label_settings != null:
		_session_role_label.label_settings = health_label.label_settings
		_session_role_label.add_theme_font_size_override("font_size", 22)
	add_child(_session_role_label)

func _update_session_role_label() -> void:
	if _session_role_label == null:
		return
	var session = _get_network_session()
	if session == null or not bool(session.call("is_multiplayer_active")):
		_session_role_label.text = "Net: Single"
		return
	if bool(session.call("is_host")):
		_session_role_label.text = "Net: Host"
	else:
		_session_role_label.text = "Net: Client"

func _get_network_session():
	return get_node_or_null("/root/NetworkSession")

func _is_multiplayer_active() -> bool:
	var session = _get_network_session()
	if session == null:
		return false
	return bool(session.call("is_multiplayer_active"))

func set_inventory_system(system: InventorySystem) -> void:
	if _inventory_system:
		if _inventory_system.inventory_changed.is_connected(_on_inventory_changed):
			_inventory_system.inventory_changed.disconnect(_on_inventory_changed)
		if _inventory_system.inventory_opened_changed.is_connected(_on_inventory_opened_changed):
			_inventory_system.inventory_opened_changed.disconnect(_on_inventory_opened_changed)

	_inventory_system = system
	if _inventory_system == null:
		return

	if not _inventory_system.inventory_changed.is_connected(_on_inventory_changed):
		_inventory_system.inventory_changed.connect(_on_inventory_changed)
	if not _inventory_system.inventory_opened_changed.is_connected(_on_inventory_opened_changed):
		_inventory_system.inventory_opened_changed.connect(_on_inventory_opened_changed)

	_on_inventory_changed(_inventory_system.get_slot_snapshot())
	_on_inventory_opened_changed(_inventory_system.is_inventory_open())

func _on_inventory_changed(snapshot: Dictionary) -> void:
	_latest_snapshot = snapshot
	_refresh_inventory_ui()

func _on_inventory_opened_changed(is_open: bool) -> void:
	if _inventory_panel == null:
		_build_inventory_ui()
	if _inventory_panel:
		_inventory_panel.visible = is_open
		if is_open:
			_recenter_inventory_panel()
			_inventory_panel.move_to_front()
	if not is_open:
		_selected_slot = null
		_set_feedback("")
		_refresh_inventory_ui()

func set_inventory_panel_visible(is_open: bool) -> void:
	_on_inventory_opened_changed(is_open)

func _build_inventory_ui() -> void:
	_inventory_panel = PanelContainer.new()
	_inventory_panel.name = "InventoryPanel"
	_inventory_panel.visible = false
	_inventory_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_inventory_panel.anchor_left = 0.0
	_inventory_panel.anchor_top = 0.0
	_inventory_panel.anchor_right = 0.0
	_inventory_panel.anchor_bottom = 0.0
	_inventory_panel.custom_minimum_size = Vector2(760, 420)
	_inventory_panel.size = PANEL_DESIRED_SIZE
	add_child(_inventory_panel)
	_recenter_inventory_panel()
	if not get_viewport().size_changed.is_connected(_recenter_inventory_panel):
		get_viewport().size_changed.connect(_recenter_inventory_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	_inventory_panel.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 6)
	margin.add_child(root)

	var title_row := HBoxContainer.new()
	title_row.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(title_row)

	var title := Label.new()
	title.text = "Inventory"
	title.add_theme_font_size_override("font_size", 20)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_row.add_child(title)

	var close_button := Button.new()
	close_button.text = "X"
	close_button.custom_minimum_size = Vector2(36, 28)
	close_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	close_button.tooltip_text = "Close Inventory"
	close_button.pressed.connect(_close_inventory_panel)
	title_row.add_child(close_button)

	_feedback_label = Label.new()
	_feedback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_feedback_label.modulate = Color(1, 0.4, 0.4, 1)
	root.add_child(_feedback_label)

	var content_row := HBoxContainer.new()
	content_row.add_theme_constant_override("separation", 10)
	content_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(content_row)

	var player_panel := PanelContainer.new()
	player_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	player_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	player_panel.add_theme_stylebox_override("panel", _make_tinted_panel_style(Color(0.13, 0.17, 0.22, 0.9)))
	content_row.add_child(player_panel)

	var player_margin := MarginContainer.new()
	player_margin.add_theme_constant_override("margin_left", 10)
	player_margin.add_theme_constant_override("margin_top", 10)
	player_margin.add_theme_constant_override("margin_right", 10)
	player_margin.add_theme_constant_override("margin_bottom", 10)
	player_panel.add_child(player_margin)

	var player_root := VBoxContainer.new()
	player_root.add_theme_constant_override("separation", 6)
	player_margin.add_child(player_root)

	player_root.add_child(_build_section_label("Equipment"))
	var equipment_grid := GridContainer.new()
	equipment_grid.columns = 2
	equipment_grid.add_theme_constant_override("h_separation", 6)
	equipment_grid.add_theme_constant_override("v_separation", 6)
	player_root.add_child(equipment_grid)

	for slot_name in [&"helmet", &"chest", &"arms", &"legs", &"feet"]:
		var slot_ref := SlotRef.equipment(slot_name)
		var button := _make_slot_button(slot_ref)
		equipment_grid.add_child(button)

	player_root.add_child(_build_section_label("Weapons (1-4)"))
	var weapons_grid := GridContainer.new()
	weapons_grid.columns = 4
	weapons_grid.add_theme_constant_override("h_separation", 6)
	weapons_grid.add_theme_constant_override("v_separation", 6)
	player_root.add_child(weapons_grid)
	for i in range(WEAPON_SLOT_UI_COUNT):
		var weapon_ref := SlotRef.weapon(i)
		var weapon_button := _make_slot_button(weapon_ref)
		weapons_grid.add_child(weapon_button)

	player_root.add_child(_build_section_label("Storage (10)"))
	var storage_grid := GridContainer.new()
	storage_grid.columns = 5
	storage_grid.add_theme_constant_override("h_separation", 6)
	storage_grid.add_theme_constant_override("v_separation", 6)
	player_root.add_child(storage_grid)
	for i in range(STORAGE_SLOT_UI_COUNT):
		var storage_ref := SlotRef.storage(i)
		var storage_button := _make_slot_button(storage_ref)
		storage_grid.add_child(storage_button)

	_chest_panel = PanelContainer.new()
	_chest_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_chest_panel.custom_minimum_size = Vector2(300, 0)
	_chest_panel.add_theme_stylebox_override("panel", _make_tinted_panel_style(Color(0.28, 0.20, 0.11, 0.9)))
	content_row.add_child(_chest_panel)

	var chest_margin := MarginContainer.new()
	chest_margin.add_theme_constant_override("margin_left", 10)
	chest_margin.add_theme_constant_override("margin_top", 10)
	chest_margin.add_theme_constant_override("margin_right", 10)
	chest_margin.add_theme_constant_override("margin_bottom", 10)
	_chest_panel.add_child(chest_margin)

	var chest_root := VBoxContainer.new()
	chest_root.add_theme_constant_override("separation", 6)
	chest_margin.add_child(chest_root)

	_chest_section_label = _build_section_label("Chest")
	chest_root.add_child(_chest_section_label)
	_chest_grid = GridContainer.new()
	_chest_grid.columns = 4
	_chest_grid.add_theme_constant_override("h_separation", 6)
	_chest_grid.add_theme_constant_override("v_separation", 6)
	chest_root.add_child(_chest_grid)
	for i in range(CHEST_SLOT_UI_COUNT):
		var chest_ref := SlotRef.chest(i)
		var chest_button := _make_slot_button(chest_ref)
		_chest_grid.add_child(chest_button)
	_chest_panel.visible = false
	_chest_section_label.visible = false
	_chest_grid.visible = false

func _build_section_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 16)
	return label

func _make_slot_button(slot_ref: SlotRef) -> InventorySlotButton:
	var button: InventorySlotButton = SLOT_BUTTON_SCRIPT.new()
	button.custom_minimum_size = Vector2(0, 32)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.text = "..."
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.set_slot_ref(slot_ref)
	if slot_ref.section == &"storage" or slot_ref.section == &"chest":
		button.custom_minimum_size = Vector2(60, 60)
		button.alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.slot_pressed.connect(_on_slot_button_pressed)
	button.slot_double_clicked.connect(_on_slot_button_double_clicked)
	button.slot_drop_requested.connect(_on_slot_drop_requested)
	_slot_buttons[slot_ref.to_key()] = button
	_slot_button_refs[slot_ref.to_key()] = slot_ref
	return button

func _on_slot_button_pressed(slot_ref: SlotRef) -> void:
	if _inventory_system == null:
		return

	var has_item := _get_slot_item_snapshot(slot_ref) != null
	if _selected_slot == null:
		if not has_item:
			_set_feedback("Slot is empty.", true)
			return
		_selected_slot = slot_ref
		_set_feedback("Selected %s." % _slot_label(slot_ref))
		_refresh_inventory_ui()
		return

	if _selected_slot.is_equal(slot_ref):
		_selected_slot = null
		_set_feedback("")
		_refresh_inventory_ui()
		return

	var moved := _inventory_system.try_move_item(_selected_slot, slot_ref)
	if not moved:
		_set_feedback("Invalid move for slot rules.", true)
	else:
		_selected_slot = null
		_set_feedback("")

func _on_slot_button_double_clicked(slot_ref: SlotRef) -> void:
	if _inventory_system == null:
		return
	if slot_ref == null or slot_ref.section != &"chest":
		return
	var item_snapshot = _get_slot_item_snapshot(slot_ref)
	if item_snapshot == null:
		return
	if _try_quick_transfer_to_player_inventory(slot_ref, item_snapshot):
		_selected_slot = null
		_set_feedback("")
	else:
		_set_feedback("No valid inventory slot available.", true)

func _on_slot_drop_requested(from_slot: SlotRef, to_slot: SlotRef) -> void:
	if _inventory_system == null:
		return
	var moved := _inventory_system.try_move_item(from_slot, to_slot)
	if not moved:
		_set_feedback("Invalid move for slot rules.", true)
	else:
		_selected_slot = null
		_set_feedback("")

func _refresh_inventory_ui() -> void:
	_update_chest_section_visibility()

	for key in _slot_buttons.keys():
		var button: InventorySlotButton = _slot_buttons[key]
		var slot_ref: SlotRef = _slot_button_refs.get(key)
		button.text = _slot_button_text(slot_ref)

		var item_snapshot = _get_slot_item_snapshot(slot_ref)
		button.set_has_item(item_snapshot != null)
		if item_snapshot != null:
			button.tooltip_text = String(item_snapshot.get("display_name", "Item"))
		else:
			button.tooltip_text = "Empty slot"

		button.modulate = Color(1, 0.95, 0.55, 1) if _selected_slot != null and _selected_slot.is_equal(slot_ref) else Color(1, 1, 1, 1)

func _slot_button_text(slot_ref: SlotRef) -> String:
	var item_snapshot = _get_slot_item_snapshot(slot_ref)
	var item_text := "[Empty]"
	if item_snapshot != null:
		item_text = String(item_snapshot.get("display_name", "Item"))
	if slot_ref.section == &"storage" or slot_ref.section == &"chest":
		if item_snapshot == null:
			return "%s\n-" % _slot_label(slot_ref)
		return "%s\n%s" % [_slot_label(slot_ref), item_text]
	return "%s: %s" % [_slot_label(slot_ref), item_text]

func _slot_label(slot_ref: SlotRef) -> String:
	match slot_ref.section:
		&"equipment":
			return EQUIPMENT_LABELS.get(slot_ref.slot_name, String(slot_ref.slot_name))
		&"weapons":
			return "Weapon %d" % (slot_ref.index + 1)
		&"storage":
			return str(slot_ref.index + 1)
		&"chest":
			return "C%d" % (slot_ref.index + 1)
		_:
			return "Unknown"

func _get_slot_item_snapshot(slot_ref: SlotRef) -> Variant:
	if _latest_snapshot.is_empty():
		return null
	match slot_ref.section:
		&"equipment":
			var equipment_snapshot: Dictionary = _latest_snapshot.get("equipment", {})
			return equipment_snapshot.get(slot_ref.slot_name)
		&"weapons":
			var weapon_snapshot: Array = _latest_snapshot.get("weapons", [])
			if slot_ref.index < 0 or slot_ref.index >= weapon_snapshot.size():
				return null
			return weapon_snapshot[slot_ref.index]
		&"storage":
			var storage_snapshot: Array = _latest_snapshot.get("storage", [])
			if slot_ref.index < 0 or slot_ref.index >= storage_snapshot.size():
				return null
			return storage_snapshot[slot_ref.index]
		&"chest":
			var chest_snapshot: Array = _latest_snapshot.get("chest", [])
			if slot_ref.index < 0 or slot_ref.index >= chest_snapshot.size():
				return null
			return chest_snapshot[slot_ref.index]
		_:
			return null

func _set_feedback(text: String, is_error: bool = false) -> void:
	if _feedback_label:
		_feedback_label.text = text
		if text == "":
			return
		_feedback_label.modulate = Color(1, 0.4, 0.4, 1) if is_error else Color(0.8, 0.9, 1.0, 1)

func _recenter_inventory_panel() -> void:
	if _inventory_panel == null:
		return
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var panel_width := minf(PANEL_DESIRED_SIZE.x, maxf(320.0, viewport_size.x - 32.0))
	var panel_height := minf(PANEL_DESIRED_SIZE.y, maxf(280.0, viewport_size.y - 32.0))
	_inventory_panel.size = Vector2(panel_width, panel_height)
	var panel_size: Vector2 = _inventory_panel.size
	_inventory_panel.position = Vector2(
		maxf((viewport_size.x - panel_size.x) * 0.5, 0.0),
		maxf((viewport_size.y - panel_size.y) * 0.5, 0.0)
	)

func _update_chest_section_visibility() -> void:
	if _chest_panel == null or _chest_section_label == null or _chest_grid == null:
		return
	var chest_open := bool(_latest_snapshot.get("is_chest_open", false))
	_chest_panel.visible = chest_open
	_chest_section_label.visible = chest_open
	_chest_grid.visible = chest_open
	if chest_open:
		var chest_name := String(_latest_snapshot.get("chest_name", "Chest"))
		_chest_section_label.text = "Chest: %s" % chest_name

func _close_inventory_panel() -> void:
	if _inventory_system == null:
		return
	_inventory_system.set_inventory_open(false)
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _try_quick_transfer_to_player_inventory(from_slot: SlotRef, item_snapshot: Dictionary) -> bool:
	var category := StringName(item_snapshot.get("category", "misc"))
	var destinations: Array[SlotRef] = []

	if category == &"armor":
		var equipment_slot := StringName(item_snapshot.get("equipment_slot", ""))
		if equipment_slot != StringName(""):
			destinations.append(SlotRef.equipment(equipment_slot))
	elif category == &"weapon":
		for i in range(WEAPON_SLOT_UI_COUNT):
			destinations.append(SlotRef.weapon(i))

	for i in range(STORAGE_SLOT_UI_COUNT):
		destinations.append(SlotRef.storage(i))

	for slot_ref in destinations:
		if _get_slot_item_snapshot(slot_ref) != null:
			continue
		if _inventory_system.try_move_item(from_slot, slot_ref):
			return true
	return false

func _make_tinted_panel_style(tint: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = tint
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_right = 6
	style.corner_radius_bottom_left = 6
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = tint.lerp(Color.WHITE, 0.35)
	return style

func _configure_bottom_hud_layout() -> void:
	if _bottom_margin == null or _bottom_row == null:
		return
	# Keep bottom HUD text anchored inside frame at any viewport size/font scale.
	var content_height := _bottom_row.get_combined_minimum_size().y
	var bar_height := maxi(int(ceil(content_height)) + 24, 88)
	_bottom_margin.anchor_left = 0.0
	_bottom_margin.anchor_top = 1.0
	_bottom_margin.anchor_right = 1.0
	_bottom_margin.anchor_bottom = 1.0
	_bottom_margin.offset_left = 0.0
	_bottom_margin.offset_right = 0.0
	_bottom_margin.offset_bottom = -42.0
	_bottom_margin.offset_top = _bottom_margin.offset_bottom - float(bar_height)
