extends RefCounted
## Stages the valet stand nearest the camera for a still (tools/glshot/still_shot.gd
## VALET=drop|queue|back) and returns the EYE that frames it ("" if there is none within 160 m).
## Loaded at run time by the still script, so it may name the game's classes:
##   drop   a car at the drop-off on its hazards, its door open, the driver getting out and a
##          valet running round its tail to the door (VALET_T seconds into it, default 2.6)
##   queue  the same with two more cars queued behind it on their hazards
##   back   a car brought back: its valet out and walking to the podium, the guest coming out
## VALET_VIEW=kerb (default: on the pavement up the kerb, looking along the queue at the podium)
## or across (from the far pavement over the road). VALET_PICK=n takes the n-th nearest stand.

var _tree: SceneTree
var _ws: Node


func stage(scene: Node, kind: String, cam: Camera3D) -> String:
	_tree = scene.get_tree()
	_ws = _tree.root.get_node("/root/WorldState")
	var traffic := scene.get_node_or_null("Traffic") as TrafficManager
	if traffic == null or cam == null:
		return ""
	var cp: Vector3 = _ws.to_world(cam.global_position)
	var stands: Array = _tree.get_nodes_in_group("valet_stand").filter(func(n: Node) -> bool:
		return Vector2(cp.x, cp.z).distance_to((n as ValetStand).s.podium) < 160.0)
	stands.sort_custom(func(a: Node, b: Node) -> bool:
		return Vector2(cp.x, cp.z).distance_to((a as ValetStand).s.podium) < Vector2(cp.x, cp.z).distance_to((b as ValetStand).s.podium))
	var pick := int(OS.get_environment("VALET_PICK")) if OS.get_environment("VALET_PICK") != "" else 0
	if stands.size() <= pick:
		print("VALET: no stand within 160 m of the camera")
		return ""
	var stand := stands[pick] as ValetStand
	var s: Dictionary = stand.s
	traffic.staged = true
	stand.manual = true
	var tdir := int(s.tdir)
	var lanes := int(s.lanes)
	var plan: CityPlan = traffic.plan
	var width := plan.road_width(int(s.axis), int(s.index))
	var shift := 0.0 if bool(s.double) else CityPlan.parking_offset(width) - CityPlan.lane_center(width, lanes, lanes - 1)
	var cars: Array = []
	var gaps := [0.0, 6.9, 13.6] if kind == "queue" else [0.0]
	var valet: Valet = null
	for v: Variant in stand.valets:
		if is_instance_valid(v):
			valet = v
	for g: float in gaps:
		var car: Vehicle = traffic.place_car(int(s.axis), int(s.index), tdir, lanes - 1, float(s.stop_s) - float(tdir) * g, 0.0, false)
		car.traffic.shift = shift * (1.0 if g < 1.0 else 0.85)
		car.traffic.v = 0.0
		var back := kind == "back" and g < 1.0 and valet != null
		if back:
			valet.hide_in_car()
		stand.take(car, back, valet if back else null)
		cars.append(car)
	var secs := float(OS.get_environment("VALET_T")) if OS.get_environment("VALET_T") != "" else (2.6 if kind != "back" else 2.2)
	var ticks := int(secs * Engine.physics_ticks_per_second)
	var t0 := Engine.get_physics_frames()
	while Engine.get_physics_frames() - t0 < ticks + 30:
		await _tree.physics_frame
		if stand.front == null and Engine.get_physics_frames() - t0 > 30:
			# Not served yet: keep the clock from running before the car is at the drop-off.
			t0 += 1
	print("VALET stand %s %s serve=%d front=%s queue=%d" % [String(s.id), "hotel" if s.hotel else "restaurant", stand.serve, stand.front, stand.queue.size()])
	var pod: Vector2 = s.podium
	var trav: Vector2 = s.trav
	var o: Vector2 = s.out
	var view := OS.get_environment("VALET_VIEW")
	var eye: Vector2
	var look: Vector2
	var h := 1.75
	if view == "across":
		eye = pod + o * (Valets.PODIUM_IN + width + 2.5) + trav * 3.0
		look = pod + o * 1.5 - trav * 2.0
		h = 1.7
	else:
		eye = pod + o * (Valets.PODIUM_IN - 0.6) - trav * 15.0
		look = pod + o * 2.2 + trav * 1.0
		h = 2.1
	var chunk := stand.get_parent() as CityChunk
	var gy: float = chunk.ground_y(eye.x, eye.y) if chunk else 0.0
	var d := look - eye
	var yaw := rad_to_deg(atan2(-d.x, -d.y))
	var pitch := rad_to_deg(atan2(-1.0, d.length()))
	return "%.2f,%.2f,%.2f,%.1f,%.1f" % [eye.x, gy + h, eye.y, yaw, pitch]
