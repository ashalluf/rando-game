class_name TrafficBehaviour
extends RefCounted
## Street traffic that reads alive at eye level (fleet wave 4, traffic-behaviour-2), on top of
## TrafficManager's IDM queues and TrafficAI's drivers, through four hook lines in
## TrafficManager._drive_street / _drive_streets and one in Vehicle._tick_lights:
## - CREEP at a red: some drivers stop a car's length short of the line, stand, then roll up to it.
## - INCH in a queue: a standing car with slack ahead (the IDM's clamp leaves up to 1.2 m) rolls up
##   now and then, so the brake lights of a queue go off and on again car by car.
## - FOOT off the brake: some drivers at a long stop ease the pedal a moment (the lamps flicker).
## - A BUS pulls out of its stop on its left indicator: it signals, waits, then eases out.
## - LEFT TURNS wait in the box for a gap in the oncoming traffic (and clear on the amber).
## - Cars stop POLITELY back from a crosswalk somebody is still on.
## - WRECKS and knocked-out cars in a lane: changed round on a two-lane road (TrafficAI's lane
##   change), edged round into the oncoming side when it is clear on a one-lane road, slowed past
##   (rubbernecking) in the lanes beside.
## - HEADS turn: the traced driver and passenger (car_cabin.gdshaderinc `occupant_look`) glance
##   both ways before a turn, watch the oncoming traffic, a wreck, a pedestrian, the player.
## Every per-car-per-tick cost is a few dictionary reads; the obstacle survey runs every
## OBSTACLE_EVERY seconds, the heads only for cars within LOOK_RANGE of the camera.
## TRAFFIC_BEHAVIOUR=0 in the environment turns it all off (the A/B).

static var enabled: bool = OS.get_environment("TRAFFIC_BEHAVIOUR") != "0"

## Share of drivers who stop short of the line at a red and creep up to it.
const CREEP_SHARE := 0.5
## How far short of the line they stop (m), and how long they stand before creeping (s).
const CREEP_SHORT := Vector2(1.7, 3.4)
const CREEP_AFTER := Vector2(2.0, 6.5)
## The creep's speed (m/s) and its gentle braking (m/s2).
const CREEP_SPEED := 0.7
const CREEP_DECEL := 0.9
## A queued car with at least this much slack (m, past its standing gap) rolls up to its leader,
## after standing this long (s).
const INCH_SLACK := 0.55
const INCH_AFTER := Vector2(1.2, 4.5)
const INCH_SPEED := 0.95
## Share of drivers who ease off the brake at a stop, how often (s) and for how long (s).
const FOOT_SHARE := 0.4
const FOOT_EVERY := Vector2(3.5, 10.0)
const FOOT_FOR := Vector2(0.7, 1.5)
## A bus done at its stop signals left this long before it pulls out (s).
const BUS_SIGNAL := Vector2(0.9, 2.0)
## A left-turner waits in the box for oncoming cars further than this many seconds away.
const LEFT_GAP_SECONDS := 4.0
## Where its centre waits short of the junction's centre (m), and how long before it just goes.
const LEFT_WAIT_AT := 4.0
const LEFT_GIVE_UP := 16.0
## How far back from a crosswalk somebody is on the nose waits (m).
const POLITE_BACK := 1.3
## The obstacle survey: how often (s), how far round the player (m).
const OBSTACLE_EVERY := 0.4
const OBSTACLE_REACH := 220.0
## How far ahead an obstacle in the lane is seen (m), the slow pass beside one (m/s, within m).
const DODGE_LOOK := 60.0
const RUBBERNECK_SPEED := 4.5
const RUBBERNECK_REACH := 22.0
## How far to the side of an obstacle's centre a car must pass (m).
const DODGE_CLEAR := 2.35
## Heads: which cars (m from the camera), how fast they turn (rad/s), how far (rad).
const LOOK_RANGE := 30.0
const LOOK_RATE := 3.2
const LOOK_MAX := 1.35

