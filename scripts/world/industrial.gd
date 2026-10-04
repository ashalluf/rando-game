class_name Industrial
extends RefCounted
## The INDUSTRIAL district as Los Angeles industry (2026-10-04, owner: "make the graphics a
## million times better"): east of the 110 down to the port it is Vernon and the Alameda corridor,
## east of Vignes the Arts District. Before this every lot was a `Building` WAREHOUSE (a box with
## ribbon windows, an office block in all but name) or a slab, standing alone on bare paving
## (40 % of the district's block ground, tools/lot_coverage.gd).
##
## What a block is now:
##   - A WAREHOUSE lot is a tilt-up concrete warehouse built here (Building is never made for it):
##     panels with their joints and reveals, a parapet with its coping, a membrane roof with
##     skylights and rooftop units, a glazed office at one front corner, and - where the lot is
##     deep enough - a TRUCK COURT between it and the street: dock doors along the front with their
##     seals, bumpers and dock lights, trailers backed onto some of them (a tractor coupled to a
##     few), a concrete dock apron, trailer stall stripes, chain-link with barbed wire along the
##     street with a rolling gate open. A shallow lot gets grade-level roll-up doors instead and its
##     setback is employee parking or weeds. In the Arts District the warehouses are BRICK (steel
##     multi-pane windows, soot) and their street-facing side walls carry large ORIGINAL murals
##     (abstract, invented in the shader: no real artist's work, no lettering, no brand).
##   - Every other lot (a slab: offices, workshops; brick lofts in the Arts District) stays a
##     Building; the ground its cell leaves is a yard.
##   - The block's ground is all spoken for: courts, storage yards (gravel or cracked asphalt with
##     pallet loads, drums, dumpsters, roll-offs, shipping containers, a corrugated shed, a group of
##     storage tanks in a containment wall), drive aisles, weedy dirt strips, and on some blocks a
##     RAIL SPUR down the middle between the rows of lots (ballast and ties, two rails, bumper
##     stops, boxcars and tank cars standing on it, rail doors on the warehouses backing onto it).
##     Now and then an elevated steel water tower.
## Every roll is a hash of the plan seed and the lot or block (never the chunk rng, Building's own
## or the block rng), so nothing else in the city moves; every plan is PURE (lot_plan(),
## block_plan(): the plan, the block, each lot and its planned building), which is how
## GroundCoverage asks the chunk's own question. A FULL chunk's industrial geometry is TWO meshes
## (the ground on shaders/industrial_ground.gdshader, no shadow, its stall paint lifted in it; everything
## upright on shaders/industrial_walls.gdshader, every prop - trailers, tractors, rail cars,
## pallets, drums, bins, tanks, the water tower - written into it by IndustrialKit.place()) and one
## shadowless batch of light pools; containers are PortKit's batch. LOD
## chunks and the far city's capture get the warehouses, trailers, rail cars, tanks and the water
## tower as plain far boxes and the yards as ground slabs - nothing else.

## Off, every industrial lot builds as it did before this (the A/B: INDUSTRIAL=0 on still_shot.gd
## and block_shot.tscn; FILL=yard on tools/lot_coverage.gd).
static var enabled: bool = true

# --- Ground kinds: shaders/industrial_ground.gdshader, COLOR.r in 16ths -------------------------
const G_ASPHALT := 0
const G_CONCRETE := 1
const G_GRAVEL := 2
const G_DIRT := 3
const G_BALLAST := 4
const G_PAINT := 5
const G_WEEDS := 6

## The ground's top over the pavement slab, its paint's, and the skirt below them (metres).
const LIFT := 0.05
const PAINT_LIFT := 0.062
const SKIRT := 0.12

# --- The warehouse ------------------------------------------------------------------------------
## A lot at least this deep (metres, cell edge to cell edge across the street) gets a truck court.
const COURT_MIN_LOT := 44.0
## The court's depth: this share of the cell's depth, clamped (metres).
const COURT_SHARE := 0.44
const COURT_DEPTH := Vector2(19.5, 30.0)
## The shallowest a warehouse may be (metres front to back); a court that would leave less is
## dropped.
const MIN_DEPTH := 14.0
## Its parapet over the roof, its wall's thickness, and the target panel width (metres).
const PARAPET := 1.05
const WALL := 0.28
const PANEL := 7.6
## Docks: a door every this many metres (real dock spacing is 12-14 ft), its opening, its sill
## over the court (a trailer's floor), and the end of the front wall kept for the office.
const DOCK_PITCH := 4.25
const DOCK_DOOR := Vector2(2.75, 3.05)
const DOCK_SILL := 1.22
const OFFICE_RUN := Vector2(9.0, 14.0)
## A grade-level roll-up door.
const GRADE_DOOR := Vector2(3.7, 4.3)
## Odds a dock has a trailer at it, and that the trailer still has its tractor.
const TRAILER_ODDS := 0.55
const TRACTOR_ODDS := 0.22
## The dock apron (concrete) in front of the dock wall, metres.
const APRON := 5.0
## Chain-link: its height, the barbed wire over it, the opening of a court's gate.
const FENCE_H := 2.4
const BARBED_H := 0.5
const GATE := 13.0
## Odds a street-facing side wall carries a mural: in the Arts District and elsewhere.
const MURAL_ARTS := 0.75
const MURAL_ELSEWHERE := 0.08

# --- The block ----------------------------------------------------------------------------------
## Odds a block with room for one (two rows of lots, at least SPUR_CLEAR between them) has a rail
## spur down the middle, and the clear width it needs.
const SPUR_ODDS := 0.5
const SPUR_CLEAR := 5.6
## Gauge (rail centres) and the ballast's width.
const GAUGE := 1.5
const BALLAST_W := 4.2
## Odds a spur has cars standing on it, and how much of it they cover at most.
const SPUR_CARS := 0.8
## Odds a storage yard big enough has a group of storage tanks, a corrugated shed, a water tower.
const TANK_ODDS := 0.35
const SHED_ODDS := 0.4
const TOWER_ODDS := 0.09
## Per-chunk budgets.
const MAX_TRAILERS := 40
const MAX_PALLETS := 90
const MAX_CONTAINERS := 16

## Tilt-up paints (sRGB, as written): warm whites, greys, sand, a pale blue-grey and a sage.
const TILT_PAINTS := [Color(0.86, 0.84, 0.79), Color(0.80, 0.80, 0.78), Color(0.88, 0.86, 0.80), Color(0.74, 0.72, 0.67),
	Color(0.83, 0.78, 0.68), Color(0.72, 0.75, 0.76), Color(0.76, 0.77, 0.70), Color(0.91, 0.90, 0.87), Color(0.66, 0.65, 0.62)]
## Brick (the Arts District): the paint is a multiplier on the photographed brick.
const BRICK_PAINTS := [Color(1.0, 0.95, 0.9), Color(0.92, 0.84, 0.78), Color(1.05, 1.0, 0.96), Color(0.85, 0.82, 0.8)]
## Dock and roll-up doors.
const DOOR_PAINTS := [Color(0.78, 0.79, 0.80), Color(0.25, 0.30, 0.38), Color(0.88, 0.88, 0.86), Color(0.30, 0.34, 0.30),
	Color(0.55, 0.20, 0.17), Color(0.66, 0.64, 0.58)]
## Trailers (mostly plain white, some grey, a few in a fleet colour) and tractors.
const TRAILER_PAINTS := [Color(0.95, 0.95, 0.93), Color(0.95, 0.95, 0.93), Color(0.95, 0.95, 0.93), Color(0.93, 0.93, 0.9),
	Color(0.78, 0.79, 0.8), Color(0.55, 0.62, 0.72), Color(0.72, 0.28, 0.22), Color(0.88, 0.70, 0.25), Color(0.4, 0.55, 0.42)]
const TRACTOR_PAINTS := [Color(0.92, 0.92, 0.92), Color(0.08, 0.08, 0.09), Color(0.62, 0.08, 0.07), Color(0.12, 0.22, 0.48),
	Color(0.55, 0.57, 0.6), Color(0.85, 0.55, 0.12), Color(0.2, 0.4, 0.26), Color(0.4, 0.1, 0.25)]
const BOXCAR_PAINTS := [Color(0.42, 0.17, 0.11), Color(0.45, 0.2, 0.12), Color(0.3, 0.33, 0.36), Color(0.55, 0.42, 0.18),
	Color(0.22, 0.3, 0.26), Color(0.62, 0.62, 0.6), Color(0.18, 0.24, 0.42)]
const TANK_PAINTS := [Color(0.92, 0.92, 0.9), Color(0.82, 0.83, 0.82), Color(0.9, 0.88, 0.8), Color(0.66, 0.70, 0.66)]
const DRUM_PAINTS := [Color(0.14, 0.26, 0.55), Color(0.1, 0.1, 0.11), Color(0.5, 0.52, 0.55), Color(0.62, 0.18, 0.1)]
const BIN_PAINTS := [Color(0.16, 0.32, 0.2), Color(0.12, 0.2, 0.42), Color(0.45, 0.47, 0.5), Color(0.55, 0.32, 0.15)]
## The far boxes' colours (linear-ish, as Building's facade colours go to lod_box).
const FAR_ROOF := Color(0.62, 0.62, 0.6)


static func wanted(ch: CityChunk, district: int) -> bool:
	return enabled and ch.zone == MacroMap.Zone.CITY and district == CityPlan.District.INDUSTRIAL


## The Arts District (east of Vignes, MacroMap.district_at()'s second industrial rect).
static func arts(plan: CityPlan, p: Vector2) -> bool:
	if plan.macro == null:
		return false
	var ext := DowntownReal.game_extent()
	var m := plan.macro
	return p.x > ext.end.x and p.y > m.downtown_center.y + m.arts_district_z.x and p.y < m.downtown_center.y + m.arts_district_z.y


static func _h01(parts: Array) -> float:
	return float(absi(hash(parts)) % 100003) / 100003.0


## True when nothing of the freeway (deck, pillars, ramps) is within a metre of `r`: rail cars,
## trailers, tanks and the water tower stay out from under the decks (tests/downtown_checks.gd
## holds every far box to that).
static func clear_of_freeway(plan: CityPlan, r: Rect2) -> bool:
	return plan.macro == null or plan.macro.freeway == null or not plan.macro.freeway.blocks_rect(r, 1.0)


static func _box_rect(c: Vector2, along: Vector2, length: float, width: float) -> Rect2:
	var half := Vector2(absf(along.x) * length + absf(along.y) * width, absf(along.y) * length + absf(along.x) * width) * 0.5
	return Rect2(c - half, half * 2.0)


static func _pick(list: Array, parts: Array) -> Variant:
	return list[absi(hash(parts)) % list.size()]


# --- Frames -------------------------------------------------------------------------------------

## Which side of the block's inner rect `c` is nearest: 0 -Z, 1 +Z, 2 -X, 3 +X.
static func street_side(inner: Rect2, c: Vector2) -> int:
	var d := [c.y - inner.position.y, inner.end.y - c.y, c.x - inner.position.x, inner.end.x - c.x]
	var best := 0
	for i in 4:
		if float(d[i]) < float(d[best]):
			best = i
	return best


