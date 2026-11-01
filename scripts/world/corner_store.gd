class_name CornerStore
extends RefCounted
## The corner store (2026-10-05, fleet task "walk-in-store"): the one kind of building the player
## can walk into. A one-storey stucco convenience store on a corner lot in MIDTOWN and the
## SUBURBS, built to the back of the pavement on both streets, a lit sign band across the front
## and round the corner, steel bars over the windows, and inside real geometry: wall shelving and
## gondolas of products (code-built boxes, cans, bottles and bags in MultiMeshes), a bank of glass
## door coolers glowing down one side, the counter with the till, the scratch-ticket case and the
## lotto terminal, the cigarette rack behind the cashier, a drop ceiling of troffers, a vinyl tile
## floor, and a glass door that swings open as the player comes up to it.
##
## WHERE is worked out, never placed: a hash of seed + block decides whether a MIDTOWN or SUBURBS
## block of plain buildings has a store (ODDS) and at which of its four corners (tried in a hashed
## order); the corner's lot must be a whole lot of the grid (not a courtyard), on level ground, off
## the freeways, with both its streets open, and not any other feature's (the fire and police
## stations, worship, Broadway, Chinatown, car dealers, an oil well, the civic buildings: all asked
## first, since CityChunk._build_lot asks claims() after all of them and after the pad roll, so
## no roll anywhere moves). Pure: the LOD chunks, the far city, the tests and the probe ask the
## same question (plan_for()).
##
## FULL chunks: CornerStoreKit builds it (the shell, the interior as a deferred build step) under
## a CornerStoreSite node, which hides the interior and lets the glass draw the TRACED room
## (shaders/corner_store_glass.gdshader: the same shelves, gondolas, coolers and counter as the
## geometry, laid out by the same numbers) while the player and the camera are outside, and shows
## the real interior behind clear glass when either comes within reach of the door. LOD chunks and
## the far city: the box in its stucco and the sign band as a lit panel.
##
## Names are this game's own (NAMES), never a real chain's.

const ODDS := {
	CityPlan.District.MIDTOWN: 0.20,
	CityPlan.District.SUBURBS: 0.13,
}
## The store's size (m): the frontage and the depth it wants, the least it takes.
const WIDTH := Vector2(9.0, 14.5)
const DEPTH := Vector2(8.5, 13.0)
## The most the ground may fall across the footprint (m): the floor is one level.
const MAX_RELIEF := 0.8
## Height of the floor over the highest pavement under it (m).
const FLOOR_LIFT := 0.04
const WALL := 0.25
## Ceiling (the drop ceiling), the roof's top and the parapet's top over the floor (m).
const CEILING := 3.0
const ROOF := 3.55
const PARAPET := 4.35
## The storefront: bulkhead top, glass top (door head), transom top.
const BULKHEAD := 0.55
const DOOR_W := 1.0
const DOOR_H := 2.2
const GLASS_TOP := 2.75
## The sign band on the front and the corner side (bottom, top).
const SIGN_Y := Vector2(3.05, 4.05)
## Interior layout (see layout()).
const BACK_SHELF := 0.45
const COOLER_DEEP := 0.85
const COOLER_DOOR := 0.78
const COUNTER_DEEP := 0.62
const COUNTER_OFF := 1.25
const GONDOLA_W := 0.9
const GONDOLA_PITCH := 2.3
const GONDOLA_FRONT := 2.6

const NAMES := ["SUNNY CORNER MARKET", "LA ESQUINA MARKET", "LUCKY STAR MINI MART", "CORNER KING MARKET",
	"HAPPY DAY FOOD MART", "MOONLITE MARKET", "BLUE SKY LIQUOR & DELI", "PALMITA MARKET",
	"NEIGHBOR'S FOOD MART", "QUICK STOP MARKET", "EL SOLECITO MARKET", "GOLDEN POPPY MARKET",
	"NITE OWL MINI MART", "ARROYO MARKET", "JACARANDA FOOD MART", "SIERRA LIQUOR & MARKET",
	"STARLITE MARKET", "VISTA MINI MART", "TOWER LIQUOR & MARKET", "SAN RAFA MARKET"]
