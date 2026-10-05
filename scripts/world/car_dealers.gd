class_name CarDealers
extends RefCounted
## Car dealerships (2026-10-05, "the auto rows of LA's boulevards"): runs of new-car dealers and
## used-car lots along a few long boulevards in MIDTOWN and the SUBURBS.
##
## A NEW-CAR DEALER is a glass showroom pavilion at the back of its site under a deep white roof,
## framed by a big portal in its invented brand's colours (the brand's badge on the lintel, its
## name on the fascia), a brand wall inside, a lit ceiling, cars on display on the polished floor
## (real Vehicles: they can be shot, set on fire, stolen); beside it a service drive-through with a
## canopy and two bays; in front a lot packed with rows of cars nose-out to the street, each with
## a window card (price_sticker.gdshader), the front row's middle cars real Vehicles, a car up on
## a display ramp at the corner; pennant strings strung from the light poles to the roof, feather
## flags along the frontage, inflatable tube men dancing at the corners (tube_man.gdshader), brand
## flags on three poles, and a tall brand pylon at the kerb, its lightbox lit after dark. A USED
## LOT is an asphalt lot packed tighter, a white office trailer on blocks at the back, a hand-
## painted board on posts, criss-crossed pennant strings, grease-pencil prices on the glass and a
## chain-link fence round the rest.
##
## WHERE is worked out, never placed: an avenue-wide road is an auto row by a hash of the seed and
## the road (ROW_ODDS); along it, every RUN blocks a hash says whether that stretch has dealers
## (RUN_ODDS), and each block on either side of the stretch in a dealer district is one by a third
## hash (BLOCK_ODDS). The block gives up a run of its edge lots along that road - one row deep, or
## two where the first is shallow and the second has no pocket garden - MIN_FRONT .. MAX_FRONT of
## frontage, clear of the freeways, the fire station's block and every landmark. Hashes of seed +
## road + block only, never a chunk's, block's or Building's rng: CityChunk._build_lot() asks
## claims() after the pad roll (like FireStation), so no lot, roll or prop elsewhere moves.
##
## Brands and lots are this game's own (VELMARA, QUENTIS, ...; LUCKY STAR AUTO, ...) with simple
## geometric marks (dealer_sign.gdshader): never a real maker, dealer or logo.

const DISTRICTS := [CityPlan.District.MIDTOWN, CityPlan.District.SUBURBS]
## Share of avenue-wide roads that are auto rows somewhere along their length.
const ROW_ODDS := 0.32
## Blocks per stretch of an auto row, and the share of stretches that have dealers.
const RUN := 6
const RUN_ODDS := 0.5
## Share of a dealer stretch's blocks (each side) that hold one.
const BLOCK_ODDS := 0.8
const USED_SHARE := 0.38
## Frontage (m) a site takes, and its depth.
const MIN_FRONT := 30.0
const MAX_FRONT := 74.0
const MIN_DEPTH := 18.0
const MAX_DEPTH := 48.0
const ROW_TWO_BELOW := 27.0

## Invented brands: name, mark (dealer_sign.gdshader), colour (sRGB).
const BRANDS := [
	["VELMARA", 0, Color(0.72, 0.05, 0.06)],
	["QUENTIS", 1, Color(0.05, 0.22, 0.62)],
	["HALDRIC", 2, Color(0.06, 0.32, 0.20)],
	["ORIVO", 3, Color(0.93, 0.42, 0.04)],
	["SUNDALE", 4, Color(0.10, 0.10, 0.11)],
	["BRAVENT", 5, Color(0.02, 0.45, 0.47)],
]
## Body types a brand's lot carries (the generated road bodies).
const LINEUP := [Vehicle.BodyType.SEDAN, Vehicle.BodyType.CROSSOVER, Vehicle.BodyType.CROSSOVER, Vehicle.BodyType.PICKUP, Vehicle.BodyType.SEDAN]
## Showroom paints: what a new-car lot looks like (white, black, silvers, a few colours), sRGB.
const NEW_PAINTS := [Color(0.92, 0.92, 0.91), Color(0.92, 0.92, 0.91), Color(0.06, 0.06, 0.07), Color(0.62, 0.63, 0.65),
	Color(0.40, 0.41, 0.43), Color(0.72, 0.04, 0.05), Color(0.08, 0.30, 0.75), Color(0.24, 0.25, 0.27), Color(0.88, 0.89, 0.92)]
const USED_PAINTS := [Color(0.85, 0.85, 0.83), Color(0.08, 0.08, 0.09), Color(0.55, 0.56, 0.58), Color(0.36, 0.08, 0.08),
	Color(0.12, 0.17, 0.32), Color(0.52, 0.47, 0.40), Color(0.30, 0.32, 0.36), Color(0.14, 0.24, 0.17), Color(0.75, 0.56, 0.10),
	Color(0.60, 0.60, 0.58), Color(0.25, 0.10, 0.06)]
const USED_NAMES := ["LUCKY STAR AUTO", "BOULEVARD MOTORS", "ACE AUTO MART", "VALLEY VIEW MOTORS", "DOS AMIGOS AUTO SALES",
	"BEST DEAL AUTOS", "GOLDEN ROAD CARS", "SUNSET CAR CORRAL", "BIG JOE'S AUTO", "PRIMO MOTORS"]
const USED_LINES := ["WE FINANCE", "BAD CREDIT OK", "EASY TERMS", "CASH FOR CARS", "TRADE-INS WELCOME", "NO CREDIT CHECK"]
## Pennant colours (sRGB): a new lot strings its brand colour and white, a used lot everything.
const PENNANT_RAINBOW := [Color(0.85, 0.08, 0.06), Color(0.98, 0.82, 0.06), Color(0.06, 0.32, 0.85), Color(0.08, 0.62, 0.22), Color(0.96, 0.96, 0.95), Color(0.95, 0.45, 0.05)]
const TUBE_COLORS := [Color(0.95, 0.15, 0.08), Color(0.08, 0.45, 0.95), Color(0.98, 0.85, 0.08), Color(0.1, 0.8, 0.25), Color(0.98, 0.45, 0.05), Color(0.85, 0.1, 0.65)]

## Showroom and building heights (m).
const SHOWROOM_H := 6.4
const SERVICE_H := 5.2
const PYLON_H := 10.5
const STALL_W := 2.75
const ROW_PITCH := 5.9
## The static lot cars' bodies (ArenaGrounds.car_mesh(): 0 saloon, 1 pickup, 2 SUV, 3 coupe) and
## the matching size of their collision box.
const CAR_BOX := [Vector3(1.86, 1.45, 4.7), Vector3(1.98, 1.7, 5.4), Vector3(1.98, 1.95, 4.9), Vector3(1.9, 1.3, 4.45)]
## Real Vehicles a dealer puts on its floor and in its front row (they cost a car build each).
const SHOWROOM_CARS := 2
const FRONT_CARS := 4
const USED_REAL_CARS := 3
const CAR_SHADOW_DISTANCE := 70.0
const TUBE_DRAW_DISTANCE := 320.0

## Off (CAR_DEALERS=0 in the environment): no dealers anywhere, the lots keep what they had (the A/B).
static var enabled: bool = OS.get_environment("CAR_DEALERS") != "0"
static var _cache: Dictionary = {}
static var _mats: Dictionary = {}


static func _h01(parts: Array) -> float:
	return float(absi(hash(parts)) % 100003) / 100003.0


# --- Where --------------------------------------------------------------------------------------

## True when road (axis, index) is an auto row and the stretch of it holding block index `along`
## (the block's index along the road) has dealers.
static func is_row(plan: CityPlan, axis: int, index: int, along: int) -> bool:
	if plan.road_width(axis, index) < plan.avenue_width - 0.1:
		return false
	if _h01([plan.seed, axis, index, "auto_row"]) >= ROW_ODDS:
		return false
	return _h01([plan.seed, axis, index, floori(float(along) / float(RUN)), "auto_run"]) < RUN_ODDS


## The dealership of block (bx, bz): {} or {"block", "side" (Industrial.lot_side's numbering: 0 -z,
## 1 +z, 2 -x, 3 +x), "road" [axis, index], "rect" (the site, true world XZ), "frame"
## (Industrial.frame()), "lots" (the claimed lots' seeds), "anchor" (the seed of the lot that builds
## it), "used", "brand" (index into BRANDS), "name", "id"}. Cached per plan and block.
static func site(plan: CityPlan, bx: int, bz: int) -> Dictionary:
	var key := Vector3i(plan.seed, bx, bz)
	if _cache.has(key):
		return _cache[key]
	var out := {}
	_cache[key] = out
	if not enabled or plan.macro == null:
		return out
	var b := plan.block(bx, bz)
	if int(b.kind) != CityPlan.BlockKind.BUILDINGS or b.has("site") or b.has("grounds"):
		return out
	if not DISTRICTS.has(int(b.district)):
		return out
	var rect: Rect2 = b.rect
	if plan.zone_at(rect.get_center()) != MacroMap.Zone.CITY or plan.river_block(bx, bz) or Landmarks.claims(rect):
		return out
	if DowntownReal.in_extent(rect.get_center()):
		return out
	if plan.macro.replica and plan.macro.replica.block_lots(plan, bx, bz) != null:
		return out
	var fs := FireStation.for_cell(plan, FireStation._cell_of(rect.get_center()))
	if not fs.is_empty() and fs.block == Vector2i(bx, bz):
		return out
	for side in 4:
		var road: Array = [[CityPlan.AXIS_Z, bz], [CityPlan.AXIS_Z, bz + 1], [CityPlan.AXIS_X, bx], [CityPlan.AXIS_X, bx + 1]][side]
		var along := bx if int(road[0]) == CityPlan.AXIS_Z else bz
		if not is_row(plan, int(road[0]), int(road[1]), along):
			continue
		if _h01([plan.seed, bx, bz, side, "dealer"]) >= BLOCK_ODDS:
			continue
		var s := _fit(plan, bx, bz, rect, side)
		if s.is_empty():
			continue
		var used := _h01([plan.seed, bx, bz, "dealer_used"]) < USED_SHARE
		var id := absi(hash([plan.seed, bx, bz, "dealer_id"]))
		s.merge({"block": Vector2i(bx, bz), "side": side, "road": road, "used": used,
			"brand": id % BRANDS.size(), "id": id,
			"name": USED_NAMES[(id >> 4) % USED_NAMES.size()] if used else String(BRANDS[id % BRANDS.size()][0])})
		out.merge(s)
		break
	return out


