class_name GolfCourse
extends RefCounted
## The valley's public golf course: nine holes, a driving range, a Spanish revival clubhouse with
## its car park and pro shop, laid on the rolling valley floor north of the front range (the real
## valley's municipal courses are its biggest open spaces). A landmark AREA, like MacArthur Park:
## its entry (Landmarks.all()) carries an "area" that CityPlan.sites() snaps to whole blocks, every
## road inside the four boundary roads is closed (CityPlan.road_open()), and the site's chunks
## build the course instead of a block (GolfBuild, Landmarks.site_steps()). Closing rather than
## removing the roads keeps every road index, block seed and roll in the city where it was.
##
## This file is the LAYOUT, PURE: worked out once per plan from the snapped site and hashes of
## the seed (never a chunk, block or Building rng). Nine holes are routed from a hand-drawn
## template (ROUTE, a loop out from the clubhouse and back, in metres of a 660 x 580 frame),
## mirrored east-west by a hash and every point jittered by a hash, then validated - a jitter that
## brings two holes' corridors too close falls back to a smaller one. Each hole has three tee boxes,
## a fairway that narrows to the green (par 4 and 5), a green with a collar and a pin, greenside
## and fairway bunkers; a pond with a fountain sits in front of the short par 3, a creek winds
## across the course into it, a cart path loops tee to green and back to the clubhouse (bridges
## where it crosses the creek), and the trees stand in the rough between the holes.
##
## Everything a FULL chunk draws on the ground is a distance field (metres, negative inside):
## fairway, green, bunker, tee, water, path. field() evaluates them at a point from a chunk's
## feature subset (gather()), and GolfBuild writes them into the turf mesh's vertices, where
## shaders/golf_turf.gdshader thresholds them per pixel (crisp edges from a 1.6 m grid). The same
## fields shape the ground (shape()): greens crowned, tees raised, bunkers dug with a lip, the pond
## and creek cut down to their water.

const ID := "golf_course"
## The site's wanted edges (world metres), snapped to the nearest roads by CityPlan.sites(): the
## valley floor between Ridge/Linden and the 14 m street south of River Blvd on the default seed
## (x -389..298, z -3131..-2544: 667 x 587 m kerb to kerb, about 39 ha).
const SITE := {
	"west_x": -389.0, "east_x": 298.0, "north_z": -3131.0, "south_z": -2544.0,
	"anchor": Vector2(-46.0, -2590.0),
	# Public street names round a course are fair game; these are invented.
	"streets": {"north": "FAIRWAY DR", "south": "COUNTRY CLUB DR", "west": "LINKS AVE", "east": "GREENS AVE"},
}
## The course's name on the clubhouse, the signs and the scorecards: invented.
const NAME := "VALLEY OAKS"
const CLUB_NAME := "VALLEY OAKS GOLF CLUB"

## The pavement ring inside the site's kerbs (m), and the strip between it and the course (a hedge
## and the boundary fence).
const PAVEMENT := 4.0
const BORDER := 6.0
## The template frame's size (m): ROUTE is drawn in it and scaled to the real course area.
const FRAME := Vector2(660.0, 580.0)
## The routing: per hole [par, [tee, bends..., green]] in frame metres (x east, y south), the
## clubhouse at the bottom middle. Drawn by hand (tools/... route sketch), checked by hole_gaps().
const ROUTE := [
	[4, [Vector2(455, 488), Vector2(545, 412), Vector2(612, 272)]],
	[3, [Vector2(598, 232), Vector2(565, 92)]],
	[4, [Vector2(625, 38), Vector2(470, 26), Vector2(232, 46)]],
	[3, [Vector2(186, 34), Vector2(80, 140)]],
	[4, [Vector2(105, 182), Vector2(150, 292), Vector2(196, 418)]],
	[4, [Vector2(250, 446), Vector2(292, 322), Vector2(328, 196)]],
	[3, [Vector2(372, 150), Vector2(498, 166)]],
	[4, [Vector2(552, 205), Vector2(515, 320), Vector2(450, 410)]],
	[4, [Vector2(415, 275), Vector2(362, 400), Vector2(332, 488)]],
]
## The practice ground and buildings in frame metres (Rect2: x, y, w, h).
const RANGE_RECT := Rect2(8, 286, 76, 284)
const CLUB_RECT := Rect2(282, 520, 100, 44)
const PARK_RECT := Rect2(398, 506, 166, 74)
const PUTT_CENTRE := Vector2(232, 536)
const SHOP_RECT := Rect2(156, 550, 18, 11)
## The pond (frame centre and radii) in front of the par 3 seventh, and the creek that feeds it.
const POND := [Vector2(438, 168), Vector2(30, 19)]
const CREEK := [Vector2(96, 250), Vector2(150, 300), Vector2(210, 312), Vector2(262, 286),
	Vector2(318, 262), Vector2(372, 232), Vector2(410, 196)]
## Hash jitter of every route point (m), and how close two holes' centre lines may come (m).
const JITTER := 11.0
const MIN_GAP := 44.0

## Turf geometry (m).
const FAIRWAY_HALF := Vector2(13.5, 17.0)
const APPROACH_HALF := 10.5
const GREEN_HALF := Vector2(12.0, 15.5)
const PAR3_GREEN_HALF := Vector2(10.0, 13.0)
const COLLAR := 1.3
const TEE_HALF := Vector2(6.0, 4.0)
const CREEK_HALF := 1.9
const PATH_HALF := 1.25
## Ground shaping (m): the green's crown, the tee pads' lift, the bunkers' depth and lip, the
## rough's mounding.
const GREEN_CROWN := 0.32
const TEE_LIFT := 0.45
const BUNKER_DEPTH := 0.62
const BUNKER_LIP := 0.2
const MOUND := 0.5
const MOUND_SCALE := 26.0
## Where the distance fields stop mattering (m): a feature further than this from a point cannot
## change what is drawn there (the vertex codes clamp at +-FIELD_REACH).
const FIELD_REACH := 8.0

