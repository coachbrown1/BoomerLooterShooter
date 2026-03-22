@tool
extends VBoxContainer

const DUNGEON_SCENE_PATH := "res://Scenes/World/dungeon.tscn"
const DEFAULT_DUNGEON_CONTENT_PATH := "res://Data/dungeons/default_dungeon_content.tres"
const DUNGEON_MANAGER_SCRIPT_PATH := "res://Scripts/Dungeon/dungeon_manager.gd"
const HANDCRAFTED_DIR_PATH := "res://Scenes/Dungeon/Handcrafted"
const DEFAULT_START_TEMPLATE_SCENE_PATH := "res://Scenes/Dungeon/Handcrafted/Castle_Start.tscn"
const DEFAULT_ROOM_TEMPLATE_SCENE_PATH := "res://Scenes/Dungeon/Rooms/castle_default_room.tscn"
const HANDCRAFTED_LAYOUT_SCRIPT_PATH := "res://Scripts/Dungeon/handcrafted_room_layout.gd"
const HANDCRAFTED_ENEMY_SPAWNER_SCRIPT_PATH := "res://Scripts/Dungeon/handcrafted_enemy_spawner.gd"
const HANDCRAFTED_PLAYTEST_SCENE_PATH := "res://Scenes/World/handcrafted_room_playtest.tscn"
const HANDCRAFTED_PLAYTEST_CONFIG_DIR := "res://.tmp"
const HANDCRAFTED_PLAYTEST_CONFIG_PATH := "res://.tmp/handcrafted_room_playtest.cfg"
const CONTENT_TAB_INDEX := 1
const HANDCRAFTED_TAB_INDEX := 2
const STATUS_LOG_SIZE := 3

enum WizardRoomType {
	START_TEMPLATE,
	DEFAULT_TEMPLATE,
	SPECIAL_TEMPLATE,
}

enum WizardRegisterTarget {
	NONE,
	START_ROOM,
	DEFAULT_ROOM,
	SPECIAL_ROOM_POOL,
}

var plugin: EditorPlugin = null

# Status log
var _status_log: VBoxContainer
var _status_lines: Array[Label] = []
var _status_colors: Array[Color] = []

# Core layout
var _tabs: TabContainer
var _manager_inspector: EditorInspector

# Content tab
var _content_editor_scroll: ScrollContainer
var _content_editor_root: VBoxContainer

# Layout tab spinboxes
var _grid_min_spin: SpinBox
var _grid_max_spin: SpinBox
var _seed_spin: SpinBox
var _preview_room_selector: OptionButton

# Handcrafted tab
var _wizard_name_edit: LineEdit
var _wizard_room_type_selector: OptionButton
var _wizard_register_selector: OptionButton
var _playtest_room_selector: OptionButton
var _content_pool_toggle_button: Button
var _content_pool_status_label: Label

# Data
var _content_resource: Resource = null
var _preview_targets: Array = []

# Scene option lists (populated by _refresh_option_lists, used as Callables in pickers)
var _scene_options: Array[String] = []
var _enemy_scene_options: Array[String] = []
var _room_scene_options: Array[String] = []
var _corridor_scene_options: Array[String] = []
var _door_scene_options: Array[String] = []


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	if not Engine.is_editor_hint():
		return
	_build_ui()
	_refresh_all()

func _notification(what: int) -> void:
	if not Engine.is_editor_hint():
		return
	if what == NOTIFICATION_VISIBILITY_CHANGED and is_visible_in_tree():
		if _content_resource != null:
			_refresh_option_lists()
			_rebuild_content_editor()

func _on_tab_changed(tab_index: int) -> void:
	if tab_index == CONTENT_TAB_INDEX:
		_refresh_option_lists()
		_rebuild_content_editor()
	elif tab_index == HANDCRAFTED_TAB_INDEX:
		_refresh_option_lists()
		_refresh_room_selector()
		_sync_wizard_name_placeholder()
		_refresh_content_pool_controls()


# ---------------------------------------------------------------------------
# Top-level UI build
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	for child in get_children():
		child.queue_free()
	_status_lines.clear()
	_status_colors.clear()

	size_flags_vertical = Control.SIZE_EXPAND_FILL
	size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var title := Label.new()
	title.text = "Dungeon Designer"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(0.88, 0.94, 1.0, 1.0))
	add_child(title)

	_build_status_bar()

	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tabs.tab_changed.connect(_on_tab_changed)
	add_child(_tabs)

	_build_layout_tab()
	_build_content_tab()
	_build_handcrafted_tab()

func _build_status_bar() -> void:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 6)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_right", 6)
	margin.add_theme_constant_override("margin_bottom", 4)
	panel.add_child(margin)
	_status_log = VBoxContainer.new()
	_status_log.add_theme_constant_override("separation", 1)
	margin.add_child(_status_log)
	for _i in STATUS_LOG_SIZE:
		var lbl := Label.new()
		lbl.text = ""
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lbl.add_theme_font_size_override("font_size", 11)
		_status_log.add_child(lbl)
		_status_lines.append(lbl)
		_status_colors.append(Color(0.85, 0.95, 0.85, 1.0))
	add_child(panel)


# ---------------------------------------------------------------------------
# Tab: Dungeon Layout
# ---------------------------------------------------------------------------

func _build_layout_tab() -> void:
	var tab := VBoxContainer.new()
	tab.name = "Dungeon Layout"
	tab.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.add_child(tab)

	var actions := HFlowContainer.new()
	actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(_make_button("Open Dungeon Scene", _on_open_dungeon_scene_pressed))
	actions.add_child(_make_button("Save Open Scene", _on_save_scene_pressed))
	tab.add_child(actions)

	# Quick Layout
	var layout_section := _make_panel_section("Quick Layout", tab)
	var grid := GridContainer.new()
	grid.columns = 2
	layout_section.add_child(grid)
	_grid_min_spin = _add_spin_row(grid, "Grid Size Min", 2, 100, 1)
	_grid_max_spin = _add_spin_row(grid, "Grid Size Max", 2, 100, 1)
	_seed_spin = _add_spin_row(grid, "Generation Seed (0=random)", 0, 2147483647, 1)
	var layout_actions := HFlowContainer.new()
	layout_actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout_actions.add_child(_make_button("Load From Scene", _on_load_layout_pressed))
	layout_actions.add_child(_make_button("Apply + Save Layout", _on_apply_layout_pressed))
	layout_section.add_child(layout_actions)

	# Preview Generation
	var preview_section := _make_panel_section("Preview Generation", tab)
	var preview_hint := Label.new()
	preview_hint.text = "Builds the dungeon in-editor so you can inspect room placement before pressing Play."
	preview_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	preview_hint.add_theme_font_size_override("font_size", 11)
	preview_section.add_child(preview_hint)
	var preview_actions := HFlowContainer.new()
	preview_actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_actions.add_child(_make_button("Create Preview", _on_create_preview_pressed))
	preview_actions.add_child(_make_button("Clear Preview", _on_clear_preview_pressed))
	preview_section.add_child(preview_actions)

	# Preview Room Jump (own section)
	var jump_section := _make_panel_section("Preview Room Jump", tab)
	var jump_hint := Label.new()
	jump_hint.text = "Navigate the editor camera to START, EXIT, or handcrafted rooms in a generated preview."
	jump_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	jump_hint.add_theme_font_size_override("font_size", 11)
	jump_section.add_child(jump_hint)
	_preview_room_selector = OptionButton.new()
	_preview_room_selector.fit_to_longest_item = false
	_preview_room_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	jump_section.add_child(_preview_room_selector)
	var jump_actions := HFlowContainer.new()
	jump_actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	jump_actions.add_child(_make_button("Refresh Rooms", _on_refresh_preview_rooms_pressed))
	jump_actions.add_child(_make_button("Go To Room", _on_go_to_preview_room_pressed))
	jump_section.add_child(jump_actions)

	# Layout Inspector
	var inspector_header := Label.new()
	inspector_header.text = "LAYOUT INSPECTOR — All DungeonManager Fields"
	inspector_header.add_theme_font_size_override("font_size", 12)
	inspector_header.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0, 1.0))
	tab.add_child(inspector_header)
	var inspector_sep := HSeparator.new()
	tab.add_child(inspector_sep)
	_manager_inspector = EditorInspector.new()
	_manager_inspector.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tab.add_child(_manager_inspector)


