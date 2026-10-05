class_name LandmarkMacArthurPark
extends RefCounted
## MacArthur Park, Westlake - the first REPLICA AREA (docs/GAME_PLAN.md, 2026-09-24): a real place
## authored from real references, with seeded city round it. The park is two halves either side of
## Wilshire Boulevard, bounded by Park View Street, 6th Street, Alvarado Street and 7th Street: the
## north half holds the playing fields and the bandshell, the south half is the spring-fed lake with
## its fountain jet in the middle, ringed by a promenade and by tall Mexican fan palms, with the old
## boathouse on the north shore and lawns at both ends.
##
## Everything real about it lives in ONE table, SITE, so the follow-up that re-lays downtown at
## true scale moves it by editing numbers: where it really is (lat/long), where downtown's reference
## point really is, the real offset between them in metres, its real size and the real heading of
## Wilshire through it - and, separately, where it stands on today's compressed map.
##
## How it sits on the street grid: the landmark entry carries a `site`, which CityPlan snaps to the
## nearest whole blocks (CityPlan.sites()). Every road between the four boundary roads is CLOSED
## except Wilshire (CityPlan.road_open()), so no car, parked car, crossing or street lamp lands in
## the lake, and the park's own chunks build the park instead of a block (site_steps()). The ground,
## the lake, the paths, the palms and the crowd are built PER CHUNK - each chunk the part inside
## its own rect - so a park four hundred metres across streams with the city instead of appearing
## whole around one chunk. Only the fountain and the boathouse are built with the landmark itself
## (build(), by the chunk holding the anchor), with a far version that stands in for them.
##
## Names: MacArthur Park, Wilshire and the four streets are public place names (the project's rule:
## geography is fair game, trade dress is not). No business names or logos.

# --- The data table -----------------------------------------------------------------------------

const SITE := {
	"id": "macarthur_park",
	"name": "MacArthur Park",
	# The real place (WGS84: the park's OSM centroid, DowntownReal.POINTS.macarthur_park) and the
	# downtown reference point the real offset is measured from (DowntownReal.REAL_ORIGIN).
	"latlon": Vector2(34.0588418, -118.2776964),
	"downtown_ref": "Pershing Square",
	"downtown_ref_latlon": Vector2(34.0483957, -118.2530218),
	# Real offset from the downtown reference in metres, compass axes: +x east, +z SOUTH (north is
	# -Z), untouched by the grid's turn (DowntownReal.real_en(): 92,332 m/deg of longitude and
	# 110,923 m/deg of latitude at 34.05 N). Turned onto the grid it is 2,510 m grid-west and
	# 483 m grid-south of Pershing Square; the park is placed on the straightened Wilshire (below).
	"real_offset_m": Vector2(-2278.0, -1159.0),
	# Real extent: along Wilshire (Park View to Alvarado) x across it (6th to 7th), and area.
	"real_size_m": Vector2(460.0, 310.0),
	"real_area_acres": 35.0,
	# Compass heading of Wilshire through the park, travelling west. The game turns the whole real
	# grid onto its axes (DowntownReal.GRID_BEARING_DEG), so in game Wilshire runs along -X
	# (`yaw_deg` 0); the 8-degree bend west of the 110 is straightened out.
	"real_wilshire_heading_deg": 297.0,
	# Lake: about 14 ft (4.3 m) deep and spring fed; the fountain is one tall jet in the middle.
	"real_lake_depth_m": 4.3,
	# --- In game: downtown at 1:1 (DowntownReal.MACARTHUR) --------------------------------------
	# The site CityPlan snaps to whole blocks: the edges are the real streets, pinned (world x of
	# Park View and Alvarado, world z of 6th and 7th) and the Wilshire centreline, which is kept
	# open - DowntownReal's grid metres through its GAME_ANCHOR (2800, 102.7): west_u -2700,
	# east_u -2313, north_v 97.5, south_v 301.3, wilshire_v 210. The park is at its true distance
	# along the straightened Wilshire from downtown, 280 m grid-north of the real one (the real
	# streets bend 8 degrees west of the 110; see DowntownReal's header).
	"anchor": Vector2(293.5, 312.7),
	"west_x": 100.0, "east_x": 487.0,
	"north_z": 200.2, "south_z": 404.0,
	"wilshire_z": 312.7,
	"yaw_deg": 0.0,
	"streets": {"west": "PARK VIEW ST", "east": "ALVARADO ST", "north": "6TH ST",
		"middle": "WILSHIRE BLVD", "south": "7TH ST"},
	# The lake outline and the features, in the SOUTH half's own 0..1 frame (u west to east,
	# v Wilshire side to 7th Street side), so they follow whatever size the snapped site has.
	"lake": [
		Vector2(0.08, 0.40), Vector2(0.13, 0.22), Vector2(0.27, 0.13), Vector2(0.44, 0.15),
		Vector2(0.58, 0.11), Vector2(0.74, 0.12), Vector2(0.87, 0.20), Vector2(0.93, 0.38),
		Vector2(0.90, 0.58), Vector2(0.80, 0.75), Vector2(0.63, 0.83), Vector2(0.47, 0.79),
		Vector2(0.31, 0.85), Vector2(0.16, 0.77), Vector2(0.09, 0.60),
	],
	"fountain": Vector2(0.52, 0.47),
	"boathouse": Vector2(0.34, 0.0),
	# North half features in its own 0..1 frame.
	"field": Rect2(0.04, 0.16, 0.16, 0.70),
	"bandshell": Vector2(0.60, 0.16),
	# Where the paths of the two halves meet across Wilshire (u along the park).
	"crossing_u": 0.47,
}

# --- Tunables ------------------------------------------------------------------------------------
# A static builder with no node to hang exports on (like StreetDetail): the knobs are here.

## Surface heights, metres above the city datum (the relief is flat round a landmark).
const LAWN_TOP := CityChunk.SIDEWALK_TOP + 0.02
const PATH_TOP := LAWN_TOP + 0.025
const COPING_TOP := LAWN_TOP + 0.07
## The lake: its surface, the floor you stand on in it (a wading depth, since nobody swims in
## this game - the real lake is 4.3 m) and the foot of the basin wall under the water. The floor
## is below the city's ground box (CityStreamer's GroundBody, top at 0), which the lake volume
## lets bodies pass through (_sink); keep it above CityStreamer.under_city_ground()'s 1.5 m, or
## the player standing on it is "under the city" and gets lifted out.
const WATER_Y := -0.28
const FLOOR_Y := -1.20
const WALL_BOTTOM := -1.7
## Width of the concrete coping round the lake and of the promenade outside it (metres).
const COPING_W := 0.75
const PROMENADE_W := 5.0
## Width of the pavement ring round each half, like a block's.
const PAVEMENT := 4.0
## Lawn cell size near (FULL) and far (LOD), metres.
const CELL_FULL := 2.0
const CELL_LOD := 6.0
## Palms round the lake: how far out from the waterline and how far apart. And along the park's
## streets.
const PALM_RING_OFFSET := 8.5
const PALM_RING_STEP := 12.5
const PERIMETER_PALM_STEP := 15.0
const PERIMETER_PALM_INSET := 6.0
## Lamps and benches along the promenade and the paths.
const LAMP_STEP := 26.0
const BENCH_STEP := 18.0
## Broadleaf trees scattered on the lawns, per 1000 square metres of lawn.
const TREES_PER_1000 := 1.1
## People walking the park: the north half, and the promenades round the lake.
const CROWD_NORTH := 14
const CROWD_SOUTH := 16
## The fountain: how high the jet throws (m) and its particles.
const FOUNTAIN_HEIGHT := 22.0
const FOUNTAIN_PARTICLES := 420
## The promenade stops this far either side of the boathouse, whose veranda carries the walk.
const BOATHOUSE_CLEAR := 13.5
## Draw distances (m).
const FOUNTAIN_DRAW := 1400.0
const PATH_DRAW := 260.0

static var _layouts: Dictionary = {}
static var _lake_mat: ShaderMaterial


