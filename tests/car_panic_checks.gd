extends RefCounted
## Car panic checks for tests/smoke_test.gd (car-panic, 2026-10-05): a shot near a traffic car
## makes its driver react (CarPanic) - a hard stop on the hazards and away again, a swerve and
## back, up the kerb with two wheels and out of the lane's queue (the car behind drives past),
## backing away from a threat ahead with the reversing lamps on, and getting out and running: the
## door open, the driver a walker in the road heading for the pavement, the cabin empty, the car
## behind honking and then going round it on the wrong side while an oncoming car waits, the
## player able to take the car (nobody's crime). The switch off, the cap on a big blast, and no
## two cars inside each other through all of it. Loaded at run time, so it compiles after the
## autoloads and can name CarPanic freely.

var _t: Node
var _tree: SceneTree
var _city: Node3D
var _plan: CityPlan
var _traffic: TrafficManager
var _ws: Node
var _player: Player
var _worst_overlap: float = INF
var _worst_where: String = ""
var _stage: String = ""


func run(t: Node, city: Node3D) -> void:
	_t = t
	_tree = t.get_tree()
	_city = city
	_plan = city.plan
	_traffic = city.get_node("Traffic") as TrafficManager
	_ws = _tree.root.get_node("/root/WorldState")
	_player = _tree.get_first_node_in_group("player") as Player
	if _player.is_driving():
		_player.exit_vehicle()
	var home: Vector3 = _ws.to_world(_player.global_position)
	var police: Node = city.get_node_or_null("Police")
	var police_was: Variant = police.get("enabled") if police else null
	if police:
		police.set("enabled", false)
	var started_ms := Time.get_ticks_msec()
	_traffic.staged = true
	_clear_traffic()
	var road := _find_road(false, Vector2(home.x, home.z))
	if road.is_empty():
		_check(false, "a one-lane open city street near the spawn for the car panic checks")
	else:
		await _brake(road)
		_clear_traffic()
		await _swerve(road)
		_clear_traffic()
		await _kerb(road)
		_clear_traffic()
		await _reverse(road)
		_clear_traffic()
		await _abandon(road)
		_clear_traffic()
		await _switch_and_cap(road)
		_clear_traffic()
	_check(_worst_overlap > -0.05, "no two cars inside each other through the car panic checks (worst gap %.2f m %s)" % [_worst_overlap, _worst_where])
	CarPanic.force_kind = -1
	CarPanic.enabled = OS.get_environment("CAR_PANIC") != "0"
	_traffic.staged = false
	_player.global_position = _ws.to_local(home)
	_player.velocity = Vector3.ZERO
	_city.update_streaming(true)
	if police:
		police.set("enabled", police_was)
	await _ticks(3)
	print("car panic checks took %.1f s" % ((Time.get_ticks_msec() - started_ms) / 1000.0))


func _check(ok: bool, label: String) -> void:
	_t._check(ok, label)


func _ticks(n: int) -> void:
	for i in n:
		await _tree.physics_frame


func _clear_traffic() -> void:
	for c in _traffic.cars.duplicate():
		if is_instance_valid(c):
			_traffic._retire(c)
	_traffic.cars.clear()
	CarPanic.force_kind = -1


## An open city street near `near` with one lane each way (or two, `two`), no trackway, and a
## block at least 150 m long: [axis, index, dir, block start along, block end along] or [].
func _find_road(two: bool, near: Vector2) -> Array:
	var best := []
	var bd := INF
	var c0 := _plan.block_index_at(near)
	for axis: int in [CityPlan.AXIS_X, CityPlan.AXIS_Z]:
		var cross := CityPlan.AXIS_Z if axis == CityPlan.AXIS_X else CityPlan.AXIS_X
		var i0 := c0.x if axis == CityPlan.AXIS_X else c0.y
		var k0 := c0.y if axis == CityPlan.AXIS_X else c0.x
		for index in range(i0 - 8, i0 + 9):
			if (TrafficAI.lanes_of(_plan, axis, index) >= 2) != two or _traffic._rail_street(axis, index):
				continue
			for k in range(k0 - 8, k0 + 9):
				var lo := _plan.road_pos(cross, k) + _plan.road_width(cross, k) * 0.5
				var hi := _plan.road_pos(cross, k + 1) - _plan.road_width(cross, k + 1) * 0.5
				if hi - lo < 150.0:
					continue
				var road := _plan.road_pos(axis, index)
				var mid := (lo + hi) * 0.5
				var q := Vector2(road, mid) if axis == CityPlan.AXIS_X else Vector2(mid, road)
				if _plan.zone_at(q) != MacroMap.Zone.CITY or _traffic._replica_blocks(q, 6.0):
					continue
				if not (_plan.road_open(axis, index, lo + 2.0) and _plan.road_open(axis, index, hi - 2.0)):
					continue
				var d := q.distance_to(near)
				if d < bd:
					bd = d
					best = [axis, index, 1, lo, hi]
	return best


