class_name LaRiver
extends RefCounted
## The Los Angeles River as its concrete flood channel (VISUAL_ROADMAP #56, 2026-10-05).
##
## A DATA TABLE and pure functions, like Freeway and ReplicaAreas: the route, its cross section,
## the land level along it, which streets bridge it and which end at the bank, where the access
## ramps, the drain outfalls, the sediment bars and the rail bridge are. RiverBuild lays a chunk's
## part of it out of these; MacroMap folds the land level into the relief (`terrace()`), CityPlan
## asks it which blocks it takes (`block_role()`) and which road segments it closes
## (`road_open()`). Every roll is a hash of the seed, never a chunk or block rng.
##
## WHERE IT RUNS. The real river runs north-south just east of downtown: out of the Glendale
## Narrows past the civic centre, under the 101, along the east edge of the Arts District with
## the arched viaducts of Cesar Chavez, 1st, 4th, 6th, 7th and Olympic over it, under the 10, then
## south through Vernon and the industrial cities to the sea at Long Beach. Downtown here is 1:1
## (DowntownReal) but the basin round it is compressed, and at 1:1 the river would stand in the
## east range (real 6th St bridge: x 5205). So the route keeps its ORDER, not its distance: east
## of Vignes by 200-650 m (the Arts District between them, the river its east edge, as it is),
## crossing the pinned real streets - so the real bridged streets bridge it here too - the 101
## near its east end, the 10 near the East LA interchange's place, the 105 where the real one
## crosses it (Lynwood), and out across the industrial south to the bay's north shore east of the
## port, which is Long Beach. The 110 never crosses the real river (it runs west of it all the way
## to San Pedro), and does not here.
##
## THE CHANNEL. A trapezoid: a concrete bed `bed_half()` either side of the centre line, banks at
## SLOPE (horizontal per vertical) up to the top `top_half()` out, a coping kerb, a maintenance
## road (BANK_ROAD) and the chain-link fence. In the middle of the bed the low-flow channel, a
## trapezoidal notch LF_DEPTH deep with a thin sheet of water in it. Real numbers: the channel by
## downtown is a 45-50 m bed in 6-7 m walls; south of the 10 it widens.
##
## THE LAND. The bed has to sit above the city's ground plane (CityStreamer's GroundBody, top y 0,
## under the whole map), so the river does not cut down into y 0: the land along it is lifted to
## the channel's top (`top_at()`), a profile smoothed along the river from the city's own rolling
## relief and never lower than the channel needs, and handed back to the relief over TERRACE_FADE
## metres either side (`terrace()`, folded into MacroMap._relief_at()). Everything the city lays
## on the relief - roads, bridges, the freeway's deck height - follows it with no code of its own.

## The route's control points in world XZ, north to south (see WHERE IT RUNS). The north end
## stands at the foot of the front range (a headwall with box culverts), the south end at the back
## of the Long Beach sand (MacroMap.bay_z - bay_beach_depth).
const CONTROL := [
	Vector2(4118.0, -2140.0), Vector2(4140.0, -1700.0), Vector2(4192.0, -1100.0),
	Vector2(4300.0, -500.0), Vector2(4452.0, 100.0), Vector2(4545.0, 700.0),
	Vector2(4595.0, 1400.0), Vector2(4602.0, 2000.0), Vector2(4560.0, 2700.0),
	Vector2(4470.0, 3500.0), Vector2(4340.0, 4400.0), Vector2(4222.0, 5300.0),
	Vector2(4150.0, 6000.0), Vector2(4138.0, 6222.0),
]
## Metres between the centre line's points, and points per coarse point (the nearest search).
const STEP := 8.0
const COARSE := 8

## The cross section, metres. North of the 10 (by downtown) the bed is BED_HALF_N either side of
## the centre and the banks DEPTH_N high; south of WIDEN_Z it eases to the wider southern channel.
const BED_HALF_N := 22.0
const BED_HALF_S := 30.0
const DEPTH_N := 6.6
const DEPTH_S := 6.2
const WIDEN_Z := 2150.0
const WIDEN_RUN := 450.0
## Bank slope, horizontal metres per metre of height (the LA River's banks are about 1.5-2 : 1).
const SLOPE := 1.6
## The bed falls this much from the bank toe to the low-flow channel's edge (it drains to it).
const BED_FALL := 0.25
## The low-flow channel: half its bottom, the run of each side, its depth, and the water in it.
const LF_BOTTOM_HALF := 1.7
const LF_SIDE := 2.6
const LF_DEPTH := 0.45
const WATER_DEPTH := 0.13
## The coping kerb on the top edge (width, height), the maintenance road, and how far past it the
## fence stands. CORRIDOR is what the top adds to `top_half()`: the river's own ground ends there.
const COPING_W := 0.5
const COPING_H := 0.42
const BANK_ROAD := 5.6
const FENCE_OUT := 0.35
const CORRIDOR := COPING_W + BANK_ROAD + FENCE_OUT + 0.45
## Metres outside the corridor over which the land level hands back to the city's relief.
const TERRACE_FADE := 170.0
## The channel's bed never lower than this over y 0 (the GroundBody's top), metres.
const MIN_BED := 0.62
## Over the last MOUTH_RUN metres the walls come down to MOUTH_DEPTH and the bed's edge (by the
## low-flow notch) to MOUTH_BED, the notch's bottom just over the sand.
const MOUTH_RUN := 420.0
const MOUTH_DEPTH := 2.3
const MOUTH_BED := 0.62

