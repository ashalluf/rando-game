class_name PoliceStation
extends RefCounted
## Police stations (2026-10-05): where the cruisers come from. A two- or three-storey civic
## building in precast concrete and glass with a lit public entrance (the department's name over a
## cantilevered canopy, a glass lobby lit all night, three flagpoles, bollards and planters in the
## forecourt, a monument sign with the division's name), and behind it a secured car park: a
## palisade and chain-link with barbed wire, a sliding gate on the driveway, rows of parked
## cruisers, a fuel island under a canopy, the sally port (a covered prisoner bay with a roll-up
## door), floodlights, CCTV, and a tall lattice radio mast with its red beacon. Plus one big
## headquarters across 1st St from City Hall (`hq()`), the same kit at eight storeys on a whole
## block - an original modernist slab, not any real building's design.
##
## Police dispatch comes out of the nearest station's gate within Police.station_reach
## (nearest() -> exit_path(): the gate slides open, the cruiser drives out through it, across the
## pavement and into the lane); recalled units drive back in (Police: a LEAVING cruiser heads for
## its station and enter_path() takes it through the gate).
##
## WHERE is worked out, never placed: the city is cut into CELL squares; a hash of seed + cell
## picks up to TRIES points in it; the first whose block is ordinary MIDTOWN buildings (or the
## edge of downtown off its tower core), not a landmark's, a fire station's, the river's or under
## a freeway, gives a SITE: a centred run of the block's lot-grid cells along one street, about
## SITE_TARGET across and deep. Every lot whose centre is in the site is the station's
## (CityChunk._build_lot asks claims() after its own rolls - the pad roll is made either way, so
## no other lot moves), and the first of them in lots() order builds it. Hashes of seed + cell +
## block only, so a chunk at any level, the far city and Police ask the same question.
##
## Names are this game's own (RANDO CITY POLICE, invented division names), never a real
## department's, division's or building's.

const CELL := 1500.0
const ODDS := 0.92
const TRIES := 6
const DISTRICTS := [CityPlan.District.MIDTOWN, CityPlan.District.DOWNTOWN]
## The site: what it aims for (frontage, depth; m) and the least it will take.
const SITE_TARGET := Vector2(56.0, 50.0)
const SITE_MIN := Vector2(42.0, 38.0)
const SITE_MAX := Vector2(96.0, 84.0)
## The most the ground may rise across a site (m): the car park is one slab.
const MAX_RELIEF := 0.9
const DEPT := "RANDO CITY POLICE"
const DIVISIONS := ["MESA", "BAYSIDE", "CANYON", "ORCHARD", "CRESTVIEW", "SAGE HILL", "ARROYO",
	"COASTLINE", "LAUREL", "IRONWOOD", "SEABREEZE", "DRY CREEK", "MARIGOLD", "SUMMIT", "BASIN",
	"CYPRESS", "JUNIPER", "WILLOW CREEK", "TERRACE", "OAK GROVE", "PRAIRIE", "MEADOWBROOK", "HILLCREST",
	"BLUE HERON"]
## Storeys: ground and upper heights (m); the HQ's count.
const GROUND_H := 4.6
const UPPER_H := 3.8
const HQ_STOREYS := 8
## The driveway beside the building, its gate, and the stalls (m).
const DRIVE_W := 8.0
const GATE_W := 7.2
const GATE_H := 2.3
const STALL_W := 2.75
const STALL_D := 5.4
const AISLE := 6.6
const FENCE_H := 2.5
## Share of stalls with a cruiser in them, and the most a station parks (each is a far-twin body
## of ~8k triangles: the car park is the station's biggest cost).
const FILL := 0.78
const MAX_CARS := 18
const HQ_MAX_CARS := 24
const MAST_H := 34.0
## How far the sally port stands out into the car park (m).
const SALLY_D := 6.0
## The gate: seconds to slide, how long it stays open.
const GATE_TIME := 2.6
const GATE_HOLD := 9.0
## Parked cruisers draw to here (m).
const CAR_RANGE := 220.0

const CONCRETE := Color(0.84, 0.83, 0.79)
const CONCRETE_DARK := Color(0.52, 0.52, 0.51)
const NAVY := Color(0.05, 0.08, 0.16)

## Off (POLICE_STATIONS=0 in the environment): no stations, the lots keep their buildings.
static var enabled: bool = OS.get_environment("POLICE_STATIONS") != "0"
static var _cache: Dictionary = {}
static var _hq_cache: Dictionary = {}
## Gates asked open (station key -> ticks msec they close), so a station built after the ask
## comes up with its gate open.
static var _open_until: Dictionary = {}
static var _mats: Dictionary = {}


static func _h01(parts: Array) -> float:
	return float(absi(hash(parts)) % 100003) / 100003.0


static func _cell_of(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / CELL), floori(p.y / CELL))


# --- Where ---------------------------------------------------------------------------------------

## The station of grid cell `cell`: {} or a station (see _site()). Cached per plan and cell.
static func for_cell(plan: CityPlan, cell: Vector2i) -> Dictionary:
	var key := Vector3i(plan.seed, cell.x, cell.y)
	if _cache.has(key):
		return _cache[key]
	var out := {}
	_cache[key] = out
	if not enabled or plan.macro == null:
		return out
	if _h01([plan.seed, cell.x, cell.y, "police_station"]) > ODDS:
		return out
	var hq_block: Vector2i = hq(plan).get("block", Vector2i(-99999, -99999))
	for t in TRIES:
		var target := Vector2((float(cell.x) + lerpf(0.15, 0.85, _h01([plan.seed, cell.x, cell.y, t, "ps_x"]))) * CELL,
				(float(cell.y) + lerpf(0.15, 0.85, _h01([plan.seed, cell.x, cell.y, t, "ps_z"]))) * CELL)
		if plan.zone_at(target) != MacroMap.Zone.CITY:
			continue
		var bi := plan.block_index_at(target)
		if bi == hq_block:
			continue
		var b := plan.block(bi.x, bi.y)
		if _cell_of((b.rect as Rect2).get_center()) != cell:
			continue
		if not DISTRICTS.has(int(b.district)) or int(b.kind) != CityPlan.BlockKind.BUILDINGS or b.has("site") or b.has("grounds"):
			continue
		if plan.macro.skyline_boost((b.rect as Rect2).get_center()) > 0.3:
			continue
		if Landmarks.claims(b.rect) or plan.river_block(bi.x, bi.y):
			continue
		# Never the fire station's block.
		var fs := FireStation.for_cell(plan, FireStation._cell_of((b.rect as Rect2).get_center()))
		if not fs.is_empty() and fs.block == bi:
			continue
		var s := _site(plan, bi, false, [plan.seed, cell.x, cell.y, t])
		if s.is_empty():
			continue
		s.cell = cell
		s.key = cell
		s.number = 1 + absi(hash([plan.seed, cell.x, cell.y, "ps_no"])) % 40
		s.name = String(DIVISIONS[absi(hash([plan.seed, cell.x, cell.y, "ps_div"])) % DIVISIONS.size()])
		s.storeys = 2 + int(_h01([plan.seed, cell.x, cell.y, "ps_storeys"]) < 0.5)
		out.merge(s)
		return out
	return out


## The headquarters: the block across 1st St (grid-south) from City Hall, the whole block, facing
## City Hall. {} when that block is not plain buildings on this seed.
static func hq(plan: CityPlan) -> Dictionary:
	if _hq_cache.has(plan.seed):
		return _hq_cache[plan.seed]
	var out := {}
	_hq_cache[plan.seed] = out
	if not enabled or plan.macro == null:
		return out
	var hall := CivicSites.anchor("ziggurat_hall")
	var bi := plan.block_index_at(hall) + Vector2i(0, 1)
	var b := plan.block(bi.x, bi.y)
	if int(b.kind) != CityPlan.BlockKind.BUILDINGS or b.has("site") or b.has("grounds") or Landmarks.claims(b.rect) or plan.river_block(bi.x, bi.y):
		return out
	var s := _site(plan, bi, true, [plan.seed, "hq"])
	if s.is_empty():
		return out
	s.cell = Vector2i(-77777, -77777)
	s.key = s.cell
	s.number = 0
	s.name = "HEADQUARTERS"
	s.storeys = HQ_STOREYS
	out.merge(s)
	return out


