extends "res://tools/glshot/still_shot.gd"
## The ten reference cameras (tools/refcams/cameras.json) shot from ONE load of the city, each with
## its own hour and weather, through whatever renderer Godot was started with (opengl3 under Xvfb
## for the fleet; see tools/refcams/README.md). Driven by tools/refcams/refcams.py, which also
## reads the PNGs back for the numbers; run by hand:
##
##   OUT_DIR=build/refcams/run1 xvfb-run -a -s "-screen 0 1280x720x24" godot \
##     --rendering-driver opengl3 --display-driver x11 --audio-driver Dummy --path . \
##     --script tools/refcams/refcams_shot.gd --resolution 960x540 -- --nohud --quality=0 \
##     --spawn=2359.4,880,0,2
##
## Env: OUT_DIR (default build/refcams/latest), REFCAMS_JSON (default the committed table), ONLY=
## a comma list of names, FRAMES warm-up frames of the load (default 45), SHOT_FRAMES frames each
## camera streams and adapts for (default 30), SETTLE frames with the clock all but stopped
## (default 6). Shader TIME is held at zero (water, surf, clouds stand still) unless LIVE_TIME=1.
## STRICT=1 is still_shot's DIFF mode as well: people, cars, aircraft, particles and the player
## hidden, so two runs of one tree differ by a pixel or two. SPLIT=1 (and OSPLIT=1) prints
## still_shot's cost split for every camera (SPLITCAM <name> heads each table).
## Writes <OUT_DIR>/<name>.png per camera and <OUT_DIR>/frames.json (each shot's GEO counts,
## hour, weather, the eye it used and how long it took). The --spawn should be the first
## camera's x,z: the load builds round it.

var _out_dir := "build/refcams/latest"


func _initialize() -> void:
	Engine.set_meta("postfx_motion_blur", 0.0)
	# Shader TIME is held at its first instant (still_shot's DIFF trick) unless LIVE_TIME=1: the sea,
	# the surf and the clouds run off it, and with it running the beach and the pier moved by a
	# third of their pixels between two runs of one tree. The world itself (people, cars) moves.
	if OS.get_environment("LIVE_TIME") != "1":
		ProjectSettings.set_setting("rendering/limits/time/time_rollover_secs", 0.000001)
	if OS.get_environment("STRICT") == "1":
		seed(12345)
	_audit_toggles()
	if OS.get_environment("OUT_DIR") != "":
		_out_dir = OS.get_environment("OUT_DIR")
	DirAccess.make_dir_recursive_absolute(_out_dir)
	change_scene_to_file("res://scenes/levels/city.tscn")
	_run.call_deferred()


