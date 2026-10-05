class_name VacantLots
extends RefCounted
## The in-between land that makes a city real (2026-10-05, the vacant-lots pass): Los Angeles has
## vacant lots everywhere, and until this every lot in the city was built or filled. Now a small
## share of the lots in MIDTOWN, INDUSTRIAL and at the edges of DOWNTOWN stand empty:
##   - a VACANT lot is dry dirt and gravel with tyre ruts in from the gate, mats of dry grass,
##     tufts of foxtail, clumps of wild mustard and fennel in flower, a lone weed tree or palm, the
##     broken slab of a demolished building with its stem walls and rebar, rubble piles, dumped
##     furniture, tyres and a shopping cart, chain-link on the street sides with a privacy screen
##     and a padlocked gate, a FOR LEASE / FOR SALE sign with an invented broker's name and a 555
##     number, a NO TRESPASSING plate;
##   - a GRAVEL CAR PARK (downtown's edges and round the arena) is crushed stone with wheel stops
##     in rows and parked cars, an open gate with cones, a hand-painted PARKING $10 board and the
##     attendant's booth.
## Claimed in CityChunk._build_lot() after every roll the lot makes (the pad roll on the block rng,
## the corridor, fire station and car park checks), so nothing a seed builds elsewhere moves; the
## Building is never made. Every roll here is a hash of the plan seed and the lot (`kind_of()`,
## `plan_lot()` are PURE: GroundCoverage and the checks ask the same question the chunk does).
## Never on a landmark's, a replica area's, a rec park's or a school's block (CityPlan.lots() is
## empty there, or the replica's own), never a courtyard, a corridor lot or an inner lot.
## A FULL chunk's lots are ONE ground mesh (shaders/vacant_ground.gdshader, no shadow) and ONE
## upright mesh (shaders/vacant_walls.gdshader, casting: every fence, sign, letter, slab, pile and
## piece of junk; VacantKit's writers), plus three weed batches (shaders/vacant_weeds.gdshader, no
## shadow) and ArenaGrounds' parked cars. LOD chunks and the far city's capture get the lot as ONE
## ground slab in its dirt or gravel colour, so the gaps show from the air.
## Billboards on vacant lots are the Billboards module's (none are added here).

## Off, every lot builds as it did before this (the A/B: VACANT_LOTS=0 in the environment).
static var enabled: bool = OS.get_environment("VACANT_LOTS") != "0"

const NONE := 0
const VACANT := 1
const PARKING := 2

# --- Ground kinds: shaders/vacant_ground.gdshader, COLOR.r in 8ths ------------------------------
const G_DIRT := 0
const G_SLAB := 1
const G_GRAVEL := 2

## The ground's top over the pavement slab (Industrial's yards use the same), and its skirt.
const LIFT := 0.05
const SKIRT := 0.12

## Odds an edge lot of a district stands empty (a hash of seed + lot). DOWNTOWN only where its
## skyline boost is under EDGE_BOOST (the edges, not the core).
const ODDS := {CityPlan.District.MIDTOWN: 0.06, CityPlan.District.INDUSTRIAL: 0.055, CityPlan.District.DOWNTOWN: 0.075}
const EDGE_BOOST := 0.3
## Round the arena (event parking): extra odds within ARENA_REACH metres, and the share of those
## that are car parks.
const ARENA_REACH := 750.0
const ARENA_ODDS := 0.1
const ARENA_PARKING := 0.85
## Of the empty lots, the share that are gravel car parks.
const PARKING_SHARE := {CityPlan.District.MIDTOWN: 0.12, CityPlan.District.INDUSTRIAL: 0.0, CityPlan.District.DOWNTOWN: 0.6}
## The smallest lot that can stand empty (metres, both sides).
const MIN_LOT := 12.0

## A vacant lot's pieces: odds of a demolished building's slab, a privacy screen on a street run,
## a FOR LEASE / SALE sign, a lone tree (a palm for this share of them), an old fence on a side.
const SLAB_ODDS := 0.65
const SCREEN_ODDS := 0.45
const SIGN_ODDS := 0.8
const TREE_ODDS := 0.45
const PALM_SHARE := 0.35
const SIDE_FENCE_ODDS := 0.5
## Weeds per square metre of open dirt, and the chunk's budgets.
const TUFT_DENSITY := 0.55
const MAX_TUFTS := 1400
const MAX_MUSTARD := 260
const MAX_FENNEL := 90
const TUFT_DISTANCE := 110.0
const TALL_WEED_DISTANCE := 150.0
## Car parks: a stall, the aisle between rows, the fill of cars.
const STALL := Vector2(2.7, 5.4)
const AISLE := 7.0
const CAR_FILL := Vector2(0.35, 0.8)
const ARENA_FILL := Vector2(0.7, 0.95)

## Screen colours (sRGB, as written): black, dark green, a faded green, a blue tarp.
const SCREEN_PAINTS := [Color(0.08, 0.09, 0.09), Color(0.1, 0.2, 0.13), Color(0.18, 0.28, 0.2), Color(0.12, 0.14, 0.13), Color(0.14, 0.26, 0.42)]
const SOFA_PAINTS := [Color(0.42, 0.33, 0.24), Color(0.3, 0.32, 0.36), Color(0.5, 0.18, 0.14), Color(0.22, 0.3, 0.22), Color(0.6, 0.55, 0.45), Color(0.25, 0.22, 0.3)]
const BOOTH_PAINTS := [Color(0.86, 0.84, 0.78), Color(0.2, 0.36, 0.5), Color(0.72, 0.18, 0.12), Color(0.86, 0.72, 0.28)]
## Invented brokers (never a real firm), their brand colour, and the area codes on their boards.
const BROKERS := ["HALVERSON LAND CO.", "CALDERA COMMERCIAL", "MERIDIAN LOT PARTNERS", "VALDEZ & KORR REALTY",
	"OAKMONT GROUND ADVISORS", "BRISA PROPERTY GROUP", "TALLOW & PIKE REAL ESTATE", "NORTHGATE PARCEL CO."]
