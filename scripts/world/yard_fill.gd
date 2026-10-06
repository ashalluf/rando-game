class_name YardFill
extends RefCounted
## The ground outside downtown and midtown (2026-10-04; LotFill is downtown's and midtown's). Three
## places were still the block's bare paving or plain lawn between the buildings:
##   - BEACH TOWN blocks (62 % bare, tools/lot_coverage.gd): every lot is a low stucco house now
##     with its yard out to its grid cell - a driveway to the kerb (often a car in it), a front walk,
##     a front garden (lawn, decomposed granite and gazania, a brick or saltillo patio) behind a low
##     stucco wall, a white picket fence or a clipped hedge, timber or stucco fences down the lot
##     lines from the house front back, and a back yard (lawn, a deck, a patio, now and then a
##     pool); an L-shaped building's inner corner is a courtyard apartment's tiled garden with a
##     fountain. Some blocks are cut through by a WALK STREET toward the beach: a path between the
##     rows of houses that front it with their gardens, lamps down it (beach_block()).
##   - CAMPUS blocks (93 % plain lawn: the campus hall's square drops most of their lots): walks
##     from every building's door to the street, quads with paths corner to corner and across,
##     trees along them, lamps and benches, a surface car park, service yards with dumpsters behind
##     block walls (campus_block()).
##   - The FREEWAY's right of way in every district (the lots CityChunk keeps out from under the
##     deck and their gaps): ivy over the cells, bare dirt in the deck's shade, oleander hedge rows
##     and a row of trees parallel to the deck, a sound wall where the right of way meets a house
##     lot (chain-link in the commercial districts and along the street), and now and then a
##     maintenance yard fenced in chain-link under the deck (corridor_block()).
## Every roll is a hash of the plan seed and the lot or block (never the chunk rng or Building's
## own), so nothing else in the city moves, and every plan is PURE - a function of the plan, the
## block and each lot's ground footprint - so tools/lot_coverage.gd and the smoke test ask exactly
## the question the chunk does. The ground is ONE mesh a chunk on shaders/lot_yard.gdshader (no
## shadow), everything upright ONE mesh on shaders/lot_walls.gdshader (casting); the planting goes
## in batches the chunk already has (one shrub species, the block's street tree, one palm, one
## flower a chunk), under per-chunk budgets. LOD chunks and the far city's capture get the lawns
## and the ivy as slabs (the merged far ground), nothing else.

## Off, every block builds as it did before this (the A/B: still_shot.gd YARD_FILL=0; FILL=0 on
## tools/lot_coverage.gd; the smoke test's "rolls nothing" check).
static var enabled: bool = true

## Districts whose lots get yards (the freeway's right of way is filled in every district). The
## suburbs since the house pass (HouseKit, 2026-10-04): the beach town's yard plan with suburban
## odds (SUBURB) and the block's own lawn as the lawn.
const DISTRICTS := [CityPlan.District.BEACHTOWN, CityPlan.District.CAMPUS, CityPlan.District.SUBURBS]

# --- Ground kinds: shaders/lot_yard.gdshader, COLOR.r in 16ths --------------------------------
const G_LAWN := 0
const G_CONCRETE := 1
const G_DG := 2
const G_BRICK := 3
const G_TILE := 4
const G_DECK := 5
const G_MULCH := 6
const G_IVY := 7
const G_POOL := 8
const G_GRAVEL := 9
## What each ground kind counts as for tools/lot_coverage.gd (the probe's kinds).
const G_NAMES := ["lawn", "concrete", "dg", "brick", "tile", "deck", "mulch", "ivy", "pool", "gravel"]

# --- Upright kinds: shaders/lot_walls.gdshader, COLOR.a in 16ths ------------------------------
const W_STUCCO := 0
const W_WOOD := 1
const W_PICKET := 2
const W_SOUND := 3
const W_HEDGE := 4
const W_CONCRETE := 5
const W_BRICK := 6
const W_CHAIN := 7
const W_METAL := 8
const W_POST := 9

## Top of the yard ground over the pavement slab, and of a campus walk over the block lawn (whose
## top is 4 cm up), metres. The skirt hangs below both.
const LIFT := 0.05
const PATH_LIFT := 0.066
const SKIRT := 0.08
## The colours the lawns and the ivy are recorded in for the far ground (a slab's tint).
const LAWN_FAR := Color(0.36, 0.50, 0.25)
const IVY_FAR := Color(0.21, 0.33, 0.14)

# --- Beach town ---------------------------------------------------------------------------------
## Odds a block gets a walk street (where one fits), the clear width it needs between the rows of
## houses, and its path's width (metres).
const WALK_ODDS := 0.6
const WALK_MIN := 3.4
const WALK_PATH := 2.8
## Lamps down a walk street, metres apart.
const WALK_LAMP_STEP := 17.0
## A driveway: odds a lot has one (with a front yard deep enough), its width, and odds a car is
## parked in it.
const DRIVE_ODDS := 0.72
const DRIVE_WIDTH := 3.0
const DRIVE_MIN_DEPTH := 2.6
const DRIVE_CAR_ODDS := 0.55
## The front garden's look, as cumulative odds: lawn, decomposed granite garden, brick or tile
## patio, the rest paved.
const FRONT_LAWN := 0.34
const FRONT_DG := 0.74
const FRONT_PATIO := 0.92
## The back yard's: lawn, deck, tile, concrete, the rest decomposed granite.
const BACK_LAWN := 0.42
const BACK_DECK := 0.6
const BACK_TILE := 0.75
const BACK_CONCRETE := 0.9
## Odds a back yard big enough (POOL_MIN) has a pool.
const POOL_ODDS := 0.28
const POOL_MIN := Vector2(6.0, 3.4)
## The street line's edging, cumulative: a low stucco wall, a picket fence, a clipped hedge, the
## rest open.
const EDGE_WALL := 0.42
const EDGE_PICKET := 0.66
const EDGE_HEDGE := 0.86
const LOW_WALL := Vector2(0.7, 1.05)
const PICKET_HEIGHT := 0.95
const HEDGE_HEIGHT := Vector2(0.9, 1.3)
## Lot-line fences: their height, and odds one is stucco (else timber).
const FENCE_HEIGHT := 1.8
const FENCE_STUCCO := 0.32
## Odds an L-shaped building's inner corner is a tiled courtyard with a fountain (else a lawn).
const COURT_TILE := 0.5
## The depth of the mulch bed along a house front (metres).
const BED_DEPTH := 0.95
## Stucco paints (the walls take one each), timbers, the pickets' white, the hedges' green.
const STUCCO_PAINTS := [Color(0.94, 0.91, 0.85), Color(0.97, 0.96, 0.93), Color(0.87, 0.79, 0.67),
	Color(0.82, 0.71, 0.60), Color(0.74, 0.81, 0.82), Color(0.90, 0.82, 0.73), Color(0.96, 0.89, 0.77),
	Color(0.80, 0.76, 0.70)]
const TIMBERS := [Color(0.82, 0.66, 0.52), Color(0.66, 0.57, 0.48), Color(0.74, 0.64, 0.56), Color(0.56, 0.50, 0.45)]
const PICKET_WHITE := Color(0.93, 0.93, 0.90)
const HEDGE_GREEN := Color(0.32, 0.43, 0.22)
## Wheelie bins: green waste, blue recycling, black trash (Los Angeles' three).
const BIN_COLORS := [Color(0.16, 0.36, 0.18), Color(0.12, 0.24, 0.52), Color(0.08, 0.08, 0.09)]

# --- Suburbs --------------------------------------------------------------------------------------
## The suburbs' yards are the beach town's plan with these odds in place of the beach constants: a
## front lawn (the block's own lawn shows through: lawn pieces are not laid there), a drought garden
## of decomposed granite now and then, a pool in half the back yards deep enough, and the street
## line mostly open (an LA suburb's front lawns run to the pavement); the side and back fences are
## block walls more often than timber. Keys as the beach constants they stand in for.
const SUBURB := {"front_lawn": 0.66, "front_dg": 0.84, "front_patio": 0.9, "back_lawn": 0.55, "back_deck": 0.66,
	"back_tile": 0.78, "back_concrete": 0.92, "pool": 0.5, "edge_wall": 0.1, "edge_picket": 0.18, "edge_hedge": 0.36,
	"fence_stucco": 0.58, "pool_apron": true}
const BEACH := {"front_lawn": FRONT_LAWN, "front_dg": FRONT_DG, "front_patio": FRONT_PATIO, "back_lawn": BACK_LAWN,
	"back_deck": BACK_DECK, "back_tile": BACK_TILE, "back_concrete": BACK_CONCRETE, "pool": POOL_ODDS,
	"edge_wall": EDGE_WALL, "edge_picket": EDGE_PICKET, "edge_hedge": EDGE_HEDGE, "fence_stucco": FENCE_STUCCO}

# --- Campus ---------------------------------------------------------------------------------------
## A piece of campus ground at least this big (metres) is a quad (paths, trees, lamps, benches);
## smaller ones are service yards or planted lawn.
const QUAD_MIN := Vector2(26.0, 22.0)
## Odds one quad-sized piece a block is a surface car park instead.
const CAMPUS_PARK_ODDS := 0.5
## The longest a campus car park runs (metres); the rest of its piece is a quad.
const CAMPUS_PARK_MAX := 80.0
const CAMPUS_WALK := 3.2
const ENTRY_WALK := 3.6
## Odds a campus building has a service yard behind it (with room for one).
const SERVICE_ODDS := 0.6

# --- Freeway --------------------------------------------------------------------------------------
## A sound wall's height (metres) where the right of way meets a house lot, and the chain-link's.
const SOUND_WALL := 4.2
const ROW_FENCE := 2.1
## Districts whose lots get a sound wall (the rest get chain-link).
const SOUND_DISTRICTS := [CityPlan.District.SUBURBS, CityPlan.District.BEACHTOWN, CityPlan.District.MIDTOWN, CityPlan.District.CAMPUS]
## The oleander hedge rows: metres beyond the deck's edge, and between shrubs. The tree row.
const HEDGE_OFFSET := 3.4
const HEDGE_STEP := 2.6
const ROW_TREE_OFFSET := 8.5
const ROW_TREE_STEP := 17.0
## Shrub clumps over the right of way away from the deck, one per this many square metres.
const ROW_CLUMP_AREA := 140.0
## Odds a block's right of way holds a maintenance yard.
const ROW_YARD_ODDS := 0.4
## How far either side of the deck's edge the bare-dirt fade runs (metres).
const BARE_FADE := Vector2(-2.5, 3.0)
## CityChunk's own corridor test (a lot the deck passes within this of, or whose centre is within
## CENTRE_MARGIN of the centre line, is right of way).
const LOT_MARGIN := 3.0
const CENTRE_MARGIN := 14.0

# --- Per-chunk budgets -----------------------------------------------------------------------------
## Shrubs a chunk's yards plant (and the triangles they may cost at full detail: a scanned bush is
## 3k-27k), trees (the frame's biggest single cost), palms, parked cars, and flowers' triangles.
const MAX_SHRUBS := 44
const SHRUB_TRIS := 200000
## The bushes (PropFactory.BUSHES) a yard may plant outside LotFill's districts: the cheap two.
const CHEAP_BUSHES := [1, 3]
const MAX_TREES := 9
const MAX_PALMS := 8
const MAX_CARS := 26
const FLOWER_TRIS := 160000
const FLOWER_DISTANCE := 120.0
## Microseconds of dressing a deferred build step does before it hands the frame back.
const DRESS_BUDGET_US := 2500


static func wanted(ch: CityChunk, district: int) -> bool:
	return enabled and ch.zone == MacroMap.Zone.CITY and district in DISTRICTS


## Whether the chunk records its lots for the yard plan (`ch._yard_lots`): where the fill would
## run, on or off. The plan is pure, and others ask it with the fill off too (Kerbs.possible_cuts():
## BoulevardSigns' posts keep off the driveways, so they stand the same whether the yards are laid).
static func records(ch: CityChunk, district: int) -> bool:
	return ch.zone == MacroMap.Zone.CITY and district in DISTRICTS


## True when a lot is the freeway's right of way (CityChunk._build_lot's own test).
static func is_corridor(plan: CityPlan, lot: Dictionary) -> bool:
	if plan.macro == null or plan.macro.freeway == null:
		return false
	var size: Vector2 = lot.size
	return plan.macro.freeway.blocks(lot.center, CENTRE_MARGIN) \
		or plan.macro.freeway.blocks_rect(Rect2((lot.center as Vector2) - size * 0.5, size), LOT_MARGIN)


static func _h01(parts: Array) -> float:
	return float(absi(hash(parts)) % 100003) / 100003.0


static func _rng(plan: CityPlan, tag: String, a: Variant) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([plan.seed, "yard_fill", tag, a])
	return rng


# --- Recording the lots (CityChunk._build_lot) ------------------------------------------------------

## A lot of a yard district has its building (FULL: built; LOD and capture: planned): its ground
## footprint is kept for the block step, which lays the yards once every lot is down.
static func record_lot(ch: CityChunk, lot: Dictionary, bld: Building) -> void:
	ch._yard_lots.append({"lot": lot, "parts": ground_parts(lot, bld)})


## A building's parts that stand on the ground, as world rects.
static func ground_parts(lot: Dictionary, bld: Building) -> Array[Rect2]:
	var out: Array[Rect2] = []
	var centre: Vector2 = lot.center
	for part: Dictionary in bld.parts:
		var size: Vector3 = part.size
		var c: Vector3 = part.center
		if c.y - size.y * 0.5 > 0.05:
			continue
		out.append(Rect2(centre.x + c.x - size.x * 0.5, centre.y + c.z - size.z * 0.5, size.x, size.z))
	return out


