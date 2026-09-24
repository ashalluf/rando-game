class_name CityPlan
extends RefCounted
## The layout of an endless city from one seed, computed lazily: any road, block or
## intersection index can be asked for and always comes back the same.
## Pure data, no nodes. CityStreamer builds CityChunks from it around the player.

enum District { DOWNTOWN, MIDTOWN, SUBURBS, INDUSTRIAL, CAMPUS, BEACHTOWN }
enum BlockKind { BUILDINGS, PARK, PLAZA, MALL, BIGBOX }
enum Intersection { PLAIN, STOP_SIGNS, SIGNALS, ROUNDABOUT }

const DISTRICT_NAMES := ["Downtown", "Midtown", "Suburbs", "Industrial", "Campus", "Beach Town"]
const AXIS_X := 0
const AXIS_Z := 1

## Parameter ranges per district. Heights and lots in meters. "people" and "parked" are per
## block (owner, 2026-09-20: a packed downtown thinning toward the edges); "palms" is the
## chance a block's street trees are palms instead (owner: "it's Cali"); the downtown core
## multiplies people by up to 2x again (CityChunk._spawn_pedestrians).
const DISTRICTS := {
	District.DOWNTOWN: {
		# 18 m at the bottom, not 50: a 50 m floor meant downtown had no low-rise in it at all
		# (the measured minimum was 50.0 m, the area-weighted 25th percentile 101.9 m), and a
		# skyline is the gap between the infill and the towers. 160 at the top at the district's
		# edge; toward the core the band lerps to core_height below (it used to lerp the top by
		# 2.3x, to 368 m - generic towers over the landmark ones).
		"height": Vector2(18.0, 160.0), "lot": Vector2(28.0, 46.0), "gap": Vector2(2.0, 5.0),
		# SLAB twice, for the infill. Every other shape here has a floor baked into
		# Building._layout_parts - a CROWN is never under 50 m, a SETBACK never under 40, a TOWER
		# never under 30, STEPPED never under 15 - so without a shape that has none the 18 m
		# bottom is unreachable. SLAB also caps itself at 40 m, which is the infill tier.
		"shapes": [Building.Shape.SLAB, Building.Shape.SLAB, Building.Shape.TOWER, Building.Shape.PODIUM_TOWER, Building.Shape.SETBACK, Building.Shape.CROWN, Building.Shape.CROWN, Building.Shape.STEPPED],
		# The financial core between the landmark towers (MacroMap.downtown_core, skyline_boost
		# 1): a field of 80-200 m towers, not low-rise with the odd spike. The band is what
		# lot_height() lerps to as the boost rises; the flatter curve moves the median up to
		# ~105 m where the district curve would leave it at 70; the top stops at 205 so the
		# named towers (163-335 m) keep the skyline's peaks to themselves. SLAB never goes over
		# 40 m (Building._layout_parts), so the core draws from shapes that can reach the height
		# the far tier (Skyline) draws for the lot.
		"core_height": Vector2(40.0, 205.0), "core_curve": 1.35,
		"core_shapes": [Building.Shape.TOWER, Building.Shape.PODIUM_TOWER, Building.Shape.SETBACK, Building.Shape.CROWN,
			Building.Shape.TOWER, Building.Shape.PODIUM_TOWER, Building.Shape.SETBACK, Building.Shape.STEPPED],
		# Fewer pocket gardens between the towers of the core: 0.5 at the edge, 0.15 inside.
		"core_courtyard": 0.15,
		# And more stone: the real core is as much granite and precast as glass, and a field of
		# glass towers around the named ones read as one dark mass in every wide shot.
		"core_finishes": [Building.Finish.GLASS, Building.Finish.PANELS, Building.Finish.GLASS, Building.Finish.PANELS, Building.Finish.PANELS],

		"finishes": [Building.Finish.GLASS, Building.Finish.GLASS, Building.Finish.PANELS, Building.Finish.GLASS],
		"lit": Vector2(0.3, 0.6), "park": 0.05, "plaza": 0.12, "trees": 0.35, "courtyard": 0.5,
		"cafes": 2, "planters": 1, "clutter": 0, "weathering": Vector2(0.1, 0.4), "line_white": 0.5,
		"paving": [["pavers", 2.5, Color(1.07, 1.07, 1.07)], ["sidewalk", 3.0, Color(1.52, 1.52, 1.52)]],
		"tree_weights": [0.16, 0.24, 0.44, 0.12, 0.04], "jacarandas": 0.05,
		"lamp_tint": Color(1.0, 1.0, 1.0),
		"mall": 0.0, "bigbox": 0.0, "pads": 0.0, "lawn": false, "people": 46, "parked": 15, "palms": 0.22,
	},
	District.MIDTOWN: {
		"height": Vector2(12.0, 45.0), "lot": Vector2(20.0, 32.0), "gap": Vector2(3.0, 8.0),
		"shapes": [Building.Shape.SLAB, Building.Shape.STEPPED, Building.Shape.L_SHAPE, Building.Shape.PODIUM_TOWER, Building.Shape.TOWER],
		"finishes": [Building.Finish.FLAT, Building.Finish.BRICK, Building.Finish.PANELS, Building.Finish.GLASS],
		"lit": Vector2(0.2, 0.5), "park": 0.10, "plaza": 0.06, "trees": 0.7, "courtyard": 0.6,
		"cafes": 1, "planters": 2, "clutter": 1, "weathering": Vector2(0.2, 0.7), "line_white": 0.3,
		"paving": [["paving", 3.0, Color(0.99, 0.98, 0.96)], ["sidewalk", 3.0, Color(1.52, 1.52, 1.52)], ["pavers", 2.5, Color(1.11, 1.09, 1.05)]],
		"tree_weights": [0.32, 0.30, 0.15, 0.18, 0.05], "jacarandas": 0.08,
		"lamp_tint": Color(0.8, 0.86, 0.8),
		"mall": 0.08, "bigbox": 0.03, "pads": 0.12, "lawn": false, "people": 20, "parked": 12, "palms": 0.34,
	},
	District.SUBURBS: {
		"height": Vector2(5.0, 14.0), "lot": Vector2(14.0, 22.0), "gap": Vector2(6.0, 14.0),
		"shapes": [Building.Shape.SLAB, Building.Shape.SLAB, Building.Shape.L_SHAPE],
		"finishes": [Building.Finish.BRICK, Building.Finish.FLAT, Building.Finish.BRICK],
		"lit": Vector2(0.1, 0.35), "park": 0.18, "plaza": 0.02, "trees": 1.0, "courtyard": 0.3,
		"cafes": 0, "planters": 3, "clutter": 1, "weathering": Vector2(0.2, 0.6), "line_white": 0.6,
		"paving": [["sidewalk", 3.0, Color(1.57, 1.57, 1.57)], ["sidewalk", 3.0, Color(1.47, 1.47, 1.44)]],
		"tree_weights": [0.36, 0.32, 0.0, 0.24, 0.08], "jacarandas": 0.11,
		"lamp_tint": Color(1.0, 0.9, 0.8),
		"mall": 0.14, "bigbox": 0.07, "pads": 0.18, "lawn": true, "people": 6, "parked": 8, "palms": 0.45,
	},
	## The strip behind the sand. A beach town is not the ordinary grid shrunk down: the lots are
	## small and the setbacks nearly nothing, so it is DENSER than the suburbs while being much
	## lower, and that combination is what makes one read as a beach town from the street. Salt
	## air means heavy weathering, and it is the palmiest district on the map.
	District.BEACHTOWN: {
		"height": Vector2(6.0, 18.0), "lot": Vector2(13.0, 24.0), "gap": Vector2(2.0, 6.0),
		"shapes": [Building.Shape.SLAB, Building.Shape.SLAB, Building.Shape.L_SHAPE, Building.Shape.STEPPED],
		"finishes": [Building.Finish.FLAT, Building.Finish.FLAT, Building.Finish.PANELS, Building.Finish.BRICK],
		"lit": Vector2(0.25, 0.55), "park": 0.07, "plaza": 0.09, "trees": 0.8, "courtyard": 0.3,
		"cafes": 3, "planters": 3, "clutter": 2, "weathering": Vector2(0.35, 0.85), "line_white": 0.45,
		"paving": [["sidewalk", 3.0, Color(1.54, 1.53, 1.47)], ["pavers", 2.5, Color(1.13, 1.10, 1.03)]],
		"tree_weights": [0.2, 0.22, 0.06, 0.34, 0.18], "jacarandas": 0.07,
		"lamp_tint": Color(1.0, 0.94, 0.82),
		"mall": 0.0, "bigbox": 0.0, "pads": 0.06, "lawn": false, "people": 32, "parked": 16, "palms": 0.9,
	},
	District.CAMPUS: {
		"height": Vector2(8.0, 24.0), "lot": Vector2(26.0, 44.0), "gap": Vector2(10.0, 18.0),
		"shapes": [Building.Shape.SLAB, Building.Shape.L_SHAPE, Building.Shape.STEPPED, Building.Shape.SLAB],
		"finishes": [Building.Finish.BRICK, Building.Finish.BRICK, Building.Finish.FLAT, Building.Finish.PANELS],
		"lit": Vector2(0.2, 0.5), "park": 0.30, "plaza": 0.12, "trees": 1.0, "courtyard": 0.6,
		"cafes": 1, "planters": 3, "clutter": 0, "weathering": Vector2(0.15, 0.5), "line_white": 0.2,
		"paving": [["paving", 3.0, Color(1.02, 1.00, 0.97)], ["pavers", 2.5, Color(1.15, 1.11, 1.06)]],
		"tree_weights": [0.24, 0.42, 0.09, 0.18, 0.07], "jacarandas": 0.09,
		"lamp_tint": Color(0.8, 0.86, 0.8),
		"mall": 0.03, "bigbox": 0.0, "pads": 0.05, "lawn": true, "people": 16, "parked": 6, "palms": 0.3,
	},
	District.INDUSTRIAL: {
		"height": Vector2(6.0, 16.0), "lot": Vector2(34.0, 60.0), "gap": Vector2(6.0, 12.0),
		"shapes": [Building.Shape.WAREHOUSE, Building.Shape.WAREHOUSE, Building.Shape.SLAB],
		"finishes": [Building.Finish.PANELS, Building.Finish.FLAT],
		"lit": Vector2(0.05, 0.2), "park": 0.02, "plaza": 0.0, "trees": 0.1, "courtyard": 0.0,
		"cafes": 0, "planters": 0, "clutter": 7, "weathering": Vector2(0.5, 1.0), "line_white": 0.7,
		"paving": [["sidewalk", 3.0, Color(1.41, 1.41, 1.41)], ["concrete", 4.0, Color(0.82, 0.82, 0.82)]],
		"tree_weights": [0.27, 0.27, 0.31, 0.13, 0.02], "jacarandas": 0.02,
		"lamp_tint": Color(0.9, 0.9, 0.9),
		"mall": 0.04, "bigbox": 0.1, "pads": 0.08, "lawn": false, "people": 3, "parked": 5, "palms": 0.04,
	},
}