## Stucco colours (sRGB): cream, sand, mint, faded teal, salmon, pale yellow, white, sky.
const STUCCO := [Color(0.90, 0.86, 0.76), Color(0.84, 0.76, 0.62), Color(0.70, 0.82, 0.72), Color(0.48, 0.70, 0.70),
	Color(0.88, 0.66, 0.56), Color(0.93, 0.86, 0.58), Color(0.93, 0.92, 0.89), Color(0.66, 0.78, 0.86)]
## Sign band faces and their letters (sRGB): [face, letters].
const SIGNS := [[Color(0.86, 0.12, 0.10), Color(1.0, 0.95, 0.80)], [Color(0.98, 0.96, 0.90), Color(0.75, 0.08, 0.07)],
	[Color(0.10, 0.30, 0.62), Color(1.0, 0.92, 0.45)], [Color(0.98, 0.80, 0.18), Color(0.12, 0.12, 0.14)],
	[Color(0.08, 0.45, 0.26), Color(1.0, 0.98, 0.92)]]

## Off (WALK_IN_STORE=0 in the environment): no stores, the corner lots keep what they had.
static var enabled: bool = OS.get_environment("WALK_IN_STORE") != "0"
static var _cache: Dictionary = {}
## Why corners failed (the probe prints it).
static var reasons: Dictionary = {}


static func _why(r: String) -> void:
	reasons[r] = int(reasons.get(r, 0)) + 1


static func _h01(parts: Array) -> float:
	return float(absi(hash(parts)) % 100003) / 100003.0


## The store on block (bx, bz): {} or {"block", "lot" (its seed), "rect" (the footprint, true
## world), "cell", "corner" (Vector2 of +-1: which corner of the block), "front" (Vector2: the
## outward direction to the front street), "side" (the outward direction to the side street),
## "W", "D", "origin" (true world XZ of the front face's middle), "name", "look", "seed"}. Cached.
static func plan_for(plan: CityPlan, bx: int, bz: int) -> Dictionary:
	if not enabled or plan == null or plan.macro == null:
		return {}
	var key := Vector3i(plan.seed, bx, bz)
	if _cache.has(key):
		return _cache[key]
	var out := _find(plan, bx, bz)
	_cache[key] = out
	return out


static func _find(plan: CityPlan, bx: int, bz: int) -> Dictionary:
	var b := plan.block(bx, bz)
	var district := int(b.district)
	if not ODDS.has(district):
		return {}
	if _h01([plan.seed, bx, bz, "cstore"]) > float(ODDS[district]):
		return {}
	if int(b.kind) != CityPlan.BlockKind.BUILDINGS or b.has("site") or b.has("grounds") or b.has("hospital"):
		_why("block kind")
		return {}
	var rect: Rect2 = b.rect
	if plan.zone_at(rect.get_center()) != MacroMap.Zone.CITY or plan.river_block(bx, bz):
		return {}
	if Landmarks.claims(rect):
		return {}
	var lots := plan.lots(bx, bz)
	if lots.is_empty():
		_why("no lots")
		return {}
	var inner := rect.grow(-plan.sidewalk_width)
	var first := absi(hash([plan.seed, bx, bz, "cstore_corner"])) % 4
	for j in 4:
		var k := (first + j) % 4
		var corner := Vector2(-1.0 if k % 2 == 0 else 1.0, -1.0 if k < 2 else 1.0)
		var s := _at_corner(plan, bx, bz, inner, lots, corner)
		if not s.is_empty():
			return s
	return {}


