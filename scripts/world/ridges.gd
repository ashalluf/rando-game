class_name Ridges
extends RefCounted
## What stands on Los Angeles's hills (roadmap #59): the high-voltage transmission lines marching
## over the ranges and down through the industrial district to a substation, the antenna farm on
## the front range's highest summit, the dirt fire roads along the crests and down the spurs, a
## fire lookout, round green water tanks on the knolls above the estates, and radar / weather
## domes on the east range. This is the DATA: pure, worked out from the seed and the map, never
## placed by hand. RidgeKit builds the meshes, RidgeBuild the chunk steps, RidgeSystem (a node in
## city.tscn) the far tier: every tower's and mast's lattice as fine lines, every wire, the red
## obstruction lights.
##
## Two halves. `build_terrain()` runs in MacroMap.setup() after the switchbacks (so nothing that
## was planned before moves) and CARVES: the fire roads are HillRoads roads ("fire": true,
## "draw": false - RidgeBuild draws them in dirt) and every pad (the farm's summit, a tank's
## knoll, the lookout, a dome) is a short wide road segment ("pad": true), so carve(), the hill
## shells, the planting and the far canopy all keep off them with no code of their own. The lines
## need the city plan (blocks, lots, the river, the freeway), so they are planned lazily on first
## use (`Ridges.of(plan)`), and CityPlan.lots() asks `claims_lot()` to drop the lots under the
## right of way and the substation AFTER every roll.
## `RIDGES=0` in the environment (or `-- --no-ridges`) leaves all of it out (the A/B).

enum Kind { SUSPENSION, ANGLE, TERMINAL }
enum Site { TANK, DOME, LOOKOUT, HUT, DISH, FARM_PAD }
enum Mast { GUYED, LATTICE, MONOPOLE }

# --- Towers ----------------------------------------------------------------------------------
## Tower heights the planner may pick, metres from the body's base to the earth-wire peak. A
## 220 kV double-circuit lattice tower in the hills round the basin stands 40-60 m.
const HEIGHTS: Array[float] = [46.0, 58.0, 72.0]
## Span limits, metres (a 220 kV line in rough country spans 250-500 m, longer over a canyon).
const SPAN_MIN := 230.0
const SPAN_MAX := 480.0
const CITY_SPAN_MAX := 340.0
## The shortest span the planner falls back to on a climb a long one cannot clear.
const SPAN_SHORT := 90.0
## The spots the planner tries along a leg, metres apart.
const DP_STEP := 25.0
## The corridor raster the planner measures moved spans on: metres along, across, and its half width.
const RASTER_U := 10.0
const RASTER_V := 6.0
const RASTER_V_HALF := 66.0
## Lowest conductor over the ground, metres, anywhere in a span.
const CLEAR := 13.0
## Sag = SAG_K * span^2 (a 400 m span sags 11 m: an ACSR conductor at everyday tension).
const SAG_K := 7.0e-5
## The longest a leg may be extended below the body's base on a slope.
const MAX_LEG_EXT := 20.0
## ... and on a peak.
const PEAK_LEG_EXT := 32.0
## Half the right of way through the city, metres: no lot stands within it.
const ROW_HALF := 16.0
## The substation yard's longest side, metres.
const SUB_MAX := 200.0
## Suspension insulator string, metres (arm tip to the conductor clamp).
const STRING := 3.3
## Tension string length at an angle or terminal tower.
const TENSION := 3.6
## Two sub-conductors a phase, this far apart (a twin bundle).
const BUNDLE := 0.46

# --- The antenna farm, tanks, domes ----------------------------------------------------------
## The farm's benches: their radius (the summit's), and their spacing along the crest.
const FARM_PAD_R := 10.5
const FARM_STEP := 30.0
const TANK_MAX := 6
## Summits (besides the farm, lookout and domes) a crest fire road is walked from.
const EXTRA_CREST_SUMMITS := 6
## Summits kept from the coarse search per range (the highest), refined to their true tops.
const SUMMITS_KEPT := 30
const TANK_SPACING := 520.0
const FIRE_WIDTH := 5.0
const FIRE_GRADE := 0.75
## Step along a fire road walk, metres.
const FIRE_STEP := 20.0
## Steepest raw ground a fire road walk steps onto (its bed is then held to FIRE_GRADE), and the
## most its bed may stand off the ground on its centre line (a fire road hugs the ground).
const WALK_GRADE := 0.72
## The widest turn a walk takes in one step, radians.
const WALK_TURN := 1.2
const FIRE_EARTHWORK := 6.0
## How far a pad's fill bank may fall short of the hillside at the end of its reach.
const PAD_FALL_SLACK := 22.0

var macro: MacroMap
var seed: int = 0
## Every tower: {"id", "line", "pos" Vector2, "yaw", "dir" Vector2 (along the line, the bisector at
## an angle), "h", "base" (the body's base, world y), "legs" [4 ground heights], "kind", "turn"
## (radians, signed), "city" bool}. Gantries are not towers (see `substation`).
var towers: Array[Dictionary] = []
## Lines: {"name", "towers": Array[int] in order from the substation out, "gantry": index into
## substation.gantries}.
var lines: Array[Dictionary] = []
## The substation: {"rect" Rect2, "block" Vector2i, "base" y, "gantries": [{"pos","yaw","dir","base",
## "line"}], "transformers": [Transform], ...} or empty.
var substation: Dictionary = {}
## Masts of the antenna farm: {"id", "pos", "base", "h", "kind", "guys": [anchor Vector3...],
## "levels": [guy heights], "face" (yaw), "dishes": [[height, yaw, radius]]}.
var masts: Array[Dictionary] = []
## Small sites: {"id", "kind", "pos", "base", "r", "h", "yaw"}.
var sites: Array[Dictionary] = []
## The antenna farm: {"pos", "base", "axis" Vector2, "half" Vector2} or empty.
var farm: Dictionary = {}
## Indices into macro.hill_roads.roads of the fire roads and tank tracks.
var fire_roads: Array[int] = []
## Gates where a fire road meets the public road or the city: {"pos", "base", "yaw", "w"}.
var gates: Array[Dictionary] = []
## Summits found on the coarse lattice: [Vector2 pos, float height, int region].
var summits: Array = []

var _lines_built := false
var _plan: CityPlan
## Right-of-way pieces in the city: [Vector2 a, Vector2 b] segments, and a cell index of them.
var _row: Array = []
var _row_cells: Dictionary = {}
const ROW_CELL := 200.0
## The lots a block lost to the ridges: Vector2i block -> Array[Rect2] (their grid cells).
var claimed_cells: Dictionary = {}
var _cache_on := false
var _t_mark := 0
var _t_dp_prep := 0
var _t_dp := 0
var _t_g := 0
var _bad_spans := 0
var _t_ok := 0
var _gcache: Dictionary = {}


static func enabled() -> bool:
	return OS.get_environment("RIDGES") != "0" and not OS.get_cmdline_user_args().has("--no-ridges")


## The plan's ridges with its lines planned, or null.
static func of(plan: CityPlan) -> Ridges:
	if plan == null or plan.macro == null or plan.macro.ridges == null:
		return null
	var r: Ridges = plan.macro.ridges
	if not r._lines_built:
		r._lines_built = true
		r._plan = plan
		r._plan_lines(plan)
	return r


static func _h01(parts: Array) -> float:
	return float(absi(hash(parts)) % 100003) / 100003.0


# =============================================================================================
# Terrain half: summits, pads, fire roads (MacroMap.setup()).
# =============================================================================================

func build_terrain(m: MacroMap, seed_value: int) -> void:
	macro = m
	seed = seed_value
	if macro.hill_roads == null:
		return
	var t0 := Time.get_ticks_usec()
	_cache_on = true
	_find_summits()
	_place_farm()
	_place_east_sites()
	_crest_roads()
	_place_tanks()
	_cache_on = false
	_gcache.clear()
	_ucache.clear()
	macro.hill_roads._index()
	if OS.get_environment("RIDGE_DEBUG") != "":
		print("RIDGES terrain %d ms: %d summits, farm %s, %d masts, %d sites, %d fire roads, %d gates" % [
			(Time.get_ticks_usec() - t0) / 1000, summits.size(), farm.get("pos", "-"), masts.size(), sites.size(), fire_roads.size(), gates.size()])


## The mountains alone (no relief, no carving), cached on a 5 m lattice while planning.
func _raw(p: Vector2) -> float:
	if not _cache_on:
		return macro.raw_height_at(p)
	var k := Vector2i(roundi(p.x / 5.0), roundi(p.y / 5.0))
	var v: Variant = _gcache.get(k)
	if v == null:
		v = macro.raw_height_at(Vector2(k) * 5.0)
		_gcache[k] = v
	return v


