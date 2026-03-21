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
var network_visual_only: bool = false
var _did_impact: bool = false

const EXPLOSION_SCENE = preload("res://Scenes/Effects/fireball_explosion.tscn")

func _ready() -> void:
	if network_visual_only:
		monitoring = false
		monitorable = false
		collision_layer = 0
		collision_mask = 0
	else:
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
	if _did_impact: return
	_did_impact = true
	# Stop participating in area/body events before freeing to avoid Jolt flush warnings.
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)
	set_deferred("collision_layer", 0)
	set_deferred("collision_mask", 0)
	
	if explode_on_impact:
		call_deferred("_explode")
	call_deferred("queue_free")

func _explode() -> void:
	# Visual Explosion
	var expl = EXPLOSION_SCENE.instantiate()
	get_tree().current_scene.add_child(expl)
	expl.global_position = global_position

	if network_visual_only:
		return
	
	# Area damage logic
	var space_state = get_world_3d().direct_space_state
	if not space_state:
		return
		
	var shape = SphereShape3D.new()
	shape.radius = explosion_radius

	var query = PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis(), global_position)
	query.collide_with_areas = true
	query.collide_with_bodies = true
	query.collision_mask = 0xFFFFFFFF # Match everything, filtered below
	
	var results = space_state.intersect_shape(query)

	# Track damaged entities (not just colliders) to avoid double-hits
	var damaged_entities = []
	
	for result in results:
		var collider = result.collider
		if not is_instance_valid(collider):
			continue

		var target_entity := _resolve_damage_target(collider)
		if target_entity and target_entity not in damaged_entities:
			# Skip damaging the shooter
			if shooter and (target_entity == shooter or shooter.is_ancestor_of(target_entity)):
				continue

			_apply_damage_to_target(target_entity, explosion_damage)
			damaged_entities.append(target_entity)

func _on_area_entered(area: Area3D) -> void:
	if _did_impact: return
	if shooter and (area == shooter or shooter.is_ancestor_of(area)):
		return

	if network_visual_only:
		_trigger_impact()
		return

	var target_entity := _resolve_damage_target(area)
	if target_entity != null:
		_apply_damage_to_target(target_entity, damage)
		_trigger_impact()

func _on_body_entered(body: Node3D) -> void:
	if _did_impact: return
	if shooter and body == shooter:
		return

	if network_visual_only:
		_trigger_impact()
		return

	var target_entity := _resolve_damage_target(body)
	if target_entity != null:
		_apply_damage_to_target(target_entity, damage)
		_trigger_impact()
	elif body is StaticBody3D or body is CSGBox3D or body is GridMap: # Walls/floor
		_trigger_impact()

func _resolve_damage_target(collider: Node) -> Node:
	var current: Node = collider
	while current != null:
		if current is HitboxComponent:
			var hitbox: HitboxComponent = current
			var owner_node := hitbox.get_parent()
			if owner_node != null and owner_node.has_method("take_damage"):
				return owner_node
			return hitbox
		if current.has_method("take_damage"):
			return current
		current = current.get_parent()
	return null

func _apply_damage_to_target(target: Node, amount: int) -> void:
	if target == null:
		return
	if target is HitboxComponent:
		var hitbox: HitboxComponent = target
		if hitbox.health_component != null:
			hitbox.health_component.take_damage(amount)
		return
	if target.has_method("take_damage"):
		target.take_damage(amount)
