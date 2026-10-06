class_name Parks
extends RefCounted
## Los Angeles rec parks and school campuses (2026-10-04, owner: "make the graphics a million times
## better"). From the air real LA is stamped all over with baseball diamonds, basketball and tennis
## courts, soccer fields, school running tracks and public pools; ours had lawns, trees and
## fountains and none of those.
##
## Two block roles, rolled by CityPlan.block() through role_for() AFTER every other roll and
## override, from a hash of the seed and the block (never the block rng, so no seed moves):
##   "rec"     a rec park: a PARK block (most PARK blocks in the suburbs, midtown and the beach
##             town, and a few BUILDINGS blocks) laid out as a diamond, a soccer field, basketball
##             and tennis courts, a playground, a rec centre with a public pool, picnic shelters, a
##             car park, a walking loop and trees round it, field floodlights.
##   "school"  a school campus (CityPlan.BlockKind.SCHOOL, no lots): classroom wings with covered
##             walkways along the front, a drop-off loop on the street, a car park, an asphalt yard
##             with painted courts and games, a track round a football field with goal posts and
##             bleachers where the block is big enough (a high school), a playground and a grass
##             field otherwise (an elementary school), a chain-link fence round it all.
## Every plan is PURE (rec_plan(), school_plan(), plan_for(): the plan and the block) and cached per
## plan; every roll is a private stream seeded by hash([seed, ix, iz, ...]). Facilities are
## axis-aligned rects at real (regulation) dimensions in a facility frame: `c` the centre, `u` the
## long axis (a unit Vector2 along +-x or +-z), `v` = (-u.y, u.x), `L` x `W` the size along u x v.
##
## Drawn (Parks.build(), from CityChunk's block steps): a FULL chunk's park and school ground is ONE
## mesh on shaders/park_ground.gdshader (the kind in COLOR.r: turf, soccer, diamond, basketball,
## tennis, track and its football field, rubber, pool, deck, asphalt, DG, painted games; the lines
## drawn by the shader from the facility's own coordinates in UV), everything upright ONE casting
## mesh on shaders/park_walls.gdshader (ParkKit: fences, windscreens, nets, hoops, goals, backstop,
## dugouts, bleachers, playground, floodlights, the rec centre, the classroom wings, picnic
## shelters) and one shadowless batch of floodlight pools. LOD chunks and the far city's capture
## get the ground as slabs (partitioned, never stacked) and the buildings and bleachers as far
## boxes.

## Off: no block is rolled a rec park or a school (the A/B: PARKS=0 on still_shot.gd and
## tools/lot_coverage.gd; it must be set before the plan's blocks are asked for).
static var enabled: bool = OS.get_environment("PARKS") != "0"

## The districts each role is rolled in, with its odds. A PARK block there is a rec park at
## REC_ON_PARK; a BUILDINGS block becomes a rec park at REC_ON_BUILDINGS and a school at the
## district's SCHOOL_ODDS (LA: a school every few hundred blocks; the game packs them in so a flight
## over the suburbs crosses a few).
const REC_DISTRICTS := [CityPlan.District.SUBURBS, CityPlan.District.MIDTOWN, CityPlan.District.BEACHTOWN]
const REC_ON_PARK := 0.6
const REC_ON_BUILDINGS := {CityPlan.District.SUBURBS: 0.035, CityPlan.District.MIDTOWN: 0.025}
const SCHOOL_ODDS := {CityPlan.District.SUBURBS: 0.08, CityPlan.District.MIDTOWN: 0.045}
## Smallest inner rect (inside the pavement ring) each role takes, metres (short side, long side).
const REC_MIN := Vector2(46.0, 56.0)
const SCHOOL_MIN := Vector2(56.0, 70.0)

# --- Real dimensions (metres) ------------------------------------------------------------------
## Softball / Little League: 60 ft between bases, the pitcher 46 ft out, the fence 200-225 ft.
const BASE_PATH := 18.29
const PITCH_DIST := 14.02
const FENCE_RADIUS := Vector2(48.0, 68.6)
const BACKSTOP := 7.5
## FIBA court 28 x 15 (outdoor LA courts are NBA 94 x 50 ft, near enough); 2 m clear round it.
const BB_COURT := Vector2(28.65, 15.24)
const BB_CLEAR := 1.8
## A tennis court in its 120 x 60 ft fenced enclosure.
const TEN_COURT := Vector2(23.77, 10.97)
const TEN_ENCLOSURE := Vector2(36.58, 18.29)
## Soccer: FIFA 105 x 68 at most, youth fields smaller; 3 m run-off.
const SOCCER_MAX := Vector2(100.0, 64.0)
const SOCCER_RUNOFF := 3.0
## A 25 m, six-lane pool (2.5 m lanes) with its deck.
const POOL := Vector2(25.0, 15.0)
const POOL_DECK := 4.0
## The track: 1.22 m lanes, a 36.5 m inside radius and 84.39 m straights make 400 m in lane 1.
const LANE := 1.22
const TRACK_R := 36.5
const TRACK_S := 84.39
const TRACK_APRON := 2.0
## American football: 120 x 53 1/3 yards with the end zones.
const FOOTBALL := Vector2(109.73, 48.77)
## How far the facilities keep in from the park's edge (a ring of lawn, trees and the walk).
const REC_BORDER := 5.0
const WALK_W := 2.4
## Classroom wing depth (single-loaded, with the covered walkway along it) and storey height.
const WING_DEPTH := 11.0
const WALKWAY := 3.2
const STOREY := 3.9
const DROPOFF_DEPTH := 11.0

# --- Ground kinds: shaders/park_ground.gdshader, COLOR.r in 16ths --------------------------------
const G_TURF := 0
const G_SOCCER := 1
const G_DIAMOND := 2
const G_BASKETBALL := 3
const G_TENNIS := 4
const G_TRACK := 5
const G_RUBBER := 6
const G_POOL := 7
const G_DECK := 8
const G_ASPHALT := 9
const G_DG := 10
const G_GAMES := 11
const G_LAWN := 12

## Court and track palettes (display / sRGB numbers, as the ground shader reads them): [inside, outside].
const BB_PALETTES := [
	[Color(0.20, 0.36, 0.56), Color(0.16, 0.42, 0.33)],
	[Color(0.62, 0.24, 0.20), Color(0.18, 0.40, 0.30)],
	[Color(0.19, 0.30, 0.50), Color(0.13, 0.20, 0.36)],
	[Color(0.36, 0.38, 0.42), Color(0.20, 0.36, 0.56)],
]
const TEN_PALETTES := [
	[Color(0.19, 0.34, 0.55), Color(0.20, 0.42, 0.32)],
	[Color(0.22, 0.45, 0.33), Color(0.55, 0.24, 0.20)],
	[Color(0.24, 0.47, 0.36), Color(0.17, 0.35, 0.27)],
]
## School colours (end zones, wing trim, bleacher seats): invented schools, invented colours.
const SCHOOL_COLORS := [Color(0.55, 0.10, 0.12), Color(0.10, 0.20, 0.45), Color(0.08, 0.36, 0.20),
	Color(0.62, 0.40, 0.06), Color(0.32, 0.12, 0.40), Color(0.85, 0.42, 0.08)]
## Stucco for the rec centres and the classroom wings (LAUSD's beiges, creams and the odd pastel).
const WALL_PAINTS := [Color(0.86, 0.80, 0.68), Color(0.90, 0.86, 0.76), Color(0.80, 0.74, 0.62),
	Color(0.84, 0.78, 0.70), Color(0.78, 0.82, 0.78), Color(0.88, 0.80, 0.70)]

static var _cache: Dictionary = {}


static func _h01(parts: Array) -> float:
	return float(absi(hash(parts)) % 100000) / 100000.0


static func _rng(plan: CityPlan, ix: int, iz: int, tag: String) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash([plan.seed, ix, iz, "parks", tag])
	return r


static func perp(u: Vector2) -> Vector2:
	return Vector2(-u.y, u.x)


## A point in a facility's frame (a along u, b along v), world XZ.
static func fp(f: Dictionary, a: float, b: float) -> Vector2:
	var u: Vector2 = f.u
	return (f.c as Vector2) + u * a + perp(u) * b


## The world rect of a facility's (a0..a1, b0..b1) piece (u is axis-aligned).
static func frect(f: Dictionary, a0: float, a1: float, b0: float, b1: float) -> Rect2:
	var p := fp(f, a0, b0)
	var q := fp(f, a1, b1)
	var lo := Vector2(minf(p.x, q.x), minf(p.y, q.y))
	return Rect2(lo, Vector2(maxf(p.x, q.x), maxf(p.y, q.y)) - lo)


## Whether a rect's x side is the one `length` long (a row of courts runs its courts across it).
static func _along_x(r: Rect2, length: float) -> bool:
	return absf(r.size.x - length) < 0.01


static func _fac(t: String, r: Rect2, long_x: bool, flip: bool = false) -> Dictionary:
	var u := Vector2(1.0, 0.0) if long_x else Vector2(0.0, 1.0)
	if flip:
		u = -u
	return {"t": t, "r": r, "c": r.get_center(), "u": u, "L": r.size.x if long_x else r.size.y, "W": r.size.y if long_x else r.size.x}


# --- Roles --------------------------------------------------------------------------------------

