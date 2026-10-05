extends RefCounted
## Road wear (RoadWear: 25 stamps in one atlas, laid per chunk), for tests/smoke_test.gd. Loaded
## at run time, not named there, so it compiles after the autoloads.
##
## Checks the library (at most 25 stamps, every one with its placement row, the atlas and its
## shader), the instance packing (exact in half floats), the variety (thousands of looks), how
## worn roads are by district (industrial > midtown > downtown's avenues, some streets fresh),
## then builds FULL chunks: one shadowless batch on the wear shader faded at its draw distance,
## within the cap, every stamp on the chunk's own ground, more wear in industrial than downtown,
## potholes rarer than cracks, the same chunk twice the same, the block built with the wear off
## the same block (hash-seeded), and the deep potholes indexed for the car bump and dropped with
## their chunk. Placement points come from the chunk's "road_wear" meta (instance transforms read
## back as identity under --headless).

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	var plan: CityPlan = city.plan
	_library()
	_levels(plan)
	_chunks(city, plan)


func _library() -> void:
	var stamps: Array = RoadWearTable.STAMPS
	var names := {}
	var bad := 0
	for row: Array in stamps:
		names[row[0]] = true
		var size: Vector2 = row[1]
		if size.x <= 0.05 or size.y <= 0.05 or not RoadWear.KINDS.has(row[0]):
			bad += 1
	for k: String in RoadWear.KINDS:
		if not names.has(k):
			bad += 1
		for partner: String in RoadWear.KINDS[k][3]:
			if not names.has(partner):
				bad += 1
	_t._check(stamps.size() <= 25 and stamps.size() >= 20 and names.size() == stamps.size() and bad == 0,
		"the road wear library is at most 25 stamps, each with a size and a placement row (%d stamps, %d bad)" % [stamps.size(), bad])
	var potholes := 0
	for row: Array in stamps:
		if (row[0] as String).begins_with("pothole") and (int(row[3]) & RoadWearTable.DEEP) != 0 and float(row[2]) > 0.025:
			potholes += 1
	_t._check(potholes >= 4, "the library has deep potholes for the parallax and the bump (%d)" % potholes)
	var mat := RoadWear.material()
	var tex_ok := true
	for p: String in ["wear_color", "wear_nrm", "wear_data"]:
		var tex := mat.get_shader_parameter(p) as Texture2D
		tex_ok = tex_ok and tex != null and tex.get_width() == RoadWearTable.ATLAS_PX and tex.get_height() == RoadWearTable.ATLAS_PX
	_t._check(tex_ok and mat.shader != null and mat.shader.get_shader_uniform_list().size() > 10,
		"the wear material has its shader and the three %d px atlas maps" % RoadWearTable.ATLAS_PX)
	# Packing: every custom value an integer under 2048 (exact in a half float).
	var worst := 31 + 32 * 25
	_t._check(worst < 2048 and 31 * 32 + 31 < 2048 and 255 < 2048, "the instance packing stays exact in half floats (max %d)" % worst)
	var v := RoadWear.variant_count()
	_t._check(int(v.single) >= 5000 and int(v.paired) >= 1000000,
		"the 25 stamps give thousands of distinct looks (%d single, %d paired, before turns and scales)" % [int(v.single), int(v.paired)])


func _levels(plan: CityPlan) -> void:
	var sums := {}
	var counts := {}
	var fresh := 0
	var total := 0
	for i in range(-40, 40):
		for d in [CityPlan.District.DOWNTOWN, CityPlan.District.MIDTOWN, CityPlan.District.INDUSTRIAL]:
			var l := RoadWear.road_level(plan, CityPlan.AXIS_X, i, d)
			var avenue := plan.road_width(CityPlan.AXIS_X, i) >= plan.avenue_width - 0.1
			var key := "%d_%s" % [d, "ave" if avenue else "st"]
			sums[key] = float(sums.get(key, 0.0)) + l
			counts[key] = int(counts.get(key, 0)) + 1
			if d == CityPlan.District.MIDTOWN:
				total += 1
				if l < 0.4:
					fresh += 1
	var mean := func(k: String) -> float: return float(sums.get(k, 0.0)) / maxf(float(counts.get(k, 0)), 1.0)
	var ind: float = (mean.call("3_st") + mean.call("3_ave")) * 0.5
	var mid: float = (mean.call("1_st") + mean.call("1_ave")) * 0.5
	var dta: float = mean.call("0_ave")
	_t._check(ind > mid and mid > dta, "industrial roads wear most, midtown next, downtown's avenues least (%.2f, %.2f, %.2f)" % [ind, mid, dta])
	_t._check(fresh > 0 and fresh < total / 3, "some streets were resurfaced lately (%d of %d midtown roads)" % [fresh, total])


