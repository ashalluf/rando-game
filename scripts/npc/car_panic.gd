class_name CarPanic
extends RefCounted
## Drivers react to chaos (car-panic, fleet wave 2, 2026-10-05). Gunfire or a blast near a street
## traffic car (Pedestrian.alarm(), which every gun, blast and police round calls) makes its
## driver do one of:
##
## * BRAKE   stamp on the brake, stand on the hazards a few seconds, drive on.
## * SWERVE  brake hard and jink away from the threat inside the lane's room, then back.
## * KERB    swing over the parking lane and up the kerb with two wheels (only where the kerb is
##           clear: no parked car, nobody standing there, no lamp or hydrant), sit it out on the
##           hazards, then back down into the lane (or leave it there and run: ABANDON on the kerb).
## * REVERSE threat ahead: stop and back away from it, as far as the car behind and the junction
##           behind allow, then drive on.
## * ABANDON stop, the driver's door swings open (ErrandProps) and the driver gets out and runs
##           (a Pedestrian with the panic run, across the road away from the threat on a
##           StreetErrands road path - the traffic brakes for them as for a jaywalker); the cabin
##           trace empties (CarCabin) and the car stays where it stopped, door open, lamps off. The
##           player can take it (enter_vehicle: it drops out of the traffic as nobody's crime).
## * FLOOR   threat behind, or caught in a junction: put the foot down and get out of there.
##
## Cars behind a car stopped in their lane honk (TrafficAI.honk, "panic"); on a street with two
## lanes each way TrafficAI passes it (it reads as double-parked, `dp_at`), on a one-lane street
## the car behind goes round it on the wrong side once the oncoming lane is clear (ROUND), and
## oncoming cars that meet it stop and let it through (YIELD).
##
## Every state lives in the car's traffic dict under `cp` and is driven by street_tick(), one
## hook line at the top of TrafficManager._drive_street(); everything else the traffic does is
## untouched. Nothing here reports a crime: only the shot or the blast itself, as before, and a
## person hit. Kinds are rolled from a hash of the car and the alarm, never the traffic's rng.
## `CAR_PANIC=0` in the environment turns it off (the A/B).

static var enabled: bool = OS.get_environment("CAR_PANIC") != "0"

enum Kind { BRAKE, SWERVE, KERB, REVERSE, ABANDON, FLOOR, ROUND, YIELD }
enum Phase { STOP, HOLD, MOVE, BACK }

## Most cars panicking at once (the nearest first).
const MAX_PANIC := 12
## A driver hears gunfire this share of the alarm's radius away (glass and engine noise), a
## blast all of it.
const HEAR_GUN := 0.85
const HEAR_BLAST := 1.0
## Near: under this share of the hearing distance the stronger reactions are likelier.
const NEAR_SHARE := 0.45
## Braking (m/s squared): a hard stop near the threat, firmer than comfortable further off.
const STOP_DECEL := Vector2(8.2, 5.2)
## Seconds a driver sits it out on the hazards after stopping (BRAKE, SWERVE, KERB, REVERSE).
const HOLD_SECONDS := Vector2(2.6, 7.5)
## The jink sideways (m) and how fast the car moves across while it still rolls (m/s per m/s).
const SWERVE_LAT := 1.2
const LAT_PER_SPEED := 0.42
## The kerb: crawl speed while it swings over and up (m/s), how far in from the kerb face the
## car's centre stands (m; two wheels up), and its roll once up there (radians).
const KERB_CRAWL := 2.8
const KERB_IN := 0.3
const KERB_ROLL := 0.085
## Reversing (m/s) and how far (m).
const REVERSE_SPEED := 3.6
const REVERSE_DIST := Vector2(7.0, 17.0)
## Pulling away again: target speed and lateral rate (m/s).
const RESUME_SPEED := 6.0
const RESUME_LAT := 0.75
## FLOOR: cruise speed gain and how long.
const FLOOR_GAIN := 1.6
const FLOOR_SECONDS := Vector2(5.0, 8.0)
## ABANDON: seconds after the car stands before the door opens.
const DOOR_DELAY := Vector2(0.35, 1.1)
## Cars behind: how close and how long stopped before they honk, and before one goes round (s).
const BEHIND_REACH := 16.0
const HONK_AFTER := 1.2
const ROUND_PATIENCE := 3.5
## ROUND: crawl out, pass speed (m/s), the clearance kept to the stopped car's side (m), how far
## up the oncoming lane must be clear before starting (m), and how close an oncoming car may be
## asked to stop for it (m ahead).
const ROUND_CRAWL := 2.2
const ROUND_SPEED := 5.5
const ROUND_SIDE := 0.5
const ROUND_CLEAR := 95.0
const YIELD_REACH := 70.0

## Counters for the checks and the HUD (kind names, "honk", "round", "yield", "driver").
static var counts: Dictionary = {}
## The last reactions: [kind, car instance id].
static var log: Array = []
## Tests and stills: force every reaction to this Kind (-1 rolls).
static var force_kind: int = -1
static var _events: int = 0
static var _last_ms: int = -100000
static var _last_at: Vector3 = Vector3.INF
static var _tm: TrafficManager


## The city's TrafficManager (the streamer's "Traffic"; found through a traffic car when the city
## is not the current scene, as in the smoke test), cached.
static func traffic_of(tree: SceneTree) -> TrafficManager:
	if _tm != null and is_instance_valid(_tm) and _tm.is_inside_tree():
		return _tm
	_tm = null
	if tree.current_scene:
		_tm = tree.current_scene.get_node_or_null("Traffic") as TrafficManager
	if _tm == null:
		for n in tree.get_nodes_in_group("vehicle"):
			if n.get_parent() is TrafficManager:
				_tm = n.get_parent() as TrafficManager
				break
	return _tm


static func count(what: String) -> void:
	counts[what] = int(counts.get(what, 0)) + 1


# --- Hearing it ---------------------------------------------------------------------------------

