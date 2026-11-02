class_name FashionDistrict
extends RefCounted
## Downtown's fashion district (2026-10-06, "wholesale shops with racks of clothes and bolts of
## fabric spilling onto the pavement under awnings, a narrow market alley crowded with stalls,
## mannequins, hand trucks and people with bags"): the blocks east of Main St between 7th St and
## Pico Blvd, which DowntownReal pins on every seed (Main x 3236, Alameda x 3390, 7th z 404, Pico
## z 1563), out to EAST_LIMIT. The real district's FORMS - wholesale and retail clothing and
## textile shops, their stock out on the pavement every morning, the market alley between two
## streets lined with stalls under tarps - and every NAME invented.
##
## It is an OVERLAY on the seeded city: no lot, roll or building moves. What it does, each from
## one hook line:
## - dress() (CityChunk._build_lot(), after HistoricCore): every building of a district block
##   keeps its lot and rolls, takes its shop names from SHOP_POOL (the clothing and textile names
##   already in Building.SHOP_NAMES - so the shop interiors behind the glass are the clothing
##   rooms, ShopRoom.CLOTHING, and the window vinyl reads them) and hangs the kit's awnings over
##   every shop (Building.kit_awning_building_chance 1).
## - steps() (CityChunk's FULL block steps, after Micromobility): the goods out on the pavement -
##   a frontage SET (FashionKit.frontage(): racks, gridwalls, mannequins, sale tables, fabric
##   rolls and bolt stands, hand trucks, cartons) per shop front, tight against the wall under the
##   awnings, with a gap for each door; sellers by some of them (StreetVendor).
## - dress_market() (AlleyKit.dress(), first thing): a district block's service alley south of
##   MARKET_NORTH is, by hash, a MARKET ALLEY - stalls down both sides (FashionKit.stall()),
##   tarps and bulb strings strung overhead, mannequins and hand trucks in the gaps, a banner with
##   its invented name at each mouth, warm lights, stall keepers and shoppers carrying bags
##   (FashionShopper, which strolls the alley).
## - owns_face() (Encampment._faces()): the camps keep off the faces the goods stand on.
## - walker() (CityChunk._spawn_walker()): the district's walkers carry shopping bags more often.
## Every choice is a hash of the seed and the block / face / slot, never a chunk, block or Building
## rng. FULL chunks only: LOD chunks and the far city see the buildings as they were.
##
## Off (FASHION=0 in the environment): none of it, the A/B for stills and frame counts.

static var enabled: bool = OS.get_environment("FASHION") != "0"

## The stretch: east of Main, from 7th St to Pico Blvd (DowntownReal names), and how far east.
const WEST_AVENUE := "MAIN ST"
const NORTH_STREET := "7TH ST"
const SOUTH_STREET := "PICO BLVD"
## The district's east edge, metres east of Alameda's centre line (the real district runs to about
## San Pedro and Central; east of here is the Arts District's warehouses).
const EAST_REACH := 330.0
## The market alleys are south of this street (the real one runs south of Olympic).
const MARKET_NORTH := "9TH ST"
## Odds a block face carries goods, cut on skid row (Encampment.skid_row() x SKID_CUT); odds a
## district block's alley is a market.
const FACE_ODDS := 0.92
const SKID_CUT := 0.55
const MARKET_ODDS := 0.8
## Pavement: clear of each corner (m), the gap left for a shop door between sets (m), how far the
## goods stand off the wall (m), the farthest a wall may stand from the kerb and still be a shop
## front (m), the most sets a chunk lays, odds a set slot is left empty.
const CORNER_CLEAR := 6.5
const DOOR_GAP := 1.7
const WALL_OFF := 0.08
const MAX_WALL_DEPTH := 9.0
const MAX_SETS := 40
const EMPTY_ODDS := 0.18
## The walkers keep to the kerb half of a district pavement (CityChunk._pedestrian_steps()).
const WALK_SIDEWALK := 3.0
## Sellers by the goods: one per this many sets, at most per chunk.
const SELLER_EVERY := 4
const MAX_SELLERS := 5
## The market alley: a stall's width along the alley and depth, the mouths kept clear, the
## narrowest alley with stalls on both sides / on one, tarp and bulb spacing, people.
const STALL_W := 2.4
const STALL_D := 1.5
const MOUTH_CLEAR := 3.5
const BOTH_SIDES_W := 4.4
const ONE_SIDE_W := 3.6
const TARP_EVERY := Vector2(5.0, 8.0)
const BULB_EVERY := 4.5
const GAP_ODDS := 0.14
## The share of a side's length a building must back for it to carry stalls, and how far beyond
## the alley's edge a building counts (m).
const MIN_WALLED := 0.5
const WALL_REACH := 7.0
## The widest service strip a stall backs across to its wall (m).
const MAX_STRIP := 4.0
## The aisle left between the stalls (m).
const AISLE := 2.2
const SHOPPERS_PER_M := 1.0 / 5.0
const MAX_SHOPPERS := 7
const KEEPER_EVERY := 3
const MAX_KEEPERS := 3
## Draw distances (m): the goods, the stalls and tarps (seen down the alley and from above). The
## goods and stalls cast no shadow (see dress_market()).
const GOODS_DRAW := 75.0
const STALL_DRAW := 110.0
## The market alleys' invented names (on the banners at the mouths).
const ALLEY_NAMES := ["CALLEJON DE LA MODA", "SANTA LUZ ALLEY", "EL BAZAR TEXTIL", "MERCADITO DEL SOL",
	"PASAJE ESTRELLA", "THE THREAD ALLEY"]
