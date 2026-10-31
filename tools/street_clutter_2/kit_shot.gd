extends SceneTree
## The second street clutter pass's kit alone (StreetClutter2): every mesh in a row on a grey
## ground, sun and sky, under opengl3 in seconds. OUT=png, NIGHT=1, WET=0..1.
##   xvfb-run -a godot --rendering-driver opengl3 --path . --script tools/street_clutter_2/kit_shot.gd
func _initialize() -> void:
	var sc: GDScript = load("res://scripts/world/street_clutter_2.gd")
	RenderingServer.global_shader_parameter_set("road_wetness", float(OS.get_environment("WET")) if OS.get_environment("WET") != "" else 0.0)
	RenderingServer.global_shader_parameter_set("night_factor", 1.0 if OS.get_environment("NIGHT") == "1" else 0.0)
	RenderingServer.global_shader_parameter_set("sky_tint", Color(0.66, 0.75, 0.88))
	var root3 := Node3D.new()
	get_root().add_child(root3)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.5, 0.6, 0.75)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.5, 0.55, 0.65)
	root3.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 30, 0)
	sun.shadow_enabled = true
	root3.add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 40)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.35, 0.35, 0.34)
	ground.material_override = gm
	root3.add_child(ground)
	var x := -9.0
	for key: String in sc.get("KEYS"):
		# One instance in a MultiMesh, so the shaders get their instance custom data.
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true
		mm.mesh = sc.call("mesh_for", key)
		mm.instance_count = 1
		mm.set_instance_transform(0, Transform3D())
		mm.set_instance_color(0, Color.WHITE)
		mm.set_instance_custom_data(0, Color(0.4, 0.8, 8.0 / 32.0 if key == "sc2_paper" else 0.0, 0.0))
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.position = Vector3(x, 0.01, 0.0)
		if key == "sc2_poster":
			mi.scale = Vector3(0.157, 1.0, 0.157)
			mi.position.y = -1.6
		if key == "sc2_puddle":
			mi.scale = Vector3(2.0, 1.0, 1.4)
		root3.add_child(mi)
		x += 1.5
	var cam := Camera3D.new()
	cam.position = Vector3(0, 2.2, 7.5)
	cam.rotation_degrees = Vector3(-14, 0, 0)
	cam.fov = 70
	root3.add_child(cam)
	cam.current = true
	for i in 6:
		await process_frame
	var img := get_root().get_texture().get_image()
	img.save_png(OS.get_environment("OUT") if OS.get_environment("OUT") != "" else "/tmp/kit.png")
	quit()
