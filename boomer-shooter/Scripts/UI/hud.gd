extends CanvasLayer

@onready var screen_fx = $ScreenFX
@onready var health_label = $MarginContainer/HBoxContainer/HealthLabel
@onready var ammo_label = $MarginContainer/HBoxContainer/AmmoLabel

const EQUIPMENT_LABELS: Dictionary = {
	&"helmet": "Helmet",
	&"chest": "Chest",
	&"arms": "Arms",
	&"legs": "Legs",
	&"feet": "Feet"
}
const PANEL_DESIRED_SIZE := Vector2(700, 430)

var _inventory_system: InventorySystem = null
var _inventory_panel: PanelContainer = null
var _feedback_label: Label = null
var _slot_buttons: Dictionary = {}
var _slot_button_refs: Dictionary = {}
var _selected_slot: SlotRef = null
var _latest_snapshot: Dictionary = {}

func _ready() -> void:
	# Print out a message so the user knows about the debug key
	print("Debug: Press 'G' to toggle Screen Effects (Saturation/Vignette)")
	_build_inventory_ui()

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
	if _inventory_panel:
		_inventory_panel.visible = is_open
	if not is_open:
		_selected_slot = null
		_set_feedback("")
		_refresh_inventory_ui()

func _build_inventory_ui() -> void:
	_inventory_panel = PanelContainer.new()
	_inventory_panel.name = "InventoryPanel"
	_inventory_panel.visible = false
	_inventory_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_inventory_panel.anchor_left = 0.0
	_inventory_panel.anchor_top = 0.0
	_inventory_panel.anchor_right = 0.0
	_inventory_panel.anchor_bottom = 0.0
	_inventory_panel.custom_minimum_size = Vector2(320, 280)
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

	var title := Label.new()
	title.text = "Inventory"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	root.add_child(title)

	_feedback_label = Label.new()
	_feedback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_feedback_label.modulate = Color(1, 0.4, 0.4, 1)
	root.add_child(_feedback_label)

	root.add_child(_build_section_label("Equipment"))
	var equipment_grid := GridContainer.new()
	equipment_grid.columns = 2
	equipment_grid.add_theme_constant_override("h_separation", 6)
	equipment_grid.add_theme_constant_override("v_separation", 6)
	root.add_child(equipment_grid)

	for slot_name in [&"helmet", &"chest", &"arms", &"legs", &"feet"]:
		var slot_ref := SlotRef.equipment(slot_name)
		var button := _make_slot_button(slot_ref)
		equipment_grid.add_child(button)

	root.add_child(_build_section_label("Weapons (1-4)"))
	var weapons_grid := GridContainer.new()
	weapons_grid.columns = 4
	weapons_grid.add_theme_constant_override("h_separation", 6)
	weapons_grid.add_theme_constant_override("v_separation", 6)
	root.add_child(weapons_grid)
	for i in range(4):
		var weapon_ref := SlotRef.weapon(i)
		var weapon_button := _make_slot_button(weapon_ref)
		weapons_grid.add_child(weapon_button)

	root.add_child(_build_section_label("Storage (10)"))
	var storage_grid := GridContainer.new()
	storage_grid.columns = 5
	storage_grid.add_theme_constant_override("h_separation", 6)
	storage_grid.add_theme_constant_override("v_separation", 6)
	root.add_child(storage_grid)
	for i in range(10):
		var storage_ref := SlotRef.storage(i)
		var storage_button := _make_slot_button(storage_ref)
		storage_grid.add_child(storage_button)

func _build_section_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 16)
	return label

func _make_slot_button(slot_ref: SlotRef) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(0, 32)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.text = "..."
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	if slot_ref.section == &"storage":
		button.custom_minimum_size = Vector2(60, 60)
		button.alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.pressed.connect(_on_slot_button_pressed.bind(slot_ref))
	_slot_buttons[slot_ref.to_key()] = button
	_slot_button_refs[slot_ref.to_key()] = slot_ref
	return button

func _on_slot_button_pressed(slot_ref: SlotRef) -> void:
	if _inventory_system == null:
		return

	var has_item := _get_slot_item_snapshot(slot_ref) != null
	if _selected_slot == null:
		if not has_item:
			_set_feedback("Slot is empty.")
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
		_set_feedback("Invalid move for slot rules.")
	else:
		_selected_slot = null
		_set_feedback("")

func _refresh_inventory_ui() -> void:
	for key in _slot_buttons.keys():
		var button: Button = _slot_buttons[key]
		var slot_ref: SlotRef = _slot_button_refs.get(key)
		button.text = _slot_button_text(slot_ref)

		var item_snapshot = _get_slot_item_snapshot(slot_ref)
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
	if slot_ref.section == &"storage":
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
		_:
			return null

func _set_feedback(text: String) -> void:
	if _feedback_label:
		_feedback_label.text = text

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
