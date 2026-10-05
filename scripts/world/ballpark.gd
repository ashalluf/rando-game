class_name Ballpark
extends RefCounted
## THE BALLPARK IN THE RAVINE (2026-10-05, "a baseball stadium in a ravine north of downtown"):
## the FORM of Los Angeles' famous hillside ballpark in its real relation to downtown, with every
## name invented (no team, no sponsor, no logo; the park is SUNRIDGE BALLPARK). This file is the
## DATA - where it stands, its frame, the field's real dimensions, the tiers, the pad and the
## terraces the hills are cut to, the access roads - and the carve MacroMap applies; the meshes
## are BallparkBuild.
##
## WHERE. Home plate's real point (34.07328, -118.24065) goes through DowntownReal.game_xz(): it
## lands 2.9 km grid-north and 0.8 km grid-west of Pershing Square, on the low embayed front range
## (MacroMap.embay_*: the Elysian hills) above the 110 / 101 junction, between downtown and the
## valley plateau. The real field faces north-north-east (home to centre field at a compass 31
## degrees); after the grid's turn that is game north, 6.4 degrees west. 1:1, like downtown: the
## field, the stands and the lots at true size, at the true distance from downtown.
##
## THE FRAME. Local (u, v): v from home plate toward centre field (`FWD`), u to the right of a
## batter looking out (`RIGHT`, the first-base side, game east). world(u, v) = HOME + RIGHT u + FWD v.
##
## THE GROUND. The real park sits in a ravine cut into the hills, its lots on terraces at the level
## of the tiers they serve, planted embankments with palms between them. Here: the lower pad at
## `PAD_Y` (the field, the plaza, the outfield lots) and the upper terrace `TERRACE_RISE` higher
## (the loge-level lots behind home and down the lines), joined by a planted slope; outside the
## site the hills are cut back at 1:1 and filled at 1:1.5 (carve()). The pad height is fixed, not
## read off the seed's terrain, so the stadium, its far copy and the checks agree on every seed.
##
## THE ROADS. Two, registered with HillRoads (so the hill chunks draw their asphalt, carve their
## beds, and keep planting off them): the north drive to the valley floor, and Stadium Way
## switchbacking down the south face to Hill St at downtown's north edge.

## Home plate (world XZ) and the unit direction toward centre field: DowntownReal.game_xz of the
## real home plate and centre field points, rounded.
const HOME := Vector2(2008.0, -2778.0)
const FWD := Vector2(-0.1117, -0.9937)
const RIGHT := Vector2(0.9937, -0.1117)

## The lower pad's elevation (metres): field, plaza, outfield lots. The upper terrace stands
## TERRACE_RISE over it: the loge concourse, where the bridges come in.
const PAD_Y := 142.0
const TERRACE_RISE := 22.0
## The terrace: everything at least TERRACE_R metres from TERRACE_C (local u, v) and on the home
## side of v TERRACE_V0 .. TERRACE_V1, up a planted slope SLOPE_RUN metres wide.
const TERRACE_C := Vector2(0.0, 15.0)
const TERRACE_R := 140.0
const SLOPE_RUN := 33.0
const TERRACE_V0 := -25.0
const TERRACE_V1 := 25.0
## The site: a rounded rectangle in local (u, v), corner radius SITE_CORNER.
const SITE_U := 290.0
const SITE_V0 := -260.0
const SITE_V1 := 330.0
const SITE_CORNER := 70.0
## Outside the site: cut banks 1:1, fill banks 1:1.5, rolled in over BANK_SHOULDER, handed back
## to the hills by BANK_REACH.
const CUT_SLOPE := 1.0
const FILL_SLOPE := 0.67
const BANK_SHOULDER := 8.0
const BANK_REACH := 170.0

