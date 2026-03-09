extends Node3D

@export var emission_color: Color = Color(0.3, 1.0, 0.6)
@export var particle_amount: int = 12
@export var radius: float = 1.0
@export var intensity: float = 1.0

@export var enable_particles: bool = true

var _spores: GPUParticles3D
var _glow: MeshInstance3D

const TEX_SPORE = preload("res://Assets/Effects/vfx_spore.png")

func _ready() -> void:
	_setup_glow()
	if enable_particles and particle_amount > 0:
		_setup_particles()

func _setup_glow() -> void:
	# Add a soft glowing radial billboard
	var mesh := QuadMesh.new()
	mesh.size = Vector2(radius * 3.0, radius * 3.0)
	
	_glow = MeshInstance3D.new()
	_glow.name = "PropGlow"
	_glow.mesh = mesh
	_glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_glow.position.y = radius * 0.8
	add_child(_glow)
	
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = StandardMaterial3D.BLEND_MODE_ADD
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(emission_color.r, emission_color.g, emission_color.b, 0.15 * intensity)
	
	# Use a simple radial gradient if possible, but for now we'll just use a soft texture if we had one
	# Or just a solid color with alpha gradient (not easy in StandardMaterial3D without a texture)
	# Let's use the ring texture but very blurred/transparent
	mat.albedo_texture = preload("res://Assets/Effects/vfx_circle_fill.png")
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_glow.material_override = mat
	
	# Pulse the glow
	var tween = create_tween().set_loops()
	tween.tween_property(mat, "albedo_color:a", 0.05 * intensity, 2.0).set_trans(Tween.TRANS_SINE)
	tween.tween_property(mat, "albedo_color:a", 0.2 * intensity, 2.0).set_trans(Tween.TRANS_SINE)

func _setup_particles() -> void:
	_spores = GPUParticles3D.new()
	_spores.name = "SporeParticles"
	_spores.amount = particle_amount
	_spores.lifetime = 8.0
	_spores.preprocess = 4.0
	_spores.visibility_aabb = AABB(Vector3(-2, -2, -2), Vector3(4, 10, 4))
	add_child(_spores)

	var proc := ParticleProcessMaterial.new()
	proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	proc.emission_sphere_radius = radius
	proc.direction = Vector3(0, 1, 0)
	proc.spread = 45.0 # Narrower spread to encourage vertical travel
	proc.gravity = Vector3(0, 0.2, 0) # Increased lift
	proc.initial_velocity_min = 0.2
	proc.initial_velocity_max = 0.6
	proc.damping_min = 0.05
	proc.damping_max = 0.1
	proc.scale_min = 0.1
	proc.scale_max = 0.3
	proc.angle_min = -180.0
	proc.angle_max = 180.0
	
	# Color and Alpha
	proc.color = Color(emission_color.r, emission_color.g, emission_color.b, 0.8)
	var grad := Gradient.new()
	grad.add_point(0.0, Color(1, 1, 1, 0))
	grad.add_point(0.2, Color(1, 1, 1, 1))
	grad.add_point(0.8, Color(1, 1, 1, 1))
	grad.add_point(1.0, Color(1, 1, 1, 0))
	var tex := GradientTexture1D.new()
	tex.gradient = grad
	proc.color_ramp = tex
	
	_spores.process_material = proc

	var quad := QuadMesh.new()
	quad.size = Vector2(0.2, 0.2)
	_spores.draw_pass_1 = quad
	
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = StandardMaterial3D.BLEND_MODE_ADD
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_texture = TEX_SPORE
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	_spores.material_override = mat
