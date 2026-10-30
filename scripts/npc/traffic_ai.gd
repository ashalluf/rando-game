class_name TrafficAI
extends RefCounted
## Traffic that drives like people (traffic-ai, 2026-10-05). TrafficManager (scripts/npc/traffic.gd)
## still owns the lanes, the queues and the Intelligent Driver Model; this is what it asks about
## the people at the wheels:
##
## * MOODS, a hash per car (roll_mood()): most drivers NORMAL; a few PUSHY (short gaps, late hard
##   braking, through the amber, honk soon, quick to change lanes), a few CAREFUL (long gaps, slow,
##   stop for every amber, slow to honk) and a few DOZY (on the phone: slow off the line on green).
## * REACTION at a light: a car that was held by its stop line waits its mood's reaction time
##   before it pulls away, and a car behind one that does not go on green honks.
## * LANE CHANGES on a street with two lanes each way (street_think()): round a bus at its stop, a
##   double-parked car or a slow truck, into the lane for the turn it rolled, and a swerve round
##   the player on foot. Signalled first (the indicator Vehicle._tick_lights reads, `sig`), only
##   into a gap that is safe ahead and behind (gap_ok()), a smooth lateral move over a few seconds
##   (`lc_*`: the car belongs to the new lane's queue at once and stays a ghost in the old one
##   until it is mostly across, so both queues keep their gaps).
## * DOUBLE PARKING: now and then a car in the kerb lane stops mid-block on its hazards for a
##   while (the cars behind pass it).
## * PULL-OUTS: now and then a parked car near the player becomes a traffic car (pullout()): it
##   signals, waits for a gap, and pulls out of the parking lane as a lane change.
## * FREEWAYS (freeway_think() and the ramp cars): passing, keeping right, trucks in the two slow
##   lanes, cars leaving by the off-ramps and joining from the on-ramps, merging into a gap.
## * HONKING (honk()): Sfx car_horn / car_horn_long (CC0 recordings, tools/traffic_horns.py),
##   positional, rate-limited per car and city-wide, only within earshot.
##
## Everything here is maths on the positions the manager already has: no physics queries.
## `TRAFFIC_AI=0` in the environment turns it all off (the A/B), which is the old traffic.

static var enabled: bool = OS.get_environment("TRAFFIC_AI") != "0"

enum Mood { NORMAL, PUSHY, CAREFUL, DOZY }
## Shares of the non-normal moods (the rest are NORMAL).
const PUSHY_SHARE := 0.12
const CAREFUL_SHARE := 0.12
const DOZY_SHARE := 0.08

## Street lane changes: seconds of indicator before a car moves over (a pushy driver's share of
## it), the lateral move (s), how long a car waits for a gap before it gives up (s), and how
## often a car looks for a reason to change (s).
const SIGNAL_SECONDS := 1.4
const MOVE_SECONDS := 3.0
const SWERVE_SECONDS := 1.3
const GIVE_UP_SECONDS := 7.0
const THINK_SECONDS := 0.5
## Share of the move after which a changing car stops counting in the lane it left.
const GHOST_UNTIL := 0.65
## Distance ahead a car looks for something to pass, and how close to the next junction a car
## still starts a change (m past the crossing road's edge).
const PASS_LOOK := 60.0
const JUNCTION_KEEP := 10.0
## A car with a turn rolled heads for its turn lane within this distance of the junction (m).
const TURN_LANE_REACH := 140.0
## The player on foot this far ahead in the lane makes a car swerve if the next lane is clear.
const SWERVE_REACH := Vector2(5.0, 30.0)

## Double parking: the chance a car in the kerb lane does it at a given block, and for how long.
const DOUBLE_PARK_CHANCE := 0.025
const DOUBLE_PARK_SECONDS := Vector2(12.0, 26.0)
## How far over toward the kerb a double-parked car stands (m).
const DOUBLE_PARK_SHIFT := 0.7

## Pull-outs: one at a time at most, looked for every PULLOUT_EVERY seconds with PULLOUT_CHANCE,
## from parked cars this far from the player (m).
const PULLOUT_EVERY := 3.0
const PULLOUT_CHANCE := 0.35
const PULLOUT_RANGE := Vector2(22.0, 110.0)
const PULLOUT_MOVE := 3.4

## Freeway: how often a car thinks (s), its lateral move (s), the share of freeway cars that take
## the next off-ramp, the most cars on the ramps at once, and the seconds between cars joining
## from one on-ramp.
const FW_THINK_SECONDS := 0.6
const FW_MOVE_SECONDS := 3.6
const FW_EXIT_SHARE := 0.22
const MAX_RAMP_CARS := 6
const RAMP_EVERY := Vector2(7.0, 16.0)
## Ramp speeds (m/s): down an off-ramp to, and up an on-ramp to.
const RAMP_OFF_SPEED := 13.0
const RAMP_ON_SPEED := 21.0
## Where along an on-ramp (0 the deck edge, 1 the street) a joining car merges.
const MERGE_AT := 0.02

## Honking: the most honks city-wide in HONK_WINDOW seconds, how far from the player a horn is
## worth playing (m), and each car's quiet time after it honks (s).
const MAX_HONKS := 3
const HONK_WINDOW := 2.0
const HONK_REACH := 120.0
const HONK_COOLDOWN := Vector2(3.5, 7.0)

## The shared clock (s) honking and pull-outs run on, advanced by TrafficManager each tick.
static var clock: float = 0.0
static var _rolls: int = 0
static var _honks: Array = []
## The last honks, for the checks: [reason, car instance id, clock].
static var honk_log: Array = []
## Counters for the checks and the HUD: lane changes started on streets / freeways, merges,
## exits, pull-outs, swerves, double parks.
static var counts: Dictionary = {}


static func count(what: String) -> void:
	counts[what] = int(counts.get(what, 0)) + 1


# --- Moods --------------------------------------------------------------------------------------

## Rolls a driver for `car` into its traffic dict (a hash of the car and how many have been
## rolled, never the traffic's rng): the mood and its numbers, `m_*`. `force` a Mood for tests;
## placed cars (TrafficManager.place_car) are NORMAL with fixed numbers so the checks are exact.
static func roll_mood(car: Vehicle, t: Dictionary, force: int = -1) -> void:
	var h := absi(hash([car.get_instance_id(), _rolls, "traffic_mood"]))
	_rolls += 1
	var u := float(h % 10007) / 10007.0
	var w := float((h / 10007) % 997) / 997.0
	var mood: int = Mood.NORMAL
	if force >= 0:
		mood = force
	elif u < PUSHY_SHARE:
		mood = Mood.PUSHY
	elif u < PUSHY_SHARE + CAREFUL_SHARE:
		mood = Mood.CAREFUL
	elif u < PUSHY_SHARE + CAREFUL_SHARE + DOZY_SHARE:
		mood = Mood.DOZY
	t.mood = mood
	# m_gap: time gap and standing gap scale; m_brake: how hard it is willing to brake on the way
	# in (a pushy driver brakes late); m_amber: amber_margin scale (smaller runs more ambers);
	# m_speed: its own speed; m_react: seconds off the line on green; m_patience: seconds before
	# it honks at somebody who is not going; m_eager: how much slower a car ahead must be before
	# it passes.
	match mood:
		Mood.PUSHY:
			_mood_numbers(t, 0.55, 1.45, 0.55, 1.15, lerpf(0.2, 0.45, w), lerpf(0.7, 1.4, w), 0.85)
		Mood.CAREFUL:
			_mood_numbers(t, 1.5, 0.8, 1.7, 0.86, lerpf(0.9, 1.5, w), lerpf(5.0, 9.0, w), 0.55)
		Mood.DOZY:
			_mood_numbers(t, 1.05, 1.0, 1.0, 0.95, lerpf(2.6, 4.6, w), 3.5, 0.7)
		_:
			if force >= 0:
				w = 0.5
			_mood_numbers(t, lerpf(0.85, 1.15, w), 1.0, 1.0, 1.0, lerpf(0.45, 0.85, w), lerpf(2.2, 3.4, w), 0.7)
	t.speed = float(t.get("speed", 10.0)) * float(t.m_speed)


