class_name MacArthurLook
## The reference camera over MacArthur Park (tools/refcams, "macarthur": from the south, 120 m up,
## 11:00), judged against a 2026 game (wave 4, rc-macarthur; docs/HANDOFF.md "MacArthur Park from
## the air"). What gave it away, in the order the eye lands on it, and what this changes in
## LandmarkMacArthurPark (each a few lines there that ask `enabled`):
##   * The lawns were lit-lime sheets, the LOD chunks' parts a lighter flat rectangle beside the
##     FULL ones: one lawn material at both levels now (`lawn_material()`), deeper, drier and worn
##     like a park that is walked on all day.
##   * The lake was a black pill: the water mesh carries the metres to the wall (`water_pieces()`,
##     UV2.x) and lake.gdshader's `shore_look` draws a silted shelf, scum against the wall and a
##     green-teal body in LINEAR colour on both renderers.
##   * A perfectly even picket of identical palms round the water and almost no shade trees: the
##     lake ring is jittered, gapped and broken into clumps (`palm_keep()` / `palm_jitter()`, hashes)
##     and the lawns carry ~3x the broadleaf trees (`TREES_PER_1000`).
##   * The walks vanished 260 m out, and the LOD halves had none: drawn at both levels to
##     `PATH_DRAW`, with diagonals across the north lawn (`extra_paths()`).
## Every roll is a hash of the seed and the place. MACARTHUR_LOOK=0 is the A/B: the park as it was.

static var enabled: bool = OS.get_environment("MACARTHUR_LOOK") != "0"

## Shade trees per 1000 m2 of lawn (the old park: 1.1) and the least spacing between them.
const TREES_PER_1000 := 3.2
const TREE_SPACING := 10.5
## The lake's palm ring: the share of the evenly spaced spots kept, how far each is slid along
## and across the ring (m), and how often a kept palm gets a second one beside it (a clump).
const PALM_KEEP := 0.72
const PALM_SLIDE := 4.0
const PALM_ACROSS := 2.2
const PALM_CLUMP := 0.22
## The walks are drawn this far (m) at both levels.
const PATH_DRAW := 1100.0
## The water grid (m) and the outline it measures the shore from (every n-th point).
const WATER_CELL := 4.0
const SHORE_STRIDE := 2
## The park's lawn: tint (deeper than the old 0.86 / 0.97 / 0.72), dryness, wear (the city's
## lawns are 0.3) and mower stripe width.
const LAWN_TINT := Color(0.74, 0.86, 0.60)
const LAWN_DRYNESS := 0.48
const LAWN_WEAR := 0.42
const LAWN_STRIPES := 4.2

static var _lawn_mats: Dictionary = {}
static var _shore_cache: Dictionary = {}


static func _h01(key: Array) -> float:
	return float(absi(hash(key)) % 100000) / 100000.0


## The park's lawn, the same material near and far (the far half drew a flat lighter colour).
static func lawn_material(seed_value: int) -> Material:
	if _lawn_mats.has(seed_value):
		return _lawn_mats[seed_value]
	var base := PropFactory.lawn(LAWN_TINT, hash([seed_value, "macarthur_lawn"]), LAWN_DRYNESS, LAWN_STRIPES) as ShaderMaterial
	# Its own copy for the wear (PropFactory's cache is shared with every lawn of that key).
	var mat := base.duplicate() as ShaderMaterial
	mat.set_shader_parameter("wear_amount", LAWN_WEAR)
	for m in base.get_meta_list():
		mat.set_meta(m, base.get_meta(m))
	_lawn_mats[seed_value] = mat
	return mat


## Whether the lake ring's palm `i` stands, and where (slid along `t`, across by its normal).
static func palm_keep(seed_value: int, i: int) -> bool:
	return _h01([seed_value, "mac_palm_keep", i]) < PALM_KEEP


