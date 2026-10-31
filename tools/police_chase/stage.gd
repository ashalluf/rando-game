extends RefCounted
## The police chase staged in front of the camera for tools/glshot/still_shot.gd:
##   CHASE=box     a stopped car boxed in by three cruisers, the crews out behind their doors
##   CHASE=pit     a cruiser PITs a fast car (run live, then frozen as the car swings round)
##   CHASE=spikes  a car on a roadblock's spike strip, its tyres going, the roadblock beyond
##   CHASE=doors   a cruiser stopped facing the player, its officers behind the open doors
## Everything is laid out along the street the camera looks down (its nearest road on the axis it
## faces). Returns the EYE to shoot from ("x,y,z,yaw,pitch", true world). CHASE_LIVE seconds of
## play first (default per scene); CHASE_EYE=low|high|side picks another view.

var _scene: Node
var _police: Police
var _plan: CityPlan
var _tree: SceneTree
## The street frame: origin (true world XZ on the road's centre line level with the camera), along
## (unit, the way the camera looks), across (unit, to its right), the lane offset.
var _o: Vector2
var _u: Vector2
var _r: Vector2
var _lane: float = 1.9


func stage(tree: SceneTree, scene: Node, kind: String, cam: Camera3D) -> String:
	_tree = tree
	_scene = scene
	_police = scene.get_node_or_null("Police") as Police
	if _police == null or cam == null:
		return ""
	_police._ensure_refs()
	_plan = _police.plan
	var player := tree.get_first_node_in_group("player") as Player
	_frame(cam)
	_police.clear()
	_police.cruisers_per_star = PackedInt32Array([0, 0, 0, 0, 0, 0])
	_police.roadblock_stars = 99
	_police.lose_seconds = 1.0e6
	_police.accuracy_base = 0.0
	_police.enabled = true
	# The player stays where the scene puts him (on foot in view, or in his car): the free camera
	# would otherwise pull him to itself and every officer would turn to aim at the lens.
	OS.set_environment("EYE_KEEP_PLAYER", "1")
	var tm: Variant = scene.get_node_or_null("Traffic")
	if tm:
		tm.set("staged", true)
	match kind:
		"box":
			return await _box(player)
		"pit":
			return await _pit(player)
		"spikes":
			return await _spikes(player)
		_:
			return await _doors(player)


func _frame(cam: Camera3D) -> void:
	var w := WorldState.to_world(cam.global_position)
	var f := -cam.global_basis.z
	var along_z := absf(f.z) > absf(f.x)
	var axis := CityPlan.AXIS_X if along_z else CityPlan.AXIS_Z
	var coord := w.x if along_z else w.z
	var index := _plan._index_at(axis, coord)
	if absf(coord - _plan.road_pos(axis, index + 1)) < absf(coord - _plan.road_pos(axis, index)):
		index += 1
	var road := _plan.road_pos(axis, index)
	if along_z:
		_u = Vector2(0.0, signf(f.z))
		_o = Vector2(road, w.z)
	else:
		_u = Vector2(signf(f.x), 0.0)
		_o = Vector2(w.x, road)
	_r = Vector2(-_u.y, _u.x)
	_lane = CityPlan.lane_center(_plan.road_width(axis, index), 2, 0) * 0.9
	print("CHASE street axis %d index %d at %s along %s width %.1f" % [axis, index, str(_o), str(_u), _plan.road_width(axis, index)])


## True world point at `u` metres along and `x` across (right +).
func _at(u: float, x: float, y: float = 0.0) -> Vector3:
	var p := _o + _u * u + _r * x
	var h: float = _police.traffic._relief(p) if _police.traffic else 0.0
	return Vector3(p.x, h + y, p.y)


## Yaw that faces along the street turned by `turn` radians (to the left +).
func _yaw(turn: float = 0.0) -> float:
	return atan2(-_u.x, -_u.y) + turn


