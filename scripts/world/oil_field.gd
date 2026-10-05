class_name OilField
extends RefCounted
## Los Angeles' urban oil field (2026-10-05, "pumpjacks nodding on bare hills in the middle of the
## city"): a low hill south-west of downtown, between the 105 and the beach towns, in the forms of
## the Baldwin Hills / Inglewood field - dry grass and scrub, dirt lease roads winding round the
## hill and up to its crest, dozens of pumpjacks on graded pads, tank batteries in their berms, two
## drilling rigs, pipe runs on supports, a power line, a chain-link fence round it all with the
## operator's warning signs. The operator and the lease names are invented.
##
## This file is the DATA (pure, from the seed): the site (a landmark area, snapped to the street
## grid like MacArthur Park, its interior streets closed - CityPlan.sites()), the hill (folded into
## the city's relief by MacroMap._relief_at() through apply(): the ground, the perimeter streets,
## the far city's plates and anything else that stands on the relief follow it with no code of
## their own), the lease roads and their grade, the pads and what stands on each. OilFieldBuild
## builds it, OilKit is the hardware. Built once per MacroMap (MacroMap.oil), before the hill
## roads and the freeway. `OIL_FIELD=0` in the environment leaves it out (the A/B).
##
## The single pumpjacks hidden in the city (an industrial lot, a lot between houses) are
## lot_well(): a pure claim on a lot, asked by CityChunk._build_lot() after every roll.

const ID := "oil_field"
## The edges asked for (world XZ); CityPlan snaps each to the nearest road. Midtown, south of the
## 105 and west of the 110, north-east of the airport: where the Baldwin Hills stand relative to
## the airport and downtown, the distances compressed like everything west of downtown.
const WANT_WEST := 270.0
const WANT_EAST := 1050.0
const WANT_NORTH := 1340.0
const WANT_SOUTH := 1890.0
## How high the hill's crest stands over the ground round it (m), and the width of the ring
## from the kerb in which the city's own relief is handed over to the hill.
const PEAK := 46.0
const EDGE_BLEND := 36.0
## The pavement round the site (as a block's), and the fence just inside it.
const PAVEMENT := 4.0
const FENCE_IN := 5.5
## Lease roads: half the graded width, the bank either side, the steepest grade (a pickup and a
## workover rig climb it), the sample step along them.
const ROAD_HALF := 3.4
const ROAD_BANK := 8.0
const MAX_GRADE := 0.125
const STEP := 6.0
## A pad's bank (its cut or fill down to the hill).
const PAD_BANK := 9.0
## Pumpjacks: their spacing on a pad (m, at scale 1) and their size range.
const WELL_PITCH := 13.5
const SCALE_RANGE := Vector2(0.78, 1.18)
## Share of wells standing idle (a pumpjack waiting on a workover is a still one).
const IDLE_SHARE := 0.12
## Strokes per minute of a running one.
const SPM_RANGE := Vector2(5.5, 10.5)
## Pads per kind: drilling rigs, tank batteries; the rest wells.
const RIGS := 2
const BATTERY_EVERY := 7
## Spatial index cell (m).
const CELL := 32.0
## The invented operator, on every sign.
const OPERATOR := "BASIN CREST OIL CO."
const LEASES := ["HOLLISTER", "VANCE", "MERRIDEW", "CALDERA", "OKAFOR", "LINDQVIST", "PAXTON", "ARROYO SECO", "DUNMORE", "TELLEZ"]

enum Pad { WELLS, BATTERY, RIG }

## Off: no site, no hill, no claimed lots. Set before the city loads (Landmarks.all() is built once).
static var enabled: bool = OS.get_environment("OIL_FIELD") != "0"

