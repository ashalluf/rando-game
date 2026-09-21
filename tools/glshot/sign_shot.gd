extends SceneTree
## Renders a row of shopfronts so the signs can be judged on their own, without waiting for the
## whole city to stream in. A city shot costs minutes; this costs seconds, and the sign band is
## three metres of a facade that a city shot puts twenty pixels of on the screen.
##
##   OUT=sign.png DIST=30 LIBGL_ALWAYS_SOFTWARE=1 xvfb-run -a -s "-screen 0 1280x720x24" \
##     godot --rendering-driver opengl3 --display-driver x11 --audio-driver Dummy --path . \
##     --script tools/glshot/sign_shot.gd --resolution 1280x720
##
## Env: OUT (png), DIST (metres back from the shopfronts), EYE (camera height), COUNT (buildings),
## BSEED (first seed), NIGHT (1 lights the lamps), PAINT (1 forces the painted names to full
## strength, which is what the web build gets), NOLETTERS (1 hides the raised letters, to see the
## paint alone). It is the Compatibility renderer, like the web build: judge shape and texture.
func _initialize() -> void:
	var root3d := Node3D.new()
	get_root().add_child(root3d)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.52, 0.68, 0.92)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.62, 0.66, 0.72)
	env.environment = e
	root3d.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-46, 24, 0)
	var night := _env_int("NIGHT", 0) == 1
	if night:
		sun.light_energy = 0.05
		e.ambient_light_color = Color(0.10, 0.12, 0.18)
		e.background_color = Color(0.04, 0.05, 0.09)
	root3d.add_child(sun)
	RenderingServer.global_shader_parameter_set("lamp_factor", 1.0 if night else 0.0)
	RenderingServer.global_shader_parameter_set("night_factor", 1.0 if night else 0.0)
	var scene := load("res://scenes/props/building.tscn") as PackedScene
	var count := _env_int("COUNT", 4)
	var lot := 24.0
	var x := 0.0
	for i in count:
		var b := scene.instantiate()
		b.seed = _env_int("BSEED", 3) + i * 17
		b.lot_size = Vector2(lot, lot)
		b.min_height = 12.0
		b.max_height = 22.0
		b.force_shape = 0
		b.position = Vector3(x, 0.0, 0.0)
		root3d.add_child(b)
		x += lot + 1.0
	await process_frame
	if _env_int("PAINT", 0) == 1 or _env_int("NOLETTERS", 0) == 1:
		_override(root3d)
	var dist := float(_env_int("DIST", 24))
	var eye := float(_env_int("EYE", 4))
	var cam := Camera3D.new()
	root3d.add_child(cam)
	# Off to one side, so the row runs away from the camera: a fascia is nearly always seen at a
	# glancing angle, which is the hardest case for a painted name.
	cam.look_at_from_position(Vector3(-dist * 0.45, eye, dist), Vector3(lot * 0.6, 3.8, 0.0))
	cam.far = 3000.0
	get_root().get_camera_3d()
	for i in 6:
		await process_frame
	var out := OS.get_environment("OUT")
	if out == "":
		out = "sign_shot.png"
	get_root().get_texture().get_image().save_png(out)
	print("saved ", out)
	quit()


func _override(node: Node) -> void:
	for child in node.get_children():
		if child is MeshInstance3D:
			var mi := child as MeshInstance3D
			if str(mi.name).begins_with("Sign") and _env_int("NOLETTERS", 0) == 1:
				mi.visible = false
			if mi.material_override is ShaderMaterial and _env_int("PAINT", 0) == 1:
				(mi.material_override as ShaderMaterial).set_shader_parameter("sign_paint_near", 1.0)
		_override(child)


func _env_int(name: String, def: int) -> int:
	var v := OS.get_environment(name)
	return int(v) if v != "" else def
