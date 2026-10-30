class_name PowerPlant
extends RefCounted
## A gas-fired power plant on the coast (2026-10-30, fleet wave 3, "power-plant"): the FORM of the
## El Segundo and Redondo Beach plants - the old steam units' tall generating building and its TWIN
## STACKS with their red aviation lights, a newer combined-cycle block (gas turbines, their filter
## houses, the heat-recovery boilers and their own steel stacks, the steam turbine hall), the
## switchyard of transformers, breakers and lattice gantries, the fuel tanks in their berm, the
## intake pump house, an office and the gate - on three beach-town blocks just south of the airport
## and the end of the 105 freeway (x -634..-401, z 1217..1552 on the default seed). In front of it,
## on the sand, a seawall and the cooling water's intake and outfall trestle. A double-circuit line
## leaves the switchyard on lattice towers in the ridges' line style (RidgeKit's tower bodies,
## Ridges' spans and power_wire.gdshader) and runs east along the freeway to a receiving station.
## Names are invented: SEACLIFF GENERATING STATION of the BASIN LIGHT & POWER company.
##
## How it sits on the map: a landmark AREA (like the film studio lot's) that CityPlan snaps to whole
## blocks; the streets inside are closed and become the plant's yard. The layout is PURE (layout(),
## cached per plan; every position from the snapped rect, nothing rolled on a chunk or block rng),
## so the FULL chunks, the LOD chunks, the far city and the checks agree. The line's right of way
## takes the lots it crosses AFTER every roll (claims_lot() from CityPlan.lots(), claims_cell() from
## HouseKit.extra_lots()).
##
## POWER_PLANT=0 in the environment: no entry, no site, no line - the blocks are beach town (the A/B).

const SITE_ID := "power_plant"

static var enabled: bool = OS.get_environment("POWER_PLANT") != "0"

# --- Where -------------------------------------------------------------------------------------
## The area CityPlan snaps to whole blocks: the beach road (x -645.5) to the street at x -460.9 (the
## South Bay Mall's ring road stands just past it),
## the street south of the 105 (z 1208.4) to the next (z 1562.6) on the default seed.
const WEST_X := -645.5
const EAST_X := -460.9
const NORTH_Z := 1208.4
const SOUTH_Z := 1562.6
## The landmark's anchor: between the twin stacks (its chunk builds the stacks' lights in detail).
const ANCHOR := Vector2(-541.5, 1302.4)
const RADIUS := 30.0
const FLAT_MARGIN := 60.0
## The design the layout is drawn for (metres, kerb to kerb); another seed's snapped rect scales it.
const DESIGN := Vector2(165.6, 334.2)
## The smallest rect the plant is laid out in (else the site is bare yard).
const MIN_SIZE := Vector2(140.0, 270.0)

# --- The section -------------------------------------------------------------------------------
const PAVEMENT := 4.5
## The fence line, in from the kerb.
const FENCE_IN := 5.2
const BASE_Y := CityChunk.SIDEWALK_TOP + 0.05

# --- The stacks --------------------------------------------------------------------------------
const STACK_H := 78.0
const STACK_R0 := 4.6
const STACK_R1 := 3.1
const HRSG_STACK_H := 52.0
const HRSG_STACK_R := 3.2

# --- The line ----------------------------------------------------------------------------------
## Tower height, the line's distance south of the freeway's centre line, the right of way's half
## width (lots inside it are taken), the most a span may run.
const TOWER_H := 42.0
const LINE_OFFSET := 62.0
const ROW_HALF := 13.0
const MAX_SPAN := 420.0
const MIN_SPAN := 160.0
## The receiving station at the line's end, its size (x, z).
const STATION := Vector2(40.0, 50.0)

# --- Names (invented) --------------------------------------------------------------------------
const NAME := "SEACLIFF GENERATING STATION"
const COMPANY := "BASIN LIGHT & POWER"
const STATION_NAME := "LARKWOOD RECEIVING STATION"

static var _layouts: Dictionary = {}
static var _lines: Dictionary = {}