static func _at_corner(plan: CityPlan, bx: int, bz: int, inner: Rect2, lots: Array[Dictionary], corner: Vector2) -> Dictionary:
	var cpt := Vector2(inner.position.x if corner.x < 0.0 else inner.end.x, inner.position.y if corner.y < 0.0 else inner.end.y)
	var lot := {}
	for l: Dictionary in lots:
		var cell: Rect2 = l.cell
		var cc := Vector2(cell.position.x if corner.x < 0.0 else cell.end.x, cell.position.y if corner.y < 0.0 else cell.end.y)
		if cc.distance_to(cpt) < 0.5:
			lot = l
			break
	if lot.is_empty() or bool(lot.yard):
		_why("no corner lot")
		return {}
	# Both streets open at the corner: x side is road AXIS_X bx (or bx + 1), z side AXIS_Z bz (+1).
	var rx := [CityPlan.AXIS_X, bx if corner.x < 0.0 else bx + 1]
	var rz := [CityPlan.AXIS_Z, bz if corner.y < 0.0 else bz + 1]
	if not plan.road_open(int(rx[0]), int(rx[1]), cpt.y) or not plan.road_open(int(rz[0]), int(rz[1]), cpt.x):
		_why("road closed")
		return {}
	# Every other feature that claims a lot is asked first (they win in _build_lot too).
	if FireStation.claims(plan, bx, bz, lot) or PoliceStation.claims(plan, bx, bz, lot) \
			or Worship.claims(plan, bx, bz, lot) or Broadway.claims(plan, bx, bz, lot) \
			or Chinatown.claims(plan, bx, bz, lot) or CarDealers.claims(plan, bx, bz, lot) \
			or CivicBuildings.claims(plan, bx, bz, lot):
		_why("claimed")
		return {}
	if not OilField.lot_well(plan, lot, int(plan.block(bx, bz).district)).is_empty():
		return {}
	# The front is the wider street (a boulevard over a side street); a hash breaks a tie.
	var wx := plan.road_width(int(rx[0]), int(rx[1]))
	var wz := plan.road_width(int(rz[0]), int(rz[1]))
	var front_x := wx > wz + 0.5 or (absf(wx - wz) <= 0.5 and _h01([plan.seed, bx, bz, "cstore_front"]) < 0.5)
	var to_x := Vector2(corner.x, 0.0)
	var to_z := Vector2(0.0, corner.y)
	var front := to_x if front_x else to_z
	var side := to_z if front_x else to_x
	var cell: Rect2 = lot.cell
	# Frontage runs along the front street (perpendicular to `front`).
	var along := cell.size.y if front_x else cell.size.x
	var deep := cell.size.x if front_x else cell.size.y
	if along < WIDTH.x or deep < DEPTH.x:
		_why("small %.0fx%.0f" % [along, deep])
		return {}
	# The size it wants is a hash too: not every store is the biggest the corner takes.
	var sd := absi(hash([plan.seed, bx, bz, "cstore_seed"]))
	var W := minf(along, lerpf(10.5, WIDTH.y, float(sd % 101) / 100.0))
	var D := minf(deep, lerpf(10.0, DEPTH.y, float((sd >> 8) % 101) / 100.0))
	# Footprint: from the corner, W along the front street, D in from it.
	var fp_along := -side * W
	var fp_in := -front * D
	var a := cpt
	var c := cpt + fp_along + fp_in
	var fp := Rect2(Vector2(minf(a.x, c.x), minf(a.y, c.y)), Vector2(absf(c.x - a.x), absf(c.y - a.y)))
	if plan.macro.freeway and plan.macro.freeway.blocks_rect(fp.grow(3.0), 3.0):
		_why("freeway")
		return {}
	var lo := INF
	var hi := -INF
	for q: Vector2 in [fp.position, fp.end, Vector2(fp.position.x, fp.end.y), Vector2(fp.end.x, fp.position.y), fp.get_center()]:
		if plan.zone_at(q) != MacroMap.Zone.CITY:
			return {}
		var r := plan.macro.relief_at(q)
		lo = minf(lo, r)
		hi = maxf(hi, r)
	if hi - lo > MAX_RELIEF:
		_why("relief")
		return {}
	var origin := cpt - side * (W * 0.5)
	var name: String = NAMES[absi(hash([plan.seed, bx, bz, "cstore_name"])) % NAMES.size()]
	var look := absi(hash([plan.seed, bx, bz, "cstore_look"]))
	return {"block": Vector2i(bx, bz), "lot": int(lot.seed), "rect": fp, "cell": cell, "corner": corner,
		"front": front, "side": side, "W": W, "D": D, "origin": origin, "name": name, "seed": sd,
		"stucco": STUCCO[look % STUCCO.size()], "sign": SIGNS[(look / 7) % SIGNS.size()],
		"relief": hi - lo, "district": int(plan.block(bx, bz).district)}


