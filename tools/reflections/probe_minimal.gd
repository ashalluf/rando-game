extends SceneTree
## Minimal reflection probe sanity test: a chrome ball between a red and a green wall under a probe.
## OUT png; NOPROBE=1 without it.
func _initialize() -> void:
	var top := Node3D.new()
	root.add_child(top)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.3, 0.5, 0.9)
	if OS.get_environment("CITYENV") == "1":
		var st := (load("res://scenes/levels/city.tscn") as PackedScene).get_state()
		for i in st.get_node_count():
			if st.get_node_type(i) == "WorldEnvironment":
				for k in st.get_node_property_count(i):
					if st.get_node_property_name(i, k) == "environment":
						env = (st.get_node_property_value(i, k) as Environment).duplicate(true)
		env.sdfgi_enabled = false
		env.volumetric_fog_enabled = false
		if OS.get_environment("NOSSR") == "1":
			env.ssr_enabled = false
	var we := WorldEnvironment.new()
	we.environment = env
	top.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	top.add_child(sun)
	for side in [-1.0, 1.0]:
		var w := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(1, 8, 30)
		w.mesh = bm
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(1, 0.1, 0.1) if side < 0 else Color(0.1, 1, 0.1)
		w.material_override = m
		w.position = Vector3(side * 6.0, 4.0, 0.0)
		top.add_child(w)
	var ball := MeshInstance3D.new()
	ball.mesh = SphereMesh.new()
	var c := StandardMaterial3D.new()
	c.metallic = 1.0
	c.roughness = 0.02
	ball.material_override = c
	ball.position = Vector3(0, 1, 0)
	top.add_child(ball)
	if OS.get_environment("NOPROBE") != "1":
		var p := ReflectionProbe.new()
		p.size = Vector3(12, 10, 30)
		p.position = Vector3(0, 5, 0)
		p.box_projection = true
		p.update_mode = ReflectionProbe.UPDATE_ONCE if OS.get_environment("ONCE") == "1" else ReflectionProbe.UPDATE_ALWAYS
		var e := OS.get_environment("SET")
		if "amb" in e: p.ambient_mode = ReflectionProbe.AMBIENT_DISABLED
		if "org" in e: p.origin_offset = Vector3(0, -3.0, 0)
		if "maxd" in e: p.max_distance = 320.0
		if "lod" in e: p.mesh_lod_threshold = 6.0
		if "shadow" in e: p.enable_shadows = true
		if "blend" in e: p.blend_distance = 4.0
		if "node" in e:
			var n := Node.new()
			top.add_child(n)
			n.add_child(p)
		else:
			top.add_child(p)
	var cam := Camera3D.new()
	top.add_child(cam)
	cam.look_at_from_position(Vector3(0, 1.5, 5), Vector3(0, 1, 0))
	cam.current = true
	for i in 12:
		await process_frame
	root.get_texture().get_image().save_png(OS.get_environment("OUT"))
	print("MINI wrote")
	quit()