## Pedestrian.alarm(): a shot or a blast at `at` (scene position) heard `radius` metres off.
static func alarm(tree: SceneTree, at: Vector3, radius: float, blast: bool) -> void:
	if not enabled or tree == null:
		return
	var now := Time.get_ticks_msec()
	if not blast and now - _last_ms < 300 and at.distance_to(_last_at) < 12.0:
		return
	_last_ms = now
	_last_at = at
	var tm := traffic_of(tree)
	if tm == null or tm.plan == null:
		return
	var reach := radius * (HEAR_BLAST if blast else HEAR_GUN)
	_events += 1
	var busy := 0
	var heard: Array = []
	for car: Vehicle in tm.cars:
		if not is_instance_valid(car) or not car.is_inside_tree() or not car.is_traffic():
			continue
		var t: Dictionary = car.traffic
		if t.has("cp"):
			var k := int((t.cp as Dictionary).k)
			if k != Kind.ROUND and k != Kind.YIELD and k != Kind.FLOOR:
				busy += 1
				continue
		if not _eligible(car, t):
			continue
		var d := car.global_position.distance_to(at)
		if d < reach:
			heard.append([d, car])
	heard.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for e: Array in heard:
		if busy >= MAX_PANIC:
			break
		if start(tm, e[1], at, float(e[0]) / maxf(reach, 1.0), blast):
			busy += 1


static func _eligible(car: Vehicle, t: Dictionary) -> bool:
	if not t.has("axis") or not t.has("speed") or t.has("pull") or t.has("police") or t.has("emergency"):
		return false
	if car.driver != null or car.is_in_group("police_car") or car.is_in_group("emergency_unit"):
		return false
	return t.has("along")


## Starts `car`'s reaction to a threat at `at` (scene position), `near` 0 at the threat .. 1 at
## the edge of hearing. True if the driver reacts.
static func start(tm: TrafficManager, car: Vehicle, at: Vector3, near: float, blast: bool) -> bool:
	var t: Dictionary = car.traffic
	var f := _frame(tm, car)
	var wp: Vector3 = t.get("wp", WorldState.to_world(car.global_position))
	var th := WorldState.to_world(at)
	var rel := Vector2(th.x - wp.x, th.z - wp.z)
	var ahead: float = rel.dot(f.fwd)
	var side: float = rel.dot(f.kerb_dir)
	var h := absi(hash([car.get_instance_id(), _events, "car_panic"]))
	var u := float(h % 10007) / 10007.0
	var w := float((h / 10007) % 997) / 997.0
	var close := near < NEAR_SHARE or (blast and near < 0.65)
	var kind := Kind.BRAKE
	if force_kind >= 0:
		kind = force_kind
	elif BigVehicles.is_big(car.body_type) or t.has("bus") or t.has("work"):
		kind = Kind.BRAKE
	elif f.in_box:
		kind = Kind.FLOOR
	elif ahead < -6.0 and near < 0.7 and u < 0.55:
		kind = Kind.FLOOR
	elif close:
		kind = _pick(u, [[Kind.ABANDON, 0.3], [Kind.REVERSE, 0.2], [Kind.KERB, 0.2], [Kind.SWERVE, 0.15], [Kind.BRAKE, 1.0]])
	else:
		kind = _pick(u, [[Kind.BRAKE, 0.4], [Kind.SWERVE, 0.25], [Kind.KERB, 0.12], [Kind.REVERSE, 0.13], [Kind.ABANDON, 1.0]])
	# What the street allows.
	if kind == Kind.REVERSE and (ahead < 2.0 and force_kind < 0):
		kind = Kind.KERB
	if kind == Kind.KERB and not kerb_clear(tm, car, f):
		kind = Kind.SWERVE
	if kind == Kind.ABANDON and force_kind < 0 and not _crowd_room_possible(tm, car):
		kind = Kind.BRAKE
	if kind == Kind.FLOOR and force_kind < 0 and float(t.get("v", 0.0)) < 1.0 and not f.in_box:
		kind = Kind.BRAKE
	TrafficAI.end_move(t)
	t.erase("dp_at")
	t.erase("park_at")
	var cp := {"k": kind, "ph": Phase.STOP, "t": 0.0, "age": 0.0, "th": Vector2(th.x, th.z),
		"lat": f.lat, "lane0": float(t.lane), "w": w, "near": near}
	match kind:
		Kind.FLOOR:
			cp.speed0 = float(t.speed)
			cp.hold = lerpf(FLOOR_SECONDS.x, FLOOR_SECONDS.y, w)
			t.speed = float(t.speed) * FLOOR_GAIN
		Kind.SWERVE:
			# Away from the threat: toward the kerb if it is on the far side, else in toward the
			# centre line, as far as the lane's room allows.
			var two := TrafficAI.lanes_of(tm.plan, int(f.axis), int(f.index)) >= 2
			var room_in := minf(maxf(0.0, f.room_kerb), 0.5 if two else SWERVE_LAT)
			var to_kerb := side < 0.0
			var amount := room_in if to_kerb else (0.45 if two else 0.55)
			if to_kerb and amount < 0.25:
				amount = -0.45
			elif not to_kerb:
				amount = -amount
			cp.lat_to = f.lat + f.kerb_sign * amount
		Kind.KERB:
			cp.lat_to = f.kerb_sign * (f.w2 - KERB_IN)
		Kind.ABANDON:
			cp.lat_to = f.lat + f.kerb_sign * minf(0.45, maxf(0.0, f.room_kerb))
		_:
			cp.lat_to = f.lat
	cp.decel = lerpf(STOP_DECEL.x, STOP_DECEL.y, clampf(near, 0.0, 1.0))
	cp.hold = cp.get("hold", lerpf(HOLD_SECONDS.x, HOLD_SECONDS.y, w))
	cp.rev_left = lerpf(REVERSE_DIST.x, REVERSE_DIST.y, w)
	t.cp = cp
	t.erase("cpw")
	var name: String = Kind.keys()[kind]
	count(name.to_lower())
	log.append([name, car.get_instance_id()])
	if log.size() > 64:
		log.pop_front()
	return true


static func _pick(u: float, table: Array) -> int:
	for e: Array in table:
		if u < float(e[1]):
			return int(e[0])
		u -= float(e[1])
	return int((table[table.size() - 1] as Array)[0])


# --- Geometry ------------------------------------------------------------------------------------

