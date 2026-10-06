class_name CrowdLook
extends SkeletonModifier3D
## Where a pedestrian near the camera looks (VISUAL_ROADMAP #28's head look, taken further).
## Two halves:
##  - the THINKING, in the physics tick (`think()`, called from Pedestrian._post_pose()): what is
##    worth a look - from one shared survey of the world (`_survey()`, once a physics frame for the
##    whole crowd) and the events other systems post (`notice()`) - and a damped, speed-capped
##    spring per axis that eases the head (and past `CHEST_FROM` a little of the chest) round;
##  - the POSE, here (`_process_modification_with_delta()`): a SkeletonModifier3D on the rig's
##    skeleton turning Spine01 / Spine (the chest), neck and Head about the world's up and the
##    face's right, after the clip, the life overlays and errands have posed the rig, so it never
##    accumulates on a pose and fades out by itself when its person leaves the look range.
## Things worth a look, strongest first (`Kind`, weights in `WEIGHT`): a gunshot or blast that
## scared this person (Pedestrian._look_threat), a blast anywhere within BLAST_RANGE, a car crash
## or a car being shot, the player landing hard, the player boosting past, a police / emergency
## siren, a burning car, anything in the group `crowd_look_magnet` (a busker, a performer: meta
## `look_range` / `look_weight` optional), a talk partner or a shop window (the life layer), a car
## going by close, the player walking past, a passer-by. Loud ones are heard from behind; quiet
## ones need to be in front. Social glances (the player, a passer-by) are short and often end in a
## look-away (civil inattention: eyes off and a little down). With nothing going on, an idle
## glance to the side now and then. Other systems that pose the head themselves call
## `hold_off(ped, seconds)` (or set `held` 1) and the look fades out under them.
## Only people within Pedestrian.look_range of the player AND of the camera get one (made the
## first time they are near, so a crowd far away has none). `CROWD_LOOK=0` in the environment
## turns it off (the old _post_pose head turn, the A/B).

enum Kind { THREAT, BLAST, CRASH, LANDING, BOOST, SIREN, FIRE, MAGNET, LIFE, CAR, PLAYER, PASSER, IDLE, AWAY }

## How much each kind is worth (the best score wins; a new target must beat the one held by
## `STICKY`). LIFE sits above the social glances, so a talker keeps to the conversation.
const WEIGHT := {
	Kind.THREAT: 12.0, Kind.BLAST: 9.0, Kind.CRASH: 8.0, Kind.LANDING: 8.0, Kind.BOOST: 6.5,
	Kind.SIREN: 5.0, Kind.FIRE: 4.5, Kind.MAGNET: 4.0, Kind.LIFE: 3.6, Kind.CAR: 2.4,
	Kind.PLAYER: 3.0, Kind.PASSER: 1.6, Kind.IDLE: 0.3, Kind.AWAY: 0.2,
}
## Heard from any direction (true) or seen only in front (false).
const HEARD := {
	Kind.THREAT: true, Kind.BLAST: true, Kind.CRASH: true, Kind.LANDING: true, Kind.BOOST: true,
	Kind.SIREN: true, Kind.FIRE: false, Kind.MAGNET: false, Kind.LIFE: true, Kind.CAR: false,
	Kind.PLAYER: false, Kind.PASSER: false,
}
## Seconds a look at each kind lasts [min, max] before the person may move on.
const DWELL := {
	Kind.THREAT: Vector2(2.0, 3.0), Kind.BLAST: Vector2(2.4, 4.0), Kind.CRASH: Vector2(2.0, 3.6),
	Kind.LANDING: Vector2(1.8, 3.0), Kind.BOOST: Vector2(1.2, 2.2), Kind.SIREN: Vector2(1.5, 3.0),
	Kind.FIRE: Vector2(2.0, 4.0), Kind.MAGNET: Vector2(2.5, 5.5), Kind.LIFE: Vector2(1.5, 3.0),
	Kind.CAR: Vector2(0.6, 1.4), Kind.PLAYER: Vector2(0.8, 1.6), Kind.PASSER: Vector2(0.45, 1.0),
	Kind.IDLE: Vector2(0.7, 1.6), Kind.AWAY: Vector2(0.4, 0.9),
}
## Seconds after a look before the same thing is worth a full look again (it is worth
## `REPEAT_SHARE` of its weight meanwhile), so people do not stare at a passing car for good.
const COOLDOWN := 5.0
const REPEAT_SHARE := 0.3
## A target held must be beaten by this factor.
const STICKY := 1.3
## The cone of sight: things further round than this from the face are not seen (radians).
const SIGHT := 1.92 # 110 degrees
## How far round the head and neck turn (radians), and how far the chest adds (radians), the
## chest starting to help past CHEST_FROM.
const HEAD_YAW_MAX := 1.26 # 72 degrees
const CHEST_YAW_MAX := 0.38 # 22 degrees
const CHEST_FROM := 0.87 # 50 degrees
const CHEST_SHARE := 0.15
const PITCH_UP := 0.35
const PITCH_DOWN := -0.45
## The springs: stiffness (1/s) and top speed (rad/s), calm and startled.
const STIFF_CALM := 7.0
const STIFF_STARTLE := 13.0
const SPEED_CALM := 2.6
const SPEED_STARTLE := 6.5
## Chance a social glance ends in a look-away, and a quiet minute's idle glances (seconds apart).
const AWAY_SHARE := 0.55
const IDLE_GAP := Vector2(3.5, 9.0)