## The entry Landmarks.all() lists: id, anchor, a radius for the relief flattening and the minimap,
## and the site CityPlan snaps to the grid.
## On since 2026-09-24 evening. It was held off because traffic leaked onto its closed roads:
## a car that had to turn off a closed road, and found the lane it was turning into taken, went
## straight on instead (TrafficManager._drive_street now makes it wait), and the checks re-centred
## the world outside the physics tick, which threw every traffic car hundreds of metres (see
## CityStreamer.recenter()). Off, there is no entry,
## no site, and every road is open. Set it before the city scene loads (Landmarks.all() is built
## once).
static var enabled: bool = true


static func entry() -> Dictionary:
	return {
		"id": SITE.id, "anchor": SITE.anchor, "radius": 270.0,
		"area": {"west_x": SITE.west_x, "east_x": SITE.east_x, "north_z": SITE.north_z,
			"south_z": SITE.south_z, "keep_z": [SITE.wilshire_z], "streets": SITE.streets},
	}


# --- Layout ---------------------------------------------------------------------------------------

## Everything the park's builders place, in world XZ, worked out once per plan from the snapped
## site: the two halves, the lake, the paths, the palms, the trees, the benches, the lamps, the crowd
## rects. {} when the plan has no such site (no macro map: the test room).
static func layout(plan: CityPlan) -> Dictionary:
	var key := plan.get_instance_id()
	if _layouts.has(key):
		return _layouts[key]
	var site := plan.site_by_id(SITE.id)
	if site.is_empty():
		return {}
	var halves: Array = site.halves
	var north: Rect2 = halves[0]
	var south: Rect2 = halves[1]
	var n_in := north.grow(-PAVEMENT)
	var s_in := south.grow(-PAVEMENT)
	var lay := {"north": north, "south": south, "north_in": n_in, "south_in": s_in, "site": site}
	# The lake, mapped into the south half with room for the promenade and the palms, then smoothed.
	var margin := PROMENADE_W + COPING_W + 2.0
	var frame := s_in.grow(-margin)
	var pts := PackedVector2Array()
	for p: Vector2 in SITE.lake:
		pts.append(frame.position + frame.size * p)
	pts = _chaikin(_chaikin(_chaikin(pts)))
	if Geometry2D.is_polygon_clockwise(pts):
		pts.reverse()
	lay.lake = pts
	lay.lake_bounds = _bounds(pts)
	lay.coping = _offset(pts, COPING_W)
	lay.promenade_mid = _offset(pts, COPING_W + PROMENADE_W * 0.5)
	lay.palm_ring = _offset(pts, PALM_RING_OFFSET)
	lay.fountain = frame.position + frame.size * (SITE.fountain as Vector2)
	# The boathouse on the north shore: the waterline point nearest the given spot, facing the lake.
	var want: Vector2 = frame.position + frame.size * (SITE.boathouse as Vector2)
	var best := pts[0]
	for p in pts:
		if p.distance_to(want) < best.distance_to(want):
			best = p
	lay.boathouse = best
	lay.boathouse_yaw = _yaw_toward(best, lay.fountain)
	var f: Rect2 = SITE.field
	lay.field = Rect2(n_in.position + n_in.size * f.position, n_in.size * f.size)
	lay.bandshell = n_in.position + n_in.size * (SITE.bandshell as Vector2) + Vector2(0.0, 9.0)
	var wz: float = site.keep_rects[0].get_center().y if not (site.keep_rects as Array).is_empty() else (north.end.y + south.position.y) * 0.5
	lay.wilshire_z = wz
	lay.wilshire_rect = Rect2(north.position.x, north.end.y, north.size.x, south.position.y - north.end.y)
	lay.crossing = Vector2(north.position.x + north.size.x * float(SITE.crossing_u), wz)
	lay.paths = _paths(lay)
	lay.palms = _palm_spots(lay)
	lay.trees = _tree_spots(lay, plan.seed)
	lay.benches = _bench_spots(lay)
	lay.lamps = _lamp_spots(lay)
	lay.crowd = _crowd_rects(lay)
	lay.beds = _flower_beds(lay)
	_layouts[key] = lay
	return lay


## Chaikin corner cutting: one pass turns a polygon's corners into two points each.
static func _chaikin(pts: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := pts.size()
	for i in n:
		var a := pts[i]
		var b := pts[(i + 1) % n]
		out.append(a.lerp(b, 0.25))
		out.append(a.lerp(b, 0.75))
	return out


static func _bounds(pts: PackedVector2Array) -> Rect2:
	var r := Rect2(pts[0], Vector2.ZERO)
	for p in pts:
		r = r.expand(p)
	return r


## `pts` (counter-clockwise in Godot's 2D sense) pushed out by `d` metres along its vertex normals.
## The lake is smooth and gently curved, so a pointwise offset is exact enough and keeps the point
## count (and so the correspondence the promenade ribbon uses).
static func _offset(pts: PackedVector2Array, d: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := pts.size()
	for i in n:
		var prev := pts[(i - 1 + n) % n]
		var next := pts[(i + 1) % n]
		var t := (next - prev).normalized()
		# Counter-clockwise with y down (world z): the outward normal is (t.y, -t.x).
		out.append(pts[i] + Vector2(t.y, -t.x) * d)
	return out


static func _yaw_toward(from: Vector2, to: Vector2) -> float:
	var d := to - from
	return atan2(-d.x, -d.y)


## True when `p` is in the lake or within `pad` metres of its waterline.
static func in_lake(lay: Dictionary, p: Vector2, pad: float = 0.0) -> bool:
	var b: Rect2 = lay.lake_bounds
	if not b.grow(pad).has_point(p):
		return false
	var lake: PackedVector2Array = lay.lake
	if Geometry2D.is_point_in_polygon(p, lake):
		return true
	if pad <= 0.0:
		return false
	for i in lake.size():
		if Geometry2D.get_closest_point_to_segment(p, lake[i], lake[(i + 1) % lake.size()]).distance_to(p) < pad:
			return true
	return false


## The walks: the promenade round the lake, links from the corners and from the Wilshire crossing
## down to it, a walk along the north half's Wilshire side, a loop round the playing field and a
## path up to 6th Street. [{"pts": PackedVector2Array, "width": float, "closed": bool}]
static func _paths(lay: Dictionary) -> Array:
	var out: Array = []
	var s_in: Rect2 = lay.south_in
	var n_in: Rect2 = lay.north_in
	var ring: PackedVector2Array = lay.promenade_mid
	out.append({"pts": ring, "width": PROMENADE_W, "closed": true})
	var crossing: Vector2 = lay.crossing
	# From the crossing into the south half, to the nearest point of the promenade.
	out.append({"pts": PackedVector2Array([Vector2(crossing.x, s_in.position.y - PAVEMENT * 0.5), _nearest(ring, Vector2(crossing.x, s_in.position.y))]), "width": 4.0, "closed": false})
	# Corner links.
	for c: Vector2 in [s_in.position, Vector2(s_in.end.x, s_in.position.y), Vector2(s_in.position.x, s_in.end.y), s_in.end]:
		out.append({"pts": PackedVector2Array([c, _nearest(ring, c)]), "width": 3.2, "closed": false})
	# North half: the walk along Wilshire, the link from the crossing, a path up to 6th, and the
	# loop round the field.
	var walk_z := n_in.end.y - 8.0
	out.append({"pts": PackedVector2Array([Vector2(n_in.position.x + 2.0, walk_z), Vector2(n_in.end.x - 2.0, walk_z)]), "width": 3.6, "closed": false})
	out.append({"pts": PackedVector2Array([Vector2(crossing.x, walk_z), Vector2(crossing.x, n_in.end.y + PAVEMENT * 0.5)]), "width": 4.0, "closed": false})
	out.append({"pts": PackedVector2Array([Vector2(crossing.x + 60.0, walk_z), Vector2(crossing.x + 60.0, n_in.position.y - PAVEMENT * 0.5)]), "width": 3.2, "closed": false})
	var fr: Rect2 = (lay.field as Rect2).grow(3.5)
	out.append({"pts": PackedVector2Array([fr.position, Vector2(fr.end.x, fr.position.y), fr.end, Vector2(fr.position.x, fr.end.y)]), "width": 2.8, "closed": true})
	return out


static func _nearest(pts: PackedVector2Array, p: Vector2) -> Vector2:
	var best := pts[0]
	for q in pts:
		if q.distance_squared_to(p) < best.distance_squared_to(p):
			best = q
	return best


## Points `step` apart along a polyline (closed or open).
static func _along(pts: PackedVector2Array, step: float, closed: bool, phase: float = 0.0) -> Array:
	var out: Array = []
	var n := pts.size()
	var segs := n if closed else n - 1
	var carry := phase
	for i in segs:
		var a := pts[i]
		var b := pts[(i + 1) % n]
		var len := a.distance_to(b)
		var t := carry
		while t < len:
			var p := a.lerp(b, t / len)
			out.append([p, (b - a).normalized()])
			t += step
		carry = t - len
	return out


static func _near_path(lay: Dictionary, p: Vector2, pad: float) -> bool:
	for path: Dictionary in lay.paths:
		var pts: PackedVector2Array = path.pts
		var n := pts.size()
		var segs := n if path.closed else n - 1
		for i in segs:
			var q := Geometry2D.get_closest_point_to_segment(p, pts[i], pts[(i + 1) % n])
			if q.distance_to(p) < float(path.width) * 0.5 + pad:
				return true
	return false


static func _palm_spots(lay: Dictionary) -> Array:
	var out: Array = []
	for s: Array in _along(lay.palm_ring, PALM_RING_STEP, true):
		if (s[0] as Vector2).distance_to(lay.boathouse) > 15.0:
			out.append(s[0])
	# Along the park's streets, just inside the pavement ring, on all four sides of both halves.
	for half: Rect2 in [lay.north_in, lay.south_in]:
		var r := half.grow(-(PERIMETER_PALM_INSET - PAVEMENT))
		var corners := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
		for s: Array in _along(corners, PERIMETER_PALM_STEP, true, 4.0):
			var p: Vector2 = s[0]
			if _near_path(lay, p, 2.0) or (lay.field as Rect2).grow(4.0).has_point(p):
				continue
			out.append(p)
	return out


static func _tree_spots(lay: Dictionary, seed_value: int) -> Array:
	var out: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, "macarthur_trees"])
	for half: Rect2 in [lay.north_in, lay.south_in]:
		var area := half.size.x * half.size.y
		var want := int(area / 1000.0 * TREES_PER_1000)
		var placed := 0
		for i in want * 4:
			if placed >= want:
				break
			var p := Vector2(rng.randf_range(half.position.x + 8.0, half.end.x - 8.0), rng.randf_range(half.position.y + 8.0, half.end.y - 8.0))
			if in_lake(lay, p, PALM_RING_OFFSET + 3.0) or _near_path(lay, p, 3.5):
				continue
			if (lay.field as Rect2).grow(6.0).has_point(p) or p.distance_to(lay.bandshell) < 22.0 or p.distance_to(lay.boathouse) < 26.0:
				continue
			var clear := true
			for q: Vector2 in out:
				if q.distance_to(p) < 9.0:
					clear = false
					break
			if clear:
				out.append(p)
				placed += 1
	return out


