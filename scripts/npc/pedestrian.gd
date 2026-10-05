class_name Pedestrian
extends CharacterBody3D
## Wandering pedestrian. Walks between random points on its block's sidewalk ring, bobs a bit,
## and turns into a ragdoll when something fast hits it (cars, crates, explosions, bullets,
## a boosting player). Collides with the world only, so cars never get stuck on it.

const SHIRTS := [Color(0.9, 0.3, 0.3), Color(0.3, 0.5, 0.9), Color(0.95, 0.85, 0.3), Color(0.4, 0.75, 0.45), Color(0.9, 0.9, 0.9), Color(0.6, 0.35, 0.7), Color(0.95, 0.55, 0.2)]
const PANTS := [Color(0.2, 0.25, 0.4), Color(0.15, 0.15, 0.17), Color(0.5, 0.4, 0.3), Color(0.35, 0.35, 0.38)]
const SKINS := [Color(0.95, 0.8, 0.65), Color(0.85, 0.65, 0.5), Color(0.6, 0.42, 0.3), Color(0.4, 0.28, 0.2)]
## The crowd (see docs/ASSETS.md): real people built by tools/crowd with the hero's pipeline -
## MPFB humans (Blender) of every age, build and complexion, in CC0 MakeHuman clothes, shoes and
## hair, on the crowd's 24-bone rig with the Idle, Casual_Walk_inplace and run_fast_3_inplace clips.
## Each is one opaque Body (one 2K atlas, its vertex colour saying what is skin, top, bottom and
## hair, so a look recolours exactly) plus a Hair mesh of cut-out cards (is_hair()), about 15k
## triangles in all. They replaced the nine generated rigs (pedestrian_d..l, 2026-09-22), whose
## look was baked into one photo texture and read as plastic mannequins however it was shaded;
## those files stay (the hero's clips are retargeted from pedestrian_d's) but are not loaded.
## Missing files fall back to the box person.
const MODELS := [
	"res://assets/models/crowd_a.glb",
	"res://assets/models/crowd_b.glb",
	"res://assets/models/crowd_c.glb",
	"res://assets/models/crowd_d.glb",
	"res://assets/models/crowd_e.glb",
	"res://assets/models/crowd_f.glb",
	"res://assets/models/crowd_g.glb",
	"res://assets/models/crowd_h.glb",
	"res://assets/models/crowd_i.glb",
	"res://assets/models/crowd_j.glb",
	"res://assets/models/crowd_k.glb",
	"res://assets/models/crowd_l.glb",
]
## Ground speed (m/s) the walk clip is authored for at speed_scale 1: how fast a planted foot
## travels backwards under the in-place clip (tools/crowd/clip_probe.tscn, 0.70-0.77 on every
## rig). It was taken as 1.3, so every walker's feet slid forward at half the body's speed.
const WALK_CLIP_SPEED := 0.8
const WALK_CLIP := "Casual_Walk_inplace"
const IDLE_CLIP := "Idle"
## The run cycle the player's avatar uses too, and its authored ground speed (measured the same
## way, 2.65-3.0; it was taken as 5.0).
const RUN_CLIP := "run_fast_3_inplace"
const RUN_CLIP_SPEED := 2.75
## Where the left foot lands in each clip (fraction of the clip) and how many strides the walk
## clip holds, so a change between walk and run carries on with the same foot instead of popping.
const WALK_CYCLES := 3.0
const WALK_LEFT_DOWN := 0.03
const RUN_LEFT_DOWN := 0.17

@export var walk_speed: float = 1.8
## Anything moving faster than this that touches us knocks us over (m/s).
@export var knock_speed: float = 4.0
## A boosting player has to be at least this fast to tackle us (m/s).
@export var tackle_speed: float = 14.0
## Odds that a pedestrian stands still for a while when it reaches a spot instead of turning
## straight round. A crowd where nobody ever stops reads as a conveyor belt, not a street.
@export var pause_chance: float = 0.28
## How long a pause lasts (seconds, min and max).
@export var pause_seconds: Vector2 = Vector2(1.4, 5.5)
## Spread of the idle's rate. It used to scale the walk cadence too, off the rate the speed
## asks for, which slid the feet; a walker's cadence now comes from its pace and build.
@export var gait_spread: Vector2 = Vector2(0.84, 1.20)
## How far the torso leans, in degrees. Positive stoops forward. Rolled per character.
@export var lean_spread: Vector2 = Vector2(-1.5, 4.5)
## Fraction of the crowd wearing a cap, a beanie, a bucket hat or a backpack (CrowdHat for the
## hats). Each is one extra draw call and only within `accessory_distance`, and a changed
## silhouette separates two people far harder than another shirt colour does.
@export var accessory_chance: float = 0.42
## Metres past which a pedestrian's accessory stops drawing.
@export var accessory_distance: float = 60.0
## Running pace when frightened (m/s); each person runs within 12 % of it.
@export var run_speed: float = 4.4
## How long a scare lasts (seconds, min and max). Another shot while running starts it again.
@export var panic_seconds: Vector2 = Vector2(7.0, 12.0)
## Share of the walkers who, reaching a spot on their pavement, head for the nearest crosswalk
## and cross to the next block instead of turning back along their own (owner, 2026-09-24:
## "GTA-level street life"). They cross at signals and stop signs, never mid-block.
@export var cross_chance: float = 0.3
## Pace on the crosswalk, as a multiple of this walker's own (people hurry across).
@export var cross_pace: float = 1.2
## How far back from the kerb edge people wait to cross (m), and how far along the kerb a
## waiting crowd spreads either side of the crosswalk's middle (the crosswalk is 3 m wide).
@export var kerb_wait: float = 0.7
@export var kerb_spread: float = 1.1
## Seconds a walker stands at a stop-sign crosswalk before stepping out (min and max).
@export var stop_sign_patience: Vector2 = Vector2(0.8, 2.6)

@export_group("Locomotion")
## Pulling away from a standstill (m/s per second): the first steps are short and slow.
@export var walk_accel: float = 1.9
## Slowing to a stop (m/s per second): the last steps shorten instead of the feet sliding.
@export var stop_decel: float = 2.6
## A frightened person's acceleration (m/s per second).
@export var run_accel: float = 8.0
## Most a walker turns while walking (degrees a second); the body goes the way it faces, so a
## tighter turn is taken slower, never slid sideways.
@export var turn_rate: float = 200.0
## Turn rate while running from something (degrees a second).
@export var run_turn_rate: float = 520.0
## A turn sharper than this (degrees) from below `pivot_speed` (m/s) is taken standing: stop,
## step round on the spot at `pivot_rate` (degrees a second), then set off.
@export var pivot_angle: float = 100.0
@export var pivot_speed: float = 0.5
@export var pivot_rate: float = 150.0
## Walk clip rate while stepping round on the spot.
@export var pivot_cadence: float = 0.9
## Above this speed (m/s) the run clip takes over from the walk.
@export var run_clip_from: float = 2.9
## Spread of the arm swing, as a multiple of the clip's (rolled per person).
@export var arm_swing_spread: Vector2 = Vector2(0.7, 1.35)
## Share of people who walk with their head down (a phone, their feet).
@export var head_down_share: float = 0.14

@export_group("Head look")
## People within this distance of the player turn their heads to things (metres). Past it the
## pose is the clip's, which is what the middle and far bodies show anyway.
@export var look_range: float = 26.0
## A car passing within this distance catches the eye (metres), if it is doing over 3 m/s.
@export var look_car_range: float = 11.0
## The player walking within this distance of somebody is looked at (metres).
@export var look_player_range: float = 7.0
## Seconds a gunshot or a blast holds everyone's eyes.
@export var look_threat_seconds: float = 2.4
## Furthest the head turns from the body (degrees), and how fast it gets there (1/s).
@export var look_max_yaw: float = 72.0
@export var look_speed: float = 5.0
@export_group("")

## Crossing to the next block: walking to the kerb, waiting there, on the crosswalk.
enum Cross { NONE, TO_KERB, WAIT, CROSSING }
var _cross: int = Cross.NONE
## The two kerb points, the crosswalk (intersection, crossed road's axis, which side of the
## junction: Vector4i(ix, iz, axis, side)), the road's centre line and half width across the
## crossing, and the block on the far side.
var _cross_from := Vector2.ZERO
var _cross_to := Vector2.ZERO
var _cross_key := Vector4i.ZERO
var _cross_road := Vector2.ZERO
var _cross_ring := Rect2()
var _cross_signal: bool = false
var _cross_wait: float = 0.0
var _cross_patience: float = 1.5
## True while this walker is counted on its crosswalk (crosswalk_busy()).
var _on_crosswalk: bool = false
## Corners of the pavement ring to walk through before `_target`, so a walker goes round the
## block rather than through it (_ring_route()).
var _route: PackedVector2Array = PackedVector2Array()
var _route_pending: bool = true
## Seconds a near walker has pushed against something without getting anywhere.
var _walk_stuck_t: float = 0.0
## Crossing decisions roll on their own stream, like the cosmetic ones on `_style`.
var _way := RandomNumberGenerator.new()
## Walkers on each crosswalk right now, keyed Vector4i(ix, iz, crossed axis, side): what traffic
## yields to (TrafficManager._drive_street()). A count, taken on and off in exactly two places.
static var _crosswalks: Dictionary = {}

## Seconds of panic left; above zero the pedestrian runs away from `_threat` and never pauses.
var _panic_left: float = 0.0
## Where the scare came from (the same XZ space as `ring`).
var _threat := Vector2.ZERO
## Counts down to this pedestrian's scream; below zero, no scream is due.
var _scream_in: float = -1.0
## When and where the last alarm went off, so an automatic rifle does not re-scan the crowd ten
## times a second from the same spot.
static var _last_alarm_ms: int = -100000
static var _last_alarm_at := Vector3.INF
## When the last scream started. Screams are spaced out across the whole crowd: a hundred people
## screaming in the same frame is one loud noise, a few overlapping voices is a panicking street.
static var _last_scream_ms: int = -100000
## Shortest gap between two screams anywhere (milliseconds).
static var scream_gap_ms: int = 140

## Locomotion state: current ground speed along the facing, the clip in use, standing turn.
var _speed: float = 0.0
var _clip: String = ""
## Which of the three clips this rig has (looked up once: has_animation() is a string lookup).
var _has_walk: bool = false
var _has_run: bool = false
var _has_idle: bool = false
var _pivoting: bool = false
## The turn rates and pivot angle above in radians (worked out once, in _ready()).
var _turn_rad: float = 0.0
var _run_turn_rad: float = 0.0
var _pivot_rate_rad: float = 0.0
var _pivot_rad: float = 0.0
var _faced: bool = false
var _run_pace: float = 4.4
## A pause rolled at the start of a leg, taken at its end, so the walker slows into it.
var _pause_next: float = 0.0
## Everything this file's animation work rolls (arm swing, head, idle seek, LOD phase): its
## own stream, so it moves nothing else.
var _anim_rng := RandomNumberGenerator.new()
var _head_skel: Skeleton3D
var _look_bones := PackedInt32Array()
var _arm_bones := PackedInt32Array()
var _arm_swing: float = 1.0
var _posture_pitch: float = 0.0
var _look_near: bool = false
var _look_yaw: float = 0.0
var _look_pitch: float = 0.0
var _look_point := Vector3.INF
var _look_threat := Vector3.INF
var _look_hold: float = 0.0
var _look_scan: float = 0.0
## Moving cars near the player, [position, velocity], shared by the whole crowd and refreshed
## a few times a second (_nearby_cars()).
static var _cars: Array = []
static var _cars_tick: int = -1000
static var _cars_prev: Dictionary = {}
## Per model: the walk clip's mean upper-arm rotations, what the swing is scaled about.
static var _arm_means: Dictionary = {}

var ring: Rect2
var shirt: Color
var pants: Color
var skin: Color
var _target: Vector2
var _rng := RandomNumberGenerator.new()
var _visual: Node3D
var _bob: float = 0.0
var _down: bool = false
## The ragdoll this pedestrian became, for rounds that arrive after it went down.
var _doll: Ragdoll
var _anim: AnimationPlayer
## Which rig this pedestrian wears ("" for the box person); the ragdoll keeps the same one.
var _model_path: String = ""
## Clothing look index, so the ragdoll that replaces this pedestrian keeps the same outfit.
var _look: int = 0
## Update LOD: far pedestrians move and animate every Nth physics frame (see _update_lod).
var _lod_stride: int = 1
var _lod_tick: int = 0
var _lod_timer: float = 0.0
## Cadence multiplier on the walk clip for this character.
var _gait: float = 1.0
## The build's stride (the visual's depth scale) and the clip rate last set.
var _stride: float = 1.0
var _rate: float = -1.0
## Seconds left standing still; 0 means walking.
var _pause_left: float = 0.0
## Everything cosmetic (look, gait, lean, accessory, pauses) rolls on its own stream, so adding
## or removing one of them never shifts where the crowd walks. Same seed, same city.
var _style := RandomNumberGenerator.new()
static var _player: Node3D


func setup(block_rect: Rect2, sidewalk: float, seed_value: int) -> void:
	ring = block_rect
	_rng.seed = seed_value
	_style.seed = hash([seed_value, "style"])
	shirt = SHIRTS[_rng.randi() % SHIRTS.size()]
	pants = PANTS[_rng.randi() % PANTS.size()]
	skin = SKINS[_rng.randi() % SKINS.size()]
	# 1.05-1.5 m/s: a city pace. The clip's step is 0.5 m, so matched to the stride 2.6 m/s
	# would take four steps a second.
	walk_speed = _rng.randf_range(1.05, 1.5)
	_speed = walk_speed
	_anim_rng.seed = hash([seed_value, "anim"])
	_run_pace = run_speed * _anim_rng.randf_range(0.88, 1.12)
	_arm_swing = _anim_rng.randf_range(arm_swing_spread.x, arm_swing_spread.y)
	_posture_pitch = -deg_to_rad(_anim_rng.randf_range(16.0, 24.0)) if _anim_rng.randf() < head_down_share \
		else deg_to_rad(_anim_rng.randf_range(-3.0, 3.0))
	# Everybody's far updates on a different tick, not all a crowd's on the same one.
	_lod_tick = _anim_rng.randi() % 8
	_target = _random_ring_point(sidewalk)
	_sidewalk = sidewalk
	_way.seed = hash([seed_value, "way"])
	_route_pending = true
	_life_seed = seed_value


var _life_seed: int = 0


var _sidewalk: float = 4.0


func _ready() -> void:
	add_to_group("pedestrian")
	_turn_rad = deg_to_rad(turn_rate)
	_run_turn_rad = deg_to_rad(run_turn_rate)
	_pivot_rate_rad = deg_to_rad(pivot_rate)
	_pivot_rad = deg_to_rad(pivot_angle)
	collision_layer = 8 # the npc layer: bullets, blasts and bumpers look for it
	collision_mask = 1
	floor_snap_length = 0.4
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.7
	shape.shape = capsule
	shape.position = Vector3(0.0, 0.85, 0.0)
	add_child(shape)
	_visual = Node3D.new()
	add_child(_visual)
	if _lives() and life_enabled:
		_roll_life(_life_seed)
	if _add_model():
		_add_hit_area()
		_setup_life()
		return
	_part(Vector3(0.5, 0.65, 0.3), Vector3(0.0, 1.05, 0.0), shirt)
	_part(Vector3(0.2, 0.7, 0.2), Vector3(-0.14, 0.38, 0.0), pants)
	_part(Vector3(0.2, 0.7, 0.2), Vector3(0.14, 0.38, 0.0), pants)
	_part(Vector3(0.16, 0.6, 0.16), Vector3(-0.36, 1.05, 0.0), skin)
	_part(Vector3(0.16, 0.6, 0.16), Vector3(0.36, 1.05, 0.0), skin)
	var head := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.15
	sphere.height = 0.3
	sphere.radial_segments = 8
	sphere.rings = 4
	head.mesh = sphere
	head.material_override = PropFactory.material(skin, 0.8)
	head.position = Vector3(0.0, 1.55, 0.0)
	_visual.add_child(head)
	_add_hit_area()


## Picks one of the generated characters (seeded) and starts its walk cycle. False if none exist.
func _add_model() -> bool:
	var available: Array[String] = []
	for path in MODELS:
		if ResourceLoader.exists(path):
			available.append(path)
	if available.is_empty():
		return false
	var path: String = available[_style.randi() % available.size()]
	var scene: PackedScene = load(path)
	if scene == null:
		return false
	var inst := scene.instantiate() as Node3D
	inst.rotation.y = PI # Meshy rigs face +Z; our visuals face -Z
	_look = _style.randi() % CHARACTER_LOOKS
	prepare_rig(inst, _look)
	_visual.add_child(inst)
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		_meshes.append(mi as MeshInstance3D)
	_model_path = path
	# Build variation: nobody in a crowd is the same height or width as the person next to them.
	var tall := _style.randf_range(0.90, 1.10)
	_visual.scale = Vector3(_style.randf_range(0.94, 1.07), tall, _style.randf_range(0.94, 1.07))
	# A fixed stoop or a chest-out posture, held for this character's whole life. Forward is -Z,
	# so a negative X rotation tips the head forward.
	_visual.rotation.x = -deg_to_rad(_style.randf_range(lean_spread.x, lean_spread.y))
	_gait = _style.randf_range(gait_spread.x, gait_spread.y)
	_stride = _visual.scale.z
	_anim = inst.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _anim:
		fix_arm_pose(_anim, path)
		_has_walk = _anim.has_animation(WALK_CLIP)
		_has_run = _anim.has_animation(RUN_CLIP)
		_has_idle = _anim.has_animation(IDLE_CLIP)
		for clip in _anim.get_animation_list():
			_anim.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
		# Advanced by hand in _physics_process so far pedestrians can animate less often.
		_anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		if _anim.has_animation(WALK_CLIP):
			_set_clip(WALK_CLIP, 0.0)
			# Pose the rig at the top of the walk before hanging anything off its bones. The
			# clip holds the spine seven degrees off the bind pose the whole way round, so a
			# backpack lined up against the bind pose rides tilted back and floating off the
			# spine. Lining it up against a walking frame puts it on the back.
			_anim.seek(0.0, true)
	_add_accessory(inst)
	if _anim and _anim.has_animation(WALK_CLIP):
		# Start everyone at a different point in the cycle. A crowd stepping in perfect
		# unison is the most obvious tell that they are all the same model.
		_anim.seek(_style.randf() * _anim.get_animation(WALK_CLIP).length, true)
		_anim.speed_scale = walk_speed / (WALK_CLIP_SPEED * _stride)
	var found := inst.find_children("*", "Skeleton3D", true, false)
	if not found.is_empty():
		_head_skel = found[0]
		for bone in ["neck", "Head"]:
			_look_bones.append(_head_skel.find_bone(bone))
		for bone in ["LeftArm", "RightArm"]:
			_arm_bones.append(_head_skel.find_bone(bone))
		if -1 in _look_bones:
			_look_bones.clear()
		if -1 in _arm_bones or _anim == null:
			_arm_bones.clear()
		elif not _arm_means.has(path):
			_arm_means[path] = _clip_means(_anim, _head_skel, WALK_CLIP, _arm_bones)
	return true