## Tee box colours, back to front (blue, white, red): the markers' paint.
const TEE_COLORS := [Color(0.10, 0.22, 0.62), Color(0.92, 0.92, 0.90), Color(0.72, 0.10, 0.08)]

static var enabled: bool = OS.get_environment("GOLF") != "0"
static var _layouts: Dictionary = {}


static func entry() -> Dictionary:
	return {
		"id": ID, "anchor": SITE.anchor, "radius": 18.0,
		"area": {"west_x": SITE.west_x, "east_x": SITE.east_x, "north_z": SITE.north_z,
			"south_z": SITE.south_z, "keep_z": [], "streets": SITE.streets},
	}


# --- Hashes ---------------------------------------------------------------------------------------

static func h01(parts: Array) -> float:
	return float(absi(hash(parts)) % 100003) / 100003.0


static func hrange(a: float, b: float, parts: Array) -> float:
	return lerpf(a, b, h01(parts))


## Smooth value noise in [0, 1] off integer hashes (deterministic, no FastNoiseLite state).
static func vnoise(p: Vector2, salt: int) -> float:
	var i := Vector2i(floori(p.x), floori(p.y))
	var f := p - Vector2(i)
	f = f * f * (Vector2(3.0, 3.0) - 2.0 * f)
	var a := _lat(i.x, i.y, salt)
	var b := _lat(i.x + 1, i.y, salt)
	var c := _lat(i.x, i.y + 1, salt)
	var d := _lat(i.x + 1, i.y + 1, salt)
	return lerpf(lerpf(a, b, f.x), lerpf(c, d, f.x), f.y)


static func _lat(x: int, y: int, salt: int) -> float:
	var hh := (x * 73856093) ^ (y * 19349663) ^ (salt * 83492791)
	hh = (hh ^ (hh >> 13)) * 1274126177
	return float((hh ^ (hh >> 16)) & 0xffff) / 65535.0


# --- Layout ---------------------------------------------------------------------------------------

## Everything the course's builders place, world XZ, once per plan. {} without the site (no macro
## map: the test room, a bare plan) or with the course off.
static func layout(plan: CityPlan) -> Dictionary:
	if plan == null or not enabled:
		return {}
	var key := plan.get_instance_id()
	if _layouts.has(key):
		return _layouts[key]
	var site := plan.site_by_id(ID)
	if site.is_empty():
		_layouts[key] = {}
		return {}
	var lay := _make(plan, site)
	_layouts[key] = lay
	return lay


static func _make(plan: CityPlan, site: Dictionary) -> Dictionary:
	var ps := plan.seed
	var rect: Rect2 = site.rect
	var walk := rect.grow(-PAVEMENT)
	var course := walk.grow(-BORDER)
	var mirror := h01([ps, "golf_mirror"]) < 0.5
	var sc := course.size / FRAME
	var lay := {"site": site, "rect": rect, "walk": walk, "course": course, "mirror": mirror, "seed": ps}
	var to_w := func(q: Vector2) -> Vector2:
		var x := FRAME.x - q.x if mirror else q.x
		return course.position + Vector2(x, q.y) * sc
	var rect_w := func(r: Rect2) -> Rect2:
		var a: Vector2 = to_w.call(r.position)
		var b: Vector2 = to_w.call(r.end)
		return Rect2(Vector2(minf(a.x, b.x), minf(a.y, b.y)), (b - a).abs())
	lay.to_w = to_w
	# The practice ground and the buildings. The car park and the clubhouse forecourt run out to the
	# pavement (the street is where the cars come in).
	var range_r: Rect2 = rect_w.call(RANGE_RECT)
	var club: Rect2 = rect_w.call(CLUB_RECT)
	var park: Rect2 = rect_w.call(PARK_RECT)
	park.size.y = walk.end.y - park.position.y
	var shop: Rect2 = rect_w.call(SHOP_RECT)
	lay.range = range_r
	lay.club = club
	lay.park = park
	lay.shop = shop
	# The drop-off in front of the entrance (the building's front is 3 m inside the rect's street
	# edge) and the terrace behind the main block, over the course.
	var cx := club.get_center().x
	lay.forecourt = Rect2(cx - 16.0, club.end.y - 3.5, 32.0, walk.end.y - club.end.y + 3.5)
	lay.terrace = Rect2(cx - 20.0, club.position.y + 3.0, 40.0, 10.0)
	# Holes: the template jittered by a hash, validated, with less jitter if it fails.
	var holes: Array = []
	for attempt in 4:
		var amp := JITTER * pow(0.5, float(attempt)) if attempt < 3 else 0.0
		holes = []
		for i in ROUTE.size():
			var pts := PackedVector2Array()
			var src: Array = ROUTE[i][1]
			for k in src.size():
				var q: Vector2 = src[k]
				var j := Vector2(hrange(-1.0, 1.0, [ps, "golf_j", i, k, 0]), hrange(-1.0, 1.0, [ps, "golf_j", i, k, 1])) * amp
				# The first tee and the last green stay put by the clubhouse.
				if (i == 0 and k == 0) or (i == ROUTE.size() - 1 and k == src.size() - 1):
					j *= 0.25
				pts.append(to_w.call(q + j))
			holes.append(pts)
		if hole_gaps(holes) >= MIN_GAP * minf(sc.x, sc.y):
			break
	lay.holes = []
	for i in holes.size():
		lay.holes.append(_hole(ps, i, holes[i], int(ROUTE[i][0])))
	# Water: the pond (a jittered ellipse, smoothed) and the creek into it.
	var pc: Vector2 = to_w.call(POND[0])
	var pr: Vector2 = POND[1] * sc
	var pond := PackedVector2Array()
	for k in 14:
		var a := TAU * float(k) / 14.0
		var r := 1.0 + hrange(-0.22, 0.22, [ps, "golf_pond", k])
		pond.append(pc + Vector2(cos(a) * pr.x, sin(a) * pr.y) * r)
	pond = _chaikin(_chaikin(_chaikin(pond)))
	lay.pond = pond
	lay.pond_bounds = _bounds(pond)
	lay.fountain = pc + Vector2(hrange(-4.0, 4.0, [ps, "golf_fountain", 0]), hrange(-3.0, 3.0, [ps, "golf_fountain", 1]))
	var creek := PackedVector2Array()
	for k in CREEK.size():
		var q: Vector2 = CREEK[k]
		var j := Vector2(hrange(-1.0, 1.0, [ps, "golf_creek", k, 0]), hrange(-1.0, 1.0, [ps, "golf_creek", k, 1])) * 6.0
		if k == CREEK.size() - 1:
			# Its mouth: on the pond's rim, aimed at the middle.
			creek.append(pc + (to_w.call(q) - pc).normalized() * (minf(pr.x, pr.y) * 0.5))
		else:
			creek.append(to_w.call(q + j))
	creek = _chaikin(_chaikin(creek, false), false)
	lay.creek = creek
	lay.creek_bounds = _bounds(creek).grow(CREEK_HALF + FIELD_REACH)
	_water_levels(plan, lay)
	# The cart path, then what avoids it: the bunkers, the trees.
	lay.path = _cart_path(lay)
	lay.path_bounds = _bounds(lay.path).grow(PATH_HALF + FIELD_REACH)
	for h: Dictionary in lay.holes:
		_bunkers(ps, h, lay)
	lay.range_targets = _range_targets(lay)
	lay.putt = {"c": to_w.call(PUTT_CENTRE), "a": 13.0 * sc.x, "b": 9.0 * sc.y, "ang": 0.0, "pins": 6}
	lay.bridges = _bridges(lay)
	lay.trees = _trees(plan, lay)
	lay.bins = _bins(lay)
	return lay


