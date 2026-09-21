extends SceneTree
## TEMPORARY review harness: renders LandmarkVerdeCafe in isolation. Deleted after use.
func _initialize() -> void:
	var root3d := Node3D.new()
	get_root().add_child(root3d)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.55, 0.72, 0.95)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.62, 0.66, 0.72)
	e.ambient_light_energy = 0.9
	env.environment = e
	root3d.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-46, 152, 0)
	sun.light_energy = 1.1
	root3d.add_child(sun)
	# A slab of pavement so the cafe is not floating in the void.
	var ground := MeshInstance3D.new()
	var gm := BoxMesh.new()
	gm.size = Vector3(90, 0.4, 90)
	ground.mesh = gm
	ground.position = Vector3(0, -0.38, 0)
	ground.material_override = PropFactory.material(Color(0.62, 0.61, 0.58))
	root3d.add_child(ground)
	await process_frame
	LandmarkVerdeCafe.build(Vector2(0, 0), root3d, StaticBody3D.new(), null, true)
	RenderingServer.global_shader_parameter_set("lamp_factor", float(OS.get_environment("NIGHT") == "1"))
	RenderingServer.global_shader_parameter_set("night_factor", float(OS.get_environment("NIGHT") == "1"))
	var cam := Camera3D.new()
	root3d.add_child(cam)
	var eye := _env_v("EYE", Vector3(14, 6, 20))
	var tgt := _env_v("TGT", Vector3(-1, 2.2, 0))
	cam.look_at_from_position(eye, tgt)
	cam.far = 900.0
	cam.current = true
	for i in 14:
		await process_frame
	var out := OS.get_environment("OUT")
	if out == "":
		out = "cafe_shot.png"
	get_root().get_texture().get_image().save_png(out)
	print("saved ", out)
	quit()

static func _env_v(key: String, fallback: Vector3) -> Vector3:
	var v := OS.get_environment(key)
	if v == "":
		return fallback
	var p := v.split(",")
	return Vector3(float(p[0]), float(p[1]), float(p[2]))
