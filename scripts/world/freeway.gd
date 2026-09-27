class_name Freeway
extends RefCounted
## The freeway system: long curved routes across the basin, carried on a deck above the street
## grid on pillars, with barriers, lane paint, overhead sign gantries and ramps down to the
## surface streets.
##
## This is the one thing in the city that is deliberately not on the grid. A basin city like
## this one is read by its freeways before anything else, and a perfectly square street plan is
## the loudest sign that a map was generated rather than built, so these curve continuously and
## cut across the blocks at whatever angle they like.
##
## Same shape of data as HillRoads: seeded polylines with a smoothed height profile, a cell
## index for "what passes through this chunk", and everything in true world XZ.

## Deck width (both carriageways plus the median) and how far above the ground it rides.
const DECK_WIDTH := 34.0
const DECK_THICKNESS := 1.4
const DECK_RISE := 9.5
## Pillar spacing, and the spacing of the overhead sign gantries. Both are rounded to whole STEP
## segments, so they want to be multiples of STEP: at 32 the bents landed every 24 m and the
## elevated section read as a retaining wall from the side rather than a deck on legs.
const PILLAR_SPACING := 72.0
const GANTRY_SPACING := 340.0
## Off-ramps (CityChunk._build_freeway_ramps(), ramp_path()): how far along the route one runs
## from the deck edge to the street, how wide it is, how far out to its side it bows, and in how
## many straight pieces it is built.
const RAMP_RUN := 78.0
const RAMP_WIDTH := 9.0
const RAMP_BOW := 10.0
const RAMP_STEPS := 13
## How far outside the airport fence a deck has to end (_drivable()), metres.
const AIRPORT_KEEP := 60.0
## Points are this far apart along a route; the deck is built from them directly.
const STEP := 24.0
const CELL := 160.0
## Max change in deck height per metre of run, so the grade is drivable. Steep for a freeway,
## but the valley route has to climb through the pass and real mountain freeways do 6 to 7 %.
const MAX_GRADE := 0.07
## The deck never gets closer than this to the ground underneath it.
const MIN_CLEARANCE := 4.0
## Vertical gap between two decks where routes cross. Without this they simply intersect: the
## Coast and Cross freeways met with 1.2 m between two 34 m wide decks, which is one passing
## through the other. A real interchange puts one clearly over the top.
const DECK_SEPARATION := 7.5
## Ground a freeway can be built over. Routes are drawn as long sweeping curves across the whole
## basin and are then trimmed to the run that clears this, so no route tries to scale the
## peninsula cliffs or the east range.
const MAX_GROUND := 230.0

## Routes: {"name", "points": PackedVector2Array, "heights": PackedFloat32Array, "width": float}
var routes: Array[Dictionary] = []
## Ramps: {"route", "index", "side", "pos": Vector2, "yaw": float, "top": float}
var ramps: Array[Dictionary] = []

var _macro: MacroMap
var _cells: Dictionary = {}
## Cumulative distance to each point of each route, so traffic can be driven by distance along
## the deck rather than by point index - the points are a fixed step along the *drawn* curve,
## which is not a fixed step along the ground once the curve bends.
var _runs: Array[PackedFloat32Array] = []


