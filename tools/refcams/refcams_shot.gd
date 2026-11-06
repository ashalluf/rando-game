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
	_golf_group()
	_bonfire_lit()
	_pump_car()
	_lowrider_meet()
	_arena_event()
	_market_day()
	# OCCLUSION=0: occlusion culling off (still_shot's switch), to tell what is culled in plain sight.
	if OS.get_environment("OCCLUSION") == "0":
		get_root().use_occlusion_culling = false
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
		# A "hero" row (cameras_w5.json's hero_foot) stages the player on foot at the eye's x, z and
		# shoots through his own CameraRig: the default third-person view, not a free camera.
		_hero = cam.get("hero", {}) if cam.get("hero", null) is Dictionary else {}
		var y := float(eye[1])
		if cam.get("agl", false) and plan != null:
			y += float(plan.height_at(Vector2(float(eye[0]), float(eye[2]))))
		var eye_text := "%.2f,%.2f,%.2f,%.2f,%.2f" % [float(eye[0]), y, float(eye[2]), float(eye[3]), float(eye[4])]
		OS.set_environment("EYE", "" if not _hero.is_empty() else eye_text)
		var fov := float(cam.get("fov", 55.0))
		if not _hero.is_empty():
			_hero_start(player, eye, y)
		_set_weather(weather, String(cam.get("weather", "clear")))
		_bonfire_lit_for(cam)
		if day:
			day.set("hour", float(cam.hour))
			day.call("_apply")
		_port_clock(cam)
		_freight_clock(cam, scene)
		Engine.time_scale = 1.0
		# A "drive" row (cameras_w5.json, chase_cam): the player drives his own car and the shot is
		# his chase camera (tools/refcams/chase_stage.gd), not the free eye.
		var drive: RefCounted = null
		if cam.has("drive"):
			OS.set_environment("EYE", "")
			drive = load("res://tools/refcams/chase_stage.gd").new()
			await drive.call("run", self, cam, player)
			fov = player.get("camera").fov
		elif cam.has("wingsuit"):
			# A "wingsuit" row (cameras_w8.json, wingsuit_golden): the hero gliding in his suit, the
			# shot from his own chase camera (tools/refcams/wingsuit_stage.gd).
			OS.set_environment("EYE", "")
			drive = load("res://tools/refcams/wingsuit_stage.gd").new()
			await drive.call("run", self, cam, player)
			fov = player.get("camera").fov
		elif cam.has("boat"):
			# A "boat" row (cameras_w8.json, speedboat_golden): the player at the helm under way
			# off the coast, a free chase eye on the hull (tools/refcams/boat_stage.gd).
			OS.set_environment("EYE", "")
			drive = load("res://tools/refcams/boat_stage.gd").new()
			await drive.call("run", self, cam, player)
		else:
			_place(player, fov)
			# The marine layer's morning damp (MarineMorning) wants the hour and the eye: soaked at once.
			if weather and weather.has_method("settle_wet"):
				var keys: Array = weather.get_script().get_script_constant_map().get("STATE_KEYS", [])
				weather.call("settle_wet", keys.find(String(cam.get("weather", "clear"))), float(cam.hour),
					Vector3(float(eye[0]), y, float(eye[2])))
			if scene.has_method("update_streaming"):
				scene.call("update_streaming", true)
		# A row may ask for more frames (cameras_w5.json "shot_frames": a view over big chunks that
		# the FULL ring has not finished building after the default). What it stages is staged
		# the default count before the shot, so it is where the row says whatever the wait.
		var frames := 0 if drive else maxi(_env_int("SHOT_FRAMES", 30), int(cam.get("shot_frames", 0)))
		var stage_at := frames - _env_int("SHOT_FRAMES", 30)
		var traffic_staged := false
		var park: RefCounted = null
		for i in frames:
			if i == stage_at:
				_stage_air(scene, cam)
				_stage_rail(cam, scene)
				traffic_staged = _stage_street_cars(cam, scene, plan)
				_stage_storm_flash(cam, weather)
				# A "park_car" row (cameras_w6.json, car_closeup): a parked car and the eye round it.
				if cam.has("park_car"):
					park = load("res://tools/refcams/park_stage.gd").new()
					if not park.call("stage", self, cam, scene, plan):
						park = null
			if i == frames - 3:
				_stage_freeway_cars(cam, scene)
			if cam.has("skate_t") and (i == stage_at or i >= frames - 3):
				_skate_clock(cam)
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
		# A staged camera ("stage": "mayhem" in cameras_w5.json): the scene is set up now, once
		# the chunks round the eye stand, and the effect clock stepped to its moment.
		var stage := String(cam.get("stage", ""))
		if stage == "mayhem":
			_stager = load("res://tools/refcams/mayhem_stage.gd")
			await _stager.stage(self, scene, _eye_cam, player, func() -> void: _place(player, fov))
		elif stage == "person":
			# cameras_w6.json's person_closeup: one pedestrian at arm's length (person_stage.gd).
			_stager = load("res://tools/refcams/person_stage.gd")
			await _stager.stage(self, scene, _eye_cam, player, func() -> void: _place(player, fov), cam)
		elif stage == "hospital":
			# cameras_w7.json's hospital_er: an ambulance backing into the ER bay (hospital_stage.gd).
			_stager = load("res://tools/refcams/hospital_stage.gd")
			await _stager.stage(self, scene, _eye_cam, player, func() -> void: _place(player, fov), cam)
		Engine.time_scale = 0.0005
		for i in _env_int("SETTLE", 6):
			await process_frame
			if drive:
				drive.call("hold")
			else:
				_place(player, fov)
		if not drive:
			_clear_lens(cam.name)
		if park and _eye_cam:
			park.call("clear_people", self, _eye_cam.global_position)
		for car in _fw_staged:
			if is_instance_valid(car) and _eye_cam:
				print("REFCAM %s: staged %s at %.1f m, visible %s, in tree %s" % [cam.name, car.name, (car as Node3D).global_position.distance_to(_eye_cam.global_position), (car as Node3D).is_visible_in_tree(), (car as Node).is_inside_tree()])
		_fw_staged.clear()
		await process_frame
		if not _hero.is_empty():
			_hero_report(player, cam.name)
		if traffic_staged:
			scene.get_node("Traffic").set("staged", false)
		_unstage_rail(scene)
		var png := _out_dir.path_join("%s.png" % cam.name)
		get_root().get_texture().get_image().save_png(png)
		# NIGHT_AB=1 (rc5-gas-station-night): what lights the night ground - the frame again with
		# each light source taken away in turn (<name>_nab_<what>.png) and the environment printed.
		if OS.get_environment("NIGHT_AB") == "1":
			await _night_ab(scene, png)
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
		if drive:
			await drive.call("debug", _out_dir)
			drive.call("finish")
			Engine.time_scale = 1.0
			if _eye_cam:
				_eye_cam.make_current()
		_write_frames(load_ms, shots)
		_release_storm_flash(cam, weather)
		if park:
			park.call("finish")
		if _stager != null:
			_unstage(scene, player)
		print("REFCAM %s saved %s eye %s hour %.2f %s" % [cam.name, png, eye_text, float(cam.hour), cam.get("weather", "clear")])
		if is_instance_valid(_air_staged) and _air_staged is Node3D:
			# Where the staged aircraft is at the shot (TRUE world): a row's air_dist / air_side are
			# tuned from this line.
			var at: Vector3 = _air_staged.get("world_pos") if _air_staged.get("world_pos") != null else (_air_staged as Node3D).global_position
			print("REFCAM %s air at %.1f,%.1f,%.1f" % [cam.name, at.x, at.y, at.z])
		_air_staged = null
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
			_fw_staged.append(car)
	print("REFCAM %s: placed %d street cars on road %d (axis %d at %.1f)" % [cam.name, placed, best, axis, float(plan.road_pos(axis, best))])
	return true


