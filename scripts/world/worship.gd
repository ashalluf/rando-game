class_name Worship
extends RefCounted
## Places of worship across the city (2026-10-05, fleet task "churches"): a Mission Revival church
## with its bell tower and arcade, a modern board-formed concrete church with a free-standing
## campanile, a small storefront church, a Greek-revival temple-front church with a white steeple,
## a Buddhist temple behind its gate, and a synagogue with its round window and twin towers. All at
## real size, with grounds (lawns, paths, a low wall or fence on the street, trees, a lit name
## board), floodlit at night with their windows glowing from inside, and every one a SANCTUARY
## (Sanctuary zone + body: no shot at or into it, no blast beside it, like the masjid). Every name
## is this game's own; none is a real congregation's or building's.
##
## WHERE is worked out, never placed (FireStation's / PoliceStation's way): the city is cut into
## CELL squares; a hash of seed + cell says whether the cell has one, which kind (by the district's
## weights, `KIND_WEIGHTS`) and up to TRIES points in it; the first point whose block is ordinary
## buildings that nobody else claims (a site, grounds, a hospital, a landmark, the river, the fire
## or police station's block, Broadway's frontage) gives a SITE: a centred run of the block's
## lot-grid cells along one street about the kind's size (`SIZES`). Every lot whose centre is in
## it is the site's (CityChunk._build_lot asks claims() after the fire and police stations', so no
## roll moves) and the first of them in lots() order builds it (`build_lot()`). Hashes of seed +
## cell only: a chunk at any level, the far city, StreetWear and the encampments ask the same
## question and get the same answer.
##
## StreetWear paints nothing within the site's radius + its WORSHIP_MARGIN (`blocked_near()`), and
## no encampment is laid on a block within Encampment.WORSHIP_CLEAR of one (`near_rect()`).

enum Kind { MISSION, MODERN, STOREFRONT, GREEK, TEMPLE, SYNAGOGUE }
const KIND_NAMES := ["mission", "modern", "storefront", "greek", "temple", "synagogue"]

const CELL := 800.0
const ODDS := 0.85
const TRIES := 10
## Per district (CityPlan.District) the weight of each Kind, in Kind order. Missing: none there.
const KIND_WEIGHTS := {
	CityPlan.District.SUBURBS: [3.0, 2.0, 0.0, 0.6, 2.0, 1.2],
	CityPlan.District.MIDTOWN: [1.4, 1.0, 2.6, 2.0, 1.0, 1.8],
	CityPlan.District.DOWNTOWN: [1.0, 0.6, 2.6, 2.2, 0.5, 1.4],
	CityPlan.District.BEACHTOWN: [2.2, 1.2, 1.0, 0.0, 0.5, 0.6],
	CityPlan.District.INDUSTRIAL: [0.0, 0.0, 1.0, 0.0, 0.0, 0.0],
}
## The site each kind aims for, the least it takes and the most (frontage, depth; m).
const SIZES := [
	[Vector2(46.0, 52.0), Vector2(36.0, 42.0), Vector2(70.0, 76.0)],
	[Vector2(42.0, 46.0), Vector2(32.0, 38.0), Vector2(66.0, 72.0)],
	[Vector2(13.0, 20.0), Vector2(9.0, 15.0), Vector2(26.0, 40.0)],
	[Vector2(34.0, 46.0), Vector2(26.0, 38.0), Vector2(56.0, 70.0)],
	[Vector2(40.0, 42.0), Vector2(32.0, 34.0), Vector2(64.0, 68.0)],
	[Vector2(34.0, 42.0), Vector2(28.0, 34.0), Vector2(56.0, 66.0)],
]
## The most the ground may rise across a site (m): the grounds are one level.
const MAX_RELIEF := 1.2

