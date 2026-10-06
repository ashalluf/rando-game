class_name Onlookers
extends Node
## What a crowd does after chaos dies down (2026-10-05, fleet task "onlookers"): once the panic
## near a wreck, a blast site or a body is over, people come back and stand round it in a loose
## ring at a distance - filming it on their phones held up at eye level (the screen lit, a video
## light on the back after dark), pointing, a hand over the mouth, one or two on the phone
## calling for help, the rest just staring with their arms folded - and they drift away as the
## responders (Emergency's crews and units, the police) arrive, or after a minute or two.
##
## Built on crowd life (CrowdLife, Pedestrian's "Life" section) and near the camera only: an
## onlooker is a plain walker within Pedestrian.life_range of the player, recruited when it is
## free (Pedestrian._life_free(): no stop, errand, crossing or panic under way), sent round its
## own block's pavement ring to a spot at the scene's distance band (`CrowdLife.Act.WATCH`), and
## posed there by an arm solve laid over the life clips (pose()). Panic still wins: a new shot or
## blast scares them off (Pedestrian._scare -> _end_act -> release()), and they come back once
## it is quiet again.
##
## One node under the tree root, made by the first walker with life clips (ensure()). Scenes
## (`scenes`) are kept in TRUE world positions (WorldState) and looked for every SCAN seconds,
## the way Emergency finds its calls: CarDamage's burning cars and wrecks, Explosion.blast_count,
## fresh Ragdolls in PhysicsBudget's debris. Every roll is a hash of the scene and the person,
## never a chunk or a walker's rng. ONLOOKERS=0 in the environment turns it off (the A/B).
##
## Pedestrian hooks (one line each): `watch` (this person's part in a scene), walk() from
## _walk, pose() from _physics_process, release() from _end_act.

static var enabled: bool = OS.get_environment("ONLOOKERS") != "0"
static var debug: bool = OS.get_environment("ONLOOKERS_DEBUG") == "1"

enum Kind { WRECK, BLAST, BODY }
## What an onlooker does at the scene.
enum Role { GAWK, FILM, POINT, COVER, CALL }

## How often scenes are looked for and people recruited (s).
const SCAN := 0.5
## Scenes are watched only this close to the player (m): near the camera, where crowd life is.
const SCENE_RADIUS := 80.0
## Two events this close are one scene (m).
const MERGE := 16.0
## Seconds of quiet (no shot or blast within ALARM_REACH) before anyone comes back.
const SETTLE := 3.5
const ALARM_REACH := 60.0
## Walkers this close to a scene may come and look (m).
const RECRUIT_REACH := 55.0
## People recruited per scene per scan (they arrive staggered), and per scene in all
## (CROWD_MIN..CROWD_MAX by a hash of the scene) and in the whole city.
const RECRUIT_STEP := 2
const CROWD_MIN := 5
const CROWD_MAX := 12
const MAX_WATCHERS := 28
## The ring's distance band per kind (m from the scene): a body is crowded closest, a burning
## car kept off by its heat.
const BAND := {Kind.WRECK: Vector2(6.5, 13.0), Kind.BLAST: Vector2(7.0, 15.0), Kind.BODY: Vector2(4.2, 10.0)}
const BURNING_BAND := Vector2(9.5, 17.0)
## Onlookers keep this far apart (m).
const SPACING := 1.3
## How long a scene keeps its crowd after it went quiet (s), by hash.
const LINGER := Vector2(70.0, 150.0)
## Responders this close to a scene send its crowd away (m), each after their own delay (s).
const RESPONDER_REACH := 38.0
const RESPONDER_GROUPS := ["responder", "emergency_unit", "police", "police_car"]
const LEAVE_DELAY := Vector2(0.6, 9.0)
## How long a body may lie before it no longer draws anyone (s).
const BODY_FRESH := 90.0
## How long a watched body is kept from its first being seen (s; PhysicsBudget's debris clock).
const BODY_HOLD := 75.0
## Shares of the roles (the callers come first: 1 or 2 a scene).
const FILM_SHARE := 0.42
const POINT_SHARE := 0.16
const COVER_SHARE := 0.18
## How long a call lasts (s), then the caller films or stares.
const CALL_SECONDS := Vector2(14.0, 32.0)

## The open scenes: {id, kind, world (true), born_ms, linger, crowd, members, spots, callers,
## closing, ref (the car or the body)}.
var scenes: Array[Dictionary] = []
## Recruited since the start (tests read it).
var recruited: int = 0

static var _node: Onlookers
static var _phone: Mesh
var _scan_t: float = 0.0
var _blasts_seen: int = 0
var _next_id: int = 1
var _player: Node3D


## The one node, made under the tree root the first time a walker with life clips appears.
static func ensure(tree: SceneTree) -> void:
	if not enabled or tree == null or (_node != null and is_instance_valid(_node)):
		return
	_node = Onlookers.new()
	_node.name = "Onlookers"
	tree.root.add_child.call_deferred(_node)


