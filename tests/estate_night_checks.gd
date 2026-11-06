extends RefCounted
## The hillside estates past the FULL chunks (EstateFar, shaders/far_estate.gdshader), for
## tests/smoke_test.gd. Loaded at run time, not named there, so it compiles after the autoloads.
##
## The parts are pure and laid on HillHomeKit's plan: the same estate gives the same parts; one
## garden pad, no house of their own (HillHomeKit draws it), the pool glow on the plan's pool, the
## gate's and the door's lamps and garden lights; everything but the lamps on the pad's frame; every
## code survives the half floats the Compatibility renderer hands INSTANCE_CUSTOM over as. The
## shader seats a far part as far_canopy seats a far house (the same plane_height(), the same
## sink). A LOD hill chunk lays them as one shadowless batch beside HillHomeKit's boxes, and a
## far-city tile lays them on their own node beside HillHomeKit's houses (still on far_canopy),
## with the plan's trees in the planting.

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	var plan: CityPlan = city.plan
	var macro: MacroMap = plan.macro
	_t._check(EstateFar.enabled, "the far estates are on (ESTATE_NIGHT is not 0)")
	if macro == null or macro.hill_roads == null or macro.hill_roads.mansions.is_empty():
		_t._check(false, "the plan has hill estates to check")
		return
	# An estate a hill chunk builds (one whose block is not a hill block is never built).
	var m: Dictionary = {}
	for e: Dictionary in macro.hill_roads.mansions:
		var k := plan.block_index_at(e.pos)
		if plan.zone_at((plan.block(k.x, k.y).rect as Rect2).get_center()) == MacroMap.Zone.HILLS:
			m = e
			break
	_t._check(not m.is_empty(), "a hill chunk builds an estate to check")
	if m.is_empty():
		return
	_parts(plan, macro)
	_shader()
	_lod_chunk(city, plan, m)
	_far_tile(city, plan, macro, m)


## Half-float rounding (11 significant bits), as Compatibility stores INSTANCE_CUSTOM.
static func _half(v: float) -> float:
	if v == 0.0:
		return 0.0
	var e := floorf(log(absf(v)) / log(2.0))
	var q := pow(2.0, e - 10.0)
	return roundf(v / q) * q


func _parts(plan: CityPlan, macro: MacroMap) -> void:
	var same := true
	var whole := true
	var inside := true
	var codes := true
	var pool_ok := true
	var lamps_min := 1000
	var n := 0
	for m: Dictionary in macro.hill_roads.mansions.slice(0, 60):
		var a := EstateFar.parts(plan, m, false)
		var b := EstateFar.parts(plan, m, false)
		same = same and str(a) == str(b)
		var kinds := {}
		var lamps := 0
		var h: Dictionary = HillHomeKit.plan_home(plan, m) if HillHomeKit.enabled else {}
		for p: Array in a:
			var c: Color = p[2]
			var kind := int(floor(c.g + 0.002))
			kinds[kind] = kinds.get(kind, 0) + 1
			# Survives half floats: the kind, the seat height and the offsets.
			codes = codes and int(floor(_half(c.g) + 0.002)) == kind and absf(_half(c.b) - c.b) < 0.02 \
				and absf(_half(c.a) - c.a) < 0.02 and absf(_half(c.r) - c.r) < 0.02
			if kind == EstateFar.K_LAMP:
				lamps += 1
				continue
			if not h.is_empty():
				var o: Vector3 = (p[0] as Transform3D).origin
				var q := Vector2(o.x, o.z) - (h.o as Vector2)
				var u := q.dot(h.fu)
				var v := q.dot(h.fv)
				inside = inside and u > -1.0 and u < float(h.Wp) + 1.0 and v > -1.0 and v < float(h.Dp) + 1.0
		if HillHomeKit.enabled:
			var has_pool := not (h.pool as Dictionary).is_empty()
			whole = whole and kinds.get(EstateFar.K_PAD, 0) == 1 and kinds.get(EstateFar.K_HOUSE, 0) == 0 \
				and kinds.get(EstateFar.K_ROOF, 0) == 0 and kinds.get(EstateFar.K_POOL, 0) == (1 if has_pool else 0)
			if has_pool:
				var pc := HillHomeKit.frame_point(h, ((h.pool as Dictionary).r as Rect2).get_center())
				for p: Array in a:
					if int(floor((p[2] as Color).g + 0.002)) == EstateFar.K_POOL:
						var o2: Vector3 = (p[0] as Transform3D).origin
						pool_ok = pool_ok and Vector2(o2.x, o2.z).distance_to(pc) < 0.01
		else:
			whole = whole and kinds.get(EstateFar.K_PAD, 0) == 1 and kinds.get(EstateFar.K_HOUSE, 0) >= 1 and kinds.get(EstateFar.K_POOL, 0) == 1
		lamps_min = mini(lamps_min, lamps)
		n += 1
	_t._check(same, "an estate's far parts are the same every time (%d estates)" % n)
	_t._check(whole, "every far estate has one garden pad, the plan's pool glow and no house of its own beside HillHomeKit's")
	_t._check(lamps_min >= 2, "every far estate has its lamps, the gate's at least (fewest %d)" % lamps_min)
	_t._check(inside, "every far estate's parts but its lamps lie on the plan's pad")
	_t._check(pool_ok, "the far pool glow is on the plan's pool")
	_t._check(codes, "the far estates' codes survive half floats (kind, seat height, offsets)")
	var real := EstateFar.parts(plan, macro.hill_roads.mansions[0], true)
	_t._check(int(floor((real[0][2] as Color).g + 0.002)) == EstateFar.K_PAD + EstateFar.REAL, "a LOD chunk's parts are flagged to stay on the real terrain")


