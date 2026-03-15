extends Area3D
class_name LootPickup

var item_data: InventoryItemData = null
var ammo_type: String = ""
var ammo_amount: int = 0
var ammo_display_name: String = ""
var ammo_icon_path: String = ""
var health_amount: int = 0
var health_display_name: String = ""
var health_icon_path: String = ""

const HOVER_AMPLITUDE := 0.07
const HOVER_SPEED := 2.2
const ROTATE_SPEED := 1.2
const LAUNCH_DURATION := 0.55

var _hovering := false
var _hover_base_y := 0.0
var _hover_time := 0.0
var _sprite: Sprite3D = null

func _ready() -> void:
	add_to_group("loot_pickup")
	_sprite = Sprite3D.new()
	_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_sprite.pixel_size = 0.001
	add_child(_sprite)

	var shape_node := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.3
	shape_node.shape = sphere
	add_child(shape_node)

	if item_data != null or _is_ammo_pickup() or _is_health_pickup():
		_apply_icon()

func _apply_icon() -> void:
	if _sprite == null:
		return
	if _is_health_pickup():
		if not health_icon_path.is_empty() and ResourceLoader.exists(health_icon_path):
			_sprite.texture = load(health_icon_path)
		_sprite.modulate = Color("ff6b7d")
		return
	if _is_ammo_pickup():
		if not ammo_icon_path.is_empty() and ResourceLoader.exists(ammo_icon_path):
			_sprite.texture = load(ammo_icon_path)
		_sprite.modulate = _get_ammo_color()
		return
	if item_data == null:
		return
	var tex: Texture2D = item_data.item_icon
	if tex == null and not item_data.item_icon_path.is_empty():
		if ResourceLoader.exists(item_data.item_icon_path):
			tex = load(item_data.item_icon_path)
	if tex != null:
		_sprite.texture = tex
	# Tint based on rarity so it pops visually
	var rarity := item_data.rarity_name
	if rarity.is_empty():
		rarity = String(item_data.stats.get("rarity", ""))
	match rarity:
		"Legendary": _sprite.modulate = Color("ff9f2f")
		"Epic":      _sprite.modulate = Color("b05cff")
		"Rare":      _sprite.modulate = Color("4d7dff")
		"Uncommon":  _sprite.modulate = Color("49b36a")
		_:           _sprite.modulate = Color.WHITE

func launch(from_pos: Vector3, direction: Vector3) -> void:
	global_position = from_pos
	var spread := Vector3(randf_range(-0.3, 0.3), 0.0, randf_range(-0.3, 0.3))
	var land_pos := from_pos + direction * randf_range(0.6, 1.4) + spread
	land_pos.y = from_pos.y
	var peak_y := from_pos.y + randf_range(0.7, 1.2)
	var half := LAUNCH_DURATION * 0.5

	# Horizontal: linear travel to landing spot
	var tx := create_tween()
	tx.tween_property(self, "global_position:x", land_pos.x, LAUNCH_DURATION)
	var tz := create_tween()
	tz.tween_property(self, "global_position:z", land_pos.z, LAUNCH_DURATION)

	# Vertical: arc up then fall down, then start hover
	var ty := create_tween()
	ty.tween_property(self, "global_position:y", peak_y, half).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	ty.tween_property(self, "global_position:y", land_pos.y, half).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	ty.tween_callback(_start_hover)

func _start_hover() -> void:
	_hover_base_y = global_position.y
	_hovering = true

func settle_at(world_pos: Vector3) -> void:
	global_position = world_pos
	_start_hover()

func _process(delta: float) -> void:
	if not _hovering:
		return
	_hover_time += delta
	global_position.y = _hover_base_y + sin(_hover_time * HOVER_SPEED) * HOVER_AMPLITUDE
	if _sprite:
		_sprite.rotation.y += ROTATE_SPEED * delta

func interact(interactor: Node) -> void:
	if _is_health_pickup():
		if interactor == null or not interactor.has_method("heal"):
			return
		if int(interactor.get("current_health")) >= int(interactor.get("max_health")):
			return
		interactor.call("heal", health_amount)
		queue_free()
		return
	if _is_ammo_pickup():
		var manager: WeaponManager = interactor.get("weapon_manager") as WeaponManager
		if manager == null or ammo_type.is_empty() or ammo_amount <= 0:
			return
		manager.add_ammo(ammo_type, ammo_amount)
		queue_free()
		return
	if item_data == null:
		queue_free()
		return
	var inv: InventorySystem = interactor.get("inventory_system") as InventorySystem
	if inv == null:
		return
	if inv.try_add_to_storage(item_data):
		queue_free()

func get_item_snapshot() -> Dictionary:
	if _is_health_pickup():
		return {
			"display_name": _get_health_display_name(),
			"category": "health",
			"health_amount": health_amount,
			"icon_path": health_icon_path,
			"rarity": ""
		}
	if _is_ammo_pickup():
		return {
			"display_name": _get_ammo_display_name(),
			"category": "ammo",
			"ammo_type": ammo_type,
			"ammo_amount": ammo_amount,
			"icon_path": ammo_icon_path,
			"rarity": ""
		}
	if item_data == null:
		return {}
	return item_data.to_dict()

func configure_ammo_pickup(new_ammo_type: String, new_ammo_amount: int, new_display_name: String, new_icon_path: String) -> void:
	ammo_type = new_ammo_type
	ammo_amount = new_ammo_amount
	ammo_display_name = new_display_name
	ammo_icon_path = new_icon_path
	if _sprite != null:
		_apply_icon()

func configure_health_pickup(new_health_amount: int, new_display_name: String, new_icon_path: String) -> void:
	health_amount = new_health_amount
	health_display_name = new_display_name
	health_icon_path = new_icon_path
	if _sprite != null:
		_apply_icon()

func configure_item_pickup(new_item_data: InventoryItemData) -> void:
	item_data = new_item_data
	ammo_type = ""
	ammo_amount = 0
	ammo_display_name = ""
	ammo_icon_path = ""
	health_amount = 0
	health_display_name = ""
	health_icon_path = ""
	if _sprite != null:
		_apply_icon()

func _is_ammo_pickup() -> bool:
	return not ammo_type.is_empty() and ammo_amount > 0

func _is_health_pickup() -> bool:
	return health_amount > 0

func _get_ammo_display_name() -> String:
	if not ammo_display_name.is_empty():
		return ammo_display_name
	return "%s Ammo" % ammo_type.capitalize()

func _get_health_display_name() -> String:
	if not health_display_name.is_empty():
		return health_display_name
	return "Health Pickup"

func _get_ammo_color() -> Color:
	match ammo_type:
		"energy":
			return Color("ffd84d")
		"shells":
			return Color("ff8f59")
		"light":
			return Color("9dd6ff")
		_:
			return Color.WHITE