static func _mood_numbers(t: Dictionary, gap: float, brake: float, amber: float, speed: float, react: float, patience: float, eager: float) -> void:
	t.m_gap = gap
	t.m_brake = brake
	t.m_amber = amber
	t.m_speed = speed
	t.m_react = react
	t.m_patience = patience
	t.m_eager = eager


# --- Lanes --------------------------------------------------------------------------------------

## How many lanes each way road (axis, index) has (TrafficManager's own rule).
static func lanes_of(plan: CityPlan, axis: int, index: int) -> int:
	return 2 if plan.road_width(axis, index) > plan.street_width + 1.0 else 1


## Which lane (0 by the centre line) a signed lane offset is on.
static func lane_n(plan: CityPlan, axis: int, index: int, lane: float) -> int:
	var width := plan.road_width(axis, index)
	var lanes := lanes_of(plan, axis, index)
	var best := 0
	var bd := INF
	for n in lanes:
		var d := absf(absf(lane) - CityPlan.lane_center(width, lanes, n))
		if d < bd:
			bd = d
			best = n
	return best


## The signed offset of lane `n` for traffic driving `dir` on road (axis, index).
static func lane_offset_n(plan: CityPlan, axis: int, index: int, dir: int, n: int) -> float:
	var width := plan.road_width(axis, index)
	var lanes := lanes_of(plan, axis, index)
	var side := -dir if axis == CityPlan.AXIS_X else dir
	return float(side) * CityPlan.lane_center(width, lanes, clampi(n, 0, lanes - 1))


## Which way a turn goes for the driver: 1 right, -1 left (Vehicle._traffic_signal()'s rule; a
## U-turn is a left).
static func turn_side(axis: int, dir: int, turn: int) -> int:
	if turn == 0:
		return 0
	if turn == 2:
		return -1
	var x_road := axis == CityPlan.AXIS_X
	var forward := Vector3(0.0, 0.0, dir) if x_road else Vector3(dir, 0.0, 0.0)
	var after := Vector3(float(turn), 0.0, 0.0) if x_road else Vector3(0.0, 0.0, float(turn))
	return 1 if after.dot(forward.cross(Vector3.UP)) > 0.0 else -1


## The lane a car turning onto road (axis, index) heading `dir` lands in: the kerb lane for a
## right turn, the inner one for a left (a light rail street keeps to its outer lane).
static func turn_lane(tm: TrafficManager, axis: int, index: int, dir: int, side: int) -> float:
	var lanes := lanes_of(tm.plan, axis, index)
	var n := lanes - 1 if side > 0 or tm._rail_street(axis, index) else 0
	return lane_offset_n(tm.plan, axis, index, dir, n)


## The indicator for moving from lane offset `from` to `to`: out toward the kerb is right.
static func side_of_move(from: float, to: float) -> int:
	return 1 if absf(to) > absf(from) else -1


## True when lane group `key` has room for `car` at `along`: nothing ahead closer than the car
## would want to follow it at, nothing behind that would have to brake harder than comfortably to
## keep its own gap. `urgent` (a swerve) takes tighter gaps.
static func gap_ok(tm: TrafficManager, groups: Dictionary, key: int, car: Vehicle, along: float, dir: int, v: float, urgent: bool = false) -> bool:
	var t: Dictionary = car.traffic
	var half := float(t.get("half", 2.4))
	var rear := float(t.get("rear", half))
	var tg := float(t.get("m_gap", 1.0)) * (0.5 if urgent else 1.0)
	for other in groups.get(key, []):
		if other == car or not is_instance_valid(other):
			continue
		var ot: Dictionary = (other as Vehicle).traffic
		if not ot.has("along"):
			continue
		var ov := float(ot.get("v", 0.0))
		var d := (float(ot.along) - along) * float(dir)
		if d >= 0.0:
			var gap := d - half - float(ot.get("rear", ot.get("half", 2.4)))
			var need := tm.min_gap * 0.8 + v * tm.time_gap * 0.6 * tg + maxf(0.0, v - ov) * maxf(0.0, v - ov) / (2.0 * tm.brake_comfort)
			if gap < maxf(need, 1.6):
				return false
		else:
			var gap := -d - float(ot.get("half", 2.4)) - rear
			var need := tm.min_gap + ov * tm.time_gap * 0.8 * tg + maxf(0.0, ov - v) * maxf(0.0, ov - v) / (2.0 * tm.brake_comfort)
			if gap < maxf(need, 2.0):
				return false
	return true


## The nearest car of lane group `key` ahead of `along` (direction `dir`), other than `me`:
## [car, gap from my nose to its rear] or [].
static func ahead_in(groups: Dictionary, key: int, along: float, dir: int, half: float, me: Vehicle) -> Array:
	var best: Vehicle = null
	var bd := INF
	for other in groups.get(key, []):
		if other == me or not is_instance_valid(other):
			continue
		var ot: Dictionary = (other as Vehicle).traffic
		var d := (float(ot.get("along", along)) - along) * float(dir)
		if d > 0.0 and d < bd:
			bd = d
			best = other
	if best == null:
		return []
	return [best, bd - half - float(best.traffic.get("rear", best.traffic.get("half", 2.4)))]


## Starts the move to lane offset `to` (the car's queue changes at once: TrafficManager groups
## it by `lane`, and keeps it as a ghost in its old lane until GHOST_UNTIL of the move).
static func start_move(car: Vehicle, groups: Dictionary, to: float, seconds: float, why: String) -> void:
	var t: Dictionary = car.traffic
	var from := float(t.lane) + signf(float(t.lane)) * float(t.get("shift", 0.0))
	t.lc_key = TrafficManager.lane_key(int(t.axis), int(t.index), int(t.dir), float(t.lane))
	t.lc_from = from
	t.lc_to = to
	t.lc_p = 0.0
	t.lc_dur = seconds
	t.lc_why = why
	t.sig = side_of_move(from, to)
	t.lane = to
	t.shift = 0.0
	t.erase("lc_want")
	t.erase("lc_wait")
	var key := TrafficManager.lane_key(int(t.axis), int(t.index), int(t.dir), to)
	if not groups.has(key):
		groups[key] = []
	(groups[key] as Array).append(car)
	count("street_" + why)


## Ends a move (or a wait for a gap that never came).
static func end_move(t: Dictionary) -> void:
	for k in ["lc_from", "lc_to", "lc_p", "lc_dur", "lc_why", "lc_want", "lc_wait", "lc_noghost", "lc_key", "lc_src", "lc_lat", "lane_now", "lc_reason"]:
		t.erase(k)
	if not t.has("dp_at"):
		t.sig = 0


