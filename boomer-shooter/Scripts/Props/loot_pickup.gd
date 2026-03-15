extends Area3D
class_name LootPickup

var item_data: InventoryItemData = null

const HOVER_AMPLITUDE := 0.07
const HOVER_SPEED := 2.2
const ROTATE_SPEED := 1.2
const LAUNCH_DURATION := 0.55

var _hovering := false
var _hover_base_y := 0.0
var _hover_time := 0.0
var _sprite: Sprite3D = null

func _ready() -> void:
	_sprite = Sprite3D.new()
	_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_sprite.pixel_size = 0.001
	add_child(_sprite)

	var shape_node := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.3
	shape_node.shape = sphere
	add_child(shape_node)

	if item_data != null:
		_apply_icon()

func _apply_icon() -> void:
	if _sprite == null or item_data == null:
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

func _process(delta: float) -> void:
	if not _hovering:
		return
	_hover_time += delta
	global_position.y = _hover_base_y + sin(_hover_time * HOVER_SPEED) * HOVER_AMPLITUDE
	if _sprite:
		_sprite.rotation.y += ROTATE_SPEED * delta

func interact(interactor: Node) -> void:
	if item_data == null:
		queue_free()
		return
	var inv: InventorySystem = interactor.get("inventory_system") as InventorySystem
	if inv == null:
		return
	if inv.try_add_to_storage(item_data):
		queue_free()

func get_item_snapshot() -> Dictionary:
	if item_data == null:
		return {}
	return item_data.to_dict()
