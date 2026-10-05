extends SceneTree
## The murals on their own (scripts/world/murals.gd, shaders/mural.gdshader): a long stucco wall
## carrying every scene, a brick wall with ghost signs, a strip of road with each painted
## crosswalk pattern, and painted signal cabinets. Seconds a frame instead of minutes for a city
## still.
##
##   OUT=m.png CAM=0,3,22 LOOK=0,3,0 xvfb-run -a -s "-screen 0 1280x720x24" godot \
##     --rendering-driver opengl3 --audio-driver Dummy --path . \
##     --script tools/glshot/mural_shot.gd --resolution 1280x720
##
## Env: OUT, CAM, LOOK (x,y,z), FOV, SEED (0..1), AGE (0..1), WEAR (0..7). Layout: the mural
## wall runs along x at z 0 facing +z, six 9 x 5 m murals from x -30 (coast, mountains, desert,
## botanical, folk, waves), a frieze over them at y 6; the brick wall at x 40..60 (ghost signs);
## the road at z 10..40 from x -30 (four crosswalks, 12 x 3 m, 5 m apart in z); the cabinets at
## z 6 from x -30, 3 m apart.
func _initialize() -> void:
	var stage := Node3D.new()
	get_root().add_child(stage)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.3, 0.45, 0.68)
	sky_mat.sky_horizon_color = Color(0.7, 0.74, 0.78)
	sky_mat.ground_horizon_color = Color(0.5, 0.48, 0.45)
	sky_mat.ground_bottom_color = Color(0.2, 0.19, 0.18)
	sky.sky_material = sky_mat
	e.sky = sky
	e.background_mode = Environment.BG_SKY
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.45
	e.tonemap_mode = Environment.TONE_MAPPER_AGX
	e.tonemap_exposure = 1.25
	env.environment = e
	stage.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, 25.0, 0.0)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	stage.add_child(sun)
	var mur: GDScript = load("res://scripts/world/murals.gd")
	var seed01 := float(OS.get_environment("SEED")) if OS.get_environment("SEED") != "" else 0.37
	var age := float(OS.get_environment("AGE")) if OS.get_environment("AGE") != "" else 0.25
	var wear := int(OS.get_environment("WEAR")) if OS.get_environment("WEAR") != "" else 2
	_box(stage, Vector3(-36.0, 0.0, -0.4), Vector3(66.0, 9.0, 0.4), Color(0.78, 0.74, 0.66), "stucco")
	_box(stage, Vector3(38.0, 0.0, -0.4), Vector3(24.0, 14.0, 0.4), Color(0.55, 0.3, 0.24), "brick")
	_box(stage, Vector3(-40.0, -0.1, 0.0), Vector3(120.0, 0.1, 50.0), Color(0.14, 0.14, 0.145), "asphalt")
	var xf: Array = []
	var cols: Array = []
	var cus: Array = []
	for i in 6:
		var w := 9.0
		var h := 5.0
		var c := Vector3(-30.0 + i * 10.5 + w * 0.5, 0.4 + h * 0.5, 0.01)
		xf.append(Transform3D(Basis(Vector3.RIGHT * w, Vector3.UP * h, Vector3.BACK * w), c))
		cols.append(Color(w, age, 0.0, 1.0))
		cus.append(mur.call("custom", mur.MODE_MURAL, i, fmod(seed01 + i * 0.13, 1.0), 0.0, 0, wear))
	# A frieze along the top.
	xf.append(Transform3D(Basis(Vector3.RIGHT * 60.0, Vector3.UP * 1.2, Vector3.BACK * 60.0), Vector3(0.0, 7.0, 0.01)))
	cols.append(Color(60.0, age, 0.0, 1.0))
	cus.append(mur.call("custom", mur.MODE_FRIEZE, 0, seed01, 0.0, 0, wear))
	# Ghost signs on the brick.
	for i in 4:
		var w := 8.0
		var h := 2.0
		var c := Vector3(42.0 + (i % 2) * 9.0 + w * 0.5, 4.0 + (i / 2) * 5.0, 0.01)
		xf.append(Transform3D(Basis(Vector3.RIGHT * w, Vector3.UP * h, Vector3.BACK * w), c))
		cols.append(Color(0.55, 0.3, 0.24, age + 0.4))
		cus.append(mur.call("custom", mur.MODE_GHOST, 0, fmod(seed01 + i * 0.29, 1.0), float(i * 3 % 16), 2, wear))
	# Crosswalks on the road.
	for i in 4:
		var c := Vector3(-24.0, 0.01, 12.0 + i * 5.0)
		xf.append(Transform3D(Basis(Vector3.RIGHT * 12.0, Vector3.FORWARD * 3.0, Vector3.UP * 12.0), c))
		cols.append(Color(12.0, age, 0.0, 1.0))
		cus.append(mur.call("custom", mur.MODE_CROSSWALK, i, seed01, 0.0, 4, wear))
	# Cabinets: a box and a wrap on its four faces.
	for i in 4:
		var at := Vector3(-30.0 + i * 3.0, 0.0, 6.0)
		_box(stage, at + Vector3(-0.39, 0.12, -0.26), Vector3(0.78, 1.44, 0.52), Color(0.66, 0.68, 0.63), "steel")
		for f: Array in mur.call("cabinet_faces"):
			var n: Vector3 = f[1]
			var w: float = f[2]
			var right := Vector3.UP.cross(n)
			xf.append(Transform3D(Basis(right * w, Vector3.UP * float(f[3]), n * w), at + (f[0] as Vector3)))
			cols.append(Color(w, age * 0.5, 0.0, 1.0))
			cus.append(mur.call("custom", mur.MODE_WRAP, (i * 2 + 1) % 6, fmod(seed01 + i * 0.21, 1.0), 0.0, 5, 0))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = mur.call("mesh")
	mm.instance_count = xf.size()
	for i in xf.size():
		mm.set_instance_transform(i, xf[i])
		mm.set_instance_color(i, cols[i])
		mm.set_instance_custom_data(i, cus[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	stage.add_child(mmi)
	var cam := Camera3D.new()
	cam.fov = float(OS.get_environment("FOV")) if OS.get_environment("FOV") != "" else 50.0
	stage.add_child(cam)
	cam.look_at_from_position(_vec(OS.get_environment("CAM"), Vector3(-12.0, 3.0, 26.0)), _vec(OS.get_environment("LOOK"), Vector3(-12.0, 3.0, 0.0)), Vector3.UP)
	cam.make_current()
	for i in 8:
		await process_frame
	var img := get_root().get_texture().get_image()
	var out := OS.get_environment("OUT")
	img.save_png(out if out != "" else "mural_shot.png")
	quit()


## A plain box from `corner` (min x, min y, min z) of `size`.
func _box(stage: Node3D, corner: Vector3, size: Vector3, color: Color, kind: String) -> void:
	var g := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	g.mesh = b
	g.position = corner + size * 0.5
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.9
	var tex := {"stucco": "res://assets/textures/plaster/plaster_Color.jpg", "brick": "", "asphalt": "", "steel": ""}
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(0.5, 0.5, 0.5)
	var noise := NoiseTexture2D.new()
	noise.noise = FastNoiseLite.new()
	noise.noise.frequency = 0.08 if kind != "brick" else 0.3
	noise.seamless = true
	m.albedo_texture = noise if kind != "steel" else null
	m.albedo_color = color * 1.6 if kind != "steel" else color
	g.material_override = m
	stage.add_child(g)


static func _vec(s: String, fallback: Vector3) -> Vector3:
	if s == "":
		return fallback
	var p := s.split(",")
	return Vector3(p[0].to_float(), p[1].to_float(), p[2].to_float())
