extends Button
class_name InventorySlotButton

signal slot_pressed(slot_ref: SlotRef)
signal slot_double_clicked(slot_ref: SlotRef)
signal slot_drop_requested(from_slot: SlotRef, to_slot: SlotRef)

var slot_ref: SlotRef = null
var has_item: bool = false
var _suppress_next_pressed: bool = false

func _ready() -> void:
	pressed.connect(_on_pressed)

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
