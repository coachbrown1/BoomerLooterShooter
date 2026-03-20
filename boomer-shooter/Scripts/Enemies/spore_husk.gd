extends EnemyBase
class_name SporeHusk

@export var aoe_radius: float = 3.5
@export var telegraph_color: Color = Color(0.45, 0.95, 0.55, 0.45)
@export var burst_color: Color = Color(0.7, 1.0, 0.75, 0.9)
@export var telegraph_height: float = 0.05
@export var telegraph_expand_speed: float = 1.0

var _aoe_telegraph: MeshInstance3D
var _aoe_fill: MeshInstance3D
var _aoe_burst: GPUParticles3D
var _aoe_mist: GPUParticles3D
var _aoe_ring: GPUParticles3D
var _windup_particles: GPUParticles3D

const TEX_SPORE = preload("res://Assets/Effects/vfx_spore.png")
const TEX_MIST = preload("res://Assets/Effects/vfx_mist.png")
const TEX_RING = preload("res://Assets/Effects/vfx_ring.png")
const TEX_FILL = preload("res://Assets/Effects/vfx_circle_fill.png")

func _ready() -> void:
	super._ready()
	_setup_aoe_vfx()

func _process_windup_effect() -> void:
	# Pulse slightly during windup to indicate an explosion
	var pulse = 1.0 + sin(_attack_timer * 20.0) * 0.1
	billboard_sprite.scale = get_billboard_scale_with_multiplier(pulse)

	if _aoe_telegraph:
		_aoe_telegraph.visible = true
		_aoe_fill.visible = true
		var t := clampf(_attack_timer / maxf(windup_time, 0.001), 0.0, 1.0)
		
		# Telegraph grows and pulses
		var t_pulse := 1.0 + sin(_attack_timer * 15.0) * 0.05
		_aoe_telegraph.scale = Vector3(t_pulse, 1.0, t_pulse)
		
		# Fill expands
		var fill_scale := lerpf(0.01, 1.0, t)
		_aoe_fill.scale = Vector3(fill_scale, 1.0, fill_scale)
		_aoe_fill.material_override.albedo_color.a = t * 0.5
		
		if not _windup_particles.emitting:
			_windup_particles.emitting = true

func _execute_attack() -> void:
	# Reset scale
	billboard_sprite.scale = get_billboard_scale_with_multiplier()
	if _aoe_telegraph:
		_aoe_telegraph.visible = false
		_aoe_fill.visible = false
	
	if _windup_particles:
		_windup_particles.emitting = false

	# AoE Damage
	if player:
		var dist_squared = global_position.distance_squared_to(player.global_position)
		if dist_squared <= aoe_radius * aoe_radius:
			if player.has_method("take_damage"):
				player.take_damage(attack_damage)

	_play_burst_vfx()

	# Transition to COOLDOWN state since we're bypassing super._execute_attack()
	current_state = State.COOLDOWN
	billboard_sprite.animate = true