## Where `car` is on its road: forward and kerb directions (true world XZ), the road's centre and
## half width, the kerb side's sign in road offsets, the car's lateral offset from the centre
## line, how much room toward the kerb the lane leaves it, the next junction and the last.
static func _frame(tm: TrafficManager, car: Vehicle) -> Dictionary:
	var plan := tm.plan
	var t: Dictionary = car.traffic
	var axis: int = t.axis
	var index: int = t.index
	var dir: int = t.dir
	var wp: Vector3 = t.get("wp", WorldState.to_world(car.global_position))
	var along: float = wp.z if axis == CityPlan.AXIS_X else wp.x
	var across: float = wp.x if axis == CityPlan.AXIS_X else wp.z
	var road := plan.road_pos(axis, index)
	var width := plan.road_width(axis, index)
	var lane0 := float(t.get("cp", {}).get("lane0", t.lane))
	var kerb_sign := signf(lane0) if lane0 != 0.0 else (-float(dir) if axis == CityPlan.AXIS_X else float(dir))
	var fwd := Vector2(0.0, float(dir)) if axis == CityPlan.AXIS_X else Vector2(float(dir), 0.0)
	var kerb_dir := Vector2(kerb_sign, 0.0) if axis == CityPlan.AXIS_X else Vector2(0.0, kerb_sign)
	var cross_axis := CityPlan.AXIS_Z if axis == CityPlan.AXIS_X else CityPlan.AXIS_X
	var cross_index := plan._index_at(cross_axis, along) + (1 if dir > 0 else 0)
	var cw := plan.road_width(cross_axis, cross_index)
	var to_centre := (plan.road_pos(cross_axis, cross_index) - along) * float(dir)
	var prev_index := cross_index - dir
	var half := float(t.get("half", 2.4))
	var rear := float(t.get("rear", half))
	var past := (along - plan.road_pos(cross_axis, prev_index)) * float(dir) - plan.road_width(cross_axis, prev_index) * 0.5
	var cw_w := float(car._dims().get("width", 1.9))
	var lat := across - road
	# Room toward the kerb from where it is: to the parked cars' inner side (or the kerb).
	var room := CityPlan.parking_offset(width) - 1.0 - cw_w * 0.5 - 0.2 - absf(lat)
	return {"axis": axis, "index": index, "dir": dir, "along": along, "road": road, "w2": width * 0.5,
		"kerb_sign": kerb_sign, "fwd": fwd, "kerb_dir": kerb_dir, "lat": lat, "room_kerb": room,
		"to_line": to_centre - cw * 0.5 - half, "past": past - rear, "half": half, "rear": rear,
		"width": cw_w, "in_box": past - rear < 0.5 or to_centre - cw * 0.5 - half < 0.5}


## True when `car` can swing over and up its kerb here: no car parked or standing in the way, no
## person on the spot, nothing solid (lamps, hydrants, signal poles) on the pavement there, and
## the junction ahead not in the way.
static func kerb_clear(tm: TrafficManager, car: Vehicle, f: Dictionary) -> bool:
	if float(f.to_line) < 14.0:
		return false
	var along_c: float = float(f.along) + float(f.dir) * 5.0
	var lat_c: float = float(f.kerb_sign) * (float(f.w2) - KERB_IN)
	var p := Vector2(float(f.road) + lat_c, along_c) if int(f.axis) == CityPlan.AXIS_X else Vector2(along_c, float(f.road) + lat_c)
	var span := float(f.half) + 6.0
	var tree := car.get_tree()
	for n in tree.get_nodes_in_group("vehicle"):
		var o := n as Node3D
		if o == null or o == car or not o.is_inside_tree():
			continue
		var op := WorldState.to_world(o.global_position)
		var d := Vector2(op.x - p.x, op.z - p.y)
		var da := absf(d.y if int(f.axis) == CityPlan.AXIS_X else d.x)
		var dl := absf(d.x if int(f.axis) == CityPlan.AXIS_X else d.y)
		if da < span + 3.0 and dl < 2.6:
			return false
	for n in tree.get_nodes_in_group("pedestrian"):
		var o := n as Node3D
		if o == null or not o.is_inside_tree():
			continue
		var op := WorldState.to_world(o.global_position)
		var d := Vector2(op.x - p.x, op.z - p.y)
		var da := absf(d.y if int(f.axis) == CityPlan.AXIS_X else d.x)
		var dl := absf(d.x if int(f.axis) == CityPlan.AXIS_X else d.y)
		if da < span and dl < 2.5:
			return false
	# Solid street furniture on the pavement edge (a shape query, once per decision).
	var space := car.get_world_3d().direct_space_state if car.is_inside_tree() else null
	if space == null:
		return true
	var box := BoxShape3D.new()
	var len := span * 2.0
	box.size = Vector3(float(f.width) + 0.4, 1.3, len) if int(f.axis) == CityPlan.AXIS_X else Vector3(len, 1.3, float(f.width) + 0.4)
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = box
	q.collision_mask = 1 | 4
	var y := tm._relief(p) + CityChunk.SIDEWALK_TOP + 0.95
	q.transform = Transform3D(Basis.IDENTITY, WorldState.to_local(Vector3(p.x, y, p.y)))
	q.exclude = [car.get_rid()]
	return space.intersect_shape(q, 1).is_empty()


## True when an abandoning driver could be somebody: a FULL chunk by the car with crowd room.
static func _crowd_room_possible(tm: TrafficManager, car: Vehicle) -> bool:
	var streamer := tm.get_parent()
	if streamer == null or not streamer.has_method("take_crowd_room"):
		return false
	var wp := WorldState.to_world(car.global_position)
	var chunk: Variant = (streamer.get("chunks") as Dictionary).get(tm.plan.chunk_index_at(Vector2(wp.x, wp.z)))
	return chunk is Node3D and int((chunk as Node).get("level")) == CityChunk.Level.FULL


# --- Driving it ----------------------------------------------------------------------------------

