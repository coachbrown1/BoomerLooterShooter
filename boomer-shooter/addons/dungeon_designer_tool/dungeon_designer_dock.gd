@tool
extends VBoxContainer

const DUNGEON_SCENE_PATH := "res://Scenes/World/dungeon.tscn"
const BIOME_DB_PATH := "res://Data/biomes/biome_dungeon_database.tres"
const DUNGEON_MANAGER_SCRIPT_PATH := "res://Scripts/Dungeon/dungeon_manager.gd"
const HANDCRAFTED_DIR_PATH := "res://Scenes/Dungeon/Handcrafted"
const HANDCRAFTED_LAYOUT_SCRIPT_PATH := "res://Scripts/Dungeon/handcrafted_room_layout.gd"
const HANDCRAFTED_QUADRANT_SCRIPT_PATH := "res://Scripts/Dungeon/handcrafted_quadrant_composite_room.gd"
const HANDCRAFTED_ENEMY_SPAWNER_SCRIPT_PATH := "res://Scripts/Dungeon/handcrafted_enemy_spawner.gd"
const QUADRANT_TEMPLATE_SCENE_PATH := "res://Scenes/Dungeon/Handcrafted/Castle_Crossroom.tscn"
const BIOME_TAB_INDEX := 1

enum WizardRoomType {
	START_SKELETON,
	NORMAL_SKELETON,
	QUADRANT_COMPOSITE,
}

enum WizardRegisterTarget {
	NONE,
	START_ROOM,
	NORMAL_ROOM_POOL,
	QUADRANT_POOL,
}

var plugin: EditorPlugin = null

var _status_label: Label
var _tabs: TabContainer
var _biome_selector: OptionButton
var _manager_inspector: EditorInspector
var _biome_editor_scroll: ScrollContainer
var _biome_editor_root: VBoxContainer
var _preview_room_selector: OptionButton
var _wizard_name_edit: LineEdit
var _wizard_room_type_selector: OptionButton
var _wizard_register_selector: OptionButton
var _grid_min_spin: SpinBox
var _grid_max_spin: SpinBox
var _room_size_spin: SpinBox
var _corridor_width_spin: SpinBox
var _corridor_length_spin: SpinBox
var _seed_spin: SpinBox

var _biome_db: Resource = null
var _biomes: Array = []
var _selected_biome: Resource = null
var _preview_targets: Array = []
var _texture_options: Array[String] = []
var _scene_options: Array[String] = []
var _enemy_scene_options: Array[String] = []
var _prop_scene_options: Array[String] = []
var _handcrafted_scene_options: Array[String] = []
var _door_scene_options: Array[String] = []
var _light_scene_options: Array[String] = []

func _ready() -> void:
	if not Engine.is_editor_hint():
		return
	_build_ui()
	_refresh_all()

func _notification(what: int) -> void:
	if not Engine.is_editor_hint():
		return
	if what == NOTIFICATION_VISIBILITY_CHANGED and is_visible_in_tree():
		_auto_refresh_biome_editor_options()