## The carved ground, cached on a 5 m lattice while planning (cleared whenever something is carved).
func _hc(p: Vector2) -> float:
	var k := Vector2i(roundi(p.x / 5.0), roundi(p.y / 5.0))
	var v: Variant = _hcache.get(k)
	if v == null:
		v = macro.height_at(Vector2(k) * 5.0)
		_hcache[k] = v
	return v


var _hcache: Dictionary = {}


## The ground before any carving: what the hill roads are cut into.
func _uncarved(p: Vector2) -> float:
	if _cache_on:
		var k := Vector2i(roundi(p.x / 4.0), roundi(p.y / 4.0))
		var v: Variant = _ucache.get(k)
		if v == null:
			var q := Vector2(k) * 4.0
			var r0 := macro.raw_height_at(q)
			v = r0 + macro._relief_at(q, r0)
			_ucache[k] = v
		return v
	var r := macro.raw_height_at(p)
	return r + macro._relief_at(p, r)


var _ucache: Dictionary = {}


## True when no road, pad or estate's banks reach `p` (nor within `r` of it, on a ring).
func _free(p: Vector2, r: float, ring: int = 8) -> bool:
	var hr := macro.hill_roads
	var spots: Array[Vector2] = [p]
	if r > 0.0:
		for a in ring:
			spots.append(p + Vector2.from_angle(TAU * a / ring) * r)
	for q in spots:
		var u := _uncarved(q)
		if absf(hr.carve(q, u) - u) > 0.05:
			return false
	return true


## Kept clear of the landmarks, the freeway, the replica, the coast and the city.
func _site_ok(p: Vector2, reach: float) -> bool:
	if macro.zone_at(p) != MacroMap.Zone.HILLS:
		return false
	for lm in Landmarks.all():
		if p.distance_to(lm.anchor) < float(lm.radius) + reach + 60.0:
			return false
	if macro.freeway and macro.freeway.blocks(p, reach + 50.0):
		return false
	if macro.headland_dist(p) < 400.0:
		return false
	for m: Dictionary in macro.hill_roads.mansions:
		if p.distance_to(m.pos) < reach + 45.0:
			return false
	return true


## Where the planner looks for summits: the front range south of the valley, and the east range.
func _region_of(p: Vector2) -> int:
	if p.x > macro.east_start_x + 150.0 and p.x < 7800.0 and p.y > -3200.0 and p.y < 5600.0:
		return 1
	if p.x > -1300.0 and p.x < macro.east_start_x - 100.0 and macro.plateau_at(p) < 5.0 and p.y < macro.hills_start_z:
		return 0
	return -1


func _find_summits() -> void:
	summits.clear()
	var step := 75.0
	var grid := {}
	for region: Rect2 in [Rect2(-1300.0, -3700.0, 6200.0, 2800.0), Rect2(5150.0, -3200.0, 2650.0, 8800.0)]:
		var nx := int(region.size.x / step)
		var nz := int(region.size.y / step)
		for j in nz:
			for i in nx:
				var p := region.position + Vector2(i, j) * step
				grid[Vector2i(roundi(p.x / step), roundi(p.y / step))] = _raw(p)
	for k: Vector2i in grid:
		var h: float = grid[k]
		if h < 60.0:
			continue
		var top := true
		for dj in range(-2, 3):
			for di in range(-2, 3):
				if (di != 0 or dj != 0) and float(grid.get(k + Vector2i(di, dj), -1.0)) >= h:
					top = false
		if not top:
			continue
		var p := Vector2(k) * step
		var reg := _region_of(p)
		if reg < 0:
			continue
		summits.append([p, h, reg])
	summits.sort_custom(func(a: Array, b: Array) -> bool: return float(a[1]) > float(b[1]))
	var kept: Array = []
	var per := [0, 0]
	for sm: Array in summits:
		if per[int(sm[2])] < SUMMITS_KEPT:
			per[int(sm[2])] += 1
			kept.append(sm)
	summits = kept
	for si in summits.size():
		var p: Vector2 = summits[si][0]
		var h: float = summits[si][1]
		# Climb to the true top on a finer lattice.
		var best := p
		var bh := h
		for pass_i in 3:
			var s := [24.0, 10.0, 4.0][pass_i] as float
			var c := best
			for dj in range(-2, 3):
				for di in range(-2, 3):
					var q := c + Vector2(di, dj) * s
					var qh := _raw(q)
					if qh > bh:
						bh = qh
						best = q
		summits[si] = [best, bh, summits[si][2]]
	summits.sort_custom(func(a: Array, b: Array) -> bool: return float(a[1]) > float(b[1]))


## The axis along which a summit falls least (its ridge line): the pad and the farm lie along it.
func _ridge_axis(p: Vector2) -> Vector2:
	var best := Vector2.RIGHT
	var drop := INF
	for a in 12:
		var d := Vector2.from_angle(PI * a / 12.0)
		var h := _raw(p)
		var fall := (h - _raw(p + d * 45.0)) + (h - _raw(p - d * 45.0))
		if fall < drop:
			drop = fall
			best = d
	return best


## A pad (a short wide road: carve() levels it, everything keeps off it) at `p` along `axis`,
## `half` its half size (along, across). Tries cuts down from the ground at `p`; the level it
## got, or NAN when the slopes round it cannot be graded.
func _add_pad(p: Vector2, axis: Vector2, half: Vector2, name: String) -> float:
	var g := _uncarved(p)
	var across := Vector2(-axis.y, axis.x)
	for cut: float in [1.5, 4.0, 7.0, 10.0, 14.0, 18.0]:
		var h := g - cut
		var ok := true
		var e := HillRoads.BANK_REACH - HillRoads.BANK_FADE
		for a in 12:
			var d := Vector2.from_angle(TAU * a / 12.0)
			# The stadium's rim in that direction, then the bank's reach beyond it.
			var rim := p + axis * clampf(d.dot(axis) * 1e4, -(half.x - half.y), half.x - half.y) + d * half.y
			# The cut bank must meet the hillside; a fill may hand back to a slope that falls away
			# faster than its own (a summit's flanks), but not by more than a storey or two.
			var q := rim + d * e
			var dh := _uncarved(q) - h
			if dh > HillRoads.CUT_BANK * e + HillRoads.EARTHWORK_SLACK or -dh > HillRoads.FILL_BANK * e + PAD_FALL_SLACK:
				ok = false
				break
			# The pad's own floor must not stand far out over its rim (a fill a storey high).
			if _uncarved(rim) - h < -9.0:
				ok = false
				break
		if not ok:
			continue
		var a0 := p - axis * maxf(half.x - half.y, 0.5)
		var a1 := p + axis * maxf(half.x - half.y, 0.5)
		macro.hill_roads.roads.append({"name": name, "points": PackedVector2Array([a0, a1]), "heights": PackedFloat32Array([h, h]),
			"width": half.y * 2.0, "mansions": false, "planned_points": PackedVector2Array([a0, a1]), "draw": false, "pad": true})
		macro.hill_roads._index()
		_hcache.clear()
		return h
	return NAN


func _place_farm() -> void:
	# The highest front-range summit that can take the farm: tried highest first. These summits are
	# eroded spikes (the ground falls 20-60 m within 30 m of a top), so the farm is a row of small
	# benches stepped along the crest, a mast compound on each, as on the real peaks above the basin.
	for s: Array in summits:
		if int(s[2]) != 0:
			continue
		var p: Vector2 = s[0]
		if not _site_ok(p, 90.0) or not _free(p, 60.0):
			continue
		var crest := _crest_line(p, _ridge_axis(p), 3, FARM_STEP)
		var roads_before := macro.hill_roads.roads.size()
		var pads: Array = []
		for c: Array in crest:
			var q: Vector2 = c[0]
			var r := FARM_PAD_R if int(c[1]) == 0 else FARM_PAD_R - 1.5
			var h := _add_pad(q, c[2], Vector2(r, r), "Antenna farm")
			if not is_nan(h):
				pads.append([q, h, c[2], int(c[1]), r])
		if pads.size() < 4:
			macro.hill_roads.roads.resize(roads_before)
			macro.hill_roads._index()
			continue
		farm = {"pos": p, "base": float(pads[0][1]), "axis": _ridge_axis(p), "pads": pads, "summit": float(s[1])}
		_lay_farm()
		return


