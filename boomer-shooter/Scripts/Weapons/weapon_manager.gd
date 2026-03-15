extends Node3D
class_name WeaponManager

@onready var player: CharacterBody3D = owner

var weapons: Array[Weapon] = []
var current_weapon_index: int = -1 # Inventory weapon slot index (0-3)
var current_weapon: Weapon = null
var inventory_system: InventorySystem = null

var _slot_weapons: Array = []
var _weapon_key_to_weapon: Dictionary = {}

var _cached_huds: Array[Node] = []
var _input_enabled: bool = true
var _viewmodel_enabled: bool = true
var _equipment_stats: Dictionary = {}

# Inventory of ammo
# "light" is bullets
# "shells" is shotgun shells
# "energy" is for plasma/fireball
# "arrows" is for crossbow
var ammo_inventory: Dictionary = {
	"light": 60,
	"shells": 20,
	"energy": 5,
	"arrows": 0
}

signal ammo_changed(current, reserve, type)
signal weapon_changed(weapon)

func _ready() -> void:
	_slot_weapons.resize(4)
	for i in range(_slot_weapons.size()):
		_slot_weapons[i] = null

	for child in get_children():
		if child is Weapon:
			weapons.append(child)
			child.hide_weapon()

			# Setup signal connections for HUD
			if not child.fired.is_connected(_on_weapon_fired):
				child.fired.connect(_on_weapon_fired)

			# Ensure weapon has a reference to the manager
			child.weapon_manager = self
			_weapon_key_to_weapon[get_weapon_key_for_weapon(child)] = child
	_sync_default_slot_weapons()
	_select_first_available_weapon()

func switch_to_weapon(index: int) -> void:
	if index < 0 or index >= _slot_weapons.size() or index == current_weapon_index:
		return
	var weapon_to_switch: Weapon = _slot_weapons[index]
	if weapon_to_switch == null:
		return

	if current_weapon:
		current_weapon.hide_weapon()

	current_weapon_index = index
	current_weapon = weapon_to_switch
	current_weapon.show_weapon()
	weapon_changed.emit(current_weapon)
	_update_hud()

func next_weapon() -> void:
	_cycle_weapon(1)

func prev_weapon() -> void:
	_cycle_weapon(-1)

func _unhandled_input(event: InputEvent) -> void:
	if is_input_blocked() or not _input_enabled:
		return
	if not current_weapon or current_weapon.is_reloading:
		return

	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			next_weapon()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			prev_weapon()

	if InputMap.has_action("reload") and event.is_action_pressed("reload"):
		if current_weapon and current_weapon.can_reload():
			if _is_network_multiplayer_active() and not _is_network_host():
				var dungeon_manager = get_tree().get_first_node_in_group("dungeon_manager")
				if dungeon_manager != null and dungeon_manager.has_method("request_weapon_reload"):
					dungeon_manager.call(
						"request_weapon_reload",
						_get_owner_peer_id(),
						current_weapon_index,
						get_current_weapon_key()
					)
			current_weapon.reload(false)

func get_ammo(type: String) -> int:
	return ammo_inventory.get(type, 0)

func consume_ammo(type: String, amount: int) -> void:
	if type in ammo_inventory:
		ammo_inventory[type] -= amount
		ammo_inventory[type] = max(0, ammo_inventory[type])
	_update_hud()

func add_ammo(type: String, amount: int) -> void:
	if type in ammo_inventory:
		ammo_inventory[type] += amount
	_update_hud()

func _on_weapon_fired() -> void:
	_update_hud()

func _update_hud() -> void:
	if not current_weapon:
		return
	if not _is_local_owner():
		return
	ammo_changed.emit(current_weapon.current_mag, get_ammo(current_weapon.ammo_type), current_weapon.ammo_type)

	# Optional: Directly update HUD group
	var huds_valid = _cached_huds.size() > 0
	if huds_valid:
		for hud in _cached_huds:
			if not is_instance_valid(hud):
				huds_valid = false
				break

	if not huds_valid:
		_cached_huds = get_tree().get_nodes_in_group("hud")

	for hud in _cached_huds:
		if is_instance_valid(hud) and hud.has_method("update_ammo_display"):
			var displayed_mag_size := current_weapon.mag_size
			if current_weapon.has_method("get_effective_mag_size"):
				displayed_mag_size = int(current_weapon.call("get_effective_mag_size"))
			hud.update_ammo_display(
				current_weapon.current_mag,
				displayed_mag_size,
				get_ammo(current_weapon.ammo_type),
				current_weapon.ammo_type == "none",
				current_weapon.has_infinite_reserve_ammo() if current_weapon.has_method("has_infinite_reserve_ammo") else false
			)

