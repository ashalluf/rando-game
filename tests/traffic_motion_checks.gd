extends RefCounted
## Traffic motion checks for tests/smoke_test.gd (traffic-motion, wave 3): the pure rules of
## TrafficMotion (nose down braking, a weaker squat, the lean out of a turn, the steering angle
## from the path and held at a stop, the spring that rocks back once, the queue beat), then a
## placed street car braking to a stop behind a standing one near the player: its BODY pitches
## nose down while the car itself stays level, its wheels stop turning when it stops, the body
## comes back to rest, a car out of traffic is put back at rest, the switch off leaves the old
## glide; and the cost per car. Loaded at run time, so it compiles after the autoloads.

var _t: Node
var _tree: SceneTree
var _city: Node3D
var _plan: CityPlan
var _traffic: TrafficManager
var _ws: Node
var _player: Player


func run(t: Node, city: Node3D) -> void:
	_t = t
	_tree = t.get_tree()
	_city = city
	_plan = city.plan
	_traffic = city.get_node("Traffic") as TrafficManager
	_ws = _tree.root.get_node("/root/WorldState")
	_player = _tree.get_first_node_in_group("player") as Player
	var started_ms := Time.get_ticks_msec()
	_pure()
	if _player.is_driving():
		_player.exit_vehicle()
	var home: Vector3 = _ws.to_world(_player.global_position)
	var police: Node = city.get_node_or_null("Police")
	var police_was: Variant = police.get("enabled") if police else null
	if police:
		police.set("enabled", false)
	_traffic.staged = true
	_clear()
	var road := _find_road(Vector2(home.x, home.z))
	if road.is_empty():
		_check(false, "an open one-lane city street near the spawn for the traffic motion checks")
	else:
		await _live(road)
	_clear()
	TrafficMotion.enabled = OS.get_environment("TRAFFIC_MOTION") != "0"
	_traffic.staged = false
	_player.global_position = _ws.to_local(home)
	_player.velocity = Vector3.ZERO
	_city.update_streaming(true)
	if police:
		police.set("enabled", police_was)
	await _ticks(3)
	print("traffic motion checks took %.1f s" % ((Time.get_ticks_msec() - started_ms) / 1000.0))


func _check(ok: bool, label: String) -> void:
	_t._check(ok, label)


func _ticks(n: int) -> void:
	for i in n:
		await _tree.physics_frame


func _clear() -> void:
	for c in _traffic.cars.duplicate():
		if is_instance_valid(c):
			_traffic._retire(c)
	_traffic.cars.clear()


func _pure() -> void:
	var brake := TrafficMotion.pitch_for(-6.0)
	var pull := TrafficMotion.pitch_for(2.5)
	_check(brake < -0.02 and brake > -TrafficMotion.PITCH_MAX - 0.0001,
			"braking at 6 m/s^2 puts the nose down 1-2.4 degrees (%.2f deg)" % rad_to_deg(brake))
	_check(pull > 0.0 and pull < absf(TrafficMotion.pitch_for(-2.5)),
			"pulling away squats the tail, less than the same braking dives (%.2f deg)" % rad_to_deg(pull))
	_check(TrafficMotion.pitch_for(-40.0) == -TrafficMotion.PITCH_MAX, "the dive is capped")
	var left := TrafficMotion.roll_for(3.0)
	_check(left < -0.01 and left > -TrafficMotion.ROLL_MAX, "turning left the body leans out to the right (%.2f deg)" % rad_to_deg(left))
	_check(absf(TrafficMotion.roll_for(3.0, true)) > absf(left), "a bus or a truck leans further than a car")
	var st := TrafficMotion.steer_for(0.5, 6.0, 2.7)
	_check(st > 0.15 and st < TrafficMotion.STEER_MAX, "a left turn of 0.5 rad/s at 6 m/s steers the front wheels left ~12 degrees (%.1f deg)" % rad_to_deg(st))
	_check(TrafficMotion.steer_for(-0.5, 6.0, 2.7) < 0.0, "a right turn steers right")
	_check(TrafficMotion.steer_for(0.5, -3.0, 2.7) < 0.0, "backing round to the left the front wheels point right")
	# The spring: from 0 toward 1, it passes the target once and settles (damping under 1).
	var x := Vector2.ZERO
	var peak := 0.0
	for i in 240:
		x = TrafficMotion.spring(x.x, x.y, 1.0, TrafficMotion.PITCH_HZ, TrafficMotion.PITCH_ZETA, 1.0 / 60.0)
		peak = maxf(peak, x.x)
	_check(peak > 1.05 and peak < 1.6 and absf(x.x - 1.0) < 0.02,
			"the body's spring rocks past its target once and settles (peak %.2f, end %.3f)" % [peak, x.x])
	var d0 := TrafficMotion.queue_delay(11, 3, 0.65)
	var lo := INF
	var hi := -INF
	for s in 200:
		var d := TrafficMotion.queue_delay(s, 7, 0.65)
		lo = minf(lo, d)
		hi = maxf(hi, d)
	_check(d0 == TrafficMotion.queue_delay(11, 3, 0.65) and lo >= TrafficMotion.QUEUE_REACT_RANGE.x and hi <= TrafficMotion.QUEUE_REACT_RANGE.y and hi - lo > 0.1,
			"the queue beat is a hash, between %.2f and %.2f s, and varies (%.2f..%.2f)" % [TrafficMotion.QUEUE_REACT_RANGE.x, TrafficMotion.QUEUE_REACT_RANGE.y, lo, hi])
	_check(TrafficMotion.queue_delay(1, 1, 4.6) <= TrafficMotion.QUEUE_REACT_RANGE.y, "a dozy driver's beat is capped")


