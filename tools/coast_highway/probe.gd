extends SceneTree
## Coast highway probe: transects across the northern coast (zone, raw height, height, district,
## the PCH's bed). Headless, seconds:
##   godot --headless --path . --script tools/coast_highway/probe.gd
func _initialize() -> void:
	var sd := int(OS.get_environment("SEED")) if OS.get_environment("SEED") != "" else 1337
	var macro := MacroMap.new()
	macro.seed = sd
	macro.setup()
	var plan := CityPlan.new()
	plan.seed = sd
	plan.macro = macro
	for z in [-400.0, -600.0, -800.0, -1000.0, -1200.0, -1400.0, -1600.0, -1900.0]:
		var cx := macro.coast_x(z)
		var line := "z %6.0f coast %7.1f bw %4.0f |" % [z, cx, macro.beach_width_at(z)]
		for dx in [-10.0, 10.0, 30.0, 46.0, 60.0, 80.0, 110.0, 150.0, 200.0, 300.0, 450.0]:
			var p := Vector2(cx + dx, z)
			line += " %+4.0f:%s%.0f/%.0f" % [dx, MacroMap.ZONE_NAMES[macro.zone_at(p)][0], macro.raw_height_at(p), macro.height_at(p)]
		print(line)
	var ch: CoastHighway = macro.coast_highway
	if ch:
		print("COAST z_north %.0f z_full %.0f z_south %.0f houses %d opens %d towers %d stairs %d stalls %d" % [ch.z_north, ch.z_full, ch.z_south, ch.houses.size(), ch.opens.size(), ch.towers.size(), ch.stairs.size(), ch.stalls.size()])
		var surf := 0
		for st in ch.stalls:
			surf += 1 if st.surf else 0
		print("  surf cars ", surf, " opens ", ch.opens)
		var styles := [0, 0, 0, 0]
		for hs in ch.houses:
			styles[hs.style] += 1
		print("  styles ", styles)
		var others := 0
		for sg in macro.hill_roads.segments_in(Rect2(-1100.0, ch.z_north - 100.0, 300.0, ch.z_south - ch.z_north + 100.0)):
			var mid: Vector2 = (sg.a + sg.b) * 0.5
			var dd: float = mid.x - macro.coast_x(mid.y)
			if absf(dd - CoastHighway.CENTRE) > 3.0 and dd < CoastHighway.REACH + 60.0:
				others += 1
				print("  other road seg ", mid, " d %.0f w %.0f" % [dd, sg.width])
		print("  other roads near ", others, " mansions ", macro.hill_roads.mansions_in(Rect2(-1100.0, ch.z_north - 100.0, 300.0, ch.z_south - ch.z_north + 100.0)).size())
	for r in macro.hill_roads.roads:
		if r.name == "Pacific Coast Highway":
			var pts: PackedVector2Array = r.points
			print("PCH pts ", pts.size(), " first ", pts[0], " last ", pts[pts.size() - 1])
			for i in range(0, pts.size(), 4):
				if pts[i].y < -300.0:
					print("  pch ", pts[i], " h %.1f" % r.heights[i])
	var k0 := plan.chunk_index_at(Vector2(-1100.0, -1600.0))
	var k1 := plan.chunk_index_at(Vector2(-850.0, -750.0))
	for iz in range(k0.y, k1.y + 1):
		var line := "iz %d" % iz
		for ix in range(k0.x, k1.x + 1):
			var r := plan.owned_rect(ix, iz)
			var b := plan.block(ix, iz)
			var zn := macro.zone_at((b.rect as Rect2).get_center())
			line += " | %d: x%.0f..%.0f z%.0f..%.0f %s %s" % [ix, r.position.x, r.end.x, r.position.y, r.end.y, MacroMap.ZONE_NAMES[zn], b.get("kind", "")]
		print(line)
	for s in macro.freeway.segments_in(Rect2(-1150.0, -1600.0, 300.0, 900.0)):
		print("freeway seg ", s.a, s.b)
	quit()
