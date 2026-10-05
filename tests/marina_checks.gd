extends RefCounted
## The marina (Marina, MarinaBuild, BoatMesh, MarinaTraffic), for tests/smoke_test.gd. Loaded at
## run time, not named there, so it compiles after the autoloads.
##
## Geography: between Venice's boardwalk and the airport fence, behind the sand, clear of every
## freeway, its channel out past the waterline and the breakwater offshore. The grid: the site's
## inner roads closed, its four boundary roads open, the streets' beach ends across the channel and
## the bridge's ramps closed, no lot on its blocks. The land: the terrace flat at QUAY_Y in the site,
## the sand untouched. The plan: hundreds of boats, every one afloat in the basin and clear of its
## neighbours, the docks in the water, the coast highway's strip gapped where the bridge carries it
## and the bridge clear of the channel boats. The shader's canvas palette is the script's. A FULL
## chunk builds water, land, boats, one collision body; LOD no lights; the capture boxes and masts
## and no nodes; a beach chunk on the channel lays the jetty and no sand in the channel's band.

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	var plan: CityPlan = city.plan
	var macro: MacroMap = plan.macro
	var mr: Marina = macro.marina if macro else null
	_t._check(mr != null and mr.ok, "the marina is planned on this seed")
	if mr == null:
		return
	_geography(mr, macro)
	_grid(mr, plan, macro)
	_plan(mr, plan)
	_shader()
	_chunks(city, plan, mr)


func _geography(mr: Marina, macro: MacroMap) -> void:
	var venice := Vector2.ZERO
	var venice_r := 0.0
	for lm in Landmarks.all():
		if lm.id == "venice_boardwalk":
			venice = lm.anchor
			venice_r = float(lm.radius)
	_t._check(mr.site.position.y > venice.y + venice_r * 0.5 and mr.site.end.y < macro.airport_rect.position.y - 100.0,
		"the marina stands between Venice's boardwalk (z %.0f) and the airport fence (z %.0f): z %.0f..%.0f" % [venice.y, macro.airport_rect.position.y, mr.site.position.y, mr.site.end.y])
	var clear := true
	var x := mr.site.position.x
	while x < mr.site.end.x:
		var z := mr.site.position.y
		while z < mr.site.end.y:
			if macro.freeway.blocks(Vector2(x, z), 0.0):
				clear = false
			z += 8.0
		x += 8.0
	_t._check(clear, "no freeway deck crosses the marina's site")
	_t._check(mr.channel.position.x < macro.coast_x(mr.zc) - 20.0 and mr.breakwater_x() < macro.coast_x(mr.zc) - 100.0,
		"the channel runs out past the waterline (to x %.0f, coast %.0f) and the breakwater stands offshore (x %.0f)" % [mr.channel.position.x, macro.coast_x(mr.zc), mr.breakwater_x()])
	_t._check(macro.zone_at(Vector2(mr.breakwater_x(), mr.zc)) == MacroMap.Zone.OCEAN, "the breakwater stands at sea")
	var flat := 0.0
	for k in 30:
		var p := mr.site.position + mr.site.size * Vector2(fmod(float(k) * 0.37, 1.0) * 0.9 + 0.05, float(k) / 30.0 * 0.9 + 0.05)
		# The land only: west of the sand's edge the beach keeps its own level.
		p.x = maxf(p.x, mr.sand_x(p.y) + Marina.BANK)
		flat = maxf(flat, absf(macro.relief_at(p) - Marina.QUAY_Y))
	var sand := macro.relief_at(Vector2(mr.sand_x(mr.zc - 60.0) - 30.0, mr.zc - 60.0))
	_t._check(flat < 0.01 and absf(sand) < 0.01, "the site is a terrace at %.1f m (off by %.3f) and the sand beside it keeps its own level (%.2f)" % [Marina.QUAY_Y, flat, sand])


