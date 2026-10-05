extends SceneTree
## The street furniture on its own (scripts/world/street_furniture.gd): every piece in a row on a
## pavement by a kerb, daylight or night. Seconds a frame instead of minutes for a city still.
##
##   OUT=f.png CAM=-1,1.6,-6 LOOK=1.5,0.7,0 xvfb-run -a -s "-screen 0 1280x720x24" godot \
##     --rendering-driver opengl3 --audio-driver Dummy --path . \
##     --script tools/glshot/furniture_shot.gd --resolution 1280x720
##
## Env: OUT, CAM, LOOK (x,y,z), FOV, NIGHT=1, OLD=1 (the old meshes in the same places: the
## before), WEAR=0..1 (every piece's wear), WET=0..1, AD=n (the bench's ad). Layout: the kerb
## runs along x at z 0, the road at z > 0; pieces stand at z -0.6 from x -4, 1.4 m apart: hydrant,
## meter, pay station, bench, bin, three carts, bike racks, planter. Prints each mesh's triangles.
func _initialize() -> void:
	# Classes by path, a frame in: the script is compiled before the autoloads exist.
	await process_frame
	var pf: GDScript = load("res://scripts/world/prop_factory.gd")
	var sd: GDScript = load("res://scripts/world/street_detail.gd")
	var night := OS.get_environment("NIGHT") == "1"
	var old := OS.get_environment("OLD") == "1"
	var wear := float(OS.get_environment("WEAR")) if OS.get_environment("WEAR") != "" else 0.35
	if OS.get_environment("DEBUG") != "":
		var sfm: ShaderMaterial = (load("res://scripts/world/street_furniture.gd") as GDScript).call("material")
		sfm.set_shader_parameter("debug_mode", int(OS.get_environment("DEBUG")))
		if OS.get_environment("CULL") == "0":
			var sh := Shader.new()
			sh.code = sfm.shader.code.replace("render_mode cull_back;", "render_mode cull_disabled;")
			sfm.shader = sh
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
	RenderingServer.global_shader_parameter_set("road_wetness", float(OS.get_environment("WET")) if OS.get_environment("WET") != "" else 0.0)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42.0, 145.0, 0.0)
	sun.light_energy = 1.3 if not night else 0.03
	sun.shadow_enabled = OS.get_environment("NOSHADOW") != "1"
	stage.add_child(sun)
	for i in 2:
		var g := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(40.0, 0.1 if i == 0 else 0.25, 12.0)
		g.mesh = b
		g.position = Vector3(0.0, 0.05 if i == 0 else 0.125, 6.0 if i == 0 else -6.0)
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.12, 0.12, 0.125) if i == 0 else Color(0.55, 0.54, 0.52)
		m.roughness = 0.9
		g.material_override = m
		stage.add_child(g)
	var top := 0.25
	var face := Basis(Vector3.UP, PI)   # local -Z (the front) toward the road (+z)
	var x := -4.0
	var ad := float(OS.get_environment("AD")) if OS.get_environment("AD") != "" else 1.0
	if old:
		_place(stage, pf.call("model_hydrant", false), Transform3D(face, Vector3(x, top, -0.6)), Color.BLACK)
		_place(stage, sd.call("_meter_mesh"), Transform3D(face, Vector3(x + 1.4, top, -0.6)), Color.BLACK)
		_place(stage, sd.call("_meter_mesh"), Transform3D(face, Vector3(x + 2.8, top, -0.6)), Color.BLACK)
		_place(stage, pf.call("model_bench"), Transform3D(face, Vector3(x + 4.8, top, -1.0)), Color.BLACK)
		_place(stage, pf.call("model_trash_can", false), Transform3D(face, Vector3(x + 6.8, top, -0.6)), Color.BLACK)
		for k in 3:
			_place(stage, pf.call("bike_rack"), Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(x + 11.6, top, -1.6 + k * 0.8)), Color.BLACK)
		_place(stage, pf.call("model_planter"), Transform3D(face, Vector3(x + 13.4, top, -1.2)), Color.BLACK)
	else:
		var sf: GDScript = load("res://scripts/world/street_furniture.gd")
		_place(stage, sf.call("hydrant"), Transform3D(face, Vector3(x, top, -0.6)), Color(0.86, 0.68, 0.10, wear))
		_place(stage, sf.call("meter"), Transform3D(face, Vector3(x + 1.4, top, -0.6)), Color(0.3, 0.32, 0.34, wear))
		_place(stage, sf.call("pay_station"), Transform3D(face, Vector3(x + 2.8, top, -0.6)), Color(0.16, 0.17, 0.18, wear))
		_place(stage, sf.call("ad_bench"), Transform3D(face, Vector3(x + 4.8, top, -1.0)), Color((ad + 0.5) / 16.0, 0.0, 0.0, wear))
		_place(stage, sf.call("mesh_bin"), Transform3D(face, Vector3(x + 6.8, top, -0.6)), Color(0.07, 0.075, 0.08, wear))
		for k in 3:
			var p: Color = (sf.get("CART_PAINTS") as Array)[k]
			_place(stage, sf.call("cart"), Transform3D(face.rotated(Vector3.UP, (k - 1) * 0.1), Vector3(x + 8.2 + k * 0.8, top, -0.5)), Color(p.r, p.g, p.b, wear))
		for k in 3:
			_place(stage, sf.call("bike_rack"), Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(x + 11.6, top, -1.6 + k * 0.8)), Color(0, 0, 0, wear))
		var pl: Array = sf.call("planter_instances", 7, Transform3D(face, Vector3(x + 13.4, top, -1.2)))
		for inst in pl:
			_place(stage, inst[1], inst[2], inst[4] if inst.size() > 4 else Color.BLACK, inst[3] if inst.size() > 3 else Color.WHITE)
		for n in ["hydrant", "meter", "pay_station", "ad_bench", "mesh_bin", "cart", "bike_rack", "planter"]:
			var m: Mesh = sf.call(n)
			var tris := (m.surface_get_arrays(0)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
			print("MESH %s: %d triangles, shadow proxy %s" % [n, tris, str(pf.call("shadow_proxy", m) != null)])
	if night:
		var l := OmniLight3D.new()
		l.position = Vector3(2.0, 4.0, 0.5)
		l.omni_range = 14.0
		l.light_energy = 2.0
		l.light_color = Color(1.0, 0.8, 0.55)
		stage.add_child(l)
	var cam := Camera3D.new()
	cam.fov = float(OS.get_environment("FOV")) if OS.get_environment("FOV") != "" else 50.0
	stage.add_child(cam)
	cam.look_at_from_position(_vec(OS.get_environment("CAM"), Vector3(2.0, 1.8, 6.5)), _vec(OS.get_environment("LOOK"), Vector3(2.0, 0.6, -0.8)), Vector3.UP)
	cam.make_current()
	for i in 8:
		await process_frame
	var img := get_root().get_texture().get_image()
	var out := OS.get_environment("OUT")
	img.save_png(out if out != "" else "furniture_shot.png")
	quit()


func _place(stage: Node3D, mesh: Mesh, xf: Transform3D, custom: Color, color: Color = Color.WHITE) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = 1
	mm.set_instance_transform(0, xf)
	mm.set_instance_color(0, color)
	mm.set_instance_custom_data(0, custom)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	stage.add_child(mmi)


static func _vec(s: String, fallback: Vector3) -> Vector3:
	if s == "":
		return fallback
	var p := s.split(",")
	return Vector3(p[0].to_float(), p[1].to_float(), p[2].to_float())
