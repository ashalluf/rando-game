class_name CrowdFlow
extends RefCounted
## The crowd's flow (fleet wave 4, "pedestrian-flow"; docs/HANDOFF.md "The crowd's flow"): how the
## ring walkers (Pedestrian) move among each other near the camera.
## - Local avoidance: every walker within `RANGE` of the camera that ticks every physics frame
##   writes itself into a coarse grid (note(), from Pedestrian._physics_process); the next frame
##   each one steering a leg asks step() - a cheap reciprocal velocity step over the neighbours in
##   the grid: the time and point of closest approach to each, a sidestep to whichever side that
##   point is not on (both take half, so two walkers meeting head on pass right shoulder to right
##   shoulder - keep right - instead of stopping dead), falling in behind somebody slower going the
##   same way, and slowing where the pavement is crowded. Standing people are obstacles too.
## - Props: a knee-high ray ahead every `PROBE_EVERY` (near walkers, world + props layers) turns a
##   walker off a bin, a news box or a shelter for a moment, toward the side that is open, before
##   Pedestrian's stuck rule (0.8 s walked flat into something) has to give the leg up.
## - Groups: of the walkers a FULL chunk spawns (spawned(), one hook in CityChunk._spawn_walker),
##   `GROUP_SHARE` join a walker spawned just before them on the same ring: two, now and then
##   three, sharing a leader. The follower walks a slot beside the leader (follow(), one hook in
##   Pedestrian._walk), matching its pace and catching up when it lags, stands with it when it
##   stops (facing it: they talk), and goes to the kerb and over the road with it.
## - Kerbs: walkers waiting to cross take SLOTS along the kerb and a row back (kerb_slot(), one
##   hook in Pedestrian.plan_crossing), so a red light gathers a bunch rather than a stack on one
##   spot; a walker ending a leg near a crosswalk where people already wait joins them
##   (join_bunch()); when the walking figure comes up they step off one after another
##   (`REACT`, front row first), and at a stop sign - or a car turning at a signal - they wait for
##   the car coming to pass (may_go()).
## - Doors: now and then a walker comes OUT of a shop door near the player (door_tick(): somebody
##   already inside a shop, else one borrowed from out of sight, StreetErrands' pool and rules), and
##   a walker passing a door on its own pavement sometimes turns in (StreetErrands' shop visit).
## Every roll is a walker's own stream (hash of its seed and "flow") or the flow's own; all timing
## is the physics clock (Pedestrian._life_now_ms()). Nothing a seed builds moves.

## The whole layer on or off (CROWD_FLOW=0 in the environment: the A/B).
static var enabled: bool = OS.get_environment("CROWD_FLOW") != "0"

## Avoidance runs within this of the camera (metres): Pedestrian.physics_range, where every walker
## ticks every physics frame and moves through move_and_slide.
const RANGE := 35.0
## The grid's cell (metres) and how far a walker looks for others.
const CELL := 4.0
const LOOK := 3.4
## A walker's radius for passing (metres) and the clearance kept on top of two of them.
const RADIUS := 0.3
const CLEARANCE := 0.16
## How far ahead in time a meeting is planned for (seconds).
const HORIZON := 2.4
## How hard a sidestep pushes (a unit of the walker's heading), and the most it pushes.
const PUSH_GAIN := 1.6
const MAX_PUSH := 1.1
## A crowded pavement: each other walker within DENSITY_REACH takes this share off the pace,
## down to DENSITY_MIN of it.
const DENSITY_REACH := 2.0
const DENSITY_SLOW := 0.09
const DENSITY_MIN := 0.6
## The prop probe: every this many seconds, this long, at knee height; a dodge lasts this long and
## turns the heading this far.
const PROBE_EVERY := 0.3
const PROBE_LEN := 1.9
const PROBE_HEIGHT := 0.55
const DODGE_SECONDS := 0.9
const DODGE_TURN := 0.8
## Groups: the share of a chunk's walkers who join one spawned before them, the share of leaders
## who take a second follower, and how far beside the leader a follower walks (metres).
const GROUP_SHARE := 0.34
const TRIO_SHARE := 0.3
const PAIR_GAP := 0.72
## A follower this far off its slot walks faster to catch up (metres), and gives up past LOSE.
const CATCH_UP := 3.0
const LOSE := 40.0
## How quickly a follower takes up the leader's heading (per second).
const HEADING_RATE := 3.0
## Kerb slots: along the kerb from the crossing's line (metres, + away from the junction: the
## line is 1.8 m from its corner), rows of this many, the next row this far back from the road.
const SLOT_LAT := [0.0, 0.72, 1.44, -0.45, 2.16, 2.88]
const ROW := 6
const ROW_BACK := 0.8
## Stepping off when the walking figure comes up: the first row within REACT.x..REACT.y seconds,
## each row after a little later.
const REACT := Vector2(0.15, 0.9)
const REACT_ROW := 0.45
## A car coming: on the crossed road within this far (metres) and this many seconds of the
## crosswalk; at a signal only a car this close (a turn); no walker waits longer than these.
const CAR_REACH := 32.0
const CAR_SECONDS := 4.5
const SIGNAL_CAR_REACH := 12.0
const HOLD_MAX := 12.0
const SIGNAL_HOLD_MAX := 3.0
## Joining a bunch already waiting: within this of its kerb (metres), this share of the time.
const BUNCH_REACH := 22.0
const BUNCH_SHARE := 0.55
## Doors: a walker comes out of a shop near the player every so often (seconds), from a door this
## near / far from them (metres); a walker passing within PASS_REACH of a door on its pavement
## turns in PASS_SHARE of the time (one look a second).
const DOOR_INTERVAL := Vector2(4.0, 10.0)
const DOOR_RANGE := Vector2(8.0, 42.0)
const DOOR_WAIT := Vector2(0.3, 2.5)
const PASS_REACH := 2.4
const PASS_SHARE := 0.07

