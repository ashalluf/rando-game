class_name Reservoir
extends RefCounted
## The reservoir in the front range west of the ridge sign: a long irregular lake filling a canyon,
## held back by a curved concrete arch-gravity dam that faces the basin (the FORM of the reservoir
## behind the famous sign in LA's hills; every name in the game is invented). CLAUDE.md's
## "Reservoir" note is the reference, docs/HANDOFF.md has the story.
##
## This is the DATA (MacroMap.reservoir, built in MacroMap.setup() after the river and before the
## hill roads); `LandmarkReservoir` builds what stands on it.
##
## How the land is made. The canyon is the range's own (a natural gorge at x -520 on the default
## seed); the lake is a DEPRESSION subtracted from the natural mountains along a few authored arms
## (`ARMS`: axis polylines with a waterline half width and a bed depth per point), so the banks keep
## the range's eroded spurs and gullies and the shore is simply where that ground crosses the water
## level - it follows the contour, coves where gullies come down, points where spurs do. A core
## floor (`C`) guarantees open water along every arm. `carve()` is applied by MacroMap at the end of
## raw_height_at(), so the hill tiles, their collision, the planting, the far bake and the zone test
## all see one surface. The level is fitted per seed: `DESIGN_LEVEL`, lowered until the flooded
## region is closed (never reaches the edge of `BOX`), so no seed spills water over a saddle.
##
## The dam is an arc (centre `dam_centre`, radius `DAM_RADIUS`, convex upstream: the arch thrusts
## into the abutments), its crest `FREEBOARD` over the water; it spans the gorge between the angles
## where the ground first rises over the crest (`dam_a0` .. `dam_a1`). Under its footprint the
## ground is held at its foundation, and downstream of it a short channel leads the gorge away.
## A spillway (`spill`) leaves the lake round the east abutment and drops down the hillside as a
## stepped chute; a trail runs round the lake on a bench cut at `TRAIL_RISE` over the water
## (`trail`: polylines worked out from the ground's own contour).
##
## Everything is a pure function of the seed and the map. Nothing here rolls a random number.

## The Landmarks.all() anchor: the lake's middle. The landmark chunk round it builds the detail.
const ANCHOR := Vector2(-540.0, -1350.0)
## The box everything here touches (world XZ). carve() is the identity outside it.
const BOX := Rect2(-850.0, -1700.0, 640.0, 580.0)
## The carve fades back to the natural ground over the last EDGE_FADE metres inside BOX, so no
## depression reaching its edge leaves a cliff along it.
const EDGE_FADE := 70.0
## The level the lake is designed for (m); lowered per seed until it holds (see _fit_level()).
const DESIGN_LEVEL := 265.0
const MIN_LEVEL := 150.0
## Crest of the dam over the water.
const FREEBOARD := 4.0
## Dam: where the upstream face crosses the gorge's axis, and the radius of its arc. The arc's
## centre is DAM_RADIUS south (downstream) of DAM_AT.
const DAM_AT := Vector2(-494.0, -1250.0)
const DAM_RADIUS := 240.0
## The crest's width (road and both parapets) and how far the downstream face steps out per metre
## of height (an arch-gravity section: a near-vertical upstream face, a battered downstream one).
const CREST_WIDTH := 9.0
const BATTER := 0.55
const MIN_DAM_HEIGHT := 46.0
const MAX_DAM_HEIGHT := 78.0
## How far the dam's ends run into the rock past where the ground meets the crest (m along the arc).
const ABUTMENT_KEY := 7.0
## The platform at the dam's toe (m deep) and the fill falling from it (m down per m).
const SHELF := 24.0
const FILL_SLOPE := 0.7
## The lake's arms: axis points (world XZ), waterline half widths (m) and bed depths under the
## level (m), all per point. The first arm starts at the dam.
const ARMS := [
	{"pts": [Vector2(-496.0, -1258.0), Vector2(-516.0, -1280.0), Vector2(-540.0, -1310.0), Vector2(-525.0, -1370.0),
		Vector2(-492.0, -1430.0), Vector2(-458.0, -1488.0), Vector2(-440.0, -1540.0)],
		"w": [26.0, 46.0, 64.0, 72.0, 66.0, 46.0, 16.0],
		"bed": [46.0, 40.0, 34.0, 28.0, 20.0, 12.0, 3.0]},
	{"pts": [Vector2(-548.0, -1330.0), Vector2(-600.0, -1366.0), Vector2(-648.0, -1410.0), Vector2(-676.0, -1462.0)],
		"w": [52.0, 46.0, 34.0, 12.0],
		"bed": [28.0, 20.0, 12.0, 3.0]},
	{"pts": [Vector2(-505.0, -1282.0), Vector2(-450.0, -1290.0), Vector2(-400.0, -1318.0)],
		"w": [40.0, 32.0, 12.0],
		"bed": [30.0, 16.0, 3.0]},
]
## How far past an arm's waterline the depression fades back to the natural ground (m). The banks
## are the natural slope plus that fade, so steep but still the range's own.
const FALL := 125.0
const FALL_AT_DAM := 22.0
## The dam's design span (radians each side of its middle), which the depression's fall near the
## dam is measured from (the fitted span depends on the depression), and the face arm's.
const DESIGN_SPAN := 0.6
const FACE_SPAN := 0.38
## Steepest a core bank gets over the waterline (rise per metre) where the depression alone would
## leave the shore further out.
const CORE_BANK := 1.25
## How far past the waterline the core holds (m) and over how far it lets go.
const CORE_HOLD := 12.0
const CORE_RELEASE := 70.0
## The trail: a 4.8 m bench cut round the lake TRAIL_RISE over the water.
const TRAIL_RISE := 6.0
const TRAIL_HALF := 2.4
const TRAIL_BLEND := 4.0
## Grid the level is fitted on and the water mesh / contours are worked out on (m).
const CELL := 5.0