## True when `lot` of block (bx, bz) is a corner store's (CityChunk._build_lot asks, after every
## roll and every other lot claim).
static func claims(plan: CityPlan, bx: int, bz: int, lot: Dictionary) -> bool:
	var s := plan_for(plan, bx, bz)
	return not s.is_empty() and int(s.lot) == int(lot.seed)


## Every store on the blocks within `radius` of `p` (true world XZ), nearest first.
static func near(plan: CityPlan, p: Vector2, radius: float) -> Array:
	var out: Array = []
	var b0 := plan.block_index_at(p - Vector2(radius, radius))
	var b1 := plan.block_index_at(p + Vector2(radius, radius))
	for bx in range(b0.x, b1.x + 1):
		for bz in range(b0.y, b1.y + 1):
			var s := plan_for(plan, bx, bz)
			if not s.is_empty() and (s.origin as Vector2).distance_to(p) <= radius:
				out.append(s)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return (a.origin as Vector2).distance_squared_to(p) < (b.origin as Vector2).distance_squared_to(p))
	return out


## +1 when the side street is on the store's local +x (see local_basis()).
static func corner_sign(s: Dictionary) -> float:
	var basis := local_basis(s)
	var side: Vector2 = s.side
	return signf(Vector2(basis.x.x, basis.x.z).dot(side))


## The store's frame: +Z out to the front street, +X along it, y up.
static func local_basis(s: Dictionary) -> Basis:
	var f: Vector2 = s.front
	var outward := Vector3(f.x, 0.0, f.y)
	return Basis(Vector3.UP.cross(outward), Vector3.UP, outward)


## The interior layout in the store's frame (x across, z from the front face 0 back to -D, y from
## the floor): every number the geometry, the collision and the traced glass share.
static func layout(s: Dictionary) -> Dictionary:
	var W: float = s.W
	var D: float = s.D
	var cs := corner_sign(s)
	var ix0 := -W * 0.5 + WALL
	var ix1 := W * 0.5 - WALL
	var iz0 := -D + WALL
	var iz1 := -WALL
	# The counter runs front to back along the corner-side wall, the cashier between it and the
	# wall (the cigarette rack on it); the door is just past the counter's customer side.
	var counter_x := cs * (W * 0.5 - WALL - COUNTER_OFF - COUNTER_DEEP * 0.5)
	var counter_z := Vector2(-1.15, -minf(4.3, D - 3.0))
	var door_x := cs * (W * 0.5 - WALL - COUNTER_OFF - COUNTER_DEEP - 0.25 - DOOR_W * 0.5)
	# Coolers down the other wall, from past the front window to the back shelving.
	var cooler_z := Vector2(-2.0, iz0 + BACK_SHELF + 0.25)
	var n_doors := maxi(int(floor((cooler_z.x - cooler_z.y) / COOLER_DOOR)), 0)
	cooler_z.y = cooler_z.x - float(n_doors) * COOLER_DOOR
	var cooler_face := -cs * (W * 0.5 - WALL - COOLER_DEEP)
	# Gondolas between the cooler aisle and the counter's customer side, running back from the
	# window (as the traced retail room lays them).
	var ga := cooler_face + (-cs) * -1.15
	var gb := counter_x - cs * (COUNTER_DEEP * 0.5 + 1.2)
	var span := absf(gb - ga)
	var n_g := clampi(int(floor((span - GONDOLA_W) / GONDOLA_PITCH)) + 1, 0, 4) if span >= GONDOLA_W else 0
	var gondolas: Array[float] = []
	var mid := (ga + gb) * 0.5
	for i in n_g:
		gondolas.append(mid + (float(i) - float(n_g - 1) * 0.5) * GONDOLA_PITCH)
	var g_z := Vector2(-GONDOLA_FRONT, iz0 + BACK_SHELF + 1.25)
	return {"W": W, "D": D, "cs": cs, "relief": float(s.get("relief", 0.0)), "ix0": ix0, "ix1": ix1, "iz0": iz0, "iz1": iz1,
		"counter_x": counter_x, "counter_z": counter_z, "door_x": door_x,
		"cooler_z": cooler_z, "n_doors": n_doors, "cooler_face": cooler_face,
		"gondolas": gondolas, "g_z": g_z, "g_h": 1.55}


