extends SceneTree
## DrivingFX in the test room, in a minute or two: the room's floor re-dressed as asphalt (or sand,
## DRIVE_SAND=1), a car driven badly in front of a free camera (tools/glshot/drive_fx_stage.gd's
## DRIVE= kinds and knobs), the clock all but frozen, one shot. For the effects' look; the city
## stills (still_shot.gd DRIVE=) are the real thing.
##
##   OUT=/tmp/room.png DRIVE=burnout CAM=0,1.6,12 LOOK=0,0.5,0 xvfb-run -a -s "-screen 0 1280x720x24" \
##     godot --rendering-driver opengl3 --display-driver x11 --audio-driver Dummy --path . \
##     --script tools/glshot/drive_fx_room.gd --resolution 1280x720
##
## Env: OUT png; CAM / LOOK the camera and what it looks at (the car stands DRIVE_DIST ahead of the
## camera, so put LOOK there); FOV; NIGHT=1 darkens the sun and sky (sparks); WET=0.8 sets the
## street wetness; SETTLE frames with the clock frozen.

func _initialize() -> void:
	var level: Node3D = (load("res://scenes/levels/test_box.tscn") as PackedScene).instantiate()
	root.add_child(level)
	await process_frame
	await process_frame
	# An open floor: the room's boxes, gauges and crates out of the way.
	for c in level.get_children():
		if c.name != "Ground" and (c is StaticBody3D or c is RigidBody3D or c is Label3D or (c is MeshInstance3D)):
			c.queue_free()
	for c in get_nodes_in_group("physics_prop"):
		(c as Node).queue_free()
	await process_frame
	var ground := level.get_node_or_null("Ground")
	if ground:
		for mi in ground.find_children("*", "MeshInstance3D", true, false):
			if OS.get_environment("DRIVE_SAND") == "1":
				(mi as MeshInstance3D).material_override = load("res://scripts/world/prop_factory.gd").pbr("sand", 6.0, Color(1, 1, 1))
			else:
				(mi as MeshInstance3D).material_override = load("res://scripts/world/prop_factory.gd").road("asphalt", 7.0, Color(0.79, 0.79, 0.81), 3)
	if OS.get_environment("NIGHT") == "1":
		var sun := level.get_node_or_null("Sun") as DirectionalLight3D
		if sun:
			sun.light_energy = 0.04
		var we := level.get_node_or_null("WorldEnvironment") as WorldEnvironment
		if we and we.environment:
			we.environment.background_energy_multiplier = 0.05
			we.environment.ambient_light_energy = 0.08
	if OS.get_environment("WET") != "":
		load("res://scripts/world/prop_factory.gd").set_wetness(float(OS.get_environment("WET")))
	var player := get_first_node_in_group("player") as Node3D
	var cam := Camera3D.new()
	root.add_child(cam)
	var p := _v("CAM", Vector3(0, 1.6, 12))
	cam.global_position = p
	cam.look_at(_v("LOOK", Vector3(0, 0.5, 0)), Vector3.UP)
	cam.fov = float(_env("FOV", "50"))
	cam.far = 2000.0
	cam.make_current()
	# The player out of the way, hidden, his own camera and HUD off.
	player.global_position = p + Vector3(30.0, 0.0, 30.0)
	player.visible = false
	for c in player.find_children("*", "Camera3D", true, false):
		(c as Camera3D).current = false
	cam.make_current()
	var hud := level.get_node_or_null("DebugHud")
	if hud:
		hud.queue_free()
	await process_frame
	cam.make_current()
	print("room cam ", cam.global_position, " current ", cam.current)
	if OS.get_environment("DRIVE_SAND") == "1":
		load("res://scripts/vehicles/driving_fx.gd").set("force_surface", 2)
	await load("res://tools/glshot/drive_fx_stage.gd").stage(self, _env("DRIVE", "burnout"), cam)
	Engine.time_scale = 0.0005
	for i in int(_env("SETTLE", "4")):
		await process_frame
	var out := _env("OUT", "/tmp/drive_fx_room.png")
	root.get_texture().get_image().save_png(out)
	print("saved ", out)
	quit()


func _env(k: String, d: String) -> String:
	var v := OS.get_environment(k)
	return v if v != "" else d


func _v(k: String, d: Vector3) -> Vector3:
	var s := OS.get_environment(k)
	if s == "":
		return d
	var a := s.split(",")
	return Vector3(a[0].to_float(), a[1].to_float(), a[2].to_float())