## Stands this character still (staging and tests): the clip follows the speed.
func _play_idle() -> void:
	_speed = 0.0
	_set_clip(IDLE_CLIP, 0.3)


## Idle, walk or run from the speed this person actually covers the ground at, with the clip's
## rate matched to it so the planted foot stays planted (a taller or longer-legged build takes
## longer steps, so fewer of them), and a standing turn stepped round on the spot.
func _animate_gait() -> void:
	if _anim == null:
		return
	var rate := _gait
	if _life_clip != "" and _speed < 0.12 and not _pivoting:
		_set_clip(_life_clip, 0.25 if _life_clip in CrowdLife.ONE_SHOTS else 0.5)
		rate = 1.0
	elif _jogger and _life_ok and _panic_left <= 0.0 and _speed > 1.2:
		_set_clip(CrowdLife.JOG, 0.3)
		rate = _speed / (CrowdLife.JOG_CLIP_SPEED * _stride)
	elif _pivoting and _speed < 0.35 and _has_walk:
		_set_clip(WALK_CLIP, 0.3)
		rate = pivot_cadence
	elif _speed > run_clip_from - (0.4 if _clip == RUN_CLIP else 0.0) and _has_run:
		_set_clip(RUN_CLIP, 0.3)
		rate = _speed / (RUN_CLIP_SPEED * _stride)
	elif _speed > (0.22 if _clip == IDLE_CLIP else 0.1) or not _has_idle:
		_set_clip(WALK_CLIP, 0.35)
		rate = maxf(_speed, 0.4) / (WALK_CLIP_SPEED * _stride)
	else:
		_set_clip(IDLE_CLIP, 0.45)
	if absf(rate - _rate) > 0.005:
		_rate = rate
		_anim.speed_scale = rate


## Cross-fades to `clip` (once; asking again does nothing). Walk and run swap on the same foot,
## a walk starts on a footfall and an idle somewhere of its own.
func _set_clip(clip: String, blend: float) -> void:
	if clip == _clip or _anim == null or not _anim.has_animation(clip):
		return
	# Past lod_mid a cross-fade is two clips evaluated at 15 Hz for a figure a few dozen pixels
	# tall: cut instead (still on the same foot).
	if _lod_stride >= 4:
		blend = 0.0
	var from := _clip
	var t := _anim.current_animation_position if _anim.current_animation != "" else 0.0
	var from_len := _anim.get_animation(from).length if from != "" and _anim.has_animation(from) else 1.0
	_clip = clip
	_anim.play(clip, blend)
	var length := _anim.get_animation(clip).length
	var phase := -1.0
	if from == WALK_CLIP:
		phase = fposmod((t / from_len - WALK_LEFT_DOWN) * WALK_CYCLES, 1.0)
	elif from == RUN_CLIP:
		phase = fposmod(t / from_len - RUN_LEFT_DOWN, 1.0)
	if clip == RUN_CLIP:
		_anim.seek(fposmod(maxf(phase, 0.0) + RUN_LEFT_DOWN, 1.0) * length, false)
	elif clip == WALK_CLIP:
		var cycle := float(_anim_rng.randi() % int(WALK_CYCLES))
		_anim.seek(fposmod((maxf(phase, 0.0) + cycle) / WALK_CYCLES + WALK_LEFT_DOWN, 1.0) * length, false)
	elif clip in CrowdLife.ONE_SHOTS:
		_anim.seek(0.0, false)
	else:
		_anim.seek(_anim_rng.randf() * length, false)


## Turns toward `to_goal` and eases the speed toward `want`; returns the ground velocity, which
## is always along the way the body faces. A sharp turn from a near standstill is taken on the
## spot (pivot), a bend is taken slower, and a frightened person turns and bolts at once.
func _steer(to_goal: Vector2, want: float, delta: float, panicking: bool) -> Vector2:
	var yaw := _visual.rotation.y
	if to_goal.length_squared() > 1e-4:
		var goal_yaw := atan2(-to_goal.x, -to_goal.y)
		if not _faced:
			yaw = goal_yaw
			_faced = true
		var err := angle_difference(yaw, goal_yaw)
		var a := absf(err)
		if panicking:
			_pivoting = false
		elif a > _pivot_rad and _speed < pivot_speed:
			_pivoting = true
		elif a < 0.21: # 12 degrees
			_pivoting = false
		var rate := (_run_turn_rad if panicking else (_pivot_rate_rad if _pivoting else _turn_rad)) * delta
		if a > 1e-4:
			yaw = wrapf(yaw + clampf(err, -rate, rate), -PI, PI)
			_visual.rotation.y = yaw
		if _pivoting:
			want = 0.0
		elif not panicking and a > 0.02:
			want *= clampf(1.0 - a * 0.382, 0.2, 1.0) # none by 150 degrees
	var accel := run_accel if panicking else (walk_accel if want > _speed else stop_decel)
	_speed = move_toward(_speed, want, accel * delta)
	return Vector2(-sin(yaw), -cos(yaw)) * _speed


## Steps round to face `yaw` where it stands (and lets any speed it still has run out).
func _turn_on_spot(yaw: float, delta: float) -> void:
	var err := angle_difference(_visual.rotation.y, yaw)
	_pivoting = absf(err) > deg_to_rad(20.0) or (_pivoting and absf(err) > deg_to_rad(4.0))
	var rate := deg_to_rad(pivot_rate) * delta
	_visual.rotation.y = wrapf(_visual.rotation.y + clampf(err, -rate, rate), -PI, PI)
	if _speed > 0.0:
		_speed = move_toward(_speed, 0.0, stop_decel * delta)
		var f := Vector2(-sin(_visual.rotation.y), -cos(_visual.rotation.y)) * _speed * delta
		position += Vector3(f.x, 0.0, f.y)


## Caps, beanies, bucket hats and backpacks. The headwear is CrowdHat's: a real cap, beanie or
## bucket hat modelled round this rig's own head (tools/crowd/hat_fit.gd measures it), sitting
## down on the forehead and over the ear tops, with the hair pressed under it and showing below
## the band. The pack is built here in code, the way the street props are, and hung off the
## spine. Each is one mesh shared by every wearer of that rig (the hats) or every wearer (the
## pack), one material per colourway, one draw call, no shadow pass, nothing past
## `accessory_distance`. A changed silhouette separates two people at fifty metres; a fourth shirt
## colour does not.
enum Accessory {NONE, CAP, BEANIE, PACK, BUCKET}
## The hat each Accessory is (CrowdHat.Kind).
const HAT_KIND := {Accessory.CAP: CrowdHat.Kind.CAP, Accessory.BEANIE: CrowdHat.Kind.BEANIE,
	Accessory.BUCKET: CrowdHat.Kind.BUCKET}
const PACK_COLORS := [
	Color(0.13, 0.14, 0.16), Color(0.19, 0.27, 0.40), Color(0.36, 0.27, 0.18),
	Color(0.45, 0.16, 0.16), Color(0.22, 0.34, 0.26), Color(0.55, 0.53, 0.50),
]
static var _pack_mesh: Mesh
## The hat this person wears (an Accessory, NONE for none) and its colourway, so the ragdoll
## they become wears it too.
var _hat: int = Accessory.NONE
var _hat_pick: int = 0


func _add_accessory(inst: Node3D) -> void:
	if _style.randf() >= accessory_chance:
		return
	# The rolls are the ones the old box hats made, in the old order (CampFigure.seed_for() and
	# everything rolled after this depend on them): what to wear, then one colour roll.
	var roll := _style.randf()
	var kind: int = Accessory.PACK if roll < 0.38 else (Accessory.BEANIE if roll < 0.60 else
		(Accessory.CAP if roll < 0.90 else Accessory.BUCKET))
	var skel := inst.find_child("Skeleton3D", true, false) as Skeleton3D
	if skel == null:
		return
	if kind != Accessory.PACK:
		if skel.find_bone("Head") < 0:
			return
		_hat = kind
		_hat_pick = _style.randi()
		CrowdHat.dress(inst, _model_path, HAT_KIND[kind], _hat_pick, _accessory_reach())
		return
	var idx := skel.find_bone("Spine01")
	if idx < 0:
		return
	# The rig's skeleton works in centimetres under a 0.01 armature, so anything hung off a bone
	# has to be scaled back up by that chain to be built in metres. Read it off the nodes rather
	# than hard-coding 100, in case a rig is ever exported at a different scale.
	var unit := 1.0
	var node: Node3D = skel
	while node != null and node != inst:
		unit *= node.transform.basis.get_scale().y
		node = node.get_parent() as Node3D
	unit = 1.0 / maxf(unit, 0.0001)
	var att := BoneAttachment3D.new()
	skel.add_child(att)
	att.bone_name = "Spine01"
	var mi := MeshInstance3D.new()
	mi.mesh = _pack()
	mi.material_override = PropFactory.material(PACK_COLORS[_style.randi() % PACK_COLORS.size()], 0.72)
	mi.visibility_range_end = _accessory_reach()
	# No shadow pass and no global illumination: a second draw call per wearer is not worth it.
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	# The bone as it stands in the walk clip, not as it stands in the bind pose (see _add_model).
	var pose := skel.get_bone_global_pose(idx)
	# Built level in skeleton space and then pushed back through that pose, so the pack hangs
	# plumb on the back whatever angle the spine holds, and still rides it once the clip moves on.
	mi.transform = pose.affine_inverse() * Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * unit), pose.origin)
	att.add_child(mi)


func _accessory_reach() -> float:
	return accessory_distance * (0.6 if OS.has_feature("web") else 1.0)


## The ragdoll this person became wears their hat too (its rig is a fresh copy of the model).
func _dress_doll(doll: Ragdoll) -> void:
	if _hat != Accessory.NONE and doll._rig:
		CrowdHat.dress(doll._rig, _model_path, HAT_KIND[_hat], _hat_pick, _accessory_reach())


## The backpack: one shared mesh, built in metres about the spine bone. Part colours go in the
## vertex colour and the per-character colour multiplies them, so one mesh covers every colourway.
static func _pack() -> Mesh:
	if _pack_mesh != null:
		return _pack_mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var white := Color(1.0, 1.0, 1.0)
	# Sunk a centimetre into the back rather than floated off it: the front face is never seen,
	# and a gap between a pack and a spine is.
	st.set_smooth_group(0xFFFFFFFF)
	_acc_box(st, Vector3(0.0, -0.020, -0.218), Vector3(0.285, 0.390, 0.160), white)
	_acc_box(st, Vector3(0.0, 0.168, -0.226), Vector3(0.270, 0.050, 0.146), Color(0.86, 0.86, 0.86))
	_acc_box(st, Vector3(0.0, -0.112, -0.303), Vector3(0.185, 0.125, 0.030), Color(0.74, 0.74, 0.74))
	for side: float in [-1.0, 1.0]:
		_acc_beam(st, Vector3(side * 0.086, 0.135, -0.148), Vector3(side * 0.103, 0.222, -0.020),
				0.048, 0.026, Color(0.72, 0.72, 0.72))
	st.generate_normals()
	_pack_mesh = st.commit()
	return _pack_mesh


## Winding matches the rest of the project: vertices clockwise seen from outside, so
## generate_normals() points them out of the solid.
static func _acc_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, colour: Color) -> void:
	for v: Vector3 in [a, b, c, a, c, d]:
		st.set_color(colour)
		st.set_uv(Vector2.ZERO)
		st.add_vertex(v)


## A box with its own axes: `ex`, `ey`, `ez` are half-extent vectors and must be right-handed.
static func _acc_prism(st: SurfaceTool, centre: Vector3, ex: Vector3, ey: Vector3, ez: Vector3, colour: Color) -> void:
	var p := [
		centre - ex - ey - ez, centre + ex - ey - ez, centre + ex + ey - ez, centre - ex + ey - ez,
		centre - ex - ey + ez, centre + ex - ey + ez, centre + ex + ey + ez, centre - ex + ey + ez,
	]
	for f: Array in [[0, 1, 2, 3], [5, 4, 7, 6], [4, 0, 3, 7], [1, 5, 6, 2], [3, 2, 6, 7], [4, 5, 1, 0]]:
		_acc_quad(st, p[f[0]], p[f[1]], p[f[2]], p[f[3]], colour)


static func _acc_box(st: SurfaceTool, centre: Vector3, size: Vector3, colour: Color) -> void:
	_acc_prism(st, centre, Vector3(size.x * 0.5, 0.0, 0.0), Vector3(0.0, size.y * 0.5, 0.0),
			Vector3(0.0, 0.0, size.z * 0.5), colour)


## A strap: a thin box running from `a` to `b`.
static func _acc_beam(st: SurfaceTool, a: Vector3, b: Vector3, width: float, thick: float, colour: Color) -> void:
	var axis := b - a
	var length := axis.length()
	if length < 0.001:
		return
	var forward := axis / length
	var side := forward.cross(Vector3.UP)
	if side.length() < 0.001:
		side = forward.cross(Vector3.FORWARD)
	side = side.normalized()
	# Right-handed: ex cross ey has to come out along ez.
	_acc_prism(st, (a + b) * 0.5, side * (width * 0.5), forward.cross(side) * (thick * 0.5),
			forward * (length * 0.5), colour)


## Arm retarget. The generated clips were authored for a skeleton whose arms hang straight, but
## every generated rig is bound in whatever pose its mesh came out in - an A-pose for the first
## two, a palms-up shrug with the forearms raised for the newer ones - and the clips drive the
## arm bones as if that rest pose were the canonical one. So the arms came out held out like a
## scarecrow, or with the hands up by the ears. Rotating fixed amounts off the keys (the old
## ARM_DROP) had to be tuned per rig by eye and still left the forearms and wrists wrong.
##
## Instead the arm keys are rebuilt from the rig's own rest pose: the upper arm hangs from the
## shoulder with a little spread, swings opposite the same-side thigh (the phase is read from
## the clip's own legs, so the arms stay in step with the feet), the elbow bends forward and
## bends more as the arm comes forward, the forearm and wrist turn the palm to face the thigh,
## and the wrist is straightened. All of it is in the chest's frame, so the shoulders' twist
## and the torso's lean carry the arms with them. The clips animate these bones, so a pose
## override would be overwritten every frame; this runs once per model on the shared animation
## resource, so it costs nothing at runtime and fixes every instance at the same time.
## Judge a change with tools/glshot/character_shot.gd, front AND side.
##
## Per clip kind (matched against the clip name): swing amplitude, forward bias of the swing,
## elbow bend, extra elbow bend at the front of the swing, spread of the upper arm from the
## body, and how far the forearm comes back in from that spread. Degrees.
## The last two are a pair: the upper arm has to clear the ribs and the jacket, but carried on
## down the forearm the same angle leaves the hand a hand's width off the thigh, and a crowd of
## people walking with their hands held out from their sides reads as gunslingers.
const ARM_GAIT := {
	"run": [34.0, 8.0, 78.0, 14.0, 12.0, 4.0],
	"walk": [15.0, 4.0, 15.0, 15.0, 9.0, 7.0],
	"idle": [0.0, 3.0, 12.0, 0.0, 8.0, 7.0],
}
## Extra spread per model file (degrees), for a bulky jacket the arms would pass through.
const ARM_SPREAD := {}
## Palm turn (degrees) carried by the forearm and by the wrist. Split, because linear skinning
## puts all of a single bone's twist at one joint and a whole quarter turn there pinches it.
## Measured, not assumed: 60 in total puts the palm on the thigh with the hand edge-on from the
## front; 85 left the hands as open fans, and past that the palms turn to face forward.
const FOREARM_TWIST := 32.0
const WRIST_TWIST := 28.0
static var _arms_fixed: Dictionary = {}


static func fix_arm_pose(anim: AnimationPlayer, model_path: String) -> void:
	if anim == null or _arms_fixed.has(model_path):
		return
	var root := anim.get_node_or_null(anim.root_node)
	if root == null:
		return
	var found := root.find_children("*", "Skeleton3D", true, false)
	if found.is_empty():
		return
	var skel: Skeleton3D = found[0]
	_arms_fixed[model_path] = true
	var spread_extra: float = ARM_SPREAD.get(model_path.get_file(), 0.0)
	for clip in anim.get_animation_list():
		var a := anim.get_animation(clip)
		var gait: Array = ARM_GAIT["idle"]
		for kind in ARM_GAIT:
			if String(clip).to_lower().contains(kind):
				gait = ARM_GAIT[kind]
				break
		var tracks := {}
		for t in a.get_track_count():
			if a.track_get_type(t) == Animation.TYPE_ROTATION_3D:
				var bi := skel.find_bone(String(a.track_get_path(t).get_concatenated_subnames()))
				if bi >= 0:
					tracks[bi] = t
		_retarget_arm(a, skel, tracks, 1.0, gait, spread_extra)
		_retarget_arm(a, skel, tracks, -1.0, gait, spread_extra)


