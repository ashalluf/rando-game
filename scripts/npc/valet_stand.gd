class_name ValetStand
extends Node3D
## One valet stand at work (Valets): the cars it has called in, the one being served at the
## drop-off, its valets at the podium, away driving a car or bringing one back. A child of the
## stand's chunk (its space is the true world plan, like the chunk's walkers'); one tick a
## physics frame, and nothing at all while the player is further than ACTIVE_RANGE.
##
## * Arrivals: every arrival_gap() seconds (a hash-seeded stream per stand) a car is called in -
##   a street car already coming down the kerb lane toward the stand, else one from the traffic's
##   pool placed upstream (TrafficManager.place_car()). It is tagged (`traffic.valet`, the stand's
##   instance id) and the traffic drives it to the drop-off as to a bus stop (Valets.street_stop),
##   on its hazards for the last stretch; the ones behind queue on theirs.
## * DROP: at the drop-off its driver's door swings open (ErrandProps), the driver gets out and
##   walks into the building (a StreetErrands walker: a hidden one from near by, else a new one
##   under the crowd cap), a free valet runs round the tail to the door, gets in, and the car pulls
##   away as ordinary traffic ("to the lot round the block"); that valet is away RETURN seconds.
## * RETURN: a valet's time is up - a car from the pool is placed upstream with them at the wheel
##   and pulls in, they get out and run back to the podium, a guest comes out of the door to the
##   car, gets in and drives off.
## A car shot, crashed, panicking (CarPanic) or taken away mid-service is let go and whoever was
## to get in it goes back to the podium.

## Metres from the player inside which the stand calls cars in and serves them.
const ACTIVE_RANGE := 115.0
## Most cars called in at once (the one being served and the queue behind it).
const MAX_QUEUE := 3
## Where an arriving car is found or placed: metres upstream of the drop-off.
const CALL_REACH := Vector2(30.0, 110.0)
const PLACE_AT := Vector2(70.0, 100.0)
## Seconds a valet is away with a car before bringing one back.
const RETURN_SECONDS := Vector2(35.0, 90.0)
## Seconds the car stands after its door shuts before it pulls away.
const PULL_DELAY := 1.0
## The hazards come on this far from the drop-off (m).
const HAZARD_REACH := 32.0
## A served car standing longer than this (s) without anyone getting in is sent off anyway.
const SERVE_PATIENCE := 45.0

enum Serve { NONE, DROP_OPEN, DROP_WAIT_VALET, DROP_IN, RET_OPEN, RET_WAIT_GUEST, RET_GUEST_IN, PULL }

## The stand (Valets.plan_chunk()'s dictionary).
var s: Dictionary = {}
var valets: Array = []
## Cars called in, oldest first.
var queue: Array = []
var front: Vehicle = null
var serve: int = Serve.NONE
## Away valets: [valet, seconds left].
var away: Array = []
## Counters the checks read: cars served (dropped off), brought back, called, placed.
var served: int = 0
var returned: int = 0
var called: int = 0
var placed: int = 0
## Off: the stand serves only what a check hands it (no arrivals or returns of its own).
var manual: bool = false

var _clock: float = 0.0
var _next_arrival: float = 0.0
var _hour: float = 13.0
var _rng := RandomNumberGenerator.new()
var _door: Node3D = null
var _open: float = 0.0
var _want_open: bool = false
var _t: float = 0.0
var _runner: Valet = null
var _guest: Pedestrian = null
var _tick: int = 0


func setup(stand: Dictionary, hour: float) -> void:
	add_to_group("valet_stand")
	s = stand
	_hour = hour
	_rng.seed = hash([int(stand.key), "valet_stand"])
	var gap := Valets.arrival_gap(bool(s.hotel), _hour)
	_next_arrival = _rng.randf_range(2.0, gap.x)