const BROKER_PAINTS := [Color(0.72, 0.1, 0.1), Color(0.08, 0.22, 0.5), Color(0.06, 0.36, 0.26), Color(0.12, 0.12, 0.14),
	Color(0.8, 0.42, 0.06), Color(0.0, 0.42, 0.52), Color(0.42, 0.1, 0.32), Color(0.2, 0.3, 0.12)]
const AREA_CODES := ["213", "323", "310", "818", "562"]
## The far slab's colours (city ground colours, as Industrial's yards hand them over).
const FAR_DIRT := Color(0.6, 0.52, 0.4)
const FAR_GRAVEL := Color(0.6, 0.58, 0.54)

static var _arena: Variant = null


static func _h01(parts: Array) -> float:
	return float(absi(hash(parts)) % 100003) / 100003.0


static func _pick(list: Array, parts: Array) -> Variant:
	return list[absi(hash(parts)) % list.size()]


## Where the arena stands (Landmarks' "arena"), or a point nowhere near anything.
static func arena_xz() -> Vector2:
	if _arena == null:
		_arena = Vector2(1e9, 1e9)
		for lm: Dictionary in Landmarks.all():
			if String(lm.id) == "arena":
				_arena = lm.anchor
				break
	return _arena


# --- The pure plans -----------------------------------------------------------------------------

## What a lot of the plan becomes: NONE (built as before), VACANT or PARKING. Pure.
static func kind_of(plan: CityPlan, bx: int, bz: int, lot: Dictionary) -> int:
	if not enabled or plan.macro == null:
		return NONE
	if lot.get("yard", false) or lot.get("parking", false) or not lot.get("edge", false) or not lot.has("cell"):
		return NONE
	var size: Vector2 = lot.size
	if size.x < MIN_LOT or size.y < MIN_LOT:
		return NONE
	var b: Dictionary = plan.block(bx, bz)
	if int(b.kind) != CityPlan.BlockKind.BUILDINGS or b.has("site") or b.has("grounds"):
		return NONE
	var district: int = b.district
	if not ODDS.has(district):
		return NONE
	if plan.macro.replica and plan.macro.replica.block_role(plan, bx, bz) != 0:
		return NONE
	var centre: Vector2 = lot.center
	var odds: float = ODDS[district]
	var share: float = PARKING_SHARE[district]
	var near_arena := centre.distance_to(arena_xz()) < ARENA_REACH
	if district == CityPlan.District.DOWNTOWN and plan.macro.skyline_boost(centre) >= EDGE_BOOST and not near_arena:
		return NONE
	if near_arena:
		odds += ARENA_ODDS
		share = ARENA_PARKING
	if _h01([plan.seed, lot.seed, "vacant"]) >= odds:
		return NONE
	if plan.zone_at(centre) != MacroMap.Zone.CITY:
		return NONE
	if YardFill.is_corridor(plan, lot) or FireStation.claims(plan, bx, bz, lot):
		return NONE
	if not Industrial.clear_of_freeway(plan, lot.cell):
		return NONE
	return PARKING if _h01([plan.seed, lot.seed, "vacant_park"]) < share else VACANT


## The lot's layout in its street frame (Industrial.frame(): u along the street from the cell's
## left corner seen from it, v in from the street). Pure. Keys: kind, cell, side, frame, gate_u,
## ground [[rect, G_*, g, b, uv2 mode, uv2 origin, axis a, axis n, shift]], fences [{a, b, out,
## screen, paint, rusty, wear, gate: Vector2 (u0, u1) or none, open}], items [{t, p, yaw, ...}],
## slab (Rect2 or empty), stalls [[p, yaw, car]], text (the sign's lines).
static func plan_lot(plan: CityPlan, bx: int, bz: int, lot: Dictionary, kind: int) -> Dictionary:
	var b: Dictionary = plan.block(bx, bz)
	var inner: Rect2 = (b.rect as Rect2).grow(-plan.sidewalk_width)
	var cell: Rect2 = lot.cell
	var side := Industrial.lot_side(inner, cell)
	var f := Industrial.frame(cell, side)
	var L: float = f.len
	var D: float = f.depth
	var s := hash([plan.seed, lot.seed, "vacant_plan"])
	var rng := RandomNumberGenerator.new()
	rng.seed = s
	var gw := VacantKit.GATE_W if kind == VACANT else 7.0
	var gate_u := clampf(L * rng.randf_range(0.3, 0.7), gw * 0.5 + 1.2, maxf(L - gw * 0.5 - 1.2, gw * 0.5 + 1.2))
	var out := {"kind": kind, "cell": cell, "side": side, "frame": f, "gate_u": gate_u, "ground": [], "fences": [],
		"items": [], "slab": Rect2(), "stalls": [], "seed": s, "near_arena": (lot.center as Vector2).distance_to(arena_xz()) < ARENA_REACH}
	# Which cell edges are on a street (0 -Z, 1 +Z, 2 -X, 3 +X, Industrial's order).
	var on := [absf(cell.position.y - inner.position.y) < 0.6, absf(cell.end.y - inner.end.y) < 0.6,
		absf(cell.position.x - inner.position.x) < 0.6, absf(cell.end.x - inner.end.x) < 0.6]
	on[side] = true
	var screen_paint: Color = _pick(SCREEN_PAINTS, [s, "screen"])
	var wear := _h01([s, "wear"])
	for e in 4:
		var line := _edge(cell, e, 0.35)
		var outward := [Vector2(0, -1), Vector2(0, 1), Vector2(-1, 0), Vector2(1, 0)][e] as Vector2
		var fe := {"a": line[0], "b": line[1], "out": outward, "screen": false, "paint": screen_paint, "rusty": false, "wear": wear,
			"gate": Vector2(-1.0, -1.0), "open": kind == PARKING}
		if on[e]:
			fe.screen = kind == VACANT and _h01([s, e, "scr"]) < SCREEN_ODDS
			fe.rusty = kind == VACANT and _h01([s, e, "rust"]) < 0.4
		elif kind == VACANT and _h01([s, e, "side"]) < SIDE_FENCE_ODDS:
			fe.rusty = true
		else:
			continue
		if e == side:
			# The edge line runs from u 0 to u L (the frame's corner is the line's start for sides
			# 0 and 3, its end for 1 and 2): the gate's span measured from `a`.
			var ga := gate_u - gw * 0.5
			var gb := gate_u + gw * 0.5
			var len := (fe.a as Vector2).distance_to(fe.b)
			if Industrial.fp(f, 0.0, 0.35).distance_to(fe.a) > 1.0:
				fe.gate = Vector2(len - gb, len - ga)
			else:
				fe.gate = Vector2(ga, gb)
		out.fences.append(fe)
	if kind == VACANT:
		var tagged := lot.duplicate()
		tagged["_district"] = int(b.district)
		_plan_vacant(plan, out, rng, tagged)
	else:
		_plan_parking(out, rng)
	return out


