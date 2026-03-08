@tool
extends EditorPlugin

const DOCK_SCRIPT := preload("res://addons/dungeon_designer_tool/dungeon_designer_dock.gd")

var _dock: VBoxContainer = null

func _enter_tree() -> void:
	_dock = DOCK_SCRIPT.new()
	_dock.plugin = self
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, _dock)

func _exit_tree() -> void:
	if _dock == null:
		return
	remove_control_from_docks(_dock)
	_dock.queue_free()
	_dock = null
