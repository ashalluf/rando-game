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
## Max change in deck height per metre of run, so the grade is drivable.
const MAX_GRADE := 0.055

## Routes: {"name", "points": PackedVector2Array, "heights": PackedFloat32Array, "width": float}
var routes: Array[Dictionary] = []
## Ramps: {"route", "index", "side", "pos": Vector2, "yaw": float, "top": float}
var ramps: Array[Dictionary] = []

var _macro: MacroMap
var _cells: Dictionary = {}


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

	# 3. The valley route: climbs out of the basin through a pass in the front range and runs
	#    north across the inland valley.
	var valley := PackedVector2Array()
	var vz := -620.0
	while vz > macro.valley_to_z - 500.0:
		valley.append(Vector2(760.0 + 260.0 * sin((vz + 620.0) / 900.0), vz))
		vz -= STEP
	_add_route("Valley Freeway", valley, rng)

	_place_ramps(rng)
	_index()


## A route's deck height at one of its points: the ground below it plus the rise, smoothed and
## grade-limited so it does not follow every bump in the terrain.
func _add_route(route_name: String, pts: PackedVector2Array, rng: RandomNumberGenerator) -> int:
	if pts.size() < 4:
		return -1
	var raw := PackedFloat32Array()
	for p in pts:
		raw.append(_macro.height_at(p) + DECK_RISE)
	var heights := _smooth(raw)
	heights = _limit_grade(heights, pts)
	routes.append({
		"name": route_name, "points": pts, "heights": heights,
		"width": DECK_WIDTH * rng.randf_range(0.94, 1.08),
	})
	return routes.size() - 1


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
