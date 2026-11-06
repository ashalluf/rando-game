extends Node
## The pier at night alone, in about a minute: the city's own Environment (copied out of
## city.tscn), its DayNight, a dark sea plane, a sand strip and PierPark built at the origin (its
## anchor at 0, 0). The default camera is the pier_night reference camera's, moved with the pier
## (refcam eye (-945, 1.8, -235) - anchor (-940, -350)).
##
##   OUT=pier.png xvfb-run -a -s "-screen 0 1280x720x24" godot --rendering-driver opengl3 \
##     --display-driver x11 --audio-driver Dummy --path . tools/pier_night/pier_shot.tscn \
##     --resolution 1280x720
##
## Env: OUT; HOUR (21); EYE=x,y,z,yaw,pitch (pier frame); FOV (55); FAR=1 the far copy;
## FRAMES (30); T= seconds of shader time offset (the rides and the LED patterns; default 0, the refcam's
## held first instant); HAZE (night_atmos.x, 0.3 a clear night). PIER_NIGHT=0 is the A/B.

var _frame := 0
var _frames := 30
var _day: Node


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
	top.name = "PierShot"
	var we := WorldEnvironment.new()
	we.name = "Env"
	we.environment = env
	top.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = true
	top.add_child(sun)
	var sea := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(20000, 20000)
	sea.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.02, 0.03, 0.04)
	gm.roughness = 0.08
	sea.material_override = gm
	sea.position = Vector3(0, 0.15, 0)
	top.add_child(sea)
	var sand := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(160, 1.0, 600)
	sand.mesh = bm
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0.42, 0.36, 0.27)
	sm.roughness = 0.95
	sand.material_override = sm
	sand.position = Vector3(60, 0.0, 0)
	top.add_child(sand)
	var e := _env("EYE", "-5,1.8,115,61.7,7").split(",")
	var cam := Camera3D.new()
	cam.fov = float(_env("FOV", "55"))
	cam.far = 12000.0
	cam.position = Vector3(float(e[0]), float(e[1]), float(e[2]))
	cam.rotation_degrees = Vector3(float(e[4]), float(e[3]), 0)
	top.add_child(cam)
	_day = (load("res://scripts/world/day_night.gd") as GDScript).new()
	_day.name = "DayNight"
	_day.set("sun_path", NodePath("../Sun"))
	_day.set("environment_path", NodePath("../Env"))
	top.add_child(_day)
	add_child(top)
	PierPark.build(Vector2.ZERO, top, null, null, _env("FAR", "0") != "1")
	cam.make_current()
	_frames = int(_env("FRAMES", "30"))
	Engine.time_scale = 0.0


func _process(_delta: float) -> void:
	_frame += 1
	_day.set("hour", float(_env("HOUR", "21")))
	_day.call("set_paused", true)
	RenderingServer.global_shader_parameter_set("night_atmos", Vector4(float(_env("HAZE", "0.3")), 1.0, 1.0, 720.0))
	if _env("T", "") != "" and _frame == 2:
		var t := float(_env("T", "0"))
		for m: Variant in [PierMesh.material("wheel"), PierMesh.material("park")]:
			(m as ShaderMaterial).set_shader_parameter("time_offset", t)
		for n in find_children("WheelGlow", "MeshInstance3D", true, false):
			((n as MeshInstance3D).mesh.surface_get_material(0) as ShaderMaterial).set_shader_parameter("time_offset", t)
	if _frame == _frames:
		var out := _env("OUT", "pier.png")
		get_viewport().get_texture().get_image().save_png(out)
		print("PIER wrote %s" % out)
		get_tree().quit()
