extends RefCounted
## The fire station at night (the fire_station_night reference camera in
## tools/refcams/cameras_w8.json: StationExit, EmergencyWash, FireStation.setback), for
## tests/smoke_test.gd. Loaded at run time, not named there, so it compiles after the autoloads.
##
## Checks: the camera row is staged and looks at a station across its street; a station's face
## stands at most MAX_SETBACK back from its lot (FIRE_STATION_FRONT=0 the old apron); the path out
## of the bay starts inside the building on the bay floor and lands in the lane heading down it;
## the street traffic stops short of a station a unit is coming out of, both ways, and not past
## it or on another road; a unit sent out of the station starts in its bay and is on its lane by
## the end; the wash's red stays clear of AgX's salmon.

var _t: Object
var _city: Node


func run(t: Object, city: Node) -> void:
	_t = t
	_city = city
	var plan: CityPlan = city.get("plan")
	var st := _camera(plan)
	_setback()
	_stop_gap()
	_wash()
	if not st.is_empty():
		_path(plan, st)
		_live(plan, st)


func _camera(plan: CityPlan) -> Dictionary:
	var table: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tools/refcams/cameras_w8.json"))
	var row: Dictionary = {}
	for c: Dictionary in (table as Dictionary).get("cameras", []):
		if c.get("name", "") == "fire_station_night":
			row = c
	_t._check(not row.is_empty() and String(row.get("stage", "")) == "fire_station" and float(row.get("hour", 0.0)) == 21.0,
		"the fire_station_night camera row is staged and at 21:00")
	if row.is_empty() or plan == null:
		return {}
	var e: Array = row.eye
	var eye := Vector2(float(e[0]), float(e[2]))
	var st := FireStation.nearest(plan, eye, 120.0)
	_t._check(not st.is_empty(), "a fire station stands within 120 m of the fire_station_night eye")
	if st.is_empty():
		return {}
	var b := StationExit.bays(plan, st)
	var face: Vector2 = b.face
	var out: Vector2 = b.out
	var yaw := deg_to_rad(float(e[3]))
	var look := Vector2(-sin(yaw), -cos(yaw))
	_t._check((eye - face).dot(out) > 15.0 and look.dot((face - eye).normalized()) > 0.9,
		"the eye stands across the street from the bays and looks at them (%.1f m out, %.2f)" % [(eye - face).dot(out), look.dot((face - eye).normalized())])
	return st


func _setback() -> void:
	var was := FireStation.front_capped
	FireStation.front_capped = true
	_t._check(FireStation.setback(2.0, 3.0) == 5.0 and FireStation.setback(6.0, 30.0) == FireStation.MAX_SETBACK,
		"a station's face stands its apron back, at most %.1f m" % FireStation.MAX_SETBACK)
	FireStation.front_capped = false
	_t._check(FireStation.setback(6.0, 30.0) == 36.0, "FIRE_STATION_FRONT=0 keeps the old setback")
	FireStation.front_capped = was


func _path(plan: CityPlan, st: Dictionary) -> void:
	var b := StationExit.bays(plan, st)
	_t._check(float(b.to_kerb) <= FireStation.MAX_SETBACK + plan.sidewalk_width + 0.01 or not FireStation.front_capped,
		"the camera's station stands at the street (%.1f m face to kerb)" % float(b.to_kerb))
	var goal: Vector2 = (st.front as Vector2) + (st.frame.a as Vector2) * 200.0
	var start := FireStation.exit_lane(plan, st, goal)
	_t._check(start.size() > 4, "the station's street is open for a unit going out")
	if start.size() <= 4:
		return
	var axis := int(start[0])
	var dir := int(start[2])
	var lane := 2.0 * float(-dir if axis == CityPlan.AXIS_X else dir)
	var p := StationExit.path_for(plan, st, start, 10.0, lane, func(q: Vector2) -> float: return plan.macro.relief_at(q) if plan.macro else 0.0)
	var pts: PackedVector3Array = p.pts
	var face: Vector2 = b.face
	var out: Vector2 = b.out
	var p0 := Vector2(pts[0].x, pts[0].z)
	var pn := Vector2(pts[pts.size() - 1].x, pts[pts.size() - 1].z)
	_t._check((p0 - face).dot(out) < -5.0, "the unit starts inside its bay (%.1f m behind the face)" % (p0 - face).dot(out))
	var road := plan.road_pos(axis, int(start[1])) + lane
	var lat := pn.x if axis == CityPlan.AXIS_X else pn.y
	_t._check(absf(lat - road) < 0.15, "the path lands on the lane (%.2f m off)" % absf(lat - road))
	var yaws: PackedFloat32Array = p.yaws
	var want := EmergencyCar.heading(axis, dir)
	_t._check(absf(angle_difference(yaws[yaws.size() - 2], want)) < 0.12, "and heads down it (%.2f rad off)" % absf(angle_difference(yaws[yaws.size() - 2], want)))
	var dy := 0.0
	var dl := 0.0
	for i in range(1, pts.size()):
		dy = maxf(dy, absf(pts[i].y - pts[i - 1].y))
		dl = maxf(dl, Vector2(pts[i].x - pts[i - 1].x, pts[i].z - pts[i - 1].z).length())
	_t._check(dy < 0.08 and dl < 0.55 and pts[0].y > pts[pts.size() - 1].y - 0.5,
		"the path steps evenly from the bay floor down the ramp (steps %.2f m, rise %.3f m, %.2f -> %.2f)" % [dl, dy, pts[0].y, pts[pts.size() - 1].y])


