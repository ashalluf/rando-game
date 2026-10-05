class_name Cemetery
extends RefCounted
## Memorial parks (2026-10-05, fleet task "cemetery"). Los Angeles' big lawn cemeteries are
## landscaped hills: close-mown grass over a rounded rise, flat bronze markers in long rows flush
## with the turf (so the mowers run over them), an older section of upright headstones, obelisks
## and family monuments, a classical mausoleum on the crown, a small Mission-style chapel by the
## entrance, mature pines, cypresses and shade trees, one winding drive looping round the hill,
## and an iron fence on a low wall with a lit gate and the park's name over it.
##
## WHERE is worked out, never placed (FireStation's and Schools' approach): the map is cut into
## CELL squares and a hash of the seed and the cell picks up to TRIES points in it; the block under
## a point becomes a memorial park when it is plain SUBURBS ground no one else claims (Schools'
## eligibility list: Parks' roles, sites, landmarks, the replica, the river, the freeway, the light
## rail, the approach, a fire station's block) and big enough. apply() is CityPlan.block()'s hook,
## called on the block being made, BEFORE Schools' hook, and decides from that block's own data and
## the roads alone - never another block - so the answer is the same whatever order blocks are
## asked for in. The block becomes a PARK with grounds "cemetery" (CityPlan.lots() is empty there,
## Schools and the stations skip it, the minimap paints it green).
##
## The plan is PURE (plan_for(): hashes of seed + block, never a chunk or block rng), in the site's
## street frame (u along the front street, v in from it). CemeteryBuild draws it.
##
## It is a SANCTUARY (Sanctuary, the masjid's rule): a zone over the whole site at every level and
## all its collision in the sanctuary body group, so no gun fires at it, into it or from inside it,
## no rocket lands near it, nothing marks it. Nothing in it breaks.
##
## Names are invented (NAMES); no real cemetery's, family's or person's name anywhere.

## Off (CEMETERY=0 in the environment): no block becomes a memorial park (the A/B).
static var enabled: bool = OS.get_environment("CEMETERY") != "0"

const CELL := 1500.0
const TRIES := 5
## Odds each of a cell's tries is wanted at all (the rest of the cells keep their suburb).
const ODDS := 0.75
const DISTRICTS := [CityPlan.District.SUBURBS]
## Site (inside the outer pavements, over the closed streets) limits, metres: short side, long side.
const MIN_SIZE := Vector2(95.0, 125.0)
const MAX_SIZE := 300.0
## A street the park may close: no wider than a local street, never a pinned real road.
const MAX_CLOSED_WIDTH := 15.5

# --- Real sizes (metres) ------------------------------------------------------------------------
## The rise: crown height from the site's size, clamped (a gentle hill, 6-12 % at most).
const HILL_SHARE := 0.045
const HILL_MIN := 2.4
const HILL_MAX := 5.0
## The edge band kept level for the wall and its planting.
const EDGE := 3.5
const ROAD_W := 5.4
## Grave spacing: row pitch (head to head) and along a row.
const ROW_PITCH := 2.9
const GRAVE_PITCH := 1.3
## An aisle (no graves) every this many rows.
const AISLE_EVERY := 7
const CHAPEL := Vector2(11.0, 20.0)
const MAUSOLEUM := Vector2(15.0, 11.0)
## Fence: the low wall and the iron above it.
const WALL_H := 0.55
const FENCE_H := 1.75
const GATE_W := 8.0

const NAMES := ["EVERGREEN SLOPE", "QUIET OAKS", "VISTA SERENA", "HALCYON HILL", "MEADOWREST", "CYPRESS DELL",
	"SAN ARBOLES", "WILLOWMERE", "STILLWATER HEIGHTS", "LOMA DE PAZ", "HOLLYCREST", "AMBERFIELD"]

static var _plans: Dictionary = {}
static var _cells: Dictionary = {}
static var _closed: Dictionary = {}
## Why candidate blocks were turned down (tools/cemetery/probe.gd prints it).
static var why: Dictionary = {}


static func _no(reason: String) -> bool:
	why[reason] = int(why.get(reason, 0)) + 1
	return false


static func _h01(parts: Array) -> float:
	return float(absi(hash(parts)) % 100003) / 100003.0


static func _cell_of(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / CELL), floori(p.y / CELL))


## CityPlan.block()'s hook: marks block `b` (already cached, kind and Parks' grounds rolled) a
## memorial park when its cell's site takes it.
static func apply(plan: CityPlan, b: Dictionary) -> void:
	if not enabled or plan.macro == null:
		return
	var k := Vector2i(int(b.ix), int(b.iz))
	var d := decide(plan, _cell_of(_block_rect(plan, k).get_center()))
	if d.is_empty() or not (d.blocks as Array).has(k):
		return
	b.kind = CityPlan.BlockKind.PARK
	b.grounds = "cemetery"
	b.cemetery = d.cell