## Stands the player off the road on the far side's pavement, level with `along`, and streams.
func _stand(road: Array, along: float, far: bool = true) -> void:
	var axis: int = road[0]
	var index: int = road[1]
	var dir: int = road[2]
	var kerb_sign := float(-dir if axis == CityPlan.AXIS_X else dir)
	var off := (-kerb_sign if far else kerb_sign) * (_plan.road_width(axis, index) * 0.5 + 3.0)
	var p := Vector2(_plan.road_pos(axis, index) + off, along) if axis == CityPlan.AXIS_X else Vector2(along, _plan.road_pos(axis, index) + off)
	_player.global_position = _ws.to_local(Vector3(p.x, _plan.height_at(p) + 1.2, p.y))
	_player.velocity = Vector3.ZERO
	_city.update_streaming(true)


## A scene point `ahead` metres up the road from `car` and `side` metres toward its kerb.
func _beside(car: Vehicle, road: Array, ahead: float, side: float) -> Vector3:
	var axis: int = road[0]
	var dir: int = road[2]
	var kerb_sign := float(-dir if axis == CityPlan.AXIS_X else dir)
	var w: Vector3 = _ws.to_world(car.global_position)
	var p := w + (Vector3(kerb_sign * side, 1.2, float(dir) * ahead) if axis == CityPlan.AXIS_X else Vector3(float(dir) * ahead, 1.2, kerb_sign * side))
	return _ws.to_local(p)


func _along(car: Vehicle, axis: int) -> float:
	var w: Vector3 = _ws.to_world(car.global_position)
	return w.z if axis == CityPlan.AXIS_X else w.x


func _lat(car: Vehicle, road: Array) -> float:
	var w: Vector3 = _ws.to_world(car.global_position)
	return (w.x if int(road[0]) == CityPlan.AXIS_X else w.z) - _plan.road_pos(int(road[0]), int(road[1]))


## The worst bumper gap (negative: inside) between any two of `cars` sharing a lateral band.
func _note_overlaps(cars: Array, road: Array) -> void:
	for i in cars.size():
		for j in range(i + 1, cars.size()):
			var a: Vehicle = cars[i]
			var b: Vehicle = cars[j]
			if not is_instance_valid(a) or not is_instance_valid(b) or not a.is_traffic() or not b.is_traffic():
				continue
			if absf(_lat(a, road) - _lat(b, road)) > 1.9:
				continue
			var d := absf(_along(a, int(road[0])) - _along(b, int(road[0])))
			var gap := d - float(a.traffic.get("half", 2.4)) - float(b.traffic.get("half", 2.4))
			if gap < _worst_overlap:
				_worst_overlap = gap
				_worst_where = "%s (lats %.2f / %.2f, kinds %s / %s)" % [_stage, _lat(a, road), _lat(b, road), str(a.traffic.get("cp", {}).get("k", "-")), str(b.traffic.get("cp", {}).get("k", "-"))]


