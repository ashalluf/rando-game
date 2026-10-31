class_name FacadeMid
extends RefCounted
## The facade from 20-80 m (fleet wave 4, "building-mid-detail"; the owner's bar: "make it look
## like GTA 6"). Past the pavement and short of the far city, a Building is its window grid, the
## kit's cornices, balconies and fire escapes, and FacadeStreet's street-level hardware - and the
## storeys in between read as empty and lived in by nobody. This file hangs the life on them, built
## in code into ONE mesh a building (MidDress, one draw, no shadow, no collision) on
## shaders/facade_mid.gdshader:
##
## - balcony life on every balcony the Building already rolled (the kit's or the box one): chairs
##   and a table, potted plants and vines spilling over the rail, a reed or canvas privacy screen
##   tied inside the railing, a towel over it, a drying rack or a line of washing, a grill, storage
##   tubs, a satellite dish clamped to the rail;
## - on the walls of residential blocks: through-wall sleeve air conditioners under the sills,
##   dryer and bathroom vents, satellite dishes on brackets (all aimed at the same patch of the
##   southern sky, as real ones are), a few windows open (a sash pushed up, a casement swung out,
##   the room and a curtain behind), downpipes down the upper tiers FacadeStreet does not reach;
## - metal flashing along roof edges that have no parapet or cornice;
## - a painted name across the top spandrel of some low masonry blocks (invented hotels, apartments
##   and trades, hand lettered with a drop shadow, flaking);
## - and on plain rendered walk-ups a kit fire escape of their own (the Building's escapes are
##   brick only), through the building's own kit batch.
##
## Every placement is a hash of the building's seed, the wall and the window, never a Building rng
## (Building._rng and _roof_rng run exactly as before): nothing a seed built before moves. LOD
## chunks and the far city are untouched - all of this is under a few pixels there.
##
## `FACADE_MID=0` in the environment turns it all off (the A/B).

static var enabled: bool = OS.get_environment("FACADE_MID") != "0"

const SHADER := preload("res://shaders/facade_mid.gdshader")
static var _material: ShaderMaterial

## How far the dressing draws (metres from the building's centre, plus half its footprint).
const DRAW_DISTANCE := 92.0
const NEAR_DISTANCE := 58.0

## Kinds (the shader's vertex alpha x 16).
const K_PAINT := 0
const K_GALV := 1
const K_FABRIC := 2
const K_LEAF := 3
const K_POT := 4
const K_PLASTIC := 5
const K_ROOM := 6
const K_GLASS := 7
const K_SIGN := 8
const K_WOOD := 9
const K_LOUVRE := 10
const K_RUBBER := 11
const K_DISH := 12
const K_SOIL := 13

## Shares.
const BALCONY_LIFE := 0.88          # of balconies with anything on them at all
const SCREEN_ODDS := 0.28
const PLANT_ODDS := 0.55
const VINE_ODDS := 0.14
const CHAIR_ODDS := 0.42
const RACK_ODDS := 0.16
const LINE_ODDS := 0.10
const TOWEL_ODDS := 0.14
const GRILL_ODDS := 0.08
const TUB_ODDS := 0.12
const BALCONY_DISH_ODDS := 0.12
const MAX_BALCONY_DISHES := 5
## Per window of a residential wall.
const WINDOW_AC_ODDS := 0.06
const SLEEVE_AC_ODDS := 0.07
const FLOWER_BOX_ODDS := 0.04
const VENT_ODDS := 0.09
const OPEN_ODDS := 0.075
const WALL_DISH_ODDS := 0.035
const MAX_WALL_DISHES := 4
## Per building.
const SIGN_ODDS := 0.24
const ESCAPE_ODDS := 0.4
const UPPER_PIPE_ODDS := 0.5

## Where every dish points: one patch of the southern sky (+Z is south), low in the south-west,
## about 40 degrees up.
const DISH_AIM := Vector3(-0.38, 0.62, 0.69)

const CHAIR_PAINTS := [Color(0.92, 0.92, 0.90), Color(0.10, 0.10, 0.11), Color(0.20, 0.36, 0.30),
	Color(0.62, 0.20, 0.12), Color(0.55, 0.55, 0.53), Color(0.18, 0.28, 0.45)]
const FABRICS := [Color(0.88, 0.86, 0.80), Color(0.72, 0.18, 0.15), Color(0.16, 0.30, 0.52),
	Color(0.20, 0.42, 0.30), Color(0.86, 0.68, 0.20), Color(0.40, 0.40, 0.42), Color(0.92, 0.55, 0.62),
	Color(0.10, 0.10, 0.12), Color(0.55, 0.42, 0.30), Color(0.35, 0.62, 0.70)]
const SCREENS := [Color(0.62, 0.50, 0.32), Color(0.70, 0.60, 0.42), Color(0.30, 0.40, 0.32),
	Color(0.82, 0.80, 0.74), Color(0.20, 0.25, 0.32)]
const POTS := [Color(0.62, 0.30, 0.18), Color(0.70, 0.40, 0.26), Color(0.85, 0.84, 0.80),
	Color(0.18, 0.18, 0.19), Color(0.30, 0.42, 0.50)]
const LEAVES := [Color(0.16, 0.30, 0.12), Color(0.22, 0.36, 0.14), Color(0.12, 0.24, 0.13),
	Color(0.30, 0.38, 0.16)]
const FLOWERS := [Color(0.82, 0.14, 0.42), Color(0.92, 0.30, 0.12), Color(0.95, 0.88, 0.85), Color(0.86, 0.22, 0.20)]
const CURTAINS := [Color(0.92, 0.90, 0.84), Color(0.80, 0.72, 0.58), Color(0.55, 0.20, 0.18),
	Color(0.30, 0.38, 0.55), Color(0.86, 0.80, 0.62)]
const FLASHING := [Color(0.56, 0.57, 0.56), Color(0.20, 0.20, 0.21), Color(0.84, 0.83, 0.79)]

## Painted signs: [panel, letters] (sRGB), and the names (all invented).
const SIGN_SCHEMES := [
	[Color(0.0, 0.0, 0.0, 0.0), Color(0.92, 0.90, 0.82)],
	[Color(0.0, 0.0, 0.0, 0.0), Color(0.55, 0.12, 0.10)],
	[Color(0.0, 0.0, 0.0, 0.0), Color(0.12, 0.14, 0.16)],
	[Color(0.50, 0.12, 0.10), Color(0.94, 0.90, 0.78)],
	[Color(0.12, 0.26, 0.20), Color(0.95, 0.88, 0.62)],
	[Color(0.12, 0.16, 0.30), Color(0.95, 0.94, 0.88)],
	[Color(0.86, 0.78, 0.55), Color(0.20, 0.12, 0.08)],
]
const HOME_NAMES := ["THE MARLOWE", "THE ALCOTT", "VILLA SERENA", "CASA DEL REY", "THE WINSLOW",
	"BELMONT ARMS", "THE KENDRA", "PALMERA COURT", "THE HOLLISTER", "LA ROSITA", "THE GRANVILLE",
	"SUNRAY ARMS", "THE BRYCE", "CASA LINDA", "THE ODELL", "MIRADOR"]