## A cell edge as a line `inset` metres inside it: [a, b] (world xz).
static func _edge(r: Rect2, e: int, inset: float) -> Array:
	match e:
		0:
			return [Vector2(r.position.x, r.position.y + inset), Vector2(r.end.x, r.position.y + inset)]
		1:
			return [Vector2(r.position.x, r.end.y - inset), Vector2(r.end.x, r.end.y - inset)]
		2:
			return [Vector2(r.position.x + inset, r.position.y), Vector2(r.position.x + inset, r.end.y)]
		_:
			return [Vector2(r.end.x - inset, r.position.y), Vector2(r.end.x - inset, r.end.y)]


static func _plan_vacant(plan: CityPlan, out: Dictionary, rng: RandomNumberGenerator, lot: Dictionary) -> void:
	var f: Dictionary = out.frame
	var L: float = f.len
	var D: float = f.depth
	var cell: Rect2 = out.cell
	var s: int = out.seed
	var gate_u: float = out.gate_u
	var slab := Rect2()
	if L >= 14.0 and D >= 14.0 and rng.randf() < SLAB_ODDS:
		var u0 := rng.randf_range(1.5, L * 0.18)
		var u1 := L - rng.randf_range(1.5, L * 0.18)
		var v0 := rng.randf_range(3.0, minf(7.0, D * 0.3))
		var v1 := D - rng.randf_range(1.2, 4.0)
		if u1 - u0 >= 8.0 and v1 - v0 >= 8.0:
			slab = Industrial.fr(f, u0, v0, u1, v1)
	out.slab = slab
	var a: Vector2 = f.a
	var n: Vector2 = f.n
	var o: Vector2 = f.o
	if slab.size != Vector2.ZERO:
		out.ground.append([slab, G_SLAB, slab.size.x / 64.0, slab.size.y / 64.0, "local", slab.position, Vector2(1, 0), Vector2(0, 1), 0.0])
		for piece: Rect2 in Industrial._minus(cell, slab):
			if piece.size.x > 0.05 and piece.size.y > 0.05:
				out.ground.append([piece, G_DIRT, _h01([s, "var"]), 0.0, "frame", o, a, n, gate_u])
	else:
		out.ground.append([cell, G_DIRT, _h01([s, "var"]), 0.0, "frame", o, a, n, gate_u])
	var items: Array = out.items
	var taken: Array[Rect2] = []
	# Keep the drive in from the gate clear (the ruts run there).
	taken.append(Industrial.fr(f, gate_u - 2.4, 0.0, gate_u + 2.4, minf(16.0, D)))
	# The slab's broken stem walls with rebar, and a few heaved pieces of it.
	if slab.size != Vector2.ZERO:
		items.append({"t": "stem", "r": slab})
		for i in rng.randi_range(2, 5):
			var p := Vector2(rng.randf_range(slab.position.x, slab.end.x), rng.randf_range(slab.position.y, slab.end.y))
			items.append({"t": "chunk", "p": p, "yaw": rng.randf() * TAU, "size": Vector2(rng.randf_range(0.9, 2.4), rng.randf_range(0.7, 1.8)), "tilt": rng.randf_range(0.15, 0.5)})
	# Rubble piles.
	for i in rng.randi_range(1, 2 + int(L * D > 900.0)):
		var r := rng.randf_range(1.2, 2.8)
		var p := _free_spot(f, rng, taken, r + 0.5, 1.5 + r, D - 1.0 - r)
		if p != Vector2.INF:
			items.append({"t": "rubble", "p": p, "r": r, "brick": rng.randf() < 0.5})
			taken.append(Rect2(p - Vector2(r, r), Vector2(r, r) * 2.0))
	# Dumped junk, mostly just inside the street fence (thrown over it, or left at the gate).
	var junk := ["sofa", "armchair", "mattress", "tyres", "tyres", "tv", "cart", "mattress_lean", "sofa"]
	for i in rng.randi_range(2, 5):
		var t: String = junk[rng.randi() % junk.size()]
		var near := rng.randf() < 0.7
		var v_lo := 1.2 if near else 3.0
		var v_hi := 4.5 if near else D - 2.0
		if t == "mattress_lean":
			v_lo = 0.95
			v_hi = 1.0
		var p := _free_spot(f, rng, taken, 1.2, v_lo, v_hi)
		if p == Vector2.INF:
			continue
		var yaw := Industrial.yaw_to(-n) + (0.0 if t == "mattress_lean" else rng.randf_range(-1.2, 1.2))
		items.append({"t": t, "p": p, "yaw": yaw, "paint": _pick(SOFA_PAINTS, [s, i, "paint"]), "n": rng.randi_range(2, 6), "flag": rng.randf() < 0.5})
		taken.append(Rect2(p - Vector2(1.2, 1.2), Vector2(2.4, 2.4)))
	# A lone weed tree (an ailanthus is what grows in these) or a palm, toward the back.
	if rng.randf() < TREE_ODDS and D > 10.0:
		var p := _free_spot(f, rng, taken, 1.5, maxf(D - 6.0, 3.0), D - 1.6)
		if p != Vector2.INF:
			items.append({"t": "palm" if rng.randf() < PALM_SHARE else "tree", "p": p, "yaw": rng.randf() * TAU, "h": rng.randf_range(4.5, 8.0), "v": rng.randi()})
	# The broker's board facing the street, clear of the gate.
	if rng.randf() < SIGN_ODDS and L > 10.0:
		var u := rng.randf_range(2.6, L - 2.6)
		if absf(u - gate_u) < VacantKit.GATE_W * 0.5 + 2.4:
			u = gate_u + (VacantKit.GATE_W * 0.5 + 2.6) * (1.0 if gate_u < L * 0.5 else -1.0)
		var acres := (cell.size.x * cell.size.y) / 4046.9
		var broker := absi(hash([s, "broker"])) % BROKERS.size()
		var industrial: bool = int(lot.get("_district", -1)) == CityPlan.District.INDUSTRIAL
		var lines := ["FOR LEASE" if rng.randf() < 0.55 else "FOR SALE",
			"%.2f ACRES" % acres if acres >= 0.1 else "%d SQ FT" % int(cell.size.x * cell.size.y * 10.764),
			("INDUSTRIAL LAND" if industrial else ["BUILD TO SUIT", "LAND FOR SALE", "WILL DIVIDE", "ZONED COMMERCIAL"][absi(hash([s, "pitch"])) % 4]),
			BROKERS[broker],
			"(%s) 555-%04d" % [AREA_CODES[absi(hash([s, "area"])) % AREA_CODES.size()], 100 + absi(hash([s, "phone"])) % 99]]
		items.append({"t": "lease", "p": Industrial.fp(f, u, 1.1), "face": -n, "lines": lines, "brand": BROKER_PAINTS[broker]})
	# NO TRESPASSING on the gate.
	items.append({"t": "trespass", "p": Industrial.fp(f, gate_u + VacantKit.GATE_W * 0.25, 0.35), "face": -n})
	# The weeds' patches: mustard and fennel stands (the tufts go everywhere open).
	var patches: Array = []
	for i in rng.randi_range(2, 4):
		patches.append([Industrial.fp(f, rng.randf_range(2.0, L - 2.0), rng.randf_range(2.0, D - 2.0)), rng.randf_range(2.0, 5.0), "mustard"])
	for i in rng.randi_range(0, 2):
		patches.append([Industrial.fp(f, rng.randf_range(2.0, L - 2.0), rng.randf_range(2.0, D - 2.0)), rng.randf_range(1.2, 2.8), "fennel"])
	out["patches"] = patches
	out["taken"] = taken