## The smallest distance between any two holes' centre lines (m), green ends grown by nothing.
static func hole_gaps(holes: Array) -> float:
	var best := INF
	for i in holes.size():
		var a: PackedVector2Array = holes[i]
		for j in range(i + 1, holes.size()):
			var b: PackedVector2Array = holes[j]
			for k in a.size() - 1:
				for t in 21:
					var p := a[k].lerp(a[k + 1], float(t) / 20.0)
					best = minf(best, poly_dist(b, p))
	return best


## One hole from its centre line: tees, fairway, green, pin, mowing direction, yardage, par.
static func _hole(ps: int, i: int, pts: PackedVector2Array, template_par: int) -> Dictionary:
	var length := 0.0
	for k in pts.size() - 1:
		length += pts[k].distance_to(pts[k + 1])
	var yards := length / 0.9144
	var par := 3 if yards < 235.0 else (4 if yards < 470.0 else 5)
	if template_par == 3:
		par = 3
	var gc := pts[pts.size() - 1]
	var approach := (gc - pts[pts.size() - 2]).normalized()
	var gh: Vector2 = PAR3_GREEN_HALF if par == 3 else GREEN_HALF
	var green := {"c": gc, "a": gh.y * hrange(0.88, 1.12, [ps, "golf_g", i, 0]), "b": gh.x * hrange(0.85, 1.1, [ps, "golf_g", i, 1]),
		"ang": approach.angle() + hrange(-0.45, 0.45, [ps, "golf_g", i, 2])}
	# The pin: somewhere in the inner two thirds of the green (today's pin sheet).
	var pa := hrange(0.0, TAU, [ps, "golf_pin", i, 0])
	var pr := sqrt(h01([ps, "golf_pin", i, 1])) * 0.6
	var pin: Vector2 = gc + Vector2(cos(pa) * float(green.a), sin(pa) * float(green.b)).rotated(float(green.ang)) * pr
	# Tees: back on the first point, middle and forward up the first leg; boxes square to the line.
	var first := (pts[1] - pts[0]).normalized()
	var side := Vector2(-first.y, first.x)
	var tees: Array = []
	var tee_half: Vector2 = TEE_HALF * (Vector2(1.25, 1.3) if par == 3 else Vector2.ONE)
	var steps := [0.0, hrange(14.0, 20.0, [ps, "golf_t", i, 0]), hrange(30.0, 40.0, [ps, "golf_t", i, 1])]
	if par == 3:
		steps = [0.0, hrange(10.0, 14.0, [ps, "golf_t", i, 0]), hrange(20.0, 26.0, [ps, "golf_t", i, 1])]
	for t in 3:
		var c := pts[0] + first * float(steps[t]) + side * hrange(-3.0, 3.0, [ps, "golf_t", i, t, 2])
		tees.append({"c": c, "u": first, "half": tee_half, "color": TEE_COLORS[t], "mow": Vector2(-first.y, first.x)})
	# The fairway: from the landing area in front of the forward tee to the green's front.
	var fw := PackedVector2Array()
	var fw_from := float(steps[2]) + hrange(35.0, 60.0, [ps, "golf_fw", i, 0])
	if par >= 4:
		var front := length - float(green.a) * 0.55
		fw = sub_poly(pts, fw_from, front)
	var u := (pts[pts.size() - 1] - pts[0]).normalized()
	green["mow"] = Vector2(cos(approach.angle() + 0.785), sin(approach.angle() + 0.785))
	return {"n": i + 1, "par": par, "pts": pts, "length": length, "yards": int(round(yards)),
		"green": green, "pin": pin, "tees": tees, "fw": fw, "fw_from": fw_from,
		"fw_half": hrange(FAIRWAY_HALF.x, FAIRWAY_HALF.y, [ps, "golf_fw", i, 1]),
		"mow": Vector2(cos(approach.angle() + 0.785), sin(approach.angle() + 0.785)), "dir": u,
		"path_side": 1.0 if h01([ps, "golf_ps", i]) < 0.5 else -1.0,
		"bunkers": [], "bounds": _bounds(pts).grow(gh.y + 24.0)}