## The block step (after every lot of the block is down, before the approach parking and the lawn's
## grass): the yards, the campus ground and the freeway's right of way, for any tier.
static func block_step(ch: CityChunk, block: Dictionary) -> void:
	if not enabled or ch.zone != MacroMap.Zone.CITY:
		return
	var district: int = block.district
	if district == CityPlan.District.BEACHTOWN or district == CityPlan.District.SUBURBS:
		_build_beach(ch, beach_block(ch.plan, ch.ix, ch.iz, ch._yard_lots))
	elif district == CityPlan.District.CAMPUS:
		_build_campus(ch, campus_block(ch.plan, ch.ix, ch.iz, ch._yard_lots))
	if not ch._yard_corridor.is_empty():
		_build_corridor(ch, corridor_block(ch.plan, ch.ix, ch.iz, ch._yard_corridor))


# --- The lot grid ---------------------------------------------------------------------------------

## The block's lot grid as CityPlan lays it: its inner rect, the cell size, the count each way.
static func lot_grid(plan: CityPlan, bx: int, bz: int, lots: Array) -> Dictionary:
	var inner: Rect2 = (plan.block(bx, bz).rect as Rect2).grow(-plan.sidewalk_width)
	var cell := Vector2(inner.size.x, inner.size.y)
	for lot: Dictionary in lots:
		if lot.has("cell"):
			cell = (lot.cell as Rect2).size
			break
	var nx := maxi(1, roundi(inner.size.x / maxf(cell.x, 0.01)))
	var nz := maxi(1, roundi(inner.size.y / maxf(cell.y, 0.01)))
	return {"inner": inner, "cell": cell, "nx": nx, "nz": nz}


static func cell_index(grid: Dictionary, p: Vector2) -> Vector2i:
	var inner: Rect2 = grid.inner
	var cell: Vector2 = grid.cell
	return Vector2i(clampi(floori((p.x - inner.position.x) / cell.x), 0, int(grid.nx) - 1),
		clampi(floori((p.y - inner.position.y) / cell.y), 0, int(grid.nz) - 1))


static func cell_rect(grid: Dictionary, i: Vector2i) -> Rect2:
	var inner: Rect2 = grid.inner
	var cell: Vector2 = grid.cell
	return Rect2(inner.position + Vector2(cell.x * i.x, cell.y * i.y), cell)


## Which side of the block's inner rect a rect is nearest: 0 -Z, 1 +Z, 2 -X, 3 +X.
static func nearest_side(inner: Rect2, r: Rect2) -> int:
	var d := [r.position.y - inner.position.y, inner.end.y - r.end.y, r.position.x - inner.position.x, inner.end.x - r.end.x]
	var best := 0
	for i in 4:
		if float(d[i]) < float(d[best]) - 0.01:
			best = i
	return best


## What the landmarks near `rect` stand on, as far as is known: the campus hall's own footprint, a
## downtown tower's, a pier's deck and its landing (they run out to sea from the anchor), and any
## other landmark's whole square (its shape is not known here). The boardwalk is tested point by
## point instead (usable()).
static func landmark_holes(plan: CityPlan, rect: Rect2) -> Array[Rect2]:
	var out: Array[Rect2] = []
	if plan.macro == null:
		return out
	for lm in Landmarks.all():
		if lm.get("area") is Dictionary or lm.id == "venice_boardwalk":
			continue
		var r: float = lm.radius
		var a: Vector2 = lm.anchor
		var sq := Rect2(a - Vector2(r, r), Vector2(r * 2.0, r * 2.0))
		if not sq.intersects(rect):
			continue
		var fp := Landmarks.campus_footprint(lm)
		if fp.size.x > 0.0:
			out.append(fp.grow(2.0))
		elif LandmarkDowntown.is_tower(str(lm.id)):
			out.append(LandmarkDowntown.footprint(lm).grow(4.0))
		elif lm.id == "pier" or lm.id == "manhattan_pier":
			out.append(Rect2(a.x - 420.0, a.y - 40.0, 460.0, 80.0))
		elif lm.id == "south_bay_mall":
			# The site it grades and paves (LandmarkSouthBayMall SITE_*).
			out.append(Rect2(a.x - LandmarkSouthBayMall.SITE_HALF_X - 4.0, a.y - LandmarkSouthBayMall.SITE_BACK - 4.0,
				LandmarkSouthBayMall.SITE_HALF_X * 2.0 + 8.0, LandmarkSouthBayMall.SITE_BACK + LandmarkSouthBayMall.SITE_FRONT + 8.0))
		elif lm.id == "redondo_pier":
			# Its two-level car park stands on the land behind the anchor (LandmarkBeachPiers RD_*).
			out.append(Rect2(a.x - 420.0, a.y - 70.0, 530.0, 140.0))
		else:
			out.append(sq)
	return out


## True when all of `r` is city ground clear of the boardwalk's buildings (sampled every 4 m).
static func usable(plan: CityPlan, r: Rect2) -> bool:
	return _usable_part(plan, r) == r


static func _usable_at(plan: CityPlan, p: Vector2) -> bool:
	return plan.zone_at(p) == MacroMap.Zone.CITY and not (plan.macro and Landmarks.covers(plan, p, 6.0))


## The biggest part of `r` that is all city ground clear of the boardwalk's buildings, on a 4 m
## sample grid: the longest run of clear columns, then of clear rows within it (the sand and the
## boardwalk's shops lie along one side of a block, so that is a trim, not a hole). Rect2() if none.
static func _usable_part(plan: CityPlan, r: Rect2) -> Rect2:
	var nx := maxi(1, ceili(r.size.x / 4.0))
	var nz := maxi(1, ceili(r.size.y / 4.0))
	var ok := PackedByteArray()
	ok.resize((nx + 1) * (nz + 1))
	var all_ok := true
	for j in nz + 1:
		for i in nx + 1:
			var good := _usable_at(plan, r.position + Vector2(r.size.x * i / nx, r.size.y * j / nz))
			ok[j * (nx + 1) + i] = 1 if good else 0
			all_ok = all_ok and good
	if all_ok:
		return r
	var cols := _longest_run(nx + 1, func(i: int) -> bool:
		for j in nz + 1:
			if ok[j * (nx + 1) + i] == 0:
				return false
		return true)
	if cols.y - cols.x < 2:
		return Rect2()
	var rows := _longest_run(nz + 1, func(j: int) -> bool:
		for i in range(cols.x, cols.y):
			if ok[j * (nx + 1) + i] == 0:
				return false
		return true)
	if rows.y - rows.x < 2:
		return Rect2()
	var x0 := r.position.x + r.size.x * cols.x / nx
	var x1 := r.position.x + r.size.x * (cols.y - 1) / nx
	var z0 := r.position.y + r.size.y * rows.x / nz
	var z1 := r.position.y + r.size.y * (rows.y - 1) / nz
	return Rect2(x0, z0, x1 - x0, z1 - z0)


## The longest run [from, to) of indices 0..n-1 for which `good` holds.
static func _longest_run(n: int, good: Callable) -> Vector2i:
	var best := Vector2i(0, 0)
	var start := -1
	for i in n + 1:
		var g: bool = i < n and good.call(i)
		if g and start < 0:
			start = i
		elif not g and start >= 0:
			if i - start > best.y - best.x:
				best = Vector2i(start, i)
			start = -1
	return best


## The cells a landmark's square dropped from a beach-town block, less what the landmarks stand on:
## [[Rect2, role]] - a beach car park where one fits (the lots behind the sand), else a pocket park.
static func beach_dropped(plan: CityPlan, bx: int, bz: int) -> Array:
	var out: Array = []
	if plan.dropped_cells(bx, bz).is_empty():
		return out
	# The free ground as a few big rects: the inner rect less every lot's cell and the landmarks.
	var block: Dictionary = plan.block(bx, bz)
	var inner: Rect2 = (block.rect as Rect2).grow(-plan.sidewalk_width)
	var holes := landmark_holes(plan, block.rect)
	for lot: Dictionary in plan.lots(bx, bz):
		holes.append(lot.get("cell", Rect2((lot.center as Vector2) - (lot.size as Vector2) * 0.5, lot.size)))
	var k := 0
	for whole: Rect2 in LotFill._minus(inner, holes, 0.0):
		k += 1
		var piece := _usable_part(plan, whole)
		if minf(piece.size.x, piece.size.y) < 4.0:
			continue
		var park := piece.size.x >= 20.0 and piece.size.y >= 16.0 and _h01([plan.seed, bx, bz, k, "beach_park"]) < 0.6
		out.append([piece, "parking" if park else "park"])
	return out


# --- Lot frames ---------------------------------------------------------------------------------------
# A lot's yard is planned in its street frame: u along the street, v back from the front edge
# (0) to the back of the cell (V). The frame is axis-aligned, so every rect maps to a rect.

static func _frame(cell: Rect2, side: int) -> Dictionary:
	match side:
		0:
			return {"o": cell.position, "u": Vector2(1, 0), "v": Vector2(0, 1), "U": cell.size.x, "V": cell.size.y, "side": side}
		1:
			return {"o": Vector2(cell.position.x, cell.end.y), "u": Vector2(1, 0), "v": Vector2(0, -1), "U": cell.size.x, "V": cell.size.y, "side": side}
		2:
			return {"o": cell.position, "u": Vector2(0, 1), "v": Vector2(1, 0), "U": cell.size.y, "V": cell.size.x, "side": side}
		_:
			return {"o": Vector2(cell.end.x, cell.position.y), "u": Vector2(0, 1), "v": Vector2(-1, 0), "U": cell.size.y, "V": cell.size.x, "side": side}


## Frame rect [u0, u1] x [v0, v1] as a world rect.
static func _fr(f: Dictionary, u0: float, v0: float, u1: float, v1: float) -> Rect2:
	var o: Vector2 = f.o
	var a: Vector2 = o + (f.u as Vector2) * u0 + (f.v as Vector2) * v0
	var b: Vector2 = o + (f.u as Vector2) * u1 + (f.v as Vector2) * v1
	return Rect2(Vector2(minf(a.x, b.x), minf(a.y, b.y)), Vector2(absf(b.x - a.x), absf(b.y - a.y)))


## A world rect in frame coordinates, as Rect2(u0, v0, du, dv).
static func _to_frame(f: Dictionary, r: Rect2) -> Rect2:
	var o: Vector2 = f.o
	var a := r.position - o
	var b := r.end - o
	var ua := a.dot(f.u)
	var ub := b.dot(f.u)
	var va := a.dot(f.v)
	var vb := b.dot(f.v)
	return Rect2(minf(ua, ub), minf(va, vb), absf(ub - ua), absf(vb - va))


static func _fp(f: Dictionary, u: float, v: float) -> Vector2:
	return (f.o as Vector2) + (f.u as Vector2) * u + (f.v as Vector2) * v


# --- Beach town: the plan -------------------------------------------------------------------------------

## A beach-town block's yards, from the plan and each built lot's ground footprint (`entries`:
## [{"lot", "parts"}]). Returns {"walk": Rect2 (zero size: none), "walk_path": Rect2, "lots": [lot
## plans]}: a lot plan is {"lot", "cell" (the yard's rect: the cell less the walk), "frame",
## "parts", "front" (v of the house front), "back" (v of its back), "pieces": [[Rect2, G_*,
## variant, role]], "drive": Rect2, "walk_front": bool}. Roles: front, drive, path, side, back,
## court, pool.
static func beach_block(plan: CityPlan, bx: int, bz: int, entries: Array) -> Dictionary:
	var lots: Array = []
	for e: Dictionary in entries:
		lots.append(e.lot)
	var grid := lot_grid(plan, bx, bz, lots)
	var wk := walk_for(plan, bx, bz)
	var walk: Rect2 = wk[0]
	var walk_path: Rect2 = wk[1]
	var suburb := int(plan.block(bx, bz).district) == CityPlan.District.SUBURBS
	var out: Array = []
	for e: Dictionary in entries:
		out.append(_beach_lot(plan, grid, e, walk, walk_path, SUBURB if suburb else BEACH))
	return {"walk": walk, "walk_path": walk_path, "lots": out, "grid": grid, "dropped": beach_dropped(plan, bx, bz), "suburb": suburb}


## A beach block's walk street, [walk, walk_path] (zero rects: none), PURE - from the plan's lots
## alone, so the houses (HouseKit, built lot by lot before the block step) can face it: the row
## boundary along x with the widest gap every column leaves between its two rows' lot rects, when
## it is wide enough and the block rolls one. A cell must hold a house lot either side (not a pocket
## garden, a car park, the freeway's right of way, or a lot big enough to be rolled a commercial
## pad - that roll is the chunk's, so such a column has no walk). (It used to measure the gap
## between the buildings' own parts; the houses are planned inside their cells now, so the lot
## rects are the gap that is known before them.)
static var _walks := {}


static func walk_for(plan: CityPlan, bx: int, bz: int) -> Array:
	var key := hash([plan.seed, bx, bz])
	if _walks.has(key):
		return _walks[key]
	var walk := Rect2()
	var walk_path := Rect2()
	var b: Dictionary = plan.block(bx, bz)
	if int(b.district) == CityPlan.District.BEACHTOWN and _h01([plan.seed, bx, bz, "walk"]) < WALK_ODDS:
		var lots := plan.lots(bx, bz)
		var grid := lot_grid(plan, bx, bz, lots)
		var inner: Rect2 = grid.inner
		var pads: float = float((CityPlan.DISTRICTS[b.district] as Dictionary).get("pads", 0.0))
		var by_cell := {}
		for lot: Dictionary in lots:
			var size: Vector2 = lot.size
			if lot.yard or lot.get("parking", false) or is_corridor(plan, lot):
				continue
			if lot.edge and pads > 0.0 and size.x >= 18.0 and size.y >= 18.0:
				continue
			by_cell[cell_index(grid, lot.center)] = Rect2((lot.center as Vector2) - size * 0.5, size)
		if int(grid.nz) >= 3 and int(grid.nx) >= 1:
			var best := -1.0
			var best_lo := 0.0
			var best_hi := 0.0
			for j in range(1, int(grid.nz)):
				var line: float = inner.position.y + (grid.cell as Vector2).y * j
				var lo := line - (grid.cell as Vector2).y * 0.5
				var hi := line + (grid.cell as Vector2).y * 0.5
				var ok := true
				for i in int(grid.nx):
					var below: Variant = by_cell.get(Vector2i(i, j - 1))
					var above: Variant = by_cell.get(Vector2i(i, j))
					if below == null or above == null:
						ok = false
						break
					lo = maxf(lo, (below as Rect2).end.y)
					hi = minf(hi, (above as Rect2).position.y)
				if ok and hi - lo > best:
					best = hi - lo
					best_lo = lo
					best_hi = hi
			if best >= WALK_MIN:
				walk = Rect2(inner.position.x, best_lo + 0.3, inner.size.x, best - 0.6)
				var pw := minf(WALK_PATH, walk.size.y * 0.55)
				walk_path = Rect2(inner.position.x, walk.get_center().y - pw * 0.5, inner.size.x, pw)
	if _walks.size() > 4096:
		_walks.clear()
	_walks[key] = [walk, walk_path]
	return _walks[key]


