class_name CarPark
extends RefCounted
## Multi-storey car parks you can drive up (2026-10-05, fleet task "garage-drive-in"): open-deck
## precast parking structures downtown and in midtown, three to six decks and a roof, on a site
## of a few lot cells along one street. A car goes in past the entry barrier, round the ground
## deck, up a straight ramp in the RAMP STRIP to the next deck, along that deck's aisle back to
## the ramp's foot and up again, to the roof; it comes down the same two-way ramps and leaves past
## the exit barrier beside the entry. Every deck, ramp, wall, column and parked car collides.
##
## WHERE is worked out, never placed (FireStation's and PoliceStation's way): the city is cut
## into CELL squares; a hash of seed + cell says whether one has a car park and tries up to TRIES
## hashed points in it; the first DOWNTOWN (off the tower core) or MIDTOWN block of plain
## buildings no other feature has claimed gives a SITE - a centred run of its lot cells along one
## street (SITE_TARGET), every one of its lots present and unclaimed, on near-level ground, clear
## of the freeways. CityChunk._build_lot() asks claims() AFTER every other claim (the pad roll is
## made either way, so no other lot moves) and the first of the site's lots builds it.
##
## THE PLAN (layout(), pure; the site's street frame: u along the street, v in from it, both
## from the site's street corner): a stair-and-lift CORE at the low-u end, then END ZONE E0
## (the entry and exit lanes at the ground, a cross aisle on every deck), the middle, END ZONE E1.
## Across v: a parking MODULE (a stall row, a two-way aisle, a stall row) against the street, the
## RAMP STRIP behind it (walled, a straight ramp from u_r0 to u_r1 on every level, stacked one
## storey apart), and on a deep site a second module behind that. A car on deck k reaches the
## ramp to k + 1 at E0 (it rises toward +u) and arrives on k + 1 at u_r1, drives on to E1, turns
## into an aisle, back to E0 and up again: the classic loop of a straight-ramp structure.
## Names are invented (OPERATORS), never a real parking company.

const CELL := 640.0
const ODDS := 0.9
const TRIES := 6
const DISTRICTS := [CityPlan.District.DOWNTOWN, CityPlan.District.MIDTOWN]
## Downtown's tower core keeps its towers (skyline boost over this).
const MAX_BOOST := 0.55
## Site: frontage x depth (m) aimed for, at least, at most.
const SITE_TARGET := Vector2(60.0, 46.0)
const SITE_MIN := Vector2(51.0, 26.5)
const SITE_MAX := Vector2(92.0, 76.0)
## Ground within this of level over the site (m).
const MAX_RELIEF := 0.9

## The structure (m).
const STALL_W := 2.7
const STALL_D := 5.2
const AISLE := 6.8
const WALL := 0.25
const STRIP := 7.0
const MODULE := STALL_D * 2.0 + AISLE
const CORE := 5.0
const END := 9.0
const RAMP_LEN := 24.0
## The ramp's vertical curves at each end (m along it; the grade is half the ramp's there).
const RAMP_EASE := 3.5
## Floor to floor, slab, the downstand beams (clear height under a beam: FLOOR - SLAB - BEAM).
const FLOOR := 3.05
const SLAB := 0.24
const BEAM := 0.42
const PARAPET := 1.07
## Setback from the site's street edge to the structure's face (a planting strip).
const SETBACK := 0.9
## The entry and exit lanes at the ground: the island between them (u from E0's start).
const ISLAND_U := 3.55
const ISLAND_W := 0.6
## Barrier arms: where they stand (v in from the structure's face) and how long they are.
const ARM_V := 3.4
const ARM_LEN := 3.3
## The entry's clearance (the bar across it) and the sign on it.
const CLEARANCE := 2.13
## Parked cars: share of the deck stalls and the roof's that are taken.
const FILL := 0.68
const ROOF_FILL := 0.4
const OPERATORS := ["CIVIC PARK", "MERIDIAN PARKING", "SIXTH STREET GARAGE", "PARK & GO", "HARBOR SQUARE PARKING",
	"GRAND DECK", "TEMPLE GARAGE", "FIGTREE PARKING", "ORCHID PARK", "CENTRE STREET DECK"]