## A site on block `bi`: {"block", "site" (Rect2, true world), "side" (the street it fronts, as
## Industrial.frame), "frame", "road" [axis, index], "lots" (seeds), "builder" (the seed of the
## lot that builds it), "hq", "front" (true world XZ: the road's centre line level with the
## gate), "gate_u"} or {}. `whole`: the whole block (the HQ).
static func _site(plan: CityPlan, bi: Vector2i, whole: bool, salt: Array) -> Dictionary:
	var b := plan.block(bi.x, bi.y)
	var lots := plan.lots(bi.x, bi.y)
	if lots.is_empty():
		return {}
	var inner := (b.rect as Rect2).grow(-plan.sidewalk_width)
	var cs: Vector2 = (lots[0].cell as Rect2).size
	var nx := maxi(1, roundi(inner.size.x / cs.x))
	var nz := maxi(1, roundi(inner.size.y / cs.y))
	var roads := [[CityPlan.AXIS_Z, bi.y], [CityPlan.AXIS_Z, bi.y + 1], [CityPlan.AXIS_X, bi.x], [CityPlan.AXIS_X, bi.x + 1]]
	var order: Array = [0, 1, 2, 3]
	if not whole:
		var k := absi(hash(salt + ["ps_side"])) % 4
		order = [k, (k + 1) % 4, (k + 2) % 4, (k + 3) % 4]
	for side: int in order:
		var along_n := nx if side < 2 else nz
		var depth_n := nz if side < 2 else nx
		var ca := cs.x if side < 2 else cs.y
		var cd := cs.y if side < 2 else cs.x
		var ku := along_n if whole else clampi(ceili(SITE_TARGET.x / ca - 0.15), 1, along_n)
		var kv := depth_n if whole else clampi(ceili(SITE_TARGET.y / cd - 0.15), 1, depth_n)
		var L := float(ku) * ca
		var D := float(kv) * cd
		if L < SITE_MIN.x or D < SITE_MIN.y or (not whole and (L > SITE_MAX.x or D > SITE_MAX.y)):
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
		var yard := false
		for lot: Dictionary in lots:
			if site.grow(-0.5).has_point(lot.center):
				# A courtyard lot builds its garden before any claim is asked (its rolls come
				# first): a site never takes one.
				yard = yard or bool(lot.yard)
				mine.append(int(lot.seed))
				if builder == -1:
					builder = int(lot.seed)
		# A cell short (a landmark's square or the approach's clear zone dropped it): not here.
		if not whole and mine.size() != ku * kv:
			continue
		if mine.is_empty() or yard:
			continue
		if plan.macro.freeway and plan.macro.freeway.blocks_rect(site.grow(4.0), 3.0):
			continue
		# The station stands on one level: the car park is one slab.
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
		var lay := layout(L, D, whole)
		if lay.is_empty():
			continue
		var gate_u: float = lay.gate_u
		var edge := Industrial.fp(f, gate_u, 0.0)
		var road_pos := plan.road_pos(int(road[0]), int(road[1]))
		var along := edge.y if int(road[0]) == CityPlan.AXIS_X else edge.x
		if not plan.road_open(int(road[0]), int(road[1]), along):
			continue
		var front := Vector2(road_pos, edge.y) if int(road[0]) == CityPlan.AXIS_X else Vector2(edge.x, road_pos)
		return {"block": bi, "site": site, "side": side, "frame": f, "road": road, "lots": mine,
			"builder": builder, "hq": whole, "front": front, "gate_u": gate_u, "layout": lay}
	return {}


## The plan of a site L x D in its frame (u along the street, v in from it; m). Pure.
static func layout(L: float, D: float, hq_site: bool) -> Dictionary:
	var sb := 14.0 if hq_site else 6.5
	var db := 24.0 if hq_site else clampf(D * 0.36, 14.0, 19.0)
	var drive_u1 := L - 0.6
	var drive_u0 := drive_u1 - DRIVE_W
	var ub0 := 1.2
	var ub1 := minf(drive_u0 - 2.4, ub0 + (78.0 if hq_site else 46.0))
	var pv0 := sb + db + 0.6
	var pv1 := D - 0.6
	if ub1 - ub0 < 24.0 or pv1 - pv0 < STALL_D + AISLE:
		return {}
	# Stall rows down the car park: double-loaded modules (a row, the aisle, a row) from the
	# building back, a single row and its aisle in what is left. [v0, v1, face] (-1 the car's
	# nose toward the street, +1 away).
	var rows: Array = []
	var v := pv0
	while v + STALL_D * 2.0 + AISLE <= pv1 + 0.01:
		rows.append([v, v + STALL_D, -1.0])
		rows.append([v + STALL_D + AISLE, v + STALL_D * 2.0 + AISLE, 1.0])
		v += STALL_D * 2.0 + AISLE
	if pv1 - v >= STALL_D + AISLE:
		rows.append([pv1 - STALL_D, pv1, 1.0])
	# The lobby pavilion's projection and the canopy's reach in front of it.
	var lp := 3.2 if hq_site else 2.2
	var cd := 3.4 if hq_site else 2.0
	return {"L": L, "D": D, "sb": sb, "db": db, "lp": lp, "cd": cd, "ub0": ub0, "ub1": ub1, "drive_u0": drive_u0,
		"drive_u1": drive_u1, "gate_u": (drive_u0 + drive_u1) * 0.5, "pv0": pv0, "pv1": pv1, "rows": rows,
		"hq": hq_site}


## True when `lot` of block (bx, bz) is a station's (CityChunk._build_lot asks, after its rolls).
static func claims(plan: CityPlan, bx: int, bz: int, lot: Dictionary) -> bool:
	var s := station_on(plan, bx, bz)
	return not s.is_empty() and (s.lots as Array).has(int(lot.seed))


## The station on block (bx, bz), or {}.
static func station_on(plan: CityPlan, bx: int, bz: int) -> Dictionary:
	if not enabled or plan.macro == null:
		return {}
	var h := hq(plan)
	if not h.is_empty() and h.block == Vector2i(bx, bz):
		return h
	var b := plan.block(bx, bz)
	var s := for_cell(plan, _cell_of((b.rect as Rect2).get_center()))
	if not s.is_empty() and s.block == Vector2i(bx, bz):
		return s
	return {}


## The nearest station to `goal` (true world XZ) within `reach` (its gate's front), or {}.
static func nearest(plan: CityPlan, goal: Vector2, reach: float) -> Dictionary:
	if plan == null or not enabled or plan.macro == null:
		return {}
	var c := _cell_of(goal)
	var best: Dictionary = {}
	var best_d := reach
	var cands: Array[Dictionary] = [hq(plan)]
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			cands.append(for_cell(plan, c + Vector2i(dx, dz)))
	for s in cands:
		if s.is_empty():
			continue
		var d := (s.front as Vector2).distance_to(goal)
		if d < best_d:
			best_d = d
			best = s
	return best


## True when `p` (true world XZ) is on the kerb in front of a station's gate (CityChunk._park_car
## asks, after its rolls).
static func keeps_clear(plan: CityPlan, p: Vector2) -> bool:
	var s := nearest(plan, p, 40.0)
	if s.is_empty():
		return false
	var axis := int(s.road[0])
	var d := p - (s.front as Vector2)
	var along := d.y if axis == CityPlan.AXIS_X else d.x
	var lat := d.x if axis == CityPlan.AXIS_X else d.y
	return absf(along) < 10.0 and absf(lat) < plan.road_width(axis, int(s.road[1])) * 0.5 + 1.5


## [point (true world XZ), reach] along the pavement in front of the station on block (bx, bz)
## (its whole frontage): what Encampment keeps its camps off.
static func keep_clear_points(plan: CityPlan, bx: int, bz: int) -> Array:
	var s := station_on(plan, bx, bz)
	if s.is_empty():
		return []
	var out: Array = []
	var L: float = (s.layout as Dictionary).L
	var n := maxi(2, ceili(L / 6.0))
	for i in n + 1:
		out.append([world_xz(s, L * float(i) / float(n), -plan.sidewalk_width * 0.5), 6.0])
	return out


## A point of the station's frame (u along the street, v in from the site's street edge) as true
## world XZ.
static func world_xz(s: Dictionary, u: float, v: float) -> Vector2:
	return Industrial.fp(s.frame, u, v)


## Where a cruiser out of `s` joins the street: [axis, index, dir, point (true world XZ on the
## road's centre line in front of the gate)] heading toward `goal`; [] when the road is closed.
static func exit_lane(plan: CityPlan, s: Dictionary, goal: Vector2) -> Array:
	var axis := int(s.road[0])
	var index := int(s.road[1])
	var front: Vector2 = s.front
	var along := front.y if axis == CityPlan.AXIS_X else front.x
	var to := (goal.y if axis == CityPlan.AXIS_X else goal.x) - along
	if not plan.road_open(axis, index, along):
		return []
	return [axis, index, 1 if to >= 0.0 else -1, front]


## The drive out of the gate, true world XZ points: from inside the car park up the driveway,
## through the gate, across the pavement and round into the lane at `lane` metres off the centre
## line heading `dir` along the road. The last point is on the lane `turn` metres past the gate.
static func exit_path(plan: CityPlan, s: Dictionary, dir: int, lane: float, turn: float = 11.0) -> PackedVector2Array:
	var lay: Dictionary = s.layout
	var u: float = s.gate_u
	var axis := int(s.road[0])
	var out := PackedVector2Array()
	out.append(world_xz(s, u, float(lay.sb) + 10.0))
	out.append(world_xz(s, u, float(lay.sb) + 3.0))
	out.append(world_xz(s, u, -plan.sidewalk_width + 0.5))
	var front: Vector2 = s.front
	var fwd := Vector2(0.0, dir) if axis == CityPlan.AXIS_X else Vector2(dir, 0.0)
	var lane_pt := front + (Vector2(lane, 0.0) if axis == CityPlan.AXIS_X else Vector2(0.0, lane))
	var corner := lane_pt
	var kerb: Vector2 = out[2]
	# The turn: a quadratic curve from the kerb through the corner on the lane to `turn` past it.
	var end := lane_pt + fwd * turn
	for k in range(1, 9):
		var t := float(k) / 8.0
		out.append(kerb.lerp(corner, t).lerp(corner.lerp(end, t), t))
	return out


## The way in, from a point on the road in front of the gate: the exit run backwards.
static func enter_path(plan: CityPlan, s: Dictionary, dir: int, lane: float) -> PackedVector2Array:
	var p := exit_path(plan, s, -dir, lane)
	p.reverse()
	return p


## Height (true world) of a point of the station's drive: the road's on the street, the
## pavement's on the site.
static func path_height(plan: CityPlan, s: Dictionary, p: Vector2) -> float:
	var g := plan.macro.relief_at(p) if plan.macro else 0.0
	var f: Dictionary = s.frame
	var v := (p - (f.o as Vector2)).dot(f.n as Vector2)
	var top := CityChunk.SIDEWALK_TOP + 0.03
	if v >= 0.0:
		return g + top
	# Down the driveway's ramp across the pavement to the kerb.
	return g + lerpf(top, CityChunk.ROAD_TOP, clampf(-v / maxf(plan.sidewalk_width, 0.1), 0.0, 1.0))


