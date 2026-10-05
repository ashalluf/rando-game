class_name Schools
extends RefCounted
## Public schools (2026-10-05, owner: "make the graphics a million times better"; GAME_PLAN, the
## schools pass). Los Angeles' neighbourhoods are full of them: an elementary school on its block
## with stucco or mid-century brick classroom wings and covered walkways, a row of portable
## classrooms up on blocks with their ramps, a blacktop painted with hopscotch, four-square, a map
## and basketball courts, a play structure, a grass field with a backstop, the lunch shelter, the
## flagpole and the marquee sign; and the big high schools - a gym, an auditorium with its fly
## tower, a two-storey classroom block, a stadium (a track round the football field, bleachers both
## sides, a press box, a scoreboard and light standards lit on game nights), tennis courts, a car
## park - which take two or three blocks and close the streets between them.
##
## WHERE is worked out, never placed (FireStation's approach): the map is cut into CELL squares; a
## hash of the seed and the cell says whether it has a school, what kind, and picks a point in it;
## the block under the point (and for a high school one or two blocks beside it in a row, all in
## the same cell) becomes the school if every block is plain city ground in SCHOOL_DISTRICTS -
## buildings or a park nobody else has claimed (Parks' rec parks and campuses, landmarks, sites,
## the replica, the river, the freeway, the light rail, the approach). CityPlan.block() hands every
## block it makes to apply() AFTER its own rolls and overrides (and Parks'), so no seed moves: the
## block becomes BlockKind.SCHOOL with grounds "school_e" / "school_h" and CityPlan.lots() is empty
## there. The streets between a high school's blocks are closed (road_closed(), CityPlan.road_open()).
## Re-entrancy: deciding a cell asks the plan for its blocks, and apply() is a no-op while a
## decision is running (`_deciding`); the decision then marks the blocks itself. Only blocks whose
## centre lies in the cell are ever asked for, so a block is always decided before anyone sees it.
##
## The plan is PURE (plan_for(): hashes of seed + cell, never a chunk or block rng), laid out in the
## site's street frame. Drawn: the ground into the Parks ground mesh (shaders/park_ground.gdshader:
## turf, courts, the track, rubber, asphalt, the yard games, the painted map G_MAP), sports kit into
## the Parks walls mesh (ParkKit), the buildings, signs, flags, portables and stadium lights into ONE
## mesh of their own (SchoolKit, shaders/school_walls.gdshader). A high school spans chunks: every
## ground piece is clipped to the chunk's owned rect and every upright piece built by the chunk its
## anchor is in, so each chunk builds exactly its own part at any level. LOD chunks and the far city
## get the ground as slabs (partitioned) and the buildings as far boxes.
##
## Names are invented (SCHOOL_NAMES + "ELEMENTARY" / "HIGH SCHOOL", or the front street's name),
## mascots invented; never a real school's or district's name. No children: the campus is the empty
## look of a school at the weekend or in class time.

## Off (SCHOOLS=0 in the environment): no block becomes a school (the A/B for stills and counts).
static var enabled: bool = OS.get_environment("SCHOOLS") != "0"

const CELL := 640.0
## Points tried in a cell before it is given up.
const TRIES := 3
## Odds a cell has a school, and that it is a high school (when its blocks allow one).
const ODDS := 0.8
const HIGH_ODDS := 0.4
const SCHOOL_DISTRICTS := [CityPlan.District.SUBURBS, CityPlan.District.MIDTOWN, CityPlan.District.BEACHTOWN]
## Smallest site (inside the pavement): an elementary block, a high school's row of blocks.
const ELEM_MIN := Vector2(50.0, 62.0)
const HIGH_MIN := Vector2(72.0, 175.0)
## Largest site: past this a block is a stretched one (pinned real roads) and would be mostly empty.
const ELEM_MAX := 190.0
const HIGH_MAX := 320.0
## A street a high school may close: no wider than a local street, and never a pinned real road.
const MAX_CLOSED_WIDTH := 15.5

# --- Real sizes (metres) -------------------------------------------------------------------------
const STOREY := 4.0
const WING_DEPTH := 10.0
const WALKWAY := 3.2
const SETBACK := 4.5
## A portable classroom: 40 x 24 ft, 0.6 m up on its blocks; its ramp runs along the long side.
const PORTABLE := Vector2(12.2, 7.3)
const PORTABLE_RISE := 0.62
const RAMP_W := 1.25
## The gym (a high school's: two courts across, bleachers) and the auditorium.
const GYM := Vector2(46.0, 34.0)
const GYM_H := 11.5
const AUD := Vector2(28.0, 40.0)
const AUD_H := 9.0
const FLY_H := 19.0
## The painted map on an elementary blacktop.
const MAP := Vector2(15.0, 9.0)
## The bus loading zone along the front kerb (m) and the most buses parked in it.
const BUS_ZONE := 42.0
const MAX_BUSES := 3

## National school bus yellow (paint), and the bell: school buses run in traffic within BUS_REACH of
## a school between these hours (morning drop-off, afternoon pick-up), BUS_SHARE of street spawns.
const BUS_YELLOW := Color(0.96, 0.66, 0.02)
const BUS_HOURS := [Vector2(6.8, 8.6), Vector2(14.2, 16.2)]
const BUS_REACH := 1400.0
const BUS_SHARE := 0.07
## Hour forced for tests and stills (-1: the city's clock).
static var force_hour: float = -1.0

## The ground kind for the painted map (shaders/park_ground.gdshader; Parks.G_* end at 12).
const G_MAP := 13

const SCHOOL_NAMES := ["Sycamore Grove", "Mesa Vista", "Arroyo Seco", "Laurel Canyon", "Rio Hondo", "Harbor Crest",
	"Canyon View", "Pacific Heights", "Valley Oak", "Toyon", "Manzanita", "Live Oak", "Coyote Hills", "Bay Shore",
	"Mar Vista Park", "Hillcrest", "Sunset Ridge", "Palisade", "El Camino Real", "Rancho Verde", "La Brea Flats",
	"Cypress Point", "Lomita Terrace", "Ocean Air", "Jacaranda", "Mission Bell", "Highland Park", "Fremont Hill"]
const MASCOTS := ["CONDORS", "COYOTES", "MUSTANGS", "PELICANS", "BOBCATS", "SEA LIONS", "HAWKS", "GRIZZLIES",
	"MARLINS", "RATTLERS", "ROADRUNNERS", "OWLS"]
## Marquee messages (the LED board under the name).
const MESSAGES_E := ["WELCOME BACK", "BOOK FAIR FRI", "PICTURE DAY", "GO GREEN WEEK", "SCIENCE NIGHT", "NO SCHOOL MON"]
const MESSAGES_H := ["HOMECOMING FRI", "GO {M}!", "FINALS WEEK", "SENIOR NIGHT", "BAND CONCERT", "CLASS OF 27"]

## Classroom wall finishes: stucco (paint) or mid-century brick; the trim in the school colour.
const STUCCO := [Color(0.86, 0.80, 0.68), Color(0.90, 0.86, 0.76), Color(0.80, 0.74, 0.62), Color(0.84, 0.78, 0.70),
	Color(0.78, 0.82, 0.78), Color(0.88, 0.80, 0.70), Color(0.92, 0.90, 0.84)]
const BRICK := [Color(0.62, 0.36, 0.28), Color(0.70, 0.46, 0.36), Color(0.56, 0.40, 0.34), Color(0.78, 0.66, 0.52)]
const COLOURS := [Color(0.55, 0.10, 0.12), Color(0.10, 0.20, 0.45), Color(0.08, 0.36, 0.20), Color(0.62, 0.40, 0.06),
	Color(0.32, 0.12, 0.40), Color(0.85, 0.42, 0.08), Color(0.10, 0.36, 0.48), Color(0.45, 0.06, 0.10)]
const PORTABLE_PAINTS := [Color(0.80, 0.74, 0.62), Color(0.74, 0.70, 0.60), Color(0.84, 0.80, 0.70), Color(0.70, 0.66, 0.56)]

## Tree wells on the blacktop: their grid pitch (m) and the most a school gets.
const TREE_WELL_STEP := 15.0
const MAX_TREE_WELLS := 10

## Far colours (LOD chunks and the far city), as Parks' are tuned.
const FAR_ROOF := Color(0.64, 0.64, 0.62)

static var _cells: Dictionary = {}
static var _plans: Dictionary = {}
static var _closed: Dictionary = {}
static var _deciding: bool = false
## Why cells came out empty (tools/schools/probe.gd prints it).
static var why: Dictionary = {}


static func _no(reason: String) -> void:
	why[reason] = int(why.get(reason, 0)) + 1


static func _h01(parts: Array) -> float:
	return float(absi(hash(parts)) % 100003) / 100003.0


static func _cell_of(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / CELL), floori(p.y / CELL))


## Block (ix, iz)'s rect between the kerbs, worked out from the roads alone (CityPlan.block()'s).
static func _block_rect(plan: CityPlan, k: Vector2i) -> Rect2:
	var x0 := plan.road_pos(CityPlan.AXIS_X, k.x) + plan.road_width(CityPlan.AXIS_X, k.x) * 0.5
	var x1 := plan.road_pos(CityPlan.AXIS_X, k.x + 1) - plan.road_width(CityPlan.AXIS_X, k.x + 1) * 0.5
	var z0 := plan.road_pos(CityPlan.AXIS_Z, k.y) + plan.road_width(CityPlan.AXIS_Z, k.y) * 0.5
	var z1 := plan.road_pos(CityPlan.AXIS_Z, k.y + 1) - plan.road_width(CityPlan.AXIS_Z, k.y + 1) * 0.5
	return Rect2(x0, z0, x1 - x0, z1 - z0)


# --- Placement --------------------------------------------------------------------------------

## CityPlan.block()'s hook, after the block is made and cached: marks it a school when its cell's
## school takes it.
static func apply(plan: CityPlan, b: Dictionary) -> void:
	if _deciding or plan.macro == null:
		return
	var d := decide(plan, _cell_of((b.rect as Rect2).get_center()))
	if d.is_empty() or not (d.blocks as Array).has(Vector2i(int(b.ix), int(b.iz))):
		return
	_mark(b, d)


static func _mark(b: Dictionary, d: Dictionary) -> void:
	b.kind = CityPlan.BlockKind.SCHOOL
	b.grounds = "school_h" if d.high else "school_e"
	b.school = d.cell