func _build_ui() -> void:
	for child in get_children():
		child.queue_free()

	size_flags_vertical = Control.SIZE_EXPAND_FILL
	size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var title := Label.new()
	title.text = "Dungeon Designer"
	title.add_theme_font_size_override("font_size", 18)
	add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Edit dungeon layout + biome data from one place."
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(subtitle)

	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status_label)

	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tabs.tab_changed.connect(_on_tab_changed)
	add_child(_tabs)

	var layout_tab := VBoxContainer.new()
	layout_tab.name = "Dungeon Layout"
	layout_tab.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.add_child(layout_tab)

	var layout_action_row := HFlowContainer.new()
	layout_action_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout_action_row.add_child(_make_button("Open Dungeon Scene", _on_open_dungeon_scene_pressed))
	layout_action_row.add_child(_make_button("Refresh", _on_refresh_pressed))
	layout_action_row.add_child(_make_button("Save Open Scene", _on_save_scene_pressed))
	layout_action_row.add_child(_make_button("Create Preview", _on_create_preview_pressed))
	layout_action_row.add_child(_make_button("Clear Preview", _on_clear_preview_pressed))
	layout_tab.add_child(layout_action_row)

	var quick_layout := PanelContainer.new()
	var quick_layout_root := VBoxContainer.new()
	quick_layout.add_child(quick_layout_root)
	layout_tab.add_child(quick_layout)

	var quick_layout_title := Label.new()
	quick_layout_title.text = "Quick Layout Controls"
	quick_layout_root.add_child(quick_layout_title)

	var quick_layout_grid := GridContainer.new()
	quick_layout_grid.columns = 2
	quick_layout_root.add_child(quick_layout_grid)

	_grid_min_spin = _add_spin_row(quick_layout_grid, "Grid Size Min", 2, 100, 1)
	_grid_max_spin = _add_spin_row(quick_layout_grid, "Grid Size Max", 2, 100, 1)
	_room_size_spin = _add_spin_row(quick_layout_grid, "Room Size (tiles)", 3, 200, 1)
	_corridor_width_spin = _add_spin_row(quick_layout_grid, "Corridor Width (tiles)", 1, 20, 1)
	_corridor_length_spin = _add_spin_row(quick_layout_grid, "Corridor Length (tiles)", 1, 200, 1)
	_seed_spin = _add_spin_row(quick_layout_grid, "Generation Seed (0=random)", 0, 2147483647, 1)

	var quick_layout_actions := HFlowContainer.new()
	quick_layout_actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	quick_layout_actions.add_child(_make_button("Load From Scene", _on_load_layout_pressed))
	quick_layout_actions.add_child(_make_button("Apply + Save Layout", _on_apply_layout_pressed))
	quick_layout_root.add_child(quick_layout_actions)

	var preview_nav_header := Label.new()
	preview_nav_header.text = "Preview Room Jump (START/EXIT + handcrafted)"
	quick_layout_root.add_child(preview_nav_header)

	var preview_nav_row := VBoxContainer.new()
	_preview_room_selector = OptionButton.new()
	_preview_room_selector.fit_to_longest_item = false
	_preview_room_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_nav_row.add_child(_preview_room_selector)
	var preview_nav_actions := HFlowContainer.new()
	preview_nav_actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_nav_actions.add_child(_make_button("Refresh Rooms", _on_refresh_preview_rooms_pressed))
	preview_nav_actions.add_child(_make_button("Go To Room", _on_go_to_preview_room_pressed))
	preview_nav_row.add_child(preview_nav_actions)
	quick_layout_root.add_child(preview_nav_row)

	var manager_header := Label.new()
	manager_header.text = "Layout Inspector (All DungeonManager Fields)"
	layout_tab.add_child(manager_header)

	_manager_inspector = EditorInspector.new()
	_manager_inspector.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout_tab.add_child(_manager_inspector)

	var biome_tab := VBoxContainer.new()
	biome_tab.name = "Biome Data"
	biome_tab.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.add_child(biome_tab)

	var biome_action_row := HFlowContainer.new()
	biome_action_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	biome_action_row.add_child(_make_button("Refresh", _on_refresh_pressed))
	biome_action_row.add_child(_make_button("Save Selected Biome", _on_save_biome_pressed))
	biome_action_row.add_child(_make_button("Open Biome Resource", _on_open_biome_resource_pressed))
	biome_action_row.add_child(_make_button("Open Start Scene", _on_open_start_scene_pressed))
	biome_tab.add_child(biome_action_row)

	var biome_row := VBoxContainer.new()
	var biome_label := Label.new()
	biome_label.text = "Selected Biome:"
	biome_row.add_child(biome_label)

	_biome_selector = OptionButton.new()
	_biome_selector.fit_to_longest_item = false
	_biome_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_biome_selector.item_selected.connect(_on_biome_selected)
	biome_row.add_child(_biome_selector)
	biome_tab.add_child(biome_row)

	_build_handcrafted_room_wizard(biome_tab)

	var biome_header := Label.new()
	biome_header.text = "Biome Editor"
	biome_tab.add_child(biome_header)

	_biome_editor_scroll = ScrollContainer.new()
	_biome_editor_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_biome_editor_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	biome_tab.add_child(_biome_editor_scroll)

	_biome_editor_root = VBoxContainer.new()
	_biome_editor_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_biome_editor_scroll.add_child(_biome_editor_root)

