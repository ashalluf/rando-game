extends Node
## The street_noon refcam's ground on either renderer in a minute or two (docs/HANDOFF.md, the
## street_noon review): the city's Environment, DayNight and sun (as tools/cinematic/grade_probe.gd)
## over the REAL materials of a downtown street - the carriageway on PropFactory.road() with each of
## CityChunk.ROAD_TINTS on both asphalt sets in strips, a pavement slab on the downtown sidewalk look
## and a car-height grey card - so the road against the pavement can be measured where the Mac
## draws it (Forward+, lavapipe) as well as on opengl3. Prints the mean sRGB of every strip.
##
##   OUT=/tmp/r HOURS=12 VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json xvfb-run -a -s \
##     "-screen 0 1280x720x24" godot --rendering-driver vulkan --display-driver x11 \
##     --audio-driver Dummy --path . res://tools/rc_street_noon/road_probe.tscn --resolution 960x540
##
## (--rendering-driver opengl3 for the Compatibility path.) FRAMES per hour (default 24).

var _frame := 0
var _frames := 24
var _hours: PackedStringArray
var _hi := 0
var _day: Node
var _cam: Camera3D
var _probes: Array = []


func _env(key: String, def: String) -> String:
	var v := OS.get_environment(key)
	return v if v != "" else def


func _box(parent: Node3D, size: Vector3, at: Vector3, mat: Material, label: String = "") -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = at
	mi.material_override = mat
	parent.add_child(mi)
	if label != "":
		_probes.append([label, at + Vector3(0, size.y * 0.5, 0)])


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
	var we := WorldEnvironment.new()
	we.name = "Env"
	we.environment = env
	top.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = true
	top.add_child(sun)
	# Strips of carriageway running away from the camera: every tint on both sets.
	var tints: Array = (load("res://scripts/world/city_chunk.gd") as GDScript).get("ROAD_TINTS")
	var x := -9.0
	for set_key: String in ["asphalt", "asphalt_aerial"]:
		for i in tints.size():
			var mat := PropFactory.road(set_key, 7.0 if set_key == "asphalt" else 9.0, tints[i], 1000 + i)
			_box(top, Vector3(1.8, 0.2, 40.0), Vector3(x, -0.1, -24.0), mat, "%s_%d" % [set_key, i])
			x += 1.8
	# The downtown pavement (CityPlan DOWNTOWN "paving" sidewalk row) and the plaza paving.
	var side := PropFactory.road("sidewalk", 3.0, Color(1.52, 1.52, 1.52), 77, 1.5, 0.45)
	_box(top, Vector3(6.0, 0.35, 40.0), Vector3(x + 3.2, 0.0, -24.0), side, "sidewalk_1.52")
	# A bike lane (Micromobility's paint) on the first tint's asphalt, kerb side to the left.
	var under := PropFactory.road("asphalt", 7.0, tints[0], 1100)
	_box(top, Vector3(2.6, 0.2, 40.0), Vector3(-11.2, -0.1, -24.0), under, "")
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = (load("res://scripts/world/micromobility.gd") as GDScript).call("lane_mesh")
	mm.instance_count = 1
	mm.set_instance_transform(0, Transform3D(Basis().scaled(Vector3(2.6, 1.0, 40.0)), Vector3(-11.2, 0.004, -24.0)))
	mm.set_instance_custom_data(0, Color(1.0, 0.0, 1.0, 0.0))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	top.add_child(mmi)
	_probes.append(["bike_lane", Vector3(-11.45, 0.0, 0.0)])
	var grey := StandardMaterial3D.new()
	grey.albedo_color = Color(0.18, 0.18, 0.18)
	grey.roughness = 0.9
	_box(top, Vector3(1.2, 1.8, 0.1), Vector3(-14.5, 0.9, -12), grey, "")
	_cam = Camera3D.new()
	_cam.fov = 55.0
	_cam.far = 3000.0
	_cam.position = Vector3(0, 9.0, 4.0)
	_cam.rotation_degrees = Vector3(-38.0, 0, 0)
	top.add_child(_cam)
	_day = (load("res://scripts/world/day_night.gd") as GDScript).new()
	_day.name = "DayNight"
	_day.set("sun_path", NodePath("../Sun"))
	_day.set("environment_path", NodePath("../Env"))
	top.add_child(_day)
	add_child(top)
	_cam.make_current()
	get_viewport().use_taa = true
	_frames = int(_env("FRAMES", "24"))
	_hours = _env("HOURS", "12").split(",")


func _process(_delta: float) -> void:
	_frame += 1
	_day.set("hour", float(_hours[_hi]))
	_day.call("set_paused", true)
	if _frame == _frames:
		var img := get_viewport().get_texture().get_image()
		var out := "%s_%s.png" % [_env("OUT", "/tmp/road_probe"), _hours[_hi]]
		img.save_png(out)
		print("ROAD_PROBE wrote %s (%s)" % [out, RenderingServer.get_current_rendering_driver_name()])
		for p in _probes:
			# Mean sRGB over a patch 12 m down the strip.
			var w := Vector3(p[1].x, p[1].y, -14.0)
			var s := _cam.unproject_position(w)
			var acc := Color(0, 0, 0)
			var n := 0
			for dy in range(-6, 7):
				for dx in range(-3, 4):
					var px := Vector2i(int(s.x) + dx, int(s.y) + dy)
					if px.x >= 0 and px.y >= 0 and px.x < img.get_width() and px.y < img.get_height():
						acc += img.get_pixelv(px)
						n += 1
			acc /= maxf(1.0, n)
			print("ROAD_PROBE %s %s %d %d %d" % [_hours[_hi], p[0], int(acc.r * 255), int(acc.g * 255), int(acc.b * 255)])
		_frame = 0
		_hi += 1
		if _hi >= _hours.size():
			get_tree().quit()