## The school of grid cell `cell`: {} or {"cell", "high", "blocks" (a row, west/north first),
## "axis" (the row runs along x: 0, z: 1), "roads" (the closed roads' indices)}. Cached per seed.
static func decide(plan: CityPlan, cell: Vector2i) -> Dictionary:
	var key := Vector3i(plan.seed, cell.x, cell.y)
	if _cells.has(key):
		return _cells[key]
	var out := {}
	_cells[key] = out
	if not enabled or plan.macro == null:
		return out
	if _h01([plan.seed, cell.x, cell.y, "school"]) > ODDS:
		_no("odds")
		return out
	var want_high := _h01([plan.seed, cell.x, cell.y, "sc_high"]) < HIGH_ODDS
	var cache := {}
	for attempt in TRIES:
		_try(plan, cell, attempt, want_high, cache, out)
		if not out.is_empty():
			break
	if out.is_empty():
		return out
	for k: Vector2i in out.blocks:
		_mark(cache[k], out)
	for i in (out.roads as Array).size():
		var k: Vector2i = out.blocks[i]
		_closed[Vector3i(int(out.axis), int(out.roads[i]), k.y if int(out.axis) == 0 else k.x)] = true
	return out


## One try at cell `cell`'s school: a point in the cell from the hash, the block under it, a row
## for a high school when one is wanted and fits, else an elementary school on the block.
static func _try(plan: CityPlan, cell: Vector2i, attempt: int, want_high: bool, cache: Dictionary, out: Dictionary) -> void:
	var target := Vector2((float(cell.x) + lerpf(0.15, 0.85, _h01([plan.seed, cell.x, cell.y, attempt, "sc_x"]))) * CELL,
			(float(cell.y) + lerpf(0.15, 0.85, _h01([plan.seed, cell.x, cell.y, attempt, "sc_z"]))) * CELL)
	if plan.zone_at(target) != MacroMap.Zone.CITY:
		_no("zone")
		return
	var a := plan.block_index_at(target)
	if _cell_of(_block_rect(plan, a).get_center()) != cell:
		_no("cell")
		return
	var rows: Array = []
	if want_high:
		var dirs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, 1)]
		if _h01([plan.seed, cell.x, cell.y, "sc_dir"]) < 0.5:
			dirs.reverse()
		for d: Vector2i in dirs:
			for n: int in [3, 2]:
				for off in n:
					var row: Array[Vector2i] = []
					for i in n:
						row.append(a - d * off + d * i)
					if _row_fits(plan, cell, row, d):
						rows.append([row, d])
	# Ask the plan for every block that may be taken, with apply() off (they are in this cell).
	_deciding = true
	for r: Array in rows:
		for k: Vector2i in r[0]:
			if not cache.has(k):
				cache[k] = plan.block(k.x, k.y)
	if not cache.has(a):
		cache[a] = plan.block(a.x, a.y)
	_deciding = false
	for r: Array in rows:
		var row: Array = r[0]
		var d: Vector2i = r[1]
		var site := _union(plan, row)
		var ok := true
		for k: Vector2i in row:
			if not _eligible(plan, cache[k], site):
				ok = false
				break
		if ok:
			var roads: Array[int] = []
			for i in range(1, row.size()):
				var k: Vector2i = row[i]
				roads.append(k.x if d.x == 1 else k.y)
			out.merge({"cell": cell, "high": true, "blocks": row, "axis": 0 if d.x == 1 else 1, "roads": roads})
			return
	var inner := (cache[a].rect as Rect2).grow(-plan.sidewalk_width)
	if minf(inner.size.x, inner.size.y) < ELEM_MIN.x or maxf(inner.size.x, inner.size.y) < ELEM_MIN.y or maxf(inner.size.x, inner.size.y) > ELEM_MAX:
		_no("small")
		return
	if not _eligible(plan, cache[a], inner):
		_no("ineligible")
		return
	var one: Array[Vector2i] = [a]
	var none: Array[int] = []
	out.merge({"cell": cell, "high": false, "blocks": one, "axis": -1, "roads": none})


## A row of blocks a high school could take: all in `cell`, the streets between them local and not
## real (pinned) roads, the site big enough for a track and a campus.
static func _row_fits(plan: CityPlan, cell: Vector2i, row: Array[Vector2i], d: Vector2i) -> bool:
	for k: Vector2i in row:
		if _cell_of(_block_rect(plan, k).get_center()) != cell:
			return false
	for i in range(1, row.size()):
		var k: Vector2i = row[i]
		var axis := CityPlan.AXIS_X if d.x == 1 else CityPlan.AXIS_Z
		var index := k.x if d.x == 1 else k.y
		if plan.road_width(axis, index) > MAX_CLOSED_WIDTH:
			return false
		if not DowntownReal.pin_at(axis, plan.road_pos(axis, index)).is_empty():
			return false
	var site := _union(plan, row)
	return minf(site.size.x, site.size.y) >= HIGH_MIN.x and maxf(site.size.x, site.size.y) >= HIGH_MIN.y \
		and maxf(site.size.x, site.size.y) <= HIGH_MAX and minf(site.size.x, site.size.y) <= HIGH_MAX * 0.6


## The site of a row of blocks: inside the outer pavements, across the closed streets.
static func _union(plan: CityPlan, row: Array) -> Rect2:
	var r := Rect2()
	for i in row.size():
		var b := _block_rect(plan, row[i]).grow(-plan.sidewalk_width)
		r = b if i == 0 else r.merge(b)
	return r


## Plain city ground no one else has a claim on (Parks' role_for list, and the river).
static func _eligible(plan: CityPlan, b: Dictionary, site: Rect2) -> bool:
	var macro: MacroMap = plan.macro
	var rect: Rect2 = b.rect
	if not (int(b.district) in SCHOOL_DISTRICTS):
		return false
	if b.has("site") or b.has("grounds") or b.get("was_plaza", false):
		return false
	if int(b.kind) != CityPlan.BlockKind.BUILDINGS and int(b.kind) != CityPlan.BlockKind.PARK:
		return false
	for p: Vector2 in [rect.position, rect.end, Vector2(rect.end.x, rect.position.y), Vector2(rect.position.x, rect.end.y), rect.get_center()]:
		if macro.zone_at(p) != MacroMap.Zone.CITY:
			return false
	var area := site.grow(plan.sidewalk_width)
	if DowntownReal.in_extent(rect.get_center()) or Landmarks.claims(rect):
		return false
	if macro.freeway and macro.freeway.blocks_rect(area, 8.0):
		return false
	var rail := LightRail.of(plan)
	if rail != null and (rail.blocks_rect(area, 8.0) or not rail.cuts_in(area).is_empty()):
		return false
	if macro.runway_clear_zone().grow(80.0).intersects(area):
		return false
	if macro.replica and macro.replica._bounds.intersects(area.grow(40.0)):
		return false
	var ix := int(b.ix)
	var iz := int(b.iz)
	if not plan.site_at_block(ix, iz).is_empty() or plan._beside_site(ix, iz):
		return false
	if plan.river_block(ix, iz):
		return false
	if _fire_station_block(plan, Vector2i(ix, iz)):
		return false
	for lm in Landmarks.all():
		if lm.get("area") is Dictionary:
			continue
		var r: float = lm.radius
		if Rect2((lm.anchor as Vector2) - Vector2(r, r), Vector2(r, r) * 2.0).intersects(area):
			return false
	return true


## Whether block `k` is the one its fire-station cell points at (FireStation.for_cell()'s target,
## worked out from the hashes and the roads alone - asking FireStation would ask the plan for
## blocks outside the deciding cell). A school never takes it, so no station moves.
static func _fire_station_block(plan: CityPlan, k: Vector2i) -> bool:
	if not FireStation.enabled:
		return false
	var c := FireStation._cell_of(_block_rect(plan, k).get_center())
	if FireStation._h01([plan.seed, c.x, c.y, "fire_station"]) > FireStation.ODDS:
		return false
	var target := Vector2((float(c.x) + lerpf(0.25, 0.75, FireStation._h01([plan.seed, c.x, c.y, "fs_x"]))) * FireStation.CELL,
			(float(c.y) + lerpf(0.25, 0.75, FireStation._h01([plan.seed, c.x, c.y, "fs_z"]))) * FireStation.CELL)
	return plan.block_index_at(target) == k


## The decision whose blocks include block (bx, bz), or {}.
static func school_at(plan: CityPlan, bx: int, bz: int) -> Dictionary:
	var b := plan.block(bx, bz)
	if not b.has("school"):
		return {}
	return decide(plan, b.school)


## CityPlan.road_open()'s hook: true on a street a high school closed, between its blocks.
static func road_closed(plan: CityPlan, axis: int, index: int, along: float) -> bool:
	if _deciding or plan.macro == null:
		return false
	# Every road a school closed is registered when its cell is decided; a cell nobody has asked
	# about is decided here, from the two blocks the road runs between at `along`.
	var other := plan._index_at(1 - axis, along)
	var key := Vector3i(axis, index, other)
	if _closed.has(key):
		return _block_span(plan, axis, index, other, along)
	var probe := Vector2(plan.road_pos(axis, index) - 1.0, along) if axis == CityPlan.AXIS_X else Vector2(along, plan.road_pos(axis, index) - 1.0)
	# A high school's row runs up to two blocks either side of the block under its cell's target
	# point, so the blocks beside this road may belong to the cell next door. Decide every cell
	# round the road before answering: deciding only the two blocks' own cells cached "open" here,
	# and a later decision of the neighbour closed it (the map then drew a closed road).
	var c := _cell_of(probe)
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			decide(plan, c + Vector2i(dx, dz))
	if not _closed.has(key):
		_closed[key] = false
		return false
	return _block_span(plan, axis, index, other, along)


## Whether `along` lies along a closed road's block (not in the open crossings at its ends).
static func _block_span(plan: CityPlan, axis: int, index: int, other: int, along: float) -> bool:
	if not _closed[Vector3i(axis, index, other)]:
		return false
	var o := 1 - axis
	var lo := plan.road_pos(o, other) + plan.road_width(o, other) * 0.5
	var hi := plan.road_pos(o, other + 1) - plan.road_width(o, other + 1) * 0.5
	return along > lo and along < hi


## True where a parked car may not stand (CityChunk._park_car, after its rolls): on a closed
## street, or in a school's bus loading zone.
static func keeps_clear(plan: CityPlan, p: Vector2) -> bool:
	if not enabled or plan.macro == null:
		return false
	var c := _cell_of(p)
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var d := decide(plan, c + Vector2i(dx, dz))
			if d.is_empty():
				continue
			var pl := plan_for_school(plan, d)
			if pl.is_empty():
				continue
			for z: Rect2 in pl.closed_strips:
				if z.grow(0.5).has_point(p):
					return true
			if (pl.bus_rect as Rect2).has_point(p):
				return true
	return false


# --- The plan ------------------------------------------------------------------------------------

## The plan of block (bx, bz)'s school (shared by the blocks of a high school), or {}.
static func plan_for(plan: CityPlan, bx: int, bz: int) -> Dictionary:
	var d := school_at(plan, bx, bz)
	if d.is_empty():
		return {}
	return plan_for_school(plan, d)


