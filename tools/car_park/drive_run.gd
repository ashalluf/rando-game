extends RefCounted
## The body of tools/car_park/drive_shot.gd (loaded once the autoloads exist).

var tree: SceneTree
var cam: Camera3D
var out_dir: String
var prefix: String
var n_shot: int = 0


func run(t: SceneTree) -> void:
	tree = t
	out_dir = OS.get_environment("OUT_DIR") if OS.get_environment("OUT_DIR") != "" else "build/carpark"
	prefix = OS.get_environment("PREFIX")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://" + out_dir) if not out_dir.begins_with("/") else out_dir)
	var city: Node = tree.current_scene
	var ws: Node = tree.root.get_node("/root/WorldState")
	var plan: CityPlan = city.get("plan")
	var cpv := OS.get_environment("CP").split(",")
	var cp := Vector2(cpv[0].to_float(), cpv[1].to_float()) if cpv.size() >= 2 else Vector2.ZERO
	var s := CarPark.nearest(plan, cp, 400.0)
	if s.is_empty():
		push_error("drive_shot: no car park near %s" % cp)
		return
	print("DRIVE car park %s at %s, %d decks" % [s.name, (s.site as Rect2).get_center(), int(s.layout.decks)])
	var player := tree.get_first_node_in_group("player") as Player
	var path: PackedVector3Array = load("res://tools/car_park/autopilot.gd").local_path(plan, s, ws, int(OS.get_environment("TO_DECK")) if OS.get_environment("TO_DECK") != "" else -1)
	# Stream round the car park and wait for its node.
	player.global_position = path[0] + Vector3.UP * 1.5
	player.velocity = Vector3.ZERO
	var cp_node: Node3D = null
	for i in 400:
		city.call("update_streaming", true)
		await tree.process_frame
		for n in tree.get_nodes_in_group("car_park"):
			cp_node = n
		if cp_node and i > 30:
			break
	print("DRIVE node %s, build %.1f ms" % [cp_node, float(cp_node.get_meta("build_us", 0)) / 1000.0 if cp_node else -1.0])
	cam = Camera3D.new()
	cam.name = "DriveCamera"
	var pc := tree.root.get_camera_3d()
	tree.root.add_child(cam)
	if pc:
		cam.attributes = pc.attributes
		cam.far = pc.far
	cam.near = 0.05
	cam.fov = 62.0
	cam.make_current()
	var lay: Dictionary = s.layout
	var xf := CarParkBuild.frame_xform(plan, s)
	var local_xf := Transform3D(xf.basis, ws.call("to_local", xf.origin))
	# 1. The structure from across the street.
	var across := local_xf * Vector3(float(lay.ls) * 0.72, 1.7, -plan.sidewalk_width * 2.0 - plan.road_width(int(s.road[0]), int(s.road[1])) - 3.0)
	_aim(across, local_xf * Vector3(float(lay.ls) * 0.42, float(lay.height) * 0.42, 6.0), 60.0)
	await _shot("exterior")
	if OS.get_environment("NO_DRIVE") == "1":
		return
	# The car, on the road in front, facing the way the path goes.
	var car := Vehicle.new()
	car.setup(int(OS.get_environment("BODY")) if OS.get_environment("BODY") != "" else Vehicle.BodyType.SEDAN, Color(0.55, 0.05, 0.05), Vehicle.Addon.NONE)
	city.add_child(car)
	var d0 := path[1] - path[0]
	d0.y = 0.0
	car.global_transform = Transform3D(Basis.looking_at(d0.normalized(), Vector3.UP), path[0] + Vector3.UP * 0.6)
	for i in 30:
		car.hold_crash_watch(3)
		await tree.physics_frame
	player.enter_vehicle(car)
	var ap = load("res://tools/car_park/autopilot.gd").new()
	ap.setup(path)
	var decks := int(lay.decks)
	var gy0: float = (ws.call("to_local", Vector3(0.0, CarPark.ground_y(plan, s), 0.0)) as Vector3).y
	# Shots by where the car has got to on the path (index) or how high it is.
	var shots := [[5, "barrier", "side"], [9, "ramp_up", "chase"], [13, "deck2", "chase"], [path.size() - 6, "top_ramp", "chase"],
		[path.size() - 1, "roof", "roof"]]
	var next := 0
	Engine.max_physics_steps_per_frame = 24
	tree.root.disable_3d = true
	var t := 0.0
	var stuck_t := 0.0
	var last := car.global_position
	while t < 400.0:
		var arrived: bool = ap.step(car)
		await tree.physics_frame
		t += 1.0 / float(Engine.physics_ticks_per_second)
		if car.global_position.distance_to(last) > 2.0:
			last = car.global_position
			stuck_t = 0.0
		else:
			stuck_t += 1.0 / float(Engine.physics_ticks_per_second)
		if stuck_t > 20.0:
			print("DRIVE blocker: ", ap.blocker(car))
			await _car_shot(car, "stuck", "side", local_xf, lay)
			print("DRIVE stuck at path index %d, %s (deck height %.2f)" % [ap.i, ws.call("to_world", car.global_position), car.global_position.y - gy0])
			break
		if next < shots.size() and (ap.reached >= int(shots[next][0]) or arrived):
			ap.release()
			await _car_shot(car, String(shots[next][1]), String(shots[next][2]), local_xf, lay)
			next += 1
		if arrived and next >= shots.size():
			break
	ap.release()
	print("DRIVE done in %.0f s of game time: index %d of %d, height over the ground deck %.2f (roof %.2f)" % [t, ap.reached, path.size() - 1,
			car.global_position.y - gy0, CarPark.FLOOR * float(decks)])


## A still with the clock stopped, from the car.
func _car_shot(car: Node3D, name: String, kind: String, local_xf: Transform3D, lay: Dictionary) -> void:
	var fwd := -car.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var right := fwd.cross(Vector3.UP)
	var p := car.global_position
	match kind:
		"side":
			_aim(p - fwd * 4.5 + right * 4.0 + Vector3.UP * 1.5, p + fwd * 3.0 + Vector3.UP * 0.8, 66.0)
		"roof":
			_aim(p - fwd * 9.0 + right * 3.0 + Vector3.UP * 3.2, p + fwd * 4.0, 64.0)
		_:
			_aim(p - fwd * 6.2 + Vector3.UP * 1.65, p + fwd * 3.0 + Vector3.UP * 0.6, 68.0)
	await _shot(name)


func _aim(eye: Vector3, at: Vector3, fov: float) -> void:
	cam.global_transform = Transform3D(Basis.looking_at((at - eye).normalized(), Vector3.UP), eye)
	cam.fov = fov


func _shot(name: String) -> void:
	var ts := Engine.time_scale
	Engine.time_scale = 0.0005
	tree.root.disable_3d = false
	for i in int(OS.get_environment("SETTLE")) if OS.get_environment("SETTLE") != "" else 8:
		await tree.process_frame
	var img := tree.root.get_texture().get_image()
	var path := "%s/%s%02d_%s.jpg" % [out_dir, prefix, n_shot, name]
	if not path.begins_with("/"):
		path = ProjectSettings.globalize_path("res://" + path)
	img.save_jpg(path, 0.9)
	print("DRIVE shot ", path)
	n_shot += 1
	tree.root.disable_3d = true
	Engine.time_scale = ts