static func entry() -> Dictionary:
	return {"id": SITE_ID, "anchor": ANCHOR, "radius": RADIUS,
		"flat_rect": Rect2(WEST_X + 12.0, NORTH_Z + 9.0, EAST_X - WEST_X - 24.0, SOUTH_Z - NORTH_Z - 18.0), "flat_margin": FLAT_MARGIN,
		"area": {"west_x": WEST_X, "east_x": EAST_X, "north_z": NORTH_Z, "south_z": SOUTH_Z, "keep_z": [], "streets": {}}}


static func h01(parts: Array) -> float:
	return float(absi(hash(parts)) % 100003) / 100003.0


# =================================================================================================
# Layout (pure)
# =================================================================================================

## {"site", "rect" (kerb to kerb), "fence" (the fence line), "inner", "gate": {at, w}, "pieces":
## [{"kind", "c" (world XZ), "size" (x, y, z; x along world x), "yaw", "seed", ...}], "ground":
## [[Rect2, Industrial.G_*]] (drawn over the gravel), "stacks": [Vector3 top], "lamps": [Vector2],
## "cars": [{at, yaw, v}], "gantry": {pos, yaw, base}, "anchor"}. {} without the site.
static func layout(plan: CityPlan) -> Dictionary:
	if plan == null or not enabled or plan.macro == null:
		return {}
	var key := plan.get_instance_id()
	if _layouts.has(key):
		return _layouts[key]
	var lay := _make_layout(plan)
	_layouts[key] = lay
	return lay


## Site point (u east from the west kerb, v south from the north kerb) to world XZ, scaled from the
## design to this seed's rect.
static func _w(lay: Dictionary, u: float, v: float) -> Vector2:
	var r: Rect2 = lay.rect
	var s: Vector2 = lay.scale
	return Vector2(r.position.x + u * s.x, r.position.y + v * s.y)


static func _piece(lay: Dictionary, kind: String, u: float, v: float, size: Vector3, extra: Dictionary = {}) -> Dictionary:
	var p := {"kind": kind, "c": _w(lay, u, v), "size": size, "yaw": 0.0, "seed": absi(hash([lay.seed, kind, int(u), int(v)]))}
	p.merge(extra, true)
	(lay.pieces as Array).append(p)
	return p


static func _rect_uv(lay: Dictionary, u0: float, v0: float, u1: float, v1: float) -> Rect2:
	var a := _w(lay, u0, v0)
	var b := _w(lay, u1, v1)
	return Rect2(a, b - a)