## Lane key -> [[along, half length, lateral offset from the road centre, true world pos], ...].
static var _obst: Dictionary = {}
## Road (axis, index) -> the same records, for the lanes beside (rubbernecking).
static var _obst_road: Dictionary = {}
static var _survey_t: float = 0.0
## Instance id -> [true world position at the last survey, whether it covered a lane].
static var _seen: Dictionary = {}
static var _look_tick: int = 0
## What the checks count.
static var counts: Dictionary = {}
## A true world point every driver near the camera looks at (stills; NAN x: none).
static var look_override := Vector3(NAN, 0.0, 0.0)


static func count(what: String) -> void:
	counts[what] = int(counts.get(what, 0)) + 1


## A 0..1 roll per car and salt.
static func roll(car: Vehicle, salt: int) -> float:
	return float(absi(hash([car.get_instance_id(), salt, "tb2"])) % 10007) / 10007.0


# --- Once a tick --------------------------------------------------------------------------------

## Called by TrafficManager._drive_streets once a tick, before any car is driven.
static func begin_tick(tm: TrafficManager, delta: float) -> void:
	if not enabled:
		return
	_survey_t -= delta
	if _survey_t <= 0.0:
		_survey_t = OBSTACLE_EVERY
		survey(tm)
	_look_tick += 1
	if _look_tick % 3 == 0:
		_heads(tm, delta * 3.0)


## Every car standing in a travel lane that is not traffic - a wreck, a car knocked out of the
## traffic, one the player left in the road - by lane key.
static func survey(tm: TrafficManager) -> void:
	_obst.clear()
	_obst_road.clear()
	var player := tm._player
	if player == null or not player.is_inside_tree():
		return
	var pw := WorldState.to_world(player.global_position)
	var plan := tm.plan
	var reach2 := OBSTACLE_REACH * OBSTACLE_REACH
	for n in tm.get_tree().get_nodes_in_group("vehicle"):
		var c := n as Vehicle
		if c == null or not c.is_inside_tree() or c.is_traffic() or c.driver != null or c is Aircraft:
			continue
		var wp := WorldState.to_world(c.global_position)
		if Vector2(wp.x - pw.x, wp.z - pw.z).length_squared() > reach2:
			continue
		# Flying, or riding something (a wreck on a tow truck's bed has no collision).
		if c.linear_velocity.length_squared() > 9.0 or c.collision_layer == 0:
			continue
		# Most of these are parked cars that have not moved since the last survey: what lanes they
		# cover is remembered (nothing, for a car in its parking lane).
		var id := c.get_instance_id()
		var seen: Array = _seen.get(id, [])
		if not seen.is_empty() and (seen[0] as Vector3).distance_squared_to(wp) < 0.04:
			if seen[1]:
				register(plan, c, wp)
			continue
		_seen[id] = [wp, register(plan, c, wp)]
	if _seen.size() > 4000:
		_seen.clear()


## Puts car `c` standing at true world `wp` on the lanes it covers (tests call it directly).
## True when it covers any.
static func register(plan: CityPlan, c: Vehicle, wp: Vector3) -> bool:
	var any := false
	var half := TrafficManager.car_half_length(c)
	for axis: int in [CityPlan.AXIS_X, CityPlan.AXIS_Z]:
		var across := wp.x if axis == CityPlan.AXIS_X else wp.z
		var along := wp.z if axis == CityPlan.AXIS_X else wp.x
		var i0 := plan._index_at(axis, across)
		for index: int in [i0, i0 + 1]:
			var lat := across - plan.road_pos(axis, index)
			var w := plan.road_width(axis, index)
			if absf(lat) > w * 0.5:
				continue
			# Inside a junction box it is in both roads' way and neither's lanes: left alone.
			var cross := CityPlan.AXIS_Z if axis == CityPlan.AXIS_X else CityPlan.AXIS_X
			var k := plan._index_at(cross, along)
			var near_cross := false
			for kk: int in [k, k + 1]:
				if absf(along - plan.road_pos(cross, kk)) < plan.road_width(cross, kk) * 0.5 + 1.0:
					near_cross = true
			if near_cross or not plan.road_open(axis, index, along):
				continue
			var rec := [along, half, lat, wp]
			var lanes := TrafficAI.lanes_of(plan, axis, index)
			var road_key := Vector2i(axis, index)
			var hit := false
			for dir: int in [1, -1]:
				for ln in lanes:
					var off := TrafficAI.lane_offset_n(plan, axis, index, dir, ln)
					if absf(lat - off) < 1.75:
						var key := TrafficManager.lane_key(axis, index, dir, off)
						if not _obst.has(key):
							_obst[key] = []
						(_obst[key] as Array).append(rec)
						hit = true
			if hit:
				any = true
				if not _obst_road.has(road_key):
					_obst_road[road_key] = []
				(_obst_road[road_key] as Array).append(rec)
	return any