var macro: MacroMap
## The water level, the dam's crest, its foundation (toe) and the arc's centre.
var level: float = DESIGN_LEVEL
var crest: float = DESIGN_LEVEL + FREEBOARD
var toe: float = DESIGN_LEVEL - 50.0
var dam_centre: Vector2 = DAM_AT + Vector2(0.0, DAM_RADIUS)
## Angles of the dam's ends round dam_centre (radians, atan2 of (dx, dz); 0 is due north... see
## arc_point()). a0 is the west end, a1 the east.
var dam_a0: float = -0.5
var dam_a1: float = 0.5
## The dam's base thickness (crest width plus the batter over its height).
var dam_base: float = 40.0
## The arms in use: ARMS as packed arrays with their bounds, plus one along the dam's upstream face
## (added once the dam is fitted, so the water reaches the whole face).
var _arms: Array = []
## Per arm: smoothed natural ground along the axis (m), the same length as its points.
var _axis_ground: Array = []
## The grid nodes' arm terms (see _terms()), TERMS * arms floats a node.
var _grid_terms: Array[PackedFloat32Array] = []
## The spillway's polyline (world XZ) and floor heights per point; the weir is at index 1.
var spill: PackedVector2Array = PackedVector2Array()
var spill_floor: PackedFloat32Array = PackedFloat32Array()
const SPILL_HALF := 5.0
const SPILL_REACH := 90.0
## The trail: polylines (world XZ), from one abutment round the lake to the other.
var trail: Array[PackedVector2Array] = []
var _trail_cells: Dictionary = {}
const TRAIL_CELL := 16.0
var _trail_on: bool = false
## The natural ground on the grid (before any carving) and its size.
var _nat := PackedFloat32Array()
var _nx: int = 0
var _nz: int = 0
## The flooded cells (1) on the grid, after the final carve.
var wet_grid := PackedByteArray()
## Where the last flood that failed reached the edge of the box (probes).
var spilled_at := Vector2.INF
var _spilled: bool = false
## The final carved ground on the grid (what the water mesh and the ring are laid from).
var ground_grid := PackedFloat32Array()


func build(m: MacroMap) -> void:
	macro = m
	_nx = int(ceil(BOX.size.x / CELL)) + 1
	_nz = int(ceil(BOX.size.y / CELL)) + 1
	_nat.resize(_nx * _nz)
	# The natural mountains (MacroMap.reservoir is still null while this runs), sampled every
	# other node and filled in bilinearly: the finest order of erosion in the height is 110 m
	# apart, and a height in the eroded range costs 20-40 us.
	for j in range(0, _nz, 2):
		for i in range(0, _nx, 2):
			_nat[j * _nx + i] = _full_natural(grid_point(i, j))
	for j in _nz:
		for i in _nx:
			if i % 2 == 0 and j % 2 == 0:
				continue
			var i0 := i - i % 2
			var j0 := j - j % 2
			var i1 := mini(i0 + 2, (_nx - 1) - (_nx - 1) % 2)
			var j1 := mini(j0 + 2, (_nz - 1) - (_nz - 1) % 2)
			if i1 == i0 or j1 == j0:
				_nat[j * _nx + i] = _full_natural(grid_point(i, j))
				continue
			var fi := float(i - i0) / float(i1 - i0)
			var fj := float(j - j0) / float(j1 - j0)
			_nat[j * _nx + i] = lerpf(lerpf(_nat[j0 * _nx + i0], _nat[j0 * _nx + i1], fi), lerpf(_nat[j1 * _nx + i0], _nat[j1 * _nx + i1], fi), fj)
	_arms = []
	_axis_ground = []
	for arm: Dictionary in ARMS:
		_add_arm(PackedVector2Array(arm.pts), PackedFloat32Array(arm.w), PackedFloat32Array(arm.bed))
	# The upstream face: an arm along the design arc, inside its ends, so no dry ground is left
	# standing against the dam behind a shallow end of the lake.
	var face := PackedVector2Array()
	var fw := PackedFloat32Array()
	var fb := PackedFloat32Array()
	for k in 7:
		face.append(arc_point(lerpf(-FACE_SPAN, FACE_SPAN, float(k) / 6.0), DAM_RADIUS + 16.0))
		var mid := 1.0 - absf(float(k) / 3.0 - 1.0)
		fw.append(lerpf(4.0, 18.0, mid))
		fb.append(lerpf(1.0, 14.0, mid))
	_add_arm(face, fw, fb)
	_cache_terms()
	_fit_level()
	_fit_dam()
	_outer = BOX.merge(Rect2(dam_centre - Vector2.ONE * (DAM_RADIUS + 20.0), Vector2.ONE * (DAM_RADIUS + 20.0) * 2.0))
	_plan_spillway()
	_refresh_grid()
	# The full carve (dam, spillway) must still hold; lower it a metre at a time if it does not.
	while _spilled and level > MIN_LEVEL:
		level -= 1.0
		crest = level + FREEBOARD
		_fit_dam()
		_plan_spillway()
		_refresh_grid()
	# The natural ground was read every other node and filled in: near the waterline read it for
	# real, so the flood (and the water mesh) agree with the ground the tiles draw.
	var fixed := 0
	for c in _nx * _nz:
		var i := c % _nx
		var j := c / _nx
		if (i % 2 == 0 and j % 2 == 0) or absf(ground_grid[c] - level) > 6.0:
			continue
		_nat[c] = _full_natural(grid_point(i, j))
		ground_grid[c] = _carve(grid_point(i, j), _nat[c], level, true, _grid_terms[c])
		fixed += 1
	wet_grid = _flood(ground_grid, level, true)
	if wet_grid.is_empty():
		wet_grid.resize(_nx * _nz)
	# The dam's ends run on until the ground the tiles draw stands over the crest at the face.
	for side in 2:
		var sgn := -1.0 if side == 0 else 1.0
		for it in 20:
			var a := (dam_a0 if side == 0 else dam_a1) + sgn * 6.0 / DAM_RADIUS
			var p := arc_point(a, DAM_RADIUS + 3.0)
			if carve(p, macro.raw_height_at(p)) + macro.plateau_at(p) > crest - 2.0:
				break
			if side == 0:
				dam_a0 -= 2.0 / DAM_RADIUS
			else:
				dam_a1 += 2.0 / DAM_RADIUS
	_plan_trail()
	# Only the ground along the trail moved.
	var done := {}
	for line in trail:
		for p in line:
			var ci := int(round((p.x - BOX.position.x) / CELL))
			var cj := int(round((p.y - BOX.position.y) / CELL))
			for dj in range(-2, 3):
				for di in range(-2, 3):
					var i := ci + di
					var j := cj + dj
					if i < 0 or j < 0 or i >= _nx or j >= _nz or done.has(j * _nx + i):
						continue
					done[j * _nx + i] = true
					ground_grid[j * _nx + i] = _carve(grid_point(i, j), _nat[j * _nx + i], level, true, _grid_terms[j * _nx + i])
	wet_grid = _flood(ground_grid, level, true)
	if wet_grid.is_empty():
		wet_grid.resize(_nx * _nz)


