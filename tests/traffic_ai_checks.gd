extends RefCounted
## Traffic AI checks for tests/smoke_test.gd (traffic-ai, 2026-10-05): drivers' moods, a car
## changing lanes round a bus at its stop (signalled first, never into anything), waiting for a
## gap past a double-parked car, getting into the turn lane, swerving round the player on foot,
## a honk at a driver who does not go on green, a parked car pulling out, and on the freeway a
## pass, a merge from an on-ramp and an exit down an off-ramp. Then the live traffic with all of
## it on - no car ever inside another - and what the traffic's tick costs with it on and off.
## Loaded at run time, so it compiles after the autoloads and can name TrafficAI freely.

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
	if _player.is_driving():
		_player.exit_vehicle()
	var home: Vector3 = _ws.to_world(_player.global_position)
	var police: Node = city.get_node_or_null("Police")
	var police_was: Variant = police.get("enabled") if police else null
	if police:
		police.set("enabled", false)
	var started_ms := Time.get_ticks_msec()
	_moods()
	_nose_order()
	_turn_in_clear()
	_traffic.staged = true
	_clear_traffic()
	await _bus_pass()
	_clear_traffic()
	await _double_park_gap()
	_clear_traffic()
	await _turn_lane()
	_clear_traffic()
	await _swerve()
	_clear_traffic()
	await _dawdle_honk()
	_clear_traffic()
	await _pullout(home)
	_clear_traffic()
	await _freeway_pass()
	_clear_traffic()
	await _freeway_ramps()
	_clear_traffic()
	_traffic.staged = false
	_player.global_position = _ws.to_local(home)
	_player.velocity = Vector3.ZERO
	_city.update_streaming(true)
	await _live_and_cost()
	if police:
		police.set("enabled", police_was)
	_player.global_position = _ws.to_local(home)
	_player.velocity = Vector3.ZERO
	await _ticks(3)
	print("traffic ai checks took %.1f s" % ((Time.get_ticks_msec() - started_ms) / 1000.0))


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


## Every junction within two of crossing k0 on road (axis, index) green for that road.
func _greens(axis: int, index: int, k0: int) -> void:
	for k in range(k0 - 2, k0 + 3):
		var node := Vector2i(index, k) if axis == CityPlan.AXIS_X else Vector2i(k, index)
		if TrafficSignals.is_signal(_plan, node.x, node.y):
			TrafficSignals.force(_plan, node.x, node.y, axis, TrafficSignals.Light.GREEN, 0.2)


## The player on foot `off` metres to the side of road (axis, index)'s centre line at `along`.
func _stand(axis: int, index: int, along: float, off: float) -> void:
	if _player.is_driving():
		_player.exit_vehicle()
	var road := _plan.road_pos(axis, index) + off
	var p := Vector2(road, along) if axis == CityPlan.AXIS_X else Vector2(along, road)
	_player.global_position = _ws.to_local(Vector3(p.x, _plan.height_at(p) + 1.0, p.y))
	_player.velocity = Vector3.ZERO


## A two-lane road with a bus stop near the spawn: [axis, index, k, dir, stop] or [].
func _find_stop() -> Array:
	for r in 16:
		for axis: int in [CityPlan.AXIS_X, CityPlan.AXIS_Z]:
			for index: int in [r, -r]:
				if BigVehicles.route_of(_plan, axis, index) == 0 or TrafficAI.lanes_of(_plan, axis, index) < 2 or _traffic._rail_street(axis, index):
					continue
				for k in range(-2, 3):
					for dir: int in [1, -1]:
						var stop := BigVehicles.block_stop(_plan, axis, index, k, dir)
						if is_nan(stop):
							continue
						var road := _plan.road_pos(axis, index)
						var q := Vector2(road, stop) if axis == CityPlan.AXIS_X else Vector2(stop, road)
						if _plan.zone_at(q) == MacroMap.Zone.CITY and _plan.road_open(axis, index, stop) and _plan.road_open(axis, index, stop - float(dir) * 120.0) and _plan.road_open(axis, index, stop + float(dir) * 60.0):
							return [axis, index, k, dir, stop]
	return []


## A two-lane open city road near the spawn with `need` metres of one block from crossing k on:
## [axis, index, k, dir, block start along, block end along] or [].
## `signal_end`: the junction at its +along end must have signals (a stop sign there can hold a
## car for as long as walkers keep stepping onto its crosswalk).
func _find_avenue(need: float, signal_end: bool = false) -> Array:
	for r in 20:
		for axis: int in [CityPlan.AXIS_X, CityPlan.AXIS_Z]:
			for index: int in [r, -r]:
				if TrafficAI.lanes_of(_plan, axis, index) < 2 or _traffic._rail_street(axis, index) or BigVehicles.route_of(_plan, axis, index) != 0:
					continue
				var cross := CityPlan.AXIS_Z if axis == CityPlan.AXIS_X else CityPlan.AXIS_X
				for k in range(-2, 3):
					var lo := _plan.road_pos(cross, k) + _plan.road_width(cross, k) * 0.5
					var hi := _plan.road_pos(cross, k + 1) - _plan.road_width(cross, k + 1) * 0.5
					if hi - lo < need:
						continue
					var mid := (lo + hi) * 0.5
					var road := _plan.road_pos(axis, index)
					var q := Vector2(road, mid) if axis == CityPlan.AXIS_X else Vector2(mid, road)
					if _plan.zone_at(q) != MacroMap.Zone.CITY or _traffic._replica_blocks(q, 6.0):
						continue
					var end_node := Vector2i(index, k + 1) if axis == CityPlan.AXIS_X else Vector2i(k + 1, index)
					if signal_end and not TrafficSignals.is_signal(_plan, end_node.x, end_node.y):
						continue
					if _plan.road_open(axis, index, lo + 2.0) and _plan.road_open(axis, index, hi - 2.0) and _plan.road_open(axis, index, hi + 60.0) and _plan.road_open(axis, index, lo - 60.0):
						return [axis, index, k, 1, lo, hi]
	return []


