@tool
extends Area3D
class_name Portal

signal player_entered(body: Node3D)

func _ready() -> void:
	if not Engine.is_editor_hint():
		body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		player_entered.emit(body)
