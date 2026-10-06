class_name Canals
extends RefCounted
## The canal neighbourhood behind the boardwalk (2026-10-05, "a canal neighbourhood in the beach
## town - the form of the Venice canals"). Original names: the neighbourhood is MARISOL CANALS,
## its waterways Heron, Lantern, Mariner, Juniper and Coral.
##
## What it is: a grid of narrow, shallow, still canals (CANAL_W 15 m between the bank tops), each
## with sloped planted banks, a concrete coping and a walkway along both sides; arched white
## footbridges across every stretch between crossings; houses on narrow lots facing the water with
## small gardens down to the walk, a gate in a low fence, a porch light by the door; timber docks
## with rowboats, kayaks and canoes moored at them. No cars: every street inside is closed.
##
## How it sits on the map: its Landmarks entry carries an "area" (like MacArthur Park), which
## CityPlan snaps to the four perimeter streets and closes every road between them
## (CityPlan.road_open()); the perimeter streets stay open, so the neighbourhood is ringed by
## ordinary residential streets. Its chunks build their own part of it (site_steps()), as
## MacArthur Park's do; the far city records its ground and its houses (capture_steps()).
## Nothing here touches a block rng: every roll is a hash of the seed and the place.
##
## The water is BELOW the city's ground box (CityStreamer's GroundBody, top at 0): the bed is at
## FLOOR_Y. A volume over each canal lets bodies through the box while they are in it (_sink, the
## lake's rule), so the player wades in at knee depth. FLOOR_Y must stay above
## CityStreamer.under_city_ground()'s 1.5 m, or a player standing on the bed is lifted out.
##
## Layout, in world XZ (layout(), pure and cached per plan): the site rect less a pavement ring is
## cut by NS_COUNT canals running north-south and EW_COUNT running east-west. A canal's CORRIDOR is
## its water and banks (|o| < HALF, o the offset from its centre line), its BAND the corridor plus
## a walkway each side. What the bands leave are ISLANDS of lots: an edge island holds one row of
## lots facing its canal (backing onto the perimeter street's pavement), a middle island two rows
## back to back, each facing its own canal.

const SITE_ID := "venice_canals"
const NAME := "MARISOL CANALS"
## North-south canals first (west to east), then east-west (north to south).
const CANAL_NAMES := ["HERON CANAL", "LANTERN CANAL", "MARINER CANAL", "JUNIPER CANAL", "CORAL CANAL"]

## Off, there is no entry and no site: the blocks are ordinary beach-town blocks (the A/B:
## CANALS=0 in the environment). Set before the city scene loads (Landmarks.all() is built once).
static var enabled: bool = OS.get_environment("CANALS") != "0"

# --- Where -----------------------------------------------------------------------------------
## The site CityPlan snaps to whole blocks (world metres): two blocks by two, a block inland of
## the boardwalk's shop strip, between the streets at x -824 / -645 and z -403 / 0 on the default
## seed. The snapped rect follows whatever grid another seed has.
const ANCHOR := Vector2(-735.0, -200.0)
const WEST_X := -824.0
const EAST_X := -645.0
const NORTH_Z := -403.0
const SOUTH_Z := 0.0

# --- The section (metres) -----------------------------------------------------------------------
## Pavement ring round the site, inside the perimeter kerbs.
const PAVEMENT := 4.0
## Bank top to bank top.
const CANAL_W := 15.0
const HALF := 7.5
## The concrete coping on the bank top: from COPE_IN to HALF.
const COPE_IN := 7.1
## The bed: flat out to BED_HALF, then the bank rises to the coping.
const BED_HALF := 4.6
## Walkway width each side.
const WALK_W := 2.6
## Lot depth in an edge island (one row) and the target frontage.
const EDGE_LOT := 24.0
const LOT_W := 11.5
## The front garden strip between the walk and the yard HouseKit plans the house in.
const GARDEN := 1.6
## The walk alley down the middle of a two-row island, between the back fences.
const ALLEY := 5.0
const NS_COUNT := 2
const EW_COUNT := 3

# --- Heights (metres above the city datum; the relief is flat round a landmark) -------------------
const WALK_Y := CityChunk.SIDEWALK_TOP
const LAWN_Y := CityChunk.SIDEWALK_TOP + 0.03
const COPE_Y := CityChunk.SIDEWALK_TOP + 0.08
## Where the bank meets the coping's face.
const BANK_TOP_Y := 0.12
const WATER_Y := -0.62
const FLOOR_Y := -1.2
const WALL_BOTTOM := -1.7

# --- Density and draw -------------------------------------------------------------------------
## Docks: the share of lots with one; boats moored at a dock; extra boats tied to the bank.
const DOCK_ODDS := 0.34
const BANK_BOAT_ODDS := 0.12
## Reeds and bank planting per metre of bank (each side), FULL only.
const REEDS_PER_M := 0.55
const BANK_SHRUBS_PER_M := 0.09
## Walkers per metre of walkway.
const WALKERS_PER_M := 1.0 / 45.0
## Trees in the yards: the share of lots with one.
const YARD_TREE_ODDS := 0.6
## Draw distances.
const BOAT_DRAW := 180.0
const FENCE_DRAW := 160.0
const PLANT_DRAW := 90.0
const BRIDGE_DRAW := 600.0

# Canal house types: the beach town's stucco boxes and Spanish revival, the cottage (a craftsman
# or a ranch, usually in lap siding) and the modern box (mid-century or a flat-roofed box with a
# wall of glass to the water). No dingbats: a tuck-under carport has no street here.
const STYLES := [[HouseKit.Style.STUCCO_BOX, 0.36], [HouseKit.Style.MIDCENTURY, 0.52], [HouseKit.Style.CRAFTSMAN, 0.70],
	[HouseKit.Style.SPANISH, 0.86], [HouseKit.Style.RANCH, 1.0]]

static var _layouts: Dictionary = {}


## The entry Landmarks.all() lists: id, anchor, a radius (relief flattening, the minimap) and the
## area CityPlan snaps to the grid. No kept roads: no street runs through the canals.
static func entry() -> Dictionary:
	return {"id": SITE_ID, "anchor": ANCHOR, "radius": 215.0,
		"area": {"west_x": WEST_X, "east_x": EAST_X, "north_z": NORTH_Z, "south_z": SOUTH_Z, "keep_z": [], "streets": {}}}


static func _h01(parts: Array) -> float:
	return float(absi(hash(parts)) % 100003) / 100003.0


# =================================================================================================
# Layout (pure)
# =================================================================================================

## {"rect", "inner", "canals": [{"axis" (0 runs along z, across = x; 1 runs along x), "c", "a0",
## "a1", "name"}], "corridors": [Rect2], "bands": [Rect2], "islands": [Rect2], "lots": [...],
## "bridges": [{"canal", "at" (Vector2), "axis"}], "walks": [Rect2], "copes": [Rect2],
## "ring": [Rect2]}. {} with no such site (no macro map, or the site is off).
static func layout(plan: CityPlan) -> Dictionary:
	if plan == null:
		return {}
	var key := plan.get_instance_id()
	if _layouts.has(key):
		return _layouts[key]
	var lay := _make_layout(plan)
	_layouts[key] = lay
	return lay


