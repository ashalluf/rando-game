class_name CivicBuildings
extends RefCounted
## Neighbourhood civic buildings (2026-10-05, fleet task "civic-buildings"): the public buildings
## every Los Angeles neighbourhood has a few blocks away -
## - a SPANISH revival branch library (white stucco, a clay-tile hip roof, a projecting entrance
##   pavilion with a cast-stone arched doorway, tall arched reading-room windows with iron grilles,
##   now and then a corner tower or a side loggia),
## - a MID-CENTURY branch library (a glass pavilion under a deep cantilevered roof, a folded-plate
##   roof over the reading room on some, a stone-veneer feature wall with the name, breeze block),
## - a POST OFFICE of an invented postal service (CONTINENTAL POST): a stripped-classical brick or
##   stucco front up a granite stair, the flag on its pole in front, blue collection boxes at the
##   kerb, and behind it the loading dock and the yard of parked mail trucks,
## - a CITY SERVICES office (RANDO CITY SERVICES: permits, water and power, parking), concrete
##   with a pier colonnade and sun louvres, three flags,
## - a COMMUNITY CENTER: a tall bowstring-roofed gym hall and a lower classroom wing round a
##   covered entry, picnic tables and benches.
## Everything is geometry built in code (CivicKit), one mesh per building with a surface per
## material; windows wear shaders/civic_glass.gdshader, which traces the room behind each pane
## (book stacks, the post office's box wall and counter, desks, the hall's floor) and lights it by
## the city's hour after dark.
##
## WHERE is worked out, never placed (FireStation's and PoliceStation's way): the city is cut into
## CELL squares; a hash of seed + cell picks up to TRIES points; the first whose block is plain
## BUILDINGS in a civic district (not a landmark's, a site's, a park's, a school's, a hospital's,
## the river's, the fire or police station's, a beach walk street's, under a freeway or in the
## downtown towers) gives a SITE: a centred run of the block's lot-grid cells along one street,
## the size the kind wants. The kind is a hash weighted by district (KIND_ODDS). Every lot whose
## centre is in the site is the building's (CityChunk._build_lot asks claims() AFTER every roll
## and after the fire station, the police station and Broadway), the first of them in lots()
## order builds it. Hashes of seed + cell + block only, so the LOD chunks, the far city, the
## tests and the probes ask the same question.
##
## FULL chunks: the real building, its forecourt, lamps and pools, real lights (lamp_light), a few
## people (CivicVisitor), the mail trucks (CivicKit.mail_truck_mesh(), parked, static). LOD chunks
## and the far city: the building as CODED far boxes (FarBuilding's code: the far shader draws the
## same window grid, finish and lit rooms) and its pitched roofs as slabs, like HouseBuild.lod().
##
## Names are this game's own (RANDO CITY PUBLIC LIBRARY, CONTINENTAL POST, RANDO CITY SERVICES,
## invented branch names), never a real library's, agency's or post office's.

enum Kind { LIBRARY_SPANISH, LIBRARY_MODERN, POST_OFFICE, CITY_SERVICES, COMMUNITY }

const CELL := 640.0
const ODDS := 0.9
const TRIES := 10
## Per district: cumulative-free weights in Kind order (0 = never there).
const KIND_ODDS := {
	CityPlan.District.SUBURBS: [0.30, 0.22, 0.22, 0.0, 0.26],
	CityPlan.District.MIDTOWN: [0.20, 0.20, 0.24, 0.20, 0.16],
	CityPlan.District.BEACHTOWN: [0.36, 0.12, 0.26, 0.0, 0.26],
	CityPlan.District.DOWNTOWN: [0.0, 0.22, 0.44, 0.34, 0.0],
}
## The share of downtown cells that get one at all.
const DOWNTOWN_ODDS := 0.5
## The site each kind wants (frontage, depth; m), the least it takes, the most.
const SITE_TARGET := [Vector2(36.0, 34.0), Vector2(38.0, 34.0), Vector2(44.0, 44.0), Vector2(42.0, 36.0), Vector2(42.0, 36.0)]
const SITE_MIN := [Vector2(26.0, 26.0), Vector2(26.0, 26.0), Vector2(32.0, 32.0), Vector2(30.0, 28.0), Vector2(30.0, 27.0)]
const SITE_MAX := Vector2(72.0, 70.0)
## The most the ground may rise across a site (m): it stands on one level.
const MAX_RELIEF := 1.8
## A downtown block counts only off the tower core (MacroMap.skyline_boost under this).
const CORE_BOOST := 0.3

