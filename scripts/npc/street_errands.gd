class_name StreetErrands
extends RefCounted
## The pavement's comings and goings (GAME_PLAN G5's second pass, 2026-10-05): within
## Pedestrian.life_range of the player, a walker now and then goes somewhere real -
## - waits at a bus stop (the slots in front of the shelter) and boards the bus when its doors open
##   at the stop: walks to the front door and is gone inside (the traced cabin shows the riders);
##   riders and people out of the shops get off at the rear door at a later stop and walk away;
## - walks round a parked car to its driver's door, which opens (ErrandProps), gets in, the lamps
##   come on and the car pulls out of its space into the traffic (pull_out(): the parked physics
##   car becomes a kinematic traffic car whose lane offset eases in from the kerb); and the other
##   way, a traffic car pulls into a free kerb space (TrafficManager's `park_at`, a stop like a
##   bus's) and its driver gets out and walks off - or, for a delivery van or a box truck, carries
##   a bag or wheels a hand truck of boxes from the back of the truck into a shop and back;
## - jaywalks: crosses mid-block where the parking lanes have a gap and nothing is coming (some
##   run), and traffic brakes and honks for them (jaywalker_gap());
## - walks into a shop through its door bay (the door ShopfrontKit and building.gdshader put there,
##   from the same shop rolls: note_shop_doors()) and disappears behind the glass, and later comes
##   out of one, sometimes with a bag.
## Nobody is made or lost: whoever goes inside a shop, a bus or a car waits hidden (no collision, no
## draw) and comes out of a door later; a driver getting out of a car that just parked is one of
## them when there is one near, else a new walker under the crowd cap.
##
## An errand is a little program on the walker (`Pedestrian.errand`: "steps", "i") run by walk():
## goto (the walker's own ring walking, round the corners), path (placed straight lines, down off
## the kerb and up again, the road registered as a jaywalker's while on it), face, wait_bus, board,
## ride, car_door, enter_car, hide, inside, show, truck, bag, ring. Every roll is this walker's own
## stream (hash of its seed and "errand"), never the life stream or a chunk's rng.

## The whole layer on or off (STREET_ERRANDS=0 in the environment: the A/B for stills).
static var enabled: bool = OS.get_environment("STREET_ERRANDS") != "0"
## ERRAND_DEBUG=1: every errand called off says where and why.
static var debug: bool = OS.get_environment("ERRAND_DEBUG") == "1"

## Of the life stops rolled near the player (Pedestrian._try_life), the share that become each
## errand when one is possible from where the walker stands.
const BUS_SHARE := 0.5
const SHOP_SHARE := 0.32
const CAR_SHARE := 0.1
## Jaywalking: downtown and midtown, elsewhere.
const JAY_SHARE := Vector2(0.12, 0.05)
## How far a walker looks for each (metres).
const STOP_REACH := 45.0
const DOOR_REACH := 24.0
const CAR_REACH := 22.0
## A bus queue: the longest a walker waits (seconds), and how long a rider stays on.
const QUEUE_SECONDS := Vector2(45.0, 120.0)
const RIDE_SECONDS := Vector2(20.0, 150.0)
## Inside a shop (seconds); the share who come out with a bag.
const SHOP_SECONDS := Vector2(14.0, 70.0)
const BAG_SHARE := 0.35
## A traffic car pulls into a kerb space near the player every so often (seconds), between these
## distances from them (metres), and that share of them are deliveries.
const PARK_INTERVAL := Vector2(10.0, 24.0)
const PARK_RANGE := Vector2(16.0, 70.0)
## What the driver who gets out of a parked car does.
const DELIVER_NONE := 0
const DELIVER_BAG := 1
const DELIVER_TRUCK := 2
const COURIER_SHARE := 0.3
## How long a delivery takes inside (seconds).
const DELIVER_SECONDS := Vector2(8.0, 16.0)
## Jaywalkers: a stretch this far from the corners, this much clear time ahead of every car.
const JAY_CORNER := 14.0
const JAY_CLEAR_SECONDS := 2.0
const JAY_RUN_SHARE := 0.35
## Traffic: brakes for a jaywalker within this many metres of its lane centre; honks inside this.
const JAY_LANE_REACH := 2.6
const HONK_REACH := 22.0
const HONK_SHARE := 0.55

## The bus stops of the FULL chunks streamed in (add_stop): dictionaries, pruned as chunks go.
static var _stops: Array = []
## Walkers out in the carriageway: instance id -> [axis, index, along, across].
static var _jay: Dictionary = {}
## Walkers inside somewhere (hidden): instance id -> Pedestrian.
static var _hidden: Dictionary = {}
static var _frame: int = -1
static var _buses: Array = []
static var _next_park_ms: int = 0
static var _honked: Dictionary = {}
static var _traffic_ref: WeakRef
static var _world_rng := RandomNumberGenerator.new()


# --- Hooks -------------------------------------------------------------------------------------

## A bus stop's shelter just went up (BigVehicles.build_bus_stops): its queue on this chunk.
## `p` is the shelter's spot on the pavement (2 m in from the kerb, level with the bus's front
## door), `inward` the way off the road, `d2` along the kerb; the bus on (axis, index) heading
## `dir` stops its nose at `stop`.
static func add_stop(chunk: Node, rect: Rect2, p: Vector2, inward: Vector2, _d2: Vector2, axis: int, index: int, dir: int, stop: float) -> void:
	if not enabled or chunk == null or int(chunk.get("level")) != CityChunk.Level.FULL:
		return
	_prune_stops()
	var travel := Vector2(0.0, float(dir)) if axis == CityPlan.AXIS_X else Vector2(float(dir), 0.0)
	var kerb := p - inward * 2.0
	var slots: Array = []
	# The first slot is by the door; the rest queue back along the kerb, toward the bus's tail.
	for k in 6:
		var back := [0.3, -0.7, -1.7, 1.3, -2.7, -3.6][k] as float
		var off := 1.05 + 0.35 * float(k % 2)
		slots.append(kerb + inward * off + travel * back)
	_stops.append({
		"chunk": weakref(chunk), "ring": rect, "kerb": kerb, "inward": inward, "travel": travel,
		"axis": axis, "index": index, "dir": dir, "stop": stop, "slots": slots, "taken": [null, null, null, null, null, null],
	})


## Where the door bay of every shop on this wall is (Building, beside the storefront pieces):
## the same shop rolls ShopfrontKit.storefront_face() and building.gdshader place the door with,
## kept on the building as [local point at the foot of the door, local outward normal, shop key].
static func note_shop_doors(b: Building, face_id: int, fc: Vector3, a: Vector3, n: Vector3, size_u: float,
		cols: int, pitch: float, cut: float, bottom: float, span: float) -> void:
	if not enabled:
		return
	var span_i := maxi(int(span + 0.5), 1)
	var runs := ceili(float(cols) / float(span_i))
	var skip := 1 if cut > 0.0 else 0
	var doors: Array = b.get_meta("shop_doors", [])
	for run in runs:
		var key := b.shop_key(face_id, run)
		var col := run * span_i + ShopfrontKit.door_index(key, span_i)
		if col >= cols or col < skip or col >= cols - skip:
			continue
		var along := size_u * 0.5 - (float(col) + 0.5) * pitch
		doors.append([fc + a * along + Vector3(0.0, bottom, 0.0), n, key])
	b.set_meta("shop_doors", doors)


## Called from Pedestrian._walk every tick for a walker near the player or on an errand: true
## when the errand drives the walker this tick (the normal walking is skipped).
static func walk(p: Pedestrian, delta: float, panicking: bool) -> bool:
	if not enabled:
		return false
	_tick_world(p)
	if p.errand.is_empty():
		return false
	var steps: Array = p.errand.steps
	var i: int = p.errand.i
	if i >= steps.size():
		_done(p)
		return false
	var step: Dictionary = steps[i]
	var hidden := _hidden.has(p.get_instance_id())
	if p._down:
		release(p)
		return false
	if not hidden and (panicking or not _near(p)) and not step.get("road", false):
		# A fright, or the player gone: whatever this was is off, from where they stand.
		_abort(p)
		return false
	match String(step.do):
		"goto":
			return _do_goto(p, step)
		"path":
			_do_path(p, step, delta, panicking)
		"face":
			_do_face(p, step, delta)
		"wait_bus":
			_do_wait_bus(p, step, delta)
		"board":
			_do_board(p, step, delta)
		"ride":
			_do_ride(p, step)
		"look_road":
			_do_look_road(p, step, delta)
		"car_door":
			_do_car_door(p, step, delta)
		"enter_car":
			_do_enter_car(p, step, delta)
		"hide":
			_hide(p)
			_next(p, {"do": "inside", "door": step.get("door"), "until": _now() + int(1000.0 * float(step.get("secs", 30.0)))})
		"inside":
			_do_inside(p, step)
		"show":
			_show(p, step.get("at") as Vector2, float(step.get("yaw", p._visual.rotation.y)))
			_next(p)
		"ring":
			p.ring = step.ring
			_next(p)
		"truck":
			_set_truck(p, int(step.boxes))
			_next(p)
		"bag":
			_set_bag(p, bool(step.on))
			_next(p)
		_:
			_next(p)
	return true