## Which way a lot of a yard block faces, PURE: {"side" (the cell edge its street frame's v = 0 is
## on: 0 -Z, 1 +Z, 2 -X, 3 +X), "yard" (its cell, less the walk street when it fronts one),
## "walk_front"}. The nearest block edge, or the walk street when the cell runs along one.
static func lot_front(plan: CityPlan, bx: int, bz: int, lot: Dictionary, grid: Dictionary) -> Dictionary:
	var inner: Rect2 = grid.inner
	var cell: Rect2 = lot.get("cell", Rect2((lot.center as Vector2) - (lot.size as Vector2) * 0.5, lot.size))
	var side := nearest_side(inner, cell)
	var yard := cell
	var walk_front := false
	var wk := walk_for(plan, bx, bz)
	var walk: Rect2 = wk[0]
	var walk_path: Rect2 = wk[1]
	if walk.size.x > 0.0 and walk.intersects(cell):
		walk_front = true
		if cell.get_center().y < walk_path.get_center().y:
			yard = Rect2(cell.position, Vector2(cell.size.x, walk_path.position.y - cell.position.y))
			side = 1
		else:
			yard = Rect2(Vector2(cell.position.x, walk_path.end.y), Vector2(cell.size.x, cell.end.y - walk_path.end.y))
			side = 0
	return {"side": side, "yard": yard, "walk_front": walk_front, "cell": cell}


static func _beach_lot(plan: CityPlan, grid: Dictionary, e: Dictionary, walk: Rect2, walk_path: Rect2, odds: Dictionary = BEACH) -> Dictionary:
	var lot: Dictionary = e.lot
	var inner: Rect2 = grid.inner
	var cell: Rect2 = lot.get("cell", Rect2((lot.center as Vector2) - (lot.size as Vector2) * 0.5, lot.size))
	var parts: Array[Rect2] = []
	parts.assign(e.parts)
	# A house (HouseKit) says which way it faces, where its garage door and its front door are; the
	# yard follows it. A building of the old kind faces the nearest street (or the walk street).
	var house: Dictionary = e.get("house", {})
	var side := nearest_side(inner, cell)
	var walk_front := false
	var yard := cell
	if not house.is_empty():
		side = int(house.side)
		yard = house.yard
		walk_front = bool(house.walk_front)
	elif walk.size.x > 0.0 and walk.intersects(cell):
		walk_front = true
		if cell.get_center().y < walk_path.get_center().y:
			yard = Rect2(cell.position, Vector2(cell.size.x, walk_path.position.y - cell.position.y))
			side = 1
		else:
			yard = Rect2(Vector2(cell.position.x, walk_path.end.y), Vector2(cell.size.x, cell.end.y - walk_path.end.y))
			side = 0
	var f := _frame(yard, side)
	var U: float = f.U
	var V: float = f.V
	# The house's extent in the frame.
	var bu0 := U
	var bu1 := 0.0
	var bv0 := V
	var bv1 := 0.0
	for r: Rect2 in parts:
		var q := _to_frame(f, r)
		bu0 = minf(bu0, q.position.x)
		bu1 = maxf(bu1, q.end.x)
		bv0 = minf(bv0, q.position.y)
		bv1 = maxf(bv1, q.end.y)
	if bu1 <= bu0:
		bu0 = U * 0.3
		bu1 = U * 0.7
		bv0 = V * 0.3
		bv1 = V * 0.7
	bv0 = clampf(bv0, 0.0, V)
	bv1 = clampf(bv1, bv0, V)
	var key: int = lot.seed
	var pieces: Array = []
	var holes: Array[Rect2] = parts.duplicate()
	# The driveway: on one side of the frontage, from the front edge to the house - or, for a house,
	# from the front edge to its garage door (or carport, or down the side of it).
	var drive := Rect2()
	var fd := bv0
	if not house.is_empty():
		var dr: Vector2 = house.drive
		if dr.y > dr.x and not walk_front and float(house.drive_v) > 0.5:
			drive = _fr(f, maxf(dr.x, 0.0), 0.0, minf(dr.y, U), minf(float(house.drive_v), V))
	elif not walk_front and fd >= DRIVE_MIN_DEPTH and _h01([plan.seed, key, "drive"]) < DRIVE_ODDS:
		var left := _h01([plan.seed, key, "drive_side"]) < 0.5
		var du0 := 0.35 if left else U - 0.35 - DRIVE_WIDTH
		if du0 >= 0.0 and du0 + DRIVE_WIDTH <= U:
			drive = _fr(f, du0, 0.0, du0 + DRIVE_WIDTH, fd)
	if drive.size.x > 0.0:
		pieces.append([drive, G_CONCRETE, _h01([plan.seed, key, "age"]) * 0.6, "drive"])
	# The front walk: from the front edge to the middle of the house front (clear of the drive), or
	# to a house's front door (its porch or stoop).
	var front_style := _h01([plan.seed, key, "front"])
	var path_kind := G_CONCRETE if front_style < float(odds.front_dg) else (G_BRICK if front_style < float(odds.front_patio) else G_CONCRETE)
	var walk_r := Rect2()
	var walk_v := fd
	if not house.is_empty():
		walk_v = minf(float(house.door_v), V)
	if walk_v >= 1.2:
		var cu := clampf((bu0 + bu1) * 0.5, 1.0, U - 1.0)
		if not house.is_empty():
			cu = clampf(float(house.door_u), 0.8, U - 0.8)
		if drive.size.x > 0.0:
			var dq := _to_frame(f, drive)
			if cu > dq.position.x - 1.0 and cu < dq.end.x + 1.0:
				cu = dq.end.x + 1.4 if dq.position.x < U * 0.5 else dq.position.x - 1.4
		cu = clampf(cu, 0.8, U - 0.8)
		walk_r = _fr(f, cu - 0.6, 0.0, cu + 0.6, walk_v)
		for r: Rect2 in LotFill._minus(walk_r, holes, 0.0):
			pieces.append([r, path_kind, 0.3, "path"])
	if not house.is_empty():
		# The drive and the walk can reach past the house's front line (a garage or a door set
		# back): nothing else is laid over them.
		if drive.size.x > 0.0:
			holes.append(drive)
		if walk_r.size.x > 0.0:
			holes.append(walk_r)
	# The front garden: the rest of the front zone.
	var front_kind: int
	if front_style < float(odds.front_lawn):
		front_kind = G_LAWN
	elif front_style < float(odds.front_dg):
		front_kind = G_DG
	elif front_style < float(odds.front_patio):
		front_kind = G_BRICK if _h01([plan.seed, key, "patio"]) < 0.5 else G_TILE
	else:
		front_kind = G_CONCRETE
	var fzone := _fr(f, 0.0, 0.0, U, fd)
	var cut: Array[Rect2] = holes.duplicate()
	if drive.size.x > 0.0:
		cut.append(drive)
	if walk_r.size.x > 0.0:
		cut.append(walk_r)
	# A planting bed of mulch along the house front, a lawn's or a patio's edge.
	if fd >= 2.6 and (front_kind == G_LAWN or front_kind == G_BRICK or front_kind == G_TILE):
		var bed := _fr(f, maxf(bu0, 0.2), fd - BED_DEPTH, minf(bu1, U - 0.2), fd)
		for r: Rect2 in LotFill._minus(bed, cut, 0.0):
			pieces.append([r, G_MULCH, 0.5, "bed"])
		cut.append(bed)
	for r: Rect2 in LotFill._minus(fzone, cut, 0.0):
		pieces.append([r, front_kind, _h01([plan.seed, key, "thirst"]), "front"])
	# The back yard (behind the house) and the side yards (beside it).
	var back_style := _h01([plan.seed, key, "back"])
	var back_kind: int
	if back_style < float(odds.back_lawn):
		back_kind = G_LAWN
	elif back_style < float(odds.back_deck):
		back_kind = G_DECK
	elif back_style < float(odds.back_tile):
		back_kind = G_TILE
	elif back_style < float(odds.back_concrete):
		back_kind = G_CONCRETE
	else:
		back_kind = G_DG
	var bzone := _fr(f, 0.0, bv1, U, V)
	var pool := Rect2()
	var bq := _to_frame(f, bzone)
	if bq.size.y >= POOL_MIN.y + 1.6 and U >= POOL_MIN.x + 2.0 and _h01([plan.seed, key, "pool"]) < float(odds.pool):
		var pu := (U - POOL_MIN.x) * (0.25 + 0.5 * _h01([plan.seed, key, "pool_u"]))
		var pv := bv1 + 1.0 + (bq.size.y - POOL_MIN.y - 1.6) * 0.5
		pool = _fr(f, pu, pv, pu + POOL_MIN.x, pv + POOL_MIN.y)
		if not odds.get("pool_apron", false):
			back_kind = G_CONCRETE if back_kind == G_LAWN or back_kind == G_DG else back_kind
	var back_cut: Array[Rect2] = holes.duplicate()
	if pool.size.x > 0.0:
		back_cut.append(pool)
		pieces.append([pool, G_POOL, 0.0, "pool"])
		# A suburban pool sits in the lawn on a concrete deck of its own.
		if odds.get("pool_apron", false) and back_kind == G_LAWN:
			var apron := pool.grow(1.2).intersection(bzone)
			for r: Rect2 in LotFill._minus(apron, back_cut, 0.0):
				pieces.append([r, G_CONCRETE, 0.15, "apron"])
			back_cut.append(apron)
	for r: Rect2 in LotFill._minus(bzone, back_cut, 0.0):
		pieces.append([r, back_kind, _h01([plan.seed, key, "thirst"]) * 0.8, "back"])
	for sz: Rect2 in [_fr(f, 0.0, bv0, bu0, bv1), _fr(f, bu1, bv0, U, bv1)]:
		for r: Rect2 in LotFill._minus(sz, holes, 0.0):
			var narrow := minf(r.size.x, r.size.y) < 2.4
			pieces.append([r, G_CONCRETE if narrow else back_kind, 0.4, "side"])
	# Inside the house's extent but not under it: an L's inner corner, a courtyard.
	var bbox := _fr(f, bu0, bv0, bu1, bv1)
	var court_kind := G_TILE if _h01([plan.seed, key, "court"]) < COURT_TILE else G_LAWN
	for r: Rect2 in LotFill._minus(bbox, holes, 0.0):
		pieces.append([r, court_kind, 0.2, "court"])
	return {"lot": lot, "cell": yard, "full_cell": cell, "frame": f, "parts": parts, "front": bv0, "back": bv1,
		"house_u": Vector2(bu0, bu1), "pieces": pieces, "drive": drive, "walk_front": walk_front, "odds": odds}


# --- Beach town: the build ------------------------------------------------------------------------------

static func _build_beach(ch: CityChunk, bp: Dictionary) -> void:
	var full := ch.level == CityChunk.Level.FULL and not ch.capturing
	var walk: Rect2 = bp.walk
	var walk_path: Rect2 = bp.walk_path
	if walk.size.x > 0.0:
		var vk := G_BRICK if _h01([ch.plan.seed, ch.ix, ch.iz, "walk_kind"]) < 0.4 else G_CONCRETE
		# The path; the gardens of the houses along it run up to its edges.
		_ground(ch, walk_path, vk, 0.5)
	# In the suburbs the block's lawn (and its blades) is the lawn: the yard lays the rest a little
	# higher (clear of the lawn slab's top) and keeps the blades off it.
	var suburb: bool = bp.get("suburb", false)
	for lp: Dictionary in bp.lots:
		for pc: Array in lp.pieces:
			if suburb:
				if pc[1] == G_LAWN:
					continue
				_ground(ch, pc[0], pc[1], pc[2], PATH_LIFT)
				ch._lot_rects.append(pc[0])
			else:
				_ground(ch, pc[0], pc[1], pc[2])
	# What a landmark's square left: the beach car parks behind the sand, pocket parks.
	var k := 0
	for d: Array in bp.dropped:
		k += 1
		var r: Rect2 = d[0]
		if d[1] == "parking":
			LotFill._car_park(ch, r, hash([ch.ix, ch.iz, k, "beach_park"]))
		else:
			_pocket_park(ch, r, _rng(ch.plan, "pocket", [ch.ix, ch.iz, k]), full)
	if not full:
		Backyards.block(ch, bp)
		return
	var grid: Dictionary = bp.grid
	var corridor_cells := {}
	for lot: Dictionary in ch._yard_corridor:
		corridor_cells[cell_index(grid, lot.center)] = true
	var jobs: Array[Callable] = []
	for lp: Dictionary in bp.lots:
		jobs.append(_dress_beach_lot.bind(ch, lp, grid, corridor_cells))
	if walk.size.x > 0.0:
		jobs.append(_dress_walk.bind(ch, walk, walk_path))
	_defer(ch, jobs)
	Backyards.block(ch, bp)