static func _make_layout(plan: CityPlan) -> Dictionary:
	var s := plan.site_by_id(SITE_ID)
	if s.is_empty():
		return {}
	var R: Rect2 = s.rect
	var I := R.grow(-PAVEMENT)
	var canals: Array = []
	var ns_x := [I.position.x + EDGE_LOT + WALK_W + HALF, I.end.x - (EDGE_LOT + WALK_W + HALF)]
	for k in NS_COUNT:
		canals.append({"axis": 0, "c": float(ns_x[k]), "a0": I.position.y, "a1": I.end.y, "name": CANAL_NAMES[k]})
	for k in EW_COUNT:
		var z := I.position.y + I.size.y * float(k + 1) / float(EW_COUNT + 1)
		canals.append({"axis": 1, "c": z, "a0": I.position.x, "a1": I.end.x, "name": CANAL_NAMES[(NS_COUNT + k) % CANAL_NAMES.size()]})
	var corridors: Array[Rect2] = []
	var bands: Array[Rect2] = []
	for c: Dictionary in canals:
		corridors.append(_canal_rect(c, HALF))
		bands.append(_canal_rect(c, HALF + WALK_W))
	# Islands: the cells between the bands.
	var xs: Array = [I.position.x]
	for k in NS_COUNT:
		xs.append(float(ns_x[k]) - HALF - WALK_W)
		xs.append(float(ns_x[k]) + HALF + WALK_W)
	xs.append(I.end.x)
	var zs: Array = [I.position.y]
	for k in EW_COUNT:
		var c: Dictionary = canals[NS_COUNT + k]
		zs.append(float(c.c) - HALF - WALK_W)
		zs.append(float(c.c) + HALF + WALK_W)
	zs.append(I.end.y)
	var islands: Array[Rect2] = []
	var lots: Array = []
	var alleys: Array[Rect2] = []
	for i in range(0, xs.size(), 2):
		for j in range(0, zs.size(), 2):
			var isl := Rect2(xs[i], zs[j], float(xs[i + 1]) - float(xs[i]), float(zs[j + 1]) - float(zs[j]))
			islands.append(isl)
			var col := i / 2
			var rows: Array = []
			if col == 0:
				rows.append([isl, 3])
			elif col == NS_COUNT:
				rows.append([isl, 2])
			else:
				# Two rows back to back with a paved walk alley between their back fences.
				var mid := isl.position.x + isl.size.x * 0.5
				var a0 := mid - ALLEY * 0.5
				var a1 := mid + ALLEY * 0.5
				alleys.append(Rect2(a0, isl.position.y, ALLEY, isl.size.y))
				rows.append([Rect2(isl.position.x, isl.position.y, a0 - isl.position.x, isl.size.y), 2])
				rows.append([Rect2(a1, isl.position.y, isl.end.x - a1, isl.size.y), 3])
			for r: Array in rows:
				# The back line's fence: an edge row's (on the pavement), or the west row's of two.
				var back := true
				_row_lots(plan, r[0], int(r[1]), lots, col, j / 2, back)
	# Walkways: each canal's two side strips, less every corridor, the NS ones taking the corners.
	var walks: Array[Rect2] = []
	var copes: Array[Rect2] = []
	var inner_cuts: Array[Rect2] = []
	for c: Dictionary in canals:
		inner_cuts.append(_canal_rect(c, COPE_IN))
	for ci in canals.size():
		var c: Dictionary = canals[ci]
		for sgn: float in [-1.0, 1.0]:
			var strip := _side_strip(c, HALF, HALF + WALK_W, sgn)
			var holes: Array = corridors.duplicate()
			var cope := _side_strip(c, COPE_IN, HALF, sgn)
			var cope_holes: Array = inner_cuts.duplicate()
			if int(c.axis) == 1:
				for cj in canals.size():
					var o: Dictionary = canals[cj]
					if int(o.axis) == 0:
						for sg2: float in [-1.0, 1.0]:
							holes.append(_side_strip(o, HALF, HALF + WALK_W, sg2))
							cope_holes.append(_side_strip(o, COPE_IN, HALF, sg2))
			walks.append_array(Parks.minus(strip, holes, 0.05))
			copes.append_array(Parks.minus(cope, cope_holes, 0.05))
	# Bridges: the middle of every stretch of canal between two crossings (or a crossing and an
	# end), turned across it.
	var bridges: Array = []
	for ci in canals.size():
		var c: Dictionary = canals[ci]
		var cuts: Array = [float(c.a0)]
		for o: Dictionary in canals:
			if int(o.axis) != int(c.axis):
				cuts.append(float(o.c) - HALF - WALK_W)
				cuts.append(float(o.c) + HALF + WALK_W)
		cuts.append(float(c.a1))
		cuts.sort()
		for k in range(0, cuts.size() - 1, 2):
			var a := (float(cuts[k]) + float(cuts[k + 1])) * 0.5
			if float(cuts[k + 1]) - float(cuts[k]) < 30.0:
				continue
			var at := Vector2(float(c.c), a) if int(c.axis) == 0 else Vector2(a, float(c.c))
			bridges.append({"canal": ci, "at": at, "axis": int(c.axis), "seed": hash([plan.seed, "canal_bridge", ci, k])})
	# Docks: the lot's front middle, kept off the bridges' landings.
	for lot: Dictionary in lots:
		lot["dock"] = false
		if _h01([plan.seed, lot.seed, "dock"]) >= DOCK_ODDS:
			continue
		var p: Vector2 = lot.dock_at
		var clear := true
		for b: Dictionary in bridges:
			if (b.at as Vector2).distance_to(p) < 9.0 + HALF:
				clear = false
		lot["dock"] = clear
	var ring: Array[Rect2] = Parks.minus(R, [I], 0.05)
	walks.append_array(alleys)
	return {"rect": R, "inner": I, "canals": canals, "corridors": corridors, "bands": bands, "islands": islands,
		"lots": lots, "bridges": bridges, "walks": walks, "copes": copes, "ring": ring, "site": s}


## A canal's rect out to offset `half` either side of its centre line, along its whole length.
static func _canal_rect(c: Dictionary, half: float) -> Rect2:
	if int(c.axis) == 0:
		return Rect2(float(c.c) - half, float(c.a0), half * 2.0, float(c.a1) - float(c.a0))
	return Rect2(float(c.a0), float(c.c) - half, float(c.a1) - float(c.a0), half * 2.0)


