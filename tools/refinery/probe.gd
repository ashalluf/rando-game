extends Node
## The refinery, printed (headless, a minute): the snapped site, the blocks and their roles, the
## items, the far pieces built and their cost, and EYE lines for stills (still_shot.gd
## EYE=x,y,z,yaw,pitch). A bare MacroMap and CityPlan, no city.
##   godot --headless --path . res://tools/refinery/probe.tscn   (SEED= another seed)

func _ready() -> void:
	var sd := int(OS.get_environment("SEED")) if OS.get_environment("SEED") != "" else 1337
	var macro := MacroMap.new()
	macro.seed = sd
	macro.setup()
	var plan := CityPlan.new()
	plan.seed = sd
	plan.macro = macro
	var t0 := Time.get_ticks_usec()
	var lay := Refinery.layout(plan)
	print("REFINERY layout %.1f ms" % ((Time.get_ticks_usec() - t0) / 1000.0))
	if lay.is_empty():
		print("REFINERY none")
		get_tree().quit()
		return
	var s: Dictionary = lay.site
	print("REFINERY rect=%s roads x %d..%d z %d..%d gate=%s" % [lay.rect, s.ix0, s.ix1, s.iz0, s.iz1, lay.gate.at])
	for sb: Dictionary in lay.subs:
		print("SUB %d,%d %s v%d %s" % [sb.bx, sb.bz, sb.role, sb.variant, sb.content])
	var counts := {}
	for it: Dictionary in lay.items:
		counts[it.type] = int(counts.get(it.type, 0)) + 1
	print("ITEMS ", counts, " racks ", lay.racks.size(), " berms ", lay.berms.size())
	for ix in range(int(s.ix0) - 1, int(s.ix1) + 1):
		print("ROAD X %d open(mid)=%s" % [ix, plan.road_open(0, ix, (lay.rect as Rect2).get_center().y)])
	# Every far piece, and one FULL-detail write per block, timed.
	var gy := func(p: Vector2) -> float: return macro.relief_at(p)
	var far_tris := 0
	var near_max := 0
	var t1 := Time.get_ticks_usec()
	var nl := 0
	for bx in range(int(s.ix0), int(s.ix1)):
		for bz in range(int(s.iz0), int(s.iz1)):
			var area := plan.owned_rect(bx, bz)
			for detail: bool in [false, true]:
				RefineryKit.tris = 0
				var st := SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				var lights: Array = []
				var fl: Array = []
				var pl: Array = []
				var tb := Time.get_ticks_usec()
				Refinery.write(lay, area, st, detail, gy, lights, fl, pl)
				var ms := (Time.get_ticks_usec() - tb) / 1000.0
				if detail:
					near_max = maxi(near_max, RefineryKit.tris)
					print("BLOCK %d,%d near tris %d lights %d flames %d plumes %d  %.1f ms" % [bx, bz, RefineryKit.tris, lights.size(), fl.size(), pl.size(), ms])
				else:
					far_tris += RefineryKit.tris
					nl += lights.size()
	print("FAR total tris %d lights %d  %.1f ms" % [far_tris, nl, (Time.get_ticks_usec() - t1) / 1000.0])
	var r: Rect2 = lay.rect
	var g: Vector2 = lay.gate.at
	print("EYE gate   %.1f,1.7,%.1f,%.1f,6" % [g.x + 12.0, g.y - 40.0, rad_to_deg(atan2(-12.0, -40.0)) + 180.0])
	print("EYE aerial %.1f,260,%.1f,%.1f,-30" % [r.position.x - 300.0, r.end.y + 300.0, rad_to_deg(atan2(-300.0, 300.0))])
	print("EYE tanks  %.1f,40,%.1f,0,-15" % [r.end.x - 60.0, r.end.y + 60.0])
	get_tree().quit()
