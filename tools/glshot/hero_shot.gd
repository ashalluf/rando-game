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
## fires a slow rocket so it is in frame just past the muzzle.
func _initialize() -> void:
	var stage := Node3D.new()
	get_root().add_child(stage)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.62, 0.66, 0.72)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.75, 0.78, 0.84)
	e.ambient_light_energy = 0.6
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	stage.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40.0, 30.0, 0.0)
	sun.light_energy = 1.4
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
	manager.equip(int(OS.get_environment("WEAPON")) if OS.get_environment("WEAPON") != "" else 0)
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
	var yaw := deg_to_rad(float(OS.get_environment("YAW")) if OS.get_environment("YAW") != "" else 90.0)
	var walk := OS.get_environment("WALK") == "1"
	for i in 40:
		if walk:
			Input.action_press("move_forward")
		await physics_frame
		# Keep him on the spot facing -Z however the walk moves him.
		player.global_position = Vector3(0.0, player.global_position.y, 0.0)
		(player.get("visual") as Node3D).rotation.y = 0.0
		# CAM_DIST / CAM_Y close in on the hands (default: the whole figure).
		var dist := float(OS.get_environment("CAM_DIST")) if OS.get_environment("CAM_DIST") != "" else 2.6
		var centre := Vector3(0.0, float(OS.get_environment("CAM_Y")) if OS.get_environment("CAM_Y") != "" else 1.25, -float(OS.get_environment("CAM_FWD")) if OS.get_environment("CAM_FWD") != "" else 0.0)
		cam.global_position = centre + Basis(Vector3.UP, -yaw) * Vector3(0.0, 0.15 * dist / 2.6, -dist)
		cam.look_at(centre, Vector3.UP)
		cam.current = true
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
	get_root().get_texture().get_image().save_png(out)
	print("saved ", out)
	quit()
