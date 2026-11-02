extends SceneTree
## The airliner alone in a few seconds (opengl3 + Xvfb), to judge the livery shader
## (shaders/airliner_livery.gdshader) close up without loading the city:
##
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --rendering-driver opengl3 --path . \
##     --script tools/airport_apron/jet_shot.gd --resolution 1280x720 -- OUT=build/jet.png
##
## Env: LIVERY (0..5, default 2), CAM=x,y,z (metres from the jet's centre; default a three-quarter
## view from its left), LOOK=x,y,z, FOV, DETAIL=0 (the old flat livery), HOUR (the sun: 12).

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
	env.background_color = Color(0.55, 0.7, 0.9)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.62, 0.72)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	var we := WorldEnvironment.new()
	we.environment = env
	root3.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -30, 0)
	sun.light_energy = 1.6
	sun.shadow_enabled = true
	root3.add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(200, 200)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.35, 0.35, 0.34)
	ground.material_override = gm
	root3.add_child(ground)
	var scene: PackedScene = load("res://assets/models/jet_airliner.glb")
	var inst := scene.instantiate() as Node3D
	# AirportTerminal.livery_material()'s numbers (named here: that class pulls in the autoloads).
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/airliner_livery.gdshader")
	mat.set_shader_parameter("livery", float(_env("LIVERY", "2")))
	mat.set_shader_parameter("cabin_glow", 0.8)
	mat.set_shader_parameter("detail", float(_env("DETAIL", "1")))
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_override = mat
	root3.add_child(inst)
	# The model is 1.902 units long along x; the game scales it to 38 m.
	inst.scale = Vector3.ONE * (38.0 / 1.902)
	inst.position = Vector3(0, 0.342 * 38.0 / 1.902, 0)
	var cam := Camera3D.new()
	root3.add_child(cam)
	cam.fov = float(_env("FOV", "40"))
	cam.position = _v3(_env("CAM", "-14,6,30"))
	cam.look_at(_v3(_env("LOOK", "-4,4,0")))
	for i in 8:
		await process_frame
	var out := _env("OUT", "build/jet.png")
	get_root().get_texture().get_image().save_png(out)
	print("JET_SHOT saved ", out)
	quit()
