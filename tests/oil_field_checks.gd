extends RefCounted
## The oil field (OilField, OilFieldBuild, OilKit), for tests/smoke_test.gd. Loaded at run time,
## not named there, so it compiles after the autoloads.
##
## The site: on city ground in midtown, clear of the freeways, the airport and its approach, the
## same rect CityPlan snaps; its interior streets closed, its edges open. The hill: it rises, it
## meets the city's relief at the kerb, its pads are level and its lease roads hold their grade on
## their own bed. The layout: dozens of wells, the rigs, batteries and gates, pads inside the fence
## and apart, all pure. The pumpjack: the shader's paint table is OilKit's, its pitman keeps its
## length through the stroke, its mesh tags only known parts. The chunks: a FULL one builds the
## ground (terrain material, collision), the dirt, the hardware and its pumpjacks and no buildings;
## LOD the far pumpjacks without the hardware; the capture boxes and no nodes; the lights mesh.
## The city's single wells: in industrial lots and between houses, pure, away from the field, and a
## FULL chunk that holds one builds its fence and its pumpjack.

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	var plan: CityPlan = city.plan
	var macro: MacroMap = plan.macro
	var f: OilField = macro.oil if macro else null
	_t._check(f != null and OilField.enabled, "the oil field is built")
	if f == null:
		return
	_site(f, plan, macro)
	_hill(f, macro)
	_layout(f, macro)
	_pumpjack()
	_chunks(city, plan, f)
	_lots(city, plan, f)


func _site(f: OilField, plan: CityPlan, macro: MacroMap) -> void:
	var site := plan.site_by_id(OilField.ID)
	var c := f.rect.get_center()
	_t._check(not site.is_empty() and (site.rect as Rect2).is_equal_approx(f.rect)
		and macro.zone_at(c) == MacroMap.Zone.CITY and plan.district_at(c) == CityPlan.District.MIDTOWN,
		"the oil field's site is CityPlan's snapped rect, on city ground in midtown (%s)" % f.rect)
	_t._check(not macro.freeway.blocks_rect(f.rect, 8.0) and not f.rect.intersects(macro.airport_rect.grow(200.0))
		and not f.rect.intersects(macro.runway_clear_zone()), "the field keeps clear of the freeways, the airport and the runway's approach")
	# Streets through it closed; its edges open.
	var mid_z := c.y
	var inner_x := f.ix0 + 1
	var open_inside := plan.road_open(CityPlan.AXIS_X, inner_x, mid_z)
	var edge_open := plan.road_open(CityPlan.AXIS_X, f.ix0, mid_z) and plan.road_open(CityPlan.AXIS_X, f.ix1, mid_z)
	var blocks := 0
	for ix in range(f.ix0, f.ix1):
		for iz in range(f.iz0, f.iz1):
			if plan.block(ix, iz).get("site", "") == OilField.ID and plan.lots(ix, iz).is_empty():
				blocks += 1
	_t._check(not open_inside and edge_open and blocks == (f.ix1 - f.ix0) * (f.iz1 - f.iz0),
		"the streets through the field are closed, its edges open, its %d blocks the site's with no lots" % blocks)