## Points along the crest either way from a summit `p`, `n` steps of `step` metres each way:
## [[pos, index (0 at the summit, negative one way), crest direction]], summit first.
func _crest_line(p: Vector2, axis: Vector2, n: int, step: float) -> Array:
	var out: Array = [[p, 0, axis]]
	for sg: int in [1, -1]:
		var q := p
		var dir := axis * float(sg)
		for k in n:
			var best := Vector2.INF
			var best_dir := dir
			var best_score := -INF
			for dt: float in [-0.6, -0.3, 0.0, 0.3, 0.6]:
				var d := dir.rotated(dt)
				var c := q + d * step
				var score := _crestness(c, d) - absf(dt) * 4.0
				if score > best_score:
					best_score = score
					best = c
					best_dir = d
			if best_score < -3.0:
				break
			q = best
			dir = best_dir
			out.append([q, (k + 1) * sg, dir * float(sg)])
	out.sort_custom(func(x: Array, y: Array) -> bool: return absi(int(x[1])) < absi(int(y[1])))
	return out


## The masts on the farm's benches: the tallest guyed mast on the summit, lattice towers,
## monopoles and a second guyed mast along the crest, an equipment hut beside each, dishes on the
## masts and a couple on the ground. Heights are hashes.
func _lay_farm() -> void:
	var kinds := [Mast.GUYED, Mast.LATTICE, Mast.MONOPOLE, Mast.GUYED, Mast.LATTICE, Mast.MONOPOLE, Mast.LATTICE]
	var heights := [[150.0, 40.0], [52.0, 22.0], [34.0, 12.0], [105.0, 35.0], [40.0, 18.0], [28.0, 10.0], [36.0, 14.0]]
	var pads: Array = farm.pads
	for i in pads.size():
		var pad: Array = pads[i]
		var at: Vector2 = pad[0]
		var base: float = pad[1]
		var axis: Vector2 = pad[2]
		var r: float = pad[4]
		var across := Vector2(-axis.y, axis.x)
		var kind: int = kinds[i % kinds.size()]
		var hh: Array = heights[i % heights.size()]
		var mh := float(hh[0]) + _h01([seed, "mast_h", i]) * float(hh[1])
		var yaw := atan2(axis.x, axis.y)
		var mp := at - across * (1.5 if kind == Mast.GUYED else 2.5)
		var m := {"id": "mast%d" % i, "pos": mp, "base": base, "h": mh, "kind": kind, "face": yaw + float(i) * 0.7,
			"guys": [], "levels": [], "dishes": []}
		if kind == Mast.GUYED:
			# Three anchors 120 degrees apart, 0.45-0.55 of the height out, where they land.
			var out := mh * (0.45 + 0.1 * _h01([seed, "guy_out", i]))
			var a0 := atan2(axis.y, axis.x) + PI / 6.0 + _h01([seed, "guy_a", i]) * 0.3
			for k in 3:
				var q: Vector2 = mp + Vector2.from_angle(a0 + TAU * k / 3.0) * out
				m.guys.append(q)
			var n := 4 if mh > 140.0 else 3
			for k in n:
				m.levels.append(mh * (float(k) + 0.8) / (float(n) + 0.4))
		var nd := 1 + int(_h01([seed, "dishes", i]) * 3.0)
		for k in nd:
			var dh := mh * (0.3 + 0.45 * _h01([seed, "dish_h", i, k]))
			m.dishes.append([dh, TAU * _h01([seed, "dish_yaw", i, k]), 0.9 + 0.9 * _h01([seed, "dish_r", i, k])])
		masts.append(m)
		sites.append({"id": "hut%d" % i, "kind": Site.HUT, "pos": at + across * (r - 3.4), "base": base,
			"r": 2.4 + _h01([seed, "hut_r", i]) * 1.0, "h": 2.9 + _h01([seed, "hut_h", i]) * 0.6, "yaw": yaw})
		if i == 1 or i == 2:
			sites.append({"id": "gdish%d" % i, "kind": Site.DISH, "pos": at + axis * (r - 3.0), "base": base, "r": 1.8 + i * 0.5,
				"h": 3.2, "yaw": TAU * _h01([seed, "gdish", i])})


## The lookout on the highest east-range summit, domes on the next two that stand clear of it.
func _place_east_sites() -> void:
	var taken: Array[Vector2] = []
	if not farm.is_empty():
		taken.append(farm.pos)
	var want := [Site.LOOKOUT, Site.DOME, Site.DOME]
	var k := 0
	for s: Array in summits:
		if k >= want.size():
			break
		var p: Vector2 = s[0]
		var region := int(s[2])
		if region != 1 or p.x > 6600.0:
			continue
		var far := true
		for q in taken:
			far = far and p.distance_to(q) > 900.0
		if not far or not _site_ok(p, 60.0) or not _free(p, 50.0):
			continue
		var kind: int = want[k]
		var half := Vector2(13.0, 11.0) if kind == Site.LOOKOUT else Vector2(16.0, 14.0)
		var axis := _ridge_axis(p)
		var h := _add_pad(p, axis, half, "Lookout" if kind == Site.LOOKOUT else "Dome")
		if is_nan(h):
			continue
		taken.append(p)
		var r := 0.0
		var ht := 0.0
		if kind == Site.DOME:
			r = 5.5 + _h01([seed, "dome_r", k]) * 2.5
			ht = 6.0 + _h01([seed, "dome_h", k]) * 10.0
		else:
			ht = 12.0
			r = 3.6
		sites.append({"id": "site%d" % k, "kind": kind, "pos": p, "base": h, "r": r, "h": ht, "yaw": atan2(axis.x, axis.y), "summit": float(s[1])})
		k += 1


# --- Fire roads ------------------------------------------------------------------------------

## How much `q` stands over the ground either side of `dir`, 25 m out: positive on a crest.
func _crestness(q: Vector2, dir: Vector2) -> float:
	var n := Vector2(-dir.y, dir.x)
	return _raw(q) - 0.5 * (_raw(q + n * 25.0) + _raw(q - n * 25.0))


## A walk along a crest (down < 0: down a spur, falling all the way). Returns the points walked.
func _walk_crest(start: Vector2, heading: Vector2, max_steps: int, down: bool, own: PackedVector2Array) -> PackedVector2Array:
	var pts := PackedVector2Array([start])
	var p := start
	var dir := heading.normalized()
	var junction := start
	for n in max_steps:
		var best := Vector2.INF
		var best_dir := dir
		var best_score := -INF
		var hp := _raw(p)
		# Any heading within WALK_TURN of the last: a fire road on ground this rugged keeps to the
		# crests where it can and sidles round a knob where it cannot.
		for k in 19:
			var dt := WALK_TURN * (float(k) / 9.0 - 1.0)
			var d := dir.rotated(dt)
			var q := p + d * FIRE_STEP
			var gq := _raw(q)
			var grade := (gq - hp) / FIRE_STEP
			# Off a summit's spike the first steps may be steeper: the pad and the bed cut it down.
			var limit := WALK_GRADE * (1.4 if pts.size() < 3 else 1.0)
			if absf(grade) > limit:
				continue
			if down and grade > 0.04:
				continue
			var c := _crestness(q, d)
			var score := clampf(c, -6.0, 10.0) * 0.6 - absf(dt) * 3.0
			if down:
				score += clampf(-grade, 0.0, 0.22) * 30.0
			else:
				score -= absf(grade) * 10.0
			if score > best_score:
				best_score = score
				best = q
				best_dir = d
		if best == Vector2.INF:
			_why("steep after %d" % pts.size())
			break
		# Keep off itself and the other fire roads, out of the city and the landmarks, and clear of
		# every other road's banks (a junction's first metres excepted).
		var crowded := false
		for i in maxi(own.size(), 0):
			if own[i].distance_to(best) < 45.0 and best.distance_to(junction) > 60.0:
				crowded = true
				break
		for i in maxi(pts.size() - 4, 0):
			if pts[i].distance_to(best) < 32.0:
				crowded = true
				break
		if crowded or macro.zone_at(best) != MacroMap.Zone.HILLS or _region_of(best) < 0:
			_why("crowded/zone %s %d %d" % [crowded, macro.zone_at(best), _region_of(best)])
			break
		if not _site_ok(best, 10.0):
			_why("site")
			break
		if best.distance_to(junction) > 110.0 and not _free(best, FIRE_WIDTH * 0.5 + 18.0):
			_why("not free")
			break
		pts.append(best)
		p = best
		dir = best_dir
		if down and _raw(p) < 30.0:
			break
	return pts


func _why(what: String) -> void:
	if OS.get_environment("RIDGE_DEBUG") != "":
		print("  walk stops: ", what)


