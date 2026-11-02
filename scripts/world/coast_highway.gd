class_name CoastHighway
extends RefCounted
## The coast highway under the bluffs (the form of the Pacific Coast Highway north of Santa Monica,
## all names invented): north of the beach town the front range comes down to the sea, and the
## road runs on a bench a few metres over the sand, four lanes between the beach and a cut bluff.
## On the ocean side a row of beach houses stands on pilings over the sand with decks and stairs
## down to it, broken by open beach where cars park along the shoulder, surfers' vans among them,
## with lifeguard towers on the sand; at the north end a slide has closed the road.
##
## A pure plan (MacroMap.coast_highway, built in MacroMap.setup() after the marina and before the
## hill roads): the land profile across the coast is folded into MacroMap.raw_height_at() and the
## relief is calmed under it (`profile()`, `calm()`), so the terrain, the hill road's carve, the
## zones and the far ground all follow; the coast highway (HillRoads' "Pacific Coast Highway",
## COAST_INSET in from the waterline) is the centre line, its strip drawn here instead
## (CoastHighwayBuild). Everything is laid in d = x - coast_x(z), metres in from the waterline
## along +x, the same measure the road's own points use. Every roll is a hash of seed + place.

## Off: COAST_HIGHWAY=0 in the environment (the A/B).
static func enabled() -> bool:
	return OS.get_environment("COAST_HIGHWAY") != "0"


## The cross-section, in d (metres in from the waterline). The road's centre is HillRoads'.
const CENTRE := HillRoads.COAST_INSET
## Half the road: two lanes each way (LANE wide), a painted median and a parking shoulder each side.
const LANE := 3.6
const MEDIAN := 1.2
const SHOULDER := 2.8
const HALF := LANE * 2.0 + MEDIAN * 0.5 + SHOULDER
## The road's seaward and landward edges.
const ROAD_IN := CENTRE - HALF
const ROAD_OUT := CENTRE + HALF
## The seawall's face: the back of the sand, the street face of the beach houses. Between it and
## the road a concrete apron (driveways, the walk to the beach stairs).
const WALL := ROAD_IN - 3.4
## The bluff's toe, past a concrete gutter, and how steep it climbs (the hill road's carve holds
## it to 1:1 from the carriageway's own edge further up).
const TOE := ROAD_OUT + 1.6
const BLUFF_SLOPE := 1.5
## Where the profile hands the land back to the mountains, metres in from the waterline.
const REACH := 150.0
const REACH_FADE := 60.0
## The road's bench over the sea (terrain level; the asphalt lies ROAD_LIFT over it, like every
## hill road strip, so it meets the coast highway's strip south of the stretch at the same height).
const ROAD_Y := 4.0
const ROAD_LIFT := 0.26
## The north end: the coast highway's first point. North of it the mountains come back down to the
## road over NORTH_FADE metres - the slide that closed it. The south end: the bench comes down to
## the beach town's level between SOUTH_FULL and SOUTH_END metres south of the first point.
const NORTH_FADE := 90.0
const SOUTH_FULL := 470.0
const SOUTH_END := 600.0
## How far down the coast highway's strip past the stretch its traffic drives (CoastTraffic).
const TRAFFIC_RUN_ON := 320.0
## The closure: k-rails across the road, the slide's rocks on it, CLOSURE metres from the end.
const CLOSURE := 34.0

## Beach houses: a row of lots on the sand side of the wall. Runs of houses alternate with open
## beach along the shore in RUN-metre cells (HOUSE_ODDS of them houses); a house is WIDTH wide
## (along the shore) with GAP between, DEPTH deep from the wall, a deck DECK deep past its sea face.
const RUN := 70.0
const HOUSE_ODDS := 0.6
const WIDTH := Vector2(9.0, 14.5)
const GAP := Vector2(1.4, 3.2)
const DEPTH := Vector2(11.0, 14.0)
const DECK := Vector2(2.8, 4.2)
## Every ACCESS-th gap in a run is a public beach access way: wider, with a stair to the sand.
const ACCESS_EVERY := 5
const ACCESS_GAP := 4.2
## Styles: white modern, cedar shingle, grey board, pastel stucco.
enum Style { WHITE, CEDAR, BOARD, STUCCO }
const STYLE_ODDS := [0.36, 0.26, 0.2, 0.18]
## Parking: stall pitch along each shoulder, the share of stalls taken by the open beach and among
## the houses, and the share of the parked cars that are surfers' (a van, a pickup, an SUV with
## boards).
const STALL := 6.6
const PARK_OPEN := 0.5
const PARK_HOUSES := 0.3
const PARK_INLAND := 0.36
const SURF_SHARE := 0.32
## Lifeguard towers on the open beach: one per open stretch at least TOWER_MIN long, TOWER_D in.
const TOWER_MIN := 60.0
const TOWER_D := 9.0
## Beach stairs on open stretches, about every STAIR_EVERY metres.
const STAIR_EVERY := 110.0
## Street lamps on the bluff side, every LAMP_EVERY metres of z (a fixed phase, so chunks agree).
const LAMP_EVERY := 52.0