## A car told of a shot: stamps on the brake, stands on the hazards, drives on.
func _brake(road: Array) -> void:
	var axis: int = road[0]
	var lo: float = road[3]
	_stand(road, lo + 60.0)
	await _ticks(3)
	CarPanic.force_kind = CarPanic.Kind.BRAKE
	var car := _traffic.place_car(axis, int(road[1]), int(road[2]), 0, lo + 25.0, 11.0, false)
	await _ticks(3)
	var a0 := _along(car, axis)
	Pedestrian.alarm(_tree, _beside(car, road, 14.0, -4.0), 45.0, 1, false, "")
	var reacted := car.traffic.has("cp") and int(car.traffic.cp.k) == CarPanic.Kind.BRAKE
	var stop_at := INF
	var hazard := false
	var resumed := false
	for i in 60 * 14:
		await _tree.physics_frame
		var t: Dictionary = car.traffic
		if stop_at == INF and float(t.get("v", 1.0)) <= 0.0:
			stop_at = (_along(car, axis) - a0) * float(road[2])
		hazard = hazard or t.get("hazard", false)
		if stop_at < INF and not t.has("cp") and float(t.get("v", 0.0)) > 2.0:
			resumed = true
			break
	_check(reacted and stop_at < 13.0 and hazard and resumed,
		"a driver near a shot brakes hard, stands on the hazards and drives on (reacted %s, stopped in %.1f m, hazards %s, drove on %s)" % [reacted, stop_at, hazard, resumed])


## A swerve away from the threat and back into the lane.
func _swerve(road: Array) -> void:
	var axis: int = road[0]
	var lo: float = road[3]
	_stand(road, lo + 60.0)
	await _ticks(3)
	CarPanic.force_kind = CarPanic.Kind.SWERVE
	var car := _traffic.place_car(axis, int(road[1]), int(road[2]), 0, lo + 25.0, 11.0, false)
	await _ticks(3)
	var lat0 := _lat(car, road)
	# The shot on the far side: it jinks toward the kerb, as far as the parked cars leave room.
	Pedestrian.alarm(_tree, _beside(car, road, 12.0, -6.0), 45.0, 1, false, "")
	var most := 0.0
	var back := false
	for i in 60 * 14:
		await _tree.physics_frame
		most = maxf(most, absf(_lat(car, road) - lat0))
		if most > 0.2 and not car.traffic.has("cp"):
			back = absf(_lat(car, road) - lat0) < 0.1
			break
	_check(most > 0.2 and back, "a swerving driver jinks away from a shot and comes back into the lane (most %.2f m, back %s)" % [most, back])


## Up the kerb with two wheels where it is clear, out of the lane's queue: the car behind drives
## past it. Where no stretch near the spawn is clear, a KERB falls back to a SWERVE.
func _kerb(road: Array) -> void:
	_stage = "_kerb"
	var axis: int = road[0]
	var index: int = road[1]
	var dir: int = road[2]
	var lo: float = road[3]
	var hi: float = road[4]
	var car: Vehicle = null
	var at := lo + 20.0
	while at < hi - 60.0:
		_stand(road, at + 40.0)
		await _ticks(2)
		car = _traffic.place_car(axis, index, dir, 0, at, 9.0, false)
		await _ticks(2)
		if CarPanic.kerb_clear(_traffic, car, CarPanic._frame(_traffic, car)):
			break
		_traffic.cars.erase(car)
		_traffic._retire(car)
		car = null
		at += 9.0
	if car == null:
		CarPanic.force_kind = CarPanic.Kind.KERB
		car = _traffic.place_car(axis, index, dir, 0, lo + 25.0, 9.0, false)
		await _ticks(2)
		Pedestrian.alarm(_tree, _beside(car, road, 10.0, -5.0), 45.0, 1, false, "")
		var fell := car.traffic.has("cp") and int(car.traffic.cp.k) == CarPanic.Kind.SWERVE
		_check(fell, "with no clear kerb near the spawn a driver told to mount it swerves instead (%s)" % fell)
		return
	CarPanic.force_kind = CarPanic.Kind.KERB
	var follower := _traffic.place_car(axis, index, dir, 0, at - 30.0, 9.0, false)
	await _ticks(2)
	CarPanic.start(_traffic, car, _beside(car, road, 10.0, -5.0), 0.2, false)
	var w2 := _plan.road_width(axis, index) * 0.5
	var up := false
	var out_of_lane := false
	var passed := false
	var back := false
	for i in 60 * 22:
		await _tree.physics_frame
		_note_overlaps([car, follower], road)
		var lat := absf(_lat(car, road))
		up = up or lat > w2 - 0.6
		if car.traffic.has("cp"):
			out_of_lane = out_of_lane or float(car.traffic.lane) != float(car.traffic.cp.lane0)
		passed = passed or (_along(follower, axis) - _along(car, axis)) * float(dir) > 3.0
		if passed and up and not car.traffic.has("cp"):
			back = true
			break
	_check(up and out_of_lane and passed and back,
		"a driver mounts the clear kerb with two wheels, out of the lane's queue, the car behind drives past, and it comes back down (up %s, out of the queue %s, passed %s, back %s)" % [up, out_of_lane, passed, back])