func _add_arm(pts: PackedVector2Array, w: PackedFloat32Array, bed: PackedFloat32Array) -> void:
	var bounds := Rect2(pts[0], Vector2.ZERO)
	var wmax := 0.0
	for k in pts.size():
		bounds = bounds.expand(pts[k])
		wmax = maxf(wmax, w[k])
	_arms.append({"pts": pts, "w": w, "bed": bed, "bounds": bounds.grow(wmax + FALL + 1.0)})
	var hs := PackedFloat32Array()
	for p in pts:
		# Across the axis too: the valley's floor, not one bump on it.
		var sum := 0.0
		for o: Vector2 in [Vector2.ZERO, Vector2(18.0, 0.0), Vector2(-18.0, 0.0), Vector2(0.0, 18.0), Vector2(0.0, -18.0)]:
			sum += _natural(p + o)
		hs.append(sum / 5.0)
	# Smoothed along the arm: the depression must not leave a sill.
	var sm := hs.duplicate()
	for k in hs.size():
		sm[k] = (hs[maxi(k - 1, 0)] + 2.0 * hs[k] + hs[mini(k + 1, hs.size() - 1)]) * 0.25
	_axis_ground.append(sm)


func _cache_terms() -> void:
	_grid_terms.resize(_nx * _nz)
	for c in _nx * _nz:
		_grid_terms[c] = _terms(grid_point(c % _nx, c / _nx))


## The natural mountains (MacroMap.reservoir must not be this one while it is called).
func _natural(p: Vector2) -> float:
	if BOX.has_point(p):
		var i := (p.x - BOX.position.x) / CELL
		var j := (p.y - BOX.position.y) / CELL
		var i0 := clampi(int(i), 0, _nx - 2)
		var j0 := clampi(int(j), 0, _nz - 2)
		var fi := clampf(i - i0, 0.0, 1.0)
		var fj := clampf(j - j0, 0.0, 1.0)
		var c := j0 * _nx + i0
		return lerpf(lerpf(_nat[c], _nat[c + 1], fi), lerpf(_nat[c + _nx], _nat[c + _nx + 1], fi), fj)
	return _full_natural(p)


## The natural ground as height_at() stands it: the mountains plus the inland valley's plateau
## base (which reaches the lake's north end). Everything here works in that space; carve() takes the
## plateau back off, since MacroMap adds it after raw_height_at().
func _full_natural(p: Vector2) -> float:
	return macro.raw_height_at(p) + macro.plateau_at(p)


## World XZ of grid node (i, j).
func grid_point(i: int, j: int) -> Vector2:
	return BOX.position + Vector2(float(i) * CELL, float(j) * CELL)


## The arc's point at angle `a` and radius `r` (a 0 is due north of dam_centre: the crest's middle).
func arc_point(a: float, r: float = DAM_RADIUS) -> Vector2:
	return dam_centre + Vector2(sin(a), -cos(a)) * r


## Angle of `p` round the dam's centre (as arc_point()).
func arc_angle(p: Vector2) -> float:
	var q := p - dam_centre
	return atan2(q.x, -q.y)


