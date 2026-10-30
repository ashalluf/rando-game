class_name BoulevardSigns
extends RefCounted
## The visual noise of LA's commercial boulevards (the signage pass, 2026-10-05):
##   * tall POLE SIGNS on the boulevard frontage of MIDTOWN lots (in the gap between two
##     buildings, or at the front corner of a surface car park) and beside the SUBURBS' plazas and
##     big boxes - a strip-mall tenant pylon, a Googie motel sign (chasing bulbs, NO VACANCY neon,
##     COLOR TV / FREE WIFI plates), a liquor or check-cashing cabinet, a tyre shop's with a giant
##     tyre (SignKit's meshes, invented names in the atlas);
##   * WINDOW VINYL on the shop windows (promos picked by what the shop is: phone offers on a phone
##     shop, menu pictures on a taqueria, EBT / ATM / LOTTERY on a liquor store, SE HABLA ESPAÑOL,
##     NOW HIRING, Korean / Armenian / Thai glyph runs) and vinyl BANNERS over some sign bands
##     (GRAND OPENING, LIQUIDATION SALE, ...);
##   * LAMP-POST BANNERS in pairs on the lamps of some boulevards (invented city events and
##     district names), swaying in the wind;
##   * STREET PLATES at a real density: stacked parking / street-cleaning / no-stopping plates on
##     their own posts along the kerb, a BASIN TRANSIT bus-zone post by every bus shelter, and
##     wayfinding signs on some boulevard corners.
## The art is one atlas (tools/make_sign_art.py), everything one material
## (shaders/boulevard_sign.gdshader), one batch per kind a chunk.
##
## Every roll is a hash of seed + place, never a chunk, block or Building rng, and everything is
## placed after the block's own props (the props keep their ids). FULL chunks only, except the
## tall pole signs' heads: LOD chunks and the far city keep a motel sign's or a pylon's head as a
## lit far box (the roof plant's PANEL, like a billboard's) and its pole as a MAST.

## Off: nothing is added (the A/B; BOULEVARD_SIGNS=0 in the environment).
static var enabled: bool = OS.get_environment("BOULEVARD_SIGNS") != "0"

## The atlas grid, as tools/make_sign_art.py draws it: [origin y, cell w, cell h, columns, count].
const FAMILIES := {
	"TENANT": [0, 512, 128, 4, 24],
	"NAME": [768, 512, 256, 4, 12],
	"VINYL": [1536, 256, 256, 8, 16],
	"BANNER": [2048, 512, 128, 4, 8],
	"LAMPB": [2304, 128, 384, 16, 16],
	"PLATE": [2688, 128, 192, 16, 32],
}

enum Pole { TENANT, MOTEL, LIQUOR, CHECKS, TIRE }
const POLE_KEYS := ["sg_tenant", "sg_motel_", "sg_box", "sg_box", "sg_tire"]

## Odds a candidate spot on a boulevard frontage gets a pole sign: the gap between two buildings,
## and the front corner of a surface car park.
const GAP_ODDS := 0.14
const PARK_ODDS := 0.6
## Odds a SUBURBS plaza or big box gets a second pole sign at its other front corner.
const PLAZA_ODDS := 0.65
## The least gap a sign stands in (both sides of its cabinet clear), and the least distance
## between two pole signs on one frontage.
const MIN_GAP := 2.4
const SPACING := 28.0
## Where the pole stands: this far into the lot from the back of the pavement.
const POLE_IN := 0.35
## Which kind, in MIDTOWN gaps / at a car park / beside a plaza: cumulative odds over Pole.
const KIND_GAP := [0.28, 0.48, 0.7, 0.86, 1.0]
const KIND_PARK := [0.45, 0.8, 0.88, 0.94, 1.0]
const KIND_PLAZA := [0.4, 0.62, 0.8, 0.86, 1.0]
## Pole signs' draw distance and their shadows'.
const POLE_DRAW := 420.0
const POLE_SHADOW := 120.0
## A pole sign leaves a street tree this much room along the kerb.
const TREE_CLEAR := 1.8

## Window vinyl: the odds a shop has any (by district), how many pieces at most, the draw distance.
const VINYL_ODDS := [0.45, 0.6, 0.35, 0.25, 0.2, 0.45]
const VINYL_MAX := 3
const VINYL_DRAW := 70.0
## Banners over a sign band: the odds a shop has one, the draw distance.
const BANNER_ODDS := 0.07
const BANNER_DRAW := 140.0
## How far a shop's face may stand back from the pavement and still be dressed.
const MAX_SETBACK := 7.0

## Lamp-post banners: the odds a boulevard carries them (by district), the draw distance.
const LAMPB_ODDS := [0.35, 0.45, 0.15, 0.0, 0.3, 0.5]
const LAMPB_DRAW := 170.0

## Street plates: the spacing of the posts along a kerb (by district; 0 none), how far in from the
## kerb a post stands, the draw distance.
const PLATE_SPACING := [34.0, 38.0, 70.0, 80.0, 60.0, 45.0]
const POST_IN := 0.45
const PLATE_DRAW := 110.0
## Wayfinding signs: the odds a boulevard frontage gets one (by district).
const WAYFIND_ODDS := [0.18, 0.12, 0.0, 0.0, 0.1, 0.12]