var seed: int = 0
var block_size_range: Vector2 = Vector2(70.0, 120.0)
var street_width: float = 14.0
var avenue_width: float = 24.0
## Every Nth road (roughly) is an avenue.
var avenue_every: int = 3
var sidewalk_width: float = 4.0
## District rings, in meters from the origin.
var downtown_radius: float = 180.0
var midtown_radius: float = 380.0
## Beyond this radius, one seeded quadrant is industrial.
var industrial_start_radius: float = 260.0

## Optional big-picture map. When set, it decides districts and zones (ocean, beach, hills).
var macro: MacroMap

## The downtown street grid, the same for every seed: [position, width] per road, per axis
## (AXIS_X: the north-south avenues, AXIS_Z: the east-west streets). The downtown towers are
## fixed landmarks (LandmarkDowntown) and each stands in a particular block, so the blocks have
## to be where the towers are whatever the seed - on any other seed an unpinned grid ran roads
## straight through them. These are the default seed's own roads, to the last bit, so that city
## does not move by a millimetre; on other seeds the seeded blocks either side stretch or split
## to meet them (_next_road).
const PINNED_ROADS := [
	[[409.37879180908203, 14.0], [507.7798385620117, 24.0], [589.1617813110352, 24.0], [660.7405776977539, 24.0],
		[734.894157409668, 24.0], [824.2449493408203, 14.0], [932.5944137573242, 24.0]],
	[[228.40353, 24.0], [337.9709, 14.0], [417.44156, 14.0], [536.65106, 24.0],
		[654.6276397705078, 24.0], [730.2834, 14.0], [837.092414855957, 24.0], [907.1332855224609, 14.0]],
]

