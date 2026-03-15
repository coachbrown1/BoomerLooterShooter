@tool
extends Area3D
class_name Portal

signal player_interacted(body: Node3D)

func _ready() -> void:
	if not Engine.is_editor_hint():
		monitoring = false  # No longer using overlap; interaction is raycast-based.

func interact(body: Node3D) -> void:
	player_interacted.emit(body)