## A camera row's optional `freeway_cars` (wave 6, freeway_night): {"route": the Freeway route
## index, "clear": metres round the eye in which no other traffic car is kept, "cars": [[ahead, li,
## dir, speed, kind], ...]} - freeway cars placed through TrafficManager.place_freeway_car() a few
## frames before the shot, `ahead` metres along the route from the eye in the direction the
## camera looks (dir -1 runs toward the route's start), in lane `li` (0 by the median), `kind` a
## Vehicle.BodyType name or "". Rows without the key place nothing.
var _fw_staged: Array = []


func _stage_freeway_cars(cam: Dictionary, scene: Node) -> void:
	var spec: Variant = cam.get("freeway_cars")
	var traffic := scene.get_node_or_null("Traffic")
	if not spec is Dictionary or traffic == null or _eye_cam == null:
		return
	var fw: Variant = traffic.call("_freeway")
	if fw == null:
		return
	var ri := int(spec.get("route", 3))
	var eye: Vector3 = get_root().get_node("/root/WorldState").call("to_world", _eye_cam.global_position)
	var t0: float = fw.nearest_on(ri, Vector2(eye.x, eye.z))[0]
	var look := -_eye_cam.global_transform.basis.z
	var d: Vector2 = fw.point_at(ri, t0)[1]
	var toward := 1.0 if Vector2(look.x, look.z).dot(d) >= 0.0 else -1.0
	var clear := float(spec.get("clear", 40.0))
	for v in traffic.get("freeway_cars"):
		var car := v as Node3D
		if is_instance_valid(car) and car.global_position.distance_to(_eye_cam.global_position) < clear:
			car.visible = false
			print("REFCAM %s: hid %s (inside the staged clearance)" % [cam.name, car.name])
	var width := float(fw.routes[ri].width)
	var fw_script: GDScript = fw.get_script()
	var body_types: Dictionary = load("res://scripts/vehicles/vehicle.gd").get_script_constant_map().get("BodyType", {})
	var placed := 0
	for c: Array in spec.get("cars", []):
		var kind := -1
		if c.size() > 4 and String(c[4]) != "":
			kind = int(body_types.get(String(c[4]), -1))
		var dir := int(c[2])
		var car: Node3D = traffic.call("place_freeway_car", ri, t0 + float(c[0]) * toward, dir, kind, float(c[3]))
		if car == null:
			continue
		var t: Dictionary = car.get("traffic")
		t.lane = float(fw_script.call("lane_fraction", width, int(c[1]))) * float(dir)
		t.li = int(c[1])
		traffic.call("_place_freeway_car", car, fw)
		_fw_staged.append(car)
		placed += 1
	print("REFCAM %s: placed %d freeway cars on route %d at t %.1f" % [cam.name, placed, ri, t0])


