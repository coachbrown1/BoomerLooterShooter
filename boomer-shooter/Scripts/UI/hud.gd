extends CanvasLayer

@onready var screen_fx = $ScreenFX
@onready var _bottom_margin: MarginContainer = $MarginContainer
@onready var _bottom_row: BoxContainer = $MarginContainer/HBoxContainer
@onready var _health_row: HBoxContainer = $MarginContainer/HBoxContainer/HealthRow
@onready var _ammo_row: HBoxContainer = $MarginContainer/HBoxContainer/AmmoRow
@onready var health_label: Label = $MarginContainer/HBoxContainer/HealthRow/HealthLabel
@onready var ammo_label: Label = $MarginContainer/HBoxContainer/AmmoRow/AmmoLabel
@onready var _health_icon: TextureRect = $MarginContainer/HBoxContainer/HealthRow/HealthIcon
@onready var _ammo_icon: TextureRect = $MarginContainer/HBoxContainer/AmmoRow/AmmoIcon
const SLOT_BUTTON_SCRIPT = preload("res://Scripts/UI/inventory_slot_button.gd")
const WORLD_DROP_TARGET_SCRIPT = preload("res://Scripts/UI/inventory_world_drop_target.gd")
const HUD_HEART_ICON := "res://Assets/Icons/UI/hud_heart_icon.png"
const HUD_FRAME_KIT_PATH := "res://Assets/UI/Generated/hud_frame_kit.png"
const HUD_PROMPT_ICON_PATH := "res://Assets/UI/Generated/fantasy_ui_icon_set.png"
const HUD_BADGE_ICON_PATH := "res://Assets/UI/Generated/inventory_micro_badges.png"
const AMMO_ICON_PATHS: Dictionary = {
	"light": "res://Assets/Pickups/pickup_rifle_ammo.png",
	"shells": "res://Assets/Pickups/pickup_shells_ammo.png",
	"energy": "res://Assets/Pickups/pickup_energy_ammo.png",
	"arrows": "res://Assets/Icons/Weapons/icon_crossbow.png",
}
const HUD_FRAME_REGIONS := {
	"module": Rect2(103, 15, 146, 81),
	"long_bar": Rect2(10, 217, 198, 28),
	"title_bar": Rect2(10, 253, 198, 29),
}
const HUD_PROMPT_ICON_REGIONS := {
	"interact": Rect2(32, 32, 106, 118),
	"chest": Rect2(185, 39, 130, 107),
	"shared_chest": Rect2(342, 50, 145, 85),
	"door": Rect2(35, 179, 100, 139),
	"loot": Rect2(200, 189, 101, 123),
	"health": Rect2(367, 189, 98, 122),
	"ammo": Rect2(21, 348, 130, 131),
}
const HUD_BADGE_REGIONS := {
	"armor": Rect2(21, 209, 79, 82),
	"weapon": Rect2(115, 209, 81, 82),
	"ammo": Rect2(231, 209, 38, 82),
	"health": Rect2(304, 214, 81, 72),
	"chest": Rect2(400, 214, 79, 73),
}
const LOW_HEALTH_RATIO := 0.25
const LOW_AMMO_RATIO := 0.2

const EQUIPMENT_LABELS: Dictionary = {
	&"helmet": "Helmet",
	&"chest": "Chest",
	&"arms": "Arms",
	&"legs": "Legs",
	&"feet": "Feet"
}
const STAT_LABELS: Dictionary = {
	"health_add": "Health",
	"health_mult": "Health %",
	"move_speed_add": "Move Speed",
	"move_speed_mult": "Move Speed %",
	"sprint_multiplier": "Sprint Speed",
	"damage_reduction": "Damage Reduction",
	"weapon_damage_add": "Weapon Damage",
	"weapon_damage_mult": "Weapon Damage %",
	"mag_size_add": "Magazine Size",
	"mag_size_mult": "Magazine Size %",
	"reload_speed_mult": "Reload Speed %",
	"recoil_recovery_mult": "Recoil Recovery %",
	"spread_reduction": "Spread Reduction",
	"fov_kick_reduction": "FOV Kick Reduction",
	"light_damage_add": "Rifle Damage",
	"light_damage_mult": "Rifle Damage %",
	"light_mag_size_add": "Rifle Mag Size",
	"light_mag_size_mult": "Rifle Mag Size %",
	"shells_damage_add": "Shotgun Family Damage",
	"shells_damage_mult": "Shotgun Family Damage %",
	"shells_mag_size_add": "Shotgun Family Mag Size",
	"shells_mag_size_mult": "Shotgun Family Mag Size %",
	"arrows_damage_add": "Crossbow Family Damage",
	"arrows_damage_mult": "Crossbow Family Damage %",
	"arrows_mag_size_add": "Crossbow Family Mag Size",
	"arrows_mag_size_mult": "Crossbow Family Mag Size %",
	"energy_damage_add": "Energy Family Damage",
	"energy_damage_mult": "Energy Family Damage %",
	"energy_mag_size_add": "Energy Family Mag Size",
	"energy_mag_size_mult": "Energy Family Mag Size %",
	"rifle_damage_add": "Rifle Damage",
	"rifle_damage_mult": "Rifle Damage %",
	"rifle_mag_size_add": "Rifle Mag Size",
	"rifle_mag_size_mult": "Rifle Mag Size %",
	"shotgun_damage_add": "Shotgun Damage",
	"shotgun_damage_mult": "Shotgun Damage %",
	"shotgun_mag_size_add": "Shotgun Mag Size",
	"shotgun_mag_size_mult": "Shotgun Mag Size %",
	"crossbow_damage_add": "Crossbow Damage",
	"crossbow_damage_mult": "Crossbow Damage %",
	"crossbow_mag_size_add": "Crossbow Mag Size",
	"crossbow_mag_size_mult": "Crossbow Mag Size %",
	"fireball_damage_add": "Fireball Damage",
	"fireball_damage_mult": "Fireball Damage %",
	"fireball_mag_size_add": "Fireball Mag Size",
	"fireball_mag_size_mult": "Fireball Mag Size %"
}
const RARITY_BORDER_COLORS: Dictionary = {
	"Common": Color("8b919d"),
	"Uncommon": Color("49b36a"),
	"Rare": Color("4d7dff"),
	"Epic": Color("b05cff"),
	"Legendary": Color("ff9f2f")
}
const WEAPON_ICON_PATH := "res://Assets/Icons/Weapons/icon_%s.png"
const PANEL_DESIRED_SIZE := Vector2(760, 410)
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
var _teammate_module: PanelContainer = null
var _teammate_icon: TextureRect = null
var _session_role_label: Label = null
var _session_role_panel: PanelContainer = null
var _teammate_refresh_timer: float = 0.0
var _cached_local_player: Node = null
var _cached_teammate: Node = null
var _world_item_tooltip: PanelContainer = null
var _world_item_tooltip_title: Label = null
var _world_item_tooltip_detail: Label = null
var _world_item_tooltip_icon: TextureRect = null
var _toast_stack: VBoxContainer = null
var _center_status_panel: PanelContainer = null
var _center_status_label: Label = null
var _center_status_icon: TextureRect = null
var _center_status_tween: Tween = null
var _stat_module_row: BoxContainer = null
var _health_module: PanelContainer = null
var _ammo_module: PanelContainer = null
var _ammo_reserve_label: Label = null
var _ammo_warning_label: Label = null
var _ui_frame_texture: Texture2D = null
var _ui_prompt_icon_texture: Texture2D = null
var _ui_badge_texture: Texture2D = null
var _current_health_value: int = 0
var _current_mag_value: int = 0
var _current_mag_size_value: int = 0
var _current_reserve_value: int = 0
var _current_ammo_type: String = "light"
var _low_ammo_warning: bool = false
var _health_warning_phase: float = 0.0
var _inventory_open_tween: Tween = null
var _chest_section_container: PanelContainer = null
var _world_drop_overlay: Control = null