## Access ramps down a bank into the channel (RiverBuild._ramp): one about every RAMP_PITCH
## metres, RAMP_WIDTH wide, falling at RAMP_GRADE.
const RAMP_PITCH := 560.0
const RAMP_WIDTH := 5.2
const RAMP_GRADE := 0.105
## Drain outfalls: one slot every OUTFALL_PITCH metres per bank, taken at OUTFALL_ODDS (the
## concrete shader paints the same slots' stains: ihash, mirrored there).
const OUTFALL_PITCH := 46.0
const OUTFALL_ODDS := 0.42
## Sediment bars on the bed: a slot every BAR_PITCH metres, taken at BAR_ODDS.
const BAR_PITCH := 95.0
const BAR_ODDS := 0.5

## Bridge designs (RiverBridges). ARCH: a concrete open-spandrel arch viaduct with a balustrade,
## twin-lantern lamp standards and end pylons (the 1920s-30s viaducts' form). RIBBON: a white tied
## arch pair over the deck with hangers, lit along its ribs at night (the new viaduct's form).
## GIRDER: a plain concrete deck on pier bents with a barrier and cobra-head lamps. RAIL: a steel
## through plate-girder bridge carrying one freight track.
enum Bridge { ARCH, RIBBON, GIRDER, RAIL }
## The real streets the real river is bridged by, with the design here. Public street names only;
## no bridge is named anywhere.
const NAMED_BRIDGES := {
	"CESAR CHAVEZ AVE": Bridge.ARCH, "1ST ST": Bridge.ARCH, "4TH ST": Bridge.ARCH,
	"6TH ST": Bridge.RIBBON, "7TH ST": Bridge.ARCH, "OLYMPIC BLVD": Bridge.GIRDER,
	"TEMPLE ST": Bridge.GIRDER, "VENICE BLVD": Bridge.GIRDER,
}
## Share of the other crossing streets that get a bridge (a plain one); the rest end at the bank.
const OTHER_BRIDGE_ODDS := 0.16
## A street crosses at no more than this skew off square (degrees), or it ends at the bank.
const MAX_SKEW_DEG := 52.0

## Road segment states (crossings()).
enum Seg { OPEN, CLOSED, BRIDGE }

var pts := PackedVector2Array()
var dirs := PackedVector2Array()
var run := PackedFloat32Array()
var tops := PackedFloat32Array()
var length: float = 0.0
var seed: int = 0
var _macro: MacroMap
## Bounds of the whole terrace (the centre line grown by the corridor and the fade).
var bounds := Rect2()
var _coarse_z := PackedFloat32Array()

## Plan-derived tables, worked out once per plan (crossings(), bridges ...).
var _plan_id: int = -1
var _segs: Dictionary = {}
var _bridges: Array[Dictionary] = []
var _ramps: Array[Dictionary] = []
var _rail: Dictionary = {}
var _roles: Dictionary = {}


func build(macro: MacroMap, seed_value: int) -> void:
	_macro = macro
	seed = seed_value
	pts = _spline(PackedVector2Array(CONTROL))
	var n := pts.size()
	dirs.resize(n)
	run.resize(n)
	run[0] = 0.0
	for i in n:
		var a := pts[maxi(i - 1, 0)]
		var b := pts[mini(i + 1, n - 1)]
		dirs[i] = (b - a).normalized()
		if i > 0:
			run[i] = run[i - 1] + pts[i].distance_to(pts[i - 1])
	length = run[n - 1]
	_coarse_z.clear()
	for i in range(0, n, COARSE):
		_coarse_z.append(pts[i].y)
	bounds = Rect2(pts[0], Vector2.ZERO)
	for p in pts:
		bounds = bounds.expand(p)
	bounds = bounds.grow(BED_HALF_S + DEPTH_S * SLOPE + CORRIDOR + TERRACE_FADE + 10.0)
	_profile()