# --- Stop points (TrafficManager._drive_street) ------------------------------------------------

## The nearest extra place this car must stand still short of, as a gap from its nose (m), or INF.
## Also sets the car's look target and its dodge shift. `line_hold`: a light / sign / crosswalk
## holds it at `to_line` this tick.
static func street_stop(tm: TrafficManager, car: Vehicle, t: Dictionary, groups: Dictionary, along: float, v: float, to_centre: float, to_line: float, cw: float, node: Vector2i, line_hold: bool, delta: float) -> float:
	# A car a check or a still placed drives exactly as told unless it asks for this (`tb`), like
	# TrafficAI's `ai`: the checks that place cars measure stops to the centimetre.
	if not enabled or (t.has("placed") and not t.has("tb")):
		return INF
	var axis: int = t.axis
	var index: int = t.index
	var dir: int = t.dir
	var half: float = t.get("half", 2.4)
	var to_far := to_centre + cw * 0.5 + 0.15 - half
	# Most cars most ticks: moving, nothing at the line, no turn coming up, no crosswalk close, no
	# bus, nothing standing on the road. Out after a handful of reads (this runs for every car).
	# (A red holds every car coming up to it from a block away: only its last 40 m matter here.)
	if v > 1.0 and (not line_hold or to_line > 40.0) and to_far > 30.0 and not t.has("bus") and not t.has("tb_dodge") and (to_centre > LEFT_WAIT_AT + 24.0 or int(t.get("turn", 0)) == 0) and (_obst_road.is_empty() or not _obst_road.has(Vector2i(axis, index))):
		if t.has("tb_foot"):
			t.erase("tb_foot")
		if t.has("tb_creep"):
			t.erase("tb_creep")
		return INF
	var plan := tm.plan
	var gap := INF
	if not t.has("tb_r"):
		t.tb_r = [roll(car, 1), roll(car, 2), roll(car, 3), roll(car, 4)]
	var r: Array = t.tb_r
	var now := TrafficAI.clock
	# Stand still long enough and the foot comes off the brake now and then (the lamps read it).
	_foot(t, r, v, delta)
	# Creep at a red: stop short, stand, then roll up to the line (post_speed does the roll).
	if line_hold and to_line > -0.2 and float(r[0]) < CREEP_SHARE and not t.has("bus") and not BigVehicles.is_big(car.body_type):
		var state := int(t.get("tb_creep", 0))
		var short := lerpf(CREEP_SHORT.x, CREEP_SHORT.y, float(r[1]))
		if state == 0:
			gap = minf(gap, to_line - short)
			if v < 0.05 and to_line - short < 1.3:
				t.tb_creep = 1
				t.tb_ct = lerpf(CREEP_AFTER.x, CREEP_AFTER.y, float(r[2]))
		elif state == 1:
			gap = minf(gap, maxf(to_line - short, 0.0))
			t.tb_ct = float(t.tb_ct) - delta
			if float(t.tb_ct) <= 0.0:
				t.tb_creep = 2
				count("creep")
	elif t.has("tb_creep"):
		t.erase("tb_creep")
	# A bus done at its stop: indicator left, a beat, then out.
	if t.has("bus"):
		gap = minf(gap, _bus_out(tm, car, t, along, delta))
	# Somebody still on the far crosswalk: wait a little back from it, not with the nose on it.
	if to_far > -0.4 and to_far < 40.0 and Pedestrian.crosswalk_busy(node, axis, dir):
		gap = minf(gap, maxf(to_far - POLITE_BACK, 0.0) if v < 0.5 or to_far > POLITE_BACK + 0.6 else INF)
		_look_at(t, _crosswalk_point(plan, axis, index, node, dir, cw, now), now)
	elif line_hold and to_line < 8.0 and Pedestrian.crosswalk_busy(node, axis, -dir):
		_look_at(t, _crosswalk_point(plan, axis, index, node, -dir, cw, now), now)
	# Turning left across the oncoming traffic: into the box, then wait for a gap.
	var turn := int(t.get("turn", 0))
	var side := TrafficAI.turn_side(axis, dir, turn) if turn == 1 or turn == -1 else 0
	if side < 0 and to_centre > 0.0:
		gap = minf(gap, _left_wait(tm, car, t, groups, along, v, to_centre, to_line, node, line_hold, delta))
	elif t.has("tb_left"):
		t.erase("tb_left")
	# Something standing in the lane ahead that is not traffic.
	gap = minf(gap, _obstacles(tm, car, t, groups, along, v, half, delta))
	return gap