var _industrial_quadrant: int = -1
var _road_pos: Array[Dictionary] = [{0: 0.0}, {0: 0.0}]
var _road_width: Array[Dictionary] = [{}, {}]
var _blocks: Dictionary = {}
var _intersections: Dictionary = {}


func industrial_quadrant() -> int:
	if _industrial_quadrant < 0:
		_industrial_quadrant = _rng_for(7, 0, 0).randi_range(0, 3)
	return _industrial_quadrant


# --- Roads -------------------------------------------------------------------------

## Center coordinate of road `i` on an axis. Road 0 is at 0 on both axes.
func road_pos(axis: int, i: int) -> float:
	var cache: Dictionary = _road_pos[axis]
	if cache.has(i):
		return cache[i]
	if i > 0:
		var j := i
		while not cache.has(j):
			j -= 1
		var pos: float = cache[j]
		while j < i:
			pos = _next_road(axis, j, pos)
			j += 1
			cache[j] = pos
		return pos
	var j := i
	while not cache.has(j):
		j += 1
	var pos: float = cache[j]
	while j > i:
		j -= 1
		pos -= _block_size(axis, j)
		cache[j] = pos
	return pos


## The road after road `j` (at `pos`) going up the axis: a seeded block on, unless that would
## land within a minimum block of the next pinned road or past it, in which case the pinned road
## (or, when the gap is more than a block and a half, a road halfway to it first).
func _next_road(axis: int, j: int, pos: float) -> float:
	var step := _block_size(axis, j)
	for pin: Array in PINNED_ROADS[axis]:
		var at: float = pin[0]
		if at <= pos + 1.0:
			continue
		if pos + step > at - block_size_range.x:
			var gap := at - pos
			return pos + gap * 0.5 if gap > block_size_range.y + 10.0 else at
		return pos + step
	return pos + step