## Which plates make a post's stack: the time limits (green), street cleaning (red), the others.
const P_LIMIT := [0, 1, 18, 25, 27, 29, 31, 23]
const P_CLEAN := [2, 3, 24, 26, 28, 30]
const P_OTHER := [4, 5, 6, 7, 19, 20, 21, 22]
const P_ARROWS := [16, 17]
const P_BUS := [9, 10, 11]

## Vinyl cells by what the shop is (Building.SHOP_NAMES), and the general ones.
const VINYL_BY_NAME := {
	"PHONE FIX": [2, 3, 0], "LIQUOR": [6, 12, 5, 14], "TACOS": [4, 0, 1], "TAX PRO": [0, 14, 13],
	"PHARMACY": [13, 1, 6], "BANK": [14, 13], "DELI": [4, 1], "PIZZA": [1, 13], "SMOKE SHOP": [6, 12],
	"LAUNDRY": [13, 0], "BARBER": [0, 8, 13], "NAILS & SPA": [10, 9, 13], "DONUT HOLE": [1, 13],
	"THRIFT": [7, 15], "CAMERA": [5, 7], "BAKERY": [9, 13], "SUSHI": [8, 10],
}
const VINYL_ANY := [0, 1, 7, 8, 9, 10, 11, 13, 1, 0]

const K_PLATE := "sg_plate"
const K_POST := "sg_post"
const K_LAMPB := "sg_lampb"
const K_ARMS := "sg_lampb_arms"
const K_VINYL := "sg_vinyl"
const K_BANNER := "sg_banner"
const K_WAYFIND := "sg_wayfind"


static func _h01(parts: Array) -> float:
	return float(absi(hash(parts)) % 100003) * (1.0 / 100003.0)


static func _pick(cum: Array, r: float) -> int:
	for i in cum.size():
		if r < float(cum[i]):
			return i
	return cum.size() - 1


## [axis, index] of the road beside sidewalk edge `e` (CityChunk._sidewalk_edges() order).
static func edge_road(ix: int, iz: int, e: int) -> Array:
	match e:
		0: return [CityPlan.AXIS_Z, iz]
		1: return [CityPlan.AXIS_Z, iz + 1]
		2: return [CityPlan.AXIS_X, ix]
	return [CityPlan.AXIS_X, ix + 1]


static func is_boulevard(plan: CityPlan, axis: int, index: int) -> bool:
	return plan.road_width(axis, index) > plan.street_width + 1.0


## Whether a boulevard carries lamp-post banners (a hash of the road; the district is the block's).
static func banner_street(plan: CityPlan, axis: int, index: int, district: int) -> bool:
	if not is_boulevard(plan, axis, index):
		return false
	return _h01([plan.seed, "sg_lampb_street", axis, index]) < float(LAMPB_ODDS[district])


# --- Pole signs: the plan ------------------------------------------------------------------------