## Reaches (metres).
const BLAST_RANGE := 160.0
const CRASH_RANGE := 55.0
const SHOT_CAR_RANGE := 35.0
const BOOST_RANGE := 30.0
const BOOST_SPEED := 16.0
const SIREN_RANGE := 70.0
const FIRE_RANGE := 30.0
const MAGNET_RANGE := 12.0
const PASSER_RANGE := 4.5
## How long a posted event lasts (seconds) unless given.
const EVENT_LIFE := 3.5

static var enabled: bool = OS.get_environment("CROWD_LOOK") != "0"

## Posted and surveyed events: [kind, true world position, node or null, born (s), life (s),
## range (m), weight scale, id]. Positions are true world, so an origin shift moves nothing.
static var _events: Array = []
static var _next_id: int = 1
static var _survey_frame: int = -1
static var _blasts_seen: int = -1
static var _walkers: Array = [] # [node, true world position]
static var _walkers_frame: int = -1000
static var _boost_id: int = 0
static var _boost_until: float = 0.0
static var _camera_at := Vector3.INF # scene position of the camera, last survey

## The person this modifier belongs to, and what it holds.
var ped: Node3D
var chest_bones := PackedInt32Array()
var neck: int = -1
var head: int = -1
## Applied angles (radians): head yaw over the chest's, the chest's yaw, the head's pitch.
var yaw: float = 0.0
var chest: float = 0.0
var pitch: float = 0.0
## 0..1: another system holds the head (onlookers, umbrellas, errands): the look fades out.
var held: float = 0.0
## False: no quiet looks (cars going by, the player walking past, passers-by, idle glances) -
## the checks turn them off to stage one thing at a time.
var social: bool = true
var _held_until: float = -1.0
var _yaw_v: float = 0.0
var _chest_v: float = 0.0
var _pitch_v: float = 0.0
var _fade: float = 0.0
## The target: kind, a fixed point (true world) or a node to follow (+ height), its event id.
var _kind: int = Kind.IDLE
var _point := Vector3.INF
var _node: Node3D
var _lift: float = 0.0
var _target_id: int = 0
var _dwell: float = 0.0
var _scan: float = 0.0
var _idle_in: float = 0.0
var _away_side: float = 1.0
var _seen := {} # id -> time last looked at
var _rng := RandomNumberGenerator.new()


