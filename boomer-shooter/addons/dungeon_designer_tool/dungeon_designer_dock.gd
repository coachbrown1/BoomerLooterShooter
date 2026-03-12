@tool
extends VBoxContainer

const DUNGEON_SCENE_PATH := "res://Scenes/World/dungeon.tscn"
const BIOME_DB_PATH := "res://Data/biomes/biome_dungeon_database.tres"
const DUNGEON_MANAGER_SCRIPT_PATH := "res://Scripts/Dungeon/dungeon_manager.gd"

var plugin: EditorPlugin = null

var _status_label: Label
var _biome_selector: OptionButton
var _manager_inspector: EditorInspector
var _biome_editor_scroll: ScrollContainer
var _biome_editor_root: VBoxContainer
var _preview_room_selector: OptionButton
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

	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(tabs)

	var layout_tab := VBoxContainer.new()
	layout_tab.name = "Dungeon Layout"
	layout_tab.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.add_child(layout_tab)

	var layout_action_row := HBoxContainer.new()
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

	var quick_layout_actions := HBoxContainer.new()
	quick_layout_actions.add_child(_make_button("Load From Scene", _on_load_layout_pressed))
	quick_layout_actions.add_child(_make_button("Apply + Save Layout", _on_apply_layout_pressed))
	quick_layout_root.add_child(quick_layout_actions)

	var preview_nav_header := Label.new()
	preview_nav_header.text = "Preview Room Jump (START/EXIT + handcrafted)"
	quick_layout_root.add_child(preview_nav_header)

	var preview_nav_row := HBoxContainer.new()
	_preview_room_selector = OptionButton.new()
	_preview_room_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_nav_row.add_child(_preview_room_selector)
	preview_nav_row.add_child(_make_button("Refresh Rooms", _on_refresh_preview_rooms_pressed))
	preview_nav_row.add_child(_make_button("Go To Room", _on_go_to_preview_room_pressed))
	quick_layout_root.add_child(preview_nav_row)

	var manager_header := Label.new()
	manager_header.text = "Layout Inspector (All DungeonManager Fields)"
	layout_tab.add_child(manager_header)

	_manager_inspector = EditorInspector.new()
	_manager_inspector.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_manager_inspector.custom_minimum_size = Vector2(0, 250)
	layout_tab.add_child(_manager_inspector)

	var biome_tab := VBoxContainer.new()
	biome_tab.name = "Biome Data"
	biome_tab.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.add_child(biome_tab)

	var biome_action_row := HBoxContainer.new()
	biome_action_row.add_child(_make_button("Refresh", _on_refresh_pressed))
	biome_action_row.add_child(_make_button("Save Selected Biome", _on_save_biome_pressed))
	biome_action_row.add_child(_make_button("Open Biome Resource", _on_open_biome_resource_pressed))
	biome_action_row.add_child(_make_button("Open Start Scene", _on_open_start_scene_pressed))
	biome_tab.add_child(biome_action_row)

	var biome_row := HBoxContainer.new()
	var biome_label := Label.new()
	biome_label.text = "Selected Biome:"
	biome_row.add_child(biome_label)

	_biome_selector = OptionButton.new()
	_biome_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_biome_selector.item_selected.connect(_on_biome_selected)
	biome_row.add_child(_biome_selector)
	biome_tab.add_child(biome_row)

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
		_biome_selector.add_item("%s (%s)" % [biome_id, biome.resource_path])

	if _biomes.is_empty():
		_set_status("No biome resources found in %s." % BIOME_DB_PATH, true)
		return

	_biome_selector.select(0)
	_set_selected_biome(0)

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
		return
	_selected_biome = _biomes[index]
	_rebuild_biome_editor()

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
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	return label

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
	row.add_child(label)
	var spin := SpinBox.new()
	spin.min_value = min_value
	spin.max_value = max_value
	spin.step = step
	spin.value = float(_selected_biome.get(property_name))
	spin.rounded = integer_only
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
	row.add_child(label)
	var picker := ColorPickerButton.new()
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
	row.add_child(label)

	var picker := OptionButton.new()
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker.add_item("(None)")
	picker.set_item_metadata(0, "")
	var current_path := _resource_path_from_variant(_selected_biome.get(property_name))
	var selected := 0
	for path in options:
		var index := picker.get_item_count()
		picker.add_item(path.get_file())
		picker.set_item_metadata(index, path)
		if path == current_path:
			selected = index
	picker.select(selected)
	picker.item_selected.connect(func(index: int) -> void:
		var path: String = str(picker.get_item_metadata(index))
		if path == "":
			_set_biome_property(property_name, null)
			return
		var loaded := load(path)
		_set_biome_property(property_name, loaded)
	)
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
	list.custom_minimum_size = Vector2(0, 100)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.add_child(list)

	var refresh := func() -> void:
		list.clear()
		var values := _get_resource_array(property_name)
		for value in values:
			if value is Resource:
				var resource: Resource = value
				var path := resource.resource_path
				list.add_item(path if path != "" else str(resource))
		if list.get_item_count() > 0:
			list.select(0)
	refresh.call()

	var controls := HBoxContainer.new()
	container.add_child(controls)

	var picker := OptionButton.new()
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for path in options:
		var index := picker.get_item_count()
		picker.add_item(path.get_file())
		picker.set_item_metadata(index, path)
	controls.add_child(picker)

	var add_button := Button.new()
	add_button.text = "Add"
	add_button.pressed.connect(func() -> void:
		if picker.get_item_count() == 0:
			return
		var path := str(picker.get_item_metadata(picker.selected))
		var loaded := load(path)
		if not (loaded is Resource):
			return
		var values := _get_resource_array(property_name)
		values.append(loaded)
		_set_biome_property(property_name, values)
		refresh.call()
	)
	controls.add_child(add_button)

	var remove_button := Button.new()
	remove_button.text = "Remove"
	remove_button.pressed.connect(func() -> void:
		var selected := list.get_selected_items()
		if selected.is_empty():
			return
		var values := _get_resource_array(property_name)
		values.remove_at(int(selected[0]))
		_set_biome_property(property_name, values)
		refresh.call()
	)
	controls.add_child(remove_button)

	var up_button := Button.new()
	up_button.text = "Up"
	up_button.pressed.connect(func() -> void:
		var selected := list.get_selected_items()
		if selected.is_empty():
			return
		var idx := int(selected[0])
		if idx <= 0:
			return
		var values := _get_resource_array(property_name)
		var tmp_up: Variant = values[idx - 1]
		values[idx - 1] = values[idx]
		values[idx] = tmp_up
		_set_biome_property(property_name, values)
		refresh.call()
		list.select(idx - 1)
	)
	controls.add_child(up_button)

	var down_button := Button.new()
	down_button.text = "Down"
	down_button.pressed.connect(func() -> void:
		var selected := list.get_selected_items()
		if selected.is_empty():
			return
		var idx := int(selected[0])
		var values := _get_resource_array(property_name)
		if idx >= values.size() - 1:
			return
		var tmp_down: Variant = values[idx + 1]
		values[idx + 1] = values[idx]
		values[idx] = tmp_down
		_set_biome_property(property_name, values)
		refresh.call()
		list.select(idx + 1)
	)
	controls.add_child(down_button)

	var open_button := Button.new()
	open_button.text = "Open"
	open_button.pressed.connect(func() -> void:
		if plugin == null:
			return
		var selected := list.get_selected_items()
		if selected.is_empty():
			return
		var values := _get_resource_array(property_name)
		var idx := int(selected[0])
		if idx < 0 or idx >= values.size():
			return
		var value: Variant = values[idx]
		if kind == "scene" and value is PackedScene:
			var packed: PackedScene = value
			if packed.resource_path != "":
				plugin.get_editor_interface().open_scene_from_path(packed.resource_path)
		elif value is Resource:
			plugin.get_editor_interface().edit_resource(value)
	)
	controls.add_child(open_button)

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
