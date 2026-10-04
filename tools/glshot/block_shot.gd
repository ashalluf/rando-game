extends Node
## Stills of a few city blocks without the whole city: builds the FULL chunks round a point (the
## real CityChunk build: buildings, yards, street furniture, planting), lights them with the city
## scene's own WorldEnvironment and sun, and saves a frame from a free camera. A minute or two a
## shot instead of the ten to twenty a city still takes on a busy render lock - for the loop on a
## block's look (judge the final one in the city with still_shot.gd). Nothing past the built
## blocks is drawn: no far city, no horizon, no traffic.
##
##   OUT=/tmp/b.png EYE=-648,2,60,140,-3 FOV=55 LIBGL_ALWAYS_SOFTWARE=1 \
##     flock -o /tmp/rando_render_gl.lock xvfb-run -a -s "-screen 0 1280x720x24" godot \
##     --rendering-driver opengl3 --display-driver x11 --audio-driver Dummy --path . \
##     res://tools/glshot/block_shot.tscn --resolution 1280x720
##
## EYE=x,y,z,yaw,pitch (TRUE world; y is metres over the ground there; yaw 0 looks north, 90
## west), FOV (vertical), OUT, FRAMES (default 10), BLOCKS (chunks each way round each eye,
## default 1), SHOTS="x,y,z,yaw,pitch;..." more eyes from the same run (OUT_1.png, ...), GEO=1
## prints each frame's triangles and draws, YARD_FILL=0 builds without YardFill (the A/B), INDUSTRIAL=0 without Industrial.

func _ready() -> void:
	await get_tree().process_frame
	if OS.get_environment("INDUSTRIAL") == "0":
		(load("res://scripts/world/industrial.gd") as GDScript).set("enabled", false)
	if OS.get_environment("YARD_FILL") == "0":
		(load("res://scripts/world/yard_fill.gd") as GDScript).set("enabled", false)
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
	if sun:
		sun.rotation_degrees = city.get("sun_rotation_degrees")
		RenderingServer.global_shader_parameter_set("sun_direction", sun.global_basis.z)
	var style: Dictionary = city.chunk_style()
	var eyes: Array = [OS.get_environment("EYE")]
	for e in OS.get_environment("SHOTS").split(";", false):
		eyes.append(e)
	var cam := Camera3D.new()
	cam.fov = float(OS.get_environment("FOV")) if OS.get_environment("FOV") != "" else 55.0
	cam.far = 4000.0
	add_child(cam)
	cam.make_current()
	var built := {}
	var chunk_script: GDScript = load("res://scripts/world/city_chunk.gd")
	var blocks := int(OS.get_environment("BLOCKS")) if OS.get_environment("BLOCKS") != "" else 1
	var out := OS.get_environment("OUT") if OS.get_environment("OUT") != "" else "block.png"
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
		cam.global_transform = Transform3D(Basis.from_euler(Vector3(deg_to_rad(p[4].to_float()), deg_to_rad(p[3].to_float()), 0.0)), at)
		for i in (int(OS.get_environment("FRAMES")) if OS.get_environment("FRAMES") != "" else 10):
			await get_tree().process_frame
		var file := out if k == 0 else out.get_basename() + "_%d.png" % k
		get_viewport().get_texture().get_image().save_png(file)
		print("saved ", file)
		if OS.get_environment("GEO") == "1":
			print("GEO_%d tris=%d draws=%d" % [k, Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)])
	city.free()
	get_tree().quit()