## The modifier for `p`'s skeleton, made the first time (null when off or the rig lacks bones).
static func of(p: Node3D, skel: Skeleton3D) -> CrowdLook:
	if not enabled or skel == null:
		return null
	for c in skel.get_children():
		if c is CrowdLook:
			return c
	var m := CrowdLook.new()
	m.name = "CrowdLook"
	m.ped = p
	for b in ["Spine01", "Spine"]:
		var i := skel.find_bone(b)
		if i >= 0:
			m.chest_bones.append(i)
	m.neck = skel.find_bone("neck")
	m.head = skel.find_bone("Head")
	if m.neck < 0 or m.head < 0:
		m.free()
		return null
	m._rng.seed = hash([p.get_instance_id(), "look"])
	m._idle_in = m._rng.randf_range(IDLE_GAP.x, IDLE_GAP.y)
	skel.add_child(m)
	return m


## Another system poses the head for `seconds`: the look fades out under it.
static func hold_off(p: Node, seconds: float) -> void:
	var skel: Skeleton3D = p.get("_head_skel") if p else null
	if skel == null:
		return
	for c in skel.get_children():
		if c is CrowdLook:
			(c as CrowdLook)._held_until = _now() + seconds


## Something worth a look happened at `at` (a scene position): a crash, a hard landing, a shot
## car, a performer's flourish. `node` is followed while it lasts.
static func notice(at: Vector3, kind: int, reach: float = -1.0, life: float = EVENT_LIFE, node: Node3D = null, scale: float = 1.0) -> int:
	if not enabled:
		return 0
	if reach < 0.0:
		reach = CRASH_RANGE
	var id := _next_id
	_next_id += 1
	_events.append([kind, _to_world(at), node, _now(), life, reach, scale, id])
	if _events.size() > 48:
		_events.pop_front()
	return id


## Vehicle.take_hit()'s hook: a crash or a car being shot or blasted turns heads.
static func car_hit(car: Node3D, kind: int, damage: float) -> void:
	if not enabled or car == null or not car.is_inside_tree():
		return
	if kind == Vehicle.HIT_BLAST: # the blast is surveyed itself
		return
	if kind == Vehicle.HIT_CRASH:
		notice(car.global_position, Kind.CRASH, CRASH_RANGE, 3.5, car, clampf(0.6 + damage / 12.0, 0.6, 1.4))
	else:
		notice(car.global_position, Kind.CRASH, SHOT_CAR_RANGE, 2.0, car, 0.7)


## LandingFX.land()'s hook: the player hitting the ground at `fall` m/s.
static func landing(player: Node3D, fall: float) -> void:
	if not enabled or player == null or fall < 30.0:
		return
	var k := clampf((fall - 30.0) / 55.0, 0.0, 1.0)
	notice(player.global_position, Kind.LANDING, 16.0 + 30.0 * k, 2.6, player, 0.6 + 0.5 * k)


static func _now() -> float:
	return float(Engine.get_physics_frames()) / float(Engine.physics_ticks_per_second)


static func _to_world(p: Vector3) -> Vector3:
	return WorldState.to_world(p)


static func _to_local(p: Vector3) -> Vector3:
	return WorldState.to_local(p)


## Once a physics frame for everyone: blasts, the player's boost, sirens and burning cars become
## events; the camera's position and (four times a second) the walkers near it are kept.
static func _survey(tree: SceneTree) -> void:
	var frame := Engine.get_physics_frames()
	if frame == _survey_frame:
		return
	_survey_frame = frame
	var now := _now()
	var i := 0
	while i < _events.size():
		var e: Array = _events[i]
		if now - float(e[3]) > float(e[4]):
			_events.remove_at(i)
		else:
			i += 1
	var cam := tree.root.get_camera_3d() if tree.root else null
	_camera_at = cam.global_position if cam else Vector3.INF
	if _blasts_seen < 0:
		_blasts_seen = Explosion.blast_count
	elif Explosion.blast_count != _blasts_seen:
		_blasts_seen = Explosion.blast_count
		_events.append([Kind.BLAST, Explosion.last_blast_world, null, now, 3.5, BLAST_RANGE, 1.0, _next_id])
		_next_id += 1
	var player := Pedestrian._player
	if is_instance_valid(player) and player is CharacterBody3D:
		var v := (player as CharacterBody3D).velocity
		if v.length() > BOOST_SPEED:
			if now > _boost_until:
				_boost_id = notice(player.global_position, Kind.BOOST, BOOST_RANGE, 1.0, player)
			else:
				for e: Array in _events:
					if int(e[7]) == _boost_id:
						e[3] = now # still going: keep the event alive
						e[1] = _to_world(player.global_position)
			_boost_until = now + 0.6
	if frame % 15 == 0:
		_survey_slow(tree, now)


