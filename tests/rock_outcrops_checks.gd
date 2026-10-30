extends RefCounted
## The hills' real rock (RockKit, RockOutcrops, RockFar, RockBuild), for tests/smoke_test.gd.
## Loaded at run time, not named there, so it compiles after the autoloads.
##
## The kit: every scan loads with its LODs, the tors' far meshes are a couple of hundred
## triangles, all on the rock shader. The plan: hundreds of tors, all in the hills, off the hill
## roads, the estate pads and the landmarks, mostly where the ground is painted rock or is a crest,
## the same twice and another seed's different. The far node: a near and a far instance for every
## tor, a near cell shown round the camera collapses its tors in the far cells. The chunks: a FULL
## hill chunk claims and collides its tors and lays outcrops on its painted rock, an LOD chunk only
## claims, both release when they go; the old scattered boulders keep their rolls with the rock on
## or off (nothing else in the chunk moves).

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	var plan: CityPlan = city.plan
	_kit()
	if not RockOutcrops.enabled:
		_t._check(true, "rock outcrops are off (ROCKS=0)")
		return
	var tors := RockOutcrops.tors(plan)
	_plan(plan, tors)
	_far(tors)
	_chunks(city, plan, tors)


func _kit() -> void:
	var ok := true
	var note := ""
	for k in RockKit.KINDS.size():
		var m := RockKit.mesh(k)
		var lods := RockKit.lod_triangles(m)
		var mat := m.surface_get_material(0) as ShaderMaterial
		var good := m.get_surface_count() == 1 and (lods.size() == 1) == RockKit.MID_FILES.has(k) and lods[0] >= 2000 and lods[0] <= 10000 \
			and mat != null and mat.shader.resource_path.ends_with("rock_outcrop.gdshader")
		ok = ok and good
		note += "%s %s " % [RockKit.KINDS[k], str(lods)]
	for k: int in RockKit.TOR_KINDS:
		var lods := RockKit.lod_triangles(RockKit.mid_mesh(k))
		ok = ok and lods[0] <= 2000 and lods.size() >= 3 and lods[lods.size() - 1] <= 400
		note += "mid %s " % str(lods)
	_t._check(ok, "the rock kit's tor scans load as one level (boulders with LODs) on the rock shader, the tors' welded meshes carry LODs (%s)" % note)


func _plan(plan: CityPlan, tors: Array) -> void:
	var macro: MacroMap = plan.macro
	var in_hills := 0
	var off_roads := 0
	var on_rock := 0
	var tall := 0.0
	for tr: Dictionary in tors:
		var p: Vector2 = tr.pos
		if macro.zone_at(p) == MacroMap.Zone.HILLS:
			in_hills += 1
		var clear := true
		for seg: Dictionary in macro.hill_roads.segments_in(Rect2(p, Vector2.ZERO).grow(float(tr.radius) + 40.0)):
			var c := Geometry2D.get_closest_point_to_segment(p, seg.a, seg.b)
			if p.distance_to(c) < float(seg.width) * 0.5 + float(tr.radius) + 4.0:
				clear = false
		for m: Dictionary in macro.hill_roads.mansions_in(Rect2(p, Vector2.ZERO).grow(float(tr.radius) + HillRoads.PAD_RADIUS + 10.0)):
			if p.distance_to(m.pos) < HillRoads.PAD_RADIUS + float(tr.radius):
				clear = false
		if clear:
			off_roads += 1
		var e := 12.0
		var grad := Vector2(macro.height_at(p + Vector2(e, 0.0)) - macro.height_at(p - Vector2(e, 0.0)),
			macro.height_at(p + Vector2(0.0, e)) - macro.height_at(p - Vector2(0.0, e))) / (2.0 * e)
		var drain := macro.drainage_at(p)
		var g := HillPlanting.ground(p, grad, false, drain)
		if float(g.rocky) > 0.15 or drain < -0.2:
			on_rock += 1
		tall = maxf(tall, float(tr.top))
	var n := maxi(tors.size(), 1)
	_t._check(tors.size() > 800, "RockOutcrops plans hundreds of tors on the ranges (%d, the tallest standing %.0f m)" % [tors.size(), tall])
	_t._check(in_hills == tors.size() and off_roads == tors.size(),
		"every tor is in the hills (%d of %d) and off the hill roads and estate pads (%d)" % [in_hills, tors.size(), off_roads])
	_t._check(float(on_rock) / n > 0.6, "tors stand where the ground is painted rock or is a crest (%d of %d)" % [on_rock, tors.size()])
	var again := RockOutcrops._plan_tors(plan)
	var same := again.size() == tors.size()
	for i in mini(again.size(), tors.size()):
		same = same and (again[i].pos as Vector2).is_equal_approx(tors[i].pos) and int(again[i].kind) == int(tors[i].kind)
	_t._check(same, "the tors are the same planned twice (hashes of the seed and the place)")