## The road's bed: the ground smoothed, held to FIRE_GRADE, pinned to `start_h` if given, and kept
## as far as its banks can be graded (HillRoads' own test). Adds it; the index, or -1.
func _add_fire_road(name: String, pts: PackedVector2Array, start_h: float, min_len: float) -> int:
	if pts.size() < 3:
		return -1
	var hr := macro.hill_roads
	var hs := PackedFloat32Array()
	for q in pts:
		hs.append(_uncarved(q))
	# A light 3-tap smoothing: the bed hugs the crest (these are the fire breaks and fire roads
	# bulldozed straight along the ridgelines, as steep as the ridge is).
	var sm := hs.duplicate()
	for i in range(1, hs.size() - 1):
		sm[i] = (hs[i - 1] + hs[i] * 2.0 + hs[i + 1]) * 0.25
	hs = sm
	if not is_nan(start_h):
		hs[0] = start_h
	for i in range(1, hs.size()):
		var run := pts[i].distance_to(pts[i - 1])
		hs[i] = clampf(hs[i], hs[i - 1] - FIRE_GRADE * run, hs[i - 1] + FIRE_GRADE * run)
	if is_nan(start_h):
		for i in range(hs.size() - 2, -1, -1):
			var run := pts[i].distance_to(pts[i + 1])
			hs[i] = clampf(hs[i], hs[i + 1] - FIRE_GRADE * run, hs[i + 1] + FIRE_GRADE * run)
	var keep := pts.size()
	for i in pts.size():
		if i > 3 and absf(hs[i] - _uncarved(pts[i])) > FIRE_EARTHWORK:
			keep = i
			break
	_why("road kept %d of %d" % [keep, pts.size()])
	if keep < 3:
		return -1
	var len := 0.0
	for i in range(1, keep):
		len += pts[i].distance_to(pts[i - 1])
	if len < min_len:
		return -1
	hr.roads.append({"name": name, "points": pts.slice(0, keep), "heights": hs.slice(0, keep), "width": FIRE_WIDTH,
		"mansions": false, "planned_points": pts.slice(0, keep), "draw": false, "fire": true})
	hr._index()
	_hcache.clear()
	fire_roads.append(hr.roads.size() - 1)
	return hr.roads.size() - 1


## Fire roads: along the crest both ways from the antenna farm's end benches, the lookout and
## the domes, and down a spur or two from each crest road toward the foot of the range, gated at
## the bottom. Walked (`_walk_crest()`), not searched: the ranges are steeper than 45 degrees off
## their crests almost everywhere, so a road can only be where a crest or a spur carries it.
func _crest_roads() -> void:
	var starts: Array = []
	if not farm.is_empty():
		var pads: Array = farm.pads
		for sg: int in [1, -1]:
			var end: Array = []
			for pad: Array in pads:
				if signi(int(pad[3])) == sg and (end.is_empty() or absi(int(pad[3])) > absi(int(end[3]))):
					end = pad
			if not end.is_empty():
				var ax: Vector2 = (end[2] as Vector2) * float(sg)
				starts.append([(end[0] as Vector2) + ax * (float(end[4]) + 2.0), ax, float(end[1]), "Summit Fire Rd"])
	for s: Dictionary in sites:
		if s.kind == Site.LOOKOUT or s.kind == Site.DOME:
			var ax := Vector2(sin(float(s.yaw)), cos(float(s.yaw)))
			starts.append([s.pos + ax * 15.0, ax, s.base, "Ridge Fire Rd"])
			starts.append([s.pos - ax * 15.0, -ax, s.base, "Ridge Fire Rd"])
	# And along the crests from the higher summits that are clear of everything else.
	var extra := 0
	for sm: Array in summits:
		if extra >= EXTRA_CREST_SUMMITS:
			break
		var p: Vector2 = sm[0]
		var clear := true
		for st: Array in starts:
			clear = clear and p.distance_to(st[0]) > 700.0
		if not clear or not _site_ok(p, 30.0) or not _free(p, 30.0) or (int(sm[2]) == 1 and p.x > 6800.0):
			continue
		var ax := _ridge_axis(p)
		starts.append([p, ax, NAN, "Crest Fire Rd"])
		starts.append([p, -ax, NAN, "Crest Fire Rd"])
		extra += 1
	var own := PackedVector2Array()
	var crest_ids: Array[int] = []
	for st: Array in starts:
		var pts := _walk_crest(st[0], st[1], 70, false, own)
		var ri := _add_fire_road("%s %d" % [st[3], fire_roads.size() + 1], pts, st[2], 160.0)
		if ri >= 0:
			crest_ids.append(ri)
			own.append_array(macro.hill_roads.roads[ri].points)
	# Spurs: along each crest road, toward whichever side falls away, down to the range's foot.
	for ri in crest_ids:
		var road: Dictionary = macro.hill_roads.roads[ri]
		var pts: PackedVector2Array = road.points
		var hs: PackedFloat32Array = road.heights
		var i := 6
		var made := 0
		while i < pts.size() - 3 and made < 2:
			var d := (pts[i + 1] - pts[i - 1]).normalized()
			var n := Vector2(-d.y, d.x)
			var side := n if _raw(pts[i] + n * 60.0) < _raw(pts[i] - n * 60.0) else -n
			var walk := _walk_crest(pts[i], side, 80, true, own)
			if walk.size() > 8:
				var si := _add_fire_road("Spur Fire Rd %d" % (fire_roads.size() + 1), walk, hs[i], 180.0)
				if si >= 0:
					made += 1
					var sp: PackedVector2Array = macro.hill_roads.roads[si].points
					own.append_array(sp)
					_gate_at_end(si)
					i += 16
					continue
			i += 5


func _gate_at_end(ri: int) -> void:
	var sp: PackedVector2Array = macro.hill_roads.roads[ri].points
	var sh: PackedFloat32Array = macro.hill_roads.roads[ri].heights
	var e := sp.size() - 1
	var dir := (sp[e] - sp[e - 1]).normalized()
	gates.append({"pos": sp[e] - dir * 4.0, "base": sh[e] - dir.dot(Vector2.ZERO), "yaw": atan2(dir.x, dir.y), "w": FIRE_WIDTH, "road": ri})


# --- Water tanks -----------------------------------------------------------------------------

## Round steel tanks on the knolls above the estates (the ones every hillside neighbourhood here
## has, painted green), each on its own pad with a dirt track to the nearest road when one can be
## graded.
func _place_tanks() -> void:
	var hr := macro.hill_roads
	var order: Array = []
	for mi in hr.mansions.size():
		order.append([_h01([seed, "tank_order", mi]), mi])
	order.sort()
	var n := 0
	for o: Array in order:
		if n >= TANK_MAX:
			break
		var m: Dictionary = hr.mansions[int(o[1])]
		var mp: Vector2 = m.pos
		var mh: float = m.height
		var near := false
		for s: Dictionary in sites:
			near = near or (s.kind == Site.TANK and (s.pos as Vector2).distance_to(mp) < TANK_SPACING)
		if near:
			continue
		var best := Vector2.INF
		var bh := mh + 25.0
		for a in 16:
			for dist: float in [90.0, 140.0, 190.0, 240.0]:
				var q := mp + Vector2.from_angle(TAU * a / 16.0 + _h01([seed, "tank_a", o[1]])) * dist
				var qh := _raw(q)
				if qh > bh and qh < mh + 140.0:
					bh = qh
					best = q
		if best == Vector2.INF:
			continue
		# Up to the knoll's top.
		for s: float in [12.0, 6.0]:
			var c := best
			for dj in range(-3, 4):
				for di in range(-3, 4):
					var q := c + Vector2(di, dj) * s
					if _raw(q) > _raw(best):
						best = q
		var r := 6.5 + _h01([seed, "tank_r", o[1]]) * 5.5
		if not _site_ok(best, r + 20.0) or not _free(best, r + 40.0):
			continue
		var h := _add_pad(best, _ridge_axis(best), Vector2(r + 7.0, r + 7.0), "Tank")
		if is_nan(h):
			continue
		var tank := {"id": "tank%d" % n, "kind": Site.TANK, "pos": best, "base": h, "r": r,
			"h": 7.0 + _h01([seed, "tank_h", o[1]]) * 5.0, "yaw": TAU * _h01([seed, "tank_yaw", o[1]])}
		sites.append(tank)
		n += 1
		_tank_track(best, h, r + 7.0)