## The street a warehouse faces: of the sides its cell has on a street, the one it is deepest
## from (room for a truck court), the nearest on a tie.
static func lot_side(inner: Rect2, cell: Rect2) -> int:
	var on := [absf(cell.position.y - inner.position.y) < 0.6, absf(cell.end.y - inner.end.y) < 0.6,
		absf(cell.position.x - inner.position.x) < 0.6, absf(cell.end.x - inner.end.x) < 0.6]
	var best := -1
	var best_depth := -1.0
	for i in 4:
		if not on[i]:
			continue
		var depth := cell.size.y if i < 2 else cell.size.x
		if depth > best_depth + 0.5:
			best = i
			best_depth = depth
	return best if best >= 0 else street_side(inner, cell.get_center())


## A cell's frame, the street on `side`: u along the street (0..len), v in from the street edge
## (0..depth). `o` is the world point (u 0, v 0), `a` the unit along u, `n` the unit inward.
static func frame(cell: Rect2, side: int) -> Dictionary:
	match side:
		0:
			return {"o": cell.position, "a": Vector2(1, 0), "n": Vector2(0, 1), "len": cell.size.x, "depth": cell.size.y}
		1:
			return {"o": Vector2(cell.end.x, cell.end.y), "a": Vector2(-1, 0), "n": Vector2(0, -1), "len": cell.size.x, "depth": cell.size.y}
		2:
			return {"o": Vector2(cell.position.x, cell.end.y), "a": Vector2(0, -1), "n": Vector2(1, 0), "len": cell.size.y, "depth": cell.size.x}
		_:
			return {"o": Vector2(cell.end.x, cell.position.y), "a": Vector2(0, 1), "n": Vector2(-1, 0), "len": cell.size.y, "depth": cell.size.x}


static func fp(f: Dictionary, u: float, v: float) -> Vector2:
	return (f.o as Vector2) + (f.a as Vector2) * u + (f.n as Vector2) * v


## A frame rect (u0..u1, v0..v1) as a world rect.
static func fr(f: Dictionary, u0: float, v0: float, u1: float, v1: float) -> Rect2:
	var p := fp(f, u0, v0)
	var q := fp(f, u1, v1)
	return Rect2(Vector2(minf(p.x, q.x), minf(p.y, q.y)), Vector2(absf(q.x - p.x), absf(q.y - p.y)))


## The yaw that turns local +z onto the world direction `d` (Forward is -Z: yaw = atan2(-d.x, -d.z)
## turns -z onto d, so +z needs the opposite).
static func yaw_to(d: Vector2) -> float:
	return atan2(d.x, d.y)


# --- The pure plans -----------------------------------------------------------------------------

## The rail spur a block has, or {}: down the middle between two rows of lots, the whole length of
## the block's inner rect. {"rect": the ballast's world rect, "axis": 0 runs along x, 1 along z,
## "c": the centre line's coordinate (z for axis 0), "a"/"b": the inner rect's ends along it,
## "clear": metres between the lots either side}.
static func spur(plan: CityPlan, bx: int, bz: int) -> Dictionary:
	var b: Dictionary = plan.block(bx, bz)
	if int(b.district) != CityPlan.District.INDUSTRIAL or int(b.kind) != CityPlan.BlockKind.BUILDINGS:
		return {}
	if _h01([plan.seed, bx, bz, "ind_spur"]) >= SPUR_ODDS:
		return {}
	var inner: Rect2 = (b.rect as Rect2).grow(-plan.sidewalk_width)
	var lots := plan.lots(bx, bz)
	if lots.size() < 2:
		return {}
	var best := {}
	for axis in 2:
		# Rows across `axis`: lots grouped by their centre's other coordinate.
		var rows := {}
		for lot: Dictionary in lots:
			var c: Vector2 = lot.center
			var k := snappedf(c.y if axis == 0 else c.x, 0.5)
			rows[k] = true
		if rows.size() != 2:
			continue
		var keys: Array = rows.keys()
		keys.sort()
		var lo_end := -INF
		var hi_start := INF
		for lot: Dictionary in lots:
			var c: Vector2 = lot.center
			var half: float = (lot.size as Vector2).y * 0.5 if axis == 0 else (lot.size as Vector2).x * 0.5
			var k: float = c.y if axis == 0 else c.x
			if absf(k - float(keys[0])) < 1.0:
				lo_end = maxf(lo_end, k + half)
			else:
				hi_start = minf(hi_start, k - half)
		var clear := hi_start - lo_end
		if clear < SPUR_CLEAR:
			continue
		var mid := (lo_end + hi_start) * 0.5
		var length := inner.size.x if axis == 0 else inner.size.y
		if length < 60.0:
			continue
		if best.is_empty() or clear > float(best.clear):
			var r := Rect2(inner.position.x, mid - BALLAST_W * 0.5, inner.size.x, BALLAST_W) if axis == 0 \
				else Rect2(mid - BALLAST_W * 0.5, inner.position.y, BALLAST_W, inner.size.y)
			best = {"rect": r, "axis": axis, "c": mid, "a": inner.position.x if axis == 0 else inner.position.y,
				"b": inner.end.x if axis == 0 else inner.end.y, "clear": clear}
	return best


## A warehouse lot's plan, from the plan, its block, the lot and the WAREHOUSE part Building laid
## out for it (whose height it keeps). Pure.
static func lot_plan(plan: CityPlan, bx: int, bz: int, lot: Dictionary, part: Vector3) -> Dictionary:
	var b: Dictionary = plan.block(bx, bz)
	var inner: Rect2 = (b.rect as Rect2).grow(-plan.sidewalk_width)
	var cell: Rect2 = lot.get("cell", Rect2((lot.center as Vector2) - (lot.size as Vector2) * 0.5, lot.size))
	var side := lot_side(inner, cell)
	var f := frame(cell, side)
	var size: Vector2 = lot.size
	var lot_len: float = size.x if side < 2 else size.y
	var lot_depth: float = size.y if side < 2 else size.x
	var L: float = f.len
	var D: float = f.depth
	var s: int = lot.seed
	# Along the street: the lot's own frontage, trimmed a little each side for the drive aisles.
	var w := lot_len * lerpf(0.86, 0.95, _h01([s, "ind_w"]))
	var u0 := (L - w) * 0.5
	# Across: a truck court in front where the lot is deep enough, else a short setback.
	var sp := spur(plan, bx, bz)
	var back := D - (D - lot_depth) * 0.5 - 0.5
	var rail_back := false
	if not sp.is_empty():
		var sr: Rect2 = sp.rect
		var cell_back := fr(f, 0.0, D - 0.1, L, D)
		if cell_back.grow(1.0).intersects(sr):
			# The spur runs behind this lot: back off its clearance and give the wall rail doors.
			var clear_v := D - (float(sp.clear) * 0.5 - 2.2)
			back = minf(back, clear_v)
			rail_back = true
	var court := 0.0
	var p := arts(plan, cell.get_center())
	var brick := p and _h01([s, "ind_brick"]) < 0.8
	# An Arts District brick warehouse stands at the back of the pavement, as they do on the old
	# streets east of Alameda; a tilt-up one is set back behind its court or a strip.
	var front := (D - lot_depth) * 0.5 + (lerpf(0.0, 0.6, _h01([s, "ind_front"])) if brick else lerpf(1.5, 4.0, _h01([s, "ind_front"])))
	if lot_depth >= COURT_MIN_LOT and not brick:
		court = clampf(D * COURT_SHARE, COURT_DEPTH.x, COURT_DEPTH.y)
		if back - court < MIN_DEPTH:
			court = 0.0
	var v0 := court if court > 0.0 else front
	if back - v0 < MIN_DEPTH:
		v0 = maxf(0.5, back - MIN_DEPTH)
	var h: float = part.y
	var out := {
		"cell": cell, "side": side, "frame": f, "u0": u0, "u1": u0 + w, "v0": v0, "v1": back,
		"rect": fr(f, u0, v0, u0 + w, back), "h": h, "court": court, "rail_back": rail_back,
		"brick": brick, "arts": p,
		"paint": _pick(TILT_PAINTS, [s, "ind_paint"]), "brick_paint": _pick(BRICK_PAINTS, [s, "ind_bpaint"]),
		"door": _pick(DOOR_PAINTS, [s, "ind_door"]), "office_left": _h01([s, "ind_office"]) < 0.5,
		"seed": s,
	}
	# The side walls that face a street (a corner lot): murals go there.
	var murals: Array = []
	var odds := MURAL_ARTS if p else MURAL_ELSEWHERE
	for e in 2:
		var u_edge: float = u0 if e == 0 else u0 + w
		var probe := fp(f, u_edge + (-1.0 if e == 0 else 1.0) * 1.0, (v0 + back) * 0.5)
		var to_edge := minf(minf(probe.x - inner.position.x, inner.end.x - probe.x), minf(probe.y - inner.position.y, inner.end.y - probe.y))
		if to_edge < (L - w) * 0.5 + 3.0 and _h01([s, "ind_mural", e]) < odds:
			murals.append(e)
	# In the Arts District the front wall carries one too when there is no court in front of it.
	if p and court == 0.0 and _h01([s, "ind_mural_front"]) < 0.45:
		murals.append(2)
	out["murals"] = murals
	out["docks"] = _docks(out)
	return out


## The front wall's openings, in u along the street: [{u, kind: 0 dock / 1 grade door / 2 office}].
static func _docks(lp: Dictionary) -> Array:
	var u0: float = lp.u0
	var u1: float = lp.u1
	var s: int = lp.seed
	var office := lerpf(OFFICE_RUN.x, OFFICE_RUN.y, _h01([s, "ind_office_run"]))
	var out: Array = []
	var left: bool = lp.office_left
	var a := u0 + (office if left else 2.5)
	var b := u1 - (2.5 if left else office)
	out.append({"u": (u0 + office * 0.5) if left else (u1 - office * 0.5), "kind": 2, "w": office})
	if float(lp.court) > 0.0 and not lp.brick:
		# Docks across the rest, a grade door at the far end.
		var n := floori((b - a - GRADE_DOOR.x - 2.0) / DOCK_PITCH)
		var start := a + DOCK_PITCH * 0.5 if left else b - DOCK_PITCH * 0.5
		var step := DOCK_PITCH if left else -DOCK_PITCH
		for i in maxi(n, 0):
			out.append({"u": start + step * i, "kind": 0})
		out.append({"u": (b - GRADE_DOOR.x * 0.5 - 0.8) if left else (a + GRADE_DOOR.x * 0.5 + 0.8), "kind": 1})
	else:
		# Grade-level roll-up doors, two or three spaced along.
		var n := clampi(floori((b - a) / 11.0), 1, 3)
		for i in n:
			out.append({"u": lerpf(a, b, (float(i) + 0.5) / float(n)), "kind": 1})
	return out