## Where a car is in its road's frame: [along, across] (true world).
func _frame(car: Vehicle, axis: int) -> Vector2:
	var w: Vector3 = _ws.to_world(car.global_position)
	return Vector2(w.z, w.x) if axis == CityPlan.AXIS_X else Vector2(w.x, w.z)


## True when two cars on one road overlap as boxes (length by a 1.9 m width) in the road frame.
func _overlap(a: Vehicle, b: Vehicle, axis: int) -> float:
	var fa := _frame(a, axis)
	var fb := _frame(b, axis)
	if absf(fa.y - fb.y) > 1.9:
		return INF
	var ta: Dictionary = a.traffic
	var tb: Dictionary = b.traffic
	var dir := float(ta.get("dir", 1))
	# Gap between the one behind's nose and the one ahead's tail (negative: inside it).
	if (fb.x - fa.x) * dir >= 0.0:
		return (fb.x - fa.x) * dir - float(ta.get("half", 2.4)) - float(tb.get("rear", tb.get("half", 2.4)))
	return (fa.x - fb.x) * dir - float(tb.get("half", 2.4)) - float(ta.get("rear", ta.get("half", 2.4)))


## A lane group is ordered by the noses (TrafficAI.nose_ahead()), not the centres: a car beside
## the front half of a bus dwelling at its stop (a lane change's ghost in the bus's lane) has its
## centre ahead of the bus's and its nose behind - by the centres it never braked for the bus and
## drove on into it (gate-flakes run 5757: -4.35 m).
func _nose_order() -> void:
	var bus := Vehicle.new()
	var car := Vehicle.new()
	bus.traffic = {"along": 100.0, "dir": 1, "half": 6.1, "rear": 6.1, "v": 0.0, "bus": 1}
	car.traffic = {"along": 101.5, "dir": 1, "half": 2.3, "rear": 2.3, "v": 3.0, "lc_p": 0.37}
	var key := 7
	var group: Array = [bus, car]
	group.sort_custom(func(a: Vehicle, b: Vehicle) -> bool: return TrafficAI.nose_ahead(a, b, 1.0))
	var ahead := TrafficAI.ahead_in({key: [bus, car]}, key, 101.5, 1, 2.3, car)
	var bus_ahead := TrafficAI.ahead_in({key: [bus, car]}, key, 100.0, 1, 6.1, bus)
	var room := TrafficAI.gap_ok(_traffic, {key: [bus]}, key, car, 101.5, 1, 3.0)
	# The same the other way: -x travel, the bus's nose further toward -x.
	bus.traffic.along = -100.0
	car.traffic.along = -101.5
	var back := [bus, car]
	back.sort_custom(func(a: Vehicle, b: Vehicle) -> bool: return TrafficAI.nose_ahead(a, b, -1.0))
	_check(group[1] == bus and not ahead.is_empty() and ahead[0] == bus and float(ahead[1]) < 0.0 and bus_ahead.is_empty() and not room and back[1] == bus,
		"a car beside a dwelling bus's front half has the bus ahead of it in the lane (bus last %s, car's ahead %s at %.1f m, bus's ahead %s, room to move in %s)" % [
			group[1] == bus, "bus" if not ahead.is_empty() and ahead[0] == bus else "none", float(ahead[1]) if not ahead.is_empty() else 99.0, "none" if bus_ahead.is_empty() else "car", room])
	bus.free()
	car.free()


## Moods: the shares, and what they do - the pushy keep shorter gaps, run an amber a careful
## driver stops for.
func _moods() -> void:
	var car := Vehicle.random_car(RandomNumberGenerator.new())
	var n := [0, 0, 0, 0]
	var samples := {}
	for i in 2000:
		var t := {"speed": 10.0}
		TrafficAI.roll_mood(car, t)
		n[int(t.mood)] += 1
		samples[int(t.mood)] = t
	var share := func(m: int) -> float: return float(n[m]) / 2000.0
	_check(absf(share.call(TrafficAI.Mood.PUSHY) - TrafficAI.PUSHY_SHARE) < 0.035 and absf(share.call(TrafficAI.Mood.CAREFUL) - TrafficAI.CAREFUL_SHARE) < 0.035
			and absf(share.call(TrafficAI.Mood.DOZY) - TrafficAI.DOZY_SHARE) < 0.03,
		"drivers' moods come in their shares (pushy %.3f, careful %.3f, dozy %.3f)" % [share.call(TrafficAI.Mood.PUSHY), share.call(TrafficAI.Mood.CAREFUL), share.call(TrafficAI.Mood.DOZY)])
	var p: Dictionary = samples[TrafficAI.Mood.PUSHY]
	var c: Dictionary = samples[TrafficAI.Mood.CAREFUL]
	var d: Dictionary = samples[TrafficAI.Mood.DOZY]
	_check(float(p.m_gap) < 1.0 and float(c.m_gap) > 1.0 and float(p.speed) > 10.0 and float(c.speed) < 10.0 and float(d.m_react) > 2.0 and float(p.m_patience) < float(c.m_patience),
		"a pushy driver keeps shorter gaps and drives faster than a careful one, a dozy one is slow off the line")
	# The same amber, 20 m from the line at 12 m/s (stopping needs 3.6 m/s^2 = brake_comfort).
	var node := Vector2i(0, 0)
	TrafficSignals.force(_plan, node.x, node.y, CityPlan.AXIS_X, TrafficSignals.Light.AMBER, 0.5)
	var pt := p.duplicate()
	var ct := c.duplicate()
	var runs := not _traffic._must_stop(pt, node, CityPlan.AXIS_X, 18.0, 12.0, 0.016)
	var stops := _traffic._must_stop(ct, node, CityPlan.AXIS_X, 18.0, 12.0, 0.016)
	_check(runs and stops, "on the same amber a pushy driver goes through and a careful one stops (pushy runs %s, careful stops %s)" % [runs, stops])
	car.free()


