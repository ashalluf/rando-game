class_name StarBoulevard
extends RefCounted
## The walk of fame (2026-10-05, fleet wave 2 "star-boulevard"): ONE boulevard through midtown,
## north-west of downtown under the hills, whose pavements are laid with terrazzo stars - every
## name invented, never a real person - with tourist souvenir shops along it, a grand movie
## palace set back behind a forecourt of concrete slabs pressed with (invented) hands, shoes and
## signatures, costumed street characters (original costumes, nobody's copyrighted character)
## posing on the stars, sightseeing buses at the kerb and neon after dark.
##
## WHICH boulevard is a hash of the seed, never placed: every east-west road at least
## MIN_WIDTH wide inside SEARCH whose blocks on both sides run MIN_RUN or more in a row as plain
## MIDTOWN building blocks (no site, grounds, river, school) is a candidate; the seed picks one
## and a stretch of at most MAX_RUN blocks of it (`plan_for()`, cached per seed, pure). Nothing
## about the blocks moves: CityChunk asks this AFTER its own rolls, from five one-line hooks:
## - `claims()` / `build_lot()` (CityChunk._build_lot, after Broadway's): the palace's lot. The
##   palace is BroadwayTheatre's builder handed a frame set back FORECOURT metres; the forecourt
##   in front of it is built here (`_forecourt()`).
## - `dress()` (after HistoricCore's): a building fronting the walk keeps its lot and rolls, and is
##   held low (HEIGHT_LIMIT), its shops named from STRIP_SHOPS (Building.name_pool) with more
##   blade signs (lit after dark).
## - `lamp()` (each pavement lamp): the walk's lamps carry a neon star medallion.
## - `steps()` (the FULL block's pavement steps, before the parked cars and walkers): the
##   terrazzo band (`_band()`, shaders/walk_of_fame.gdshader), the souvenir stands, the lamp
##   medallions, the sightseeing buses and the costumed characters (StreetCharacter), one a step.
## - `blocks_parking()` (CityChunk._park_car, after its rolls): the buses' kerb.
## LOD chunks and the far city get the palace's far boxes (BroadwayTheatre) and nothing else.
##
## Off (STAR_BOULEVARD=0 in the environment): none of it, the A/B.

static var enabled: bool = OS.get_environment("STAR_BOULEVARD") != "0"

## The boulevard: at least this wide (a midtown avenue), its blocks plain midtown both sides.
const MIN_WIDTH := 23.9
const MIN_RUN := 4
const MAX_RUN := 6
## Where to look (true world): midtown north-west of downtown, under the hills.
const SEARCH := Rect2(300.0, -2900.0, 1350.0, 1300.0)
## The band of stars: from BAND_FROM to BAND_FROM + BAND metres in from the kerb (the plain inner
## pavement slab, past Kerbs' ring), stopping END_CLEAR short of each corner.
const BAND_FROM := 2.6
const BAND := 1.4
const BAND_LIFT := 0.008
const END_CLEAR := 4.2
const BAND_DRAW := 160.0
## The 1920s-50s main street was built low.
const HEIGHT_LIMIT := 34.0
const BLADE_CHANCE := 0.85
## The palace: smallest lot (frontage, depth), the forecourt's depth.
const PALACE_MIN := Vector2(24.0, 40.0)
const FORECOURT := 10.0
## Souvenir goods on the pavement: how far in from the kerb, the step, the odds.
const GOODS_FROM_KERB := 3.45
const GOODS_STEP := 4.6
const GOODS_ODDS := 0.5
const CORNER_CLEAR := 7.0
## Costumed characters per block face, and the kerb the sightseeing buses keep.
const MAX_CHARACTERS := 3
const BUS_ZONE := 30.0
const BUSES := 2

## The palace's flanking shops and the pavement's feather flags (invented; drawn in their own
## geometry, never through Building.SHOP_NAMES, whose window vinyl is a generated table).
const STAR_SHOPS := ["STAR SOUVENIRS", "WALK OF STARS GIFTS", "T-SHIRTS 3 FOR 10", "CELEBRITY MAPS",
	"MOVIE POSTERS", "COSTUME RENTAL", "STARLIGHT GIFTS", "POSTCARDS", "AUTOGRAPHS", "LUCKY STAR CANDY",
	"PREMIERE CAFE", "TOURS & TICKETS"]
## The shops along the walk: Building's own names that a tourist strip has (cameras, records,
## books, tattoo, thrift, sunglasses, coffee, pizza, discount, perfume, gifts, hats, electronics).
const STRIP_SHOPS := ["CAMERA", "RECORDS", "BOOKS", "TATTOO", "THRIFT", "OPTICAL", "COFFEE STOP",
	"PIZZA", "DISCOUNT CITY", "PERFUMES", "REGALOS", "SOMBREROS", "ELECTRONICA", "DONUT HOLE", "BOBA"]
## The feather flags' words.
const FLAGS := ["SOUVENIRS", "GIFTS", "T-SHIRTS", "STAR MAPS"]

## The palace (BroadwayTheatre's spec format; Broadway.THEATRES has the keys). Invented.
const PALACE := {"id": "starlight_palace", "num": 0, "name": "THE GRAND CELESTE", "style": Broadway.Style.SPANISH,
	"front_h": 26.0, "sign_h": 17.0, "marquee": "v",
	"titles": ["WORLD PREMIERE", "THE GOLDEN HOUR", "RED CARPET 7PM", "STARS IN PERSON"],
	"enamel": Color(0.50, 0.10, 0.12), "neon": Color(1.0, 0.36, 0.16), "letters": Color(1.0, 0.86, 0.48),
	"terrazzo": [Color(0.50, 0.16, 0.13), Color(0.12, 0.12, 0.13)], "tower": 12.0, "roof_sign": true, "shops": STAR_SHOPS}

static var _plans: Dictionary = {}
static var _pool: PackedInt32Array = PackedInt32Array()
static var _material: ShaderMaterial
static var _meshes: Dictionary = {}


static func h01(parts: Array) -> float:
	return float(absi(hash(parts)) % 100003) / 100003.0


# --- The plan -------------------------------------------------------------------------------------