## CityPlan.block()'s question, before it caches the block: "", "rec" or "school". Must not ask the
## plan for this block (it is being made).
static func role_for(plan: CityPlan, ix: int, iz: int, rect: Rect2, district: int, kind: int) -> String:
	var macro: MacroMap = plan.macro
	if macro == null:
		return ""
	if not (district in REC_DISTRICTS):
		return ""
	if kind != CityPlan.BlockKind.PARK and kind != CityPlan.BlockKind.BUILDINGS:
		return ""
	var inner := rect.grow(-plan.sidewalk_width)
	var short := minf(inner.size.x, inner.size.y)
	var long := maxf(inner.size.x, inner.size.y)
	if short < REC_MIN.x or long < REC_MIN.y:
		return ""
	# Only on plain city ground, away from everything with its own claim on a block.
	for p: Vector2 in [rect.position, rect.end, Vector2(rect.end.x, rect.position.y), Vector2(rect.position.x, rect.end.y), rect.get_center()]:
		if macro.zone_at(p) != MacroMap.Zone.CITY:
			return ""
	if DowntownReal.in_extent(rect.get_center()) or Landmarks.claims(rect):
		return ""
	if macro.freeway and macro.freeway.blocks_rect(rect, 6.0):
		return ""
	# Nor where the light rail's aerial structure or trench crosses the block.
	var rail := LightRail.of(plan)
	if rail != null and (rail.blocks_rect(rect, 6.0) or not rail.cuts_in(rect).is_empty()):
		return ""
	if macro.runway_clear_zone().grow(60.0).intersects(rect):
		return ""
	if macro.replica and macro.replica._bounds.intersects(rect.grow(40.0)):
		return ""
	if not plan.site_at_block(ix, iz).is_empty() or plan._beside_site(ix, iz):
		return ""
	for lm in Landmarks.all():
		if lm.get("area") is Dictionary:
			continue
		var r: float = lm.radius
		if Rect2((lm.anchor as Vector2) - Vector2(r, r), Vector2(r, r) * 2.0).intersects(rect):
			return ""
	var roll := _h01([plan.seed, ix, iz, "parks_role"])
	if kind == CityPlan.BlockKind.PARK:
		return "rec" if roll < REC_ON_PARK else ""
	var school: float = SCHOOL_ODDS.get(district, 0.0)
	if roll < school and short >= SCHOOL_MIN.x and long >= SCHOOL_MIN.y:
		return "school"
	if roll < school + float(REC_ON_BUILDINGS.get(district, 0.0)):
		return "rec"
	return ""


## The plan of a block with a role ({} for any other block).
static func plan_for(plan: CityPlan, ix: int, iz: int) -> Dictionary:
	var b := plan.block(ix, iz)
	match b.get("grounds", ""):
		"rec":
			return rec_plan(plan, ix, iz)
		"school":
			return school_plan(plan, ix, iz)
	return {}


# --- Packing ------------------------------------------------------------------------------------

## A free spot for a w x h rect (either way round when `turn`) in `area` clear of `placed` by
## `gap`: candidate corners at the area's edges and against what is placed (bottom-left fill),
## the one touching most edges and nearest `toward` wins. {} when nothing fits.
static func _fit(area: Rect2, placed: Array, w: float, h: float, gap: float, turn: bool, toward: Vector2) -> Dictionary:
	var best := {}
	var best_score := INF
	var sizes: Array[Vector2] = [Vector2(w, h)]
	if turn and absf(w - h) > 0.01:
		sizes.append(Vector2(h, w))
	for sz: Vector2 in sizes:
		if sz.x > area.size.x + 0.01 or sz.y > area.size.y + 0.01:
			continue
		var xs: Array[float] = [area.position.x, area.end.x - sz.x]
		var zs: Array[float] = [area.position.y, area.end.y - sz.y]
		for p: Rect2 in placed:
			xs.append(p.end.x + gap)
			xs.append(p.position.x - gap - sz.x)
			zs.append(p.end.y + gap)
			zs.append(p.position.y - gap - sz.y)
		for x: float in xs:
			if x < area.position.x - 0.01 or x + sz.x > area.end.x + 0.01:
				continue
			for z: float in zs:
				if z < area.position.y - 0.01 or z + sz.y > area.end.y + 0.01:
					continue
				var r := Rect2(x, z, sz.x, sz.y)
				var ok := true
				for p: Rect2 in placed:
					if p.grow(gap - 0.02).intersects(r):
						ok = false
						break
				if not ok:
					continue
				var edges := 0
				if absf(x - area.position.x) < 0.05 or absf(x + sz.x - area.end.x) < 0.05:
					edges += 1
				if absf(z - area.position.y) < 0.05 or absf(z + sz.y - area.end.y) < 0.05:
					edges += 1
				var score := -float(edges) * 1000.0 + r.get_center().distance_to(toward)
				if score < best_score:
					best_score = score
					best = {"r": r, "long_x": sz.x >= sz.y}
	return best


## The pieces of `area` not under `holes` (axis-aligned cuts), dropping slivers under `min_side`.
static func minus(area: Rect2, holes: Array, min_side: float = 0.3) -> Array[Rect2]:
	var out: Array[Rect2] = [area]
	for h: Rect2 in holes:
		var next: Array[Rect2] = []
		for r: Rect2 in out:
			if not r.intersects(h):
				next.append(r)
				continue
			var i := r.intersection(h)
			if i.position.y > r.position.y:
				next.append(Rect2(r.position.x, r.position.y, r.size.x, i.position.y - r.position.y))
			if i.end.y < r.end.y:
				next.append(Rect2(r.position.x, i.end.y, r.size.x, r.end.y - i.end.y))
			if i.position.x > r.position.x:
				next.append(Rect2(r.position.x, i.position.y, i.position.x - r.position.x, i.size.y))
			if i.end.x < r.end.x:
				next.append(Rect2(i.end.x, i.position.y, r.end.x - i.end.x, i.size.y))
		out = next
	var kept: Array[Rect2] = []
	for r: Rect2 in out:
		if r.size.x >= min_side and r.size.y >= min_side:
			kept.append(r)
	return kept


## Which side of `inner` a rect is nearest: 0 -z (north), 1 +z, 2 -x, 3 +x.
static func near_side(inner: Rect2, r: Rect2) -> int:
	var d := [r.position.y - inner.position.y, inner.end.y - r.end.y, r.position.x - inner.position.x, inner.end.x - r.end.x]
	var best := 0
	for i in 4:
		if float(d[i]) < float(d[best]):
			best = i
	return best


# --- Rec park -----------------------------------------------------------------------------------

static func rec_plan(plan: CityPlan, ix: int, iz: int) -> Dictionary:
	var key := "rec_%d_%d_%d" % [plan.seed, ix, iz]
	if _cache.has(key):
		return _cache[key]
	var b := plan.block(ix, iz)
	var site: Rect2 = (b.rect as Rect2).grow(-plan.sidewalk_width)
	var work := site.grow(-REC_BORDER)
	var rng := _rng(plan, ix, iz, "rec")
	var placed: Array = []
	var fac: Array = []
	var corners := [work.position, Vector2(work.end.x, work.position.y), work.end, Vector2(work.position.x, work.end.y)]
	var corner: int = rng.randi() % 4
	var toward: Vector2 = corners[corner]
	var opposite: Vector2 = corners[(corner + 2) % 4]
	# The diamond in a corner: home plate in the corner, the foul lines along the two edges.
	var short := minf(work.size.x, work.size.y)
	if short >= 52.0 and rng.randf() < 0.82:
		var fence := clampf(short - BACKSTOP - 4.0, FENCE_RADIUS.x, FENCE_RADIUS.y)
		var side := fence + BACKSTOP + 1.5
		if side <= short:
			fac.append(_diamond(work, corner, fence))
			placed.append((fac.back() as Dictionary).r)
	# Then the rest, the big ones first, each where it fits.
	var want: Array = []
	if rng.randf() < 0.7:
		want.append("soccer")
	want.append("basketball")
	if rng.randf() < 0.7:
		want.append("tennis")
	want.append("playground")
	if rng.randf() < 0.55:
		want.append("rec_centre")
	if rng.randf() < 0.45:
		want.append("pool")
	want.append("parking")
	want.append("picnic")
	want.append("picnic")
	for t: String in want:
		var f := {}
		match t:
			"soccer":
				for sz: Vector2 in [Vector2(100.0, 64.0), Vector2(90.0, 55.0), Vector2(75.0, 48.0), Vector2(64.0, 40.0), Vector2(55.0, 36.0)]:
					var fit := _fit(work, placed, sz.x + SOCCER_RUNOFF * 2.0, sz.y + SOCCER_RUNOFF * 2.0, 3.0, true, opposite)
					if not fit.is_empty():
						f = _fac("soccer", fit.r, fit.long_x)
						f.field = sz
						break
			"basketball":
				var n := 2 if rng.randf() < 0.65 else 1
				for m in range(n, 0, -1):
					var fit := _fit(work, placed, BB_COURT.x + BB_CLEAR * 2.0, (BB_COURT.y + BB_CLEAR * 2.0) * m, 2.5, true, toward.lerp(opposite, 0.5))
					if not fit.is_empty():
						f = _fac("basketball", fit.r, _along_x(fit.r, BB_COURT.x + BB_CLEAR * 2.0))
						f.n = m
						f.pal = rng.randi() % BB_PALETTES.size()
						break
			"tennis":
				var n := 2 + (1 if rng.randf() < 0.3 else 0)
				for m in range(n, 0, -1):
					var fit := _fit(work, placed, TEN_ENCLOSURE.x, TEN_ENCLOSURE.y * m, 2.5, true, opposite)
					if not fit.is_empty():
						f = _fac("tennis", fit.r, _along_x(fit.r, TEN_ENCLOSURE.x))
						f.n = m
						f.pal = rng.randi() % TEN_PALETTES.size()
						break
			"playground":
				var fit := _fit(work, placed, 22.0, 16.0, 3.0, true, toward.lerp(opposite, 0.3))
				if not fit.is_empty():
					f = _fac("playground", fit.r, fit.long_x)
					f.pal = rng.randi() % 4
			"rec_centre":
				var fit := _fit(work, placed, 30.0, 17.0, 3.0, true, site.get_center())
				if not fit.is_empty():
					f = _fac("rec_centre", fit.r, fit.long_x)
					f.storeys = 1
					f.paint = WALL_PAINTS[rng.randi() % WALL_PAINTS.size()]
			"pool":
				var fit := _fit(work, placed, POOL.x + POOL_DECK * 2.0 + 2.0, POOL.y + POOL_DECK * 2.0 + 2.0, 3.0, true, site.get_center())
				if not fit.is_empty():
					f = _fac("pool", fit.r, fit.long_x)
			"parking":
				# Against a street, so the car park has its way in.
				for sz: Vector2 in [Vector2(40.0, 19.0), Vector2(28.0, 19.0)]:
					var fit := _fit(work.grow(REC_BORDER - 0.5), placed, sz.x, sz.y, 3.0, true, toward)
					if not fit.is_empty():
						var r: Rect2 = fit.r
						if minf(minf(r.position.y - site.position.y, site.end.y - r.end.y), minf(r.position.x - site.position.x, site.end.x - r.end.x)) < 1.0:
							f = _fac("parking", r, fit.long_x)
							break
			"picnic":
				var fit := _fit(work, placed, 11.0, 8.0, 4.0, true, opposite.lerp(toward, rng.randf()))
				if not fit.is_empty():
					f = _fac("picnic", fit.r, fit.long_x)
		if not f.is_empty():
			fac.append(f)
			placed.append(f.r)
	var out := {"role": "rec", "site": site, "work": work, "fac": fac,
		"lit": _h01([plan.seed, ix, iz, "parks_lit"]) < 0.8,
		"walk": site.grow(-(REC_BORDER - WALK_W) * 0.5 - WALK_W * 0.5)}
	_cache[key] = out
	return out