## The pole signs of block (ix, iz), pure (hashes of the plan only), the same for every level:
## [{kind, at (pole foot, XZ), out (into the lot), along, a, b, flags, seed, e}].
static func plan_poles(plan: CityPlan, ix: int, iz: int) -> Array:
	var out: Array = []
	if not enabled:
		return out
	var block := plan.block(ix, iz)
	if block.has("site") or block.has("grounds"):
		return out
	var district := int(block.district)
	var kind := int(block.kind)
	var rect: Rect2 = block.rect
	var sw := plan.sidewalk_width
	var edges := CityChunk._sidewalk_edges(rect)
	var cands: Array = []
	if district == CityPlan.District.MIDTOWN and kind == CityPlan.BlockKind.BUILDINGS:
		var lots := plan.lots(ix, iz)
		for e in 4:
			var road := edge_road(ix, iz, e)
			if not is_boulevard(plan, road[0], road[1]):
				continue
			var a: Vector2 = edges[e][0]
			var b: Vector2 = edges[e][1]
			var inward: Vector2 = edges[e][2]
			var dir := (b - a).normalized()
			var line := a + inward * sw
			for lot: Dictionary in lots:
				var cell: Rect2 = lot.cell
				var lr := Rect2((lot.center as Vector2) - (lot.size as Vector2) * 0.5, lot.size)
				# The lot's front on this face: its cell reaches the back of the pavement.
				if absf((cell.get_center() - line).dot(inward) - _half(cell, inward)) > 0.6:
					continue
				var c_lo := (cell.position - a).dot(dir)
				var c_hi := (cell.end - a).dot(dir)
				var lo := minf(c_lo, c_hi)
				var hi := maxf(c_lo, c_hi)
				var r_lo := minf((lr.position - a).dot(dir), (lr.end - a).dot(dir))
				var r_hi := maxf((lr.position - a).dot(dir), (lr.end - a).dot(dir))
				if bool(lot.parking):
					var t := r_lo + 1.4
					cands.append({"e": e, "t": t, "src": "park", "id": [lot.seed, "p", e]})
					continue
				# The gap past the lot's +dir side, if it is not the block's end.
				if hi < a.distance_to(b) - sw - 1.0:
					var half_gap := hi - r_hi
					var other := _lot_at(lots, line + dir * (hi + 1.0) + inward * 2.0)
					var other_half := 99.0
					if not other.is_empty():
						var olr := Rect2((other.center as Vector2) - (other.size as Vector2) * 0.5, other.size)
						other_half = minf((olr.position - a).dot(dir), (olr.end - a).dot(dir)) - hi
					if half_gap + other_half >= MIN_GAP and half_gap >= MIN_GAP * 0.4 and other_half >= MIN_GAP * 0.4:
						# In the middle of the gap.
						var mid := hi + (other_half - half_gap) * 0.5 if other_half < 50.0 else hi + 0.5
						cands.append({"e": e, "t": mid, "src": "gap", "id": [lot.seed, "g", e]})
	elif (district == CityPlan.District.SUBURBS or district == CityPlan.District.MIDTOWN) \
			and (kind == CityPlan.BlockKind.MALL or kind == CityPlan.BlockKind.BIGBOX):
		# The plaza's front is the -z face (Commercial lays the strip at the back, +z); its own
		# pylon stands at the -x front corner, this one at the +x.
		var road := edge_road(ix, iz, 0)
		if is_boulevard(plan, road[0], road[1]) or kind == CityPlan.BlockKind.MALL:
			var len := (edges[0][1] as Vector2).distance_to(edges[0][0])
			cands.append({"e": 0, "t": len - sw - 3.0, "src": "plaza", "id": [ix, iz, "plaza"]})
	# Roll, then keep them SPACING apart on a face (in order along it).
	cands.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return x.e < y.e or (x.e == y.e and float(x.t) < float(y.t)))
	var last := {}
	for c: Dictionary in cands:
		var src := String(c.src)
		var odds := GAP_ODDS if src == "gap" else (PARK_ODDS if src == "park" else PLAZA_ODDS)
		var hid: Array = [plan.seed, "sg_pole"] + (c.id as Array)
		if _h01(hid) >= odds:
			continue
		var e := int(c.e)
		if last.has(e) and float(c.t) - float(last[e]) < SPACING:
			continue
		var a: Vector2 = edges[e][0]
		var b: Vector2 = edges[e][1]
		var inward: Vector2 = edges[e][2]
		var dir := (b - a).normalized()
		var at := a + dir * float(c.t) + inward * (sw + POLE_IN)
		var road := edge_road(ix, iz, e)
		if not plan.road_open(road[0], road[1], at.y if road[0] == CityPlan.AXIS_X else at.x):
			continue
		if plan.macro and Landmarks.covers(plan, at, 6.0):
			continue
		if not StreetWear.allowed(at):
			continue
		# Nothing under or against a freeway deck or ramp: the head reaches 4.5 m into the lot.
		if plan.macro and plan.macro.freeway and plan.macro.freeway.blocks_rect(Rect2(at - Vector2(5.0, 5.0), Vector2(10.0, 10.0)), 1.0):
			continue
		last[e] = float(c.t)
		var cum: Array = KIND_GAP if src == "gap" else (KIND_PARK if src == "park" else KIND_PLAZA)
		var pk := _pick(cum, _h01(hid + ["kind"]))
		var s := _h01(hid + ["seed"])
		var pa := 0
		var pb := 0
		var flags := 0
		match pk:
			Pole.TENANT:
				pa = int(s * 4.0) % 4
				pb = absi(hash(hid + ["tenants"])) % 20
			Pole.MOTEL:
				pa = int(s * SignKit.MOTELS) % SignKit.MOTELS
				pb = 12 if _h01(hid + ["plates"]) < 0.6 else 14
				flags = (1 if _h01(hid + ["full"]) < 0.4 else 0) + (2 if _h01(hid + ["flicker"]) < 0.2 else 0)
			Pole.LIQUOR:
				pa = 5 + int(s * 2.0) % 2
			Pole.CHECKS:
				pa = 7 + int(s * 2.0) % 2
			Pole.TIRE:
				pa = 9 + int(s * 2.0) % 2
		out.append({"kind": pk, "at": at, "out": inward, "along": dir, "a": pa, "b": pb, "flags": flags, "seed": s, "e": e})
	return out


static func _half(r: Rect2, axis_dir: Vector2) -> float:
	return absf(axis_dir.x) * r.size.x * 0.5 + absf(axis_dir.y) * r.size.y * 0.5


static func _lot_at(lots: Array, p: Vector2) -> Dictionary:
	for lot: Dictionary in lots:
		if (lot.cell as Rect2).has_point(p):
			return lot
	return {}


## The instance transform of a pole sign (the batch adds the relief).
static func pole_xform(p: Dictionary) -> Transform3D:
	var o: Vector2 = p.out
	var x := Vector3(o.x, 0.0, o.y)
	var basis := Basis(x, Vector3.UP, x.cross(Vector3.UP))
	var at: Vector2 = p.at
	return Transform3D(basis, Vector3(at.x, CityChunk.SIDEWALK_TOP, at.y))


