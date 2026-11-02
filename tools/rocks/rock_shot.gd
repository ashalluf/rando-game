extends SceneTree
## The rock kit (scripts/world/rock_kit.gd) in a row on a dry-grass ground: seconds a frame.
##
##   OUT=r.png xvfb-run -a -s "-screen 0 1600x800x24" godot --rendering-driver opengl3 \
##     --audio-driver Dummy --path . --script tools/rocks/rock_shot.gd --resolution 1600x800
##
## Env: OUT, CAM / LOOK (x,y,z), FOV, YAW (degrees, turns every rock), PLAIN=1 the glTF's own
## materials, SCALE (every rock), TONE (0 sandstone .. 1 granite; default by kind), SUN=pitch,yaw, LOD=n (draw that LOD as the mesh), FAR=1 the tors' welded meshes
## (custom r 1: the seat stays off).
var TONE := -1.0


func _initialize() -> void:
	var stage := Node3D.new()
	get_root().add_child(stage)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.28, 0.45, 0.7)
	sky_mat.sky_horizon_color = Color(0.72, 0.76, 0.8)
	sky_mat.ground_horizon_color = Color(0.5, 0.48, 0.45)
	sky_mat.ground_bottom_color = Color(0.2, 0.19, 0.18)
	sky.sky_material = sky_mat
	e.sky = sky
	e.background_mode = Environment.BG_SKY
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.5
	e.tonemap_mode = Environment.TONE_MAPPER_AGX
	e.tonemap_exposure = 1.25
	env.environment = e
	stage.add_child(env)
	var sun := DirectionalLight3D.new()
	var sun_rot := Vector2(-40.0, 35.0)
	var sp_env := OS.get_environment("SUN")
	if sp_env != "":
		var q := sp_env.split(",")
		sun_rot = Vector2(q[0].to_float(), q[1].to_float())
	sun.rotation_degrees = Vector3(sun_rot.x, sun_rot.y, 0.0)
	sun.light_energy = 1.4
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 250.0
	stage.add_child(sun)
	RenderingServer.global_shader_parameter_set("sun_direction", sun.transform.basis.z)
	var ground := MeshInstance3D.new()
	var gb := BoxMesh.new()
	gb.size = Vector3(600.0, 0.1, 400.0)
	ground.mesh = gb
	ground.position = Vector3(0.0, -0.05, 0.0)
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.42, 0.36, 0.22)
	gm.roughness = 0.95
	ground.material_override = gm
	stage.add_child(ground)
	var kit: GDScript = load("res://scripts/world/rock_kit.gd")
	var plain := OS.get_environment("PLAIN") == "1"
	var yaw := deg_to_rad(OS.get_environment("YAW").to_float())
	var scale := OS.get_environment("SCALE").to_float()
	if scale <= 0.0:
		scale = 1.0
	var lod := int(OS.get_environment("LOD")) if OS.get_environment("LOD") != "" else -1
	var x := -30.0
	TONE = OS.get_environment("TONE").to_float() if OS.get_environment("TONE") != "" else -1.0
	for kind in kit.KINDS.size():
		var mesh: Mesh = kit.plain_mesh(kind) if plain else kit.mesh(kind)
		if OS.get_environment("FAR") == "1":
			if not kit.TOR_KINDS.has(kind):
				continue
			mesh = kit.mid_mesh(kind)
		if lod >= 0:
			mesh = kit.lod_of(mesh, lod)
		var aabb := mesh.get_aabb()
		# A MultiMesh of one, as the game draws them: INSTANCE_CUSTOM r 1 (the real ground), the tone.
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = mesh
		mm.instance_count = 1
		var w := maxf(aabb.size.x, aabb.size.z) * scale
		x += w * 0.5 + 2.0
		mm.set_instance_transform(0, Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scale), Vector3(x, 0.0, 0.0)))
		mm.set_instance_custom_data(0, Color(1.0, TONE if TONE >= 0.0 else float(kind % 3) * 0.5, 0.0, 1.0))
		x += w * 0.5
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		stage.add_child(mi)
		var tris := 0
		for s in mesh.get_surface_count():
			tris += (mesh.surface_get_arrays(s)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
		print("ROCK %s tris %d aabb %s" % [kit.KINDS[kind], tris, aabb])
	var cam := Camera3D.new()
	cam.fov = OS.get_environment("FOV").to_float() if OS.get_environment("FOV") != "" else 50.0
	cam.far = 4000.0
	var cpos := Vector3(0.0, 12.0, 45.0)
	var look := Vector3(0.0, 3.0, 0.0)
	if OS.get_environment("CAM") != "":
		var c := OS.get_environment("CAM").split(",")
		cpos = Vector3(c[0].to_float(), c[1].to_float(), c[2].to_float())
	if OS.get_environment("LOOK") != "":
		var l := OS.get_environment("LOOK").split(",")
		look = Vector3(l[0].to_float(), l[1].to_float(), l[2].to_float())
	stage.add_child(cam)
	cam.look_at_from_position(cpos, look)
	for i in 8:
		await process_frame
	var img := get_root().get_texture().get_image()
	var out := OS.get_environment("OUT")
	img.save_png(out if out != "" else "rock_shot.png")
	quit()