## Bunkers round the green (one to three, never in front on a par 3's line), and one or two at the
## landing area of a par 4 or 5, on the fairway's edge. Clear of the cart path and the water.
static func _bunkers(ps: int, h: Dictionary, lay: Dictionary) -> void:
	var i: int = h.n
	var g: Dictionary = h.green
	var gc: Vector2 = g.c
	var back: Vector2 = -(gc - (h.pts as PackedVector2Array)[(h.pts as PackedVector2Array).size() - 2]).normalized()
	var n := 1 + int(h01([ps, "golf_bk", i]) * 2.99)
	for k in n:
		var ang := hrange(0.6, 2.2, [ps, "golf_bk", i, k, 0]) * (1.0 if (k % 2 == 0) == (h01([ps, "golf_bk", i, "s"]) < 0.5) else -1.0)
		if k == 2:
			ang = PI + hrange(-0.5, 0.5, [ps, "golf_bk", i, k, 0])
		var d := back.rotated(ang)
		var a := hrange(6.5, 10.0, [ps, "golf_bk", i, k, 1])
		var b := hrange(3.2, 4.6, [ps, "golf_bk", i, k, 2])
		var reach := ellipse_radius(g, d) + COLLAR + b + 1.2
		var c := gc + d * reach
		var bk := {"c": c, "a": a, "b": b, "ang": d.angle() + PI * 0.5, "lobe": d.rotated(PI * 0.5) * a * hrange(-0.55, 0.55, [ps, "golf_bk", i, k, 3]), "lr": b * 0.8}
		if _bunker_clear(bk, lay):
			(h.bunkers as Array).append(bk)
	if int(h.par) >= 4 and (h.fw as PackedVector2Array).size() >= 2:
		var land := minf(float(h.length) - 95.0, hrange(185.0, 225.0, [ps, "golf_fb", i]))
		if land > float(h.fw_from) + 20.0:
			var m := 1 + int(h01([ps, "golf_fb", i, "n"]) < 0.4)
			for k in m:
				var s := land + float(k) * 22.0
				var at := poly_at(h.pts, s)
				var dir := poly_dir(h.pts, s)
				var sgn := (1.0 if h01([ps, "golf_fb", i, k, "side"]) < 0.5 else -1.0) * (1.0 if k == 0 else -1.0)
				var c: Vector2 = at + Vector2(-dir.y, dir.x) * sgn * (float(h.fw_half) + 1.5)
				var bk := {"c": c, "a": hrange(8.0, 13.0, [ps, "golf_fb", i, k, 1]), "b": hrange(3.6, 5.2, [ps, "golf_fb", i, k, 2]),
					"ang": dir.angle(), "lobe": dir * hrange(-5.0, 5.0, [ps, "golf_fb", i, k, 3]), "lr": 3.2}
				if _bunker_clear(bk, lay):
					(h.bunkers as Array).append(bk)


static func _bunker_clear(bk: Dictionary, lay: Dictionary) -> bool:
	var c: Vector2 = bk.c
	var r := float(bk.a) + 3.0
	if poly_dist(lay.path, c) < r + PATH_HALF + 1.0:
		return false
	if poly_dist(lay.creek, c) < r + CREEK_HALF + 2.0 or pond_sdf(lay, c) < r + 2.0:
		return false
	return (lay.course as Rect2).grow(-4.0).has_point(c)


## The radius of ellipse `e` ({c, a, b, ang}) in direction `d` (unit).
static func ellipse_radius(e: Dictionary, d: Vector2) -> float:
	var q := d.rotated(-float(e.ang))
	var a := float(e.a)
	var b := float(e.b)
	return 1.0 / sqrt((q.x * q.x) / (a * a) + (q.y * q.y) / (b * b))


## Water levels: the pond's surface (flat: under the lowest ground round it) and the creek's
## surface along its line (falling all the way to the pond, never above the ground).
static func _water_levels(plan: CityPlan, lay: Dictionary) -> void:
	var m := plan.macro
	var low := INF
	var pond: PackedVector2Array = lay.pond
	for p in pond:
		low = minf(low, m.relief_at(p))
	var b: Rect2 = lay.pond_bounds
	for gx in 5:
		for gz in 5:
			var p := b.position + b.size * Vector2((gx + 0.5) / 5.0, (gz + 0.5) / 5.0)
			if pond_inside(lay, p):
				low = minf(low, m.relief_at(p))
	lay.pond_level = low + CityChunk.SIDEWALK_TOP - 0.32
	var creek: PackedVector2Array = lay.creek
	var levels := PackedFloat32Array()
	levels.resize(creek.size())
	var run := INF
	for k in creek.size():
		run = minf(run, m.relief_at(creek[k]) + CityChunk.SIDEWALK_TOP - 0.85)
		levels[k] = maxf(run, float(lay.pond_level))
	# Never above the pond level is impossible to keep at the mouth if the ground there is lower;
	# the mouth simply meets the pond.
	levels[creek.size() - 1] = float(lay.pond_level)
	for k in range(creek.size() - 2, -1, -1):
		levels[k] = maxf(levels[k], levels[k + 1])
	lay.creek_levels = levels


## The cart path: out from the clubhouse to each tee, down one side of each hole to its green,
## on to the next tee and back to the clubhouse at the end. Points kept clear of greens, tees and
## the water, then smoothed.
static func _cart_path(lay: Dictionary) -> PackedVector2Array:
	var club: Rect2 = lay.club
	var pts := PackedVector2Array()
	pts.append(Vector2(club.get_center().x, club.position.y - 12.0))
	for h: Dictionary in lay.holes:
		var line: PackedVector2Array = h.pts
		var s: float = h.path_side
		var t0: Dictionary = (h.tees as Array)[0]
		var first := (line[1] - line[0]).normalized()
		var off := float(h.fw_half) + 9.0 if int(h.par) >= 4 else 10.0
		pts.append(line[0] - first * 9.0 + Vector2(-first.y, first.x) * s * 9.0)
		for k in range(1, line.size() - 1):
			var d0 := (line[k] - line[k - 1]).normalized()
			var d1 := (line[k + 1] - line[k]).normalized()
			var n := (Vector2(-d0.y, d0.x) + Vector2(-d1.y, d1.x)).normalized()
			pts.append(line[k] + n * s * off)
		var g: Dictionary = h.green
		var last := (line[line.size() - 1] - line[line.size() - 2]).normalized()
		var gside := Vector2(-last.y, last.x) * s
		var r := ellipse_radius(g, gside) + COLLAR + 7.0
		pts.append(line[line.size() - 1] - last * (float(g.a) * 0.5) + gside * r)
		pts.append(line[line.size() - 1] + last * (float(g.a) * 0.6) + gside * (r - 2.0))
		var _unused := t0
	pts.append(Vector2(club.get_center().x + 14.0, club.position.y - 12.0))
	# Keep each point out of the water and off every green, tee and the range.
	for k in pts.size():
		pts[k] = _push_clear(lay, pts[k])
	pts = _chaikin(_chaikin(_chaikin(pts, false), false), false)
	for k in pts.size():
		pts[k] = _push_clear(lay, pts[k])
	return pts


