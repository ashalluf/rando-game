class_name BusyStreets
extends RefCounted
## Busy streets (fleet wave 3, "busy-streets"; docs/HANDOFF.md "Busy streets"): the near streets
## dense with moving and queued traffic, parked cars and walkers, by day and evening, thinning late
## at night - by spending the budgets that already exist where the camera looks, not by raising
## them all. Four parts, each a hook of a line or two:
##
## 1. TRAFFIC WHERE THE CAMERA LOOKS. TrafficManager kept its cap of cars spread evenly over a
##    380 m circle round the player and spawned them 60-260 m off along five roads either side:
##    measured at the downtown bookmark, 150 cars live, 26 moving within 150 m, 5-9 in the view.
##    Now `focus_share` of the spawns go onto the roads crossing the camera's own block, `near_min`
##    .. `focus_max` metres off, ahead of the camera rather than behind it (`ahead_share`), and
##    never popping in inside the view cone nearer than `view_pop_min`; and a car more than
##    `rear_reach` off that is out of the view (`rear_cone`) goes back to the pool (`retire_far()`),
##    so the cap is spent in front of the camera. Pooled cars come back free (no build).
## 2. THE HOUR. The street cap follows NightCity.traffic_level() - the far city's traffic by hour,
##    so the near and the far streets agree - through `hour_factor()`: full through the day,
##    busy in the evening, a third of it in the small hours. The crowd follows `crowd_factor()`.
##    `edge_density` (TrafficManager's floor away from downtown) is raised to `EDGE_DENSITY`.
## 3. THE CROWD WHERE THE CAMERA IS. Walkers are spawned once, when a block is built, out of one
##    city-wide cap (650), and nothing ever moved them: arrive in a block late and the cap was
##    spent on blocks built earlier that are still standing. `crowd_tick()` (CityStreamer, once a
##    second) tops up the FULL blocks within `crowd_reach` of the camera toward what they planned
##    (CityChunk records it, `note_crowd()`) times the hour, out of the room under the cap, and
##    when there is none frees the farthest plain walkers past `crowd_far` that are out of view.
##    New walkers appear out of the view or `crowd_pop_min` off. Late at night it also thins a
##    near block over its share, out of view.
## 4. FULLER KERBS. A block parked at most its district's "parked" cars on ~70 kerb spots (and
##    rolled each spot at 55 %): `park_extra()` puts up to `PARK_EXTRA` more of the district's
##    count on the spots the block's own pass left empty, from a hash of seed + spot (never the
##    block rng), with every keep-clear the old pass has - so nothing the seed built moves.
##
## Cost is held by the caps: the same 150 street cars, the same crowd cap; the parked cars are
## sleeping bodies on their far twin past Vehicle.body_far_distance (30 m) and a welded middle /
## far body for walkers past Pedestrian.mid_body_range. BUSY_STREETS=0 is the A/B.
## Probe: tools/busy_streets/census.gd. Checks: tests/busy_streets_checks.gd.

static var enabled: bool = OS.get_environment("BUSY_STREETS") != "0"

## Share of street spawns placed round the camera's own block (the rest keep the old rule).
static var focus_share: float = 0.7
## A focused spawn is this far off the camera along its road, at least...
static var near_min: float = 40.0
## ...and at most (metres).
static var focus_max: float = 190.0
## Share of focused spawns ahead of the camera rather than behind it.
static var ahead_share: float = 0.72
## Inside the view cone a car is never put down nearer than this (it would pop in).
static var view_pop_min: float = 115.0
## Half angle of the view cone (degrees) the spawn and retire rules use.
static var view_cone: float = 50.0
## A street car past this from the camera and outside the view goes back to the pool.
static var rear_reach: float = 230.0
## A road's own cross streets: focused spawns pick index offsets -1..+1 of the camera's block.
const FOCUS_ROADS := 1
## The street cars' floor away from downtown (TrafficManager.edge_density was 0.2).
const EDGE_DENSITY := 0.32

## Near blocks topped up toward their planned walkers (metres from the camera to a block's centre).
static var crowd_reach: float = 170.0
## Plain walkers past this from the camera, out of view, may be freed for the near blocks.
static var crowd_far: float = 210.0
## Walkers added a second at most (each is an instantiated rig; the loading screen warmed them).
static var crowd_per_tick: int = 6
## A topped-up walker appears out of the view, or at least this far off.
static var crowd_pop_min: float = 45.0