func _ready() -> void:
	# Print out a message so the user knows about the debug key
	print("Debug: Press 'G' to toggle Screen Effects (Saturation/Vignette)")
	_apply_hud_icons()
	_build_stat_modules()
	_ensure_session_role_label()
	_ensure_teammate_health_label()
	_configure_bottom_hud_layout()
	if not get_viewport().size_changed.is_connected(_configure_bottom_hud_layout):
		get_viewport().size_changed.connect(_configure_bottom_hud_layout)
	_build_inventory_ui()
	_build_world_item_tooltip()
	_build_center_status()
	_build_toast_stack()
	_set_mouse_filter_recursive(_bottom_margin, Control.MOUSE_FILTER_IGNORE)
	_update_teammate_health_label()
	set_process(true)

func _process(delta: float) -> void:
	_teammate_refresh_timer += delta
	_health_warning_phase += delta
	if _teammate_refresh_timer < TEAMMATE_REFRESH_INTERVAL:
		_update_health_warning_visuals(delta)
		return
	_teammate_refresh_timer = 0.0
	_update_local_health_label()
	_update_teammate_health_label()
	_update_health_warning_visuals(delta)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_G:
		if screen_fx:
			screen_fx.visible = !screen_fx.visible
			print("Screen Effects: ", "ON" if screen_fx.visible else "OFF")

func update_health(health: int) -> void:
	if not is_node_ready():
		await ready
	_current_health_value = maxi(0, health)
	if health_label:
		health_label.text = str(_current_health_value)
	_update_health_warning_visuals(0.0)

func update_ammo(ammo: int, max_ammo: int, ammo_type: String = "light") -> void:
	if not is_node_ready():
		await ready
	update_ammo_display(ammo, max_ammo, 0, false, false, ammo_type)

func update_ammo_display(current_mag: int, mag_size: int, reserve: int, is_infinite: bool, has_infinite_reserve: bool = false, ammo_type: String = "light") -> void:
	if not is_node_ready():
		await ready
	_current_mag_value = maxi(0, current_mag)
	_current_mag_size_value = maxi(0, mag_size)
	_current_reserve_value = maxi(0, reserve)
	_current_ammo_type = ammo_type
	_low_ammo_warning = not is_infinite and _current_mag_size_value > 0 and float(_current_mag_value) / float(_current_mag_size_value) <= LOW_AMMO_RATIO
	if ammo_label:
		ammo_label.text = "\u221E" if is_infinite else str(_current_mag_value)
	if _ammo_reserve_label:
		if is_infinite:
			_ammo_reserve_label.text = "\u221E / \u221E"
		elif has_infinite_reserve:
			_ammo_reserve_label.text = "%d mag  |  \u221E reserve" % [_current_mag_size_value]
		else:
			_ammo_reserve_label.text = "%d mag  |  %d reserve" % [_current_mag_size_value, _current_reserve_value]
	if _ammo_warning_label:
		_ammo_warning_label.visible = _low_ammo_warning
	_update_ammo_icon(ammo_type)
	_update_ammo_warning_visuals()
	_configure_bottom_hud_layout()

func _ensure_teammate_health_label() -> void:
	if _teammate_health_label != null:
		return
	if _bottom_row == null:
		return

	_teammate_health_label = Label.new()
	_teammate_health_label.name = "TeammateHealthLabel"
	_teammate_health_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_teammate_health_label.text = "--"
	_teammate_health_label.visible = false
	if health_label and health_label.label_settings != null:
		_teammate_health_label.label_settings = health_label.label_settings

	if _teammate_module == null:
		_teammate_module = _create_module_panel()
		_teammate_module.name = "TeammateModule"
		_teammate_module.visible = false
		var margin := _wrap_panel_with_margin(_teammate_module, 14, 12)
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 10)
		margin.add_child(row)
		_teammate_icon = TextureRect.new()
		_teammate_icon.custom_minimum_size = Vector2(28, 28)
		_teammate_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_teammate_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(_teammate_icon)
		row.add_child(_teammate_health_label)
		if _stat_module_row != null:
			_stat_module_row.add_child(_teammate_module)
	if _teammate_icon != null and _teammate_icon.texture == null:
		_teammate_icon.texture = _load_texture(HUD_HEART_ICON)

func _update_teammate_health_label() -> void:
	if _teammate_health_label == null:
		return
	if not _is_multiplayer_active():
		if _teammate_module != null:
			_teammate_module.visible = false
		_cached_teammate = null
		return

	if _teammate_module != null:
		_teammate_module.visible = true
	var local_player = _find_local_player()
	var teammate = _find_teammate(local_player)
	if teammate == null:
		_teammate_health_label.text = "--"
		return

	var teammate_health_variant: Variant = teammate.get("current_health")
	if teammate_health_variant == null:
		_teammate_health_label.text = "--"
		return

	var teammate_health: int = maxi(0, int(teammate_health_variant))
	_teammate_health_label.text = str(teammate_health)

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
	var player_nodes = get_tree().get_nodes_in_group("player")
	for player_variant in player_nodes:
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

	for player_variant in player_nodes:
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

	var player_nodes = get_tree().get_nodes_in_group("player")
	for player_variant in player_nodes:
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