func build(macro: MacroMap, seed_value: int) -> void:
	_macro = macro
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 31 + 977
	routes.clear()
	ramps.clear()

	# 1. The coast route: runs the length of the basin north to south, a few blocks inland,
	#    bending with the shoreline.
	var coast := PackedVector2Array()
	var z := macro.hills_start_z + 40.0
	while z < 1250.0:
		var cx := macro.coast_x(z) + 330.0 + 120.0 * sin(z / 620.0) + 55.0 * sin(z / 197.0 + 2.1)
		coast.append(Vector2(cx, z))
		z += STEP
	_add_route("405 Coast Freeway", coast, rng)

	# 2. The cross route (the 105): in from the coast just south of the airport and its runway
	#    protection zone, across the basin, down the west side of the 110 corridor and then east,
	#    crossing the 110 south of the 10 - where the real one crosses it, well below downtown -
	#    and on east. (Its line down there was drawn when the port stood at z 3000; the port moved
	#    to the headland's east flank, the 105 kept its line.) It used to run through the middle of the basin at
	#    z 500, which at 1:1 (DowntownReal) is straight through MacArthur Park and the Financial
	#    District. It swings wide round the masjid's neighbourhood (Exposition, south of the 10
	#    and west of the 110, LandmarkMasjidOmar) so the order north to south is the real one: the
	#    10, the masjid, the 105.
	var cz := macro.runway_clear_zone().end.y + 70.0
	var cross := _spline(PackedVector2Array([
		Vector2(macro.coast_x(cz) + 60.0, cz), Vector2(300.0, cz + 15.0), Vector2(1000.0, cz + 60.0),
		Vector2(1420.0, cz + 420.0), Vector2(1540.0, 2300.0), Vector2(1700.0, 2790.0),
		Vector2(2000.0, 2925.0), Vector2(3100.0, 2890.0), Vector2(macro.east_start_x - 200.0, 2870.0)]))
	_add_route("105 Century Freeway", cross, rng)

	# 3. The valley route (the 101): along the north edge of downtown past the civic centre on
	#    its real alignment (DowntownReal.FREEWAY_101) to the four-level interchange, west-south-
	#    west from there - its real heading, which runs it into the pass - and north through the
	#    pass in the front range and across the inland valley. The climb to the valley floor is
	#    the whole northern run, and a short route could not make it at a drivable grade.
	var valley := DowntownReal.freeway(DowntownReal.FREEWAY_101)
	# The real line runs on west past the pass mouth; the route turns north into the pass instead.
	valley.remove_at(valley.size() - 1)
	valley.append(Vector2(1150.0, -1325.0))
	valley.append(Vector2(macro.pass_center_x + 70.0, -1420.0))
	var pass_z: float = (macro.hills_full_z + macro.valley_from_z) * 0.5
	var vz := -1560.0
	while vz > macro.valley_to_z - 700.0:
		# Zero at the pass, so the route threads it and curves away either side.
		var t := (vz - pass_z) / 1100.0
		valley.append(Vector2(macro.pass_center_x + 210.0 * sin(t * 1.4), vz))
		vz -= STEP * 6.0
	_add_route("101 Hollywood Freeway", _spline(valley), rng)

	# 4. The harbour route (the 110): down the west edge of downtown on its real alignment
	#    (DowntownReal.FREEWAY_110), from the four-level interchange past the arena to the 10,
	#    and on south, nearly due south as the real one runs, to the port on the headland's east
	#    flank (MacroMap.port_rect), ending at the terminal's north-west corner by the channel -
	#    where the real one ends in San Pedro. The spur that moves containers off the docks, and the
	#    reason downtown and the port feel like one place rather than two.
	var harbour := DowntownReal.freeway(DowntownReal.FREEWAY_110)
	var dock := macro.port_rect.position
	harbour.append_array(PackedVector2Array([Vector2(2400.0, 3700.0), Vector2(2470.0, 4700.0),
		Vector2(dock.x - 170.0, dock.y - 485.0), Vector2(dock.x - 60.0, dock.y - 45.0)]))
	_add_route("110 Harbor Freeway", _spline(harbour), rng)

	# 5. The 10: from the 110 east along the south of downtown (DowntownReal.FREEWAY_10) toward
	#    the east range, whose grade trims it.
	_add_route("10 Santa Monica Freeway", _spline(DowntownReal.freeway(DowntownReal.FREEWAY_10)), rng)

	_separate_crossings()
	_place_ramps(rng)
	_index()


