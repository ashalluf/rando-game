extends SceneTree
## The player's boats (BoatKit) alone on calm water with the ocean-ish sky, seconds a frame:
##   OUT=b.png xvfb-run -a -s "-screen 0 1280x720x24" godot --rendering-driver opengl3 \
##     --audio-driver Dummy --path . --script tools/boats/boat_shot.gd --resolution 1280x720
## Env: OUT, CAM / LOOK (x,y,z), FOV, LEVEL=n (one level for both), ACCENT=n, PAINT=r,g,b.
func _initialize() -> void:
	var stage := Node3D.new()
	get_root().add_child(stage)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.28, 0.45, 0.7)
	sky_mat.sky_horizon_color = Color(0.72, 0.76, 0.8)
	sky_mat.ground_horizon_color = Color(0.3, 0.4, 0.45)
	sky_mat.ground_bottom_color = Color(0.05, 0.12, 0.15)
	sky.sky_material = sky_mat
	e.sky = sky
	e.background_mode = Environment.BG_SKY
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.6
	e.tonemap_mode = Environment.TONE_MAPPER_AGX
	e.tonemap_exposure = 1.25
	env.environment = e
	stage.add_child(env)
	for g in ["lamp_factor", "night_factor", "wind_factor", "road_wetness"]:
		RenderingServer.global_shader_parameter_set(g, 0.0)
	RenderingServer.global_shader_parameter_set("origin_shift", Vector3.ZERO)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40.0, 35.0, 0.0)
	sun.light_energy = 1.4
	sun.shadow_enabled = true
	stage.add_child(sun)
	var sea := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(300.0, 300.0)
	sea.mesh = pm
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(0.03, 0.12, 0.15)
	wm.roughness = 0.08
	wm.metallic_specular = 0.8
	sea.material_override = wm
	stage.add_child(sea)
	await process_frame
	var bk: GDScript = load("res://scripts/vehicles/boat_kit.gd")
	var lvl := int(OS.get_environment("LEVEL")) if OS.get_environment("LEVEL") != "" else 0
	var accent := int(OS.get_environment("ACCENT")) if OS.get_environment("ACCENT") != "" else 2
	var paint := Color(0.93, 0.93, 0.92)
	if OS.get_environment("PAINT") != "":
		var q := OS.get_environment("PAINT").split(",")
		paint = Color(q[0].to_float(), q[1].to_float(), q[2].to_float())
	for k in 2:
		var mi := MeshInstance3D.new()
		mi.mesh = bk.mesh(k, lvl, accent)
		mi.material_override = bk.material(paint, 1)
		mi.position = Vector3(-3.0 if k == 0 else 3.0, 0.0, 0.0)
		mi.rotation.y = 0.5
		stage.add_child(mi)
		print("TRIS kind %d level %d: %d" % [k, lvl, bk.triangles(k, lvl)])
	var cam := Camera3D.new()
	var c := _v(OS.get_environment("CAM"), Vector3(6.0, 4.5, 9.0))
	var l := _v(OS.get_environment("LOOK"), Vector3(0.0, 0.6, 0.0))
	cam.fov = float(OS.get_environment("FOV")) if OS.get_environment("FOV") != "" else 45.0
	stage.add_child(cam)
	cam.global_position = c
	cam.look_at(l)
	cam.current = true
	for i in 6:
		await process_frame
	var img := get_root().get_texture().get_image()
	var out := OS.get_environment("OUT") if OS.get_environment("OUT") != "" else "boat.png"
	img.save_png(out)
	print("SAVED ", out)
	quit()


func _v(s: String, d: Vector3) -> Vector3:
	if s == "":
		return d
	var q := s.split(",")
	return Vector3(q[0].to_float(), q[1].to_float(), q[2].to_float())