## The grid: last frame's walkers (read) and this frame's (written), cell -> [[pedestrian,
## position, velocity, group], ...] in scene space.
static var _prev: Dictionary = {}
static var _cur: Dictionary = {}
static var _frame: int = -1
static var _cam := Vector3.INF
## The walkers spawned last on each ring (parent id + ring -> [WeakRef, ...]): who a new one joins.
static var _recent: Dictionary = {}
## The walkers waiting at each crosswalk (Vector4i key -> [WeakRef, ...]).
static var _waiting: Dictionary = {}
static var _next_door_ms: int = 0
static var _rng := RandomNumberGenerator.new()
## The last walker door_tick() sent out of a shop (the checks follow them).
static var last_out: WeakRef
## Counters for the checks and the probe.
static var stats := {"dodges": 0, "probes": 0, "joined": 0, "doors_out": 0, "doors_in": 0, "held": 0}


# --- Hooks -------------------------------------------------------------------------------------

## Pedestrian._physics_process, every tick a walker runs (after its LOD stride): it goes into this
## frame's grid when it is near the camera, seen and standing on the pavement.
static func note(p: Pedestrian) -> void:
	if not enabled:
		return
	_swap(p)
	if p._down or not p.visible or p.collision_layer == 0 or p._lod_stride > 1 or _cam == Vector3.INF:
		return
	var g := p.global_position
	if g.distance_squared_to(_cam) > RANGE * RANGE:
		return
	var key := Vector2i(floori(g.x / CELL), floori(g.z / CELL))
	var arr: Array = _cur.get(key, [])
	if arr.is_empty():
		_cur[key] = arr
	arr.append([p, Vector2(g.x, g.z), Vector2(p.velocity.x, p.velocity.z), int(p.flow.get("gid", 0))])
	door_tick(p)


## CityChunk._spawn_walker: a walker the chunk just made. Some join the one made before them on the
## same ring and are placed at their side at once (the chunk is still being built, unseen).
static func spawned(chunk: Node, p: Pedestrian) -> void:
	if not enabled or not _groupable(p):
		return
	var rng := _rng_of(p)
	var key := hash([chunk.get_instance_id(), p.ring.position, p.ring.size])
	if _recent.size() > 600:
		_recent.clear()
	var recent: Array = _recent.get(key, [])
	if recent.is_empty():
		_recent[key] = recent
	if rng.randf() < GROUP_SHARE:
		for i in range(recent.size() - 1, -1, -1):
			var l := (recent[i] as WeakRef).get_ref() as Pedestrian
			if l != null and _can_lead(l):
				join(p, l, true)
				break
	if not p.flow.has("leader"):
		recent.append(weakref(p))
		if recent.size() > 4:
			recent.remove_at(0)


