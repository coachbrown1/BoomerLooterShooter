extends EnemyBase
class_name DeathKnightBoss

## Death Knight Boss – Phased decision tree
## ─────────────────────────────────────────────────────────────────────────────
## Phase 1 (100 % → 50 %):
##   Chase + melee.  Every 10 % HP lost → dash away, beam, resume chase.
## Phase 2 (50 % → 15 %):
##   Dash attacks to close distance + melee.  Same 10 % threshold response.
## Phase 3 (< 15 %):
##   Constant loop: dash to open space → beam attack → repeat until death.
## ─────────────────────────────────────────────────────────────────────────────

enum AttackType { MELEE, BEAM }
enum BossPhase  { ONE, TWO, THREE }
enum DashMode   { NONE, AWAY, ATTACK, OPEN_SPACE }

# ── Attack tuning ──────────────────────────────────────────────────────────
@export var melee_damage: int        = 30
@export var melee_range: float       = 2.5
@export var melee_windup_time: float = 0.55

@export var beam_damage: int         = 45
@export var beam_max_range: float    = 18.0
@export var beam_windup_time: float  = 2.4
@export var beam_cooldown: float     = 2.8

# ── Dash tuning ────────────────────────────────────────────────────────────
@export var dash_away_speed: float      = 18.0
@export var dash_away_distance: float   = 8.0
@export var dash_attack_speed: float    = 22.0
@export var dash_attack_distance: float = 7.0
@export var dash_open_speed: float      = 16.0
@export var dash_open_distance: float   = 6.0

# ── Shake / tell (beam windup only) ───────────────────────────────────────
@export var shake_speed: float       = 16.0
@export var shake_x_amp: float       = 0.06
@export var shake_scale_amp: float   = 0.045

# ── Spritesheet frame indices  (hframes=6, vframes=4) ─────────────────────
const FRAME_IDLE       := 0
const FRAME_WALK_FIRST := 6
const FRAME_WALK_COUNT := 6
const FRAME_ATK_A      := 12
const FRAME_ATK_B      := 13
const FRAME_ATK_FIRE   := 18

const BEAM_SCENE := preload("res://Scenes/Projectiles/death_knight_beam.tscn")

# ── Phase / threshold state ────────────────────────────────────────────────
var _phase: BossPhase    = BossPhase.ONE
## Next HP-percentage threshold that triggers a dash-away + beam sequence.
## Starts at 90, decrements by 10 each time it fires.
var _next_threshold_pct: int = 90

# ── Dash state ─────────────────────────────────────────────────────────────
var _dash_mode: DashMode  = DashMode.NONE
var _dash_dir: Vector3    = Vector3.ZERO
var _dash_origin: Vector3 = Vector3.ZERO
var _dash_target_dist: float = 0.0
## When true, firing a beam immediately follows the dash landing.
var _after_dash_beam: bool = false

# ── Phase 2 dash-in cooldown ───────────────────────────────────────────────
const P2_DASH_COOLDOWN_TIME := 2.5
var _p2_dash_cooldown: float = 0.0

# ── Attack / windup state ──────────────────────────────────────────────────
var _pending_attack: AttackType = AttackType.MELEE
var _is_beam_windup: bool       = false
var _walk_anim_timer: float     = 0.0
var _walk_frame_idx: int        = 0
var _sprite_base_x: float       = 0.0

# ── Client-proxy state ─────────────────────────────────────────────────────
var _proxy_is_beam_windup:  bool  = false
var _proxy_windup_progress: float = 0.0


# ══════════════════════════════════════════════════════════════════════════════
#  INIT
# ══════════════════════════════════════════════════════════════════════════════

func _ready() -> void:
	super._ready()
	billboard_sprite.animate          = false
	billboard_sprite.bounce_walk_mode = false
	billboard_sprite.frame            = FRAME_IDLE
	_sprite_base_x = billboard_sprite.position.x


# ══════════════════════════════════════════════════════════════════════════════
#  PHYSICS – override to inject dash sub-state before base state machine
# ══════════════════════════════════════════════════════════════════════════════