func road_width(axis: int, i: int) -> float:
	var cache: Dictionary = _road_width[axis]
	if cache.has(i):
		return cache[i]
	var at := road_pos(axis, i)
	for pin: Array in PINNED_ROADS[axis]:
		if absf(float(pin[0]) - at) < 0.01:
			cache[i] = float(pin[1])
			return cache[i]
	var is_avenue := posmod(i, avenue_every) == avenue_every - 1 or _rng_for(2 + axis, i, 0).randf() < 0.15
	var w := avenue_width if is_avenue else street_width
	cache[i] = w
	return w


## Width of the parking lane along each kerb (metres). It was 4.4, nearly twice a real one, and it
## pushed the kerb-side traffic lane straight through the parked cars: on a 14 m street the lane
## centre and the parked cars were 13 cm apart, so every passing car shoved or launched them.
const PARKING_LANE := 2.6


## Where parked cars stand, from the road's centre line: in the parking lane, against the kerb.
static func parking_offset(width: float) -> float:
	return width * 0.5 - PARKING_LANE * 0.5


## Centre of travel lane `n` (0 = beside the centre line) of `lanes`, from the centre line. The
## lanes share what is left between the centre line and the parking lane, so traffic, the lane
## arrows and the parked cars can never overlap.
static func lane_center(width: float, lanes: int, n: int) -> float:
	return (width * 0.5 - PARKING_LANE - 0.2) / float(lanes) * (float(n) + 0.5)


## Size of the block between road `i` and road `i + 1` on an axis.
func _block_size(axis: int, i: int) -> float:
	return _rng_for(4 + axis, i, 0).randf_range(block_size_range.x, block_size_range.y)


## Index of the block containing a world XZ position (block (ix, iz) spans road ix..ix+1, iz..iz+1).
func block_index_at(pos: Vector2) -> Vector2i:
	return Vector2i(_index_at(AXIS_X, pos.x), _index_at(AXIS_Z, pos.y))


func _index_at(axis: int, value: float) -> int:
	var i := 0
	while value >= road_pos(axis, i + 1):
		i += 1
	while value < road_pos(axis, i):
		i -= 1
	return i


# --- Blocks and intersections --------------------------------------------------------

