extends CanvasLayer
class_name WarTableMenu

signal closed

const NODE_STATE_HIDDEN := "hidden"
const NODE_STATE_VISIBLE := "visible"
const NODE_STATE_UNLOCKED := "unlocked"

var _currency_value: Label
var _message_label: Label
var _node_list: VBoxContainer
var _selection_title: Label
var _selection_state: Label
var _selection_branch: Label
var _selection_cost: Label
var _selection_requirements: Label
var _selection_details: Label
var _unlock_button: Button
var _node_buttons: Dictionary = {}
var _selected_node_id: String = ""
var _drill_hall_panel: DrillHallPanel
var _tab_container: TabContainer

func _ready() -> void:
	layer = 20
	_build_ui()
	refresh_from_progression()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func refresh_from_progression() -> void:
	if _currency_value != null:
		_currency_value.text = str(MetaProgression.get_war_table_currency())
	if _message_label != null and _message_label.text.is_empty():
		_message_label.text = "Select a node to inspect its requirements or unlock it."
	_rebuild_node_list()
	if _selected_node_id.is_empty():
		var nodes := MetaProgression.get_war_table_nodes()
		if not nodes.is_empty():
			_selected_node_id = String(nodes[0].get("id", ""))
	_refresh_selected_node()
	if _drill_hall_panel != null:
		_drill_hall_panel.refresh_from_progression()

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.02, 0.02, 0.82)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(1220, 760)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.11, 0.08, 0.06, 0.98), Color(0.63, 0.48, 0.25)))
	center.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	panel.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)

	var header_row := HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 12)
	root.add_child(header_row)

	var title_box := VBoxContainer.new()
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_child(title_box)

	var title := Label.new()
	title.text = "War Table"
	title.add_theme_font_size_override("font_size", 28)
	title_box.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Command the castle's long-term progression and open future hub stations."
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle.modulate = Color(0.88, 0.83, 0.72)
	title_box.add_child(subtitle)

	var currency_box := VBoxContainer.new()
	currency_box.alignment = BoxContainer.ALIGNMENT_END
	header_row.add_child(currency_box)

	var currency_label := Label.new()
	currency_label.text = "War Table Currency"
	currency_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	currency_label.modulate = Color(0.92, 0.84, 0.63)
	currency_box.add_child(currency_label)

	_currency_value = Label.new()
	_currency_value.text = "0"
	_currency_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_currency_value.add_theme_font_size_override("font_size", 24)
	currency_box.add_child(_currency_value)

	var close_button := Button.new()
	close_button.text = "Close"
	close_button.pressed.connect(_on_close_pressed)
	header_row.add_child(close_button)

	_message_label = Label.new()
	_message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message_label.modulate = Color(0.86, 0.82, 0.74)
	root.add_child(_message_label)

	root.add_child(HSeparator.new())

	_tab_container = TabContainer.new()
	_tab_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tab_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_tab_container)

	var war_table_page := VBoxContainer.new()
	war_table_page.name = "War Table"
	war_table_page.add_theme_constant_override("separation", 10)
	_tab_container.add_child(war_table_page)

	var page_summary := Label.new()
	page_summary.text = "Unlocked nodes glow with power. Hidden branches remain fogged until adjacent nodes reveal them."
	page_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page_summary.modulate = Color(0.85, 0.8, 0.7)
	war_table_page.add_child(page_summary)

	var content_row := HBoxContainer.new()
	content_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_row.add_theme_constant_override("separation", 14)
	war_table_page.add_child(content_row)

	var tree_panel := PanelContainer.new()
	tree_panel.custom_minimum_size = Vector2(460, 0)
	tree_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tree_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tree_panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.10, 0.08, 0.05, 0.98), Color(0.48, 0.37, 0.22)))
	content_row.add_child(tree_panel)

	var tree_margin := MarginContainer.new()
	tree_margin.add_theme_constant_override("margin_left", 12)
	tree_margin.add_theme_constant_override("margin_right", 12)
	tree_margin.add_theme_constant_override("margin_top", 12)
	tree_margin.add_theme_constant_override("margin_bottom", 12)
	tree_panel.add_child(tree_margin)

	var tree_root := VBoxContainer.new()
	tree_root.add_theme_constant_override("separation", 10)
	tree_margin.add_child(tree_root)

	var tree_title := Label.new()
	tree_title.text = "Unlock Tree"
	tree_title.add_theme_font_size_override("font_size", 18)
	tree_root.add_child(tree_title)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tree_root.add_child(scroll)

	_node_list = VBoxContainer.new()
	_node_list.add_theme_constant_override("separation", 8)
	scroll.add_child(_node_list)

	var detail_panel := PanelContainer.new()
	detail_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.14, 0.11, 0.08, 0.98), Color(0.58, 0.44, 0.25)))
	content_row.add_child(detail_panel)

	var detail_margin := MarginContainer.new()
	detail_margin.add_theme_constant_override("margin_left", 16)
	detail_margin.add_theme_constant_override("margin_right", 16)
	detail_margin.add_theme_constant_override("margin_top", 16)
	detail_margin.add_theme_constant_override("margin_bottom", 16)
	detail_panel.add_child(detail_margin)

	var detail_root := VBoxContainer.new()
	detail_root.add_theme_constant_override("separation", 10)
	detail_margin.add_child(detail_root)

	_selection_title = Label.new()
	_selection_title.text = "Select a node"
	_selection_title.add_theme_font_size_override("font_size", 22)
	detail_root.add_child(_selection_title)

	_selection_state = Label.new()
	_selection_state.modulate = Color(0.9, 0.82, 0.58)
	detail_root.add_child(_selection_state)

	_selection_branch = Label.new()
	detail_root.add_child(_selection_branch)

	_selection_cost = Label.new()
	detail_root.add_child(_selection_cost)

	_selection_requirements = Label.new()
	_selection_requirements.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_selection_requirements.modulate = Color(0.86, 0.8, 0.73)
	detail_root.add_child(_selection_requirements)

	_selection_details = Label.new()
	_selection_details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_selection_details.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_root.add_child(_selection_details)

	_unlock_button = Button.new()
	_unlock_button.text = "Unlock"
	_unlock_button.pressed.connect(_on_unlock_pressed)
	detail_root.add_child(_unlock_button)

	var drill_hall_page := DrillHallPanel.new()
	drill_hall_page.name = "Drill Hall"
	drill_hall_page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	drill_hall_page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tab_container.add_child(drill_hall_page)
	_drill_hall_panel = drill_hall_page