## Off (CAR_PARKS=0 in the environment): no car parks anywhere, every lot keeps what it had.
static var enabled: bool = OS.get_environment("CAR_PARKS") != "0"
static var _cache: Dictionary = {}


static func _h01(parts: Array) -> float:
	return float(absi(hash(parts)) % 100003) / 100003.0


static func _cell_of(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / CELL), floori(p.y / CELL))


# --- Where ---------------------------------------------------------------------------------------

## The car park of grid cell `cell`: {} or {"cell", "block", "site" (Rect2, true world), "side",
## "frame" (Industrial.frame of the site), "road" [axis, index], "lots" (seeds), "builder" (the
## seed of the lot that builds it), "layout" (layout()), "front" (true world XZ: the road's centre
## line level with the entry), "name", "seed"}. Cached per plan and cell.
static func for_cell(plan: CityPlan, cell: Vector2i) -> Dictionary:
	var key := Vector3i(plan.seed, cell.x, cell.y)
	if _cache.has(key):
		return _cache[key]
	var out := {}
	_cache[key] = out
	if not enabled or plan.macro == null:
		return out
	if _h01([plan.seed, cell.x, cell.y, "car_park"]) > ODDS:
		return out
	for t in TRIES:
		var target := Vector2((float(cell.x) + lerpf(0.1, 0.9, _h01([plan.seed, cell.x, cell.y, t, "cp_x"]))) * CELL,
				(float(cell.y) + lerpf(0.1, 0.9, _h01([plan.seed, cell.x, cell.y, t, "cp_z"]))) * CELL)
		if plan.zone_at(target) != MacroMap.Zone.CITY:
			continue
		var bi := plan.block_index_at(target)
		var b := plan.block(bi.x, bi.y)
		var rect: Rect2 = b.rect
		if _cell_of(rect.get_center()) != cell:
			continue
		if not _block_ok(plan, bi, b):
			continue
		var s := _site(plan, bi, [plan.seed, cell.x, cell.y, t])
		if s.is_empty():
			continue
		s.cell = cell
		s.seed = absi(hash([plan.seed, cell.x, cell.y, "cp_seed"]))
		s.name = String(OPERATORS[int(s.seed) % OPERATORS.size()])
		out.merge(s)
		return out
	return out


## A block a car park may stand on: plain buildings in its districts, off the tower core, and no
## other feature's (a site, grounds, a hospital, a landmark, the river, a station, an alley, a
## tower going up).
static func _block_ok(plan: CityPlan, bi: Vector2i, b: Dictionary) -> bool:
	if not DISTRICTS.has(int(b.district)) or int(b.kind) != CityPlan.BlockKind.BUILDINGS:
		return false
	if b.has("site") or b.has("grounds") or b.has("hospital") or b.has("was_plaza"):
		return false
	var rect: Rect2 = b.rect
	if plan.macro.skyline_boost(rect.get_center()) > MAX_BOOST:
		return false
	if Landmarks.claims(rect) or plan.river_block(bi.x, bi.y):
		return false
	if plan.macro.runway_clear_zone().intersects(rect):
		return false
	if not PoliceStation.station_on(plan, bi.x, bi.y).is_empty():
		return false
	var fs := FireStation.for_cell(plan, FireStation._cell_of(rect.get_center()))
	if not fs.is_empty() and fs.block == bi:
		return false
	if not Alleys.spec(plan, bi.x, bi.y).is_empty():
		return false
	if not Construction.tower_site(plan, bi.x, bi.y).is_empty():
		return false
	return true


## True when some feature that _build_lot() asks before the car park takes `lot`.
static func _taken(plan: CityPlan, bi: Vector2i, lot: Dictionary, district: int) -> bool:
	if lot.yard or lot.get("parking", false) or YardFill.is_corridor(plan, lot):
		return true
	if FireStation.claims(plan, bi.x, bi.y, lot) or PoliceStation.claims(plan, bi.x, bi.y, lot):
		return true
	if Worship.claims(plan, bi.x, bi.y, lot) or Broadway.claims(plan, bi.x, bi.y, lot) or Chinatown.claims(plan, bi.x, bi.y, lot):
		return true
	if CarDealers.claims(plan, bi.x, bi.y, lot) or CivicBuildings.claims(plan, bi.x, bi.y, lot):
		return true
	if not OilField.lot_well(plan, lot, district).is_empty():
		return true
	return false