func _update_session_role_label() -> void:
	return

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
	if _world_drop_overlay != null:
		_world_drop_overlay.visible = is_open
	if _inventory_panel == null:
		return
	if _inventory_open_tween != null and _inventory_open_tween.is_valid():
		_inventory_open_tween.kill()
	if is_open:
		_recenter_inventory_panel()
		_inventory_panel.visible = true
		_inventory_panel.move_to_front()
		_inventory_panel.modulate = Color(1, 1, 1, 0)
		_inventory_panel.scale = Vector2(0.97, 0.97)
		_inventory_open_tween = create_tween()
		_inventory_open_tween.set_parallel(true)
		_inventory_open_tween.tween_property(_inventory_panel, "modulate", Color.WHITE, 0.18)
		_inventory_open_tween.tween_property(_inventory_panel, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	else:
		_inventory_open_tween = create_tween()
		_inventory_open_tween.set_parallel(true)
		_inventory_open_tween.tween_property(_inventory_panel, "modulate", Color(1, 1, 1, 0), 0.12)
		_inventory_open_tween.tween_property(_inventory_panel, "scale", Vector2(0.98, 0.98), 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		_inventory_open_tween.finished.connect(func() -> void:
			if _inventory_panel != null:
				_inventory_panel.visible = false
				_inventory_panel.scale = Vector2.ONE
				_inventory_panel.modulate = Color.WHITE
		)
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
	_inventory_panel.custom_minimum_size = Vector2(620, 320)
	_inventory_panel.size = PANEL_DESIRED_SIZE
	_inventory_panel.pivot_offset = PANEL_DESIRED_SIZE * 0.5
	_inventory_panel.add_theme_stylebox_override("panel", _make_frame_texture_style("module", 18, Vector4(18, 18, 18, 18)))
	add_child(_inventory_panel)
	_recenter_inventory_panel()
	if not get_viewport().size_changed.is_connected(_recenter_inventory_panel):
		get_viewport().size_changed.connect(_recenter_inventory_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	_inventory_panel.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 6)
	margin.add_child(root)

	var title_row := HBoxContainer.new()
	title_row.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(title_row)

	var title := Label.new()
	title.text = "Inventory"
	title.add_theme_font_size_override("font_size", 18)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_row.add_child(title)

	var close_button := Button.new()
	close_button.text = "X"
	close_button.custom_minimum_size = Vector2(32, 24)
	close_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	close_button.tooltip_text = "Close Inventory"
	close_button.pressed.connect(_close_inventory_panel)
	title_row.add_child(close_button)

	_feedback_label = Label.new()
	_feedback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_feedback_label.modulate = Color(1, 0.4, 0.4, 1)
	_feedback_label.add_theme_font_size_override("font_size", 12)
	root.add_child(_feedback_label)

	var content_row := HBoxContainer.new()
	content_row.add_theme_constant_override("separation", 6)
	content_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(content_row)

	var player_panel := PanelContainer.new()
	player_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	player_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	player_panel.add_theme_stylebox_override("panel", _make_tinted_panel_style(Color(0.10, 0.12, 0.16, 0.94)))
	content_row.add_child(player_panel)

	var player_margin := MarginContainer.new()
	player_margin.add_theme_constant_override("margin_left", 6)
	player_margin.add_theme_constant_override("margin_top", 6)
	player_margin.add_theme_constant_override("margin_right", 6)
	player_margin.add_theme_constant_override("margin_bottom", 6)
	player_panel.add_child(player_margin)

	var player_root := HBoxContainer.new()
	player_root.add_theme_constant_override("separation", 6)
	player_margin.add_child(player_root)

	var equipment_column := VBoxContainer.new()
	equipment_column.add_theme_constant_override("separation", 4)
	equipment_column.custom_minimum_size = Vector2(92, 0)
	player_root.add_child(equipment_column)
	equipment_column.add_child(_build_section_label("Gear", "armor"))
	var equipment_grid := GridContainer.new()
	equipment_grid.columns = 1
	equipment_grid.add_theme_constant_override("h_separation", 4)
	equipment_grid.add_theme_constant_override("v_separation", 5)
	equipment_column.add_child(equipment_grid)

	for slot_name in [&"helmet", &"chest", &"arms", &"legs", &"feet"]:
		var slot_ref := SlotRef.equipment(slot_name)
		var button := _make_slot_button(slot_ref)
		var slot_stack := VBoxContainer.new()
		slot_stack.add_theme_constant_override("separation", 2)
		var slot_label := Label.new()
		slot_label.text = EQUIPMENT_LABELS.get(slot_name, String(slot_name).capitalize())
		slot_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		slot_label.add_theme_font_size_override("font_size", 11)
		slot_stack.add_child(slot_label)
		slot_stack.add_child(button)
		equipment_grid.add_child(slot_stack)

	var weapons_column := VBoxContainer.new()
	weapons_column.add_theme_constant_override("separation", 4)
	weapons_column.custom_minimum_size = Vector2(92, 0)
	player_root.add_child(weapons_column)
	weapons_column.add_child(_build_section_label("Weapons", "weapon"))
	var weapons_grid := GridContainer.new()
	weapons_grid.columns = 1
	weapons_grid.add_theme_constant_override("h_separation", 4)
	weapons_grid.add_theme_constant_override("v_separation", 4)
	weapons_column.add_child(weapons_grid)
	for i in range(WEAPON_SLOT_UI_COUNT):
		var weapon_ref := SlotRef.weapon(i)
		var weapon_button := _make_slot_button(weapon_ref)
		weapons_grid.add_child(weapon_button)

	var storage_column := VBoxContainer.new()
	storage_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	storage_column.add_theme_constant_override("separation", 4)
	player_root.add_child(storage_column)
	storage_column.add_child(_build_section_label("Storage", "ammo"))
	var storage_grid := GridContainer.new()
	storage_grid.columns = 5
	storage_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	storage_grid.add_theme_constant_override("h_separation", 4)
	storage_grid.add_theme_constant_override("v_separation", 4)
	storage_column.add_child(storage_grid)
	for i in range(STORAGE_SLOT_UI_COUNT):
		var storage_ref := SlotRef.storage(i)
		var storage_button := _make_slot_button(storage_ref)
		storage_grid.add_child(storage_button)

	_chest_panel = PanelContainer.new()
	_chest_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_chest_panel.custom_minimum_size = Vector2(236, 0)
	_chest_panel.add_theme_stylebox_override("panel", _make_tinted_panel_style(Color(0.20, 0.14, 0.09, 0.95)))
	content_row.add_child(_chest_panel)

	var chest_margin := MarginContainer.new()
	chest_margin.add_theme_constant_override("margin_left", 6)
	chest_margin.add_theme_constant_override("margin_top", 6)
	chest_margin.add_theme_constant_override("margin_right", 6)
	chest_margin.add_theme_constant_override("margin_bottom", 6)
	_chest_panel.add_child(chest_margin)

	var chest_root := VBoxContainer.new()
	chest_root.add_theme_constant_override("separation", 4)
	chest_margin.add_child(chest_root)

	_chest_section_container = _build_section_label("Shared Chest", "chest")
	_chest_section_label = _chest_section_container.get_meta("title_label") as Label
	chest_root.add_child(_chest_section_container)
	_chest_grid = GridContainer.new()
	_chest_grid.columns = 4
	_chest_grid.add_theme_constant_override("h_separation", 4)
	_chest_grid.add_theme_constant_override("v_separation", 4)
	chest_root.add_child(_chest_grid)
	for i in range(CHEST_SLOT_UI_COUNT):
		var chest_ref := SlotRef.chest(i)
		var chest_button := _make_slot_button(chest_ref)
		_chest_grid.add_child(chest_button)
	_chest_panel.visible = false
	_chest_section_container.visible = false
	_chest_grid.visible = false

	_world_drop_overlay = WORLD_DROP_TARGET_SCRIPT.new()
	_world_drop_overlay.name = "WorldDropOverlay"
	_world_drop_overlay.visible = false
	_world_drop_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_world_drop_overlay.anchor_right = 1.0
	_world_drop_overlay.anchor_bottom = 1.0
	_world_drop_overlay.world_drop_requested.connect(_on_world_drop_requested)
	add_child(_world_drop_overlay)
	move_child(_world_drop_overlay, get_child_count() - 2)

func _build_section_label(text: String, badge_key: String = "") -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _make_frame_texture_style("title_bar", 14, Vector4(14, 8, 14, 8)))
	var margin := _wrap_panel_with_margin(panel, 12, 6)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	margin.add_child(row)
	if not badge_key.is_empty():
		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(16, 16)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture = _make_badge_texture(badge_key)
		row.add_child(icon)
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 14)
	row.add_child(label)
	panel.set_meta("title_label", label)
	return panel

