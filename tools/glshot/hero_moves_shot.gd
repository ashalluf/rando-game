extends SceneTree
## The hero's moves (Avatar: the clips of tools/hero/hero_clips.gd, the flight and fall poses, the
## hit flinch, the draw) in the hero_shot room, several stills from ONE load.
##
##   OUT=/tmp/moves SHOTS="moves/land_hero@0.4@0;fly@0@90" LIBGL_ALWAYS_SOFTWARE=1 \
##     xvfb-run -a -s "-screen 0 1280x720x24" godot --rendering-driver opengl3 --display-driver x11 \
##     --audio-driver Dummy --path . --script tools/glshot/hero_moves_shot.gd --resolution 600x700
##
## Each shot is what@seconds@yaw[@cam_dist]; it is saved as OUT_<n>_<what>_<yaw>.png. `what` is a
## clip name (frozen at the seconds; moves/<name> for the hero's moves), or a staged move run for
## that many seconds of game time: idle (standing with the gun), fly (boosting level through the
## air; FLY_TURN degrees a second of turn), climb (boosting up at 45 degrees), fall (falling at
## 40 m/s), hit_front / hit_left / hit_right / hit_back (a round from that side), draw (a weapon
## change), turn (turning on the spot), sprint (on the ground at 13 m/s), aim (raised, firing),
## land_<fall speed> (a landing standing still), roll (a hard landing running), jump (the
## take-off), idle_look / idle_neck / idle_watch / idle_stretch (an idle variant, with the gun).
## yaw orbits the camera (0 front-on, 90 his right side). WEAPON (default 0; -1 none) the gun.
## CAM_Y the height the camera looks at (default 1.0), FOOTIK=0 turns the foot IK off.