## Pedestrian._try_life: maybe start an errand instead of a stop. True when one started.
static func try_start(p: Pedestrian, at_spawn: bool) -> bool:
	if not enabled or not p._life_ok or p._jogger or p._dog_walker or not p.errand.is_empty() or not p._lives():
		return false
	var plan := p._city_plan()
	if plan == null:
		return false
	var rng := _rng_of(p)
	var here := Vector2(p.position.x, p.position.z)
	var stop := _near_stop(p, here)
	if not stop.is_empty() and rng.randf() < BUS_SHARE:
		return _start_bus(p, stop, at_spawn)
	if at_spawn:
		return false
	var r := rng.randf()
	if r < SHOP_SHARE:
		var door := _near_door(p, here, DOOR_REACH)
		if not door.is_empty():
			return _start_shop(p, door)
		return false
	r -= SHOP_SHARE
	if r < CAR_SHARE:
		var car := _near_parked_car(p, plan, here)
		if car != null:
			return _start_car_in(p, plan, car)
		return false
	r -= CAR_SHARE
	var district := plan.district_at(here)
	var jay := JAY_SHARE.x if district == CityPlan.District.DOWNTOWN or district == CityPlan.District.MIDTOWN else JAY_SHARE.y
	if r < jay:
		return _start_jay(p, plan, here)
	return false


## The walker leaves the tree or goes down: nothing of theirs stays registered.
static func release(p: Pedestrian) -> void:
	var id := p.get_instance_id()
	_jay.erase(id)
	_hidden.erase(id)
	if p.errand.is_empty():
		return
	for s: Dictionary in _stops:
		var taken: Array = s.taken
		for k in taken.size():
			if taken[k] == p:
				taken[k] = null
	var car: Variant = p.errand.get("car")
	if car is Vehicle and is_instance_valid(car) and car.get_node_or_null("ErrandCar") == null:
		(car as Vehicle).remove_meta("errand")
	_set_truck(p, -1)
	p.errand = {}


## After the clip has posed the rig: the arms forward onto a hand truck's handle.
static func pose(p: Pedestrian, _delta: float) -> void:
	if p._head_skel == null or not p.errand.has("truck_node"):
		return
	var skel := p._head_skel
	for side: float in [1.0, -1.0]:
		var prefix := "Left" if side > 0.0 else "Right"
		_aim_bone(skel, prefix + "Arm", prefix + "ForeArm", Vector3(0.12 * side, -0.78, 0.62))
		_aim_bone(skel, prefix + "ForeArm", prefix + "Hand", Vector3(-0.06 * side, -0.38, 0.92))


## TrafficManager._drive_street: how far ahead of `car`'s nose a jaywalker stands in or by its
## lane (INF: nobody), and a horn for them now and then.
static func jaywalker_gap(car: Node3D, axis: int, index: int, dir: int, along: float, half: float, lane_x: float, v: float) -> float:
	if _jay.is_empty():
		return INF
	var best := INF
	for id: int in _jay:
		var j: Array = _jay[id]
		if int(j[0]) != axis or int(j[1]) != index:
			continue
		if absf(float(j[3]) - lane_x) > JAY_LANE_REACH:
			continue
		var ahead := (float(j[2]) - along) * float(dir) - half - 0.5
		if ahead > -half and ahead < 55.0:
			best = minf(best, maxf(ahead, 0.0))
	if best < HONK_REACH and v > 2.0:
		_honk(car)
	return best


## TrafficManager._drive_street: the car standing in the kerb space it pulled into (`park_at`)
## is parked - out of the traffic, a physics car on its wheels like the chunk's own - and its
## driver gets out (ErrandCar). Always true.
static func park_here(traffic: Node, car: Vehicle) -> bool:
	(traffic.get("cars") as Array).erase(car)
	var t: Dictionary = car.traffic
	var deliver: int = t.get("deliver", DELIVER_NONE)
	car.traffic = {}
	car.traffic_speed = 0.0
	car.collision_mask = car._mask()
	# Handed to physics on purpose: not a crash.
	car.hold_crash_watch(6)
	car._add_real_wheels()
	car.freeze = false
	car.sleeping = false
	car.linear_velocity = Vector3.ZERO
	car.angular_velocity = Vector3.ZERO
	# The chunk of the block it parked by frees it with its own parked cars.
	var plan: CityPlan = traffic.get("plan")
	var streamer := traffic.get_parent()
	if plan and streamer and streamer.get("chunks") is Dictionary:
		var wp := WorldState.to_world(car.global_position)
		var chunk: Variant = (streamer.get("chunks") as Dictionary).get(plan.chunk_index_at(Vector2(wp.x, wp.z)))
		if chunk is Node and chunk.get("_cars") is Array:
			(chunk.get("_cars") as Array).append(car)
	ErrandCar.on(car).arrive(deliver)
	return true


## A parked car somebody got into joins the traffic: its real wheels off (a kinematic body must
## never keep them), frozen, in the traffic's own lists, its lane offset starting at the kerb
## space so the TrafficManager eases it out into the lane as it pulls away. False while the lane
## beside it is not clear (ErrandCar tries again).
static func pull_out(car: Vehicle) -> bool:
	var traffic := _traffic_of(car)
	if traffic == null:
		return false
	var plan: CityPlan = traffic.get("plan")
	var road := _parked_road(plan, car)
	if road.is_empty():
		return false
	var axis: int = road.axis
	var index: int = road.index
	var dir: int = road.dir
	var width := plan.road_width(axis, index)
	var lanes := 2 if width > plan.street_width + 1.0 else 1
	var side := -dir if axis == CityPlan.AXIS_X else dir
	var lane := float(side) * CityPlan.lane_center(width, lanes, lanes - 1)
	var wp := WorldState.to_world(car.global_position)
	var along := wp.z if axis == CityPlan.AXIS_X else wp.x
	if not traffic.call("_lane_clear", axis, index, dir, lane, along, 13.0):
		return false
	for w in car.wheels:
		if is_instance_valid(w):
			car.remove_child(w)
			w.free()
	car.wheels.clear()
	car.linear_velocity = Vector3.ZERO
	car.angular_velocity = Vector3.ZERO
	car.engine_force = 0.0
	car.hold_crash_watch(6)
	car.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	car.freeze = true
	var speed: float = (traffic.get("speed_range") as Vector2).x + randf() * 3.0
	car.traffic = {"axis": axis, "index": index, "dir": dir, "lane": lane, "speed": speed, "v": 0.0,
		"half": TrafficManager.car_half_length(car), "rear": TrafficManager.car_rear_length(car),
		"shift": CityPlan.parking_offset(width) - absf(lane)}
	car.collision_mask = car._mask()
	car.traffic_speed = 0.0
	# Not the chunk's to free any more: the traffic's (TrafficManager._retire frees a car it does
	# not own once it is done with it).
	car.set_meta("driven", true)
	(traffic.get("cars") as Array).append(car)
	return true