var seed: int = 0
## Kerb to kerb (the snapped site), its road indices, centre and half size.
var rect := Rect2()
var ix0 := 0
var ix1 := 0
var iz0 := 0
var iz1 := 0
var centre := Vector2.ZERO
var half := Vector2.ONE
## The relief the hill stands on (the city's relief round the site, averaged).
var base_h := 0.0
## [{"pts": PackedVector2Array, "h": PackedFloat32Array (relief at each point), "ring": bool}]
var roads: Array = []
## The fence gates where a spoke road meets the perimeter: [{"p": Vector2 (on the fence line), "side": 0 -Z, 1 +Z, 2 -X, 3 +X}]
var gates: Array = []
## [{"c": Vector2, "r": float, "h": float (relief), "kind": Pad, "dir": Vector2 (along the road),
##   "out": Vector2 (away from the road), "wells": [{"p", "yaw", "scale", "phase", "spm", "paint"}],
##   "lease": String, "id": int}]
var pads: Array = []
var _noise: FastNoiseLite
var _ridge: FastNoiseLite
## Vector2i cell -> [[road index, segment index], ...] and Vector2i cell -> [pad index, ...].
var _seg_cells: Dictionary = {}
var _pad_cells: Dictionary = {}


## The field for this map, or null (off, or the site does not snap).
static func make(macro: MacroMap, sd: int) -> OilField:
	if not enabled:
		return null
	var f := OilField.new()
	if not f._build(macro, sd):
		return null
	return f


## The entry Landmarks.all() lists: an area site (CityPlan snaps it to whole blocks and closes the
## streets through it), anchored at its centre with a token radius (the hill is the relief's own;
## a big radius would flatten it).
static func entry() -> Dictionary:
	return {
		"id": ID, "anchor": Vector2((WANT_WEST + WANT_EAST) * 0.5, (WANT_NORTH + WANT_SOUTH) * 0.5), "radius": 1.0,
		"area": {"west_x": WANT_WEST, "east_x": WANT_EAST, "north_z": WANT_NORTH, "south_z": WANT_SOUTH, "keep_z": [], "streets": {}},
	}


static func _h01(parts: Array) -> float:
	return float(absi(hash(parts)) % 100003) / 100003.0


# --- Building the data ---------------------------------------------------------------------------

func _build(macro: MacroMap, sd: int) -> bool:
	seed = sd
	# The street grid alone (road positions and widths depend on the seed and the pinned real
	# streets, nothing else): the same snap CityPlan.sites() makes.
	var cp := CityPlan.new()
	cp.seed = sd
	ix0 = cp._nearest_road(CityPlan.AXIS_X, WANT_WEST)
	ix1 = cp._nearest_road(CityPlan.AXIS_X, WANT_EAST)
	iz0 = cp._nearest_road(CityPlan.AXIS_Z, WANT_NORTH)
	iz1 = cp._nearest_road(CityPlan.AXIS_Z, WANT_SOUTH)
	if ix1 - ix0 < 2 or iz1 - iz0 < 2:
		return false
	var x0 := cp.road_pos(CityPlan.AXIS_X, ix0) + cp.road_width(CityPlan.AXIS_X, ix0) * 0.5
	var x1 := cp.road_pos(CityPlan.AXIS_X, ix1) - cp.road_width(CityPlan.AXIS_X, ix1) * 0.5
	var z0 := cp.road_pos(CityPlan.AXIS_Z, iz0) + cp.road_width(CityPlan.AXIS_Z, iz0) * 0.5
	var z1 := cp.road_pos(CityPlan.AXIS_Z, iz1) - cp.road_width(CityPlan.AXIS_Z, iz1) * 0.5
	rect = Rect2(x0, z0, x1 - x0, z1 - z0)
	centre = rect.get_center()
	half = rect.size * 0.5
	_noise = FastNoiseLite.new()
	_noise.seed = sd + 4051
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 1.0 / 260.0
	_noise.fractal_octaves = 2
	_ridge = FastNoiseLite.new()
	_ridge.seed = sd + 4057
	_ridge.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_ridge.frequency = 1.0 / 150.0
	_ridge.fractal_octaves = 2
	# The ground the hill rises from: the city's relief round the kerb.
	var sum := 0.0
	var n := 0
	for i in 32:
		var t := float(i) / 32.0
		for p: Vector2 in [Vector2(lerpf(x0, x1, t), z0), Vector2(lerpf(x0, x1, t), z1), Vector2(x0, lerpf(z0, z1, t)), Vector2(x1, lerpf(z0, z1, t))]:
			sum += macro._relief_natural(p, macro.raw_height_at(p))
			n += 1
	base_h = sum / float(n)
	_plan_roads(macro)
	_plan_pads()
	_index()
	return true