# ---------------------------------------------------------------------------
# Tab: Dungeon Content
# ---------------------------------------------------------------------------

func _build_content_tab() -> void:
	var tab := VBoxContainer.new()
	tab.name = "Dungeon Content"
	tab.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.add_child(tab)

	var actions := HFlowContainer.new()
	actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(_make_button("Refresh", _on_refresh_pressed))
	actions.add_child(_make_button("Save Dungeon Content", _on_save_content_pressed))
	actions.add_child(_make_button("Open Content Resource", _on_open_content_resource_pressed))
	tab.add_child(actions)

	_content_editor_scroll = ScrollContainer.new()
	_content_editor_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content_editor_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab.add_child(_content_editor_scroll)

	_content_editor_root = VBoxContainer.new()
	_content_editor_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content_editor_scroll.add_child(_content_editor_root)


# ---------------------------------------------------------------------------
# Tab: Handcrafted Rooms
# ---------------------------------------------------------------------------

func _build_handcrafted_tab() -> void:
	var tab := VBoxContainer.new()
	tab.name = "Handcrafted Rooms"
	tab.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.add_child(tab)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab.add_child(scroll)

	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(root)

	_build_room_wizard_section(root)
	_build_room_playtest_section(root)
	_build_content_pool_section(root)

func _build_room_wizard_section(parent: Control) -> void:
	var section := _make_panel_section("Room Wizard", parent)

	var subtitle := Label.new()
	subtitle.text = "Create an authored room from the active dungeon templates, optionally register it in the dungeon content, then open it."
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle.add_theme_font_size_override("font_size", 11)
	section.add_child(subtitle)

	var grid := GridContainer.new()
	grid.columns = 2
	section.add_child(grid)

	var name_label := Label.new()
	name_label.text = "Scene Name"
	grid.add_child(name_label)
	_wizard_name_edit = LineEdit.new()
	_wizard_name_edit.placeholder_text = "Castle_GuardHall"
	_wizard_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(_wizard_name_edit)

	var type_label := Label.new()
	type_label.text = "Base Type"
	grid.add_child(type_label)
	_wizard_room_type_selector = OptionButton.new()
	_wizard_room_type_selector.add_item("Start Room Template", WizardRoomType.START_TEMPLATE)
	_wizard_room_type_selector.add_item("Default Room Template", WizardRoomType.DEFAULT_TEMPLATE)
	_wizard_room_type_selector.add_item("Special Room Template", WizardRoomType.SPECIAL_TEMPLATE)
	_wizard_room_type_selector.item_selected.connect(_on_wizard_room_type_selected)
	grid.add_child(_wizard_room_type_selector)

	var register_label := Label.new()
	register_label.text = "Register In Content"
	grid.add_child(register_label)
	_wizard_register_selector = OptionButton.new()
	_populate_wizard_register_options(WizardRoomType.START_TEMPLATE)
	grid.add_child(_wizard_register_selector)

	var actions := HFlowContainer.new()
	actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(_make_button("Create Handcrafted Room", _on_create_handcrafted_room_pressed))
	section.add_child(actions)

func _build_room_playtest_section(parent: Control) -> void:
	var section := _make_panel_section("Room Playtest", parent)

	var subtitle := Label.new()
	subtitle.text = "Pick a room from the list or open one in the editor, then launch the single-room playtest harness."
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle.add_theme_font_size_override("font_size", 11)
	section.add_child(subtitle)

	_playtest_room_selector = OptionButton.new()
	_playtest_room_selector.fit_to_longest_item = false
	_playtest_room_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_playtest_room_selector.item_selected.connect(func(_idx: int) -> void:
		_refresh_content_pool_controls()
	)
	section.add_child(_playtest_room_selector)

	var actions := HFlowContainer.new()
	actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(_make_button("Refresh Room List", _on_refresh_room_list_pressed))
	actions.add_child(_make_button("Open Selected Room", _on_open_selected_room_pressed))
	actions.add_child(_make_button("Playtest Selected Room", _on_playtest_selected_room_pressed))
	section.add_child(actions)

func _build_content_pool_section(parent: Control) -> void:
	var section := _make_panel_section("Content Pool", parent)

	var subtitle := Label.new()
	subtitle.text = "Toggle the selected (or currently open) room in the active special room pool."
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle.add_theme_font_size_override("font_size", 11)
	section.add_child(subtitle)

	_content_pool_status_label = Label.new()
	_content_pool_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content_pool_status_label.add_theme_font_size_override("font_size", 11)
	section.add_child(_content_pool_status_label)

	var actions := HFlowContainer.new()
	actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content_pool_toggle_button = _make_button("Add To Special Room Pool", _on_toggle_selected_room_in_pool_pressed)
	actions.add_child(_content_pool_toggle_button)
	section.add_child(actions)

	_refresh_content_pool_controls()


# ---------------------------------------------------------------------------
# UI Helpers
# ---------------------------------------------------------------------------

func _make_button(text: String, callable: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(callable)
	return button

## Creates a styled panel section with a colored title header and separator.
## Adds the panel to [parent] and returns the VBoxContainer to add children to.
func _make_panel_section(title: String, parent: Control) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)
	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(root)
	var title_lbl := Label.new()
	title_lbl.text = title.to_upper()
	title_lbl.add_theme_font_size_override("font_size", 12)
	title_lbl.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0, 1.0))
	root.add_child(title_lbl)
	root.add_child(HSeparator.new())
	parent.add_child(panel)
	return root

## Like _make_panel_section but adds to _content_editor_root (the scroll area).
func _make_content_section(title: String) -> VBoxContainer:
	return _make_panel_section(title, _content_editor_root)

func _add_spin_row(container: GridContainer, label_text: String, min_value: int, max_value: int, step_value: int) -> SpinBox:
	var label := Label.new()
	label.text = label_text
	container.add_child(label)
	var spin := SpinBox.new()
	spin.min_value = min_value
	spin.max_value = max_value
	spin.step = step_value
	spin.rounded = true
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.add_child(spin)
	return spin

func _make_form_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size.x = 130
	label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	return label

## Creates a button that opens a searchable popup backed by options_getter (Callable → Array[String]).
## On popup open the getter is called fresh, so newly scanned files always appear.
func _make_searchable_picker(options_getter: Callable, initial_path: String, on_path_selected: Callable) -> Button:
	var state := {"path": initial_path}
	var btn := Button.new()
	btn.text = initial_path.get_file() if initial_path != "" else "(None)"
	btn.clip_text = true
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.pressed.connect(func() -> void:
		var current_options: Array[String] = options_getter.call()
		_show_search_popup(btn, current_options, state.path, func(path: String) -> void:
			state.path = path
			btn.text = path.get_file() if path != "" else "(None)"
			on_path_selected.call(path)
		)
	)
	return btn

func _show_search_popup(anchor: Control, options: Array[String], current_path: String, on_selected: Callable) -> void:
	var popup := PopupPanel.new()
	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(300, 0)
	popup.add_child(vbox)

	var search := LineEdit.new()
	search.placeholder_text = "Search…"
	vbox.add_child(search)

	var list := ItemList.new()
	list.custom_minimum_size = Vector2(300, 240)
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(list)

	var fill := func(filter: String) -> void:
		list.clear()
		list.add_item("(None)")
		list.set_item_metadata(0, "")
		var sel := 0
		for path in options:
			var fname := path.get_file()
			if filter == "" or fname.to_lower().contains(filter.to_lower()):
				var idx := list.get_item_count()
				list.add_item(fname)
				list.set_item_tooltip(idx, path)
				list.set_item_metadata(idx, path)
				if path == current_path:
					sel = idx
		if list.get_item_count() > 0:
			list.select(sel)
			list.ensure_current_is_visible()
	fill.call("")

	search.text_changed.connect(func(text: String) -> void: fill.call(text))
	list.item_selected.connect(func(idx: int) -> void:
		var path: String = str(list.get_item_metadata(idx))
		on_selected.call(path)
		popup.hide()
	)
	popup.popup_hide.connect(popup.queue_free)

	add_child(popup)
	var screen_pos := anchor.get_screen_position() + Vector2(0.0, anchor.size.y)
	popup.popup(Rect2i(int(screen_pos.x), int(screen_pos.y), 300, 280))
	search.grab_focus()