## The strip between offsets o0 and o1 on one side (`sgn`) of a canal, along its whole length.
static func _side_strip(c: Dictionary, o0: float, o1: float, sgn: float) -> Rect2:
	var lo := float(c.c) + (o0 if sgn > 0.0 else -o1)
	if int(c.axis) == 0:
		return Rect2(lo, float(c.a0), o1 - o0, float(c.a1) - float(c.a0))
	return Rect2(float(c.a0), lo, float(c.a1) - float(c.a0), o1 - o0)


## One row of lots along z in `r`, fronting side `side` (2: the front at x min, 3: at x max).
static func _row_lots(plan: CityPlan, r: Rect2, side: int, out: Array, col: int, row: int, back_fence: bool) -> void:
	var n := maxi(1, roundi(r.size.y / LOT_W))
	var w := r.size.y / float(n)
	for k in n:
		var cell := Rect2(r.position.x, r.position.y + w * k, r.size.x, w)
		var sd := hash([plan.seed, "canal_lot", col, row, side, k])
		# The garden strip on the walk, then the yard HouseKit plans the house in.
		var garden: Rect2
		var yard: Rect2
		var front_x: float
		var dir: float
		if side == 2:
			garden = Rect2(cell.position.x, cell.position.y, GARDEN, cell.size.y)
			yard = Rect2(cell.position.x + GARDEN, cell.position.y, cell.size.x - GARDEN, cell.size.y)
			front_x = cell.position.x
			dir = -1.0
		else:
			garden = Rect2(cell.end.x - GARDEN, cell.position.y, GARDEN, cell.size.y)
			yard = Rect2(cell.position.x, cell.position.y, cell.size.x - GARDEN, cell.size.y)
			front_x = cell.end.x
			dir = 1.0
		out.append({"seed": sd, "center": cell.get_center(), "size": cell.size, "cell": cell, "side": side,
			"yard": yard, "garden": garden, "front_x": front_x, "dir": dir, "first": k == 0, "back_fence": back_fence,
			# The dock's point on the canal's centre line side of the walk, level with the lot.
			"dock_at": Vector2(front_x + dir * (WALK_W + HALF - CanalKit.DOCK_O), cell.get_center().y)})


## The house a canal lot gets: HouseKit's plan, fronted on the canal, with the garage taken out
## (no street reaches the canal side) and, on a modern box, a wall of glass to the water.
static func house_for(plan: CityPlan, lot: Dictionary) -> Dictionary:
	if lot.has("house"):
		return lot.house
	var front := {"side": int(lot.side), "yard": lot.yard, "walk_front": true, "styles": STYLES}
	var h := HouseKit.plan_fronted(plan, lot, CityPlan.District.BEACHTOWN, front)
	if not (h.garage as Dictionary).is_empty():
		var gw: Dictionary = h.wings[int(h.garage.wing)]
		if gw.role == "garage" or gw.role == "carport":
			gw.role = "room"
		h.garage = {}
		h.drive = Vector2.ZERO
	var style: int = h.style
	if style == HouseKit.Style.MIDCENTURY or (style == HouseKit.Style.STUCCO_BOX and _h01([plan.seed, lot.seed, "glass"]) < 0.55):
		h["glass_front"] = true
	lot["house"] = h
	return h


## The across offset of world point `p` from the nearest canal centre line it lies along (INF
## outside every canal's length): what the bank height is a function of.
static func canal_offset(lay: Dictionary, p: Vector2) -> float:
	var best := INF
	for c: Dictionary in lay.canals:
		var along := p.y if int(c.axis) == 0 else p.x
		if along < float(c.a0) - 0.01 or along > float(c.a1) + 0.01:
			continue
		var o := absf((p.x if int(c.axis) == 0 else p.y) - float(c.c))
		best = minf(best, o)
	return best


## The bank's height at offset `o` from the centre line.
static func bank_y(o: float) -> float:
	if o <= BED_HALF:
		return FLOOR_Y
	if o >= COPE_IN:
		return BANK_TOP_Y
	var t := (o - BED_HALF) / (COPE_IN - BED_HALF)
	# A little concave at the toe, steeper toward the top, as a dredged earth bank stands.
	return lerpf(FLOOR_Y, BANK_TOP_Y, lerpf(t, t * t, 0.35))


## True when world XZ `p` is over a canal's water or banks.
static func in_canal(lay: Dictionary, p: Vector2) -> bool:
	return canal_offset(lay, p) < HALF


# =================================================================================================
# The chunk's steps
# =================================================================================================

## Per-chunk accumulator: SurfaceTools by material, collision faces.
class Acc extends RefCounted:
	var st := {}
	var faces := PackedVector3Array()


static func _acc(ch: CityChunk) -> Acc:
	if not ch.has_meta("canal_acc"):
		ch.set_meta("canal_acc", Acc.new())
	return ch.get_meta("canal_acc")


static func _st(ch: CityChunk, mat: String) -> SurfaceTool:
	var acc := _acc(ch)
	if not acc.st.has(mat):
		var s := SurfaceTool.new()
		s.begin(Mesh.PRIMITIVE_TRIANGLES)
		acc.st[mat] = s
	return acc.st[mat]


static func site_steps(ch: CityChunk) -> Array[Callable]:
	var steps: Array[Callable] = []
	var lay := layout(ch.plan)
	if lay.is_empty():
		return steps
	var area := ch.owned_rect()
	var full := ch.level == CityChunk.Level.FULL
	steps.append(_ground.bind(ch, lay, area))
	steps.append(_banks.bind(ch, lay, area))
	steps.append(_water.bind(ch, lay, area))
	steps.append(_houses.bind(ch, lay, area))
	if full:
		steps.append(_gardens.bind(ch, lay, area))
		steps.append(_planting.bind(ch, lay, area))
		steps.append(_bridges.bind(ch, lay, area))
		steps.append(_docks.bind(ch, lay, area))
		steps.append(_crowd.bind(ch, lay, area))
	steps.append(_commit.bind(ch))
	return steps


## The far city's record of the block: the ground (lawn, the walks, the water) and the houses as
## the LOD chunk builds them. Run in capture mode: _add_slab records, HouseKit records lod boxes.
static func capture_steps(ch: CityChunk) -> Array[Callable]:
	var steps: Array[Callable] = []
	var lay := layout(ch.plan)
	if lay.is_empty():
		return steps
	var area := ch.owned_rect()
	steps.append(_ground.bind(ch, lay, area))
	steps.append(_water.bind(ch, lay, area))
	steps.append(_houses.bind(ch, lay, area))
	return steps


static func _parts(rects: Array, area: Rect2) -> Array[Rect2]:
	var out: Array[Rect2] = []
	for r: Rect2 in rects:
		var p := r.intersection(area)
		if p.size.x > 0.05 and p.size.y > 0.05:
			out.append(p)
	return out