static func palm_spots(seed_value: int, i: int, p: Vector2, t: Vector2) -> Array:
	var n := Vector2(-t.y, t.x)
	var a := p + t * (_h01([seed_value, "mac_palm_s", i]) - 0.5) * 2.0 * PALM_SLIDE \
		+ n * (_h01([seed_value, "mac_palm_n", i]) - 0.5) * 2.0 * PALM_ACROSS
	var out := [a]
	if _h01([seed_value, "mac_palm_clump", i]) < PALM_CLUMP:
		var ang := _h01([seed_value, "mac_palm_ang", i]) * TAU
		out.append(a + Vector2.from_angle(ang) * (2.4 + 1.2 * _h01([seed_value, "mac_palm_d", i])))
	return out


## Walks across the north lawn, corner to the crossing, the way people actually cut across it.
static func extra_paths(lay: Dictionary) -> Array:
	var out: Array = []
	var n_in: Rect2 = lay.north_in
	var crossing: Vector2 = lay.crossing
	var walk_z := n_in.end.y - 8.0
	var fr: Rect2 = (lay.field as Rect2).grow(3.5)
	var hub := Vector2(crossing.x, walk_z)
	var bs: Vector2 = lay.bandshell
	for c: Vector2 in [Vector2(n_in.end.x - 3.0, n_in.position.y + 3.0), Vector2(fr.end.x + 2.0, n_in.position.y + 3.0)]:
		out.append({"pts": PackedVector2Array([hub, hub.lerp(c, 0.5) + Vector2(0.0, 4.0), c]), "width": 3.0, "closed": false})
	# Up to the bandshell's front from the walk.
	out.append({"pts": PackedVector2Array([Vector2(bs.x, walk_z), Vector2(bs.x, bs.y + 9.0)]), "width": 3.4, "closed": false})
	return out


## Metres from `p` to the lake's outline (the outline thinned to every SHORE_STRIDE-th point).
static func shore_distance(lake: PackedVector2Array, p: Vector2) -> float:
	var key := Vector2i(roundi(p.x * 8.0), roundi(p.y * 8.0))
	if _shore_cache.has(key):
		return _shore_cache[key]
	var best := INF
	var n := lake.size()
	var i := 0
	while i < n:
		var a := lake[i]
		var b := lake[(i + SHORE_STRIDE) % n]
		var q := Geometry2D.get_closest_point_to_segment(p, a, b)
		best = minf(best, q.distance_squared_to(p))
		i += SHORE_STRIDE
	var d := sqrt(best)
	if _shore_cache.size() > 60000:
		_shore_cache.clear()
	_shore_cache[key] = d
	return d


## The water inside `area` as triangles [a, b, c] (Vector2), on a WATER_CELL grid so each vertex
## can carry its distance to the shore: cells well inside are whole quads, cells the waterline
## crosses are clipped to it exactly.
static func water_tris(lake: PackedVector2Array, bounds: Rect2, area: Rect2) -> Array:
	var out: Array = []
	var r := bounds.intersection(area)
	if r.size.x <= 0.0 or r.size.y <= 0.0:
		return out
	var x0 := floorf(r.position.x / WATER_CELL) * WATER_CELL
	var z0 := floorf(r.position.y / WATER_CELL) * WATER_CELL
	var z := z0
	while z < r.end.y:
		var x := x0
		while x < r.end.x:
			var cell := Rect2(x, z, WATER_CELL, WATER_CELL).intersection(area)
			x += WATER_CELL
			if cell.size.x <= 0.001 or cell.size.y <= 0.001:
				continue
			var quad := PackedVector2Array([cell.position, Vector2(cell.end.x, cell.position.y), cell.end, Vector2(cell.position.x, cell.end.y)])
			var c := cell.get_center()
			var inside := Geometry2D.is_point_in_polygon(c, lake)
			var d := shore_distance(lake, c)
			if d > WATER_CELL:
				if inside:
					out.append([quad[0], quad[1], quad[2]])
					out.append([quad[0], quad[2], quad[3]])
				continue
			for poly: PackedVector2Array in Geometry2D.intersect_polygons(quad, lake):
				var idx := Geometry2D.triangulate_polygon(poly)
				for k in range(0, idx.size(), 3):
					out.append([poly[idx[k]], poly[idx[k + 1]], poly[idx[k + 2]]])
		z += WATER_CELL
	return out