## A smooth centre line through the control points, resampled every STEP metres (centripetal
## Catmull-Rom, as Freeway._spline(), at the river's own step).
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
		var m := maxi(4, int(p1.distance_to(p2) / 2.0))
		for k in m:
			var t := lerpf(t1, t2, float(k) / float(m))
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
	if out[out.size() - 1].distance_to(fine[fine.size() - 1]) > STEP * 0.3:
		out.append(fine[fine.size() - 1])
	return out


## The land level along the river: the city's relief under the centre line, smoothed over a few
## hundred metres, never lower than the channel needs, the bed falling (never rising) downstream,
## and the last MOUTH_RUN metres let down to the sand.
func _profile() -> void:
	var n := pts.size()
	var raw := PackedFloat32Array()
	raw.resize(n)
	for i in n:
		raw[i] = _macro._relief_at(pts[i], _macro.raw_height_at(pts[i]))
	# Smooth: a running mean over +-25 points (+-200 m), twice.
	for pass_i in 2:
		var src := raw.duplicate()
		for i in n:
			var sum := 0.0
			var c := 0
			for k in range(maxi(0, i - 25), mini(n, i + 26)):
				sum += src[k]
				c += 1
			raw[i] = sum / float(c)
	tops.resize(n)
	var bed_prev := INF
	for i in n:
		var s := run[i]
		var d := depth(s)
		var bed := maxf(raw[i] - d - BED_FALL, MIN_BED)
		# Downstream the bed only falls.
		bed = minf(bed, bed_prev)
		bed_prev = bed
		tops[i] = bed + BED_FALL + d
	# The mouth: the bed eased down to the sand, the walls to MOUTH_DEPTH (depth() tapers them).
	for i in n:
		var s := run[i]
		var t := smoothstep(length - MOUTH_RUN, length, s)
		if t <= 0.0:
			continue
		var bed := tops[i] - depth(s) - BED_FALL
		var low := lerpf(bed, MOUTH_BED, t)
		tops[i] = low + BED_FALL + depth(s)


# --- The cross section ---------------------------------------------------------------------------

func _widen(s: float) -> float:
	var p := at(s)[0] as Vector2
	return smoothstep(WIDEN_Z, WIDEN_Z + WIDEN_RUN, p.y)


## Half the bed's width at `s` metres down the river (to the bank toes).
func bed_half(s: float) -> float:
	return lerpf(BED_HALF_N, BED_HALF_S, _widen(s))


## Bank height (toe to top edge) at `s`.
func depth(s: float) -> float:
	var d := lerpf(DEPTH_N, DEPTH_S, _widen(s))
	return lerpf(d, MOUTH_DEPTH, smoothstep(length - MOUTH_RUN, length, s))


## Half the channel's width at its top edge.
func top_half(s: float) -> float:
	return bed_half(s) + depth(s) * SLOPE


## Half the river's whole corridor (channel, coping, bank road, fence): the city ends here.
func corridor_half(s: float) -> float:
	return top_half(s) + CORRIDOR


## Half the low-flow channel's width at the bed.
static func lf_half() -> float:
	return LF_BOTTOM_HALF + LF_SIDE


## [Vector2 point, Vector2 direction] `s` metres down the centre line (clamped).
func at(s: float) -> Array:
	var i := _index_at(s)
	var f := clampf((s - run[i]) / maxf(run[i + 1] - run[i], 0.001), 0.0, 1.0)
	return [pts[i].lerp(pts[i + 1], f), dirs[i].lerp(dirs[i + 1], f).normalized()]


func _index_at(s: float) -> int:
	var lo := 0
	var hi := run.size() - 1
	while hi - lo > 1:
		var mid := (lo + hi) / 2
		if run[mid] <= s:
			lo = mid
		else:
			hi = mid
	return lo


## The land level (the channel's top edge and the ground round it) at `s`.
func top_at(s: float) -> float:
	var i := _index_at(s)
	var f := clampf((s - run[i]) / maxf(run[i + 1] - run[i], 0.001), 0.0, 1.0)
	return lerpf(tops[i], tops[i + 1], f)


## The bed at the bank toe (the bed falls BED_FALL from there to the low-flow channel's edge).
func toe_at(s: float) -> float:
	return top_at(s) - depth(s)


