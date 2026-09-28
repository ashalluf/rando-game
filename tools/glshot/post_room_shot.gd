extends SceneTree
## CameraPost end to end in the test room (the smoke test's level, small enough for lavapipe):
## the real player, camera rig, gun, HUD and weapon wheel, with the motion blur and the depth of
## field exactly as the game builds them.
##
##   OUT=/tmp/room.png MODE=run xvfb-run -a -s "-screen 0 1280x720x24" godot \
##     --rendering-driver vulkan --display-driver x11 --audio-driver Dummy --path . \
##     --script tools/glshot/post_room_shot.gd --resolution 960x540
##
## Env: OUT png path; MODE still | run (the player carried along at SPEED m/s, the camera
## following as in play) | whip (the view turning RATE degrees a second, a mouse flick) | aim
## (hold aim: the far blur past the crosshair's target) | wheel (the weapon wheel open) | boost
## (really boosting along the view: BOOST_TIME, BOOST_SCALE; the player's BoostTrail);
## MB=0 turns the motion blur off (the "before"); AA=taa (default) | fsr | none; YAW / PITCH the
## view (degrees); WARMUP + FRAMES frames (the engine compiles its motion-vector pipelines in the
## background, and draws no velocity until they are ready); DT the frame time the blur is told
## (1/60: a software frame takes seconds). Prints POST (what CameraPost did) for the last frame.
## Under --rendering-driver opengl3 it shows the Compatibility path: no effect, no errors.