## A bus at its stop in the kerb lane and a car coming up behind it: the car signals, moves to the
## other lane once it is clear, passes the bus, and is never inside it.
## A car turning into a lane finds room by the cars' ends, not their centres: a bus whose centre
## is 7.5 m ahead has its rear 6.4 m behind that, so the old centre-to-centre test let a turning
## car land inside it (CI 355). Placed values only, no frames.
func _turn_in_clear() -> void:
	var bus := Vehicle.new()
	var car := Vehicle.new()
	bus.traffic = {"along": 107.5, "half": 6.35, "rear": 6.35}
	car.traffic = {"along": 0.0, "half": 2.3, "rear": 2.3}
	var groups := {7: [bus]}
	var behind_bus := not _traffic._group_clear(groups, 7, 100.0, 2.3 + 4.4, car, 1)
	bus.traffic.along = 122.0
	var room := _traffic._group_clear(groups, 7, 100.0, 2.3 + 4.4, car, 1)
	bus.free()
	car.free()
	_check(behind_bus and room,
		"a car turns in behind a bus only clear of its rear (blocked 7.5 m behind its centre %s, clear 22 m behind %s)" % [behind_bus, room])


func _bus_pass() -> void:
	var s := _find_stop()
	if s.is_empty():
		_check(false, "a two-lane road with a bus stop near the spawn, for the lane-change check")
		return
	var axis: int = s[0]
	var index: int = s[1]
	var dir: int = s[3]
	var stop: float = s[4]
	var cross := CityPlan.AXIS_Z if axis == CityPlan.AXIS_X else CityPlan.AXIS_X
	_greens(axis, index, _plan._index_at(cross, stop))
	_stand(axis, index, stop, -(_plan.road_width(axis, index) * 0.5 + 5.0) * float(-dir if axis == CityPlan.AXIS_X else dir))
	await _ticks(2)
	var lanes := TrafficAI.lanes_of(_plan, axis, index)
	var bus := _traffic.place_car(axis, index, dir, lanes - 1, stop - float(dir) * 9.0, 4.0, false, BigVehicles.BUS)
	# Held at its stop for the whole check (the car behind spends seconds pulled over first).
	bus.traffic.dwell_need = 60.0
	var car := _traffic.place_car(axis, index, dir, lanes - 1, stop - float(dir) * 85.0, 11.0, false)
	car.traffic.ai = true
	# Pulled over for a siren for its first seconds: no lane change may start while it yields.
	car.traffic.yield_t = 2.5
	var changed_yielding := false
	var signalled := false
	var lit := false
	var started := false
	var worst := INF
	var passed := false
	for i in 60 * 24:
		await _tree.physics_frame
		var t: Dictionary = car.traffic
		if not t.has("along"):
			continue
		# The seconds spent pulled over must not cost the forced green at the junction ahead.
		# (force() sets the one shared clock, so it is the junction the car is heading for.)
		if i == 180 and t.has("node"):
			var jn: Vector2i = t.node
			if TrafficSignals.is_signal(_plan, jn.x, jn.y):
				TrafficSignals.force(_plan, jn.x, jn.y, axis, TrafficSignals.Light.GREEN, 0.05)
		if float(t.get("yield_t", 0.0)) > 0.0 and (t.has("lc_want") or t.has("lc_from")):
			changed_yielding = true
		if not started and t.has("lc_from"):
			started = true
		if not started and int(t.get("sig", 0)) == -1:
			signalled = true
			lit = lit or car.light_signal == -1
		worst = minf(worst, _overlap(car, bus, axis))
		if (float(t.along) - float(bus.traffic.along)) * float(dir) > float(t.get("rear", 2.4)) + float(bus.traffic.get("half", 6.0)) + 1.0:
			passed = true
			break
	var inner := TrafficAI.lane_n(_plan, axis, index, float(car.traffic.lane)) == 0
	_check(not changed_yielding, "a car pulled over for a siren starts no lane change until it has gone by")
	_check(signalled and lit and started, "a car behind a bus at its stop signals left first, its indicator lit, then moves over (signalled %s, lamp %s, moved %s)" % [signalled, lit, started])
	_check(passed and inner and worst > -0.05, "it passes the bus in the other lane and is never inside it (passed %s, inner lane %s, tightest %.2f m)" % [passed, inner, worst if worst < INF else 99.0])