## TrafficManager._drive_street(), first thing for a car with a `cp` state: true when this drove
## the car this tick (the rest of _drive_street is skipped), false to let the traffic drive it.
static func street_tick(tm: TrafficManager, car: Vehicle, leader: Vehicle, groups: Dictionary, delta: float) -> bool:
	var t: Dictionary = car.traffic
	var cp: Dictionary = t.cp
	cp.age = float(cp.age) + delta
	cp.t = float(cp.t) + delta
	if not enabled:
		_end(t)
		return false
	match int(cp.k):
		Kind.FLOOR:
			if float(cp.t) > float(cp.hold):
				t.speed = float(cp.speed0)
				_end(t)
			return false
		Kind.ROUND:
			return _round_tick(tm, car, leader, groups, delta)
		Kind.YIELD:
			return _yield_tick(tm, car, leader, delta)
	return _panic_tick(tm, car, leader, groups, delta)


static func _panic_tick(tm: TrafficManager, car: Vehicle, leader: Vehicle, groups: Dictionary, delta: float) -> bool:
	var t: Dictionary = car.traffic
	var cp: Dictionary = t.cp
	var f := _frame(tm, car)
	var kind := int(cp.k)
	var v := float(t.get("v", 0.0))
	var lat := float(cp.lat)
	var lat_to := float(cp.lat_to)
	var lat_rate := 0.0
	t.rev = false
	match int(cp.ph):
		Phase.STOP:
			var crawl := KERB_CRAWL if kind == Kind.KERB and absf(lat_to - lat) > 0.05 else 0.0
			if v > crawl:
				v = maxf(v - float(cp.decel) * delta, crawl)
			else:
				v = move_toward(v, crawl, 2.0 * delta)
			lat_rate = _lat_step(lat, lat_to, maxf(v, 0.8 if crawl > 0.0 else 0.0) * LAT_PER_SPEED * (1.6 if kind == Kind.KERB else 1.0), delta)
			if v <= 0.0 and (absf(lat_to - lat - lat_rate * delta) < 0.06 or crawl == 0.0):
				v = 0.0
				cp.ph = Phase.MOVE if kind == Kind.REVERSE else Phase.HOLD
				cp.t = 0.0
				if kind == Kind.ABANDON:
					PanicCar.on(car, cp.th)
		Phase.HOLD:
			v = 0.0
			t.hazard = true
			if kind != Kind.ABANDON and float(cp.t) > float(cp.hold):
				cp.ph = Phase.BACK
				cp.t = 0.0
		Phase.MOVE:
			t.hazard = true
			t.rev = true
			v = move_toward(v, -REVERSE_SPEED, 3.0 * delta)
			var room_back := _room_behind(tm, car, groups, f)
			if room_back < 0.4 or float(cp.rev_left) <= 0.0:
				v = move_toward(minf(v, 0.0), 0.0, 6.0 * delta)
				if v >= 0.0:
					v = 0.0
					cp.ph = Phase.HOLD
					cp.hold = 1.0 + 2.0 * float(cp.w)
					cp.t = 0.0
			else:
				v = maxf(v, -sqrt(2.0 * 4.0 * maxf(room_back - 0.3, 0.0)))
			cp.rev_left = float(cp.rev_left) + v * delta
		Phase.BACK:
			t.erase("hazard")
			var lane := float(cp.lane0)
			if float(t.lane) != lane:
				# Off the lanes (on the kerb): back into its lane once there is room there.
				var key := TrafficManager.lane_key(int(f.axis), int(f.index), int(f.dir), lane)
				if tm._group_clear(groups, key, float(f.along), float(f.half) + 5.0, car, int(f.dir)):
					t.lane = lane
				else:
					cp.t = 0.0
					_place(tm, car, f, 0.0, lat, 0.0)
					return true
			v = move_toward(v, RESUME_SPEED, 1.8 * delta)
			var target := lane
			lat_rate = _lat_step(lat, target, maxf(v, 0.5) * 0.3 + RESUME_LAT * 0.5, delta)
			if absf(target - lat) < 0.04:
				_end(t)
				t.v = v
				car.traffic_speed = v
				return false
	# Moving forward: never into what is ahead in the lane, nor into the junction past a kerb.
	var step := v * delta
	if step > 0.0:
		var room := _room_ahead(car, leader, f)
		if (kind == Kind.KERB or float(t.lane) != float(cp.lane0) or int(cp.ph) == Phase.BACK) and float(f.to_line) > 0.0:
			# Never over the stop line on its own: the traffic's own rules take the junction.
			room = minf(room, float(f.to_line) - (2.0 if kind == Kind.KERB else 0.3))
		if step > room:
			step = maxf(room, 0.0)
			v = minf(v, step / delta)
	lat += lat_rate * delta
	cp.lat = lat
	# Out of its lane altogether (up on the kerb): out of its lane's queue too, so the cars behind
	# drive on past (a lane offset nobody drives, by the kerb).
	if int(cp.ph) != Phase.BACK and absf(lat) > absf(float(cp.lane0)) + float(f.width) + 0.15 and float(t.lane) == float(cp.lane0):
		t.lane = float(f.kerb_sign) * (float(f.w2) + 0.5)
	# Standing in the lane: something to pass for the cars behind (TrafficAI reads `dp_at`), and
	# the ones stuck behind it honk and, on a one-lane street, go round.
	var standing := absf(v) < 0.5 and float(t.lane) == float(cp.lane0)
	if standing:
		t.dp_at = float(f.along)
		t.why = 4
		_behind(tm, car, groups, f, delta)
	else:
		t.erase("dp_at")
		t.why = 0
	t.v = v
	car.traffic_speed = absf(v)
	_place(tm, car, f, step, lat, lat_rate)
	return true


## Lateral rate (m/s) from `lat` toward `to` at most `rate`.
static func _lat_step(lat: float, to: float, rate: float, delta: float) -> float:
	var d := to - lat
	if absf(d) < 0.001 or rate <= 0.0:
		return 0.0
	return clampf(d / maxf(delta, 0.0001), -rate, rate)


## How far the nose may move before it touches the car ahead in its lane (m).
static func _room_ahead(car: Vehicle, leader: Vehicle, f: Dictionary) -> float:
	if leader == null or not is_instance_valid(leader) or not leader.is_traffic():
		return INF
	var lt: Dictionary = leader.traffic
	return (float(lt.get("along", 0.0)) - float(f.along)) * float(f.dir) - float(f.half) - float(lt.get("rear", lt.get("half", 2.4))) - 0.6


