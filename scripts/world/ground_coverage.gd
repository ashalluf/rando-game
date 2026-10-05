class_name GroundCoverage
extends RefCounted
## What covers the city's ground, block by block (tools/lot_coverage.gd prints it; the smoke test
## checks it). Each block's inner rect (inside the pavement ring) is rasterised on a `grid` m grid,
## every lot's building laid out exactly as CityChunk._build_lot() lays it (Building.plan_only(),
## no nodes, podium_lot where LotFill runs) and the fills asked the same questions the chunk asks
## (LotFill's forecourts, car parks and leftovers; YardFill's yards, walk streets, campus ground and
## the freeway's right of way). Pure data: no chunk, no nodes but a building planned and freed.
## Kinds, in order:
##   bare      the block's plain paving (or a campus or suburban block's plain lawn): nothing on it
##   built     under a building part standing on the ground (podiums included), a downtown tower or
##             the campus hall (its quad, steps and sign wall too)
##   yard      a pocket garden (lawn); a corridor lot's old ivy when the fills are off
##   forecourt a lot's ground a downtown or midtown building leaves, out to its cell (LotFill)
##   parking   a surface car park (LotFill; YardFill's beach and campus car parks)
##   garden    a house's yard, a courtyard, a walk street, a pocket park, the campus's walks, quads,
##             lawns and service yards (YardFill)
##   row       the freeway's right of way, out to its cells (YardFill)
##   sport     a rec park's fields, courts, playground, pool and walks, a school's track, fields,
##             courts and asphalt yard (Parks; their buildings are built, their car parks parking)
##   works     an industrial block's truck courts, dock aprons, storage yards, drive strips,
##             setbacks and rail spur (Industrial)
## A pad lot (Commercial.build_pad(), rolled from the chunk's own rng) is counted as its building.

const KINDS := ["bare", "built", "yard", "forecourt", "parking", "garden", "row", "works", "sport"]
const BARE := 0
const BUILT := 1
const YARD := 2
const FORECOURT := 3
const PARKING := 4
const GARDEN := 5
const ROW := 6
const WORKS := 7
const SPORT := 8
const DISTRICT_NAMES := ["DOWNTOWN", "MIDTOWN", "SUBURBS", "INDUSTRIAL", "CAMPUS", "BEACHTOWN"]
const SHAPE_NAMES := ["SLAB", "TOWER", "STEPPED", "PODIUM_TOWER", "L_SHAPE", "SETBACK", "CROWN", "WAREHOUSE"]


## A plan on its own map, as the city builds it.
static func make_plan(seed_value: int) -> CityPlan:
	var plan := CityPlan.new()
	plan.seed = seed_value
	plan.macro = MacroMap.new()
	plan.macro.seed = seed_value
	plan.macro.setup()
	return plan