static func pole_mesh(kind: int, a: int) -> Mesh:
	match kind:
		Pole.TENANT: return SignKit.tenant_pylon()
		Pole.MOTEL: return SignKit.motel(a)
		Pole.TIRE: return SignKit.box_sign(true)
	return SignKit.box_sign(false)


static func pole_key(kind: int, a: int) -> String:
	return POLE_KEYS[kind] + (str(a) if kind == Pole.MOTEL else "")


## Collision boxes [size, centre (local), ...] of a pole sign kind: the pole and the head.
static func _pole_shapes(kind: int) -> Array:
	match kind:
		Pole.TENANT:
			return [[Vector3(SignKit.TENANT_W + 0.2, SignKit.TENANT_TOP, SignKit.CAB_DEPTH + 0.1), Vector3(SignKit.TENANT_CX, SignKit.TENANT_TOP * 0.5, 0.0)]]
		Pole.MOTEL:
			return [[Vector3(0.45, SignKit.MOTEL_POLE_TOP, 0.45), Vector3(0.0, SignKit.MOTEL_POLE_TOP * 0.5, 0.0)],
				[Vector3(SignKit.MOTEL_BOARD.x + 1.0, SignKit.MOTEL_BOARD.y, 0.5), Vector3(SignKit.MOTEL_BOARD_C.x, SignKit.MOTEL_BOARD_C.y, 0.0)],
				[Vector3(1.4, 5.8, 0.3), Vector3(3.6, 7.7, 0.0)]]
	var top := SignKit.BOX_BOTTOM + SignKit.BOX_H
	return [[Vector3(0.35, top, 0.35), Vector3(0.0, top * 0.5, 0.0)],
		[Vector3(SignKit.BOX_W + 0.3, SignKit.BOX_H, SignKit.CAB_DEPTH), Vector3(SignKit.BOX_CX, SignKit.BOX_BOTTOM + SignKit.BOX_H * 0.5, 0.0)]]


## The far boxes of block (ix, iz)'s tall pole signs (LOD chunks; the far city captures them): a
## pylon's or a motel sign's head as a lit PANEL in its art's mean colour, its pole as a MAST.
static func block_step(ch: CityChunk, block: Dictionary) -> void:
	if not enabled or ch.plan == null or (ch.level == CityChunk.Level.FULL and not ch.capturing):
		return
	if int(block.district) != CityPlan.District.MIDTOWN and int(block.district) != CityPlan.District.SUBURBS:
		return
	var flag := FarBuilding.PLANT_FLAG
	for p: Dictionary in plan_poles(ch.plan, ch.ix, ch.iz):
		var kind := int(p.kind)
		if kind != Pole.TENANT and kind != Pole.MOTEL:
			continue
		var xf := pole_xform(p)
		var yaw := atan2(-xf.basis.z.x, -xf.basis.z.z)
		var head_c: Vector3
		var head: Vector3
		var colour: Color
		var top: float
		if kind == Pole.TENANT:
			var h := SignKit.TENANT_TOP - 4.0
			head = Vector3(SignKit.TENANT_W, h, 0.5)
			head_c = Vector3(SignKit.TENANT_CX, SignKit.TENANT_TOP - h * 0.5, 0.0)
			colour = SignArtTable.TENANT_MEAN[int(p.a) % 4].lerp(Color(0.7, 0.7, 0.66), 0.4).linear_to_srgb()
			top = 4.0
		else:
			head = Vector3(SignKit.MOTEL_BOARD.x, SignKit.MOTEL_BOARD.y, 0.5)
			head_c = Vector3(SignKit.MOTEL_BOARD_C.x, SignKit.MOTEL_BOARD_C.y, 0.0)
			colour = SignArtTable.NAME_MEAN[int(p.a)].linear_to_srgb()
			top = SignKit.MOTEL_POLE_TOP
		var o := xf * head_c
		var basis := Basis(Vector3.UP, yaw).scaled_local(head)
		ch._batch.add("lod_box", PropFactory.unit_box(), Transform3D(basis, o), colour, Color(float(FarBuilding.Plant.PANEL), 1.0, 1.0, flag))
		var foot := xf.origin
		ch._batch.add("lod_box", PropFactory.unit_box(), Transform3D(Basis.from_scale(Vector3(0.35, top, 0.35)), foot + Vector3(0.0, top * 0.5, 0.0)),
			Color(0.3, 0.3, 0.32), Color(float(FarBuilding.Plant.MAST), 1.0, 0.0, flag))


# --- FULL build ----------------------------------------------------------------------------------

