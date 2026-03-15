extends CanvasLayer

const BOOTSTRAP_SCENE := "res://Scenes/System/bootstrap.tscn"

func _ready() -> void:
	layer = 10
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_build_ui()

func _build_ui() -> void:
	# Dark overlay
	var overlay := ColorRect.new()
	overlay.color = Color(0.0, 0.0, 0.0, 0.72)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)

	# Center container
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 24)
	center.add_child(vbox)

	# "VICTORY" title
	var title := Label.new()
	title.text = "VICTORY"
	title.add_theme_font_size_override("font_size", 72)
	title.add_theme_color_override("font_color", Color("ffd966"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	# Subtitle
	var subtitle := Label.new()
	subtitle.text = "You escaped the dungeon!"
	subtitle.add_theme_font_size_override("font_size", 22)
	subtitle.add_theme_color_override("font_color", Color("cccccc"))
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(subtitle)

	# Spacer
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 16)
	vbox.add_child(spacer)

	# Return to menu button
	var btn := Button.new()
	btn.text = "Return to Main Menu"
	btn.custom_minimum_size = Vector2(260, 52)
	btn.add_theme_font_size_override("font_size", 20)
	btn.pressed.connect(_on_return_pressed)
	vbox.add_child(btn)

func _on_return_pressed() -> void:
	get_tree().change_scene_to_file(BOOTSTRAP_SCENE)
