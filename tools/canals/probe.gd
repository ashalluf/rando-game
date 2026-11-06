extends SceneTree
## The canal neighbourhood's layout, printed (headless, seconds): the snapped site, the canals,
## islands, lots and houses by type, bridges, docks; then builds each site chunk FULL and LOD
## (BUILD=1) and counts what it made. Usage:
##   godot --headless --path . --script tools/canals/probe.gd [-- BUILD=1]
## Classes are loaded by path (the tool compiles before the autoloads exist).
func _initialize() -> void:
	change_scene_to_file("res://scenes/levels/city.tscn")
	for i in 8:
		await process_frame
	var plan = current_scene.get("plan")
	var canals: GDScript = load("res://scripts/world/canals.gd")
	var lay: Dictionary = canals.call("layout", plan)
	if lay.is_empty():
		print("CANALS none")
		quit()
		return
	var s: Dictionary = lay.site
	print("SITE rect=%s inner=%s roads x %d..%d z %d..%d" % [lay.rect, lay.inner, s.ix0, s.ix1, s.iz0, s.iz1])
	for c: Dictionary in lay.canals:
		print("CANAL %s axis=%d c=%.1f %.1f..%.1f" % [c.name, c.axis, c.c, c.a0, c.a1])
	print("ISLANDS %d LOTS %d BRIDGES %d WALKS %d COPES %d" % [lay.islands.size(), lay.lots.size(), lay.bridges.size(), lay.walks.size(), lay.copes.size()])
	var styles := {}
	var docks := 0
	var glass := 0
	for lot: Dictionary in lay.lots:
		var h: Dictionary = canals.call("house_for", plan, lot)
		var nm: String = ["ranch", "spanish", "craftsman", "midcentury", "stucco_box", "dingbat"][int(h.style)]
		styles[nm] = int(styles.get(nm, 0)) + 1
		if lot.dock:
			docks += 1
		if h.get("glass_front", false):
			glass += 1
	print("STYLES ", styles, " glass_fronts=", glass, " docks=", docks)
	for b: Dictionary in lay.bridges:
		print("BRIDGE at=%s axis=%d" % [b.at, b.axis])
	# Road closures.
	for ix in range(int(s.ix0), int(s.ix1) + 1):
		var x: float = plan.road_pos(0, ix)
		print("ROAD X %d at %.1f open(mid)=%s" % [ix, x, plan.road_open(0, ix, (lay.rect as Rect2).get_center().y)])
	for iz in range(int(s.iz0), int(s.iz1) + 1):
		var z: float = plan.road_pos(1, iz)
		print("ROAD Z %d at %.1f open(mid)=%s" % [iz, z, plan.road_open(1, iz, (lay.rect as Rect2).get_center().x)])
	if OS.get_environment("BUILD") == "1":
		var cc: GDScript = load("res://scripts/world/city_chunk.gd")
		for ix in range(int(s.ix0), int(s.ix1)):
			for iz in range(int(s.iz0), int(s.iz1)):
				for level in [0, 1]:
					var ch = cc.new()
					ch.plan = plan
					ch.ix = ix
					ch.iz = iz
					ch.level = level
					ch.zone = plan.zone_at(plan.block(ix, iz).rect.get_center())
					ch.style = current_scene.call("_style_for", ix, iz) if current_scene.has_method("_style_for") else {}
					print("CHUNK %d,%d level %d site=%s" % [ix, iz, level, plan.block(ix, iz).get("site", "")])
	quit()
