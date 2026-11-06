extends SceneTree
## The police at night in a small street of their own (PoliceNightLook): a wet or dry road between
## two facades, a pursuit pair of cruisers bearing down, a roadblock pair across the far end with
## its flares, a parked car whose paint and glass take the strobes - without the city, so it
## renders on lavapipe (Forward+, where the real strobes are) in a few minutes and on opengl3 in
## seconds (the washes alone, what the web draws; FORCE=1 forces the real lights there too).
##
##   OUT=/tmp/pn.png xvfb-run -a -s "-screen 0 1280x720x24" godot \
##     --rendering-driver vulkan --display-driver x11 --audio-driver Dummy --path . \
##     --script tools/police_night/police_shot.gd --resolution 1280x720
##
## Env: OUT png path; RAIN=0..1 wet road and rain (road_wetness, rain_intensity); VIEW=chase
## (default: behind the player, the cruisers coming) | low (at the road, the mirrored strobes) |
## block (the roadblock and its flares); LOOK=0 the A/B (the old bar and its own BarLight);
## T=seconds the flash clock is held at; STRIP=n saves n frames 0.05 s apart from T (OUT_00.png ...);
## FRAMES before the shot (default 30). Nothing here names a class as a TYPE (compiled before the
## autoloads exist).

func _env(k: String, d: String) -> String:
	var v := OS.get_environment(k)
	return v if v != "" else d