## Four times a second: sirens, burning cars, magnets and walkers within reach of the camera.
static func _survey_slow(tree: SceneTree, now: float) -> void:
	var centre := _camera_at
	if is_instance_valid(Pedestrian._player):
		centre = Pedestrian._player.global_position if centre == Vector3.INF else centre
	if centre == Vector3.INF:
		return
	var reach2 := (SIREN_RANGE + 30.0) * (SIREN_RANGE + 30.0)
	# Drop the last survey's standing events (sirens, fires, magnets) and post the current ones.
	var i := 0
	while i < _events.size():
		var k: int = _events[i][0]
		if k == Kind.SIREN or k == Kind.FIRE or k == Kind.MAGNET:
			_events.remove_at(i)
		else:
			i += 1
	for group in ["police_car", "emergency_unit"]:
		for n in tree.get_nodes_in_group(group):
			var car := n as Node3D
			if car and car.is_inside_tree() and car.global_position.distance_squared_to(centre) < reach2 \
					and car.has_method("siren_running") and car.siren_running():
				_post(Kind.SIREN, car, SIREN_RANGE, 1.0, now, 1.2)
	for c in CarDamage._burning:
		var car := c as Node3D
		if is_instance_valid(car) and car.global_position.distance_squared_to(centre) < reach2:
			_post(Kind.FIRE, car, FIRE_RANGE, 1.0, now, 1.0)
	for n in tree.get_nodes_in_group("crowd_look_magnet"):
		var m := n as Node3D
		if m and m.is_inside_tree() and m.global_position.distance_squared_to(centre) < reach2:
			_post(Kind.MAGNET, m, float(m.get_meta("look_range", MAGNET_RANGE)), float(m.get_meta("look_weight", 1.0)), now, 0.0)
	_walkers.clear()
	var r2 := 40.0 * 40.0
	for n in tree.get_nodes_in_group("pedestrian"):
		var p := n as Node3D
		if p and p.is_inside_tree() and p.global_position.distance_squared_to(centre) < r2:
			_walkers.append(p)


## A standing event for `node`, keeping the id it had last survey (so a look holds on).
static func _post(kind: int, node: Node3D, reach: float, scale: float, now: float, lift: float) -> void:
	var id := hash([kind, node.get_instance_id()])
	_events.append([kind, _to_world(node.global_position + Vector3.UP * lift), node, now, 0.6, reach, scale, id])


