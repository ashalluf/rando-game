extends RefCounted
## The "fire_station_night" reference camera's staging (tools/refcams/cameras_w8.json, `"stage":
## "fire_station"`): an engine of the city's own Emergency service going out of the station nearest
## the eye on a call, its bay doors up, a few street cars on the station's road reacting to it.
## The call is opened by hand `call_ahead` metres down the station's street (Emergency.open_call),
## the engine sent through the ordinary Emergency.send() (FireStation.exit_lane, the doors), and
## then the engine and the street traffic are STEPPED `t` seconds at 60 Hz by hand (a software
## frame is seconds long; stepped, the moment in the frame is the same every run): the engine's
## own _physics_process and TrafficAI.advance_shot() for the cars. Loaded at run time by
## refcams_shot.gd (after the autoloads), so it may name Emergency, FireStation and TrafficAI.
##
##   "fire_station": {"t": seconds after the dispatch (default 4.0), "call_ahead": metres down the
##     street to the call, +x along the station's frame (default 260), "cars": [[ahead, dir, lane,
##     speed], ...] street cars placed on the station's road, `ahead` metres along the frame's +a
##     from the bays' centre}
##
## Env FS_T overrides `t` for framing work.

static var hero_at := Vector3.INF
static var hero_yaw := 0.0
static var _car: Node = null
static var _em: Node = null
static var _tm: Node = null
static var _was_enabled := true
static var _placed: Array = []


static func stage(tree: SceneTree, scene: Node, cam: Camera3D, _player: Node3D, place: Callable, row: Dictionary = {}) -> void:
	var spec: Dictionary = row.get("fire_station", {}) if row.get("fire_station", null) is Dictionary else {}
	var t := float(spec.get("t", 4.0))
	if OS.get_environment("FS_T") != "":
		t = float(OS.get_environment("FS_T"))
	var plan: CityPlan = scene.get("plan")
	var em := scene.get_node_or_null("Emergency") as Emergency
	var tm := scene.get_node_or_null("Traffic") as TrafficManager
	if em == null or plan == null:
		push_warning("refcams fire_station: no Emergency")
		return
	var eye := WorldState.to_world(cam.global_position)
	var st := FireStation.nearest(plan, Vector2(eye.x, eye.z), 120.0)
	if st.is_empty():
		push_warning("refcams fire_station: no station within 120 m of the eye")
		return
	_em = em
	_tm = tm
	_was_enabled = em.enabled
	em.enabled = true
	em.call("_ensure_refs")
	var f: Dictionary = st.frame
	var a2: Vector2 = f.a
	var front: Vector2 = st.front
	var call_at := front + a2 * float(spec.get("call_ahead", 260.0))
	var axis := int(st.road[0])
	var index := int(st.road[1])
	# The traffic on the station's street, placed before the engine comes out (it sees them).
	if tm:
		tm.staged = true
		var front_along := front.y if axis == CityPlan.AXIS_X else front.x
		var a_sign := (a2.y if axis == CityPlan.AXIS_X else a2.x)
		for c: Array in spec.get("cars", []):
			var car := tm.place_car(axis, index, int(c[1]), int(c[2]), front_along + float(c[0]) * a_sign, float(c[3]))
			if car:
				_placed.append(car)
	var inc := em.open_call(Emergency.KIND_FIRE, Vector3(call_at.x, plan.height_at(call_at), call_at.y))
	var car := em.send(EmergencyCar.Kind.ENGINE, inc)
	if car == null:
		push_warning("refcams fire_station: the engine was not sent")
		return
	inc["engine"] = car
	_car = car
	# Nothing else answers a call or moves the engine while the shot is held.
	em.enabled = false
	await tree.physics_frame
	var dt := 1.0 / 60.0
	for i in int(round(t / dt)):
		if is_instance_valid(car):
			car._physics_process(dt)
		if tm:
			TrafficAI.advance_shot(tm, dt)
	# The firefighter stopping the street stands at the kerb by now (StationWatch walks there in a
	# few seconds of the game's own physics, which the stepping above does not run).
	var ex: Variant = car.get("_exit") if is_instance_valid(car) else null
	if ex != null and is_instance_valid(ex.watch):
		var wch: Node3D = ex.watch
		wch.global_position = wch.get("spot")
		var lk: Vector3 = (wch.get("look") as Vector3) - wch.global_position
		var vis: Node3D = wch.get("_visual")
		if vis:
			vis.rotation.y = atan2(-lk.x, -lk.z)
	if is_instance_valid(car):
		# Held where the stepping left it: its lights (and wash) set up once, then nothing moves it
		# (PhysicsBudget would switch its physics back on).
		car._process(0.6)
		car._process(0.6)
		car.process_mode = Node.PROCESS_MODE_DISABLED
	# The bay doors all the way up (their tween runs on the scaled clock the shot all but stops).
	for node in tree.get_nodes_in_group("fire_station"):
		var n := node as Node3D
		if n and n.get_meta("cell", Vector2i(-99999, -99999)) == st.cell:
			for child in n.get_children():
				if String(child.name).begins_with("BayDoor"):
					var tw: Variant = child.get_meta("door_tween", null)
					if tw is Tween and (tw as Tween).is_valid():
						(tw as Tween).kill()
					(child as Node3D).position.y = FireStation.BAY_DOOR.y - 0.35
			FireStationNight.show_spill(n, true)
	for i in 6:
		await tree.process_frame
		place.call()
	if car is Node3D:
		var w := WorldState.to_world((car as Node3D).global_position)
		print("REFCAM fire_station_night: station %d front (%.1f, %.1f), engine at (%.1f, %.1f, %.1f) speed %.1f, %d cars placed" % [
				int(st.number), front.x, front.y, w.x, w.y, w.z, float(car.get("traffic_speed")), _placed.size()])
		for p in _placed:
			if is_instance_valid(p):
				var pw := WorldState.to_world((p as Node3D).global_position)
				var tr: Dictionary = p.get("traffic")
				print("REFCAM fire_station_night:   car at (%.1f, %.1f) speed %.1f shift %.2f" % [pw.x, pw.z, float(p.get("traffic_speed")), float(tr.get("shift", 0.0))])


static func unstage() -> void:
	if is_instance_valid(_em):
		if is_instance_valid(_car):
			(_em.get("units") as Array).erase(_car)
		_em.set("enabled", _was_enabled)
	if is_instance_valid(_car):
		_car.queue_free()
	_car = null
	if is_instance_valid(_tm):
		_tm.set("staged", false)
	_placed.clear()