## How far the tail may back before it touches the car behind or reaches the junction behind (m).
static func _room_behind(tm: TrafficManager, car: Vehicle, groups: Dictionary, f: Dictionary) -> float:
	var room := float(f.past) - 1.0
	var t: Dictionary = car.traffic
	var key := TrafficManager.lane_key(int(f.axis), int(f.index), int(f.dir), float(t.lane))
	for o in groups.get(key, []):
		if o == car or not is_instance_valid(o):
			continue
		var ot: Dictionary = (o as Vehicle).traffic
		var d := (float(f.along) - float(ot.get("along", 0.0))) * float(f.dir)
		if d > 0.0:
			room = minf(room, d - float(f.rear) - float(ot.get("half", 2.4)) - 1.2)
	# The player (on foot or in a car) behind it.
	if not tm._player_block.is_empty():
		var rel: Vector3 = (tm._player_block[0] as Vector3) - (t.wp as Vector3)
		var back := -(rel.z if int(f.axis) == CityPlan.AXIS_X else rel.x) * float(f.dir)
		var latd := absf(rel.x if int(f.axis) == CityPlan.AXIS_X else rel.z)
		if back > 0.0 and latd < float(tm._player_block[1]) and absf(rel.y) < 3.0:
			room = minf(room, back - float(f.rear) - float(tm._player_block[2]) - 1.0)
	return room


## Places the car `step` metres on along its road at lateral offset `lat` from the centre line,
## nosed into its lateral motion, up on the kerb as far as it is over it.
static func _place(tm: TrafficManager, car: Vehicle, f: Dictionary, step: float, lat: float, lat_rate: float) -> void:
	var t: Dictionary = car.traffic
	var axis: int = f.axis
	var dir: int = f.dir
	var along := float(f.along) + float(dir) * step
	t.along = along
	var lane_pos := float(f.road) + lat
	var wp := Vector3(lane_pos, 0.0, along) if axis == CityPlan.AXIS_X else Vector3(along, 0.0, lane_pos)
	var here := tm._relief(Vector2(wp.x, wp.z))
	var forward := Vector3(0.0, 0.0, dir) if axis == CityPlan.AXIS_X else Vector3(dir, 0.0, 0.0)
	var ahead_h := tm._relief(Vector2(wp.x + forward.x * 4.0, wp.z + forward.z * 4.0))
	# Up the kerb: the outer wheels climb it as the car's outer half passes over the kerb face.
	var over := clampf((absf(lat) + float(f.width) * 0.5 - float(f.w2) - 0.1) / 0.5, 0.0, 1.0)
	var lift := (CityChunk.SIDEWALK_TOP - CityChunk.ROAD_TOP) * 0.55 * over
	wp.y = here + CityChunk.ROAD_TOP + car.road_lift() + lift
	var yaw := tm._heading(axis, dir)
	var v := float(t.get("v", 0.0))
	if lat_rate != 0.0:
		var go := maxf(absf(v), 1.5)
		var latv := clampf(lat_rate, -go * 0.5, go * 0.5)
		var vel := forward * go * (signf(v) if v < -0.1 else 1.0)
		vel += Vector3(latv, 0.0, 0.0) if axis == CityPlan.AXIS_X else Vector3(0.0, 0.0, latv)
		if v < -0.1:
			vel = -vel
		yaw = atan2(-vel.x, -vel.z)
	# The kerb is on the car's right: that side up.
	var roll := KERB_ROLL * over * (1.0 if signf(lat) == float(f.kerb_sign) else -1.0)
	t.wp = wp
	car.global_transform = Transform3D(Basis.from_euler(Vector3(atan2(ahead_h - here, 4.0), yaw, roll)), WorldState.to_local(wp))
	if not car.is_physics_processing():
		car._tick_lights(car.get_physics_process_delta_time())


## The cars stuck behind a car standing in their lane: they honk, and on a street with one lane
## each way the one right behind goes round once the oncoming lane is clear.
static func _behind(tm: TrafficManager, car: Vehicle, groups: Dictionary, f: Dictionary, delta: float) -> void:
	var t: Dictionary = car.traffic
	var key := TrafficManager.lane_key(int(f.axis), int(f.index), int(f.dir), float(t.lane))
	var best: Vehicle = null
	var bd := INF
	for o in groups.get(key, []):
		if o == car or not is_instance_valid(o):
			continue
		var ot: Dictionary = (o as Vehicle).traffic
		var d := (float(f.along) - float(ot.get("along", 0.0))) * float(f.dir)
		if d > 0.0 and d < bd:
			bd = d
			best = o
	if best == null:
		return
	var bt: Dictionary = best.traffic
	if bt.has("cp") or bt.has("lc_from"):
		return
	var gap := bd - float(f.rear) - float(bt.get("half", 2.4))
	if gap > BEHIND_REACH or float(bt.get("v", 0.0)) > 1.0:
		bt.erase("cpw")
		return
	bt.cpw = float(bt.get("cpw", 0.0)) + delta
	var wait := float(bt.cpw)
	if wait > HONK_AFTER * float(bt.get("m_patience", 3.0)) / 3.0:
		if TrafficAI.honk(tm, best, "panic", wait > 5.0):
			count("honk")
	var stays := int(t.cp.k) == Kind.ABANDON or (int(t.cp.ph) == Phase.HOLD and float(t.cp.hold) - float(t.cp.t) > 3.0)
	if not stays or wait < ROUND_PATIENCE:
		return
	if TrafficAI.enabled and TrafficAI.lanes_of(tm.plan, int(f.axis), int(f.index)) >= 2 and not tm._rail_street(int(f.axis), int(f.index)):
		return # TrafficAI passes it (it reads as double-parked)
	try_round(tm, best, car)