func _physics_process(delta: float) -> void:
	if _network_proxy_mode:
		_apply_proxy_motion(delta)
		return
	if current_state == State.DEAD or _hitstop_active:
		return

	if not is_on_floor():
		velocity.y -= 9.8 * delta

	if _p2_dash_cooldown > 0.0:
		_p2_dash_cooldown -= delta

	# Dash takes full control of this tick – bypass the base state machine.
	if _dash_mode != DashMode.NONE:
		_process_dash(delta)
		move_and_slide()
		return

	_process_state(delta)
	move_and_slide()


# ══════════════════════════════════════════════════════════════════════════════
#  MANUAL ANIMATION  (runs every rendered frame via _process)
# ══════════════════════════════════════════════════════════════════════════════

func _process(delta: float) -> void:
	match current_state:
		State.CHASE:
			_walk_anim_timer += delta
			if _walk_anim_timer >= 1.0 / 5.0:
				_walk_anim_timer = 0.0
				_walk_frame_idx  = (_walk_frame_idx + 1) % FRAME_WALK_COUNT
				billboard_sprite.frame = FRAME_WALK_FIRST + _walk_frame_idx
		State.IDLE:
			billboard_sprite.frame = FRAME_IDLE
			_walk_anim_timer = 0.0
		_:
			pass


# ══════════════════════════════════════════════════════════════════════════════
#  HEALTH / PHASE TRANSITIONS
# ══════════════════════════════════════════════════════════════════════════════

func _on_health_changed(current: int, max_hp: int) -> void:
	super._on_health_changed(current, max_hp)
	if current_state == State.DEAD:
		return

	var pct := int(float(current) / float(max_hp) * 100.0)

	# ── Phase transitions (take priority over threshold checks) ──────────
	if _phase != BossPhase.THREE and pct <= 15:
		_phase = BossPhase.THREE
		_on_phase_entered(BossPhase.THREE)
		return

	if _phase == BossPhase.ONE and pct <= 50:
		_phase = BossPhase.TWO
		# Skip the 50 % threshold – it's handled by the phase-entry dash below.
		_next_threshold_pct = 40
		_on_phase_entered(BossPhase.TWO)
		return

	# ── 10 % HP threshold: dash away + beam (Phase 1 and 2 only) ─────────
	if _phase != BossPhase.THREE and pct <= _next_threshold_pct:
		# Advance past any thresholds skipped by burst damage.
		while _next_threshold_pct >= pct and _next_threshold_pct > 0:
			_next_threshold_pct -= 10
		_begin_dash_away_sequence()


func _on_phase_entered(phase: BossPhase) -> void:
	match phase:
		BossPhase.TWO:
			# Immediately dash away + beam to announce Phase 2.
			_begin_dash_away_sequence()
		BossPhase.THREE:
			# Cancel everything and begin the relentless dash-beam loop.
			_begin_phase3_dash()


# ══════════════════════════════════════════════════════════════════════════════
#  DASH SEQUENCES
# ══════════════════════════════════════════════════════════════════════════════

## Phase 1 / 2 threshold response: dash directly away from the player,
## then immediately fire a beam attack.
func _begin_dash_away_sequence() -> void:
	if not player or current_state == State.DEAD:
		return
	var away := (global_position - player.global_position)
	away.y = 0.0
	if away.length_squared() < 0.001:
		away = Vector3(1.0, 0.0, 0.0)
	_cancel_current_action()
	_dash_dir         = away.normalized()
	_dash_origin      = global_position
	_dash_target_dist = dash_away_distance
	_dash_mode        = DashMode.AWAY
	_after_dash_beam  = true


## Phase 2: dash toward the player to close distance, then attempt melee.
func _begin_dash_attack() -> void:
	if not player or current_state == State.DEAD:
		return
	var toward := (player.global_position - global_position)
	toward.y = 0.0
	if toward.length_squared() < 0.001:
		return
	_cancel_current_action()
	_dash_dir         = toward.normalized()
	_dash_origin      = global_position
	_dash_target_dist = dash_attack_distance
	_dash_mode        = DashMode.ATTACK
	_after_dash_beam  = false
	_p2_dash_cooldown = P2_DASH_COOLDOWN_TIME


## Phase 3: find the most open direction and dash there, then beam attack.
func _begin_phase3_dash() -> void:
	if current_state == State.DEAD:
		return
	var open_dir := _find_open_space_direction()
	_cancel_current_action()
	_dash_dir         = open_dir
	_dash_origin      = global_position
	_dash_target_dist = dash_open_distance
	_dash_mode        = DashMode.OPEN_SPACE
	_after_dash_beam  = true


