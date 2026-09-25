extends RefCounted
## Street-life checks for tests/smoke_test.gd (owner, 2026-09-24: "GTA-level street life"):
## traffic signals, queues, pedestrians crossing on the walk phase, cars yielding to them, and a
## cruiser routed along the streets to a player standing mid-block. Loaded at run time (not named
## there), so it compiles after the autoloads and can name TrafficSignals, TrafficManager,
## Pedestrian and StreetRoute freely. Every scenario forces the one shared signal clock
## (TrafficSignals.force), so none of it waits for a light to change on its own: about twenty
## seconds of game time in all.

var _t: Node
var _tree: SceneTree
var _city: Node3D
var _plan: CityPlan
var _traffic: TrafficManager
var _ws: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	_tree = t.get_tree()
	_city = city
	_plan = city.plan
	_traffic = city.get_node("Traffic") as TrafficManager
	_ws = _tree.root.get_node("/root/WorldState")
	# The player goes back where the checks found him: the air traffic's checks later fire a
	# rocket from wherever he stands, and from the pavement mid-block it hits a building.
	var player := _tree.get_first_node_in_group("player") as Player
	var home: Vector3 = _ws.to_world(player.global_position)
	_hardware()
	_timing()
	await _live_queues()
	# Hands off the street cars while the checks place their own (TrafficManager.staged).
	_traffic.staged = true
	_clear_traffic()
	await _red_and_green()
	await _yield_to_walkers()
	await _crossing()
	_clear_traffic()
	await _police_route()
	_traffic.staged = false
	player.global_position = _ws.to_local(home)
	player.velocity = Vector3.ZERO
	_city.update_streaming(true)
	await _ticks(5)


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


## The model and the batches: the numbers the placing code builds on are the model's, and a
## signalised junction in a full-detail chunk carries heads that the lens shader lights.
func _hardware() -> void:
	var arm := PropFactory.signal_part("sig_arm").get_aabb()
	var pole := PropFactory.signal_part("sig_pole").get_aabb()
	var bracket := PropFactory.signal_part("sig_bracket").get_aabb()
	_check(absf(arm.end.x - PropFactory.SIGNAL_ARM_LENGTH) < 0.05 and absf(pole.end.y - PropFactory.SIGNAL_POLE_HEIGHT) < 0.1 and absf(bracket.end.x - PropFactory.SIGNAL_BRACKET_REACH) < 0.03,
		"the signal model matches the numbers it is placed with (arm %.2f, pole %.2f, bracket %.2f)" % [arm.end.x, pole.end.y, bracket.end.x])
	var lens := PropFactory.signal_lens_material()
	var timing: Vector4 = lens.get_shader_parameter("timing")
	_check(timing.is_equal_approx(Vector4(TrafficSignals.GREEN, TrafficSignals.AMBER, TrafficSignals.ALL_RED, TrafficSignals.WALK_TIME)),
		"the lens shader times its lamps from TrafficSignals (%s)" % timing)
	var heads := 0
	var peds := 0
	var junctions := 0
	var lit_by_shader := false
	for k in _city.chunks:
		var chunk: Node = _city.chunks[k]
		if int(chunk.get("level")) != 0 or not TrafficSignals.is_signal(_plan, k.x + 1, k.y + 1):
			continue
		var hb := chunk.get_node_or_null("Batch_sig_head") as MultiMeshInstance3D
		var pb := chunk.get_node_or_null("Batch_sig_ped") as MultiMeshInstance3D
		if hb == null or pb == null:
			continue
		junctions += 1
		heads += hb.multimesh.instance_count
		peds += pb.multimesh.instance_count
		var mesh := hb.multimesh.mesh
		for s in mesh.get_surface_count():
			if mesh.surface_get_material(s) == lens:
				lit_by_shader = hb.multimesh.use_custom_data
	_check(junctions >= 2 and heads >= junctions * 8 and peds == junctions * 8 and lit_by_shader,
		"signalised junctions carry mast-arm heads and pedestrian heads lit by the lens shader (%d junctions, %d heads, %d pedestrian heads)" % [junctions, heads, peds])


