extends RefCounted
## The extra occluders (Occluders, MountainOccluder), for tests/smoke_test.gd. Loaded at run time,
## not named there, so it compiles after the autoloads.
##
## Every one of them must lie INSIDE what it stands for, or whatever is behind the sliver is culled
## in plain sight: the hill tile's sheet under the drawn terrain at every point of every triangle,
## a deck's box inside the segment's collision box, a bank under the channel's surface, a sound
## wall's sheet inside its panel, the mountain sheet under the horizon plane's lowest possible
## surface and never inside INNER of the camera. And OCCLUDERS=0 (Occluders.enabled) builds none.

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	var plan: CityPlan = city.plan
	_terrain(city, plan)
	_decks(city, plan)
	_banks(city, plan)
	_walls()
	_mountains(city)
	_landmarks(plan)
	_switch(city, plan)


func _extra(chunk: CityChunk) -> ArrayOccluder3D:
	var node := chunk.get_node_or_null("OccluderExtra") as OccluderInstance3D
	return node.occluder as ArrayOccluder3D if node else null


func _drop(chunk: CityChunk) -> void:
	chunk.get_parent().remove_child(chunk)
	chunk.free()


## A front-range hill chunk: the sheet under the drawn tile everywhere.
func _terrain(city: Node3D, plan: CityPlan) -> void:
	var k := plan.chunk_index_at(Vector2(300.0, -1150.0))
	for level in [CityChunk.Level.FULL, CityChunk.Level.LOD]:
		var chunk: CityChunk = city._new_chunk(k, level)
		chunk.build()
		var occ := _extra(chunk)
		var tris := occ.indices.size() / 3 if occ else 0
		var worst := -INF
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		if occ:
			var v := occ.vertices
			var ix := occ.indices
			for i in range(0, ix.size(), 3):
				for n in 6:
					var a := rng.randf()
					var b := rng.randf()
					if a + b > 1.0:
						a = 1.0 - a
						b = 1.0 - b
					var p := v[ix[i]] + (v[ix[i + 1]] - v[ix[i]]) * a + (v[ix[i + 2]] - v[ix[i]]) * b
					worst = maxf(worst, p.y - chunk._terrain_height(Vector2(p.x, p.z)))
				for c in 3:
					var p := v[ix[i + c]]
					worst = maxf(worst, p.y - chunk._terrain_height(Vector2(p.x, p.z)))
		_t._check(tris >= 8 and tris <= 200 and worst < -0.5,
			"a %s hill tile's occluder is a coarse sheet (%d triangles) under its drawn ground (at most %.2f m above it)" % ["FULL" if level == CityChunk.Level.FULL else "LOD", tris, worst])
		_drop(chunk)


## A freeway chunk downtown: one box a segment it builds, inside that segment's collision box.
func _decks(city: Node3D, plan: CityPlan) -> void:
	var k := plan.chunk_index_at(Vector2(1989.0, 160.0))
	var chunk: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
	chunk.build()
	var area := chunk.owned_rect()
	var owned := 0
	var outside := 0
	for seg: Dictionary in chunk._freeway_segments():
		if seg.has("link") or (seg.a as Vector2).distance_to(seg.b) < 1.6 or not area.has_point((seg.a as Vector2).lerp(seg.b, 0.5)):
			continue
		owned += 1
		var box: Array = Occluders.deck_box(seg)
		var basis: Basis = box[0]
		var centre: Vector3 = box[1]
		# The collision box (CityChunk._build_freeway()): seg.width x DECK_THICKNESS x len + 0.4.
		var len := (seg.a as Vector2).distance_to(seg.b)
		var half := Vector3(float(seg.width) * 0.5, Freeway.DECK_THICKNESS * 0.5, len * 0.5 + 0.2)
		var axes := [basis.x.normalized(), basis.y.normalized(), basis.z.normalized()]
		for c in 8:
			var corner := centre + basis * Vector3(-1.0 if c & 1 else 1.0, -1.0 if c & 2 else 1.0, -1.0 if c & 4 else 1.0)
			var d := corner - centre
			if absf(d.dot(axes[0])) > half.x - 0.5 or absf(d.dot(axes[1])) > half.y - 0.1 or absf(d.dot(axes[2])) > half.z:
				outside += 1
	var occ := _extra(chunk)
	var tris := occ.indices.size() / 3 if occ else 0
	_t._check(owned > 0 and outside == 0 and tris >= owned * 12,
		"a freeway chunk's %d deck segments each have an occluder box (%d triangles) inside the deck (%d corners out)" % [owned, tris, outside])
	_drop(chunk)


## A river chunk: both banks under the channel's surface, pushed into the earth.
func _banks(city: Node3D, plan: CityPlan) -> void:
	var rv: LaRiver = plan.macro.river
	if rv == null:
		_t._check(true, "no river on this map (RIVER=0): no bank occluders to check")
		return
	var k := plan.chunk_index_at(rv.point(rv.length * 0.4, 0.0))
	var chunk: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
	chunk.build()
	var occ := _extra(chunk)
	var worst := -INF
	var n := 0
	if occ:
		for p in occ.vertices:
			var nr := rv.nearest(Vector2(p.x, p.z), 200.0)
			if nr.w < 0.5:
				continue
			n += 1
			worst = maxf(worst, p.y - rv.surface(nr.x, nr.y))
	_t._check(n >= 8 and worst < -0.3, "a river chunk's bank occluders (%d points) lie under the channel's concrete (at most %.2f m above it)" % [n, worst])
	_drop(chunk)


