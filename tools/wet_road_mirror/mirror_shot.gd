extends SceneTree
## The wet road's mirror alone (docs/HANDOFF.md "The wet road's mirror"): one street slab on the
## real road material, two rows of lit shop fronts and office windows along it (emissive boxes, so
## Forward+'s SSR has something to mirror), street lamps, a night sky, the rain's globals. Small
## enough for Forward+ under lavapipe (a city block is not: 13 GB), seconds on opengl3:
##
##   OUT=/tmp/m.png VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json xvfb-run -a -s \
##     "-screen 0 1280x720x24" godot --rendering-driver vulkan --display-driver x11 --audio-driver Dummy \
##     --path . --script tools/wet_road_mirror/mirror_shot.gd --resolution 960x540
##
## WET (road_wetness, default 1), RAIN (rain_intensity, default 0: no rings, so frames compare),
## LAMP (lamp_factor, default 1), WET_ROAD_MIRROR=0 the old mirror, SSR=0 off on Forward+,
## EYE=x,y,z,yaw,pitch (default 0,1.7,0,0,-3), FRAMES (default 20), FOV (55).

var _out := ""


func _env(k: String, d: String) -> String:
	var v := OS.get_environment(k)
	return v if v != "" else d


func _initialize() -> void:
	_out = _env("OUT", "/tmp/mirror_shot.png")
	var root3d := Node3D.new()
	get_root().add_child(root3d)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.035, 0.03, 0.04)
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.05, 0.045, 0.05)
	env.glow_enabled = true
	env.ssr_enabled = _env("SSR", "1") != "0"
	env.ssr_max_steps = 96
	env.ssr_fade_in = 0.15
	env.ssr_fade_out = 2.0
	var we := WorldEnvironment.new()
	we.environment = env
	root3d.add_child(we)
	# The street: 14 m of carriageway along -Z, its lamps along Z (lamp_axis 1).
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(14.0, 300.0)
	var mat: ShaderMaterial = (load("res://scripts/world/prop_factory.gd") as GDScript).call("road", "asphalt", 7.0, Color(0.72, 0.72, 0.74), 1234)
	mat.set_shader_parameter("lamp_axis", 1)
	mesh.material = mat
	var road := MeshInstance3D.new()
	road.mesh = mesh
	road.position = Vector3(0.0, 0.0, -140.0)
	root3d.add_child(road)
	# The pavements and the buildings along both sides: dark walls, lit shop fronts at the foot
	# (hashed, so it is not a row of identical lights), lit windows above.
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	for side in [-1.0, 1.0]:
		var walk := MeshInstance3D.new()
		var wb := BoxMesh.new()
		wb.size = Vector3(4.0, 0.15, 300.0)
		walk.mesh = wb
		var wm := StandardMaterial3D.new()
		wm.albedo_color = Color(0.25, 0.24, 0.23)
		walk.material_override = wm
		walk.position = Vector3(side * 9.0, 0.075, -140.0)
		root3d.add_child(walk)
		var z := -4.0
		while z > -280.0:
			var wide := rng.randf_range(8.0, 22.0)
			var tall := rng.randf_range(10.0, 45.0)
			var wall := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(6.0, tall, wide - 0.6)
			wall.mesh = bm
			var dm := StandardMaterial3D.new()
			dm.albedo_color = Color(0.12, 0.11, 0.1)
			wall.material_override = dm
			wall.position = Vector3(side * 14.0, tall * 0.5, z - wide * 0.5)
			root3d.add_child(wall)
			if rng.randf() < 0.65:
				var shop := MeshInstance3D.new()
				var sm := BoxMesh.new()
				sm.size = Vector3(0.1, 3.2, wide * rng.randf_range(0.5, 0.9))
				shop.mesh = sm
				var em := StandardMaterial3D.new()
				var warm := rng.randf() < 0.7
				em.albedo_color = Color.BLACK
				em.emission_enabled = true
				em.emission = Color(1.0, 0.7, 0.4) if warm else Color(0.75, 0.85, 1.0)
				em.emission_energy_multiplier = rng.randf_range(0.8, 3.0)
				shop.material_override = em
				shop.position = Vector3(side * 10.95, 1.8, z - wide * 0.5)
				root3d.add_child(shop)
			for f in range(2, int(tall / 3.2) - 1):
				for b in range(int(wide / 2.6)):
					if rng.randf() > 0.22:
						continue
					var win := MeshInstance3D.new()
					var qm := BoxMesh.new()
					qm.size = Vector3(0.05, 1.5, 1.4)
					win.mesh = qm
					var lm := StandardMaterial3D.new()
					lm.albedo_color = Color.BLACK
					lm.emission_enabled = true
					lm.emission = Color(1.0, 0.82, 0.55)
					lm.emission_energy_multiplier = 0.7
					win.material_override = lm
					win.position = Vector3(side * 10.97, f * 3.2 + 1.6, z - 1.3 - b * 2.6)
					root3d.add_child(win)
			z -= wide
	# Street lamps every 30 m, staggered.
	var lz := -10.0
	var s := 1.0
	while lz > -250.0:
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.72, 0.42)
		l.light_energy = 3.0
		l.omni_range = 18.0
		l.position = Vector3(s * 6.4, 7.5, lz)
		root3d.add_child(l)
		s = -s
		lz -= 30.0
	var cam := Camera3D.new()
	var e := _env("EYE", "0,1.7,0,0,-3").split(",")
	cam.position = Vector3(float(e[0]), float(e[1]), float(e[2]))
	cam.rotation_degrees = Vector3(float(e[4]), float(e[3]), 0.0)
	cam.fov = float(_env("FOV", "55"))
	cam.far = 2000.0
	root3d.add_child(cam)
	cam.current = true
	var rs := RenderingServer
	rs.global_shader_parameter_set("ground_detail", 1.0)
	rs.global_shader_parameter_set("road_wetness", float(_env("WET", "1")))
	rs.global_shader_parameter_set("road_drying", 0.0)
	rs.global_shader_parameter_set("rain_intensity", float(_env("RAIN", "0")))
	rs.global_shader_parameter_set("lamp_factor", float(_env("LAMP", "1")))
	rs.global_shader_parameter_set("road_stamp_near", 0.0)
	rs.global_shader_parameter_set("sky_tint", Color(0.07, 0.06, 0.07, 1.0))
	rs.global_shader_parameter_set("wet_road_mirror", 0.0 if _env("WET_ROAD_MIRROR", "1") == "0" else 1.0)
	_shoot.call_deferred(int(_env("FRAMES", "20")))


func _shoot(frames: int) -> void:
	for i in frames:
		await process_frame
	var img := get_root().get_viewport().get_texture().get_image()
	img.save_png(_out)
	print("saved ", _out)
	quit()