func _add_bool_row(container: VBoxContainer, label_text: String, property_name: String) -> void:
	var row := HBoxContainer.new()
	var checkbox := CheckBox.new()
	checkbox.text = label_text
	checkbox.button_pressed = bool(_content_resource.get(property_name))
	checkbox.toggled.connect(func(pressed: bool) -> void:
		_set_content_property(property_name, pressed)
	)
	row.add_child(checkbox)
	container.add_child(row)

func _add_float_row(container: VBoxContainer, label_text: String, property_name: String, min_value: float, max_value: float, step: float, integer_only: bool = false) -> void:
	var row := HBoxContainer.new()
	var label := _make_form_label(label_text)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var spin := SpinBox.new()
	spin.min_value = min_value
	spin.max_value = max_value
	spin.step = step
	spin.value = float(_content_resource.get(property_name))
	spin.rounded = integer_only
	spin.custom_minimum_size.x = 80
	spin.size_flags_horizontal = Control.SIZE_SHRINK_END
	spin.value_changed.connect(func(value: float) -> void:
		if integer_only:
			_set_content_property(property_name, int(value))
		else:
			_set_content_property(property_name, value)
	)
	row.add_child(spin)
	container.add_child(row)

func _add_color_row(container: VBoxContainer, label_text: String, property_name: String) -> void:
	var row := HBoxContainer.new()
	var label := _make_form_label(label_text)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var picker := ColorPickerButton.new()
	picker.custom_minimum_size.x = 80
	picker.size_flags_horizontal = Control.SIZE_SHRINK_END
	var current: Variant = _content_resource.get(property_name)
	if current is Color:
		picker.color = current
	picker.color_changed.connect(func(color: Color) -> void:
		_set_content_property(property_name, color)
	)
	row.add_child(picker)
	container.add_child(row)

## options_getter: Callable that returns Array[String]; called fresh each time the popup opens.
func _add_resource_picker_row(container: VBoxContainer, label_text: String, property_name: String, options_getter: Callable, kind: String) -> void:
	var row := HBoxContainer.new()
	var label := _make_form_label(label_text)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)

	var current_path := _resource_path_from_variant(_content_resource.get(property_name))
	var picker := _make_searchable_picker(options_getter, current_path, func(path: String) -> void:
		if path == "":
			_set_content_property(property_name, null)
			return
		var loaded := load(path)
		_set_content_property(property_name, loaded)
	)
	picker.custom_minimum_size.x = 130
	picker.size_flags_horizontal = Control.SIZE_SHRINK_END
	row.add_child(picker)

	var open_button := Button.new()
	open_button.text = "Open"
	open_button.pressed.connect(func() -> void:
		if plugin == null:
			return
		var value: Variant = _content_resource.get(property_name)
		if kind == "scene" and value is PackedScene:
			var packed: PackedScene = value
			if packed.resource_path != "":
				plugin.get_editor_interface().open_scene_from_path(packed.resource_path)
		elif value is Resource:
			plugin.get_editor_interface().edit_resource(value)
	)
	row.add_child(open_button)
	container.add_child(row)

## options_getter: Callable → Array[String]; called fresh each time the popup opens.
func _add_resource_array_editor(container: VBoxContainer, title: String, property_name: String, options_getter: Callable, kind: String) -> void:
	var title_label := Label.new()
	title_label.text = title
	container.add_child(title_label)

	var list := ItemList.new()
	list.select_mode = ItemList.SELECT_SINGLE
	list.custom_minimum_size = Vector2(0, 80)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.add_child(list)

	var refresh := func() -> void:
		list.clear()
		var values := _get_content_array(property_name)
		for value in values:
			if value is Resource:
				var resource: Resource = value
				var path := resource.resource_path
				var display := path.get_file() if path != "" else str(resource)
				var item_idx := list.get_item_count()
				list.add_item(display)
				if path != "":
					list.set_item_tooltip(item_idx, path)
		if list.get_item_count() > 0:
			list.select(0)
	refresh.call()

	# Returns the resource's raw array reference for in-place mutation.
	# Bypasses _set_content_property entirely to avoid typed-array coercion
	# failures when setting Array[PackedScene] back via Object.set().
	var get_arr := func() -> Array:
		if _content_resource == null:
			return []
		var raw: Variant = _content_resource.get(property_name)
		if typeof(raw) != TYPE_ARRAY:
			return []
		return raw

	var mark_changed := func() -> void:
		if _content_resource != null:
			_content_resource.emit_changed()

	# Add row: searchable picker (fresh options on popup open) + Add button
	var add_row := HBoxContainer.new()
	add_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.add_child(add_row)

	var initial_opts: Array[String] = options_getter.call()
	var picker_state := {"path": initial_opts[0] if not initial_opts.is_empty() else ""}
	var picker := _make_searchable_picker(options_getter, picker_state.path, func(path: String) -> void:
		picker_state.path = path
	)
	add_row.add_child(picker)

	var add_button := Button.new()
	add_button.text = "Add"
	add_button.pressed.connect(func() -> void:
		if picker_state.path == "":
			_set_status("Select a scene in the picker before adding.", true)
			return
		var loaded := load(picker_state.path)
		if not (loaded is Resource):
			_set_status("Could not load: %s" % picker_state.path, true)
			return
		var arr := get_arr.call()
		for existing in arr:
			if existing is Resource and str((existing as Resource).resource_path) == picker_state.path:
				_set_status("%s is already in the list." % picker_state.path.get_file(), true)
				return
		arr.append(loaded)
		mark_changed.call()
		refresh.call()
		_set_status("Added %s." % picker_state.path.get_file())
	)
	add_row.add_child(add_button)

	# Action row: Remove | ↑ | ↓ | Open
	var action_row := HBoxContainer.new()
	action_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.add_child(action_row)

	var remove_button := Button.new()
	remove_button.text = "Remove"
	remove_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	remove_button.pressed.connect(func() -> void:
		var selected := list.get_selected_items()
		if selected.is_empty():
			return
		var arr := get_arr.call()
		arr.remove_at(int(selected[0]))
		mark_changed.call()
		refresh.call()
	)
	action_row.add_child(remove_button)

	var up_button := Button.new()
	up_button.text = "↑"
	up_button.pressed.connect(func() -> void:
		var selected := list.get_selected_items()
		if selected.is_empty():
			return
		var idx := int(selected[0])
		if idx <= 0:
			return
		var arr := get_arr.call()
		var tmp: Variant = arr[idx - 1]
		arr[idx - 1] = arr[idx]
		arr[idx] = tmp
		mark_changed.call()
		refresh.call()
		list.select(idx - 1)
	)
	action_row.add_child(up_button)

	var down_button := Button.new()
	down_button.text = "↓"
	down_button.pressed.connect(func() -> void:
		var selected := list.get_selected_items()
		if selected.is_empty():
			return
		var idx := int(selected[0])
		var arr := get_arr.call()
		if idx >= arr.size() - 1:
			return
		var tmp: Variant = arr[idx + 1]
		arr[idx + 1] = arr[idx]
		arr[idx] = tmp
		mark_changed.call()
		refresh.call()
		list.select(idx + 1)
	)
	action_row.add_child(down_button)

	var open_button := Button.new()
	open_button.text = "Open"
	open_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	open_button.pressed.connect(func() -> void:
		if plugin == null:
			return
		var selected := list.get_selected_items()
		if selected.is_empty():
			return
		var values := _get_content_array(property_name)
		var sel_idx := int(selected[0])
		if sel_idx < 0 or sel_idx >= values.size():
			return
		var value: Variant = values[sel_idx]
		if kind == "scene" and value is PackedScene:
			var packed: PackedScene = value
			if packed.resource_path != "":
				plugin.get_editor_interface().open_scene_from_path(packed.resource_path)
		elif value is Resource:
			plugin.get_editor_interface().edit_resource(value)
	)
	action_row.add_child(open_button)

