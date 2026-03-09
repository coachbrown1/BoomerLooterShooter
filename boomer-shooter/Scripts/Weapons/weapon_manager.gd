extends Node3D
class_name WeaponManager

@onready var player: CharacterBody3D = owner

var weapons: Array[Weapon] = []
var current_weapon_index: int = -1
var current_weapon: Weapon = null

# Inventory of ammo
# "light" is bullets
# "shells" is shotgun shells
# "energy" is for plasma/fireball
# "arrows" is for crossbow
var ammo_inventory: Dictionary = {
	"light": 100,
	"shells": 20,
	"energy": 50,
	"arrows": 15
}

signal ammo_changed(current, reserve, type)
signal weapon_changed(weapon)

func _ready() -> void:
	for child in get_children():
		if child is Weapon:
			weapons.append(child)
			child.hide_weapon()

			# Setup signal connections for HUD
			if not child.fired.is_connected(_on_weapon_fired):
				child.fired.connect(_on_weapon_fired)

			# Ensure weapon has a reference to the manager
			child.weapon_manager = self

	if weapons.size() > 0:
		switch_to_weapon(0)

func switch_to_weapon(index: int) -> void:
	if index < 0 or index >= weapons.size() or index == current_weapon_index:
		return

	if current_weapon:
		current_weapon.hide_weapon()

	current_weapon_index = index
	current_weapon = weapons[current_weapon_index]
	current_weapon.show_weapon()
	weapon_changed.emit(current_weapon)
	_update_hud()

func next_weapon() -> void:
	if weapons.size() <= 1: return
	var next_idx = (current_weapon_index + 1) % weapons.size()
	switch_to_weapon(next_idx)

func prev_weapon() -> void:
	if weapons.size() <= 1: return
	var prev_idx = current_weapon_index - 1
	if prev_idx < 0:
		prev_idx = weapons.size() - 1
	switch_to_weapon(prev_idx)

func _unhandled_input(event: InputEvent) -> void:
	if not current_weapon or current_weapon.is_reloading:
		return

	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			next_weapon()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			prev_weapon()

	if event.is_action_pressed("reload"):
		if current_weapon and current_weapon.can_reload():
			current_weapon.reload()

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
	if not current_weapon: return
	ammo_changed.emit(current_weapon.current_mag, get_ammo(current_weapon.ammo_type), current_weapon.ammo_type)

	# Optional: Directly update HUD group
	var huds = get_tree().get_nodes_in_group("hud")
	for hud in huds:
		if hud.has_method("update_ammo_display"):
			hud.update_ammo_display(
				current_weapon.current_mag,
				current_weapon.mag_size,
				get_ammo(current_weapon.ammo_type),
				current_weapon.ammo_type == "none"
			)