## A diamond with home plate in `corner` of `work` (0 NW, 1 NE, 2 SE, 3 SW) and the fence at
## `fence` metres: its frame's u runs down the first-base line, v down the third.
static func _diamond(work: Rect2, corner: int, fence: float) -> Dictionary:
	var us := [Vector2(1.0, 0.0), Vector2(0.0, 1.0), Vector2(-1.0, 0.0), Vector2(0.0, -1.0)]
	var cs := [work.position, Vector2(work.end.x, work.position.y), work.end, Vector2(work.position.x, work.end.y)]
	var u: Vector2 = us[corner]
	var v := perp(u)
	var side := fence + BACKSTOP + 1.5
	var home: Vector2 = (cs[corner] as Vector2) + (u + v) * BACKSTOP
	var f := {"t": "diamond", "u": u, "c": home, "home": home, "fence": fence, "side": side}
	f.r = frect(f, -BACKSTOP, side - BACKSTOP, -BACKSTOP, side - BACKSTOP)
	f.L = side
	f.W = side
	return f


# --- School ------------------------------------------------------------------------------------

static func school_plan(plan: CityPlan, ix: int, iz: int) -> Dictionary:
	var key := "school_%d_%d_%d" % [plan.seed, ix, iz]
	if _cache.has(key):
		return _cache[key]
	var b := plan.block(ix, iz)
	var site: Rect2 = (b.rect as Rect2).grow(-plan.sidewalk_width)
	var rng := _rng(plan, ix, iz, "school")
	var fac: Array = []
	var long_x := site.size.x >= site.size.y
	var long := maxf(site.size.x, site.size.y)
	var short := minf(site.size.x, site.size.y)
	# The front: the wings along one of the short ends when the block is long enough for a track
	# behind them (a high school), else along a long side (an elementary school round its yard).
	var high := long >= 140.0 and short >= 72.0
	var front: int
	if high:
		front = (2 if rng.randf() < 0.5 else 3) if long_x else (0 if rng.randf() < 0.5 else 1)
	else:
		front = (0 if rng.randf() < 0.5 else 1) if long_x else (2 if rng.randf() < 0.5 else 3)
	var colour_i := rng.randi() % SCHOOL_COLORS.size()
	var colour: Color = SCHOOL_COLORS[colour_i]
	var paint: Color = WALL_PAINTS[rng.randi() % WALL_PAINTS.size()]
	var storeys := 2 if high or rng.randf() < 0.45 else 1
	# The front strip: the drop-off loop on the street, then the wings with their walkway.
	var strip := DROPOFF_DEPTH + WING_DEPTH + WALKWAY
	var front_r := _strip(site, front, strip)
	var rest := _strip_rest(site, front, strip)
	# Along the front: the car park at one end (a third), the drop-off loop and wings beside it.
	var along := front_r.size.x if front <= 1 else front_r.size.y
	var park_len := clampf(along * 0.3, 24.0, 44.0)
	var park_at_start := rng.randf() < 0.5
	var park_r := _sub_along(front_r, front, 0.0 if park_at_start else along - park_len, park_len)
	var wings_r := _sub_along(front_r, front, park_len + 2.0 if park_at_start else 0.0, along - park_len - 2.0)
	fac.append(_fac("parking", park_r, front <= 1))
	var drop := _strip(wings_r, front, DROPOFF_DEPTH)
	var wing_band := _strip_rest(wings_r, front, DROPOFF_DEPTH)
	var dropf := _fac("dropoff", drop, front <= 1)
	dropf.front = front
	fac.append(dropf)
	# Wings: runs of 26-48 m with 6 m breezeways between.
	var band_len := wing_band.size.x if front <= 1 else wing_band.size.y
	var at := 0.0
	while band_len - at >= 18.0:
		var len := minf(rng.randf_range(26.0, 48.0), band_len - at)
		if band_len - at - len < 18.0:
			len = band_len - at
		var wr := _sub_along(wing_band, front, at, len)
		var w := _fac("wing", wr, front <= 1)
		w.front = front
		w.storeys = storeys
		w.paint = paint
		w.trim = colour
		fac.append(w)
		at += len + 6.0
	var placed: Array = []
	if high:
		var t := _track(rest, rng)
		if not t.is_empty():
			t.colour = colour
			fac.append(t)
			placed.append(t.r)
			# The bleachers on the home straight's outside, the press box over them.
			if t.has("stands"):
				var s := _fac("bleachers", t.stands, t.stands.size.x >= t.stands.size.y)
				s.big = true
				s.colour = colour
				s.facing = t.c
				fac.append(s)
				placed.append(s.r)
	# The yard: asphalt with courts and games painted on; for an elementary school a grass field
	# and a playground as well; bungalows (portable classrooms) along its edge.
	var yard_area := rest.grow(-2.0)
	var court := _fit(yard_area, placed, BB_COURT.x + BB_CLEAR * 2.0, (BB_COURT.y + BB_CLEAR * 2.0) * 2.0, 1.0, true, front_r.get_center())
	if not court.is_empty():
		var f := _fac("basketball", court.r, _along_x(court.r, BB_COURT.x + BB_CLEAR * 2.0))
		f.n = 2
		f.yard = true
		f.pal = 0
		fac.append(f)
		placed.append(f.r)
	if not high:
		var field := {}
		for sz: Vector2 in [Vector2(75.0, 48.0), Vector2(60.0, 40.0), Vector2(48.0, 32.0), Vector2(40.0, 26.0)]:
			field = _fit(yard_area, placed, sz.x + 6.0, sz.y + 6.0, 4.0, true, rest.get_center() * 2.0 - front_r.get_center())
			if not field.is_empty():
				var f := _fac("soccer", field.r, field.long_x)
				f.field = sz
				fac.append(f)
				placed.append(f.r)
				break
		var pg := _fit(yard_area, placed, 20.0, 14.0, 3.0, true, front_r.get_center())
		if not pg.is_empty():
			var f := _fac("playground", pg.r, pg.long_x)
			f.pal = rng.randi() % 4
			fac.append(f)
			placed.append(f.r)
	var games := _fit(yard_area, placed, 16.0, 12.0, 2.0, true, front_r.get_center())
	if not games.is_empty():
		var f := _fac("games", games.r, games.long_x)
		fac.append(f)
		placed.append(f.r)
	for i in rng.randi_range(1, 3):
		var bung := _fit(yard_area, placed, 12.5, 7.5, 3.0, true, rest.get_center())
		if bung.is_empty():
			break
		var f := _fac("bungalow", bung.r, bung.long_x)
		f.paint = paint
		f.trim = colour
		fac.append(f)
		placed.append(f.r)
	var lunch := _fit(yard_area, placed, 16.0, 9.0, 3.0, true, front_r.get_center())
	if not lunch.is_empty():
		fac.append(_fac("lunch", lunch.r, lunch.long_x))
		placed.append((fac.back() as Dictionary).r)
	var out := {"role": "school", "site": site, "rest": rest, "front": front, "front_r": front_r, "fac": fac,
		"high": high, "colour": colour, "colour_i": colour_i, "paint": paint, "lit": high, "yard": yard_area}
	_cache[key] = out
	return out


## The `depth` m strip of `r` along side `side` (0 -z, 1 +z, 2 -x, 3 +x).
static func _strip(r: Rect2, side: int, depth: float) -> Rect2:
	match side:
		0:
			return Rect2(r.position.x, r.position.y, r.size.x, depth)
		1:
			return Rect2(r.position.x, r.end.y - depth, r.size.x, depth)
		2:
			return Rect2(r.position.x, r.position.y, depth, r.size.y)
	return Rect2(r.end.x - depth, r.position.y, depth, r.size.y)


static func _strip_rest(r: Rect2, side: int, depth: float) -> Rect2:
	match side:
		0:
			return Rect2(r.position.x, r.position.y + depth, r.size.x, r.size.y - depth)
		1:
			return Rect2(r.position.x, r.position.y, r.size.x, r.size.y - depth)
		2:
			return Rect2(r.position.x + depth, r.position.y, r.size.x - depth, r.size.y)
	return Rect2(r.position.x, r.position.y, r.size.x - depth, r.size.y)


## The part of a strip along side `side` from `at` metres along it, `len` long.
static func _sub_along(r: Rect2, side: int, at: float, len: float) -> Rect2:
	if side <= 1:
		return Rect2(r.position.x + at, r.position.y, len, r.size.y)
	return Rect2(r.position.x, r.position.y + at, r.size.x, len)