## Whether block (ix, iz) is a memorial park.
static func is_cemetery(plan: CityPlan, ix: int, iz: int) -> bool:
	return String(plan.block(ix, iz).get("grounds", "")) == "cemetery"


## Block k's rect between the kerbs, from the roads alone (CityPlan.block()'s).
static func _block_rect(plan: CityPlan, k: Vector2i) -> Rect2:
	return Schools._block_rect(plan, k)


## The memorial park of grid cell `cell`: {} or {"cell", "blocks" (Array[Vector2i]), "site" (Rect2,
## inside the outer pavements), "closed" ([axis, index, lo, hi]: the stretches of the inner
## streets the park covers)}. PURE: roads, hashes and the map, never CityPlan.block(), so the
## answer is the same whichever block asks first. Cached per seed.
static func decide(plan: CityPlan, cell: Vector2i) -> Dictionary:
	var key := Vector3i(plan.seed, cell.x, cell.y)
	if _cells.has(key):
		return _cells[key]
	var out := {}
	_cells[key] = out
	if not enabled or plan.macro == null:
		return out
	for attempt in TRIES:
		if _h01([plan.seed, cell.x, cell.y, attempt, "cem"]) > ODDS:
			_no("odds")
			continue
		var target := Vector2((float(cell.x) + lerpf(0.1, 0.9, _h01([plan.seed, cell.x, cell.y, attempt, "cem_x"]))) * CELL,
				(float(cell.y) + lerpf(0.1, 0.9, _h01([plan.seed, cell.x, cell.y, attempt, "cem_z"]))) * CELL)
		if plan.zone_at(target) != MacroMap.Zone.CITY or plan.district_at(target) != CityPlan.District.SUBURBS:
			_no("district")
			continue
		var a := plan.block_index_at(target)
		# Shapes: the 2 x 2 blocks round the target's block (which corner it is from the hash), then
		# two blocks in a row either way.
		var shapes: Array = []
		var corner := absi(hash([plan.seed, cell.x, cell.y, attempt, "cem_c"])) % 4
		for i in 4:
			var c := (corner + i) % 4
			var o := Vector2i(-(c & 1), -((c >> 1) & 1))
			shapes.append([a + o, Vector2i(2, 2)])
		shapes.append([a, Vector2i(2, 1)])
		shapes.append([a + Vector2i(-1, 0), Vector2i(2, 1)])
		shapes.append([a, Vector2i(1, 2)])
		shapes.append([a + Vector2i(0, -1), Vector2i(1, 2)])
		for sh: Array in shapes:
			var d := _fit(plan, cell, sh[0], sh[1])
			if not d.is_empty():
				out.merge(d)
				return out
	return out


## The site of the blocks from `k0`, `n` blocks each way, if every one of them may be taken.
static func _fit(plan: CityPlan, cell: Vector2i, k0: Vector2i, n: Vector2i) -> Dictionary:
	var blocks: Array[Vector2i] = []
	var site := Rect2()
	for dx in n.x:
		for dz in n.y:
			var k := k0 + Vector2i(dx, dz)
			var r := _block_rect(plan, k)
			if _cell_of(r.get_center()) != cell:
				return _fail("cell")
			if not _eligible(plan, k, r):
				return {}
			blocks.append(k)
			var inner := r.grow(-plan.sidewalk_width)
			site = inner if blocks.size() == 1 else site.merge(inner)
	var short := minf(site.size.x, site.size.y)
	var long := maxf(site.size.x, site.size.y)
	if short < MIN_SIZE.x or long < MIN_SIZE.y or long > MAX_SIZE or short > MAX_SIZE * 0.85:
		return _fail("size")
	# The streets between the blocks: local ones only, never a real (pinned) road.
	var closed: Array = []
	if n.x == 2:
		var idx := k0.x + 1
		if plan.road_width(CityPlan.AXIS_X, idx) > MAX_CLOSED_WIDTH or not DowntownReal.pin_at(CityPlan.AXIS_X, plan.road_pos(CityPlan.AXIS_X, idx)).is_empty():
			return _fail("street")
		closed.append([CityPlan.AXIS_X, idx, site.position.y - plan.sidewalk_width, site.end.y + plan.sidewalk_width])
	if n.y == 2:
		var idx := k0.y + 1
		if plan.road_width(CityPlan.AXIS_Z, idx) > MAX_CLOSED_WIDTH or not DowntownReal.pin_at(CityPlan.AXIS_Z, plan.road_pos(CityPlan.AXIS_Z, idx)).is_empty():
			return _fail("street")
		closed.append([CityPlan.AXIS_Z, idx, site.position.x - plan.sidewalk_width, site.end.x + plan.sidewalk_width])
	return {"cell": cell, "blocks": blocks, "site": site, "closed": closed}


