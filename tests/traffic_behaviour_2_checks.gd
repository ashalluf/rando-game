extends RefCounted
## Traffic behaviour checks for tests/smoke_test.gd (fleet wave 4, traffic-behaviour-2,
## TrafficBehaviour): a driver who stops short at a red and creeps up to the line (never past it),
## the car behind inching up after it and a foot easing off the brake (the lamps go off while the
## car stands), a bus pulling out of its stop on its left indicator, a left-turner waiting in the
## box until the oncoming car has gone by, a car waiting back from a crosswalk somebody is on, a
## wreck changed round on a two-lane road and edged round on a one-lane one (slowly, and clear of
## it), heads turned toward what the driver looks at, and the A/B costs nothing.
## Loaded at run time, so it compiles after the autoloads and can name TrafficBehaviour freely.

var _t: Node
var _tree: SceneTree
var _city: Node3D
var _plan: CityPlan
var _traffic: TrafficManager
var _ws: Node
var _player: Player
var _home: Vector3


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
	_home = _ws.to_world(_player.global_position)
	var started_ms := Time.get_ticks_msec()
	var was := TrafficBehaviour.enabled
	TrafficBehaviour.enabled = true
	var police: Node = city.get_node_or_null("Police")
	var police_was: Variant = police.get("enabled") if police else null
	if police:
		police.set("enabled", false)
	_traffic.staged = true
	_clear_traffic()
	await _creep_inch_foot()
	_clear_traffic()
	await _bus_pull_out()
	_clear_traffic()
	await _left_turn_gap()
	_clear_traffic()
	await _polite_crosswalk()
	_clear_traffic()
	await _wreck_two_lane()
	_clear_traffic()
	await _wreck_one_lane()
	_clear_traffic()
	_heads()
	_placed_untouched()
	_traffic.staged = false
	TrafficBehaviour.enabled = was
	if police:
		police.set("enabled", police_was)
	_player.global_position = _ws.to_local(_home)
	_player.velocity = Vector3.ZERO
	await _ticks(3)
	print("traffic behaviour checks took %.1f s" % ((Time.get_ticks_msec() - started_ms) / 1000.0))


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
	for c in _traffic.freeway_cars.duplicate():
		if is_instance_valid(c):
			_traffic._retire(c)
	_traffic.freeway_cars.clear()
	TrafficBehaviour._obst.clear()
	TrafficBehaviour._obst_road.clear()


func _cross(axis: int) -> int:
	return CityPlan.AXIS_Z if axis == CityPlan.AXIS_X else CityPlan.AXIS_X


func _node(axis: int, index: int, k: int) -> Vector2i:
	return Vector2i(index, k) if axis == CityPlan.AXIS_X else Vector2i(k, index)


## The player on foot `off` metres to the side of road (axis, index)'s centre line at `along`.
func _stand(axis: int, index: int, along: float, off: float) -> void:
	if _player.is_driving():
		_player.exit_vehicle()
	var road := _plan.road_pos(axis, index) + off
	var p := Vector2(road, along) if axis == CityPlan.AXIS_X else Vector2(along, road)
	_player.global_position = _ws.to_local(Vector3(p.x, _plan.height_at(p) + 1.0, p.y))
	_player.velocity = Vector3.ZERO


## A city road near the spawn with `lanes` lanes each way, a block of at least `need` metres from
## crossing k to k+1 open all along, and a signalled junction at k+1 (or any junction when
## `signal_end` is false): [axis, index, k] or [].
func _find_road(lanes: int, need: float, signal_end: bool) -> Array:
	var hb: Vector2i = _plan.block_index_at(Vector2(_home.x, _home.z))
	for r in 24:
		for axis: int in [CityPlan.AXIS_X, CityPlan.AXIS_Z]:
			for di: int in [r, -r]:
				var index := (hb.x if axis == CityPlan.AXIS_X else hb.y) + di
				if TrafficAI.lanes_of(_plan, axis, index) != lanes or _traffic._rail_street(axis, index):
					continue
				if BigVehicles.route_of(_plan, axis, index) != 0:
					continue
				var cross := _cross(axis)
				var k0 := hb.y if axis == CityPlan.AXIS_X else hb.x
				for k in range(k0 - 2, k0 + 3):
					var lo := _plan.road_pos(cross, k) + _plan.road_width(cross, k) * 0.5
					var hi := _plan.road_pos(cross, k + 1) - _plan.road_width(cross, k + 1) * 0.5
					if hi - lo < need:
						continue
					var node := _node(axis, index, k + 1)
					if signal_end and not TrafficSignals.is_signal(_plan, node.x, node.y):
						continue
					var ok := true
					for f in 9:
						var a := lerpf(lo - 5.0, hi + 40.0, float(f) / 8.0)
						var q := Vector2(_plan.road_pos(axis, index), a) if axis == CityPlan.AXIS_X else Vector2(a, _plan.road_pos(axis, index))
						if not _plan.road_open(axis, index, a) or _plan.zone_at(q) != MacroMap.Zone.CITY or _plan.river_block(_plan.block_index_at(q).x, _plan.block_index_at(q).y):
							ok = false
							break
					if ok:
						return [axis, index, k]
	return []