## A street car's lane-change thinking, once a tick before it is driven (TrafficManager.
## _drive_street): signalling and waiting for a gap, or every THINK_SECONDS looking for a reason
## to change - a turn lane, something to pass, the player in the road - and now and then deciding
## to double-park. `to_centre` / `cw` the next junction's, `past` metres past the last one.
static func street_think(tm: TrafficManager, car: Vehicle, leader: Vehicle, groups: Dictionary, to_centre: float, cw: float, past: float, delta: float) -> void:
	var t: Dictionary = car.traffic
	if t.has("lc_from") or t.has("pull"):
		return
	if t.has("placed") and not t.has("ai"):
		return
	if t.has("bus") or t.has("dp_at"):
		return
	# Pulled over for a siren behind (TrafficManager's yield_t): stay put until it has gone by,
	# and drop any change it was signalling for.
	if float(t.get("yield_t", 0.0)) > 0.0:
		if t.has("lc_want"):
			end_move(t)
		return
	# Most ticks there is nothing to do: no change waiting for a gap, the think timer running, and
	# the player not close ahead. Out before any lookup (this runs for every car every tick).
	if not t.has("lc_want"):
		var near := false
		if not tm._player_block.is_empty() and not bool(tm._player_block[3]):
			near = ((tm._player_block[0] as Vector3) - (t.wp as Vector3)).length_squared() < SWERVE_REACH.y * SWERVE_REACH.y
		var timer := float(t.get("lc_next", fposmod(float(car.get_instance_id() % 97) * 0.013, THINK_SECONDS))) - delta
		t.lc_next = timer
		if timer > 0.0 and not near:
			return
	var axis: int = t.axis
	var index: int = t.index
	var dir: int = t.dir
	var plan := tm.plan
	# Two lanes each way and no trackway, worked out once per road the car is on.
	var road_key := Vector2i(axis, index)
	if t.get("lc_road", Vector2i(-999999, 0)) != road_key:
		t.lc_road = road_key
		t.lc_multi = lanes_of(plan, axis, index) >= 2 and not tm._rail_street(axis, index)
	if not bool(t.lc_multi):
		return
	var lanes := 2
	var along := float(t.along)
	var v := float(t.get("v", 0.0))
	var half := float(t.get("half", 2.4))
	var room := to_centre - cw * 0.5 - JUNCTION_KEEP
	# Never starting a change inside a junction (its nose still in the last one, or already in the
	# next); a move may run on across one, as people do round a bus just past a corner.
	var nose_room := to_centre - cw * 0.5 - half
	var in_box := past + 2.0 * half < 1.0 or nose_room < 2.0
	var cur := lane_n(plan, axis, index, float(t.lane))
	# Signalling: move over once there is a gap, give up after a while or near the junction.
	if t.has("lc_want"):
		var to := float(t.lc_want)
		t.lc_wait = float(t.get("lc_wait", 0.0)) + delta
		if float(t.lc_wait) > GIVE_UP_SECONDS or (str(t.get("lc_reason", "")) == "turn" and nose_room < 6.0):
			end_move(t)
			t.lc_next = 2.5
			return
		var need := SIGNAL_SECONDS * (0.4 if int(t.get("mood", 0)) == Mood.PUSHY else 1.0)
		if float(t.lc_wait) >= need and not in_box:
			var key := TrafficManager.lane_key(axis, index, dir, to)
			if gap_ok(tm, groups, key, car, along, dir, v):
				var secs := MOVE_SECONDS * (0.7 if int(t.get("mood", 0)) == Mood.PUSHY else (1.25 if int(t.get("mood", 0)) == Mood.CAREFUL else 1.0))
				start_move(car, groups, to, secs, str(t.get("lc_reason", "pass")))
		return
	# The player on foot in the lane ahead: swerve at once if the next lane is clear.
	if not in_box and not tm._player_block.is_empty() and not bool(tm._player_block[3]):
		var rel: Vector3 = (tm._player_block[0] as Vector3) - (t.wp as Vector3)
		var ahead := (rel.z if axis == CityPlan.AXIS_X else rel.x) * float(dir)
		var lat := (rel.x if axis == CityPlan.AXIS_X else rel.z)
		var lane_pos := plan.road_pos(axis, index) + float(t.lane)
		var here := (t.wp as Vector3).x if axis == CityPlan.AXIS_X else (t.wp as Vector3).z
		lat += here - lane_pos
		if ahead > SWERVE_REACH.x + half and ahead < SWERVE_REACH.y and absf(lat) < 1.6 and absf(rel.y) < 3.0 and v > 2.0:
			var other_n := 1 - cur
			var to := lane_offset_n(plan, axis, index, dir, other_n)
			var other_pos := plan.road_pos(axis, index) + to
			var player_off := absf((tm._player_block[0] as Vector3).x - other_pos) if axis == CityPlan.AXIS_X else absf((tm._player_block[0] as Vector3).z - other_pos)
			var key := TrafficManager.lane_key(axis, index, dir, to)
			if player_off > 2.4 and gap_ok(tm, groups, key, car, along, dir, v, true):
				start_move(car, groups, to, SWERVE_SECONDS, "swerve")
				honk(tm, car, "swerve", true)
				return
	if float(t.lc_next) > 0.0:
		return
	t.lc_next = THINK_SECONDS
	if in_box:
		return
	var want := -1
	var reason := ""
	# Into the lane for the turn it rolled.
	var side := turn_side(axis, dir, int(t.get("turn", 0)))
	if side != 0 and to_centre < TURN_LANE_REACH and nose_room > maxf(12.0, v * 2.2):
		var n := lanes - 1 if side > 0 else 0
		if n != cur:
			want = n
			reason = "turn"
	# Round something in the lane ahead that is not going to move with the traffic.
	if want < 0 and leader != null and is_instance_valid(leader):
		var lt: Dictionary = leader.traffic
		var gap := (float(lt.get("along", along)) - along) * float(dir) - half - float(lt.get("rear", lt.get("half", 2.4)))
		var lv := float(lt.get("v", 0.0))
		var blocked := false
		if gap < PASS_LOOK and int(lt.get("why", 0)) != 1:
			if lt.has("bus") and (lv < 2.0 or float(lt.get("shift", 0.0)) > 0.3):
				blocked = true
			elif lt.has("dp_at"):
				blocked = true
			elif BigVehicles.is_big(leader.body_type) and lv > 1.0 and lv < float(t.speed) * float(t.get("m_eager", 0.7)) and gap < 30.0:
				blocked = true
		if blocked and side == 0:
			want = 1 - cur
			reason = "pass"
	if want < 0:
		# Now and then double-park instead (the kerb lane, a quiet mid-block stretch).
		if cur == lanes - 1 and side == 0 and not BigVehicles.is_big(car.body_type) and room > 60.0 and v > 3.0:
			var node: Vector2i = t.get("node", Vector2i.ZERO)
			var h := absi(hash([car.get_instance_id(), node, "double_park"]))
			if t.get("dp_node", Vector2i(-999999, 0)) != node:
				t.dp_node = node
				if float(h % 10000) / 10000.0 < DOUBLE_PARK_CHANCE:
					var stop_in := maxf(22.0, v * v / (2.0 * tm.brake_comfort) + 10.0)
					if stop_in < room - 20.0:
						t.dp_at = along + float(dir) * (stop_in + half)
						t.dp = lerpf(DOUBLE_PARK_SECONDS.x, DOUBLE_PARK_SECONDS.y, float((h / 10000) % 97) / 97.0)
						t.sig = 1
						count("double_park")
		return
	t.lc_want = lane_offset_n(plan, axis, index, dir, want)
	t.lc_reason = reason
	t.lc_wait = 0.0
	t.sig = side_of_move(float(t.lane), float(t.lc_want))