## The physics tick's half: pick what to look at and ease toward it.
func think(delta: float) -> void:
	if ped == null or not is_instance_valid(ped):
		return
	var tree := ped.get_tree()
	_survey(tree)
	var now := _now()
	held = clampf(held - delta * 2.0, 0.0, 1.0) if now > _held_until else clampf(held + delta * 4.0, 0.0, 1.0)
	var eye := ped.global_position + Vector3.UP * 1.55 * _visual_scale()
	var near_cam := _camera_at == Vector3.INF or eye.distance_squared_to(_camera_at) \
		< pow(float(ped.get("look_range")) * 1.2, 2.0)
	_fade = clampf(_fade + (delta * 3.0 if near_cam else -delta * 2.0), 0.0, 1.0)
	_dwell -= delta
	_scan -= delta
	_idle_in -= delta
	if _scan <= 0.0:
		_scan = _rng.randf_range(0.22, 0.4)
		_choose(eye, now)
	# Where the target is now, against the way the body faces.
	var face: float = (ped.get("_visual") as Node3D).global_rotation.y
	var want_yaw := 0.0
	var want_pitch: float = ped.get("_posture_pitch")
	var startled := _kind <= Kind.LANDING
	var target := _target_point()
	if _kind == Kind.IDLE or _kind == Kind.AWAY:
		want_yaw = _point.x
		want_pitch += _point.y
	elif target != Vector3.INF:
		var d := target - eye
		var rel := angle_difference(face, atan2(-d.x, -d.z))
		want_yaw = clampf(rel, -(HEAD_YAW_MAX + CHEST_YAW_MAX), HEAD_YAW_MAX + CHEST_YAW_MAX)
		want_pitch = clampf(atan2(d.y, Vector2(d.x, d.z).length()), PITCH_DOWN, PITCH_UP)
	var want_chest := clampf(want_yaw * CHEST_SHARE + signf(want_yaw) * maxf(absf(want_yaw) - CHEST_FROM, 0.0),
		-CHEST_YAW_MAX, CHEST_YAW_MAX)
	var want_head := clampf(want_yaw - want_chest, -HEAD_YAW_MAX, HEAD_YAW_MAX)
	var stiff := STIFF_STARTLE if startled else STIFF_CALM
	var top := SPEED_STARTLE if startled else SPEED_CALM
	var res := _spring(yaw, _yaw_v, want_head, stiff, top, delta)
	yaw = res.x
	_yaw_v = res.y
	res = _spring(chest, _chest_v, want_chest, stiff * 0.7, top * 0.5, delta)
	chest = res.x
	_chest_v = res.y
	res = _spring(pitch, _pitch_v, want_pitch, stiff, top * 0.7, delta)
	pitch = res.x
	_pitch_v = res.y
	ped.set("_look_yaw", yaw + chest)
	ped.set("_look_pitch", pitch)
	active = true


## A critically damped spring with a top speed: [value, velocity].
static func _spring(x: float, v: float, to: float, w: float, top: float, dt: float) -> Vector2:
	var steps := maxi(1, ceili(dt / 0.034))
	var h := dt / float(steps)
	for s in steps:
		v += (w * w * (to - x) - 2.0 * w * v) * h
		v = clampf(v, -top, top)
		x += v * h
	return Vector2(x, v)


func _visual_scale() -> float:
	var vis := ped.get("_visual") as Node3D
	return vis.scale.y if vis else 1.0


func _target_point() -> Vector3:
	if is_instance_valid(_node) and _node.is_inside_tree():
		return _node.global_position + Vector3.UP * _lift
	if _point != Vector3.INF and _kind != Kind.IDLE and _kind != Kind.AWAY:
		return _to_local(_point)
	return Vector3.INF