## A flat quad over `r` at height `y` into material `mat` (and the collision faces).
static func _flat(ch: CityChunk, mat: String, r: Rect2, y: float, collide: bool = true, uv_scale: float = 1.0) -> void:
	var st := _st(ch, mat)
	var a := Vector3(r.position.x, y + ch._gy(r.position.x, r.position.y), r.position.y)
	var b := Vector3(r.end.x, y + ch._gy(r.end.x, r.position.y), r.position.y)
	var c := Vector3(r.end.x, y + ch._gy(r.end.x, r.end.y), r.end.y)
	var d := Vector3(r.position.x, y + ch._gy(r.position.x, r.end.y), r.end.y)
	_tri_up(st, a, c, b, uv_scale)
	_tri_up(st, a, d, c, uv_scale)
	if collide:
		_acc(ch).faces.append_array([a, b, c, a, c, d])


## A triangle wound to face +y, UV in world metres.
static func _tri_up(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, uv_scale: float = 1.0) -> void:
	var n := (b - a).cross(c - a)
	if n.y > 0.0:
		var t := b
		b = c
		c = t
	for v: Vector3 in [a, b, c]:
		st.set_color(Color.WHITE)
		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(v.x, v.z) * uv_scale)
		st.add_vertex(v)


## A quad a-b-c-d facing `facing` (world), UV (along, height) in metres.
static func _wall_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, facing: Vector3, col: Color = Color.WHITE) -> void:
	var front := (c - a).cross(b - a)
	var order := [a, b, c, a, c, d]
	if front.dot(facing) < 0.0:
		order = [a, c, b, a, d, c]
	var n := facing.normalized()
	var along := (b - a).normalized()
	for v: Vector3 in order:
		st.set_color(col)
		st.set_normal(n)
		st.set_uv(Vector2(v.x * along.x + v.z * along.z, v.y))
		st.add_vertex(v)


## The pavement ring, the walkways, the coping and the lots' lawns.
static func _ground(ch: CityChunk, lay: Dictionary, area: Rect2) -> void:
	var full := ch.level == CityChunk.Level.FULL and not ch.capturing
	if not full:
		# LOD and the far city: thin slabs in the ground's colours (merged far ground).
		for r: Rect2 in _parts(lay.ring, area) + _parts(lay.walks, area) + _parts(lay.copes, area):
			ch._add_slab(Vector3(r.get_center().x, WALK_Y - 0.1, r.get_center().y), Vector3(r.size.x, 0.2, r.size.y), ch.style.sidewalk, true)
		for lot: Dictionary in lay.lots:
			var p := (lot.cell as Rect2).intersection(area)
			if p.size.x > 0.05 and p.size.y > 0.05:
				ch._add_slab(Vector3(p.get_center().x, LAWN_Y - 0.1, p.get_center().y), Vector3(p.size.x, 0.2, p.size.y), Color(0.34, 0.44, 0.24), true)
		return
	for r: Rect2 in _parts(lay.ring, area) + _parts(lay.walks, area):
		_flat(ch, "walk", r, WALK_Y)
	for r: Rect2 in _parts(lay.copes, area):
		_flat(ch, "cope", r, COPE_Y)
	for lot: Dictionary in lay.lots:
		var p := (lot.cell as Rect2).intersection(area)
		if p.size.x > 0.05 and p.size.y > 0.05:
			_flat(ch, "lawn", p, LAWN_Y)
	# The lawn's edge where it meets the walk: a short face down to it (the lawn sits 3 cm proud).
	# The coping's water-side face down to the bank.
	var cope_st := _st(ch, "cope")
	for c: Dictionary in lay.canals:
		for sgn: float in [-1.0, 1.0]:
			for r: Rect2 in Parks.minus(_side_strip(c, COPE_IN - 0.001, COPE_IN + 0.001, sgn), _cut_rects(lay, c, COPE_IN), 0.0):
				var piece := r.intersection(area)
				if piece.size.x <= 0.0 and piece.size.y <= 0.0:
					continue
				var axis := int(c.axis)
				var o := float(c.c) + sgn * COPE_IN
				var a0: float = piece.position.y if axis == 0 else piece.position.x
				var a1: float = piece.end.y if axis == 0 else piece.end.x
				if a1 - a0 < 0.05:
					continue
				var p0 := Vector2(o, a0) if axis == 0 else Vector2(a0, o)
				var p1 := Vector2(o, a1) if axis == 0 else Vector2(a1, o)
				var facing := Vector3(-sgn, 0.0, 0.0) if axis == 0 else Vector3(0.0, 0.0, -sgn)
				var qa := Vector3(p0.x, COPE_Y, p0.y)
				var qb := Vector3(p1.x, COPE_Y, p1.y)
				var qc := Vector3(p1.x, BANK_TOP_Y - 0.05, p1.y)
				var qd := Vector3(p0.x, BANK_TOP_Y - 0.05, p0.y)
				_wall_quad(cope_st, qa, qb, qc, qd, facing)
				_acc(ch).faces.append_array([qa, qb, qc, qa, qc, qd])


## The cuts across a canal's sides: the corridors of the canals that cross it, out to `o`.
static func _cut_rects(lay: Dictionary, c: Dictionary, o: float) -> Array:
	var out: Array = []
	for other: Dictionary in lay.canals:
		if int(other.axis) != int(c.axis):
			out.append(_canal_rect(other, o))
	return out


