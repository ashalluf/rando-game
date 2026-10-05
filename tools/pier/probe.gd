extends SceneTree
## Pier park probe: the shore, zones and ground round Rando Pier, and the block the anchor is in.
##   godot --headless --path . --script tools/pier/probe.gd
func _initialize() -> void:
	var macro := MacroMap.new()
	macro.seed = 1337
	macro.setup()
	var plan := CityPlan.new()
	plan.seed = 1337
	plan.macro = macro
	var a := Vector2(-940.0, -350.0)
	for z in [-420.0, -380.0, -350.0, -320.0, -290.0, -260.0, -220.0]:
		print("z=%.0f coast_x=%.1f beach_w=%.1f" % [z, macro.coast_x(z), macro.beach_width_at(z)])
	for dx in [40.0, 20.0, 0.0, -20.0, -40.0, -60.0, -80.0, -120.0, -200.0, -280.0]:
		var line := "dx=%4.0f" % dx
		for dz in [-30.0, 0.0, 30.0, 60.0]:
			var p := a + Vector2(dx, dz)
			line += "  [%s h=%.2f]" % [MacroMap.zone_name(macro.zone_at(p)), macro.height_at(p)]
		print(line)
	var idx := plan.block_index_at(a)
	print("block ", idx, " rect ", plan.owned_rect(idx.x, idx.y))
	for lm in Landmarks.all():
		if lm.anchor.distance_to(a) < 500.0:
			print("landmark ", lm.id, " ", lm.anchor, " r=", lm.radius)
	quit()