## A car double-parks on its hazards; the one behind it wants round it but a third runs alongside
## in the other lane: it waits, signalling, and moves over only into a safe gap.
func _double_park_gap() -> void:
	var a := _find_avenue(150.0)
	if a.is_empty():
		_check(false, "a two-lane road near the spawn for the double-parking check")
		return
	var axis: int = a[0]
	var index: int = a[1]
	var dir: int = a[3]
	var lo: float = a[4]
	_greens(axis, index, int(a[2]))
	_stand(axis, index, lo + 60.0, _plan.road_width(axis, index) * 0.5 + 5.0)
	await _ticks(2)
	var lanes := TrafficAI.lanes_of(_plan, axis, index)
	var parker := _traffic.place_car(axis, index, dir, lanes - 1, lo + 40.0, 6.0, false)
	parker.traffic.dp_at = lo + 70.0
	parker.traffic.dp = 40.0
	parker.traffic.sig = 1
	var car := _traffic.place_car(axis, index, dir, lanes - 1, lo + 14.0, 7.0, false)
	car.traffic.ai = true
	var side := _traffic.place_car(axis, index, dir, 0, lo + 9.0, 7.0, false)
	var hazards := false
	var waited := false
	var start_gap := INF
	var worst := INF
	var moved := false
	for i in 60 * 22:
		await _tree.physics_frame
		var t: Dictionary = car.traffic
		if not t.has("along") or not side.traffic.has("along"):
			continue
		hazards = hazards or (parker.light_signal == 2 and float(parker.traffic.get("v", 1.0)) < 0.1)
		if t.has("lc_want") and float(t.get("lc_wait", 0.0)) > TrafficAI.SIGNAL_SECONDS * 1.5:
			waited = true
		if t.has("lc_from") and not moved:
			moved = true
			var g := (float(t.along) - float(side.traffic.along)) * float(dir)
			start_gap = absf(g) - float(t.get("half", 2.4)) - float(side.traffic.get("half", 2.4))
		worst = minf(worst, minf(_overlap(car, parker, axis), _overlap(car, side, axis)))
		if moved and not t.has("lc_from") and (float(t.along) - float(parker.traffic.along)) * float(dir) > 8.0:
			break
	_check(hazards, "a double-parked car stands on its hazards")
	_check(waited and moved and start_gap > 1.5 and worst > -0.05,
		"the car behind it waits, signalling, while the other lane is taken, and moves over only into a gap (waited %s, moved %s, gap at the start %.1f m, tightest %.2f m)" % [waited, moved, start_gap, worst if worst < INF else 99.0])


## A car in the kerb lane with a left turn coming up gets into the inner lane before the junction,
## signalling left, and turns into the inner lane of the cross street.
func _turn_lane() -> void:
	var a := _find_avenue(150.0, true)
	if a.is_empty():
		return
	var axis: int = a[0]
	var index: int = a[1]
	var dir: int = a[3]
	var lo: float = a[4]
	var hi: float = a[5]
	var k: int = a[2]
	var cross := CityPlan.AXIS_Z if axis == CityPlan.AXIS_X else CityPlan.AXIS_X
	_greens(axis, index, k + 1)
	var cross_index := k + 1
	var lane_here := _plan.road_pos(axis, index)
	var turn := 0
	for nd: int in [1, -1]:
		if TrafficAI.turn_side(axis, dir, nd) == -1 and _plan.road_open(cross, cross_index, lane_here + nd * (_plan.road_width(axis, index) * 0.5 + 3.0)):
			turn = nd
	if turn == 0:
		_check(false, "an open left turn at the end of the turn-lane check's block")
		return
	_stand(axis, index, lo + 20.0, _plan.road_width(axis, index) * 0.5 + 5.0)
	await _ticks(2)
	var lanes := TrafficAI.lanes_of(_plan, axis, index)
	var car := _traffic.place_car(axis, index, dir, lanes - 1, maxf(lo + 6.0, hi - 120.0), 9.0, true)
	car.traffic.ai = true
	await _ticks(1)
	car.traffic.turn = turn
	car.traffic.forced = false
	var signalled_left := false
	var inner_before := false
	var turned := false
	var forced_green := false
	for i in 60 * 26:
		await _tree.physics_frame
		var t: Dictionary = car.traffic
		if int(t.axis) == axis:
			if int(t.get("sig", 0)) == -1 or car.light_signal == -1:
				signalled_left = true
			var to_c := float(t.get("to_c", INF))
			if to_c < _plan.road_width(cross, cross_index) * 0.5 + 4.0 and to_c > 0.0 and TrafficAI.lane_n(_plan, axis, index, float(t.lane)) == 0 and not t.has("lc_from"):
				inner_before = true
			if int(t.turn) != turn and to_c > 30.0:
				t.turn = turn
			# TrafficSignals.force() sets the one shared clock: green for this junction as the car
			# comes up to it, whatever the others show.
			# Again every two seconds while it stands at the line: the forced phase runs out, and a
			# busy crosswalk can hold the car past it.
			var held_here := to_c < 40.0 and float(t.get("v", 0.0)) < 0.3 and i % 120 == 0
			if (to_c < 70.0 and not forced_green) or held_here:
				forced_green = true
				var jn := Vector2i(index, cross_index) if axis == CityPlan.AXIS_X else Vector2i(cross_index, index)
				if TrafficSignals.is_signal(_plan, jn.x, jn.y):
					TrafficSignals.force(_plan, jn.x, jn.y, axis, TrafficSignals.Light.GREEN, 0.2)
		else:
			turned = true
			break
	if not turned:
		printerr("traffic ai: turn-lane car never turned: %s" % str(car.traffic))
	var on_inner := turned and TrafficAI.lane_n(_plan, int(car.traffic.axis), int(car.traffic.index), float(car.traffic.lane)) == 0
	_check(signalled_left and inner_before and on_inner,
		"a car with a left turn signals, moves to the inner lane before the junction and turns into the inner lane (signal %s, inner before %s, turned %s, inner after %s)" % [signalled_left, inner_before, turned, on_inner])