func _eye(u: float, x: float, y: float, look_u: float, look_x: float, look_y: float) -> String:
	var e := _at(u, x, y)
	var l := _at(look_u, look_x, look_y)
	var d := l - e
	var yaw := rad_to_deg(atan2(-d.x, -d.z))
	var pitch := rad_to_deg(atan2(d.y, Vector2(d.x, d.z).length()))
	return "%.2f,%.2f,%.2f,%.2f,%.2f" % [e.x, e.y, e.z, yaw, pitch]


func _car(at: Vector3, yaw: float, paint: Color) -> Vehicle:
	var car := Vehicle.new()
	car.setup(Vehicle.BodyType.SEDAN, paint, Vehicle.Addon.NONE)
	car.setup_look(Vehicle.Finish.GLOSS)
	_scene.add_child(car)
	car.global_transform = Transform3D(Basis(Vector3.UP, yaw), WorldState.to_local(at + Vector3.UP * 0.9))
	return car


func _cruiser(at: Vector3, yaw: float, kind: String) -> PoliceCar:
	return _police.spawn_cruiser(at + Vector3.UP * 0.9, yaw, kind)


func _ticks(n: int) -> void:
	for i in n:
		await _tree.physics_frame


func _frames(n: int) -> void:
	for i in n:
		await _tree.process_frame
		_police.report_sighting()


func _live(seconds: float) -> float:
	var s := float(OS.get_environment("CHASE_LIVE")) if OS.get_environment("CHASE_LIVE") != "" else seconds
	return s


func _box(player: Player) -> String:
	var mine := _car(_at(20.0, _lane), _yaw(0.12), Color(0.55, 0.04, 0.03))
	await _ticks(4)
	player.enter_vehicle(mine)
	_police.set_wanted(3)
	var a := _cruiser(_at(13.4, _lane - 0.6), _yaw(-0.25), "parked")
	var b := _cruiser(_at(26.6, _lane + 0.9), _yaw(PI - 0.45), "parked")
	var c := _cruiser(_at(19.0, _lane - 3.1), _yaw(0.5), "parked")
	await _frames(int(_live(4.0) / 0.133))
	var chase := PoliceChase.instance()
	if chase:
		chase.boxes += 1
	var v := OS.get_environment("CHASE_EYE")
	if v == "high":
		return _eye(4.0, -9.0, 9.0, 20.0, 0.0, 0.5)
	return _eye(6.0, -6.5, 2.1, 19.0, _lane, 0.9)


func _pit(player: Player) -> String:
	var mine := _car(_at(14.0, _lane), _yaw(), Color(0.08, 0.22, 0.5))
	var cop := _cruiser(_at(14.0 - 4.9, _lane - 2.6), _yaw(), "pursue")
	cop.mode = PoliceCar.Mode.PURSUE
	await _ticks(4)
	player.enter_vehicle(mine)
	_police.set_wanted(2)
	# The door he got in by swings shut before the run (CarInteriors holds it open a moment).
	await _ticks(100)
	var fwd := Vector3(_u.x, 0.0, _u.y)
	mine.linear_velocity = fwd * 17.0
	cop.linear_velocity = fwd * 18.0
	mine.hold_crash_watch(3)
	cop.hold_crash_watch(3)
	var chase := PoliceChase.instance()
	var spun_t := -1.0
	var t := 0.0
	var dt := 1.0 / 60.0
	for i in int(_live(5.0) * 60.0):
		await _tree.physics_frame
		t += dt
		if chase and chase.pits == 0:
			mine.linear_velocity = fwd * 17.0 + Vector3.UP * minf(mine.linear_velocity.y, 0.0)
		if chase and chase.pits == 0 and t > 0.4:
			chase._pit_cool = 0.0
			var lat := (cop.global_position - mine.global_position).dot(Vector3(_r.x, 0.0, _r.y))
			chase.roles[cop.get_instance_id()] = {"role": PoliceChase.Role.PIT, "side": signf(lat), "phase": 1, "t": 0.0}
		if chase and chase.pits > 0 and spun_t < 0.0:
			spun_t = t
		var after := float(OS.get_environment("CHASE_AFTER")) if OS.get_environment("CHASE_AFTER") != "" else 0.55
		if spun_t >= 0.0 and t - spun_t > after:
			break
	print("CHASE pit: %d pits, car turned %.0f deg" % [chase.pits if chase else -1, rad_to_deg(absf(wrapf(mine.rotation.y - _yaw(), -PI, PI)))])
	var at := WorldState.to_world(mine.global_position)
	var rel := Vector2(at.x, at.z) - _o
	var u := rel.dot(_u)
	var x := rel.dot(_r)
	return _eye(u - 13.0, x - 6.0, 2.4, u + 1.0, x, 0.6)