## A camera row's optional "air" key (cameras_w5.json): AirTraffic.stage() of that kind with
## "air_dist" / "air_side", as still_shot.gd's AIR / AIR_DIST / AIR_SIDE (the airport's ground:
## "taxi" is a landed jet `air_dist` seconds along its way to stand `air_side`). No key, nothing.
func _stage_air(scene: Node, cam: Dictionary) -> void:
	var kind := String(cam.get("air", ""))
	if kind == "":
		return
	var air := scene.get_node_or_null("AirTraffic")
	var lens := get_root().get_camera_3d()
	if air == null or lens == null:
		print("REFCAM %s: no AirTraffic to stage %s" % [cam.name, kind])
		return
	var placed: Node = air.call("stage", kind, lens, float(cam.get("air_dist", 300.0)), float(cam.get("air_side", 0.0)))
	print("REFCAM %s: staged %s (%s)" % [cam.name, kind, placed.name if placed else "nothing"])
	_air_staged = placed


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


## The staging script of the camera being shot (null for a plain camera).
var _stager: GDScript = null
var _air_staged: Node = null


## After a staged camera: the hero hidden again, the aim let go, the police stood down.
func _unstage(scene: Node, player: Node3D) -> void:
	if _stager.has_method("unstage") or "unstage" in _stager.get_script_method_list().map(func(m): return m.name):
		_stager.call("unstage")
	_stager.set("hero_at", Vector3.INF)
	_stager = null
	Input.action_release("alt_fire")
	var police := scene.get_node_or_null("Police")
	if police:
		police.call("set_wanted", 0)
	player.visible = false


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


