class_name Kerbs
extends RefCounted
## Los Angeles kerbs and pavement edges (2026-10-05, fleet task "kerbs"): the kerb is CUT, not
## painted on. A FULL city block's pavement is laid as an inner slab (CityChunk._block_surface,
## the old slab less a ring `RING` metres wide) plus this ring, built here as real geometry in the
## pavement's own material with collision:
##   * kerb ramps at the corners, two a corner, one in line with each crosswalk (CR_*): the ramp
##     cut down to a lip over the gutter, flared sides, a yellow truncated-dome pad at its foot;
##   * driveway aprons (DR_*) where a yard's driveway (YardFill / HouseKit) meets the street: the
##     kerb dropped to a lip, the apron sloping up across the parkway, flares either side;
##   * tree wells: a street tree's grate (`tree_grate`, now a cast-iron grate on the marks
##     shader) or, by hash, a bare dirt well cut into the slab with its own walls (WELL_*);
##   * slabs heaved and cracked by the roots beside some trees (HEAVE_*), lifted a few
##     centimetres on their hinge, with the crack along it.
## And on the kerb (ONE marks mesh per 64 m tile, shaders/kerb_marks.gdshader): painted zones -
## red at the corners, at hydrants and bus stops, yellow loading, white passenger, green
## short-term, blue disabled - worn through to the concrete, with stencilled limits; and in the
## suburbs and the beach town the house number stencilled on the kerb face in front of each house.
##
## Every roll is a hash of seed + block + edge (+ lot / tree position), never a chunk, block or
## Building rng: nothing else a seed builds moves. The zones and ramps are pure (`edge_zones()`,
## `corner_ramps()`); hydrants, trees and driveways are read off what the chunk already built.
## LOD chunks and the far city keep the plain slab (they never see the ring). `KERBS=0` in the
## environment turns it all off (the A/B). Checks: tests/kerbs_checks.gd; probe tools/kerbs/probe.gd.

static var enabled: bool = OS.get_environment("KERBS") != "0"

## How wide the ring of pavement built here is, from the kerb line inward (metres). Everything the
## ring cuts (ramps, aprons, wells, heaves) must fit inside it.
const RING := 2.6
## Pavement top and road top above the ground (CityChunk's).
const TOP := CityChunk.SIDEWALK_TOP
const ROAD := CityChunk.ROAD_TOP
## How far the kerb face hangs below the road top (buried in the road slab).
const FACE_FOOT := 0.3

## Corner ramps: centre along the kerb from the corner (in line with the crosswalk, which
## CityChunk._add_crosswalks puts 1.8 m out, and clear of the signal pole at 1.2 / 1.2, the corner
## bollards at 0.6 / 1.7 and the kerb inlet at 4 m), half its width, the flares' length along the
## kerb, its run back from the kerb, the lip it leaves over the gutter.
const CR_CENTRE := 2.6
const CR_HALF := 0.55
const CR_FLARE := 0.35
const CR_RUN := 1.1
const CR_LIP := 0.012
## The truncated-dome pad: how far up the ramp it reaches, and its inset from the ramp's sides.
const PAD_DEPTH := 0.61
const PAD_INSET := 0.05

## Driveway aprons: flares, run across the parkway, lip, and the most and least a drive may be.
const DR_FLARE := 0.55
const DR_RUN := 0.85
const DR_LIP := 0.03
const DR_MIN := 2.4
const DR_MAX := 12.0
## Nothing upright may stand within this of a cut (metres): a cut that would undermine a lamp, a
## hydrant, a pole or a tree is not made.
const CLEAR := 0.15

## Tree wells: the share of a district's street trees in a bare dirt well (the rest keep their
## cast-iron grate), the well's size, how deep the dirt sits.
const WELL_DIRT := [0.22, 0.4, 0.75, 0.6, 0.5, 0.7, 0.75]
const WELL_SIZE := 1.25
const WELL_DIRT_DEPTH := 0.035
const WELL_WALL := 0.09
## Root heave: the share of trees that have lifted a slab, and by how much (metres).
const HEAVE_ODDS := 0.45
const HEAVE_LIFT := Vector2(0.018, 0.045)
## Hairline cracks in the slabs round a tree (marks mesh), per tree.
const CRACK_ODDS := 0.6

## Kerb paint colours (sRGB, as the city's paint is written).
const RED := Color(0.70, 0.12, 0.10)
const YELLOW := Color(0.86, 0.66, 0.09)
const WHITE := Color(0.90, 0.90, 0.87)
const GREEN := Color(0.16, 0.48, 0.22)
const BLUE := Color(0.10, 0.30, 0.62)
const DOME_YELLOW := Color(0.88, 0.68, 0.10)
const INK := Color(0.06, 0.06, 0.06)
## Red at both ends of a face: length range (metres from the end of the pavement).
const END_RED := Vector2(4.5, 9.0)
## Red either side of a hydrant (California: 15 ft each way, about 4.6 m).
const HYDRANT_RED := 4.6
## One mid-block zone a face: odds per district (CityPlan.District order: DOWNTOWN, MIDTOWN,
## SUBURBS, INDUSTRIAL, CAMPUS, BEACHTOWN, ...) of [yellow, green, white, blue]. Cumulative.
const ZONE_ODDS := [
	[0.30, 0.55, 0.68, 0.80],
	[0.16, 0.42, 0.54, 0.66],
	[0.0, 0.03, 0.07, 0.11],
	[0.45, 0.48, 0.48, 0.52],
	[0.0, 0.06, 0.32, 0.50],
	[0.04, 0.16, 0.22, 0.30],
	[0.0, 0.03, 0.07, 0.11],
]
## House numbers on the kerb: districts that get them.
const NUMBER_DISTRICTS := [CityPlan.District.SUBURBS, CityPlan.District.BEACHTOWN]
## Marks mesh tiles (metres) and how far they draw.
const TILE := 64.0
const MARKS_DRAW := 230.0
const GLYPH_H := 0.084
const GLYPH_PITCH := 0.072

## Kinds in the marks mesh's COLOR.a (kind / 16 + half a step).
enum Kind { PAINT, DOMES, PLATE, GLYPH, DIRT, GRATE, CRACK, APRON }

## The ring's collision triangles while it is built (a packed array held in a Dictionary is a
## value: appending to it there appends to a copy).
class _Faces:
	var faces := PackedVector3Array()


static var _material: ShaderMaterial
static var _grate: ArrayMesh
static var _glyph_bits := {}


static func _h01(parts: Array) -> float:
	return float(absi(hash(parts)) % 100003) / 100003.0


# --- Hooks ------------------------------------------------------------------------------------------

## Whether this chunk's block gets the cut ring (CityChunk._block_surface asks, and if so lays the
## inner slab only; CityChunk._block_steps then runs build() after the pavement furniture).
static func takes(ch: CityChunk, rect: Rect2) -> bool:
	return enabled and ch.level == CityChunk.Level.FULL and not ch.capturing and ch.zone == MacroMap.Zone.CITY \
			and rect.size.x > RING * 2.0 + 4.0 and rect.size.y > RING * 2.0 + 4.0


## The slab CityChunk lays itself when the ring is ours.
static func inner(rect: Rect2) -> Rect2:
	return rect.grow(-RING)


## Remembers the pavement's material for the ring (the same instance as the inner slab's).
static func begin(ch: CityChunk, rect: Rect2, material: Material) -> void:
	ch.set_meta("kerbs", {"rect": rect, "mat": material, "clear": []})