## `car` goes round `obs` (standing in its lane ahead) on the oncoming side, if the oncoming lane
## is clear far enough up the road and the stopped car is not at the junction. True if it started.
static func try_round(tm: TrafficManager, car: Vehicle, obs: Vehicle) -> bool:
	var f := _frame(tm, car)
	var ot: Dictionary = obs.traffic
	var obs_ahead := (float(ot.along) - float(f.along)) * float(f.dir)
	var obs_to_line := float(f.to_line) - obs_ahead
	if obs_to_line < float(ot.get("half", 2.4)) * 2.0 + 10.0 or bool(f.in_box):
		return false
	if not _oncoming_clear(tm, car, f, ROUND_CLEAR):
		return false
	var t: Dictionary = car.traffic
	TrafficAI.end_move(t)
	var ow := float(obs._dims().get("width", 1.9))
	var obs_lat := float(ot.get("cp", {}).get("lat", float(ot.lane)))
	t.cp = {"k": Kind.ROUND, "ph": Phase.STOP, "t": 0.0, "age": 0.0, "lat": f.lat, "lane0": float(t.lane),
		"obs": obs, "lat_to": obs_lat - float(f.kerb_sign) * (ow * 0.5 + float(f.width) * 0.5 + ROUND_SIDE)}
	t.erase("cpw")
	t.sig = -1
	count("round")
	return true


## True when no oncoming car on this road is between `car` and `reach` metres up the road.
static func _oncoming_clear(tm: TrafficManager, car: Vehicle, f: Dictionary, reach: float) -> bool:
	for o: Vehicle in tm.cars:
		if o == car or not is_instance_valid(o) or not o.is_traffic():
			continue
		var ot: Dictionary = o.traffic
		if int(ot.get("axis", -1)) != int(f.axis) or int(ot.get("index", -999999)) != int(f.index) or int(ot.get("dir", 0)) == int(f.dir):
			continue
		var d := (float(ot.get("along", 0.0)) - float(f.along)) * float(f.dir)
		if d > -8.0 and d < reach:
			return false
	return true


static func _round_tick(tm: TrafficManager, car: Vehicle, leader: Vehicle, groups: Dictionary, delta: float) -> bool:
	var t: Dictionary = car.traffic
	var cp: Dictionary = t.cp
	var f := _frame(tm, car)
	var obs: Variant = cp.obs
	var v := float(t.get("v", 0.0))
	var lat := float(cp.lat)
	var lat_rate := 0.0
	var obs_ok: bool = obs is Vehicle and is_instance_valid(obs) and (obs as Vehicle).is_traffic()
	var obs_gap := INF
	var past_obs := true
	var obs_lat := 0.0
	var sep := 0.0
	if obs_ok:
		var ot: Dictionary = (obs as Vehicle).traffic
		var d := (float(ot.along) - float(f.along)) * float(f.dir)
		obs_gap = d - float(f.half) - float(ot.get("rear", ot.get("half", 2.4)))
		past_obs = -d - float(f.rear) - float(ot.get("half", 2.4)) > 2.5
		obs_lat = float(ot.get("cp", {}).get("lat", float(ot.lane)))
		sep = float((obs as Vehicle)._dims().get("width", 1.9)) * 0.5 + float(f.width) * 0.5 + 0.15
	# Beside it or about to be: only with the sides clear of each other.
	var alongside := obs_ok and not past_obs and obs_gap < 0.6
	# Oncoming cars that meet it stop and let it through.
	if int(cp.ph) != Phase.BACK:
		for o: Vehicle in tm.cars:
			if o == car or not is_instance_valid(o) or not o.is_traffic():
				continue
			var ot: Dictionary = o.traffic
			if ot.has("cp") or int(ot.get("axis", -1)) != int(f.axis) or int(ot.get("index", -999999)) != int(f.index) or int(ot.get("dir", 0)) == int(f.dir):
				continue
			var d := (float(ot.get("along", 0.0)) - float(f.along)) * float(f.dir)
			if d > 0.0 and d < YIELD_REACH:
				ot.cp = {"k": Kind.YIELD, "t": 0.0, "age": 0.0, "obs": car}
				count("yield")
	match int(cp.ph):
		Phase.STOP:
			# Out round it at a crawl.
			v = move_toward(v, ROUND_CRAWL, 2.0 * delta)
			lat_rate = _lat_step(lat, float(cp.lat_to), 1.1, delta)
			if absf(float(cp.lat_to) - lat) < 0.08:
				cp.ph = Phase.MOVE
			if not obs_ok or float(cp.t) > 12.0:
				cp.ph = Phase.BACK
		Phase.MOVE:
			v = move_toward(v, ROUND_SPEED, 2.2 * delta)
			lat_rate = _lat_step(lat, float(cp.lat_to), 1.1, delta)
			if past_obs or not obs_ok or float(cp.t) > 15.0:
				cp.ph = Phase.BACK
		Phase.BACK:
			v = move_toward(v, RESUME_SPEED, 1.8 * delta)
			# Never back in across the stopped car's side: on past it first (or wait behind it).
			if not alongside:
				lat_rate = _lat_step(lat, float(cp.lane0), 1.0, delta)
			elif obs_ok:
				var keep := obs_lat + signf(lat - obs_lat) * sep
				if absf(lat - obs_lat) < sep:
					lat_rate = _lat_step(lat, keep, 1.0, delta)
			if absf(float(cp.lane0) - lat) < 0.04:
				t.sig = 0
				_end(t)
				t.v = v
				car.traffic_speed = v
				return false
	if int(cp.ph) == Phase.BACK and t.get("sig", 0) != 1:
		t.sig = 1
	var step := v * delta
	# The car past the stopped one (or, once back, its own leader) still holds it.
	var room := INF
	if int(cp.ph) == Phase.BACK and not alongside:
		room = _room_ahead(car, leader, f)
	elif obs_ok:
		# The nearest car of its lane ahead of both it and the stopped car.
		var from := maxf(float(((obs as Vehicle).traffic as Dictionary).along) * float(f.dir), float(f.along) * float(f.dir))
		for o in groups.get(TrafficManager.lane_key(int(f.axis), int(f.index), int(f.dir), float(t.lane)), []):
			if o == car or o == obs or not is_instance_valid(o):
				continue
			var oa := float((o as Vehicle).traffic.get("along", 0.0)) * float(f.dir)
			if oa > from:
				room = minf(room, oa - float(f.along) * float(f.dir) - float(f.half) - float((o as Vehicle).traffic.get("rear", 2.4)) - 1.0)
	room = minf(room, float(f.to_line) + 1.0)
	if alongside and absf((lat + lat_rate * delta) - obs_lat) < sep:
		room = minf(room, obs_gap - 0.5)
	if step > room:
		step = maxf(room, 0.0)
		v = minf(v, step / delta)
	lat += lat_rate * delta
	cp.lat = lat
	t.v = v
	t.why = 0
	car.traffic_speed = v
	_place(tm, car, f, step, lat, lat_rate)
	return true