## Every BUILDINGS block whose centre is in `area`: one line per row (district, FREEWAY, ROW_CELLS,
## MACARTHUR_SE), then the shapes and the podiums. {"lines": [String], "rows": {row: {"blocks",
## "lots_n", "frac": {kind: 0..1}}}}.
## `fill`: 0 neither fill (the city before LotFill), 1 LotFill only (before YardFill), 2 both
## (before Industrial), 3 all three.
static func report(seed_value: int, area: Rect2, fill: int, grid: float = 1.0) -> Dictionary:
	var plan := make_plan(seed_value)
	var lo: Vector2i = plan.block_index_at(area.position)
	var hi: Vector2i = plan.block_index_at(area.end)
	var tot := {}
	var shape_cov := {}
	var podiums := {}
	var se := macarthur_se_blocks(plan)
	for bx in range(lo.x, hi.x + 1):
		for bz in range(lo.y, hi.y + 1):
			var b: Dictionary = plan.block(bx, bz)
			var rect: Rect2 = b.rect
			if not area.has_point(rect.get_center()):
				continue
			var res := block(plan, bx, bz, fill, grid)
			if res.is_empty():
				continue
			var rows: Array[String] = [res.row]
			rows.append_array(res.get("extra", []))
			if res.freeway:
				rows.append("FREEWAY")
				rows.append("ROW_CELLS")
			if se.has(Vector2i(bx, bz)):
				rows.append("MACARTHUR_SE")
			for row in rows:
				if not tot.has(row):
					tot[row] = {"blocks": 0, "cells": 0, "lots": 0.0, "lots_n": 0, "lot_built": 0.0, "k": [0, 0, 0, 0, 0, 0, 0, 0, 0]}
				var t: Dictionary = tot[row]
				t.blocks += 1
				t.lots += float(res.lots)
				t.lots_n += int(res.lots_n)
				t.lot_built += float(res.lot_built)
				var ks: Array = res.row_k if row == "ROW_CELLS" else res.k
				for k in KINDS.size():
					t.k[k] += int(ks[k])
					t.cells += int(ks[k])
			for sk: String in res.shapes:
				if not shape_cov.has(sk):
					shape_cov[sk] = [0, 0.0]
				shape_cov[sk][0] += int(res.shapes[sk][0])
				shape_cov[sk][1] += float(res.shapes[sk][1])
			for pk: String in res.podiums:
				podiums[pk] = int(podiums.get(pk, 0)) + int(res.podiums[pk])
	var lines: Array[String] = []
	var rows_out := {}
	for row: String in tot:
		var t: Dictionary = tot[row]
		var frac := {}
		var line := "COVER %s blocks %d lots %d | buildings cover %.1f %% of their lots |" % [row, t.blocks, t.lots_n, 100.0 * t.lot_built / maxf(t.lots, 1.0)]
		for k in KINDS.size():
			frac[KINDS[k]] = float(t.k[k]) / maxf(float(t.cells), 1.0)
			line += " %s %.1f %%" % [KINDS[k], 100.0 * frac[KINDS[k]]]
		lines.append(line)
		rows_out[row] = {"blocks": t.blocks, "lots_n": t.lots_n, "frac": frac}
	var keys := shape_cov.keys()
	keys.sort()
	for k: String in keys:
		lines.append("SHAPE %s n %d mean lot cover %.1f %%" % [k, shape_cov[k][0], 100.0 * shape_cov[k][1] / shape_cov[k][0]])
	var pk := podiums.keys()
	pk.sort()
	for k: String in pk:
		lines.append("PODIUM %s %d" % [k, podiums[k]])
	return {"lines": lines, "rows": rows_out}


## The blocks the MACARTHUR_SE row counts: the ones across the street from MacArthur Park's site
## that rolled a plaza (on the default seed, the 100 x 180 m square of paving south of the park's
## east half) - buildings since the yard pass (CityPlan.block() "was_plaza").
static func macarthur_se_blocks(plan: CityPlan) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var s := plan.site_by_id("macarthur_park")
	if s.is_empty():
		return out
	for bx in range(int(s.ix0) - 1, int(s.ix1) + 1):
		for bz in range(int(s.iz0) - 1, int(s.iz1) + 1):
			if plan.block(bx, bz).get("was_plaza", false):
				out.append(Vector2i(bx, bz))
	return out


## A plaza block as CityChunk._build_plaza() / _furnish_plaza() lay it, on the coverage grid: its
## fountain built, its four raised beds garden, the rest bare paving.
static func _plaza(box: Array, rect: Rect2) -> void:
	var inner := rect.grow(-2.0)
	var center := inner.get_center()
	var basin_r := minf(inner.size.x, inner.size.y) * 0.12
	_paint(box, Rect2(center - Vector2(basin_r, basin_r), Vector2(basin_r, basin_r) * 2.0), BUILT)
	var keep := basin_r + 9.0
	var bw := clampf(inner.size.x * 0.24, 8.0, 26.0)
	var bd := clampf(inner.size.y * 0.24, 8.0, 26.0)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var c := center + Vector2(sx * maxf(keep + bw * 0.5, inner.size.x * 0.26), sz * maxf(keep * 0.7 + bd * 0.5, inner.size.y * 0.26))
			var bed := Rect2(c - Vector2(bw, bd) * 0.5, Vector2(bw, bd))
			if inner.grow(-7.0).encloses(bed):
				_paint(box, bed, GARDEN)