func _make_slot_button(slot_ref: SlotRef) -> InventorySlotButton:
	var button: InventorySlotButton = SLOT_BUTTON_SCRIPT.new()
	button.custom_minimum_size = Vector2(0, 32)
	button.text = ""
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.set_slot_ref(slot_ref)
	if slot_ref.section == &"storage" or slot_ref.section == &"chest":
		button.custom_minimum_size = Vector2(46, 46)
		button.alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.expand_icon = true
	elif slot_ref.section == &"weapons":
		button.custom_minimum_size = Vector2(64, 64)
		button.alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.expand_icon = true
	else:
		button.custom_minimum_size = Vector2(54, 54)
		button.alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.expand_icon = true
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
	if slot_ref == null:
		return
	var item_snapshot = _get_slot_item_snapshot(slot_ref)
	if item_snapshot == null:
		return
	if _try_auto_equip_item(slot_ref, item_snapshot):
		_selected_slot = null
		_set_feedback("")
		return
	if slot_ref.section != &"chest":
		_set_feedback("No compatible equipment slot.", true)
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

func _on_world_drop_requested(from_slot: SlotRef) -> void:
	if _inventory_system == null:
		return
	if from_slot == null or (from_slot.section != &"storage" and from_slot.section != &"equipment"):
		_set_feedback("Only storage and equipped gear can be dropped into the world.", true)
		return
	var dropped: bool = _inventory_system.request_drop_item(from_slot)
	if not dropped:
		_set_feedback("Could not drop that item into the world.", true)
		return
	_selected_slot = null
	_set_feedback("")

func _refresh_inventory_ui() -> void:
	_update_chest_section_visibility()

	for key in _slot_buttons.keys():
		var button: InventorySlotButton = _slot_buttons[key]
		var slot_ref: SlotRef = _slot_button_refs.get(key)
		var item_snapshot = _get_slot_item_snapshot(slot_ref)
		var icon_tex := _get_item_icon(item_snapshot, slot_ref)
		button.icon = icon_tex
		button.set_badge_texture(null)
		if icon_tex != null:
			button.text = ""
		else:
			button.text = _slot_button_text(slot_ref)

		button.set_has_item(item_snapshot != null)
		button.set_rarity_border_color(_get_rarity_border_color(item_snapshot))
		if item_snapshot != null:
			button.tooltip_text = _build_item_tooltip(item_snapshot, slot_ref)
		else:
			button.tooltip_text = _slot_label(slot_ref)
		button.set_selected(_selected_slot != null and _selected_slot.is_equal(slot_ref))

func _get_item_icon(item_snapshot: Variant, slot_ref: SlotRef) -> Texture2D:
	if item_snapshot == null:
		return null
	var explicit_icon_path := String(item_snapshot.get("icon_path", ""))
	if not explicit_icon_path.is_empty() and ResourceLoader.exists(explicit_icon_path):
		return load(explicit_icon_path)
	if slot_ref != null and slot_ref.section != &"weapons":
		return null
	var weapon_key := String(item_snapshot.get("weapon_key", ""))
	if weapon_key.is_empty():
		return null
	var path := WEAPON_ICON_PATH % weapon_key
	if not ResourceLoader.exists(path):
		return null
	return load(path)

func _slot_button_text(slot_ref: SlotRef) -> String:
	var item_snapshot = _get_slot_item_snapshot(slot_ref)
	if item_snapshot != null:
		return ""
	if slot_ref.section == &"equipment":
		return ""
	return ""

func _slot_label(slot_ref: SlotRef) -> String:
	match slot_ref.section:
		&"equipment":
			return EQUIPMENT_LABELS.get(slot_ref.slot_name, String(slot_ref.slot_name))
		&"weapons":
			return "Weapon"
		&"storage":
			return "Storage"
		&"chest":
			return "Chest"
		_:
			return "Unknown"