## A car's speed after the drive's own rules (TrafficManager._drive_street, after the clamp that
## stands a car closed up on something): the creep at the line and the inch up a queue.
## `still` is the slack (m) before the nearest thing standing still ahead.
static func post_speed(car: Vehicle, t: Dictionary, v: float, nv: float, still: float, delta: float) -> float:
	if not enabled or (v > 0.5 and nv > 0.5 and not t.has("tb_slow") and not t.has("tb_inch") and not t.has("tb_creep")):
		return nv
	if float(t.get("react", 0.0)) > 0.0 or (t.has("placed") and not t.has("tb")):
		return nv
	if t.has("tb_slow"):
		var cap := float(t.tb_slow)
		t.erase("tb_slow")
		if nv > cap:
			nv = maxf(cap, v - 3.0 * delta)
	if int(t.get("tb_creep", 0)) == 2:
		if still > 0.08 and still < 8.0:
			return move_toward(v, minf(CREEP_SPEED, sqrt(2.0 * CREEP_DECEL * still)), 1.4 * delta)
		t.tb_creep = 3
		return 0.0
	# Inching up a queue: only from a stand, with nothing else moving it.
	if v < 0.05 and nv < 0.05 and still > INCH_SLACK and still < 4.0 and not t.has("tb_creep"):
		var wait := float(t.get("tb_inch", -1.0))
		if wait < 0.0:
			var r: Array = t.get("tb_r", [0.5, 0.5, 0.5, 0.5])
			wait = lerpf(INCH_AFTER.x, INCH_AFTER.y, fposmod(float(r[3]) * 7.31 + TrafficAI.clock * 0.07, 1.0))
		wait -= delta
		t.tb_inch = wait
		if wait <= 0.0:
			t.tb_inching = true
			t.erase("tb_inch")
			count("inch")
	if t.get("tb_inching", false):
		if still > 0.12 and still < 4.5:
			return move_toward(v, minf(INCH_SPEED, sqrt(2.0 * CREEP_DECEL * still)), 1.6 * delta)
		t.erase("tb_inching")
		return 0.0
	if v > 0.5 and t.has("tb_inch"):
		t.erase("tb_inch")
	return nv


## The kerb shift the car wants (TrafficManager's want_shift): a bus held at its stop keeps its
## stop shift while it signals; a car edging round an obstacle moves toward the centre line.
static func want_shift(t: Dictionary, want: float) -> float:
	if not enabled:
		return want
	if float(t.get("tb_bus_go", 0.0)) > 0.0:
		want = maxf(want, BigVehicles.STOP_SHIFT)
	if t.has("tb_dodge"):
		want = minf(want, float(t.tb_dodge))
	return want


# --- The pieces ---------------------------------------------------------------------------------