## Interrupt whatever the boss is currently doing and reset to a clean slate.
func _cancel_current_action() -> void:
	_dash_mode      = DashMode.NONE
	_after_dash_beam = false
	_is_beam_windup = false
	_attack_timer   = 0.0
	billboard_sprite.position.x = _sprite_base_x
	billboard_sprite.scale      = Vector3(1.0, 1.0, 1.0)
	billboard_sprite.modulate   = Color(1.0, 1.0, 1.0, 1.0)
	velocity        = Vector3.ZERO
	current_state   = State.CHASE


## Raycast 8 directions and return the one with the most clear distance.
func _find_open_space_direction() -> Vector3:
	var space  := get_world_3d().direct_space_state
	var origin := global_position + Vector3(0.0, actual_height * 0.5, 0.0)
	var probe  := dash_open_distance + 2.0
	var best_dir  := Vector3(1.0, 0.0, 0.0)
	var best_dist := 0.0

	for i in range(8):
		var angle := i * TAU / 8.0
		var dir   := Vector3(cos(angle), 0.0, sin(angle))
		var q     := PhysicsRayQueryParameters3D.create(origin, origin + dir * probe)
		q.collision_mask = 1
		q.exclude        = [get_rid()]
		var hit  := space.intersect_ray(q)
		var dist := probe if hit.is_empty() else origin.distance_to(hit.position)
		if dist > best_dist:
			best_dist = dist
			best_dir  = dir

	return best_dir


# ══════════════════════════════════════════════════════════════════════════════
#  PROCESS DASH
# ══════════════════════════════════════════════════════════════════════════════

func _process_dash(delta: float) -> void:
	var speed := dash_away_speed
	match _dash_mode:
		DashMode.ATTACK:
			speed = dash_attack_speed
		DashMode.OPEN_SPACE:
			speed = dash_open_speed

	velocity.x = _dash_dir.x * speed
	velocity.z = _dash_dir.z * speed

	if global_position.distance_to(_dash_origin) >= _dash_target_dist:
		_end_dash()


func _end_dash() -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	var completed_mode := _dash_mode
	_dash_mode = DashMode.NONE

	if _after_dash_beam:
		_after_dash_beam = false
		_pending_attack  = AttackType.BEAM
		_start_windup()
		return

	match completed_mode:
		DashMode.ATTACK:
			# Landed close to player – melee if in range, else chase.
			if player:
				var d2 := global_position.distance_squared_to(player.global_position)
				if d2 <= pow(melee_range + 0.5, 2):
					_pending_attack = AttackType.MELEE
					_start_windup()
					return
			current_state = State.CHASE
		_:
			current_state = State.CHASE


# ══════════════════════════════════════════════════════════════════════════════
#  STATE MACHINE (overrides base to inject phase-specific chase behaviour)
# ══════════════════════════════════════════════════════════════════════════════

func _process_state(delta: float) -> void:
	_refresh_target_player()

	if not player:
		return

	if _aggro_suppressed:
		current_state = State.IDLE
		_attack_timer = 0.0
		velocity      = Vector3.ZERO
		if billboard_sprite:
			billboard_sprite.animate = false
			billboard_sprite.frame   = 0
		return

	var dist_sq   := global_position.distance_squared_to(player.global_position)
	var same_room := _is_player_in_same_room()

	match current_state:
		State.IDLE:
			if same_room and dist_sq <= pow(aggro_range, 2):
				current_state = State.CHASE
			else:
				velocity.x = 0.0
				velocity.z = 0.0

		State.CHASE:
			if not same_room:
				current_state = State.IDLE
				velocity = Vector3.ZERO
				return
			match _phase:
				BossPhase.ONE:
					_chase_phase1(dist_sq)
				BossPhase.TWO:
					_chase_phase2(dist_sq)
				BossPhase.THREE:
					# Phase 3 is fully dash-driven; restart loop if we end up here.
					_begin_phase3_dash()

		State.WINDUP:
			if not same_room:
				current_state = State.IDLE
				_attack_timer = 0.0
				velocity      = Vector3.ZERO
				return
			velocity.x     = 0.0
			velocity.z     = 0.0
			_attack_timer += delta
			_process_windup_effect()
			if _attack_timer >= windup_time:
				_attack_timer = 0.0
				_execute_attack()

		State.ATTACK:
			current_state = State.COOLDOWN

		State.COOLDOWN:
			velocity.x     = 0.0
			velocity.z     = 0.0
			_attack_timer += delta
			if _attack_timer >= cooldown_time:
				_attack_timer = 0.0
				if _phase == BossPhase.THREE:
					_begin_phase3_dash()
				else:
					current_state = State.CHASE if same_room else State.IDLE