## What is worth a look right now, from everything in reach, against what is held.
func _choose(eye: Vector3, now: float) -> void:
	var face: float = (ped.get("_visual") as Node3D).global_rotation.y
	var held_score := 0.0
	if _dwell > 0.0 and _kind != Kind.IDLE and _kind != Kind.AWAY:
		held_score = float(WEIGHT[_kind]) * STICKY
	elif _dwell > 0.0:
		held_score = float(WEIGHT[_kind])
	var best_score := held_score
	var best: Array = []
	var see := func(at: Vector3) -> bool:
		var d := at - eye
		return absf(angle_difference(face, atan2(-d.x, -d.z))) < SIGHT
	var weigh := func(kind: int, at: Vector3, reach: float, scale: float, id: int) -> float:
		var dist := at.distance_to(eye)
		if dist > reach or dist < 0.4:
			return 0.0
		if not HEARD.get(kind, false) and not see.call(at):
			return 0.0
		var s := float(WEIGHT[kind]) * scale * (1.0 - 0.5 * dist / reach)
		if id != 0 and id != _target_id and _seen.has(id) and now - float(_seen[id]) < COOLDOWN:
			s *= REPEAT_SHARE
		return s
	# A threat this person ran from (Pedestrian._scare()).
	if float(ped.get("_look_hold")) > 0.0 and ped.get("_look_threat") != Vector3.INF:
		var s := float(WEIGHT[Kind.THREAT])
		if s > best_score:
			best_score = s
			best = [Kind.THREAT, ped.get("_look_threat"), null, 0.0, -1]
	for e: Array in _events:
		var at := _to_local(e[1])
		if is_instance_valid(e[2]) and (e[2] as Node3D).is_inside_tree():
			at = (e[2] as Node3D).global_position + Vector3.UP * _lift_for(int(e[0]))
		if e[2] == ped:
			continue
		var s: float = weigh.call(int(e[0]), at, float(e[5]), float(e[6]), int(e[7]))
		if s > best_score:
			best_score = s
			best = [int(e[0]), at, e[2] if is_instance_valid(e[2]) else null, _lift_for(int(e[0])), int(e[7])]
	# The life layer's own look (a talk partner, a window, a dog).
	var life_look: Vector3 = ped.get("_life_look")
	if life_look != Vector3.INF and int(ped.get("_act")) != 0:
		var s := float(WEIGHT[Kind.LIFE])
		if s > best_score:
			best_score = s
			best = [Kind.LIFE, life_look, null, 0.0, -2]
	if social and best_score < float(WEIGHT[Kind.CAR]) * 1.2:
		_quiet_candidates(eye, now, weigh, best_score, best)
		if not best.is_empty() and best.size() == 6:
			best_score = best[5]
			best.resize(5)
	if not best.is_empty():
		_start(best, now)
		return
	if _dwell > 0.0:
		return
	# Nothing new: what was a glance at somebody may end with eyes off; else ahead, or now and
	# then an idle glance to the side.
	if (_kind == Kind.PLAYER or _kind == Kind.PASSER) and _rng.randf() < AWAY_SHARE:
		_away_side = -signf(yaw + chest) if absf(yaw + chest) > 0.05 else (1.0 if _rng.randf() < 0.5 else -1.0)
		_set_free(Kind.AWAY, Vector2(_away_side * _rng.randf_range(0.18, 0.4), -_rng.randf_range(0.08, 0.2)))
		return
	if _idle_in <= 0.0 and social:
		_idle_in = _rng.randf_range(IDLE_GAP.x, IDLE_GAP.y)
		var side := 1.0 if _rng.randf() < 0.5 else -1.0
		_set_free(Kind.IDLE, Vector2(side * _rng.randf_range(0.3, 0.8), _rng.randf_range(-0.12, 0.1)))
		return
	_set_free(Kind.IDLE, Vector2.ZERO)
	_dwell = 0.0


## The quiet things (a car close by, the player walking past, a passer-by), only when nothing
## louder is on. Writes the winner into `best` as [kind, at, node, lift, id, score].
func _quiet_candidates(eye: Vector3, _now_s: float, weigh: Callable, best_score: float, best: Array) -> void:
	var tree := ped.get_tree()
	for car: Array in Pedestrian._nearby_cars(tree):
		var at: Vector3 = car[0]
		var vel: Vector3 = car[1]
		if vel.length_squared() < 9.0:
			continue
		var s: float = weigh.call(Kind.CAR, at + vel * 0.12 + Vector3.UP * 0.6, float(ped.get("look_car_range")), 1.0, 0)
		if s > best_score:
			best_score = s
			best.assign([Kind.CAR, at + vel * 0.12 + Vector3.UP * 0.6, null, 0.0, 0, s])
	var player := Pedestrian._player
	if is_instance_valid(player):
		var at := player.global_position + Vector3.UP * 1.5
		var s: float = weigh.call(Kind.PLAYER, at, float(ped.get("look_player_range")), 1.0, player.get_instance_id())
		if s > best_score:
			best_score = s
			best.assign([Kind.PLAYER, at, player, 1.5, player.get_instance_id(), s])
	var me := ped.global_position
	for n in _walkers:
		var o := n as Node3D
		if o == ped or not is_instance_valid(o):
			continue
		var at := o.global_position
		if at.distance_squared_to(me) > PASSER_RANGE * PASSER_RANGE:
			continue
		var s: float = weigh.call(Kind.PASSER, at + Vector3.UP * 1.55, PASSER_RANGE, 1.0, o.get_instance_id())
		# Only some people glance at each passer-by, and not every time they pass.
		if s > best_score and (hash([get_instance_id(), o.get_instance_id()]) & 3) != 0:
			best_score = s
			best.assign([Kind.PASSER, at + Vector3.UP * 1.55, o, 1.55, o.get_instance_id(), s])