## The run of lots along `side` of the block that makes the site: {"rect", "frame", "lots",
## "anchor"} or {}.
static func _fit(plan: CityPlan, bx: int, bz: int, rect: Rect2, side: int) -> Dictionary:
	var inner := rect.grow(-plan.sidewalk_width)
	var lots := plan.lots(bx, bz)
	var row: Array = [] # [u0, u1, lot] along the side
	for lot: Dictionary in lots:
		if lot.yard:
			continue
		var c: Rect2 = lot.get("cell", Rect2((lot.center as Vector2) - (lot.size as Vector2) * 0.5, lot.size))
		var on: bool = [absf(c.position.y - inner.position.y) < 0.6, absf(c.end.y - inner.end.y) < 0.6,
			absf(c.position.x - inner.position.x) < 0.6, absf(c.end.x - inner.end.x) < 0.6][side]
		if not on:
			continue
		var u0 := c.position.x if side < 2 else c.position.y
		var u1 := c.end.x if side < 2 else c.end.y
		row.append([u0, u1, lot, c])
	if row.size() < 2:
		return {}
	row.sort_custom(func(p: Array, q: Array) -> bool: return float(p[0]) < float(q[0]))
	# Windows of contiguous cells; start at a hashed offset so a row of dealers do not all sit at
	# the same end of their blocks.
	var start := absi(hash([plan.seed, bx, bz, "dealer_start"])) % row.size()
	var best: Array = []
	for k in row.size():
		var i0 := (start + k) % row.size()
		var win: Array = [row[i0]]
		var j := i0 + 1
		while j < row.size() and absf(float(row[j][0]) - float(win.back()[1])) < 0.6 and float(row[j][1]) - float(win[0][0]) <= MAX_FRONT:
			win.append(row[j])
			j += 1
		if float(win.back()[1]) - float(win[0][0]) >= MIN_FRONT:
			best = win
			break
	if best.is_empty():
		return {}
	var site_rect: Rect2 = best[0][3]
	var claimed: Array = []
	for w: Array in best:
		site_rect = site_rect.merge(w[3])
		claimed.append(int((w[2] as Dictionary).seed))
	var depth := site_rect.size.y if side < 2 else site_rect.size.x
	if depth < ROW_TWO_BELOW:
		# A second row of cells inward, when every one of them is a lot and none a pocket garden.
		var second: Array = []
		for w: Array in best:
			var c: Rect2 = w[3]
			var want := c
			match side:
				0: want = Rect2(c.position + Vector2(0.0, c.size.y), c.size)
				1: want = Rect2(c.position - Vector2(0.0, c.size.y), c.size)
				2: want = Rect2(c.position + Vector2(c.size.x, 0.0), c.size)
				_: want = Rect2(c.position - Vector2(c.size.x, 0.0), c.size)
			var found: Dictionary = {}
			for lot: Dictionary in lots:
				var lc: Rect2 = lot.get("cell", Rect2())
				if lc.get_center().distance_to(want.get_center()) < 0.8:
					found = lot
			if found.is_empty() or found.yard:
				second.clear()
				break
			second.append(found)
		if not second.is_empty():
			var grown := site_rect
			for lot: Dictionary in second:
				grown = grown.merge(lot.cell)
			var d2 := grown.size.y if side < 2 else grown.size.x
			if d2 <= MAX_DEPTH:
				site_rect = grown
				depth = d2
				for lot: Dictionary in second:
					claimed.append(int(lot.seed))
	if depth < MIN_DEPTH:
		return {}
	if plan.macro.freeway and plan.macro.freeway.blocks_rect(site_rect.grow(6.0), 3.0):
		return {}
	var anchor := -1
	for lot: Dictionary in lots:
		if claimed.has(int(lot.seed)):
			anchor = int(lot.seed)
			break
	return {"rect": site_rect, "frame": Industrial.frame(site_rect, side), "lots": claimed, "anchor": anchor}


static func _block_site(plan: CityPlan, bx: int, bz: int) -> Dictionary:
	return site(plan, bx, bz)


## True when `lot` of block (bx, bz) is a dealer's (CityChunk._build_lot asks, after its rolls).
static func claims(plan: CityPlan, bx: int, bz: int, lot: Dictionary) -> bool:
	var s := site(plan, bx, bz)
	return not s.is_empty() and (s.lots as Array).has(int(lot.seed))


## True when `p` (true world XZ) is inside the dealer site of block (bx, bz): the empty cells the
## lot grid left are not given houses there (CityChunk._lot_steps, HouseKit.extra_lots()).
static func covers(plan: CityPlan, bx: int, bz: int, p: Vector2) -> bool:
	var s := site(plan, bx, bz)
	return not s.is_empty() and (s.rect as Rect2).grow(0.5).has_point(p)


# --- Layout -------------------------------------------------------------------------------------

## The site's frame as a transform: local x along the street, +z out toward it, y up from the
## pavement top; the origin at the middle of the site's street edge. `y` is the origin's height.
static func frame_xf(s: Dictionary, y: float) -> Transform3D:
	var f: Dictionary = s.frame
	var n2: Vector2 = f.n
	var a2: Vector2 = f.a
	var front2: Vector2 = (f.o as Vector2) + a2 * (float(f.len) * 0.5)
	var outward := Vector3(-n2.x, 0.0, -n2.y)
	var x_axis := Vector3.UP.cross(outward)
	return Transform3D(Basis(x_axis, Vector3.UP, outward), Vector3(front2.x, y, front2.y))


## Everything a dealership places, in its local frame (pure: the same answer at any level). Keys:
## "W", "D" (site frontage and depth), "showroom" / "service" / "trailer" (Rect2 in local x, z),
## "cars" ([x, z, yaw, kind ("static" | "real" | "ramp"), body v, paint, seed]), "real_floor"
## (showroom cars [x, z, yaw]), "poles" ([x, z]), "tubes" ([x, z, colour, phase]), "flags"
## ([x, z]), "feathers" ([x, z]), "pylon" ([x, z] or empty), "drive" (x of the driveway),
## "strings" ([Vector3, Vector3]), "sign" ([x, z]), "fence" (sides to fence: true for used).
static func layout(s: Dictionary) -> Dictionary:
	var f: Dictionary = s.frame
	var W: float = f.len
	var D: float = f.depth
	var id: int = s.id
	var used: bool = s.used
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([id, "dealer_layout"])
	var L := {"W": W, "D": D, "cars": [], "real_floor": [], "poles": [], "tubes": [], "flags": [], "feathers": [],
		"pylon": [], "strings": [], "sign": [], "showroom": Rect2(), "service": Rect2(), "trailer": Rect2(), "drive": 0.0}
	var e := 1.0 if rng.randf() < 0.5 else -1.0 # which end the building stands at
	var hw := W * 0.5
	var blocked: Array[Rect2] = []
	var back := -D + 0.8
	if not used:
		var sw := clampf(W * 0.48, 16.0, 30.0)
		var sd := clampf(D * 0.42, 11.0, 17.0)
		if D - sd < 11.0:
			sd = maxf(D - 11.0, 9.0)
		var sx := e * (hw - sw * 0.5 - 1.0)
		L.showroom = Rect2(sx - sw * 0.5, back, sw, sd)
		blocked.append(Rect2(sx - sw * 0.5 - 0.6, back, sw + 1.2, sd + 4.5)) # the portal and the aisle in front
		var free := W - sw - 2.0
		if free > 28.0:
			var svw := 12.0
			var vx := sx - e * (sw * 0.5 + 0.4 + svw * 0.5)
			L.service = Rect2(vx - svw * 0.5, back, svw, sd - 1.0)
			# Its canopy, and the drive out to the street in front of it.
			blocked.append(Rect2(vx - svw * 0.5 - 0.5, back, svw + 1.0, sd + 6.0))
			L.drive = vx
		else:
			L.drive = sx - e * (sw * 0.5 + 4.5)
		# The showroom floor's cars.
		var nfloor := SHOWROOM_CARS
		for i in nfloor:
			var fx := sx - sw * 0.5 + sw * (float(i) + 0.5) / float(nfloor)
			var fz := back + sd * (0.42 + 0.1 * float(i % 2))
			L.real_floor.append([fx, fz, rng.randf_range(-0.6, 0.6) + PI * 0.15 * e])
		L.pylon = [e * (hw - 1.6), -1.4]
		L.flags = [[-e * (hw - 1.2), -1.0], [-e * (hw - 3.0), -1.6], [-e * (hw - 4.8), -1.0]]
	else:
		var tl := clampf(W * 0.28, 8.5, 12.0)
		var tx := e * (hw - tl * 0.5 - 1.5)
		L.trailer = Rect2(tx - tl * 0.5, back + 0.6, tl, 3.6)
		blocked.append(Rect2(tx - tl * 0.5 - 1.0, back, tl + 2.0, 7.5))
		L.drive = -e * (hw - 4.5)
		L.sign = [e * (hw - 2.2), -1.0]
	blocked.append(Rect2(L.drive - 3.6, -D, 7.2, D + 1.0))
	# Rows of cars: nose out to the street (local +z), the front row 1.2 m in from the property
	# line, rows ROW_PITCH apart back to the building or the back of the lot.
	var pitch := STALL_W if not used else 2.55
	var row_pitch := ROW_PITCH if not used else 5.6
	var z := -1.2 - 2.4
	var row_i := 0
	var paints: Array = USED_PAINTS if used else NEW_PAINTS
	var front_real := 0
	var real_cap := USED_REAL_CARS if used else FRONT_CARS
	while z - 2.4 > back:
		var n := int((W - 3.0) / pitch)
		var x0 := -float(n) * pitch * 0.5 + pitch * 0.5
		# The front row's real cars stand mid-frontage, away from the drive.
		var centre := n >> 1
		for i in n:
			var x := x0 + float(i) * pitch
			var car_r := Rect2(x - 1.0, z - 2.4, 2.0, 4.8)
			var hit := false
			for br: Rect2 in blocked:
				if br.intersects(car_r):
					hit = true
					break
			if hit:
				continue
			var v := rng.randi() % 4
			if not used and v == 3 and rng.randf() < 0.5:
				v = 0
			var paint: Color = paints[rng.randi() % paints.size()]
			var yaw_j := rng.randf_range(-0.02, 0.02)
			var seed_c := rng.randi()
			var kind := "static"
			if row_i == 0 and front_real < real_cap and absi(i - centre) <= real_cap:
				kind = "real"
				front_real += 1
			# A used lot leaves a gap now and then (sold).
			if used and kind == "static" and rng.randf() < 0.08:
				continue
			L.cars.append([x, z, yaw_j, kind, v, paint, seed_c])
		z -= row_pitch
		row_i += 1
	# A car up on a ramp at the front corner opposite the drive (new lots).
	if not used:
		var rx := -e * (hw - 6.5)
		var ramp_r := Rect2(rx - 1.2, -5.0, 2.4, 4.8)
		var clear := true
		for c: Array in L.cars:
			if Rect2(float(c[0]) - 1.0, float(c[1]) - 2.4, 2.0, 4.8).intersects(ramp_r):
				# The ramp car replaces the one standing there.
				c[3] = "ramp"
				clear = false
				break
		if clear:
			pass
	# Light poles: along the front between the cars and the walk, and down the middle.
	var npole := maxi(2, int(W / 19.0) + 1)
	for i in npole:
		var px := -hw + 1.0 + (W - 2.0) * float(i) / float(npole - 1)
		if absf(px - float(L.drive)) < 4.0:
			px += 4.5 * (1.0 if px <= float(L.drive) else -1.0)
		L.poles.append([px, -0.6])
	var mid_z := -D * 0.55
	if D > 26.0 and not used:
		for i in maxi(1, int(W / 26.0)):
			var px := -hw + W * (float(i) + 0.5) / float(maxi(1, int(W / 26.0)))
			var inside := false
			for br: Rect2 in blocked:
				if br.has_point(Vector2(px, mid_z)):
					inside = true
			if not inside:
				L.poles.append([px, mid_z])
	# Pennant strings: pole to pole along the front at the poles' tops, and from each front pole up
	# to the roof (new) or criss-crossed to a mast in the middle (used).
	var top := 6.2
	var front_poles: Array = (L.poles as Array).filter(func(p: Array) -> bool: return float(p[1]) > -1.0)
	front_poles.sort_custom(func(p: Array, q: Array) -> bool: return float(p[0]) < float(q[0]))
	for i in front_poles.size() - 1:
		L.strings.append([Vector3(float(front_poles[i][0]), top, -0.6), Vector3(float(front_poles[i + 1][0]), top, -0.6)])
	if not used:
		var sr: Rect2 = L.showroom
		var roof_y := SHOWROOM_H + 0.4
		for p: Array in front_poles:
			var tx := clampf(float(p[0]), sr.position.x + 0.5, sr.end.x - 0.5)
			L.strings.append([Vector3(float(p[0]), top, -0.6), Vector3(tx, roof_y, sr.end.y + 1.0)])
	else:
		var mast := Vector3(0.0, 7.0, -D * 0.5)
		L.mast = [mast.x, mast.z]
		for p: Array in front_poles:
			L.strings.append([Vector3(float(p[0]), top, -0.6), mast])
		for c: Vector2 in [Vector2(-hw + 0.6, -D + 0.6), Vector2(hw - 0.6, -D + 0.6)]:
			L.strings.append([Vector3(c.x, 4.5, c.y), mast])
			L.poles_wood = (L.get("poles_wood", []) as Array) + [[c.x, c.y]]
	# Tube men: the two front corners and by the drive.
	var spots: Array = [[-hw + 1.4, -1.0], [hw - 1.4, -1.0]]
	if not used:
		spots[1 if e > 0.0 else 0] = [L.drive + e * 4.4, -1.0]
	else:
		spots = [[L.drive - e * 4.0, -1.0]]
		if W > 44.0:
			spots.append([0.0, -1.0])
	for i in spots.size():
		var col: Color = TUBE_COLORS[(id + i * 3) % TUBE_COLORS.size()]
		L.tubes.append([float(spots[i][0]), float(spots[i][1]), col, _h01([id, i, "tube"])])
	# Feather flags along the frontage between the poles (new lots).
	if not used:
		var nf := maxi(2, int(W / 9.0))
		for i in nf:
			var fx := -hw + W * (float(i) + 0.5) / float(nf)
			var near := absf(fx - float(L.drive)) < 4.5 or absf(fx - float(L.pylon[0])) < 2.5
			for p: Array in front_poles:
				near = near or absf(fx - float(p[0])) < 1.2
			if not near:
				L.feathers.append([fx, -0.8])
	return L


