extends PanelContainer
class_name DrillHallPanel

const CATEGORIES := [
	"Mobility",
	"Survivability",
	"Ammo Economy",
	"Utility"
]

var _status_label: Label
var _level_value_label: Label
var _xp_value_label: Label
var _point_value_label: Label
var _next_xp_value_label: Label
var _category_list: VBoxContainer

func _ready() -> void:
	_build_ui()
	refresh_from_progression()

func refresh_from_progression() -> void:
	if _status_label == null:
		return
	var unlocked := MetaProgression.is_station_unlocked(MetaProgression.STATION_DRILL_HALL)
	var xp_state: Dictionary = MetaProgression.get_castle_xp_state()
	var level := int(xp_state.get("level", 0))
	var xp := int(xp_state.get("xp", 0))
	var points := int(xp_state.get("unspent_points", 0))
	var next_xp := int(xp_state.get("next_level_xp", 0))

	_level_value_label.text = str(level)
	_xp_value_label.text = str(xp)
	_point_value_label.text = str(points)
	_next_xp_value_label.text = str(next_xp)

	if unlocked:
		_status_label.text = "Drill Hall unlocked. Castle XP now feeds specialization progress."
	else:
		_status_label.text = "Locked. Unlock the Drill Hall node in the War Table to start earning Castle XP."

	for category in _category_list.get_children():
		if category is Control:
			var row := category as Control
			var name_label := row.get_node_or_null("Name") as Label
			var state_label := row.get_node_or_null("State") as Label
			if name_label != null:
				name_label.modulate = Color(0.94, 0.9, 0.82)
			if state_label != null:
				state_label.text = "Preview only" if unlocked else "Locked"
				state_label.modulate = Color(0.89, 0.77, 0.46) if unlocked else Color(0.67, 0.67, 0.72)

func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)

	var title := Label.new()
	title.text = "Drill Hall"
	title.add_theme_font_size_override("font_size", 22)
	root.add_child(title)

	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_status_label)

	root.add_child(HSeparator.new())

	var stats_row := HBoxContainer.new()
	stats_row.add_theme_constant_override("separation", 10)
	root.add_child(stats_row)

	stats_row.add_child(_make_metric_card("Level", "_level_value_label"))
	stats_row.add_child(_make_metric_card("Castle XP", "_xp_value_label"))
	stats_row.add_child(_make_metric_card("Unspent Points", "_point_value_label"))
	stats_row.add_child(_make_metric_card("Next Level", "_next_xp_value_label"))

	root.add_child(HSeparator.new())

	var categories_title := Label.new()
	categories_title.text = "Specialization Categories"
	categories_title.add_theme_font_size_override("font_size", 18)
	root.add_child(categories_title)

	_category_list = VBoxContainer.new()
	_category_list.add_theme_constant_override("separation", 8)
	root.add_child(_category_list)

	for category_name in CATEGORIES:
		_category_list.add_child(_make_category_row(category_name))

	var note := Label.new()
	note.text = "Specialization spending is not implemented yet. This panel is the forward-facing status surface."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.modulate = Color(0.82, 0.78, 0.7)
	root.add_child(note)

func _make_metric_card(title_text: String, value_field_name: String) -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(0, 92)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", _make_card_style())

	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 12)
	pad.add_theme_constant_override("margin_right", 12)
	pad.add_theme_constant_override("margin_top", 10)
	pad.add_theme_constant_override("margin_bottom", 10)
	card.add_child(pad)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	pad.add_child(vbox)

	var label := Label.new()
	label.text = title_text
	label.modulate = Color(0.94, 0.88, 0.76)
	vbox.add_child(label)

	var value := Label.new()
	value.name = StringName(value_field_name)
	value.text = "0"
	value.add_theme_font_size_override("font_size", 24)
	vbox.add_child(value)
	match value_field_name:
		"_level_value_label":
			_level_value_label = value
		"_xp_value_label":
			_xp_value_label = value
		"_point_value_label":
			_point_value_label = value
		"_next_xp_value_label":
			_next_xp_value_label = value
	return card

func _make_category_row(category_name: String) -> PanelContainer:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _make_card_style(Color(0.16, 0.13, 0.1, 0.96), Color(0.48, 0.36, 0.22)))

	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 12)
	pad.add_theme_constant_override("margin_right", 12)
	pad.add_theme_constant_override("margin_top", 10)
	pad.add_theme_constant_override("margin_bottom", 10)
	card.add_child(pad)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	pad.add_child(row)

	var name_label := Label.new()
	name_label.name = "Name"
	name_label.text = category_name
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)

	var state_label := Label.new()
	state_label.name = "State"
	state_label.text = "Locked"
	state_label.modulate = Color(0.67, 0.67, 0.72)
	row.add_child(state_label)

	return card

func _make_card_style(fill_color: Color = Color(0.14, 0.11, 0.08, 0.96), border_color: Color = Color(0.55, 0.43, 0.24)) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill_color
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = border_color
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	return style