## The block's ground and dressing, from its lots' entries ({lot, parts: ground rects, plan: a
## lot_plan or {}}). Pure. {"pieces": [[Rect2, role, kind]], "spur": spur(), "fences": [[a, b]],
## "tower": Vector2 or null}. Roles: "court", "store", "strip", "front", "apron".
static func block_plan(plan: CityPlan, bx: int, bz: int, entries: Array) -> Dictionary:
	var b: Dictionary = plan.block(bx, bz)
	var inner: Rect2 = (b.rect as Rect2).grow(-plan.sidewalk_width)
	var sp := spur(plan, bx, bz)
	var spur_rect: Rect2 = sp.rect if not sp.is_empty() else Rect2()
	var pieces: Array = []
	var fences: Array = []
	for e: Dictionary in entries:
		var lot: Dictionary = e.lot
		var lp: Dictionary = e.plan
		var cell: Rect2 = lot.get("cell", Rect2((lot.center as Vector2) - (lot.size as Vector2) * 0.5, lot.size))
		var side: int = lp.side if not lp.is_empty() else street_side(inner, cell.get_center())
		var f := frame(cell, side)
		var L: float = f.len
		var D: float = f.depth
		var s: int = lot.seed
		var raw: Array = []
		if not lp.is_empty():
			var u0: float = lp.u0
			var u1: float = lp.u1
			var v0: float = lp.v0
			var v1: float = lp.v1
			if float(lp.court) > 0.0:
				raw.append([fr(f, 0.0, 0.0, L, v0 - APRON), "court"])
				raw.append([fr(f, 0.0, v0 - APRON, L, v0), "apron"])
				# The court is fenced along the street, its gate open in the middle.
				var gc := L * 0.5 + (_h01([s, "ind_gate"]) - 0.5) * maxf(L - GATE - 6.0, 0.0)
				fences.append([fp(f, 0.0, 0.4), fp(f, gc - GATE * 0.5, 0.4)])
				fences.append([fp(f, gc + GATE * 0.5, 0.4), fp(f, L, 0.4)])
			else:
				raw.append([fr(f, 0.0, 0.0, L, v0), "front"])
			raw.append([fr(f, 0.0, v0, u0, v1), "strip"])
			raw.append([fr(f, u1, v0, L, v1), "strip"])
			raw.append([fr(f, 0.0, v1, L, D), "store" if D - v1 > 7.0 else "strip"])
		else:
			# A building's lot: the ground its cell leaves round the bounding rect of its parts.
			var bound := Rect2()
			for r: Rect2 in e.parts:
				bound = r if bound.size == Vector2.ZERO else bound.merge(r)
			if bound.size == Vector2.ZERO:
				raw.append([cell, "store"])
			else:
				var a0 := (bound.position - (f.o as Vector2))
				var a1 := (bound.end - (f.o as Vector2))
				var fa: Vector2 = f.a
				var fn: Vector2 = f.n
				var bu0 := clampf(minf(a0.dot(fa), a1.dot(fa)), 0.0, L)
				var bu1 := clampf(maxf(a0.dot(fa), a1.dot(fa)), 0.0, L)
				var bv0 := clampf(minf(a0.dot(fn), a1.dot(fn)), 0.0, D)
				var bv1 := clampf(maxf(a0.dot(fn), a1.dot(fn)), 0.0, D)
				raw.append([fr(f, 0.0, 0.0, L, bv0), "front"])
				raw.append([fr(f, 0.0, bv0, bu0, bv1), "strip"])
				raw.append([fr(f, bu1, bv0, L, bv1), "strip"])
				var back_role := "store" if D - bv1 > 8.0 and _h01([s, "ind_yard"]) < 0.7 else "strip"
				raw.append([fr(f, 0.0, bv1, L, D), back_role])
		for r: Array in raw:
			var rect: Rect2 = r[0]
			if rect.size.x < 0.4 or rect.size.y < 0.4:
				continue
			for piece: Rect2 in _minus(rect, spur_rect):
				if piece.size.x < 0.4 or piece.size.y < 0.4:
					continue
				pieces.append([piece, r[1], _ground_kind(plan, piece, String(r[1]), s), side])
	# Storage yards that reach a street are fenced along it too (a gate in the middle of each run).
	for pc: Array in pieces:
		if pc[1] != "store":
			continue
		var r: Rect2 = pc[0]
		for edge in 4:
			var line := _edge_line(r, edge)
			var mid: Vector2 = ((line[0] as Vector2) + (line[1] as Vector2)) * 0.5
			var on := (edge == 0 and absf(r.position.y - inner.position.y) < 0.6) or (edge == 1 and absf(r.end.y - inner.end.y) < 0.6) \
				or (edge == 2 and absf(r.position.x - inner.position.x) < 0.6) or (edge == 3 and absf(r.end.x - inner.end.x) < 0.6)
			if not on:
				continue
			var a: Vector2 = line[0]
			var bb: Vector2 = line[1]
			var inset := Vector2(0.0, 0.4) if edge == 0 else (Vector2(0.0, -0.4) if edge == 1 else (Vector2(0.4, 0.0) if edge == 2 else Vector2(-0.4, 0.0)))
			if a.distance_to(bb) > 16.0:
				var dir := (bb - a).normalized()
				fences.append([a + inset, mid - dir * 4.0 + inset])
				fences.append([mid + dir * 4.0 + inset, bb + inset])
			else:
				fences.append([a + inset, bb + inset])
	# The spur runs out to the street through a gap in every fence.
	if spur_rect.size != Vector2.ZERO:
		var cut: Array = []
		for fe: Array in fences:
			cut.append_array(_clip_segment(fe[0], fe[1], spur_rect.grow(0.6)))
		fences = cut
	# A water tower in the biggest storage yard, now and then.
	var tower: Variant = null
	if _h01([plan.seed, bx, bz, "ind_tower"]) < TOWER_ODDS:
		var best := 0.0
		for pc: Array in pieces:
			var r: Rect2 = pc[0]
			if pc[1] == "store" and minf(r.size.x, r.size.y) >= 11.5 and r.get_area() > best \
					and clear_of_freeway(plan, Rect2(r.get_center() - Vector2(6.0, 6.0), Vector2(12.0, 12.0))):
				best = r.get_area()
				tower = r.get_center()
	return {"pieces": pieces, "spur": sp, "fences": fences, "tower": tower, "inner": inner}


## Every lot of an INDUSTRIAL block planned the way CityChunk plans it, without a chunk: the
## entries block_plan() takes. Pad lots (rolled from the chunk's own rng) come out as their
## building here; corridor lots are left out (YardFill's). For GroundCoverage and the checks.
static func block_entries(plan: CityPlan, bx: int, bz: int) -> Array:
	var out: Array = []
	var b: Dictionary = plan.block(bx, bz)
	var district: int = b.district
	var boost: float = plan.macro.skyline_boost((b.rect as Rect2).get_center()) if plan.macro else 0.0
	var scene: PackedScene = load("res://scenes/props/building.tscn")
	for lot: Dictionary in plan.lots(bx, bz):
		if lot.yard or YardFill.is_corridor(plan, lot):
			continue
		var bld: Building = scene.instantiate()
		bld.seed = lot.seed
		bld.lot_size = lot.size
		var target: float = plan.lot_height(lot.seed, district, boost)
		bld.min_height = target * 0.88
		bld.max_height = target
		var sh: Array[int] = []
		sh.assign(CityPlan.lot_shapes(district, boost))
		bld.shape_options = sh
		var fi: Array[int] = []
		fi.assign([Building.Finish.BRICK, Building.Finish.BRICK, Building.Finish.BRICK, Building.Finish.PANELS] if arts(plan, lot.center) else CityPlan.lot_finishes(district, boost))
		bld.finish_options = fi
		bld.plan_only()
		var parts: Array[Rect2] = []
		var centre: Vector2 = lot.center
		for part: Dictionary in bld.parts:
			var size: Vector3 = part.size
			var c: Vector3 = part.center
			if c.y - size.y * 0.5 > 0.05:
				continue
			parts.append(Rect2(centre.x + c.x - size.x * 0.5, centre.y + c.z - size.z * 0.5, size.x, size.z))
		if bld.shape == Building.Shape.WAREHOUSE and not bld.parts.is_empty():
			var lp := lot_plan(plan, bx, bz, lot, (bld.parts[0] as Dictionary).size)
			out.append({"lot": lot, "parts": [lp.rect], "plan": lp})
		else:
			out.append({"lot": lot, "parts": parts, "plan": {}})
		bld.free()
	return out


## An axis-aligned segment less the part of it inside `hole`: [[a, b], ...].
static func _clip_segment(a: Vector2, b: Vector2, hole: Rect2) -> Array:
	var along_x := absf(b.x - a.x) >= absf(b.y - a.y)
	var lo := minf(a.x, b.x) if along_x else minf(a.y, b.y)
	var hi := maxf(a.x, b.x) if along_x else maxf(a.y, b.y)
	var cross := a.y if along_x else a.x
	var h_lo := hole.position.x if along_x else hole.position.y
	var h_hi := hole.end.x if along_x else hole.end.y
	var c_lo := hole.position.y if along_x else hole.position.x
	var c_hi := hole.end.y if along_x else hole.end.x
	if cross < c_lo or cross > c_hi or h_hi <= lo or h_lo >= hi:
		return [[a, b]]
	var out: Array = []
	var mk := func(t0: float, t1: float) -> Array:
		return [Vector2(t0, cross), Vector2(t1, cross)] if along_x else [Vector2(cross, t0), Vector2(cross, t1)]
	if h_lo - lo > 0.5:
		out.append(mk.call(lo, h_lo))
	if hi - h_hi > 0.5:
		out.append(mk.call(h_hi, hi))
	return out


static func side_on_street(inner: Rect2, r: Rect2) -> bool:
	return absf(r.position.y - inner.position.y) < 0.6 or absf(r.end.y - inner.end.y) < 0.6 \
		or absf(r.position.x - inner.position.x) < 0.6 or absf(r.end.x - inner.end.x) < 0.6


static func _ground_kind(plan: CityPlan, r: Rect2, role: String, s: int) -> int:
	match role:
		"court":
			return G_ASPHALT
		"apron":
			return G_CONCRETE
		"front":
			return G_ASPHALT if minf(r.size.x, r.size.y) >= 5.2 and _h01([s, "ind_front_park"]) < 0.6 else G_WEEDS
		"store":
			var x := _h01([plan.seed, s, r.position, "ind_store"])
			return G_GRAVEL if x < 0.45 else (G_ASPHALT if x < 0.85 else G_DIRT)
		_:
			var x := _h01([plan.seed, s, r.position, "ind_strip"])
			return G_ASPHALT if x < 0.5 else (G_DIRT if x < 0.8 else G_GRAVEL)


## `r` less `hole` (axis-aligned), as up to four rects.
static func _minus(r: Rect2, hole: Rect2) -> Array[Rect2]:
	var out: Array[Rect2] = []
	if hole.size == Vector2.ZERO or not r.intersects(hole):
		out.append(r)
		return out
	var h := r.intersection(hole)
	if h.position.y > r.position.y:
		out.append(Rect2(r.position.x, r.position.y, r.size.x, h.position.y - r.position.y))
	if h.end.y < r.end.y:
		out.append(Rect2(r.position.x, h.end.y, r.size.x, r.end.y - h.end.y))
	if h.position.x > r.position.x:
		out.append(Rect2(r.position.x, h.position.y, h.position.x - r.position.x, h.size.y))
	if h.end.x < r.end.x:
		out.append(Rect2(h.end.x, h.position.y, r.end.x - h.end.x, h.size.y))
	return out