## The driver of a car that has just parked gets out at its door: one of the people hidden inside
## somewhere near (no one is made or lost), else a new walker on the kerb-side block under the
## crowd cap. Null when neither is possible. `deliver` is what they do next (DELIVER_*).
static func spawn_driver(car: Vehicle, deliver: int) -> Pedestrian:
	var traffic := _traffic_of(car)
	if traffic == null:
		return null
	var plan: CityPlan = traffic.get("plan")
	var geo := _car_frame(car)
	var ring := _kerb_ring(plan, geo)
	if ring.size == Vector2.ZERO:
		return null
	var door_in: Vector2 = geo.door_in
	var p := _from_pool(Vector2(geo.pos.x, geo.pos.y), 160.0)
	if p == null:
		p = _from_far(car, Vector2(geo.pos.x, geo.pos.y))
	if p != null:
		_show(p, door_in, geo.yaw + PI * 0.5)
		p.ring = ring
	else:
		var streamer := traffic.get_parent()
		if streamer == null or not streamer.has_method("take_crowd_room"):
			return null
		var chunk: Variant = (streamer.get("chunks") as Dictionary).get(plan.chunk_index_at(ring.get_center()))
		if not (chunk is Node3D) or int((chunk as Node).get("level")) != CityChunk.Level.FULL:
			return null
		if not streamer.take_crowd_room():
			return null
		p = Pedestrian.new()
		p.setup(ring, plan.sidewalk_width, hash([plan.seed, car.get_instance_id(), _now()]))
		p.position = Vector3(door_in.x, (chunk as Node).call("ground_y", door_in.x, door_in.y) + 0.1 - (CityChunk.SIDEWALK_TOP - CityChunk.ROAD_TOP), door_in.y)
		(chunk as Node).add_child(p)
		p._visual.rotation.y = geo.yaw + PI * 0.5
		p._faced = true
	var steps: Array = []
	var road := [geo.axis, geo.index]
	steps.append({"do": "path", "pts": [geo.door_out, geo.behind, geo.kerb], "road": true, "jay": road})
	var door := {}
	if deliver != DELIVER_NONE:
		door = _near_door_on(p, ring, geo.kerb, 40.0)
	if not door.is_empty():
		p.errand = {"steps": steps, "i": 0, "car": car, "delivery": deliver}
		if deliver == DELIVER_TRUCK:
			# Round to the back of the truck for the hand truck, then to the shop's door.
			steps[0] = {"do": "path", "pts": [geo.door_out, geo.tail_road, geo.tail_kerb], "road": true, "jay": road}
			steps.append({"do": "truck", "boxes": 3})
		else:
			steps.append({"do": "bag", "on": true})
		_append_shop_visit(steps, door, _rng_of(p).randf_range(DELIVER_SECONDS.x, DELIVER_SECONDS.y), deliver == DELIVER_TRUCK)
		if deliver == DELIVER_TRUCK:
			steps.append({"do": "goto", "at": geo.tail_kerb})
			steps.append({"do": "path", "pts": [geo.tail_kerb], "keep_truck": true})
			steps.append({"do": "truck", "boxes": -1})
			steps.append({"do": "path", "pts": [geo.tail_road, geo.door_out], "road": true, "jay": road})
		else:
			steps.append({"do": "goto", "at": geo.kerb})
			steps.append({"do": "path", "pts": [geo.behind, geo.door_out], "road": true, "jay": road})
		steps.append({"do": "car_door", "road": true})
		steps.append({"do": "enter_car", "road": true})
	else:
		p.errand = {"steps": steps, "i": 0}
	return p


## A shop door the still and the checks can use: the nearest within `reach` of a true-world point.
static func door_near(chunk: Node, at: Vector2, reach: float) -> Dictionary:
	var best := {}
	var best_d := reach
	for d: Dictionary in _doors(chunk):
		var dd := (d.p as Vector2).distance_to(at)
		if dd < best_d:
			best_d = dd
			best = d
	return best


# --- Starting an errand ------------------------------------------------------------------------

static func _start_bus(p: Pedestrian, stop: Dictionary, at_spawn: bool) -> bool:
	var taken: Array = stop.taken
	var slot := taken.find(null)
	if slot < 0:
		return false
	taken[slot] = p
	var at: Vector2 = (stop.slots as Array)[slot]
	var look := -(stop.inward as Vector2) - (stop.travel as Vector2) * 0.7
	var yaw := atan2(-look.x, -look.y) + _rng_of(p).randf_range(-0.25, 0.25)
	var wait := {"do": "wait_bus", "stop": stop, "slot": slot, "yaw": yaw,
		"until": _now() + int(1000.0 * _rng_of(p).randf_range(QUEUE_SECONDS.x, QUEUE_SECONDS.y))}
	if at_spawn:
		p._place_at(at, yaw)
		p.errand = {"steps": [wait], "i": 0}
	else:
		p.errand = {"steps": [{"do": "goto", "at": at}, {"do": "path", "pts": [at]}, wait], "i": 0}
	return true


static func _start_shop(p: Pedestrian, door: Dictionary) -> bool:
	var steps: Array = []
	_append_shop_visit(steps, door, _rng_of(p).randf_range(SHOP_SECONDS.x, SHOP_SECONDS.y), false)
	p.errand = {"steps": steps, "i": 0}
	return true


## Into a shop and out again: along the pavement to the spot in front of its door, up to the door,
## a beat there (the door pulled), through it and gone; later out of it and back to the pavement.
static func _append_shop_visit(steps: Array, door: Dictionary, secs: float, truck: bool) -> void:
	var at: Vector2 = door.p
	var out: Vector2 = door.out
	var yaw := atan2(out.x, out.y)
	steps.append({"do": "goto", "at": door.front})
	steps.append({"do": "path", "pts": [at + out * (1.2 if truck else 0.9)], "keep_truck": truck})
	steps.append({"do": "face", "yaw": yaw, "secs": 0.5, "keep_truck": truck})
	steps.append({"do": "path", "pts": [at + out * 0.15], "pace": 0.8, "keep_truck": truck})
	steps.append({"do": "hide", "door": door, "secs": secs})


static func _start_car_in(p: Pedestrian, plan: CityPlan, car: Vehicle) -> bool:
	var geo := _car_frame(car)
	if geo.is_empty() or car.has_meta("errand"):
		return false
	car.set_meta("errand", true)
	var road := [geo.axis, geo.index]
	p.errand = {"steps": [
		{"do": "goto", "at": geo.kerb},
		{"do": "path", "pts": [geo.behind, geo.door_out], "road": true, "jay": road},
		{"do": "car_door", "road": true},
		{"do": "enter_car", "road": true},
	], "i": 0, "car": car}
	return true


## Mid-block, straight over to the pavement opposite: from the kerb in front of them, if the road
## goes on to a block the city goes on to, nothing is parked across the way, and no rail runs there.
static func _start_jay(p: Pedestrian, plan: CityPlan, here: Vector2) -> bool:
	var ring := p.ring
	var d := [here.x - ring.position.x, ring.end.x - here.x, here.y - ring.position.y, ring.end.y - here.y]
	var e := 0
	for k in 4:
		if d[k] < d[e]:
			e = k
	if d[e] > p._sidewalk:
		return false
	var axis := CityPlan.AXIS_X if e < 2 else CityPlan.AXIS_Z
	var out := -1.0 if e % 2 == 0 else 1.0
	var kerb_c: float = ring.position.x if e == 0 else (ring.end.x if e == 1 else (ring.position.y if e == 2 else ring.end.y))
	var along := here.y if axis == CityPlan.AXIS_X else here.x
	var lo := ring.position.y if axis == CityPlan.AXIS_X else ring.position.x
	var hi := ring.end.y if axis == CityPlan.AXIS_X else ring.end.x
	if along < lo + JAY_CORNER or along > hi - JAY_CORNER:
		return false
	# The road beyond this kerb, and the block over it.
	var index := plan._index_at(axis, kerb_c + out * 2.0)
	var best := index
	for i: int in [index - 1, index, index + 1, index + 2]:
		if absf(plan.road_pos(axis, i) - kerb_c) < absf(plan.road_pos(axis, best) - kerb_c):
			best = i
	index = best
	var width := plan.road_width(axis, index)
	if absf(absf(plan.road_pos(axis, index) - kerb_c) - width * 0.5) > 1.5 or width > 30.0:
		return false
	if not plan.road_open(axis, index, along) or LightRail.of(plan) != null and LightRail.of(plan).street_rail(axis, index):
		return false
	var far_c := kerb_c + out * width
	var b := plan.block_index_at(ring.get_center())
	var next: Rect2 = plan.block(b.x + int(out), b.y).rect if axis == CityPlan.AXIS_X else plan.block(b.x, b.y + int(out)).rect
	var far_pt := Vector2(far_c + out * 0.7, along) if axis == CityPlan.AXIS_X else Vector2(along, far_c + out * 0.7)
	if not p._crossable(plan, next, far_pt) or not next.grow(0.5).has_point(far_pt):
		return false
	# A gap in the parked cars on both sides (a slide along the kerb to find one).
	var gap := NAN
	for shift: float in [0.0, 2.5, -2.5, 5.0, -5.0]:
		if _road_gap(p, plan, axis, index, along + shift, width):
			gap = along + shift
			break
	if is_nan(gap) or gap < lo + JAY_CORNER - 3.0 or gap > hi - JAY_CORNER + 3.0:
		return false
	var kerb_pt := Vector2(kerb_c - out * 0.6, gap) if axis == CityPlan.AXIS_X else Vector2(gap, kerb_c - out * 0.6)
	var far := Vector2(far_c + out * 0.8, gap) if axis == CityPlan.AXIS_X else Vector2(gap, far_c + out * 0.8)
	var rng := _rng_of(p)
	var run := rng.randf() < JAY_RUN_SHARE
	var look := Vector2(out, 0.0) if axis == CityPlan.AXIS_X else Vector2(0.0, out)
	var band := Vector2(kerb_c - out * 1.8, gap) if axis == CityPlan.AXIS_X else Vector2(gap, kerb_c - out * 1.8)
	p.errand = {"steps": [
		{"do": "goto", "at": band},
		{"do": "path", "pts": [kerb_pt]},
		{"do": "look_road", "yaw": atan2(-look.x, -look.y), "axis": axis, "index": index, "along": gap,
			"width": width, "run": run, "secs": rng.randf_range(0.8, 1.8), "patience": rng.randf_range(4.0, 12.0)},
		{"do": "path", "pts": [far], "road": true, "jay": [axis, index], "pace": p.run_speed * 0.8 if run else p.walk_speed * 1.25},
		{"do": "ring", "ring": next},
	], "i": 0}
	return true


