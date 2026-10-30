extends Node
## Scans the coast south of the airport: road positions, zones, districts, coast x (headless).
##   godot --headless --path . res://tools/power_plant/site_scan.tscn

func _ready() -> void:
	var plan := CityPlan.new()
	plan.seed = 1337
	plan.macro = MacroMap.new()
	plan.macro.seed = 1337
	plan.macro.setup()
	var m: MacroMap = plan.macro
	for z in range(900, 1800, 50):
		print("Z %d coast_x %.1f beach %.1f zone@+60 %s" % [z, m.coast_x(float(z)), m.beach_width_at(float(z)), MacroMap.zone_name(m.zone_at(Vector2(m.coast_x(float(z)) + 100.0, float(z))))])
	var ix0 := plan.block_index_at(Vector2(-1000, 1000)).x
	var ix1 := plan.block_index_at(Vector2(900, 1000)).x
	var iz0 := plan.block_index_at(Vector2(-700, 950)).y
	var iz1 := plan.block_index_at(Vector2(-700, 2100)).y
	for ix in range(ix0, ix1 + 2):
		print("ROADX %d x=%.1f w=%.1f" % [ix, plan.road_pos(0, ix), plan.road_width(0, ix)])
	for iz in range(iz0, iz1 + 2):
		print("ROADZ %d z=%.1f w=%.1f" % [iz, plan.road_pos(1, iz), plan.road_width(1, iz)])
	for iz in range(iz0, iz1 + 1):
		var line := ""
		for ix in range(ix0, ix1 + 1):
			var b: Dictionary = plan.block(ix, iz)
			var c: Vector2 = (b.rect as Rect2).get_center()
			line += "%s/%d/%d%s%s " % [MacroMap.zone_name(m.zone_at(c)).substr(0, 2), int(b.district), int(b.kind), "S" if b.has("site") else "", "G" if b.has("grounds") else ""]
		print("ROW %d %s" % [iz, line])
	var fw = m.freeway
	for iz in range(iz0, iz1 + 1):
		var l2 := ""
		for ix in range(ix0, ix1 + 1):
			l2 += ("F" if fw.blocks_rect((plan.block(ix, iz).rect as Rect2), 3.0) else ".")
		print("FWY %d %s" % [iz, l2])
	for sg in fw.segments_in(Rect2(-800, 950, 1600, 300)):
		print("SEG r%s a %s b %s w %.1f y %.1f" % [sg.get("route", "?"), sg.a, sg.b, float(sg.width), float(sg.get("y", sg.get("ya", 0.0)))])
	for rp in fw.ramps_in(Rect2(-800, 950, 1600, 300)):
		print("RAMP ", rp.pos)
	print("airport ", m.airport_rect, " clear ", m.runway_clear_zone())
	if m.replica:
		print("replica coast ", m.replica.coast_range())
	get_tree().quit()