## The player on foot in the kerb lane mid-block: a car coming up in that lane swerves into the
## clear lane beside it instead of braking to a stop, and honks; it never touches the player.
func _swerve() -> void:
	var a := _find_avenue(150.0)
	if a.is_empty():
		return
	var axis: int = a[0]
	var index: int = a[1]
	var dir: int = a[3]
	var lo: float = a[4]
	_greens(axis, index, int(a[2]))
	var lanes := TrafficAI.lanes_of(_plan, axis, index)
	var kerb := TrafficAI.lane_offset_n(_plan, axis, index, dir, lanes - 1)
	_stand(axis, index, lo + 95.0, kerb)
	await _ticks(3)
	var logged := TrafficAI.honk_log.size()
	var car := _traffic.place_car(axis, index, dir, lanes - 1, lo + 30.0, 11.0, false)
	car.traffic.ai = true
	# Not a car that rolls a double park on the way (2.5 % a block, a hash of the car: it stood
	# at its kerb 4 m in and never reached the player).
	car.traffic.no_dp = true
	var swerved := false
	var closest := INF
	var slowest := INF
	var stop_note := ""
	for i in 60 * 12:
		await _tree.physics_frame
		var t: Dictionary = car.traffic
		if not t.has("along"):
			continue
		swerved = swerved or str(t.get("lc_why", "")) == "swerve"
		var pw: Vector3 = _ws.to_world(_player.global_position)
		var cw: Vector3 = _ws.to_world(car.global_position)
		var along_d := (pw.z - cw.z) if axis == CityPlan.AXIS_X else (pw.x - cw.x)
		var lat := absf(pw.x - cw.x) if axis == CityPlan.AXIS_X else absf(pw.z - cw.z)
		if absf(along_d) < float(t.get("half", 2.4)) + 0.4:
			closest = minf(closest, lat)
		if float(t.get("v", 0.0)) < 0.5 and stop_note.is_empty():
			stop_note = _why_stopped(car, pw, axis, index)
		slowest = minf(slowest, float(t.get("v", 0.0)))
		if along_d * float(dir) < -10.0:
			break
	var honked := false
	for k in range(logged, TrafficAI.honk_log.size()):
		if int(TrafficAI.honk_log[k][1]) == car.get_instance_id():
			honked = true
	_check(swerved and closest > 1.5 and slowest > 2.0 and honked,
		"a car swerves into the clear lane round the player standing in the road, honking, and keeps going (swerved %s, closest %.1f m to the side, slowest %.1f m/s, honked %s)" % [swerved, closest, slowest, honked])
	if not stop_note.is_empty() and not (swerved and closest > 1.5 and slowest > 2.0 and honked):
		printerr("traffic ai: swerve car stopped: %s" % stop_note)
	_stand(axis, index, lo + 95.0, _plan.road_width(axis, index) * 0.5 + 5.0)


## What held the swerve car (printed when the check fails): its own state, the player, and every
## other street car within 40 m of it.
func _why_stopped(car: Vehicle, pw: Vector3, axis: int, index: int) -> String:
	var t: Dictionary = car.traffic
	var cw: Vector3 = _ws.to_world(car.global_position)
	var keys := {}
	for k in t.keys():
		if k in ["axis", "index", "dir", "lane", "along", "v", "turn", "to_c", "lc_why", "lc_key", "sig", "park_at", "dp_at", "cp", "valet", "pull", "work", "placed", "ai", "held", "forced"]:
			keys[k] = t[k]
	var others := []
	for c in _traffic.cars:
		if c != car and is_instance_valid(c):
			var ow: Vector3 = _ws.to_world(c.global_position)
			if ow.distance_to(cw) < 40.0:
				var ot: Dictionary = c.traffic
				others.append("%s lane %s along %.1f v %.1f placed %s" % [c.name, str(ot.get("lane", "?")), float(ot.get("along", 0.0)), float(ot.get("v", 0.0)), str(ot.get("placed", false))])
	return "car %s in cars %s at %s, player %s (%.1f m), road %d/%d, %s, others %s, cars %d, staged %s" % [car.name, _traffic.cars.has(car), cw, pw, cw.distance_to(pw), axis, index, keys, others, _traffic.cars.size(), _traffic.staged]