## A row's optional "bonfire_lit" (wave 7's bonfire_night): 1 lights every beach bonfire ring
## (Bonfires.force_lit, as BONFIRE_LIT=1), so the rings round the eye burn with their groups whatever
## the night's rolls. Set before the city loads (a ring's group is planned as its chunk builds) when
## a camera of this run asks; each camera then sets it again (the key, or -1: the hashes decide).
func _bonfire_lit() -> void:
	if OS.get_environment("BONFIRE_LIT") != "":
		return
	var only := OS.get_environment("ONLY").split(",", false)
	for cam: Dictionary in _cameras().get("cameras", []):
		if cam.has("bonfire_lit") and (only.is_empty() or String(cam.name) in only):
			OS.set_environment("BONFIRE_LIT", str(int(cam.bonfire_lit)))


## A row's optional "arena_event" (wave 8's arena_night): 1 makes tonight an event night at the
## arena (ArenaNight, as ARENA_EVENT=1: searchlights, the fuller plaza), 0 a quiet one. Set before the
## city loads, when a camera of this run asks (the plaza is planned as its chunk builds).
func _arena_event() -> void:
	if OS.get_environment("ARENA_EVENT") != "":
		return
	var only := OS.get_environment("ONLY").split(",", false)
	for cam: Dictionary in _cameras().get("cameras", []):
		if cam.has("arena_event") and (only.is_empty() or String(cam.name) in only):
			OS.set_environment("ARENA_EVENT", str(int(cam.arena_event)))


func _bonfire_lit_for(cam: Dictionary) -> void:
	if not cam.has("bonfire_lit") and OS.get_environment("BONFIRE_LIT") == "":
		return
	var bf: GDScript = load("res://scripts/world/bonfires.gd")
	bf.set("force_lit", int(cam.get("bonfire_lit", -1)))


## A row's optional "pump_car" (wave 8's gas_station_night): 1 puts a car at a pump, its driver
## beside it, on every gas station (GasNight.force_pump_car, as PUMP_CAR=1) whatever the station's
## hash. Set before the city loads: the car is placed as its chunk builds.
func _pump_car() -> void:
	if OS.get_environment("PUMP_CAR") != "":
		return
	var only := OS.get_environment("ONLY").split(",", false)
	for cam: Dictionary in _cameras().get("cameras", []):
		if int(cam.get("pump_car", 0)) == 1 and (only.is_empty() or String(cam.name) in only):
			OS.set_environment("PUMP_CAR", "1")


## A row's optional "lowrider_meet" (wave 7's lowrider_meet): {"on": 1, "pose": "i:routine:s[:side],..."}
## holds every meet on (LOWRIDER_MEET=1) and freezes row cars mid-routine (LOWRIDER_POSE). Set before
## the city loads: the meet's row is parked as its chunk builds.
func _lowrider_meet() -> void:
	var only := OS.get_environment("ONLY").split(",", false)
	for cam: Dictionary in _cameras().get("cameras", []):
		if cam.get("lowrider_meet", null) is Dictionary and (only.is_empty() or String(cam.name) in only):
			var lm: Dictionary = cam.lowrider_meet
			if OS.get_environment("LOWRIDER_MEET") == "" and int(lm.get("on", 1)) == 1:
				OS.set_environment("LOWRIDER_MEET", "1")
				(load("res://scripts/world/lowrider_meet.gd") as GDScript).set("force", true)
			if OS.get_environment("LOWRIDER_POSE") == "" and lm.has("pose"):
				OS.set_environment("LOWRIDER_POSE", String(lm.pose))