## {"road": index of the AXIS_Z road, "z", "width", "name", "k0", "k1" (the stretch's block x
## indices, inclusive), "palace": {"block", "lot", "side", "spec"} or {}} - or {} with no walk.
static func plan_for(plan: CityPlan) -> Dictionary:
	if plan == null or not enabled or plan.macro == null:
		return {}
	if _plans.has(plan.seed):
		return _plans[plan.seed]
	var out := {}
	_plans[plan.seed] = out
	var lo := plan.block_index_at(SEARCH.position)
	var hi := plan.block_index_at(SEARCH.end)
	var cands: Array = []
	for r in range(lo.y + 1, hi.y + 1):
		if plan.road_width(CityPlan.AXIS_Z, r) < MIN_WIDTH:
			continue
		var run := 0
		var start := 0
		for k in range(lo.x, hi.x + 2):
			var ok := k <= hi.x and _good_block(plan, k, r - 1) and _good_block(plan, k, r)
			if ok:
				if run == 0:
					start = k
				run += 1
			if not ok or k == hi.x + 1:
				if run >= MIN_RUN:
					cands.append([r, start, run])
				run = 0
	if cands.is_empty():
		return out
	var pick: Array = cands[absi(hash([plan.seed, "star_blvd"])) % cands.size()]
	var n := mini(int(pick[2]), MAX_RUN)
	var k0 := int(pick[1]) + absi(hash([plan.seed, "star_blvd_at"])) % (int(pick[2]) - n + 1)
	var r := int(pick[0])
	out.road = r
	out.z = plan.road_pos(CityPlan.AXIS_Z, r)
	out.width = plan.road_width(CityPlan.AXIS_Z, r)
	out.name = plan.road_name(CityPlan.AXIS_Z, r)
	out.k0 = k0
	out.k1 = k0 + n - 1
	out.palace = {}
	out.palace = _pick_palace(plan, out)
	return out


static func _good_block(plan: CityPlan, bx: int, bz: int) -> bool:
	var b := plan.block(bx, bz)
	return b.district == CityPlan.District.MIDTOWN and b.kind == CityPlan.BlockKind.BUILDINGS \
			and not b.has("site") and not b.has("grounds") and not b.has("chinatown") and not plan.river_block(bx, bz)


## -1 for a block on the walk's north side (the boulevard along its +z edge), +1 the south, else 0.
static func block_side(plan: CityPlan, bx: int, bz: int) -> int:
	var p := plan_for(plan)
	if p.is_empty() or bx < int(p.k0) or bx > int(p.k1):
		return 0
	if bz == int(p.road) - 1:
		return -1
	if bz == int(p.road):
		return 1
	return 0


## The boulevard's kerb line on a block of `side`, and the inward direction (z).
static func kerb_z(rect: Rect2, side: int) -> float:
	return rect.end.y if side < 0 else rect.position.y


## True when `lot` of a walk block faces the boulevard.
static func lot_fronts(plan: CityPlan, bx: int, bz: int, side: int, lot: Dictionary) -> bool:
	if side == 0 or lot.get("yard", false):
		return false
	var inner := (plan.block(bx, bz).rect as Rect2).grow(-plan.sidewalk_width)
	var c: Vector2 = lot.center
	var s: Vector2 = lot.size
	if side < 0:
		return c.y + s.y * 0.5 > inner.end.y - 3.0
	return c.y - s.y * 0.5 < inner.position.y + 3.0


static func _claimed(plan: CityPlan, bx: int, bz: int, lot: Dictionary) -> bool:
	return FireStation.claims(plan, bx, bz, lot) or PoliceStation.claims(plan, bx, bz, lot) \
			or Worship.claims(plan, bx, bz, lot) or Broadway.claims(plan, bx, bz, lot) \
			or Chinatown.claims(plan, bx, bz, lot) or CarDealers.claims(plan, bx, bz, lot) \
			or CivicBuildings.claims(plan, bx, bz, lot)


static func _pick_palace(plan: CityPlan, p: Dictionary) -> Dictionary:
	var mid := (plan.block(int(p.k0), int(p.road)).rect as Rect2).position.x
	mid = (mid + (plan.block(int(p.k1), int(p.road)).rect as Rect2).end.x) * 0.5
	var best := {}
	var best_score := INF
	for k in range(int(p.k0), int(p.k1) + 1):
		for side: int in [-1, 1]:
			var bz := int(p.road) - 1 if side < 0 else int(p.road)
			for lot: Dictionary in plan.lots(k, bz):
				if not lot_fronts(plan, k, bz, side, lot) or lot.get("parking", false):
					continue
				var s: Vector2 = lot.size
				if s.x < PALACE_MIN.x:
					continue
				# The lot behind it, if it lines up, takes the auditorium (the walk's lots are
				# shallow: a palace is two lots deep).
				var behind := _lot_behind(plan, k, bz, side, lot)
				var depth := s.y
				if not behind.is_empty():
					depth = absf((lot.center as Vector2).y - float(side) * s.y * 0.5 - ((behind.center as Vector2).y + float(side) * (behind.size as Vector2).y * 0.5))
				if depth < PALACE_MIN.y:
					continue
				var rect := Rect2((lot.center as Vector2) - s * 0.5, s)
				if not behind.is_empty():
					rect = rect.merge(Rect2((behind.center as Vector2) - (behind.size as Vector2) * 0.5, behind.size))
				if plan.macro.freeway != null and plan.macro.freeway.blocks_rect(rect, 14.0):
					continue
				var rail := LightRail.of(plan)
				if rail != null and rail.blocks_rect(rect, 2.0):
					continue
				if _claimed(plan, k, bz, lot) or (not behind.is_empty() and _claimed(plan, k, bz, behind)):
					continue
				var score := absf((lot.center as Vector2).x - mid) + h01([plan.seed, lot.seed, "sb_palace"]) * 80.0
				if score < best_score:
					best_score = score
					best = {"block": Vector2i(k, bz), "lot": lot, "behind": behind, "depth": depth, "side": side, "spec": PALACE}
	return best


## The lot straight behind `lot` (the same frontage within a few metres, its back to it), or {}.
static func _lot_behind(plan: CityPlan, bx: int, bz: int, side: int, lot: Dictionary) -> Dictionary:
	var c: Vector2 = lot.center
	var s: Vector2 = lot.size
	for o: Dictionary in plan.lots(bx, bz):
		if o.seed == lot.seed or o.get("yard", false) or o.get("parking", false):
			continue
		var oc: Vector2 = o.center
		var os: Vector2 = o.size
		if absf(oc.x - c.x) > 5.0 or absf(os.x - s.x) > 8.0:
			continue
		# Behind: further from the boulevard, touching (within a lot gap).
		var gap := (c.y + float(side) * s.y * 0.5) - (oc.y - float(side) * os.y * 0.5)
		if signf(oc.y - c.y) == float(side) and absf(gap) < 6.0:
			return o
	return {}


