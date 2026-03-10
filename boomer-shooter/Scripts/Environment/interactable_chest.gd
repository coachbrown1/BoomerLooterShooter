extends StaticBody3D
class_name InteractableChest

@export var interact_prompt: String = "Open Chest"
var is_open: bool = false
@onready var lid_hinge: Node3D = $LidHinge

func _ready() -> void:
	# Add to interactable group if not already, useful for raycasts
	add_to_group("interactable")

func interact() -> void:
	if is_open:
		return
		
	is_open = true
	
	var tween = create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN_OUT)
	
	# Rotates lid up to open
	tween.tween_property(lid_hinge, "rotation_degrees:x", -110.0, 0.8)
	
	print("Chest opened!")