## Everything of one FULL chunk, as one build step at the end (after the furniture, the buildings
## and the street wear it keeps clear of).
static func build(ch: CityChunk) -> void:
	if not enabled or ch.level != CityChunk.Level.FULL or ch.capturing or ch.plan == null:
		return
	if ch.zone != MacroMap.Zone.CITY:
		return
	var plan := ch.plan
	var block := plan.block(ch.ix, ch.iz)
	if block.has("site") or block.has("grounds") or plan.river_block(ch.ix, ch.iz):
		return
	var district := int(block.district)
	var counts := {"pole": 0, "vinyl": 0, "banner": 0, "lampb": 0, "post": 0, "plate": 0, "wayfind": 0}
	_poles(ch, counts)
	if int(block.kind) == CityPlan.BlockKind.BUILDINGS and district != CityPlan.District.INDUSTRIAL:
		_shopfronts(ch, block, district, counts)
	_lamp_banners(ch, block, district, counts)
	_plates(ch, block, district, counts)
	var b := ch._batch
	for k in POLE_KEYS:
		for v in SignKit.MOTELS:
			var key := String(k) + (str(v) if k == "sg_motel_" else "")
			b.set_draw_distance(key, POLE_DRAW)
			b.set_shadow_distance(key, POLE_SHADOW)
	b.set_draw_distance(K_VINYL, VINYL_DRAW)
	b.set_no_shadow(K_VINYL)
	b.set_draw_distance(K_BANNER, BANNER_DRAW)
	b.set_no_shadow(K_BANNER)
	b.set_draw_distance(K_LAMPB, LAMPB_DRAW)
	b.set_shadow_distance(K_LAMPB, 50.0)
	b.set_draw_distance(K_ARMS, LAMPB_DRAW)
	b.set_no_shadow(K_ARMS)
	b.set_draw_distance(K_PLATE, PLATE_DRAW)
	b.set_no_shadow(K_PLATE)
	b.set_draw_distance(K_POST, PLATE_DRAW)
	b.set_shadow_distance(K_POST, 35.0)
	b.set_draw_distance(K_WAYFIND, PLATE_DRAW + 40.0)
	b.set_shadow_distance(K_WAYFIND, 45.0)
	ch.set_meta("boulevard_signs", counts)


static func _poles(ch: CityChunk, counts: Dictionary) -> void:
	var trees: Array = []
	var data: Dictionary = ch._batch.data()
	if data.has("tree_grate"):
		for x: Transform3D in data["tree_grate"].xforms:
			trees.append(Vector2(x.origin.x, x.origin.z))
	for p: Dictionary in plan_poles(ch.plan, ch.ix, ch.iz):
		var at: Vector2 = p.at
		var along: Vector2 = p.along
		var blocked := false
		for t: Vector2 in trees:
			if absf((t - at).dot(along)) < TREE_CLEAR:
				blocked = true
				break
		if blocked:
			continue
		var kind := int(p.kind)
		var xf := pole_xform(p)
		var custom := Color(float(p.a), float(p.b), float(p.flags), float(p.seed))
		var shapes: Array = []
		var yaw := atan2(xf.basis.z.x, xf.basis.z.z)
		for s: Array in _pole_shapes(kind):
			shapes.append([s[0], xf * (s[1] as Vector3), yaw])
		ch._add_prop("pole_sign", xf.origin, Color(0.3, 0.3, 0.32), [
			[pole_key(kind, int(p.a)), pole_mesh(kind, int(p.a)), xf, Color.WHITE, custom],
		], shapes)
		if not ch.prop_records.is_empty() and ch.prop_records.back().kind == "pole_sign":
			ch.prop_records.back().health = 400.0
			ch.prop_records.back()["sg"] = true
		counts.pole = int(counts.pole) + 1


# --- Shopfronts: window vinyl and banners --------------------------------------------------------

static func _shopfronts(ch: CityChunk, block: Dictionary, district: int, counts: Dictionary) -> void:
	var rect: Rect2 = block.rect
	var sw := ch.plan.sidewalk_width
	var line := rect.grow(-sw)
	for part: Dictionary in StreetWear._ground_parts(ch):
		if not bool(part.storefront) or bool(part.get("parking", false)) or bool(part.warehouse):
			continue
		var bld: Building = part.building
		var pr: Rect2 = part.rect
		for face in 4:
			var n := StreetWear._normal(face)
			# The face must look onto the pavement, at most MAX_SETBACK back from it.
			var setback: float
			match face:
				0: setback = line.end.x - pr.end.x
				1: setback = pr.position.x - line.position.x
				2: setback = line.end.y - pr.end.y
				_: setback = pr.position.y - line.position.y
			if setback < -0.5 or setback > MAX_SETBACK:
				continue
			_dress_face(ch, part, bld, face, n, district, counts)