func _hill(f: OilField, macro: MacroMap) -> void:
	var top := -INF
	for i in 30:
		for j in 30:
			var p := f.rect.position + f.rect.size * Vector2((i + 0.5) / 30.0, (j + 0.5) / 30.0)
			top = maxf(top, macro.relief_at(p))
	var seam := 0.0
	for k in 40:
		var t := float(k) / 40.0
		for p: Vector2 in [Vector2(lerpf(f.rect.position.x, f.rect.end.x, t), f.rect.position.y + 0.01), Vector2(f.rect.end.x - 0.01, lerpf(f.rect.position.y, f.rect.end.y, t))]:
			seam = maxf(seam, absf(macro.relief_at(p) - macro._relief_natural(p, macro.raw_height_at(p))))
	_t._check(top > f.base_h + OilField.PEAK * 0.75 and seam < 0.05,
		"the hill rises %.1f m over its base and meets the city's relief at the kerb (%.3f m)" % [top - f.base_h, seam])
	var pad_err := 0.0
	for pd: Dictionary in f.pads:
		var c: Vector2 = pd.c
		for k in 8:
			var a := TAU * float(k) / 8.0
			var p := c + (pd.dir as Vector2) * cos(a) * (float(pd.hx) - 3.0) + (pd.out as Vector2) * sin(a) * (float(pd.hz) - 3.0)
			pad_err = maxf(pad_err, absf(macro.relief_at(p) - float(pd.h)))
		pad_err = maxf(pad_err, absf(macro.relief_at(c) - float(pd.h)))
	var grade := 0.0
	var bed := 0.0
	for rd: Dictionary in f.roads:
		var pts: PackedVector2Array = rd.pts
		var hs: PackedFloat32Array = rd.h
		for i in pts.size() - 1:
			grade = maxf(grade, absf(hs[i + 1] - hs[i]) / maxf(pts[i].distance_to(pts[i + 1]), 0.01))
			var m := (pts[i] + pts[i + 1]) * 0.5
			var e := minf(minf(m.x - f.rect.position.x, f.rect.end.x - m.x), minf(m.y - f.rect.position.y, f.rect.end.y - m.y))
			if e < OilField.EDGE_BLEND + 2.0 or _near_pad(f, m, 1.0):
				continue
			bed = maxf(bed, absf(macro.relief_at(m) - (hs[i] + hs[i + 1]) * 0.5))
	_t._check(pad_err < 0.2 and grade <= OilField.MAX_GRADE + 0.002 and bed < 0.35,
		"the pads are level (%.3f m), the lease roads hold %.1f %% at most and lie on their own bed (%.2f m)" % [pad_err, grade * 100.0, bed])


func _near_pad(f: OilField, p: Vector2, pad: float) -> bool:
	for pd: Dictionary in f.pads:
		if OilField.pad_dist(pd, p) < OilField.PAD_BANK + pad:
			return true
	return false


func _layout(f: OilField, macro: MacroMap) -> void:
	var kinds := [0, 0, 0]
	for pd: Dictionary in f.pads:
		kinds[int(pd.kind)] += 1
	var fence := f.rect.grow(-OilField.FENCE_IN)
	var apart := true
	var inside := true
	for i in f.pads.size():
		var a: Dictionary = f.pads[i]
		for k in 4:
			var corner: Vector2 = (a.c as Vector2) + (a.dir as Vector2) * float(a.hx) * (1.0 if k % 2 == 0 else -1.0) + (a.out as Vector2) * float(a.hz) * (1.0 if k < 2 else -1.0)
			inside = inside and fence.has_point(corner)
		for j in range(i + 1, f.pads.size()):
			var b: Dictionary = f.pads[j]
			apart = apart and (a.c as Vector2).distance_to(b.c) >= float(a.r) + float(b.r) + 3.9
	_t._check(f.wells().size() >= 40 and kinds[OilField.Pad.RIG] == OilField.RIGS and kinds[OilField.Pad.BATTERY] >= 3 and f.gates.size() == 3 and apart and inside,
		"the field holds %d pumpjacks on %d pads, %d tank batteries, %d rigs and %d gates, every pad inside the fence and apart" % [f.wells().size(), kinds[0], kinds[1], kinds[2], f.gates.size()])
	var again := OilField.make(macro, f.seed)
	var same := again != null and again.pads.size() == f.pads.size() and again.roads.size() == f.roads.size()
	if same:
		for i in f.pads.size():
			same = same and (again.pads[i].c as Vector2).is_equal_approx(f.pads[i].c) and int(again.pads[i].kind) == int(f.pads[i].kind)
	_t._check(same, "the field's plan is pure (made again from the seed, the same pads and roads)")