const HOME_TAILS := ["APTS", "APARTMENTS", "", "ARMS", ""]
const TRADE_NAMES := ["FURNITURE", "ROOMS BY THE WEEK", "HOTEL CARMEN", "TAILORING", "HARDWARE",
	"PAWN  LOANS", "MATTRESS OUTLET", "HOTEL ROSSLYN", "STORAGE", "LIQUOR  DELI", "DRY GOODS",
	"WHOLESALE", "HOTEL VISTA", "PRINTING CO", "TIRES  BRAKES", "BAKERY"]


static func material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = SHADER
	return _material


## The building's accumulator: the main one (DRAW_DISTANCE), or with `near` the small pieces'
## (NEAR_DISTANCE: chairs, pots, grills, tubs are a few pixels past it).
static func _acc(b: Building, near := false) -> FacadeStreet.Acc:
	var key := "fm_near" if near else "fm_acc"
	if not b.has_meta(key):
		b.set_meta(key, FacadeStreet.Acc.new())
	return b.get_meta(key)


## 0..1 from the building's seed and anything else.
static func _h(b: Building, tag: String, x: int = 0, y: int = 0) -> float:
	return float(absi(hash([b.seed, "facade_mid", tag, x, y])) % 100003) / 100003.0


static func _pick(b: Building, list: Array, tag: String, x: int = 0, y: int = 0) -> Variant:
	return list[absi(hash([b.seed, "facade_mid pick", tag, x, y])) % list.size()]


# --- Balconies ----------------------------------------------------------------------------------

## One balcony the Building placed: `xf` is its box (basis columns a * width, UP * rail height,
## n * depth; origin on the wall face at floor level). `kit`: the kit's balcony (floor at the
## origin, front rail at 0.975 of the depth) or the box one (floor 6 % of the rail up, rail at 0.98).
static func balcony(b: Building, xf: Transform3D, kit: bool, face_index: int, col: int, row: int) -> void:
	if not enabled:
		return
	var key := (face_index * 1009 + col) * 997 + row
	if _h(b, "life", key) >= BALCONY_LIFE:
		return
	var acc := _acc(b)
	var small := _acc(b, true)
	var a := xf.basis.x.normalized()
	var n := xf.basis.z.normalized()
	var bw := xf.basis.x.length()
	var rail_h := xf.basis.y.length() * (1.08 / 1.1 if kit else 0.98)
	var depth := xf.basis.z.length() * (0.975 if kit else 0.98)
	var floor_y := 0.0 if kit else xf.basis.y.length() * 0.06
	var o := xf.origin + Vector3(0.0, floor_y, 0.0)
	var w := Basis(a, Vector3.UP, n)
	# Free floor along the wall: what is placed takes a slice of `u` (from -bw/2 to bw/2).
	var half := bw * 0.5 - 0.12
	var front := depth - 0.06
	var used: Array = []   # [u0, u1]
	var take := func(u0: float, u1: float) -> bool:
		if u0 < -half or u1 > half:
			return false
		for r: Array in used:
			if u1 > float(r[0]) and u0 < float(r[1]):
				return false
		used.append([u0, u1])
		return true

	# A privacy screen tied inside the front rail: reed, canvas or a mesh banner.
	if _h(b, "screen", key) < SCREEN_ODDS:
		var sc: Color = _pick(b, SCREENS, "screen", key)
		var reed := _h(b, "reed", key) < 0.55
		var sh := rail_h * 0.92
		var p := o + n * (front - 0.03)
		acc.quad(p - a * (bw * 0.5 - 0.06), p + a * (bw * 0.5 - 0.06), p + a * (bw * 0.5 - 0.06) + Vector3(0.0, sh, 0.0),
			p - a * (bw * 0.5 - 0.06) + Vector3(0.0, sh, 0.0), n, K_WOOD if reed else K_FABRIC, sc, Vector2.ZERO, Vector2(bw, sh))
		acc.quad(p - a * (bw * 0.5 - 0.06), p + a * (bw * 0.5 - 0.06), p + a * (bw * 0.5 - 0.06) + Vector3(0.0, sh, 0.0),
			p - a * (bw * 0.5 - 0.06) + Vector3(0.0, sh, 0.0), -n, K_WOOD if reed else K_FABRIC, sc.darkened(0.15), Vector2.ZERO, Vector2(bw, sh))
	# A towel or a rug over the top rail.
	if _h(b, "towel", key) < TOWEL_ODDS:
		var tc: Color = _pick(b, FABRICS, "towel", key)
		var tu := (_h(b, "towel u", key) - 0.5) * (bw - 1.0)
		var tw := 0.5 + 0.4 * _h(b, "towel w", key)
		var top := o + n * front + Vector3(0.0, rail_h + 0.02, 0.0) + a * tu
		var drop_out := 0.35 + 0.35 * _h(b, "towel drop", key)
		_drape(acc, top, a, n, tw, drop_out, 0.30, tc)
	# Potted plants along the rail, now and then a vine spilling over it.
	if _h(b, "plants", key) < PLANT_ODDS:
		var count := 1 + int(_h(b, "plant count", key) * 3.0)
		for k in count:
			var u := -half + 0.25 + (half * 2.0 - 0.5) * _h(b, "plant u", key, k)
			var r := 0.13 + 0.09 * _h(b, "plant r", key, k)
			if not take.call(u - r, u + r):
				continue
			var at := o + a * u + n * (front - r - 0.04)
			_plant(small, at, a, n, r, b, key * 7 + k)
	if _h(b, "vine", key) < VINE_ODDS:
		var vu := (_h(b, "vine u", key) - 0.5) * (bw - 0.8)
		_vine(acc, o + n * (front + 0.02) + Vector3(0.0, rail_h, 0.0) + a * vu, a, n, 0.5 + 0.5 * _h(b, "vine w", key),
			0.6 + 0.9 * _h(b, "vine drop", key), b, key)
	# Chairs and a small table.
	if _h(b, "chairs", key) < CHAIR_ODDS:
		var paint: Color = _pick(b, CHAIR_PAINTS, "chair", key)
		var pair := _h(b, "pair", key) < 0.6 and bw > 1.8
		var u0 := -half + 0.32 + (half * 2.0 - 0.64) * _h(b, "chair u", key)
		if pair:
			u0 = clampf(u0, -half + 0.32, half - 1.1)
			if take.call(u0 - 0.3, u0 + 1.1):
				_chair(small, o + a * u0 + n * (depth * 0.45), a, n, deg_to_rad(20.0 + 30.0 * _h(b, "yaw", key)), paint)
				_chair(small, o + a * (u0 + 0.8) + n * (depth * 0.45), a, n, deg_to_rad(-20.0 - 30.0 * _h(b, "yaw2", key)), paint)
				if depth > 1.05 and _h(b, "table", key) < 0.6:
					_table(small, o + a * (u0 + 0.4) + n * (depth * 0.72), paint.darkened(0.1))
		elif take.call(u0 - 0.3, u0 + 0.3):
			_chair(small, o + a * u0 + n * (depth * 0.5), a, n, deg_to_rad((_h(b, "yaw", key) - 0.5) * 70.0), paint)
	# Laundry: a drying rack, or a line across the balcony.
	if _h(b, "rack", key) < RACK_ODDS:
		var ru := -half + 0.5 + (half * 2.0 - 1.0) * _h(b, "rack u", key)
		if take.call(ru - 0.45, ru + 0.45):
			_rack(acc, o + a * ru + n * (depth * 0.5), a, n, b, key)
	elif _h(b, "line", key) < LINE_ODDS:
		_line(acc, o + Vector3(0.0, rail_h + 0.25, 0.0) + n * (depth * 0.55), a, n, bw - 0.2, b, key)
	if _h(b, "grill", key) < GRILL_ODDS:
		var gu := half - 0.3
		if take.call(gu - 0.28, gu + 0.28):
			_grill(small, o + a * gu + n * (depth * 0.55))
	if _h(b, "tub", key) < TUB_ODDS:
		var tu := -half + 0.3
		if take.call(tu - 0.3, tu + 0.3):
			var c: Color = [Color(0.22, 0.38, 0.62), Color(0.86, 0.86, 0.84), Color(0.12, 0.12, 0.12)][absi(hash([b.seed, "tub", key])) % 3]
			small.box(Transform3D(w, o + a * tu + n * 0.30 + Vector3(0.0, 0.17, 0.0)), Vector3(0.56, 0.34, 0.40), K_PLASTIC, c, 0.0, false)
			if _h(b, "tub2", key) < 0.5:
				small.box(Transform3D(w, o + a * tu + n * 0.30 + Vector3(0.0, 0.47, 0.0)), Vector3(0.50, 0.26, 0.36), K_PLASTIC, c.lightened(0.1), 0.0, false)
	# A dish clamped to the rail, where the wall faces the southern sky.
	var dishes := int(b.get_meta("fm_dishes", 0))
	if dishes < MAX_BALCONY_DISHES and n.dot(Vector3(DISH_AIM.x, 0.0, DISH_AIM.z).normalized()) > 0.15 and _h(b, "bdish", key) < BALCONY_DISH_ODDS:
		b.set_meta("fm_dishes", dishes + 1)
		var side := -1.0 if _h(b, "bdish side", key) < 0.5 else 1.0
		var post := o + a * (side * (bw * 0.5 - 0.05)) + n * front + Vector3(0.0, rail_h, 0.0)
		acc.tube(post, post + Vector3(0.0, 0.42, 0.0), 0.022, K_GALV, Color.WHITE, 6)
		_dish(acc, post + Vector3(0.0, 0.52, 0.0) + n * 0.10, 0.27 + 0.08 * _h(b, "bdish r", key))