## Where `p` is in the hill's own frame: 0 at the centre, 1 at the inner edge of the hand-over
## ring (a rounded rectangle, its outline wobbled by the noise).
func _d(p: Vector2) -> float:
	var inner := half - Vector2(EDGE_BLEND, EDGE_BLEND)
	var q := (p - centre) / inner
	var d := pow(pow(absf(q.x), 3.2) + pow(absf(q.y), 3.2), 1.0 / 3.2)
	return d + _noise.get_noise_2dv(p * 1.7) * 0.07


## The hill before any grading: a broad crest with flanks falling away, spurs and gullies cut down
## them (both strongest mid-flank), metres of relief.
func hill(p: Vector2) -> float:
	var d := _d(p)
	var prof := 1.0 - smoothstep(0.16, 1.0, d)
	var flank := sin(clampf(prof, 0.0, 1.0) * PI)
	var spur := _noise.get_noise_2dv(p) * 0.09
	var gully := pow(1.0 - absf(_ridge.get_noise_2dv(p)), 5.0) * 0.08
	var rise := clampf(prof + (spur - gully) * flank, 0.0, 1.15)
	return base_h + PEAK * rise


## The gully strength at `p` (0 open slope .. 1 gully floor), for the ground's drainage colour.
func drainage(p: Vector2) -> float:
	var flank := sin(clampf(1.0 - smoothstep(0.16, 1.0, _d(p)), 0.0, 1.0) * PI)
	return clampf(pow(1.0 - absf(_ridge.get_noise_2dv(p)), 5.0) * flank * 1.6, 0.0, 1.0)


## The relief with the field folded in (MacroMap._relief_at()): the city's own outside the site,
## handed over to the graded hill across the ring inside the kerb.
func apply(p: Vector2, h: float) -> float:
	if not rect.has_point(p):
		return h
	var e := minf(minf(p.x - rect.position.x, rect.end.x - p.x), minf(p.y - rect.position.y, rect.end.y - p.y))
	var w := smoothstep(0.0, EDGE_BLEND, e)
	if w <= 0.0:
		return h
	return lerpf(h, graded(p), w)


## The hill as graded: the lease roads benched into it, the pads levelled, each with its banks.
func graded(p: Vector2) -> float:
	var h := hill(p)
	var cell := Vector2i(floori(p.x / CELL), floori(p.y / CELL))
	var segs: Array = _seg_cells.get(cell, [])
	var best := INF
	var road_h := 0.0
	for s: Array in segs:
		var rd: Dictionary = roads[s[0]]
		var pts: PackedVector2Array = rd.pts
		var hs: PackedFloat32Array = rd.h
		var i: int = s[1]
		var a := pts[i]
		var b := pts[i + 1]
		var ab := b - a
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
		var dist := p.distance_to(a + ab * t)
		if dist < best:
			best = dist
			road_h = lerpf(hs[i], hs[i + 1], t)
	if best < ROAD_HALF + ROAD_BANK:
		h = lerpf(h, road_h, 1.0 - smoothstep(ROAD_HALF + 0.6, ROAD_HALF + ROAD_BANK, best))
	for k: int in _pad_cells.get(cell, []):
		var pd: Dictionary = pads[k]
		var dist := p.distance_to(pd.c)
		var r: float = pd.r
		if dist < r + PAD_BANK:
			h = lerpf(h, pd.h, 1.0 - smoothstep(r, r + PAD_BANK, dist))
	return h


# --- Roads -----------------------------------------------------------------------------------------

## A point of the ring road (the contour round the hill's flank) at angle `a`.
func _ring_point(a: float, d: float) -> Vector2:
	var inner := half - Vector2(EDGE_BLEND, EDGE_BLEND)
	var c := Vector2(cos(a), sin(a))
	# The rounded rectangle's own radius that way, then wobbled.
	var k := pow(pow(absf(c.x), 3.2) + pow(absf(c.y), 3.2), -1.0 / 3.2)
	var wob := 1.0 + 0.06 * sin(a * 3.0 + float(seed % 7)) + 0.04 * sin(a * 5.0 + 1.3)
	return centre + c * inner * k * d * wob