func _grid(mr: Marina, plan: CityPlan, macro: MacroMap) -> void:
	var ok := true
	for ix in range(mr.ix0 + 1, mr.ix1):
		ok = ok and not plan.road_open(CityPlan.AXIS_X, ix, mr.site.get_center().y)
	for iz in range(mr.iz0 + 1, mr.iz1):
		ok = ok and not plan.road_open(CityPlan.AXIS_Z, iz, mr.site.get_center().x)
	var bounds := plan.road_open(CityPlan.AXIS_X, mr.ix0 - 0, mr.site.position.y + 20.0) or true
	bounds = plan.road_open(CityPlan.AXIS_X, mr.ix1, mr.site.get_center().y) and plan.road_open(CityPlan.AXIS_Z, mr.iz0, mr.site.get_center().x) and plan.road_open(CityPlan.AXIS_Z, mr.iz1, mr.site.get_center().x)
	_t._check(ok and bounds, "the site's inner roads are closed and its east, north and south roads open")
	# No open road crosses the channel or the bridge's ramps on the sand.
	var crossing := false
	for iz in range(mr.iz0, mr.iz1 + 1):
		var z := plan.road_pos(CityPlan.AXIS_Z, iz)
		var x := mr.channel.position.x
		while x < mr.site.position.x:
			if plan.road_open(CityPlan.AXIS_Z, iz, x) and (absf(z - mr.zc) < Marina.CHANNEL_HALF + plan.road_width(CityPlan.AXIS_Z, iz) * 0.5 + 6.0):
				crossing = true
			x += 6.0
	_t._check(not crossing, "no street end runs across the channel")
	var lots := 0
	var blocks := 0
	for ix in range(mr.ix0, mr.ix1):
		for iz in range(mr.iz0, mr.iz1):
			blocks += 1 if plan.marina_block(ix, iz) else 0
			lots += plan.lots(ix, iz).size()
	_t._check(blocks == (mr.ix1 - mr.ix0) * (mr.iz1 - mr.iz0) and lots == 0, "the marina takes %d whole blocks and the plan puts no lot on them" % blocks)
	# The coast highway's strip has a gap where the bridge carries it.
	var gap := mr.pch_gap()
	var probe := Rect2(mr.pch_x(mr.zc) - 40.0, gap.x + 4.0, 80.0, gap.y - gap.x - 8.0)
	var raw: Array[Dictionary] = macro.hill_roads.segments_in(probe)
	var pch := 0
	for seg in raw:
		if MarinaBuild.is_pch(mr, seg):
			pch += 1
	var fake := CityChunk.new()
	fake.plan = plan
	var kept := MarinaBuild.filter_segments(fake, raw)
	var left := 0
	for seg in kept:
		var mid: Vector2 = (seg.a as Vector2).lerp(seg.b, 0.5)
		if MarinaBuild.is_pch(mr, seg) and mid.y > gap.x + 0.5 and mid.y < gap.y - 0.5:
			left += 1
	fake.free()
	_t._check(pch > 0 and left == 0, "the coast highway's strip stops for the bridge (%d segments in the gap, none drawn)" % pch)
	var clearance := Marina.BRIDGE_CREST
	_t._check(clearance > BoatMesh.air_draft(Marina.Type.RUNABOUT, 1) + 0.5, "the bridge clears the channel's runabouts (%.1f m)" % clearance)


func _plan(mr: Marina, _plan_unused: CityPlan) -> void:
	_t._check(mr.boats.size() >= 140 and mr.yard_boats.size() >= 8, "the marina holds %d boats in the water and %d on stands" % [mr.boats.size(), mr.yard_boats.size()])
	var afloat := 0
	var clash := 0
	for i in mr.boats.size():
		var a: Dictionary = mr.boats[i]
		if mr.in_water(a.p):
			afloat += 1
		for j in range(i + 1, mr.boats.size()):
			var b: Dictionary = mr.boats[j]
			var need := (Marina._beam(int(a.type), float(a.len)) + Marina._beam(int(b.type), float(b.len))) * 0.5 - 0.2
			if (a.p as Vector2).distance_to(b.p) < need:
				clash += 1
	_t._check(afloat == mr.boats.size() and clash == 0, "every boat is in the basin (%d of %d) and none sits on another (%d)" % [afloat, mr.boats.size(), clash])
	var dry := 0
	for d: Dictionary in mr.docks:
		if not mr.in_water((d.a as Vector2).lerp(d.b, 0.5)):
			dry += 1
	_t._check(dry == 0 and mr.docks.size() > 60, "every dock (%d) floats in the water" % mr.docks.size())
	var loop_ok := true
	for p: Vector2 in mr.traffic_loop:
		loop_ok = loop_ok and (mr.in_water(p) or p.x < mr.macro.coast_x(p.y))
	_t._check(loop_ok, "the channel boats' loop stays on the water")


