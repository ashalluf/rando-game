extends SceneTree
## The building sites' kit on its own (ConstructionKit): a tower crane, a road-works closure (cones,
## drums, the arrow board, trench plates, the excavator, a barricade, the sign), a skip, toilets,
## cabins, stacks and a hoarding panel, lit by day or at night. Seconds a frame.
##
##   OUT=k.png CAM=-14,4,22 LOOK=0,2,0 xvfb-run -a -s "-screen 0 1280x720x24" godot \
##     --rendering-driver opengl3 --audio-driver Dummy --path . \
##     --script tools/construction/kit_shot.gd --resolution 1280x720
##
## Env: OUT, CAM, LOOK, FOV, NIGHT=1, TIME (shader seconds for the crane's swing), CRANE=0 hides
## the crane. The crane stands at (-30, 0, -30) with a 40 m mast and a 44 m jib.
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
	RenderingServer.global_shader_parameter_set("sky_tint", Color(0.55, 0.65, 0.8) if not night else Color(0.04, 0.04, 0.06))
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, 35.0, 0.0)
	sun.light_energy = 1.3 if not night else 0.03
	sun.shadow_enabled = true
	stage.add_child(sun)
	var g := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(160.0, 0.1, 160.0)
	g.mesh = bm
	g.position = Vector3(0.0, 0.05, 0.0)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.13, 0.13, 0.135)
	m.roughness = 0.9
	g.material_override = m
	stage.add_child(g)
	var K: GDScript = load("res://scripts/world/construction_kit.gd")
	var st: SurfaceTool = K.call("new_st")
	# A closure along z at x = 0, the traffic running -z (upstream at +z).
	var face := Basis()
	for i in 7:
		K.call("cone", st, Transform3D(face, Vector3(lerpf(1.3, -1.45, float(i) / 6.0), 0.1, 14.0 - float(i) * 2.0)))
	for z in [-2.0, -6.5, -11.0]:
		K.call("cone", st, Transform3D(face, Vector3(-1.45, 0.1, z)))
	K.call("drum", st, Transform3D(face, Vector3(-1.2, 0.1, 1.2)))
	K.call("arrow_board", st, Transform3D(face, Vector3(0.0, 0.1, -1.0)))
	for i in 2:
		K.call("trench_plate", st, Transform3D(face, Vector3(0.0, 0.1, -7.0 - float(i) * 3.2)), Vector2(2.4, 3.05))
	K.call("excavator", st, Transform3D(face, Vector3(0.2, 0.1, -16.0)), PI + 0.4, 0.7)
	K.call("barricade", st, Transform3D(face, Vector3(0.0, 0.1, -20.5)), 2.0)
	K.call("skip", st, Transform3D(Basis(), Vector3(8.0, 0.1, -4.0)), Color(0.18, 0.32, 0.55), 0.6)
	K.call("toilet", st, Transform3D(Basis(Vector3.UP, PI), Vector3(5.0, 0.1, 4.0)), Color(0.16, 0.36, 0.62))
	K.call("cabin", st, Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(12.0, 0.1, 6.0)))
	K.call("lumber_stack", st, Transform3D(Basis(), Vector3(5.0, 0.1, -12.0)))
	K.call("rebar_bundle", st, Transform3D(Basis(), Vector3(8.0, 0.1, -18.0)))
	K.call("form_stack", st, Transform3D(Basis(), Vector3(3.5, 0.1, 9.0)), Color(0.82, 0.62, 0.2))
	K.call("box", st, Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(-6.0, 1.32, 0.0)), Vector3(30.0, 2.44, 0.04), 7, Color.WHITE, 1.01, 0, 32)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = K.call("material")
	stage.add_child(mi)
	if OS.get_environment("CRANE") != "0":
		var cr := MeshInstance3D.new()
		cr.mesh = K.call("crane_mesh", 40.0, 44.0, 14.0, 30.0)
		cr.material_override = K.call("crane_material")
		cr.position = Vector3(-30.0, 40.1, -30.0)
		cr.custom_aabb = AABB(Vector3(-50, -42, -50), Vector3(100, 60, 100))
		stage.add_child(cr)
		print("crane tris ", (cr.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3)
	print("kit tris ", (mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3)
	var cam := Camera3D.new()
	cam.fov = float(OS.get_environment("FOV")) if OS.get_environment("FOV") != "" else 50.0
	cam.far = 2000.0
	stage.add_child(cam)
	cam.look_at_from_position(_vec(OS.get_environment("CAM"), Vector3(-14.0, 4.0, 22.0)), _vec(OS.get_environment("LOOK"), Vector3(0.0, 2.0, 0.0)), Vector3.UP)
	cam.make_current()
	for i in 8:
		await process_frame
	var img := get_root().get_texture().get_image()
	var out := OS.get_environment("OUT")
	img.save_png(out if out != "" else "kit_shot.png")
	quit()


static func _vec(s: String, fallback: Vector3) -> Vector3:
	if s == "":
		return fallback
	var p := s.split(",")
	return Vector3(p[0].to_float(), p[1].to_float(), p[2].to_float())