static func _free_spot(f: Dictionary, rng: RandomNumberGenerator, taken: Array[Rect2], r: float, v_lo: float, v_hi: float) -> Vector2:
	var L: float = f.len
	for attempt in 8:
		var u := rng.randf_range(r + 0.6, maxf(L - r - 0.6, r + 0.7))
		var v := rng.randf_range(v_lo, maxf(v_hi, v_lo + 0.01))
		var p := Industrial.fp(f, u, v)
		var box := Rect2(p - Vector2(r, r), Vector2(r, r) * 2.0)
		var hit := false
		for t: Rect2 in taken:
			if t.intersects(box):
				hit = true
				break
		if not hit:
			return p
	return Vector2.INF


static func _plan_parking(out: Dictionary, rng: RandomNumberGenerator) -> void:
	var f: Dictionary = out.frame
	var L: float = f.len
	var D: float = f.depth
	var cell: Rect2 = out.cell
	var s: int = out.seed
	var gate_u: float = out.gate_u
	var a: Vector2 = f.a
	var n: Vector2 = f.n
	var o: Vector2 = f.o
	# Rows parallel to the street: a row against the front fence (broken by the entrance), an aisle,
	# then back to back rows and aisles to the back.
	var rows: Array = [] # [v of the row's start, which way the noses point (+1 inward / -1 toward the street)]
	var v := 0.7
	rows.append([v, -1.0])
	v += STALL.y + AISLE
	while v + STALL.y <= D - 0.4:
		rows.append([v, 1.0])
		if v + STALL.y * 2.0 <= D - 0.4:
			rows.append([v + STALL.y, -1.0])
			v += STALL.y * 2.0 + AISLE
		else:
			v += STALL.y + AISLE
	out.ground.append([cell, G_GRAVEL, _h01([s, "var"]), (STALL.y * 2.0 + AISLE) / 32.0, "frame", o, a, n, 0.0])
	var fill := rng.randf_range(ARENA_FILL.x, ARENA_FILL.y) if out.near_arena else rng.randf_range(CAR_FILL.x, CAR_FILL.y)
	var nst := int((L - 1.0) / STALL.x)
	var u0 := (L - float(nst) * STALL.x) * 0.5
	var booth_u := gate_u + 3.5 + 1.0
	for ri in rows.size():
		var row: Array = rows[ri]
		var vc: float = float(row[0]) + STALL.y * 0.5
		for i in nst:
			var su := u0 + (float(i) + 0.5) * STALL.x
			if ri == 0 and absf(su - gate_u) < 3.5 + 3.2:
				continue
			if ri == 0 and absf(su - booth_u) < 2.4:
				continue
			var p := Industrial.fp(f, su, vc)
			# The nose end of the stall, where its wheel stop lies.
			var nose := float(row[1])
			var stop := Industrial.fp(f, su, vc + nose * (STALL.y * 0.5 - 0.6))
			var car := _h01([s, ri, i, "car"]) < fill
			out.stalls.append([p, Industrial.yaw_to(n * nose), car, stop])
	out.items.append({"t": "booth", "p": Industrial.fp(f, booth_u, 1.6), "yaw": Industrial.yaw_to(-n), "paint": _pick(BOOTH_PAINTS, [s, "booth"])})
	out.items.append({"t": "price", "p": Industrial.fp(f, gate_u - 3.5 - 1.3, 0.75), "face": -n, "event": out.near_arena})
	for k: float in [-1.0, 1.0]:
		out.items.append({"t": "cone", "p": Industrial.fp(f, gate_u + k * 3.2, 0.9)})
	out["patches"] = []
	out["taken"] = []