# --- Building it ---------------------------------------------------------------------------------

## Builds the station on its lots in chunk `ch` (FULL: everything; LOD: boxes the far city
## captures). Called from CityChunk._build_lot for each of the site's lots: the builder lot builds
## it, the rest are left empty.
static func build_lot(ch: CityChunk, lot: Dictionary) -> void:
	var s := station_on(ch.plan, ch.ix, ch.iz)
	if s.is_empty() or int(lot.seed) != int(s.builder):
		return
	var lay: Dictionary = s.layout
	var site: Rect2 = s.site
	ch._lot_rects.append(site)
	var f: Dictionary = s.frame
	var L: float = lay.L
	var centre2 := Industrial.fp(f, L * 0.5, 0.0)
	var g := ch._gy(site.get_center().x, site.get_center().y)
	var a2: Vector2 = f.a
	var n2: Vector2 = f.n
	# Local frame: origin at the site's street edge, middle of the frontage, on the pavement top;
	# -Z inward (v), +Z toward the street; local x along the street, u = L/2 + sx * x.
	var outward := Vector3(-n2.x, 0.0, -n2.y)
	var x_axis := Vector3.UP.cross(outward)
	var basis := Basis(x_axis, Vector3.UP, outward)
	var xf := Transform3D(basis, Vector3(centre2.x, g + CityChunk.SIDEWALK_TOP, centre2.y))
	var sx := signf(Vector2(x_axis.x, x_axis.z).dot(a2))
	var storeys := int(s.storeys)
	var top := GROUND_H + UPPER_H * float(storeys - 1)
	var ub0: float = lay.ub0
	var ub1: float = lay.ub1
	var bw := ub1 - ub0
	var bu := (ub0 + ub1) * 0.5
	var bd: float = lay.db
	var bv := float(lay.sb) + bd * 0.5
	var bcentre := xf * Vector3(sx * (bu - L * 0.5), top * 0.5, -bv)
	var bsize := Vector3(bw, top, bd)
	if ch.level != CityChunk.Level.FULL:
		# Far: the building, the sally port and the mast as boxes (the old path, no code).
		var rot := basis * Basis.from_scale(bsize)
		ch._batch.add("lod_box", PropFactory.unit_box(), Transform3D(rot, bcentre), CONCRETE * 0.85,
				Color(0.12, 0.25, float(int(lot.seed) % 997) / 997.0, 0.0))
		ch._add_lod_shape(Vector3(bw, top, bd) if absf(x_axis.x) > 0.5 else Vector3(bd, top, bw), bcentre)
		var mast := xf * Vector3(sx * (float(lay.drive_u1) - 1.4 - L * 0.5), MAST_H * 0.5, -(float(lay.pv1) - 1.4))
		ch._batch.add("lod_box", PropFactory.unit_box(), Transform3D(basis * Basis.from_scale(Vector3(1.2, MAST_H, 1.2)), mast),
				Color(0.55, 0.56, 0.58), Color(0.0, 0.0, 0.5, 0.0))
		return
	var node := Node3D.new()
	node.name = "PoliceStation%d" % int(s.number)
	node.transform = xf
	node.add_to_group("police_station")
	node.set_meta("key", s.key)
	ch.add_child(node)
	_build_detail(node, s, sx, ch.plan.sidewalk_width)
	ch._occluder_boxes.append([xf, Vector3(sx * (bu - L * 0.5), top * 0.5, -bv), bsize - Vector3(0.6, 0.6, 0.6)])
	ch.building_count += 1


