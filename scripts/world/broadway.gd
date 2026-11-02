class_name Broadway
extends RefCounted
## The historic Broadway theatre district (2026-10-05, "the movie palaces"): downtown's Broadway
## between 3rd St and Olympic Blvd, which DowntownReal pins 1:1 (x 2991, z -403 .. 1006 on every
## seed). The real street's FORMS - 1910s-1930s movie palaces with towering blade signs and
## chasing marquees, the 1920s commercial blocks round them with their busy discount, electronics
## and bridal shops, its own cast-iron street lamps, a street clock on a corner - and every NAME
## invented (no real theatre, show, shop or company anywhere).
##
## WHERE is a table, never placed by hand: THEATRES lists each palace by its real street ADDRESS
## (the real house numbers of Broadway's palaces; odd numbers on the east side, even on the west),
## turned into a point along Broadway by the real cross streets (DowntownReal.STREETS: the 300
## block runs from 3rd to 4th, the 900 block from 9th to Olympic). Each palace takes the
## Broadway-facing lot of the seeded block that holds its point (the nearest free one within
## LOT_REACH when an earlier palace has it) - CityChunk._build_lot() asks claims() after its own
## rolls (the pad roll is made either way), so no other lot, roll or building moves. Lookups are
## hashes and the table only, cached per plan: a chunk at any level, the far city and the checks
## all get the same palaces.
##
## What else this touches, each from one hook line:
## - dress(): every other building fronting Broadway in the stretch keeps its lot and rolls but is
##   a 1920s commercial block - masonry finishes, held under the old 150 ft height limit
##   (HEIGHT_LIMIT), and its shops named from BROADWAY_SHOPS (Building.name_pool).
## - lamp(): the street lamps along Broadway's pavements are BroadwayStreet's cast-iron lanterns
##   (same spacing, same prop slot, so prop ids and the rng do not move).
## - block_step(): racks of goods and dress forms outside the shops, the street clock, the coloured
##   light under each marquee (BroadwayStreet).
## The palaces themselves are BroadwayTheatre (FULL: the whole facade, marquee, blade sign,
## ticket booth and terrazzo; LOD and the far city: boxes with their sign column, lit at night).
##
## Off (BROADWAY=0 in the environment): none of it, the A/B for stills and frame counts.

enum Style { FRENCH, SPANISH, DECO }

## The avenue and the stretch.
const AVENUE := "BROADWAY"
## The cross streets bounding each hundred block, 300 to 1000 (DowntownReal.STREETS names).
const CROSS := ["3RD ST", "4TH ST", "5TH ST", "6TH ST", "7TH ST", "8TH ST", "9TH ST", "OLYMPIC BLVD"]
## The old city height limit (150 ft) the 1920s blocks were built to.
const HEIGHT_LIMIT := 46.0
## A palace takes the nearest free Broadway lot within this many metres of its address.
const LOT_REACH := 60.0
## Smallest Broadway frontage a palace will take (m).
const MIN_FRONTAGE := 18.0

