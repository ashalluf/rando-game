class_name Footbridges
extends RefCounted
## Pedestrian overcrossings (2026-10-30, fleet task "footbridges"; docs/HANDOFF.md "Footbridges"):
## the caged steel and concrete footbridges Los Angeles puts over its wide boulevards by schools
## and parks, and over the freeways between two neighbourhoods.
##
## WHERE is worked out, never placed, and is PURE (the plan, the freeway, hashes of seed + place;
## no chunk, block or Building rng), so every chunk that a bridge touches asks the same question
## and gets the same bridge:
## * BOULEVARD: a road at least MIN_ROAD_WIDTH wide, the stretch of it between two crossings,
##   with a school or a park on one side (Parks' "rec" / "school", Schools' campuses, PARK and
##   SCHOOL blocks) and BOULEVARD_ODDS of a hash. The bridge crosses square to the road in the
##   middle of the stretch at CLEARANCE_ROAD over the asphalt; on each pavement a landing at the
##   back of it and a straight stair (two flights and a half landing) running along the kerb.
## * FREEWAY: one SLOT of SLOT_SEGMENTS deck segments at a time along each route, tried at the
##   segment indices a hash orders, the first that fits: a straight stretch over city ground, no
##   gantry, other deck, connector or ramp near, CLEARANCE_DECK over the deck top, and on each
##   side a stair TOWER (switchback flights in a caged steel frame) standing on the right of way
##   (only corridor lots, CityChunk._lot_under_freeway()'s rule, never a road, a pavement or a
##   building's lot), FREEWAY_ODDS of the slots.
## A bridge is a Dictionary (see _boulevard() / _freeway()): id, kind, form, paint, c (the span's
## centre, true world XZ), dir (along the span), along (perpendicular: the road's or route's
## direction), half (centre to each span end), y (walkway top, world metres), ends (2 entries:
## {"side", "p" span end, "ground", "foot" what the stair stands on, "stair": its flights}),
## clear (Rect2s, world: what the planting and the street furniture keep off, FootbridgeBuild).

## The A/B switch: FOOTBRIDGES=0 in the environment, none of it.
static var enabled: bool = OS.get_environment("FOOTBRIDGES") != "0"

enum Kind { BOULEVARD, FREEWAY }
## TRUSS: a steel through-truss (Pratt panels) with the chain-link cage arching between its
## chords. GIRDER: a precast box girder with solid parapets and the cage on them.
enum Form { TRUSS, GIRDER }