func _along(car: Vehicle, axis: int) -> float:
	var wp: Vector3 = _ws.to_world(car.global_position)
	return wp.z if axis == CityPlan.AXIS_X else wp.x


func _lateral(car: Vehicle, axis: int) -> float:
	var wp: Vector3 = _ws.to_world(car.global_position)
	return wp.x if axis == CityPlan.AXIS_X else wp.z


## How far car's nose is short of the stop line of crossing `k` (driving +along).
func _to_line(car: Vehicle, axis: int, k: int) -> float:
	var cross := _cross(axis)
	return _plan.road_pos(cross, k) - _along(car, axis) - _plan.road_width(cross, k) * 0.5 - _traffic.stop_line_back - float(car.traffic.get("half", 2.4))


## Creep, inch, foot: two cars at a red. The front one stops short and creeps to the line; the
## one behind inches up after it; the front driver's foot comes off the brake now and then.
func _creep_inch_foot() -> void:
	var road := _find_road(1, 90.0, true)
	if road.is_empty():
		road = _find_road(2, 90.0, true)
	if road.is_empty():
		_check(false, "a road with a signalled junction near the spawn, for the creep check")
		return
	var axis: int = road[0]
	var index: int = road[1]
	var k: int = road[2] + 1
	var node := _node(axis, index, k)
	var cross_pos := _plan.road_pos(_cross(axis), k)
	var cw := _plan.road_width(_cross(axis), k)
	_stand(axis, index, cross_pos - 35.0, _plan.road_width(axis, index) * 0.5 + 4.0)
	TrafficSignals.force(_plan, node.x, node.y, axis, TrafficSignals.Light.RED, 0.3)
	await _ticks(2)
	_clear_crosswalks(node)
	var front := _traffic.place_car(axis, index, 1, 0, cross_pos - cw * 0.5 - 30.0, 7.0, false)
	front.traffic.tb_r = [0.0, 0.5, 0.0, 0.0]
	front.traffic.tb = true
	var back := _traffic.place_car(axis, index, 1, 0, cross_pos - cw * 0.5 - 48.0, 7.0, false)
	back.traffic.tb_r = [0.9, 0.5, 0.1, 0.9]
	back.traffic.tb = true
	var c0 := TrafficBehaviour.counts.duplicate()
	var first_stop := INF
	var worst_line := INF
	var foot_dark := false
	var back_first := INF
	var back_last := INF
	var worst_gap := INF
	for i in 60 * 28:
		await _tree.physics_frame
		if foot_dark and not is_inf(back_first) and back_last - back_first > 0.4 and int(front.traffic.get("tb_creep", 0)) == 3:
			break
		# Held red for the whole check.
		if i % 30 == 0:
			TrafficSignals.force(_plan, node.x, node.y, axis, TrafficSignals.Light.RED, 0.3)
		if not front.is_traffic() or not back.is_traffic():
			break
		var fv := float(front.traffic.get("v", 1.0))
		var tl := _to_line(front, axis, k)
		worst_line = minf(worst_line, tl)
		if is_inf(first_stop) and fv < 0.02 and i > 30:
			first_stop = tl
		if fv < 0.02 and i > 60 and not front.light_brake:
			foot_dark = true
		var bv := float(back.traffic.get("v", 1.0))
		var ba := _along(back, axis)
		if bv < 0.02 and i > 60:
			if is_inf(back_first):
				back_first = ba
			back_last = ba
		var gap := _along(front, axis) - ba - float(front.traffic.get("rear", 2.4)) - float(back.traffic.get("half", 2.4))
		worst_gap = minf(worst_gap, gap)
	var final_line := _to_line(front, axis, k)
	_check(first_stop > 1.3 and first_stop < 4.5, "a creeping driver stops short of the line at a red (first stood %.2f m short)" % first_stop)
	_check(final_line > -0.05 and final_line < 0.9 and worst_line > -0.1, "then creeps up to it and never past it (ends %.2f m short, closest %.2f)" % [final_line, worst_line])
	_check(int(TrafficBehaviour.counts.get("creep", 0)) > int(c0.get("creep", 0)), "the creep is counted")
	_check(not is_inf(back_first) and back_last - back_first > 0.4, "the car behind inches up after it (%.2f m)" % (back_last - back_first if not is_inf(back_first) else -1.0))
	_check(worst_gap > 0.8, "and never closes on it (closest %.2f m)" % worst_gap)
	_check(foot_dark, "a foot off the brake: the brake lamps go dark a moment while the car stands")