## An open city street near `near` with one lane each way and a block at least 140 m long:
## [axis, index, dir, block start along, block end along] or [].
func _find_road(near: Vector2) -> Array:
	var best := []
	var bd := INF
	var c0 := _plan.block_index_at(near)
	for axis: int in [CityPlan.AXIS_X, CityPlan.AXIS_Z]:
		var cross := CityPlan.AXIS_Z if axis == CityPlan.AXIS_X else CityPlan.AXIS_X
		var i0 := c0.x if axis == CityPlan.AXIS_X else c0.y
		var k0 := c0.y if axis == CityPlan.AXIS_X else c0.x
		for index in range(i0 - 8, i0 + 9):
			if TrafficAI.lanes_of(_plan, axis, index) >= 2 or _traffic._rail_street(axis, index):
				continue
			for k in range(k0 - 8, k0 + 9):
				var lo := _plan.road_pos(cross, k) + _plan.road_width(cross, k) * 0.5
				var hi := _plan.road_pos(cross, k + 1) - _plan.road_width(cross, k + 1) * 0.5
				if hi - lo < 140.0:
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


func _body_pitch(car: Vehicle) -> float:
	var b := car.get_node_or_null("BodyModel") as Node3D
	return b.transform.basis.get_euler().x if b else 0.0


