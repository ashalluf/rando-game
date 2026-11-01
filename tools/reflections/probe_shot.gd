extends SceneTree
## A street canyon of its own - generated Buildings both sides, a glass tower, cars at the kerb -
## under the city's own Environment, sun and DayNight, with the street's reflection probe exactly
## as ReflectionProbes stands one (a box over the road and both pavements, its eye 4.2 m up). Small
## enough for lavapipe (Forward+, the only renderer the probes are for): a few minutes a still.
##
##   OUT=/tmp/probe.png VIEW=car xvfb-run -a -s "-screen 0 1280x720x24" godot \
##     --rendering-driver vulkan --display-driver x11 --audio-driver Dummy --path . \
##     --script tools/reflections/probe_shot.gd --resolution 960x540
##
## Env: OUT png; VIEW car (a door from the pavement) | tower (the glass tower from the street) |
## street (down the street) | ball (the chrome ball in mid-street, BALL=1) | hood (the bonnet from the driver's height); HOUR (default 15);
## PROBES=0 no probe (the before); HDRI=0 no street HDRI under the sky's horizon; PAINT (r,g,b of
## the near car); FRAMES before the shot (default 40); BENCH n: n frames timed after the shot
## with the probe standing still, then n more while it re-renders (CPU / GPU ms a frame, BENCH
## lines; lavapipe's GPU is the CPU, so read the ratios); WET road wetness (0..1); HIGH=1 keeps
## SDFGI and volumetric fog (very slow on lavapipe); BALL=1 a chrome ball by the car;
## SHADOWS=1 the probe renders with shadows (off in the game: the cost).

var _top: Node3D
var _day: Node
var _probes: Node
var _vp: RID