func _initialize() -> void:
	var look_script: GDScript = load("res://scripts/npc/police_night_look.gd")
	look_script.set("enabled", _env("LOOK", "1") != "0")
	look_script.set("hold", true)
	look_script.set("clock", float(_env("T", "0.02")))
	if _env("FORCE", "0") == "1":
		look_script.set("force", true)
	var lights_script: GDScript = load("res://scripts/vehicles/car_lights.gd")
	lights_script.set("lamp_override", 1.0)
	var rain := float(_env("RAIN", "0"))
	RenderingServer.global_shader_parameter_set("lamp_factor", 1.0)
	RenderingServer.global_shader_parameter_set("night_factor", 1.0)
	RenderingServer.global_shader_parameter_set("road_wetness", rain)
	RenderingServer.global_shader_parameter_set("rain_intensity", rain)
	var dn: GDScript = load("res://scripts/world/day_night.gd")
	dn.set("lamp_now", 1.0)
	var world := Node3D.new()
	world.name = "World"
	root.add_child(world)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.010, 0.013, 0.025)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.09, 0.10, 0.15)
	env.ambient_light_energy = 0.45
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_bloom = 0.08
	env.glow_hdr_threshold = 1.0
	env.ssr_enabled = true
	env.fog_enabled = true
	env.fog_light_color = Color(0.05, 0.055, 0.07)
	env.fog_density = 0.004 + 0.01 * rain
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.006 + 0.02 * rain
	env.volumetric_fog_albedo = Color(0.8, 0.8, 0.85)
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	var moon := DirectionalLight3D.new()
	moon.light_energy = 0.03
	moon.light_color = Color(0.6, 0.7, 1.0)
	moon.rotation_degrees = Vector3(-50.0, 30.0, 0.0)
	world.add_child(moon)
	var pf: GDScript = load("res://scripts/world/prop_factory.gd")
	pf.call("set_wetness", rain)
	var road: Material = pf.call("road", "asphalt", 5.0, Color(1, 1, 1), 7, 0.0, 1.0)
	_slab(world, Vector3(20.0, 0.2, 140.0), Vector3(0.0, -0.1, -40.0), road)
	_slab(world, Vector3(5.0, 0.15, 140.0), Vector3(12.5, 0.075, -40.0), pf.call("road", "sidewalk", 3.0, Color(1, 1, 1), 8, 1.5, 0.4))
	_slab(world, Vector3(5.0, 0.15, 140.0), Vector3(-12.5, 0.075, -40.0), pf.call("road", "sidewalk", 3.0, Color(1, 1, 1), 9, 1.5, 0.4))
	for k in 5:
		var z := 12.0 - 26.0 * float(k)
		_wall(world, Vector3(1.0, 14.0 + 6.0 * float(k % 2), 24.0), Vector3(15.5, 0.0, z), pf.call("pbr", "brick" if k % 2 == 0 else "plaster_beige", 3.0))
		_wall(world, Vector3(1.0, 18.0 - 5.0 * float(k % 2), 24.0), Vector3(-15.5, 0.0, z), pf.call("pbr", "plaster_beige" if k % 2 == 0 else "brick", 3.0))
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60.0, 0.2, 160.0)
	shape.shape = box
	body.add_child(shape)
	body.position = Vector3(0.0, -0.1, -40.0)
	world.add_child(body)
	var player := Node3D.new()
	player.add_to_group("player")
	player.position = Vector3(1.5, 0.0, 6.0)
	world.add_child(player)
	var police_script: GDScript = load("res://scripts/npc/police.gd")
	var police: Node = police_script.new()
	police.name = "Police"
	police.set("enabled", false)
	police.set("stars", 3)
	world.add_child(police)
	var pc: GDScript = load("res://scripts/npc/police_car.gd")
	var vs: GDScript = load("res://scripts/vehicles/vehicle.gd")
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	var cars: Array = []
	# The pursuit: two cruisers coming at the camera, a car's length apart and offset.
	for spec in [[Vector3(-2.2, 0.0, -14.0), 0.03], [Vector3(2.6, 0.0, -24.0), -0.05], [Vector3(-3.5, 0.0, -66.0), PI * 0.5], [Vector3(2.0, 0.0, -66.5), -PI * 0.5]]:
		var car: Node = pc.call("make", false, rng)
		car.set("police", police)
		car.set("scripted", true)
		var at: Vector3 = spec[0]
		at.y = float(car.call("road_lift"))
		car.set("position", at)
		# A cruiser drives -Z; these face +Z, at the camera, or across the road.
		car.set("rotation", Vector3(0.0, PI + float(spec[1]), 0.0))
		world.add_child(car)
		cars.append(car)
	var parked: Node = vs.new()
	parked.call("setup", 0, Color(0.06, 0.07, 0.09), 0)
	parked.set("position", Vector3(7.8, 0.6, -6.0))
	world.add_child(parked)
	var parked2: Node = vs.new()
	parked2.call("setup", 8, Color(0.75, 0.76, 0.78), 0)
	parked2.set("position", Vector3(-7.8, 0.6, -20.0))
	world.add_child(parked2)
	await physics_frame
	await physics_frame
	cars[2].set("roadblock", true)
	cars[3].set("roadblock", true)
	var cam := Camera3D.new()
	cam.fov = 58.0
	world.add_child(cam)
	match _env("VIEW", "chase"):
		"low":
			cam.look_at_from_position(Vector3(1.0, 0.55, 10.0), Vector3(-0.5, 1.0, -20.0))
		"block":
			cam.look_at_from_position(Vector3(-1.0, 2.4, -44.0), Vector3(0.0, 0.8, -66.0))
		_:
			cam.look_at_from_position(Vector3(1.8, 3.2, 12.0), Vector3(0.0, 1.2, -24.0))
	cam.current = true
	for i in int(_env("FRAMES", "30")):
		await process_frame
	for c in cars:
		var g: Node3D = c.get_node_or_null("PoliceGlow")
		print("CRUISER lit=%s glow=%s side=%d pool=%s %s walls=%s aabb=%s vit=%s" % [c.call("bar_lit"), g.visible if g else null, int(c.call("flash_side", float(look_script.get("clock")))), g.get_node("Pool").visible if g else null, (g.get_node("Pool") as Node3D).global_transform if g else null, [g.get_node("WallA").visible, g.get_node("WallB").visible] if g else null, (g.get_node("Pool") as MeshInstance3D).get_aabb() if g else null, (g.get_node("Pool") as Node3D).is_visible_in_tree() if g else null])
	var out := _env("OUT", "police_night.png")
	var strip := int(_env("STRIP", "0"))
	if strip <= 0:
		await process_frame
		await process_frame
		root.get_texture().get_image().save_png(out)
		print("saved %s, strobes %d" % [out, int(look_script.get("active_count"))])
	else:
		var t0 := float(_env("T", "0.02"))
		for k in strip:
			look_script.set("clock", t0 + 0.05 * float(k))
			await process_frame
			await process_frame
			var p := out.get_basename() + "_%02d.png" % k
			root.get_texture().get_image().save_png(p)
			print("saved %s, strobes %d" % [p, int(look_script.get("active_count"))])
	quit()


func _slab(parent: Node3D, size: Vector3, at: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = size
	mi.mesh = m
	mi.material_override = mat
	mi.position = at
	parent.add_child(mi)


## A facade: a box standing on the pavement, with a collision body so the washes find it.
func _wall(parent: Node3D, size: Vector3, foot: Vector3, mat: Material) -> void:
	var at := foot + Vector3(0.0, size.y * 0.5, 0.0)
	_slab(parent, size, at, mat)
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.position = at
	parent.add_child(body)