## The shader's plane_height() and corner_height() are far_canopy.gdshader's, character for
## character, and its seat sinks a part as far as far_canopy sinks a far house.
func _shader() -> void:
	var mine := FileAccess.get_file_as_string("res://shaders/far_estate.gdshader")
	var theirs := FileAccess.get_file_as_string("res://shaders/far_canopy.gdshader")
	var ok := true
	for fn in ["float corner_height(", "float plane_height("]:
		ok = ok and _body(mine, fn) != "" and _body(mine, fn) == _body(theirs, fn)
	ok = ok and theirs.contains("- 0.8) * (1.0 - real)") and mine.contains("uniform float seat_sink = %.1f;" % EstateFar.FAR_SINK)
	_t._check(ok, "far_estate.gdshader seats on the far plane exactly as far_canopy.gdshader does (plane, sink)")


static func _body(src: String, head: String) -> String:
	var i := src.find(head)
	if i < 0:
		return ""
	var j := src.find("\n}\n", i)
	return src.substr(i, j - i)


func _lod_chunk(city: Node3D, plan: CityPlan, m: Dictionary) -> void:
	var k := plan.block_index_at(m.pos)
	var chunk: CityChunk = city._new_chunk(k, CityChunk.Level.LOD)
	chunk.build()
	var batch := chunk.get_node_or_null("Batch_estate_far") as MultiMeshInstance3D
	var count := 0
	for e in plan.macro.hill_roads.mansions_in(chunk.owned_rect()):
		count += EstateFar.parts(plan, e, true).size()
	var ok := batch != null and batch.multimesh.instance_count == count and (batch.multimesh.mesh as Mesh).surface_get_material(0) == EstateFar.material() \
		and batch.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF \
		and (not HillHomeKit.enabled or chunk.get_node_or_null("Batch_lod_box") != null)
	_t._check(ok, "a LOD hill chunk lays its estates' gardens and lamps as one shadowless batch beside the houses (%d of %d parts)" % [batch.multimesh.instance_count if batch else -1, count])
	chunk.get_parent().remove_child(chunk)
	chunk.free()


func _far_tile(city: Node3D, plan: CityPlan, macro: MacroMap, m: Dictionary) -> void:
	var sky := Skyline.new()
	var canopy := ShaderMaterial.new()
	sky.setup(plan, city.chunk_style(), canopy)
	var k := plan.block_index_at(m.pos)
	var t := Skyline.tile_of(k)
	sky._work = {"t": t, "xforms": [], "colors": [], "customs": [], "veg": [], "veg_colors": [], "veg_custom": [],
		"houses": [], "house_colors": [], "house_custom": [], "hills": {}, "ranges": {},
		"est": [], "est_colors": [], "est_custom": []}
	var rect: Rect2 = plan.block(k.x, k.y).rect
	sky._add_hills(rect, macro)
	var expected := 0
	var trees := 0
	var house_boxes := 0
	for e in macro.hill_roads.mansions_in(rect):
		expected += EstateFar.parts(plan, e, false).size()
		trees += EstateFar.trees(plan, e).size()
		if HillHomeKit.enabled:
			house_boxes += HillHomeKit.far_boxes(plan, e).size()
	var est: Array = sky._work.est
	_t._check(est.size() == expected and (sky._work.est_custom as Array).size() == expected and (sky._work.veg as Array).size() >= trees \
		and (not HillHomeKit.enabled or (sky._work.houses as Array).size() == house_boxes),
		"a far-city hill block lays its estates' gardens and lamps (%d of %d), the houses (%d) and the trees" % [est.size(), expected, (sky._work.houses as Array).size()])
	sky._commit_tile()
	var tile = sky._tiles.get(t)
	var en: MultiMeshInstance3D = tile.est if tile else null
	var hn: MultiMeshInstance3D = tile.house if tile else null
	_t._check(en != null and en.material_override == EstateFar.material() and (hn == null or hn.material_override == canopy),
		"the far city's estate lamps wear the far-estate material and its houses keep far_canopy")
	sky.free()
