extends StaticBody3D
class_name InteractableChest

@export var interact_prompt: String = "Open Chest"
@export var chest_name: String = "Chest"
@export var slot_count: int = 16
var is_open: bool = false
var _stored_items: Array = []
var _lid_tween: Tween = null
@onready var lid_hinge: Node3D = $LidHinge

var _cached_inventory_system: InventorySystem = null

func _ready() -> void:
	# Add to interactable group if not already, useful for raycasts
	add_to_group("interactable")
	_stored_items.resize(max(slot_count, 1))
	for i in range(_stored_items.size()):
		_stored_items[i] = null

func interact() -> void:
	if not is_open:
		is_open = true
		_kill_lid_tween_if_active()
		_lid_tween = create_tween()
		_lid_tween.set_trans(Tween.TRANS_SINE)
		_lid_tween.set_ease(Tween.EASE_IN_OUT)
		# Rotates lid up to open
		_lid_tween.tween_property(lid_hinge, "rotation_degrees:x", -110.0, 0.8)

	var inventory_system := _get_player_inventory_system()
	if inventory_system:
		inventory_system.open_chest(self)
		print("Chest opened: ", chest_name)

func get_storage_copy() -> Array:
	return _stored_items.duplicate()

func set_storage_items(items: Array) -> void:
	_stored_items.resize(max(slot_count, 1))
	for i in range(_stored_items.size()):
		_stored_items[i] = items[i] if i < items.size() else null

func close_chest() -> void:
	if not is_open:
		return
	is_open = false
	_kill_lid_tween_if_active()
	_lid_tween = create_tween()
	_lid_tween.set_trans(Tween.TRANS_SINE)
	_lid_tween.set_ease(Tween.EASE_IN_OUT)
	_lid_tween.tween_property(lid_hinge, "rotation_degrees:x", 0.0, 0.5)

func _get_player_inventory_system() -> InventorySystem:
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