## A row's optional "market_day" (wave 8's farmers_market): 1 makes today every farmers' market's
## day (FarmersMarket.force_market_day, as MARKET_DAY=1), and its "hour" the hour the market is
## built for (MARKET_HOUR: a chunk built during the load would otherwise be built at the load's
## hour). Set before the city loads: the static reads the environment when the class first loads.
func _market_day() -> void:
	if OS.get_environment("MARKET_DAY") != "":
		return
	var only := OS.get_environment("ONLY").split(",", false)
	for cam: Dictionary in _cameras().get("cameras", []):
		if cam.has("market_day") and (only.is_empty() or String(cam.name) in only):
			OS.set_environment("MARKET_DAY", str(int(cam.market_day)))
			if cam.has("hour") and OS.get_environment("MARKET_HOUR") == "":
				OS.set_environment("MARKET_HOUR", str(float(cam.hour)))


## A row's optional "golf_group" ("hole:stage[:tee[:count]]", wave 6's golf_morning) puts a group
## of golfers there whatever the hole's roll (GolfLife.force_group). Set before the city loads:
## golfers are spawned as the course's chunks build.
func _golf_group() -> void:
	var only := OS.get_environment("ONLY").split(",", false)
	for cam: Dictionary in _cameras().get("cameras", []):
		if cam.has("golf_group") and (only.is_empty() or String(cam.name) in only):
			OS.set_environment("GOLF_GROUP", String(cam.golf_group))


func _cameras() -> Dictionary:
	var path := OS.get_environment("REFCAMS_JSON")
	if path == "":
		path = "res://tools/refcams/cameras.json"
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


## The free camera at EYE, and the player parked hidden on it so streaming centres there and
## nothing he does (falling, the fall-through recovery) moves the frame.
func _place(player: Node3D, fov: float) -> void:
	if not _hero.is_empty():
		_hero_place(player, fov)
		return
	if _eye_cam and get_root().get_camera_3d() != _eye_cam:
		_eye_cam.make_current() # back from a hero camera
	_eye(player, fov)
	if _eye_cam:
		player.global_position = _eye_cam.global_position
	player.set("velocity", Vector3.ZERO)
	# An eye in the underground station (rail_at rows): the parked player is let through the city's
	# ground box at once, or each step throws him out to the street and the tunnel train is hidden.
	if _rail_held and player is PhysicsBody3D:
		(load("res://scripts/world/metro_station.gd") as GDScript).call("admit", player)
	# A staged camera puts the hero in the shot, at the stage's spot, facing down the street.
	if _stager != null and _stager.get("hero_at") != Vector3.INF:
		player.visible = true
		player.global_position = _stager.get("hero_at")
		var vis := player.get_node_or_null("Visual") as Node3D
		if vis:
			vis.rotation.y = float(_stager.get("hero_yaw"))


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
	if player.get("vehicle") != null:
		return
	_place(player, fov)


## The hero camera's row ({"hero": {...}} in a camera; every key optional): the player stands at
## the eye's x, z on the ground (eye y is unused), faces and looks along the eye's yaw, the rig
## pitched by the eye's pitch, at the rig's own distance unless "distance"; "walk" (0..1, default
## 0.35) holds move_forward at that strength so he walks away from the lens (put back to the start
## every frame, so the frame never moves); "weapon" the WeaponManager slot (default 0, the rifle).
var _hero: Dictionary = {}
var _hero_at := Vector3.ZERO