# --- Building it --------------------------------------------------------------------------------

## Builds the dealership on its site in chunk `ch` when `lot` is its anchor; the site's other lots
## build nothing. Called from CityChunk._build_lot in place of a Building.
static func build_lot(ch: CityChunk, lot: Dictionary) -> void:
	var s := site(ch.plan, ch.ix, ch.iz)
	if s.is_empty() or int(lot.seed) != int(s.anchor):
		return
	var r: Rect2 = s.rect
	ch._lot_rects.append(r.grow(0.3))
	LotFill._ground(ch, r, "asphalt")
	var L := layout(s)
	if ch.level != CityChunk.Level.FULL or ch.capturing:
		_far(ch, s, L)
		ch.building_count += 1
		return
	var jobs: Array[Callable] = [_build_detail.bind(ch, s, L)]
	for c: Array in L.cars:
		if c[3] == "real":
			jobs.append(_real_car.bind(ch, s, Vector3(float(c[0]), 0.0, float(c[1])), float(c[2]), int(c[6]), bool(s.used)))
	for c: Array in L.real_floor:
		jobs.append(_real_car.bind(ch, s, Vector3(float(c[0]), 0.2, float(c[1])), float(c[2]), absi(hash([s.id, c[0]])), false))
	var next := [0]
	ch._run_or_defer(func() -> bool:
		if next[0] < jobs.size():
			jobs[next[0]].call()
			next[0] += 1
		return next[0] >= jobs.size())
	ch.building_count += 1


## World XZ of local (x, z).
static func _w2(xf: Transform3D, x: float, z: float) -> Vector2:
	var p := xf * Vector3(x, 0.0, z)
	return Vector2(p.x, p.z)


## LOD chunks and the far city: the buildings and the pylon as boxes (old path: plain coloured
## roof-plant boxes, the showroom as glazing, the pylon as a lit sign face). The same boxes at both
## (the far city IS the LOD chunk's capture, box for box); the cars are left to the FULL ring.
static func _far(ch: CityChunk, s: Dictionary, L: Dictionary) -> void:
	var xf := frame_xf(s, CityChunk.SIDEWALK_TOP)
	var seedf := float(int(s.id) % 997) / 997.0
	var brand: Color = BRANDS[int(s.brand)][2]
	var boxes: Array = [] # [local centre, size, colour, custom, collide]
	if not s.used:
		var sr: Rect2 = L.showroom
		var c := sr.get_center()
		boxes.append([Vector3(c.x, SHOWROOM_H * 0.5, c.y), Vector3(sr.size.x, SHOWROOM_H, sr.size.y), Color(0.22, 0.27, 0.31), Color(3.0, 0.0, seedf, 4.0), true])
		boxes.append([Vector3(c.x, SHOWROOM_H + 0.3, c.y + 0.6), Vector3(sr.size.x + 2.4, 0.6, sr.size.y + 1.2), Color(0.9, 0.9, 0.88), Color(0.0, 0.0, seedf, 4.0), false])
		boxes.append([Vector3(c.x, SHOWROOM_H + 1.2, sr.end.y + 1.2), Vector3(7.0, 2.2, 3.4), brand, Color(0.0, 0.0, seedf, 4.0), false])
		var vr: Rect2 = L.service
		if vr.size.x > 0.0:
			var vc := vr.get_center()
			boxes.append([Vector3(vc.x, SERVICE_H * 0.5, vc.y), Vector3(vr.size.x, SERVICE_H, vr.size.y), Color(0.78, 0.79, 0.8), Color(0.0, 0.0, seedf, 4.0), true])
		var py: Array = L.pylon
		boxes.append([Vector3(float(py[0]), PYLON_H * 0.5, float(py[1])), Vector3(0.7, PYLON_H, 2.8), brand, Color(4.0, 0.0, 1.0, 4.0), false])
	else:
		var tr: Rect2 = L.trailer
		var tc := tr.get_center()
		boxes.append([Vector3(tc.x, 1.9, tc.y), Vector3(tr.size.x, 2.8, tr.size.y), Color(0.86, 0.86, 0.83), Color(0.0, 0.0, seedf, 4.0), true])
	for b: Array in boxes:
		var lc: Vector3 = b[0]
		var size: Vector3 = b[1]
		var wc := xf * lc
		ch._batch.add("lod_box", PropFactory.unit_box(), Transform3D(xf.basis * Basis.from_scale(size), wc), b[2], b[3])
		if b[4]:
			var wsize := size if absf(xf.basis.x.x) > 0.5 else Vector3(size.z, size.y, size.x)
			ch._add_lod_shape(wsize, wc + Vector3(0.0, ch._gy(wc.x, wc.z), 0.0))