func _live(road: Array) -> void:
	var axis: int = road[0]
	var index: int = road[1]
	var dir: int = road[2]
	var lo: float = road[3]
	var start := lo + 12.0
	var stop_at := start + 46.0
	# Stand the player on the pavement beside where the car will stop, so the camera is near.
	var off := _plan.road_width(axis, index) * 0.5 + 3.0
	var mid := (start + stop_at) * 0.5
	var p := Vector2(_plan.road_pos(axis, index) + off, mid) if axis == CityPlan.AXIS_X else Vector2(mid, _plan.road_pos(axis, index) + off)
	_player.global_position = _ws.to_local(Vector3(p.x, _plan.height_at(p) + 1.2, p.y))
	_player.velocity = Vector3.ZERO
	_city.update_streaming(true)
	await _ticks(4)
	var ahead := _traffic.place_car(axis, index, dir, 0, stop_at, 0.0, false, Vehicle.BodyType.SEDAN)
	var car := _traffic.place_car(axis, index, dir, 0, start, 11.0, false, Vehicle.BodyType.SEDAN)
	if car == null or ahead == null:
		_check(false, "two traffic cars placed for the traffic motion checks")
		return
	var min_pitch := 0.0
	var max_after := -1.0
	var stopped_at := -1
	var spin_stopped := 0.0
	var spin_was := car._wheel_spin
	var level := true
	var made := false
	var usec_seen := 0.0
	for i in 420:
		await _tree.physics_frame
		if not is_instance_valid(car) or not car.is_traffic():
			break
		if car.motion != null:
			made = true
		min_pitch = minf(min_pitch, _body_pitch(car))
		if absf(car.global_basis.get_euler().x) > 0.06:
			level = false
		usec_seen = maxf(usec_seen, TrafficMotion.usec)
		var v := float(car.traffic.get("v", 0.0))
		if stopped_at < 0 and v < 0.05 and i > 30:
			stopped_at = i
			spin_was = car._wheel_spin
		if stopped_at >= 0 and i > stopped_at + 20:
			max_after = maxf(max_after, _body_pitch(car))
			spin_stopped = maxf(spin_stopped, absf(wrapf(car._wheel_spin - spin_was, -PI, PI)))
		if stopped_at >= 0 and i > stopped_at + 200:
			break
	_check(made, "a traffic car near the camera gets its body motion (TrafficMotion)")
	_check(stopped_at > 0, "the placed car braked to a stop behind the standing one")
	_check(min_pitch < -0.006, "braking to a stop the body dives nose down (%.2f deg)" % rad_to_deg(min_pitch))
	_check(level, "the car itself stays level on the street (only the body model moves)")
	_check(spin_stopped < 0.02, "standing, its wheels stop turning (%.3f rad)" % spin_stopped)
	var rest_pitch := _body_pitch(car) if is_instance_valid(car) else 0.0
	_check(absf(rest_pitch) < 0.004, "standing, the body settles back to rest (%.2f deg)" % rad_to_deg(rest_pitch))
	print("traffic motion: dive %.2f deg, cost %.1f us a frame (%d cars), traffic tick %.0f us" % [rad_to_deg(min_pitch), usec_seen, TrafficMotion.moving, _traffic.drive_usec])
	_check(usec_seen < 400.0, "the body motion costs little (%.1f us a physics frame)" % usec_seen)
	# Steering held at a stop: a stopped car keeps the angle it had.
	if is_instance_valid(car) and car.motion != null:
		car.motion.steer = 0.3
		var s := TrafficMotion.tick(car, 0.0, 0.0, 5.0, 1.0 / 60.0)
		_check(absf(s - 0.3) < 0.0001, "a car standing mid-turn keeps its front wheels turned")
		# The switch off: the old glide, the body back at rest.
		car.motion.pitch = -0.03
		car.motion._write()
		TrafficMotion.enabled = false
		var off_s := TrafficMotion.tick(car, 0.0, 0.0, 5.0, 1.0 / 60.0)
		_check(is_nan(off_s) and car.motion == null and absf(_body_pitch(car)) < 0.0001,
				"TRAFFIC_MOTION off puts the body back at rest and hands the steering back")
		TrafficMotion.enabled = true
		# Out of traffic (hit, driven): put back at rest.
		TrafficMotion.tick(car, 0.0, 6.0, 5.0, 1.0 / 60.0)
		if car.motion != null:
			car.motion.pitch = -0.03
			car.motion._write()
			var saved: Dictionary = car.traffic
			car.traffic = {}
			TrafficMotion.tick(car, 0.0, 0.0, 5.0, 1.0 / 60.0)
			_check(car.motion == null and absf(_body_pitch(car)) < 0.0001, "a car leaving traffic has its body put back at rest")
			car.traffic = saved
	_clear()
	await _turn(road)
	# The queue beat (pure dictionaries, not placed).
	var t := {"m_react": 0.65}
	var lead := Vehicle.new()
	lead.traffic = {"v": 0.0}
	TrafficMotion.queue_react(car, t, lead, 0.0)
	var waited: bool = t.get("qs", false)
	lead.traffic.v = 2.0
	TrafficMotion.queue_react(car, t, lead, 0.0)
	_check(waited and float(t.get("react", 0.0)) >= TrafficMotion.QUEUE_REACT_RANGE.x,
			"a car standing behind a standing car waits a beat when it moves off (%.2f s)" % float(t.get("react", 0.0)))
	var tp := {"m_react": 0.65, "placed": true}
	lead.traffic.v = 0.0
	TrafficMotion.queue_react(car, tp, lead, 0.0)
	lead.traffic.v = 2.0
	TrafficMotion.queue_react(car, tp, lead, 0.0)
	_check(not tp.has("react"), "a car placed by hand (checks, stills) gets no beat unless asked")
	lead.free()