var seed: int = 0
var macro: MacroMap
## The road's north and south ends (z; north is negative), and where its bench is full height.
var z_north: float = 0.0
var z_full: float = 0.0
var z_south: float = 0.0
## The plan: houses, open stretches, towers, stairs, parking stalls (see build()).
var houses: Array[Dictionary] = []
var opens: Array[Vector2] = []
var towers: Array[Dictionary] = []
var stairs: Array[Dictionary] = []
var stalls: Array[Dictionary] = []
var _house_cells: Dictionary = {}
const CELL := 60.0


static func make(m: MacroMap, sd: int) -> CoastHighway:
	if not enabled():
		return null
	var ch := CoastHighway.new()
	ch.build(m, sd)
	return ch


func build(m: MacroMap, sd: int) -> void:
	macro = m
	seed = sd
	# The coast highway starts where HillRoads starts it (_add_coast_highway()).
	z_north = m.shelf_full_z - 420.0
	z_full = z_north + SOUTH_FULL
	z_south = z_north + SOUTH_END
	_plan_houses()
	_plan_beach()
	_plan_stalls()


static func _h(parts: Array) -> float:
	return float(absi(hash(parts)) % 1000003) / 1000003.0


func h01(parts: Array) -> float:
	return _h([seed, "coast_hwy"] + parts)


# --- The land -----------------------------------------------------------------------------------

## 0..1: how much of the coast highway's profile holds at z.
func weight(z: float) -> float:
	if z < z_north - NORTH_FADE or z > z_south:
		return 0.0
	return smoothstep(z_north - NORTH_FADE, z_north, z)


## The bench's height (terrain) at z: ROAD_Y over the stretch, down to the beach town's level
## south of z_full.
func bench_y(z: float) -> float:
	return ROAD_Y * (1.0 - smoothstep(z_full, z_south, z))


## The road bed's height at z: the coast highway's own profile (HillRoads smooths and grade-limits
## the bench it was sampled from, and carves the ground to it), or the bench before the hill roads
## are built.
func bed_y(z: float) -> float:
	if _pch_z.is_empty():
		_load_profile()
		if _pch_z.is_empty():
			return bench_y(z)
	var n := _pch_z.size()
	if z <= _pch_z[0]:
		return _pch_h[0]
	if z >= _pch_z[n - 1]:
		return _pch_h[n - 1]
	var i := clampi(int((z - _pch_z[0]) / (_pch_z[1] - _pch_z[0])), 0, n - 2)
	while i > 0 and _pch_z[i] > z:
		i -= 1
	while i < n - 2 and _pch_z[i + 1] < z:
		i += 1
	return lerpf(_pch_h[i], _pch_h[i + 1], clampf((z - _pch_z[i]) / maxf(_pch_z[i + 1] - _pch_z[i], 0.001), 0.0, 1.0))


var _pch_z := PackedFloat32Array()
var _pch_h := PackedFloat32Array()


func _load_profile() -> void:
	if macro == null or macro.hill_roads == null:
		return
	for r: Dictionary in macro.hill_roads.roads:
		if r.name != "Pacific Coast Highway":
			continue
		var pts: PackedVector2Array = r.points
		var hs: PackedFloat32Array = r.heights
		for i in pts.size():
			if pts[i].y > z_south + TRAFFIC_RUN_ON + 60.0:
				break
			_pch_z.append(pts[i].y)
			_pch_h.append(hs[i])
		return


## The asphalt's height at z.
func road_y(z: float) -> float:
	return bed_y(z) + ROAD_LIFT