## A straight dirt track from a tank's pad to the nearest road it can be graded down to.
func _tank_track(p: Vector2, h: float, rim: float) -> void:
	var hr := macro.hill_roads
	var best_q := Vector2.INF
	var best_h := 0.0
	var best_d := 260.0
	for road: Dictionary in hr.roads:
		if road.get("pad", false) or road.get("fire", false):
			continue
		var pts: PackedVector2Array = road.points
		var hs: PackedFloat32Array = road.heights
		for i in pts.size():
			var d := pts[i].distance_to(p)
			if d < best_d and d > rim + 30.0 and absf(hs[i] - h) < (d - rim) * FIRE_GRADE * 0.9:
				best_d = d
				best_q = pts[i]
				best_h = hs[i]
	if best_q == Vector2.INF:
		return
	var dir := (best_q - p).normalized()
	var pts := PackedVector2Array()
	var a := p + dir * (rim - 1.0)
	var b := best_q - dir * (FIRE_WIDTH + 4.0)
	var n := maxi(3, ceili(a.distance_to(b) / 12.0))
	for k in n + 1:
		pts.append(a.lerp(b, float(k) / n))
	var hs := PackedFloat32Array()
	for k in n + 1:
		hs.append(lerpf(h, best_h, float(k) / n))
	for i in pts.size():
		if absf(hs[i] - _uncarved(pts[i])) > FIRE_EARTHWORK:
			return
	hr.roads.append({"name": "Tank Rd", "points": pts, "heights": hs, "width": FIRE_WIDTH - 0.8, "mansions": false,
		"planned_points": pts, "draw": false, "fire": true})
	hr._index()
	fire_roads.append(hr.roads.size() - 1)
	gates.append({"pos": b - dir * 2.0, "base": hs[n], "yaw": atan2(-dir.x, -dir.y), "w": FIRE_WIDTH - 0.8, "road": hr.roads.size() - 1})


# =============================================================================================
# Lines half (lazy, with the plan): the substation and the two transmission lines.
# =============================================================================================

## The tower's geometry, local: x across the line (the arms), z along it, y up from the body's base.
static func spec(h: float) -> Dictionary:
	return {
		"h": h,
		"base_half": 0.092 * h,
		"waist_y": 0.56 * h,
		"waist_half": 1.35,
		"arm_y": [0.605 * h, 0.745 * h, 0.885 * h],
		"arm_tip": [1.35 + 0.115 * h, 1.35 + 0.142 * h, 1.35 + 0.115 * h],
		"arm_depth": 2.3,
		"peak_y": h,
		"peak_tip": 1.0 + 0.06 * h,
	}


## A tower's transform (local x across, z along the line), at its body's base.
static func tower_xform(t: Dictionary) -> Transform3D:
	var p: Vector2 = t.pos
	return Transform3D(Basis(Vector3.UP, float(t.yaw)), Vector3(p.x, float(t.base), p.y))


## Where the conductors and earth wires hang from a tower, world space: 6 phases (circuit side
## -1 bottom, middle, top, then side +1) and 2 earth wires. `toward` the far end of the span
## (an angle or terminal tower's tension strings reach out toward it).
static func attach(t: Dictionary, toward: Vector2) -> Array[Vector3]:
	var sp := spec(float(t.h))
	var xf := tower_xform(t)
	var out: Array[Vector3] = []
	var kind: int = t.kind
	var reach := Vector3.ZERO
	if kind != Kind.SUSPENSION:
		var d := (toward - (t.pos as Vector2)).normalized()
		var local := xf.basis.inverse() * Vector3(d.x, 0.0, d.y)
		reach = Vector3(0.0, 0.0, signf(local.z) * TENSION)
	for side: float in [-1.0, 1.0]:
		for k in 3:
			var y: float = sp.arm_y[k]
			var tip: float = sp.arm_tip[k]
			var local := Vector3(side * tip, y - STRING, 0.0)
			if kind != Kind.SUSPENSION:
				local = Vector3(side * tip, y - 0.35, 0.0) + reach
			out.append(xf * local)
	for side: float in [-1.0, 1.0]:
		out.append(xf * Vector3(side * float(sp.peak_tip), float(sp.peak_y) + 0.15, 0.0))
	return out


## The same for a substation gantry (its beam over two bays, the earth peaks on its columns).
static func gantry_attach(g: Dictionary, toward: Vector2) -> Array[Vector3]:
	var xf := Transform3D(Basis(Vector3.UP, float(g.yaw)), Vector3((g.pos as Vector2).x, float(g.base), (g.pos as Vector2).y))
	var d := (toward - (g.pos as Vector2)).normalized()
	var local_dir := xf.basis.inverse() * Vector3(d.x, 0.0, d.y)
	var reach := signf(local_dir.z) * TENSION
	var out: Array[Vector3] = []
	for side: float in [-1.0, 1.0]:
		for k in 3:
			var x := side * (2.0 + 4.2 * float(k))
			out.append(xf * Vector3(x, GANTRY_BEAM - 0.4, reach))
	for side: float in [-1.0, 1.0]:
		out.append(xf * Vector3(side * GANTRY_HALF, GANTRY_BEAM + 4.6, 0.0))
	return out


const GANTRY_BEAM := 16.5
const GANTRY_HALF := 14.6


## The conductors' attach points of a line's span `k` (k = 0 from the gantry to tower 0).
func span_ends(line: Dictionary, k: int) -> Array:
	var ids: Array = line.towers
	var a_end: Array[Vector3]
	var b_end: Array[Vector3]
	var b: Dictionary = towers[int(ids[k])]
	if k == 0:
		var g: Dictionary = substation.gantries[int(line.gantry)]
		a_end = gantry_attach(g, b.pos)
		b_end = attach(b, g.pos)
	else:
		var a: Dictionary = towers[int(ids[k - 1])]
		a_end = attach(a, b.pos)
		b_end = attach(b, a.pos)
	# Match the circuits by side across the span: a tower's "side -1" faces the other way when the
	# two ends are turned half round from each other.
	var a_x := (a_end[5] - a_end[2])
	var b_x := (b_end[5] - b_end[2])
	if a_x.dot(b_x) < 0.0:
		var sw: Array[Vector3] = [b_end[3], b_end[4], b_end[5], b_end[0], b_end[1], b_end[2], b_end[7], b_end[6]]
		b_end = sw
	return [a_end, b_end]


## Lowest point of the conductor between two attach heights over a horizontal run `l`.
static func sag(l: float) -> float:
	return SAG_K * l * l


## Points along a sagging wire from `a` to `b` (a parabola, close to the catenary at this sag).
static func wire(a: Vector3, b: Vector3, pieces: int, extra_sag := 0.0) -> PackedVector3Array:
	var out := PackedVector3Array()
	var l := Vector2(b.x - a.x, b.z - a.z).length()
	var s := sag(l) + extra_sag
	for i in pieces + 1:
		var t := float(i) / pieces
		var p := a.lerp(b, t)
		p.y -= 4.0 * s * t * (1.0 - t)
		out.append(p)
	return out


func _plan_lines(plan: CityPlan) -> void:
	_cache_on = true
	if not _place_substation(plan):
		_cache_on = false
		return
	var rect: Rect2 = substation.rect
	var c := rect.get_center()
	# Line A comes over the east range from the east; line B leaves north-east, climbs onto the
	# east range and runs north along it into the back range. Waypoints jittered by hash.
	var j := func(tag: String, k: int, amp: float) -> Vector2:
		return Vector2(_h01([seed, tag, k, "x"]) - 0.5, _h01([seed, tag, k, "z"]) - 0.5) * amp * 2.0
	var a_way := [c + Vector2(1200.0, 60.0) + j.call("wa", 0, 60.0), Vector2(7700.0, c.y + 250.0) + j.call("wa", 1, 150.0)]
	var b_way := [c + Vector2(330.0, -880.0) + j.call("wb", 0, 50.0), Vector2(5280.0, 1500.0) + j.call("wb", 1, 80.0),
		Vector2(5700.0, -800.0) + j.call("wb", 2, 120.0), Vector2(5550.0, -3000.0) + j.call("wb", 3, 120.0),
		Vector2(6700.0, -3700.0) + j.call("wb", 4, 120.0)]
	for spec_l: Array in [["Eastern 220 kV", a_way], ["Northern 220 kV", b_way]]:
		var way: Array = spec_l[1]
		var gi := _gantry_for(plan, way[0])
		_route(plan, String(spec_l[0]), gi, way)
	_cache_on = false
	_gcache.clear()
	_ucache.clear()
	_ground_cache.clear()
	_index_row()
	if OS.get_environment("RIDGE_DEBUG") != "":
		print("RIDGES lines: dp prep %d ms (ground %d, ok %d), dp %d ms, %d spans the ground forced low" % [_t_dp_prep / 1000, _t_g / 1000, _t_ok / 1000, _t_dp / 1000, _bad_spans])