func _rebuild_node_list() -> void:
	for child in _node_list.get_children():
		child.queue_free()
	_node_buttons.clear()
	var last_branch := ""
	for node_state in MetaProgression.get_war_table_nodes():
		var branch := String(node_state.get("branch", ""))
		if branch != last_branch:
			var branch_label := Label.new()
			branch_label.text = branch.to_upper()
			branch_label.modulate = Color(0.96, 0.82, 0.52)
			branch_label.add_theme_font_size_override("font_size", 13)
			_node_list.add_child(branch_label)
			last_branch = branch
		var button := Button.new()
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size = Vector2(0, 42)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.text = _format_node_button_text(node_state)
		button.pressed.connect(_on_node_button_pressed.bind(String(node_state.get("id", ""))))
		_style_node_button(button, node_state)
		_node_list.add_child(button)
		_node_buttons[String(node_state.get("id", ""))] = button

func _refresh_selected_node() -> void:
	if _selected_node_id.is_empty() and not _node_buttons.is_empty():
		_selected_node_id = String(_node_buttons.keys()[0])
	var node_state := MetaProgression.get_node_state(_selected_node_id)
	if node_state.is_empty():
		_selection_title.text = "Select a node"
		_selection_state.text = ""
		_selection_branch.text = ""
		_selection_cost.text = ""
		_selection_requirements.text = ""
		_selection_details.text = "Choose a node from the tree to inspect its requirements."
		_unlock_button.disabled = true
		return

	var node_id := String(node_state.get("id", ""))
	var visible := bool(node_state.get("visible", false))
	var unlocked := bool(node_state.get("unlocked", false))
	var permanent_lock := bool(node_state.get("permanent_lock", false))
	var title := String(node_state.get("title", node_id))
	_selection_title.text = title if visible or unlocked or permanent_lock else "Hidden Node"
	_selection_state.text = _get_state_text(node_state)
	_selection_branch.text = "Branch: %s" % String(node_state.get("branch", ""))
	_selection_cost.text = "Cost: %d War Table currency" % int(node_state.get("cost", 0))
	_selection_requirements.text = _get_requirement_text(node_state)
	_selection_details.text = _get_node_details_text(node_state)
	_unlock_button.text = "Unlock Node" if not unlocked else "Unlocked"
	_unlock_button.disabled = not _can_attempt_unlock(node_state)

	for key in _node_buttons.keys():
		var button := _node_buttons[key] as Button
		if button == null:
			continue
		var state := MetaProgression.get_node_state(String(key))
		button.text = _format_node_button_text(state, String(key) == _selected_node_id)

