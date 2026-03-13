extends "res://addons/gut/test.gd"

const DungeonManagerScript = preload("res://Scripts/Dungeon/dungeon_manager.gd")

func test_offset_spawn_position_is_stable() -> void:
	var manager = DungeonManagerScript.new()
	assert_eq(manager._offset_spawn_position(Vector3.ZERO, 0), Vector3.ZERO)
	assert_eq(manager._offset_spawn_position(Vector3.ZERO, 1), Vector3(2.0, 0.0, 0.0))
	assert_eq(manager._offset_spawn_position(Vector3.ZERO, 2), Vector3(-2.0, 0.0, 0.0))
	assert_eq(manager._offset_spawn_position(Vector3.ZERO, 3), Vector3(0.0, 0.0, 2.0))
	assert_eq(manager._offset_spawn_position(Vector3.ZERO, 4), Vector3(0.0, 0.0, -2.0))
	manager.free()
