@tool
extends StaticBody3D
class_name DungeonDoor

@export var is_open: bool = false
@onready var hinge: Node3D = $Hinge
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var door_mesh: MeshInstance3D = $Hinge/DoorMesh

func _ready() -> void:
	add_to_group("dungeon_door")
	hinge.rotation_degrees.y = 90.0 if is_open else 0.0
	collision_shape.disabled = is_open

func open() -> void:
	if is_open:
		return
	is_open = true
	var tween = create_tween()
	tween.tween_property(hinge, "rotation_degrees:y", 90.0, 0.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.finished.connect(func() -> void:
		collision_shape.disabled = true
	)
	# Play sound here if you want
