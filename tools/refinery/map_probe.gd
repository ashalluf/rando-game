extends SceneTree
## Where can the refinery go? Prints the blocks between the 110 and the port: district, zone,
## and what already claims them (headless, a minute).
##   godot --headless --path . --script tools/refinery/map_probe.gd   (X0, X1, Z0, Z1 the box)

func _initialize() -> void:
	var macro := MacroMap.new()
	macro.seed = 1337
	macro.setup()
	var plan := CityPlan.new()
	plan.seed = 1337
	plan.macro = macro
	var x0 := float(OS.get_environment("X0")) if OS.get_environment("X0") != "" else 1800.0
	var x1 := float(OS.get_environment("X1")) if OS.get_environment("X1") != "" else 4800.0
	var z0 := float(OS.get_environment("Z0")) if OS.get_environment("Z0") != "" else 3400.0
	var z1 := float(OS.get_environment("Z1")) if OS.get_environment("Z1") != "" else 6100.0
	var a: Vector2i = plan.block_index_at(Vector2(x0, z0))
	var b: Vector2i = plan.block_index_at(Vector2(x1, z1))
	var hdr := "      "
	for ix in range(a.x, b.x + 1):
		hdr += "%6d" % int(plan.road_pos(0, ix))
	print(hdr)
	for iz in range(a.y, b.y + 1):
		var line := "%6d" % int(plan.road_pos(1, iz))
		for ix in range(a.x, b.x + 1):
			var blk: Dictionary = plan.block(ix, iz)
			var r: Rect2 = blk.rect
			var c := r.get_center()
			var z: int = plan.macro.zone_at(c)
			var ch := "."
			if z != MacroMap.Zone.CITY:
				ch = ["C", "B", "O", "H", "A", "P"][z] if z < 6 else "?"
			elif plan.river_block(ix, iz):
				ch = "R"
			elif blk.has("site"):
				ch = "S"
			elif blk.has("grounds") or blk.has("hospital"):
				ch = "G"
			elif FreightYard.claims(plan, ix, iz):
				ch = "Y"
			else:
				var fw: bool = plan.macro.freeway != null and plan.macro.freeway.blocks_rect(r, 0.0)
				var d: int = blk.district
				ch = ["d", "m", "s", "i", "c", "b"][d] if d < 6 else str(d)
				if fw:
					ch = ch.to_upper()
			line += "%6s" % ch
		print(line)
	var site := Rect2(2739.0, 5167.0, 3235.0 - 2739.0, 5830.0 - 5167.0)
	print("SITE ", site, " freeway blocks: ", plan.macro.freeway.blocks_rect(site.grow(-12.0), 0.0))
	for r in plan.macro.freeway.ramps_in(site.grow(60.0)):
		print("RAMP ", r.pos, " ", r.get("side", ""))
	var fr = FreightRail.of(plan)
	print("FREIGHT ", fr != null)
	print("ZONE C=city B=beach O=ocean H=hills A=airport P=port; R river S site G grounds Y freight yard; lowercase district d m s i c b; upper = freeway reaches")
	quit()