func _spikes(player: Player) -> String:
	_police.set_wanted(4)
	var cross := _yaw(PI * 0.5)
	_cruiser(_at(46.0, -2.7), cross, "roadblock")
	_cruiser(_at(46.0, 2.7), cross + PI, "roadblock")
	var mid := _o + _u * 46.0
	var axis := CityPlan.AXIS_X if absf(_u.y) > 0.5 else CityPlan.AXIS_Z
	var index := _plan._index_at(axis, mid.x if axis == CityPlan.AXIS_X else mid.y)
	if absf((mid.x if axis == CityPlan.AXIS_X else mid.y) - _plan.road_pos(axis, index + 1)) < absf((mid.x if axis == CityPlan.AXIS_X else mid.y) - _plan.road_pos(axis, index)):
		index += 1
	var travel := _u.y if axis == CityPlan.AXIS_X else _u.x
	var strip := PoliceChase.roadblock(_police, mid, axis, index, travel)
	var mine := _car(_at(14.0, _lane), _yaw(), Color(0.85, 0.85, 0.82))
	await _ticks(4)
	player.enter_vehicle(mine)
	await _ticks(100)
	mine.hold_crash_watch(3)
	var fwd := Vector3(_u.x, 0.0, _u.y)
	for i in int(_live(4.0) * 60.0):
		await _tree.physics_frame
		# Held at speed until it is on the strip (a staged car with nobody's foot down slows).
		if ChaseFlatTyres.flats(mine) == 0:
			mine.linear_velocity = fwd * 15.0 + Vector3.UP * minf(mine.linear_velocity.y, 0.0)
		if ChaseFlatTyres.flats(mine) >= 2 and i > 0:
			var after := float(OS.get_environment("CHASE_AFTER")) if OS.get_environment("CHASE_AFTER") != "" else 0.25
			await _ticks(int(after * 60.0))
			break
	print("CHASE spikes: %d flat, strip %.1f m" % [ChaseFlatTyres.flats(mine), strip.length if strip else -1.0])
	var at := WorldState.to_world(mine.global_position)
	var u := (Vector2(at.x, at.z) - _o).dot(_u)
	if OS.get_environment("CHASE_EYE") == "high":
		return _eye(u - 9.0, -5.0, 5.0, u + 12.0, 0.0, 0.3)
	return _eye(u - 3.5, _lane + 3.6, 0.9, u + 0.5, _lane - 0.3, 0.35)


func _doors(player: Player) -> String:
	player.global_position = WorldState.to_local(_at(0.0, 0.0, 0.3))
	player.velocity = Vector3.ZERO
	_police.set_wanted(2)
	var cop := _cruiser(_at(17.0, 0.5), _yaw(PI - 0.3), "parked")
	await _frames(int(_live(6.0) / 0.133))
	print("CHASE doors: %d officers, doors open %s" % [_police.officers.size(), str(PoliceChase.instance().door_cars.has(cop.get_instance_id()) if PoliceChase.instance() else false)])
	if OS.get_environment("CHASE_EYE") == "front":
		return _eye(9.0, 1.2, 1.5, 17.0, 0.5, 1.0)
	return _eye(23.0, -3.4, 1.45, 4.0, 1.2, 1.1)