# --- The steps ---------------------------------------------------------------------------------

static func _do_goto(p: Pedestrian, step: Dictionary) -> bool:
	var at: Vector2 = step.at
	if not step.get("sent", false):
		step.sent = true
		step.until = _now() + 90000
		# A few metres along the same pavement: straight there, placed (the ring's own walking
		# rounds a target off the band's edge and can stop short of it).
		if Vector2(p.position.x, p.position.z).distance_to(at) < 6.0:
			_next(p, {"do": "path", "pts": [at]})
			return true
		p._go_to(at)
		p._pause_left = 0.0
		p._pause_next = 0.0
	var here := Vector2(p.position.x, p.position.z)
	if here.distance_to(at) < 1.15:
		_next(p)
		return true
	# Close, but held up by something on the pavement (a lamp post, a bin, somebody standing):
	# the placed steps after this one take them the last few metres.
	var d := here.distance_to(at)
	if d < float(step.get("best", INF)) - 0.2:
		step.best = d
		step.since = _now()
	elif _now() - int(step.get("since", _now())) > 1500:
		# Held up by something on the pavement (a lamp post, a bin, somebody standing), or the
		# ring's walking stopped short: the rest of the way straight, placed.
		_next(p, {"do": "path", "pts": [at]})
		return true
	if _now() > int(step.until):
		# Never got there (walled in by something on the pavement): off it.
		_abort(p)
		return false
	# The ring's own walking takes them there (round the corners); a walker who lost the target
	# (a stuck-shuffle picks a new one) is put back on it.
	if p._target.distance_to(at) > 0.01 and p._route.is_empty():
		p._go_to(at)
	return false


static func _do_path(p: Pedestrian, step: Dictionary, delta: float, panicking: bool) -> void:
	var pts: Array = step.pts
	var k: int = step.get("k", 0)
	if k >= pts.size():
		_jay.erase(p.get_instance_id())
		_next(p)
		return
	var pace: float = step.get("pace", p.walk_speed)
	if panicking:
		pace = p._run_pace
	var goal: Vector2 = pts[k]
	var left := _step_to(p, goal, delta, pace, k == pts.size() - 1)
	if step.get("road", false):
		var j: Array = step.get("jay", [])
		if j.size() == 2:
			var axis: int = j[0]
			_jay[p.get_instance_id()] = [axis, int(j[1]), p.position.z if axis == CityPlan.AXIS_X else p.position.x,
				p.position.x if axis == CityPlan.AXIS_X else p.position.z]
	if left < 0.12:
		step.k = k + 1
		if k + 1 >= pts.size():
			_jay.erase(p.get_instance_id())
			_next(p)


static func _do_face(p: Pedestrian, step: Dictionary, delta: float) -> void:
	p._turn_on_spot(float(step.yaw), delta)
	step.t = float(step.get("t", 0.0)) + delta
	if step.t >= float(step.secs) and absf(angle_difference(p._visual.rotation.y, float(step.yaw))) < 0.2:
		p._pivoting = false
		_next(p)


static func _do_wait_bus(p: Pedestrian, step: Dictionary, delta: float) -> void:
	var stop: Dictionary = step.stop
	p._speed = 0.0
	p.velocity = Vector3.ZERO
	p._turn_on_spot(float(step.yaw), delta)
	if p._life_clip == "" and p._life_ok:
		p._life_clip = p._stand_clip()
	if not (stop.chunk as WeakRef).get_ref():
		_abort(p)
		return
	step.check = float(step.get("check", 0.0)) - delta
	if step.check <= 0.0:
		step.check = 0.3
		var bus := _bus_at(stop)
		if not bus.is_empty():
			# The queue boards in order, a beat apart.
			var slot: int = step.slot
			p._life_clip = ""
			_next(p, {"do": "board", "bus": bus[0], "delay": 0.25 + 0.7 * float(slot), "stop": stop, "slot": slot})
			return
	if _now() > int(step.until):
		_abort(p)


static func _do_board(p: Pedestrian, step: Dictionary, delta: float) -> void:
	var bv: Variant = step.bus
	if not is_instance_valid(bv) or not (bv as Vehicle).is_traffic():
		_abort(p)
		return
	var bus: Vehicle = bv
	var fit := bus.get_node_or_null("BusFittings") as BigVehicles.BusFittings
	var t: Dictionary = bus.traffic
	# Held at the stop while anybody is still getting on.
	if t.has("dwell"):
		t.dwell_need = maxf(float(t.get("dwell_need", 0.0)), float(t.dwell) + 2.0)
	step.delay = float(step.delay) - delta
	if step.delay > 0.0:
		return
	if fit == null or fit.open < 0.5:
		return
	var door := _bus_doors(bus)[0] as Vector2
	var left := _step_to(p, door, delta, p.walk_speed, true)
	if left < 0.3:
		var stop: Dictionary = step.stop
		(stop.taken as Array)[int(step.slot)] = null
		_hide(p)
		var key := _stop_key(stop)
		_next(p, {"do": "ride", "bus": bus, "from": key, "until": _now() + int(1000.0 * _rng_of(p).randf_range(RIDE_SECONDS.x, RIDE_SECONDS.y))})


static func _do_ride(p: Pedestrian, step: Dictionary) -> void:
	var bv: Variant = step.bus
	if not is_instance_valid(bv) or not (bv as Vehicle).is_inside_tree() or not (bv as Vehicle).is_traffic() or _now() > int(step.until):
		# Off the bus somewhere out of sight: one of the people inside, who come out of doors.
		_next(p, {"do": "inside", "door": _near_door(p, p.ring.get_center(), 400.0), "until": _now() + 4000})
		return
	var wp := WorldState.to_world((bv as Vehicle).global_position)
	p.position = Vector3(wp.x, wp.y, wp.z)


static func _do_look_road(p: Pedestrian, step: Dictionary, delta: float) -> void:
	p._turn_on_spot(float(step.yaw), delta)
	p._speed = 0.0
	step.t = float(step.get("t", 0.0)) + delta
	if step.t < float(step.secs):
		return
	var plan := p._city_plan()
	var cross := float(step.width) / (p.run_speed * 0.8 if step.run else p.walk_speed * 1.25)
	if _road_clear(p, plan, int(step.axis), int(step.index), float(step.along), cross + JAY_CLEAR_SECONDS):
		_next(p)
	elif step.t > float(step.patience):
		_abort(p)


static func _do_car_door(p: Pedestrian, step: Dictionary, delta: float) -> void:
	var car: Variant = p.errand.get("car")
	if not (car is Vehicle) or not is_instance_valid(car) or (car as Vehicle).is_traffic() or (car as Vehicle).driver != null:
		_abort(p)
		return
	var geo := _car_frame(car)
	p._turn_on_spot(float(geo.yaw) - PI * 0.5, delta)
	_keep_in_road(p, geo)
	var ec := ErrandCar.on(car)
	ec.request_open()
	step.t = float(step.get("t", 0.0)) + delta
	if ec.is_open():
		_next(p)
	elif step.t > 6.0:
		_abort(p)


static func _do_enter_car(p: Pedestrian, step: Dictionary, delta: float) -> void:
	var car: Variant = p.errand.get("car")
	if not (car is Vehicle) or not is_instance_valid(car):
		_abort(p)
		return
	var geo := _car_frame(car)
	_keep_in_road(p, geo)
	var left := _step_to(p, geo.door_in, delta, 0.9, true)
	if left < 0.15:
		_jay.erase(p.get_instance_id())
		_set_truck(p, -1)
		ErrandCar.on(car).entered(true)
		_hide(p)
		p.errand.erase("car")
		p.errand.erase("delivery")
		var ring_c := p.ring.get_center()
		_next(p, {"do": "inside", "door": _near_door(p, ring_c, 400.0), "until": _now() + int(1000.0 * _rng_of(p).randf_range(SHOP_SECONDS.x, SHOP_SECONDS.y))})