func _plan_roads(macro: MacroMap) -> void:
	roads = []
	gates = []
	# The ring road round the flank and the loop round the crest.
	var ring := PackedVector2Array()
	var crest := PackedVector2Array()
	var n := 96
	for i in n + 1:
		var a := TAU * float(i) / float(n)
		ring.append(_ring_point(a, 0.6))
	for i in 49:
		var a := TAU * float(i) / 48.0
		crest.append(_ring_point(a, 0.2))
	ring = _resample(ring, STEP)
	crest = _resample(crest, STEP)
	var ring_h := _profile(ring, -1.0, -1.0, true)
	roads.append({"pts": ring, "h": ring_h, "ring": true})
	# Three gates on three of the four sides (the fourth by hash), each a spoke up the flank that
	# meets the ring at an angle (a straight climb would be too steep for the grade).
	var skip := absi(hash([seed, "oil_gate_skip"])) % 4
	for side in 4:
		if side == skip:
			continue
		var along := lerpf(0.3, 0.7, _h01([seed, "oil_gate", side]))
		var fence := rect.grow(-FENCE_IN)
		var g: Vector2
		var inward: Vector2
		match side:
			0:
				g = Vector2(lerpf(fence.position.x, fence.end.x, along), fence.position.y)
				inward = Vector2(0.0, 1.0)
			1:
				g = Vector2(lerpf(fence.position.x, fence.end.x, along), fence.end.y)
				inward = Vector2(0.0, -1.0)
			2:
				g = Vector2(fence.position.x, lerpf(fence.position.y, fence.end.y, along))
				inward = Vector2(1.0, 0.0)
			_:
				g = Vector2(fence.end.x, lerpf(fence.position.y, fence.end.y, along))
				inward = Vector2(-1.0, 0.0)
		gates.append({"p": g, "side": side})
		# The ring point the spoke climbs to: off to one side of the straight line in.
		var straight := (g - centre).angle()
		var off := (0.55 if _h01([seed, "oil_spoke", side]) < 0.5 else -0.55)
		var target := _ring_point(straight + off, 0.6)
		var spoke := PackedVector2Array()
		# From outside the fence on the pavement edge, in square to the fence, then curving round.
		var start := g - inward * (FENCE_IN - PAVEMENT + 0.2)
		var mid1 := g + inward * 18.0
		var mid2 := mid1.lerp(target, 0.5) + (target - mid1).orthogonal().normalized() * (14.0 * signf(off))
		for i in 25:
			var t := float(i) / 24.0
			spoke.append(_bezier(start, mid1, mid2, target, t))
		spoke = _resample(spoke, STEP)
		# Snap its end onto the ring, then the grade: the gate end at the street's relief, the ring
		# end at the ring's own height.
		var j := _nearest_index(ring, target)
		spoke[spoke.size() - 1] = ring[j]
		var street_h := macro._relief_natural(start, macro.raw_height_at(start))
		var h := _profile(spoke, street_h, ring_h[j], false)
		roads.append({"pts": spoke, "h": h, "ring": false})
	# The crest loop and the road up to it from the ring, on the far side of the first gate.
	var up_a := (gates[0].p as Vector2 - centre).angle() + PI * 0.75
	var low := _nearest_index(ring, _ring_point(up_a, 0.6))
	var top := _nearest_index(crest, _ring_point(up_a + 0.9, 0.2))
	var crest_h := _profile(crest, -1.0, -1.0, true)
	roads.append({"pts": crest, "h": crest_h, "ring": true})
	var up := PackedVector2Array()
	var a0 := ring[low]
	var a3 := crest[top]
	var tangent := (ring[mini(low + 1, ring.size() - 1)] - ring[maxi(low - 1, 0)]).normalized()
	for i in 21:
		var t := float(i) / 20.0
		up.append(_bezier(a0, a0 + tangent * 110.0, a3 - (a3 - centre).orthogonal().normalized() * 90.0, a3, t))
	up = _resample(up, STEP)
	up[0] = a0
	up[up.size() - 1] = a3
	roads.append({"pts": up, "h": _profile(up, ring_h[low], crest_h[top], false), "ring": false})


static func _bezier(a: Vector2, b: Vector2, c: Vector2, d: Vector2, t: float) -> Vector2:
	var u := 1.0 - t
	return a * u * u * u + b * 3.0 * u * u * t + c * 3.0 * u * t * t + d * t * t * t


