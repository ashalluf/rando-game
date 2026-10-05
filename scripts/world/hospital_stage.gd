class_name HospitalStage
extends RefCounted
## Stills of a hospital for tools/glshot/still_shot.gd (HOSPITAL=front|bay|roof|aerial): the
## hospital nearest the camera (the medical centre with HOSPITAL_AT=medical), and for `bay` an
## ambulance staged partway into its back-in path (Emergency's own unit, posed at once: a software
## frame takes seconds). Returns the EYE ("x,y,z,yaw,pitch", true world) that frames it, or "".

static func stage(tree: SceneTree, city: Node, scene: String, cam: Camera3D) -> String:
	var plan: CityPlan = city.get("plan")
	if plan == null:
		return ""
	var ws := tree.root.get_node("/root/WorldState")
	var cw: Vector3 = ws.to_world(cam.global_position)
	var lay: Dictionary
	var med := Hospital.medical_block(plan)
	if OS.get_environment("HOSPITAL_AT") == "medical" and med != Vector2i.MAX:
		lay = Hospital.layout(plan, med.x, med.y)
	else:
		lay = Hospital.nearest(plan, Vector2(cw.x, cw.z), 20000.0)
	if lay.is_empty():
		return ""
	if scene == "bay":
		var em := city.get_node_or_null("Emergency") as Emergency
		if em != null:
			_stage_ambulance(tree, em, plan, lay, float(OS.get_environment("HOSPITAL_T")) if OS.get_environment("HOSPITAL_T") != "" else 0.72)
	return eye_for(lay, scene)


## The EYE that frames `scene` of hospital `lay` (pure: the probe prints them).
static func eye_for(lay: Dictionary, scene: String) -> String:
	var gy: float = lay.floor_gy
	var y0 := gy + CityChunk.SIDEWALK_TOP
	var W: float = lay.W
	var D: float = lay.D
	var top := y0 + float(lay.podium_h) + float(lay.tower_h)
	var tower: Rect2 = lay.tower
	var tc := Hospital.fp(lay, tower.get_center().x, tower.get_center().y)
	match scene:
		"front":
			var e := Hospital.fp(lay, W * 0.5 - 18.0, -24.0)
			var t := Hospital.fp(lay, W * 0.5, 14.0)
			return _eye(Vector3(e.x, y0 + 1.7, e.y), Vector3(t.x, y0 + 16.0, t.y))
		"bay":
			var court: Rect2 = lay.court
			var canopy: Rect2 = lay.canopy
			var e := Hospital.fp(lay, W + 13.0, court.position.y - 9.0)
			var t := Hospital.fp(lay, court.position.x + 4.0, canopy.get_center().y + 3.0)
			return _eye(Vector3(e.x, gy + CityChunk.ROAD_TOP + 1.7, e.y), Vector3(t.x, y0 + 4.0, t.y))
		"roof":
			var e := tc + (lay.n as Vector2) * -36.0 + (lay.a as Vector2) * -26.0
			return _eye(Vector3(e.x, top + 30.0, e.y), Vector3(tc.x, top + 2.0, tc.y))
		_:
			var c := (lay.inner as Rect2).get_center()
			var e := c + (lay.n as Vector2) * -150.0 + (lay.a as Vector2) * -110.0
			return _eye(Vector3(e.x, y0 + 120.0, e.y), Vector3(c.x, y0 + 10.0, c.y))


## An ambulance `t` (0..1) of the way along its back-in path into bay 1, lights on, reversing.
static func _stage_ambulance(_tree: SceneTree, em: Emergency, plan: CityPlan, lay: Dictionary, t: float) -> void:
	em._ensure_refs()
	em.enabled = true
	var inc := em._open(Emergency.KIND_DOWN, Vector3.ZERO)
	inc.loaded = true
	inc.done = true
	var car := em._take(EmergencyCar.Kind.AMBULANCE)
	car.service = em
	car.incident = inc
	var stop := StreetRoute.kerb_stop(plan, Hospital.er_goal(lay), 0.0)
	var axis := int(stop.get("axis", CityPlan.AXIS_X))
	var index := int(stop.get("index", 0))
	var dir := int(stop.get("dir", 1))
	car.begin_drive(plan, axis, index, dir, 0.0)
	var road := plan.road_pos(axis, index) + float(stop.get("lateral", 0.0))
	var along := float(stop.get("along", 0.0))
	var p := Vector2(road, along) if axis == CityPlan.AXIS_X else Vector2(along, road)
	var dir2 := Vector2(0.0, dir) if axis == CityPlan.AXIS_X else Vector2(dir, 0.0)
	em._enter_at(car, Transform3D(Basis(Vector3.UP, EmergencyCar.heading(axis, dir)), WorldState.to_local(Vector3(p.x, 0.0, p.y))))
	em.units.append(car)
	car.hospital = lay
	car.crew_aboard = car.crew_alive
	car.bay = Hospital.take_bay(lay, car)
	car._back_path = Hospital.back_in_path(lay, car.bay, p, dir2)
	var total := 0.0
	for i in car._back_path.size() - 1:
		total += (car._back_path[i][0] as Vector2).distance_to(car._back_path[i + 1][0])
	car._back_s = total * t
	car.mode = EmergencyCar.Mode.BACKING
	car._back_in(0.0)


static func _eye(e: Vector3, look_at: Vector3) -> String:
	var d := look_at - e
	var yaw := rad_to_deg(atan2(-d.x, -d.z))
	var pitch := rad_to_deg(atan2(d.y, Vector2(d.x, d.z).length()))
	return "%.2f,%.2f,%.2f,%.2f,%.2f" % [e.x, e.y, e.z, yaw, pitch]