## Roads at least this wide (the 24 m avenues and the wide real streets) get boulevard bridges.
const MIN_ROAD_WIDTH := 22.0
const BOULEVARD_ODDS := 0.45
## Only every BOULEVARD_EVERY-th stretch of a road may hold one (no two on neighbouring stretches).
const BOULEVARD_EVERY := 3
## A stair or tower climbs at most this (metres): steeper ground, or a deck too high over it, is not
## crossed.
const MAX_STAIR_RISE := 7.4
const MAX_TOWER_RISE := 19.5
## Freeway slots: segments a slot covers (~860 m), and the share of slots that build one.
const SLOT_SEGMENTS := 36
const FREEWAY_ODDS := 0.6
## How many of a slot's segments are tried, in hash order.
const SLOT_TRIES := 36
## Vertical clearance (metres) under the structure: over a boulevard's asphalt (Caltrans' 17 ft
## for a pedestrian overcrossing, plus a hair), and over a freeway deck's top.
const CLEARANCE_ROAD := 5.35
const CLEARANCE_DECK := 5.3
## The walkway's top over the underside of its structure, per form.
const DEPTH := {Form.TRUSS: 0.62, Form.GIRDER: 1.25}
## The walkway's clear width between the rails, and the structure's outside width.
const WALK_W := 2.6
const BRIDGE_W := 3.5
## Stairs: riser (at most), tread, the flight's clear width, the half landing.
const RISER := 0.178
const TREAD := 0.28
const STAIR_W := 1.7
const HALF_LANDING := 1.6
## The top landing: along the span (how far the span's end reaches onto the pavement) and across.
const LANDING_D := 2.2
const LANDING_W := 3.2
## How far from the block's edge (the road's edge) the landing's far face stands: the pavement's
## back half, so the kerb side stays walkable.
const PAVE_BACK := 0.15
## Blocks' corners: the stair and landing keep this far from the crossing roads' kerbs.
const CORNER_CLEAR := 11.0
## Freeway towers: the gap between the deck's edge and the tower, the flights' width, the risers
## a flight, the landings at each end of the tower.
const TOWER_GAP := 2.4
const TOWER_STAIR_W := 1.35
const TOWER_RISERS := 12
const TOWER_LANDING := 1.5
## The top landing (and those under it at the tower's near end): long enough for the span to land.
const TOWER_TOP := 3.9
## The tower's frame and cage stand this far outside the flights.
const TOWER_SKIN := 0.18
## What a stair tower may stand on: ground no further than this from flat (metres over its rect).
const MAX_RELIEF := 1.4
## Clear of the gantries (FreewayKit: every GANTRY_SPACING) and of another deck, connector or
## ramp by this much (metres).
const FREEWAY_KEEP := 4.0
## Paints: the light seafoam, tan, blue-grey and dark green of LA's overcrossings, and galvanised.
const PAINTS := [Color(0.56, 0.68, 0.64), Color(0.66, 0.62, 0.52), Color(0.46, 0.56, 0.66),
	Color(0.30, 0.40, 0.34), Color(0.70, 0.71, 0.70), Color(0.62, 0.66, 0.70)]

static var _cache: Dictionary = {}
## Why freeway spots were turned down, for the probe (reason -> count).
static var rejects: Dictionary = {}


static func _no(reason: String) -> Dictionary:
	rejects[reason] = int(rejects.get(reason, 0)) + 1
	return {}


static func _nob(reason: String) -> bool:
	rejects[reason] = int(rejects.get(reason, 0)) + 1
	return false
static var _cache_seed: int = -2147483648


static func h01(parts: Array) -> float:
	return float(hash(parts) & 0x7fffffff) / 2147483647.0


static func _cached(plan: CityPlan, key: Variant, maker: Callable) -> Variant:
	if plan.seed != _cache_seed:
		_cache.clear()
		_cache_seed = plan.seed
	if not _cache.has(key):
		_cache[key] = maker.call()
	return _cache[key]


## Every bridge whose span centre, landings, stairs or towers come within `margin` of `rect`
## (world XZ). Boulevard bridges by the roads round the blocks the rect reaches, freeway bridges by
## the slots of the deck segments in it.
static func near(plan: CityPlan, rect: Rect2, margin: float = 0.0) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not enabled or plan == null or plan.macro == null:
		return out
	var r := rect.grow(margin + 30.0)
	var lo := plan.block_index_at(r.position)
	var hi := plan.block_index_at(r.end)
	var seen := {}
	for ix in range(lo.x, hi.x + 2):
		for k in range(lo.y - 1, hi.y + 1):
			var b: Dictionary = boulevard_at(plan, CityPlan.AXIS_X, ix, k)
			if not b.is_empty() and not seen.has(b.id):
				seen[b.id] = true
				out.append(b)
	for iz in range(lo.y, hi.y + 2):
		for k in range(lo.x - 1, hi.x + 1):
			var b: Dictionary = boulevard_at(plan, CityPlan.AXIS_Z, iz, k)
			if not b.is_empty() and not seen.has(b.id):
				seen[b.id] = true
				out.append(b)
	var fw: Freeway = plan.macro.freeway
	if fw != null:
		var slots := {}
		for s: Dictionary in fw.segments_in(r):
			if s.has("link"):
				continue
			slots[Vector2i(int(s.route), int(s.index) / SLOT_SEGMENTS)] = true
		for key: Vector2i in slots:
			var b: Dictionary = freeway_slot(plan, key.x, key.y)
			if not b.is_empty() and not seen.has(b.id):
				seen[b.id] = true
				out.append(b)
	var hit: Array[Dictionary] = []
	for b in out:
		if (b.bounds as Rect2).grow(margin).intersects(rect):
			hit.append(b)
	return hit