## {"rect": Rect2 (between road edges), "ix", "iz", "district", "kind", "seed"}
func block(ix: int, iz: int) -> Dictionary:
	var key := Vector2i(ix, iz)
	if _blocks.has(key):
		return _blocks[key]
	var x0 := road_pos(AXIS_X, ix) + road_width(AXIS_X, ix) * 0.5
	var x1 := road_pos(AXIS_X, ix + 1) - road_width(AXIS_X, ix + 1) * 0.5
	var z0 := road_pos(AXIS_Z, iz) + road_width(AXIS_Z, iz) * 0.5
	var z1 := road_pos(AXIS_Z, iz + 1) - road_width(AXIS_Z, iz + 1) * 0.5
	var rect := Rect2(x0, z0, x1 - x0, z1 - z0)
	var district := district_at(rect.get_center())
	var params: Dictionary = DISTRICTS[district]
	var rng := _rng_for(3, ix, iz)
	var roll := rng.randf()
	var kind := BlockKind.BUILDINGS
	var mall: float = params.get("mall", 0.0)
	var bigbox: float = params.get("bigbox", 0.0)
	if roll < params.park:
		kind = BlockKind.PARK
	elif roll < params.park + params.plaza:
		kind = BlockKind.PLAZA
	elif roll < params.park + params.plaza + mall and rect.size.x > 60.0 and rect.size.y > 60.0:
		kind = BlockKind.MALL
	elif roll < params.park + params.plaza + mall + bigbox and rect.size.x > 80.0 and rect.size.y > 80.0:
		kind = BlockKind.BIGBOX
	var result := {"rect": rect, "ix": ix, "iz": iz, "district": district, "kind": kind, "seed": rng.randi()}
	# Ground a landmark owns outright (a replica area's site): the chunk builds that instead.
	var site := site_at_block(ix, iz)
	if not site.is_empty():
		result["site"] = site.id
	_blocks[key] = result
	return result


# --- Landmark sites ----------------------------------------------------------------------------
# A landmark entry with a "site" (Landmarks.all(); LandmarkMacArthurPark is the first) owns whole
# blocks outright: its desired edges are snapped to the nearest roads, every road between those
# four is CLOSED except the ones it keeps (MacArthur Park keeps Wilshire), and its chunks build the
# landmark's ground instead of a block. Closing rather than removing the roads keeps every road
# index and position - and so every block seed in the city - exactly where it was.

var _sites: Array = []
var _sites_ready: bool = false


## The snapped sites: {id, ix0, ix1, iz0, iz1 (the four boundary roads), keep_z (kept road
## indices), rect (kerb to kerb), halves (the rects between the kept roads, north to south),
## keep_rects (the kept roads' carriageways across the site)}. Only with a macro map: a bare
## plan (the test room, unit checks) has no replica areas.
func sites() -> Array:
	if _sites_ready or macro == null:
		return _sites
	_sites_ready = true
	for lm in Landmarks.all():
		if lm.has("site"):
			var s := _snap_site(lm.id, lm.site)
			if not s.is_empty():
				_sites.append(s)
	return _sites


func site_by_id(id: String) -> Dictionary:
	for s: Dictionary in sites():
		if s.id == id:
			return s
	return {}


func _nearest_road(axis: int, coord: float) -> int:
	var i := _index_at(axis, coord)
	return i + 1 if absf(road_pos(axis, i + 1) - coord) < absf(road_pos(axis, i) - coord) else i


func _snap_site(id: String, spec: Dictionary) -> Dictionary:
	var ix0 := _nearest_road(AXIS_X, spec.west_x)
	var ix1 := _nearest_road(AXIS_X, spec.east_x)
	var iz0 := _nearest_road(AXIS_Z, spec.north_z)
	var iz1 := _nearest_road(AXIS_Z, spec.south_z)
	if ix1 - ix0 < 1 or iz1 - iz0 < 1:
		return {}
	var keep: Array[int] = []
	for kz in spec.get("keep_z", []):
		var k := _nearest_road(AXIS_Z, kz)
		if k > iz0 and k < iz1 and not keep.has(k):
			keep.append(k)
	keep.sort()
	var x0 := road_pos(AXIS_X, ix0) + road_width(AXIS_X, ix0) * 0.5
	var x1 := road_pos(AXIS_X, ix1) - road_width(AXIS_X, ix1) * 0.5
	var z0 := road_pos(AXIS_Z, iz0) + road_width(AXIS_Z, iz0) * 0.5
	var z1 := road_pos(AXIS_Z, iz1) - road_width(AXIS_Z, iz1) * 0.5
	var halves: Array[Rect2] = []
	var keep_rects: Array[Rect2] = []
	var top := z0
	for k in keep:
		var kz0 := road_pos(AXIS_Z, k) - road_width(AXIS_Z, k) * 0.5
		var kz1 := road_pos(AXIS_Z, k) + road_width(AXIS_Z, k) * 0.5
		halves.append(Rect2(x0, top, x1 - x0, kz0 - top))
		keep_rects.append(Rect2(x0, kz0, x1 - x0, kz1 - kz0))
		top = kz1
	halves.append(Rect2(x0, top, x1 - x0, z1 - top))
	return {"id": id, "ix0": ix0, "ix1": ix1, "iz0": iz0, "iz1": iz1, "keep_z": keep,
		"rect": Rect2(x0, z0, x1 - x0, z1 - z0), "halves": halves, "keep_rects": keep_rects,
		"streets": spec.get("streets", {})}