## The substation: the industrial block nearest a hashed point in Vernon, west of the river.
func _place_substation(plan: CityPlan) -> bool:
	var target := Vector2(3820.0, 3260.0) + (Vector2(_h01([seed, "sub", "x"]), _h01([seed, "sub", "z"])) - Vector2(0.5, 0.5)) * 300.0
	var center := plan.block_index_at(target)
	var best := Vector2i(999999, 0)
	var best_d := INF
	for dj in range(-4, 5):
		for di in range(-4, 5):
			var k := center + Vector2i(di, dj)
			if not _block_ok(plan, k.x, k.y, true):
				continue
			var b := plan.block(k.x, k.y)
			var r: Rect2 = b.rect
			if r.size.x < 90.0 or r.size.y < 90.0:
				continue
			var d := r.get_center().distance_to(target)
			if d < best_d:
				best_d = d
				best = k
	if best.x == 999999:
		return false
	var b := plan.block(best.x, best.y)
	var rect: Rect2 = (b.rect as Rect2).grow(-plan.sidewalk_width - 1.0)
	# No longer than SUB_MAX on either side: the end of the block nearest the target.
	for ax in 2:
		if rect.size[ax] > SUB_MAX:
			var lo: float = clampf(target[ax] - SUB_MAX * 0.5, rect.position[ax], rect.end[ax] - SUB_MAX)
			rect.position[ax] = lo
			rect.size[ax] = SUB_MAX
	var ctr := rect.get_center()
	substation = {"rect": rect, "block": best, "base": CityChunk.SIDEWALK_TOP + plan.macro.relief_at(ctr), "gantries": []}
	return true


## A city block a tower (or the substation) may stand on: ordinary industrial lots, no landmark,
## park, school, river, light rail or freeway.
func _block_ok(plan: CityPlan, ix: int, iz: int, whole: bool) -> bool:
	var b := plan.block(ix, iz)
	var r: Rect2 = b.rect
	if b.has("site") or b.has("grounds") or int(b.kind) != CityPlan.BlockKind.BUILDINGS:
		return false
	if int(b.district) != CityPlan.District.INDUSTRIAL:
		return false
	if plan.zone_at(r.get_center()) != MacroMap.Zone.CITY or plan.river_block(ix, iz) or Landmarks.claims(r):
		return false
	if plan.macro.replica and plan.macro.replica.block_role(plan, ix, iz) != 0:
		return false
	if whole and plan.macro.freeway and plan.macro.freeway.blocks_rect(r, 10.0):
		return false
	var rail := LightRail.of(plan)
	if rail != null and rail.blocks_rect(r, 4.0):
		return false
	return true


## A gantry on the substation's edge facing `toward`, two bays across the line's approach.
func _gantry_for(plan: CityPlan, toward: Vector2) -> int:
	var rect: Rect2 = substation.rect
	var c := rect.get_center()
	var d := toward - c
	var pos: Vector2
	var dir: Vector2
	if absf(d.x) * rect.size.y > absf(d.y) * rect.size.x:
		dir = Vector2(signf(d.x), 0.0)
		pos = Vector2(c.x + dir.x * (rect.size.x * 0.5 - 9.0), clampf(c.y + d.y * 0.15, rect.position.y + 20.0, rect.end.y - 20.0))
	else:
		dir = Vector2(0.0, signf(d.y))
		pos = Vector2(clampf(c.x + d.x * 0.15, rect.position.x + 20.0, rect.end.x - 20.0), c.y + dir.y * (rect.size.y * 0.5 - 9.0))
	var g := {"pos": pos, "yaw": atan2(dir.x, dir.y), "dir": dir, "base": float(substation.base)}
	substation.gantries.append(g)
	return substation.gantries.size() - 1


## Ground at a tower's four feet, given its centre, yaw and height.
func _feet(p: Vector2, yaw: float, h: float) -> Array:
	var bh := 0.092 * h
	var out: Array = []
	var b := Basis(Vector3.UP, yaw)
	for k in 4:
		var lx := bh * (1.0 if k == 1 or k == 2 else -1.0)
		var lz := bh * (1.0 if k >= 2 else -1.0)
		var w := b * Vector3(lx, 0.0, lz)
		out.append(_ground(p + Vector2(w.x, w.z)))
	return out


## The ground a tower stands on: the carved hills, or the city's pavement level.
func _ground(p: Vector2) -> float:
	if _cache_on:
		var k := Vector2i(roundi(p.x / 4.0), roundi(p.y / 4.0))
		var v: Variant = _ground_cache.get(k)
		if v == null:
			v = _ground_exact(Vector2(k) * 4.0)
			_ground_cache[k] = v
		return v
	return _ground_exact(p)


var _ground_cache: Dictionary = {}


func _ground_exact(p: Vector2) -> float:
	if macro.zone_at(p) == MacroMap.Zone.HILLS:
		return macro.height_at(p)
	return CityChunk.SIDEWALK_TOP + macro.relief_at(p)


## Whether a tower may stand at `p`: in the hills, off every road, pad and estate's banks, off the
## landmarks and the freeway; in the city, well inside an ordinary industrial block.
func _tower_ok(plan: CityPlan, p: Vector2) -> bool:
	var zone := macro.zone_at(p)
	if zone != MacroMap.Zone.HILLS and zone != MacroMap.Zone.CITY:
		return false
	if macro.freeway and macro.freeway.blocks(p, 22.0):
		return false
	if zone == MacroMap.Zone.HILLS:
		for lm in Landmarks.all():
			if p.distance_to(lm.anchor) < float(lm.radius) + 40.0:
				return false
		for m: Dictionary in macro.hill_roads.mansions:
			if absf((m.pos as Vector2).x - p.x) < 50.0 and (m.pos as Vector2).distance_to(p) < 50.0:
				return false
		return _free(p, 14.0, 4)
	if macro.river and macro.river.in_corridor(p, 18.0):
		return false
	if zone != MacroMap.Zone.CITY:
		return false
	var k := plan.block_index_at(p)
	if not _block_ok(plan, k.x, k.y, false):
		return false
	var inner := (plan.block(k.x, k.y).rect as Rect2).grow(-plan.sidewalk_width - 7.0)
	if not inner.has_point(p):
		return false
	if not substation.is_empty() and (substation.rect as Rect2).grow(25.0).has_point(p):
		return false
	return true


## The lowest conductor's clearance over the ground between two attach heights (world), metres;
## negative where it would dip into the hillside.
func _clearance(a: Vector2, ya: float, b: Vector2, yb: float) -> float:
	var l := a.distance_to(b)
	var s := sag(l)
	var worst := INF
	var n := maxi(4, ceili(l / 15.0))
	for i in range(1, n):
		var t := float(i) / n
		var q := a.lerp(b, t)
		var y := lerpf(ya, yb, t) - 4.0 * s * t * (1.0 - t)
		worst = minf(worst, y - _ground(q))
	return worst


## The height of the lowest conductor on a tower at `p` of height `h` (world y), with its base.
func _low_attach(p: Vector2, yaw: float, h: float) -> Vector2:
	var feet := _feet(p, yaw, h)
	var base := maxf(maxf(feet[0], feet[1]), maxf(feet[2], feet[3])) + 0.35
	return Vector2(base + 0.605 * h - STRING, base)


func _make_tower(line: int, p: Vector2, dir: Vector2, h: float, kind: int, turn: float) -> int:
	var yaw := atan2(dir.x, dir.y)
	var was := _cache_on
	_cache_on = false
	var feet := _feet(p, yaw, h)
	_cache_on = was
	var base := maxf(maxf(feet[0], feet[1]), maxf(feet[2], feet[3])) + 0.35
	towers.append({"id": towers.size(), "line": line, "pos": p, "yaw": yaw, "dir": dir, "h": h, "base": base, "legs": feet,
		"kind": kind, "turn": turn, "city": macro.zone_at(p) == MacroMap.Zone.CITY})
	return towers.size() - 1


## A valid spot near `p` (the point itself, or the nearest of rings round it), or INF.
func _nudge(plan: CityPlan, p: Vector2) -> Vector2:
	if _tower_ok(plan, p) and _leg_ok(p):
		return p
	for r: float in [15.0, 30.0, 45.0, 65.0, 90.0]:
		for a in 12:
			var q := p + Vector2.from_angle(TAU * a / 12.0 + r) * r
			if _tower_ok(plan, q) and _leg_ok(q):
				return q
	return Vector2.INF


