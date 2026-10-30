extends SceneTree
## The micromobility kit on its own (scripts/world/micro_mesh.gd, BikeRider): every vehicle in a
## row on a pavement, a BASIN BIKE station (kiosk and docks with bikes in them), a rack, a
## delineator, and with RIDERS=1 a rider on each kind posed mid-stroke. Seconds a frame.
##
##   OUT=m.png CAM=-3,1.6,-6 LOOK=0,0.8,0 xvfb-run -a -s "-screen 0 1280x720x24" godot \
##     --rendering-driver opengl3 --audio-driver Dummy --path . \
##     --script tools/glshot/micro_shot.gd --resolution 1280x720
##
## Env: OUT, CAM, LOOK (x,y,z), FOV, NIGHT=1, RIDERS=1 (riders in the row instead of the parked
## vehicles), CRANK=<radians> (the pedals' angle), RIG=<0..11> (one crowd rig for every rider),
## FALLEN=1 (the scooters lying over). Layout: the kerb along x at z 0, the road at z > 0, the
## vehicles at z -1.2 from x -6, 1.6 m apart (road, cruiser, cargo, share, scooter A, scooter B),
## the station from x 4. Prints each mesh's triangles.
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
	var mm: GDScript = load("res://scripts/world/micro_mesh.gd")
	var top := 0.25
	var riders := OS.get_environment("RIDERS") == "1"
	var fallen := OS.get_environment("FALLEN") == "1"
	var paints := [Color(0.7, 0.06, 0.05, 0.2), Color(0.55, 0.82, 0.8, 0.3), Color(0.2, 0.3, 0.22, 0.4), Color(0, 0, 0, 0.3), Color(0, 0, 0, 0.5), Color(0, 0, 0, 0.6)]
	for k in 6:
		var at := Vector3(-8.0 + k * 2.2, top, -1.2)
		if riders:
			var r: Node3D = load("res://scripts/npc/bike_rider.gd").new()
			var rig := int(OS.get_environment("RIG")) if OS.get_environment("RIG") != "" else -1
			r.call("setup_rider", k, 1000 + k * 17, Color(paints[k].r, paints[k].g, paints[k].b), rig)
			r.position = at
			r.rotation.y = PI * 0.5
			r.set("frozen", true)
			stage.add_child(r)
			if OS.get_environment("CRANK") != "":
				r.set("crank_angle", float(OS.get_environment("CRANK")))
			continue
		var m: Mesh = mm.call("whole", k)
		var xf := Transform3D(Basis(Vector3.UP, PI * 0.5), at)
		if fallen and k >= 4:
			xf = Transform3D(Basis(Vector3.UP, PI * 0.5) * Basis(Vector3.FORWARD, 1.32), at + Vector3(0.0, 0.12, 0.0))
		_place(stage, m, xf, paints[k])
		print("whole ", k, ": ", mm.call("triangles", m), " triangles")
	# The station: kiosk and six docks, bikes in four of them, then a rack and a delineator.
	_place(stage, mm.call("kiosk"), Transform3D(Basis(), Vector3(4.0, top, -1.6)), Color(0, 0, 0, 0.2))
	print("kiosk: ", mm.call("triangles", mm.call("kiosk")), " dock: ", mm.call("triangles", mm.call("dock")))
	for d in 6:
		var dx := 5.0 + d * 0.85
		_place(stage, mm.call("dock"), Transform3D(Basis(), Vector3(dx, top, -2.2)), Color(0, 0, 0, 0.2))
		if d % 3 != 2:
			_place(stage, mm.call("whole", 3), Transform3D(Basis(Vector3.UP, PI), Vector3(dx, top, -1.15)), Color(0, 0, 0, 0.3 + 0.1 * d))
	_place(stage, mm.call("rack"), Transform3D(Basis(), Vector3(-9.0, top, -1.2)), Color(0, 0, 0, 0.2))
	_place(stage, mm.call("delineator"), Transform3D(Basis(), Vector3(-9.0, 0.1, 1.0)), Color(0, 0, 0, 0.2))
	print("rack: ", mm.call("triangles", mm.call("rack")), " delineator: ", mm.call("triangles", mm.call("delineator")))
	if night:
		for p: Vector3 in [Vector3(0.0, 4.5, -2.0), Vector3(6.0, 4.5, -2.0)]:
			var l := OmniLight3D.new()
			l.position = p
			l.omni_range = 9.0
			l.light_energy = 1.6
			l.light_color = Color(1.0, 0.85, 0.65)
			stage.add_child(l)
	var cam := Camera3D.new()
	cam.fov = float(OS.get_environment("FOV")) if OS.get_environment("FOV") != "" else 50.0
	stage.add_child(cam)
	cam.look_at_from_position(_vec(OS.get_environment("CAM"), Vector3(-2.0, 1.6, -7.5)), _vec(OS.get_environment("LOOK"), Vector3(-2.0, 0.7, -1.2)), Vector3.UP)
	cam.make_current()
	for i in 10:
		await process_frame
	var img := get_root().get_texture().get_image()
	var out := OS.get_environment("OUT")
	img.save_png(out if out != "" else "micro_shot.png")
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