## Everything a FULL chunk draws of a dealership: one node in the site's frame holding the
## buildings, signs and cloth as a few merged meshes; the lot cars, stickers, tube men and light
## poles in the chunk's batches; collision on the chunk's StreetProps body.
static func _build_detail(ch: CityChunk, s: Dictionary, L: Dictionary) -> void:
	var r: Rect2 = s.rect
	var c2 := r.get_center()
	var g := ch._gy(c2.x, c2.y)
	var xf0 := frame_xf(s, CityChunk.SIDEWALK_TOP) # no relief: the batch adds it
	var xf := frame_xf(s, CityChunk.SIDEWALK_TOP + g)
	var node := Node3D.new()
	node.name = "Dealer_%s" % String(s.name).replace(" ", "_").replace("'", "")
	node.transform = xf
	node.add_to_group("car_dealer")
	ch.add_child(node)
	var geo := Geo.new()
	var brand_i: int = s.brand
	var brand: Color = BRANDS[brand_i][2]
	var lift := LotFill.ASPHALT_LIFT
	if not s.used:
		_showroom(ch, node, geo, s, L, xf, g)
		if (L.service as Rect2).size.x > 0.0:
			_service(ch, node, geo, s, L, xf, g)
		_pylon(ch, node, geo, s, L, xf, g)
		for fl: Array in L.flags:
			geo.box("pole", Vector3(float(fl[0]), 4.0, float(fl[1])), Vector3(0.1, 8.0, 0.1))
			geo.box("concrete", Vector3(float(fl[0]), 0.15, float(fl[1])), Vector3(0.5, 0.3, 0.5))
		for ff: Array in L.feathers:
			geo.box("pole", Vector3(float(ff[0]), 1.7, float(ff[1])), Vector3(0.04, 3.4, 0.04))
			geo.box("concrete", Vector3(float(ff[0]), 0.08, float(ff[1])), Vector3(0.35, 0.16, 0.35))
		# The display ramp at the corner.
		for c: Array in L.cars:
			if c[3] == "ramp":
				geo.ramp_block("concrete", Vector3(float(c[0]), lift, float(c[1])), 2.3, 4.8, 0.85)
	else:
		_trailer(ch, node, geo, s, L, xf, g)
		_used_sign(ch, node, geo, s, L)
		var mast: Array = L.get("mast", [])
		if not mast.is_empty():
			geo.box("pole", Vector3(float(mast[0]), 3.6, float(mast[1])), Vector3(0.12, 7.2, 0.12))
		for p: Array in L.get("poles_wood", []):
			geo.box("wood", Vector3(float(p[0]), 2.3, float(p[1])), Vector3(0.18, 4.6, 0.18))
		# Chain-link on the lot's inner sides (LotFill's fence), the street side open.
		_fence_sides(ch, s)
	# Low steel bollards along the street edge (concrete-filled pipe, painted, a domed cap) with a
	# gap for the drive: one batch a chunk.
	var hw := float(L.W) * 0.5
	var bx := -hw + 0.8
	var bollard := PropFactory.cylinder("dl_bollard_y" if s.used else "dl_bollard_w", 0.08, 0.78, Color(0.93, 0.93, 0.9) if not s.used else Color(0.95, 0.78, 0.1), -1.0, 12)
	while bx < hw - 0.5:
		if absf(bx - float(L.drive)) > 3.8 and not (not s.used and absf(bx - float((L.pylon as Array)[0])) < 1.6):
			ch._batch.add("dl_bollard_%d" % (1 if s.used else 0), bollard, Transform3D(Basis(), xf0 * Vector3(bx, lift + 0.39, -0.25)))
		bx += 2.6
	var mi := MeshInstance3D.new()
	mi.name = "Dealer"
	mi.mesh = geo.commit()
	node.add_child(mi)
	# The cloth: pennant strings, flags, feather flags.
	var cloth := _cloth_mesh(s, L)
	if cloth != null:
		var ci := MeshInstance3D.new()
		ci.name = "Cloth"
		ci.mesh = cloth
		ci.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ci.visibility_range_end = 260.0
		node.add_child(ci)
	# Light poles in the street lamps' batch (no OmniLight: the pools carry the night).
	for p: Array in L.poles:
		var w := xf0 * Vector3(float(p[0]), lift, float(p[1]))
		LotFill._lamp(ch, w)
		var pool_c := xf0 * Vector3(float(p[0]), lift, float(p[1]) - 6.0)
		ch._batch.add("dl_pool", PropFactory.light_pool(Color(0.92, 0.96, 1.0), 1.5), Transform3D(Basis(Vector3.RIGHT, -PI * 0.5).scaled(Vector3(18.0, 1.0, 18.0)), pool_c + Vector3(0.0, 0.06, 0.0)))
	ch._batch.set_no_shadow("dl_pool")
	# The floodlights: two LED floods over the lot (with the street lamps: DayNight, Quality).
	var nf := 2 if float(L.W) > 36.0 else 1
	for i in nf:
		var fx := -float(L.W) * 0.5 + float(L.W) * (float(i) + 0.5) / float(nf)
		var flood := OmniLight3D.new()
		flood.position = xf * Vector3(fx, 7.5, -float(L.D) * 0.38)
		flood.omni_range = 24.0
		flood.omni_attenuation = 1.1
		flood.light_color = Color(0.92, 0.96, 1.0)
		flood.light_energy = 0.0
		flood.shadow_enabled = false
		flood.distance_fade_enabled = true
		flood.distance_fade_begin = 110.0
		flood.distance_fade_length = 30.0
		flood.add_to_group("lamp_light")
		ch.add_child(flood)
	# Tube men on their fans.
	for t: Array in L.tubes:
		var w := xf0 * Vector3(float(t[0]), lift, float(t[1]))
		var basis := xf0.basis * Basis(Vector3.UP, (float(t[3]) - 0.5) * 0.8)
		ch._batch.add("dl_tube", tube_man_mesh(), Transform3D(basis, w + Vector3(0.0, 0.55, 0.0)), t[2], Color(float(t[3]), _h01([t[3], "tempo"]), float(int(t[3] * 10.0) % 2), 0.0))
		geo_fan(ch, xf0 * Vector3(float(t[0]), lift, float(t[1])))
	ch._batch.set_draw_distance("dl_tube", TUBE_DRAW_DISTANCE)
	# The static lot cars, their window stickers, a breakable-proof prop each (rounds spark off
	# the metal; it never breaks: they are scenery that stands up to the gunfire).
	for c: Array in L.cars:
		if c[3] == "real":
			continue
		_static_car(ch, s, xf0, c)
	for key: String in ["dl_car_0", "dl_car_1", "dl_car_2", "dl_car_3"]:
		ch._batch.set_shadow_distance(key, CAR_SHADOW_DISTANCE)
	ch._batch.set_no_shadow("dl_sticker")
	ch._batch.set_draw_distance("dl_sticker", 90.0)


static func geo_fan(ch: CityChunk, at: Vector3) -> void:
	ch._batch.add("dl_fan", fan_mesh(), Transform3D(Basis(), at))


static func _static_car(ch: CityChunk, s: Dictionary, xf0: Transform3D, c: Array) -> void:
	var v := int(c[4])
	var ramp: bool = c[3] == "ramp"
	var local_basis := Basis(Vector3.UP, PI + float(c[2])) # car_mesh's nose is -Z; the noses face the street (+z)
	var lp := Vector3(float(c[0]), LotFill.ASPHALT_LIFT + 0.005, float(c[1]))
	if ramp:
		# Nose up on the ramp, front wheels on its top.
		local_basis = local_basis * Basis(Vector3.RIGHT, -0.17)
		lp.y += 0.42
	var bxf := xf0.basis * local_basis
	var w := xf0 * lp
	var mesh := ArenaGrounds.car_mesh(v)
	var key := "dl_car_%d" % v
	var paint: Color = c[5]
	var sticker := sticker_xform(v, bool(s.used))
	var sxf := Transform3D(bxf, w) * sticker
	var custom := Color(_h01([c[6], "price"]), 1.0 if s.used else 0.0, _h01([s.id, "band"]), 0.0)
	var box: Vector3 = CAR_BOX[v]
	var yaw := atan2(bxf.z.x, bxf.z.z)
	var before := ch.prop_records.size()
	ch._add_prop("dealer_car", w, paint, [
		[key, mesh, Transform3D(bxf, w), paint],
		["dl_sticker", sticker_mesh(), sxf, Color.WHITE, custom],
	], [[box, w + Vector3(0.0, box.y * 0.5 + 0.05, 0.0), yaw]])
	if ch.prop_records.size() > before:
		ch.prop_records.back().health = 1e12


## A real car for sale: a Vehicle, parked and asleep, with the chunk's parked cars (so it leaves
## with the chunk, can be shot, burnt and driven off).
static func _real_car(ch: CityChunk, s: Dictionary, local: Vector3, yaw_j: float, seed_value: int, used: bool) -> void:
	if not PhysicsBudget.can_spawn():
		return
	var type: Vehicle.BodyType = LINEUP[absi(hash([seed_value, "type"])) % LINEUP.size()]
	if not used and _h01([seed_value, "sport"]) < 0.12:
		type = Vehicle.BodyType.SPORTS
	var paints: Array = USED_PAINTS if used else NEW_PAINTS
	var paint: Color = paints[absi(hash([seed_value, "paint"])) % paints.size()]
	var car := Vehicle.new()
	car.setup(type, paint, Vehicle.Addon.NONE)
	var fin := Vehicle.Finish.METALLIC
	if not used and _h01([seed_value, "fin"]) < 0.3:
		fin = Vehicle.Finish.PEARL
	elif used:
		fin = Vehicle.Finish.GLOSS if _h01([seed_value, "fin"]) < 0.5 else Vehicle.Finish.METALLIC
	car.setup_look(fin, Vehicle.Livery.NONE, Vehicle._contrast_trim(paint))
	car.wheel_style = absi(hash([seed_value, 31])) % PropFactory.WHEEL_FACES.size()
	car.wheel_kit = absi(hash([seed_value, 33])) % PropFactory.WHEEL_KITS.size()
	var xf0 := frame_xf(s, CityChunk.SIDEWALK_TOP)
	var w := xf0 * (local + Vector3(0.0, LotFill.ASPHALT_LIFT, 0.0))
	var holder: Node = ch.get_parent() if ch.get_parent() else ch
	var spot := w + Vector3(0.0, 0.3 + ch._gy(w.x, w.z), 0.0)
	car.position = WorldState.to_local(spot) if holder != ch else spot
	# Nose out (Vehicle forward is -Z): toward the street, local +z.
	var out := xf0.basis.z
	car.rotation.y = atan2(-out.x, -out.z) + yaw_j
	car.set_meta("for_sale", true)
	car.name = "ForSale"
	holder.add_child(car)
	car.visible = ch.visible
	ch._cars.append(car)


