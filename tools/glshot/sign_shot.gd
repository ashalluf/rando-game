extends SceneTree
## The boulevard signs on their own (scripts/world/sign_kit.gd, BoulevardSigns): every pole sign
## in a row along a pavement, a post of plates, a lamp banner pair, window vinyl and a band banner
## on a wall, lit by day or at night (lamp_factor 1). Seconds a frame instead of minutes.
##
##   OUT=s.png CAM=-6,3,16 LOOK=6,6,0 xvfb-run -a -s "-screen 0 1280x720x24" godot \
##     --rendering-driver opengl3 --audio-driver Dummy --path . \
##     --script tools/glshot/sign_shot.gd --resolution 1280x720
##
## Env: OUT, CAM, LOOK (x,y,z), FOV, NIGHT=1, MOTEL=n (the first motel's variant), FLAGS (the
## motels' flags: 1 NO lit, 2 a failing tube). Layout: the kerb along x at z 0, the road at z > 0,
## the poles at z -4.35 every 9 m from x -12 (tenant, motel, motel, liquor, checks, tire), their
## faces along x; a post, lamp banners and a wall with vinyl and a banner at x 44.. . Prints each
## mesh's triangles.
func _initialize() -> void:
	var night := OS.get_environment("NIGHT") == "1"
	var stage := Node3D.new()
	get_root().add_child(stage)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.3, 0.45, 0.68) if not night else Color(0.01, 0.015, 0.03)
	sky_mat.sky_horizon_color = Color(0.7, 0.74, 0.78) if not night else Color(0.05, 0.04, 0.04)
	sky_mat.ground_horizon_color = Color(0.5, 0.48, 0.45) if not night else Color(0.03, 0.03, 0.03)
	sky_mat.ground_bottom_color = Color(0.2, 0.19, 0.18) if not night else Color(0.01, 0.01, 0.01)
	sky.sky_material = sky_mat
	e.sky = sky
	e.background_mode = Environment.BG_SKY
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.45 if not night else 0.25
	e.tonemap_mode = Environment.TONE_MAPPER_AGX
	e.tonemap_exposure = 1.25 if not night else 1.6
	e.glow_enabled = night
	env.environment = e
	stage.add_child(env)
	RenderingServer.global_shader_parameter_set("lamp_factor", 1.0 if night else 0.0)
	RenderingServer.global_shader_parameter_set("night_factor", 1.0 if night else 0.0)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, 35.0, 0.0)
	sun.light_energy = 1.3 if not night else 0.03
	sun.shadow_enabled = true
	stage.add_child(sun)
	# Road and pavement.
	for i in 2:
		var g := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(140.0, 0.1 if i == 0 else 0.25, 12.0)
		g.mesh = b
		g.position = Vector3(20.0, 0.05 if i == 0 else 0.125, 6.0 if i == 0 else -6.0)
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.12, 0.12, 0.125) if i == 0 else Color(0.55, 0.54, 0.52)
		m.roughness = 0.9
		g.material_override = m
		stage.add_child(g)
	var bs: GDScript = load("res://scripts/world/boulevard_signs.gd")
	var kit: GDScript = load("res://scripts/world/sign_kit.gd")
	var motel := int(OS.get_environment("MOTEL")) if OS.get_environment("MOTEL") != "" else 0
	var flags := float(OS.get_environment("FLAGS")) if OS.get_environment("FLAGS") != "" else 1.0
	var poles := [[0, 1, 3], [1, motel, 12], [1, (motel + 2) % 5, 14], [2, 5, 0], [3, 7, 0], [4, 9, 0]]
	# The sign's +x into the lot (-z here), its faces along the street (+-x).
	var xb := Basis(Vector3(0, 0, -1), Vector3.UP, Vector3(0, 0, -1).cross(Vector3.UP))
	for i in poles.size():
		var p: Array = poles[i]
		var m: Mesh = bs.call("pole_mesh", p[0], p[1])
		_place(stage, m, Transform3D(xb, Vector3(-12.0 + i * 9.0, 0.25, -4.35)), Color(float(p[1]), float(p[2]), flags, 0.3 * i))
		print("pole ", p[0], ": ", (m.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3, " triangles")
	# A post of plates, facing +x.
	var face := Vector3(1, 0, 0)
	var pb := Basis(Vector3.UP.cross(face), Vector3.UP, face)
	_place(stage, kit.call("post"), Transform3D(Basis(), Vector3(44.0, 0.25, -0.45)), Color.BLACK)
	var y := 2.95 - 0.23
	for c: int in [5, 0, 2, 17]:
		var b := pb
		if c == 16 or c == 17:
			b = Basis(pb.x, pb.y * 0.55, pb.z)
		_place(stage, kit.call("plate"), Transform3D(b, Vector3(44.0, 0.25 + y, -0.45) + face * 0.03), Color(float(c), 0, 0, 0.1))
		y -= 0.49
	# A lamp pole with banners (a plain cylinder for the pole).
	var lp := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.05
	cyl.bottom_radius = 0.1
	cyl.height = 6.0
	lp.mesh = cyl
	lp.position = Vector3(48.0, 3.25, -1.0)
	stage.add_child(lp)
	var to_road := Vector3(0, 0, 1)
	_place(stage, kit.call("lamp_banner_arms"), Transform3D(Basis(to_road, Vector3.UP, to_road.cross(Vector3.UP)), Vector3(48.0, 0.25 + 2.3, -1.0)), Color.BLACK)
	for side: float in [-1.0, 1.0]:
		var x := to_road * side
		_place(stage, kit.call("lamp_banner"), Transform3D(Basis(x, Vector3.UP, x.cross(Vector3.UP)), Vector3(48.0, 0.25 + 2.3, -1.0) + x * 0.08), Color(1, 0, 0, 0.3))
	# A wall with vinyl and a banner, facing +z.
	var wall := MeshInstance3D.new()
	var wb := BoxMesh.new()
	wb.size = Vector3(10.0, 5.0, 0.4)
	wall.mesh = wb
	wall.position = Vector3(56.0, 2.75, -4.2)
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(0.08, 0.1, 0.12)
	wm.roughness = 0.1
	wall.material_override = wm
	stage.add_child(wall)
	var n := Vector3(0, 0, 1)
	var vb := Basis(Vector3.UP.cross(n), Vector3.UP, n)
	var cells := [0, 1, 2, 3, 4, 6, 8, 11]
	for i in cells.size():
		var s := 0.6
		_place(stage, kit.call("vinyl"), Transform3D(vb.scaled(Vector3(s, s, s)), Vector3(52.0 + (i % 4) * 1.4, 1.1 + (i / 4) * 0.9, -3.99)), Color(float(cells[i]), 0, 0, 0.2))
	_place(stage, kit.call("band_banner"), Transform3D(vb.scaled(Vector3(0.7, 0.7, 0.7)), Vector3(56.0, 4.3, -3.86)), Color(0, 0, 0, 0.2))
	_place(stage, kit.call("wayfinding"), Transform3D(pb, Vector3(41.0, 0.25, -0.75)), Color(0, 6, 0, 0.2))
	if night:
		var l := OmniLight3D.new()
		l.position = Vector3(10.0, 4.0, 4.0)
		l.omni_range = 30.0
		l.light_energy = 1.2
		l.light_color = Color(1.0, 0.75, 0.45)
		stage.add_child(l)
	var cam := Camera3D.new()
	cam.fov = float(OS.get_environment("FOV")) if OS.get_environment("FOV") != "" else 50.0
	stage.add_child(cam)
	cam.look_at_from_position(_vec(OS.get_environment("CAM"), Vector3(-6.0, 3.0, 16.0)), _vec(OS.get_environment("LOOK"), Vector3(6.0, 6.0, -3.0)), Vector3.UP)
	cam.make_current()
	for i in 8:
		await process_frame
	var img := get_root().get_texture().get_image()
	var out := OS.get_environment("OUT")
	img.save_png(out if out != "" else "sign_shot.png")
	quit()


func _place(stage: Node3D, mesh: Mesh, xf: Transform3D, custom: Color) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = 1
	mm.set_instance_transform(0, xf)
	mm.set_instance_color(0, Color.WHITE)
	mm.set_instance_custom_data(0, custom)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	stage.add_child(mmi)


static func _vec(s: String, fallback: Vector3) -> Vector3:
	if s == "":
		return fallback
	var p := s.split(",")
	return Vector3(p[0].to_float(), p[1].to_float(), p[2].to_float())
