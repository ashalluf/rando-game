extends SceneTree
## The sky alone, in seconds: the city's own Environment (copied out of city.tscn, never the
## city), its DayNight and sun, a camera and a flat dark ground. For the look and for the cost.
##
##   OUT=sky.png HOUR=13 YAW=180 PITCH=15 xvfb-run -a -s "-screen 0 1280x720x24" godot \
##     --rendering-driver vulkan --display-driver x11 --audio-driver Dummy --path . \
##     --script tools/sky/sky_shot.gd --resolution 1280x720 -- --quality=0
##
## (opengl3 for the Compatibility path.) Env: OUT png; HOUR; YAW (degrees, 0 looks north, 90
## east... as the game's yaw: forward is -Z); PITCH; FOV; CAM_Y metres up; FRAMES before the shot
## (default 24); MOONAGE days; COVERAGE (0..1, the cloud_coverage uniform held); CONTRAILS n;
## DOME city_glow held (night); DETAIL 0 forces the painted cumulus; SHADER another sky shader
## (the A/B: /tmp/sky_old.gdshader); BENCH n frames after the shot, timed (CPU and GPU ms a frame,
## printed as BENCH lines - lavapipe's GPU is the CPU, so read the difference between two runs).

var _frame := 0
var _frames := 24
var _bench := 0
var _bench_t0 := 0
var _vp: RID
var _day: Node
var _sky: ShaderMaterial
var _gpu_sum := 0.0
var _cpu_sum := 0.0


func _env(key: String, def: String) -> String:
	var v := OS.get_environment(key)
	return v if v != "" else def


func _initialize() -> void:
	var ps := load("res://scenes/levels/city.tscn") as PackedScene
	var st := ps.get_state()
	var env: Environment
	for i in st.get_node_count():
		if st.get_node_type(i) == "WorldEnvironment":
			for k in st.get_node_property_count(i):
				if st.get_node_property_name(i, k) == "environment":
					env = st.get_node_property_value(i, k)
	env = env.duplicate(true) as Environment
	_sky = env.sky.sky_material as ShaderMaterial
	if _env("SHADER", "") != "":
		_sky.shader = load(_env("SHADER", "")) if _env("SHADER", "").begins_with("res://") else _load_shader(_env("SHADER", ""))
	var top := Node3D.new()
	top.name = "SkyShot"
	var we := WorldEnvironment.new()
	we.name = "Env"
	we.environment = env
	top.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = true
	top.add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60000, 60000)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.16, 0.15, 0.13)
	gm.roughness = 0.95
	ground.material_override = gm
	top.add_child(ground)
	var cam := Camera3D.new()
	cam.fov = float(_env("FOV", "70"))
	cam.far = 12000.0
	cam.position = Vector3(0, float(_env("CAM_Y", "2")), 0)
	cam.rotation_degrees = Vector3(float(_env("PITCH", "12")), float(_env("YAW", "0")), 0)
	top.add_child(cam)
	_day = (load("res://scripts/world/day_night.gd") as GDScript).new()
	_day.name = "DayNight"
	_day.set("sun_path", NodePath("../Sun"))
	_day.set("environment_path", NodePath("../Env"))
	if _env("MOONAGE", "") != "":
		_day.set("moon_age_days", float(_env("MOONAGE", "0")))
	top.add_child(_day)
	root.add_child(top)
	cam.make_current()
	_frames = int(_env("FRAMES", "24"))
	_bench = int(_env("BENCH", "0"))
	# The game runs TAA at every level, which is what resolves the march's per-frame dither.
	if _env("TAA", "1") == "1":
		root.use_taa = true
	_vp = root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(_vp, true)


func _load_shader(path: String) -> Shader:
	var sh := Shader.new()
	sh.code = FileAccess.get_file_as_string(path)
	return sh


func _hold() -> void:
	if _env("HOUR", "") != "":
		_day.set("hour", float(_env("HOUR", "12")))
	_day.call("set_paused", true)
	if _env("COVERAGE", "") != "":
		_day.set("cloud_coverage", float(_env("COVERAGE", "0.4")))
	if _env("DETAIL", "") != "":
		_sky.set_shader_parameter("cloud_detail", float(_env("DETAIL", "1")))
	if _env("DOME", "") != "":
		_sky.set_shader_parameter("city_glow", float(_env("DOME", "0")))
		_sky.set_shader_parameter("city_wrap", float(_env("DOME_WRAP", "0.3")))


func _process(_delta: float) -> bool:
	_frame += 1
	_hold()
	if _frame == _frames:
		var out := _env("OUT", "sky.png")
		root.get_texture().get_image().save_png(out)
		print("SKY wrote %s hour %s" % [out, str(_day.get("hour"))])
		if _bench <= 0:
			return true
		_bench_t0 = Time.get_ticks_usec()
	elif _frame > _frames and _frame <= _frames + _bench:
		_gpu_sum += RenderingServer.viewport_get_measured_render_time_gpu(_vp)
		_cpu_sum += RenderingServer.viewport_get_measured_render_time_cpu(_vp)
		if _frame == _frames + _bench:
			var wall := float(Time.get_ticks_usec() - _bench_t0) / 1000.0 / float(_bench)
			print("BENCH frames %d  wall %.1f ms  gpu %.2f ms  cpu %.2f ms" % [_bench, wall, _gpu_sum / _bench, _cpu_sum / _bench])
			return true
	return false