## Shows a ConfirmationDialog; calls on_confirmed if the user accepts.
func _confirm(message: String, on_confirmed: Callable) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.dialog_text = message
	dialog.confirmed.connect(func() -> void:
		on_confirmed.call()
		dialog.queue_free()
	)
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered()


# ---------------------------------------------------------------------------
# Refresh and data loading
# ---------------------------------------------------------------------------

func _refresh_all() -> void:
	_refresh_manager_section()
	_refresh_content_section()
	_refresh_room_selector()
	_refresh_content_pool_controls()

func _refresh_manager_section() -> void:
	var manager := _get_dungeon_manager_from_edited_scene()
	if manager == null:
		_manager_inspector.edit(null)
		_load_layout_from_scene_defaults()
		_clear_preview_target_list()
		_set_status("Open %s to edit layout settings." % DUNGEON_SCENE_PATH)
		return
	_manager_inspector.edit(manager)
	_pull_layout_from_manager(manager)
	_refresh_preview_room_targets(manager)
	_set_status("DungeonManager loaded from edited scene.")

func _refresh_content_section() -> void:
	_content_resource = null
	_rebuild_content_editor()
	_refresh_option_lists()

	_content_resource = load(DEFAULT_DUNGEON_CONTENT_PATH)
	if _content_resource == null:
		_set_status("Could not load dungeon content: %s" % DEFAULT_DUNGEON_CONTENT_PATH, true)
		return
	if not (_content_resource is Resource):
		_set_status("Dungeon content did not load as a Resource.", true)
		_content_resource = null
		return

	_rebuild_content_editor()
	_sync_wizard_name_placeholder()
	_refresh_content_pool_controls()

## Rebuilds the scrollable content editor UI from the loaded _content_resource.
func _rebuild_content_editor() -> void:
	if _content_editor_root == null:
		return
	for child in _content_editor_root.get_children():
		child.queue_free()
	if _content_resource == null:
		var empty := Label.new()
		empty.text = "No dungeon content resource loaded.\nExpected: %s" % DEFAULT_DUNGEON_CONTENT_PATH
		_content_editor_root.add_child(empty)
		return

	var resource_label := Label.new()
	resource_label.text = "Resource: %s" % _content_resource.resource_path.get_file()
	resource_label.add_theme_font_size_override("font_size", 11)
	resource_label.add_theme_color_override("font_color", Color(0.55, 0.65, 0.55, 1.0))
	_content_editor_root.add_child(resource_label)

	var scenes := _make_content_section("Stitched Scenes")
	_add_resource_picker_row(scenes, "Start Room Scene", "start_room_scene", func() -> Array[String]: return _room_scene_options, "scene")
	_add_resource_picker_row(scenes, "Default Room Scene", "default_room_scene", func() -> Array[String]: return _room_scene_options, "scene")
	_add_resource_array_editor(scenes, "Special Room Scenes", "special_room_scenes", func() -> Array[String]: return _room_scene_options, "scene")
	_add_float_row(scenes, "Special Room Chance", "special_room_chance", 0.0, 1.0, 0.01)
	_add_resource_picker_row(scenes, "Corridor Scene", "corridor_scene", func() -> Array[String]: return _corridor_scene_options, "scene")
	_add_resource_picker_row(scenes, "Doorway Assembly Scene", "doorway_assembly_scene", func() -> Array[String]: return _door_scene_options, "scene")

	var environment := _make_content_section("Environment")
	_add_color_row(environment, "Fog Light Color", "fog_light_color")

	var enemies := _make_content_section("Enemies")
	_add_resource_array_editor(enemies, "Enemy Scenes", "enemy_scenes", func() -> Array[String]: return _enemy_scene_options, "scene")

	var validation := _make_content_section("Validation")
	validation.add_child(_make_button("Validate Dungeon Content", _validate_content))

## Populates all scene option arrays using EditorFileSystem (fast, cached),
## falling back to DirAccess if EditorFileSystem is not available.
func _refresh_option_lists() -> void:
	_scene_options = _collect_files_from_dir("res://Scenes", ["tscn"])

	_enemy_scene_options = []
	_room_scene_options = []
	_corridor_scene_options = []
	_door_scene_options = []

	for path in _scene_options:
		if path.begins_with("res://Scenes/Enemies/"):
			var name := path.get_file()
			if name != "enemy_chaser.tscn" and name != "enemy_melee.tscn" and name != "enemy_ranged.tscn":
				_enemy_scene_options.append(path)
		if path.begins_with("res://Scenes/Dungeon/Handcrafted/") or path.begins_with("res://Scenes/Dungeon/Rooms/"):
			_room_scene_options.append(path)
		if path.begins_with("res://Scenes/Dungeon/Corridors/"):
			_corridor_scene_options.append(path)
		if path.find("door") != -1:
			_door_scene_options.append(path)

## Updates the playtest room selector dropdown with directory-prefixed labels
## so Handcrafted/ and Rooms/ entries are easy to distinguish.
func _refresh_room_selector() -> void:
	if _playtest_room_selector == null:
		return
	_playtest_room_selector.clear()
	for path in _room_scene_options:
		var rel := path.trim_prefix("res://Scenes/Dungeon/").get_basename()
		_playtest_room_selector.add_item(rel)

	# Auto-select the currently edited room if applicable
	var selected_path := _get_edited_room_path()
	if selected_path == "":
		selected_path = _room_scene_options[0] if not _room_scene_options.is_empty() else ""
	for index in range(_room_scene_options.size()):
		if _room_scene_options[index] == selected_path:
			_playtest_room_selector.select(index)
			break

func _refresh_content_pool_controls() -> void:
	if _content_pool_toggle_button == null or _content_pool_status_label == null:
		return
	var room_scene_path := _get_selected_room_path()
	if _content_resource == null:
		_content_pool_toggle_button.disabled = true
		_content_pool_toggle_button.text = "Add To Special Room Pool"
		_content_pool_status_label.text = "No dungeon content resource is loaded."
		return
	if room_scene_path == "":
		_content_pool_toggle_button.disabled = true
		_content_pool_toggle_button.text = "Add To Special Room Pool"
		_content_pool_status_label.text = "Open a room scene or pick one from the list."
		return

	var in_pool := _is_scene_in_content_array("special_room_scenes", room_scene_path)
	_content_pool_toggle_button.disabled = false
	_content_pool_toggle_button.text = "Remove From Special Room Pool" if in_pool else "Add To Special Room Pool"
	_content_pool_status_label.text = "%s is %s the active special room pool." % [
		room_scene_path.get_file(), "in" if in_pool else "not in"
	]


# ---------------------------------------------------------------------------
# Room path helpers
# ---------------------------------------------------------------------------

## Returns the path of the currently edited scene IF it is a room scene.
func _get_edited_room_path() -> String:
	if plugin == null:
		return ""
	var root := plugin.get_editor_interface().get_edited_scene_root()
	if root == null:
		return ""
	var scene_path := String(root.scene_file_path)
	if scene_path.begins_with("%s/" % HANDCRAFTED_DIR_PATH) or scene_path.begins_with("res://Scenes/Dungeon/Rooms/"):
		return scene_path
	return ""

## Returns the path from the dropdown list. Used exclusively by "Open Selected Room"
## so that the button always respects what the user explicitly selected.
func _get_dropdown_room_path() -> String:
	if _playtest_room_selector == null:
		return ""
	var index := _playtest_room_selector.selected
	if index < 0 or index >= _room_scene_options.size():
		return ""
	return _room_scene_options[index]

## Returns the best available room path: edited scene first, then dropdown.
## Used by Playtest and Content Pool which should auto-detect the open room.
func _get_selected_room_path() -> String:
	var edited := _get_edited_room_path()
	if edited != "":
		return edited
	return _get_dropdown_room_path()

