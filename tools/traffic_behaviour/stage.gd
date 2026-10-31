extends RefCounted
## Stills for TrafficBehaviour (traffic-behaviour-2), called by tools/glshot/still_shot.gd for
## TB2=wreck|left|heads|bus: stages street traffic near the camera and returns the free camera's
## EYE string. The traffic then moves only by TRAFFIC_STEPS (TrafficAI.advance_shot), saved as
## OUT with _t1, _t2, ... Run TRAFFIC_BEHAVIOUR=0 for the before.
##   wreck  a car standing across the kerb lane of a one-lane street, a car edging round it, more
##          coming (camera on the pavement past it, looking back)
##   left   a car waiting in the box to turn left while the oncoming cars come through
##   heads  a car at a red with the camera at its windscreen: its driver looks at the camera
##   bus    a bus done at its stop, its left indicator on, pulling out


static func stage(tm: TrafficManager, kind: String, cam: Camera3D) -> String:
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
		"wreck":
			var r := _road(tm, here, 1, 140.0, false)
			if r.is_empty():
				return ""
			var axis: int = r[0]
			var index: int = r[1]
			var lo: float = r[3]
			var hi: float = r[4]
			var mid := (lo + hi) * 0.5 + 10.0
			_greens(tm, axis, index, int(r[2]))
			var wreck := tm.place_car(axis, index, 1, 0, mid, 0.0, false)
			wreck.traffic = {}
			tm.cars.erase(wreck)
			wreck.rotate_y(0.42)
			wreck.alarm_left = 600.0
			# Crashed: dents, crazed glass, smoke from the bay (CarDamage's own staging).
			if wreck.has_method("damage_state"):
				wreck.damage_state().stage("dents,glass,smoke")
			TrafficBehaviour.survey(tm)
			TrafficBehaviour.register(plan, wreck, WorldState.to_world(wreck.global_position))
			var car := tm.place_car(axis, index, 1, 0, mid - 34.0, 7.0, false)
			tm.place_car(axis, index, 1, 0, mid - 52.0, 7.0, false)
			tm.place_car(axis, index, 1, 0, mid - 68.0, 7.0, false)
			tm.set_meta("shot_car", car)
			var road := plan.road_pos(axis, index)
			var side := float(-1 if axis == CityPlan.AXIS_X else 1)
			var lat := road + side * (plan.road_width(axis, index) * 0.5 + 1.2)
			var e := _xz(axis, lat, mid + 14.0)
			return TrafficAI._eye_string(plan, e, 1.7, _xz(axis, road, mid - 20.0), 0.9)
		"left":
			var r := _road(tm, here, 1, 80.0, true)
			if r.is_empty():
				r = _road(tm, here, 2, 80.0, true)
			if r.is_empty():
				return ""
			var axis: int = r[0]
			var index: int = r[1]
			var k: int = int(r[2]) + 1
			var cross := _cross(axis)
			var cross_pos := plan.road_pos(cross, k)
			var cw := plan.road_width(cross, k)
			var node := _node(axis, index, k)
			TrafficSignals.force(plan, node.x, node.y, axis, TrafficSignals.Light.GREEN, 0.3)
			var left := 1 if TrafficAI.turn_side(axis, 1, 1) < 0 else -1
			var car := tm.place_car(axis, index, 1, 0, cross_pos - TrafficBehaviour.LEFT_WAIT_AT - 1.0, 1.0, true)
			var t: Dictionary = car.traffic
			t.node = node
			t.turn = left
			t.forced = false
			t.amber_go = false
			t.sign_ok = false
			t.sign_t = 0.0
			tm.set_meta("shot_car", car)
			for d: float in [14.0, 34.0, 56.0]:
				tm.place_car(axis, index, -1, 0, cross_pos + cw * 0.5 + d, 8.5, false)
			tm.place_car(axis, index, 1, 0, cross_pos - cw * 0.5 - 14.0, 0.0, false)
			# On the far corner, looking back at the turner and the oncoming lane.
			var road := plan.road_pos(axis, index)
			var side := float(-1 if axis == CityPlan.AXIS_X else 1)
			var e := _xz(axis, road - side * (plan.road_width(axis, index) * 0.5 + 2.0), cross_pos + cw * 0.5 + 3.0)
			return TrafficAI._eye_string(plan, e, 2.2, _xz(axis, road, cross_pos - 6.0), 0.8)
		"heads":
			var r := _road(tm, here, 1, 80.0, true)
			if r.is_empty():
				r = _road(tm, here, 2, 80.0, true)
			if r.is_empty():
				return ""
			var axis: int = r[0]
			var index: int = r[1]
			var k: int = int(r[2]) + 1
			var cross := _cross(axis)
			var cross_pos := plan.road_pos(cross, k)
			var cw := plan.road_width(cross, k)
			var node := _node(axis, index, k)
			TrafficSignals.force(plan, node.x, node.y, axis, TrafficSignals.Light.RED, 0.3)
			var line := cross_pos - cw * 0.5 - tm.stop_line_back
			var car := tm.place_car(axis, index, 1, 0, line - 2.6, 0.0, false)
			tm.place_car(axis, index, 1, 0, line - 10.0, 0.0, false)
			tm.set_meta("shot_car", car)
			# Beside the driver's window (the car's left), a little ahead, at eye height.
			var wp := WorldState.to_world(car.global_position)
			var fwd := -car.global_basis.z
			var right := car.global_basis.x
			var eye := wp + fwd * 1.2 - right * 2.7
			TrafficBehaviour.look_override = Vector3(eye.x, wp.y + 1.2, eye.z)
			var target := wp - fwd * 0.2 - right * 0.4
			return TrafficAI._eye_string(plan, Vector2(eye.x, eye.z), 1.35, Vector2(target.x, target.z), 1.05)
		"bus":
			var best := []
			var bd := INF
			var center := plan.block_index_at(here)
			for axis: int in [CityPlan.AXIS_X, CityPlan.AXIS_Z]:
				var c0 := center.x if axis == CityPlan.AXIS_X else center.y
				for index in range(c0 - 6, c0 + 7):
					if BigVehicles.route_of(plan, axis, index) == 0 or tm._rail_street(axis, index):
						continue
					var cross := _cross(axis)
					var k0 := plan._index_at(cross, here.y if axis == CityPlan.AXIS_X else here.x)
					for k in range(k0 - 4, k0 + 5):
						var stop := BigVehicles.block_stop(plan, axis, index, k, 1)
						if is_nan(stop) or not plan.road_open(axis, index, stop - 60.0) or not plan.road_open(axis, index, stop + 40.0):
							continue
						var q := _xz(axis, plan.road_pos(axis, index), stop)
						if plan.zone_at(q) != MacroMap.Zone.CITY:
							continue
						var d := q.distance_to(here)
						if d < bd:
							bd = d
							best = [axis, index, k, stop]
			if best.is_empty():
				return ""
			var axis: int = best[0]
			var index: int = best[1]
			var stop: float = best[3]
			_greens(tm, axis, index, int(best[2]))
			var lanes := TrafficAI.lanes_of(plan, axis, index)
			var bus := tm.place_car(axis, index, 1, lanes - 1, stop - 6.0, 2.0, false, BigVehicles.BUS)
			bus.traffic.dwell_need = 1.5
			tm.set_meta("shot_car", bus)
			# Behind the bus over the road's centre line, looking along its left side.
			var road := plan.road_pos(axis, index)
			var e := _xz(axis, road, stop - 26.0)
			var side := float(-1 if axis == CityPlan.AXIS_X else 1)
			return TrafficAI._eye_string(plan, e, 2.6, _xz(axis, road + side * 2.0, stop + 4.0), 1.6)
	return ""