static func _push_clear(lay: Dictionary, p: Vector2) -> Vector2:
	for it in 6:
		var moved := false
		var ps := pond_sdf(lay, p)
		if ps < 5.0:
			var c: Vector2 = (lay.pond_bounds as Rect2).get_center()
			p += (p - c).normalized() * (5.0 - ps)
			moved = true
		for h: Dictionary in lay.holes:
			var g: Dictionary = h.green
			var gd := ellipse_sdf(g, p)
			if gd < COLLAR + 5.0:
				p += (p - (g.c as Vector2)).normalized() * (COLLAR + 5.0 - gd)
				moved = true
			for t: Dictionary in h.tees:
				var td := box_sdf(t, p)
				if td < 3.0:
					p += (p - (t.c as Vector2)).normalized() * (3.0 - td)
					moved = true
		var rr: Rect2 = (lay.range as Rect2).grow(4.0)
		if rr.has_point(p):
			p.x = rr.end.x + 0.5 if absf(p.x - rr.end.x) < absf(p.x - rr.position.x) else rr.position.x - 0.5
			moved = true
		var c2: Rect2 = (lay.course as Rect2).grow(-3.0)
		p = p.clamp(c2.position, c2.end)
		if not moved:
			break
	return p


## The driving range's target greens (circles at 50-250 yards up the range) and its flags.
static func _range_targets(lay: Dictionary) -> Array:
	var r: Rect2 = lay.range
	var out: Array = []
	var tee_y := r.end.y - 14.0
	var ps: int = lay.seed
	for k in 5:
		var yd := 50.0 * float(k + 1)
		var y := tee_y - yd * 0.9144
		if y < r.position.y + 8.0:
			break
		var x := r.position.x + r.size.x * (0.3 + 0.4 * h01([ps, "golf_rt", k]))
		out.append({"c": Vector2(x, y), "a": 6.0 + float(k) * 1.1, "b": 6.0 + float(k) * 1.1, "ang": 0.0, "yards": int(yd)})
	return out


## Where the cart path crosses the creek: [centre, direction of the path, span].
static func _bridges(lay: Dictionary) -> Array:
	var out: Array = []
	var path: PackedVector2Array = lay.path
	var creek: PackedVector2Array = lay.creek
	for k in path.size() - 1:
		var a := path[k]
		var b := path[k + 1]
		for j in creek.size() - 1:
			var x: Variant = Geometry2D.segment_intersects_segment(a, b, creek[j], creek[j + 1])
			if x != null:
				var near := false
				for o: Array in out:
					if (o[0] as Vector2).distance_to(x) < 12.0:
						near = true
				if not near:
					out.append([x, (b - a).normalized(), CREEK_HALF * 2.0 + 5.0])
	return out


## The trees: a jittered grid over the course, kept in the rough clear of everything played,
## thinned by a slow noise into groves and lines between the holes. [position, species, scale
## roll]. Species: 0 the broad city tree (oak-like), 1 the tall pine, 2 the jacaranda, 3 a palm.
static func _trees(plan: CityPlan, lay: Dictionary) -> Array:
	var ps := plan.seed
	var out: Array = []
	var c: Rect2 = lay.course
	var step := 10.5
	var all := gather(lay, c)
	var nx := int(c.size.x / step)
	var nz := int(c.size.y / step)
	for gz in nz:
		for gx in nx:
			var p := c.position + Vector2((float(gx) + 0.5 + hrange(-0.4, 0.4, [ps, "golf_tr", gx, gz, 0])) * step,
				(float(gz) + 0.5 + hrange(-0.4, 0.4, [ps, "golf_tr", gx, gz, 1])) * step)
			var grove := vnoise(p / 55.0, ps & 0xffff)
			if grove < 0.47:
				continue
			if not c.grow(-2.0).has_point(p):
				continue
			var f := field(all, p)
			if f[0] < 9.0 or f[1] < 12.0 or f[2] < 5.0 or f[3] < 7.0 or f[4] < 5.0 or f[5] < 3.5:
				continue
			if (lay.range as Rect2).grow(8.0).has_point(p) or (lay.club as Rect2).grow(14.0).has_point(p) or (lay.park as Rect2).grow(3.0).has_point(p) or (lay.shop as Rect2).grow(8.0).has_point(p):
				continue
			if _in_line_of_play(lay, p):
				continue
			var roll := h01([ps, "golf_tr", gx, gz, 2])
			var species := 0 if roll < 0.4 else (4 if roll < 0.72 else (1 if roll < 0.88 else 2))
			out.append([p, species, h01([ps, "golf_tr", gx, gz, 3])])
	# Palms: a row along the entry drive and a pair at the clubhouse front.
	var park: Rect2 = lay.park
	var club: Rect2 = lay.club
	var walk: Rect2 = lay.walk
	var x_drive := park.position.x - 3.0 if not lay.mirror else park.end.x + 3.0
	var y := park.position.y + 4.0
	while y < walk.end.y - 3.0:
		out.append([Vector2(x_drive, y), 3, h01([ps, "golf_palm", int(y)])])
		y += 11.0
	for sx in [-1.0, 1.0]:
		out.append([Vector2(club.get_center().x + sx * (club.size.x * 0.5 + 6.0), club.end.y + 6.0), 3, h01([ps, "golf_palm_c", sx])])
		out.append([Vector2(club.get_center().x + sx * (club.size.x * 0.5 - 6.0), club.position.y - 13.0), 3, h01([ps, "golf_palm_t", sx])])
	return out


