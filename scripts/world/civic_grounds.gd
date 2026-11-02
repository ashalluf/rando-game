class_name CivicGrounds
extends RefCounted
## The ground the civic centre's blocks leave over (rc-downtown-aerial, 2026-10-31).
##
## A civic site takes the footprint its table gives (CivicSites.SITES); at 1:1 city hall's block is
## 97 x 286 m and the hall's footprint 140 m of it, so a 97 x 72 m slab of bare paving lay either
## side of the hall - from the downtown aerial the hall stood in the middle of an empty car-park
## shaped field. The real hall stands on lawns (the south lawn on 1st St, the north lawn on
## Temple), under big street trees, with walks across them. `leftovers()` is ArenaGrounds' cut for
## the civic centre's sites; `build()` lays each rect as a lawn quartered by walks, edged with
## paving, an allee of broadleaf trees along its street sides and jacarandas in the quarters,
## benches on the walks. The far copy keeps the lawns and the trees (shadowless), so the handover
## does not change what the block is.
##
## Every roll is a private rng of a hash of the site and the rect, never a chunk or block rng.
## `CIVIC_GROUNDS=0` in the environment is the A/B (the bare paving again; downtown's park lawns
## take the rolled tint again too, see park_lawn()).

## The civic centre's sites that share their blocks' leftovers (the first in CivicSites.ORDER of a
## block builds them).
const CIVIC := ["ziggurat_hall", "civic_park", "concert_hall", "lattice_museum"]
## Rects thinner than this are left as paving; thinner than LAWN_MIN a planted bed.
const MIN_FILL := 6.0
const LAWN_MIN := 22.0
## The paved margin round a lawn, and the walks across it.
const EDGE := 4.5
const WALK := 4.0
## Trees along a lawn's edges, metres apart, and how far in from its edge.
const ALLEE_EVERY := 13.0
const ALLEE_IN := 3.2
## An irrigated civic lawn, barely dry: deeper than the green end of CityChunk._lawn_color(),
## which read lime from the air.
const LAWN_TINT := Color(0.56, 0.70, 0.50)
const LAWN_DRYNESS := 0.15

static var enabled := OS.get_environment("CIVIC_GROUNDS") != "0"
## The weathered flat roofs (shaders/roof_weather.gdshaderinc, set per Building material):
## `ROOF_WEATHER=0` is their A/B. Kept here with the rest of this camera's fixes.
static var roof_weather := OS.get_environment("ROOF_WEATHER") != "0"


## World rects of `id`'s block that no civic-centre site covers, if `id` is the first civic site
## in that block; else empty.
static func leftovers(plan: CityPlan, id: String) -> Array[Rect2]:
	var out: Array[Rect2] = []
	if not CIVIC.has(id):
		return out
	var block := Landmarks.site_rect(plan, CivicSites.anchor(id))
	var sites: Array[Rect2] = []
	for other: String in CIVIC:
		if Landmarks.site_rect(plan, CivicSites.anchor(other)) != block:
			continue
		if sites.is_empty() and other != id:
			return out
		sites.append((CivicSites.site(plan, other).world as Rect2))
	var xs := [block.position.x, block.end.x]
	var zs := [block.position.y, block.end.y]
	for r in sites:
		for x: float in [r.position.x, r.end.x]:
			if x > block.position.x + 0.5 and x < block.end.x - 0.5 and not xs.has(x):
				xs.append(x)
		for z: float in [r.position.y, r.end.y]:
			if z > block.position.y + 0.5 and z < block.end.y - 0.5 and not zs.has(z):
				zs.append(z)
	xs.sort()
	zs.sort()
	# Cells no site covers, merged along x into runs, runs of the same extent stacked along z.
	var runs: Array[Rect2] = []
	for j in zs.size() - 1:
		var run := Rect2()
		var open := false
		for i in xs.size() - 1:
			var cell := Rect2(Vector2(xs[i], zs[j]), Vector2(xs[i + 1] - xs[i], zs[j + 1] - zs[j]))
			var covered := false
			for r in sites:
				if r.has_point(cell.get_center()):
					covered = true
			if covered:
				if open:
					runs.append(run)
				open = false
			elif open:
				run = run.merge(cell)
			else:
				run = cell
				open = true
		if open:
			runs.append(run)
	for r in runs:
		var merged := false
		for k in out.size():
			var o := out[k]
			if is_equal_approx(o.position.x, r.position.x) and is_equal_approx(o.size.x, r.size.x) and is_equal_approx(o.end.y, r.position.y):
				out[k] = o.merge(r)
				merged = true
				break
		if not merged:
			out.append(r)
	var kept: Array[Rect2] = []
	for r in out:
		if minf(r.size.x, r.size.y) >= MIN_FILL:
			kept.append(r)
	return kept


## The lawns of `id`'s block in world XZ (what build() lays as lawn): the checks and the probe.
static func lawn_rects(plan: CityPlan, id: String) -> Array[Rect2]:
	var out: Array[Rect2] = []
	for r in leftovers(plan, id) + inner_rects(plan, id):
		if minf(r.size.x, r.size.y) >= LAWN_MIN:
			out.append_array(_quarters(r.grow(-EDGE)))
	return out


