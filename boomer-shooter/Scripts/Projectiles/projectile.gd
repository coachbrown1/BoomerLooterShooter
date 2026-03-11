extends Area3D
class_name Projectile

@export var speed: float = 10.0
@export var damage: int = 10
@export var lifetime: float = 5.0
@export var fall_gravity: float = 0.0
@export var explode_on_impact: bool = false
@export var explosion_radius: float = 3.0
@export var explosion_damage: int = 25

var direction: Vector3 = Vector3.ZERO
var velocity: Vector3 = Vector3.ZERO
var shooter: Node3D = null

const EXPLOSION_SCENE = preload("res://Scenes/Effects/fireball_explosion.tscn")

func _ready() -> void:
	monitoring = true
	area_entered.connect(_on_area_entered)
	body_entered.connect(_on_body_entered)
	
	velocity = direction.normalized() * speed

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
	if fall_gravity > 0.0:
		velocity.y -= fall_gravity * delta
		# Adjust orientation based on new velocity if it's an arrow
		var target_pos = global_position + velocity
		if velocity.normalized().abs().is_equal_approx(Vector3(0, 1, 0)):
			look_at(target_pos, Vector3.RIGHT)
		else:
			look_at(target_pos, Vector3.UP)

	global_translate(velocity * delta)

func _trigger_impact() -> void:
	if explode_on_impact:
		_explode()
	queue_free()

func _explode() -> void:
	# Visual Explosion
	var expl = EXPLOSION_SCENE.instantiate()
	get_tree().current_scene.add_child(expl)
	expl.global_position = global_position
	
	# Area damage logic
	var space_state = get_world_3d().direct_space_state
	# Create sphere shape for intersection
	var shape = SphereShape3D.new()
	shape.radius = explosion_radius

	var params = PhysicsShapeQueryParameters3D.new()
	params.shape = shape
	params.transform = Transform3D(Basis(), global_position)
	params.collide_with_areas = true
	params.collision_mask = 0xFFFFFFFF

	var results = space_state.intersect_shape(params)

	# We want to damage hitboxes and player
	var damaged_nodes = []
	for result in results:
		var collider = result.collider
		if collider is HitboxComponent and collider not in damaged_nodes:
			if collider.health_component:
				collider.health_component.take_damage(explosion_damage)
			damaged_nodes.append(collider)
		elif collider.is_in_group("player") and collider not in damaged_nodes:
			if collider.has_method("take_damage"):
				collider.take_damage(explosion_damage)
				damaged_nodes.append(collider)

func _on_area_entered(area: Area3D) -> void:
	if shooter and shooter.is_ancestor_of(area):
		return

	if area is HitboxComponent:
		if not explode_on_impact:
			# Direct hit
			if area.health_component:
				area.health_component.take_damage(damage)
		_trigger_impact()

func _on_body_entered(body: Node3D) -> void:
	if shooter and body == shooter:
		return

	if body.is_in_group("player"):
		if not explode_on_impact:
			if body.has_method("take_damage"):
				body.take_damage(damage)
		_trigger_impact()
	elif body is StaticBody3D or body is CSGBox3D: # Walls/floor
		_trigger_impact()