func _run() -> void:
	var table := _cameras()
	var cams: Array = table.get("cameras", [])
	var only := OS.get_environment("ONLY")
	if only != "":
		var want := only.split(",", false)
		cams = cams.filter(func(c: Dictionary) -> bool: return String(c.name) in want)
	var started := Time.get_ticks_msec()
	var player: Node3D = null
	for i in _env_int("FRAMES", 45):
		await process_frame
		if current_scene == null:
			continue
		var traffic := current_scene.get_node_or_null("Traffic")
		if traffic:
			traffic.set("builds_per_frame", 40)
		if player == null:
			player = get_first_node_in_group("player") as Node3D
	if player == null or current_scene == null:
		push_error("refcams: the city did not load")
		quit(1)
		return
	var load_ms := Time.get_ticks_msec() - started
	print("REFCAMS loaded in %d ms, %d cameras" % [load_ms, cams.size()])
	var scene := current_scene
	var day := scene.get_node_or_null("DayNight")
	var weather := scene.get_node_or_null("Weather")
	var plan: Variant = scene.get("plan")
	if day:
		day.call("set_paused", true)
	var shots := []
	for cam: Dictionary in cams:
		var t0 := Time.get_ticks_msec()
		var eye: Array = cam.eye
		var y := float(eye[1])
		if cam.get("agl", false) and plan != null:
			y += float(plan.height_at(Vector2(float(eye[0]), float(eye[2]))))
		var eye_text := "%.2f,%.2f,%.2f,%.2f,%.2f" % [float(eye[0]), y, float(eye[2]), float(eye[3]), float(eye[4])]
		OS.set_environment("EYE", eye_text)
		var fov := float(cam.get("fov", 55.0))
		_set_weather(weather, String(cam.get("weather", "clear")))
		if day:
			day.set("hour", float(cam.hour))
			day.call("_apply")
		Engine.time_scale = 1.0
		_place(player, fov)
		if scene.has_method("update_streaming"):
			scene.call("update_streaming", true)
		var traffic_staged := _stage_street_cars(cam, scene, plan)
		for i in _env_int("SHOT_FRAMES", 30):
			await process_frame
			_place(player, fov)
			if day:
				day.set("hour", float(cam.hour))
		if OS.get_environment("STRICT") == "1":
			_diff_freeze(player)
			# _diff_freeze puts the clock back to the run's --hour= (the FIRST camera's), which drew
			# the evening cameras with a midday sky in every strict run: this camera's hour again.
			if day:
				day.set("hour", float(cam.hour))
				day.call("_apply")
		Engine.time_scale = 0.0005
		for i in _env_int("SETTLE", 6):
			await process_frame
			_place(player, fov)
		_clear_lens(cam.name)
		await process_frame
		if traffic_staged:
			scene.get_node("Traffic").set("staged", false)
		var png := _out_dir.path_join("%s.png" % cam.name)
		get_root().get_texture().get_image().save_png(png)
		var c: Array = await _geo_report("GEO_%s" % cam.name)
		# SPLIT=1 (OSPLIT=1 too): still_shot's cost table for this camera's frame, every category
		# hidden in turn (tools/perf_audit_4/split_table.py ranks them from the log).
		if OS.get_environment("SPLIT") == "1":
			print("SPLITCAM %s" % cam.name)
			await _geo_split(player, Vector3.ZERO, Vector3.ZERO, false, fov)
		shots.append({
			"name": cam.name, "png": "%s.png" % cam.name, "eye": eye_text, "hour": cam.hour,
			"weather": cam.get("weather", "clear"), "fov": fov,
			"geo": {"tris": c[0], "draws": c[1], "objects": c[2], "camera_tris": c[3],
				"shadow_tris": c[4], "camera_draws": c[5], "shadow_draws": c[6]},
			"shot_ms": Time.get_ticks_msec() - t0,
		})
		_write_frames(load_ms, shots)
		print("REFCAM %s saved %s eye %s hour %.2f %s" % [cam.name, png, eye_text, float(cam.hour), cam.get("weather", "clear")])
	print("REFCAMS done, %d shots in %d ms" % [shots.size(), Time.get_ticks_msec() - started])
	quit()


## A camera row's optional `street_cars` (wave 5, rain_day): {"axis": "z" (a road of constant z) or
## "x", "at": the road's coordinate (the nearest road there is taken), "cars": [[along, dir, lane,
## speed], ...]} - street traffic placed through TrafficManager.place_car() as the camera starts
## (along = the TRUE world coordinate down the road; dir +1 runs toward +along), with the upkeep
## held (`staged`) until the shot is taken, so the view always has its traffic (and its tyre spray)
## whatever the load's own traffic did. Rows without the key place nothing.
func _stage_street_cars(cam: Dictionary, scene: Node, plan: Variant) -> bool:
	var spec: Variant = cam.get("street_cars")
	var traffic := scene.get_node_or_null("Traffic")
	if not spec is Dictionary or traffic == null or plan == null:
		return false
	var axis := 1 if String(spec.get("axis", "z")) == "z" else 0  # CityPlan.AXIS_Z / AXIS_X
	var at := float(spec.get("at", 0.0))
	var probe := Vector2(0.0, at) if axis == 1 else Vector2(at, 0.0)
	var start: Vector2i = plan.block_index_at(probe)
	var i0 := start.y if axis == 1 else start.x
	var best := i0
	for i in range(i0 - 1, i0 + 3):
		if absf(float(plan.road_pos(axis, i)) - at) < absf(float(plan.road_pos(axis, best)) - at):
			best = i
	traffic.set("staged", true)
	var placed := 0
	for c: Array in spec.get("cars", []):
		var car: Variant = traffic.call("place_car", axis, best, int(c[1]), int(c[2]), float(c[0]), float(c[3]))
		if car != null:
			placed += 1
	print("REFCAM %s: placed %d street cars on road %d (axis %d at %.1f)" % [cam.name, placed, best, axis, float(plan.road_pos(axis, best))])
	return true


