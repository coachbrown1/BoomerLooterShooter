extends Resource
class_name InventoryItemData

@export var item_id: StringName = &""
@export var display_name: String = ""
@export var category: StringName = &"misc" # weapon, armor, misc
@export var equipment_slot: StringName = &"" # helmet, chest, arms, legs, feet
@export var weapon_key: StringName = &""
@export var weapon_scene: PackedScene
@export var stats: Dictionary = {}

func to_dict() -> Dictionary:
	return {
		"item_id": String(item_id),
		"display_name": display_name,
		"category": String(category),
		"equipment_slot": String(equipment_slot),
		"weapon_key": String(weapon_key),
		"stats": stats.duplicate(true)
	}
