extends SceneTree
## The street lamp kit on its own (scripts/world/street_lamps.gd, tools/make_street_lamps.py):
## every type in a row along a kerb, arms over the road, lit with daylight or at night
## (lamp_factor 1, each lamp's pool and omni as the city places them). Seconds a frame.
##
##   OUT=l.png CAM=-14,2,-12 LOOK=0,4,0 xvfb-run -a -s "-screen 0 1280x720x24" godot \
##     --rendering-driver opengl3 --audio-driver Dummy --path . \
##     --script tools/glshot/lamp_shot.gd --resolution 1280x720
##
## Env: OUT, CAM, LOOK (x,y,z), FOV, NIGHT=1, LED=1 (every lamp LED), OLD=1 (the old Poly Haven
## post in every slot), ONLY=n (one type). Layout: the kerb runs along x at z 0, the road at z > 0;
## lamps every 7 m from x -14 at z -0.8, in StreetLamps.Type order. Prints each type's triangles.
func _initialize() -> void:
	var SL: GDScript = load("res://scripts/world/street_lamps.gd")
	var PF: GDScript = load("res://scripts/world/prop_factory.gd")
	var NC: GDScript = load("res://scripts/world/night_city.gd")
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
	e.ambient_light_energy = 0.45 if not night else 0.2
	e.tonemap_mode = Environment.TONE_MAPPER_AGX
	e.tonemap_exposure = 1.25 if not night else 1.5
	e.glow_enabled = night
	env.environment = e
	stage.add_child(env)
	RenderingServer.global_shader_parameter_set("lamp_factor", 1.0 if night else 0.0)
	RenderingServer.global_shader_parameter_set("night_factor", 1.0 if night else 0.0)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38.0, 150.0, 0.0)
	sun.light_energy = 1.3 if not night else 0.02
	sun.shadow_enabled = true
	stage.add_child(sun)
	for i in 2:
		var g := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(80.0, 0.1 if i == 0 else 0.15, 14.0)
		g.mesh = b
		g.position = Vector3(0.0, 0.05 if i == 0 else 0.075, 7.0 if i == 0 else -7.0)
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.1, 0.1, 0.105) if i == 0 else Color(0.36, 0.355, 0.34)
		m.roughness = 0.9
		g.material_override = m
		stage.add_child(g)
	var only := int(OS.get_environment("ONLY")) if OS.get_environment("ONLY") != "" else -1
	var led := OS.get_environment("LED") == "1"
	var old := OS.get_environment("OLD") == "1"
	for t in SL.TYPES.size():
		if only >= 0 and t != only:
			continue
		var at := Vector3(-14.0 + 7.0 * t, 0.15, -0.8)
		var spec: Dictionary = SL.TYPES[t]
		var b: Basis = SL.basis_for(Vector2(at.x, at.z), Vector2(0.0, 1.0))
		var mesh: Mesh = PF.model_lamp() if old else SL.mesh(t)
		var paint: Color = SL.TWIN_PAINTS[0] if t == 1 else (SL.LANTERN_PAINTS[1] if t == 2 else Color.WHITE)
		_place(stage, mesh, Transform3D(b, at), paint, Color(1.0 if led else 0.0, 0.4 + 0.1 * t, 0.0, 0.0))
		var arr := mesh.surface_get_arrays(0)
		print("type ", spec.node, ": ", (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3, " triangles")
		if night:
			var head := Vector3.ZERO
			var lights: Array = [Vector2(0.0, 3.5)] if old else spec.lights
			for l: Vector2 in lights:
				head += at + b * Vector3(l.x, l.y, 0.0)
			head /= float(lights.size())
			var size: float = 13.0 if old else float(spec.pool)
			var pool := Transform3D(Basis(Vector3.RIGHT, -PI * 0.5).scaled(Vector3(size, 1.0, size)), Vector3(head.x, at.y + 0.09, head.z))
			_place(stage, PF.light_pool(), pool, NC.pool_color(Vector2(2800, 100)) if led else Color.WHITE, Color.BLACK)
			var l := OmniLight3D.new()
			l.position = head - Vector3(0.0, 0.25, 0.0)
			l.omni_range = 13.0 if old else float(spec.range)
			l.omni_attenuation = 1.4 * log(3.5) / log(maxf(head.y - at.y - 0.25, 3.5))
			l.light_energy = 1.6
			l.light_color = NC.LED_LIGHT if led else NC.SODIUM_LIGHT
			stage.add_child(l)
	var cam := Camera3D.new()
	cam.fov = float(OS.get_environment("FOV")) if OS.get_environment("FOV") != "" else 50.0
	stage.add_child(cam)
	cam.look_at_from_position(_vec(OS.get_environment("CAM"), Vector3(-6.0, 1.7, -16.0)), _vec(OS.get_environment("LOOK"), Vector3(0.0, 4.0, 0.0)), Vector3.UP)
	cam.make_current()
	for i in 8:
		await process_frame
	var img := get_root().get_texture().get_image()
	var out := OS.get_environment("OUT")
	img.save_png(out if out != "" else "lamp_shot.png")
	quit()


func _place(stage: Node3D, mesh: Mesh, xf: Transform3D, color: Color, custom: Color) -> void:
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