const LIBRARY := "RANDO CITY PUBLIC LIBRARY"
const POST := "CONTINENTAL POST"
const SERVICES := "RANDO CITY SERVICES"
## Branch and centre names: invented neighbourhood names.
const PLACES := ["SYCAMORE GLEN", "LARKSPUR", "TOYON RIDGE", "CIELO VERDE", "MANZANITA", "BAY LAUREL",
	"ROSEMEAD GROVE", "AGAVE HEIGHTS", "PALMETTO", "CORONA VISTA", "LINDEN PARK", "SAGEBRUSH",
	"WILLOW BEND", "MARIPOSA", "SEA CLIFF", "QUAIL HOLLOW", "MISSION VIEW", "OLIVE KNOLL",
	"ACACIA", "CANYON GATE", "HARBOR LIGHTS", "LEMON GROVE", "VERBENA", "SUNRIDGE", "PEPPERTREE",
	"BLUE JAY", "DESCANSO", "LA LOMITA", "ENCINO VERDE", "SANTA ROSITA"]

## Off (CIVIC=0 in the environment): no civic buildings, the lots keep what they had (the A/B).
static var enabled: bool = OS.get_environment("CIVIC") != "0"
static var _cache: Dictionary = {}
## Why tries failed (the probe prints it; DEBUG only).
static var reasons: Dictionary = {}


static func _why(r: String) -> void:
	reasons[r] = int(reasons.get(r, 0)) + 1


static func _h01(parts: Array) -> float:
	return float(absi(hash(parts)) % 100003) / 100003.0


static func _cell_of(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / CELL), floori(p.y / CELL))


static func kind_name(kind: int) -> String:
	return ["library_spanish", "library_modern", "post_office", "city_services", "community"][kind]


# --- Where ---------------------------------------------------------------------------------------

## The civic building of grid cell `cell`: {} or a site (see _site()) plus "kind", "name",
## "number", "cell", "key". Cached per plan and cell. Pure.
static func for_cell(plan: CityPlan, cell: Vector2i) -> Dictionary:
	var key := Vector3i(plan.seed, cell.x, cell.y)
	if _cache.has(key):
		return _cache[key]
	var out := {}
	_cache[key] = out
	if not enabled or plan.macro == null:
		return out
	if _h01([plan.seed, cell.x, cell.y, "civic"]) > ODDS:
		return out
	for t in TRIES:
		var target := Vector2((float(cell.x) + lerpf(0.12, 0.88, _h01([plan.seed, cell.x, cell.y, t, "cv_x"]))) * CELL,
				(float(cell.y) + lerpf(0.12, 0.88, _h01([plan.seed, cell.x, cell.y, t, "cv_z"]))) * CELL)
		if plan.zone_at(target) != MacroMap.Zone.CITY:
			_why("zone")
			continue
		var bi := plan.block_index_at(target)
		var b := plan.block(bi.x, bi.y)
		var rect: Rect2 = b.rect
		if _cell_of(rect.get_center()) != cell:
			_why("cell")
			continue
		if not _block_ok(plan, bi, b):
			_why("block %d/%d" % [int(b.district), int(b.kind)])
			continue
		# Downtown's cells are many and its blocks big: only some of them get one.
		if int(b.district) == CityPlan.District.DOWNTOWN and _h01([plan.seed, cell.x, cell.y, "cv_dt"]) > DOWNTOWN_ODDS:
			continue
		var kind := _pick_kind(int(b.district), [plan.seed, cell.x, cell.y, t])
		if kind < 0:
			continue
		var s := _site(plan, bi, kind, [plan.seed, cell.x, cell.y, t])
		if s.is_empty():
			_why("site d%d k%d" % [int(b.district), kind])
			continue
		s.kind = kind
		s.cell = cell
		s.key = cell
		s.district = int(b.district)
		s.number = 1 + absi(hash([plan.seed, cell.x, cell.y, "cv_no"])) % 89
		s.name = String(PLACES[absi(hash([plan.seed, cell.x, cell.y, "cv_name"])) % PLACES.size()])
		s.variant = absi(hash([plan.seed, cell.x, cell.y, "cv_var"])) % 1000
		out.merge(s)
		return out
	return out