## A cloth hanging over a rail at `top`: down the outside `drop_out`, down the inside `drop_in`.
static func _drape(acc: FacadeStreet.Acc, top: Vector3, a: Vector3, n: Vector3, w: float, drop_out: float, drop_in: float, c: Color) -> void:
	var l := -a * (w * 0.5)
	var r := a * (w * 0.5)
	var o0 := top + n * 0.04
	var o1 := o0 + n * 0.02 - Vector3(0.0, drop_out, 0.0)
	var i0 := top - n * 0.04
	var i1 := i0 - n * 0.02 - Vector3(0.0, drop_in, 0.0)
	for s: float in [1.0, -1.0]:
		acc.quad(o0 + l, o0 + r, o1 + r, o1 + l, n * s, K_FABRIC, c if s > 0.0 else c.darkened(0.2), Vector2.ZERO, Vector2(w, drop_out))
		acc.quad(i0 + l, i0 + r, i1 + r, i1 + l, -n * s, K_FABRIC, c if s > 0.0 else c.darkened(0.2), Vector2.ZERO, Vector2(w, drop_in))
		acc.quad(i0 + l, i0 + r, o0 + r, o0 + l, Vector3.UP * s, K_FABRIC, c, Vector2.ZERO, Vector2(w, 0.08))


## A pot of `r` with a plant in it (leaf cards, flowers on some).
static func _plant(acc: FacadeStreet.Acc, at: Vector3, a: Vector3, n: Vector3, r: float, b: Building, key: int) -> void:
	var pot: Color = _pick(b, POTS, "pot", key)
	var ph := r * (1.3 + 0.7 * _h(b, "pot h", key))
	_cone(acc, at, r * 0.75, at + Vector3(0.0, ph, 0.0), r, K_POT, pot, 8)
	acc.disc(at + Vector3(0.0, ph - 0.03, 0.0), Vector3.UP, r * 0.94, K_SOIL, Color(0.20, 0.15, 0.10), 0.0, 5)
	var leaf: Color = _pick(b, LEAVES, "leaf", key)
	var tall := 0.35 + 0.9 * _h(b, "plant tall", key)
	var spread := r * (1.4 + 1.2 * _h(b, "plant spread", key))
	var flower := _h(b, "flower", key) < 0.35
	var fc: Color = _pick(b, FLOWERS, "flower c", key)
	for k in 3:
		var ang := PI * float(k) / 3.0 + _h(b, "card yaw", key) * PI
		var d := a * cos(ang) + n * sin(ang)
		var base := at + Vector3(0.0, ph - 0.05, 0.0)
		_card(acc, base - d * spread, base + d * spread, tall, d.cross(Vector3.UP), K_LEAF, leaf.lightened(0.06 * float(k)),
			float(absi(hash([key, k])) % 97))
	if flower:
		for k in 5:
			var off := Vector3(_h(b, "fx", key, k) - 0.5, 0.0, _h(b, "fz", key, k) - 0.5) * spread * 1.4
			var p := at + Vector3(0.0, ph + tall * (0.5 + 0.45 * _h(b, "fy", key, k)), 0.0) + off
			acc.box(Transform3D(Basis.IDENTITY, p), Vector3(0.07, 0.06, 0.07), K_FABRIC, fc, 0.0, false)


## A vine spilling over the rail at `top`, down the outside of the balcony.
static func _vine(acc: FacadeStreet.Acc, top: Vector3, a: Vector3, n: Vector3, w: float, drop: float, b: Building, key: int) -> void:
	var leaf: Color = _pick(b, LEAVES, "vine leaf", key)
	var bloom := _h(b, "vine bloom", key) < 0.5
	var bc: Color = _pick(b, FLOWERS, "vine bloom c", key)
	for k in 3:
		var u := (float(k) - 1.0) * w * 0.33
		var p := top + a * u + n * (0.02 + 0.03 * float(k))
		var dk := drop * (0.6 + 0.4 * _h(b, "vine dk", key, k))
		var blooms := bloom and k != 2
		_card_down(acc, p - a * (w * 0.3), p + a * (w * 0.3), dk, n, K_LEAF, bc if blooms else leaf.lightened(0.05 * float(k)),
			float(absi(hash([key, "vine", k])) % 97), 1.0 if blooms else 0.0)


## A leaf card standing from the line `p0`-`p1` up `h`, both faces (`side` its face normal).
static func _card(acc: FacadeStreet.Acc, p0: Vector3, p1: Vector3, h: float, side: Vector3, kind: int, c: Color, s: float, bloom := 0.0) -> void:
	var up := Vector3(0.0, h, 0.0)
	var nn := side.normalized()
	acc.quad(p0, p1, p1 + up, p0 + up, nn, kind, c, Vector2(s, 0.0), Vector2(0.999, 0.999), bloom)
	acc.quad(p0, p1, p1 + up, p0 + up, -nn, kind, c.darkened(0.1), Vector2(s, 0.0), Vector2(0.999, 0.999), bloom)