static func _dress_face(ch: CityChunk, part: Dictionary, bld: Building, face: int, n: Vector3, district: int, counts: Dictionary) -> void:
	var along_x := face >= 2
	var size: Vector3 = part.size
	var size_u: float = size.x if along_x else size.z
	var pitch: float = part.pitch_x if along_x else part.pitch_z
	var cols := maxi(1, roundi(size_u / pitch))
	var span := int(maxf((part.spans as Vector4)[face], 1.0))
	var runs := int(ceil(float(cols) / float(span)))
	var base: float = part.base
	var sf_h := maxf(float(part.gfh) - base, 0.5)
	var cut: float = 0.0 if part.boxy else pitch
	var names := bld.shop_names(face, runs)
	for shop in runs:
		var key := bld.shop_key(face + 1, shop)
		var hid := [ch.plan.seed, "sg_shop", bld.seed, face, shop]
		var name: String = Building.SHOP_NAMES[names[shop]]
		var col0 := shop * span
		var col1 := mini(col0 + span, cols)
		var door := col0 + ShopfrontKit.door_index(key, span)
		var shop_u0 := float(col0) * pitch
		var shop_u1 := float(col1) * pitch
		if shop_u0 < cut + 0.2 or shop_u1 > size_u - cut - 0.2:
			continue
		# Vinyl on the display windows.
		if _h01(hid + ["v"]) < float(VINYL_ODDS[district]):
			var pieces := 1 + int(_h01(hid + ["vn"]) * VINYL_MAX)
			var pool: Array = VINYL_BY_NAME.get(name, VINYL_ANY)
			var placed := 0
			for c in range(col0, col1):
				if c == door or placed >= pieces:
					continue
				var hb := hid + ["bay", c]
				var glass_w := pitch * ShopfrontKit.GLASS_HALF * 2.0
				var glass_lo := base + sf_h * ShopfrontKit.GLASS_LOW + 0.08
				var glass_hi := minf(base + ShopfrontKit.TRANSOM_LOW - 0.06, base + sf_h * ShopfrontKit.GLASS_TOP - 0.05)
				var s := minf(lerpf(0.42, 0.72, _h01(hb + ["s"])), minf(glass_w * 0.45, glass_hi - glass_lo))
				if s < 0.3:
					continue
				var side := -1.0 if _h01(hb + ["side"]) < 0.5 else 1.0
				var u := (float(c) + 0.5) * pitch + side * (glass_w * 0.25)
				var high := _h01(hb + ["h"]) < 0.35
				var v := glass_hi - s * 0.5 - 0.04 if high else glass_lo + s * 0.5 + 0.02
				var cell: int = pool[absi(hash(hb + ["cell"])) % pool.size()]
				var p := StreetWear._face_point(part, face, u, v) + n * 0.01
				_add_flat(ch, K_VINYL, SignKit.vinyl(), p, n, Vector2(s, s), Color(float(cell), 0.0, 0.0, _h01(hb)))
				# Where the vinyl went (true world, with its facing), for framing stills (tools/sign_probe.gd).
				var spots: Array = ch.get_meta("sg_vinyl_spots", [])
				if spots.size() < 64:
					spots.append([p, n])
					ch.set_meta("sg_vinyl_spots", spots)
				counts.vinyl = int(counts.vinyl) + 1
				placed += 1
				# Now and then a second, smaller piece in the same window.
				if placed < pieces and _h01(hb + ["two"]) < 0.4:
					var s2 := s * 0.7
					var u2 := u - side * minf(glass_w * 0.45, s * 0.5 + s2 * 0.5 + 0.06)
					var v2 := glass_lo + s2 * 0.5 + 0.02
					var cell2: int = VINYL_ANY[absi(hash(hb + ["cell2"])) % VINYL_ANY.size()]
					if cell2 != cell and absf(u2 - (float(c) + 0.5) * pitch) < glass_w * 0.5 - s2 * 0.5:
						var q := StreetWear._face_point(part, face, u2, v2) + n * 0.011
						_add_flat(ch, K_VINYL, SignKit.vinyl(), q, n, Vector2(s2, s2), Color(float(cell2), 0.0, 0.0, _h01(hb + ["2"])))
						counts.vinyl = int(counts.vinyl) + 1
						placed += 1
		# A banner over the sign band.
		if _h01(hid + ["b"]) < BANNER_ODDS:
			var band_lo := base + sf_h * ShopfrontKit.FASCIA_LOW
			var band_hi := base + sf_h * ShopfrontKit.FASCIA_TOP
			var hgt := minf(band_hi - band_lo + 0.12, (shop_u1 - shop_u0) * 0.75 / 4.0)
			if hgt > 0.35:
				var cell := absi(hash(hid + ["bc"])) % 6
				var p := StreetWear._face_point(part, face, (shop_u0 + shop_u1) * 0.5, (band_lo + band_hi) * 0.5) + n * 0.14
				_add_flat(ch, K_BANNER, SignKit.band_banner(), p, n, Vector2(hgt, hgt), Color(float(cell), 0.0, 0.0, _h01(hid + ["bs"])))
				counts.banner = int(counts.banner) + 1


## A flat piece at TRUE point `p` (the batch adds the relief, so it is taken off), its x along
## the viewer's right as seen from the front, facing `n`, scaled by `size` (x, y).
static func _add_flat(ch: CityChunk, key: String, mesh: Mesh, p: Vector3, n: Vector3, size: Vector2, custom: Color) -> int:
	# Seen from the front (looking along -n) the piece's +x is the viewer's right: up x n.
	var x := Vector3.UP.cross(n).normalized()
	var basis := Basis(x * size.x, Vector3.UP * size.y, n * size.x)
	var at := p - Vector3(0.0, ch._gy(p.x, p.z), 0.0)
	return ch._batch.add(key, mesh, Transform3D(basis, at), Color.WHITE, custom)


# --- Lamp-post banners ---------------------------------------------------------------------------

