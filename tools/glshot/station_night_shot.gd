extends Node
## A police station at night in a small scene, on either renderer: the FULL chunks round EYE
## (the real CityChunk build) lit by the city scene's own WorldEnvironment, Sun AND DayNight -
## so the hour, the sky, the exposure, the lamp_factor globals and every `lamp_light` OmniLight3D
## (street lamps, the station's own) are exactly what the game sets. block_shot.tscn's NIGHT=1 is
## a crude stand-in with no DayNight: its lamps are never switched on, which is why the station
## read so dark there. Small enough for lavapipe (Forward+, the Mac's renderer):
##
##   OUT=/tmp/sn.png EYE=3652,1.7,-1079,18,3 HOUR=21 xvfb-run -a -s "-screen 0 1280x720x24" \
##     godot --rendering-driver vulkan --display-driver x11 --audio-driver Dummy --path . \
##     res://tools/glshot/station_night_shot.tscn --resolution 960x540
##
## (opengl3: --rendering-driver opengl3 and LIBGL_ALWAYS_SOFTWARE=1.) EYE=x,y,z,yaw,pitch (TRUE
## world; y is metres over the ground there; yaw 0 looks north, 90 west), SHOTS="eye;eye" more
## eyes from the same build (OUT_1.png, ...), HOUR (default 21), FOV (default 55), FRAMES
## (default 24 a shot: auto exposure and TAA settle), BLOCKS (chunks each way, default 1),
## AE=0 turns the player camera's auto exposure off, POLICE_STATIONS=0 the A/B, GEO=1 prints
## each frame's triangles and draws, LIGHTS=1 counts the lamp lights on and in range.

var plan: CityPlan


func _ready() -> void:
	await get_tree().process_frame
	Engine.set_meta("postfx_motion_blur", 0.0)
	var city: Node = (load("res://scenes/levels/city.tscn") as PackedScene).instantiate()
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
	var hour := float(OS.get_environment("HOUR")) if OS.get_environment("HOUR") != "" else 21.0
	var holder := Node3D.new()
	holder.name = "Light"
	add_child(holder)
	holder.set("plan", plan)
	for keep in ["WorldEnvironment", "Sun", "DayNight"]:
		var n: Node = city.get_node_or_null(keep)
		if n:
			city.remove_child(n)
			n.owner = null
			if keep == "DayNight":
				n.set("start_hour", hour)
			holder.add_child(n)
	var day := holder.get_node_or_null("DayNight")
	if day:
		day.call("set_paused", true)
	var style: Dictionary = city.chunk_style()
	var eyes: Array = [OS.get_environment("EYE")]
	for e in OS.get_environment("SHOTS").split(";", false):
		eyes.append(e)
	var cam := Camera3D.new()
	cam.fov = float(OS.get_environment("FOV")) if OS.get_environment("FOV") != "" else 55.0
	cam.near = 0.05
	cam.far = 4000.0
	if OS.get_environment("AE") != "0":
		var pl: Node = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
		var pc := pl.find_children("*", "Camera3D", true, false)
		if not pc.is_empty():
			var at := (pc[0] as Camera3D).attributes
			if at:
				at = at.duplicate()
				(at as CameraAttributesPractical).dof_blur_far_enabled = false
				cam.attributes = at
		pl.free()
	add_child(cam)
	cam.make_current()
	var built := {}
	var chunk_script: GDScript = load("res://scripts/world/city_chunk.gd")
	var blocks := int(OS.get_environment("BLOCKS")) if OS.get_environment("BLOCKS") != "" else 1
	var frames := int(OS.get_environment("FRAMES")) if OS.get_environment("FRAMES") != "" else 24
	var out := OS.get_environment("OUT") if OS.get_environment("OUT") != "" else "station_night.png"
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
		for i in frames:
			await get_tree().process_frame
		var file := out if k == 0 else out.get_basename() + "_%d.png" % k
		get_viewport().get_texture().get_image().save_png(file)
		print("saved ", file)
		if OS.get_environment("GEO") == "1":
			print("GEO_%d tris=%d draws=%d" % [k, Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)])
		if OS.get_environment("LIGHTS") == "1":
			var on := 0
			var near := 0
			for l in get_tree().get_nodes_in_group("lamp_light"):
				var o := l as OmniLight3D
				if o.visible and o.light_energy > 0.0:
					on += 1
					if o.global_position.distance_to(at) < 120.0:
						near += 1
			print("LIGHTS_%d on=%d within120=%d lamp_factor=%.2f" % [k, on, near, float(RenderingServer.global_shader_parameter_get("lamp_factor"))])
	city.free()
	get_tree().quit()