## The ground at `pos` with the reservoir carved in, given the natural mountains `h` there.
func carve(pos: Vector2, h: float) -> float:
	if not _outer.has_point(pos):
		return h
	# The lake's depression fades out toward the edge of BOX (and is nothing outside it); the dam,
	# its shelf and the spillway reach into the outer box round the dam.
	var e := minf(minf(pos.x - BOX.position.x, BOX.end.x - pos.x), minf(pos.y - BOX.position.y, BOX.end.y - pos.y))
	var base := macro.plateau_at(pos)
	return _carve(pos, h + base, level, true, PackedFloat32Array(), smoothstep(0.0, EDGE_FADE, e)) - base


## BOX and the square round the dam's arc (set once the dam is placed).
var _outer: Rect2 = BOX


func _carve(pos: Vector2, h: float, lv: float, full: bool, terms: PackedFloat32Array = PackedFloat32Array(), lake_w: float = 1.0) -> float:
	var q := pos - dam_centre
	var rad := q.length()
	var ang := atan2(q.x, -q.y)
	# How far upstream of the dam's upstream face (m; negative downstream).
	var up := rad - DAM_RADIUS
	# The lake carve stops at the dam. Outside the dam's span the hand-over is wider, or the
	# depression would leave a step along the line of the arc beyond the dam's ends.
	var past := maxf(maxf(dam_a0 - ang, ang - dam_a1), 0.0) * DAM_RADIUS
	var band := 2.0 + clampf(past, 0.0, 60.0)
	var upf := (smoothstep(-band, band, up) if full else 1.0) * lake_w
	var r := h
	if upf > 0.0:
		if terms.is_empty():
			terms = _terms(pos)
		r = lerpf(h, _lake(terms, h, lv), upf)
	if not full:
		return r
	# The dam's footprint: held at its foundation across the gorge, cut down or filled up to it, so
	# nothing pokes through the dam and nothing is open under it.
	if ang > dam_a0 - 0.01 and ang < dam_a1 + 0.01 and up < 4.0 and up > -dam_base - 6.0:
		r = toe - 1.5
	# Downstream: a shelf at the toe (the stilling basin's platform), SHELF metres deep, then a fill
	# slope falling at 1 in FILL_SLOPE to wherever the natural gorge is, rising to the abutments at
	# its sides. Cut where the ground stands higher, filled where the gorge drops away.
	elif up <= -dam_base - 6.0 and up > -dam_base - 6.0 - 100.0 and ang > dam_a0 - 0.3 and ang < dam_a1 + 0.3:
		var below := -up - dam_base - 6.0
		var lat := maxf(maxf(dam_a0 + 0.05 - ang, ang - dam_a1 + 0.05), 0.0) * rad
		var shelf := toe - 1.5
		var beyond := maxf(below - SHELF, 0.0)
		# Both rise or fall fast enough to be past any ground by the edge of their region.
		r = minf(r, shelf + lat * 3.0 + beyond * 0.4 + maxf(below - 70.0, 0.0) * 4.0)
		var fill := shelf - minf(beyond, 36.0) * FILL_SLOPE - maxf(beyond - 36.0, 0.0) * 2.5 - lat * 2.5
		r = maxf(r, fill)
	# The trail's bench.
	if _trail_on and up > 3.0:
		var td := trail_distance(pos)
		if td < TRAIL_HALF + TRAIL_BLEND:
			var bench := level + TRAIL_RISE
			var k := smoothstep(TRAIL_HALF + TRAIL_BLEND, TRAIL_HALF, td)
			r = lerpf(r, bench, k)
	# The spillway's slot.
	if spill.size() > 1:
		var sd := _spill_query(pos)
		if sd.x < SPILL_REACH:
			# Concrete walls 3 m up, then a cut bank at 1:1 that steepens on until it is over any
			# ground (so the cut never ends in a step).
			var e := maxf(sd.x - SPILL_HALF, 0.0)
			var wall := sd.y + minf(e, 1.2) * 2.5 + maxf(e - 1.2, 0.0) * 1.0 + maxf(e - 14.0, 0.0) * 3.0
			r = minf(r, wall)
	return r