static func _lamp_banners(ch: CityChunk, block: Dictionary, district: int, counts: Dictionary) -> void:
	if float(LAMPB_ODDS[district]) <= 0.0:
		return
	var plan := ch.plan
	var rect: Rect2 = block.rect
	var edges := CityChunk._sidewalk_edges(rect)
	var streets: Array = []
	for e in 4:
		var road := edge_road(ch.ix, ch.iz, e)
		streets.append(banner_street(plan, road[0], road[1], district))
	if not streets.has(true):
		return
	for r: Dictionary in ch.prop_records:
		if String(r.kind) != "lamp":
			continue
		var pos: Vector3 = r.position
		var p2 := Vector2(pos.x, pos.z)
		for e in 4:
			if not streets[e]:
				continue
			var a: Vector2 = edges[e][0]
			var inward: Vector2 = edges[e][2]
			if absf((p2 - a).dot(inward) - 1.0) > 0.2:
				continue
			var road := edge_road(ch.ix, ch.iz, e)
			# The street's event, alternating with its district's name every other lamp.
			var ev := absi(hash([plan.seed, "sg_lampb_ev", road[0], road[1]])) % 16
			var other := (ev + 3 + absi(hash([plan.seed, "sg_lampb_d", road[0], road[1]])) % 12) % 16
			var along_t := (p2 - a).dot((edges[e][1] - a).normalized())
			var cell := ev if int(floor(along_t / 30.0)) % 2 == 0 else other
			var base := Vector3(pos.x, pos.y - ch._gy(pos.x, pos.z) + SignKit.LAMPB_BOTTOM, pos.z)
			var to_road := Vector3(-inward.x, 0.0, -inward.y)
			var arms_basis := Basis(to_road, Vector3.UP, to_road.cross(Vector3.UP))
			var added: Array = []
			added.append([K_ARMS, ch._batch.add(K_ARMS, SignKit.lamp_banner_arms(), Transform3D(arms_basis, base), Color.WHITE, Color.BLACK)])
			for side: float in [-1.0, 1.0]:
				var x := to_road * side
				var bb := Basis(x, Vector3.UP, x.cross(Vector3.UP))
				var o := base + x * 0.08
				added.append([K_LAMPB, ch._batch.add(K_LAMPB, SignKit.lamp_banner(), Transform3D(bb, o), Color.WHITE, Color(float(cell), 0.0, 0.0, _h01([pos.x, pos.z, side])))])
			for inst: Array in added:
				(r.instances as Array).append(inst)
			counts.lampb = int(counts.lampb) + 2
			break


# --- Street plates ---------------------------------------------------------------------------

static func _plates(ch: CityChunk, block: Dictionary, district: int, counts: Dictionary) -> void:
	var plan := ch.plan
	var rect: Rect2 = block.rect
	var edges := CityChunk._sidewalk_edges(rect)
	var occupied := StreetClutter._occupied(ch)
	var cuts := Kerbs.possible_cuts(ch, rect, district)
	var spacing := float(PLATE_SPACING[district])
	if int(block.kind) != CityPlan.BlockKind.BUILDINGS and int(block.kind) != CityPlan.BlockKind.MALL:
		spacing = 0.0
	# Bus zones: a post beside every shelter, downstream of it.
	for r: Dictionary in ch.prop_records.duplicate():
		if String(r.kind) != "bus_stop":
			continue
		var pos: Vector3 = r.position
		var p2 := Vector2(pos.x, pos.z)
		for e in 4:
			var a: Vector2 = edges[e][0]
			var b: Vector2 = edges[e][1]
			var inward: Vector2 = edges[e][2]
			var depth := (p2 - a).dot(inward)
			if depth < 0.5 or depth > 3.5:
				continue
			var dir := (b - a).normalized()
			var t := (p2 - a).dot(dir)
			for off: float in [5.5, -5.5, 7.0, -7.0]:
				var q := a + dir * (t + off) + inward * POST_IN
				if StreetVendors._clear(occupied, q, 0.45) and not _in_kerb_cut(cuts, q, 0.3):
					_post(ch, q, inward, [9, 10, 11], counts, occupied)
					break
			break
	if spacing <= 0.0:
		return
	for e in 4:
		var road := edge_road(ch.ix, ch.iz, e)
		var a: Vector2 = edges[e][0]
		var b: Vector2 = edges[e][1]
		var inward: Vector2 = edges[e][2]
		var length := a.distance_to(b)
		var dir := (b - a) / length
		var boulevard := is_boulevard(plan, road[0], road[1])
		var hs := [plan.seed, "sg_plates", road[0], road[1], ch.ix, ch.iz, e]
		# One street-cleaning day and one limit for the whole frontage (as a real block has).
		var clean: int = P_CLEAN[absi(hash(hs + ["clean"])) % P_CLEAN.size()]
		var limit: int = P_LIMIT[absi(hash(hs + ["limit"])) % P_LIMIT.size()]
		var other: int = P_OTHER[absi(hash(hs + ["other"])) % P_OTHER.size()]
		var tow := boulevard and _h01(hs + ["tow"]) < 0.4
		var t := spacing * (0.35 + 0.4 * _h01(hs + ["t0"]))
		var k := 0
		while t < length - 9.0:
			if t > 9.0:
				var plates: Array
				var hk := hs + [k]
				if tow:
					plates = [5, limit] if _h01(hk) < 0.6 else [4]
				else:
					plates = [limit, clean]
					if _h01(hk + ["o"]) < 0.25:
						plates = [other, clean]
				if _h01(hk + ["arrow"]) < 0.3:
					plates.append(P_ARROWS[int(_h01(hk + ["ad"]) * 2.0) % 2])
				for slide: float in [0.0, 1.2, -1.2, 2.4, -2.4]:
					var q := a + dir * (t + slide) + inward * POST_IN
					if not StreetWear.allowed(q):
						break
					if StreetVendors._clear(occupied, q, 0.5) and not _in_kerb_cut(cuts, q, 0.3):
						if plan.road_open(road[0], road[1], q.y if road[0] == CityPlan.AXIS_X else q.x):
							_post(ch, q, inward, plates, counts, occupied)
						break
			t += spacing * (0.8 + 0.4 * _h01(hs + ["s", k]))
			k += 1
		# A wayfinding sign near the start of a boulevard frontage.
		if boulevard and _h01(hs + ["way"]) < float(WAYFIND_ODDS[district]):
			for slide: float in [7.0, 9.0, 11.0]:
				var q := a + dir * slide + inward * 0.75
				if StreetVendors._clear(occupied, q, 0.6) and not _in_kerb_cut(cuts, q, 0.3):
					var x := Vector3(dir.x, 0.0, dir.y)
					var basis := Basis(x, Vector3.UP, x.cross(Vector3.UP))
					var at := Vector3(q.x, CityChunk.SIDEWALK_TOP, q.y)
					var cell := 6 + absi(hash(hs + ["wc"])) % 2
					ch._add_prop("street_sign", at, Color(0.15, 0.17, 0.16), [
						[K_WAYFIND, SignKit.wayfinding(), Transform3D(basis, at), Color.WHITE, Color(0.0, float(cell), 0.0, 0.5)],
					], [[Vector3(0.15, 3.6, 0.15), at + Vector3(0.0, 1.8, 0.0), 0.0]])
					if not ch.prop_records.is_empty():
						ch.prop_records.back()["sg"] = true
					occupied.append([q, 0.6])
					counts.wayfind = int(counts.wayfind) + 1
					break