## Whether block `bi` may give a civic site at all: plain buildings in a civic district, nobody
## else's.
static func _block_ok(plan: CityPlan, bi: Vector2i, b: Dictionary) -> bool:
	var district := int(b.district)
	if not KIND_ODDS.has(district):
		return false
	if int(b.kind) != CityPlan.BlockKind.BUILDINGS or b.has("site") or b.has("grounds") or b.has("hospital"):
		return false
	var rect: Rect2 = b.rect
	# A chunk builds as its block centre's zone (a block at the foot of the hills is a hill chunk).
	if plan.zone_at(rect.get_center()) != MacroMap.Zone.CITY:
		return false
	if Landmarks.claims(rect) or plan.river_block(bi.x, bi.y):
		return false
	if district == CityPlan.District.DOWNTOWN and plan.macro.skyline_boost(rect.get_center()) > CORE_BOOST:
		return false
	# Never the fire station's or a police station's block.
	var fs := FireStation.for_cell(plan, FireStation._cell_of(rect.get_center()))
	if not fs.is_empty() and fs.block == bi:
		return false
	if not PoliceStation.station_on(plan, bi.x, bi.y).is_empty():
		return false
	# A beach block with a walk street between its rows keeps its houses.
	if district == CityPlan.District.BEACHTOWN and (YardFill.walk_for(plan, bi.x, bi.y)[0] as Rect2).size != Vector2.ZERO:
		return false
	return true


static func _pick_kind(district: int, salt: Array) -> int:
	var w: Array = KIND_ODDS.get(district, [])
	var total := 0.0
	for x: float in w:
		total += x
	if total <= 0.0:
		return -1
	var r := _h01(salt + ["cv_kind"]) * total
	for i in w.size():
		r -= float(w[i])
		if r < 0.0:
			return i
	return w.size() - 1


