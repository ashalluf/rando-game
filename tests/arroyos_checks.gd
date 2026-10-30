extends RefCounted
## The dry creek beds in the canyon floors (Arroyos, ArroyoBuild, ArroyoKit), for
## tests/smoke_test.gd. Loaded at run time, not named there, so it compiles after the autoloads.
##
## The network: built, big enough, every line running downhill head to foot, the snap putting a
## point on lower ground than the coarse line and giving the same answer twice (pure: two chunks
## agree along their edge). A FULL hill chunk with washes: the bed mesh on the bed shader, cobbles,
## boulders and bank planting, nothing of HillPlanting left in the bed and everything else it
## planted where it was with the beds off; a culvert where a drawn hill road crosses a wash; the LOD
## chunk's painted strip and no props; and ARROYOS off builds none of it.

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	var plan: CityPlan = city.plan
	if plan.macro == null:
		_t._check(false, "arroyos: the plan has a map")
		return
	var t0 := Time.get_ticks_msec()
	var net: Variant = Arroyos.build_now(plan)
	_t._check(net != null, "arroyos: the network builds (%d ms)" % (Time.get_ticks_msec() - t0))
	if net == null:
		return
	_network(plan, net)
	var k := _busiest_chunk(plan, net)
	_t._check(k != Vector2i(1 << 30, 0), "arroyos: a hill chunk holds a wash")
	if k == Vector2i(1 << 30, 0):
		return
	_full(city, plan, k)
	_lod(city, plan, k)
	_culvert(city, plan, net)


func _network(plan: CityPlan, net: Variant) -> void:
	var lines: Array = net.lines
	var points := 0
	var downhill := 0
	var drawn := 0
	for l: Dictionary in lines:
		var pts: PackedVector2Array = l.pts
		var ws: PackedFloat32Array = l.w
		points += pts.size()
		# The stretches that carry a bed (a gap across a filled pit is the flood's own flat).
		var first := -1
		var last := -1
		for i in pts.size():
			if ws[i] > 0.0:
				last = i
				if first < 0:
					first = i
		if last - first < 4:
			continue
		drawn += 1
		# Within RISE and a metre: the points are the coarse cells' path rounded, not the cells.
		if plan.macro.raw_height_at(pts[last]) < plan.macro.raw_height_at(pts[first]) + Arroyos.RISE + 1.0:
			downhill += 1
	_t._check(lines.size() > 80 and points * Arroyos.STEP > 60000.0, "arroyos: %d washes, %.0f km of them" % [lines.size(), points * Arroyos.STEP / 1000.0])
	_t._check(downhill >= drawn * 0.92, "arroyos: the washes run downhill head to foot (%d of %d)" % [downhill, drawn])
	# The snap: lower ground, and the same answer from a cold cache.
	var lower := 0
	var tried := 0
	var same := true
	for li in range(0, lines.size(), maxi(1, lines.size() / 25)):
		var pts: PackedVector2Array = lines[li].pts
		var pi := pts.size() / 2
		var s := Arroyos.snapped(net, li, pi)
		tried += 1
		if plan.macro.raw_height_at(s) <= plan.macro.raw_height_at(pts[pi]) + 0.05:
			lower += 1
		net.raw_off.erase(li)
		same = same and Arroyos.snapped(net, li, pi).is_equal_approx(s)
	_t._check(lower >= tried * 0.9, "arroyos: the snap finds the gully floor (%d of %d lower)" % [lower, tried])
	_t._check(same, "arroyos: the snap is pure (chunks agree along their edges)")


## The hill chunk with the most wash points.
func _busiest_chunk(plan: CityPlan, net: Variant) -> Vector2i:
	var counts := {}
	for l: Dictionary in net.lines:
		var pts: PackedVector2Array = l.pts
		var ws: PackedFloat32Array = l.w
		for i in range(0, pts.size(), 2):
			if ws[i] <= 0.0:
				continue
			var k := plan.block_index_at(pts[i])
			counts[k] = int(counts.get(k, 0)) + 1
	var best := Vector2i(1 << 30, 0)
	var most := 0
	for k: Vector2i in counts:
		var r := plan.owned_rect(k.x, k.y)
		if plan.macro.zone_at(r.get_center()) != MacroMap.Zone.HILLS:
			continue
		if plan.macro.hill_roads and not plan.macro.hill_roads.mansions_in(r).is_empty():
			continue
		if int(counts[k]) > most:
			most = counts[k]
			best = k
	return best


func _build(city: Node3D, k: Vector2i, level: int) -> CityChunk:
	var chunk: CityChunk = city._new_chunk(k, level)
	chunk.build()
	return chunk


func _free(chunk: CityChunk) -> void:
	if chunk.get_parent():
		chunk.get_parent().remove_child(chunk)
	chunk.free()