## Rebuilds one arm's keys in `a`. `side` is +1 for the left arm (the rigs face +Z, so their
## left is +X) and -1 for the right.
static func _retarget_arm(a: Animation, skel: Skeleton3D, tracks: Dictionary, side: float,
		gait: Array, spread_extra: float) -> void:
	var pre := "Left" if side > 0.0 else "Right"
	var arm := skel.find_bone(pre + "Arm")
	var fore := skel.find_bone(pre + "ForeArm")
	var hand := skel.find_bone(pre + "Hand")
	if arm < 0 or fore < 0 or hand < 0 or not tracks.has(arm) or not tracks.has(fore):
		return
	var shoulder := skel.get_bone_parent(arm)
	var chest := skel.get_bone_parent(shoulder)
	# The collarbone first, because the arm keys are written relative to it. The clips hold it
	# 8 to 20 degrees below level the whole way round - the same retarget mismatch as the arms -
	# which slumps the shoulders and squares them off. Every rig's own rest collarbone is level,
	# so the keys are turned until their average lies on it: the shoulders' bob through the
	# stride stays, the slump goes.
	if tracks.has(shoulder):
		var t_sh: int = tracks[shoulder]
		var reach := skel.get_bone_rest(arm).origin.normalized()
		var mean := Vector3.ZERO
		for k in a.track_get_key_count(t_sh):
			mean += (a.track_get_key_value(t_sh, k) as Quaternion) * reach
		if mean.length() > 0.001:
			var level := Quaternion(mean.normalized(), skel.get_bone_rest(shoulder).basis.get_rotation_quaternion() * reach)
			for k in a.track_get_key_count(t_sh):
				a.track_set_key_value(t_sh, k, (level * (a.track_get_key_value(t_sh, k) as Quaternion)).normalized())
	var arm_rest := _rest_rot(skel, arm)
	var fore_rest := _rest_rot(skel, fore)
	var chest_rest_inv := _rest_rot(skel, chest).inverse()
	# The rest pose's upper arm and forearm directions and the elbow's hinge axis between them.
	var u0 := (arm_rest * skel.get_bone_rest(fore).origin).normalized()
	var f0 := (fore_rest * skel.get_bone_rest(hand).origin).normalized()
	var h0 := u0.cross(f0)
	if h0.length() < 0.1:
		h0 = u0.cross(Vector3.BACK)
	h0 = h0.normalized()
	var rest_u := Basis(u0, h0, u0.cross(h0)).transposed()
	var rest_f := Basis(f0, h0, f0.cross(h0)).transposed()

	# Arm swing phase from the same-side thigh: the arm is forward while that leg is back.
	var thigh := skel.find_bone(pre + "UpLeg")
	var knee := skel.find_bone(pre + "Leg")
	var leg_mid := 0.0
	var leg_amp := 0.0
	if thigh >= 0 and knee >= 0 and gait[0] > 0.0:
		var lo := INF
		var hi := -INF
		for i in 48:
			var ang := _thigh_angle(a, skel, tracks, thigh, knee, a.length * float(i) / 48.0)
			lo = minf(lo, ang)
			hi = maxf(hi, ang)
		leg_mid = (lo + hi) * 0.5
		leg_amp = (hi - lo) * 0.5
	var spread := deg_to_rad(gait[4] + spread_extra) * side

	var target := func(time: float) -> Array:
		var swing := 0.0
		if leg_amp > deg_to_rad(2.0):
			swing = -(_thigh_angle(a, skel, tracks, thigh, knee, time) - leg_mid) / leg_amp
		var elbow := deg_to_rad(gait[2] + gait[3] * clampf(swing, 0.0, 1.0))
		# Hanging straight down with the elbow hinge along -X, then spread out from the body,
		# swung about the shoulders' lateral axis, then turned with the chest. Only its turn,
		# not its lean: the clips tip the torso about seven degrees forward, and arms carried
		# by that pitch trail behind the body instead of hanging under gravity.
		var chest_fwd := (_pose_rot(a, skel, tracks, chest, time) * chest_rest_inv) * Vector3.BACK
		var turn := Quaternion(Vector3.UP, atan2(chest_fwd.x, chest_fwd.z))
		var frame := turn * Quaternion(Vector3.LEFT, deg_to_rad(gait[1] + gait[0] * swing)) \
				* Quaternion(Vector3.BACK, spread)
		var u1 := frame * Vector3.DOWN
		var h1 := frame * Vector3.LEFT
		var f1 := Quaternion(turn * Vector3.BACK, -deg_to_rad(gait[5]) * side) * (Quaternion(h1, elbow) * u1)
		var hf := (h1 - f1 * h1.dot(f1)).normalized()
		var g_arm := Quaternion(Basis(u1, h1, u1.cross(h1)) * rest_u) * arm_rest
		var g_fore := Quaternion(f1, deg_to_rad(FOREARM_TWIST) * side) \
				* Quaternion(Basis(f1, hf, f1.cross(hf)) * rest_f) * fore_rest
		return [g_arm.normalized(), g_fore.normalized()]

	var t_arm: int = tracks[arm]
	for k in a.track_get_key_count(t_arm):
		var time := a.track_get_key_time(t_arm, k)
		var g: Array = target.call(time)
		var parent := _pose_rot(a, skel, tracks, shoulder, time)
		a.track_set_key_value(t_arm, k, (parent.inverse() * (g[0] as Quaternion)).normalized())
	var t_fore: int = tracks[fore]
	for k in a.track_get_key_count(t_fore):
		var g: Array = target.call(a.track_get_key_time(t_fore, k))
		a.track_set_key_value(t_fore, k, ((g[0] as Quaternion).inverse() * (g[1] as Quaternion)).normalized())
	# The wrist: straightened onto the forearm's axis, then the rest of the palm turn.
	if tracks.has(hand):
		var hand_rest := skel.get_bone_rest(hand).basis.get_rotation_quaternion()
		var axis := skel.get_bone_rest(hand).origin.normalized()
		var q := Quaternion(axis, deg_to_rad(WRIST_TWIST) * side) * Quaternion(hand_rest * Vector3.UP, axis) * hand_rest
		var t_hand: int = tracks[hand]
		for k in a.track_get_key_count(t_hand):
			a.track_set_key_value(t_hand, k, q.normalized())


static func _rest_rot(skel: Skeleton3D, bone: int) -> Quaternion:
	return skel.get_bone_global_rest(bone).basis.get_rotation_quaternion()


## A bone's skeleton-space rotation at `time` in `a`, walking up the chain from the clip's keys
## (the rest rotation where a bone has no track).
static func _pose_rot(a: Animation, skel: Skeleton3D, tracks: Dictionary, bone: int, time: float) -> Quaternion:
	var q := Quaternion.IDENTITY
	var b := bone
	while b >= 0:
		var local: Quaternion
		if tracks.has(b):
			local = a.rotation_track_interpolate(tracks[b], time)
		else:
			local = skel.get_bone_rest(b).basis.get_rotation_quaternion()
		q = local * q
		b = skel.get_bone_parent(b)
	return q


## Forward pitch of the thigh at `time` (radians, positive is the knee forward).
static func _thigh_angle(a: Animation, skel: Skeleton3D, tracks: Dictionary, thigh: int, knee: int, time: float) -> float:
	var d := _pose_rot(a, skel, tracks, thigh, time) * skel.get_bone_rest(knee).origin
	return atan2(d.z, -d.y)


## Fixes an instantiated rig so it renders right (shared by pedestrians, ragdolls and the
## player's avatar). The rig's skeleton is in centimeters under a 0.01 armature while the mesh
## bounds are in meters, so the imported AABB is 2 cm tall and the renderer culls the character:
## give the skinned mesh a generous box in skeleton units. Meshy's animated export also keeps
## only the base color and leaves the glTF defaults of metallic 1 plus a full emission of the
## same texture (a shiny, self-lit mannequin): make it plain skin and cloth. The material is
## shared by every instance of the model.
static func prepare_rig(inst: Node3D, look: int = -1) -> void:
	var body_mat: ShaderMaterial = null
	var hairs: Array[MeshInstance3D] = []
	for node in inst.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		mi.custom_aabb = AABB(Vector3(-150.0, -10.0, -150.0), Vector3(300.0, 260.0, 300.0))
		if is_hair(mi):
			hairs.append(mi)
			continue
		var mat := mi.mesh.surface_get_material(0) as StandardMaterial3D
		if mat and mat.metallic_texture == null:
			mat.metallic = 0.0
			mat.roughness = 0.85
			mat.emission_enabled = false
		if mat and mat.albedo_texture and mi.skin:
			_note_rig(mi, mat)
		if look >= 0 and mat:
			mi.material_override = character_material(mat.albedo_texture, look)
			if mi.material_override and body_mat == null:
				body_mat = mi.material_override as ShaderMaterial
	# The crowd rigs' hair cards: cut out on their own shader in the look's hair colour (the
	# same colour the look gives the scalp under them), and never in a shadow pass - a head's
	# shadow is the same shape without them, and alpha-tested cards are what a shadow pass pays
	# most for.
	for mi in hairs:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var src := mi.mesh.surface_get_material(0) as StandardMaterial3D
		if src and src.albedo_texture:
			mi.material_override = hair_material(src.albedo_texture, body_mat)


## The crowd rigs built by tools/crowd carry their hair cards, brows and lashes as a second skinned
## mesh, "Hair", next to the opaque "Body". Everything that swaps a rig's material, cuts its limbs
## or bakes it into a figure works on the body alone; the hair keeps its own material (and goes
## with the head when a limb hider collapses the head bone).
static func is_hair(mi: MeshInstance3D) -> bool:
	return mi != null and String(mi.name).begins_with("Hair")


## Puts every hair mesh of `inst` back in its photographed colour: for the looks (a uniform, a
## rough sleeper's worn clothes) that keep the person's own hair on the body. `grime` dulls and
## dries it (a rough sleeper's).
static func plain_hair(inst: Node, grime: float = 0.0) -> void:
	for node in inst.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if is_hair(mi):
			var src := mi.mesh.surface_get_material(0) as StandardMaterial3D
			if src and src.albedo_texture:
				mi.material_override = hair_material(src.albedo_texture, null, grime)


## What the region-masked rigs (tools/crowd) need beyond their colour texture, keyed by it:
## "normal" (the glTF material's normal map) and "means" (the mean texture value of the top, the
## bottom and the hair regions, gamma space: what the shader keeps a recolour's shading round).
static var _rig_info: Dictionary = {}
## The crowd rigs' tiling surface detail (character.gdshader detail_tex) and their skin's Forward+
## subsurface strength.
const CROWD_DETAIL := "res://assets/textures/crowd/crowd_detail.png"
const CROWD_SKIN_SSS := 0.35
static var _hair_means: Dictionary = {}
static var _hair_looks: Dictionary = {}


## Remembers a region-masked rig's extras the first time one is prepared (a colour array on the
## skinned surface is what marks one; the older single-texture rigs have none).
static func _note_rig(mi: MeshInstance3D, mat: StandardMaterial3D) -> void:
	var tex := mat.albedo_texture
	if _rig_info.has(tex) or mi.mesh == null or mi.mesh.get_surface_count() == 0:
		return
	if mi.mesh.surface_get_format(0) & Mesh.ARRAY_FORMAT_COLOR == 0:
		return
	_rig_info[tex] = {"normal": mat.normal_texture, "means": _region_means(mi.mesh, tex)}


## Mean gamma-space texture value under each region (top, bottom, hair) of a masked rig, sampled
## at the centres of a spread of its triangles. The defaults when there is no mesh or image data
## (the headless check's dummy renderer).
static func _region_means(mesh: Mesh, tex: Texture2D) -> Vector3:
	var out := Vector3(0.5, 0.35, 0.18)
	var arrays := mesh.surface_get_arrays(0)
	if arrays.is_empty() or arrays[Mesh.ARRAY_COLOR] == null or arrays[Mesh.ARRAY_TEX_UV] == null \
			or arrays[Mesh.ARRAY_INDEX] == null:
		return out
	var img := tex.get_image()
	if img == null or img.is_empty():
		return out
	if img.is_compressed():
		img = img.duplicate() as Image
		img.decompress()
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var w := img.get_width()
	var h := img.get_height()
	var sum := Vector3.ZERO
	var cnt := Vector3.ZERO
	for t in range(0, index.size() / 3, 3):
		var a := index[t * 3]
		var b := index[t * 3 + 1]
		var c := index[t * 3 + 2]
		var uv := (uvs[a] + uvs[b] + uvs[c]) / 3.0
		var col := (colors[a] + colors[b] + colors[c]) / 3.0
		var px := img.get_pixel(clampi(int(uv.x * w), 0, w - 1), clampi(int(uv.y * h), 0, h - 1))
		var val := maxf(px.r, maxf(px.g, px.b))
		# The region levels also carry the fabric (0.25-1.0): weigh by which region, not how much.
		var wt := Vector3(1.0 if col.r > 0.1 else 0.0, 1.0 if col.g > 0.1 else 0.0, col.b * (1.0 - clampf(col.b + col.a - 1.0, 0.0, 1.0)))
		sum += wt * val
		cnt += wt
	for k in 3:
		if cnt[k] > 2.0:
			out[k] = sum[k] / cnt[k]
	return out


## Mean brightness of a hair atlas' opaque texels (the hair shader's recolour is a ratio to it).
static func _hair_mean(tex: Texture2D) -> float:
	if _hair_means.has(tex):
		return _hair_means[tex]
	var mean := 0.2
	var img := tex.get_image()
	if img != null and not img.is_empty():
		if img.is_compressed():
			img = img.duplicate() as Image
			img.decompress()
		var sum := 0.0
		var n := 0.0
		var step := maxi(img.get_width() / 128, 1)
		for y in range(0, img.get_height(), step):
			for x in range(0, img.get_width(), step):
				var c := img.get_pixel(x, y)
				if c.a > 0.6:
					sum += c.r * 0.299 + c.g * 0.587 + c.b * 0.114
					n += 1.0
		if n > 10.0:
			mean = sum / n
	_hair_means[tex] = mean
	return mean


## The hair cards' material for a look: the hair colour and strength of `look_mat` (the body's
## character material, so the cards match the scalp under them), or the photographed colour when
## there is none. Shared by every wearer of that look.
static func hair_material(albedo: Texture2D, look_mat: ShaderMaterial, grime: float = 0.0) -> ShaderMaterial:
	var color := Color(0.05, 0.04, 0.035)
	var strength := 0.0
	if look_mat:
		color = look_mat.get_shader_parameter("hair_color")
		strength = look_mat.get_shader_parameter("hair_strength")
	var key := "%d_%s_%.3f_%.2f" % [albedo.get_instance_id(), color.to_html(), strength, grime]
	if _hair_looks.has(key):
		return _hair_looks[key]
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/crowd_hair.gdshader")
	mat.set_shader_parameter("albedo_tex", albedo)
	mat.set_shader_parameter("atlas_mean", _hair_mean(albedo))
	mat.set_shader_parameter("hair_color", color)
	mat.set_shader_parameter("hair_strength", strength)
	mat.set_shader_parameter("grime", grime)
	_hair_looks[key] = mat
	return mat


## Character materials, shared by look so a crowd of hundreds still uses a handful of materials.
## `look` picks a clothing hue and brightness; see shaders/character.gdshader.
## Skin tones, as multipliers on the model's own complexion (see shaders/character.gdshader).
## Small on purpose. With two models these went down to 0.56, to stand in for a range of
## complexions the models did not have - and multiplying a pale face that far gives grey mud,
## not a darker person. The range of people now comes from the models themselves; this only
## keeps two copies of one model from being the same colour.
const SKIN_TINTS := [
	Color(1.02, 0.99, 0.96), Color(0.97, 0.93, 0.88), Color(1.0, 1.0, 1.0),
	Color(0.93, 0.88, 0.82), Color(1.03, 1.0, 0.98), Color(0.95, 0.91, 0.86),
	Color(0.99, 0.95, 0.91),
]
## Hair, beards and eyebrows. Taken outright rather than tinted (see the shader): the source
## hair is nearly black on every model, so a tint of it stays nearly black and a whole city
## walks around with the same head. Weighted the way a street looks - mostly dark, a few fair,
## the odd grey head.
const HAIR_COLORS := [
	Color(0.045, 0.038, 0.035), Color(0.075, 0.058, 0.048), Color(0.13, 0.090, 0.060),
	Color(0.20, 0.135, 0.085), Color(0.30, 0.190, 0.105), Color(0.42, 0.285, 0.145),
	Color(0.36, 0.150, 0.075), Color(0.55, 0.425, 0.225), Color(0.72, 0.600, 0.380),
	Color(0.52, 0.505, 0.485), Color(0.78, 0.770, 0.745),
]
const CHARACTER_LOOKS := 24
## Texture-value bands the character shader splits skin, hair and cloth on, written in gamma
## (sRGB) space - the numbers you read straight off the texture file in an image viewer.
## Measured over triangle-interior samples of both rigs: garments and hair top out near value
## 0.40 and lit skin starts near 0.65, so SKIN_VALUE_BAND sits in the gap with room either side.
## Brightness is the only test that separates them on pedestrian_c, whose jacket and trousers are
## the same warm brown as its skin.
const SKIN_VALUE_BAND := Vector2(0.44, 0.62)
## Hair is the dark half of the head band, the face the bright half. Hair sits at 0.19-0.40 and a
## face at 0.65-0.95 on both rigs.
const HAIR_VALUE_BAND := Vector2(0.32, 0.55)
## Below the first number a pixel is a seam, a deep fold or the shadow under a hem: hue means
## nothing there and recolouring it makes fabric look printed on. Above the second it is cloth
## and takes the garment colour in full. The band used to be 0.045..0.13, which put the rigs'
## own near-black trousers (about 0.10) only halfway up it, so trousers took barely half the
## recolour and stayed black however they were rolled.
const CLOTH_VALUE_BAND := Vector2(0.030, 0.075)
## The source hair's own shading is mapped from this value band onto this brightness range, so a
## recoloured head still shows strands and roots instead of going flat. Applied in gamma space
## inside the shader, so unlike the bands above this one is not converted per renderer.
const HAIR_SHADE_BAND := Vector2(0.18, 0.45)
const HAIR_SHADE_RANGE := Vector2(0.55, 1.0)
static var _looks: Dictionary = {}


## Moves a texture-value threshold from gamma (sRGB) space into whichever space this renderer
## hands `source_color` textures back in.
##
## Forward+ and Mobile sample such a texture through an sRGB view, so the shader sees a LINEAR
## value; the Compatibility renderer (the web build) hands back the raw sRGB texels. The picture
## on screen is the same either way, but the numbers the shader compares against are not, and
## every threshold in character.gdshader was written against the sRGB ones. On desktop that put
## every threshold in the wrong place: a garment at sRGB 0.35 arrives as 0.10, its saturation
## arrives much higher, and the shader called the whole body skin - so no pedestrian's clothes
## were ever recoloured in the Mac build at all. Verified by rendering a known grey through a
## source_color sampler under both renderers.
static func _texture_is_linear() -> bool:
	return RenderingServer.get_current_rendering_method() != "gl_compatibility"


static func _texture_value(v: float) -> float:
	if not _texture_is_linear():
		return v
	return v / 12.92 if v <= 0.04045 else pow((v + 0.055) / 1.055, 2.4)


## How hard the baked relief reads. The maps carry a tangent slope of about 8 degrees, which is
## fabric weave and skin, not armour plate, so this wants to stay near 1.
const NORMAL_STRENGTH := 1.0


## The relief map that goes with a rig's colour texture, or null if that rig has none.
static func _normal_map_for(albedo: Texture2D) -> Texture2D:
	var path := albedo.resource_path
	var cut := path.find("_anim_texture")
	if cut < 0:
		return null
	var nrm := path.substr(0, cut) + "_nrm.png"
	if not ResourceLoader.exists(nrm):
		return null
	return load(nrm) as Texture2D