func _clear_crosswalks(node: Vector2i) -> void:
	for p in _tree.get_nodes_in_group("pedestrian"):
		var w := p as Pedestrian
		if w and w._cross != Pedestrian.Cross.NONE and w._cross_key.x == node.x and w._cross_key.y == node.y:
			w.queue_free()
	for key: Vector4i in Pedestrian._crosswalks.keys():
		if key.x == node.x and key.y == node.y:
			Pedestrian._crosswalks.erase(key)


## A bus at its stop: doors, then the left indicator before it moves, still on as it pulls out,
## off once it is back in its lane.
func _bus_pull_out() -> void:
	var s := _find_stop()
	if s.is_empty():
		_check(false, "a bus stop near the spawn, for the pull-out check")
		return
	var axis: int = s[0]
	var index: int = s[1]
	var dir: int = s[3]
	var stop: float = s[4]
	var cross := _cross(axis)
	var k0 := _plan._index_at(cross, stop)
	for kk in range(k0 - 1, k0 + 3):
		var nd := _node(axis, index, kk)
		if TrafficSignals.is_signal(_plan, nd.x, nd.y):
			TrafficSignals.force(_plan, nd.x, nd.y, axis, TrafficSignals.Light.GREEN, 0.2)
	_stand(axis, index, stop, (_plan.road_width(axis, index) * 0.5 + 5.0) * float(-dir if axis == CityPlan.AXIS_X else dir))
	await _ticks(2)
	var lanes := TrafficAI.lanes_of(_plan, axis, index)
	var bus := _traffic.place_car(axis, index, dir, lanes - 1, stop - float(dir) * 12.0, 4.0, false, BigVehicles.BUS)
	bus.traffic.dwell_need = 2.5
	bus.traffic.tb = true
	var c0 := int(TrafficBehaviour.counts.get("bus_signal", 0))
	var signalled_still := false
	var lit := false
	var moved_signalling := false
	var off_after := false
	var hold := 0.0
	for i in 60 * 22:
		await _tree.physics_frame
		if not bus.is_traffic():
			break
		var t: Dictionary = bus.traffic
		var v := float(t.get("v", 0.0))
		var served := t.has("served")
		if served and v < 0.05 and int(t.get("sig", 0)) == -1:
			signalled_still = true
			hold += 1.0 / 60.0
			lit = lit or bus.light_signal == -1
		if served and v > 1.0 and int(t.get("sig", 0)) == -1:
			moved_signalling = true
		if moved_signalling and int(t.get("sig", 0)) == 0 and float(t.get("shift", 1.0)) < 0.15:
			off_after = true
			break
	_check(int(TrafficBehaviour.counts.get("bus_signal", 0)) > c0 and signalled_still and hold > 0.6, "a bus done at its stop signals left before it moves (%.1f s)" % hold)
	_check(lit, "and its indicator lamp shows it")
	_check(moved_signalling and off_after, "it pulls out still signalling and the indicator goes off back in its lane (moved %s, off %s)" % [moved_signalling, off_after])


## A two-lane road with a bus stop near the spawn: [axis, index, k, dir, stop] or [].
func _find_stop() -> Array:
	for r in 16:
		for axis: int in [CityPlan.AXIS_X, CityPlan.AXIS_Z]:
			for index: int in [r, -r]:
				if BigVehicles.route_of(_plan, axis, index) == 0 or _traffic._rail_street(axis, index):
					continue
				for k in range(-2, 3):
					for dir: int in [1, -1]:
						var stop := BigVehicles.block_stop(_plan, axis, index, k, dir)
						if is_nan(stop):
							continue
						var road := _plan.road_pos(axis, index)
						var q := Vector2(road, stop) if axis == CityPlan.AXIS_X else Vector2(stop, road)
						if _plan.zone_at(q) == MacroMap.Zone.CITY and _plan.road_open(axis, index, stop) and _plan.road_open(axis, index, stop - float(dir) * 60.0) and _plan.road_open(axis, index, stop + float(dir) * 80.0):
							return [axis, index, k, dir, stop]
	return []


