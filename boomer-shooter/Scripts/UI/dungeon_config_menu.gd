## DungeonConfigMenu — shown when the player interacts with the hub portal.
## Lets the player configure grid size and seed before entering the dungeon.
## Emits `confirmed` with the chosen settings, or `cancelled` if dismissed.
extends CanvasLayer
class_name DungeonConfigMenu

signal confirmed(grid_min: int, grid_max: int, seed_val: int)
signal cancelled

var _grid_min_spin: SpinBox
var _grid_max_spin: SpinBox
var _seed_spin: SpinBox

func _ready() -> void:
	_build_ui()
	_populate_from_game_state()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _build_ui() -> void:
	layer = 10

	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.0, 0.0, 0.65)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	center.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(420, 0)
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	# Title
	var title := Label.new()
	title.text = "Configure Dungeon"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	vbox.add_child(title)

	vbox.add_child(HSeparator.new())

	# Grid Min row
	vbox.add_child(_make_row("Grid Min", func(row: HBoxContainer) -> void:
		_grid_min_spin = SpinBox.new()
		_grid_min_spin.min_value = 2
		_grid_min_spin.max_value = 20
		_grid_min_spin.step = 1
		_grid_min_spin.value = 10
		_grid_min_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_grid_min_spin.value_changed.connect(_on_grid_min_changed)
		row.add_child(_grid_min_spin)
	))

	# Grid Max row
	vbox.add_child(_make_row("Grid Max", func(row: HBoxContainer) -> void:
		_grid_max_spin = SpinBox.new()
		_grid_max_spin.min_value = 2
		_grid_max_spin.max_value = 20
		_grid_max_spin.step = 1
		_grid_max_spin.value = 10
		_grid_max_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(_grid_max_spin)
	))

	# Seed row
	vbox.add_child(_make_row("Seed  (0 = random)", func(row: HBoxContainer) -> void:
		_seed_spin = SpinBox.new()
		_seed_spin.min_value = 0
		_seed_spin.max_value = 2147483647
		_seed_spin.step = 1
		_seed_spin.value = 0
		_seed_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(_seed_spin)
	))

	vbox.add_child(HSeparator.new())

	# Buttons
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 10)
	vbox.add_child(btn_row)

	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel_btn.pressed.connect(_on_cancel)
	btn_row.add_child(cancel_btn)

	var enter_btn := Button.new()
	enter_btn.text = "Enter Dungeon"
	enter_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	enter_btn.pressed.connect(_on_confirm)
	btn_row.add_child(enter_btn)


func _make_row(label_text: String, fill_fn: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(150, 0)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(lbl)
	fill_fn.call(row)
	return row


func _populate_from_game_state() -> void:
	_grid_min_spin.value = GameState.dungeon_grid_min
	_grid_max_spin.value = GameState.dungeon_grid_max
	_seed_spin.value = GameState.dungeon_seed


func _on_grid_min_changed(val: float) -> void:
	if _grid_max_spin != null:
		_grid_max_spin.min_value = val
		if _grid_max_spin.value < val:
			_grid_max_spin.value = val


func _on_confirm() -> void:
	var grid_min := int(_grid_min_spin.value)
	var grid_max := int(maxi(int(_grid_max_spin.value), grid_min))
	confirmed.emit(
		grid_min,
		grid_max,
		int(_seed_spin.value)
	)
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	queue_free()


func _on_cancel() -> void:
	cancelled.emit()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_on_cancel()