static func _lift_for(kind: int) -> float:
	match kind:
		Kind.BOOST, Kind.LANDING:
			return 1.4
		Kind.CRASH, Kind.FIRE:
			return 0.8
		Kind.SIREN:
			return 1.2
		Kind.MAGNET:
			return 1.3
	return 0.0


func _start(best: Array, now: float) -> void:
	var kind: int = best[0]
	var id: int = best[4]
	if id != _target_id or kind != _kind:
		var dw: Vector2 = DWELL[kind]
		_dwell = _rng.randf_range(dw.x, dw.y)
		if _target_id != 0:
			_seen[_target_id] = now
	_kind = kind
	_node = best[2] as Node3D
	_lift = best[3]
	_point = _to_world(best[1])
	_target_id = id
	if id != 0:
		_seen[id] = now
	if _seen.size() > 40:
		_seen.clear()


## A look that is not at a thing: [yaw, pitch offset] in `_point`.
func _set_free(kind: int, angles: Vector2) -> void:
	if _target_id != 0:
		_seen[_target_id] = _now()
	_kind = kind
	_node = null
	_target_id = 0
	_point = Vector3(angles.x, angles.y, 0.0)
	var dw: Vector2 = DWELL[kind]
	_dwell = _rng.randf_range(dw.x, dw.y) if angles != Vector2.ZERO else 0.0


func _process_modification_with_delta(delta: float) -> void:
	var skel := get_skeleton()
	if skel == null or ped == null or not is_instance_valid(ped):
		return
	# Out of the look range nobody calls think(): ease back to the clip's pose and stop.
	if not bool(ped.get("_look_near")):
		var k := exp(-4.0 * delta)
		yaw *= k
		chest *= k
		pitch *= k
		if absf(yaw) + absf(chest) + absf(pitch) < 0.004:
			yaw = 0.0
			chest = 0.0
			pitch = 0.0
			active = false
			return
	var w := _fade * (1.0 - held)
	if w <= 0.001 or absf(yaw) + absf(chest) + absf(pitch) < 0.002:
		return
	var vis := ped.get("_visual") as Node3D
	var face := vis.global_rotation.y if vis else 0.0
	var to_skel := skel.global_basis.orthonormalized().inverse()
	var up := (to_skel * Vector3.UP).normalized()
	var right := (to_skel * Vector3(cos(face), 0.0, -sin(face))).normalized()
	var n := chest_bones.size()
	for i in n:
		_turn(skel, chest_bones[i], Quaternion(up, chest * w / float(n)))
	_turn(skel, neck, Quaternion(up, yaw * w * 0.4) * Quaternion(right, pitch * w * 0.4))
	_turn(skel, head, Quaternion(up, yaw * w * 0.6) * Quaternion(right, pitch * w * 0.6))


## Turns `bone` by `r` (a rotation in skeleton space) over its current pose.
static func _turn(skel: Skeleton3D, bone: int, r: Quaternion) -> void:
	var parent := skel.get_bone_parent(bone)
	var pq := GripHands._chain(skel, parent).basis.orthonormalized().get_rotation_quaternion() \
		if parent >= 0 else Quaternion.IDENTITY
	skel.set_bone_pose_rotation(bone, (pq.inverse() * r * pq * skel.get_bone_pose_rotation(bone)).normalized())