## Everything a FULL chunk draws of a station, in its local frame (see build_lot). `sx` maps u to
## local x: x = sx * (u - L/2); v maps to z = -v.
static func _build_detail(node: Node3D, s: Dictionary, sx: float, sidewalk: float) -> void:
	var lay: Dictionary = s.layout
	var L: float = lay.L
	var D: float = lay.D
	var hq_site: bool = lay.hq
	var sb: float = lay.sb
	var db: float = lay.db
	var ub0: float = lay.ub0
	var ub1: float = lay.ub1
	var du0: float = lay.drive_u0
	var du1: float = lay.drive_u1
	var pv0: float = lay.pv0
	var pv1: float = lay.pv1
	var storeys := int(s.storeys)
	var top := GROUND_H + UPPER_H * float(storeys - 1)
	var seed_v := int(s.builder)
	var g := Geo.new()
	var P := func(u: float, y: float, v: float) -> Vector3:
		return Vector3(sx * (u - L * 0.5), y, -v)
	# A box from frame extents (u0..u1, y0..y1, v0..v1).
	var B := func(key: String, u0: float, u1: float, y0: float, y1: float, v0: float, v1: float) -> void:
		g.box(key, Vector3(sx * ((u0 + u1) * 0.5 - L * 0.5), (y0 + y1) * 0.5, -(v0 + v1) * 0.5), Vector3(absf(u1 - u0), y1 - y0, absf(v1 - v0)))
	var bv0 := sb
	var bv1 := sb + db
	var bu := (ub0 + ub1) * 0.5
	# --- The ground: forecourt paving, the car park's asphalt, the driveway's apron to the kerb.
	B.call("paving", 0.0, du0, 0.0, 0.03, 0.0, sb)
	B.call("paving", du1, L, 0.0, 0.03, 0.0, sb)
	B.call("paving", 0.0, ub0, 0.0, 0.03, sb, bv1)
	B.call("paving", ub1, du0 - 0.3, 0.0, 0.03, sb, bv1)
	B.call("asphalt", du0 - 0.3, L, 0.0, 0.035, sb, pv0 - 0.6)
	B.call("asphalt", 0.0, L, 0.0, 0.035, pv0 - 0.6, D)
	B.call("asphalt", du0, du1, 0.0, 0.035, 0.0, sb)
	g.ramp("concrete", P.call((du0 + du1) * 0.5, 0.0, 0.0), (du1 - du0) + 0.6, sidewalk - 0.1, -(CityChunk.SIDEWALK_TOP - CityChunk.ROAD_TOP) - 0.02)
	# --- The building.
	_building(g, B, P, s, sx)
	# --- Forecourt: bollards along the street, planters, flagpoles, the monument sign.
	var entry_u := bu
	var k := 0
	var u := ub0 + 1.0
	while u < ub1 - 0.5:
		if absf(u - entry_u) > 2.5:
			g.cyl("bollard", P.call(u, 0.0, 0.9), 0.13, 1.0, 10)
			g.cyl("bollard_cap", P.call(u, 1.0, 0.9), 0.14, 0.05, 10)
		u += 1.7
		k += 1
	for side: float in [-1.0, 1.0]:
		var pu := entry_u + side * minf(bw_half(ub0, ub1) * 0.55, 14.0)
		B.call("concrete", pu - 3.2, pu + 3.2, 0.0, 0.62, 2.2, 3.8)
		B.call("hedge", pu - 3.0, pu + 3.0, 0.62, 1.15, 2.4, 3.6)
	var lobby_half := (14.0 if hq_site else 9.0) * 0.5 + 2.5
	for i in 3:
		var fu := entry_u + lobby_half + 2.0 + float(i) * 1.6
		if fu > ub1 - 1.0:
			fu = entry_u - lobby_half - 2.0 - float(i) * 1.6
		g.cyl("steel", P.call(fu, 0.0, sb - 1.6), 0.07, 11.0 - 0.6 * float(i % 2), 8)
		g.cyl("gold", P.call(fu, 11.0 - 0.6 * float(i % 2), sb - 1.6), 0.11, 0.18, 8)
		var fl := ["flag_navy", "flag_gold", "flag_navy"][i] as String
		B.call(fl, fu + 0.08, fu + 1.75, 9.65 - 0.6 * float(i % 2), 10.75 - 0.6 * float(i % 2), sb - 1.62, sb - 1.58)
	var mu := ub0 + 4.5
	B.call("concrete_dark", mu - 2.6, mu + 2.6, 0.0, 0.25, 1.1, 2.3)
	B.call("concrete", mu - 2.4, mu + 2.4, 0.25, 1.65, 1.5, 1.9)
	# --- The secured car park: palisade on the street line with the sliding gate, chain-link
	# with barbed wire round the rest.
	var fence_v := sb + 0.2
	_palisade(g, P, ub1 + 0.2, du0, fence_v)
	for post_u: float in [du0, du1 + 0.15]:
		B.call("steel_dark", post_u - 0.15, post_u + 0.15, 0.0, FENCE_H + 0.3, fence_v - 0.15, fence_v + 0.15)
	_chain(g, P, Vector2(du1 + 0.3, fence_v), Vector2(L - 0.3, fence_v))
	_chain(g, P, Vector2(L - 0.3, fence_v), Vector2(L - 0.3, D - 0.3))
	_chain(g, P, Vector2(L - 0.3, D - 0.3), Vector2(0.3, D - 0.3))
	_chain(g, P, Vector2(0.3, D - 0.3), Vector2(0.3, bv1))
	_chain(g, P, Vector2(0.3, bv1), Vector2(ub0, bv1))
	# Gate track and a keypad pedestal at the driver's window, inside and out.
	B.call("steel_dark", du0 - GATE_W - 0.2, du1, 0.0, 0.05, fence_v + 0.35, fence_v + 0.5)
	B.call("steel_dark", du0 + 0.4, du0 + 0.7, 0.0, 1.2, -0.8, -0.5)
	B.call("lamp_cool", du0 + 0.42, du0 + 0.68, 1.0, 1.15, -0.81, -0.79)
	# --- Stalls, the cruisers in them, the fuel island, the mast, the floodlights.
	var cars: Array[Transform3D] = []
	var max_cars := HQ_MAX_CARS if hq_site else MAX_CARS
	var sally_u0 := ub1 - 7.5
	var sally_u1 := ub1 - 1.0
	var row_specs: Array = lay.rows
	var fuel_u0 := 1.5
	var fuel_u1 := fuel_u0 + 3.0 * STALL_W
	var mast_u := du1 - 1.6
	var mast_v := pv1 - 1.6
	# From the back fence forward: the rows behind the building are the ones it hides.
	for ri in range(row_specs.size() - 1, -1, -1):
		var r: Array = row_specs[ri]
		var v0: float = r[0]
		var v1: float = r[1]
		var su := 1.2
		var idx := 0
		while su + STALL_W <= L - 1.0:
			var cu := su + STALL_W * 0.5
			su += STALL_W
			idx += 1
			if ri == 0 and cu > sally_u0 - 2.0 and cu < sally_u1 + 2.0:
				continue
			if ri < row_specs.size() - 1 and cu > du0 - 0.5:
				# The driveway runs on into the car park: keep its end clear.
				continue
			if ri == row_specs.size() - 1 and cu < fuel_u1 + 0.4:
				continue
			if ri == row_specs.size() - 1 and cu > mast_u - 3.0:
				continue
			# Stall lines.
			B.call("paint", cu - STALL_W * 0.5 - 0.06, cu - STALL_W * 0.5 + 0.06, 0.035, 0.045, v0 + 0.2, v1 - 0.1)
			B.call("paint", cu + STALL_W * 0.5 - 0.06, cu + STALL_W * 0.5 + 0.06, 0.035, 0.045, v0 + 0.2, v1 - 0.1)
			# Wheel stop.
			var ws := v0 + 0.55 if float(r[2]) < 0.0 else v1 - 0.55
			B.call("concrete", cu - 0.9, cu + 0.9, 0.035, 0.17, ws - 0.1, ws + 0.1)
			if cars.size() < max_cars and _h01([seed_v, ri, idx, "ps_car"]) < FILL:
				var cv := (v0 + v1) * 0.5
				# Nose to the kerb: row 0 faces the building (toward the street, +z local), the
				# back row faces the back fence (-z). The car model's nose is -Z.
				var face := Vector3(0.0, 0.0, 1.0) if float(r[2]) < 0.0 else Vector3(0.0, 0.0, -1.0)
				var yaw := atan2(-face.x, -face.z) + (_h01([seed_v, ri, idx, "ps_yaw"]) - 0.5) * 0.04
				cars.append(Transform3D(Basis(Vector3.UP, yaw), P.call(cu, 0.035, cv)))
	# Fuel island: a canopy on two columns over an island with two dispensers.
	var last_row: Array = row_specs.back()
	var fv0 := float(last_row[0]) - 0.8
	var fv1 := float(last_row[1]) - 0.2
	var fum := (fuel_u0 + fuel_u1) * 0.5
	var fvm := (fv0 + fv1) * 0.5
	B.call("concrete", fum - 0.7, fum + 0.7, 0.0, 0.2, fv0 + 0.6, fv1 - 0.6)
	for dz: float in [-1.2, 1.2]:
		B.call("pump", fum - 0.35, fum + 0.35, 0.2, 1.85, fvm + dz - 0.3, fvm + dz + 0.3)
		B.call("lamp_cool", fum - 0.36, fum + 0.36, 1.45, 1.75, fvm + dz - 0.18, fvm + dz + 0.18)
	for dz: float in [-2.4, 2.4]:
		B.call("steel", fum - 0.15, fum + 0.15, 0.2, 4.6, fvm + dz - 0.15, fvm + dz + 0.15)
	B.call("canopy", fum - 4.4, fum + 4.4, 4.6, 5.2, fv0 - 0.8, fv1 + 0.4)
	B.call("lamp_cool", fum - 3.6, fum + 3.6, 4.58, 4.6, fvm - 0.6, fvm + 0.6)
	# The radio mast: a square lattice tapering up, X-braced, with antennas and a red beacon.
	_mast(g, P.call(mast_u, 0.0, mast_v))
	# Floodlights: poles along the back fence and by the drive, two heads each.
	var flood_spots: Array[Vector2] = []
	var nfl := maxi(2, int(L / 22.0))
	for i in nfl:
		flood_spots.append(Vector2(lerpf(4.0, L - 6.0, float(i) / float(maxi(nfl - 1, 1))), D - 0.9))
	flood_spots.append(Vector2(du0 - 1.0, bv1 + 1.0))
	for fs in flood_spots:
		var base: Vector3 = P.call(fs.x, 0.0, fs.y)
		g.cyl("steel", base, 0.11, 9.0, 8)
		var inward := Vector3(0.0, 0.0, 1.0) if fs.y > pv0 else Vector3(0.0, 0.0, -1.0)
		for side: float in [-0.7, 0.7]:
			var head := base + Vector3(side, 9.0, inward.z * 0.4)
			g.box("steel_dark", head, Vector3(0.6, 0.18, 0.5))
			g.box("lamp_cool", head + Vector3(0.0, -0.1, 0.0), Vector3(0.52, 0.03, 0.42))
	# CCTV: cameras on brackets at the building's corners and on the gate posts.
	var cams: Array[Vector3] = [P.call(ub0 + 0.2, GROUND_H + 0.4, sb - 0.2), P.call(ub1 - 0.2, GROUND_H + 0.4, sb - 0.2),
		P.call(ub0 + 0.2, GROUND_H + 0.4, bv1 + 0.2), P.call(ub1 - 0.2, GROUND_H + 0.4, bv1 + 0.2),
		P.call(du0, FENCE_H + 0.5, fence_v), P.call(du1 + 0.15, FENCE_H + 0.5, fence_v)]
	for cpos in cams:
		var away := Vector3(cpos.x, 0.0, cpos.z).normalized() if Vector3(cpos.x, 0.0, cpos.z).length() > 0.1 else Vector3.BACK
		g.box("steel_dark", cpos + away * 0.15, Vector3(0.06, 0.06, 0.3))
		g.box("camera", cpos + away * 0.32 + Vector3(0.0, -0.08, 0.0), Vector3(0.16, 0.14, 0.32))
	var mi := MeshInstance3D.new()
	mi.name = "Building"
	mi.mesh = g.commit()
	node.add_child(mi)
	# The gate: its own node, slid open along the street line behind the palisade.
	var gate := MeshInstance3D.new()
	gate.name = "Gate"
	gate.mesh = gate_mesh()
	var closed: Vector3 = P.call((du0 + du1) * 0.5, 0.0, fence_v + 0.42)
	var open_shift := Vector3(-sx * (GATE_W + 0.4), 0.0, 0.0)
	gate.position = closed
	gate.set_meta("closed", closed)
	gate.set_meta("open", closed + open_shift)
	if Time.get_ticks_msec() < int(_open_until.get(s.key, 0)):
		gate.position = closed + open_shift
	node.add_child(gate)
	_cruisers(node, cars)
	_lights(node, s, P, flood_spots, sx)
	_texts(node, s, P, sx)
	_collision(node, s, P, cars)


static func bw_half(u0: float, u1: float) -> float:
	return (u1 - u0) * 0.5