func _hero_start(player: Node3D, eye: Array, ground_y: float) -> void:
	var ws := root.get_node_or_null("/root/WorldState")
	var off: Vector3 = ws.get("world_offset") if ws else Vector3.ZERO
	var gy := ground_y - float(eye[1])
	if current_scene and current_scene.get("plan") != null:
		gy = float(current_scene.get("plan").height_at(Vector2(float(eye[0]), float(eye[2]))))
	# Kept in TRUE world: the streaming re-centres the origin while the shot settles.
	_hero_at = Vector3(float(eye[0]), gy + 0.3, float(eye[2]))
	player.visible = true
	player.global_position = _hero_at - off
	var vis := player.get_node_or_null("Visual") as Node3D
	if vis:
		vis.rotation.y = deg_to_rad(float(eye[3]))
	var wm: Node = player.get("weapon_manager")
	if wm and wm.has_method("equip"):
		wm.call("equip", int(_hero.get("weapon", 0)))
	var rig := player.get_node_or_null("CameraRig")
	if rig:
		rig.call("set_look", float(eye[3]), float(eye[4]))
		if _hero.has("distance"):
			rig.set("camera_distance", float(_hero.distance))
		var cam := rig.get("camera") as Camera3D
		if cam:
			cam.make_current()


func _hero_place(player: Node3D, fov: float) -> void:
	var walk := float(_hero.get("walk", 0.35))
	if walk > 0.0 and Engine.time_scale > 0.5:
		Input.action_press("move_forward", walk)
	else:
		Input.action_release("move_forward")
	# The ground under him is real (he stands on it); only x, z go back to the start.
	var ws := root.get_node_or_null("/root/WorldState")
	var at: Vector3 = ws.call("to_local", _hero_at) if ws else _hero_at
	player.global_position = Vector3(at.x, player.global_position.y, at.z)
	var rig := player.get_node_or_null("CameraRig")
	if rig:
		rig.set("camera_fov", fov)
		rig.set("boost_fov_boost", 0.0)
		var cam := rig.get("camera") as Camera3D
		if cam and get_root().get_camera_3d() != cam:
			cam.make_current()


func _hero_report(player: Node3D, shot: String) -> void:
	Input.action_release("move_forward")
	var ws := root.get_node_or_null("/root/WorldState")
	var cam := get_root().get_camera_3d()
	var near := 0
	var within := 0
	for p in get_nodes_in_group("pedestrian"):
		var n := p as Node3D
		if n == null or not n.is_visible_in_tree():
			continue
		var d := n.global_position.distance_to(player.global_position)
		if d <= 12.0:
			within += 1
			if d >= 3.0:
				near += 1
	print("REFCAM %s hero at %s speed %.2f, camera %s, %d people within 12 m (%d at 3-12 m)" % [shot,
		str(ws.call("to_world", player.global_position)) if ws else "?", float(player.call("horizontal_speed")),
		str(ws.call("to_world", cam.global_position)) if ws and cam else "?", within, near])


## A camera row's optional `port_t` (wave 7, port_night): the container terminal's clock
## (PortLife.clock, seconds) held there for the shot, so the cranes, tractors and straddle carriers
## stand where the row was framed for. Rows without it let the clock run as before.
## A row's optional "skate_t" (wave 8's skate_park): THE PIT's skaters held at that clock (seconds;
## SkateParkLife.set_clock + hold, as SKATE_T= / SKATE_HOLD=1), so a rider is where the row was framed
## (mid-air). Set while the shot waits (the park's life exists once its chunk is built); rows without
## the key leave the clock alone.
func _skate_clock(cam: Dictionary) -> void:
	var sl: GDScript = load("res://scripts/world/skate_park_life.gd")
	sl.set("hold", true)
	for n in get_root().find_children("*", "", true, false):
		if n.get_script() == sl:
			n.call("set_clock", float(cam.skate_t))


func _port_clock(cam: Dictionary) -> void:
	var pl: GDScript = load("res://scripts/world/port_life.gd")
	if cam.has("port_t"):
		pl.set("clock", float(cam.port_t))
		pl.set("hold", true)
	else:
		pl.set("hold", OS.get_environment("PORT_HOLD") == "1")