## Shop names (Building.SHOP_NAMES, so the vinyl and the interiors know them); repeats weight them.
const SHOP_POOL := ["ROPA PARA TODOS", "ROPA PARA TODOS", "TELAS FINAS", "TELAS FINAS", "TELAS FINAS",
	"PRECIOS BAJOS", "PRECIOS BAJOS", "TODO EN OFERTA", "ZAPATERIA", "SOMBREROS", "BOTAS VAQUERAS",
	"BRIDAL WORLD", "QUINCEANERAS", "VESTIDOS DE GALA", "NOVIAS ELENA", "LA REINA BRIDAL", "THRIFT",
	"DISCOUNT CITY", "PERFUMES", "JOYERIA ORO"]

## The hours the shops put their goods out (by the hour a chunk is built at, StreetVendors'
## clock), and the hours the market alley has its people (its stalls stand all night, lit).
const OPEN_HOURS := Vector2(7.5, 20.5)
const MARKET_HOURS := Vector2(8.0, 22.0)
## Tests and stills: build as at this hour (< 0: the city's clock).
static var force_hour: float = -1.0

static var _info: Dictionary = {}
static var _pool: PackedInt32Array = PackedInt32Array()
## Counters for probes and checks.
static var sets_laid: int = 0
static var stalls_laid: int = 0
static var markets_laid: int = 0


static func h01(parts: Array) -> float:
	return float(absi(hash(parts)) % 100003) / 100003.0


## The stretch in world coordinates: Rect2 from Main's centre line to the east edge, 7th to Pico.
static func stretch() -> Rect2:
	var main := DowntownReal.named(CityPlan.AXIS_X, WEST_AVENUE)
	var ala := DowntownReal.named(CityPlan.AXIS_X, "ALAMEDA ST")
	var x0 := float(main[0]) if not main.is_empty() else 3235.7
	var x1 := (float(ala[0]) if not ala.is_empty() else 3390.0) + EAST_REACH
	var z0 := Broadway.street_z(NORTH_STREET)
	var z1 := Broadway.street_z(SOUTH_STREET)
	return Rect2(x0, z0, x1 - x0, z1 - z0)


## What the district makes of block (bx, bz): {} when it is not a district block, else {"faces":
## the faces carrying goods (0 -Z, 1 +Z, 2 -X, 3 +X, CityChunk._sidewalk_edges' order), "market":
## its alley may be a market, "rect", "east" (x where the goods stop)}. Cached per plan.
static func block_info(plan: CityPlan, bx: int, bz: int) -> Dictionary:
	if not enabled or plan == null or plan.macro == null:
		return {}
	var key := hash([plan.get_instance_id(), plan.seed, bx, bz])
	if _info.has(key):
		return _info[key]
	if _info.size() > 20000:
		_info.clear()
	var out := _block_info(plan, bx, bz)
	_info[key] = out
	return out