## One block: {"row" (district name, DOWNTOWN split), "freeway" (a corridor lot stands in it),
## "cells", "k" [count per kind], "lots", "lots_n", "lot_built", "shapes" {name: [n, cover]},
## "podiums" {name: n}} - {} for a block that is not a CITY block of buildings.
static func block(plan: CityPlan, bx: int, bz: int, fill: int, grid: float = 1.0) -> Dictionary:
	var b: Dictionary = plan.block(bx, bz)
	var brect: Rect2 = b.rect
	# A hospital campus is its own build (Hospital), not counted here.
	if Hospital.is_hospital(b):
		return {}
	if b.has("grounds") and fill >= 3 and plan.zone_at(brect.get_center()) == MacroMap.Zone.CITY:
		return _grounds(plan, bx, bz, b, grid)
	if int(b.kind) != CityPlan.BlockKind.BUILDINGS or b.has("site") or plan.zone_at(brect.get_center()) != MacroMap.Zone.CITY:
		return {}
	# A marina block is the marina's own ground (MarinaBuild).
	if plan.marina_block(bx, bz):
		return {}
	# Before the yard pass a plaza beside MacArthur Park was a plaza.
	var as_plaza: bool = fill < 2 and b.get("was_plaza", false)
	# A block a landmark claims whole (the civic set) is the landmark's own ground.
	if Landmarks.claims(brect):
		return {}
	# A replica area's block is the replica's own build (ReplicaBuilder), not the seeded block's.
	if plan.macro.replica and plan.macro.replica.block_role(plan, bx, bz) != 0:
		return {}
	var district: int = b.district
	var boost: float = plan.macro.skyline_boost(brect.get_center())
	var row: String = DISTRICT_NAMES[district]
	if district == CityPlan.District.DOWNTOWN:
		row += "_core" if boost > 0.55 else "_rest"
	var industrial: bool = fill >= 3 and district == CityPlan.District.INDUSTRIAL
	var filled: bool = fill >= 1 and district in LotFill.DISTRICTS
	var yards: bool = fill >= 2 and district in YardFill.DISTRICTS
	var rows: bool = fill >= 2
	var inner: Rect2 = brect.grow(-plan.sidewalk_width)
	var gx := maxi(1, int(inner.size.x / grid))
	var gz := maxi(1, int(inner.size.y / grid))
	var cells := PackedByteArray()
	cells.resize(gx * gz)
	var box := [cells, inner, grid, gx, gz]
	# The box is the grid's only holder: a packed array written with two holders is copied.
	cells = PackedByteArray()
	var out := {"row": row, "freeway": false, "cells": gx * gz, "lots": 0.0, "lots_n": 0, "lot_built": 0.0, "shapes": {}, "podiums": {}}
	for lm in Landmarks.all():
		var fp := Landmarks.campus_footprint(lm)
		if LandmarkDowntown.is_tower(str(lm.id)):
			fp = LandmarkDowntown.footprint(lm)
		if fp.size.x > 0.0 and fp.intersects(inner):
			_paint(box, fp, BUILT)
	var building_scene: PackedScene = load("res://scenes/props/building.tscn")
	var entries: Array = []
	var corridor: Array = []
	if as_plaza:
		_plaza(box, brect)
	# The industrial district: Industrial's warehouses (their own footprints) and its yards.
	var ind_entries: Array = Industrial.block_entries(plan, bx, bz) if industrial else []
	var ind_plans := {}
	for e: Dictionary in ind_entries:
		if not (e.plan as Dictionary).is_empty():
			ind_plans[int(e.lot.seed)] = e.plan
	var all_lots: Array = [] if as_plaza else plan.lots(bx, bz)
	# The cells the lot grid left empty hold a house of their own since the house pass.
	if fill >= 2 and not as_plaza and HouseKit.enabled and district in HouseKit.DISTRICTS:
		all_lots.append_array(HouseKit.extra_lots(plan, bx, bz))
	for lot: Dictionary in all_lots:
		var size: Vector2 = lot.size
		var lot_rect := Rect2((lot.center as Vector2) - size * 0.5, size)
		var cell: Rect2 = lot.get("cell", lot_rect)
		out.lots += size.x * size.y
		out.lots_n += 1
		if lot.yard:
			_paint(box, lot_rect, YARD)
			continue
		if YardFill.is_corridor(plan, lot):
			out.freeway = true
			corridor.append(lot)
			if rows:
				_paint(box, cell, ROW)
			else:
				_paint(box, lot_rect, YARD)
			continue
		if filled and lot.get("parking", false):
			_paint(box, cell, PARKING)
			continue
		# A vacant lot or a gravel car park (VacantLots: the lot's whole cell).
		if fill >= 3 and VacantLots.kind_of(plan, bx, bz, lot) != VacantLots.NONE:
			_paint(box, cell, PARKING if VacantLots.kind_of(plan, bx, bz, lot) == VacantLots.PARKING else YARD)
			continue
		# A house of the suburbs or the beach town (HouseKit, the same pure plan the chunk builds).
		if fill >= 2 and HouseKit.enabled and district in HouseKit.DISTRICTS:
			var house := HouseKit.plan_house(plan, bx, bz, lot, district)
			var hground := 0.0
			for r: Rect2 in HouseKit.ground_parts(house):
				_paint(box, r, BUILT)
				hground += r.size.x * r.size.y
			out.lot_built += minf(hground, size.x * size.y)
			if yards:
				entries.append(HouseKit.yard_entry(lot, house))
			var hk: String = row + " house_" + HouseKit.STYLE_NAMES[int(house.style)]
			if not out.shapes.has(hk):
				out.shapes[hk] = [0, 0.0]
			out.shapes[hk][0] += 1
			out.shapes[hk][1] += minf(hground / (size.x * size.y), 1.0)
			continue
		var bld: Building = building_scene.instantiate()
		bld.seed = lot.seed
		bld.lot_size = size
		var target: float = plan.lot_height(lot.seed, district, boost)
		bld.min_height = target * 0.88
		bld.max_height = target
		var sh: Array[int] = []
		sh.assign(CityPlan.lot_shapes(district, boost))
		bld.shape_options = sh
		var fi: Array[int] = []
		fi.assign(CityPlan.lot_finishes(district, boost))
		bld.finish_options = fi
		bld.podium_lot = filled
		if industrial and Industrial.arts(plan, lot.center):
			var bf: Array[int] = [Building.Finish.BRICK, Building.Finish.BRICK, Building.Finish.BRICK, Building.Finish.PANELS]
			bld.finish_options = bf
		bld.plan_only()
		var ground := 0.0
		var parts := YardFill.ground_parts(lot, bld)
		if ind_plans.has(int(lot.seed)):
			parts = [ind_plans[int(lot.seed)].rect]
		for r: Rect2 in parts:
			_paint(box, r, BUILT)
			ground += r.size.x * r.size.y
		out.lot_built += minf(ground, size.x * size.y)
		if filled:
			_paint(box, cell, FORECOURT)
		if yards:
			entries.append({"lot": lot, "parts": parts})
		if int(bld.podium_kind) > 0:
			var pk := row + (" parking" if int(bld.podium_kind) == 2 else " retail")
			out.podiums[pk] = int(out.podiums.get(pk, 0)) + 1
		var sk: String = row + " " + SHAPE_NAMES[int(bld.shape)]
		if not out.shapes.has(sk):
			out.shapes[sk] = [0, 0.0]
		out.shapes[sk][0] += 1
		out.shapes[sk][1] += minf(ground / (size.x * size.y), 1.0)
		bld.free()
	if filled and not as_plaza:
		# What a landmark's square dropped, less the landmark (LotFill.leftovers()).
		var holes: Array[Rect2] = []
		for lm in Landmarks.all():
			if lm.get("area") is Dictionary:
				continue
			var r: float = lm.radius
			var sq := Rect2((lm.anchor as Vector2) - Vector2(r, r), Vector2(r * 2.0, r * 2.0))
			if sq.intersects(brect):
				holes.append(LandmarkDowntown.footprint(lm).grow(4.0) if LandmarkDowntown.is_tower(str(lm.id)) else sq)
		for cell: Rect2 in plan.dropped_cells(bx, bz):
			for piece: Rect2 in LotFill._minus(cell, holes, 0.0):
				_paint(box, piece, FORECOURT)
	if yards and (district == CityPlan.District.BEACHTOWN or district == CityPlan.District.SUBURBS):
		var bp := YardFill.beach_block(plan, bx, bz, entries)
		for lp: Dictionary in bp.lots:
			for pc: Array in lp.pieces:
				_paint(box, pc[0], GARDEN)
		if (bp.walk as Rect2).size.x > 0.0:
			_paint(box, bp.walk, GARDEN)
		for d: Array in bp.dropped:
			_paint(box, d[0], PARKING if d[1] == "parking" else GARDEN)
	elif yards and district == CityPlan.District.CAMPUS:
		var cp := YardFill.campus_block(plan, bx, bz, entries)
		for r: Rect2 in cp.parks:
			_paint(box, r, PARKING)
		for pc: Array in cp.pieces:
			_paint(box, pc[0], GARDEN)
		for r: Rect2 in cp.quads:
			_paint(box, r, GARDEN)
		for r: Rect2 in cp.lawns:
			_paint(box, r, GARDEN)
		# A building's own lot on campus: its walk, apron and service yard are painted above; the
		# rest of its cell is the block's lawn with its foundation planting and trees.
		for e: Dictionary in entries:
			_paint(box, e.lot.get("cell", Rect2()), GARDEN)
	if industrial:
		var bp := Industrial.block_plan(plan, bx, bz, ind_entries)
		for pc: Array in bp.pieces:
			_paint(box, pc[0], WORKS)
		if not (bp.spur as Dictionary).is_empty():
			_paint(box, bp.spur.rect, WORKS)
	var counts := [0, 0, 0, 0, 0, 0, 0, 0, 0]
	var painted: PackedByteArray = box[0]
	for k in painted.size():
		counts[painted[k]] += 1
	out["k"] = counts
	# The same counted inside the right of way's cells alone (the ROW row).
	var row_k := [0, 0, 0, 0, 0, 0, 0, 0, 0]
	if not corridor.is_empty():
		var grid_info := YardFill.lot_grid(plan, bx, bz, plan.lots(bx, bz))
		var cells_r: Array[Rect2] = []
		for lot: Dictionary in corridor:
			cells_r.append(YardFill.cell_rect(grid_info, YardFill.cell_index(grid_info, lot.center)))
		for j in gz:
			for i in gx:
				var p := inner.position + Vector2((i + 0.5) * grid, (j + 0.5) * grid)
				for r: Rect2 in cells_r:
					if r.has_point(p):
						row_k[painted[j * gx + i]] += 1
						break
	out["row_k"] = row_k
	return out


