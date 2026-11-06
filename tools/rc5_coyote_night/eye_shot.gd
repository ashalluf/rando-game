extends SceneTree
## The wildlife's eyeshine alone, in seconds (rc5-coyote-night): a coyote, a raccoon and a deer on a
## dark ground under one warm lamp, lamp_factor 1, facing the lens at DIST metres (default 8) - and
## the same row turned side-on at the right. Opengl3 under Xvfb (needs a real renderer):
##   OUT=eyes.png xvfb-run -a -s "-screen 0 1280x720x24" godot --rendering-driver opengl3 \
##     --display-driver x11 --audio-driver Dummy --path . --script tools/rc5_coyote_night/eye_shot.gd
## Env: DIST, SPECIES (comma list), FOV, TURN (degrees off facing the lens).

func _initialize() -> void:
	RenderingServer.global_shader_parameter_set("lamp_factor", 1.0)
	var root3 := Node3D.new()
	root.add_child(root3)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.01, 0.012, 0.025)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.05, 0.06, 0.09)
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	var we := WorldEnvironment.new()
	we.environment = env
	root3.add_child(we)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(80, 80)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.12, 0.12, 0.12)
	ground.material_override = gm
	root3.add_child(ground)
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.75, 0.45)
	lamp.light_energy = 6.0
	lamp.omni_range = 30.0
	lamp.position = Vector3(3, 7, -6)
	root3.add_child(lamp)
	var dist := float(OS.get_environment("DIST")) if OS.get_environment("DIST") != "" else 8.0
	var turn := deg_to_rad(float(OS.get_environment("TURN")) if OS.get_environment("TURN") != "" else 0.0)
	var names := (OS.get_environment("SPECIES") if OS.get_environment("SPECIES") != "" else "coyote,raccoon,deer").split(",")
	var cam := Camera3D.new()
	cam.position = Vector3(0, 1.4, 0)
	cam.fov = float(OS.get_environment("FOV")) if OS.get_environment("FOV") != "" else 40.0
	cam.look_at_from_position(cam.position, Vector3(0, 0.4, -dist))
	root3.add_child(cam)
	cam.make_current()
	var ws := load("res://scripts/npc/wild_animal.gd")
	for i in names.size():
		for k in 2:
			var an: Node3D = ws.new()
			an.call("setup", names[i], 11 + i)
			an.set("calm", true)
			var x := (float(i) - float(names.size() - 1) * 0.5) * 1.6 + (float(k) - 0.5) * 6.0
			an.position = Vector3(x, 0, -dist)
			# yaw 0 faces -z: turned PI faces the lens (+z).
			an.set("_yaw", PI + turn + (0.0 if k == 0 else PI * 0.5))
			root3.add_child(an)
	for i in 30:
		await process_frame
	var out := OS.get_environment("OUT") if OS.get_environment("OUT") != "" else "eyes.png"
	root.get_texture().get_image().save_png(out)
	print("EYES saved ", out)
	quit()