static func character_material(albedo: Texture2D, look: int) -> ShaderMaterial:
	if albedo == null:
		return null
	var key := "%d_%d" % [albedo.get_instance_id(), look % CHARACTER_LOOKS]
	if _looks.has(key):
		return _looks[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = 4200 + (look % CHARACTER_LOOKS)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/character.gdshader")
	mat.set_shader_parameter("albedo_tex", albedo)
	# The rig's baked relief map, named after the rig the albedo came from
	# (pedestrian_a_anim_texture_0.jpg -> pedestrian_a_nrm.png). Rigs without one keep
	# normal_strength at the shader's 0.0 and render off the mesh normal exactly as before.
	var nrm := _normal_map_for(albedo)
	var info: Dictionary = _rig_info.get(albedo, {})
	if not info.is_empty():
		mat.set_shader_parameter("region_mask", 1.0)
		var means: Vector3 = info.means
		mat.set_shader_parameter("top_mean", means.x)
		mat.set_shader_parameter("bottom_mean", means.y)
		mat.set_shader_parameter("hair_mean", means.z)
		nrm = info.normal
		# Pores, knit, twill and weave (tools/crowd/make_detail.py), the skin's subsurface warmth
		# on Forward+, the wet eye: one shared texture and a few numbers, nothing per look.
		if ResourceLoader.exists(CROWD_DETAIL):
			mat.set_shader_parameter("detail_tex", load(CROWD_DETAIL))
			mat.set_shader_parameter("detail_strength", 1.0)
		mat.set_shader_parameter("skin_sss", CROWD_SKIN_SSS)
	if nrm != null:
		mat.set_shader_parameter("normal_tex", nrm)
		mat.set_shader_parameter("normal_strength", NORMAL_STRENGTH)
	# Half the looks keep the model's own outfit. The recolour was the only source of variety
	# when there were two models; with a real wardrobe of them, a photographed jacket beats a
	# repainted one, so it now only has to stop two copies of a model dressing alike.
	var plain := look % 2 == 0
	# The top, rolled as a wardrobe rather than as one range. `cloth_value` is the garment's own
	# brightness, 0 black to 1 white; the shader keeps the source texture's value as shading
	# around it. It used to be a multiplier on that source value, which is why the whole city
	# wore black: the rigs' garments are dark in the texture and their trousers nearly so, and
	# no multiplier lifts a dark texel to a white shirt.
	var top := rng.randf()
	mat.set_shader_parameter("cloth_hue", rng.randf())
	if top < 0.30:
		# White, cream, pale grey - the commonest thing anybody actually wears.
		mat.set_shader_parameter("cloth_sat", rng.randf_range(0.0, 0.09))
		mat.set_shader_parameter("cloth_value", rng.randf_range(0.80, 0.96))
	elif top < 0.56:
		# Mid tones: navy, olive, burgundy, tan.
		mat.set_shader_parameter("cloth_sat", rng.randf_range(0.18, 0.42))
		mat.set_shader_parameter("cloth_value", rng.randf_range(0.30, 0.58))
	elif top < 0.80:
		# Dark: black, charcoal, deep navy. Still a quarter of the street, just not all of it.
		mat.set_shader_parameter("cloth_hue", rng.randf_range(0.55, 0.72))
		mat.set_shader_parameter("cloth_sat", rng.randf_range(0.0, 0.20))
		mat.set_shader_parameter("cloth_value", rng.randf_range(0.07, 0.22))
	else:
		# Something bright.
		mat.set_shader_parameter("cloth_sat", rng.randf_range(0.45, 0.80))
		mat.set_shader_parameter("cloth_value", rng.randf_range(0.45, 0.78))
	# High, because what it mixes AWAY from is the source garment, which is near-black: at 0.7
	# a white shirt still came out mid-grey once Forward+ had linearised the base underneath it.
	mat.set_shader_parameter("cloth_strength", 0.0 if plain else rng.randf_range(0.80, 0.95))
	# Trousers are rolled apart from the top, and weighted the way a pavement actually looks:
	# denim, black and grey, khaki, and only occasionally something bright. Matching the top to
	# the bottom is what made every recoloured character read as wearing a boiler suit.
	var lower := rng.randf()
	if lower < 0.40:
		mat.set_shader_parameter("pants_hue", rng.randf_range(0.55, 0.68)) # denim
		mat.set_shader_parameter("pants_sat", rng.randf_range(0.10, 0.34))
		mat.set_shader_parameter("pants_value", rng.randf_range(0.16, 0.38))
	elif lower < 0.70:
		mat.set_shader_parameter("pants_hue", rng.randf()) # black through to pale grey
		mat.set_shader_parameter("pants_sat", rng.randf_range(0.0, 0.07))
		mat.set_shader_parameter("pants_value", rng.randf_range(0.06, 0.72))
	elif lower < 0.90:
		mat.set_shader_parameter("pants_hue", rng.randf_range(0.07, 0.20)) # khaki, sand, olive
		mat.set_shader_parameter("pants_sat", rng.randf_range(0.12, 0.32))
		mat.set_shader_parameter("pants_value", rng.randf_range(0.40, 0.66))
	else:
		mat.set_shader_parameter("pants_hue", rng.randf())
		mat.set_shader_parameter("pants_sat", rng.randf_range(0.30, 0.55))
		mat.set_shader_parameter("pants_value", rng.randf_range(0.28, 0.58))
	mat.set_shader_parameter("pants_strength", 0.0 if plain else rng.randf_range(0.82, 0.96))
	mat.set_shader_parameter("hair_color", HAIR_COLORS[rng.randi() % HAIR_COLORS.size()])
	# A look that keeps the model's own clothes keeps its own hair too. The hair swap was rolled
	# for every look, so a Black woman in her own blazer came out blonde and a grey-haired man
	# came out black-haired - a recolour on a photographed person reads as a wig.
	mat.set_shader_parameter("hair_strength", 0.0 if plain else rng.randf_range(0.75, 1.0))
	# The crowd rigs keep their own hair: each was given a colour that suits the person (a grey head
	# on the elderly, black on most), and a rolled one put white brows on a young man.
	if not info.is_empty():
		mat.set_shader_parameter("hair_strength", 0.0)
	mat.set_shader_parameter("skin_tint", SKIN_TINTS[look % SKIN_TINTS.size()])
	# Every threshold the shader compares a texture value against, moved into this renderer's
	# colour space (see _texture_value). Cheaper than converting the sample per pixel, and the
	# two renderers then classify identically.
	mat.set_shader_parameter("skin_value_lo", _texture_value(SKIN_VALUE_BAND.x))
	mat.set_shader_parameter("skin_value_hi", _texture_value(SKIN_VALUE_BAND.y))
	mat.set_shader_parameter("hair_value_lo", _texture_value(HAIR_VALUE_BAND.x))
	mat.set_shader_parameter("hair_value_hi", _texture_value(HAIR_VALUE_BAND.y))
	mat.set_shader_parameter("cloth_value_lo", _texture_value(CLOTH_VALUE_BAND.x))
	mat.set_shader_parameter("cloth_value_hi", _texture_value(CLOTH_VALUE_BAND.y))
	# The garment colours and the hair shading ramp are built in gamma space inside the shader,
	# so they only need to know which space the texture arrived in.
	mat.set_shader_parameter("value_is_linear", 1.0 if _texture_is_linear() else 0.0)
	# Straight-line fit of the hair shading ramp across its band.
	var shade_gain := (HAIR_SHADE_RANGE.y - HAIR_SHADE_RANGE.x) / maxf(HAIR_SHADE_BAND.y - HAIR_SHADE_BAND.x, 0.0001)
	mat.set_shader_parameter("hair_shade_gain", shade_gain)
	mat.set_shader_parameter("hair_shade_bias", HAIR_SHADE_RANGE.x - shade_gain * HAIR_SHADE_BAND.x)
	_looks[key] = mat
	return mat


## The player's tracksuit: jacket and trousers in one velour colour with white piping down the
## sleeves and legs (shaders/character.gdshader). Its own material rather than a crowd look, so
## nobody on the street is dressed like the hero. Pair it with add_piping() on the same rig, or
## the stripes have no data to draw from.
static func tracksuit_material(albedo: Texture2D, color: Color) -> ShaderMaterial:
	var look := character_material(albedo, 1)
	if look == null:
		return null
	var mat := look.duplicate() as ShaderMaterial
	for part in ["cloth", "pants"]:
		mat.set_shader_parameter(part + "_hue", color.h)
		mat.set_shader_parameter(part + "_sat", color.s)
		mat.set_shader_parameter(part + "_value", color.v)
		mat.set_shader_parameter(part + "_strength", 0.97)
	# The rig's own hair and complexion: it is still the same person, just changed.
	mat.set_shader_parameter("hair_strength", 0.0)
	mat.set_shader_parameter("skin_tint", Color(1, 1, 1))
	mat.set_shader_parameter("cloth_roughness", 0.92)
	mat.set_shader_parameter("velour", TRACKSUIT_SHEEN)
	mat.set_shader_parameter("piping", 1.0)
	mat.set_shader_parameter("cloth_shade_keep", 0.5)
	return mat


## Rim sheen of the tracksuit's velour (0 flat cotton, 1 satin-bright edges).
const TRACKSUIT_SHEEN := 0.6
## Arm and leg bones that carry the piping, each with the bone its axis points at.
const PIPING_BONES := {
	"LeftArm": "LeftForeArm", "LeftForeArm": "LeftHand",
	"RightArm": "RightForeArm", "RightForeArm": "RightHand",
	"LeftUpLeg": "LeftLeg", "LeftLeg": "LeftFoot",
	"RightUpLeg": "RightLeg", "RightLeg": "RightFoot",
}


## Bakes where the tracksuit piping runs into every skinned mesh of a rig, as CUSTOM0: for each
## vertex, its signed distance in metres round its arm or leg from the limb's outer line, how
## much of it follows arm and leg bones and how squarely it faces outward; and as CUSTOM1 how
## much of it follows the head and the hands (the only places skin can be) and the feet (the
## shoes, which keep their own colour). Measured on the
## rest pose, so the stripes are part of the cloth and move with it rather than being painted
## on in screen or model space, where they would slide over the sleeve as the arm swings.
## The outer line of a leg is its side away from the body's midline; an arm's is taken from
## "out and a little up", which on an A-posed or T-posed rest arm is its top - the side that
## faces out once it hangs. Needs mesh data, which the headless dummy renderer does not keep:
## there it changes nothing.
static func add_piping(inst: Node3D) -> void:
	var skel := inst.find_child("Skeleton3D", true, false) as Skeleton3D
	if skel == null:
		return
	var rig_xf := Ragdoll._rig_space_of_skel(skel)
	var hips := skel.find_bone("Hips")
	var mid_x := (rig_xf * skel.get_bone_global_rest(hips).origin).x if hips >= 0 else 0.0
	for node in inst.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.skin == null or mi.mesh == null or mi.mesh.get_surface_count() != 1:
			continue
		var arrays := mi.mesh.surface_get_arrays(0)
		if arrays.is_empty() or arrays[Mesh.ARRAY_BONES] == null or arrays[Mesh.ARRAY_WEIGHTS] == null:
			continue
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		if verts.is_empty() or bones.size() % verts.size() != 0:
			continue
		var per := bones.size() / verts.size()
		# Per skin bind: its rest transform into model space, and for a limb bone its axis
		# (origin, direction) and the frame round it (outer line, and the line 90 degrees on).
		var bind_xf: Array[Transform3D] = []
		var limb: Array = []
		for i in mi.skin.get_bind_count():
			var bname := String(mi.skin.get_bind_name(i))
			var bone := skel.find_bone(bname)
			var rest := skel.get_bone_global_rest(bone) if bone >= 0 else Transform3D.IDENTITY
			bind_xf.append(rig_xf * rest * mi.skin.get_bind_pose(i))
			var child := skel.find_bone(PIPING_BONES.get(bname, ""))
			if bone < 0 or child < 0:
				limb.append(null)
				continue
			var o := rig_xf * rest.origin
			var axis := (rig_xf * skel.get_bone_global_rest(child).origin - o).normalized()
			var side := signf(o.x - mid_x)
			var hint := Vector3(side, 0.6 if bname.ends_with("Arm") else 0.0, 0.0)
			var out := (hint - axis * hint.dot(axis)).normalized()
			limb.append([o, axis, out, axis.cross(out) * side])
		# 1 the head, 2 a hand, 3 a foot.
		var skin_bind := PackedByteArray()
		skin_bind.resize(mi.skin.get_bind_count())
		for i in mi.skin.get_bind_count():
			var bn := String(mi.skin.get_bind_name(i))
			skin_bind[i] = 1 if bn.begins_with("head") or bn == "Head" else (2 if bn.ends_with("Hand") else (3 if bn.ends_with("Foot") or bn.ends_with("ToeBase") else 0))
		var custom := PackedFloat32Array()
		custom.resize(verts.size() * 3)
		var custom1 := PackedFloat32Array()
		custom1.resize(verts.size() * 3)
		for v in verts.size():
			var pos := Vector3.ZERO
			var total := 0.0
			var on_limb := 0.0
			var on_head := 0.0
			var on_hand := 0.0
			var on_foot := 0.0
			var best := -1
			var best_w := 0.0
			for k in per:
				var w := weights[v * per + k]
				var bi := bones[v * per + k]
				if w <= 0.0 or bi < 0 or bi >= bind_xf.size():
					continue
				pos += bind_xf[bi] * verts[v] * w
				total += w
				if skin_bind[bi] == 1:
					on_head += w
				elif skin_bind[bi] == 2:
					on_hand += w
				elif skin_bind[bi] == 3:
					on_foot += w
				if limb[bi] != null:
					on_limb += w
					if w > best_w:
						best_w = w
						best = bi
			pos /= maxf(total, 0.0001)
			var arc := 0.0
			var facing := -1.0
			if best >= 0:
				var l: Array = limb[best]
				var radial: Vector3 = pos - l[0]
				radial -= (l[1] as Vector3) * radial.dot(l[1])
				var r := radial.length()
				if r > 0.0001:
					var c := radial.dot(l[2]) / r
					arc = atan2(radial.dot(l[3]) / r, c) * r
					facing = c
			custom[v * 3] = arc
			custom[v * 3 + 1] = on_limb / maxf(total, 0.0001)
			custom[v * 3 + 2] = facing
			custom1[v * 3] = on_head / maxf(total, 0.0001)
			custom1[v * 3 + 1] = on_hand / maxf(total, 0.0001)
			custom1[v * 3 + 2] = on_foot / maxf(total, 0.0001)
		arrays[Mesh.ARRAY_CUSTOM0] = custom
		arrays[Mesh.ARRAY_CUSTOM1] = custom1
		var flags := (Mesh.ARRAY_CUSTOM_RGB_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) | (Mesh.ARRAY_CUSTOM_RGB_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT)
		if per == 8:
			flags |= Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)
		mesh.surface_set_material(0, mi.mesh.surface_get_material(0))
		mi.mesh = mesh


func _add_hit_area() -> void:
	# Hit detector: anything fast on the props layer, or a fast player.
	var area := Area3D.new()
	area.collision_layer = 0
	area.collision_mask = 2 | 4
	# Nothing looks for this zone, and a monitorable area sits in the broadphase's dynamic tree,
	# where every step it moves it is tested against the whole city's static geometry.
	area.monitorable = false
	var ashape := CollisionShape3D.new()
	_hit_shape = ashape
	var abox := BoxShape3D.new()
	abox.size = Vector3(1.0, 1.8, 1.0)
	ashape.shape = abox
	ashape.position = Vector3(0.0, 0.9, 0.0)
	area.add_child(ashape)
	area.body_entered.connect(_on_body_entered)
	add_child(area)


func _part(size: Vector3, pos: Vector3, color: Color) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = PropFactory.material(color, 0.8)
	mesh.position = pos
	_visual.add_child(mesh)


func _physics_process(delta: float) -> void:
	if _down:
		return
	_lod_timer += delta
	if _lod_timer >= 0.5:
		_lod_timer = 0.0
		_update_lod()
	_lod_tick += 1
	if _lod_stride > 1 and _lod_tick % _lod_stride != 0:
		return
	delta *= _lod_stride
	if _anim:
		_anim.advance(delta)
	_walk(delta)
	_animate_gait()
	if _look_near:
		_post_pose(delta)
	if _life_ok:
		_life_pose(delta)
	if not errand.is_empty():
		StreetErrands.pose(self, delta)


func _walk(delta: float) -> void:
	var panicking := _panic_left > 0.0
	if panicking:
		_panic_left -= delta
		if _scream_in >= 0.0:
			_scream_in -= delta
			if _scream_in < 0.0:
				_scream()
		if _panic_left <= 0.0:
			_scream_in = -1.0
			if _cross != Cross.CROSSING:
				_go_to(_random_ring_point(_sidewalk))
	# On an errand (StreetErrands: a bus, a shop, a parked car, over the road mid-block).
	if (_life_near or not errand.is_empty()) and StreetErrands.walk(self, delta, panicking):
		return
	# Standing still: waiting at a kerb, looking in a window, checking a phone. A crowd where
	# every single person walks without ever stopping reads as a conveyor belt.
	if _pause_left > 0.0:
		_pause_left -= delta
		if _speed > 0.02:
			# The last short step or two of a stop, not a freeze on the spot.
			_speed = move_toward(_speed, 0.0, stop_decel * delta)
			var f := Vector2(-sin(_visual.rotation.y), -cos(_visual.rotation.y)) * _speed
			_move(f, delta)
			return
		_speed = 0.0
		_pivoting = false
		velocity.x = 0.0
		velocity.z = 0.0
		# Someone standing on the pavement does not need a collision solve every step: only a
		# body that is still falling (just spawned, or knocked off a kerb) does.
		if not _kinematic and not is_on_floor():
			velocity.y -= 30.0 * delta
			move_and_slide()
		return
	if _act != CrowdLife.Act.NONE and _stage != Stage.GOING:
		if panicking:
			_end_act()
		else:
			_do_act(delta)
			return
	if _cross == Cross.WAIT:
		_wait_at_kerb(delta)
		return
	if _cross == Cross.CROSSING:
		_walk_crossing(delta, panicking)
		return
	# The parent's space, which for a chunk's walker is the true world plan `ring` is in. This
	# used to be the scene position, which is the same thing only until the first origin shift.
	var here := Vector2(position.x, position.z) - _ring_origin()
	if _route_pending:
		_route_pending = false
		_route = _ring_route(here, _target)
	var goal := _target if _route.is_empty() else _route[0]
	var to_target := goal - here
	if to_target.length() < 1.0 and not _route.is_empty():
		_route.remove_at(0)
		goal = _target if _route.is_empty() else _route[0]
		to_target = goal - here
	# A leg that ends standing (a kerb, a pause) is walked into slowly and ended close.
	var stops := _route.is_empty() and not panicking and (_cross == Cross.TO_KERB or _pause_next > 0.0 or _act != CrowdLife.Act.NONE)
	if to_target.length() < (0.35 if stops else 1.0):
		if _cross == Cross.TO_KERB:
			_arrive_at_kerb()
			return
		if _act != CrowdLife.Act.NONE and not panicking:
			_arrive_act()
			return
		if panicking:
			_go_to(_flee_point())
		elif _way.randf() < cross_chance and plan_crossing(-1):
			pass
		elif _life_near and _life.randf() < life_chance and _try_life(false):
			if _stage != Stage.GOING:
				return
		else:
			_go_to(_random_ring_point(_sidewalk))
			if _pause_next > 0.0:
				_pause_left = _pause_next
				_pause_next = 0.0
			# Rolled now, taken at the end of the new leg, so the walker slows into it.
			if _has_idle and _style.randf() < pause_chance and not _jogger:
				_pause_next = _style.randf_range(pause_seconds.x, pause_seconds.y)
		goal = _target if _route.is_empty() else _route[0]
		to_target = goal - here
		stops = _route.is_empty() and not panicking and (_cross == Cross.TO_KERB or _pause_next > 0.0 or _act != CrowdLife.Act.NONE)
	var want := _run_pace if panicking else walk_speed
	if stops:
		want = minf(want, sqrt(2.0 * stop_decel * maxf(to_target.length() - 0.2, 0.0)) + 0.15)
	var v := _steer(to_target, want, delta, panicking)
	_move(v, delta)
	if not _kinematic:
		# Walked square into something flat - a bus shelter, a news box, a parked car over the
		# kerb - since walkers keep to the pavement band now: somewhere else, not the same spot
		# marched on for ever.
		var real := get_real_velocity()
		if _speed > 0.5 and Vector2(real.x, real.z).length() < _speed * 0.25:
			_walk_stuck_t += delta
			if _walk_stuck_t > 0.8:
				_walk_stuck_t = 0.0
				_end_act(true)
				_go_to(_flee_point() if panicking else _random_ring_point(_sidewalk))
		else:
			_walk_stuck_t = 0.0
	if _anim == null:
		_bob += delta * _speed * 4.0
		_visual.position.y = absf(sin(_bob)) * 0.06