## Where a moving car is across the road this tick: [lane offset, lateral speed (m/s)], and the
## move's progress advanced by `delta` at speed `v` (a car stuck behind something stops moving
## over). Ends the move when it is done.
static func move_tick(t: Dictionary, v: float, delta: float) -> Array:
	var from := float(t.lc_from)
	var to := float(t.lc_to)
	var p := float(t.lc_p)
	var rate := clampf(v / 3.0, 0.0, 1.0) / maxf(float(t.lc_dur), 0.1)
	if t.has("lc_noghost"):
		rate = maxf(rate, 0.08 / maxf(float(t.lc_dur), 0.1)) if v > 0.2 else rate
	p = minf(p + rate * delta, 1.0)
	t.lc_p = p
	var e := p * p * (3.0 - 2.0 * p)
	var lat := (to - from) * 6.0 * p * (1.0 - p) * rate
	if p >= 1.0:
		end_move(t)
		return [to, 0.0]
	return [lerpf(from, to, e), lat]


# --- Honking ------------------------------------------------------------------------------------

## A honk from `car` (`long` leaning on it). Rate-limited per car (HONK_COOLDOWN) and city-wide
## (MAX_HONKS a HONK_WINDOW), and only played within HONK_REACH of the player. True if it honked.
static func honk(tm: TrafficManager, car: Vehicle, reason: String, long: bool = false) -> bool:
	if not enabled or not is_instance_valid(car) or not car.is_inside_tree():
		return false
	var t: Dictionary = car.traffic
	if clock < float(t.get("honk_at", -INF)):
		return false
	while not _honks.is_empty() and clock - float(_honks[0]) > HONK_WINDOW:
		_honks.pop_front()
	if _honks.size() >= MAX_HONKS:
		return false
	var player := tm._player
	if player == null or car.global_position.distance_to(player.global_position) > HONK_REACH:
		return false
	var h := absi(hash([car.get_instance_id(), clock]))
	t.honk_at = clock + lerpf(HONK_COOLDOWN.x, HONK_COOLDOWN.y, float(h % 101) / 100.0)
	_honks.append(clock)
	honk_log.append([reason, car.get_instance_id(), clock])
	if honk_log.size() > 64:
		honk_log.pop_front()
	count("honk_" + reason)
	var at := car.global_position - car.global_basis.z * float(t.get("half", 2.4)) + Vector3.UP * 0.7
	if not EngineAudio.horn(car, long, at): # the car's own horn (engine-audio pass)
		Sfx.play("car_horn_long" if long else "car_horn", at, 0.0, 1.0 + float(h % 13 - 6) * 0.012)
	return true


# --- Pull-outs ----------------------------------------------------------------------------------

## Now and then (PULLOUT_EVERY, PULLOUT_CHANCE) a parked car near the player pulls out into the
## traffic: see pullout(). Called from the manager's half-second upkeep.
static func maybe_pullout(tm: TrafficManager) -> void:
	if tm.staged or not enabled:
		return
	if float(tm.get_meta("pull_next", 0.0)) > clock:
		return
	tm.set_meta("pull_next", clock + PULLOUT_EVERY)
	for c in tm.cars:
		if is_instance_valid(c) and c.traffic.has("pull"):
			return
	if float(absi(hash([int(clock * 10.0), "pullout"])) % 1000) / 1000.0 > PULLOUT_CHANCE:
		return
	var list := pullout_candidates(tm)
	if list.is_empty():
		return
	pullout(tm, list[absi(hash([int(clock * 10.0), "pick"])) % list.size()])


## Parked cars that could pull out now: asleep in a parking lane, facing the way that side's
## traffic drives, in range of the player, never driven or hit, on an open city street.
static func pullout_candidates(tm: TrafficManager) -> Array:
	var out: Array = []
	var city := tm.get_parent()
	if city == null or tm._player == null:
		return out
	var chunks: Variant = city.get("chunks")
	if not chunks is Dictionary:
		return out
	var pp := tm._player.global_position
	for chunk in (chunks as Dictionary).values():
		if not is_instance_valid(chunk):
			continue
		var list: Variant = chunk.get("_cars")
		if not list is Array:
			continue
		for c in list:
			# A chunk's list keeps a car someone freed (a wreck cleared, an errand's car gone).
			if not is_instance_valid(c):
				continue
			var car := c as Vehicle
			if car == null or not car.is_inside_tree() or not car.visible:
				continue
			var d := car.global_position.distance_to(pp)
			if d < PULLOUT_RANGE.x or d > PULLOUT_RANGE.y:
				continue
			if not pullout_road(tm, car).is_empty():
				out.append(car)
	return out


## The road a parked car would pull out onto: [axis, index, dir, parking offset (signed)], or []
## when it cannot (driven, damaged, awake, facing the wrong way, not in a parking lane).
static func pullout_road(tm: TrafficManager, car: Vehicle) -> Array:
	if car.is_traffic() or car.driver != null or car._npc_driver or car.has_meta("driven") or car._damage != null or car is Aircraft:
		return []
	if BigVehicles.is_big(car.body_type):
		return []
	if not PhysicsServer3D.body_get_state(car.get_rid(), PhysicsServer3D.BODY_STATE_SLEEPING):
		return []
	var plan := tm.plan
	var wp := WorldState.to_world(car.global_position)
	var f := -car.global_basis.z
	var axis := -1
	var dir := 0
	if absf(f.z) > 0.97:
		axis = CityPlan.AXIS_X
		dir = 1 if f.z > 0.0 else -1
	elif absf(f.x) > 0.97:
		axis = CityPlan.AXIS_Z
		dir = 1 if f.x > 0.0 else -1
	else:
		return []
	var across := wp.x if axis == CityPlan.AXIS_X else wp.z
	var along := wp.z if axis == CityPlan.AXIS_X else wp.x
	var i0 := plan._index_at(axis, across)
	var side := -dir if axis == CityPlan.AXIS_X else dir
	for index in [i0, i0 + 1]:
		var road := plan.road_pos(axis, index)
		var park := float(side) * CityPlan.parking_offset(plan.road_width(axis, index))
		if absf(across - road - park) > 0.9:
			continue
		var pos2 := Vector2(wp.x, wp.z)
		if plan.zone_at(pos2) != MacroMap.Zone.CITY or tm._replica_blocks(pos2, 6.0) or not plan.road_open(axis, index, along) or not plan.road_open(axis, index, along + float(dir) * 20.0):
			return []
		# Mid-block, clear of the junctions either side.
		var cross := CityPlan.AXIS_Z if axis == CityPlan.AXIS_X else CityPlan.AXIS_X
		var k := plan._index_at(cross, along)
		var a0 := plan.road_pos(cross, k) + plan.road_width(cross, k) * 0.5
		var a1 := plan.road_pos(cross, k + 1) - plan.road_width(cross, k + 1) * 0.5
		if along - a0 < 10.0 or a1 - along < 14.0:
			return []
		return [axis, index, dir, park]
	return []