## A left-turner on green waits in the box while an oncoming car comes through, then turns.
func _left_turn_gap() -> void:
	var road := _find_road(1, 80.0, true)
	if road.is_empty():
		road = _find_road(2, 80.0, true)
	if road.is_empty():
		_check(false, "a road with a signalled junction near the spawn, for the left-turn check")
		return
	var axis: int = road[0]
	var index: int = road[1]
	var k: int = road[2] + 1
	var node := _node(axis, index, k)
	var cross := _cross(axis)
	var cross_pos := _plan.road_pos(cross, k)
	var cw := _plan.road_width(cross, k)
	# The arm it turns onto must be open.
	var left := 1 if TrafficAI.turn_side(axis, 1, 1) < 0 else -1
	var lane_here := _plan.road_pos(axis, index)
	if not _plan.road_open(cross, k, lane_here + float(left) * (_plan.road_width(axis, index) * 0.5 + 3.0)):
		_check(true, "left-turn check skipped: the arm is closed here")
		return
	_stand(axis, index, cross_pos - 30.0, _plan.road_width(axis, index) * 0.5 + 4.0)
	TrafficSignals.force(_plan, node.x, node.y, axis, TrafficSignals.Light.GREEN, 0.3)
	await _ticks(2)
	_clear_crosswalks(node)
	var car := _traffic.place_car(axis, index, 1, 0, cross_pos - cw * 0.5 - 22.0, 7.0, true)
	var t: Dictionary = car.traffic
	t.tb = true
	t.node = node
	t.turn = left
	t.forced = false
	t.amber_go = false
	t.sign_ok = false
	t.sign_t = 0.0
	# The oncoming car, put on the road as the turner comes up to the box (a few seconds off).
	var on: Vehicle = null
	for i in 60 * 8:
		await _tree.physics_frame
		if not car.is_traffic() or cross_pos - _along(car, axis) < TrafficBehaviour.LEFT_WAIT_AT + 14.0:
			break
	on = _traffic.place_car(axis, index, -1, 0, cross_pos + cw * 0.5 + 26.0, 8.0, false)
	var c0 := int(TrafficBehaviour.counts.get("left_gap", 0))
	var waited := 0.0
	var turned_before := false
	var turned := false
	var oncoming_past := false
	for i in 60 * 20:
		await _tree.physics_frame
		if i % 30 == 0:
			TrafficSignals.force(_plan, node.x, node.y, axis, TrafficSignals.Light.GREEN, 0.3)
		if not car.is_traffic():
			break
		if on.is_traffic() and _along(on, axis) < cross_pos - cw * 0.5 - 3.0:
			oncoming_past = true
		if int(car.traffic.axis) != axis:
			turned = true
			turned_before = not oncoming_past
			break
		if float(car.traffic.get("v", 1.0)) < 0.05 and _to_line(car, axis, k) < 0.0:
			waited += 1.0 / 60.0
	_check(waited > 0.5, "a left-turner waits in the box for the oncoming car (%.1f s)" % waited)
	_check(turned and not turned_before, "and turns only once it has gone by (turned %s, before %s)" % [turned, turned_before])
	_check(int(TrafficBehaviour.counts.get("left_gap", 0)) > c0, "the gap it took is counted")


