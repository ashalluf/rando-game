extends RefCounted
## A camera row's optional `hill_car` key (cameras_w8.json's switchback_night): an ordinary car
## standing on a hill road with its lamps lit (a driver in the cabin), so the frame holds a pair of
## headlights on the switchback's next leg whatever the traffic rolled (no traffic drives the hill
## roads). Loaded at run time by refcams_shot.gd (after the autoloads).
##
##   {"at": [x, z], "toward": [x, z], "seed": n}
## at / toward TRUE world points on the road: the car stands at `at` nosed toward `toward`, on the
## road's top found by a ray, pitched to the grade. `seed` picks the car (Vehicle.random_car on a
## generator of that seed). The log prints REFCAM hill_car lines.

static var _car: Node3D = null


static func stage(tree: SceneTree, scene: Node, row: Dictionary) -> void:
	var spec: Dictionary = row.get("hill_car", {}) if row.get("hill_car", null) is Dictionary else {}
	if spec.is_empty():
		return
	var at := Vector2(float(spec.at[0]), float(spec.at[1]))
	var to := Vector2(float(spec.toward[0]), float(spec.toward[1]))
	var dir := (to - at).normalized()
	var rng := RandomNumberGenerator.new()
	rng.seed = int(spec.get("seed", 7))
	var vehicle_script: GDScript = load("res://scripts/vehicles/vehicle.gd")
	var car: Node3D = vehicle_script.call("random_car", rng)
	# Placed, not driven: kinematic, with a traffic record nobody's loop drives ("parked": the foot
	# off the brake, so the tail lamps are not brake lamps), which also seats a driver.
	car.set("traffic", {"placed": true, "parked": true, "speed": 0.0, "v": 0.0})
	(car as RigidBody3D).freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	(car as RigidBody3D).freeze = true
	scene.add_child(car)
	await tree.process_frame
	var ws: Node = tree.root.get_node("/root/WorldState")
	var space := car.get_world_3d().direct_space_state
	var ys := []
	for k in [-2.0, 0.0, 2.0]:
		var p := at + dir * k
		var top: Vector3 = ws.call("to_local", Vector3(p.x, 400.0, p.y))
		var q := PhysicsRayQueryParameters3D.create(top, top + Vector3.DOWN * 500.0, 1)
		q.exclude = [(car as CollisionObject3D).get_rid()]
		var hit := space.intersect_ray(q)
		ys.append(float((ws.call("to_world", hit.position) as Vector3).y) if not hit.is_empty() else NAN)
	var y := float(ys[1])
	if is_nan(y):
		print("REFCAM hill_car: no ground under %s" % str(at))
		return
	var pitch := atan2(float(ys[2]) - float(ys[0]), 4.0) if not (is_nan(float(ys[0])) or is_nan(float(ys[2]))) else 0.0
	var yaw := atan2(-dir.x, -dir.y)
	# The hill road strip lies CanyonRoad.LIFT over the carved ground the ray hits.
	var lift := float(car.call("road_lift")) + 0.26
	car.global_transform = Transform3D(Basis.from_euler(Vector3(pitch, yaw, 0.0)), ws.call("to_local", Vector3(at.x, y + lift, at.y)))
	car.set("traffic_speed", 0.0)
	_car = car
	print("REFCAM hill_car: %s at %.1f,%.1f,%.1f yaw %.0f pitch %.1f lights %s" % [car.name, at.x, y + lift, at.y, rad_to_deg(yaw), rad_to_deg(pitch), str(car.call("lights_running"))])


static func unstage() -> void:
	if is_instance_valid(_car):
		_car.queue_free()
	_car = null