func _leg_ok(p: Vector2, yaw: float = 0.0) -> bool:
	var feet := _feet(p, yaw, 58.0)
	var hi := maxf(maxf(feet[0], feet[1]), maxf(feet[2], feet[3]))
	var lo := minf(minf(feet[0], feet[1]), minf(feet[2], feet[3]))
	if hi - lo < MAX_LEG_EXT:
		return true
	# A tower straddles a peak on long leg extensions (the spot is the highest ground round it): the
	# only place a span can get over a spike, and how the real lines over these hills stand.
	if hi - lo < PEAK_LEG_EXT:
		var g := _ground(p)
		for a in 8:
			if _ground(p + Vector2.from_angle(TAU * a / 8.0) * 25.0) > g + 1.0:
				return false
		return true
	return false


## Lays a line out from the substation's gantry `gi` through the waypoints: an angle tower at each
## (nudged to a spot it may stand on), suspension towers between, each span as long as the ground
## lets the lowest conductor clear it by CLEAR, the tower as short as will do.
func _route(plan: CityPlan, name: String, gi: int, way: Array) -> void:
	var li := lines.size()
	var line := {"name": name, "towers": [], "gantry": gi}
	lines.append(line)
	var g: Dictionary = substation.gantries[gi]
	var pts: Array[Vector2] = [g.pos as Vector2]
	for w: Vector2 in way:
		var q := _nudge(plan, w)
		if q != Vector2.INF:
			pts.append(q)
	if pts.size() < 2:
		return
	# The first span leaves the gantry square to it: a tower out in front of the yard.
	var gdir: Vector2 = g.dir
	var first := _nudge(plan, (g.pos as Vector2) + gdir * 170.0)
	if first != Vector2.INF:
		pts.insert(1, first)
	var prev_low := float(g.base) + GANTRY_BEAM - 0.4
	for wi in range(1, pts.size()):
		var last := wi == pts.size() - 1
		var a := pts[wi - 1]
		var b := pts[wi]
		var d := (b - a).normalized()
		var nd := d if last else (pts[wi + 1] - b).normalized()
		var bis := d if last else (d + nd).normalized()
		var turn := 0.0 if last else d.angle_to(nd)
		var b_kind := Kind.TERMINAL if last else (Kind.ANGLE if absf(turn) > 0.12 else Kind.SUSPENSION)
		var leg := _leg_towers(plan, a, b, prev_low, bis)
		for k in leg.size():
			var st: Array = leg[k]
			var at_end := k == leg.size() - 1
			var ti := _make_tower(li, st[0], bis if at_end else d, st[1], b_kind if at_end else Kind.SUSPENSION, turn if at_end else 0.0)
			line.towers.append(ti)
			prev_low = towers[ti].base + 0.605 * float(st[1]) - STRING
	# The right of way through the city: from the gantry to the first tower in the hills.
	var chain: Array[Vector2] = [g.pos as Vector2]
	for ti: int in line.towers:
		chain.append(towers[ti].pos)
	for k in range(1, chain.size()):
		var pa := chain[k - 1]
		var pb := chain[k]
		if macro.zone_at(pa) == MacroMap.Zone.CITY or macro.zone_at(pb) == MacroMap.Zone.CITY:
			_row.append([pa, pb])


## The towers of one straight leg from `a` (a tower whose lowest conductor hangs at `a_low`) to
## the waypoint `b` (always a tower, turned to `b_dir`): the fewest towers, each as short as will
## do, whose every span keeps all six conductors CLEAR over the ground under them - a dynamic
## programme over spots every DP_STEP metres. A span that cannot clear is allowed only at a heavy
## cost, so a leg is never left without towers. [[pos, height], ...], b last.
func _leg_towers(plan: CityPlan, a: Vector2, b: Vector2, a_low: float, b_dir: Vector2) -> Array:
	_t_mark = Time.get_ticks_usec()
	var leg := a.distance_to(b)
	var d := (b - a) / maxf(leg, 0.01)
	var nrm := Vector2(-d.y, d.x)
	var n := maxi(1, ceili(leg / DP_STEP))
	var yaw := atan2(d.x, d.y)
	var pos: Array[Vector2] = []
	var nudged: Array[bool] = []
	var ok: Array[bool] = []
	var base := PackedFloat32Array()
	var gmax := PackedFloat32Array()
	var city: Array[bool] = []
	for i in n + 1:
		var q := a.lerp(b, float(i) / n)
		# A spot a little to one side when the line itself is not one (a street, a lot line).
		# A spot a little to one side when the line itself is not one (a street, a lot line, the
		# flank of a spike). A span to or from a moved spot is measured along its true line.
		var moved := false
		if i > 0 and i < n and not (_tower_ok(plan, q) and _leg_ok(q, yaw)):
			for off: float in [12.0, -12.0, 24.0, -24.0, 36.0, -36.0, 50.0, -50.0]:
				if _tower_ok(plan, q + nrm * off) and _leg_ok(q + nrm * off, yaw):
					q += nrm * off
					moved = true
					break
		nudged.append(moved)
		pos.append(q)
		city.append(macro.zone_at(q) == MacroMap.Zone.CITY)
		var t_a := Time.get_ticks_usec()
		# The ground under all six conductors: the centre line and both outer phases, at this spot and
		# half way to its neighbours (a narrow crest between two spots is what a span hits).
		var gm := -INF
		for along: float in [-0.5, 0.0, 0.5]:
			var qa := q + d * along * (leg / n)
			gm = maxf(gm, maxf(_ground(qa), maxf(_ground(qa + nrm * 9.0), _ground(qa - nrm * 9.0))))
		gmax.append(gm)
		var t_b := Time.get_ticks_usec()
		var valid := i == n or (i > 0 and _tower_ok(plan, q) and _leg_ok(q, yaw))
		_t_g += t_b - t_a
		_t_ok += Time.get_ticks_usec() - t_b
		ok.append(valid)
		var feet := _feet(q, atan2(b_dir.x, b_dir.y) if i == n else yaw, 52.0) if valid else [0.0, 0.0, 0.0, 0.0]
		base.append(maxf(maxf(feet[0], feet[1]), maxf(feet[2], feet[3])) + 0.35)
	_t_dp_prep += Time.get_ticks_usec() - _t_mark
	_t_mark = Time.get_ticks_usec()
	# The ground of the corridor either side of the leg, for spans between moved spots.
	var ru := maxi(2, ceili(leg / RASTER_U) + 1)
	var rv := int(RASTER_V_HALF * 2.0 / RASTER_V) + 1
	var raster := PackedFloat32Array()
	raster.resize(ru * rv)
	# Filled as it is read (most cells never are; a cell is a carved-ground sample, ~0.1 ms).
	raster.fill(NAN)
	var nh := HEIGHTS.size()
	var cost := PackedFloat32Array()
	var from := PackedInt32Array()
	cost.resize((n + 1) * nh)
	from.resize((n + 1) * nh)
	cost.fill(INF)
	from.fill(-1)
	for j in range(1, n + 1):
		if not ok[j]:
			continue
		var span_max := CITY_SPAN_MAX if city[j] else SPAN_MAX
		var i0 := maxi(0, j - int(span_max / leg * n))
		for i in range(i0, j):
			if i > 0 and not ok[i]:
				continue
			var span := pos[i].distance_to(pos[j])
			if span < SPAN_SHORT and i > 0 and j < n:
				continue
			# The ground under this span, once for every pair of heights: along its true line when
			# either end was moved, else the leg's own samples.
			var ts := PackedFloat32Array()
			var gs := PackedFloat32Array()
			if nudged[i] or nudged[j]:
				# Off the corridor raster: the true line, its outer phases 9 m either side.
				var ui := (pos[i] - a).dot(d)
				var vi := (pos[i] - a).dot(nrm)
				var uj := (pos[j] - a).dot(d)
				var vj := (pos[j] - a).dot(nrm)
				var m := maxi(4, ceili(span / RASTER_U))
				for k in range(1, m):
					var t := float(k) / m
					var cu := clampi(roundi(lerpf(ui, uj, t) / RASTER_U), 0, ru - 1)
					var cv := lerpf(vi, vj, t)
					var g0 := -INF
					for dv: float in [-9.0, 0.0, 9.0]:
						var iv := clampi(roundi((cv + dv + RASTER_V_HALF) / RASTER_V), 0, rv - 1)
						var cell := cu * rv + iv
						if is_nan(raster[cell]):
							raster[cell] = _ground(a + d * (cu * RASTER_U) + nrm * (iv * RASTER_V - RASTER_V_HALF))
						g0 = maxf(g0, raster[cell])
					ts.append(t)
					gs.append(g0)
			else:
				for k in range(i + 1, j):
					ts.append(float(k - i) / float(j - i))
					gs.append(gmax[k])
			var sg := SAG_K * span * span
			var extra := 0.35 if span < SPAN_MIN else 0.0
			# The clearance only grows with either tower's height: when the shortest pair clears, all
			# do, and when the tallest does not, none does - most spans are one or the other.
			var base_i := a_low if i == 0 else base[i] + 0.605 * HEIGHTS[0] - STRING
			var lo_j := base[j] + 0.605 * HEIGHTS[0] - STRING
			var tall := 0.605 * (HEIGHTS[nh - 1] - HEIGHTS[0])
			var w_short := _worst(ts, gs, base_i, lo_j, sg)
			var w_tall := _worst(ts, gs, base_i + (0.0 if i == 0 else tall), lo_j + tall, sg)
			for hi in (1 if i == 0 else nh):
				var c0: float = 0.0 if i == 0 else cost[i * nh + hi]
				if c0 >= INF:
					continue
				var low_i := a_low if i == 0 else base[i] + 0.605 * HEIGHTS[hi] - STRING
				for hj in nh:
					var low_j := base[j] + 0.605 * HEIGHTS[hj] - STRING
					var worst := w_short
					if w_short < CLEAR:
						worst = w_tall if w_tall < CLEAR else _worst(ts, gs, low_i, low_j, sg)
					var c := c0 + 1.0 + (HEIGHTS[hj] - HEIGHTS[0]) * 0.012 + extra
					if worst < CLEAR:
						c += 25.0 + (CLEAR - worst) * 0.5
					if c < cost[j * nh + hj]:
						cost[j * nh + hj] = c
						from[j * nh + hj] = i * nh + hi
	_t_dp += Time.get_ticks_usec() - _t_mark
	var end := -1
	var end_c := INF
	for hj in nh:
		if cost[n * nh + hj] < end_c:
			end_c = cost[n * nh + hj]
			end = n * nh + hj
	var out: Array = []
	while end >= 0 and end / nh > 0:
		out.push_front([pos[end / nh], HEIGHTS[end % nh]])
		end = from[end]
	_fix_spans(plan, out, a, a_low, yaw, b_dir)
	return out


