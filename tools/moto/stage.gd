extends RefCounted
## Stages motorcycles in front of the camera for a still (tools/glshot/still_shot.gd MOTO=...) and
## returns the EYE that frames it ("" keeps the player's own chase camera). Loaded at run time by
## the still script, so it may name the game's classes.
##   ride     the hero on a bike in the street where he stands (MOTO_TYPE 0 sport, 1 cruiser,
##            2 scooter), MOTO_LEAN rad into a turn, MOTO_WHEELIE rad nose up: the chase camera
##   throw    the same, then thrown off at MOTO_SPEED m/s: MOTO_FRAMES later, the body in the air
##   filter   a queue at the red of the junction ahead and a bike threading it between the lanes
##            (MOTO_FILTER_T seconds of it); EYE on the pavement behind
##   parked   the nearest stall of parked bikes (or a pair put at the nearest kerb); EYE beside it
##   riders   three bikes with their riders in the lane beside the camera; EYE on the pavement

var _tree: SceneTree
var _scene: Node
var _plan: CityPlan
var _traffic: TrafficManager
var _ws: Node


func _envf(key: String, fallback: float) -> float:
	var v := OS.get_environment(key)
	return float(v) if v != "" else fallback


func _ticks(n: int) -> void:
	for i in n:
		await _tree.physics_frame


func stage(tree: SceneTree, scene: Node, kind: String, cam: Camera3D) -> String:
	_tree = tree
	_scene = scene
	_plan = scene.get("plan")
	_traffic = scene.get_node_or_null("Traffic") as TrafficManager
	_ws = tree.root.get_node("/root/WorldState")
	if _plan == null or cam == null:
		print("MOTO: nothing to stage with")
		return ""
	var player := tree.get_first_node_in_group("player") as Player
	match kind:
		"ride", "throw":
			return await _ride(player, kind == "throw")
		"filter":
			return await _filter(cam)
		"parked":
			return await _parked(cam)
		"riders":
			return await _riders(cam)
	print("MOTO: unknown kind ", kind)
	return ""


func _ride(player: Player, throw: bool) -> String:
	if player == null:
		return ""
	var type: int = Motorcycle.TYPES[clampi(int(_envf("MOTO_TYPE", 0.0)), 0, 2)]
	var bike := Motorcycle.make(type, int(_envf("MOTO_LOOK", 3.0)))
	var rig := player.camera_rig
	var yaw: float = rig.global_rotation.y if rig else 0.0
	bike.transform = Transform3D(Basis(Vector3.UP, yaw), player.global_position + Vector3.UP * 0.4)
	_scene.add_child(bike)
	await _ticks(20)
	player.enter_vehicle(bike)
	bike.hold_pose = {"lean": _envf("MOTO_LEAN", 0.0), "wheelie": _envf("MOTO_WHEELIE", 0.0), "speed": _envf("MOTO_SPEED", 12.0), "steer": 0.0}
	await _ticks(10)
	if throw:
		bike.hold_pose = {}
		bike.linear_velocity = -bike.global_basis.z * _envf("MOTO_SPEED", 18.0)
		bike.throw_rider(Vector3.UP * 3.0)
		await _ticks(int(_envf("MOTO_FRAMES", 14.0)))
	print("MOTO ride %s at %s" % [bike.display_name(), str(_ws.to_world(bike.global_position))])
	return ""