func _far(tors: Array) -> void:
	var f := RockFar.current
	_t._check(f != null and f.is_inside_tree(), "the far rock node is in the city (RockFar)")
	if f == null:
		return
	var slots_ok: bool = (f._slots as Array).size() == tors.size()
	for s: Variant in f._slots:
		slots_ok = slots_ok and s is Array and (f._near as Dictionary).has(s[0]) and (f._far as Dictionary).has(s[2])
	_t._check(slots_ok, "every tor has a near and a far instance (%d near cells, %d far cells)" % [(f._near as Dictionary).size(), (f._far as Dictionary).size()])
	var tr: Dictionary = tors[tors.size() / 2]
	var cell := Vector2i(floori(tr.pos.x / RockFar.NEAR_CELL), floori(tr.pos.y / RockFar.NEAR_CELL))
	var shown_before := f.near_shown(cell)
	f.survey(Vector3(tr.pos.x, 0.0, tr.pos.y))
	var shown := f.near_shown(cell)
	var node := f._near[Vector3i(cell.x, cell.y, int(tr.kind))] as Node3D
	f.survey(Vector3(tr.pos.x + 20000.0, 0.0, tr.pos.y))
	var gone := not f.near_shown(cell) and not node.visible
	var cam := f.get_viewport().get_camera_3d()
	if cam:
		f.survey(WorldState.to_world(cam.global_position))
	_t._check(shown and node.visible and gone, "a near cell shows round the camera and goes past NEAR_RANGE (was %s)" % shown_before)


func _chunks(city: Node3D, plan: CityPlan, tors: Array) -> void:
	var f := RockFar.current
	# The chunk holding the most tors among a sample.
	var counts := {}
	for i in range(0, tors.size(), 7):
		var k := plan.chunk_index_at(tors[i].pos)
		counts[k] = int(counts.get(k, 0)) + 1
	var keys: Array = counts.keys()
	keys.sort_custom(func(x: Vector2i, y: Vector2i) -> bool: return int(counts[x]) > int(counts[y]))
	var best := Vector2i.ZERO
	var chunk: CityChunk = null
	for k: Vector2i in keys.slice(0, 6):
		chunk = city._new_chunk(k, CityChunk.Level.FULL)
		chunk.build()
		best = k
		if chunk.zone == MacroMap.Zone.HILLS and chunk.has_meta("rock_claims"):
			break
		chunk.get_parent().remove_child(chunk)
		chunk.free()
		chunk = null
	if chunk == null:
		_t._check(false, "a FULL hill chunk with tors builds")
		return
	var rocks: Dictionary = chunk.get_meta("rocks", {})
	var body := chunk.get_node_or_null("RockBody") as StaticBody3D
	var ids: Array = chunk.get_meta("rock_claims", [])
	var claimed := not ids.is_empty()
	for id: int in ids:
		claimed = claimed and RockFar.is_claimed(id)
	_t._check(chunk.zone == MacroMap.Zone.HILLS and body != null and body.collision_layer == 1 and body.collision_mask == 0
		and body.get_child_count() == int(rocks.get("tors", -1)) and claimed,
		"a FULL hill chunk %s collides and claims its tors (%d) and lays outcrops (%d), scree (%d), bank boulders (%d)"
		% [best, int(rocks.get("tors", 0)), int(rocks.get("outcrops", 0)), int(rocks.get("scree", 0)), int(rocks.get("bank", 0))])
	chunk.get_parent().remove_child(chunk)
	chunk.free()
	var released := true
	for id: int in ids:
		released = released and not RockFar.is_claimed(id)
	_t._check(released, "the tors go back to the far seat when their chunk goes")
	var lod: CityChunk = city._new_chunk(best, CityChunk.Level.LOD)
	lod.build()
	var lod_ok := lod.get_node_or_null("RockBody") == null and not (lod.get_meta("rock_claims", []) as Array).is_empty()
	lod.get_parent().remove_child(lod)
	lod.free()
	_t._check(lod_ok, "an LOD hill chunk claims its tors but builds no rock collision")
	# Outcrops and bank boulders somewhere: the hill chunks along a few hill roads.
	var outcrops := 0
	var bank := 0
	var tried := 0
	for road: Dictionary in plan.macro.hill_roads.roads:
		if tried >= 4 or not bool(road.get("draw", true)):
			continue
		var pts: PackedVector2Array = road.points
		var k := plan.chunk_index_at(pts[pts.size() / 2])
		if plan.zone_at(pts[pts.size() / 2]) != MacroMap.Zone.HILLS:
			continue
		tried += 1
		var c: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
		c.build()
		var r: Dictionary = c.get_meta("rocks", {})
		outcrops += int(r.get("outcrops", 0))
		bank += int(r.get("bank", 0))
		c.get_parent().remove_child(c)
		c.free()
	_t._check(outcrops + int(rocks.get("outcrops", 0)) > 0 and bank > 0,
		"hill chunks lay outcrops on their painted rock and boulders in the roads' cut banks (%d, %d in %d chunks)" % [outcrops, bank, tried])
	# The old scattered boulders and everything else in the chunk keep their rolls with the rock off.
	var on := _batch_counts(city, best)
	RockOutcrops.enabled = false
	var off := _batch_counts(city, best)
	RockOutcrops.enabled = true
	var same := true
	for key: String in off:
		if int(on.get(key, -1)) != int(off[key]):
			same = false
	for key: String in on:
		if not key.begins_with("rock_k") and not off.has(key):
			same = false
	_t._check(same and on.has("rock_0") == off.has("rock_0"), "the hill chunk's other planting and boulders are the same with the rock off (%d kinds)" % off.size())


func _batch_counts(city: Node3D, k: Vector2i) -> Dictionary:
	var c: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
	c.build()
	var out := {}
	var data: Dictionary = c._batch.data()
	for key: String in data:
		var entry: Variant = data[key]
		out[key] = (entry.xforms as Array).size() if entry is Dictionary and (entry as Dictionary).has("xforms") else 1
	c.get_parent().remove_child(c)
	c.free()
	return out
