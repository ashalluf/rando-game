extends Node
## Ground-level stills of the hills without the whole city: builds the FULL hill chunks round a
## point (the real CityChunk build, so the terrain, the shells, the planting and the rocks are
## exactly the game's), lights them with the city scene's own WorldEnvironment and sun, and
## saves a frame from a free camera. About a minute a shot instead of eight, for the loop on the
## hill ground's look (judge the final one in the city with still_shot.gd):
##
##   OUT=/tmp/g.png EYE=-150,1.7,-1100,-160,-6 FOV=60 LIBGL_ALWAYS_SOFTWARE=1 \
##     flock -o /tmp/rando_render_gl.lock xvfb-run -a -s "-screen 0 1280x720x24" godot \
##     --rendering-driver opengl3 --display-driver x11 --audio-driver Dummy --path . \
##     res://tools/glshot/hill_ground_shot.tscn --resolution 1280x720
##
## EYE=x,y,z,yaw,pitch (TRUE world; y is metres over the ground there), FOV (vertical), OUT,
## FRAMES (default 12), BLOCKS (chunks each way round the eye, default 1), SUN=pitch,yaw degrees,
## SHOTS="x,y,z,yaw,pitch;..." more eyes from the same build (OUT_1.png, ...), NOSHELLS=1 hides
## the hill shells, AB=1 saves every frame again without them (<name>_noshells.png), DEBUG_SEQ=1,3
## saves it again in those shell debug modes (<name>_dbgN.png), GEO=1 prints each frame's
## triangles and draws, SHELL_DEBUG=1 draws
## the shells solid (hill_shells.gdshader debug_mode), PROFILE=n profiles n frames with the shells
## and n without (run with --gpu-profile under Forward+; see the block after the shot).

func _ready() -> void:
	await get_tree().process_frame
	var city: Node = (load("res://scenes/levels/city.tscn") as PackedScene).instantiate()
	var plan := CityPlan.new()
	plan.seed = city.world_seed
	plan.block_size_range = city.block_size_range
	plan.street_width = city.street_width
	plan.avenue_width = city.avenue_width
	plan.sidewalk_width = city.sidewalk_width
	plan.downtown_radius = city.downtown_radius
	plan.midtown_radius = city.midtown_radius
	plan.macro = MacroMap.new()
	plan.macro.seed = city.world_seed
	plan.macro.setup()
	for keep in ["WorldEnvironment", "Sun"]:
		var n: Node = city.get_node_or_null(keep)
		if n:
			city.remove_child(n)
			n.owner = null
			add_child(n)
	var sun := get_node_or_null("Sun") as DirectionalLight3D
	var sun_env := OS.get_environment("SUN")
	# The streamer turns the sun in its _ready (the scene's own rotation is level, shining north,
	# and lights every up-facing surface at a grazing angle); do the same, or SUN=pitch,yaw.
	if sun:
		sun.rotation_degrees = city.get("sun_rotation_degrees")
	if sun and sun_env != "":
		var sp := sun_env.split(",")
		sun.rotation_degrees = Vector3(sp[0].to_float(), sp[1].to_float(), 0.0)
	if sun:
		RenderingServer.global_shader_parameter_set("sun_direction", sun.global_basis.z)
	if OS.get_environment("SHELL_DEBUG") != "":
		PropFactory.hill_shell_material().set_shader_parameter("debug_mode", int(OS.get_environment("SHELL_DEBUG")))
	var style: Dictionary = city.chunk_style()
	var eyes: Array = [OS.get_environment("EYE")]
	for e in OS.get_environment("SHOTS").split(";", false):
		eyes.append(e)
	var cam := Camera3D.new()
	cam.fov = float(OS.get_environment("FOV")) if OS.get_environment("FOV") != "" else 60.0
	cam.far = 12000.0
	add_child(cam)
	cam.make_current()
	var built := {}
	var chunk_script: GDScript = load("res://scripts/world/city_chunk.gd")
	var blocks := int(OS.get_environment("BLOCKS")) if OS.get_environment("BLOCKS") != "" else 1
	var out := OS.get_environment("OUT") if OS.get_environment("OUT") != "" else "hill_ground.png"
	for k in eyes.size():
		var p: PackedStringArray = (eyes[k] as String).split(",")
		var at := Vector3(p[0].to_float(), p[1].to_float(), p[2].to_float())
		at.y += plan.height_at(Vector2(at.x, at.z))
		var home: Vector2i = plan.block_index_at(Vector2(at.x, at.z))
		for dz in range(-blocks, blocks + 1):
			for dx in range(-blocks, blocks + 1):
				var bk := Vector2i(home.x + dx, home.y + dz)
				if built.has(bk):
					continue
				var ch = chunk_script.new()
				ch.plan = plan
				ch.ix = bk.x
				ch.iz = bk.y
				ch.level = 0
				ch.style = style
				add_child(ch)
				ch.build()
				built[bk] = ch
		if OS.get_environment("NOSHELLS") == "1":
			get_tree().call_group("hill_shells", "set_visible", false)
		cam.global_transform = Transform3D(Basis.from_euler(Vector3(deg_to_rad(p[4].to_float()), deg_to_rad(p[3].to_float()), 0.0)), at)
		for i in (int(OS.get_environment("FRAMES")) if OS.get_environment("FRAMES") != "" else 12):
			await get_tree().process_frame
		var file := out if k == 0 else out.get_basename() + "_%d.png" % k
		get_viewport().get_texture().get_image().save_png(file)
		print("saved ", file)
		# DEBUG_SEQ=1,3: the same frame again with the shells in each debug_mode (<name>_dbgN.png).
		for m in OS.get_environment("DEBUG_SEQ").split(",", false):
			PropFactory.hill_shell_material().set_shader_parameter("debug_mode", int(m))
			for i in 3:
				await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png(file.get_basename() + "_dbg%s.png" % m)
			PropFactory.hill_shell_material().set_shader_parameter("debug_mode", 0)
		# AB=1: the same frame again without the shells, saved beside it (<name>_noshells.png).
		if OS.get_environment("AB") == "1":
			get_tree().call_group("hill_shells", "set_visible", false)
			for i in 3:
				await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png(file.get_basename() + "_noshells.png")
			get_tree().call_group("hill_shells", "set_visible", true)
		if OS.get_environment("GEO") == "1":
			print("GEO tris=%d draws=%d" % [Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)])
		# PROFILE=n (with --gpu-profile, Forward+): n frames with the shells, then n without, each
		# between markers - split the log at GPU_PROFILE_SPLIT and feed each half to
		# tools/gpu_profile.py.
		var prof := int(OS.get_environment("PROFILE")) if OS.get_environment("PROFILE") != "" else 0
		if prof > 0 and k == 0:
			for pass_shells: bool in [true, false]:
				get_tree().call_group("hill_shells", "set_visible", pass_shells)
				for i in 3:
					await get_tree().process_frame
				print("GPU_PROFILE_BEGIN shells=%s" % pass_shells)
				for i in prof:
					await get_tree().process_frame
				print("GPU_PROFILE_END")
				print("GEO shells=%s tris=%d draws=%d" % [pass_shells, Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)])
				if pass_shells:
					print("GPU_PROFILE_SPLIT")
			get_tree().call_group("hill_shells", "set_visible", OS.get_environment("NOSHELLS") != "1")
	city.free()
	get_tree().quit()