## The biggest track that fits `area` along its long axis: the regulation 400 m (lane 1) when it
## fits, else the inside radius and straights shrunk to fit (300-390 m, as many LA middle-school
## tracks are), with a football field inside at regulation size or scaled to fit, and room left on
## one long side for the bleachers. {} when not even a 200 m track fits.
static func _track(area: Rect2, rng: RandomNumberGenerator) -> Dictionary:
	var long_x := area.size.x >= area.size.y
	var long := maxf(area.size.x, area.size.y)
	var short := minf(area.size.x, area.size.y)
	var lanes := 8 if short >= 104.0 else (6 if short >= 88.0 else 4)
	var stand := 7.0 if short >= 70.0 else 0.0
	var ring := float(lanes) * LANE
	var r := minf(TRACK_R, (short - stand) * 0.5 - ring - TRACK_APRON)
	var s := minf(TRACK_S, long - 2.0 * (r + ring + TRACK_APRON) - 2.0)
	if r < 17.0 or s < 20.0:
		return {}
	var lap := 2.0 * s + TAU * (r + 0.3)
	if lap > 400.0:
		s = (400.0 - TAU * (r + 0.3)) * 0.5
		lap = 400.0
	var ext := Vector2(s + 2.0 * (r + ring + TRACK_APRON), 2.0 * (r + ring + TRACK_APRON))
	# Centred along the area's long axis, against the side away from the stands.
	var stand_side := 1.0 if rng.randf() < 0.5 else -1.0
	var u := Vector2(1.0, 0.0) if long_x else Vector2(0.0, 1.0)
	var c := area.get_center() + perp(u) * (-stand_side * stand * 0.5)
	var size := Vector2(ext.x, ext.y) if long_x else Vector2(ext.y, ext.x)
	var t := _fac("track", Rect2(c - size * 0.5, size), long_x)
	t.S = s
	t.R = r
	t.lanes = lanes
	t.lap = lap
	t.palette = 0 if rng.randf() < 0.85 else 1
	# The football field inside: regulation if it fits within the inside kerb, else scaled.
	var fl := FOOTBALL.x * 0.5
	var fw := FOOTBALL.y * 0.5
	var scale := 1.0
	for i in 40:
		var hl := fl * scale
		var hw := fw * scale
		var reach := s * 0.5 + sqrt(maxf(r * r - hw * hw, 0.0)) - 1.0
		if hw < r - 1.5 and hl <= reach:
			break
		scale -= 0.02
	t.football = scale if scale >= 0.55 else 0.0
	if stand > 0.0:
		# Along the home straight (the -v side when stand_side < 0), outside the lanes.
		var b0 := (r + ring + TRACK_APRON) * stand_side
		var b1 := b0 + stand * stand_side
		t.stands = frect(t, -s * 0.5, s * 0.5, minf(b0, b1), maxf(b0, b1))
		t.stand_side = stand_side
	return t


# --- Build -------------------------------------------------------------------------------------

## Metres the park ground stands over the pavement (the old park's lawn top was 4 cm). The pool's
## water is 3.5 cm under it: anything lower is under the block's pavement slab.
const LIFT := 0.05
## Far colours for the LOD chunks' and the far city's slabs (CityChunk.far_tint() takes 0.6 of
## anything but asphalt, as it does for every textured surface; these are set so the far ground
## lands near what the shader draws).
const FAR_TURF := Color(0.40, 0.62, 0.28)
const FAR_CLAY := Color(0.86, 0.56, 0.40)
const FAR_TRACK := Color(0.95, 0.46, 0.34)
const FAR_POOL := Color(0.40, 0.82, 0.92)
const FAR_DECK := Color(0.88, 0.86, 0.82)
const FAR_RUBBER := Color(0.70, 0.40, 0.32)
const FAR_DG := Color(0.88, 0.76, 0.60)
const FAR_ROOF := Color(0.66, 0.66, 0.64)
## Floodlight pools: LED sports lighting, a cool white.
const FLOOD_TINT := Color(1.0, 0.97, 0.92)
## The most park people a chunk spawns (on top of the block's own walkers, under the crowd cap).
const MAX_PEOPLE := 18


static func wanted(ch: CityChunk, block: Dictionary) -> bool:
	return enabled and ch.zone == MacroMap.Zone.CITY and block.has("grounds") and not block.has("site")


static func _state(ch: CityChunk) -> void:
	if ch._park.is_empty():
		ch._park = {"ground": [], "walls": null, "people": []}


static func _walls(ch: CityChunk) -> SurfaceTool:
	if ch._park.walls == null:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.set_smooth_group(-1)
		ch._park.walls = st
	return ch._park.walls


static func _full(ch: CityChunk) -> bool:
	return ch.level == CityChunk.Level.FULL and not ch.capturing


static func _top(ch: CityChunk, p: Vector2) -> float:
	return CityChunk.SIDEWALK_TOP + LIFT + ch._gy(p.x, p.y)


static func _at(ch: CityChunk, p: Vector2, up: float = 0.0) -> Vector3:
	return Vector3(p.x, _top(ch, p) + up, p.y)


## A frame (ParkKit.frame) at a facility point: x along `x_dir` (unit XZ).
static func _fxf(ch: CityChunk, f: Dictionary, a: float, b: float, x_dir: Vector2, up: float = 0.0) -> Transform3D:
	return ParkKit.frame(_at(ch, fp(f, a, b), up), x_dir)


## One ground piece: the facility frame's (a0..a1, b0..b1) at `kind`; a FULL chunk keeps it for the
## mesh, a LOD chunk or the far city lays it as a slab of `far` (when it is not too small).
static func _ground(ch: CityChunk, f: Dictionary, a0: float, a1: float, b0: float, b1: float, kind: int, g: float, b: float, a: float, uv2: Vector2, far: Color, drop: float = 0.0) -> void:
	if _full(ch):
		ch._park.ground.append([kind, f.c, f.u, a0, a1, b0, b1, Color((float(kind) + 0.5) / 16.0, g, b, a), uv2, drop])
		return
	var r := frect(f, a0, a1, b0, b1)
	if r.size.x < 1.0 or r.size.y < 1.0:
		return
	var c := r.get_center()
	ch._add_slab(Vector3(c.x, CityChunk.SIDEWALK_TOP + LIFT - 0.02, c.y), Vector3(r.size.x, 0.04, r.size.y), far, false)


## A world rect of plain ground (lawn, deck, asphalt, DG) in a frame of its own.
static func _ground_rect(ch: CityChunk, r: Rect2, kind: int, far: Color, g: float = 0.0) -> void:
	var f := {"c": r.get_center(), "u": Vector2(1.0, 0.0)}
	_ground(ch, f, -r.size.x * 0.5, r.size.x * 0.5, -r.size.y * 0.5, r.size.y * 0.5, kind, g, 0.0, 1.0, r.size * 0.5, far)


## A far box (LOD chunks and the far city), and its collision on a LOD chunk.
static func _far_box(ch: CityChunk, r: Rect2, h: float, col: Color, y0: float = 0.0) -> void:
	var c := r.get_center()
	ch._batch.add("lod_box", PropFactory.unit_box(), Transform3D(Basis().scaled(Vector3(r.size.x, h, r.size.y)),
		Vector3(c.x, CityChunk.SIDEWALK_TOP + y0 + h * 0.5, c.y)), col, Color(0.0, 0.0, 0.0, 1.0))
	if not ch.capturing:
		ch._add_lod_shape(Vector3(r.size.x, h, r.size.y), Vector3(c.x, CityChunk.SIDEWALK_TOP + ch._gy(c.x, c.y) + y0 + h * 0.5, c.y))


## A building's collision and occluder (FULL), at the rect's centre over the relief.
static func _solid(ch: CityChunk, r: Rect2, h: float) -> void:
	var c := r.get_center()
	var pos := Vector3(c.x, CityChunk.SIDEWALK_TOP + ch._gy(c.x, c.y) + h * 0.5, c.y)
	ch._add_shape(Vector3(r.size.x, h, r.size.y), pos)
	ch._occluder_boxes.append([Transform3D(), pos, Vector3(r.size.x - 0.6, h, r.size.y - 0.6)])


## A floodlight pole at a facility point aimed at another, its light pool on the field after dark.
static func _flood(ch: CityChunk, p: Vector2, aim: Vector2, h: float, heads: int, pool: float) -> void:
	if not _full(ch):
		return
	ParkKit.floodlight(_walls(ch), _at(ch, p), aim, h, heads)
	var c := p.lerp(aim, 0.55)
	var xf := Transform3D(Basis(Vector3.RIGHT, -PI * 0.5).scaled(Vector3(pool, 1.0, pool)), Vector3(c.x, CityChunk.SIDEWALK_TOP + LIFT + 0.15, c.y))
	ch._batch.add("park_pool", PropFactory.light_pool(FLOOD_TINT, 0.55, 1.8), xf)


## The block step (any tier): the whole rec park or school. Called in place of CityChunk's own park.
static func build(ch: CityChunk, block: Dictionary) -> void:
	if not wanted(ch, block):
		return
	_state(ch)
	var pl := plan_for(ch.plan, ch.ix, ch.iz)
	if pl.is_empty():
		return
	if pl.role == "school":
		_build_school(ch, pl)
	else:
		_build_rec(ch, pl)


static func _build_rec(ch: CityChunk, pl: Dictionary) -> void:
	var site: Rect2 = pl.site
	var full := _full(ch)
	var holes: Array = []
	for f: Dictionary in pl.fac:
		holes.append(f.r)
		_facility(ch, pl, f)
	# The walking loop round the facilities (decomposed granite), less what stands on it.
	var walk: Rect2 = pl.walk
	var strips := [Rect2(walk.position.x, walk.position.y - WALK_W * 0.5, walk.size.x, WALK_W),
		Rect2(walk.position.x, walk.end.y - WALK_W * 0.5, walk.size.x, WALK_W),
		Rect2(walk.position.x - WALK_W * 0.5, walk.position.y + WALK_W * 0.5, WALK_W, walk.size.y - WALK_W),
		Rect2(walk.end.x - WALK_W * 0.5, walk.position.y + WALK_W * 0.5, WALK_W, walk.size.y - WALK_W)]
	var walks: Array = []
	for s: Rect2 in strips:
		for piece in minus(s, holes, 0.5):
			walks.append(piece)
			_ground_rect(ch, piece, G_DG, FAR_DG)
	holes.append_array(walks)
	for piece in minus(site, holes, 0.3):
		_ground_rect(ch, piece, G_LAWN, ch.style.grass, _h01([ch.plan.seed, ch.ix, ch.iz, "lawn_tone"]))
	if not full:
		return
	var blockers: Array[Rect2] = []
	for h: Rect2 in holes:
		blockers.append(h.grow(0.6))
	ch._add_grass(site.grow(-1.0), 0.8, 0.0, blockers)
	_rec_planting(ch, pl, holes)


