extends SceneTree
## The street vendors' stands on their own (scripts/world/street_vendors.gd): a taco truck at a
## kerb and every cart in a row on a pavement, lit with daylight or at night (lamp_factor 1, the
## stands' own lights). Seconds a frame instead of minutes for a city still.
##
##   OUT=v.png CAM=-6,1.7,9 LOOK=0,1.2,0 xvfb-run -a -s "-screen 0 1280x720x24" godot \
##     --rendering-driver opengl3 --audio-driver Dummy --path . \
##     --script tools/glshot/vendor_shot.gd --resolution 1280x720
##
## Env: OUT, CAM, LOOK (x,y,z), FOV, NIGHT=1, TRUCK=n (variant). Layout: the kerb runs along x
## at z 0, the road at z > 0 with the truck in it (window toward -z), the carts at z -1.6 from
## x -8 (fruit, elote, hot dog, paleta, flowers, 3.5 m apart). Prints each mesh's triangles.
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
		b.size = Vector3(60.0, 0.1 if i == 0 else 0.25, 12.0)
		g.mesh = b
		g.position = Vector3(0.0, 0.05 if i == 0 else 0.125, 6.0 if i == 0 else -6.0)
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.12, 0.12, 0.125) if i == 0 else Color(0.55, 0.54, 0.52)
		m.roughness = 0.9
		g.material_override = m
		stage.add_child(g)
	var sv: GDScript = load("res://scripts/world/street_vendors.gd")
	var variant := int(OS.get_environment("TRUCK")) if OS.get_environment("TRUCK") != "" else 0
	var truck: Mesh = sv.call("truck", variant)
	_place(stage, truck, Transform3D(Basis(Vector3(0, 0, -1), Vector3.UP, Vector3(0, 0, -1).cross(Vector3.UP)), Vector3(2.0, 0.1, 1.3)), Color(0.93, 0.93, 0.9, 0.3))
	var kinds := [1, 2, 3, 4, 5]
	for i in kinds.size():
		var m: Mesh = sv.call("cart", kinds[i])
		var at := Vector3(-8.0 + i * 3.5, 0.25, -1.6)
		var xf := Transform3D(Basis(Vector3.UP, PI), at)
		_place(stage, m, xf, Color(0.1, 0.32, 0.65, 0.4))
		if kinds[i] <= 2 or kinds[i] == 4:
			var sock: Vector3 = (sv.get("UMBRELLA_SOCKET") as Dictionary).get(kinds[i], Vector3.ZERO)
			var s := 0.75 if kinds[i] == 4 else 1.0
			_place(stage, sv.call("umbrella_mesh"), Transform3D(Basis(Vector3.UP, PI).scaled(Vector3.ONE * s), xf * sock), Color(0.85, 0.12, 0.1, float(i % 6) / 8.0))
		print("mesh ", kinds[i], ": ", (m.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3, " triangles")
	print("truck: ", (truck.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3, " triangles")
	if night:
		for p: Vector3 in [Vector3(2.0, 2.5, -1.0), Vector3(-1.0, 2.0, -1.6)]:
			var l := OmniLight3D.new()
			l.position = p
			l.omni_range = 7.0
			l.light_energy = 2.6
			l.light_color = Color(1.0, 0.9, 0.75)
			stage.add_child(l)
	var cam := Camera3D.new()
	cam.fov = float(OS.get_environment("FOV")) if OS.get_environment("FOV") != "" else 50.0
	stage.add_child(cam)
	cam.look_at_from_position(_vec(OS.get_environment("CAM"), Vector3(-4.0, 1.7, -9.0)), _vec(OS.get_environment("LOOK"), Vector3(0.0, 1.2, 0.0)), Vector3.UP)
	cam.make_current()
	for i in 8:
		await process_frame
	var img := get_root().get_texture().get_image()
	var out := OS.get_environment("OUT")
	img.save_png(out if out != "" else "vendor_shot.png")
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