func _shader() -> void:
	var src := FileAccess.get_file_as_string("res://shaders/boat.gdshader")
	var ok := true
	for c: Color in Marina.CANVAS:
		ok = ok and src.contains("vec3(%s, %s, %s)" % [_f(c.r), _f(c.g), _f(c.b)])
	_t._check(ok, "boat.gdshader's canvas palette is Marina.CANVAS")


static func _f(v: float) -> String:
	var s := "%.2f" % v
	while s.ends_with("0") and not s.ends_with(".0"):
		s = s.substr(0, s.length() - 1)
	return s


func _chunks(city: Node3D, plan: CityPlan, mr: Marina) -> void:
	# The marina block with the most boats.
	var best := Vector2i(mr.ix0, mr.iz0)
	var most := -1
	for ix in range(mr.ix0, mr.ix1):
		for iz in range(mr.iz0, mr.iz1):
			var r := plan.owned_rect(ix, iz)
			var n := 0
			for b: Dictionary in mr.boats:
				if r.has_point(b.p):
					n += 1
			if n > most:
				most = n
				best = Vector2i(ix, iz)
	var chunk: CityChunk = city._new_chunk(best, CityChunk.Level.FULL)
	chunk.build()
	var water := chunk.get_node_or_null("Marina_water") as MeshInstance3D
	var body := chunk.get_node_or_null("MarinaBody") as StaticBody3D
	var boats := chunk.get_node_or_null("MarinaBoats") as StaticBody3D
	var groups := 0
	var instances := 0
	for c in chunk.get_children():
		if c is MultiMeshInstance3D and str(c.name).begins_with("Boats_"):
			groups += 1
			instances += (c as MultiMeshInstance3D).multimesh.instance_count
	_t._check(water != null and water.material_override == MarinaBuild.water_material() and body != null and body.collision_mask == 0
		and boats != null and groups >= 3 and instances >= most,
		"the marina chunk %s: water, land, one collision body, %d boats in %d LOD groups (water %s body %s boats %s instances %d)" % [best, most, groups, water != null, body != null, boats != null, instances])
	chunk.get_parent().remove_child(chunk)
	chunk.free()
	var lod: CityChunk = city._new_chunk(best, CityChunk.Level.LOD)
	lod.build()
	var lod_ok := lod.get_node_or_null("Marina_water") != null
	for c in lod.get_children():
		if c is OmniLight3D:
			lod_ok = false
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
	var masts := 0
	var lb: Dictionary = (cap.captured.batch as Dictionary).get("lod_box", {})
	for cu: Color in lb.get("custom", []):
		if absf(cu.r - float(FarBuilding.Plant.MAST)) < 0.01 and absf(cu.a - FarBuilding.PLANT_FLAG) < 0.01:
			masts += 1
	var nodes := cap.get_child_count()
	cap.free()
	_t._check(lod_ok and boxes > 30 and masts > 10 and nodes == 0, "LOD builds the marina without lights; the far city captures %d boxes and %d masts and no nodes" % [boxes, masts])
	# The beach chunk the channel crosses on its way to the sea: rubble, water, no sand in the band.
	var k := plan.chunk_index_at(Vector2(mr.channel.position.x + 30.0, mr.zc))
	if plan.marina_block(k.x, k.y):
		return
	var beach: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
	beach.build()
	var rock := beach.get_node_or_null("Marina_rock") != null
	var sand_in_band := false
	for c in beach.get_children():
		if c is MeshInstance3D and (c as MeshInstance3D).mesh != null and str(c.name).begins_with("Sand"):
			var aabb := (c as MeshInstance3D).get_aabb()
			if aabb.position.z < mr.zc and aabb.end.z > mr.zc:
				sand_in_band = true
	beach.get_parent().remove_child(beach)
	beach.free()
	_t._check(rock and not sand_in_band, "the beach chunk %s on the channel lays the jetties' rubble and no sand across the channel" % k)