## The bridges this chunk builds: those whose span centre is in its owned rect.
static func owned_by(plan: CityPlan, ix: int, iz: int) -> Array[Dictionary]:
	var own := plan.owned_rect(ix, iz)
	var out: Array[Dictionary] = []
	for b in near(plan, own):
		if own.has_point(b.c):
			out.append(b)
	return out


# --- Boulevards ---------------------------------------------------------------------------

## The bridge over road (axis, index) on its stretch beside block row/column k (between crossing
## roads k and k + 1 of the other axis), or {}.
static func boulevard_at(plan: CityPlan, axis: int, index: int, k: int) -> Dictionary:
	return _cached(plan, [0, axis, index, k], _boulevard.bind(plan, axis, index, k))


static func _grounds_school_or_park(b: Dictionary) -> bool:
	var g := String(b.get("grounds", ""))
	if g == "rec" or g.begins_with("school"):
		return true
	return int(b.kind) == CityPlan.BlockKind.SCHOOL or (int(b.kind) == CityPlan.BlockKind.PARK and not b.has("site"))


static func _plain_side(plan: CityPlan, b: Dictionary, any_district := false) -> bool:
	if b.has("site") or b.has("hospital") or b.has("chinatown"):
		return false
	if plan.river_block(int(b.ix), int(b.iz)) or plan.marina_block(int(b.ix), int(b.iz)):
		return false
	if not any_district and (int(b.district) == CityPlan.District.DOWNTOWN or int(b.district) == CityPlan.District.INDUSTRIAL):
		return false
	var rep: ReplicaAreas = plan.macro.replica
	if rep != null and rep.block_role(plan, int(b.ix), int(b.iz)) != 0:
		return false
	return true