## Per arm, what the lake carve needs at `pos` whatever the level: [s (how much of the
## depression reaches here), ha + bed (the depression's depth is that less the level), bed, w,
## distance to the axis], TERMS floats an arm; s < 0 when the arm does not reach.
const TERMS := 5
func _terms(pos: Vector2) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(_arms.size() * TERMS)
	var fall := lerpf(FALL_AT_DAM, FALL, smoothstep(25.0, 170.0, _arc_distance(pos)))
	for ai in _arms.size():
		var arm: Dictionary = _arms[ai]
		var o := ai * TERMS
		out[o] = -1.0
		var bb: Rect2 = arm.bounds
		if not bb.has_point(pos):
			continue
		var pts: PackedVector2Array = arm.pts
		var best := INF
		var bt := 0.0
		var bk := 0
		for k in pts.size() - 1:
			var a := pts[k]
			var ab := pts[k + 1] - a
			var t := clampf((pos - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
			var d := pos.distance_to(a + ab * t)
			if d < best:
				best = d
				bt = t
				bk = k
		var ws: PackedFloat32Array = arm.w
		var w := lerpf(ws[bk], ws[bk + 1], bt)
		# Near the dam the depression stays in the gorge, or it would lower the walls the dam is
		# keyed into and the crest would run on for hundreds of metres.
		if best > w + fall:
			continue
		var beds: PackedFloat32Array = arm.bed
		var hs: PackedFloat32Array = _axis_ground[ai]
		var bed := lerpf(beds[bk], beds[bk + 1], bt)
		out[o] = 1.0 - smoothstep(w * 0.6, w + fall, best)
		out[o + 1] = lerpf(hs[bk], hs[bk + 1], bt) + bed
		out[o + 2] = bed
		out[o + 3] = w
		out[o + 4] = best
	return out


## Distance from `pos` to the dam's upstream face (the arc between its ends).
func _arc_distance(pos: Vector2) -> float:
	var q := pos - dam_centre
	var ang := atan2(q.x, -q.y)
	if absf(ang) <= DESIGN_SPAN:
		return absf(q.length() - DAM_RADIUS)
	return minf(pos.distance_to(arc_point(-DESIGN_SPAN)), pos.distance_to(arc_point(DESIGN_SPAN)))


## The lake's ground from the terms: the natural ground `h` less the deepest depression reaching
## here, under the core (open water along every axis, banks rising at CORE_BANK past it).
func _lake(terms: PackedFloat32Array, h: float, lv: float) -> float:
	var dep := 0.0
	var core := INF
	var core_w := 0.0
	for o in range(0, terms.size(), TERMS):
		var sv := terms[o]
		if sv < 0.0:
			continue
		dep = maxf(dep, maxf(terms[o + 1] - lv, 0.0) * sv)
		var w := terms[o + 3]
		var best := terms[o + 4]
		var c: float
		if best < w:
			var u := best / w
			c = lv - terms[o + 2] * (1.0 - u * u)
		else:
			c = lv + (best - w) * CORE_BANK
		if c < core:
			core = c
			# The core holds the water's edge; up the bank it hands back to the depressed ground,
			# or where that stands far higher it would end in a wall.
			core_w = 1.0 - smoothstep(w + CORE_HOLD, w + CORE_HOLD + CORE_RELEASE, best)
	if core == INF:
		return h - dep
	return lerpf(h - dep, _smin(h - dep, core, 6.0), core_w)


static func _smin(a: float, b: float, k: float) -> float:
	var hh := maxf(k - absf(a - b), 0.0) / k
	return minf(a, b) - hh * hh * k * 0.25


## The level: the design level, lowered until the flooded region (from the arms' axes) closes
## inside BOX less a margin. The dam is not in the ground yet, so the flood is cut at its arc.
func _fit_level() -> void:
	var g := _nat.duplicate()
	# Only the nodes an arm reaches change with the level.
	var active := PackedInt32Array()
	for c in _nx * _nz:
		var t: PackedFloat32Array = _grid_terms[c]
		for o in range(0, t.size(), TERMS):
			if t[o] >= 0.0:
				active.append(c)
				break
	var holds := func(lv: float) -> bool:
		for c in active:
			g[c] = _lake(_grid_terms[c], _nat[c], lv)
		return not _flood(g, lv, true).is_empty()
	if holds.call(DESIGN_LEVEL):
		level = DESIGN_LEVEL
	else:
		# The flood only grows with the level: bisect to a metre.
		var lo := MIN_LEVEL
		var hi := DESIGN_LEVEL
		while hi - lo > 1.0:
			var mid := (lo + hi) * 0.5
			if holds.call(mid):
				lo = mid
			else:
				hi = mid
		level = floorf(lo)
	crest = level + FREEBOARD


## The flooded cells of grid `g` at level `lv` from the arms' axes, upstream of the dam's arc
## (when `cut_dam`). Empty when the flood reaches the edge of the box (the lake would spill).
func _flood(g: PackedFloat32Array, lv: float, cut_dam: bool) -> PackedByteArray:
	var wet := PackedByteArray()
	wet.resize(_nx * _nz)
	var stack: Array[int] = []
	for arm: Dictionary in ARMS:
		for p: Vector2 in arm.pts:
			var i := int(round((p.x - BOX.position.x) / CELL))
			var j := int(round((p.y - BOX.position.y) / CELL))
			if i >= 0 and j >= 0 and i < _nx and j < _nz:
				stack.append(j * _nx + i)
	while not stack.is_empty():
		var c: int = stack.pop_back()
		if wet[c] == 1:
			continue
		var i := c % _nx
		var j := c / _nx
		if g[c] >= lv:
			continue
		if cut_dam and grid_point(i, j).distance_to(dam_centre) < DAM_RADIUS + 1.0:
			continue
		if i <= 1 or j <= 1 or i >= _nx - 2 or j >= _nz - 2:
			spilled_at = grid_point(i, j)
			return PackedByteArray()
		wet[c] = 1
		stack.append(c - 1)
		stack.append(c + 1)
		stack.append(c - _nx)
		stack.append(c + _nx)
	return wet


## The dam's span: from the crest's middle outward along the arc until the carved ground (just
## upstream of the face) stands over the crest, then ABUTMENT_KEY on into the rock. Its foundation:
## the lowest natural ground under the downstream half of the footprint, held to a sane height.
func _fit_dam() -> void:
	var step := 2.0 / DAM_RADIUS
	var ends := [0.0, 0.0]
	for side in 2:
		var sgn := -1.0 if side == 0 else 1.0
		var a := 0.0
		while absf(a) < 1.2:
			var p := arc_point(a, DAM_RADIUS + 3.0)
			var g := _carve(p, _natural(p), level, false)
			var p2 := arc_point(a, DAM_RADIUS - 6.0)
			var g2 := _natural(p2)
			if g > crest + 1.0 and g2 > crest + 1.0:
				break
			a += sgn * step
		ends[side] = a + sgn * ABUTMENT_KEY / DAM_RADIUS
	dam_a0 = ends[0]
	dam_a1 = ends[1]
	var low := INF
	var a2 := dam_a0
	while a2 <= dam_a1:
		low = minf(low, _natural(arc_point(a2, DAM_RADIUS - 12.0)))
		a2 += step * 2.0
	var hgt := clampf(crest - low, MIN_DAM_HEIGHT, MAX_DAM_HEIGHT)
	toe = crest - hgt
	dam_base = CREST_WIDTH + BATTER * hgt


## The spillway: a weir in a cut at the east abutment just upstream of the dam's end, then a
## channel round the end of the dam and a stepped chute down the hillside to the gorge's floor.
func _plan_spillway() -> void:
	spill = PackedVector2Array()
	spill_floor = PackedFloat32Array()
	var a_end := dam_a1 + 4.0 / DAM_RADIUS
	# Approach (in the lake), weir, the turn round the dam's end, then down the slope toward the
	# gorge's axis below the toe.
	var approach := arc_point(a_end - 14.0 / DAM_RADIUS, DAM_RADIUS + 26.0)
	var weir := arc_point(a_end + 6.0 / DAM_RADIUS, DAM_RADIUS + 6.0)
	var turn := arc_point(a_end + 10.0 / DAM_RADIUS, DAM_RADIUS - dam_base * 0.5)
	var down := arc_point(a_end + 4.0 / DAM_RADIUS, DAM_RADIUS - dam_base - 30.0)
	var foot := arc_point(dam_a1 * 0.45, DAM_RADIUS - dam_base - 55.0)
	var pts := [approach, weir, turn, down, foot]
	var floors := [level - 2.5, level + 0.6, level - 1.5, lerpf(level, toe, 0.7), toe - 4.0]
	for k in pts.size():
		spill.append(pts[k])
		spill_floor.append(floors[k])


## (distance to the spillway's axis, its floor height there).
func _spill_query(pos: Vector2) -> Vector2:
	var best := INF
	var fl := 0.0
	for k in spill.size() - 1:
		var a := spill[k]
		var b := spill[k + 1]
		var ab := b - a
		var t := clampf((pos - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		var d := pos.distance_to(a + ab * t)
		if d < best:
			best = d
			fl = lerpf(spill_floor[k], spill_floor[k + 1], t)
	return Vector2(best, fl)


## The final ground on the grid and the flood on it.
func _refresh_grid() -> void:
	ground_grid.resize(_nx * _nz)
	for j in _nz:
		for i in _nx:
			ground_grid[j * _nx + i] = _carve(grid_point(i, j), _nat[j * _nx + i], level, true, _grid_terms[j * _nx + i])
	wet_grid = _flood(ground_grid, level, true)
	_spilled = wet_grid.is_empty()
	if _spilled:
		wet_grid.resize(_nx * _nz)


## The trail: the contour of the carved ground at TRAIL_RISE over the water round the flooded
## region, upstream of the dam, as polylines (Chaikin-smoothed, resampled every 3 m).
func _plan_trail() -> void:
	trail = []
	for line: PackedVector2Array in contour(level + TRAIL_RISE, 120.0):
		var sm := line
		for it in 3:
			sm = _chaikin(sm)
		trail.append(_resample(sm, 3.0))
	_trail_cells = {}
	for li in trail.size():
		var line: PackedVector2Array = trail[li]
		for k in line.size() - 1:
			var mid := (line[k] + line[k + 1]) * 0.5
			var key := Vector2i(floori(mid.x / TRAIL_CELL), floori(mid.y / TRAIL_CELL))
			if not _trail_cells.has(key):
				_trail_cells[key] = []
			(_trail_cells[key] as Array).append(Vector2i(li, k))
	_trail_on = not trail.is_empty()


## The contour of the carved ground at height `th` round the lake (within 80 m of its water and
## upstream of the dam's arc), as polylines at least `min_length` long (marching squares on the
## grid, unsmoothed).
func contour(th: float, min_length: float) -> Array[PackedVector2Array]:
	var near := _dilate(wet_grid, int(80.0 / CELL))
	var segs: Array = []
	for j in _nz - 1:
		for i in _nx - 1:
			var c := j * _nx + i
			if near[c] == 0:
				continue
			var p0 := grid_point(i, j)
			if p0.distance_to(dam_centre) < DAM_RADIUS + 8.0:
				continue
			var v := [ground_grid[c] - th, ground_grid[c + 1] - th, ground_grid[c + _nx + 1] - th, ground_grid[c + _nx] - th]
			var corners := [p0, p0 + Vector2(CELL, 0.0), p0 + Vector2(CELL, CELL), p0 + Vector2(0.0, CELL)]
			var cross: Array = []
			for e in 4:
				var va: float = v[e]
				var vb: float = v[(e + 1) % 4]
				if (va < 0.0) != (vb < 0.0):
					var t := va / (va - vb)
					cross.append((corners[e] as Vector2).lerp(corners[(e + 1) % 4], t))
			if cross.size() == 2:
				segs.append([cross[0], cross[1]])
			elif cross.size() == 4:
				segs.append([cross[0], cross[1]])
				segs.append([cross[2], cross[3]])
	var out: Array[PackedVector2Array] = []
	for line: PackedVector2Array in _chain(segs):
		if _length(line) >= min_length:
			out.append(line)
	return out


## The ring line: the contour just over the waterline (the bathtub ring's middle), every 10 m.
var _ring_line: Array[PackedVector2Array] = []
func ring_line() -> Array[PackedVector2Array]:
	if _ring_line.is_empty():
		for line in contour(level + 2.0, 20.0):
			_ring_line.append(_resample(line, 10.0))
	return _ring_line


## Where CityChunk's hill shells must not grow inside `area` ([a, b, reach] like its other
## marks): the bathtub ring and the shore, the trail, the dam and the spillway.
func shell_marks(area: Rect2) -> Array:
	var marks: Array = []
	if not BOX.grow(20.0).intersects(area):
		return marks
	for line in ring_line():
		for k in line.size() - 1:
			if area.has_point(line[k]) or area.has_point(line[k + 1]):
				marks.append([line[k], line[k + 1], 7.0])
	for line in trail:
		for k in range(0, line.size() - 2, 2):
			if area.has_point(line[k]) or area.has_point(line[k + 2]):
				marks.append([line[k], line[k + 2], TRAIL_HALF + 1.5])
	for k in spill.size() - 1:
		marks.append([spill[k], spill[k + 1], SPILL_HALF + 3.0])
	var n := maxi(2, int((dam_a1 - dam_a0) * DAM_RADIUS / 10.0))
	for k in n:
		var a := lerpf(dam_a0, dam_a1, float(k) / float(n - 1))
		var mid := arc_point(a, DAM_RADIUS - dam_base * 0.5)
		if area.grow(dam_base).has_point(mid):
			marks.append([mid, mid, dam_base * 0.5 + 6.0])
	return marks


## Distance from `pos` to the trail's centre line (INF when far from it).
func trail_distance(pos: Vector2) -> float:
	var c := Vector2i(floori(pos.x / TRAIL_CELL), floori(pos.y / TRAIL_CELL))
	var best := INF
	for dj in range(-1, 2):
		for di in range(-1, 2):
			var arr: Array = _trail_cells.get(c + Vector2i(di, dj), [])
			for e: Vector2i in arr:
				var line: PackedVector2Array = trail[e.x]
				var a := line[e.y]
				var b := line[e.y + 1]
				var ab := b - a
				var t := clampf((pos - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
				best = minf(best, pos.distance_to(a + ab * t))
	return best


func _dilate(g: PackedByteArray, n: int) -> PackedByteArray:
	var out := g.duplicate()
	for it in n:
		var nxt := out.duplicate()
		for j in range(1, _nz - 1):
			for i in range(1, _nx - 1):
				var c := j * _nx + i
				if out[c] == 0 and (out[c - 1] == 1 or out[c + 1] == 1 or out[c - _nx] == 1 or out[c + _nx] == 1):
					nxt[c] = 1
		out = nxt
	return out


## Joins marching-squares segments end to end into polylines.
static func _chain(segs: Array) -> Array:
	var ends := {}
	var key := func(p: Vector2) -> Vector2i:
		return Vector2i(roundi(p.x * 20.0), roundi(p.y * 20.0))
	for si in segs.size():
		for e in 2:
			var k: Vector2i = key.call(segs[si][e])
			if not ends.has(k):
				ends[k] = []
			(ends[k] as Array).append(si)
	var used := PackedByteArray()
	used.resize(segs.size())
	var lines: Array = []
	for si in segs.size():
		if used[si] == 1:
			continue
		used[si] = 1
		var line: Array = [segs[si][0], segs[si][1]]
		for dir in 2:
			while true:
				var tip: Vector2 = line[-1] if dir == 0 else line[0]
				var next := -1
				for cand: int in ends.get(key.call(tip), []):
					if used[cand] == 0:
						next = cand
						break
				if next < 0:
					break
				used[next] = 1
				var s: Array = segs[next]
				var other: Vector2 = s[1] if key.call(s[0]) == key.call(tip) else s[0]
				if dir == 0:
					line.append(other)
				else:
					line.push_front(other)
		lines.append(PackedVector2Array(line))
	return lines


static func _length(line: PackedVector2Array) -> float:
	var s := 0.0
	for k in line.size() - 1:
		s += line[k].distance_to(line[k + 1])
	return s


static func _chaikin(line: PackedVector2Array) -> PackedVector2Array:
	var closed := line.size() > 3 and line[0].distance_to(line[line.size() - 1]) < 0.5
	var out := PackedVector2Array()
	if not closed:
		out.append(line[0])
	for k in line.size() - 1:
		out.append(line[k].lerp(line[k + 1], 0.25))
		out.append(line[k].lerp(line[k + 1], 0.75))
	if not closed:
		out.append(line[line.size() - 1])
	else:
		out.append(out[0])
	return out


static func _resample(line: PackedVector2Array, step: float) -> PackedVector2Array:
	var out := PackedVector2Array([line[0]])
	var carry := 0.0
	for k in line.size() - 1:
		var a := line[k]
		var b := line[k + 1]
		var seg := a.distance_to(b)
		var t := step - carry
		while t <= seg:
			out.append(a.lerp(b, t / seg))
			t += step
		carry = seg - (t - step)
	if out[out.size() - 1].distance_to(line[line.size() - 1]) > step * 0.3:
		out.append(line[line.size() - 1])
	return out


# --- Queries --------------------------------------------------------------------------------------

## True where the lake's water stands over `pos` (the flood on the grid, bilinear by nearest node).
func wet(pos: Vector2) -> bool:
	if not BOX.has_point(pos):
		return false
	var i := int(round((pos.x - BOX.position.x) / CELL))
	var j := int(round((pos.y - BOX.position.y) / CELL))
	if i < 0 or j < 0 or i >= _nx or j >= _nz:
		return false
	return wet_grid[j * _nx + i] == 1


## True where nothing should be planted or scattered: under the water, on the bathtub ring
## (`margin` metres over the level) or on the trail's bench, inside the lake's neighbourhood.
func keep_clear(pos: Vector2, ground_h: float, margin: float = 6.0) -> bool:
	if not _outer.has_point(pos):
		return false
	if ground_h < level + margin and near_lake(pos, 40.0):
		return true
	if _trail_on and trail_distance(pos) < TRAIL_HALF + 2.5:
		return true
	if spill.size() > 1 and _spill_query(pos).x < SPILL_HALF + 4.0:
		return true
	var q := pos - dam_centre
	var ang := atan2(q.x, -q.y)
	return ang > dam_a0 - 0.02 and ang < dam_a1 + 0.02 and q.length() > DAM_RADIUS - dam_base - 8.0 and q.length() < DAM_RADIUS + 6.0


## True within `reach` metres of open water.
func near_lake(pos: Vector2, reach: float) -> bool:
	var n := int(ceil(reach / CELL))
	var ci := int(round((pos.x - BOX.position.x) / CELL))
	var cj := int(round((pos.y - BOX.position.y) / CELL))
	for dj in range(-n, n + 1, maxi(1, n / 3)):
		for di in range(-n, n + 1, maxi(1, n / 3)):
			var i := ci + di
			var j := cj + dj
			if i >= 0 and j >= 0 and i < _nx and j < _nz and wet_grid[j * _nx + i] == 1:
				return true
	return false


## Grid size (nodes) and its data, for the builders.
func grid_size() -> Vector2i:
	return Vector2i(_nx, _nz)


## Water depth at grid node (i, j) (0 on dry ground).
func depth_at_node(i: int, j: int) -> float:
	return maxf(level - ground_grid[j * _nx + i], 0.0)


## A mask of the lake's neighbourhood over BOX for the terrain shader (R: 1 on the water and
## fading out over `fade` metres from it), size x size.
func mask_image(size: int, fade: float) -> Image:
	var img := Image.create(size, size, false, Image.FORMAT_L8)
	var near := _dilate(wet_grid, int(fade / CELL))
	var near2 := _dilate(wet_grid, int(fade * 0.5 / CELL))
	for py in size:
		for px in size:
			var p := BOX.position + Vector2((float(px) + 0.5) / size * BOX.size.x, (float(py) + 0.5) / size * BOX.size.y)
			var i := clampi(int(round((p.x - BOX.position.x) / CELL)), 0, _nx - 1)
			var j := clampi(int(round((p.y - BOX.position.y) / CELL)), 0, _nz - 1)
			var c := j * _nx + i
			var v := 0.0
			if wet_grid[c] == 1:
				v = 1.0
			elif near2[c] == 1:
				v = 0.75
			elif near[c] == 1:
				v = 0.4
			# Not on the dam's downstream side: its gorge walls are not the lake's shore.
			if p.distance_to(dam_centre) < DAM_RADIUS + 2.0:
				v = 0.0
			img.set_pixel(px, py, Color(v, v, v))
	return img


## The ridge round the lake seen from its middle at the waterline: per azimuth (N_RIDGE of them,
## 0 north, clockwise seen from above toward +x), the tangent of the highest elevation angle,
## 1 where that ridge is the dam, and its distance (for the water's mirror): [tans, dams, dists].
const N_RIDGE := 48
var _ridge: Array = []
func ridge_profile() -> Array:
	if not _ridge.is_empty():
		return _ridge
	var tans := PackedFloat32Array()
	var dams := PackedFloat32Array()
	var dists := PackedFloat32Array()
	var c := lake_centre()
	for k in N_RIDGE:
		var az := TAU * float(k) / float(N_RIDGE)
		var dir := Vector2(sin(az), -cos(az))
		var best := 0.0
		var is_dam := 0.0
		var best_d := 600.0
		var d := 30.0
		while d < 2400.0:
			var p := c + dir * d
			var h := macro.height_at(p)
			var q := p - dam_centre
			var ang := atan2(q.x, -q.y)
			var on_dam := ang > dam_a0 and ang < dam_a1 and q.length() < DAM_RADIUS + 1.0 and q.length() > DAM_RADIUS - CREST_WIDTH
			if on_dam:
				h = maxf(h, crest + 1.2)
			var t := (h - level) / d
			if t > best:
				best = t
				best_d = d
				is_dam = 1.0 if on_dam else 0.0
			d += 12.0 if d < 600.0 else 40.0
		tans.append(best)
		dams.append(is_dam)
		dists.append(best_d)
	_ridge = [tans, dams, dists]
	return _ridge


## Where the lake's mirror is measured from: the middle of the wet grid.
func lake_centre() -> Vector2:
	var s := Vector2.ZERO
	var n := 0
	for j in _nz:
		for i in _nx:
			if wet_grid[j * _nx + i] == 1:
				s += grid_point(i, j)
				n += 1
	return s / maxf(float(n), 1.0) if n > 0 else ANCHOR


## Wet area in square metres (tests, probes).
func wet_area() -> float:
	var n := 0
	for v in wet_grid:
		n += v
	return float(n) * CELL * CELL


## Crest length along the arc (m).
func crest_length() -> float:
	return (dam_a1 - dam_a0) * DAM_RADIUS
