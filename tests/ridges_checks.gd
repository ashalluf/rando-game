extends RefCounted
## What stands on the hills (Ridges, RidgeKit, RidgeBuild, RidgeSystem), for tests/smoke_test.gd.
## Loaded at run time, not named there, so it compiles after the autoloads.
##
## The plan: an antenna farm of masts on its benches, fire roads carved into the hills with gates,
## water tanks, a lookout and domes, a substation on its industrial block and two lines of towers
## out of it. The lines: every span's six conductors stay over the ground, the towers stand on
## their feet (leg extensions within the limit), in the hills off the roads and estates, in the city
## inside an industrial block and off the streets, the freeway and the river; no lot is left under
## the substation or the right of way. The carving: the fire roads' beds and the pads are where
## the ground is, and nothing planned before the ridges moved (the hill roads, the estates, the lots
## of a block the line does not take - checked against the same seed planned with RIDGES=0). The
## build: a FULL chunk with a tower builds it with collision and hides its far version, an LOD
## chunk builds no tower, the far node holds the wires and the red lights.

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	var plan: CityPlan = city.plan
	var r := Ridges.of(plan)
	_t._check(r != null, "the ridges are planned (Ridges.of)")
	if r == null:
		return
	_plan(r, plan)
	_lines(r, plan)
	_carving(r, plan)
	_unmoved(r, plan)
	_chunks(r, city, plan)
	_far(city)


func _plan(r: Ridges, plan: CityPlan) -> void:
	var km := 0.0
	for ri: int in r.fire_roads:
		var pts: PackedVector2Array = plan.macro.hill_roads.roads[ri].points
		for i in range(1, pts.size()):
			km += pts[i].distance_to(pts[i - 1]) / 1000.0
	var tanks := 0
	var domes := 0
	var lookouts := 0
	for s: Dictionary in r.sites:
		tanks += 1 if s.kind == Ridges.Site.TANK else 0
		domes += 1 if s.kind == Ridges.Site.DOME else 0
		lookouts += 1 if s.kind == Ridges.Site.LOOKOUT else 0
	var tall := 0.0
	for m: Dictionary in r.masts:
		tall = maxf(tall, float(m.h))
	_t._check(not r.farm.is_empty() and r.masts.size() >= 4 and tall > 120.0,
		"the antenna farm stands on a front-range summit: %d masts, the tallest %.0f m" % [r.masts.size(), tall])
	_t._check(km > 1.5 and r.gates.size() >= 1 and tanks >= 2 and lookouts == 1 and domes >= 1,
		"fire roads (%.1f km, %d gates), %d water tanks, a lookout and %d domes" % [km, r.gates.size(), tanks, domes])
	var ok := r.lines.size() == 2 and not r.substation.is_empty()
	for line: Dictionary in r.lines:
		ok = ok and (line.towers as Array).size() >= 8
	_t._check(ok, "a substation and two lines out of it (%s towers)" % [str(r.lines.map(func(l: Dictionary) -> int: return (l.towers as Array).size()))])


func _lines(r: Ridges, plan: CityPlan) -> void:
	var worst := INF
	var low_spans := 0
	var spans := 0
	for line: Dictionary in r.lines:
		for k in (line.towers as Array).size():
			var ends: Array = r.span_ends(line, k)
			var lo := INF
			for ph in 6:
				for q in Ridges.wire(ends[0][ph], ends[1][ph], 24):
					lo = minf(lo, q.y - r._ground_exact(Vector2(q.x, q.z)))
			worst = minf(worst, lo)
			spans += 1
			low_spans += 1 if lo < Ridges.CLEAR - 2.0 else 0
	_t._check(worst > 0.5 and low_spans * 6 <= spans, "every span's six conductors stay over the ground (lowest %.1f m; %d of %d spans under %.0f m)" % [worst, low_spans, spans, Ridges.CLEAR - 2.0])
	var bad: Array[String] = []
	for t: Dictionary in r.towers:
		var p: Vector2 = t.pos
		var lo := minf(minf(t.legs[0], t.legs[1]), minf(t.legs[2], t.legs[3]))
		if float(t.base) - lo > Ridges.MAX_LEG_EXT + 2.0:
			bad.append("t%d legs %.1f" % [t.id, float(t.base) - lo])
		if plan.macro.freeway and plan.macro.freeway.blocks(p, 15.0):
			bad.append("t%d freeway" % t.id)
		if plan.macro.river and plan.macro.river.in_corridor(p, 5.0):
			bad.append("t%d river" % t.id)
		var zone := plan.zone_at(p)
		if zone == MacroMap.Zone.CITY:
			var k := plan.block_index_at(p)
			var b := plan.block(k.x, k.y)
			if not (b.rect as Rect2).grow(-plan.sidewalk_width).has_point(p) or int(b.district) != CityPlan.District.INDUSTRIAL:
				bad.append("t%d street" % t.id)
		elif zone == MacroMap.Zone.HILLS:
			for m: Dictionary in plan.macro.hill_roads.mansions:
				if p.distance_to(m.pos) < 40.0:
					bad.append("t%d estate" % t.id)
		else:
			bad.append("t%d zone %d" % [t.id, zone])
	_t._check(bad.is_empty(), "every tower stands on its feet, off the streets, roads, estates, freeway and river %s" % [str(bad.slice(0, 6))])
	# No lot under the substation or the right of way.
	var under := 0
	var sub_rect: Rect2 = r.substation.rect
	for k: Vector2i in r.claimed_cells.keys() + [r.substation.block]:
		for lot: Dictionary in plan.lots(k.x, k.y):
			var lr := Rect2((lot.center as Vector2) - (lot.size as Vector2) * 0.5, lot.size)
			if lr.intersects(sub_rect):
				under += 1
			for seg: Array in r.row_in(lr):
				if Ridges._rect_seg_distance(lr, seg[0], seg[1]) < Ridges.ROW_HALF - 0.5:
					under += 1
	_t._check(under == 0 and r.claimed_cells.size() > 0, "no lot left under the substation or the right of way (%d blocks give lots up)" % r.claimed_cells.size())