static func _make_layout(plan: CityPlan) -> Dictionary:
	var s := plan.site_by_id(SITE_ID)
	if s.is_empty():
		return {}
	var rect: Rect2 = s.rect
	var lay := {"site": s, "rect": rect, "seed": plan.seed, "pieces": [], "ground": [], "stacks": [], "lamps": [],
		"cars": [], "scale": Vector2(rect.size.x / DESIGN.x, rect.size.y / DESIGN.y),
		"fence": rect.grow(-FENCE_IN), "inner": rect.grow(-(FENCE_IN + 0.3)), "ok": false}
	if rect.size.x < MIN_SIZE.x or rect.size.y < MIN_SIZE.y:
		return lay
	lay.ok = true
	var sc: Vector2 = lay.scale
	var W := DESIGN.x
	var EF := W - FENCE_IN / sc.x
	# --- The old steam units: the turbine hall along the sea side, the boiler house behind it, the
	# twin stacks, the flue ducts from the boiler house over to them, the units' step-up transformer.
	_piece(lay, "turbine_hall", 23.0, 85.0, Vector3(34.0, 25.0, 110.0))
	_piece(lay, "boiler_house", 58.0, 85.0, Vector3(36.0, 48.0, 98.0))
	for v: float in [58.0, 112.0]:
		var st := _piece(lay, "stack", 92.0, v, Vector3(STACK_R0 * 2.0, STACK_H, STACK_R0 * 2.0), {"r0": STACK_R0, "r1": STACK_R1, "bands": true})
		(lay.stacks as Array).append(Vector3((st.c as Vector2).x, STACK_H, (st.c as Vector2).y))
		_piece(lay, "flue", 81.7, v, Vector3(11.4, 7.0, 6.5), {"y": 31.0})
	_piece(lay, "gsu", 23.0, 18.0, Vector3(9.0, 7.0, 7.0), {"train": 3})
	# --- The combined-cycle block: two trains west to east (filter house, gas turbine, HRSG, its
	# stack), the steam turbine hall east of them, the step-up transformers on the south side.
	for k in 2:
		var v: float = [190.0, 258.0][k]
		_piece(lay, "filter_house", 13.0, v, Vector3(14.0, 22.0, 15.0), {"train": k})
		_piece(lay, "gas_turbine", 32.0, v, Vector3(24.0, 10.0, 9.5), {"train": k})
		_piece(lay, "hrsg", 68.0, v, Vector3(40.0, 27.0, 13.0), {"train": k})
		var hs := _piece(lay, "hrsg_stack", 93.0, v, Vector3(HRSG_STACK_R * 2.0, HRSG_STACK_H, HRSG_STACK_R * 2.0), {"r0": HRSG_STACK_R, "r1": HRSG_STACK_R, "bands": false})
		(lay.stacks as Array).append(Vector3((hs.c as Vector2).x, HRSG_STACK_H, (hs.c as Vector2).y))
		_piece(lay, "gsu", 30.0, v + 14.5, Vector3(9.0, 7.0, 7.0), {"train": k})
		_piece(lay, "pipe_bridge", 96.0, v + 9.5, Vector3(10.0, 22.0, 3.0), {"train": k})
	_piece(lay, "st_hall", 114.0, 245.0, Vector3(30.0, 23.0, 80.0))
	_piece(lay, "gsu", 114.0, 292.0, Vector3(9.0, 7.0, 7.0), {"train": 2})
	# Water: the intake pump house with its big pipes up to the turbine hall, the demineralised and
	# raw water tanks by the steam hall.
	_piece(lay, "pump_house", 18.0, 166.0, Vector3(24.0, 9.0, 18.0))
	_piece(lay, "tank", 102.0, 310.0, Vector3(14.0, 13.0, 14.0), {"r": 7.0, "paint": Color(0.84, 0.84, 0.8)})
	_piece(lay, "tank", 120.0, 316.0, Vector3(11.0, 10.0, 11.0), {"r": 5.5, "paint": Color(0.62, 0.66, 0.6)})
	# --- Fuel oil: two tanks in a bermed yard on the east side.
	_piece(lay, "berm", 147.0, 268.0, Vector3(26.0, 1.7, 100.0))
	for v: float in [242.0, 293.0]:
		_piece(lay, "tank", 147.0, v, Vector3(24.0, 13.0, 24.0), {"r": 11.5, "paint": Color(0.86, 0.85, 0.82), "fuel": true})
	# --- The switchyard (north-east): gravel, the dead-end gantry for the line, two rows of strain
	# gantries, the bays of breakers and bus, two big transformers, the control house.
	var sy := _rect_uv(lay, 106.0, 8.0, EF - 1.0, 118.0)
	lay["switchyard"] = sy
	_piece(lay, "switchyard", (106.0 + EF - 1.0) * 0.5, 63.0, Vector3(sy.size.x, 20.0, sy.size.y))
	var g := _w(lay, (106.0 + EF - 1.0) * 0.5, 16.0)
	lay["gantry"] = {"pos": g, "yaw": PI, "base": BASE_Y + plan.macro.relief_at(g)}
	# --- Offices, the car park, the gate on the street (east), the guard booth.
	_piece(lay, "admin", 137.0, 139.0, Vector3(38.0, 8.6, 22.0))
	_piece(lay, "guard", EF - 10.0, 183.0, Vector3(3.6, 3.0, 3.0))
	lay["gate"] = {"at": _w(lay, EF, 172.0), "w": 12.0}
	for i in 12:
		var row := i / 6
		var u := 121.0 + float(i % 6) * 5.6
		var v := 186.0 + float(row) * 9.0
		if h01([plan.seed, "pp_car", i]) < 0.78:
			lay.cars.append({"at": _w(lay, u, v), "yaw": 0.0 if row == 0 else PI, "v": int(h01([plan.seed, "pp_car_v", i]) * 4.0)})
	# --- Ground over the gravel: asphalt roads, concrete pads (no two overlap).
	var G := lay.ground as Array
	G.append([_rect_uv(lay, 99.0, 6.0, 105.0, 200.0), Industrial.G_ASPHALT])
	G.append([_rect_uv(lay, 105.0, 166.0, EF, 178.0), Industrial.G_ASPHALT])
	G.append([_rect_uv(lay, 116.0, 180.0, 156.0, 200.0), Industrial.G_ASPHALT])
	G.append([_rect_uv(lay, 4.0, 10.0, 98.0, 144.0), Industrial.G_CONCRETE])
	G.append([_rect_uv(lay, 4.0, 178.0, 98.0, 282.0), Industrial.G_CONCRETE])
	G.append([_rect_uv(lay, 98.0, 200.0, 131.0, 300.0), Industrial.G_CONCRETE])
	G.append([_rect_uv(lay, 112.0, 124.0, EF - 2.0, 156.0), Industrial.G_CONCRETE])
	# --- Flood masts round the yard.
	for p: Vector2 in [Vector2(6.0, 6.0), Vector2(6.0, 300.0), Vector2(96.0, 150.0), Vector2(96.0, 296.0),
			Vector2(106.0, 122.0), Vector2(EF - 2.0, 122.0), Vector2(EF - 2.0, 10.0), Vector2(EF - 2.0, 326.0)]:
		lay.lamps.append(_w(lay, p.x, p.y))
	lay["intake_z"] = _w(lay, 0.0, 85.0).y
	return lay


