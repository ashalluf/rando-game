extends Node
## First-use stutter probe (shader-warm): the test room under the CITY's Environment and sun,
## then a scripted run of "first time" events - a rifle burst, a rocket, a pedestrian shot with
## the shotgun, every car body, the police and emergency cars, a car set on fire, nightfall with
## the lamps and car lights, rain, landmarks streaming in - timing every frame and counting the
## pipelines Godot compiles while each event is on screen.
##
## A scene, not a --script tool: it names CityPlan and Landmarks, which need the autoloads.
##
## Under lavapipe (Forward+ on the CPU) a pipeline compile is LLVM codegen: tens to hundreds of
## milliseconds, so a missed warm-up stands out as a spike the way it does on a GPU driver.
##
##   WARM=1 EVENTS=all tools/shader_warm/run_probe.sh 480x270
##
## Env: WARM=0 (no loading-screen warm-up: the "before" of the warm-up itself) | 1 (the loading
## screen's shader warm-up, LoadingScreen._warm_shaders(), run first, as the game does);
## WARM_ONLY=a,b only the shader files whose names contain a or b (lavapipe keeps every pipeline
## it compiles, ~200 MB a shader: all of them do not fit); REHEARSE=1 the new rehearsal
## (WarmRehearsal.run) after it; KEEP_ATLAS=1 only the decal atlas keeper;
## EVENTS=all or a comma list of names (see EVENTS below); FRAMES per event (default 12);
## LANDMARKS=n how many landmarks the landmark event builds (default all). run_probe.sh empties
## the on-disk shader and pipeline caches first unless KEEP_CACHE=1 (a first launch).
## Prints a line per event: FIRST <name> worst=<ms> sum_over_base=<ms> draw=<n> spec=<n> surf=<n>
## mesh=<n>, the worst frames of the run (SPIKE) and a TOTAL line. Never --headless: the dummy
## renderer compiles nothing.

const EVENTS := ["rifle", "rocket", "ped", "shotgun_ped", "cars", "police", "emergency", "fire",
		"night", "rain", "landmarks"]

var _frames_per_event := 12
var _base_ms := 0.0
var _log: Array = []
var _spikes: Array = []
var _player: Node3D
var _cam: Camera3D
var _world: Node3D
var _total_draw := 0
var _total_ms := 0.0


func _env(k: String, d: String) -> String:
	var v := OS.get_environment(k)
	return v if v != "" else d


func _ready() -> void:
	await get_tree().process_frame
	_frames_per_event = int(_env("FRAMES", "12"))
	var level: Node3D = (load("res://scenes/levels/test_box.tscn") as PackedScene).instantiate()
	# The city's own Environment (SDFGI, SSR, SSAO, SSIL, volumetric fog, glow, the LUT) and
	# sun: the pipeline variants depend on which of them are on.
	var city: Node = (load("res://scenes/levels/city.tscn") as PackedScene).instantiate()
	for keep in ["WorldEnvironment", "Sun"]:
		var old: Node = level.get_node_or_null(keep)
		if old:
			level.remove_child(old)
			old.free()
		var n: Node = city.get_node_or_null(keep)
		if n:
			city.remove_child(n)
			n.owner = null
			level.add_child(n)
	city.free()
	get_tree().root.add_child(level)
	_world = level
	await get_tree().process_frame
	await get_tree().process_frame
	_player = get_tree().get_first_node_in_group("player") as Node3D
	_cam = get_viewport().get_camera_3d()
	if _env("PHYS", "1") == "1":
		Engine.max_physics_steps_per_frame = 1
	for i in 6:
		await get_tree().process_frame
	if _env("WARM", "1") == "1":
		var t0 := Time.get_ticks_msec()
		if _env("WARM_ONLY", "") != "":
			LoadingScreen.only_shaders = PackedStringArray(_env("WARM_ONLY", "").split(",", false))
		var ls := LoadingScreen.new()
		get_tree().root.add_child(ls)
		await ls.call("_warm_shaders")
		print("WARM quads done in %d ms, draw compilations %d" % [Time.get_ticks_msec() - t0, int(_mon("draw"))])
		ls.queue_free()
	if _env("REHEARSE", "0") == "1":
		var t1 := Time.get_ticks_msec()
		await WarmRehearsal.run(_world, _cam, Callable(), true)
		print("WARM rehearsal done in %d ms, draw compilations %d" % [Time.get_ticks_msec() - t1, int(_mon("draw"))])
	elif _env("KEEP_ATLAS", "0") == "1":
		WarmRehearsal.keep_decal_atlas(_world)
	# A baseline: the room alone, settled.
	var base: Array = []
	for i in 10:
		base.append(await _frame())
	base.sort()
	_base_ms = base[base.size() / 2]
	print("BASE median frame %.0f ms" % _base_ms)
	var list: Array = EVENTS if _env("EVENTS", "all") == "all" else Array(_env("EVENTS", "").split(",", false))
	for ev in list:
		await _event(String(ev))
	_spikes.sort_custom(func(a, b): return a[0] > b[0])
	for i in mini(10, _spikes.size()):
		print("SPIKE %.0f ms in %s" % [_spikes[i][0], _spikes[i][1]])
	print("TOTAL draw=%d over_base=%.0f ms" % [_total_draw, _total_ms])
	get_tree().quit()