## A smooth route through control points, resampled to one point every STEP metres along the
## curve: the deck, the traffic and the bake all assume STEP. The spline is CENTRIPETAL Catmull-Rom
## (knots spaced by the square root of the chord): the uniform kind loops back on itself where a
## short span meets a long one - the 110's first 230 m span before its 2 km run doubled the deck
## back 12 m at the four-level interchange, and put two more hairpins in it near Olympic and Pico.
## The ends are extended by a phantom point mirrored through them, so the first span has a tangent.
static func _spline(ctrl: PackedVector2Array) -> PackedVector2Array:
	var fine := PackedVector2Array()
	var count := ctrl.size()
	for i in count - 1:
		var p1 := ctrl[i]
		var p2 := ctrl[i + 1]
		var p0 := ctrl[i - 1] if i > 0 else p1 * 2.0 - p2
		var p3 := ctrl[i + 2] if i + 2 < count else p2 * 2.0 - p1
		var t1 := sqrt(maxf(p0.distance_to(p1), 0.001))
		var t2 := t1 + sqrt(maxf(p1.distance_to(p2), 0.001))
		var t3 := t2 + sqrt(maxf(p2.distance_to(p3), 0.001))
		var n := maxi(4, int(p1.distance_to(p2) / 4.0))
		for k in n:
			var t := lerpf(t1, t2, float(k) / float(n))
			var a1 := p0.lerp(p1, t / t1)
			var a2 := p1.lerp(p2, (t - t1) / (t2 - t1))
			var a3 := p2.lerp(p3, (t - t2) / (t3 - t2))
			var b1 := a1.lerp(a2, t / t2)
			var b2 := a2.lerp(a3, (t - t1) / (t3 - t1))
			fine.append(b1.lerp(b2, (t - t1) / (t2 - t1)))
	fine.append(ctrl[ctrl.size() - 1])
	var out := PackedVector2Array([fine[0]])
	var carry := 0.0
	for i in range(1, fine.size()):
		var a := fine[i - 1]
		var seg := a.distance_to(fine[i])
		while carry + seg >= STEP:
			a = a.lerp(fine[i], (STEP - carry) / seg)
			seg = a.distance_to(fine[i])
			out.append(a)
			carry = 0.0
		carry += seg
	return out


## A route's deck height at one of its points: the ground below it plus the rise, smoothed and
## grade-limited so it does not follow every bump in the terrain.
func _add_route(route_name: String, drawn: PackedVector2Array, rng: RandomNumberGenerator) -> int:
	var pts := _drivable(drawn)
	if pts.size() < 24:
		return -1
	var raw := PackedFloat32Array()
	for p in pts:
		raw.append(_macro.height_at(p) + DECK_RISE)
	var heights := _smooth(raw)
	heights = _limit_grade(heights, pts)
	heights = _clear_ground(heights, pts)
	routes.append({
		"name": route_name, "points": pts, "heights": heights,
		"width": DECK_WIDTH * rng.randf_range(0.94, 1.08),
	})
	return routes.size() - 1


## The longest run of a drawn route that is over ground a freeway can be built on: below
## MAX_GROUND, not out at sea and not over the airport. Everything outside it is dropped, so a
## route ends where the basin does instead of running up a cliff with its deck buried under the
## hillside - and the coast route stops at the airport's north fence: it used to run straight on
## over the terminal and all three runways at nine metres, in the arriving jets' way.
func _drivable(pts: PackedVector2Array) -> PackedVector2Array:
	var best_from := 0
	var best_len := 0
	var run_from := -1
	for i in pts.size():
		var p := pts[i]
		if _macro.height_at(p) <= MAX_GROUND and _macro.zone_at(p) != MacroMap.Zone.OCEAN \
				and not _macro.airport_rect.grow(AIRPORT_KEEP).has_point(p):
			if run_from < 0:
				run_from = i
			if i - run_from + 1 > best_len:
				best_from = run_from
				best_len = i - run_from + 1
		else:
			run_from = -1
	return pts.slice(best_from, best_from + best_len)


## Raise the deck wherever the grade-limited profile left it buried, without breaking the grade.
##
## Smoothing and grade-limiting both ignore the ground, so a rise the limiter cannot follow ends
## up inside the hill. The fix is to build the *lowest* profile that clears the ground and still
## obeys the grade - propagate the required clearance forwards and backwards, relaxing by the
## max grade each step - and then take the higher of the two profiles at every point. The
## maximum of two grade-feasible profiles is itself grade-feasible (a max of Lipschitz functions
## keeps the same bound), so the result clears the ground everywhere and is still drivable.
func _clear_ground(h: PackedFloat32Array, pts: PackedVector2Array) -> PackedFloat32Array:
	var need := PackedFloat32Array()
	for p in pts:
		need.append(_macro.height_at(p) + MIN_CLEARANCE)
	for i in range(1, need.size()):
		need[i] = maxf(need[i], need[i - 1] - MAX_GRADE * pts[i].distance_to(pts[i - 1]))
	for i in range(need.size() - 2, -1, -1):
		need[i] = maxf(need[i], need[i + 1] - MAX_GRADE * pts[i].distance_to(pts[i + 1]))
	var out := h.duplicate()
	for i in out.size():
		out[i] = maxf(out[i], need[i])
	return out


