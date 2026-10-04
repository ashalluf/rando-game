extends Node
## How long an industrial chunk takes to build, step by step, FULL and LOD, with Industrial on and
## off (the A/B), headless:
##
##   godot --headless --path . res://tools/industrial_bench/industrial_bench.tscn
##
## BLOCKS="bx,bz;..." (default a Vernon truck-court block, a spur block and two Arts District
## blocks). Prints each build's total and its slowest step, in milliseconds.

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
	var spec := OS.get_environment("BLOCKS")
	if spec == "":
		spec = "24,22;26,21;33,3;36,3"
	var ind: GDScript = load("res://scripts/world/industrial.gd")
	# Off once first to warm the shared models and materials, then on, then off again.
	for on: bool in [false, true, false]:
		ind.set("enabled", on)
		for b in spec.split(";", false):
			var p := b.split(",")
			var k := Vector2i(p[0].to_int(), p[1].to_int())
			for level in [0, 1]:
				var ch := CityChunk.new()
				ch.plan = plan
				ch.ix = k.x
				ch.iz = k.y
				ch.level = level
				ch.style = style
				add_child(ch)
				ch.begin_build()
				var total := 0.0
				var worst := 0.0
				var steps := 0
				while true:
					var t0 := Time.get_ticks_usec()
					var done := ch.build_step()
					var ms := float(Time.get_ticks_usec() - t0) / 1000.0
					total += ms
					worst = maxf(worst, ms)
					steps += 1
					if done:
						break
				print("BENCH industrial=%s block %s %s: %.1f ms in %d steps, slowest %.1f ms" % [on, k, "FULL" if level == 0 else "LOD", total, steps, worst])
				remove_child(ch)
				ch.free()
	city.free()
	get_tree().quit()