func set_inventory_system(inventory: InventorySystem) -> void:
	if inventory_system and inventory_system.weapon_slots_changed.is_connected(_on_weapon_slots_changed):
		inventory_system.weapon_slots_changed.disconnect(_on_weapon_slots_changed)

	inventory_system = inventory
	if inventory_system:
		if not inventory_system.weapon_slots_changed.is_connected(_on_weapon_slots_changed):
			inventory_system.weapon_slots_changed.connect(_on_weapon_slots_changed)
		_on_weapon_slots_changed(inventory_system.weapons)
		apply_equipment_stats(inventory_system.get_equipped_stats())
	else:
		_sync_default_slot_weapons()
		_select_first_available_weapon()

func activate_weapon_slot(index: int) -> void:
	switch_to_weapon(index)

func get_weapons() -> Array[Weapon]:
	return weapons.duplicate()

func get_weapon_key_for_weapon(weapon: Weapon) -> String:
	if weapon == null:
		return ""
	return _normalize_weapon_name(weapon.weapon_name)

func is_input_blocked() -> bool:
	return inventory_system != null and inventory_system.is_inventory_open()

func set_input_enabled(enabled: bool) -> void:
	_input_enabled = enabled

func is_input_enabled() -> bool:
	return _input_enabled

func set_viewmodel_enabled(enabled: bool) -> void:
	_viewmodel_enabled = enabled
	for weapon in weapons:
		if weapon == null:
			continue
		weapon.set_viewmodel_enabled(enabled)

func apply_equipment_stats(stats: Dictionary) -> void:
	_equipment_stats = stats.duplicate(true)
	for weapon in weapons:
		if weapon == null:
			continue
		if weapon.has_method("set_equipment_stats"):
			weapon.set_equipment_stats(_equipment_stats)
	_refresh_weapon_item_stats()

func get_current_weapon_slot() -> int:
	return current_weapon_index

func get_current_weapon() -> Weapon:
	return current_weapon

func get_current_weapon_key() -> String:
	if current_weapon == null:
		return ""
	return get_weapon_key_for_weapon(current_weapon)

func switch_to_weapon_by_key(raw_key: String) -> bool:
	var key := _normalize_weapon_name(raw_key)
	if key.is_empty():
		return false
	var weapon: Weapon = _weapon_key_to_weapon.get(key, null)
	if weapon == null:
		return false

	var slot_index := _find_slot_index_for_weapon(weapon)
	if slot_index >= 0:
		switch_to_weapon(slot_index)
		return true

	if current_weapon and current_weapon != weapon:
		current_weapon.hide_weapon()
	current_weapon = weapon
	current_weapon_index = -1
	current_weapon.show_weapon()
	weapon_changed.emit(current_weapon)
	_update_hud()
	return true

func get_ammo_snapshot() -> Dictionary:
	return ammo_inventory.duplicate(true)

func apply_authoritative_weapon_state(slot_index: int, current_mag_value: int, ammo_snapshot: Dictionary) -> void:
	for ammo_key in ammo_snapshot.keys():
		ammo_inventory[ammo_key] = int(ammo_snapshot[ammo_key])

	if slot_index >= 0:
		switch_to_weapon(slot_index)

	if current_weapon != null:
		var effective_mag_size := current_weapon.mag_size
		if current_weapon.has_method("get_effective_mag_size"):
			effective_mag_size = int(current_weapon.call("get_effective_mag_size"))
		current_weapon.current_mag = max(0, min(effective_mag_size, current_mag_value))

	_update_hud()