## Ground inside a site its builder leaves bare, world XZ. City hall: the site is the block's
## width, the plinth 74 m of it (LandmarkCivicCenter._city_hall()), so 30 m strips either side of
## the plinth along the street faces were paving; the real hall has lawns there. Clear of the
## forecourt's lamps and flagpoles along the park front.
static func inner_rects(plan: CityPlan, id: String) -> Array[Rect2]:
	var out: Array[Rect2] = []
	if id != "ziggurat_hall":
		return out
	var info := CivicSites.site(plan, id)
	var s: Rect2 = info.local
	var pw := minf(74.0, s.size.x - 2.0)
	var gap := 4.0
	var x0 := pw * 0.5 + gap
	if s.end.x - x0 < LAWN_MIN:
		return out
	var z0 := s.position.y + 4.0
	for side: float in [-1.0, 1.0]:
		var r := Rect2(Vector2(x0 if side > 0.0 else s.position.x, z0), Vector2(s.end.x - x0, s.end.y - z0))
		out.append(CivicSites.rect_to_world(info, r))
	return out


## A lawn cut into four by a walk along its long axis and one across.
static func _quarters(lawn: Rect2) -> Array[Rect2]:
	var c := lawn.get_center()
	var h := WALK * 0.5
	return [Rect2(lawn.position, Vector2(c.x - h - lawn.position.x, c.y - h - lawn.position.y)),
		Rect2(Vector2(c.x + h, lawn.position.y), Vector2(lawn.end.x - c.x - h, c.y - h - lawn.position.y)),
		Rect2(Vector2(lawn.position.x, c.y + h), Vector2(c.x - h - lawn.position.x, lawn.end.y - c.y - h)),
		Rect2(Vector2(c.x + h, c.y + h), Vector2(lawn.end.x - c.x - h, lawn.end.y - c.y - h))]


## Fills `id`'s leftovers under `parent` (the chunk or the far-landmark holder), in a frame of its
## own at the site's centre with no turn. Called by CivicSites.build() while ctx is set.
static func build(plan: CityPlan, id: String, info: Dictionary, parent: Node3D, detailed: bool) -> void:
	if not enabled or not CIVIC.has(id):
		return
	var rects := leftovers(plan, id)
	var inner := inner_rects(plan, id)
	if rects.is_empty() and inner.is_empty():
		return
	var centre: Vector2 = info.centre
	var y0: float = info.y0
	var root := Node3D.new()
	root.name = "CivicGrounds_" + id
	root.position = Vector3(centre.x, 0.0, centre.y)
	parent.add_child(root)
	var statics: StaticBody3D = null
	if detailed:
		statics = StaticBody3D.new()
		statics.name = "CivicGroundsBody"
		statics.collision_layer = 1
		statics.collision_mask = 0
		root.add_child(statics)
	var g := LandmarkGeo.new()
	var batch := MultiMeshBatch.new()
	g.use("cg_paving", LandmarkMats.paving("pavers", 2.4, Color(0.92, 0.9, 0.86), 5117, 3.0, 0.25))
	g.use("cg_kerb", LandmarkMats.plain("cg_kerb", Color(0.74, 0.72, 0.68), 0.85))
	var chunk: CityChunk = CivicSites.ctx.get("chunk") if detailed else null
	for k in rects.size():
		var w := rects[k]
		var r := Rect2(w.position - centre, w.size)
		var seed_value := absi(hash([id, k, "civic_grounds"]))
		g.cap("cg_paving", LandmarkGeo.ccw(LandmarkArenaDistrict._rect_poly(r)), y0 + 0.03)
		if minf(r.size.x, r.size.y) < LAWN_MIN:
			ArenaGrounds.bed(g, batch, statics, r.grow(-1.5), y0, seed_value, 11.0, false, false, not detailed)
			continue
		_lawn(g, batch, r, y0, seed_value, detailed, chunk, centre)
	for k in inner.size():
		var r := Rect2(inner[k].position - centre, inner[k].size)
		g.cap("cg_paving", LandmarkGeo.ccw(LandmarkArenaDistrict._rect_poly(r)), y0 + 0.03)
		_lawn(g, batch, r, y0, absi(hash([id, k, "civic_grounds_inner"])), detailed, chunk, centre)
	if not detailed:
		ArenaGrounds._far_shadows(batch)
	g.commit(root, "CivicGrounds")
	batch.build(root)