## The dressing (walls, planting, props) as build steps of their own, queued before the finish
## (CityChunk._run_or_defer()) and run a few milliseconds at a time: a beach block's twenty-odd
## yards in one step were the slowest step of its build. The ground is laid in the block step
## itself, before the lawn's grass, which keeps off it. Last in the build, so the block's own props
## keep the ids they had.
static func _defer1(ch: CityChunk, job: Callable) -> void:
	var jobs: Array[Callable] = [job]
	_defer(ch, jobs)


static func _defer(ch: CityChunk, jobs: Array[Callable]) -> void:
	if jobs.is_empty():
		return
	var next := [0]
	ch._run_or_defer(func() -> bool:
		var t0 := Time.get_ticks_usec()
		while next[0] < jobs.size():
			jobs[next[0]].call()
			next[0] += 1
			if Time.get_ticks_usec() - t0 > DRESS_BUDGET_US:
				break
		return next[0] >= jobs.size())


## A beach-town pocket park: lawn, a walk across it, palms down it, benches, a hedge round it.
static func _pocket_park(ch: CityChunk, r: Rect2, rng: RandomNumberGenerator, full: bool) -> void:
	var long_x := r.size.x >= r.size.y
	var c := r.get_center()
	var w := 2.4
	var walk := Rect2(r.position.x, c.y - w * 0.5, r.size.x, w) if long_x else Rect2(c.x - w * 0.5, r.position.y, w, r.size.y)
	_ground(ch, walk, G_CONCRETE, 0.3)
	for lawn: Rect2 in _less(r, walk):
		_ground(ch, lawn, G_LAWN, 0.25)
	if not full:
		return
	var len := maxf(r.size.x, r.size.y)
	var n := clampi(int(len / 9.0), 1, 6)
	var base := CityChunk.SIDEWALK_TOP + LIFT
	for i in n:
		var t := (float(i) + 0.5) / float(n)
		for s: float in [-1.0, 1.0]:
			var p := Vector2(lerpf(r.position.x, r.end.x, t), c.y + s * (w * 0.5 + 1.6)) if long_x else Vector2(c.x + s * (w * 0.5 + 1.6), lerpf(r.position.y, r.end.y, t))
			if (i + int(s > 0.0)) % 2 == 0:
				_palm(ch, p, rng)
			elif rng.randf() < 0.5:
				_shrub(ch, p, rng, 1.0)
		if i % 2 == 1:
			var bp := Vector2(lerpf(r.position.x, r.end.x, t), c.y - w * 0.5 - 0.6) if long_x else Vector2(c.x - w * 0.5 - 0.6, lerpf(r.position.y, r.end.y, t))
			ch._add_bench(Vector3(bp.x, base, bp.y), PI if long_x else -PI * 0.5)
	# A low clipped hedge round the lawn, open at the walk's two ends.
	for e in 4:
		var line := _edge_line(r.grow(-0.5), e)
		var a: Vector2 = line[0]
		var b: Vector2 = line[1]
		var along := absf(b.x - a.x) > absf(b.y - a.y)
		if along == long_x:
			_hedge_run(ch, a, b)
		else:
			var m := (a + b) * 0.5
			var d := (b - a).normalized()
			_hedge_run(ch, a, m - d * (w * 0.5 + 0.6))
			_hedge_run(ch, m + d * (w * 0.5 + 0.6), b)


static func _hedge_run(ch: CityChunk, a: Vector2, b: Vector2) -> void:
	var len := a.distance_to(b)
	if len < 0.6:
		return
	var along_x := absf(b.x - a.x) > absf(b.y - a.y)
	var n := maxi(1, ceili(len / 6.0))
	for i in n:
		var p0 := a.lerp(b, float(i) / float(n))
		var p1 := a.lerp(b, float(i + 1) / float(n))
		var c := (p0 + p1) * 0.5
		var seg := p0.distance_to(p1)
		_box_wall(ch, Vector3(seg, 0.95, 0.8) if along_x else Vector3(0.8, 0.95, seg), Vector3(c.x, CityChunk.SIDEWALK_TOP + LIFT, c.y), W_HEDGE, HEDGE_GREEN)


## A walk street's lamps, staggered down it at the path's edges.
static func _dress_walk(ch: CityChunk, _walk: Rect2, path: Rect2) -> void:
	var n := maxi(1, int(path.size.x / WALK_LAMP_STEP))
	for i in n:
		var x := path.position.x + path.size.x * (float(i) + 0.5) / float(n)
		var z := path.position.y + 0.35 if i % 2 == 0 else path.end.y - 0.35
		LotFill._lamp(ch, Vector3(x, CityChunk.SIDEWALK_TOP + LIFT, z))


static func _dress_beach_lot(ch: CityChunk, lp: Dictionary, grid: Dictionary, corridor_cells: Dictionary) -> void:
	var plan := ch.plan
	var lot: Dictionary = lp.lot
	var key: int = lot.seed
	var rng := _rng(plan, "lot", key)
	var f: Dictionary = lp.frame
	var U: float = f.U
	var V: float = f.V
	var fd: float = lp.front
	var bv1: float = lp.back
	var hu: Vector2 = lp.house_u
	var drive: Rect2 = lp.drive
	var inner: Rect2 = grid.inner
	var base := CityChunk.SIDEWALK_TOP + LIFT
	var paint: Color = STUCCO_PAINTS[absi(hash([plan.seed, key, "stucco"])) % STUCCO_PAINTS.size()]
	var timber: Color = TIMBERS[absi(hash([plan.seed, key, "timber"])) % TIMBERS.size()]
	# The street line (or the walk street's edge): a low wall, pickets or a hedge, open at the drive
	# and the front walk; a walk-street garden always has a low wall or pickets, with a gate.
	var odds: Dictionary = lp.get("odds", BEACH)
	var roll := _h01([plan.seed, key, "edge"])
	if lp.walk_front:
		roll = roll * float(odds.edge_picket)
	var openings: Array[Vector2] = []
	if drive.size.x > 0.0:
		var dq := _to_frame(f, drive)
		openings.append(Vector2(dq.position.x - 0.1, dq.end.x + 0.1))
	for pc: Array in lp.pieces:
		if pc[3] == "path":
			var pq := _to_frame(f, pc[0])
			openings.append(Vector2(pq.position.x - 0.05, pq.end.x + 0.05))
	if fd >= 1.0 and roll < float(odds.edge_hedge):
		for span: Vector2 in _spans(0.25, U - 0.25, openings):
			if roll < float(odds.edge_wall):
				# Lower along a walk street, where the gardens are the street.
				var h := lerpf(LOW_WALL.x, LOW_WALL.y, _h01([plan.seed, key, "wall_h"])) * (0.75 if lp.walk_front else 1.0)
				_wall_run(ch, f, Vector2(span.x, 0.15), Vector2(span.y, 0.15), h, 0.24, W_STUCCO, paint)
				# A cap course a hair wider, in the trim colour.
				_wall_run(ch, f, Vector2(span.x, 0.15), Vector2(span.y, 0.15), 0.07, 0.3, W_STUCCO, paint.lightened(0.25), h)
			elif roll < float(odds.edge_picket):
				_wall_run(ch, f, Vector2(span.x, 0.2), Vector2(span.y, 0.2), PICKET_HEIGHT, 0.04, W_PICKET, PICKET_WHITE)
				_posts(ch, f, span, 0.2, PICKET_HEIGHT + 0.08, 1.8, PICKET_WHITE)
			else:
				var hh := lerpf(HEDGE_HEIGHT.x, HEDGE_HEIGHT.y, _h01([plan.seed, key, "hedge_h"]))
				_wall_run(ch, f, Vector2(span.x, 0.45), Vector2(span.y, 0.45), hh, 0.75, W_HEDGE, HEDGE_GREEN)
	# The lot lines: a fence down each side from the house front back, and along the back, built by
	# the lot on the -x / -z side of a shared line (so each is built once) or wherever the line is
	# the block's edge (a corner lot's side street: a taller stucco wall). Not toward the freeway's
	# right of way, which builds its own sound wall.
	var full_cell: Rect2 = lp.full_cell
	var stucco_fence := _h01([plan.seed, key, "fence"]) < float(odds.fence_stucco)
	var ci := cell_index(grid, full_cell.get_center())
	for edge in 4:
		# 0 -Z, 1 +Z, 2 -X, 3 +X of the full cell.
		var on_block := (edge == 0 and absf(full_cell.position.y - inner.position.y) < 0.3) or (edge == 1 and absf(full_cell.end.y - inner.end.y) < 0.3) \
			or (edge == 2 and absf(full_cell.position.x - inner.position.x) < 0.3) or (edge == 3 and absf(full_cell.end.x - inner.end.x) < 0.3)
		# The front edge has its own edging (the street line, or the walk street's).
		if edge == int(f.side):
			continue
		var nb: Vector2i = ci + [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)][edge]
		if not on_block and corridor_cells.has(nb):
			continue
		if not on_block and (edge == 0 or edge == 2):
			continue
		var line := _edge_line(lp.cell, edge)
		# In frame coordinates: a line along u (the back) or along v (a side).
		var a := _to_frame(f, Rect2(line[0], Vector2.ZERO))
		var b := _to_frame(f, Rect2(line[1], Vector2.ZERO))
		var pa := Vector2(a.position.x, a.position.y)
		var pb := Vector2(b.position.x, b.position.y)
		var along_v := absf(pa.x - pb.x) < 0.01
		if along_v:
			# A side: from the house front line back (the front garden stays open), a gate near the front.
			var v0 := maxf(fd, 0.0)
			var v1 := V
			var u := pa.x
			var inset := 0.12 if u < U * 0.5 else -0.12
			if v1 - v0 < 1.0:
				continue
			var h := FENCE_HEIGHT if not on_block else 1.4
			var kind := W_STUCCO if (stucco_fence or on_block) else W_WOOD
			var col: Color = paint if kind == W_STUCCO else timber
			# Open for the first metre past the house front: the side gate.
			if v1 - v0 > 2.2:
				_wall_run(ch, f, Vector2(u + inset, v0 + 1.0), Vector2(u + inset, v1), h, 0.12 if kind == W_WOOD else 0.2, kind, col)
		else:
			var v := pa.y
			var inset := -0.12 if v > V * 0.5 else 0.12
			var h := FENCE_HEIGHT if not on_block else 1.4
			var kind := W_STUCCO if (stucco_fence or on_block) else W_WOOD
			var col: Color = paint if kind == W_STUCCO else timber
			_wall_run(ch, f, Vector2(0.1, v + inset), Vector2(U - 0.1, v + inset), h, 0.12 if kind == W_WOOD else 0.2, kind, col)
	# Planting, a car in the drive, the bins, the pool's coping, the courtyard's fountain.
	for pc: Array in lp.pieces:
		var r: Rect2 = pc[0]
		var kind: int = pc[1]
		match String(pc[3]):
			"front":
				_plant_front(ch, r, kind, rng)
			"back":
				_plant_back(ch, r, kind, rng)
			"court":
				_dress_court(ch, r, kind, rng)
			"bed":
				# Shrubs down the bed, a flower between them.
				var long := maxf(r.size.x, r.size.y)
				var n := clampi(int(long / 1.8), 0, 5)
				for i in n:
					var t := (float(i) + 0.5) / float(n)
					var p := Vector2(lerpf(r.position.x, r.end.x, t), r.get_center().y) if r.size.x >= r.size.y else Vector2(r.get_center().x, lerpf(r.position.y, r.end.y, t))
					if i % 2 == 0:
						_shrub(ch, p, rng, 0.7)
					else:
						_flower(ch, p, rng)
			"pool":
				_coping(ch, r)
	if drive.size.x > 0.0 and _h01([plan.seed, key, "drive_car"]) < DRIVE_CAR_ODDS and ch._yard_cars < MAX_CARS:
		var dq := _to_frame(f, drive)
		if dq.size.y >= 5.0:
			var c := _fp(f, dq.get_center().x, maxf(dq.end.y - 3.0, 2.7))
			var into: Vector2 = f.v
			ch._yard_cars += 1
			LotFill._car(ch, rng, Vector3(c.x, base, c.y), atan2(into.x, into.y) + rng.randf_range(-0.03, 0.03))
	# The bins, in the side yard by the drive (or the front corner).
	var bin_v := clampf(fd + 0.6, 0.6, V - 0.6)
	var bin_u := hu.x - 0.6 if hu.x > 1.4 else (hu.y + 0.6 if U - hu.y > 1.4 else -1.0)
	if bin_u > 0.0 and _h01([plan.seed, key, "bins"]) < 0.8:
		for k in 3:
			var p := _fp(f, bin_u, bin_v + float(k) * 0.75)
			_box_wall(ch, Vector3(0.62, 1.05, 0.7), Vector3(p.x, base, p.y), W_METAL, BIN_COLORS[k])
	# Now and then a dog in the yard (DogYard: a hash share, behind the front wall or pickets, or out back).
	DogYard.consider(ch, lp, fd >= 1.0 and roll < float(odds.edge_picket) and not lp.walk_front)


## Front garden planting by its look: a lawn gets a tree or a palm and a bed of shrubs along the
## house front; a decomposed granite garden gets gazania and the odd shrub and palm; a patio pots.
static func _plant_front(ch: CityChunk, r: Rect2, kind: int, rng: RandomNumberGenerator) -> void:
	var area := r.size.x * r.size.y
	if area < 3.0:
		return
	var c := r.get_center()
	match kind:
		G_LAWN:
			# A palm or a tree on a lawn big enough (the shrubs are in the bed along the house).
			if minf(r.size.x, r.size.y) >= 3.6 and rng.randf() < 0.6:
				if rng.randf() < 0.55:
					_palm(ch, c + Vector2(rng.randf_range(-0.5, 0.5), rng.randf_range(-0.5, 0.5)), rng)
				else:
					_tree(ch, c, rng)
		G_DG:
			# Gazania over the decomposed granite, a palm or a shrub as its specimen.
			var n := clampi(int(area / 2.2), 1, 14)
			for i in n:
				_flower(ch, Vector2(rng.randf_range(r.position.x + 0.3, r.end.x - 0.3), rng.randf_range(r.position.y + 0.3, r.end.y - 0.3)), rng)
			if minf(r.size.x, r.size.y) >= 2.2 and rng.randf() < 0.5:
				_palm(ch, c, rng)
			elif area > 6.0:
				_shrub(ch, c, rng, 0.8)