## Trees, benches and light poles round a rec park's loop, from a private stream.
static func _rec_planting(ch: CityChunk, pl: Dictionary, holes: Array) -> void:
	var rng := _rng(ch.plan, ch.ix, ch.iz, "rec_plant")
	var site: Rect2 = pl.site
	var walk: Rect2 = pl.walk
	var trees := 0
	# A row along the outside of the loop and one along the inside, every 11-15 m.
	for ring: Rect2 in [site.grow(-1.0), walk.grow(-WALK_W * 0.5 - 1.6)]:
		var cs := [ring.position, Vector2(ring.end.x, ring.position.y), ring.end, Vector2(ring.position.x, ring.end.y)]
		for e in 4:
			var a: Vector2 = cs[e]
			var b: Vector2 = cs[(e + 1) % 4]
			var len := a.distance_to(b)
			var t := rng.randf_range(3.0, 8.0)
			while t < len - 2.0 and trees < 60:
				var p := a.lerp(b, t / len)
				t += rng.randf_range(11.0, 15.0)
				var clear := true
				for h: Rect2 in holes:
					if h.grow(1.4).has_point(p):
						clear = false
						break
				if clear:
					ch._add_tree(Vector3(p.x, CityChunk.SIDEWALK_TOP + LIFT, p.y), rng)
					trees += 1
	# Light poles down the loop and benches facing in.
	var cs2 := [walk.position, Vector2(walk.end.x, walk.position.y), walk.end, Vector2(walk.position.x, walk.end.y)]
	for e in 4:
		var a: Vector2 = cs2[e]
		var b: Vector2 = cs2[(e + 1) % 4]
		var len := a.distance_to(b)
		var dir := (b - a) / maxf(len, 0.01)
		var inward := Vector2(-dir.y, dir.x)
		if inward.dot(walk.get_center() - a) < 0.0:
			inward = -inward
		var n := maxi(1, int(len / 34.0))
		for i in n:
			var p := a.lerp(b, (float(i) + 0.5) / float(n))
			var lp := p + inward * (WALK_W * 0.5 + 0.5)
			LotFill._lamp(ch, Vector3(lp.x, CityChunk.SIDEWALK_TOP + LIFT, lp.y))
			if rng.randf() < 0.6:
				var bp := p.lerp(b, 0.5 / float(n)) + inward * (WALK_W * 0.5 + 0.7)
				var clear := true
				for fac: Dictionary in pl.fac:
					if (fac.r as Rect2).grow(0.5).has_point(bp):
						clear = false
				if clear:
					ch._add_bench(Vector3(bp.x, CityChunk.SIDEWALK_TOP + LIFT, bp.y), atan2(inward.x, inward.y))


## One facility of a rec park or a school, at any tier.
static func _facility(ch: CityChunk, pl: Dictionary, f: Dictionary) -> void:
	match f.t:
		"diamond":
			_diamond_build(ch, pl, f)
		"soccer":
			_soccer_build(ch, pl, f)
		"basketball":
			_basketball_build(ch, pl, f)
		"tennis":
			_tennis_build(ch, pl, f)
		"playground":
			_playground_build(ch, f)
		"rec_centre":
			_rec_centre_build(ch, f)
		"pool":
			_pool_build(ch, f)
		"parking":
			LotFill._car_park(ch, f.r, hash([ch.plan.seed, ch.ix, ch.iz, "park_lot"]))
		"picnic":
			_picnic_build(ch, f)
		"dropoff":
			_dropoff_build(ch, pl, f)
		"wing":
			_wing_build(ch, f)
		"track":
			_track_build(ch, pl, f)
		"bleachers":
			_stands_build(ch, f)
		"games":
			_ground(ch, f, -f.L * 0.5, f.L * 0.5, -f.W * 0.5, f.W * 0.5, G_GAMES, 0.0, 0.0, 1.0, Vector2(f.L, f.W) * 0.5, ch.style.asphalt)
		"bungalow":
			_bungalow_build(ch, f)
		"lunch":
			_ground(ch, f, -f.L * 0.5, f.L * 0.5, -f.W * 0.5, f.W * 0.5, G_DECK, 0.0, 0.0, 1.0, Vector2(f.L, f.W) * 0.5, FAR_DECK)
			if _full(ch):
				ParkKit.shelter(_walls(ch), _fxf(ch, f, 0.0, 0.0, f.u), f.L - 1.0, f.W - 1.0, 4, (pl.get("colour", Color(0.2, 0.3, 0.5)) as Color).lightened(0.1))
			else:
				_far_box(ch, f.r.grow(-0.5), 3.3, FAR_ROOF)


static func _diamond_build(ch: CityChunk, pl: Dictionary, f: Dictionary) -> void:
	var fence: float = f.fence
	var side: float = f.side
	if _full(ch):
		_ground(ch, f, -BACKSTOP, side - BACKSTOP, -BACKSTOP, side - BACKSTOP, G_DIAMOND, 0.0, 0.0, 1.0, Vector2(fence, BASE_PATH), FAR_TURF)
	else:
		# The skinned infield (bases plus the arc) and the turf round it, side by side.
		var inf := Rect2(fp(f, -3.0, -3.0), Vector2.ZERO).expand(fp(f, BASE_PATH + 7.0, BASE_PATH + 7.0))
		var whole := f.r as Rect2
		for piece in minus(whole, [inf]):
			_ground_rect(ch, piece, G_TURF, FAR_TURF)
		_ground_rect(ch, inf, G_DG, FAR_CLAY)
		return
	var st := _walls(ch)
	var u: Vector2 = f.u
	var v := perp(u)
	var home := _at(ch, f.home)
	ParkKit.backstop(st, ParkKit.frame(home, u))
	ParkKit.bases(st, ParkKit.frame(home, u), BASE_PATH, PITCH_DIST)
	# Dugouts on the foul side of each line, their backs away from the field.
	ParkKit.dugout(st, _fxf(ch, f, 12.0, -3.2, -u), 7.0)
	ParkKit.dugout(st, _fxf(ch, f, -3.2, 12.0, v), 7.0)
	for d: Vector2 in [fp(f, 12.0, -4.3), fp(f, -4.3, 12.0)]:
		ch._add_shape(Vector3(7.4, 2.4, 2.4), Vector3(d.x, _top(ch, d) + 1.2, d.y), 0.0 if absf(u.x) > 0.5 else PI * 0.5)
	# Bleachers beyond the dugouts, facing the field.
	ParkKit.bleachers(st, _fxf(ch, f, 22.5, -4.2, -u), 7.5, 4)
	ParkKit.bleachers(st, _fxf(ch, f, -4.2, 22.5, v), 7.5, 4)
	# The outfield fence on its arc and low fences down the lines to it; yellow foul poles.
	var segs := 16
	var prev := Vector3.ZERO
	for i in segs + 1:
		var ang := (PI * 0.5) * float(i) / float(segs)
		var q := fp(f, cos(ang) * fence, sin(ang) * fence)
		var p := _at(ch, q)
		if i > 0:
			ParkKit.fence(st, prev, p, 1.8, false)
		prev = p
	for q: Vector2 in [fp(f, fence, 0.0), fp(f, 0.0, fence)]:
		ParkKit.post(st, _at(ch, q), 0.08, 7.0, ParkKit.K_STEEL, Color(0.95, 0.80, 0.10), 8)
	ParkKit.fence(st, _at(ch, fp(f, 17.0, -5.0)), _at(ch, fp(f, fence - 0.5, -5.0)), 1.2, false)
	ParkKit.fence(st, _at(ch, fp(f, -5.0, 17.0)), _at(ch, fp(f, -5.0, fence - 0.5)), 1.2, false)
	if pl.get("lit", false):
		var aim := fp(f, fence * 0.42, fence * 0.42)
		for q: Vector2 in [fp(f, -6.8, 30.0), fp(f, 30.0, -6.8), fp(f, -6.8, fence * 0.72), fp(f, fence * 0.72, -6.8), fp(f, fence * 0.8, fence * 0.8)]:
			_flood(ch, q, aim, 20.0, 6, fence * 0.9)


static func _soccer_build(ch: CityChunk, pl: Dictionary, f: Dictionary) -> void:
	var field: Vector2 = f.field
	_ground(ch, f, -f.L * 0.5, f.L * 0.5, -f.W * 0.5, f.W * 0.5, G_SOCCER, 0.0, 0.0, 1.0, field * 0.5, FAR_TURF.lightened(0.04))
	if not _full(ch):
		return
	var st := _walls(ch)
	var s := clampf(field.y / 68.0, 0.62, 1.0)
	var u: Vector2 = f.u
	var gw := 7.32 if s > 0.85 else (5.5 if s > 0.7 else 4.9)
	var gh := 2.44 if s > 0.85 else 2.0
	ParkKit.soccer_goal(st, _fxf(ch, f, field.x * 0.5, 0.0, -u), gw, gh)
	ParkKit.soccer_goal(st, _fxf(ch, f, -field.x * 0.5, 0.0, u), gw, gh)
	if pl.get("lit", false) and pl.role == "rec":
		for sa: float in [-1.0, 1.0]:
			for sb: float in [-1.0, 1.0]:
				_flood(ch, fp(f, sa * field.x * 0.28, sb * (f.W * 0.5 - 0.6)), fp(f, sa * field.x * 0.12, 0.0), 18.0, 4, field.y * 0.85)