## One leftover as a lawn: paved margin, four quarters with a concrete edge, an allee along the
## outer edges, a jacaranda in each quarter, benches facing the walks.
static func _lawn(g: LandmarkGeo, batch: MultiMeshBatch, r: Rect2, y0: float, seed_value: int, detailed: bool, chunk: CityChunk, centre: Vector2) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var lawn_mat := PropFactory.lawn(LAWN_TINT, seed_value % 100000, LAWN_DRYNESS, 3.0)
	g.use("cg_lawn", lawn_mat)
	var lawn := r.grow(-EDGE)
	var quarters := _quarters(lawn)
	for q in quarters:
		g.cap("cg_lawn", LandmarkGeo.ccw(LandmarkArenaDistrict._rect_poly(q)), y0 + 0.07)
		var c := q.get_center()
		# A low concrete edge round each quarter, so the lawn has a lip and not a printed edge.
		for e: Array in [[Vector2(c.x, q.position.y), Vector2(q.size.x + 0.3, 0.3)], [Vector2(c.x, q.end.y), Vector2(q.size.x + 0.3, 0.3)],
				[Vector2(q.position.x, c.y), Vector2(0.3, q.size.y)], [Vector2(q.end.x, c.y), Vector2(0.3, q.size.y)]]:
			var at: Vector2 = e[0]
			var sz: Vector2 = e[1]
			g.box("cg_kerb", Vector3(at.x, y0 + 0.08, at.y), Vector3(sz.x, 0.14, sz.y), Color.WHITE)
		if chunk:
			var wq := Rect2(q.position + centre, q.size)
			chunk._add_grass(wq.grow(-0.5), 0.9, 0.0, [], lawn_mat, wq)
	# The allee: broadleaf street trees in a line just inside the lawn's outer edge, all round.
	var trees: Array[Vector2] = []
	for side in 4:
		var horiz := side < 2
		var length := lawn.size.x if horiz else lawn.size.y
		var n := maxi(1, int(length / ALLEE_EVERY))
		for i in n:
			var f := (float(i) + 0.5) / float(n)
			var p: Vector2
			match side:
				0: p = Vector2(lerpf(lawn.position.x, lawn.end.x, f), lawn.position.y + ALLEE_IN)
				1: p = Vector2(lerpf(lawn.position.x, lawn.end.x, f), lawn.end.y - ALLEE_IN)
				2: p = Vector2(lawn.position.x + ALLEE_IN, lerpf(lawn.position.y, lawn.end.y, f))
				_: p = Vector2(lawn.end.x - ALLEE_IN, lerpf(lawn.position.y, lawn.end.y, f))
			# Off the walks, and not twice at a corner.
			if absf(p.x - lawn.get_center().x) < WALK or absf(p.y - lawn.get_center().y) < WALK:
				continue
			var dup := false
			for t in trees:
				if t.distance_to(p) < ALLEE_EVERY * 0.6:
					dup = true
			if dup:
				continue
			trees.append(p)
			var tv := 1 + (seed_value + i + side) % 3
			_tree(batch, rng, tv, p, y0 + 0.07, rng.randf_range(9.0, 12.0))
	# A jacaranda in the middle of each quarter big enough for it.
	var jac := PropFactory.CITY_TREES.size() - 1
	for q in quarters:
		if minf(q.size.x, q.size.y) < 14.0:
			continue
		var p := q.get_center() + Vector2(rng.randf_range(-2.0, 2.0), rng.randf_range(-2.0, 2.0))
		_tree(batch, rng, jac, p, y0 + 0.07, rng.randf_range(8.0, 10.5))
	if not detailed:
		return
	var bench := PropFactory.model_bench()
	var c := lawn.get_center()
	for q in quarters:
		var qc := q.get_center()
		# One bench on each quarter's edge along the long walk, facing it.
		var long_x := lawn.size.x >= lawn.size.y
		var p: Vector2
		var yaw: float
		if long_x:
			var side := -1.0 if qc.y < c.y else 1.0
			p = Vector2(qc.x, c.y + side * (WALK * 0.5 - 0.6))
			yaw = PI if side < 0.0 else 0.0
		else:
			var side := -1.0 if qc.x < c.x else 1.0
			p = Vector2(c.x + side * (WALK * 0.5 - 0.6), qc.y)
			yaw = -PI * 0.5 if side < 0.0 else PI * 0.5
		batch.add("cg_bench", bench, Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x, y0 + 0.03, p.y)))


static func _tree(batch: MultiMeshBatch, rng: RandomNumberGenerator, tv: int, p: Vector2, y: float, height: float) -> void:
	var sc := PropFactory.city_tree_scale(tv, height)
	batch.add("tree_%d" % tv, PropFactory.model_tree(tv), Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sc, sc, sc)), Vector3(p.x, y, p.y)),
		Color.WHITE, Color(rng.randf(), rng.randf(), rng.randf(), rng.randf_range(0.5, 1.0)))


## Downtown's park lawns are watered: a PARK block inside the real downtown (Grand Park, Pershing
## Square, Grand Hope Park) takes an irrigated tint in place of the rolled one (the roll is still
## made; called after it by CityChunk._build_park()). Off with CIVIC_GROUNDS=0.
static func park_lawn(rect: Rect2, rolled: Color) -> Color:
	if not enabled or not DowntownReal.in_extent(rect.get_center()):
		return rolled
	return LAWN_TINT