## True when a parked car standing at `p` (the parking lane, plan coords) would block this
## chunk's own red kerb or a driveway it cut (CityChunk._park_car, after its rolls).
static func blocks_parking(ch: CityChunk, p: Vector3) -> bool:
	if not ch.has_meta("kerbs"):
		return false
	var st: Dictionary = ch.get_meta("kerbs")
	for c: Array in st.clear:
		var a: Vector2 = c[0]
		var b: Vector2 = c[1]
		var q := Vector2(p.x, p.z)
		var ab := b - a
		var t := clampf((q - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
		if (a + ab * t).distance_to(q) < 2.6:
			return true
	return false


# --- The plan (pure) ---------------------------------------------------------------------------------

## The block's four pavement edges [a, b, inward] (CityChunk._sidewalk_edges' order) and the road
## each faces: [axis, index].
static func edge_roads(ix: int, iz: int) -> Array:
	return [[CityPlan.AXIS_Z, iz], [CityPlan.AXIS_Z, iz + 1], [CityPlan.AXIS_X, ix], [CityPlan.AXIS_X, ix + 1]]


## Whether edge `e`'s road is open at `u` metres along it.
static func _open_at(plan: CityPlan, ix: int, iz: int, rect: Rect2, e: int, u: float) -> bool:
	var road: Array = edge_roads(ix, iz)[e]
	var along := (rect.position.x + u) if e < 2 else (rect.position.y + u)
	return plan.road_open(int(road[0]), int(road[1]), along)


## The corner ramps of block (ix, iz): [{e, uc}] - two at each corner whose two roads are open
## there, on the two faces that meet at it. Pure.
static func corner_ramps(plan: CityPlan, ix: int, iz: int, rect: Rect2) -> Array:
	var out: Array = []
	var lens := [rect.size.x, rect.size.x, rect.size.y, rect.size.y]
	for e in 4:
		var length: float = lens[e]
		for end in 2:
			var uc := CR_CENTRE if end == 0 else length - CR_CENTRE
			if not _open_at(plan, ix, iz, rect, e, uc):
				continue
			# The crossing road at that end (the other pair of edges' road on that side).
			var other := (2 if end == 0 else 3) if e < 2 else (0 if end == 0 else 1)
			var cross_u: float = 0.5 if (e == 0 or e == 2) else (float(lens[other]) - 0.5)
			if not _open_at(plan, ix, iz, rect, other, cross_u):
				continue
			out.append({"e": e, "uc": uc})
	return out


## The painted zones of edge `e` of block (ix, iz), pure: [[u0, u1, color, text]]. Red at both ends
## and along any bus stop, then by district one mid-block zone (loading, short-term, passenger,
## disabled) with its stencil. Hydrant zones are the chunk's (build()).
static func edge_zones(plan: CityPlan, ix: int, iz: int, rect: Rect2, e: int, district: int) -> Array:
	var out: Array = []
	var length := rect.size.x if e < 2 else rect.size.y
	if length < 18.0:
		return out
	var red_a := lerpf(END_RED.x, END_RED.y, _h01([plan.seed, ix, iz, e, "kerb_red_a"]))
	var red_b := lerpf(END_RED.x, END_RED.y, _h01([plan.seed, ix, iz, e, "kerb_red_b"]))
	if _open_at(plan, ix, iz, rect, e, 1.0):
		out.append([0.25, red_a, RED, ""])
	if _open_at(plan, ix, iz, rect, e, length - 1.0):
		out.append([length - red_b, length - 0.25, RED, ""])
	# Bus stops: the kerb where nothing may park (BigVehicles.in_stop_zone), sampled a metre out in
	# the carriageway.
	var edges := CityChunk._sidewalk_edges(rect)
	var a: Vector2 = edges[e][0]
	var b: Vector2 = edges[e][1]
	var n: Vector2 = edges[e][2]
	var dir := (b - a) / length
	var run_start := -1.0
	var u := red_a + 1.0
	var road: Array = edge_roads(ix, iz)[e]
	if BigVehicles.route_of(plan, int(road[0]), int(road[1])) == 0:
		u = length
	while u < length - red_b - 1.0:
		var q := a + dir * u - n * 1.4
		var stop := BigVehicles.in_stop_zone(plan, q)
		if stop and run_start < 0.0:
			run_start = u
		elif not stop and run_start >= 0.0:
			out.append([run_start, u, RED, ""])
			run_start = -1.0
		u += 1.0
	if run_start >= 0.0:
		out.append([run_start, u, RED, ""])
	# One zone mid-block, by district.
	var odds: Array = ZONE_ODDS[clampi(district, 0, ZONE_ODDS.size() - 1)]
	var roll := _h01([plan.seed, ix, iz, e, "kerb_zone"])
	var kind := -1
	for k in odds.size():
		if roll < float(odds[k]):
			kind = k
			break
	if kind >= 0:
		var runs := [Vector2(7.0, 14.0), Vector2(6.0, 12.0), Vector2(6.0, 10.0), Vector2(6.0, 7.0)]
		var run := lerpf(runs[kind].x, runs[kind].y, _h01([plan.seed, ix, iz, e, "kerb_zone_len"]))
		var lo := red_a + 4.0
		var hi := length - red_b - run - 4.0
		if hi > lo:
			var u0 := lerpf(lo, hi, _h01([plan.seed, ix, iz, e, "kerb_zone_at"]))
			var color: Color = [YELLOW, GREEN, WHITE, BLUE][kind]
			var text := ""
			match kind:
				0:
					text = "LOADING ZONE" if _h01([plan.seed, ix, iz, e, "kerb_txt"]) < 0.6 else "COMMERCIAL LOADING"
				1:
					text = ["15 MIN", "20 MIN", "30 MIN"][int(_h01([plan.seed, ix, iz, e, "kerb_txt"]) * 2.999)]
				2:
					text = "PASSENGER LOADING"
			var clash := false
			for z: Array in out:
				if u0 < float(z[1]) + 2.0 and u0 + run > float(z[0]) - 2.0:
					clash = true
			if not clash:
				out.append([u0, u0 + run, color, text])
	return out


## Zones as painted: overlaps of one colour merged, and red (no stopping) cut out of any other
## colour it overlaps, so no two coats ever lie on the same stretch of kerb. Pure.
static func resolve(zones: Array) -> Array:
	var red: Array = []
	var rest: Array = []
	for z: Array in zones:
		(red if z[2] == RED else rest).append(z.duplicate())
	red.sort_custom(func(p: Array, q: Array) -> bool: return float(p[0]) < float(q[0]))
	var merged: Array = []
	for z: Array in red:
		if not merged.is_empty() and float(z[0]) <= float(merged[-1][1]) + 0.3:
			merged[-1][1] = maxf(float(merged[-1][1]), float(z[1]))
		else:
			merged.append(z)
	var out: Array = merged.duplicate()
	for z: Array in rest:
		var spans: Array = [[float(z[0]), float(z[1])]]
		for r: Array in merged:
			var next: Array = []
			for s: Array in spans:
				var a := float(r[0]) - 0.3
				var b := float(r[1]) + 0.3
				if b <= s[0] or a >= s[1]:
					next.append(s)
					continue
				if a > s[0]:
					next.append([s[0], a])
				if b < s[1]:
					next.append([b, s[1]])
			spans = next
		for s: Array in spans:
			if float(s[1]) - float(s[0]) > 1.5:
				# The stencil only on the piece that keeps the zone's start.
				out.append([s[0], s[1], z[2], z[3] if absf(float(s[0]) - float(z[0])) < 0.01 else ""])
	return out


## The street number of the house whose frontage centre is `u` metres along edge `e`: hundreds
## from the block's place along the street, even on one side and odd on the other, rising with u.
static func house_number(plan: CityPlan, ix: int, iz: int, rect: Rect2, e: int, u: float) -> int:
	var length := rect.size.x if e < 2 else rect.size.y
	var block_idx := ix if e < 2 else iz
	var base := (absi(block_idx + 40) % 98 + 1) * 100
	var slot := clampi(int(u / maxf(length, 1.0) * 48.0), 0, 47)
	return base + slot * 2 + (1 if e == 1 or e == 3 else 0)


# --- The build step ---------------------------------------------------------------------------------

## The ring, its cuts and the kerb marks (a FULL chunk's block step, after the pavement furniture).
static func build(ch: CityChunk, block: Dictionary) -> void:
	for s: Callable in steps(ch, block):
		s.call()


## build() as build steps (CityChunk._block_steps appends them after the pavement furniture), each
## a few milliseconds: the plan (what stands there, the cuts), the ring's four bands, its notches,
## wells, heaves, kerb faces and collision, then the marks.
static func steps(ch: CityChunk, block: Dictionary) -> Array[Callable]:
	var out: Array[Callable] = []
	# The same test _block_surface makes when it hands the ring over (the list is made before
	# that step runs).
	if not takes(ch, block.rect):
		return out
	var ctx := {}
	out.append(func() -> void: _plan_step(ch, block, ctx))
	for b in 4:
		out.append(func() -> void:
			if ctx.has("st"):
				_band(ctx, b))
	out.append(func() -> void:
		if ctx.has("st"):
			_cut_surfaces(ctx))
	for e in 4:
		out.append(func() -> void:
			if ctx.has("st"):
				_face_edge(ctx, e))
	out.append(func() -> void:
		if ctx.has("st"):
			_finish_ring(ctx))
	for e in 4:
		out.append(func() -> void:
			if ctx.has("st"):
				_paint_edge(ctx, e))
	out.append(func() -> void:
		if ctx.has("st"):
			_paint_rest(ctx, block))
	out.append(func() -> void:
		if ctx.has("st"):
			_commit(ctx)
			_record(ctx))
	if OS.get_environment("KERBS_PROF") == "1":
		var timed: Array[Callable] = []
		for i in out.size():
			var f: Callable = out[i]
			timed.append(func() -> void:
				var t0 := Time.get_ticks_usec()
				f.call()
				print("KERBS_STEP %d %.2f ms" % [i, (Time.get_ticks_usec() - t0) / 1000.0]))
		return timed
	return out


static func _plan_step(ch: CityChunk, block: Dictionary, ctx: Dictionary) -> void:
	if not ch.has_meta("kerbs"):
		return
	var st: Dictionary = ch.get_meta("kerbs")
	var rect: Rect2 = st.rect
	var plan := ch.plan
	var district: int = block.district
	var edges := CityChunk._sidewalk_edges(rect)
	var lens := [rect.size.x, rect.size.x, rect.size.y, rect.size.y]
	ctx.merge({"ch": ch, "rect": rect, "edges": edges, "lens": lens, "notches": [], "cuts": [],
		"marks": {}, "acc": _Faces.new(), "obstacles": [], "district": district})
	_gather_obstacles(ch, ctx)
	# Corner ramps.
	for r: Dictionary in corner_ramps(plan, ch.ix, ch.iz, rect):
		_try_notch(ctx, int(r.e), float(r.uc), CR_HALF, CR_FLARE, CR_RUN, CR_LIP, 0)
	# Driveways (the yard districts).
	if district == CityPlan.District.SUBURBS or district == CityPlan.District.BEACHTOWN:
		_driveways(ctx, block)
	# Tree wells and root heave.
	_trees(ctx)
	_ring_setup(ctx, st.mat)


static func _record(ctx: Dictionary) -> void:
	var ch: CityChunk = ctx.ch
	var st: Dictionary = ch.get_meta("kerbs")
	var edges: Array = ctx.edges
	# What was built, for the checks and the probe (tools/kerbs/probe.gd).
	var ramps := 0
	var drives := 0
	for n: Dictionary in ctx.notches:
		if int(n.kind) == 0:
			ramps += 1
		else:
			drives += 1
	st["built"] = {"ramps": ramps, "drives": drives, "wells": (ctx.get("wells", []) as Array).size(),
		"heaves": (ctx.get("heaves", []) as Array).size(), "cracks": (ctx.get("cracks", []) as Array).size(),
		"zones": ctx.get("painted", []), "numbers": ctx.get("numbers", []), "notches": ctx.notches,
		"wells_at": ctx.get("wells", []), "heaves_at": ctx.get("heaves", []), "edges": edges,
		"faces": (ctx.acc as _Faces).faces.size() / 3}


## Upright things already standing in the ring (the block's props and batch instances): a cut is
## never made under one. Flat things (paint, grates, patches, grass) do not count.
static func _gather_obstacles(ch: CityChunk, ctx: Dictionary) -> void:
	var rect: Rect2 = ctx.rect
	var band := rect.grow(0.4)
	var inner_r := rect.grow(-RING - 0.4)
	var obs: Array = ctx.obstacles
	for rec: Dictionary in ch.prop_records:
		var p: Vector3 = rec.position
		var q := Vector2(p.x, p.z)
		if band.has_point(q) and not inner_r.has_point(q):
			obs.append(q)
	var flat := ["dash", "stripe", "manhole", "patch", "pstripe", "gutter", "grate", "kerb_inlet", "kerb_paint",
		"stop_line", "arrow_left", "arrow_straight", "tree_grate", "grass", "wear", "lamp_pool", "pool"]
	var data := ch._batch.data()
	for key: String in data:
		if key in flat or key.begins_with("text_") or key.begins_with("grass") or key.ends_with("_pool"):
			continue
		for xf: Transform3D in data[key].xforms:
			var q := Vector2(xf.origin.x, xf.origin.z)
			if band.has_point(q) and not inner_r.has_point(q):
				obs.append(q)
	# Trash cans and other bodies the block stood on the pavement.
	for c in ch.get_children():
		if c is TrashCan:
			var q := Vector2((c as Node3D).position.x, (c as Node3D).position.z)
			obs.append(q)


## The footprint of a notch on edge e (world 2D polygon, kerb line first).
static func _notch_poly(ctx: Dictionary, e: int, uc: float, a: float, f: float, run: float) -> PackedVector2Array:
	return PackedVector2Array([_pt(ctx, e, uc - a - f, 0.0), _pt(ctx, e, uc + a + f, 0.0), _pt(ctx, e, uc + a, run), _pt(ctx, e, uc - a, run)])


static func _pt(ctx: Dictionary, e: int, u: float, v: float) -> Vector2:
	var ed: Array = ctx.edges[e]
	var a: Vector2 = ed[0]
	var b: Vector2 = ed[1]
	var n: Vector2 = ed[2]
	return a + (b - a).normalized() * u + n * v


## Adds a notch (ramp or driveway apron) if it stays on its face, clear of the ends, of the other
## cuts and of anything standing there.
static func _try_notch(ctx: Dictionary, e: int, uc: float, a: float, f: float, run: float, lip: float, kind: int) -> bool:
	var length: float = ctx.lens[e]
	if uc - a - f < 0.3 or uc + a + f > length - 0.3:
		return false
	var poly := _notch_poly(ctx, e, uc, a, f, run)
	var box := _poly_box(poly)
	for o: Vector2 in ctx.obstacles:
		if box.grow(CLEAR).has_point(o) and _near_poly(poly, o, CLEAR):
			return false
	for c: Dictionary in ctx.cuts:
		if (c.box as Rect2).grow(0.15).intersects(box):
			return false
	var n := {"e": e, "uc": uc, "a": a, "f": f, "run": run, "lip": lip, "kind": kind, "poly": poly, "box": box}
	ctx.notches.append(n)
	ctx.cuts.append({"poly": poly, "box": box})
	return true


## Whether p is inside poly or within r of its outline.
static func _near_poly(poly: PackedVector2Array, p: Vector2, r: float) -> bool:
	if Geometry2D.is_point_in_polygon(p, poly):
		return true
	for i in poly.size():
		var q := Geometry2D.get_closest_point_to_segment(p, poly[i], poly[(i + 1) % poly.size()])
		if q.distance_to(p) < r:
			return true
	return false


static func _poly_box(poly: PackedVector2Array) -> Rect2:
	var r := Rect2(poly[0], Vector2.ZERO)
	for p in poly:
		r = r.expand(p)
	return r


## Every place this block's ring MAY cut - each corner ramp and each driveway apron the plan asks
## for - whether or not Kerbs is on and whether or not the cut is then made (a cut gives way to a
## prop or another cut). Pure in the plan and the chunk's recorded lots, so what keeps off these
## (BoulevardSigns' posts) stands the same with the kerbs off, as the kerbs check holds every other
## prop to. World XZ polygons, kerb line first, as the notches are.
static func possible_cuts(ch: CityChunk, rect: Rect2, district: int) -> Array:
	var ctx := {"edges": CityChunk._sidewalk_edges(rect)}
	var out: Array = []
	for r: Dictionary in corner_ramps(ch.plan, ch.ix, ch.iz, rect):
		out.append(_notch_poly(ctx, int(r.e), float(r.uc), CR_HALF, CR_FLARE, CR_RUN))
	if district != CityPlan.District.SUBURBS and district != CityPlan.District.BEACHTOWN:
		return out
	if not YardFill.enabled or ch._yard_lots.is_empty():
		return out
	var bp := YardFill.beach_block(ch.plan, ch.ix, ch.iz, ch._yard_lots)
	for lp: Dictionary in bp.lots:
		var drive: Rect2 = lp.drive
		if drive.size.x <= 0.0 or lp.walk_front:
			continue
		var side := int((lp.frame as Dictionary).side)
		var gap := 0.0
		match side:
			0: gap = drive.position.y - rect.position.y
			1: gap = rect.end.y - drive.end.y
			2: gap = drive.position.x - rect.position.x
			_: gap = rect.end.x - drive.end.x
		if gap > ch.plan.sidewalk_width + 1.5:
			continue
		var u0 := (drive.position.x - rect.position.x) if side < 2 else (drive.position.y - rect.position.y)
		var w := drive.size.x if side < 2 else drive.size.y
		if w < DR_MIN or w > DR_MAX:
			continue
		out.append(_notch_poly(ctx, side, u0 + w * 0.5, w * 0.5, DR_FLARE, DR_RUN))
	return out


## Driveway aprons where the yards' driveways meet the street (YardFill's plan of this block).
static func _driveways(ctx: Dictionary, block: Dictionary) -> void:
	var ch: CityChunk = ctx.ch
	if not YardFill.enabled or ch._yard_lots.is_empty():
		return
	var bp := YardFill.beach_block(ch.plan, ch.ix, ch.iz, ch._yard_lots)
	var rect: Rect2 = ctx.rect
	var st: Dictionary = ch.get_meta("kerbs")
	ctx["lots"] = bp.lots
	for lp: Dictionary in bp.lots:
		var drive: Rect2 = lp.drive
		if drive.size.x <= 0.0 or lp.walk_front:
			continue
		var side := int((lp.frame as Dictionary).side)
		# The drive must start at the block's pavement (the lot fronts the street, not the walk).
		var gap := 0.0
		match side:
			0: gap = drive.position.y - rect.position.y
			1: gap = rect.end.y - drive.end.y
			2: gap = drive.position.x - rect.position.x
			_: gap = rect.end.x - drive.end.x
		if gap > ch.plan.sidewalk_width + 1.5:
			continue
		var u0 := (drive.position.x - rect.position.x) if side < 2 else (drive.position.y - rect.position.y)
		var w := drive.size.x if side < 2 else drive.size.y
		if w < DR_MIN or w > DR_MAX:
			continue
		var uc := u0 + w * 0.5
		if _try_notch(ctx, side, uc, w * 0.5, DR_FLARE, DR_RUN, DR_LIP, 1):
			# Nothing parks across it (this chunk's own cars: CityChunk._park_car).
			st.clear.append([_pt(ctx, side, uc - w * 0.5 - DR_FLARE, -2.0), _pt(ctx, side, uc + w * 0.5 + DR_FLARE, -2.0)])


## Street trees in the ring: a bare dirt well cut for some (the grate hidden), a heaved slab
## beside some, hairline cracks round others. The tree_grate batch wears the cast-iron grate.
static func _trees(ctx: Dictionary) -> void:
	var ch: CityChunk = ctx.ch
	var rect: Rect2 = ctx.rect
	var data := ch._batch.data()
	if not data.has("tree_grate"):
		return
	var batch: Dictionary = data["tree_grate"]
	batch.mesh = grate_mesh()
	var plan := ch.plan
	var mat: Material = (ch.get_meta("kerbs") as Dictionary).mat
	var joint := 1.5
	if mat is ShaderMaterial:
		var j: Variant = (mat as ShaderMaterial).get_shader_parameter("joint_spacing")
		if j != null and float(j) > 0.3:
			joint = float(j)
	var dirt_share: float = WELL_DIRT[clampi(int(ctx.district), 0, WELL_DIRT.size() - 1)]
	var xforms: Array = batch.xforms
	ctx["wells"] = []
	ctx["heaves"] = []
	ctx["cracks"] = []
	for i in xforms.size():
		var xf: Transform3D = xforms[i]
		var c := Vector2(xf.origin.x, xf.origin.z)
		var e := _edge_of(ctx, c)
		if e < 0:
			continue
		var v := _v_of(ctx, e, c)
		if v < 0.3 or v > RING - 0.3:
			continue
		var key := [plan.seed, int(roundf(c.x * 10.0)), int(roundf(c.y * 10.0))]
		if _h01(key + ["well"]) < dirt_share:
			var half := WELL_SIZE * 0.5
			var wr := Rect2(c - Vector2(half, half), Vector2(WELL_SIZE, WELL_SIZE))
			if _clear_rect(ctx, wr, c):
				ctx.cuts.append({"poly": _rect_poly(wr), "box": wr})
				(ctx.wells as Array).append(wr)
				# The grate goes: the well is open.
				xforms[i] = Transform3D(Basis().scaled(Vector3(0.0001, 0.0001, 0.0001)), xf.origin - Vector3(0.0, 0.5, 0.0))
		if _h01(key + ["heave"]) < HEAVE_ODDS:
			_heave(ctx, e, c, joint, key)
		if _h01(key + ["crack"]) < CRACK_ODDS:
			(ctx.cracks as Array).append([c, e, key])


## Which edge a point in the ring is nearest (-1: not in the ring).
static func _edge_of(ctx: Dictionary, p: Vector2) -> int:
	var rect: Rect2 = ctx.rect
	if not rect.has_point(p):
		return -1
	var d := [p.y - rect.position.y, rect.end.y - p.y, p.x - rect.position.x, rect.end.x - p.x]
	var best := 0
	for e in 4:
		if float(d[e]) < float(d[best]):
			best = e
	return best if float(d[best]) < RING else -1


static func _v_of(ctx: Dictionary, e: int, p: Vector2) -> float:
	var ed: Array = ctx.edges[e]
	return (p - (ed[0] as Vector2)).dot(ed[2])


static func _u_of(ctx: Dictionary, e: int, p: Vector2) -> float:
	var ed: Array = ctx.edges[e]
	return (p - (ed[0] as Vector2)).dot(((ed[1] as Vector2) - (ed[0] as Vector2)).normalized())


static func _rect_poly(r: Rect2) -> PackedVector2Array:
	return PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])