func _initialize() -> void:
	var packed: PackedScene = load("res://scenes/levels/test_box.tscn")
	var level := packed.instantiate()
	root.add_child(level)
	await process_frame
	await process_frame
	var mode := _env("MODE", "run")
	var player := get_first_node_in_group("player") as Node3D
	var post: Node = player.get_node("CameraRig/Post")
	var rig: Node = player.get("camera_rig")
	var dt := float(_env("DT", str(1.0 / 60.0)))
	post.set("fixed_frame_seconds", dt)
	if _env("MB", "1") == "0":
		post.set("motion_blur_enabled", false)
	match _env("AA", "taa"):
		"fsr":
			root.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2
			root.scaling_3d_scale = 0.6
		"none":
			root.use_taa = false
		_:
			root.use_taa = true
	var yaw := float(_env("YAW", "0"))
	var pitch := float(_env("PITCH", "-8"))
	rig.call("set_look", yaw, pitch)
	if mode == "aim":
		Input.action_press("alt_fire")
	elif mode == "wheel":
		Input.action_press("weapon_wheel")
	elif mode == "hurt":
		# Two hits from either side and front-left, health left low, and a hit marker (DamageHud,
		# Crosshair.mark_hit): the frame a firefight leaves on screen.
		var health: Node = player.get("health")
		var p0: Vector3 = player.global_position
		var fwd3 := Vector3(-sin(deg_to_rad(yaw)), 0.0, -cos(deg_to_rad(yaw)))
		var right3 := fwd3.cross(Vector3.UP)
		health.call("take_damage", 90.0, p0 + right3 * 12.0)
		health.call("take_damage", 70.0, p0 + fwd3 * 10.0 - right3 * 8.0)
		health.call("take_damage", 40.0, p0 - fwd3 * 10.0)
		# Loaded, not named: this script compiles before the autoloads exist, and the crosshair
		# names Player, which uses them.
		load("res://scripts/ui/crosshair.gd").mark_hit(true)
		for i in 3:
			await process_frame
	elif mode == "land":
		# Dropped from DROP metres (default 40: a full slam), the clock at a tick a frame, the shot
		# LAND_AFTER seconds of game time after touching down (LandingFX: dust ring, crater, shove).
		player.global_position.y += float(_env("DROP", "40"))
		Engine.time_scale = 0.125
		var after := 0.0
		for i in 2000:
			await process_frame
			if player.is_on_floor():
				after += root.get_process_delta_time()
				if after >= float(_env("LAND_AFTER", "0.15")):
					break
		Engine.time_scale = 0.0005
	elif mode == "pause":
		# The pause menu over the room (the room has no DayNight or Weather, so its pickers
		# have nothing to drive here; the look is what this is for).
		var menu: Node = (load("res://scenes/ui/pause_menu.tscn") as PackedScene).instantiate()
		level.add_child(menu)
		await process_frame
		menu.call("open")
		for i in 12:
			await process_frame
	elif mode == "fire":
		# Hold the trigger for FIRE_TIME seconds of game time with the clock at FIRE_SCALE: the
		# muzzle flash, tracers, impacts and the rifle's spent cases (BrassCasings) in flight.
		# WEAPON=n switches to that slot first (2 the rocket launcher, 3 the shotgun).
		if _env("WEAPON", "") != "":
			var slot := "weapon_%s" % _env("WEAPON", "1")
			Input.action_press(slot)
			await process_frame
			Input.action_release(slot)
			for i in 10:
				await process_frame
		if _env("AIM", "0") == "1":
			Input.action_press("alt_fire")
			for i in 20:
				await process_frame
		Input.action_press("fire")
		Engine.time_scale = float(_env("FIRE_SCALE", "0.05"))
		var fired := 0.0
		while fired < float(_env("FIRE_TIME", "0.6")):
			await process_frame
			fired += root.get_process_delta_time()
		Input.action_release("fire")
		Engine.time_scale = float(_env("FIRE_AFTER_SCALE", "0.0005"))
	elif mode == "boost":
		# The real boost (BoostTrail and all), the clock slowed to BOOST_SCALE (default 0.02: the
		# room renders fast; in a slow scene 0.125 is a tick a frame, since Godot caps a frame at
		# eight ticks), flown for BOOST_TIME seconds of game time before the shot.
		player.global_position.y += float(_env("START_Y", "0"))
		Input.action_press("boost")
		Engine.time_scale = float(_env("BOOST_SCALE", "0.02"))
		var flown := 0.0
		var frames := 0
		while flown < float(_env("BOOST_TIME", "1.2")):
			await process_frame
			flown += root.get_process_delta_time()
			frames += 1
		print("boost: %d frames, %.2f s, %.1f m/s at %s" % [frames, flown, (player.get("velocity") as Vector3).length(), player.global_position])
	var speed := float(_env("SPEED", "45"))
	var rate := float(_env("RATE", "280"))
	var start := player.global_position
	var forward := Vector3(-sin(deg_to_rad(yaw)), 0.0, -cos(deg_to_rad(yaw)))
	var total := int(_env("WARMUP", "30")) + int(_env("FRAMES", "8"))
	var t := 0.0
	for i in total:
		t += dt
		match mode:
			"run":
				player.global_position = start + forward * speed * t
			"whip":
				rig.call("set_look", yaw + rate * t, pitch)
		if i < total - 1:
			await process_frame
	# Capture the frame drawn from the last move (see motion_blur_shot.gd).
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var out := _env("OUT", "/tmp/post_room_shot.png")
	img.save_png(out)
	var effect: Variant = post.get("effect")
	var cam: Camera3D = player.get("camera")
	var attrs := cam.attributes as CameraAttributesPractical
	print("POST mode=%s mb=%s effect=%s ready=%s drawn=%d | dof far=%s %.1f m +%.1f amount %.3f -> %s" % [
			mode, _env("MB", "1"), str(effect != null), str(effect.ready if effect else false),
			effect.frames_drawn if effect else -1, str(attrs.dof_blur_far_enabled),
			attrs.dof_blur_far_distance, attrs.dof_blur_far_transition, attrs.dof_blur_amount, out])
	Input.action_release("alt_fire")
	Input.action_release("weapon_wheel")
	quit()


static func _env(key: String, fallback: String) -> String:
	var v := OS.get_environment(key)
	return v if v != "" else fallback