## The building: precast concrete with glass bands between spandrels and full-height fins on the
## upper floors, a glazed double-height lobby pavilion with a cantilevered canopy at the entrance,
## a stair tower clad in dark metal, the sally port on the car park side, roof plant.
static func _building(g: Geo, B: Callable, P: Callable, s: Dictionary, sx: float) -> void:
	var lay: Dictionary = s.layout
	var L: float = lay.L
	var sb: float = lay.sb
	var db: float = lay.db
	var ub0: float = lay.ub0
	var ub1: float = lay.ub1
	var storeys := int(s.storeys)
	var top := GROUND_H + UPPER_H * float(storeys - 1)
	var v0 := sb
	var v1 := sb + db
	var bu := (ub0 + ub1) * 0.5
	# Core: the inner box the facade wraps (glass bands sit on its faces).
	B.call("concrete_dark", ub0, ub1, 0.0, 0.6, v0 - 0.05, v1 + 0.05)
	B.call("glass", ub0 + 0.25, ub1 - 0.25, 0.6, top, v0 + 0.25, v1 - 0.25)
	# Ground floor: concrete wall with slot windows, the lobby in the middle of the front.
	var lobby_w := 14.0 if bool(lay.hq) else 9.0
	var lu0 := bu - lobby_w * 0.5
	var lu1 := bu + lobby_w * 0.5
	for face: Array in [[v0, v0 + 0.4], [v1 - 0.4, v1]]:
		var fv0: float = face[0]
		var fv1: float = face[1]
		var u := ub0
		var slot := 0
		while u < ub1 - 0.01:
			var u2 := minf(u + 2.4, ub1)
			var front := fv0 == v0
			if front and u2 > lu0 and u < lu1:
				u = u2
				continue
			if slot % 2 == 1:
				B.call("concrete", u, u2, 0.6, 1.2, fv0, fv1)
				B.call("concrete", u, u2, 3.3, GROUND_H, fv0, fv1)
			else:
				B.call("concrete", u, u2, 0.6, GROUND_H, fv0, fv1)
			u = u2
			slot += 1
	for side_u: Array in [[ub0, ub0 + 0.4], [ub1 - 0.4, ub1]]:
		B.call("concrete", side_u[0], side_u[1], 0.6, GROUND_H, v0, v1)
	# Upper floors: a spandrel band at each floor line, glass between, fins every bay.
	for k in range(1, storeys):
		var y := GROUND_H + UPPER_H * float(k - 1)
		B.call("concrete", ub0 - 0.15, ub1 + 0.15, y - 0.25, y + 1.0, v0 - 0.15, v0 + 0.3)
		B.call("concrete", ub0 - 0.15, ub1 + 0.15, y - 0.25, y + 1.0, v1 - 0.3, v1 + 0.15)
		B.call("concrete", ub0 - 0.15, ub0 + 0.3, y - 0.25, y + 1.0, v0, v1)
		B.call("concrete", ub1 - 0.3, ub1 + 0.15, y - 0.25, y + 1.0, v0, v1)
	var fin_top := top
	var u := ub0 + 1.6
	while u < ub1 - 1.0:
		B.call("fin", u - 0.11, u + 0.11, GROUND_H + 0.75, fin_top, v0 - 0.55, v0 + 0.1)
		B.call("fin", u - 0.11, u + 0.11, GROUND_H + 0.75, fin_top, v1 - 0.1, v1 + 0.55)
		u += 1.6
	var v := v0 + 1.6
	while v < v1 - 1.0:
		B.call("fin", ub0 - 0.55, ub0 + 0.1, GROUND_H + 0.75, fin_top, v - 0.11, v + 0.11)
		B.call("fin", ub1 - 0.1, ub1 + 0.55, GROUND_H + 0.75, fin_top, v - 0.11, v + 0.11)
		v += 1.6
	# Parapet and roof.
	B.call("concrete", ub0 - 0.2, ub1 + 0.2, top, top + 1.1, v0 - 0.2, v0 + 0.15)
	B.call("concrete", ub0 - 0.2, ub1 + 0.2, top, top + 1.1, v1 - 0.15, v1 + 0.2)
	B.call("concrete", ub0 - 0.2, ub0 + 0.15, top, top + 1.1, v0, v1)
	B.call("concrete", ub1 - 0.15, ub1 + 0.2, top, top + 1.1, v0, v1)
	B.call("roof", ub0 + 0.15, ub1 - 0.15, top - 0.05, top + 0.05, v0 + 0.15, v1 - 0.15)
	# Roof plant: units and a penthouse.
	var nunits := maxi(2, int((ub1 - ub0) / 12.0))
	for i in nunits:
		var cu := lerpf(ub0 + 5.0, ub1 - 5.0, (float(i) + 0.5) / float(nunits))
		B.call("plant", cu - 1.6, cu + 1.6, top, top + 1.6, v0 + db * 0.45 - 1.1, v0 + db * 0.45 + 1.1)
		B.call("steel_dark", cu - 0.6, cu + 0.6, top + 1.6, top + 1.75, v0 + db * 0.45 - 0.6, v0 + db * 0.45 + 0.6)
	# The stair tower at the low-u end, dark metal, standing over the roof.
	B.call("metal", ub0 - 0.6, ub0 + 3.4, 0.0, top + 2.6, v1 - 6.0, v1 + 0.6)
	B.call("glass", ub0 - 0.62, ub0 - 0.6, 1.0, top + 2.0, v1 - 4.8, v1 - 0.6)
	# The lobby pavilion: double height, glazed, projecting toward the street under a thin roof
	# that cantilevers out as the entrance canopy.
	var lp: float = lay.lp
	var cd: float = lay.cd
	B.call("concrete_dark", lu0, lu1, 0.0, 0.15, v0 - lp, v0)
	B.call("lobby", lu0 + 0.1, lu1 - 0.1, 0.15, GROUND_H + 1.5, v0 - lp + 0.1, v0 + 0.3)
	for mu in range(int(lobby_w / 1.5) + 1):
		var x := lu0 + float(mu) * lobby_w / float(int(lobby_w / 1.5))
		B.call("metal", x - 0.04, x + 0.04, 0.15, GROUND_H + 1.5, v0 - lp + 0.06, v0 - lp + 0.14)
	B.call("metal", lu0, lu1, 2.7, 2.78, v0 - lp + 0.05, v0 - lp + 0.15)
	B.call("canopy", lu0 - 2.5, lu1 + 2.5, GROUND_H + 1.5, GROUND_H + 1.95, v0 - lp - cd, v0)
	B.call("lamp_warm", lu0 - 2.0, lu1 + 2.0, GROUND_H + 1.48, GROUND_H + 1.5, v0 - lp - cd + 0.4, v0 - lp + 0.4)
	# Entry doors (dark bronze frames).
	B.call("metal", bu - 1.9, bu + 1.9, 0.15, 2.6, v0 - lp + 0.02, v0 - lp + 0.06)
	B.call("lobby", bu - 1.8, bu + 1.8, 0.2, 2.5, v0 - lp - 0.01, v0 - lp + 0.03)
	# The name band over the canopy (the letters are TextMesh, _texts()), lit from below.
	B.call("metal", lu0 - 2.5, lu1 + 2.5, GROUND_H + 1.95, GROUND_H + 2.85, v0 - lp - cd, v0 - lp - cd + 0.15)
	# Sally port: a covered bay on the car park side at the drive end, its roll-up door facing the
	# car park, yellow bollards each side.
	var su0 := ub1 - 7.5
	var su1 := ub1 - 1.0
	B.call("concrete", su0, su0 + 0.35, 0.0, 5.2, v1, v1 + SALLY_D)
	B.call("concrete", su1 - 0.35, su1, 0.0, 5.2, v1, v1 + SALLY_D)
	B.call("concrete", su0, su1, 4.6, 5.3, v1, v1 + SALLY_D)
	B.call("rollup", su0 + 0.35, su1 - 0.35, 0.0, 4.4, v1 + SALLY_D - 0.3, v1 + SALLY_D - 0.15)
	B.call("lamp_warm", su0 + 1.0, su1 - 1.0, 4.58, 4.6, v1 + 1.0, v1 + SALLY_D - 1.0)
	for bx: float in [su0 - 0.5, su1 + 0.5]:
		g.cyl("bollard_yellow", P.call(bx, 0.0, v1 + SALLY_D + 0.1), 0.15, 1.1, 10)


## The street run of the fence: steel palisade between two posts, square pickets with pointed
## heads, rails top and bottom.
static func _palisade(g: Geo, P: Callable, u0: float, u1: float, v: float) -> void:
	if u1 - u0 < 0.5:
		return
	var a: Vector3 = P.call(u0, 0.0, v)
	var b: Vector3 = P.call(u1, 0.0, v)
	var d := b - a
	var n := maxi(2, int(d.length() / 0.16))
	for i in n + 1:
		var p := a + d * (float(i) / float(n))
		g.box("steel_dark", p + Vector3(0.0, FENCE_H * 0.5, 0.0), Vector3(0.04, FENCE_H, 0.04))
		g.box("steel_dark", p + Vector3(0.0, FENCE_H + 0.06, 0.0), Vector3(0.02, 0.12, 0.02))
	for y: float in [0.25, FENCE_H - 0.2]:
		g.box("steel_dark", (a + b) * 0.5 + Vector3(0.0, y, 0.0), Vector3(absf(d.x) + 0.04, 0.06, absf(d.z) + 0.04))


## A chain-link run from `a` to `b` (frame u, v): posts every 3 m, the mesh, a top rail and three
## strands of barbed wire on outrigger arms.
static func _chain(g: Geo, P: Callable, a2: Vector2, b2: Vector2) -> void:
	var a: Vector3 = P.call(a2.x, 0.0, a2.y)
	var b: Vector3 = P.call(b2.x, 0.0, b2.y)
	var d := b - a
	var len := d.length()
	if len < 0.3:
		return
	var n := maxi(1, ceili(len / 3.0))
	for i in n + 1:
		var p := a + d * (float(i) / float(n))
		g.box("steel", p + Vector3(0.0, (FENCE_H + 0.45) * 0.5, 0.0), Vector3(0.06, FENCE_H + 0.45, 0.06))
	g.fence(a, b, FENCE_H)
	var dir := d / len
	var rail := (a + b) * 0.5
	g.box("steel", rail + Vector3(0.0, FENCE_H, 0.0), Vector3(absf(d.x) + 0.04, 0.04, absf(d.z) + 0.04))
	for k in 3:
		var y := FENCE_H + 0.12 + 0.13 * float(k)
		g.box("wire", rail + Vector3(0.0, y, 0.0) - Vector3(-dir.z, 0.0, dir.x) * 0.06 * float(k), Vector3(absf(d.x) + 0.02, 0.012, absf(d.z) + 0.012))