const NAMES := [
	["OUR LADY OF THE ARROYO", "SAN MARCOS DE LA LOMA", "SANTA LUCIA DEL VALLE", "ST. AMBROSE OF THE HILLS",
		"OUR LADY OF THE CANYON", "SAN TELMO DEL MAR", "HOLY CROSS OF THE BASIN", "SANTA INES DE LA SIERRA"],
	["LIGHT OF THE BASIN LUTHERAN", "SAGE HILL CHAPEL", "RIVERSTONE FELLOWSHIP", "HIGH MESA COMMUNITY CHURCH",
		"CHURCH OF THE OPEN SKY", "CANYON VIEW PRESBYTERIAN", "NEW DAWN EPISCOPAL", "WILLOW CREEK UNITED"],
	["IGLESIA LUZ DEL VALLE", "NEW MORNING STAR MINISTRIES", "TEMPLO FUENTE DE VIDA", "GREATER FAITH TABERNACLE",
		"IGLESIA CASA DE ORACION", "ZION HILL MISSIONARY CHURCH", "IGLESIA ROCA FIRME", "TRUE VINE FELLOWSHIP"],
	["FIRST CHURCH OF RANDO CITY", "MT. HARMONY BAPTIST CHURCH", "OLD STONE METHODIST", "PILGRIM HILL CONGREGATIONAL",
		"TRINITY OF THE PLAINS", "UNION CHAPEL OF THE BASIN", "BETHEL HEIGHTS CHURCH", "CALVARY OF THE COAST"],
	["LOTUS HILL BUDDHIST TEMPLE", "QUIET VALLEY ZEN CENTER", "PURE LAND TEMPLE", "BASIN DHARMA HALL",
		"CLEAR STREAM TEMPLE", "WHITE CLOUD MONASTERY", "PEACEFUL HARBOR TEMPLE", "MOUNTAIN GATE TEMPLE"],
	["CONGREGATION OR HAEMEK", "SHAAREI HAGIVAH", "TEMPLE BETH HAEMEK", "CONGREGATION KOL HAYAM",
		"TEMPLE NER HAGIVAH", "CONGREGATION OHEL SHALOM", "TEMPLE SHAAREI OR", "CONGREGATION BNEI HAEMEK"],
]

## Off (WORSHIP=0 in the environment): none anywhere, the lots keep their buildings (the A/B).
static var enabled: bool = OS.get_environment("WORSHIP") != "0"
## Forces one kind everywhere (WORSHIP_KIND=mission|modern|...), for stills.
static var force_kind: int = KIND_NAMES.find(OS.get_environment("WORSHIP_KIND"))
static var _cache: Dictionary = {}
## Why cells found nothing (WORSHIP_DEBUG=1), for the probe.
static var why: Dictionary = {}
static var _debug: bool = OS.get_environment("WORSHIP_DEBUG") == "1"


static func h01(parts: Array) -> float:
	return float(absi(hash(parts)) % 100003) / 100003.0


static func _cell_of(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / CELL), floori(p.y / CELL))


# --- Where ---------------------------------------------------------------------------------------

## The place of worship of grid cell `cell`: {} or a site (see _site()) plus "cell", "kind",
## "name". Cached per plan and cell.
static func for_cell(plan: CityPlan, cell: Vector2i) -> Dictionary:
	var key := Vector3i(plan.seed, cell.x, cell.y)
	if _cache.has(key):
		return _cache[key]
	var out := {}
	_cache[key] = out
	if not enabled or plan.macro == null:
		return out
	if h01([plan.seed, cell.x, cell.y, "worship"]) > ODDS:
		return out
	for t in TRIES:
		var target := Vector2((float(cell.x) + lerpf(0.12, 0.88, h01([plan.seed, cell.x, cell.y, t, "wx"]))) * CELL,
				(float(cell.y) + lerpf(0.12, 0.88, h01([plan.seed, cell.x, cell.y, t, "wz"]))) * CELL)
		if plan.zone_at(target) != MacroMap.Zone.CITY:
			_why("zone")
			continue
		var bi := plan.block_index_at(target)
		var b := plan.block(bi.x, bi.y)
		var rect: Rect2 = b.rect
		if _cell_of(rect.get_center()) != cell:
			_why("cell")
			continue
		if not KIND_WEIGHTS.has(int(b.district)) or int(b.kind) != CityPlan.BlockKind.BUILDINGS:
			_why("district")
			continue
		if b.has("site") or b.has("grounds") or b.has("hospital"):
			_why("claimed")
			continue
		if plan.macro.skyline_boost(rect.get_center()) > 0.3 or Landmarks.claims(rect) or plan.river_block(bi.x, bi.y):
			_why("core")
			continue
		if _taken(plan, bi):
			_why("taken")
			continue
		var kind := _pick_kind(int(b.district), h01([plan.seed, cell.x, cell.y, t, "wkind"]))
		if kind < 0:
			_why("kind")
			continue
		var s := _site(plan, bi, kind, [plan.seed, cell.x, cell.y, t])
		if s.is_empty():
			_why("site")
			continue
		s.cell = cell
		s.kind = kind
		var names: Array = NAMES[kind]
		s.name = String(names[absi(hash([plan.seed, cell.y, cell.x, kind, "wname"])) % names.size()])
		s.seed = absi(hash([plan.seed, cell.x, cell.y, "wseed"]))
		out.merge(s)
		return out
	return out


