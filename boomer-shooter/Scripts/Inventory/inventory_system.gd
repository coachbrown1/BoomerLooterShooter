extends Node
class_name InventorySystem

const EQUIPMENT_SLOT_NAMES: Array[StringName] = [
	&"helmet",
	&"chest",
	&"arms",
	&"legs",
	&"feet"
]
const WEAPON_SLOT_COUNT: int = 4
const STORAGE_SLOT_COUNT: int = 10
const DEFAULT_CHEST_SLOT_COUNT: int = 16
const STARTER_GEAR_IDS: Array[StringName] = [
	&"helmet_scout_visor_common",
	&"chest_bruiser_plate_common",
	&"arms_loader_bracers_common",
	&"legs_raider_greaves_common",
	&"feet_strider_boots_common"
]

signal inventory_changed(snapshot: Dictionary)
signal weapon_slots_changed(weapon_items: Array)
signal inventory_opened_changed(is_open: bool)
signal equipment_stats_changed(stats: Dictionary)

var equipment: Dictionary = {}
var weapons: Array = []
var storage: Array = []
var chest_storage: Array = []
var is_open: bool = false
var _active_chest: InteractableChest = null

var _weapon_manager: WeaponManager
@export var gear_catalog: GearCatalogData = preload("res://Data/gear/gear_catalog.tres")

func _ready() -> void:
	_init_slots()
	_emit_inventory_changed()
	_emit_weapon_slots_changed()
	_emit_equipment_stats_changed()

func _init_slots() -> void:
	equipment.clear()
	for slot_name in EQUIPMENT_SLOT_NAMES:
		equipment[slot_name] = null

	weapons.resize(WEAPON_SLOT_COUNT)
	for i in range(WEAPON_SLOT_COUNT):
		weapons[i] = null

	storage.resize(STORAGE_SLOT_COUNT)
	for i in range(STORAGE_SLOT_COUNT):
		storage[i] = null

func initialize_with_weapon_manager(manager: WeaponManager) -> void:
	_weapon_manager = manager
	if _weapon_manager == null:
		return

	var live_weapons: Array = _weapon_manager.get_weapons()
	for i in range(min(live_weapons.size(), WEAPON_SLOT_COUNT)):
		var weapon: Weapon = live_weapons[i]
		if weapon == null:
			continue
		var item := InventoryItemData.new()
		item.item_id = StringName("weapon_%s" % _normalize_weapon_name(weapon.weapon_name))
		item.display_name = weapon.weapon_name
		item.category = &"weapon"
		item.weapon_key = StringName(_weapon_manager.get_weapon_key_for_weapon(weapon))
		weapons[i] = item

	_seed_starter_gear_if_needed()

	_emit_inventory_changed()
	_emit_weapon_slots_changed()
	_emit_equipment_stats_changed()

func get_slot_snapshot() -> Dictionary:
	var equipment_snapshot := {}
	for slot_name in EQUIPMENT_SLOT_NAMES:
		equipment_snapshot[slot_name] = _item_to_snapshot(equipment.get(slot_name))

	var weapon_snapshot: Array = []
	for item in weapons:
		weapon_snapshot.append(_item_to_snapshot(item))

	var storage_snapshot: Array = []
	for item in storage:
		storage_snapshot.append(_item_to_snapshot(item))
	var chest_snapshot: Array = []
	for item in chest_storage:
		chest_snapshot.append(_item_to_snapshot(item))

	return {
		"equipment": equipment_snapshot,
		"weapons": weapon_snapshot,
		"storage": storage_snapshot,
		"chest": chest_snapshot,
		"is_chest_open": _active_chest != null,
		"chest_name": get_active_chest_name()
	}

func try_move_item(from_slot: SlotRef, to_slot: SlotRef) -> bool:
	if not _is_valid_slot(from_slot) or not _is_valid_slot(to_slot):
		return false
	if from_slot.is_equal(to_slot):
		return false

	var source_item: InventoryItemData = _get_item(from_slot)
	if source_item == null:
		return false
	if not _can_place_item_in_slot(source_item, to_slot):
		return false

	var destination_item: InventoryItemData = _get_item(to_slot)
	if destination_item != null and not _can_place_item_in_slot(destination_item, from_slot):
		return false

	_set_item(to_slot, source_item)
	_set_item(from_slot, destination_item)

	_emit_inventory_changed()
	if from_slot.section == &"weapons" or to_slot.section == &"weapons":
		_emit_weapon_slots_changed()
	if from_slot.section == &"equipment" or to_slot.section == &"equipment":
		_emit_equipment_stats_changed()
	return true

func set_weapon_slot_active(index: int) -> void:
	if index < 0 or index >= WEAPON_SLOT_COUNT:
		return
	if weapons[index] == null:
		return
	if _weapon_manager:
		_weapon_manager.activate_weapon_slot(index)

