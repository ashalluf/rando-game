extends Node3D
## One Arts District brick wall alone, for the arts_district refcam's shader work on either
## renderer (seconds on opengl3, a few minutes on lavapipe Forward+; the city does not fit there):
## a brick front with its steel sash, a mural over brick, a grade door in its steel frame and a
## dark downspout, written by IndustrialKit's own box writer on the walls material, lit by the city
## scene's Environment and a 10:00 sun.
##   OUT=/tmp/w.png RC5_ARTS=0|1 xvfb-run -a -s "-screen 0 1280x720x24" godot --rendering-driver
##     opengl3|vulkan --display-driver x11 --audio-driver Dummy --path .
##     res://tools/rc5_arts_district/wall_shot.tscn --resolution 1280x720
## CAM=x,y,z LOOK=x,y,z move the camera (the wall's face is z 0, facing +z, 30 m long, 12 m high).
func _ready() -> void:
	var root := self
	var env := WorldEnvironment.new()
	var state := (load("res://scenes/levels/city.tscn") as PackedScene).get_state()
	for i in state.get_node_count():
		if state.get_node_name(i) == "WorldEnvironment":
			for p in state.get_node_property_count(i):
				if state.get_node_property_name(i, p) == "environment":
					env.environment = (state.get_node_property_value(i, p) as Environment).duplicate()
	if env.environment == null:
		env.environment = Environment.new()
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42.0, 150.0, 0.0)
	sun.light_energy = 1.6
	sun.shadow_enabled = true
	root.add_child(sun)
	RenderingServer.global_shader_parameter_set("sky_tint", Color(0.62, 0.75, 0.92))
	RenderingServer.global_shader_parameter_set("lamp_factor", 0.0)
	RenderingServer.global_shader_parameter_set("night_factor", 0.0)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	var brick := Color(0.92, 0.84, 0.78)
	IndustrialKit.box(st, Transform3D(Basis(), Vector3(0, 6.0, -0.2)), Vector3(30.0, 12.0, 0.4), IndustrialKit.K_BRICK, brick, 5.2)
	# A mural over the right half's upper storey, flagged as on brick.
	IndustrialKit.box(st, Transform3D(Basis(), Vector3(8.0, 8.6, 0.03)), Vector3(12.0, 6.0, 0.02), IndustrialKit.K_MURAL, Color(0.31, 0.62, RcArtsDistrict.mural_flag(true)), 12.0)
	# A grade door with its frame, a downspout.
	IndustrialKit.box(st, Transform3D(Basis(), Vector3(-9.0, 2.15, 0.03)), Vector3(3.7, 4.3, 0.05), IndustrialKit.K_ROLLUP, Color(0.55, 0.57, 0.6), 0.075)
	var ch := CityChunk.new()
	Industrial._state(ch)
	var f := Industrial.frame(Rect2(-15.0, -10.0, 30.0, 10.0), 1)
	var cx := {"ch": ch, "basis": Basis(Vector3(-1, 0, 0), Vector3.UP, Vector3(0, 0, -1)), "f": f, "floor": 0.0}
	RcArtsDistrict.door_frame(cx, 24.0, 10.0, Industrial.GRADE_DOOR)
	if ch._ind.walls != null:
		st.append_from((ch._ind.walls as SurfaceTool).commit(), 0, Transform3D())
	ch.free()
	IndustrialKit.box(st, Transform3D(Basis(), Vector3(-2.6, 6.0, 0.08)), Vector3(0.14, 12.0, 0.12), RcArtsDistrict.spout_kind(true), RcArtsDistrict.spout_paint(true))
	IndustrialKit.box(st, Transform3D(Basis(), Vector3(0, -0.05, 6.0)), Vector3(40.0, 0.1, 14.0), IndustrialKit.K_CONCRETE, Color(0.6, 0.59, 0.56))
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = IndustrialKit.walls_material()
	root.add_child(mi)
	var cam := Camera3D.new()
	cam.fov = 55.0
	root.add_child(cam)
	var c := OS.get_environment("CAM").split(",") if OS.get_environment("CAM") != "" else PackedStringArray(["-6", "1.7", "14"])
	var l := OS.get_environment("LOOK").split(",") if OS.get_environment("LOOK") != "" else PackedStringArray(["2", "5", "0"])
	cam.look_at_from_position(Vector3(c[0].to_float(), c[1].to_float(), c[2].to_float()), Vector3(l[0].to_float(), l[1].to_float(), l[2].to_float()))
	cam.make_current()
	for i in int(OS.get_environment("FRAMES")) if OS.get_environment("FRAMES") != "" else 40:
		await get_tree().process_frame
	var out := OS.get_environment("OUT") if OS.get_environment("OUT") != "" else "/tmp/wall.png"
	get_viewport().get_texture().get_image().save_png(out)
	print("WALL saved ", out)
	get_tree().quit()