## Pedestrian._walk, before its own walking: a follower walks with its leader. True when this tick
## was the group's (the walker's own walking is skipped); false when the walker's own code runs
## (no group, an act, a crossing of the leader's that the follower is now on).
static func follow(p: Pedestrian, delta: float, panicking: bool) -> bool:
	if not enabled:
		return false
	var wr: Variant = p.flow.get("leader")
	if wr == null:
		return false
	var l := (wr as WeakRef).get_ref() as Pedestrian
	if panicking or l == null or not is_instance_valid(l) or not l.is_inside_tree() or l._down or not l.visible \
			or l.collision_layer == 0 or not l.errand.is_empty() or not p.errand.is_empty() or l._panic_left > 0.0 \
			or l._jogger:
		leave(p)
		return false
	if p._act != CrowdLife.Act.NONE:
		return false
	var lc := l._cross
	var pc := p._cross
	if lc != Pedestrian.Cross.NONE:
		if pc == Pedestrian.Cross.NONE:
			if l._cross_ring == p.ring or l.ring == p.ring:
				_copy_cross(p, l)
			else:
				leave(p)
			return false
		if p._cross_key != l._cross_key:
			leave(p)
			return false
		if pc == Pedestrian.Cross.WAIT:
			if lc == Pedestrian.Cross.CROSSING:
				# Off the kerb a beat after the leader.
				if not p.flow.has("go_at"):
					p.flow.go_at = _now() + int(1000.0 * _rng_of(p).randf_range(0.1, 0.45))
				if _now() >= int(p.flow.go_at):
					p.flow.erase("go_at")
					p._start_crossing()
					return false
			var across := (p._cross_to - p._cross_from).normalized()
			p.velocity.x = 0.0
			p.velocity.z = 0.0
			p._turn_on_spot(atan2(-across.x, -across.y), delta)
			return true
		return false
	if pc != Pedestrian.Cross.NONE:
		# The leader is over and on: a follower still out in the road carries on over; one still
		# waiting at the kerb crosses on its own light, out of the group.
		if pc == Pedestrian.Cross.CROSSING and l.ring == p._cross_ring:
			return false
		leave(p)
		return false
	if l.ring != p.ring:
		leave(p)
		return false
	var lpos := Vector2(l.position.x, l.position.z)
	var here := Vector2(p.position.x, p.position.z)
	if lpos.distance_to(here) > LOSE:
		leave(p)
		return false
	# The leader's heading, eased (a leader turning on the spot does not swing the slot round).
	var lyaw: float = l._visual.rotation.y
	var hd: float = float(p.flow.get("hd", lyaw))
	hd = wrapf(hd + angle_difference(hd, lyaw) * minf(HEADING_RATE * delta, 1.0), -PI, PI)
	p.flow.hd = hd
	var slot := band_clamp(slot_point(lpos, hd, int(p.flow.get("slot", 0)), float(p.flow.get("side", 1.0))), p.ring, p._sidewalk)
	var to := slot - here
	var dist := to.length()
	var lspeed: float = l._speed
	var f := Vector2(-sin(hd), -cos(hd))
	if lspeed < 0.15 and dist < 1.3:
		# The leader has stopped (a pause, a window, a talk): stand with them, turned to them.
		var face := lpos - here
		var yaw := atan2(-face.x, -face.y) if face.length() > 0.2 else hd
		p._turn_on_spot(yaw, delta)
		p.velocity.x = 0.0
		p.velocity.z = 0.0
		if not p._kinematic and not p.is_on_floor():
			p.velocity.y -= 30.0 * delta
			p.move_and_slide()
		return true
	var want := lspeed + clampf(to.dot(f) * 0.9, -0.7, 0.9)
	if dist > CATCH_UP:
		want = maxf(want, minf(l.walk_speed * 1.45, 2.3))
	want = clampf(want, 0.0, 2.4)
	var aim := slot + f * clampf(lspeed * 0.7, 0.0, 1.2) - here
	var av := avoid(p, aim, want, false)
	var v := p._steer(Vector2(av.x, av.y), av.z, delta, false)
	p._move(v, delta)
	return true


## Pedestrian._walk and _walk_crossing, just before _steer(): the heading and pace after the
## neighbours, the props and - on the pavement - a door being passed. x, y the way to go (as long
## as `to_goal`), z the pace.
static func avoid(p: Pedestrian, to_goal: Vector2, want: float, panicking: bool) -> Vector3:
	var keep := Vector3(to_goal.x, to_goal.y, want)
	if not enabled or p._lod_stride > 1 or want < 0.05:
		return keep
	var dist := to_goal.length()
	if dist < 1e-3:
		return keep
	_swap(p)
	var g := p.global_position
	if _cam == Vector3.INF or g.distance_squared_to(_cam) > RANGE * RANGE:
		return keep
	var pos := Vector2(g.x, g.z)
	var dir := to_goal / dist
	var res := step(pos, dir, want, _neighbours(pos, p, int(p.flow.get("gid", 0))), panicking)
	dir = Vector2(res.x, res.y)
	dir = _dodge(p, g, dir)
	if not panicking and p._cross == Pedestrian.Cross.NONE:
		_pass_door(p)
	return Vector3(dir.x * dist, dir.y * dist, res.z)