## A leaf card hanging from the line `p0`-`p1` down `h`, both faces.
static func _card_down(acc: FacadeStreet.Acc, p0: Vector3, p1: Vector3, h: float, n: Vector3, kind: int, c: Color, s: float, bloom := 0.0) -> void:
	var dn := Vector3(0.0, -h, 0.0) + n * 0.06
	acc.quad(p0 + dn, p1 + dn, p1, p0, n, kind, c, Vector2(s, 0.0), Vector2(0.999, 0.999), bloom)
	acc.quad(p0 + dn, p1 + dn, p1, p0, -n, kind, c.darkened(0.1), Vector2(s, 0.0), Vector2(0.999, 0.999), bloom)


## A frustum from a circle of `r0` at `p0` to one of `r1` at `p1` (round sides, open ends).
static func _cone(acc: FacadeStreet.Acc, p0: Vector3, r0: float, p1: Vector3, r1: float, kind: int, c: Color, segs: int) -> void:
	for k in segs:
		var t0 := TAU * float(k) / float(segs)
		var t1 := TAU * float(k + 1) / float(segs)
		var d0 := Vector3(cos(t0), 0.0, sin(t0))
		var d1 := Vector3(cos(t1), 0.0, sin(t1))
		var nm := ((d0 + d1).normalized() * (p1.y - p0.y) + Vector3(0.0, r0 - r1, 0.0)).normalized()
		acc.quad(p0 + d0 * r0, p0 + d1 * r0, p1 + d1 * r1, p1 + d0 * r1, nm, kind, c, Vector2(float(k) * 0.1, 0.0), Vector2(0.1, p1.y - p0.y))


## A stacking chair at `at` (its feet), facing out of the wall turned by `yaw`.
static func _chair(acc: FacadeStreet.Acc, at: Vector3, a: Vector3, n: Vector3, yaw: float, c: Color) -> void:
	var f := (n * cos(yaw) + a * sin(yaw)).normalized()
	var s := Vector3.UP.cross(f).normalized()
	var w := Basis(s, Vector3.UP, f)
	acc.box(Transform3D(w, at + Vector3(0.0, 0.44, 0.0)), Vector3(0.44, 0.04, 0.42), K_PLASTIC, c, 0.0, false)
	var back := Basis(s, -0.18) * w
	acc.box(Transform3D(back, at + Vector3(0.0, 0.70, 0.0) - f * 0.22), Vector3(0.42, 0.44, 0.03), K_PLASTIC, c, 0.0, false)
	for sx: float in [-0.19, 0.19]:
		for sz: float in [-0.18, 0.18]:
			var foot := at + s * sx + f * sz
			acc.tube(foot, foot + Vector3(0.0, 0.43, 0.0), 0.012, K_PLASTIC, c.darkened(0.1), 3)


static func _table(acc: FacadeStreet.Acc, at: Vector3, c: Color) -> void:
	acc.disc(at + Vector3(0.0, 0.70, 0.0), Vector3.UP, 0.30, K_PLASTIC, c, 0.0, 12)
	acc.disc(at + Vector3(0.0, 0.69, 0.0), Vector3.DOWN, 0.30, K_PLASTIC, c.darkened(0.2), 0.0, 12)
	acc.tube(at, at + Vector3(0.0, 0.69, 0.0), 0.022, K_PAINT, c.darkened(0.3), 5)
	acc.disc(at + Vector3(0.0, 0.01, 0.0), Vector3.UP, 0.20, K_PAINT, c.darkened(0.3), 0.0, 8)


## A folding drying rack with washing on it.
static func _rack(acc: FacadeStreet.Acc, at: Vector3, a: Vector3, n: Vector3, b: Building, key: int) -> void:
	var steel := Color(0.85, 0.85, 0.84)
	for sx: float in [-0.42, 0.42]:
		var p := at + a * sx
		acc.tube(p - n * 0.25, p + Vector3(0.0, 0.92, 0.0), 0.008, K_PAINT, steel, 4)
		acc.tube(p + n * 0.25, p + Vector3(0.0, 0.92, 0.0), 0.008, K_PAINT, steel, 4)
	for k in 4:
		var y := 0.55 + 0.12 * float(k)
		var dz := (0.25 * (1.0 - (y / 0.92))) * (1.0 if k % 2 == 0 else -1.0)
		acc.tube(at - a * 0.42 + n * dz + Vector3(0.0, y, 0.0), at + a * 0.42 + n * dz + Vector3(0.0, y, 0.0), 0.006, K_PAINT, steel, 4)
	for k in 3:
		var c: Color = _pick(b, FABRICS, "wash", key, k)
		var u := -0.3 + 0.3 * float(k)
		var cw := 0.22 + 0.12 * _h(b, "wash w", key, k)
		var drop := 0.30 + 0.30 * _h(b, "wash d", key, k)
		var top := at + a * u + Vector3(0.0, 0.92 - 0.04 * float(k), 0.0) + n * (0.02 * float(k - 1))
		_cloth(acc, top, a, n, cw, drop, c)


## A washing line across the balcony at `at` (its middle), `span` long, with washing pegged on it.
static func _line(acc: FacadeStreet.Acc, at: Vector3, a: Vector3, n: Vector3, span: float, b: Building, key: int) -> void:
	acc.tube(at - a * (span * 0.5), at + a * (span * 0.5), 0.004, K_RUBBER, Color(0.8, 0.8, 0.8), 3)
	var count := 2 + int(_h(b, "line count", key) * 4.0)
	for k in count:
		var u := -span * 0.42 + span * 0.84 * (float(k) + 0.5) / float(count)
		var c: Color = _pick(b, FABRICS, "line wash", key, k)
		_cloth(acc, at + a * u, a, n, 0.25 + 0.2 * _h(b, "lw", key, k), 0.3 + 0.35 * _h(b, "ld", key, k), c)


## One piece of washing hanging from `top`: a cloth `w` wide, `drop` long, both faces.
static func _cloth(acc: FacadeStreet.Acc, top: Vector3, a: Vector3, n: Vector3, w: float, drop: float, c: Color) -> void:
	var l := -a * (w * 0.5)
	var r := a * (w * 0.5)
	var bot := top - Vector3(0.0, drop, 0.0) + n * 0.03
	acc.quad(bot + l, bot + r, top + r, top + l, n, K_FABRIC, c, Vector2.ZERO, Vector2(w, drop))
	acc.quad(bot + l, bot + r, top + r, top + l, -n, K_FABRIC, c.darkened(0.15), Vector2.ZERO, Vector2(w, drop))


## A kettle grill on three legs.
static func _grill(acc: FacadeStreet.Acc, at: Vector3) -> void:
	var black := Color(0.04, 0.04, 0.045)
	_cone(acc, at + Vector3(0.0, 0.55, 0.0), 0.16, at + Vector3(0.0, 0.78, 0.0), 0.26, K_PAINT, black, 10)
	_cone(acc, at + Vector3(0.0, 0.78, 0.0), 0.26, at + Vector3(0.0, 0.93, 0.0), 0.12, K_PAINT, black, 10)
	acc.disc(at + Vector3(0.0, 0.93, 0.0), Vector3.UP, 0.12, K_PAINT, black, 0.0, 8)
	for k in 3:
		var t := TAU * float(k) / 3.0
		var d := Vector3(cos(t), 0.0, sin(t))
		acc.tube(at + d * 0.22, at + d * 0.12 + Vector3(0.0, 0.58, 0.0), 0.012, K_PAINT, black, 4)