## The radio mast at `base` (local): four legs tapering from 2.4 m to 0.8 m, rings and X braces
## every 3 m, a platform, dishes and whips, a red beacon on top.
static func _mast(g: Geo, base: Vector3) -> void:
	var h := MAST_H
	var levels := int(h / 3.0)
	var half := func(y: float) -> float:
		return lerpf(1.2, 0.4, y / h)
	for cx: float in [-1.0, 1.0]:
		for cz: float in [-1.0, 1.0]:
			var h0: float = half.call(0.0)
			var h1: float = half.call(h)
			var p0 := base + Vector3(cx * h0, 0.0, cz * h0)
			var p1 := base + Vector3(cx * h1, h, cz * h1)
			g.beam("steel", p0, p1, 0.09)
	for i in levels:
		var y0 := float(i) * 3.0
		var y1 := y0 + 3.0
		var a0: float = half.call(y0)
		var a1: float = half.call(y1)
		var c0 := [Vector3(-a0, y0, -a0), Vector3(a0, y0, -a0), Vector3(a0, y0, a0), Vector3(-a0, y0, a0)]
		var c1 := [Vector3(-a1, y1, -a1), Vector3(a1, y1, -a1), Vector3(a1, y1, a1), Vector3(-a1, y1, a1)]
		for f in 4:
			var q0: Vector3 = base + c0[f]
			var q1: Vector3 = base + c0[(f + 1) % 4]
			var r0: Vector3 = base + c1[f]
			var r1: Vector3 = base + c1[(f + 1) % 4]
			g.beam("steel", r0, r1, 0.045)
			g.beam("steel", q0, r1, 0.035)
			g.beam("steel", q1, r0, 0.035)
	# Platform, dishes, whips, beacon.
	var t := base + Vector3(0.0, h, 0.0)
	g.box("steel_dark", t + Vector3(0.0, -2.0, 0.0), Vector3(1.8, 0.08, 1.8))
	g.box("dish", t + Vector3(0.75, -3.2, 0.0), Vector3(0.12, 1.1, 1.1))
	g.box("dish", t + Vector3(0.0, -5.5, -0.75), Vector3(0.9, 0.9, 0.12))
	g.box("dish", t + Vector3(-0.7, -1.2, 0.3), Vector3(0.3, 1.4, 0.3))
	g.beam("steel", t, t + Vector3(0.0, 4.5, 0.0), 0.05)
	g.beam("steel", t + Vector3(0.3, 0.0, 0.3), t + Vector3(0.3, 3.0, 0.3), 0.025)
	g.beam("steel", t + Vector3(-0.3, 0.0, -0.3), t + Vector3(-0.3, 2.4, -0.3), 0.025)
	g.box("beacon", t + Vector3(0.0, 4.6, 0.0), Vector3(0.22, 0.22, 0.22))
	var hm: float = half.call(h * 0.5)
	for c: float in [-1.0, 1.0]:
		g.box("beacon", base + Vector3(c * (hm + 0.1), h * 0.5, c * (hm + 0.1)), Vector3(0.16, 0.16, 0.16))


## The parked cruisers: the sedan's far twin in the police livery (one MultiMesh), the light bars
## dark on top (another).
static func _cruisers(node: Node3D, cars: Array[Transform3D]) -> void:
	if cars.is_empty():
		return
	var body := cruiser_mesh()
	if body.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = body.mesh
	mm.instance_count = cars.size()
	var bars := MultiMesh.new()
	bars.transform_format = MultiMesh.TRANSFORM_3D
	bars.mesh = PoliceCar.light_bar_mesh()
	bars.instance_count = cars.size()
	for i in cars.size():
		mm.set_instance_transform(i, cars[i] * Transform3D(Basis(), body.offset))
		bars.set_instance_transform(i, cars[i] * Transform3D(Basis(), body.bar))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Cruisers"
	mmi.multimesh = mm
	mmi.visibility_range_end = CAR_RANGE
	node.add_child(mmi)
	var bmi := MultiMeshInstance3D.new()
	bmi.name = "CruiserBars"
	bmi.multimesh = bars
	bmi.material_override = bar_material()
	bmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bmi.visibility_range_end = CAR_RANGE * 0.6
	node.add_child(bmi)


## {"mesh" (the sedan's far twin with the cruiser's paint and the parts material), "offset" (the
## model's origin from a car standing on y 0), "bar" (the light bar's place)}, or {} without the
## model. Built once.
static func cruiser_mesh() -> Dictionary:
	if _mats.has("cruiser"):
		return _mats.cruiser
	var out := {}
	_mats.cruiser = out
	var path: String = Vehicle.BODY_MODELS.get(Vehicle.BodyType.SEDAN, "")
	if path == "" or not ResourceLoader.exists(path):
		return out
	var inst := (load(path) as PackedScene).instantiate()
	var far: ArrayMesh = null
	var near_box := AABB()
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if String(m.name).ends_with("_far"):
			far = m.mesh as ArrayMesh
		elif m.mesh:
			near_box = m.mesh.get_aabb()
	inst.free()
	if far == null or far.get_surface_count() == 0:
		return out
	var mesh := far.duplicate() as ArrayMesh
	if mesh == null:
		return out
	for si in mesh.get_surface_count():
		var src := mesh.surface_get_material(si) as StandardMaterial3D
		if src == null:
			continue
		if String(src.resource_name).begins_with("paint"):
			mesh.surface_set_material(si, _cruiser_paint(src, near_box if near_box.size != Vector3.ZERO else far.get_aabb()))
		else:
			var pm := Vehicle._part_material(src)
			if pm != null:
				mesh.surface_set_material(si, pm)
	var box := far.get_aabb()
	out.mesh = mesh
	out.offset = Vector3(-box.get_center().x, -box.position.y, -box.get_center().z)
	out.bar = Vector3(0.0, box.size.y - 0.02, box.size.z * 0.05)
	return out


static func _cruiser_paint(src: StandardMaterial3D, box: AABB) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = Vehicle.PAINT_SHADER
	mat.set_shader_parameter("albedo_tex", src.albedo_texture)
	mat.set_shader_parameter("paint", PoliceCar.POLICE_BLACK)
	if src.normal_texture:
		mat.set_shader_parameter("normal_tex", src.normal_texture)
		mat.set_shader_parameter("has_normal", true)
	var f: Dictionary = Vehicle.FINISHES[Vehicle.Finish.GLOSS]
	mat.set_shader_parameter("paint_metallic", f.metallic)
	mat.set_shader_parameter("paint_roughness", f.roughness)
	mat.set_shader_parameter("clearcoat_amount", f.clearcoat)
	mat.set_shader_parameter("clearcoat_roughness_value", f.cc_rough)
	mat.set_shader_parameter("flake_strength", f.flake)
	mat.set_shader_parameter("stripe_color", PoliceCar.POLICE_WHITE)
	mat.set_shader_parameter("stripe_mode", 5)
	mat.set_shader_parameter("door_band", PoliceCar.DOOR_BAND)
	mat.set_shader_parameter("roof_from", 0.84)
	mat.set_shader_parameter("body_min", box.position)
	mat.set_shader_parameter("body_size", box.size)
	mat.set_shader_parameter("length_is_x", box.size.x >= box.size.z)
	return mat


## The parked cruisers' light bars: dark lenses (the police lights shader with its lights off).
static func bar_material() -> ShaderMaterial:
	if _mats.has("bar"):
		return _mats.bar
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/police_lights.gdshader")
	m.set_shader_parameter("lights_on", 0.0)
	m.set_shader_parameter("energy", 0.0)
	_mats.bar = m
	return m


## The sliding gate: a steel frame with vertical bars and a diagonal brace, GATE_W x GATE_H,
## centred on x at the origin, on rollers.
static func gate_mesh() -> Mesh:
	if _mats.has("gate_mesh"):
		return _mats.gate_mesh
	var g := Geo.new()
	var w := GATE_W
	var h := GATE_H
	g.box("steel_dark", Vector3(0.0, 0.12, 0.0), Vector3(w, 0.12, 0.08))
	g.box("steel_dark", Vector3(0.0, h - 0.06, 0.0), Vector3(w, 0.12, 0.08))
	g.box("steel_dark", Vector3(0.0, h * 0.5, 0.0), Vector3(w, 0.06, 0.06))
	for sx: float in [-1.0, 1.0]:
		g.box("steel_dark", Vector3(sx * (w * 0.5 - 0.06), h * 0.5, 0.0), Vector3(0.12, h - 0.1, 0.08))
	var n := int(w / 0.14)
	for i in n:
		var x := -w * 0.5 + 0.12 + float(i) * (w - 0.24) / float(n - 1)
		g.box("steel_dark", Vector3(x, h * 0.5 + 0.08, 0.0), Vector3(0.03, h - 0.06, 0.03))
	g.beam("steel_dark", Vector3(-w * 0.5 + 0.1, 0.18, 0.0), Vector3(w * 0.5 - 0.1, h - 0.12, 0.0), 0.05)
	for x: float in [-w * 0.35, w * 0.35]:
		g.cyl("steel", Vector3(x, -0.02, 0.0), 0.09, 0.14, 8)
	# A sign plate in the middle: police vehicles only.
	g.box("sign", Vector3(0.0, 1.45, 0.05), Vector3(1.1, 0.5, 0.02))
	var mesh := g.commit()
	_mats.gate_mesh = mesh
	return mesh


