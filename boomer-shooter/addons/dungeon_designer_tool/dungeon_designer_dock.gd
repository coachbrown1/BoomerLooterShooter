@tool
extends VBoxContainer

const DUNGEON_SCENE_PATH := "res://Scenes/World/dungeon.tscn"
const BIOME_DB_PATH := "res://Data/biomes/biome_dungeon_database.tres"
const DUNGEON_MANAGER_SCRIPT_PATH := "res://Scripts/Dungeon/dungeon_manager.gd"

var plugin: EditorPlugin = null

var _status_label: Label
var _biome_selector: OptionButton
var _manager_inspector: EditorInspector
var _biome_inspector: EditorInspector
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
	biome_header.text = "Biome Inspector (All Fields)"
	biome_tab.add_child(biome_header)

	_biome_inspector = EditorInspector.new()
	_biome_inspector.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_biome_inspector.custom_minimum_size = Vector2(0, 300)
	biome_tab.add_child(_biome_inspector)

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
	_biome_inspector.edit(null)

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
		_biome_inspector.edit(null)
		return
	_selected_biome = _biomes[index]
	_biome_inspector.edit(_selected_biome)

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