## A satellite dish whose rim centre is at `c`, `r` across half, aimed at DISH_AIM: the dish
## (front white, back grey), the feed arm and its LNB, the mast stub behind.
static func _dish(acc: FacadeStreet.Acc, c: Vector3, r: float) -> void:
	var f := DISH_AIM.normalized()
	var u := f.cross(Vector3.UP).normalized()
	var v := u.cross(f)
	var segs := 8
	var rings := [0.0, 0.6, 1.0]
	var depth := r * 0.28
	var white := Color(0.88, 0.88, 0.86)
	for i in rings.size() - 1:
		var r0: float = rings[i]
		var r1: float = rings[i + 1]
		for k in segs:
			var t0 := TAU * float(k) / float(segs)
			var t1 := TAU * float(k + 1) / float(segs)
			var q := func(rr: float, t: float) -> Vector3:
				# The bowl: z = depth * rr^2 back from the rim's plane.
				return c + (u * cos(t) + v * sin(t)) * (rr * r) - f * (depth * (1.0 - rr * rr))
			var p00: Vector3 = q.call(r0, t0)
			var p01: Vector3 = q.call(r0, t1)
			var p11: Vector3 = q.call(r1, t1)
			var p10: Vector3 = q.call(r1, t0)
			var nm := (f + (u * cos(t0) + v * sin(t0)) * (-(r0 + r1) * depth / r)).normalized()
			acc.quad(p00, p10, p11, p01, nm, K_DISH, white, Vector2(r0, 0.0), Vector2(0.1, 0.1))
			acc.quad(p00, p10, p11, p01, -nm, K_DISH, white.darkened(0.25), Vector2(r0, 0.0), Vector2(0.1, 0.1))
	# The feed arm from under the bowl out to the LNB at the focus.
	var low := c - v * (r * 0.95) - f * (depth * 0.1)
	var lnb := c + f * (r * 0.75)
	acc.tube(low, lnb - v * 0.03, 0.012, K_PAINT, Color(0.30, 0.30, 0.32), 4)
	acc.box(Transform3D(Basis(u, v, f), lnb), Vector3(0.06, 0.07, 0.12), K_PLASTIC, Color(0.20, 0.20, 0.22), 0.0, false)
	var back := c - f * (depth + 0.05)
	acc.box(Transform3D(Basis(u, v, f), back), Vector3(0.10, 0.14, 0.08), K_GALV, Color.WHITE, 0.0, false)


# --- Walls ----------------------------------------------------------------------------------------

## One wall of one part, called from Building._add_facade_details() with what it knows of it.
## `busy`: balconies or a fire escape hang on this wall; `flash`: the part's roof edge is free and
## has no parapet or cornice on it; `escape_ok`: the building may take a fire escape of ours.
static func face(b: Building, face_index: int, fc: Vector3, a: Vector3, n: Vector3, size_u: float, cols: int,
		pitch: float, cut: float, bottom: float, storefront: float, floor_h: float, rows: int, top: float,
		masonry: bool, residential: bool, busy: bool, flash: bool, escape_ok: bool) -> void:
	if not enabled or b.shape == Building.Shape.WAREHOUSE:
		return
	var face_id := face_index + 1
	# A wall standing against another wing of the building gets nothing.
	if FacadeStreet._inside_part(b, fc + n * 0.6 + Vector3(0.0, bottom + (top - bottom) * 0.5, 0.0)):
		return
	var acc := _acc(b)
	var fkey := (face_index * 7919 + roundi(fc.x * 10.0)) * 104729 + roundi(fc.z * 10.0)
	var skip := 1 if cut > 0.0 else 0
	var half := size_u * 0.5 - cut
	var w := Basis(a, Vector3.UP, n)

	# --- Roof-edge flashing ------------------------------------------------------------------
	if flash and size_u > 2.0:
		var fcol: Color = FLASHING[absi(hash([b.seed, "fm flash"])) % FLASHING.size()]
		var fl := size_u - 2.0 * cut + (0.06 if cut <= 0.0 else 0.0)
		var y := top - 0.07
		acc.box(Transform3D(w, fc + Vector3(0.0, y, 0.0) + n * 0.022), Vector3(fl, 0.16, 0.044), K_GALV if fcol.r > 0.5 and fcol.r < 0.6 else K_PAINT, fcol)
		# The drip edge kicked out under it, and the cap over the roof edge.
		acc.box(Transform3D(w, fc + Vector3(0.0, y - 0.085, 0.0) + n * 0.05), Vector3(fl, 0.012, 0.06), K_PAINT, fcol.darkened(0.1))
		acc.quad(fc - a * (fl * 0.5) + Vector3(0.0, top + 0.012, 0.0) + n * 0.045, fc + a * (fl * 0.5) + Vector3(0.0, top + 0.012, 0.0) + n * 0.045,
			fc + a * (fl * 0.5) + Vector3(0.0, top + 0.012, 0.0) - n * 0.20, fc - a * (fl * 0.5) + Vector3(0.0, top + 0.012, 0.0) - n * 0.20,
			Vector3.UP, K_PAINT, fcol)

	var punched := b.window_style == Building.WindowStyle.PUNCHED
	if not punched and b.window_style != Building.WindowStyle.NARROW:
		return
	var rect: Array = Building.WINDOW_RECTS[b.window_style]
	var cx: float = rect[0]
	var cy: float = rect[1]
	var hx: float = rect[2]
	var hy: float = rect[3]
	var ww := 2.0 * hx * pitch
	var wh := 2.0 * hy * floor_h
	var door_c := FacadeStreet.door_for(b, face_id, size_u, cols, bottom, storefront, pitch, floor_h)
	var ac_ok := b._kit != null and punched and residential and ww >= 0.8

	# --- A fire escape of our own on a plain rendered walk-up ----------------------------------
	var esc_col := -1
	if escape_ok and not busy and b._kit != null and bottom < 0.01 and rows >= 3 and rows <= 8 and face_id != b.back_face \
			and cols - 2 * skip >= 4 and absi(hash([b.seed, "fm escape face"])) % 4 == face_index \
			and _h(b, "escape") < ESCAPE_ODDS:
		esc_col = skip + 1 + absi(hash([b.seed, "fm escape col"])) % maxi(cols - 2 * skip - 2, 1)
		_escape(b, fc, a, n, size_u, pitch, esc_col, bottom, storefront, floor_h, rows, top)

	# --- A painted name across the top spandrel -------------------------------------------------
	if masonry and punched and bottom < 0.01 and rows >= 2 and rows <= 7 and face_id != b.back_face \
			and absi(hash([b.seed, "fm sign face"])) % 4 == face_index and _h(b, "sign") < SIGN_ODDS and half > 4.0:
		_painted_sign(b, acc, fc, a, n, half, bottom, storefront, floor_h, rows, top, cy, hy, storefront > 0.0)

	# --- Downpipes down the upper tiers FacadeStreet does not reach ---------------------------
	if bottom > 0.01 and masonry and top - bottom <= 30.0 and size_u >= 6.0 and not busy and _h(b, "upper pipe", fkey) < UPPER_PIPE_ODDS:
		var side := 1.0 if _h(b, "upper pipe side", fkey) < 0.5 else -1.0
		var paint := b.facade_color.darkened(0.15)
		FacadeStreet._downpipe(acc, fc + a * (side * (half - 0.34)), a, n, bottom + 0.15, top - 0.9, false, false, K_PAINT, paint)

	if not residential or busy:
		return
	# --- Window by window: sleeve ACs, vents, dishes, open windows ----------------------------
	var dishes := 0
	var dish_ok := n.dot(Vector3(DISH_AIM.x, 0.0, DISH_AIM.z).normalized()) > 0.2
	var pier := pitch - ww
	for col in range(skip, cols - skip):
		if esc_col >= 0 and absi(col - esc_col) <= 1:
			continue
		var u := -size_u * 0.5 + (col + 1.0 - cx) * pitch
		for row in rows:
			var v := bottom + storefront + (row + cy) * floor_h
			if v + wh * 0.5 > top - 0.3:
				continue
			if row == 0 and door_c >= 0 and cols - 1 - col == door_c:
				continue
			var wkey := (face_index * 1009 + col) * 997 + row
			var at := fc + a * u + Vector3(0.0, v, 0.0)
			# The kit's window AC on this sill (Building's own roll).
			var kit_ac := ac_ok and b._kit_hash("ac", wkey) < b.kit_ac_chance
			var ground := row == 0 and bottom < 0.01
			# One roll a window: an extra window AC of the kit's, a sleeve unit under the sill, the
			# window open, a flower box on the sill - or nothing.
			var r := _h(b, "window", wkey)
			if not kit_ac:
				if r < WINDOW_AC_ODDS:
					if ac_ok and not ground:
						var off := (_h(b, "ac side", wkey) - 0.5) * (ww - 0.72)
						var unit: Color = [Color(0.86, 0.85, 0.80), Color(0.78, 0.76, 0.70), Color(0.70, 0.71, 0.72)][absi(hash([b.seed, "fm ac colour", wkey])) % 3]
						b._kit.add("kit_ac_window", PropFactory.facade_kit("ac_window"),
							Transform3D(w, at + a * off - Vector3(0.0, wh * 0.5, 0.0)), unit, Color(b._kit_iron, 0.0, 0.0, 0.0))
				elif r < WINDOW_AC_ODDS + SLEEVE_AC_ODDS:
					if punched and ww >= 0.8 and not (ground and storefront > 0.0) and not (row == 0 and bottom > 0.01):
						_sleeve_ac(acc, at - Vector3(0.0, wh * 0.5 + 0.34, 0.0), a, n, b, wkey)
				elif r < WINDOW_AC_ODDS + SLEEVE_AC_ODDS + OPEN_ODDS:
					if not ground:
						_open_window(acc, at, a, n, ww, wh, b, wkey)
				elif r < WINDOW_AC_ODDS + SLEEVE_AC_ODDS + OPEN_ODDS + FLOWER_BOX_ODDS:
					if not ground and ww >= 0.6:
						_flower_box(acc, at - Vector3(0.0, wh * 0.5, 0.0), a, n, ww, b, wkey)
			if not ground and pier >= 0.55 and _h(b, "vent", wkey) < VENT_ODDS:
				var side := 1.0 if _h(b, "vent side", wkey) < 0.5 else -1.0
				_vent(acc, at + a * (side * (ww * 0.5 + pier * 0.5)) + Vector3(0.0, wh * 0.25, 0.0), a, n, _h(b, "vent kind", wkey))
			elif dish_ok and dishes < MAX_WALL_DISHES and not ground and pier >= 0.5 and _h(b, "wall dish", wkey) < WALL_DISH_ODDS:
				var side := 1.0 if _h(b, "dish side", wkey) < 0.5 else -1.0
				_wall_dish(acc, at + a * (side * (ww * 0.5 + pier * 0.5)) + Vector3(0.0, wh * 0.35, 0.0), a, n, 0.26 + 0.1 * _h(b, "dish r", wkey))
				dishes += 1


