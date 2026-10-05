extends RefCounted
## The freeway kit (FreewayKit, CityChunk._build_freeway()) for tests/smoke_test.gd. Loaded at run
## time (not named there), so it compiles after the autoloads. Checks: the lane layout (four
## lanes each way, real widths, shoulders inside the barriers) and that traffic drives the lanes
## that are painted; kind codes survive the 8-bit vertex colour; the route numbers on the
## shields are this game's own; a chunk under a sign gantry builds the four meshes and the
## collision, with the signs' lettering, Botts' dots, markers, lamp lenses and light pools in
## them, every flat thing facing up, no NaN; an LOD chunk builds the same deck without the small
## stuff; and the triangle cost per deck segment stays inside its budget.

## Triangles per deck segment, all four meshes, averaged over a chunk.
const FULL_TRI_BUDGET := 1400.0
const LOD_TRI_BUDGET := 420.0

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	var plan: CityPlan = city.plan
	var fw: Freeway = plan.macro.freeway if plan.macro else null
	_t._check(fw != null and not fw.routes.is_empty(), "the freeway kit has routes to build")
	if fw == null or fw.routes.is_empty():
		return
	_layout(fw)
	_codes()
	_names(fw)
	await _chunks(city, plan, fw)


func _layout(fw: Freeway) -> void:
	var ok := true
	var traffic_ok := true
	for f: float in [0.94, 1.0, 1.08]:
		var width := Freeway.DECK_WIDTH * f
		var lay := Freeway.lane_layout(width)
		var lw: float = lay.lane
		ok = ok and lw >= 3.2 and lw <= Freeway.LANE_MAX + 0.001 and float(lay.inner) > FreewayKit.MEDIAN_HALF + 0.5 \
			and float(lay.edge) + 1.1 <= float(lay.outer) and float(lay.outer) < float(lay.half)
		var prev := -INF
		for k in Freeway.LANES:
			var u := Freeway.lane_fraction(width, k) * float(lay.half)
			traffic_ok = traffic_ok and u > float(lay.inner) + lw * 0.4 and u < float(lay.edge) - lw * 0.4 and u > prev + lw * 0.9
			prev = u
	_t._check(ok, "freeway lanes: four each way 3.2-3.6 m wide, shoulders inside the barriers, on every deck width")
	_t._check(traffic_ok, "freeway traffic lanes are the painted lanes' centres")


func _codes() -> void:
	var ok := true
	for k in range(1, 12):
		var a := FreewayKit.kind_color(Color.WHITE, k).a
		var q := roundf(a * 255.0) / 255.0
		ok = ok and int(round(a * FreewayKit.KIND_SCALE)) == k and int(round(q * FreewayKit.KIND_SCALE)) == k
	_t._check(ok, "freeway kind codes survive an 8-bit vertex colour")


func _names(fw: Freeway) -> void:
	var ok := true
	var seen := {}
	for r: Dictionary in fw.routes:
		var name: String = r.name
		var real := name.split(" ")[0]
		var n := FreewayKit.route_number(name)
		ok = ok and str(n) != real and n != 90
		seen[n] = true
	_t._check(ok and seen.size() == fw.routes.size(), "every route's shield number is the game's own and distinct (%s)" % [seen.keys()])
	_t._check(FreewayKit.sign_case("OLIVE ST") == "Olive St" and FreewayKit.sign_case("5TH ST") == "5th St", "sign names are set in mixed case")
	var geo := FreewayKit.text_geo("EXIT 12A", 0.4)
	_t._check((geo[0] as PackedVector3Array).size() > 30 and float(geo[2]) > 1.0 and float(geo[2]) < 4.5,
		"sign lettering builds as geometry at its size (%d verts, %.2f m)" % [(geo[0] as PackedVector3Array).size(), float(geo[2])])