## The banks and the bed: a height field over each canal's corridor (|o| < COPE_IN), its grid
## lines at the section's breakpoints so the profile is exact, the canals that cross it included.
## And the end walls where a canal meets the pavement ring.
static func _banks(ch: CityChunk, lay: Dictionary, area: Rect2) -> void:
	var full := ch.level == CityChunk.Level.FULL
	if not full:
		return
	var st := _st(ch, "bank")
	var offs := [0.0, BED_HALF, BED_HALF + 0.6, BED_HALF + 1.2, BED_HALF + 1.7, COPE_IN - 0.4, COPE_IN]
	var canals: Array = lay.canals
	for ci in canals.size():
		var c: Dictionary = canals[ci]
		var rect := _canal_rect(c, COPE_IN)
		# A crossing square belongs to the north-south canal.
		var pieces: Array[Rect2] = [rect]
		if int(c.axis) == 1:
			var holes: Array = []
			for o: Dictionary in canals:
				if int(o.axis) == 0:
					holes.append(_canal_rect(o, COPE_IN))
			pieces = Parks.minus(rect, holes, 0.01)
		for piece: Rect2 in pieces:
			var part := piece.intersection(area)
			if part.size.x < 0.05 or part.size.y < 0.05:
				continue
			var xl: Array = [part.position.x, part.end.x]
			var zl: Array = [part.position.y, part.end.y]
			for o: Dictionary in canals:
				for off: float in offs:
					for sgn: float in [-1.0, 1.0]:
						var v := float(o.c) + sgn * off
						if int(o.axis) == 0:
							if v > part.position.x and v < part.end.x:
								xl.append(v)
						elif v > part.position.y and v < part.end.y:
							zl.append(v)
			var step := 2.0
			var along_lo: float = part.position.y if int(c.axis) == 0 else part.position.x
			var along_hi: float = part.end.y if int(c.axis) == 0 else part.end.x
			var t := ceilf(along_lo / step) * step
			while t < along_hi:
				if int(c.axis) == 0:
					zl.append(t)
				else:
					xl.append(t)
				t += step
			xl = _uniq(xl)
			zl = _uniq(zl)
			var nx := xl.size()
			var nz := zl.size()
			var pts := PackedVector3Array()
			pts.resize(nx * nz)
			for j in nz:
				for i in nx:
					var p := Vector2(float(xl[i]), float(zl[j]))
					var o := canal_offset(lay, p)
					pts[j * nx + i] = Vector3(p.x, bank_y(minf(o, COPE_IN)) + ch._gy(p.x, p.y), p.y)
			for j in nz - 1:
				for i in nx - 1:
					var a := pts[j * nx + i]
					var b := pts[j * nx + i + 1]
					var cc := pts[(j + 1) * nx + i + 1]
					var d := pts[(j + 1) * nx + i]
					_bank_tri(st, a, b, cc)
					_bank_tri(st, a, cc, d)
					_acc(ch).faces.append_array([a, b, cc, a, cc, d])
		# The end walls: where the canal meets the pavement ring at either end, a vertical concrete
		# wall from the bed to the walk, following the bank's profile.
		for end: float in [float(c.a0), float(c.a1)]:
			var axis := int(c.axis)
			var p_mid := Vector2(float(c.c), end) if axis == 0 else Vector2(end, float(c.c))
			if not area.has_point(p_mid):
				continue
			var facing := Vector3(0.0, 0.0, 1.0 if end == float(c.a0) else -1.0) if axis == 0 else Vector3(1.0 if end == float(c.a0) else -1.0, 0.0, 0.0)
			var wst := _st(ch, "cope")
			var segs: Array = [-COPE_IN, -COPE_IN + 0.4, -BED_HALF - 1.7, -BED_HALF - 1.2, -BED_HALF - 0.6, -BED_HALF, BED_HALF, BED_HALF + 0.6, BED_HALF + 1.2, BED_HALF + 1.7, COPE_IN - 0.4, COPE_IN]
			for k in segs.size() - 1:
				var o0 := float(segs[k])
				var o1 := float(segs[k + 1])
				var q0 := Vector2(float(c.c) + o0, end) if axis == 0 else Vector2(end, float(c.c) + o0)
				var q1 := Vector2(float(c.c) + o1, end) if axis == 0 else Vector2(end, float(c.c) + o1)
				var qa := Vector3(q0.x, WALK_Y, q0.y)
				var qb := Vector3(q1.x, WALK_Y, q1.y)
				var qc := Vector3(q1.x, bank_y(absf(o1)) - 0.02, q1.y)
				var qd := Vector3(q0.x, bank_y(absf(o0)) - 0.02, q0.y)
				_wall_quad(wst, qa, qb, qc, qd, facing)
				_acc(ch).faces.append_array([qa, qb, qc, qa, qc, qd])
			# A white railing along the pavement edge over the end wall.
			var r0 := Vector2(float(c.c) - HALF, end) if axis == 0 else Vector2(end, float(c.c) - HALF)
			var r1 := Vector2(float(c.c) + HALF, end) if axis == 0 else Vector2(end, float(c.c) + HALF)
			var inset := Vector2(facing.x, facing.z) * 0.12
			CanalKit.railing(_st(ch, "paint"), r0 - inset, r1 - inset, WALK_Y, 1.05, Color(0.93, 0.93, 0.9))
			_acc(ch).faces.append_array(CanalKit.box_faces((r0 + r1) * 0.5 - inset, r1 - r0, 0.12, WALK_Y, WALK_Y + 1.05))


static func _uniq(a: Array) -> Array:
	a.sort()
	var out: Array = []
	for v in a:
		if out.is_empty() or float(v) - float(out.back()) > 0.02:
			out.append(v)
	return out


## A bank triangle facing up, its UV2 the height over the water (the shader's wet band) and its
## slope.
static func _bank_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	# Godot's front face is counter-clockwise as the viewer sees it: its normal is (c - a) x (b - a).
	var n := (c - a).cross(b - a)
	if n.y < 0.0:
		var t := b
		b = c
		c = t
		n = -n
	n = n.normalized()
	for v: Vector3 in [a, b, c]:
		st.set_normal(n)
		st.set_uv(Vector2(v.x, v.z))
		st.set_uv2(Vector2(v.y - WATER_Y, n.y))
		st.add_vertex(v)


## The water: one quad per piece of canal in the chunk, UV the across offset from its own centre
## line and the along coordinate, UV2.x which way it runs (the reflection works in that frame).
## A canal's water as rects: [pieces, cross], `cross[i]` the index of the canal crossing piece i
## or -1. A north-south canal's water owns the crossings, but there the way along the cross canal
## is open, so those squares are pieces of their own, tagged with the cross canal: the shader
## mirrors down whichever canal the reflected ray runs along. Pure (tests/fwd_review_a_checks.gd).
static func water_pieces(canals: Array, ci: int, half: float) -> Array:
	var c: Dictionary = canals[ci]
	var rect := _canal_rect(c, half)
	var holes: Array = []
	var hole_ids: Array[int] = []
	for oi in canals.size():
		if int(canals[oi].axis) != int(c.axis):
			holes.append(_canal_rect(canals[oi], half))
			hole_ids.append(oi)
	if holes.is_empty():
		return [[rect], [-1]]
	var pieces: Array = Parks.minus(rect, holes, 0.01)
	var cross: Array = []
	cross.resize(pieces.size())
	cross.fill(-1)
	if int(c.axis) == 0:
		for hi in holes.size():
			var sq: Rect2 = rect.intersection(holes[hi])
			if sq.size.x > 0.05 and sq.size.y > 0.05:
				pieces.append(sq)
				cross.append(hole_ids[hi])
	return [pieces, cross]