## A polyline resampled to points `step` apart (the last point kept).
static func _resample(pts: PackedVector2Array, step: float) -> PackedVector2Array:
	var out := PackedVector2Array([pts[0]])
	var carry := 0.0
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var seg := a.distance_to(b)
		var s := step - carry
		while s <= seg:
			out.append(a.lerp(b, s / seg))
			s += step
		carry = seg - (s - step)
	if out[out.size() - 1].distance_to(pts[pts.size() - 1]) > step * 0.3:
		out.append(pts[pts.size() - 1])
	else:
		out[out.size() - 1] = pts[pts.size() - 1]
	return out


static func _nearest_index(pts: PackedVector2Array, p: Vector2) -> int:
	var best := 0
	for i in pts.size():
		if pts[i].distance_squared_to(p) < pts[best].distance_squared_to(p):
			best = i
	return best


## A road's height profile: the hill under it smoothed, its ends held where they must meet (a
## negative end is free), and the grade limited both ways (the higher of the forward and the
## backward limits never steeper than MAX_GRADE: the bed is cut or filled where the hill is not).
func _profile(pts: PackedVector2Array, h0: float, h1: float, closed: bool) -> PackedFloat32Array:
	var n := pts.size()
	var raw := PackedFloat32Array()
	raw.resize(n)
	for i in n:
		raw[i] = hill(pts[i])
	var sm := PackedFloat32Array()
	sm.resize(n)
	for i in n:
		var s := 0.0
		var w := 0.0
		for k in range(-4, 5):
			var j := i + k
			if closed:
				j = posmod(j, n - 1)
			elif j < 0 or j >= n:
				continue
			var wk := 1.0 - absf(float(k)) / 5.0
			s += raw[j] * wk
			w += wk
		sm[i] = s / w
	if h0 >= -0.5:
		sm[0] = h0
	if h1 >= -0.5:
		sm[n - 1] = h1
	# Alternate forward and backward clamps until the profile holds the grade everywhere; pinned
	# ends never move (a closed loop runs round twice, its last point its first).
	var m := n - 1 if closed else n
	for pass_i in 24:
		var moved := 0.0
		var span := 2 * m if closed else m
		for k in range(1, span):
			var i := k % m
			var j := (k - 1) % m
			if (i == 0 and h0 >= -0.5) or (not closed and i == n - 1 and h1 >= -0.5):
				continue
			var d := pts[i].distance_to(pts[j]) * MAX_GRADE
			var c := clampf(sm[i], sm[j] - d, sm[j] + d)
			moved = maxf(moved, absf(c - sm[i]))
			sm[i] = c
		for k in range(span - 2, -1, -1):
			var i := k % m
			var j := (k + 1) % m
			if (i == 0 and h0 >= -0.5) or (not closed and i == n - 1 and h1 >= -0.5):
				continue
			var d := pts[i].distance_to(pts[j]) * MAX_GRADE
			var c := clampf(sm[i], sm[j] - d, sm[j] + d)
			moved = maxf(moved, absf(c - sm[i]))
			sm[i] = c
		if moved < 0.001:
			break
	if closed:
		sm[n - 1] = sm[0]
	return sm


## The distance from `p` to the nearest lease road, and that road's height there.
func road_distance(p: Vector2) -> Vector2:
	var best := INF
	var hh := 0.0
	for rd: Dictionary in roads:
		var pts: PackedVector2Array = rd.pts
		var hs: PackedFloat32Array = rd.h
		for i in pts.size() - 1:
			var a := pts[i]
			var ab := pts[i + 1] - a
			var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
			var d := p.distance_to(a + ab * t)
			if d < best:
				best = d
				hh = lerpf(hs[i], hs[i + 1], t)
	return Vector2(best, hh)


# --- Pads ------------------------------------------------------------------------------------------