func _get_selected_room_scene() -> PackedScene:
	var scene_path := _get_selected_room_path()
	if scene_path == "":
		return null
	var loaded := load(scene_path)
	if loaded is PackedScene:
		return loaded as PackedScene
	return null


# ---------------------------------------------------------------------------
# Button handlers: Layout tab
# ---------------------------------------------------------------------------

func _on_open_dungeon_scene_pressed() -> void:
	if plugin == null:
		return
	plugin.get_editor_interface().open_scene_from_path(DUNGEON_SCENE_PATH)
	await get_tree().process_frame
	_refresh_manager_section()

func _on_save_scene_pressed() -> void:
	if plugin == null:
		return
	var err := plugin.get_editor_interface().save_scene()
	if err == OK:
		_set_status("Saved edited scene.")
	else:
		_set_status("Save scene failed with error %d." % err, true)

func _on_load_layout_pressed() -> void:
	_refresh_manager_section()

func _on_apply_layout_pressed() -> void:
	if plugin == null:
		return
	var manager := await _ensure_open_manager()
	if manager == null:
		_set_status("Could not load DungeonManager from scene.", true)
		return
	_push_layout_to_manager(manager)
	var err := plugin.get_editor_interface().save_scene()
	if err == OK:
		_set_status("Applied layout values and saved %s." % DUNGEON_SCENE_PATH)
	else:
		_set_status("Apply succeeded but save failed with error %d." % err, true)

func _on_create_preview_pressed() -> void:
	if plugin == null:
		return
	var manager := await _ensure_open_manager()
	if manager == null:
		_set_status("Could not load DungeonManager from scene.", true)
		return

	_push_layout_to_manager(manager)

	var seed := int(manager.get("generation_seed"))
	if seed == 0:
		seed = int(Time.get_unix_time_from_system()) ^ int(Time.get_ticks_usec() & 0x7fffffff)
		if seed == 0:
			seed = 1
		manager.set("generation_seed", seed)
		_seed_spin.value = seed

	var err := plugin.get_editor_interface().save_scene()
	if err != OK:
		_set_status("Could not save the scene before preview generation (error %d)." % err, true)
		return

	manager = await _ensure_open_manager()
	if manager == null:
		_set_status("Could not reload DungeonManager after saving.", true)
		return

	manager.call("generate_floor", int(manager.get("floor_number")), true)
	await get_tree().process_frame

	_refresh_preview_room_targets(manager)
	_set_status("Preview generated with seed %d. Press Play to run this exact layout." % seed)

func _on_clear_preview_pressed() -> void:
	if plugin == null:
		return
	var manager := await _ensure_open_manager()
	if manager == null:
		_set_status("Could not load DungeonManager from scene.", true)
		return

	if manager.has_method("clear_editor_preview"):
		manager.call("clear_editor_preview")
	else:
		var nav_region: Node = manager.get_node_or_null("NavigationRegion3D")
		if nav_region != null:
			for child in nav_region.get_children():
				child.queue_free()

	await get_tree().process_frame
	_clear_preview_target_list()
	_set_status("Preview cleared from editor scene.")

func _on_refresh_preview_rooms_pressed() -> void:
	var manager := _get_dungeon_manager_from_edited_scene()
	_refresh_preview_room_targets(manager)
	if _preview_targets.is_empty():
		_set_status("No preview room targets found. Generate a preview first.", true)
	else:
		_set_status("Loaded %d preview room targets." % _preview_targets.size())

func _on_go_to_preview_room_pressed() -> void:
	if _preview_targets.is_empty():
		_set_status("No preview room targets. Generate a preview first.", true)
		return
	var index := _preview_room_selector.selected
	if index < 0 or index >= _preview_targets.size():
		_set_status("Select a room target first.", true)
		return

	var target: Dictionary = _preview_targets[index]
	var world_position_variant: Variant = target.get("world_position", Vector3.ZERO)
	if typeof(world_position_variant) != TYPE_VECTOR3:
		_set_status("Selected room target is missing a valid world position.", true)
		return
	var world_position: Vector3 = world_position_variant

	_move_player_to(world_position)
	_move_preview_marker(world_position)
	var focused := _focus_editor_camera(world_position)
	var label := str(target.get("label", "Room"))
	if focused:
		_set_status("Moved to %s." % label)
	else:
		_set_status("Moved marker/player to %s. Frame manually if needed." % label)

func _on_refresh_pressed() -> void:
	_refresh_all()


# ---------------------------------------------------------------------------
# Button handlers: Content tab
# ---------------------------------------------------------------------------

func _on_save_content_pressed() -> void:
	if _content_resource == null:
		_set_status("No dungeon content loaded.", true)
		return
	var path := str(_content_resource.resource_path)
	if path == "":
		_set_status("Dungeon content has no resource path.", true)
		return
	var err := ResourceSaver.save(_content_resource, path)
	if err == OK:
		_set_status("Saved dungeon content: %s" % path)
	else:
		_set_status("Save failed with error %d." % err, true)

func _on_open_content_resource_pressed() -> void:
	if plugin == null or _content_resource == null:
		return
	plugin.get_editor_interface().edit_resource(_content_resource)
	_set_status("Opened dungeon content resource in inspector.")


# ---------------------------------------------------------------------------
# Button handlers: Handcrafted tab
# ---------------------------------------------------------------------------

func _on_refresh_room_list_pressed() -> void:
	_refresh_option_lists()
	_refresh_room_selector()
	_refresh_content_pool_controls()
	if _playtest_room_selector == null or _playtest_room_selector.item_count == 0:
		_set_status("No dungeon room scenes found.", true)
	else:
		_set_status("Loaded %d dungeon room scenes." % _playtest_room_selector.item_count)

## Opens exactly what is selected in the dropdown — never the currently edited scene.
func _on_open_selected_room_pressed() -> void:
	if plugin == null:
		return
	var scene_path := _get_dropdown_room_path()
	if scene_path == "":
		_set_status("Select a room from the list first.", true)
		return
	plugin.get_editor_interface().open_scene_from_path(scene_path)
	await get_tree().process_frame
	_refresh_content_pool_controls()
	_set_status("Opened: %s" % scene_path.get_file())

func _on_playtest_selected_room_pressed() -> void:
	if plugin == null:
		return
	var room_scene_path := _get_selected_room_path()
	if room_scene_path == "":
		_set_status("Select a dungeon room scene first.", true)
		return
	if not _write_playtest_config(room_scene_path):
		return
	var current_root := plugin.get_editor_interface().get_edited_scene_root()
	if current_root != null and String(current_root.scene_file_path) == room_scene_path:
		var save_err := plugin.get_editor_interface().save_scene()
		if save_err != OK:
			_set_status("Saved playtest config, but could not save the current room scene (error %d)." % save_err, true)
			return
	if plugin.get_editor_interface().has_method("play_custom_scene"):
		plugin.get_editor_interface().play_custom_scene(HANDCRAFTED_PLAYTEST_SCENE_PATH)
		_set_status("Launching playtest for %s." % room_scene_path.get_file())
	else:
		plugin.get_editor_interface().open_scene_from_path(HANDCRAFTED_PLAYTEST_SCENE_PATH)
		_set_status("play_custom_scene unavailable; opened the playtest scene instead.")

func _on_toggle_selected_room_in_pool_pressed() -> void:
	if _content_resource == null:
		_set_status("No dungeon content loaded.", true)
		_refresh_content_pool_controls()
		return
	var room_scene := _get_selected_room_scene()
	if room_scene == null:
		_set_status("Select or open a dungeon room scene first.", true)
		_refresh_content_pool_controls()
		return
	if not _has_property(_content_resource, "special_room_scenes"):
		_set_status("Dungeon content does not expose special_room_scenes.", true)
		_refresh_content_pool_controls()
		return

	var scene_path := str(room_scene.resource_path)
	if _is_scene_in_content_array("special_room_scenes", scene_path):
		_confirm("Remove %s from the special room pool?" % scene_path.get_file(), func() -> void:
			_do_remove_from_pool(scene_path)
		)
	else:
		_do_add_to_pool(room_scene)