## Pedestrian.plan_crossing, once it has picked the crosswalk: the walker's own place at the kerb
## (a slot along it, or a row back), the crossing line moved over with it.
static func on_plan_crossing(p: Pedestrian, spread: float) -> void:
	if not enabled:
		return
	p.flow.erase("go_at")
	var across := (p._cross_to - p._cross_from).normalized()
	var along := Vector2(absf(across.y), absf(across.x))
	var ends := kerb_slot(p, p._cross_key, p._cross_from - along * spread, p._cross_to - along * spread)
	p._cross_from = ends[0]
	p._cross_to = ends[1]


## Pedestrian._wait_at_kerb, once the light (or a stop sign's patience) says go: whether to step
## off now - after this walker's own beat (the front row first), and not with a car about to pass.
static func may_go(p: Pedestrian) -> bool:
	if not enabled:
		return true
	var now := _now()
	if not p.flow.has("go_at"):
		var row := int(p.flow.get("kerb_slot", 0)) / ROW
		var rng := _rng_of(p)
		p.flow.go_at = now + int(1000.0 * (rng.randf_range(REACT.x, REACT.y) + REACT_ROW * float(row)))
	if now < int(p.flow.go_at):
		return false
	var hold := SIGNAL_HOLD_MAX if p._cross_signal else HOLD_MAX
	if float(p.flow.get("held", 0.0)) < hold and _car_coming(p):
		p.flow.held = float(p.flow.get("held", 0.0)) + 1.0 / float(Engine.physics_ticks_per_second) * float(maxi(p._lod_stride, 1))
		if not p.flow.get("held_counted", false):
			p.flow.held_counted = true
			stats.held = int(stats.held) + 1
		return false
	p.flow.erase("go_at")
	p.flow.erase("held")
	p.flow.erase("held_counted")
	return true


## Pedestrian._walk, at the end of a leg on the pavement: when people are already waiting at a
## crosswalk off this walker's corner, often join them. True when a crossing was planned.
static func join_bunch(p: Pedestrian) -> bool:
	if not enabled or _waiting.is_empty() or p._jogger or p.flow.get("leader") != null:
		return false
	var here := Vector2(p.position.x, p.position.z)
	var axis := -1
	for key: Vector4i in _waiting.keys():
		var w := _first_waiting(key)
		if w == null or w == p or w.ring != p.ring or w._cross_from.distance_to(here) > BUNCH_REACH:
			continue
		axis = key.z
		break
	if axis < 0 or _rng_of(p).randf() >= BUNCH_SHARE:
		return false
	return p.plan_crossing(axis)


# --- Pure (the checks call these) --------------------------------------------------------------

## One walker's reciprocal step: at `pos` heading `dir` (unit) at pace `want`, with `others`
## ([position, velocity], ...). x, y the new heading (unit), z the new pace.
static func step(pos: Vector2, dir: Vector2, want: float, others: Array, hurry: bool = false) -> Vector3:
	var vdes := dir * want
	var right := Vector2(-dir.y, dir.x)
	var push := 0.0
	var cap := want
	var crowd := 0
	var reach := 2.0 * RADIUS + CLEARANCE
	for o: Array in others:
		var rel: Vector2 = (o[0] as Vector2) - pos
		var d := rel.length()
		if d > LOOK or d < 1e-4:
			continue
		if d < DENSITY_REACH:
			crowd += 1
		var ahead := rel.dot(dir)
		if ahead < -0.25:
			continue # behind: theirs to step round
		var vo: Vector2 = o[1]
		var vr := vdes - vo
		var vr2 := vr.length_squared()
		var t := 0.0
		if vr2 > 1e-4:
			t = clampf(rel.dot(vr) / vr2, 0.0, HORIZON)
		var c := rel - vr * t
		var cd := c.length()
		var lat := rel.dot(right)
		var same := vo.dot(dir)
		# Close ahead, the same way and no quicker: fall in behind rather than climb their back.
		if ahead > 0.0 and d < 1.9 and same > 0.15 and absf(lat) < reach and same < want:
			cap = minf(cap, same + maxf(d - 0.95, 0.0) * 0.9)
		if cd >= reach:
			continue
		var urgency := (1.0 - t / HORIZON) * (1.0 - cd / reach)
		# The side the meeting point is not on; dead ahead, keep right (both do: they pass).
		var cl := c.dot(right)
		var side := -signf(cl) if absf(cl) > 0.05 else 1.0
		# Somebody moving takes half the sidestep themselves; somebody standing takes none.
		var share := 0.55 if vo.length() > 0.3 else 1.0
		push += side * urgency * share * PUSH_GAIN
	push = clampf(push, -MAX_PUSH, MAX_PUSH)
	var nd := (dir + right * push).normalized()
	# A walker stepping out round somebody slow is passing them: they do not slow to their pace.
	var speed := minf(want, maxf(cap, want * minf(absf(push) * 1.4, 1.0)))
	if not hurry and crowd > 1:
		speed *= maxf(DENSITY_MIN, 1.0 / (1.0 + DENSITY_SLOW * float(crowd - 1)))
	return Vector3(nd.x, nd.y, speed)