## The channel's surface at lateral offset `o` (metres from the centre line) at `s`: the low-flow
## channel, the bed, the bank; the top level outside the channel.
func surface(s: float, o: float) -> float:
	var a := absf(o)
	var top := top_at(s)
	var toe := top - depth(s)
	var bh := bed_half(s)
	var lf := lf_half()
	if a >= top_half(s):
		return top
	if a >= bh:
		return lerpf(toe, top, (a - bh) / (top_half(s) - bh))
	var edge := toe - BED_FALL
	if a >= lf:
		return lerpf(edge, toe, (a - lf) / (bh - lf))
	if a >= LF_BOTTOM_HALF:
		return lerpf(edge - LF_DEPTH, edge, (a - LF_BOTTOM_HALF) / LF_SIDE)
	return edge - LF_DEPTH


## The water's surface at `s` (the low-flow channel's sheet).
func water_at(s: float) -> float:
	return top_at(s) - depth(s) - BED_FALL - LF_DEPTH + WATER_DEPTH


# --- Where things are relative to it -------------------------------------------------------------

## Nearest point of the centre line to world XZ `pos`, if within `reach`:
## Vector4(s, o, distance, 1) - `o` is the signed lateral offset (positive to the left of the flow,
## which runs south, so west) - or Vector4(0, 0, INF, 0).
func nearest(pos: Vector2, reach: float) -> Vector4:
	if pts.size() < 2:
		return Vector4(0.0, 0.0, INF, 0.0)
	# The route runs south all the way (checked), so the coarse points are sorted by z.
	var lo := 0
	var hi := _coarse_z.size() - 1
	var z := pos.y - reach - float(COARSE) * STEP
	while hi - lo > 1:
		var mid := (lo + hi) / 2
		if _coarse_z[mid] < z:
			lo = mid
		else:
			hi = mid
	var best_c := -1
	var best_d := INF
	var c := lo
	var n := pts.size()
	while c < _coarse_z.size():
		if _coarse_z[c] > pos.y + reach + float(COARSE) * STEP:
			break
		var d := pos.distance_squared_to(pts[mini(c * COARSE, n - 1)])
		if d < best_d:
			best_d = d
			best_c = c
		c += 1
	if best_c < 0 or sqrt(best_d) > reach + float(COARSE) * STEP:
		return Vector4(0.0, 0.0, INF, 0.0)
	var i0 := maxi(0, (best_c - 1) * COARSE)
	var i1 := mini(n - 1, (best_c + 1) * COARSE)
	var bi := -1
	var bt := 0.0
	var bd := INF
	for i in range(i0, i1):
		var a := pts[i]
		var ab := pts[i + 1] - a
		var t := clampf((pos - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		var d := pos.distance_squared_to(a + ab * t)
		if d < bd:
			bd = d
			bi = i
			bt = t
	if bi < 0 or sqrt(bd) > reach:
		return Vector4(0.0, 0.0, INF, 0.0)
	var a2 := pts[bi]
	var ab2 := pts[bi + 1] - a2
	var foot := a2 + ab2 * bt
	var nrm := Vector2(-ab2.y, ab2.x).normalized()
	var s := run[bi] + (run[bi + 1] - run[bi]) * bt
	var o := (pos - foot).dot(nrm)
	# Past either end the offset is not lateral; the distance carries it.
	return Vector4(s, o, sqrt(bd), 1.0)


## The land level and how much of it the relief takes at `pos`: Vector2(level, weight), weight 1
## inside the corridor, falling to 0 over TERRACE_FADE outside it, and over the same distance past
## either end. MacroMap._relief_at() blends the city's relief toward it.
func terrace(pos: Vector2) -> Vector2:
	if not bounds.has_point(pos):
		return Vector2.ZERO
	var reach := BED_HALF_S + DEPTH_S * SLOPE + CORRIDOR + TERRACE_FADE
	var nr := nearest(pos, reach)
	if nr.w < 0.5:
		return Vector2.ZERO
	var ch := corridor_half(nr.x)
	var w := 1.0 - smoothstep(ch + 4.0, ch + TERRACE_FADE, nr.z)
	return Vector2(top_at(nr.x), w)


## True where world XZ `pos` is inside the river's corridor (its half width plus `pad`), between
## its ends.
func in_corridor(pos: Vector2, pad: float = 0.0) -> bool:
	if not bounds.has_point(pos):
		return false
	var nr := nearest(pos, BED_HALF_S + DEPTH_S * SLOPE + CORRIDOR + pad + 2.0)
	if nr.w < 0.5 or nr.x <= 0.01 or nr.x >= length - 0.01:
		return false
	return absf(nr.y) < corridor_half(nr.x) + pad


## The channel's surface under world XZ `pos` when it is inside the channel's opening (between the
## top edges), else INF: what a freeway bent standing in the river reaches down to.
func channel_floor(pos: Vector2) -> float:
	if not bounds.has_point(pos):
		return INF
	var nr := nearest(pos, BED_HALF_S + DEPTH_S * SLOPE + 4.0)
	if nr.w < 0.5 or nr.x <= 0.01 or nr.x >= length - 0.01:
		return INF
	if absf(nr.y) >= top_half(nr.x):
		return INF
	return surface(nr.x, nr.y)


## Metres between the centre line and a world rect (0 where it crosses it), within `reach`.
func rect_distance(r: Rect2, reach: float) -> float:
	if not bounds.grow(reach).intersects(r):
		return INF
	var best := INF
	var i0 := _first_index_z(r.position.y - reach - STEP)
	for i in range(i0, pts.size() - 1):
		if pts[i].y > r.end.y + reach + STEP:
			break
		best = minf(best, Freeway.segment_rect_distance(pts[i], pts[i + 1], r))
	return best


## The first point index whose z is at or past `z` (the route runs south).
func _first_index_z(z: float) -> int:
	var lo := 0
	var hi := pts.size() - 1
	if pts[0].y >= z:
		return 0
	while hi - lo > 1:
		var mid := (lo + hi) / 2
		if pts[mid].y < z:
			lo = mid
		else:
			hi = mid
	return lo


## Point indices [i0, i1] whose segments may reach a world rect within `reach`.
func index_range(r: Rect2, reach: float) -> Vector2i:
	var i0 := maxi(0, _first_index_z(r.position.y - reach) - 1)
	var i1 := i0
	while i1 < pts.size() - 1 and pts[i1].y < r.end.y + reach:
		i1 += 1
	return Vector2i(i0, mini(i1 + 1, pts.size() - 1))


## The band between lateral offsets `o0` and `o1` (o0 < o1; each a Callable s -> offset or a
## float) over point indices i0..i1, as one polygon in world XZ.
func band(i0: int, i1: int, o0: Variant, o1: Variant) -> PackedVector2Array:
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	for i in range(i0, i1 + 1):
		var s := run[i]
		var nrm := Vector2(-dirs[i].y, dirs[i].x)
		var a: float = o0.call(s) if o0 is Callable else float(o0)
		var b: float = o1.call(s) if o1 is Callable else float(o1)
		left.append(pts[i] + nrm * b)
		right.append(pts[i] + nrm * a)
	right.reverse()
	left.append_array(right)
	return left


## A point at `s` down the river and `o` across it (world XZ).
func point(s: float, o: float) -> Vector2:
	var pd := at(s)
	var d: Vector2 = pd[1]
	return (pd[0] as Vector2) + Vector2(-d.y, d.x) * o


# --- Hashes ---------------------------------------------------------------------------------------

## A 32-bit integer hash (Wellons' lowbias32), the same arithmetic as shaders/river_concrete
## .gdshader's ihash(): what lets the script know where the shader paints an outfall's stain.
static func ihash(x: int) -> int:
	x = x & 0xFFFFFFFF
	x ^= x >> 16
	x = (x * 0x7feb352d) & 0xFFFFFFFF
	x ^= x >> 15
	x = (x * 0x846ca68b) & 0xFFFFFFFF
	x ^= x >> 16
	return x


static func ihash01(x: int) -> float:
	return float(ihash(x) & 0xFFFFFF) / 16777216.0


## A seed-mixed hash in 0..1 of any parts.
func h01(parts: Array) -> float:
	return float(absi(hash([seed, "la_river"] + parts)) % 100003) / 100003.0


## Outfall slot `k` on side `side` (0 west, 1 east): taken? (The shader runs the same test on
## the bank's s with seed 0: the slots do not move with the seed, the stains are the street's.)
static func outfall_at(k: int, side: int) -> bool:
	return ihash01(k * 2 + side + 7919) < OUTFALL_ODDS


## Sediment bars over [s0, s1): [{"s0", "s1", "side" (+1 west / -1 east of the low flow),
## "width"}], hashed per slot, kept off the bridges' piers and the ramps' feet by the builder.
func bars_in(s0: float, s1: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for k in range(floori(s0 / BAR_PITCH) - 1, ceili(s1 / BAR_PITCH) + 1):
		if h01(["bar", k]) >= BAR_ODDS:
			continue
		var a := (float(k) + h01(["bar_at", k]) * 0.4) * BAR_PITCH
		var l := lerpf(22.0, 60.0, h01(["bar_len", k]))
		if a + l < s0 or a >= s1 or a < 120.0 or a + l > length - MOUTH_RUN:
			continue
		out.append({"s0": a, "s1": a + l, "side": 1.0 if h01(["bar_side", k]) < 0.5 else -1.0,
			"width": lerpf(4.0, 11.0, h01(["bar_w", k])), "k": k})
	return out


# --- The street grid ------------------------------------------------------------------------------

func _ensure(plan: CityPlan) -> void:
	if _plan_id == plan.get_instance_id():
		return
	_plan_id = plan.get_instance_id()
	_segs.clear()
	_roles.clear()
	_bridges.clear()
	_ramps.clear()
	_rail = {}
	_classify(plan)
	_place_ramps(plan)
	_place_rail(plan)


## Every road segment near the river: OPEN (it does not come near), CLOSED (it ends at the bank)
## or BRIDGE (it crosses on a bridge). Keyed Vector3i(axis, road index, segment index) - segment
## j of a road runs between crossing roads j and j + 1.
func _classify(plan: CityPlan) -> void:
	var reach := BED_HALF_S + DEPTH_S * SLOPE + CORRIDOR
	var area := Rect2(pts[0], Vector2.ZERO)
	for p in pts:
		area = area.expand(p)
	area = area.grow(reach + 140.0)
	for axis in 2:
		var other := 1 - axis
		var k0 := plan._index_at(axis, area.position[axis])
		var k1 := plan._index_at(axis, area.end[axis]) + 1
		var j0 := plan._index_at(other, area.position[other])
		var j1 := plan._index_at(other, area.end[other]) + 1
		for k in range(k0, k1 + 1):
			var c := plan.road_pos(axis, k)
			var w := plan.road_width(axis, k)
			# The road's segments that reach the corridor, in runs of consecutive ones: a run is
			# one crossing (the roads between its segments run along the river and are closed).
			var runs: Array = []
			for j in range(j0, j1):
				# The segment with the junction squares at both its ends: a junction the corridor
				# reaches takes both its segments into the crossing.
				var a := plan.road_pos(other, j) - plan.road_width(other, j) * 0.5
				var b := plan.road_pos(other, j + 1) + plan.road_width(other, j + 1) * 0.5
				var r := _seg_rect(axis, c, w, a, b)
				var hc := corridor_half(clampf(nearest(r.get_center(), 1e6).x, 0.0, length))
				if rect_distance(r, hc + 1.0) > hc:
					continue
				if not runs.is_empty() and int((runs.back() as Array).back()) == j - 1:
					(runs.back() as Array).append(j)
				else:
					runs.append([j])
			for rn: Array in runs:
				var ja: int = rn[0]
				var jb: int = rn.back()
				var a := plan.road_pos(other, ja) - plan.road_width(other, ja) * 0.5
				var b := plan.road_pos(other, jb + 1) + plan.road_width(other, jb + 1) * 0.5
				var br := _bridge_for(plan, axis, k, ja, c, w, a, b)
				for j: int in rn:
					_segs[Vector3i(axis, k, j)] = Seg.CLOSED if br.is_empty() else Seg.BRIDGE
				if not br.is_empty():
					br["segs"] = rn
					_bridges.append(br)


static func _seg_rect(axis: int, c: float, w: float, a: float, b: float) -> Rect2:
	if axis == CityPlan.AXIS_X:
		return Rect2(c - w * 0.5, a, w, b - a)
	return Rect2(a, c - w * 0.5, b - a, w)


## The bridge carrying road segment (axis, k, j) over the river, or {} when it cannot have one
## (it runs along the river, crosses too skewed, an end of it is in the corridor, it is past the
## river's ends) or the roll says it ends at the bank.
func _bridge_for(plan: CityPlan, axis: int, k: int, j: int, c: float, w: float, a: float, b: float) -> Dictionary:
	var along := Vector2(0.0, 1.0) if axis == CityPlan.AXIS_X else Vector2(1.0, 0.0)
	var p0 := Vector2(c, a) if axis == CityPlan.AXIS_X else Vector2(a, c)
	var p1 := Vector2(c, b) if axis == CityPlan.AXIS_X else Vector2(b, c)
	# Where the road's centre line crosses the river's: once, or no bridge.
	var hits: Array = []
	var i0 := _first_index_z(minf(p0.y, p1.y) - STEP * 2.0)
	for i in range(maxi(0, i0 - 1), pts.size() - 1):
		if pts[i].y > maxf(p0.y, p1.y) + STEP * 2.0:
			break
		var x: Variant = Geometry2D.segment_intersects_segment(p0, p1, pts[i], pts[i + 1])
		if x != null:
			hits.append([x, i])
	if hits.size() != 1:
		return {}
	var hp: Vector2 = hits[0][0]
	var hi: int = hits[0][1]
	var s := run[hi] + pts[hi].distance_to(hp)
	if s < 160.0 or s > length - MOUTH_RUN - 60.0:
		return {}
	var skew := rad_to_deg(acos(clampf(absf(along.dot(Vector2(-dirs[hi].y, dirs[hi].x))), 0.0, 1.0)))
	if skew > MAX_SKEW_DEG:
		return {}
	if _macro.zone_at(hp) != MacroMap.Zone.CITY:
		return {}
	# Both ends (the intersections) clear of the corridor.
	var hc := corridor_half(s)
	for e: Vector2 in [p0, p1]:
		var nr := nearest(e, hc + 40.0)
		if nr.w > 0.5 and absf(nr.y) < hc + 3.0:
			return {}
	var name := plan.road_name(axis, k)
	var kind := -1
	if NAMED_BRIDGES.has(name) and DowntownReal.named(axis, name).size() > 0:
		kind = int(NAMED_BRIDGES[name])
	elif w >= plan.avenue_width - 0.1 and h01(["avenue_bridge", axis, k]) < 0.55:
		kind = Bridge.GIRDER if h01(["avenue_kind", axis, k]) < 0.5 else Bridge.ARCH
	elif h01(["bridge", axis, k, j]) < OTHER_BRIDGE_ODDS:
		kind = Bridge.GIRDER
	if kind < 0:
		return {}
	# A bridge under a freeway deck is a plain one (no pylons or arches into the deck).
	if _macro.freeway and _macro.freeway.blocks(hp, 30.0):
		kind = Bridge.GIRDER
	# The span: where the road's centre line meets the channel's top edges (+ a metre each side).
	var t_hit := (hp - p0).dot(along)
	var span := _span_along(p0, along, t_hit, b - a, s)
	return {
		"kind": kind, "axis": axis, "index": k, "seg": j, "c": c, "width": w, "along": along,
		"p": hp, "s": s, "skew": skew, "t0": span.x, "t1": span.y, "p0": p0, "name": name,
		"dir": dirs[hi], "owner": plan.chunk_index_at(hp),
	}


## Along a road line (from `p0`, direction `along`, `len` metres), the interval round `t_hit` where
## the road is over the channel's opening, widened a metre each side: Vector2(t0, t1).
func _span_along(p0: Vector2, along: Vector2, t_hit: float, len: float, s_hit: float) -> Vector2:
	var out := Vector2(t_hit, t_hit)
	for dirn: float in [-1.0, 1.0]:
		var t := t_hit
		while t > 0.0 and t < len:
			var nr := nearest(p0 + along * t, top_half(s_hit) * 3.0)
			if nr.w < 0.5 or absf(nr.y) > top_half(nr.x) + COPING_W:
				break
			t += dirn * 0.5
		if dirn < 0.0:
			out.x = t - 0.5
		else:
			out.y = t + 0.5
	return out


## Whether road segment (axis, index) is open at `along` (CityPlan.road_open()).
func road_open(plan: CityPlan, axis: int, index: int, along: float) -> bool:
	var c := plan.road_pos(axis, index)
	if axis == CityPlan.AXIS_X:
		if c < bounds.position.x or c > bounds.end.x:
			return true
	elif c < bounds.position.y or c > bounds.end.y:
		return true
	_ensure(plan)
	if _segs.is_empty():
		return true
	var j := plan._index_at(1 - axis, along)
	return int(_segs.get(Vector3i(axis, index, j), Seg.OPEN)) != Seg.CLOSED


## The state of road segment (axis, index, seg).
func segment(plan: CityPlan, axis: int, index: int, seg: int) -> int:
	_ensure(plan)
	return int(_segs.get(Vector3i(axis, index, seg), Seg.OPEN))


## 1 when chunk (ix, iz)'s area (its block and its +X / +Z roads) reaches the river's corridor:
## the chunk builds the river's ground in place of the seeded block (RiverBuild). 0 otherwise.
func block_role(plan: CityPlan, ix: int, iz: int) -> int:
	var key := Vector2i(ix, iz)
	if _roles.has(key):
		return _roles[key]
	var r := plan.owned_rect(ix, iz)
	var role := 0
	if bounds.intersects(r):
		var reach := BED_HALF_S + DEPTH_S * SLOPE + CORRIDOR + 2.0
		var d := rect_distance(r, reach)
		if d < reach:
			# Exact: some point of the rect inside the corridor (the corridor is narrower to the
			# north than `reach`).
			role = 1 if _rect_in_corridor(r) else 0
	_roles[key] = role
	return role


func _rect_in_corridor(r: Rect2) -> bool:
	var ir := index_range(r, BED_HALF_S + DEPTH_S * SLOPE + CORRIDOR + 4.0)
	for i in range(ir.x, ir.y + 1):
		var s := run[i]
		if s <= 0.01 or s >= length - 0.01:
			continue
		var h := corridor_half(s) + 1.0
		var poly := band(maxi(ir.x, i - 1), mini(ir.y, i + 1), -h, h)
		var rect_poly := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
		if not Geometry2D.intersect_polygons(poly, rect_poly).is_empty():
			return true
	return false


## Every street bridge: [{"kind", "axis", "index", "seg", "c", "width", "along", "p", "s", "skew",
## "t0", "t1", "p0", "name", "dir", "owner"}].
func bridges(plan: CityPlan) -> Array[Dictionary]:
	_ensure(plan)
	return _bridges


## Access ramps: [{"s0", "s1" (top end and foot, s0 < s1 or the reverse: the ramp falls from s0 to
## s1), "side" (+1 west, -1 east), "owner"}].
func ramps(plan: CityPlan) -> Array[Dictionary]:
	_ensure(plan)
	return _ramps


## The rail bridge: {"s", "p", "dir" (along the track), "half" (track half length), "owner"}, or
## {} when no spot was found.
func rail_bridge(plan: CityPlan) -> Dictionary:
	_ensure(plan)
	return _rail


## Ramps every RAMP_PITCH metres, alternating banks, each kept clear of the bridges and of
## freeway bents in the channel.
func _place_ramps(plan: CityPlan) -> void:
	var k := 0
	var s := 260.0
	while s < length - MOUTH_RUN - 120.0:
		var side := 1.0 if (k + int(h01(["ramp_side"]) * 2.0)) % 2 == 0 else -1.0
		var fall := depth(s) / RAMP_GRADE
		var down := 1.0 if h01(["ramp_dir", k]) < 0.5 else -1.0
		var s0 := s
		var s1 := s + fall * down
		var lo := minf(s0, s1) - 14.0
		var hi := maxf(s0, s1) + 14.0
		var ok := lo > 80.0 and hi < length - MOUTH_RUN
		for br in _bridges:
			if float(br.s) > lo - 30.0 and float(br.s) < hi + 30.0:
				ok = false
		if ok and _macro.freeway:
			var m := 0.0
			while m <= 1.0:
				if _macro.freeway.blocks(point(lerpf(lo, hi, m), side * top_half(s)), 6.0):
					ok = false
				m += 0.1
		if ok:
			var mid := point((s0 + s1) * 0.5, side * top_half(s))
			_ramps.append({"s0": s0, "s1": s1, "side": side, "owner": plan.chunk_index_at(mid), "k": k})
			k += 1
			s += RAMP_PITCH * lerpf(0.85, 1.2, h01(["ramp_gap", k]))
		else:
			s += 40.0


## One freight rail bridge, square across the river, at the first spot from a hashed start where
## its track (the channel and RAIL_REACH beyond each top edge) keeps clear of every road and of the
## freeway, on city ground.
const RAIL_REACH := CORRIDOR + 9.0
func _place_rail(plan: CityPlan) -> void:
	var start := lerpf(900.0, 2200.0, h01(["rail_at"]))
	var s := start
	while s < length - MOUTH_RUN - 200.0:
		var pd := at(s)
		var p: Vector2 = pd[0]
		var d: Vector2 = pd[1]
		var across := Vector2(-d.y, d.x)
		var half := top_half(s) + RAIL_REACH
		var ok := _macro.zone_at(p) == MacroMap.Zone.CITY
		for br in _bridges:
			if absf(float(br.s) - s) < 90.0:
				ok = false
		for rp in _ramps:
			if s > minf(rp.s0, rp.s1) - 30.0 and s < maxf(rp.s0, rp.s1) + 30.0:
				ok = false
		if ok:
			var m := -1.0
			while m <= 1.0:
				var q := p + across * half * m
				var kq := plan.chunk_index_at(q)
				if _on_road(plan, q, 4.0) or block_role(plan, kq.x, kq.y) == 0 \
						or (_macro.freeway and _macro.freeway.blocks(q, 12.0)):
					ok = false
					break
				m += 0.05
		if ok:
			_rail = {"s": s, "p": p, "dir": across, "half": half, "owner": plan.chunk_index_at(p), "flow": d}
			return
		s += 23.0


## True when world XZ `q` is on (or within `pad` of) any road strip.
func _on_road(plan: CityPlan, q: Vector2, pad: float) -> bool:
	for axis in 2:
		var k := plan._index_at(axis, q[axis])
		for kk: int in [k, k + 1]:
			if absf(q[axis] - plan.road_pos(axis, kk)) < plan.road_width(axis, kk) * 0.5 + pad \
					and plan.road_open(axis, kk, q[1 - axis]):
				return true
	return false