func _do_add_to_pool(room_scene: PackedScene) -> void:
	if not _append_to_content_array("special_room_scenes", room_scene):
		_set_status("Could not add room to special room pool.", true)
		_refresh_content_pool_controls()
		return
	var save_err := _save_content_resource()
	_refresh_content_pool_controls()
	if save_err != OK:
		_set_status("Updated special room pool in memory, but save failed with error %d." % save_err, true)
		return
	_set_status("%s added to the active special room pool." % str(room_scene.resource_path).get_file())

func _do_remove_from_pool(scene_path: String) -> void:
	if not _remove_from_content_array("special_room_scenes", scene_path):
		_set_status("Could not remove room from special room pool.", true)
		_refresh_content_pool_controls()
		return
	var save_err := _save_content_resource()
	_refresh_content_pool_controls()
	if save_err != OK:
		_set_status("Updated special room pool in memory, but save failed with error %d." % save_err, true)
		return
	_set_status("%s removed from the active special room pool." % scene_path.get_file())


# ---------------------------------------------------------------------------
# Handcrafted Room Wizard
# ---------------------------------------------------------------------------

func _on_wizard_room_type_selected(index: int) -> void:
	if _wizard_room_type_selector == null:
		return
	var room_type := _wizard_room_type_selector.get_item_id(index)
	_populate_wizard_register_options(room_type)
	_sync_wizard_name_placeholder()

func _populate_wizard_register_options(room_type: int) -> void:
	if _wizard_register_selector == null:
		return
	_wizard_register_selector.clear()
	_wizard_register_selector.add_item("Do Not Register", WizardRegisterTarget.NONE)
	match room_type:
		WizardRoomType.START_TEMPLATE:
			_wizard_register_selector.add_item("Set As Start Room", WizardRegisterTarget.START_ROOM)
		WizardRoomType.SPECIAL_TEMPLATE:
			_wizard_register_selector.add_item("Add To Special Room Pool", WizardRegisterTarget.SPECIAL_ROOM_POOL)
		_:
			_wizard_register_selector.add_item("Set As Default Room", WizardRegisterTarget.DEFAULT_ROOM)
	_wizard_register_selector.select(0)

func _sync_wizard_name_placeholder() -> void:
	if _wizard_name_edit == null:
		return
	var prefix := _get_content_name_prefix()
	var room_type := WizardRoomType.DEFAULT_TEMPLATE
	if _wizard_room_type_selector != null and _wizard_room_type_selector.selected >= 0:
		room_type = _wizard_room_type_selector.get_item_id(_wizard_room_type_selector.selected)
	match room_type:
		WizardRoomType.START_TEMPLATE:
			_wizard_name_edit.placeholder_text = "%s_StartRoom" % prefix
		WizardRoomType.SPECIAL_TEMPLATE:
			_wizard_name_edit.placeholder_text = "%s_SpecialRoom" % prefix
		_:
			_wizard_name_edit.placeholder_text = "%s_DefaultRoom" % prefix

## Derives the content name prefix from the start room scene filename (e.g. "Castle" from Castle_Start.tscn).
func _get_content_name_prefix() -> String:
	if _content_resource != null and _has_property(_content_resource, "start_room_scene"):
		var start_variant: Variant = _content_resource.get("start_room_scene")
		if start_variant is PackedScene:
			var fname := (start_variant as PackedScene).resource_path.get_file().get_basename()
			var parts := fname.split("_")
			if parts.size() > 0 and parts[0].length() > 0:
				return parts[0]
	return "Dungeon"

func _on_create_handcrafted_room_pressed() -> void:
	if plugin == null:
		return
	if _wizard_name_edit == null or _wizard_room_type_selector == null or _wizard_register_selector == null:
		_set_status("Handcrafted room wizard is not ready yet.", true)
		return

	var raw_name := _wizard_name_edit.text.strip_edges()
	if raw_name == "":
		raw_name = _wizard_name_edit.placeholder_text.strip_edges()
	if raw_name == "":
		_set_status("Enter a room scene name first.", true)
		return

	var scene_name := _sanitize_scene_name(raw_name)
	if scene_name == "":
		_set_status("Room scene name must contain letters or numbers.", true)
		return

	var register_target := _wizard_register_selector.get_item_id(_wizard_register_selector.selected)

	# Confirm if we would replace an existing slot
	if register_target == WizardRegisterTarget.START_ROOM and _content_resource != null:
		var existing: Variant = _content_resource.get("start_room_scene")
		if existing is PackedScene:
			var existing_name := (existing as PackedScene).resource_path.get_file()
			_confirm("This will replace the current start room (%s). Continue?" % existing_name,
				func() -> void: _do_create_handcrafted_room(scene_name, register_target)
			)
			return
	elif register_target == WizardRegisterTarget.DEFAULT_ROOM and _content_resource != null:
		var existing: Variant = _content_resource.get("default_room_scene")
		if existing is PackedScene:
			var existing_name := (existing as PackedScene).resource_path.get_file()
			_confirm("This will replace the current default room (%s). Continue?" % existing_name,
				func() -> void: _do_create_handcrafted_room(scene_name, register_target)
			)
			return

	_do_create_handcrafted_room(scene_name, register_target)

func _do_create_handcrafted_room(scene_name: String, register_target: int) -> void:
	var room_type := _wizard_room_type_selector.get_item_id(_wizard_room_type_selector.selected)
	var scene_path := _build_unique_handcrafted_scene_path(scene_name)
	var packed_scene := _build_handcrafted_room_scene(scene_name, room_type)
	if packed_scene == null:
		_set_status("Could not build handcrafted room scene.", true)
		return

	var save_err := ResourceSaver.save(packed_scene, scene_path)
	if save_err != OK:
		_set_status("Create handcrafted room failed with error %d." % save_err, true)
		return

	var saved_scene := load(scene_path)
	if not (saved_scene is PackedScene):
		_set_status("Room scene was saved but could not be reloaded: %s" % scene_path, true)
		return

	var register_result := _register_new_handcrafted_scene(saved_scene, register_target)
	_refresh_option_lists()
	_rebuild_content_editor()
	plugin.get_editor_interface().open_scene_from_path(scene_path)
	_wizard_name_edit.text = ""

	if register_result == "":
		_set_status("Created: %s" % scene_path.get_file())
	else:
		_set_status("Created %s — %s" % [scene_path.get_file(), register_result])

func _sanitize_scene_name(value: String) -> String:
	var cleaned := ""
	for chr in value.strip_edges():
		var code := chr.unicode_at(0)
		var is_alpha_num := (code >= 48 and code <= 57) or (code >= 65 and code <= 90) or (code >= 97 and code <= 122)
		if is_alpha_num:
			cleaned += chr
		elif chr == " " or chr == "-" or chr == "." or chr == "/":
			if not cleaned.ends_with("_"):
				cleaned += "_"
		elif chr == "_":
			if not cleaned.ends_with("_"):
				cleaned += "_"
	return cleaned.strip_edges().trim_suffix("_").trim_prefix("_")

func _build_unique_handcrafted_scene_path(scene_name: String) -> String:
	var attempt := 0
	while true:
		var suffix := "" if attempt == 0 else "_%d" % (attempt + 1)
		var candidate := "%s/%s%s.tscn" % [HANDCRAFTED_DIR_PATH, scene_name, suffix]
		if not ResourceLoader.exists(candidate):
			return candidate
		attempt += 1
	return "%s/%s.tscn" % [HANDCRAFTED_DIR_PATH, scene_name]

func _build_handcrafted_room_scene(scene_name: String, room_type: int) -> PackedScene:
	var root := _build_room_scene_from_template(scene_name, room_type)
	if root == null:
		return null
	var packed := PackedScene.new()
	var pack_err := packed.pack(root)
	root.free()
	if pack_err != OK:
		return null
	return packed

