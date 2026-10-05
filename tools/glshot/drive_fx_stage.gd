extends RefCounted
## DRIVE=burnout|drift|donut|scrape|sand on tools/glshot/still_shot.gd: a car driven badly in front
## of the camera so DrivingFX has something to show (skid marks, tyre smoke, sparks, sand spray).
## The car goes DRIVE_DIST metres ahead of the camera (default 14) and DRIVE_SIDE to its right,
## on the ground under that point, heading DRIVE_YAW degrees from the camera's view (default 90:
## across the frame left to right), and is driven for DRIVE_TIME seconds of game time:
##   burnout - the player at the wheel, full throttle against the handbrake: rear smoke, rubber.
##   drift   - sliding round an arc of DRIVE_RADIUS m (default 22) at DRIVE_SPEED m/s (14), the body
##             DRIVE_ANGLE degrees (35) off its path: smoke and two arcs of marks behind.
##   donut   - the same, tighter (radius 6, 9 m/s, 60 degrees): a ring of rubber.
##   scrape  - on its roof, sliding at DRIVE_SPEED: sparks, the grind (shoot it at night).
##   sand    - driving straight at DRIVE_SPEED with a little slide: sand spray and tracks (on a beach).
## Loaded, not named, by still_shot.gd (it compiles before the autoloads); this one names Vehicle
## freely because it is loaded after they exist.

static func stage(tree: SceneTree, kind: String, cam: Camera3D) -> void:
	var player := tree.get_first_node_in_group("player") as Player
	var scene: Node = tree.current_scene if tree.current_scene else player.get_parent()
	var fwd := -cam.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var right := fwd.cross(Vector3.UP)
	var dist := _f("DRIVE_DIST", 14.0)
	var at := cam.global_position + fwd * dist + right * _f("DRIVE_SIDE", 0.0)
	var space := cam.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 60.0, at - Vector3.UP * 200.0, 1)
	var hit := space.intersect_ray(q)
	if not hit.is_empty():
		at = hit.position
	var dfx: Node = DrivingFX.instance()
	print("DRIVE ground under %s: %s, zone %s" % [at, hit.get("collider"), dfx.call("_zone_at", at) if dfx else "?"])
	var heading := fwd.rotated(Vector3.UP, -deg_to_rad(_f("DRIVE_YAW", 90.0)))
	var rng := RandomNumberGenerator.new()
	rng.seed = int(_f("DRIVE_SEED", 7.0))
	var car := Vehicle.new()
	var body := int(_f("DRIVE_BODY", float(Vehicle.BodyType.SPORTS)))
	car.setup(body, Vehicle.PAINTS[rng.randi() % Vehicle.PAINTS.size()] if _f("DRIVE_PAINT", -1.0) < 0.0 else Vehicle.PAINTS[int(_f("DRIVE_PAINT", 0.0))], Vehicle.Addon.NONE)
	var flip := kind == "scrape"
	scene.add_child(car)
	car.global_transform = Transform3D(Basis.looking_at(heading, Vector3.UP), at + Vector3.UP * (2.2 if flip else 0.9))
	if flip:
		car.global_transform.basis = car.global_basis * Basis(Vector3.BACK, PI)
	for i in 30:
		car.hold_crash_watch(3)
		await tree.physics_frame
	var fx: Node = DrivingFX.instance()
	print("DRIVE %s car %s at %s (world %s), DrivingFX %s" % [kind, car.display_name(), car.global_position,
			WorldState.to_world(car.global_position), fx != null])
	var time := _f("DRIVE_TIME", 2.2)
	var speed := _f("DRIVE_SPEED", 9.0 if kind == "donut" else 14.0)
	var radius := _f("DRIVE_RADIUS", 6.0 if kind == "donut" else 22.0)
	var angle := deg_to_rad(_f("DRIVE_ANGLE", 60.0 if kind == "donut" else 35.0))
	Engine.time_scale = 1.0
	if kind == "burnout":
		player.enter_vehicle(car)
		Input.action_press("move_forward")
		Input.action_press("alt_fire")
	var travel := heading
	var elapsed := 0.0
	# Turning left round the arc: the nose points into the turn, past the way the car is going.
	if kind == "drift" or kind == "donut":
		car.global_basis = Basis.looking_at(travel.rotated(Vector3.UP, angle), Vector3.UP)
	while elapsed < time:
		var dt := 1.0 / float(Engine.physics_ticks_per_second)
		car.hold_crash_watch(3)
		match kind:
			"burnout":
				# A brake stand: the handbrake does not hold a car against full throttle here.
				car.linear_velocity = Vector3(car.linear_velocity.x * 0.2, car.linear_velocity.y, car.linear_velocity.z * 0.2)
			"drift", "donut":
				travel = travel.rotated(Vector3.UP, speed / radius * dt)
				car.linear_velocity = Vector3(travel.x * speed, car.linear_velocity.y, travel.z * speed)
				car.angular_velocity = Vector3(0.0, speed / radius, 0.0)
			"scrape":
				car.linear_velocity = Vector3(travel.x * speed, car.linear_velocity.y, travel.z * speed)
			"sand":
				var v := travel * speed + car.global_basis.x * 2.5
				car.linear_velocity = Vector3(v.x, car.linear_velocity.y, v.z)
		await tree.physics_frame
		elapsed += dt
	if kind == "burnout":
		# Keep the throttle on through the frozen frames: the smoke keeps coming.
		pass
	print("DRIVE done: marks %d, smoke %d, dust %d, sparks %d; car now %s" % [int(fx.call("marks_alive")) if fx else -1,
			int(fx.get("last_smoke")) if fx else -1, int(fx.get("last_dust")) if fx else -1, int(fx.get("last_sparks")) if fx else -1,
			WorldState.to_world(car.global_position)])


static func _f(key: String, fallback: float) -> float:
	var v := OS.get_environment(key)
	return float(v) if v != "" else fallback
