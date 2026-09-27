extends SceneTree
## Close-ups of one car on a bare ground plane, from any camera, by day or at night - the fast
## loop for styling a body model (twenty seconds a shot; the city takes minutes).
##
##   OUT=sedan.png LIBGL_ALWAYS_SOFTWARE=1 xvfb-run -a -s "-screen 0 1280x720x24" \
##     godot --rendering-driver opengl3 --display-driver x11 --audio-driver Dummy --path . \
##     --script tools/glshot/sedan_shot.gd --resolution 1280x720 -- --view=front3
##
## `--type=N` body type (0 sedan), `--view` front3 / rear3 / side / front / rear / top, or
## `--cam=x,y,z --look=x,y,z` (the car's nose points -Z, its centre is the origin), `--fov=`,
## `--paint=#rrggbb`, `--police` (the cruiser), `--night` (lamps lit, beams on the road).
## Nothing here may name Vehicle or PoliceCar as a TYPE: this script is compiled before the
## autoloads exist (CLAUDE.md).

func _vec(s: String) -> Vector3:
	var p := s.split(",")
	return Vector3(p[0].to_float(), p[1].to_float(), p[2].to_float())


func _initialize() -> void:
	var type := 0
	var view := "front3"
	var paint := Color(0.62, 0.64, 0.67)
	var cam_at := Vector3.INF
	var look := Vector3(0.0, 0.6, 0.0)
	var fov := 40.0
	var night := false
	var police := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--type="):
			type = arg.trim_prefix("--type=").to_int()
		elif arg.begins_with("--view="):
			view = arg.trim_prefix("--view=")
		elif arg.begins_with("--paint="):
			paint = Color(arg.trim_prefix("--paint="))
		elif arg.begins_with("--cam="):
			cam_at = _vec(arg.trim_prefix("--cam="))
		elif arg.begins_with("--look="):
			look = _vec(arg.trim_prefix("--look="))
		elif arg.begins_with("--fov="):
			fov = arg.trim_prefix("--fov=").to_float()
		elif arg == "--night":
			night = true
		elif arg == "--police":
			police = true
	var root := get_root()
	var world := Node3D.new()
	root.add_child(world)
	await process_frame

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	if night:
		sky_mat.sky_top_color = Color(0.01, 0.012, 0.02)
		sky_mat.sky_horizon_color = Color(0.04, 0.035, 0.03)
		sky_mat.ground_horizon_color = Color(0.03, 0.025, 0.02)
		sky_mat.ground_bottom_color = Color(0.01, 0.01, 0.01)
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	RenderingServer.global_shader_parameter_set("night_factor", 1.0 if night else 0.0)
	RenderingServer.global_shader_parameter_set("lamp_factor", 1.0 if night else 0.0)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-44.0, -130.0, 0.0)
	sun.light_energy = 0.05 if night else 1.4
	sun.shadow_enabled = true
	world.add_child(sun)
	if night:
		# A street lamp off to one side, so the paint has something to show.
		var lamp := OmniLight3D.new()
		lamp.position = Vector3(-4.0, 6.0, 3.0)
		lamp.omni_range = 16.0
		lamp.light_energy = 2.2
		lamp.light_color = Color(1.0, 0.72, 0.42)
		world.add_child(lamp)

	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200.0, 2.0, 200.0)
	shape.shape = box
	shape.position = Vector3(0.0, -1.0, 0.0)
	floor_body.add_child(shape)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(200.0, 200.0)
	ground.mesh = plane
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.20, 0.20, 0.21)
	gm.roughness = 0.9
	ground.material_override = gm
	floor_body.add_child(ground)
	world.add_child(floor_body)

	var car: Node3D
	if police:
		var rng := RandomNumberGenerator.new()
		car = load("res://scripts/npc/police_car.gd").call("make", false, rng)
		# Kinematic (it joins as a dispatch unit): stand it on its wheels by hand.
		car.position = Vector3(0.0, 0.24, 0.0)
		car.set("police", null)
	else:
		car = load("res://scripts/vehicles/vehicle.gd").new()
		car.call("setup", type, paint, 0)
		car.position = Vector3(0.0, 0.9, 0.0)
	world.add_child(car)
	for i in 90:
		await physics_frame
	for i in 3:
		await process_frame

	var cam := Camera3D.new()
	if cam_at == Vector3.INF:
		match view:
			"front":
				cam_at = Vector3(0.0, 1.0, -7.5)
			"rear":
				cam_at = Vector3(0.0, 1.1, 7.5)
			"side":
				cam_at = Vector3(8.0, 0.9, 0.0)
			"rear3":
				cam_at = Vector3(4.6, 1.35, 5.4)
			"top":
				cam_at = Vector3(5.0, 5.0, -4.0)
			_:
				cam_at = Vector3(4.4, 1.25, -5.6)
	world.add_child(cam)
	cam.fov = fov
	cam.look_at_from_position(cam_at, look)
	cam.current = true
	for i in 4:
		await process_frame
	var out := OS.get_environment("OUT")
	if out == "":
		out = "sedan_shot.png"
	root.get_texture().get_image().save_png(out)
	print("saved ", out)
	quit()