## Where two routes cross in plan, lift the later one clear over the earlier one.
##
## Nothing in the routing stops two decks meeting at the same height, and two 34 m wide decks at
## the same height are one passing through the other. Raising is deliberately the only move -
## lowering the second route instead would drive it into the ground it is already only
## MIN_CLEARANCE above.
##
## The lift uses the same relaxation as `_clear_ground()`: propagate the required height
## forwards and backwards along the route, easing by MAX_GRADE each step, then take the higher
## of that and the existing profile. The maximum of two grade-feasible profiles is itself
## grade-feasible, so the flyover is drivable and rises gradually instead of stepping up.
func _separate_crossings() -> void:
	for b in routes.size():
		var pb: PackedVector2Array = routes[b].points
		var hb: PackedFloat32Array = routes[b].heights
		var need := PackedFloat32Array()
		need.resize(pb.size())
		for i in need.size():
			need[i] = -1e9
		var lifted := false
		for a in b:
			var pa: PackedVector2Array = routes[a].points
			var ha: PackedFloat32Array = routes[a].heights
			if not _bounds(pa).intersects(_bounds(pb)):
				continue
			for j in pb.size() - 1:
				for i in pa.size() - 1:
					var t := _segments_cross(pa[i], pa[i + 1], pb[j], pb[j + 1])
					if t < 0.0:
						continue
					var over: float = maxf(ha[i], ha[i + 1]) + DECK_SEPARATION
					if over > need[j]:
						need[j] = over
						need[j + 1] = maxf(need[j + 1], over)
						lifted = true
		if not lifted:
			continue
		for i in range(1, need.size()):
			need[i] = maxf(need[i], need[i - 1] - MAX_GRADE * pb[i].distance_to(pb[i - 1]))
		for i in range(need.size() - 2, -1, -1):
			need[i] = maxf(need[i], need[i + 1] - MAX_GRADE * pb[i].distance_to(pb[i + 1]))
		var out := hb.duplicate()
		for i in out.size():
			out[i] = maxf(out[i], need[i])
		routes[b].heights = out


static func _bounds(pts: PackedVector2Array) -> Rect2:
	var r := Rect2(pts[0], Vector2.ZERO)
	for p in pts:
		r = r.expand(p)
	return r.grow(2.0)


## Where segment a0-a1 crosses b0-b1, as the fraction along b, or -1 if they do not cross.
static func _segments_cross(a0: Vector2, a1: Vector2, b0: Vector2, b1: Vector2) -> float:
	var r := a1 - a0
	var sv := b1 - b0
	var denom := r.cross(sv)
	if absf(denom) < 0.000001:
		return -1.0
	var t := (b0 - a0).cross(sv) / denom
	var u := (b0 - a0).cross(r) / denom
	if t < 0.0 or t > 1.0 or u < 0.0 or u > 1.0:
		return -1.0
	return u


func _smooth(h: PackedFloat32Array) -> PackedFloat32Array:
	var out := h.duplicate()
	for pass_i in 4:
		var src := out.duplicate()
		for i in src.size():
			var sum := 0.0
			var n := 0
			for k in range(-3, 4):
				var j := i + k
				if j >= 0 and j < src.size():
					sum += src[j]
					n += 1
			out[i] = sum / n
	return out


func _limit_grade(h: PackedFloat32Array, pts: PackedVector2Array) -> PackedFloat32Array:
	var out := h.duplicate()
	for i in range(1, out.size()):
		var run := pts[i].distance_to(pts[i - 1])
		out[i] = clampf(out[i], out[i - 1] - MAX_GRADE * run, out[i - 1] + MAX_GRADE * run)
	for i in range(out.size() - 2, -1, -1):
		var run := pts[i].distance_to(pts[i + 1])
		out[i] = clampf(out[i], out[i + 1] - MAX_GRADE * run, out[i + 1] + MAX_GRADE * run)
	return out