## The field (metres, real): 90 ft bases, 60 ft 6 in to the rubber, the mound 18 ft across,
## the infield arc 95 ft from the rubber, 330 ft down the lines, 375 in the alleys, 395 to centre.
const BASE := 27.432
const RUBBER := 18.44
const MOUND_R := 2.74
const ARC_R := 28.96
const FENCE_LINE := 100.6
const FENCE_ALLEY := 114.3
const FENCE_CENTER := 120.4
const FENCE_H := 2.6
const TRACK := 4.6
## The backstop and the stands' front, out from the foul lines and round behind home (the real
## backstop is 55 ft).
const FRONT := 16.8

## The four tiers, low to high: front offset from the foul lines (D), front height over the field,
## rows, row depth and rise, how far down the lines the tier runs (metres from home along the
## line), its seat colour (sRGB: yellow field level, orange loge, turquoise reserve, sky-blue top
## deck - the real park's pastel bands), and how full it is.
const TIERS := [
	{"name": "field", "d": FRONT, "y": 1.2, "rows": 28, "depth": 0.82, "rise": 0.34, "end": 96.0, "seat": Color(0.93, 0.78, 0.25), "fill": 0.86},
	{"name": "loge", "d": 34.0, "y": 13.0, "rows": 20, "depth": 0.86, "rise": 0.46, "end": 84.0, "seat": Color(0.92, 0.52, 0.22), "fill": 0.8},
	{"name": "reserve", "d": 47.0, "y": 25.5, "rows": 22, "depth": 0.86, "rise": 0.5, "end": 76.0, "seat": Color(0.25, 0.68, 0.7), "fill": 0.72},
	{"name": "top", "d": 62.0, "y": 39.0, "rows": 22, "depth": 0.86, "rise": 0.55, "end": 62.0, "seat": Color(0.38, 0.62, 0.86), "fill": 0.55},
]
## The concourse behind each tier's last row, and the deck's underside below its front.
const CONCOURSE := 6.0
const FASCIA := 1.6
## The pavilions past the fence, left and right field: from FENCE angle PAV_A0 to PAV_A1 (degrees
## off the centre line), PAV_ROWS rows from PAV_Y over the fence's foot.
const PAV_A0 := 17.0
const PAV_A1 := 43.5
const PAV_ROWS := 26
const PAV_DEPTH := 0.8
const PAV_RISE := 0.42
const PAV_Y := 3.4
const PAV_GAP := 3.0
## The scoreboards: a stretched hexagon over the back of each pavilion (the left one bigger).
const BOARD_W := Vector2(32.0, 26.0)
const BOARD_H := Vector2(12.0, 10.0)

## Where the landmark's entry anchors (the bowl's middle): the chunk this falls in builds the
## detailed park.
static func anchor() -> Vector2:
	return world(0.0, 20.0)


static func entry() -> Dictionary:
	# Radius: the bowl. It is what keeps a hill chunk's shells off the stadium and the relief
	# flat; the pad and the lots are kept clear by covers() / shell_marks().
	return {"id": "ballpark", "anchor": anchor(), "radius": 140.0}


# --- The frame -----------------------------------------------------------------------------

static func world(u: float, v: float) -> Vector2:
	return HOME + RIGHT * u + FWD * v


static func world3(u: float, v: float, y: float) -> Vector3:
	var p := world(u, v)
	return Vector3(p.x, y, p.y)


static func local(p: Vector2) -> Vector2:
	var q := p - HOME
	return Vector2(q.dot(RIGHT), q.dot(FWD))


## The outfield fence's distance from home at `deg` degrees off the centre line (+ toward right
## field): 330 down the lines, 375 in the alleys, 395 to centre, the alleys rounded.
static func fence_r(deg: float) -> float:
	var a := clampf(absf(deg), 0.0, 45.0)
	if a <= 22.5:
		var t := a / 22.5
		return lerpf(FENCE_CENTER, FENCE_ALLEY, t * t)
	var t2 := (a - 22.5) / 22.5
	return lerpf(FENCE_ALLEY, FENCE_LINE, t2 * (0.6 + 0.4 * t2))


# --- The ground ------------------------------------------------------------------------------