static func _edge_line(r: Rect2, e: int) -> Array:
	match e:
		0:
			return [r.position, Vector2(r.end.x, r.position.y)]
		1:
			return [Vector2(r.position.x, r.end.y), r.end]
		2:
			return [r.position, Vector2(r.position.x, r.end.y)]
		_:
			return [Vector2(r.end.x, r.position.y), r.end]


# --- The chunk side -----------------------------------------------------------------------------

## CityChunk._build_lot(), for an INDUSTRIAL lot whose Building is set up (options, position) but
## not yet built: plans it, and when it is a WAREHOUSE builds the tilt-up warehouse instead and
## returns true (the chunk frees the Building). Any other lot is recorded for the block step and
## built by the chunk as before (false). In the Arts District the Building's finish is brick.
static func build_lot(ch: CityChunk, lot: Dictionary, bld: Building) -> bool:
	_state(ch)
	if arts(ch.plan, lot.center):
		var fi: Array[int] = [Building.Finish.BRICK, Building.Finish.BRICK, Building.Finish.BRICK, Building.Finish.PANELS]
		bld.finish_options = fi
	bld.plan_only()
	var centre: Vector2 = lot.center
	var parts: Array[Rect2] = []
	for part: Dictionary in bld.parts:
		var size: Vector3 = part.size
		var c: Vector3 = part.center
		if c.y - size.y * 0.5 > 0.05:
			continue
		parts.append(Rect2(centre.x + c.x - size.x * 0.5, centre.y + c.z - size.z * 0.5, size.x, size.z))
	if bld.shape != Building.Shape.WAREHOUSE or bld.parts.is_empty():
		# Building's FULL path builds it in _ready(); plan_only() marked it generated.
		bld._generated = false
		ch._ind.entries.append({"lot": lot, "parts": parts, "plan": {}})
		return false
	var lp := lot_plan(ch.plan, ch.ix, ch.iz, lot, (bld.parts[0] as Dictionary).size)
	var rect: Rect2 = lp.rect
	ch._ind.entries.append({"lot": lot, "parts": [rect], "plan": lp})
	ch._ind.foot.append(rect)
	ch._lot_rects.append(rect)
	var c := rect.get_center()
	var g := ch._gy(c.x, c.y)
	var h: float = lp.h
	if ch.level == CityChunk.Level.FULL and not ch.capturing:
		_warehouse(ch, lp)
	else:
		var col: Color = (lp.brick_paint as Color) * Color(0.5, 0.3, 0.24) if lp.brick else lp.paint
		ch._batch.add("lod_box", PropFactory.unit_box(), Transform3D(Basis().scaled(Vector3(rect.size.x, h + PARAPET, rect.size.y)),
			Vector3(c.x, CityChunk.SIDEWALK_TOP + (h + PARAPET) * 0.5, c.y)), col, Color(0.0, 0.0, 0.0, 1.0))
		ch._add_lod_shape(Vector3(rect.size.x, h, rect.size.y), Vector3(c.x, CityChunk.SIDEWALK_TOP + g + h * 0.5, c.y))
		ch._occluder_boxes.append([Transform3D(), Vector3(c.x, CityChunk.SIDEWALK_TOP + g + h * 0.5, c.y), Vector3(rect.size.x, h, rect.size.y)])
		_far_trailers(ch, lp)
	return true


static func _state(ch: CityChunk) -> void:
	if ch._ind.is_empty():
		ch._ind = {"entries": [], "foot": [], "walls": null, "ground": [], "paint": [], "counts": {}}


static func _walls(ch: CityChunk) -> SurfaceTool:
	if ch._ind.walls == null:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.set_smooth_group(-1)
		ch._ind.walls = st
	return ch._ind.walls


static func _count(ch: CityChunk, key: String, budget: int) -> bool:
	var n: int = int(ch._ind.counts.get(key, 0))
	if n >= budget:
		return false
	ch._ind.counts[key] = n + 1
	return true


## A box in the walls mesh at a chunk-space position whose y is over the relief already.
static func _wbox(ch: CityChunk, xf: Transform3D, size: Vector3, kind: int, paint: Color, param: float = 0.0, skip: int = 32) -> void:
	IndustrialKit.box(_walls(ch), xf, size, kind, paint, param, skip)


## The warehouse: walls, parapet, roof, the office, doors and docks, lamps, downspouts, rooftop
## units, murals, its collision and its occluder. FULL only.
static func _warehouse(ch: CityChunk, lp: Dictionary) -> void:
	var f: Dictionary = lp.frame
	var rect: Rect2 = lp.rect
	var c := rect.get_center()
	var s: int = lp.seed
	# The floor at the centre's ground; a plinth down to the lowest corner.
	var g := ch._gy(c.x, c.y)
	var gmin := g
	for k: Vector2 in [rect.position, rect.end, Vector2(rect.position.x, rect.end.y), Vector2(rect.end.x, rect.position.y)]:
		gmin = minf(gmin, ch._gy(k.x, k.y))
	var floor_y := CityChunk.SIDEWALK_TOP + g
	var h: float = lp.h
	var top := h + PARAPET
	var brick: bool = lp.brick
	var kind := IndustrialKit.K_BRICK if brick else IndustrialKit.K_TILTUP
	var paint: Color = lp.brick_paint if brick else lp.paint
	var fa: Vector2 = f.a
	var fn: Vector2 = f.n
	var u0: float = lp.u0
	var u1: float = lp.u1
	var v0: float = lp.v0
	var v1: float = lp.v1
	var w := u1 - u0
	var d := v1 - v0
	# The frame as 3D: +x along u, +z along v (inward), so yaw takes local +z to n.
	var basis := Basis(Vector3(fa.x, 0.0, fa.y), Vector3.UP, Vector3(fn.x, 0.0, fn.y))
	var cx := {"ch": ch, "basis": basis, "f": f, "floor": floor_y}
	# Plinth.
	if g - gmin > 0.02:
		_wbox(ch, Transform3D(Basis(), Vector3(c.x, floor_y - (g - gmin + 0.3) * 0.5, c.y)), Vector3(rect.size.x + 0.1, g - gmin + 0.3, rect.size.y + 0.1), IndustrialKit.K_CONCRETE, Color(0.62, 0.61, 0.58), 0.0, 32 | 16)
	# Walls: front (v0, facing the street), back, the two ends; each up through the parapet.
	_fb(cx, (u0 + u1) * 0.5, v0 + WALL * 0.5, top * 0.5, Vector3(w, top, WALL), kind, paint, _panel_w(brick, w))
	_fb(cx, (u0 + u1) * 0.5, v1 - WALL * 0.5, top * 0.5, Vector3(w, top, WALL), kind, paint, _panel_w(brick, w))
	_fb(cx, u0 + WALL * 0.5, (v0 + v1) * 0.5, top * 0.5, Vector3(WALL, top, d - WALL * 2.0), kind, paint, _panel_w(brick, d - WALL * 2.0))
	_fb(cx, u1 - WALL * 0.5, (v0 + v1) * 0.5, top * 0.5, Vector3(WALL, top, d - WALL * 2.0), kind, paint, _panel_w(brick, d - WALL * 2.0))
	# The roof deck inside the parapet (its top is the membrane), its seed in the param.
	_fb(cx, (u0 + u1) * 0.5, (v0 + v1) * 0.5, h - 0.15, Vector3(w - WALL * 2.0, 0.3, d - WALL * 2.0), IndustrialKit.K_ROOF, Color(0.9, 0.9, 0.88), float(s % 977), 15)
	# Skylights in rows (raised curbs with domes), rooftop units, a hatch.
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([ch.plan.seed, s, "ind_roof"])
	var sky_rows := maxi(1, floori((w - 8.0) / 12.0))
	var sky_cols := maxi(1, floori((d - 8.0) / 9.0))
	if not brick:
		for i in sky_rows:
			for j in sky_cols:
				var su := u0 + 4.0 + (w - 8.0) * (float(i) + 0.5) / float(sky_rows)
				var sv := v0 + 4.0 + (d - 8.0) * (float(j) + 0.5) / float(sky_cols)
				_fb(cx, su, sv, h + 0.12, Vector3(1.3, 0.24, 2.5), IndustrialKit.K_SKYLIGHT, Color(0.7, 0.75, 0.78))
	for i in clampi(floori(w * d / 600.0), 1, 6):
		var ru := rng.randf_range(u0 + 4.0, u1 - 4.0)
		var rv := rng.randf_range(v0 + 4.0, v1 - 4.0)
		var big := rng.randf() < 0.4
		var rs := Vector3(2.2, 1.3, 3.4) if big else Vector3(1.4, 1.0, 1.9)
		_fb(cx, ru, rv, h + rs.y * 0.5, rs, IndustrialKit.K_CORRUGATED, Color(0.72, 0.73, 0.72))
		_fb(cx, ru, rv, h + rs.y + 0.05, Vector3(rs.x - 0.2, 0.1, rs.z - 0.2), IndustrialKit.K_STEEL, Color(0.3, 0.31, 0.32))
	# Office: glass across the front corner (two storeys when it is tall), a canopy over the door.
	var docks: Array = lp.docks
	var front_v := v0 - 0.02
	var door_paint: Color = lp.door
	for dk: Dictionary in docks:
		var u: float = dk.u
		match int(dk.kind):
			2:
				var ow: float = dk.w
				_fb(cx, u, front_v - 0.02, 2.3, Vector3(ow - 1.2, 3.4, 0.06), IndustrialKit.K_GLASS, Color(0.3, 0.36, 0.4), 1.5)
				if h >= 9.0:
					_fb(cx, u, front_v - 0.02, 6.1, Vector3(ow - 1.2, 2.6, 0.06), IndustrialKit.K_GLASS, Color(0.3, 0.36, 0.4), 1.5)
				_fb(cx, u, front_v - 1.0, 4.25, Vector3(4.5, 0.25, 2.0), IndustrialKit.K_STEEL, Color(0.22, 0.23, 0.25))
				_fb(cx, u, front_v - 0.03, 1.15, Vector3(1.9, 2.3, 0.05), IndustrialKit.K_GLASS, Color(0.18, 0.2, 0.22), 0.95)
			0:
				# Dock door, its seal, bumpers, the dock light, the plate below.
				_fb(cx, u, front_v - 0.02, DOCK_SILL + DOCK_DOOR.y * 0.5, Vector3(DOCK_DOOR.x, DOCK_DOOR.y, 0.05), IndustrialKit.K_ROLLUP, door_paint, 0.075)
				_fb(cx, u, front_v - 0.2, DOCK_SILL + DOCK_DOOR.y + 0.32, Vector3(DOCK_DOOR.x + 0.7, 0.6, 0.38), IndustrialKit.K_RUBBER, Color(0.06, 0.06, 0.06))
				for sx: float in [-1.0, 1.0]:
					_fb(cx, u + sx * (DOCK_DOOR.x * 0.5 + 0.18), front_v - 0.2, DOCK_SILL + DOCK_DOOR.y * 0.5 - 0.1, Vector3(0.36, DOCK_DOOR.y + 0.2, 0.38), IndustrialKit.K_RUBBER, Color(0.07, 0.07, 0.07))
					_fb(cx, u + sx * 0.95, front_v - 0.1, DOCK_SILL - 0.25, Vector3(0.28, 0.5, 0.18), IndustrialKit.K_RUBBER, Color(0.05, 0.05, 0.05))
				_fb(cx, u, front_v - 0.06, DOCK_SILL - 0.02, Vector3(2.0, 0.04, 0.12), IndustrialKit.K_STEEL, Color(0.75, 0.62, 0.12))
				var lu := u + DOCK_DOOR.x * 0.5 + 0.6
				_fb(cx, lu, front_v - 0.42, DOCK_SILL + DOCK_DOOR.y + 0.1, Vector3(0.05, 0.05, 0.8), IndustrialKit.K_STEEL, Color(0.2, 0.2, 0.2))
				_fb(cx, lu, front_v - 0.85, DOCK_SILL + DOCK_DOOR.y + 0.02, Vector3(0.24, 0.16, 0.28), IndustrialKit.K_LAMP, Color(1.0, 0.9, 0.72))
				_pool(ch, _at(cx, u, v0 - 3.5, 0.0), 5.5, Color(1.0, 0.88, 0.7), 0.85)
				_dock_traffic(ch, lp, u)
			1:
				_fb(cx, u, front_v - 0.02, GRADE_DOOR.y * 0.5, Vector3(GRADE_DOOR.x, GRADE_DOOR.y, 0.05), IndustrialKit.K_ROLLUP, door_paint, 0.075)
				_fb(cx, u, front_v - 0.04, GRADE_DOOR.y + 0.12, Vector3(GRADE_DOOR.x + 0.4, 0.24, 0.12), IndustrialKit.K_STEEL, door_paint.darkened(0.4))
				for sx: float in [-1.0, 1.0]:
					IndustrialKit.cyl(_walls(ch), Transform3D(Basis(), _at(cx, u + sx * (GRADE_DOOR.x * 0.5 + 0.35), v0 - 0.45, 0.0)), 0.11, 1.1, IndustrialKit.K_STEEL, Color(0.9, 0.75, 0.1), 8, true)
	# Wall packs high on the front every other panel, and over the back (rail) wall.
	var pw: float = _panel_w(brick, w)
	var np := maxi(1, roundi(w / pw))
	for i in range(1, np, 2):
		var u := u0 + pw * float(i) + pw * 0.5
		_fb(cx, u, front_v - 0.12, h - 1.4, Vector3(0.36, 0.26, 0.22), IndustrialKit.K_LAMP, Color(1.0, 0.95, 0.85))
		_pool(ch, _at(cx, u, v0 - 5.0, 0.0), 11.0, Color(1.0, 0.94, 0.84), 0.55)
	# The end walls: a steel man door near the front, wall packs and downspouts down the side.
	for e in 2:
		var ue := u0 - 0.04 if e == 0 else u1 + 0.04
		var out := -1.0 if e == 0 else 1.0
		var side_basis := basis * Basis(Vector3.UP, PI * 0.5)
		var door_v := v0 + 3.0 + _h01([s, "ind_mandoor", e]) * minf(6.0, d * 0.3)
		_wbox(ch, Transform3D(side_basis, _at(cx, ue, door_v, 1.08)), Vector3(1.0, 2.16, 0.05), IndustrialKit.K_STEEL, (door_paint as Color).darkened(0.15))
		_wbox(ch, Transform3D(side_basis, _at(cx, ue + out * 0.06, door_v, 2.35)), Vector3(1.4, 0.08, 0.12), IndustrialKit.K_STEEL, Color(0.3, 0.3, 0.31))
		var ns := maxi(1, roundi((d - WALL * 2.0) / _panel_w(brick, d - WALL * 2.0)))
		var spw := (d - WALL * 2.0) / float(ns)
		for i in range(1, ns):
			var vv := v0 + WALL + spw * float(i)
			if i % 2 == 0:
				_wbox(ch, Transform3D(side_basis, _at(cx, ue + out * 0.08, vv, h * 0.5)), Vector3(0.14, h, 0.12), IndustrialKit.K_GALV, Color(0.62, 0.63, 0.62))
			else:
				_wbox(ch, Transform3D(side_basis, _at(cx, ue + out * 0.12, vv, h - 1.6)), Vector3(0.36, 0.26, 0.22), IndustrialKit.K_LAMP, Color(1.0, 0.95, 0.85))
				var pp := _at(cx, ue + out * 4.0, vv, 0.0)
				_pool(ch, pp, 9.0, Color(1.0, 0.94, 0.84), 0.45)
	# Downspouts on every other front and back joint.
	for i in range(2, np, 2):
		for vv: float in [v0 - 0.08, v1 + 0.08]:
			_fb(cx, u0 + pw * float(i), vv, h * 0.5, Vector3(0.14, h, 0.12), IndustrialKit.K_GALV, Color(0.62, 0.63, 0.62))
	# Rail doors on the back wall where the spur runs behind it.
	if lp.rail_back:
		var nd := maxi(1, floori((w - 6.0) / 16.0))
		for i in nd:
			var u := lerpf(u0 + 3.0, u1 - 3.0, (float(i) + 0.5) / float(nd))
			_fb(cx, u, v1 + 0.04, DOCK_SILL + 1.8, Vector3(3.0, 3.6, 0.05), IndustrialKit.K_ROLLUP, door_paint, 0.075)
			_fb(cx, u, v1 + 0.2, DOCK_SILL + 3.85, Vector3(3.6, 0.5, 0.35), IndustrialKit.K_RUBBER, Color(0.06, 0.06, 0.06))
			_fb(cx, u + 2.2, v1 + 0.2, DOCK_SILL + 3.4, Vector3(0.3, 0.22, 0.25), IndustrialKit.K_LAMP, Color(1.0, 0.9, 0.72))
	# Murals on the street-facing walls (0 the u0 end, 1 the u1 end, 2 the front).
	for m: int in lp.murals:
		var mh := minf(h - 0.9, 11.0)
		var col := Color(float(absi(hash([s, "mural", m])) % 251) / 255.0, float(absi(hash([s, "mural_b", m])) % 251) / 255.0, 0.5)
		if m == 2:
			var ml := minf(w - 4.0, 30.0)
			# Clear of the office and the doors: a run of the front wall's upper half.
			_fb(cx, (u0 + u1) * 0.5, front_v - 0.05, 4.6 + (h - 4.6) * 0.5, Vector3(ml, maxf(h - 5.2, 2.0), 0.02), IndustrialKit.K_MURAL, col, ml)
		else:
			var ml := minf(d - 3.0, 36.0)
			var uu := u0 - 0.03 if m == 0 else u1 + 0.03
			_wbox(ch, Transform3D(basis * Basis(Vector3.UP, PI * 0.5 if m == 0 else -PI * 0.5), _at(cx, uu, (v0 + v1) * 0.5, 0.5 + mh * 0.5)), Vector3(ml, mh, 0.02), IndustrialKit.K_MURAL, col, ml)
	# Collision: the shell as one box (the roof is walked on at h), and the occluder.
	ch._add_shape(Vector3(rect.size.x, top, rect.size.y), Vector3(c.x, floor_y + top * 0.5, c.y))
	ch._occluder_boxes.append([Transform3D(), Vector3(c.x, floor_y + h * 0.5, c.y), Vector3(rect.size.x, h, rect.size.y)])