static func _water(ch: CityChunk, lay: Dictionary, area: Rect2) -> void:
	var far := ch.level != CityChunk.Level.FULL or ch.capturing
	var canals: Array = lay.canals
	for ci in canals.size():
		var c: Dictionary = canals[ci]
		var half := COPE_IN if far else (BED_HALF + 1.6)
		var split := water_pieces(canals, ci, half)
		var pieces: Array = split[0]
		var cross: Array = split[1]
		for pi in pieces.size():
			var piece: Rect2 = pieces[pi]
			var part := piece.intersection(area)
			if part.size.x < 0.05 or part.size.y < 0.05:
				continue
			if ch.capturing:
				ch._add_slab(Vector3(part.get_center().x, 0.05, part.get_center().y), Vector3(part.size.x, 0.1, part.size.y), Color(0.10, 0.16, 0.15), false)
				continue
			var st := _st(ch, "water")
			var y := (WATER_Y if not far else 0.0)
			var corners := [part.position, Vector2(part.end.x, part.position.y), part.end, Vector2(part.position.x, part.end.y)]
			var vs: Array = []
			for q: Vector2 in corners:
				vs.append(Vector3(q.x, y + ch._gy(q.x, q.y), q.y))
			for tri: Array in [[0, 1, 2], [0, 2, 3]]:
				for k: int in tri:
					var v: Vector3 = vs[k]
					var across: float = (v.x if int(c.axis) == 0 else v.z) - float(c.c)
					var along: float = v.z if int(c.axis) == 0 else v.x
					var uv2 := Vector2(float(c.axis), float(ci))
					if cross[pi] >= 0:
						# A crossing: UV.y is the offset across the cross canal, UV2.x 2 + its index.
						along = v.z - float(canals[cross[pi]].c)
						uv2.x = 2.0 + float(cross[pi])
					st.set_normal(Vector3.UP)
					st.set_uv(Vector2(across, along))
					st.set_uv2(uv2)
					st.add_vertex(v)
			if not far:
				_sink_volume(ch, part)


## The houses whose lot centre is in this chunk: HouseKit's builder (FULL into the chunk's house
## meshes, LOD and capture as LOD boxes).
static func _houses(ch: CityChunk, lay: Dictionary, area: Rect2) -> void:
	if not HouseKit.enabled:
		return
	for lot: Dictionary in lay.lots:
		if not area.has_point(lot.center):
			continue
		HouseKit.build(ch, house_for(ch.plan, lot))


## Front gardens: a low fence along the walk with a gate, a path to the door, a porch light, beds
## of flowers; fences between the lots; a tree in some yards.
static func _gardens(ch: CityChunk, lay: Dictionary, area: Rect2) -> void:
	var ps := ch.plan.seed
	var paint := _st(ch, "paint")
	var timber := _st(ch, "timber")
	var stucco := _st(ch, "stucco")
	var paving := _st(ch, "path")
	var flowers := [absi(hash([ps, ch.ix, ch.iz, "canal_flower_a"])) % PropFactory.FLOWERS.size(),
		absi(hash([ps, ch.ix, ch.iz, "canal_flower_b"])) % PropFactory.FLOWERS.size()]
	var trees := 0
	for lot: Dictionary in lay.lots:
		if not area.has_point(lot.center):
			continue
		var h := house_for(ch.plan, lot)
		var cell: Rect2 = lot.cell
		var s: int = lot.seed
		var fx: float = lot.front_x
		var dir: float = lot.dir
		var door := YardFill._fp(h.f, float(h.door_u), float(h.door_v))
		var gate_z := clampf(door.y, cell.position.y + 1.2, cell.end.y - 1.2)
		var fence_x := fx - dir * 0.15
		var kind := _h01([ps, s, "fence"])
		var col: Color = h.colors.wall
		var z0 := cell.position.y + 0.05
		var z1 := cell.end.y - 0.05
		var spans := [[z0, gate_z - 0.6], [gate_z + 0.6, z1]]
		for sp: Array in spans:
			var a := Vector2(fence_x, float(sp[0]))
			var b := Vector2(fence_x, float(sp[1]))
			if b.y - a.y < 0.3:
				continue
			if kind < 0.45:
				CanalKit.picket_fence(paint, a, b, LAWN_Y, 0.95, Color(0.95, 0.95, 0.92))
			elif kind < 0.75:
				CanalKit.low_wall(stucco, a, b, LAWN_Y, 0.75, 0.22, col)
			else:
				CanalKit.glass_rail(paint, a, b, LAWN_Y, 0.95, Color(0.20, 0.21, 0.22))
			_acc(ch).faces.append_array(CanalKit.box_faces((a + b) * 0.5, b - a, 0.12, LAWN_Y, LAWN_Y + 0.9))
		# Gate posts.
		CanalKit.post(paint, Vector2(fence_x, gate_z - 0.62), LAWN_Y, 1.15, 0.11, Color(0.95, 0.95, 0.92))
		CanalKit.post(paint, Vector2(fence_x, gate_z + 0.62), LAWN_Y, 1.15, 0.11, Color(0.95, 0.95, 0.92))
		# The path from the gate to the door.
		var p0 := Vector2(fx, gate_z)
		var p1 := Vector2(door.x - dir * 0.2, gate_z)
		var path_r := Rect2(minf(p0.x, p1.x), gate_z - 0.55, absf(p1.x - p0.x), 1.1)
		if absf(door.y - gate_z) > 0.3:
			var dz := Rect2(minf(p1.x, p1.x) - 0.55, minf(gate_z, door.y) - 0.55, 1.1, absf(door.y - gate_z) + 1.1)
			_flat(ch, "path", dz, LAWN_Y + 0.015, false, 1.0)
		_flat(ch, "path", path_r, LAWN_Y + 0.015, false, 1.0)
		# Side fences: on the lot's +z line (and its -z line at the head of a row), from the house
		# front back; and along the back line once (edge rows back onto the pavement; of two rows
		# back to back, the west one builds it).
		var house_front_x: float = fx - dir * (GARDEN + float((h.wings[0].r as Rect2).position.y))
		var back_x := cell.position.x if dir > 0.0 else cell.end.x
		var fence_col := Color(0.62, 0.46, 0.32).lerp(Color(0.45, 0.33, 0.24), _h01([ps, s, "stain"]))
		var lines: Array = [cell.end.y - 0.04]
		if lot.first:
			lines.append(cell.position.y + 0.04)
		for lz: float in lines:
			var fa := Vector2(house_front_x, lz)
			var fb := Vector2(back_x + dir * 0.04, lz)
			CanalKit.board_fence(timber, fa, fb, LAWN_Y, 1.7, fence_col)
			_acc(ch).faces.append_array(CanalKit.box_faces((fa + fb) * 0.5, fb - fa, 0.08, LAWN_Y, LAWN_Y + 1.7))
		if lot.back_fence:
			var fa := Vector2(back_x + dir * 0.04, cell.position.y + 0.04)
			var fb := Vector2(back_x + dir * 0.04, cell.end.y - 0.04)
			CanalKit.board_fence(timber, fa, fb, LAWN_Y, 1.8, fence_col)
			_acc(ch).faces.append_array(CanalKit.box_faces((fa + fb) * 0.5, fb - fa, 0.08, LAWN_Y, LAWN_Y + 1.8))
		# Beds of flowers along the fence, either side of the gate.
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([ps, s, "garden"])
		var bed_x := fx - dir * 0.75
		for k in rng.randi_range(5, 9):
			var z := rng.randf_range(z0 + 0.4, z1 - 0.4)
			if absf(z - gate_z) < 0.9:
				continue
			var f: int = flowers[0] if rng.randf() < 0.7 else flowers[1]
			var sc := rng.randf_range(0.8, 1.4)
			ch._batch.add("flower_%d" % f, PropFactory.model_flower(f), Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sc, sc, sc)), Vector3(bed_x + rng.randf_range(-0.4, 0.4), LAWN_Y, z)), Color(1, 1, 1))
		for k in 2:
			if rng.randf() < 0.55:
				var z := rng.randf_range(z0 + 0.8, z1 - 0.8)
				if absf(z - gate_z) > 1.2:
					var v := rng.randi() % 4
					var sc := rng.randf_range(0.6, 0.95)
					ch._batch.add("shrub_%d" % v, PropFactory.model_shrub(v), Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sc, sc, sc)), Vector3(bed_x - dir * 0.3, LAWN_Y, z)), Color(0.95, 1.0, 0.92))
		# A porch light by the door: a lantern on the wall, its glow and its pool.
		var lamp_at := Vector3(door.x + dir * 0.05, 0.0, door.y + 0.85)
		CanalKit.add_porch_light(ch, lamp_at, dir, _h01([ps, s, "porch_on"]) < 0.85)
		# A tree in the back yard now and then.
		if trees < 14 and _h01([ps, s, "yard_tree"]) < YARD_TREE_ODDS:
			var back_x2 := cell.position.x + 2.0 if dir > 0.0 else cell.end.x - 2.0
			var tz := cell.get_center().y + rng.randf_range(-cell.size.y * 0.25, cell.size.y * 0.25)
			var trng := RandomNumberGenerator.new()
			trng.seed = hash([ps, s, "tree"])
			if _h01([ps, s, "palm"]) < 0.35:
				ch._add_palm(Vector3(back_x2, LAWN_Y, tz), trng, false)
			else:
				ch._add_tree(Vector3(back_x2, LAWN_Y, tz), trng)
			trees += 1
	for f: int in flowers:
		ch._batch.set_draw_distance("flower_%d" % f, PLANT_DRAW)
		ch._batch.set_no_shadow("flower_%d" % f)