static func _fail(reason: String) -> Dictionary:
	_no(reason)
	return {}


## Plain suburban city ground nobody else has a claim on, worked out without the block itself:
## Schools' list (zone, downtown, landmarks, freeway, light rail, approach, replica, sites, river,
## a fire station's block), the marina, and any block Parks might give a role whatever it rolled.
static func _eligible(plan: CityPlan, k: Vector2i, rect: Rect2) -> bool:
	var macro: MacroMap = plan.macro
	var district := plan.district_at(rect.get_center())
	if not (district in DISTRICTS):
		return _no("district")
	for p: Vector2 in [rect.position, rect.end, Vector2(rect.end.x, rect.position.y), Vector2(rect.position.x, rect.end.y), rect.get_center()]:
		if macro.zone_at(p) != MacroMap.Zone.CITY:
			return _no("zone")
	var area := rect.grow(4.0)
	if DowntownReal.in_extent(rect.get_center()) or Landmarks.claims(rect):
		return _no("landmark")
	if macro.freeway and macro.freeway.blocks_rect(area, 8.0):
		return _no("freeway")
	var rail := LightRail.of(plan)
	if rail != null and (rail.blocks_rect(area, 8.0) or not rail.cuts_in(area).is_empty()):
		return _no("rail")
	if macro.runway_clear_zone().grow(80.0).intersects(area):
		return _no("approach")
	if macro.replica and macro.replica._bounds.intersects(area.grow(40.0)):
		return _no("replica")
	if not plan.site_at_block(k.x, k.y).is_empty() or plan._beside_site(k.x, k.y):
		return _no("site")
	if plan.river_block(k.x, k.y) or plan.marina_block(k.x, k.y):
		return _no("river")
	if Schools._fire_station_block(plan, k):
		return _no("fire station")
	if Parks.enabled and Parks.role_for(plan, k.x, k.y, rect, district, _rolled_kind(plan, k, rect, district)) != "":
		return _no("parks")
	for lm in Landmarks.all():
		if lm.get("area") is Dictionary:
			continue
		var r: float = lm.radius
		if Rect2((lm.anchor as Vector2) - Vector2(r, r), Vector2(r, r) * 2.0).intersects(area):
			return _no("landmark")
	return true


## The kind CityPlan.block() rolls for block k before any override (its own first roll, the same
## stream), so Parks' role can be asked without making the block: only PARK and BUILDINGS matter
## to it, and the overrides that turn a mall or a plaza back into buildings are ruled out above.
static func _rolled_kind(plan: CityPlan, k: Vector2i, rect: Rect2, district: int) -> int:
	var params: Dictionary = CityPlan.DISTRICTS[district]
	var roll := plan._rng_for(3, k.x, k.y).randf()
	if roll < float(params.park):
		return CityPlan.BlockKind.PARK
	if roll < float(params.park) + float(params.plaza):
		return CityPlan.BlockKind.PLAZA
	var mall: float = params.get("mall", 0.0)
	var bigbox: float = params.get("bigbox", 0.0)
	var base := float(params.park) + float(params.plaza)
	if roll < base + mall and rect.size.x > 60.0 and rect.size.y > 60.0:
		return CityPlan.BlockKind.MALL
	if roll < base + mall + bigbox and rect.size.x > 80.0 and rect.size.y > 80.0:
		return CityPlan.BlockKind.BIGBOX
	return CityPlan.BlockKind.BUILDINGS


## CityPlan.road_open()'s question: whether the street (axis, index) at `along` runs through a
## memorial park (closed: the lawn covers it). Decides the cells round it first, so the answer is
## the same whichever was asked first.
static func road_closed(plan: CityPlan, axis: int, index: int, along: float) -> bool:
	if plan.macro == null:
		return false
	var key := Vector4i(plan.seed, axis, index, roundi(along * 4.0))
	var hit: Variant = _closed.get(key)
	if hit != null:
		return hit
	var pos := plan.road_pos(axis, index)
	var probe := Vector2(pos, along) if axis == CityPlan.AXIS_X else Vector2(along, pos)
	var c := _cell_of(probe)
	var out := false
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var d := decide(plan, c + Vector2i(dx, dz))
			if d.is_empty():
				continue
			for cl: Array in d.closed:
				if int(cl[0]) == axis and int(cl[1]) == index and along > float(cl[2]) and along < float(cl[3]):
					out = true
	if _closed.size() > 200000:
		_closed.clear()
	_closed[key] = out
	return out