static func _boulevard(plan: CityPlan, axis: int, index: int, k: int) -> Dictionary:
	var w := plan.road_width(axis, index)
	if w < MIN_ROAD_WIDTH:
		return {}
	if posmod(k + index, BOULEVARD_EVERY) != 0 or h01([plan.seed, "fbr", axis, index, k]) >= BOULEVARD_ODDS:
		return {}
	var other := 1 - axis
	var pos := plan.road_pos(axis, index)
	# The two blocks beside this stretch: (index - 1, k) and (index, k) along the road's axis.
	var b0: Dictionary = plan.block(index - 1, k) if axis == CityPlan.AXIS_X else plan.block(k, index - 1)
	var b1: Dictionary = plan.block(index, k) if axis == CityPlan.AXIS_X else plan.block(k, index)
	if not (_grounds_school_or_park(b0) or _grounds_school_or_park(b1)):
		return {}
	if not (_plain_side(plan, b0) and _plain_side(plan, b1)):
		return {}
	var c0 := plan.road_pos(other, k) + plan.road_width(other, k) * 0.5
	var c1 := plan.road_pos(other, k + 1) - plan.road_width(other, k + 1) * 0.5
	var length := c1 - c0
	var sgn := 1.0 if h01([plan.seed, "fbr_sgn", axis, index, k]) < 0.5 else -1.0
	var form: int = Form.TRUSS if h01([plan.seed, "fbr_form", axis, index, k]) < 0.6 else Form.GIRDER
	# The road's direction (along) and the span's (dir), as world XZ.
	var along := Vector2(0.0, 1.0) if axis == CityPlan.AXIS_X else Vector2(1.0, 0.0)
	var dir := Vector2(1.0, 0.0) if axis == CityPlan.AXIS_X else Vector2(0.0, 1.0)
	var at := func(s: float, t: float) -> Vector2:
		return along * s + dir * t
	# Heights: the walkway clears the road's crown wherever the span crosses it.
	var mid_s := (c0 + c1) * 0.5
	var road_top := -INF
	for f in 5:
		var t := pos + (float(f) / 4.0 - 0.5) * w
		road_top = maxf(road_top, CityChunk.ROAD_TOP + plan.macro.relief_at(at.call(mid_s, t)))
	var y := road_top + CLEARANCE_ROAD + float(DEPTH[form])
	# The stair: risers from the pavement to the walkway, two flights with a half landing.
	var ground := CityChunk.SIDEWALK_TOP + plan.macro.relief_at(at.call(mid_s, pos + w * 0.5 + 2.0))
	var n := int(ceil((y - ground) / RISER))
	var n1 := n / 2
	var n2 := n - n1
	var run := float(n1 - 1 + n2 - 1) * TREAD + HALF_LANDING
	var foot := LANDING_W * 0.5 + run
	# The footprint along the road: from the landing's far side to the stair's foot.
	var need := LANDING_W + run + CORNER_CLEAR * 2.0
	if length < need:
		return {}
	var jitter := (h01([plan.seed, "fbr_at", axis, index, k]) - 0.5) * (length - need) * 0.6
	var s_land := mid_s - sgn * (run * 0.5) + jitter
	s_land = clampf(s_land, c0 + CORNER_CLEAR + LANDING_W * 0.5 + (run if sgn < 0.0 else 0.0),
		c1 - CORNER_CLEAR - LANDING_W * 0.5 - (run if sgn > 0.0 else 0.0))
	var walk := plan.sidewalk_width
	var land_t := w * 0.5 + walk - PAVE_BACK - LANDING_D * 0.5
	var c: Vector2 = at.call(s_land, pos)
	# The road must be open over the whole stretch the bridge touches (a high school's closed street
	# or the river's cut ends are not crossed).
	for s: float in [s_land - LANDING_W, s_land, s_land + sgn * foot]:
		if not plan.road_open(axis, index, s):
			return {}
	if plan.zone_at(c) != MacroMap.Zone.CITY:
		return {}
	var fw: Freeway = plan.macro.freeway
	var span_rect := _rect_of(c, dir, along, land_t + LANDING_D * 0.5 + 0.5, foot + LANDING_W)
	if fw != null and fw.blocks_rect(span_rect, 6.0):
		return {}
	var rail := LightRail.of(plan)
	if rail != null and rail.street_rail(axis, index):
		return {}
	var ends: Array = []
	var clear: Array[Rect2] = []
	for side: float in [-1.0, 1.0]:
		var p: Vector2 = at.call(s_land, pos + side * land_t)
		var g := CityChunk.SIDEWALK_TOP + plan.macro.relief_at(at.call(s_land + sgn * foot, pos + side * land_t))
		if y - g > MAX_STAIR_RISE or y - g < CLEARANCE_ROAD:
			return {}
		# This side's own risers (its foot may stand a little higher or lower than the estimate).
		var ns := int(ceil((y - g) / RISER))
		if absi(ns - n) > 2:
			return {}
		var s1 := ns / 2
		var s2 := ns - s1
		var srun := float(s1 - 1 + s2 - 1) * TREAD + HALF_LANDING
		var flights := _straight_stair(at, s_land, pos + side * land_t, sgn, y, g, s1, s2)
		var landing_c: Vector2 = p
		var lr := _rect_of(landing_c, dir, along, LANDING_D * 0.5, LANDING_W * 0.5)
		var sr := _rect_of(at.call(s_land + sgn * (LANDING_W * 0.5 + srun * 0.5), pos + side * land_t), dir, along, STAIR_W * 0.5 + 0.3, srun * 0.5 + 0.6)
		clear.append(lr.grow(0.6))
		clear.append(sr.grow(0.4))
		ends.append({"side": side, "p": p, "span_end": at.call(s_land, pos + side * (land_t - LANDING_D * 0.5)),
			"ground": g, "landing": {"c": landing_c, "d": LANDING_D, "w": LANDING_W}, "stair": flights,
			"tower": {}})
	# The road under the span: no street tree in the span's way either side of it.
	clear.append(_rect_of(c, dir, along, land_t, BRIDGE_W * 0.5 + 1.2))
	var id := "fb_b_%d_%d_%d" % [axis, index, k]
	var paint: Color = PAINTS[int(h01([plan.seed, "fbr_paint", axis, index, k]) * PAINTS.size()) % PAINTS.size()]
	var bounds := Rect2(c, Vector2.ZERO)
	for r: Rect2 in clear:
		bounds = bounds.merge(r)
	return {"id": id, "kind": Kind.BOULEVARD, "form": form, "paint": paint, "seed": hash([plan.seed, id]),
		"c": c, "dir": dir, "along": along, "half": land_t - LANDING_D * 0.5, "y": y, "ends": ends,
		"clear": clear, "bounds": bounds, "road_top": road_top, "axis": axis, "index": index, "k": k,
		"sgn": sgn}