## The showroom: floor, glass curtain walls on mullions, a solid back wall with the brand wall
## inside, the deep white roof, the portal in the brand's colour with its badge, the name on the
## fascia, ceiling lights, a reception desk; one warm light inside after dark.
static func _showroom(ch: CityChunk, node: Node3D, geo: Geo, s: Dictionary, L: Dictionary, xf: Transform3D, g: float) -> void:
	var sr: Rect2 = L.showroom
	var x0 := sr.position.x
	var x1 := sr.end.x
	var zb := sr.position.y
	var zf := sr.end.y
	var w := sr.size.x
	var d := sr.size.y
	var cx := (x0 + x1) * 0.5
	var H := SHOWROOM_H
	var brand_i: int = s.brand
	# Floor: a polished slab standing a step above the lot, out a metre under the portal.
	geo.box("floor", Vector3(cx, -0.2, (zb + zf + 1.2) * 0.5), Vector3(w + 0.4, 0.8, d + 1.2))
	# Back wall (solid), its brand wall inside and the badge on it.
	geo.box("white", Vector3(cx, H * 0.5, zb + 0.15), Vector3(w, H, 0.3))
	geo.box("brand%d" % brand_i, Vector3(cx, 2.6, zb + 0.32), Vector3(minf(w * 0.5, 9.0), 4.0, 0.04))
	geo.quad_uv("sign%d_w" % brand_i, Vector3(cx, 2.9, zb + 0.35), Vector3.RIGHT, Vector3.UP, 2.2, 2.2)
	# Glass: front and both sides, one pane each, mullions every 1.6 m outside it.
	var gt := 0.03
	geo.box("glass", Vector3(cx, H * 0.5 + 0.1, zf - 0.05), Vector3(w, H - 0.2, gt))
	for sx: float in [x0 + 0.05, x1 - 0.05]:
		geo.box("glass", Vector3(sx, H * 0.5 + 0.1, (zb + zf) * 0.5), Vector3(gt, H - 0.2, d - 0.3))
	var nm := maxi(2, int(w / 1.6))
	for i in nm + 1:
		var x := x0 + w * float(i) / float(nm)
		geo.box("mullion", Vector3(x, H * 0.5, zf - 0.02), Vector3(0.07, H, 0.16))
	var nd := maxi(2, int(d / 1.6))
	for i in nd + 1:
		var z := zb + d * float(i) / float(nd)
		for sx: float in [x0, x1]:
			geo.box("mullion", Vector3(sx, H * 0.5, z), Vector3(0.16, H, 0.07))
	# Transoms at door-head height and the base channel.
	geo.box("mullion", Vector3(cx, 2.7, zf - 0.02), Vector3(w, 0.08, 0.14))
	geo.box("mullion", Vector3(cx, 0.06, zf - 0.02), Vector3(w, 0.12, 0.16))
	# The roof: a deep white slab with an overhang, a dark soffit under it.
	geo.box("white", Vector3(cx, H + 0.3, (zb + zf) * 0.5 + 0.6), Vector3(w + 2.4, 0.6, d + 1.2 + 0.2))
	geo.box("soffit", Vector3(cx, H - 0.01, (zb + zf) * 0.5 + 0.6), Vector3(w + 2.3, 0.02, d + 1.1))
	# Ceiling lights inside.
	var nx := maxi(2, int(w / 3.0))
	var nz := maxi(2, int(d / 3.0))
	for i in nx:
		for k in nz:
			geo.box("ceiling_light", Vector3(x0 + w * (float(i) + 0.5) / float(nx), H - 0.04, zb + d * (float(k) + 0.5) / float(nz)), Vector3(1.2, 0.05, 0.6))
	# The portal: two blades and a lintel in the brand's colour framing the doors, standing out
	# over the walk, its soffit lit; the badge on the lintel and the name on the fascia beside it.
	var dx := cx
	var pw := 7.2
	var pd := 3.6
	var pz := zf - 0.6 + pd * 0.5
	for sx: float in [-1.0, 1.0]:
		geo.box("brand%d" % brand_i, Vector3(dx + sx * (pw * 0.5 - 0.4), (H + 2.4) * 0.5, pz), Vector3(0.8, H + 2.4, pd))
	geo.box("brand%d" % brand_i, Vector3(dx, H + 1.4, pz), Vector3(pw, 2.0, pd))
	geo.box("soffit_light", Vector3(dx, H + 0.39, pz + 0.2), Vector3(pw - 2.0, 0.02, pd - 0.8))
	geo.quad_uv("sign%d_b" % brand_i, Vector3(dx, H + 1.4, zf - 0.6 + pd + 0.012), Vector3.RIGHT, Vector3.UP, 1.7, 1.7)
	# The doors: a pair of sliding glass leaves in a dark frame.
	geo.box("mullion", Vector3(dx, 1.4, zf + 0.02), Vector3(2.8, 0.1, 0.1))
	geo.box("mullion", Vector3(dx, 2.75, zf + 0.02), Vector3(3.1, 0.16, 0.18))
	for sx: float in [-1.0, 1.0]:
		geo.box("mullion", Vector3(dx + sx * 1.5, 1.35, zf + 0.02), Vector3(0.1, 2.7, 0.16))
	# A reception desk and two lounge chairs.
	geo.box("white", Vector3(cx + w * 0.25, 0.55, zb + 2.0), Vector3(3.2, 1.1, 0.9))
	geo.box("brand%d" % brand_i, Vector3(cx + w * 0.25, 0.5, zb + 2.47), Vector3(3.2, 0.9, 0.04))
	for k in 2:
		geo.box("dark", Vector3(cx - w * 0.3 + float(k) * 1.2, 0.45, zb + 1.5), Vector3(0.8, 0.9, 0.8))
	# Name lettering on the roof fascia, beside the portal.
	if not OS.has_feature("web"):
		var name_x := dx + (pw * 0.5 + 0.5 + minf(w * 0.5 - pw * 0.5 - 1.0, 8.0) * 0.5) * (1.0 if cx < 0.0 else -1.0)
		var t := _text(String(s.name), 0.75, BRANDS[brand_i][2], 1.2)
		var ti := MeshInstance3D.new()
		ti.name = "Name"
		ti.mesh = t
		ti.position = Vector3(name_x, H + 0.3, zf + 1.22)
		ti.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ti.visibility_range_end = 220.0
		node.add_child(ti)
	# The lit interior after dark (DayNight drives the group; Quality turns it off at low levels).
	var light := OmniLight3D.new()
	light.position = Vector3(cx, H - 1.2, (zb + zf) * 0.5)
	light.omni_range = maxf(w, d) * 0.75
	light.omni_attenuation = 1.2
	light.light_color = Color(1.0, 0.95, 0.88)
	light.light_energy = 0.0
	light.shadow_enabled = false
	light.distance_fade_enabled = true
	light.distance_fade_begin = 90.0
	light.distance_fade_length = 30.0
	light.add_to_group("lamp_light")
	node.add_child(light)
	# Collision: the walls and the roof, the front left open at the doors.
	_shape_local(ch, xf, Vector3(cx, H * 0.5, zb + 0.15), Vector3(w, H, 0.3))
	for sx: float in [x0 + 0.1, x1 - 0.1]:
		_shape_local(ch, xf, Vector3(sx, H * 0.5, (zb + zf) * 0.5), Vector3(0.2, H, d))
	var lw := (dx - 1.5) - x0
	if lw > 0.2:
		_shape_local(ch, xf, Vector3(x0 + lw * 0.5, H * 0.5, zf - 0.05), Vector3(lw, H, 0.2))
	var rw := x1 - (dx + 1.5)
	if rw > 0.2:
		_shape_local(ch, xf, Vector3(x1 - rw * 0.5, H * 0.5, zf - 0.05), Vector3(rw, H, 0.2))
	_shape_local(ch, xf, Vector3(cx, H + 0.3, (zb + zf) * 0.5 + 0.6), Vector3(w + 2.4, 0.6, d + 1.4))
	for sx: float in [-1.0, 1.0]:
		_shape_local(ch, xf, Vector3(dx + sx * (pw * 0.5 - 0.4), (H + 2.4) * 0.5, pz), Vector3(0.8, H + 2.4, pd))


## The service drive-through: a panel box with two bays (one door up, one half up), the bays lit
## inside, a canopy on two columns over the drive with SERVICE on its fascia.
static func _service(ch: CityChunk, node: Node3D, geo: Geo, s: Dictionary, L: Dictionary, xf: Transform3D, g: float) -> void:
	var vr: Rect2 = L.service
	var x0 := vr.position.x
	var x1 := vr.end.x
	var zb := vr.position.y
	var zf := vr.end.y
	var w := vr.size.x
	var d := vr.size.y
	var cx := (x0 + x1) * 0.5
	var H := SERVICE_H
	var brand_i: int = s.brand
	geo.box("panel", Vector3(cx, H * 0.5, zb + 0.15), Vector3(w, H, 0.3))
	for sx: float in [x0 + 0.15, x1 - 0.15]:
		geo.box("panel", Vector3(sx, H * 0.5, (zb + zf) * 0.5), Vector3(0.3, H, d))
	geo.box("panel", Vector3(cx, H + 0.15, (zb + zf) * 0.5), Vector3(w, 0.3, d))
	# The front: piers either side of two 4.2 m bays and a header over them.
	var bay := 4.2
	var bays := [cx - 2.6, cx + 2.6]
	var edges := [x0, bays[0] - bay * 0.5, bays[0] + bay * 0.5, bays[1] - bay * 0.5, bays[1] + bay * 0.5, x1]
	for k in range(0, edges.size(), 2):
		var a: float = edges[k]
		var b: float = edges[k + 1]
		if b - a > 0.05:
			geo.box("panel", Vector3((a + b) * 0.5, H * 0.5, zf - 0.15), Vector3(b - a, H, 0.3))
	geo.box("panel", Vector3(cx, (4.3 + H) * 0.5, zf - 0.15), Vector3(w, H - 4.3, 0.3))
	# Inside: a dark floor and walls, lit strips, the doors rolled up into the header (one half down).
	geo.box("dark", Vector3(cx, 0.02, (zb + zf) * 0.5), Vector3(w - 0.6, 0.04, d - 0.6))
	geo.box("inner", Vector3(cx, H * 0.5, zb + 0.32), Vector3(w - 0.6, H - 0.2, 0.04))
	for bx: float in bays:
		geo.box("ceiling_light", Vector3(bx, 4.2, (zb + zf) * 0.5), Vector3(0.3, 0.05, d - 2.0))
	geo.box("door", Vector3(bays[1], 3.4, zf - 0.32), Vector3(bay, 1.8, 0.06))
	# The canopy over the drive, on two columns.
	var cd := 6.0
	geo.box("white", Vector3(cx, 4.75, zf + cd * 0.5), Vector3(w + 0.4, 0.5, cd))
	geo.box("brand%d" % brand_i, Vector3(cx, 4.75, zf + cd + 0.03), Vector3(w + 0.4, 0.5, 0.06))
	geo.box("soffit_light", Vector3(cx, 4.49, zf + cd * 0.5), Vector3(w - 1.0, 0.02, cd - 1.0))
	for sx: float in [x0 + 0.4, x1 - 0.4]:
		geo.box("mullion", Vector3(sx, 2.25, zf + cd - 0.4), Vector3(0.3, 4.5, 0.3))
		_shape_local(ch, xf, Vector3(sx, 2.25, zf + cd - 0.4), Vector3(0.3, 4.5, 0.3))
	if not OS.has_feature("web"):
		var ti := MeshInstance3D.new()
		ti.name = "Service"
		ti.mesh = _text("SERVICE", 0.34, Color(0.97, 0.97, 0.95), 1.4)
		ti.position = Vector3(cx, 4.75, zf + cd + 0.07)
		ti.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ti.visibility_range_end = 140.0
		node.add_child(ti)
	_shape_local(ch, xf, Vector3(cx, H * 0.5, zb + d * 0.5 - 0.5), Vector3(w, H, d - 1.0))
	ch._occluder_boxes.append([xf, Vector3(cx, H * 0.5, (zb + zf) * 0.5), Vector3(w - 0.6, H - 0.6, d - 0.6)])