## The analytic cycle: the two axes never both have green, each sees green, amber and red, the
## box has an all-red, and people walk with the traffic beside them, never across a green.
func _timing() -> void:
	var saved := TrafficSignals.clock
	var both_green := false
	var all_red := false
	var seen := {}
	var walk_bad := false
	var walked := false
	var step := 0.25
	var t := 0.0
	while t < TrafficSignals.CYCLE:
		TrafficSignals.set_clock(t)
		var lx := TrafficSignals.light(_plan, 0, 0, CityPlan.AXIS_X)
		var lz := TrafficSignals.light(_plan, 0, 0, CityPlan.AXIS_Z)
		seen[Vector2i(0, lx)] = true
		seen[Vector2i(1, lz)] = true
		both_green = both_green or (lx == TrafficSignals.Light.GREEN and lz == TrafficSignals.Light.GREEN)
		all_red = all_red or (lx == TrafficSignals.Light.RED and lz == TrafficSignals.Light.RED)
		for crossing: int in [CityPlan.AXIS_X, CityPlan.AXIS_Z]:
			var w := TrafficSignals.walk(_plan, 0, 0, crossing)
			var crossed_light := lx if crossing == CityPlan.AXIS_X else lz
			if w != TrafficSignals.Walk.DONT and crossed_light != TrafficSignals.Light.RED:
				walk_bad = true
			walked = walked or w == TrafficSignals.Walk.WALK
		t += step
	TrafficSignals.set_clock(saved)
	_check(not both_green and all_red and seen.size() == 6, "the signal cycle gives each axis green, amber and red, never both green, with an all-red")
	_check(walked and not walk_bad, "the walking figure only shows while the road being crossed has red")


## Live traffic, as it drives: no car ever inside another in the same lane.
func _live_queues() -> void:
	var worst := INF
	var stopped := 0
	for i in 100:
		await _tree.physics_frame
		if i % 10 != 0:
			continue
		var groups := {}
		for car in _traffic.cars:
			if not is_instance_valid(car) or not car.is_inside_tree() or not car.traffic.has("along"):
				continue
			var key := TrafficManager.lane_key(int(car.traffic.axis), int(car.traffic.index), int(car.traffic.dir), float(car.traffic.lane))
			if not groups.has(key):
				groups[key] = []
			(groups[key] as Array).append(car)
			if float(car.traffic.get("v", 1.0)) < 0.3:
				stopped += 1
		for key in groups:
			var g: Array = groups[key]
			for a in g.size():
				for b in range(a + 1, g.size()):
					var ta: Dictionary = g[a].traffic
					var tb: Dictionary = g[b].traffic
					worst = minf(worst, absf(float(ta.along) - float(tb.along)) - float(ta.half) - float(tb.half))
	_check(worst > -0.05, "live street traffic never drives into the car in front (tightest gap %.2f m, %d stopped samples)" % [worst if worst < INF else 99.0, stopped])