static func _plant_back(ch: CityChunk, r: Rect2, kind: int, rng: RandomNumberGenerator) -> void:
	if minf(r.size.x, r.size.y) < 2.0:
		return
	var c := r.get_center()
	if kind == G_LAWN and minf(r.size.x, r.size.y) >= 4.0 and rng.randf() < 0.55:
		_tree(ch, c + Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)), rng)
	# Shrubs along the yard's longer edge (the back fence).
	var n := clampi(int(maxf(r.size.x, r.size.y) / 3.0), 0, 4)
	for i in n:
		if rng.randf() < 0.55:
			var t := (float(i) + 0.5) / float(n)
			var p := Vector2(lerpf(r.position.x + 0.6, r.end.x - 0.6, t), r.end.y - 0.7) if r.size.x >= r.size.y else Vector2(r.end.x - 0.7, lerpf(r.position.y + 0.6, r.end.y - 0.6, t))
			_shrub(ch, p, rng, 0.9)


## A courtyard apartment's garden: a tiled court with a fountain in the middle and palms in two
## corners, or a lawn with a tree.
static func _dress_court(ch: CityChunk, r: Rect2, kind: int, rng: RandomNumberGenerator) -> void:
	if minf(r.size.x, r.size.y) < 3.0:
		return
	var c := r.get_center()
	var base := CityChunk.SIDEWALK_TOP + LIFT
	if kind == G_TILE and minf(r.size.x, r.size.y) >= 4.5:
		# A tiled fountain: a low octagon read as a square basin, a pedestal, the water.
		var s := minf(minf(r.size.x, r.size.y) * 0.32, 2.6)
		for side in 4:
			var horiz := side < 2
			var off := Vector2(0.0, (s - 0.2) * 0.5 * (1.0 if side == 0 else -1.0)) if horiz else Vector2((s - 0.2) * 0.5 * (1.0 if side == 2 else -1.0), 0.0)
			var size := Vector3(s, 0.45, 0.2) if horiz else Vector3(0.2, 0.45, s - 0.4)
			_box_wall(ch, size, Vector3(c.x + off.x, base, c.y + off.y), W_STUCCO, Color(0.86, 0.62, 0.48))
		_box_wall(ch, Vector3(0.35, 0.95, 0.35), Vector3(c.x, base, c.y), W_STUCCO, Color(0.9, 0.86, 0.78))
		_ground_box(ch, Vector3(s - 0.4, 0.05, s - 0.4), Vector3(c.x, base + 0.34 + ch._gy(c.x, c.y), c.y), G_POOL)
		for k in 2:
			var corner := Vector2(r.position.x + 1.0, r.position.y + 1.0) if k == 0 else Vector2(r.end.x - 1.0, r.end.y - 1.0)
			_palm(ch, corner, rng)
	else:
		_tree(ch, c, rng)
		_shrub(ch, c + Vector2(r.size.x * 0.3, 0.0), rng, 0.8)


## A pool's coping: a pale stone edge round it (the water is in the ground mesh, a step down).
static func _coping(ch: CityChunk, r: Rect2) -> void:
	var base := CityChunk.SIDEWALK_TOP + LIFT
	var t := 0.32
	for side in 4:
		var horiz := side < 2
		var c := r.get_center() + (Vector2(0.0, (r.size.y + t) * 0.5 * (1.0 if side == 0 else -1.0)) if horiz else Vector2((r.size.x + t) * 0.5 * (1.0 if side == 2 else -1.0), 0.0))
		var size := Vector3(r.size.x + t * 2.0, 0.06, t) if horiz else Vector3(t, 0.06, r.size.y)
		_box_wall(ch, size, Vector3(c.x, base, c.y), W_CONCRETE, Color(0.9, 0.88, 0.84), false)


# --- Campus ----------------------------------------------------------------------------------------------

## A campus block's ground, from the plan and each built lot's footprint: {"pieces": [[Rect2, G_*,
## variant, role]], "strips": [[a, b, width, G_*]], "quads": [Rect2], "parks": [Rect2],
## "service": [[Rect2, door side]], "entries": [[from Vector2, to Vector2]]}. The free ground is the
## block's inner rect less every lot's cell that holds a building and less the campus hall; a big
## piece of it is a quad (or once a block a car park), a small one a service yard or a planted
## lawn. Each building gets a walk from its street face to the pavement and, with room behind it,
## a service yard.
static func campus_block(plan: CityPlan, bx: int, bz: int, entries: Array) -> Dictionary:
	var block: Dictionary = plan.block(bx, bz)
	var inner: Rect2 = (block.rect as Rect2).grow(-plan.sidewalk_width)
	var holes: Array[Rect2] = []
	var lots: Array = []
	for e: Dictionary in entries:
		lots.append(e.lot)
		holes.append(e.lot.get("cell", Rect2((e.lot.center as Vector2) - (e.lot.size as Vector2) * 0.5, e.lot.size)))
	# Every lot the plan still has (a pocket garden, a corridor lot, a pad) keeps its cell too.
	for lot: Dictionary in plan.lots(bx, bz):
		var c: Rect2 = lot.get("cell", Rect2((lot.center as Vector2) - (lot.size as Vector2) * 0.5, lot.size))
		if not holes.has(c):
			holes.append(c)
	holes.append_array(landmark_holes(plan, inner))
	var out := {"pieces": [], "strips": [], "quads": [], "parks": [], "service": [], "lawns": []}
	var parked := false
	var k := 0
	for r: Rect2 in LotFill._minus(inner, holes, 0.0):
		k += 1
		if minf(r.size.x, r.size.y) < 3.0:
			continue
		if r.size.x >= QUAD_MIN.x and r.size.y >= QUAD_MIN.y or r.size.y >= QUAD_MIN.x and r.size.x >= QUAD_MIN.y:
			if not parked and r.size.x >= 24.0 and r.size.y >= 18.0 and _h01([plan.seed, bx, bz, k, "campus_park"]) < CAMPUS_PARK_ODDS:
				parked = true
				# A car park the length of a whole block is a lot of asphalt: past CAMPUS_PARK_MAX
				# the rest of the piece is a quad.
				var long_x := r.size.x >= r.size.y
				var long := maxf(r.size.x, r.size.y)
				if long <= CAMPUS_PARK_MAX:
					out.parks.append(r)
					continue
				var cut := CAMPUS_PARK_MAX * 0.8
				out.parks.append(Rect2(r.position, Vector2(cut, r.size.y)) if long_x else Rect2(r.position, Vector2(r.size.x, cut)))
				r = Rect2(r.position + Vector2(cut, 0.0), Vector2(r.size.x - cut, r.size.y)) if long_x else Rect2(r.position + Vector2(0.0, cut), Vector2(r.size.x, r.size.y - cut))
				if minf(r.size.x, r.size.y) < QUAD_MIN.y or maxf(r.size.x, r.size.y) < QUAD_MIN.x:
					out.lawns.append(r)
					continue
			_quad_plan(plan, r, out, [bx, bz, k])
		elif minf(r.size.x, r.size.y) >= 9.0 and _h01([plan.seed, bx, bz, k, "service"]) < 0.5:
			var pad := r.grow(-1.0)
			out.service.append([pad, nearest_side(inner, r)])
			out.pieces.append([pad, G_CONCRETE, 0.6, "service"])
		else:
			out.lawns.append(r)
	# The buildings: a walk from the door (the middle of the face nearest the street) out to the
	# pavement, and a service yard behind when there is room.
	for e: Dictionary in entries:
		var lot: Dictionary = e.lot
		var cell: Rect2 = lot.get("cell", Rect2((lot.center as Vector2) - (lot.size as Vector2) * 0.5, lot.size))
		var side := nearest_side(inner, cell)
		var f := _frame(cell, side)
		var parts: Array[Rect2] = []
		parts.assign(e.parts)
		var bv0: float = f.V
		var bv1 := 0.0
		var bu0: float = f.U
		var bu1 := 0.0
		for r: Rect2 in parts:
			var q := _to_frame(f, r)
			bv0 = minf(bv0, q.position.y)
			bv1 = maxf(bv1, q.end.y)
			bu0 = minf(bu0, q.position.x)
			bu1 = maxf(bu1, q.end.x)
		if bu1 <= bu0:
			continue
		var cu := (bu0 + bu1) * 0.5
		# Out to the block's pavement: the frame's front edge is the cell's, so carry on to the inner edge.
		var reach := _street_reach(inner, cell, side)
		# A plaza before the door (a wider apron along the face) and the walk out to the street, which
		# stops where the apron starts so the two never lie on each other.
		var walk_end := bv0
		if bv0 > 4.0:
			var apron := _fr(f, maxf(bu0 - 1.0, 0.0), bv0 - 3.0, minf(bu1 + 1.0, f.U), bv0)
			out.pieces.append([apron, G_CONCRETE, 0.15, "apron"])
			walk_end = bv0 - 3.0
		if walk_end + reach > 0.5:
			var r := _fr(f, cu - ENTRY_WALK * 0.5, -reach, cu + ENTRY_WALK * 0.5, walk_end)
			out.pieces.append([r, G_CONCRETE, 0.2, "entry", _fp(f, cu, bv0), f.u])
		var back: float = float(f.V) - bv1
		if back >= 7.0 and _h01([plan.seed, lot.seed, "campus_service"]) < SERVICE_ODDS:
			var su := clampf(cu - 5.0, 0.5, maxf(float(f.U) - 10.5, 0.5))
			var pad := _fr(f, su, bv1 + 0.5, su + minf(10.0, float(f.U) - 1.0), bv1 + minf(back - 1.0, 7.0))
			out.service.append([pad, -1])
			out.pieces.append([pad, G_CONCRETE, 0.7, "service"])
	return out


## How far from a cell's edge on `side` the block's pavement is (0 for a lot at the edge).
static func _street_reach(inner: Rect2, cell: Rect2, side: int) -> float:
	match side:
		0:
			return cell.position.y - inner.position.y
		1:
			return inner.end.y - cell.end.y
		2:
			return cell.position.x - inner.position.x
		_:
			return inner.end.x - cell.end.x


## A quad over `r`: a walk round it 2 m in, two diagonals corner to corner and one cross walk.
static func _quad_plan(plan: CityPlan, r: Rect2, out: Dictionary, tag: Array) -> void:
	out.quads.append(r)
	var q := r.grow(-2.0)
	var a := q.position
	var b := q.end
	var c := Vector2(q.position.x, q.end.y)
	var d := Vector2(q.end.x, q.position.y)
	var w := CAMPUS_WALK
	if _h01([plan.seed, tag, "diag"]) < 0.75:
		out.strips.append([a, b, w, G_CONCRETE])
		out.strips.append([c, d, w, G_CONCRETE])
	# One straight walk across the long way, through the middle.
	var mid := q.get_center()
	if q.size.x >= q.size.y:
		out.pieces.append([Rect2(q.position.x, mid.y - w * 0.5, q.size.x, w), G_CONCRETE, 0.25, "walk"])
	else:
		out.pieces.append([Rect2(mid.x - w * 0.5, q.position.y, w, q.size.y), G_CONCRETE, 0.25, "walk"])


static func _build_campus(ch: CityChunk, cp: Dictionary) -> void:
	var full := ch.level == CityChunk.Level.FULL and not ch.capturing
	for pc: Array in cp.pieces:
		_ground(ch, pc[0], pc[1], pc[2], PATH_LIFT)
		ch._lot_rects.append(pc[0])
	for s: Array in cp.strips:
		_strip(ch, s[0], s[1], s[2], s[3], 0.25)
		# The lawn's blade grass keeps off the walk (its blockers are rects: squares along it).
		var a: Vector2 = s[0]
		var b: Vector2 = s[1]
		var n := maxi(1, ceili(a.distance_to(b) / 2.0))
		for i in n + 1:
			var p := a.lerp(b, float(i) / float(n))
			ch._lot_rects.append(Rect2(p - Vector2(1.8, 1.8), Vector2(3.6, 3.6)))
	for r: Rect2 in cp.parks:
		LotFill._car_park(ch, r, hash([ch.ix, ch.iz, r.position, "campus_park"]))
		ch._lot_rects.append(r)
	if full:
		_defer1(ch, _dress_campus.bind(ch, cp))


static func _dress_campus(ch: CityChunk, cp: Dictionary) -> void:
	var rng := _rng(ch.plan, "campus", [ch.ix, ch.iz])
	for r: Rect2 in cp.quads:
		_dress_quad(ch, r, cp.strips, rng)
	for sv: Array in cp.service:
		_service_yard(ch, sv[0], rng)
	for r: Rect2 in cp.lawns:
		if minf(r.size.x, r.size.y) >= 6.0 and rng.randf() < 0.6:
			_tree(ch, r.get_center(), rng)
		for i in clampi(int(r.size.x * r.size.y / 60.0), 0, 4):
			_shrub(ch, Vector2(rng.randf_range(r.position.x + 1.0, r.end.x - 1.0), rng.randf_range(r.position.y + 1.0, r.end.y - 1.0)), rng, 1.0)
	# Trees either side of each building's entry walk, a bench by the door.
	for pc: Array in cp.pieces:
		if pc[3] != "entry":
			continue
		var r: Rect2 = pc[0]
		var long_x := r.size.x > r.size.y
		var len := maxf(r.size.x, r.size.y)
		var n := clampi(int(len / 11.0), 1 if len >= 5.0 else 0, 3)
		# Foundation shrubs along the face either side of the door, where the walk meets the building.
		if pc.size() >= 6:
			var door: Vector2 = pc[4]
			var along: Vector2 = pc[5]
			var out_dir := Vector2(-along.y, along.x)
			if (r.get_center() - door).dot(out_dir) < 0.0:
				out_dir = -out_dir
			for s: float in [-1.0, 1.0]:
				for j in 3:
					_shrub(ch, door + along * s * (ENTRY_WALK * 0.5 + 1.2 + float(j) * 1.7) + out_dir * 0.9, rng, 0.85)
		for i in n:
			var t := (float(i) + 0.5) / float(n)
			for s: float in [-1.0, 1.0]:
				var p := Vector2(lerpf(r.position.x, r.end.x, t), r.get_center().y + s * (r.size.y * 0.5 + 1.6)) if long_x \
					else Vector2(r.get_center().x + s * (r.size.x * 0.5 + 1.6), lerpf(r.position.y, r.end.y, t))
				_tree(ch, p, rng)