static func find() -> Onlookers:
	return _node if _node != null and is_instance_valid(_node) else null


func _ready() -> void:
	_blasts_seen = Explosion.blast_count


func _exit_tree() -> void:
	if _node == self:
		_node = null


func _physics_process(delta: float) -> void:
	if not enabled:
		return
	_scan_t -= delta
	if _scan_t > 0.0:
		return
	_scan_t = SCAN
	if _player == null or not is_instance_valid(_player) or not _player.is_inside_tree():
		_player = get_tree().get_first_node_in_group("player") as Node3D
	if _player == null:
		scenes.clear()
		return
	_look_for_scenes()
	_upkeep()
	_recruit()


static func _now() -> int:
	return Pedestrian._life_now_ms()


# --- Scenes ------------------------------------------------------------------------------------

func _look_for_scenes() -> void:
	var pp := _player.global_position
	for list: Array in [CarDamage._burning, CarDamage._wrecks]:
		for item in list:
			var car: Vehicle = (item as CarDamage).car if item is CarDamage else item as Vehicle
			if car == null or not is_instance_valid(car) or not car.is_inside_tree() or car is EmergencyCar:
				continue
			if car.global_position.distance_to(pp) > SCENE_RADIUS:
				continue
			open_scene(Kind.WRECK, WorldState.to_world(car.global_position), car)
	if Explosion.blast_count != _blasts_seen:
		_blasts_seen = Explosion.blast_count
		var at := WorldState.to_local(Explosion.last_blast_world)
		if at.distance_to(pp) < SCENE_RADIUS:
			open_scene(Kind.BLAST, Explosion.last_blast_world)
	var now := Time.get_ticks_msec() / 1000.0
	for node in get_tree().get_nodes_in_group(PhysicsBudget.DEBRIS_GROUP):
		var doll := node as Ragdoll
		if doll == null or doll.is_queued_for_deletion() or doll.has_meta("responder") or doll.bodies.is_empty():
			continue
		if doll.has_meta("onlooked") or now - float(doll.get_meta("spawn_time", now)) > BODY_FRESH:
			continue
		var b := doll.bodies[0] as Node3D
		if b == null or not is_instance_valid(b) or b.global_position.distance_to(pp) > SCENE_RADIUS:
			continue
		doll.set_meta("onlooked", true)
		open_scene(Kind.BODY, WorldState.to_world(b.global_position), doll)
		# A body is debris for twelve seconds, less than a panic lasts: kept while it is watched.
		var age := now - float(doll.get_meta("spawn_time", now))
		doll.set_meta("debris_life", maxf(float(doll.get_meta("debris_life", 0.0)), age + BODY_HOLD))


## A scene at `world` (a true world position), or the open one it merges into. A car keeps its
## own scene (one per car); a blast or a body joins whatever is there. Returns the scene.
func open_scene(kind: int, world: Vector3, ref: Object = null) -> Dictionary:
	for s: Dictionary in scenes:
		if ref != null and s.ref == ref:
			return s
	for s: Dictionary in scenes:
		if (s.world as Vector3).distance_to(world) < MERGE and not s.closing:
			# A body by the wreck is the wreck's scene; a blast there wakes it up again.
			if kind == Kind.BODY and s.kind == Kind.BLAST:
				s.kind = Kind.BODY
				s.ref = ref
				s.world = world
			if ref != null and s.ref == null:
				s.ref = ref
			return s
	var id := _next_id
	_next_id += 1
	var h := hash([world.snapped(Vector3.ONE * 4.0), kind, "onlookers"])
	var s := {
		"id": id, "kind": kind, "world": world, "born_ms": _now(), "ref": ref,
		"linger": lerpf(LINGER.x, LINGER.y, _h01(h, 1)),
		"crowd": CROWD_MIN + int(_h01(h, 2) * float(CROWD_MAX - CROWD_MIN + 1)),
		"callers_want": 1 if _h01(h, 3) < 0.6 else 2,
		"callers": 0, "members": [], "spots": [], "closing": false, "quiet_ms": -1, "seed": h,
	}
	scenes.append(s)
	if debug:
		print("ONLOOKERS scene %d kind %d at %s crowd %d" % [id, kind, world, int(s.crowd)])
	return s


## The scene's point in scene coordinates (where the car or the body is now).
func scene_point(s: Dictionary) -> Vector3:
	var ref: Variant = s.ref
	if ref != null and is_instance_valid(ref):
		if ref is Ragdoll and not (ref as Ragdoll).bodies.is_empty() and is_instance_valid((ref as Ragdoll).bodies[0]):
			return ((ref as Ragdoll).bodies[0] as Node3D).global_position
		if ref is Node3D and (ref as Node3D).is_inside_tree():
			return (ref as Node3D).global_position
	return WorldState.to_local(s.world)


func _band(s: Dictionary) -> Vector2:
	var ref: Variant = s.ref
	if s.kind == Kind.WRECK and ref is Vehicle and is_instance_valid(ref):
		var dmg: Variant = (ref as Vehicle)._damage
		if dmg != null and is_instance_valid(dmg) and (dmg as CarDamage).on_fire():
			return BURNING_BAND
	return BAND[s.kind]


