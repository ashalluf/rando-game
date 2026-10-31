extends Node
## What stands on the LA hills' blocks: per block its kind, district, lots (yards, houses,
## apartments) and the relief across it. Headless, seconds:
##   godot --headless --path . res://tools/la_hills/lots_probe.tscn      (HILL=id)
func _ready() -> void:
	var macro := MacroMap.new()
	macro.seed = 1337
	macro.setup()
	var plan := CityPlan.new()
	plan.seed = 1337
	plan.macro = macro
	var only := OS.get_environment("HILL")
	var tot := {}
	for hl: Dictionary in macro.la_hills.hills():
		if only != "" and hl.id != only:
			continue
		var box: Rect2 = hl.box
		var bx0 := plan._index_at(CityPlan.AXIS_X, box.position.x)
		var bx1 := plan._index_at(CityPlan.AXIS_X, box.end.x)
		var bz0 := plan._index_at(CityPlan.AXIS_Z, box.position.y)
		var bz1 := plan._index_at(CityPlan.AXIS_Z, box.end.y)
		var counts := {}
		for bx in range(bx0, bx1 + 1):
			for bz in range(bz0, bz1 + 1):
				var b := plan.block(bx, bz)
				var c: Vector2 = (b.rect as Rect2).get_center() if b.has("rect") else Vector2.ZERO
				if macro.la_hills.lift_raw(c) < 3.0:
					continue
				var kind := str(CityPlan.BlockKind.keys()[int(b.kind)])
				var dn := str(CityPlan.District.keys()[int(b.district)])
				var lots := plan.lots(bx, bz)
				var yards := 0
				var houses := 0
				var apts := 0
				var area := 0.0
				for lot: Dictionary in lots:
					if lot.yard:
						yards += 1
						continue
					area += (lot.size as Vector2).x * (lot.size as Vector2).y
					if Apartments.claims(plan, bx, bz, lot, int(b.district)):
						apts += 1
					elif int(b.district) in HouseKit.DISTRICTS:
						houses += 1
				var extra := HouseKit.extra_lots(plan, bx, bz).size()
				var key := kind + "/" + dn
				counts[key] = int(counts.get(key, 0)) + 1
				print("%s (%d,%d) %s %s lots %d yards %d houses %d apts %d extra %d mean lot %.0f m2 lift %.1f rect %s%s" % [hl.id, bx, bz, kind, dn, lots.size(), yards, houses, apts, extra, area / maxf(1, lots.size() - yards), macro.la_hills.lift_raw(c), b.get("rect", ""), " " + str(b.get("grounds", "")) + str(b.get("site", ""))])
		print("== ", hl.id, " ", counts)
	get_tree().quit()