func _make_button(text: String, callable: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(callable)
	return button

func _build_handcrafted_room_wizard(parent: Control) -> void:
	var panel := PanelContainer.new()
	parent.add_child(panel)

	var root := VBoxContainer.new()
	panel.add_child(root)

	var title := Label.new()
	title.text = "Handcrafted Room Wizard"
	root.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Create a clean handcrafted room scene, optionally register it into the selected biome, then open it."
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(subtitle)

	var grid := GridContainer.new()
	grid.columns = 2
	root.add_child(grid)

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
	_wizard_room_type_selector.add_item("Start Room Skeleton", WizardRoomType.START_SKELETON)
	_wizard_room_type_selector.add_item("Normal Room Skeleton", WizardRoomType.NORMAL_SKELETON)
	_wizard_room_type_selector.add_item("Quadrant Composite Room", WizardRoomType.QUADRANT_COMPOSITE)
	_wizard_room_type_selector.item_selected.connect(_on_wizard_room_type_selected)
	grid.add_child(_wizard_room_type_selector)

	var register_label := Label.new()
	register_label.text = "Register In Biome"
	grid.add_child(register_label)

	_wizard_register_selector = OptionButton.new()
	_populate_wizard_register_options(WizardRoomType.START_SKELETON)
	grid.add_child(_wizard_register_selector)

	var actions := HFlowContainer.new()
	actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(_make_button("Create Handcrafted Room", _on_create_handcrafted_room_pressed))
	root.add_child(actions)

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

func _refresh_all() -> void:
	_refresh_manager_section()
	_refresh_biome_section()

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

func _refresh_biome_section() -> void:
	_biome_selector.clear()
	_biomes = []
	_selected_biome = null
	_rebuild_biome_editor()
	_refresh_biome_option_lists()

	_biome_db = load(BIOME_DB_PATH)
	if _biome_db == null:
		_set_status("Could not load biome database: %s" % BIOME_DB_PATH, true)
		return
	if not _has_property(_biome_db, "biomes"):
		_set_status("Biome database has no 'biomes' property.", true)
		return

	var raw_biomes: Variant = _biome_db.get("biomes")
	if typeof(raw_biomes) != TYPE_ARRAY:
		_set_status("Biome database 'biomes' is not an Array.", true)
		return

	for biome_variant in raw_biomes:
		if biome_variant is Resource:
			_biomes.append(biome_variant)

	for biome_variant in _biomes:
		var biome: Resource = biome_variant
		var biome_id := "<unnamed>"
		if _has_property(biome, "biome_id"):
			biome_id = str(biome.get("biome_id"))
		_biome_selector.add_item(biome_id)

	if _biomes.is_empty():
		_set_status("No biome resources found in %s." % BIOME_DB_PATH, true)
		return

	_biome_selector.select(0)
	_set_selected_biome(0)

func _auto_refresh_biome_editor_options() -> void:
	if _selected_biome == null:
		return
	_refresh_biome_option_lists()
	_rebuild_biome_editor()

func _on_tab_changed(tab_index: int) -> void:
	if tab_index == BIOME_TAB_INDEX:
		_auto_refresh_biome_editor_options()

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

func _set_selected_biome(index: int) -> void:
	if index < 0 or index >= _biomes.size():
		_selected_biome = null
		_rebuild_biome_editor()
		_sync_wizard_name_placeholder()
		return
	_selected_biome = _biomes[index]
	_rebuild_biome_editor()
	_sync_wizard_name_placeholder()

func _on_open_dungeon_scene_pressed() -> void:
	if plugin == null:
		return
	plugin.get_editor_interface().open_scene_from_path(DUNGEON_SCENE_PATH)
	await get_tree().process_frame
	_refresh_manager_section()

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

	manager.call("generate_floor", int(manager.get("floor_number")), true)
	await get_tree().process_frame

	var err := plugin.get_editor_interface().save_scene()
	if err == OK:
		_refresh_preview_room_targets(manager)
		_set_status("Preview generated with seed %d. Press Play to run this exact layout." % seed)
	else:
		_set_status("Preview generated, but save failed with error %d." % err, true)

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
		_set_status("No preview room targets found. Generate preview first.", true)
	else:
		_set_status("Loaded %d preview room targets." % _preview_targets.size())

func _on_go_to_preview_room_pressed() -> void:
	if _preview_targets.is_empty():
		_set_status("No preview room targets found. Generate preview first.", true)
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
		_set_status("Moved marker/player to %s. Manually frame in viewport if needed." % label)

func _on_refresh_pressed() -> void:
	_refresh_all()

func _on_save_scene_pressed() -> void:
	if plugin == null:
		return
	var err := plugin.get_editor_interface().save_scene()
	if err == OK:
		_set_status("Saved edited scene.")
	else:
		_set_status("Save scene failed with error %d." % err, true)

func _on_save_biome_pressed() -> void:
	if _selected_biome == null:
		_set_status("No biome selected to save.", true)
		return
	var path := str(_selected_biome.resource_path)
	if path == "":
		_set_status("Selected biome has no resource path.", true)
		return
	var err := ResourceSaver.save(_selected_biome, path)
	if err == OK:
		_set_status("Saved biome resource: %s" % path)
	else:
		_set_status("Save biome failed with error %d." % err, true)

func _on_biome_selected(index: int) -> void:
	_set_selected_biome(index)
	_sync_wizard_name_placeholder()

func _on_open_biome_resource_pressed() -> void:
	if plugin == null or _selected_biome == null:
		return
	plugin.get_editor_interface().edit_resource(_selected_biome)
	_set_status("Opened biome resource in inspector.")

func _on_open_start_scene_pressed() -> void:
	if plugin == null or _selected_biome == null:
		return
	if not _has_property(_selected_biome, "handcrafted_start_room_scene"):
		_set_status("Selected biome does not expose handcrafted_start_room_scene.", true)
		return
	var start_scene_variant: Variant = _selected_biome.get("handcrafted_start_room_scene")
	if not (start_scene_variant is PackedScene):
		_set_status("Biome start scene is empty.", true)
		return
	var start_scene: PackedScene = start_scene_variant
	var path := str(start_scene.resource_path)
	if path == "":
		_set_status("Biome start scene has no path.", true)
		return
	plugin.get_editor_interface().open_scene_from_path(path)
	_set_status("Opened start scene: %s" % path)

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
		WizardRoomType.START_SKELETON:
			_wizard_register_selector.add_item("Set As Selected Biome Start Room", WizardRegisterTarget.START_ROOM)
		WizardRoomType.QUADRANT_COMPOSITE:
			_wizard_register_selector.add_item("Add To Selected Biome Normal Rooms", WizardRegisterTarget.NORMAL_ROOM_POOL)
			_wizard_register_selector.add_item("Add To Selected Biome Quadrant Pool", WizardRegisterTarget.QUADRANT_POOL)
		_:
			_wizard_register_selector.add_item("Add To Selected Biome Normal Rooms", WizardRegisterTarget.NORMAL_ROOM_POOL)
	_wizard_register_selector.select(0)

func _sync_wizard_name_placeholder() -> void:
	if _wizard_name_edit == null:
		return
	var biome_prefix := "Room"
	if _selected_biome != null and _has_property(_selected_biome, "biome_id"):
		biome_prefix = str(_selected_biome.get("biome_id")).capitalize()
	var room_type := WizardRoomType.NORMAL_SKELETON
	if _wizard_room_type_selector != null and _wizard_room_type_selector.selected >= 0:
		room_type = _wizard_room_type_selector.get_item_id(_wizard_room_type_selector.selected)
	match room_type:
		WizardRoomType.START_SKELETON:
			_wizard_name_edit.placeholder_text = "%s_StartVariant" % biome_prefix
		WizardRoomType.QUADRANT_COMPOSITE:
			_wizard_name_edit.placeholder_text = "%s_CrossroomVariant" % biome_prefix
		_:
			_wizard_name_edit.placeholder_text = "%s_GuardHall" % biome_prefix

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

	var room_type := _wizard_room_type_selector.get_item_id(_wizard_room_type_selector.selected)
	var register_target := _wizard_register_selector.get_item_id(_wizard_register_selector.selected)
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
	_refresh_biome_option_lists()
	_rebuild_biome_editor()
	plugin.get_editor_interface().open_scene_from_path(scene_path)
	_wizard_name_edit.text = ""

	if register_result == "":
		_set_status("Created handcrafted room: %s" % scene_path)
	else:
		_set_status("Created handcrafted room: %s. %s" % [scene_path, register_result])

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
	var root: Node3D = null
	match room_type:
		WizardRoomType.QUADRANT_COMPOSITE:
			root = _build_quadrant_composite_scene_root(scene_name)
		_:
			root = _build_overlay_room_scene_root(scene_name, room_type)
	if root == null:
		return null

	var packed := PackedScene.new()
	var pack_err := packed.pack(root)
	root.free()
	if pack_err != OK:
		return null
	return packed

func _build_overlay_room_scene_root(scene_name: String, room_type: int) -> Node3D:
	var root := Node3D.new()
	root.name = scene_name
	var layout_script := load(HANDCRAFTED_LAYOUT_SCRIPT_PATH)
	if layout_script is Script:
		root.set_script(layout_script)
	root.set("allow_random_orientation", room_type == WizardRoomType.NORMAL_SKELETON)

	_add_owned_child(root, _make_room_guides_root(), root)
	_add_owned_child(root, _make_door_socket_root(room_type == WizardRoomType.START_SKELETON), root)

	if room_type == WizardRoomType.START_SKELETON:
		var spawn_pad := MeshInstance3D.new()
		spawn_pad.name = "SpawnPad"
		spawn_pad.position = Vector3(0.0, 0.15, -2.5)
		var pad_mesh := CylinderMesh.new()
		pad_mesh.top_radius = 2.5
		pad_mesh.bottom_radius = 2.8
		pad_mesh.height = 0.3
		var pad_material := StandardMaterial3D.new()
		pad_material.albedo_color = Color(0.16, 0.15, 0.14, 1.0)
		pad_material.roughness = 0.95
		pad_material.emission_enabled = true
		pad_material.emission = Color(0.18, 0.11, 0.04, 1.0)
		pad_material.emission_energy_multiplier = 0.2
		pad_mesh.material = pad_material
		spawn_pad.mesh = pad_mesh
		_add_owned_child(root, spawn_pad, root)

		var player_spawn := Node3D.new()
		player_spawn.name = "PlayerSpawn"
		player_spawn.position = Vector3(0.0, 0.0, -2.5)
		_add_owned_child(root, player_spawn, root)
	else:
		var encounter_root := Node3D.new()
		encounter_root.name = "Encounter"
		_add_owned_child(root, encounter_root, root)

		var spawner := Marker3D.new()
		spawner.name = "EnemySpawner"
		spawner.position = Vector3(0.0, 0.0, 0.0)
		var spawner_script := load(HANDCRAFTED_ENEMY_SPAWNER_SCRIPT_PATH)
		if spawner_script is Script:
			spawner.set_script(spawner_script)
		_add_owned_child(encounter_root, spawner, root)

	return root

func _build_quadrant_composite_scene_root(scene_name: String) -> Node3D:
	var template_variant := load(QUADRANT_TEMPLATE_SCENE_PATH)
	if not (template_variant is PackedScene):
		return null
	var template_scene: PackedScene = template_variant
	var inst: Variant = template_scene.instantiate()
	if not (inst is Node3D):
		if inst is Node:
			var cleanup: Node = inst
			cleanup.free()
		return null
	var root: Node3D = inst
	root.name = scene_name
	return root

func _make_door_socket_root(mark_start_socket: bool) -> Node3D:
	var sockets_root := Node3D.new()
	sockets_root.name = "DoorSockets"

	var socket_positions := {
		"NorthSocket": Vector3(0.0, 0.0, -10.0),
		"SouthSocket": Vector3(0.0, 0.0, 10.0),
		"WestSocket": Vector3(-10.0, 0.0, 0.0),
		"EastSocket": Vector3(10.0, 0.0, 0.0),
	}
	for socket_name in socket_positions.keys():
		var marker := Marker3D.new()
		marker.name = socket_name
		marker.position = socket_positions[socket_name]
		sockets_root.add_child(marker)
		marker.owner = sockets_root
		if mark_start_socket and socket_name == "SouthSocket":
			marker.set_meta("start_room_primary_doorway", true)

	return sockets_root

func _make_room_guides_root() -> Node3D:
	var debug_root := Node3D.new()
	debug_root.name = "RoomBoundsDebug"

	var guide_material := StandardMaterial3D.new()
	guide_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	guide_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	guide_material.albedo_color = Color(0.8, 0.7, 0.45, 0.55)

	var long_mesh := BoxMesh.new()
	long_mesh.material = guide_material
	long_mesh.size = Vector3(20.0, 0.2, 0.25)

	var short_mesh := BoxMesh.new()
	short_mesh.material = guide_material
	short_mesh.size = Vector3(0.25, 0.2, 20.0)

	var north_edge := MeshInstance3D.new()
	north_edge.name = "NorthEdge"
	north_edge.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	north_edge.position = Vector3(0.0, 0.1, -10.0)
	north_edge.mesh = long_mesh
	_add_owned_child(debug_root, north_edge, debug_root)

	var south_edge := MeshInstance3D.new()
	south_edge.name = "SouthEdge"
	south_edge.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	south_edge.position = Vector3(0.0, 0.1, 10.0)
	south_edge.mesh = long_mesh
	_add_owned_child(debug_root, south_edge, debug_root)

	var west_edge := MeshInstance3D.new()
	west_edge.name = "WestEdge"
	west_edge.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	west_edge.position = Vector3(-10.0, 0.1, 0.0)
	west_edge.mesh = short_mesh
	_add_owned_child(debug_root, west_edge, debug_root)

	var east_edge := MeshInstance3D.new()
	east_edge.name = "EastEdge"
	east_edge.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	east_edge.position = Vector3(10.0, 0.1, 0.0)
	east_edge.mesh = short_mesh
	_add_owned_child(debug_root, east_edge, debug_root)

	return debug_root

func _add_owned_child(parent: Node, child: Node, owner: Node) -> void:
	parent.add_child(child)
	child.owner = owner

func _register_new_handcrafted_scene(scene: PackedScene, register_target: int) -> String:
	if register_target == WizardRegisterTarget.NONE:
		return "Left unregistered."
	if _selected_biome == null:
		return "No biome selected, so it was not registered."

	match register_target:
		WizardRegisterTarget.START_ROOM:
			if not _has_property(_selected_biome, "handcrafted_start_room_scene"):
				return "Selected biome does not expose handcrafted_start_room_scene."
			_selected_biome.set("handcrafted_start_room_scene", scene)
		WizardRegisterTarget.NORMAL_ROOM_POOL:
			if not _append_scene_to_biome_array("handcrafted_normal_room_scenes", scene):
				return "Selected biome does not expose handcrafted_normal_room_scenes."
		WizardRegisterTarget.QUADRANT_POOL:
			if not _append_scene_to_biome_array("handcrafted_quadrant_room_scenes", scene):
				return "Selected biome does not expose handcrafted_quadrant_room_scenes."

	var path := str(_selected_biome.resource_path)
	if path == "":
		return "Registered in memory only because the selected biome has no resource path."
	var save_err := ResourceSaver.save(_selected_biome, path)
	if save_err != OK:
		return "Updated biome in memory but saving failed with error %d." % save_err
	return "Updated selected biome: %s" % path

func _append_scene_to_biome_array(property_name: String, scene: PackedScene) -> bool:
	if not _has_property(_selected_biome, property_name):
		return false
	var current_variant: Variant = _selected_biome.get(property_name)
	var scenes: Array = []
	if typeof(current_variant) == TYPE_ARRAY:
		scenes.assign(current_variant)
	for existing_variant in scenes:
		if existing_variant is PackedScene and str((existing_variant as PackedScene).resource_path) == str(scene.resource_path):
			_selected_biome.set(property_name, scenes)
			return true
	scenes.append(scene)
	_selected_biome.set(property_name, scenes)
	return true

func _refresh_biome_option_lists() -> void:
	_texture_options = _collect_files_recursive("res://Assets", ["png", "jpg", "jpeg", "webp", "tga", "bmp", "exr", "hdr"])
	_scene_options = _collect_files_recursive("res://Scenes", ["tscn"])
	_enemy_scene_options = []
	_prop_scene_options = []
	_handcrafted_scene_options = []
	_door_scene_options = []
	_light_scene_options = []
	for path in _scene_options:
		if path.begins_with("res://Scenes/Enemies/"):
			var name := path.get_file()
			if name != "enemy_chaser.tscn" and name != "enemy_melee.tscn" and name != "enemy_ranged.tscn":
				_enemy_scene_options.append(path)
		if path.begins_with("res://Scenes/Props/"):
			_prop_scene_options.append(path)
		if path.begins_with("res://Scenes/Dungeon/Handcrafted/"):
			_handcrafted_scene_options.append(path)
		if path.find("door") != -1:
			_door_scene_options.append(path)
		if path.begins_with("res://Scenes/Dungeon/") or path.begins_with("res://Scenes/Props/"):
			_light_scene_options.append(path)

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

func _rebuild_biome_editor() -> void:
	if _biome_editor_root == null:
		return
	for child in _biome_editor_root.get_children():
		child.queue_free()
	if _selected_biome == null:
		var empty := Label.new()
		empty.text = "Select a biome to edit."
		_biome_editor_root.add_child(empty)
		return

	var surfaces := _make_biome_section("Surface Textures")
	_add_resource_array_editor(surfaces, "Floor Textures", "floor_textures", _texture_options, "texture")
	_add_resource_array_editor(surfaces, "Wall Textures", "wall_textures", _texture_options, "texture")
	_add_resource_array_editor(surfaces, "Ceiling Textures", "ceiling_textures", _texture_options, "texture")

	var doors := _make_biome_section("Doors And Handcrafted Rooms")
	_add_resource_picker_row(doors, "Door Scene", "door_scene", _door_scene_options, "scene")
	_add_resource_picker_row(doors, "Doorway Assembly Scene", "doorway_assembly_scene", _door_scene_options, "scene")
	_add_resource_picker_row(doors, "Start Room Scene", "handcrafted_start_room_scene", _handcrafted_scene_options, "scene")
	_add_resource_array_editor(doors, "Normal Room Scenes", "handcrafted_normal_room_scenes", _handcrafted_scene_options, "scene")
	_add_float_row(doors, "Normal Room Chance", "handcrafted_normal_room_chance", 0.0, 1.0, 0.01)

	var lighting := _make_biome_section("Lighting")
	_add_color_row(lighting, "Room Light Color", "room_light_color")
	_add_resource_picker_row(lighting, "Room Cookie Texture", "room_light_cookie_texture", _texture_options, "texture")
	_add_color_row(lighting, "Corridor Light Color", "corridor_light_color")
	_add_float_row(lighting, "Corridor Light Energy", "corridor_light_energy", 0.0, 20.0, 0.05)
	_add_float_row(lighting, "Corridor Light Range", "corridor_light_range", 0.0, 60.0, 0.1)
	_add_float_row(lighting, "Corridor Light Height", "corridor_light_height", 0.0, 2.0, 0.01)
	_add_float_row(lighting, "Corridor Light Step", "corridor_light_step", 1.0, 30.0, 1.0, true)
	_add_float_row(lighting, "Corridor Light Chance", "corridor_light_chance", 0.0, 1.0, 0.01)
	_add_bool_row(lighting, "Use Prop Lights", "use_prop_lights")
	_add_resource_picker_row(lighting, "Wall Light Scene", "wall_light_scene", _light_scene_options, "scene")
	_add_color_row(lighting, "Wall Light Color", "wall_light_color")
	_add_float_row(lighting, "Wall Light Energy", "wall_light_energy", 0.0, 20.0, 0.05)
	_add_float_row(lighting, "Wall Light Range", "wall_light_range", 0.0, 60.0, 0.1)
	_add_float_row(lighting, "Wall Light Height", "wall_light_height", 0.0, 5.0, 0.01)
	_add_resource_picker_row(lighting, "Floor Light Scene", "floor_light_scene", _light_scene_options, "scene")
	_add_color_row(lighting, "Floor Light Color", "floor_light_color")
	_add_float_row(lighting, "Floor Light Energy", "floor_light_energy", 0.0, 20.0, 0.05)
	_add_float_row(lighting, "Floor Light Range", "floor_light_range", 0.0, 60.0, 0.1)
	_add_float_row(lighting, "Floor Light Height", "floor_light_height", 0.0, 5.0, 0.01)
	_add_color_row(lighting, "Fog Light Color", "fog_light_color")
	_add_resource_picker_row(lighting, "Exit Portal Texture", "exit_portal_texture", _texture_options, "texture")

	var props := _make_biome_section("Props")
	_add_resource_array_editor(props, "Universal Prop Scenes", "universal_prop_scenes", _prop_scene_options, "scene")
	_add_resource_array_editor(props, "Biome Prop Scenes", "biome_prop_scenes", _prop_scene_options, "scene")

	var enemies := _make_biome_section("Enemies")
	_add_resource_array_editor(enemies, "Enemy Scenes", "enemy_scenes", _enemy_scene_options, "scene")

	var validation := _make_biome_section("Validation")
	validation.add_child(_make_button("Validate Selected Biome", _validate_selected_biome))

func _make_biome_section(title: String) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_child(root)
	var label := Label.new()
	label.text = title
	label.add_theme_font_size_override("font_size", 14)
	root.add_child(label)
	_biome_editor_root.add_child(panel)
	return root

func _make_form_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size.x = 130
	label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	return label

# Opens a compact searchable popup. The button shows the current filename; clicking
# it opens a filtered list. Selecting an item calls on_path_selected(path).
func _make_searchable_picker(options: Array[String], initial_path: String, on_path_selected: Callable) -> Button:
	var state := {"path": initial_path}
	var btn := Button.new()
	btn.text = initial_path.get_file() if initial_path != "" else "(None)"
	btn.clip_text = true
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.pressed.connect(func() -> void:
		_show_search_popup(btn, options, state.path, func(path: String) -> void:
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
	checkbox.button_pressed = bool(_selected_biome.get(property_name))
	checkbox.toggled.connect(func(pressed: bool) -> void:
		_set_biome_property(property_name, pressed)
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
	spin.value = float(_selected_biome.get(property_name))
	spin.rounded = integer_only
	spin.custom_minimum_size.x = 80
	spin.size_flags_horizontal = Control.SIZE_SHRINK_END
	spin.value_changed.connect(func(value: float) -> void:
		if integer_only:
			_set_biome_property(property_name, int(value))
		else:
			_set_biome_property(property_name, value)
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
	var current: Variant = _selected_biome.get(property_name)
	if current is Color:
		picker.color = current
	picker.color_changed.connect(func(color: Color) -> void:
		_set_biome_property(property_name, color)
	)
	row.add_child(picker)
	container.add_child(row)

func _add_resource_picker_row(container: VBoxContainer, label_text: String, property_name: String, options: Array[String], kind: String) -> void:
	var row := HBoxContainer.new()
	var label := _make_form_label(label_text)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)

	var current_path := _resource_path_from_variant(_selected_biome.get(property_name))
	var picker := _make_searchable_picker(options, current_path, func(path: String) -> void:
		if path == "":
			_set_biome_property(property_name, null)
			return
		var loaded := load(path)
		_set_biome_property(property_name, loaded)
	)
	picker.custom_minimum_size.x = 130
	picker.size_flags_horizontal = Control.SIZE_SHRINK_END
	row.add_child(picker)

	var open_button := Button.new()
	open_button.text = "Open"
	open_button.pressed.connect(func() -> void:
		if plugin == null:
			return
		var value: Variant = _selected_biome.get(property_name)
		if kind == "scene" and value is PackedScene:
			var packed: PackedScene = value
			if packed.resource_path != "":
				plugin.get_editor_interface().open_scene_from_path(packed.resource_path)
		elif value is Resource:
			plugin.get_editor_interface().edit_resource(value)
	)
	row.add_child(open_button)
	container.add_child(row)

func _add_resource_array_editor(container: VBoxContainer, title: String, property_name: String, options: Array[String], kind: String) -> void:
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
		var values := _get_resource_array(property_name)
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

	# Add row: searchable picker (fill) + Add button
	var add_row := HBoxContainer.new()
	add_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.add_child(add_row)

	var picker_state := {"path": options[0] if not options.is_empty() else ""}
	var picker := _make_searchable_picker(options, picker_state.path, func(path: String) -> void:
		picker_state.path = path
	)
	add_row.add_child(picker)

	var add_button := Button.new()
	add_button.text = "Add"
	add_button.pressed.connect(func() -> void:
		if picker_state.path == "":
			return
		var loaded := load(picker_state.path)
		if not (loaded is Resource):
			return
		var values := _get_resource_array(property_name)
		values.append(loaded)
		_set_biome_property(property_name, values)
		refresh.call()
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
		var values := _get_resource_array(property_name)
		values.remove_at(int(selected[0]))
		_set_biome_property(property_name, values)
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
		var values := _get_resource_array(property_name)
		var tmp: Variant = values[idx - 1]
		values[idx - 1] = values[idx]
		values[idx] = tmp
		_set_biome_property(property_name, values)
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
		var values := _get_resource_array(property_name)
		if idx >= values.size() - 1:
			return
		var tmp: Variant = values[idx + 1]
		values[idx + 1] = values[idx]
		values[idx] = tmp
		_set_biome_property(property_name, values)
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
		var values := _get_resource_array(property_name)
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

func _set_biome_property(property_name: String, value: Variant) -> void:
	if _selected_biome == null:
		return
	_selected_biome.set(property_name, value)
	_selected_biome.emit_changed()

func _get_resource_array(property_name: String) -> Array:
	if _selected_biome == null:
		return []
	var raw: Variant = _selected_biome.get(property_name)
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

func _resource_path_from_variant(value: Variant) -> String:
	if value is Resource:
		var resource: Resource = value
		return resource.resource_path
	if value is String:
		return str(value)
	return ""

func _validate_selected_biome() -> void:
	if _selected_biome == null:
		_set_status("No biome selected.", true)
		return
	var issues: Array[String] = []
	if _get_resource_array("floor_textures").is_empty():
		issues.append("floor_textures is empty")
	if _get_resource_array("wall_textures").is_empty():
		issues.append("wall_textures is empty")
	if _get_resource_array("ceiling_textures").is_empty():
		issues.append("ceiling_textures is empty")
	if _get_resource_array("universal_prop_scenes").is_empty():
		issues.append("universal_prop_scenes is empty")
	if _get_resource_array("enemy_scenes").is_empty():
		issues.append("enemy_scenes is empty")
	if bool(_selected_biome.get("use_prop_lights")):
		if _selected_biome.get("wall_light_scene") == null:
			issues.append("use_prop_lights is true but wall_light_scene is missing")
		if _selected_biome.get("wall_light_scene") == null and _selected_biome.get("floor_light_scene") == null:
			issues.append("use_prop_lights is true but no wall/floor light scene is configured")
	if issues.is_empty():
		_set_status("Biome validation passed.")
	else:
		_set_status("Biome validation issues: %s" % "; ".join(issues), true)

func _set_status(message: String, is_error: bool = false) -> void:
	if _status_label == null:
		return
	_status_label.text = message
	var color := Color(0.95, 0.95, 0.95, 1.0)
	if is_error:
		color = Color(1.0, 0.45, 0.45, 1.0)
	_status_label.add_theme_color_override("font_color", color)

func _clear_preview_target_list() -> void:
	_preview_targets = []
	if _preview_room_selector != null:
		_preview_room_selector.clear()

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
	_room_size_spin.value = int(manager.get("room_size_tiles"))
	_corridor_width_spin.value = int(manager.get("corridor_width_tiles"))
	_corridor_length_spin.value = int(manager.get("corridor_length_tiles"))
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
	manager.set("room_size_tiles", int(_room_size_spin.value))
	manager.set("corridor_width_tiles", int(_corridor_width_spin.value))
	manager.set("corridor_length_tiles", int(_corridor_length_spin.value))
	manager.set("generation_seed", int(_seed_spin.value))

func _ensure_open_manager() -> Node:
	var manager := _get_dungeon_manager_from_edited_scene()
	if manager != null:
		return manager
	if plugin == null:
		return null
	plugin.get_editor_interface().open_scene_from_path(DUNGEON_SCENE_PATH)
	await get_tree().process_frame
	return _get_dungeon_manager_from_edited_scene()

func _has_property(resource: Resource, property_name: String) -> bool:
	if resource == null:
		return false
	for property_variant in resource.get_property_list():
		if typeof(property_variant) != TYPE_DICTIONARY:
			continue
		var property_dict: Dictionary = property_variant
		if str(property_dict.get("name", "")) == property_name:
			return true
	return false