## Paints a world rect into a block's grid (`box` = [cells, inner, grid, gx, gz]) with a kind, only
## over bare ground - built paints over anything.
static func _paint(box: Array, r: Rect2, kind: int) -> void:
	if r.size.x <= 0.0 or r.size.y <= 0.0:
		return
	var cells: PackedByteArray = box[0]
	box[0] = null
	var inner: Rect2 = box[1]
	var grid: float = box[2]
	var gx: int = box[3]
	var gz: int = box[4]
	var i0 := clampi(int((r.position.x - inner.position.x) / grid), 0, gx)
	var i1 := clampi(int(ceil((r.end.x - inner.position.x) / grid)), 0, gx)
	var j0 := clampi(int((r.position.y - inner.position.y) / grid), 0, gz)
	var j1 := clampi(int(ceil((r.end.y - inner.position.y) / grid)), 0, gz)
	for j in range(j0, j1):
		var cz := inner.position.y + (j + 0.5) * grid
		if cz < r.position.y or cz > r.end.y:
			continue
		for i in range(i0, i1):
			var cx := inner.position.x + (i + 0.5) * grid
			if cx < r.position.x or cx > r.end.x:
				continue
			var k := j * gx + i
			if cells[k] == BUILT:
				continue
			if kind == BUILT or cells[k] == BARE:
				cells[k] = kind
	box[0] = cells