## A dozy driver at the front of a red-light queue does not go on green: the car behind honks at
## it, and it goes a few seconds later.
func _dawdle_honk() -> void:
	var node := Vector2i(0, 0)
	var cross_w := _plan.road_width(CityPlan.AXIS_Z, 0)
	var cross_pos := _plan.road_pos(CityPlan.AXIS_Z, 0)
	_stand(CityPlan.AXIS_X, 0, cross_pos - 20.0, _plan.road_width(CityPlan.AXIS_X, 0) * 0.5 + 5.0)
	TrafficSignals.force(_plan, node.x, node.y, CityPlan.AXIS_X, TrafficSignals.Light.RED, 0.5)
	await _ticks(2)
	var front := _traffic.place_car(CityPlan.AXIS_X, 0, 1, 0, cross_pos - cross_w * 0.5 - 20.0, 6.0, false)
	TrafficAI.roll_mood(front, front.traffic, TrafficAI.Mood.DOZY)
	front.traffic.m_react = 4.5
	var back := _traffic.place_car(CityPlan.AXIS_X, 0, 1, 0, cross_pos - cross_w * 0.5 - 40.0, 6.0, false)
	for i in 60 * 8:
		await _tree.physics_frame
		if i > 90 and float(front.traffic.get("v", 1.0)) < 0.05 and float(back.traffic.get("v", 1.0)) < 0.05:
			break
	# The live crowd off this junction's crosswalks: a walker still crossing is a right reason for
	# the front car to wait, and then nobody is dawdling.
	for p in _tree.get_nodes_in_group("pedestrian"):
		var w := p as Pedestrian
		if w and w._cross != Pedestrian.Cross.NONE and w._cross_key.x == node.x and w._cross_key.y == node.y:
			w.queue_free()
	await _ticks(2)
	var logged := TrafficAI.honk_log.size()
	TrafficSignals.force(_plan, node.x, node.y, CityPlan.AXIS_X, TrafficSignals.Light.GREEN, 0.2)
	var waited := 0.0
	var went := false
	var honked := false
	for i in 60 * 10:
		await _tree.physics_frame
		if float(front.traffic.get("v", 0.0)) < 0.05 and not went:
			waited += 1.0 / 60.0
		else:
			went = true
		for k in range(logged, TrafficAI.honk_log.size()):
			if TrafficAI.honk_log[k][0] == "dawdle" and int(TrafficAI.honk_log[k][1]) == back.get_instance_id():
				honked = true
		if went and honked:
			break
	_check(waited > 3.5 and went and honked, "a dozy driver sits through the start of the green, the car behind honks, then it goes (waited %.1f s, honked %s, went %s)" % [waited, honked, went])


## A parked car near the player pulls out: off its chunk's list, no physics wheels, signalling
## left, into the kerb lane once it is clear, and drives off.
func _pullout(home: Vector3) -> void:
	_player.global_position = _ws.to_local(home)
	_player.velocity = Vector3.ZERO
	_city.update_streaming(true)
	var list: Array = []
	for i in 60 * 6:
		await _tree.physics_frame
		if i % 20 == 0:
			list = TrafficAI.pullout_candidates(_traffic)
			if not list.is_empty():
				break
	if list.is_empty():
		_check(false, "a parked car near the player that could pull out")
		return
	var car: Vehicle = list[0]
	var ok := TrafficAI.pullout(_traffic, car)
	var listed := false
	for chunk in _city.chunks.values():
		if is_instance_valid(chunk) and (chunk.get("_cars") as Array).has(car):
			listed = true
	var physical_wheels := 0
	for c in car.get_children():
		if c is VehicleWheel3D:
			physical_wheels += 1
	_check(ok and not listed and physical_wheels == 0 and car.freeze and _traffic.cars.has(car),
		"a parked car pulling out leaves its chunk, has no physics wheels and is kinematic traffic (listed %s, wheels %d)" % [listed, physical_wheels])
	var axis: int = car.traffic.axis
	var start := _frame(car, axis)
	var lit := false
	var went := false
	for i in 60 * 14:
		await _tree.physics_frame
		lit = lit or car.light_signal == -1
		var t: Dictionary = car.traffic
		if not t.has("pull") and not t.has("lc_from") and absf(_frame(car, axis).x - start.x) > 8.0:
			went = true
			break
	var lane_pos := _plan.road_pos(axis, int(car.traffic.index)) + float(car.traffic.lane)
	var off := absf(_frame(car, axis).y - lane_pos)
	_check(lit and went and off < 0.15, "it signals, pulls out into the kerb lane and drives off (indicator %s, went %s, %.2f m off the lane)" % [lit, went, off])


## Two freeway cars in one lane, the one behind much faster: it moves over, passes, and they are
## never closer than the freeway's following rule allows in one lane.
func _freeway_pass() -> void:
	var fw: Freeway = _plan.macro.freeway if _plan.macro else null
	if fw == null or fw.routes.is_empty():
		return
	var ri := 0
	var t0 := fw.length_of(ri) * 0.5
	var at: Vector3 = fw.point_at(ri, t0)[0]
	_player.global_position = _ws.to_local(at + Vector3(0.0, 40.0, 0.0))
	_player.velocity = Vector3.ZERO
	var slow := _traffic.place_freeway_car(ri, t0 + 70.0, 1, -1, 13.0)
	var fast := _traffic.place_freeway_car(ri, t0, 1, -1, 28.0)
	fast.traffic.ai = true
	var moved := false
	var passed := false
	var worst := INF
	for i in 60 * 20:
		await _tree.physics_frame
		_player.velocity = Vector3.ZERO
		_player.global_position = _ws.to_local(at + Vector3(0.0, 40.0, 0.0))
		_keep_freeway_clear(ri, 1, float(fast.traffic.t), float(slow.traffic.t))
		var a: Dictionary = fast.traffic
		var b: Dictionary = slow.traffic
		moved = moved or a.has("lc_from")
		if int(a.get("li", 1)) == int(b.get("li", 1)) and not a.has("lc_from"):
			worst = minf(worst, absf(float(b.t) - float(a.t)) - float(a.half) - float(b.rear))
		if float(a.t) > float(b.t) + 30.0:
			passed = true
			break
	_check(moved and passed and worst > 2.0, "a fast freeway car moves over and passes a slow one (moved %s, passed %s, closest in one lane %.1f m)" % [moved, passed, worst if worst < INF else 999.0])