## Frame helpers: the site's street frame. `s` along the front street, `d` in from it.
static func _fr(site: Rect2, front: int) -> Dictionary:
	match front:
		0:
			return {"o": site.position, "s": Vector2(1, 0), "d": Vector2(0, 1), "A": site.size.x, "D": site.size.y}
		1:
			return {"o": Vector2(site.position.x, site.end.y), "s": Vector2(1, 0), "d": Vector2(0, -1), "A": site.size.x, "D": site.size.y}
		2:
			return {"o": site.position, "s": Vector2(0, 1), "d": Vector2(1, 0), "A": site.size.y, "D": site.size.x}
	return {"o": Vector2(site.end.x, site.position.y), "s": Vector2(0, 1), "d": Vector2(-1, 0), "A": site.size.y, "D": site.size.x}


## A world rect from the frame's (s0..s1, d0..d1).
static func _lr(f: Dictionary, s0: float, s1: float, d0: float, d1: float) -> Rect2:
	var o: Vector2 = f.o
	var p: Vector2 = o + (f.s as Vector2) * s0 + (f.d as Vector2) * d0
	var q: Vector2 = o + (f.s as Vector2) * s1 + (f.d as Vector2) * d1
	var lo := Vector2(minf(p.x, q.x), minf(p.y, q.y))
	return Rect2(lo, Vector2(maxf(p.x, q.x), maxf(p.y, q.y)) - lo)


static func _lp(f: Dictionary, s: float, d: float) -> Vector2:
	return (f.o as Vector2) + (f.s as Vector2) * s + (f.d as Vector2) * d


## A building facility: world rect, its face toward the yard / street, storeys, finish.
static func _bld(t: String, r: Rect2, out_dir: Vector2, storeys: int, extra: Dictionary = {}) -> Dictionary:
	var f := {"t": t, "r": r, "c": r.get_center(), "out": out_dir, "storeys": storeys}
	f.merge(extra)
	return f


static func plan_for_school(plan: CityPlan, d: Dictionary) -> Dictionary:
	var key := Vector3i(plan.seed, (d.cell as Vector2i).x, (d.cell as Vector2i).y)
	if _plans.has(key):
		return _plans[key]
	var row: Array = d.blocks
	var site := _union(plan, row)
	var cell: Vector2i = d.cell
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([plan.seed, cell.x, cell.y, "school_plan"])
	var first: Vector2i = row[0]
	var last: Vector2i = row[row.size() - 1]
	# The front: the widest street on a long side (on an elementary block, any side).
	var sides: Array = []
	var long_x := site.size.x >= site.size.y
	var cand: Array = [0, 1] if long_x else [2, 3]
	if not d.high:
		cand = [0, 1, 2, 3]
	for s: int in cand:
		var w := 0.0
		match s:
			0:
				w = plan.road_width(CityPlan.AXIS_Z, first.y)
			1:
				w = plan.road_width(CityPlan.AXIS_Z, last.y + 1)
			2:
				w = plan.road_width(CityPlan.AXIS_X, first.x)
			3:
				w = plan.road_width(CityPlan.AXIS_X, last.x + 1)
		sides.append([w + rng.randf() * 0.5, s])
	sides.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) > float(b[0]))
	var front: int = sides[0][1]
	var fr := _fr(site, front)
	var colour_i := rng.randi() % COLOURS.size()
	var brick := rng.randf() < 0.42
	var paint: Color = (BRICK[rng.randi() % BRICK.size()] if brick else STUCCO[rng.randi() % STUCCO.size()])
	var name_i := absi(hash([plan.seed, cell.x, cell.y, "school_name"])) % SCHOOL_NAMES.size()
	var mascot: String = MASCOTS[absi(hash([plan.seed, cell.x, cell.y, "mascot"])) % MASCOTS.size()]
	var school_name: String = SCHOOL_NAMES[name_i]
	if _h01([plan.seed, cell.x, cell.y, "street_name"]) < 0.3:
		# Named after the street out front, the way LA's are ("Third Street Elementary").
		var road := _front_road(plan, row, front)
		var street := plan.road_name(int(road[0]), int(road[1]))
		if street.get_slice_count(" ") > 1:
			street = street.substr(0, street.rfind(" "))
		if street.length() >= 3 and street.length() <= 16 and street.unicode_at(0) >= 65:
			school_name = street + (" Street" if not d.high else "")
	var msgs: Array = MESSAGES_H if d.high else MESSAGES_E
	var message: String = (msgs[rng.randi() % msgs.size()] as String).replace("{M}", mascot)
	var pl := {"high": d.high, "site": site, "front": front, "fr": fr, "fac": [], "colour": COLOURS[colour_i], "colour_i": colour_i,
		"brick": brick, "paint": paint, "name": school_name.to_upper(), "full_name": school_name.to_upper() + (" HIGH SCHOOL" if d.high else " ELEMENTARY SCHOOL"),
		"mascot": mascot, "message": message, "role": "school", "blocks": row, "cell": cell,
		"game_night": _h01([plan.seed, cell.x, cell.y, "game_night"]) < 0.75, "lit": true,
		"closed_strips": [], "front_road": _front_road(plan, row, front)}
	# The closed streets between the blocks, kerb to kerb.
	var strips: Array[Rect2] = []
	for i in range(1, row.size()):
		var k: Vector2i = row[i]
		var prev := _block_rect(plan, row[i - 1])
		var here := _block_rect(plan, k)
		if int(d.axis) == 0:
			strips.append(Rect2(prev.end.x, maxf(prev.position.y, here.position.y), here.position.x - prev.end.x, minf(prev.end.y, here.end.y) - maxf(prev.position.y, here.position.y)))
		else:
			strips.append(Rect2(maxf(prev.position.x, here.position.x), prev.end.y, minf(prev.end.x, here.end.x) - maxf(prev.position.x, here.position.x), here.position.y - prev.end.y))
	pl.closed_strips = strips
	if d.high:
		_plan_high(pl, rng)
	else:
		_plan_elementary(pl, rng)
	# The bus loading zone: along the front kerb in front of the main building.
	var road: Array = pl.front_road
	var rp := plan.road_pos(int(road[0]), int(road[1]))
	var rw := plan.road_width(int(road[0]), int(road[1]))
	var bus_s: float = pl.get("bus_s", fr.A * 0.5)
	var zone_len := minf(BUS_ZONE, fr.A - 16.0)
	var p0 := _lp(fr, bus_s - zone_len * 0.5, 0.0)
	var p1 := _lp(fr, bus_s + zone_len * 0.5, 0.0)
	var kerb_off := rw * 0.5 - CityPlan.PARKING_LANE
	var zr: Rect2
	if int(road[0]) == CityPlan.AXIS_X:
		var x_side := rp + (kerb_off + CityPlan.PARKING_LANE * 0.5) * signf(site.get_center().x - rp)
		zr = Rect2(Vector2(x_side - 1.8, minf(p0.y, p1.y)), Vector2(3.6, absf(p1.y - p0.y)))
	else:
		var z_side := rp + (kerb_off + CityPlan.PARKING_LANE * 0.5) * signf(site.get_center().y - rp)
		zr = Rect2(Vector2(minf(p0.x, p1.x), z_side - 1.8), Vector2(absf(p1.x - p0.x), 3.6))
	pl.bus_rect = zr
	pl.bus_axis = int(road[0])
	pl.buses = 1 + absi(hash([plan.seed, cell.x, cell.y, "buses"])) % MAX_BUSES
	_plans[key] = pl
	return pl


## [axis, index] of the street along the front.
static func _front_road(plan: CityPlan, row: Array, front: int) -> Array:
	var first: Vector2i = row[0]
	var last: Vector2i = row[row.size() - 1]
	match front:
		0:
			return [CityPlan.AXIS_Z, first.y]
		1:
			return [CityPlan.AXIS_Z, last.y + 1]
		2:
			return [CityPlan.AXIS_X, first.x]
	return [CityPlan.AXIS_X, last.x + 1]