static func _yield_tick(tm: TrafficManager, car: Vehicle, leader: Vehicle, delta: float) -> bool:
	var t: Dictionary = car.traffic
	var cp: Dictionary = t.cp
	var obs: Variant = cp.obs
	var f := _frame(tm, car)
	var going: bool = obs is Vehicle and is_instance_valid(obs) and (obs as Vehicle).is_traffic() \
		and ((obs as Vehicle).traffic as Dictionary).has("cp") and int(((obs as Vehicle).traffic.cp as Dictionary).k) == Kind.ROUND
	if going:
		var ot: Dictionary = (obs as Vehicle).traffic
		var d := (float(ot.along) - float(f.along)) * float(f.dir)
		if d < -3.0:
			going = false
	if not going or float(cp.t) > 20.0:
		_end(t)
		return false
	var v := maxf(float(t.get("v", 0.0)) - 6.0 * delta, 0.0)
	var step := v * delta
	var room := _room_ahead(car, leader, f)
	var ot2: Dictionary = (obs as Vehicle).traffic
	room = minf(room, (float(ot2.along) - float(f.along)) * float(f.dir) - float(f.half) - float(ot2.get("half", 2.4)) - 3.0)
	if step > room:
		step = maxf(room, 0.0)
		v = minf(v, step / delta)
	t.v = v
	car.traffic_speed = v
	_place(tm, car, f, step, float(f.lat), 0.0)
	return true


## Ends whatever `t`'s car was doing; the traffic drives it from here.
static func _end(t: Dictionary) -> void:
	t.erase("cp")
	t.erase("hazard")
	t.erase("rev")
	t.erase("cpw")
	if t.has("dp_at") and not t.has("dp"):
		t.erase("dp_at")


# --- The player and the abandoned car --------------------------------------------------------

## True for a car its driver ran from (ABANDON, standing): the player may get in.
static func is_abandoned(car: Vehicle) -> bool:
	return car.is_traffic() and car.traffic.has("cp") and int((car.traffic.cp as Dictionary).k) == Kind.ABANDON \
		and int((car.traffic.cp as Dictionary).ph) == Phase.HOLD


## Player.enter_vehicle(): an abandoned traffic car leaves the traffic first, as nobody's crime.
static func take(car: Vehicle) -> void:
	if not is_abandoned(car):
		return
	var tm := traffic_of(car.get_tree())
	if tm:
		tm.cars.erase(car)
	Police.innocent = true
	car.drop_out_of_traffic()
	Police.innocent = false


## The driver who got out of `car`: a walker at its door, running from `threat` (true world XZ)
## across the road to the far pavement or up onto the near one, whichever is away from it, on a
## StreetErrands road path (the traffic brakes for them). Null without a FULL chunk or crowd room.
static func spawn_driver(car: Vehicle, threat: Vector2) -> Pedestrian:
	var tm := traffic_of(car.get_tree())
	if tm == null or not car.is_traffic():
		return null
	var plan := tm.plan
	var streamer := tm.get_parent()
	if streamer == null or not streamer.has_method("take_crowd_room"):
		return null
	var f := _frame(tm, car)
	var wp := WorldState.to_world(car.global_position)
	var pos := Vector2(wp.x, wp.z)
	var stand := WorldState.to_world(car.global_transform * ErrandProps.door_stand(car, 0.55))
	var door := Vector2(stand.x, stand.z)
	var kd: Vector2 = f.kerb_dir
	var fwd: Vector2 = f.fwd
	var rel := threat - pos
	# Away from the threat: over the road when it is on the kerb side, else up the near kerb.
	var far := rel.dot(kd) > 1.5
	var away := -signf(rel.dot(fwd)) if absf(rel.dot(fwd)) > 1.0 else 1.0
	var road := float(f.road)
	var off := (-1.0 if far else 1.0) * float(f.kerb_sign) * (float(f.w2) + 1.6)
	var a_kerb := float(f.along) + away * 7.0 * float(f.dir)
	var kerb := Vector2(road + off, a_kerb) if int(f.axis) == CityPlan.AXIS_X else Vector2(a_kerb, road + off)
	var a_mid := float(f.along) + away * 3.0 * float(f.dir)
	var mid_off := (-1.0 if far else 1.0) * float(f.kerb_sign) * (float(f.w2) - 0.8)
	var mid := Vector2(road + mid_off, a_mid) if int(f.axis) == CityPlan.AXIS_X else Vector2(a_mid, road + mid_off)
	if not far:
		# Round the back or the front of its own car to the near kerb.
		var a_end := float(f.along) + away * (float(f.half) + 1.2) * float(f.dir)
		var lat_d := float(f.lat) - float(f.kerb_sign) * (float(f.width) * 0.5 + 0.7)
		var end_pt := Vector2(road + lat_d, a_end) if int(f.axis) == CityPlan.AXIS_X else Vector2(a_end, road + lat_d)
		mid = end_pt
	var b := plan.block_index_at(kerb)
	var ring: Rect2 = plan.block(b.x, b.y).rect
	var chunk: Variant = (streamer.get("chunks") as Dictionary).get(plan.chunk_index_at(ring.get_center()))
	if not (chunk is Node3D) or int((chunk as Node).get("level")) != CityChunk.Level.FULL:
		return null
	if not streamer.take_crowd_room():
		return null
	var p := Pedestrian.new()
	p.setup(ring, plan.sidewalk_width, hash([plan.seed, car.get_instance_id(), "car_panic_driver"]))
	p.position = Vector3(door.x, (chunk as Node).call("ground_y", door.x, door.y) + 0.1 - (CityChunk.SIDEWALK_TOP - CityChunk.ROAD_TOP), door.y)
	(chunk as Node).add_child(p)
	p._visual.rotation.y = atan2(-(mid - door).x, -(mid - door).y)
	p._faced = true
	if StreetErrands.enabled:
		p.errand = {"steps": [{"do": "path", "pts": [mid, kerb], "road": true, "jay": [int(f.axis), int(f.index)]}], "i": 0}
	else:
		p.position = Vector3(kerb.x, (chunk as Node).call("ground_y", kerb.x, kerb.y) + 0.1, kerb.y)
	p._scare(WorldState.to_local(Vector3(threat.x, wp.y, threat.y)))
	count("driver")
	return p


