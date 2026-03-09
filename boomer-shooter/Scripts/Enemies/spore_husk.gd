extends EnemyBase
class_name SporeHusk

@export var aoe_radius: float = 3.5
@export var telegraph_color: Color = Color(0.45, 0.95, 0.55, 0.45)
@export var burst_color: Color = Color(0.7, 1.0, 0.75, 0.9)
@export var telegraph_height: float = 0.05
@export var telegraph_expand_speed: float = 1.0

var _aoe_telegraph: MeshInstance3D
var _aoe_burst: GPUParticles3D

func _ready() -> void:
	super._ready()
	_setup_aoe_vfx()

func _process_windup_effect() -> void:
	# Pulse slightly during windup to indicate an explosion
	var pulse = 1.0 + sin(_attack_timer * 20.0) * 0.1
	billboard_sprite.scale = Vector3(pulse, pulse, pulse)

	if _aoe_telegraph:
		_aoe_telegraph.visible = true
		var t := clampf(_attack_timer / maxf(windup_time, 0.001), 0.0, 1.0)
		var scale_value := lerpf(0.2, 1.0, t * telegraph_expand_speed)
		_aoe_telegraph.scale = Vector3(scale_value, 1.0, scale_value)

func _execute_attack() -> void:
	# Reset scale
	billboard_sprite.scale = Vector3.ONE
	if _aoe_telegraph:
		_aoe_telegraph.visible = false
		_aoe_telegraph.scale = Vector3(0.2, 1.0, 0.2)

	# AoE Damage
	if player:
		var dist = global_position.distance_to(player.global_position)
		if dist <= aoe_radius:
			if player.has_method("take_damage"):
				player.take_damage(attack_damage)

	_play_burst_vfx()

	# Transition to COOLDOWN state since we're bypassing super._execute_attack()
	current_state = State.COOLDOWN
	billboard_sprite.animate = true

func _setup_aoe_vfx() -> void:
	var telegraph_mesh := CylinderMesh.new()
	telegraph_mesh.top_radius = aoe_radius
	telegraph_mesh.bottom_radius = aoe_radius
	telegraph_mesh.height = telegraph_height

	_aoe_telegraph = MeshInstance3D.new()
	_aoe_telegraph.name = "AoeTelegraph"
	_aoe_telegraph.mesh = telegraph_mesh
	_aoe_telegraph.position = Vector3(0.0, telegraph_height * 0.5 + 0.02, 0.0)
	_aoe_telegraph.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_aoe_telegraph.visible = false
	_aoe_telegraph.scale = Vector3(0.2, 1.0, 0.2)
	add_child(_aoe_telegraph)

	var telegraph_material := StandardMaterial3D.new()
	telegraph_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	telegraph_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	telegraph_material.albedo_color = telegraph_color
	telegraph_material.emission_enabled = true
	telegraph_material.emission = telegraph_color
	telegraph_material.emission_energy_multiplier = 1.2
	telegraph_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_aoe_telegraph.material_override = telegraph_material

	_aoe_burst = GPUParticles3D.new()
	_aoe_burst.name = "AoeBurst"
	_aoe_burst.amount = 80
	_aoe_burst.lifetime = 0.55
	_aoe_burst.one_shot = true
	_aoe_burst.explosiveness = 1.0
	_aoe_burst.emitting = false
	_aoe_burst.visibility_aabb = AABB(Vector3(-aoe_radius, 0.0, -aoe_radius), Vector3(aoe_radius * 2.0, 2.0, aoe_radius * 2.0))
	_aoe_burst.draw_order = GPUParticles3D.DRAW_ORDER_INDEX
	add_child(_aoe_burst)

	var proc_mat := ParticleProcessMaterial.new()
	proc_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	proc_mat.emission_sphere_radius = aoe_radius * 0.35
	proc_mat.direction = Vector3(0.0, 1.0, 0.0)
	proc_mat.spread = 35.0
	proc_mat.initial_velocity_min = 2.0
	proc_mat.initial_velocity_max = 5.5
	proc_mat.gravity = Vector3(0.0, -4.0, 0.0)
	proc_mat.scale_min = 0.4
	proc_mat.scale_max = 1.2
	proc_mat.color = burst_color
	proc_mat.color_ramp = _build_spore_color_ramp()
	_aoe_burst.process_material = proc_mat

	var quad := QuadMesh.new()
	quad.size = Vector2(0.35, 0.35)
	_aoe_burst.draw_pass_1 = quad

func _play_burst_vfx() -> void:
	if _aoe_burst == null:
		return
	_aoe_burst.restart()
	_aoe_burst.emitting = true

func _build_spore_color_ramp() -> GradientTexture1D:
	var gradient := Gradient.new()
	gradient.add_point(0.0, Color(burst_color.r, burst_color.g, burst_color.b, 0.9))
	gradient.add_point(0.6, Color(burst_color.r, burst_color.g, burst_color.b, 0.55))
	gradient.add_point(1.0, Color(burst_color.r, burst_color.g, burst_color.b, 0.0))
	var tex := GradientTexture1D.new()
	tex.gradient = gradient
	return tex