## Extra parked cars a block may add on the spots its own pass left empty (fraction of its count).
const PARK_EXTRA := 0.4
## And the share of those empty spots that get one (a hash per spot).
const PARK_EXTRA_ODDS := 0.5


# --- the hour -------------------------------------------------------------------------------

## 0..1 of the street cap at `hour`: NightCity's traffic level (the far city's) normalised so the
## working day is full, the evening busy and the small hours a third.
static func hour_factor(hour: float) -> float:
	return clampf(NightCity.traffic_level(hour) / 0.66, 0.3, 1.0)


## 0..1 of a block's planned walkers at `hour`: full 8:00-21:00, the evening still out, the small
## hours a quarter. A near block is thinned toward it only under `THIN_BELOW` (after midnight).
const CROWD_KEYS: Array[float] = [0.5, 0.36, 0.25, 0.22, 0.25, 0.4, 0.62, 0.86, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 0.96, 0.88, 0.72, 0.5]


const THIN_BELOW := 0.55


static func crowd_factor(hour: float) -> float:
	var h := fposmod(hour, 24.0)
	var i := floori(h)
	return lerpf(CROWD_KEYS[i], CROWD_KEYS[i + 1], h - float(i))


static func hour_now(node: Node) -> float:
	return StreetVendors.hour_now(node)


# --- the camera -----------------------------------------------------------------------------

## The camera's true world position and flat heading (unit, y 0), or the player's when there is
## no camera. [Vector3, Vector3]
static func eye(tree: SceneTree, fallback: Node3D) -> Array:
	var cam := tree.root.get_viewport().get_camera_3d() if tree else null
	if cam and cam.is_inside_tree():
		var f := -cam.global_transform.basis.z
		f.y = 0.0
		return [WorldState.to_world(cam.global_position), f.normalized() if f.length() > 0.01 else Vector3.FORWARD]
	var p := WorldState.to_world(fallback.global_position) if fallback else Vector3.ZERO
	var fwd := -fallback.global_transform.basis.z if fallback else Vector3.FORWARD
	fwd.y = 0.0
	return [p, fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD]


## Whether true-world `p` is inside the view cone from `at` looking `fwd` (flat).
static func in_view(at: Vector3, fwd: Vector3, p: Vector3, cone_deg: float = -1.0) -> bool:
	var d := Vector3(p.x - at.x, 0.0, p.z - at.z)
	var l := d.length()
	if l < 0.5:
		return true
	return d.dot(fwd) / l > cos(deg_to_rad(view_cone if cone_deg < 0.0 else cone_deg))


# --- traffic --------------------------------------------------------------------------------

## While the street cars are under this share of their target (a fresh load, a teleport, the hour
## turning busy) the street is FILLING: spawns come in bursts of `FILL_BURST` a half second and may
## land in plain sight from near_min on - the loading screen hides it, and an empty street in front
## of the camera waiting for cars to drive in from 115 m is what every still showed.
const FILL_BELOW := 0.7
const FILL_BURST := 40
static var fill_now: bool = false


## How many street spawns TrafficManager._maintain() may queue this half second (it was 12).
static func spawn_burst(tm: TrafficManager, want: int) -> int:
	fill_now = enabled and not tm.staged and tm.cars.size() < roundi(want * FILL_BELOW)
	return FILL_BURST if fill_now else 12


## A focused spawn for TrafficManager._spawn_near(): Vector3(axis, index, along), or
## Vector3.INF to keep the old rule. Rolls on the traffic's own rng (not the city's).
static func pick_spawn(tm: TrafficManager, rng: RandomNumberGenerator) -> Vector3:
	if not enabled or rng.randf() >= focus_share:
		return Vector3.INF
	var e := eye(tm.get_tree(), tm._player)
	var at: Vector3 = e[0]
	var fwd: Vector3 = e[1]
	var plan := tm.plan
	var axis := rng.randi_range(0, 1)
	var center := plan.block_index_at(Vector2(at.x, at.z))
	var index := (center.x if axis == CityPlan.AXIS_X else center.y) + rng.randi_range(-FOCUS_ROADS, FOCUS_ROADS + 1)
	# Along the road: ahead of the camera mostly (the camera's heading projected on the road).
	var a_cam := at.z if axis == CityPlan.AXIS_X else at.x
	var f_along := fwd.z if axis == CityPlan.AXIS_X else fwd.x
	var ahead := signf(f_along) if absf(f_along) > 0.2 else (1.0 if rng.randf() < 0.5 else -1.0)
	var sgn := ahead if rng.randf() < ahead_share else -ahead
	var off := rng.randf_range(near_min, focus_max)
	var along := a_cam + off * sgn
	var cross := plan.road_pos(axis, index)
	var p := Vector3(cross, at.y, along) if axis == CityPlan.AXIS_X else Vector3(along, at.y, cross)
	if not fill_now and in_view(at, fwd, p) and Vector2(p.x - at.x, p.z - at.z).length() < view_pop_min:
		# In plain sight and close: push it out to where a new car is a dot down the street.
		along = a_cam + sgn * rng.randf_range(view_pop_min, maxf(view_pop_min + 1.0, focus_max))
	return Vector3(axis, index, along)