## True when XZ `q` is inside, or within `margin` of, one of `cuts` (Kerbs.possible_cuts(): the
## corner ramps and driveway aprons the kerb ring may cut): a post there would stand in the slope.
static func _in_kerb_cut(cuts: Array, q: Vector2, margin: float) -> bool:
	for poly: PackedVector2Array in cuts:
		if Geometry2D.is_point_in_polygon(q, poly):
			return true
		for k in poly.size():
			if Geometry2D.get_closest_point_to_segment(q, poly[k], poly[(k + 1) % poly.size()]).distance_to(q) < margin:
				return true
	return false


## A sign post at `q` (XZ, on the pavement) with `plates` stacked from the top, facing along the
## kerb (both ways: the stack alternates which way each plate faces, as real ones are bolted).
static func _post(ch: CityChunk, q: Vector2, inward: Vector2, plates: Array, counts: Dictionary, occupied: Array) -> void:
	var at := Vector3(q.x, CityChunk.SIDEWALK_TOP, q.y)
	var along := Vector3(-inward.y, 0.0, inward.x)
	var flip := 1.0 if _h01([q.x, q.y, "flip"]) < 0.5 else -1.0
	var face := along * flip
	var basis := Basis(Vector3.UP.cross(face), Vector3.UP, face)
	var instances: Array = [[K_POST, SignKit.post(), Transform3D(Basis(Vector3.UP, atan2(face.x, face.z)), at)]]
	var y := SignKit.POST_H - 0.05 - SignKit.PLATE.y * 0.5
	for i in plates.size():
		var cell: int = plates[i]
		var h := SignKit.PLATE.y if cell != 16 and cell != 17 else SignKit.PLATE.y * 0.55
		var c := at + Vector3(0.0, y, 0.0) + face * 0.03
		var b := basis
		if cell == 16 or cell == 17:
			b = Basis(basis.x, basis.y * 0.55, basis.z)
			c += Vector3(0.0, SignKit.PLATE.y * 0.22, 0.0)
		instances.append([K_PLATE, SignKit.plate(), Transform3D(b, c), Color.WHITE, Color(float(cell), 0.0, 0.0, _h01([q.x, q.y, i]))])
		y -= h + 0.03
	ch._add_prop("street_sign", at, Color(0.6, 0.61, 0.6), instances, [[Vector3(0.12, SignKit.POST_H, 0.12), at + Vector3(0.0, SignKit.POST_H * 0.5, 0.0), 0.0]])
	if not ch.prop_records.is_empty():
		ch.prop_records.back()["sg"] = true
	occupied.append([q, 0.5])
	counts.post = int(counts.post) + 1
	counts.plate = int(counts.plate) + plates.size()


## Builds every mesh and the material once (the loading screen).
static func warm() -> Array:
	if not enabled:
		return []
	SignKit.warm()
	return [SignKit.material()]