## The brand pylon at the kerb: a tall slab in the brand's colour, a lit badge high on both faces
## and the name on a lit panel under it.
static func _pylon(ch: CityChunk, node: Node3D, geo: Geo, s: Dictionary, L: Dictionary, xf: Transform3D, g: float) -> void:
	var py: Array = L.pylon
	var x := float(py[0])
	var z := float(py[1])
	var brand_i: int = s.brand
	geo.box("concrete", Vector3(x, 0.3, z), Vector3(1.2, 0.6, 3.2))
	geo.box("brand%d" % brand_i, Vector3(x, PYLON_H * 0.5, z), Vector3(0.7, PYLON_H, 2.8))
	geo.box("white", Vector3(x, PYLON_H + 0.06, z), Vector3(0.8, 0.12, 2.9))
	for sx: float in [-1.0, 1.0]:
		var face_x := x + sx * 0.36
		var right := Vector3(0.0, 0.0, -sx)
		geo.quad_uv("sign%d_w" % brand_i, Vector3(face_x, PYLON_H - 1.6, z), right, Vector3.UP, 2.3, 2.3)
		geo.quad_uv("lightbox", Vector3(face_x, PYLON_H - 3.5, z), right, Vector3.UP, 2.5, 1.0)
		if not OS.has_feature("web"):
			var ti := MeshInstance3D.new()
			ti.mesh = _text(String(s.name), 0.5, BRANDS[brand_i][2], 0.0)
			ti.position = Vector3(face_x + sx * 0.02, PYLON_H - 3.5, z)
			ti.rotation.y = sx * PI * 0.5
			ti.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			ti.visibility_range_end = 260.0
			node.add_child(ti)
	_shape_local(ch, xf, Vector3(x, PYLON_H * 0.5, z), Vector3(0.8, PYLON_H, 3.0))


## A used lot's office: a white trailer on blocks with a skirt, a door up three steps, windows,
## a window air conditioner, and a sign board on its roof.
static func _trailer(ch: CityChunk, node: Node3D, geo: Geo, s: Dictionary, L: Dictionary, xf: Transform3D, g: float) -> void:
	var tr: Rect2 = L.trailer
	var cx := tr.get_center().x
	var cz := tr.get_center().y
	var l := tr.size.x
	var d := tr.size.y
	var y0 := 0.7
	var h := 2.7
	geo.box("trailer", Vector3(cx, y0 + h * 0.5, cz), Vector3(l, h, d))
	geo.box("trailer_roof", Vector3(cx, y0 + h + 0.05, cz), Vector3(l + 0.1, 0.1, d + 0.1))
	geo.box("skirt", Vector3(cx, y0 * 0.5, cz), Vector3(l - 0.2, y0, d - 0.2))
	var fz := cz + d * 0.5
	# Windows along the front, a door with steps and a rail.
	var dxp := cx - l * 0.5 + 1.6
	geo.box("door", Vector3(dxp, y0 + 1.05, fz + 0.02), Vector3(0.95, 2.05, 0.04))
	for k in 3:
		geo.box("concrete", Vector3(dxp, y0 - 0.2 - float(k) * 0.22 + 0.11, fz + 0.4 + float(k) * 0.3), Vector3(1.3, 0.2, 0.3 + float(2 - k) * 0.0))
	geo.box("pole", Vector3(dxp + 0.75, y0 + 0.2, fz + 0.7), Vector3(0.05, 1.0, 0.9))
	var nw := maxi(2, int((l - 3.0) / 2.2))
	for i in nw:
		var wx := dxp + 1.5 + (l - 3.5) * (float(i) + 0.5) / float(nw)
		geo.box("window", Vector3(wx, y0 + 1.55, fz + 0.02), Vector3(1.2, 0.9, 0.04))
		geo.box("trim", Vector3(wx, y0 + 1.07, fz + 0.06), Vector3(1.35, 0.06, 0.1))
	geo.box("ac", Vector3(cx + l * 0.5 - 1.2, y0 + 1.5, fz + 0.3), Vector3(0.7, 0.5, 0.6))
	# The roof board.
	geo.box("wood", Vector3(cx, y0 + h + 0.9, fz - 0.6), Vector3(minf(l - 1.0, 7.0), 1.4, 0.1))
	for sx: float in [-1.0, 1.0]:
		geo.box("pole", Vector3(cx + sx * 2.0, y0 + h + 0.4, fz - 0.7), Vector3(0.06, 0.8, 0.06))
	if not OS.has_feature("web"):
		var ti := MeshInstance3D.new()
		ti.mesh = _text(String(s.name), 0.42, Color(0.75, 0.08, 0.06), 0.0)
		ti.position = Vector3(cx, y0 + h + 1.05, fz - 0.54)
		ti.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ti.visibility_range_end = 180.0
		node.add_child(ti)
		var t2 := MeshInstance3D.new()
		t2.mesh = _text("OFFICE", 0.22, Color(0.1, 0.1, 0.1), 0.0)
		t2.position = Vector3(dxp, y0 + 2.25, fz + 0.05)
		t2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		t2.visibility_range_end = 60.0
		node.add_child(t2)
	_shape_local(ch, xf, Vector3(cx, (y0 + h) * 0.5, cz), Vector3(l, y0 + h, d))
	ch._occluder_boxes.append([xf, Vector3(cx, (y0 + h) * 0.5, cz), Vector3(l - 0.4, y0 + h - 0.4, d - 0.4)])


## A used lot's hand-painted board on two posts at the kerb corner.
static func _used_sign(ch: CityChunk, node: Node3D, geo: Geo, s: Dictionary, L: Dictionary) -> void:
	var sp: Array = L.sign
	var x := float(sp[0])
	var z := float(sp[1])
	var bw := 4.6
	for sx: float in [-1.0, 1.0]:
		geo.box("wood", Vector3(x + sx * (bw * 0.5 - 0.4), 2.4, z), Vector3(0.2, 4.8, 0.2))
	geo.box("board", Vector3(x, 3.9, z), Vector3(bw, 1.6, 0.08))
	geo.box("wood", Vector3(x, 4.74, z), Vector3(bw + 0.1, 0.08, 0.12))
	geo.box("wood", Vector3(x, 3.06, z), Vector3(bw + 0.1, 0.08, 0.12))
	_shape_local(ch, frame_xf(s, CityChunk.SIDEWALK_TOP + ch._gy((s.rect as Rect2).get_center().x, (s.rect as Rect2).get_center().y)), Vector3(x, 2.4, z), Vector3(bw, 4.8, 0.3))
	if OS.has_feature("web"):
		return
	var line: String = USED_LINES[(int(s.id) >> 7) % USED_LINES.size()]
	for face: float in [1.0, -1.0]:
		var t1 := MeshInstance3D.new()
		t1.mesh = _text(String(s.name), 0.36, Color(0.78, 0.07, 0.05), 0.0)
		t1.position = Vector3(x, 4.25, z + face * 0.045)
		t1.rotation.y = 0.0 if face > 0.0 else PI
		t1.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		t1.visibility_range_end = 180.0
		node.add_child(t1)
		var t2 := MeshInstance3D.new()
		t2.mesh = _text(line + "!", 0.42, Color(0.06, 0.18, 0.55), 0.0)
		t2.position = Vector3(x, 3.6, z + face * 0.045)
		t2.rotation.y = 0.0 if face > 0.0 else PI
		t2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		t2.visibility_range_end = 180.0
		node.add_child(t2)


## Chain-link (LotFill's) along the site's sides that are not the street, as far as the cell row
## reaches; the street side stays open.
static func _fence_sides(ch: CityChunk, s: Dictionary) -> void:
	var r: Rect2 = s.rect
	var side: int = s.side
	var base := CityChunk.SIDEWALK_TOP + LotFill.ASPHALT_LIFT
	for k in 4:
		if k == side:
			continue
		var along_x := k <= 1
		var line := [r.position.y + 0.25, r.end.y - 0.25, r.position.x + 0.25, r.end.x - 0.25][k] as float
		var length := r.size.x - 0.6 if along_x else r.size.y - 0.6
		var c := Vector2(r.get_center().x, line) if along_x else Vector2(line, r.get_center().y)
		LotFill._fence(ch, c, length, along_x, base)


static func _shape_local(ch: CityChunk, xf: Transform3D, c: Vector3, size: Vector3) -> void:
	var w := xf * c
	var wsize := size if absf(xf.basis.x.x) > 0.5 else Vector3(size.z, size.y, size.x)
	ch._add_shape(wsize, w)


# --- Meshes -------------------------------------------------------------------------------------

## Text lettering; `glow` > 0 lights it after dark (lamp_factor).
static func _text(text: String, size: float, color: Color, glow: float) -> TextMesh:
	if glow <= 0.0:
		return BigVehicles.text_mesh(text, size, color)
	var key := "text|%s|%.2f|%s|%.1f" % [text, size, color.to_html(), glow]
	if _mats.has(key):
		return _mats[key]
	var tm := TextMesh.new()
	tm.text = text
	tm.font_size = 64
	tm.pixel_size = size / 64.0
	tm.depth = 0.04
	tm.curve_step = 1.5
	var m := ShaderMaterial.new()
	m.shader = _glow_shader()
	m.set_shader_parameter("tint", Vector3(color.r, color.g, color.b))
	m.set_shader_parameter("strength", glow)
	tm.material = m
	_mats[key] = tm
	return tm


static func _glow_shader() -> Shader:
	if _mats.has("glow_shader"):
		return _mats.glow_shader
	var sh := Shader.new()
	sh.code = """shader_type spatial;
#include "res://shaders/color_space.gdshaderinc"
global uniform float lamp_factor;
uniform vec3 tint = vec3(1.0);
uniform float strength = 2.0;
uniform float day = 0.08;
void fragment() {
	vec3 c = cs_srgb_to_linear(tint);
	ALBEDO = cs_out(c);
	ROUGHNESS = 0.35;
	EMISSION = cs_out(c * mix(day, strength, clamp(lamp_factor, 0.0, 1.0)));
}
"""
	_mats.glow_shader = sh
	return sh