## Benches along the outer edge of the promenade, facing the water. [[pos, yaw]]
static func _bench_spots(lay: Dictionary) -> Array:
	var out: Array = []
	var outer := _offset(lay.lake, COPING_W + PROMENADE_W + 0.6)
	for s: Array in _along(outer, BENCH_STEP, true, 6.0):
		var p: Vector2 = s[0]
		if p.distance_to(lay.boathouse) < 20.0:
			continue
		var t: Vector2 = s[1]
		# The inward normal (toward the lake) is (-t.y, t.x) for the counter-clockwise outline.
		out.append([p, _yaw_toward(p, p + Vector2(-t.y, t.x))])
	var n_in: Rect2 = lay.north_in
	var walk_z := n_in.end.y - 8.0
	var x := n_in.position.x + 14.0
	while x < n_in.end.x - 10.0:
		if absf(x - (lay.crossing as Vector2).x) > 6.0:
			out.append([Vector2(x, walk_z - 2.6), _yaw_toward(Vector2(x, walk_z - 2.6), Vector2(x, walk_z - 10.0))])
		x += BENCH_STEP * 1.4
	return out


static func _lamp_spots(lay: Dictionary) -> Array:
	var out: Array = []
	var outer := _offset(lay.lake, COPING_W + PROMENADE_W + 0.9)
	for s: Array in _along(outer, LAMP_STEP, true, 13.0):
		if (s[0] as Vector2).distance_to(lay.boathouse) > 16.0:
			out.append(s[0])
	var n_in: Rect2 = lay.north_in
	var walk_z := n_in.end.y - 8.0
	var x := n_in.position.x + 8.0
	while x < n_in.end.x - 6.0:
		out.append(Vector2(x, walk_z + 2.4))
		x += LAMP_STEP
	return out


## Where the park's people walk (each a ring rect Pedestrian wanders): the open north half in
## three parts, and four strips round the lake that the water never enters. [[rect, count]]
static func _crowd_rects(lay: Dictionary) -> Array:
	var out: Array = []
	var n_in: Rect2 = lay.north_in
	var parts := 3
	for i in parts:
		var r := Rect2(n_in.position.x + n_in.size.x * i / parts, n_in.position.y, n_in.size.x / parts, n_in.size.y)
		out.append([r, CROWD_NORTH / parts])
	var s_in: Rect2 = lay.south_in
	var lb: Rect2 = (lay.lake_bounds as Rect2).grow(COPING_W + 1.0)
	var strips := [
		Rect2(s_in.position.x, s_in.position.y, s_in.size.x, lb.position.y - s_in.position.y),
		Rect2(s_in.position.x, lb.end.y, s_in.size.x, s_in.end.y - lb.end.y),
		Rect2(s_in.position.x, lb.position.y, lb.position.x - s_in.position.x, lb.size.y),
		Rect2(lb.end.x, lb.position.y, s_in.end.x - lb.end.x, lb.size.y),
	]
	for r: Rect2 in strips:
		if r.size.x > 6.0 and r.size.y > 6.0:
			out.append([r, CROWD_SOUTH / 4])
	return out


## Planted beds: round the boathouse and at the two ends of the lake.
static func _flower_beds(lay: Dictionary) -> Array:
	var out: Array = []
	var b: Vector2 = lay.boathouse
	out.append(Rect2(b + Vector2(-16.0, -12.0), Vector2(9.0, 5.0)))
	out.append(Rect2(b + Vector2(8.0, -12.0), Vector2(9.0, 5.0)))
	var lb: Rect2 = lay.lake_bounds
	var s_in: Rect2 = lay.south_in
	out.append(Rect2(Vector2((s_in.position.x + lb.position.x) * 0.5 - 6.0, lb.get_center().y - 4.0), Vector2(12.0, 8.0)))
	out.append(Rect2(Vector2((s_in.end.x + lb.end.x) * 0.5 - 6.0, lb.get_center().y - 4.0), Vector2(12.0, 8.0)))
	return out


# --- Per-chunk parts --------------------------------------------------------------------------

## The build steps a chunk inside the site runs instead of a block's: the part of the park inside
## its own rect. FULL chunks get everything; LOD chunks the ground, the water and the palms.
static func site_steps(chunk: CityChunk) -> Array[Callable]:
	var steps: Array[Callable] = []
	var lay := layout(chunk.plan)
	if lay.is_empty():
		return steps
	var area := chunk.owned_rect()
	steps.append(_ground.bind(chunk, lay, area))
	steps.append(_water.bind(chunk, lay, area))
	if chunk.level == CityChunk.Level.FULL:
		steps.append(_walks.bind(chunk, lay, area))
		steps.append(_planting.bind(chunk, lay, area))
		steps.append(_furniture.bind(chunk, lay, area))
		steps.append(_features.bind(chunk, lay, area))
		for c: Array in lay.crowd:
			var r: Rect2 = c[0]
			if area.has_point(r.get_center()):
				var rng := RandomNumberGenerator.new()
				rng.seed = hash([chunk.plan.seed, "macarthur_crowd", int(r.position.x), int(r.position.y)])
				steps.append_array(chunk._crowd_steps(r, minf(4.0, minf(r.size.x, r.size.y) * 0.4), int(c[1]), rng))
	else:
		steps.append(_far_planting.bind(chunk, lay, area))
		steps.append(chunk._add_relief_floor)
	return steps


static func _chunk_rng(chunk: CityChunk, salt: String) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([chunk.plan.seed, "macarthur", salt, chunk.ix, chunk.iz])
	return rng


