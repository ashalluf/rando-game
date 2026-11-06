extends RefCounted
## Stages the real car cabin (CarInterior) for tools/glshot/still_shot.gd: CABIN_STAGE=<door>|in.
## The parked car with a cabin kit nearest the camera (an everyday body, not traffic) gets its rig;
##   * a number 0..1: the player stands at its driver's door (the car's left) with the door that far
##     open - getting in -, framed from the front quarter (CABIN_EYE=front|door|side);
##   * "in": the player is at the wheel and the passenger's door stands open, framed through it.
## Returns the EYE ("x,y,z,yaw,pitch", true world). Loaded at run time (after the autoloads).

static func stage(tree: SceneTree, env: String, cam: Camera3D) -> String:
	var ws := tree.root.get_node("/root/WorldState")
	var player := tree.get_first_node_in_group("player") as Node3D
	var from: Vector3 = cam.global_position
	var best: Vehicle = null
	var best_d := INF
	for n in tree.get_nodes_in_group("vehicle"):
		var c := n as Vehicle
		if c == null or not CarInteriors.supported(c) or c.is_traffic() or c.driver != null or c.is_wreck():
			continue
		if OS.get_environment("CABIN_TYPE") != "" and c.body_type != OS.get_environment("CABIN_TYPE").to_int():
			continue
		var d := c.global_position.distance_to(from)
		if d < best_d:
			best_d = d
			best = c
	if best == null:
		print("CABIN_STAGE: no parked everyday car near ", ws.to_world(from))
		return ""
	var car := best
	var inside := env == "in"
	var xf := car.global_transform
	var stand := xf * Vector3(-1.5, 0.0, -0.15)
	# On whatever is under that spot (the kerb, the pavement), found by a ray.
	var space := car.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(stand + Vector3.UP * 0.6, stand - Vector3.UP * 3.0, 1)
	var hit := space.intersect_ray(q)
	if not hit.is_empty():
		stand.y = (hit.position as Vector3).y
	player.global_position = stand + Vector3.UP * 0.05
	player.set("velocity", Vector3.ZERO)
	var rig: CarInterior = null
	for i in 900:
		var inst := CarInteriors.instance()
		if inst != null:
			rig = inst.activate(car)
		if rig != null:
			break
		await tree.physics_frame
	if rig == null:
		print("CABIN_STAGE: the rig never came up")
		return ""
	if inside:
		player.call("enter_vehicle", car)
		await tree.physics_frame
		while rig.busy():
			await tree.physics_frame
	for i in 40:
		await tree.physics_frame
	var amount := 0.75 if inside else clampf(env.to_float(), 0.0, 1.0)
	var d: Dictionary = rig.door(1.0 if inside else -1.0)
	if not d.is_empty():
		d.open = amount
		d.target = amount
		rig.tick(0.0)
	OS.set_environment("EYE_KEEP_PLAYER", "0" if inside else "1")
	var view := OS.get_environment("CABIN_EYE")
	var eye_local := Vector3(-4.3, 1.55, -3.4)
	var look_local := Vector3(-0.7, 0.85, -0.3)
	if inside:
		eye_local = Vector3(2.75, 1.35, 0.25)
		look_local = Vector3(-0.35, 0.92, -0.55)
	elif view == "door":
		eye_local = Vector3(-3.0, 1.4, 0.9)
		look_local = Vector3(-0.4, 0.8, -0.4)
	elif view == "side":
		eye_local = Vector3(-6.5, 1.7, -0.5)
		look_local = Vector3(0.0, 0.8, -0.2)
	var eye := xf * eye_local
	var dir := (xf * look_local - eye).normalized()
	var w: Vector3 = ws.to_world(eye)
	var out := "%.2f,%.2f,%.2f,%.2f,%.2f" % [w.x, w.y, w.z, rad_to_deg(atan2(-dir.x, -dir.z)), rad_to_deg(asin(dir.y))]
	print("CABIN_STAGE %s car %s type %d scheme %d at %s EYE=%s" % [env, car.name, car.body_type, rig.scheme, ws.to_world(car.global_position), out])
	return out