## A site on block `bi` (see for_cell()), or {}.
static func _site(plan: CityPlan, bi: Vector2i, salt: Array) -> Dictionary:
	var b := plan.block(bi.x, bi.y)
	var lots := plan.lots(bi.x, bi.y)
	if lots.is_empty():
		return {}
	var inner := (b.rect as Rect2).grow(-plan.sidewalk_width)
	var cs: Vector2 = (lots[0].cell as Rect2).size
	var nx := maxi(1, roundi(inner.size.x / cs.x))
	var nz := maxi(1, roundi(inner.size.y / cs.y))
	var roads := [[CityPlan.AXIS_Z, bi.y], [CityPlan.AXIS_Z, bi.y + 1], [CityPlan.AXIS_X, bi.x], [CityPlan.AXIS_X, bi.x + 1]]
	var k0 := absi(hash(salt + ["cp_side"])) % 4
	for o in 4:
		var side := (k0 + o) % 4
		var along_n := nx if side < 2 else nz
		var depth_n := nz if side < 2 else nx
		var ca := cs.x if side < 2 else cs.y
		var cd := cs.y if side < 2 else cs.x
		var ku := clampi(ceili(SITE_TARGET.x / ca - 0.15), 1, along_n)
		var kv := clampi(ceili(SITE_TARGET.y / cd - 0.15), 1, depth_n)
		var L := float(ku) * ca
		var D := float(kv) * cd
		if L < SITE_MIN.x or D < SITE_MIN.y or L > SITE_MAX.x or D > SITE_MAX.y:
			continue
		var i0 := (along_n - ku) / 2
		var site: Rect2
		match side:
			0:
				site = Rect2(inner.position + Vector2(float(i0) * cs.x, 0.0), Vector2(L, D))
			1:
				site = Rect2(Vector2(inner.position.x + float(i0) * cs.x, inner.end.y - D), Vector2(L, D))
			2:
				site = Rect2(inner.position + Vector2(0.0, float(i0) * cs.y), Vector2(D, L))
			_:
				site = Rect2(Vector2(inner.end.x - D, inner.position.y + float(i0) * cs.y), Vector2(D, L))
		var mine: Array[int] = []
		var builder := -1
		var bad := false
		for lot: Dictionary in lots:
			if not site.grow(-0.5).has_point(lot.center):
				continue
			if _taken(plan, bi, lot, int(b.district)):
				bad = true
				break
			mine.append(int(lot.seed))
			if builder == -1:
				builder = int(lot.seed)
		if bad or mine.size() != ku * kv:
			continue
		if plan.macro.freeway and plan.macro.freeway.blocks_rect(site.grow(4.0), 3.0):
			continue
		var lo := INF
		var hi := -INF
		for q: Vector2 in [site.position, site.end, Vector2(site.position.x, site.end.y), Vector2(site.end.x, site.position.y), site.get_center()]:
			var r := plan.macro.relief_at(q)
			lo = minf(lo, r)
			hi = maxf(hi, r)
		if hi - lo > MAX_RELIEF:
			continue
		var road: Array = roads[side]
		var f := Industrial.frame(site, side)
		var decks := _decks(plan, site, salt)
		var lay := layout(L, D, decks)
		if lay.is_empty():
			continue
		var entry_u: float = lay.entry_u
		var edge := Industrial.fp(f, entry_u, 0.0)
		var road_pos := plan.road_pos(int(road[0]), int(road[1]))
		var along := edge.y if int(road[0]) == CityPlan.AXIS_X else edge.x
		if not plan.road_open(int(road[0]), int(road[1]), along):
			continue
		var front := Vector2(road_pos, edge.y) if int(road[0]) == CityPlan.AXIS_X else Vector2(edge.x, road_pos)
		return {"block": bi, "site": site, "side": side, "frame": f, "road": road, "lots": mine,
			"builder": builder, "front": front, "layout": lay, "relief": [lo, hi]}
	return {}