## The land's height across the coast at (d, z) given the natural height there (`natural`, the
## mountains with the shore ramp): the sand under the seawall, the bench under the road, the cut
## bluff behind it, the mountains past REACH.
func profile(d: float, z: float, natural: float) -> float:
	var w := weight(z)
	if w <= 0.0 or d < -2.0 or d > REACH + REACH_FADE:
		return natural
	var by := bed_y(z)
	var h: float
	if d < WALL - 1.0:
		h = 0.0
	elif d < ROAD_IN:
		h = by * smoothstep(WALL - 1.0, ROAD_IN, d)
	elif d < TOE:
		h = by
	else:
		var cut := by + (d - TOE) * BLUFF_SLOPE
		if natural >= by:
			h = minf(natural, cut)
		else:
			# Lower ground behind the bench (the south end): back down to it.
			h = lerpf(by, natural, smoothstep(TOE, TOE + 30.0, d))
	if d > REACH:
		h = lerpf(h, natural, smoothstep(REACH, REACH + REACH_FADE, d))
	return lerpf(natural, h, w)


## The relief calmed to nothing under the profile (the bench and the sand are flat), handed back
## past the bluff.
func calm(pos: Vector2, relief: float) -> float:
	var w := weight(pos.y)
	if w <= 0.0:
		return relief
	var d := pos.x - macro.coast_x(pos.y)
	if d < -40.0 or d > REACH + REACH_FADE:
		return relief
	return relief * (1.0 - w * (1.0 - smoothstep(REACH, REACH + REACH_FADE, d)))


## The sand's width at z (MacroMap.beach_width_at()): out to the seawall over the stretch, back to
## the basin's `base` south of it.
func beach_width(z: float, base: float) -> float:
	var w := weight(z)
	if w <= 0.0:
		return base
	return lerpf(base, WALL - 0.5, w * (1.0 - smoothstep(z_full + 20.0, z_south, z)))


## True inside the stretch's built corridor (sand to the bluff's toe), `margin` metres grown: what
## the hill scatter, planting and shells keep off.
func covers(p: Vector2, margin: float = 0.0) -> bool:
	if p.y < z_north - CLOSURE - margin or p.y > z_south + margin:
		return false
	var d := p.x - macro.coast_x(p.y)
	return d > -margin and d < TOE + 3.0 + margin


## The z range of the stretch the road and the houses are this file's (the beach's path and court
## are not laid there: BeachLife.kept_off()).
func covers_z(z: float) -> bool:
	return z > z_north - CLOSURE and z < z_full + 40.0


## A point at d in from the waterline at z, true world XZ.
func at(d: float, z: float) -> Vector2:
	return Vector2(macro.coast_x(z) + d, z)


## The shore's frame at z: `land` (inland, unit) and `along` (+z, unit), as BeachLife uses it.
func frame(z: float) -> Array:
	var slope := (macro.coast_x(z + 2.0) - macro.coast_x(z - 2.0)) / 4.0
	return [Vector2(1.0, -slope).normalized(), Vector2(slope, 1.0).normalized()]


## Yaw of something facing the sea (its -Z toward -land) at z.
func sea_yaw(z: float) -> float:
	var land: Vector2 = frame(z)[0]
	return atan2(land.x, land.y)


# --- The plan -----------------------------------------------------------------------------------

func _plan_houses() -> void:
	houses.clear()
	opens.clear()
	_house_cells.clear()
	var z := z_north + CLOSURE + 26.0
	var end := z_full - 6.0
	var open_from := z
	while z < end:
		var cell := floori(z / RUN)
		var run_end := minf((float(cell) + 1.0) * RUN, end)
		if h01(["run", cell]) < HOUSE_ODDS and run_end - z > WIDTH.x:
			if z > open_from + 0.5:
				opens.append(Vector2(open_from, z))
			var k := 0
			while z + WIDTH.x < run_end:
				var w := lerpf(WIDTH.x, WIDTH.y, h01(["w", cell, k]))
				w = minf(w, run_end - z)
				var key := houses.size()
				var depth := lerpf(DEPTH.x, DEPTH.y, h01(["depth", cell, k]))
				var r := h01(["style", cell, k])
				var style := Style.STUCCO
				var acc := 0.0
				for s in STYLE_ODDS.size():
					acc += float(STYLE_ODDS[s])
					if r < acc:
						style = s as Style
						break
				var hs := {
					"z0": z, "z1": z + w, "zc": z + w * 0.5, "key": key, "style": style,
					"depth": depth, "deck": lerpf(DECK.x, DECK.y, h01(["deck", cell, k])),
					"floors": 2 if h01(["floors", cell, k]) < 0.68 else 1,
					"garage": h01(["garage", cell, k]) < 0.85,
					"garage_u": h01(["garage_u", cell, k]),
					"stair": h01(["stair", cell, k]) < 0.6,
					"stair_side": 1.0 if h01(["stair_side", cell, k]) < 0.5 else -1.0,
					"roof_deck": h01(["roof_deck", cell, k]) < 0.4,
					"tone": h01(["tone", cell, k]),
					"seed": absi(hash([seed, "coast_house", cell, k])),
				}
				houses.append(hs)
				for c in range(floori(z / CELL), floori((z + w) / CELL) + 1):
					if not _house_cells.has(c):
						_house_cells[c] = []
					(_house_cells[c] as Array).append(key)
				z += w
				k += 1
				var access := k % ACCESS_EVERY == 0
				var gap := ACCESS_GAP if access else lerpf(GAP.x, GAP.y, h01(["gap", cell, k]))
				if access and z + gap < run_end:
					stairs.append({"z": z + gap * 0.5, "dir": 1.0, "access": true})
				z += gap
			open_from = z
			z = maxf(z, run_end)
		else:
			z = run_end
	if end > open_from + 0.5:
		opens.append(Vector2(open_from, end))