static func _at(cx: Dictionary, u: float, v: float, y: float) -> Vector3:
	var p := fp(cx.f, u, v)
	return Vector3(p.x, float(cx.floor) + y, p.y)


## A box in the warehouse's frame: centre (u, v, y over the floor), size along (u, y, v).
static func _fb(cx: Dictionary, u: float, v: float, y: float, size: Vector3, k: int, col: Color, param: float = 0.0, skip: int = 32) -> void:
	_wbox(cx.ch, Transform3D(cx.basis, _at(cx, u, v, y)), size, k, col, param, skip)


static func _panel_w(brick: bool, len: float) -> float:
	return len / maxf(1.0, roundf(len / (5.2 if brick else PANEL)))


## A trailer at a dock (and now and then its tractor), facing the street, its doors at the seal.
static func _dock_traffic(ch: CityChunk, lp: Dictionary, u: float) -> void:
	var s: int = lp.seed
	var court: float = lp.court
	if court <= 0.0 or _h01([s, "ind_trl", int(u * 10.0)]) >= TRAILER_ODDS:
		return
	if not _count(ch, "trailers", MAX_TRAILERS):
		return
	var f: Dictionary = lp.frame
	var v0: float = lp.v0
	var kind := 2 if _h01([s, "ind_trl_k", int(u * 10.0)]) < 0.15 else (1 if _h01([s, "ind_trl_s", int(u * 10.0)]) < 0.35 else 0)
	var length := 16.15 if kind != 2 else 12.2
	var centre := fp(f, u + (_h01([s, "ind_trl_j", int(u * 10.0)]) - 0.5) * 0.12, v0 - 0.4 - length * 0.5)
	var out_dir := -(f.n as Vector2)
	var yaw := yaw_to(out_dir) + (_h01([s, "ind_trl_y", int(u * 10.0)]) - 0.5) * 0.02
	var paint: Color = _pick(TRAILER_PAINTS, [s, "ind_trl_p", int(u * 10.0)])
	if not clear_of_freeway(ch.plan, _box_rect(centre, out_dir, length, 2.6)):
		return
	_prop(ch, Vector3(centre.x, CityChunk.SIDEWALK_TOP + LIFT, centre.y), yaw, paint, IndustrialKit.trailer.bind(kind))
	ch._add_shape(Vector3(2.6, 3.0, length), Vector3(centre.x, CityChunk.SIDEWALK_TOP + ch._gy(centre.x, centre.y) + 2.55, centre.y), yaw)
	if court - APRON - length > 8.0 and _h01([s, "ind_trc", int(u * 10.0)]) < TRACTOR_ODDS:
		var sleeper := _h01([s, "ind_trc_s", int(u * 10.0)]) < 0.6
		var tl := 7.4 if sleeper else 6.2
		# Kingpin 1.2 m behind the trailer's nose over the fifth wheel 1.35 m ahead of the tractor's tail.
		var tc := centre + out_dir * (length * 0.5 - 1.2 + tl * 0.5 - 1.35)
		if not clear_of_freeway(ch.plan, _box_rect(tc, out_dir, tl, 2.5)):
			return
		_prop(ch, Vector3(tc.x, CityChunk.SIDEWALK_TOP + LIFT, tc.y), yaw, _pick(TRACTOR_PAINTS, [s, "ind_trc_p", int(u * 10.0)]), IndustrialKit.tractor.bind(sleeper))
		ch._add_shape(Vector3(2.5, 2.8, tl), Vector3(tc.x, CityChunk.SIDEWALK_TOP + ch._gy(tc.x, tc.y) + 1.6, tc.y), yaw)