static func _foot(t: Dictionary, r: Array, v: float, delta: float) -> void:
	var foot := float(t.get("tb_foot", 0.0))
	if foot > 0.0:
		t.tb_foot = foot - delta
		if v > 0.3 or float(t.tb_foot) <= 0.0:
			t.erase("tb_foot")
		return
	if float(r[3]) >= FOOT_SHARE or v > 0.05:
		t.erase("tb_foot_in")
		return
	var wait := float(t.get("tb_foot_in", -1.0))
	if wait < 0.0:
		wait = lerpf(FOOT_EVERY.x, FOOT_EVERY.y, fposmod(float(r[2]) * 3.7 + TrafficAI.clock * 0.13, 1.0))
	wait -= delta
	if wait <= 0.0:
		t.tb_foot = lerpf(FOOT_FOR.x, FOOT_FOR.y, fposmod(float(r[1]) * 5.3 + TrafficAI.clock * 0.29, 1.0))
		t.erase("tb_foot_in")
		count("foot")
	else:
		t.tb_foot_in = wait


static func _bus_out(tm: TrafficManager, car: Vehicle, t: Dictionary, along: float, delta: float) -> float:
	var axis: int = t.axis
	var cross := CityPlan.AXIS_Z if axis == CityPlan.AXIS_X else CityPlan.AXIS_X
	var key := Vector3i(axis, int(t.index), tm.plan._index_at(cross, along))
	if t.get("served", Vector3i(0, 0, -999999)) != key:
		# The doors have closed (TrafficManager._bus_dwell's beat before it is done): signal.
		var need := float(t.get("dwell_need", 0.0))
		if need > 0.0 and float(t.get("dwell", 0.0)) > need:
			t.sig = -1
		if t.has("tb_bus_key"):
			t.erase("tb_bus_key")
			t.erase("tb_bus_go")
		return INF
	if not t.has("tb_bus_key"):
		if float(t.get("shift", 0.0)) < 0.3:
			return INF
		t.tb_bus_key = key
		t.tb_bus_go = lerpf(BUS_SIGNAL.x, BUS_SIGNAL.y, roll(car, 7))
		t.sig = -1
		count("bus_signal")
	var go := float(t.get("tb_bus_go", 0.0))
	if go > 0.0:
		t.tb_bus_go = go - delta
		t.sig = -1
		return 0.0
	# Out in the lane again: the indicator goes off.
	if int(t.get("sig", 0)) == -1 and float(t.get("shift", 0.0)) < 0.12:
		t.sig = 0
	elif float(t.get("shift", 0.0)) >= 0.12:
		t.sig = -1
	return INF