## A site on block `bi` for `kind`: {"block", "site" (Rect2, true world), "side", "frame" (as
## Industrial.frame: u along the street, v in from it), "road" [axis, index], "lots" (seeds),
## "builder" (the seed of the lot that builds it), "front" (true world XZ on the road's centre
## line level with the site's middle), "L", "D"} or {}.
static func _site(plan: CityPlan, bi: Vector2i, kind: int, salt: Array) -> Dictionary:
	var b := plan.block(bi.x, bi.y)
	var lots := plan.lots(bi.x, bi.y)
	if lots.is_empty():
		return {}
	var inner := (b.rect as Rect2).grow(-plan.sidewalk_width)
	if not lots[0].has("cell"):
		return {}
	var cs: Vector2 = (lots[0].cell as Rect2).size
	if cs.x < 1.0 or cs.y < 1.0:
		return {}
	var nx := maxi(1, roundi(inner.size.x / cs.x))
	var nz := maxi(1, roundi(inner.size.y / cs.y))
	var roads := [[CityPlan.AXIS_Z, bi.y], [CityPlan.AXIS_Z, bi.y + 1], [CityPlan.AXIS_X, bi.x], [CityPlan.AXIS_X, bi.x + 1]]
	var k := absi(hash(salt + ["cv_side"])) % 4
	var target: Vector2 = SITE_TARGET[kind]
	var least: Vector2 = SITE_MIN[kind]
	for j in 4:
		var side := (k + j) % 4
		var along_n := nx if side < 2 else nz
		var depth_n := nz if side < 2 else nx
		var ca := cs.x if side < 2 else cs.y
		var cd := cs.y if side < 2 else cs.x
		var ku := clampi(ceili(target.x / ca - 0.2), 1, along_n)
		var kv := clampi(ceili(target.y / cd - 0.2), 1, depth_n)
		var L := float(ku) * ca
		var D := float(kv) * cd
		if L < least.x or D < least.y or L > SITE_MAX.x or D > SITE_MAX.y:
			_why("size")
			continue
		var i0 := (along_n - ku) / 2
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
		var mine: Array[int] = []
		var builder := -1
		var bad := false
		for lot: Dictionary in lots:
			if not site.grow(-0.5).has_point(lot.center):
				continue
			# A courtyard lot builds its garden before any claim is asked; a palace is Broadway's.
			if bool(lot.yard) or Broadway.claims(plan, bi.x, bi.y, lot):
				bad = true
				break
			mine.append(int(lot.seed))
			if builder == -1:
				builder = int(lot.seed)
		# A cell short (a landmark's square, the approach's clear zone or the gap roll dropped it).
		if bad or mine.size() != ku * kv:
			_why("lots" if not bad else "bad")
			continue
		if plan.macro.freeway and plan.macro.freeway.blocks_rect(site.grow(4.0), 3.0):
			continue
		var lo := INF
		var hi := -INF
		for q: Vector2 in [site.position, site.end, Vector2(site.position.x, site.end.y), Vector2(site.end.x, site.position.y), site.get_center()]:
			var r := plan.macro.relief_at(q)
			lo = minf(lo, r)
			hi = maxf(hi, r)
		var off_city := false
		for q2: Vector2 in [site.position, site.end, Vector2(site.position.x, site.end.y), Vector2(site.end.x, site.position.y)]:
			if plan.zone_at(q2) != MacroMap.Zone.CITY:
				off_city = true
		if off_city:
			_why("zone_site")
			continue
		if hi - lo > MAX_RELIEF:
			_why("relief")
			continue
		var road: Array = roads[side]
		var f := Industrial.frame(site, side)
		var edge := Industrial.fp(f, L * 0.5, 0.0)
		var road_pos := plan.road_pos(int(road[0]), int(road[1]))
		var along := edge.y if int(road[0]) == CityPlan.AXIS_X else edge.x
		if not plan.road_open(int(road[0]), int(road[1]), along):
			continue
		var front := Vector2(road_pos, edge.y) if int(road[0]) == CityPlan.AXIS_X else Vector2(edge.x, road_pos)
		return {"block": bi, "site": site, "side": side, "frame": f, "road": road, "lots": mine,
			"builder": builder, "front": front, "L": L, "D": D}
	return {}


## The civic building on block (bx, bz), or {}.
static func on_block(plan: CityPlan, bx: int, bz: int) -> Dictionary:
	if not enabled or plan == null or plan.macro == null:
		return {}
	var b := plan.block(bx, bz)
	var s := for_cell(plan, _cell_of((b.rect as Rect2).get_center()))
	if not s.is_empty() and s.block == Vector2i(bx, bz):
		return s
	return {}


## True when `lot` of block (bx, bz) is a civic building's (CityChunk._build_lot asks, after
## every roll and the fire station, the police station and Broadway).
static func claims(plan: CityPlan, bx: int, bz: int, lot: Dictionary) -> bool:
	var s := on_block(plan, bx, bz)
	return not s.is_empty() and (s.lots as Array).has(int(lot.seed))


## Every civic building whose cell is within `radius` of `p` (true world XZ), nearest first.
static func near(plan: CityPlan, p: Vector2, radius: float) -> Array:
	var out: Array = []
	if plan == null:
		return out
	var c := _cell_of(p)
	var n := ceili(radius / CELL) + 1
	for dx in range(-n, n + 1):
		for dz in range(-n, n + 1):
			var s := for_cell(plan, c + Vector2i(dx, dz))
			if s.is_empty():
				continue
			if (s.site as Rect2).get_center().distance_to(p) <= radius:
				out.append(s)
	out.sort_custom(func(a: Dictionary, b2: Dictionary) -> bool:
		return (a.site as Rect2).get_center().distance_squared_to(p) < (b2.site as Rect2).get_center().distance_squared_to(p))
	return out


## A point of the site's frame (u along the street, v in from its street edge) as true world XZ.
static func world_xz(s: Dictionary, u: float, v: float) -> Vector2:
	return Industrial.fp(s.frame, u, v)