## FreewayFill refills the freeway round the player even while staged (16 cars a tick, ~42 m
## apart a lane), and a 28 m/s car needs ~70 m clear to move over: in that traffic it rightly stays
## behind (gate-flakes' final run, "moved false"). What the pass check measures is the pass, so
## the stretch round its two cars is kept clear of everything not placed.
func _keep_freeway_clear(ri: int, dir: int, t_a: float, t_b: float) -> void:
	var lo := minf(t_a, t_b) - 160.0
	var hi := maxf(t_a, t_b) + 160.0
	for c in _traffic.freeway_cars.duplicate():
		if not is_instance_valid(c):
			continue
		var ct: Dictionary = c.traffic
		if ct.has("placed") or int(ct.get("fw", -1)) != ri or int(ct.get("dir", 0)) != dir or ct.has("ramp"):
			continue
		if float(ct.t) > lo and float(ct.t) < hi:
			_traffic.freeway_cars.erase(c)
			_traffic._retire(c)


## A car up an on-ramp merges into the outer lane; a car with an exit leaves by the off-ramp.
func _freeway_ramps() -> void:
	var fw: Freeway = _plan.macro.freeway if _plan.macro else null
	if fw == null:
		return
	var on_ramp := {}
	var off_ramp := {}
	var ri_on := -1
	var ri_off := -1
	for ri in fw.routes.size():
		for r: Dictionary in TrafficAI.ramps_of(_traffic, fw, ri):
			if bool(r.on) and on_ramp.is_empty() and float(r.t) > 400.0:
				on_ramp = r
				ri_on = ri
			if not bool(r.on) and off_ramp.is_empty() and float(r.t) > 400.0:
				off_ramp = r
				ri_off = ri
	if on_ramp.is_empty() or off_ramp.is_empty():
		_check(false, "the freeway has an on-ramp and an off-ramp to check (on %s, off %s)" % [not on_ramp.is_empty(), not off_ramp.is_empty()])
		return
	# On: the player hovering over the merge point, so the car stays in range.
	var merge_at: Vector3 = TrafficAI.ramp_point(on_ramp, 0.0)[0]
	var hover := merge_at + Vector3(0.0, 60.0, 0.0)
	var merges := int(TrafficAI.counts.get("fw_merge", 0))
	_traffic._spawn_ramp_car(ri_on, on_ramp)
	var car: Vehicle = _traffic.freeway_cars.back()
	var rose := false
	var merged := false
	var settled := false
	var start_y: float = car.global_position.y
	# A dense outer lane past the merge point, as FreewayFill makes it (a car every 40 m at
	# 25 m/s): a gap a standing start may take hardly ever comes by itself (CI 399, gate-flakes
	# run 7373: the ramp car stood at its merge point the whole window), so a car coming up the
	# lane has to let it in (TrafficAI.merge_yielders()). Nothing else in that stretch.
	var width_on := float(fw.routes[ri_on].width)
	var ramp_t := float(on_ramp.t)
	var stream: Array[Vehicle] = []
	var put := func(at_t: float) -> void:
		var s := _traffic.place_freeway_car(ri_on, at_t, -1, -1, 25.0)
		s.traffic.li = Freeway.LANES - 1
		s.traffic.lane = -Freeway.lane_fraction(width_on, Freeway.LANES - 1)
		s.traffic.v = 25.0
		stream.append(s)
	_player.velocity = Vector3.ZERO
	_player.global_position = _ws.to_local(hover)
	_keep_freeway_clear(ri_on, -1, ramp_t - 60.0, ramp_t + 300.0)
	for k in range(-1, 8):
		put.call(ramp_t + 300.0 - 40.0 * float(k + 1) - 20.0)
	var stream_left := 40.0 / 25.0
	var waited := 0
	for i in 60 * 20:
		await _tree.physics_frame
		_player.velocity = Vector3.ZERO
		_player.global_position = _ws.to_local(hover)
		if not is_instance_valid(car):
			break
		_keep_freeway_clear(ri_on, -1, ramp_t - 60.0, ramp_t + 300.0)
		if car.traffic.has("ramp"):
			stream_left -= 1.0 / 60.0
			if stream_left <= 0.0:
				stream_left = 40.0 / 25.0
				put.call(ramp_t + 300.0)
			if car.traffic.get("ramp_wait", false):
				waited += 1
		rose = rose or car.global_position.y > start_y + 3.0
		if not car.traffic.has("ramp"):
			merged = true
			# In the outer lane, or drifting into it (a slow runner can end the window mid-move).
			if int(car.traffic.li) == Freeway.LANES - 1 and int(car.traffic.dir) == -1:
				settled = true
				break
	for c in stream:
		if is_instance_valid(c) and c != car:
			_traffic.freeway_cars.erase(c)
			_traffic._retire(c)
	if not settled:
		printerr("traffic ai: merging car never settled: valid %s in tree %s %s" % [is_instance_valid(car), is_instance_valid(car) and car.is_inside_tree(), str(car.traffic) if is_instance_valid(car) else ""])
	_check(rose and merged and settled and int(TrafficAI.counts.get("fw_merge", 0)) > merges,
		"a car climbs an on-ramp and merges into the outer lane of the freeway, a car every 40 m in it (climbed %s, merged %s, in lane %s, waited %.1f s at the merge)" % [rose, merged, settled, waited / 60.0])
	# Off: a car in the outer lane 160 m before an off-ramp, with an exit to make.
	var t0 := float(off_ramp.t) - 160.0
	var at: Vector3 = fw.point_at(ri_off, t0)[0]
	var exits := int(TrafficAI.counts.get("fw_exit", 0))
	# An incident worked out from the clock near this ramp holds the drivers' thinking off (one
	# single-process CI run): the exit is the AI's, so stage it with none.
	var incidents_were: bool = FreewayIncidents.enabled
	FreewayIncidents.enabled = false
	# Nor does the four-level stack take it at a diverge on the way (StackTraffic takes a share of
	# the cars coming up to one off the main line: gate run 4444, "left false, went down false").
	var stack_traffic: Node = _traffic.get_parent().get_node_or_null("StackTraffic") if _traffic.get_parent() else null
	var take_was: float = stack_traffic.get("take_share") if stack_traffic else 0.0
	if stack_traffic:
		stack_traffic.set("take_share", 0.0)
	var leaver := _traffic.place_freeway_car(ri_off, t0, 1, -1, 22.0)
	var width := float(fw.routes[ri_off].width)
	leaver.traffic.li = Freeway.LANES - 1
	leaver.traffic.lane = Freeway.lane_fraction(width, Freeway.LANES - 1)
	leaver.traffic.exit = true
	leaver.traffic.ai = true
	var left := false
	var down := false
	var top_y := 0.0
	for i in 60 * 16:
		await _tree.physics_frame
		_player.velocity = Vector3.ZERO
		_player.global_position = _ws.to_local(at + Vector3(0.0, 60.0, 0.0))
		if not is_instance_valid(leaver) or not leaver.is_inside_tree() or not _traffic.freeway_cars.has(leaver):
			down = left
			break
		if leaver.traffic.has("ramp") and not left:
			left = true
			top_y = leaver.global_position.y
		if left and leaver.global_position.y < top_y - 4.0:
			down = true
	FreewayIncidents.enabled = incidents_were
	if stack_traffic:
		stack_traffic.set("take_share", take_was)
	var gone := "" if left else (" (%s)" % ("freed" if not is_instance_valid(leaver) else ("parent %s, fw car %s" % [leaver.get_parent().name if leaver.get_parent() else "none", _traffic.freeway_cars.has(leaver)])))
	_check(left and down and int(TrafficAI.counts.get("fw_exit", 0)) > exits, "a car with an exit leaves the freeway down the off-ramp (left %s, went down %s%s)" % [left, down, gone])