static func _cross(axis: int) -> int:
	return CityPlan.AXIS_Z if axis == CityPlan.AXIS_X else CityPlan.AXIS_X


static func _node(axis: int, index: int, k: int) -> Vector2i:
	return Vector2i(index, k) if axis == CityPlan.AXIS_X else Vector2i(k, index)


static func _xz(axis: int, lat: float, along: float) -> Vector2:
	return Vector2(lat, along) if axis == CityPlan.AXIS_X else Vector2(along, lat)


static func _greens(tm: TrafficManager, axis: int, index: int, k: int) -> void:
	for kk in range(k - 1, k + 3):
		var nd := _node(axis, index, kk)
		if TrafficSignals.is_signal(tm.plan, nd.x, nd.y):
			TrafficSignals.force(tm.plan, nd.x, nd.y, axis, TrafficSignals.Light.GREEN, 0.2)


## The road near `here` with `lanes` lanes, a block of `need` m from crossing k to k+1 open and in
## the city, a signalled k+1 if asked: [axis, index, k, block start, block end] or [].
static func _road(tm: TrafficManager, here: Vector2, lanes: int, need: float, signal_end: bool) -> Array:
	var plan := tm.plan
	var hb := plan.block_index_at(here)
	for r in 16:
		for axis: int in [CityPlan.AXIS_X, CityPlan.AXIS_Z]:
			for di: int in [r, -r]:
				var index := (hb.x if axis == CityPlan.AXIS_X else hb.y) + di
				if TrafficAI.lanes_of(plan, axis, index) != lanes or tm._rail_street(axis, index) or BigVehicles.route_of(plan, axis, index) != 0:
					continue
				var cross := _cross(axis)
				var k0 := hb.y if axis == CityPlan.AXIS_X else hb.x
				for k in range(k0 - 2, k0 + 3):
					var lo := plan.road_pos(cross, k) + plan.road_width(cross, k) * 0.5
					var hi := plan.road_pos(cross, k + 1) - plan.road_width(cross, k + 1) * 0.5
					if hi - lo < need:
						continue
					var nd := _node(axis, index, k + 1)
					if signal_end and not TrafficSignals.is_signal(plan, nd.x, nd.y):
						continue
					var ok := true
					for f in 7:
						var a := lerpf(lo - 5.0, hi + 30.0, float(f) / 6.0)
						var q := _xz(axis, plan.road_pos(axis, index), a)
						if not plan.road_open(axis, index, a) or plan.zone_at(q) != MacroMap.Zone.CITY:
							ok = false
							break
					if ok:
						return [axis, index, k, lo, hi]
	return []