## True when `p` (true world XZ) is a kerb spot a parked car must leave free: in front of a post
## office's driveway or its collection boxes (CityChunk._park_car asks, after its rolls).
static func keeps_clear(plan: CityPlan, p: Vector2) -> bool:
	if not enabled or plan == null:
		return false
	var s := for_cell(plan, _cell_of(p))
	if s.is_empty() or int(s.kind) != Kind.POST_OFFICE:
		return false
	var lay := CivicKit.layout(s)
	var axis := int(s.road[0])
	var rp := plan.road_pos(axis, int(s.road[1]))
	for spot: Array in [[float(lay.drive_u), 6.0], [CivicKit.kerb_truck_u(lay), 5.5]]:
		var at := world_xz(s, float(spot[0]), 0.0)
		var front := Vector2(rp, at.y) if axis == CityPlan.AXIS_X else Vector2(at.x, rp)
		var d := p - front
		var along := d.y if axis == CityPlan.AXIS_X else d.x
		var lat := d.x if axis == CityPlan.AXIS_X else d.y
		if absf(along) < float(spot[1]) and absf(lat) < plan.road_width(axis, int(s.road[1])) * 0.5 + 1.5:
			return true
	return false


## [point (true world XZ), reach] along the pavement in front of the civic building on block
## (bx, bz): what Encampment keeps its camps off.
static func keep_clear_points(plan: CityPlan, bx: int, bz: int) -> Array:
	var s := on_block(plan, bx, bz)
	if s.is_empty():
		return []
	var out: Array = []
	var L: float = s.L
	var n := maxi(2, ceili(L / 6.0))
	for i in n + 1:
		out.append([world_xz(s, L * float(i) / float(n), -plan.sidewalk_width * 0.5), 6.0])
	return out


# --- Building it ---------------------------------------------------------------------------------

## Builds the civic building on its lots in chunk `ch` (FULL: everything; LOD: coded far boxes the
## far city captures). Called from CityChunk._build_lot for each of the site's lots: the builder
## lot builds it, the rest are left to it.
static func build_lot(ch: CityChunk, lot: Dictionary) -> void:
	var s := on_block(ch.plan, ch.ix, ch.iz)
	if s.is_empty() or int(lot.seed) != int(s.builder):
		return
	var site: Rect2 = s.site
	ch._lot_rects.append(site)
	var xf := local_transform(ch, s)
	var sx := local_sx(s)
	var lay := CivicKit.layout(s)
	if ch.level != CityChunk.Level.FULL:
		_build_far(ch, s, lay, xf, sx)
		return
	var node := Node3D.new()
	node.name = "Civic_%s_%d" % [kind_name(int(s.kind)), int(s.number)]
	node.transform = xf
	node.add_to_group("civic_building")
	node.set_meta("key", s.key)
	node.set_meta("kind", int(s.kind))
	ch.add_child(node)
	var out := CivicKit.build(node, s, lay, sx, ch.plan.sidewalk_width)
	# The occluder: the main mass, inset.
	for ob: Array in out.get("occluders", []):
		ch._occluder_boxes.append([xf, ob[0], (ob[1] as Vector3) - Vector3(0.6, 0.6, 0.6)])
	# Trees in the forecourt, on the chunk's own batch (a private rng: nothing else moves).
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([ch.plan.seed, s.key, "cv_trees"])
	for t: Array in out.get("trees", []):
		var at: Vector3 = xf * (t[0] as Vector3)
		at.y = CityChunk.SIDEWALK_TOP + 0.02
		if bool(t[1]):
			ch._add_palm(at, rng, false)
		else:
			ch._add_tree(at, rng)
	# Static parked cars on the chunk's car-park batch (LotFill's kind: no new draws).
	for car: Array in out.get("cars", []):
		var cxf: Transform3D = xf * (car[0] as Transform3D)
		cxf.origin.y = CityChunk.SIDEWALK_TOP + 0.03
		var ckey := "apark_car_%d" % int(car[2])
		ch._batch.add(ckey, ArenaGrounds.car_mesh(int(car[2])), cxf, car[1])
		ch._batch.set_shadow_distance(ckey, LotFill.CAR_SHADOW_DISTANCE)
	# Benches seat the chunk's walkers (CrowdLife), in the chunk's space.
	for bch: Array in out.get("seats", []):
		var at2: Vector3 = xf * (bch[0] as Vector3)
		at2.y = CityChunk.SIDEWALK_TOP + ch._gy(at2.x, at2.z)
		CrowdLife.add_seat(ch, at2, xf.basis.get_euler().y + float(bch[1]))
	# A few people: visitors on a ring in the forecourt, a worker by the dock.
	for ring: Array in out.get("people", []):
		_spawn_person(ch, s, xf, ring[0], int(ring[1]), bool(ring[2]))
	ch.building_count += 1