## Quiet: no shot or blast near the scene for SETTLE seconds (Pedestrian.alarm's own record).
func _quiet(s: Dictionary, at: Vector3) -> bool:
	var since := Time.get_ticks_msec() - Pedestrian._last_alarm_ms
	if Pedestrian._last_alarm_at != Vector3.INF and since < int(SETTLE * 1000.0) \
			and Pedestrian._last_alarm_at.distance_to(at) < ALARM_REACH:
		return false
	return _now() - int(s.born_ms) > int(SETTLE * 1000.0)


func _upkeep() -> void:
	var pp := _player.global_position
	var now := _now()
	for i in range(scenes.size() - 1, -1, -1):
		var s: Dictionary = scenes[i]
		s.members = (s.members as Array).filter(func(m): return is_instance_valid(m) and is_same((m as Pedestrian).watch.get("scene"), s))
		var at := scene_point(s)
		var gone := at.distance_to(pp) > SCENE_RADIUS * 1.6
		var ref: Variant = s.ref
		if ref != null and not is_instance_valid(ref):
			# The body taken away, the wreck cleared.
			_close(s)
		if not s.closing:
			if _quiet(s, at):
				if int(s.quiet_ms) < 0:
					s.quiet_ms = now
				if now - int(s.quiet_ms) > int(float(s.linger) * 1000.0):
					_close(s)
			else:
				s.quiet_ms = -1
			if _responders_at(at):
				_close(s)
		if gone or (s.closing and (s.members as Array).is_empty()):
			for m: Pedestrian in s.members:
				leave(m)
			scenes.remove_at(i)


## Help has come (an engine, an ambulance, its crew, the police): the crowd goes, one by one.
func _responders_at(at: Vector3) -> bool:
	var r2 := RESPONDER_REACH * RESPONDER_REACH
	for g: String in RESPONDER_GROUPS:
		for n in get_tree().get_nodes_in_group(g):
			if n is Node3D and (n as Node3D).is_inside_tree() and (n as Node3D).global_position.distance_squared_to(at) < r2:
				return true
	return false


func _close(s: Dictionary) -> void:
	if s.closing:
		return
	s.closing = true
	if debug:
		print("ONLOOKERS scene %d closes (%d watching)" % [int(s.id), (s.members as Array).size()])
	var now := _now()
	for m: Pedestrian in s.members:
		var h := hash([int(s.seed), m.get_instance_id(), "leave"])
		m.watch.leave_ms = now + int(1000.0 * lerpf(LEAVE_DELAY.x, LEAVE_DELAY.y, _h01(h, 0)))


# --- Recruiting --------------------------------------------------------------------------------

func _recruit() -> void:
	var total := 0
	for s: Dictionary in scenes:
		total += (s.members as Array).size()
	if total >= MAX_WATCHERS:
		return
	var open: Array = []
	for s: Dictionary in scenes:
		if not s.closing and int(s.quiet_ms) >= 0 and (s.members as Array).size() < int(s.crowd):
			open.append(s)
	if open.is_empty():
		return
	var peds := get_tree().get_nodes_in_group("pedestrian")
	for s: Dictionary in open:
		var at := scene_point(s)
		var cands: Array = []
		for n in peds:
			var p := n as Pedestrian
			if p == null or not p.is_inside_tree() or not p._lives() or not _free(p):
				continue
			var d2 := p.global_position.distance_squared_to(at)
			if d2 < RECRUIT_REACH * RECRUIT_REACH:
				cands.append([d2, p])
		cands.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
		var took := 0
		for c: Array in cands:
			if took >= RECRUIT_STEP or (s.members as Array).size() >= int(s.crowd) or total >= MAX_WATCHERS:
				break
			if join(c[1], s, false):
				took += 1
				total += 1


## Free to come and look: free for crowd life, or only standing about (a phone, a window).
static func _free(p: Pedestrian) -> bool:
	if not p.watch.is_empty() or p._dog_walker:
		return false
	if p._life_free():
		return true
	return p._life_ok and p._life_near and not p._down and p._panic_left <= 0.0 and p.errand.is_empty() \
		and p._cross == Pedestrian.Cross.NONE and not p._jogger \
		and (p._act == CrowdLife.Act.STAND or p._act == CrowdLife.Act.WINDOW)