## Signed distance (metres) from local `q` to the site's outline, negative inside.
static func site_sd(q: Vector2) -> float:
	var c := Vector2(0.0, (SITE_V0 + SITE_V1) * 0.5)
	var half := Vector2(SITE_U, (SITE_V1 - SITE_V0) * 0.5) - Vector2.ONE * SITE_CORNER
	var d := (q - c).abs() - half
	return Vector2(maxf(d.x, 0.0), maxf(d.y, 0.0)).length() + minf(maxf(d.x, d.y), 0.0) - SITE_CORNER


## 0 on the lower pad, 1 on the upper terrace, between on the planted slope (local `q`).
static func terrace_t(q: Vector2) -> float:
	var tr := clampf((q.distance_to(TERRACE_C) - TERRACE_R) / SLOPE_RUN, 0.0, 1.0)
	var tv := clampf((TERRACE_V1 - q.y) / (TERRACE_V1 - TERRACE_V0), 0.0, 1.0)
	return tr * tv


## The site's finished ground at local `q` (inside the outline).
static func level(q: Vector2) -> float:
	return PAD_Y + TERRACE_RISE * terrace_t(q)


## True when world XZ `p` is on the site (its outline grown by `margin`): nothing of the hills'
## own planting, scatter or shells goes there.
static func covers(p: Vector2, margin: float = 0.0) -> bool:
	if not enabled():
		return false
	var q := local(p)
	if absf(q.x) > SITE_U + margin + 1.0 or q.y < SITE_V0 - margin - 1.0 or q.y > SITE_V1 + margin + 1.0:
		return false
	return site_sd(q) < margin


## The ground with the site cut in: `h` is the natural height at world `p`. Inside the outline the
## site's level; outside, the hills cut back at CUT_SLOPE (filled at FILL_SLOPE) from the level at
## the nearest edge, rolled in over BANK_SHOULDER and handed back to the hills by BANK_REACH.
static func carve(p: Vector2, h: float) -> float:
	if _enabled == 0:
		return h
	var q := local(p)
	if absf(q.x) > SITE_U + BANK_REACH or q.y < SITE_V0 - BANK_REACH or q.y > SITE_V1 + BANK_REACH:
		return h
	var e := site_sd(q)
	if e >= BANK_REACH:
		return h
	if e <= 0.0:
		return level(q)
	# The level at the nearest point of the outline: walk back along the outline's gradient.
	var g := Vector2(site_sd(q + Vector2(0.5, 0.0)) - site_sd(q - Vector2(0.5, 0.0)), site_sd(q + Vector2(0.0, 0.5)) - site_sd(q - Vector2(0.0, 0.5)))
	var edge := q - g.normalized() * e if g.length_squared() > 1e-6 else q
	var bed := level(edge)
	var dh := h - bed
	var reach := (CUT_SLOPE if dh > 0.0 else FILL_SLOPE) * e
	var off := minf(absf(dh), reach)
	off = minf(off, absf(dh) * smoothstep(0.0, BANK_SHOULDER, e))
	off = lerpf(off, absf(dh), smoothstep(BANK_REACH - 20.0, BANK_REACH, e))
	return bed + signf(dh) * off


## Capsules ([a, b, reach], world XZ) covering the site, for the hill shells' keep-out
## (CityChunk._shell_marks). Rows along u, every 60 m of v.
static func shell_marks(area: Rect2) -> Array:
	var out: Array = []
	if not enabled():
		return out
	var probe := area.grow(SITE_U + 40.0)
	if not probe.has_point(anchor()):
		return out
	var v := SITE_V0 + 30.0
	while v < SITE_V1:
		var half := SITE_U
		# Round the ends with the outline's corners.
		var dv := maxf(maxf(SITE_V0 + SITE_CORNER - v, v - (SITE_V1 - SITE_CORNER)), 0.0)
		if dv > 0.0:
			half = SITE_U - SITE_CORNER + sqrt(maxf(SITE_CORNER * SITE_CORNER - dv * dv, 0.0))
		half -= 30.0
		out.append([world(-half, v), world(half, v), 34.0])
		v += 60.0
	return out


