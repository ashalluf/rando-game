extends Node
## The wingsuit in seconds, in the test room (no city), through whatever renderer runs it:
##   OUT=/tmp/ws.png LOOK=150,-12 INPUT=0.5,0 TIME=1.5 xvfb-run -a -s "-screen 0 1280x720x24" godot \
##     --rendering-driver opengl3 --display-driver x11 --audio-driver Dummy --path . \
##     tools/wingsuit/glide_shot.tscn --resolution 1280x720
## LOOK = camera yaw off his heading and pitch (degrees); INPUT = the stick (roll, pitch);
## TIME = seconds flown; DIST = camera distance (m); FOV = the camera's (degrees); SKID=1 stages a skid on the floor instead.

func _ready() -> void:
	var level: Node = load("res://scenes/levels/test_box.tscn").instantiate()
	get_tree().root.add_child.call_deferred(level)
	for i in 20:
		await get_tree().process_frame
	var player := get_tree().get_first_node_in_group("player") as CharacterBody3D
	var suit: Node = player.get("wingsuit")
	var rig: Node3D = player.get_node("CameraRig")
	var env := func(k: String, d: String) -> String:
		return OS.get_environment(k) if OS.get_environment(k) != "" else d
	var skid: bool = env.call("SKID", "0") == "1"
	player.global_position = Vector3(0, 8.0 if skid else 150.0, 60)
	player.velocity = Vector3(0, -3, -(55.0 if skid else 45.0))
	await get_tree().physics_frame
	await get_tree().physics_frame
	suit.call("open")
	var stick: PackedStringArray = (env.call("INPUT", "0,0") as String).split(",")
	suit.call("force_input", Vector2(float(stick[0]), float(stick[1])))
	var t := 0.0
	var want := float(env.call("TIME", "1.5"))
	while t < want:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	suit.set("chase_after", 1.0e9)
	var look: PackedStringArray = (env.call("LOOK", "150,-12") as String).split(",")
	rig.call("set_look", rad_to_deg(float(suit.get("heading"))) + float(look[0]), float(look[1]))
	if env.call("DIST", "") != "":
		suit.set("camera_extra", float(env.call("DIST", "")) - 6.5)
	if env.call("FOV", "") != "":
		suit.set("_base_fov", float(env.call("FOV", "")))
		suit.set("fov_extra", 0.0)
	Engine.time_scale = 0.001
	for i in 8:
		await get_tree().process_frame
	var cam := get_viewport().get_camera_3d()
	print("GLIDE state %s speed %.1f cam->player %.1f m, fov %.1f" % [suit.get("state"), player.velocity.length(), cam.global_position.distance_to(player.global_position), cam.fov])
	var img := get_viewport().get_texture().get_image()
	img.save_png(env.call("OUT", "/tmp/ws.png"))
	get_tree().quit()