static func _basketball_build(ch: CityChunk, pl: Dictionary, f: Dictionary) -> void:
	var n: int = f.n
	var yard: bool = f.get("yard", false)
	var cw: float = f.W / float(n)
	var pal: int = f.get("pal", 0)
	for k in n:
		var b0: float = -f.W * 0.5 + cw * float(k)
		var fc := {"c": fp(f, 0.0, b0 + cw * 0.5), "u": f.u}
		_ground(ch, fc, -f.L * 0.5, f.L * 0.5, -cw * 0.5, cw * 0.5, G_BASKETBALL, (float(pal) + 0.5) / 8.0, 1.0 if yard else 0.0, 1.0, BB_COURT * 0.5,
			ch.style.asphalt if yard else (BB_PALETTES[pal][1] as Color) * 1.5)
		if not _full(ch):
			continue
		var st := _walls(ch)
		var u: Vector2 = f.u
		ParkKit.hoop(st, _fxf(ch, fc, BB_COURT.x * 0.5, 0.0, -u), not yard and _h01([ch.plan.seed, ch.ix, ch.iz, k, "chain"]) < 0.5)
		ParkKit.hoop(st, _fxf(ch, fc, -BB_COURT.x * 0.5, 0.0, u), not yard and _h01([ch.plan.seed, ch.ix, ch.iz, k, "chain2"]) < 0.5)
	if not _full(ch) or yard:
		return
	if pl.get("lit", false):
		for sa: float in [-1.0, 1.0]:
			for sb: float in [-1.0, 1.0]:
				_flood(ch, fp(f, sa * f.L * 0.3, sb * (f.W * 0.5 - 0.3)), fp(f, sa * f.L * 0.15, 0.0), 9.0, 2, maxf(f.W, 22.0))
	if _h01([ch.plan.seed, ch.ix, ch.iz, "bb_fence"]) < 0.5:
		ParkKit.fence_rect(_walls(ch), ch, f.r, CityChunk.SIDEWALK_TOP + LIFT, 3.0, false, [fp(f, 0.0, -f.W * 0.5), fp(f, 0.0, f.W * 0.5)])


static func _tennis_build(ch: CityChunk, pl: Dictionary, f: Dictionary) -> void:
	var n: int = f.n
	var cw: float = f.W / float(n)
	var pal: int = f.get("pal", 0)
	for k in n:
		var b0: float = -f.W * 0.5 + cw * float(k)
		var fc := {"c": fp(f, 0.0, b0 + cw * 0.5), "u": f.u}
		_ground(ch, fc, -f.L * 0.5, f.L * 0.5, -cw * 0.5, cw * 0.5, G_TENNIS, (float(pal) + 0.5) / 8.0, 0.0, 1.0, Vector2(f.L, cw) * 0.5, (TEN_PALETTES[pal][1] as Color) * 1.5)
		if _full(ch):
			ParkKit.tennis_net(_walls(ch), _fxf(ch, fc, 0.0, 0.0, perp(f.u)))
	if not _full(ch):
		return
	ParkKit.fence_rect(_walls(ch), ch, f.r, CityChunk.SIDEWALK_TOP + LIFT, 3.6, true, [fp(f, -f.L * 0.5 + 3.0, -f.W * 0.5), fp(f, f.L * 0.5 - 3.0, f.W * 0.5)])
	if pl.get("lit", false):
		for sa: float in [-1.0, 1.0]:
			for k in n + 1:
				var b: float = -f.W * 0.5 + cw * float(k)
				_flood(ch, fp(f, sa * f.L * 0.25, b + (0.3 if k == 0 else -0.3)), fp(f, sa * f.L * 0.12, b + (cw * 0.5 if k < n else -cw * 0.5)), 10.0, 2, cw * 1.1)


static func _playground_build(ch: CityChunk, f: Dictionary) -> void:
	_ground(ch, f, -f.L * 0.5, f.L * 0.5, -f.W * 0.5, f.W * 0.5, G_RUBBER, (float(f.get("pal", 0)) + 0.5) / 8.0, 0.0, 1.0, Vector2(f.L, f.W) * 0.5, FAR_RUBBER)
	if not _full(ch):
		return
	var st := _walls(ch)
	var u: Vector2 = f.u
	var set_i: int = f.get("pal", 0)
	ParkKit.play_structure(st, _fxf(ch, f, -f.L * 0.12, -f.W * 0.08, u), set_i)
	ParkKit.swings(st, _fxf(ch, f, f.L * 0.5 - 3.2, 0.0, perp(u)), 4, (ParkKit.PLAY_SETS[set_i % 4] as Array)[0])
	# The curb round the safety surface.
	for e in 4:
		var horiz := e < 2
		var len: float = f.L if horiz else f.W
		var p := fp(f, 0.0, (f.W * 0.5 + 0.08) * (1.0 if e == 0 else -1.0)) if horiz else fp(f, (f.L * 0.5 + 0.08) * (1.0 if e == 2 else -1.0), 0.0)
		ParkKit.box(st, ParkKit.frame(_at(ch, p, -0.05), u if horiz else perp(u)), Vector3(len + 0.32, 0.22, 0.16), ParkKit.K_CONCRETE, ParkKit.CONCRETE)
	var bp := fp(f, -f.L * 0.5 - 1.2, 0.0)
	ch._add_bench(Vector3(bp.x, CityChunk.SIDEWALK_TOP + LIFT, bp.y), atan2(-u.x, -u.y) + PI)


static func _rec_centre_build(ch: CityChunk, f: Dictionary) -> void:
	_ground(ch, f, -f.L * 0.5, f.L * 0.5, -f.W * 0.5, f.W * 0.5, G_DECK, 0.0, 0.0, 1.0, Vector2(f.L, f.W) * 0.5, FAR_DECK)
	var bl: float = f.L - 2.0
	var bw: float = f.W - 5.0
	var h := 5.6
	var br := frect(f, -bl * 0.5, bl * 0.5, -f.W * 0.5 + 1.0, -f.W * 0.5 + 1.0 + bw)
	if not _full(ch):
		_far_box(ch, br, h + 0.8, (f.paint as Color) * 0.8)
		return
	var st := _walls(ch)
	var u: Vector2 = f.u
	var paint: Color = f.paint
	ParkKit.flat_building(st, _fxf(ch, f, 0.0, -f.W * 0.5 + 1.0 + bw * 0.5, u), bl, bw, h, paint, ParkKit.W_CLERESTORY, Color(0.20, 0.30, 0.42))
	# The entry: a glazed bay and a canopy on the open side.
	var front_b: float = -f.W * 0.5 + 1.0 + bw
	ParkKit.box(st, _fxf(ch, f, 0.0, front_b + 0.02, u, 0.0) * Transform3D(Basis(), Vector3(0.0, 1.5, 0.0)), Vector3(6.0, 3.0, 0.06), ParkKit.K_GLASS, Color(0.25, 0.32, 0.38))
	ParkKit.box(st, _fxf(ch, f, 0.0, front_b + 1.5, u, 0.0) * Transform3D(Basis(), Vector3(0.0, 3.35, 0.0)), Vector3(8.0, 0.25, 3.0), ParkKit.K_CANOPY, Color(0.20, 0.30, 0.42), 1.0)
	for s: float in [-1.0, 1.0]:
		ParkKit.post(st, _at(ch, fp(f, s * 3.7, front_b + 2.8)), 0.09, 3.3, ParkKit.K_STEEL, Color(0.20, 0.30, 0.42), 8)
	_solid(ch, br, h)


static func _pool_build(ch: CityChunk, f: Dictionary) -> void:
	var hl := POOL.x * 0.5
	var hw := POOL.y * 0.5
	# The deck round the tank (four pieces, side by side with it), then the water.
	for piece in minus(Rect2(-f.L * 0.5, -f.W * 0.5, f.L, f.W), [Rect2(-hl, -hw, POOL.x, POOL.y)]):
		_ground(ch, f, piece.position.x, piece.end.x, piece.position.y, piece.end.y, G_DECK, 0.0, 0.0, 1.0, Vector2(f.L, f.W) * 0.5, FAR_DECK)
	_ground(ch, f, -hl, hl, -hw, hw, G_POOL, 0.0, 1.6 / 4.0, 1.0, Vector2(hl, hw), FAR_POOL, 0.035)
	if not _full(ch):
		return
	var st := _walls(ch)
	var u: Vector2 = f.u
	var v := perp(u)
	# Coping round the tank, just over the deck, its inner face down to the water.
	for e in 4:
		var horiz := e < 2
		var sgn := 1.0 if e % 2 == 0 else -1.0
		var p := fp(f, 0.0, sgn * (hw + 0.17)) if horiz else fp(f, sgn * (hl + 0.17), 0.0)
		ParkKit.box(st, ParkKit.frame(_at(ch, p, -0.035), u if horiz else v), Vector3((POOL.x if horiz else POOL.y) + 0.68, 0.1, 0.34), ParkKit.K_CONCRETE, Color(0.86, 0.85, 0.82))
	ParkKit.pool_ladder(st, _fxf(ch, f, -hl + 1.2, -hw - 0.05, v))
	ParkKit.pool_ladder(st, _fxf(ch, f, hl - 1.2, hw + 0.05, -v))
	ParkKit.guard_chair(st, _fxf(ch, f, 0.0, -hw - 1.6, u))
	ParkKit.fence_rect(st, ch, f.r.grow(-0.3), CityChunk.SIDEWALK_TOP + LIFT, 1.9, false, [fp(f, -f.L * 0.5 + 0.3, 0.0)])


static func _picnic_build(ch: CityChunk, f: Dictionary) -> void:
	_ground(ch, f, -f.L * 0.5, f.L * 0.5, -f.W * 0.5, f.W * 0.5, G_DECK, 0.0, 0.0, 1.0, Vector2(f.L, f.W) * 0.5, FAR_DECK)
	if not _full(ch):
		_far_box(ch, f.r.grow(-1.2), 3.4, Color(0.42, 0.34, 0.28))
		return
	ParkKit.shelter(_walls(ch), _fxf(ch, f, 0.0, 0.0, f.u), f.L - 2.0, f.W - 2.0, 2, Color(0.36, 0.26, 0.20))


# --- School pieces -------------------------------------------------------------------------------

