extends SceneTree
## The airliner alone in the night sky as the airport_final refcam sees it (from the street below,
## looking up at its belly), in seconds (opengl3 + Xvfb), to judge JetFinal's livery pass:
##
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --rendering-driver opengl3 --path . \
##     --script tools/rc5_airport_final/final_shot.gd --resolution 1280x720 -- OUT=build/final.png
##
## Env: LIVERY (0..5, default 0), CAM=x,y,z metres from the jet's centre (default under and ahead
## of it, the refcam's angle), LOOK=x,y,z, FOV (default 18: a long lens to see it at its refcam
## size), JF=0 the old livery (the before), UNDER=r,g,b the city underlight, GEAR=g the gear lamps.
## The jet's nose is -X (the model's own frame, scaled to 38 m).

func _initialize() -> void:
	_run.call_deferred()


func _env(k: String, d: String) -> String:
	var v := OS.get_environment(k)
	return v if v != "" else d


func _v3(s: String) -> Vector3:
	var p := s.split(",")
	return Vector3(float(p[0]), float(p[1]), float(p[2]))


func _run() -> void:
	var root3 := Node3D.new()
	get_root().add_child(root3)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.03, 0.04, 0.08)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.10, 0.12, 0.2)
	env.ambient_light_energy = float(_env("AMB", "0.35"))
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.glow_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	root3.add_child(we)
	RenderingServer.global_shader_parameter_set("lamp_factor", 1.0)
	RenderingServer.global_shader_parameter_set("origin_shift", Vector3.ZERO)
	var moon := DirectionalLight3D.new()
	moon.rotation_degrees = Vector3(-50, -30, 0)
	moon.light_energy = 0.09
	moon.light_color = Color(0.6, 0.7, 1.0)
	root3.add_child(moon)
	var scene: PackedScene = load("res://assets/models/jet_airliner.glb")
	var inst := scene.instantiate() as Node3D
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/airliner_livery.gdshader")
	mat.set_shader_parameter("livery", float(_env("LIVERY", "0")))
	mat.set_shader_parameter("cabin_glow", 0.8)
	mat.set_shader_parameter("logo_light", 0.65)
	if _env("JF", "1") != "0":
		# JetFinal's numbers (named here: the class pulls in the autoloads).
		mat.set_shader_parameter("final_look", 1.0)
		mat.set_shader_parameter("under_glow", _v3(_env("UNDER", "0.20,0.12,0.06")))
		mat.set_shader_parameter("gear_light", float(_env("GEAR", "1.0")))
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_override = mat
	root3.add_child(inst)
	inst.scale = Vector3.ONE * (38.0 / 1.902)
	var cam := Camera3D.new()
	root3.add_child(cam)
	cam.fov = float(_env("FOV", "18"))
	cam.far = 4000.0
	cam.position = _v3(_env("CAM", "-90,-110,15"))
	cam.look_at(_v3(_env("LOOK", "0,0,0")))
	for i in 8:
		await process_frame
	var out := _env("OUT", "build/final.png")
	get_root().get_texture().get_image().save_png(out)
	print("FINAL_SHOT saved ", out)
	quit()
