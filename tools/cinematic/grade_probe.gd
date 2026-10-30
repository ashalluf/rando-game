extends SceneTree
## The look on Forward+ in a minute (the cinematic review, docs/HANDOFF.md "The cinematic
## review"): the city's own Environment (copied out of city.tscn), its DayNight - exposure, bloom,
## fog, ambient and the per-hour grade - and sun, over a small set of test pieces that show what
## the grade does to real materials: an asphalt plane, a stucco wall, a brick wall, a red car-paint
## sphere and a chrome one (the sun's specular), a grey card, and an orange lamp box (bloom). The
## city does not fit lavapipe any more (grade_shot.tscn was OOM-killed in the macro setup on a
## 15 GB box), so this is the Forward+ check of a grade change.
##
##   OUT=/tmp/g HOURS=12,17.2,17.85,21.5 VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json \
##     xvfb-run -a -s "-screen 0 1280x720x24" godot --rendering-driver vulkan --display-driver x11 \
##     --audio-driver Dummy --path . --script tools/cinematic/grade_probe.gd --resolution 960x540
##
## Writes OUT_<hour>.png per hour. FRAMES per hour (default 20); YAW / PITCH / CAM_Y the camera;
## HOUR_GRADE=0 the old single curve.

var _frame := 0
var _frames := 20
var _hours: PackedStringArray
var _hi := 0
var _day: Node


func _env(key: String, def: String) -> String:
	var v := OS.get_environment(key)
	return v if v != "" else def


func _tex_mat(set_name: String, tile: float, tint: Color = Color.WHITE) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	var base := "res://assets/textures/%s/%s_1K-JPG_" % [set_name, set_name]
	m.albedo_texture = load(base + "Color.jpg")
	m.albedo_color = tint
	m.normal_enabled = true
	m.normal_texture = load(base + "NormalGL.jpg")
	m.roughness_texture = load(base + "Roughness.jpg")
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE / tile
	return m


func _box(parent: Node3D, size: Vector3, at: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = at
	mi.material_override = mat
	parent.add_child(mi)


func _sphere(parent: Node3D, r: float, at: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	mi.mesh = sm
	mi.position = at
	mi.material_override = mat
	parent.add_child(mi)


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
	var top := Node3D.new()
	top.name = "GradeProbe"
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
	pm.size = Vector2(4000, 4000)
	ground.mesh = pm
	ground.material_override = _tex_mat("Asphalt033", 4.0)
	top.add_child(ground)
	_box(top, Vector3(14, 9, 1), Vector3(-6, 4.5, -18), _tex_mat("BeigeWall001", 3.0))
	_box(top, Vector3(10, 12, 1), Vector3(9, 6, -22), _tex_mat("Bricks104", 2.0))
	var grey := StandardMaterial3D.new()
	grey.albedo_color = Color(0.18, 0.18, 0.18)
	grey.roughness = 0.9
	_box(top, Vector3(1.2, 1.8, 0.1), Vector3(-1.5, 0.9, -7), grey)
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color(0.45, 0.03, 0.03)
	paint.metallic = 0.3
	paint.roughness = 0.35
	paint.clearcoat_enabled = true
	paint.clearcoat = 1.0
	paint.clearcoat_roughness = 0.05
	_sphere(top, 1.0, Vector3(1.2, 1.0, -8), paint)
	var chrome := StandardMaterial3D.new()
	chrome.albedo_color = Color(0.9, 0.9, 0.9)
	chrome.metallic = 1.0
	chrome.roughness = 0.08
	_sphere(top, 0.7, Vector3(3.6, 0.7, -9), chrome)
	var lamp := StandardMaterial3D.new()
	lamp.albedo_color = Color(0.1, 0.1, 0.1)
	lamp.emission_enabled = true
	lamp.emission = Color(1.0, 0.55, 0.2)
	lamp.emission_energy_multiplier = 4.0
	_box(top, Vector3(0.6, 0.35, 0.35), Vector3(-3.5, 3.0, -9), lamp)
	var cam := Camera3D.new()
	cam.fov = 60.0
	cam.far = 6000.0
	cam.position = Vector3(0, float(_env("CAM_Y", "1.7")), 0)
	cam.rotation_degrees = Vector3(float(_env("PITCH", "4")), float(_env("YAW", "0")), 0)
	top.add_child(cam)
	_day = (load("res://scripts/world/day_night.gd") as GDScript).new()
	_day.name = "DayNight"
	_day.set("sun_path", NodePath("../Sun"))
	_day.set("environment_path", NodePath("../Env"))
	top.add_child(_day)
	root.add_child(top)
	cam.make_current()
	root.use_taa = true
	_frames = int(_env("FRAMES", "20"))
	_hours = _env("HOURS", "12").split(",")


func _process(_delta: float) -> bool:
	_frame += 1
	_day.set("hour", float(_hours[_hi]))
	_day.call("set_paused", true)
	if _frame == _frames:
		var out := "%s_%s.png" % [_env("OUT", "/tmp/grade_probe"), _hours[_hi]]
		root.get_texture().get_image().save_png(out)
		print("GRADE_PROBE wrote %s" % out)
		_frame = 0
		_hi += 1
		if _hi >= _hours.size():
			return true
	return false