## Reeds along the waterline and shrubs on the banks, per canal side in the chunk.
static func _planting(ch: CityChunk, lay: Dictionary, area: Rect2) -> void:
	var ps := ch.plan.seed
	var clump := absi(hash([ps, "canal_reed"])) % PropFactory.GRASS_CLUMPS.size()
	var reed := PropFactory.model_grass_clump(clump)
	var reed_key := "canal_reed"
	for ci in (lay.canals as Array).size():
		var c: Dictionary = lay.canals[ci]
		for sgn: float in [-1.0, 1.0]:
			var strip := _side_strip(c, BED_HALF + 0.8, COPE_IN - 0.3, sgn)
			for piece: Rect2 in Parks.minus(strip, _cut_rects(lay, c, HALF + 1.0), 0.5):
				var part := piece.intersection(area)
				if part.size.x < 0.5 or part.size.y < 0.5:
					continue
				var axis := int(c.axis)
				var length: float = part.size.y if axis == 0 else part.size.x
				var rng := RandomNumberGenerator.new()
				rng.seed = hash([ps, "canal_bank", ci, int(sgn), int(part.position.x), int(part.position.y)])
				# Reeds in clumps along the waterline, the clumps patchy along the bank.
				var n := int(length * REEDS_PER_M)
				for k in n:
					var along := rng.randf() * length
					var patch := sin(along * 0.21 + float(ci) * 1.7) * 0.5 + 0.5
					if rng.randf() > patch * 1.3:
						continue
					var o := rng.randf_range(BED_HALF + 1.0, BED_HALF + 1.9)
					var p := _side_point(c, part, along, o * sgn)
					var sc := rng.randf_range(0.9, 1.7)
					var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sc, sc * rng.randf_range(1.6, 2.4), sc)), Vector3(p.x, bank_y(o) - 0.05, p.y))
					ch._batch.add(reed_key, reed, xf, Color(rng.randf_range(0.75, 0.95), rng.randf_range(0.95, 1.1), rng.randf_range(0.65, 0.8)))
				# Shrubs and low planting up the bank.
				var m := int(length * BANK_SHRUBS_PER_M)
				for k in m:
					var along := rng.randf() * length
					var o := rng.randf_range(COPE_IN - 1.3, COPE_IN - 0.5)
					var p := _side_point(c, part, along, o * sgn)
					var v := rng.randi() % 4
					var sc := rng.randf_range(0.55, 0.85)
					ch._batch.add("shrub_%d" % v, PropFactory.model_shrub(v), Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sc, sc, sc)), Vector3(p.x, bank_y(o) - 0.03, p.y)), Color(0.9, 1.0, 0.9))
	ch._batch.set_draw_distance(reed_key, PLANT_DRAW)
	ch._batch.set_no_shadow(reed_key)


## A point `along` metres into `part` along canal `c`, `o` across from its centre line.
static func _side_point(c: Dictionary, part: Rect2, along: float, o: float) -> Vector2:
	if int(c.axis) == 0:
		return Vector2(float(c.c) + o, part.position.y + along)
	return Vector2(part.position.x + along, float(c.c) + o)


## The footbridges whose middle is in this chunk.
static func _bridges(ch: CityChunk, lay: Dictionary, area: Rect2) -> void:
	for b: Dictionary in lay.bridges:
		var at: Vector2 = b.at
		if not area.has_point(at):
			continue
		CanalKit.add_bridge(ch, at, int(b.axis), int(b.seed))


## The docks and the boats, by lot; and a boat tied to the bank here and there.
static func _docks(ch: CityChunk, lay: Dictionary, area: Rect2) -> void:
	var ps := ch.plan.seed
	for lot: Dictionary in lay.lots:
		var p: Vector2 = lot.dock_at
		if not area.has_point(p):
			continue
		var dir: float = lot.dir
		if lot.dock:
			CanalKit.add_dock(ch, p, dir, int(lot.seed))
		elif _h01([ps, lot.seed, "bank_boat"]) < BANK_BOAT_ODDS:
			var boat := Vector3(p.x + dir * 0.6, WATER_Y, p.y + 1.0)
			CanalKit.add_boat(ch, boat, PI * 0.5 if _h01([ps, lot.seed, "flip"]) < 0.5 else -PI * 0.5, int(lot.seed) ^ 77)


## Walkers on the walkways, and on the pavement ring.
static func _crowd(ch: CityChunk, lay: Dictionary, area: Rect2) -> void:
	for r: Rect2 in _parts(lay.walks, area):
		var length := maxf(r.size.x, r.size.y)
		if length < 20.0:
			continue
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([ch.plan.seed, "canal_walkers", int(r.position.x), int(r.position.y)])
		var n := int(length * WALKERS_PER_M + rng.randf())
		for step: Callable in ch._crowd_steps(r, minf(r.size.x, r.size.y) * 0.5, n, rng):
			step.call()


