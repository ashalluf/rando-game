extends Node
## Alley probe: which blocks have a service alley (Alleys.spec(), pure), and - planning every lot's
## building the way the chunk does (Building.plan_only()) - the runs the block step would lay: how
## many reach both mouths, their widths, and an EYE= for still_shot.gd down each.
##   godot --headless --path . tools/alleys/probe.tscn -- [SEED=n] [AREA=x0,z0,x1,z1] [LIST=n] [WALLED=0..1]
## BUILD=bx,bz builds that block's FULL chunk instead and prints what its alley holds (the props by
## kind, the runs, the wear, the upright triangles) and how long the alley's steps took.

func _ready() -> void:
	await get_tree().process_frame
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=")
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	var seed_value := int(args.get("SEED", "1337"))
	var area := Rect2(-1500, -2500, 6500, 6000)
	if args.has("AREA"):
		var v: PackedStringArray = str(args.AREA).split(",")
		area = Rect2(float(v[0]), float(v[1]), float(v[2]) - float(v[0]), float(v[3]) - float(v[1]))
	var listn := int(args.get("LIST", "12"))
	var plan := GroundCoverage.make_plan(seed_value)
	if args.has("BUILD"):
		_build(plan, str(args.BUILD))
		get_tree().quit()
		return
	var lo: Vector2i = plan.block_index_at(area.position)
	var hi: Vector2i = plan.block_index_at(area.end)
	var scene: PackedScene = load("res://scenes/props/building.tscn")
	var stats := {}
	var listed := 0
	var t0 := Time.get_ticks_msec()
	for bx in range(lo.x, hi.x + 1):
		for bz in range(lo.y, hi.y + 1):
			var b := plan.block(bx, bz)
			var rect: Rect2 = b.rect
			if not area.has_point(rect.get_center()) or int(b.kind) != CityPlan.BlockKind.BUILDINGS:
				continue
			if plan.zone_at(rect.get_center()) != MacroMap.Zone.CITY:
				continue
			var d: int = b.district
			if not d in Alleys.DISTRICTS:
				continue
			var key: String = GroundCoverage.DISTRICT_NAMES[d]
			if not stats.has(key):
				stats[key] = {"blocks": 0, "alley": 0, "through": 0, "dead": 0, "none": 0, "len": 0.0, "w": 0.0, "runs": 0}
			var s: Dictionary = stats[key]
			s.blocks += 1
			var sp := Alleys.spec(plan, bx, bz)
			if sp.is_empty():
				continue
			s.alley += 1
			var foot := {}
			var boost := plan.macro.skyline_boost(rect.get_center())
			for lot: Dictionary in sp.lots:
				if lot.yard or lot.get("parking", false):
					continue
				var bld: Building = scene.instantiate()
				bld.seed = lot.seed
				bld.lot_size = lot.size
				var target := plan.lot_height(lot.seed, d, boost)
				bld.min_height = target * 0.88
				bld.max_height = target
				var sh: Array[int] = []
				sh.assign(CityPlan.lot_shapes(d, boost))
				bld.shape_options = sh
				var fi: Array[int] = []
				fi.assign(CityPlan.lot_finishes(d, boost))
				bld.finish_options = fi
				bld.podium_lot = true
				bld.plan_only()
				var holes: Array[Rect2] = []
				for part: Dictionary in bld.parts:
					var size: Vector3 = part.size
					var c: Vector3 = part.center
					if c.y - size.y * 0.5 > 0.05:
						continue
					holes.append(Rect2(lot.center.x + c.x - size.x * 0.5, lot.center.y + c.z - size.z * 0.5, size.x, size.z))
				foot[int(lot.seed)] = holes
				bld.free()
			var ob := Alleys.obstacles(sp, foot)
			var rs := Alleys.runs(sp, ob[0])
			if rs.is_empty():
				s.none += 1
				continue
			if rs.size() == 1 and rs[0].m0 and rs[0].m1:
				s.through += 1
			else:
				s.dead += 1
			for r: Dictionary in rs:
				# How walled-in the run is: the share of its length with a building's back within
				# 4 m of each edge.
				var walled := 0
				var samples := 0
				var t := float(r.s0) + 1.0
				while t < float(r.s1) - 1.0:
					for side: float in [-1.0, 1.0]:
						samples += 1
						var edge := float(r.c) + side * float(r.w) * 0.5
						for h: Rect2 in ob[0]:
							var h0 := h.position.x if sp.along_x else h.position.y
							var h1 := h.end.x if sp.along_x else h.end.y
							if t < h0 or t > h1:
								continue
							var face := (h.end.y if sp.along_x else h.end.x) if side < 0.0 else (h.position.y if sp.along_x else h.position.x)
							var gap := side * (face - edge)
							if gap > -0.1 and gap < 4.0:
								walled += 1
								break
					t += 2.0
				r["walled"] = float(walled) / maxf(1.0, float(samples))
				s.runs += 1
				s.len += float(r.s1) - float(r.s0)
				s.w += float(r.w)
				if listed < listn and float(r.walled) >= float(args.get("WALLED", "0")):
					listed += 1
					var along_x: bool = sp.along_x
					var s_eye := float(r.s0) - 3.0 if r.m0 else float(r.s0) + 2.0
					var p := Vector2(s_eye, float(r.c)) if along_x else Vector2(float(r.c), s_eye)
					# yaw: looking +s. Forward is -Z, yaw for direction d = atan2(-d.x, -d.z).
					var dir := Vector2(1, 0) if along_x else Vector2(0, 1)
					var yaw := rad_to_deg(atan2(-dir.x, -dir.y))
					var gy: float = plan.macro.relief_at(p)
					print("RUN %s block %d,%d along_%s s %.1f..%.1f c %.1f w %.2f walled %.2f mouths %s%s  EYE=%.1f,%.1f,%.1f,%.0f,-4" % [key, bx, bz, "x" if along_x else "z", r.s0, r.s1, r.c, r.w, r.walled,
						"L" if r.m0 else "-", "H" if r.m1 else "-", p.x, gy + 1.9, p.y, yaw])
	for key: String in stats:
		var s: Dictionary = stats[key]
		print("ALLEYS %s blocks %d with_alley %d through %d dead_end %d none %d | runs %d mean len %.1f m mean width %.2f m" % [key, s.blocks, s.alley, s.through, s.dead, s.none, s.runs, s.len / maxf(1.0, float(s.runs)), s.w / maxf(1.0, float(s.runs))])
	print("probe %d ms" % (Time.get_ticks_msec() - t0))
	get_tree().quit()


func _build(plan: CityPlan, at: String) -> void:
	var v := at.split(",")
	var city: Node = (load("res://scenes/levels/city.tscn") as PackedScene).instantiate()
	var style: Dictionary = city.chunk_style()
	var ch := CityChunk.new()
	ch.plan = plan
	ch.ix = int(v[0])
	ch.iz = int(v[1])
	ch.level = CityChunk.Level.FULL
	ch.style = style
	add_child(ch)
	var tris0 := IndustrialKit.tris
	var t0 := Time.get_ticks_usec()
	ch.build()
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0
	print("BUILD %s in %.0f ms: runs %s" % [at, ms, str(ch.get_meta("alley_runs", []))])
	print("PROPS ", ch.get_meta("alley_props", {}))
	print("WEAR %d  upright tris ~%d  ground %s walls %s" % [int(ch.get_meta("alley_wear", 0)), IndustrialKit.tris - tris0,
		str(ch.get_node_or_null("AlleyGround") != null), str(ch.get_node_or_null("AlleyWalls") != null)])
	city.free()