## The site whose blocks include block (ix, iz), or {}.
func site_at_block(ix: int, iz: int) -> Dictionary:
	for s: Dictionary in sites():
		if ix >= s.ix0 and ix < s.ix1 and iz >= s.iz0 and iz < s.iz1:
			return s
	return {}


## False where road `index` on `axis` runs through a site's ground at `along` (the coordinate
## along the road): no traffic, parking, crossings or street furniture there. The perimeter roads,
## the kept roads and a closed road's crossing of a kept one stay open.
func road_open(axis: int, index: int, along: float) -> bool:
	for s: Dictionary in sites():
		if axis == AXIS_X:
			if index <= s.ix0 or index >= s.ix1:
				continue
			if along <= road_pos(AXIS_Z, s.iz0) + road_width(AXIS_Z, s.iz0) * 0.5 or along >= road_pos(AXIS_Z, s.iz1) - road_width(AXIS_Z, s.iz1) * 0.5:
				continue
			var on_kept := false
			for k: int in s.keep_z:
				if absf(along - road_pos(AXIS_Z, k)) < road_width(AXIS_Z, k) * 0.5:
					on_kept = true
			if not on_kept:
				return false
		else:
			if index <= s.iz0 or index >= s.iz1 or (s.keep_z as Array).has(index):
				continue
			if along <= road_pos(AXIS_X, s.ix0) + road_width(AXIS_X, s.ix0) * 0.5 or along >= road_pos(AXIS_X, s.ix1) - road_width(AXIS_X, s.ix1) * 0.5:
				continue
			return false
	return true


## The road on `axis` whose centre line is nearest `coord`, open at `along`? (For callers that
## know a position rather than an index.)
func road_open_at(axis: int, coord: float, along: float) -> bool:
	return road_open(axis, _nearest_road(axis, coord), along)


## True where world XZ `p` is on a site's own ground (not on one of the roads it keeps open).
func in_site(p: Vector2) -> bool:
	for s: Dictionary in sites():
		var r: Rect2 = s.rect
		if not r.has_point(p):
			continue
		for k: Rect2 in s.keep_rects:
			if k.has_point(p):
				return false
		return true
	return false


## True when any of the four roads meeting at intersection (ix, iz) is closed on the arm leaving
## it (a T where a closed road meets a site's edge), so no crossing, signal or sign is built there.
func junction_closed(ix: int, iz: int) -> bool:
	if sites().is_empty():
		return false
	var x := road_pos(AXIS_X, ix)
	var z := road_pos(AXIS_Z, iz)
	var wx := road_width(AXIS_X, ix)
	var wz := road_width(AXIS_Z, iz)
	return not (road_open(AXIS_X, ix, z - wz * 0.5 - 2.0) and road_open(AXIS_X, ix, z + wz * 0.5 + 2.0)
		and road_open(AXIS_Z, iz, x - wx * 0.5 - 2.0) and road_open(AXIS_Z, iz, x + wx * 0.5 + 2.0))


## {"pos": Vector2, "kind": Intersection, "size": Vector2 (road widths x, z), "seed"}
func intersection(ix: int, iz: int) -> Dictionary:
	var key := Vector2i(ix, iz)
	if _intersections.has(key):
		return _intersections[key]
	var wx := road_width(AXIS_X, ix)
	var wz := road_width(AXIS_Z, iz)
	var rng := _rng_for(6, ix, iz)
	var roll := rng.randf()
	var both_avenues := wx >= avenue_width - 0.1 and wz >= avenue_width - 0.1
	var any_avenue := wx >= avenue_width - 0.1 or wz >= avenue_width - 0.1
	var kind := Intersection.PLAIN
	if ix == 0 and iz == 0:
		kind = Intersection.SIGNALS # the spawn point; keep it open
	elif both_avenues:
		kind = Intersection.ROUNDABOUT if roll < 0.3 else Intersection.SIGNALS
	elif any_avenue:
		kind = Intersection.SIGNALS if roll < 0.7 else Intersection.STOP_SIGNS
	else:
		kind = Intersection.STOP_SIGNS if roll < 0.6 else Intersection.PLAIN
	var result := {"pos": Vector2(road_pos(AXIS_X, ix), road_pos(AXIS_Z, iz)), "kind": kind, "size": Vector2(wx, wz), "seed": rng.randi()}
	_intersections[key] = result
	return result


