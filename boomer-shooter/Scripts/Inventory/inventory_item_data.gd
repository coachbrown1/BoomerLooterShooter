extends Resource
class_name InventoryItemData

@export var item_id: StringName = &""
@export var display_name: String = ""
@export var category: StringName = &"misc" # weapon, armor, misc
@export var equipment_slot: StringName = &"" # helmet, chest, arms, legs, feet
@export var weapon_key: StringName = &""
@export var weapon_scene: PackedScene
@export var item_icon_path: String = ""
@export var item_icon: Texture2D
@export var stats: Dictionary = {}

func to_dict() -> Dictionary:
	return {
		"item_id": String(item_id),
		"display_name": display_name,
		"category": String(category),
		"equipment_slot": String(equipment_slot),
		"weapon_key": String(weapon_key),
		"icon_path": item_icon_path,
		"stats": stats.duplicate(true)
	}