## Everything accumulated into one mesh per material, and one collision body.
static func _commit(ch: CityChunk) -> void:
	if not ch.has_meta("canal_acc"):
		return
	var acc: Acc = ch.get_meta("canal_acc")
	ch.remove_meta("canal_acc")
	for mat: String in acc.st:
		var s: SurfaceTool = acc.st[mat]
		if mat != "water" and mat != "glow":
			s.generate_tangents()
		var mesh := s.commit()
		if mesh.get_surface_count() == 0:
			continue
		var mi := MeshInstance3D.new()
		mi.name = "Canal_" + mat
		mi.mesh = mesh
		mi.material_override = material(mat)
		if mat in ["water", "walk", "lawn", "path", "glow", "cope"]:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if mat in ["paint", "timber", "boat", "stucco", "iron"]:
			mi.visibility_range_end = FENCE_DRAW if mat != "boat" else BOAT_DRAW
			mi.visibility_range_end_margin = 20.0
			mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		ch.add_child(mi)
	if not acc.faces.is_empty():
		var body := StaticBody3D.new()
		body.name = "CanalGround"
		body.collision_layer = 1
		body.collision_mask = 0
		var shape := ConcavePolygonShape3D.new()
		shape.backface_collision = true
		shape.set_faces(acc.faces)
		var cs := CollisionShape3D.new()
		cs.shape = shape
		body.add_child(cs)
		ch.add_child(body)


static var _mats := {}


static func material(name: String) -> Material:
	if _mats.has(name):
		return _mats[name]
	var m: Material
	match name:
		"walk":
			m = PropFactory.road("sidewalk", 3.0, Color(1.45, 1.43, 1.38), 7713, 1.5, 0.35)
		"path":
			m = PropFactory.pbr("pavers", 1.6, Color(1.05, 0.92, 0.82))
		"cope":
			m = PropFactory.pbr("concrete", 2.0, Color(0.95, 0.93, 0.88))
		"lawn":
			m = PropFactory.lawn(Color(0.86, 0.98, 0.72), 4411, 0.25, 0.0)
		"bank":
			var sm := ShaderMaterial.new()
			sm.shader = load("res://shaders/canal_bank.gdshader")
			sm.set_shader_parameter("grass_tex", PropFactory.texture("grass", "Color"))
			sm.set_shader_parameter("mud_tex", PropFactory.texture("hill_dirt", "Color"))
			sm.set_shader_parameter("water_y", WATER_Y)
			m = sm
		"water":
			var wm := ShaderMaterial.new()
			wm.shader = load("res://shaders/canal_water.gdshader")
			wm.set_shader_parameter("facade_offset", HALF + WALK_W + GARDEN + 2.2)
			wm.set_shader_parameter("lot_width", LOT_W)
			m = wm
		"paint", "boat", "iron":
			var pm := StandardMaterial3D.new()
			pm.vertex_color_use_as_albedo = true
			pm.vertex_color_is_srgb = true
			pm.roughness = 0.55 if name == "paint" else (0.42 if name == "boat" else 0.5)
			pm.metallic = 0.6 if name == "iron" else 0.0
			m = pm
		"timber":
			var tm := (PropFactory.pbr("planks", 1.8, Color.WHITE) as StandardMaterial3D).duplicate() as StandardMaterial3D
			tm.vertex_color_use_as_albedo = true
			tm.vertex_color_is_srgb = true
			m = tm
		"stucco":
			var stm := (PropFactory.pbr("plaster_white", 2.5, Color.WHITE) as StandardMaterial3D).duplicate() as StandardMaterial3D
			stm.vertex_color_use_as_albedo = true
			stm.vertex_color_is_srgb = true
			m = stm
		"glow":
			var gm := ShaderMaterial.new()
			gm.shader = load("res://shaders/canal_lamp.gdshader")
			m = gm
		_:
			m = PropFactory.material(Color.MAGENTA)
	_mats[name] = m
	return m


# =================================================================================================
# The water as a volume
# =================================================================================================

## How many canal volumes each body is in (instance id -> count): a body crossing from one
## chunk's volume into the next is in both for a moment, and only the last one out may give it the
## ground box back.
static var _inside: Dictionary = {}


## A trigger over a piece of canal (one Area3D a chunk, a box per piece): whatever falls in throws
## up a splash, and the player and loose bodies pass through the city's ground box to the canal bed
## while they are in it (MacArthur Park's lake does the same).
static func _sink_volume(ch: CityChunk, part: Rect2) -> void:
	var zone: Area3D
	if ch.has_meta("canal_zone"):
		zone = ch.get_meta("canal_zone")
	else:
		zone = Area3D.new()
		zone.name = "CanalWater"
		zone.collision_layer = 0
		zone.collision_mask = 2 | 4
		zone.monitorable = false
		var mine := {}
		zone.body_entered.connect(func(body: Node3D) -> void:
			LandmarkMacArthurPark._splash(zone, body)
			_sink(zone, body, true, mine))
		zone.body_exited.connect(func(body: Node3D) -> void: _sink(zone, body, false, mine))
		# A chunk that unloads with something still in the water must not leave it passing through
		# the ground everywhere else.
		zone.tree_exiting.connect(func() -> void:
			for body: Node3D in mine.values().duplicate():
				if is_instance_valid(body):
					_sink(zone, body, false, mine))
		ch.add_child(zone)
		ch.set_meta("canal_zone", zone)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	# Out to the bank tops, so the sloped banks below the box's top are reachable too.
	var r := part.grow(COPE_IN - BED_HALF - 1.6 - 0.1)
	box.size = Vector3(r.size.x, (WATER_Y + 1.0) - WALL_BOTTOM, r.size.y)
	cs.shape = box
	cs.position = Vector3(r.get_center().x, (WATER_Y + 1.0 + WALL_BOTTOM) * 0.5 + ch._gy(r.get_center().x, r.get_center().y), r.get_center().y)
	zone.add_child(cs)


static func _sink(zone: Area3D, body: Node3D, on: bool, mine: Dictionary) -> void:
	if not (body is PhysicsBody3D) or not zone.is_inside_tree():
		return
	var city := zone.get_tree().get_first_node_in_group("city")
	var ground := city.get_node_or_null("GroundBody") as PhysicsBody3D if city else null
	if ground == null:
		return
	var id := body.get_instance_id()
	if on:
		if mine.has(id):
			return
		mine[id] = body
		_inside[id] = int(_inside.get(id, 0)) + 1
		if int(_inside[id]) == 1:
			PhysicsServer3D.body_add_collision_exception((body as PhysicsBody3D).get_rid(), ground.get_rid())
	else:
		if not mine.has(id):
			return
		mine.erase(id)
		_inside[id] = int(_inside.get(id, 1)) - 1
		if int(_inside[id]) <= 0:
			_inside.erase(id)
			PhysicsServer3D.body_remove_collision_exception((body as PhysicsBody3D).get_rid(), ground.get_rid())