## Whether rect r sits wholly in the ring band and clear of every cut and obstacle (but `own`).
static func _clear_rect(ctx: Dictionary, r: Rect2, own: Vector2) -> bool:
	var rect: Rect2 = ctx.rect
	var in_band := rect.grow(-0.16).encloses(r) and not inner(rect).grow(-0.05).intersects(r)
	if not in_band:
		return false
	for c: Dictionary in ctx.cuts:
		if (c.box as Rect2).grow(0.12).intersects(r):
			return false
	for o: Vector2 in ctx.obstacles:
		if o.distance_to(own) < 0.2:
			continue
		if r.grow(0.25).has_point(o):
			return false
	return true


## A slab beside tree `c` lifted on its hinge by the roots: the joint cell next to it along the
## kerb (or behind it), cut out of the ring and laid back tilted.
static func _heave(ctx: Dictionary, e: int, c: Vector2, joint: float, key: Array) -> void:
	var ch: CityChunk = ctx.ch
	var ed: Array = ctx.edges[e]
	var dir := ((ed[1] as Vector2) - (ed[0] as Vector2)).normalized()
	var n: Vector2 = ed[2]
	var off := Vector2(ch.position.x, ch.position.z)
	var choices := [dir, -dir, n]
	var pick := int(_h01(key + ["heave_side"]) * 2.999)
	for k in 3:
		var d: Vector2 = choices[(pick + k) % 3]
		var probe := c + d * (WELL_SIZE * 0.5 + joint * 0.5 + 0.05)
		# The joint cell holding the probe point, on the grid the paving shader draws its joints
		# on (world position at build time).
		var w := probe + off
		var cell := Rect2(Vector2(floorf(w.x / joint), floorf(w.y / joint)) * joint - off, Vector2(joint, joint))
		cell = cell.intersection(Rect2(ctx.rect).grow(-0.16))
		if cell.size.x < 0.5 or cell.size.y < 0.5:
			continue
		if not _clear_rect(ctx, cell, c):
			continue
		var lift := lerpf(HEAVE_LIFT.x, HEAVE_LIFT.y, _h01(key + ["heave_lift"]))
		ctx.cuts.append({"poly": _rect_poly(cell), "box": cell})
		# Lifted on the side toward the tree, hinged on the far side.
		(ctx.heaves as Array).append([cell, c, lift])
		return


