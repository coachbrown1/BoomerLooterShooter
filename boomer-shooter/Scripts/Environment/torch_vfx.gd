@tool
extends Node3D

# Simple script that just allows for easy identification in the scene,
# and potentially syncing the light to any parameters in the future.
# The actual effects are now fully contained as child nodes.

@export var fire_color: Color = Color(1.0, 0.6, 0.2)
@export var intensity: float = 1.0

func _ready() -> void:
	pass