## Where follower `slot` walks beside a leader at `lpos` heading `yaw`: slot 0 at the leader's
## `side` (+1 right), slot 1 at the other side, a little behind.
static func slot_point(lpos: Vector2, yaw: float, slot: int, side: float) -> Vector2:
	var f := Vector2(-sin(yaw), -cos(yaw))
	var r := Vector2(-f.y, f.x)
	if slot == 0:
		return lpos + r * side * PAIR_GAP - f * 0.05
	return lpos - r * side * PAIR_GAP - f * 0.4


## `at` kept on the pavement band of `ring` (between the kerb and the building line): never out in
## the road, never inside the block.
static func band_clamp(at: Vector2, ring: Rect2, sidewalk: float) -> Vector2:
	var lo := 0.55
	var hi := maxf(sidewalk - 0.45, lo + 0.1)
	var d := [at.y - ring.position.y, ring.end.x - at.x, ring.end.y - at.y, at.x - ring.position.x]
	var e := 0
	for i in 4:
		if float(d[i]) < float(d[e]):
			e = i
	var inset := clampf(float(d[e]), lo, hi)
	match e:
		0:
			at.y = ring.position.y + inset
		1:
			at.x = ring.end.x - inset
		2:
			at.y = ring.end.y - inset
		_:
			at.x = ring.position.x + inset
	return at


## A car at `rel` from a crosswalk's middle moving `vel`, the crossed road running along `along`
## and `half` wide each side of the crossing line (across): whether to let it pass first.
static func car_blocks(rel: Vector2, vel: Vector2, along: Vector2, across: Vector2, half: float, reach: float) -> bool:
	if absf(rel.dot(across)) > half + 1.0:
		return false
	var s := rel.dot(along)
	var vs := vel.dot(along)
	var speed := vel.length()
	if speed < 0.6 or absf(s) > reach:
		return false
	if absf(s) < 3.5:
		return true # on it now
	if s * vs >= 0.0:
		return false # going away
	return absf(s) / maxf(absf(vs), 0.1) < CAR_SECONDS


# --- Groups ------------------------------------------------------------------------------------

## `p` follows `l` (`snap`: put them at their slot now).
static func join(p: Pedestrian, l: Pedestrian, snap: bool) -> void:
	var gid := int(l.flow.get("gid", 0))
	if gid == 0:
		gid = l.get_instance_id()
		l.flow.gid = gid
	var n := int(l.flow.get("followers", 0))
	l.flow.followers = n + 1
	var lrng := _rng_of(l)
	if not l.flow.has("side"):
		l.flow.side = 1.0 if lrng.randf() < 0.5 else -1.0
	p.flow.gid = gid
	p.flow.leader = weakref(l)
	p.flow.slot = n
	p.flow.side = float(l.flow.side)
	p.flow.hd = l._visual.rotation.y if l._visual else 0.0
	# One pace for the group: whoever walks with somebody walks at their speed.
	p.walk_speed = l.walk_speed
	p.flow.own = [p.pause_chance, p.cross_chance]
	p.pause_chance = 0.0
	p.cross_chance = 0.0
	stats.joined = int(stats.joined) + 1
	if snap:
		var lpos := Vector2(l.position.x, l.position.z)
		var at := band_clamp(slot_point(lpos, float(p.flow.hd), n, float(p.flow.side)), p.ring, p._sidewalk)
		p.position = Vector3(at.x, l.position.y, at.y)
		if p._visual:
			p._visual.rotation.y = float(p.flow.hd)
			p._faced = true