## Makes parked `car` a traffic car pulling out of its spot: off its chunk's list (the traffic
## owns it now), its physics wheels off BEFORE it freezes (a frozen VehicleBody3D with wheels is
## NaN), kinematic, a driver at the wheel, signalling left until pull_tick() finds a gap.
static func pullout(tm: TrafficManager, car: Vehicle) -> bool:
	var road := pullout_road(tm, car)
	if road.is_empty():
		return false
	var city := tm.get_parent()
	for chunk in (city.get("chunks") as Dictionary).values():
		if is_instance_valid(chunk):
			var list: Variant = chunk.get("_cars")
			if list is Array and (list as Array).has(car):
				(list as Array).erase(car)
	for w in car.wheels:
		if is_instance_valid(w):
			car.remove_child(w)
			w.free()
	car.wheels.clear()
	car.linear_velocity = Vector3.ZERO
	car.angular_velocity = Vector3.ZERO
	car.engine_force = 0.0
	var axis: int = road[0]
	var index: int = road[1]
	var dir: int = road[2]
	var lanes := lanes_of(tm.plan, axis, index)
	var lane := lane_offset_n(tm.plan, axis, index, dir, lanes - 1)
	var t := {"axis": axis, "index": index, "dir": dir, "lane": lane, "v": 0.0,
		"speed": lerpf(tm.speed_range.x, tm.speed_range.y, float(absi(hash([car.get_instance_id(), "pull_speed"])) % 1000) / 999.0) * lerpf(1.0, tm.dense_speed_factor, tm.density_at(Vector2(WorldState.to_world(car.global_position).x, WorldState.to_world(car.global_position).z))),
		"half": TrafficManager.car_half_length(car), "rear": TrafficManager.car_rear_length(car),
		"pull": true, "park": float(road[3]), "sig": -1, "pull_t": 0.0}
	roll_mood(car, t)
	car.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	car.freeze = true
	car.traffic = t
	car.traffic_speed = 0.0
	car.collision_mask = car._mask()
	tm.cars.append(car)
	count("pullout")
	return true


## A parked car waiting to pull out (not in any queue yet): indicator on, and once it has shown
## it for a moment and the kerb lane behind it is clear, it goes - as a lane change out of the
## parking lane. Gives up after a minute (stays put, signalling off).
static func pull_tick(tm: TrafficManager, car: Vehicle, groups: Dictionary, delta: float) -> void:
	var t: Dictionary = car.traffic
	t.pull_t = float(t.get("pull_t", 0.0)) + delta
	t.v = 0.0
	car.traffic_speed = 0.0
	if float(t.pull_t) > 60.0:
		t.sig = 0
		return
	t.sig = -1
	if float(t.pull_t) < SIGNAL_SECONDS * 1.2:
		return
	var key := TrafficManager.lane_key(int(t.axis), int(t.index), int(t.dir), float(t.lane))
	if not gap_ok(tm, groups, key, car, float(t.along), int(t.dir), 4.0):
		return
	t.erase("pull")
	t.lc_from = float(t.park)
	t.lc_to = float(t.lane)
	t.lc_p = 0.0
	t.lc_dur = PULLOUT_MOVE
	t.lc_why = "pullout"
	t.lc_noghost = true
	t.sig = -1
	if not groups.has(key):
		groups[key] = []
	(groups[key] as Array).append(car)


# --- Freeways -----------------------------------------------------------------------------------

## The lane index (0 the carpool lane by the median) of a freeway car.
static func fw_lane(fw: Freeway, t: Dictionary) -> int:
	if t.has("li"):
		return int(t.li)
	var width := float(fw.routes[int(t.fw)].width)
	var best := 0
	var bd := INF
	for n in Freeway.LANES:
		var d := absf(absf(float(t.lane)) - Freeway.lane_fraction(width, n))
		if d < bd:
			bd = d
			best = n
	t.li = best
	return best


## A freeway car's lane, its exit plan and its mood, set when it joins (TrafficManager spawns).
static func fw_setup(car: Vehicle, fw: Freeway, placed: bool) -> void:
	var t: Dictionary = car.traffic
	fw_lane(fw, t)
	if placed:
		roll_mood(car, t, Mood.NORMAL)
		return
	roll_mood(car, t)
	t.home = int(t.li)
	var h := absi(hash([car.get_instance_id(), "fw_exit"]))
	if int(t.dir) > 0 and not BigVehicles.is_big(car.body_type) and float(h % 1000) / 1000.0 < FW_EXIT_SHARE:
		t.exit = true


## The ramps of route `ri`, with how far along the route each leaves the deck: [{r, t, path,
## top, ground, on}] (`on` true for an on-ramp: one on the left of the +t carriageway, which runs
## the way the -t traffic drives). Cached on the manager.
static func ramps_of(tm: TrafficManager, fw: Freeway, ri: int) -> Array:
	var cache: Dictionary = tm.get_meta("fw_ramps", {})
	if cache.has(ri):
		return cache[ri]
	var out: Array = []
	for r in fw.ramps:
		if int(r.route) != ri:
			continue
		var start: Vector2 = r.pos
		var yaw := float(r.yaw)
		var o := Vector2(-sin(yaw), -cos(yaw))
		var run: PackedFloat32Array = fw._runs[ri]
		var path := Freeway.ramp_path(r)
		var length := 0.0
		for k in path.size() - 1:
			length += path[k].distance_to(path[k + 1])
		out.append({"r": r, "t": run[int(r.index)], "path": path, "top": float(r.top), "len": length,
			"ground": tm.plan.height_at(start + o * Freeway.RAMP_RUN) + 0.12, "on": float(r.side) < 0.0})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.t) < float(b.t))
	cache[ri] = out
	tm.set_meta("fw_ramps", cache)
	return out


## Where `u` (0 at the deck edge, 1 at the street) along ramp `ramp` puts a car: [world position
## of the road surface, heading down the ramp]. Heights as CityChunk builds the ramp (eased from
## the deck to the street), lifted back to the deck top over its first metres, where the car
## comes off the deck.
static func ramp_point(ramp: Dictionary, u: float) -> Array:
	var path: PackedVector2Array = ramp.path
	var steps := Freeway.RAMP_STEPS
	var f := clampf(u, 0.0, 1.0) * float(steps)
	var k := mini(floori(f), steps - 1)
	var a := path[k]
	var b := path[k + 1]
	var p := a.lerp(b, f - float(k))
	var e := u * u * (3.0 - 2.0 * u)
	var top := float(ramp.top)
	var y := lerpf(top - Freeway.DECK_THICKNESS * 0.5, float(ramp.ground), e)
	y += Freeway.DECK_THICKNESS * 0.5 * (1.0 - smoothstep(0.0, 0.14, u))
	return [Vector3(p.x, y, p.y), (b - a).normalized()]