## Somebody on the far crosswalk: the car waits back from it, not with its nose on the stripes.
func _polite_crosswalk() -> void:
	var road := _find_road(1, 80.0, true)
	if road.is_empty():
		road = _find_road(2, 80.0, true)
	if road.is_empty():
		_check(false, "a road with a signalled junction near the spawn, for the crosswalk check")
		return
	var axis: int = road[0]
	var index: int = road[1]
	var k: int = road[2] + 1
	var node := _node(axis, index, k)
	var cross := _cross(axis)
	var cross_pos := _plan.road_pos(cross, k)
	var cw := _plan.road_width(cross, k)
	_stand(axis, index, cross_pos - 30.0, _plan.road_width(axis, index) * 0.5 + 4.0)
	TrafficSignals.force(_plan, node.x, node.y, axis, TrafficSignals.Light.GREEN, 0.3)
	await _ticks(2)
	_clear_crosswalks(node)
	var key := Vector4i(node.x, node.y, axis, 1)
	Pedestrian._crosswalks[key] = 1
	var car := _traffic.place_car(axis, index, 1, 0, cross_pos - cw * 0.5 - 30.0, 7.0, false)
	car.traffic.tb = true
	var stood := INF
	var looked := false
	for i in 60 * 10:
		await _tree.physics_frame
		if i % 30 == 0:
			TrafficSignals.force(_plan, node.x, node.y, axis, TrafficSignals.Light.GREEN, 0.3)
			Pedestrian._crosswalks[key] = 1
		if not car.is_traffic():
			break
		looked = looked or car.traffic.has("tb_look_at")
		if float(car.traffic.get("v", 1.0)) < 0.02 and i > 60:
			stood = cross_pos + cw * 0.5 + 0.15 - _along(car, axis) - float(car.traffic.get("half", 2.4))
			break
	Pedestrian._crosswalks.erase(key)
	var went := false
	for i in 60 * 6:
		await _tree.physics_frame
		if not car.is_traffic() or float(car.traffic.get("v", 0.0)) > 1.0:
			went = true
			break
	_check(stood > 0.9 and stood < 3.0, "a car waits back from a crosswalk somebody is on (%.2f m from it)" % stood)
	_check(looked, "and its driver looks at it")
	_check(went, "and goes once it is clear")


## A car standing in the road that is not traffic (a knocked-out car's stand-in), in lane n.
func _obstacle(axis: int, index: int, dir: int, lane_n: int, along: float) -> Vehicle:
	var o := _traffic.place_car(axis, index, dir, lane_n, along, 0.0, false)
	o.traffic = {}
	_traffic.cars.erase(o)
	TrafficBehaviour.survey(_traffic)
	return o


## Two lanes: the car behind signals, changes lanes round the wreck and passes it slowly.
func _wreck_two_lane() -> void:
	var road := _find_road(2, 160.0, false)
	if road.is_empty():
		_check(true, "wreck lane-change check skipped: no two-lane block near the spawn")
		return
	var axis: int = road[0]
	var index: int = road[1]
	var k: int = road[2]
	var cross := _cross(axis)
	var lo := _plan.road_pos(cross, k) + _plan.road_width(cross, k) * 0.5
	var hi := _plan.road_pos(cross, k + 1) - _plan.road_width(cross, k + 1) * 0.5
	var mid := (lo + hi) * 0.5 + 20.0
	_stand(axis, index, mid, _plan.road_width(axis, index) * 0.5 + 4.0)
	for kk: int in [k, k + 1, k + 2]:
		var nd := _node(axis, index, kk)
		if TrafficSignals.is_signal(_plan, nd.x, nd.y):
			TrafficSignals.force(_plan, nd.x, nd.y, axis, TrafficSignals.Light.GREEN, 0.2)
	await _ticks(2)
	var wreck := _obstacle(axis, index, 1, 1, mid)
	var car := _traffic.place_car(axis, index, 1, 1, lo + 6.0, 9.0, false)
	car.traffic.ai = true
	car.traffic.tb = true
	var c0 := int(TrafficBehaviour.counts.get("wreck_lane_change", 0))
	var worst := INF
	var passed := false
	var pass_speed := 0.0
	for i in 60 * 20:
		await _tree.physics_frame
		if i % 20 == 0:
			TrafficBehaviour.survey(_traffic)
		if not car.is_traffic():
			break
		var d := _along(wreck, axis) - _along(car, axis)
		var same := absf(_lateral(car, axis) - _lateral(wreck, axis)) < 1.9
		if same:
			worst = minf(worst, d - 4.8)
		if absf(d) < 3.0:
			pass_speed = maxf(pass_speed, float(car.traffic.get("v", 0.0)))
		if d < -8.0:
			passed = true
			break
	wreck.queue_free()
	_check(int(TrafficBehaviour.counts.get("wreck_lane_change", 0)) > c0, "a car behind a wreck asks for the other lane")
	_check(passed and worst > -0.5, "and passes it in the other lane without touching it (passed %s, closest in lane %.2f)" % [passed, worst])
	_check(pass_speed < TrafficBehaviour.RUBBERNECK_SPEED + 0.6, "slowly, to look (%.1f m/s beside it)" % pass_speed)