# --- The roads -----------------------------------------------------------------------------

## The north drive (to the valley floor) and Stadium Way (down the south face to Hill St), world
## XZ polylines. Their heights are worked out in add_roads() from the site's level at the start
## and the ground at the end, grade-limited.
const NORTH_DRIVE := [Vector2(-60.0, 300.0), Vector2(-60.0, 345.0)]
const NORTH_END := Vector2(1955.0, -3345.0)
## Stadium Way, from the upper terrace east of home to Hill St (DowntownReal: x 2864.4).
const STADIUM_WAY := [
	Vector2(2262.0, -2602.0), Vector2(2420.0, -2600.0), Vector2(2600.0, -2606.0), Vector2(2740.0, -2600.0),
	Vector2(2795.0, -2572.0), Vector2(2802.0, -2527.0), Vector2(2765.0, -2497.0), Vector2(2620.0, -2482.0),
	Vector2(2525.0, -2468.0), Vector2(2482.0, -2440.0), Vector2(2490.0, -2402.0), Vector2(2540.0, -2385.0),
	Vector2(2760.0, -2372.0), Vector2(2815.0, -2350.0), Vector2(2820.0, -2318.0), Vector2(2780.0, -2300.0),
	Vector2(2640.0, -2290.0), Vector2(2600.0, -2268.0), Vector2(2615.0, -2238.0), Vector2(2700.0, -2228.0),
	Vector2(2820.0, -2222.0), Vector2(2858.0, -2195.0), Vector2(2864.4, -2160.0), Vector2(2864.4, -2110.0),
]
const ROAD_WIDTH := 14.0
const ROAD_GRADE := 0.105
const ROAD_STEP := 12.0

## Off (the A/B): `BALLPARK=0` in the environment.
static var _enabled: int = -1


static func enabled() -> bool:
	if _enabled < 0:
		_enabled = 0 if OS.get_environment("BALLPARK") == "0" else 1
	return _enabled == 1


## Adds the two roads to the hill roads (after everything else HillRoads built, so no roll moves)
## and re-indexes them. `macro` must have its hill roads; `natural` is the ground before the site's
## carve (MacroMap's raw + relief).
static func add_roads(macro: MacroMap) -> void:
	if not enabled() or macro.hill_roads == null:
		return
	var hr: HillRoads = macro.hill_roads
	var north := PackedVector2Array()
	for p: Vector2 in NORTH_DRIVE:
		north.append(world(p.x, p.y))
	north.append(NORTH_END)
	_add_road(hr, macro, "Sunridge Dr", _resample(north))
	var way := PackedVector2Array()
	for p: Vector2 in STADIUM_WAY:
		way.append(p)
	_add_road(hr, macro, "Stadium Way", _resample(way))
	hr._index()


