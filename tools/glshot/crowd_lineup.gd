extends SceneTree
## Several crowd rigs side by side in one frame, frozen in a clip - for judging the crowd as a set
## (skin tones, builds, clothes, hair against each other) in one render instead of one each.
##
##   OUT=lineup.png MODELS=res://assets/models/crowd_a.glb,res://assets/models/crowd_b.glb LOOKS=0,1 \
##     LIBGL_ALWAYS_SOFTWARE=1 xvfb-run -a -s "-screen 0 1920x1080x24" godot \
##     --rendering-driver opengl3 --display-driver x11 --audio-driver Dummy --path . \
##     --script tools/glshot/crowd_lineup.gd --resolution 1600x900
##
## Env: MODELS (comma list of rigged .glb; default every Pedestrian.MODELS entry), LOOKS (comma
## list, used in turn; default 0, which keeps each model's own clothes; -1 leaves the plain glTF
## material), SPACING (metres between people, default 0.85), CLIP (default the walk), PHASE (0..1,
## default 0.25) and PHASE_STEP (added per person so the row is not in step), YAW (degrees the
## camera orbits; 90 is the side), CAM_DIST / CAM_Y / AIM_Y / FOV, BODY=mid|far (the welded middle
## / far bodies, hair cards hidden, as the game draws them past mid_body_range), SUN_YAW, SKY=1 for
## a brighter outdoor fill, SHOTS="name,yaw,dist,cam_y,aim_y,fov,aim_x;..." for several views from one
## load (OUT_<name>.png each; empty fields keep the values above). Applies the rigs exactly as the game does (Pedestrian.prepare_rig and
## fix_arm_pose), loaded dynamically because this compiles before the autoloads exist.
func _initialize() -> void:
	var ped_script = load("res://scripts/npc/pedestrian.gd")
	var models: Array = []
	if OS.get_environment("MODELS") != "":
		models = Array(OS.get_environment("MODELS").split(","))
	else:
		models = Array(ped_script.MODELS)
	var looks: Array = [0]
	if OS.get_environment("LOOKS") != "":
		looks = Array(OS.get_environment("LOOKS").split(",")).map(func(x): return int(x))
	var clip := OS.get_environment("CLIP") if OS.get_environment("CLIP") != "" else "Casual_Walk_inplace"
	var phase := float(OS.get_environment("PHASE")) if OS.get_environment("PHASE") != "" else 0.25
	var phase_step := float(OS.get_environment("PHASE_STEP")) if OS.get_environment("PHASE_STEP") != "" else 0.13
	var spacing := float(OS.get_environment("SPACING")) if OS.get_environment("SPACING") != "" else 0.85
	var yaw := deg_to_rad(float(OS.get_environment("YAW"))) if OS.get_environment("YAW") != "" else 0.0
	var width := spacing * float(models.size() - 1)
	var dist := float(OS.get_environment("CAM_DIST")) if OS.get_environment("CAM_DIST") != "" else maxf(4.0, width * 1.25 + 2.5)
	var cam_y := float(OS.get_environment("CAM_Y")) if OS.get_environment("CAM_Y") != "" else 1.15
	var aim_y := float(OS.get_environment("AIM_Y")) if OS.get_environment("AIM_Y") != "" else 0.9
	var sun_yaw := 30.0 + (float(OS.get_environment("SUN_YAW")) if OS.get_environment("SUN_YAW") != "" else 0.0)
	var body := OS.get_environment("BODY")

	var root := Node3D.new()
	get_root().add_child(root)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.62, 0.66, 0.72)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.75, 0.78, 0.84)
	e.ambient_light_energy = 0.8 if OS.get_environment("SKY") == "1" else 0.6
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38.0, sun_yaw, 0.0)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	root.add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40.0, 40.0)
	ground.mesh = plane
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.46, 0.46, 0.47)
	ground.material_override = gm
	root.add_child(ground)

	var insts: Array = []
	for i in models.size():
		var packed: PackedScene = load(String(models[i]).strip_edges())
		if packed == null:
			print("crowd_lineup: cannot load ", models[i])
			continue
		var inst: Node3D = packed.instantiate()
		inst.position = Vector3(-width * 0.5 + spacing * float(i), 0.0, 0.0)
		root.add_child(inst)
		insts.append([inst, String(models[i]).strip_edges(), int(looks[i % looks.size()]), fposmod(phase + phase_step * float(i), 1.0)])
	await process_frame
	for rec: Array in insts:
		var inst: Node3D = rec[0]
		ped_script.prepare_rig(inst, rec[2])
		var anims := inst.find_children("*", "AnimationPlayer", true, false)
		if not anims.is_empty():
			var ap: AnimationPlayer = anims[0]
			ped_script.fix_arm_pose(ap, rec[1])
			if ap.has_animation(clip):
				ap.play(clip)
				ap.seek(ap.get_animation(clip).length * float(rec[3]), true)
				ap.pause()
		for node in inst.find_children("*", "MeshInstance3D", true, false):
			var mi := node as MeshInstance3D
			if body != "" and ped_script.is_hair(mi):
				mi.visible = false
			elif mi.skin and body != "":
				mi.mesh = ped_script.far_mesh(mi.mesh, ped_script.get("mid_triangles") if body == "mid" else ped_script.get("far_triangles"))
	var cam := Camera3D.new()
	cam.fov = float(OS.get_environment("FOV")) if OS.get_environment("FOV") != "" else 40.0
	cam.far = 400.0
	root.add_child(cam)
	cam.current = true
	var out := OS.get_environment("OUT") if OS.get_environment("OUT") != "" else "crowd_lineup.png"
	# SHOTS="name,yaw,dist,cam_y,aim_y,fov,aim_x;..." takes several views from one load, each saved as
	# OUT with _name before the extension (empty fields keep the values above).
	var shots: Array = []
	for spec in OS.get_environment("SHOTS").split(";", false):
		shots.append(spec.split(","))
	if shots.is_empty():
		shots.append(PackedStringArray([""]))
	for spec: PackedStringArray in shots:
		var f := func(i: int, fallback: float) -> float:
			return float(spec[i]) if spec.size() > i and spec[i] != "" else fallback
		var y := deg_to_rad(f.call(1, rad_to_deg(yaw)))
		var d: float = f.call(2, dist)
		var ax: float = f.call(6, 0.0)
		cam.fov = f.call(5, cam.fov)
		cam.position = Vector3(ax + sin(y) * d, f.call(3, cam_y), cos(y) * d)
		cam.look_at(Vector3(ax, f.call(4, aim_y), 0.0), Vector3.UP)
		for i in 12:
			await process_frame
		var path := out if spec[0] == "" else out.get_basename() + "_" + spec[0] + "." + out.get_extension()
		get_root().get_texture().get_image().save_png(path)
		print("saved ", path)
	quit()
