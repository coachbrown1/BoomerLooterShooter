extends EnemyBase
class_name DeathKnightBoss

## Death Knight Mini-Boss
## ─────────────────────────────────────────────────────────────────────────────
## Two-attack pattern:
##   MELEE  – Close-range slash.  Triggered when the player enters melee_range.
##   BEAM   – Ranged ice/magic beam fired from the chest.  Triggered at any
##            distance beyond melee_range up to beam_max_range, provided the
##            boss has line-of-sight.  A shake/bounce "tell" plays during the
##            full beam windup so the player has time to dodge.
## ─────────────────────────────────────────────────────────────────────────────

enum AttackType { MELEE, BEAM }

# ── Attack tuning ──────────────────────────────────────────────────────────
@export var melee_damage: int        = 30
@export var melee_range: float       = 2.5      # Max distance for a melee hit
@export var melee_windup_time: float = 0.55     # Quick wind-up for the slash

@export var beam_damage: int         = 45
@export var beam_max_range: float    = 18.0     # Max beam range
@export var beam_windup_time: float  = 2.4      # Long wind-up so player can react
@export var beam_cooldown: float     = 2.8      # Longer rest after firing beam

# ── Shake / tell effect (beam windup only) ────────────────────────────────
@export var shake_speed: float       = 16.0     # Oscillations per second
@export var shake_x_amp: float       = 0.06     # Horizontal pixel-shift amplitude
@export var shake_scale_amp: float   = 0.045    # Scale-pulse amplitude (0 = off)

# ── Spritesheet frame indices  (hframes=6, vframes=3) ─────────────────────
# Row 0 (frames  0-5) = IDLE animation
# Row 1 (frames  6-11) = WALK animation
# Row 2 (frames 12-17) = ATTACK animation
const FRAME_IDLE       := 0
const FRAME_WALK_FIRST := 6    # First frame of WALK row
const FRAME_WALK_COUNT := 6    # Number of walk frames
const FRAME_ATK_A      := 12   # Alternate between these two during beam windup
const FRAME_ATK_B      := 13
const FRAME_ATK_FIRE   := 14   # Shown at the moment of firing

const BEAM_SCENE := preload("res://Scenes/Projectiles/death_knight_beam.tscn")

# ── Runtime state ──────────────────────────────────────────────────────────
var _pending_attack: AttackType = AttackType.MELEE
var _is_beam_windup:   bool     = false
var _walk_anim_timer:  float    = 0.0
var _walk_frame_idx:   int      = 0
var _sprite_base_x:    float    = 0.0   # Neutral X of the Sprite3D (restored after shake)

# ── Client-proxy state (used only when _network_proxy_mode == true) ────────
# Received via snapshot; drive the shake/tell effect on remote clients.
var _proxy_is_beam_windup:    bool  = false
var _proxy_windup_progress:   float = 0.0


# ══════════════════════════════════════════════════════════════════════════════
#  INIT
# ══════════════════════════════════════════════════════════════════════════════

func _ready() -> void:
	super._ready()
	# Disable BillboardSprite auto-cycling; we drive every frame manually.
	billboard_sprite.animate       = false
	billboard_sprite.bounce_walk_mode = false
	billboard_sprite.frame         = FRAME_IDLE
	_sprite_base_x = billboard_sprite.position.x


# ══════════════════════════════════════════════════════════════════════════════
#  MANUAL ANIMATION  (runs every rendered frame via _process)
# ══════════════════════════════════════════════════════════════════════════════

func _process(delta: float) -> void:
	match current_state:
		State.CHASE:
			_walk_anim_timer += delta
			if _walk_anim_timer >= 1.0 / 5.0:   # 5 fps walk cycle
				_walk_anim_timer = 0.0
				_walk_frame_idx  = (_walk_frame_idx + 1) % FRAME_WALK_COUNT
				billboard_sprite.frame = FRAME_WALK_FIRST + _walk_frame_idx

		State.IDLE:
			billboard_sprite.frame = FRAME_IDLE
			_walk_anim_timer = 0.0

		_:
			pass  # WINDUP / ATTACK / COOLDOWN handled by their own paths


# ══════════════════════════════════════════════════════════════════════════════
#  MULTIPLAYER SNAPSHOT OVERRIDES
# ══════════════════════════════════════════════════════════════════════════════

func get_network_state_snapshot() -> Dictionary:
	var snap: Dictionary = super.get_network_state_snapshot()
	# Ship the beam windup progress so clients can replicate the shake tell.
	snap["dk_beam_windup"]     = _is_beam_windup
	snap["dk_windup_progress"] = clampf(
		_attack_timer / windup_time if current_state == State.WINDUP else 0.0,
		0.0, 1.0)
	return snap


