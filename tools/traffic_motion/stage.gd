extends RefCounted
## Stills of traffic moving, for tools/glshot/still_shot.gd TMOTION=brake|pull|turn (with
## TMOTION_STEPS="s,s,..." seconds before each still, saved as OUT with _m1, _m2, ... added):
##   brake  a car at 12 m/s brakes to a stop behind a standing one, seen side-on from the pavement
##   pull   three cars wait at a red; it turns green at the first step and they pull away
##   turn   a car turns off the street at the junction in front of a camera on the corner
## The traffic is staged (TrafficManager.staged, its own tick off) and moved only by advance(),
## which drives it, ticks every car's wheels and body (Vehicle._update_wheels) and forces the turn
## and the greens. Loaded, not named: still_shot compiles before the autoloads exist.
## TRAFFIC_MOTION=0 on the same command is the before.

static var _car: Vehicle
static var _cars: Array = []
static var _node := Vector2i.ZERO
static var _axis: int = 0
static var _turn: int = 0
static var _green_at: float = -1.0
static var _clock: float = 0.0


## Stages `kind` near `cam` and returns the EYE string for still_shot ("" when nothing fits).
static func stage(tm: TrafficManager, kind: String, cam: Camera3D) -> String:
	if tm == null or cam == null:
		return ""
	tm.staged = true
	for c in tm.cars.duplicate():
		if is_instance_valid(c):
			tm._retire(c)
	tm.cars.clear()
	tm.set_physics_process(false)
	TrafficMotion.react_placed = true
	_cars.clear()
	_clock = 0.0
	_green_at = -1.0
	_turn = 0
	var plan := tm.plan
	var cp := WorldState.to_world(cam.global_position)
	var road := _find_road(tm, Vector2(cp.x, cp.z))
	if road.is_empty():
		print("TMOTION: no street")
		return ""
	var axis: int = road[0]
	var index: int = road[1]
	var dir: int = road[2]
	var lo: float = road[3]
	var hi: float = road[4]
	_axis = axis
	var cross := CityPlan.AXIS_Z if axis == CityPlan.AXIS_X else CityPlan.AXIS_X
	var k := plan._index_at(cross, hi)
	for kk in [k - 1, k, k + 1, k + 2]:
		if absf(plan.road_pos(cross, kk) - plan.road_width(cross, kk) * 0.5 - hi) < 0.5:
			k = kk
	_node = Vector2i(index, k) if axis == CityPlan.AXIS_X else Vector2i(k, index)
	var road_x := plan.road_pos(axis, index)
	var half_w := plan.road_width(axis, index) * 0.5
	# The kerb on the cars' own side (right-hand traffic).
	var kerb := float(-dir if axis == CityPlan.AXIS_X else dir)
	match kind:
		"brake":
			var stop_at := lo + 62.0
			_add(tm.place_car(axis, index, dir, 0, stop_at, 0.0, false, Vehicle.BodyType.CROSSOVER))
			_car = tm.place_car(axis, index, dir, 0, lo + 8.0, 13.0, false, Vehicle.BodyType.SEDAN)
			_add(_car)
			# Low on the kerb a few metres short of the standing car, looking back up the lane at
			# the one coming in: it stops about five metres away, three-quarter front on.
			# Low in the empty oncoming lane a little short of the standing car, looking back up the
			# lane at the one coming in: it stops a few metres away, three-quarter front on.
			var at := stop_at - float(dir) * 4.0
			return _eye(plan, _xz(axis, road_x - kerb * 1.6, at), 1.0, _xz(axis, road_x + kerb * 1.6, stop_at - float(dir) * 18.0), 0.55)
		"pull":
			var line := plan.road_pos(cross, k) - float(dir) * (plan.road_width(cross, k) * 0.5 + tm.stop_line_back)
			if TrafficSignals.is_signal(plan, _node.x, _node.y):
				TrafficSignals.force(plan, _node.x, _node.y, axis, TrafficSignals.Light.RED, 6.0)
			var kinds := [Vehicle.BodyType.SEDAN, Vehicle.BodyType.CROSSOVER, Vehicle.BodyType.PICKUP]
			for n in 3:
				var c := tm.place_car(axis, index, dir, 0, line - float(dir) * (2.6 + 6.6 * float(n)), 10.0, false, kinds[n])
				c.traffic.v = 0.0
				c.traffic_speed = 0.0
				_add(c)
			_car = _cars[0]
			_green_at = 0.05
			# Behind the queue in the oncoming lane, a chase camera's height, looking up it.
			var at2 := line - float(dir) * 26.0
			return _eye(plan, _xz(axis, road_x - kerb * 1.4, at2), 1.6, _xz(axis, road_x + kerb * 1.6, line - float(dir) * 8.0), 0.6)
		"turn":
			var past := half_w + 3.0
			for d: int in [1, -1]:
				if plan.road_open(cross, k, road_x + float(d) * past):
					_turn = d
					break
			if _turn == 0:
				return ""
			_green_at = 0.0
			_car = tm.place_car(axis, index, dir, 0, hi - 34.0, 8.0, true, Vehicle.BodyType.SEDAN)
			_add(_car)
			# The far corner of the junction the car turns toward, looking back at the turn.
			var cpos := plan.road_pos(cross, k)
			var cw := plan.road_width(cross, k) * 0.5
			# Past the junction in the oncoming lane, facing back: the car comes on and turns off.
			var eye := _xz(axis, road_x - kerb * 1.5, cpos + float(dir) * (cw + 9.0))
			var centre := _xz(axis, road_x + kerb * 1.0, cpos - float(dir) * 3.0)
			return _eye(plan, eye, 1.3, centre, 0.6)
	return ""