## Sends `p` to a spot round scene `s` with a role. `at_once` puts them there already watching
## (stills, tests). False when its pavement has no spot at the scene's distance.
func join(p: Pedestrian, s: Dictionary, at_once: bool) -> bool:
	var parent := p.get_parent() as Node3D
	if parent == null or p._visual == null:
		return false
	var at := scene_point(s)
	var local := parent.to_local(at)
	var c := Vector2(local.x, local.z)
	var spot := _pick_spot(p, s, c)
	if spot == Vector2.INF:
		return false
	if p._act != CrowdLife.Act.NONE:
		p._end_act(true)
	var h := hash([int(s.seed), p._life_seed, "role"])
	var role := Role.GAWK
	if int(s.callers) < int(s.callers_want) and (p._carry != CrowdLife.Carry.BAG):
		role = Role.CALL
		s.callers = int(s.callers) + 1
	else:
		var r := _h01(h, 0)
		if r < FILM_SHARE:
			role = Role.FILM
		elif r < FILM_SHARE + POINT_SHARE:
			role = Role.POINT
		elif r < FILM_SHARE + POINT_SHARE + COVER_SHARE:
			role = Role.COVER
		if role == Role.FILM and p._carry == CrowdLife.Carry.BAG:
			role = Role.GAWK
	# The free hand: the right, unless it holds the bag.
	var hand := "Left" if p._carry == CrowdLife.Carry.BAG else "Right"
	var two := role == Role.FILM and p._carry != CrowdLife.Carry.CUP and p._carry != CrowdLife.Carry.SMOKE \
		and _h01(h, 1) < 0.55
	(s.spots as Array).append(spot)
	(s.members as Array).append(p)
	recruited += 1
	var to := c - spot
	p.watch = {
		"scene": s, "spot": spot, "role": role, "hand": hand, "two": two, "seed": h,
		"face": atan2(-to.x, -to.y), "w": 0.0, "want": 0.0, "beat": 0.0, "leave_ms": -1,
		"base": CrowdLife.FOLD if _h01(h, 2) < 0.45 and role == Role.GAWK else CrowdLife.IDLE,
		"until": -1, "one_left": 0.0,
	}
	if role == Role.CALL:
		p.watch.until = _now() + int(1000.0 * lerpf(CALL_SECONDS.x, CALL_SECONDS.y, _h01(h, 3)))
	p._act = CrowdLife.Act.WATCH
	p._pause_left = 0.0
	p._pause_next = 0.0
	p._act_face = float(p.watch.face)
	p._act_spot = spot
	p._life_look = at + Vector3.UP * (0.3 if s.kind == Kind.BODY else 0.9)
	if at_once:
		p._place_at(spot, p._act_face)
		p._stage = Pedestrian.Stage.DOING
		_begin(p)
	else:
		p._stage = Pedestrian.Stage.GOING
		p._go_to(spot)
	if debug:
		print("ONLOOKERS %s joins scene %d as %s at %s (%.1f m)" % [p.name, int(s.id), Role.keys()[role], spot, spot.distance_to(c)])
	return true


## The spot on `p`'s pavement ring (its parent's space) nearest the scene's band, clear of the
## others already there, preferring one near where they stand. INF when none is within reach.
func _pick_spot(p: Pedestrian, s: Dictionary, c: Vector2) -> Vector2:
	var band := _band(s)
	var ring := p.ring
	if ring.size.x < 4.0 or ring.size.y < 4.0:
		return Vector2.INF
	var here := Vector2(p.position.x, p.position.z)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([int(s.seed), p._life_seed, "spot"])
	var best := Vector2.INF
	var best_score := INF
	var walk := maxf(p._sidewalk, 2.0)
	for i in 28:
		var inset := rng.randf_range(0.8, maxf(walk - 0.8, 1.0))
		var q: Vector2
		match i % 4:
			0:
				q = Vector2(rng.randf_range(ring.position.x + 1.0, ring.end.x - 1.0), ring.position.y + inset)
			1:
				q = Vector2(rng.randf_range(ring.position.x + 1.0, ring.end.x - 1.0), ring.end.y - inset)
			2:
				q = Vector2(ring.position.x + inset, rng.randf_range(ring.position.y + 1.0, ring.end.y - 1.0))
			_:
				q = Vector2(ring.end.x - inset, rng.randf_range(ring.position.y + 1.0, ring.end.y - 1.0))
		var d := q.distance_to(c)
		# Never closer than the band (the heat, the body); farther is only worse.
		if d < band.x - 0.4:
			continue
		var off := maxf(band.x - d, 0.0) * 4.0 + maxf(d - band.y, 0.0)
		if off > 9.0:
			continue
		var score := off + q.distance_to(here) * 0.03
		for o: Vector2 in s.spots:
			var g := q.distance_to(o)
			if g < SPACING:
				score += 20.0
			elif g < SPACING * 2.0:
				score += (SPACING * 2.0 - g) * 1.5
		if score < best_score:
			best_score = score
			best = q
	return best if best_score < 20.0 else Vector2.INF


# --- One onlooker ------------------------------------------------------------------------------