## True where `p` lies in the corridor a ball flies down (tee to green, 20 m either side).
static func _in_line_of_play(lay: Dictionary, p: Vector2) -> bool:
	for h: Dictionary in lay.holes:
		if not (h.bounds as Rect2).has_point(p):
			continue
		if poly_dist(h.pts, p) < float(h.fw_half) + 7.0:
			return true
	return false


## Ball washers, benches, yardage posts and hole signs at each tee: [kind, position, yaw, data].
static func _bins(lay: Dictionary) -> Array:
	var out: Array = []
	for h: Dictionary in lay.holes:
		var t0: Dictionary = (h.tees as Array)[0]
		var u: Vector2 = t0.u
		var side := Vector2(-u.y, u.x) * float(h.path_side)
		var half: Vector2 = t0.half
		var c: Vector2 = t0.c
		out.append(["sign", c - u * (half.y + 3.0) + side * (half.x + 1.8), atan2(-u.x, -u.y), h])
		out.append(["washer", c + side * (half.x + 2.2) - u * 1.0, atan2(-side.x, -side.y), h])
		out.append(["bench", c + side * (half.x + 3.6) - u * 4.5, atan2(side.x, side.y), h])
		# Yardage posts at 200 / 150 / 100 yards from the green's centre, on the line, at the
		# fairway's edge (red, white, blue the golf way round: 100 red, 150 white, 200 blue).
		if int(h.par) >= 4:
			for yd: int in [200, 150, 100]:
				var s := float(h.length) - float(yd) * 0.9144
				if s < float(h.fw_from) + 10.0:
					continue
				var at := poly_at(h.pts, s)
				var dir := poly_dir(h.pts, s)
				out.append(["yardage", at + Vector2(-dir.y, dir.x) * float(h.path_side) * (float(h.fw_half) + 2.0), 0.0, yd])
				out.append(["plate", at, atan2(-dir.x, -dir.y), yd])
	return out


# --- Geometry -------------------------------------------------------------------------------------

static func _chaikin(pts: PackedVector2Array, closed: bool = true) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := pts.size()
	if n < 3:
		return pts
	if not closed:
		out.append(pts[0])
	var m := n if closed else n - 1
	for i in m:
		var a := pts[i]
		var b := pts[(i + 1) % n]
		out.append(a.lerp(b, 0.25))
		out.append(a.lerp(b, 0.75))
	if not closed:
		out.append(pts[n - 1])
	return out


static func _bounds(pts: PackedVector2Array) -> Rect2:
	var r := Rect2(pts[0], Vector2.ZERO)
	for p in pts:
		r = r.expand(p)
	return r


## Distance from `p` to the polyline `pts` (open).
static func poly_dist(pts: PackedVector2Array, p: Vector2) -> float:
	var best := INF
	for k in pts.size() - 1:
		best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, pts[k], pts[k + 1])))
	return best


## The point `s` metres along polyline `pts` (clamped), and its direction.
static func poly_at(pts: PackedVector2Array, s: float) -> Vector2:
	var run := 0.0
	for k in pts.size() - 1:
		var l := pts[k].distance_to(pts[k + 1])
		if run + l >= s:
			return pts[k].lerp(pts[k + 1], clampf((s - run) / maxf(l, 0.001), 0.0, 1.0))
		run += l
	return pts[pts.size() - 1]


static func poly_dir(pts: PackedVector2Array, s: float) -> Vector2:
	var run := 0.0
	for k in pts.size() - 1:
		var l := pts[k].distance_to(pts[k + 1])
		if run + l >= s:
			return (pts[k + 1] - pts[k]) / maxf(l, 0.001)
		run += l
	return (pts[pts.size() - 1] - pts[pts.size() - 2]).normalized()


## The part of polyline `pts` from `s0` to `s1` metres along it.
static func sub_poly(pts: PackedVector2Array, s0: float, s1: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	if s1 <= s0:
		return out
	out.append(poly_at(pts, s0))
	var run := 0.0
	for k in pts.size() - 1:
		run += pts[k].distance_to(pts[k + 1])
		if run > s0 and run < s1 and k < pts.size() - 2:
			out.append(pts[k + 1])
	out.append(poly_at(pts, s1))
	return out


## Signed distance to ellipse `e` ({c, a, b, ang}), approximate (exact on the axes), metres.
static func ellipse_sdf(e: Dictionary, p: Vector2) -> float:
	var q := (p - (e.c as Vector2)).rotated(-float(e.ang))
	var a := float(e.a)
	var b := float(e.b)
	var k := Vector2(q.x / a, q.y / b).length()
	if k < 1e-5:
		return -minf(a, b)
	# Distance along the ray through q to the rim, scaled to the gradient (good near the edge).
	var k1 := Vector2(q.x / (a * a), q.y / (b * b)).length()
	return k * (k - 1.0) / maxf(k1, 1e-5)


## Signed distance to a tee box ({c, u, half}: half.x along u... u is the line of play; the box's
## long side runs ACROSS it).
static func box_sdf(t: Dictionary, p: Vector2) -> float:
	var u: Vector2 = t.u
	var d := p - (t.c as Vector2)
	var half: Vector2 = t.half
	var q := Vector2(absf(d.dot(Vector2(-u.y, u.x))) - half.x, absf(d.dot(u)) - half.y)
	return Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0)


static func rect_sdf(r: Rect2, p: Vector2) -> float:
	var c := r.get_center()
	var q := (p - c).abs() - r.size * 0.5
	return Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0)


