@tool
extends EditorPlugin

const DOCK_SCRIPT_PATH := "res://addons/dungeon_designer_tool/dungeon_designer_dock.gd"

var _dock: VBoxContainer = null

func _enter_tree() -> void:
	var dock_script_variant := load(DOCK_SCRIPT_PATH)
	if not (dock_script_variant is Script):
		push_error("Dungeon Designer: failed to load dock script at %s." % DOCK_SCRIPT_PATH)
		return
	var dock_script: Script = dock_script_variant
	_dock = dock_script.new()
	_dock.name = "Dungeon Designer"
	_dock.plugin = self
	add_control_to_dock(DOCK_SLOT_LEFT_BL, _dock)

func _exit_tree() -> void:
	if _dock == null:
		return
	remove_control_from_docks(_dock)
	_dock.queue_free()
	_dock = null