## Where a left-turner's centre must stand (m ahead), or INF once it may go.
static func _left_wait(tm: TrafficManager, car: Vehicle, t: Dictionary, groups: Dictionary, along: float, v: float, to_centre: float, to_line: float, node: Vector2i, line_hold: bool, delta: float) -> float:
	if line_hold:
		# Held at the line itself: nothing of ours yet.
		return INF
	var st: Array = t.get("tb_left", [])
	if st.is_empty() or st[0] != node:
		st = [node, false, 0.0, 0.0, false, false]
		t.tb_left = st
	if st[1]:
		return INF
	if to_centre > LEFT_WAIT_AT + 18.0:
		return INF
	var axis: int = t.axis
	var index: int = t.index
	var dir: int = t.dir
	var plan := tm.plan
	# Watching the oncoming traffic.
	var cross_pos := plan.road_pos(CityPlan.AXIS_Z if axis == CityPlan.AXIS_X else CityPlan.AXIS_X, node.y if axis == CityPlan.AXIS_X else node.x)
	var road := plan.road_pos(axis, index)
	var ahead := Vector3(road, 0.0, cross_pos + float(dir) * 30.0) if axis == CityPlan.AXIS_X else Vector3(cross_pos + float(dir) * 30.0, 0.0, road)
	_look_at(t, ahead, TrafficAI.clock)
	if v < 0.3 and to_centre < LEFT_WAIT_AT + 2.0:
		st[2] = float(st[2]) + delta
	# Once in the box on a light that is no longer green, clear the junction (everybody does).
	var kind: int = plan.intersection(node.x, node.y).kind
	var in_box := to_line < -0.2
	if in_box and kind == CityPlan.Intersection.SIGNALS and TrafficSignals.light(plan, node.x, node.y, axis) != TrafficSignals.Light.GREEN:
		st[1] = true
		count("left_clear")
		return INF
	if float(st[2]) > LEFT_GIVE_UP:
		st[1] = true
		return INF
	st[3] = float(st[3]) - delta
	if float(st[3]) <= 0.0:
		st[3] = 0.2
		# The gap must hold for the time it still takes to get to the turn, too. Clear while still
		# coming up to the box it rolls on; it only commits once it is there.
		var need := LEFT_GAP_SECONDS + maxf(to_centre - LEFT_WAIT_AT, 0.0) / maxf(v, 3.0)
		st[4] = oncoming_clear(tm, groups, axis, index, dir, cross_pos, need, 95.0)
		if st[4] and to_centre < LEFT_WAIT_AT + 3.0:
			st[1] = true
			if st[5]:
				count("left_gap")
			return INF
	if st[4]:
		return INF
	st[5] = true
	return maxf(to_centre - LEFT_WAIT_AT, 0.0)


## True when no car of road (axis, index)'s `-dir` lanes is coming at `at` (along) within `secs`
## seconds or `reach` metres (moving cars only: one standing at its line is no threat).
static func oncoming_clear(tm: TrafficManager, groups: Dictionary, axis: int, index: int, dir: int, at: float, secs: float, reach: float) -> bool:
	var plan := tm.plan
	for n in TrafficAI.lanes_of(plan, axis, index):
		var key := TrafficManager.lane_key(axis, index, -dir, TrafficAI.lane_offset_n(plan, axis, index, -dir, n))
		for other in groups.get(key, []):
			if not is_instance_valid(other):
				continue
			var ot: Dictionary = (other as Vehicle).traffic
			if not ot.has("along"):
				continue
			var d := (at - float(ot.along)) * float(-dir) + float(ot.get("half", 2.4))
			var ov := float(ot.get("v", 0.0))
			if d < -1.0 or d > reach or ov < 0.6:
				continue
			if d / ov < secs:
				return false
	return true