## A painted window box on the sill at `at` (the opening's foot), planted.
static func _flower_box(acc: FacadeStreet.Acc, at: Vector3, a: Vector3, n: Vector3, ww: float, b: Building, key: int) -> void:
	var w := Basis(a, Vector3.UP, n)
	var bw := ww - 0.08
	var paint: Color = _pick(b, [Color(0.86, 0.85, 0.80), Color(0.20, 0.30, 0.24), Color(0.45, 0.26, 0.16), Color(0.15, 0.15, 0.16)], "fbox", key)
	acc.box(Transform3D(w, at + n * 0.14 - Vector3(0.0, 0.09, 0.0)), Vector3(bw, 0.18, 0.22), K_PAINT, paint)
	acc.box(Transform3D(w, at + n * 0.09 - Vector3(0.0, 0.22, 0.0)), Vector3(0.04, 0.12, 0.16), K_PAINT, paint.darkened(0.2))
	var leaf: Color = _pick(b, LEAVES, "fbox leaf", key)
	var bloom: Color = _pick(b, FLOWERS, "fbox bloom", key)
	var base := at + n * 0.14
	_card(acc, base - a * (bw * 0.5), base + a * (bw * 0.5), 0.30, n, K_LEAF, leaf, float(absi(hash([key, "fb"])) % 97))
	_card_down(acc, base + n * 0.1 - a * (bw * 0.45), base + n * 0.1 + a * (bw * 0.45), 0.28, n, K_LEAF, leaf.lightened(0.05), float(absi(hash([key, "fd"])) % 97))
	for k in 5:
		var p := base + a * ((float(k) / 4.0 - 0.5) * (bw - 0.15)) + Vector3(0.0, 0.14 + 0.08 * _h(b, "fbf", key, k), 0.0) + n * 0.04
		acc.box(Transform3D(Basis.IDENTITY, p), Vector3(0.08, 0.07, 0.08), K_FABRIC, bloom, 0.0, false)


## A through-wall air conditioner in its sleeve under the window at `at` (its centre).
static func _sleeve_ac(acc: FacadeStreet.Acc, at: Vector3, a: Vector3, n: Vector3, b: Building, key: int) -> void:
	var w := Basis(a, Vector3.UP, n)
	var unit: Color = [Color(0.86, 0.85, 0.80), Color(0.74, 0.73, 0.69), Color(0.60, 0.61, 0.62)][absi(hash([b.seed, "fm sleeve", key])) % 3]
	# The sleeve's trim flush on the wall, the unit's grille standing out of it.
	acc.box(Transform3D(w, at + n * 0.012), Vector3(0.70, 0.44, 0.024), K_PAINT, unit.darkened(0.08))
	acc.box(Transform3D(w, at + n * 0.10), Vector3(0.64, 0.38, 0.17), K_PAINT, unit)
	acc.quad(at + n * 0.186 + a * -0.30 + Vector3(0.0, -0.17, 0.0), at + n * 0.186 + a * 0.30 + Vector3(0.0, -0.17, 0.0),
		at + n * 0.186 + a * 0.30 + Vector3(0.0, 0.17, 0.0), at + n * 0.186 + a * -0.30 + Vector3(0.0, 0.17, 0.0),
		n, K_LOUVRE, unit.darkened(0.25), Vector2.ZERO, Vector2(0.6, 0.34))
	# The drip tube and its stain-dark lip.
	acc.tube(at + n * 0.05 + a * 0.24 + Vector3(0.0, -0.19, 0.0), at + n * 0.07 + a * 0.24 + Vector3(0.0, -0.30, 0.0), 0.008, K_RUBBER, Color.BLACK, 3)


