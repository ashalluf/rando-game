extends Node
## Oil field probe (OilField): the site, the hill, the roads and their grades, the pads and wells,
## the claimed city lots near a point. Headless, seconds:
##   godot --headless --path . res://tools/oil_field/probe.tscn      (SEED=n)
func _ready() -> void:
	var sd := int(OS.get_environment("SEED")) if OS.get_environment("SEED") != "" else 1337
	var t0 := Time.get_ticks_msec()
	var macro := MacroMap.new()
	macro.seed = sd
	macro.setup()
	var plan := CityPlan.new()
	plan.seed = sd
	plan.macro = macro
	var f: OilField = macro.oil
	print("setup ms=", Time.get_ticks_msec() - t0)
	if f == null:
		print("no field")
		get_tree().quit()
		return
	var site := plan.site_by_id(OilField.ID)
	print("rect=", f.rect, " site=", site.get("rect"), " base_h=%.2f" % f.base_h, " blocks x %d..%d z %d..%d" % [f.ix0, f.ix1, f.iz0, f.iz1])
	var top := -INF
	var top_p := Vector2.ZERO
	for i in 60:
		for j in 60:
			var p := f.rect.position + f.rect.size * Vector2((i + 0.5) / 60.0, (j + 0.5) / 60.0)
			var h := macro.relief_at(p)
			if h > top:
				top = h
				top_p = p
	print("crest %.1f m at %s" % [top, top_p])
	for rd: Dictionary in f.roads:
		var pts: PackedVector2Array = rd.pts
		var hs: PackedFloat32Array = rd.h
		var mg := 0.0
		var cut := 0.0
		for i in pts.size() - 1:
			mg = maxf(mg, absf(hs[i + 1] - hs[i]) / maxf(pts[i].distance_to(pts[i + 1]), 0.01))
			cut = maxf(cut, absf(hs[i] - f.hill(pts[i])))
		print("road ring=%s points=%d length=%.0f max grade=%.3f max cut/fill=%.1f" % [rd.ring, pts.size(), pts.size() * OilField.STEP, mg, cut])
	var kinds := [0, 0, 0]
	for pd: Dictionary in f.pads:
		kinds[int(pd.kind)] += 1
	print("pads=%d wells-pads=%d batteries=%d rigs=%d wells=%d gates=%d" % [f.pads.size(), kinds[0], kinds[1], kinds[2], f.wells().size(), f.gates.size()])
	for pd: Dictionary in f.pads:
		if int(pd.kind) != 0:
			print("  pad kind=%d c=%s r=%.1f h=%.1f EYE=%.0f,%.0f" % [pd.kind, pd.c, pd.r, pd.h, (pd.c as Vector2).x, (pd.c as Vector2).y])
	# EYEs for close-ups: the first wells, seen from their lease road at 1.7 m over the ground.
	for pi in mini(8, f.pads.size()):
		var pd: Dictionary = f.pads[pi]
		if (pd.wells as Array).is_empty():
			continue
		var w: Dictionary = pd.wells[0]
		var fwd := Vector2(cos(float(w.yaw)), -sin(float(w.yaw)))
		var mid: Vector2 = (w.p as Vector2) - fwd * 5.0 * float(w.scale)
		var eye: Vector2 = (pd.c as Vector2) - (pd.out as Vector2) * (float(pd.hz) + OilField.ROAD_HALF + 1.0) + (pd.dir as Vector2) * 6.0
		var i := pi
		var d := mid - eye
		print("  well %d EYE=%.1f,1.7,%.1f,%.1f,3 (EYE_AGL=1) spm=%.1f dist=%.1f" % [i, eye.x, eye.y, rad_to_deg(atan2(-d.x, -d.y)), w.spm, d.length()])
	var claimed := 0
	var by: Dictionary = {}
	for ix in range(-30, 30):
		for iz in range(-20, 60):
			var b := plan.block(ix, iz)
			for lot: Dictionary in plan.lots(ix, iz):
				var w := OilField.lot_well(plan, lot, int(b.district))
				if not w.is_empty():
					claimed += 1
					var d := CityPlan.district_name(int(b.district))
					by[d] = int(by.get(d, 0)) + 1
					if int(by[d]) <= 4:
						var r: Rect2 = b.rect
						var c: Vector2 = lot.center
						var gaps := [c.y - r.position.y, r.end.y - c.y, c.x - r.position.x, r.end.x - c.x]
						var nrm := [Vector2(0, -1), Vector2(0, 1), Vector2(-1, 0), Vector2(1, 0)]
						var k := 0
						for q in 4:
							if float(gaps[q]) < float(gaps[k]):
								k = q
						var eye: Vector2 = c + (nrm[k] as Vector2) * (float(gaps[k]) + 9.0) + Vector2(-(nrm[k] as Vector2).y, (nrm[k] as Vector2).x) * 6.0
						var dd: Vector2 = c - eye
						print("  lot well %s at %s lot %s EYE=%.1f,1.7,%.1f,%.1f,6 (EYE_AGL=1)" % [d, w.p, lot.size, eye.x, eye.y, rad_to_deg(atan2(-dd.x, -dd.y))])
	print("claimed lots=", claimed, " ", by)
	get_tree().quit()