func _mon(kind: String) -> float:
	match kind:
		"draw":
			return Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_DRAW)
		"spec":
			return Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_SPECIALIZATION)
		"surf":
			return Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_SURFACE)
		"mesh":
			return Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_MESH)
		"canvas":
			return Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_CANVAS)
	return 0.0


## One frame's wall time in ms (process_frame to process_frame: it includes the render).
func _frame() -> float:
	var t := Time.get_ticks_usec()
	await get_tree().process_frame
	return float(Time.get_ticks_usec() - t) / 1000.0


func _event(name: String) -> void:
	var m0 := {}
	for k in ["draw", "spec", "surf", "mesh"]:
		m0[k] = _mon(k)
	# Every frame from the event's start counts, its own setup frames too (a car spawned and
	# shot spends frames in the setup, and those are the ones that pay).
	var times: Array = []
	var last := [Time.get_ticks_usec()]
	var rec := func() -> void:
		var now := Time.get_ticks_usec()
		times.append(float(now - last[0]) / 1000.0)
		last[0] = now
	get_tree().process_frame.connect(rec)
	var t_setup := Time.get_ticks_usec()
	await call("_ev_" + name)
	var setup_ms := float(Time.get_ticks_usec() - t_setup) / 1000.0
	for i in _frames_per_event:
		await get_tree().process_frame
	get_tree().process_frame.disconnect(rec)
	var worst := 0.0
	var over := 0.0
	for ms: float in times:
		worst = maxf(worst, ms)
		over += maxf(ms - _base_ms * 1.5, 0.0)
		_spikes.append([ms, name, 0])
	var line := "FIRST %-12s frames=%2d worst=%6.0f over_base=%6.0f setup=%6.0f" % [name, times.size(), worst, over, setup_ms]
	for k in ["draw", "spec", "surf", "mesh"]:
		line += " %s=%d" % [k, int(_mon(k) - m0[k])]
	_total_draw += int(_mon("draw") - m0["draw"])
	_total_ms += over
	print(line)
	await _cleanup()


## Everything an event adds goes under this holder, freed after it.
var _holder: Node3D


func _hold() -> Node3D:
	if _holder == null or not is_instance_valid(_holder):
		_holder = Node3D.new()
		_holder.name = "ProbeHolder"
		_world.add_child(_holder)
	return _holder


func _cleanup() -> void:
	Input.action_release("fire")
	Input.action_release("alt_fire")
	if _holder and is_instance_valid(_holder):
		_holder.queue_free()
		_holder = null
	for i in 3:
		await get_tree().process_frame