func _pumpjack() -> void:
	var src := FileAccess.get_file_as_string("res://shaders/pumpjack.gdshader")
	var table_ok := true
	for c: Color in OilKit.PAINTS:
		table_ok = table_ok and src.contains("vec3(%.2f, %.2f, %.2f)" % [c.r, c.g, c.b])
	# The pitman's length through a turn of the crank: the beam follows the wrist pin.
	var lo := INF
	var hi := -INF
	for k in 36:
		var phi := TAU * float(k) / 36.0
		var beam := OilKit.beam_angle(phi)
		var pin := OilKit.CRANK + OilKit.CRANK_R * Vector2(cos(phi), sin(phi))
		var tail := OilKit.PIVOT + Vector2(-OilKit.TAIL, 0.0).rotated(beam)
		var l := pin.distance_to(tail)
		lo = minf(lo, l)
		hi = maxf(hi, l)
	var stroke := 2.0 * OilKit.FRONT * OilKit.beam_angle(-PI * 0.5)
	_t._check(table_ok and hi - lo < 0.3 and stroke > 2.0 and stroke < 4.4,
		"the pumpjack shader's paints are OilKit's, its pitman keeps its length to %.2f m and the rod strokes %.2f m" % [hi - lo, stroke])
	var near := OilKit.pumpjack(false)
	var far := OilKit.pumpjack(true)
	var tags_ok := true
	var arr := near.surface_get_arrays(0)
	var uv2: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV2]
	for v in uv2:
		tags_ok = tags_ok and v.x >= -0.01 and v.x <= 5.01 and v.y >= -0.01 and v.y <= 1.01
	var tn := near.surface_get_array_len(0) / 3
	var tf := far.surface_get_array_len(0) / 3
	_t._check(tags_ok and tn > 1200 and tn < 5000 and tf < 400 and near.custom_aabb.size.y > 9.0,
		"the pumpjack mesh: %d triangles near, %d far, every vertex tagged with a known part, bounds for the whole stroke" % [tn, tf])