## The palace's lot (the front one), or the lot behind it it also stands on.
static func palace_on(plan: CityPlan, bx: int, bz: int, lot: Dictionary) -> Dictionary:
	if block_side(plan, bx, bz) == 0:
		return {}
	var pal: Dictionary = plan_for(plan).get("palace", {})
	if pal.is_empty() or pal.block != Vector2i(bx, bz):
		return {}
	if int((pal.lot as Dictionary).seed) == int(lot.seed):
		return pal
	if not (pal.behind as Dictionary).is_empty() and int((pal.behind as Dictionary).seed) == int(lot.seed):
		return {"behind_only": true}
	return {}


# --- Hooks ----------------------------------------------------------------------------------------

## CityChunk._build_lot(): is this lot the palace's?
static func claims(plan: CityPlan, bx: int, bz: int, lot: Dictionary) -> bool:
	return not palace_on(plan, bx, bz, lot).is_empty()


## CityChunk._build_lot(): the palace, set back behind its forecourt (FULL), or its far boxes.
static func build_lot(ch: CityChunk, lot: Dictionary) -> void:
	var pal := palace_on(ch.plan, ch.ix, ch.iz, lot)
	if pal.is_empty() or pal.has("behind_only"):
		# The lot behind is the auditorium's, built with the front lot.
		if not pal.is_empty():
			ch._lot_rects.append(Rect2((lot.center as Vector2) - (lot.size as Vector2) * 0.5, lot.size))
		return
	var f := palace_frame(ch, pal)
	var p := pal.duplicate()
	p.frame = f
	BroadwayTheatre.build(ch, p)
	if ch.level == CityChunk.Level.FULL:
		_forecourt(ch, pal)


## The palace's frame (BroadwayTheatre's [Transform3D, frontage, depth, to_kerb]): its front
## FORECOURT metres back from the lot's street edge, facing the boulevard.
static func palace_frame(ch: CityChunk, pal: Dictionary) -> Array:
	var lot: Dictionary = pal.lot
	var c: Vector2 = lot.center
	var s: Vector2 = lot.size
	var side: int = pal.side
	var front := c.y - float(side) * s.y * 0.5
	var fz := front + float(side) * FORECOURT
	var out := Vector3(0.0, 0.0, -float(side))
	var x_axis := Vector3.UP.cross(out)
	var g := ch._gy(c.x, fz)
	var xf := Transform3D(Basis(x_axis, Vector3.UP, out), Vector3(c.x, g + CityChunk.SIDEWALK_TOP, fz))
	return [xf, s.x, float(pal.get("depth", s.y)) - FORECOURT, FORECOURT + ch.plan.sidewalk_width]


## CityChunk._build_lot(): a building fronting the walk is a low main-street block of souvenir
## shops. Set before it generates (both levels, so the far copy agrees); no roll moves.
static func dress(ch: CityChunk, lot: Dictionary, building: Building) -> void:
	var side := block_side(ch.plan, ch.ix, ch.iz)
	if side == 0 or not lot_fronts(ch.plan, ch.ix, ch.iz, side, lot):
		return
	building.max_height = minf(building.max_height, HEIGHT_LIMIT)
	building.min_height = minf(building.min_height, building.max_height * 0.85)
	building.name_pool = shop_pool()
	building.kit_blade_chance = BLADE_CHANCE


## The indices of STRIP_SHOPS in Building.SHOP_NAMES.
static func shop_pool() -> PackedInt32Array:
	if _pool.is_empty():
		for name: String in STRIP_SHOPS:
			var i := Building.SHOP_NAMES.find(name)
			if i >= 0:
				_pool.append(i)
	return _pool


## CityChunk._build_sidewalk_props(): each pavement lamp; the walk's own get a medallion later.
static func lamp(ch: CityChunk, p: Vector2, inward: Vector2) -> void:
	var side := block_side(ch.plan, ch.ix, ch.iz)
	if side == 0 or absf(inward.y - float(side)) > 0.1:
		return
	var lamps: Array = ch.get_meta("sb_lamps", [])
	lamps.append(p)
	ch.set_meta("sb_lamps", lamps)


## CityChunk._park_car(): the sightseeing buses' kerb in front of the palace.
static func blocks_parking(plan: CityPlan, p: Vector3) -> bool:
	var z := bus_zone(plan)
	return z.has_area() and z.has_point(Vector2(p.x, p.z))


## The buses' stretch of parking lane (true world), or an empty rect.
static func bus_zone(plan: CityPlan) -> Rect2:
	var p := plan_for(plan)
	if p.is_empty() or (p.palace as Dictionary).is_empty():
		return Rect2()
	var pal: Dictionary = p.palace
	var lane := float(p.z) + float(pal.side) * CityPlan.parking_offset(float(p.width))
	var cx: float = (pal.lot.center as Vector2).x
	return Rect2(cx - BUS_ZONE * 0.5, lane - 2.0, BUS_ZONE, 4.0)


## The FULL block's steps (CityChunk._block_steps, before the parked cars and the walkers).
static func steps(ch: CityChunk, block: Dictionary) -> Array[Callable]:
	var out: Array[Callable] = []
	var side := block_side(ch.plan, ch.ix, ch.iz)
	if side == 0 or ch.level != CityChunk.Level.FULL or ch.capturing:
		return out
	var rect: Rect2 = block.rect
	out.append(func() -> void: _band(ch, rect, side))
	out.append(func() -> void: _street(ch, rect, side))
	out.append(func() -> void: _buses(ch))
	for i in MAX_CHARACTERS:
		out.append(func() -> void: _spawn_character(ch, rect, side, i))
	return out


# --- The band of stars ----------------------------------------------------------------------------

static func material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = load("res://shaders/walk_of_fame.gdshader")
		_material.set_shader_parameter("atlas", load("res://assets/textures/star_boulevard/walk_atlas.png"))
		_material.set_shader_parameter("name_count", StarNames.NAMES.size())
	return _material