## A straight stair from the landing at (s_land, t) along the road (`sgn` the way it goes down):
## two flights with a half landing. Each flight: {"top": Vector3 (the centre of its top edge, at
## its top riser's height), "down": Vector2 (the way it descends), "n": risers, "tread", "w"}.
## Landings: {"c": Vector3 (centre, top), "size": Vector2 (along down, across), "down"}.
static func _straight_stair(at: Callable, s_land: float, t: float, sgn: float, y: float, g: float, n1: int, n2: int) -> Dictionary:
	var down: Vector2 = (at.call(1.0, 0.0) as Vector2) * sgn
	var rise := (y - g) / float(n1 + n2)
	var s0 := s_land + sgn * LANDING_W * 0.5
	var top1: Vector2 = at.call(s0, t)
	var f1 := {"top": Vector3(top1.x, y, top1.y), "down": down, "n": n1, "tread": TREAD, "w": STAIR_W, "rise": rise}
	var y_half := y - rise * float(n1)
	var s_half := s0 + sgn * float(n1 - 1) * TREAD
	var hc: Vector2 = at.call(s_half + sgn * HALF_LANDING * 0.5, t)
	var s2 := s_half + sgn * HALF_LANDING
	var top2: Vector2 = at.call(s2, t)
	var f2 := {"top": Vector3(top2.x, y_half, top2.y), "down": down, "n": n2, "tread": TREAD, "w": STAIR_W, "rise": rise}
	return {"flights": [f1, f2], "landings": [{"c": Vector3(hc.x, y_half, hc.y), "size": Vector2(HALF_LANDING, STAIR_W), "down": down}],
		"foot": at.call(s2 + sgn * float(n2 - 1) * TREAD, t)}


## A rect (world, axis-aligned bounds) round a centre with half extents `hd` along `dir` and `ha`
## along `along` (both world axes here, or bounds of a turned one).
static func _rect_of(c: Vector2, dir: Vector2, along: Vector2, hd: float, ha: float) -> Rect2:
	var ex := absf(dir.x) * hd + absf(along.x) * ha
	var ez := absf(dir.y) * hd + absf(along.y) * ha
	return Rect2(c - Vector2(ex, ez), Vector2(ex, ez) * 2.0)


# --- Freeways -----------------------------------------------------------------------------

## The bridge in slot `slot` of route `ri` (SLOT_SEGMENTS segments a slot), or {}.
static func freeway_slot(plan: CityPlan, ri: int, slot: int) -> Dictionary:
	return _cached(plan, [1, ri, slot], _freeway_slot.bind(plan, ri, slot))