func _chunks(city: Node3D, plan: CityPlan, f: OilField) -> void:
	# The chunk with the most wells, and one with a rig.
	var best := Vector2i(9999, 9999)
	var best_n := 0
	var rig := Vector2i(9999, 9999)
	for ix in range(f.ix0 - 1, f.ix1 + 1):
		for iz in range(f.iz0 - 1, f.iz1 + 1):
			var r := plan.owned_rect(ix, iz)
			var n := 0
			for pd: Dictionary in f.pads:
				if r.has_point(pd.c):
					n += (pd.wells as Array).size()
					if int(pd.kind) == OilField.Pad.RIG:
						rig = Vector2i(ix, iz)
			if n > best_n:
				best_n = n
				best = Vector2i(ix, iz)
	if best_n == 0:
		_t._check(false, "a field chunk holds wells")
		return
	var chunk: CityChunk = city._new_chunk(best, CityChunk.Level.FULL)
	chunk.build()
	var ground := chunk.get_node_or_null("OilGround") as MeshInstance3D
	var body := chunk.get_node_or_null("OilGroundBody") as StaticBody3D
	var dirt := chunk.get_node_or_null("OilDirt") as MeshInstance3D
	var walls := chunk.get_node_or_null("OilWalls") as MeshInstance3D
	var jacks := chunk.get_node_or_null("Batch_pumpjack") as MultiMeshInstance3D
	var buildings := 0
	for c in chunk.get_children():
		if c is Building:
			buildings += 1
	_t._check(ground != null and ground.mesh.surface_get_material(0) == PropFactory.terrain_material() and body != null
		and body.collision_layer & CityChunk.TERRAIN_LAYER != 0 and body.collision_mask == 0 and dirt != null
		and dirt.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF and walls != null
		and jacks != null and jacks.multimesh.instance_count == best_n and jacks.multimesh.mesh == OilKit.pumpjack(false) and buildings == 0,
		"field chunk %s: the hill's ground with its collision, the dirt, the hardware, %d pumpjacks and no buildings" % [best, best_n])
	chunk.get_parent().remove_child(chunk)
	chunk.free()
	if rig != Vector2i(9999, 9999):
		var rc: CityChunk = city._new_chunk(rig, CityChunk.Level.FULL)
		rc.build()
		var rw := rc.get_node_or_null("OilWalls") as MeshInstance3D
		var tris := rw.mesh.surface_get_array_len(0) / 3 if rw else 0
		_t._check(rw != null and tris > 3000 and rc.get_node_or_null("Batch_oil_pool") != null,
			"the rig's chunk %s: mast, substructure and racks in the one hardware mesh (%d triangles), light pools" % [rig, tris])
		rc.get_parent().remove_child(rc)
		rc.free()
	var lod: CityChunk = city._new_chunk(best, CityChunk.Level.LOD)
	lod.build()
	var lj := lod.get_node_or_null("Batch_pumpjack") as MultiMeshInstance3D
	var lod_ok := lj != null and lj.multimesh.mesh == OilKit.pumpjack(true) and lod.get_node_or_null("OilGround") != null
	lod.get_parent().remove_child(lod)
	lod.free()
	var cap := CityChunk.new()
	cap.plan = plan
	cap.ix = best.x
	cap.iz = best.y
	cap.level = CityChunk.Level.LOD
	cap.capturing = true
	cap.style = city.chunk_style()
	cap.build()
	var boxes: int = (cap.captured.boxes as Array).size()
	var nodes := cap.get_child_count()
	cap.free()
	var lights := OilFieldBuild.lights_mesh(plan.macro)
	var nl := lights.surface_get_array_len(0) / 6 if lights else 0
	_t._check(lod_ok and boxes > 20 and nodes == 0 and nl > 20,
		"LOD keeps the nodding far pumpjacks; the far city captures %d boxes and no nodes; %d field lights" % [boxes, nl])


func _lots(city: Node3D, plan: CityPlan, f: OilField) -> void:
	var by := {}
	var pure := true
	var near_field := false
	var industrial := Vector2i(9999, 9999)
	for ix in range(-30, 30):
		for iz in range(-20, 60):
			var b := plan.block(ix, iz)
			for lot: Dictionary in plan.lots(ix, iz):
				var w := OilField.lot_well(plan, lot, int(b.district))
				if w.is_empty():
					continue
				by[int(b.district)] = int(by.get(int(b.district), 0)) + 1
				pure = pure and (OilField.lot_well(plan, lot, int(b.district)).p as Vector2).is_equal_approx(w.p)
				near_field = near_field or f.rect.grow(300.0).has_point(lot.center)
				if int(b.district) == CityPlan.District.INDUSTRIAL and industrial == Vector2i(9999, 9999):
					industrial = Vector2i(ix, iz)
	_t._check(int(by.get(CityPlan.District.INDUSTRIAL, 0)) > 3 and int(by.get(CityPlan.District.SUBURBS, 0)) > 3 and pure and not near_field,
		"single wells hide in the city: %d industrial lots, %d between houses, pure, none by the field" % [int(by.get(CityPlan.District.INDUSTRIAL, 0)), int(by.get(CityPlan.District.SUBURBS, 0))])
	if industrial == Vector2i(9999, 9999):
		return
	var k := plan.chunk_index_at((plan.block(industrial.x, industrial.y).rect as Rect2).get_center())
	var chunk: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
	chunk.build()
	var jacks := chunk.get_node_or_null("Batch_pumpjack") as MultiMeshInstance3D
	_t._check(jacks != null and chunk.get_node_or_null("OilLotWalls") != null and chunk.get_node_or_null("OilLotGravel") != null,
		"an industrial chunk %s builds its well site: gravel, fence and pumpjack" % k)
	chunk.get_parent().remove_child(chunk)
	chunk.free()
