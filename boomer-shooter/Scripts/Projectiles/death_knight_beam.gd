extends Node3D
class_name DeathKnightBeam

## Visual-only beam fired by the Death Knight Boss.
## Damage is resolved by a raycast in death_knight_boss.gd before this node is
## spawned, so this scene is purely cosmetic.  Set beam_length before add_child.

## Set by the boss before add_child so _ready() can size the geometry.
var beam_length: float = 12.0

@export var beam_width: float = 0.22
@export var lifetime: float = 0.65
@export var beam_color: Color = Color(0.35, 0.55, 2.2, 1.0)
@export var emit_multiplier: float = 3.5

var _mat: StandardMaterial3D = null


func _ready() -> void:
	_build_geometry()
	_start_fade()


func _build_geometry() -> void:
	# ── Emissive beam body ──────────────────────────────────────────────────
	_mat = StandardMaterial3D.new()
	_mat.transparency           = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.shading_mode           = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.albedo_color           = Color(beam_color.r, beam_color.g, beam_color.b, 0.9)
	_mat.emission_enabled       = true
	_mat.emission               = beam_color
	_mat.emission_energy_multiplier = emit_multiplier

	var box  := BoxMesh.new()
	box.size     = Vector3(beam_width, beam_width, beam_length)
	box.material = _mat

	var mesh_inst := MeshInstance3D.new()
	mesh_inst.mesh     = box
	# Offset so the near-end sits at the spawn origin and the beam extends along -Z
	mesh_inst.position = Vector3(0.0, 0.0, -beam_length * 0.5)
	add_child(mesh_inst)

	# ── Impact flash sphere at the far end ──────────────────────────────────
	var tip_mat := StandardMaterial3D.new()
	tip_mat.shading_mode           = BaseMaterial3D.SHADING_MODE_UNSHADED
	tip_mat.albedo_color           = Color(0.8, 0.9, 1.0, 1.0)
	tip_mat.emission_enabled       = true
	tip_mat.emission               = Color(1.0, 1.0, 1.0, 1.0)
	tip_mat.emission_energy_multiplier = 6.0

	var sphere     := SphereMesh.new()
	sphere.radius  = beam_width * 1.8
	sphere.height  = beam_width * 3.6
	sphere.material = tip_mat

	var tip_inst := MeshInstance3D.new()
	tip_inst.mesh     = sphere
	tip_inst.position = Vector3(0.0, 0.0, -beam_length)
	add_child(tip_inst)

	# ── Ambient glow light at the origin ────────────────────────────────────
	var light := OmniLight3D.new()
	light.light_color   = Color(0.4, 0.6, 1.0)
	light.light_energy  = 5.0
	light.omni_range    = 8.0
	add_child(light)


func _start_fade() -> void:
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(_mat, "albedo_color:a",             0.0,  lifetime)
	tween.tween_property(_mat, "emission_energy_multiplier", 0.0,  lifetime)
	# Wait for both tweens, then free
	tween.set_parallel(false)
	tween.tween_callback(queue_free)