# --- Geometry -------------------------------------------------------------------------------------

## The ring: top (cut round every notch, well and heave), the notches' ramps and flares, the wells'
## walls, the heaved slabs, and the kerb face all round. One mesh in the pavement material, and its
## collision as one trimesh on the chunk's StreetProps.
static func _ring_setup(ctx: Dictionary, mat: Material) -> void:
	var ch: CityChunk = ctx.ch
	var rect: Rect2 = ctx.rect
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	ctx["st"] = st
	ctx["mat"] = mat
	ctx["inv"] = Vector2(1.0 / rect.size.x, 1.0 / rect.size.y)
	var step := ch.ground_grid_step if CityChunk._detail() >= 1.0 else ch.ground_grid_step * 2.0
	var inn := inner(rect)
	var nx := clampi(ceili(inn.size.x / step), 1, 120)
	var nz := clampi(ceili(inn.size.y / step), 1, 120)
	# Breakpoints: the inner slab's own grid (so the seam has no T-junctions), the band ends.
	var xs: Array[float] = [rect.position.x]
	for i in nx + 1:
		xs.append(inn.position.x + inn.size.x * i / nx)
	xs.append(rect.end.x)
	var zs: Array[float] = []
	for j in nz + 1:
		zs.append(inn.position.y + inn.size.y * j / nz)
	ctx["xs"] = xs
	ctx["zs"] = zs