## `p` walks on alone (the leader gone, panicking, on an errand or out of reach).
static func leave(p: Pedestrian) -> void:
	var wr: Variant = p.flow.get("leader")
	if wr == null:
		return
	var l := (wr as WeakRef).get_ref() as Pedestrian
	if l != null and is_instance_valid(l):
		l.flow.followers = maxi(int(l.flow.get("followers", 1)) - 1, 0)
	var own: Array = p.flow.get("own", [])
	if own.size() == 2:
		p.pause_chance = float(own[0])
		p.cross_chance = float(own[1])
	p.flow.erase("own")
	p.flow.erase("leader")
	p.flow.erase("gid")
	p.flow.erase("slot")
	p.flow.erase("hd")
	p.flow.erase("go_at")
	if not p._down and p._cross == Pedestrian.Cross.NONE and p.errand.is_empty() and p._act == CrowdLife.Act.NONE:
		p._go_to(p._random_ring_point(p._sidewalk))


## A follower crossing with its leader: the same crosswalk, its own slot at the kerb.
static func _copy_cross(p: Pedestrian, l: Pedestrian) -> void:
	p._end_act(true)
	p._cross_key = l._cross_key
	p._cross_road = l._cross_road
	p._cross_ring = l._cross_ring
	p._cross_signal = l._cross_signal
	p._cross_patience = l._cross_patience
	p._cross_wait = 0.0
	var base: Array = l.flow.get("kerb_base", [l._cross_from, l._cross_to])
	var ends := kerb_slot(p, p._cross_key, base[0], base[1])
	p._cross_from = ends[0]
	p._cross_to = ends[1]
	p._cross = Pedestrian.Cross.TO_KERB
	p._pause_left = 0.0
	p._go_to(p._cross_from)
	if l._cross != Pedestrian.Cross.TO_KERB:
		# The leader is already at the kerb or out in the road: straight over after them.
		p._cross = Pedestrian.Cross.TO_KERB


static func _groupable(p: Pedestrian) -> bool:
	var s: Script = p.get_script()
	return s != null and s.resource_path.ends_with("/pedestrian.gd") and p._life_ok and not p._jogger \
		and not p._dog_walker and p.errand.is_empty()


static func _can_lead(l: Pedestrian) -> bool:
	if not is_instance_valid(l) or l._down or not l.is_inside_tree() or l.flow.get("leader") != null:
		return false
	if not _groupable(l):
		return false
	if not l.flow.has("cap"):
		l.flow.cap = 2 if _rng_of(l).randf() < TRIO_SHARE else 1
	return int(l.flow.get("followers", 0)) < int(l.flow.cap)


# --- Kerbs -------------------------------------------------------------------------------------

## The next free place at the kerb of crosswalk `key` for `p`, from the crossing's base line
## (`from` at the kerb, `to` at the far kerb): [from, to] for this walker.
static func kerb_slot(p: Pedestrian, key: Vector4i, from: Vector2, to: Vector2) -> Array:
	var list: Array = _waiting.get(key, [])
	if list.is_empty():
		_waiting[key] = list
	var used := {}
	for i in range(list.size() - 1, -1, -1):
		var w := (list[i] as WeakRef).get_ref() as Pedestrian
		if w == null or w == p or not _is_waiting(w, key):
			list.remove_at(i)
			continue
		used[int(w.flow.get("kerb_slot", -1))] = true
	var k := 0
	while used.has(k):
		k += 1
	list.append(weakref(p))
	p.flow.kerb_slot = k
	p.flow.kerb_base = [from, to]
	var across := (to - from).normalized()
	var along := Vector2(absf(across.y), absf(across.x))
	var rng := _rng_of(p)
	var row := k / ROW
	var away := 1.0 if (p.ring.get_center() - from).dot(along) >= 0.0 else -1.0
	var lat := away * (float(SLOT_LAT[k % ROW]) + 0.36 * float(row % 2) + rng.randf_range(-0.16, 0.16))
	var back := float(row) * ROW_BACK + rng.randf_range(0.0, 0.18)
	return [from + along * lat - across * back, to + along * lat]


static func _is_waiting(w: Pedestrian, key: Vector4i) -> bool:
	return is_instance_valid(w) and w.is_inside_tree() and not w._down and w._cross_key == key \
		and (w._cross == Pedestrian.Cross.TO_KERB or w._cross == Pedestrian.Cross.WAIT)


## Somebody standing (or on the way) at crosswalk `key`, or null.
static func _first_waiting(key: Vector4i) -> Pedestrian:
	var list: Array = _waiting.get(key, [])
	for i in range(list.size() - 1, -1, -1):
		var w := (list[i] as WeakRef).get_ref() as Pedestrian
		if w == null or not _is_waiting(w, key):
			list.remove_at(i)
			continue
		if w._cross == Pedestrian.Cross.WAIT:
			return w
	if list.is_empty():
		_waiting.erase(key)
	return null