## Finds a block whose chunk owns a gantry segment, builds it FULL and LOD and looks inside.
func _chunks(city: Node3D, plan: CityPlan, fw: Freeway) -> void:
	var gantry_every := int(round(Freeway.GANTRY_SPACING / Freeway.STEP))
	var key := Vector2i(999999, 0)
	for ri in fw.routes.size():
		var pts: PackedVector2Array = fw.routes[ri].points
		for i in range(gantry_every, pts.size() - 1, gantry_every):
			var mid := pts[i].lerp(pts[i + 1], 0.5)
			if plan.zone_at(mid) == MacroMap.Zone.CITY:
				key = plan.block_index_at(mid)
				break
		if key.x != 999999:
			break
	_t._check(key.x != 999999, "a city block under a sign gantry")
	if key.x == 999999:
		return
	var chunk: CityChunk = city._new_chunk(key, CityChunk.Level.FULL)
	chunk.build()
	var nodes_ok := chunk.has_node("FreewayDeck") and chunk.has_node("FreewayStructure") and chunk.has_node("FreewayPaint") \
		and chunk.has_node("FreewayGlow") and chunk.has_node("FreewayBody")
	_t._check(nodes_ok, "a deck chunk builds deck, structure, paint, glow and collision")
	if nodes_ok:
		_t._check((chunk.get_node("FreewayPaint") as GeometryInstance3D).cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			and (chunk.get_node("FreewayGlow") as GeometryInstance3D).cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			and (chunk.get_node("FreewayStructure") as GeometryInstance3D).material_override == FreewayKit.structure_material(),
			"the paint and the pools cast no shadow, the structure shares one material")
	# The same build again into a kit we can read (mesh data is not kept by the dummy renderer).
	var segs := chunk._freeway_segments()
	var kit := FreewayKit.new(chunk)
	var built := kit.build_segments(segs, chunk.owned_rect())
	var body_n := 0
	if nodes_ok:
		body_n = (chunk.get_node("FreewayBody") as Node).get_child_count()
	_t._check(built > 0 and body_n == built, "one collision box per deck segment built (%d / %d)" % [body_n, built])
	var paint := kit.paint.commit_to_arrays()
	var body := kit.body.commit_to_arrays()
	var glow := kit.glow.commit_to_arrays()
	var pk := _kinds(paint)
	var bk := _kinds(body)
	_t._check(pk.get(FreewayKit.P_SIGN, 0) > 300, "the gantry's signs have faces and lettering (%d sign vertices)" % pk.get(FreewayKit.P_SIGN, 0))
	_t._check(pk.get(FreewayKit.P_BOTTS, 0) > 0 and pk.get(FreewayKit.P_RPM, 0) > 0 and pk.get(FreewayKit.P_LINE, 0) > 0,
		"the deck has lane lines, Botts' dots and edge markers")
	_t._check(bk.get(FreewayKit.S_BARRIER, 0) > 0 and bk.get(FreewayKit.S_LENS, 0) > 0 and bk.get(FreewayKit.S_FASCIA, 0) > 0
		and bk.get(FreewayKit.S_STEEL, 0) > 0, "the structure has barriers, girder, steel and lamp lenses")
	var pools := (glow[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 6 if glow.size() > 0 and glow[Mesh.ARRAY_VERTEX] != null else 0
	_t._check(pools >= 2 and pools % 2 == 0, "every light standard throws a pool on each carriageway (%d pools)" % pools)
	_t._check(_flat_up(paint), "the deck's paint faces up")
	_t._check(_finite(paint) and _finite(body), "no NaN in the freeway meshes")
	var tris := float(_tris(paint) + _tris(body) + _tris(glow) + _tris(kit.top.commit_to_arrays()))
	_t._check(tris / built < FULL_TRI_BUDGET, "a FULL deck segment stays inside its triangle budget (%.0f < %.0f)" % [tris / built, FULL_TRI_BUDGET])
	chunk.get_parent().remove_child(chunk)
	chunk.free()
	# LOD: the same deck, its boards blank, no dots, markers or furniture.
	var lod: CityChunk = city._new_chunk(key, CityChunk.Level.LOD)
	lod.build()
	_t._check(lod.has_node("FreewayStructure") and lod.has_node("FreewayGlow"), "an LOD deck chunk builds the structure and the lights")
	var lkit := FreewayKit.new(lod)
	var lbuilt := lkit.build_segments(lod._freeway_segments(), lod.owned_rect())
	var lpaint := lkit.paint.commit_to_arrays()
	var lk := _kinds(lpaint)
	_t._check(lk.get(FreewayKit.P_BOTTS, 0) == 0 and lk.get(FreewayKit.P_RPM, 0) == 0, "an LOD deck draws no dots or markers")
	var ltris := float(_tris(lpaint) + _tris(lkit.body.commit_to_arrays()) + _tris(lkit.glow.commit_to_arrays()) + _tris(lkit.top.commit_to_arrays()))
	_t._check(lbuilt > 0 and ltris / lbuilt < LOD_TRI_BUDGET, "an LOD deck segment stays inside its triangle budget (%.0f < %.0f)" % [ltris / maxf(lbuilt, 1.0), LOD_TRI_BUDGET])
	lod.get_parent().remove_child(lod)
	lod.free()
	await _t.get_tree().process_frame


func _kinds(arrays: Array) -> Dictionary:
	var out := {}
	if arrays.is_empty() or arrays[Mesh.ARRAY_COLOR] == null:
		return out
	for c: Color in arrays[Mesh.ARRAY_COLOR]:
		var k := int(round(c.a * FreewayKit.KIND_SCALE))
		out[k] = int(out.get(k, 0)) + 1
	return out


func _flat_up(arrays: Array) -> bool:
	if arrays.is_empty():
		return false
	var cols: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var nrms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	for i in cols.size():
		var k := int(round(cols[i].a * FreewayKit.KIND_SCALE))
		if k in [FreewayKit.P_LINE, FreewayKit.P_DASH, FreewayKit.P_BOTTS, FreewayKit.P_RPM, FreewayKit.P_DIAMOND, FreewayKit.P_JOINT, FreewayKit.P_GRATE]:
			if nrms[i].y < 0.98:
				return false
	return true


func _finite(arrays: Array) -> bool:
	if arrays.is_empty():
		return true
	for v: Vector3 in arrays[Mesh.ARRAY_VERTEX]:
		if not (is_finite(v.x) and is_finite(v.y) and is_finite(v.z)):
			return false
	for n: Vector3 in arrays[Mesh.ARRAY_NORMAL]:
		if not is_finite(n.x) or absf(n.length() - 1.0) > 0.01:
			return false
	return true


func _tris(arrays: Array) -> int:
	if arrays.is_empty() or arrays[Mesh.ARRAY_VERTEX] == null:
		return 0
	if arrays[Mesh.ARRAY_INDEX] != null and (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() > 0:
		return (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	return (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
