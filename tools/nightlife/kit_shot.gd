extends SceneTree
## The night-life kit alone (seconds, opengl3 + Xvfb): a club entrance, a bar's front, a rope line,
## the premiere carpet and a searchlight cart in a row on a grey floor, lit as at night.
##   OUT=kit.png xvfb-run -a godot --rendering-driver opengl3 --path . --script tools/nightlife/kit_shot.gd
## NIGHT=0 by day.

func _initialize() -> void:
	await process_frame
	var kit: GDScript = load("res://scripts/world/nightlife_kit.gd")
	var root3 := Node3D.new()
	get_root().add_child(root3)
	var night := OS.get_environment("NIGHT") != "0"
	RenderingServer.global_shader_parameter_set("lamp_factor", 1.0 if night else 0.0)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.03, 0.06) if night else Color(0.5, 0.6, 0.75)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.25, 0.27, 0.35) if night else Color(0.6, 0.6, 0.6)
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.glow_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	root3.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 30, 0)
	sun.light_energy = 0.15 if night else 1.2
	root3.add_child(sun)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 30)
	floor_mi.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.35, 0.35, 0.36)
	floor_mi.material_override = fm
	root3.add_child(floor_mi)
	var wall := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(60, 8, 0.4)
	wall.mesh = bm
	wall.position = Vector3(0, 4, -0.2)
	wall.material_override = fm
	root3.add_child(wall)
	var custom := Color(0.42, 0.04, 0.06, 0.6)
	var items := [[kit.call("club_entrance", 1), Vector3(-12, 0, 0)], [kit.call("bar_entrance"), Vector3(-4, 0, 0)],
		[kit.call("rope_line", 5, 1, 0), Vector3(-1, 0, 0)], [kit.call("premiere", 4.0, 2.6), Vector3(10, 0, 0)],
		[kit.call("searchlight_cart"), Vector3(18, 0, 4)]]
	for it: Array in items:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true
		mm.mesh = it[0]
		mm.instance_count = 1
		mm.set_instance_transform(0, Transform3D(Basis(), it[1]))
		mm.set_instance_color(0, Color.WHITE)
		mm.set_instance_custom_data(0, custom)
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		root3.add_child(mmi)
	var cam := Camera3D.new()
	cam.position = Vector3(2, 4.5, 16)
	cam.fov = 70
	root3.add_child(cam)
	cam.look_at(Vector3(2, 2, 0))
	for i in 8:
		await process_frame
	var img := get_root().get_texture().get_image()
	img.save_png(OS.get_environment("OUT") if OS.get_environment("OUT") != "" else "kit.png")
	quit()
