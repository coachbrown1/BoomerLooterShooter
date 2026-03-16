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
const STARTER_WEAPON_KEY: StringName = &"crossbow"

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

	var starter_weapon := _create_weapon_item(STARTER_WEAPON_KEY, "Common")
	if starter_weapon != null:
		weapons[0] = starter_weapon

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

## Restores inventory state from a snapshot produced by get_slot_snapshot().
func apply_slot_snapshot(snapshot: Dictionary) -> void:
	if snapshot.is_empty():
		return

	var equip_data: Dictionary = snapshot.get("equipment", {})
	for slot_name in EQUIPMENT_SLOT_NAMES:
		var raw: Variant = equip_data.get(String(slot_name), null)
		equipment[slot_name] = InventoryItemData.from_dict(raw) if raw is Dictionary else null

	var weapon_data: Array = snapshot.get("weapons", [])
	weapons.resize(WEAPON_SLOT_COUNT)
	for i in range(WEAPON_SLOT_COUNT):
		var raw: Variant = weapon_data[i] if i < weapon_data.size() else null
		weapons[i] = InventoryItemData.from_dict(raw) if raw is Dictionary else null

	var storage_data: Array = snapshot.get("storage", [])
	storage.resize(STORAGE_SLOT_COUNT)
	for i in range(STORAGE_SLOT_COUNT):
		var raw: Variant = storage_data[i] if i < storage_data.size() else null
		storage[i] = InventoryItemData.from_dict(raw) if raw is Dictionary else null

	_emit_inventory_changed()
	_emit_weapon_slots_changed()
	_emit_equipment_stats_changed()

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
	if not _can_assign_weapon_after_move(source_item, from_slot, to_slot):
		return false
	if destination_item != null and not _can_assign_weapon_after_move(destination_item, to_slot, from_slot):
		return false

	_set_item(to_slot, source_item)
	_set_item(from_slot, destination_item)

	_emit_inventory_changed()
	if from_slot.section == &"weapons" or to_slot.section == &"weapons":
		_emit_weapon_slots_changed()
	if from_slot.section == &"equipment" or to_slot.section == &"equipment":
		_emit_equipment_stats_changed()
	if from_slot.section == &"chest" or to_slot.section == &"chest":
		_sync_active_chest_state()
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
	_push_owner_toast("Opened %s" % chest.chest_name, "shared_chest" if _is_multiplayer_active() else "chest")

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

func get_active_chest_payload() -> Array:
	if _active_chest == null:
		return []
	return _active_chest.get_storage_payload()

func refresh_active_chest_from_world() -> void:
	if _active_chest == null:
		return
	chest_storage = _active_chest.get_storage_copy()
	_emit_inventory_changed()
	_push_owner_toast("Shared chest updated", "shared_chest")

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

func _sync_active_chest_state() -> void:
	if _active_chest == null:
		return
	_active_chest.set_storage_items(chest_storage)

	var session = get_node_or_null("/root/NetworkSession")
	if session == null or not bool(session.call("is_multiplayer_active")):
		return

	var dungeon_manager = get_tree().get_first_node_in_group("dungeon_manager")
	if dungeon_manager == null:
		return
	var peer_id := 1
	var owner_node := owner
	if owner_node != null and owner_node.has_method("get_network_peer_id"):
		peer_id = int(owner_node.call("get_network_peer_id"))
	if dungeon_manager.has_method("request_sync_active_chest_contents"):
		dungeon_manager.call("request_sync_active_chest_contents", peer_id, get_active_chest_path(), _active_chest.global_position, _active_chest.get_storage_payload())

func _item_to_snapshot(item: InventoryItemData) -> Variant:
	if item == null:
		return null
	return item.to_dict()

func try_add_to_storage(item: InventoryItemData) -> bool:
	for i in range(STORAGE_SLOT_COUNT):
		if storage[i] == null:
			storage[i] = item
			_emit_inventory_changed()
			return true
	return false

func request_drop_item(slot_ref: SlotRef) -> bool:
	if slot_ref == null:
		return false
	if slot_ref.section != &"storage" and slot_ref.section != &"equipment":
		return false
	if not _is_valid_slot(slot_ref):
		return false
	var item: InventoryItemData = _get_item(slot_ref)
	if item == null:
		return false
	var owner_node := owner
	if not (owner_node is Node3D):
		return false
	var owner_body := owner_node as Node3D
	var drop_origin := owner_body.global_position + Vector3(0.0, 0.8, 0.0)
	var launch_direction := -owner_body.global_transform.basis.z.normalized()
	launch_direction.y = 0.0
	if launch_direction.length_squared() <= 0.0001:
		launch_direction = Vector3.FORWARD
	launch_direction = launch_direction.normalized()
	var world_drop_manager := _get_world_drop_manager()
	if world_drop_manager == null:
		return false
	var peer_id := 1
	if owner_node.has_method("get_network_peer_id"):
		peer_id = int(owner_node.call("get_network_peer_id"))
	var display_name: String = item.display_name
	var slot_payload := _slot_ref_to_payload(slot_ref)
	if _is_multiplayer_active():
		if world_drop_manager.has_method("request_drop_inventory_item"):
			world_drop_manager.call("request_drop_inventory_item", peer_id, slot_payload, drop_origin, launch_direction)
			_push_owner_toast("Dropped %s" % display_name, "loot")
			return true
		return false
	return _drop_item_to_world(slot_ref, drop_origin, launch_direction, true)