# --- The plan -----------------------------------------------------------------------------------

## The site's plan ({} if the block is not a memorial park):
##   site (Rect2), seed, name, o / a / n (frame: origin on the front edge's left end, along, in),
##   L, D (along, deep), crown (Vector2 world), H (crown height), hx0/hx1/hz0/hz1 (the rise's extents
##   from the crown), gate (world point on the front edge), road (PackedVector2Array, closed loop
##   from the gate and back), chapel / mausoleum ({c, a (along), w, d, yaw}), old (Rect2 in frame:
##   the old section), trees ([pos, kind, height, yaw]), lamps ([pos]).
static func plan_for(plan: CityPlan, ix: int, iz: int) -> Dictionary:
	var b := plan.block(ix, iz)
	if String(b.get("grounds", "")) != "cemetery":
		return {}
	var cell: Vector2i = b.cemetery
	var key := Vector3i(plan.seed, cell.x, cell.y)
	if _plans.has(key):
		return _plans[key]
	var out := {}
	_plans[key] = out
	var d := decide(plan, cell)
	var site: Rect2 = d.site
	var kmin := Vector2i(1 << 30, 1 << 30)
	var kmax := Vector2i(-(1 << 30), -(1 << 30))
	for k: Vector2i in d.blocks:
		kmin = Vector2i(mini(kmin.x, k.x), mini(kmin.y, k.y))
		kmax = Vector2i(maxi(kmax.x, k.x), maxi(kmax.y, k.y))
	ix = kmin.x
	iz = kmin.y
	var s := int(hash([plan.seed, cell.x, cell.y, "cemetery"]))
	out.blocks = d.blocks
	out.closed = d.closed
	out.site = site
	out.seed = s
	out.name = NAMES[absi(s) % NAMES.size()] + " MEMORIAL PARK"
	# Front: the widest of the four streets (a hash breaks ties), so the gate opens on the boulevard.
	var widths := [
		plan.road_width(CityPlan.AXIS_Z, kmin.y),  # north edge (z0)
		plan.road_width(CityPlan.AXIS_Z, kmax.y + 1),  # south edge (z1)
		plan.road_width(CityPlan.AXIS_X, kmin.x),  # west edge (x0)
		plan.road_width(CityPlan.AXIS_X, kmax.x + 1),  # east edge (x1)
	]
	var front := 0
	var best := -1.0
	for i in 4:
		var w: float = widths[i] + _h01([s, i, "front"]) * 0.5
		if w > best:
			best = w
			front = i
	var o: Vector2
	var a: Vector2
	var n: Vector2
	match front:
		0:
			o = site.position
			a = Vector2(1, 0)
			n = Vector2(0, 1)
		1:
			o = Vector2(site.end.x, site.end.y)
			a = Vector2(-1, 0)
			n = Vector2(0, -1)
		2:
			o = Vector2(site.position.x, site.end.y)
			a = Vector2(0, -1)
			n = Vector2(1, 0)
		_:
			o = Vector2(site.end.x, site.position.y)
			a = Vector2(0, 1)
			n = Vector2(-1, 0)
	var L := site.size.x if front < 2 else site.size.y
	var D := site.size.y if front < 2 else site.size.x
	out.front = front
	out.o = o
	out.a = a
	out.n = n
	out.L = L
	out.D = D
	# The rise: crown a little off the middle, toward the back.
	var cu := L * lerpf(0.4, 0.6, _h01([s, "cu"]))
	var cv := D * lerpf(0.5, 0.62, _h01([s, "cv"]))
	var crown := fp(out, cu, cv)
	out.crown = crown
	out.crown_uv = Vector2(cu, cv)
	out.H = clampf(minf(L, D) * HILL_SHARE, HILL_MIN, HILL_MAX)
	out.hx0 = crown.x - site.position.x - EDGE
	out.hx1 = site.end.x - EDGE - crown.x
	out.hz0 = crown.y - site.position.y - EDGE
	out.hz1 = site.end.y - EDGE - crown.y
	# The gate on the front, a little off its middle.
	var gu := L * lerpf(0.38, 0.62, _h01([s, "gu"]))
	out.gate_u = gu
	out.gate = fp(out, gu, 0.0)
	# The mausoleum on the crown, its front toward the gate.
	out.mausoleum = {"c": crown, "w": MAUSOLEUM.x, "d": MAUSOLEUM.y, "f": _face_to(crown, out.gate)}
	# The drive: in from the gate, round the crown as a wobbling loop, back to the gate.
	out.road = _road(out)
	# The chapel beside the drive near the gate, on the side with more room.
	var side := 1.0 if gu < L * 0.5 else -1.0
	var ch_u := gu + side * (ROAD_W * 0.5 + 6.0 + CHAPEL.x * 0.5)
	var ch_v := 6.0 + CHAPEL.y * 0.5
	out.chapel = {"c": fp(out, ch_u, ch_v), "w": CHAPEL.x, "d": CHAPEL.y, "f": -n, "uv": Vector2(ch_u, ch_v), "side": side}
	# The old section: the back corner away from the chapel.
	var old_u0 := 0.0 if side > 0.0 else L * 0.5
	out.old = Rect2(old_u0 + EDGE, D * 0.55, L * 0.5 - EDGE, D * 0.45 - EDGE)
	out.trees = _trees(out)
	out.lamps = _lamps(out)
	return out