## NIGHT_AB=1: the frame again with each light source off in turn, and the night numbers printed.
func _night_ab(scene: Node, png: String) -> void:
	var day := scene.get_node_or_null("DayNight")
	var we := scene.find_child("WorldEnvironment", true, false) as WorldEnvironment
	var env: Environment = we.environment if we else null
	if env == null:
		var cam := get_root().get_viewport().get_camera_3d()
		env = cam.environment if cam and cam.environment else null
	if day:
		day.set_process(false)
		day.set_physics_process(false)
	var suns: Array = scene.find_children("*", "DirectionalLight3D", true, false)
	if env:
		print("NIGHT_AB env: tonemap_exposure %.3f ambient_source %d ambient_energy %.3f sky_contribution %.3f ambient_color %s fog %s fog_density %.5f bg_energy %.3f" % [env.tonemap_exposure, env.ambient_light_source, env.ambient_light_energy, env.ambient_light_sky_contribution, env.ambient_light_color, env.fog_enabled, env.fog_density, env.background_energy_multiplier])
	for d in suns:
		var dl := d as DirectionalLight3D
		print("NIGHT_AB sun %s visible %s energy %.3f color %s dir %s" % [dl.name, dl.visible, dl.light_energy, dl.light_color, -dl.global_transform.basis.z])
	var cam3 := get_root().get_viewport().get_camera_3d()
	if cam3 and cam3.attributes:
		print("NIGHT_AB camera attributes %s" % cam3.attributes)
	var lamps: Array = get_nodes_in_group("lamp_light")
	var pools: Array = []
	for n in scene.find_children("*", "GeometryInstance3D", true, false):
		var nm := String(n.name).to_lower()
		if nm.contains("pool") or nm.contains("spill") or nm.contains("glow"):
			pools.append(n)
	print("NIGHT_AB %d lamp lights, %d pool/spill/glow nodes" % [lamps.size(), pools.size()])
	var eye := cam3.global_position if cam3 else Vector3.ZERO
	for l in lamps:
		var o := l as OmniLight3D
		if o and o.is_visible_in_tree() and o.global_position.distance_to(eye) < 60.0:
			print("NIGHT_AB lamp %s/%s at %s (d %.1f) energy %.2f range %.1f att %.2f" % [o.get_parent().name, o.name, (o.global_position - eye).snapped(Vector3.ONE * 0.1), o.global_position.distance_to(eye), o.light_energy, o.omni_range, o.omni_attenuation])
	for n in pools:
		var g := n as GeometryInstance3D
		if g.is_visible_in_tree() and g is MultiMeshInstance3D and (g as MultiMeshInstance3D).multimesh:
			var mm := (g as MultiMeshInstance3D).multimesh
			var near := 0
			for i in mm.visible_instance_count if mm.visible_instance_count >= 0 else mm.instance_count:
				if (g.global_transform * mm.get_instance_transform(i)).origin.distance_to(eye) < 40.0:
					near += 1
			if near > 0:
				print("NIGHT_AB pools %s/%s: %d within 40 m" % [g.get_parent().name, g.name, near])
	var variants := ["nolamps", "nopools", "nomoon", "noamb", "nothing"]
	for v: String in variants:
		var saved := {}
		if v in ["nolamps", "nothing"]:
			for l in lamps:
				saved[l] = (l as Node3D).visible
				(l as Node3D).visible = false
		if v in ["nopools", "nothing"]:
			for n in pools:
				saved[n] = (n as Node3D).visible
				(n as Node3D).visible = false
		if v in ["nomoon", "nothing"]:
			for d in suns:
				saved[d] = (d as Node3D).visible
				(d as Node3D).visible = false
		var amb := [0.0, 0.0]
		if env and v in ["noamb", "nothing"]:
			amb = [env.ambient_light_energy, env.ambient_light_sky_contribution]
			env.ambient_light_energy = 0.0
			env.ambient_light_sky_contribution = 0.0
		for i in 4:
			await process_frame
		get_root().get_texture().get_image().save_png(png.get_basename() + "_nab_%s.png" % v)
		for n in saved:
			(n as Node3D).visible = saved[n]
		if env and v in ["noamb", "nothing"]:
			env.ambient_light_energy = amb[0]
			env.ambient_light_sky_contribution = amb[1]
	if day:
		day.set_process(true)
		day.set_physics_process(true)