static func _freeway_slot(plan: CityPlan, ri: int, slot: int) -> Dictionary:
	if h01([plan.seed, "fbf", ri, slot]) >= FREEWAY_ODDS:
		return {}
	var fw: Freeway = plan.macro.freeway
	var route: Dictionary = fw.routes[ri]
	var count: int = (route.points as PackedVector2Array).size() - 1
	var order: Array = []
	for j in SLOT_SEGMENTS:
		var i := slot * SLOT_SEGMENTS + j
		if i >= 2 and i < count - 2:
			order.append([h01([plan.seed, "fbf_try", ri, i]), i])
	order.sort()
	for k in mini(order.size(), SLOT_TRIES):
		var b := _freeway(plan, ri, int(order[k][1]))
		if not b.is_empty():
			return b
	return {}


static func _freeway(plan: CityPlan, ri: int, i: int) -> Dictionary:
	var fw: Freeway = plan.macro.freeway
	var route: Dictionary = fw.routes[ri]
	var pts: PackedVector2Array = route.points
	var hs: PackedFloat32Array = route.heights
	var width: float = route.width
	var half := width * 0.5
	# Not at a gantry (FreewayKit: idx % gantry_every == 0) or within a segment of one.
	var gantry_every := int(round(Freeway.GANTRY_SPACING / Freeway.STEP))
	for d in range(-1, 3):
		if posmod(i + d, gantry_every) == 0:
			return _no("f1")
	# A straight stretch: the segments either side within a few degrees of this one.
	var a := pts[i]
	var b := pts[i + 1]
	var along := (b - a).normalized()
	for j: int in [i - 1, i + 1]:
		var d2 := (pts[j + 1] - pts[j]).normalized()
		if along.dot(d2) < 0.9985:
			return _no("f2")
	var stack: FreewayStack = fw.stack
	if stack != null:
		for j in range(i - 2, i + 3):
			if stack.covered.has(Vector2i(ri, j)) or stack.open_edges.has(Vector2i(ri, j)):
				return _no("f3")
	var c := (a + b) * 0.5
	var dir := Vector2(-along.y, along.x)
	var deck := maxf(hs[i], hs[i + 1])
	var form: int = Form.TRUSS if h01([plan.seed, "fbf_form", ri, i]) < 0.75 else Form.GIRDER
	var y := deck + CLEARANCE_DECK + float(DEPTH[form])
	var sgn := 1.0 if h01([plan.seed, "fbf_sgn", ri, i]) < 0.5 else -1.0
	var flights_n := 0
	var ends: Array = []
	var clear: Array[Rect2] = []
	var tower_d := TOWER_STAIR_W * 2.0 + 0.2
	var tower_off := half + TOWER_GAP + tower_d * 0.5 + TOWER_SKIN
	var span_half := half + TOWER_GAP
	if plan.zone_at(c) != MacroMap.Zone.CITY:
		return _no("f4")
	# Nothing else of the freeway near: another route's deck, a connector, an off-ramp.
	# The span's line, end to end over both towers.
	var s0 := c - dir * (tower_off + 2.0)
	var s1 := c + dir * (tower_off + 2.0)
	var span_rect := Rect2(c, Vector2.ZERO).expand(s0).expand(s1).grow(4.0)
	for s: Dictionary in fw.segments_in(span_rect.grow(30.0)):
		if int(s.route) == ri:
			continue
		if _seg_seg(s.a, s.b, s0, s1) < float(s.width) * 0.5 + FREEWAY_KEEP:
			return _no("f5")
	for r: Dictionary in fw.ramps_in(span_rect.grow(Freeway.RAMP_RUN + Freeway.RAMP_BOW + FREEWAY_KEEP)):
		var path := Freeway.ramp_path(r)
		for q in path.size() - 1:
			if _seg_seg(path[q], path[q + 1], s0, s1) < Freeway.RAMP_WIDTH * 0.5 + FREEWAY_KEEP:
				return _no("f6")
	var rail := LightRail.of(plan)
	for side: float in [-1.0, 1.0]:
		var tc := c + dir * side * tower_off
		var g := CityChunk.SIDEWALK_TOP + plan.macro.relief_at(tc)
		if y - g > MAX_TOWER_RISE:
			return _no("rise")
		var n := int(ceil((y - g) / RISER))
		var nf := int(ceil(float(n) / float(TOWER_RISERS)))
		flights_n = maxi(flights_n, nf)
		var per := int(ceil(float(n) / float(nf)))
		var run := float(per - 1) * TREAD
		var tower_len := TOWER_TOP + run + TOWER_LANDING
		# The top landing sits where the span arrives (centred on the span's line); the tower runs
		# from it along the route.
		var t_c := tc + along * sgn * (tower_len * 0.5 - TOWER_TOP * 0.5)
		var foot_rect := _turned_rect(t_c, dir, along, tower_d * 0.5 + TOWER_SKIN + 0.4, tower_len * 0.5 + TOWER_SKIN + 0.4)
		if not _tower_ground_ok(plan, foot_rect, t_c, g):
			return _no("f7")
		if rail != null and rail.blocks_rect(foot_rect, 2.0):
			return _no("f8")
		if fw.blocks_rect(foot_rect, 0.6):
			# Its own deck: the tower stands TOWER_GAP outside the edge, so a margin under that
			# is the only thing that can say yes here - another deck or a ramp.
			return _no("f9")
		var stair := _tower_stair(tc, t_c, dir * side, along * sgn, y, g, n, nf, tower_len)
		clear.append(foot_rect.grow(1.6))
		ends.append({"side": side, "p": tc, "span_end": c + dir * side * span_half, "ground": g,
			"landing": {}, "stair": stair,
			"tower": {"c": t_c, "len": tower_len, "d": tower_d, "out": dir * side, "along": along * sgn, "top": y, "g": g}})
	# The span over the deck: trees on the right of way keep out of its line.
	clear.append(_turned_rect(c, dir, along, tower_off, BRIDGE_W * 0.5 + 3.0))
	var id := "fb_f_%d_%d" % [ri, i]
	var paint: Color = PAINTS[int(h01([plan.seed, "fbf_paint", ri, i]) * PAINTS.size()) % PAINTS.size()]
	var bounds := Rect2(c, Vector2.ZERO)
	for r: Rect2 in clear:
		bounds = bounds.merge(r)
	return {"id": id, "kind": Kind.FREEWAY, "form": form, "paint": paint, "seed": hash([plan.seed, id]),
		"c": c, "dir": dir, "along": along, "half": span_half, "y": y, "ends": ends, "clear": clear,
		"bounds": bounds, "deck": deck, "route": ri, "index": i, "sgn": sgn}