## An elementary school: the main wing along the front (the office by the entry, classrooms
## beyond), a side wing down one edge, the blacktop behind with its courts, games, the map, the
## lunch shelter and the play structure, a grass field with a backstop at the back, a row of
## portables along the back or the far side, a staff car park.
static func _plan_elementary(pl: Dictionary, rng: RandomNumberGenerator) -> void:
	var fr: Dictionary = pl.fr
	var A: float = fr.A
	var D: float = fr.D
	var fac: Array = pl.fac
	var storeys := 2 if rng.randf() < 0.35 else 1
	var flip := rng.randf() < 0.5
	# s measured from the flip end, so the layout mirrors.
	var sx := func(s0: float, s1: float) -> Vector2:
		return Vector2(A - s1, A - s0) if flip else Vector2(s0, s1)
	var b0 := SETBACK
	var b1 := SETBACK + WING_DEPTH
	var w1 := b1 + WALKWAY
	# The staff car park at the far end of the front band, when there is room.
	var park_len := 0.0
	if A >= 84.0:
		park_len = clampf(A * 0.24, 20.0, 30.0)
	var main_len := A - park_len - (3.0 if park_len > 0.0 else 0.0)
	# The office: one storey, glazed entry, by the gate.
	var office_len := minf(16.0, main_len * 0.3)
	var gate := 6.0
	var so: Vector2 = sx.call(0.0, office_len)
	fac.append(_bld("office", _lr(fr, so.x, so.y, b0, b1), -(fr.d as Vector2), 1, {"walk": _lr(fr, so.x, so.y, b1, w1)}))
	# Classroom wings along the rest of the front: runs of 28-46 m with 6 m breezeways between
	# (gated in the fence line), alternating one and two storeys when the school has both.
	var at := office_len + gate
	var wi := 0
	while main_len - at >= 16.0:
		var len := minf(rng.randf_range(28.0, 46.0), main_len - at)
		if main_len - at - len < 22.0:
			len = main_len - at
		var sc: Vector2 = sx.call(at, at + len)
		var st := storeys if wi % 2 == 0 else 1
		fac.append(_bld("classroom", _lr(fr, sc.x, sc.y, b0, b1), -(fr.d as Vector2), st, {"walk": _lr(fr, sc.x, sc.y, b1, w1), "doors_out": fr.d}))
		at += len + 6.0
		wi += 1
	var sg: Vector2 = sx.call(office_len, office_len + gate)
	fac.append({"t": "entry", "r": _lr(fr, sg.x, sg.y, b0, w1)})
	pl.bus_s = (sg.x + sg.y) * 0.5
	if park_len > 0.0:
		var sp: Vector2 = sx.call(A - park_len, A)
		fac.append({"t": "parking", "r": _lr(fr, sp.x, sp.y, b0, minf(D * 0.4, w1 + 8.0))})
	# The front lawn and its sign, flagpole and trees.
	fac.append({"t": "lawn", "r": _lr(fr, 0.0, A, 0.0, SETBACK), "gate_s": (sg.x + sg.y) * 0.5})
	# The side wing down the flip end, its walkway toward the yard.
	var yard_d0 := w1 + 3.0
	var side_len := clampf((D - yard_d0) * 0.5, 0.0, 44.0)
	var placed: Array = []
	for f: Dictionary in fac:
		placed.append((f.r as Rect2))
	if side_len >= 18.0:
		var ss: Vector2 = sx.call(0.0, WING_DEPTH)
		var sw: Vector2 = sx.call(WING_DEPTH, WING_DEPTH + WALKWAY)
		var r := _lr(fr, ss.x, ss.y, yard_d0, yard_d0 + side_len)
		var out_dir: Vector2 = (fr.s as Vector2) * (-1.0 if flip else 1.0)
		fac.append(_bld("classroom", r, out_dir, 1, {"walk": _lr(fr, sw.x, sw.y, yard_d0, yard_d0 + side_len), "doors_out": out_dir, "mural": true}))
		placed.append(r)
		placed.append(_lr(fr, sw.x, sw.y, yard_d0, yard_d0 + side_len))
	var yard := _lr(fr, 0.0, A, yard_d0, D).grow(-1.5)
	pl.yard = yard
	var back := _lp(fr, A * 0.5, D)
	var near := _lp(fr, A * 0.5, yard_d0)
	var far_end := _lp(fr, 0.0 if flip else A, D)
	# Portables in a row along the back edge.
	for n in [5, 4, 3, 2]:
		var fit := Parks._fit(yard, placed, float(n) * PORTABLE.x + float(n - 1) * 3.0, PORTABLE.y + RAMP_W + 1.8, 2.0, true, _lp(fr, 0.0 if not flip else A, D))
		if not fit.is_empty():
			var r: Rect2 = fit.r
			fac.append({"t": "portables", "r": r, "n": n, "long_x": fit.long_x, "paint": PORTABLE_PAINTS[rng.randi() % PORTABLE_PAINTS.size()]})
			placed.append(r)
			break
	# The grass field with its backstop, the biggest that fits at the back.
	for sz: Vector2 in [Vector2(70.0, 50.0), Vector2(60.0, 44.0), Vector2(50.0, 38.0), Vector2(42.0, 32.0), Vector2(34.0, 26.0)]:
		var fit := Parks._fit(yard, placed, sz.x, sz.y, 3.0, true, far_end)
		if not fit.is_empty():
			var f := Parks._fac("field", fit.r, fit.long_x)
			fac.append(f)
			placed.append(f.r)
			break
	# Courts on the blacktop by the wings.
	var court := Parks._fit(yard, placed, Parks.BB_COURT.x + Parks.BB_CLEAR * 2.0, (Parks.BB_COURT.y + Parks.BB_CLEAR * 2.0) * 2.0, 1.5, true, near)
	if court.is_empty():
		court = Parks._fit(yard, placed, Parks.BB_COURT.x + Parks.BB_CLEAR * 2.0, Parks.BB_COURT.y + Parks.BB_CLEAR * 2.0, 1.5, true, near)
	if not court.is_empty():
		var f := Parks._fac("basketball", court.r, Parks._along_x(court.r, Parks.BB_COURT.x + Parks.BB_CLEAR * 2.0))
		f.n = 2 if minf(court.r.size.x, court.r.size.y) > Parks.BB_COURT.y * 1.6 + 6.0 else 1
		f.yard = true
		f.pal = 0
		fac.append(f)
		placed.append(f.r)
	for t: String in ["games", "map", "lunch", "playground", "games"]:
		var size := Vector2(16.0, 12.0)
		match t:
			"map":
				size = MAP + Vector2(2.0, 2.0)
			"lunch":
				size = Vector2(18.0, 10.0)
			"playground":
				size = Vector2(22.0, 15.0)
		var fit := Parks._fit(yard, placed, size.x, size.y, 2.0, true, near if t != "playground" else back)
		if fit.is_empty():
			continue
		var f := Parks._fac(t, fit.r, fit.long_x)
		f.pal = rng.randi() % 4
		fac.append(f)
		placed.append(f.r)
	# Shade trees and a few lunch tables round the yard's edge come at build time (planting).


## A high school: the stadium at one end; the classroom block along the front, the auditorium at
## the corner, the office and library by the entry, the gym behind, tennis courts, outdoor courts,
## the lunch quad and the student car park.
static func _plan_high(pl: Dictionary, rng: RandomNumberGenerator) -> void:
	var fr: Dictionary = pl.fr
	var A: float = fr.A
	var D: float = fr.D
	var fac: Array = pl.fac
	var flip := rng.randf() < 0.5
	var sx := func(s0: float, s1: float) -> Vector2:
		return Vector2(A - s1, A - s0) if flip else Vector2(s0, s1)
	# The stadium: a track sized to the depth and up to 190 m of the length.
	var lt := clampf(A * 0.6, 120.0, 192.0)
	lt = minf(lt, A - 70.0)
	var st: Vector2 = sx.call(A - lt, A)
	var t_area := _lr(fr, st.x, st.y, 0.0, D)
	var t := Parks._track(t_area, rng)
	var placed: Array = []
	if not t.is_empty():
		t.colour = pl.colour
		t.stand_side_world = t.get("stand_side", 1.0)
		fac.append(t)
		placed.append(t.r)
		if t.has("stands"):
			var s := Parks._fac("bleachers", t.stands, (t.stands as Rect2).size.x >= (t.stands as Rect2).size.y)
			s.big = true
			s.colour = pl.colour
			s.facing = t.c
			fac.append(s)
			placed.append(s.r)
	var cl := A - lt - 3.0
	var b0 := SETBACK
	# The classroom block along the front, two storeys, a courtyard walkway behind.
	var aud_w := AUD.x
	var office_len := 18.0
	var gate := 7.0
	var cls_len := cl - aud_w - office_len - gate - 4.0
	var s_cls: Vector2 = sx.call(0.0, cls_len)
	var bd := WING_DEPTH + 4.0
	var at := 0.0
	while cls_len - at >= 16.0:
		var len := minf(rng.randf_range(40.0, 60.0), cls_len - at)
		if cls_len - at - len < 24.0:
			len = cls_len - at
		var sc: Vector2 = sx.call(at, at + len)
		fac.append(_bld("classroom", _lr(fr, sc.x, sc.y, b0, b0 + bd), -(fr.d as Vector2), 2,
			{"walk": _lr(fr, sc.x, sc.y, b0 + bd, b0 + bd + WALKWAY), "doors_out": fr.d, "deep": true}))
		at += len + 7.0
	var s_off: Vector2 = sx.call(cls_len + gate, cls_len + gate + office_len)
	fac.append(_bld("office", _lr(fr, s_off.x, s_off.y, b0, b0 + 12.0), -(fr.d as Vector2), 1, {"walk": _lr(fr, s_off.x, s_off.y, b0 + 12.0, b0 + 12.0 + WALKWAY)}))
	var s_gate: Vector2 = sx.call(cls_len, cls_len + gate)
	fac.append({"t": "entry", "r": _lr(fr, s_gate.x, s_gate.y, b0, b0 + bd + WALKWAY)})
	pl.bus_s = (s_cls.x + s_cls.y) * 0.5
	var s_aud: Vector2 = sx.call(cl - aud_w, cl)
	var aud_d := minf(AUD.y, D * 0.45)
	fac.append(_bld("auditorium", _lr(fr, s_aud.x, s_aud.y, b0, b0 + aud_d), -(fr.d as Vector2), 1, {"fly": true}))
	var s_campus: Vector2 = sx.call(0.0, cl)
	fac.append({"t": "lawn", "r": _lr(fr, s_campus.x, s_campus.y, 0.0, SETBACK), "gate_s": (s_gate.x + s_gate.y) * 0.5})
	for f: Dictionary in fac:
		if f.t != "track" and f.t != "bleachers":
			placed.append(f.r)
	var campus := _lr(fr, s_campus.x, s_campus.y, b0, D).grow(-1.0)
	pl.yard = campus
	var back_corner := _lp(fr, A if flip else 0.0, D)
	var mid_s := (s_campus.x + s_campus.y) * 0.5
	# The gym at the back, the biggest box on the campus.
	var gym := Parks._fit(campus, placed, GYM.x, GYM.y, 4.0, true, back_corner)
	if not gym.is_empty():
		var r: Rect2 = gym.r
		var c := r.get_center()
		var to_front := _lp(fr, (s_gate.x + s_gate.y) * 0.5, 0.0) - c
		var out_dir := Vector2(signf(to_front.x), 0.0) if absf(to_front.x) > absf(to_front.y) else Vector2(0.0, signf(to_front.y))
		fac.append(_bld("gym", r, out_dir, 1, {"long_x": gym.long_x}))
		placed.append(r)
	var tennis_done := false
	for m in [4, 3, 2]:
		var fit := Parks._fit(campus, placed, Parks.TEN_ENCLOSURE.x, Parks.TEN_ENCLOSURE.y * m, 3.0, true, _lp(fr, mid_s, D))
		if not fit.is_empty():
			var f := Parks._fac("tennis", fit.r, Parks._along_x(fit.r, Parks.TEN_ENCLOSURE.x))
			f.n = m
			f.pal = rng.randi() % Parks.TEN_PALETTES.size()
			fac.append(f)
			placed.append(f.r)
			tennis_done = true
			break
	for sz: Vector2 in [Vector2(44.0, 36.0), Vector2(36.0, 30.0), Vector2(30.0, 24.0)]:
		var fit := Parks._fit(campus, placed, sz.x, sz.y, 3.0, true, _lp(fr, s_campus.y if not flip else s_campus.x, D))
		if not fit.is_empty():
			fac.append({"t": "parking", "r": fit.r})
			placed.append(fit.r)
			break
	var court := Parks._fit(campus, placed, Parks.BB_COURT.x + Parks.BB_CLEAR * 2.0, (Parks.BB_COURT.y + Parks.BB_CLEAR * 2.0) * 2.0, 2.0, true, _lp(fr, mid_s, D * 0.6))
	if not court.is_empty():
		var f := Parks._fac("basketball", court.r, Parks._along_x(court.r, Parks.BB_COURT.x + Parks.BB_CLEAR * 2.0))
		f.n = 2
		f.yard = true
		f.pal = 0
		fac.append(f)
		placed.append(f.r)
	# The quad: a lawn behind the classrooms with trees and benches, the lunch shelter by it.
	for sz: Vector2 in [Vector2(34.0, 22.0), Vector2(26.0, 18.0), Vector2(20.0, 14.0)]:
		var q := Parks._fit(campus, placed, sz.x, sz.y, 3.0, true, _lp(fr, mid_s, b0 + bd + WALKWAY + 4.0))
		if not q.is_empty():
			fac.append(Parks._fac("quad", q.r, q.long_x))
			placed.append(q.r)
			break
	var lunch := Parks._fit(campus, placed, 20.0, 11.0, 3.0, true, _lp(fr, mid_s, b0 + bd + 6.0))
	if not lunch.is_empty():
		fac.append(Parks._fac("lunch", lunch.r, lunch.long_x))
		placed.append(lunch.r)
	if not tennis_done:
		pass
	# A couple of portables even at a high school.
	var port := Parks._fit(campus, placed, 2.0 * PORTABLE.x + 3.0, PORTABLE.y + RAMP_W + 1.8, 2.0, true, back_corner)
	if not port.is_empty():
		fac.append({"t": "portables", "r": port.r, "n": 2, "long_x": port.long_x, "paint": PORTABLE_PAINTS[rng.randi() % PORTABLE_PAINTS.size()]})
		placed.append(port.r)