static func _dropoff_build(ch: CityChunk, pl: Dictionary, f: Dictionary) -> void:
	_ground(ch, f, -f.L * 0.5, f.L * 0.5, -f.W * 0.5, f.W * 0.5, G_ASPHALT, 0.0, 1.0, 1.0, Vector2(f.L, f.W) * 0.5, ch.style.asphalt)
	if not _full(ch):
		return
	var st := _walls(ch)
	var u: Vector2 = f.u
	# The island down the middle of the loop: a kerbed planter, the flagpole and the school's sign.
	var il: float = maxf(f.L - 16.0, 4.0)
	ParkKit.box(st, _fxf(ch, f, 0.0, 0.0, u, 0.0) * Transform3D(Basis(), Vector3(0.0, 0.08, 0.0)), Vector3(il, 0.16, 2.2), ParkKit.K_CONCRETE, ParkKit.CONCRETE)
	ParkKit.post(st, _at(ch, fp(f, -il * 0.5 + 1.0, 0.0)), 0.07, 11.0, ParkKit.K_GALV, Color(0.85, 0.86, 0.86), 8)
	var col: Color = pl.colour
	ParkKit.box(st, _fxf(ch, f, il * 0.5 - 2.0, 0.0, u, 0.0) * Transform3D(Basis(), Vector3(0.0, 0.8, 0.0)), Vector3(3.2, 1.6, 0.5), ParkKit.K_CMU, ParkKit.CMU)
	ParkKit.box(st, _fxf(ch, f, il * 0.5 - 2.0, 0.0, u, 0.0) * Transform3D(Basis(), Vector3(0.0, 1.0, 0.0)), Vector3(2.8, 0.8, 0.56), ParkKit.K_STEEL, col)
	for k in 3:
		var p := fp(f, -il * 0.5 + 3.5 + float(k) * maxf(il - 7.0, 1.0) * 0.5, 0.0)
		LotFill._shrub(ch, Vector3(p.x, CityChunk.SIDEWALK_TOP + LIFT + 0.16, p.y), _rng(ch.plan, ch.ix, ch.iz, "drop_%d" % k))


static func _wing_build(ch: CityChunk, f: Dictionary) -> void:
	# The wing's rect is the building (on the street side) and its covered walkway (the yard side).
	var front: int = f.front
	var r: Rect2 = f.r
	var bld := _strip(r, front, WING_DEPTH)
	var walk := _strip_rest(r, front, WING_DEPTH)
	var h := float(f.storeys) * STOREY
	_ground_rect(ch, walk, G_DECK, FAR_DECK)
	_ground_rect(ch, bld, G_DECK, FAR_DECK)
	if not _full(ch):
		_far_box(ch, bld, h + 0.85, (f.paint as Color) * 0.85)
		return
	var st := _walls(ch)
	var along := Vector2(1.0, 0.0) if front <= 1 else Vector2(0.0, 1.0)
	var c := bld.get_center()
	var len := bld.size.x if front <= 1 else bld.size.y
	ParkKit.flat_building(st, ParkKit.frame(_at(ch, c), along), len, WING_DEPTH, h, f.paint, ParkKit.W_CLASS_DOORS, f.trim)
	# The walkway runs along the yard face.
	var out := [Vector2(0, 1), Vector2(0, -1), Vector2(1, 0), Vector2(-1, 0)][front] as Vector2
	var face := c + out * WING_DEPTH * 0.5
	var a := face - along * len * 0.5
	var b := face + along * len * 0.5
	ParkKit.walkway(st, _at(ch, a), _at(ch, b), Vector3(out.x, 0.0, out.y), WALKWAY, 3.2, f.trim)
	_solid(ch, bld, h)


static func _track_build(ch: CityChunk, pl: Dictionary, f: Dictionary) -> void:
	var lanes: int = f.lanes
	var fb: float = f.football
	if not _full(ch):
		# From afar: the infield's turf (the oval's inside, squared off), the red ring round it.
		var ia: float = f.S * 0.5 + f.R * 0.55
		var ib: float = f.R * 0.8
		var whole := Rect2(-f.L * 0.5, -f.W * 0.5, f.L, f.W)
		_ground(ch, f, -ia, ia, -ib, ib, G_TURF, 0.0, 0.0, 1.0, Vector2.ONE, FAR_TURF)
		for piece in minus(whole, [Rect2(-ia, -ib, ia * 2.0, ib * 2.0)]):
			_ground(ch, f, piece.position.x, piece.end.x, piece.position.y, piece.end.y, G_TRACK, 0.0, 0.0, 1.0, Vector2.ONE, FAR_TRACK)
		return
	_ground(ch, f, -f.L * 0.5, f.L * 0.5, -f.W * 0.5, f.W * 0.5, G_TRACK, float(lanes) / 10.0, (float(pl.get("colour_i", 0)) + 0.5) / 8.0, fb, Vector2(f.S * 0.5, f.R), FAR_TRACK)
	var st := _walls(ch)
	var u: Vector2 = f.u
	if fb > 0.0:
		var hl := FOOTBALL.x * 0.5 * fb
		ParkKit.goal_posts(st, _fxf(ch, f, hl, 0.0, -u), fb)
		ParkKit.goal_posts(st, _fxf(ch, f, -hl, 0.0, u), fb)
	else:
		ParkKit.soccer_goal(st, _fxf(ch, f, f.S * 0.5 + f.R * 0.6, 0.0, -u), 7.32, 2.44)
		ParkKit.soccer_goal(st, _fxf(ch, f, -f.S * 0.5 - f.R * 0.6, 0.0, u), 7.32, 2.44)
	if pl.get("lit", false):
		var ext: float = f.R + float(lanes) * LANE + TRACK_APRON * 0.5
		for sa: float in [-1.0, 0.0, 1.0]:
			for sb: float in [-1.0, 1.0]:
				var a: float = sa * f.S * 0.42
				_flood(ch, fp(f, a, sb * ext), fp(f, a * 0.5, 0.0), 24.0, 8, f.R * 1.5)


static func _stands_build(ch: CityChunk, f: Dictionary) -> void:
	var depth: float = f.W
	var rows := clampi(int((depth - 0.8) / 0.72), 3, 12)
	var top := 0.42 + 0.36 * float(rows - 1)
	if not _full(ch):
		_far_box(ch, f.r, top + 1.0, Color(0.70, 0.71, 0.72))
		return
	var st := _walls(ch)
	# Facing the track: x along the stands, the rows rising away from it.
	var to_track: Vector2 = ((f.facing as Vector2) - (f.c as Vector2))
	var back := -Vector2(0.0, signf(to_track.y)) if absf(f.u.x) > 0.5 else -Vector2(signf(to_track.x), 0.0)
	var x := Vector2(back.y, -back.x)
	var front_c: Vector2 = (f.c as Vector2) - back * depth * 0.5
	var xf := ParkKit.frame(_at(ch, front_c), x)
	ParkKit.bleachers(st, xf, f.L - 2.0, rows, Color(0.80, 0.81, 0.82))
	ParkKit.press_box(st, xf * Transform3D(Basis(), Vector3(0.0, 0.0, 0.3 + 0.72 * float(rows) - 2.6)), minf(14.0, f.L * 0.3), top + 1.0, f.colour)
	ch._add_shape(Vector3(f.r.size.x, top, f.r.size.y), Vector3(f.c.x, _top(ch, f.c) + top * 0.5, f.c.y))


static func _bungalow_build(ch: CityChunk, f: Dictionary) -> void:
	if not _full(ch):
		_far_box(ch, f.r.grow(-0.4), 3.9, (f.paint as Color) * 0.85)
		return
	var st := _walls(ch)
	var u: Vector2 = f.u
	ParkKit.box(st, _fxf(ch, f, 0.0, 0.0, u) * Transform3D(Basis(), Vector3(0.0, 0.3, 0.0)), Vector3(f.L - 0.6, 0.6, f.W - 0.6), ParkKit.K_CMU, ParkKit.CMU.darkened(0.3))
	ParkKit.flat_building(st, _fxf(ch, f, 0.0, 0.0, u, 0.6), f.L - 0.6, f.W - 0.6, 3.0, f.paint, ParkKit.W_BUNGALOW, f.trim)
	ParkKit.beam(st, _at(ch, fp(f, f.L * 0.5 - 0.3, f.W * 0.5 - 0.9), 0.55), _at(ch, fp(f, f.L * 0.5 + 3.4, f.W * 0.5 - 0.9), 0.02), 1.2, 0.12, ParkKit.K_CONCRETE, ParkKit.CONCRETE)
	_solid(ch, f.r.grow(-0.3), 3.9)


static func _build_school(ch: CityChunk, pl: Dictionary) -> void:
	var site: Rect2 = pl.site
	var holes: Array = []
	for f: Dictionary in pl.fac:
		if f.t != "bleachers" and f.t != "bungalow":
			holes.append(f.r)
		_facility(ch, pl, f)
	# The rest of the campus is the yard: asphalt.
	for piece in minus(site, holes, 0.3):
		_ground_rect(ch, piece, G_ASPHALT, ch.style.asphalt)
	if not _full(ch):
		return
	# Chain-link round the campus but along the front (the wings, the drop-off, the car park).
	var st := _walls(ch)
	var front: int = pl.front
	var r := site.grow(-0.25)
	var cs := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
	# Edges in cs order: 0 north (-z), 1 east (+x), 2 south (+z), 3 west (-x); front 0 -z 1 +z 2 -x 3 +x.
	var front_edge: int = [0, 2, 3, 1][front]
	for e in 4:
		if e == front_edge:
			continue
		var a: Vector2 = cs[e]
		var b: Vector2 = cs[(e + 1) % 4]
		var mid := (a + b) * 0.5
		var dir := (b - a).normalized()
		# A gate in the middle of each side.
		ParkKit.fence(st, _at(ch, a), _at(ch, mid - dir * 2.5), 2.4)
		ParkKit.fence(st, _at(ch, mid + dir * 2.5), _at(ch, b), 2.4)
	# A few shade trees in the yard's corners.
	var rng := _rng(ch.plan, ch.ix, ch.iz, "school_trees")
	var yard: Rect2 = pl.yard
	for i in 10:
		var p := Vector2(rng.randf_range(yard.position.x, yard.end.x), rng.randf_range(yard.position.y, yard.end.y))
		var clear := true
		for h: Rect2 in holes:
			if h.grow(3.0).has_point(p):
				clear = false
				break
		if clear and yard.grow(-3.0).has_point(p) and not yard.grow(-12.0).has_point(p):
			ch._add_tree(Vector3(p.x, CityChunk.SIDEWALK_TOP + LIFT, p.y), rng)


# --- Commit ------------------------------------------------------------------------------------