## The same trailers as far boxes (LOD chunks and the far city).
static func _far_trailers(ch: CityChunk, lp: Dictionary) -> void:
	var f: Dictionary = lp.frame
	for dk: Dictionary in lp.docks:
		if int(dk.kind) != 0:
			continue
		var u: float = dk.u
		var s: int = lp.seed
		if float(lp.court) <= 0.0 or _h01([s, "ind_trl", int(u * 10.0)]) >= TRAILER_ODDS:
			continue
		var kind := 2 if _h01([s, "ind_trl_k", int(u * 10.0)]) < 0.15 else 0
		var length := 16.15 if kind != 2 else 12.2
		var centre := fp(f, u, float(lp.v0) - 0.4 - length * 0.5)
		if not clear_of_freeway(ch.plan, _box_rect(centre, -(f.n as Vector2), length, 2.6)):
			continue
		var sz := Vector3(2.6, 4.0, length) if (f.n as Vector2).y != 0.0 else Vector3(length, 4.0, 2.6)
		ch._batch.add("lod_box", PropFactory.unit_box(), Transform3D(Basis().scaled(sz), Vector3(centre.x, CityChunk.SIDEWALK_TOP + 2.1, centre.y)),
			_pick(TRAILER_PAINTS, [s, "ind_trl_p", int(u * 10.0)]) * 0.8, Color(0.0, 0.0, 0.0, 1.0))


## A prop (one of IndustrialKit's mesh functions) written into the chunk's walls mesh at `at`
## (relief added here), turned by `yaw`, painted by `tint`: no draw of its own.
static func _prop(ch: CityChunk, at: Vector3, yaw: float, tint: Color, build: Callable) -> void:
	IndustrialKit.place(_walls(ch), Transform3D(Basis(Vector3.UP, yaw), at + Vector3(0.0, ch._gy(at.x, at.z), 0.0)), tint, build)


## A light pool on the ground (additive, nothing by day), at a chunk-space point.
static func _pool(ch: CityChunk, at: Vector3, size: float, _tint: Color, _strength: float) -> void:
	# 15 cm over the yard: at a few centimetres the additive quad z-fought the asphalt at a grazing
	# angle and lit the court in stripes.
	var xf := Transform3D(Basis(Vector3.RIGHT, -PI * 0.5).scaled(Vector3(size, 1.0, size)), Vector3(at.x, CityChunk.SIDEWALK_TOP + LIFT + 0.15, at.z))
	# One batch a chunk whatever the lamp (the tint is the dock lights' warm white; the strength
	# rides the pool's size).
	ch._batch.add("ind_pool", PropFactory.light_pool(Color(1.0, 0.9, 0.74), 0.7, 1.6), xf)


## The block step, after every lot is down (any tier): the yards, the spur, fences, the water tower.
static func block_step(ch: CityChunk, block: Dictionary) -> void:
	if not wanted(ch, int(block.district)):
		return
	_state(ch)
	var bp := block_plan(ch.plan, ch.ix, ch.iz, ch._ind.entries)
	var full := ch.level == CityChunk.Level.FULL and not ch.capturing
	for pc: Array in bp.pieces:
		var r: Rect2 = pc[0]
		ch._lot_rects.append(r)
		if full:
			ch._ind.ground.append([r, int(pc[2]), _h01([ch.plan.seed, r.position, "ind_var"])])
		elif r.get_area() >= 60.0 and maxf(r.size.x, r.size.y) >= 6.0:
			var col := _far_ground(int(pc[2]))
			var c := r.get_center()
			ch._add_slab(Vector3(c.x, CityChunk.SIDEWALK_TOP + LIFT - 0.02, c.y), Vector3(r.size.x, 0.04, r.size.y), col, false, _far_material(int(pc[2])))
	var sp: Dictionary = bp.spur
	if not sp.is_empty():
		var sr: Rect2 = sp.rect
		if full:
			ch._ind.ground.append([sr, G_BALLAST, 0.0 if int(sp.axis) == 0 else 1.0, fposmod(float(sp.c), BALLAST_W) / BALLAST_W])
		else:
			var c := sr.get_center()
			ch._add_slab(Vector3(c.x, CityChunk.SIDEWALK_TOP + LIFT - 0.02, c.y), Vector3(sr.size.x, 0.04, sr.size.y), Color(0.42, 0.39, 0.36), false, _far_material(G_GRAVEL))
		ch._lot_rects.append(sr)
		_spur(ch, sp, full)
	if bp.tower != null:
		var t: Vector2 = bp.tower
		if full:
			_prop(ch, Vector3(t.x, CityChunk.SIDEWALK_TOP + LIFT, t.y), _h01([ch.plan.seed, ch.ix, ch.iz, "ind_tw_yaw"]) * TAU, Color.WHITE, IndustrialKit.water_tower)
			ch._add_shape(Vector3(9.0, 20.0, 9.0), Vector3(t.x, CityChunk.SIDEWALK_TOP + ch._gy(t.x, t.y) + 10.0, t.y))
		else:
			ch._batch.add("lod_box", PropFactory.unit_box(), Transform3D(Basis().scaled(Vector3(8.4, 7.5, 8.4)), Vector3(t.x, CityChunk.SIDEWALK_TOP + 24.5, t.y)), Color(0.8, 0.8, 0.78), Color(0.0, 0.0, 0.0, 1.0))
			ch._batch.add("lod_box", PropFactory.unit_box(), Transform3D(Basis().scaled(Vector3(5.0, 20.0, 5.0)), Vector3(t.x, CityChunk.SIDEWALK_TOP + 10.0, t.y)), Color(0.55, 0.55, 0.54), Color(0.0, 0.0, 0.0, 1.0))
	if not full:
		_far_yards(ch, bp)
		return
	for fe: Array in bp.fences:
		_fence(ch, fe[0], fe[1])
	# The yards' dressing, in slices before the finish (YardFill's way: the block's own props keep
	# their ids).
	var jobs: Array = []
	for pc: Array in bp.pieces:
		jobs.append(_dress.bind(ch, pc, bp))
	ch._run_or_defer(func() -> bool:
		var t0 := Time.get_ticks_usec()
		while not jobs.is_empty() and Time.get_ticks_usec() - t0 < 2500:
			(jobs.pop_front() as Callable).call()
		return jobs.is_empty())


static func _far_ground(kind: int) -> Color:
	match kind:
		G_CONCRETE:
			return Color(0.78, 0.77, 0.73)
		G_GRAVEL:
			return Color(0.58, 0.55, 0.5)
		G_DIRT, G_WEEDS:
			return Color(0.55, 0.48, 0.38)
		_:
			return Color(0.42, 0.42, 0.42)


static func _far_material(kind: int) -> Material:
	match kind:
		G_CONCRETE:
			return PropFactory.road("concrete", 4.0, Color(0.95, 0.94, 0.9), 0, 4.5, 0.6)
		G_GRAVEL, G_DIRT, G_WEEDS:
			return PropFactory.pbr("hill_dirt", 4.0, _far_ground(kind) * 1.4)
		_:
			return PropFactory.road("asphalt", 5.0, Color(0.9, 0.9, 0.9), 0, 0.0, 1.0)


## Far boxes for what a yard holds that reads from the air: the storage tanks.
static func _far_yards(ch: CityChunk, bp: Dictionary) -> void:
	for pc: Array in bp.pieces:
		var r: Rect2 = pc[0]
		if pc[1] != "store":
			continue
		var s := absi(hash([ch.plan.seed, r.position, "ind_dress"]))
		var tanks := _tank_spots(ch.plan, r, s)
		for t: Array in tanks:
			var p: Vector2 = t[0]
			var rad: float = t[1]
			var th: float = t[2]
			ch._batch.add("lod_box", PropFactory.unit_box(), Transform3D(Basis().scaled(Vector3(rad * 1.8, th, rad * 1.8)), Vector3(p.x, CityChunk.SIDEWALK_TOP + th * 0.5, p.y)),
				_pick(TANK_PAINTS, [s, "tank_p"]), Color(0.0, 0.0, 0.0, 1.0))


## A storage yard's tanks, when it rolls them: [[centre, radius, height]] (pure).
static func _tank_spots(plan: CityPlan, r: Rect2, s: int) -> Array:
	var out: Array = []
	if minf(r.size.x, r.size.y) < 13.0 or r.get_area() < 260.0 or _h01([s, "tanks"]) >= TANK_ODDS:
		return out
	var rad := lerpf(2.4, 3.6, _h01([s, "tank_r"]))
	var th := lerpf(6.0, 11.0, _h01([s, "tank_h"]))
	var step := rad * 2.0 + 1.6
	var along_x := r.size.x >= r.size.y
	var n := clampi(floori(((r.size.x if along_x else r.size.y) - 4.0) / step), 1, 4)
	var c := r.get_center()
	for i in n:
		var o := (float(i) - float(n - 1) * 0.5) * step
		var p := c + (Vector2(o, 0.0) if along_x else Vector2(0.0, o))
		if not clear_of_freeway(plan, Rect2(p - Vector2(rad, rad), Vector2(rad, rad) * 2.0)):
			return []
		out.append([p, rad, th])
	return out


## The rails, ties are the ground shader's, bumper stops, and the cars standing on it.
static func _spur(ch: CityChunk, sp: Dictionary, full: bool) -> void:
	var axis: int = sp.axis
	var c: float = sp.c
	var a: float = float(sp.a) + 1.5
	var b: float = float(sp.b) - 1.5
	var dir := Vector2(1, 0) if axis == 0 else Vector2(0, 1)
	var side := Vector2(0, 1) if axis == 0 else Vector2(1, 0)
	var p0 := (Vector2(a, c) if axis == 0 else Vector2(c, a))
	var length := b - a
	var rail_top := CityChunk.SIDEWALK_TOP + LIFT + 0.18
	if full:
		var n := maxi(1, ceili(length / 6.0))
		for i in n:
			var q0 := p0 + dir * (length * float(i) / float(n))
			var q1 := p0 + dir * (length * float(i + 1) / float(n))
			var m := (q0 + q1) * 0.5
			var seg := q0.distance_to(q1)
			for sx: float in [-1.0, 1.0]:
				var rp := m + side * sx * GAUGE * 0.5
				var size := Vector3(seg, 0.15, 0.08) if axis == 0 else Vector3(0.08, 0.15, seg)
				_wbox(ch, Transform3D(Basis(), Vector3(rp.x, rail_top - 0.075 + ch._gy(rp.x, rp.y), rp.y)), size, IndustrialKit.K_STEEL, Color(0.36, 0.3, 0.26), 0.0, 32)
		# Bumper stops at both ends.
		for e: float in [0.0, 1.0]:
			var q := p0 + dir * (length * e) + dir * (0.8 if e == 0.0 else -0.8)
			var size := Vector3(0.8, 1.2, 2.4) if axis == 0 else Vector3(2.4, 1.2, 0.8)
			_wbox(ch, Transform3D(Basis(), Vector3(q.x, rail_top + 0.45 + ch._gy(q.x, q.y), q.y)), size, IndustrialKit.K_STEEL, Color(0.75, 0.6, 0.1))
	# Cars: a string of boxcars and tank cars from one end.
	var s := absi(hash([ch.plan.seed, ch.ix, ch.iz, "ind_spur_cars"]))
	if _h01([s, "cars"]) >= SPUR_CARS:
		return
	var take := lerpf(0.35, 0.85, _h01([s, "share"])) * length
	var pos := 2.5 + _h01([s, "start"]) * maxf(length - take - 5.0, 0.0)
	var i := 0
	while pos < take + 2.5:
		var tank := _h01([s, "tank", i]) < 0.35
		var cl := 17.4 if tank else 16.2
		if pos + cl > length - 2.0:
			break
		var mid := p0 + dir * (pos + cl * 0.5)
		if not clear_of_freeway(ch.plan, _box_rect(mid, dir, cl, 3.2)):
			# The string of cars stops short of a deck over the spur.
			break
		var yaw := yaw_to(dir)
		var paint: Color = _pick(BOXCAR_PAINTS, [s, "paint", i])
		if tank:
			paint = Color(0.13, 0.13, 0.13) if _h01([s, "tp", i]) < 0.7 else Color(0.82, 0.82, 0.8)
		if full:
			_prop(ch, Vector3(mid.x, rail_top, mid.y), yaw, paint, IndustrialKit.tank_car if tank else IndustrialKit.boxcar)
			ch._add_shape(Vector3(3.2, 4.2, cl) , Vector3(mid.x, rail_top + ch._gy(mid.x, mid.y) + 2.6, mid.y), yaw)
		else:
			var sz := Vector3(cl, 4.4, 3.1) if axis == 0 else Vector3(3.1, 4.4, cl)
			ch._batch.add("lod_box", PropFactory.unit_box(), Transform3D(Basis().scaled(sz), Vector3(mid.x, rail_top + 2.6, mid.y)), paint, Color(0.0, 0.0, 0.0, 1.0))
		pos += cl + 0.9
		i += 1