static func _resample(pts: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in pts.size() - 1:
		var n := maxi(1, ceili(pts[i].distance_to(pts[i + 1]) / ROAD_STEP))
		for k in n:
			out.append(pts[i].lerp(pts[i + 1], float(k) / n))
	out.append(pts[pts.size() - 1])
	return out


## Heights: the site's level at the start, the natural ground (with the site cut in) at the end,
## and in between the ground smoothed along the road, then held within ROAD_GRADE of its
## neighbours by passes from both ends, never climbing on the way down (the least earthwork a
## drivable grade allows).
static func _add_road(hr: HillRoads, macro: MacroMap, road_name: String, pts: PackedVector2Array) -> void:
	var n := pts.size()
	var ground := PackedFloat32Array()
	for p in pts:
		ground.append(carve(p, macro.raw_height_at(p) + macro.relief_at(p)))
	var hs := PackedFloat32Array()
	hs.resize(n)
	for i in n:
		var acc := 0.0
		var w := 0.0
		for k in range(maxi(0, i - 4), mini(n, i + 5)):
			acc += ground[k]
			w += 1.0
		hs[i] = acc / w
	hs[0] = level(local(pts[0]))
	hs[n - 1] = ground[n - 1]
	for _pass in 6:
		for i in range(1, n):
			var g := ROAD_GRADE * pts[i].distance_to(pts[i - 1])
			hs[i] = clampf(hs[i], hs[i - 1] - g, hs[i - 1])
		for i in range(n - 2, -1, -1):
			var g := ROAD_GRADE * pts[i].distance_to(pts[i + 1])
			hs[i] = clampf(hs[i], hs[i + 1], hs[i + 1] + g)
	hr.roads.append({"name": road_name, "points": pts, "heights": hs, "width": ROAD_WIDTH,
		"mansions": false, "planned_points": pts, "ballpark": true})


## The road named `road_name` from HillRoads (or {}).
static func road(macro: MacroMap, road_name: String) -> Dictionary:
	if macro == null or macro.hill_roads == null:
		return {}
	for r in macro.hill_roads.roads:
		if r.get("ballpark", false) and r.name == road_name:
			return r
	return {}


# --- The lots ------------------------------------------------------------------------------------
# ballpark_lot.gdshader draws all of this from copies of these numbers (lot_*, plaza_*): change both.

## Stall modules across the site: from LOT_V0 every LOT_MODULE metres a double row of stalls
## (LOT_STALL_D deep, back to back) and a drive aisle; every fourth module a planted median in
## place of the stalls. Across u, blocks of LOT_BLOCK_STALLS_N stalls (LOT_STALL_W wide) with a
## cross aisle, every LOT_BLOCK_U.
const LOT_MODULE := 18.6
const LOT_STALL_D := 5.7
const LOT_STALL_W := 2.75
const LOT_BLOCK_U := 84.0
const LOT_BLOCK_STALLS_N := 28
## The plaza round the bowl: this far from home on the bowl's side, past the fence by PLAZA_FAIR
## in fair ground; then the ring drive, RING wide.
const PLAZA_BOWL := 108.0
const PLAZA_FAIR := 30.0
const RING := 16.0
## Planting along the site's edge, metres in.
const EDGE_PLANTING := 6.0


static func plaza_r(q: Vector2) -> float:
	var deg := rad_to_deg(atan2(q.x, q.y))
	return fence_r(deg) + PLAZA_FAIR if absf(deg) <= 45.0 and q.y > 0.0 else PLAZA_BOWL


enum Ground { LOT, PLAZA, RING_DRIVE, PLANTING }


## What the site's ground is at local `q` (ballpark_lot.gdshader's ground_kind(), the same tests).
static func ground_kind(q: Vector2) -> Ground:
	if site_sd(q) > -EDGE_PLANTING:
		return Ground.PLANTING
	var t := terrace_t(q)
	if t > 0.002 and t < 0.998:
		return Ground.PLANTING
	var pr := q.length()
	var pz := plaza_r(q)
	if pr < pz:
		return Ground.PLAZA
	if pr < pz + RING:
		return Ground.RING_DRIVE
	var tn := terrace_t(q + Vector2(3.0, 0.0)) + terrace_t(q - Vector2(3.0, 0.0)) + terrace_t(q + Vector2(0.0, 3.0)) + terrace_t(q - Vector2(0.0, 3.0))
	if (t < 0.002 and tn > 0.002) or (t > 0.998 and tn < 3.99):
		return Ground.PLANTING
	return Ground.LOT


## bp_hash01() in ballpark_common.gdshaderinc, bit for bit: lowbias32 of two integers.
static func ihash(a: int, b: int) -> int:
	var x := ((a + 65536) * 7919 + (b + 65536)) & 0xFFFFFFFF
	x ^= x >> 16
	x = (x * 0x7feb352d) & 0xFFFFFFFF
	x ^= x >> 15
	x = (x * 0x846ca68b) & 0xFFFFFFFF
	x ^= x >> 16
	return x


static func ihash01(a: int, b: int) -> float:
	return float(ihash(a, b) & 0xFFFF) / 65535.0


## The stall at local `q`: -1 when there is none or it is empty, else a number that picks the car
## (body and paint). The shader paints a car exactly where this returns one.
static func stall_car(q: Vector2) -> int:
	if ground_kind(q) != Ground.LOT:
		return -1
	var mv := (q.y - SITE_V0) / LOT_MODULE
	var mi := floori(mv)
	var vin := (mv - mi) * LOT_MODULE
	var ub := (q.x + SITE_U) / LOT_BLOCK_U
	var bi := floori(ub)
	var uin := (ub - bi) * LOT_BLOCK_U
	if mi % 4 == 3 or uin >= LOT_STALL_W * LOT_BLOCK_STALLS_N or vin >= LOT_STALL_D * 2.0:
		return -1
	var side := 0 if vin < LOT_STALL_D else 1
	var k := floori(uin / LOT_STALL_W)
	var ki := bi * LOT_BLOCK_STALLS_N + k
	var row := mi * 2 + side
	var fill := clampf(1.05 - (q.length() - 130.0) / 350.0, 0.3, 0.9)
	if ihash01(ki, row) >= fill:
		return -1
	return ihash(ki + 7000, row) & 0xFFFF


## The lot's light poles (local), on the line between back-to-back stalls of every other module,
## mid-block; none on the plaza, the drive, the planting or a median.
static func poles() -> Array[Vector2]:
	var out: Array[Vector2] = []
	var mi := 0
	while SITE_V0 + mi * LOT_MODULE < SITE_V1:
		if mi % 2 == 0 and mi % 4 != 3:
			var v := SITE_V0 + mi * LOT_MODULE + LOT_STALL_D
			var bi := 0
			while -SITE_U + (bi + 0.5) * LOT_BLOCK_U < SITE_U:
				var q := Vector2(-SITE_U + (bi + 0.5) * LOT_BLOCK_U, v)
				if ground_kind(q) == Ground.LOT and ground_kind(q + Vector2(0.0, 3.0)) == Ground.LOT and ground_kind(q - Vector2(0.0, 3.0)) == Ground.LOT:
					out.append(q)
				bi += 1
		mi += 1
	return out


## Where the palms stand (local x, y; z a variety number): along the middle of the planted slope
## between the lot levels, round the plaza's edge on the bowl's side, and down the planted medians
## within MEDIAN_PALM_REACH of home.
const MEDIAN_PALM_REACH := 300.0


static func palm_spots() -> Array[Vector3]:
	var out: Array[Vector3] = []
	var mid := TERRACE_R + SLOPE_RUN * 0.5
	var steps := int(TAU * mid / 15.0)
	for i in steps:
		var a := TAU * i / steps
		var q := TERRACE_C + Vector2(cos(a), sin(a)) * mid
		if q.y < TERRACE_V0 - 4.0 and site_sd(q) < -EDGE_PLANTING:
			out.append(Vector3(q.x, q.y, float(i)))
	var ring_r := PLAZA_BOWL - 3.0
	for i in 64:
		var deg := lerpf(55.0, 305.0, float(i) / 63.0)
		var q := Vector2(sin(deg_to_rad(deg)), cos(deg_to_rad(deg))) * ring_r
		out.append(Vector3(q.x, q.y, float(i + 3)))
	var mi := 3
	while SITE_V0 + mi * LOT_MODULE < SITE_V1:
		var v := SITE_V0 + mi * LOT_MODULE + LOT_STALL_D
		var u := -SITE_U + 10.0
		while u < SITE_U:
			var q := Vector2(u, v)
			if q.length() < MEDIAN_PALM_REACH and ground_kind(q) == Ground.LOT and fmod(u + SITE_U, LOT_BLOCK_U) < LOT_STALL_W * LOT_BLOCK_STALLS_N:
				out.append(Vector3(q.x, q.y, float(mi * 31 + int(u))))
			u += 21.0
		mi += 4
	return out
