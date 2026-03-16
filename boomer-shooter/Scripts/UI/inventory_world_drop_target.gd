extends PanelContainer
class_name InventoryWorldDropTarget

signal world_drop_requested(from_slot: SlotRef)

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if typeof(data) != TYPE_DICTIONARY:
		return false
	if data.get("type", "") != "inventory_slot":
		return false
	var from_slot: SlotRef = data.get("from_slot")
	if from_slot == null:
		return false
	return from_slot.section == &"storage" or from_slot.section == &"equipment"

func _drop_data(_at_position: Vector2, data: Variant) -> void:
	var from_slot: SlotRef = data.get("from_slot")
	if from_slot == null:
		return
	world_drop_requested.emit(from_slot)