## One band of the ring's top: north and south full width, west and east between them.
static func _band(ctx: Dictionary, b: int) -> void:
	var rect: Rect2 = ctx.rect
	var xs: Array[float] = ctx.xs
	var zs: Array[float] = ctx.zs
	var bands := [
		[true, xs, rect.position.y, rect.position.y + RING],
		[true, xs, rect.end.y - RING, rect.end.y],
		[false, zs, rect.position.x, rect.position.x + RING],
		[false, zs, rect.end.x - RING, rect.end.x],
	]
	var band: Array = bands[b]
	var along_x: bool = band[0]
	var cuts_at: Array[float] = []
	cuts_at.assign(band[1])
	var first: float = cuts_at[0]
	var last: float = cuts_at[-1]
	var lo: float = band[2]
	var hi: float = band[3]
	var brect := Rect2(first, lo, last - first, hi - lo) if along_x else Rect2(lo, first, hi - lo, last - first)
	var mine: Array = []
	for c: Dictionary in ctx.cuts:
		if (c.box as Rect2).intersects(brect):
			mine.append(c)
			var bx: Rect2 = c.box
			cuts_at.append(bx.position.x if along_x else bx.position.y)
			cuts_at.append(bx.end.x if along_x else bx.end.y)
	cuts_at.sort()
	for k in cuts_at.size() - 1:
		var s0: float = cuts_at[k]
		var s1: float = cuts_at[k + 1]
		if s1 - s0 < 0.005 or s0 < first - 0.001 or s1 > last + 0.001:
			continue
		var cell := Rect2(s0, lo, s1 - s0, hi - lo) if along_x else Rect2(lo, s0, hi - lo, s1 - s0)
		var near: Array = []
		for c: Dictionary in mine:
			if (c.box as Rect2).intersects(cell):
				near.append(c)
		_top_cell(ctx, cell, near)


## The cuts' own surfaces, the kerb faces, then the ring's mesh and collision.
static func _cut_surfaces(ctx: Dictionary) -> void:
	for n: Dictionary in ctx.notches:
		_notch_surface(ctx, n)
	for w: Rect2 in ctx.get("wells", []):
		_well_walls(ctx, w)
	for h: Array in ctx.get("heaves", []):
		_heave_slab(ctx, h)


static func _face_edge(ctx: Dictionary, e: int) -> void:
	var rect: Rect2 = ctx.rect
	if e < 2:
		_kerb_face(ctx, e, ctx.xs)
		return
	var zs: Array = [rect.position.y]
	zs.append_array(ctx.zs)
	zs.append(rect.end.y)
	_kerb_face(ctx, e, zs)


static func _finish_ring(ctx: Dictionary) -> void:
	var ch: CityChunk = ctx.ch
	var st: SurfaceTool = ctx.st
	var mesh := st.commit()
	var mi := MeshInstance3D.new()
	mi.name = "KerbRing"
	mi.mesh = mesh
	mi.material_override = ctx.mat
	ch.add_child(mi)
	var acc: _Faces = ctx.acc
	if ch._statics and acc.faces.size() > 0:
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(acc.faces)
		var cs := CollisionShape3D.new()
		cs.shape = shape
		ch._statics.add_child(cs)


## Ground height under (x, z) in the chunk.
static func _g(ctx: Dictionary, p: Vector2) -> float:
	return (ctx.ch as CityChunk)._gy(p.x, p.y)


static func _v3(ctx: Dictionary, p: Vector2, h: float) -> Vector3:
	return Vector3(p.x, h + _g(ctx, p), p.y)


## A triangle in the ring mesh facing `want`, flat-shaded, with the block's 0..1 UV; also into
## the collision faces.
static func _tri(ctx: Dictionary, a: Vector3, b: Vector3, c: Vector3, want: Vector3, collide: bool = true) -> void:
	var n := (c - a).cross(b - a)
	if n.length_squared() < 1e-14:
		return
	if n.dot(want) < 0.0:
		var t := b
		b = c
		c = t
		n = -n
	n = n.normalized()
	var st: SurfaceTool = ctx.st
	var rect: Rect2 = ctx.rect
	var inv: Vector2 = ctx.inv
	for v: Vector3 in [a, b, c]:
		st.set_normal(n)
		st.set_uv(Vector2(v.x - rect.position.x, v.z - rect.position.y) * inv)
		st.add_vertex(v)
	if collide:
		var acc: _Faces = ctx.acc
		acc.faces.append(a)
		acc.faces.append(b)
		acc.faces.append(c)


## One cell of a band's top, less the cuts that reach it.
static func _top_cell(ctx: Dictionary, cell: Rect2, cuts: Array) -> void:
	var polys: Array = [_rect_poly(cell)]
	for c: Dictionary in cuts:
		if not (c.box as Rect2).intersects(cell):
			continue
		var next: Array = []
		for p: PackedVector2Array in polys:
			for q: PackedVector2Array in Geometry2D.clip_polygons(p, c.poly):
				# A clockwise result is a hole (a cut wholly inside the cell): the breakpoints at
				# every cut's ends keep that from happening, and a cell that still gets one is
				# left out rather than covering the cut.
				if Geometry2D.is_polygon_clockwise(q):
					return
				next.append(q)
		polys = next
	for p: PackedVector2Array in polys:
		if p.size() < 3 or absf(_area(p)) < 1e-5:
			continue
		var idx := Geometry2D.triangulate_polygon(p)
		for t in range(0, idx.size(), 3):
			_tri(ctx, _v3(ctx, p[idx[t]], TOP), _v3(ctx, p[idx[t + 1]], TOP), _v3(ctx, p[idx[t + 2]], TOP), Vector3.UP)


static func _area(p: PackedVector2Array) -> float:
	var s := 0.0
	for i in p.size():
		var a := p[i]
		var b := p[(i + 1) % p.size()]
		s += a.x * b.y - b.x * a.y
	return s * 0.5


## A notch's ramp and flares (or a driveway's apron and its flares).
static func _notch_surface(ctx: Dictionary, n: Dictionary) -> void:
	var e: int = n.e
	var uc: float = n.uc
	var a: float = n.a
	var f: float = n.f
	var run: float = n.run
	var lo: float = ROAD + float(n.lip)
	var p0 := _pt(ctx, e, uc - a - f, 0.0)
	var p1 := _pt(ctx, e, uc - a, 0.0)
	var p2 := _pt(ctx, e, uc + a, 0.0)
	var p3 := _pt(ctx, e, uc + a + f, 0.0)
	var q1 := _pt(ctx, e, uc - a, run)
	var q2 := _pt(ctx, e, uc + a, run)
	# The ramp, in strips across it so it follows the relief along the kerb.
	var strips := maxi(1, ceili(a * 2.0 / 1.2))
	for s in strips:
		var t0 := float(s) / strips
		var t1 := float(s + 1) / strips
		var b0 := p1.lerp(p2, t0)
		var b1 := p1.lerp(p2, t1)
		var c0 := q1.lerp(q2, t0)
		var c1 := q1.lerp(q2, t1)
		_tri(ctx, _v3(ctx, b0, lo), _v3(ctx, b1, lo), _v3(ctx, c1, TOP), Vector3.UP)
		_tri(ctx, _v3(ctx, b0, lo), _v3(ctx, c1, TOP), _v3(ctx, c0, TOP), Vector3.UP)
	_tri(ctx, _v3(ctx, p0, TOP), _v3(ctx, p1, lo), _v3(ctx, q1, TOP), Vector3.UP)
	_tri(ctx, _v3(ctx, p2, lo), _v3(ctx, p3, TOP), _v3(ctx, q2, TOP), Vector3.UP)


## The walls of a bare dirt well (the dirt itself is in the marks mesh).
static func _well_walls(ctx: Dictionary, w: Rect2) -> void:
	var cs := [w.position, Vector2(w.end.x, w.position.y), w.end, Vector2(w.position.x, w.end.y)]
	var mid := w.get_center()
	for i in 4:
		var a: Vector2 = cs[i]
		var b: Vector2 = cs[(i + 1) % 4]
		var into := mid - (a + b) * 0.5
		var want := Vector3(into.x, 0.0, into.y).normalized()
		var bot := TOP - WELL_WALL
		_tri(ctx, _v3(ctx, a, TOP), _v3(ctx, b, TOP), _v3(ctx, b, bot), want)
		_tri(ctx, _v3(ctx, a, TOP), _v3(ctx, b, bot), _v3(ctx, a, bot), want)
	# A floor under the dirt so the well is closed for collision and from any angle.
	var f := TOP - WELL_DIRT_DEPTH - 0.004
	_tri(ctx, _v3(ctx, cs[0], f), _v3(ctx, cs[1], f), _v3(ctx, cs[2], f), Vector3.UP)
	_tri(ctx, _v3(ctx, cs[0], f), _v3(ctx, cs[2], f), _v3(ctx, cs[3], f), Vector3.UP)


