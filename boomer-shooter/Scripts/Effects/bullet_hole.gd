extends Decal

const TEXTURES = [
	preload("res://Assets/Effects/bullet_hole_0.png"),
	preload("res://Assets/Effects/bullet_hole_1.png"),
	preload("res://Assets/Effects/bullet_hole_2.png"),
	preload("res://Assets/Effects/bullet_hole_3.png")
]

func _ready() -> void:
	texture_albedo = TEXTURES.pick_random()
	
	# Randomize scale slightly for organic feel
	var noise = randf_range(0.8, 1.3)
	size *= noise
	
	# Auto-destroy timer is already connected in the scene file
