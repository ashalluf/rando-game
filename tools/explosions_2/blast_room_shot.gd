extends SceneTree
## A blast in a small street, frame by frame, small enough for lavapipe's Forward+ (the owner's
## Mac's renderer) as well as opengl3: the test room, two real Buildings facing each other across
## a 20 m street, the city's grade (AgX, glow, SSAO; the room's own sky), and one explosion (or a
## car's own explosion) photographed at several times from ONE blast.
##
##   OUT=/tmp/blast.png TIMES=0.03,0.1,0.3,1,3,8,14 VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json \
##     xvfb-run -a -s "-screen 0 1280x720x24" godot --rendering-driver vulkan --display-driver x11 \
##     --audio-driver Dummy --path . --script tools/explosions_2/blast_room_shot.gd --resolution 960x540
##
## Env: OUT (stem; `_t<seconds>.png` each), TIMES, NIGHT=1 (no sun, a dark sky, night_factor 1),
## GOLDEN=1 (a low warm sun, a peach horizon), SUN=pitch,yaw (degrees, the sun turned), WET=1 (a glossy wet road), PROPS=1 (bins and parked cars in the shock ring), FACADE=1 (a rocket into a building's face, 6 m up), UP=m (the camera that high, looking down),
## CAR=1 (a parked car's own explosion: fuel fireball and toss; CHAIN=1 two more cars beside it), DIST (camera metres from the
## blast, default 34), HEIGHT (camera eye, 1.7), RADIUS (9), SCALE (slow motion before 1 s,
## 0.375 = 0.05 s a frame), LATE (after 1 s, 2.0), CAM_X (camera sideways, -4), LOOK_Y (aim height,
## 9), WEB=1 (the web build's card path), GAS=1 (a petrol pump's vapour blast, Blast4), FULL=0 (WeaponFX.explosion alone; by default Explosion.blast(), so the crater and rubble too). EXPLOSIONS_2=0 is the old blast (the before).
## FRAMES=n saves n more frames after each time with the clock all but stopped, or with
## FRAMES_SCALE=1 under `--fixed-fps 60` at true 60 fps steps (what TAA integrates on the Mac).
## Loads WeaponFX, Vehicle and Building by path: naming them compiles them before the autoloads.