## A valet of this stand, `i`-th, made now in `chunk` (the build step already took crowd room).
func add_valet(chunk: Node, i: int, seed_value: int) -> Valet:
	var pod: Vector2 = s.podium
	var trav: Vector2 = s.trav
	var out_d: Vector2 = s.out
	# The first stands behind the podium facing the road; the others to either side of it.
	var at := pod - out_d * 0.55 + trav * (0.0 if i == 0 else (1.3 if i == 1 else -1.4))
	var face := out_d if i == 0 else (out_d - trav * 0.6).normalized() if i == 1 else (out_d + trav * 0.6).normalized()
	var v := Valet.new()
	v.setup_valet(s.rect, seed_value, at, atan2(-face.x, -face.y), int(s.uniform))
	v.name = "Valet_%s_%d" % [String(s.id), i]
	v.position = Vector3(at.x, (chunk as CityChunk).ground_y(at.x, at.y) + 0.1, at.y)
	chunk.add_child(v)
	valets.append(v)
	return v


func _physics_process(delta: float) -> void:
	_clock += delta
	_open = move_toward(_open, 1.0 if _want_open else 0.0, delta / ErrandProps.DOOR_TIME)
	if is_instance_valid(_door):
		ErrandProps.swing(_door, _open)
	_tick += 1
	_prune()
	if not Valets.enabled:
		return
	var near := _player_near()
	if not near and front == null and queue.is_empty():
		# Nobody to see it: everybody back at the podium.
		for a: Array in away:
			var v := a[0] as Valet
			if is_instance_valid(v):
				v.home_now()
		away.clear()
		return
	for a: Array in away:
		a[1] = float(a[1]) - delta
	if near and not manual:
		_maybe_arrival()
		_maybe_return()
	_serve(delta)


# --- Called in ---------------------------------------------------------------------------------

func _maybe_arrival() -> void:
	if _clock < _next_arrival:
		return
	var gap := Valets.arrival_gap(bool(s.hotel), _hour)
	_next_arrival = _clock + _rng.randf_range(gap.x, gap.y)
	# Somebody stays at the podium: no new car while only one valet is back.
	if queue.size() >= MAX_QUEUE or _free_valets() < mini(2, valets.size()):
		return
	var traffic := _traffic()
	if traffic == null or traffic.get("staged"):
		return
	var car := _pick_arrival(traffic)
	if car == null:
		car = _place_car(traffic, false)
	if car != null:
		take(car, false)


## Tags `car` (a street car on this stand's road) as one of the stand's: the traffic drives it in.
func take(car: Vehicle, bringing_back: bool, valet: Valet = null) -> void:
	var t: Dictionary = car.traffic
	t.valet = get_instance_id()
	t.no_turns = true
	t.placed = true
	t.turn = 0
	if bringing_back:
		t.valet_return = valet.get_instance_id() if valet else 0
	car.set_meta("valet", true)
	car.set_meta("errand", true)
	queue.append(car)
	called += 1


## A street car in this stand's kerb lane, coming toward the drop-off, doing nothing else.
func _pick_arrival(traffic: Node) -> Vehicle:
	var stop_s := float(s.stop_s)
	var tdir := int(s.tdir)
	for car: Vehicle in traffic.get("cars"):
		if not is_instance_valid(car) or not StreetErrands._may_park(car):
			continue
		var t: Dictionary = car.traffic
		if t.has("valet") or int(t.axis) != int(s.axis) or int(t.index) != int(s.index) or int(t.dir) != tdir:
			continue
		var ahead := (stop_s - float(t.get("along", 0.0))) * float(tdir)
		if ahead < CALL_REACH.x or ahead > CALL_REACH.y:
			continue
		return car
	return null


## A car from the traffic's pool placed in the kerb lane upstream, or null when the lane is busy.
func _place_car(traffic: Node, bringing_back: bool) -> Vehicle:
	var plan: CityPlan = traffic.get("plan")
	var axis := int(s.axis)
	var index := int(s.index)
	var tdir := int(s.tdir)
	var lanes := int(s.lanes)
	var along := float(s.stop_s) - float(tdir) * _rng.randf_range(PLACE_AT.x, PLACE_AT.y)
	if not plan.road_open(axis, index, along):
		return null
	var width := plan.road_width(axis, index)
	var side := -tdir if axis == CityPlan.AXIS_X else tdir
	var lane := float(side) * CityPlan.lane_center(width, lanes, lanes - 1)
	if not traffic.call("_lane_clear", axis, index, tdir, lane, along, 14.0):
		return null
	var car: Vehicle = traffic.call("place_car", axis, index, tdir, lanes - 1, along, 8.0, false)
	if car == null:
		return null
	placed += 1
	if bringing_back:
		car.set_meta("valet_back", true)
	return car