func _build_room_scene_from_template(scene_name: String, room_type: int) -> Node3D:
	var template_scene := _get_wizard_template_scene(room_type)
	if template_scene == null:
		return null
	var scene_variant: Variant = template_scene.instantiate()
	if not (scene_variant is Node3D):
		if scene_variant is Node:
			(scene_variant as Node).queue_free()
		return null
	var root: Node3D = scene_variant
	root.name = scene_name
	_apply_wizard_room_metadata(root, room_type)
	return root

func _get_wizard_template_scene(room_type: int) -> PackedScene:
	var scene_variant: Variant = null
	match room_type:
		WizardRoomType.START_TEMPLATE:
			if _content_resource != null and _has_property(_content_resource, "start_room_scene"):
				scene_variant = _content_resource.get("start_room_scene")
			if not (scene_variant is PackedScene):
				scene_variant = load(DEFAULT_START_TEMPLATE_SCENE_PATH)
		WizardRoomType.SPECIAL_TEMPLATE:
			var special_scenes := _get_content_array("special_room_scenes")
			if not special_scenes.is_empty():
				scene_variant = special_scenes[0]
			elif _content_resource != null and _has_property(_content_resource, "default_room_scene"):
				scene_variant = _content_resource.get("default_room_scene")
			if not (scene_variant is PackedScene):
				scene_variant = load(DEFAULT_ROOM_TEMPLATE_SCENE_PATH)
		_:
			if _content_resource != null and _has_property(_content_resource, "default_room_scene"):
				scene_variant = _content_resource.get("default_room_scene")
			if not (scene_variant is PackedScene):
				scene_variant = load(DEFAULT_ROOM_TEMPLATE_SCENE_PATH)
	return scene_variant as PackedScene

func _apply_wizard_room_metadata(root: Node3D, room_type: int) -> void:
	match room_type:
		WizardRoomType.START_TEMPLATE:
			_try_set_room_metadata(root, PackedStringArray(["start"]), PackedStringArray(["south"]), PackedInt32Array([0, 90, 180, 270]))
		WizardRoomType.SPECIAL_TEMPLATE:
			_try_set_room_metadata(root, PackedStringArray(["special"]), PackedStringArray(["south"]), PackedInt32Array([0, 90, 180, 270]))
		_:
			_try_set_room_metadata(root, PackedStringArray(["default"]), PackedStringArray(["*"]), PackedInt32Array([0]))

func _try_set_room_metadata(root: Node3D, role_tags: PackedStringArray, doorway_profiles: PackedStringArray, allowed_rotations: PackedInt32Array) -> void:
	if _has_property(root, "room_role_tags"):
		root.set("room_role_tags", role_tags)
	if _has_property(root, "supported_doorway_profiles"):
		root.set("supported_doorway_profiles", doorway_profiles)
	if _has_property(root, "allowed_rotation_degrees"):
		root.set("allowed_rotation_degrees", allowed_rotations)

func _register_new_handcrafted_scene(scene: PackedScene, register_target: int) -> String:
	if register_target == WizardRegisterTarget.NONE:
		return "Left unregistered."
	if _content_resource == null:
		return "No dungeon content loaded, so it was not registered."

	match register_target:
		WizardRegisterTarget.START_ROOM:
			if not _has_property(_content_resource, "start_room_scene"):
				return "Dungeon content does not expose start_room_scene."
			_content_resource.set("start_room_scene", scene)
		WizardRegisterTarget.DEFAULT_ROOM:
			if not _has_property(_content_resource, "default_room_scene"):
				return "Dungeon content does not expose default_room_scene."
			_content_resource.set("default_room_scene", scene)
		WizardRegisterTarget.SPECIAL_ROOM_POOL:
			if not _append_to_content_array("special_room_scenes", scene):
				return "Dungeon content does not expose special_room_scenes."

	var path := str(_content_resource.resource_path)
	if path == "":
		return "Registered in memory only (resource has no path)."
	var save_err := ResourceSaver.save(_content_resource, path)
	if save_err != OK:
		return "Updated content in memory but save failed with error %d." % save_err
	return "Registered in dungeon content."


# ---------------------------------------------------------------------------
# Content resource helpers
# ---------------------------------------------------------------------------

func _set_content_property(property_name: String, value: Variant) -> void:
	if _content_resource == null:
		return
	_content_resource.set(property_name, value)
	_content_resource.emit_changed()

func _get_content_array(property_name: String) -> Array:
	if _content_resource == null:
		return []
	var raw: Variant = _content_resource.get(property_name)
	if typeof(raw) != TYPE_ARRAY:
		return []
	var values: Array = raw
	var out: Array = []
	for value in values:
		if value is Resource:
			out.append(value)
		elif value is String:
			var loaded := load(str(value))
			if loaded is Resource:
				out.append(loaded)
	return out

func _append_to_content_array(property_name: String, scene: PackedScene) -> bool:
	if not _has_property(_content_resource, property_name):
		return false
	var raw: Variant = _content_resource.get(property_name)
	if typeof(raw) != TYPE_ARRAY:
		return false
	var arr: Array = raw
	for existing in arr:
		if existing is PackedScene and str((existing as PackedScene).resource_path) == str(scene.resource_path):
			return true  # already present, nothing to do
	arr.append(scene)
	_content_resource.emit_changed()
	return true

func _remove_from_content_array(property_name: String, scene_path: String) -> bool:
	if not _has_property(_content_resource, property_name):
		return false
	var raw: Variant = _content_resource.get(property_name)
	if typeof(raw) != TYPE_ARRAY:
		return false
	var arr: Array = raw
	for index in range(arr.size() - 1, -1, -1):
		var existing: Variant = arr[index]
		if existing is PackedScene and str((existing as PackedScene).resource_path) == scene_path:
			arr.remove_at(index)
	_content_resource.emit_changed()
	return true

func _is_scene_in_content_array(property_name: String, scene_path: String) -> bool:
	if scene_path == "":
		return false
	for value in _get_content_array(property_name):
		if value is PackedScene and str((value as PackedScene).resource_path) == scene_path:
			return true
	return false

func _save_content_resource() -> int:
	if _content_resource == null:
		return ERR_UNAVAILABLE
	var path := str(_content_resource.resource_path)
	if path == "":
		return ERR_INVALID_PARAMETER
	return ResourceSaver.save(_content_resource, path)

func _validate_content() -> void:
	if _content_resource == null:
		_set_status("No dungeon content loaded.", true)
		return
	var issues: Array[String] = []
	if _content_resource.get("start_room_scene") == null:
		issues.append("start_room_scene is empty")
	if _content_resource.get("default_room_scene") == null:
		issues.append("default_room_scene is empty")
	if _content_resource.get("corridor_scene") == null:
		issues.append("corridor_scene is empty")
	if _get_content_array("enemy_scenes").is_empty():
		issues.append("enemy_scenes is empty")
	if issues.is_empty():
		_set_status("Dungeon content validation passed.")
	else:
		_set_status("Validation issues: %s" % "; ".join(issues), true)

func _resource_path_from_variant(value: Variant) -> String:
	if value is Resource:
		var resource: Resource = value
		return resource.resource_path
	if value is String:
		return str(value)
	return ""


# ---------------------------------------------------------------------------
# File collection (EditorFileSystem with DirAccess fallback)
# ---------------------------------------------------------------------------

func _collect_files_from_dir(dir_path: String, extensions: Array[String]) -> Array[String]:
	if plugin != null:
		var fs := plugin.get_editor_interface().get_resource_filesystem()
		if fs != null:
			var efs_dir := fs.get_filesystem_path(dir_path)
			if efs_dir != null:
				var out: Array[String] = []
				_collect_from_efs_dir(efs_dir, extensions, out)
				out.sort()
				return out
	return _collect_files_recursive(dir_path, extensions)

func _collect_from_efs_dir(dir: EditorFileSystemDirectory, extensions: Array[String], out: Array[String]) -> void:
	for i in range(dir.get_file_count()):
		var ext := dir.get_file(i).get_extension().to_lower()
		if extensions.has(ext):
			out.append(dir.get_file_path(i))
	for i in range(dir.get_subdir_count()):
		_collect_from_efs_dir(dir.get_subdir(i), extensions, out)