## Pedestrian._walk: true when the onlooker's stop has the tick (arrived and watching). On the
## way there the ordinary walk takes them round the ring; a fright drops it all.
static func walk(p: Pedestrian, delta: float, panicking: bool) -> bool:
	if p.watch.is_empty():
		return false
	var s: Dictionary = p.watch.scene
	if p._act != CrowdLife.Act.WATCH:
		release(p)
		return false
	if panicking or not p._life_near:
		p._end_act(true)
		return false
	var leave_ms := int(p.watch.leave_ms)
	if leave_ms >= 0 and _now() >= leave_ms:
		leave(p)
		return false
	if p._stage == Pedestrian.Stage.GOING:
		return false
	if p._speed > 0.02:
		p._speed = move_toward(p._speed, 0.0, p.stop_decel * delta)
		p._move(Vector2(-sin(p._visual.rotation.y), -cos(p._visual.rotation.y)) * p._speed, delta)
		return true
	p._speed = 0.0
	p.velocity.x = 0.0
	p.velocity.z = 0.0
	if not p._kinematic and not p.is_on_floor():
		p.velocity.y -= 30.0 * delta
		p.move_and_slide()
	var node := find()
	var at: Vector3 = node.scene_point(s) if node else WorldState.to_local(s.world)
	p._life_look = at + Vector3.UP * (0.3 if s.kind == Kind.BODY else 0.9)
	if p._stage == Pedestrian.Stage.SETTLE:
		var parent := p.get_parent() as Node3D
		var local := parent.to_local(at) if parent else at
		var to := Vector2(local.x, local.z) - Vector2(p.position.x, p.position.z)
		var face := atan2(-to.x, -to.y)
		p._turn_on_spot(face, delta)
		if absf(angle_difference(p._visual.rotation.y, face)) < 0.12:
			p._pivoting = false
			p._stage = Pedestrian.Stage.DOING
			_begin(p)
		return true
	_beat(p, delta)
	return true


## Arrived: start the role.
static func _begin(p: Pedestrian) -> void:
	var role: int = p.watch.role
	p.watch.beat = _h01(int(p.watch.seed), 4) * 3.0 + 1.0
	match role:
		Role.CALL:
			p._life_base = CrowdLife.PHONE
			p.watch.want = 0.0
		Role.FILM:
			p._life_base = CrowdLife.IDLE
			p.watch.want = 1.0
		Role.POINT:
			p._life_base = CrowdLife.TALK
			p.watch.want = 1.0
		Role.COVER:
			p._life_base = CrowdLife.IDLE
			p.watch.want = 1.0
		_:
			p._life_base = String(p.watch.base)
			p.watch.want = 0.0
	p._life_clip = p._life_base


## The beats of a role: the call ends, the phone goes up and down, the arm points again, the
## hand goes back to the mouth, a shake of the head, a nod to the neighbour.
static func _beat(p: Pedestrian, delta: float) -> void:
	var w: Dictionary = p.watch
	if float(w.one_left) > 0.0:
		w.one_left = float(w.one_left) - delta
		if float(w.one_left) <= 0.0:
			p._life_clip = p._life_base
	if int(w.until) >= 0 and _now() > int(w.until) and int(w.role) == Role.CALL:
		# Off the phone: now they film it too, or just stare.
		w.role = Role.FILM if _h01(int(w.seed), 5) < 0.5 else Role.GAWK
		w.until = -1
		_begin(p)
		return
	w.beat = float(w.beat) - delta
	if float(w.beat) > 0.0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([int(w.seed), _now() / 997])
	match int(w.role):
		Role.FILM:
			# Mostly filming; now and then the phone comes down to look at it, then up again.
			if float(w.want) > 0.5 and rng.randf() < 0.3:
				w.want = 0.35
				w.beat = rng.randf_range(2.0, 4.0)
			else:
				w.want = 1.0
				w.beat = rng.randf_range(8.0, 18.0)
		Role.POINT:
			if float(w.want) > 0.5:
				w.want = 0.0
				p._life_base = CrowdLife.IDLE if rng.randf() < 0.5 else CrowdLife.FOLD
				p._life_clip = p._life_base
				w.beat = rng.randf_range(5.0, 11.0)
			else:
				w.want = 1.0
				p._life_base = CrowdLife.TALK
				p._life_clip = p._life_base
				w.beat = rng.randf_range(2.5, 4.5)
		Role.COVER:
			if float(w.want) > 0.5:
				w.want = 0.0
				w.beat = rng.randf_range(3.0, 8.0)
				if rng.randf() < 0.4:
					_one_shot(p, CrowdLife.SHAKE)
			else:
				w.want = 1.0
				w.beat = rng.randf_range(2.5, 6.0)
		Role.CALL:
			w.beat = rng.randf_range(4.0, 9.0)
		_:
			w.beat = rng.randf_range(4.0, 10.0)
			var r := rng.randf()
			if r < 0.3:
				_one_shot(p, CrowdLife.SHAKE)
			elif r < 0.5:
				_one_shot(p, CrowdLife.NOD)


static func _one_shot(p: Pedestrian, clip: String) -> void:
	if p._anim == null or not p._anim.has_animation(clip):
		return
	p._life_clip = clip
	p.watch.one_left = p._anim.get_animation(clip).length - 0.15