func _ahead(dist: float, up: float = 0.0) -> Vector3:
	var f := -_cam.global_basis.z
	f.y = 0.0
	f = f.normalized()
	return Vector3(_cam.global_position.x, 0.0, _cam.global_position.z) + f * dist + Vector3.UP * up


func _fire(slot: int, frames: int, pitch: float = -10.0) -> void:
	var manager: Node = _player.get("weapon_manager")
	manager.call("equip", slot)
	_player.get("camera_rig").call("set_look", 0.0, pitch)
	for i in 4:
		await get_tree().process_frame
	Input.action_press("fire")
	for i in frames:
		await get_tree().process_frame
	Input.action_release("fire")


func _ev_rifle() -> void:
	await _fire(0, 6)


func _ev_rocket() -> void:
	await _fire(1, 2, -14.0)


func _ev_ped() -> void:
	var ped_script: GDScript = load("res://scripts/npc/pedestrian.gd")
	for i in 3:
		var p: Node3D = ped_script.new()
		var at := _ahead(7.0 + i * 1.5) + Vector3(float(i - 1) * 1.6, 0.3, 0.0)
		p.call("setup", Rect2(at.x - 2.0, at.z - 2.0, 4.0, 4.0), 1.0, 5100 + i * 37)
		_hold().add_child(p)
		p.global_position = at
		p.set("_pause_left", 60.0)
	_player.get("camera_rig").call("set_look", 0.0, -8.0)


func _ev_shotgun_ped() -> void:
	var ped_script: GDScript = load("res://scripts/npc/pedestrian.gd")
	var p: Node3D = ped_script.new()
	var at := _ahead(5.0) + Vector3(0.0, 0.3, 0.0)
	p.call("setup", Rect2(at.x - 2.0, at.z - 2.0, 4.0, 4.0), 1.0, 6100)
	_hold().add_child(p)
	p.global_position = at
	p.set("_pause_left", 60.0)
	for i in 3:
		await get_tree().process_frame
	_player.get("camera_rig").call("look_at_point", p.global_position + Vector3.UP * 1.1)
	var manager: Node = _player.get("weapon_manager")
	manager.call("equip", 2)
	for i in 3:
		await get_tree().process_frame
	Input.action_press("fire")
	await get_tree().process_frame
	await get_tree().process_frame
	Input.action_release("fire")


func _car(type: int) -> Node3D:
	var car: Node3D
	if type == 12 or type == 13:
		car = load("res://scripts/npc/emergency_car.gd").call("make", type - 12, RandomNumberGenerator.new())
	elif type >= 9 and type <= 11:
		car = load("res://scripts/vehicles/big_vehicles.gd").call("make", type, 0)
	else:
		car = load("res://scripts/vehicles/vehicle.gd").new()
		car.call("setup", type, Color(0.6, 0.1, 0.1), 0)
	return car


func _ev_cars() -> void:
	_player.get("camera_rig").call("set_look", 0.0, -8.0)
	var types: Array = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 14, 15, 16, 17, 18, 19]
	for i in types.size():
		var car := _car(int(types[i]))
		if car == null:
			continue
		car.position = _ahead(14.0 + (i / 6) * 9.0) + Vector3(float(i % 6 - 2.5) * 5.5, 0.9, 0.0)
		_hold().add_child(car)


func _ev_police() -> void:
	var car: Node3D = load("res://scripts/npc/police_car.gd").call("make", false, RandomNumberGenerator.new())
	car.set("police", null)
	car.position = _ahead(10.0) + Vector3(0.0, float(car.call("road_lift")), 0.0)
	_hold().add_child(car)
	var van: Node3D = load("res://scripts/npc/police_car.gd").call("make", true, RandomNumberGenerator.new())
	van.set("police", null)
	van.position = _ahead(12.0) + Vector3(5.0, float(van.call("road_lift")), 0.0)
	_hold().add_child(van)


func _ev_emergency() -> void:
	for t in [12, 13]:
		var car := _car(t)
		car.position = _ahead(14.0) + Vector3(float(t - 12) * 7.0 - 3.5, float(car.call("road_lift")), 0.0)
		car.set("lights_forced", true)
		_hold().add_child(car)


