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
## (hold aim: the far blur past the crosshair's target) | wheel (the weapon wheel open);
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
