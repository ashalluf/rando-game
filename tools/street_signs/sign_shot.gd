extends SceneTree
## The street's signs on their own (SignKit): every assembly in a row on a pavement, lit by day
## or at night (lamp_factor 1; the camera's "headlights" light the retroreflective sheeting).
## Seconds a frame instead of minutes for a city still.
##
##   OUT=s.png xvfb-run -a -s "-screen 0 1280x720x24" godot --rendering-driver opengl3 \
##     --audio-driver Dummy --path . --script tools/street_signs/sign_shot.gd --resolution 1280x720
##
## Env: OUT, CAM, LOOK (x,y,z), FOV, NIGHT=1, BACK=1 (turn every sign round: the backs).
## Layout along x from -9, 2.2 m apart: name post, stop with blades, yield, speed 35, no parking,
## parking (cleaning + 2 hour), school; a mast arm at y 6.55 above with its name sign, lane-use
## sign and NO TURN ON RED. Prints each mesh's triangles.
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
	env.environment = e
	stage.add_child(env)
	RenderingServer.global_shader_parameter_set("lamp_factor", 1.0 if night else 0.0)
	RenderingServer.global_shader_parameter_set("night_factor", 1.0 if night else 0.0)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, 35.0, 0.0)
	sun.light_energy = 1.3 if not night else 0.03
	sun.shadow_enabled = true
	stage.add_child(sun)
	for i in 2:
		var g := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(60.0, 0.1 if i == 0 else 0.15, 12.0)
		g.mesh = b
		g.position = Vector3(0.0, 0.05 if i == 0 else 0.075, 6.0 if i == 0 else -6.0)
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.12, 0.12, 0.125) if i == 0 else Color(0.55, 0.54, 0.52)
		m.roughness = 0.9
		g.material_override = m
		stage.add_child(g)
	var kit: GDScript = load("res://scripts/world/sign_kit.gd")
	var back := PI if OS.get_environment("BACK") == "1" else 0.0
	var meshes: Array = [
		kit.call("name_post", "VISTA BLVD", "600", "5TH ST", "1100"),
		kit.call("stop_post", ["HILL AVE", "600", "WILSHIRE BLVD", "500"]),
		kit.call("yield_post"),
		kit.call("speed_post", 35),
		kit.call("no_parking_post"),
		kit.call("parking_post", 1, 0, true),
		kit.call("school_post"),
	]
	for i in meshes.size():
		_place(stage, meshes[i], Transform3D(Basis(Vector3.UP, back), Vector3(-9.0 + i * 2.6, 0.15, -0.6)), Color(float(i) / 7.0, 0, 0, 0))
		print("mesh %d: %d triangles" % [i, kit.call("triangles", meshes[i])])
	# A mast arm (a plain tube) with its signs, over the road.
	var arm := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.09
	cyl.bottom_radius = 0.12
	cyl.height = 9.0
	arm.mesh = cyl
	arm.rotation_degrees = Vector3(0, 0, 90)
	arm.position = Vector3(0.0, 6.55, 3.0)
	stage.add_child(arm)
	var arm_meshes: Array = [kit.call("arm_name", "WILSHIRE BLVD", "300"), kit.call("arm_lanes"), kit.call("arm_no_turn_red")]
	var xs := [-2.4, 0.4, 2.4]
	for i in arm_meshes.size():
		_place(stage, arm_meshes[i], Transform3D(Basis(Vector3.UP, back), Vector3(xs[i], 6.55, 3.0)), Color(0.3, 0, 0, 0))
		print("arm mesh %d: %d triangles" % [i, kit.call("triangles", arm_meshes[i])])
	var cam := Camera3D.new()
	cam.fov = float(OS.get_environment("FOV")) if OS.get_environment("FOV") != "" else 50.0
	stage.add_child(cam)
	var cdef := Vector3(-1.0, 2.6, 9.0) if back == 0.0 else Vector3(-1.0, 2.6, -9.0)
	cam.look_at_from_position(_vec(OS.get_environment("CAM"), cdef), _vec(OS.get_environment("LOOK"), Vector3(-1.0, 3.0, 0.0)), Vector3.UP)
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