## Moves along the ground at `v` (m/s, XZ): placed directly out of the player's reach, through
## move_and_slide inside it.
func _move(v: Vector2, delta: float) -> void:
	velocity.x = v.x
	velocity.z = v.y
	if _kinematic or _act == CrowdLife.Act.SIT:
		# Out of reach of the player: walk the pavement directly, on the chunk's own ground
		# height, with no collision solve. The ring is open pavement, so the path is the same
		# one move_and_slide would have taken.
		var at := position + Vector3(velocity.x, 0.0, velocity.z) * delta
		at.y = _ground_y(at.x, at.z, position.y)
		position = at
	else:
		if not is_on_floor():
			velocity.y -= 30.0 * delta
		else:
			velocity.y = 0.0
		move_and_slide()


## After the clip has posed the rig (near people only): the arm swing scaled to this person's
## own, and the head (and a little of the neck) turned to whatever is going on nearby.
func _post_pose(delta: float) -> void:
	if _head_skel == null:
		return
	if _arm_bones.size() == 2 and _clip == WALK_CLIP and absf(_arm_swing - 1.0) > 0.02:
		var means: Array = _arm_means.get(_model_path, [])
		for i in mini(means.size(), 2):
			var mean: Quaternion = means[i]
			var dq := mean.inverse() * _head_skel.get_bone_pose_rotation(_arm_bones[i])
			if dq.w < 0.0:
				dq = -dq
			var axis := Vector3(dq.x, dq.y, dq.z)
			if axis.length_squared() > 1e-8:
				var ang := 2.0 * atan2(axis.length(), dq.w)
				_head_skel.set_bone_pose_rotation(_arm_bones[i], mean * Quaternion(axis.normalized(), ang * _arm_swing))
	if _look_bones.size() != 2:
		return
	_look_hold = maxf(_look_hold - delta, 0.0)
	_look_scan -= delta
	if _look_scan <= 0.0:
		_look_scan = 0.3 + _anim_rng.randf() * 0.25
		_pick_look()
	var want_yaw := 0.0
	var want_pitch := _posture_pitch
	var face := _visual.global_rotation.y
	if _look_point != Vector3.INF:
		var d := _look_point - (global_position + Vector3.UP * 1.55 * _visual.scale.y)
		var rel := angle_difference(face, atan2(-d.x, -d.z))
		if absf(rel) < deg_to_rad(115.0):
			var reach := deg_to_rad(look_max_yaw)
			want_yaw = clampf(rel, -reach, reach)
			want_pitch = clampf(atan2(d.y, Vector2(d.x, d.z).length()), -0.45, 0.35)
	var k := 1.0 - exp(-look_speed * delta)
	_look_yaw = lerpf(_look_yaw, want_yaw, k)
	_look_pitch = lerpf(_look_pitch, want_pitch, k)
	if absf(_look_yaw) + absf(_look_pitch) < 0.003:
		return
	# Built in skeleton space round the world's up and the head's right, then handed to each
	# bone in its parent's frame; the neck takes 40 % of the turn and the head the rest.
	var to_skel := _head_skel.global_basis.orthonormalized().inverse()
	var up := (to_skel * Vector3.UP).normalized()
	var right := (to_skel * Vector3(cos(face), 0.0, -sin(face))).normalized()
	for i in 2:
		var bone := _look_bones[i]
		var share := 0.4 if i == 0 else 0.6
		var parent := _head_skel.get_bone_parent(bone)
		var pq := _head_skel.get_bone_global_pose(parent).basis.orthonormalized().get_rotation_quaternion() \
			if parent >= 0 else Quaternion.IDENTITY
		var r := Quaternion(up, _look_yaw * share) * Quaternion(right, _look_pitch * share)
		_head_skel.set_bone_pose_rotation(bone, (pq.inverse() * r * pq * _head_skel.get_bone_pose_rotation(bone)).normalized())


## What this person looks at next: a gunshot or blast they just heard, else a car going by
## close, else the player walking past; nothing (straight ahead) most of the time.
func _pick_look() -> void:
	_look_point = Vector3.INF
	if _look_hold > 0.0 and _look_threat != Vector3.INF:
		_look_point = _look_threat
		return
	if _life_look != Vector3.INF and _act != CrowdLife.Act.NONE:
		_look_point = _life_look
		return
	var me := global_position
	var best := look_car_range * look_car_range
	for car: Array in _nearby_cars(get_tree()):
		var at: Vector3 = car[0]
		var vel: Vector3 = car[1]
		var d2 := at.distance_squared_to(me)
		if d2 < best and vel.length_squared() > 9.0:
			best = d2
			_look_point = at + vel * 0.12 + Vector3.UP * 0.6
	if _look_point != Vector3.INF:
		return
	if is_instance_valid(_player) and _player.global_position.distance_squared_to(me) < look_player_range * look_player_range:
		_look_point = _player.global_position + Vector3.UP * 1.5


## Moving cars within reach of the player, [position, velocity], worked out once every quarter
## second for the whole crowd (velocity from the last survey, so kinematic traffic counts too).
static func _nearby_cars(tree: SceneTree) -> Array:
	var tick := Engine.get_physics_frames()
	if tick - _cars_tick < 15:
		return _cars
	var dt := float(tick - _cars_tick) / float(Engine.physics_ticks_per_second)
	_cars_tick = tick
	_cars = []
	var centre: Vector3 = _player.global_position if is_instance_valid(_player) else Vector3.INF
	var seen := {}
	for n in tree.get_nodes_in_group("vehicle"):
		var car := n as Node3D
		if car == null or not car.is_inside_tree():
			continue
		var at := car.global_position
		if centre != Vector3.INF and at.distance_squared_to(centre) > 2500.0:
			continue
		var id := car.get_instance_id()
		var vel := Vector3.ZERO
		if _cars_prev.has(id) and dt < 1.0:
			vel = (at - (_cars_prev[id] as Vector3)) / dt
			if vel.length_squared() > 1600.0: # an origin shift, not a car doing 144 km/h
				vel = Vector3.ZERO
		seen[id] = at
		_cars.append([at, vel])
	_cars_prev = seen
	return _cars


## The walk clip's mean rotation for each of `bones` (sign-aligned quaternion average of the
## keys), what the arm swing is scaled about.
static func _clip_means(anim: AnimationPlayer, skel: Skeleton3D, clip: String, bones: PackedInt32Array) -> Array:
	var out: Array = []
	if not anim.has_animation(clip):
		return out
	var a := anim.get_animation(clip)
	for bone in bones:
		var name := skel.get_bone_name(bone)
		var sum := Vector4.ZERO
		var first := Quaternion.IDENTITY
		for t in a.get_track_count():
			if a.track_get_type(t) != Animation.TYPE_ROTATION_3D or String(a.track_get_path(t).get_concatenated_subnames()) != name:
				continue
			for k in a.track_get_key_count(t):
				var q: Quaternion = a.track_get_key_value(t, k)
				if k == 0:
					first = q
				if first.dot(q) < 0.0:
					q = -q
				sum += Vector4(q.x, q.y, q.z, q.w)
		if sum.length_squared() < 1e-8:
			return []
		sum = sum.normalized()
		out.append(Quaternion(sum.x, sum.y, sum.z, sum.w))
	return out


## Far pedestrians move and animate every 2nd (past physics_range), 4th (past lod_mid) or 8th
## (past lod_far) physics frame with a matching delta, so a crowd of hundreds costs what a few
## dozen used to.
static var lod_mid: float = 60.0
static var lod_far: float = 140.0
## Pedestrians cast shadows only inside this range (metres). Measured on a downtown street, the
## crowd was 6.4 of the frame's 15.7 million triangles, because all 650 of them - 16k-triangle
## rigs since 2026-09-22 - were drawn once for the camera and again into up to four shadow
## cascades. A person's shadow past this is a few pixels, and the one cast by the building behind
## them is what the eye reads anyway.
static var shadow_range: float = 45.0
## Mesh LOD bias per distance tier (near, mid, middle body, far body): below 1 the renderer drops
## to the coarser generated LODs sooner. Nobody can see 16k triangles on a figure forty pixels tall.
## The two welded bodies have no LODs of their own, so their entries do nothing.
const LOD_BIAS := [1.0, 0.45, 0.45, 0.2]
## The models' own LODs stop at 8,300 and 5,500 of their 16,600 triangles: they are unwelded -
## most positions carry two or three UV copies - and the importer will not simplify across a
## seam. Measured at 1080p, most of the crowd between 45 and 140 m drew 8,300 a figure. So past
## mid_body_range a pedestrian wears a welded body of at most mid_triangles, and past lod_far one
## of at most far_triangles (far_mesh()). Set mid_body_range past lod_far to turn the middle one
## off.
static var mid_body_range: float = 50.0
## Most triangles the middle body (mid_body_range to lod_far) may have. The simplifier halves
## at each step, so this lands on ~2,080: side by side with the model at 50-140 m, 1,040 already
## lost the small bright pattern on the busiest jackets at 50 m and 2,080 did not.
static var mid_triangles: int = 2100
## Most triangles the far body (past lod_far) may have: ~520, a figure under ten pixels tall.
static var far_triangles: int = 600
## Welded bodies, keyed by the model mesh they stand in for, then by their triangle cap (see
## far_mesh()).
static var _far_meshes: Dictionary = {}
## A model's welded topology and its LOD chain, shared by every cap built from it (far_mesh()).
static var _welds: Dictionary = {}
## A welded body's triangle whose UVs span more than this many times the atlas a triangle of its
## size spans on the model takes one flat texel instead (_unweld()).
const STRETCH_LIMIT := 2.5
var _meshes: Array[MeshInstance3D] = []
var _draw_tier: int = -1
## Past this distance from the player (metres) a pedestrian walks without physics: no
## move_and_slide, no hit detector. Measured headless on a downtown block, the 625-strong crowd was
## 46 of 101 ms of physics a frame - a collision solve and an overlap test per person per step, to
## walk along flat pavement. Inside it everything is as before, so the ones you can reach still
## stumble, get knocked flying and stand on what they stand on.
static var physics_range: float = 35.0
var _kinematic: bool = false
var _hit_shape: CollisionShape3D


## Whether the head may be turned over the clip (a subclass that poses the rig itself says no).
func _head_look_ok() -> bool:
	return true


func _update_lod() -> void:
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
		if _player == null:
			_lod_stride = 1
			return
	var d := global_position.distance_to(_player.global_position)
	# Every step only inside physics_range, where they can be touched; then 30, 15 and 7.5 Hz.
	# A figure forty metres off moves 6 cm between updates at walking pace, which nobody can see,
	# and the crowd's scripts were 12 ms of every physics step at every-step-to-60-metres.
	_lod_stride = 1 if d < physics_range else (2 if d < lod_mid else (4 if d < lod_far else 8))
	_look_near = d < look_range and _head_skel != null and _head_look_ok()
	if _life_ok:
		var near := d < life_range and not _down
		if near != _life_near:
			_life_near = near
			_life_range_changed(near)
	var kinematic := d > physics_range and not _down
	if kinematic != _kinematic:
		_kinematic = kinematic
		# Out of range the body keeps its layer (bullets, blasts and car bumpers still find it)
		# but drops its mask, and the hit zone leaves the broadphase: otherwise each of several
		# hundred walkers is paired with every kerb, slab and wall it passes, and re-paired every
		# time it moves, for collisions that can never happen.
		collision_mask = 0 if kinematic else 1
		if _hit_shape:
			_hit_shape.disabled = kinematic
		if kinematic:
			velocity = Vector3.ZERO
	var tier := 0 if d < shadow_range else (3 if d >= lod_far else (2 if d >= mid_body_range else 1))
	if tier != _draw_tier:
		_draw_tier = tier
		for mi in _meshes:
			if is_instance_valid(mi) and is_hair(mi):
				# The welded middle and far bodies have no cards: the scalp under them is
				# painted in the hair colour, which is all a head is past mid_body_range.
				mi.visible = tier < 2 and not mi.has_meta("under_hat")
				mi.lod_bias = LOD_BIAS[tier]
			elif is_instance_valid(mi):
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if tier == 0 \
					else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				mi.lod_bias = LOD_BIAS[tier]
				if mi.skin:
					if not mi.has_meta("near_mesh"):
						mi.set_meta("near_mesh", mi.mesh)
					var near: Mesh = mi.get_meta("near_mesh")
					mi.mesh = near if tier < 2 \
						else far_mesh(near, far_triangles if tier == 3 else mid_triangles)


## A coarse body for people past mid_body_range / lod_far: the model welded to one vertex per
## position so the simplifier can go all the way down, cut to the first of its LODs with at most
## `cap` triangles (default far_triangles), then each triangle takes back, from the seam copies
## of its three corners, the three whose UVs lie closest together (_unweld()): welded to whichever
## copy came first, a triangle's corners could come from three UV islands across the atlas and
## some models' clothes came out skin-coloured. A triangle that still spans two islands takes one
## flat texel instead. The body has no LODs of its own, on purpose: the simplifier's error on a
## figure this thin says nothing about its limbs, and the chain it made
## - with errors measured in the mesh's metres, while the renderer weighs them by the instance's
## scale, 0.01 under these rigs' armature - had the renderer draw the old far body at its last
## level, 18-35 triangles, a stick. Built once per model and cap (the loading screen does all
## nine); the original mesh when there is no mesh data to weld (the headless check).
static func far_mesh(mesh: Mesh, cap: int = -1) -> Mesh:
	if mesh == null:
		return mesh
	if cap < 0:
		cap = far_triangles
	if not _far_meshes.has(mesh):
		_far_meshes[mesh] = {}
	var per_cap: Dictionary = _far_meshes[mesh]
	if per_cap.has(cap):
		return per_cap[cap]
	per_cap[cap] = mesh
	var w := _weld(mesh)
	if w.is_empty():
		return mesh
	var base: PackedInt32Array = (w.out as Array)[Mesh.ARRAY_INDEX]
	for lod: PackedInt32Array in w.lods:
		if lod.size() / 3 <= cap:
			base = lod
			break
	var result := _unweld(w, base, mesh.surface_get_material(0))
	per_cap[cap] = result
	return result


## The welded copy of a model's single skinned surface ({} when there is no mesh data): `out`
## (arrays, one vertex per position, the full index), `lods` (the simplifier's chain on it),
## `src` (the model's own arrays), `start` / `copies` (each welded vertex's source vertices, CSR).
static func _weld(mesh: Mesh) -> Dictionary:
	if _welds.has(mesh):
		return _welds[mesh]
	_welds[mesh] = {}
	var arrays := mesh.surface_get_arrays(0)
	if arrays.is_empty() or arrays[Mesh.ARRAY_INDEX] == null or arrays[Mesh.ARRAY_BONES] == null \
			or arrays[Mesh.ARRAY_TEX_UV] == null:
		return {}
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	if verts.is_empty():
		return {}
	var per: int = (arrays[Mesh.ARRAY_BONES] as PackedInt32Array).size() / verts.size()
	var first := {}
	var order := PackedInt32Array()
	var weld := PackedInt32Array()
	weld.resize(verts.size())
	for v in verts.size():
		var key := Vector3i(roundi(verts[v].x * 2000.0), roundi(verts[v].y * 2000.0), roundi(verts[v].z * 2000.0))
		if not first.has(key):
			first[key] = order.size()
			order.append(v)
		weld[v] = first[key]
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	for a in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_TEX_UV]:
		if arrays[a] == null:
			continue
		var src = arrays[a]
		var dst = src.duplicate()
		dst.resize(order.size())
		for i in order.size():
			dst[i] = src[order[i]]
		out[a] = dst
	for a in [Mesh.ARRAY_TANGENT, Mesh.ARRAY_BONES, Mesh.ARRAY_WEIGHTS]:
		if arrays[a] == null:
			continue
		var n := 4 if a == Mesh.ARRAY_TANGENT else per
		var src = arrays[a]
		var dst = src.duplicate()
		dst.resize(order.size() * n)
		for i in order.size():
			for k in n:
				dst[i * n + k] = src[order[i] * n + k]
		out[a] = dst
	var idx := PackedInt32Array()
	idx.resize(index.size())
	for i in index.size():
		idx[i] = weld[index[i]]
	out[Mesh.ARRAY_INDEX] = idx
	var im := ImporterMesh.new()
	im.add_surface(Mesh.PRIMITIVE_TRIANGLES, out, [], {}, mesh.surface_get_material(0))
	im.generate_lods(25.0, 60.0, [])
	var lods: Array[PackedInt32Array] = []
	for l in im.get_surface_lod_count(0):
		lods.append(im.get_surface_lod_indices(0, l))
	# Each welded vertex's source copies, compressed-row: copies[start[w] .. start[w + 1]).
	var start := PackedInt32Array()
	start.resize(order.size() + 1)
	for v in verts.size():
		start[weld[v] + 1] += 1
	for w in order.size():
		start[w + 1] += start[w]
	var fill := start.duplicate()
	var copies := PackedInt32Array()
	copies.resize(verts.size())
	for v in verts.size():
		copies[fill[weld[v]]] = v
		fill[weld[v]] += 1
	# Each source vertex's UV island: triangles that share a source vertex share a UV chart.
	var island := PackedInt32Array()
	island.resize(verts.size())
	for v in verts.size():
		island[v] = v
	for t in index.size() / 3:
		var r0 := _find(island, index[t * 3])
		for k in [1, 2]:
			var r := _find(island, index[t * 3 + k])
			if r != r0:
				island[r] = r0
	for v in verts.size():
		island[v] = _find(island, v)
	# The model's texel density: UV perimeter per metre of perimeter, median over its triangles.
	var src_uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var ratios := PackedFloat32Array()
	for t in range(0, index.size() / 3, 5):
		var i0 := index[t * 3]
		var i1 := index[t * 3 + 1]
		var i2 := index[t * 3 + 2]
		var p := verts[i0].distance_to(verts[i1]) + verts[i1].distance_to(verts[i2]) \
			+ verts[i2].distance_to(verts[i0])
		if p > 0.0:
			ratios.append((src_uv[i0].distance_to(src_uv[i1]) + src_uv[i1].distance_to(src_uv[i2])
				+ src_uv[i2].distance_to(src_uv[i0])) / p)
	ratios.sort()
	var density: float = ratios[ratios.size() / 2] if not ratios.is_empty() else INF
	var result := {"out": out, "lods": lods, "src": arrays, "per": per, "start": start, "copies": copies,
		"island": island, "density": density}
	_welds[mesh] = result
	return result