func _full(city: Node3D, plan: CityPlan, k: Vector2i) -> void:
	var t0 := Time.get_ticks_usec()
	var chunk := _build(city, k, CityChunk.Level.FULL)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	var b: ArroyoBuild = chunk.get_meta("arroyo_build") if chunk.has_meta("arroyo_build") else null
	var bed: MeshInstance3D = chunk.get_node_or_null("ArroyoBed")
	_t._check(b != null and not b.segs.is_empty(), "arroyos: the FULL chunk %s has bed segments (%d)" % [k, b.segs.size() if b else 0])
	var shader_ok := bed != null and (bed.material_override as ShaderMaterial).shader.resource_path.ends_with("arroyo_bed.gdshader")
	_t._check(shader_ok, "arroyos: the bed is drawn on arroyo_bed.gdshader")
	var tris: int = chunk.get_meta("arroyo_bed_tris", 0)
	_t._check(tris > 50 and tris < 60000, "arroyos: the bed is %d triangles" % tris)
	var cobbles: int = chunk.get_meta("arroyo_cobbles", 0)
	_t._check(cobbles > 20 and cobbles <= ArroyoBuild.MAX_COBBLES, "arroyos: %d cobbles in the bed" % cobbles)
	var banks: Array = chunk.get_meta("arroyo_banks", [])
	var kinds := {}
	for e: Array in banks:
		kinds[e[1]] = int(kinds.get(e[1], 0)) + 1
	_t._check(banks.size() > 4, "arroyos: the banks are planted (%s)" % kinds)
	# Every bed segment on natural ground (no road bed, bank or pad).
	var carved := 0
	for s: Array in b.segs:
		var p: Vector2 = (s[0] + s[1]) * 0.5
		if not Arroyos.natural(plan, p, 0.6):
			carved += 1
	_t._check(carved <= b.segs.size() / 50, "arroyos: the beds lie on natural ground (%d carved of %d)" % [carved, b.segs.size()])
	# HillPlanting keeps out of the bed, and everything else it planted is where it was.
	var in_bed := 0
	var on := {}
	for e: Array in chunk.hill_planting.get("points", []):
		if b.bed_distance(e[0]) < 0.6:
			in_bed += 1
		on[str(e)] = true
	_t._check(in_bed == 0, "arroyos: nothing of the hills' own planting stands in the bed (%d)" % in_bed)
	var own_ms := int(chunk.get_meta("arroyo_usec", 0)) / 1000.0
	var step_ms := int(chunk.get_meta("arroyo_max_usec", 0)) / 1000.0
	_t._check(step_ms < 15.0, "arroyos: no arroyo build step over 15 ms (%.1f; %.1f ms in all)" % [step_ms, own_ms])
	print("ARROYOS full chunk %s: %d segments, %d bed triangles, %d cobbles, banks %s, chunk build %.0f ms, arroyos %.1f ms (longest step %.1f)" % [k, b.segs.size(), tris, cobbles, kinds, ms, own_ms, step_ms])
	_free(chunk)
	Arroyos.enabled = false
	var off := _build(city, k, CityChunk.Level.FULL)
	Arroyos.enabled = true
	var moved := 0
	var kept := 0
	for e: Array in off.hill_planting.get("points", []):
		if b.bed_distance(e[0]) < 0.6:
			continue
		kept += 1
		if not on.has(str(e)):
			moved += 1
	_t._check(off.get_node_or_null("ArroyoBed") == null and not off.has_meta("arroyo_cobbles"), "arroyos: ARROYOS=0 builds no beds")
	_t._check(moved == 0 and kept > 0, "arroyos: the hills' planting is unmoved outside the beds (%d of %d moved)" % [moved, kept])
	_free(off)


func _lod(city: Node3D, plan: CityPlan, k: Vector2i) -> void:
	var chunk := _build(city, k, CityChunk.Level.LOD)
	var bed: MeshInstance3D = chunk.get_node_or_null("ArroyoBed")
	_t._check(bed != null and not chunk.has_meta("arroyo_cobbles"), "arroyos: the LOD chunk paints the strip and places no stones")
	_free(chunk)


## A drawn hill road over a wash: the chunk at the crossing builds a culvert.
func _culvert(city: Node3D, plan: CityPlan, net: Variant) -> void:
	var hr := plan.macro.hill_roads
	var tried := 0
	var made := 0
	var seen := {}
	for l: Dictionary in net.lines:
		if tried >= 14 or made > 0:
			break
		var pts: PackedVector2Array = l.pts
		for i in range(0, pts.size() - 1, 3):
			var box := Rect2(pts[i], Vector2.ZERO).expand(pts[mini(i + 3, pts.size() - 1)]).grow(6.0)
			var hit := false
			for seg: Dictionary in hr.segments_in(box):
				if seg.draw and Geometry2D.segment_intersects_segment(pts[i], pts[mini(i + 3, pts.size() - 1)], seg.a, seg.b) != null:
					hit = true
					break
			if not hit:
				continue
			var k := plan.block_index_at(pts[i])
			if seen.has(k):
				continue
			seen[k] = true
			tried += 1
			var chunk := _build(city, k, CityChunk.Level.FULL)
			var n: int = chunk.get_meta("arroyo_culverts", 0)
			if n > 0:
				var found := false
				for c in chunk.get_children():
					if c is MeshInstance3D and str(c.name).begins_with("Culvert"):
						found = (c as MeshInstance3D).mesh.get_surface_count() == 1
				_t._check(found, "arroyos: the culvert's ends are built at chunk %s" % k)
				made += n
			_free(chunk)
			break
	_t._check(made > 0, "arroyos: a hill road crossing a wash gets a culvert (%d chunks tried)" % tried)
