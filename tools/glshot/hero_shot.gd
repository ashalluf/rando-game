extends SceneTree
## The hero holding a gun, close up, in a plain lit room - for judging the grip and the arm pose,
## which a street camera shows at forty pixels tall.
##
##   OUT=hero.png WEAPON=0 AIM=1 YAW=90 LIBGL_ALWAYS_SOFTWARE=1 xvfb-run -a -s "-screen 0 1280x720x24" \
##     godot --rendering-driver opengl3 --display-driver x11 --audio-driver Dummy --path . \
##     --script tools/glshot/hero_shot.gd --resolution 900x900
##
## Env: OUT (png), WEAPON (0 AK, 1 rocket launcher, 2 shotgun), AIM=1 raises it to the
## shoulder, YAW (degrees to orbit the camera round the hero; 0 is front-on, 90 his right side),
## WALK=1 plays the walk clip (the IK has to hold the gun whatever the legs do), CAM_DIST and
## CAM_Y (and CAM_FWD, metres in front of him) bring the camera in on the hands, DEBUG=1 marks the IK targets, ROCKET=1 (with WEAPON=1)
## fires a slow rocket so it is in frame just past the muzzle. WEAPON=-1 puts the gun away (arms on
## the clip); CLIP=Idle|Casual_Walk_inplace|run_fast_3_inplace with SEEK (seconds) freezes a clip
## frame. The light is the city's grade (AgX, the look LUT, sky ambient, a shadowed sun at
## SUN_PITCH / SUN_YAW); FLAT=1 is the old flat-lit room. CAM_AT=hands|head aims at the hands
## or the head wherever the pose put them (CAM_Y is then an offset from there). Run it with --rendering-driver vulkan
## (lavapipe) for the Forward+ look: subsurface skin and SSAO only exist there.
func _initialize() -> void:
	var stage := Node3D.new()
	get_root().add_child(stage)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	var sun := DirectionalLight3D.new()
	if OS.get_environment("FLAT") == "1":
		e.background_mode = Environment.BG_COLOR
		e.background_color = Color(0.62, 0.66, 0.72)
		e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		e.ambient_light_color = Color(0.75, 0.78, 0.84)
		e.ambient_light_energy = 0.6
		e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		sun.rotation_degrees = Vector3(-40.0, 30.0, 0.0)
		sun.light_energy = 1.4
	else:
		# The city's own grade (city.tscn): AgX, the look LUT, sky ambient, a shadowed sun -
		# so skin, velour and gold are judged under the light they are played in.
		var sky_mat := ProceduralSkyMaterial.new()
		sky_mat.sky_top_color = Color(0.32, 0.46, 0.68)
		sky_mat.sky_horizon_color = Color(0.66, 0.70, 0.74)
		sky_mat.ground_horizon_color = Color(0.52, 0.50, 0.47)
		sky_mat.ground_bottom_color = Color(0.30, 0.28, 0.26)
		var sky := Sky.new()
		sky.sky_material = sky_mat
		e.background_mode = Environment.BG_SKY
		e.sky = sky
		e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		e.ambient_light_energy = float(OS.get_environment("AMBIENT")) if OS.get_environment("AMBIENT") != "" else 0.45
		e.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
		e.tonemap_mode = Environment.TONE_MAPPER_AGX
		e.tonemap_exposure = 1.25
		e.tonemap_white = 5.0
		var grade := Gradient.new()
		grade.offsets = PackedFloat32Array([0, 0.14, 0.28, 0.45, 0.62, 0.78, 0.9, 1])
		grade.colors = PackedColorArray([Color(0.035, 0.036, 0.041), Color(0.172, 0.176, 0.180), Color(0.318, 0.307, 0.290), Color(0.470, 0.448, 0.412), Color(0.628, 0.598, 0.548), Color(0.772, 0.738, 0.680), Color(0.877, 0.845, 0.786), Color(0.962, 0.936, 0.878)])
		var lut := GradientTexture1D.new()
		lut.gradient = grade
		lut.width = 256
		e.adjustment_enabled = true
		e.adjustment_saturation = 1.32
		e.adjustment_color_correction = lut
		e.ssao_enabled = true
		sun.rotation_degrees = Vector3(float(OS.get_environment("SUN_PITCH")) if OS.get_environment("SUN_PITCH") != "" else -38.0, float(OS.get_environment("SUN_YAW")) if OS.get_environment("SUN_YAW") != "" else 35.0, 0.0)
		sun.light_energy = 1.3
		sun.light_color = Color(1.0, 0.96, 0.9)
		sun.shadow_enabled = true
		sun.directional_shadow_max_distance = 12.0
	env.environment = e
	stage.add_child(env)
	stage.add_child(sun)
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40.0, 1.0, 40.0)
	shape.shape = box
	shape.position = Vector3(0.0, -0.5, 0.0)
	floor_body.add_child(shape)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40.0, 40.0)
	floor_mesh.mesh = plane
	floor_body.add_child(floor_mesh)
	stage.add_child(floor_body)
	var player: Node3D = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	stage.add_child(player)
	for i in 4:
		await process_frame
	var manager: Node = player.get("weapon_manager")
	var weapon := int(OS.get_environment("WEAPON")) if OS.get_environment("WEAPON") != "" else 0
	if weapon < 0:
		(manager as Node3D).visible = false # no gun: the arms go back to the clip
	else:
		manager.equip(weapon)
	var rig: Node = player.get("camera_rig")
	rig.set_look(0.0, 0.0)
	if OS.get_environment("AIM") == "1":
		player.notify_fired()
		player.set("aim_hold_time", 1.0e6)
		player.notify_fired()
	# DEBUG=1 marks the IK targets: red where the right wrist should be, blue the left.
	if OS.get_environment("DEBUG") == "1":
		for pair in [["GripRight", Color(1, 0, 0)], ["GripLeft", Color(0, 0.3, 1)]]:
			var target: Node3D = manager.get_node_or_null(pair[0])
			if target:
				var dot := MeshInstance3D.new()
				var sphere := SphereMesh.new()
				sphere.radius = 0.025
				sphere.height = 0.05
				dot.mesh = sphere
				var m := StandardMaterial3D.new()
				m.albedo_color = pair[1]
				m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				m.no_depth_test = true
				dot.material_override = m
				target.add_child(dot)
	var cam := Camera3D.new()
	cam.fov = 40.0
	stage.add_child(cam)
	# CAM_AT=hands aims at the middle of the two hands as the IK left them (CAM_DIST, YAW and
	# CAM_Y as an offset still apply), CAM_AT=head at the head: the stance moves both about.
	var aim_at := OS.get_environment("CAM_AT")
	var at := [Vector3.INF]
	var sk0: Skeleton3D = player.find_child("Skeleton3D", true, false)
	if aim_at != "" and sk0:
		sk0.skeleton_updated.connect(func() -> void:
			var names: Array = ["RightHand", "LeftHand"] if aim_at == "hands" else ["Head", "Head"]
			var a := sk0.to_global(sk0.get_bone_global_pose(sk0.find_bone(names[0])).origin)
			var b := sk0.to_global(sk0.get_bone_global_pose(sk0.find_bone(names[1])).origin)
			at[0] = (a + b) * 0.5)
	var yaw := deg_to_rad(float(OS.get_environment("YAW")) if OS.get_environment("YAW") != "" else 90.0)
	var walk := OS.get_environment("WALK") == "1"
	# CAM_DIST / CAM_Y close in on the hands (default: the whole figure).
	var place := func() -> void:
		var dist := float(OS.get_environment("CAM_DIST")) if OS.get_environment("CAM_DIST") != "" else 2.6
		var centre := Vector3(0.0, float(OS.get_environment("CAM_Y")) if OS.get_environment("CAM_Y") != "" else 1.25, -float(OS.get_environment("CAM_FWD")) if OS.get_environment("CAM_FWD") != "" else 0.0)
		if at[0] != Vector3.INF:
			centre = at[0] + Vector3(0.0, float(OS.get_environment("CAM_Y")) if OS.get_environment("CAM_Y") != "" else 0.0, 0.0)
		cam.global_position = centre + Basis(Vector3.UP, -yaw) * Vector3(0.0, 0.15 * dist / 2.6, -dist)
		cam.look_at(centre, Vector3.UP)
		cam.current = true
	for i in 40:
		if walk:
			Input.action_press("move_forward")
		await physics_frame
		# Keep him on the spot facing -Z however the walk moves him.
		player.global_position = Vector3(0.0, player.global_position.y, 0.0)
		(player.get("visual") as Node3D).rotation.y = 0.0
		place.call()
	# ROCKET=1 (with WEAPON=1 AIM=1): a rocket just out of the launcher, crawling so it is in frame.
	if OS.get_environment("ROCKET") == "1":
		var launcher: Node = manager.get("current")
		if launcher and launcher.has_method("launch_rocket"):
			var muzzle: Node3D = launcher.get("muzzle")
			var shot: Node3D = launcher.launch_rocket(muzzle.global_position, -(launcher as Node3D).global_basis.z)
			shot.set("speed", 3.0)
			for i in 24:
				await physics_frame
	var sk: Skeleton3D = player.find_child("Skeleton3D", true, false)
	var clip := OS.get_environment("CLIP")
	if clip != "":
		var anim: AnimationPlayer = player.find_child("AnimationPlayer", true, false)
		if anim and anim.has_animation(clip):
			player.set_physics_process(false) # or Avatar.drive() picks its own clip back
			anim.play(clip, 0.0)
			anim.seek(float(OS.get_environment("SEEK")) if OS.get_environment("SEEK") != "" else 0.0, true)
			anim.speed_scale = 0.0
			for i in 3:
				await process_frame
			place.call() # the clip's frame moved the head and hands
			await process_frame
	if sk:
		for b in ["Hips", "RightArm", "RightHand", "LeftHand"]:
			print(b, " at ", sk.to_global(sk.get_bone_global_pose(sk.find_bone(b)).origin))
	print("player at ", player.global_position, " mount at ", (manager as Node3D).global_position, " grip R ", (manager.get_node_or_null("GripRight") as Node3D).global_position if manager.get_node_or_null("GripRight") else "none")
	if sk and manager.get_node_or_null("GripRight"):
		var gr: Node3D = manager.get_node("GripRight")
		var hb := sk.find_bone("RightHand")
		var chain := sk.get_bone_pose(hb)
		var p := sk.get_bone_parent(hb)
		while p >= 0:
			chain = sk.get_bone_pose(p) * chain
			p = sk.get_bone_parent(p)
		var hand_world := (sk.global_transform * chain)
		var hb2 := hand_world.basis.orthonormalized()
		var mb := gr.global_basis.orthonormalized()
		print("hand Y ", hb2.y.snapped(Vector3.ONE*0.01), " want Y ", mb.y.snapped(Vector3.ONE*0.01), " hand Z ", hb2.z.snapped(Vector3.ONE*0.01), " want Z ", mb.z.snapped(Vector3.ONE*0.01))
		print("hand at ", hand_world.origin, " marker at ", gr.global_position, " global_pose hand ", sk.to_global(sk.get_bone_global_pose(hb).origin))
	var out := OS.get_environment("OUT")
	if out == "":
		out = "hero.png"
	await process_frame
	# What this frame cost (only under a real renderer; --headless reads zero).
	print("GEO tris=%d draws=%d objects=%d" % [int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)), int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))])
	get_root().get_texture().get_image().save_png(out)
	print("saved ", out)
	quit()