## A valet whose time away is up is brought back in a car.
func _maybe_return() -> void:
	if away.is_empty() or queue.size() >= MAX_QUEUE:
		return
	var a: Array = away[0]
	if float(a[1]) > 0.0:
		return
	var traffic := _traffic()
	if traffic == null or traffic.get("staged"):
		return
	var car := _place_car(traffic, true)
	if car == null:
		a[1] = 3.0
		return
	away.remove_at(0)
	take(car, true, a[0] as Valet)


# --- The drop-off ------------------------------------------------------------------------------

## TrafficManager (through Valets.street_stop): `car`'s stop at the drop-off.
func stop_for(traffic: Node, car: Vehicle, t: Dictionary, along: float, v: float) -> Vector2:
	if not queue.has(car):
		Valets.release_car(car)
		return Vector2(INF, 0.0)
	var to_stop := (float(s.stop_s) - along) * float(s.tdir)
	if to_stop < -4.0 and car != front:
		# Went past it (put down too close): let it go.
		_drop(car)
		return Vector2(INF, 0.0)
	var plan: CityPlan = traffic.get("plan")
	var width := plan.road_width(int(s.axis), int(s.index))
	# Into the stand's kept stretch of parking lane; double-parked where the lane is the
	# neighbour chunk's (its parked cars may stand there).
	var shift := 0.0 if bool(s.double) else CityPlan.parking_offset(width) - absf(float(t.lane))
	t.hazard = to_stop < HAZARD_REACH
	if v < 0.3 and to_stop < 1.5 and front == null and float(t.get("shift", 0.0)) > shift - 0.15:
		_arrived(car)
	if car == front:
		return Vector2(maxf(to_stop, 0.0), shift)
	return Vector2(to_stop, shift * clampf((30.0 - to_stop) / 22.0, 0.0, 1.0))


func _arrived(car: Vehicle) -> void:
	front = car
	_t = 0.0
	_door = ErrandProps.door_node(car)
	_open = 0.0
	if car.traffic.has("valet_return"):
		serve = Serve.RET_OPEN
	else:
		serve = Serve.DROP_OPEN