## The shortest distance between segments a0-a1 and b0-b1.
static func _seg_seg(a0: Vector2, a1: Vector2, b0: Vector2, b1: Vector2) -> float:
	if Geometry2D.segment_intersects_segment(a0, a1, b0, b1) != null:
		return 0.0
	var best := (Geometry2D.get_closest_point_to_segment(a0, b0, b1) - a0).length()
	best = minf(best, (Geometry2D.get_closest_point_to_segment(a1, b0, b1) - a1).length())
	best = minf(best, (Geometry2D.get_closest_point_to_segment(b0, a0, a1) - b0).length())
	return minf(best, (Geometry2D.get_closest_point_to_segment(b1, a0, a1) - b1).length())


## The world-axis bounds of a rect turned to (dir, along) round `c`.
static func _turned_rect(c: Vector2, dir: Vector2, along: Vector2, hd: float, ha: float) -> Rect2:
	var ex := absf(dir.x) * hd + absf(along.x) * ha
	var ez := absf(dir.y) * hd + absf(along.y) * ha
	return Rect2(c - Vector2(ex, ez), Vector2(ex, ez) * 2.0)


## A stair tower's ground: city zone, flat enough, a plain buildings block's inner ground (never a
## road or a pavement), and every lot it touches a corridor lot - the right of way the freeway
## leaves (CityChunk._lot_under_freeway()'s rule).
static func _tower_ground_ok(plan: CityPlan, r: Rect2, c: Vector2, g: float) -> bool:
	var corners := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y), c]
	var blk := plan.block_index_at(c)
	var block: Dictionary = plan.block(blk.x, blk.y)
	if int(block.kind) != CityPlan.BlockKind.BUILDINGS or not _plain_side(plan, block, true):
		return _nob("t1")
	if block.has("grounds"):
		return _nob("t2")
	var inner: Rect2 = (block.rect as Rect2).grow(-plan.sidewalk_width - 0.5)
	for p: Vector2 in corners:
		if not inner.has_point(p) or plan.zone_at(p) != MacroMap.Zone.CITY:
			return _nob("t3")
		if absf(CityChunk.SIDEWALK_TOP + plan.macro.relief_at(p) - g) > MAX_RELIEF:
			return _nob("t4")
	var fw: Freeway = plan.macro.freeway
	for lot: Dictionary in plan.lots(blk.x, blk.y):
		var size: Vector2 = lot.size
		var lr := Rect2((lot.center as Vector2) - size * 0.5, size)
		if not lr.grow(2.5).intersects(r):
			continue
		if not (fw.blocks(lot.center, 14.0) or fw.blocks_rect(lr, CityChunk.LOT_FREEWAY_MARGIN)):
			return _nob("t5")
	if Alleys.spec(plan, blk.x, blk.y).size() > 0:
		return _nob("t6")
	return true