## A vent beside a window: a dryer hood with its flap, or a square louvre.
static func _vent(acc: FacadeStreet.Acc, at: Vector3, a: Vector3, n: Vector3, kind: float) -> void:
	var w := Basis(a, Vector3.UP, n)
	if kind < 0.5:
		var white := Color(0.88, 0.87, 0.83)
		acc.box(Transform3D(w, at + n * 0.008), Vector3(0.20, 0.20, 0.016), K_PLASTIC, white)
		var hood := Basis(a, -0.35) * w
		acc.box(Transform3D(hood, at + n * 0.06 + Vector3(0.0, -0.01, 0.0)), Vector3(0.14, 0.13, 0.08), K_PLASTIC, white)
	else:
		var grey := Color(0.66, 0.66, 0.64)
		acc.box(Transform3D(w, at + n * 0.015), Vector3(0.26, 0.26, 0.03), K_PAINT, grey)
		acc.quad(at + n * 0.031 + a * -0.11 + Vector3(0.0, -0.11, 0.0), at + n * 0.031 + a * 0.11 + Vector3(0.0, -0.11, 0.0),
			at + n * 0.031 + a * 0.11 + Vector3(0.0, 0.11, 0.0), at + n * 0.031 + a * -0.11 + Vector3(0.0, 0.11, 0.0),
			n, K_LOUVRE, grey.darkened(0.3), Vector2.ZERO, Vector2(0.22, 0.22))


## A dish on a wall bracket beside a window, `at` on the wall.
static func _wall_dish(acc: FacadeStreet.Acc, at: Vector3, a: Vector3, n: Vector3, r: float) -> void:
	var w := Basis(a, Vector3.UP, n)
	acc.box(Transform3D(w, at + n * 0.01), Vector3(0.16, 0.24, 0.02), K_GALV, Color.WHITE)
	var tip := at + n * 0.36
	acc.tube(at + n * 0.01, tip, 0.02, K_GALV, Color.WHITE, 6)
	acc.tube(at + n * 0.01 - Vector3(0.0, 0.18, 0.0), tip - Vector3(0.0, 0.02, 0.0), 0.012, K_GALV, Color.WHITE, 4)
	acc.tube(tip, tip + Vector3(0.0, 0.16, 0.0), 0.02, K_GALV, Color.WHITE, 6)
	_dish(acc, tip + Vector3(0.0, 0.28, 0.0) + DISH_AIM.normalized() * 0.06, r)
	# The coax down the wall and in.
	acc.tube(at + n * 0.03 + Vector3(0.0, -0.12, 0.0), at + n * 0.03 + Vector3(0.0, -0.9, 0.0) + a * 0.12, 0.005, K_RUBBER, Color.BLACK, 3)


## An open window at `at` (the opening's centre, on the wall face), `ww` x `wh`: a hung sash pushed
## up or a casement swung out, the room behind (lit after dark on some) with its curtain.
static func _open_window(acc: FacadeStreet.Acc, at: Vector3, a: Vector3, n: Vector3, ww: float, wh: float, b: Building, key: int) -> void:
	var w := Basis(a, Vector3.UP, n)
	var cur: Color = _pick(b, CURTAINS, "curtain", key)
	var lit := 1.0 if _h(b, "lit", key) < 0.55 else 0.0
	var sash := _h(b, "sash", key) < 0.6 or ww < 0.7
	var iw := ww - 0.06
	var frame := Color(0.90, 0.89, 0.85)
	var z := n * 0.02
	if sash:
		# The lower sash pushed up: the room shows under it.
		var gap := wh * (0.32 + 0.22 * _h(b, "gap", key))
		var y0 := -wh * 0.5 + 0.04
		var p := at + z + Vector3(0.0, y0, 0.0)
		acc.quad(p - a * (iw * 0.5), p + a * (iw * 0.5), p + a * (iw * 0.5) + Vector3(0.0, gap, 0.0), p - a * (iw * 0.5) + Vector3(0.0, gap, 0.0),
			n, K_ROOM, cur, Vector2.ZERO, Vector2(1.0, 1.0), lit)
		acc.box(Transform3D(w, at + n * 0.03 + Vector3(0.0, y0 + gap + 0.03, 0.0)), Vector3(iw, 0.06, 0.05), K_PAINT, frame)
		# Now and then the curtain blowing out under the sash.
		if _h(b, "blow", key) < 0.3:
			var top := at + n * 0.04 + Vector3(0.0, y0 + gap - 0.02, 0.0) - a * (iw * 0.2)
			_cloth(acc, top, a, n, iw * 0.45, gap * 0.7, cur)
	else:
		# A casement on the left or the right jamb, swung out.
		var p := at + z
		acc.quad(p - a * (iw * 0.5) - Vector3(0.0, wh * 0.5 - 0.04, 0.0), p + a * (iw * 0.5) - Vector3(0.0, wh * 0.5 - 0.04, 0.0),
			p + a * (iw * 0.5) + Vector3(0.0, wh * 0.5 - 0.04, 0.0), p - a * (iw * 0.5) + Vector3(0.0, wh * 0.5 - 0.04, 0.0),
			n, K_ROOM, cur, Vector2.ZERO, Vector2(1.0, 1.0), lit)
		var side := 1.0 if _h(b, "hinge", key) < 0.5 else -1.0
		var leaf_w := iw if iw < 1.0 else iw * 0.5
		var ang := deg_to_rad(45.0 + 40.0 * _h(b, "swing", key))
		var hinge := at + a * (side * iw * 0.5) + n * 0.05
		var out := (-a * side * cos(ang) + n * sin(ang)).normalized()
		var mid := hinge + out * (leaf_w * 0.5)
		var lb := Basis(out, Vector3.UP, out.cross(Vector3.UP).normalized() * side)
		var lh := wh - 0.08
		for s: float in [-1.0, 1.0]:
			acc.box(Transform3D(lb, mid + Vector3(0.0, s * (lh * 0.5 - 0.025), 0.0)), Vector3(leaf_w, 0.05, 0.045), K_PAINT, frame, 0.0, false)
			acc.box(Transform3D(lb, mid + out * (s * (leaf_w * 0.5 - 0.025))), Vector3(0.05, lh, 0.045), K_PAINT, frame, 0.0, false)
		var gn := lb.z
		var g0 := mid - out * (leaf_w * 0.5 - 0.05)
		var g1 := mid + out * (leaf_w * 0.5 - 0.05)
		var hy := Vector3(0.0, lh * 0.5 - 0.05, 0.0)
		acc.quad(g0 - hy, g1 - hy, g1 + hy, g0 + hy, gn, K_GLASS, Color.WHITE)
		acc.quad(g0 - hy, g1 - hy, g1 + hy, g0 + hy, -gn, K_GLASS, Color.WHITE)


