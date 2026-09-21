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
## Points are this far apart along a route; the deck is built from them directly.
const STEP := 24.0
const CELL := 160.0
## Max change in deck height per metre of run, so the grade is drivable. Steep for a freeway,
## but the valley route has to climb through the pass and real mountain freeways do 6 to 7 %.
const MAX_GRADE := 0.07
## The deck never gets closer than this to the ground underneath it.
const MIN_CLEARANCE := 4.0
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
	_add_route("Coast Freeway", coast, rng)

	# 2. The cross route: west to east through the middle of the basin, south of downtown, with
	#    a long sweeping curve in it.
	var cross := PackedVector2Array()
	var x := macro.coast_x(560.0) + 60.0
	while x < macro.east_start_x + 300.0:
		cross.append(Vector2(x, 520.0 + 190.0 * sin(x / 780.0 + 0.6) + 60.0 * sin(x / 210.0)))
		x += STEP
	_add_route("Cross Freeway", cross, rng)

	# 3. The valley route: starts down in the basin, climbs through the pass in the front range
	#    and runs north across the inland valley. It starts a long way south on purpose - the
	#    climb to the valley floor is the whole run, and a short route cannot do it at a
	#    drivable grade.
	var valley := PackedVector2Array()
	var vz := 500.0
	var pass_z: float = (macro.hills_full_z + macro.valley_from_z) * 0.5
	while vz > macro.valley_to_z - 700.0:
		# Zero at the pass, so the route threads it and curves away either side.
		var t := (vz - pass_z) / 1100.0
		valley.append(Vector2(macro.pass_center_x + 210.0 * sin(t * 1.4), vz))
		vz -= STEP
	_add_route("Valley Freeway", valley, rng)

	_place_ramps(rng)
	_index()


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
## MAX_GROUND and not out at sea. Everything outside it is dropped, so a route ends where the
## basin does instead of running up a cliff with its deck buried under the hillside.
func _drivable(pts: PackedVector2Array) -> PackedVector2Array:
	var best_from := 0
	var best_len := 0
	var run_from := -1
	for i in pts.size():
		var p := pts[i]
		if _macro.height_at(p) <= MAX_GROUND and _macro.zone_at(p) != MacroMap.Zone.OCEAN:
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


## True if `pos` is under the deck within `margin` metres of a route centre line. Used to keep
## buildings, trees and lamps out from under the freeway.
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
