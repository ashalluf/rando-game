extends SceneTree
## Close-ups of crowd faces, the camera framed on each person's Head bone - for judging the face
## pass (CrowdFaces) on several rigs from one load.
##
##   OUT=faces.png MODELS=res://assets/models/crowd_a.glb,res://assets/models/crowd_c.glb \
##     LIBGL_ALWAYS_SOFTWARE=1 xvfb-run -a -s "-screen 0 1280x720x24" godot --rendering-driver opengl3 \
##     --display-driver x11 --audio-driver Dummy --path . --script tools/crowd_faces/face_shot.gd
##
## Writes OUT_<i>.png per person and OUT_grid.png (all of them side by side, square crops).
## Env: MODELS, LOOK (default 0: own clothes), CLIP (default life/idle), DIST (metres from the
## face, default 0.7), YAW (degrees round the person, default 15), FOV (default 30), NIGHT=1 (a
## sodium lamp up and behind to the side, the street at night: lamp_factor 1, no sun), STILL=
## "blink,gx,gy" holds the face (face_still), STREET=1 walks the view back to DIST along the road
## (a pavement framing: the camera at eye height). Forward+: --rendering-driver vulkan with lavapipe
## (VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json); a few minutes.
func _initialize() -> void:
	var ped = load("res://scripts/npc/pedestrian.gd")
	var models: Array = Array(OS.get_environment("MODELS").split(",", false))
	if models.is_empty():
		models = ["res://assets/models/crowd_a.glb", "res://assets/models/crowd_c.glb"]
	var look := int(OS.get_environment("LOOK")) if OS.get_environment("LOOK") != "" else 0
	var clip := OS.get_environment("CLIP") if OS.get_environment("CLIP") != "" else "life/idle"
	var dist := float(OS.get_environment("DIST")) if OS.get_environment("DIST") != "" else 0.7
	var yaw := deg_to_rad(float(OS.get_environment("YAW")) if OS.get_environment("YAW") != "" else 15.0)
	var night := OS.get_environment("NIGHT") == "1"
	var root := Node3D.new()
	get_root().add_child(root)
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.55, 0.62, 0.72) if not night else Color(0.015, 0.018, 0.03)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.62, 0.70, 0.82)
	e.ambient_light_energy = 0.45 if not night else 0.05
	e.tonemap_mode = Environment.TONE_MAPPER_AGX
	var we := WorldEnvironment.new()
	we.environment = e
	root.add_child(we)
	RenderingServer.global_shader_parameter_set("lamp_factor", 1.0 if night else 0.0)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38.0, 40.0, 0.0)
	sun.light_energy = 1.3 if not night else 0.0
	sun.shadow_enabled = true
	root.add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40.0, 40.0)
	ground.mesh = plane
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.2, 0.2, 0.21)
	ground.material_override = gm
	root.add_child(ground)
	var people: Array = []
	for i in models.size():
		var inst: Node3D = (load(String(models[i])) as PackedScene).instantiate()
		inst.position = Vector3(float(i) * 3.0, 0.0, 0.0)
		root.add_child(inst)
		people.append(inst)
		if night:
			# A street lamp 4.5 m up, a little behind and to one side, and a weak one in front.
			var lamp := OmniLight3D.new()
			lamp.position = inst.position + Vector3(-1.6, 4.5, -1.2)
			lamp.omni_range = 12.0
			lamp.light_energy = 2.2
			lamp.light_color = Color(1.0, 0.72, 0.42)
			lamp.shadow_enabled = true
			root.add_child(lamp)
			var fill := OmniLight3D.new()
			fill.position = inst.position + Vector3(1.5, 3.0, 4.0)
			fill.omni_range = 10.0
			fill.light_energy = 0.35
			fill.light_color = Color(1.0, 0.85, 0.65)
			root.add_child(fill)
	await process_frame
	var still := OS.get_environment("STILL").split(",", false)
	for i in people.size():
		var inst: Node3D = people[i]
		ped.prepare_rig(inst, look)
		var ap: AnimationPlayer = inst.find_children("*", "AnimationPlayer", true, false)[0]
		ped.fix_arm_pose(ap, String(models[i]))
		var life_path := "res://assets/models/crowd_life/%s_life.res" % String(models[i]).get_file().get_basename()
		if clip.begins_with("life/") and not ap.has_animation_library("life") and ResourceLoader.exists(life_path):
			ap.add_animation_library("life", load(life_path))
		if ap.has_animation(clip):
			ap.play(clip)
			ap.seek(ap.get_animation(clip).length * 0.3, true)
			ap.pause()
		if still.size() >= 3:
			for n in inst.find_children("*", "MeshInstance3D", true, false):
				var sm := (n as MeshInstance3D).material_override as ShaderMaterial
				if sm and not ped.is_hair(n):
					sm = sm.duplicate() as ShaderMaterial
					sm.set_shader_parameter("face_still", Vector4(1.0, float(still[0]), float(still[1]), float(still[2])))
					(n as MeshInstance3D).material_override = sm
	for k in 4:
		await process_frame
	var cam := Camera3D.new()
	cam.fov = float(OS.get_environment("FOV")) if OS.get_environment("FOV") != "" else 30.0
	cam.near = 0.02
	root.add_child(cam)
	cam.current = true
	var out := OS.get_environment("OUT") if OS.get_environment("OUT") != "" else "faces.png"
	var crops: Array[Image] = []
	for i in people.size():
		var inst: Node3D = people[i]
		var skel := inst.find_child("Skeleton3D", true, false) as Skeleton3D
		var head := skel.global_transform * skel.get_bone_global_pose(skel.find_bone("Head"))
		# The face: a little above the head bone and forward of it.
		var fwd := head.basis.z.normalized()
		fwd.y = 0.0
		fwd = fwd.normalized() if fwd.length() > 0.1 else Vector3.BACK
		var face := head.origin + Vector3.UP * 0.07 + fwd * 0.06
		var dir := fwd.rotated(Vector3.UP, yaw)
		cam.position = face + dir * dist + Vector3.UP * float(OS.get_environment("CAM_UP") if OS.get_environment("CAM_UP") != "" else "-0.04")
		cam.look_at(face, Vector3.UP)
		for k in 10:
			await process_frame
		var img := get_root().get_texture().get_image()
		img.save_png(out.get_basename() + "_%d.png" % i)
		var s := mini(img.get_width(), img.get_height())
		var c := img.get_region(Rect2i((img.get_width() - s) / 2, (img.get_height() - s) / 2, s, s))
		c.resize(480, 480, Image.INTERPOLATE_LANCZOS)
		c.convert(Image.FORMAT_RGBA8)
		crops.append(c)
	var grid := Image.create(480 * crops.size(), 480, false, Image.FORMAT_RGBA8)
	for i in crops.size():
		grid.blit_rect(crops[i], Rect2i(0, 0, 480, 480), Vector2i(i * 480, 0))
	grid.save_png(out.get_basename() + "_grid.png")
	print("saved ", out.get_basename(), "_grid.png")
	quit()