## A quad's furniture: trees along the walks, lamps at the walks' ends and crossing, benches facing
## the middle, shrubs in beds along the edges.
static func _dress_quad(ch: CityChunk, r: Rect2, strips: Array, rng: RandomNumberGenerator) -> void:
	var c := r.get_center()
	var base := CityChunk.SIDEWALK_TOP + PATH_LIFT
	for s: Array in strips:
		var a: Vector2 = s[0]
		var b: Vector2 = s[1]
		if not r.grow(0.5).has_point(a) or not r.grow(0.5).has_point(b):
			continue
		var dir := (b - a).normalized()
		var nrm := Vector2(-dir.y, dir.x)
		var len := a.distance_to(b)
		var n := clampi(int(len / 14.0), 1, 5)
		for i in n:
			var t := (float(i) + 0.5) / float(n)
			var p := a.lerp(b, t)
			# Not on the crossing in the middle.
			if p.distance_to(c) < 6.0:
				continue
			_tree(ch, p + nrm * (CAMPUS_WALK * 0.5 + 2.2) * (1.0 if i % 2 == 0 else -1.0), rng)
		for t: float in [0.18, 0.82]:
			var p := a.lerp(b, t) + nrm * (CAMPUS_WALK * 0.5 + 0.6)
			LotFill._lamp(ch, Vector3(p.x, base, p.y))
	# Benches round the crossing, facing in.
	for k in 4:
		var ang := float(k) * PI * 0.5 + PI * 0.25 + PI * 0.125
		var p := c + Vector2(cos(ang), sin(ang)) * 5.5
		ch._add_bench(Vector3(p.x, base, p.y), atan2(cos(ang), sin(ang)))
	# Shrub beds along the quad's edges.
	var n := clampi(int((r.size.x + r.size.y) / 9.0), 2, 10)
	for i in n:
		var t := rng.randf()
		var edge := rng.randi() % 4
		var p: Vector2
		match edge:
			0:
				p = Vector2(lerpf(r.position.x + 2.0, r.end.x - 2.0, t), r.position.y + 1.0)
			1:
				p = Vector2(lerpf(r.position.x + 2.0, r.end.x - 2.0, t), r.end.y - 1.0)
			2:
				p = Vector2(r.position.x + 1.0, lerpf(r.position.y + 2.0, r.end.y - 2.0, t))
			_:
				p = Vector2(r.end.x - 1.0, lerpf(r.position.y + 2.0, r.end.y - 2.0, t))
		_shrub(ch, p, rng, 1.1)


## A service yard over `pad`: a block-wall enclosure on three sides of a dumpster bay, two
## dumpsters, a transformer, a few pallets.
static func _service_yard(ch: CityChunk, pad: Rect2, rng: RandomNumberGenerator) -> void:
	var base := CityChunk.SIDEWALK_TOP + PATH_LIFT
	var c := pad.get_center()
	var long_x := pad.size.x >= pad.size.y
	# The enclosure: 5 x 3.2 m, 2 m walls, its open side to the pad's long axis.
	var ew := 5.2
	var ed := 3.2
	var eo := Vector2(pad.position.x + ew * 0.5 + 0.5, c.y) if long_x else Vector2(c.x, pad.position.y + ew * 0.5 + 0.5)
	var wall := Color(0.78, 0.74, 0.68)
	if long_x:
		_box_wall(ch, Vector3(ew, 2.0, 0.2), Vector3(eo.x, base, eo.y - ed * 0.5), W_SOUND, wall)
		_box_wall(ch, Vector3(0.2, 2.0, ed), Vector3(eo.x - ew * 0.5, base, eo.y), W_SOUND, wall)
		_box_wall(ch, Vector3(0.2, 2.0, ed), Vector3(eo.x + ew * 0.5, base, eo.y), W_SOUND, wall)
		for k in 2:
			_dumpster(ch, Vector2(eo.x - 1.2 + 2.4 * k, eo.y - 0.35), 0.0)
	else:
		_box_wall(ch, Vector3(0.2, 2.0, ew), Vector3(eo.x - ed * 0.5, base, eo.y), W_SOUND, wall)
		_box_wall(ch, Vector3(ed, 2.0, 0.2), Vector3(eo.x, base, eo.y - ew * 0.5), W_SOUND, wall)
		_box_wall(ch, Vector3(ed, 2.0, 0.2), Vector3(eo.x, base, eo.y + ew * 0.5), W_SOUND, wall)
		for k in 2:
			_dumpster(ch, Vector2(eo.x - 0.35, eo.y - 1.2 + 2.4 * k), PI * 0.5)
	# A transformer on its own pad at the far end, and a stack of pallets.
	var far := Vector2(pad.end.x - 1.4, c.y) if long_x else Vector2(c.x, pad.end.y - 1.4)
	_box_wall(ch, Vector3(1.5, 1.35, 1.3), Vector3(far.x, base, far.y), W_METAL, Color(0.26, 0.36, 0.26))
	if rng.randf() < 0.7:
		var pp := far + (Vector2(-2.4, 0.0) if long_x else Vector2(0.0, -2.4))
		for k in rng.randi_range(2, 5):
			_box_wall(ch, Vector3(1.2, 0.14, 1.0), Vector3(pp.x, base + float(k) * 0.145, pp.y), W_WOOD, Color(0.72, 0.6, 0.46), k == 0)


static func _dumpster(ch: CityChunk, at: Vector2, yaw: float) -> void:
	var base := CityChunk.SIDEWALK_TOP + PATH_LIFT
	var green := Color(0.14, 0.30, 0.22)
	var size := Vector3(1.9, 1.15, 1.2) if yaw == 0.0 else Vector3(1.2, 1.15, 1.9)
	_box_wall(ch, size, Vector3(at.x, base, at.y), W_METAL, green)
	# The lid, black plastic, a little proud.
	_box_wall(ch, Vector3(size.x + 0.04, 0.06, size.z + 0.04), Vector3(at.x, base + 1.15, at.y), W_METAL, Color(0.06, 0.06, 0.07), false)


# --- The freeway's right of way ---------------------------------------------------------------------------

## A block's right of way: {"cells": [Rect2], "walls": [[a, b, kind]] (cell edges toward a house
## lot: a sound wall or chain-link; toward the street: chain-link), "yard": Rect2 (a maintenance
## yard's cell, zero size for none), "district"}. Pure: the plan, the block and its corridor lots.
static func corridor_block(plan: CityPlan, bx: int, bz: int, corridor: Array) -> Dictionary:
	var block: Dictionary = plan.block(bx, bz)
	var all := plan.lots(bx, bz)
	var grid := lot_grid(plan, bx, bz, all)
	var by_cell := {}
	for lot: Dictionary in all:
		by_cell[cell_index(grid, lot.center)] = lot
	var mine := {}
	var cells: Array[Rect2] = []
	for lot: Dictionary in corridor:
		var i := cell_index(grid, lot.center)
		mine[i] = true
		cells.append(cell_rect(grid, i))
	var sound := int(block.district) in SOUND_DISTRICTS
	var walls: Array = []
	var dirs := [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]
	for i: Vector2i in mine:
		var r := cell_rect(grid, i)
		for e in 4:
			var nb: Vector2i = i + dirs[e]
			if mine.has(nb):
				continue
			var line := _edge_line(r, e)
			var outside := nb.x < 0 or nb.y < 0 or nb.x >= int(grid.nx) or nb.y >= int(grid.nz)
			var kind := W_CHAIN
			if not outside and by_cell.has(nb) and not (by_cell[nb] as Dictionary).yard and sound:
				kind = W_SOUND
			walls.append([line[0], line[1], kind, e])
	# A maintenance yard in the cell most under the deck, now and then.
	var yard := Rect2()
	if not cells.is_empty() and _h01([plan.seed, bx, bz, "row_yard"]) < ROW_YARD_ODDS and plan.macro and plan.macro.freeway:
		var best := INF
		for r: Rect2 in cells:
			if minf(r.size.x, r.size.y) < 14.0:
				continue
			var d := _deck_distance(plan, r.get_center())
			if d < best:
				best = d
				yard = r
	return {"cells": cells, "walls": walls, "yard": yard, "district": int(block.district), "grid": grid}


## The two ends of side `e` (0 -Z, 1 +Z, 2 -X, 3 +X) of `r`.
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


## Metres from `p` to the nearest deck edge (negative under the deck).
static func _deck_distance(plan: CityPlan, p: Vector2) -> float:
	var best := INF
	for s in plan.macro.freeway.segments_in(Rect2(p - Vector2(40.0, 40.0), Vector2(80.0, 80.0))):
		var a: Vector2 = s.a
		var b: Vector2 = s.b
		var d := (Geometry2D.get_closest_point_to_segment(p, a, b) - p).length() - float(s.width) * 0.5
		best = minf(best, d)
	return best


static func _build_corridor(ch: CityChunk, cp: Dictionary) -> void:
	var full := ch.level == CityChunk.Level.FULL and not ch.capturing
	var yard: Rect2 = cp.yard
	for r: Rect2 in cp.cells:
		ch._lot_rects.append(r)
		if r == yard and full:
			_ground(ch, r, G_GRAVEL, 0.6)
			continue
		if full:
			ch._yard_ivy.append(r)
		elif maxf(r.size.x, r.size.y) >= 6.0:
			ch._add_slab(Vector3(r.get_center().x, CityChunk.SIDEWALK_TOP + 0.02, r.get_center().y), Vector3(r.size.x, 0.04, r.size.y),
				IVY_FAR, false, PropFactory.lawn(CityChunk.CORRIDOR_IVY, hash([ch.plan.seed, "corridor_ivy"]), 0.0, 0.0))
	if full:
		_defer1(ch, _dress_corridor.bind(ch, cp))


static func _dress_corridor(ch: CityChunk, cp: Dictionary) -> void:
	var yard: Rect2 = cp.yard
	var rng := _rng(ch.plan, "row", [ch.ix, ch.iz])
	# The boundary: a sound wall toward a house lot, chain-link toward the street and anything else.
	for w: Array in cp.walls:
		var a: Vector2 = w[0]
		var b: Vector2 = w[1]
		var e: int = w[3]
		# A hair inside the right of way.
		var inward := [Vector2(0, 0.25), Vector2(0, -0.25), Vector2(0.25, 0), Vector2(-0.25, 0)][e] as Vector2
		if int(w[2]) == W_SOUND:
			_sound_wall(ch, a + inward, b + inward)
		else:
			_chain_run(ch, a + inward, b + inward, ROW_FENCE)
	if yard.size.x > 0.0:
		_maintenance_yard(ch, yard, rng)
	# Planting along the deck: an oleander hedge row and a tree row either side, kept to this block's
	# right of way and out from under the deck and its ramps.
	var cells: Array[Rect2] = []
	for r: Rect2 in cp.cells:
		if r != yard:
			cells.append(r.grow(-0.9))
	var fw: Freeway = ch.plan.macro.freeway
	var area := Rect2()
	for r: Rect2 in cells:
		area = r if area.size.x <= 0.0 else area.merge(r)
	if area.size.x <= 0.0:
		return
	for s in fw.segments_in(area):
		var a: Vector2 = s.a
		var b: Vector2 = s.b
		var len := a.distance_to(b)
		if len < 0.5:
			continue
		var dir := (b - a) / len
		var nrm := Vector2(-dir.y, dir.x)
		var half := float(s.width) * 0.5
		for side: float in [-1.0, 1.0]:
			var t := 0.0
			while t < len:
				var p := a + dir * t + nrm * side * (half + HEDGE_OFFSET)
				if _in_any(cells, p) and not fw.blocks(p, HEDGE_OFFSET - 1.0) and not fw.blocks_rect(Rect2(p - Vector2(0.5, 0.5), Vector2(1.0, 1.0)), 0.8):
					_shrub(ch, p + Vector2(rng.randf_range(-0.3, 0.3), rng.randf_range(-0.3, 0.3)), rng, 1.6)
				t += HEDGE_STEP
			t = ROW_TREE_STEP * 0.5 * (0.5 + 0.5 * float(int(s.index) % 2))
			while t < len:
				var p := a + dir * t + nrm * side * (half + ROW_TREE_OFFSET)
				if _in_any(cells, p) and not fw.blocks(p, ROW_TREE_OFFSET - 2.0) and not fw.blocks_rect(Rect2(p - Vector2(0.5, 0.5), Vector2(1.0, 1.0)), 3.0):
					_tree(ch, p, rng)
				t += ROW_TREE_STEP
	# Clumps over the rest of the right of way, away from the deck.
	for r: Rect2 in cells:
		var n := clampi(int(r.size.x * r.size.y / ROW_CLUMP_AREA), 0, 4)
		for i in n:
			var p := Vector2(rng.randf_range(r.position.x, r.end.x), rng.randf_range(r.position.y, r.end.y))
			if _deck_distance(ch.plan, p) > ROW_TREE_OFFSET + 2.0:
				_shrub(ch, p, rng, 1.3)


## `area` less one rect.
static func _less(area: Rect2, hole: Rect2) -> Array[Rect2]:
	var holes: Array[Rect2] = [hole]
	return LotFill._minus(area, holes, 0.0)