## The switchback stair inside a tower: u runs along `along` from the span's line (`tc`); the top
## landing (TOWER_TOP long, where the span arrives) and the landings under it hold the near end,
## TOWER_LANDING ones the far end; flights alternate between them, flight k in lane (k % 2): lane 0
## next to the deck (toward -out), lane 1 away from it.
static func _tower_stair(tc: Vector2, t_c: Vector2, out: Vector2, along: Vector2, y: float, g: float,
		n: int, nf: int, tower_len: float) -> Dictionary:
	var flights: Array = []
	var landings: Array = []
	var rise := (y - g) / float(n)
	var per := int(ceil(float(n) / float(nf)))
	var left := n
	var lane_off := (TOWER_STAIR_W + 0.2) * 0.5
	var lane_w := TOWER_STAIR_W * 2.0 + 0.2
	var run := tower_len - TOWER_TOP - TOWER_LANDING
	var near_c := tc
	var far_c := tc + along * (TOWER_TOP * 0.5 + run + TOWER_LANDING * 0.5)
	var yy := y
	landings.append({"c": Vector3(near_c.x, y, near_c.y), "size": Vector2(TOWER_TOP, lane_w), "down": along, "top": true})
	var tread := run / float(maxi(per - 1, 1))
	for k in nf:
		var nk := mini(per, left)
		left -= nk
		var lane := out * (-lane_off if k % 2 == 0 else lane_off)
		var top: Vector2
		var down: Vector2
		if k % 2 == 0:
			top = tc + along * (TOWER_TOP * 0.5) + lane
			down = along
		else:
			top = tc + along * (TOWER_TOP * 0.5 + run) + lane
			down = -along
		flights.append({"top": Vector3(top.x, yy, top.y), "down": down, "n": nk, "tread": tread, "w": TOWER_STAIR_W, "rise": rise})
		yy -= rise * float(nk)
		if k < nf - 1:
			var lc := far_c if k % 2 == 0 else near_c
			var ll := TOWER_LANDING if k % 2 == 0 else TOWER_TOP
			landings.append({"c": Vector3(lc.x, yy, lc.y), "size": Vector2(ll, lane_w), "down": down})
	var lf: Dictionary = flights[flights.size() - 1]
	var lt: Vector3 = lf.top
	var foot := Vector2(lt.x, lt.z) + (lf.down as Vector2) * float(int(lf.n) - 1) * float(lf.tread)
	return {"flights": flights, "landings": landings, "foot": foot, "tc": tc}