## A heaved slab: the cell's top lifted by `lift` on the side toward the tree, and the faces the
## lift exposes.
static func _heave_slab(ctx: Dictionary, h: Array) -> void:
	var cell: Rect2 = h[0]
	var tree: Vector2 = h[1]
	var lift: float = h[2]
	var cs := [cell.position, Vector2(cell.end.x, cell.position.y), cell.end, Vector2(cell.position.x, cell.end.y)]
	var c := cell.get_center()
	var toward := (tree - c).normalized()
	var span := maxf(cell.size.x, cell.size.y) * 0.5
	var hs: Array[float] = []
	for p: Vector2 in cs:
		var k := clampf(((p - c).dot(toward) / span) * 0.5 + 0.5, 0.0, 1.0)
		hs.append(TOP + lift * k)
	_tri(ctx, _v3(ctx, cs[0], hs[0]), _v3(ctx, cs[1], hs[1]), _v3(ctx, cs[2], hs[2]), Vector3.UP)
	_tri(ctx, _v3(ctx, cs[0], hs[0]), _v3(ctx, cs[2], hs[2]), _v3(ctx, cs[3], hs[3]), Vector3.UP)
	for i in 4:
		var a: Vector2 = cs[i]
		var b: Vector2 = cs[(i + 1) % 4]
		var out := (a + b) * 0.5 - c
		var want := Vector3(out.x, 0.0, out.y).normalized()
		_tri(ctx, _v3(ctx, a, hs[i]), _v3(ctx, b, hs[(i + 1) % 4]), _v3(ctx, b, TOP - 0.02), want)
		_tri(ctx, _v3(ctx, a, hs[i]), _v3(ctx, b, TOP - 0.02), _v3(ctx, a, TOP - 0.02), want)


## Height of the kerb's top above the ground at `u` along edge e (lowered in its notches).
static func kerb_top(notches: Array, e: int, u: float) -> float:
	for n: Dictionary in notches:
		if int(n.e) != e:
			continue
		var d := absf(u - float(n.uc))
		var a: float = n.a
		var f: float = n.f
		var lo := ROAD + float(n.lip)
		if d <= a:
			return lo
		if d < a + f:
			return lerpf(lo, TOP, (d - a) / f)
	return TOP


## The kerb face along edge e, from the road (buried FACE_FOOT under it) up to the kerb's top,
## broken at the grid's breakpoints and every notch's.
static func _kerb_face(ctx: Dictionary, e: int, coords: Array) -> void:
	var length: float = ctx.lens[e]
	var rect: Rect2 = ctx.rect
	var start := rect.position.x if e < 2 else rect.position.y
	var us: Array[float] = []
	for c in coords:
		us.append(clampf(float(c) - start, 0.0, length))
	for n: Dictionary in ctx.notches:
		if int(n.e) != e:
			continue
		var uc: float = n.uc
		for d: float in [-float(n.a) - float(n.f), -float(n.a), float(n.a), float(n.a) + float(n.f)]:
			us.append(uc + d)
	us.sort()
	var ed: Array = ctx.edges[e]
	var nrm: Vector2 = -(ed[2] as Vector2)
	var want := Vector3(nrm.x, 0.0, nrm.y)
	for k in us.size() - 1:
		var u0 := us[k]
		var u1 := us[k + 1]
		if u1 - u0 < 0.003:
			continue
		var a := _pt(ctx, e, u0, 0.0)
		var b := _pt(ctx, e, u1, 0.0)
		var ta := kerb_top(ctx.notches, e, u0)
		var tb := kerb_top(ctx.notches, e, u1)
		var foot := ROAD - FACE_FOOT
		_tri(ctx, _v3(ctx, a, ta), _v3(ctx, b, tb), _v3(ctx, b, foot), want)
		_tri(ctx, _v3(ctx, a, ta), _v3(ctx, b, foot), _v3(ctx, a, foot), want)


# --- Marks ----------------------------------------------------------------------------------------

## The marks mesh tile holding point p.
static func _mst(ctx: Dictionary, p: Vector2) -> SurfaceTool:
	var marks: Dictionary = ctx.marks
	var k := Vector2i(floori(p.x / TILE), floori(p.y / TILE))
	if not marks.has(k):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		marks[k] = st
	return marks[k]


## One quad (a, b, c, d in order round it) in the marks mesh: kind, sRGB colour, UVs at its
## corners, data in UV2.
static func _mquad(ctx: Dictionary, a: Vector3, b: Vector3, c: Vector3, d: Vector3, nrm: Vector3, kind: int, col: Color,
		ua: Vector2, ub: Vector2, uc: Vector2, ud: Vector2, data: Vector2) -> void:
	var st := _mst(ctx, Vector2((a.x + c.x) * 0.5, (a.z + c.z) * 0.5))
	var cc := Color(col.r, col.g, col.b, (float(kind) + 0.5) / 16.0)
	var tri := (c - a).cross(b - a)
	var flip := tri.dot(nrm) < 0.0
	var order := [[a, ua], [b, ub], [c, uc], [a, ua], [c, uc], [d, ud]]
	if flip:
		order = [[a, ua], [c, uc], [b, ub], [a, ua], [d, ud], [c, uc]]
	for o: Array in order:
		st.set_color(cc)
		st.set_normal(nrm)
		st.set_uv(o[1])
		st.set_uv2(data)
		st.add_vertex(o[0])


## The kerb's paint, house numbers, dome pads, well dirt and cracks.
static func _paint(ctx: Dictionary, block: Dictionary) -> void:
	for e in 4:
		_paint_edge(ctx, e)
	_paint_rest(ctx, block)


## Edge e's zones: the plan's, red round this block's hydrants, resolved, painted and stencilled.
static func _paint_edge(ctx: Dictionary, e: int) -> void:
	var ch: CityChunk = ctx.ch
	var plan := ch.plan
	var rect: Rect2 = ctx.rect
	var st: Dictionary = ch.get_meta("kerbs")
	var district: int = ctx.district
	if true:
		var length: float = ctx.lens[e]
		var zones := edge_zones(plan, ch.ix, ch.iz, rect, e, district)
		# Red either side of this block's hydrant(s).
		for rec: Dictionary in ch.prop_records:
			if rec.kind != "hydrant":
				continue
			var hp: Vector3 = rec.position
			var q := Vector2(hp.x, hp.z)
			if _edge_of(ctx, q) != e:
				continue
			var u := _u_of(ctx, e, q)
			zones.append([maxf(u - HYDRANT_RED, 0.25), minf(u + HYDRANT_RED, length - 0.25), RED, ""])
		for z: Array in resolve(zones):
			var u0: float = z[0]
			var u1: float = z[1]
			var col: Color = z[2]
			var seed := _h01([plan.seed, ch.ix, ch.iz, e, int(u0 * 10.0), "paint"])
			if not ctx.has("painted"):
				ctx["painted"] = []
			(ctx.painted as Array).append([e, u0, u1, z[2], z[3]])
			_paint_run(ctx, e, u0, u1, col, seed)
			if z[3] != "":
				_stencil_runs(ctx, e, u0, u1, z[3], WHITE if col == GREEN or col == BLUE else INK, seed)
			if col == RED:
				# Red is no stopping: nobody parks along it (this chunk's own cars).
				st.clear.append([_pt(ctx, e, u0 + 2.0, -2.0), _pt(ctx, e, maxf(u1 - 2.0, u0 + 2.0), -2.0)])


## House numbers, dome pads, well dirt and cracks.
static func _paint_rest(ctx: Dictionary, block: Dictionary) -> void:
	_house_numbers(ctx, block)
	for n: Dictionary in ctx.notches:
		if int(n.kind) == 0:
			_dome_pad(ctx, n)
		else:
			_apron(ctx, n)
	for w: Rect2 in ctx.get("wells", []):
		_dirt(ctx, w)
	for c: Array in ctx.get("cracks", []):
		_tree_cracks(ctx, c)
	for h: Array in ctx.get("heaves", []):
		_heave_crack(ctx, h)


## Paint along [u0, u1] of edge e, round the face and over the kerb's top edge, skipping notches.
static func _paint_run(ctx: Dictionary, e: int, u0: float, u1: float, col: Color, seed: float) -> void:
	var spans: Array = [[u0, u1]]
	for n: Dictionary in ctx.notches:
		if int(n.e) != e:
			continue
		var a := float(n.uc) - float(n.a) - float(n.f) - 0.05
		var b := float(n.uc) + float(n.a) + float(n.f) + 0.05
		var next: Array = []
		for s: Array in spans:
			if b <= s[0] or a >= s[1]:
				next.append(s)
				continue
			if a > s[0]:
				next.append([s[0], a])
			if b < s[1]:
				next.append([b, s[1]])
		spans = next
	var ed: Array = ctx.edges[e]
	var nrm2: Vector2 = -(ed[2] as Vector2)
	var out3 := Vector3(nrm2.x, 0.0, nrm2.y)
	for s: Array in spans:
		var t: float = s[0]
		while t < float(s[1]) - 0.02:
			var t1 := minf(t + 1.5, float(s[1]))
			var a := _pt(ctx, e, t, 0.0)
			var b := _pt(ctx, e, t1, 0.0)
			var ai := _pt(ctx, e, t, 0.16)
			var bi := _pt(ctx, e, t1, 0.16)
			var off := Vector3(nrm2.x, 0.0, nrm2.y) * 0.003
			var fh := TOP - ROAD
			# The face, from just over the road to the top edge.
			_mquad(ctx, _v3(ctx, a, ROAD + 0.004) + off, _v3(ctx, b, ROAD + 0.004) + off, _v3(ctx, b, TOP + 0.0015) + off, _v3(ctx, a, TOP + 0.0015) + off,
				out3, Kind.PAINT, col, Vector2(t, 0.004), Vector2(t1, 0.004), Vector2(t1, fh), Vector2(t, fh), Vector2(seed, 0.0))
			# The top, 16 cm in from the face.
			_mquad(ctx, _v3(ctx, a, TOP + 0.0025) + off, _v3(ctx, b, TOP + 0.0025) + off, _v3(ctx, bi, TOP + 0.0025), _v3(ctx, ai, TOP + 0.0025),
				Vector3.UP, Kind.PAINT, col, Vector2(t, fh), Vector2(t1, fh), Vector2(t1, fh + 0.16), Vector2(t, fh + 0.16), Vector2(seed, 0.0))
			t = t1