# --- Build ------------------------------------------------------------------------------------------

## The school's build steps for chunk `ch` (CityChunk._block_steps, on a SCHOOL block whose
## grounds are this pass's): its part of the ground, the buildings, the kit, the planting and signs
## and the commit. Any level; capture mode records slabs and far boxes.
static func steps(ch: CityChunk, block: Dictionary) -> Array[Callable]:
	var out: Array[Callable] = []
	if not enabled or not block.has("school") or ch.zone != MacroMap.Zone.CITY:
		return out
	var pl := plan_for(ch.plan, ch.ix, ch.iz)
	if pl.is_empty():
		return out
	out.append(func() -> void:
		Parks._state(ch)
		_ground_step(ch, pl))
	out.append(func() -> void: _buildings_step(ch, pl))
	out.append(func() -> void: _kit_step(ch, pl))
	out.append(func() -> void: _finish_step(ch, pl))
	return out


static func _own(ch: CityChunk) -> Rect2:
	return ch.plan.owned_rect(ch.ix, ch.iz)


static func _mine(ch: CityChunk, p: Vector2) -> bool:
	return _own(ch).has_point(p)


## Parks' ground piece, clipped to the chunk's owned rect (the frame and so the painted lines
## carry on across the cut into the next chunk's piece).
static func _gp(ch: CityChunk, f: Dictionary, a0: float, a1: float, b0: float, b1: float, kind: int, g: float, b: float, a: float, uv2: Vector2, far: Color, drop: float = 0.0) -> void:
	var r := Parks.frect(f, a0, a1, b0, b1).intersection(_own(ch))
	if r.size.x < 0.05 or r.size.y < 0.05:
		return
	var u: Vector2 = f.u
	var v := Parks.perp(u)
	var c: Vector2 = f.c
	var p0 := r.position - c
	var p1 := r.end - c
	Parks._ground(ch, f, minf(p0.dot(u), p1.dot(u)), maxf(p0.dot(u), p1.dot(u)), minf(p0.dot(v), p1.dot(v)), maxf(p0.dot(v), p1.dot(v)), kind, g, b, a, uv2, far, drop)


## A world rect of plain ground (its own frame), clipped.
static func _gr(ch: CityChunk, r: Rect2, kind: int, far: Color, g: float = 0.0, b: float = 0.0) -> void:
	var f := {"c": r.get_center(), "u": Vector2(1.0, 0.0)}
	_gp(ch, f, -r.size.x * 0.5, r.size.x * 0.5, -r.size.y * 0.5, r.size.y * 0.5, kind, g, b, 1.0, r.size * 0.5, far)


static func _full(ch: CityChunk) -> bool:
	return ch.level == CityChunk.Level.FULL and not ch.capturing


static func _top(ch: CityChunk, p: Vector2) -> float:
	return CityChunk.SIDEWALK_TOP + Parks.LIFT + ch._gy(p.x, p.y)


static func _at(ch: CityChunk, p: Vector2, up: float = 0.0) -> Vector3:
	return Vector3(p.x, _top(ch, p) + up, p.y)


## The chunk's school mesh in the making (FULL only).
static func _st(ch: CityChunk) -> SurfaceTool:
	if not ch._park.has("school"):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.set_smooth_group(-1)
		ch._park["school"] = st
	return ch._park["school"]


static func _ground_step(ch: CityChunk, pl: Dictionary) -> void:
	var site: Rect2 = pl.site
	var holes: Array = []
	var fill_kind := Parks.G_ASPHALT
	var fill_far: Color = ch.style.asphalt
	for f: Dictionary in pl.fac:
		var r: Rect2 = f.r
		holes.append(r)
		match f.t:
			"track":
				_track_ground(ch, pl, f)
			"bleachers", "lunch", "entry":
				_gr(ch, r, Parks.G_DECK, Parks.FAR_DECK)
			"basketball":
				var n: int = f.n
				var cw: float = f.W / float(n)
				for k in n:
					var b0: float = -f.W * 0.5 + cw * float(k)
					var fc := {"c": Parks.fp(f, 0.0, b0 + cw * 0.5), "u": f.u}
					_gp(ch, fc, -f.L * 0.5, f.L * 0.5, -cw * 0.5, cw * 0.5, Parks.G_BASKETBALL, 0.5 / 8.0, 1.0, 1.0, Parks.BB_COURT * 0.5, ch.style.asphalt)
			"tennis":
				var n: int = f.n
				var cw: float = f.W / float(n)
				var pal: int = f.get("pal", 0)
				for k in n:
					var b0: float = -f.W * 0.5 + cw * float(k)
					var fc := {"c": Parks.fp(f, 0.0, b0 + cw * 0.5), "u": f.u}
					_gp(ch, fc, -f.L * 0.5, f.L * 0.5, -cw * 0.5, cw * 0.5, Parks.G_TENNIS, (float(pal) + 0.5) / 8.0, 0.0, 1.0, Vector2(f.L, cw) * 0.5, (Parks.TEN_PALETTES[pal][1] as Color) * 1.5)
			"games":
				_gp(ch, f, -f.L * 0.5, f.L * 0.5, -f.W * 0.5, f.W * 0.5, Parks.G_GAMES, 0.0, 0.0, 1.0, Vector2(f.L, f.W) * 0.5, ch.style.asphalt)
			"map":
				_gp(ch, f, -f.L * 0.5, f.L * 0.5, -f.W * 0.5, f.W * 0.5, G_MAP, 0.0, 0.0, 1.0, Vector2(f.L, f.W) * 0.5, ch.style.asphalt)
			"playground":
				_gp(ch, f, -f.L * 0.5, f.L * 0.5, -f.W * 0.5, f.W * 0.5, Parks.G_RUBBER, (float(f.get("pal", 0)) + 0.5) / 8.0, 0.0, 1.0, Vector2(f.L, f.W) * 0.5, Parks.FAR_RUBBER)
			"field":
				_field_ground(ch, f)
			"classroom", "office", "gym", "auditorium":
				_gr(ch, r, Parks.G_DECK, Parks.FAR_DECK)
				if f.has("walk"):
					_gr(ch, f.walk, Parks.G_DECK, Parks.FAR_DECK)
					holes.append(f.walk)
			"lawn":
				var gate: float = f.gate_s
				var fr: Dictionary = pl.fr
				var walk := _lr(fr, gate - 2.5, gate + 2.5, 0.0, SETBACK)
				_gr(ch, walk, Parks.G_DECK, Parks.FAR_DECK)
				for piece in Parks.minus(r, [walk]):
					_gr(ch, piece, Parks.G_LAWN, ch.style.grass, _h01([ch.plan.seed, pl.cell, "lawn"]))
			"parking":
				if _own(ch).encloses(r):
					LotFill._car_park(ch, r, hash([ch.plan.seed, pl.cell, "school_lot", r.position]))
				else:
					_gr(ch, r, Parks.G_ASPHALT, ch.style.asphalt)
			"portables":
				_gr(ch, r, Parks.G_ASPHALT, ch.style.asphalt)
			"quad":
				# A lawn inside a concrete walk.
				var inner := r.grow(-2.0)
				_gr(ch, inner, Parks.G_LAWN, ch.style.grass, 0.4)
				for piece in Parks.minus(r, [inner]):
					_gr(ch, piece, Parks.G_DECK, Parks.FAR_DECK)
	for piece in Parks.minus(site, holes, 0.3):
		_gr(ch, piece, fill_kind, fill_far)
	# The closed streets between a high school's blocks: a pavement slab kerb to kerb (it carries
	# the collision; the campus ground lies on it), built by the chunk that owns the street.
	for s: Rect2 in pl.closed_strips:
		if not _mine(ch, s.get_center()):
			continue
		var c := s.get_center()
		ch._add_slab(Vector3(c.x, CityChunk.SIDEWALK_TOP * 0.5, c.y), Vector3(s.size.x, CityChunk.SIDEWALK_TOP, s.size.y), ch.style.sidewalk, true,
			PropFactory.road("paving", 3.0, Color(0.95, 0.94, 0.92), hash([ch.plan.seed, pl.cell, "strip"]), 1.5, 0.45))


## The track (Parks' kind 5: lanes, the football field inside, the end zones in the school colour),
## clipped; from afar the infield turf and the red ring round it.
static func _track_ground(ch: CityChunk, pl: Dictionary, f: Dictionary) -> void:
	var lanes: int = f.lanes
	if not _full(ch):
		var ia: float = f.S * 0.5 + f.R * 0.55
		var ib: float = f.R * 0.8
		var whole := Rect2(-f.L * 0.5, -f.W * 0.5, f.L, f.W)
		_gp(ch, f, -ia, ia, -ib, ib, Parks.G_TURF, 0.0, 0.0, 1.0, Vector2.ONE, Parks.FAR_TURF)
		for piece in Parks.minus(whole, [Rect2(-ia, -ib, ia * 2.0, ib * 2.0)]):
			_gp(ch, f, piece.position.x, piece.end.x, piece.position.y, piece.end.y, Parks.G_TRACK, 0.0, 0.0, 1.0, Vector2.ONE, Parks.FAR_TRACK)
		return
	_gp(ch, f, -f.L * 0.5, f.L * 0.5, -f.W * 0.5, f.W * 0.5, Parks.G_TRACK, float(lanes) / 10.0, (float(pl.colour_i) + 0.5) / 8.0, f.football, Vector2(f.S * 0.5, f.R), Parks.FAR_TRACK)