## The store's node transform in chunk `ch`'s space: origin at the front face's middle, on the floor.
static func local_transform(ch: CityChunk, s: Dictionary) -> Transform3D:
	return Transform3D(local_basis(s), Vector3((s.origin as Vector2).x, floor_y(ch, s), (s.origin as Vector2).y))


## The floor's height in chunk space: over the highest pavement under the footprint.
static func floor_y(ch: CityChunk, s: Dictionary) -> float:
	var fp: Rect2 = s.rect
	var hi := -INF
	for q: Vector2 in [fp.position, fp.end, Vector2(fp.position.x, fp.end.y), Vector2(fp.end.x, fp.position.y), fp.get_center()]:
		hi = maxf(hi, ch._gy(q.x, q.y))
	return hi + CityChunk.SIDEWALK_TOP + FLOOR_LIFT


## CityChunk._build_lot's hook: the store, FULL or far.
static func build_lot(ch: CityChunk, lot: Dictionary) -> void:
	var s := plan_for(ch.plan, ch.ix, ch.iz)
	if s.is_empty() or int(lot.seed) != int(s.lot):
		return
	ch._lot_rects.append(s.rect as Rect2)
	var xf := local_transform(ch, s)
	ch.building_count += 1
	if ch.level != CityChunk.Level.FULL:
		_build_far(ch, s, xf)
		return
	CornerStoreKit.build(ch, s, layout(s), xf)


## LOD chunks and the far city: the box in its stucco, the sign band as a lit panel.
static func _build_far(ch: CityChunk, s: Dictionary, xf: Transform3D) -> void:
	var W: float = s.W
	var D: float = s.D
	var b := xf.basis
	var sd := int(s.seed)
	var stucco: Color = s.stucco
	var sign: Array = s.sign
	var rel: float = s.get("relief", 0.0)
	var body_c := xf * Vector3(0.0, (PARAPET - 0.5 - rel) * 0.5, -D * 0.5)
	var body_s := Vector3(W, PARAPET + 0.5 + rel, D)
	var o := body_c
	o.y -= ch._gy(o.x, o.z)
	ch._batch.add("lod_box", PropFactory.unit_box(), Transform3D(b * Basis.from_scale(body_s), o),
			Color(stucco.r, stucco.g, stucco.b, 1.0), Color(0.0, 0.0, float(sd % 997) / 997.0, 1.0))
	ch._add_lod_shape((b * body_s).abs(), body_c)
	var cs := corner_sign(s)
	var face: Color = sign[0]
	for pn: Array in [[Vector3(0.0, (SIGN_Y.x + SIGN_Y.y) * 0.5, 0.12), Vector3(W, SIGN_Y.y - SIGN_Y.x, 0.2)],
			[Vector3(cs * (W * 0.5 + 0.12), (SIGN_Y.x + SIGN_Y.y) * 0.5, -D * 0.3), Vector3(0.2, SIGN_Y.y - SIGN_Y.x, D * 0.6)]]:
		var c: Vector3 = xf * (pn[0] as Vector3)
		c.y -= ch._gy(c.x, c.z)
		ch._batch.add("lod_box", PropFactory.unit_box(), Transform3D(b * Basis.from_scale(pn[1] as Vector3), c), face,
				Color(float(FarBuilding.Plant.PANEL), 1.0, 1.0, FarBuilding.PLANT_FLAG))