## The pavement ring round each half and the lawns inside it, with the lake cut out of the south
## lawn cell by cell (cells on the shore are clipped exactly to the waterline).
static func _ground(chunk: CityChunk, lay: Dictionary, area: Rect2) -> void:
	var full := chunk.level == CityChunk.Level.FULL
	var paving := PropFactory.road("sidewalk", 3.0, Color(1.5, 1.5, 1.48), hash([chunk.plan.seed, "macarthur_paving"]), 1.6, 0.4)
	for half: Rect2 in [lay.north, lay.south]:
		var inner := half.grow(-PAVEMENT)
		var strips := [
			Rect2(half.position.x, half.position.y, half.size.x, PAVEMENT),
			Rect2(half.position.x, inner.end.y, half.size.x, PAVEMENT),
			Rect2(half.position.x, inner.position.y, PAVEMENT, inner.size.y),
			Rect2(inner.end.x, inner.position.y, PAVEMENT, inner.size.y),
		]
		for s: Rect2 in strips:
			var part := s.intersection(area)
			if part.size.x > 0.05 and part.size.y > 0.05:
				chunk._add_ground_grid(part, CityChunk.SIDEWALK_TOP, CityChunk.SIDEWALK_TOP + 0.5, paving, true, chunk.style.sidewalk)
		var lawn_part := inner.intersection(area)
		if lawn_part.size.x > 0.05 and lawn_part.size.y > 0.05:
			_lawn(chunk, lay, lawn_part, full)


static func _lawn(chunk: CityChunk, lay: Dictionary, rect: Rect2, full: bool) -> void:
	var cell := CELL_FULL if full else CELL_LOD
	var nx := maxi(1, ceili(rect.size.x / cell))
	var nz := maxi(1, ceili(rect.size.y / cell))
	var cx := rect.size.x / nx
	var cz := rect.size.y / nz
	var lake: PackedVector2Array = lay.lake
	var lb: Rect2 = (lay.lake_bounds as Rect2).grow(cell * 1.5)
	# Cells the waterline passes through (and their neighbours) are clipped exactly; the rest are
	# kept or dropped whole by their centre.
	var shore := {}
	if lb.intersects(rect):
		for i in lake.size():
			var a := lake[i]
			var b := lake[(i + 1) % lake.size()]
			var steps := maxi(1, ceili(a.distance_to(b) / (minf(cx, cz) * 0.5)))
			for k in steps + 1:
				var p := a.lerp(b, float(k) / steps)
				var gi := floori((p.x - rect.position.x) / cx)
				var gj := floori((p.y - rect.position.y) / cz)
				for di in [-1, 0, 1]:
					for dj in [-1, 0, 1]:
						shore[Vector2i(gi + di, gj + dj)] = true
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	var tris := 0
	for j in nz:
		for i in nx:
			var x0 := rect.position.x + i * cx
			var z0 := rect.position.y + j * cz
			var quad := PackedVector2Array([Vector2(x0, z0), Vector2(x0 + cx, z0), Vector2(x0 + cx, z0 + cz), Vector2(x0, z0 + cz)])
			if shore.has(Vector2i(i, j)):
				for poly: PackedVector2Array in Geometry2D.clip_polygons(quad, lake):
					var idx := Geometry2D.triangulate_polygon(poly)
					for k in range(0, idx.size(), 3):
						_flat_tri(st, chunk, poly[idx[k]], poly[idx[k + 1]], poly[idx[k + 2]], LAWN_TOP)
						tris += 1
				continue
			var mid := Vector2(x0 + cx * 0.5, z0 + cz * 0.5)
			if lb.has_point(mid) and Geometry2D.is_point_in_polygon(mid, lake):
				continue
			_flat_tri(st, chunk, quad[0], quad[1], quad[2], LAWN_TOP)
			_flat_tri(st, chunk, quad[0], quad[2], quad[3], LAWN_TOP)
			tris += 2
	if tris == 0:
		return
	var mesh := st.commit()
	var mi := MeshInstance3D.new()
	mi.name = "ParkLawn"
	mi.mesh = mesh
	if full:
		mi.material_override = PropFactory.lawn(Color(0.86, 0.97, 0.72), hash([chunk.plan.seed, "macarthur_lawn"]), 0.3, 4.2)
	else:
		mi.material_override = PropFactory.material(Color(0.30, 0.40, 0.20), 0.95)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	chunk.add_child(mi)
	if full and chunk._statics:
		var shape := CollisionShape3D.new()
		shape.shape = mesh.create_trimesh_shape()
		chunk._statics.add_child(shape)


## One upward-facing triangle at height `y` (plus the relief), wound so it faces up.
static func _flat_tri(st: SurfaceTool, chunk: CityChunk, a: Vector2, b: Vector2, c: Vector2, y: float) -> void:
	var cross := (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
	# Godot's front faces are clockwise as the viewer sees them. Looking down on (x, z) - x to the
	# right, z down the screen - that is a POSITIVE 2D cross product (the freeway deck's l0, r1, r0
	# order in CityChunk is the worked example).
	if cross < 0.0:
		var t := b
		b = c
		c = t
	for p: Vector2 in [a, b, c]:
		st.set_uv(p * 0.2)
		st.add_vertex(Vector3(p.x, y + chunk._gy(p.x, p.y), p.y))


## The lake inside this chunk: the water surface, the basin wall and its coping round the shore,
## the floor you stand on in it, and a splash trigger over it.
static func _water(chunk: CityChunk, lay: Dictionary, area: Rect2) -> void:
	var lake: PackedVector2Array = lay.lake
	if not (lay.lake_bounds as Rect2).grow(COPING_W + 1.0).intersects(area):
		return
	var full := chunk.level == CityChunk.Level.FULL
	var area_poly := PackedVector2Array([area.position, Vector2(area.end.x, area.position.y), area.end, Vector2(area.position.x, area.end.y)])
	var water := SurfaceTool.new()
	water.begin(Mesh.PRIMITIVE_TRIANGLES)
	water.set_normal(Vector3.UP)
	var floor_tris := PackedVector3Array()
	var any := false
	var pieces := Geometry2D.intersect_polygons(lake, area_poly)
	for poly: PackedVector2Array in pieces:
		var idx := Geometry2D.triangulate_polygon(poly)
		for k in range(0, idx.size(), 3):
			_flat_tri(water, chunk, poly[idx[k]], poly[idx[k + 1]], poly[idx[k + 2]], WATER_Y)
			for q in [poly[idx[k]], poly[idx[k + 1]], poly[idx[k + 2]]]:
				floor_tris.append(Vector3(q.x, FLOOR_Y, q.y))
			any = true
	if any:
		var mi := MeshInstance3D.new()
		mi.name = "Lake"
		mi.mesh = water.commit()
		mi.material_override = lake_material(lay)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		chunk.add_child(mi)
		if full and chunk._statics:
			var floor_mesh := ConcavePolygonShape3D.new()
			floor_mesh.backface_collision = true
			floor_mesh.set_faces(floor_tris)
			var fs := CollisionShape3D.new()
			fs.shape = floor_mesh
			chunk._statics.add_child(fs)
			_lake_volume(chunk, pieces)
	# The basin: for every stretch of shore whose middle is in this chunk, the wall down into the
	# water and the coping over it.
	var wall := SurfaceTool.new()
	wall.begin(Mesh.PRIMITIVE_TRIANGLES)
	var coping: PackedVector2Array = lay.coping
	var walls := 0
	var n := lake.size()
	for i in n:
		var a := lake[i]
		var b := lake[(i + 1) % n]
		if not area.has_point((a + b) * 0.5):
			continue
		var ca := coping[i]
		var cb := coping[(i + 1) % n]
		var ya := chunk._gy(a.x, a.y)
		var yb := chunk._gy(b.x, b.y)
		# Wall face, looking into the water (inward).
		_quad(wall, Vector3(a.x, COPING_TOP + ya, a.y), Vector3(b.x, COPING_TOP + yb, b.y), Vector3(b.x, WALL_BOTTOM + yb, b.y), Vector3(a.x, WALL_BOTTOM + ya, a.y), (a + b) * 0.5 - (ca + cb) * 0.5)
		# Coping top, and its outer face down to the lawn.
		_quad(wall, Vector3(a.x, COPING_TOP + ya, a.y), Vector3(ca.x, COPING_TOP + ya, ca.y), Vector3(cb.x, COPING_TOP + yb, cb.y), Vector3(b.x, COPING_TOP + yb, b.y), Vector2.ZERO, true)
		_quad(wall, Vector3(ca.x, COPING_TOP + ya, ca.y), Vector3(ca.x, LAWN_TOP - 0.1 + ya, ca.y), Vector3(cb.x, LAWN_TOP - 0.1 + yb, cb.y), Vector3(cb.x, COPING_TOP + yb, cb.y), (ca + cb) * 0.5 - (a + b) * 0.5)
		walls += 1
		if full and chunk._statics:
			var mid := (a + b) * 0.5
			var cm := (ca + cb) * 0.5
			var len := a.distance_to(b) + 0.1
			var thick := 0.35
			var centre := mid + (cm - mid).normalized() * thick * 0.5
			var s := CollisionShape3D.new()
			var bs := BoxShape3D.new()
			bs.size = Vector3(len, COPING_TOP - WALL_BOTTOM, thick)
			s.shape = bs
			var dir := (b - a).normalized()
			s.transform = Transform3D(Basis(Vector3.UP, atan2(-dir.y, dir.x)), Vector3(centre.x, (COPING_TOP + WALL_BOTTOM) * 0.5 + ya, centre.y))
			chunk._statics.add_child(s)
	if walls > 0:
		wall.generate_normals()
		var wm := MeshInstance3D.new()
		wm.name = "LakeBasin"
		wm.mesh = wall.commit()
		wm.material_override = PropFactory.pbr("concrete", 2.0, Color(0.92, 0.90, 0.86))
		chunk.add_child(wm)


## A quad a-b-c-d; `facing` (2D, xz) is the way its front must point, or up when `up` is set.
static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, facing: Vector2, up: bool = false) -> void:
	var want := Vector3.UP if up else Vector3(facing.x, 0.0, facing.y)
	# Godot's front face is counter-clockwise as seen by the viewer, i.e. its normal is
	# (c - a) x (b - a) for the order a, b, c.
	var front := (c - a).cross(b - a)
	var order := [a, b, c, a, c, d]
	if front.dot(want) < 0.0:
		order = [a, c, b, a, d, c]
	for v: Vector3 in order:
		st.set_uv(Vector2(v.x + v.z, v.y))
		st.add_vertex(v)