## The palaces, north to south. `num` is the real address on S Broadway; everything else is this
## game's own: `name` (invented), `style`, `front_h` (the front building's height, m: an office
## block over the lobby where the real one has one), `sign_h` (the blade sign), `marquee` ("v"
## a vee front, "flat", "round" a drum), `titles` (the changeable-letter boards: three lines on
## the front, the rest on the sides), `enamel` (the sign's painted sheet), `neon` and `letters`
## (night colours), `terrazzo` (two colours of the entrance floor), `roof_sign` (a rooftop name
## in lit letters), `tower` (a clock tower over the front, m above it).
const THEATRES := [
	{"id": "monarca", "num": 307, "name": "EL MONARCA", "style": Style.SPANISH, "front_h": 45.0, "sign_h": 18.0,
		"marquee": "flat", "titles": ["NOCHE DE GALA", "MARIACHI SOL DE ORO", "SAB 8PM", "BOLETOS AQUI"],
		"enamel": Color(0.55, 0.08, 0.07), "neon": Color(1.0, 0.33, 0.12), "letters": Color(1.0, 0.86, 0.55),
		"terrazzo": [Color(0.56, 0.16, 0.12), Color(0.86, 0.78, 0.62)]},
	{"id": "aurora", "num": 518, "name": "AURORA", "style": Style.DECO, "front_h": 17.0, "sign_h": 16.0,
		"marquee": "v", "titles": ["THE GLASS ORCHID", "MIDNIGHT ON MAIN", "LATE SHOW 11:45", "ALL SEATS $5"],
		"enamel": Color(0.10, 0.22, 0.30), "neon": Color(0.25, 0.85, 1.0), "letters": Color(0.80, 0.95, 1.0),
		"terrazzo": [Color(0.12, 0.20, 0.26), Color(0.80, 0.76, 0.66)]},
	{"id": "camellia", "num": 534, "name": "CAMELLIA", "style": Style.FRENCH, "front_h": 19.0, "sign_h": 13.0,
		"marquee": "flat", "titles": ["SILENT CLASSICS", "FILM FESTIVAL", "TONIGHT", "ORGAN LIVE"],
		"enamel": Color(0.82, 0.74, 0.58), "neon": Color(1.0, 0.30, 0.55), "letters": Color(1.0, 0.70, 0.82),
		"terrazzo": [Color(0.50, 0.22, 0.28), Color(0.84, 0.80, 0.70)]},
	{"id": "empress", "num": 615, "name": "THE EMPRESS", "style": Style.FRENCH, "front_h": 25.0, "sign_h": 20.0,
		"marquee": "v", "titles": ["THE LAST TROLLEY", "IN 70MM", "NOW SHOWING", "RESTORED PRINT"],
		"enamel": Color(0.60, 0.48, 0.20), "neon": Color(1.0, 0.62, 0.18), "letters": Color(1.0, 0.90, 0.62),
		"terrazzo": [Color(0.20, 0.18, 0.30), Color(0.82, 0.70, 0.40)]},
	{"id": "paloma", "num": 630, "name": "LA PALOMA", "style": Style.FRENCH, "front_h": 22.0, "sign_h": 16.0,
		"marquee": "round", "titles": ["CORAZON DE PLATA", "EN VIVO", "VIE SAB DOM", "FUNCION 9PM"],
		"enamel": Color(0.86, 0.84, 0.78), "neon": Color(0.95, 0.20, 0.30), "letters": Color(1.0, 0.40, 0.42),
		"terrazzo": [Color(0.36, 0.12, 0.14), Color(0.88, 0.84, 0.76)]},
	{"id": "valencia", "num": 703, "name": "VALENCIA", "style": Style.SPANISH, "front_h": 44.0, "sign_h": 18.0,
		"marquee": "v", "titles": ["LUCHA LIBRE NIGHT", "LOS TRUENOS", "DOORS 7PM", "GENERAL ADMISSION"],
		"enamel": Color(0.18, 0.30, 0.18), "neon": Color(0.30, 1.0, 0.45), "letters": Color(0.92, 1.0, 0.80),
		"terrazzo": [Color(0.18, 0.32, 0.24), Color(0.86, 0.80, 0.64)]},
	{"id": "crescent", "num": 744, "name": "CRESCENT", "style": Style.FRENCH, "front_h": 20.0, "sign_h": 15.0,
		"marquee": "flat", "titles": ["SWING FEVER", "BIG BAND REVUE", "DANCE TIL 2", "THURSDAYS"],
		"enamel": Color(0.10, 0.12, 0.28), "neon": Color(0.55, 0.40, 1.0), "letters": Color(1.0, 0.92, 0.70),
		"terrazzo": [Color(0.14, 0.14, 0.30), Color(0.78, 0.72, 0.58)]},
	{"id": "zenith", "num": 802, "name": "ZENITH", "style": Style.FRENCH, "front_h": 22.0, "sign_h": 14.0,
		"marquee": "v", "titles": ["SILVER CANYON", "DOUBLE FEATURE", "MATINEE 2PM", "COLD INSIDE"],
		"enamel": Color(0.62, 0.12, 0.10), "neon": Color(1.0, 0.75, 0.25), "letters": Color(1.0, 0.92, 0.64),
		"terrazzo": [Color(0.52, 0.20, 0.10), Color(0.86, 0.80, 0.66)], "tower": 14.0},
	{"id": "stardust", "num": 812, "name": "STARDUST", "style": Style.DECO, "front_h": 16.0, "sign_h": 15.0,
		"marquee": "round", "titles": ["FOR LEASE", "RETAIL SPACE", "CALL 555 0142", "AVAILABLE NOW"],
		"enamel": Color(0.80, 0.80, 0.78), "neon": Color(1.0, 0.25, 0.75), "letters": Color(1.0, 0.55, 0.90),
		"terrazzo": [Color(0.20, 0.20, 0.22), Color(0.82, 0.62, 0.70)]},
	{"id": "sovereign", "num": 842, "name": "SOVEREIGN", "style": Style.FRENCH, "front_h": 30.0, "sign_h": 20.0,
		"marquee": "v", "titles": ["THE CRIMSON REEL", "ORGAN CONCERT", "SUNDAY 3PM", "MEMBERS FREE"],
		"enamel": Color(0.70, 0.56, 0.24), "neon": Color(1.0, 0.18, 0.12), "letters": Color(1.0, 0.86, 0.50),
		"terrazzo": [Color(0.40, 0.08, 0.08), Color(0.84, 0.74, 0.50)], "roof_sign": true},
	{"id": "solana", "num": 933, "name": "SOLANA", "style": Style.SPANISH, "front_h": 46.0, "sign_h": 17.0,
		"marquee": "flat", "titles": ["HALL OF ECHOES", "WORLD PREMIERE", "TONIGHT 8PM", "RED CARPET 6PM"],
		"enamel": Color(0.24, 0.10, 0.22), "neon": Color(1.0, 0.40, 0.85), "letters": Color(1.0, 0.85, 0.95),
		"terrazzo": [Color(0.30, 0.10, 0.22), Color(0.86, 0.78, 0.66)]},
]