## A placed car turning at the junction past the block: the logic snaps it onto the cross street
## at the junction's centre; drawn, it turns round the fillet - no tick turns it by more than a
## smooth turn would, its front wheels steer into the turn, the body leans out.
func _turn(road: Array) -> void:
	var axis: int = road[0]
	var index: int = road[1]
	var dir: int = road[2]
	var hi: float = road[4]
	var cross := CityPlan.AXIS_Z if axis == CityPlan.AXIS_X else CityPlan.AXIS_X
	var k := _plan._index_at(cross, hi)
	for kk in [k - 1, k, k + 1, k + 2]:
		if absf(_plan.road_pos(cross, kk) - _plan.road_width(cross, kk) * 0.5 - hi) < 0.5:
			k = kk
	var node := Vector2i(index, k) if axis == CityPlan.AXIS_X else Vector2i(k, index)
	var past := _plan.road_width(axis, index) * 0.5 + 3.0
	var nd := 0
	for d: int in [1, -1]:
		if _plan.road_open(cross, k, _plan.road_pos(axis, index) + float(d) * past):
			nd = d
			break
	if nd == 0 or not _plan.road_open(axis, index, hi - 40.0):
		_check(false, "an open turn at the end of the traffic motion checks' street")
		return
	var start := hi - 40.0
	var off := _plan.road_width(axis, index) * 0.5 + 4.0
	var p := Vector2(_plan.road_pos(axis, index) + off, hi) if axis == CityPlan.AXIS_X else Vector2(hi, _plan.road_pos(axis, index) + off)
	_player.global_position = _ws.to_local(Vector3(p.x, _plan.height_at(p) + 1.2, p.y))
	_player.velocity = Vector3.ZERO
	_city.update_streaming(true)
	await _ticks(3)
	if TrafficSignals.is_signal(_plan, node.x, node.y):
		TrafficSignals.force(_plan, node.x, node.y, axis, TrafficSignals.Light.GREEN, 0.05)
	var car := _traffic.place_car(axis, index, dir, 0, start, 7.0, true, Vehicle.BodyType.SEDAN)
	if car == null:
		_check(false, "a car placed for the turn")
		return
	var last_yaw := car.global_rotation.y
	var worst := 0.0
	var turned := false
	var steer_max := 0.0
	var roll_max := 0.0
	var arc_seen := false
	for i in 600:
		await _tree.physics_frame
		if not is_instance_valid(car) or not car.is_traffic():
			break
		var t: Dictionary = car.traffic
		if int(t.axis) == axis and int(t.get("turn", 0)) != nd and t.get("node", Vector2i.ZERO) == node:
			t.turn = nd
		if TrafficSignals.is_signal(_plan, node.x, node.y) and i % 30 == 0:
			TrafficSignals.force(_plan, node.x, node.y, axis, TrafficSignals.Light.GREEN, 0.05)
		if t.has("tm_arc"):
			arc_seen = true
		var y := car.global_rotation.y
		worst = maxf(worst, absf(wrapf(y - last_yaw, -PI, PI)))
		last_yaw = y
		for rig: Array in car._wheel_rigs:
			if rig[4]:
				steer_max = maxf(steer_max, absf((rig[0] as Node3D).rotation.y))
		var b := car.get_node_or_null("BodyModel") as Node3D
		if b:
			roll_max = maxf(roll_max, absf(b.transform.basis.get_euler().z))
		if int(t.axis) == cross:
			turned = true
			if not t.has("tm_arc"):
				break
	_check(turned and arc_seen, "the placed car turned onto the cross street round a fillet")
	_check(worst < 0.12, "no tick turns the car by more than a smooth turn would (worst %.1f deg; the snap was 90)" % rad_to_deg(worst))
	_check(steer_max > 0.12, "its front wheels steer into the turn (%.1f deg)" % rad_to_deg(steer_max))
	_check(roll_max > 0.002, "the body leans out of the turn (%.2f deg)" % rad_to_deg(roll_max))
	print("traffic motion turn: worst %.1f deg a tick, steer %.1f deg, roll %.2f deg" % [rad_to_deg(worst), rad_to_deg(steer_max), rad_to_deg(roll_max)])