## A point of the plan's frame (u along the front, v in from it) in world XZ.
static func fp(pl: Dictionary, u: float, v: float) -> Vector2:
	return (pl.o as Vector2) + (pl.a as Vector2) * u + (pl.n as Vector2) * v


## A world XZ point in the plan's frame (u, v).
static func to_uv(pl: Dictionary, p: Vector2) -> Vector2:
	var d := p - (pl.o as Vector2)
	return Vector2(d.dot(pl.a), d.dot(pl.n))


## The unit direction from `from` toward `to`, snapped to the nearer of the site's two axes.
static func _face_to(from: Vector2, to: Vector2) -> Vector2:
	var d := to - from
	if absf(d.x) > absf(d.y):
		return Vector2(signf(d.x), 0.0)
	return Vector2(0.0, signf(d.y))


## The rise's height over the pavement at world XZ `p` (0 outside the rise, at the edge band).
static func height(pl: Dictionary, p: Vector2) -> float:
	var crown: Vector2 = pl.crown
	var dx := p.x - crown.x
	var dz := p.y - crown.y
	var ux := dx / (float(pl.hx1) if dx > 0.0 else float(pl.hx0))
	var uz := dz / (float(pl.hz1) if dz > 0.0 else float(pl.hz0))
	var r := pow(pow(absf(ux), 3.0) + pow(absf(uz), 3.0), 1.0 / 3.0)
	var h := float(pl.H) * (1.0 - smoothstep(0.12, 1.0, r))
	# Gentle swells across it, so the turf is not a lathe-turned dome.
	var sw := sin(p.x * 0.071 + float(pl.seed % 97)) * sin(p.y * 0.053 + float(pl.seed % 61)) * 0.35
	return maxf(h + sw * smoothstep(1.0, 0.6, r), 0.0) if r < 1.0 else 0.0


## The drive as a closed polyline (world XZ), ~3 m a point: gate, in, the loop, out.
static func _road(pl: Dictionary) -> PackedVector2Array:
	var L: float = pl.L
	var D: float = pl.D
	var cuv: Vector2 = pl.crown_uv
	var gu: float = pl.gate_u
	var s: int = pl.seed
	# The loop's radii: clear of the mausoleum, inside the edge with room for graves both sides.
	var ru := clampf(minf(cuv.x, L - cuv.x) - 18.0, MAUSOLEUM.x * 0.5 + 14.0, 200.0)
	var rv := clampf(minf(cuv.y - 22.0, D - cuv.y) - 14.0, MAUSOLEUM.y * 0.5 + 12.0, 200.0)
	var pts := PackedVector2Array()
	pts.append(Vector2(gu, 0.0))
	pts.append(Vector2(gu, 8.0))
	# The loop starts and ends at its point nearest the gate (the bottom, toward the front).
	var start := atan2(-1.0, (gu - cuv.x) / ru)
	var steps := int(TAU * (ru + rv) * 0.5 / 3.0)
	var ph1 := _h01([s, "w1"]) * TAU
	var ph2 := _h01([s, "w2"]) * TAU
	var loop := PackedVector2Array()
	for i in steps + 1:
		var t := start + TAU * float(i) / float(steps)
		var wob := 1.0 + 0.09 * sin(t * 3.0 + ph1) + 0.05 * sin(t * 5.0 + ph2)
		loop.append(cuv + Vector2(cos(t) * ru, sin(t) * rv) * wob)
	# From the entry straight to the loop's start, round, and back down.
	var entry := Vector2(gu, 8.0)
	var first := loop[0]
	var lead := int(entry.distance_to(first) / 3.0)
	for i in range(1, lead):
		pts.append(entry.lerp(first, float(i) / float(lead)))
	pts.append_array(loop)
	var out := PackedVector2Array()
	for p in pts:
		out.append(fp(pl, p.x, p.y))
	return out