## A traffic car the shot's clock left with the lens inside or just against its body (the freeway
## camera stands in a slow lane 2.5 m over the deck; on main e5bb9e4 a truck filled the frame) is
## hidden for the shot and named in the log. Only bodies whose box, grown LENS_ROOM, holds the eye.
const LENS_ROOM := 0.6


func _clear_lens(shot: String) -> void:
	if _eye_cam == null:
		return
	var eye := _eye_cam.global_position
	for v in get_nodes_in_group("vehicle"):
		var car := v as Node3D
		if car == null or not car.is_visible_in_tree() or car.global_position.distance_to(eye) > 30.0:
			continue
		var box := AABB()
		var first := true
		for mi in car.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			if m.mesh == null or not m.is_visible_in_tree():
				continue
			var b := m.global_transform * m.get_aabb()
			box = b if first else box.merge(b)
			first = false
		if not first and box.grow(LENS_ROOM).has_point(eye):
			car.visible = false
			print("REFCAM %s: hid %s, its body held the lens" % [shot, car.name])


## frames.json, rewritten after every shot so a run that dies part way keeps what it shot.
func _write_frames(load_ms: int, shots: Array) -> void:
	var out := {"renderer": RenderingServer.get_current_rendering_driver_name(),
		"method": ProjectSettings.get_setting("rendering/renderer/rendering_method"),
		"resolution": [get_root().size.x, get_root().size.y], "load_ms": load_ms,
		"strict": OS.get_environment("STRICT") == "1", "live_time": OS.get_environment("LIVE_TIME") == "1",
		"shots": shots}
	var f := FileAccess.open(_out_dir.path_join("frames.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(out, "\t"))
	f.close()


func _cameras() -> Dictionary:
	var path := OS.get_environment("REFCAMS_JSON")
	if path == "":
		path = "res://tools/refcams/cameras.json"
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


## The free camera at EYE, and the player parked hidden on it so streaming centres there and
## nothing he does (falling, the fall-through recovery) moves the frame.
func _place(player: Node3D, fov: float) -> void:
	_eye(player, fov)
	if _eye_cam:
		player.global_position = _eye_cam.global_position
	player.set("velocity", Vector3.ZERO)


## The weather held for the shot, with the streets as wet as that weather leaves them (a clear
## shot after a rainy one would otherwise show the drying street).
func _set_weather(weather: Node, key: String) -> void:
	if weather == null:
		return
	var keys: Array = weather.get_script().get_script_constant_map().get("STATE_KEYS", [])
	var idx := keys.find(key)
	if idx < 0:
		push_error("refcams: unknown weather %s" % key)
		return
	weather.call("force_state", idx, true)
	var wet := clampf(float(weather.call("_rain_level", idx)) * 1.2, 0.0, 1.0)
	weather.set("wetness", wet)


## still_shot's _geo_split re-poses the player before its base count: here that is the free camera.
func _pose(player: Node3D, _anchor: Vector3, _hold: Vector3, _boost: bool, fov: float) -> void:
	_place(player, fov)
