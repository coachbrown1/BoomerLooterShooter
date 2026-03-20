extends StaticBody3D
class_name InteractableChest

@export var interact_prompt: String = "Open Chest"
@export var chest_name: String = "Chest"
@export var slot_count: int = 16
@export var gear_catalog: GearCatalogData = preload("res://Data/gear/gear_catalog.tres")
@export var min_gear_items: int = 3
@export var max_gear_items: int = 5
var is_open: bool = false
var _stored_items: Array = []
var _lid_tween: Tween = null
@onready var lid_hinge: Node3D = _resolve_lid_hinge()

var _cached_inventory_system: InventorySystem = null

func _ready() -> void:
	# Add to interactable group if not already, useful for raycasts
	add_to_group("interactable")
	add_to_group("interactable_chest")
	if lid_hinge == null:
		push_warning("InteractableChest: LidHinge node not found for %s" % String(get_path()))
	_stored_items.resize(max(slot_count, 1))
	for i in range(_stored_items.size()):
		_stored_items[i] = null

func interact(interactor: Node = null) -> void:
	ensure_loot_populated()
	_open_lid()

	var inventory_system := _get_player_inventory_system(interactor)
	if inventory_system:
		inventory_system.open_chest(self)
		print("Chest opened: ", chest_name)

func open_visual_only() -> void:
	_open_lid()

func get_storage_copy() -> Array:
	return _stored_items.duplicate()

func get_storage_payload() -> Array:
	var payload: Array = []
	for item_variant in _stored_items:
		if item_variant == null:
			payload.append(null)
			continue
		if item_variant is InventoryItemData:
			var item: InventoryItemData = item_variant
			payload.append(item.to_dict())
			continue
		payload.append(null)
	return payload

func set_storage_items(items: Array) -> void:
	_stored_items.resize(max(slot_count, 1))
	for i in range(_stored_items.size()):
		if i >= items.size():
			_stored_items[i] = null
			continue
		_stored_items[i] = _coerce_storage_item(items[i])

func ensure_loot_populated() -> void:
	_populate_default_loot_if_needed()

func _coerce_storage_item(item_variant: Variant) -> Variant:
	if item_variant == null:
		return null
	if item_variant is InventoryItemData:
		return item_variant
	if typeof(item_variant) == TYPE_DICTIONARY:
		return InventoryItemData.from_dict(item_variant)
	return null

func close_chest() -> void:
	if not is_open or lid_hinge == null:
		return
	is_open = false
	_kill_lid_tween_if_active()
	_lid_tween = create_tween()
	_lid_tween.set_trans(Tween.TRANS_SINE)
	_lid_tween.set_ease(Tween.EASE_IN_OUT)
	_lid_tween.tween_property(lid_hinge, "rotation_degrees:x", 0.0, 0.5)

func _open_lid() -> void:
	if is_open or lid_hinge == null:
		return
	is_open = true
	_kill_lid_tween_if_active()
	_lid_tween = create_tween()
	_lid_tween.set_trans(Tween.TRANS_SINE)
	_lid_tween.set_ease(Tween.EASE_IN_OUT)
	# Rotates lid up to open
	_lid_tween.tween_property(lid_hinge, "rotation_degrees:x", 110.0, 0.8)

func _get_player_inventory_system(interactor: Node = null) -> InventorySystem:
	if interactor != null and interactor.has_method("get"):
		var candidate: Variant = interactor.get("inventory_system")
		if candidate is InventorySystem:
			return candidate

	if not is_instance_valid(_cached_inventory_system):
		var players := get_tree().get_nodes_in_group("player")
		if not players.is_empty():
			var player = players[0]
			if is_instance_valid(player):
				_cached_inventory_system = player.get("inventory_system") as InventorySystem
	return _cached_inventory_system

func _kill_lid_tween_if_active() -> void:
	if _lid_tween != null and _lid_tween.is_valid():
		_lid_tween.kill()
	_lid_tween = null

func _resolve_lid_hinge() -> Node3D:
	var direct := get_node_or_null("LidHinge")
	if direct is Node3D:
		return direct
	var nested := find_child("LidHinge", true, false)
	if nested is Node3D:
		return nested
	return null

func _populate_default_loot_if_needed() -> void:
	if gear_catalog == null:
		return
	for item in _stored_items:
		if item != null:
			return

	# Mix the chest's stable identity hash with the dungeon's per-run seed so
	# loot varies each playthrough while remaining deterministic within a run.
	var dungeon_seed: int = 0
	var dm := get_tree().get_first_node_in_group("dungeon_manager")
	if dm and "generation_seed" in dm:
		dungeon_seed = int(dm.generation_seed)

	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s|%s|%d" % [String(get_path()), chest_name, slot_count]) ^ dungeon_seed
	var desired_count := clampi(rng.randi_range(min_gear_items, max_gear_items), 1, slot_count)
	var loot := gear_catalog.create_random_items(desired_count, int(rng.randi()))
	set_storage_items(loot)
