extends SceneTree
## Ballpark clash probe: the ballpark's site, banks and roads against the freeways (and the
## four-level stack), the other landmarks and the river. Headless, seconds:
##   godot --headless --path . --script tools/stadium/clash_probe.gd   (SEED=n)
func _initialize() -> void:
	var sd := int(OS.get_environment("SEED")) if OS.get_environment("SEED") != "" else 1337
	var macro := MacroMap.new()
	macro.seed = sd
	macro.setup()
	var fw: Freeway = macro.freeway
	if fw.stack:
		print("STACK centre ", fw.stack.centre, " dist to home ", fw.stack.centre.distance_to(Ballpark.HOME))
	else:
		print("STACK none")
	var site := Ballpark.bounds()
	print("SITE bounds ", site, " carve box ", Ballpark.CARVE_BOX)
	var big := Ballpark.CARVE_BOX.grow(50.0)
	var n := 0
	for s in fw.segments_in(big):
		var mid: Vector2 = (s.a + s.b) * 0.5
		var q := Ballpark.local(mid)
		var e := Ballpark.site_sd(q)
		if e < Ballpark.BANK_REACH + 30.0:
			n += 1
			if n <= 30:
				print("FWY seg near site: ", s.get("route", "?"), " mid ", mid, " site_sd ", snappedf(e, 0.1))
	print("FWY segs within bank reach: ", n)
	print("blocks_rect(site,3) = ", fw.blocks_rect(site, 3.0))
	for rn in ["Sunridge Dr", "Stadium Way"]:
		var r := Ballpark.road(macro, rn)
		if r.is_empty():
			print("ROAD ", rn, " missing")
			continue
		var pts: PackedVector2Array = r.points
		var hs: PackedFloat32Array = r.heights
		var hit := 0
		var worst := 0.0
		for i in pts.size():
			var g := macro.height_at(pts[i])
			if absf(g - hs[i]) > worst:
				worst = absf(g - hs[i])
				r["_w"] = "%s raw %.1f ground %.1f bed %.1f" % [pts[i], macro.raw_height_at(pts[i]), g, hs[i]]
			if fw.blocks_rect(Rect2(pts[i] - Vector2(7, 7), Vector2(14, 14)), 1.0):
				hit += 1
				if hit <= 8:
					print("  ", rn, " point ", pts[i], " on a freeway footprint, road y ", snappedf(hs[i], 0.1))
		print("ROAD ", rn, " pts ", pts.size(), " freeway hits ", hit, " max |ground-bed| ", snappedf(worst, 0.01), " at ", r.get("_w", ""))
	var plan := CityPlan.new()
	plan.seed = sd
	plan.macro = macro
	for lm in Landmarks.all():
		if lm.id == "ballpark":
			continue
		var d: float = lm.anchor.distance_to(Ballpark.anchor())
		if d < 900.0:
			print("LANDMARK near: ", lm.id, " ", lm.anchor, " d ", snappedf(d, 1.0), " r ", lm.get("radius", 0))
	quit()