static func bunker_sdf(bk: Dictionary, p: Vector2) -> float:
	var d := ellipse_sdf(bk, p)
	var lc: Vector2 = (bk.c as Vector2) + (bk.lobe as Vector2)
	return minf(d, p.distance_to(lc) - float(bk.lr))


static func pond_inside(lay: Dictionary, p: Vector2) -> bool:
	return (lay.pond_bounds as Rect2).has_point(p) and Geometry2D.is_point_in_polygon(p, lay.pond)


static func pond_sdf(lay: Dictionary, p: Vector2) -> float:
	var b: Rect2 = lay.pond_bounds
	if not b.grow(FIELD_REACH + 30.0).has_point(p):
		return rect_sdf(b, p)
	var pts: PackedVector2Array = lay.pond
	var best := INF
	for k in pts.size():
		best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, pts[k], pts[(k + 1) % pts.size()])))
	return -best if Geometry2D.is_point_in_polygon(p, pts) else best


## Every field at `p` straight from the layout (slow: the tests and the planting use it; the turf
## mesh uses gather() + field()). [fairway, green, bunker, tee, water, path].
static func field_all(lay: Dictionary, p: Vector2) -> PackedFloat32Array:
	var sub := gather(lay, Rect2(p, Vector2.ZERO))
	return field(sub, p)


# --- Fields for a chunk ---------------------------------------------------------------------------

## The features that can reach `area` (grown by FIELD_REACH), binned on a BIN metre grid so a point
## only runs over what can reach it: each bin holds [fairway segments, greens, bunkers, tees, creek
## segments, path segments, paved rects, pond?, range?]. Polylines go in as segments.
const BIN := 12.0


static func gather(lay: Dictionary, area: Rect2) -> Dictionary:
	var reach := area.grow(FIELD_REACH + 2.0)
	var items: Array = [] # [category, influence rect, item]
	for h: Dictionary in lay.holes:
		if not (h.bounds as Rect2).grow(30.0).intersects(reach):
			continue
		var fw: PackedVector2Array = h.fw
		var run := float(h.fw_from)
		var fw_reach := float(h.fw_half) * 1.2 + FIELD_REACH + 0.5
		for k in fw.size() - 1:
			var a := fw[k]
			var b := fw[k + 1]
			var l := a.distance_to(b)
			items.append([0, Rect2(a, Vector2.ZERO).expand(b).grow(fw_reach), [a, b, run, l, h]])
			run += l
		var g: Dictionary = h.green
		items.append([1, Rect2(g.c, Vector2.ZERO).grow(float(g.a) + COLLAR + FIELD_REACH + 0.5), g])
		for t: Dictionary in h.tees:
			items.append([3, Rect2(t.c, Vector2.ZERO).grow(9.0 + FIELD_REACH), t])
		for bk: Dictionary in h.bunkers:
			items.append([2, Rect2(bk.c, Vector2.ZERO).grow(float(bk.a) + (bk.lobe as Vector2).length() + float(bk.lr) + FIELD_REACH + 0.5), bk])
	for g: Dictionary in lay.range_targets:
		items.append([1, Rect2(g.c, Vector2.ZERO).grow(float(g.a) + COLLAR + FIELD_REACH + 0.5), g])
	var putt: Dictionary = lay.putt
	items.append([1, Rect2(putt.c, Vector2.ZERO).grow(float(putt.a) + COLLAR + FIELD_REACH + 0.5), putt])
	var creek: PackedVector2Array = lay.creek
	var levels: PackedFloat32Array = lay.creek_levels
	for k in creek.size() - 1:
		items.append([4, Rect2(creek[k], Vector2.ZERO).expand(creek[k + 1]).grow(CREEK_HALF + FIELD_REACH + 0.5), [creek[k], creek[k + 1], levels[k], levels[k + 1]]])
	var path: PackedVector2Array = lay.path
	for k in path.size() - 1:
		items.append([5, Rect2(path[k], Vector2.ZERO).expand(path[k + 1]).grow(PATH_HALF + FIELD_REACH + 0.5), [path[k], path[k + 1]]])
	for r: Rect2 in [lay.forecourt, lay.terrace, (lay.shop as Rect2).grow(2.0)]:
		items.append([6, r.grow(FIELD_REACH + 0.5), r])
	items.append([7, (lay.pond_bounds as Rect2).grow(FIELD_REACH + 0.5), true])
	items.append([8, (lay.range as Rect2).grow(FIELD_REACH + 0.5), true])
	var nx := maxi(1, ceili(reach.size.x / BIN))
	var nz := maxi(1, ceili(reach.size.y / BIN))
	var bins: Array = []
	bins.resize(nx * nz)
	for it: Array in items:
		var r: Rect2 = (it[1] as Rect2).intersection(reach)
		if r.size.x <= 0.0 and r.size.y <= 0.0 and not reach.intersects(it[1]):
			continue
		if not reach.intersects(it[1]):
			continue
		var i0 := clampi(floori((r.position.x - reach.position.x) / BIN), 0, nx - 1)
		var i1 := clampi(floori((r.end.x - reach.position.x) / BIN), 0, nx - 1)
		var j0 := clampi(floori((r.position.y - reach.position.y) / BIN), 0, nz - 1)
		var j1 := clampi(floori((r.end.y - reach.position.y) / BIN), 0, nz - 1)
		for j in range(j0, j1 + 1):
			for i in range(i0, i1 + 1):
				var k := j * nx + i
				if bins[k] == null:
					bins[k] = [[], [], [], [], [], [], [], false, false]
				var bin: Array = bins[k]
				var cat: int = it[0]
				if cat >= 7:
					bin[cat] = true
				else:
					(bin[cat] as Array).append(it[2])
	var tees: Array = []
	for it: Array in items:
		if int(it[0]) == 3 and reach.intersects(it[1]):
			tees.append(it[2])
	return {"lay": lay, "origin": reach.position, "nx": nx, "nz": nz, "bins": bins, "tees": tees}