static func _add(c: Vehicle) -> void:
	if c != null:
		_cars.append(c)


## (across, along) on a road of `axis` as world XZ.
static func _xz(axis: int, across: float, along: float) -> Vector2:
	return Vector2(across, along) if axis == CityPlan.AXIS_X else Vector2(along, across)


static func _eye(plan: CityPlan, e: Vector2, height: float, target: Vector2, target_y: float) -> String:
	var y := plan.height_at(e) + height
	var ty := plan.height_at(target) + target_y
	var d := Vector3(target.x - e.x, ty - y, target.y - e.y)
	return "%.2f,%.2f,%.2f,%.2f,%.2f" % [e.x, y, e.y, rad_to_deg(atan2(-d.x, -d.z)), rad_to_deg(atan2(d.y, Vector2(d.x, d.z).length()))]


## Drives the staged traffic `seconds` at 60 Hz, as its own tick would, plus the wheels and bodies.
static func advance(tm: TrafficManager, seconds: float) -> void:
	var dt := 1.0 / 60.0
	for i in int(round(seconds / dt)):
		_clock += dt
		TrafficSignals.advance(dt)
		TrafficAI.clock += dt
		if _green_at >= 0.0 and _clock >= _green_at and TrafficSignals.is_signal(tm.plan, _node.x, _node.y):
			TrafficSignals.force(tm.plan, _node.x, _node.y, _axis, TrafficSignals.Light.GREEN, 0.05)
		if _turn != 0 and is_instance_valid(_car) and int(_car.traffic.axis) == _axis and _car.traffic.get("node", Vector2i.ZERO) == _node:
			_car.traffic.turn = _turn
		tm._drive_streets(dt)
		for c in tm.cars:
			if is_instance_valid(c):
				c._update_wheels(dt)
	if is_instance_valid(_car):
		var st: TrafficMotion = _car.motion
		print("TMOTION t=%.2f v=%.2f pitch=%.2f roll=%.2f steer=%.1f deg" % [_clock, float(_car.traffic.get("v", 0.0)),
				rad_to_deg(st.pitch) if st else 0.0, rad_to_deg(st.roll) if st else 0.0, rad_to_deg(st.steer) if st else 0.0])


static func _find_road(tm: TrafficManager, near: Vector2) -> Array:
	var plan := tm.plan
	var best := []
	var bd := INF
	var c0 := plan.block_index_at(near)
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
				if hi - lo < 120.0:
					continue
				var q := _xz(axis, plan.road_pos(axis, index), (lo + hi) * 0.5)
				if plan.zone_at(q) != MacroMap.Zone.CITY or tm._replica_blocks(q, 6.0):
					continue
				if not (plan.road_open(axis, index, lo + 2.0) and plan.road_open(axis, index, hi - 2.0)):
					continue
				var d := q.distance_to(near)
				if d < bd:
					bd = d
					best = [axis, index, 1, lo, hi]
	return best