## Off-ramps every few hundred metres, alternating sides, wherever the deck is over buildable
## ground rather than water or mountain.
func _place_ramps(rng: RandomNumberGenerator) -> void:
	for ri in routes.size():
		var route: Dictionary = routes[ri]
		var pts: PackedVector2Array = route.points
		var heights: PackedFloat32Array = route.heights
		var i := 8
		var side := 1.0
		while i < pts.size() - 8:
			var p := pts[i]
			if _macro.zone_at(p) == MacroMap.Zone.CITY:
				var seg := pts[i + 1] - pts[i - 1]
				var normal := Vector2(-seg.y, seg.x).normalized()
				ramps.append({
					"route": ri, "index": i, "side": side,
					"pos": p + normal * side * (route.width * 0.5),
					"yaw": atan2(-seg.x, -seg.y), "top": heights[i],
				})
				side = -side
			i += int(rng.randf_range(11.0, 17.0))


func _index() -> void:
	_cells.clear()
	_runs.clear()
	for ri in routes.size():
		var pts: PackedVector2Array = routes[ri].points
		var run := PackedFloat32Array()
		run.resize(pts.size())
		run[0] = 0.0
		for i in range(1, pts.size()):
			run[i] = run[i - 1] + pts[i].distance_to(pts[i - 1])
		_runs.append(run)
	for ri in routes.size():
		var pts: PackedVector2Array = routes[ri].points
		var reach: float = routes[ri].width * 0.5 + 24.0
		for si in pts.size() - 1:
			var a := pts[si]
			var b := pts[si + 1]
			var lo := Vector2(minf(a.x, b.x), minf(a.y, b.y)) - Vector2.ONE * reach
			var hi := Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + Vector2.ONE * reach
			for cx in range(floori(lo.x / CELL), floori(hi.x / CELL) + 1):
				for cz in range(floori(lo.y / CELL), floori(hi.y / CELL) + 1):
					var key := Vector2i(cx, cz)
					if not _cells.has(key):
						_cells[key] = []
					_cells[key].append(Vector2i(ri, si))


## Deck segments touching a world rect: [{"a", "b", "ha", "hb", "width", "index", "route"}].
func segments_in(rect: Rect2) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var seen := {}
	var grown := rect.grow(CELL)
	for cx in range(floori(grown.position.x / CELL), floori(grown.end.x / CELL) + 1):
		for cz in range(floori(grown.position.y / CELL), floori(grown.end.y / CELL) + 1):
			var key := Vector2i(cx, cz)
			if not _cells.has(key):
				continue
			for ref in _cells[key]:
				if seen.has(ref):
					continue
				seen[ref] = true
				var route: Dictionary = routes[ref.x]
				var pts: PackedVector2Array = route.points
				out.append({
					"a": pts[ref.y], "b": pts[ref.y + 1],
					"ha": route.heights[ref.y], "hb": route.heights[ref.y + 1],
					"width": route.width, "index": ref.y, "route": ref.x,
				})
	return out


## Ramps whose landing falls inside a world rect.
func ramps_in(rect: Rect2) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for r in ramps:
		if rect.has_point(r.pos):
			out.append(r)
	return out


## True if any part of the world rect `rect` comes within `margin` metres of the deck's edge (the
## deck and its pillars are the route's width about the centre line) or of an off-ramp. What
## keeps a building's whole footprint out from under the freeway: testing only a lot's centre let
## the corner of a 60 m downtown lot stand 25 m into the deck, and nothing at all looked at the
## ramps, which peel off the deck edge and bow up to RAMP_BOW metres out over the lots.
func blocks_rect(rect: Rect2, margin: float) -> bool:
	for s in segments_in(rect.grow(margin)):
		if segment_rect_distance(s.a, s.b, rect) < float(s.width) * 0.5 + margin:
			return true
	for r in ramps_in(rect.grow(RAMP_RUN + RAMP_BOW + margin)):
		var path := ramp_path(r)
		for k in path.size() - 1:
			if segment_rect_distance(path[k], path[k + 1], rect) < RAMP_WIDTH * 0.5 + margin:
				return true
	return false