## A wreck or a knocked-out car in the lane ahead: [the gap to stand at (m) or INF], with the lane
## change asked of TrafficAI, the edge round it, the slow pass and the look set as it goes.
static func _obstacles(tm: TrafficManager, car: Vehicle, t: Dictionary, groups: Dictionary, along: float, v: float, half: float, delta: float) -> float:
	# A service vehicle at work (a tow truck coming for this very wreck) keeps its own stops.
	if _obst_road.is_empty() or t.has("work"):
		_end_dodge(t)
		return INF
	var axis: int = t.axis
	var index: int = t.index
	var dir: int = t.dir
	var recs: Array = _obst_road.get(Vector2i(axis, index), [])
	if recs.is_empty():
		_end_dodge(t)
		return INF
	var plan := tm.plan
	var lane := float(t.lane)
	var key := TrafficManager.lane_key(axis, index, dir, lane)
	var mine: Array = _obst.get(key, [])
	var now := TrafficAI.clock
	# Rubbernecking: slow past anything standing on this road, and look at it.
	for rec: Array in recs:
		var d := (float(rec[0]) - along) * float(dir)
		if d > -float(rec[1]) - half and d < RUBBERNECK_REACH + half:
			t.tb_slow = RUBBERNECK_SPEED
			_look_at(t, rec[3], now)
		elif d > 0.0 and d < 45.0:
			_look_at(t, rec[3], now)
	var best: Array = []
	var bd := INF
	for rec: Array in mine:
		var d := (float(rec[0]) - along) * float(dir) - half - float(rec[1])
		# Kept until the whole car is past it, with a metre to spare, before it moves back.
		var lo := -2.0 * float(rec[1]) - 2.0 * half - 1.0 if t.has("tb_dodge") else 0.0
		if d > lo and d < DODGE_LOOK and d < bd:
			bd = d
			best = rec
	if best.is_empty():
		# Past it (or nothing): back into the lane.
		_end_dodge(t)
		return INF
	var lanes := TrafficAI.lanes_of(plan, axis, index)
	var cur := TrafficAI.lane_n(plan, axis, index, lane)
	# Two lanes this way: change lanes round it (TrafficAI signals and waits for the gap).
	if lanes >= 2 and TrafficAI.enabled and not tm._rail_street(axis, index) and not t.has("lc_from"):
		var other := TrafficAI.lane_offset_n(plan, axis, index, dir, 1 - cur)
		var okey := TrafficManager.lane_key(axis, index, dir, other)
		if not _obst.has(okey) or not _blocks(_obst[okey], along, dir, half):
			if not t.has("lc_want") and bd > 4.0 and (not t.has("placed") or t.has("ai")):
				t.lc_want = other
				t.lc_reason = "pass"
				t.lc_wait = 0.0
				t.sig = TrafficAI.side_of_move(lane, other)
				count("wreck_lane_change")
			return maxf(bd - 2.5, 0.0)
	# One lane (or the other is blocked too): edge round it toward the centre line when the
	# oncoming side is clear, else stand behind it.
	var lat := float(best[2])
	var lsign := signf(lane)
	var need := minf(0.0, (lat - lsign * DODGE_CLEAR - lane) * lsign)
	need = maxf(need, -3.6)
	var shift := float(t.get("shift", 0.0))
	if t.has("tb_dodge"):
		t.tb_dodge = need
		if shift > need + 0.35:
			# Still moving over: creep up to it.
			return maxf(bd - 0.8, 0.0)
		return INF
	if bd < 30.0 and oncoming_clear(tm, groups, axis, index, dir, float(best[0]), 5.0, 90.0):
		t.tb_dodge = need
		t.sig = -1
		count("wreck_dodge")
	return maxf(bd - 2.0, 0.0)


static func _end_dodge(t: Dictionary) -> void:
	if t.has("tb_dodge"):
		t.erase("tb_dodge")
		if int(t.get("sig", 0)) == -1 and not t.has("lc_want") and not t.has("lc_from") and not t.has("dp_at"):
			t.sig = 0


static func _blocks(recs: Array, along: float, dir: int, half: float) -> bool:
	for rec: Array in recs:
		var d := (float(rec[0]) - along) * float(dir)
		if d > -float(rec[1]) - half and d < DODGE_LOOK + 10.0:
			return true
	return false


static func _crosswalk_point(plan: CityPlan, axis: int, index: int, node: Vector2i, side: int, cw: float, now: float) -> Vector3:
	var cross := CityPlan.AXIS_Z if axis == CityPlan.AXIS_X else CityPlan.AXIS_X
	var cp := plan.road_pos(cross, node.y if axis == CityPlan.AXIS_X else node.x) + float(side) * (cw * 0.5 + 1.5)
	var road := plan.road_pos(axis, index) + sin(now * 0.7) * plan.road_width(axis, index) * 0.35
	return Vector3(road, 0.0, cp) if axis == CityPlan.AXIS_X else Vector3(cp, 0.0, road)


## The driver looks at true world point `p` for the next half second.
static func _look_at(t: Dictionary, p: Vector3, now: float) -> void:
	t.tb_look_at = p
	t.tb_look_t = now


# --- Heads --------------------------------------------------------------------------------------

