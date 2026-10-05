extends SceneTree
## Police station stills in the real city: a free camera at EYE, and with GATE=1 a two-star
## crime by the player and the cruiser it brings out of the nearest station's gate, shot as a
## sequence (SEQ seconds after the dispatch, one frame each: OUT_0.png, OUT_1.png, ...).
##
##   OUT=/tmp/ps.png EYE=3700,14,-1112,140,-8 GATE=1 SEQ=1.5,4,6.5,9 LIBGL_ALWAYS_SOFTWARE=1 \
##     xvfb-run -a -s "-screen 0 1280x720x24" godot --rendering-driver opengl3 --display-driver x11 \
##     --audio-driver Dummy --path . --script tools/glshot/police_station_shot.gd --resolution 1280x720 \
##     -- --spawn=3660,-1110,180,-5 --nohud --hour=12
##
## EYE=x,y,z,yaw,pitch (true world; yaw 0 looks north, 90 west), FOV, FRAMES (streaming frames
## first, default 40), SHOTS="x,y,z,yaw,pitch;..." more stills from the same load (OUT_s1.png...),
## GEO=1 prints each frame's triangles and draws. Classes are reached through load(): this script
## compiles before the autoloads exist.

var _cam: Camera3D


func _initialize() -> void:
	Engine.set_meta("postfx_motion_blur", 0.0)
	# A lighter world than the game's (the far city, the LOD ring, the crowd and traffic caps
	# down), so a whole-city frame fits a software renderer: what matters is the station's block.
	var c: Node = (load("res://scenes/levels/city.tscn") as PackedScene).instantiate()
	c.set("far_city_radius", 1500.0)
	c.set("far_city_immediate_radius", 1500.0)
	c.set("lod_radius_blocks", 3)
	c.set("keep_radius_blocks", 3)
	c.set("max_pedestrians", 80)
	c.set("traffic_cars", 24)
	root.add_child.call_deferred(c)
	set_deferred("current_scene", c)
	var frames := int(OS.get_environment("FRAMES")) if OS.get_environment("FRAMES") != "" else 40
	for i in frames:
		await process_frame
		if current_scene and i == 3 and current_scene.has_method("finish_far_city"):
			current_scene.call("finish_far_city")
	var city := current_scene
	var out := OS.get_environment("OUT") if OS.get_environment("OUT") != "" else "/tmp/police_station.png"
	var eye := OS.get_environment("EYE")
	_place(eye)
	for i in 12:
		await process_frame
	if OS.get_environment("GATE") == "1":
		var police: Node = city.get_node("Police")
		var plan: Variant = city.get("plan")
		var ps: GDScript = load("res://scripts/world/police_station.gd")
		var p := eye.split(",")
		var at := Vector2(p[0].to_float(), p[2].to_float())
		var st: Dictionary = ps.call("nearest", plan, at, 800.0)
		print("STATION ", st.get("name"), " front ", st.get("front"))
		police.set("enabled", true)
		police.call("set_wanted", 2)
		police.set("_dispatch_t", 1e9)
		var ws: Node = root.get_node("/root/WorldState")
		var player := city.get_tree().get_first_node_in_group("player") as Node3D
		var pw: Vector3 = ws.call("to_world", player.global_position)
		var goal := Vector2(pw.x, pw.z) + Vector2(60.0, 80.0)
		print("DISPATCH ", police.call("_dispatch_from_station", st, goal))
		var seq := (OS.get_environment("SEQ") if OS.get_environment("SEQ") != "" else "1.5,4,6.5,9").split(",")
		var ticks := 0
		var k := 0
		for t: String in seq:
			var want := int(t.to_float() * 60.0)
			while ticks < want:
				await physics_frame
				ticks += 1
			_place(eye)
			await process_frame
			var path := out.get_basename() + "_%d.png" % k
			root.get_texture().get_image().save_png(path)
			print("SAVED ", path, " at %.1f s gate %.2f" % [ticks / 60.0, float(ps.call("gate_open_amount", self, st))])
			k += 1
	else:
		Engine.time_scale = 0.0005
		for i in 4:
			await process_frame
		root.get_texture().get_image().save_png(out)
		print("SAVED ", out)
		_geo()
		var shots := OS.get_environment("SHOTS")
		if shots != "":
			var n := 1
			for s: String in shots.split(";"):
				Engine.time_scale = 1.0
				_place(s)
				for i in 20:
					await process_frame
				Engine.time_scale = 0.0005
				for i in 4:
					await process_frame
				var path := out.get_basename() + "_s%d.png" % n
				root.get_texture().get_image().save_png(path)
				print("SAVED ", path)
				_geo()
				n += 1
	quit()


func _geo() -> void:
	if OS.get_environment("GEO") != "1":
		return
	print("GEO tris %d draws %d objects %d" % [Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)])


func _place(eye: String) -> void:
	var p := eye.split(",")
	if p.size() < 5:
		return
	var ws: Node = root.get_node("/root/WorldState")
	var at := Vector3(p[0].to_float(), p[1].to_float(), p[2].to_float()) - (ws.get("world_offset") as Vector3)
	if _cam == null:
		var player_cam := root.get_camera_3d()
		_cam = Camera3D.new()
		root.add_child(_cam)
		if player_cam:
			_cam.attributes = player_cam.attributes
			_cam.far = player_cam.far
			_cam.near = player_cam.near
		_cam.make_current()
	_cam.fov = float(OS.get_environment("FOV")) if OS.get_environment("FOV") != "" else 50.0
	_cam.global_transform = Transform3D(Basis.from_euler(Vector3(deg_to_rad(p[4].to_float()), deg_to_rad(p[3].to_float()), 0.0)), at)
	var player := current_scene.get_tree().get_first_node_in_group("player") as Node3D if current_scene else null
	if player:
		player.visible = false