## How many decks over the ground (the roof is the top one): taller downtown.
static func _decks(plan: CityPlan, site: Rect2, salt: Array) -> int:
	var dt := plan.district_at(site.get_center()) == CityPlan.District.DOWNTOWN
	var r := _h01(salt + ["cp_decks"])
	return (3 + int(r * 3.99)) if dt else (2 + int(r * 2.99))


## The plan of a site L x D (m, frame) with `decks` decks over the ground (deck `decks` is the
## roof). Pure. {} when the site cannot take one. Everything in frame metres; see the header.
static func layout(L: float, D: float, decks: int) -> Dictionary:
	var modules := 2 if D - SETBACK - 0.6 >= WALL * 3.0 + MODULE * 2.0 + STRIP else 1
	var ds := WALL + MODULE + WALL + STRIP + WALL + (MODULE + WALL if modules == 2 else 0.0)
	var ls := minf(L - 1.0, CORE + END * 2.0 + 66.0)
	if ls < CORE + END * 2.0 + RAMP_LEN + 3.0 or D - SETBACK < ds + 0.3:
		return {}
	var u0 := (L - ls) * 0.5
	var v0 := SETBACK
	# u marks (structure-relative: add u0 for frame u).
	var e0 := CORE
	var m0 := CORE + END
	var m1 := ls - END
	var r0 := m0
	var r1 := m0 + RAMP_LEN
	# v bands (structure-relative: add v0 for frame v): [v_from, v_to, kind, back] - kind 0 drive,
	# 1 stall row (its back wall at `back`).
	var bands: Array = []
	var v := WALL
	bands.append([v, v + STALL_D, 1, v])
	bands.append([v + STALL_D, v + STALL_D + AISLE, 0, 0.0])
	bands.append([v + STALL_D + AISLE, v + MODULE, 1, v + MODULE])
	var s0 := WALL + MODULE + WALL
	var s1 := s0 + STRIP
	if modules == 2:
		var c := s1 + WALL
		bands.append([c, c + STALL_D, 1, c])
		bands.append([c + STALL_D, c + STALL_D + AISLE, 0, 0.0])
		bands.append([c + STALL_D + AISLE, c + MODULE, 1, c + MODULE])
	# Stalls along the middle: as many as fit, centred.
	var n := int((m1 - m0) / STALL_W)
	var st0 := m0 + ((m1 - m0) - float(n) * STALL_W) * 0.5
	# Column lines along u: the core's face, E0's end, every third stall line, E1's start, the end.
	var cols: Array[float] = [e0, m0]
	var k := 3
	while k < n:
		var cu := st0 + float(k) * STALL_W
		if cu - cols[cols.size() - 1] > 4.0 and m1 - cu > 4.0:
			cols.append(cu)
		k += 3
	cols.append(m1)
	cols.append(ls)
	# Column lines across v: the face, both strip walls, the back.
	# (The strip's columns stand flush with its walls' faces, clear of the lane; the back ones
	# flush with the back.)
	var col_v: Array[float] = [WALL * 0.5, s0 - 0.27, s1 + 0.27]
	if modules == 2:
		col_v.append(ds - 0.27)
	# The ramp's grade (its middle; half that over the eases at the ends).
	var grade := FLOOR / (RAMP_LEN - RAMP_EASE)
	return {"L": L, "D": D, "ls": ls, "ds": ds, "u0": u0, "v0": v0, "decks": decks, "modules": modules,
		"e0": e0, "m0": m0, "m1": m1, "r0": r0, "r1": r1, "s0": s0, "s1": s1, "bands": bands,
		"stalls": n, "st0": st0, "cols": cols, "col_v": col_v, "grade": grade,
		"entry_u": u0 + e0 + ISLAND_U + ISLAND_W + (END - ISLAND_U - ISLAND_W) * 0.5, "exit_u": u0 + e0 + ISLAND_U * 0.5,
		"height": FLOOR * float(decks) + PARAPET}