static func _in_any(rects: Array[Rect2], p: Vector2) -> bool:
	for r: Rect2 in rects:
		if r.has_point(p):
			return true
	return false


## A sound wall from a to b: split-face block in 6 m panels between pilasters, a cap, stepping
## with the ground.
static func _sound_wall(ch: CityChunk, a: Vector2, b: Vector2) -> void:
	var len := a.distance_to(b)
	if len < 0.5:
		return
	var n := maxi(1, ceili(len / 6.0))
	var along_x := absf(b.x - a.x) > absf(b.y - a.y)
	var tan := Color(0.80, 0.76, 0.68)
	var base := CityChunk.SIDEWALK_TOP + LIFT
	for i in n:
		var p0 := a.lerp(b, float(i) / float(n))
		var p1 := a.lerp(b, float(i + 1) / float(n))
		var c := (p0 + p1) * 0.5
		var seg := p0.distance_to(p1)
		_box_wall(ch, Vector3(seg, SOUND_WALL, 0.3) if along_x else Vector3(0.3, SOUND_WALL, seg), Vector3(c.x, base, c.y), W_SOUND, tan)
		_box_wall(ch, Vector3(0.55, SOUND_WALL + 0.2, 0.5) if along_x else Vector3(0.5, SOUND_WALL + 0.2, 0.55), Vector3(p0.x, base, p0.y), W_SOUND, tan.darkened(0.05), false)
	_box_wall(ch, Vector3(0.55, SOUND_WALL + 0.2, 0.5) if along_x else Vector3(0.5, SOUND_WALL + 0.2, 0.55), Vector3(b.x, base, b.y), W_SOUND, tan.darkened(0.05), false)


## Chain-link from a to b: the mesh as one cut-out panel a run (in 6 m pieces stepping with the
## ground), galvanised posts every 3 m and a top rail.
static func _chain_run(ch: CityChunk, a: Vector2, b: Vector2, h: float) -> void:
	var len := a.distance_to(b)
	if len < 0.5:
		return
	var along_x := absf(b.x - a.x) > absf(b.y - a.y)
	var base := CityChunk.SIDEWALK_TOP + LIFT
	var galv := Color(0.6, 0.61, 0.62)
	var n := maxi(1, ceili(len / 6.0))
	for i in n:
		var p0 := a.lerp(b, float(i) / float(n))
		var p1 := a.lerp(b, float(i + 1) / float(n))
		var c := (p0 + p1) * 0.5
		var seg := p0.distance_to(p1)
		_box_wall(ch, Vector3(seg, h, 0.02) if along_x else Vector3(0.02, h, seg), Vector3(c.x, base, c.y), W_CHAIN, galv)
		_box_wall(ch, Vector3(seg, 0.05, 0.05) if along_x else Vector3(0.05, 0.05, seg), Vector3(c.x, base + h - 0.05, c.y), W_POST, galv, false)
	var posts := maxi(1, ceili(len / 3.0))
	for i in posts + 1:
		var p := a.lerp(b, float(i) / float(posts))
		_box_wall(ch, Vector3(0.06, h + 0.05, 0.06), Vector3(p.x, base, p.y), W_POST, galv, false)


## A Caltrans maintenance yard: chain-link round the cell with a gate gap, k-rail stacked in rows,
## a storage container, a work truck, a light pole.
static func _maintenance_yard(ch: CityChunk, r: Rect2, rng: RandomNumberGenerator) -> void:
	var q := r.grow(-0.6)
	var gate := rng.randi() % 4
	for e in 4:
		var line := _edge_line(q, e)
		var a: Vector2 = line[0]
		var b: Vector2 = line[1]
		if e == gate:
			var m := (a + b) * 0.5
			var d := (b - a).normalized()
			_chain_run(ch, a, m - d * 3.0, ROW_FENCE)
			_chain_run(ch, m + d * 3.0, b, ROW_FENCE)
		else:
			_chain_run(ch, a, b, ROW_FENCE)
	var base := CityChunk.SIDEWALK_TOP + LIFT
	var c := q.get_center()
	var along_x := q.size.x >= q.size.y
	# K-rail: 3 m pieces in two rows, a few stacked.
	var grey := Color(0.82, 0.81, 0.78)
	var row0 := c + (Vector2(-q.size.x * 0.25, -q.size.y * 0.3) if along_x else Vector2(-q.size.x * 0.3, -q.size.y * 0.25))
	for k in rng.randi_range(4, 7):
		var p := row0 + (Vector2(float(k % 4) * 3.15, float(k / 4) * 0.9) if along_x else Vector2(float(k / 4) * 0.9, float(k % 4) * 3.15))
		var size := Vector3(3.0, 0.81, 0.6) if along_x else Vector3(0.6, 0.81, 3.0)
		_box_wall(ch, size, Vector3(p.x, base, p.y), W_CONCRETE, grey)
		if k < 2:
			_box_wall(ch, size, Vector3(p.x, base + 0.81, p.y), W_CONCRETE, grey, false)
	# A storage container along the far side.
	var cont := c + (Vector2(q.size.x * 0.18, q.size.y * 0.3 - 1.4) if along_x else Vector2(q.size.x * 0.3 - 1.4, q.size.y * 0.18))
	var paints := [Color(0.55, 0.22, 0.16), Color(0.2, 0.32, 0.5), Color(0.25, 0.4, 0.28), Color(0.72, 0.66, 0.54)]
	_box_wall(ch, Vector3(6.1, 2.6, 2.44) if along_x else Vector3(2.44, 2.6, 6.1), Vector3(cont.x, base, cont.y), W_METAL, paints[rng.randi() % paints.size()])
	# The crew's truck and a light.
	var truck := c + (Vector2(-q.size.x * 0.2, q.size.y * 0.15) if along_x else Vector2(q.size.x * 0.15, -q.size.y * 0.2))
	if ch._yard_cars < MAX_CARS:
		ch._yard_cars += 1
		ch._batch.add("apark_car_2", ArenaGrounds.car_mesh(2), Transform3D(Basis(Vector3.UP, (0.0 if along_x else PI * 0.5) + PI * 0.5), Vector3(truck.x, base + 0.005, truck.y)), Color(0.92, 0.92, 0.9))
		ch._batch.set_shadow_distance("apark_car_2", LotFill.CAR_SHADOW_DISTANCE)
	LotFill._lamp(ch, Vector3(q.position.x + 1.0, base, q.position.y + 1.0))


# --- Placing things ----------------------------------------------------------------------------------------

## One rect of yard ground: a FULL chunk collects it into the yard mesh (commit()); a LOD chunk or
## the far city's capture lays the lawns (6 m and more) as slabs - the merged far ground, or
## captured.ground. The rest of it is the pavement's colour give or take from up there, and every
## slab is more of the far ground's triangles.
static func _ground(ch: CityChunk, r: Rect2, kind: int, variant: float, lift: float = LIFT) -> void:
	if r.size.x < 0.3 or r.size.y < 0.3:
		return
	if ch.level == CityChunk.Level.FULL and not ch.capturing:
		ch._yard_ground.append([r, kind, variant, lift])
		return
	if kind != G_LAWN or maxf(r.size.x, r.size.y) < 6.0 or minf(r.size.x, r.size.y) < 2.0:
		return
	var c := r.get_center()
	ch._add_slab(Vector3(c.x, CityChunk.SIDEWALK_TOP + lift - 0.02, c.y), Vector3(r.size.x, 0.04, r.size.y), LAWN_FAR, false, LotFill._lawn_material(ch))


## A walk from a to b, `width` wide (a campus diagonal): FULL only, in the yard mesh.
static func _strip(ch: CityChunk, a: Vector2, b: Vector2, width: float, kind: int, variant: float) -> void:
	if ch.level == CityChunk.Level.FULL and not ch.capturing:
		ch._yard_strips.append([a, b, width, kind, variant])


## A box in the yard ground mesh (a fountain's water): FULL only, at `at` (relief included).
static func _ground_box(ch: CityChunk, size: Vector3, at: Vector3, kind: int) -> void:
	ch._yard_boxes.append([size, at, kind])


## An upright box standing on the ground at `foot` (x, base height, z; the relief is added here),
## `size` tall from there: into the walls mesh, with box collision when `collide`.
static func _box_wall(ch: CityChunk, size: Vector3, foot: Vector3, kind: int, paint: Color, collide: bool = true) -> void:
	if ch.level != CityChunk.Level.FULL or ch.capturing:
		return
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	# Stand on the lowest of the corners, so a wall on a slope does not hang over the ground.
	var g := minf(minf(ch._gy(foot.x - hx, foot.z - hz), ch._gy(foot.x + hx, foot.z + hz)), minf(ch._gy(foot.x - hx, foot.z + hz), ch._gy(foot.x + hx, foot.z - hz)))
	var g_hi := maxf(maxf(ch._gy(foot.x - hx, foot.z - hz), ch._gy(foot.x + hx, foot.z + hz)), maxf(ch._gy(foot.x - hx, foot.z + hz), ch._gy(foot.x + hx, foot.z - hz)))
	var sunk := g_hi - g
	var s := Vector3(size.x, size.y + sunk + 0.04, size.z)
	var c := Vector3(foot.x, foot.y + g - 0.04 + s.y * 0.5, foot.z)
	ch._yard_walls.append([s, c, kind, paint, size.y])
	if collide and size.y >= 0.3:
		ch._add_shape(s, c)


## A wall run in a lot's frame, from frame point a to b (u, v), `h` tall and `thick`, its foot at
## `lift` over the yard (a cap course on a wall).
static func _wall_run(ch: CityChunk, f: Dictionary, a: Vector2, b: Vector2, h: float, thick: float, kind: int, paint: Color, lift: float = 0.0) -> void:
	var pa := _fp(f, a.x, a.y)
	var pb := _fp(f, b.x, b.y)
	var len := pa.distance_to(pb)
	if len < 0.3:
		return
	var along_x := absf(pb.x - pa.x) > absf(pb.y - pa.y)
	var base := CityChunk.SIDEWALK_TOP + LIFT + lift
	# In pieces of up to 6 m, so a run follows the ground.
	var n := maxi(1, ceili(len / 6.0))
	for i in n:
		var p0 := pa.lerp(pb, float(i) / float(n))
		var p1 := pa.lerp(pb, float(i + 1) / float(n))
		var c := (p0 + p1) * 0.5
		var seg := p0.distance_to(p1)
		_box_wall(ch, Vector3(seg, h, thick) if along_x else Vector3(thick, h, seg), Vector3(c.x, base, c.y), kind, paint, lift == 0.0)


## Picket posts along a frame span at v, every `step` metres.
static func _posts(ch: CityChunk, f: Dictionary, span: Vector2, v: float, h: float, step: float, paint: Color) -> void:
	var n := maxi(1, ceili((span.y - span.x) / step))
	for i in n + 1:
		var p := _fp(f, lerpf(span.x, span.y, float(i) / float(n)), v)
		_box_wall(ch, Vector3(0.09, h, 0.09), Vector3(p.x, CityChunk.SIDEWALK_TOP + LIFT, p.y), W_STUCCO, paint, false)


## [a, b] less the openings (each [from, to]), as spans at least 0.4 m long.
static func _spans(a: float, b: float, openings: Array[Vector2]) -> Array[Vector2]:
	var out: Array[Vector2] = [Vector2(a, b)]
	for o: Vector2 in openings:
		var next: Array[Vector2] = []
		for s: Vector2 in out:
			if o.y <= s.x or o.x >= s.y:
				next.append(s)
				continue
			if o.x > s.x:
				next.append(Vector2(s.x, o.x))
			if o.y < s.y:
				next.append(Vector2(o.y, s.y))
		out = next
	var kept: Array[Vector2] = []
	for s: Vector2 in out:
		if s.y - s.x >= 0.4:
			kept.append(s)
	return kept


## A shrub: ONE species a chunk (LotFill's pick - the forecourt planters' - so a chunk with both
## has one batch), within the chunk's count and triangle budget.
static func _shrub(ch: CityChunk, at: Vector2, rng: RandomNumberGenerator, size: float) -> void:
	var pick := _shrub_pick(ch)
	var mesh := PropFactory.model_bush(pick)
	var tris := CityChunk._mesh_tris(mesh)
	if ch._yard_shrubs >= MAX_SHRUBS or (ch._yard_shrubs + 1) * tris > SHRUB_TRIS:
		return
	ch._yard_shrubs += 1
	var sc := size * rng.randf_range(0.8, 1.2)
	var basis := Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3(sc, sc * rng.randf_range(0.85, 1.15), sc))
	var tint := Color(rng.randf_range(0.85, 1.1), rng.randf_range(0.9, 1.1), rng.randf_range(0.85, 1.0))
	if LaTrees.accent_shrub(ch, Vector3(at.x, CityChunk.SIDEWALK_TOP + LIFT, at.y), LaTrees.SHRUB_ACCENT):
		return
	ch._batch.add("bush_%d" % pick, mesh, Transform3D(basis, Vector3(at.x, CityChunk.SIDEWALK_TOP + LIFT, at.y)), tint)


## Which of PropFactory.BUSHES a chunk's yards plant: where LotFill runs too, its pick (one batch for
## both); elsewhere one of the two cheap ones (bush_b 8k, sorrel 3k triangles - bush_c is 27k, and a
## batch draws every instance at the LOD of its nearest one).
static func _shrub_pick(ch: CityChunk) -> int:
	if int(ch.plan.block(ch.ix, ch.iz).district) in LotFill.DISTRICTS:
		return absi(hash([ch.plan.seed, ch.ix, ch.iz, "fill_shrub"])) % PropFactory.BUSHES.size()
	return CHEAP_BUSHES[absi(hash([ch.plan.seed, ch.ix, ch.iz, "yard_shrub"])) % CHEAP_BUSHES.size()]