func _collect_files_recursive(root: String, extensions: Array[String]) -> Array[String]:
	var out: Array[String] = []
	_collect_files_recursive_inner(root, extensions, out)
	out.sort()
	return out

func _collect_files_recursive_inner(root: String, extensions: Array[String], out: Array[String]) -> void:
	var dir := DirAccess.open(root)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name != "." and name != "..":
			var full_path := root.path_join(name)
			if dir.current_is_dir():
				_collect_files_recursive_inner(full_path, extensions, out)
			else:
				var ext := name.get_extension().to_lower()
				if extensions.has(ext):
					out.append(full_path)
		name = dir.get_next()
	dir.list_dir_end()


# ---------------------------------------------------------------------------
# Playtest config
# ---------------------------------------------------------------------------

func _write_playtest_config(room_scene_path: String) -> bool:
	var dir_err := DirAccess.make_dir_recursive_absolute(HANDCRAFTED_PLAYTEST_CONFIG_DIR)
	if dir_err != OK and dir_err != ERR_ALREADY_EXISTS:
		_set_status("Could not create playtest config dir (error %d)." % dir_err, true)
		return false
	var cfg := ConfigFile.new()
	cfg.set_value("playtest", "room_scene_path", room_scene_path)
	var save_err := cfg.save(HANDCRAFTED_PLAYTEST_CONFIG_PATH)
	if save_err != OK:
		_set_status("Could not save playtest config (error %d)." % save_err, true)
		return false
	return true


# ---------------------------------------------------------------------------
# DungeonManager helpers
# ---------------------------------------------------------------------------

func _get_dungeon_manager_from_edited_scene() -> Node:
	if plugin == null:
		return null
	var root := plugin.get_editor_interface().get_edited_scene_root()
	if root == null:
		return null
	return _find_node_by_script(root, DUNGEON_MANAGER_SCRIPT_PATH)

func _find_node_by_script(node: Node, script_path: String) -> Node:
	var script := node.get_script()
	if script is Script and str(script.resource_path) == script_path:
		return node
	for child in node.get_children():
		if child is Node:
			var found := _find_node_by_script(child, script_path)
			if found != null:
				return found
	return null

func _load_layout_from_scene_defaults() -> void:
	var scene := load(DUNGEON_SCENE_PATH) as PackedScene
	if scene == null:
		return
	var temp_root := scene.instantiate()
	if temp_root == null:
		return
	var manager := _find_node_by_script(temp_root, DUNGEON_MANAGER_SCRIPT_PATH)
	if manager != null:
		_pull_layout_from_manager(manager)
	temp_root.free()

func _pull_layout_from_manager(manager: Node) -> void:
	if manager == null:
		return
	_grid_min_spin.value = int(manager.get("grid_size_min"))
	_grid_max_spin.value = int(manager.get("grid_size_max"))
	_seed_spin.value = int(manager.get("generation_seed"))

func _push_layout_to_manager(manager: Node) -> void:
	if manager == null:
		return
	var grid_min := int(_grid_min_spin.value)
	var grid_max := int(_grid_max_spin.value)
	if grid_max < grid_min:
		grid_max = grid_min
		_grid_max_spin.value = grid_max
	manager.set("grid_size_min", grid_min)
	manager.set("grid_size_max", grid_max)
	manager.set("generation_seed", int(_seed_spin.value))

func _ensure_open_manager() -> Node:
	var manager := _get_dungeon_manager_from_edited_scene()
	if _manager_supports_editor_preview(manager):
		return manager
	if plugin == null:
		return null
	plugin.get_editor_interface().open_scene_from_path(DUNGEON_SCENE_PATH)
	await get_tree().process_frame
	await get_tree().process_frame
	manager = _get_dungeon_manager_from_edited_scene()
	if _manager_supports_editor_preview(manager):
		return manager
	return null

func _manager_supports_editor_preview(manager: Node) -> bool:
	if manager == null:
		return false
	return manager.has_method("generate_floor") and manager.has_method("clear_editor_preview")

func _refresh_preview_room_targets(manager: Node = null) -> void:
	_clear_preview_target_list()
	if manager == null:
		manager = _get_dungeon_manager_from_edited_scene()
	if manager == null:
		return
	if not manager.has_method("get_editor_preview_room_targets"):
		return
	var targets_variant: Variant = manager.call("get_editor_preview_room_targets")
	if typeof(targets_variant) != TYPE_ARRAY:
		return
	for target_variant in targets_variant:
		if typeof(target_variant) != TYPE_DICTIONARY:
			continue
		var target: Dictionary = target_variant
		_preview_targets.append(target)
		_preview_room_selector.add_item(str(target.get("label", "Room")))
	if not _preview_targets.is_empty():
		_preview_room_selector.select(0)

func _clear_preview_target_list() -> void:
	_preview_targets = []
	if _preview_room_selector != null:
		_preview_room_selector.clear()

func _move_player_to(world_position: Vector3) -> void:
	if plugin == null:
		return
	var root := plugin.get_editor_interface().get_edited_scene_root()
	if root == null:
		return
	var player := root.get_node_or_null("Player")
	if player is Node3D:
		var player_node: Node3D = player
		player_node.global_position = Vector3(world_position.x, 1.0, world_position.z)

func _move_preview_marker(world_position: Vector3) -> void:
	if plugin == null:
		return
	var root := plugin.get_editor_interface().get_edited_scene_root()
	if root == null:
		return
	var marker: Marker3D = root.get_node_or_null("PreviewRoomFocus")
	if marker == null:
		marker = Marker3D.new()
		marker.name = "PreviewRoomFocus"
		root.add_child(marker)
	marker.global_position = world_position + Vector3(0.0, 0.5, 0.0)
	var selection := plugin.get_editor_interface().get_selection()
	if selection != null:
		selection.clear()
		selection.add_node(marker)

func _focus_editor_camera(world_position: Vector3) -> bool:
	if plugin == null:
		return false
	var editor_interface := plugin.get_editor_interface()
	if editor_interface == null:
		return false
	if not editor_interface.has_method("get_editor_viewport_3d"):
		return false
	var viewport: Variant = editor_interface.call("get_editor_viewport_3d", 0)
	if viewport == null:
		return false
	if not viewport.has_method("get_camera_3d"):
		return false
	var camera_variant: Variant = viewport.call("get_camera_3d")
	if not (camera_variant is Camera3D):
		return false
	var camera: Camera3D = camera_variant
	camera.global_position = world_position + Vector3(0.0, 22.0, 18.0)
	camera.look_at(world_position, Vector3.UP)
	return true


# ---------------------------------------------------------------------------
# Status bar
# ---------------------------------------------------------------------------

func _set_status(message: String, is_error: bool = false) -> void:
	if _status_lines.is_empty():
		return
	# Shift existing entries down (oldest falls off the bottom)
	for i in range(STATUS_LOG_SIZE - 1, 0, -1):
		_status_lines[i].text = _status_lines[i - 1].text
		_status_colors[i] = _status_colors[i - 1]
	# New entry at top
	_status_colors[0] = Color(1.0, 0.45, 0.45, 1.0) if is_error else Color(0.85, 0.95, 0.85, 1.0)
	_status_lines[0].text = message
	# Re-apply all colors with progressive dimming for older entries
	for i in range(STATUS_LOG_SIZE):
		var c := _status_colors[i]
		var alpha := 1.0 - i * 0.32
		_status_lines[i].add_theme_color_override("font_color", Color(c.r, c.g, c.b, maxf(alpha, 0.1)))


# ---------------------------------------------------------------------------
# Misc helpers
# ---------------------------------------------------------------------------

func _has_property(target: Object, property_name: String) -> bool:
	if target == null:
		return false
	for property_variant in target.get_property_list():
		if typeof(property_variant) != TYPE_DICTIONARY:
			continue
		var property_dict: Dictionary = property_variant
		if str(property_dict.get("name", "")) == property_name:
			return true
	return false