## The traced driver and passenger of the cars near the camera turn their heads
## (car_cabin.gdshaderinc `occupant_look`: radians toward the car's right, driver / passengers).
static func _heads(tm: TrafficManager, dt: float) -> void:
	var cam := tm.get_viewport().get_camera_3d() if tm.is_inside_tree() else null
	if cam == null:
		return
	var cp := cam.global_position
	var range2 := LOOK_RANGE * LOOK_RANGE
	var now := TrafficAI.clock
	var player := tm._player
	for c in tm.cars:
		if not is_instance_valid(c) or not c.is_inside_tree():
			continue
		if c.global_position.distance_squared_to(cp) > range2:
			continue
		var t: Dictionary = c.traffic
		# Nobody inside (Vehicle._occupant_key is 0 for an empty cabin).
		if t.is_empty() or c._occupant_key == 0:
			continue
		var target := look_target(c, t, player, now)
		var cur: Vector2 = t.get("tb_look", Vector2.ZERO)
		cur.x = move_toward(cur.x, target.x, LOOK_RATE * dt)
		cur.y = move_toward(cur.y, target.y, LOOK_RATE * 0.8 * dt)
		t.tb_look = cur
		var mat := c.cabin_glass() as ShaderMaterial
		if mat == null or mat == c._glass_shared:
			continue
		var last: Vector2 = t.get("tb_look_set", Vector2(INF, INF))
		if mat.get_instance_id() != int(t.get("tb_look_mat", 0)) or absf(last.x - cur.x) > 0.025 or absf(last.y - cur.y) > 0.025:
			mat.set_shader_parameter("occupant_look", cur)
			t.tb_look_set = cur
			t.tb_look_mat = mat.get_instance_id()


## Where car `c`'s driver (x) and passenger (y) want to look, radians toward the car's right.
static func look_target(c: Vehicle, t: Dictionary, player: Node3D, now: float) -> Vector2:
	var drv := NAN
	if not is_nan(look_override.x):
		drv = _angle_to(c, WorldState.to_local(look_override))
	elif t.has("tb_look_at") and now - float(t.get("tb_look_t", -99.0)) < 0.6:
		drv = _angle_to(c, WorldState.to_local(t.tb_look_at as Vector3))
	if is_nan(drv) and player != null and player.is_inside_tree():
		var pp := player.global_position
		if pp.distance_squared_to(c.global_position) < 14.0 * 14.0:
			drv = _angle_to(c, pp)
	var seed := float(c.get_instance_id() % 997) * 0.173
	if is_nan(drv):
		var turn := int(t.get("turn", 0))
		var to_c := float(t.get("to_c", INF))
		if turn != 0 and turn != 2 and to_c < 28.0 and to_c > -3.0:
			# Before a turn: a look the way it is going, one the other way, then the way again.
			var side := float(TrafficAI.turn_side(int(t.axis), int(t.dir), turn))
			var ph := fposmod(now * 0.45 + seed, 1.0)
			drv = side * 1.05 if ph < 0.45 else (-side * 0.85 if ph < 0.7 else side * 0.6)
		else:
			# Idle glances: mostly ahead, now and then out a window or at a mirror.
			var slot := floorf(now / 3.2 + seed)
			var h := fposmod(sin(slot * 12.9898 + seed * 78.233) * 43758.5453, 1.0)
			var still := float(t.get("v", 0.0)) < 0.3
			var share := 0.55 if still else 0.25
			drv = 0.0
			if h < share:
				var k := fposmod(h * 13.7, 1.0)
				drv = (-1.0 if k < 0.5 else 1.0) * lerpf(0.35, 1.2 if still else 0.5, fposmod(h * 7.1, 1.0))
	# The passenger: at the driver now and then (talking), out their own window, or ahead.
	var ps := floorf(now / 4.1 + seed * 1.7)
	var hp := fposmod(sin(ps * 4.898 + seed * 21.13) * 23421.631, 1.0)
	var pas := 0.0
	if hp < 0.3:
		pas = -0.95
	elif hp < 0.5:
		pas = 0.8
	return Vector2(clampf(drv, -LOOK_MAX, LOOK_MAX), pas)


## Radians toward car `c`'s right from its heading to scene point `p`.
static func _angle_to(c: Vehicle, p: Vector3) -> float:
	var to := p - c.global_position
	var fwd := -c.global_basis.z
	var right := c.global_basis.x
	return atan2(to.dot(right), to.dot(fwd))