## Back to walking, away from the scene (the scene closing, or the player gone).
static func leave(p: Pedestrian) -> void:
	if p.watch.is_empty():
		return
	var s: Dictionary = p.watch.scene
	var spot: Vector2 = p.watch.spot
	p._end_act(true)
	# Somewhere along the pavement away from it.
	var away := p._random_ring_point(p._sidewalk)
	for i in 4:
		var q := p._random_ring_point(p._sidewalk)
		if q.distance_squared_to(spot) > away.distance_squared_to(spot):
			away = q
	if p._panic_left <= 0.0:
		p._go_to(away)
	if debug:
		print("ONLOOKERS %s leaves scene %d" % [p.name, int(s.id)])


## Pedestrian._end_act (and so _exit_tree, a fright, out of range): nothing of theirs stays.
static func release(p: Pedestrian) -> void:
	if p.watch.is_empty():
		return
	var s: Dictionary = p.watch.scene
	(s.members as Array).erase(p)
	(s.spots as Array).erase(p.watch.spot)
	if int(p.watch.role) == Role.CALL and int(s.callers) > 0 and not s.closing:
		s.callers = int(s.callers) - 1
	p.watch = {}
	if p.has_meta("onlooker_phone"):
		var ph: Node3D = p.get_meta("onlooker_phone")
		if is_instance_valid(ph):
			ph.visible = false


# --- The pose ----------------------------------------------------------------------------------

## Pedestrian._physics_process, after the clip and crowd life have posed the rig: the arms for
## the role (the phone held up, the arm pointed, the hand at the mouth), and the phone shown.
static func pose(p: Pedestrian, delta: float) -> void:
	var sk := p._head_skel
	if sk == null or p.watch.is_empty():
		return
	var w: Dictionary = p.watch
	var role: int = w.role
	var doing := p._stage == Pedestrian.Stage.DOING and p._speed < 0.05
	var want := float(w.want) if doing and float(w.one_left) <= 0.0 else 0.0
	w.w = move_toward(float(w.w), want, delta * (2.2 if want > float(w.w) else 3.0))
	var weight := smoothstep(0.0, 1.0, float(w.w))
	# The phone: the caller's own (the carry phone on the ear), the filmer's in the free hand.
	var carry_phone: Node3D = p._props.get(CrowdLife.Prop.PHONE)
	if role == Role.CALL and doing:
		if carry_phone == null:
			carry_phone = p._hold(CrowdLife.Prop.PHONE)
			p._props[CrowdLife.Prop.PHONE] = carry_phone
		carry_phone.visible = true
	elif carry_phone != null and role == Role.FILM:
		carry_phone.visible = false
	var film := role == Role.FILM and doing
	var film_phone := _film_phone(p, String(w.hand), film)
	if film_phone != null:
		film_phone.visible = film and float(w.w) > 0.15
	if weight <= 0.001:
		return
	var head_b := sk.find_bone("Head")
	if head_b < 0:
		return
	var unit := p._skel_unit
	var head := sk.get_bone_global_pose(head_b).origin
	# The body's own frame in skeleton space, from the world: the rigs' skeleton +Z is not the way
	# they face on every rig (measured 45 degrees off on some), so nothing assumes it.
	var to_sk := sk.global_basis.inverse()
	var yaw := p._visual.global_rotation.y
	var up := (to_sk * Vector3.UP).normalized()
	var fwd := (to_sk * Vector3(-sin(yaw), 0.0, -cos(yaw))).normalized()
	var left := (to_sk * Vector3(-cos(yaw), 0.0, sin(yaw))).normalized()
	# The scene in skeleton space.
	var node := find()
	var s: Dictionary = w.scene
	var at: Vector3 = node.scene_point(s) if node else WorldState.to_local(s.world)
	var target_sk := sk.global_transform.affine_inverse() * (at + Vector3.UP * (0.25 if s.kind == Kind.BODY else 0.8))
	var eye := head + up * 0.07 * unit + fwd * 0.08 * unit
	var to := (target_sk - eye)
	to.y = clampf(to.normalized().y, -0.55, 0.2) * Vector3(to.x, 0.0, to.z).length()
	var dir := to.normalized() if to.length() > 0.01 else fwd
	if dir.dot(fwd) < 0.4:
		dir = (dir + fwd).normalized()
	var side := String(w.hand)
	var sgn := -1.0 if side == "Right" else 1.0 # +X is the rig's left
	match role:
		Role.FILM:
			# Held out in front of the face along the line to the scene, a little to the hand's
			# side, the palm (and the screen) toward the face, the fingers up.
			# Fingers up (tilted with the view), the palm and the screen toward the face.
			var gz := -dir
			var gy := (up - gz * up.dot(gz)).normalized()
			var phone_at := eye + dir * 0.33 * unit + left * sgn * (0.02 if bool(w.two) else 0.07) * unit - up * 0.03 * unit
			# The hand bone is the wrist: the phone's middle is 7.5 cm along the fingers from it.
			var wrist := phone_at - gy * 0.075 * unit - gz * 0.022 * unit
			_arm(sk, side, wrist, up * -1.0 + left * sgn * 0.35 - fwd * 0.1, _hand_for(side, gy, gz), weight)
			if bool(w.two):
				var other := "Left" if side == "Right" else "Right"
				var owrist := phone_at - left * sgn * 0.075 * unit - gy * 0.07 * unit - gz * 0.03 * unit
				_arm(sk, other, owrist, up * -1.0 - left * sgn * 0.35 - fwd * 0.1, _hand_for(other, gy, gz), weight)
		Role.POINT:
			var shoulder := sk.get_bone_global_pose(sk.find_bone(side + "Arm")).origin
			var pd := (dir + up * 0.12).normalized()
			var reach := _arm_length(sk, side) * 0.93
			var hb := _along(sk, side + "Hand", pd)
			_arm(sk, side, shoulder + pd * reach, up * -1.0 + left * sgn * 0.5, hb, weight)
		Role.COVER:
			# The palm over the mouth, the fingers up and in.
			var mouth := head + fwd * 0.12 * unit - up * 0.035 * unit
			var y := (up + left * -sgn * 0.45).normalized()
			var wrist2 := mouth - y * 0.075 * unit + fwd * 0.035 * unit
			_arm(sk, side, wrist2, up * -1.0 + left * sgn * 0.6 - fwd * 0.2, _hand_for(side, y, -fwd), weight)


