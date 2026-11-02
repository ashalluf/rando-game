extends Node
## The ravine ballpark alone, in a minute or two: the city's own Environment (copied out of
## city.tscn), its DayNight, a dark ground plane at the pad and the detailed BallparkBuild at its
## real world place (no city, no terrain: the hills round it are missing). The default camera is
## the stadium_night reference camera (tools/refcams/cameras_w6.json).
##
##   OUT=park.png xvfb-run -a -s "-screen 0 1280x720x24" godot --rendering-driver opengl3 \
##     --display-driver x11 --audio-driver Dummy --path . tools/stadium_night/park_shot.tscn \
##     --resolution 1280x720
##
## Forward+ (lavapipe): --rendering-driver vulkan with VK_ICD_FILENAMES=.../lvp_icd.json.
## Env: OUT; HOUR (21); EYE=x,y,z,yaw,pitch (true world); FOV (48); FRAMES (30); FAR=1 the far
## copy; SHOTS="x,y,z,yaw,pitch[@fov];..." more views from the same build (OUT with _1, _2 ...).
## STADIUM_NIGHT=0 is the A/B.

var _frame := 0
var _frames := 30
var _day: Node
var _cam: Camera3D
var _shots: Array = []
var _shot := 0


func _env(key: String, def: String) -> String:
	var v := OS.get_environment(key)
	return v if v != "" else def


func _ready() -> void:
	var ps := load("res://scenes/levels/city.tscn") as PackedScene
	var st := ps.get_state()
	var env: Environment
	for i in st.get_node_count():
		if st.get_node_type(i) == "WorldEnvironment":
			for k in st.get_node_property_count(i):
				if st.get_node_property_name(i, k) == "environment":
					env = st.get_node_property_value(i, k)
	env = env.duplicate(true) as Environment
	var top := Node3D.new()
	top.name = "ParkShot"
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
	pm.size = Vector2(6000, 6000)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.05, 0.06, 0.04)
	gm.roughness = 0.95
	ground.material_override = gm
	ground.position = Vector3(Ballpark.HOME.x, Ballpark.PAD_Y - 0.6, Ballpark.HOME.y)
	top.add_child(ground)
	_cam = Camera3D.new()
	_cam.far = 12000.0
	top.add_child(_cam)
	_shots = [_env("EYE", "1965.6,235,-3155.6,-173.6,-14") + "@" + _env("FOV", "48")]
	for s in _env("SHOTS", "").split(";", false):
		_shots.append(s if "@" in s else s + "@" + _env("FOV", "48"))
	_place(0)
	_day = (load("res://scripts/world/day_night.gd") as GDScript).new()
	_day.name = "DayNight"
	_day.set("sun_path", NodePath("../Sun"))
	_day.set("environment_path", NodePath("../Env"))
	top.add_child(_day)
	add_child(top)
	var statics := StaticBody3D.new()
	top.add_child(statics)
	BallparkBuild.build(top, statics, _env("FAR", "0") != "1")
	_cam.make_current()
	_frames = int(_env("FRAMES", "30"))
	Engine.time_scale = 0.0


func _place(i: int) -> void:
	var parts := String(_shots[i]).split("@")
	var e := parts[0].split(",")
	_cam.fov = float(parts[1]) if parts.size() > 1 else 48.0
	_cam.position = Vector3(float(e[0]), float(e[1]), float(e[2]))
	_cam.rotation_degrees = Vector3(float(e[4]), float(e[3]), 0)


func _process(_delta: float) -> void:
	_frame += 1
	_day.set("hour", float(_env("HOUR", "21")))
	_day.call("set_paused", true)
	for l in get_tree().get_nodes_in_group("lamp_light"):
		(l as Light3D).light_energy = 1.0
	if _frame == _frames:
		var out := _env("OUT", "park.png")
		if _shot > 0:
			out = out.get_basename() + "_%d.png" % _shot
		get_viewport().get_texture().get_image().save_png(out)
		print("PARK wrote %s  tris=%d draws=%d" % [out, Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)])
		_shot += 1
		if _shot >= _shots.size():
			get_tree().quit()
			return
		_place(_shot)
		_frame = _frames - 8
