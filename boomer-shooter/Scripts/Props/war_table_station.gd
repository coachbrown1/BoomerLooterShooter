extends StaticBody3D
class_name WarTableStation

signal player_interacted(body: Node3D)

@export var interact_prompt: String = "War Table"

func _ready() -> void:
	add_to_group("interactable")
	add_to_group("war_table_station")

func interact(body: Node3D) -> void:
	player_interacted.emit(body)