## Three cars and a fast fourth up to the red at the spawn junction (always signalised), then
## green: they queue at the line, none crosses it, none overlaps, and they go on green.
func _red_and_green() -> void:
	var node := Vector2i(0, 0)
	_check(TrafficSignals.is_signal(_plan, node.x, node.y), "the spawn junction is signalised")
	_park_player_off_road()
	var cross_w := _plan.road_width(CityPlan.AXIS_Z, 0)
	var cross_pos := _plan.road_pos(CityPlan.AXIS_Z, 0)
	var line := cross_pos - cross_w * 0.5 - _traffic.stop_line_back
	TrafficSignals.force(_plan, node.x, node.y, CityPlan.AXIS_X, TrafficSignals.Light.RED, 0.5)
	var queue: Array[Vehicle] = []
	for k in 3:
		queue.append(_traffic.place_car(CityPlan.AXIS_X, 0, 1, 0, cross_pos - 32.0 - 12.0 * k, 9.0, false))
	# Behind the queue and much faster: it has to brake for the last car, not drive into it.
	var late := _traffic.place_car(CityPlan.AXIS_X, 0, 1, 0, cross_pos - 86.0, 16.0, false)
	queue.append(late)
	var over_line := false
	var worst := INF
	for i in 60 * 9:
		await _tree.physics_frame
		for k in queue.size():
			var t: Dictionary = queue[k].traffic
			if not t.has("along"):
				continue
			if float(t.along) + float(t.half) > line + 0.4:
				over_line = true
			if k > 0 and queue[k - 1].traffic.has("along"):
				var ahead: Dictionary = queue[k - 1].traffic
				worst = minf(worst, float(ahead.along) - float(t.along) - float(ahead.half) - float(t.half))
		if i > 120 and float(late.traffic.get("v", 1.0)) < 0.05 and float(queue[0].traffic.get("v", 1.0)) < 0.05:
			break
	var front: Dictionary = queue[0].traffic
	if not front.has("along"):
		_check(false, "the queue's cars are driven (offset %s, manager at %s, in tree %s, listed %s, keys %s)" % [_ws.world_offset, _traffic.position, queue[0].is_inside_tree(), _traffic.cars.has(queue[0]), front.keys()])
		_clear_traffic()
		return
	var all_stopped := true
	for car in queue:
		all_stopped = all_stopped and float(car.traffic.get("v", 1.0)) < 0.3
	_check(all_stopped and not over_line and float(front.along) + float(front.half) > line - 3.0,
		"a car stops at the red and the queue waits behind it (front nose %.1f m short of the line, over it %s)" % [line - float(front.along) - float(front.half), over_line])
	_check(worst > -0.05 and worst < 6.0, "a fast car does not drive through the stopped queue (tightest gap %.2f m)" % worst)
	TrafficSignals.force(_plan, node.x, node.y, CityPlan.AXIS_X, TrafficSignals.Light.GREEN, 0.2)
	var went := false
	for i in 60 * 6:
		await _tree.physics_frame
		if float(queue[0].traffic.get("along", -INF)) > cross_pos + 2.0:
			went = true
			break
	_check(went, "on green the front car drives on through the junction")
	_clear_traffic()


## A car with a green on the east-west road and somebody on its crosswalk stops short of it, and
## goes once they are across.
func _yield_to_walkers() -> void:
	var node := Vector2i(0, 0)
	var pos := _plan.road_pos(CityPlan.AXIS_X, 0)
	var cw := _plan.road_width(CityPlan.AXIS_X, 0)
	# The live crowd off this junction's crosswalks across the road, so the only walker the car
	# sees is the one this check puts there: a real one still crossing from the red before, or
	# stepping out later, is a correct reason to wait and made the "then goes" half flaky.
	for p in _tree.get_nodes_in_group("pedestrian"):
		var w := p as Pedestrian
		if w and w._cross != Pedestrian.Cross.NONE and w._cross_key.x == node.x and w._cross_key.y == node.y and w._cross_key.z == CityPlan.AXIS_Z:
			w.queue_free()
	await _ticks(1)
	TrafficSignals.force(_plan, node.x, node.y, CityPlan.AXIS_Z, TrafficSignals.Light.GREEN, 0.2)
	# Driving -x toward the junction from +x: its near crosswalk is on the +x side.
	var car := _traffic.place_car(CityPlan.AXIS_Z, 0, -1, 0, pos + 42.0, 9.0, false)
	var key := Vector4i(node.x, node.y, CityPlan.AXIS_Z, 1)
	var walkers: Dictionary = Pedestrian._crosswalks
	walkers[key] = int(walkers.get(key, 0)) + 1
	var line := pos + cw * 0.5 + _traffic.stop_line_back
	var over := false
	for i in 60 * 9:
		await _tree.physics_frame
		var t: Dictionary = car.traffic
		if t.has("along") and float(t.along) - float(t.half) < line - 0.4:
			over = true
		if i > 60 and float(t.get("v", 1.0)) < 0.05:
			break
	var held := float(car.traffic.get("v", 1.0)) < 0.3 and not over
	var held_at := float(car.traffic.get("along", INF))
	var n := int(walkers.get(key, 0)) - 1
	if n > 0:
		walkers[key] = n
	else:
		walkers.erase(key)
	TrafficSignals.force(_plan, node.x, node.y, CityPlan.AXIS_Z, TrafficSignals.Light.GREEN, 0.2)
	var went := false
	for i in 60 * 7:
		await _tree.physics_frame
		if float(car.traffic.get("along", INF)) < pos:
			went = true
			break
	var still_busy := Pedestrian.crosswalk_busy(node, CityPlan.AXIS_Z, 1) or Pedestrian.crosswalk_busy(node, CityPlan.AXIS_Z, -1)
	_check(held and went, "a car on green waits for somebody on its crosswalk, then goes (held %s at %.1f, over %s, went %s, line %.1f, crosswalks busy %s)" % [held, held_at, over, went, line, still_busy])
	_clear_traffic()