func _build_world_item_tooltip() -> void:
	_world_item_tooltip = PanelContainer.new()
	_world_item_tooltip.visible = false
	_world_item_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_world_item_tooltip.anchor_left = 0.5
	_world_item_tooltip.anchor_right = 0.5
	_world_item_tooltip.anchor_top = 1.0
	_world_item_tooltip.anchor_bottom = 1.0
	_world_item_tooltip.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_world_item_tooltip.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_world_item_tooltip.offset_left = 0.0
	_world_item_tooltip.offset_right = 0.0
	_world_item_tooltip.offset_top = -168.0
	_world_item_tooltip.offset_bottom = -116.0
	_world_item_tooltip.custom_minimum_size = Vector2(320, 52)
	_world_item_tooltip.add_theme_stylebox_override("panel", _make_frame_texture_style("long_bar", 16, Vector4(18, 10, 18, 10)))
	add_child(_world_item_tooltip)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	_world_item_tooltip.add_child(margin)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	margin.add_child(row)

	_world_item_tooltip_icon = TextureRect.new()
	_world_item_tooltip_icon.custom_minimum_size = Vector2(28, 28)
	_world_item_tooltip_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_world_item_tooltip_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(_world_item_tooltip_icon)

	var text_root := VBoxContainer.new()
	text_root.add_theme_constant_override("separation", 0)
	row.add_child(text_root)

	_world_item_tooltip_title = Label.new()
	_world_item_tooltip_title.add_theme_font_size_override("font_size", 16)
	text_root.add_child(_world_item_tooltip_title)

	_world_item_tooltip_detail = Label.new()
	_world_item_tooltip_detail.add_theme_font_size_override("font_size", 12)
	_world_item_tooltip_detail.modulate = Color(0.86, 0.83, 0.74, 0.95)
	text_root.add_child(_world_item_tooltip_detail)

func show_world_item_tooltip(item_snapshot: Dictionary) -> void:
	if _world_item_tooltip == null or _world_item_tooltip_title == null:
		return
	_world_item_tooltip_title.text = "Take %s" % String(item_snapshot.get("display_name", "Item"))
	_world_item_tooltip_detail.text = _build_pickup_prompt_detail(item_snapshot)
	_world_item_tooltip_icon.texture = _get_prompt_icon_for_snapshot(item_snapshot)
	_world_item_tooltip.visible = true

func hide_world_item_tooltip() -> void:
	if _world_item_tooltip != null:
		_world_item_tooltip.visible = false

func _build_item_tooltip(item_snapshot: Dictionary, slot_ref: SlotRef = null) -> String:
	var lines: Array[String] = []
	lines.append(String(item_snapshot.get("display_name", "Item")))

	var stats: Dictionary = item_snapshot.get("stats", {})
	var rarity := String(item_snapshot.get("rarity", stats.get("rarity", "")))
	if not rarity.is_empty():
		lines.append("Rarity: %s" % rarity)

	var category := String(item_snapshot.get("category", ""))
	if category == "armor":
		var equipment_slot := StringName(item_snapshot.get("equipment_slot", ""))
		if equipment_slot != StringName(""):
			lines.append("Slot: %s" % EQUIPMENT_LABELS.get(equipment_slot, String(equipment_slot).capitalize()))
	elif category == "weapon":
		var weapon_key := String(item_snapshot.get("weapon_key", ""))
		if not weapon_key.is_empty():
			lines.append("Weapon: %s" % weapon_key.capitalize())
	elif category == "ammo":
		var ammo_type := String(item_snapshot.get("ammo_type", ""))
		var ammo_amount := int(item_snapshot.get("ammo_amount", 0))
		if not ammo_type.is_empty():
			lines.append("Ammo Type: %s" % ammo_type.capitalize())
		if ammo_amount > 0:
			lines.append("Amount: +%d" % ammo_amount)
	elif category == "health":
		var health_amount := int(item_snapshot.get("health_amount", 0))
		if health_amount > 0:
			lines.append("Restore: +%d Health" % health_amount)

	var implicit_stats: Dictionary = item_snapshot.get("implicit_stats", {})
	var affixes: Array = item_snapshot.get("affixes", [])
	var implicit_lines := _build_stat_lines(implicit_stats)
	if not implicit_lines.is_empty():
		lines.append("")
		lines.append("Implicit")
		lines.append_array(implicit_lines)

	if not affixes.is_empty():
		lines.append("")
		lines.append("Added Modifiers")
		for affix_variant in affixes:
			if typeof(affix_variant) != TYPE_DICTIONARY:
				continue
			var affix: Dictionary = affix_variant
			var affix_lines := _build_stat_lines(affix.get("stats", {}))
			lines.append_array(affix_lines)

	var total_only_lines := _build_stat_lines(_get_total_only_stats(stats, implicit_stats, affixes))
	if implicit_lines.is_empty() and affixes.is_empty() and not total_only_lines.is_empty():
		lines.append("")
		lines.append_array(total_only_lines)

	var comparison_lines := _build_comparison_lines(item_snapshot, slot_ref)
	if not comparison_lines.is_empty():
		lines.append("")
		lines.append("Compare Equipped")
		lines.append_array(comparison_lines)

	return "\n".join(lines)

func _build_stat_lines(stats: Dictionary) -> Array[String]:
	var ordered_keys := [
		"health_add",
		"health_mult",
		"move_speed_add",
		"move_speed_mult",
		"sprint_multiplier",
		"damage_reduction",
		"weapon_damage_add",
		"weapon_damage_mult",
		"mag_size_add",
		"mag_size_mult",
		"reload_speed_mult",
		"recoil_recovery_mult",
		"spread_reduction",
		"fov_kick_reduction",
		"light_damage_add",
		"light_damage_mult",
		"light_mag_size_add",
		"light_mag_size_mult",
		"shells_damage_add",
		"shells_damage_mult",
		"shells_mag_size_add",
		"shells_mag_size_mult",
		"arrows_damage_add",
		"arrows_damage_mult",
		"arrows_mag_size_add",
		"arrows_mag_size_mult",
		"energy_damage_add",
		"energy_damage_mult",
		"energy_mag_size_add",
		"energy_mag_size_mult",
		"rifle_damage_add",
		"rifle_damage_mult",
		"rifle_mag_size_add",
		"rifle_mag_size_mult",
		"shotgun_damage_add",
		"shotgun_damage_mult",
		"shotgun_mag_size_add",
		"shotgun_mag_size_mult",
		"crossbow_damage_add",
		"crossbow_damage_mult",
		"crossbow_mag_size_add",
		"crossbow_mag_size_mult",
		"fireball_damage_add",
		"fireball_damage_mult",
		"fireball_mag_size_add",
		"fireball_mag_size_mult"
	]
	var lines: Array[String] = []
	for stat_key in ordered_keys:
		if not stats.has(stat_key):
			continue
		lines.append("%s: %s" % [_get_stat_label(stat_key), _format_stat_value(stat_key, float(stats.get(stat_key, 0.0)))])
	return lines