## The kit's fire escape on this wall, landings up the column `col` (Building's escape, line for
## line: the same pieces, sizes and collision).
static func _escape(b: Building, fc: Vector3, a: Vector3, n: Vector3, size_u: float, pitch: float, col: int,
		bottom: float, storefront: float, floor_h: float, rows: int, top: float) -> void:
	var eu := -size_u * 0.5 + (float(col) + 0.5) * pitch
	var ew: float = minf(pitch * 0.9, 2.6)
	var lowest := true
	for row in rows:
		var ev := bottom + storefront + float(row) * floor_h
		if ev < bottom + storefront + 0.5 or ev + floor_h > top - 0.5:
			continue
		var piece := "fe_bottom" if lowest else ("fe_stair_r" if row % 2 == 0 else "fe_stair_l")
		lowest = false
		var xf := Transform3D(Basis(a * (ew / 2.4), Vector3.UP * (floor_h / 3.5), n * (1.35 / 1.3)), fc + a * eu + Vector3(0.0, ev, 0.0))
		b._kit.add("kit_" + piece, PropFactory.facade_kit(piece), xf, Color.WHITE, Color(b._kit_iron, 0.0, 0.0, 0.0))
		b._kit_solid_box(xf, Vector3(0.0, -0.04, 0.65), Vector3(2.4, 0.08, 1.3))


## A painted name across the top spandrel of this wall (between the top storey's windows and the
## ones under it), hand lettered with a drop shadow, on a painted panel or straight on the wall.
static func _painted_sign(b: Building, acc: FacadeStreet.Acc, fc: Vector3, a: Vector3, n: Vector3, half: float,
		bottom: float, storefront: float, floor_h: float, rows: int, top: float, cy: float, hy: float, trade: bool) -> void:
	# The top row the Building draws, and the spandrel under it.
	var wh := 2.0 * hy * floor_h
	var top_row := -1
	for row in rows:
		if bottom + storefront + (row + cy) * floor_h + wh * 0.5 <= top - 0.3:
			top_row = row
	if top_row < 1:
		return
	# A string course in that spandrel takes it (Building's rule).
	if b.string_course_every > 0 and rows >= b.string_course_every + 3 and top_row % b.string_course_every == 0:
		return
	var lo := bottom + storefront + (float(top_row - 1) + cy + hy) * floor_h + 0.10
	var hi := bottom + storefront + (float(top_row) + cy - hy) * floor_h - 0.10
	if hi - lo < 0.7:
		return
	var text := ""
	if trade:
		text = _pick(b, TRADE_NAMES, "sign trade")
	else:
		var tail: String = _pick(b, HOME_TAILS, "sign tail")
		text = _pick(b, HOME_NAMES, "sign home")
		if tail != "" and not text.begins_with("CASA") and not text.begins_with("VILLA"):
			text += " " + tail
	var scheme: Array = _pick(b, SIGN_SCHEMES, "sign scheme")
	var panel: Color = scheme[0]
	var ink: Color = scheme[1]
	var cap := minf((hi - lo) * (0.62 if panel.a > 0.0 or panel.r > 0.0 else 0.72), 1.15)
	var pen := cap * 0.13
	var lay := SignFont.layout(text, cap, pen)
	var width: float = lay[1]
	var room := half * 2.0 * 0.86
	if width > room:
		var s := room / width
		cap *= s
		pen *= s
		lay = SignFont.layout(text, cap, pen)
		width = lay[1]
	if cap < 0.35:
		return
	var mid_y := (lo + hi) * 0.5
	var origin := fc + Vector3(0.0, mid_y - cap * 0.5, 0.0) + a * (-width * 0.5)
	var has_panel := panel.r + panel.g + panel.b > 0.0
	if has_panel:
		var pw := width + cap * 0.9
		var ph := cap * 1.6
		var pc := fc + Vector3(0.0, mid_y, 0.0) + n * 0.02
		acc.quad(pc - a * (pw * 0.5) - Vector3(0.0, ph * 0.5, 0.0), pc + a * (pw * 0.5) - Vector3(0.0, ph * 0.5, 0.0),
			pc + a * (pw * 0.5) + Vector3(0.0, ph * 0.5, 0.0), pc - a * (pw * 0.5) + Vector3(0.0, ph * 0.5, 0.0),
			n, K_SIGN, panel, Vector2.ZERO, Vector2(pw, ph))
	var shadow := (panel.darkened(0.55) if has_panel else Color(0.08, 0.07, 0.06))
	var sh_off := a * (pen * 0.45) - Vector3(0.0, pen * 0.45, 0.0)
	for stroke: PackedVector2Array in lay[0]:
		_ribbon(acc, stroke, origin + sh_off + n * 0.03, a, n, pen, shadow)
		_ribbon(acc, stroke, origin + n * 0.036, a, n, pen, ink)


## One stroke of a painted letter: a ribbon `pen` wide along the polyline, with square pads at the
## joints, on the wall plane at `origin` (x along `a`, y up).
static func _ribbon(acc: FacadeStreet.Acc, stroke: PackedVector2Array, origin: Vector3, a: Vector3, n: Vector3, pen: float, c: Color) -> void:
	var to3 := func(p: Vector2) -> Vector3:
		return origin + a * p.x + Vector3(0.0, p.y, 0.0)
	var hw := pen * 0.5
	for i in stroke.size() - 1:
		var p0: Vector2 = stroke[i]
		var p1: Vector2 = stroke[i + 1]
		var d := p1 - p0
		if d.length() < 0.0001:
			continue
		var side := Vector2(-d.y, d.x).normalized() * hw
		var q0: Vector3 = to3.call(p0 - side)
		var q1: Vector3 = to3.call(p1 - side)
		var q2: Vector3 = to3.call(p1 + side)
		var q3: Vector3 = to3.call(p0 + side)
		acc.quad(q0, q1, q2, q3, n, K_SIGN, c, p0, d)
	for i in stroke.size():
		var p: Vector2 = stroke[i]
		var q0: Vector3 = to3.call(p + Vector2(-hw, -hw))
		var q1: Vector3 = to3.call(p + Vector2(hw, -hw))
		var q2: Vector3 = to3.call(p + Vector2(hw, hw))
		var q3: Vector3 = to3.call(p + Vector2(-hw, hw))
		acc.quad(q0, q1, q2, q3, n, K_SIGN, c, p, Vector2(pen, pen))


## Builds the building's MidDress from what balcony() and face() gathered: one mesh, one draw, no
## shadow, no collision.
static func commit(b: Building) -> void:
	if b.has_meta("fm_dishes"):
		b.remove_meta("fm_dishes")
	_commit_one(b, "fm_acc", "MidDress", DRAW_DISTANCE)
	_commit_one(b, "fm_near", "MidDressNear", NEAR_DISTANCE)


static func _commit_one(b: Building, key: String, node_name: String, reach: float) -> void:
	if not b.has_meta(key):
		return
	var acc: FacadeStreet.Acc = b.get_meta(key)
	b.remove_meta(key)
	if acc.verts.is_empty():
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = acc.verts
	arrays[Mesh.ARRAY_NORMAL] = acc.norms
	arrays[Mesh.ARRAY_COLOR] = acc.cols
	arrays[Mesh.ARRAY_TEX_UV] = acc.uvs
	arrays[Mesh.ARRAY_TEX_UV2] = acc.uv2s
	arrays[Mesh.ARRAY_INDEX] = acc.idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.material_override = material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = reach + b.footprint.length() * 0.5
	mi.visibility_range_end_margin = 10.0
	mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	b.add_child(mi)