func _filter(cam: Camera3D) -> String:
	if _traffic == null:
		return ""
	var cp: Vector3 = _ws.to_world(cam.global_position)
	var fwd := -cam.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var axis := 0 if absf(fwd.z) >= absf(fwd.x) else 1
	var dir := (1 if fwd.z > 0.0 else -1) if axis == 0 else (1 if fwd.x > 0.0 else -1)
	# The nearest road along the camera's heading with two lanes each way.
	var here := Vector2(cp.x, cp.z)
	var bi := _plan.block_index_at(here)
	var index := -99999
	for d in [0, 1, -1, 2, -2, 3, -3]:
		var i: int = (bi.x if axis == 0 else bi.y) + d
		if _plan.road_width(axis, i) > _plan.street_width + 1.0:
			index = i
			break
	if index == -99999:
		print("MOTO filter: no two-lane road near")
		return ""
	var cross := 1 - axis
	var along_cam := cp.z if axis == 0 else cp.x
	var k := _plan._index_at(cross, along_cam + float(dir) * 40.0) + (1 if dir > 0 else 0)
	var node := Vector2i(index, k) if axis == 0 else Vector2i(k, index)
	TrafficSignals.force(_plan, node.x, node.y, axis, TrafficSignals.Light.RED, 2.0)
	_traffic.staged = true
	for c in _traffic.cars.duplicate():
		if is_instance_valid(c) and int(c.traffic.get("axis", -1)) == axis and int(c.traffic.get("index", -99999)) == index:
			_traffic.cars.erase(c)
			_traffic._retire(c)
	var cross_pos := _plan.road_pos(cross, k)
	var line := cross_pos - float(dir) * (_plan.road_width(cross, k) * 0.5 + _traffic.stop_line_back)
	for lane_n in 2:
		var nose := line - float(dir) * 0.8
		for j in 4:
			var car := _traffic.place_car(axis, index, dir, lane_n, nose, 0.0, false)
			car.traffic.v = 0.0
			car.traffic_speed = 0.0
			var along := nose - float(dir) * float(car.traffic.half)
			_put(car, axis, index, along)
			nose = along - float(dir) * (float(car.traffic.rear) + 2.2)
	var bike_along := line - float(dir) * 44.0
	var bike := _traffic.place_car(axis, index, dir, 0, bike_along, 6.0, false, Motorcycle.TYPES[int(_envf("MOTO_TYPE", 0.0))])
	_put(bike, axis, index, bike_along)
	await _ticks(int(_envf("MOTO_FILTER_T", 4.5) * 60.0))
	var bp: Vector3 = _ws.to_world(bike.global_position)
	var back := Vector3(0.0, 0.0, -dir) if axis == 0 else Vector3(-dir, 0.0, 0.0)
	var side := Vector3(1.0, 0.0, 0.0) if axis == 0 else Vector3(0.0, 0.0, 1.0)
	var eye := bp + back * 7.5 + side * 2.2 * float(dir)
	var look := (bp - eye)
	look.y = 0.0
	var yaw := rad_to_deg(atan2(-look.x, -look.z))
	print("MOTO filter bike %s filtering %s shift %.2f" % [str(bp), str(bike.traffic.get("filtering", false)), float(bike.traffic.get("shift", 0.0))])
	OS.set_environment("EYE_AGL", "1")
	return "%.2f,%.2f,%.2f,%.2f,%.2f" % [eye.x, 1.9, eye.z, yaw, -8.0]


func _put(car: Vehicle, axis: int, index: int, along: float) -> void:
	var lane: float = car.traffic.lane
	var p2 := Vector2(_plan.road_pos(axis, index) + lane, along) if axis == 0 else Vector2(along, _plan.road_pos(axis, index) + lane)
	var h: float = _traffic._relief(p2)
	car.global_position = _ws.to_local(Vector3(p2.x, 0.1 + car.road_lift() + h, p2.y))
	car.traffic.along = along


func _parked(cam: Camera3D) -> String:
	await _ticks(10)
	var best: Motorcycle = null
	var bd := INF
	for n in _tree.get_nodes_in_group("motorcycle"):
		var m := n as Motorcycle
		if m == null or m.is_traffic() or m.driver != null:
			continue
		var d := m.global_position.distance_to(cam.global_position)
		if d < bd:
			bd = d
			best = m
	if best == null:
		print("MOTO parked: none near")
		return ""
	var bp: Vector3 = _ws.to_world(best.global_position)
	var right := best.global_basis.x
	var fwd := -best.global_basis.z
	var eye := bp + fwd * 3.2 + right * 2.6
	var look := bp - eye
	var yaw := rad_to_deg(atan2(-look.x, -look.z))
	print("MOTO parked %s at %s (%.0f m)" % [best.display_name(), str(bp), bd])
	OS.set_environment("EYE_AGL", "1")
	return "%.2f,%.2f,%.2f,%.2f,%.2f" % [eye.x, 1.5, eye.z, yaw, -14.0]


func _riders(cam: Camera3D) -> String:
	if _traffic == null:
		return ""
	var cp: Vector3 = _ws.to_world(cam.global_position)
	var fwd := -cam.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var axis := 0 if absf(fwd.z) >= absf(fwd.x) else 1
	var dir := (1 if fwd.z > 0.0 else -1) if axis == 0 else (1 if fwd.x > 0.0 else -1)
	var bi := _plan.block_index_at(Vector2(cp.x, cp.z))
	var index: int = bi.x if axis == 0 else bi.y
	_traffic.staged = true
	var start := (cp.z if axis == 0 else cp.x) + float(dir) * 12.0
	var last: Vehicle
	for j in 3:
		var along := start + float(dir) * 9.0 * float(j)
		last = _traffic.place_car(axis, index, dir, 1, along, 9.0, false, Motorcycle.TYPES[j])
		_put(last, axis, index, along)
	await _ticks(20)
	var bp: Vector3 = _ws.to_world(last.global_position)
	var side := Vector3(1.0, 0.0, 0.0) if axis == 0 else Vector3(0.0, 0.0, 1.0)
	var lane_sign := signf(float(last.traffic.lane))
	var back := Vector3(0.0, 0.0, -dir) if axis == 0 else Vector3(-dir, 0.0, 0.0)
	var eye := bp + side * lane_sign * 4.5 + back * 4.0
	var look := bp + back * 10.0 - eye
	var yaw := rad_to_deg(atan2(-look.x, -look.z))
	OS.set_environment("EYE_AGL", "1")
	return "%.2f,%.2f,%.2f,%.2f,%.2f" % [eye.x, 1.6, eye.z, yaw, -6.0]