## Hidden inside a shop, a bus or a car. Out of a shop by its door when the time is up; anybody
## else comes out somewhere on their pavement once nobody near the player could see it.
static func _do_inside(p: Pedestrian, step: Dictionary) -> void:
	if _now() < int(step.until):
		return
	var door: Variant = step.get("door")
	if door is Dictionary and _door_alive(door):
		var d: Dictionary = door
		var out: Vector2 = d.out
		var what: int = p.errand.get("delivery", DELIVER_NONE)
		var steps: Array = [
			{"do": "show", "at": (d.p as Vector2) + out * 0.15, "yaw": atan2(-out.x, -out.y)},
			{"do": "ring", "ring": d.ring},
		]
		if what == DELIVER_TRUCK:
			steps.append({"do": "truck", "boxes": 0})
		elif what == DELIVER_BAG:
			steps.append({"do": "bag", "on": false})
		elif _rng_of(p).randf() < BAG_SHARE and p._carry == CrowdLife.Carry.NONE:
			steps.append({"do": "bag", "on": true})
		steps.append({"do": "path", "pts": [(d.p as Vector2) + out * (1.2 if what == DELIVER_TRUCK else 0.9), d.front]})
		steps.append_array((p.errand.steps as Array).slice(int(p.errand.i) + 1))
		p.errand.steps = steps
		p.errand.i = 0
		return
	if p._life_near:
		return
	var at := p._random_ring_point(p._sidewalk)
	_show(p, at, p._visual.rotation.y)
	p.position.y = p._ground_y(at.x, at.y, p.position.y)
	_done(p)


# --- Shared ------------------------------------------------------------------------------------

## Once a physics frame, from whichever walker gets there first: the buses standing with their
## doors open (and who gets off them), and now and then a car pulling in to park near the player.
static func _tick_world(p: Pedestrian) -> void:
	var f := Engine.get_physics_frames()
	if f == _frame:
		return
	_frame = f
	var traffic := _traffic_of(p)
	if traffic == null:
		_buses.clear()
		return
	_buses.clear()
	for c: Variant in traffic.get("cars"):
		if not is_instance_valid(c):
			continue
		var car := c as Vehicle
		if car == null or not car.is_traffic() or not car.traffic.has("bus"):
			continue
		var fit := car.get_node_or_null("BusFittings") as BigVehicles.BusFittings
		if fit == null or fit.open < 0.55:
			continue
		_buses.append(car)
		var seen := float(car.get_meta("errand_dwell", -1.0))
		var need := float(car.traffic.get("dwell_need", 0.0))
		if seen != need:
			car.set_meta("errand_dwell", need)
			_let_off(car)
	if _now() >= _next_park_ms:
		_next_park_ms = _now() + int(1000.0 * _world_rng.randf_range(PARK_INTERVAL.x, PARK_INTERVAL.y))
		_pick_parker(traffic)


## A bus has opened its doors at a stop: riders whose time is up get off, and a few of the people
## inside shops near it come off it instead (nobody sees them go in).
static func _let_off(bus: Vehicle) -> void:
	var doors := _bus_doors(bus)
	var rear: Vector2 = doors[1]
	var stop := _stop_near(rear, 16.0)
	var plan := (_traffic_of(bus).get("plan") as CityPlan)
	var ring: Rect2 = stop.ring if not stop.is_empty() else plan.block(plan.block_index_at(rear + _kerb_dir(bus) * 3.0).x, plan.block_index_at(rear + _kerb_dir(bus) * 3.0).y).rect
	var key := _stop_key(stop) if not stop.is_empty() else Vector4i.ZERO
	var off: Array = []
	for id: int in _hidden:
		var pv: Variant = _hidden[id]
		if not is_instance_valid(pv):
			continue
		var p: Pedestrian = pv
		if not is_instance_valid(p) or p.errand.is_empty():
			continue
		var s: Dictionary = (p.errand.steps as Array)[int(p.errand.i)]
		if s.do == "ride" and s.bus == bus and s.from != key and _rng_of(p).randf() < 0.45:
			off.append(p)
	var extra := [0, 0, 1, 1, 2][_world_rng.randi() % 5] as int
	for id: int in _hidden.keys():
		if extra <= 0:
			break
		var pv: Variant = _hidden[id]
		if not is_instance_valid(pv):
			continue
		var p: Pedestrian = pv
		if not is_instance_valid(p) or p.errand.is_empty() or off.has(p):
			continue
		var s: Dictionary = (p.errand.steps as Array)[int(p.errand.i)]
		if s.do == "inside" and Vector2(p.position.x, p.position.z).distance_to(rear) < 160.0:
			off.append(p)
			extra -= 1
	for k in off.size():
		alight(off[k], bus, k, ring)


## `p` (hidden inside somewhere) comes down the rear steps of `bus`, `k`-th off it, and walks off
## onto the pavement of `ring`.
static func alight(p: Pedestrian, bus: Vehicle, k: int, ring: Rect2) -> void:
	var rear: Vector2 = _bus_doors(bus)[1]
	var kerb := _kerb_dir(bus)
	var yaw := atan2(-kerb.x, -kerb.y)
	if not _hidden.has(p.get_instance_id()):
		_hide(p)
	p.errand = {"steps": [
		{"do": "face", "yaw": yaw, "secs": 0.4 + 1.1 * float(k)},
		{"do": "show", "at": rear, "yaw": yaw},
		{"do": "ring", "ring": ring},
		{"do": "path", "pts": [rear + kerb * 1.3, rear + kerb * 2.6 + _along(bus) * (float(k) - 0.5) * 1.4]},
	], "i": 0}


## Now and then, a traffic car in a kerb lane near the player pulls in to a free kerb space ahead
## of it (and its driver gets out there: park_here()).
static func _pick_parker(traffic: Node) -> void:
	var plan: CityPlan = traffic.get("plan")
	var player := traffic.get_tree().get_first_node_in_group("player") as Node3D if traffic.is_inside_tree() else null
	if plan == null or player == null:
		return
	var pp := WorldState.to_world(player.global_position)
	var cars: Array = traffic.get("cars")
	if cars.is_empty():
		return
	var start := _world_rng.randi() % cars.size()
	for n in cars.size():
		var car := cars[(start + n) % cars.size()] as Vehicle
		if car == null or not is_instance_valid(car) or not _may_park(car):
			continue
		var t: Dictionary = car.traffic
		if not t.has("wp") or float(t.get("v", 0.0)) < 2.0:
			continue
		var wp: Vector3 = t.wp
		var dist := Vector2(wp.x - pp.x, wp.z - pp.z).length()
		if dist < PARK_RANGE.x or dist > PARK_RANGE.y:
			continue
		var spot := free_space(traffic, car)
		if is_nan(spot):
			continue
		start_parking(car, spot)
		return


## Sends `car` into the kerb space at `spot` (true-world coordinate along its road).
static func start_parking(car: Vehicle, spot: float) -> void:
	var t: Dictionary = car.traffic
	var plan: CityPlan = _traffic_of(car).get("plan")
	var width := plan.road_width(int(t.axis), int(t.index))
	t.park_at = spot
	t.park_shift = CityPlan.parking_offset(width) - absf(float(t.lane))
	t.no_turns = true
	var big := car.body_type == Vehicle.BodyType.BOX_TRUCK
	var courier := car.body_type == Vehicle.BodyType.VAN and car.livery == Vehicle.Livery.DELIVERY
	if big:
		t.deliver = DELIVER_TRUCK
	elif courier or _world_rng.randf() < COURIER_SHARE:
		t.deliver = DELIVER_BAG
	car.set_meta("errand", true)


## Which street cars may pull in to park: ordinary cars and box trucks in a kerb lane, not a bus,
## a semi, the police, a fire engine or an ambulance, not one already doing something.
static func _may_park(car: Vehicle) -> bool:
	if not car.is_traffic() or car.has_meta("errand") or car.traffic.has("bus") or car.traffic.has("park_at"):
		return false
	if car.traffic.has("police") or car.traffic.has("emergency") or car.is_in_group("police_car") or car.is_in_group("emergency_unit"):
		return false
	if BigVehicles.is_big(car.body_type) and car.body_type != Vehicle.BodyType.BOX_TRUCK:
		return false
	var t: Dictionary = car.traffic
	if not t.has("axis") or int(t.get("turn", 0)) != 0:
		return false
	var plan: CityPlan = _traffic_of(car).get("plan")
	var width := plan.road_width(int(t.axis), int(t.index))
	var lanes := 2 if width > plan.street_width + 1.0 else 1
	return absf(absf(float(t.lane)) - CityPlan.lane_center(width, lanes, lanes - 1)) < 0.3