## A threat ahead: it backs away, reversing lamps on, never into the car behind.
func _reverse(road: Array) -> void:
	_stage = "_reverse"
	var axis: int = road[0]
	var dir: int = road[2]
	var lo: float = road[3]
	_stand(road, lo + 80.0)
	await _ticks(3)
	CarPanic.force_kind = CarPanic.Kind.REVERSE
	var car := _traffic.place_car(axis, int(road[1]), dir, 0, lo + 70.0, 10.0, false)
	var behind := _traffic.place_car(axis, int(road[1]), dir, 0, lo + 30.0, 0.0, false)
	await _ticks(3)
	Pedestrian.alarm(_tree, _beside(car, road, 22.0, -1.0), 45.0, 1, false, "")
	var furthest := -INF
	var a_stop := INF
	var lamps := false
	var resumed := false
	for i in 60 * 16:
		await _tree.physics_frame
		_note_overlaps([car, behind], road)
		var a := _along(car, axis) * float(dir)
		if a_stop == INF and float(car.traffic.get("v", 1.0)) <= 0.0:
			a_stop = a
		if a_stop < INF:
			furthest = maxf(furthest, a_stop - a)
		lamps = lamps or car.light_reverse or bool(car.traffic.get("rev", false))
		if a_stop < INF and not car.traffic.has("cp"):
			resumed = true
			break
	_check(furthest > 2.0 and lamps and resumed,
		"a driver with the shooting ahead backs away on the reversing lamps, short of the car behind, then drives on (backed %.1f m, lamps %s, drove on %s)" % [furthest, lamps, resumed])