## The grass field: a kickball diamond (Parks' kind 2) from its home corner, the rest turf.
static func _field_ground(ch: CityChunk, f: Dictionary) -> void:
	var r: Rect2 = f.r
	var side := minf(r.size.x, r.size.y)
	var home_off := 4.0
	var corners := [[r.position, Vector2(1, 0)], [Vector2(r.end.x, r.position.y), Vector2(0, 1)], [r.end, Vector2(-1, 0)], [Vector2(r.position.x, r.end.y), Vector2(0, -1)]]
	var pick: Array = corners[absi(hash([r.position, "home"])) % 4]
	var u: Vector2 = pick[1]
	var home: Vector2 = (pick[0] as Vector2) + (u + Parks.perp(u)) * home_off
	var d := {"c": home, "u": u}
	var fence := side - home_off - 2.0
	var base := 18.29 if fence > 40.0 else 15.24
	f.home = home
	f.home_u = u
	f.base = base
	var sq := Parks.frect(d, -home_off, side - home_off, -home_off, side - home_off)
	_gp(ch, d, -home_off, side - home_off, -home_off, side - home_off, Parks.G_DIAMOND, 0.0, 0.0, 1.0, Vector2(fence, base), Parks.FAR_TURF)
	for piece in Parks.minus(r, [sq]):
		var fp2 := {"c": piece.get_center(), "u": Vector2(1, 0) if piece.size.x >= piece.size.y else Vector2(0, 1)}
		var hl := maxf(piece.size.x, piece.size.y) * 0.5
		var hw := minf(piece.size.x, piece.size.y) * 0.5
		_gp(ch, fp2, -hl, hl, -hw, hw, Parks.G_TURF, 0.0, 0.0, 1.0, Vector2.ONE, Parks.FAR_TURF)


## The xf of a building facility: at the middle of its foot, z toward `yard` (its doors).
static func _bxf(ch: CityChunk, r: Rect2, yard: Vector2) -> Transform3D:
	var z := Vector3(yard.x, 0.0, yard.y).normalized()
	var x := Vector3.UP.cross(z).normalized()
	var c := r.get_center()
	return Transform3D(Basis(x, Vector3.UP, z), _at(ch, c))


## The building's length along x and depth along z for a frame facing `yard`.
static func _dims(r: Rect2, yard: Vector2) -> Vector2:
	return Vector2(r.size.y, r.size.x) if absf(yard.x) > 0.5 else Vector2(r.size.x, r.size.y)


static func _buildings_step(ch: CityChunk, pl: Dictionary) -> void:
	var full := _full(ch)
	var trim: Color = pl.colour
	var paint: Color = pl.paint
	var brick: bool = pl.brick
	var fr: Dictionary = pl.fr
	var door_paint: Color = DOOR_PAINTS_FOR[absi(hash([pl.cell, "door"])) % DOOR_PAINTS_FOR.size()]
	var street := -(fr.d as Vector2)
	var number := 1
	for f: Dictionary in pl.fac:
		var r: Rect2 = f.r
		match f.t:
			"classroom", "office", "gym", "auditorium":
				if not _mine(ch, r.get_center()):
					continue
				var h := 0.0
				var yard: Vector2 = f.get("doors_out", fr.d)
				match f.t:
					"classroom":
						h = float(f.storeys) * STOREY + 1.1
					"office":
						h = STOREY + 1.8
					"gym":
						h = GYM_H + 2.6
						yard = f.out
					"auditorium":
						h = FLY_H + 0.6
				if not full:
					var col := paint * (0.82 if not brick else 0.9)
					if f.t == "auditorium":
						var fd := _strip_far(r, street, 5.0)
						_far_box_r(ch, fd, AUD_H + 0.9, col)
						var back := _strip_back(r, street, minf(13.0, r.size.x if absf(street.x) > 0.5 else r.size.y) * 0.36 + 6.0)
						_far_box_r(ch, back, FLY_H + 0.6, col)
					else:
						_far_box_r(ch, r, h, col)
					continue
				var st := _st(ch)
				match f.t:
					"classroom":
						var xf := _bxf(ch, r, yard)
						var dm := _dims(r, yard)
						SchoolKit.classroom(st, xf, dm.x, dm.y, f.storeys, paint, brick, trim, f.get("mural", false), door_paint)
						var w: Rect2 = f.walk
						var a := xf * Vector3(-dm.x * 0.5, 0.0, dm.y * 0.5)
						var b := xf * Vector3(dm.x * 0.5, 0.0, dm.y * 0.5)
						var wh := 3.1 if int(f.storeys) == 1 else STOREY * 2.0 + 0.2
						if int(f.storeys) == 1:
							SchoolKit.walkway(st, a, b, xf.basis.z, WALKWAY, wh, trim)
						else:
							# The upper balcony is the lower walk's roof; posts carry it.
							var n := maxi(1, int(dm.x / 4.5))
							for i in n + 1:
								var p := a.lerp(b, float(i) / float(n)) + xf.basis.z * (WALKWAY - 0.2)
								SchoolKit.box(st, Transform3D(Basis(), p + Vector3(0.0, STOREY * 0.5, 0.0)), Vector3(0.18, STOREY, 0.18), SchoolKit.K_CONCRETE, SchoolKit.CONCRETE)
						Parks._solid(ch, r, float(f.storeys) * STOREY + 0.4)
					"office":
						var xf := _bxf(ch, r, fr.d)
						var dm := _dims(r, fr.d)
						SchoolKit.office(st, xf, dm.x, dm.y, paint, brick, trim, pl.name)
						var a := xf * Vector3(-dm.x * 0.5, 0.0, dm.y * 0.5)
						var b := xf * Vector3(dm.x * 0.5, 0.0, dm.y * 0.5)
						SchoolKit.walkway(st, a, b, xf.basis.z, WALKWAY, 3.1, trim)
						Parks._solid(ch, r, STOREY + 0.4)
					"gym":
						var xf := _bxf(ch, r, Vector2(-f.out.y, f.out.x))
						var dm := _dims(r, Vector2(-f.out.y, f.out.x))
						# Its +x end faces `out` (the doors and the mascot).
						if (xf.basis.x).dot(Vector3(f.out.x, 0.0, f.out.y)) < 0.0:
							xf = xf.rotated_local(Vector3.UP, PI)
						SchoolKit.gym(st, xf, dm.x, dm.y, paint, brick, trim, pl.mascot)
						Parks._solid(ch, r, GYM_H)
					"auditorium":
						var body := _strip_far(r, street, 5.0)
						var xf := _bxf(ch, body, fr.d)
						var dm := _dims(body, fr.d)
						SchoolKit.auditorium(st, xf, dm.x, dm.y, paint, brick, trim, pl.name)
						Parks._solid(ch, body, AUD_H)
			"portables":
				_portables(ch, pl, f, door_paint, number)
				number += int(f.n)


const DOOR_PAINTS_FOR := SchoolKit.DOOR_PAINTS


## The part of `r` past its first `depth` metres from the side facing `street` (the building behind
## the auditorium's lobby).
static func _strip_far(r: Rect2, street: Vector2, depth: float) -> Rect2:
	if street.y < -0.5:
		return Rect2(r.position.x, r.position.y + depth, r.size.x, r.size.y - depth)
	if street.y > 0.5:
		return Rect2(r.position.x, r.position.y, r.size.x, r.size.y - depth)
	if street.x < -0.5:
		return Rect2(r.position.x + depth, r.position.y, r.size.x - depth, r.size.y)
	return Rect2(r.position.x, r.position.y, r.size.x - depth, r.size.y)


## The last `depth` metres of `r` away from `street` (the fly tower).
static func _strip_back(r: Rect2, street: Vector2, depth: float) -> Rect2:
	if street.y < -0.5:
		return Rect2(r.position.x, r.end.y - depth, r.size.x, depth)
	if street.y > 0.5:
		return Rect2(r.position.x, r.position.y, r.size.x, depth)
	if street.x < -0.5:
		return Rect2(r.end.x - depth, r.position.y, depth, r.size.y)
	return Rect2(r.position.x, r.position.y, depth, r.size.y)


static func _far_box_r(ch: CityChunk, r: Rect2, h: float, col: Color) -> void:
	Parks._far_box(ch, r, h, col)


## A row of portables: each up on its blocks, its ramp toward the yard.
static func _portables(ch: CityChunk, pl: Dictionary, f: Dictionary, door_paint: Color, first: int) -> void:
	var r: Rect2 = f.r
	var n: int = f.n
	var long_x: bool = f.long_x
	var yard_c: Vector2 = (pl.yard as Rect2).get_center()
	# The ramps face the middle of the yard: the bodies stand on the far side of the row's depth.
	var depth := r.size.y if long_x else r.size.x
	var toward := Vector2(0.0, signf(yard_c.y - r.get_center().y)) if long_x else Vector2(signf(yard_c.x - r.get_center().x), 0.0)
	if toward.length() < 0.5:
		toward = Vector2(0.0, 1.0) if long_x else Vector2(1.0, 0.0)
	var along := Vector2(1.0, 0.0) if long_x else Vector2(0.0, 1.0)
	var start := r.position if long_x else r.position
	for i in n:
		var a := float(i) * (PORTABLE.x + 3.0) + PORTABLE.x * 0.5
		var c := start + along * a
		# Across the row: the body's centre is PORTABLE.y / 2 in from the side away from the yard.
		var lo := r.position.y if long_x else r.position.x
		var hi := r.end.y if long_x else r.end.x
		var across := (lo + PORTABLE.y * 0.5) if (toward.y if long_x else toward.x) > 0.0 else (hi - PORTABLE.y * 0.5)
		if long_x:
			c.y = across
		else:
			c.x = across
		if not _mine(ch, c):
			continue
		var body := Rect2(c - (Vector2(PORTABLE.x, PORTABLE.y) if long_x else Vector2(PORTABLE.y, PORTABLE.x)) * 0.5, Vector2(PORTABLE.x, PORTABLE.y) if long_x else Vector2(PORTABLE.y, PORTABLE.x))
		if not _full(ch):
			_far_box_r(ch, body, PORTABLE_RISE + 3.3, f.paint)
			continue
		var z := Vector3(toward.x, 0.0, toward.y)
		var x := Vector3.UP.cross(z).normalized()
		var xf := Transform3D(Basis(x, Vector3.UP, z), _at(ch, c))
		SchoolKit.portable(_st(ch), xf, f.paint, pl.colour, door_paint, first + i)
		Parks._solid(ch, body, PORTABLE_RISE + 3.2)
	var _d := depth