## A free kerb space ahead of traffic car `car` on its side of its road, before the next corner,
## far enough ahead to stop in comfort (true-world coordinate along the road), or NAN.
static func free_space(traffic: Node, car: Vehicle) -> float:
	var plan: CityPlan = traffic.get("plan")
	var t: Dictionary = car.traffic
	var axis: int = t.axis
	var index: int = t.index
	var dir: int = t.dir
	var along: float = t.get("along", 0.0)
	var v: float = t.get("v", 0.0)
	var cross := CityPlan.AXIS_Z if axis == CityPlan.AXIS_X else CityPlan.AXIS_X
	var k := plan._index_at(cross, along)
	# The parked cars' grid: the spots of the block on the road's low side, 8 m apart from 8 m in
	# (CityChunk._park_car_steps).
	var rect: Rect2 = plan.block(index - 1, k).rect if axis == CityPlan.AXIS_X else plan.block(k, index - 1).rect
	var r0 := rect.position.y if axis == CityPlan.AXIS_X else rect.position.x
	var r1 := rect.end.y if axis == CityPlan.AXIS_X else rect.end.x
	var lo := r0 + 8.0
	var need := maxf(18.0, v * v / 4.0 + 8.0)
	var length := float(car._dims().length)
	var side := signf(float(t.lane))
	var lateral := plan.road_pos(axis, index) + side * CityPlan.parking_offset(plan.road_width(axis, index))
	var s := lo
	while s < r1 - 8.0:
		var ahead := (s - along) * float(dir)
		if ahead >= need and ahead <= need + 30.0:
			var p := Vector2(lateral, s) if axis == CityPlan.AXIS_X else Vector2(s, lateral)
			if plan.road_open(axis, index, s) and not BigVehicles.in_stop_zone(plan, p) \
					and not FireStation.keeps_clear(plan, p) and not (plan.macro and Landmarks.covers(plan, p, 3.0)) \
					and _space_free(traffic, plan, p, axis, length + 1.4):
				return s
		s += 8.0
	return NAN


# --- Hiding, showing, props ---------------------------------------------------------------------

static func _hide(p: Pedestrian) -> void:
	_hidden[p.get_instance_id()] = p
	_jay.erase(p.get_instance_id())
	p.visible = false
	p.collision_layer = 0
	var area := p._hit_shape.get_parent() as Area3D if p._hit_shape else null
	if area:
		area.monitoring = false
	p._speed = 0.0
	p.velocity = Vector3.ZERO
	p._life_clip = ""
	_set_truck(p, -1)


static func _show(p: Pedestrian, at: Vector2, yaw: float) -> void:
	_hidden.erase(p.get_instance_id())
	p.position = Vector3(at.x, _floor(p, at), at.y)
	p._visual.rotation.y = yaw
	p._faced = true
	p._speed = 0.0
	p._panic_left = 0.0
	p._pause_left = 0.0
	p._end_act(true)
	p.visible = true
	p.collision_layer = 8
	var area := p._hit_shape.get_parent() as Area3D if p._hit_shape else null
	if area:
		area.monitoring = true


## The hand truck: `boxes` on it (0 empty), -1 none.
static func _set_truck(p: Pedestrian, boxes: int) -> void:
	var have: Variant = p.errand.get("truck_node") if not p.errand.is_empty() else null
	if have is Node3D and is_instance_valid(have):
		(have as Node3D).queue_free()
	if not p.errand.is_empty():
		p.errand.erase("truck_node")
	if boxes < 0 or p._visual == null:
		return
	var mi := MeshInstance3D.new()
	mi.name = "HandTruck"
	mi.mesh = ErrandProps.hand_truck(boxes)
	mi.position = Vector3(0.0, -0.06, -1.22) / p._visual.scale
	mi.scale = Vector3.ONE / p._visual.scale
	mi.visibility_range_end = 120.0
	p._visual.add_child(mi)
	p.errand.truck_node = mi


static func _set_bag(p: Pedestrian, on: bool) -> void:
	if on:
		if p._carry == CrowdLife.Carry.NONE:
			p.errand.bag_carry = true
			p._carry = CrowdLife.Carry.BAG
	elif p.errand.get("bag_carry", false):
		p.errand.erase("bag_carry")
		p._carry = CrowdLife.Carry.NONE


## Goes on to the errand's next step (or puts `replace` in place of the current one).
static func _next(p: Pedestrian, replace: Dictionary = {}) -> void:
	if p.errand.is_empty():
		return
	var steps: Array = p.errand.steps
	if not replace.is_empty():
		steps[int(p.errand.i)] = replace
		return
	p.errand.i = int(p.errand.i) + 1
	if int(p.errand.i) >= steps.size():
		_done(p)


static func _done(p: Pedestrian) -> void:
	_jay.erase(p.get_instance_id())
	_set_truck(p, -1)
	if not p.errand.is_empty() and p.errand.get("bag_carry", false) and _rng_of(p).randf() < 0.5:
		# A delivery's bag stays in the shop; a shopper keeps theirs a while.
		p._carry = CrowdLife.Carry.NONE
	if not p.errand.is_empty() and p.errand.has("car"):
		var car: Variant = p.errand.car
		if car is Vehicle and is_instance_valid(car) and (car as Node).get_node_or_null("ErrandCar") == null:
			(car as Vehicle).remove_meta("errand")
	p.errand = {}
	p._life_clip = ""
	p._go_to(p._random_ring_point(p._sidewalk))


## Called off part way (a fright, the player gone, the bus or the car gone): back to the pavement.
static func _abort(p: Pedestrian) -> void:
	if debug and not p.errand.is_empty():
		print("ERRAND abort %s at step %d %s (near %s, panic %.1f)" % [p.name, int(p.errand.i), String(((p.errand.steps as Array)[mini(int(p.errand.i), (p.errand.steps as Array).size() - 1)] as Dictionary).do), _near(p), p._panic_left])
	if not p.errand.is_empty():
		var cur: Dictionary = (p.errand.steps as Array)[mini(int(p.errand.i), (p.errand.steps as Array).size() - 1)]
		if cur.has("stop") and cur.has("slot"):
			var taken: Array = (cur.stop as Dictionary).taken
			if int(cur.slot) < taken.size() and taken[int(cur.slot)] == p:
				taken[int(cur.slot)] = null
	for s: Dictionary in _stops:
		var taken: Array = s.taken
		for k in taken.size():
			if taken[k] == p:
				taken[k] = null
	if _hidden.has(p.get_instance_id()):
		return
	_set_bag(p, false)
	_done(p)
	if p._panic_left > 0.0:
		p._go_to(p._flee_point())


# --- Geometry ----------------------------------------------------------------------------------

## A placed step toward `goal` (true world XZ) at `pace`, easing into the stop when `stops`:
## down off the kerb onto the road and up again (CityChunk's pavement is a kerb above it).
## Returns how far is left.
static func _step_to(p: Pedestrian, goal: Vector2, delta: float, pace: float, stops: bool) -> float:
	var here := Vector2(p.position.x, p.position.z)
	var to := goal - here
	var d := to.length()
	if d < 0.04:
		p._speed = move_toward(p._speed, 0.0, p.stop_decel * delta)
		p.velocity = Vector3.ZERO
		return d
	var want := pace
	if stops:
		want = minf(want, sqrt(2.0 * p.stop_decel * maxf(d - 0.05, 0.0)) + 0.15)
	var v := p._steer(to, want, delta, false)
	var step := v * delta
	if step.length() > d:
		step = to
	var at := here + step
	p.position = Vector3(at.x, _floor(p, at), at.y)
	p.velocity = Vector3(v.x, 0.0, v.y)
	return (goal - at).length()


## The height to stand at (chunk space): the pavement, or a kerb lower on a carriageway.
static func _floor(p: Pedestrian, at: Vector2) -> float:
	var y := p._ground_y(at.x, at.y, p.position.y)
	var plan := p._city_plan()
	if plan and on_carriageway(plan, at):
		y -= CityChunk.SIDEWALK_TOP - CityChunk.ROAD_TOP
	return y


## True when true-world point `at` is on a road's carriageway (between its kerbs).
static func on_carriageway(plan: CityPlan, at: Vector2) -> bool:
	for axis: int in [CityPlan.AXIS_X, CityPlan.AXIS_Z]:
		var c := at.x if axis == CityPlan.AXIS_X else at.y
		var i := plan._index_at(axis, c)
		for j: int in [i, i + 1]:
			if absf(c - plan.road_pos(axis, j)) < plan.road_width(axis, j) * 0.5:
				return true
	return false


## A parked car's frame in true world: its position and yaw, the road it is parked on, and the
## points round it a driver walks: by the driver's door (outside, in the lane), in its gap
## (getting in), behind the car in the parking lane, the kerb behind it, and the same at its tail.
## Empty when the car is not in a kerb space.
static func _car_frame(car: Vehicle) -> Dictionary:
	var traffic := _traffic_of(car)
	if traffic == null:
		return {}
	var plan: CityPlan = traffic.get("plan")
	var road := _parked_road(plan, car)
	if road.is_empty():
		return {}
	var xf := car.global_transform
	var wp := WorldState.to_world(xf.origin)
	var fwd3 := -xf.basis.z
	var fwd := Vector2(fwd3.x, fwd3.z).normalized()
	var right := Vector2(-fwd.y, fwd.x)
	var dims := car._dims()
	var half := float(dims.length) * 0.5
	var w := float(dims.width) * 0.5
	var stand := ErrandProps.door_stand(car)
	var door_z := stand.z
	var pos := Vector2(wp.x, wp.z)
	var at_door := pos - fwd * door_z
	return {
		"pos": pos, "yaw": atan2(-fwd.x, -fwd.y), "axis": road.axis, "index": road.index, "dir": road.dir,
		"door_out": at_door - right * (w + 0.62),
		"door_in": at_door - right * (w - 0.25),
		"behind": pos - fwd * (half + 0.9),
		"kerb": pos - fwd * (half + 0.9) + right * (w + 1.15),
		"tail_road": pos - fwd * (half + 1.3) - right * 0.2,
		"tail_kerb": pos - fwd * (half + 1.3) + right * (w + 1.2),
		"right": right,
	}