## The x range the band covers on a block (whole squares, clear of the corners).
static func band_span(rect: Rect2) -> Vector2:
	return Vector2(ceilf(rect.position.x + END_CLEAR), floorf(rect.end.x - END_CLEAR))


## The band down this block's boulevard pavement: one mesh, a quad strip a metre a step (on the
## relief), cut where an alley's mouth crosses the pavement.
static func _band(ch: CityChunk, rect: Rect2, side: int) -> void:
	var span := band_span(rect)
	if span.y - span.x < 2.0:
		return
	var kz := kerb_z(rect, side)
	# Inward is +z on the south side's block (its kerb at its -z edge), -z on the north side's.
	var inz := 1.0 if side > 0 else -1.0
	var z0 := kz + inz * BAND_FROM
	var z1 := kz + inz * (BAND_FROM + BAND)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# The reader faces the buildings: along runs to their right (+x on the north side).
	var dir := -float(side)
	var salt := 1 if side < 0 else 2
	var x := span.x
	var any := false
	while x < span.y - 0.5:
		var xa := x
		var xb := x + 1.0
		x = xb
		if Alleys.in_mouth(ch.plan, ch.ix, ch.iz, Vector2(xa + 0.5, (z0 + z1) * 0.5)):
			continue
		var pts := [Vector2(xa, z0), Vector2(xb, z0), Vector2(xb, z1), Vector2(xa, z1)]
		var vs: Array[Vector3] = []
		var uvs: Array[Vector2] = []
		for q: Vector2 in pts:
			vs.append(Vector3(q.x, ch._gy(q.x, q.y) + CityChunk.SIDEWALK_TOP + BAND_LIFT, q.y))
			uvs.append(Vector2(q.x * dir, absf(q.y - z0)))
		var order := [0, 1, 2, 0, 2, 3] if side > 0 else [0, 2, 1, 0, 3, 2]
		for i: int in order:
			st.set_normal(Vector3.UP)
			st.set_uv(uvs[i])
			st.set_uv2(Vector2(float(salt), 0.0))
			st.add_vertex(vs[i])
		any = true
	if not any:
		return
	st.generate_tangents()
	var mi := MeshInstance3D.new()
	mi.name = "WalkOfFame"
	mi.mesh = st.commit()
	mi.material_override = material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = BAND_DRAW
	mi.add_to_group("walk_of_fame")
	ch.add_child(mi)


## The forecourt: the slabs of hands and names (the shader's forecourt mode) from the street edge
## of the lot to the palace's front, low walls with planters and palms down both sides, a pair
## of lantern pylons at the street and brass stanchions with velvet ropes.
static func _forecourt(ch: CityChunk, pal: Dictionary) -> void:
	var lot: Dictionary = pal.lot
	var c: Vector2 = lot.center
	var s: Vector2 = lot.size
	var side: int = pal.side
	var front := c.y - float(side) * s.y * 0.5
	var back := front + float(side) * FORECOURT
	var x0 := c.x - s.x * 0.5
	var x1 := c.x + s.x * 0.5
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var steps_x := maxi(int(ceilf(s.x / 2.5)), 1)
	var steps_z := maxi(int(ceilf(FORECOURT / 2.5)), 1)
	var salt := 5 + int(lot.seed) % 97
	for i in steps_x:
		for j in steps_z:
			var xa := lerpf(x0, x1, float(i) / steps_x)
			var xb := lerpf(x0, x1, float(i + 1) / steps_x)
			var za := lerpf(front, back, float(j) / steps_z)
			var zb := lerpf(front, back, float(j + 1) / steps_z)
			var pts := [Vector2(xa, za), Vector2(xb, za), Vector2(xb, zb), Vector2(xa, zb)]
			var order := [0, 1, 2, 0, 2, 3] if side > 0 else [0, 2, 1, 0, 3, 2]
			for k: int in order:
				var q: Vector2 = pts[k]
				st.set_normal(Vector3.UP)
				st.set_uv(Vector2((q.x - x0) * -float(side), absf(q.y - front)))
				st.set_uv2(Vector2(float(salt), 1.0))
				st.add_vertex(Vector3(q.x, ch._gy(q.x, q.y) + CityChunk.SIDEWALK_TOP + 0.012, q.y))
	st.generate_tangents()
	var mi := MeshInstance3D.new()
	mi.name = "PalaceForecourt"
	mi.mesh = st.commit()
	mi.material_override = material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.add_to_group("walk_of_fame")
	ch.add_child(mi)
	# The walls, planters, pylons and stanchions: one vertex-coloured mesh and one collision body.
	var g := ch._gy(c.x, (front + back) * 0.5)
	var root := Node3D.new()
	root.name = "ForecourtFittings"
	root.position = Vector3(c.x, g + CityChunk.SIDEWALK_TOP, front)
	ch.add_child(root)
	var fit := MeshInstance3D.new()
	fit.mesh = forecourt_mesh(s.x, side)
	root.add_child(fit)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	root.add_child(body)
	var inz := float(side)
	for sx: float in [-1.0, 1.0]:
		var wx := sx * (s.x * 0.5 - 0.45)
		LandmarkGeo.shape_box(body, Vector3(wx, 0.4, inz * FORECOURT * 0.5), Vector3(0.9, 0.8, FORECOURT - 0.4))
		LandmarkGeo.shape_box(body, Vector3(sx * PYLON_X, 2.6, inz * 0.8), Vector3(1.0, 5.2, 1.0))
	# The palms in the planters (the chunk's own palm batch: one draw with the street's).
	for sx: float in [-1.0, 1.0]:
		for k in 2:
			var pz := front + float(side) * (3.5 + float(k) * 5.5)
			var px := c.x + sx * (s.x * 0.5 - 0.45)
			var v := absi(hash([ch.plan.seed, lot.seed, "sb_palm", sx, k])) % PropFactory.PALM_VARIANTS
			var sc := 1.25 + 0.25 * h01([ch.plan.seed, lot.seed, "sb_palm_s", sx, k])
			ch._batch.add("palm_%d" % v, PropFactory.palm(v), Transform3D(Basis(Vector3.UP, h01([lot.seed, sx, k]) * TAU).scaled(Vector3.ONE * sc), Vector3(px, CityChunk.SIDEWALK_TOP + 0.8, pz)))
	# Light on the slabs at night from the pylons' lanterns.
	for sx: float in [-1.0, 1.0]:
		var at := Vector3(c.x + sx * PYLON_X, 0.1 + CityChunk.SIDEWALK_TOP, front + float(side) * 2.5)
		ch._batch.add("sb_pool", PropFactory.light_pool(Color(1.0, 1.0, 1.0), 1.3, 1.6), Transform3D(Basis(Vector3.RIGHT, -PI * 0.5).scaled(Vector3(9.0, 1.0, 9.0)), at), Color(1.0, 0.82, 0.6, 0.9))
	ch._batch.set_no_shadow("sb_pool")