func _env(k: String, d: String) -> String:
	var v := OS.get_environment(k)
	return v if v != "" else d


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	# The autoloads (WorldState, Sfx) come up in the first frames; Building's class chain needs them.
	for i in 3:
		await process_frame
	var ps := load("res://scenes/levels/city.tscn") as PackedScene
	var st := ps.get_state()
	var env: Environment
	for i in st.get_node_count():
		if st.get_node_type(i) == "WorldEnvironment":
			for k in st.get_node_property_count(i):
				if st.get_node_property_name(i, k) == "environment":
					env = st.get_node_property_value(i, k)
	env = env.duplicate(true) as Environment
	# HIGH=1 keeps SDFGI and the volumetric fog (Quality HIGH); without it the MEDIUM level's
	# effects (SSR, SSIL, SSAO, glow), which is all lavapipe can render in minutes.
	if _env("HIGH", "0") != "1":
		env.sdfgi_enabled = false
		env.volumetric_fog_enabled = false
	_top = Node3D.new()
	_top.name = "ProbeShot"
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	_top.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 300.0
	_top.add_child(sun)
	_day = (load("res://scripts/world/day_night.gd") as GDScript).new()
	_day.name = "DayNight"
	_day.set("sun_path", NodePath("../Sun"))
	_day.set("environment_path", NodePath("../WorldEnvironment"))
	_top.add_child(_day)
	root.add_child(_top)
	RenderingServer.global_shader_parameter_set("road_wetness", float(_env("WET", "0")))
	var pf: GDScript = load("res://scripts/world/prop_factory.gd")
	_slab(Vector3(400.0, 0.2, 400.0), Vector3(0.0, -0.1, 0.0), pf.call("pbr", "asphalt", 5.0))
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400.0, 0.2, 400.0)
	shape.shape = box
	body.add_child(shape)
	body.position = Vector3(0.0, -0.1, 0.0)
	_top.add_child(body)
	for side in [-1.0, 1.0]:
		_slab(Vector3(4.0, 0.15, 400.0), Vector3(side * 9.0, 0.075, 0.0), pf.call("pbr", "sidewalk", 3.0))
	# Buildings both sides of the street, a glass tower among them.
	var scene := load("res://scenes/props/building.tscn") as PackedScene
	var n := 0
	for side in [-1.0, 1.0]:
		for k in 6:
			var z := -75.0 + k * 27.0
			var b := scene.instantiate()
			var tower: bool = side > 0.0 and k == 2
			b.seed = 101 + n * 17
			b.lot_size = Vector2(24.0, 24.0)
			b.min_height = 70.0 if tower else 12.0
			b.max_height = 110.0 if tower else 34.0
			if tower:
				b.finish_options.assign([3])
			b.position = Vector3(side * (11.0 + 12.5), 0.0, z)
			_top.add_child(b)
			n += 1
	var vs: GDScript = load("res://scripts/vehicles/vehicle.gd")
	var paint := _env("PAINT", "0.78,0.79,0.80").split_floats(",")
	var near_car := _car(vs, 0, Color(paint[0], paint[1], paint[2]), Vector3(-4.2, 0.6, 0.0), PI)
	_car(vs, 14, Color(0.06, 0.07, 0.09), Vector3(-4.2, 0.6, 7.5), PI)
	_car(vs, 1, Color(0.42, 0.05, 0.05), Vector3(4.2, 0.6, -6.0), 0.0)
	if _env("HDRI", "1") == "0":
		pass
	else:
		(load("res://scripts/world/reflection_probes.gd") as GDScript).call("street_sky", env)
	if _env("RAWPROBE", "0") == "1":
		var rp := ReflectionProbe.new()
		rp.size = Vector3(32.0, 70.0, 180.0)
		rp.position = Vector3(0.0, 34.0, 0.0)
		rp.origin_offset = Vector3(0.0, -29.8, 0.0)
		rp.box_projection = true
		rp.update_mode = ReflectionProbe.UPDATE_ONCE if _env("RAWONCE", "0") == "1" else ReflectionProbe.UPDATE_ALWAYS
		if _env("RAWSET", "0") == "1":
			rp.ambient_mode = ReflectionProbe.AMBIENT_DISABLED
			rp.enable_shadows = true
			rp.mesh_lod_threshold = 6.0
			rp.max_distance = 320.0
			rp.blend_distance = 4.0
		_top.add_child(rp)
	elif _env("PROBES", "1") == "1":
		var rps: GDScript = load("res://scripts/world/reflection_probes.gd")
		rps.set("force", true)
		rps.set("shadows", _env("SHADOWS", "0") == "1")
		_probes = rps.new()
		_probes.name = "ReflectionProbes"
		_top.add_child(_probes)
		var across := 14.0 + 2.0 * (4.0 + 5.0)
		_probes.set("fixed", [{"key": "street", "center": Vector3(0.0, -2.0 + 35.0, 0.0), "size": Vector3(across, 70.0, 180.0),
			"origin": Vector3(0.0, 4.2 - 33.0, 0.0), "dist": 0.0}])
	# BALL=1: a chrome ball beside the car - exactly what the reflection sees there.
	if _env("BALL", "0") == "1":
		var ball := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.9
		sm.height = 1.8
		ball.mesh = sm
		var chrome := StandardMaterial3D.new()
		chrome.albedo_color = Color(0.95, 0.95, 0.95)
		chrome.metallic = 1.0
		chrome.roughness = 0.02
		ball.material_override = chrome
		ball.position = Vector3(0.0, 1.3, 4.0) if _env("VIEW", "car") == "ball" else near_car.position + Vector3(1.6, 0.4, 3.2)
		_top.add_child(ball)
	var cam := Camera3D.new()
	cam.fov = 60.0
	cam.far = 4000.0
	_top.add_child(cam)
	var at: Vector3 = near_car.position
	match _env("VIEW", "car"):
		"tower":
			cam.look_at_from_position(Vector3(-6.0, 1.7, 22.0), Vector3(14.0, 34.0, -21.0))
		"street":
			cam.look_at_from_position(Vector3(-1.5, 2.0, 30.0), Vector3(-1.0, 4.0, -40.0))
		"ball":
			cam.fov = 40.0
			cam.look_at_from_position(Vector3(0.6, 1.8, 10.5), Vector3(0.0, 1.25, 4.0))
		"hood":
			cam.look_at_from_position(at + Vector3(0.0, 1.35, 2.6), at + Vector3(0.0, 0.7, -0.6))
		_:
			cam.look_at_from_position(at + Vector3(4.4, 1.55, 3.4), at + Vector3(0.0, 0.55, 0.0))
	cam.current = true
	_vp = root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(_vp, true)
	root.use_taa = true
	for i in int(_env("FRAMES", "40")):
		_hold()
		await process_frame
		if i % 5 == 0:
			print("PROBE frame %d %d ms" % [i, Time.get_ticks_msec()])
		if i == 8 and _probes and _env("ALWAYS", "0") == "1":
			for c in _probes.get_children():
				(c as ReflectionProbe).update_mode = ReflectionProbe.UPDATE_ALWAYS
				print("PROBE always ", c.name, " ", (c as ReflectionProbe).global_position, " ", (c as ReflectionProbe).size, " visible ", (c as ReflectionProbe).visible)
	var out := _env("OUT", "probe.png")
	root.get_texture().get_image().save_png(out)
	print("PROBE wrote %s hour %s probes %s renders %s" % [out, str(_day.get("hour")), str(_probes != null), str(_probes.get("renders") if _probes else 0)])
	var bench := int(_env("BENCH", "0"))
	if bench > 0:
		_bench("still", bench)
		await _wait(bench)
		if _probes:
			# Stale light: the next refresh slot re-renders it where it stands (a nudge).
			for s: Dictionary in _probes.get("_slots"):
				s.light = []
		_bench("refresh", bench)
		await _wait(bench)
	quit()


var _bench_name := ""
var _bench_n := 0
var _cpu := 0.0
var _gpu := 0.0
var _count := 0


func _bench(nm: String, n: int) -> void:
	_bench_name = nm
	_bench_n = n
	_cpu = 0.0
	_gpu = 0.0
	_count = 0


func _wait(n: int) -> void:
	var t0 := Time.get_ticks_usec()
	for i in n:
		_hold()
		await process_frame
		_cpu += RenderingServer.viewport_get_measured_render_time_cpu(_vp)
		_gpu += RenderingServer.viewport_get_measured_render_time_gpu(_vp)
		_count += 1
	print("BENCH %s probes=%s frames %d cpu %.2f ms gpu %.2f ms wall %.1f ms" % [_bench_name, str(_probes != null), _count, _cpu / _count, _gpu / _count, (Time.get_ticks_usec() - t0) / 1000.0 / n])


func _hold() -> void:
	_day.set("hour", float(_env("HOUR", "15")))
	_day.call("set_paused", true)


func _slab(size: Vector3, at: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = size
	mi.mesh = m
	mi.material_override = mat
	mi.position = at
	_top.add_child(mi)


func _car(vs: GDScript, type: int, paint: Color, at: Vector3, yaw: float) -> Node3D:
	var car: Node3D = vs.new()
	car.call("setup", type, paint, 0)
	car.position = at
	car.rotation = Vector3(0.0, yaw, 0.0)
	_top.add_child(car)
	return car
