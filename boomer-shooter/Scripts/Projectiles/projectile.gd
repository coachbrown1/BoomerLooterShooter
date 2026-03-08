extends Area3D
class_name Projectile

@export var speed: float = 10.0
@export var damage: int = 10
@export var lifetime: float = 5.0

var direction: Vector3 = Vector3.ZERO

func _ready() -> void:
	monitoring = true
	area_entered.connect(_on_area_entered)
	body_entered.connect(_on_body_entered)
	
	# Orient sprites: arrow tip is +X in the texture
	# We want it to point towards -Z (Godot 3D forward)
	# Sprite_H is horizontal (rotated around Y)
	# Sprite_V is vertical (rotated around Z)
	for child in get_children():
		if child is Sprite3D:
			child.rotation_degrees.y = -90
			if child.name == "Sprite_V":
				child.rotation_degrees.x = 90
	
	await get_tree().create_timer(lifetime).timeout
	queue_free()

func _physics_process(delta: float) -> void:
	if direction != Vector3.ZERO:
		global_translate(direction * speed * delta)

func _on_area_entered(area: Area3D) -> void:
	if area is HitboxComponent:
		# If we hit the player's hitbox
		if area.health_component and area.owner.is_in_group("player"):
			area.health_component.take_damage(damage)
			queue_free()

func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		if body.has_method("take_damage"):
			body.take_damage(damage)
		queue_free()
	elif body is StaticBody3D or body is CSGBox3D: # Walls/floor
		queue_free()