func _chase_phase1(dist_sq: float) -> void:
	# Phase 1 normal chase is melee-only; beam attacks only come from the
	# 10 % threshold dash-away sequence.
	if dist_sq <= pow(melee_range, 2):
		_pending_attack = AttackType.MELEE
		_start_windup()
	elif dist_sq > pow(aggro_range * 2.0, 2):
		current_state = State.IDLE
	else:
		_move_towards_player()


func _chase_phase2(dist_sq: float) -> void:
	# Phase 2 closes distance with dash attacks and finishes with melee.
	# Beams only fire via the 10 % threshold dash-away sequence.
	if dist_sq <= pow(melee_range, 2):
		_pending_attack = AttackType.MELEE
		_start_windup()
	elif _p2_dash_cooldown <= 0.0:
		_begin_dash_attack()
	else:
		_move_towards_player()


# ══════════════════════════════════════════════════════════════════════════════
#  ATTACK SELECTION
# ══════════════════════════════════════════════════════════════════════════════

func _should_start_windup(dist_squared_to_player: float) -> bool:
	if player == null:
		return false
	if dist_squared_to_player <= pow(melee_range, 2):
		_pending_attack = AttackType.MELEE
		return true
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
	current_state   = State.WINDUP
	_attack_timer   = 0.0
	billboard_sprite.animate = false
	billboard_sprite.frame   = FRAME_ATK_A
	if _is_beam_windup:
		billboard_sprite.modulate = Color(0.8, 0.85, 1.5, 1.0)


func _process_windup_effect() -> void:
	if not _is_beam_windup:
		var t := _attack_timer / windup_time
		billboard_sprite.frame = FRAME_ATK_A + clampi(int(t * 3.0), 0, 2)
		return

	var phase_t  := _attack_timer * shake_speed * TAU
	var progress := _attack_timer / windup_time
	var intensity := 1.0 + maxf(0.0, (progress - 0.6) / 0.4) * 3.0

	billboard_sprite.position.x = _sprite_base_x + sin(phase_t) * shake_x_amp * intensity
	var pulse := 1.0 + sin(phase_t * 0.7) * shake_scale_amp * intensity
	billboard_sprite.scale = Vector3(pulse, pulse, 1.0)
	billboard_sprite.frame = FRAME_ATK_A if fmod(_attack_timer * 6.0, 1.0) < 0.5 else FRAME_ATK_B

	var blue := lerpf(1.5, 3.0, progress)
	billboard_sprite.modulate = Color(0.7, 0.8, blue, 1.0)


# ══════════════════════════════════════════════════════════════════════════════
#  EXECUTE ATTACK
# ══════════════════════════════════════════════════════════════════════════════

func _execute_attack() -> void:
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

	current_state = State.ATTACK


func _fire_melee() -> void:
	if not player:
		return
	var dist_sq := global_position.distance_squared_to(player.global_position)
	if dist_sq <= pow(melee_range + 0.5, 2):
		if player.has_method("take_damage"):
			player.take_damage(melee_damage)


