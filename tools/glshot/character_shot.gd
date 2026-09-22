extends SceneTree
## One character, close and front-on, frozen mid-stride - for judging a rig's pose, which the
## city camera cannot do: from a street camera a pedestrian is eighty pixels tall.
##
##   OUT=ped.png MODEL=res://assets/models/pedestrian_d_anim.glb PHASE=0.25 \
##     LIBGL_ALWAYS_SOFTWARE=1 xvfb-run -a -s "-screen 0 1280x720x24" godot \
##     --rendering-driver opengl3 --display-driver x11 --audio-driver Dummy --path . \
##     --script tools/glshot/character_shot.gd --resolution 900x900
##
## Env: MODEL (rigged .glb), OUT (png), CLIP (default the walk), PHASE (0..1 through the clip -
## 0.25 is a full stride with the arms at the ends of their swing, which is where a bad arm
## pose is worst), YAW (degrees to orbit the camera; 0 is front-on, 90 is the side).
## The rig fixes are applied exactly as the game applies them (Pedestrian.prepare_rig and
## fix_arm_pose), loaded dynamically because this script compiles before the autoloads exist.
func _initialize() -> void:
	var model := OS.get_environment("MODEL")
	if model == "":
		model = "res://assets/models/pedestrian_d_anim.glb"
	var clip := OS.get_environment("CLIP")
	if clip == "":
		clip = "Casual_Walk_inplace"
	var phase := 0.25
	if OS.get_environment("PHASE") != "":
		phase = float(OS.get_environment("PHASE"))
	var yaw := 0.0
	if OS.get_environment("YAW") != "":
		yaw = deg_to_rad(float(OS.get_environment("YAW")))

	var root := Node3D.new()
	get_root().add_child(root)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.62, 0.66, 0.72)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.75, 0.78, 0.84)
	e.ambient_light_energy = 0.6
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38.0, 30.0, 0.0)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	root.add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(12.0, 12.0)
	ground.mesh = plane
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.46, 0.46, 0.47)
	ground.material_override = gm
	root.add_child(ground)

	var packed: PackedScene = load(model)
	if packed == null:
		print("character_shot: cannot load ", model)
		quit()
		return
	var inst: Node3D = packed.instantiate()
	root.add_child(inst)
	await process_frame
	var ped_script = load("res://scripts/npc/pedestrian.gd")
	ped_script.prepare_rig(inst)
	var anims := inst.find_children("*", "AnimationPlayer", true, false)
	if not anims.is_empty():
		var ap: AnimationPlayer = anims[0]
		ped_script.fix_arm_pose(ap, model)
		if ap.has_animation(clip):
			ap.play(clip)
			ap.seek(ap.get_animation(clip).length * phase, true)
			ap.pause()
		else:
			print("character_shot: no clip ", clip, " in ", ap.get_animation_list())

	var cam := Camera3D.new()
	cam.fov = 40.0
	var dist := 3.4
	cam.position = Vector3(sin(yaw) * dist, 1.05, cos(yaw) * dist)
	root.add_child(cam)
	cam.look_at(Vector3(0.0, 0.92, 0.0), Vector3.UP)
	cam.current = true
	for i in 12:
		await process_frame
	var out := OS.get_environment("OUT")
	if out == "":
		out = "character_shot.png"
	get_root().get_texture().get_image().save_png(out)
	print("saved ", out)
	quit()