func _ev_fire() -> void:
	var car := _car(0)
	car.position = _ahead(10.0) + Vector3(0.0, 0.9, 0.0)
	_hold().add_child(car)
	for i in 4:
		await get_tree().process_frame
	# Shot full of holes, then a blast: holes, crazed glass, dents, smoke and fire.
	var shape := 0
	var at: Vector3 = car.global_position + Vector3(0.0, 0.8, 1.0)
	for i in 6:
		car.call("take_hit", shape, 60.0, Vector3(0.0, 0.0, -1.0), at + Vector3(0.3 * i - 0.8, 0.0, 0.0), 0)
	car.call("take_hit", shape, 900.0, Vector3(0.0, 0.0, -1.0), at + Vector3(0.0, -0.8, 2.0), 2)


func _ev_night() -> void:
	RenderingServer.global_shader_parameter_set("night_factor", 1.0)
	RenderingServer.global_shader_parameter_set("lamp_factor", 1.0)
	var sun := _world.get_node_or_null("Sun") as DirectionalLight3D
	if sun:
		sun.light_energy = 0.05
	# A street lamp's light and a car's shadowed headlight, the kinds the city turns on at night.
	var omni := OmniLight3D.new()
	omni.light_color = Color(1.0, 0.7, 0.4)
	omni.omni_range = 18.0
	omni.position = _ahead(8.0, 6.0)
	_hold().add_child(omni)
	var spot := SpotLight3D.new()
	spot.shadow_enabled = true
	spot.spot_range = 40.0
	spot.position = _cam.global_position + Vector3(0.0, -0.5, 0.0)
	spot.rotation = _cam.global_rotation
	_hold().add_child(spot)
	var car := _car(0)
	car.position = _ahead(12.0) + Vector3(2.0, 0.9, 0.0)
	_hold().add_child(car)
	car.set("_npc_driver", true)


func _ev_rain() -> void:
	RenderingServer.global_shader_parameter_set("night_factor", 0.0)
	RenderingServer.global_shader_parameter_set("lamp_factor", 0.0)
	var sun := _world.get_node_or_null("Sun") as DirectionalLight3D
	if sun:
		sun.light_energy = 1.0
	var w: Node = load("res://scripts/world/weather.gd").new()
	w.name = "Weather"
	_hold().add_child(w)
	for i in 2:
		await get_tree().process_frame
	w.call("force_state", 2, true)


func _ev_landmarks() -> void:
	# A real plan (the far copies read the macro map), built off the clock: CityStreamer builds it
	# long before the first landmark is seen.
	var city: Node = (load("res://scenes/levels/city.tscn") as PackedScene).instantiate()
	var plan := CityPlan.new()
	plan.seed = city.get("world_seed")
	plan.block_size_range = city.get("block_size_range")
	plan.street_width = city.get("street_width")
	plan.avenue_width = city.get("avenue_width")
	plan.sidewalk_width = city.get("sidewalk_width")
	plan.downtown_radius = city.get("downtown_radius")
	plan.midtown_radius = city.get("midtown_radius")
	plan.macro = MacroMap.new()
	plan.macro.seed = plan.seed
	plan.macro.setup()
	city.free()
	var all: Array = Landmarks.all()
	var n := mini(all.size(), int(_env("LANDMARKS", "999")))
	_player.get("camera_rig").call("set_look", 0.0, 4.0)
	var ahead := _ahead(260.0)
	for i in n:
		var lm: Dictionary = all[i]
		var holder := Node3D.new()
		_hold().add_child(holder)
		Landmarks.build(lm, holder, null, plan, false)
		var a: Vector2 = lm.anchor
		holder.position = Vector3(ahead.x - a.x, 0.0, ahead.z - a.y) + Vector3(float(i % 9 - 4) * 40.0, 0.0, -float(i / 9) * 30.0)
	print("LANDMARKS built %d far copies" % n)