func _initialize() -> void:
	var stage := Node3D.new()
	get_root().add_child(stage)
	var env := WorldEnvironment.new()
	var e := Environment.new()
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
	e.ambient_light_energy = 0.45
	e.tonemap_mode = Environment.TONE_MAPPER_AGX
	e.tonemap_exposure = 1.25
	e.tonemap_white = 5.0
	env.environment = e
	stage.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38.0, 35.0, 0.0)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 14.0
	stage.add_child(sun)
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(80.0, 1.0, 80.0)
	shape.shape = box
	shape.position = Vector3(0.0, -0.5, 0.0)
	floor_body.add_child(shape)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(80.0, 80.0)
	floor_mesh.mesh = plane
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.42, 0.41, 0.39)
	floor_mesh.material_override = fm
	floor_body.add_child(floor_mesh)
	stage.add_child(floor_body)
	# A step to stand half on (the foot IK): STEP=1.
	if OS.get_environment("STEP") == "1":
		var step := StaticBody3D.new()
		var ss := CollisionShape3D.new()
		var sb := BoxShape3D.new()
		sb.size = Vector3(1.0, 0.18, 2.0)
		ss.shape = sb
		step.add_child(ss)
		var sm := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = sb.size
		sm.mesh = bm
		var stm := StandardMaterial3D.new()
		stm.albedo_color = Color(0.6, 0.45, 0.3)
		sm.material_override = stm
		step.add_child(sm)
		step.position = Vector3(0.6, 0.09, 0.0)
		stage.add_child(step)
	var player: Node3D = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	stage.add_child(player)
	for i in 4:
		await process_frame
	var manager: Node = player.get("weapon_manager")
	var weapon := int(OS.get_environment("WEAPON")) if OS.get_environment("WEAPON") != "" else 0
	if weapon < 0:
		(manager as Node3D).visible = false
	else:
		manager.equip(weapon)
	var rig: Node = player.get("camera_rig")
	rig.set_look(0.0, 0.0)
	var avatar: Node = player.get("avatar")
	if OS.get_environment("FOOTIK") == "0":
		avatar.set("foot_ik", false)
	var cam := Camera3D.new()
	cam.fov = 40.0
	stage.add_child(cam)
	var visual: Node3D = player.get("visual")
	var out := OS.get_environment("OUT")
	if out == "":
		out = "/tmp/moves"
	var n := 0
	for spec in OS.get_environment("SHOTS").split(";", false):
		var parts := spec.split("@")
		var what := parts[0]
		var secs := float(parts[1]) if parts.size() > 1 else 0.0
		var yaw := deg_to_rad(float(parts[2]) if parts.size() > 2 else 0.0)
		var dist := float(parts[3]) if parts.size() > 3 else 2.8
		player.set_physics_process(true)
		player.global_position = Vector3(0.0, 0.1, 0.0)
		player.set("velocity", Vector3.ZERO)
		visual.rotation.y = 0.0
		avatar.call("debug_reset")
		for i in 3:
			await physics_frame
		var anim: AnimationPlayer = player.find_child("AnimationPlayer", true, false)
		var focus := Vector3(0.0, float(OS.get_environment("CAM_Y")) if OS.get_environment("CAM_Y") != "" else 1.0, 0.0)
		if anim.has_animation(what):
			player.set_physics_process(false)
			anim.play(what, 0.0)
			anim.seek(secs, true)
			anim.speed_scale = 0.0
			for i in 3:
				await process_frame
		else:
			# A staged move: the avatar is told what is going on and runs for `secs` of game time.
			var t := 0.0
			var dt := 1.0 / 60.0
			if what.begins_with("hit_"):
				var side := {"hit_front": Vector3(0, 1.3, -6), "hit_back": Vector3(0, 1.3, 6), "hit_left": Vector3(-6, 1.3, 0), "hit_right": Vector3(6, 1.3, 0)}
				avatar.call("hit_from", player.global_position + (side.get(what, Vector3(0, 1.3, -6)) as Vector3), 60.0)
			elif what == "draw":
				manager.equip((weapon + 1) % 3)
			elif what.begins_with("land_"):
				avatar.call("landed", float(what.trim_prefix("land_")), 0.0)
			elif what.begins_with("roll"):
				avatar.call("landed", 80.0, 12.0)
			elif what == "jump":
				avatar.call("jumped", false)
			elif what.begins_with("idle_"):
				var len: float = anim.get_animation("moves/" + what).length
				avatar.call("_start_oneshot", "moves/" + what, 0.0, len, 1.0, 0.0)
			if OS.get_environment("AIM") == "1" or what == "aim":
				player.set("aim_hold_time", 1.0e6)
				player.notify_fired()
			player.set_physics_process(false)
			var prev_yaw := 0.0
			var fly_turn := deg_to_rad(float(OS.get_environment("FLY_TURN")) if OS.get_environment("FLY_TURN") != "" else 0.0)
			while t < secs:
				var vel := Vector3.ZERO
				var floor := true
				var boosting := false
				match what:
					"fly":
						vel = Basis(Vector3.UP, visual.rotation.y) * Vector3(0, 0.0, -40.0)
						floor = false
						boosting = true
						visual.rotation.y += fly_turn * dt
					"climb":
						vel = Vector3(0, 28.0, -28.0)
						floor = false
						boosting = true
					"fall":
						vel = Vector3(0, -40.0, -3.0)
						floor = false
					"jump":
						vel = Vector3(0, 16.0 - 30.0 * t, 0.0)
						floor = false
					"sprint":
						vel = Vector3(0, 0, -13.0)
					"turn":
						visual.rotation.y += 4.0 * dt
				avatar.call("drive", dt, Vector2(vel.x, vel.z).length(), floor, vel.y, boosting, vel)
				var gun: Node = manager.get("current") if (manager as Node3D).visible else null
				avatar.call("hold_gun", gun, OS.get_environment("AIM") == "1" or what == "aim", dt)
				await physics_frame
				t += dt
			if what == "fly" or what == "climb" or what == "fall":
				focus = Vector3(0.0, 1.0, 0.0)
		var cam_yaw := yaw + visual.rotation.y
		cam.global_position = focus + Basis(Vector3.UP, -cam_yaw) * Vector3(0.0, 0.25 * dist / 3.6, -dist)
		cam.look_at(focus, Vector3.UP)
		cam.current = true
		await process_frame
		await process_frame
		var motion: Node = player.find_child("HeroMotion", true, false)
		if motion:
			print("MOTION %s lift %s hips_drop %.3f fly %.2f fall %.2f" % [what, motion.get("foot_lift"), motion.get("hips_drop"), motion.get("fly"), motion.get("fall")])
		var path := "%s_%02d_%s_%d.png" % [out, n, what.replace("/", "-"), int(rad_to_deg(yaw))]
		get_root().get_texture().get_image().save_png(path)
		print("saved ", path)
		n += 1
		if anim:
			anim.speed_scale = 1.0
	quit()