## Whether the traffic may still spawn with PhysicsBudget full: traffic cars are kinematic
## (placed, mask dropped - no simulation), and counted against the props budget the kerbs' parked
## cars, built first as the ring streams in, used to take all of it and every queued street spawn
## was dropped (the empty roads of the stills). The traffic's own caps bound it instead; the bodies
## that are not traffic still have to fit the budget.
static func traffic_room(tm: TrafficManager) -> bool:
	if not enabled:
		return false
	var own := tm.cars.size() + tm.freeway_cars.size() + tm.loop_cars.size()
	return PhysicsBudget.active_body_count() - own < PhysicsBudget.max_active_bodies


## Whether a street car at true world `wp` should go back to the pool to be spent nearer the
## camera (TrafficManager._maintain(); never while the traffic is staged).
static func retire_far(tm: TrafficManager, wp: Vector3, at: Vector3, fwd: Vector3) -> bool:
	if not enabled or tm.staged:
		return false
	var d := Vector2(wp.x - at.x, wp.z - at.z).length()
	return d > rear_reach and not in_view(at, fwd, wp, view_cone + 15.0)


# --- the crowd ------------------------------------------------------------------------------

## CityChunk._pedestrian_steps(): what this block planned (its ring, pavement width, walkers).
static func note_crowd(ch: Node3D, rect: Rect2, sidewalk: float, count: int) -> void:
	if not enabled or count <= 0:
		return
	var list: Array = ch.get_meta("busy_crowd", [])
	list.append([rect, sidewalk, count])
	ch.set_meta("busy_crowd", list)


static var _ped_script: Script = null
static var _crowd_clock: float = 0.0


## Plain walkers (not officers, sleepers, vendors, ...) - the only people this moves.
static func is_plain_walker(n: Node) -> bool:
	if _ped_script == null:
		_ped_script = load("res://scripts/npc/pedestrian.gd")
	var p := n as Pedestrian
	return p != null and p.get_script() == _ped_script and not p._down and p.visible \
			and not p.has_meta("no_trim") and p.errand.is_empty() and p.watch.is_empty() \
			and p._act == CrowdLife.Act.NONE and not p.is_queued_for_deletion()


## Once a second from CityStreamer._process(): tops up the near blocks' walkers.
static func crowd_tick(streamer: Node3D, delta: float) -> void:
	if not enabled:
		return
	_crowd_clock += delta
	if _crowd_clock < 1.0:
		return
	_crowd_clock = 0.0
	balance_crowd(streamer)


## One pass of the crowd balance (crowd_tick; the checks call it directly). Returns how many
## walkers it added (minus how many it thinned).
static func balance_crowd(streamer: Node3D) -> int:
	var tree := streamer.get_tree()
	if tree == null or not ("chunks" in streamer) or not ("max_pedestrians" in streamer):
		return 0
	var e := eye(tree, streamer.get("_player") as Node3D)
	var at: Vector3 = e[0]
	var fwd: Vector3 = e[1]
	var factor := crowd_factor(hour_now(streamer))
	# The near blocks, nearest first: [chunk, entry, live, want].
	var near: Array = []
	for k in streamer.chunks:
		var ch: Node3D = streamer.chunks[k]
		if not is_instance_valid(ch) or not ch.visible or not ch.has_meta("busy_crowd") or int(ch.get("level")) != CityChunk.Level.FULL:
			continue
		for entry: Array in ch.get_meta("busy_crowd"):
			var r: Rect2 = entry[0]
			var c := r.get_center()
			var d := Vector2(c.x - at.x, c.y - at.z).length() - r.size.length() * 0.35
			if d > crowd_reach:
				continue
			var live := 0
			for child in ch.get_children():
				if child is Pedestrian and (child as Pedestrian).ring == r and not child.is_queued_for_deletion():
					live += 1
			near.append([ch, entry, live, roundi(int(entry[2]) * factor), d])
	if near.is_empty():
		return 0
	near.sort_custom(func(a: Array, b: Array) -> bool: return float(a[4]) < float(b[4]))
	var added := 0
	var budget := crowd_per_tick
	var cap: int = streamer.max_pedestrians
	for n: Array in near:
		var ch: CityChunk = n[0]
		var entry: Array = n[1]
		var short: int = int(n[3]) - int(n[2])
		if short < 0:
			if factor >= THIN_BELOW:
				continue
			# Late at night: thin the block toward its share, out of view.
			added -= _thin(ch, entry[0], -short, at, fwd)
			continue
		while short > 0 and budget > 0:
			var room := CityChunk.count_crowd_room(tree, cap)
			if room <= roundi(cap * Encampment.walker_reserve(ch.plan, ch.ix, ch.iz)) and not _free_far(tree, at, fwd):
				return added
			_spawn(ch, entry, at, fwd)
			short -= 1
			budget -= 1
			added += 1
		if budget <= 0:
			break
	return added


