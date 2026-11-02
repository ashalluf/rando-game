extends SceneTree
## Renders one Building's roof with its rooftop pieces (Rooftops), the real OpenGL renderer under
## Xvfb, in seconds - the fast loop before a city still:
##
##   OUT=roof.png FEAT=helipad LIBGL_ALWAYS_SOFTWARE=1 xvfb-run -a -s "-screen 0 1280x720x24" \
##     godot --rendering-driver opengl3 --display-driver x11 --audio-driver Dummy --path . \
##     --script tools/glshot/rooftop_shot.gd --resolution 960x540
##
## Env: FEAT (helipad, pool, garden, penthouse, mast, bmu: the first seed from SEED0 whose plan has
## one, framed on it), SEED0, LOT (m, 40), HMIN / HMAX (60 / 120), FINISH, NIGHT=1, GOLDEN=1,
## DIST (m from the piece, 26), ELEV (camera height over the roof, 14), YAW (degrees round it),
## FOV, ROOFTOPS=0 (the before, same seed). Compatibility renderer: judge shapes and materials.
func _initialize() -> void:
	var root3d := Node3D.new()
	get_root().add_child(root3d)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.55, 0.70, 0.92)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.60, 0.68)
	e.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.environment = e
	root3d.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, 35, 0)
	sun.shadow_enabled = true
	root3d.add_child(sun)
	for i in 3:
		await process_frame
	var scene := load("res://scenes/props/building.tscn") as PackedScene
	var R = load("res://scripts/world/rooftops.gd")
	var feat := OS.get_environment("FEAT")
	if feat == "":
		feat = "helipad"
	var seed0 := _env_int("SEED0", 1)
	var lot := float(_env_int("LOT", 40))
	var b = null
	var piece: Dictionary = {}
	var plan: Dictionary = {}
	for k in 4000:
		var cand = scene.instantiate()
		cand.seed = seed0 + k * 7919
		cand.lot_size = Vector2(lot, lot)
		cand.min_height = float(_env_int("HMIN", 60))
		cand.max_height = float(_env_int("HMAX", 120))
		if OS.get_environment("FINISH") != "":
			cand.finish_options.assign([int(OS.get_environment("FINISH"))])
		cand.plan_only()
		cand.roof_plan()
		var p: Dictionary = R.plan(cand)
		var found := {}
		if not p.is_empty():
			for f: Dictionary in p.feats:
				if f.kind == feat and (OS.get_environment("HANG") == "" or bool(f.get("hang", false))) \
						and (OS.get_environment("HELI") == "" or bool(f.get("heli", false))):
					found = f
		if not found.is_empty():
			b = scene.instantiate()
			b.seed = cand.seed
			b.lot_size = cand.lot_size
			b.min_height = cand.min_height
			b.max_height = cand.max_height
			b.finish_options.assign(cand.finish_options)
			piece = found
			plan = p
			cand.free()
			break
		cand.free()
	if b == null:
		print("no building with ", feat)
		quit()
		return
	root3d.add_child(b)
	var c: Vector3 = plan.c
	var at := Vector3(c.x + piece.at.x, plan.top, c.z + piece.at.y)
	var cam := Camera3D.new()
	root3d.add_child(cam)
	var dist := float(_env_int("DIST", 26))
	var elev := float(_env_int("ELEV", 14))
	var yaw := deg_to_rad(float(_env_int("YAW", 35)))
	var look_y := float(_env_int("LOOKY", 1))
	cam.look_at_from_position(at + Vector3(sin(yaw) * dist, elev, cos(yaw) * dist), at + Vector3(0, look_y, 0))
	if feat == "bmu":
		# Out past the facade the machine works on, level with the cradle (or the jib), looking
		# back at it a little from the side.
		var nrm: Vector2 = [Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0), Vector2(0, -1)][int(piece.side)]
		var n3 := Vector3(nrm.x, 0, nrm.y)
		var t3 := Vector3(-nrm.y, 0, nrm.x)
		var target := at + n3 * (float(piece.reach) + 0.6)
		if bool(piece.get("hang", false)):
			# Halfway down to the cradle, so the jib and the cradle are both in the frame.
			target.y += (3.0 - float(piece.depth)) * 0.5
		else:
			target.y += 2.5
		cam.look_at_from_position(target + n3 * dist + t3 * dist * 0.45 + Vector3(0, elev, 0), target)
	cam.fov = float(_env_int("FOV", 55))
	cam.far = 3000.0
	cam.current = true
	# A ground plane far below so the view down a facade has a street.
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(3000, 3000)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.35, 0.35, 0.34)
	ground.material_override = gm
	root3d.add_child(ground)
	if OS.get_environment("NIGHT") == "1":
		RenderingServer.global_shader_parameter_set("night_factor", 1.0)
		RenderingServer.global_shader_parameter_set("lamp_factor", 1.0)
		RenderingServer.global_shader_parameter_set("sky_tint", Color(0.04, 0.05, 0.09))
		e.background_color = Color(0.02, 0.025, 0.05)
		e.ambient_light_color = Color(0.05, 0.06, 0.09)
		sun.light_energy = 0.04
	elif OS.get_environment("GOLDEN") == "1":
		RenderingServer.global_shader_parameter_set("lamp_factor", 0.35)
		RenderingServer.global_shader_parameter_set("sky_tint", Color(0.95, 0.62, 0.40))
		e.background_color = Color(0.92, 0.62, 0.42)
		e.ambient_light_color = Color(0.52, 0.42, 0.42)
		sun.rotation_degrees = Vector3(-9, 70, 0)
		sun.light_color = Color(1.0, 0.68, 0.40)
		sun.light_energy = 1.3
	for i in 12:
		await process_frame
	var out := OS.get_environment("OUT")
	if out == "":
		out = "rooftop_shot.png"
	get_root().get_texture().get_image().save_png(out)
	print("saved ", out, " seed=", b.seed, " height=", b.height, " finish=", b.finish, " feats=", (plan.feats as Array).map(func(f): return f.kind), " tris=", b.get_meta("rooftops_tris", 0))
	quit()


static func _env_int(key: String, fallback: int) -> int:
	var v := OS.get_environment(key)
	return int(v) if v != "" else fallback