func apply_network_state_snapshot(snapshot: Dictionary) -> void:
	super.apply_network_state_snapshot(snapshot)
	_proxy_is_beam_windup  = snapshot.get("dk_beam_windup",      false)
	_proxy_windup_progress = snapshot.get("dk_windup_progress",  0.0)


## Overrides the base class to:
##  1. Use hframes * vframes for the frame limit (fixes multi-row spritesheet clamping).
##  2. Replicate the beam-windup shake/tint on client proxies using wall-clock time
##     so clients see the tell even though their _attack_timer is frozen.
func _update_proxy_visual_state() -> void:
	if not _network_proxy_mode:
		return  # Non-proxy visuals are driven by _process() and attack overrides.

	# Apply the received animation frame (full range 0..hframes*vframes-1).
	var frame_limit := billboard_sprite.hframes * billboard_sprite.vframes - 1
	billboard_sprite.frame = clampi(_proxy_visual_frame, 0, frame_limit)
	if billboard_sprite.animate != _proxy_visual_animate:
		billboard_sprite.animate = _proxy_visual_animate

	if current_state == State.WINDUP and _proxy_is_beam_windup:
		# Drive shake with wall-clock time so it animates continuously even
		# though the proxy's _attack_timer doesn't advance.
		var t := Time.get_ticks_msec() * 0.001 * shake_speed * TAU
		var intensity := 1.0 + maxf(0.0, (_proxy_windup_progress - 0.6) / 0.4) * 3.0
		billboard_sprite.position.x = _sprite_base_x + sin(t) * shake_x_amp * intensity
		var pulse := 1.0 + sin(t * 0.7) * shake_scale_amp * intensity
		billboard_sprite.scale = Vector3(pulse, pulse, 1.0)
		var blue := lerpf(1.5, 3.0, _proxy_windup_progress)
		billboard_sprite.modulate = Color(0.7, 0.8, blue, 1.0)
	else:
		# Restore neutral sprite state once windup ends.
		billboard_sprite.position.x = _sprite_base_x
		billboard_sprite.scale      = Vector3(1.0, 1.0, 1.0)
		if current_state != State.DEAD:
			billboard_sprite.modulate = Color(1.0, 1.0, 1.0, 1.0)


# ══════════════════════════════════════════════════════════════════════════════
#  ATTACK SELECTION
# ══════════════════════════════════════════════════════════════════════════════

func _should_start_windup(dist_squared_to_player: float) -> bool:
	if player == null:
		return false

	# Close range: always slash
	if dist_squared_to_player <= pow(melee_range, 2):
		_pending_attack = AttackType.MELEE
		return true

	# Longer range: beam – only if we have clear line-of-sight
	if dist_squared_to_player <= pow(beam_max_range, 2):
		if _has_line_of_sight():
			_pending_attack = AttackType.BEAM
			return true

	return false


# ══════════════════════════════════════════════════════════════════════════════
#  WINDUP
# ══════════════════════════════════════════════════════════════════════════════

func _start_windup() -> void:
	_is_beam_windup = (_pending_attack == AttackType.BEAM)
	windup_time     = beam_windup_time if _is_beam_windup else melee_windup_time

	current_state  = State.WINDUP
	_attack_timer  = 0.0
	billboard_sprite.animate = false
	billboard_sprite.frame   = FRAME_ATK_A

	if _is_beam_windup:
		# Subtle blue tint shows power building up
		billboard_sprite.modulate = Color(0.8, 0.85, 1.5, 1.0)


func _process_windup_effect() -> void:
	if not _is_beam_windup:
		# Melee: quick step through early attack frames
		var t := _attack_timer / windup_time
		billboard_sprite.frame = FRAME_ATK_A + clampi(int(t * 3.0), 0, 2)
		return

	# ── Beam tell: bounce + shake ─────────────────────────────────────────
	var phase := _attack_timer * shake_speed * TAU
	var progress := _attack_timer / windup_time   # 0 → 1 over full windup

	# Intensity ramps up in the final 40 % of the windup
	var intensity := 1.0 + maxf(0.0, (progress - 0.6) / 0.4) * 3.0

	billboard_sprite.position.x = _sprite_base_x + sin(phase) * shake_x_amp * intensity

	var pulse := 1.0 + sin(phase * 0.7) * shake_scale_amp * intensity
	billboard_sprite.scale = Vector3(pulse, pulse, 1.0)

	# Flicker between two attack frames for a "charging" look
	billboard_sprite.frame = FRAME_ATK_A if fmod(_attack_timer * 6.0, 1.0) < 0.5 else FRAME_ATK_B

	# Deepen the blue tint as the shot nears
	var blue := lerpf(1.5, 3.0, progress)
	billboard_sprite.modulate = Color(0.7, 0.8, blue, 1.0)


