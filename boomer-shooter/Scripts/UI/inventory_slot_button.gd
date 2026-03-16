extends Button
class_name InventorySlotButton

signal slot_pressed(slot_ref: SlotRef)
signal slot_double_clicked(slot_ref: SlotRef)
signal slot_drop_requested(from_slot: SlotRef, to_slot: SlotRef)

var slot_ref: SlotRef = null
var has_item: bool = false
var _suppress_next_pressed: bool = false
var _selected: bool = false
var _base_fill_color := Color(0.13, 0.15, 0.18, 0.95)
var _empty_border_color := Color(0.28, 0.31, 0.36, 0.85)
var _rarity_border_color := Color(0.52, 0.55, 0.60, 1.0)
var _selected_fill_color := Color(0.18, 0.16, 0.10, 0.98)
var _selected_border_color := Color(0.93, 0.79, 0.38, 1.0)
var _badge_icon: TextureRect = null

func _ready() -> void:
	pressed.connect(_on_pressed)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_ensure_badge_icon()
	_refresh_styles()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed and mouse_event.double_click:
			_suppress_next_pressed = true
			slot_double_clicked.emit(slot_ref)
			accept_event()

func set_slot_ref(value: SlotRef) -> void:
	slot_ref = value

func set_has_item(value: bool) -> void:
	has_item = value
	_refresh_styles()

func set_rarity_border_color(color: Color) -> void:
	_rarity_border_color = color
	_refresh_styles()

func set_selected(value: bool) -> void:
	_selected = value
	_refresh_styles()

func set_badge_texture(texture: Texture2D) -> void:
	_ensure_badge_icon()
	if _badge_icon == null:
		return
	_badge_icon.texture = texture
	_badge_icon.visible = texture != null

func _on_pressed() -> void:
	if _suppress_next_pressed:
		_suppress_next_pressed = false
		return
	slot_pressed.emit(slot_ref)

func _get_drag_data(_at_position: Vector2) -> Variant:
	if slot_ref == null or not has_item:
		return null

	if icon != null:
		var preview := TextureRect.new()
		preview.texture = icon
		preview.custom_minimum_size = Vector2(64, 64)
		preview.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		set_drag_preview(preview)
	else:
		var preview := Label.new()
		preview.text = text
		preview.add_theme_font_size_override("font_size", 14)
		set_drag_preview(preview)

	return {
		"type": "inventory_slot",
		"from_slot": slot_ref
	}

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if slot_ref == null:
		return false
	if typeof(data) != TYPE_DICTIONARY:
		return false
	if data.get("type", "") != "inventory_slot":
		return false
	var from_slot: SlotRef = data.get("from_slot")
	if from_slot == null:
		return false
	return not from_slot.is_equal(slot_ref)

func _drop_data(_at_position: Vector2, data: Variant) -> void:
	var from_slot: SlotRef = data.get("from_slot")
	if from_slot == null:
		return
	slot_drop_requested.emit(from_slot, slot_ref)

func _refresh_styles() -> void:
	var fill := _selected_fill_color if _selected else _base_fill_color
	var border := _selected_border_color if _selected else _get_current_border_color()
	var normal := _make_stylebox(fill, border, 3 if _selected else 2)
	var hover := _make_stylebox(fill.lightened(0.06), border.lightened(0.12), 3 if _selected else 2)
	var pressed := _make_stylebox(fill.darkened(0.08), border.lightened(0.2), 3 if _selected else 2)
	var focus := _make_stylebox(fill.lightened(0.04), border.lightened(0.25), 4 if _selected else 3)
	add_theme_stylebox_override("normal", normal)
	add_theme_stylebox_override("hover", hover)
	add_theme_stylebox_override("pressed", pressed)
	add_theme_stylebox_override("focus", focus)
	add_theme_stylebox_override("disabled", normal)

func _get_current_border_color() -> Color:
	return _rarity_border_color if has_item else _empty_border_color

func _make_stylebox(fill_color: Color, border_color: Color, border_width: int = 2) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill_color
	style.border_color = border_color
	style.border_width_left = border_width
	style.border_width_top = border_width
	style.border_width_right = border_width
	style.border_width_bottom = border_width
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_right = 6
	style.corner_radius_bottom_left = 6
	style.content_margin_left = 4
	style.content_margin_top = 4
	style.content_margin_right = 4
	style.content_margin_bottom = 4
	return style

func _ensure_badge_icon() -> void:
	if _badge_icon != null:
		return
	_badge_icon = TextureRect.new()
	_badge_icon.name = "BadgeIcon"
	_badge_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_badge_icon.anchor_left = 0.0
	_badge_icon.anchor_top = 0.0
	_badge_icon.anchor_right = 0.0
	_badge_icon.anchor_bottom = 0.0
	_badge_icon.offset_left = 4.0
	_badge_icon.offset_top = 4.0
	_badge_icon.offset_right = 28.0
	_badge_icon.offset_bottom = 28.0
	_badge_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_badge_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_badge_icon.visible = false
	add_child(_badge_icon)
