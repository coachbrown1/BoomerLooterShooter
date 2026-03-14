@tool
extends Marker3D
class_name HandcraftedEnemySpawner

@export var enemy_scene: PackedScene
@export_range(1, 8, 1) var spawn_count: int = 1
@export_range(0.0, 6.0, 0.1) var spawn_radius: float = 0.0
@export_range(0.0, 3.0, 0.1) var vertical_offset: float = 0.0

func get_spawn_position(index: int) -> Vector3:
	if spawn_count <= 1 or spawn_radius <= 0.0:
		return global_position + Vector3(0.0, vertical_offset, 0.0)
	var angle_step := TAU / float(spawn_count)
	var angle := angle_step * float(index)
	var offset := Vector3(cos(angle), 0.0, sin(angle)) * spawn_radius
	return global_position + offset + Vector3(0.0, vertical_offset, 0.0)