static var _ground_mat: ShaderMaterial
static var _walls_mat: ShaderMaterial


static func ground_material() -> ShaderMaterial:
	if _ground_mat != null:
		return _ground_mat
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/park_ground.gdshader")
	mat.set_shader_parameter("grass_tex", PropFactory.texture("grass", "Color"))
	mat.set_shader_parameter("dirt_tex", PropFactory.texture("hill_dirt", "Color"))
	mat.set_shader_parameter("asphalt_tex", PropFactory.texture("asphalt", "Color"))
	mat.set_shader_parameter("concrete_tex", PropFactory.texture("concrete", "Color"))
	_ground_mat = mat
	return mat


static func walls_material() -> ShaderMaterial:
	if _walls_mat != null:
		return _walls_mat
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/park_walls.gdshader")
	mat.set_shader_parameter("concrete_tex", PropFactory.texture("concrete", "Color"))
	mat.set_shader_parameter("planks_tex", PropFactory.texture("planks", "Color"))
	_walls_mat = mat
	return mat


## The FULL chunk's park ground (one mesh, no shadow) and its upright geometry (one mesh, casting).
## After the batches are added, before they build.
static func commit(ch: CityChunk) -> void:
	if ch._park.is_empty():
		return
	ch._batch.set_no_shadow("park_pool")
	if not ch._park.ground.is_empty():
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for g: Array in ch._park.ground:
			_piece(st, ch, g)
		var mi := MeshInstance3D.new()
		mi.name = "ParkGround"
		mi.mesh = st.commit()
		mi.material_override = ground_material()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ch.add_child(mi)
	if ch._park.walls != null:
		var mi := MeshInstance3D.new()
		mi.name = "ParkWalls"
		mi.mesh = (ch._park.walls as SurfaceTool).commit()
		mi.material_override = walls_material()
		ch.add_child(mi)
	ch._park.walls = null
	ch._park.ground.clear()


## One ground piece as a relief-following grid: UV the facility frame's (a, b), UV2 its numbers,
## TANGENT its u axis (the pool's trace reads it), COLOR what it is.
static func _piece(st: SurfaceTool, ch: CityChunk, g: Array) -> void:
	var c: Vector2 = g[1]
	var u: Vector2 = g[2]
	var a0: float = g[3]
	var a1: float = g[4]
	var b0: float = g[5]
	var b1: float = g[6]
	var col: Color = g[7]
	var uv2: Vector2 = g[8]
	var drop: float = g[9]
	var f := {"c": c, "u": u}
	var r := frect(f, a0, a1, b0, b1)
	var step := 8.0 if LotFill._planar(ch, r) else 4.0
	var na := clampi(ceili((a1 - a0) / step), 1, 40)
	var nb := clampi(ceili((b1 - b0) / step), 1, 40)
	var tan := Plane(u.x, 0.0, u.y, 1.0)
	var top := CityChunk.SIDEWALK_TOP + LIFT - drop
	var pts := PackedVector3Array()
	var uvs := PackedVector2Array()
	for j in nb + 1:
		for i in na + 1:
			var a := lerpf(a0, a1, float(i) / float(na))
			var b := lerpf(b0, b1, float(j) / float(nb))
			var p := fp(f, a, b)
			pts.append(Vector3(p.x, top + ch._gy(p.x, p.y), p.y))
			uvs.append(Vector2(a, b))
	# Faces up whichever way the frame turns (u x v is down or up by the frame's handedness).
	var flip := (Vector3(u.x, 0.0, u.y).cross(Vector3(-u.y, 0.0, u.x))).y > 0.0
	for j in nb:
		for i in na:
			var k00 := j * (na + 1) + i
			var k10 := k00 + 1
			var k01 := k00 + na + 1
			var k11 := k01 + 1
			var order: Array = [k00, k10, k01, k10, k11, k01] if not flip else [k00, k01, k10, k10, k01, k11]
			for k: int in order:
				st.set_normal(Vector3.UP)
				st.set_tangent(tan)
				st.set_color(col)
				st.set_uv(uvs[k])
				st.set_uv2(uv2)
				st.add_vertex(pts[k])


# --- People ------------------------------------------------------------------------------------

## The park's or school's people as build steps (FULL chunks, after the block's walkers): joggers
## round the track's lanes and the rec park's loop, pickup games on the courts and fields, fielders
## on the diamond, parents at the playground, people at the picnic tables. Each is a ParkGoer under
## the city's crowd cap, MAX_PEOPLE at most a chunk; seeds from a private stream.
static func people_steps(ch: CityChunk, block: Dictionary) -> Array[Callable]:
	var steps: Array[Callable] = []
	if not wanted(ch, block) or ch.level != CityChunk.Level.FULL or ch.capturing:
		return steps
	var pl := plan_for(ch.plan, ch.ix, ch.iz)
	if pl.is_empty():
		return steps
	var rng := _rng(ch.plan, ch.ix, ch.iz, "people")
	var want: Array = []
	for f: Dictionary in pl.fac:
		match f.t:
			"basketball":
				var n: int = f.n
				var cw: float = f.W / float(n)
				for k in n:
					if rng.randf() < 0.75:
						var court := frect(f, -f.L * 0.5 + 1.5, f.L * 0.5 - 1.5, -f.W * 0.5 + cw * float(k) + 1.0, -f.W * 0.5 + cw * float(k + 1) - 1.0)
						var group := "bb_%d_%d" % [want.size(), k]
						for i in rng.randi_range(3, 6):
							want.append([ParkGoer.Mode.PLAY, court, group])
						var fc := {"c": fp(f, 0.0, -f.W * 0.5 + cw * (float(k) + 0.5)), "u": f.u}
						want.append([-1, court, group, fc])
			"track":
				for i in rng.randi_range(3, 5):
					var lane := rng.randi_range(0, int(f.lanes) - 1)
					want.append([ParkGoer.Mode.JOG, f.r, f, f.R + 0.35 + float(lane) * LANE])
			"diamond":
				if rng.randf() < 0.7:
					var fence: float = f.fence
					for spot: Vector2 in [Vector2(PITCH_DIST, PITCH_DIST) * 0.70711, Vector2(BASE_PATH - 1.5, 1.5), Vector2(BASE_PATH * 1.05, BASE_PATH * 0.6),
							Vector2(1.5, BASE_PATH - 1.5), Vector2(fence * 0.55, fence * 0.3), Vector2(fence * 0.45, fence * 0.45), Vector2(-1.0, -1.2)]:
						var c := fp(f, spot.x, spot.y)
						want.append([ParkGoer.Mode.FIELD, Rect2(c - Vector2(2.5, 2.5), Vector2(5.0, 5.0))])
			"soccer":
				if rng.randf() < 0.5:
					var field: Vector2 = f.field
					for i in rng.randi_range(4, 7):
						want.append([ParkGoer.Mode.PLAY, frect(f, -field.x * 0.4, field.x * 0.4, -field.y * 0.4, field.y * 0.4)])
			"tennis":
				if rng.randf() < 0.6:
					var cw2: float = f.W / float(f.n)
					for s: float in [-1.0, 1.0]:
						want.append([ParkGoer.Mode.PLAY, frect(f, s * 13.5 - 2.0, s * 13.5 + 2.0, -f.W * 0.5 + 3.0, -f.W * 0.5 + cw2 - 3.0)])
			"playground", "picnic", "games":
				for i in rng.randi_range(2, 4):
					want.append([ParkGoer.Mode.HANG, (f.r as Rect2).grow(-0.8)])
	if pl.role == "rec":
		for i in rng.randi_range(1, 3):
			want.append([ParkGoer.Mode.LOOP, (pl.walk as Rect2).grow(WALK_W * 0.5)])
	var people := 0
	for w: Array in want:
		if int(w[0]) < 0:
			steps.append(func() -> void: _ball(ch, w))
			continue
		if people >= MAX_PEOPLE:
			continue
		people += 1
		var seed_value := rng.randi()
		steps.append(func() -> void: _spawn(ch, w, seed_value))
	return steps


## The ball for a pickup game: the court's players (those spawned under its group), its two rims.
static func _ball(ch: CityChunk, w: Array) -> void:
	var group: String = w[2]
	var players: Array = []
	for p: Node in ch._park.get("people", []):
		if is_instance_valid(p) and p.get_meta("park_group", "") == group:
			players.append(p)
	if players.size() < 2:
		return
	var fc: Dictionary = w[3]
	var b := ParkBall.new()
	b.players = players
	var c: Vector2 = fc.c
	b.court_y = _top(ch, c)
	var rim_a := BB_COURT.x * 0.5 - 1.2 - 0.38
	for s: float in [-1.0, 1.0]:
		var q := fp(fc, s * rim_a, 0.0)
		b.rims.append(Vector3(q.x, _top(ch, q) + ParkBall.RIM_Y, q.y))
	var start: Node3D = players[0]
	b.position = start.position + Vector3(0.3, 0.5, 0.0)
	ch.add_child(b)


static func _spawn(ch: CityChunk, w: Array, seed_value: int) -> void:
	if not ch._take_crowd_room():
		return
	var p := ParkGoer.new()
	if int(w[0]) == ParkGoer.Mode.JOG:
		var f: Dictionary = w[2]
		p.setup_oval(f.c, f.u, f.S * 0.5, float(w[3]), seed_value)
	else:
		p.setup_mode(int(w[0]), w[1], seed_value)
	var start := p._random_ring_point(p._sidewalk)
	if int(w[0]) == ParkGoer.Mode.PLAY or int(w[0]) == ParkGoer.Mode.FIELD or int(w[0]) == ParkGoer.Mode.HANG:
		var r: Rect2 = w[1]
		var h := hash([seed_value, "start"])
		start = r.position + r.size * Vector2(float(absi(h) % 1000) / 1000.0, float(absi(h / 1000) % 1000) / 1000.0)
	p.position = Vector3(start.x, CityChunk.SIDEWALK_TOP + LIFT + 0.1 + ch._gy(start.x, start.y), start.y)
	if w.size() > 2 and w[2] is String:
		p.set_meta("park_group", w[2])
	ch.add_child(p)
	ch._park.people.append(p)