const _EMPTY_BIN := [[], [], [], [], [], [], [], false, false]


## The fields at `p`: [fairway, green, bunker, tee, water, path, mow.x, mow.y, water level].
## Metres, negative inside. The mowing direction is the nearest feature's (the range's own on it).
static func field(sub: Dictionary, p: Vector2) -> PackedFloat32Array:
	var lay: Dictionary = sub.lay
	var o: Vector2 = sub.origin
	var nx: int = sub.nx
	var i := clampi(floori((p.x - o.x) / BIN), 0, nx - 1)
	var j := clampi(floori((p.y - o.y) / BIN), 0, int(sub.nz) - 1)
	var bin: Variant = (sub.bins as Array)[j * nx + i]
	var b: Array = bin if bin != null else _EMPTY_BIN
	var fw := 1e3
	var mow := Vector2(0.7071, 0.7071)
	var mow_d := INF
	for s: Array in b[0]:
		var a: Vector2 = s[0]
		var e: Vector2 = s[1]
		var ab := e - a
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-4), 0.0, 1.0)
		var h: Dictionary = s[4]
		var along := float(s[2]) + float(s[3]) * t
		var total := float(h.length)
		# Narrowing to the approach over the last 60 m, and a slow wave in its edges.
		var half := lerpf(float(h.fw_half), APPROACH_HALF, smoothstep(total - 75.0, total - 15.0, along))
		half *= 1.0 + 0.12 * sin(along / 23.0 + float(h.n) * 1.7) + 0.06 * sin(along / 9.0 + float(h.n))
		var d := p.distance_to(a + ab * t) - half
		if d < fw:
			fw = d
		if d < mow_d:
			mow_d = d
			mow = h.mow
	if b[8]:
		var rr: Rect2 = lay.range
		var rd := rect_sdf(Rect2(rr.position.x + 1.0, rr.position.y + 1.0, rr.size.x - 2.0, rr.size.y - 20.0), p)
		if rd < fw:
			fw = rd
			mow = Vector2(1.0, 0.0)
			mow_d = rd
	var green := 1e3
	for g: Dictionary in b[1]:
		var d := ellipse_sdf(g, p)
		if d < green:
			green = d
			if d < mow_d:
				mow_d = d
				mow = g.get("mow", Vector2(1.0, 0.0))
	var bunker := 1e3
	for bk: Dictionary in b[2]:
		bunker = minf(bunker, bunker_sdf(bk, p))
	var tee := 1e3
	for t: Dictionary in b[3]:
		var d := box_sdf(t, p)
		if d < tee:
			tee = d
			if d < mow_d:
				mow_d = d
				mow = t.mow
	if b[8]:
		var rr: Rect2 = lay.range
		var td := rect_sdf(Rect2(rr.position.x + 2.0, rr.end.y - 18.0, rr.size.x - 4.0, 12.0), p)
		if td < tee:
			tee = td
	var water := 1e3
	var level := 0.0
	if b[7]:
		water = pond_sdf(lay, p)
		level = float(lay.pond_level)
	for s: Array in b[4]:
		var a: Vector2 = s[0]
		var e: Vector2 = s[1]
		var ab := e - a
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-4), 0.0, 1.0)
		var d := p.distance_to(a + ab * t) - CREEK_HALF
		if d < water:
			water = d
			level = lerpf(float(s[2]), float(s[3]), t)
	var path := 1e3
	for s: Array in b[5]:
		path = minf(path, p.distance_to(Geometry2D.get_closest_point_to_segment(p, s[0], s[1])) - PATH_HALF)
	for r: Rect2 in b[6]:
		path = minf(path, rect_sdf(r, p))
	return PackedFloat32Array([fw, green, bunker, tee, water, path, mow.x, mow.y, level])


## The ground at `p` given its fields `f` and the plain relief top `base` (the chunk's _gy plus the
## pavement top): the rough's mounding, the green's crown, the tees' pads, the bunkers dug out,
## the banks down to the water. `tee_level` is the pad top of the nearest tee (GolfBuild works it
## out once per tee).
static func shape(sub: Dictionary, p: Vector2, f: PackedFloat32Array, base: float, tee_level: float) -> float:
	var lay: Dictionary = sub.lay
	var fw := f[0]
	var green := f[1]
	var bunker := f[2]
	var tee := f[3]
	var water := f[4]
	var path := f[5]
	# Mounds: big soft swells in the rough, gentler on the fairways, none on the hard ground.
	var m := (vnoise(p / MOUND_SCALE, 7) - 0.5) * 2.0 + (vnoise(p / (MOUND_SCALE * 0.43), 11) - 0.5) * 0.6
	var amp := MOUND * lerpf(0.45, 1.0, smoothstep(-2.0, 7.5, fw))
	amp *= smoothstep(-1.0, 6.0, path + 1.25)
	var y := base + m * amp
	# Greens: a crown that rises from the collar and tips back toward the approach.
	if green < 6.0:
		var crown := GREEN_CROWN * smoothstep(5.0, -6.0, green)
		y += crown
	# Tee pads: level tops, sloped sides over 2.5 m.
	if tee < 3.0 and tee_level > -1e5:
		y = lerpf(y, tee_level, smoothstep(3.0, 0.0, tee))
	# Bunkers: dug out with a raised lip round them.
	if bunker < 2.5:
		y += BUNKER_LIP * (1.0 - smoothstep(0.0, 2.5, absf(bunker))) * (1.0 if bunker > 0.0 else 0.4)
		if bunker < 0.0:
			y -= BUNKER_DEPTH * smoothstep(0.0, 2.2, -bunker)
	# Water: banks run down to the surface, and under it the bed.
	if water < 7.9:
		var level := f[8]
		var bank := level + 0.06 + maxf(water, 0.0) * 0.28 + maxf(water - 4.0, 0.0) * 1.6
		y = minf(y, bank)
		if water < 0.0:
			y = minf(y, level - minf(1.3, 0.12 + (-water) * 0.32))
	var _l := lay
	return y