static func lake_material(lay: Dictionary) -> ShaderMaterial:
	if _lake_mat == null:
		_lake_mat = ShaderMaterial.new()
		_lake_mat.shader = load("res://shaders/lake.gdshader")
	_lake_mat.set_shader_parameter("fountain_at", lay.fountain)
	return _lake_mat


## The water itself, as a trigger shaped like the lake (convex prisms from the floor to above
## the surface): whatever falls in throws up a splash, and the player and loose bodies sink
## through the city's ground box to the lake floor (_sink) while they are in it.
static func _lake_volume(chunk: CityChunk, pieces: Array) -> void:
	var zone := Area3D.new()
	zone.name = "LakeSplash"
	zone.collision_layer = 0
	zone.collision_mask = 2 | 4
	zone.monitorable = false
	for poly: PackedVector2Array in pieces:
		for part: PackedVector2Array in Geometry2D.decompose_polygon_in_convex(poly):
			var pts := PackedVector3Array()
			for q in part:
				var y := chunk._gy(q.x, q.y)
				pts.append(Vector3(q.x, WALL_BOTTOM + y, q.y))
				pts.append(Vector3(q.x, WATER_Y + 1.0 + y, q.y))
			var cs := CollisionShape3D.new()
			var hull := ConvexPolygonShape3D.new()
			hull.points = pts
			cs.shape = hull
			zone.add_child(cs)
	if zone.get_child_count() == 0:
		zone.free()
		return
	var inside := {}
	zone.body_entered.connect(func(body: Node3D) -> void:
		_splash(zone, body)
		_sink(zone, body, true, inside))
	zone.body_exited.connect(func(body: Node3D) -> void: _sink(zone, body, false, inside))
	# A chunk that unloads with something still in the water must not leave it passing through the
	# ground everywhere else.
	zone.tree_exiting.connect(func() -> void:
		for body: Node3D in inside.values():
			if is_instance_valid(body):
				_sink(zone, body, false, {}))
	chunk.add_child(zone)


## Lets a body through the city's ground box (or stops letting it) while it is in the lake. The
## box's top is the city datum, 0, and the lake floor is under it; a collision exception is per
## pair, so nothing else changes - the walls, the floor and every other surface still stop it.
## Wheel rays and queries ignore exceptions, so a car that lands in the lake rides its wheels on
## the box, chassis awash; people and bodies stand on the floor.
static func _sink(zone: Area3D, body: Node3D, on: bool, inside: Dictionary) -> void:
	if not (body is PhysicsBody3D) or not zone.is_inside_tree():
		return
	var city := zone.get_tree().get_first_node_in_group("city")
	var ground := city.get_node_or_null("GroundBody") as PhysicsBody3D if city else null
	if ground == null:
		return
	var id := body.get_instance_id()
	if on:
		inside[id] = body
		PhysicsServer3D.body_add_collision_exception((body as PhysicsBody3D).get_rid(), ground.get_rid())
	else:
		inside.erase(id)
		PhysicsServer3D.body_remove_collision_exception((body as PhysicsBody3D).get_rid(), ground.get_rid())


static var _last_splash_ms: int = -1000


static func _splash(zone: Area3D, body: Node3D) -> void:
	if not zone.is_inside_tree():
		return
	var v := Vector3.ZERO
	if body is RigidBody3D:
		v = (body as RigidBody3D).linear_velocity
	elif body is CharacterBody3D:
		v = (body as CharacterBody3D).velocity
	var speed := v.length()
	var now := Time.get_ticks_msec()
	if speed < 2.5 or now - _last_splash_ms < 120:
		return
	_last_splash_ms = now
	var at := body.global_position
	at.y = zone.global_position.y + WATER_Y
	var strength := clampf(speed / 14.0, 0.3, 2.0)
	var fx := CPUParticles3D.new()
	fx.one_shot = true
	fx.emitting = false
	fx.amount = int(40 + 70 * strength)
	fx.lifetime = 1.3
	fx.explosiveness = 0.92
	fx.direction = Vector3.UP
	fx.spread = 32.0
	fx.initial_velocity_min = 3.0 * strength
	fx.initial_velocity_max = 8.0 * strength
	fx.gravity = Vector3(0.0, -9.8, 0.0)
	fx.scale_amount_min = 0.12
	fx.scale_amount_max = 0.35
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var mat := StandardMaterial3D.new()
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.billboard_keep_scale = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_texture = WeaponFX.puff_texture()
	mat.albedo_color = Color(0.82, 0.86, 0.86, 0.75)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	quad.material = mat
	fx.mesh = quad
	fx.custom_aabb = AABB(Vector3(-6, -2, -6), Vector3(12, 12, 12))
	zone.get_parent().add_child(fx)
	fx.global_position = at
	fx.emitting = true
	fx.finished.connect(fx.queue_free)
	Sfx.play("land", at, -4.0, 0.55)


static func _ribbon(st: SurfaceTool, chunk: CityChunk, a: Vector2, b: Vector2, width: float, y: float, along0: float) -> void:
	var d := b - a
	var len := d.length()
	if len < 0.01:
		return
	var n := Vector2(-d.y, d.x) / len * width * 0.5
	var pts := [a - n, a + n, b + n, b - n]
	var uvs := [Vector2(0.0, along0), Vector2(width, along0), Vector2(width, along0 + len), Vector2(0.0, along0 + len)]
	var order := [0, 1, 2, 0, 2, 3]
	var cross: float = (pts[1].x - pts[0].x) * (pts[2].y - pts[0].y) - (pts[1].y - pts[0].y) * (pts[2].x - pts[0].x)
	if cross < 0.0:
		order = [0, 2, 1, 0, 3, 2]
	for k in order:
		var p: Vector2 = pts[k]
		st.set_uv(uvs[k])
		st.set_normal(Vector3.UP)
		st.add_vertex(Vector3(p.x, y + chunk._gy(p.x, p.y), p.y))


