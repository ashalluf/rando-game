extends Node
## How long a river chunk takes to build, step by step, FULL, LOD and the far city's capture,
## headless, and what it made (meshes and their vertex counts, collision faces, lights):
##
##   godot --headless --path . res://tools/la_river/river_bench.tscn
##
## BLOCKS="bx,bz;..." (default: the chunks that own the 1st St, 6th St and Olympic bridges, the
## rail bridge and a ramp).

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
	var rv: LaRiver = plan.macro.river
	var spec := OS.get_environment("BLOCKS")
	var keys: Array[Vector2i] = []
	if spec == "":
		for br in rv.bridges(plan):
			if ["1ST ST", "6TH ST", "OLYMPIC BLVD"].has(br.name):
				keys.append(br.owner)
		if not rv.rail_bridge(plan).is_empty():
			keys.append(rv.rail_bridge(plan).owner)
		keys.append(rv.ramps(plan)[1].owner)
	else:
		for b in spec.split(";", false):
			var p := b.split(",")
			keys.append(Vector2i(p[0].to_int(), p[1].to_int()))
	for k in keys:
		for level in [0, 1, 2]:
			var ch := CityChunk.new()
			ch.plan = plan
			ch.ix = k.x
			ch.iz = k.y
			ch.level = 0 if level == 0 else 1
			ch.capturing = level == 2
			ch.style = style
			if level < 2:
				add_child(ch)
			ch.begin_build()
			var total := 0.0
			var worst := 0.0
			var steps := 0
			var times: Array[String] = []
			while true:
				var t0 := Time.get_ticks_usec()
				var done := ch.build_step()
				var ms := float(Time.get_ticks_usec() - t0) / 1000.0
				total += ms
				worst = maxf(worst, ms)
				times.append("%.0f" % ms)
				steps += 1
				if done:
					break
			var parts := []
			for c in ch.get_children():
				if c is MeshInstance3D and str(c.name).begins_with("River"):
					var m: Mesh = (c as MeshInstance3D).mesh
					var verts := 0
					for si in m.get_surface_count():
						verts += (m.surface_get_arrays(si)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
					parts.append("%s %d tris" % [c.name, verts / 3])
				if c is StaticBody3D and str(c.name) == "RiverBody":
					var shp := ((c as StaticBody3D).get_child(0) as CollisionShape3D).shape as ConcavePolygonShape3D
					parts.append("collision %d faces" % (shp.get_faces().size() / 3))
			var lights := 0
			for c in ch.get_children():
				if c is OmniLight3D:
					lights += 1
			var lvl: String = ["FULL", "LOD", "CAPTURE"][level]
			var extra := ""
			if level == 2:
				extra = " boxes %d ground %d" % [(ch.captured.boxes as Array).size(), (ch.captured.ground as Array).size()]
			print("RIVER block %s %s: %.1f ms in %d steps, slowest %.1f ms; %s; lights %d%s; steps %s" % [k, lvl, total, steps, worst, ", ".join(parts), lights, extra, " ".join(times)])
			if level < 2:
				ch.queue_free()
			else:
				ch.free()
	get_tree().quit()