func _plan_beach() -> void:
	towers.clear()
	for i in opens.size():
		var o := opens[i]
		var span := o.y - o.x
		if span >= TOWER_MIN:
			var tz := lerpf(o.x + 20.0, o.y - 20.0, h01(["tower", i]))
			towers.append({"z": tz, "d": TOWER_D + 3.0 * h01(["tower_d", i]), "key": i})
		# Stairs down the seawall: a few along each open stretch.
		var n := int(span / STAIR_EVERY)
		for k in n:
			var sz := o.x + (float(k) + 0.5) * span / n
			stairs.append({"z": sz, "dir": -1.0 if h01(["stair_dir", i, k]) < 0.5 else 1.0, "access": false})


## Parking stalls on both shoulders: {"d", "z", "side" (-1 sea, +1 bluff), "yaw", "key"}.
func _plan_stalls() -> void:
	stalls.clear()
	for side: float in [-1.0, 1.0]:
		var d := (ROAD_IN + SHOULDER * 0.5) if side < 0.0 else (ROAD_OUT - SHOULDER * 0.5)
		var z := z_north + CLOSURE + 12.0
		var k := 0
		while z < z_full - 8.0:
			k += 1
			var here := z
			z += STALL
			var odds := PARK_INLAND
			if side < 0.0:
				var hs := house_at(here, 1.5)
				if not hs.is_empty():
					# Never across a garage door; among the houses fewer anyway.
					if bool(hs.garage) and absf(here - garage_z(hs)) < 4.2:
						continue
					odds = PARK_HOUSES
				else:
					odds = PARK_OPEN
				if _stair_near(here, 4.0):
					continue
			if h01(["stall", side, k]) >= odds:
				continue
			# Facing the way the lane beside it runs (right-hand traffic: the sea side southbound).
			var land: Vector2 = frame(here)[0]
			var along: Vector2 = frame(here)[1]
			var fwd := along if side < 0.0 else -along
			stalls.append({"d": d, "z": here, "side": side, "yaw": atan2(-fwd.x, -fwd.y), "key": k,
				"surf": h01(["surf", side, k]) < SURF_SHARE, "seed": absi(hash([seed, "coast_car", side, k]))})


func _stair_near(z: float, r: float) -> bool:
	for s: Dictionary in stairs:
		if absf(float(s.z) - z) < r:
			return true
	return false


## The house whose lot holds z (grown `margin` along the shore), or {}.
func house_at(z: float, margin: float = 0.0) -> Dictionary:
	var c := floori(z / CELL)
	for cc in [c - 1, c, c + 1]:
		for key: int in _house_cells.get(cc, []):
			var hs: Dictionary = houses[key]
			if z >= float(hs.z0) - margin and z <= float(hs.z1) + margin:
				return hs
	return {}


## The z of a house's garage door's centre.
func garage_z(hs: Dictionary) -> float:
	var w := float(hs.z1) - float(hs.z0)
	return lerpf(float(hs.z0) + 2.0, float(hs.z1) - 2.0, clampf(float(hs.garage_u), 0.0, 1.0)) if w > 6.0 else float(hs.zc)


## Houses, towers, stairs and stalls whose z falls in [z0, z1).
func houses_in(z0: float, z1: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for hs: Dictionary in houses:
		if float(hs.zc) >= z0 and float(hs.zc) < z1:
			out.append(hs)
	return out


func items_in(list: Array, z0: float, z1: float) -> Array:
	var out := []
	for it: Dictionary in list:
		if float(it.z) >= z0 and float(it.z) < z1:
			out.append(it)
	return out