## A freeway car's thinking every FW_THINK_SECONDS: pass a slower car ahead (left first, then
## right), keep right once past, get over for its exit; trucks keep to the two slow lanes. Starts
## a move (`lc_*` in lane fractions) into a lane only with room ahead and behind.
static func freeway_think(tm: TrafficManager, fw: Freeway, car: Vehicle, leader: Vehicle, groups: Dictionary, delta: float) -> void:
	var t: Dictionary = car.traffic
	if t.has("lc_from") or t.has("ramp"):
		return
	if t.has("placed") and not t.has("ai"):
		return
	t.lc_next = float(t.get("lc_next", fposmod(float(car.get_instance_id() % 89) * 0.017, FW_THINK_SECONDS))) - delta
	if float(t.lc_next) > 0.0:
		return
	t.lc_next = FW_THINK_SECONDS
	var li := fw_lane(fw, t)
	var big := BigVehicles.is_big(car.body_type)
	var lo := Freeway.LANES - 2 if big else 0
	var dir := int(t.dir)
	var v := float(t.get("v", t.speed))
	var want := -1
	var reason := ""
	# The exit: over to the outer lane within a kilometre of its off-ramp.
	if t.has("exit"):
		var ramp: Dictionary = t.get("exit_ramp", {})
		if ramp.is_empty():
			ramp = next_ramp(tm, fw, int(t.fw), float(t.t), dir, false)
		if not ramp.is_empty() and (float(ramp.t) - float(t.t)) * float(dir) < 1000.0 and li < Freeway.LANES - 1:
			want = li + 1
			reason = "exit"
	if want < 0 and leader != null and is_instance_valid(leader):
		var lt: Dictionary = leader.traffic
		var gap := absf(float(lt.t) - float(t.t))
		var lv := float(lt.get("v", lt.speed))
		if gap < 90.0 and lv < float(t.speed) * float(t.get("m_eager", 0.7)) + 3.0 and lv < float(t.speed) - 2.0:
			for n in [li - 1, li + 1]:
				if n < lo or n >= Freeway.LANES:
					continue
				var ahead := fw_ahead(groups, Vector3(float(t.fw), float(dir), float(n)), float(t.t), dir, car)
				if ahead.is_empty() or float(ahead[1]) > gap + 20.0 or float((ahead[0] as Vehicle).traffic.get("v", 0.0)) > lv + 3.0:
					want = n
					reason = "pass"
					break
	if want < 0 and t.has("home") and li < int(t.home):
		# Keep right once there is nothing to pass: the lane to the right clear well ahead.
		var n := li + 1
		var ahead := fw_ahead(groups, Vector3(float(t.fw), float(dir), float(n)), float(t.t), dir, car)
		if ahead.is_empty() or float(ahead[1]) > 110.0:
			want = n
			reason = "right"
	if want < 0:
		return
	if fw_gap_ok(tm, groups, Vector3(float(t.fw), float(dir), float(want)), car, float(t.t), dir, v):
		var width := float(fw.routes[int(t.fw)].width)
		t.lc_from = float(t.lane)
		t.lc_to = Freeway.lane_fraction(width, want) * float(dir)
		t.lc_p = 0.0
		t.lc_dur = FW_MOVE_SECONDS * (0.7 if int(t.get("mood", 0)) == Mood.PUSHY else 1.0)
		t.lc_src = li
		t.li = want
		t.lane = t.lc_to
		t.sig = 1 if want > li else -1
		count("fw_" + reason)


## The nearest car of freeway group `key` ahead of `along_t`: [car, centre to centre (m)] or [].
static func fw_ahead(groups: Dictionary, key: Vector3, along_t: float, dir: int, me: Vehicle) -> Array:
	var best: Vehicle = null
	var bd := INF
	for other in groups.get(key, []):
		if other == me or not is_instance_valid(other):
			continue
		var d := (float(other.traffic.t) - along_t) * float(dir)
		if d > 0.0 and d < bd:
			bd = d
			best = other
	return [] if best == null else [best, bd]


## Room in freeway lane group `key` for `car` at route distance `at`: the manager's freeway
## follow rule (it closes up to freeway_gap * 0.6 plus the lengths) must not have to stop the car
## behind, nor this car, and nobody closing much faster.
static func fw_gap_ok(tm: TrafficManager, groups: Dictionary, key: Vector3, car: Vehicle, at: float, dir: int, v: float) -> bool:
	var t: Dictionary = car.traffic
	for other in groups.get(key, []):
		if other == car or not is_instance_valid(other):
			continue
		var ot: Dictionary = (other as Vehicle).traffic
		var ov := float(ot.get("v", ot.speed))
		var d := (float(ot.t) - at) * float(dir)
		var extra: float
		if d >= 0.0:
			extra = float(t.get("half", 2.4)) + float(ot.get("rear", 2.4)) - 4.8
			if d < tm.freeway_gap * 0.6 + extra + v * 0.45 + maxf(0.0, v - ov) * 1.2:
				return false
		else:
			extra = float(ot.get("half", 2.4)) + float(t.get("rear", 2.4)) - 4.8
			if -d < tm.freeway_gap * 0.6 + extra + ov * 0.55 + maxf(0.0, ov - v) * 1.8:
				return false
	return true


## The next ramp of route `ri` ahead of `at` for traffic driving `dir`: an off-ramp (`on` false)
## for the +t traffic, an on-ramp for the -t traffic. {} if none.
static func next_ramp(tm: TrafficManager, fw: Freeway, ri: int, at: float, dir: int, on: bool) -> Dictionary:
	for ramp: Dictionary in ramps_of(tm, fw, ri):
		if bool(ramp.on) != on:
			continue
		if (float(ramp.t) - at) * float(dir) > 2.0:
			if dir > 0:
				return ramp
	if dir < 0:
		var list := ramps_of(tm, fw, ri)
		for i in range(list.size() - 1, -1, -1):
			var ramp: Dictionary = list[i]
			if bool(ramp.on) == on and (float(ramp.t) - at) * float(dir) > 2.0:
				return ramp
	return {}


## A car on the outer lane with an exit to make: indicator on for the last 250 m, and at its
## off-ramp it leaves the deck (a ramp car from now on). True if it left this tick.
static func fw_exit_tick(tm: TrafficManager, fw: Freeway, car: Vehicle, speed: float, delta: float) -> bool:
	var t: Dictionary = car.traffic
	if not t.has("exit") or t.has("lc_from") or fw_lane(fw, t) != Freeway.LANES - 1:
		return false
	# The off-ramp it is making for, looked up once and kept until it is passed.
	var ramp: Dictionary = t.get("exit_ramp", {})
	if ramp.is_empty() or (float(ramp.t) - float(t.t)) * float(t.dir) < -1.0:
		ramp = next_ramp(tm, fw, int(t.fw), float(t.t), int(t.dir), false)
		t.exit_ramp = ramp
	if ramp.is_empty():
		return false
	var dist := (float(ramp.t) - float(t.t)) * float(t.dir)
	if dist < 250.0:
		t.sig = 1
	if dist > speed * delta + 2.5:
		return false
	t.ramp = ramp
	t.u = 0.0
	t.up = false
	t.v = speed
	t.erase("exit")
	t.erase("exit_ramp")
	count("fw_exit")
	car.global_transform = ramp_xform(car)
	return true


