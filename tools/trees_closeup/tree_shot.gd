extends SceneTree
## Street trees close up (trees-closeup): a pavement with a row of the city's trees - three
## scanned street trees, the jacaranda, two palms and three code-built LA trees - lit like a
## street, seconds a still on opengl3, a minute or two on lavapipe Forward+.
##
##   OUT=build/tc/a xvfb-run -a -s "-screen 0 1280x720x24" godot --rendering-driver opengl3 \
##     --audio-driver Dummy --path . --script tools/trees_closeup/tree_shot.gd --resolution 1280x720
##   (Forward+: --rendering-driver vulkan with VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json)
##
## Env: OUT (a prefix: <OUT>_<view>.png), VIEWS=name,... (default all of VIEW_DEFS), LIGHT=noon |
## golden | night, FRAMES=n before each still (default 8; give Forward+ 24 for TAA), WIND=n
## (wind_factor), TIME_SKIP=seconds (frames are rendered with that much shader time between them),
## TREES_CLOSEUP=0 the before. CAM=x,y,z LOOK=x,y,z FOV=n for one free view named "free".
## The row runs along +X at z 0, the kerb at z 3, the camera on the pavement at z 7-9.

const VIEW_DEFS := {
	"street": [Vector3(-3.0, 1.7, 9.0), Vector3(4.0, 3.2, 0.0), 62.0],
	"palm_up": [Vector3(15.0, 1.6, 4.5), Vector3(17.0, 9.0, 0.0), 60.0],
	"jac": [Vector3(-14.0, 1.7, 6.5), Vector3(-17.0, 5.0, 0.0), 60.0],
	"crown": [Vector3(-4.0, 1.6, 4.5), Vector3(-4.5, 4.2, 0.0), 55.0],
	"car": [Vector3(30.0, 1.25, 4.0), Vector3(0.0, 3.5, 0.0), 58.0],
	"far": [Vector3(4.0, 2.0, 32.0), Vector3(4.0, 4.5, 0.0), 45.0],
	"la": [Vector3(30.0, 1.7, 9.0), Vector3(34.0, 4.5, 0.0), 60.0],
}

# [kind, arg, x, scale]: kind "scan" PropFactory.model_tree(arg), "palm" palm(arg), "la" LaTrees.
const ROW := [
	["scan", 4, -18.0, 0.42], ["scan", 0, -9.0, 1.45], ["scan", 2, -3.0, 1.5], ["scan", 1, 3.0, 1.6],
	["palm", 0, 9.0, 1.0], ["palm", 1, 16.0, 1.0], ["la", 3, 24.0, 0.75], ["la", 2, 31.0, 1.0],
	["la", 4, 37.0, 0.7],
]