# ══════════════════════════════════════════════════════════════════════════════
#  EXECUTE ATTACK
# ══════════════════════════════════════════════════════════════════════════════

func _execute_attack() -> void:
	# Restore sprite to neutral before anything else
	billboard_sprite.position.x = _sprite_base_x
	billboard_sprite.scale      = Vector3(1.0, 1.0, 1.0)
	billboard_sprite.modulate   = Color(1.0, 1.0, 1.0, 1.0)
	billboard_sprite.frame      = FRAME_ATK_FIRE

	if _pending_attack == AttackType.BEAM:
		_fire_beam()
		cooldown_time = beam_cooldown
	else:
		_fire_melee()
		cooldown_time = 1.2

	# Advance state directly (mirrors what super._execute_attack would do)
	# We do NOT call super here to avoid it re-enabling BillboardSprite auto-anim.
	current_state = State.ATTACK


# ── Melee ──────────────────────────────────────────────────────────────────

func _fire_melee() -> void:
	if not player:
		return
	var dist_sq := global_position.distance_squared_to(player.global_position)
	if dist_sq <= pow(melee_range + 0.5, 2):   # small lunge buffer
		if player.has_method("take_damage"):
			player.take_damage(melee_damage)


# ── Beam ───────────────────────────────────────────────────────────────────

func _fire_beam() -> void:
	if not player:
		return

	# Spawn point: chest height
	var spawn_pos := global_position + Vector3(0.0, actual_height * 0.60, 0.0)
	# Aim slightly above the player's base so beams aren't always ground-level
	var aim_pos   := player.global_position + Vector3(0.0, 1.0, 0.0)
	var dir       := (aim_pos - spawn_pos).normalized()

	# ── Raycast: find actual beam end (wall or open air) ─────────────────
	var space  := get_world_3d().direct_space_state
	var q      := PhysicsRayQueryParameters3D.create(
		spawn_pos, spawn_pos + dir * beam_max_range)
	q.collision_mask = 1          # world geometry only
	q.exclude        = [get_rid()]
	var hit    := space.intersect_ray(q)

	var beam_length := beam_max_range
	var hit_player  := false

	if hit.is_empty():
		# Nothing in the way – check if player is within range
		var pdist := spawn_pos.distance_to(aim_pos)
		if pdist <= beam_max_range:
			hit_player = true
	else:
		beam_length = spawn_pos.distance_to(hit.position)
		# Player is between boss and the wall → beam hits them
		var pdist := spawn_pos.distance_to(aim_pos)
		if pdist < beam_length:
			hit_player = true
			beam_length = pdist

	# ── Damage ───────────────────────────────────────────────────────────
	if hit_player and player.has_method("take_damage"):
		player.take_damage(beam_damage)

	# ── Spawn visual beam ─────────────────────────────────────────────────
	# beam_length must be set BEFORE add_child so _ready() sizes the mesh.
	var beam           := BEAM_SCENE.instantiate()
	beam.beam_length   = maxf(0.5, beam_length)
	get_parent().add_child(beam)
	beam.global_position = spawn_pos
	# look_at requires being in the tree (done after add_child)
	beam.look_at(spawn_pos + dir, Vector3.UP)

	# ── Broadcast beam visual to all remote clients ────────────────────────
	# The host already has the beam above; rpc_spawn_enemy_beam_visual uses
	# call_remote so only clients execute the spawn, avoiding a duplicate.
	if _dungeon_manager and _dungeon_manager.has_method("rpc_spawn_enemy_beam_visual"):
		_dungeon_manager.rpc("rpc_spawn_enemy_beam_visual", spawn_pos, dir, maxf(0.5, beam_length))

	# Brief bright flash on the boss sprite at the fire moment
	billboard_sprite.modulate = Color(0.5, 0.7, 2.5, 1.0)
	var tween := create_tween()
	tween.tween_property(billboard_sprite, "modulate", Color(1, 1, 1, 1), 0.25)


# ══════════════════════════════════════════════════════════════════════════════
#  HELPERS
# ══════════════════════════════════════════════════════════════════════════════

## Raycast from eye-level toward the player to check for obstructions.
func _has_line_of_sight() -> bool:
	if not player:
		return false
	var eye_pos  := global_position + Vector3(0.0, actual_height * 0.75, 0.0)
	var aim_pos  := player.global_position + Vector3(0.0, 1.0, 0.0)
	var space    := get_world_3d().direct_space_state
	var q        := PhysicsRayQueryParameters3D.create(eye_pos, aim_pos)
	q.collision_mask = 1      # world geometry only
	q.exclude        = [get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()