## Night: the floodlit car park (additive pools, one MultiMesh), the entrance's glow, and two
## real lights in the lamp group (the entrance and the car park; DayNight sets their energy).
static func _lights(node: Node3D, s: Dictionary, P: Callable, floods: Array[Vector2], _sx: float) -> void:
	var lay: Dictionary = s.layout
	var pools := MultiMesh.new()
	pools.transform_format = MultiMesh.TRANSFORM_3D
	pools.mesh = PropFactory.light_pool(Color(0.86, 0.92, 1.0), 0.75)
	var spots: Array[Transform3D] = []
	for fs in floods:
		var mid := (float(lay.pv0) + float(lay.pv1)) * 0.5
		var c: Vector3 = P.call(fs.x, 0.06, fs.y + signf(mid - fs.y) * 6.5)
		spots.append(Transform3D(Basis(Vector3.RIGHT, -PI * 0.5).scaled(Vector3(19.0, 1.0, 19.0)), c))
	var bu := (float(lay.ub0) + float(lay.ub1)) * 0.5
	var warm := Transform3D(Basis(Vector3.RIGHT, -PI * 0.5).scaled(Vector3(14.0, 1.0, 9.0)), P.call(bu, 0.06, float(lay.sb) - 4.0))
	pools.instance_count = spots.size()
	for i in spots.size():
		pools.set_instance_transform(i, spots[i])
	var pmi := MultiMeshInstance3D.new()
	pmi.name = "Pools"
	pmi.multimesh = pools
	pmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pmi.visibility_range_end = 260.0
	node.add_child(pmi)
	var wmi := MeshInstance3D.new()
	wmi.name = "EntryPool"
	wmi.mesh = PropFactory.light_pool(Color(1.0, 0.82, 0.58), 1.4)
	wmi.transform = warm
	wmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	wmi.visibility_range_end = 220.0
	node.add_child(wmi)
	if OS.has_feature("web"):
		return
	for spec: Array in [[P.call(bu, GROUND_H + 1.2, float(lay.sb) - 4.5), Color(1.0, 0.82, 0.6), 16.0],
			[P.call(float(lay.L) * 0.5, 8.0, (float(lay.pv0) + float(lay.pv1)) * 0.5), Color(0.85, 0.92, 1.0), 30.0]]:
		var l := OmniLight3D.new()
		l.position = spec[0]
		l.light_color = spec[1]
		l.omni_range = spec[2]
		l.light_energy = 0.0
		l.shadow_enabled = false
		l.distance_fade_enabled = true
		l.distance_fade_begin = 120.0
		l.distance_fade_length = 40.0
		l.visible = false
		l.add_to_group("lamp_light")
		node.add_child(l)


## The lettering: the department over the canopy, the division on the monument sign and the
## sally port's and the gate's plates. TextMesh, off on the web like the shop names.
static func _texts(node: Node3D, s: Dictionary, P: Callable, sx: float) -> void:
	if OS.has_feature("web"):
		return
	var lay: Dictionary = s.layout
	var bu := (float(lay.ub0) + float(lay.ub1)) * 0.5
	var face := float(lay.sb) - float(lay.lp) - float(lay.cd) - 0.02
	var name_line := DEPT
	var sub := ("%s DIVISION" % String(s.name)) if not lay.hq else "POLICE HEADQUARTERS"
	var items: Array = [
		[name_line, 0.62 if lay.hq else 0.5, Color(0.94, 0.92, 0.86), P.call(bu, GROUND_H + 2.4, face), 0.0, 180.0],
		[sub, 0.34, Color(0.9, 0.88, 0.8), P.call(float(lay.ub0) + 4.5, 1.15, 1.48), 0.0, 90.0],
		[DEPT, 0.2, Color(0.9, 0.88, 0.8), P.call(float(lay.ub0) + 4.5, 0.62, 1.48), 0.0, 60.0],
		["SALLY PORT", 0.34, Color(0.95, 0.78, 0.1), P.call(float(lay.ub1) - 4.25, 4.95, float(lay.sb) + float(lay.db) + SALLY_D + 0.02), PI, 60.0],
	]
	for it: Array in items:
		var mi := MeshInstance3D.new()
		mi.mesh = BigVehicles.text_mesh(it[0], it[1], it[2])
		mi.position = it[3]
		mi.rotation.y = float(it[4])
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = it[5]
		node.add_child(mi)
	# The gate's plate rides with the gate.
	var gate := node.get_node_or_null("Gate")
	if gate:
		var gm := MeshInstance3D.new()
		gm.mesh = BigVehicles.text_mesh("POLICE VEHICLES ONLY", 0.09, Color(0.95, 0.95, 0.95))
		gm.position = Vector3(0.0, 1.45, 0.065)
		gm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		gm.visibility_range_end = 40.0
		gate.add_child(gm)


## Collision: the building, the sally port, the mast's foot, the fuel canopy's island, the fences
## and the gate (on the gate's node), the parked cruisers.
static func _collision(node: Node3D, s: Dictionary, P: Callable, cars: Array[Transform3D]) -> void:
	var lay: Dictionary = s.layout
	var top := GROUND_H + UPPER_H * float(int(s.storeys) - 1)
	var body := StaticBody3D.new()
	body.name = "Body"
	body.collision_layer = 1
	body.collision_mask = 0
	node.add_child(body)
	var add := func(c: Vector3, size: Vector3, basis: Basis) -> void:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		cs.shape = bs
		cs.transform = Transform3D(basis, c)
		body.add_child(cs)
	var ext := func(u0: float, u1: float, y0: float, y1: float, v0: float, v1: float) -> void:
		var a: Vector3 = P.call(u0, y0, v0)
		var b: Vector3 = P.call(u1, y1, v1)
		add.call((a + b) * 0.5, (b - a).abs(), Basis())
	var sb: float = lay.sb
	var db: float = lay.db
	ext.call(lay.ub0, lay.ub1, 0.0, top, sb, sb + db)
	ext.call(float(lay.ub1) - 7.5, float(lay.ub1) - 1.0, 0.0, 5.3, sb + db, sb + db + SALLY_D)
	var fv := sb + 0.2
	var L: float = lay.L
	var D: float = lay.D
	for seg: Array in [[float(lay.ub1), float(lay.drive_u0), fv, fv], [float(lay.drive_u1), L - 0.3, fv, fv],
			[L - 0.3, L - 0.3, fv, D - 0.3], [0.3, L - 0.3, D - 0.3, D - 0.3], [0.3, 0.3, sb + db, D - 0.3]]:
		ext.call(minf(seg[0], seg[1]) - 0.05, maxf(seg[0], seg[1]) + 0.05, 0.0, FENCE_H + 0.5, minf(seg[2], seg[3]) - 0.05, maxf(seg[2], seg[3]) + 0.05)
	ext.call(float(lay.drive_u1) - 2.6, float(lay.drive_u1) - 0.6, 0.0, 6.0, float(lay.pv1) - 2.6, float(lay.pv1) - 0.6)
	for c in cars:
		add.call(c.origin + Vector3(0.0, 0.75, 0.0), Vector3(1.9, 1.4, 4.8), c.basis)
	# The gate's own collision, which moves with it.
	var gate := node.get_node_or_null("Gate") as Node3D
	if gate:
		var gb := AnimatableBody3D.new()
		gb.name = "GateBody"
		gb.collision_layer = 1
		gb.collision_mask = 0
		gb.sync_to_physics = false
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(GATE_W, GATE_H, 0.12)
		cs.shape = bs
		cs.position = Vector3(0.0, GATE_H * 0.5, 0.0)
		gb.add_child(cs)
		gate.add_child(gb)


## Slides the gate of `s` open (it closes again GATE_HOLD later).
static func open_gate(tree: SceneTree, s: Dictionary, hold: float = GATE_HOLD) -> void:
	if tree == null or s.is_empty():
		return
	_open_until[s.key] = Time.get_ticks_msec() + int((GATE_TIME * 2.0 + hold) * 1000.0)
	for n in tree.get_nodes_in_group("police_station"):
		var node := n as Node3D
		if node == null or node.get_meta("key", Vector2i(-1, -1)) != s.key:
			continue
		var gate := node.get_node_or_null("Gate") as Node3D
		if gate == null:
			continue
		if gate.has_meta("tween"):
			var old := gate.get_meta("tween") as Tween
			if old and old.is_valid():
				old.kill()
		var tw := gate.create_tween()
		tw.tween_property(gate, "position", gate.get_meta("open"), GATE_TIME * clampf(gate.position.distance_to(gate.get_meta("open")) / (GATE_W + 0.4), 0.05, 1.0)).set_trans(Tween.TRANS_SINE)
		tw.tween_interval(hold)
		tw.tween_property(gate, "position", gate.get_meta("closed"), GATE_TIME).set_trans(Tween.TRANS_SINE)
		gate.set_meta("tween", tw)


## How far open the gate of `s` is (0 shut .. 1 open), or -1 when it is not built.
static func gate_open_amount(tree: SceneTree, s: Dictionary) -> float:
	for n in tree.get_nodes_in_group("police_station"):
		var node := n as Node3D
		if node == null or node.get_meta("key", Vector2i(-1, -1)) != s.key:
			continue
		var gate := node.get_node_or_null("Gate") as Node3D
		if gate == null:
			return -1.0
		var c: Vector3 = gate.get_meta("closed")
		var o: Vector3 = gate.get_meta("open")
		return clampf(gate.position.distance_to(c) / maxf(c.distance_to(o), 0.01), 0.0, 1.0)
	return -1.0


# --- Materials -----------------------------------------------------------------------------------