## The inflatable tube man: a tube 6 m tall with a head and two arm tubes, standing straight
## (tube_man.gdshader dances it). UV around and up each part, UV2.x the part.
static func tube_man_mesh() -> ArrayMesh:
	if _mats.has("tube_mesh"):
		return _mats.tube_mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var H := 6.0
	var seg := 12
	var rings := 22
	# Body: radius bulging a little at the hips and the head.
	var body: Array = []
	for j in rings + 1:
		var t := float(j) / float(rings)
		var r := 0.3 + 0.03 * sin(t * PI * 2.0) + 0.04 * smoothstep(0.85, 0.95, t)
		if t > 0.97:
			r *= sqrt(maxf(0.0, 1.0 - pow((t - 0.97) / 0.03, 2.0))) * 0.9 + 0.1
		var ring: Array = []
		for i in seg + 1:
			var a := TAU * float(i) / float(seg)
			ring.append([Vector3(cos(a) * r, t * H, sin(a) * r), Vector3(cos(a), 0.0, sin(a)), Vector2(float(i) / float(seg), t)])
		body.append(ring)
	_tube(st, body, 0.0)
	# Arms: tubes out along +-x from the shoulder.
	for side: float in [-1.0, 1.0]:
		var arm: Array = []
		var arm_rings := 10
		for j in arm_rings + 1:
			var t := float(j) / float(arm_rings)
			var r := 0.17 - 0.03 * t
			var cx := side * (0.28 + t * 1.45)
			var ring: Array = []
			for i in 9:
				var a := TAU * float(i) / 8.0
				ring.append([Vector3(cx, 0.74 * H + cos(a) * r, sin(a) * r), Vector3(0.0, cos(a), sin(a)), Vector2(float(i) / 8.0, t)])
			arm.append(ring)
		_tube(st, arm, side)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/tube_man.gdshader")
	st.set_material(mat)
	var mesh := st.commit()
	# The dance moves it a few metres: keep it drawn.
	mesh.custom_aabb = AABB(Vector3(-4.5, -0.5, -4.5), Vector3(9.0, 7.5, 9.0))
	_mats.tube_mesh = mesh
	return mesh


static func _tube(st: SurfaceTool, rings: Array, part: float) -> void:
	for j in rings.size() - 1:
		var a: Array = rings[j]
		var b: Array = rings[j + 1]
		for i in a.size() - 1:
			for v: Array in [a[i], b[i], b[i + 1], a[i], b[i + 1], a[i + 1]]:
				st.set_color(Color.WHITE)
				st.set_normal(v[1])
				st.set_uv(v[2])
				st.set_uv2(Vector2(part, 0.0))
				st.add_vertex(v[0])


## The blower under a tube man: a black drum on a base.
static func fan_mesh() -> Mesh:
	if _mats.has("fan_mesh"):
		return _mats.fan_mesh
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.34
	cyl.bottom_radius = 0.38
	cyl.height = 0.55
	cyl.radial_segments = 14
	cyl.rings = 1
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.07, 0.07, 0.08)
	m.roughness = 0.6
	cyl.material = m
	var st := SurfaceTool.new()
	st.append_from(cyl, 0, Transform3D(Basis(), Vector3(0.0, 0.275, 0.0)))
	st.set_material(m)
	var mesh := st.commit()
	_mats.fan_mesh = mesh
	return mesh


## Where a lot car's price goes on its windscreen (ArenaGrounds.car_mesh(v)'s glasshouse, nose -Z):
## a transform taking the unit quad (QuadMesh, facing +Z) onto the glass. A used car's price is
## painted big across the middle; a new car's card sits low on the passenger side.
static func sticker_xform(v: int, used: bool) -> Transform3D:
	var dims := [[4.7, 1.82, 0.62, 0.52, 1.25], [5.4, 1.95, 0.78, 0.6, 1.5], [4.9, 1.95, 0.8, 0.85, 1.0], [4.45, 1.86, 0.52, 0.44, 1.35]][clampi(v, 0, 3)] as Array
	var hl := float(dims[0]) * 0.5
	var y1 := 0.3 + float(dims[2])
	var cab_h := float(dims[3])
	var cab0 := -hl + float(dims[4]) - 0.05
	var rake := 0.6 if v != 2 else 0.35
	var up := Vector3(0.0, cab_h, rake).normalized()
	var n := Vector3(0.0, rake, -cab_h).normalized()
	var length := Vector3(0.0, cab_h, rake).length()
	var size := Vector2(0.95, 0.5) if used else Vector2(0.36, 0.27)
	var x := 0.0 if used else 0.42
	var f := 0.5 if used else 0.26
	var c := Vector3(x, y1, cab0) + up * length * f + n * 0.012
	var right := Vector3(-1.0, 0.0, 0.0) # seen from the front (-Z), screen-right is world -x
	return Transform3D(Basis(right * size.x, up * size.y, n), c)


static func sticker_mesh() -> Mesh:
	if _mats.has("sticker_mesh"):
		return _mats.sticker_mesh
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/price_sticker.gdshader")
	q.material = m
	_mats.sticker_mesh = q
	return q


## The pennant strings, flags and feather flags of one dealership as one mesh (dealer_flag.gdshader).
static func _cloth_mesh(s: Dictionary, L: Dictionary) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var count := 0
	var brand: Color = BRANDS[int(s.brand)][2]
	var used: bool = s.used
	var id: int = s.id
	var si := 0
	for pair: Array in L.strings:
		var a: Vector3 = pair[0]
		var b: Vector3 = pair[1]
		var cols: Array = PENNANT_RAINBOW if used else [brand, Color(0.96, 0.96, 0.95), brand, Color(0.7, 0.72, 0.75)]
		count += _pennants(st, a, b, cols, float(id % 97) + float(si) * 3.1)
		si += 1
	if not used:
		# Brand flags on the three poles: brand / white / brand bands, flying along +x.
		for i in (L.flags as Array).size():
			var fl: Array = L.flags[i]
			var top := Vector3(float(fl[0]), 7.9, float(fl[1]))
			var cols := [brand, Color(0.96, 0.96, 0.95), brand] if i != 1 else [Color(0.96, 0.96, 0.95), brand, Color(0.96, 0.96, 0.95)]
			_flag(st, top, Vector3(1.0, 0.0, 0.0), 1.9, 1.15, cols, float(i) + float(id % 13))
			count += 1
		for i in (L.feathers as Array).size():
			var ff: Array = L.feathers[i]
			_feather(st, Vector3(float(ff[0]), 0.4, float(ff[1])), brand if i % 2 == 0 else Color(0.96, 0.96, 0.95), brand if i % 2 == 1 else Color(0.96, 0.96, 0.95), float(i) * 1.7)
			count += 1
	if count == 0:
		return null
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/dealer_flag.gdshader")
	st.set_material(m)
	return st.commit()


## One string of pennants from `a` to `b` (catenary sag), triangles every 0.42 m hanging under it,
## colours in turn; the rope as a thin ribbon. Returns 1.
static func _pennants(st: SurfaceTool, a: Vector3, b: Vector3, cols: Array, seed_value: float) -> int:
	var span := a.distance_to(b)
	var sag := 0.05 * span + 0.15
	var dir := (b - a).normalized()
	var n := dir.cross(Vector3.UP)
	if n.length_squared() < 1e-6:
		n = Vector3(1, 0, 0)
	n = n.normalized()
	var pts := maxi(2, int(span / 0.42))
	var at := func(t: float) -> Vector3: return a.lerp(b, t) - Vector3(0.0, sag * 4.0 * t * (1.0 - t), 0.0)
	for k in pts:
		var t0 := (float(k) + 0.08) / float(pts)
		var t1 := (float(k) + 0.92) / float(pts)
		var p0: Vector3 = at.call(t0)
		var p1: Vector3 = at.call(t1)
		var tip := (p0 + p1) * 0.5 - Vector3(0.0, 0.42, 0.0)
		var col: Color = cols[k % cols.size()]
		var sd := seed_value + float(k) * 0.37
		_vert(st, p0, n, col, 1.0, Vector2(0.0, 0.0), Vector2(0.0, sd))
		_vert(st, p1, n, col, 1.0, Vector2(0.0, 1.0), Vector2(0.0, sd))
		_vert(st, tip, n, col, 1.0, Vector2(1.0, 0.5), Vector2(1.0, sd))
	# The rope.
	var rope := Color(0.12, 0.12, 0.12)
	var segs := maxi(4, int(span / 2.0))
	for k in segs:
		var p0: Vector3 = at.call(float(k) / float(segs))
		var p1: Vector3 = at.call(float(k + 1) / float(segs))
		var dy := Vector3(0.0, 0.012, 0.0)
		for v: Vector3 in [p0 - dy, p0 + dy, p1 + dy, p0 - dy, p1 + dy, p1 - dy]:
			_vert(st, v, n, rope, 0.0, Vector2.ZERO, Vector2.ZERO)
	return 1


## A flag hoisted at `top` on its pole, flying along `fly` (horizontal), in horizontal bands of `cols`.
static func _flag(st: SurfaceTool, top: Vector3, fly: Vector3, length: float, height: float, cols: Array, seed_value: float) -> void:
	var n := fly.cross(Vector3.UP).normalized()
	var nu := 8
	var bands := cols.size()
	for bi in bands:
		var v0 := float(bi) / float(bands)
		var v1 := float(bi + 1) / float(bands)
		for i in nu:
			var u0 := float(i) / float(nu)
			var u1 := float(i + 1) / float(nu)
			var q := [[u0, v0], [u1, v0], [u1, v1], [u0, v0], [u1, v1], [u0, v1]]
			for uv: Array in q:
				var u := float(uv[0])
				var v := float(uv[1])
				var p := top + fly * (0.06 + u * length) - Vector3(0.0, v * height, 0.0)
				_vert(st, p, n, cols[bi], 1.0, Vector2(u, v), Vector2(u, seed_value))


## A feather flag: a tall narrow banner on a pole bent over at the top, its fly edge curving in.
static func _feather(st: SurfaceTool, foot: Vector3, body: Color, edge: Color, seed_value: float) -> void:
	var n := Vector3(0.0, 0.0, 1.0)
	var H := 3.2
	var wmax := 0.72
	var steps := 10
	for j in steps:
		var t0 := float(j) / float(steps)
		var t1 := float(j + 1) / float(steps)
		var w0 := wmax * sqrt(maxf(0.0, 1.0 - pow(maxf(t0 - 0.55, 0.0) / 0.45, 2.0)))
		var w1 := wmax * sqrt(maxf(0.0, 1.0 - pow(maxf(t1 - 0.55, 0.0) / 0.45, 2.0)))
		var y0 := foot.y + 0.5 + t0 * H
		var y1 := foot.y + 0.5 + t1 * H
		# The edge band by the pole in the second colour.
		var e0 := minf(0.16, w0)
		var e1 := minf(0.16, w1)
		var quads := [[0.0, e0, 0.0, e1, edge], [e0, w0, e1, w1, body]]
		for q: Array in quads:
			var a := Vector3(foot.x + float(q[0]), y0, foot.z)
			var b := Vector3(foot.x + float(q[1]), y0, foot.z)
			var c := Vector3(foot.x + float(q[3]), y1, foot.z)
			var d := Vector3(foot.x + float(q[2]), y1, foot.z)
			var ua := float(q[0]) / wmax
			var ub := float(q[1]) / wmax
			var uc := float(q[3]) / wmax
			var ud := float(q[2]) / wmax
			var col: Color = q[4]
			_vert(st, a, n, col, 1.0, Vector2(ua, t0), Vector2(ua * 0.6, seed_value))
			_vert(st, b, n, col, 1.0, Vector2(ub, t0), Vector2(ub * 0.6, seed_value))
			_vert(st, c, n, col, 1.0, Vector2(uc, t1), Vector2(uc * 0.6, seed_value))
			_vert(st, a, n, col, 1.0, Vector2(ua, t0), Vector2(ua * 0.6, seed_value))
			_vert(st, c, n, col, 1.0, Vector2(uc, t1), Vector2(uc * 0.6, seed_value))
			_vert(st, d, n, col, 1.0, Vector2(ud, t1), Vector2(ud * 0.6, seed_value))