func _stop_gap() -> void:
	var keep := StationExit.exiting.duplicate()
	StationExit.exiting.clear()
	var stub := Node.new() # stands in for the unit: valid, no exit, not an EmergencyCar
	StationExit.exiting.append([CityPlan.AXIS_Z, 7, 100.0, null])
	var a := StationExit.stop_gap(CityPlan.AXIS_Z, 7, 1, 60.0)
	var b := StationExit.stop_gap(CityPlan.AXIS_Z, 7, -1, 140.0)
	var past := StationExit.stop_gap(CityPlan.AXIS_Z, 7, 1, 130.0)
	StationExit.exiting.clear()
	StationExit.exiting.append([CityPlan.AXIS_Z, 7, 100.0, stub])
	var other := StationExit.stop_gap(CityPlan.AXIS_Z, 8, 1, 60.0)
	var held := StationExit.stop_gap(CityPlan.AXIS_Z, 7, 1, 60.0)
	_t._check(is_inf(a) and is_inf(b), "a station whose unit is gone stops nobody (%s %s)" % [a, b])
	_t._check(absf(held - 20.0) < 0.01 and is_inf(other) and is_inf(StationExit.stop_gap(CityPlan.AXIS_Z, 7, 1, 130.0)),
		"traffic stops %.0f m short of a station a unit is coming out of, not on another road or past it" % StationExit.STOP_SHORT)
	_t._check(absf(StationExit.stop_gap(CityPlan.AXIS_Z, 7, -1, 140.0) - 20.0) < 0.01, "both ways")
	_t._check(is_inf(past), "a car already past goes on")
	StationExit.exiting.clear()
	StationExit.exiting.append_array(keep)
	stub.free()


func _wash() -> void:
	var sh: Shader = load("res://shaders/engine_wash.gdshader")
	var code := sh.code
	_t._check(code.contains("fog_disabled") and code.contains("blend_add") and code.contains("cs_out("),
		"the wash is additive, fog-free and written through cs_out()")
	var m := ShaderMaterial.new()
	m.shader = sh
	var red: Vector3 = m.get_shader_parameter("red") if m.get_shader_parameter("red") != null else Vector3(4.0, 0.34, 0.20)
	_t._check(red.y < 0.1 * red.x and red.z < red.y, "the wash's red holds green at a tenth of red (%s)" % red)
	_t._check(code.contains("fract(TIME * rate + phase + side * 0.5 + end * 0.25)"),
		"the wash flashes on the lenses' own clock (emergency_lights.gdshader's pattern)")


## A unit really sent out of the station: in its bay at first, on its lane once the exit is done.
func _live(plan: CityPlan, st: Dictionary) -> void:
	var em := _city.get_node_or_null("Emergency") as Emergency
	_t._check(em != null, "the city has its Emergency node")
	if em == null:
		return
	var goal: Vector2 = (st.front as Vector2) + (st.frame.a as Vector2) * 220.0
	var inc := em.open_call(Emergency.KIND_FIRE, Vector3(goal.x, plan.height_at(goal), goal.y))
	var was := StationExit.enabled
	StationExit.enabled = true
	var car := em.send(EmergencyCar.Kind.ENGINE, inc)
	StationExit.enabled = was
	_t._check(car != null and car._exit != null, "a unit sent out of a station gets an exit")
	if car == null:
		em.incidents.erase(inc)
		return
	var b := StationExit.bays(plan, st)
	var w := WorldState.to_world(car.global_position)
	var behind := (Vector2(w.x, w.z) - (b.face as Vector2)).dot(b.out as Vector2)
	_t._check(behind < -2.0, "it starts in its bay (%.1f m behind the face)" % behind)
	var wch: Variant = car._exit.watch if car._exit != null else null
	_t._check(wch is StationWatch, "a firefighter goes out to stop the street")
	if wch is StationWatch:
		var sw := WorldState.to_world((wch as StationWatch).spot)
		var to_face := (Vector2(sw.x, sw.z) - (b.face as Vector2)).dot(b.out as Vector2)
		_t._check(to_face > float(b.to_kerb) - 1.5 and to_face < float(b.to_kerb), "standing at the kerb by the apron (%.1f m out of %.1f)" % [to_face, float(b.to_kerb)])
	_t._check(StationExit.stop_gap(int(st.road[0]), int(st.road[1]), 1, (st.front.y if int(st.road[0]) == CityPlan.AXIS_X else st.front.x) - 40.0) < INF,
		"the station's street is stopped while it comes out")
	car.set_physics_process(false)
	var dt := 1.0 / 60.0
	var ticks := 0
	while car._exit != null and ticks < 60 * 25:
		car._physics_process(dt)
		ticks += 1
	_t._check(car._exit == null, "the exit hands the unit to the lanes (%.1f s)" % (float(ticks) * dt))
	w = WorldState.to_world(car.global_position)
	var t: Dictionary = car.traffic
	var lat := w.x if int(t.axis) == CityPlan.AXIS_X else w.z
	_t._check(absf(lat - (plan.road_pos(int(t.axis), int(t.index)) + float(t.lane))) < 0.3, "standing in its lane")
	for i in 60 * 6:
		car._physics_process(dt)
	StationExit.prune()
	var still := false
	for e: Array in StationExit.exiting:
		if e[3] == car:
			still = true
	_t._check(not still, "and the street goes again once it is down the road")
	em.units.erase(car)
	em.incidents.erase(inc)
	if wch is StationWatch and is_instance_valid(wch):
		em.crews.erase(wch)
		(wch as Node).queue_free()
	car.queue_free()