## An off-ramp's centre line in world XZ, RAMP_STEPS + 1 points from where it leaves the deck edge
## to where it lands on the street: RAMP_RUN metres along the route, bowed RAMP_BOW metres out to
## the ramp's side on the way. CityChunk builds the ramp on exactly these points.
static func ramp_path(r: Dictionary) -> PackedVector2Array:
	var start: Vector2 = r.pos
	var yaw: float = r.yaw
	var out := Vector2(-sin(yaw), -cos(yaw))
	var side := Vector2(-out.y, out.x)
	var path := PackedVector2Array()
	for k in RAMP_STEPS + 1:
		var t := float(k) / RAMP_STEPS
		path.append(start + out * (RAMP_RUN * t) + side * (RAMP_BOW * sin(t * PI) * float(r.side)))
	return path


## Metres between segment a-b and a world rect (0 where they touch or overlap).
static func segment_rect_distance(a: Vector2, b: Vector2, r: Rect2) -> float:
	if r.has_point(a) or r.has_point(b):
		return 0.0
	var corners := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
	for i in 4:
		if Geometry2D.segment_intersects_segment(a, b, corners[i], corners[(i + 1) % 4]) != null:
			return 0.0
	var best := INF
	for c: Vector2 in corners:
		best = minf(best, (Geometry2D.get_closest_point_to_segment(c, a, b) - c).length())
	for p: Vector2 in [a, b]:
		best = minf(best, (p.clamp(r.position, r.end) - p).length())
	return best


## True if `pos` is under the deck within `margin` metres of a route centre line. Used to keep
## trees, lamps and poles out from under the freeway (buildings go by blocks_rect()).
func blocks(pos: Vector2, margin: float) -> bool:
	var key := Vector2i(floori(pos.x / CELL), floori(pos.y / CELL))
	if not _cells.has(key):
		return false
	for ref in _cells[key]:
		var route: Dictionary = routes[ref.x]
		var pts: PackedVector2Array = route.points
		var a := pts[ref.y]
		var ab := pts[ref.y + 1] - a
		var t := clampf((pos - a).dot(ab) / maxf(ab.length_squared(), 0.001), 0.0, 1.0)
		if pos.distance_to(a + ab * t) < route.width * 0.5 + margin:
			return true
	return false


## How long a route is, end to end, along the ground.
func length_of(route_index: int) -> float:
	if route_index < 0 or route_index >= _runs.size():
		return 0.0
	var run: PackedFloat32Array = _runs[route_index]
	return run[run.size() - 1]


## Where `t` metres along a route puts you: [Vector3 deck point, Vector2 heading]. The Y is the
## top of the deck, so a car sits at this plus its own ride height. `t` is clamped to the route.
func point_at(route_index: int, t: float) -> Array:
	var route: Dictionary = routes[route_index]
	var pts: PackedVector2Array = route.points
	var heights: PackedFloat32Array = route.heights
	var run: PackedFloat32Array = _runs[route_index]
	var last := pts.size() - 1
	t = clampf(t, 0.0, run[last])
	# Binary search for the segment holding t.
	var lo := 0
	var hi := last
	while hi - lo > 1:
		var mid := (lo + hi) / 2
		if run[mid] <= t:
			lo = mid
		else:
			hi = mid
	var seg := run[hi] - run[lo]
	var f: float = 0.0 if seg <= 0.0 else (t - run[lo]) / seg
	var p := pts[lo].lerp(pts[hi], f)
	var y := lerpf(heights[lo], heights[hi], f)
	var d := pts[hi] - pts[lo]
	return [Vector3(p.x, y, p.y), (d / maxf(d.length(), 0.001))]


## How far along a route the nearest point to `pos` is, and how far away it is:
## [t, distance]. Used to spawn traffic in a window around the player rather than everywhere.
func nearest_on(route_index: int, pos: Vector2) -> Array:
	var pts: PackedVector2Array = routes[route_index].points
	var run: PackedFloat32Array = _runs[route_index]
	var best_t := 0.0
	var best_d := INF
	for i in pts.size() - 1:
		var a := pts[i]
		var ab := pts[i + 1] - a
		var f := clampf((pos - a).dot(ab) / maxf(ab.length_squared(), 0.001), 0.0, 1.0)
		var d := pos.distance_to(a + ab * f)
		if d < best_d:
			best_d = d
			best_t = run[i] + (run[i + 1] - run[i]) * f
	return [best_t, best_d]