func _plan_pads() -> void:
	pads = []
	var fence := rect.grow(-FENCE_IN)
	var rig_slots := RIGS
	var count := 0
	for ri in roads.size():
		var rd: Dictionary = roads[ri]
		var pts: PackedVector2Array = rd.pts
		var hs: PackedFloat32Array = rd.h
		var i := 3 + int(_h01([seed, "oil_pad0", ri]) * 4.0)
		while i < pts.size() - 3:
			var dir := (pts[i + 1] - pts[i - 1]).normalized()
			var side := 1.0 if _h01([seed, "oil_side", ri, i]) < 0.5 else -1.0
			var kind := Pad.WELLS
			var r := 0.0
			var wells := 1 + int(_h01([seed, "oil_nwell", ri, i]) * 2.6)
			if rig_slots > 0 and bool(rd.ring) and _h01([seed, "oil_rig", ri, i]) < 0.12 and count > 3:
				kind = Pad.RIG
				r = 19.0
			elif count % BATTERY_EVERY == BATTERY_EVERY - 1:
				kind = Pad.BATTERY
				r = 16.0
			else:
				r = 4.5 + float(wells) * WELL_PITCH * 0.5
			var placed := false
			for flip in 2:
				var s := side * (1.0 if flip == 0 else -1.0)
				var out := dir.orthogonal() * s
				var c := pts[i] + out * (ROAD_HALF + r + 1.5)
				if _pad_fits(c, r, fence, ri, i):
					var pd := {"c": c, "r": r, "h": lerpf(hs[i], hill(c), 0.55), "kind": kind, "dir": dir, "out": out,
						"wells": [], "id": pads.size(), "lease": LEASES[absi(hash([seed, "oil_lease", ri, i / 20])) % LEASES.size()]}
					if kind == Pad.WELLS:
						_wells_on(pd, wells)
					elif kind == Pad.RIG:
						rig_slots -= 1
					pads.append(pd)
					count += 1
					placed = true
					break
			i += (int(r * 2.0 / STEP) + 2 + int(_h01([seed, "oil_gap", ri, i]) * 4.0)) if placed else 2