func _on_weapon_slots_changed(weapon_items: Array) -> void:
	_slot_weapons.resize(4)
	for i in range(_slot_weapons.size()):
		_slot_weapons[i] = null

	for i in range(min(weapon_items.size(), _slot_weapons.size())):
		var item = weapon_items[i]
		if item == null:
			continue
		var key: String = String(item.weapon_key)
		var weapon: Weapon = _weapon_key_to_weapon.get(key)
		_slot_weapons[i] = weapon

	_refresh_weapon_item_stats()

	if current_weapon != null:
		var mapped_index := _find_slot_index_for_weapon(current_weapon)
		if mapped_index == -1:
			current_weapon.hide_weapon()
			current_weapon = null
			current_weapon_index = -1
		elif mapped_index != current_weapon_index:
			current_weapon.hide_weapon()
			current_weapon = null
			current_weapon_index = -1
			switch_to_weapon(mapped_index)
			return

	if not _slot_has_weapon(current_weapon_index):
		if current_weapon:
			current_weapon.hide_weapon()
		current_weapon = null
		current_weapon_index = -1

	_select_first_available_weapon()
	_update_hud()

func _refresh_weapon_item_stats() -> void:
	var stats_by_key: Dictionary = {}
	if inventory_system != null:
		for item_variant in inventory_system.weapons:
			if item_variant == null:
				continue
			var item: InventoryItemData = item_variant
			var weapon_key := String(item.weapon_key)
			if weapon_key.is_empty():
				continue
			stats_by_key[weapon_key] = item.get_total_stats()

	for weapon in weapons:
		if weapon == null or not weapon.has_method("set_weapon_item_stats"):
			continue
		var key := get_weapon_key_for_weapon(weapon)
		weapon.call("set_weapon_item_stats", stats_by_key.get(key, {}))

func _sync_default_slot_weapons() -> void:
	_slot_weapons.resize(4)
	for i in range(_slot_weapons.size()):
		_slot_weapons[i] = null
	for i in range(min(weapons.size(), _slot_weapons.size())):
		_slot_weapons[i] = weapons[i]

func _select_first_available_weapon() -> void:
	if current_weapon and _slot_has_weapon(current_weapon_index):
		return
	for i in range(_slot_weapons.size()):
		if _slot_weapons[i] != null:
			switch_to_weapon(i)
			return

func _cycle_weapon(direction: int) -> void:
	if _occupied_slot_count() <= 1:
		return

	var slot_count := _slot_weapons.size()
	var idx := current_weapon_index
	if idx < 0:
		idx = 0
	for _step in range(slot_count):
		idx = (idx + direction + slot_count) % slot_count
		if _slot_weapons[idx] != null:
			switch_to_weapon(idx)
			return

func _occupied_slot_count() -> int:
	var total := 0
	for slot_weapon in _slot_weapons:
		if slot_weapon != null:
			total += 1
	return total

func _slot_has_weapon(index: int) -> bool:
	return index >= 0 and index < _slot_weapons.size() and _slot_weapons[index] != null

func _find_slot_index_for_weapon(target_weapon: Weapon) -> int:
	for i in range(_slot_weapons.size()):
		if _slot_weapons[i] == target_weapon:
			return i
	return -1

func _normalize_weapon_name(raw_name: String) -> String:
	return raw_name.strip_edges().to_lower().replace(" ", "_")

func _get_owner_peer_id() -> int:
	if player != null and player.has_method("get_network_peer_id"):
		return int(player.call("get_network_peer_id"))
	return _get_network_local_peer_id()

func _is_local_owner() -> bool:
	if player != null and player.has_method("is_local_controlled"):
		return bool(player.call("is_local_controlled"))
	return true

func _get_network_session():
	return get_node_or_null("/root/NetworkSession")

func _is_network_multiplayer_active() -> bool:
	var session = _get_network_session()
	if session == null:
		return false
	return bool(session.call("is_multiplayer_active"))

func _is_network_host() -> bool:
	var session = _get_network_session()
	if session == null:
		return true
	return bool(session.call("is_host"))

func _get_network_local_peer_id() -> int:
	var session = _get_network_session()
	if session == null:
		return 1
	return int(session.call("get_local_peer_id"))