## The ground-floor shops of Broadway's commercial blocks (appended after Building's own 30, so
## no other building's sign roll moves; Building.name_pool picks among them). Spanish and English,
## as on the real street; every one invented.
const BROADWAY_SHOPS := ["NOVIAS ELENA", "QUINCEANERAS", "VESTIDOS DE GALA", "TODO A 99C",
	"DISCOUNT CITY", "ELECTRONICA", "CELULARES", "JOYERIA ORO", "ZAPATERIA", "PERFUMES",
	"BOTAS VAQUERAS", "TELAS FINAS", "ROPA PARA TODOS", "RADIOS & TV", "RELOJES", "REGALOS",
	"ENVIOS DE DINERO", "JUGOS FRESCOS", "BRIDAL WORLD", "LA REINA BRIDAL", "MUEBLES", "SOMBREROS",
	"PRECIOS BAJOS", "TODO EN OFERTA"]

static var enabled: bool = OS.get_environment("BROADWAY") != "0"
static var _plans: Dictionary = {}
static var _pool: PackedInt32Array = PackedInt32Array()


## Broadway's centre line x (the pinned real street).
static func avenue_x() -> float:
	var pin := DowntownReal.named(CityPlan.AXIS_X, AVENUE)
	return float(pin[0]) if not pin.is_empty() else 2991.0


## Broadway's carriageway width.
static func avenue_width() -> float:
	var pin := DowntownReal.named(CityPlan.AXIS_X, AVENUE)
	return float(pin[1]) if not pin.is_empty() else 20.0


## The game z of a cross street (DowntownReal.STREETS by name).
static func street_z(street: String) -> float:
	for s: Dictionary in DowntownReal.STREETS:
		if str(s.name) == street:
			return DowntownReal.to_game(Vector2(0.0, float(s.v))).y
	return NAN


## The stretch's two ends in z (3rd St's and Olympic's centre lines).
static func z_range() -> Vector2:
	return Vector2(street_z(CROSS[0]), street_z(CROSS[CROSS.size() - 1]))


## Where house number `num` on S Broadway is, as a game z: the hundred block between its two
## cross streets, the number's last two digits the share of the way along it.
static func address_z(num: int) -> float:
	var k := clampi(num / 100 - 3, 0, CROSS.size() - 2)
	var t := clampf(float(num % 100) / 100.0, 0.0, 1.0)
	return lerpf(street_z(CROSS[k]), street_z(CROSS[k + 1]), t)


## True when block (bx, bz) is one of the stretch's blocks fronting Broadway: returns which side
## (-1 west of it, +1 east) or 0.
static func block_side(plan: CityPlan, bx: int, bz: int) -> int:
	if not enabled or plan == null or plan.macro == null:
		return 0
	var b := plan.block(bx, bz)
	var r: Rect2 = b.rect
	var x := avenue_x()
	var half := avenue_width() * 0.5
	var zr := z_range()
	var c := r.get_center()
	if c.y < zr.x or c.y > zr.y:
		return 0
	if absf(r.end.x - (x - half)) < 1.0:
		return -1
	if absf(r.position.x - (x + half)) < 1.0:
		return 1
	return 0


## True when `lot` of a block on `side` faces Broadway (its edge on the Broadway pavement).
static func lot_fronts(plan: CityPlan, bx: int, bz: int, side: int, lot: Dictionary) -> bool:
	if side == 0 or lot.get("yard", false):
		return false
	var inner := (plan.block(bx, bz).rect as Rect2).grow(-plan.sidewalk_width)
	var c: Vector2 = lot.center
	var s: Vector2 = lot.size
	if side < 0:
		return c.x + s.x * 0.5 > inner.end.x - 3.0
	return c.x - s.x * 0.5 < inner.position.x + 3.0