## Frees the farthest plain walker past crowd_far that is out of view; false if there is none.
static func _free_far(tree: SceneTree, at: Vector3, fwd: Vector3) -> bool:
	var best: Node3D = null
	var best_d := crowd_far
	for n in tree.get_nodes_in_group("pedestrian"):
		if not is_plain_walker(n):
			continue
		var wp := WorldState.to_world((n as Node3D).global_position)
		var d := Vector2(wp.x - at.x, wp.z - at.z).length()
		if d > best_d and not in_view(at, fwd, wp):
			best = n
			best_d = d
	if best == null:
		return false
	best.remove_from_group("pedestrian")
	best.queue_free()
	return true


static func _thin(ch: Node3D, ring: Rect2, over: int, at: Vector3, fwd: Vector3) -> int:
	var gone := 0
	for child in ch.get_children():
		if gone >= mini(over, 2):
			break
		if not (child is Pedestrian) or (child as Pedestrian).ring != ring or not is_plain_walker(child):
			continue
		var wp := WorldState.to_world((child as Node3D).global_position)
		if in_view(at, fwd, wp) and Vector2(wp.x - at.x, wp.z - at.z).length() < 90.0:
			continue
		child.remove_from_group("pedestrian")
		child.queue_free()
		gone += 1
	return gone


static var _serial: int = 0


## One walker on the block's ring, at a point out of the view (or crowd_pop_min off).
static func _spawn(ch: CityChunk, entry: Array, at: Vector3, fwd: Vector3) -> void:
	_serial += 1
	var rect: Rect2 = entry[0]
	var sidewalk: float = entry[1]
	var ped := Pedestrian.new()
	ped.setup(rect, sidewalk, hash([ch.plan.seed, ch.ix, ch.iz, "busy_walker", _serial]))
	FashionDistrict.walker(ch, ped)
	var start := ped._random_ring_point(sidewalk)
	for i in 6:
		var w := Vector3(start.x, at.y, start.y)
		if not in_view(at, fwd, w) or Vector2(w.x - at.x, w.z - at.z).length() > crowd_pop_min:
			break
		start = ped._random_ring_point(sidewalk)
	ped.position = Vector3(start.x, CityChunk.SIDEWALK_TOP + 0.1 + ch._gy(start.x, start.y), start.y)
	ped.set_meta("busy_topup", true)
	ch.add_child(ped)


# --- fuller kerbs ---------------------------------------------------------------------------

## The extra parked cars a block of district count `max_cars` may add (CityChunk._park_car_steps).
static func park_extra_count(max_cars: int) -> int:
	return roundi(max_cars * PARK_EXTRA) if enabled else 0


## Whether kerb spot `spot` (CityChunk's [pos, yaw, side]) gets an extra car: a hash of seed + spot.
static func park_extra_roll(seed_value: int, spot: Array) -> bool:
	var p: Vector3 = spot[0]
	return float(absi(hash([seed_value, roundi(p.x * 4.0), roundi(p.z * 4.0), "busy_park"])) % 10007) / 10007.0 < PARK_EXTRA_ODDS


## A private rng for that spot's car (its look and facing).
static func park_extra_rng(seed_value: int, spot: Array) -> RandomNumberGenerator:
	var p: Vector3 = spot[0]
	var r := RandomNumberGenerator.new()
	r.seed = hash([seed_value, roundi(p.x * 4.0), roundi(p.z * 4.0), "busy_park_car"])
	return r