## Union-find root of `v` in `parent`, halving the path as it goes.
static func _find(parent: PackedInt32Array, v: int) -> int:
	while parent[v] != v:
		parent[v] = parent[parent[v]]
		v = parent[v]
	return v


## Turns a welded index list back into the model's own vertices: each triangle picks, among the
## seam copies of its three corners, three from one UV island if it can (fewest islands first),
## then the three whose UVs are closest together (the smallest UV perimeter), so it samples one
## patch of the texture rather than three. The islands come first because the atlas packs them
## side by side: by distance alone a leg could take a corner from the shoe's island next door.
static func _unweld(w: Dictionary, index: PackedInt32Array, material: Material) -> ArrayMesh:
	var src: Array = w.src
	var uv: PackedVector2Array = src[Mesh.ARRAY_TEX_UV]
	var start: PackedInt32Array = w.start
	var copies: PackedInt32Array = w.copies
	var island: PackedInt32Array = w.island
	var remap := PackedInt32Array()
	remap.resize(uv.size())
	remap.fill(-1)
	var order := PackedInt32Array()
	# Where each vertex takes its UV from (its own source vertex, or a flat triangle's texel).
	var uv_from := PackedInt32Array()
	var flat_map := {}
	var density: float = w.density
	var pos: PackedVector3Array = (w.out as Array)[Mesh.ARRAY_VERTEX]
	var res := PackedInt32Array()
	res.resize(index.size())
	for t in index.size() / 3:
		var a := index[t * 3]
		var b := index[t * 3 + 1]
		var c := index[t * 3 + 2]
		var best := INF
		var pick := Vector3i(copies[start[a]], copies[start[b]], copies[start[c]])
		if start[a + 1] - start[a] > 1 or start[b + 1] - start[b] > 1 or start[c + 1] - start[c] > 1:
			for i in range(start[a], mini(start[a + 1], start[a] + 6)):
				var ua := uv[copies[i]]
				var ia := island[copies[i]]
				for j in range(start[b], mini(start[b + 1], start[b] + 6)):
					var ub := uv[copies[j]]
					var ib := island[copies[j]]
					# Every island past the first costs more than any perimeter in a 0..1 atlas.
					var ab := ua.distance_to(ub) + (0.0 if ib == ia else 8.0)
					if ab >= best:
						continue
					for k in range(start[c], mini(start[c + 1], start[c] + 6)):
						var uc := uv[copies[k]]
						var ic := island[copies[k]]
						var p := ab + ub.distance_to(uc) + uc.distance_to(ua) \
							+ (0.0 if ic == ia or ic == ib else 8.0)
						if p < best:
							best = p
							pick = Vector3i(copies[i], copies[j], copies[k])
		# A triangle whose corners still span two UV islands, or stretch across far more of the
		# atlas than a triangle of its size should, would interpolate across whatever lies between
		# them in the atlas - streaks of face and shoe over a white top. It takes one corner's
		# texel instead, all three corners: a flat patch of the right colour.
		var flat := -1
		var pa := island[pick.x]
		var pb := island[pick.y]
		var pc := island[pick.z]
		if pa != pb or pb != pc:
			flat = pick.x if pa == pb or pa == pc else (pick.y if pb == pc else pick.x)
		else:
			var p3 := pos[a].distance_to(pos[b]) + pos[b].distance_to(pos[c]) + pos[c].distance_to(pos[a])
			var puv := uv[pick.x].distance_to(uv[pick.y]) + uv[pick.y].distance_to(uv[pick.z]) \
				+ uv[pick.z].distance_to(uv[pick.x])
			if puv > STRETCH_LIMIT * density * p3:
				flat = pick.x
		for n in 3:
			var v: int = pick[n]
			if flat < 0:
				if remap[v] < 0:
					remap[v] = order.size()
					order.append(v)
					uv_from.append(v)
				res[t * 3 + n] = remap[v]
			else:
				var key := v * uv.size() + flat
				if not flat_map.has(key):
					flat_map[key] = order.size()
					order.append(v)
					uv_from.append(flat)
				res[t * 3 + n] = flat_map[key]
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	var per: int = w.per
	for a in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2, Mesh.ARRAY_COLOR]:
		if src[a] == null:
			continue
		var s = src[a]
		var dst = s.duplicate()
		dst.resize(order.size())
		var from := uv_from if a == Mesh.ARRAY_TEX_UV else order
		for i in order.size():
			dst[i] = s[from[i]]
		out[a] = dst
	for a in [Mesh.ARRAY_TANGENT, Mesh.ARRAY_BONES, Mesh.ARRAY_WEIGHTS]:
		if src[a] == null:
			continue
		var n := 4 if a == Mesh.ARRAY_TANGENT else per
		var s = src[a]
		var dst = s.duplicate()
		dst.resize(order.size() * n)
		for i in order.size():
			for k in n:
				dst[i * n + k] = s[order[i] * n + k]
		out[a] = dst
	out[Mesh.ARRAY_INDEX] = res
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out)
	mesh.surface_set_material(0, material)
	return mesh


## Makes the far body of a model now (the loading screen), so no pedestrian walking out past
## lod_far stalls the frame building it - and its hats with the hair pressed under each
## (CrowdHat.warm; the police cap too for an `officer` rig), from the same instance.
static func warm_far_mesh(path: String, host: Node, officer: bool = false) -> void:
	if not ResourceLoader.exists(path):
		return
	var inst := (load(path) as PackedScene).instantiate() as Node3D
	host.add_child(inst)
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		var mesh := (mi as MeshInstance3D).mesh
		if (mi as MeshInstance3D).skin and not is_hair(mi as MeshInstance3D):
			far_mesh(mesh, mid_triangles)
			far_mesh(mesh, far_triangles)
			_welds.erase(mesh)
			if officer:
				# The responders wear these rigs too: their uniform trim's bake (~35 ms a rig).
				load("res://scripts/npc/emergency_crew.gd").trim_mesh(mesh, (mi as MeshInstance3D).skin, mi.get_parent() as Skeleton3D)
	CrowdHat.warm(inst, path, officer)
	inst.queue_free()


## Where the pavement is under (x, z) in the parent's space: the chunk's own ground height (the
## same one it placed this pedestrian with). `fallback` when the parent is not a chunk.
func _ground_y(x: float, z: float, fallback: float) -> float:
	var chunk := get_parent()
	if chunk and chunk.has_method("ground_y"):
		return chunk.ground_y(x, z) + 0.1
	return fallback


## Ring points are stored relative to the chunk's world offset so re-centering does not matter.
func _ring_origin() -> Vector2:
	return Vector2.ZERO


func _random_ring_point(sidewalk: float) -> Vector2:
	# A point on the sidewalk ring: pick an edge, then a spot 1..(sidewalk-1) m in from the curb.
	var inset := _rng.randf_range(1.0, maxf(sidewalk - 1.0, 1.2))
	var edge := _rng.randi() % 4
	match edge:
		0:
			return Vector2(_rng.randf_range(ring.position.x + 1.0, ring.end.x - 1.0), ring.position.y + inset)
		1:
			return Vector2(_rng.randf_range(ring.position.x + 1.0, ring.end.x - 1.0), ring.end.y - inset)
		2:
			return Vector2(ring.position.x + inset, _rng.randf_range(ring.position.y + 1.0, ring.end.y - 1.0))
		_:
			return Vector2(ring.end.x - inset, _rng.randf_range(ring.position.y + 1.0, ring.end.y - 1.0))


func _on_body_entered(body: Node3D) -> void:
	if _down:
		return
	var speed := 0.0
	var dir := Vector3.UP
	if body is RigidBody3D:
		speed = (body as RigidBody3D).linear_velocity.length()
		dir = (body as RigidBody3D).linear_velocity.normalized()
		if body is Vehicle and (body as Vehicle).is_traffic():
			speed = (body as Vehicle).traffic_speed
			dir = -(body as Vehicle).global_basis.z
	elif body is Player:
		speed = (body as Player).velocity.length()
		dir = (body as Player).velocity.normalized()
		if speed < tackle_speed:
			return
	if speed >= knock_speed:
		# A cruiser that runs somebody down is the police's doing, not the player's crime.
		Police.innocent = body.has_meta("police")
		knock(dir * (8.0 + speed * 0.6) + Vector3.UP * 6.0)
		Police.innocent = false


## Frightens everyone within `radius` of `at` (a gunshot, a blast): they run from it, and the
## `screams` nearest of the ones who were calm scream, each after their own short delay.
## One pass over the crowd group, and at most one pass per quarter second per spot.
## `force` skips the rate limit (a blast is bigger news than the shot that caused it).
## The same pass counts who heard it and reports the crime to the police (Police.on_alarm):
## `crime` "auto" is a gunshot, or an explosion when forced; "" reports nothing (police fire).
static func alarm(tree: SceneTree, at: Vector3, radius: float, screams: int, force: bool = false, crime: String = "auto") -> void:
	if tree == null or radius <= 0.0:
		return
	# The birds hear every shot and blast first (they startle further than people do).
	Birds.startle(at, radius)
	var now := Time.get_ticks_msec()
	if not force and now - _last_alarm_ms < 250 and at.distance_to(_last_alarm_at) < 10.0:
		return
	_last_alarm_ms = now
	_last_alarm_at = at
	var r2 := radius * radius
	var fresh: Array = []
	var heard := 0
	# The nearest static figures at the camps become people first, so they hear it too.
	CampFigure.wake_near(tree, at, radius)
	for n in tree.get_nodes_in_group("pedestrian"):
		var p := n as Pedestrian
		if p == null or p._down or not p.is_inside_tree():
			continue
		var d2 := p.global_position.distance_squared_to(at)
		if d2 > r2:
			continue
		heard += 1
		if p._panic_left <= 0.0:
			fresh.append([d2, p])
		p._scare(at)
	fresh.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for i in mini(screams, fresh.size()):
		var p: Pedestrian = fresh[i][1]
		p._scream_in = p._rng.randf_range(0.05, 0.45) + 0.25 * float(i)
	if crime != "":
		Police.on_alarm(tree, at, radius, heard, ("explosion" if force else "gunfire") if crime == "auto" else crime)


func _scare(at: Vector3) -> void:
	_end_act(true)
	_life_clip = ""
	var calm := _panic_left <= 0.0
	_panic_left = _rng.randf_range(panic_seconds.x, panic_seconds.y)
	# `at` is a scene position; the ring is in the parent's (a chunk's: the true world).
	var local := (get_parent() as Node3D).to_local(at) if get_parent() is Node3D else at
	_threat = Vector2(local.x, local.z)
	_pause_left = 0.0
	_pause_next = 0.0
	_look_threat = at
	_look_hold = look_threat_seconds
	_look_scan = 0.0
	# Panic wins over waiting to cross: back along this block's pavement at a run. Somebody
	# already out in the road keeps going, at a run, and flees on the far side.
	if _cross == Cross.TO_KERB or _cross == Cross.WAIT:
		_cross = Cross.NONE
	if calm and _cross != Cross.CROSSING:
		_go_to(_flee_point())


## Heads for `target` on this block's pavement, going round the ring (not through the block).
func _go_to(target: Vector2) -> void:
	_target = target
	_route = _ring_route(Vector2(position.x, position.z) - _ring_origin(), target)
	_route_pending = false