# --- Building it (CityChunk) --------------------------------------------------------------------

## Claims the lot if it is one of ours and builds it (any tier). True when claimed: the chunk then
## builds nothing else on it. Called after every roll _build_lot makes.
static func build_lot(ch: CityChunk, lot: Dictionary) -> bool:
	if not enabled or ch.zone != MacroMap.Zone.CITY:
		return false
	var kind := kind_of(ch.plan, ch.ix, ch.iz, lot)
	if kind == NONE:
		return false
	var lp := plan_lot(ch.plan, ch.ix, ch.iz, lot, kind)
	var cell: Rect2 = lp.cell
	if ch.level != CityChunk.Level.FULL or ch.capturing:
		# One slab in the lot's colour: the far city records it as ground.
		var c := cell.get_center()
		var col := FAR_DIRT if kind == VACANT else FAR_GRAVEL
		ch._add_slab(Vector3(c.x, CityChunk.SIDEWALK_TOP + LIFT - 0.02, c.y), Vector3(cell.size.x, 0.04, cell.size.y), col, false,
			PropFactory.pbr("hill_dirt", 4.0, col * 1.35))
		_state(ch).lots.append(lp)
		return true
	var stt := _state(ch)
	stt.lots.append(lp)
	for gr: Array in lp.ground:
		stt.ground.append(gr)
	_build_full(ch, lp)
	return true


static func _state(ch: CityChunk) -> Dictionary:
	if not ch.has_meta("vacant_lots"):
		ch.set_meta("vacant_lots", {"lots": [], "ground": [], "walls": null, "counts": {}})
	return ch.get_meta("vacant_lots")


static func _walls(ch: CityChunk) -> SurfaceTool:
	var stt := _state(ch)
	if stt.walls == null:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.set_smooth_group(-1)
		stt.walls = st
	return stt.walls


static func _count(ch: CityChunk, key: String, budget: int) -> bool:
	var c: Dictionary = _state(ch).counts
	var n: int = int(c.get(key, 0))
	if n >= budget:
		return false
	c[key] = n + 1
	return true


## A chunk-space point on the lot's ground (over the relief).
static func _g(ch: CityChunk, p: Vector2) -> Vector3:
	return Vector3(p.x, CityChunk.SIDEWALK_TOP + LIFT + ch._gy(p.x, p.y), p.y)


static func _v3(d: Vector2) -> Vector3:
	return Vector3(d.x, 0.0, d.y)


static func _build_full(ch: CityChunk, lp: Dictionary) -> void:
	var st := _walls(ch)
	var f: Dictionary = lp.frame
	var inward := _v3(f.n)
	for fe: Dictionary in lp.fences:
		var a: Vector2 = fe.a
		var b: Vector2 = fe.b
		var g: Vector2 = fe.gate
		var runs: Array = []
		if g.x >= 0.0:
			var dir := (b - a).normalized()
			runs.append([a, a + dir * g.x])
			runs.append([a + dir * g.y, b])
			var ga := a + dir * g.x
			var gb := a + dir * g.y
			if lp.kind == VACANT:
				VacantKit.gate(st, _g(ch, ga), _g(ch, gb), inward, false, fe.screen, fe.paint, fe.wear)
				ch._add_shape(Vector3(ga.distance_to(gb), VacantKit.FENCE_H, 0.1), _g(ch, (ga + gb) * 0.5) + Vector3.UP * VacantKit.FENCE_H * 0.5, atan2(-dir.y, dir.x))
		else:
			runs.append([a, b])
		for r: Array in runs:
			var ra: Vector2 = r[0]
			var rb: Vector2 = r[1]
			if ra.distance_to(rb) < 0.4:
				continue
			VacantKit.fence_run(st, _g(ch, ra), _g(ch, rb), _v3(fe.out), fe.screen, fe.paint, fe.rusty, fe.wear)
			var d := rb - ra
			ch._add_shape(Vector3(d.length(), VacantKit.FENCE_H, 0.1), _g(ch, (ra + rb) * 0.5) + Vector3.UP * VacantKit.FENCE_H * 0.5, atan2(-d.y, d.x))
	for it: Dictionary in lp.items:
		_item(ch, st, lp, it)
	for sl: Array in lp.stalls:
		var p: Vector2 = sl[0]
		var yaw: float = sl[1]
		var stop: Vector2 = sl[3]
		VacantKit.box(st, Transform3D(Basis(Vector3.UP, yaw), _g(ch, stop) + Vector3.UP * 0.06), Vector3(1.8, 0.12, 0.16), VacantKit.K_CONCRETE, Color(0.9, 0.88, 0.82))
		if sl[2]:
			var rng := RandomNumberGenerator.new()
			rng.seed = hash([lp.seed, p, "car"])
			LotFill._car(ch, rng, Vector3(p.x, CityChunk.SIDEWALK_TOP + LIFT, p.y), yaw + (rng.randf() - 0.5) * 0.08)
	if lp.kind == VACANT:
		_weeds(ch, lp)
	else:
		# A few tufts along the fences, where nothing drives.
		_weeds(ch, lp, 0.12)