func _on_node_button_pressed(node_id: String) -> void:
	_selected_node_id = node_id
	_refresh_selected_node()

func _on_unlock_pressed() -> void:
	if _selected_node_id.is_empty():
		return
	var node_state := MetaProgression.get_node_state(_selected_node_id)
	if node_state.is_empty():
		return
	if MetaProgression.unlock_node(_selected_node_id):
		_message_label.text = "%s unlocked." % String(node_state.get("title", _selected_node_id))
		refresh_from_progression()
	else:
		_message_label.text = _get_unlock_failure_reason(node_state)

func _on_close_pressed() -> void:
	closed.emit()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	queue_free()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_on_close_pressed()

func _format_node_button_text(node_state: Dictionary, selected: bool = false) -> String:
	var node_id := String(node_state.get("id", ""))
	var visible := bool(node_state.get("visible", false))
	var unlocked := bool(node_state.get("unlocked", false))
	var permanent_lock := bool(node_state.get("permanent_lock", false))
	var title := String(node_state.get("title", node_id))
	var display_title := title if visible or unlocked or permanent_lock else "???"
	var state_label := NODE_STATE_HIDDEN
	if unlocked:
		state_label = NODE_STATE_UNLOCKED
	elif visible:
		state_label = NODE_STATE_VISIBLE
	elif permanent_lock:
		state_label = "future lock"
	var prefix := "> " if selected else ""
	return "%s%s  [%s]" % [prefix, display_title, state_label]

func _style_node_button(button: Button, node_state: Dictionary) -> void:
	var visible := bool(node_state.get("visible", false))
	var unlocked := bool(node_state.get("unlocked", false))
	var permanent_lock := bool(node_state.get("permanent_lock", false))
	var fill := Color(0.18, 0.14, 0.1, 0.96)
	var border := Color(0.49, 0.38, 0.24)
	if unlocked:
		fill = Color(0.13, 0.2, 0.12, 0.96)
		border = Color(0.39, 0.62, 0.34)
	elif visible:
		fill = Color(0.2, 0.16, 0.09, 0.96)
		border = Color(0.74, 0.58, 0.28)
	elif permanent_lock:
		fill = Color(0.14, 0.12, 0.16, 0.96)
		border = Color(0.44, 0.36, 0.2)
	button.add_theme_stylebox_override("normal", _make_button_style(fill, border))
	button.add_theme_stylebox_override("hover", _make_button_style(fill.lightened(0.08), border.lightened(0.08)))
	button.add_theme_stylebox_override("pressed", _make_button_style(fill.darkened(0.08), border.lightened(0.08)))
	button.add_theme_stylebox_override("focus", _make_button_style(fill.lightened(0.12), border.lightened(0.12)))
	button.add_theme_color_override("font_color", Color(0.95, 0.92, 0.86) if unlocked else Color(0.92, 0.86, 0.74) if visible else Color(0.72, 0.72, 0.76))
	button.add_theme_color_override("font_hover_color", Color(1.0, 0.96, 0.9))
	button.add_theme_color_override("font_pressed_color", Color(0.99, 0.96, 0.86))
	button.add_theme_font_size_override("font_size", 15)