## Chain-link with barbed wire on outriggers, posts every 3 m, a top rail; in pieces of up to 6 m
## so it follows the ground.
static func _fence(ch: CityChunk, a: Vector2, b: Vector2) -> void:
	var len := a.distance_to(b)
	if len < 0.8:
		return
	var dir := (b - a) / len
	var yaw := atan2(-dir.y, dir.x)
	var basis := Basis(Vector3.UP, yaw)
	var n := maxi(1, ceili(len / 6.0))
	var base := CityChunk.SIDEWALK_TOP + LIFT
	for i in n:
		var q0 := a.lerp(b, float(i) / float(n))
		var q1 := a.lerp(b, float(i + 1) / float(n))
		var m := (q0 + q1) * 0.5
		var seg := q0.distance_to(q1)
		var g := minf(ch._gy(q0.x, q0.y), ch._gy(q1.x, q1.y))
		_wbox(ch, Transform3D(basis, Vector3(m.x, base + g + FENCE_H * 0.5 - 0.05, m.y)), Vector3(seg, FENCE_H + 0.1, 0.03), IndustrialKit.K_CHAIN, Color(0.72, 0.73, 0.74), 0.0, 32 | 16)
		# Barbed wire on outriggers leaning out over the street.
		_wbox(ch, Transform3D(basis * Basis(Vector3.RIGHT, 0.6), Vector3(m.x, base + g + FENCE_H + BARBED_H * 0.4, m.y) + Vector3(dir.y, 0.0, -dir.x) * 0.0), Vector3(seg, BARBED_H, 0.02), IndustrialKit.K_BARBED, Color(0.6, 0.6, 0.6), 0.0, 32 | 16)
		_wbox(ch, Transform3D(basis, Vector3(m.x, base + g + FENCE_H, m.y)), Vector3(seg, 0.05, 0.05), IndustrialKit.K_GALV, Color(0.7, 0.71, 0.72))
		var np := maxi(1, ceili(seg / 3.0))
		for k in np + (1 if i == n - 1 else 0):
			var p := q0.lerp(q1, float(k) / float(np))
			_wbox(ch, Transform3D(basis, Vector3(p.x, base + ch._gy(p.x, p.y) + (FENCE_H + 0.35) * 0.5 - 0.1, p.y)), Vector3(0.07, FENCE_H + 0.35, 0.07), IndustrialKit.K_GALV, Color(0.66, 0.67, 0.68))
		ch._add_shape(Vector3(seg, FENCE_H, 0.1), Vector3(m.x, base + g + FENCE_H * 0.5, m.y), atan2(-dir.y, dir.x))


## One ground piece's dressing (FULL): trailer stall stripes in a court, parked cars on a front,
## the storage yards' loads, sheds and tanks, now and then a bin on a strip.
static func _dress(ch: CityChunk, pc: Array, bp: Dictionary) -> void:
	var r: Rect2 = pc[0]
	var role: String = pc[1]
	var kind: int = pc[2]
	var s := absi(hash([ch.plan.seed, r.position, "ind_dress"]))
	var base := CityChunk.SIDEWALK_TOP + LIFT
	var c := r.get_center()
	var long_x := r.size.x >= r.size.y
	match role:
		"front":
			if kind == G_ASPHALT:
				_stalls(ch, r, s, true)
		"court":
			# Stall stripes square to the dock wall (the court's long side meets the apron).
			var side: int = pc[3]
			var along_x := side < 2
			var w := r.size.x if along_x else r.size.y
			var n := floori(w / DOCK_PITCH)
			var depth := minf(r.size.y if along_x else r.size.x, 15.0)
			for i in n + 1:
				var t := (r.position.x if along_x else r.position.y) + (w - float(n) * DOCK_PITCH) * 0.5 + float(i) * DOCK_PITCH
				var span: Rect2
				if along_x:
					span = Rect2(t - 0.06, r.end.y - depth if side == 0 else r.position.y, 0.12, depth)
				else:
					span = Rect2(r.end.x - depth if side == 2 else r.position.x, t - 0.06, depth, 0.12)
				ch._ind.paint.append([span, 0.95])
		"store":
			_store(ch, r, s, kind)
		"strip":
			if minf(r.size.x, r.size.y) >= 3.0 and _h01([s, "bin"]) < 0.35 and _count(ch, "bins", 24):
				var big := _h01([s, "bin_big"]) < 0.3 and maxf(r.size.x, r.size.y) > 9.0 and minf(r.size.x, r.size.y) >= 3.4
				var yaw := 0.0 if not long_x else PI * 0.5
				var p := c + (Vector2((_h01([s, "bx"]) - 0.5) * maxf(r.size.x - 8.0, 0.0), 0.0) if long_x else Vector2(0.0, (_h01([s, "bx"]) - 0.5) * maxf(r.size.y - 8.0, 0.0)))
				_prop(ch, Vector3(p.x, base, p.y), yaw, _pick(BIN_PAINTS, [s, "binp"]), IndustrialKit.bin.bind(big))
				ch._add_shape(Vector3(2.4, 1.8, 6.7) if big else Vector3(1.8, 1.3, 1.2), Vector3(p.x, base + ch._gy(p.x, p.y) + 0.8, p.y), yaw)
			if minf(r.size.x, r.size.y) >= 2.0 and _h01([s, "pal"]) < 0.4:
				_pallet_row(ch, r, s, 3)


## Employee parking: a row of stalls along the piece's long side with cars in some.
static func _stalls(ch: CityChunk, r: Rect2, s: int, cars: bool) -> void:
	var long_x := r.size.x >= r.size.y
	var length := r.size.x if long_x else r.size.y
	var depth := r.size.y if long_x else r.size.x
	var n := floori((length - 1.0) / 2.7)
	var base := CityChunk.SIDEWALK_TOP + LIFT
	for i in n + 1:
		var t := (r.position.x if long_x else r.position.y) + (length - float(n) * 2.7) * 0.5 + float(i) * 2.7
		var stripe := Rect2(t - 0.05, r.position.y + 0.3, 0.1, minf(depth - 0.6, 5.0)) if long_x else Rect2(r.position.x + 0.3, t - 0.05, minf(depth - 0.6, 5.0), 0.1)
		ch._ind.paint.append([stripe, 0.95])
		if cars and i < n and _h01([s, "car", i]) < 0.55 and ch._yard_cars < 30:
			ch._yard_cars += 1
			var v := 0 if _h01([s, "cv", i]) < 0.6 else (2 if _h01([s, "cv2", i]) < 0.5 else 1)
			var p := Vector2(t + 1.35, r.position.y + minf(depth, 5.4) * 0.5 + 0.2) if long_x else Vector2(r.position.x + minf(depth, 5.4) * 0.5 + 0.2, t + 1.35)
			var yaw := (0.0 if long_x else PI * 0.5) + (PI if _h01([s, "cf", i]) < 0.5 else 0.0)
			ch._batch.add("apark_car_%d" % v, ArenaGrounds.car_mesh(v), Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x, base + 0.005, p.y)),
				_pick(ArenaGrounds.CAR_PAINTS, [s, "cp", i]))


## A storage yard: tanks (in a containment wall), else a shed and rows of pallet loads, drums,
## containers and a roll-off.
static func _store(ch: CityChunk, r: Rect2, s: int, kind: int) -> void:
	var base := CityChunk.SIDEWALK_TOP + LIFT
	var tanks := _tank_spots(ch.plan, r, s)
	if not tanks.is_empty():
		var paint: Color = _pick(TANK_PAINTS, [s, "tank_p"])
		var hull := Rect2()
		for t: Array in tanks:
			var p: Vector2 = t[0]
			var rad: float = t[1]
			var th: float = t[2]
			_prop(ch, Vector3(p.x, base, p.y), _h01([s, p]) * TAU, paint, IndustrialKit.storage_tank.bind(rad, th))
			ch._add_shape(Vector3(rad * 1.8, th, rad * 1.8), Vector3(p.x, base + ch._gy(p.x, p.y) + th * 0.5, p.y))
			var tr := Rect2(p - Vector2(rad + 1.0, rad + 1.0), Vector2(rad + 1.0, rad + 1.0) * 2.0)
			hull = tr if hull.size == Vector2.ZERO else hull.merge(tr)
		hull = hull.intersection(r.grow(-0.3))
		# The containment wall (a metre of concrete) round them.
		for e in 4:
			var line := _edge_line(hull, e)
			var a: Vector2 = line[0]
			var b: Vector2 = line[1]
			var m := (a + b) * 0.5
			var size := Vector3(a.distance_to(b) + 0.3, 1.0, 0.3) if e < 2 else Vector3(0.3, 1.0, a.distance_to(b) + 0.3)
			_wbox(ch, Transform3D(Basis(), Vector3(m.x, base + ch._gy(m.x, m.y) + 0.45, m.y)), size, IndustrialKit.K_CONCRETE, Color(0.72, 0.71, 0.68))
		return
	var left := r
	# A corrugated shed in one end.
	if minf(r.size.x, r.size.y) >= 7.0 and maxf(r.size.x, r.size.y) >= 12.0 and _h01([s, "shed"]) < SHED_ODDS and clear_of_freeway(ch.plan, r):
		var long_x := r.size.x >= r.size.y
		var sl := minf(maxf(r.size.x, r.size.y) * 0.4, 14.0)
		var sd := minf(minf(r.size.x, r.size.y) - 1.5, 9.0)
		var at_start := _h01([s, "shed_end"]) < 0.5
		var sr: Rect2
		if long_x:
			sr = Rect2(r.position.x + 0.8 if at_start else r.end.x - 0.8 - sl, r.position.y + (r.size.y - sd) * 0.5, sl, sd)
			left = Rect2(r.position.x + sl + 2.0 if at_start else r.position.x, r.position.y, r.size.x - sl - 2.0, r.size.y)
		else:
			sr = Rect2(r.position.x + (r.size.x - sd) * 0.5, r.position.y + 0.8 if at_start else r.end.y - 0.8 - sl, sd, sl)
			left = Rect2(r.position.x, r.position.y + sl + 2.0 if at_start else r.position.y, r.size.x, r.size.y - sl - 2.0)
		_shed(ch, sr, s, long_x)
	# Containers on gravel or asphalt yards, pallets in rows, drums.
	if minf(left.size.x, left.size.y) >= 4.0 and _h01([s, "cont"]) < 0.45 and clear_of_freeway(ch.plan, left) and _count(ch, "containers", MAX_CONTAINERS):
		var long_x := left.size.x >= left.size.y
		if maxf(left.size.x, left.size.y) >= 14.0:
			var cr := RandomNumberGenerator.new()
			cr.seed = s
			var livery: int = PortKit.COLOR_TO_LIVERY[absi(hash([s, "liv"])) % PortKit.COLOR_TO_LIVERY.size()]
			var look := PortKit.container_look(livery, cr)
			var cp := left.get_center()
			var yaw_flip := _h01([s, "cflip"]) < 0.5
			var xf := PortKit.container_xform(Vector3(cp.x, base + 1.3, cp.y), true, false, yaw_flip)
			# The box's length runs along x (PortKit.container_xform()).
			if not long_x:
				xf.basis = Basis(Vector3.UP, PI * 0.5) * xf.basis
			ch._batch.add("container", PropFactory.container(), xf, look[0], look[1])
			ch._add_shape(Vector3(12.2, 2.6, 2.45) if long_x else Vector3(2.45, 2.6, 12.2), Vector3(cp.x, base + ch._gy(cp.x, cp.y) + 1.3, cp.y))
			left = Rect2(left.position, Vector2(left.size.x, left.size.y * 0.5 - 1.6)) if long_x else Rect2(left.position, Vector2(left.size.x * 0.5 - 1.6, left.size.y))
	if minf(left.size.x, left.size.y) >= 2.0:
		_pallet_row(ch, left, s, 10)
	if _h01([s, "drums"]) < 0.5 and minf(left.size.x, left.size.y) >= 2.0 and _count(ch, "drums", 20):
		var p := left.end - Vector2(1.2, 1.2)
		_prop(ch, Vector3(p.x, base, p.y), _h01([s, "dy"]) * 0.4, _pick(DRUM_PAINTS, [s, "dp"]), IndustrialKit.drums)