func _setup_aoe_vfx() -> void:
	# 1. Telegraph Ring (The Border)
	var ring_mesh := QuadMesh.new()
	ring_mesh.size = Vector2(aoe_radius * 2.1, aoe_radius * 2.1)
	ring_mesh.orientation = PlaneMesh.FACE_Y

	_aoe_telegraph = MeshInstance3D.new()
	_aoe_telegraph.name = "AoeTelegraph"
	_aoe_telegraph.mesh = ring_mesh
	_aoe_telegraph.position = Vector3(0.0, 0.05, 0.0)
	_aoe_telegraph.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_aoe_telegraph.visible = false
	add_child(_aoe_telegraph)

	var ring_mat := StandardMaterial3D.new()
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_mat.blend_mode = StandardMaterial3D.BLEND_MODE_ADD
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.albedo_texture = TEX_RING
	ring_mat.albedo_color = telegraph_color
	ring_mat.emission_enabled = true
	ring_mat.emission = telegraph_color
	ring_mat.emission_energy_multiplier = 2.0
	_aoe_telegraph.material_override = ring_mat

	# 2. Telegraph Fill (The internal growth)
	_aoe_fill = MeshInstance3D.new()
	_aoe_fill.name = "AoeFill"
	_aoe_fill.mesh = ring_mesh
	_aoe_fill.position = Vector3(0.0, 0.04, 0.0)
	_aoe_fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_aoe_fill.visible = false
	add_child(_aoe_fill)

	var fill_mat := StandardMaterial3D.new()
	fill_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fill_mat.blend_mode = StandardMaterial3D.BLEND_MODE_ADD
	fill_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fill_mat.albedo_texture = TEX_FILL
	fill_mat.albedo_color = Color(telegraph_color.r, telegraph_color.g, telegraph_color.b, 0.0)
	_aoe_fill.material_override = fill_mat

	# 3. Spore Burst (Primary Particles)
	_aoe_burst = GPUParticles3D.new()
	_aoe_burst.name = "AoeBurst"
	_aoe_burst.amount = 120
	_aoe_burst.lifetime = 0.8
	_aoe_burst.one_shot = true
	_aoe_burst.explosiveness = 1.0
	_aoe_burst.emitting = false
	_aoe_burst.visibility_aabb = AABB(Vector3(-5, -2, -5), Vector3(10, 10, 10))
	add_child(_aoe_burst)

	var burst_proc := ParticleProcessMaterial.new()
	burst_proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	burst_proc.emission_sphere_radius = 0.5
	burst_proc.direction = Vector3(0, 1, 0)
	burst_proc.spread = 90.0
	burst_proc.initial_velocity_min = 4.0
	burst_proc.initial_velocity_max = 8.0
	burst_proc.gravity = Vector3(0, -9.8, 0)
	burst_proc.damping_min = 2.0
	burst_proc.damping_max = 4.0
	burst_proc.scale_min = 0.5
	burst_proc.scale_max = 1.5
	burst_proc.angle_min = -180.0
	burst_proc.angle_max = 180.0
	burst_proc.color_ramp = _build_spore_color_ramp()
	_aoe_burst.process_material = burst_proc

	var spore_draw := QuadMesh.new()
	spore_draw.size = Vector2(0.3, 0.3)
	var spore_mat := StandardMaterial3D.new()
	spore_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	spore_mat.blend_mode = StandardMaterial3D.BLEND_MODE_ADD
	spore_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spore_mat.albedo_texture = TEX_SPORE
	spore_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	_aoe_burst.draw_pass_1 = spore_draw
	_aoe_burst.material_override = spore_mat

	# 4. Shockwave Ring (Expanding Wave)
	_aoe_ring = GPUParticles3D.new()
	_aoe_ring.name = "AoeRing"
	_aoe_ring.amount = 1
	_aoe_ring.lifetime = 0.4
	_aoe_ring.one_shot = true
	_aoe_ring.emitting = false
	add_child(_aoe_ring)

	var ring_proc := ParticleProcessMaterial.new()
	ring_proc.gravity = Vector3.ZERO
	ring_proc.scale_min = 0.1
	ring_proc.scale_max = 0.1 # Start small
	# Scale curve
	var scale_curve := CurveTexture.new()
	scale_curve.curve = Curve.new()
	scale_curve.curve.add_point(Vector2(0, 0.1))
	scale_curve.curve.add_point(Vector2(1, aoe_radius * 2.2))
	ring_proc.scale_curve = scale_curve
	# Alpha curve
	var alpha_curve := _build_alpha_curve(1.0, 0.0)
	ring_proc.color_ramp = alpha_curve
	_aoe_ring.process_material = ring_proc

	var wave_mesh := QuadMesh.new()
	wave_mesh.size = Vector2(1, 1)
	wave_mesh.orientation = PlaneMesh.FACE_Y
	var wave_mat := StandardMaterial3D.new()
	wave_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wave_mat.blend_mode = StandardMaterial3D.BLEND_MODE_ADD
	wave_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	wave_mat.albedo_texture = TEX_RING
	wave_mat.albedo_color = burst_color
	wave_mat.emission_enabled = true
	wave_mat.emission = burst_color
	wave_mat.emission_energy_multiplier = 3.0
	_aoe_ring.draw_pass_1 = wave_mesh
	_aoe_ring.material_override = wave_mat

	# 5. Toxic Mist (Lingering)
	_aoe_mist = GPUParticles3D.new()
	_aoe_mist.name = "AoeMist"
	_aoe_mist.amount = 15
	_aoe_mist.lifetime = 2.5
	_aoe_mist.one_shot = true
	_aoe_mist.explosiveness = 0.8
	_aoe_mist.emitting = false
	_aoe_mist.visibility_aabb = AABB(Vector3(-aoe_radius, -2, -aoe_radius), Vector3(aoe_radius*2, 5, aoe_radius*2))
	add_child(_aoe_mist)

	var mist_proc := ParticleProcessMaterial.new()
	mist_proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mist_proc.emission_sphere_radius = aoe_radius * 0.8
	mist_proc.direction = Vector3(0, 1, 0)
	mist_proc.spread = 180.0
	mist_proc.initial_velocity_min = 0.5
	mist_proc.initial_velocity_max = 1.5
	mist_proc.gravity = Vector3(0, 0.2, 0)
	mist_proc.damping_min = 0.5
	mist_proc.damping_max = 1.0
	mist_proc.scale_min = 2.0
	mist_proc.scale_max = 4.0
	mist_proc.angle_min = -180.0
	mist_proc.angle_max = 180.0
	mist_proc.color = Color(burst_color.r, burst_color.g, burst_color.b, 1.0)
	mist_proc.color_ramp = _build_alpha_curve(0.5, 0.0)
	mist_proc.anim_speed_min = 1.0
	mist_proc.anim_speed_max = 1.5
	_aoe_mist.process_material = mist_proc

	var mist_draw := QuadMesh.new()
	mist_draw.size = Vector2(1, 1)
	var mist_mat := StandardMaterial3D.new()
	mist_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mist_mat.blend_mode = StandardMaterial3D.BLEND_MODE_ADD
	mist_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mist_mat.albedo_texture = TEX_MIST
	mist_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mist_mat.particles_anim_h_frames = 4
	mist_mat.particles_anim_v_frames = 3
	mist_mat.particles_anim_loop = false
	_aoe_mist.draw_pass_1 = mist_draw
	_aoe_mist.material_override = mist_mat

	# 6. Windup "Charging" Particles
	_windup_particles = GPUParticles3D.new()
	_windup_particles.name = "WindupParticles"
	_windup_particles.amount = 40
	_windup_particles.lifetime = 0.6
	_windup_particles.emitting = false
	add_child(_windup_particles)

	var w_proc := ParticleProcessMaterial.new()
	w_proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	w_proc.emission_ring_axis = Vector3(0, 1, 0)
	w_proc.emission_ring_height = 0.1
	w_proc.emission_ring_radius = aoe_radius * 1.5
	w_proc.emission_ring_inner_radius = aoe_radius
	w_proc.direction = Vector3(0, 1, 0) # Overridden by attract
	w_proc.gravity = Vector3.ZERO
	w_proc.radial_accel_min = -10.0 # Pull inwards
	w_proc.radial_accel_max = -5.0
	w_proc.scale_min = 0.2
	w_proc.scale_max = 0.5
	w_proc.color = telegraph_color
	_windup_particles.process_material = w_proc
	_windup_particles.draw_pass_1 = spore_draw
	_windup_particles.material_override = spore_mat

func _play_burst_vfx() -> void:
	if _aoe_burst:
		_aoe_burst.restart()
		_aoe_burst.emitting = true
	if _aoe_ring:
		_aoe_ring.restart()
		_aoe_ring.emitting = true
	if _aoe_mist:
		_aoe_mist.restart()
		_aoe_mist.emitting = true

func _build_spore_color_ramp() -> GradientTexture1D:
	var gradient := Gradient.new()
	gradient.add_point(0.0, Color(1, 1, 1, 1)) # White hot at center burst
	gradient.add_point(0.2, burst_color)
	gradient.add_point(0.7, Color(burst_color.r, burst_color.g, burst_color.b, 0.6))
	gradient.add_point(1.0, Color(burst_color.r, burst_color.g, burst_color.b, 0.0))
	var tex := GradientTexture1D.new()
	tex.gradient = gradient
	return tex

func _build_alpha_curve(start_alpha: float, end_alpha: float) -> GradientTexture1D:
	var gradient := Gradient.new()
	gradient.add_point(0.0, Color(1, 1, 1, start_alpha))
	gradient.add_point(1.0, Color(1, 1, 1, end_alpha))
	var tex := GradientTexture1D.new()
	tex.gradient = gradient
	return tex