## Joining cars at the foot of the on-ramps near the player, one every RAMP_EVERY seconds a ramp,
## at most MAX_RAMP_CARS on the ramps at once, never in sight of the player at the foot.
static func maybe_ramp_cars(tm: TrafficManager, fw: Freeway, ri: int, here: Vector2) -> void:
	var n := 0
	var busy := {}
	for c in tm.freeway_cars:
		if is_instance_valid(c) and c.traffic.has("ramp"):
			n += 1
			if float(c.traffic.get("u", 0.0)) > 0.75:
				busy[float(c.traffic.ramp.t)] = true
	if n >= MAX_RAMP_CARS:
		return
	var next: Dictionary = tm.get_meta("ramp_next", {})
	for ramp: Dictionary in ramps_of(tm, fw, ri):
		if not bool(ramp.on) or busy.has(float(ramp.t)):
			continue
		var foot: Vector3 = ramp_point(ramp, 1.0)[0]
		var d := Vector2(foot.x, foot.z).distance_to(here)
		if d < 70.0 or d > tm.freeway_range * 0.8:
			continue
		var id := "%d:%d" % [ri, int(float(ramp.t))]
		if clock < float(next.get(id, -INF)):
			continue
		var h := absi(hash([id, int(clock)]))
		next[id] = clock + lerpf(RAMP_EVERY.x, RAMP_EVERY.y, float(h % 101) / 100.0)
		tm._spawn_queues[2].append(tm._spawn_ramp_car.bind(ri, ramp))
		n += 1
		if n >= MAX_RAMP_CARS:
			break
	tm.set_meta("ramp_next", next)


## A car on a ramp: down an off-ramp to the street (then off the road: retired), or up an
## on-ramp to the merge point, where it joins the outer lane once fw_gap_ok() finds it room -
## slowing to wait at the merge point if it has to - and moves over into it as a lane change.
static func ramp_tick(tm: TrafficManager, fw: Freeway, car: Vehicle, groups: Dictionary, delta: float) -> void:
	var t: Dictionary = car.traffic
	var ramp: Dictionary = t.ramp
	var length := maxf(float(ramp.len), 1.0)
	var v := float(t.get("v", 10.0))
	if not bool(t.get("up", false)):
		v = move_toward(v, RAMP_OFF_SPEED, 3.5 * delta)
		t.u = float(t.u) + v * delta / length
		if float(t.u) >= 1.0:
			tm.freeway_cars.erase(car)
			tm._retire(car)
			return
	else:
		var u := float(t.u)
		var to_merge := (u - MERGE_AT) * length
		var key := Vector3(float(t.fw), -1.0, float(Freeway.LANES - 1))
		var room := fw_gap_ok(tm, groups, key, car, float(ramp.t), -1, maxf(v, 8.0))
		if to_merge <= 0.3:
			if room:
				_merge(fw, car, ramp, v)
				return
			# No gap: wait at the merge point, indicator on.
			v = move_toward(v, 0.0, 6.0 * delta)
			t.u = MERGE_AT
			t.sig = -1
		else:
			if to_merge < 60.0:
				t.sig = -1
			if not room and v * v / 8.0 > to_merge - 1.0:
				v = maxf(0.0, v - v * v / (2.0 * maxf(to_merge, 0.5)) * delta)
			else:
				v = move_toward(v, RAMP_ON_SPEED, 2.5 * delta)
			t.u = maxf(MERGE_AT, u - v * delta / length)
	t.v = v
	car.traffic_speed = v
	car.global_transform = ramp_xform(car)


## A ramp car joins the -t carriageway's outer lane at the merge point, moving over from the
## deck edge.
static func _merge(fw: Freeway, car: Vehicle, ramp: Dictionary, v: float) -> void:
	var t: Dictionary = car.traffic
	var width := float(fw.routes[int(t.fw)].width)
	for k in ["ramp", "u", "up"]:
		t.erase(k)
	t.t = float(ramp.t)
	t.dir = -1
	t.li = Freeway.LANES - 1
	t.lane = -Freeway.lane_fraction(width, Freeway.LANES - 1)
	var bow := Freeway.RAMP_BOW * sin(MERGE_AT * PI)
	t.lc_from = -(1.0 + bow / (width * 0.5))
	t.lc_to = t.lane
	t.lc_p = 0.0
	t.lc_dur = 2.8
	t.lane_now = t.lc_from
	t.v = v
	t.sig = -1
	count("fw_merge")


## Where a ramp car stands: on the ramp's surface at its `u`, heading down it (or up it for an
## on-ramp car), nose pitched along the slope.
static func ramp_xform(car: Vehicle) -> Transform3D:
	var t: Dictionary = car.traffic
	var ramp: Dictionary = t.ramp
	var u := float(t.get("u", 0.0))
	var at := ramp_point(ramp, u)
	var p: Vector3 = at[0]
	var h: Vector2 = at[1]
	var du := 0.02
	var y1: float = (ramp_point(ramp, minf(u + du, 1.0))[0] as Vector3).y
	var y0: float = (ramp_point(ramp, maxf(u - du, 0.0))[0] as Vector3).y
	var span := maxf((minf(u + du, 1.0) - maxf(u - du, 0.0)) * float(ramp.len), 0.1)
	var rise := (y1 - y0) / span
	if bool(t.get("up", false)):
		h = -h
		rise = -rise
	var basis := Basis.from_euler(Vector3(atan(rise), atan2(-h.x, -h.y), 0.0))
	return Transform3D(basis, WorldState.to_local(p + Vector3(0.0, car.road_lift(), 0.0)))


# --- Stills (tools/glshot/still_shot.gd TRAFFIC=...) ----------------------------------------------