## The node's transform in the chunk: origin at the site's street edge, middle of the frontage,
## on the pavement top; +Z toward the street, local x along it.
static func local_transform(ch: CityChunk, s: Dictionary) -> Transform3D:
	var f: Dictionary = s.frame
	var L: float = s.L
	var site: Rect2 = s.site
	var centre2 := Industrial.fp(f, L * 0.5, 0.0)
	var g := ch._gy(site.get_center().x, site.get_center().y)
	var n2: Vector2 = f.n
	var outward := Vector3(-n2.x, 0.0, -n2.y)
	var x_axis := Vector3.UP.cross(outward)
	return Transform3D(Basis(x_axis, Vector3.UP, outward), Vector3(centre2.x, g + CityChunk.SIDEWALK_TOP, centre2.y))


## +1 or -1: local x = sx * (u - L/2).
static func local_sx(s: Dictionary) -> float:
	var f: Dictionary = s.frame
	var n2: Vector2 = f.n
	var x_axis := Vector3.UP.cross(Vector3(-n2.x, 0.0, -n2.y))
	return signf(Vector2(x_axis.x, x_axis.z).dot(f.a as Vector2))


## LOD chunks and the far city: every mass as a coded far box (the far shader's window grid, the
## finish and the lit rooms of a near building), pitched roofs as slabs over a gable prism.
static func _build_far(ch: CityChunk, s: Dictionary, lay: Dictionary, xf: Transform3D, sx: float) -> void:
	var seed_v := int(s.builder)
	for m: Dictionary in CivicKit.masses(s, lay):
		var lc: Vector3 = m.c
		lc.x *= sx
		m.c = lc
		var c: Vector3 = xf * lc
		var lsize: Vector3 = m.size
		var wsize := (xf.basis * lsize).abs()
		var o3 := c
		o3.y -= ch._gy(o3.x, o3.z)
		var basis := Basis.from_scale(wsize)
		var colour: Color = m.color
		var custom := Color(0.25, 0.3, float(seed_v % 997) / 997.0, 0.0)
		if FarBuilding.enabled and m.has("finish"):
			basis = FarBuilding.encode(wsize, _codes(m, wsize, seed_v))
			custom = Color(0.0, 0.0, float(seed_v % 997) / 997.0, FarBuilding.PART_FLAG)
		elif bool(m.get("plain", false)):
			custom = Color(0.0, 0.0, float(seed_v % 997) / 997.0, 1.0)
		ch._batch.add("lod_box", PropFactory.unit_box(), Transform3D(basis, o3), Color(colour.r, colour.g, colour.b, 1.0), custom)
		if bool(m.get("solid", true)):
			ch._add_lod_shape(wsize, c)
		if m.has("roof"):
			_far_roof(ch, xf, m, seed_v)


## A coded part's six codes (FarBuilding.boxes()'s layout) for a civic mass.
static func _codes(m: Dictionary, wsize: Vector3, seed_v: int) -> Array:
	var finish: int = m.finish
	var style: int = m.get("window", Building.WindowStyle.PUNCHED)
	var rows: int = m.get("rows", 1)
	var pitch: float = m.get("pitch", 3.2)
	var a := (seed_v % 1000) | (finish << 10) | (style << 12) | (int(m.get("roof_style", 0)) << 14) | (0 << 16)
	var b := 0 | (4 << 3)
	var cc := clampi(roundi(float(m.get("lit", 0.5)) * 65535.0), 0, 65535) | (0 << 16) | (0 << 17)
	var cols_x := clampi(roundi(wsize.x / pitch), 1, FarBuilding.MAX_COLS)
	var cols_z := clampi(roundi(wsize.z / pitch), 1, FarBuilding.MAX_COLS)
	var wall_idx := FarBuilding.WALL_SETS.find(String(m.get("wall_set", "")))
	if wall_idx < 0:
		wall_idx = 15
	var d := cols_x | (cols_z << 7) | (wall_idx << 14)
	var e := clampi(rows, 1, FarBuilding.MAX_ROWS) | (0 << 7)
	var f2 := 0
	return [a, b, cc, d, e, f2]