## The palaces of this plan: an Array of {"spec" (the THEATRES row), "block" Vector2i, "lot"
## (the lot dictionary), "side" (-1 west, +1 east), "z" (the address's game z)}. Cached per seed.
static func palaces(plan: CityPlan) -> Array:
	if plan == null:
		return []
	if _plans.has(plan.seed):
		return _plans[plan.seed]
	var out: Array = []
	_plans[plan.seed] = out
	if not enabled or plan.macro == null:
		return out
	var x := avenue_x()
	var taken := {}
	for spec: Dictionary in THEATRES:
		var num := int(spec.num)
		var side := 1 if num % 2 == 1 else -1
		var z := address_z(num)
		var best: Dictionary = {}
		var best_d := LOT_REACH
		var best_block := Vector2i.ZERO
		for dz in [-1, 0, 1]:
			var probe := Vector2(x + float(side) * 30.0, z)
			var bi := plan.block_index_at(probe) + Vector2i(0, dz)
			if block_side(plan, bi.x, bi.y) != side:
				continue
			for lot: Dictionary in plan.lots(bi.x, bi.y):
				if not lot_fronts(plan, bi.x, bi.y, side, lot):
					continue
				var c: Vector2 = lot.center
				var s: Vector2 = lot.size
				if s.y < MIN_FRONTAGE:
					continue
				var key := Vector3i(bi.x, bi.y, int(lot.seed))
				if taken.has(key):
					continue
				# Distance from the address to the lot's frontage (0 inside it).
				var d := maxf(absf(z - c.y) - s.y * 0.5, 0.0)
				if d < best_d:
					best_d = d
					best = lot
					best_block = bi
		if best.is_empty():
			continue
		taken[Vector3i(best_block.x, best_block.y, int(best.seed))] = true
		out.append({"spec": spec, "block": best_block, "lot": best, "side": side, "z": z})
	return out


## The palace standing on `lot` of block (bx, bz), or {}.
static func palace_on(plan: CityPlan, bx: int, bz: int, lot: Dictionary) -> Dictionary:
	if block_side(plan, bx, bz) == 0:
		return {}
	for p: Dictionary in palaces(plan):
		if p.block == Vector2i(bx, bz) and int((p.lot as Dictionary).seed) == int(lot.seed):
			return p
	return {}


## CityChunk._build_lot(): is this lot a palace's?
static func claims(plan: CityPlan, bx: int, bz: int, lot: Dictionary) -> bool:
	return not palace_on(plan, bx, bz, lot).is_empty()


## CityChunk._build_lot(): builds the palace on its lot (BroadwayTheatre, FULL or LOD).
static func build_lot(ch: CityChunk, lot: Dictionary) -> void:
	var p := palace_on(ch.plan, ch.ix, ch.iz, lot)
	if not p.is_empty():
		BroadwayTheatre.build(ch, p)


## CityChunk._build_lot(): a commercial block fronting Broadway in the stretch becomes a 1920s
## one - masonry, under the height limit, its shops named from BROADWAY_SHOPS. Set before the
## building generates (both levels, so the far copy agrees). Nothing else about it moves.
static func dress(ch: CityChunk, lot: Dictionary, building: Building) -> void:
	var side := block_side(ch.plan, ch.ix, ch.iz)
	if side == 0 or not lot_fronts(ch.plan, ch.ix, ch.iz, side, lot):
		return
	building.finish_options.assign([Building.Finish.BRICK, Building.Finish.FLAT, Building.Finish.BRICK])
	building.max_height = minf(building.max_height, HEIGHT_LIMIT)
	building.min_height = minf(building.min_height, building.max_height * 0.9)
	building.name_pool = shop_pool()


## The indices of BROADWAY_SHOPS in Building.SHOP_NAMES (they are appended there).
static func shop_pool() -> PackedInt32Array:
	if _pool.is_empty():
		for name: String in BROADWAY_SHOPS:
			_pool.append(Building.SHOP_NAMES.find(name))
	return _pool


## CityChunk._build_sidewalk_props(): a lamp along Broadway's pavement in the stretch is
## BroadwayStreet's lantern. Returns true when it placed one (the chunk then skips its own).
static func lamp(ch: CityChunk, p: Vector2, inward: Vector2) -> bool:
	if absf(inward.x) < 0.5:
		return false
	var side := block_side(ch.plan, ch.ix, ch.iz)
	if side == 0 or signf(inward.x) != float(side):
		return false
	BroadwayStreet.add_lamp(ch, Vector3(p.x, CityChunk.SIDEWALK_TOP, p.y), inward)
	return true


## CityChunk._build_sidewalk_props(), after StreetDetail: the pavement life of a Broadway block
## (FULL only; hashes, no rng).
static func block_step(ch: CityChunk, rect: Rect2) -> void:
	var side := block_side(ch.plan, ch.ix, ch.iz)
	if side == 0:
		return
	BroadwayStreet.build_block(ch, rect, side)


static func h01(parts: Array) -> float:
	return float(absi(hash(parts)) % 100003) / 100003.0