## A moving car about to pass over the crosswalk `p` waits at (Pedestrian._nearby_cars: cars near
## the player, a quarter second's survey).
static func _car_coming(p: Pedestrian) -> bool:
	var parent := p.get_parent() as Node3D
	if parent == null or not p.is_inside_tree():
		return false
	var mid := (p._cross_from + p._cross_to) * 0.5
	var mg := parent.to_global(Vector3(mid.x, p.position.y, mid.y))
	var across := (p._cross_to - p._cross_from).normalized()
	var along := Vector2(-across.y, across.x)
	var reach := SIGNAL_CAR_REACH if p._cross_signal else CAR_REACH
	for car: Array in Pedestrian._nearby_cars(p.get_tree()):
		var at: Vector3 = car[0]
		var vel: Vector3 = car[1]
		if car_blocks(Vector2(at.x - mg.x, at.z - mg.z), Vector2(vel.x, vel.z), along, across, p._cross_road.y, reach):
			return true
	return false


# --- Doors -------------------------------------------------------------------------------------

## Once in a while (from note(), the flow's own clock): somebody comes out of a shop door near the
## player - one already inside a shop (StreetErrands' hidden pool) or one borrowed from out of
## sight - into the "inside" step of a shop visit, so StreetErrands shows them at the door and
## walks them out onto the pavement.
static func door_tick(p: Pedestrian) -> void:
	if not StreetErrands.enabled:
		return
	var now := _now()
	if now < _next_door_ms:
		return
	if _next_door_ms == 0:
		_rng.seed = hash(["crowd_flow", "doors"])
	_next_door_ms = now + int(1000.0 * _rng.randf_range(DOOR_INTERVAL.x, DOOR_INTERVAL.y))
	var player := p._player if is_instance_valid(p._player) else p.get_tree().get_first_node_in_group("player") as Node3D
	var plan := p._city_plan()
	if player == null or plan == null:
		return
	var traffic := StreetErrands._traffic_of(p)
	if traffic != null and traffic.get("staged"):
		return
	var streamer := p.get_parent().get_parent() if p.get_parent() else null
	if streamer == null or not (streamer.get("chunks") is Dictionary):
		return
	var pw := WorldState.to_world(player.global_position)
	var here := Vector2(pw.x, pw.z)
	var ci := plan.chunk_index_at(here)
	var night := DayNight.lamp_now > 0.5
	var picks: Array = []
	var chunks: Dictionary = streamer.get("chunks")
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var c: Variant = chunks.get(ci + Vector2i(dx, dz))
			if not (c is Node) or int((c as Node).get("level")) != CityChunk.Level.FULL:
				continue
			for d: Dictionary in StreetErrands._doors(c):
				var dd := (d.p as Vector2).distance_to(here)
				if dd < DOOR_RANGE.x or dd > DOOR_RANGE.y:
					continue
				if night and not Building.shop_open(int(d.key)):
					continue
				picks.append(d)
	if picks.is_empty():
		return
	var door: Dictionary = picks[_rng.randi() % picks.size()]
	var w := StreetErrands._from_pool(door.p, 160.0)
	if w != null and w.rain != null and w.rain.inside:
		w = null
	if w == null:
		w = _far_walker(p, door.p, player.global_position)
	if w == null:
		return
	if w.flow.get("leader") != null:
		leave(w)
	StreetErrands._hide(w)
	w.ring = door.ring
	var at: Vector2 = door.p
	w.position = Vector3(at.x, w.position.y, at.y)
	w.errand = {"steps": [{"do": "inside", "door": door, "until": now + int(1000.0 * _rng.randf_range(DOOR_WAIT.x, DOOR_WAIT.y))}], "i": 0}
	stats.doors_out = int(stats.doors_out) + 1
	last_out = weakref(w)


## A walker out of sight (past StreetErrands.FAR_TAKE of the player) nearest `at`, to be the one
## who comes out of a door: StreetErrands._from_far's rule, less anyone the rain has sent indoors
## (RainCrowd: their tick stops while inside, so an errand on them would never run).
static func _far_walker(near: Node, at: Vector2, player_at: Vector3) -> Pedestrian:
	var best: Pedestrian = null
	var best_d := 320.0
	for n in near.get_tree().get_nodes_in_group("pedestrian"):
		var w := n as Pedestrian
		if w == null or w._down or not w.visible or not w.errand.is_empty() or not w._lives() \
				or w._cross != Pedestrian.Cross.NONE or w.has_meta("no_trim") or (w.rain != null and w.rain.inside):
			continue
		if w.global_position.distance_to(player_at) < StreetErrands.FAR_TAKE:
			continue
		var d := Vector2(w.position.x, w.position.z).distance_to(at)
		if d < best_d:
			best_d = d
			best = w
	if best:
		best._end_act(true)
		best._leave_crosswalk()
	return best