## True when world XZ `p` is inside the plant's site (kerb to kerb).
static func covers(plan: CityPlan, p: Vector2) -> bool:
	var lay := layout(plan)
	return not lay.is_empty() and (lay.rect as Rect2).has_point(p)


## The pieces whose centre is in `area`.
static func pieces_in(lay: Dictionary, area: Rect2) -> Array:
	var out: Array = []
	for p: Dictionary in lay.get("pieces", []):
		if area.has_point(p.c):
			out.append(p)
	return out


# =================================================================================================
# The line (pure): the switchyard's gantry, lattice towers east along the freeway, the receiving
# station at its end. In the ridges' line form (Ridges.spec / attach / wire), so the span shapes,
# conductors and earth wires are the very ones the ridges' lines draw.
# =================================================================================================

## {"gantry", "towers": [{id, pos, yaw, base, h, kind, legs}], "station": {rect, gantry}, "row":
## [[a, b]] (the right of way's centre segments), "cells": {Vector2i block: [Rect2 cell]}}. {} with
## no route.
static func line(plan: CityPlan) -> Dictionary:
	if plan == null or not enabled or plan.macro == null:
		return {}
	var key := plan.get_instance_id()
	if _lines.has(key):
		return _lines[key]
	_lines[key] = {}
	var ln := _plan_line(plan)
	_lines[key] = ln
	return ln


