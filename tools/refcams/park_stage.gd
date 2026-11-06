extends RefCounted
## A camera row's optional `park_car` (wave 6, car_closeup): one everyday car parked on a kerb, and
## the free eye placed round it in the car's own frame, so the view is "walking up to a parked car"
## whatever the load's own parked cars rolled.
##
##   "park_car": {"axis": "x" (a road of constant x, running along z) or "z", "at": the road's
##     coordinate (the nearest road there is taken), "along": the TRUE world coordinate down the road,
##     "side": +1 / -1 (which kerb; the car faces the traffic of its side), "type": a Vehicle.BodyType
##     name, "seed": where the look search starts, "eye": [x, y, z] in the car's frame (x right, y up
##     from the road, -z ahead of the nose), "look": [x, y, z] the point aimed at, same frame}
##
## The parked cars the city put within CLEAR m of the spot are freed first. Eye and look default
## to the camera row's own eye when the key is absent (rows without it stage nothing).

const CLEAR := 7.5

var car: Node3D = null
var eye_text := ""


func stage(tree: SceneTree, cam: Dictionary, scene: Node, plan: Variant) -> bool:
	var spec: Variant = cam.get("park_car")
	if not spec is Dictionary or plan == null:
		return false
	var axis := 0 if String(spec.get("axis", "x")) == "x" else 1  # CityPlan.AXIS_X / AXIS_Z
	var at := float(spec.get("at", 0.0))
	var probe := Vector2(at, 0.0) if axis == 0 else Vector2(0.0, at)
	var start: Vector2i = plan.block_index_at(probe)
	var i0 := start.x if axis == 0 else start.y
	var best := i0
	for i in range(i0 - 1, i0 + 3):
		if absf(float(plan.road_pos(axis, i)) - at) < absf(float(plan.road_pos(axis, best)) - at):
			best = i
	var side := 1.0 if float(spec.get("side", 1.0)) >= 0.0 else -1.0
	var plan_script: GDScript = plan.get_script()
	var off := float(plan_script.call("parking_offset", float(plan.road_width(axis, best))))
	var along := float(spec.get("along", 0.0))
	var road := float(plan.road_pos(axis, best)) + side * off
	var xz := Vector2(road, along) if axis == 0 else Vector2(along, road)
	var ground := float(plan.height_at(xz))
	# Right-hand traffic: on a road along z the +x kerb's cars face -z (north), the -x kerb's +z.
	var yaw := (0.0 if side > 0.0 else PI) if axis == 0 else (-PI * 0.5 if side > 0.0 else PI * 0.5)
	var world_state := tree.root.get_node_or_null("/root/WorldState")
	var offset: Vector3 = world_state.get("world_offset") if world_state else Vector3.ZERO
	var spot := Vector3(xz.x, ground, xz.y)
	# Free the parked cars round the spot (the city's own, never the traffic's).
	for v in tree.get_nodes_in_group("vehicle"):
		var n := v as Node3D
		if n == null or not is_instance_valid(n):
			continue
		var t: Variant = n.get("traffic")
		if t is Dictionary and not (t as Dictionary).is_empty():
			continue
		if (n.global_position + offset - spot).length() < CLEAR:
			n.queue_free()
	# The car: random_car() from a seeded generator, walked on until the body type matches.
	var want := String(spec.get("type", "CROSSOVER"))
	var vehicle_script: GDScript = load("res://scripts/vehicles/vehicle.gd")
	var types: Dictionary = vehicle_script.get_script_constant_map().get("BodyType", {})
	var want_type := int(types.get(want, 8))
	var s := int(spec.get("seed", 1))
	for k in 400:
		var rng := RandomNumberGenerator.new()
		rng.seed = s + k
		var c: Node3D = vehicle_script.call("random_car", rng)
		if int(c.get("body_type")) == want_type and int(c.get("livery")) == 0:
			car = c
			print("REFCAM park_car: %s from seed %d" % [want, s + k])
			break
		c.free()
	if car == null:
		push_error("refcams: no %s in 400 seeds" % want)
		return false
	car.name = "RefcamParked"
	var basis := Basis(Vector3.UP, yaw)
	car.position = spot + Vector3(0.0, 0.3, 0.0) - offset
	car.rotation.y = yaw
	scene.add_child(car)
	# The eye in the car's frame.
	var e: Array = spec.get("eye", [2.0, 1.5, -3.8])
	var l: Array = spec.get("look", [0.0, 0.6, -0.6])
	var eye := spot + basis * Vector3(float(e[0]), float(e[1]), float(e[2]))
	var look := spot + basis * Vector3(float(l[0]), float(l[1]), float(l[2]))
	var d := (look - eye).normalized()
	var cam_yaw := rad_to_deg(atan2(-d.x, -d.z))
	var cam_pitch := rad_to_deg(asin(clampf(d.y, -1.0, 1.0)))
	eye_text = "%.3f,%.3f,%.3f,%.3f,%.3f" % [eye.x, eye.y, eye.z, cam_yaw, cam_pitch]
	OS.set_environment("EYE", eye_text)
	print("REFCAM park_car: road %d (axis %d) kerb %.1f along %.1f, eye %s" % [best, axis, road, along, eye_text])
	return true


## Pedestrians standing in the lens (within `reach` of the eye) are hidden for the shot.
func clear_people(tree: SceneTree, eye: Vector3, reach: float = 2.5) -> void:
	for p in tree.get_nodes_in_group("pedestrian"):
		var n := p as Node3D
		if n and n.global_position.distance_to(eye) < reach:
			n.visible = false


func finish() -> void:
	if car and is_instance_valid(car):
		car.queue_free()
	car = null
