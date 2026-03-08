extends Sprite3D
class_name BillboardSprite

@export var animate: bool = true:
	set(value):
		animate = value
		if animate:
			timer = 0.0
@export var frames_per_sec: float = 6.0
@export var total_frames: int = 4
@export var bounce_walk_mode: bool = false
@export var bounce_amplitude: float = 0.1
@export var bounce_tilt_degrees: float = 3.0

var current_frame: int = 0
var timer: float = 0.0
var walk_step: int = 0
var base_y: float = 0.0

func _ready() -> void:
	billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	# Respect whatever hframes was set on the node; override total_frames if needed
	if hframes > 1:
		total_frames = hframes
	frame = 0
	
	if material_override:
		material_override = material_override.duplicate()
		material_override.set_shader_parameter("texture_albedo", texture)
		
	base_y = position.y


func _process(delta: float) -> void:
	if not animate or total_frames <= 1:
		if bounce_walk_mode:
			frame = 0 # Idle pose
			rotation_degrees.z = 0.0
			position.y = base_y
		return
		
	timer += delta
	if timer >= 1.0 / frames_per_sec:
		timer -= 1.0 / frames_per_sec
		
		if bounce_walk_mode:
			# Bounce Walk Mode
			frame = 1 # Force walk pose
			walk_step += 1
			# Tilt every beat
			if walk_step % 2 == 1:
				rotation_degrees.z = bounce_tilt_degrees
				position.y = base_y + bounce_amplitude
			else:
				rotation_degrees.z = -bounce_tilt_degrees
				position.y = base_y
		else:
			# Standard Animation Mode
			# 0, 1: Walk/Idle cycle
			# 2: Attack frame
			# 3: Hurt frame
			# 4: Death frame
			var cycle_limit = total_frames
			if total_frames >= 4:
				cycle_limit = 2
			
			current_frame = (current_frame + 1) % cycle_limit
			frame = current_frame