func _carving(r: Ridges, plan: CityPlan) -> void:
	var off := 0.0
	var n := 0
	for ri: int in r.fire_roads:
		var road: Dictionary = plan.macro.hill_roads.roads[ri]
		var pts: PackedVector2Array = road.points
		var hs: PackedFloat32Array = road.heights
		for i in range(2, pts.size() - 2, 3):
			off = maxf(off, absf(plan.height_at(pts[i]) - hs[i]))
			n += 1
	var pads := 0.0
	for road: Dictionary in plan.macro.hill_roads.roads:
		if road.get("pad", false):
			var c := ((road.points as PackedVector2Array)[0] + (road.points as PackedVector2Array)[1]) * 0.5
			pads = maxf(pads, absf(plan.height_at(c) - float(road.heights[0])))
	_t._check(n > 20 and off < 0.25 and pads < 0.05, "the fire roads (%d points, worst %.2f m) and the pads (%.3f m) are carved into the hills" % [n, off, pads])


## The same seed planned without the ridges: every hill road, estate and the lots of a block the
## line does not take are the same; the ground away from the ridges' carving is the same.
func _unmoved(r: Ridges, plan: CityPlan) -> void:
	OS.set_environment("RIDGES", "0")
	var m2 := MacroMap.new()
	m2.seed = plan.seed
	m2.setup()
	OS.set_environment("RIDGES", "")
	var p2 := CityPlan.new()
	p2.seed = plan.seed
	p2.macro = m2
	var hr: HillRoads = plan.macro.hill_roads
	var same := m2.ridges == null and hr.roads.size() == m2.hill_roads.roads.size() + r.fire_roads.size() + _pad_count(hr) \
		and hr.mansions.size() == m2.hill_roads.mansions.size()
	for i in m2.hill_roads.roads.size():
		same = same and (hr.roads[i].points as PackedVector2Array) == (m2.hill_roads.roads[i].points as PackedVector2Array)
	for i in m2.hill_roads.mansions.size():
		same = same and (hr.mansions[i].pos as Vector2) == (m2.hill_roads.mansions[i].pos as Vector2)
	_t._check(same, "the hill roads and estates are the ones planned without the ridges (%d roads, %d estates)" % [m2.hill_roads.roads.size(), m2.hill_roads.mansions.size()])
	# Lots of blocks round the substation that the line does not take.
	var lots_same := true
	var checked := 0
	var sb: Vector2i = r.substation.block
	for dj in range(-3, 4):
		for di in range(-3, 4):
			var k := sb + Vector2i(di, dj)
			if r.claimed_cells.has(k) or k == sb:
				continue
			var a := plan.lots(k.x, k.y)
			var b := p2.lots(k.x, k.y)
			checked += 1
			lots_same = lots_same and a.size() == b.size()
			for i in mini(a.size(), b.size()):
				lots_same = lots_same and int(a[i].seed) == int(b[i].seed)
	# And blocks that gave lots up kept the rest, roll for roll.
	for k: Vector2i in r.claimed_cells:
		var a := plan.lots(k.x, k.y)
		var b := p2.lots(k.x, k.y)
		var seeds := {}
		for lot: Dictionary in b:
			seeds[int(lot.seed)] = true
		for lot: Dictionary in a:
			lots_same = lots_same and seeds.has(int(lot.seed))
	_t._check(lots_same and checked > 10, "the lots round the substation (%d blocks) roll as they did, and the blocks that gave lots up keep the rest" % checked)
	# Ground away from the carving.
	var diff := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var tried := 0
	while tried < 200:
		var q := Vector2(rng.randf_range(-1200.0, 7000.0), rng.randf_range(-3500.0, 5000.0))
		if plan.zone_at(q) != MacroMap.Zone.HILLS:
			continue
		tried += 1
		if not r._free(q, 60.0):
			continue
		diff = maxf(diff, absf(plan.height_at(q) - m2.height_at(q)))
	_t._check(diff < 0.01, "the hills away from the ridges' carving are the same ground (%.3f m)" % diff)