static func _item(ch: CityChunk, st: SurfaceTool, lp: Dictionary, it: Dictionary) -> void:
	var t: String = it.t
	match t:
		"stem":
			_stem_walls(ch, st, it.r, lp.seed)
		"chunk":
			var p: Vector2 = it.p
			var sz: Vector2 = it.size
			var xf := Transform3D(Basis(Vector3.UP, it.yaw) * Basis(Vector3.RIGHT, it.tilt), _g(ch, p) + Vector3.UP * 0.05)
			VacantKit.box(st, xf, Vector3(sz.x, 0.16, sz.y), VacantKit.K_CONCRETE, Color(0.93, 0.92, 0.88), 0.0, 0)
			ch._add_shape(Vector3(sz.x, 0.4, sz.y), _g(ch, p) + Vector3.UP * 0.2, it.yaw)
		"rubble":
			var p: Vector2 = it.p
			var r: float = it.r
			VacantKit.rubble(st, _g(ch, p), r, absi(hash([lp.seed, p])), it.brick)
			ch._add_shape(Vector3(r * 1.2, r * 0.42, r * 1.2), _g(ch, p) + Vector3.UP * r * 0.21)
		"sofa":
			VacantKit.sofa(st, Transform3D(Basis(Vector3.UP, it.yaw), _g(ch, it.p)), it.paint, 1.0 if it.flag else 0.3)
			ch._add_shape(Vector3(2.0, 0.85, 0.9), _g(ch, it.p) + Vector3.UP * 0.42, it.yaw)
		"armchair":
			VacantKit.armchair(st, Transform3D(Basis(Vector3.UP, it.yaw), _g(ch, it.p)), it.paint)
			ch._add_shape(Vector3(0.85, 0.9, 0.85), _g(ch, it.p) + Vector3.UP * 0.45, it.yaw)
		"mattress":
			VacantKit.mattress(st, Transform3D(Basis(Vector3.UP, it.yaw), _g(ch, it.p)), Color(0.95, 0.93, 0.88), 0.0)
		"mattress_lean":
			# Against the inside of the street fence, leaning back into it.
			VacantKit.mattress(st, Transform3D(Basis(Vector3.UP, it.yaw), _g(ch, it.p)), Color(0.95, 0.93, 0.88), 0.22)
		"tyres":
			VacantKit.tyres(st, Transform3D(Basis(), _g(ch, it.p)), int(it.n), it.flag, absi(hash([lp.seed, it.p])))
		"tv":
			VacantKit.television(st, Transform3D(Basis(Vector3.UP, it.yaw) * Basis(Vector3.RIGHT, -PI * 0.5 if it.flag else 0.0), _g(ch, it.p) + (Vector3.UP * 0.25 if it.flag else Vector3.ZERO)), Color(0.12, 0.12, 0.13))
		"cart":
			VacantKit.cart(st, Transform3D(Basis(Vector3.UP, it.yaw), _g(ch, it.p)), it.flag)
		"tree":
			var v := 0 if int(it.v) % 2 == 0 else 2
			var sc := PropFactory.city_tree_scale(v, it.h)
			var tint := Color(0.92, 0.96, 0.82)
			ch._batch.add("tree_%d" % v, PropFactory.model_tree(v), Transform3D(Basis(Vector3.UP, it.yaw).scaled(Vector3(sc, sc, sc)), Vector3(it.p.x, CityChunk.SIDEWALK_TOP, it.p.y)), tint, Color(0.3, 0.6, 0.4, 0.5))
			ch._add_shape(Vector3(0.4, 4.0, 0.4), _g(ch, it.p) + Vector3.UP * 2.0)
		"palm":
			var v := absi(int(it.v)) % PropFactory.PALM_VARIANTS
			var sc := clampf(float(it.h) / 8.0, 0.6, 1.0)
			ch._batch.add("palm_%d" % v, PropFactory.palm(v), Transform3D(Basis(Vector3.UP, it.yaw).scaled(Vector3(sc, sc, sc)), Vector3(it.p.x, CityChunk.SIDEWALK_TOP, it.p.y)), Color(0.95, 0.95, 0.85))
			ch._add_shape(Vector3(0.5, 6.0 * sc, 0.5), _g(ch, it.p) + Vector3.UP * 3.0 * sc)
		"lease":
			var face := _v3(it.face)
			var lines: Array = it.lines
			var brand: Color = it.brand
			var xf := VacantKit.sign_board(st, _g(ch, it.p), face, Vector2(2.44, 1.22), 1.25, Color(0.95, 0.95, 0.93), 0.32, brand, true, false)
			VacantKit.letters(st, lines[0], 0.2, xf.translated_local(Vector3(0.0, 0.45, 0.004)), Color(0.98, 0.98, 0.96), 2.2)
			VacantKit.letters(st, lines[1], 0.15, xf.translated_local(Vector3(0.0, 0.15, 0.004)), Color(0.08, 0.08, 0.09), 2.2)
			VacantKit.letters(st, lines[2], 0.11, xf.translated_local(Vector3(0.0, -0.06, 0.004)), Color(0.15, 0.15, 0.16), 2.2)
			VacantKit.letters(st, lines[3], 0.13, xf.translated_local(Vector3(0.0, -0.3, 0.004)), brand, 2.25)
			VacantKit.letters(st, lines[4], 0.15, xf.translated_local(Vector3(0.0, -0.5, 0.004)), Color(0.08, 0.08, 0.09), 2.2)
			ch._add_shape(Vector3(2.44, 2.5, 0.2), _g(ch, it.p) + Vector3.UP * 1.25, atan2(face.x, face.z))
		"trespass":
			var face := _v3(it.face)
			var xf := VacantKit.sign_board(st, _g(ch, it.p) + face * 0.04, face, Vector2(0.46, 0.3), 1.05, Color(0.96, 0.96, 0.94), 0.0, Color.WHITE, false, false)
			VacantKit.letters(st, "NO TRESPASSING", 0.05, xf.translated_local(Vector3(0.0, 0.06, 0.004)), Color(0.75, 0.08, 0.06), 0.42)
			VacantKit.letters(st, "PRIVATE PROPERTY", 0.032, xf.translated_local(Vector3(0.0, -0.035, 0.004)), Color(0.1, 0.1, 0.1), 0.4)
			VacantKit.letters(st, "VIOLATORS WILL BE PROSECUTED", 0.022, xf.translated_local(Vector3(0.0, -0.09, 0.004)), Color(0.1, 0.1, 0.1), 0.4)
		"booth":
			VacantKit.booth(st, Transform3D(Basis(Vector3.UP, it.yaw), _g(ch, it.p)), it.paint)
			ch._add_shape(Vector3(1.7, 2.4, 1.6), _g(ch, it.p) + Vector3.UP * 1.2, it.yaw)
		"price":
			# Hand-painted on plywood, propped on two stakes inside the fence.
			var face := _v3(it.face)
			var xf := VacantKit.sign_board(st, _g(ch, it.p), face, Vector2(1.22, 0.92), 0.35, Color(0.95, 0.93, 0.86), 0.0, Color.WHITE, true, true)
			var red := Color(0.72, 0.08, 0.05)
			VacantKit.letters(st, "PARKING", 0.17, xf.translated_local(Vector3(0.0, 0.28, 0.004)), Color(0.08, 0.08, 0.08), 1.1)
			VacantKit.letters(st, "$20" if it.event else "$10", 0.36, xf.translated_local(Vector3(0.0, -0.02, 0.004)), red, 1.0)
			VacantKit.letters(st, "EVENT" if it.event else "ALL DAY", 0.12, xf.translated_local(Vector3(0.0, -0.32, 0.004)), Color(0.08, 0.08, 0.08), 1.0)
		"cone":
			VacantKit.cone(st, Transform3D(Basis(), _g(ch, it.p)))