## A row's optional "rail_at" ("<station>[:<dir>[:<seconds from mid-dwell>]]", wave 7's
## metro_station): the light rail's clock set so a train dwells at that station, and held there
## until the shot is taken (LightRailSystem's RAIL_AT / RAIL_HOLD, per camera).
var _rail_held := false


func _stage_rail(cam: Dictionary, scene: Node) -> void:
	if not cam.has("rail_at"):
		return
	var sys := scene.get_node_or_null("LightRail")
	var line: Variant = sys.get("line") if sys else null
	if line == null:
		print("REFCAM %s: no light rail to stage" % cam.name)
		return
	# LightRail is reached through its script: naming it compiles it before the autoloads exist.
	var lr: Variant = (line as Object).get_script()
	var at := String(cam.rail_at).split(":", false)
	lr.clock = float(line.call("clock_at_station", at[0].to_int(), at[1].to_int() if at.size() > 1 else 0,
		at[2].to_float() if at.size() > 2 else 0.0))
	sys.set("hold", true)
	sys.call("step")
	_rail_held = true
	print("REFCAM %s: light rail clock %.1f (%s)" % [cam.name, float(lr.clock), cam.rail_at])


func _unstage_rail(scene: Node) -> void:
	if not _rail_held:
		return
	var sys := scene.get_node_or_null("LightRail")
	if sys:
		sys.set("hold", OS.get_environment("RAIL_HOLD") == "1")
	_rail_held = false
## A camera row's optional `freight_into` (wave 7, freight_yard): the freight line's clock held at
## that many seconds into the yard stand of the trip nearest the yard (FreightRail.clock_at_yard();
## the stand is DWELL_YARD 150 s, so past 150 the train is pulling out south), so the departing
## train stands where the row was framed for. Rows without it let the clock run as before.
func _freight_clock(cam: Dictionary, scene: Node) -> void:
	var sys := scene.get_node_or_null("FreightRail") if scene else null
	if sys == null:
		return
	if not cam.has("freight_into"):
		sys.set("hold", OS.get_environment("FREIGHT_HOLD") == "1")
		return
	var line: Variant = sys.get("line")
	if line == null:
		sys.call("step")
		line = sys.get("line")
	if line == null:
		return
	load("res://scripts/world/freight_rail.gd").set("clock", float(line.call("clock_at_yard", float(cam.freight_into))))
	sys.set("hold", true)
	sys.call("step")


## A camera row's optional `storm_flash` (wave 8, storm_downtown): {"dist": metres, "az": degrees
## (0 = +x, -90 = game north), "hold": the flash level held for the shot} - a lightning strike forced
## through Weather.force_strike() as the camera's staging starts, its flash and bolt held by
## StormDrama (STORM_FLASH_HOLD's path) until the shot is saved. Rows without the key strike nothing.
func _stage_storm_flash(cam: Dictionary, weather: Node) -> void:
	var spec: Variant = cam.get("storm_flash")
	if not spec is Dictionary or weather == null or not weather.has_method("force_strike"):
		return
	var drama: Node = weather.get("_drama")
	var az := deg_to_rad(float(spec.get("az", -90.0)))
	if drama:
		drama.set("_hold", float(spec.get("hold", 0.8)))
	weather.call("force_strike", float(spec.get("dist", 1100.0)), Vector3(cos(az), 0.0, sin(az)))
	if drama:
		drama.set("_holding", float(spec.get("hold", 0.8)) > 0.0)
	print("REFCAM %s: lightning at %.0f m, az %.0f, held %.2f" % [cam.name, float(spec.get("dist", 1100.0)), float(spec.get("az", -90.0)), float(spec.get("hold", 0.8))])


func _release_storm_flash(cam: Dictionary, weather: Node) -> void:
	if not cam.get("storm_flash") is Dictionary or weather == null:
		return
	var drama: Node = weather.get("_drama")
	if drama:
		drama.set("_holding", false)
		drama.set("_hold", 0.0)