func _get_stat_label(stat_key: String) -> String:
	if STAT_LABELS.has(stat_key):
		return String(STAT_LABELS[stat_key])
	return stat_key.replace("_", " ").capitalize()

func _format_stat_value(stat_key: String, value: float) -> String:
	if stat_key.ends_with("_mult") or stat_key == "spread_reduction" or stat_key == "fov_kick_reduction":
		return "%+.0f%%" % (value * 100.0)
	if stat_key == "sprint_multiplier":
		return "%+.2f" % value
	if is_equal_approx(value, roundf(value)):
		return "%+d" % int(round(value))
	return "%+.2f" % value

func _get_rarity_border_color(item_snapshot: Variant) -> Color:
	if item_snapshot == null:
		return Color("525863")
	var stats: Dictionary = item_snapshot.get("stats", {})
	var rarity := String(stats.get("rarity", ""))
	if RARITY_BORDER_COLORS.has(rarity):
		return RARITY_BORDER_COLORS[rarity]
	var category := String(item_snapshot.get("category", ""))
	if category == "weapon":
		return Color("d7dce5")
	return Color("7f8793")

func _get_total_only_stats(total_stats: Dictionary, implicit_stats: Dictionary, affixes: Array) -> Dictionary:
	if not implicit_stats.is_empty() or not affixes.is_empty():
		return {}
	var display_stats := total_stats.duplicate(true)
	display_stats.erase("rarity")
	return display_stats

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
	_inventory_panel.pivot_offset = _inventory_panel.size * 0.5
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
	if _chest_section_container != null:
		_chest_section_container.visible = chest_open
	_chest_grid.visible = chest_open
	if chest_open:
		var chest_name := String(_latest_snapshot.get("chest_name", "Chest"))
		var prefix := "Shared Chest" if _is_multiplayer_active() else "Chest"
		_chest_section_label.text = "%s: %s" % [prefix, chest_name]

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

func _try_auto_equip_item(from_slot: SlotRef, item_snapshot: Dictionary) -> bool:
	if from_slot == null:
		return false
	if from_slot.section != &"storage" and from_slot.section != &"chest":
		return false
	var category := StringName(item_snapshot.get("category", "misc"))
	if category != &"armor":
		return false
	var equipment_slot := StringName(item_snapshot.get("equipment_slot", ""))
	if equipment_slot == StringName(""):
		return false
	return _inventory_system.try_move_item(from_slot, SlotRef.equipment(equipment_slot))

