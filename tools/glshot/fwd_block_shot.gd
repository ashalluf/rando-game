extends Node3D
## block_shot.gd with the city's own sky and weather: the FULL chunks round each EYE, lit by the
## city scene's WorldEnvironment, Sun, DayNight and Weather nodes (moved out of city.tscn, so the
## hour, the weather states, the marine layer, the Santa Ana, the heat haze, the lamps and the
## sky are the game's). No far city, no horizon plane, no traffic. Small enough for Forward+
## under lavapipe (the whole city is not), which is what it is for:
##
##   OUT=/tmp/f.png EYE=2984,1.7,170,180,4 xvfb-run -a -s "-screen 0 1280x720x24" godot \
##     --rendering-driver vulkan --display-driver x11 --audio-driver Dummy --path . \
##     res://tools/glshot/fwd_block_shot.tscn --resolution 960x540 -- --hour=21 --weather=clear
##
## (opengl3 for the Compatibility path.) EYE=x,y,z,yaw,pitch (TRUE world, y metres over the
## ground there; yaw 0 north, 90 west), SHOTS="eye;eye" more from the same load (OUT_1.png ...),
## FOV, FRAMES (default 30), BLOCKS (chunks each way, default 1; 0 none - sky and weather only),
## FAR (camera far, default 12000), GEO=1 prints triangles and draws. --hour= and --weather= are
## read by DayNight and Weather themselves. The tool node carries `plan` and `world_seed` the way
## CityStreamer does, so Weather finds the fire site and the coast.

var plan: CityPlan
var world_seed: int = 0


func _env(k: String, d: String) -> String:
	var v := OS.get_environment(k)
	return v if v != "" else d


func _ready() -> void:
	var city: Node = (load("res://scenes/levels/city.tscn") as PackedScene).instantiate()
	world_seed = city.world_seed
	plan = CityPlan.new()
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
	var style: Dictionary = city.chunk_style()
	var eyes: Array = [_env("EYE", "0,2,0,0,0")]
	for e in _env("SHOTS", "").split(";", false):
		eyes.append(e)
	var first: PackedStringArray = (eyes[0] as String).split(",")
	var at0 := Vector3(first[0].to_float(), first[1].to_float(), first[2].to_float())
	at0.y += plan.height_at(Vector2(at0.x, at0.z))
	# A stand-in player where the camera is (rain, litter and dust follow "player").
	var stand := Node3D.new()
	stand.name = "PlayerStandIn"
	stand.add_to_group("player")
	add_child(stand)
	stand.global_position = at0
	var cam := Camera3D.new()
	cam.fov = float(_env("FOV", "55"))
	cam.far = float(_env("FAR", "12000"))
	add_child(cam)
	cam.make_current()
	cam.global_transform = Transform3D(Basis.from_euler(Vector3(deg_to_rad(first[4].to_float()), deg_to_rad(first[3].to_float()), 0.0)), at0)
	for keep in ["WorldEnvironment", "Sun", "DayNight", "Weather"]:
		var n: Node = city.get_node_or_null(keep)
		if n:
			city.remove_child(n)
			n.owner = null
			add_child(n)
	var built := {}
	var chunk_script: GDScript = load("res://scripts/world/city_chunk.gd")
	var blocks := int(_env("BLOCKS", "1"))
	var out := _env("OUT", "fwd_block.png")
	for k in eyes.size():
		var p: PackedStringArray = (eyes[k] as String).split(",")
		var at := Vector3(p[0].to_float(), p[1].to_float(), p[2].to_float())
		at.y += plan.height_at(Vector2(at.x, at.z))
		var home: Vector2i = plan.block_index_at(Vector2(at.x, at.z))
		if blocks > 0:
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
		stand.global_position = at
		cam.global_transform = Transform3D(Basis.from_euler(Vector3(deg_to_rad(p[4].to_float()), deg_to_rad(p[3].to_float()), 0.0)), at)
		for i in int(_env("FRAMES", "30")):
			await get_tree().process_frame
		var file := out if k == 0 else out.get_basename() + "_%d.png" % k
		get_viewport().get_texture().get_image().save_png(file)
		print("saved ", file)
		if _env("GEO", "") == "1":
			print("GEO_%d tris=%d draws=%d" % [k, Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)])
	# Tearing the scene down under lavapipe can take minutes (and holds its 10 GB meanwhile):
	# the shots are on disk, so leave at once.
	print("DONE")
	OS.kill(OS.get_process_id())