## Stages a scene for a still near `cam` and returns a free camera for it ("x,y,z,yaw,pitch", true
## world, absolute height): `bus` a bus at its stop on a two-lane road with a car coming up behind
## it in the kerb lane, `merge` a car near the top of the nearest on-ramp with the freeway's outer
## lane busy (seen from above), `pullout` the nearest parked car that can pull out, with a car
## coming past in the kerb lane that it waits for. The traffic stops driving itself (its physics
## tick off) and moves only by advance_shot(), so a sequence of stills is exact.
static func stage_for_shot(tm: TrafficManager, kind: String, cam: Camera3D) -> String:
	if tm == null or cam == null:
		return ""
	tm.staged = true
	for c in tm.cars.duplicate():
		if is_instance_valid(c):
			tm._retire(c)
	tm.cars.clear()
	tm.set_physics_process(false)
	var plan := tm.plan
	var cp := WorldState.to_world(cam.global_position)
	var here := Vector2(cp.x, cp.z)
	match kind:
		"bus":
			var best := []
			var bd := INF
			var center := plan.block_index_at(here)
			for axis: int in [CityPlan.AXIS_X, CityPlan.AXIS_Z]:
				var c0 := center.x if axis == CityPlan.AXIS_X else center.y
				for index in range(c0 - 6, c0 + 7):
					if BigVehicles.route_of(plan, axis, index) == 0 or lanes_of(plan, axis, index) < 2 or tm._rail_street(axis, index):
						continue
					var cross := CityPlan.AXIS_Z if axis == CityPlan.AXIS_X else CityPlan.AXIS_X
					var k0 := plan._index_at(cross, here.y if axis == CityPlan.AXIS_X else here.x)
					for k in range(k0 - 4, k0 + 5):
						for dir: int in [1, -1]:
							var stop := BigVehicles.block_stop(plan, axis, index, k, dir)
							if is_nan(stop) or not plan.road_open(axis, index, stop - float(dir) * 110.0) or not plan.road_open(axis, index, stop + float(dir) * 40.0):
								continue
							var road := plan.road_pos(axis, index)
							var q := Vector2(road, stop) if axis == CityPlan.AXIS_X else Vector2(stop, road)
							if plan.zone_at(q) != MacroMap.Zone.CITY:
								continue
							var d := q.distance_to(here)
							if d < bd:
								bd = d
								best = [axis, index, k, dir, stop]
			if best.is_empty():
				return ""
			var axis: int = best[0]
			var index: int = best[1]
			var dir: int = best[3]
			var stop: float = best[4]
			var lanes := lanes_of(plan, axis, index)
			var bus := tm.place_car(axis, index, dir, lanes - 1, stop - float(dir) * 12.0, 3.0, false, BigVehicles.BUS)
			bus.traffic.dwell_need = 60.0
			advance_shot(tm, 6.0)
			_shot_greens(tm, axis, index, int(best[2]) + (0 if dir > 0 else 1))
			var car := tm.place_car(axis, index, dir, lanes - 1, stop - float(dir) * 70.0, 9.0, false)
			car.traffic.ai = true
			tm.set_meta("shot_car", car)
			# Behind and above the car, off the kerb on its side, looking up the road at the bus.
			var side := float(-dir if axis == CityPlan.AXIS_X else dir)
			# Over the carriageway, high behind the car, looking up the road past it at the bus.
			var lat := plan.road_pos(axis, index) + side * 1.0
			var along := stop - float(dir) * 74.0
			var e := Vector2(lat, along) if axis == CityPlan.AXIS_X else Vector2(along, lat)
			var target := Vector2(plan.road_pos(axis, index) + side * 3.0, stop - float(dir) * 22.0)
			if axis != CityPlan.AXIS_X:
				target = Vector2(target.y, target.x)
			return _eye_string(plan, e, 11.0, target, 0.0)
		"merge":
			var fw := tm._freeway()
			if fw == null:
				return ""
			var pick := {}
			var pri := -1
			var pd := INF
			for ri in fw.routes.size():
				for ramp: Dictionary in ramps_of(tm, fw, ri):
					if not bool(ramp.on):
						continue
					var m: Vector3 = ramp_point(ramp, 0.0)[0]
					var d := Vector2(m.x, m.z).distance_to(here)
					if d < pd:
						pd = d
						pick = ramp
						pri = ri
			if pick.is_empty():
				return ""
			for c in tm.freeway_cars.duplicate():
				if is_instance_valid(c):
					tm._retire(c)
			tm.freeway_cars.clear()
			var t0 := float(pick.t)
			# The outer lane of the -t carriageway: a car just past the merge point and one coming,
			# the merging car waits for the gap between them.
			for spec: Array in [[t0 - 30.0, 3, 23.0], [t0 + 70.0, 3, 24.0], [t0 + 20.0, 2, 26.0], [t0 - 60.0, 1, 27.0], [t0 + 40.0, 0, 28.0]]:
				var fc := tm.place_freeway_car(int(pri), float(spec[0]), -1, -1, float(spec[2]))
				var width := float(fw.routes[pri].width)
				fc.traffic.li = int(spec[1])
				fc.traffic.lane = -Freeway.lane_fraction(width, int(spec[1]))
				tm._place_freeway_car(fc, fw)
			tm._spawn_ramp_car(int(pri), pick)
			var rc: Vehicle = tm.freeway_cars.back()
			rc.traffic.u = 0.42
			rc.traffic.v = 15.0
			rc.global_transform = ramp_xform(rc)
			tm.set_meta("shot_car", rc)
			var m0: Vector3 = ramp_point(pick, 0.15)[0]
			var dir2: Vector2 = (fw.point_at(int(pri), t0)[1] as Vector2) * -1.0
			var nrm := Vector2(-dir2.y, dir2.x)
			var e3 := Vector2(m0.x, m0.z) - dir2 * 30.0 + nrm * 25.0
			return _eye_string(plan, e3, m0.y - plan.height_at(e3) + 36.0, Vector2(m0.x, m0.z) + dir2 * 22.0, m0.y, true)
		"pullout":
			var list := pullout_candidates(tm)
			var best_car: Vehicle = null
			var bd2 := INF
			for c: Vehicle in list:
				var d := c.global_position.distance_to(cam.global_position)
				if d < bd2:
					bd2 = d
					best_car = c
			if best_car == null:
				return ""
			var road := pullout_road(tm, best_car)
			pullout(tm, best_car)
			var axis: int = road[0]
			var index: int = road[1]
			var dir: int = road[2]
			var w := WorldState.to_world(best_car.global_position)
			var along := w.z if axis == CityPlan.AXIS_X else w.x
			var lanes := lanes_of(plan, axis, index)
			var cross := CityPlan.AXIS_Z if axis == CityPlan.AXIS_X else CityPlan.AXIS_X
			_shot_greens(tm, axis, index, plan._index_at(cross, along) + (1 if dir > 0 else 0))
			var passer := tm.place_car(axis, index, dir, lanes - 1, along - float(dir) * 26.0, 8.0, false)
			tm.set_meta("shot_car", best_car)
			tm.set_meta("shot_passer", passer)
			# Over the far carriageway, a little behind and above, looking at the parked car.
			var side := float(-dir if axis == CityPlan.AXIS_X else dir)
			var lat := plan.road_pos(axis, index) - side * 3.0
			var e := Vector2(lat, along - float(dir) * 13.0) if axis == CityPlan.AXIS_X else Vector2(along - float(dir) * 13.0, lat)
			var target := Vector2(w.x, w.z) + (Vector2(0.0, float(dir)) if axis == CityPlan.AXIS_X else Vector2(float(dir), 0.0)) * 5.0
			return _eye_string(plan, e, 4.5, target, 0.6)
	return ""


## Moves the staged traffic on by `seconds` (in 1/60 s steps): the streets, the freeway and its
## ramps, the signals' clock, the lamps.
static func advance_shot(tm: TrafficManager, seconds: float) -> void:
	var dt := 1.0 / 60.0
	for i in int(round(seconds / dt)):
		TrafficSignals.advance(dt)
		clock += dt
		tm._drive_streets(dt)
		tm._drive_freeway(dt)
		for c in tm.cars + tm.freeway_cars:
			if is_instance_valid(c):
				c._tick_lights(dt)


## Green at junction k0 of road (axis, index) (force() sets the one shared clock, so only one
## junction can be chosen).
static func _shot_greens(tm: TrafficManager, axis: int, index: int, k0: int) -> void:
	var node := Vector2i(index, k0) if axis == CityPlan.AXIS_X else Vector2i(k0, index)
	if TrafficSignals.is_signal(tm.plan, node.x, node.y):
		TrafficSignals.force(tm.plan, node.x, node.y, axis, TrafficSignals.Light.GREEN, 0.05)


## "x,y,z,yaw,pitch" for a camera at `e` (true world XZ) `height` metres over the ground, looking
## at `target` at `target_y` metres over the ground there (`absolute`: that height in the world).
static func _eye_string(plan: CityPlan, e: Vector2, height: float, target: Vector2, target_y: float, absolute: bool = false) -> String:
	var y := plan.height_at(e) + height
	var ty := target_y if absolute else plan.height_at(target) + target_y
	var d := Vector3(target.x - e.x, ty - y, target.y - e.y)
	var yaw := rad_to_deg(atan2(-d.x, -d.z))
	var pitch := rad_to_deg(atan2(d.y, Vector2(d.x, d.z).length()))
	return "%.2f,%.2f,%.2f,%.2f,%.2f" % [e.x, y, e.y, yaw, pitch]