## A rec park or a school campus (Parks' pure plan): its buildings, stands and shelters built, its
## car park parking, everything else - fields, courts, the track, the pool, the yard, the walk -
## sport, and a rec park's lawn round them garden. Counted in its district's row and in REC or
## SCHOOL.
static func _grounds(plan: CityPlan, bx: int, bz: int, b: Dictionary, grid: float) -> Dictionary:
	var pl := Parks.plan_for(plan, bx, bz)
	if pl.is_empty():
		pl = Schools.coverage_plan(plan, bx, bz)
	var inner: Rect2 = (b.rect as Rect2).grow(-plan.sidewalk_width)
	var gx := maxi(1, int(inner.size.x / grid))
	var gz := maxi(1, int(inner.size.y / grid))
	var cells := PackedByteArray()
	cells.resize(gx * gz)
	var box := [cells, inner, grid, gx, gz]
	cells = PackedByteArray()
	for f: Dictionary in pl.fac:
		var r: Rect2 = f.r
		match f.t:
			"rec_centre":
				_paint(box, r.grow(-1.0), BUILT)
				_paint(box, r, SPORT)
			"wing":
				_paint(box, Parks._strip(r, int(f.front), Parks.WING_DEPTH), BUILT)
				_paint(box, r, SPORT)
			"bungalow", "bleachers", "picnic", "lunch":
				_paint(box, r, BUILT)
			"parking":
				_paint(box, r, PARKING)
			_:
				_paint(box, r, SPORT)
	if pl.role == "rec" or String(b.get("grounds", "")) == "cemetery":
		_paint(box, inner, GARDEN)
	else:
		_paint(box, inner, SPORT)
	var counts := [0, 0, 0, 0, 0, 0, 0, 0, 0]
	var painted: PackedByteArray = box[0]
	for k in painted.size():
		counts[painted[k]] += 1
	var row: String = DISTRICT_NAMES[int(b.district)]
	return {"row": row, "extra": ["REC" if pl.role == "rec" else "SCHOOL"], "freeway": false, "cells": gx * gz, "lots": 0.0, "lots_n": 0,
		"lot_built": 0.0, "shapes": {}, "podiums": {}, "k": counts, "row_k": [0, 0, 0, 0, 0, 0, 0, 0, 0]}
