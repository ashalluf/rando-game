extends Node
## The oil islands (OilIslands, OilIslandBuild), headless and in seconds: each island's zone and
## distance from the shore, its pad, towers and falls, and the near and far builds' triangles and
## nodes, plus an EYE line per island for still_shot.gd (from the shore, the air, close).
##
##   godot --headless --path . tools/oil_islands/probe.tscn

func _ready() -> void:
	var macro := MacroMap.new()
	macro.seed = 1337
	macro.setup()
	var plan := CityPlan.new()
	plan.seed = 1337
	plan.macro = macro
	print("OIL_ISLANDS enabled=%s islands=%d" % [OilIslands.enabled, OilIslands.ISLANDS.size()])
	for lm in Landmarks.all():
		if not OilIslands.is_island(lm.id):
			continue
		var i := OilIslands.index_of(lm.id)
		var a: Vector2 = lm.anchor
		var shore := a.y - macro.bay_z
		var zones := {}
		for k in 32:
			var t := TAU * float(k) / 32.0
			var p := OilIslands.to_world(i, OilIslands.ring_local(i, t, 22.0))
			zones[macro.zone_at(p)] = true
		print("ISLAND %d %s anchor=%s zone=%d ring_zones=%s shore_off=%.0f m" % [i, OilIslands.ISLANDS[i].name, a, macro.zone_at(a), zones.keys(), shore])
		for t: Dictionary in OilIslands.towers(i):
			print("  tower at=%s h=%.1f wash=%d/%d" % [t.at, t.h, t.wash, t.wash2])
		for detailed in [true, false]:
			var root := Node3D.new()
			add_child(root)
			var t0 := Time.get_ticks_usec()
			Landmarks.build(lm, root, null, plan, detailed)
			var ms := (Time.get_ticks_usec() - t0) / 1000.0
			var inst := 0
			var nodes := 0
			for n in root.find_children("*", "", true, false):
				nodes += 1
				if n is MultiMeshInstance3D and (n as MultiMeshInstance3D).multimesh:
					inst += (n as MultiMeshInstance3D).multimesh.instance_count
			print("  %s: %d triangles (mesh), %d batch instances, %d nodes, %.1f ms" % ["near" if detailed else "far", OilIslandBuild.last_triangles, inst, nodes, ms])
			root.free()
		var c := OilIslands.to_world(i, Vector2.ZERO)
		print("  EYE shore %.1f,2.0,%.1f,0,2" % [c.x - 60.0, macro.bay_z - 30.0])
		print("  EYE air %.1f,140,%.1f,0,-30" % [c.x, c.y - 300.0])
		print("  surface at centre %.2f, edge+5 %.2f" % [OilIslands.surface_at(c), OilIslands.surface_at(OilIslands.to_world(i, OilIslands.ring_local(i, 0.3, 5.0)))])
	get_tree().quit()
