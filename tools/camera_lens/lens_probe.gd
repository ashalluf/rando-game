extends SceneTree
## The camera on Forward+ in minutes (docs/HANDOFF.md "The camera lens"): the city's own
## Environment (copied out of city.tscn), its DayNight and sun, the PLAYER camera's attributes
## (auto exposure, out of player.tscn) and the city's lens layer (vignette.gdshader at the city's
## numbers), over a small street: building blocks both sides, a concrete underpass 30 m long
## with two strip lights, chrome and red-paint spheres (the sun's glints), lamp boxes (bloom).
## CameraLens is attached as in the game (CAMERA_LENS=0 the before).
##
##   OUT=/tmp/lens VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json xvfb-run -a -s \
##     "-screen 0 1280x720x24" godot --rendering-driver vulkan --display-driver x11 \
##     --audio-driver Dummy --fixed-fps 30 --path . --script tools/camera_lens/lens_probe.gd \
##     --resolution 960x540
##
## MODE=shots (default): SHOTS="name@hour@x,y,z@yaw,pitch@frames;..." each held FRAMES then saved
##   as OUT_<name>.png (the auto exposure settles over the frames: 150 = 5 s at 30 fps).
## MODE=walk: the camera walks down the street at WALK_SPEED m/s from z +10 through the underpass
##   (z -50..-80) and out to z -110, after SETTLE seconds; every frame prints
##   "LENS_WALK t z p50 enclosure speed", frames at the seconds in SAVE_AT are saved as
##   OUT_walk_<t>.png. HOUR, YAW (0 = down the street, -Z), PITCH.
## Numbers per saved frame: "LENS_SHOT name p1 p5 p50 p95 p99".

var _frame := 0
var _shots: Array = []
var _si := 0
var _day: Node
var _cam: Camera3D
var _mode := "shots"
var _t := 0.0
var _save_at: PackedFloat64Array
var _saved := {}
var _lens: Node


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


func _box(parent: Node3D, size: Vector3, at: Vector3, mat: Material, solid: bool = true) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = at
	mi.material_override = mat
	parent.add_child(mi)
	if solid:
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = size
		cs.shape = sh
		body.add_child(cs)
		body.position = at
		parent.add_child(body)