## The lowest conductor's clearance over the ground samples `gs` at fractions `ts` of a span.
static func _worst(ts: PackedFloat32Array, gs: PackedFloat32Array, low_a: float, low_b: float, sg: float) -> float:
	var worst := INF
	for k in ts.size():
		var t := ts[k]
		worst = minf(worst, lerpf(low_a, low_b, t) - 4.0 * sg * t * (1.0 - t) - gs[k])
	return worst


## Every span of a leg checked along its true line (the towers may stand off the leg): a span that
## does not clear raises its far tower (and is counted in `_bad_spans`).
func _fix_spans(plan: CityPlan, out: Array, a: Vector2, a_low: float, yaw: float, b_dir: Vector2) -> void:
	var prev := a
	var prev_low := a_low
	var i := 0
	while i < out.size():
		var p: Vector2 = out[i][0]
		var last := i == out.size() - 1
		var tyaw := atan2(b_dir.x, b_dir.y) if last else yaw
		var h: float = out[i][1]
		if _span_clear(prev, prev_low, p, _low_attach(p, tyaw, h).x) < CLEAR:
			for hh in HEIGHTS:
				if hh > h and _span_clear(prev, prev_low, p, _low_attach(p, tyaw, hh).x) >= CLEAR:
					out[i][1] = hh
					h = hh
					break
			if _span_clear(prev, prev_low, p, _low_attach(p, tyaw, h).x) < CLEAR:
				_bad_spans += 1
		prev = out[i][0]
		prev_low = _low_attach(prev, tyaw, float(out[i][1])).x
		i += 1


## The lowest conductor's clearance over the ground under the whole span (centre line and both
## outer phases), sampled every 8 m along its true line.
func _span_clear(a: Vector2, ya: float, b: Vector2, yb: float) -> float:
	var l := a.distance_to(b)
	var s := sag(l)
	var d := (b - a) / maxf(l, 0.01)
	var nrm := Vector2(-d.y, d.x) * 9.0
	var worst := INF
	var n := maxi(4, ceili(l / 8.0))
	for i in range(1, n):
		var t := float(i) / n
		var q := a.lerp(b, t)
		var g := maxf(_ground(q), maxf(_ground(q + nrm), _ground(q - nrm)))
		worst = minf(worst, lerpf(ya, yb, t) - 4.0 * s * t * (1.0 - t) - g)
	return worst


func _index_row() -> void:
	_row_cells.clear()
	for i in _row.size():
		var a: Vector2 = _row[i][0]
		var b: Vector2 = _row[i][1]
		var lo := Vector2(minf(a.x, b.x), minf(a.y, b.y)) - Vector2.ONE * ROW_HALF
		var hi := Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + Vector2.ONE * ROW_HALF
		for cx in range(floori(lo.x / ROW_CELL), floori(hi.x / ROW_CELL) + 1):
			for cz in range(floori(lo.y / ROW_CELL), floori(hi.y / ROW_CELL) + 1):
				var key := Vector2i(cx, cz)
				if not _row_cells.has(key):
					_row_cells[key] = []
				_row_cells[key].append(i)


## Distance from a rect to the segment a-b (0 when they touch).
static func _rect_seg_distance(r: Rect2, a: Vector2, b: Vector2) -> float:
	if r.has_point(a) or r.has_point(b):
		return 0.0
	var corners := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
	var best := INF
	for i in 4:
		var c: Vector2 = corners[i]
		var ab := b - a
		var t := clampf((c - a).dot(ab) / maxf(ab.length_squared(), 0.001), 0.0, 1.0)
		best = minf(best, c.distance_to(a + ab * t))
		var e: Vector2 = corners[(i + 1) % 4]
		if Geometry2D.segment_intersects_segment(a, b, c, e) != null:
			return 0.0
		var ce := e - c
		for p: Vector2 in [a, b]:
			var u := clampf((p - c).dot(ce) / maxf(ce.length_squared(), 0.001), 0.0, 1.0)
			best = minf(best, p.distance_to(c + ce * u))
	return best


## CityPlan.lots()'s question (after every roll): does the substation or the line's right of way
## take this lot? Remembers the lot's grid cell for the block (RidgeBuild lays the ground there).
func claims_lot(plan: CityPlan, ix: int, iz: int, lot_rect: Rect2, cell: Rect2) -> bool:
	var key := Vector2i(ix, iz)
	if not substation.is_empty() and substation.block == key and (substation.rect as Rect2).grow(3.0).intersects(lot_rect):
		return true
	var c := lot_rect.get_center()
	var refs: Variant = _row_cells.get(Vector2i(floori(c.x / ROW_CELL), floori(c.y / ROW_CELL)))
	if refs == null:
		return false
	var b := plan.block(ix, iz)
	if int(b.district) != CityPlan.District.INDUSTRIAL:
		return false
	for i: int in refs:
		if _rect_seg_distance(lot_rect, _row[i][0], _row[i][1]) < ROW_HALF:
			if not claimed_cells.has(key):
				claimed_cells[key] = []
			if not (claimed_cells[key] as Array).has(cell):
				(claimed_cells[key] as Array).append(cell)
			return true
	return false


## Every right-of-way segment touching `rect` (grown by the right of way).
func row_in(rect: Rect2) -> Array:
	var out: Array = []
	for seg: Array in _row:
		if _rect_seg_distance(rect, seg[0], seg[1]) < ROW_HALF:
			out.append(seg)
	return out


# --- Queries for the chunks ------------------------------------------------------------------

func towers_in(rect: Rect2) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for t in towers:
		if rect.has_point(t.pos):
			out.append(t)
	return out


func masts_in(rect: Rect2) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for m in masts:
		if rect.has_point(m.pos):
			out.append(m)
	return out


func sites_in(rect: Rect2) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for s in sites:
		if rect.has_point(s.pos):
			out.append(s)
	return out


func gates_in(rect: Rect2) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for g in gates:
		if rect.has_point(g.pos):
			out.append(g)
	return out


## Every id the far tier can hide under a FULL chunk: towers 0.., then masts, then sites.
func far_id(kind: String, index: int) -> int:
	match kind:
		"tower":
			return index
		"mast":
			return towers.size() + index
		_:
			return towers.size() + masts.size() + index