## A pitched roof over mass `m` (local): two slabs in the roof colour and a prism closing the
## gable ends (HouseBuild.lod()'s shape), or for a hip roof the slabs alone over a lower prism.
static func _far_roof(ch: CityChunk, xf: Transform3D, m: Dictionary, seed_v: int) -> void:
	var plain := Color(0.0, 0.0, float(seed_v % 997) / 997.0, 1.0)
	var size: Vector3 = m.size
	var c: Vector3 = m.c
	var top := c.y + size.y * 0.5
	var along_x := size.x >= size.z
	var eave := 0.6
	var run := (size.z if along_x else size.x) * 0.5 + eave
	var length := (size.x if along_x else size.z) + eave * 2.0
	var pitch: float = m.get("roof_pitch", 0.42)
	var rise := run * pitch
	var slope_len := sqrt(run * run + rise * rise)
	var rd := (xf.basis * (Vector3.RIGHT if along_x else Vector3.BACK)).normalized()
	var ac := (xf.basis * (Vector3.BACK if along_x else Vector3.RIGHT)).normalized()
	var ridge_c := xf * Vector3(c.x, top + rise - eave * pitch, c.z)
	var roof_c: Color = m.get("roof", HouseKit.CLAY_FAR)
	for sgn: float in [-1.0, 1.0]:
		var down := (ac * sgn * run + Vector3(0, -rise, 0)).normalized()
		var nrm := (ac * sgn * rise + Vector3(0, run, 0)).normalized()
		var mid := ridge_c + down * (slope_len * 0.5) - nrm * 0.12
		var bx := nrm * 0.25
		var by := -down * slope_len
		var bz := rd * length
		if bx.cross(by).dot(bz) < 0.0:
			bz = -bz
		var o3 := mid
		o3.y -= ch._gy(o3.x, o3.z)
		ch._batch.add("lod_box", PropFactory.unit_box(), Transform3D(Basis(bx, by, bz), o3), roof_c, plain)
	var hh := (size.z if along_x else size.x) * 0.5 * pitch
	var a := hh * sqrt(2.0)
	var wl := size.x if along_x else size.z
	var px := rd * wl
	var py := (Vector3.UP + ac).normalized() * a
	var pz := (Vector3.UP - ac).normalized() * a
	if px.cross(py).dot(pz) < 0.0:
		pz = -pz
	var po := xf * Vector3(c.x, top, c.z)
	po.y -= ch._gy(po.x, po.z)
	var wc: Color = m.color
	ch._batch.add("lod_box", PropFactory.unit_box(), Transform3D(Basis(px, py, pz), po), wc, plain)


## One person on a ring in the forecourt (local rect), under the crowd cap.
static func _spawn_person(ch: CityChunk, s: Dictionary, xf: Transform3D, local_ring: Rect2, salt: int, worker: bool) -> void:
	if not ch._take_crowd_room():
		return
	# The ring in chunk space (true world for a chunk at the origin, as the walkers use).
	var a := xf * Vector3(local_ring.position.x, 0.0, local_ring.position.y)
	var b := xf * Vector3(local_ring.end.x, 0.0, local_ring.end.y)
	var ring := Rect2(Vector2(minf(a.x, b.x), minf(a.z, b.z)), Vector2(absf(b.x - a.x), absf(b.z - a.z)))
	var ped := CivicVisitor.new()
	ped.worker = worker
	ped.setup(ring, minf(1.8, minf(ring.size.x, ring.size.y) * 0.45), absi(hash([ch.plan.seed, s.key, salt, "cv_ped"])))
	var start := ped._random_ring_point(minf(1.8, minf(ring.size.x, ring.size.y) * 0.45))
	ped.position = Vector3(start.x, CityChunk.SIDEWALK_TOP + 0.1 + ch._gy(start.x, start.y), start.y)
	ch.add_child(ped)