## The height of ramp k -> k + 1's surface over deck k at `x` metres along it (0 at u_r0). A
## vertical curve RAMP_EASE long at each end, straight between: the grade never steps.
static func ramp_rise(x: float) -> float:
	var g := FLOOR / (RAMP_LEN - RAMP_EASE)
	var e := RAMP_EASE
	x = clampf(x, 0.0, RAMP_LEN)
	if x < e:
		return g * x * x / (2.0 * e)
	if x > RAMP_LEN - e:
		var y := RAMP_LEN - x
		return FLOOR - g * y * y / (2.0 * e)
	return g * e * 0.5 + g * (x - e)


## The car park on block (bx, bz), or {}.
static func on_block(plan: CityPlan, bx: int, bz: int) -> Dictionary:
	if not enabled or plan.macro == null:
		return {}
	var b := plan.block(bx, bz)
	var s := for_cell(plan, _cell_of((b.rect as Rect2).get_center()))
	if s.is_empty() or s.block != Vector2i(bx, bz):
		return {}
	return s


## True when `lot` of block (bx, bz) is a car park's (CityChunk._build_lot asks, after its rolls
## and every other claim).
static func claims(plan: CityPlan, bx: int, bz: int, lot: Dictionary) -> bool:
	var s := on_block(plan, bx, bz)
	return not s.is_empty() and (s.lots as Array).has(int(lot.seed))


## The nearest car park to `p` (true world XZ) within `reach`, or {}.
static func nearest(plan: CityPlan, p: Vector2, reach: float) -> Dictionary:
	if plan == null or not enabled or plan.macro == null:
		return {}
	var c := _cell_of(p)
	var best: Dictionary = {}
	var best_d := reach
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var s := for_cell(plan, c + Vector2i(dx, dz))
			if s.is_empty():
				continue
			var d := (s.site as Rect2).get_center().distance_to(p) - (s.site as Rect2).size.length() * 0.5
			if d < best_d:
				best_d = d
				best = s
	return best


## A point of a car park's frame (u, v: frame metres) in true world XZ.
static func world_xz(s: Dictionary, u: float, v: float) -> Vector2:
	return Industrial.fp(s.frame, u, v)


## True when `p` (true world XZ) is on the kerb in front of a car park's entry and exit, which no
## parked car may block (CityChunk._park_car asks, after its rolls).
static func keeps_clear(plan: CityPlan, p: Vector2) -> bool:
	var s := nearest(plan, p, 40.0)
	if s.is_empty():
		return false
	var lay: Dictionary = s.layout
	var mid: float = float(lay.u0) + float(lay.e0) + END * 0.5
	var d := p - world_xz(s, mid, 0.0)
	var f: Dictionary = s.frame
	var along := d.dot(f.a)
	var lat := -d.dot(f.n)
	var w := plan.road_width(int(s.road[0]), int(s.road[1]))
	return absf(along) < END * 0.5 + 5.5 and lat > -1.0 and lat < plan.sidewalk_width + w * 0.5 + 0.5


## Points (true world XZ) and radii that pavement clutter (camps, scooters) keeps clear of: the
## driveway across the pavement to the entry, flares and all.
static func keep_clear_points(plan: CityPlan, bx: int, bz: int) -> Array:
	var s := on_block(plan, bx, bz)
	if s.is_empty():
		return []
	var lay: Dictionary = s.layout
	var mid: float = float(lay.u0) + float(lay.e0) + END * 0.5
	var out: Array = []
	for du: float in [-6.0, -2.0, 2.0, 6.0]:
		out.append([world_xz(s, mid + du, -plan.sidewalk_width * 0.5), 4.5])
	return out