func _get_state_text(node_state: Dictionary) -> String:
	var visible := bool(node_state.get("visible", false))
	var unlocked := bool(node_state.get("unlocked", false))
	var permanent_lock := bool(node_state.get("permanent_lock", false))
	if unlocked:
		return "Status: Unlocked"
	if permanent_lock:
		return "Status: Locked for future content"
	if visible:
		return "Status: Visible but locked"
	return "Status: Hidden"

func _get_requirement_text(node_state: Dictionary) -> String:
	var prerequisites := Array(node_state.get("prerequisites", []))
	if prerequisites.is_empty():
		return "Prerequisites: none"
	return "Prerequisites: %s" % ", ".join(prerequisites)

func _get_node_details_text(node_state: Dictionary) -> String:
	var visible := bool(node_state.get("visible", false))
	var unlocked := bool(node_state.get("unlocked", false))
	var permanent_lock := bool(node_state.get("permanent_lock", false))
	var station_unlock := String(node_state.get("station_unlock", ""))
	var title := String(node_state.get("title", ""))
	if unlocked:
		if not station_unlock.is_empty():
			return "%s is active and has already unlocked the %s station." % [title, _pretty_station_name(station_unlock)]
		return "%s is already unlocked." % title
	if permanent_lock:
		return "This node is reserved for future endgame progression. It stays visible as a goal, but it cannot be bought yet."
	if visible:
		if not station_unlock.is_empty():
			return "Unlocking this node will activate the %s station in the hub." % _pretty_station_name(station_unlock)
		return "This visible node can be unlocked once its requirements and cost are met."
	return "This branch is still hidden. Unlock nearby nodes to reveal it."

func _can_attempt_unlock(node_state: Dictionary) -> bool:
	if bool(node_state.get("unlocked", false)):
		return false
	if bool(node_state.get("permanent_lock", false)):
		return false
	if not bool(node_state.get("visible", false)):
		return false
	return MetaProgression.can_unlock_node(String(node_state.get("id", "")))

func _get_unlock_failure_reason(node_state: Dictionary) -> String:
	if bool(node_state.get("unlocked", false)):
		return "This node is already unlocked."
	if bool(node_state.get("permanent_lock", false)):
		return "This node is locked until the endgame path is built."
	if not bool(node_state.get("visible", false)):
		return "This node is still hidden. Unlock nearby nodes first."
	for prerequisite in Array(node_state.get("prerequisites", [])):
		if not MetaProgression.is_node_unlocked(String(prerequisite)):
			return "Missing prerequisite: %s" % String(prerequisite)
	var cost := int(node_state.get("cost", 0))
	var currency := MetaProgression.get_war_table_currency()
	if currency < cost:
		return "Need %d more War Table currency." % (cost - currency)
	return "The War Table rejected that unlock."

func _pretty_station_name(station_id: String) -> String:
	match station_id:
		MetaProgression.STATION_DRILL_HALL:
			return "Drill Hall"
		MetaProgression.STATION_WAR_TABLE:
			return "War Table"
		_:
			return station_id.capitalize()

func _make_panel_style(fill_color: Color, border_color: Color) -> StyleBoxFlat:
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

func _make_button_style(fill_color: Color, border_color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill_color
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = border_color
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style