static func _block_info(plan: CityPlan, bx: int, bz: int) -> Dictionary:
	var b: Dictionary = plan.block(bx, bz)
	var rect: Rect2 = b.rect
	var st := stretch()
	var c := rect.get_center()
	if c.y < st.position.y or c.y > st.end.y or rect.position.x < st.position.x - 1.0 or rect.position.x > st.end.x:
		return {}
	if int(b.kind) != CityPlan.BlockKind.BUILDINGS or int(b.district) != CityPlan.District.DOWNTOWN:
		return {}
	if b.has("site") or b.has("grounds") or b.has("chinatown"):
		return {}
	if plan.zone_at(c) != MacroMap.Zone.CITY or plan.river_block(bx, bz) or Landmarks.claims(rect):
		return {}
	var skid := Encampment.skid_row(plan, bx, bz)
	var odds := FACE_ODDS * (1.0 - SKID_CUT * skid)
	var historic := HistoricCore.block_fronts(plan, bx, bz)
	var faces: Array[int] = []
	var east := st.end.x
	var edges := CityChunk._sidewalk_edges(rect)
	for e in 4:
		# Main St's frontage north of 9th St is the historic core's (HistoricCore dresses it).
		if e == 2 and not historic.is_empty():
			continue
		var a: Vector2 = edges[e][0]
		var bb: Vector2 = edges[e][1]
		if minf(a.x, bb.x) > east - 20.0:
			continue
		if h01([plan.seed, "fashion_face", bx, bz, e]) < odds:
			faces.append(e)
	var market := c.y > Broadway.street_z(MARKET_NORTH) and h01([plan.seed, "fashion_market", bx, bz]) < MARKET_ODDS
	return {"faces": faces, "market": market, "rect": rect, "east": east}


## CityChunk: does this block get the district's FULL steps?
static func wanted(ch: CityChunk, block: Dictionary) -> bool:
	return ch.level == CityChunk.Level.FULL and not ch.capturing and int(block.kind) == CityPlan.BlockKind.BUILDINGS \
		and not block_info(ch.plan, ch.ix, ch.iz).is_empty()


## Encampment._faces(): the camps keep off a face the goods stand on.
static func owns_face(plan: CityPlan, bx: int, bz: int, e: int) -> bool:
	var info := block_info(plan, bx, bz)
	return not info.is_empty() and e in (info.faces as Array)


## The walkers' sidewalk inset on a district block (they keep to the kerb half), or `fallback`.
static func walk_sidewalk(ch: CityChunk, block: Dictionary, fallback: float) -> float:
	return WALK_SIDEWALK if fallback < 0.0 and wanted(ch, block) else fallback


## CityChunk._build_lot(): a district building's shops are clothing and textile shops under
## awnings (before it generates, both levels; nothing else about it moves).
static func dress(ch: CityChunk, lot: Dictionary, building: Building) -> void:
	if block_info(ch.plan, ch.ix, ch.iz).is_empty() or building.fill_lot or not building.name_pool.is_empty():
		return
	building.name_pool = shop_pool()
	building.kit_awning_building_chance = 1.0


## SHOP_POOL as indices into Building.SHOP_NAMES.
static func shop_pool() -> PackedInt32Array:
	if _pool.is_empty():
		for name: String in SHOP_POOL:
			var i := Building.SHOP_NAMES.find(name)
			if i >= 0:
				_pool.append(i)
	return _pool


## CityChunk._spawn_walker(): a district walker carries a shopping bag more often (its own life
## roll; only the share moves, so a walker elsewhere is unchanged).
static func walker(ch: CityChunk, ped: Pedestrian) -> void:
	if enabled and not block_info(ch.plan, ch.ix, ch.iz).is_empty():
		ped.bag_share = 0.42


# --- The pavement --------------------------------------------------------------------------

## The district's FULL build steps for a block: the goods, then the sellers one a step.
static func steps(ch: CityChunk, block: Dictionary) -> Array[Callable]:
	var out: Array[Callable] = []
	var sellers: Array = []
	out.append(func() -> void: build_pavement(ch, block, sellers))
	for i in MAX_SELLERS:
		out.append(func() -> void: spawn_person(ch, sellers, i))
	return out


static func _state(ch: CityChunk) -> Dictionary:
	if not ch.has_meta("fashion"):
		ch.set_meta("fashion", {"stats": {"sets": 0, "stalls": 0, "tarps": 0, "people": 0, "planned": 0, "markets": 0, "set_tris": 0}, "eyes": []})
	return ch.get_meta("fashion")


