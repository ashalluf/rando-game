extends Node
## Chunk build steps round the bookmarks, headless: for every block within RADIUS blocks of each
## spot, a FULL build, an LOD build and the far city's capture, step by step, and the steps that
## overran CityStreamer.build_budget_ms (4 ms) with the step's name. The streamer runs at least one
## step a frame whatever it costs, so a step over the budget is a frame that long.
##
##   godot --headless --path . res://tools/step_bench/step_bench.tscn
##
## SPOTS="x,z;..." (world metres; default the bookmarks: downtown, freeway, masjid, hills, beach
## town, suburb, arena, MacArthur Park, river, airport, port, Vernon), RADIUS (default 1),
## LEVELS=full,lod,capture. Times are this machine's: read them against each other.

const DEFAULT_SPOTS := {
	"downtown": Vector2(2359.4, 880), "freeway": Vector2(200, 1088), "masjid": Vector2(1880.7, 2809.6),
	"hills": Vector2(300, -650), "beachtown": Vector2(-648, 60), "suburb": Vector2(-290, 307),
	"arena": Vector2(2300, 1150), "macarthur": Vector2(300, 528), "river": Vector2(4244, -777),
	"airport": Vector2(-262, 812), "port": Vector2(3065, 6300), "vernon": Vector2(2610, 3290),
}


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
	var style: Dictionary = city.chunk_style()
	var budget := float(city.build_budget_ms)
	city.free()
	var spots := {}
	var spec := OS.get_environment("SPOTS")
	if spec == "":
		spots = DEFAULT_SPOTS
	else:
		for s in spec.split(";", false):
			var p := s.split(",")
			spots[s] = Vector2(p[0].to_float(), p[1].to_float())
	var radius := int(OS.get_environment("RADIUS")) if OS.get_environment("RADIUS") != "" else 1
	var levels := OS.get_environment("LEVELS").split(",", false) if OS.get_environment("LEVELS") != "" else PackedStringArray(["full", "lod", "capture"])
	var worst_all := {}
	for name: String in spots:
		var c := plan.block_index_at(spots[name])
		for dz in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				var k := Vector2i(c.x + dx, c.y + dz)
				for lvl: String in levels:
					var ch := CityChunk.new()
					ch.plan = plan
					ch.ix = k.x
					ch.iz = k.y
					ch.level = CityChunk.Level.FULL if lvl == "full" else CityChunk.Level.LOD
					ch.capturing = lvl == "capture"
					ch.style = style
					if lvl != "capture":
						add_child(ch)
					ch.begin_build()
					var total := 0.0
					var steps := 0
					var over: Array[String] = []
					var worst := 0.0
					var worst_name := ""
					while true:
						var step_name := ""
						if ch._step < ch._steps.size():
							var cb: Callable = ch._steps[ch._step]
							step_name = String(cb.get_method())
						var t0 := Time.get_ticks_usec()
						var done := ch.build_step()
						var ms := float(Time.get_ticks_usec() - t0) / 1000.0
						total += ms
						steps += 1
						if ms > worst:
							worst = ms
							worst_name = step_name
						if ms > budget:
							over.append("%s %.1f" % [step_name, ms])
						if done:
							break
					print("STEP %-10s %-5s (%d,%d) steps %3d total %7.1f ms worst %6.1f ms (%s) over %d: %s" % [
						name, lvl, k.x, k.y, steps, total, worst, worst_name, over.size(), ", ".join(over.slice(0, 6))])
					var wk := "%s %s" % [lvl, worst_name]
					worst_all[wk] = maxf(float(worst_all.get(wk, 0.0)), worst)
					if lvl != "capture":
						ch.free()
	var ks := worst_all.keys()
	ks.sort_custom(func(a, b): return worst_all[a] > worst_all[b])
	for wk in ks.slice(0, 20):
		print("WORST %-50s %.1f ms" % [wk, worst_all[wk]])
	get_tree().quit()