func _push_owner_toast(message: String, icon_key: String = "interact") -> void:
	var owner_node := owner
	if owner_node != null and owner_node.has_method("show_hud_toast"):
		owner_node.call("show_hud_toast", message, icon_key)

func _is_multiplayer_active() -> bool:
	var session = get_node_or_null("/root/NetworkSession")
	if session == null:
		return false
	return bool(session.call("is_multiplayer_active"))

func _drop_item_to_world(slot_ref: SlotRef, drop_origin: Vector3, launch_direction: Vector3, show_toast: bool = false) -> bool:
	if slot_ref == null or not _is_valid_slot(slot_ref):
		return false
	if slot_ref.section != &"storage" and slot_ref.section != &"equipment":
		return false
	var item: InventoryItemData = _get_item(slot_ref)
	if item == null:
		return false
	var world_drop_manager := _get_world_drop_manager()
	if world_drop_manager == null or not world_drop_manager.has_method("spawn_network_item_pickup"):
		return false
	_set_item(slot_ref, null)
	_emit_inventory_changed()
	if slot_ref.section == &"equipment":
		_emit_equipment_stats_changed()
	world_drop_manager.call("spawn_network_item_pickup", item.to_dict(), drop_origin, launch_direction)
	if show_toast:
		_push_owner_toast("Dropped %s" % item.display_name, "loot")
	return true

func _slot_ref_to_payload(slot_ref: SlotRef) -> Dictionary:
	if slot_ref == null:
		return {}
	return {
		"section": String(slot_ref.section),
		"index": slot_ref.index,
		"slot_name": String(slot_ref.slot_name),
	}

func _slot_ref_from_payload(payload: Dictionary) -> SlotRef:
	if payload.is_empty():
		return null
	var section := StringName(payload.get("section", ""))
	match section:
		&"equipment":
			var slot_name := StringName(payload.get("slot_name", ""))
			if slot_name == StringName(""):
				return null
			return SlotRef.equipment(slot_name)
		&"storage":
			return SlotRef.storage(int(payload.get("index", -1)))
		&"weapons":
			return SlotRef.weapon(int(payload.get("index", -1)))
		&"chest":
			return SlotRef.chest(int(payload.get("index", -1)))
		_:
			return null

func _get_world_drop_manager() -> Node:
	var manager := get_tree().get_first_node_in_group("world_item_drop_manager")
	if manager != null:
		return manager
	manager = get_tree().get_first_node_in_group("dungeon_manager")
	if manager != null and manager.has_method("spawn_network_item_pickup"):
		return manager
	var current_scene := get_tree().current_scene
	if current_scene != null and current_scene.has_method("spawn_network_item_pickup"):
		return current_scene
	return null

func _create_weapon_item(weapon_key: StringName, rarity: String) -> InventoryItemData:
	if gear_catalog != null:
		return gear_catalog.create_weapon_item(weapon_key, rarity)
	var item := InventoryItemData.new()
	item.item_id = StringName("weapon_%s_%s" % [String(weapon_key), rarity.to_lower()])
	item.display_name = String(weapon_key).capitalize()
	item.category = &"weapon"
	item.weapon_key = weapon_key
	item.stats = {"rarity": rarity}
	item.ensure_runtime_defaults()
	return item

func _can_assign_weapon_after_move(item: InventoryItemData, from_slot: SlotRef, to_slot: SlotRef) -> bool:
	if item == null or item.category != &"weapon" or to_slot.section != &"weapons":
		return true
	var ignore_indices: Array[int] = []
	if from_slot != null and from_slot.section == &"weapons":
		ignore_indices.append(from_slot.index)
	return _is_weapon_key_available_for_slot(String(item.weapon_key), to_slot.index, ignore_indices)

func _is_weapon_key_available_for_slot(weapon_key: String, target_slot_index: int, ignore_indices: Array[int]) -> bool:
	if weapon_key.is_empty():
		return false
	for i in range(weapons.size()):
		if i == target_slot_index or ignore_indices.has(i):
			continue
		var slotted_item: InventoryItemData = weapons[i]
		if slotted_item == null:
			continue
		if String(slotted_item.weapon_key) == weapon_key:
			return false
	return true

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