## Whether another feature already has block `bi` (the fire station's lot, the police station's
## site, Broadway's frontage).
static func _taken(plan: CityPlan, bi: Vector2i) -> bool:
	var c: Vector2 = (plan.block(bi.x, bi.y).rect as Rect2).get_center()
	var fs := FireStation.for_cell(plan, FireStation._cell_of(c))
	if not fs.is_empty() and fs.block == bi:
		return true
	if not PoliceStation.station_on(plan, bi.x, bi.y).is_empty():
		return true
	return Broadway.block_side(plan, bi.x, bi.y) != 0


static func _why(k: String) -> void:
	if _debug:
		why[k] = int(why.get(k, 0)) + 1


static func _pick_kind(district: int, roll: float) -> int:
	var w: Array = KIND_WEIGHTS[district]
	if force_kind >= 0:
		return force_kind
	var total := 0.0
	for x: float in w:
		total += x
	if total <= 0.0:
		return -1
	var r := roll * total
	for k in w.size():
		r -= float(w[k])
		if r < 0.0:
			return k
	return w.size() - 1


## A site of `kind` on block `bi`: {"block", "site" (Rect2), "side", "frame" (Industrial.frame),
## "road" [axis, index], "lots" (seeds), "builder", "L", "D"} or {}.
static func _site(plan: CityPlan, bi: Vector2i, kind: int, salt: Array) -> Dictionary:
	var b := plan.block(bi.x, bi.y)
	var lots := plan.lots(bi.x, bi.y)
	if lots.is_empty() or not (lots[0] as Dictionary).has("cell"):
		return {}
	var target: Vector2 = SIZES[kind][0]
	var smin: Vector2 = SIZES[kind][1]
	var smax: Vector2 = SIZES[kind][2]
	var inner := (b.rect as Rect2).grow(-plan.sidewalk_width)
	var cs: Vector2 = (lots[0].cell as Rect2).size
	var nx := maxi(1, roundi(inner.size.x / cs.x))
	var nz := maxi(1, roundi(inner.size.y / cs.y))
	var roads := [[CityPlan.AXIS_Z, bi.y], [CityPlan.AXIS_Z, bi.y + 1], [CityPlan.AXIS_X, bi.x], [CityPlan.AXIS_X, bi.x + 1]]
	var k0 := absi(hash(salt + ["wside"])) % 4
	if _debug:
		print("WSITE kind %d district %d inner %s cell %s n %d x %d lots %d" % [kind, int(b.district), str(inner.size.round()), str(cs.round()), nx, nz, lots.size()])
	var dropped := plan.dropped_cells(bi.x, bi.y)
	var clear_zone := plan.macro.runway_clear_zone()
	for o in 4:
		var side := (k0 + o) % 4
		var along_n := nx if side < 2 else nz
		var depth_n := nz if side < 2 else nx
		var ca := cs.x if side < 2 else cs.y
		var cd := cs.y if side < 2 else cs.x
		var ku0 := clampi(ceili(target.x / ca - 0.2), 1, along_n)
		var kv0 := clampi(ceili(target.y / cd - 0.2), 1, depth_n)
		for dk: Vector2i in [Vector2i(0, 0), Vector2i(-1, 0), Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, -1)]:
			var s := _try_site(plan, bi, lots, inner, cs, side, along_n, ca, cd, clampi(ku0 + dk.x, 1, along_n), clampi(kv0 + dk.y, 1, depth_n),
				smin, smax, salt, dropped, clear_zone, roads)
			if not s.is_empty():
				return s
	return {}