## The demolished building's stem walls round its slab, broken into runs with gaps, rebar sticking
## up from the broken ends.
static func _stem_walls(ch: CityChunk, st: SurfaceTool, r: Rect2, seed: int) -> void:
	var sides := [[r.position, Vector2(r.end.x, r.position.y)], [Vector2(r.position.x, r.end.y), r.end],
		[r.position, Vector2(r.position.x, r.end.y)], [Vector2(r.end.x, r.position.y), r.end]]
	for k in 4:
		var a: Vector2 = sides[k][0]
		var b: Vector2 = sides[k][1]
		var len := a.distance_to(b)
		var dir := (b - a) / len
		var yaw := atan2(-dir.y, dir.x)
		var t := 0.0
		var i := 0
		while t < len - 0.5:
			var run := lerpf(1.5, 6.0, _h01([seed, k, i, "run"]))
			var gap := lerpf(0.6, 3.5, _h01([seed, k, i, "gap"]))
			var e := minf(t + run, len)
			if _h01([seed, k, i, "keep"]) < 0.7:
				var m := a + dir * (t + e) * 0.5
				var hgt := lerpf(0.15, 0.45, _h01([seed, k, i, "h"]))
				VacantKit.box(st, Transform3D(Basis(Vector3.UP, yaw), _g(ch, m) + Vector3.UP * (hgt * 0.5 - 0.08)), Vector3(e - t, hgt, 0.22), VacantKit.K_CONCRETE, Color(0.88, 0.87, 0.83))
				# Rebar out of the broken end.
				for j in 3:
					var rp := a + dir * (e - 0.05) + Vector2(-dir.y, dir.x) * (float(j) - 1.0) * 0.06
					var rh := lerpf(0.2, 0.7, _h01([seed, k, i, j, "rb"]))
					var lean := Basis(Vector3.UP, yaw) * Basis(Vector3.FORWARD, (_h01([seed, k, i, j, "rl"]) - 0.5) * 0.9)
					VacantKit.box(st, Transform3D(lean, _g(ch, rp) + Vector3.UP * (hgt + rh * 0.5 - 0.1)), Vector3(0.016, rh, 0.016), VacantKit.K_RUST, Color.WHITE)
			t = e + gap
			i += 1