## The goods on the block's district faces (FULL): a frontage set per shop front along the wall,
## a door gap between, clear of the corners, the street furniture, the vendors and the alley's
## mouth. Fills `sellers` with the people to stand by them.
static func build_pavement(ch: CityChunk, block: Dictionary, sellers: Array) -> void:
	var info := block_info(ch.plan, ch.ix, ch.iz)
	if info.is_empty() or not _open(ch, OPEN_HOURS):
		return
	var plan := ch.plan
	var rect: Rect2 = block.rect
	var st := _state(ch)
	var walls := StreetDetail._footprints(ch)
	var occupied := Encampment._occupied(ch)
	for c in ch.get_children():
		if c is EncampmentItem:
			occupied.append([Vector2((c as Node3D).position.x, (c as Node3D).position.z), 1.2])
	var edges := CityChunk._sidewalk_edges(rect)
	var east: float = info.east
	var laid := 0
	for e: int in info.faces:
		var a: Vector2 = edges[e][0]
		var b: Vector2 = edges[e][1]
		var inward: Vector2 = edges[e][2]
		var dir := (b - a).normalized()
		var length := a.distance_to(b)
		var t := CORNER_CLEAR
		var slot := 0
		var street := -inward
		var yaw := atan2(street.x, street.y)
		while t < length - CORNER_CLEAR and laid < MAX_SETS:
			var v := absi(hash([plan.seed, "fashion_set", ch.ix, ch.iz, e, slot])) % FashionKit.SET_VARIANTS
			var fs := FashionKit.frontage(v)
			var len: float = fs.length
			var mid := t + len * 0.5
			slot += 1
			if t + len > length - CORNER_CLEAR:
				break
			var kerb := a + dir * mid
			var ok := kerb.x <= east and h01([plan.seed, "fashion_empty", ch.ix, ch.iz, e, slot]) >= EMPTY_ODDS
			# The wall along the set's whole length: a shop front, not a forecourt or a gap.
			var depth := INF
			if ok:
				for q: float in [-0.45, 0.0, 0.45]:
					var d := _wall_depth(walls, a + dir * (mid + q * len), inward)
					if d > MAX_WALL_DEPTH:
						ok = false
						st.stats.rej_wall = int(st.stats.get("rej_wall", 0)) + 1
						break
					depth = minf(depth, d)
			if ok and (Alleys.in_mouth(plan, ch.ix, ch.iz, kerb + inward * 2.0) or Alleys.in_mouth(plan, ch.ix, ch.iz, a + dir * (t - 1.0) + inward * 2.0) \
					or Alleys.in_mouth(plan, ch.ix, ch.iz, a + dir * (t + len + 1.0) + inward * 2.0)):
				ok = false
				st.stats.rej_mouth = int(st.stats.get("rej_mouth", 0)) + 1
			var front := kerb + inward * (depth - WALL_OFF)
			if ok:
				for k in 5:
					var p := front + dir * (float(k) / 4.0 - 0.5) * len - inward * 0.6
					if not Encampment._clear_of(occupied, p, 0.5):
						ok = false
						st.stats.rej_occ = int(st.stats.get("rej_occ", 0)) + 1
						break
			if ok:
				_lay_set(ch, fs, v, Vector3(front.x, CityChunk.SIDEWALK_TOP, front.y), yaw, e, slot)
				laid += 1
				if slot % SELLER_EVERY == 1 and sellers.size() < MAX_SELLERS:
					var end := front + dir * (len * 0.5 + 0.55) - inward * 0.9
					sellers.append({"kind": "seller", "at": end, "yaw": atan2(street.x - dir.x * 0.6, street.y - dir.y * 0.6), "seed": hash([plan.seed, "fashion_seller", ch.ix, ch.iz, e, slot]), "rect": rect})
				if (st.eyes as Array).size() < 6:
					var eye := front - inward * 6.5 + dir * 3.0
					(st.eyes as Array).append("%.1f,1.7,%.1f,%.0f,-4" % [eye.x, eye.y, rad_to_deg(atan2(-(inward.x - dir.x * 0.4), -(inward.y - dir.y * 0.4))) + 180.0])
			t += len + DOOR_GAP
	st.stats.sets = int(st.stats.sets) + laid
	sets_laid += laid
	for v in FashionKit.SET_VARIANTS:
		var key := "fd_set_%d" % v
		ch._batch.set_draw_distance(key, GOODS_DRAW)
		ch._batch.set_no_shadow(key)


## One frontage set as a prop (it breaks as one: shot to pieces, the debris flies, it stays gone).
static func _lay_set(ch: CityChunk, fs: Dictionary, v: int, at: Vector3, yaw: float, e: int, slot: int) -> void:
	var b := Basis(Vector3.UP, yaw)
	var custom := Color(h01([ch.plan.seed, "fd_hue", ch.ix, ch.iz, e, slot]), h01([ch.ix, ch.iz, e, slot]), 0.0, 0.0)
	var shapes: Array = []
	for bx: Array in fs.boxes:
		var size: Vector3 = bx[0]
		var c: Vector3 = at + b * (bx[1] as Vector3)
		shapes.append([size, c, yaw])
	ch._add_prop("fd_set", at, Color(0.5, 0.42, 0.36), [["fd_set_%d" % v, fs.mesh, Transform3D(b, at), Color.WHITE, custom]], shapes)
	var st := _state(ch)
	st.stats.set_tris = int(st.stats.set_tris) + int(fs.tris)