static func _try_site(plan: CityPlan, bi: Vector2i, lots: Array, inner: Rect2, cs: Vector2, side: int, along_n: int, ca: float, cd: float,
		ku: int, kv: int, smin: Vector2, smax: Vector2, salt: Array, dropped: Array, clear_zone: Rect2, roads: Array) -> Dictionary:
	var L := float(ku) * ca
	var D := float(kv) * cd
	if L < smin.x or D < smin.y or L > smax.x or D > smax.y:
		_why("size")
		return {}
	# Off-centre along the street by a hash, so not every one sits mid-block.
	var i0 := (along_n - ku) / 2
	if along_n - ku > 1:
		i0 = absi(hash(salt + ["wslide"])) % (along_n - ku + 1)
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
	for r: Rect2 in dropped:
		if r.intersects(site.grow(-0.5)):
			_why("dropped")
			return {}
	if clear_zone.size.x > 0.0 and clear_zone.intersects(site):
		_why("approach")
		return {}
	var mine: Array[int] = []
	var builder := -1
	var bad := false
	for lot: Dictionary in lots:
		if site.grow(-0.5).has_point(lot.center):
			# A courtyard lot builds its garden before any claim is asked; a car park lot
			# likewise: a site takes neither.
			bad = bad or bool(lot.yard) or bool(lot.get("parking", false))
			mine.append(int(lot.seed))
			if builder == -1:
				builder = int(lot.seed)
	# A cell the gap roll left empty is fine (the grounds cover it; HouseKit.extra_lots() asks
	# covers()), but most of the site must be lots.
	if bad or mine.size() * 10 < ku * kv * 6:
		_why("lots")
		return {}
	if plan.macro.freeway and plan.macro.freeway.blocks_rect(site.grow(11.0), 3.0):
		return {}
	var rail := LightRail.of(plan)
	if rail != null and rail.blocks_rect(site.grow(2.0), 2.0):
		return {}
	var lo := INF
	var hi := -INF
	for q: Vector2 in [site.position, site.end, Vector2(site.position.x, site.end.y), Vector2(site.end.x, site.position.y), site.get_center()]:
		var r := plan.macro.relief_at(q)
		lo = minf(lo, r)
		hi = maxf(hi, r)
	if hi - lo > MAX_RELIEF:
		_why("relief")
		return {}
	var road: Array = roads[side]
	var f := Industrial.frame(site, side)
	var mid := Industrial.fp(f, L * 0.5, 0.0)
	if not plan.road_open(int(road[0]), int(road[1]), mid.y if int(road[0]) == CityPlan.AXIS_X else mid.x):
		return {}
	return {"block": bi, "site": site, "side": side, "frame": f, "road": road, "lots": mine,
		"builder": builder, "L": L, "D": D}
	return {}


## The site on block (bx, bz), or {}.
static func site_on(plan: CityPlan, bx: int, bz: int) -> Dictionary:
	if not enabled or plan.macro == null:
		return {}
	var b := plan.block(bx, bz)
	var s := for_cell(plan, _cell_of((b.rect as Rect2).get_center()))
	if not s.is_empty() and s.block == Vector2i(bx, bz):
		return s
	return {}


## True when `lot` of block (bx, bz) is a place of worship's (CityChunk._build_lot asks, after
## its rolls and the stations' claims).
static func claims(plan: CityPlan, bx: int, bz: int, lot: Dictionary) -> bool:
	var s := site_on(plan, bx, bz)
	return not s.is_empty() and (s.lots as Array).has(int(lot.seed))


## Whether the cell `cell` (a lot-grid cell of block (bx, bz)) is in a site: HouseKit.extra_lots()
## puts no house there.
static func covers(plan: CityPlan, bx: int, bz: int, cell: Rect2) -> bool:
	var s := site_on(plan, bx, bz)
	return not s.is_empty() and (s.site as Rect2).grow(-0.5).has_point(cell.get_center())


## Every site whose rect comes within `margin` of `rect` (true world XZ).
static func near_rect(plan: CityPlan, rect: Rect2, margin: float = 0.0) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not enabled or plan == null or plan.macro == null:
		return out
	var r := rect.grow(margin)
	var c0 := _cell_of(r.position) - Vector2i.ONE
	var c1 := _cell_of(r.end) + Vector2i.ONE
	for cx in range(c0.x, c1.x + 1):
		for cz in range(c0.y, c1.y + 1):
			var s := for_cell(plan, Vector2i(cx, cz))
			if not s.is_empty() and (s.site as Rect2).intersects(r):
				out.append(s)
	return out


## For StreetWear's `blocked` list: [centre, radius] of every site near `rect`, its half-diagonal
## plus `margin`.
static func blocked_near(plan: CityPlan, rect: Rect2, margin: float) -> Array:
	var out: Array = []
	for s: Dictionary in near_rect(plan, rect, margin + 60.0):
		var site: Rect2 = s.site
		out.append([site.get_center(), site.size.length() * 0.5 + margin])
	return out


# --- Building it ---------------------------------------------------------------------------------

## The site's frame as a transform in the chunk (true world): origin at the middle of its street
## edge on the pavement top, +z out toward the street, +x along it.
static func site_xform(ch: CityChunk, s: Dictionary) -> Transform3D:
	var f: Dictionary = s.frame
	var n2: Vector2 = f.n
	var front := Industrial.fp(f, float(s.L) * 0.5, 0.0)
	var outward := Vector3(-n2.x, 0.0, -n2.y)
	var basis := Basis(Vector3.UP.cross(outward), Vector3.UP, outward)
	return Transform3D(basis, Vector3(front.x, ch._gy(front.x, front.y) + CityChunk.SIDEWALK_TOP, front.y))