## The road (axis, index, dir) whose kerb space `car` stands in, nose the traffic's way, or {}.
static func _parked_road(plan: CityPlan, car: Vehicle) -> Dictionary:
	var wp := WorldState.to_world(car.global_position)
	var fwd3 := -car.global_basis.z
	var fwd := Vector2(fwd3.x, fwd3.z)
	if fwd.length() < 0.8:
		return {}
	fwd = fwd.normalized()
	for axis: int in [CityPlan.AXIS_X, CityPlan.AXIS_Z]:
		var across := wp.x if axis == CityPlan.AXIS_X else wp.z
		var i := plan._index_at(axis, across)
		for j: int in [i, i + 1]:
			var road := plan.road_pos(axis, j)
			var width := plan.road_width(axis, j)
			var s := signf(across - road)
			if absf(absf(across - road) - CityPlan.parking_offset(width)) > 0.7:
				continue
			var dir := int(-s) if axis == CityPlan.AXIS_X else int(s)
			var travel := Vector2(0.0, float(dir)) if axis == CityPlan.AXIS_X else Vector2(float(dir), 0.0)
			if fwd.dot(travel) < 0.96:
				continue
			return {"axis": axis, "index": j, "dir": dir}
	return {}


## The pavement ring of the block on a parked car's kerb side.
static func _kerb_ring(plan: CityPlan, geo: Dictionary) -> Rect2:
	if geo.is_empty():
		return Rect2()
	var pt: Vector2 = (geo.pos as Vector2) + (geo.right as Vector2) * 4.0
	var b := plan.block_index_at(pt)
	return plan.block(b.x, b.y).rect


static func _keep_in_road(p: Pedestrian, geo: Dictionary) -> void:
	_jay[p.get_instance_id()] = [geo.axis, geo.index, p.position.z if int(geo.axis) == CityPlan.AXIS_X else p.position.x,
		p.position.x if int(geo.axis) == CityPlan.AXIS_X else p.position.z]


## The bus's front and rear door, on the pavement side, a step out from it (true world XZ).
static func _bus_doors(bus: Vehicle) -> Array:
	var fit := bus.get_node_or_null("BusFittings") as BigVehicles.BusFittings
	var kerb := _kerb_dir(bus)
	var fwd := _along(bus)
	var pos := WorldState.to_world(bus.global_position)
	var front := Vector2(pos.x, pos.z) + fwd * 4.6 + kerb * 1.6
	var rear := Vector2(pos.x, pos.z) - fwd * 0.6 + kerb * 1.6
	if fit:
		var f := Vector3.ZERO
		var nf := 0
		var r := Vector3.ZERO
		var nr := 0
		for l: Array in fit.leaves:
			var n := l[0] as Node3D
			if not is_instance_valid(n):
				continue
			var g := WorldState.to_world(n.global_position)
			if String(n.name).begins_with("door_f"):
				f += g
				nf += 1
			else:
				r += g
				nr += 1
		if nf > 0:
			f /= float(nf)
			front = Vector2(f.x, f.z) + kerb * 0.45
		if nr > 0:
			r /= float(nr)
			rear = Vector2(r.x, r.z) + kerb * 0.45
	return [front, rear]


static func _kerb_dir(car: Node3D) -> Vector2:
	var r := car.global_basis.x
	return Vector2(r.x, r.z).normalized()


static func _along(car: Node3D) -> Vector2:
	var f := -car.global_basis.z
	return Vector2(f.x, f.z).normalized()


## The bus standing at `stop` with its doors open, or [].
static func _bus_at(stop: Dictionary) -> Array:
	for bv: Variant in _buses:
		if not is_instance_valid(bv) or not (bv as Vehicle).is_traffic():
			continue
		var bus: Vehicle = bv
		var t: Dictionary = bus.traffic
		if int(t.axis) != int(stop.axis) or int(t.index) != int(stop.index) or int(t.dir) != int(stop.dir):
			continue
		var doors := _bus_doors(bus)
		if (doors[0] as Vector2).distance_to((stop.slots as Array)[0]) < 6.0:
			return [bus]
	return []


static func _stop_key(stop: Dictionary) -> Vector4i:
	return Vector4i(int(stop.axis), int(stop.index), int(stop.dir), roundi(float(stop.stop)))


static func _stop_near(at: Vector2, reach: float) -> Dictionary:
	_prune_stops()
	var best := {}
	var best_d := reach
	for s: Dictionary in _stops:
		var d := (s.kerb as Vector2).distance_to(at)
		if d < best_d:
			best_d = d
			best = s
	return best


## A stop on this walker's own block within reach with a free place in its queue.
static func _near_stop(p: Pedestrian, here: Vector2) -> Dictionary:
	_prune_stops()
	var grown := p.ring.grow(0.6)
	for s: Dictionary in _stops:
		if (s.kerb as Vector2).distance_to(here) > STOP_REACH or not grown.has_point((s.slots as Array)[0]):
			continue
		if (s.taken as Array).has(null):
			return s
	return {}


static func _prune_stops() -> void:
	for k in range(_stops.size() - 1, -1, -1):
		if not ((_stops[k] as Dictionary).chunk as WeakRef).get_ref():
			_stops.remove_at(k)


## The shop doors of a chunk's buildings, in true world XZ: point, outward way, the spot on the
## pavement in front of it, the ring it opens onto, the shop's key. Worked out once per chunk.
static func _doors(chunk: Node) -> Array:
	if chunk == null:
		return []
	var n := chunk.get_child_count()
	if chunk.has_meta("errand_doors") and int(chunk.get_meta("errand_doors_n", -1)) == n:
		return chunk.get_meta("errand_doors")
	var plan: CityPlan = chunk.get("plan")
	var ring: Rect2 = plan.block(int(chunk.get("ix")), int(chunk.get("iz"))).rect if plan else Rect2()
	var out: Array = []
	for c in chunk.get_children():
		if not (c is Building) or not c.has_meta("shop_doors"):
			continue
		var b := c as Building
		for d: Array in b.get_meta("shop_doors"):
			var at := b.transform * (d[0] as Vector3)
			var nn := b.transform.basis * (d[1] as Vector3)
			var o := Vector2(nn.x, nn.z)
			if o.length() < 0.5:
				continue
			o = o.normalized()
			var p := Vector2(at.x, at.z)
			if ring.size != Vector2.ZERO and not ring.has_point(p):
				continue
			# The spot on the pavement in front: 1.8 m in from the kerb along the way out.
			var to_kerb := _to_edge(ring, p, o)
			if to_kerb > plan.sidewalk_width + 9.0:
				continue
			var front := p + o * clampf(to_kerb - 1.8, 0.8, 9.0)
			out.append({"p": p, "out": o, "front": front, "ring": ring, "key": int(d[2]), "chunk": weakref(chunk)})
	chunk.set_meta("errand_doors", out)
	chunk.set_meta("errand_doors_n", n)
	return out


## How far from `p` along unit `o` the rect's edge is.
static func _to_edge(r: Rect2, p: Vector2, o: Vector2) -> float:
	var t := INF
	if o.x > 0.01:
		t = minf(t, (r.end.x - p.x) / o.x)
	elif o.x < -0.01:
		t = minf(t, (r.position.x - p.x) / o.x)
	if o.y > 0.01:
		t = minf(t, (r.end.y - p.y) / o.y)
	elif o.y < -0.01:
		t = minf(t, (r.position.y - p.y) / o.y)
	return t


static func _door_alive(door: Dictionary) -> bool:
	return door.has("chunk") and (door.chunk as WeakRef).get_ref() != null


## A shop door on the walker's own block within reach, open (by night only the shops that are).
static func _near_door(p: Pedestrian, here: Vector2, reach: float) -> Dictionary:
	return _near_door_on(p, p.ring, here, reach)


static func _near_door_on(p: Pedestrian, ring: Rect2, here: Vector2, reach: float) -> Dictionary:
	var plan := p._city_plan()
	if plan == null:
		return {}
	var streamer := p.get_parent().get_parent() if p.get_parent() else null
	var chunk: Variant = null
	if streamer and streamer.get("chunks") is Dictionary:
		chunk = (streamer.get("chunks") as Dictionary).get(plan.chunk_index_at(ring.get_center()))
	if not (chunk is Node):
		chunk = p.get_parent()
	var night := DayNight.lamp_now > 0.5
	var best := {}
	var best_d := reach
	for d: Dictionary in _doors(chunk):
		if not (d.ring as Rect2).is_equal_approx(ring):
			continue
		if night and not Building.shop_open(int(d.key)):
			continue
		var dd := (d.front as Vector2).distance_to(here)
		if dd < best_d:
			best_d = dd
			best = d
	return best