## A seller by the goods, a stall keeper or a shopper (one build step each, under the crowd cap).
static func spawn_person(ch: CityChunk, people: Array, index: int) -> void:
	if index >= people.size() or not ch._take_crowd_room():
		return
	var s: Dictionary = people[index]
	var at: Vector2 = s.at
	var ped: Pedestrian
	if String(s.kind) == "shopper":
		var shopper := FashionShopper.new()
		shopper.setup_shopper(s.rect, int(s.seed), s.path)
		ped = shopper
	else:
		var vendor := StreetVendor.new()
		vendor.setup_vendor(s.rect, int(s.seed), at, float(s.yaw), false, float(s.get("floor", 0.0)))
		ped = vendor
	ped.position = Vector3(at.x, ch.ground_y(at.x, at.y) + float(s.get("floor", 0.0)) + 0.05, at.y)
	ch.add_child(ped)
	var st := _state(ch)
	st.stats.people = int(st.stats.people) + 1


# --- The market alley -----------------------------------------------------------------------

## AlleyKit.dress(): if this run of a district block's alley is a market, dresses it as one and
## returns true (the service alley's own dressing is then skipped); false leaves it to AlleyKit.
static func dress_market(ch: CityChunk, sp: Dictionary, r: Dictionary, idx: int) -> bool:
	var info := block_info(ch.plan, ch.ix, ch.iz)
	if info.is_empty() or not bool(info.market):
		return false
	var w: float = r.w
	var s0: float = r.s0
	var s1: float = r.s1
	# Not past the district's east edge.
	var clipped := false
	if bool(sp.along_x) and s1 > float(info.east):
		s1 = float(info.east)
		clipped = true
	if w < ONE_SIDE_W or s1 - s0 < 24.0 or ch.level != CityChunk.Level.FULL or ch.capturing:
		return false
	var plan := ch.plan
	var along_x: bool = sp.along_x
	var c: float = r.c
	var hw := w * 0.5
	var across := Vector3(0.0, 0.0, 1.0) if along_x else Vector3(1.0, 0.0, 0.0)
	var along := Vector3(1.0, 0.0, 0.0) if along_x else Vector3(0.0, 0.0, 1.0)
	var y0 := CityChunk.SIDEWALK_TOP + Alleys.LIFT
	var st := _state(ch)
	# A market is between two rows of buildings: a side the buildings leave open (a forecourt, a
	# lawn, a car park) gets no stalls, and a run with neither side walled is no market.
	var walls := _wall_rects(ch)
	var walled: Array = []
	for side: float in [-1.0, 1.0]:
		if _cover(walls, along_x, s0, s1, c + side * hw, side) >= MIN_WALLED:
			walled.append(side)
	if OS.get_environment("FASHION_DEBUG") == "1":
		print("FASHION market? block %d,%d run %d s %.0f..%.0f c %.1f w %.1f cover %.2f / %.2f walls %d" % [ch.ix, ch.iz, idx, s0, s1, c, w,
			_cover(walls, along_x, s0, s1, c - hw, -1.0), _cover(walls, along_x, s0, s1, c + hw, 1.0), walls.size()])
	if walled.is_empty():
		return false
	# Both sides when there is room (a side with no wall gets freestanding stalls, their gridwall
	# backs to the open ground); else the walled side.
	var sides: Array = [-1.0, 1.0] if w >= BOTH_SIDES_W else [walled[0] if walled.size() == 1 else (-1.0 if h01([plan.seed, "fd_side", ch.ix, ch.iz, idx]) < 0.5 else 1.0)]
	# The utility poles AlleyKit will stand down the alley: no stall over one.
	var poles := AlleyKit.pole_spots(ch, sp, r)
	var people: Array = []
	var run_rect := Rect2()
	var p0 := AlleyKit._wp(along_x, s0, c - hw)
	var p1 := AlleyKit._wp(along_x, s1, c + hw)
	run_rect = Rect2(Vector2(minf(p0.x, p1.x), minf(p0.y, p1.y)), Vector2(absf(p1.x - p0.x), absf(p1.y - p0.y)))
	var stalls := 0
	var keepers := 0
	# How far the stalls stand into the alley itself at most (they back onto the walls).
	var intrude := 0.0
	for side: float in sides:
		var zdir := across * -side
		var basis := Basis(Vector3.UP.cross(zdir), Vector3.UP, zdir)
		var s := s0 + MOUTH_CLEAR + STALL_W * 0.5
		var k := 0
		while s < s1 - MOUTH_CLEAR - STALL_W * 0.5:
			var blocked := false
			for pole: float in pole_spots_on(poles, side):
				if absf(pole - s) < STALL_W * 0.5 + 0.4:
					blocked = true
			# The stall's back against the building behind the alley's edge (across its service
			# strip, if it has one), never open ground.
			var g := 0.0
			for q: float in [-0.4, 0.0, 0.4]:
				g = maxf(g, _gap(walls, along_x, s + q * STALL_W, c + side * hw, side))
			# The aisle keeps AISLE metres: a stall stands no further into the alley than that leaves.
			var need := maxf(0.0, STALL_D - (w - AISLE) / float(sides.size()))
			if g == INF or g > MAX_STRIP:
				# Open ground behind: a freestanding stall, its gridwall back to it.
				g = need
			elif g < need:
				blocked = true
			var p := AlleyKit._wp(along_x, s, c + side * (hw + g - 0.04))
			var at := Vector3(p.x, y0, p.y)
			var roll := h01([plan.seed, "fd_stall", ch.ix, ch.iz, idx, side, k])
			if not blocked:
				intrude = maxf(intrude, STALL_D - g)
			if blocked:
				pass
			elif roll < GAP_ODDS:
				# A gap: mannequins at the aisle's edge, or a hand truck of cartons.
				var gv := absi(hash([plan.seed, "fd_gap", ch.ix, ch.iz, idx, side, k]))
				var gat := at + zdir * 0.5
				if gv % 2 == 0:
					var mv := gv % FashionKit.MANNEQUIN_VARIANTS
					for q in 2:
						var mp := gat + along * (float(q) - 0.5) * 0.8
						ch._add_prop("fd_manq", mp, Color(0.9, 0.9, 0.9), [["fd_manq_%d" % mv, _manq_mesh(mv), Transform3D(Basis(Vector3.UP, atan2(zdir.x, zdir.z) + (float(q) - 0.5) * 0.6), mp)]],
							[[Vector3(0.45, 1.75, 0.45), mp + Vector3(0.0, 0.88, 0.0), 0.0]])
				else:
					var tv := gv % FashionKit.TRUCK_VARIANTS
					ch._add_prop("fd_truck", gat, Color(0.6, 0.45, 0.3), [["fd_truck_%d" % tv, _truck_mesh(tv), Transform3D(basis.rotated(Vector3.UP, (h01([gv]) - 0.5) * 0.8), gat)]],
						[[Vector3(0.6, 1.3, 0.6), gat + Vector3(0.0, 0.65, 0.0), 0.0]])
			else:
				var v := absi(hash([plan.seed, "fd_stall_v", ch.ix, ch.iz, idx, side, k])) % FashionKit.STALL_VARIANTS
				var custom := Color(h01([plan.seed, "fd_shue", ch.ix, ch.iz, idx, side, k]), roll, h01([ch.ix, ch.iz, k, "wear"]), 0.0)
				var centre := at + zdir * STALL_D * 0.5
				ch._add_prop("fd_stall", centre, Color(0.35, 0.4, 0.5), [["fd_stall_%d" % v, FashionKit.stall_mesh(v), Transform3D(basis, at), Color.WHITE, custom]],
					[[Vector3(STALL_W, 2.6, STALL_D - 0.1), centre + Vector3(0.0, 1.3, 0.0), atan2(zdir.x, zdir.z)]])
				stalls += 1
				if stalls % KEEPER_EVERY == 1 and keepers < MAX_KEEPERS:
					var kp := at + zdir * (STALL_D + 0.35) + along * (STALL_W * 0.32 * (1.0 if k % 2 == 0 else -1.0))
					people.append({"kind": "keeper", "at": Vector2(kp.x, kp.z), "yaw": atan2(-zdir.x, -zdir.z) + 0.5 * (h01([k, "ky"]) - 0.5), "seed": hash([plan.seed, "fd_keeper", ch.ix, ch.iz, idx, side, k]), "rect": run_rect, "floor": Alleys.LIFT})
					keepers += 1
			s += STALL_W + 0.1
			k += 1
	# Overhead: tarps, bulb strings, a banner at each mouth.
	var span := w + 0.7
	var s := s0 + 2.0 + 3.0 * h01([plan.seed, "fd_tarp0", ch.ix, ch.iz, idx])
	var ti := 0
	var tb := Basis(across, Vector3.UP, across.cross(Vector3.UP))
	if across.cross(Vector3.UP).dot(along) < 0.0:
		tb = Basis(across, Vector3.UP, -across.cross(Vector3.UP))
	while s < s1 - 2.0:
		var tlen := 3.0 + 2.0 * h01([plan.seed, "fd_tlen", ch.ix, ch.iz, idx, ti])
		var tv := absi(hash([plan.seed, "fd_tarp", ch.ix, ch.iz, idx, ti])) % 6
		var p := AlleyKit._wp(along_x, s + tlen * 0.5, c)
		var hgt := 3.8 + 0.9 * h01([plan.seed, "fd_th", ch.ix, ch.iz, idx, ti])
		var xf := Transform3D(Basis(tb.x * (span / 6.6), tb.y, tb.z * (tlen / 4.0)), Vector3(p.x, y0 + hgt, p.y))
		ch._batch.add("fd_tarp_%d" % tv, FashionKit.overhead_tarp(tv, 6.6, 4.0), xf, Color.WHITE, Color(0.5, h01([ti]), h01([ch.ix, ti, "tw"]), 0.0))
		s += tlen + lerpf(TARP_EVERY.x, TARP_EVERY.y, h01([plan.seed, "fd_tgap", ch.ix, ch.iz, idx, ti])) - tlen * 0.5
		ti += 1
	var bs := s0 + 1.5
	var bi := 0
	while bs < s1 - 1.5:
		var p := AlleyKit._wp(along_x, bs, c)
		var xf := Transform3D(Basis(tb.x * ((w + 0.2) / 6.6), tb.y, tb.z), Vector3(p.x, y0 + 3.45 + 0.2 * h01([bi, "bh"]), p.y))
		ch._batch.add("fd_bulbs", FashionKit.bulb_string(6.6), xf)
		bs += BULB_EVERY
		bi += 1
	var name_i := absi(hash([plan.seed, "fd_alley_name", ch.ix, ch.iz])) % ALLEY_NAMES.size()
	for end: int in [0, 1]:
		var reaches: bool = r.m0 if end == 0 else (r.m1 and not clipped)
		if not reaches:
			continue
		var sm := s0 + 1.2 if end == 0 else s1 - 1.2
		var p := AlleyKit._wp(along_x, sm, c)
		var bw := minf(w - 0.6, 5.2)
		ch._batch.add("fd_banner_%d" % name_i, FashionKit.banner(name_i, ALLEY_NAMES[name_i], 5.2, 0.9),
			Transform3D(Basis(tb.x * (bw / 5.2), tb.y, tb.z), Vector3(p.x, y0 + 4.9, p.y)))
	# Two warm lights down the alley (DayNight drives the group).
	for q in 2:
		var p := AlleyKit._wp(along_x, lerpf(s0, s1, 0.3 + 0.4 * float(q)), c)
		var light := OmniLight3D.new()
		light.position = Vector3(p.x, y0 + 3.2 + ch._gy(p.x, p.y), p.y)
		light.omni_range = 14.0
		light.omni_attenuation = 1.3
		light.light_color = Color(1.0, 0.80, 0.55)
		light.light_energy = 0.0
		light.shadow_enabled = false
		light.distance_fade_enabled = true
		light.distance_fade_begin = 50.0
		light.distance_fade_length = 15.0
		light.add_to_group("lamp_light")
		ch.add_child(light)
	# Shoppers strolling the aisle with their bags (and the keepers: nobody after hours).
	if not _open(ch, MARKET_HOURS):
		people.clear()
	var n_shop := clampi(roundi((s1 - s0) * SHOPPERS_PER_M), 3, MAX_SHOPPERS) if _open(ch, MARKET_HOURS) else 0
	var lane_half := maxf(0.3, (w - maxf(intrude, 0.0) * float(sides.size()) - 0.6) * 0.5)
	var lane_c := c + (0.0 if sides.size() == 2 else (maxf(intrude, 0.0) * 0.5 * (1.0 if sides[0] < 0.0 else -1.0)))
	var spath := [AlleyKit._wp(along_x, s0 + 1.0, lane_c), AlleyKit._wp(along_x, s1 - 1.0, lane_c), lane_half, along_x]
	for i in n_shop:
		var sh := lerpf(s0 + 2.0, s1 - 2.0, h01([plan.seed, "fd_shop_s", ch.ix, ch.iz, idx, i]))
		var off := (h01([plan.seed, "fd_shop_o", ch.ix, ch.iz, idx, i]) - 0.5) * 2.0 * lane_half
		var sp2 := AlleyKit._wp(along_x, sh, lane_c + off)
		people.append({"kind": "shopper", "at": sp2, "seed": hash([plan.seed, "fd_shopper", ch.ix, ch.iz, idx, i]), "rect": run_rect, "path": spath, "floor": Alleys.LIFT})
	for key: String in ch._batch.keys():
		# Shadows: the tarps cast over the aisle; the stalls and goods under them cast none (a
		# chunk-wide batch's shadow reach is measured to its bounds' centre, so it would cast
		# the whole alley into every cascade - most of the frame cost; they stand in the tarps'
		# and the buildings' shade anyway).
		if key.begins_with("fd_tarp"):
			ch._batch.set_draw_distance(key, STALL_DRAW)
		elif key.begins_with("fd_stall") or key.begins_with("fd_banner"):
			ch._batch.set_draw_distance(key, STALL_DRAW)
			ch._batch.set_no_shadow(key)
		elif key == "fd_bulbs" or key.begins_with("fd_manq") or key.begins_with("fd_truck"):
			ch._batch.set_draw_distance(key, GOODS_DRAW)
			ch._batch.set_no_shadow(key)
	st.stats.stalls = int(st.stats.stalls) + stalls
	st.stats.tarps = int(st.stats.tarps) + ti
	st.stats.markets = int(st.stats.markets) + 1
	stalls_laid += stalls
	markets_laid += 1
	var mid := AlleyKit._wp(along_x, lerpf(s0, s1, 0.15), c)
	var look := AlleyKit._wp(along_x, s1, c) - mid
	(st.eyes as Array).push_front("%.1f,1.7,%.1f,%.0f,2 market s %.0f..%.0f c %.1f w %.1f sides %s stalls %d" % [mid.x, mid.y, rad_to_deg(atan2(-look.x, -look.y)), s0, s1, c, w, sides, stalls])
	st.stats.planned = int(st.stats.planned) + people.size()
	var jobs: Array[Callable] = []
	for i in people.size():
		jobs.append(spawn_person.bind(ch, people, i))
	YardFill._defer(ch, jobs)
	return true