## Builds the place of worship whose site holds `lot`, if `lot` is its builder; the other lots of
## the site build nothing. Called from CityChunk._build_lot in place of a Building.
static func build_lot(ch: CityChunk, lot: Dictionary) -> void:
	var s := site_on(ch.plan, ch.ix, ch.iz)
	if s.is_empty():
		return
	ch._lot_rects.append(Rect2((lot.center as Vector2) - (lot.size as Vector2) * 0.5, lot.size))
	if int(lot.seed) != int(s.builder):
		return
	ch.building_count += 1
	var xf := site_xform(ch, s)
	var plan := WorshipBuild.plan_of(s)
	if ch.level != CityChunk.Level.FULL:
		_far(ch, xf, plan)
		if not ch.capturing:
			_zone(ch, xf, s, plan)
		return
	var node := Node3D.new()
	node.name = "Worship_%s" % KIND_NAMES[int(s.kind)]
	node.transform = xf
	node.add_to_group("worship")
	node.set_meta("site", s)
	ch.add_child(node)
	var body := StaticBody3D.new()
	body.name = "Body"
	body.collision_layer = 1
	body.collision_mask = 0
	body.add_to_group(Sanctuary.BODY_GROUP)
	node.add_child(body)
	WorshipBuild.build(ch, node, body, s, plan)
	_zone(ch, xf, s, plan)
	for ob: Array in plan.get("occluders", []):
		ch._occluder_boxes.append([xf, ob[0], ob[1]])


## The Sanctuary zone over the whole site, up past the tallest thing on it.
static func _zone(ch: CityChunk, xf: Transform3D, s: Dictionary, plan: Dictionary) -> void:
	var L: float = s.L
	var D: float = s.D
	var top: float = plan.get("top", 20.0) + 4.0
	var c := xf * Vector3(0.0, top * 0.5 - 1.0, -D * 0.5)
	var zone := Sanctuary.add_zone(ch, c, Vector3(L * 0.5 + 0.5, top * 0.5 + 1.0, D * 0.5 + 0.5), xf.basis.get_euler().y)
	zone.name = "WorshipZone"


## LOD chunks and the far city: the building's masses as far boxes (old path, no code), its pitched
## roofs as two slabs tilted about the ridge (rotation times scale: a skewed box lights wrong).
static func _far(ch: CityChunk, xf: Transform3D, plan: Dictionary) -> void:
	var b := xf.basis
	for fb: Array in plan.far:
		if fb[0] is String:
			# ["roof", eave centre, length along the ridge, span, rise, ridge along local z, colour]
			var c0: Vector3 = fb[1]
			var length: float = fb[2]
			var span: float = fb[3]
			var rise: float = fb[4]
			var along_z: bool = fb[5]
			var pitch := atan2(rise, span * 0.5)
			var slope := Vector2(span * 0.5, rise).length()
			for side: float in [-1.0, 1.0]:
				var lc := c0 + Vector3.UP * (rise * 0.5)
				var rb: Basis
				var sz: Vector3
				if along_z:
					lc.x += side * span * 0.25
					rb = Basis(Vector3(0, 0, 1), -side * pitch)
					sz = Vector3(slope, 0.35, length)
				else:
					lc.z += side * span * 0.25
					rb = Basis(Vector3(1, 0, 0), side * pitch)
					sz = Vector3(length, 0.35, slope)
				var c: Vector3 = xf * lc
				ch._batch.add("lod_box", PropFactory.unit_box(), Transform3D(b * rb * Basis.from_scale(sz), c - Vector3(0.0, ch._gy(c.x, c.z), 0.0)),
					fb[6], Color(0.2, 0.05, 0.37, 0.0))
			continue
		var c: Vector3 = xf * (fb[0] as Vector3)
		var size: Vector3 = fb[1]
		var at := c - Vector3(0.0, ch._gy(c.x, c.z), 0.0)
		ch._batch.add("lod_box", PropFactory.unit_box(), Transform3D(b * Basis.from_scale(size), at), fb[2], Color(0.2, 0.05, 0.37, 0.0))
		if size.y > 3.0:
			ch._add_lod_shape(size if absf(b.x.x) > 0.7 else Vector3(size.z, size.y, size.x), c)
