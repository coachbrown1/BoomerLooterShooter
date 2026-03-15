extends Projectile
class_name EnergyOrb

const HAZARD_SCENE = preload("res://Scenes/Effects/mage_hazard_pool.tscn")

func _trigger_impact() -> void:
	if _did_impact:
		return
	_did_impact = true

	set_deferred("monitoring", false)
	set_deferred("monitorable", false)
	set_deferred("collision_layer", 0)
	set_deferred("collision_mask", 0)

	_spawn_hazard()
	call_deferred("queue_free")

func _spawn_hazard() -> void:
	var hazard := HAZARD_SCENE.instantiate()
	get_tree().current_scene.add_child(hazard)

	# Raycast down from impact point to find the floor
	var origin := global_position + Vector3.UP * 0.5
	var end := global_position + Vector3.DOWN * 4.0
	var space := get_world_3d().direct_space_state
	if space:
		var query := PhysicsRayQueryParameters3D.create(origin, end)
		query.collision_mask = 1  # static world
		var result := space.intersect_ray(query)
		if result:
			hazard.global_position = result.position
			return

	hazard.global_position = global_position