## Corner waypoints from `from` to `to` round the pavement ring, the shorter way: both points
## sit on the pavement band a few metres in from the kerb, and a straight line between two of
## its sides runs through the buildings (a near walker bumped along the walls, a far one walked
## straight through them). Empty when both are on the same side.
func _ring_route(from: Vector2, to: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	var w := ring.size.x
	var h := ring.size.y
	if w < 4.0 or h < 4.0:
		return out
	var s0 := _ring_s(from)
	var s1 := _ring_s(to)
	var perimeter := 2.0 * (w + h)
	var cw := fposmod(s1 - s0, perimeter)
	if absf(_ring_side(from) - _ring_side(to)) < 0.5:
		return out
	var inset := clampf(_sidewalk * 0.5, 1.0, 2.5)
	# Corners in clockwise order with their perimeter position: NE, SE, SW, NW (z runs south).
	var corners := [
		[w, Vector2(ring.end.x - inset, ring.position.y + inset)],
		[w + h, Vector2(ring.end.x - inset, ring.end.y - inset)],
		[2.0 * w + h, Vector2(ring.position.x + inset, ring.end.y - inset)],
		[perimeter, Vector2(ring.position.x + inset, ring.position.y + inset)],
	]
	var clockwise := cw <= perimeter * 0.5
	var span := cw if clockwise else perimeter - cw
	var picks: Array = []
	for c: Array in corners:
		var d: float = fposmod(float(c[0]) - s0, perimeter) if clockwise else fposmod(s0 - float(c[0]), perimeter)
		if d > 0.01 and d < span:
			picks.append([d, c[1]])
	picks.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	for p: Array in picks:
		out.append(p[1])
	return out


## Which side of the ring a point is on: 0 north, 1 east, 2 south, 3 west.
func _ring_side(p: Vector2) -> float:
	var d := [p.y - ring.position.y, ring.end.x - p.x, ring.end.y - p.y, p.x - ring.position.x]
	var best := 0
	for i in 4:
		if float(d[i]) < float(d[best]):
			best = i
	return float(best)


## Distance round the ring clockwise from its north-west corner to the side point nearest `p`.
func _ring_s(p: Vector2) -> float:
	var w := ring.size.x
	var h := ring.size.y
	match int(_ring_side(p)):
		0:
			return clampf(p.x - ring.position.x, 0.0, w)
		1:
			return w + clampf(p.y - ring.position.y, 0.0, h)
		2:
			return w + h + clampf(ring.end.x - p.x, 0.0, w)
	return 2.0 * w + h + clampf(ring.end.y - p.y, 0.0, h)


# --- Crossing the street -----------------------------------------------------------------------

## True while somebody is on crosswalk (`node`, the crossed road's `axis`, `side` of the junction):
## a car on that road stops short of it (TrafficManager._drive_street()).
static func crosswalk_busy(node: Vector2i, axis: int, side: int) -> bool:
	if _crosswalks.is_empty():
		return false
	return int(_crosswalks.get(Vector4i(node.x, node.y, axis, side), 0)) > 0


## The city plan, from the chunk this walker belongs to.
func _city_plan() -> CityPlan:
	var p := get_parent()
	if p == null:
		return null
	var value: Variant = p.get("plan")
	return value as CityPlan if value is CityPlan else null


## Heads for a crosswalk at the corner of the block nearest to this walker: across the road of
## `prefer_axis` (CityPlan.AXIS_X or AXIS_Z), or either (-1, rolled). Only at a junction that
## has crosswalks (signals or stop signs), and only onto a block the city really goes on to.
## False (and nothing changed) when there is no such crossing here.
func plan_crossing(prefer_axis: int = -1) -> bool:
	var plan := _city_plan()
	if plan == null or _down:
		return false
	var here := Vector2(position.x, position.z) - _ring_origin()
	var centre := ring.get_center()
	var b := plan.block_index_at(centre)
	var sx := 1 if here.x > centre.x else -1
	var sz := 1 if here.y > centre.y else -1
	var node := Vector2i(b.x + (1 if sx > 0 else 0), b.y + (1 if sz > 0 else 0))
	var inter: Dictionary = plan.intersection(node.x, node.y)
	var kind: int = inter.kind
	if kind != CityPlan.Intersection.SIGNALS and kind != CityPlan.Intersection.STOP_SIGNS:
		return false
	var pos: Vector2 = inter.pos
	var size: Vector2 = inter.size
	# This block is in the junction's (-sx, -sz) quadrant.
	var first_x := prefer_axis == CityPlan.AXIS_X if prefer_axis >= 0 else _way.randf() < 0.5
	var spread := _way.randf_range(-kerb_spread, kerb_spread)
	for attempt in (1 if prefer_axis >= 0 else 2):
		var across_x := first_x if attempt == 0 else not first_x
		var from: Vector2
		var to: Vector2
		var next: Rect2
		var key: Vector4i
		var road: Vector2
		if across_x:
			var z := pos.y - sz * (size.y * 0.5 + 1.8) + spread
			from = Vector2(pos.x - sx * (size.x * 0.5 + kerb_wait), z)
			to = Vector2(pos.x + sx * (size.x * 0.5 + kerb_wait), z)
			next = plan.block(b.x + sx, b.y).rect
			key = Vector4i(node.x, node.y, CityPlan.AXIS_X, -sz)
			road = Vector2(pos.x, size.x * 0.5)
		else:
			var x := pos.x - sx * (size.x * 0.5 + 1.8) + spread
			from = Vector2(x, pos.y - sz * (size.y * 0.5 + kerb_wait))
			to = Vector2(x, pos.y + sz * (size.y * 0.5 + kerb_wait))
			next = plan.block(b.x, b.y + sz).rect
			key = Vector4i(node.x, node.y, CityPlan.AXIS_Z, -sx)
			road = Vector2(pos.y, size.y * 0.5)
		if not _crossable(plan, next, to):
			continue
		_cross = Cross.TO_KERB
		_cross_from = from
		_cross_to = to
		_cross_key = key
		_cross_road = road
		_cross_ring = next
		_cross_signal = kind == CityPlan.Intersection.SIGNALS
		_cross_wait = 0.0
		_cross_patience = _way.randf_range(stop_sign_patience.x, stop_sign_patience.y)
		_pause_left = 0.0
		_go_to(from)
		return true
	return false


## A block worth crossing to: city ground with a pavement round it, the far kerb on it too.
func _crossable(plan: CityPlan, rect: Rect2, far_kerb: Vector2) -> bool:
	if rect.size.x < 12.0 or rect.size.y < 12.0:
		return false
	if plan.zone_at(rect.get_center()) != MacroMap.Zone.CITY or plan.zone_at(far_kerb) != MacroMap.Zone.CITY:
		return false
	# Not onto a river block: its pavement ring runs into the channel.
	var kb := plan.chunk_index_at(rect.get_center())
	if plan.river_block(kb.x, kb.y):
		return false
	return not Landmarks.covers(plan, far_kerb, 1.0)


## Straight out onto the crosswalk plan_crossing() picked, `progress` (0..1) of the way over, as
## if the walking figure had just come up (screenshots: a still cannot wait for a walker to reach
## the kerb and the light to change).
func cross_now(progress: float) -> void:
	if _cross == Cross.NONE:
		return
	var at := _cross_from.lerp(_cross_to, clampf(progress, 0.0, 0.95))
	position = Vector3(at.x, _ground_y(at.x, at.y, position.y), at.y)
	_start_crossing()


func _arrive_at_kerb() -> void:
	_cross = Cross.WAIT
	_cross_wait = 0.0
	velocity = Vector3.ZERO
	# Waiting for the light: shifting weight, arms folded, on the phone.
	if _life_ok and _life_near:
		_life_clip = _stand_clip()


## Standing at the kerb: at a signal until the walking figure comes up, at a stop sign for a
## moment. Nobody stands there for ever.
func _wait_at_kerb(delta: float) -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	_cross_wait += delta
	var go := false
	var plan := _city_plan()
	if plan == null:
		go = true
	elif _cross_signal:
		go = TrafficSignals.walk(plan, _cross_key.x, _cross_key.y, _cross_key.z) == TrafficSignals.Walk.WALK
	else:
		go = _cross_wait >= _cross_patience
	var across := (_cross_to - _cross_from).normalized()
	_turn_on_spot(atan2(-across.x, -across.y), delta)
	if go:
		_start_crossing()
	elif _cross_wait > 75.0:
		_cross = Cross.NONE
		_life_clip = ""
		_go_to(_random_ring_point(_sidewalk))


func _start_crossing() -> void:
	_cross = Cross.CROSSING
	if _act == CrowdLife.Act.NONE:
		_life_clip = ""
	if not _on_crosswalk:
		_on_crosswalk = true
		_crosswalks[_cross_key] = int(_crosswalks.get(_cross_key, 0)) + 1
	_pivoting = false


func _leave_crosswalk() -> void:
	if not _on_crosswalk:
		return
	_on_crosswalk = false
	var n := int(_crosswalks.get(_cross_key, 0)) - 1
	if n > 0:
		_crosswalks[_cross_key] = n
	else:
		_crosswalks.erase(_cross_key)


## On the crosswalk: straight over to the far kerb, down onto the asphalt and up again, placed
## rather than slid (a kerb is a step a capsule does not climb). At the far kerb this walker
## belongs to the next block.
func _walk_crossing(delta: float, panicking: bool) -> void:
	var here := Vector2(position.x, position.z)
	var to := _cross_to - here
	var across := (_cross_to - _cross_from).normalized()
	var v := _steer(to, _run_pace if panicking else walk_speed * cross_pace, delta, panicking)
	var step := v.length() * delta
	if to.length() <= step + 0.05 or to.dot(across) <= 0.0:
		position = Vector3(_cross_to.x, _ground_y(_cross_to.x, _cross_to.y, position.y), _cross_to.y)
		_leave_crosswalk()
		_cross = Cross.NONE
		ring = _cross_ring
		# The velocity is left as it was: the next step sets it for the pavement, and a walker
		# read on the step it steps up the kerb is still walking.
		if panicking:
			_go_to(_flee_point())
		else:
			_go_to(_random_ring_point(_sidewalk))
		return
	var at := here + v * delta
	var y := _ground_y(at.x, at.y, position.y)
	# On the carriageway (inside the kerbs), the ground is the road, a kerb's height lower.
	var off := absf((at.x if absf(across.x) > 0.5 else at.y) - _cross_road.x)
	if off < _cross_road.y:
		y -= CityChunk.SIDEWALK_TOP - CityChunk.ROAD_TOP
	position = Vector3(at.x, y, at.y)
	velocity = Vector3(v.x, 0.0, v.y)


func _exit_tree() -> void:
	_leave_crosswalk()
	_end_act(true)
	StreetErrands.release(self)


## The spot on this block's pavement ring farthest from the threat, out of a handful: fleeing
## along the pavement keeps them out of the traffic, and away from it is all a scare needs.
func _flee_point() -> Vector2:
	var best := _random_ring_point(_sidewalk)
	for i in 5:
		var p := _random_ring_point(_sidewalk)
		if p.distance_squared_to(_threat) > best.distance_squared_to(_threat):
			best = p
	return best


## Screams now if nobody else in the crowd has just started one, else a moment later.
func _scream() -> void:
	var now := Time.get_ticks_msec()
	if now - _last_scream_ms < scream_gap_ms:
		_scream_in = _rng.randf_range(0.08, 0.3)
		return
	_last_scream_ms = now
	_scream_in = -1.0
	Sfx.play("scream", global_position + Vector3.UP * 1.6, 0.0, _rng.randf_range(0.94, 1.08))


## Turns into a ragdoll flung by `impulse`, with `gibs` limbs torn off (a close blast).
func knock(impulse: Vector3, gibs: int = 0) -> void:
	if _down:
		return
	_down = true
	# A crime if anybody saw it, unless the police did it themselves (Police.innocent).
	Police.person_down(self)
	Sfx.play("yelp", global_position, 0.0, _rng.randf_range(0.8, 1.3))
	var doll := Ragdoll.new()
	doll.position = position
	doll.rotation.y = _visual.rotation.y
	get_parent().add_child(doll)
	if _model_path == "" or not doll.build_from_rig(_model_path, _look):
		doll.build(shirt, pants, skin)
	else:
		_dress_doll(doll)
	PhysicsBudget.register_debris(doll)
	doll.fling(impulse)
	_doll = doll
	if gibs > 0:
		doll.dismember(gibs, impulse)
	queue_free()


## A round in at `at`, travelling along `dir` (WeaponFX.bullet_wound, from any gun): they go
## down, flung by `impulse`, and bleed - `strength` 1 is a rifle round. The blood is the body's
## (Ragdoll.shot), so it stains, pools and trails. Hit again before this node is gone (a
## shotgun's other pellets in the same frame) and the round goes into the body it became.
func shot(at: Vector3, dir: Vector3, impulse: Vector3, strength: float = 1.0) -> void:
	knock(impulse)
	if _doll != null and is_instance_valid(_doll):
		_doll.shot(at, dir, Vector3.ZERO, strength)
	else:
		WeaponFX.blood(self, at, dir, strength, self)


# --- Life (GAME_PLAN G5) ---------------------------------------------------------------------
# Near the camera, people do more than walk: they stop to talk in twos and threes, take a call,
# text, sit on a bench, lean on a wall with a cigarette, look in a shop window, carry a coffee
# or shopping bags; joggers run the beach paths and some people walk a dog. All of it from the
# "life" clips (CrowdLife), all of it rolled from the person's seed, and only within life_range
# of the player in a FULL chunk: far people walk as before. Panic overrides everything.

@export_group("Life")
## People do things only this close to the player (metres); past it they just walk.
@export var life_range: float = 60.0
## Chance, at the end of each walk, that someone near the player stops to do something.
@export var life_chance: float = 0.32
## Chance a person near the player is already doing something when they appear (their chunk
## streamed in), so a street you fly into is not all walkers.
@export var life_spawn_chance: float = 0.5
## How long each kind of stop lasts (seconds, min and max).
@export var stand_seconds: Vector2 = Vector2(8.0, 30.0)
@export var talk_seconds: Vector2 = Vector2(14.0, 45.0)
@export var sit_seconds: Vector2 = Vector2(20.0, 75.0)
@export var lean_seconds: Vector2 = Vector2(15.0, 45.0)
@export var window_seconds: Vector2 = Vector2(5.0, 14.0)
## How far a walker looks for people to talk to, and for a free seat (metres).
@export var talk_reach: float = 14.0
@export var seat_reach: float = 30.0
## Shares of the crowd who carry each thing (rolled once per person).
@export var call_share: float = 0.07
@export var text_share: float = 0.1
@export var cup_share: float = 0.09
@export var bag_share: float = 0.11
@export var smoke_share: float = 0.07
## Joggers and dog walkers: the share in the suburbs, beach town and on the Esplanade, and in
## the rest of the city.
@export var jogger_share: Vector2 = Vector2(0.14, 0.03)
## Dog walkers are OFF (lead, 2026-10-04): the only CC0 rigged dog is Quaternius' low-poly,
## flat-shaded Shiba, which breaks the realism rule. Put (0.12, 0.03) back once
## `CrowdDog.MODEL` is a realistic dog; the roll is still made, so nothing else moves.
@export var dog_share: Vector2 = Vector2.ZERO
## A jogger's pace (m/s).
@export var jog_pace: Vector2 = Vector2(2.6, 3.4)
@export_group("")

## The whole layer on or off (CROWD_LIFE=0 in the environment: the A/B for stills).
static var life_enabled: bool = OS.get_environment("CROWD_LIFE") != "0"
var _life_ok: bool = false
var _life_near: bool = false
var _life_rolled: bool = false
var _born_ms: int = 0
var _life := RandomNumberGenerator.new()
var _carry: int = CrowdLife.Carry.NONE
var _jogger: bool = false
var _dog_walker: bool = false
var _dog: Node3D
## The current stop (CrowdLife.Act) and its stage.
var _act: int = CrowdLife.Act.NONE
enum Stage { GOING, SETTLE, DOING, LEAVING }
var _stage: int = Stage.GOING
var _act_left: float = 0.0
var _act_face: float = 0.0
var _act_spot := Vector2.ZERO
var _act_beat: float = 0.0
var _life_clip: String = ""
var _life_base: String = ""
var _one_shot_left: float = 0.0
var _life_look := Vector3.INF
var _seat: Dictionary = {}
var _seat_drop: float = 0.0
var _group: Dictionary = {}
var _carry_w: float = 0.0
var _props: Dictionary = {}
var _skel_unit: float = 100.0
var _hip_bone: int = -1
var _leg_bones := PackedInt32Array()
## The errand under way (StreetErrands: its steps and where it is in them), {} for none.
var errand: Dictionary = {}


## Rolls what this person carries and whether they jog or walk a dog (from the seed, so the same
## city has the same people). Called from _ready, once the chunk (and so the district) is known.
func _roll_life(seed_value: int) -> void:
	_life.seed = hash([seed_value, "life"])
	var r := _life.randf()
	var shares := [call_share, text_share, cup_share, bag_share, smoke_share]
	var kinds := [CrowdLife.Carry.CALL, CrowdLife.Carry.TEXT, CrowdLife.Carry.CUP, CrowdLife.Carry.BAG, CrowdLife.Carry.SMOKE]
	for i in shares.size():
		if r < shares[i]:
			_carry = kinds[i]
			break
		r -= shares[i]
	var leisure := _leisure_place()
	_jogger = _life.randf() < (jogger_share.x if leisure else jogger_share.y)
	_dog_walker = not _jogger and _life.randf() < (dog_share.x if leisure else dog_share.y)
	if _jogger:
		_carry = CrowdLife.Carry.NONE
		walk_speed = _life.randf_range(jog_pace.x, jog_pace.y)
		_speed = walk_speed
	elif _dog_walker:
		walk_speed = minf(walk_speed, _life.randf_range(1.0, 1.25))
		_speed = walk_speed
		if _carry == CrowdLife.Carry.BAG:
			_carry = CrowdLife.Carry.NONE


## The suburbs, the beach town and the Esplanade, where people jog and walk dogs.
func _leisure_place() -> bool:
	if self is ReplicaWalker:
		return true
	var plan := _city_plan()
	if plan == null:
		return false
	var d := plan.district_at(Vector2(position.x, position.z))
	return d == CityPlan.District.SUBURBS or d == CityPlan.District.BEACHTOWN


## Game time in milliseconds (physics ticks, so a slow render or the weapon wheel's slow motion
## stretches it with everything else).
static func _life_now_ms() -> int:
	return Engine.get_physics_frames() * 1000 / Engine.physics_ticks_per_second


## Only the plain crowd lives this way: officers and rough sleepers run their own behaviour.
func _lives() -> bool:
	var s: Script = get_script()
	return s != null and (s.resource_path.ends_with("/pedestrian.gd") or s.resource_path.ends_with("/replica_walker.gd"))


## After _add_model: the rig gets its life clips, and the bones the life poses touch are found.
func _setup_life() -> void:
	_born_ms = _life_now_ms()
	if not _lives() or not life_enabled or _anim == null or _head_skel == null:
		return
	_life_ok = CrowdLife.attach(_anim, _model_path)
	if not _life_ok:
		_jogger = false
		return
	var node: Node3D = _head_skel
	var unit := 1.0
	while node != null and node != _visual:
		unit *= node.transform.basis.get_scale().y
		node = node.get_parent() as Node3D
	_skel_unit = 1.0 / maxf(unit, 1e-5)
	_hip_bone = _head_skel.find_bone("Hips")
	for b in ["LeftUpLeg", "LeftLeg", "LeftFoot", "RightUpLeg", "RightLeg", "RightFoot"]:
		_leg_bones.append(_head_skel.find_bone(b))
	if -1 in _leg_bones:
		_leg_bones.clear()
	if _dog_walker:
		_dog = CrowdDog.make(self, _life.randi())


## Whether this person could start something now (and join a group).
func _life_free() -> bool:
	return _life_ok and _life_near and not _down and _act == CrowdLife.Act.NONE and _panic_left <= 0.0 \
		and _cross == Cross.NONE and not _jogger and _pause_left <= 0.0


## At the end of a walk, near the player: maybe stop and do something. True when it did.
func _try_life(at_spawn: bool) -> bool:
	if not _life_free() or _dog_walker:
		if _dog_walker and _life_ok and _life_near and _life.randf() < 0.35:
			# The dog stops to sniff and the owner waits for it.
			_start_stand(_life.randf_range(4.0, 10.0))
			return true
		return false
	# Somewhere to go (StreetErrands): a bus, a shop, a parked car, over the road mid-block.
	if StreetErrands.try_start(self, at_spawn):
		return true
	# A street vendor's queue nearby (StreetVendors): some stop and wait at the cart or the truck.
	if _plan_queue(at_spawn):
		return true
	var r := _life.randf()
	# What kind of person this is decides what they stop for.
	if _carry == CrowdLife.Carry.SMOKE and r < 0.75:
		return _plan_wall(CrowdLife.Act.LEAN, at_spawn) or _start_stand(_life.randf_range(stand_seconds.x, stand_seconds.y))
	if _carry == CrowdLife.Carry.CALL or _carry == CrowdLife.Carry.TEXT:
		if r < 0.65:
			return _start_stand(_life.randf_range(stand_seconds.x, stand_seconds.y))
		r = _life.randf()
	if r < 0.36:
		if _plan_talk(at_spawn):
			return true
	elif r < 0.6:
		if _plan_sit(at_spawn):
			return true
	elif r < 0.75:
		if _plan_wall(CrowdLife.Act.WINDOW, at_spawn):
			return true
	elif r < 0.85:
		if _plan_wall(CrowdLife.Act.LEAN, at_spawn):
			return true
	if r < 0.95 or _carry != CrowdLife.Carry.NONE:
		return _start_stand(_life.randf_range(stand_seconds.x, stand_seconds.y) * 0.6)
	return false


func _start_stand(seconds: float) -> bool:
	_act = CrowdLife.Act.STAND
	_stage = Stage.DOING
	_act_left = seconds
	_act_face = _visual.rotation.y
	_life_base = _stand_clip()
	_life_clip = _life_base
	_act_beat = _life.randf_range(3.0, 8.0)
	return true


## What someone standing about plays, by what they carry.
func _stand_clip() -> String:
	match _carry:
		CrowdLife.Carry.CALL:
			return CrowdLife.PHONE
		CrowdLife.Carry.TEXT, CrowdLife.Carry.CUP, CrowdLife.Carry.BAG, CrowdLife.Carry.SMOKE:
			# The cigarette is in the left hand, which folded arms would hide.
			return CrowdLife.IDLE
	return CrowdLife.IDLE if _life.randf() < 0.7 else CrowdLife.FOLD


## Recruits one or two free walkers on this block nearby and gathers them round a spot.
func _plan_talk(at_spawn: bool) -> bool:
	var parent := get_parent()
	if parent == null:
		return false
	var here := Vector2(position.x, position.z)
	var want := 1 if _life.randf() < 0.65 else 2
	var mates: Array[Pedestrian] = []
	for n in parent.get_children():
		var p := n as Pedestrian
		if p == null or p == self or not p._life_free() or p._dog_walker or p.ring != ring:
			continue
		if not at_spawn and (p._carry == CrowdLife.Carry.CALL):
			continue
		if Vector2(p.position.x, p.position.z).distance_to(here) < talk_reach:
			mates.append(p)
			if mates.size() >= want:
				break
	if mates.is_empty():
		return false
	var members: Array = [self]
	members.append_array(mates)
	var dir := Vector2(-sin(_visual.rotation.y), -cos(_visual.rotation.y))
	var centre := here + dir * 0.6
	var radius := 0.55 if members.size() == 2 else 0.68
	var spin := _life.randf() * TAU
	var group := {
		"centre": centre, "members": members, "seed": _life.randi(),
		"until": _life_now_ms() + int(1000.0 * _life.randf_range(talk_seconds.x, talk_seconds.y)),
	}
	for i in members.size():
		var m: Pedestrian = members[i]
		var a := spin + TAU * float(i) / float(members.size())
		var slot := centre + Vector2(cos(a), sin(a)) * radius
		m._join_talk(group, slot, at_spawn)
	return true


func _join_talk(group: Dictionary, slot: Vector2, at_once: bool) -> void:
	_act = CrowdLife.Act.TALK
	_group = group
	_act_spot = slot
	var to: Vector2 = (group.centre as Vector2) - slot
	_act_face = atan2(-to.x, -to.y)
	_act_beat = _life.randf_range(2.0, 6.0)
	_life_base = CrowdLife.IDLE if _life.randf() < 0.6 else CrowdLife.FOLD
	if at_once:
		_place_at(slot, _act_face)
		_stage = Stage.DOING
		_life_clip = _life_base
	else:
		_stage = Stage.GOING
		_go_to(slot)


## A free seat on this chunk's benches within seat_reach.
func _plan_sit(at_spawn: bool) -> bool:
	var parent := get_parent()
	var seat := CrowdLife.free_seat(parent, Vector2(position.x, position.z), seat_reach * (0.5 if at_spawn else 1.0))
	if seat.is_empty() or _sit_clip_info().is_empty():
		return false
	_act = CrowdLife.Act.SIT
	_seat = seat
	seat.taken = self
	var info := _sit_clip_info()
	var face := Vector2(-sin(float(seat.yaw)), -cos(float(seat.yaw)))
	# The clip carries the hips back onto the seat as they sit: stand that far in front of it.
	_act_spot = (seat.p as Vector2) + face * float(info.back) * _visual.scale.z
	_act_face = float(seat.yaw)
	# The library's chair is the clip's; a bench is CrowdLife.SEAT_HEIGHT. The hips are moved to
	# sit on the bench and the legs re-solved so the feet stay where they were (_sit_pose()).
	_seat_drop = float(info.hips) * _visual.scale.y - (CrowdLife.SEAT_HEIGHT + CrowdLife.HIP_OVER_SEAT)
	_act_left = _life.randf_range(sit_seconds.x, sit_seconds.y)
	_act_beat = _life.randf_range(4.0, 10.0)
	if at_spawn:
		_place_at(_act_spot, _act_face)
		_stage = Stage.DOING
		_life_base = CrowdLife.SIT
		_life_clip = CrowdLife.SIT
	else:
		_stage = Stage.GOING
		_go_to(_act_spot)
	return true


## A free spot at a street vendor's queue on this chunk (StreetVendors), and the roll to take it:
## walk there and wait, facing the cart or the truck's window. No roll at all on a chunk with no
## vendors, so nobody else's life moves.
func _plan_queue(at_spawn: bool) -> bool:
	var parent := get_parent()
	if parent == null or not parent.has_meta("vendor_queue"):
		return false
	var spot := StreetVendors.free_queue(parent, Vector2(position.x, position.z), seat_reach * (0.8 if at_spawn else 1.2))
	if spot.is_empty() or _life.randf() > StreetVendors.QUEUE_SHARE:
		return false
	_act = CrowdLife.Act.STAND
	_seat = spot
	spot.taken = self
	_act_spot = spot.p
	_act_face = float(spot.yaw)
	_act_left = _life.randf_range(StreetVendors.QUEUE_SECONDS.x, StreetVendors.QUEUE_SECONDS.y)
	_act_beat = _life.randf_range(3.0, 8.0)
	_life_base = _stand_clip()
	if at_spawn:
		_place_at(_act_spot, _act_face)
		_stage = Stage.DOING
		_life_clip = _life_base
	else:
		_stage = Stage.GOING
		_go_to(_act_spot)
	return true


## The sitting clips' numbers for this rig: how far back the hips go and how high they sit
## (metres, at the rig's own scale), cached per model.
static var _sit_info: Dictionary = {}
func _sit_clip_info() -> Dictionary:
	if _sit_info.has(_model_path):
		return _sit_info[_model_path]
	var out := {}
	if _anim and _anim.has_animation(CrowdLife.SIT_DOWN) and _anim.has_animation(CrowdLife.SIT):
		var down := _anim.get_animation(CrowdLife.SIT_DOWN)
		var path := NodePath("Armature/Skeleton3D:Hips")
		var t0 := down.find_track(path, Animation.TYPE_POSITION_3D)
		var sit := _anim.get_animation(CrowdLife.SIT)
		var t1 := sit.find_track(path, Animation.TYPE_POSITION_3D)
		if t0 >= 0 and t1 >= 0:
			var a := down.position_track_interpolate(t0, 0.0)
			var b := sit.position_track_interpolate(t1, 0.0)
			out = {"back": (a.z - b.z) / _skel_unit, "hips": b.y / _skel_unit, "stand": a.y / _skel_unit}
	_sit_info[_model_path] = out
	return out


## A wall on the building side of the pavement within a few metres (one ray): lean on it, or
## look in its window. False when this stretch has no wall (a forecourt, a plaza, a car park).
func _plan_wall(kind: int, at_spawn: bool) -> bool:
	var here := Vector2(position.x, position.z)
	var inward := _inward(here)
	if inward == Vector2.ZERO or not is_inside_tree():
		return false
	var parent := get_parent() as Node3D
	if parent == null:
		return false
	var from := parent.to_global(Vector3(here.x, position.y + 1.3, here.y))
	var to := parent.to_global(Vector3(here.x + inward.x * 5.0, position.y + 1.3, here.y + inward.y * 5.0))
	var q := PhysicsRayQueryParameters3D.create(from, to, 1)
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return false
	var n: Vector3 = hit.normal
	if absf(n.y) > 0.3:
		return false
	var wall := parent.to_local(hit.position)
	var out := Vector2(n.x, n.z).normalized()
	_act = kind
	_act_spot = Vector2(wall.x, wall.z) + out * (0.3 if kind == CrowdLife.Act.LEAN else 0.65)
	# Back to the wall to lean, facing it to look in the window.
	var face := out if kind == CrowdLife.Act.LEAN else -out
	_act_face = atan2(-face.x, -face.y)
	_act_left = _life.randf_range(lean_seconds.x, lean_seconds.y) if kind == CrowdLife.Act.LEAN \
		else _life.randf_range(window_seconds.x, window_seconds.y)
	_life_base = CrowdLife.FOLD if kind == CrowdLife.Act.LEAN and _carry != CrowdLife.Carry.SMOKE else CrowdLife.IDLE
	_act_beat = _life.randf_range(2.0, 6.0)
	if kind == CrowdLife.Act.WINDOW:
		_life_look = hit.position + Vector3(0.0, -0.2, 0.0)
	if at_spawn:
		_place_at(_act_spot, _act_face)
		_stage = Stage.DOING
		_life_clip = _life_base
	else:
		_stage = Stage.GOING
		_go_to(_act_spot)
	return true


## The way to the buildings from a pavement point: away from the nearest kerb of the ring.
func _inward(p: Vector2) -> Vector2:
	if ring.size == Vector2.ZERO:
		return Vector2.ZERO
	var d := [p.x - ring.position.x, ring.end.x - p.x, p.y - ring.position.y, ring.end.y - p.y]
	var dirs := [Vector2.RIGHT, Vector2.LEFT, Vector2.DOWN, Vector2.UP]
	var best := 0
	for i in 4:
		if d[i] < d[best]:
			best = i
	return dirs[best]


func _place_at(spot: Vector2, yaw: float) -> void:
	position = Vector3(spot.x, _ground_y(spot.x, spot.y, position.y), spot.y)
	_visual.rotation.y = yaw
	_faced = true
	_speed = 0.0
	velocity = Vector3.ZERO


## Arrived where the stop happens: turn to face the right way, then do it.
func _arrive_act() -> void:
	_stage = Stage.SETTLE
	_speed = 0.0


## One tick of a stop (anything but walking to it).
func _do_act(delta: float) -> void:
	if _speed > 0.02:
		# The last step or two into a stop rolled at the end of a walk.
		_speed = move_toward(_speed, 0.0, stop_decel * delta)
		_move(Vector2(-sin(_visual.rotation.y), -cos(_visual.rotation.y)) * _speed, delta)
		return
	_speed = 0.0
	velocity.x = 0.0
	velocity.z = 0.0
	if not _kinematic and not is_on_floor() and _act != CrowdLife.Act.SIT:
		velocity.y -= 30.0 * delta
		move_and_slide()
	if _one_shot_left > 0.0:
		_one_shot_left -= delta
		if _one_shot_left <= 0.0:
			if _life_clip == CrowdLife.STAND_UP:
				_end_act()
				return
			_life_clip = _life_base
	match _stage:
		Stage.SETTLE:
			_turn_on_spot(_act_face, delta)
			if absf(angle_difference(_visual.rotation.y, _act_face)) < 0.12:
				_pivoting = false
				_stage = Stage.DOING
				if _act == CrowdLife.Act.SIT:
					_place_at(_act_spot, _act_face)
					_life_base = CrowdLife.SIT
					_one_shot(CrowdLife.SIT_DOWN)
				else:
					_life_clip = _life_base
			return
		Stage.LEAVING:
			return
	_act_left -= delta
	_act_beat -= delta
	match _act:
		CrowdLife.Act.TALK:
			if _group.is_empty() or _life_now_ms() > int(_group.until):
				_end_act()
				return
			_talk_beat()
		CrowdLife.Act.SIT:
			if _seat.is_empty() or bool((_seat.record as Dictionary).get("dead", false) if _seat.record is Dictionary else false):
				_end_act()
				return
			if _act_left <= 0.0:
				_stage = Stage.LEAVING
				_one_shot(CrowdLife.STAND_UP)
				return
			if _act_beat <= 0.0:
				_act_beat = _life.randf_range(5.0, 12.0)
				var other := CrowdLife.neighbour(get_parent(), _seat)
				var base := CrowdLife.SIT_TALK if other != null and _life.randf() < 0.6 else CrowdLife.SIT
				if base != _life_base and _one_shot_left <= 0.0:
					_life_base = base
					_life_clip = base
				_life_look = (other as Node3D).global_position + Vector3.UP * 1.1 if other != null else Vector3.INF
		_:
			if _act_left <= 0.0:
				_end_act()
				return
			if _act_beat <= 0.0:
				_act_beat = _life.randf_range(4.0, 9.0)
				# A sip, a drag, or a shift of weight now and then.
				if _carry == CrowdLife.Carry.CUP or (_carry == CrowdLife.Carry.SMOKE and _act != CrowdLife.Act.WINDOW):
					_one_shot(CrowdLife.DRINK)
				elif _act == CrowdLife.Act.WINDOW and _life_look != Vector3.INF:
					# Along the window to the next thing in it.
					var along := Vector3(cos(_act_face), 0.0, -sin(_act_face)) * _life.randf_range(-1.6, 1.6)
					_life_look = _life_look + along * 0.5
	if _dog_walker and _act == CrowdLife.Act.STAND and _dog:
		_life_look = _dog.global_position + Vector3.UP * 0.3


## Who talks in a group is worked out from the clock, the same answer for every member, so the
## group needs no leader: a speaker for a few seconds, then the next.
func _talk_beat() -> void:
	var members: Array = _group.members
	var live: Array = members.filter(func(m): return is_instance_valid(m) and (m as Pedestrian)._group == _group)
	if live.size() < 2:
		_end_act()
		return
	var turn := int((_life_now_ms() + int(_group.seed) % 5000) / 4200)
	var speaker: Pedestrian = live[hash([_group.seed, turn]) % live.size()]
	if _one_shot_left <= 0.0:
		var want := CrowdLife.TALK if speaker == self else _life_base
		if want != _life_clip:
			_life_clip = want
		elif speaker != self and _act_beat <= 0.0:
			_act_beat = _life.randf_range(3.0, 8.0)
			if _life.randf() < 0.45:
				_one_shot(CrowdLife.NOD)
			elif _carry == CrowdLife.Carry.CUP:
				_one_shot(CrowdLife.DRINK)
	var look_at: Pedestrian = speaker
	if speaker == self:
		look_at = live[(live.find(self) + 1 + turn) % live.size()]
		if look_at == self:
			look_at = live[0]
	_life_look = look_at.global_position + Vector3.UP * 1.55 * look_at._visual.scale.y


func _one_shot(clip: String) -> void:
	if _anim == null or not _anim.has_animation(clip):
		return
	_life_clip = clip
	_one_shot_left = _anim.get_animation(clip).length - 0.15


## Back to walking: from where they are (a cancelled or finished stop) to a new spot.
func _end_act(silent: bool = false) -> void:
	if _act == CrowdLife.Act.NONE:
		return
	if not _seat.is_empty() and _seat.taken == self:
		_seat.taken = null
	_seat = {}
	_group = {}
	_act = CrowdLife.Act.NONE
	_stage = Stage.GOING
	_life_clip = ""
	_life_base = ""
	_one_shot_left = 0.0
	_life_look = Vector3.INF
	if _hip_bone >= 0 and _head_skel:
		_head_skel.reset_bone_pose(_hip_bone)
	if not silent and _panic_left <= 0.0:
		_go_to(_random_ring_point(_sidewalk))


## Called from _update_lod: the person came within life_range (or left it).
func _life_range_changed(near: bool) -> void:
	if not near:
		# Out of sight a stop just ends: whoever was sitting is walking again.
		if _act != CrowdLife.Act.NONE:
			_end_act()
		return
	if not _life_rolled:
		_life_rolled = true
		if _life_now_ms() - _born_ms < 4000 and _life.randf() < life_spawn_chance:
			_try_life(true)


## After the clip has posed the rig: what a walker carries laid over the arms, a sitter's hips
## put on the bench, the props shown or hidden.
func _life_pose(delta: float) -> void:
	if not _life_ok or _head_skel == null:
		return
	var running := _clip == RUN_CLIP or _clip == CrowdLife.JOG
	var over := (_carry in CrowdLife.CARRY_POSES or _carry == CrowdLife.Carry.CUP) and _life_near and not running and not _down \
		and (_act == CrowdLife.Act.NONE or (_act == CrowdLife.Act.STAND and _carry != CrowdLife.Carry.CALL)) \
		and not (_life_clip in CrowdLife.ONE_SHOTS)
	_carry_w = move_toward(_carry_w, 1.0 if over else 0.0, delta * 2.5)
	if _carry_w > 0.001:
		var w := smoothstep(0.0, 1.0, _carry_w)
		var pose := CrowdLife.carry_pose(_model_path, _head_skel, _carry)
		for b: int in pose:
			_head_skel.set_bone_pose_rotation(b, _head_skel.get_bone_pose_rotation(b).slerp(pose[b], w))
		if _carry == CrowdLife.Carry.TEXT:
			_posture_pitch = lerpf(_posture_pitch, -0.45, w)
		elif _carry == CrowdLife.Carry.CUP:
			var fore := _head_skel.find_bone("LeftForeArm")
			var hand := _head_skel.find_bone("LeftHand")
			if fore >= 0 and hand >= 0:
				var f := _head_skel.get_bone_global_pose(fore)
				var now := (_head_skel.get_bone_global_pose(hand).origin - f.origin).normalized()
				var turn := Quaternion(now, CrowdLife.CUP_FOREARM.normalized())
				_set_global_rot(fore, Basis(Quaternion.IDENTITY.slerp(turn, w)) * f.basis)
	if _act == CrowdLife.Act.SIT and _stage != Stage.GOING and _stage != Stage.SETTLE:
		_sit_pose()
	_show_props()


## A sitter's hips lowered (or raised) from the clip's chair to the bench, and the legs re-solved
## so the feet stay planted where the clip put them: a two-bone solve per leg in skeleton space.
func _sit_pose() -> void:
	if _hip_bone < 0 or _leg_bones.size() != 6 or absf(_seat_drop) < 0.005:
		return
	var info := _sit_clip_info()
	var sk := _head_skel
	var hips := sk.get_bone_pose_position(_hip_bone)
	# How far down the sit it is (0 standing, 1 seated): the drop comes in with the hips.
	var stand_y := float(info.stand) * _skel_unit
	var sit_y := float(info.hips) * _skel_unit
	var w := clampf((stand_y - hips.y) / maxf(stand_y - sit_y, 1.0), 0.0, 1.0)
	if w <= 0.0:
		return
	var feet := [sk.get_bone_global_pose(_leg_bones[2]), sk.get_bone_global_pose(_leg_bones[5])]
	var drop := _seat_drop / _visual.scale.y * _skel_unit * w
	sk.set_bone_pose_position(_hip_bone, hips - Vector3(0.0, drop, 0.0))
	for side in 2:
		var up := _leg_bones[side * 3]
		var knee := _leg_bones[side * 3 + 1]
		var foot := _leg_bones[side * 3 + 2]
		var a := sk.get_bone_global_pose(up)
		var k := sk.get_bone_global_pose(knee)
		var f := sk.get_bone_global_pose(foot)
		var target: Vector3 = (feet[side] as Transform3D).origin
		var l1 := a.origin.distance_to(k.origin)
		var l2 := k.origin.distance_to(f.origin)
		var to := target - a.origin
		var d := clampf(to.length(), absf(l1 - l2) + 0.01, (l1 + l2) * 0.999)
		var dir := to.normalized()
		# The knee stays in the plane the clip bent it in.
		var pole := (k.origin - a.origin) - dir * (k.origin - a.origin).dot(dir)
		if pole.length_squared() < 1e-6:
			pole = Vector3(0.0, 0.0, 1.0)
		pole = pole.normalized()
		var cos_a := clampf((l1 * l1 + d * d - l2 * l2) / (2.0 * l1 * d), -1.0, 1.0)
		var k_new := a.origin + (dir * cos_a + pole * sqrt(1.0 - cos_a * cos_a)) * l1
		var r1 := Quaternion((k.origin - a.origin).normalized(), (k_new - a.origin).normalized())
		_set_global_rot(up, Basis(r1) * a.basis)
		var k2 := sk.get_bone_global_pose(knee)
		var f2 := sk.get_bone_global_pose(foot)
		var r2 := Quaternion((f2.origin - k2.origin).normalized(), (a.origin + dir * d - k2.origin).normalized())
		_set_global_rot(knee, Basis(r2) * k2.basis)
		_set_global_rot(foot, (feet[side] as Transform3D).basis)


func _set_global_rot(bone: int, global_basis: Basis) -> void:
	var p := _head_skel.get_bone_parent(bone)
	var pb := _head_skel.get_bone_global_pose(p).basis if p >= 0 else Basis.IDENTITY
	_head_skel.set_bone_pose_rotation(bone, (pb.orthonormalized().inverse() * global_basis.orthonormalized()).get_rotation_quaternion())


## What is in their hands right now.
func _show_props() -> void:
	var want := {}
	if _life_near and not _down:
		match _carry:
			CrowdLife.Carry.CALL, CrowdLife.Carry.TEXT:
				want[CrowdLife.Prop.PHONE] = true
			CrowdLife.Carry.CUP:
				want[CrowdLife.Prop.CUP] = true
			CrowdLife.Carry.BAG:
				want[CrowdLife.Prop.BAG] = _act != CrowdLife.Act.SIT
			CrowdLife.Carry.SMOKE:
				want[CrowdLife.Prop.CIGARETTE] = _act == CrowdLife.Act.LEAN or _act == CrowdLife.Act.STAND
	for kind: int in want:
		if want[kind] and not _props.has(kind):
			_props[kind] = _hold(kind)
	for kind: int in _props:
		var mi: Node3D = _props[kind]
		if is_instance_valid(mi):
			mi.visible = want.get(kind, false)
	# A bag hangs plumb from the fist, whatever the wrist is doing.
	var bag: Node3D = _props.get(CrowdLife.Prop.BAG)
	if bag != null and bag.visible and bag.get_child_count() > 0:
		var mi := bag.get_child(0) as Node3D
		var yaw := _visual.global_rotation.y
		mi.global_transform = Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, PI) * Basis.from_scale(_visual.scale),
			bag.global_position)


## A prop in the hand that holds it (CrowdLife.PROP_HAND), built in the grip frame
## (CrowdLife.grip_basis()) and scaled up through the rig's centimetre skeleton.


func _hold(kind: int) -> Node3D:
	var bone: String = CrowdLife.PROP_HAND[kind]
	var att := BoneAttachment3D.new()
	_head_skel.add_child(att)
	att.bone_name = bone
	var mi := MeshInstance3D.new()
	mi.mesh = CrowdLife.prop_mesh(kind)
	mi.material_override = CrowdLife.prop_material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	mi.visibility_range_end = life_range
	mi.transform = Transform3D(CrowdLife.grip_basis(bone) * Basis.from_scale(Vector3.ONE * _skel_unit), Vector3.ZERO)
	att.add_child(mi)
	return att