## A row of pallet loads along a piece's long side.
static func _pallet_row(ch: CityChunk, r: Rect2, s: int, most: int) -> void:
	var long_x := r.size.x >= r.size.y
	var length := r.size.x if long_x else r.size.y
	var n := mini(floori((length - 1.0) / 1.5), most)
	var start := _h01([s, "pal_start"]) * maxf(length - float(n) * 1.5 - 1.0, 0.0)
	var base := CityChunk.SIDEWALK_TOP + LIFT
	for i in n:
		if _h01([s, "pal_gap", i]) < 0.18 or not _count(ch, "pallets", MAX_PALLETS):
			continue
		var t := start + 1.0 + float(i) * 1.5
		var p := Vector2(r.position.x + t, r.position.y + 0.8) if long_x else Vector2(r.position.x + 0.8, r.position.y + t)
		var k := absi(hash([s, "pal_k", i])) % 4
		var yaw := (0.0 if long_x else PI * 0.5) + (_h01([s, "pal_y", i]) - 0.5) * 0.15
		_prop(ch, Vector3(p.x, base, p.y), yaw, Color.WHITE, IndustrialKit.pallets.bind(k))


## A corrugated shed: four walls, a mono-pitch roof falling to the back, a roll-up door.
static func _shed(ch: CityChunk, r: Rect2, s: int, long_x: bool) -> void:
	var c := r.get_center()
	var g := minf(minf(ch._gy(r.position.x, r.position.y), ch._gy(r.end.x, r.end.y)), minf(ch._gy(r.position.x, r.end.y), ch._gy(r.end.x, r.position.y)))
	var base := CityChunk.SIDEWALK_TOP + LIFT + g
	var h_lo := lerpf(3.6, 4.6, _h01([s, "shed_h"]))
	var h_hi := h_lo + 1.0
	var paint: Color = [Color(0.72, 0.74, 0.74), Color(0.62, 0.42, 0.3), Color(0.55, 0.6, 0.55), Color(0.8, 0.78, 0.72), Color(0.42, 0.48, 0.55)][absi(hash([s, "shed_p"])) % 5]
	_wbox(ch, Transform3D(Basis(), Vector3(c.x, base + h_hi * 0.5, c.y)), Vector3(r.size.x, h_hi, r.size.y), IndustrialKit.K_CORRUGATED, paint, 0.0, 32 | 16)
	# The roof sheet, pitched along the short side.
	var run := r.size.y if long_x else r.size.x
	var ang := atan2(h_hi - h_lo, run)
	var roof_basis := Basis(Vector3.RIGHT, -ang) if long_x else Basis(Vector3.FORWARD, -ang)
	_wbox(ch, Transform3D(roof_basis, Vector3(c.x, base + h_hi - (h_hi - h_lo) * 0.5 + 0.08, c.y)), Vector3(r.size.x + 0.6, 0.08, r.size.y + 0.6) if long_x else Vector3(r.size.x + 0.6, 0.08, r.size.y + 0.6), IndustrialKit.K_CORRUGATED, Color(0.68, 0.68, 0.66), 0.0, 32)
	# A roll-up door on the long side facing the piece's middle.
	var door := Vector2(minf(3.6, (r.size.x if long_x else r.size.y) - 1.0), minf(3.4, h_lo - 0.4))
	var front := Vector3(c.x, base + door.y * 0.5, r.position.y - 0.02) if long_x else Vector3(r.position.x - 0.02, base + door.y * 0.5, c.y)
	var size := Vector3(door.x, door.y, 0.04) if long_x else Vector3(0.04, door.y, door.x)
	_wbox(ch, Transform3D(Basis(), front), size, IndustrialKit.K_ROLLUP, Color(0.66, 0.66, 0.64), 0.075)
	ch._add_shape(Vector3(r.size.x, h_hi, r.size.y), Vector3(c.x, base + h_hi * 0.5, c.y))


# --- Commit -------------------------------------------------------------------------------------

static var _ground_material: ShaderMaterial


static func ground_material() -> ShaderMaterial:
	if _ground_material != null:
		return _ground_material
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/industrial_ground.gdshader")
	mat.set_shader_parameter("asphalt_tex", PropFactory.texture("asphalt", "Color"))
	mat.set_shader_parameter("concrete_tex", PropFactory.texture("concrete", "Color"))
	mat.set_shader_parameter("dirt_tex", PropFactory.texture("hill_dirt", "Color"))
	mat.set_shader_parameter("gravel_tex", PropFactory.texture("sidewalk", "Color"))
	_ground_material = mat
	return mat


## The FULL chunk's industrial ground (one mesh, no shadow), its paint (in the same mesh, lifted)
## and its upright geometry (one mesh, casting). After the batches are added, before they build.
static func commit(ch: CityChunk) -> void:
	if ch._ind.is_empty():
		return
	# The pools are light, not things: they cast nothing.
	ch._batch.set_no_shadow("ind_pool")
	if not ch._ind.ground.is_empty() or not ch._ind.paint.is_empty():
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for gr: Array in ch._ind.ground:
			_ground_rect(st, ch, gr[0], CityChunk.SIDEWALK_TOP + LIFT, int(gr[1]), float(gr[2]), true, float(gr[3]) if gr.size() > 3 else 0.0)
		for pa: Array in ch._ind.paint:
			_ground_rect(st, ch, pa[0], CityChunk.SIDEWALK_TOP + PAINT_LIFT, G_PAINT, float(pa[1]), false)
		var mi := MeshInstance3D.new()
		mi.name = "IndustrialGround"
		mi.mesh = st.commit()
		mi.material_override = ground_material()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ch.add_child(mi)
	if ch._ind.walls != null:
		var st: SurfaceTool = ch._ind.walls
		var mi := MeshInstance3D.new()
		mi.name = "IndustrialWalls"
		mi.mesh = st.commit()
		mi.material_override = IndustrialKit.walls_material()
		ch.add_child(mi)
	ch._ind.walls = null
	ch._ind.ground.clear()
	ch._ind.paint.clear()


## A ground rect at `top` over the relief, one quad where the relief under it is a plane and a grid
## where it bends, with a skirt round it when `skirt`. UV is world metres (x, z).
static func _ground_rect(st: SurfaceTool, ch: CityChunk, r: Rect2, top: float, kind: int, variant: float, skirt: bool, blue: float = 0.0) -> void:
	if r.size.x < 0.05 or r.size.y < 0.05:
		return
	# Never one quad for a whole court: on the Compatibility renderer every lamp is an additive pass
	# that must land on the same depth, and a 60 m triangle clipped at the near plane does not - the
	# lamp-lit part of a court was striped at night. 8 m cells, 4 m where the relief bends.
	var step := 8.0 if LotFill._planar(ch, r) else 4.0
	var nx := clampi(ceili(r.size.x / step), 1, 32)
	var nz := clampi(ceili(r.size.y / step), 1, 32)
	var col := Color(float(kind) / 16.0 + 0.5 / 16.0, variant, blue, 1.0)
	var pts := PackedVector3Array()
	pts.resize((nx + 1) * (nz + 1))
	for j in nz + 1:
		for i in nx + 1:
			var x := r.position.x + r.size.x * i / nx
			var z := r.position.y + r.size.y * j / nz
			pts[j * (nx + 1) + i] = Vector3(x, top + ch._gy(x, z), z)
	for j in nz:
		for i in nx:
			var k00 := j * (nx + 1) + i
			var k10 := k00 + 1
			var k01 := k00 + nx + 1
			var k11 := k01 + 1
			for k: int in [k00, k10, k01, k10, k11, k01]:
				var p := pts[k]
				st.set_normal(Vector3.UP)
				st.set_color(col)
				st.set_uv(Vector2(p.x, p.z))
				st.add_vertex(p)
	if not skirt:
		return
	var down := Vector3(0.0, SKIRT, 0.0)
	var ring: Array[int] = []
	for i in nx + 1:
		ring.append(i)
	for j in range(1, nz + 1):
		ring.append(j * (nx + 1) + nx)
	for i in range(nx - 1, -1, -1):
		ring.append(nz * (nx + 1) + i)
	for j in range(nz - 1, 0, -1):
		ring.append(j * (nx + 1))
	var cc := Vector3(r.get_center().x, 0.0, r.get_center().y)
	for k in ring.size():
		var p0 := pts[ring[k]]
		var p1 := pts[ring[(k + 1) % ring.size()]]
		var mid := (p0 + p1) * 0.5
		var outv := Vector3(mid.x - cc.x, 0.0, mid.z - cc.z)
		var e := p1 - p0
		var n := Vector3(e.z, 0.0, -e.x).normalized()
		if n.dot(outv) < 0.0:
			n = -n
		var a0 := p0
		var a1 := p1
		if Vector3(e.z, 0.0, -e.x).dot(outv) > 0.0:
			a0 = p1
			a1 = p0
		for v: Vector3 in [a0, a1, a1 - down, a0, a1 - down, a0 - down]:
			st.set_normal(n)
			st.set_color(col)
			st.set_uv(Vector2(v.x + v.z, v.y))
			st.add_vertex(v)
