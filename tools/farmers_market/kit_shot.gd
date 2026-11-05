extends SceneTree
## The farmers' market kit on its own (scripts/world/farmers_market_kit.gd): two rows of stalls
## facing an aisle along x, every goods kind and variant, canopies over them, lit by a sun and a
## sky. Seconds a frame instead of a city load (~15 min) for the market's refcam.
##
##   OUT=k.png CAM=-5,1.65,0 LOOK=6,1.0,0 xvfb-run -a -s "-screen 0 1280x720x24" godot \
##     --rendering-driver opengl3 --audio-driver Dummy --path . \
##     --script tools/farmers_market/kit_shot.gd --resolution 1280x720
##
## Env: OUT, CAM, LOOK (x,y,z), FOV. The aisle runs along +x at z 0; the -z row faces +z, the +z
## row faces -z; stall i stands at x = i * 3.2. Prints each goods mesh's triangles.
func _initialize() -> void:
	# The kit names classes that use autoloads: load it by path once they exist.
	await process_frame
	var kit: GDScript = load("res://scripts/world/farmers_market_kit.gd")
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
	RenderingServer.global_shader_parameter_set("lamp_factor", 0.0)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45.0, 150.0, 0.0)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	stage.add_child(sun)
	var g := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = Vector3(60.0, 0.1, 30.0)
	g.mesh = b
	g.position = Vector3(10.0, -0.05, 0.0)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.13, 0.13, 0.135)
	m.roughness = 0.9
	g.material_override = m
	stage.add_child(g)
	var goods: Array = []
	for k in 4:
		for v in int(kit.get("VARIANTS")[k]):
			goods.append([k, v])
	for i in goods.size():
		var side := -1.0 if i % 2 == 0 else 1.0
		var x := float(i / 2) * 3.2
		var front := Vector3(0, 0, -side)
		var basis := Basis(Vector3.UP.cross(front), Vector3.UP, front)
		var xf := Transform3D(basis, Vector3(x, 0.0, side * 3.2))
		var gm: Mesh = kit.call("goods", int(goods[i][0]), int(goods[i][1]))
		_place(stage, gm, xf, Color(0, 0, 0, 0))
		_place(stage, kit.call("canopy"), xf, kit.get("CANVAS")[i % 3])
		print("goods ", goods[i], ": ", (gm.surface_get_arrays(0)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3, " triangles")
	var cam := Camera3D.new()
	cam.fov = float(OS.get_environment("FOV")) if OS.get_environment("FOV") != "" else 55.0
	stage.add_child(cam)
	cam.look_at_from_position(_vec(OS.get_environment("CAM"), Vector3(-5.0, 1.65, 0.0)), _vec(OS.get_environment("LOOK"), Vector3(6.0, 1.0, -1.0)), Vector3.UP)
	cam.make_current()
	for i in 8:
		await process_frame
	var img := get_root().get_texture().get_image()
	var out := OS.get_environment("OUT")
	img.save_png(out if out != "" else "kit_shot.png")
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