func _serve(delta: float) -> void:
	if front == null:
		return
	_t += delta
	var geo := car_frame(front)
	match serve:
		Serve.DROP_OPEN:
			if _t > 0.6:
				_want_open = true
			if _open > 0.6 and _guest == null:
				# The driver out, into the building.
				_guest = _spawn_guest(Vector2(geo.door_in), float(geo.yaw) + PI * 0.5)
				if _guest != null:
					_guest.errand = {"steps": [
						{"do": "path", "pts": [geo.door_out, geo.behind, geo.kerb], "road": true, "jay": [int(s.axis), int(s.index)]},
						{"do": "path", "pts": [s.front, s.door]},
						{"do": "hide", "secs": _rng.randf_range(60.0, 240.0)},
					], "i": 0}
				front._npc_driver = false
				front._update_occupant(true)
				serve = Serve.DROP_WAIT_VALET
				_t = 0.0
		Serve.DROP_WAIT_VALET:
			if _want_open and (_t > 2.4 or _guest == null or not is_instance_valid(_guest) \
					or Vector2(_guest.position.x, _guest.position.z).distance_to(geo.door_out) > 1.8):
				_want_open = false
			if _runner == null:
				_runner = _free_valet()
				if _runner != null:
					var done := func() -> void: _runner_at_door()
					_runner.run_job([_kerb_point(Vector2(geo.kerb)), geo.kerb, geo.behind, geo.door_out], _runner.run_pace, done, float(geo.yaw) - PI * 0.5)
			elif not is_instance_valid(_runner) or (not _runner.busy() and not _runner.hidden):
				# Called off (a fright): another valet takes it.
				_runner = null
			if _t > SERVE_PATIENCE:
				_pull()
		Serve.DROP_IN:
			if _open > 0.95 and _t > 0.5 and is_instance_valid(_runner) and not _runner.hidden:
				_runner.hide_in_car()
				away.append([_runner, _rng.randf_range(RETURN_SECONDS.x, RETURN_SECONDS.y)])
				_runner = null
				front._npc_driver = true
				front._update_occupant(true)
				_want_open = false
				served += 1
				serve = Serve.PULL
				_t = 0.0
			elif _t > 6.0:
				_pull()
		Serve.RET_OPEN:
			if _t > 0.6:
				_want_open = true
			if _open > 0.7:
				var v := instance_from_id(int(front.traffic.get("valet_return", 0))) as Valet
				front._npc_driver = false
				front._update_occupant(true)
				if v != null and is_instance_valid(v) and v.hidden:
					v.show_at(Vector2(geo.door_out), float(geo.yaw) - PI * 0.5)
					var home := func() -> void: v._work(true)
					v.run_job([geo.behind, geo.kerb, _kerb_point(Vector2(geo.kerb)), v.home], v.walk_pace * 1.6, home, v.home_yaw)
				# The guest out of the door to the car.
				_guest = _spawn_guest(Vector2(s.door), atan2(-(s.out as Vector2).x, -(s.out as Vector2).y))
				if _guest != null:
					_guest.errand = {"steps": [
						{"do": "path", "pts": [s.front, _kerb_point(Vector2(geo.kerb)), geo.kerb]},
						{"do": "path", "pts": [geo.behind, geo.door_out], "road": true, "jay": [int(s.axis), int(s.index)]},
						{"do": "hide", "secs": 600.0},
					], "i": 0}
				serve = Serve.RET_WAIT_GUEST
				_t = 0.0
				returned += 1
		Serve.RET_WAIT_GUEST:
			if _want_open and _t > 2.2:
				_want_open = false
			if _guest == null or not is_instance_valid(_guest) or _t > SERVE_PATIENCE:
				_pull()
				return
			var gp := Vector2(_guest.position.x, _guest.position.z)
			if gp.distance_to(geo.door_out) < 1.6:
				_want_open = true
			if not _guest.visible:
				serve = Serve.RET_GUEST_IN
				_t = 0.0
		Serve.RET_GUEST_IN:
			if _t > 0.8:
				_want_open = false
				front._npc_driver = true
				front._update_occupant(true)
				serve = Serve.PULL
				_t = 0.0
		Serve.PULL:
			if _open <= 0.0 and _t > PULL_DELAY:
				_pull()


## The runner reached the driver's door: in.
func _runner_at_door() -> void:
	if front == null or serve != Serve.DROP_WAIT_VALET:
		if is_instance_valid(_runner):
			_runner._work(false)
		_runner = null
		return
	_want_open = true
	serve = Serve.DROP_IN
	_t = 0.0


## The served car pulls away: ordinary traffic again.
func _pull() -> void:
	if front != null and is_instance_valid(front):
		if not front._npc_driver:
			front._npc_driver = true
			front._update_occupant(true)
		_drop(front)
	_end_service()


func _end_service() -> void:
	if is_instance_valid(_door):
		_door.queue_free()
	_door = null
	_open = 0.0
	_want_open = false
	if _runner != null and is_instance_valid(_runner) and not _runner.hidden:
		_runner.cancel_job()
		_runner._work(false)
	_runner = null
	_guest = null
	front = null
	serve = Serve.NONE
	_t = 0.0


## `car` is not the stand's any more.
func _drop(car: Vehicle) -> void:
	queue.erase(car)
	if is_instance_valid(car):
		# A valet riding in a car being let go mid-way is back at the podium (nobody sees it).
		var back := instance_from_id(int(car.traffic.get("valet_return", 0))) as Valet if car.is_traffic() else null
		if back != null and is_instance_valid(back) and back.hidden:
			back.home_now()
		Valets.release_car(car)


## Cars gone, shot, panicking or taken away are let go.
func _prune() -> void:
	for i in range(queue.size() - 1, -1, -1):
		var car: Variant = queue[i]
		var bad: bool = not is_instance_valid(car)
		if not bad:
			var c := car as Vehicle
			bad = not c.is_traffic() or not c.is_inside_tree() or c.is_wreck() or c.driver != null \
				or c.traffic.has("cp") or int(c.traffic.get("valet", 0)) != get_instance_id()
		if bad:
			if car == front:
				front = null
				_end_service()
			queue.remove_at(i)
			if is_instance_valid(car):
				var c := car as Vehicle
				var back := instance_from_id(int(c.traffic.get("valet_return", 0))) as Valet if c.is_traffic() else null
				if back != null and is_instance_valid(back) and back.hidden:
					back.home_now()
				if c.is_traffic():
					Valets.release_car(c)
				if c.has_meta("valet"):
					c.remove_meta("valet")
	for i in range(valets.size() - 1, -1, -1):
		var v: Variant = valets[i]
		if not is_instance_valid(v) or (v as Valet)._down:
			valets.remove_at(i)
	for i in range(away.size() - 1, -1, -1):
		if not is_instance_valid(away[i][0]):
			away.remove_at(i)