## The way a car drives up: true world points (x, height over the structure's ground deck, z)
## from the road in front of the entry, in past the barrier, round each deck and up each ramp to
## the roof. `to_deck` stops on that deck. For the checks and the stills' autopilot.
static func drive_path(plan: CityPlan, s: Dictionary, to_deck: int = -1) -> PackedVector3Array:
	var lay: Dictionary = s.layout
	var decks := int(lay.decks) if to_deck < 0 else mini(to_deck, int(lay.decks))
	var u0: float = lay.u0
	var v0: float = lay.v0
	var w := plan.road_width(int(s.road[0]), int(s.road[1]))
	var out := PackedVector3Array()
	var P := func(u: float, y: float, v: float) -> void:
		var q := world_xz(s, u0 + u, v0 + v)
		out.append(Vector3(q.x, y, q.y))
	var lane_in: float = float(lay.entry_u) - u0
	var strip_c := (float(lay.s0) + float(lay.s1)) * 0.5
	var aisle_c := WALL + STALL_D + AISLE * 0.5
	var r0: float = lay.r0
	var r1: float = lay.r1
	var m1: float = lay.m1
	# Arcs as points every 30 degrees (u = cu + R cos a, v = cv + R sin a), degrees a0 to a1.
	var arc := func(cu: float, cv: float, R: float, a0: float, a1: float, y: float) -> void:
		var n := maxi(2, int(absf(a1 - a0) / 30.0))
		for j in range(1, n + 1):
			var a := deg_to_rad(lerpf(a0, a1, float(j) / float(n)))
			P.call(cu + R * cos(a), y, cv + R * sin(a))
	# On the road in front, the kerb lane, a little up the street, then the turn in.
	P.call(lane_in - 30.0, 0.0, -v0 - plan.sidewalk_width - w * 0.25)
	P.call(lane_in - 12.0, 0.0, -v0 - plan.sidewalk_width - w * 0.25)
	P.call(lane_in - 2.5, 0.0, -v0 - plan.sidewalk_width - 0.3)
	P.call(lane_in, 0.0, -v0 + 0.2)
	P.call(lane_in, 0.0, 1.0)
	P.call(lane_in, 0.0, ARM_V + 3.0)
	# Over to the end zone's far side, then a right-hand sweep onto the ramp's foot.
	var R := 5.4
	var sx := r0 + 0.6 - R
	P.call(lerpf(lane_in, sx, 0.6), 0.0, ARM_V + 7.5)
	P.call(sx, 0.0, strip_c - R)
	arc.call(sx + R, strip_c - R, R, 180.0, 90.0, 0.0)
	var cv := (strip_c + aisle_c) * 0.5
	var RU := (strip_c - aisle_c) * 0.5
	for k in decks:
		var y := FLOOR * float(k)
		P.call(r0 + 3.0, y + ramp_rise(3.0 - 0.6), strip_c)
		P.call(r0 + RAMP_LEN * 0.5, y + ramp_rise(RAMP_LEN * 0.5), strip_c)
		P.call(r1 + 1.5, y + FLOOR, strip_c)
		if k == decks - 1:
			P.call(r1 + 7.0, y + FLOOR, strip_c)
			break
		# On round the loop: a U-turn in E1 into the aisle, back down it, a U-turn in E0 onto the
		# next ramp.
		P.call(m1 - 1.0, y + FLOOR, strip_c)
		arc.call(m1, cv, RU, 90.0, -90.0, y + FLOOR)
		P.call((r0 + m1) * 0.5, y + FLOOR, aisle_c)
		P.call(r0, y + FLOOR, aisle_c)
		arc.call(r0, cv, RU, -90.0, -270.0, y + FLOOR)
	return out


## The structure's ground deck height (true world y) for a car park: the top of its slab.
static func ground_y(plan: CityPlan, s: Dictionary) -> float:
	var hi: float = (s.relief as Array)[1]
	return hi + CityChunk.SIDEWALK_TOP + 0.04


## Builds the car park in chunk `ch` on the site's first lot (FULL: CarParkBuild; LOD and the
## far city: boxes).
static func build_lot(ch: CityChunk, lot: Dictionary) -> void:
	var s := on_block(ch.plan, ch.ix, ch.iz)
	if s.is_empty() or int(lot.seed) != int(s.builder):
		return
	CarParkBuild.build(ch, s)