## A stencil every ~7 m of a zone (at least once), along the kerb face.
static func _stencil_runs(ctx: Dictionary, e: int, u0: float, u1: float, text: String, ink: Color, seed: float) -> void:
	var w := text.length() * GLYPH_PITCH
	var room := u1 - u0
	if room < w + 0.6:
		return
	var count := maxi(1, int(room / 7.0))
	for k in count:
		var mid := u0 + room * (float(k) + 0.5) / float(count)
		_stencil(ctx, e, mid, text, ink, (TOP - ROAD) * 0.5, seed + float(k) * 0.37)


## `text` centred at u on edge e's face, `centre_h` over the road top.
static func _stencil(ctx: Dictionary, e: int, u: float, text: String, ink: Color, centre_h: float, seed: float) -> void:
	if kerb_top(ctx.notches, e, u - text.length() * GLYPH_PITCH * 0.5) < TOP - 0.001 or kerb_top(ctx.notches, e, u + text.length() * GLYPH_PITCH * 0.5) < TOP - 0.001:
		return
	var ed: Array = ctx.edges[e]
	var nrm2: Vector2 = -(ed[2] as Vector2)
	var out3 := Vector3(nrm2.x, 0.0, nrm2.y)
	var off := out3 * 0.0045
	var w := text.length() * GLYPH_PITCH
	# The face reads left to right from the street: u runs along `dir`, which on half the faces
	# points to the reader's left.
	var dir := ((ed[1] as Vector2) - (ed[0] as Vector2)).normalized()
	var right := Vector2(nrm2.y, -nrm2.x)
	var sgn := 1.0 if dir.dot(right) > 0.0 else -1.0
	var y0 := ROAD + centre_h - GLYPH_H * 0.5
	var y1 := y0 + GLYPH_H
	for i in text.length():
		var ch := text[i]
		if ch == " ":
			continue
		var bits := glyph_bits(ch)
		var c0 := u + sgn * (float(i) * GLYPH_PITCH - w * 0.5)
		var c1 := c0 + sgn * GLYPH_PITCH * 0.86
		var a := _pt(ctx, e, c0, 0.0)
		var b := _pt(ctx, e, c1, 0.0)
		_mquad(ctx, _v3(ctx, a, y0) + off, _v3(ctx, b, y0) + off, _v3(ctx, b, y1) + off, _v3(ctx, a, y1) + off,
			out3, Kind.GLYPH, ink, Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 1.0), Vector2(0.0, 1.0), bits)


## A 5 x 7 glyph (LedScreen's face) packed as UV2: rows 0-3 in x (20 bits), rows 4-6 in y.
static func glyph_bits(ch: String) -> Vector2:
	if _glyph_bits.has(ch):
		return _glyph_bits[ch]
	var rows: Array = LedScreen.GLYPHS.get(ch, LedScreen.GLYPHS[" "])
	var lo := 0
	var hi := 0
	for r in 7:
		var row: String = rows[r]
		var bits := 0
		for c in 5:
			if row[c] == "#":
				bits |= 1 << (4 - c)
		if r < 4:
			lo |= bits << (5 * r)
		else:
			hi |= bits << (5 * (r - 4))
	_glyph_bits[ch] = Vector2(float(lo), float(hi))
	return _glyph_bits[ch]


## House numbers on the kerb face in front of each house (suburbs and beach town): a white plate
## with the number stencilled in black, clear of the driveway.
static func _house_numbers(ctx: Dictionary, block: Dictionary) -> void:
	var ch: CityChunk = ctx.ch
	if not (int(block.district) in NUMBER_DISTRICTS):
		return
	var plan := ch.plan
	var rect: Rect2 = ctx.rect
	for lp: Dictionary in ctx.get("lots", []):
		if lp.walk_front:
			continue
		var side := int((lp.frame as Dictionary).side)
		var cell: Rect2 = lp.cell
		var u := (cell.get_center().x - rect.position.x) if side < 2 else (cell.get_center().y - rect.position.y)
		var key := [plan.seed, ch.ix, ch.iz, side, int(u * 10.0)]
		if _h01(key + ["number"]) > 0.82:
			continue
		# Off the driveway and its flares.
		var half := 0.24
		for n: Dictionary in ctx.notches:
			if int(n.e) != side:
				continue
			var lo := float(n.uc) - float(n.a) - float(n.f) - half - 0.2
			var hi := float(n.uc) + float(n.a) + float(n.f) + half + 0.2
			if u > lo and u < hi:
				u = lo if u - lo < hi - u else hi
		if u < 1.0 or u > float(ctx.lens[side]) - 1.0 or kerb_top(ctx.notches, side, u) < TOP - 0.001:
			continue
		var num := str(house_number(plan, ch.ix, ch.iz, rect, side, u))
		if not ctx.has("numbers"):
			ctx["numbers"] = []
		(ctx.numbers as Array).append([side, u, num])
		var ed: Array = ctx.edges[side]
		var nrm2: Vector2 = -(ed[2] as Vector2)
		var out3 := Vector3(nrm2.x, 0.0, nrm2.y)
		var w := num.length() * GLYPH_PITCH + 0.07
		var a := _pt(ctx, side, u - w * 0.5, 0.0)
		var b := _pt(ctx, side, u + w * 0.5, 0.0)
		var off := out3 * 0.0035
		var y0 := ROAD + 0.018
		var y1 := TOP - 0.012
		var seed := _h01(key + ["plate"])
		_mquad(ctx, _v3(ctx, a, y0) + off, _v3(ctx, b, y0) + off, _v3(ctx, b, y1) + off, _v3(ctx, a, y1) + off,
			out3, Kind.PLATE, WHITE, Vector2(0.0, 0.0), Vector2(w, 0.0), Vector2(w, y1 - y0), Vector2(0.0, y1 - y0), Vector2(seed, 0.0))
		_stencil(ctx, side, u, num, INK, (TOP - ROAD) * 0.5 + 0.003, seed)


## The truncated-dome pad at a corner ramp's foot, on the ramp's slope.
static func _dome_pad(ctx: Dictionary, n: Dictionary) -> void:
	var e: int = n.e
	var uc: float = n.uc
	var a: float = float(n.a) - PAD_INSET
	var run: float = n.run
	var lo := ROAD + float(n.lip)
	var v0 := 0.02
	var v1 := PAD_DEPTH
	var h0 := lerpf(lo, TOP, v0 / run) + 0.003
	var h1 := lerpf(lo, TOP, v1 / run) + 0.003
	var p00 := _pt(ctx, e, uc - a, v0)
	var p10 := _pt(ctx, e, uc + a, v0)
	var p11 := _pt(ctx, e, uc + a, v1)
	var p01 := _pt(ctx, e, uc - a, v1)
	var ed: Array = ctx.edges[e]
	var inward: Vector2 = ed[2]
	var slope := (TOP - lo) / run
	var nrm := Vector3(-inward.x * slope, 1.0, -inward.y * slope).normalized()
	var len_v := (v1 - v0) * sqrt(1.0 + slope * slope)
	_mquad(ctx, _v3(ctx, p00, h0), _v3(ctx, p10, h0), _v3(ctx, p11, h1), _v3(ctx, p01, h1), nrm, Kind.DOMES, DOME_YELLOW,
		Vector2(0.0, 0.0), Vector2(a * 2.0, 0.0), Vector2(a * 2.0, len_v), Vector2(0.0, len_v), Vector2(_h01([uc, e, "pad"]), 0.0))