## A walker passing a shop door on its own pavement: now and then they turn in (StreetErrands'
## shop visit). One look a second per walker.
static func _pass_door(p: Pedestrian) -> void:
	if not StreetErrands.enabled or not (p.get_parent() is CityChunk) or not p._life_free() or p._dog_walker or int(p.flow.get("followers", 0)) > 0 \
			or p.flow.get("leader") != null:
		return
	var now := _now()
	if now < int(p.flow.get("pass_t", 0)):
		return
	p.flow.pass_t = now + 1000
	var here := Vector2(p.position.x, p.position.z)
	var door := StreetErrands._near_door(p, here, PASS_REACH)
	if door.is_empty() or int(p.flow.get("last_door", -1)) == int(door.key):
		return
	p.flow.last_door = int(door.key)
	if _rng_of(p).randf() >= PASS_SHARE:
		return
	if StreetErrands._start_shop(p, door):
		stats.doors_in = int(stats.doors_in) + 1


# --- Shared ------------------------------------------------------------------------------------

## A new physics frame: this frame's grid becomes the one read, and the camera is looked up.
static func _swap(p: Node) -> void:
	var f := Engine.get_physics_frames()
	if f == _frame:
		return
	_frame = f
	_prev = _cur
	_cur = {}
	var cam := p.get_viewport().get_camera_3d() if p.is_inside_tree() else null
	_cam = cam.global_position if cam else Vector3.INF


## The walkers near `pos` in last frame's grid, as [position, velocity], less `p` and its group.
static func _neighbours(pos: Vector2, p: Pedestrian, gid: int) -> Array:
	var out: Array = []
	var cx := floori(pos.x / CELL)
	var cz := floori(pos.y / CELL)
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var arr: Variant = _prev.get(Vector2i(cx + dx, cz + dz))
			if arr == null:
				continue
			for e: Array in arr:
				if e[0] == p or (gid != 0 and int(e[3]) == gid):
					continue
				out.append([e[1], e[2]])
	return out


## The prop probe: a ray ahead at knee height now and then; something solid there turns the walker
## to the open side for a moment.
static func _dodge(p: Pedestrian, g: Vector3, dir: Vector2) -> Vector2:
	if p._kinematic:
		return dir
	var now := _now()
	var until := int(p.flow.get("dodge_until", 0))
	if now >= int(p.flow.get("probe_t", 0)):
		p.flow.probe_t = now + int(1000.0 * PROBE_EVERY) + (p.get_instance_id() % 7) * 9
		stats.probes = int(stats.probes) + 1
		var hit := _probe(p, g, dir, PROBE_LEN)
		if hit < PROBE_LEN:
			var r := Vector2(-dir.y, dir.x)
			var right := _probe(p, g, dir.lerp(r, 0.6).normalized(), PROBE_LEN)
			var left := _probe(p, g, dir.lerp(-r, 0.6).normalized(), PROBE_LEN)
			p.flow.dodge_side = 1.0 if right >= left else -1.0
			p.flow.dodge_until = now + int(1000.0 * DODGE_SECONDS)
			until = int(p.flow.dodge_until)
			stats.dodges = int(stats.dodges) + 1
	if now < until:
		var side := float(p.flow.get("dodge_side", 1.0))
		# The heading turned toward the open side (+1 right: Vector2.rotated turns x toward y,
		# which on the plan is toward the walker's right).
		return dir.rotated(side * DODGE_TURN)
	return dir


## How far ahead along `dir` the first solid thing is (PROBE_LEN: nothing).
static func _probe(p: Pedestrian, g: Vector3, dir: Vector2, length: float) -> float:
	var space := p.get_world_3d().direct_space_state if p.is_inside_tree() else null
	if space == null:
		return length
	var from := g + Vector3.UP * PROBE_HEIGHT
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3(dir.x, 0.0, dir.y) * length, 1 | 4, [p.get_rid()])
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return length
	var n: Vector3 = hit.normal
	if absf(n.y) > 0.6:
		return length # the ground or a ramp, not something in the way
	return from.distance_to(hit.position)


static func _rng_of(p: Pedestrian) -> RandomNumberGenerator:
	var rng: Variant = p.flow.get("rng")
	if rng is RandomNumberGenerator:
		return rng
	var r := RandomNumberGenerator.new()
	r.seed = hash([p._life_seed, "flow"])
	p.flow.rng = r
	return r


static func _now() -> int:
	return Pedestrian._life_now_ms()
