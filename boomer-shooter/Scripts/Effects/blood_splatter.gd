extends Decal

const TEXTURES = [
	preload("res://Assets/Effects/blood_splatter_0.png"),
	preload("res://Assets/Effects/blood_splatter_1.png"),
	preload("res://Assets/Effects/blood_splatter_2.png"),
	preload("res://Assets/Effects/blood_splatter_3.png")
]

func _ready() -> void:
	texture_albedo = TEXTURES.pick_random()
	
	# Randomize scale (blood pools are often wider)
	var noise = randf_range(1.0, 1.8)
	size *= noise
    # Variation in "wetness" blend
	albedo_mix = randf_range(0.85, 1.0)
	
	var timer = get_tree().create_timer(30.0) # Blood stays longer than holes
	timer.timeout.connect(queue_free)