func _initialize() -> void:
	var light := OS.get_environment("LIGHT")
	if light == "":
		light = "noon"
	var stage := Node3D.new()
	get_root().add_child(stage)
	# Forward+: TAA as the game runs it (Quality), so the leaf edge dither resolves.
	if OS.get_environment("TAA") == "1":
		get_root().use_taa = true
	var env := WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	match light:
		"golden":
			sm.sky_top_color = Color(0.25, 0.36, 0.58)
			sm.sky_horizon_color = Color(0.95, 0.66, 0.42)
		"night":
			sm.sky_top_color = Color(0.008, 0.012, 0.025)
			sm.sky_horizon_color = Color(0.06, 0.045, 0.035)
		_:
			sm.sky_top_color = Color(0.28, 0.45, 0.72)
			sm.sky_horizon_color = Color(0.72, 0.77, 0.82)
	sm.ground_horizon_color = Color(0.5, 0.48, 0.45) if light != "night" else Color(0.05, 0.04, 0.03)
	sm.ground_bottom_color = Color(0.2, 0.19, 0.18) if light != "night" else Color(0.02, 0.02, 0.02)
	sky.sky_material = sm
	e.sky = sky
	e.background_mode = Environment.BG_SKY
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.55 if light != "night" else 0.25
	e.tonemap_mode = Environment.TONE_MAPPER_AGX
	e.tonemap_exposure = 0.9 if light != "night" else 2.2
	env.environment = e
	stage.add_child(env)
	var wind := float(OS.get_environment("WIND")) if OS.get_environment("WIND") != "" else 1.0
	RenderingServer.global_shader_parameter_set("wind_factor", wind)
	RenderingServer.global_shader_parameter_set("lamp_factor", 1.0 if light == "night" else 0.0)
	RenderingServer.global_shader_parameter_set("night_factor", 1.0 if light == "night" else 0.0)
	var sun := DirectionalLight3D.new()
	match light:
		"golden":
			# Low in the west-south-west, behind the row from the pavement: the backlit crowns.
			sun.rotation_degrees = Vector3(-9.0, 165.0, 0.0)
			sun.light_color = Color(1.0, 0.72, 0.45)
			sun.light_energy = 1.6
		"night":
			sun.rotation_degrees = Vector3(-40.0, 30.0, 0.0)
			sun.light_color = Color(0.55, 0.62, 0.8)
			sun.light_energy = 0.04
		_:
			sun.rotation_degrees = Vector3(-58.0, 25.0, 0.0)
			sun.light_energy = 1.5
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 120.0
	stage.add_child(sun)
	RenderingServer.global_shader_parameter_set("sun_direction", sun.transform.basis.z)
	RenderingServer.global_shader_parameter_set("sky_tint", sm.sky_horizon_color)
	var pf: GDScript = load("res://scripts/world/prop_factory.gd")
	# Pavement, kerb, road; a wall behind the row for the dapples to fall on.
	_box(stage, Vector3(140.0, 0.15, 6.0), Vector3(10.0, 0.075, 0.0), _mat(Color(0.52, 0.5, 0.47), 0.9))
	_box(stage, Vector3(140.0, 0.02, 20.0), Vector3(10.0, -0.01, 13.0), _mat(Color(0.12, 0.12, 0.125), 0.85))
	if light != "golden":
		_box(stage, Vector3(140.0, 12.0, 1.0), Vector3(10.0, 6.0, -3.5), _mat(Color(0.62, 0.56, 0.5), 0.92))
	var la: GDScript = load("res://scripts/world/la_trees.gd")
	for r: Array in ROW:
		var m: Mesh
		match String(r[0]):
			"scan":
				m = pf.call("model_tree", int(r[1]))
			"palm":
				m = pf.call("palm", int(r[1]))
			_:
				m = la.call("mesh", int(r[1]), 0)
		var s: float = r[3]
		_place(stage, m, Transform3D(Basis().scaled(Vector3(s, s, s)).rotated(Vector3.UP, float(r[2]) * 0.37), Vector3(float(r[2]), 0.15, 0.0)))
	if light == "night":
		for x: float in [-12.0, 0.0, 12.0, 26.0]:
			var lamp := OmniLight3D.new()
			lamp.position = Vector3(x, 7.5, 2.6)
			lamp.light_color = Color(1.0, 0.78, 0.5)
			lamp.light_energy = 6.0
			lamp.omni_range = 18.0
			lamp.omni_attenuation = 1.4
			lamp.shadow_enabled = true
			stage.add_child(lamp)
	var cam := Camera3D.new()
	cam.far = 1500.0
	stage.add_child(cam)
	var views: Array = []
	if OS.get_environment("CAM") != "":
		views.append(["free", [_vec(OS.get_environment("CAM")), _vec(OS.get_environment("LOOK")), float(OS.get_environment("FOV")) if OS.get_environment("FOV") != "" else 60.0]])
	elif OS.get_environment("VIEWS") != "":
		for v in OS.get_environment("VIEWS").split(","):
			views.append([v, VIEW_DEFS[v]])
	else:
		for v: String in VIEW_DEFS:
			views.append([v, VIEW_DEFS[v]])
	var frames := int(OS.get_environment("FRAMES")) if OS.get_environment("FRAMES") != "" else 8
	var out := OS.get_environment("OUT")
	if out == "":
		out = "tree_shot"
	for v: Array in views:
		var d: Array = v[1]
		cam.fov = d[2]
		cam.look_at_from_position(d[0], d[1], Vector3.UP)
		cam.make_current()
		for i in frames:
			await process_frame
		var img := get_root().get_texture().get_image()
		img.save_png("%s_%s.png" % [out, v[0]])
		print("SAVED %s_%s.png" % [out, v[0]])
	quit()


func _mat(c: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m


func _box(stage: Node3D, size: Vector3, at: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.position = at
	mi.material_override = mat
	stage.add_child(mi)


func _place(stage: Node3D, mesh: Mesh, xf: Transform3D) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = 1
	mm.set_instance_transform(0, xf)
	mm.set_instance_color(0, Color.WHITE)
	mm.set_instance_custom_data(0, Color(0.2, 0.5, 0.5, 0.8))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	stage.add_child(mmi)


static func _vec(s: String) -> Vector3:
	var p := s.split(",")
	return Vector3(p[0].to_float(), p[1].to_float(), p[2].to_float())