func set_inventory_open(value: bool) -> void:
	if not value and _active_chest != null:
		_commit_and_clear_active_chest(_should_close_chest_visual_on_inventory_close())
		_emit_inventory_changed()

	if is_open == value:
		return
	is_open = value
	inventory_opened_changed.emit(is_open)

func is_inventory_open() -> bool:
	return is_open

func open_chest(chest: InteractableChest) -> void:
	if chest == null:
		return
	if _active_chest != null and _active_chest != chest:
		_commit_and_clear_active_chest()

	_active_chest = chest
	chest_storage = chest.get_storage_copy()
	if chest_storage.is_empty():
		chest_storage.resize(DEFAULT_CHEST_SLOT_COUNT)
		for i in range(chest_storage.size()):
			chest_storage[i] = null
	set_inventory_open(true)
	_emit_inventory_changed()

func get_equipped_items() -> Array[InventoryItemData]:
	var results: Array[InventoryItemData] = []
	for slot_name in EQUIPMENT_SLOT_NAMES:
		var item: InventoryItemData = equipment.get(slot_name)
		if item == null:
			continue
		results.append(item)
	return results

func get_equipped_stats() -> Dictionary:
	var combined: Dictionary = {}
	for item in get_equipped_items():
		for key_variant in item.stats.keys():
			var key := StringName(key_variant)
			if key == &"rarity":
				continue
			var current_value := float(combined.get(key, 0.0))
			combined[key] = current_value + float(item.stats.get(key_variant, 0.0))
	return combined

func get_active_chest_name() -> String:
	if _active_chest == null:
		return ""
	return _active_chest.chest_name

func get_active_chest_path() -> String:
	if _active_chest == null:
		return ""
	return String(_active_chest.get_path())

func _is_valid_slot(slot_ref: SlotRef) -> bool:
	if slot_ref == null:
		return false
	match slot_ref.section:
		&"equipment":
			return EQUIPMENT_SLOT_NAMES.has(slot_ref.slot_name)
		&"weapons":
			return slot_ref.index >= 0 and slot_ref.index < WEAPON_SLOT_COUNT
		&"storage":
			return slot_ref.index >= 0 and slot_ref.index < STORAGE_SLOT_COUNT
		&"chest":
			return _active_chest != null and slot_ref.index >= 0 and slot_ref.index < chest_storage.size()
		_:
			return false

func _can_place_item_in_slot(item: InventoryItemData, slot_ref: SlotRef) -> bool:
	match slot_ref.section:
		&"equipment":
			return item.category == &"armor" and item.equipment_slot == slot_ref.slot_name
		&"weapons":
			return item.category == &"weapon"
		&"storage":
			return true
		&"chest":
			return true
		_:
			return false

func _get_item(slot_ref: SlotRef) -> InventoryItemData:
	match slot_ref.section:
		&"equipment":
			return equipment.get(slot_ref.slot_name)
		&"weapons":
			return weapons[slot_ref.index]
		&"storage":
			return storage[slot_ref.index]
		&"chest":
			return chest_storage[slot_ref.index]
		_:
			return null

func _set_item(slot_ref: SlotRef, item: InventoryItemData) -> void:
	match slot_ref.section:
		&"equipment":
			equipment[slot_ref.slot_name] = item
		&"weapons":
			weapons[slot_ref.index] = item
		&"storage":
			storage[slot_ref.index] = item
		&"chest":
			chest_storage[slot_ref.index] = item

func _commit_and_clear_active_chest(close_visual: bool = true) -> void:
	if _active_chest == null:
		return
	_active_chest.set_storage_items(chest_storage)
	if close_visual:
		_active_chest.close_chest()
	_active_chest = null
	chest_storage.clear()

func _should_close_chest_visual_on_inventory_close() -> bool:
	var session = get_node_or_null("/root/NetworkSession")
	if session == null:
		return true
	return not bool(session.call("is_multiplayer_active"))

func _emit_inventory_changed() -> void:
	inventory_changed.emit(get_slot_snapshot())

func _emit_weapon_slots_changed() -> void:
	weapon_slots_changed.emit(weapons.duplicate())

func _emit_equipment_stats_changed() -> void:
	equipment_stats_changed.emit(get_equipped_stats())

func _item_to_snapshot(item: InventoryItemData) -> Variant:
	if item == null:
		return null
	return item.to_dict()

func _normalize_weapon_name(raw_name: String) -> String:
	return raw_name.strip_edges().to_lower().replace(" ", "_")

func _seed_starter_gear_if_needed() -> void:
	if gear_catalog == null:
		return
	for slot_name in EQUIPMENT_SLOT_NAMES:
		if equipment.get(slot_name) != null:
			return
	for item in storage:
		if item != null:
			return

	for i in range(min(STORAGE_SLOT_COUNT, STARTER_GEAR_IDS.size())):
		var starter_item := gear_catalog.create_item_by_id(STARTER_GEAR_IDS[i])
		if starter_item == null:
			continue
		storage[i] = starter_item