func _make_tinted_panel_style(tint: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = tint
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_right = 8
	style.corner_radius_bottom_left = 8
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = tint.lerp(Color("d8c08a"), 0.4)
	style.shadow_color = Color(0, 0, 0, 0.35)
	style.shadow_size = 4
	return style

func _configure_bottom_hud_layout() -> void:
	if _bottom_margin == null or _bottom_row == null:
		return
	var content_height := _bottom_row.get_combined_minimum_size().y
	var bar_height := maxi(int(ceil(content_height)) + 28, 100)
	_bottom_margin.anchor_left = 0.0
	_bottom_margin.anchor_top = 1.0
	_bottom_margin.anchor_right = 0.0
	_bottom_margin.anchor_bottom = 1.0
	_bottom_margin.offset_left = 20.0
	_bottom_margin.offset_right = 220.0
	_bottom_margin.offset_bottom = -34.0
	_bottom_margin.offset_top = _bottom_margin.offset_bottom - float(bar_height)

func _apply_hud_icons() -> void:
	_ui_frame_texture = _load_texture(HUD_FRAME_KIT_PATH)
	_ui_prompt_icon_texture = _load_texture(HUD_PROMPT_ICON_PATH)
	_ui_badge_texture = _load_texture(HUD_BADGE_ICON_PATH)
	if _health_icon != null:
		var health_texture := _load_texture(HUD_HEART_ICON)
		if health_texture != null:
			_health_icon.texture = health_texture
	if _ammo_icon != null and _ammo_icon.texture == null:
		_update_ammo_icon("light")

func _update_ammo_icon(ammo_type: String) -> void:
	if _ammo_icon == null:
		return
	var normalized_type := ammo_type.strip_edges().to_lower()
	if normalized_type == "none":
		_ammo_icon.visible = false
		return
	var icon_path := String(AMMO_ICON_PATHS.get(normalized_type, AMMO_ICON_PATHS.get("light", "")))
	var texture := _load_texture(icon_path)
	if texture == null:
		_ammo_icon.visible = false
		return
	_ammo_icon.texture = texture
	_ammo_icon.visible = true

func _load_texture(path: String) -> Texture2D:
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D

func show_interaction_prompt(action_text: String, target_text: String, icon_key: String = "interact", detail_text: String = "") -> void:
	if _world_item_tooltip == null or _world_item_tooltip_title == null:
		return
	_world_item_tooltip_title.text = "%s %s" % [action_text, target_text]
	_world_item_tooltip_detail.text = detail_text
	_world_item_tooltip_icon.texture = _resolve_icon_texture(icon_key)
	_world_item_tooltip.visible = true

func show_center_status(message: String, icon_key: String = "interact", duration: float = 1.0) -> void:
	if _center_status_panel == null or _center_status_label == null:
		return
	if _center_status_tween != null and _center_status_tween.is_valid():
		_center_status_tween.kill()
	_center_status_label.text = message
	if _center_status_icon != null:
		_center_status_icon.texture = _resolve_icon_texture(icon_key)
	_center_status_panel.visible = true
	_center_status_panel.modulate = Color(1, 1, 1, 0)
	_center_status_panel.position = Vector2(0, -8)
	_center_status_tween = create_tween()
	_center_status_tween.set_parallel(true)
	_center_status_tween.tween_property(_center_status_panel, "modulate", Color.WHITE, 0.12)
	_center_status_tween.tween_property(_center_status_panel, "position", Vector2.ZERO, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_center_status_tween.chain().tween_interval(duration)
	_center_status_tween.set_parallel(true)
	_center_status_tween.tween_property(_center_status_panel, "modulate", Color(1, 1, 1, 0), 0.18)
	_center_status_tween.tween_property(_center_status_panel, "position", Vector2(0, -10), 0.18)
	_center_status_tween.finished.connect(func() -> void:
		if _center_status_panel != null:
			_center_status_panel.visible = false
	)

func push_status_toast(message: String, icon_key: String = "interact", duration: float = 2.8) -> void:
	if _toast_stack == null:
		return
	var panel := _create_bar_panel()
	panel.custom_minimum_size = Vector2(260, 42)
	panel.modulate = Color(1, 1, 1, 0)
	var margin := _wrap_panel_with_margin(panel, 14, 8)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	margin.add_child(row)
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(24, 24)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = _resolve_icon_texture(icon_key)
	row.add_child(icon)
	var label := Label.new()
	label.text = message
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	_toast_stack.add_child(panel)
	_set_mouse_filter_recursive(panel, Control.MOUSE_FILTER_IGNORE)
	panel.position.x = 28
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(panel, "modulate", Color.WHITE, 0.14)
	tween.tween_property(panel, "position:x", 0.0, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.chain().tween_interval(duration)
	tween.set_parallel(true)
	tween.tween_property(panel, "modulate", Color(1, 1, 1, 0), 0.18)
	tween.tween_property(panel, "position:x", 18.0, 0.18)
	tween.finished.connect(func() -> void:
		if is_instance_valid(panel):
			panel.queue_free()
	)

func _build_stat_modules() -> void:
	if _stat_module_row != null:
		return
	_bottom_row.alignment = BoxContainer.ALIGNMENT_BEGIN
	_bottom_row.add_theme_constant_override("separation", 8)
	_stat_module_row = VBoxContainer.new()
	_stat_module_row.alignment = BoxContainer.ALIGNMENT_BEGIN
	_stat_module_row.add_theme_constant_override("separation", 10)
	_bottom_row.add_child(_stat_module_row)
	_bottom_row.move_child(_stat_module_row, 0)
	_health_row.get_parent().remove_child(_health_row)
	_ammo_row.get_parent().remove_child(_ammo_row)
	_health_module = _create_module_panel()
	_ammo_module = _create_module_panel()
	_configure_resource_row(_health_row)
	_configure_resource_row(_ammo_row)
	_attach_row_to_module(_health_module, _health_row)
	_attach_row_to_module(_ammo_module, _ammo_row)
	_ammo_reserve_label = Label.new()
	_ammo_reserve_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ammo_reserve_label.add_theme_font_size_override("font_size", 13)
	_ammo_reserve_label.modulate = Color(0.84, 0.82, 0.75, 0.95)
	_ammo_module.get_meta("content_root").add_child(_ammo_reserve_label)
	_ammo_warning_label = Label.new()
	_ammo_warning_label.text = "LOW"
	_ammo_warning_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ammo_warning_label.add_theme_font_size_override("font_size", 12)
	_ammo_warning_label.modulate = Color("f6a84d")
	_ammo_warning_label.visible = false
	_ammo_module.get_meta("content_root").add_child(_ammo_warning_label)
	_stat_module_row.add_child(_health_module)
	_stat_module_row.add_child(_ammo_module)
	_set_mouse_filter_recursive(_stat_module_row, Control.MOUSE_FILTER_IGNORE)
	update_ammo_display(_current_mag_value, _current_mag_size_value, _current_reserve_value, false, false, _current_ammo_type)

func _build_center_status() -> void:
	if _center_status_panel != null:
		return
	_center_status_panel = _create_bar_panel()
	_center_status_panel.visible = false
	_center_status_panel.anchor_left = 0.5
	_center_status_panel.anchor_top = 0.5
	_center_status_panel.anchor_right = 0.5
	_center_status_panel.anchor_bottom = 0.5
	_center_status_panel.offset_left = -120.0
	_center_status_panel.offset_top = 36.0
	_center_status_panel.offset_right = 120.0
	_center_status_panel.offset_bottom = 78.0
	add_child(_center_status_panel)
	var margin := _wrap_panel_with_margin(_center_status_panel, 14, 8)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	margin.add_child(row)
	_center_status_icon = TextureRect.new()
	_center_status_icon.custom_minimum_size = Vector2(22, 22)
	_center_status_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_center_status_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(_center_status_icon)
	_center_status_label = Label.new()
	_center_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(_center_status_label)
	_set_mouse_filter_recursive(_center_status_panel, Control.MOUSE_FILTER_IGNORE)

func _build_toast_stack() -> void:
	if _toast_stack != null:
		return
	_toast_stack = VBoxContainer.new()
	_toast_stack.anchor_left = 1.0
	_toast_stack.anchor_top = 0.0
	_toast_stack.anchor_right = 1.0
	_toast_stack.anchor_bottom = 0.0
	_toast_stack.offset_left = -290.0
	_toast_stack.offset_top = 88.0
	_toast_stack.offset_right = -20.0
	_toast_stack.offset_bottom = 420.0
	_toast_stack.alignment = BoxContainer.ALIGNMENT_BEGIN
	_toast_stack.add_theme_constant_override("separation", 8)
	add_child(_toast_stack)
	_set_mouse_filter_recursive(_toast_stack, Control.MOUSE_FILTER_IGNORE)

func _create_module_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(180, 74)
	panel.add_theme_stylebox_override("panel", _make_frame_texture_style("module", 18, Vector4(16, 10, 16, 10)))
	return panel

func _create_bar_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _make_frame_texture_style("long_bar", 16, Vector4(16, 8, 16, 8)))
	return panel

func _wrap_panel_with_margin(panel: Control, horizontal: int, vertical: int) -> MarginContainer:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", horizontal)
	margin.add_theme_constant_override("margin_right", horizontal)
	margin.add_theme_constant_override("margin_top", vertical)
	margin.add_theme_constant_override("margin_bottom", vertical)
	panel.add_child(margin)
	return margin

func _set_mouse_filter_recursive(control: Control, filter: Control.MouseFilter) -> void:
	if control == null:
		return
	control.mouse_filter = filter
	for child in control.get_children():
		if child is Control:
			_set_mouse_filter_recursive(child, filter)

func _configure_resource_row(row: HBoxContainer) -> void:
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)

func _attach_row_to_module(panel: PanelContainer, row: Control) -> void:
	var margin := _wrap_panel_with_margin(panel, 14, 10)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 2)
	root.alignment = BoxContainer.ALIGNMENT_CENTER
	margin.add_child(root)
	root.add_child(row)
	panel.set_meta("content_root", root)