static func _plan_line(plan: CityPlan) -> Dictionary:
	var lay := layout(plan)
	if lay.is_empty() or not bool(lay.ok) or plan.macro.freeway == null:
		return {}
	var fw: Freeway = plan.macro.freeway
	var g: Dictionary = lay.gantry
	var gp: Vector2 = g.pos
	# The freeway's centre line north of the site: the nearest deck segment to the gantry.
	var best_d := INF
	var best_z := 0.0
	for sg: Dictionary in fw.segments_in(Rect2(gp - Vector2(80.0, 260.0), Vector2(160.0, 260.0))):
		if bool(sg.get("link", false)):
			continue
		var m: Vector2 = ((sg.a as Vector2) + (sg.b as Vector2)) * 0.5
		if m.y < gp.y and gp.y - m.y < best_d:
			best_d = gp.y - m.y
			best_z = m.y
	if best_d == INF or best_d < LINE_OFFSET + 10.0:
		return {}
	var towers: Array = []
	var x := gp.x
	var zl := best_z + LINE_OFFSET
	# First tower: the angle where the line turns from north to east.
	var first := _tower_spot(plan, fw, Vector2(x, zl))
	if first == Vector2.INF:
		return {}
	towers.append(first)
	var station := Rect2()
	for n in 6:
		var tried := false
		for step: float in [MAX_SPAN, MAX_SPAN - 40.0, MAX_SPAN - 80.0, MAX_SPAN - 120.0, MAX_SPAN - 160.0, MAX_SPAN - 200.0, MIN_SPAN]:
			var p := _tower_spot(plan, fw, Vector2((towers[towers.size() - 1] as Vector2).x + step, zl))
			if p != Vector2.INF:
				towers.append(p)
				tried = true
				break
		if not tried:
			break
		if towers.size() >= 3:
			# A station east of the last tower if a block takes it.
			var last: Vector2 = towers[towers.size() - 1]
			for ahead: float in [140.0, 100.0, 180.0, 220.0, 70.0]:
				station = _station_spot(plan, fw, last + Vector2(ahead, 0.0))
				if station.size.x > 0.0:
					break
			if station.size.x > 0.0:
				break
	if station.size.x <= 0.0 or towers.size() < 3:
		return {}
	var out: Array = []
	for i in towers.size():
		var p: Vector2 = towers[i]
		var prev: Vector2 = gp if i == 0 else towers[i - 1]
		var nxt: Vector2 = towers[i + 1] if i + 1 < towers.size() else station.get_center()
		var d0 := (p - prev).normalized()
		var d1 := (nxt - p).normalized()
		var dir := (d0 + d1).normalized()
		var kind := Ridges.Kind.ANGLE if (i == 0 or d0.dot(d1) < 0.996) else Ridges.Kind.SUSPENSION
		var base := CityChunk.SIDEWALK_TOP + 0.05 + plan.macro.relief_at(p)
		var legs := []
		var sp := Ridges.spec(TOWER_H)
		var hb: float = float(sp.base_half)
		var xf := Basis(Vector3.UP, atan2(dir.x, dir.y))
		for c in 4:
			var cs: Vector2 = RidgeKit.CORNER_SIGNS[c]
			var w := xf * Vector3(cs.x * hb, 0.0, cs.y * hb)
			legs.append(CityChunk.SIDEWALK_TOP + 0.05 + plan.macro.relief_at(p + Vector2(w.x, w.z)))
		out.append({"id": i, "pos": p, "yaw": atan2(dir.x, dir.y), "base": base, "h": TOWER_H, "kind": kind, "legs": legs})
	var sc := station.get_center()
	var sgantry := {"pos": Vector2(station.position.x + 6.0, sc.y), "yaw": -PI * 0.5, "base": CityChunk.SIDEWALK_TOP + 0.05 + plan.macro.relief_at(sc)}
	var row: Array = [[gp, towers[0]]]
	for i in range(1, towers.size()):
		row.append([towers[i - 1], towers[i]])
	row.append([towers[towers.size() - 1], sgantry.pos])
	return {"gantry": g, "towers": out, "station": {"rect": station, "gantry": sgantry}, "row": row}


## A tower foot near `want` (slid along x by up to 40 m): inside a plain buildings block, off the
## pavement, the freeway, its ramps, every site and landmark, the airport.
static func _tower_spot(plan: CityPlan, fw: Freeway, want: Vector2) -> Vector2:
	for dx: float in [0.0, -14.0, 14.0, -28.0, 28.0, -40.0, 40.0]:
		var p := want + Vector2(dx, 0.0)
		var foot := Rect2(p - Vector2(6.0, 6.0), Vector2(12.0, 12.0))
		if _ground_ok(plan, fw, foot, 4.0):
			return p
	return Vector2.INF


static func _station_spot(plan: CityPlan, fw: Freeway, want: Vector2) -> Rect2:
	for dx: float in [0.0, -15.0, 15.0, -30.0, 30.0]:
		var c := want + Vector2(dx, 0.0)
		var r := Rect2(c - STATION * 0.5, STATION)
		if _ground_ok(plan, fw, r, 4.0):
			return r
	return Rect2()


static var debug: bool = OS.get_environment("PP_DEBUG") == "1"


static func _why(r: Rect2, why: String) -> bool:
	if debug:
		print("PP_LINE %s: %s" % [r.get_center(), why])
	return false


