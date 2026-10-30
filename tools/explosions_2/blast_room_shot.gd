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
## CAR=1 (a parked car's own explosion: fuel fireball and toss), DIST (camera metres from the
## blast, default 34), HEIGHT (camera eye, 1.7), RADIUS (9), SCALE (slow motion before 1 s,
## 0.375 = 0.05 s a frame), LATE (after 1 s, 2.0). EXPLOSIONS_2=0 is the old blast (the before).
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
	if night:
		sun.light_energy = 0.03
		env.background_energy_multiplier = 0.05
		env.ambient_light_energy = 0.08
		env.fog_light_color = Color(0.03, 0.035, 0.05)
		RenderingServer.global_shader_parameter_set("night_factor", 1.0)
		RenderingServer.global_shader_parameter_set("lamp_factor", 1.0)
		RenderingServer.global_shader_parameter_set("sky_tint", Color(0.05, 0.06, 0.09))
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
	cam.global_position = centre + Vector3(-4.0, h, dist)
	cam.look_at(centre + Vector3(0.0, 9.0, 0.0))
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
	var radius := float(_env("RADIUS", "9"))
	var at := centre + Vector3(1.5, 0.6, 0.0)
	Engine.time_scale = float(_env("SCALE", "0.375"))
	if OS.get_environment("CAR") == "1":
		var car: Node3D = load("res://scripts/vehicles/vehicle.gd").random_car(RandomNumberGenerator.new())
		root.add_child(car)
		car.global_position = at + Vector3(0.0, 0.8, 0.0)
		car.rotation.y = 0.6
		for i in 6:
			await physics_frame
		car.call("damage_state").explode()
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
	quit()


func _env(key: String, fallback: String) -> String:
	var v := OS.get_environment(key)
	return v if v != "" else fallback