## A walker at the corner of the spawn block, told to cross the east-west road: waits at the kerb
## through the steady hand, steps out on the walking figure, and belongs to the next block after.
func _crossing() -> void:
	var node := Vector2i(0, 0)
	var chunk: Node3D = _city.chunks.get(Vector2i(0, 0))
	_check(chunk != null, "the spawn block's chunk is loaded for the crossing check")
	if chunk == null:
		return
	var rect: Rect2 = _plan.block(0, 0).rect
	var ped := Pedestrian.new()
	ped.setup(rect, _plan.sidewalk_width, 777)
	ped.walk_speed = 3.2
	ped.cross_chance = 0.0
	var start := rect.position + Vector2(2.5, 5.0)
	ped.position = Vector3(start.x, chunk.ground_y(start.x, start.y) + 0.1, start.y)
	chunk.add_child(ped)
	await _ticks(2)
	# Steady hand for walkers crossing the east-west road: its traffic has green.
	TrafficSignals.force(_plan, node.x, node.y, CityPlan.AXIS_Z, TrafficSignals.Light.GREEN, 0.5)
	var planned := ped.plan_crossing(CityPlan.AXIS_Z)
	var waited := false
	var stepped_on := -1
	var arrived := false
	var busy_seen := false
	for i in 60 * 12:
		await _tree.physics_frame
		if ped._cross == Pedestrian.Cross.WAIT and not waited:
			waited = true
			await _ticks(40)
			waited = ped._cross == Pedestrian.Cross.WAIT
			# The walking figure for them: the north-south traffic's green.
			TrafficSignals.force(_plan, node.x, node.y, CityPlan.AXIS_X, TrafficSignals.Light.GREEN, 0.2)
		if ped._cross == Pedestrian.Cross.CROSSING and stepped_on < 0:
			stepped_on = TrafficSignals.walk(_plan, node.x, node.y, CityPlan.AXIS_Z)
		busy_seen = busy_seen or Pedestrian.crosswalk_busy(node, CityPlan.AXIS_Z, ped._cross_key.w)
		if stepped_on >= 0 and ped._cross == Pedestrian.Cross.NONE:
			arrived = true
			break
	var next_rect: Rect2 = _plan.block(0, -1).rect
	var there: bool = ped.ring == next_rect and ped.position.z < _plan.road_pos(CityPlan.AXIS_Z, 0) - _plan.road_width(CityPlan.AXIS_Z, 0) * 0.5
	_check(planned and waited, "a walker heads for the crosswalk and waits at the kerb through the steady hand")
	_check(stepped_on == TrafficSignals.Walk.WALK and busy_seen, "they step out on the walking figure, and traffic can see them on the crosswalk")
	# This walker off the crosswalk's count: others from the live crowd may be on it.
	_check(arrived and there and not ped._on_crosswalk,
		"they cross to the next block and carry on along its pavement (arrived %s, at %s, state %d, down %s)" % [arrived, ped.position.round(), ped._cross, ped._down])
	ped.queue_free()