func _sphere(parent: Node3D, r: float, at: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	mi.mesh = sm
	mi.position = at
	mi.material_override = mat
	parent.add_child(mi)


func _scene_resource(path: String, node_type: String, prop: String) -> Resource:
	var st := (load(path) as PackedScene).get_state()
	for i in st.get_node_count():
		if st.get_node_type(i) == node_type:
			for k in st.get_node_property_count(i):
				if st.get_node_property_name(i, k) == prop:
					return st.get_node_property_value(i, k)
	return null


func _initialize() -> void:
	Engine.set_meta("camera_lens_fixed", true)
	var env := (_scene_resource("res://scenes/levels/city.tscn", "WorldEnvironment", "environment") as Environment).duplicate(true) as Environment
	var attrs := (_scene_resource("res://scenes/player/player.tscn", "Camera3D", "attributes") as CameraAttributesPractical).duplicate(true) as CameraAttributesPractical
	attrs.dof_blur_far_enabled = false
	# LUM_OPEN=1 (with CAMERA_LENS=0): no clamp, so LUM=1 reads the frame's true metered value.
	if _env("LUM_OPEN", "0") == "1":
		attrs.auto_exposure_min_sensitivity = 1.0
		attrs.auto_exposure_max_sensitivity = 100000.0
	var top := Node3D.new()
	top.name = "LensProbe"
	var we := WorldEnvironment.new()
	we.name = "Env"
	we.environment = env
	top.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 300.0
	top.add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(4000, 4000)
	ground.mesh = pm
	ground.material_override = _tex_mat("Asphalt033", 4.0)
	top.add_child(ground)
	var walls := [_tex_mat("BeigeWall001", 3.0), _tex_mat("Bricks104", 2.0), _tex_mat("BeigeWall001", 3.0, Color(0.8, 0.85, 0.9))]
	# Blocks both sides of a 24 m street, leaving the underpass's stretch.
	var k := 0
	for side in [-1.0, 1.0]:
		var z := 30.0
		while z > -220.0:
			var len := 22.0 + float((k * 7) % 5) * 4.0
			var h := 14.0 + float((k * 11) % 7) * 4.0
			if z - len < -45.0 and z > -85.0:
				z = -85.0
				continue
			_box(top, Vector3(16, h, len - 3.0), Vector3(side * 20.0, h * 0.5, z - len * 0.5), walls[k % walls.size()])
			z -= len
			k += 1
	# The underpass: a deck over the street on two walls, open ends.
	var conc := _tex_mat("Concrete034", 3.0) if ResourceLoader.exists("res://assets/textures/Concrete034/Concrete034_1K-JPG_Color.jpg") else _tex_mat("BeigeWall001", 3.0, Color(0.7, 0.7, 0.7))
	_box(top, Vector3(30, 1.4, 30), Vector3(0, 7.2, -65), conc)
	_box(top, Vector3(1.2, 6.5, 30), Vector3(-12.6, 3.25, -65), conc)
	_box(top, Vector3(1.2, 6.5, 30), Vector3(12.6, 3.25, -65), conc)
	var strip := StandardMaterial3D.new()
	strip.albedo_color = Color(0.1, 0.1, 0.1)
	strip.emission_enabled = true
	strip.emission = Color(0.85, 0.92, 1.0)
	strip.emission_energy_multiplier = 3.0
	for zz in [-55.0, -65.0, -75.0]:
		_box(top, Vector3(0.25, 0.08, 3.0), Vector3(-6.0, 6.45, zz), strip, false)
		_box(top, Vector3(0.25, 0.08, 3.0), Vector3(6.0, 6.45, zz), strip, false)
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color(0.45, 0.03, 0.03)
	paint.metallic = 0.3
	paint.roughness = 0.35
	paint.clearcoat_enabled = true
	paint.clearcoat = 1.0
	paint.clearcoat_roughness = 0.05
	_sphere(top, 1.0, Vector3(-3.0, 1.0, -22), paint)
	var chrome := StandardMaterial3D.new()
	chrome.albedo_color = Color(0.9, 0.9, 0.9)
	chrome.metallic = 1.0
	chrome.roughness = 0.08
	_sphere(top, 0.7, Vector3(3.5, 0.7, -26), chrome)
	var lamp := StandardMaterial3D.new()
	lamp.albedo_color = Color(0.1, 0.1, 0.1)
	lamp.emission_enabled = true
	lamp.emission = Color(1.0, 0.55, 0.2)
	lamp.emission_energy_multiplier = 4.0
	for zz in [-10.0, -35.0, -100.0, -125.0]:
		_box(top, Vector3(0.6, 0.3, 0.35), Vector3(-10.5, 7.5, zz), lamp, false)
		_box(top, Vector3(0.6, 0.3, 0.35), Vector3(10.5, 7.5, zz), lamp, false)
	# The camera the way the player's rig holds it.
	var rig := Node3D.new()
	rig.name = "Rig"
	var arm := Node3D.new()
	arm.name = "SpringArm3D"
	rig.add_child(arm)
	_cam = Camera3D.new()
	_cam.name = "Camera3D"
	_cam.fov = 70.0
	_cam.far = 6000.0
	_cam.attributes = attrs
	arm.add_child(_cam)
	top.add_child(rig)
	_day = (load("res://scripts/world/day_night.gd") as GDScript).new()
	_day.name = "DayNight"
	_day.set("sun_path", NodePath("../Sun"))
	_day.set("environment_path", NodePath("../Env"))
	top.add_child(_day)
	# The city's lens layer, at the city's numbers.
	var layer := CanvasLayer.new()
	layer.name = "Vignette"
	layer.layer = -1
	layer.add_to_group("lens_layer")
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/vignette.gdshader")
	mat.set_shader_parameter("strength", 0.24)
	mat.set_shader_parameter("grain", 0.028)
	mat.set_shader_parameter("fringe", 0.0016)
	rect.material = mat
	layer.add_child(rect)
	top.add_child(layer)
	if CameraLens.enabled:
		_lens = CameraLens.new()
		_lens.name = "Lens"
		rig.add_child(_lens)
	root.add_child(top)
	_cam.make_current()
	root.use_taa = true
	# LUM=1: draw Godot's metered scene luminance instead of the picture (what the auto exposure
	# divides by; the shot's LENS_LUM line is its value). The gain is scale / clamp(lum, min, max).
	if _env("LUM", "0") == "1":
		root.debug_draw = Viewport.DEBUG_DRAW_SCENE_LUMINANCE
	_mode = _env("MODE", "shots")
	for s in _env("SHOTS", "street@12@0,1.7,10@0,4@120").split(";", false):
		_shots.append(s.split("@"))
	for v in _env("SAVE_AT", "2,4,5,6,7,8,10,12,13,14,15,16,18").split(","):
		_save_at.append(float(v))


func _stats(img: Image) -> String:
	var lum := PackedFloat32Array()
	var w := img.get_width()
	var h := img.get_height()
	for y in range(0, h, 4):
		for x in range(0, w, 4):
			var c := img.get_pixel(x, y)
			lum.append(255.0 * (0.299 * c.r + 0.587 * c.g + 0.114 * c.b))
	lum.sort()
	var out := []
	for p in [1, 5, 50, 95, 99]:
		out.append(roundi(lum[mini(int(lum.size() * p / 100.0), lum.size() - 1)]))
	return " ".join(out.map(func(v): return str(v)))


func _place(pos: Vector3, yaw: float, pitch: float) -> void:
	var rig := _cam.get_parent().get_parent() as Node3D
	rig.global_position = pos
	_cam.rotation_degrees = Vector3(pitch, yaw, 0.0)


func _process(delta: float) -> bool:
	if _mode == "walk":
		return _walk(delta)
	var s: Array = _shots[_si]
	_day.set("hour", float(s[1]))
	_day.call("set_paused", true)
	var p := (s[2] as String).split(",")
	var a := (s[3] as String).split(",")
	_place(Vector3(float(p[0]), float(p[1]), float(p[2])), float(a[0]), float(a[1]))
	_frame += 1
	if _frame == int(s[4]):
		var img := root.get_texture().get_image()
		img.save_png("%s_%s.png" % [_env("OUT", "/tmp/lens"), s[0]])
		if root.debug_draw == Viewport.DEBUG_DRAW_SCENE_LUMINANCE:
			var c := img.get_pixel(img.get_width() / 2, img.get_height() / 2)
			print("LENS_LUM %s %.4f (min %.4f max %.4f)" % [s[0], c.r, _cam.attributes.auto_exposure_min_sensitivity * 0.00125,
					_cam.attributes.auto_exposure_max_sensitivity * 0.00125])
		print("LENS_SHOT %s %s flare %.2f encl %.2f" % [s[0], _stats(img),
				float(_lens.get("flare_now")) if _lens else 0.0, float(_lens.get("enclosure")) if _lens else 0.0])
		_frame = 0
		_si += 1
		if _si >= _shots.size():
			return true
	return false


func _walk(delta: float) -> bool:
	_day.set("hour", float(_env("HOUR", "12")))
	_day.call("set_paused", true)
	_t += delta
	var settle := float(_env("SETTLE", "4"))
	var speed := float(_env("WALK_SPEED", "6"))
	var z := 10.0 - maxf(_t - settle, 0.0) * speed
	_place(Vector3(0.0, 1.7, maxf(z, -110.0)), float(_env("YAW", "0")), float(_env("PITCH", "2")))
	var img := root.get_texture().get_image()
	var st := _stats(img)
	print("LENS_WALK %.2f %.1f %s encl %.2f speed %.2f" % [_t, z, st,
			float(_lens.get("enclosure")) if _lens else 0.0, float(_lens.get("speed_now")) if _lens else 0.0])
	for sa in _save_at:
		if _t >= sa and not _saved.has(sa):
			_saved[sa] = true
			img.save_png("%s_walk_%04.1f.png" % [_env("OUT", "/tmp/lens"), sa])
	return z <= -110.0 and _t > settle + 120.0 / speed + float(_env("TAIL", "3"))