func _pad_count(hr: HillRoads) -> int:
	var n := 0
	for road: Dictionary in hr.roads:
		n += 1 if road.get("pad", false) else 0
	return n


func _chunks(r: Ridges, city: Node3D, plan: CityPlan) -> void:
	# A tower in the hills.
	var t: Dictionary = {}
	for tw: Dictionary in r.towers:
		if plan.zone_at(tw.pos) == MacroMap.Zone.HILLS:
			t = tw
			break
	var k := plan.chunk_index_at(t.pos)
	var before := RidgeSystem.covered.size()
	var chunk: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
	chunk.build()
	var body := chunk.get_node_or_null("RidgeBody") as StaticBody3D
	var tower := chunk.get_node_or_null("Tower%d" % int(t.id)) as MeshInstance3D
	var shapes := body.get_child_count() if body else 0
	var tris := 0
	if tower:
		for s in tower.mesh.get_surface_count():
			tris += (tower.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	var covered := RidgeSystem.covered.has(r.far_id("tower", int(t.id)))
	_t._check(tower != null and body != null and body.collision_layer == 1 and body.collision_mask == 0 and shapes >= 8
		and tris > 2000 and tris < 14000 and covered,
		"a FULL hill chunk builds its tower t%d (%d triangles, %d collision shapes) and hides its far lines" % [int(t.id), tris, shapes])
	chunk.get_parent().remove_child(chunk)
	chunk.free()
	_t._check(RidgeSystem.covered.size() == before, "the far tower comes back when its chunk goes")
	var lod: CityChunk = city._new_chunk(k, CityChunk.Level.LOD)
	lod.build()
	var lod_ok := lod.get_node_or_null("Tower%d" % int(t.id)) == null and lod.get_node_or_null("RidgeBody") == null
	lod.get_parent().remove_child(lod)
	lod.free()
	_t._check(lod_ok, "an LOD chunk builds no tower and no collision (the far lines stand in)")
	# The farm's tallest mast, and the substation.
	var big: Dictionary = r.masts[0]
	var mk := plan.chunk_index_at(big.pos)
	var mc: CityChunk = city._new_chunk(mk, CityChunk.Level.FULL)
	mc.build()
	var mast_ok := mc.get_node_or_null("Mast_%s" % big.id) != null and mc.get_node_or_null("FireRoads") != null
	mc.get_parent().remove_child(mc)
	mc.free()
	_t._check(mast_ok, "the antenna farm's chunk builds the tallest mast and the dirt of its benches")
	var sk := plan.chunk_index_at((r.substation.rect as Rect2).get_center())
	var sc: CityChunk = city._new_chunk(sk, CityChunk.Level.FULL)
	sc.build()
	var sub_ok := sc.get_node_or_null("Substation") != null and sc.get_node_or_null("RidgeBody") != null
	var buildings := 0
	for c in sc.get_children():
		if c is Building and (r.substation.rect as Rect2).grow(-2.0).has_point(Vector2(c.position.x, c.position.z)):
			buildings += 1
	sc.get_parent().remove_child(sc)
	sc.free()
	_t._check(sub_ok and buildings == 0, "the substation's chunk builds the yard and no building in it")


func _far(city: Node3D) -> void:
	var sys := city.get_node_or_null("Ridges") as RidgeSystem
	var ok := sys != null and sys.wires != null and sys.lights != null
	var verts := 0
	var lights := 0
	if ok:
		verts = (sys.wires.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		lights = (sys.lights.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 6
	_t._check(ok and verts > 20000 and lights >= 6 and sys.wires.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
		"the far node holds every wire and lattice line (%d vertices, one draw) and the masts' red lights (%d)" % [verts, lights])