static func _vert(st: SurfaceTool, p: Vector3, n: Vector3, col: Color, cloth: float, uv: Vector2, uv2: Vector2) -> void:
	st.set_color(Color(col.r, col.g, col.b, cloth))
	st.set_normal(n)
	st.set_uv(uv)
	st.set_uv2(uv2)
	st.add_vertex(p)


# --- Materials ----------------------------------------------------------------------------------

## Materials by name (shared by every dealership).
static func material(key: String) -> Material:
	if _mats.has(key):
		return _mats[key]
	var m: Material
	if key.begins_with("brand"):
		var c: Color = BRANDS[int(key.substr(5))][2]
		var bm := StandardMaterial3D.new()
		bm.albedo_color = c
		bm.roughness = 0.28
		bm.metallic = 0.15
		m = bm
	elif key.begins_with("sign"):
		# "sign<i>_w": the badge in the brand colour on a white face; "_b": white on the brand.
		var bi := int(key.substr(4, key.find("_") - 4))
		var c: Color = BRANDS[bi][2]
		var sm := ShaderMaterial.new()
		sm.shader = load("res://shaders/dealer_sign.gdshader")
		sm.set_shader_parameter("mark", int(BRANDS[bi][1]))
		var white := Vector3(0.95, 0.95, 0.94)
		var ink := Vector3(c.r, c.g, c.b)
		if key.ends_with("_b"):
			sm.set_shader_parameter("panel", ink)
			sm.set_shader_parameter("ink", white)
		else:
			sm.set_shader_parameter("panel", white)
			sm.set_shader_parameter("ink", ink)
		m = sm
	else:
		match key:
			"lightbox":
				var lm := ShaderMaterial.new()
				lm.shader = load("res://shaders/dealer_sign.gdshader")
				lm.set_shader_parameter("mark", 0)
				lm.set_shader_parameter("size", 0.0001)
				lm.set_shader_parameter("centre", Vector2(-9.0, -9.0))
				m = lm
			"white":
				var wm := StandardMaterial3D.new()
				wm.albedo_color = Color(0.9, 0.9, 0.89)
				wm.roughness = 0.4
				wm.metallic = 0.1
				m = wm
			"panel":
				m = PropFactory.pbr("metal_painted", 3.0, Color(0.82, 0.83, 0.84))
			"floor":
				var fm := StandardMaterial3D.new()
				fm.albedo_color = Color(0.82, 0.82, 0.8)
				fm.roughness = 0.1
				fm.metallic = 0.0
				m = fm
			"glass":
				var gm := StandardMaterial3D.new()
				gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				gm.albedo_color = Color(0.55, 0.66, 0.70, 0.16)
				gm.roughness = 0.03
				gm.metallic = 0.0
				gm.metallic_specular = 0.75
				m = gm
			"mullion", "pole":
				var mm := StandardMaterial3D.new()
				mm.albedo_color = Color(0.16, 0.17, 0.18) if key == "mullion" else Color(0.75, 0.76, 0.78)
				mm.roughness = 0.35
				mm.metallic = 0.7
				m = mm
			"soffit":
				m = PropFactory.material(Color(0.78, 0.78, 0.76), 0.7)
			"ceiling_light", "soffit_light":
				var lm := ShaderMaterial.new()
				lm.shader = FireStation._lamp_shader()
				lm.set_shader_parameter("strength", 4.0 if key == "ceiling_light" else 3.0)
				m = lm
			"concrete":
				m = PropFactory.pbr("concrete", 3.0, Color(0.86, 0.85, 0.82))
			"dark":
				m = PropFactory.material(Color(0.1, 0.1, 0.11), 0.6)
			"inner":
				m = PropFactory.material(Color(0.58, 0.58, 0.56), 0.85)
			"door":
				m = PropFactory.material(Color(0.7, 0.71, 0.72), 0.5)
			"bollard":
				m = PropFactory.material(Color(0.93, 0.93, 0.9), 0.5)
			"trailer":
				m = PropFactory.pbr("metal_corrugated", 2.0, Color(0.95, 0.95, 0.92))
			"trailer_roof", "skirt", "ac":
				m = PropFactory.material(Color(0.62, 0.63, 0.63) if key != "skirt" else Color(0.45, 0.44, 0.42), 0.7)
			"window":
				var wn := StandardMaterial3D.new()
				wn.albedo_color = Color(0.06, 0.07, 0.08)
				wn.roughness = 0.1
				wn.metallic = 0.3
				m = wn
			"trim":
				m = PropFactory.material(Color(0.9, 0.9, 0.88), 0.6)
			"wood":
				m = PropFactory.pbr("planks", 2.0, Color(0.75, 0.62, 0.48))
			"board":
				m = PropFactory.material(Color(0.97, 0.95, 0.88), 0.85)
			_:
				m = PropFactory.material(Color(0.5, 0.5, 0.5))
	_mats[key] = m
	return m


## Boxes, quads and ramps into one mesh, a surface per material (FireStation.Geo's rules: flat
## faces, clockwise seen from the normal, UV in metres; `quad_uv` 0..1 for the sign faces).
class Geo:
	var _st: Dictionary = {}

	func _tool(key: String) -> SurfaceTool:
		if not _st.has(key):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			_st[key] = st
		return _st[key]

	func box(key: String, c: Vector3, s: Vector3) -> void:
		var st := _tool(key)
		var h := s * 0.5
		var faces := [
			[Vector3.RIGHT, Vector3(h.x, -h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(h.x, h.y, h.z), Vector3(h.x, -h.y, h.z)],
			[Vector3.LEFT, Vector3(-h.x, -h.y, h.z), Vector3(-h.x, h.y, h.z), Vector3(-h.x, h.y, -h.z), Vector3(-h.x, -h.y, -h.z)],
			[Vector3.UP, Vector3(-h.x, h.y, -h.z), Vector3(-h.x, h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(h.x, h.y, -h.z)],
			[Vector3.DOWN, Vector3(-h.x, -h.y, h.z), Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z), Vector3(h.x, -h.y, h.z)],
			[Vector3.BACK, Vector3(h.x, -h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z), Vector3(-h.x, -h.y, h.z)],
			[Vector3.FORWARD, Vector3(-h.x, -h.y, -h.z), Vector3(-h.x, h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(h.x, -h.y, -h.z)],
		]
		for f: Array in faces:
			_quad(st, f[0], [c + (f[1] as Vector3), c + (f[2] as Vector3), c + (f[3] as Vector3), c + (f[4] as Vector3)], false)

	## A flat face of `w` x `h` centred at `c`, spanned by `right` and `up`, UV 0..1 (u along right,
	## v DOWN from the top, as the sign shader reads it), facing right x up.
	func quad_uv(key: String, c: Vector3, right: Vector3, up: Vector3, w: float, h: float) -> void:
		var st := _tool(key)
		var r := right.normalized() * w * 0.5
		var u := up.normalized() * h * 0.5
		var n := right.cross(up).normalized()
		var p := [c - r - u, c + r - u, c + r + u, c - r + u]
		var uv := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
		_tri_uv(st, n, p[0], p[1], p[2], uv[0], uv[1], uv[2])
		_tri_uv(st, n, p[0], p[2], p[3], uv[0], uv[2], uv[3])

	## A wedge ramp block: `length` along z rising from 0 at the front (+z end) to `rise` at the
	## back, `width` wide, its foot at `at` (the middle of its footprint).
	func ramp_block(key: String, at: Vector3, width: float, length: float, rise: float) -> void:
		var st := _tool(key)
		var hw := width * 0.5
		var hl := length * 0.5
		var a := at + Vector3(-hw, 0.0, hl)
		var b := at + Vector3(hw, 0.0, hl)
		var c := at + Vector3(hw, rise, -hl)
		var d := at + Vector3(-hw, rise, -hl)
		var e := at + Vector3(hw, 0.0, -hl)
		var f := at + Vector3(-hw, 0.0, -hl)
		var top_n := (c - b).cross(a - b).normalized()
		if top_n.y < 0.0:
			top_n = -top_n
		_quad(st, top_n, [a, b, c, d], false)
		_quad(st, Vector3.FORWARD, [f, d, c, e], false)
		_tri(st, Vector3.RIGHT, b, e, c)
		_tri(st, Vector3.LEFT, a, d, f)

	func _quad(st: SurfaceTool, n: Vector3, q: Array, _unused: bool) -> void:
		_tri(st, n, q[0], q[1], q[2])
		_tri(st, n, q[0], q[2], q[3])

	func _tri(st: SurfaceTool, n: Vector3, a: Vector3, b: Vector3, c: Vector3) -> void:
		if (b - a).cross(c - a).dot(n) > 0.0:
			var t := b
			b = c
			c = t
		for v: Vector3 in [a, b, c]:
			st.set_normal(n)
			var uv := Vector2(v.x + v.z, v.y) if absf(n.y) < 0.5 else Vector2(v.x, v.z)
			st.set_uv(uv)
			st.add_vertex(v)

	func _tri_uv(st: SurfaceTool, n: Vector3, a: Vector3, b: Vector3, c: Vector3, ua: Vector2, ub: Vector2, uc: Vector2) -> void:
		if (b - a).cross(c - a).dot(n) > 0.0:
			var t := b
			b = c
			c = t
			var tu := ub
			ub = uc
			uc = tu
		for k in 3:
			st.set_normal(n)
			st.set_uv([ua, ub, uc][k])
			st.add_vertex([a, b, c][k])

	func commit() -> ArrayMesh:
		var mesh := ArrayMesh.new()
		for key: String in _st:
			var st: SurfaceTool = _st[key]
			st.commit(mesh)
			mesh.surface_set_material(mesh.get_surface_count() - 1, CarDealers.material(key))
		return mesh