## How far in from the kerb the shop wall is at `kerb_point` (Encampment's search, further in:
## a forecourt's goods stand at the shop front too), INF when no wall is within MAX_WALL_DEPTH.
static func _wall_depth(walls: Array[Rect2], kerb_point: Vector2, inward: Vector2) -> float:
	for k in 28:
		var d := 2.5 + float(k) * 0.25
		for r: Rect2 in walls:
			if r.has_point(kerb_point + inward * d):
				return d
	return INF


## The buildings' ground parts round the alley (what the lots recorded for Alleys).
static func _wall_rects(ch: CityChunk) -> Array[Rect2]:
	var out: Array[Rect2] = []
	var foot: Dictionary = Alleys._state(ch).foot
	for k in foot:
		for r: Rect2 in foot[k]:
			out.append(r)
	return out


## How far beyond the alley's edge at `edge` (across) on `side` the first building stands at
## `s` along it, or INF when none within WALL_REACH.
static func _gap(walls: Array[Rect2], along_x: bool, s: float, edge: float, side: float) -> float:
	var d := 0.05
	while d <= WALL_REACH:
		var q := AlleyKit._wp(along_x, s, edge + side * d)
		for r: Rect2 in walls:
			if r.has_point(q):
				return maxf(d - 0.1, 0.0)
		d += 0.25
	return INF