static func material(key: String) -> Material:
	if _mats.has(key):
		return _mats[key]
	var m: Material
	match key:
		"concrete", "fin", "canopy":
			m = PropFactory.pbr("concrete", 3.0, CONCRETE if key != "canopy" else Color(0.92, 0.91, 0.88))
		"concrete_dark":
			m = PropFactory.pbr("concrete", 3.0, CONCRETE_DARK)
		"paving":
			m = PropFactory.pbr("pavers", 2.2, Color(0.88, 0.86, 0.82))
		"asphalt":
			m = PropFactory.pbr("asphalt", 4.0, Color(0.8, 0.8, 0.8))
		"roof":
			m = PropFactory.material(Color(0.6, 0.61, 0.62), 0.9)
		"plant":
			m = PropFactory.material(Color(0.7, 0.71, 0.7), 0.6)
		"hedge":
			m = PropFactory.material(Color(0.13, 0.24, 0.1), 0.95)
		"paint":
			m = PropFactory.material(Color(0.88, 0.88, 0.84), 0.7)
		"pump":
			m = PropFactory.material(Color(0.16, 0.2, 0.32), 0.45)
		"camera", "bollard_cap":
			m = PropFactory.material(Color(0.86, 0.86, 0.85), 0.4)
		"bollard":
			m = PropFactory.material(Color(0.12, 0.13, 0.14), 0.5)
		"bollard_yellow":
			m = PropFactory.material(Color(0.9, 0.7, 0.05), 0.5)
		"rollup":
			m = PropFactory.pbr("metal_corrugated", 1.0, Color(0.72, 0.74, 0.76))
		"flag_navy":
			m = PropFactory.material(NAVY, 0.85)
		"flag_gold":
			m = PropFactory.material(Color(0.78, 0.6, 0.18), 0.85)
		"sign":
			m = PropFactory.material(Color(0.08, 0.16, 0.42), 0.5)
		"dish":
			m = PropFactory.material(Color(0.9, 0.9, 0.88), 0.55)
		"steel", "steel_dark", "metal", "gold", "wire":
			var sm := StandardMaterial3D.new()
			sm.albedo_color = {"steel": Color(0.62, 0.63, 0.64), "steel_dark": Color(0.17, 0.18, 0.19), "metal": Color(0.12, 0.12, 0.13),
				"gold": Color(0.85, 0.66, 0.25), "wire": Color(0.55, 0.56, 0.57)}[key]
			sm.metallic = 0.7 if key != "metal" else 0.5
			sm.roughness = 0.45 if key != "gold" else 0.3
			m = sm
		"glass", "lobby":
			var gm := ShaderMaterial.new()
			gm.shader = load("res://shaders/police_station_glass.gdshader")
			gm.set_shader_parameter("cell", Vector2(1.6, UPPER_H) if key == "glass" else Vector2(1.5, 2.6))
			gm.set_shader_parameter("lobby", 1.0 if key == "lobby" else 0.0)
			m = gm
		"chain":
			m = LotFill.chain_link_panel().surface_get_material(0)
		"lamp_warm", "lamp_cool", "beacon":
			var lm := ShaderMaterial.new()
			lm.shader = _lamp_shader()
			lm.set_shader_parameter("tint", {"lamp_warm": Vector3(1.0, 0.82, 0.58), "lamp_cool": Vector3(0.86, 0.93, 1.0), "beacon": Vector3(1.0, 0.04, 0.02)}[key])
			lm.set_shader_parameter("strength", 6.0 if key != "beacon" else 9.0)
			lm.set_shader_parameter("day", 0.12 if key != "beacon" else 0.6)
			m = lm
		_:
			m = PropFactory.material(Color(0.5, 0.5, 0.5))
	_mats[key] = m
	return m


## Lamp faces: a dim fitting by day, lit after dark (lamp_factor); the beacon blinks.
static func _lamp_shader() -> Shader:
	if _mats.has("lamp_shader"):
		return _mats.lamp_shader
	var sh := Shader.new()
	sh.code = """shader_type spatial;
#include "res://shaders/color_space.gdshaderinc"
global uniform float lamp_factor;
uniform vec3 tint = vec3(1.0);
uniform float strength = 5.0;
uniform float day = 0.12;
void fragment() {
	float blink = day > 0.5 ? step(0.5, fract(TIME * 0.75)) : 1.0;
	ALBEDO = cs_out(vec3(0.7, 0.7, 0.68));
	ROUGHNESS = 0.4;
	EMISSION = cs_out(tint * strength * (day + (1.0 - day) * lamp_factor) * blink);
}
"""
	_mats.lamp_shader = sh
	return sh


## Boxes, beams, cylinders, ramps and fence quads into one mesh, a surface per material (flat
## faces, UV in metres).
class Geo:
	var _st: Dictionary = {}

	func _tool(key: String) -> SurfaceTool:
		if not _st.has(key):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			_st[key] = st
		return _st[key]

	func box(key: String, c: Vector3, s: Vector3) -> void:
		obox(key, Transform3D(Basis.from_scale(s), c))

	## A unit cube [-0.5, 0.5] through `xf` (any rotation and per-axis scale).
	func obox(key: String, xf: Transform3D) -> void:
		var st := _tool(key)
		var nb := xf.basis.inverse().transposed()
		var faces := [
			[Vector3.RIGHT, Vector3(0.5, -0.5, -0.5), Vector3(0.5, 0.5, -0.5), Vector3(0.5, 0.5, 0.5), Vector3(0.5, -0.5, 0.5)],
			[Vector3.LEFT, Vector3(-0.5, -0.5, 0.5), Vector3(-0.5, 0.5, 0.5), Vector3(-0.5, 0.5, -0.5), Vector3(-0.5, -0.5, -0.5)],
			[Vector3.UP, Vector3(-0.5, 0.5, -0.5), Vector3(-0.5, 0.5, 0.5), Vector3(0.5, 0.5, 0.5), Vector3(0.5, 0.5, -0.5)],
			[Vector3.DOWN, Vector3(-0.5, -0.5, 0.5), Vector3(-0.5, -0.5, -0.5), Vector3(0.5, -0.5, -0.5), Vector3(0.5, -0.5, 0.5)],
			[Vector3.BACK, Vector3(0.5, -0.5, 0.5), Vector3(0.5, 0.5, 0.5), Vector3(-0.5, 0.5, 0.5), Vector3(-0.5, -0.5, 0.5)],
			[Vector3.FORWARD, Vector3(-0.5, -0.5, -0.5), Vector3(-0.5, 0.5, -0.5), Vector3(0.5, 0.5, -0.5), Vector3(0.5, -0.5, -0.5)],
		]
		for f: Array in faces:
			var n: Vector3 = (nb * (f[0] as Vector3)).normalized()
			_quad(st, n, [xf * (f[1] as Vector3), xf * (f[2] as Vector3), xf * (f[3] as Vector3), xf * (f[4] as Vector3)])

	## A square bar of side `w` from `a` to `b`.
	func beam(key: String, a: Vector3, b: Vector3, w: float) -> void:
		var d := b - a
		var len := d.length()
		if len < 0.001:
			return
		var y := d / len
		var x := y.cross(Vector3.UP if absf(y.y) < 0.95 else Vector3.RIGHT).normalized()
		var z := x.cross(y).normalized()
		obox(key, Transform3D(Basis(x * w, y * len, z * w), (a + b) * 0.5))

	## An upright cylinder of radius `r` and height `h` standing on `base`.
	func cyl(key: String, base: Vector3, r: float, h: float, seg: int) -> void:
		var st := _tool(key)
		for i in seg:
			var a0 := TAU * float(i) / float(seg)
			var a1 := TAU * float(i + 1) / float(seg)
			var p0 := Vector3(cos(a0) * r, 0.0, sin(a0) * r)
			var p1 := Vector3(cos(a1) * r, 0.0, sin(a1) * r)
			var n := Vector3(cos((a0 + a1) * 0.5), 0.0, sin((a0 + a1) * 0.5))
			_quad(st, n, [base + p0, base + p1, base + p1 + Vector3(0.0, h, 0.0), base + p0 + Vector3(0.0, h, 0.0)])
			_tri(st, Vector3.UP, base + Vector3(0.0, h, 0.0), base + p0 + Vector3(0.0, h, 0.0), base + p1 + Vector3(0.0, h, 0.0))

	## A slab falling by `drop` over `length` from `at` (its high edge's centre) toward +z local,
	## `width` across.
	func ramp(key: String, at: Vector3, width: float, length: float, drop: float) -> void:
		var st := _tool(key)
		var a := at + Vector3(-width * 0.5, 0.03, 0.0)
		var b := at + Vector3(width * 0.5, 0.03, 0.0)
		var c := at + Vector3(width * 0.5, drop, length)
		var d := at + Vector3(-width * 0.5, drop, length)
		var up := (c - b).cross(a - b).normalized()
		if up.y < 0.0:
			up = -up
		_quad(st, up, [a, b, c, d])

	## A chain-link panel from `a` to `b`, `h` tall, both faces (the shader cuts it out).
	func fence(a: Vector3, b: Vector3, h: float) -> void:
		var st := _tool("chain")
		var d := b - a
		var len := d.length()
		var n := Vector3(-d.z, 0.0, d.x).normalized()
		var pts := [a + Vector3(0.0, 0.05, 0.0), b + Vector3(0.0, 0.05, 0.0), b + Vector3(0.0, h, 0.0), a + Vector3(0.0, h, 0.0)]
		var uvs := [Vector2(0.0, 0.05), Vector2(len, 0.05), Vector2(len, h), Vector2(0.0, h)]
		for k: int in [0, 1, 2, 0, 2, 3]:
			st.set_normal(n)
			st.set_uv(uvs[k])
			st.add_vertex(pts[k])

	func _quad(st: SurfaceTool, n: Vector3, q: Array) -> void:
		_tri(st, n, q[0], q[1], q[2])
		_tri(st, n, q[0], q[2], q[3])

	func _tri(st: SurfaceTool, n: Vector3, a: Vector3, b: Vector3, c: Vector3) -> void:
		# Clockwise seen from the side `n` points to (Godot's front faces).
		if (b - a).cross(c - a).dot(n) > 0.0:
			var t := b
			b = c
			c = t
		for v: Vector3 in [a, b, c]:
			st.set_normal(n)
			var uv := Vector2(v.x * absf(n.z) + v.z * absf(n.x), v.y) if absf(n.y) < 0.5 else Vector2(v.x, v.z)
			st.set_uv(uv)
			st.add_vertex(v)

	func commit() -> ArrayMesh:
		var mesh := ArrayMesh.new()
		for key: String in _st:
			var st: SurfaceTool = _st[key]
			st.commit(mesh)
			mesh.surface_set_material(mesh.get_surface_count() - 1, PoliceStation.material(key))
		return mesh