func _pad_fits(c: Vector2, r: float, fence: Rect2, ri: int, i: int) -> bool:
	if not fence.grow(-(r + EDGE_BLEND * 0.6)).has_point(c):
		return false
	for pd: Dictionary in pads:
		if c.distance_to(pd.c) < r + float(pd.r) + 7.0:
			return false
	# Clear of every road but where it hangs off its own.
	for rj in roads.size():
		var pts: PackedVector2Array = roads[rj].pts
		for k in pts.size() - 1:
			if rj == ri and absi(k - i) <= 1:
				continue
			var a := pts[k]
			var ab := pts[k + 1] - a
			var t := clampf((c - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
			if c.distance_to(a + ab * t) < r + ROAD_HALF + 1.0:
				return false
	return true


## The pumpjacks on a wells pad, in a row along the road, each facing the same way (horsehead
## toward +along), painted per pad.
func _wells_on(pd: Dictionary, n: int) -> void:
	var dir: Vector2 = pd.dir
	var paint := absi(hash([seed, "oil_paint", pd.id])) % OilKit.PAINTS.size()
	var flip := _h01([seed, "oil_face", pd.id]) < 0.5
	for k in n:
		var along := (float(k) - float(n - 1) * 0.5) * WELL_PITCH
		var p: Vector2 = pd.c + dir * along
		var face := dir * (-1.0 if flip else 1.0)
		var sc := lerpf(SCALE_RANGE.x, SCALE_RANGE.y, _h01([seed, "oil_scale", pd.id, k]))
		var spm := lerpf(SPM_RANGE.x, SPM_RANGE.y, _h01([seed, "oil_spm", pd.id, k]))
		if _h01([seed, "oil_idle", pd.id, k]) < IDLE_SHARE:
			spm = 0.0
		# The pumpjack's own +X (wellhead end) along `face`; its origin is the wellhead, so the
		# unit is centred on the pad by pulling it back half its length.
		var w := {"p": p + face * OilKit.LENGTH * sc * 0.5 - face * OilKit.LENGTH * sc * 0.08, "yaw": atan2(-face.y, face.x),
			"scale": sc, "phase": _h01([seed, "oil_phase", pd.id, k]), "spm": spm, "paint": paint}
		(pd.wells as Array).append(w)


func _index() -> void:
	_seg_cells = {}
	_pad_cells = {}
	var reach := ROAD_HALF + ROAD_BANK + 1.0
	for ri in roads.size():
		var pts: PackedVector2Array = roads[ri].pts
		for i in pts.size() - 1:
			var lo := Vector2(minf(pts[i].x, pts[i + 1].x), minf(pts[i].y, pts[i + 1].y)) - Vector2.ONE * reach
			var hi := Vector2(maxf(pts[i].x, pts[i + 1].x), maxf(pts[i].y, pts[i + 1].y)) + Vector2.ONE * reach
			for cx in range(floori(lo.x / CELL), floori(hi.x / CELL) + 1):
				for cz in range(floori(lo.y / CELL), floori(hi.y / CELL) + 1):
					var key := Vector2i(cx, cz)
					if not _seg_cells.has(key):
						_seg_cells[key] = []
					(_seg_cells[key] as Array).append([ri, i])
	for k in pads.size():
		var pd: Dictionary = pads[k]
		var c: Vector2 = pd.c
		var rr: float = float(pd.r) + PAD_BANK + 1.0
		for cx in range(floori((c.x - rr) / CELL), floori((c.x + rr) / CELL) + 1):
			for cz in range(floori((c.y - rr) / CELL), floori((c.y + rr) / CELL) + 1):
				var key := Vector2i(cx, cz)
				if not _pad_cells.has(key):
					_pad_cells[key] = []
				(_pad_cells[key] as Array).append(k)


## Every pumpjack of the field: [{"p", "yaw", "scale", "phase", "spm", "paint", "pad"}].
func wells() -> Array:
	var out: Array = []
	for pd: Dictionary in pads:
		for w: Dictionary in pd.wells:
			var e := w.duplicate()
			e.pad = pd.id
			out.append(e)
	return out


# --- Single wells in the city ------------------------------------------------------------------------

## Share of lots in each district that are a fenced well site instead of what they would hold.
const LOT_SHARE := {CityPlan.District.INDUSTRIAL: 0.035, CityPlan.District.SUBURBS: 0.011}
## A lot this small or narrower holds no well site (a pumpjack and its fence need ~11 x 6 m).
const LOT_MIN := Vector2(13.0, 13.0)


## A lot of the city that is a well site (an industrial lot, a lot between houses): {} or
## {"p" (the pumpjack's origin), "yaw", "scale", "phase", "spm", "paint", "pad": Rect2 (the fenced
## gravel, world), "tank": bool}. Pure: a hash of seed and lot, asked after every roll. Never
## near the field (it has its own) or downtown.
static func lot_well(plan: CityPlan, lot: Dictionary, district: int) -> Dictionary:
	if not enabled or plan.macro == null or not LOT_SHARE.has(district):
		return {}
	if lot.get("yard", false) or lot.get("parking", false):
		return {}
	var size: Vector2 = lot.size
	if size.x < LOT_MIN.x or size.y < LOT_MIN.y:
		return {}
	var s: int = lot.seed
	if _h01([plan.seed, "oil_lot", s]) >= float(LOT_SHARE[district]):
		return {}
	var c: Vector2 = lot.center
	if plan.macro.oil != null and (plan.macro.oil.rect as Rect2).grow(300.0).has_point(c):
		return {}
	if plan.macro.freeway != null and plan.macro.freeway.blocks_rect(Rect2(c - size * 0.5, size), 2.0):
		return {}
	# The pumpjack along the lot's longer side, the fence a metre and a half in from the lot.
	var along_x := size.x >= size.y
	var dir := Vector2(1.0, 0.0) if along_x else Vector2(0.0, 1.0)
	if _h01([plan.seed, "oil_lot_flip", s]) < 0.5:
		dir = -dir
	var room := maxf(size.x, size.y) - 3.0
	var sc := clampf(room / (OilKit.LENGTH * 1.15), 0.62, 1.0)
	var spm := lerpf(SPM_RANGE.x, SPM_RANGE.y, _h01([plan.seed, "oil_lot_spm", s]))
	if _h01([plan.seed, "oil_lot_idle", s]) < IDLE_SHARE:
		spm = 0.0
	var p := c + dir * OilKit.LENGTH * sc * 0.42
	var pad := Rect2(c - size * 0.5, size).grow(-1.5)
	return {"p": p, "yaw": atan2(-dir.y, dir.x), "scale": sc, "phase": _h01([plan.seed, "oil_lot_phase", s]), "spm": spm,
		"paint": absi(hash([plan.seed, "oil_lot_paint", s])) % OilKit.PAINTS.size(),
		"pad": pad, "tank": minf(size.x, size.y) >= 18.0 and _h01([plan.seed, "oil_lot_tank", s]) < 0.6, "dir": dir}