## A parked car within reach that a walker on this block could drive off in: in a kerb space by
## this block, nose the traffic's way, upright and still, empty, whole, nobody else's errand.
static func _near_parked_car(p: Pedestrian, plan: CityPlan, here: Vector2) -> Vehicle:
	var scene_here := p.global_position
	var grown := p.ring.grow(4.5)
	for n in p.get_tree().get_nodes_in_group("vehicle"):
		var car := n as Vehicle
		if car == null or car.is_traffic() or car.driver != null or car._npc_driver or car.has_meta("errand") or car.has_meta("driven"):
			continue
		if car.global_position.distance_squared_to(scene_here) > CAR_REACH * CAR_REACH:
			continue
		if car._damage != null or BigVehicles.is_big(car.body_type) or car.is_in_group("police_car") or car.global_basis.y.y < 0.97:
			continue
		if car.linear_velocity.length() > 0.3 or car.freeze:
			continue
		var wp := WorldState.to_world(car.global_position)
		var at := Vector2(wp.x, wp.z)
		if not grown.has_point(at) or p.ring.has_point(at):
			continue
		if _parked_road(plan, car).is_empty():
			continue
		return car
	return null


## True when nothing parked or standing is across road (axis, index) at `along` in its parking
## lanes (a box over the whole carriageway, above the road slab: cars, trucks, props).
static func _road_gap(p: Pedestrian, plan: CityPlan, axis: int, index: int, along: float, width: float) -> bool:
	var road := plan.road_pos(axis, index)
	var c := Vector2(road, along) if axis == CityPlan.AXIS_X else Vector2(along, road)
	var size := Vector3(width - 0.4, 1.0, 1.8) if axis == CityPlan.AXIS_X else Vector3(1.8, 1.0, width - 0.4)
	return _box_free(p, plan, c, size, true)


## True when a kerb space of `length` at `p` (true world XZ) has nothing in it.
static func _space_free(traffic: Node, plan: CityPlan, p: Vector2, axis: int, length: float) -> bool:
	var size := Vector3(1.9, 1.0, length) if axis == CityPlan.AXIS_X else Vector3(length, 1.0, 1.9)
	return _box_free(traffic, plan, p, size, false)


static func _box_free(node: Node, plan: CityPlan, c: Vector2, size: Vector3, ignore_traffic: bool) -> bool:
	if not node.is_inside_tree():
		return false
	var h := plan.height_at(c) if plan.macro else 0.0
	var shape := BoxShape3D.new()
	shape.size = size
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.collision_mask = 1 | 4
	q.transform = Transform3D(Basis(), WorldState.to_local(Vector3(c.x, h + CityChunk.ROAD_TOP + 0.55 + size.y * 0.5, c.y)))
	for hit: Dictionary in (node as Node3D).get_world_3d().direct_space_state.intersect_shape(q, 8):
		var col: Object = hit.collider
		if col is Vehicle and ignore_traffic and (col as Vehicle).is_traffic():
			continue
		if col is StaticBody3D and String((col as Node).name) == "GroundBody":
			continue
		return false
	return true


## Nothing on road (axis, index) is due at `along` within `seconds` (or within 7 m of it).
static func _road_clear(p: Pedestrian, plan: CityPlan, axis: int, index: int, along: float, seconds: float) -> bool:
	var traffic := _traffic_of(p)
	if traffic == null:
		return true
	for c: Variant in traffic.get("cars"):
		if not is_instance_valid(c):
			continue
		var car := c as Vehicle
		if car == null or not car.is_traffic():
			continue
		var t: Dictionary = car.traffic
		if int(t.get("axis", -1)) != axis or int(t.get("index", -99999)) != index:
			continue
		var gap := (along - float(t.get("along", 0.0))) * float(t.get("dir", 1))
		if gap < -6.0:
			continue
		if gap < 7.0 + float(t.get("v", 0.0)) * seconds:
			return false
	return true


## A horn now and then for somebody in the road (a car honks once per few seconds at most).
static func _honk(car: Node3D) -> void:
	var id := car.get_instance_id()
	var now := _now()
	if now < int(_honked.get(id, 0)):
		return
	_honked[id] = now + 5000
	if _honked.size() > 200:
		_honked.clear()
	if absi(hash([id, now / 5000])) % 1000 < int(HONK_SHARE * 1000.0):
		Sfx.play("horn", car.global_position + Vector3.UP, 0.0, 0.94 + 0.1 * float(absi(hash(id)) % 100) / 100.0)


## Somebody hidden inside somewhere near `at` (true world XZ), taken out of the hidden pool.
static func _from_pool(at: Vector2, reach: float) -> Pedestrian:
	for id: int in _hidden.keys():
		var pv: Variant = _hidden[id]
		if not is_instance_valid(pv):
			continue
		var p: Pedestrian = pv
		if not is_instance_valid(p) or p.errand.is_empty() or p._down:
			continue
		var s: Dictionary = (p.errand.steps as Array)[int(p.errand.i)]
		if s.do != "inside" or Vector2(p.position.x, p.position.z).distance_to(at) > reach:
			continue
		p.errand = {}
		return p
	return null


## A walker far enough from the player not to be watched (past FAR_TAKE) but within reach of
## `at`, taken off their pavement for somebody who has to appear here: the crowd cap is usually
## spent, and a walker vanishing a hundred metres off is never seen to.
const FAR_TAKE := 95.0
static func _from_far(near: Node, at: Vector2) -> Pedestrian:
	var player := near.get_tree().get_first_node_in_group("player") as Node3D if near.is_inside_tree() else null
	if player == null:
		return null
	var best: Pedestrian = null
	var best_d := 320.0
	for n in near.get_tree().get_nodes_in_group("pedestrian"):
		var p := n as Pedestrian
		if p == null or p._down or not p.errand.is_empty() or not p._lives() or p._cross == Pedestrian.Cross.CROSSING:
			continue
		if p.global_position.distance_to(player.global_position) < FAR_TAKE:
			continue
		var d := Vector2(p.position.x, p.position.z).distance_to(at)
		if d < best_d:
			best_d = d
			best = p
	if best:
		best._end_act(true)
		best._cross = Pedestrian.Cross.NONE
		best._leave_crosswalk()
	return best


static func _traffic_of(n: Node) -> Node:
	var t: Node = _traffic_ref.get_ref() if _traffic_ref else null
	if t != null and is_instance_valid(t) and t.is_inside_tree():
		return t
	# Up from a walker (its chunk, the city) or a car (the traffic, or the city it is parked in).
	var a := n
	while a != null:
		if a is TrafficManager:
			t = a
			break
		var c := a.get_node_or_null("Traffic")
		if c is TrafficManager:
			t = c
			break
		a = a.get_parent()
	_traffic_ref = weakref(t) if t else null
	return t


## Near enough the player to be doing things (Pedestrian.life_range; the LOD's own flag lags
## half a second behind a walker who has just come out of somewhere).
static func _near(p: Pedestrian) -> bool:
	if p._life_near:
		return true
	var pl := p._player if is_instance_valid(p._player) else p.get_tree().get_first_node_in_group("player") as Node3D
	return pl != null and pl.global_position.distance_to(p.global_position) < p.life_range


static func _rng_of(p: Pedestrian) -> RandomNumberGenerator:
	if p.has_meta("errand_rng"):
		return p.get_meta("errand_rng")
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([p._life_seed, "errand"])
	p.set_meta("errand_rng", rng)
	return rng


static func _now() -> int:
	return Pedestrian._life_now_ms()


## A bone's child direction aimed at `want` (skeleton space: +Z the rig's front, +X its left),
## over whatever the clip left.
static func _aim_bone(skel: Skeleton3D, bone_name: String, child_name: String, want: Vector3) -> void:
	var b := skel.find_bone(bone_name)
	var c := skel.find_bone(child_name)
	if b < 0 or c < 0:
		return
	var g := skel.get_bone_global_pose(b)
	var cur := skel.get_bone_global_pose(c).origin - g.origin
	if cur.length() < 1e-5:
		return
	var turn := Quaternion(cur.normalized(), want.normalized())
	var global_basis := Basis(turn) * g.basis
	var parent := skel.get_bone_parent(b)
	var pb := skel.get_bone_global_pose(parent).basis if parent >= 0 else Basis()
	skel.set_bone_pose_rotation(b, (pb.orthonormalized().inverse() * global_basis.orthonormalized()).get_rotation_quaternion())