static func _kit_step(ch: CityChunk, pl: Dictionary) -> void:
	var full := _full(ch)
	for f: Dictionary in pl.fac:
		var r: Rect2 = f.r
		match f.t:
			"basketball":
				if not full:
					continue
				var n: int = f.n
				var cw: float = f.W / float(n)
				for k in n:
					var fc := {"c": Parks.fp(f, 0.0, -f.W * 0.5 + cw * (float(k) + 0.5)), "u": f.u}
					if not _mine(ch, fc.c):
						continue
					var u: Vector2 = f.u
					ParkKit.hoop(Parks._walls(ch), Parks._fxf(ch, fc, Parks.BB_COURT.x * 0.5, 0.0, -u), false)
					ParkKit.hoop(Parks._walls(ch), Parks._fxf(ch, fc, -Parks.BB_COURT.x * 0.5, 0.0, u), false)
			"tennis":
				if not full or not _mine(ch, r.get_center()):
					continue
				var n: int = f.n
				var cw: float = f.W / float(n)
				for k in n:
					var fc := {"c": Parks.fp(f, 0.0, -f.W * 0.5 + cw * (float(k) + 0.5)), "u": f.u}
					ParkKit.tennis_net(Parks._walls(ch), Parks._fxf(ch, fc, 0.0, 0.0, Parks.perp(f.u)))
				ParkKit.fence_rect(Parks._walls(ch), ch, r, CityChunk.SIDEWALK_TOP + Parks.LIFT, 3.6, true, [Parks.fp(f, -f.L * 0.5 + 3.0, -f.W * 0.5), Parks.fp(f, f.L * 0.5 - 3.0, f.W * 0.5)])
			"track":
				_track_kit(ch, pl, f)
			"bleachers":
				if _mine(ch, r.get_center()):
					Parks._stands_build(ch, f)
			"field":
				if full and f.has("home") and _mine(ch, f.home):
					var home: Vector2 = f.home
					var u: Vector2 = f.home_u
					ParkKit.backstop(Parks._walls(ch), ParkKit.frame(_at(ch, home), u))
					ParkKit.bases(Parks._walls(ch), ParkKit.frame(_at(ch, home), u), f.base, f.base * 0.77)
					# A team bench either side of home.
					ch._add_bench(Vector3(home.x, 0.0, home.y) + Vector3((u.x + Parks.perp(u).x) * -0.5 + u.x * 9.0, CityChunk.SIDEWALK_TOP + Parks.LIFT, (u.y + Parks.perp(u).y) * -0.5 + u.y * 9.0) + Vector3(-Parks.perp(u).x * 3.0, 0.0, -Parks.perp(u).y * 3.0), atan2(Parks.perp(u).x, Parks.perp(u).y))
			"playground":
				if not full or not _mine(ch, r.get_center()):
					continue
				var st := Parks._walls(ch)
				var u: Vector2 = f.u
				var set_i: int = f.get("pal", 0)
				ParkKit.play_structure(st, Parks._fxf(ch, f, -f.L * 0.12, -f.W * 0.08, u), set_i)
				ParkKit.swings(st, Parks._fxf(ch, f, f.L * 0.5 - 3.2, 0.0, Parks.perp(u)), 4, (ParkKit.PLAY_SETS[set_i % 4] as Array)[0])
				for e in 4:
					var horiz := e < 2
					var len: float = f.L if horiz else f.W
					var p := Parks.fp(f, 0.0, (f.W * 0.5 + 0.08) * (1.0 if e == 0 else -1.0)) if horiz else Parks.fp(f, (f.L * 0.5 + 0.08) * (1.0 if e == 2 else -1.0), 0.0)
					ParkKit.box(st, ParkKit.frame(_at(ch, p, -0.05), u if horiz else Parks.perp(u)), Vector3(len + 0.32, 0.22, 0.16), ParkKit.K_CONCRETE, ParkKit.CONCRETE)
			"lunch":
				if not full or not _mine(ch, r.get_center()):
					if not full and _mine(ch, r.get_center()):
						Parks._far_box(ch, r.grow(-0.5), 3.4, Parks.FAR_ROOF)
					continue
				ParkKit.shelter(Parks._walls(ch), Parks._fxf(ch, f, 0.0, 0.0, f.u), f.L - 1.0, f.W - 1.0, 0, (pl.colour as Color).lightened(0.25))
				var st := _st(ch)
				var rows := maxi(1, int((f.W - 2.0) / 2.6))
				var cols := maxi(1, int((f.L - 2.0) / 3.2))
				for i in cols:
					for j in rows:
						var a: float = -f.L * 0.5 + 1.0 + (float(i) + 0.5) * (f.L - 2.0) / float(cols)
						var b: float = -f.W * 0.5 + 1.0 + (float(j) + 0.5) * (f.W - 2.0) / float(rows)
						SchoolKit.lunch_table(st, Parks._fxf(ch, f, a, b, f.u), (pl.colour as Color).lightened(0.35))
			"quad":
				if full and _mine(ch, r.get_center()):
					var rng := RandomNumberGenerator.new()
					rng.seed = hash([ch.plan.seed, pl.cell, "quad"])
					var inner := r.grow(-3.2)
					for c: Vector2 in [inner.position, Vector2(inner.end.x, inner.position.y), inner.end, Vector2(inner.position.x, inner.end.y)]:
						ch._add_tree(Vector3(c.x, CityChunk.SIDEWALK_TOP + Parks.LIFT, c.y), rng)
					var u: Vector2 = f.u
					for sgn: float in [-1.0, 1.0]:
						var bp := Parks.fp(f, 0.0, sgn * (f.W * 0.5 - 1.0))
						ch._add_bench(Vector3(bp.x, CityChunk.SIDEWALK_TOP + Parks.LIFT, bp.y), atan2(u.x, u.y) + (PI * 0.5 if sgn > 0.0 else -PI * 0.5))
			"games":
				if full and _mine(ch, r.get_center()):
					# Tetherball poles at the games' end.
					for s: float in [-1.0, 1.0]:
						var p := Parks.fp(f, 0.0, s * (f.W * 0.5 - 1.2))
						var st := Parks._walls(ch)
						ParkKit.post(st, _at(ch, p), 0.04, 3.05, ParkKit.K_STEEL, Color(0.86, 0.86, 0.84), 8)
						ParkKit.box(st, Transform3D(Basis(), _at(ch, p, 1.9) + Vector3(0.14, 0.0, 0.0)), Vector3(0.22, 0.22, 0.22), ParkKit.K_PLASTIC, Color(0.85, 0.80, 0.20))
	_fences(ch, pl)


## The stadium's kit: goal posts, the scoreboard, the light standards (lit on a game night, with
## their light pools on the field).
static func _track_kit(ch: CityChunk, pl: Dictionary, f: Dictionary) -> void:
	var full := _full(ch)
	var u: Vector2 = f.u
	var fb: float = f.football
	if full:
		if fb > 0.0:
			var hl := Parks.FOOTBALL.x * 0.5 * fb
			for s: float in [-1.0, 1.0]:
				if _mine(ch, Parks.fp(f, s * hl, 0.0)):
					ParkKit.goal_posts(Parks._walls(ch), Parks._fxf(ch, f, s * hl, 0.0, -u * s), fb)
		var sb := Parks.fp(f, -(f.L * 0.5 - 1.5), 0.0)
		if _mine(ch, sb):
			var z := Vector3(u.x, 0.0, u.y)
			var x := Vector3.UP.cross(z).normalized()
			SchoolKit.scoreboard(_st(ch), Transform3D(Basis(x, Vector3.UP, z), _at(ch, sb)), pl.colour, pl.mascot)
	var lit: bool = pl.game_night
	var ext: float = f.R + float(f.lanes) * Parks.LANE + Parks.TRACK_APRON * 0.6
	for sa: float in [-1.0, 0.0, 1.0]:
		for sb2: float in [-1.0, 1.0]:
			var a: float = sa * f.S * 0.45
			var p := Parks.fp(f, a, sb2 * ext)
			if not _mine(ch, p):
				continue
			var aim := Parks.fp(f, a * 0.4, 0.0)
			if full:
				SchoolKit.light_standard(_st(ch), _at(ch, p), aim, 26.0, 10, lit)
				if lit:
					var c := p.lerp(aim, 0.6)
					var xf := Transform3D(Basis(Vector3.RIGHT, -PI * 0.5).scaled(Vector3(f.R * 1.6, 1.0, f.R * 1.6)), Vector3(c.x, CityChunk.SIDEWALK_TOP + Parks.LIFT + 0.15, c.y))
					ch._batch.add("park_pool", PropFactory.light_pool(Parks.FLOOD_TINT, 0.55, 1.8), xf)
			else:
				Parks._far_box(ch, Rect2(p - Vector2(0.4, 0.4), Vector2(0.8, 0.8)), 26.0, Color(0.6, 0.62, 0.62))


## Chain-link round the campus: the sides and back on the site's edge, the front along the
## setback between the buildings (their street walls are the rest of it), a gate at the entry.
static func _fences(ch: CityChunk, pl: Dictionary) -> void:
	if not _full(ch):
		return
	var st := Parks._walls(ch)
	var fr: Dictionary = pl.fr
	var A: float = fr.A
	var D: float = fr.D
	var site: Rect2 = pl.site
	var y := CityChunk.SIDEWALK_TOP + Parks.LIFT
	var h := 2.4
	# Back and sides (in the frame: s = 0 and s = A, d = D), inset a little.
	var runs: Array = [[_lp(fr, 0.3, SETBACK), _lp(fr, 0.3, D - 0.3)], [_lp(fr, 0.3, D - 0.3), _lp(fr, A - 0.3, D - 0.3)], [_lp(fr, A - 0.3, D - 0.3), _lp(fr, A - 0.3, SETBACK)]]
	# The front: d = SETBACK, everywhere no building stands, less the gate.
	var cover: Array = []
	for f: Dictionary in pl.fac:
		if f.t in ["classroom", "office", "auditorium", "parking", "entry"]:
			var r: Rect2 = f.r
			var p0 := (r.position - (fr.o as Vector2)).dot(fr.s)
			var p1 := (r.end - (fr.o as Vector2)).dot(fr.s)
			var dd0 := (r.position - (fr.o as Vector2)).dot(fr.d)
			var dd1 := (r.end - (fr.o as Vector2)).dot(fr.d)
			if minf(dd0, dd1) <= SETBACK + 1.0:
				if f.t == "entry":
					cover.append(Vector2(minf(p0, p1) + 1.0, maxf(p0, p1) - 1.0))
				else:
					cover.append(Vector2(minf(p0, p1), maxf(p0, p1)))
	cover.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
	var s := 0.3
	for cv: Vector2 in cover:
		if cv.x > s + 0.5:
			runs.append([_lp(fr, s, SETBACK), _lp(fr, cv.x, SETBACK)])
		s = maxf(s, cv.y)
	if s < A - 0.8:
		runs.append([_lp(fr, s, SETBACK), _lp(fr, A - 0.3, SETBACK)])
	var own := _own(ch)
	for run: Array in runs:
		var a: Vector2 = run[0]
		var b: Vector2 = run[1]
		# Clip the run to the chunk (axis-aligned), so each chunk builds its own part.
		var lo := Vector2(minf(a.x, b.x), minf(a.y, b.y))
		var hi := Vector2(maxf(a.x, b.x), maxf(a.y, b.y))
		lo = Vector2(maxf(lo.x, own.position.x), maxf(lo.y, own.position.y))
		hi = Vector2(minf(hi.x, own.end.x), minf(hi.y, own.end.y))
		if hi.x < lo.x - 0.01 or hi.y < lo.y - 0.01 or lo.distance_to(hi) < 0.5:
			continue
		ParkKit.fence(st, Vector3(lo.x, y + ch._gy(lo.x, lo.y), lo.y), Vector3(hi.x, y + ch._gy(hi.x, hi.y), hi.y), h)
	var _s := site


