extends Node
## The per-hour grade (HourGrade) on a few city blocks, one frame per hour from one build: the
## real FULL chunks round a point (block_shot.gd's build), the city scene's WorldEnvironment, Sun
## and DayNight (so the sun, sky, ambient, exposure and the grade are the game's at each hour) and
## the player camera's own attributes (auto exposure). Small enough for lavapipe, so this is the
## way to see the grade on Forward+ (the Mac's renderer) without the whole city:
##
##   OUT=/tmp/g.png EYE=2359.4,2,880,0,12 HOURS=12,17.6,18.3,22 \
##     xvfb-run -a -s "-screen 0 1280x720x24" godot --rendering-driver vulkan \
##     --display-driver x11 --audio-driver Dummy --path . res://tools/glshot/grade_shot.tscn \
##     --resolution 960x540
##
## EYE=x,y,z,yaw,pitch (TRUE world; y over the ground there), FOV, BLOCKS (chunks each way, 2),
## HOURS (comma list; each saved as OUT_<hour>.png), FRAMES per hour (16), MARINE=0..1 and
## DARKEN=0..1 and SANTA=0..1 hold DayNight's weather hooks there (no Weather node here: its fog
## and rain are not drawn, only the light and the grade). HOUR_GRADE=0 is the old single curve,
## GRADE_RAW=1 the tonemapper's output with no curve and saturation 1.

## SkyExtras reads its streamer's plan (the light dome's survey).
var plan: CityPlan
var world_seed: int = 0


func _ready() -> void:
	await get_tree().process_frame
	var city: Node = (load("res://scenes/levels/city.tscn") as PackedScene).instantiate()
	plan = CityPlan.new()
	plan.seed = city.world_seed
	world_seed = city.world_seed
	plan.block_size_range = city.block_size_range
	plan.street_width = city.street_width
	plan.avenue_width = city.avenue_width
	plan.sidewalk_width = city.sidewalk_width
	plan.downtown_radius = city.downtown_radius
	plan.midtown_radius = city.midtown_radius
	plan.macro = MacroMap.new()
	plan.macro.seed = city.world_seed
	plan.macro.setup()
	for keep in ["WorldEnvironment", "Sun", "DayNight"]:
		var n: Node = city.get_node_or_null(keep)
		if n:
			city.remove_child(n)
			n.owner = null
			add_child(n)
	var day: Node = get_node_or_null("DayNight")
	if day:
		day.call("set_paused", true)
	var cam := Camera3D.new()
	cam.fov = float(OS.get_environment("FOV")) if OS.get_environment("FOV") != "" else 60.0
	cam.far = 4000.0
	var player: Node = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	var pcam := player.find_child("Camera3D", true, false) as Camera3D
	if pcam:
		cam.attributes = pcam.attributes
	player.free()
	add_child(cam)
	cam.make_current()
	var p: PackedStringArray = OS.get_environment("EYE").split(",")
	var at := Vector3(p[0].to_float(), p[1].to_float(), p[2].to_float())
	at.y += plan.height_at(Vector2(at.x, at.z))
	var blocks := int(OS.get_environment("BLOCKS")) if OS.get_environment("BLOCKS") != "" else 2
	var home: Vector2i = plan.block_index_at(Vector2(at.x, at.z))
	var chunk_script: GDScript = load("res://scripts/world/city_chunk.gd")
	var style: Dictionary = city.chunk_style()
	for dz in range(-blocks, blocks + 1):
		for dx in range(-blocks, blocks + 1):
			var ch = chunk_script.new()
			ch.plan = plan
			ch.ix = home.x + dx
			ch.iz = home.y + dz
			ch.level = 0
			ch.style = style
			add_child(ch)
			ch.build()
	cam.global_transform = Transform3D(Basis.from_euler(Vector3(deg_to_rad(p[4].to_float()), deg_to_rad(p[3].to_float()), 0.0)), at)
	var out := OS.get_environment("OUT") if OS.get_environment("OUT") != "" else "grade.png"
	var frames := int(OS.get_environment("FRAMES")) if OS.get_environment("FRAMES") != "" else 16
	for h in OS.get_environment("HOURS").split(",", false):
		if day:
			day.set("hour", h.to_float())
			for hook in [["MARINE", "marine"], ["DARKEN", "weather_darken"], ["SANTA", "santa_ana"]]:
				if OS.get_environment(hook[0]) != "":
					day.set(hook[1], OS.get_environment(hook[0]).to_float())
			day.call("_apply")
		for i in frames:
			await get_tree().process_frame
		var file := out.get_basename() + "_%s.png" % h
		get_viewport().get_texture().get_image().save_png(file)
		var grade: Variant = day.get("grade") if day else null
		print("saved ", file, " grade ", grade.get("current") if grade else "off")
	city.free()
	get_tree().quit()