func _fire_beam() -> void:
	if not player:
		return

	var spawn_pos := global_position + Vector3(0.0, actual_height * 0.60, 0.0)
	var aim_pos   := player.global_position + Vector3(0.0, 1.0, 0.0)
	var dir       := (aim_pos - spawn_pos).normalized()

	var space  := get_world_3d().direct_space_state
	var q      := PhysicsRayQueryParameters3D.create(
		spawn_pos, spawn_pos + dir * beam_max_range)
	q.collision_mask = 1
	q.exclude        = [get_rid()]
	var hit    := space.intersect_ray(q)

	var beam_length := beam_max_range
	var hit_player  := false

	if hit.is_empty():
		var pdist := spawn_pos.distance_to(aim_pos)
		if pdist <= beam_max_range:
			hit_player = true
	else:
		beam_length = spawn_pos.distance_to(hit.position)
		var pdist := spawn_pos.distance_to(aim_pos)
		if pdist < beam_length:
			hit_player  = true
			beam_length = pdist

	if hit_player and player.has_method("take_damage"):
		player.take_damage(beam_damage)

	var beam         := BEAM_SCENE.instantiate()
	beam.beam_length  = maxf(0.5, beam_length)
	get_parent().add_child(beam)
	beam.global_position = spawn_pos
	beam.look_at(spawn_pos + dir, Vector3.UP)

	if _dungeon_manager and _dungeon_manager.has_method("rpc_spawn_enemy_beam_visual"):
		_dungeon_manager.rpc("rpc_spawn_enemy_beam_visual", spawn_pos, dir, maxf(0.5, beam_length))

	billboard_sprite.modulate = Color(0.5, 0.7, 2.5, 1.0)
	var tween := create_tween()
	tween.tween_property(billboard_sprite, "modulate", Color(1, 1, 1, 1), 0.25)


# ══════════════════════════════════════════════════════════════════════════════
#  MULTIPLAYER SNAPSHOT OVERRIDES
# ══════════════════════════════════════════════════════════════════════════════

func get_network_state_snapshot() -> Dictionary:
	var snap: Dictionary = super.get_network_state_snapshot()
	snap["dk_beam_windup"]     = _is_beam_windup
	snap["dk_windup_progress"] = clampf(
		_attack_timer / windup_time if current_state == State.WINDUP else 0.0,
		0.0, 1.0)
	snap["dk_phase"] = int(_phase)
	return snap


func apply_network_state_snapshot(snapshot: Dictionary) -> void:
	super.apply_network_state_snapshot(snapshot)
	_proxy_is_beam_windup  = snapshot.get("dk_beam_windup",      false)
	_proxy_windup_progress = snapshot.get("dk_windup_progress",  0.0)
	_phase = int(snapshot.get("dk_phase", int(_phase)))


func _update_proxy_visual_state() -> void:
	if not _network_proxy_mode:
		return

	var frame_limit := billboard_sprite.hframes * billboard_sprite.vframes - 1
	billboard_sprite.frame = clampi(_proxy_visual_frame, 0, frame_limit)
	if billboard_sprite.animate != _proxy_visual_animate:
		billboard_sprite.animate = _proxy_visual_animate

	if current_state == State.WINDUP and _proxy_is_beam_windup:
		var t         := Time.get_ticks_msec() * 0.001 * shake_speed * TAU
		var intensity := 1.0 + maxf(0.0, (_proxy_windup_progress - 0.6) / 0.4) * 3.0
		billboard_sprite.position.x = _sprite_base_x + sin(t) * shake_x_amp * intensity
		var pulse := 1.0 + sin(t * 0.7) * shake_scale_amp * intensity
		billboard_sprite.scale    = Vector3(pulse, pulse, 1.0)
		var blue := lerpf(1.5, 3.0, _proxy_windup_progress)
		billboard_sprite.modulate = Color(0.7, 0.8, blue, 1.0)
	else:
		billboard_sprite.position.x = _sprite_base_x
		billboard_sprite.scale      = Vector3(1.0, 1.0, 1.0)
		if current_state != State.DEAD:
			billboard_sprite.modulate = Color(1.0, 1.0, 1.0, 1.0)


# ══════════════════════════════════════════════════════════════════════════════
#  HELPERS
# ══════════════════════════════════════════════════════════════════════════════

func _has_line_of_sight() -> bool:
	if not player:
		return false
	var eye_pos := global_position + Vector3(0.0, actual_height * 0.75, 0.0)
	var aim_pos := player.global_position + Vector3(0.0, 1.0, 0.0)
	var space   := get_world_3d().direct_space_state
	var q       := PhysicsRayQueryParameters3D.create(eye_pos, aim_pos)
	q.collision_mask = 1
	q.exclude        = [get_rid()]
	return space.intersect_ray(q).is_empty()