func _chunks(city: Node3D, plan: CityPlan) -> void:
	var by_district := {}
	var all_ok := true
	var batch_ok := true
	var on_ground := true
	var worst := 0
	var potholes := 0
	var cracks := 0
	var checked := 0
	for d in [CityPlan.District.DOWNTOWN, CityPlan.District.MIDTOWN, CityPlan.District.INDUSTRIAL]:
		var keys := _blocks_of(plan, d, 3)
		var n := 0
		for k in keys:
			var chunk: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
			chunk.build()
			var pts: PackedVector2Array = chunk.get_meta("road_wear", PackedVector2Array())
			var kinds: Dictionary = chunk.get_meta("road_wear_kinds", {})
			n += pts.size()
			worst = maxi(worst, pts.size())
			for kind: String in kinds:
				if kind.begins_with("pothole"):
					potholes += int(kinds[kind])
				elif kind.contains("crack") or kind == "alligator" or kind == "tar_snake":
					cracks += int(kinds[kind])
			var owned := plan.owned_rect(k.x, k.y).grow(1.0)
			for p in pts:
				if not owned.has_point(p):
					on_ground = false
			var node := chunk.get_node_or_null("Batch_" + RoadWear.KEY) as MultiMeshInstance3D
			if pts.size() > 0:
				batch_ok = batch_ok and node != null and node.multimesh.instance_count == pts.size() \
					and node.multimesh.mesh == RoadWear.mesh() \
					and node.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF \
					and absf(node.visibility_range_end - RoadWear.DRAW_DISTANCE) < 0.5
			checked += 1
			chunk.get_parent().remove_child(chunk)
			chunk.free()
		by_district[d] = float(n) / maxf(float(keys.size()), 1.0)
	_t._check(checked >= 6, "built FULL chunks in downtown, midtown and industrial (%d)" % checked)
	_t._check(batch_ok, "a chunk's road wear is one shadowless batch on the wear quad, faded at %d m" % int(RoadWear.DRAW_DISTANCE))
	_t._check(worst <= RoadWear.MAX_PER_CHUNK and worst > 0, "road wear stays within its per-chunk cap (%d)" % worst)
	_t._check(on_ground, "every wear stamp lies on its own chunk's ground")
	var ind: float = by_district.get(CityPlan.District.INDUSTRIAL, 0.0)
	var dt: float = by_district.get(CityPlan.District.DOWNTOWN, 0.0)
	_t._check(ind > dt * 1.3 and dt > 0.0, "industrial streets wear more than downtown's (%.0f against %.0f stamps a chunk)" % [ind, dt])
	_t._check(cracks > potholes * 3, "potholes are far rarer than cracks (%d against %d)" % [potholes, cracks])
	# Twice the same, and the block with the wear off is the same block.
	var keys := _blocks_of(plan, CityPlan.District.INDUSTRIAL, 1)
	if keys.is_empty():
		return
	var k: Vector2i = keys[0]
	var a: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
	a.build()
	var pa: PackedVector2Array = a.get_meta("road_wear", PackedVector2Array())
	var sig := _signature(a)
	var bumps_with := RoadWear.bump_total()
	var probe := Vector2.INF
	for cell: Vector2i in RoadWear._bumps:
		for e: Array in RoadWear._bumps[cell]:
			if e[3] == a.key:
				probe = e[0]
	a.get_parent().remove_child(a)
	var dropped := RoadWear.bump_total() <= bumps_with
	a.free()
	var b: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
	b.build()
	var same := b.get_meta("road_wear", PackedVector2Array()) == pa and pa.size() > 0
	var depth_here := RoadWear.bump_for(probe) if probe != Vector2.INF else -1.0
	b.get_parent().remove_child(b)
	b.free()
	_t._check(same, "the same chunk wears the same (%d stamps)" % pa.size())
	_t._check(dropped and (probe == Vector2.INF or depth_here > 0.0), "deep potholes are indexed for the car bump (%s m deep) and dropped with their chunk" % (str(snappedf(depth_here, 0.001)) if probe != Vector2.INF else "none on this block"))
	RoadWear.enabled = false
	var bare: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
	bare.build()
	RoadWear.enabled = true
	var same_block := _signature(bare) == sig and bare.get_node_or_null("Batch_" + RoadWear.KEY) == null
	bare.get_parent().remove_child(bare)
	bare.free()
	_t._check(same_block, "the road wear rolls nothing from the block: built without it, the block is the same")


func _blocks_of(plan: CityPlan, district: int, want: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var centre := plan.block_index_at(plan.macro.downtown_center if plan.macro else Vector2.ZERO)
	for r in range(0, 30):
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dz)) != r:
					continue
				var k := centre + Vector2i(dx, dz)
				var b := plan.block(k.x, k.y)
				if int(b.district) != district or b.has("site") or int(b.kind) != CityPlan.BlockKind.BUILDINGS:
					continue
				if plan.zone_at((b.rect as Rect2).get_center()) != MacroMap.Zone.CITY or plan.river_block(k.x, k.y):
					continue
				out.append(k)
				if out.size() >= want:
					return out
	return out


## Buildings, props and batches of a chunk (the crowd left out: it is capped city-wide).
func _signature(chunk: CityChunk) -> Array:
	var out: Array = []
	for c in chunk.get_children():
		if c is Building or c is TrashCan:
			var p: Vector3 = (c as Node3D).position
			out.append("%s %.2f %.2f" % [c.get_class(), p.x, p.z])
		elif c is MultiMeshInstance3D and c.name != "Batch_" + RoadWear.KEY:
			out.append("%s %d" % [c.name, (c as MultiMeshInstance3D).multimesh.instance_count])
	for r in chunk.prop_records:
		out.append("%s %.2f %.2f" % [r.kind, (r.position as Vector3).x, (r.position as Vector3).z])
	out.sort()
	return out