## Distance from world XZ `p` to the drive's centre line.
static func road_distance(pl: Dictionary, p: Vector2) -> float:
	var road: PackedVector2Array = pl.road
	var best := INF
	for i in road.size() - 1:
		var q := Geometry2D.get_closest_point_to_segment(p, road[i], road[i + 1])
		best = minf(best, p.distance_squared_to(q))
	return sqrt(best)


## Whether world XZ `p` (grown by `pad`) falls on a building's footprint (chapel or mausoleum).
static func on_building(pl: Dictionary, p: Vector2, pad: float) -> bool:
	for k: String in ["chapel", "mausoleum"]:
		var bd: Dictionary = pl[k]
		var f: Vector2 = bd.f
		var side := Vector2(-f.y, f.x)
		var d := p - (bd.c as Vector2)
		# The mausoleum's steps and portico stand out in front of it.
		var front_pad := 6.0 if k == "mausoleum" else 3.0
		var along_f := d.dot(f)
		if absf(d.dot(side)) <= float(bd.w) * 0.5 + pad and along_f <= float(bd.d) * 0.5 + pad + front_pad and along_f >= -float(bd.d) * 0.5 - pad:
			return true
	return false


## Mature trees: [world XZ, kind, height m, yaw]. Kinds: 0-4 the city broadleaf species (CITY_TREES),
## 6 Italian cypress (CemeteryKit.cypress()), 7 a palm (5, a hill pine, is no longer planted: the
## scan reads as a dead tree at this size). Rows of cypress along the entry drive, pines and
## shade trees in loose groves over the lawn, nothing on the drive or a building.
static func _trees(pl: Dictionary) -> Array:
	var out: Array = []
	var s: int = pl.seed
	var L: float = pl.L
	var D: float = pl.D
	var gu: float = pl.gate_u
	# Cypress pairs flanking the entry drive.
	var v := 12.0
	while v < 40.0:
		for side: float in [-1.0, 1.0]:
			var p := fp(pl, gu + side * (ROAD_W * 0.5 + 2.2), v)
			if not on_building(pl, p, 2.0):
				out.append([p, 6, lerpf(9.0, 12.0, _h01([s, v, side, "cy"])), 0.0])
		v += 7.5
	# Groves: a jittered grid, thinned by a slow noise so trees stand in clumps with open lawn between.
	var step := 12.0
	var nu := int(L / step)
	var nv := int(D / step)
	for i in nu:
		for j in nv:
			var hu := _h01([s, i, j, "tu"])
			var hv := _h01([s, i, j, "tv"])
			var u := (float(i) + 0.2 + 0.6 * hu) * step
			var vv := (float(j) + 0.2 + 0.6 * hv) * step
			var clump := 0.5 + 0.5 * sin(u * 0.045 + float(s % 13)) * cos(vv * 0.05 + float(s % 7))
			if _h01([s, i, j, "tk"]) > 0.25 + clump * 0.6:
				continue
			if u < EDGE + 2.5 or u > L - EDGE - 2.5 or vv < EDGE + 4.0 or vv > D - EDGE - 2.5:
				continue
			var p := fp(pl, u, vv)
			if road_distance(pl, p) < ROAD_W * 0.5 + 3.0 or on_building(pl, p, 5.0):
				continue
			var roll := _h01([s, i, j, "tkind"])
			var kind := 5
			var h := 0.0
			if roll < 0.3:
				# Old shade trees: the jacaranda and the big broadleaf grown mature.
				kind = 4 if _h01([s, i, j, "jac"]) < 0.45 else 0
				h = 0.0
			elif roll < 0.48:
				kind = 6
				h = lerpf(9.0, 13.0, hv)
			elif roll < 0.58:
				kind = 7
				h = 0.0
			else:
				var species := [0, 2, 0, 4, 2]
				kind = species[absi(hash([s, i, j, "sp"])) % species.size()]
				h = 0.0
			out.append([p, kind, h, hu * TAU])
	return out


## Low lamps along the drive (every LAMP_STEP metres of it) and the two lanterns on the gate piers.
const LAMP_STEP := 42.0


static func _lamps(pl: Dictionary) -> Array:
	var out: Array = []
	var road: PackedVector2Array = pl.road
	var run := 0.0
	var next := 20.0
	for i in road.size() - 1:
		var seg := road[i].distance_to(road[i + 1])
		if run + seg >= next:
			var d := (road[i + 1] - road[i]).normalized()
			var side := Vector2(-d.y, d.x)
			out.append(road[i] + side * (ROAD_W * 0.5 + 1.0))
			next += LAMP_STEP
		run += seg
	return out


# --- The graves ---------------------------------------------------------------------------------