func _update_health_warning_visuals(_delta: float) -> void:
	var local_player := _find_local_player()
	var max_health_value := maxi(1, int(local_player.get("max_health"))) if local_player != null else 100
	var low_health := float(_current_health_value) / float(max_health_value) <= LOW_HEALTH_RATIO
	if not low_health:
		if health_label != null:
			health_label.modulate = Color.WHITE
		if _health_icon != null:
			_health_icon.modulate = Color.WHITE
		return
	var pulse := 0.8 + (sin(_health_warning_phase * 6.5) * 0.2 + 0.2)
	if health_label != null:
		health_label.modulate = Color(1.0, 0.78 + pulse * 0.1, 0.78 + pulse * 0.05, 1.0)
	if _health_icon != null:
		_health_icon.modulate = Color(1.0, 0.72 + pulse * 0.18, 0.72 + pulse * 0.08, 1.0)

func _update_ammo_warning_visuals() -> void:
	if ammo_label != null:
		ammo_label.modulate = Color("f6d38a") if _low_ammo_warning else Color.WHITE
	if _ammo_reserve_label != null:
		_ammo_reserve_label.modulate = Color("f6a84d") if _low_ammo_warning else Color(0.84, 0.82, 0.75, 0.95)

func _make_frame_texture_style(region_key: String, margin_size: int, content_margins: Vector4) -> StyleBoxTexture:
	var atlas := AtlasTexture.new()
	atlas.atlas = _ui_frame_texture
	atlas.region = HUD_FRAME_REGIONS.get(region_key, HUD_FRAME_REGIONS["module"])
	var style := StyleBoxTexture.new()
	style.texture = atlas
	style.texture_margin_left = margin_size
	style.texture_margin_top = margin_size
	style.texture_margin_right = margin_size
	style.texture_margin_bottom = margin_size
	style.content_margin_left = content_margins.x
	style.content_margin_top = content_margins.y
	style.content_margin_right = content_margins.z
	style.content_margin_bottom = content_margins.w
	style.draw_center = true
	return style

func _make_prompt_icon(icon_key: String) -> Texture2D:
	if _ui_prompt_icon_texture == null:
		return null
	var atlas := AtlasTexture.new()
	atlas.atlas = _ui_prompt_icon_texture
	atlas.region = HUD_PROMPT_ICON_REGIONS.get(icon_key, HUD_PROMPT_ICON_REGIONS["interact"])
	return atlas

func _resolve_icon_texture(icon_key: String) -> Texture2D:
	if AMMO_ICON_PATHS.has(icon_key):
		return _load_texture(String(AMMO_ICON_PATHS[icon_key]))
	return _make_prompt_icon(icon_key)

func _make_badge_texture(badge_key: String) -> Texture2D:
	if _ui_badge_texture == null:
		return null
	var atlas := AtlasTexture.new()
	atlas.atlas = _ui_badge_texture
	atlas.region = HUD_BADGE_REGIONS.get(badge_key, HUD_BADGE_REGIONS["weapon"])
	return atlas

func _get_badge_texture_for_slot(item_snapshot: Variant, slot_ref: SlotRef) -> Texture2D:
	if slot_ref == null:
		return null
	if item_snapshot != null:
		match String(item_snapshot.get("category", "")):
			"armor":
				return _make_badge_texture("armor")
			"weapon":
				return _make_badge_texture("weapon")
			"ammo":
				return _make_badge_texture("ammo")
			"health":
				return _make_badge_texture("health")
	match slot_ref.section:
		&"equipment":
			return _make_badge_texture("armor")
		&"weapons":
			return _make_badge_texture("weapon")
		&"chest":
			return _make_badge_texture("chest")
		_:
			return null

func _build_pickup_prompt_detail(item_snapshot: Dictionary) -> String:
	var category := String(item_snapshot.get("category", ""))
	if category == "health":
		return "+%d health" % int(item_snapshot.get("health_amount", 0))
	if category == "ammo":
		return "+%d %s" % [int(item_snapshot.get("ammo_amount", 0)), String(item_snapshot.get("ammo_type", "ammo"))]
	var rarity := String(item_snapshot.get("rarity", item_snapshot.get("stats", {}).get("rarity", "")))
	return rarity if not rarity.is_empty() else "Loot"

func _get_prompt_icon_for_snapshot(item_snapshot: Dictionary) -> Texture2D:
	var category := String(item_snapshot.get("category", ""))
	match category:
		"health":
			return _make_prompt_icon("health")
		"ammo":
			return _make_prompt_icon("ammo")
		_:
			return _make_prompt_icon("loot")

func _build_comparison_lines(item_snapshot: Dictionary, slot_ref: SlotRef = null) -> Array[String]:
	var lines: Array[String] = []
	if slot_ref == null:
		return lines
	var category := String(item_snapshot.get("category", ""))
	if category != "armor":
		return lines
	if slot_ref.section != &"storage" and slot_ref.section != &"chest":
		return lines
	var equipment_slot := StringName(item_snapshot.get("equipment_slot", ""))
	if equipment_slot == StringName(""):
		return lines
	var equipment_snapshot: Dictionary = _latest_snapshot.get("equipment", {})
	var equipped_variant: Variant = equipment_snapshot.get(equipment_slot, null)
	if typeof(equipped_variant) != TYPE_DICTIONARY:
		lines.append("No item equipped")
		return lines
	var equipped_snapshot: Dictionary = equipped_variant
	if equipped_snapshot.is_empty():
		lines.append("No item equipped")
		return lines
	var candidate_stats: Dictionary = item_snapshot.get("stats", {})
	var equipped_stats: Dictionary = equipped_snapshot.get("stats", {})
	for stat_key in candidate_stats.keys():
		if stat_key == "rarity":
			continue
		var delta := float(candidate_stats.get(stat_key, 0.0)) - float(equipped_stats.get(stat_key, 0.0))
		if is_zero_approx(delta):
			continue
		lines.append("%s: %s" % [_get_stat_label(String(stat_key)), _format_stat_value(String(stat_key), delta)])
	return lines