func _exit_tree() -> void:
	for car: Variant in queue:
		if is_instance_valid(car) and (car as Vehicle).is_traffic():
			Valets.release_car(car)
	queue.clear()
	if is_instance_valid(_door):
		_door.queue_free()


# --- Helpers -----------------------------------------------------------------------------------

## A valet at the podium free for a job: the lead (the first) only when nobody else is.
func _free_valet() -> Valet:
	for i in range(valets.size() - 1, -1, -1):
		var v: Variant = valets[i]
		if is_instance_valid(v) and (v as Valet).free_for_job():
			return v
	return null


func _free_valets() -> int:
	var n := 0
	for v: Variant in valets:
		if is_instance_valid(v) and not (v as Valet).hidden:
			n += 1
	return n


## A driver or a guest: a hidden walker near by (no one is made or lost), else a new one under
## the crowd cap, shown at `at` (true world XZ) facing `yaw`. Null when neither is possible.
func _spawn_guest(at: Vector2, yaw: float) -> Pedestrian:
	var p := StreetErrands._from_pool(at, 160.0)
	if p != null:
		StreetErrands._show(p, at, yaw)
	else:
		var chunk := get_parent() as CityChunk
		if chunk == null or chunk.level != CityChunk.Level.FULL or not chunk._take_crowd_room():
			return null
		p = Pedestrian.new()
		p.setup(s.rect, chunk.plan.sidewalk_width, hash([chunk.plan.seed, int(s.key), "guest", served, returned, called]))
		p.position = Vector3(at.x, chunk.ground_y(at.x, at.y) + 0.1, at.y)
		chunk.add_child(p)
		p._visual.rotation.y = yaw
		p._faced = true
		if StreetErrands.on_carriageway(chunk.plan, at):
			p.position.y -= CityChunk.SIDEWALK_TOP - CityChunk.ROAD_TOP
	p.ring = s.rect
	return p


## The kerb face's point level with `p` (on the pavement, just in from the edge).
func _kerb_point(p: Vector2) -> Vector2:
	var o: Vector2 = s.out
	var k := float(s.kerb) - (o.y if bool(s.xrun) else o.x) * 0.5
	return Vector2(p.x, k) if bool(s.xrun) else Vector2(k, p.y)


## Where to stand at a car's driver door and so on (true world XZ), from its pose now.
func car_frame(car: Vehicle) -> Dictionary:
	var xf := car.global_transform
	var wp := WorldState.to_world(xf.origin)
	var fwd3 := -xf.basis.z
	var fwd := Vector2(fwd3.x, fwd3.z).normalized()
	var right := Vector2(-fwd.y, fwd.x)
	var dims := car._dims()
	var half := float(dims.length) * 0.5
	var w := float(dims.width) * 0.5
	var door_z := ErrandProps.door_stand(car).z
	var pos := Vector2(wp.x, wp.z)
	var at_door := pos - fwd * door_z
	return {
		"pos": pos, "yaw": atan2(-fwd.x, -fwd.y),
		"door_out": at_door - right * (w + 0.62),
		"door_in": at_door - right * (w - 0.25),
		"behind": pos - fwd * (half + 0.9) - right * 0.3,
		"kerb": pos - fwd * (half + 0.9) + right * (w + 0.9),
	}


func _traffic() -> Node:
	return StreetErrands._traffic_of(self)


func _player_near() -> bool:
	var pl := get_tree().get_first_node_in_group("player") as Node3D if is_inside_tree() else null
	if pl == null:
		return false
	var pp := WorldState.to_world(pl.global_position)
	return Vector2(pp.x, pp.z).distance_to(s.podium) < ACTIVE_RANGE