## How much of the alley's edge at `edge` (across), from s0 to s1, has a building within
## WALL_REACH beyond it on `side` (0..1).
static func _cover(walls: Array[Rect2], along_x: bool, s0: float, s1: float, edge: float, side: float) -> float:
	var n := maxi(2, ceili((s1 - s0) / 1.0))
	var hit := 0
	for i in n:
		var s := lerpf(s0, s1, (float(i) + 0.5) / float(n))
		var found := false
		for d: float in [0.3, 1.2, 2.2, 3.4, 4.6, 5.8, WALL_REACH]:
			var q := AlleyKit._wp(along_x, s, edge + side * d)
			for r: Rect2 in walls:
				if r.has_point(q):
					found = true
					break
			if found:
				break
		hit += 1 if found else 0
	return float(hit) / float(n)


## Whether the hour the chunk is built at falls in `hours`.
static func _open(ch: CityChunk, hours: Vector2) -> bool:
	var h := force_hour if force_hour >= 0.0 else StreetVendors.hour_now(ch)
	return h >= hours.x and h < hours.y


## The poles on one side of a run (AlleyKit.pole_spots(): [along, across, side]) as their along
## coordinates.
static func pole_spots_on(poles: Array, side: float) -> Array:
	var out: Array = []
	for p: Array in poles:
		if int(p[2]) == int(side):
			out.append(float(p[0]))
	return out


static func _manq_mesh(v: int) -> ArrayMesh:
	var key := "manq_mesh_%d" % v
	if not FashionKit._cache.has(key):
		FashionKit._cache[key] = FashionKit.mannequin(v).commit()
	return FashionKit._cache[key]


static func _truck_mesh(v: int) -> ArrayMesh:
	var key := "truck_mesh_%d" % v
	if not FashionKit._cache.has(key):
		FashionKit._cache[key] = FashionKit.hand_truck(v).commit()
	return FashionKit._cache[key]
