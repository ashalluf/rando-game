extends Node3D
## Sunbathers on Backyards' chaise loungers, alone (no city), to fit the "lounge" pose
## (BeachGoer.BEACH_POSES) to the lounger mesh: a row of lounger pairs, a baked YardFigure on each
## seat (every beach rig), lit like the street. Seconds; opengl3 under Xvfb (the bake needs mesh
## data, which --headless does not keep).
##
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --rendering-driver opengl3 --path . \
##     res://tools/backyards/lounger_shot.tscn -- OUT=/tmp/lounge [VIEW=side|three|top] [KEY=lounge]

func _ready() -> void:
	var out := "/tmp/lounge"
	var view := "three"
	var key := "lounge"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("OUT="):
			out = a.trim_prefix("OUT=")
		elif a.begins_with("VIEW="):
			view = a.trim_prefix("VIEW=")
		elif a.begins_with("KEY="):
			key = a.trim_prefix("KEY=")
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.62, 0.7, 0.8)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.62, 0.7, 0.82)
	e.ambient_light_energy = 0.55
	e.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	sun.light_energy = 1.6
	sun.shadow_enabled = true
	add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 40)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.5, 0.48, 0.44)
	ground.material_override = gm
	add_child(ground)
	var models: Array = BeachGoer.BEACH_MODELS
	var lounger := BackyardKit.get_mesh("loungers")
	for i in ceili(models.size() / 2.0):
		var xf := Transform3D(Basis(), Vector3(float(i) * 2.6 - 4.0, 0.0, 0.0))
		var mm := MultiMeshInstance3D.new()
		var m := MultiMesh.new()
		m.transform_format = MultiMesh.TRANSFORM_3D
		m.use_custom_data = true
		m.use_colors = true
		m.mesh = lounger
		m.instance_count = 1
		m.set_instance_transform(0, xf)
		m.set_instance_color(0, Color.WHITE)
		m.set_instance_custom_data(0, Color(0.9, 0.89, 0.86, 2.0 / 8.0 + 0.01))
		mm.multimesh = m
		add_child(mm)
		for s: int in [-1, 1]:
			var k := i * 2 + (0 if s < 0 else 1)
			if k >= models.size():
				continue
			var model: int = models[k]
			var seed_value := BeachGoer.seed_for(model, 0)
			var mesh := BeachFigure.beach_mesh(seed_value, RoughSleeper.Pose.CHAIR, key, k % BeachGoer.SUITS.size(), model)
			if mesh == null:
				print("NO MESH ", model)
				continue
			var fx := xf * Backyards.seat_xform(s)
			var f := MeshInstance3D.new()
			f.mesh = mesh
			f.transform = fx
			add_child(f)
			print("FIG ", model, " aabb ", mesh.get_aabb())
	var cam := Camera3D.new()
	cam.fov = 40.0
	add_child(cam)
	match view:
		"side":
			cam.position = Vector3(0.5, 0.9, -1.0)
			cam.look_at_from_position(Vector3(-0.5, 1.0, 0.25) + Vector3(-12.0, 0.4, 0.0), Vector3(0.0, 0.5, 0.25))
		"top":
			cam.look_at_from_position(Vector3(0.0, 14.0, -6.0), Vector3(0.0, 0.0, 0.0))
		_:
			cam.look_at_from_position(Vector3(4.0, 3.2, -6.5), Vector3(0.0, 0.5, 0.2))
	cam.current = true
	for i in 6:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out + "_" + view + ".png")
	print("SAVED ", out + "_" + view + ".png")
	get_tree().quit()