## The walks inside this chunk: each segment belongs to the chunk its middle is in.
static func _walks(chunk: CityChunk, lay: Dictionary, area: Rect2) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var any := false
	for path: Dictionary in lay.paths:
		var pts: PackedVector2Array = path.pts
		var n := pts.size()
		var segs := n if path.closed else n - 1
		var along := 0.0
		for i in segs:
			var a := pts[i]
			var b := pts[(i + 1) % n]
			if area.has_point((a + b) * 0.5) and ((a + b) * 0.5).distance_to(lay.boathouse) > BOATHOUSE_CLEAR:
				# A little longer than the segment, so a bend has no gap on its outside.
				var d := (b - a).normalized() * minf(0.5, float(path.width) * 0.12)
				_ribbon(st, chunk, a - d, b + d, float(path.width), PATH_TOP, along)
				any = true
			along += a.distance_to(b)
	if not any:
		return
	var mi := MeshInstance3D.new()
	mi.name = "ParkWalks"
	mi.mesh = st.commit()
	mi.material_override = PropFactory.road("paving", 2.6, Color(1.02, 0.99, 0.94), hash([chunk.plan.seed, "macarthur_walks"]), 1.4, 0.35)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = PATH_DRAW
	chunk.add_child(mi)


## Palms, lawn trees, bushes along the walks, planted beds and blade grass, for this chunk.
static func _planting(chunk: CityChunk, lay: Dictionary, area: Rect2) -> void:
	var rng := _chunk_rng(chunk, "planting")
	for p: Vector2 in lay.palms:
		if area.has_point(p):
			chunk._add_palm(Vector3(p.x, LAWN_TOP, p.y), rng, true)
	for p: Vector2 in lay.trees:
		if area.has_point(p):
			chunk._add_tree(Vector3(p.x, LAWN_TOP, p.y), rng)
	# Bushes along the outer edge of the promenade, in clumps.
	for s: Array in _along(_offset(lay.lake, COPING_W + PROMENADE_W + 2.2), 7.0, true, 3.0):
		var p: Vector2 = s[0]
		if area.has_point(p) and rng.randf() < 0.55 and p.distance_to(lay.boathouse) > 18.0:
			chunk._add_bush(Vector3(p.x, LAWN_TOP, p.y), rng)
	for bed: Rect2 in lay.beds:
		if area.has_point(bed.get_center()):
			chunk._scatter_ground_cover(bed, rng, 1.6)
	# Blade grass over the lawn part of this chunk, kept off the water and the walks.
	for half: Rect2 in [lay.north_in, lay.south_in]:
		var part := half.intersection(area)
		if part.size.x < 2.0 or part.size.y < 2.0:
			continue
		var blockers: Array[Rect2] = []
		_block_lake(lay, part, blockers)
		_block_walks(lay, part, blockers)
		if half == lay.north_in:
			blockers.append((lay.field as Rect2).grow(0.5))
		chunk._add_grass(part, 0.7, 0.0, blockers)


## Rects covering the lake (and its coping) inside `part`, a 4 m row at a time.
static func _block_lake(lay: Dictionary, part: Rect2, out: Array[Rect2]) -> void:
	var lb: Rect2 = (lay.lake_bounds as Rect2).grow(COPING_W + 0.6)
	var r := lb.intersection(part)
	if r.size.x <= 0.0 or r.size.y <= 0.0:
		return
	var coping := _offset(lay.lake, COPING_W + 0.6)
	var z := r.position.y
	while z < r.end.y:
		var z1 := minf(z + 4.0, r.end.y)
		var x := r.position.x
		var run_start := INF
		while x <= r.end.x:
			var inside := Geometry2D.is_point_in_polygon(Vector2(x, z), coping) or Geometry2D.is_point_in_polygon(Vector2(x, z1), coping)
			if inside and run_start == INF:
				run_start = x
			elif not inside and run_start != INF:
				out.append(Rect2(run_start - 2.0, z, x - run_start + 4.0, z1 - z))
				run_start = INF
			x += 2.0
		if run_start != INF:
			out.append(Rect2(run_start - 2.0, z, r.end.x - run_start + 2.0, z1 - z))
		z = z1


static func _block_walks(lay: Dictionary, part: Rect2, out: Array[Rect2]) -> void:
	for path: Dictionary in lay.paths:
		var pts: PackedVector2Array = path.pts
		var n := pts.size()
		var segs := n if path.closed else n - 1
		var w: float = path.width
		for i in segs:
			var a := pts[i]
			var b := pts[(i + 1) % n]
			var len := a.distance_to(b)
			var k := 0.0
			while k <= len:
				var p := a.lerp(b, k / maxf(len, 0.01))
				var r := Rect2(p - Vector2(w, w) * 0.5, Vector2(w, w))
				if r.intersects(part):
					out.append(r)
				k += maxf(w * 0.8, 1.5)


## LOD: the palms only, as silhouettes (no collision).
static func _far_planting(chunk: CityChunk, lay: Dictionary, area: Rect2) -> void:
	var rng := _chunk_rng(chunk, "far_planting")
	for p: Vector2 in lay.palms:
		if area.has_point(p):
			chunk._add_palm(Vector3(p.x, LAWN_TOP, p.y), rng, false)


## Lamps, benches, trash cans, the zebra crossing over Wilshire between the halves, and the park's
## stone name sign.
static func _furniture(chunk: CityChunk, lay: Dictionary, area: Rect2) -> void:
	for p: Vector2 in lay.lamps:
		if area.has_point(p):
			chunk._add_lamp(Vector3(p.x, CityChunk.SIDEWALK_TOP, p.y))
	for b: Array in lay.benches:
		var p: Vector2 = b[0]
		if area.has_point(p):
			chunk._add_bench(Vector3(p.x, PATH_TOP - 0.02, p.y), float(b[1]))
	var rng := _chunk_rng(chunk, "cans")
	var k := 0
	for b: Array in lay.benches:
		var p: Vector2 = b[0]
		k += 1
		if k % 3 != 0 or not area.has_point(p) or not PhysicsBudget.can_spawn():
			continue
		var can := TrashCan.new()
		can.rusty = rng.randf() < 0.3
		var q := p + Vector2(cos(float(b[1])), -sin(float(b[1]))) * 1.6
		can.position = Vector3(q.x, LAWN_TOP + 0.02 + chunk._gy(q.x, q.y), q.y)
		can.rotation.y = rng.randf_range(0.0, TAU)
		chunk.add_child(can)
	# The crossing: continental bars across Wilshire where the two halves' walks meet it.
	var c: Vector2 = lay.crossing
	if area.has_point(c):
		var road: Rect2 = lay.wilshire_rect
		var z := road.position.y + 1.2
		while z < road.end.y - 0.6:
			chunk._batch.add("stripe", PropFactory.stripe(), Transform3D(Basis().scaled(Vector3(2.2, 1.0, 1.0)), Vector3(c.x, CityChunk.ROAD_TOP + 0.015, z)))
			z += 1.9
	# The name, cut in a low stone wall at the Wilshire corner of the lake half.
	var s_in: Rect2 = lay.south_in
	var sign_at := Vector2(s_in.end.x - 14.0, s_in.position.y + 3.0)
	if area.has_point(sign_at):
		var base := Vector3(sign_at.x, LAWN_TOP + chunk._gy(sign_at.x, sign_at.y), sign_at.y)
		Landmarks._box(chunk, chunk._statics, Vector3(9.0, 0.9, 0.7), base + Vector3(0.0, 0.45, 0.0), Color(0.80, 0.77, 0.70), true).material_override = PropFactory.pbr("concrete", 1.5, Color(1.1, 1.06, 0.98))
		var text := MeshInstance3D.new()
		text.mesh = PropFactory.text_mesh(String(SITE.name).to_upper(), 0.42)
		text.material_override = PropFactory.material(Color(0.16, 0.18, 0.16), 0.6)
		# TextMesh reads from +Z; the street (Wilshire) is on the -Z side of the sign.
		text.rotation.y = PI
		text.position = base + Vector3(0.0, 0.42, -0.37)
		text.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		chunk.add_child(text)


## The north half's playing field and bandshell, where their middles fall in this chunk.
static func _features(chunk: CityChunk, lay: Dictionary, area: Rect2) -> void:
	var field: Rect2 = lay.field
	if area.has_point(field.get_center()):
		_build_field(chunk, field)
	var bs: Vector2 = lay.bandshell
	if area.has_point(bs):
		_build_bandshell(chunk, bs)