func zone_at(pos: Vector2) -> MacroMap.Zone:
	return macro.zone_at(pos) if macro else MacroMap.Zone.CITY


func height_at(pos: Vector2) -> float:
	return macro.height_at(pos) if macro else 0.0


func district_at(pos: Vector2) -> District:
	if macro:
		return macro.district_at(pos)
	var r := pos.length()
	var quadrant := (0 if pos.x >= 0.0 else 1) + (0 if pos.y >= 0.0 else 2)
	if quadrant == industrial_quadrant() and r > industrial_start_radius:
		return District.INDUSTRIAL
	if r < downtown_radius:
		return District.DOWNTOWN
	if r < midtown_radius:
		return District.MIDTOWN
	return District.SUBURBS


static func district_name(d: District) -> String:
	return DISTRICT_NAMES[d]


## Lots on a block, and the height each one's building reaches. DETERMINISTIC from
## (seed, ix, iz) alone.
##
## This used to live in CityChunk and draw from the chunk's own rng - the one already part-spent
## on the palm roll, the jacaranda roll and the paving roll - so the lots a block would get could
## not be known without replaying that whole sequence. That is why the far skyline drew INVENTED
## massing and changed as you approached it: it could not see the real buildings. Seeded here,
## off `_rng_for`, the coarse tier and the detailed city ask the same question and get the same
## answer, so the skyline you see from the air is the skyline you land in.
##
## Not cached: it is pure arithmetic, a chunk asks once, and a cache across the thousands of
## blocks the far tier walks would cost more memory than the work it saves.
func lots(ix: int, iz: int) -> Array[Dictionary]:
	var b := block(ix, iz)
	# A landmark's site builds its own ground; nothing of the block's is built there.
	if b.has("site"):
		return []
	var rect: Rect2 = b.rect
	var params: Dictionary = DISTRICTS[b.district]
	var rng := _rng_for(11, ix, iz)
	var inner := rect.grow(-sidewalk_width)
	var lot_range: Vector2 = params.lot
	var lot_w := rng.randf_range(lot_range.x, lot_range.y)
	var lot_d := rng.randf_range(lot_range.x, lot_range.y)
	var nx := maxi(1, floori(inner.size.x / lot_w))
	var nz := maxi(1, floori(inner.size.y / lot_d))
	var cell := Vector2(inner.size.x / nx, inner.size.y / nz)
	var gap_range: Vector2 = params.gap
	# Pocket gardens thin out toward the core (the roll is made either way, so nothing moves).
	var courtyard: float = float(params.courtyard)
	if macro and params.has("core_courtyard"):
		courtyard = lerpf(courtyard, float(params.core_courtyard), macro.skyline_boost(rect.get_center()))
	var blocked: Array[Rect2] = []
	if macro:
		for lm in Landmarks.all():
			# A site's own blocks are handled above; its radius is for the relief and the map.
			if lm.has("site"):
				continue
			var r: float = lm.radius
			var foot := Rect2((lm.anchor as Vector2) - Vector2(r, r), Vector2(r * 2.0, r * 2.0))
			if foot.intersects(rect):
				blocked.append(foot)
		# Nothing is built under the final approach off the end of the arrival runway.
		var clear: Rect2 = macro.runway_clear_zone()
		if clear.intersects(rect):
			blocked.append(clear)
	var out: Array[Dictionary] = []
	for lx in nx:
		for lz in nz:
			var edge := lx == 0 or lz == 0 or lx == nx - 1 or lz == nz - 1
			var yard: bool = (not edge) and rng.randf() < courtyard
			var gap := rng.randf_range(gap_range.x, gap_range.y)
			var lot_size := cell - Vector2(gap, gap)
			if lot_size.x < 6.0 or lot_size.y < 6.0:
				continue
			var lot_center := inner.position + Vector2(cell.x * (lx + 0.5), cell.y * (lz + 0.5))
			var lot_seed := rng.randi()
			var lot_rect := Rect2(lot_center - lot_size * 0.5, lot_size)
			var hit := false
			for bl in blocked:
				if bl.intersects(lot_rect):
					hit = true
			if hit:
				continue
			out.append({"seed": lot_seed, "size": lot_size, "center": lot_center, "edge": edge, "yard": yard})
	return out