func _initialize() -> void:
	var packed: PackedScene = load("res://scenes/levels/test_box.tscn")
	var level := packed.instantiate()
	root.add_child(level)
	await process_frame
	await process_frame
	var night := OS.get_environment("NIGHT") == "1"
	var env: Environment = (level.get_node("WorldEnvironment") as WorldEnvironment).environment
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.glow_enabled = true
	env.glow_intensity = 0.8
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.0
	env.ssao_enabled = true
	env.fog_enabled = true
	env.fog_density = 0.0015
	var sun := level.get_node("Sun") as DirectionalLight3D
	sun.rotation_degrees = Vector3(-38.0, -35.0, 0.0)
	RenderingServer.global_shader_parameter_set("sun_direction", sun.global_basis.z)
	if OS.get_environment("SUN") != "":
		# SUN=pitch,yaw (degrees): the sun turned for a still (a crater out of a building's shadow).
		var sv := OS.get_environment("SUN").split(",")
		sun.rotation_degrees = Vector3(float(sv[0]), float(sv[1]), 0.0)
		RenderingServer.global_shader_parameter_set("sun_direction", sun.global_basis.z)
	if night:
		sun.light_energy = 0.03
		env.background_energy_multiplier = 0.05
		env.ambient_light_energy = 0.08
		env.fog_light_color = Color(0.03, 0.035, 0.05)
		RenderingServer.global_shader_parameter_set("night_factor", 1.0)
		RenderingServer.global_shader_parameter_set("lamp_factor", 1.0)
		(load("res://scripts/world/day_night.gd") as GDScript).set("lamp_now", 1.0)
		RenderingServer.global_shader_parameter_set("sky_tint", Color(0.05, 0.06, 0.09))
	elif OS.get_environment("GOLDEN") == "1":
		# Golden hour: a low sun behind the camera's left, warm, the sky's horizon peach.
		sun.rotation_degrees = Vector3(-9.0, -60.0, 0.0)
		sun.light_color = Color(1.0, 0.66, 0.4)
		sun.light_energy = 1.6
		RenderingServer.global_shader_parameter_set("sun_direction", sun.global_basis.z)
		env.background_energy_multiplier = 0.7
		env.fog_light_color = Color(0.85, 0.62, 0.45)
		RenderingServer.global_shader_parameter_set("night_factor", 0.0)
		RenderingServer.global_shader_parameter_set("sky_tint", Color(0.86, 0.66, 0.52))
	else:
		RenderingServer.global_shader_parameter_set("night_factor", 0.0)
		RenderingServer.global_shader_parameter_set("sky_tint", Color(0.62, 0.70, 0.80))
	var player := get_first_node_in_group("player") as Node3D
	var base := player.global_position
	base.y = 0.0
	# The street: two Buildings, faces 10 m either side of its centre line (x), running along z.
	var bscene: PackedScene = load("res://scenes/props/building.tscn")
	# Far off the room's own pillars, on a floor of its own.
	var centre := base + Vector3(600.0, 0.0, -40.0)
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	var fs := CollisionShape3D.new()
	var fb := BoxShape3D.new()
	fb.size = Vector3(400.0, 1.0, 400.0)
	fs.shape = fb
	floor_body.add_child(fs)
	var fm := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = fb.size
	fm.mesh = bm
	var asphalt := StandardMaterial3D.new()
	asphalt.albedo_color = Color(0.16, 0.16, 0.17)
	asphalt.roughness = 0.9
	if OS.get_environment("WET") == "1":
		# WET=1: a rain-soaked road (dark, glossy): what a night blast should light and mirror.
		asphalt.albedo_color = Color(0.08, 0.08, 0.085)
		asphalt.roughness = 0.12
	fm.material_override = asphalt
	floor_body.add_child(fm)
	root.add_child(floor_body)
	floor_body.global_position = centre - Vector3(0.0, 0.5, 0.0)
	for side in [-1, 1]:
		for k in 2:
			var b: Node3D = bscene.instantiate()
			b.set("seed", 4100 + k * 7 + (side + 1) * 13)
			b.set("lot_size", Vector2(24.0, 26.0))
			b.set("min_height", 22.0)
			b.set("max_height", 34.0)
			root.add_child(b)
			b.global_position = centre + Vector3(float(side) * 23.0, 0.0, -14.0 + float(k) * 28.0)
	for i in 4:
		await process_frame
	player.global_position = centre + Vector3(0.0, 0.0, 40.0)
	player.visible = false
	var dist := float(_env("DIST", "34"))
	var h := float(_env("HEIGHT", "1.7"))
	var cam := Camera3D.new()
	cam.fov = 62.0
	cam.far = 2000.0
	root.add_child(cam)
	cam.global_position = centre + Vector3(float(_env("CAM_X", "-4")), h, dist)
	cam.look_at(centre + Vector3(0.0, float(_env("LOOK_Y", "9")), 0.0))
	cam.current = true
	cam.attributes = CameraAttributesPractical.new()
	var hud := get_first_node_in_group("debug_hud")
	if hud != null:
		hud.set("visible", false)
	for c in level.get_children():
		if c is CanvasLayer:
			(c as CanvasLayer).visible = false
	for i in int(_env("WARM", "8")):
		await process_frame
	if OS.get_environment("WEB") == "1":
		# The web build's path (cards, CPU particles, no volume or haze) on this renderer.
		load("res://scripts/weapons/weapon_fx.gd")._web_cache = 1
	var radius := float(_env("RADIUS", "9"))
	var at := centre + Vector3(1.5, 0.6, 0.0)
	if OS.get_environment("FACADE") == "1":
		# FACADE=1: a rocket into the left building's street face, 6 m up (the face is found by a ray).
		var sp := root.get_world_3d().direct_space_state
		var hitf := sp.intersect_ray(PhysicsRayQueryParameters3D.create(centre + Vector3(0.0, 6.0, -14.0), centre + Vector3(-30.0, 6.0, -14.0), 1))
		at = (hitf.position as Vector3) + (hitf.normal as Vector3) * 0.3 if not hitf.is_empty() else centre + Vector3(-10.5, 6.0, -14.0)
		cam.global_position = at + Vector3(float(_env("DIST", "30")) * 0.75, 1.7 - at.y + centre.y, float(_env("DIST", "30")) * 0.66)
		cam.look_at(at + Vector3(0.0, 2.0, 0.0))
	if OS.get_environment("UP") != "":
		# UP=metres: seen from the air (flying), looking down at the blast from a slant.
		var up := float(OS.get_environment("UP"))
		cam.global_position = at + Vector3(-up * 0.25, up, up * 0.55)
		cam.look_at(at)
	if OS.get_environment("PROPS") == "1":
		# PROPS=1: bins and two parked cars in the blast's shock ring (12-20 m), to see it kick them.
		for k in 6:
			var can: Node3D = load("res://scripts/world/trash_can.gd").new()
			root.add_child(can)
			var a := float(k) * 1.05 - 2.6
			can.global_position = at + Vector3(sin(a) * (11.0 + float(k)), -0.55, cos(a) * (11.0 + float(k)))
		for k in 2:
			var pc: Node3D = load("res://scripts/vehicles/vehicle.gd").random_car(RandomNumberGenerator.new())
			root.add_child(pc)
			pc.global_position = at + Vector3(-7.0 + 14.0 * float(k), 0.8, 13.0 + 3.0 * float(k))
			pc.rotation.y = 0.3 * float(k)
		for i in 40:
			await physics_frame
		for c in root.get_children():
			if c is RigidBody3D:
				c.set_meta("shot_start", (c as Node3D).global_position)
	Engine.time_scale = float(_env("SCALE", "0.375"))
	if OS.get_environment("CAR") == "1":
		var car: Node3D = load("res://scripts/vehicles/vehicle.gd").random_car(RandomNumberGenerator.new())
		root.add_child(car)
		car.global_position = at + Vector3(0.0, 0.8, 0.0)
		car.rotation.y = 0.6
		if OS.get_environment("CHAIN") == "1":
			# Two more parked cars beside it: the fuel blast's chain fuse sets them off in turn.
			for k in 2:
				var nb: Node3D = load("res://scripts/vehicles/vehicle.gd").random_car(RandomNumberGenerator.new())
				root.add_child(nb)
				nb.global_position = at + Vector3(-5.5 * (k + 1), 0.8, 1.0 + 1.5 * k)
				nb.rotation.y = 0.5 - 0.3 * k
		for i in 6:
			await physics_frame
		car.call("damage_state").explode()
	elif OS.get_environment("GAS") == "1":
		# A petrol pump's vapour blast (Blast4): what PropBreak's pump hook sets off.
		load("res://scripts/weapons/blast_4.gd").gas_next = true
		load("res://scripts/weapons/explosion.gd").blast(player, at, radius, 26.0, 0.0)
	elif OS.get_environment("FULL") != "0":
		# The whole blast as a rocket sets it off (crater, rubble, dust: BlastAftermath too).
		load("res://scripts/weapons/explosion.gd").blast(player, at, radius, 30.0, 0.0)
	else:
		load("res://scripts/weapons/weapon_fx.gd").explosion(player, at, radius)
	var out := _env("OUT", "blast_room.png")
	var elapsed := 0.0
	for s in _env("TIMES", "0.03,0.1,0.3,1,3,8,14").split(","):
		var want := float(s)
		while elapsed < want:
			Engine.time_scale = float(_env("LATE", "2.0")) if elapsed >= 1.0 else float(_env("SCALE", "0.375"))
			await process_frame
			elapsed += root.get_process_delta_time()
		var path := out.get_basename() + "_t%05.2f.png" % want
		root.get_texture().get_image().save_png(path)
		print("saved ", path, " at ", elapsed)
		# FRAMES=n: n more frames right after, the clock all but stopped (what TAA averages: is a
		# dither resolved, or does it stay a screen door?).
		var extra := int(_env("FRAMES", "0"))
		if extra > 0:
			var keep := Engine.time_scale
			Engine.time_scale = float(_env("FRAMES_SCALE", "0.0001"))
			for k in extra:
				await process_frame
				var fp := out.get_basename() + "_t%05.2f_f%02d.png" % [want, k]
				root.get_texture().get_image().save_png(fp)
			print("saved ", extra, " frames after ", path)
			Engine.time_scale = keep
		# The frame's cost with the blast in it (opengl3 / vulkan; zero under --headless).
		print("GEO t=%.2f draws=%d objects=%d tris=%d" % [elapsed,
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)])
	if OS.get_environment("PROPS") == "1":
		for c in root.get_children():
			if c is RigidBody3D and c.has_meta("shot_start"):
				var st: Vector3 = c.get_meta("shot_start")
				print("MOVED %s %.2f m (at %.1f m from the blast)" % ["car" if c is VehicleBody3D else "bin", (c as Node3D).global_position.distance_to(st), st.distance_to(at)])
	quit()


func _env(key: String, fallback: String) -> String:
	var v := OS.get_environment(key)
	return v if v != "" else fallback