## A driveway apron's newer, paler concrete over its cut (broom-finished, scored at its edges):
## the apron and its two flares, 2 mm over them.
static func _apron(ctx: Dictionary, n: Dictionary) -> void:
	var e: int = n.e
	var uc: float = n.uc
	var a: float = n.a
	var f: float = n.f
	var run: float = n.run
	var lo := ROAD + float(n.lip) + 0.002
	var hi := TOP + 0.002
	var col := Color(0.66, 0.64, 0.6)
	var seed := _h01([uc, e, "apron"])
	var p0 := _pt(ctx, e, uc - a - f, 0.0)
	var p1 := _pt(ctx, e, uc - a, 0.0)
	var p2 := _pt(ctx, e, uc + a, 0.0)
	var p3 := _pt(ctx, e, uc + a + f, 0.0)
	var q1 := _pt(ctx, e, uc - a, run)
	var q2 := _pt(ctx, e, uc + a, run)
	var w := a * 2.0 + f * 2.0
	# UV: metres along the kerb from the apron's start, metres in from the kerb; UV2.y its length.
	var uv := func(u: float, v: float) -> Vector2: return Vector2(u, v)
	var strips := maxi(1, ceili(a * 2.0 / 1.2))
	for s in strips:
		var t0 := float(s) / strips
		var t1 := float(s + 1) / strips
		_mquad(ctx, _v3(ctx, p1.lerp(p2, t0), lo), _v3(ctx, p1.lerp(p2, t1), lo), _v3(ctx, q1.lerp(q2, t1), hi), _v3(ctx, q1.lerp(q2, t0), hi),
			Vector3.UP, Kind.APRON, col, uv.call(f + a * 2.0 * t0, 0.0), uv.call(f + a * 2.0 * t1, 0.0), uv.call(f + a * 2.0 * t1, run), uv.call(f + a * 2.0 * t0, run), Vector2(seed, w))
	_mquad(ctx, _v3(ctx, p0, hi), _v3(ctx, p1, lo), _v3(ctx, q1, hi), _v3(ctx, q1, hi), Vector3.UP, Kind.APRON, col,
		uv.call(0.0, 0.0), uv.call(f, 0.0), uv.call(f, run), uv.call(f, run), Vector2(seed, w))
	_mquad(ctx, _v3(ctx, p2, lo), _v3(ctx, p3, hi), _v3(ctx, q2, hi), _v3(ctx, q2, hi), Vector3.UP, Kind.APRON, col,
		uv.call(w - f, 0.0), uv.call(w, 0.0), uv.call(w - f, run), uv.call(w - f, run), Vector2(seed, w))


## The dirt in a bare well.
static func _dirt(ctx: Dictionary, w: Rect2) -> void:
	var h := TOP - WELL_DIRT_DEPTH
	var cs := [w.position, Vector2(w.end.x, w.position.y), w.end, Vector2(w.position.x, w.end.y)]
	var c := w.get_center()
	var uv := func(p: Vector2) -> Vector2: return p - c
	_mquad(ctx, _v3(ctx, cs[0], h), _v3(ctx, cs[1], h), _v3(ctx, cs[2], h), _v3(ctx, cs[3], h), Vector3.UP, Kind.DIRT, Color(0.30, 0.22, 0.15),
		uv.call(cs[0]), uv.call(cs[1]), uv.call(cs[2]), uv.call(cs[3]), Vector2(_h01([c.x, c.y, "dirt"]), WELL_SIZE))


## Hairline cracks running out from a tree across the slabs beside it.
static func _tree_cracks(ctx: Dictionary, c: Array) -> void:
	var tree: Vector2 = c[0]
	var e: int = c[1]
	var key: Array = c[2]
	var count := 1 + int(_h01(key + ["cracks"]) * 2.5)
	for k in count:
		var ang := _h01(key + ["crack_a", k]) * TAU
		var d := Vector2(cos(ang), sin(ang))
		var from := tree + d * (WELL_SIZE * 0.5 + 0.08)
		var length := 0.6 + 1.2 * _h01(key + ["crack_l", k])
		var to := from + d * length
		if _edge_of(ctx, to) < 0 or _edge_of(ctx, from) < 0:
			continue
		var bad := false
		for cut: Dictionary in ctx.cuts:
			var bx: Rect2 = cut.box
			if bx.grow(0.05).has_point(to) or bx.grow(0.05).has_point(from.lerp(to, 0.5)):
				bad = true
		if bad or _v_of(ctx, e, to) < 0.2:
			continue
		_crack(ctx, from, to, 0.05, _h01(key + ["crack_s", k]), TOP + 0.0015)


## The crack along a heaved slab's lifted edges (where it broke from its neighbours).
static func _heave_crack(ctx: Dictionary, h: Array) -> void:
	var cell: Rect2 = h[0]
	var tree: Vector2 = h[1]
	var c := cell.get_center()
	var toward := (tree - c)
	var a := Vector2.ZERO
	var b := Vector2.ZERO
	if absf(toward.x) > absf(toward.y):
		var x := cell.end.x if toward.x > 0.0 else cell.position.x
		a = Vector2(x, cell.position.y)
		b = Vector2(x, cell.end.y)
	else:
		var z := cell.end.y if toward.y > 0.0 else cell.position.y
		a = Vector2(cell.position.x, z)
		b = Vector2(cell.end.x, z)
	# A diagonal break across the slab itself too, now and then.
	if _h01([c.x, c.y, "heave_diag"]) < 0.5:
		_crack(ctx, cell.position.lerp(cell.end, 0.1), Vector2(cell.end.x, cell.position.y).lerp(Vector2(cell.position.x, cell.end.y), 0.15), 0.06, 0.3, TOP + float(h[2]) * 0.55 + 0.002)


## A crack decal from a to b (width w), `h` over the ground.
static func _crack(ctx: Dictionary, a: Vector2, b: Vector2, w: float, seed: float, h: float) -> void:
	var d := (b - a)
	var length := d.length()
	if length < 0.1:
		return
	var side := Vector2(-d.y, d.x) / length * w * 0.5
	_mquad(ctx, _v3(ctx, a - side, h), _v3(ctx, b - side, h), _v3(ctx, b + side, h), _v3(ctx, a + side, h), Vector3.UP, Kind.CRACK, Color(0.05, 0.045, 0.04),
		Vector2(0.0, 0.0), Vector2(length, 0.0), Vector2(length, 1.0), Vector2(0.0, 1.0), Vector2(seed, w))


## The marks mesh tiles into the chunk.
static func _commit(ctx: Dictionary) -> void:
	var ch: CityChunk = ctx.ch
	var marks: Dictionary = ctx.marks
	for k: Vector2i in marks:
		var st: SurfaceTool = marks[k]
		var mi := MeshInstance3D.new()
		mi.name = "KerbMarks"
		mi.mesh = st.commit()
		mi.material_override = material()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		mi.visibility_range_end = MARKS_DRAW
		mi.visibility_range_end_margin = 20.0
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		ch.add_child(mi)


# --- Shared resources -----------------------------------------------------------------------------

static func material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = load("res://shaders/kerb_marks.gdshader")
	return _material


## The street tree's cast-iron grate (the tree_grate batch's mesh): a 1.6 m plate, its frame and a
## centre opening, the pattern drawn by the marks shader (Kind.GRATE). The plate's top sits where
## the old box's did (instance origin + 1.5 cm).
static func grate_mesh() -> ArrayMesh:
	if _grate != null:
		return _grate
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cc := Color(0.11, 0.105, 0.10, (float(Kind.GRATE) + 0.5) / 16.0)
	var s := 0.8
	var y := 0.012
	var cs := [Vector3(-s, y, -s), Vector3(s, y, -s), Vector3(s, y, s), Vector3(-s, y, s)]
	var order := [cs[0], cs[2], cs[1], cs[0], cs[3], cs[2]]
	for v: Vector3 in order:
		st.set_color(cc)
		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(v.x, v.z))
		st.set_uv2(Vector2.ZERO)
		st.add_vertex(v)
	# The frame's outer edge (a low lip all round), so it never reads as paper at a grazing view.
	for i in 4:
		var a: Vector3 = cs[i]
		var b: Vector3 = cs[(i + 1) % 4]
		var out := ((a + b) * 0.5) * Vector3(1, 0, 1)
		out = out.normalized()
		var a0 := a - Vector3(0.0, 0.02, 0.0)
		var b0 := b - Vector3(0.0, 0.02, 0.0)
		var quad := [a, b, b0, a, b0, a0]
		var n := (b - a).cross(b0 - a)
		if n.dot(out) > 0.0:
			quad = [a, b0, b, a, a0, b0]
		for v: Vector3 in quad:
			st.set_color(cc)
			st.set_normal(out)
			st.set_uv(Vector2(v.x, v.z) * 0.0 + Vector2(0.81, 0.81))
			st.set_uv2(Vector2.ZERO)
			st.add_vertex(v)
	_grate = st.commit()
	_grate.surface_set_material(0, material())
	return _grate