## The height a lot's building reaches. The band is rolled ONCE per lot and bent by pow(u, curve)
## so most lots land near the bottom and a handful reach the top - a uniform draw has no tail and
## makes the top of the city one flat line. Shared, so the far tier's silhouette IS the city's.
func lot_height(lot_seed: int, district: int, boost: float) -> float:
	var params: Dictionary = DISTRICTS[district]
	var heights: Vector2 = params.height
	var core: Vector2 = params.get("core_height", Vector2(heights.x * 1.45, heights.y * 2.3))
	var h_low: float = lerpf(heights.x, core.x, boost)
	var h_top: float = lerpf(heights.y, core.y, boost)
	var curve: float = 1.0 + log(h_top / maxf(h_low, 1.0)) / log(4.0)
	if params.has("core_curve"):
		curve = lerpf(curve, float(params.core_curve), boost)
	return lerpf(h_low, h_top, pow(float(absi(hash([lot_seed, "massing"])) % 100003) / 100003.0, curve))


## The shapes a lot's building may take: the district's, or its core set where the skyline boost
## is high (see DISTRICTS DOWNTOWN "core_shapes").
static func lot_shapes(district: int, boost: float) -> Array:
	var params: Dictionary = DISTRICTS[district]
	if boost > 0.55 and params.has("core_shapes"):
		return params.core_shapes
	return params.shapes


## ... and the finishes it may wear ("core_finishes" in the same place).
static func lot_finishes(district: int, boost: float) -> Array:
	var params: Dictionary = DISTRICTS[district]
	if boost > 0.55 and params.has("core_finishes"):
		return params.core_finishes
	return params.finishes


func _rng_for(kind: int, a: int, b: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed, kind, a, b])
	return rng


const STREET_NAMES := ["Maple", "Oak", "Cedar", "Pine", "Elm", "Birch", "Willow", "Palm", "Sunset", "Harbor", "Ocean", "Vista", "Canyon", "Ridge", "Mesa", "Laurel", "Olive", "Grand", "Union", "Market", "Main", "Park", "Hill", "Lake", "River", "Spring", "Summit", "Valley", "Meadow", "Orchard", "Bay", "Beacon", "Crest", "Fairview", "Glen", "Highland", "Juniper", "Linden", "Magnolia", "Pacific"]
const ORDINALS := ["1st", "2nd", "3rd", "4th", "5th", "6th", "7th", "8th", "9th", "10th", "11th", "12th", "14th", "15th", "16th", "17th", "18th", "19th", "20th", "21st"]


## A seeded name for a road: north-south roads (AXIS_X) are avenues and boulevards, east-west
## roads (AXIS_Z) are streets, a third of them numbered.
func road_name(axis: int, index: int) -> String:
	# A replica area's real street names (public names are fair game; CLAUDE.md).
	for s: Dictionary in sites():
		var streets: Dictionary = s.streets
		if streets.is_empty():
			continue
		if axis == AXIS_X and index == int(s.ix0) and streets.has("west"):
			return streets.west
		if axis == AXIS_X and index == int(s.ix1) and streets.has("east"):
			return streets.east
		if axis == AXIS_Z and index == int(s.iz0) and streets.has("north"):
			return streets.north
		if axis == AXIS_Z and index == int(s.iz1) and streets.has("south"):
			return streets.south
		if axis == AXIS_Z and (s.keep_z as Array).has(index) and streets.has("middle"):
			return streets.middle
	var rng := _rng_for(9, axis, index)
	var avenue := road_width(axis, index) > street_width + 1.0
	if axis == AXIS_Z and rng.randf() < 0.35:
		return ORDINALS[posmod(index, ORDINALS.size())] + " ST"
	var base: String = STREET_NAMES[rng.randi() % STREET_NAMES.size()]
	if axis == AXIS_X:
		return base.to_upper() + (" BLVD" if avenue else " AVE")
	return base.to_upper() + (" BLVD" if avenue else " ST")