## A seven-a-side pitch: artificial turf, white lines, two goals with their nets.
static func _build_field(chunk: CityChunk, r: Rect2) -> void:
	var c := r.get_center()
	var y := LAWN_TOP + 0.03
	var turf := Landmarks._box(chunk, null, Vector3(r.size.x, 0.06, r.size.y), Vector3(c.x, y - 0.03, c.y), Color(0.2, 0.4, 0.15), false)
	turf.material_override = PropFactory.pbr("grass", 3.0, Color(0.55, 0.85, 0.45), 0.9)
	var line := Color(0.92, 0.93, 0.9)
	var w := 0.1
	var inset := 1.5
	var pr := r.grow(-inset)
	for z: float in [pr.position.y, pr.end.y]:
		Landmarks._box(chunk, null, Vector3(pr.size.x, 0.012, w), Vector3(pr.get_center().x, y + 0.006, z), line, false)
	for x: float in [pr.position.x, pr.end.x, pr.get_center().x]:
		Landmarks._box(chunk, null, Vector3(w, 0.012, pr.size.y), Vector3(x, y + 0.006, pr.get_center().y), line, false)
	# Goals at the two short ends (the pitch runs along x if it is wider than deep).
	var along_x := r.size.x >= r.size.y
	for side: float in [-1.0, 1.0]:
		var g := pr.get_center() + (Vector2(side * pr.size.x * 0.5, 0.0) if along_x else Vector2(0.0, side * pr.size.y * 0.5))
		var across := Vector3(0.0, 0.0, 1.0) if along_x else Vector3(1.0, 0.0, 0.0)
		var back := Vector3(side, 0.0, 0.0) if along_x else Vector3(0.0, 0.0, side)
		var o := Vector3(g.x, y, g.y)
		for s: float in [-1.0, 1.0]:
			Landmarks._cyl(chunk, chunk._statics, 0.05, 2.0, o + across * (s * 2.5) + Vector3(0.0, 1.0, 0.0), Color(0.95, 0.95, 0.95))
		var bar := Landmarks._box(chunk, null, Vector3(0.1, 0.1, 5.1) if along_x else Vector3(5.1, 0.1, 0.1), o + Vector3(0.0, 2.0, 0.0), Color(0.95, 0.95, 0.95), false)
		bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		var net := Landmarks._box(chunk, null, Vector3(0.02, 2.0, 5.0) if along_x else Vector3(5.0, 2.0, 0.02), o + back * 1.2 + Vector3(0.0, 1.0, 0.0), Color(0.9, 0.9, 0.9), false)
		var nm := StandardMaterial3D.new()
		nm.albedo_color = Color(0.9, 0.9, 0.9, 0.28)
		nm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		nm.cull_mode = BaseMaterial3D.CULL_DISABLED
		net.material_override = nm
	# Low benches for the players along one long side.
	for i in 3:
		var bx := pr.position.x + pr.size.x * (0.25 + 0.25 * i)
		chunk._add_bench(Vector3(bx, LAWN_TOP, r.end.y + 2.2), PI)


## The bandshell: a stage under a concrete half dome that opens to the lawn in front of it.
static func _build_bandshell(chunk: CityChunk, at: Vector2) -> void:
	var y := LAWN_TOP + chunk._gy(at.x, at.y)
	var stage := Landmarks._box(chunk, chunk._statics, Vector3(16.0, 1.1, 9.0), Vector3(at.x, y + 0.55, at.y + 1.0), Color(0.72, 0.70, 0.66), true)
	stage.material_override = PropFactory.pbr("concrete", 2.0, Color(1.0, 0.97, 0.92))
	var shell := MeshInstance3D.new()
	var dome := SphereMesh.new()
	dome.radius = 9.0
	dome.height = 18.0
	dome.is_hemisphere = true
	dome.radial_segments = 32
	dome.rings = 12
	shell.mesh = dome
	var mat := PropFactory.pbr("concrete", 2.5, Color(1.05, 1.03, 0.99)).duplicate() as StandardMaterial3D
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	shell.material_override = mat
	# A hemisphere turned onto its back: its open face looks south over the lawn, and the half of
	# it that would be underground simply is.
	shell.rotation.x = -PI * 0.5
	shell.position = Vector3(at.x, y + 1.1, at.y - 2.5)
	shell.scale = Vector3(1.0, 0.85, 1.0)
	chunk.add_child(shell)
	Landmarks._shape(chunk._statics, Vector3(18.0, 9.0, 1.0), Vector3(at.x, y + 5.0, at.y - 11.0))
	# Rows of benches on the lawn in front.
	for row in 3:
		for i in 4:
			var bx := at.x - 9.0 + i * 6.0
			chunk._add_bench(Vector3(bx, LAWN_TOP, at.y + 14.0 + row * 3.2), 0.0)


# --- The landmark itself: fountain and boathouse ---------------------------------------------------

## Built by Landmarks.build(): the fountain jet and the boathouse, detailed (with collision) by the
## chunk that holds the anchor, or far (a white spindle and the boathouse's mass) otherwise.
static func build(_anchor: Vector2, parent: Node3D, statics: StaticBody3D, plan: CityPlan, detailed: bool) -> void:
	if plan == null:
		return
	var lay := layout(plan)
	if lay.is_empty():
		return
	_build_fountain(parent, lay, detailed)
	_build_boathouse(parent, statics, lay, detailed)


static func _build_fountain(parent: Node3D, lay: Dictionary, detailed: bool) -> void:
	var f: Vector2 = lay.fountain
	var base := Vector3(f.x, WATER_Y, f.y)
	# The jet itself: a tapering column of white water, brightest where it is densest.
	var column := MeshInstance3D.new()
	column.name = "FountainJet"
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.18
	cyl.bottom_radius = 0.55
	cyl.height = FOUNTAIN_HEIGHT * 0.92
	cyl.radial_segments = 14 if detailed else 8
	cyl.rings = 6
	column.mesh = cyl
	var jm := StandardMaterial3D.new()
	jm.albedo_color = Color(0.9, 0.93, 0.94, 0.72 if detailed else 0.85)
	jm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	jm.roughness = 0.2
	jm.emission_enabled = true
	jm.emission = Color(0.18, 0.2, 0.21)
	jm.cull_mode = BaseMaterial3D.CULL_DISABLED
	column.material_override = jm
	column.position = base + Vector3(0.0, FOUNTAIN_HEIGHT * 0.46, 0.0)
	column.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	column.visibility_range_end = FOUNTAIN_DRAW
	parent.add_child(column)
	if not detailed:
		return
	# The plume: water thrown up the jet and falling back round it as spray and mist.
	var plume := CPUParticles3D.new()
	plume.name = "FountainPlume"
	plume.amount = FOUNTAIN_PARTICLES
	plume.lifetime = 3.6
	plume.preprocess = 3.6
	plume.direction = Vector3.UP
	plume.spread = 3.5
	var v := sqrt(2.0 * 9.8 * FOUNTAIN_HEIGHT)
	plume.initial_velocity_min = v * 0.82
	plume.initial_velocity_max = v
	plume.gravity = Vector3(0.0, -9.8, 0.0)
	plume.damping_min = 0.4
	plume.damping_max = 1.2
	plume.scale_amount_min = 0.6
	plume.scale_amount_max = 2.4
	var grow := Curve.new()
	grow.max_value = 3.0
	grow.add_point(Vector2(0.0, 0.4))
	grow.add_point(Vector2(0.5, 1.2))
	grow.add_point(Vector2(1.0, 2.6))
	plume.scale_amount_curve = grow
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 1.0, 1.0, 0.55))
	ramp.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	plume.color_ramp = ramp
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var pm := StandardMaterial3D.new()
	pm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	pm.billboard_keep_scale = true
	pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pm.vertex_color_use_as_albedo = true
	pm.albedo_texture = WeaponFX.puff_texture()
	pm.albedo_color = Color(0.92, 0.95, 0.96, 0.8)
	pm.roughness = 0.5
	pm.emission_enabled = true
	pm.emission = Color(0.12, 0.13, 0.14)
	if not OS.has_feature("web"):
		pm.proximity_fade_enabled = true
		pm.proximity_fade_distance = 1.5
	quad.material = pm
	plume.mesh = quad
	plume.custom_aabb = AABB(Vector3(-14.0, -2.0, -14.0), Vector3(28.0, FOUNTAIN_HEIGHT + 8.0, 28.0))
	plume.position = base + Vector3(0.0, 0.3, 0.0)
	plume.visibility_range_end = FOUNTAIN_DRAW
	plume.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(plume)
	# The boil at its foot: a ring of churned white water.
	var foam := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 3.2
	disc.bottom_radius = 3.6
	disc.height = 0.12
	disc.radial_segments = 24
	foam.mesh = disc
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.86, 0.9, 0.9, 0.55)
	fm.albedo_texture = WeaponFX.puff_texture()
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.uv1_scale = Vector3(3.0, 1.0, 3.0)
	foam.material_override = fm
	foam.position = base + Vector3(0.0, 0.06, 0.0)
	foam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(foam)
	# Lit from below after dark, like the real one: a lamp-group light (DayNight drives it).
	var light := OmniLight3D.new()
	light.position = base + Vector3(0.0, 1.2, 0.0)
	light.omni_range = 16.0
	light.omni_attenuation = 1.2
	light.light_color = Color(0.85, 0.92, 1.0)
	light.light_energy = 0.0
	light.shadow_enabled = false
	light.distance_fade_enabled = true
	light.distance_fade_begin = 180.0
	light.distance_fade_length = 40.0
	light.add_to_group("lamp_light")
	parent.add_child(light)