## A tree: the block's own street tree (LotFill._tree), within the chunk's budget, never under the deck.
static func _tree(ch: CityChunk, at: Vector2, rng: RandomNumberGenerator) -> void:
	if ch._yard_trees >= MAX_TREES or ch._under_freeway(at, CityChunk.TREE_FREEWAY_MARGIN):
		return
	ch._yard_trees += 1
	LotFill._tree(ch, Vector3(at.x, CityChunk.SIDEWALK_TOP + LIFT, at.y), rng)


## A palm: one variant a chunk, within the budget, never under the deck.
static func _palm(ch: CityChunk, at: Vector2, rng: RandomNumberGenerator) -> void:
	if ch._yard_palms >= MAX_PALMS or ch._under_freeway(at, CityChunk.PALM_FREEWAY_MARGIN + 3.0):
		return
	ch._yard_palms += 1
	var v := absi(hash([ch.plan.seed, ch.ix, ch.iz, "yard_palm"])) % PropFactory.PALM_VARIANTS
	var s := rng.randf_range(0.7, 1.05)
	var tint := Color(rng.randf_range(0.88, 1.12), rng.randf_range(0.9, 1.1), rng.randf_range(0.85, 1.08))
	ch._batch.add("palm_%d" % v, PropFactory.palm(v), Transform3D(Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3(s, s, s)), Vector3(at.x, CityChunk.SIDEWALK_TOP + LIFT, at.y)), tint)


## A flowering ground-cover plant: one species a chunk, within the chunk's triangle budget.
static func _flower(ch: CityChunk, at: Vector2, rng: RandomNumberGenerator) -> void:
	var pick := absi(hash([ch.plan.seed, ch.ix, ch.iz, "yard_flower"])) % 4
	var mesh := PropFactory.model_flower(pick)
	var tris := CityChunk._mesh_tris(mesh)
	if (ch._yard_flowers + 1) * tris > FLOWER_TRIS:
		return
	ch._yard_flowers += 1
	var sc := rng.randf_range(0.7, 1.3)
	var key := "flower_%d" % pick
	ch._batch.add(key, mesh, Transform3D(Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3(sc, sc, sc)), Vector3(at.x, CityChunk.SIDEWALK_TOP + LIFT, at.y)),
		Color(rng.randf_range(0.88, 1.12), rng.randf_range(0.9, 1.1), rng.randf_range(0.88, 1.1)))
	ch._batch.set_draw_distance(key, FLOWER_DISTANCE)
	ch._batch.set_no_shadow(key)


# --- The meshes ------------------------------------------------------------------------------------------

static var _yard_material: ShaderMaterial = null
static var _walls_material: ShaderMaterial = null


static func yard_material() -> ShaderMaterial:
	if _yard_material != null:
		return _yard_material
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/lot_yard.gdshader")
	mat.set_shader_parameter("grass_tex", PropFactory.texture("grass", "Color"))
	mat.set_shader_parameter("concrete_tex", PropFactory.texture("concrete", "Color"))
	mat.set_shader_parameter("concrete_nrm", PropFactory.texture("concrete", "NormalGL"))
	mat.set_shader_parameter("dirt_tex", PropFactory.texture("hill_dirt", "Color"))
	mat.set_shader_parameter("brick_tex", PropFactory.texture("brick", "Color"))
	mat.set_shader_parameter("brick_nrm", PropFactory.texture("brick", "NormalGL"))
	mat.set_shader_parameter("planks_tex", PropFactory.texture("planks", "Color"))
	_yard_material = mat
	return mat


static func walls_material() -> ShaderMaterial:
	if _walls_material != null:
		return _walls_material
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/lot_walls.gdshader")
	mat.set_shader_parameter("plaster_tex", PropFactory.texture("plaster_white", "Color"))
	mat.set_shader_parameter("planks_tex", PropFactory.texture("planks", "Color"))
	mat.set_shader_parameter("concrete_tex", PropFactory.texture("concrete", "Color"))
	mat.set_shader_parameter("grass_tex", PropFactory.texture("grass", "Color"))
	mat.set_shader_parameter("brick_tex", PropFactory.texture("brick", "Color"))
	_walls_material = mat
	return mat


## The FULL chunk's yards as two meshes: the ground (every rect, walk and box, relief-following, no
## shadow) and everything upright (casting). A draw call each, whatever is in them.
static func commit(ch: CityChunk) -> void:
	if not (ch._yard_ground.is_empty() and ch._yard_strips.is_empty() and ch._yard_boxes.is_empty() and ch._yard_ivy.is_empty()):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for g: Array in ch._yard_ground:
			_grid(st, ch, g[0], CityChunk.SIDEWALK_TOP + float(g[3]), int(g[1]), float(g[2]), null)
		var fw: Freeway = ch.plan.macro.freeway if ch.plan.macro else null
		for r: Rect2 in ch._yard_ivy:
			var segs: Array = fw.segments_in(r.grow(30.0)) if fw else []
			_grid(st, ch, r, CityChunk.SIDEWALK_TOP + LIFT, G_IVY, 0.0, segs)
		for s: Array in ch._yard_strips:
			_ribbon(st, ch, s[0], s[1], s[2], CityChunk.SIDEWALK_TOP + PATH_LIFT + 0.01, int(s[3]), float(s[4]))
		for b: Array in ch._yard_boxes:
			_ground_box_tris(st, b[0], b[1], int(b[2]))
		var mi := MeshInstance3D.new()
		mi.name = "YardGround"
		mi.mesh = st.commit()
		mi.material_override = yard_material()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ch.add_child(mi)
	if not ch._yard_walls.is_empty():
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for w: Array in ch._yard_walls:
			_wall_tris(st, w[0], w[1], int(w[2]), w[3], float(w[4]))
		var mi := MeshInstance3D.new()
		mi.name = "YardWalls"
		mi.mesh = st.commit()
		mi.material_override = walls_material()
		ch.add_child(mi)
	ch._yard_ground.clear()
	ch._yard_strips.clear()
	ch._yard_boxes.clear()
	ch._yard_ivy.clear()
	ch._yard_walls.clear()


static func _vert(st: SurfaceTool, v: Vector3, n: Vector3, c: Color) -> void:
	st.set_normal(n)
	st.set_color(c)
	st.add_vertex(v)


## A ground rect at `top` (over the relief), one quad where the relief under it is a plane and a
## grid where it bends, with a skirt round it. `segs` (the ivy): per-vertex bareness from the deck.
static func _grid(st: SurfaceTool, ch: CityChunk, r: Rect2, top: float, kind: int, variant: float, segs: Variant) -> void:
	var nx := 1
	var nz := 1
	var step := 3.0 if segs != null else (ch.ground_grid_step if CityChunk._detail() >= 1.0 else ch.ground_grid_step * 2.0)
	if segs != null or not LotFill._planar(ch, r):
		nx = clampi(ceili(r.size.x / step), 1, 48)
		nz = clampi(ceili(r.size.y / step), 1, 48)
	var pts := PackedVector3Array()
	var cols := PackedColorArray()
	pts.resize((nx + 1) * (nz + 1))
	cols.resize((nx + 1) * (nz + 1))
	for j in nz + 1:
		for i in nx + 1:
			var x := r.position.x + r.size.x * i / nx
			var z := r.position.y + r.size.y * j / nz
			pts[j * (nx + 1) + i] = Vector3(x, top + ch._gy(x, z), z)
			var g := variant
			if segs != null:
				g = _bareness(segs as Array, Vector2(x, z))
			cols[j * (nx + 1) + i] = Color(float(kind) / 16.0, g, 0.0, 1.0)
	for j in nz:
		for i in nx:
			var k00 := j * (nx + 1) + i
			var k10 := k00 + 1
			var k01 := k00 + nx + 1
			var k11 := k01 + 1
			for k: int in [k00, k10, k01, k10, k11, k01]:
				_vert(st, pts[k], Vector3.UP, cols[k])
	# The skirt, facing out, down past the pavement.
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
	var c := Vector3(r.get_center().x, 0.0, r.get_center().y)
	for k in ring.size():
		var p0 := pts[ring[k]]
		var p1 := pts[ring[(k + 1) % ring.size()]]
		var mid := (p0 + p1) * 0.5
		var out := Vector3(mid.x - c.x, 0.0, mid.z - c.z)
		var e := p1 - p0
		var n := Vector3(e.z, 0.0, -e.x).normalized()
		if n.dot(out) < 0.0:
			n = -n
		var col := cols[ring[k]]
		# Wound to face out: the winding the top uses (counter-clockwise from above).
		var a0 := p0
		var a1 := p1
		if Vector3(e.z, 0.0, -e.x).dot(out) > 0.0:
			a0 = p1
			a1 = p0
		_vert(st, a0, n, col)
		_vert(st, a1, n, col)
		_vert(st, a1 - down, n, col)
		_vert(st, a0, n, col)
		_vert(st, a1 - down, n, col)
		_vert(st, a0 - down, n, col)


## How bare the ground at `p` is under the deck (0 open ivy .. 1 the deck's shade), from the deck
## edge's distance.
static func _bareness(segs: Array, p: Vector2) -> float:
	var best := INF
	for s in segs:
		var d := (Geometry2D.get_closest_point_to_segment(p, s.a, s.b) - p).length() - float(s.width) * 0.5
		best = minf(best, d)
	return 1.0 - smoothstep(BARE_FADE.x, BARE_FADE.y, best)


## A walk from a to b, `width` wide, over the relief every few metres.
static func _ribbon(st: SurfaceTool, ch: CityChunk, a: Vector2, b: Vector2, width: float, top: float, kind: int, variant: float) -> void:
	var len := a.distance_to(b)
	if len < 0.5:
		return
	var dir := (b - a) / len
	var side := Vector2(-dir.y, dir.x) * width * 0.5
	var n := maxi(1, ceili(len / 4.0))
	var col := Color(float(kind) / 16.0, variant, 0.0, 1.0)
	for i in n:
		var p0 := a.lerp(b, float(i) / float(n))
		var p1 := a.lerp(b, float(i + 1) / float(n))
		var l0 := p0 + side
		var r0 := p0 - side
		var l1 := p1 + side
		var r1 := p1 - side
		var vl0 := Vector3(l0.x, top + ch._gy(l0.x, l0.y), l0.y)
		var vr0 := Vector3(r0.x, top + ch._gy(r0.x, r0.y), r0.y)
		var vl1 := Vector3(l1.x, top + ch._gy(l1.x, l1.y), l1.y)
		var vr1 := Vector3(r1.x, top + ch._gy(r1.x, r1.y), r1.y)
		# Facing up whichever way the walk runs: a Godot front face's right-hand normal points away
		# from the viewer, so down here.
		var tri := [vl0, vr0, vl1, vr0, vr1, vl1]
		if (vr0 - vl0).cross(vl1 - vl0).y > 0.0:
			tri = [vl0, vl1, vr0, vr0, vl1, vr1]
		for v: Vector3 in tri:
			_vert(st, v, Vector3.UP, col)


## A box in the ground mesh (a fountain's water), its five visible faces.
static func _ground_box_tris(st: SurfaceTool, size: Vector3, at: Vector3, kind: int) -> void:
	var col := Color(float(kind) / 16.0, 0.0, 0.0, 1.0)
	var unit := CityChunk.unit_box_arrays()
	var uv: PackedVector3Array = unit[0]
	var un: PackedVector3Array = unit[1]
	var ui: PackedInt32Array = unit[4]
	for i: int in ui:
		_vert(st, uv[i] * size + at, un[i], col)


## An upright box into the walls mesh: its faces (no bottom) with UV in metres in the face's own
## frame - x along the face (world-continuous, so a run of boxes reads as one wall), y up from the
## box's foot - and UV2.x the height its courses and rails are laid out on.
static func _wall_tris(st: SurfaceTool, size: Vector3, c: Vector3, kind: int, paint: Color, h: float) -> void:
	# The paint as written (sRGB) on both renderers: vertex colours arrive raw on both, and the
	# shader works in display numbers (lot_walls.gdshader, disp() / to_lit()).
	var col := paint
	col.a = float(kind) / 16.0
	var lo := c - size * 0.5
	var hi := c + size * 0.5
	var foot := hi.y - h
	# faces: normal, then four corners counter-clockwise seen from outside (Godot's front faces are
	# clockwise to the viewer, so each quad is laid 0-2-1, 0-3-2).
	var faces := [
		[Vector3(1, 0, 0), [Vector3(hi.x, lo.y, hi.z), Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(hi.x, hi.y, hi.z)]],
		[Vector3(-1, 0, 0), [Vector3(lo.x, lo.y, lo.z), Vector3(lo.x, lo.y, hi.z), Vector3(lo.x, hi.y, hi.z), Vector3(lo.x, hi.y, lo.z)]],
		[Vector3(0, 0, 1), [Vector3(lo.x, lo.y, hi.z), Vector3(hi.x, lo.y, hi.z), Vector3(hi.x, hi.y, hi.z), Vector3(lo.x, hi.y, hi.z)]],
		[Vector3(0, 0, -1), [Vector3(hi.x, lo.y, lo.z), Vector3(lo.x, lo.y, lo.z), Vector3(lo.x, hi.y, lo.z), Vector3(hi.x, hi.y, lo.z)]],
		[Vector3(0, 1, 0), [Vector3(lo.x, hi.y, hi.z), Vector3(hi.x, hi.y, hi.z), Vector3(hi.x, hi.y, lo.z), Vector3(lo.x, hi.y, lo.z)]],
	]
	for fc: Array in faces:
		var n: Vector3 = fc[0]
		var q: Array = fc[1]
		var uvs: Array[Vector2] = []
		for p: Vector3 in q:
			var u: float
			if absf(n.x) > 0.5:
				u = p.z
			elif absf(n.z) > 0.5:
				u = p.x
			else:
				u = p.x
			var v: float = p.y - foot if n.y < 0.5 else p.z
			uvs.append(Vector2(u, v))
		for k: int in [0, 2, 1, 0, 3, 2]:
			st.set_normal(n)
			st.set_color(col)
			st.set_uv(uvs[k])
			st.set_uv2(Vector2(h, 0.0))
			st.add_vertex(q[k])