## Granite colours (sRGB): grey, charcoal, black, India red, rose, Sierra white, blue pearl.
const GRANITE := [Color(0.46, 0.46, 0.45), Color(0.26, 0.26, 0.27), Color(0.07, 0.07, 0.08), Color(0.38, 0.17, 0.14),
	Color(0.58, 0.44, 0.41), Color(0.68, 0.68, 0.66), Color(0.17, 0.19, 0.23)]
const MARBLE := Color(0.84, 0.83, 0.79)
## Plots left empty (unsold, or a grave not yet marked).
const EMPTY_ODDS := 0.13
const VASE_ODDS := 0.22
## The older monuments on a coarse grid in the old section.
const MONUMENT_PITCH := 7.0
const MONUMENT_ODDS := 0.42


## The keep-out mask (1 m cells over the site): the drive and its verges, the buildings and their
## steps, the trees' trunks, the gate's lane. Built once per plan.
static func _mask(pl: Dictionary) -> PackedByteArray:
	if pl.has("mask"):
		return pl.mask
	var site: Rect2 = pl.site
	var nx := ceili(site.size.x)
	var nz := ceili(site.size.y)
	var m := PackedByteArray()
	m.resize(nx * nz)
	var mark := func(c: Vector2, r: float) -> void:
		for j in range(maxi(0, floori(c.y - r - site.position.y)), mini(nz, ceili(c.y + r - site.position.y) + 1)):
			for i in range(maxi(0, floori(c.x - r - site.position.x)), mini(nx, ceili(c.x + r - site.position.x) + 1)):
				var q := site.position + Vector2(float(i) + 0.5, float(j) + 0.5)
				if q.distance_to(c) <= r:
					m[j * nx + i] = 1
	var road: PackedVector2Array = pl.road
	var rr := ROAD_W * 0.5 + 1.4
	for i in road.size() - 1:
		var a := road[i]
		var b := road[i + 1]
		var n := maxi(1, ceili(a.distance_to(b) / 0.7))
		for k in n + 1:
			mark.call(a.lerp(b, float(k) / float(n)), rr)
	for t: Array in pl.trees:
		mark.call(t[0] as Vector2, 2.0 if int(t[1]) == 6 else 2.6)
	# The buildings and the gate's lane: only the cells round each.
	var boxes: Array[Rect2] = []
	for k: String in ["chapel", "mausoleum"]:
		var bd: Dictionary = pl[k]
		var r := maxf(float(bd.w), float(bd.d)) * 0.5 + 10.0
		boxes.append(Rect2((bd.c as Vector2) - Vector2(r, r), Vector2(r, r) * 2.0))
	var gr := 18.0
	boxes.append(Rect2((pl.gate as Vector2) - Vector2(gr, gr), Vector2(gr, gr) * 2.0))
	for bx in boxes:
		for j in range(maxi(0, floori(bx.position.y - site.position.y)), mini(nz, ceili(bx.end.y - site.position.y))):
			for i in range(maxi(0, floori(bx.position.x - site.position.x)), mini(nx, ceili(bx.end.x - site.position.x))):
				var q := site.position + Vector2(float(i) + 0.5, float(j) + 0.5)
				if on_building(pl, q, 3.0):
					m[j * nx + i] = 1
				else:
					var uv := to_uv(pl, q)
					if absf(uv.x - float(pl.gate_u)) < 7.5 and uv.y < 16.0:
						m[j * nx + i] = 1
	pl.mask = m
	pl.mask_n = Vector2i(nx, nz)
	return m


static func _masked(pl: Dictionary, p: Vector2) -> bool:
	var m := _mask(pl)
	var n: Vector2i = pl.mask_n
	var site: Rect2 = pl.site
	var i := floori(p.x - site.position.x)
	var j := floori(p.y - site.position.y)
	if i < 0 or j < 0 or i >= n.x or j >= n.y:
		return true
	return m[j * n.x + i] != 0


## The old section's monuments: [key, world XZ]. Built once per plan.
static func _monuments(pl: Dictionary) -> Array:
	if pl.has("monuments"):
		return pl.monuments
	var out: Array = []
	var old: Rect2 = pl.old
	var s: int = pl.seed
	var nu := int(old.size.x / MONUMENT_PITCH)
	var nv := int(old.size.y / MONUMENT_PITCH)
	var kinds := ["obelisk", "column", "family", "family", "coping", "obelisk"]
	for i in nu:
		for j in nv:
			if _h01([s, i, j, "mon"]) > MONUMENT_ODDS:
				continue
			var u := old.position.x + (float(i) + 0.5) * MONUMENT_PITCH
			var v := old.position.y + (float(j) + 0.5) * MONUMENT_PITCH
			var p := fp(pl, u, v)
			if _masked(pl, p):
				continue
			out.append([kinds[absi(hash([s, i, j, "monk"])) % kinds.size()], p])
	pl.monuments = out
	return out