const PYLON_X := 7.5


## The forecourt's fittings in its own frame (origin on the lot's street edge at its middle, +z
## toward the palace when `side` is +1, -z when -1): side walls with planters, lantern pylons.
static func forecourt_mesh(width: float, side: int) -> Mesh:
	var key := "fc_%d_%d" % [roundi(width * 10.0), side]
	if _meshes.has(key):
		return _meshes[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var inz := float(side)
	var stone := Color(0.80, 0.70, 0.56)
	var soil := Color(0.20, 0.14, 0.09)
	var gold := Color(0.78, 0.58, 0.24)
	var red := Color(0.55, 0.04, 0.06)
	for sx: float in [-1.0, 1.0]:
		var wx := sx * (width * 0.5 - 0.45)
		# A low wall that is a planter: a coping, the soil inside.
		BroadwayStreet._box(st, Vector3(wx, 0.38, inz * FORECOURT * 0.5), Vector3(0.9, 0.76, FORECOURT - 0.4), stone)
		BroadwayStreet._box(st, Vector3(wx, 0.79, inz * FORECOURT * 0.5), Vector3(0.7, 0.04, FORECOURT - 0.6), soil)
		# The pylon: a stepped base, a fluted-looking shaft (two boxes), a lantern on top.
		var px := sx * PYLON_X
		var pz := inz * 0.8
		BroadwayStreet._box(st, Vector3(px, 0.3, pz), Vector3(1.1, 0.6, 1.1), stone)
		BroadwayStreet._box(st, Vector3(px, 2.6, pz), Vector3(0.8, 4.0, 0.8), Color(0.52, 0.10, 0.10))
		BroadwayStreet._box(st, Vector3(px, 2.6, pz), Vector3(0.9, 3.6, 0.5), Color(0.62, 0.14, 0.12))
		BroadwayStreet._box(st, Vector3(px, 4.7, pz), Vector3(1.0, 0.25, 1.0), gold)
		BroadwayStreet._box(st, Vector3(px, 5.15, pz), Vector3(0.55, 0.65, 0.55), Color(1.0, 0.92, 0.70))
		BroadwayStreet._box(st, Vector3(px, 5.55, pz), Vector3(0.7, 0.12, 0.7), gold)
		# Stanchions with a velvet rope along the slabs' sides, inside the walls.
		var n := 6
		for k in n:
			var z := inz * (1.6 + float(k) * (FORECOURT - 3.0) / float(n - 1))
			var x := sx * (width * 0.5 - 1.4)
			BroadwayStreet.lathe(st, [Vector2(0.16, 0.0), Vector2(0.16, 0.03), Vector2(0.03, 0.06), Vector2(0.025, 0.95), Vector2(0.05, 1.0), Vector2(0.0, 1.04)], 10, gold, Vector3(x, 0.0, z))
			if k + 1 < n:
				var z2 := inz * (1.6 + float(k + 1) * (FORECOURT - 3.0) / float(n - 1))
				var segs := 6
				for q in segs:
					var t0 := float(q) / segs
					var t1 := float(q + 1) / segs
					var y0 := 0.9 - 0.16 * sin(t0 * PI)
					var y1 := 0.9 - 0.16 * sin(t1 * PI)
					var a := Vector3(x, y0, lerpf(z, z2, t0))
					var b := Vector3(x, y1, lerpf(z, z2, t1))
					BroadwayStreet._box(st, (a + b) * 0.5, Vector3(0.05, 0.05 + absf(y1 - y0), absf(b.z - a.z) + 0.01), red)
	st.index()
	var mesh := st.commit()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.55
	mesh.surface_set_material(0, m)
	_meshes[key] = mesh
	return mesh


# --- The pavement: souvenir goods, lamp medallions ------------------------------------------------

static func _street(ch: CityChunk, rect: Rect2, side: int) -> void:
	var plan := ch.plan
	var kz := kerb_z(rect, side)
	var inz := 1.0 if side > 0 else -1.0
	var gz := kz + inz * GOODS_FROM_KERB
	# Facing the street (their front toward the kerb).
	var yaw := 0.0 if side > 0 else PI
	var b := Basis(Vector3.UP, yaw)
	var clear := Vector2(INF, -INF)
	var pal: Dictionary = plan_for(plan).get("palace", {})
	if not pal.is_empty() and pal.block == Vector2i(ch.ix, ch.iz):
		var lot: Dictionary = pal.lot
		clear = Vector2((lot.center as Vector2).x - (lot.size as Vector2).x * 0.5 - 1.0, (lot.center as Vector2).x + (lot.size as Vector2).x * 0.5 + 1.0)
	var x := rect.position.x + CORNER_CLEAR
	var i := 0
	while x < rect.end.x - CORNER_CLEAR:
		var skip := x > clear.x and x < clear.y or Alleys.in_mouth(plan, ch.ix, ch.iz, Vector2(x, gz))
		if not skip and h01([plan.seed, ch.ix, ch.iz, "sb_goods", i]) < GOODS_ODDS:
			var kind := h01([plan.seed, ch.ix, ch.iz, "sb_goods_kind", i])
			var at := Vector3(x, CityChunk.SIDEWALK_TOP, gz)
			if kind < 0.3:
				ch._batch.add("sb_rack", BroadwayStreet.rack_mesh(), Transform3D(Basis(Vector3.UP, yaw + PI * 0.5), at))
			elif kind < 0.55:
				ch._batch.add("sb_spinner", spinner_mesh(), Transform3D(b.rotated(Vector3.UP, kind * 9.0), at))
			elif kind < 0.8:
				ch._batch.add("sb_table", souvenir_table_mesh(), Transform3D(b, at))
			else:
				ch._batch.add("sb_board", map_board_mesh(), Transform3D(b, at + Vector3(0.0, 0.0, -inz * 0.4)))
			# A feather flag beside some of them, the shop's word up it.
			if h01([plan.seed, ch.ix, ch.iz, "sb_flag", i]) < FLAG_ODDS:
				var f := absi(hash([plan.seed, ch.ix, ch.iz, "sb_flag_k", i])) % FLAGS.size()
				ch._batch.add("sb_flag_%d" % f, flag_mesh(f), Transform3D(Basis(Vector3.UP, yaw + 0.3), at + Vector3(1.2, 0.0, -inz * 0.15)))
		x += GOODS_STEP
		i += 1
	for key in ["sb_rack", "sb_spinner", "sb_table", "sb_board", "sb_flag_0", "sb_flag_1", "sb_flag_2", "sb_flag_3"]:
		ch._batch.set_shadow_distance(key, 40.0)
	# The lamps' neon stars, on the street side of each pole, facing along the boulevard.
	for p: Vector2 in ch.get_meta("sb_lamps", []):
		# The mesh's arm runs to +z: toward the pole on the south side, turned round on the north.
		var at := Vector3(p.x, CityChunk.SIDEWALK_TOP + MEDALLION_Y, p.y - inz * MEDALLION_ARM)
		ch._batch.add("sb_medal", medallion_mesh(), Transform3D(Basis(Vector3.UP, 0.0 if side > 0 else PI), at))
	ch._batch.set_no_shadow("sb_medal")


const MEDALLION_Y := 4.1
const FLAG_ODDS := 0.45
const FLAG_COLORS := [Color(0.85, 0.06, 0.10), Color(0.98, 0.78, 0.08), Color(0.10, 0.25, 0.75), Color(0.95, 0.40, 0.05)]
const MEDALLION_ARM := 0.62


## A feather flag: a pole in a cross base, a tall narrow banner curved like a sail, the word
## FLAGS[k] up it on both faces (FreewayKit's TextMesh geometry, merged).
static func flag_mesh(k: int) -> Mesh:
	var key := "flag_%d" % k
	if _meshes.has(key):
		return _meshes[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pole := Color(0.75, 0.76, 0.78)
	BroadwayStreet._box(st, Vector3(0.0, 0.02, 0.0), Vector3(0.6, 0.04, 0.06), Color(0.15, 0.15, 0.16))
	BroadwayStreet._box(st, Vector3(0.0, 0.02, 0.0), Vector3(0.06, 0.04, 0.6), Color(0.15, 0.15, 0.16))
	BroadwayStreet.lathe(st, [Vector2(0.014, 0.0), Vector2(0.014, 3.0), Vector2(0.0, 3.02)], 6, pole)
	var col: Color = FLAG_COLORS[k % FLAG_COLORS.size()]
	# The banner: from the pole out 0.62 m, 0.6 m up to 3 m, the top edge curving over and down.
	var rows := 12
	var cols := 4
	var grid: Array = []
	for j in rows + 1:
		var t := float(j) / rows
		var row: Array[Vector3] = []
		for i in cols + 1:
			var u := float(i) / cols
			var top := 3.0 - 0.55 * u * u
			var y := lerpf(0.6, top, t)
			var x := 0.03 + u * 0.62 * (1.0 - 0.12 * t)
			var z := 0.05 * sin(u * PI) * (0.5 + t)
			row.append(Vector3(x, y, z))
		grid.append(row)
	for j in rows:
		for i in cols:
			var a: Vector3 = grid[j][i]
			var b: Vector3 = grid[j][i + 1]
			var c: Vector3 = grid[j + 1][i + 1]
			var d: Vector3 = grid[j + 1][i]
			var n := (b - a).cross(d - a).normalized()
			BroadwayStreet.tri(st, [a, b, c], [n, n, n], [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO], col, n)
			BroadwayStreet.tri(st, [a, c, d], [n, n, n], [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO], col, n)
			BroadwayStreet.tri(st, [a, b, c], [-n, -n, -n], [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO], col, -n)
			BroadwayStreet.tri(st, [a, c, d], [-n, -n, -n], [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO], col, -n)
	# The word, reading upward, on both faces.
	var geo: Array = FreewayKit.text_geo(str(FLAGS[k]), 0.26)
	var verts: PackedVector3Array = geo[0]
	var idx: PackedInt32Array = geo[1]
	var width: float = geo[2]
	var sc := minf(1.0, 2.0 / maxf(width, 0.01))
	var ink := Color(1, 1, 1) if col.get_luminance() < 0.6 else Color(0.08, 0.08, 0.1)
	for face: float in [1.0, -1.0]:
		var xf := Transform3D(Basis(Vector3(0, 1, 0), Vector3(-1, 0, 0) * face, Vector3(0, 0, face)).scaled(Vector3(1.0, sc, 1.0)), Vector3(0.33, 1.75, 0.06 * face + 0.03))
		var n := Vector3(0, 0, face)
		for t in range(0, idx.size(), 3):
			var vs := [xf * verts[idx[t]], xf * verts[idx[t + 1]], xf * verts[idx[t + 2]]]
			BroadwayStreet.tri(st, vs, [n, n, n], [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO], ink, n)
	st.index()
	var mesh := st.commit()
	var m := BroadwayStreet._vc_material(0.7)
	mesh.surface_set_material(0, m)
	_meshes[key] = mesh
	return mesh


## A souvenir postcard spinner: a base, a pole, four tiers of card pockets round it.
static func spinner_mesh() -> Mesh:
	if _meshes.has("spinner"):
		return _meshes.spinner
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var chrome := Color(0.72, 0.73, 0.75)
	BroadwayStreet.lathe(st, [Vector2(0.28, 0.0), Vector2(0.28, 0.03), Vector2(0.03, 0.05), Vector2(0.025, 1.72), Vector2(0.06, 1.76), Vector2(0.0, 1.78)], 12, chrome)
	for tier in 4:
		var y := 0.55 + float(tier) * 0.3
		for k in 6:
			var a := float(k) / 6.0 * TAU + float(tier) * 0.3
			var dir := Vector3(sin(a), 0.0, cos(a))
			var c := Color.from_hsv(fmod(float(k * 4 + tier) * 0.21, 1.0), 0.55, 0.9)
			var bb := Basis(Vector3.UP, a)
			BroadwayStreet._box(st, dir * 0.12 + Vector3(0.0, y, 0.0), Vector3(0.11, 0.16, 0.012), c, bb)
			BroadwayStreet._box(st, dir * 0.105 + Vector3(0.0, y - 0.06, 0.0), Vector3(0.13, 0.05, 0.03), chrome, bb)
	st.index()
	var mesh := st.commit()
	mesh.surface_set_material(0, BroadwayStreet._vc_material(0.5))
	_meshes.spinner = mesh
	return mesh


## A souvenir table: gold star trophies, snow globes, caps, mugs, a little price board.
static func souvenir_table_mesh() -> Mesh:
	if _meshes.has("table"):
		return _meshes.table
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	BroadwayStreet._box(st, Vector3(0.0, 0.74, 0.0), Vector3(1.8, 0.04, 0.7), Color(0.12, 0.10, 0.30))
	BroadwayStreet._box(st, Vector3(0.0, 0.45, 0.34), Vector3(1.8, 0.6, 0.01), Color(0.55, 0.05, 0.08))
	for sx: float in [-0.8, 0.8]:
		for sz: float in [-0.28, 0.28]:
			BroadwayStreet._box(st, Vector3(sx, 0.36, sz), Vector3(0.03, 0.72, 0.03), Color(0.3, 0.3, 0.32))
	var gold := Color(0.85, 0.64, 0.22)
	for k in 7:
		var x := -0.75 + float(k) * 0.25
		match k % 3:
			0:
				# A gold star on a black plinth.
				BroadwayStreet._box(st, Vector3(x, 0.79, -0.15), Vector3(0.08, 0.06, 0.08), Color(0.05, 0.05, 0.05))
				BroadwayStreet.lathe(st, [Vector2(0.015, 0.0), Vector2(0.015, 0.14), Vector2(0.0, 0.15)], 6, gold, Vector3(x, 0.82, -0.15))
				_star_prism(st, Vector3(x, 1.03, -0.15), 0.07, 0.025, gold)
			1:
				# A snow globe.
				BroadwayStreet.lathe(st, [Vector2(0.05, 0.0), Vector2(0.05, 0.04), Vector2(0.0, 0.04)], 10, Color(0.3, 0.15, 0.08), Vector3(x, 0.76, -0.12))
				BroadwayStreet.lathe(st, [Vector2(0.0, 0.0), Vector2(0.04, 0.01), Vector2(0.055, 0.05), Vector2(0.04, 0.095), Vector2(0.0, 0.105)], 10, Color(0.80, 0.88, 0.95), Vector3(x, 0.80, -0.12))
			_:
				# A stack of mugs.
				for m in 2:
					BroadwayStreet.lathe(st, [Vector2(0.04, 0.0), Vector2(0.04, 0.09), Vector2(0.0, 0.09)], 8, Color(0.95, 0.95, 0.93) if m == 0 else Color(0.8, 0.1, 0.1), Vector3(x, 0.76 + float(m) * 0.095, -0.12))
		# Folded tees in a row at the front.
		BroadwayStreet._box(st, Vector3(x, 0.79, 0.15), Vector3(0.2, 0.06, 0.24), Color.from_hsv(fmod(float(k) * 0.31, 1.0), 0.5, 0.75))
	BroadwayStreet._box(st, Vector3(0.95, 1.05, 0.0), Vector3(0.03, 0.6, 0.5), Color(0.98, 0.85, 0.15))
	st.index()
	var mesh := st.commit()
	mesh.surface_set_material(0, BroadwayStreet._vc_material(0.55))
	_meshes.table = mesh
	return mesh


## A celebrity-map seller's A-frame board: yellow with a red star.
static func map_board_mesh() -> Mesh:
	if _meshes.has("board"):
		return _meshes.board
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for s: float in [-1.0, 1.0]:
		var b := Basis(Vector3.RIGHT, s * 0.2)
		BroadwayStreet._box(st, Vector3(0.0, 0.55, s * 0.11), Vector3(0.62, 1.05, 0.025), Color(0.98, 0.84, 0.10), b)
		_star_prism(st, Vector3(0.0, 0.72, s * 0.135), 0.2, 0.01, Color(0.80, 0.08, 0.06), b.rotated(Vector3.RIGHT, PI * 0.5))
		BroadwayStreet._box(st, Vector3(0.0, 0.32, s * 0.13), Vector3(0.5, 0.08, 0.01), Color(0.1, 0.1, 0.12), b)
		BroadwayStreet._box(st, Vector3(0.0, 0.2, s * 0.13), Vector3(0.42, 0.06, 0.01), Color(0.1, 0.1, 0.12), b)
	st.index()
	var mesh := st.commit()
	mesh.surface_set_material(0, BroadwayStreet._vc_material(0.6))
	_meshes.board = mesh
	return mesh


## A five-pointed star prism (thickness `t` along the basis's y) round `c`, radius `r`.
static func _star_prism(st: SurfaceTool, c: Vector3, r: float, t: float, col: Color, b: Basis = Basis(Vector3.RIGHT, PI * 0.5)) -> void:
	var pts: Array[Vector3] = []
	for k in 10:
		var a := float(k) / 10.0 * TAU
		var rr := r if k % 2 == 0 else r * 0.42
		pts.append(Vector3(sin(a) * rr, 0.0, cos(a) * rr))
	var up := b * Vector3(0.0, t * 0.5, 0.0)
	for k in 10:
		var a := b * pts[k]
		var bb := b * pts[(k + 1) % 10]
		BroadwayStreet.tri(st, [c + up, c + a + up, c + bb + up], [b.y, b.y, b.y], [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO], col, b.y)
		BroadwayStreet.tri(st, [c - up, c + a - up, c + bb - up], [-b.y, -b.y, -b.y], [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO], col, -b.y)
		var n := ((a + bb) * 0.5).normalized()
		BroadwayStreet.tri(st, [c + a + up, c + bb + up, c + bb - up], [n, n, n], [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO], col, n)
		BroadwayStreet.tri(st, [c + a + up, c + bb - up, c + a - up], [n, n, n], [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO], col, n)


## A lamp's star medallion: a gold star plate on a short arm, edged in a neon tube that lights
## after dark (shaders/star_neon.gdshader; the plate faces along the boulevard, both ways).
static func medallion_mesh() -> Mesh:
	if _meshes.has("medal"):
		return _meshes.medal
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var gold := Color(0.80, 0.60, 0.25)
	# The arm back to the pole (toward +z from the plate's centre; the batch turns nothing).
	BroadwayStreet._box(st, Vector3(0.0, 0.0, MEDALLION_ARM * 0.5), Vector3(0.05, 0.05, MEDALLION_ARM), Color(0.12, 0.12, 0.13))
	# Upright, its faces toward +-x (along the boulevard), a point up.
	_star_prism(st, Vector3.ZERO, 0.42, 0.04, gold, Basis(Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 1, 0)))
	var plate := st.commit()
	plate.surface_set_material(0, _gold_material())
	# The neon: a tube round the star's outline on both faces (a thin band of quads).
	var neon := SurfaceTool.new()
	neon.begin(Mesh.PRIMITIVE_TRIANGLES)
	for face: float in [-1.0, 1.0]:
		var x := face * 0.03
		for k in 10:
			var a0 := float(k) / 10.0 * TAU
			var a1 := float(k + 1) / 10.0 * TAU
			var r0 := 0.36 if k % 2 == 0 else 0.36 * 0.42
			var r1 := 0.36 if (k + 1) % 2 == 0 else 0.36 * 0.42
			var p0 := Vector3(x, cos(a0) * r0, sin(a0) * r0)
			var p1 := Vector3(x, cos(a1) * r1, sin(a1) * r1)
			var d := (p1 - p0).normalized()
			var side_v := Vector3(1, 0, 0).cross(d).normalized() * 0.018
			var nrm := Vector3(face, 0.0, 0.0)
			for v: Vector3 in [p0 - side_v, p1 - side_v, p1 + side_v, p0 - side_v, p1 + side_v, p0 + side_v]:
				neon.set_normal(nrm)
				neon.add_vertex(v)
	neon.commit(plate)
	plate.surface_set_material(1, neon_material())
	_meshes.medal = plate
	return plate


static var _gold: StandardMaterial3D
static var _neon: ShaderMaterial


static func _gold_material() -> StandardMaterial3D:
	if _gold == null:
		_gold = StandardMaterial3D.new()
		_gold.vertex_color_use_as_albedo = true
		_gold.metallic = 0.85
		_gold.roughness = 0.3
	return _gold


static func neon_material() -> ShaderMaterial:
	if _neon == null:
		_neon = ShaderMaterial.new()
		_neon.shader = load("res://shaders/star_neon.gdshader")
	return _neon


# --- The buses and the characters -----------------------------------------------------------------

## Sightseeing buses at the kerb in front of the palace (the palace's chunk; real Vehicles that
## live under the city root like the parked cars).
static func _buses(ch: CityChunk) -> void:
	var p := plan_for(ch.plan)
	var pal: Dictionary = p.get("palace", {})
	if pal.is_empty() or pal.block != Vector2i(ch.ix, ch.iz):
		return
	if not ResourceLoader.exists(Vehicle.BODY_MODELS[BigVehicles.BUS]):
		return
	var zone := bus_zone(ch.plan)
	var side: int = pal.side
	# Kerb-side lane traffic: westbound on the north kerb, eastbound on the south.
	var d := Vector3(-1.0 if side < 0 else 1.0, 0.0, 0.0)
	var yaw := atan2(-d.x, -d.z)
	for k in BUSES:
		if not PhysicsBudget.can_spawn():
			return
		var x := zone.position.x + zone.size.x * (0.25 + 0.5 * float(k))
		var at := Vector2(x, zone.get_center().y)
		var bus := tour_bus(hash([ch.plan.seed, "sb_bus", k]))
		var holder: Node = ch.get_parent() if ch.get_parent() else ch
		var pos := Vector3(at.x, 0.5 + ch._gy(at.x, at.y), at.y)
		bus.position = WorldState.to_local(pos) if holder != ch else pos
		bus.rotation.y = yaw
		bus.add_to_group("sightseeing_bus")
		holder.add_child(bus)
		bus.visible = ch.visible
		ch._cars.append(bus)


## Where the `i`-th costumed character of this block stands: on the stars, facing the street, or
## {} when this slot is empty. Pure (hashes of seed + block).
static func character_spot(plan: CityPlan, bx: int, bz: int, rect: Rect2, side: int, i: int) -> Dictionary:
	if h01([plan.seed, bx, bz, "sb_char", i]) > 0.8:
		return {}
	var span := band_span(rect)
	if span.y - span.x < 6.0:
		return {}
	var t := (float(i) + 0.25 + 0.5 * h01([plan.seed, bx, bz, "sb_char_at", i])) / float(MAX_CHARACTERS)
	var x := lerpf(span.x + 2.0, span.y - 2.0, t)
	var inz := 1.0 if side > 0 else -1.0
	var z := kerb_z(rect, side) + inz * (BAND_FROM + BAND * 0.5)
	var to := Vector2(0.0, -inz)
	return {"at": Vector2(x, z), "yaw": atan2(-to.x, -to.y),
		"costume": absi(hash([plan.seed, bx, bz, "sb_costume", i])) % StreetCharacter.COSTUMES.size(),
		"seed": absi(hash([plan.seed, bx, bz, "sb_char_seed", i]))}


static func _spawn_character(ch: CityChunk, rect: Rect2, side: int, i: int) -> void:
	var s := character_spot(ch.plan, ch.ix, ch.iz, rect, side, i)
	if s.is_empty() or not ch._take_crowd_room():
		return
	var ped := StreetCharacter.new()
	ped.costume = int(s.costume)
	ped.setup_vendor(rect, int(s.seed), s.at, float(s.yaw), false, 0.0)
	var at: Vector2 = s.at
	ped.position = Vector3(at.x, ch.ground_y(at.x, at.y) + 0.05, at.y)
	ch.add_child(ped)


## The sightseeing company (invented): a BigVehicles bus in its own livery and lettering.
const TOUR_FLEET := "STARLINE SIGHTSEEING"
const TOUR_PAINT := Color(0.36, 0.06, 0.32)
const TOUR_TRIM := Color(0.95, 0.74, 0.20)


static func tour_bus(look: int) -> Vehicle:
	var car := BigVehicles.make(BigVehicles.BUS, look)
	car.setup(BigVehicles.BUS, TOUR_PAINT, Vehicle.Addon.NONE)
	car.setup_look(Vehicle.Finish.GLOSS, Vehicle.Livery.TWO_TONE, TOUR_TRIM)
	car.set_meta("fleet", TOUR_FLEET)
	car.set_meta("tour", true)
	return car