## The boathouse on the north shore: a two-storey clapboard pavilion under a hipped roof with a
## cupola, a veranda deck out over the water on piles, and a landing with pedal boats tied up.
## Local frame: +Z toward the lake (the yaw from the layout), origin on the shore line.
static func _build_boathouse(parent: Node3D, statics: StaticBody3D, lay: Dictionary, detailed: bool) -> void:
	var at: Vector2 = lay.boathouse
	var yaw: float = lay.boathouse_yaw
	# Forward (toward the lake) is -Z of the yaw basis; build in a frame whose +Z is the lake.
	var basis := Basis(Vector3.UP, yaw + PI)
	var o := Vector3(at.x, LAWN_TOP, at.y)
	var holder := Node3D.new()
	holder.name = "Boathouse"
	holder.position = o
	holder.basis = basis
	parent.add_child(holder)
	var body: StaticBody3D = null
	if statics:
		body = StaticBody3D.new()
		body.name = "BoathouseBody"
		body.collision_layer = 1
		body.collision_mask = 0
		body.position = o
		body.basis = basis
		parent.add_child(body)
	var white := Color(0.93, 0.92, 0.88)
	var trim := Color(0.24, 0.34, 0.30)
	var roof := Color(0.30, 0.22, 0.18)
	# The house stands on the shore, set back so its veranda reaches out over the coping.
	var house := Vector3(0.0, 0.0, -7.0)
	Landmarks._facade_box(holder, body, Vector3(20.0, 4.2, 11.0), house + Vector3(0.0, 2.1, 0.0), white, Building.Finish.FLAT, Building.WindowStyle.PUNCHED, 4.2)
	Landmarks._facade_box(holder, body, Vector3(16.0, 3.8, 9.0), house + Vector3(0.0, 4.2 + 1.9, 0.0), white, Building.Finish.FLAT, Building.WindowStyle.PUNCHED, 0.0)
	# Hipped roof and the cupola.
	var r := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 1.2
	cone.bottom_radius = 12.5
	cone.height = 4.4
	cone.radial_segments = 4
	cone.rings = 1
	r.mesh = cone
	r.material_override = PropFactory.material(roof, 0.8)
	r.rotation.y = PI * 0.25
	r.scale = Vector3(1.0, 1.0, 0.62)
	r.position = house + Vector3(0.0, 8.0 + 2.2, 0.0)
	holder.add_child(r)
	Landmarks._box(holder, body, Vector3(2.6, 2.0, 2.6), house + Vector3(0.0, 13.4, 0.0), white, true)
	var cap := MeshInstance3D.new()
	var capm := CylinderMesh.new()
	capm.top_radius = 0.0
	capm.bottom_radius = 2.2
	capm.height = 1.8
	capm.radial_segments = 4
	cap.mesh = capm
	cap.material_override = PropFactory.material(roof, 0.8)
	cap.rotation.y = PI * 0.25
	cap.position = house + Vector3(0.0, 15.3, 0.0)
	holder.add_child(cap)
	if not detailed:
		return
	# Eaves band and corner boards in the trim green.
	Landmarks._box(holder, null, Vector3(20.6, 0.35, 11.6), house + Vector3(0.0, 4.25, 0.0), trim, false)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			Landmarks._box(holder, null, Vector3(0.3, 4.2, 0.3), house + Vector3(sx * 10.0, 2.1, sz * 5.5), trim, false)
	# The veranda: a timber deck on piles from the house out over the water, with a railing.
	var deck_len := 13.0
	var deck := Landmarks._box(holder, body, Vector3(22.0, 0.3, deck_len), Vector3(0.0, 0.15, -1.5 + deck_len * 0.5), Color(0.5, 0.4, 0.3), true)
	deck.material_override = PropFactory.pbr("planks", 2.0, Color(0.95, 0.85, 0.75))
	for i in 7:
		var px := -10.5 + i * 3.5
		for pz: float in [4.0, 8.5, 11.0]:
			Landmarks._cyl(holder, null, 0.16, 2.2, Vector3(px, -0.95, pz), Color(0.3, 0.25, 0.2))
	for side: float in [-1.0, 1.0]:
		Landmarks._box(holder, body, Vector3(0.08, 1.0, deck_len - 1.0), Vector3(side * 10.9, 0.8, -1.5 + deck_len * 0.5), white, true)
	Landmarks._box(holder, body, Vector3(21.8, 1.0, 0.08), Vector3(0.0, 0.8, -1.5 + deck_len - 0.05), white, true)
	for i in 12:
		Landmarks._box(holder, null, Vector3(0.1, 1.0, 0.1), Vector3(-10.9 + i * 1.98, 0.8, -1.5 + deck_len - 0.05), white, false)
	# Veranda roof on posts along the house front.
	for i in 6:
		Landmarks._box(holder, null, Vector3(0.22, 3.0, 0.22), Vector3(-9.5 + i * 3.8, 1.8, 2.8), white, false)
	Landmarks._box(holder, null, Vector3(21.0, 0.25, 4.2), Vector3(0.0, 3.4, 0.6), roof, false)
	# The landing and the pedal boats tied up along it.
	var landing := Landmarks._box(holder, body, Vector3(3.0, 0.25, 12.0), Vector3(12.8, -0.1, 6.0), Color(0.5, 0.4, 0.3), true)
	landing.material_override = PropFactory.pbr("planks", 2.0, Color(0.9, 0.82, 0.72))
	var boat_colors := [Color(0.85, 0.82, 0.74), Color(0.12, 0.35, 0.62), Color(0.78, 0.18, 0.14), Color(0.92, 0.72, 0.18)]
	for i in 4:
		var bz := 1.8 + i * 2.6
		var hull := Landmarks._box(holder, null, Vector3(1.5, 0.55, 2.4), Vector3(15.1, WATER_Y - LAWN_TOP + 0.18, bz), boat_colors[i], false)
		hull.material_override = PropFactory.material(boat_colors[i], 0.35)
		Landmarks._box(holder, null, Vector3(1.2, 0.5, 0.6), Vector3(15.1, WATER_Y - LAWN_TOP + 0.62, bz - 0.4), Color(0.95, 0.95, 0.92), false)
		Landmarks._box(holder, null, Vector3(1.3, 0.08, 1.2), Vector3(15.1, WATER_Y - LAWN_TOP + 0.95, bz + 0.2), Color(0.95, 0.95, 0.92), false)
	# Lamps on the veranda corners.
	for side: float in [-1.0, 1.0]:
		var lamp := OmniLight3D.new()
		lamp.position = Vector3(side * 9.0, 2.9, 2.2)
		lamp.omni_range = 9.0
		lamp.light_color = Color(1.0, 0.85, 0.6)
		lamp.light_energy = 0.0
		lamp.distance_fade_enabled = true
		lamp.distance_fade_begin = 90.0
		lamp.distance_fade_length = 20.0
		lamp.add_to_group("lamp_light")
		holder.add_child(lamp)