## One lane: the car edges round the wreck toward the centre line, clear of it, and back.
func _wreck_one_lane() -> void:
	var road := _find_road(1, 140.0, false)
	if road.is_empty():
		_check(true, "wreck dodge check skipped: no one-lane block near the spawn")
		return
	var axis: int = road[0]
	var index: int = road[1]
	var k: int = road[2]
	var cross := _cross(axis)
	var lo := _plan.road_pos(cross, k) + _plan.road_width(cross, k) * 0.5
	var hi := _plan.road_pos(cross, k + 1) - _plan.road_width(cross, k + 1) * 0.5
	var mid := (lo + hi) * 0.5 + 15.0
	_stand(axis, index, mid, _plan.road_width(axis, index) * 0.5 + 4.0)
	for kk: int in [k, k + 1, k + 2]:
		var nd := _node(axis, index, kk)
		if TrafficSignals.is_signal(_plan, nd.x, nd.y):
			TrafficSignals.force(_plan, nd.x, nd.y, axis, TrafficSignals.Light.GREEN, 0.2)
	await _ticks(2)
	var wreck := _obstacle(axis, index, 1, 0, mid)
	var car := _traffic.place_car(axis, index, 1, 0, lo + 6.0, 8.0, false)
	car.traffic.tb = true
	var c0 := int(TrafficBehaviour.counts.get("wreck_dodge", 0))
	var clear_beside := INF
	var passed := false
	var back := false
	var sig := false
	for i in 60 * 22:
		await _tree.physics_frame
		if i % 20 == 0:
			TrafficBehaviour.survey(_traffic)
		if not car.is_traffic():
			break
		sig = sig or int(car.traffic.get("sig", 0)) == -1
		var d := _along(wreck, axis) - _along(car, axis)
		if absf(d) < 4.6:
			clear_beside = minf(clear_beside, absf(_lateral(car, axis) - _lateral(wreck, axis)))
		if d < -6.0:
			passed = true
		if passed and absf(float(car.traffic.get("shift", 1.0))) < 0.1:
			back = true
			break
	wreck.queue_free()
	_check(int(TrafficBehaviour.counts.get("wreck_dodge", 0)) > c0 and sig, "on a one-lane road a car edges out round a wreck, signalling")
	_check(passed and clear_beside > TrafficBehaviour.DODGE_CLEAR - 0.3, "clear of it as it passes (%.2f m to the side)" % clear_beside)
	_check(back, "and back into its lane after it")


## A placed car that did not ask for it (`tb`) is left exactly as TrafficManager drives it.
func _placed_untouched() -> void:
	var car := _traffic.place_car(CityPlan.AXIS_X, 0, 1, 0, _home.z, 5.0, false)
	var t: Dictionary = car.traffic
	var gap := TrafficBehaviour.street_stop(_traffic, car, t, {}, _home.z, 0.0, 30.0, 0.5, 12.0, Vector2i(0, 1), true, 0.016)
	var nv := TrafficBehaviour.post_speed(car, t, 0.0, 0.0, 2.0, 0.016)
	_check(is_inf(gap) and nv == 0.0 and not t.has("tb_r"), "a car a check placed is left exactly as the traffic drives it (no tb)")
	_traffic._retire(car)
	_traffic.cars.erase(car)


## Heads: a look target on the car's right turns the driver's head right, on its left left.
func _heads() -> void:
	var car := _traffic.place_car(CityPlan.AXIS_X, 0, 1, 0, _home.z, 0.0, false)
	var t: Dictionary = car.traffic
	var right := car.global_position + car.global_basis.x * 5.0
	var left := car.global_position - car.global_basis.x * 5.0
	t.tb_look_at = _ws.to_world(right)
	t.tb_look_t = TrafficAI.clock
	var a := TrafficBehaviour.look_target(car, t, null, TrafficAI.clock)
	t.tb_look_at = _ws.to_world(left)
	var b := TrafficBehaviour.look_target(car, t, null, TrafficAI.clock)
	_check(a.x > 1.0 and b.x < -1.0, "a driver turns their head toward what they look at (right %.2f, left %.2f rad)" % [a.x, b.x])
	var src := FileAccess.get_file_as_string("res://shaders/car_cabin.gdshaderinc")
	_check(src.contains("uniform vec2 occupant_look") and src.contains("occupant_look.x"), "the traced heads read occupant_look")
	_traffic._retire(car)
	_traffic.cars.erase(car)