## The stones standing in `own` (world rect), every `slices`-th row from `slice` (monuments in
## slice 0): [mesh key (CemeteryKit), world XZ, yaw, colour (sRGB), custom (weathering, lichen,
## seed, flower colour), lean (rad)]. Rows run along the front street, the lettered faces toward
## it; the old section is marble tablets, crosses and gothic stones round the monuments, the back
## half of the rest mixes upright granite into the flat markers.
static func graves(pl: Dictionary, own: Rect2, slice: int, slices: int) -> Array:
	var out: Array = []
	var s: int = pl.seed
	var n: Vector2 = pl.n
	var face := atan2(-n.x, -n.y)
	var L: float = pl.L
	var D: float = pl.D
	var old: Rect2 = pl.old
	var mons := _monuments(pl)
	if slice == 0:
		for m: Array in mons:
			var p: Vector2 = m[1]
			if own.has_point(p):
				var hm := absi(hash([s, p.x, p.y]))
				var marble: bool = m[0] == "column"
				var col: Color = MARBLE if marble else GRANITE[hm % GRANITE.size()]
				out.append([m[0], p, face, col, Color(lerpf(0.5, 1.0, float(hm % 97) / 97.0), lerpf(0.3, 0.9, float(hm % 89) / 89.0), float(hm % 83) / 83.0, 0.0), 0.0])
	var uvs: Array[Vector2] = [to_uv(pl, own.position), to_uv(pl, own.end), to_uv(pl, Vector2(own.end.x, own.position.y)), to_uv(pl, Vector2(own.position.x, own.end.y))]
	var umin := INF
	var umax := -INF
	var vmin := INF
	var vmax := -INF
	for q in uvs:
		umin = minf(umin, q.x)
		umax = maxf(umax, q.x)
		vmin = minf(vmin, q.y)
		vmax = maxf(vmax, q.y)
	var v0 := EDGE + 4.5
	var u0 := EDGE + 2.6
	var rows := int((D - EDGE - 2.5 - v0) / ROW_PITCH) + 1
	var cols := int((L - EDGE - 2.6 - u0) / GRAVE_PITCH) + 1
	for r in rows:
		if r % slices != slice or r % AISLE_EVERY == AISLE_EVERY - 1:
			continue
		var v := v0 + float(r) * ROW_PITCH
		if v < vmin - 1.0 or v > vmax + 1.0:
			continue
		for c in cols:
			if c % 16 == 15:
				continue
			var u := u0 + float(c) * GRAVE_PITCH
			if u < umin - 1.0 or u > umax + 1.0:
				continue
			var p := fp(pl, u, v)
			if not own.has_point(p):
				continue
			var hh := _h01([s, r, c, "g"])
			if hh < EMPTY_ODDS or _masked(pl, p):
				continue
			var near_mon := false
			for m: Array in mons:
				if p.distance_to(m[1]) < (2.9 if m[0] == "coping" else 2.0):
					near_mon = true
					break
			if near_mon:
				continue
			var roll := _h01([s, r, c, "k"])
			var hs := absi(hash([s, r, c, "c"]))
			var col: Color = GRANITE[hs % GRANITE.size()]
			var seed01 := float(hs % 1009) / 1009.0
			var key := "flat"
			var weather := lerpf(0.0, 0.2, _h01([s, r, c, "w"]))
			var lichen := 0.0
			var lean := 0.0
			if old.has_point(Vector2(u, v)):
				weather = lerpf(0.45, 1.0, _h01([s, r, c, "w"]))
				lichen = lerpf(0.15, 0.9, _h01([s, r, c, "l"]))
				if roll < 0.42:
					key = "marble"
					col = MARBLE
					lean = (_h01([s, r, c, "lean"]) - 0.5) * 0.09
				elif roll < 0.6:
					key = "gothic"
				elif roll < 0.74:
					key = "cross"
					col = MARBLE
				elif roll < 0.9:
					key = "tablet"
				else:
					key = "slant"
			elif v > D * 0.5 and roll < 0.32:
				key = ["tablet", "slant", "tablet", "gothic"][absi(hash([s, r, c, "u"])) % 4]
			elif _h01([s, r, c, "vase"]) < VASE_ODDS:
				key = "flat_vase"
			# Upright stones in a row stand at the head of the grave, a hand back from the row line.
			out.append([key, p, face, col, Color(weather, lichen, seed01, float(hs % 5) / 8.0), lean])
	return out