# --- Stills (tools/glshot/still_shot.gd PANIC=...) -----------------------------------------------

## Stages a reaction for a still near `cam` and returns a free camera for it ("x,y,z,yaw,pitch",
## true world): the nearest one-lane street with a long block, a car driving up it with another
## behind it, and a shot by the far kerb ahead of it; `kind` is a Kind name (brake, swerve, kerb,
## reverse, abandon) and the reaction starts at once. The traffic's own tick is off: it moves only
## by advance_shot(), so a sequence of stills is exact. `side` "near" puts the camera on the car's
## kerb side.
static func stage_for_shot(tm: TrafficManager, kind: String, cam: Camera3D, side: String = "") -> String:
	if tm == null or cam == null:
		return ""
	tm.staged = true
	for c in tm.cars.duplicate():
		if is_instance_valid(c):
			tm._retire(c)
	tm.cars.clear()
	tm.set_physics_process(false)
	var plan := tm.plan
	var cpos := WorldState.to_world(cam.global_position)
	var here := Vector2(cpos.x, cpos.z)
	var best := []
	var bd := INF
	var c0 := plan.block_index_at(here)
	for axis: int in [CityPlan.AXIS_X, CityPlan.AXIS_Z]:
		var cross := CityPlan.AXIS_Z if axis == CityPlan.AXIS_X else CityPlan.AXIS_X
		var i0 := c0.x if axis == CityPlan.AXIS_X else c0.y
		var k0 := c0.y if axis == CityPlan.AXIS_X else c0.x
		for index in range(i0 - 6, i0 + 7):
			if TrafficAI.lanes_of(plan, axis, index) >= 2 or tm._rail_street(axis, index):
				continue
			for k in range(k0 - 6, k0 + 7):
				var lo := plan.road_pos(cross, k) + plan.road_width(cross, k) * 0.5
				var hi := plan.road_pos(cross, k + 1) - plan.road_width(cross, k + 1) * 0.5
				if hi - lo < 130.0:
					continue
				var road := plan.road_pos(axis, index)
				var q := Vector2(road, (lo + hi) * 0.5) if axis == CityPlan.AXIS_X else Vector2((lo + hi) * 0.5, road)
				if plan.zone_at(q) != MacroMap.Zone.CITY or not plan.road_open(axis, index, lo + 2.0) or not plan.road_open(axis, index, hi - 2.0):
					continue
				var d := q.distance_to(here)
				if d < bd:
					bd = d
					best = [axis, index, lo, hi]
	if best.is_empty():
		return ""
	var axis: int = best[0]
	var index: int = best[1]
	var lo: float = best[2]
	var dir := 1
	var k_name := kind.to_upper()
	force_kind = Kind.keys().find(k_name)
	var at := lo + 45.0
	var car: Vehicle = null
	# A kerb needs a clear stretch: walk up the block until one is.
	while at < float(best[3]) - 50.0:
		car = tm.place_car(axis, index, dir, 0, at, 9.0, false)
		TrafficAI.advance_shot(tm, 0.05)
		if k_name != "KERB" or kerb_clear(tm, car, _frame(tm, car)):
			break
		tm.cars.erase(car)
		tm._retire(car)
		car = null
		at += 8.0
	if car == null:
		return ""
	var follower := tm.place_car(axis, index, dir, 0, at - 24.0, 9.0, false)
	TrafficAI.advance_shot(tm, 0.05)
	var f := _frame(tm, car)
	var road := float(f.road)
	var ks := float(f.kerb_sign)
	# The shot: by the far kerb up ahead (behind the car for nothing; ahead for a reverse).
	var a_th := float(f.along) + float(dir) * (20.0 if k_name == "REVERSE" else 13.0)
	var l_th := road - ks * (float(f.w2) + 2.0)
	var th := Vector2(l_th, a_th) if axis == CityPlan.AXIS_X else Vector2(a_th, l_th)
	start(tm, car, WorldState.to_local(Vector3(th.x, tm._relief(th) + 1.2, th.y)), 0.25, false)
	force_kind = -1
	tm.set_meta("shot_car", car)
	tm.set_meta("shot_follower", follower)
	# The camera: on the far pavement (or the near one), level with a point just ahead of where
	# the car will stand, looking back at it and the car behind.
	# Over the oncoming lane (or the car's own kerb side, `near`), up the road, a little high,
	# looking back down at where the car will stand and the car behind it.
	var cam_side := ks * 0.45 if side == "near" else -ks * 0.35
	var e_lat := road + cam_side * float(f.w2)
	var e_al := float(f.along) + float(dir) * (float(OS.get_environment("PANIC_EYE_D")) if OS.get_environment("PANIC_EYE_D") != "" else 9.0)
	var e := Vector2(e_lat, e_al) if axis == CityPlan.AXIS_X else Vector2(e_al, e_lat)
	var t_al := float(f.along) + float(dir) * 2.0
	var t_lat := road + ks * 1.2
	var target := Vector2(t_lat, t_al) if axis == CityPlan.AXIS_X else Vector2(t_al, t_lat)
	return TrafficAI._eye_string(plan, e, float(OS.get_environment("PANIC_EYE_H")) if OS.get_environment("PANIC_EYE_H") != "" else 2.6, target, 0.7)


## Moves the staged traffic, the abandoned cars' doors and the drivers who ran on by `seconds`.
static func advance_shot(tm: TrafficManager, seconds: float) -> void:
	var dt := 1.0 / 60.0
	for i in int(round(seconds / dt)):
		TrafficAI.advance_shot(tm, dt)
		for c: Vehicle in tm.cars:
			if not is_instance_valid(c):
				continue
			var pc := c.get_node_or_null("PanicCar") as PanicCar
			if pc:
				pc.step(dt)
				if pc.driver != null and is_instance_valid(pc.driver):
					pc.driver._physics_process(dt)