## Weeds: tufts over the open dirt (fewer on the slab, none in the ruts), mustard and fennel in
## their stands. A private rng of the lot. `scale` thins it (a car park's edges).
static func _weeds(ch: CityChunk, lp: Dictionary, scale: float = 1.0) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([lp.seed, "weeds"])
	var cell: Rect2 = lp.cell
	var slab: Rect2 = lp.slab
	var f: Dictionary = lp.frame
	var gate_u: float = lp.gate_u
	var taken: Array = lp.taken
	var area := cell.size.x * cell.size.y
	var n := int(area * TUFT_DENSITY * scale)
	var inner := cell.grow(-0.5)
	for i in n:
		var p := Vector2(rng.randf_range(inner.position.x, inner.end.x), rng.randf_range(inner.position.y, inner.end.y))
		var sc := rng.randf_range(0.9, 1.9)
		var yaw := rng.randf() * TAU
		var dry := rng.randf()
		if scale < 1.0:
			# A car park: only along its edges.
			var e := minf(minf(p.x - cell.position.x, cell.end.x - p.x), minf(p.y - cell.position.y, cell.end.y - p.y))
			if e > 1.2:
				continue
		elif slab.size != Vector2.ZERO and slab.grow(-0.6).has_point(p) and rng.randf() < 0.85:
			continue
		var rel := p - (f.o as Vector2)
		var u := rel.dot(f.a)
		var v := rel.dot(f.n)
		if absf(u - gate_u) < 2.0 and v < 20.0 and rng.randf() < 0.8:
			continue
		var blocked := false
		for t: Rect2 in taken:
			if t.has_point(p) and t.size.x < 8.0:
				blocked = true
				break
		if blocked or not _count(ch, "tuft", MAX_TUFTS):
			continue
		var tint := Color(lerpf(0.85, 1.15, dry), lerpf(0.85, 1.1, dry), lerpf(0.75, 1.0, dry))
		ch._batch.add("vac_tuft_%d" % (0 if dry > 0.25 else 1), VacantKit.tuft(0 if dry > 0.25 else 1), Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(sc, sc * rng.randf_range(0.8, 1.3), sc)), Vector3(p.x, CityChunk.SIDEWALK_TOP + LIFT, p.y)), tint)
	for pt: Array in lp.patches:
		var c: Vector2 = pt[0]
		var r: float = pt[1]
		var mustard: bool = pt[2] == "mustard"
		var count := int(r * r * (2.2 if mustard else 0.9))
		for i in count:
			var a := rng.randf() * TAU
			var d := sqrt(rng.randf()) * r
			var p := c + Vector2(cos(a), sin(a)) * d
			if not inner.has_point(p) or (slab.size != Vector2.ZERO and slab.grow(-0.5).has_point(p)):
				continue
			if not _count(ch, "mustard" if mustard else "fennel", MAX_MUSTARD if mustard else MAX_FENNEL):
				continue
			var sc := rng.randf_range(0.75, 1.2)
			var tint := Color(rng.randf_range(0.85, 1.1), rng.randf_range(0.85, 1.1), rng.randf_range(0.8, 1.0))
			var key := "vac_mustard" if mustard else "vac_fennel"
			ch._batch.add(key, VacantKit.mustard() if mustard else VacantKit.fennel(), Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sc, sc, sc)), Vector3(p.x, CityChunk.SIDEWALK_TOP + LIFT, p.y)), tint)


static var _ground_material: ShaderMaterial = null


static func ground_material() -> ShaderMaterial:
	if _ground_material != null:
		return _ground_material
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/vacant_ground.gdshader")
	mat.set_shader_parameter("dirt_tex", PropFactory.texture("hill_dirt", "Color"))
	mat.set_shader_parameter("gravel_tex", PropFactory.texture("sidewalk", "Color"))
	mat.set_shader_parameter("concrete_tex", PropFactory.texture("concrete", "Color"))
	mat.set_shader_parameter("grass_tex", PropFactory.texture("grass", "Color"))
	_ground_material = mat
	return mat


## The FULL chunk's lots: the ground (one mesh, no shadow) and everything upright (one mesh,
## casting), and the weed batches' settings. After the batches are added, before they build.
static func commit(ch: CityChunk) -> void:
	if not ch.has_meta("vacant_lots"):
		return
	var stt := _state(ch)
	for k: String in ["vac_tuft_0", "vac_tuft_1"]:
		ch._batch.set_no_shadow(k)
		ch._batch.set_draw_distance(k, TUFT_DISTANCE)
	for k: String in ["vac_mustard", "vac_fennel"]:
		ch._batch.set_no_shadow(k)
		ch._batch.set_draw_distance(k, TALL_WEED_DISTANCE)
	if not (stt.ground as Array).is_empty():
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for gr: Array in stt.ground:
			_ground_rect(st, ch, gr)
		var mi := MeshInstance3D.new()
		mi.name = "VacantGround"
		mi.mesh = st.commit()
		mi.material_override = ground_material()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ch.add_child(mi)
	if stt.walls != null:
		var mi := MeshInstance3D.new()
		mi.name = "VacantWalls"
		mi.mesh = (stt.walls as SurfaceTool).commit()
		mi.material_override = VacantKit.walls_material()
		ch.add_child(mi)
	stt.walls = null
	(stt.ground as Array).clear()


## A ground piece at the lot's top over the relief: a grid (8 m cells, 4 m where the relief bends)
## with a skirt. UV world metres; UV2 the piece's frame (see the shader); COLOR r kind, g / b.
static func _ground_rect(st: SurfaceTool, ch: CityChunk, gr: Array) -> void:
	var r: Rect2 = gr[0]
	if r.size.x < 0.05 or r.size.y < 0.05:
		return
	var top := CityChunk.SIDEWALK_TOP + LIFT
	var col := Color((float(gr[1]) + 0.5) / 8.0, float(gr[2]), float(gr[3]), 1.0)
	var local: bool = gr[4] == "local"
	var o: Vector2 = gr[5]
	var a: Vector2 = gr[6]
	var n: Vector2 = gr[7]
	var shift: float = gr[8]
	var uv2 := func(x: float, z: float) -> Vector2:
		var d := Vector2(x, z) - o
		return d if local else Vector2(d.dot(a) - shift, d.dot(n))
	var step := 8.0 if LotFill._planar(ch, r) else 4.0
	var nx := clampi(ceili(r.size.x / step), 1, 32)
	var nz := clampi(ceili(r.size.y / step), 1, 32)
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
				st.set_uv2(uv2.call(p.x, p.z))
				st.add_vertex(p)
	# The skirt down to the pavement slab, round the outside.
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
		var nn := Vector3(e.z, 0.0, -e.x).normalized()
		if nn.dot(outv) < 0.0:
			nn = -nn
		var a0 := p0
		var a1 := p1
		if Vector3(e.z, 0.0, -e.x).dot(outv) > 0.0:
			a0 = p1
			a1 = p0
		for vv: Vector3 in [a0, a1, a1 - down, a0, a1 - down, a0 - down]:
			st.set_normal(nn)
			st.set_color(col)
			st.set_uv(Vector2(vv.x + vv.z, vv.y))
			st.set_uv2(uv2.call(vv.x, vv.z))
			st.add_vertex(vv)