## The hand bone's skeleton-space basis that puts its grip frame (CrowdLife.grip_basis: y along
## the fingers, z out of the palm) along `y` and `z`. The grip frame is mirrored on one hand (its
## x follows the thumb), so x is taken with the grip's own handedness and the result stays a
## rotation.
static func _hand_for(side: String, y: Vector3, z: Vector3) -> Basis:
	var grip := CrowdLife.grip_basis(side + "Hand")
	var yy := y.normalized()
	var zz := (z - yy * z.dot(yy)).normalized()
	var x := yy.cross(zz)
	if grip.determinant() < 0.0:
		x = -x
	return Basis(x, yy, zz) * grip.inverse()


## The hand bone turned the least it takes to run its fingers (+Y) along `d`.
static func _along(sk: Skeleton3D, bone: String, d: Vector3) -> Basis:
	var b := sk.find_bone(bone)
	var g := sk.get_bone_global_pose(b).basis.orthonormalized()
	return Basis(Quaternion(g.y.normalized(), d.normalized())) * g


static func _arm_length(sk: Skeleton3D, side: String) -> float:
	var a := sk.get_bone_global_pose(sk.find_bone(side + "Arm")).origin
	var k := sk.get_bone_global_pose(sk.find_bone(side + "ForeArm")).origin
	var f := sk.get_bone_global_pose(sk.find_bone(side + "Hand")).origin
	return a.distance_to(k) + k.distance_to(f)


## A two-bone arm solve in skeleton space: the wrist to `target`, the elbow toward `pole`, the
## hand to `hand_basis`, all blended in by `weight` over what the clip had.
static func _arm(sk: Skeleton3D, side: String, target: Vector3, pole: Vector3, hand_basis: Basis, weight: float) -> void:
	var ub := sk.find_bone(side + "Arm")
	var fb := sk.find_bone(side + "ForeArm")
	var hb := sk.find_bone(side + "Hand")
	if ub < 0 or fb < 0 or hb < 0:
		return
	var old := [sk.get_bone_pose_rotation(ub), sk.get_bone_pose_rotation(fb), sk.get_bone_pose_rotation(hb)]
	var a := sk.get_bone_global_pose(ub)
	var k := sk.get_bone_global_pose(fb)
	var f := sk.get_bone_global_pose(hb)
	var l1 := a.origin.distance_to(k.origin)
	var l2 := k.origin.distance_to(f.origin)
	if l1 < 1e-4 or l2 < 1e-4:
		return
	var to := target - a.origin
	var d := clampf(to.length(), absf(l1 - l2) + 0.01 * l1, (l1 + l2) * 0.999)
	var dir := to.normalized()
	var pv := pole - dir * pole.dot(dir)
	if pv.length_squared() < 1e-6:
		pv = Vector3.DOWN - dir * Vector3.DOWN.dot(dir)
	pv = pv.normalized()
	var cos_a := clampf((l1 * l1 + d * d - l2 * l2) / (2.0 * l1 * d), -1.0, 1.0)
	var k_new := a.origin + (dir * cos_a + pv * sqrt(1.0 - cos_a * cos_a)) * l1
	_set_global_rot(sk, ub, Basis(Quaternion((k.origin - a.origin).normalized(), (k_new - a.origin).normalized())) * a.basis)
	var k2 := sk.get_bone_global_pose(fb)
	var f2 := sk.get_bone_global_pose(hb)
	_set_global_rot(sk, fb, Basis(Quaternion((f2.origin - k2.origin).normalized(), (a.origin + dir * d - k2.origin).normalized())) * k2.basis)
	_set_global_rot(sk, hb, hand_basis)
	if weight < 0.999:
		var bones := [ub, fb, hb]
		for i in 3:
			var q: Quaternion = old[i]
			sk.set_bone_pose_rotation(bones[i], q.slerp(sk.get_bone_pose_rotation(bones[i]), weight))