static func _finish_step(ch: CityChunk, pl: Dictionary) -> void:
	var full := _full(ch)
	var fr: Dictionary = pl.fr
	var street := -(fr.d as Vector2)
	for f: Dictionary in pl.fac:
		if f.t != "lawn":
			continue
		var gate: float = f.gate_s
		var A: float = fr.A
		# The marquee sign on the lawn beside the entry walk, side-on to the street; the flagpole.
		var sign_s := gate + (7.0 if gate + 9.0 < A else -7.0)
		var sp := _lp(fr, sign_s, SETBACK * 0.5)
		if full and _mine(ch, sp):
			var x := Vector3(fr.d.x, 0.0, fr.d.y)
			var z := Vector3.UP.cross(x).normalized()
			var line := "HIGH SCHOOL" if pl.high else "ELEMENTARY SCHOOL"
			SchoolKit.marquee(_st(ch), Transform3D(Basis(-z, Vector3.UP, -x), _at(ch, sp)), pl.name, line, pl.message, pl.colour, BRICK[0] if not pl.brick else pl.paint)
			# Turned square to the street: the faces read from the pavement both ways.
		var fp := _lp(fr, gate - (6.0 if gate - 8.0 > 0.0 else -6.0), SETBACK * 0.55)
		if full and _mine(ch, fp):
			SchoolKit.flagpole(_st(ch), _at(ch, fp), 9.5 if not pl.high else 12.0, Vector3((fr.s as Vector2).x, 0.0, (fr.s as Vector2).y))
		# Trees down the lawn, clear of the walk, the sign and the pole.
		if full:
			var rng := RandomNumberGenerator.new()
			rng.seed = hash([ch.plan.seed, pl.cell, "lawn_trees", ch.ix, ch.iz])
			var t := 5.0
			while t < A - 3.0:
				var p := _lp(fr, t, SETBACK * 0.5)
				t += rng.randf_range(10.0, 14.0)
				if absf(t - gate) < 6.0 or absf(t - sign_s) < 4.0:
					continue
				if not _mine(ch, p):
					continue
				ch._add_tree(Vector3(p.x, CityChunk.SIDEWALK_TOP + Parks.LIFT, p.y), rng)
	# Shade trees round the yard's edge.
	if full:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([ch.plan.seed, pl.cell, "yard_trees", ch.ix, ch.iz])
		var yard: Rect2 = pl.yard
		var holes: Array = []
		for f: Dictionary in pl.fac:
			holes.append((f.r as Rect2).grow(2.5))
			if f.has("walk"):
				holes.append((f.walk as Rect2).grow(2.0))
		for i in 18:
			var p := Vector2(rng.randf_range(yard.position.x, yard.end.x), rng.randf_range(yard.position.y, yard.end.y))
			if not _mine(ch, p) or yard.grow(-2.5).has_point(p) == false or yard.grow(-9.0).has_point(p):
				continue
			var clear := true
			for h: Rect2 in holes:
				if h.has_point(p):
					clear = false
					break
			if clear:
				ch._add_tree(Vector3(p.x, CityChunk.SIDEWALK_TOP + Parks.LIFT, p.y), rng)
		# Tree wells out on the blacktop (the greening every district is doing): a grid of shade
		# trees in concrete rings wherever nothing is painted or built.
		var st := Parks._walls(ch)
		var step := TREE_WELL_STEP
		var gx := int(yard.size.x / step)
		var gz := int(yard.size.y / step)
		var wells := 0
		for i in gx:
			for j in gz:
				var p := yard.position + Vector2((float(i) + 0.5) * yard.size.x / float(gx), (float(j) + 0.5) * yard.size.y / float(gz))
				if wells >= MAX_TREE_WELLS or not _mine(ch, p) or not yard.grow(-4.0).has_point(p):
					continue
				var clear := true
				for h: Rect2 in holes:
					if h.grow(1.5).has_point(p):
						clear = false
						break
				if not clear:
					continue
				wells += 1
				ch._add_tree(Vector3(p.x, CityChunk.SIDEWALK_TOP + Parks.LIFT, p.y), rng)
				for e in 4:
					var a := float(e) * PI * 0.5
					var d := Vector2(cos(a), sin(a))
					ParkKit.box(st, ParkKit.frame(_at(ch, p + d * 0.9, 0.06), Vector2(-d.y, d.x)), Vector3(2.0, 0.24, 0.2), ParkKit.K_CONCRETE, ParkKit.CONCRETE)
	# The buses parked in the loading zone (the chunk that owns that kerb).
	park_buses(ch, pl)
	if full and ch._park.has("school"):
		var mi := MeshInstance3D.new()
		mi.name = "SchoolWalls"
		mi.mesh = (ch._park["school"] as SurfaceTool).commit()
		mi.material_override = walls_material()
		ch.add_child(mi)
		ch._park.erase("school")
	var _st2 := street


static var _material: ShaderMaterial


static func walls_material() -> ShaderMaterial:
	if _material != null:
		return _material
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/school_walls.gdshader")
	mat.set_shader_parameter("concrete_tex", PropFactory.texture("concrete", "Color"))
	mat.set_shader_parameter("brick_tex", PropFactory.texture("brick_factory", "Color"))
	mat.set_shader_parameter("brick_nrm", PropFactory.texture("brick_factory", "NormalGL"))
	mat.set_shader_parameter("planks_tex", PropFactory.texture("planks", "Color"))
	_material = mat
	return mat


## The plan in the shape GroundCoverage reads (Parks' facility names: buildings BUILT, the car
## park PARKING, the rest SPORT), or {}.
static func coverage_plan(plan: CityPlan, bx: int, bz: int) -> Dictionary:
	var pl := plan_for(plan, bx, bz)
	if pl.is_empty():
		return {"role": "school", "fac": []}
	var fac: Array = []
	for f: Dictionary in pl.fac:
		match f.t:
			"classroom", "office", "gym", "auditorium", "portables", "lunch", "bleachers":
				fac.append({"t": "bungalow", "r": f.r})
			"parking":
				fac.append({"t": "parking", "r": f.r})
			_:
				fac.append({"t": "games", "r": f.r})
	return {"role": "school", "fac": fac}



# --- School buses --------------------------------------------------------------------------------

## The hour on the city's clock (`force_hour` first; early afternoon with no clock).
static func hour_now(node: Node) -> float:
	if force_hour >= 0.0:
		return force_hour
	return StreetVendors.hour_now(node)


## Whether the bell is ringing at `hour` (the school run, morning and afternoon).
static func bus_hours(hour: float) -> bool:
	var h := fposmod(hour, 24.0)
	for w: Vector2 in BUS_HOURS:
		if h >= w.x and h <= w.y:
			return true
	return false


## TrafficManager's question for a new street car at `at` (true world XZ): a school bus? `roll`
## is a uniform number the caller already drew (no roll of the traffic's own is spent here).
static func traffic_bus(plan: CityPlan, at: Vector2, roll: float, hour: float) -> bool:
	if not enabled or plan == null or plan.macro == null or roll >= BUS_SHARE or not bus_hours(hour):
		return false
	var c := _cell_of(at)
	var reach := ceili(BUS_REACH / CELL)
	for dx in range(-reach, reach + 1):
		for dz in range(-reach, reach + 1):
			var d := decide(plan, c + Vector2i(dx, dz))
			if d.is_empty():
				continue
			var k: Vector2i = d.blocks[0]
			if _block_rect(plan, k).get_center().distance_to(at) < BUS_REACH:
				return true
	return false


## The parked buses in a school's loading zone: [position (true world XZ, on the road), yaw]
## each, worked out from the plan (the zone's kerb, nose toward the traffic's direction there).
static func bus_spots(plan: CityPlan, pl: Dictionary) -> Array:
	var out: Array = []
	var zr: Rect2 = pl.bus_rect
	var n: int = pl.buses
	var axis: int = pl.bus_axis
	var road: Array = pl.front_road
	var rp := plan.road_pos(int(road[0]), int(road[1]))
	var len := maxf(zr.size.x, zr.size.y)
	var pitch := 13.4
	n = mini(n, int(len / pitch))
	for i in n:
		var t := (float(i) + 0.5) * pitch - float(n) * pitch * 0.5
		var c := zr.get_center()
		var p := c + (Vector2(0.0, t) if axis == CityPlan.AXIS_X else Vector2(t, 0.0))
		# Right-hand traffic: a bus at the kerb on the +side of the road faces the way that lane runs.
		var dir := Vector2.ZERO
		if axis == CityPlan.AXIS_X:
			dir = Vector2(0.0, -1.0) if p.x > rp else Vector2(0.0, 1.0)
		else:
			dir = Vector2(1.0, 0.0) if p.y > rp else Vector2(-1.0, 0.0)
		out.append([p, atan2(-dir.x, -dir.y)])
	return out


## The parked buses of the school whose front kerb is in chunk `ch`'s owned rect (FULL, a step):
## real Vehicles, parked like the chunk's cars (they live under the city root, survive the chunk).
static func park_buses(ch: CityChunk, pl: Dictionary) -> void:
	if not _full(ch) or not ResourceLoader.exists(Vehicle.BODY_MODELS[Vehicle.BodyType.SCHOOL_BUS]):
		return
	for spot: Array in bus_spots(ch.plan, pl):
		var p: Vector2 = spot[0]
		if not _mine(ch, p) or not PhysicsBudget.can_spawn():
			continue
		var bus := BigVehicles.make(Vehicle.BodyType.SCHOOL_BUS, hash([ch.plan.seed, pl.cell, p]))
		var holder: Node = ch.get_parent() if ch.get_parent() else ch
		var at := Vector3(p.x, 0.5 + ch._gy(p.x, p.y), p.y)
		bus.position = WorldState.to_local(at) if holder != ch else at
		bus.rotation.y = float(spot[1])
		holder.add_child(bus)
		bus.visible = ch.visible
		ch._cars.append(bus)