static func _ground_ok(plan: CityPlan, fw: Freeway, r: Rect2, inset: float) -> bool:
	var m := plan.macro
	if m.zone_at(r.get_center()) != MacroMap.Zone.CITY or m.airport_rect.grow(30.0).intersects(r):
		return _why(r, "zone / airport")
	if m.runway_clear_zone().grow(20.0).intersects(r):
		return _why(r, "clear zone")
	if fw.blocks_rect(r, 6.0):
		return _why(r, "freeway")
	var k := plan.block_index_at(r.get_center())
	var b := plan.block(k.x, k.y)
	if b.has("site") or b.has("grounds") or b.has("hospital") or int(b.kind) != CityPlan.BlockKind.BUILDINGS:
		return _why(r, "block kind %d %s" % [int(b.kind), b.get("grounds", b.get("site", ""))])
	if int(b.district) == CityPlan.District.DOWNTOWN:
		return _why(r, "downtown")
	var inner: Rect2 = (b.rect as Rect2).grow(-(plan.sidewalk_width + inset))
	if not inner.encloses(r):
		return _why(r, "off the block's inner %s" % inner)
	for lm in Landmarks.all():
		if lm.get("area") is Dictionary or String(lm.id).ends_with("pier"):
			continue
		if lm.id == "south_bay_mall":
			# The mall's real extent: its ring road round the lot (LandmarkSouthBayMall).
			var a: Vector2 = lm.anchor
			var ring := Rect2(a.x - LandmarkSouthBayMall.SITE_HALF_X, a.y - LandmarkSouthBayMall.SITE_BACK,
				LandmarkSouthBayMall.SITE_HALF_X * 2.0, LandmarkSouthBayMall.SITE_BACK + LandmarkSouthBayMall.SITE_FRONT)
			if ring.grow(LandmarkSouthBayMall.RING_WIDTH + 6.0).intersects(r):
				return _why(r, "the mall's ring road")
			continue
		if (lm.anchor as Vector2).distance_to(r.get_center()) < float(lm.radius) + 12.0:
			return _why(r, "landmark " + String(lm.id))
	if plan.river_block(k.x, k.y) or plan.marina_block(k.x, k.y):
		return _why(r, "river / marina")
	return true


## CityPlan.lots(): true for a lot the line's right of way or the receiving station takes (after
## every roll; the block's stream is untouched).
static func claims_lot(plan: CityPlan, ix: int, iz: int, lot_rect: Rect2) -> bool:
	if not enabled or plan.macro == null:
		return false
	var ln := line(plan)
	if ln.is_empty():
		return false
	return _in_row(ln, lot_rect)


## HouseKit.extra_lots(): true for an empty cell the right of way takes (no house of its own there).
static func claims_cell(plan: CityPlan, cell: Rect2) -> bool:
	if not enabled or plan.macro == null:
		return false
	var ln := line(plan)
	return not ln.is_empty() and _in_row(ln, cell)


static func _in_row(ln: Dictionary, r: Rect2) -> bool:
	if ((ln.station as Dictionary).rect as Rect2).grow(3.0).intersects(r):
		return true
	for seg: Array in ln.row:
		if _rect_seg_distance(r, seg[0], seg[1]) < ROW_HALF:
			return true
	return false


static func _rect_seg_distance(r: Rect2, a: Vector2, b: Vector2) -> float:
	if r.has_point(a) or r.has_point(b):
		return 0.0
	var corners := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
	var best := INF
	for i in 4:
		var c0: Vector2 = corners[i]
		var c1: Vector2 = corners[(i + 1) % 4]
		if Geometry2D.segment_intersects_segment(a, b, c0, c1) != null:
			return 0.0
		best = minf(best, (Geometry2D.get_closest_point_to_segment(c0, a, b) - c0).length())
		best = minf(best, (Geometry2D.get_closest_point_to_segment(a, c0, c1) - a).length())
		best = minf(best, (Geometry2D.get_closest_point_to_segment(b, c0, c1) - b).length())
	return best


## The right of way and the station inside `area` (world rects), for a chunk to lay its ground.
static func row_rects_in(plan: CityPlan, area: Rect2) -> Array:
	var ln := line(plan)
	if ln.is_empty():
		return []
	var out: Array = []
	for seg: Array in ln.row:
		var a: Vector2 = seg[0]
		var b: Vector2 = seg[1]
		var r := Rect2(a, Vector2.ZERO).expand(b).grow(ROW_HALF)
		var p := r.intersection(area)
		if p.size.x > 1.0 and p.size.y > 1.0:
			out.append(p)
	return out