static func _set_global_rot(sk: Skeleton3D, bone: int, global_basis: Basis) -> void:
	var parent := sk.get_bone_parent(bone)
	var pb := sk.get_bone_global_pose(parent).basis if parent >= 0 else Basis.IDENTITY
	sk.set_bone_pose_rotation(bone, (pb.orthonormalized().inverse() * global_basis.orthonormalized()).get_rotation_quaternion())


## The filmer's phone in `hand` (built once per person, hidden while not filming): the phone of
## CrowdLife's carry with a brighter screen (the camera's picture) and, on the back, the lens and
## a video light that is lit after dark (crowd_prop.gdshader's glow 3).
static func _film_phone(p: Pedestrian, hand: String, want: bool) -> Node3D:
	if p.has_meta("onlooker_phone"):
		var n: Node3D = p.get_meta("onlooker_phone")
		if is_instance_valid(n) and String(n.get_meta("hand", "")) == hand + "Hand":
			return n
		if is_instance_valid(n):
			n.queue_free()
		p.remove_meta("onlooker_phone")
	if not want:
		return null
	var att := BoneAttachment3D.new()
	p._head_skel.add_child(att)
	att.bone_name = hand + "Hand"
	att.set_meta("hand", hand + "Hand")
	var mi := MeshInstance3D.new()
	mi.mesh = film_phone_mesh()
	mi.material_override = CrowdLife.prop_material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	mi.visibility_range_end = p.life_range
	mi.transform = Transform3D(CrowdLife.grip_basis(hand + "Hand") * Basis.from_scale(Vector3.ONE * p._skel_unit), Vector3.ZERO)
	att.add_child(mi)
	p.set_meta("onlooker_phone", att)
	return att


## A 7 x 15 cm phone in the grip frame (CrowdLife.prop_mesh's conventions): the case, the screen
## facing out of the palm showing the camera's picture, and on the back (toward the scene) the
## camera bump with its lens and the video light.
static func film_phone_mesh() -> Mesh:
	if _phone != null:
		return _phone
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	CrowdLife._box(st, Vector3(0.0, 0.075, 0.022), Vector3(0.072, 0.15, 0.008), Color(0.08, 0.08, 0.09), 0.0)
	# The picture on the screen: a bright, washed street (the camera app) - the screen is what
	# a filmer's face is lit by, and what reads from behind them.
	CrowdLife._box(st, Vector3(0.0, 0.075, 0.0265), Vector3(0.065, 0.138, 0.0012), Color(0.62, 0.66, 0.7), 1.0)
	# The camera bump on the back, toward the scene (-z of the grip is into the palm's side).
	CrowdLife._box(st, Vector3(-0.018, 0.128, 0.0165), Vector3(0.028, 0.03, 0.0035), Color(0.14, 0.14, 0.15), 0.0)
	CrowdLife._box(st, Vector3(-0.024, 0.132, 0.0144), Vector3(0.009, 0.009, 0.0012), Color(0.02, 0.02, 0.03), 0.0)
	CrowdLife._box(st, Vector3(-0.008, 0.124, 0.0144), Vector3(0.009, 0.009, 0.0012), Color(1.0, 0.97, 0.9), 3.0)
	st.generate_normals()
	_phone = st.commit()
	return _phone


static func _h01(h: int, k: int) -> float:
	return float(hash([h, k]) & 0xffffff) / float(0x1000000)


# --- Staging (stills and tests) ----------------------------------------------------------------

## Opens a scene at `world` (true world) at once, quiet already, and puts up to `count` of the
## walkers within RECRUIT_REACH straight into their places. Returns the scene.
func stage(kind: int, world: Vector3, ref: Object, count: int) -> Dictionary:
	_player = get_tree().get_first_node_in_group("player") as Node3D
	var s := open_scene(kind, world, ref)
	s.born_ms = _now() - int(SETTLE * 1000.0) - 1
	s.quiet_ms = _now()
	s.crowd = maxi(int(s.crowd), count)
	Pedestrian._last_alarm_ms = -100000
	var at := scene_point(s)
	var cands: Array = []
	for n in get_tree().get_nodes_in_group("pedestrian"):
		var p := n as Pedestrian
		if p != null and p.is_inside_tree() and p._lives() and p.watch.is_empty() and p._life_ok and not p._down:
			var d2 := p.global_position.distance_squared_to(at)
			if d2 < RECRUIT_REACH * RECRUIT_REACH:
				cands.append([d2, p])
	cands.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for c: Array in cands:
		if (s.members as Array).size() >= count:
			break
		var p: Pedestrian = c[1]
		p._panic_left = 0.0
		p._scream_in = -1.0
		if p._act != CrowdLife.Act.NONE:
			p._end_act(true)
		if not p.errand.is_empty():
			StreetErrands.release(p)
		if p._cross != Pedestrian.Cross.NONE:
			continue
		join(p, s, true)
	return s