## A sound wall panel's sheet stays inside the panel; a pilaster gets none.
func _walls() -> void:
	var size := Vector3(6.0, 4.24, 0.3)
	var c := Vector3(10.0, 3.0, -4.0)
	var q := Occluders.wall_quad(size, c)
	var inside := q.size() == 4
	for p: Vector3 in q:
		inside = inside and absf(p.x - c.x) <= size.x * 0.5 and absf(p.z - c.z) <= size.z * 0.5 and absf(p.y - c.y) <= size.y * 0.5
	var turned := Occluders.wall_quad(Vector3(0.3, 4.24, 6.0), c)
	for p: Vector3 in turned:
		inside = inside and absf(p.x - c.x) <= 0.15 and absf(p.z - c.z) <= 3.0
	_t._check(inside and Occluders.wall_quad(Vector3(0.55, 4.4, 0.5), c).is_empty(),
		"a sound wall panel's occluder lies inside the panel, either way round; a pilaster gets none")


## The far mountain sheet: under the plane's lowest possible surface, never near the camera.
func _mountains(city: Node3D) -> void:
	var m = city.get_node_or_null("MountainOccluder")
	if m == null:
		_t._check(false, "the city has a MountainOccluder")
		return
	var at := Vector2(300.0, 600.0)
	var plan: CityPlan = city.plan
	var street: float = plan.height_at(at) + 1.7
	_t._check(street > m._plane_ceiling(at) and plan.height_at(at) - 60.0 < m._plane_ceiling(at),
		"a camera on a basin street is above the horizon plane (sheet on), one 60 m under the ground is not (sheet off)")
	m._below = false
	m.update(at)
	var verts := PackedVector3Array()
	for node in m.get_children():
		if node is OccluderInstance3D and (node as OccluderInstance3D).visible:
			verts.append_array(((node as OccluderInstance3D).occluder as ArrayOccluder3D).vertices)
	var span: float = m._span
	var res: int = m._res
	var tstep := span / float(res)
	var worst := -INF
	var nearest := INF
	if true:
		for p in verts:
			nearest = minf(nearest, Vector2(p.x, p.z).distance_to(at))
			# The plane is never under the lowest of the 4 x 4 texels its spline weighs at any of
			# its vertices round here, less 23 m of crag and 5 m of sink.
			var tx := int(floor((p.x + span * 0.5) / tstep))
			var ty := int(floor((p.z + span * 0.5) / tstep))
			var lo := INF
			for y in range(ty - 4, ty + 5):
				for x in range(tx - 4, tx + 5):
					lo = minf(lo, m._hgt[clampi(y, 0, res - 1) * res + clampi(x, 0, res - 1)])
			worst = maxf(worst, p.y - (lo - 28.0))
	_t._check(m.triangles > 50 and worst < 0.0 and nearest >= MountainOccluder.INNER and MountainOccluder.INNER > MountainOccluder.SINK_CLEAR,
		"the far mountains' occluder (%d triangles round the basin) is under the horizon plane (at most %.1f m over its floor) and keeps %.0f m off the camera" % [m.triangles, worst, nearest])


## The landmarks that had none: the airport's head house (its occluder read CivicSites' context,
## which only the civic sites set), the mall, the observatory, the campus hall, the hangars. Built
## for the detailed copy only.
func _landmarks(plan: CityPlan) -> void:
	var want := ["terminal", "south_bay_mall", "observatory", "campus_hall", "hangars"]
	var got := []
	var far_any := false
	for lm: Dictionary in Landmarks.all():
		if not String(lm.id) in want:
			continue
		for detailed in [true, false]:
			var holder := Node3D.new()
			var statics := StaticBody3D.new() if detailed else null
			if statics:
				holder.add_child(statics)
			Landmarks.build(lm, holder, statics, plan, detailed)
			var n := holder.find_children("*", "OccluderInstance3D", true, false).size()
			if detailed and n > 0:
				got.append(lm.id)
			if not detailed and n > 0:
				far_any = true
			holder.free()
	_t._check(got.size() == want.size() and not far_any,
		"the head house, mall, observatory, campus hall and hangars have occluders (%s), their far copies none" % [", ".join(got)])


## OCCLUDERS=0: no extra occluder on a chunk.
func _switch(city: Node3D, plan: CityPlan) -> void:
	Occluders.enabled = false
	var chunk: CityChunk = city._new_chunk(plan.chunk_index_at(Vector2(300.0, -1150.0)), CityChunk.Level.FULL)
	chunk.build()
	_t._check(chunk.get_node_or_null("OccluderExtra") == null, "OCCLUDERS=0 builds no extra occluder")
	_drop(chunk)
	Occluders.enabled = true
