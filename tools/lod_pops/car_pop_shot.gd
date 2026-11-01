extends SceneTree
## The near / far body swap of a parked car, as a strip: the camera backs away from a row of
## cars across the swap distance (Vehicle.body_far_distance, 30 m) in small steps and saves each
## frame's crop. Run under Forward+ (lavapipe) to see LodFade's crossfade; on opengl3 every range
## cuts whatever the fade mode says.
##
##   VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json OUT=build/pops/car xvfb-run -a \
##     -s "-screen 0 640x360x24" godot --rendering-driver vulkan --display-driver x11 \
##     --audio-driver Dummy --path . --script tools/lod_pops/car_pop_shot.gd --resolution 640x360
##
## Env: OUT prefix, FROM / TO / STEP metres (default 25, 37, 1), TYPES (default 0,1,2),
## LOD_POPS=0 the before (no LodFade), FOV (default 12: the cars fill the frame at 30 m).
func _initialize() -> void:
	var root := get_root()
	var world := Node3D.new()
	root.add_child(world)
	await process_frame
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-44.0, -130.0, 0.0)
	sun.light_energy = 1.4
	sun.shadow_enabled = true
	world.add_child(sun)
	RenderingServer.global_shader_parameter_set("sun_direction", sun.basis.z)
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
	var lf: GDScript = load("res://scripts/util/lod_fade.gd")
	if OS.get_environment("LOD_POPS") != "0":
		lf.set("force", true)
		lf.call("install", world)
	var types := (OS.get_environment("TYPES") if OS.get_environment("TYPES") != "" else "0,1,2").split(",")
	var paints := [Color(0.55, 0.06, 0.05), Color(0.9, 0.9, 0.92), Color(0.05, 0.12, 0.3)]
	for i in types.size():
		var car: Node3D = load("res://scripts/vehicles/vehicle.gd").new()
		car.call("setup", types[i].to_int(), paints[i % paints.size()], 0)
		car.position = Vector3((float(i) - float(types.size() - 1) * 0.5) * 6.0, 0.9, 0.0)
		car.rotation_degrees = Vector3(0, 60, 0)
		world.add_child(car)
	var cam := Camera3D.new()
	world.add_child(cam)
	cam.fov = float(OS.get_environment("FOV")) if OS.get_environment("FOV") != "" else 30.0
	cam.current = true
	for i in 90:
		await process_frame
	var from := float(OS.get_environment("FROM")) if OS.get_environment("FROM") != "" else 25.0
	var to := float(OS.get_environment("TO")) if OS.get_environment("TO") != "" else 37.0
	var step := float(OS.get_environment("STEP")) if OS.get_environment("STEP") != "" else 1.0
	var out := OS.get_environment("OUT") if OS.get_environment("OUT") != "" else "build/pops/car"
	DirAccess.make_dir_recursive_absolute(out.get_base_dir())
	var d := from
	var n := 0
	while d <= to + 0.001:
		# Distance to the cars' centre, from a camera 2 m up looking at them.
		cam.global_transform = Transform3D(Basis(), Vector3(0.0, 2.0, d)).looking_at(Vector3(0.0, 0.8, 0.0))
		for i in 6:
			await process_frame
		var img := root.get_texture().get_image()
		img.save_png("%s_%02d_%04.1fm.png" % [out, n, d])
		print("CARPOP %.1f" % d)
		d += step
		n += 1
	quit()