## Getting out and running: the door opens, the driver is a walker heading off the road, the
## cabin empties; the car behind honks and goes round on the wrong side while an oncoming car
## waits; the player can take the abandoned car.
func _abandon(road: Array) -> void:
	_stage = "_abandon"
	var axis: int = road[0]
	var index: int = road[1]
	var dir: int = road[2]
	var lo: float = road[3]
	_stand(road, lo + 45.0)
	await _ticks(4)
	CarPanic.force_kind = CarPanic.Kind.ABANDON
	var car := _traffic.place_car(axis, index, dir, 0, lo + 40.0, 9.0, false)
	var follower := _traffic.place_car(axis, index, dir, 0, lo + 18.0, 9.0, false)
	await _ticks(3)
	var honks0 := int(CarPanic.counts.get("honk", 0))
	var drivers0 := int(CarPanic.counts.get("driver", 0))
	var rounds0 := int(CarPanic.counts.get("round", 0))
	# Only this car's driver hears it (the one behind must stay to go round it).
	CarPanic.start(_traffic, car, _beside(car, road, 10.0, -6.0), 0.2, false)
	var opened := false
	var ran := false
	var empty := false
	var walker: Pedestrian = null
	var passed := false
	var oncoming: Vehicle = null
	var yielded := false
	for i in 60 * 26:
		await _tree.physics_frame
		_note_overlaps([car, follower], road)
		var pc := car.get_node_or_null("PanicCar") as PanicCar
		if pc:
			opened = opened or pc.is_open()
			if pc.driver != null and is_instance_valid(pc.driver):
				walker = pc.driver
				ran = ran or walker._panic_left > 0.0
		empty = empty or (opened and car._cabin_seats() == 0)
		# An oncoming car once the follower has started round.
		var ft: Dictionary = follower.traffic if is_instance_valid(follower) else {}
		if oncoming == null and ft.has("cp") and int(ft.cp.k) == CarPanic.Kind.ROUND:
			oncoming = _traffic.place_car(axis, index, -dir, 0, _along(car, axis) + float(dir) * 75.0, 9.0, false)
		if OS.get_environment("CP_DEBUG") == "1" and i % 30 == 0 and ft.has("cp"):
			print("CPDBG %d %s lat %.2f v %.2f along %.1f obs %.1f" % [i, str(ft.cp.get("ph")), float(ft.cp.lat), float(ft.get("v", 0.0)), _along(follower, axis), _along(car, axis)])
		if oncoming != null and is_instance_valid(oncoming) and oncoming.traffic.has("cp"):
			yielded = yielded or int(oncoming.traffic.cp.k) == CarPanic.Kind.YIELD
		if is_instance_valid(follower) and (_along(follower, axis) - _along(car, axis)) * float(dir) > 6.0 and not ft.has("cp"):
			passed = true
			break
	_check(opened and empty and int(CarPanic.counts.get("driver", 0)) > drivers0 and ran,
		"a driver who abandons the car opens the door, gets out and runs, and the cabin is empty (door %s, empty %s, a running walker %s)" % [opened, empty, ran])
	_check(int(CarPanic.counts.get("honk", 0)) > honks0 and int(CarPanic.counts.get("round", 0)) > rounds0 and passed and yielded,
		"the car behind an abandoned car honks, goes round it on the wrong side while an oncoming car waits, and gets back in its lane (honked %s, went round %s, past %s, oncoming waited %s)" % [
			int(CarPanic.counts.get("honk", 0)) > honks0, int(CarPanic.counts.get("round", 0)) > rounds0, passed, yielded])
	# The player takes it: out of the traffic, nobody's crime, the door shut behind them.
	var can := CarPanic.is_abandoned(car)
	var p: Vector3 = _ws.to_world(car.global_position)
	_player.global_position = _ws.to_local(p + Vector3(0.0, 1.0, 0.0))
	_player.enter_vehicle(car)
	await _ticks(70)
	var taken := _player.is_driving() and _player.vehicle == car and not car.is_traffic() and not Police.innocent
	var shut := car.get_node_or_null("PanicCar") == null
	_player.exit_vehicle()
	await _ticks(2)
	_check(can and taken and shut, "the player can take an abandoned car: it leaves the traffic and the door shuts (abandoned %s, taken %s, door shut %s)" % [can, taken, shut])
	if is_instance_valid(car):
		car.queue_free()
	if walker != null and is_instance_valid(walker):
		walker.queue_free()


## The switch off: nobody reacts. A big blast near a crowd of cars: at most MAX_PANIC react.
func _switch_and_cap(road: Array) -> void:
	var axis: int = road[0]
	var index: int = road[1]
	var dir: int = road[2]
	var lo: float = road[3]
	_stand(road, lo + 70.0)
	await _ticks(3)
	CarPanic.enabled = false
	var car := _traffic.place_car(axis, index, dir, 0, lo + 40.0, 9.0, false)
	await _ticks(2)
	Pedestrian.alarm(_tree, _beside(car, road, 10.0, -4.0), 45.0, 1, false, "")
	var calm := not car.traffic.has("cp")
	CarPanic.enabled = true
	_check(calm, "CAR_PANIC off: a shot near a car changes nothing (%s)" % calm)
	_clear_traffic()
	var cars: Array = []
	for k in 9:
		cars.append(_traffic.place_car(axis, index, dir, 0, lo + 10.0 + 14.0 * k, 0.0, false))
		cars.append(_traffic.place_car(axis, index, -dir, 0, lo + 12.0 + 14.0 * k, 0.0, false))
	await _ticks(2)
	Pedestrian.alarm(_tree, _beside(cars[8], road, 0.0, -1.0), 120.0, 5, true, "")
	var n := 0
	for c: Vehicle in cars:
		if c.traffic.has("cp"):
			n += 1
	_check(n > 4 and n <= CarPanic.MAX_PANIC, "a blast among %d cars sets off the nearest, no more than the cap (%d of them, cap %d)" % [cars.size(), n, CarPanic.MAX_PANIC])