## The live traffic with all of it on: no car ever inside another on the same carriageway (as
## boxes, so a car part way through a lane change counts against both lanes), and what driving the
## traffic costs a tick with the AI on and off.
func _live_and_cost() -> void:
	var worst := INF
	var changes0 := 0
	for k in TrafficAI.counts:
		if str(k).begins_with("street_"):
			changes0 += int(TrafficAI.counts[k])
	for i in 60 * 7:
		await _tree.physics_frame
		if i % 6 != 0:
			continue
		var by_road := {}
		for car in _traffic.cars:
			if not is_instance_valid(car) or not car.is_inside_tree() or not car.traffic.has("along") or car.traffic.has("pull"):
				continue
			# A filtering motorcycle rides between the lanes beside the queue it passes.
			if car.traffic.get("filtering", false):
				continue
			var key := Vector3i(int(car.traffic.axis), int(car.traffic.index), int(car.traffic.dir))
			if not by_road.has(key):
				by_road[key] = []
			(by_road[key] as Array).append(car)
		for key in by_road:
			var g: Array = by_road[key]
			for a in g.size():
				for b in range(a + 1, g.size()):
					var o := _overlap(g[a], g[b], (key as Vector3i).x)
					if o < -0.3 and o < worst:
						printerr("traffic ai: overlap %.2f m: %s vs %s" % [o, str(g[a].traffic), str(g[b].traffic)])
					worst = minf(worst, o)
	var changes := 0
	for k in TrafficAI.counts:
		if str(k).begins_with("street_"):
			changes += int(TrafficAI.counts[k])
	_check(worst > -0.3, "live traffic with lane changes, moods and pull-outs never drives into another car (tightest %.2f m, %d lane changes in the run)" % [worst if worst < INF else 99.0, changes - changes0])
	# The cost: the traffic's own smoothed tick time, AI off, then on.
	var off := await _cost(false)
	var on := await _cost(true)
	print("TRAFFIC_TICK_US ai_on=%.0f ai_off=%.0f street_cars=%d freeway_cars=%d" % [on, off, _traffic.cars.size(), _traffic.freeway_cars.size()])
	_check(on < off * 2.0 + 400.0, "the traffic's tick with the AI on stays close to what it was (%.0f us on, %.0f us off)" % [on, off])


func _cost(ai: bool) -> float:
	TrafficAI.enabled = ai
	_traffic.drive_usec = 0.0
	await _ticks(20)
	var sum := 0.0
	for i in 90:
		await _tree.physics_frame
		sum += _traffic.drive_usec
	TrafficAI.enabled = true
	return sum / 90.0
