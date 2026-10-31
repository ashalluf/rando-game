extends SceneTree
## Lines up the facade kit's pieces (tools/facade_kit.py) against a plain wall and saves a PNG, so
## each piece can be judged on its own - the way Building places them, through the kit shader:
##
##   OUT=kit.png LIBGL_ALWAYS_SOFTWARE=1 xvfb-run -a -s "-screen 0 1280x720x24" godot \
##     --rendering-driver opengl3 --display-driver x11 --audio-driver Dummy --path . \
##     --script tools/glshot/kit_shot.gd --resolution 960x540
##
## Env: OUT, SET (wall = the wall-mounted pieces, roof = the roof plant), CAM_DIST (metres).
## Compatibility renderer: flat light, judge shape and material.
func _initialize() -> void:
	var root3d := Node3D.new()
	get_root().add_child(root3d)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.55, 0.68, 0.85)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.58, 0.62)
	env.environment = e
	root3d.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, 35, 0)
	sun.shadow_enabled = true
	root3d.add_child(sun)
	var roof := OS.get_environment("SET") == "roof"
	var batch := MultiMeshBatch.new()
	var brick := Color(0.55, 0.30, 0.22)
	var stone := Color(0.80, 0.77, 0.70)
	var iron := Color(0.125, 0.0, 0.0, 0.0)
	var x := 0.0
	var wall := Basis()
	if roof:
		for p in ["water_tank", "hvac", "vent_mushroom", "vent_turbine"]:
			batch.add("kit_" + p, PropFactory.facade_kit(p), Transform3D(Basis(), Vector3(x, 0.0, 0.0)), Color(0.78, 0.77, 0.72), iron)
			x += 4.5 if p == "water_tank" else 3.0
	else:
		# Two cornice runs meeting at the square corner of a 2 x 2 m pier standing in front of the
		# wall, mitred the way _kit_runs does it (the +x end of the front run, the -x end of the
		# side run, each sliding by tan 45 = 1 per metre out).
		for c in [["cornice_classic", 4.0], ["cornice_bracket", 9.0]]:
			var mesh := PropFactory.facade_kit(c[0])
			var cx: float = c[1]
			batch.add("kit_" + c[0], mesh, Transform3D(wall, Vector3(cx - 1.0, 9.0, 3.0)), stone, Color(0.0, 1.0, 0.0, 0.0))
			batch.add("kit_" + c[0], mesh, Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(cx, 9.0, 2.0)), stone, Color(1.0, 0.0, 0.0, 0.0))
			var pier := MeshInstance3D.new()
			var pier_box := BoxMesh.new()
			pier_box.size = Vector3(2.0, 9.0, 2.0)
			pier.mesh = pier_box
			pier.material_override = PropFactory.material(brick.lightened(0.1), 0.9)
			pier.position = Vector3(cx - 1.0, 4.5, 2.0)
			root3d.add_child(pier)
		batch.add("kit_surround_brick_a", PropFactory.facade_kit("surround_brick_a"), Transform3D(wall, Vector3(-1.5, 5.0, 0.0)), stone, Color(0.0, 0.0, 0.2, 0.4))
		batch.add("kit_surround_stucco", PropFactory.facade_kit("surround_stucco"), Transform3D(wall, Vector3(0.6, 5.0, 0.0)), Color(0.9, 0.88, 0.82), Color(0.0, 0.0, 0.2, 0.4))
		batch.add("kit_ac_window", PropFactory.facade_kit("ac_window"), Transform3D(wall, Vector3(-1.5, 4.1, 0.0)), Color(0.86, 0.85, 0.8), iron)
		batch.add("kit_awning", PropFactory.facade_kit("awning"), Transform3D(wall, Vector3(-4.0, 3.3, 0.0)), Color(0.10, 0.36, 0.52), Color(0.125, 1.0, 1.0, 0.0))
		batch.add("kit_balcony", PropFactory.facade_kit("balcony"), Transform3D(wall, Vector3(12.0, 5.2, 0.0)), stone, iron)
		batch.add("kit_fe_stair_r", PropFactory.facade_kit("fe_stair_r"), Transform3D(wall, Vector3(-9.0, 7.0, 0.0)), Color.WHITE, iron)
		batch.add("kit_fe_bottom", PropFactory.facade_kit("fe_bottom"), Transform3D(wall, Vector3(-9.0, 3.5, 0.0)), Color.WHITE, iron)
	batch.build(root3d)
	# The wall (and, for the roof set, the deck) the pieces are fixed to.
	var plane := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(30.0, 0.2, 30.0) if roof else Vector3(30.0, 12.0, 0.4)
	plane.mesh = box
	plane.material_override = PropFactory.material(Color(0.62, 0.62, 0.60) if roof else brick, 0.9)
	plane.position = Vector3(3.0, -0.1, 0.0) if roof else Vector3(0.0, 4.0, -0.2)
	root3d.add_child(plane)
	var cam := Camera3D.new()
	root3d.add_child(cam)
	var dist := OS.get_environment("CAM_DIST").to_float()
	if roof:
		cam.look_at_from_position(Vector3(5.0, 7.0, 14.0 if dist <= 0.0 else dist), Vector3(5.0, 2.0, 0.0))
	else:
		cam.look_at_from_position(Vector3(4.0, 3.0, 14.0 if dist <= 0.0 else dist), Vector3(0.0, 5.5, 0.0))
	cam.fov = 60.0
	cam.current = true
	for i in 10:
		await process_frame
	var out := OS.get_environment("OUT")
	get_root().get_texture().get_image().save_png(out if out != "" else "kit_shot.png")
	print("saved ", out)
	quit()
