extends Node3D
## The marine layer's top alone in seconds (no city): MarineLayer driven as Weather drives it at
## 08:30, a camera on a hill 470 m up, a few tower boxes and a slope standing out of the deck.
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --rendering-driver opengl3 --path . \
##     res://tools/rc5_sea_of_clouds/deck_shot.tscn -- --out=/tmp/deck.png
## SEA_OF_CLOUDS=0 the old top. YAW / PITCH / Y place the camera (true world, x 6234 z 1757).

func _ready() -> void:
	var out := "/tmp/deck.png"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	e.sky = Sky.new()
	e.sky.sky_material = ProceduralSkyMaterial.new()
	e.tonemap_mode = Environment.TONE_MAPPER_AGX
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.environment = e
	add_child(env)
	var hour := 8.5
	var el := sin((hour - 6.0) / 12.0 * PI)
	var sun := DirectionalLight3D.new()
	var sun_dir := Vector3(0.75, el, 0.35).normalized()
	add_child(sun)
	sun.look_at_from_position(Vector3.ZERO, -sun_dir, Vector3.UP)
	RenderingServer.global_shader_parameter_set("sky_tint", Color(0.55, 0.68, 0.85))
	var eye := Vector3(6234.0, float(OS.get_environment("Y")) if OS.get_environment("Y") != "" else 468.0, 1757.0)
	WorldState.world_offset = Vector3(eye.x, 0.0, eye.z)
	var cam := Camera3D.new()
	cam.far = 12000.0
	cam.fov = 55.0
	add_child(cam)
	cam.position = Vector3(0.0, eye.y, 0.0)
	var yaw := float(OS.get_environment("YAW")) if OS.get_environment("YAW") != "" else 68.0
	var pitch := float(OS.get_environment("PITCH")) if OS.get_environment("PITCH") != "" else -7.0
	cam.rotation_degrees = Vector3(pitch, yaw, 0.0)
	cam.make_current()
	# Ground far under the deck, towers poking through, a hillside rising out of it.
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.5, 0.42, 0.3)
	_box(Vector3(2800.0, 0.0, 100.0) - WorldState.world_offset, Vector3(20000.0, 2.0, 20000.0), mat)
	for t in [[2800.0, 100.0, 335.0], [2700.0, 300.0, 310.0], [2900.0, 0.0, 290.0], [2600.0, -100.0, 262.0]]:
		_box(Vector3(t[0], t[2] * 0.5, t[1]) - WorldState.world_offset, Vector3(40.0, t[2], 40.0), mat)
	var hill := MeshInstance3D.new()
	var pm := PrismMesh.new()
	pm.size = Vector3(1800.0, 420.0, 900.0)
	hill.mesh = pm
	hill.material_override = mat
	hill.position = Vector3(3900.0, 210.0, -900.0) - WorldState.world_offset
	add_child(hill)
	var ml := MarineLayer.new()
	add_child(ml)
	await get_tree().process_frame
	ml.deck = LaWeather.deck_heights(hour)
	ml.top_dip = SeaOfClouds.morning(hour)
	ml.coast_x = -900.0
	for i in 8:
		ml.drive(1.0, -900.0 + LaWeather.edge_offset(hour), 0.0, Color(0.86, 0.87, 0.89), Color(0.25, 0.28, 0.33),
			Color(0, 0, 0), sun_dir, Color(0.62, 0.64, 0.66), 0.016)
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out)
	print("DECK_SHOT saved ", out)
	get_tree().quit()


func _box(c: Vector3, size: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = c
	add_child(mi)