## One star, the player in the middle of a block: a cruiser joins out on the street, drives the
## streets (never off them) and pulls up at the kerb nearest the player, and the crew gets out.
func _police_route() -> void:
	var police: Node = _city.get_node_or_null("Police")
	if police == null:
		return
	var player := _tree.get_first_node_in_group("player") as Player
	if player.is_driving():
		player.exit_vehicle()
	var rect: Rect2 = _plan.block(0, 0).rect
	var mid := rect.get_center()
	player.global_position = _ws.to_local(Vector3(mid.x, 3.0, mid.y))
	player.velocity = Vector3.ZERO
	_city.update_streaming(true)
	await _ticks(20)
	var saved := {}
	for key in ["lose_seconds", "dispatch_interval", "first_dispatch_delay", "spawn_min", "spawn_max"]:
		saved[key] = police.get(key)
	police.set("lose_seconds", 60.0)
	police.set("first_dispatch_delay", 0.0)
	police.set("dispatch_interval", 30.0)
	police.set("spawn_min", 75.0)
	police.set("spawn_max", 100.0)
	police.call("clear")
	police.set("enabled", true)
	police.call("set_wanted", 1)
	var pw: Vector3 = _ws.to_world(player.global_position)
	var stop := StreetRoute.kerb_stop(_plan, Vector2(pw.x, pw.z), 13.0)
	var car: Node3D = null
	var samples := 0
	var off := 0
	var parked := false
	# 40 s: the cruiser drives the signalised lanes, and a red (green 16 s + amber + all-red for
	# the other axis) can hold it for over 20 s; the full suite reaches this check at a different
	# point in the signal cycle than a run of this file alone. The loop leaves once it is parked.
	for i in 60 * 40:
		await _tree.physics_frame
		if i % 20 == 0:
			police.call("report_sighting")
		var cars: Array = police.get("cruisers")
		if car == null and not cars.is_empty():
			car = cars[0]
		if car == null or not is_instance_valid(car):
			continue
		var cw: Vector3 = _ws.to_world(car.global_position)
		samples += 1
		if not _on_road(Vector2(cw.x, cw.z)):
			off += 1
		if int(car.get("mode")) == 3:
			parked = true
			break
	var gap := INF
	if car and is_instance_valid(car) and not stop.is_empty():
		var cw: Vector3 = _ws.to_world(car.global_position)
		gap = Vector2(cw.x, cw.z).distance_to(stop.stop)
	if gap >= 3.0 and car and is_instance_valid(car):
		# What stood in the way: the car's own goal against the test's, and every body near it.
		var cw: Vector3 = _ws.to_world(car.global_position)
		var near := ""
		for b in _tree.root.find_children("*", "PhysicsBody3D", true, false):
			if b != car and (b as Node3D).global_position.distance_to(car.global_position) < 9.0:
				near += " %s(%s)" % [b.name, str(_ws.to_world((b as Node3D).global_position).round())]
		printerr("police route: car at %s mode %d, its stop %s, the check's %s, player at %s; near:%s" % [str(cw.round()),
			int(car.get("mode")), str((car.get("_dest") as Dictionary).get("stop", "-")), str(stop.get("stop", "-")),
			str(_ws.to_world(player.global_position).round()), near])
	_check(parked and gap < 3.0 and samples > 30 and off == 0 and (police.get("officers") as Array).size() > 0,
		"a cruiser reaches a player mid-block by road and pulls up at the nearest kerb (%.1f m from it, %d of %d samples off the road)" % [gap, off, samples])
	police.call("clear")
	police.set("enabled", false)
	for key in saved:
		police.set(key, saved[key])
	await _ticks(2)


## True when world XZ `p` is on some road's carriageway (within half a metre of its kerbs).
func _on_road(p: Vector2) -> bool:
	for axis: int in [CityPlan.AXIS_X, CityPlan.AXIS_Z]:
		var across := p.x if axis == CityPlan.AXIS_X else p.y
		var i0 := _plan._index_at(axis, across)
		for index: int in [i0, i0 + 1]:
			if absf(across - _plan.road_pos(axis, index)) <= _plan.road_width(axis, index) * 0.5 + 0.5:
				return true
	return false


## The player stood on the spawn block's pavement, clear of every lane.
func _park_player_off_road() -> void:
	var player := _tree.get_first_node_in_group("player") as Player
	if player.is_driving():
		player.exit_vehicle()
	var rect: Rect2 = _plan.block(0, 0).rect
	var at := rect.position + Vector2(20.0, 2.0)
	player.global_position = _ws.to_local(Vector3(at.x, 3.0, at.y))
	player.velocity = Vector3.ZERO
	_city.update_streaming(true)
