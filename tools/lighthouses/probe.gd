extends Node
## The harbour lights (Lighthouses): the pad, the breakwater's pieces, and a build of every piece
## near and far with its time and triangles (LandmarkGeo's count; stones are instances). EYEs for
## still_shot.gd. Headless, seconds:
##   godot --headless --path . res://tools/lighthouses/probe.tscn

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
	var m := MacroMap.new()
	m.seed = city.world_seed
	m.setup()
	plan.macro = m
	city.free()
	var y := Lighthouses.pad_y(m)
	print("PAD y %.2f at %s, zone %s" % [y, Lighthouses.LIGHT_AT, MacroMap.zone_name(m.zone_at(Lighthouses.LIGHT_AT))])
	for r in [0.0, 15.0, 21.0, 25.0, 30.0, 36.0, 42.0]:
		var line := "  r %4.0f:" % r
		for a in 8:
			var p: Vector2 = Lighthouses.LIGHT_AT + Vector2(cos(TAU * a / 8.0), sin(TAU * a / 8.0)) * r
			line += " %6.1f" % m.height_at(p)
		print(line)
	var segs := Lighthouses.segments()
	print("BREAKWATER %d pieces, %.0f m" % [segs.size(), Lighthouses.breakwater_length()])
	var holder := Node3D.new()
	add_child(holder)
	for lm: Dictionary in Lighthouses.entries():
		for detailed in ([false, true, true] if OS.get_environment("TWICE") == "1" else [true, false]):
			var t0 := Time.get_ticks_usec()
			var tri0 := LandmarkGeo.committed_triangles
			var node := Node3D.new()
			holder.add_child(node)
			var statics := StaticBody3D.new()
			node.add_child(statics)
			Landmarks.build(lm, node, statics if detailed else null, plan, detailed)
			var inst := 0
			for mm in node.find_children("*", "MultiMeshInstance3D", true, false):
				inst += (mm as MultiMeshInstance3D).multimesh.instance_count
			print("BUILD %-22s %s %6.1f ms  tris %6d  instances %4d  nodes %d" % [lm.id, "near" if detailed else "far ", (Time.get_ticks_usec() - t0) / 1000.0,
				LandmarkGeo.committed_triangles - tri0, inst, node.find_children("*", "", true, false).size()])
			node.queue_free()
	var g := Lighthouses.gate_at()
	print("EYE lighthouse front: %.1f,%.1f,%.1f,%.0f,%.0f" % [Lighthouses.LIGHT_AT.x + 30.0, y + 6.0, Lighthouses.LIGHT_AT.y + 32.0, 43, 0])
	print("EYE gate: %.1f,%.1f,%.1f" % [g.x + 40.0, 8.0, g.y + 30.0])
	get_tree().quit()
