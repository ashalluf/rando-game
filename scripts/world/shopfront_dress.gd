class_name ShopfrontDress
extends RefCounted
## Shop fronts at arm's length (fleet wave 4, "storefront-closeup-2"). ShopfrontKit frames the
## glass, hangs the doors, clads the piers and trims the boards; what a shop puts OUT at its door
## was missing: the things the eye lands on at 2-6 m.
##
## - a door mat on the pavement in front of the door (coir in a rubber border, a welcome mat's
##   darker band), not at a recessed entry (the shader traces that lobby);
## - planters by the door (a pair, or one where the door is against a pier): a tapered fibreglass
##   or concrete trough or a glazed pot, mulch, and a clipped box ball, a cone, a standard on its
##   stem or a tuft of grass;
## - a hanging sign on chains from a scrolled iron bracket on the pier at the door's end of the
##   shop: a painted board with a border and an emblem by trade (a cup for a cafe, a fork and knife
##   for a restaurant, a pole for a barber, a tag for a shop), on shops without an awning or a
##   blade sign of their own;
## - a menu case on the pier beside a cafe's or restaurant's door: a frame, a glazed front, the
##   menu behind it, lit after dark.
##
## Everything goes into the building's StreetDress mesh (FacadeStreet's one draw) on
## shaders/facade_street_props.gdshader, kinds K_COIR .. K_GLAZE. Every roll is a hash of the
## building's seed, the face and the shop run: no Building rng moves. The shop runs, door bays and
## recessed entries are ShopfrontKit's integer rolls (shop_byte salts 15 / 16 / 30), so the dress
## stands where the shader and the kit put the door.
##
## Other pavement things keep off what this puts down: every piece's footprint is a meta on the
## Building (`sf_dress`, Building-local [x, z, radius]) that StreetClutter._occupied() reads.
##
## `SHOPFRONT_DRESS=0` in the environment builds none of it (the A/B); it rides FacadeStreet's
## mesh, so FACADES_STREET=0 leaves it out too.

static var enabled: bool = OS.get_environment("SHOPFRONT_DRESS") != "0"

## Kinds (facade_street_props.gdshader's vertex alpha x 16), after FacadeStreet's 0..9.
const K_COIR := 10
const K_LEAF := 11
const K_SOIL := 12
const K_PAPER := 13
const K_SIGN := 14
const K_GLAZE := 15

## Shares by ShopRoom (RETAIL, CLOTHING, CAFE, RESTAURANT, LAUNDROMAT, BARBER, BANK, LOBBY).
const MAT_ODDS := [0.65, 0.7, 0.8, 0.85, 0.35, 0.7, 0.9, 0.95]
const PLANTER_ODDS := [0.28, 0.4, 0.6, 0.7, 0.08, 0.35, 0.6, 0.9]
const HANG_ODDS := [0.30, 0.30, 0.55, 0.50, 0.15, 0.55, 0.0, 0.0]
const MENU_ODDS := [0.0, 0.0, 0.75, 0.85, 0.0, 0.0, 0.0, 0.0]
const BOARD_ODDS := [0.18, 0.22, 0.65, 0.55, 0.0, 0.35, 0.0, 0.0]

## Planter shells: trough paints (fibreglass charcoal, white, corten, concrete) and glazes.
const POT_PAINTS := [Color(0.13, 0.13, 0.14), Color(0.86, 0.85, 0.82), Color(0.36, 0.19, 0.10), Color(0.58, 0.57, 0.54)]
const GLAZES := [Color(0.10, 0.20, 0.30), Color(0.55, 0.22, 0.10), Color(0.12, 0.25, 0.20), Color(0.80, 0.78, 0.72)]
## Hanging boards: ground colours (deep green, oxblood, navy, black, cream).
const BOARD_PAINTS := [Color(0.08, 0.20, 0.14), Color(0.32, 0.06, 0.06), Color(0.07, 0.11, 0.22), Color(0.05, 0.05, 0.055), Color(0.84, 0.80, 0.70)]
## Emblems (UV2.y on a sign face, the shader draws them): 1 cup, 2 fork and knife, 3 barber
## pole, 4 tag, 5 star, 6 scissors, 7 bottle; 8 is a chalkboard (a sandwich board's face).
const EMBLEM_BY_ROOM := [4, 6, 1, 2, 5, 3, 5, 5]

## How far the pavement in front may stand off the building's base before the mats and planters
## are left out (a plinth a step high or a door buried in a slope: neither is an entrance).
const FLOOR_SLACK := 0.45


## How much of its own light a shop shows by day (building.gdshader's shop_day_open /
## shop_day_light): an open shop's lights are on at noon, a closed one shows only the daylight.
const DAY_OPEN := 0.62
const DAY_CLOSED := 0.16


## The walls' daytime shop light (Building's material), when the dress is on.
static func day_light(mat: ShaderMaterial) -> void:
	if enabled:
		mat.set_shader_parameter("shop_day_open", DAY_OPEN)
		mat.set_shader_parameter("shop_day_light", DAY_CLOSED)


## 0..1 from the building's seed, the face, the shop and a tag.
static func _h(b: Building, tag: String, face_id: int, run: int) -> float:
	return float(absi(hash([b.seed, "sf_dress", tag, face_id, run])) % 100003) / 100003.0


## The pavement under a Building-local point, as a Building-local height (the chunk's relief), or
## `fallback` where the building is not in a chunk (tools, tests).
static func _floor(b: Building, p: Vector3, fallback: float) -> float:
	var ch := b.get_parent()
	if ch == null or not ch.has_method("_gy"):
		return fallback
	var w := b.transform * p
	# On LotFill's blocks (podium_lot) the lot round the building is its forecourt paving, laid
	# PAVING_LIFT over the pavement slab.
	var lift := LotFill.PAVING_LIFT if b.podium_lot else 0.0
	return CityChunk.SIDEWALK_TOP + lift + float(ch.call("_gy", w.x, w.z)) - b.position.y


static func _note(b: Building, p: Vector3, r: float) -> void:
	var spots: Array = b.get_meta("sf_dress", [])
	spots.append([p.x, p.z, r])
	b.set_meta("sf_dress", spots)


## Footprints of every chunk Building's dress, in the chunk's frame: [Vector2, radius] as
## StreetClutter's occupied list holds them.
static func occupied(chunk: Node) -> Array:
	var out: Array = []
	if not enabled:
		return out
	for c in chunk.get_children():
		var b := c as Building
		if b == null or not b.has_meta("sf_dress"):
			continue
		for s: Array in b.get_meta("sf_dress"):
			var w := b.transform * Vector3(float(s[0]), 0.0, float(s[1]))
			out.append([Vector2(w.x, w.z), float(s[2])])
	return out


## One storefront wall of a ground-floor part, called by Building beside ShopfrontKit.storefront_face()
## with the same layout (see there). `awnings`: the face hangs Building._kit_awnings() (each shop
## by its own roll), `canopy`: one canopy runs over the storefront - no sign is hung under either;
## `tower_h` the part's height (lobbies).
static func face(b: Building, face_id: int, fc: Vector3, a: Vector3, n: Vector3, size_u: float, cols: int,
		pitch: float, cut: float, bottom: float, sf: float, span: float, masonry: bool, awnings: bool, canopy: bool, tower_h: float) -> void:
	if not enabled or not FacadeStreet.enabled or bottom > 0.01 or face_id == b.back_face or sf < 2.8:
		return
	if FacadeStreet._inside_part(b, fc + n * 0.6 + Vector3(0.0, bottom + 1.5, 0.0)):
		return
	var acc := FacadeStreet._acc(b)
	var wall := Basis(a, Vector3.UP, n)
	var skip := 1 if cut > 0.0 else 0
	var half := size_u * 0.5 - cut
	var span_i := maxi(int(span + 0.5), 1)
	var runs := ceili(float(cols) / float(span_i))
	var full_runs := int(float(cols) / float(span_i))
	var glass_w := 2.0 * ShopfrontKit.GLASS_HALF * pitch
	var blade_byte := roundi(b.kit_blade_chance * 256.0)
	var pier_face := 0.455 if b._kit != null and ShopfrontKit.enabled else 0.40
	for run in runs:
		var key := b.shop_key(face_id, run)
		var lobby := Building.shop_is_lobby(key, run, full_runs, maxf(b.height, tower_h))
		var room: int = Building.ShopRoom.LOBBY if lobby else (b.shop_room(face_id, run) if run < full_runs else Building.shop_room_kind(key))
		var door_i := ShopfrontKit.door_index(key, span_i)
		var dc := run * span_i + door_i
		if dc >= cols or dc < skip or dc >= cols - skip:
			continue
		var along := size_u * 0.5 - (float(dc) + 0.5) * pitch
		var rec := ShopfrontKit.recessed(key)
		var single := ShopfrontKit.single_door(key, glass_w)
		var foot := fc + a * along + Vector3(0.0, bottom, 0.0)
		var ground := _floor(b, foot + n * 0.6, bottom)
		var level := absf(ground - bottom) <= FLOOR_SLACK
		# Where the shop's piers stand (at its two ends, where Building put them): the door bay is
		# against one when it is the run's first or last bay. +a is the run's k = 0 end.
		var pier_hi := door_i == 0 and absf(along + pitch * 0.5) <= half + 0.01
		var pier_lo := door_i == span_i - 1 and absf(along - pitch * 0.5) <= half + 0.01

		# --- The mat ----------------------------------------------------------------------
		if level and not rec and _h(b, "mat", face_id, run) < float(MAT_ODDS[room]):
			var mw := clampf(glass_w * 0.72, 0.8, 1.4)
			var mc := 0.0
			if single:
				mw = 0.85
				mc = -glass_w * 0.5 + ShopfrontKit.LEAF_SINGLE * 0.5
			var md := 0.58
			var out := (0.36 if not masonry else 0.10) + md * 0.5 + 0.03
			var at := foot + a * (-mc) + n * out
			at.y = ground
			_mat(acc, at, wall, mw, md, _h(b, "mat look", face_id, run))
			_note(b, at, maxf(mw, md) * 0.5)

		# --- Planters ---------------------------------------------------------------------
		if level and _h(b, "planter", face_id, run) < float(PLANTER_ODDS[room]):
			var style := int(_h(b, "planter style", face_id, run) * 4.0)
			var plant := int(_h(b, "plant", face_id, run) * 4.0)
			var paint: Color = POT_PAINTS[int(_h(b, "pot paint", face_id, run) * POT_PAINTS.size()) % POT_PAINTS.size()]
			var glaze: Color = GLAZES[int(_h(b, "glaze", face_id, run) * GLAZES.size()) % GLAZES.size()]
			var off := glass_w * 0.5 + 0.40
			for s: float in [1.0, -1.0]:
				# Not against a pier (its cladding and meter box stand there) nor past the wall's end.
				if (s > 0.0 and pier_hi) or (s < 0.0 and pier_lo):
					continue
				var pa := along + s * off
				if absf(pa) > half - 0.35:
					continue
				var at := fc + a * pa + n * 0.62
				at.y = ground
				_planter(acc, at, wall, style, plant, paint, glaze, _h(b, "planter grow", face_id, run * 2 + int(s > 0.0)))
				_note(b, at, 0.36)

		# --- A sandwich board out on the pavement beside the door ---------------------------
		var board_side := 1.0 if _h(b, "aboard side", face_id, run) < 0.5 else -1.0
		var ba := along + board_side * (glass_w * 0.5 + 0.55)
		if level and absf(ba) < half - 0.4 and _h(b, "aboard", face_id, run) < float(BOARD_ODDS[room]):
			var at := fc + a * ba + n * 1.30
			at.y = ground
			_sandwich_board(acc, at, wall, _h(b, "aboard look", face_id, run))
			_note(b, at, 0.42)

		# --- A hanging sign on chains from the pier at the door's end ---------------------
		var hang := not lobby and _h(b, "hang", face_id, run) < float(HANG_ODDS[room])
		var has_blade := Building.shop_byte(key, ShopfrontKit.SALT_BLADE) < blade_byte and b._kit != null and ShopfrontKit.enabled
		# Building._kit_awnings()' own roll for this shop.
		var under_cover := canopy or (awnings and b._kit_hash("awning", (face_id - 1) * 131 + run) <= b.kit_awning_chance)
		if hang and not has_blade and not under_cover and (pier_hi or pier_lo):
			var pa := along + (pitch * 0.5 if pier_hi else -pitch * 0.5)
			var ph := bottom + clampf(sf * 0.66, 2.75, 3.15)
			var paint: Color = BOARD_PAINTS[int(_h(b, "board paint", face_id, run) * BOARD_PAINTS.size()) % BOARD_PAINTS.size()]
			var emblem: int = EMBLEM_BY_ROOM[room]
			_hanging_sign(acc, fc + a * pa + Vector3(0.0, ph, 0.0) + n * pier_face, wall, paint, emblem, _h(b, "board", face_id, run))

		# --- A menu case on the pier beside a cafe's or restaurant's door -----------------
		if (pier_hi or pier_lo) and _h(b, "menu", face_id, run) < float(MENU_ODDS[room]):
			# The meter box FacadeStreet puts on the pier after a shop (between run r and r + 1).
			var pier_run := run - 1 if pier_hi else run
			var metered := pier_run >= 0 and pier_run < full_runs - 1 \
				and Building.shop_byte(b.shop_key(face_id, pier_run), FacadeStreet.SALT_METER) < FacadeStreet.METER_BYTE
			if not metered:
				var pa := along + (pitch * 0.5 if pier_hi else -pitch * 0.5)
				var lit := 1.0 if Building.shop_open(key) else 0.0
				_menu_case(acc, fc + a * pa + Vector3(0.0, bottom + 1.18, 0.0) + n * pier_face, wall, lit, _h(b, "menu look", face_id, run))


# --- The pieces (wall frame: `w.x` along the wall, `w.z` out of it, `at` the piece's foot) ----

## A coir mat in a rubber border, 15 mm thick.
static func _mat(acc: FacadeStreet.Acc, at: Vector3, w: Basis, mw: float, md: float, look: float) -> void:
	var rubber := Color(0.05, 0.05, 0.05)
	acc.box(Transform3D(w, at + Vector3(0.0, 0.004, 0.0)), Vector3(mw, 0.008, md), FacadeStreet.K_RUBBER, rubber, 0.0, false)
	var coir := Color(0.62, 0.45, 0.26).lerp(Color(0.32, 0.24, 0.16), look)
	if look > 0.82:
		coir = Color(0.12, 0.12, 0.13)   # a black ribbed entrance mat
	acc.box(Transform3D(w, at + Vector3(0.0, 0.0085, 0.0)), Vector3(mw - 0.05, 0.013, md - 0.05), K_COIR, coir, 0.0, false)


## A planter: `style` 0 a tapered square trough, 1 a tall round fibreglass tub, 2 a glazed pot,
## 3 a long low trough; `plant` 0 a box ball, 1 a cone, 2 a standard (ball on a stem), 3 grass.
static func _planter(acc: FacadeStreet.Acc, at: Vector3, w: Basis, style: int, plant: int, paint: Color, glaze: Color, grow: float) -> void:
	var top := 0.0
	var r_top := 0.0
	match style:
		0:
			top = 0.58
			r_top = 0.21
			_frustum(acc, at, w, 0.16, r_top, top, 4, FacadeStreet.K_PAINT, paint)
		1:
			top = 0.70
			r_top = 0.20
			_frustum(acc, at, w, 0.17, r_top, top, 14, FacadeStreet.K_PAINT, paint)
		2:
			top = 0.50
			r_top = 0.22
			_frustum(acc, at, w, 0.14, 0.24, top * 0.82, 14, K_GLAZE, glaze)
			_frustum(acc, at + Vector3(0.0, top * 0.82, 0.0), w, 0.24, r_top, top * 0.18, 14, K_GLAZE, glaze)
		_:
			top = 0.45
			r_top = 0.21
			_frustum(acc, at, w, 0.17, r_top, top, 4, FacadeStreet.K_CONCRETE, Color(0.62, 0.61, 0.58))
	var sq := style == 0 or style == 3
	# The soil just under the rim.
	var soil_y := top - 0.04
	if sq:
		acc.quad(at + w * Vector3(-r_top + 0.02, soil_y, -r_top + 0.02), at + w * Vector3(r_top - 0.02, soil_y, -r_top + 0.02),
			at + w * Vector3(r_top - 0.02, soil_y, r_top - 0.02), at + w * Vector3(-r_top + 0.02, soil_y, r_top - 0.02),
			Vector3.UP, K_SOIL, Color(0.20, 0.13, 0.08), Vector2.ZERO, Vector2(0.4, 0.4))
	else:
		acc.disc(at + Vector3(0.0, soil_y, 0.0), Vector3.UP, r_top - 0.015, K_SOIL, Color(0.20, 0.13, 0.08), 0.0, 14)
	# A rim lip on the round ones.
	if not sq:
		_frustum(acc, at + Vector3(0.0, top - 0.035, 0.0), w, r_top + 0.012, r_top + 0.012, 0.035, 14,
			K_GLAZE if style == 2 else FacadeStreet.K_PAINT, glaze if style == 2 else paint)
	var leaf := Color(0.14, 0.26, 0.09).lerp(Color(0.20, 0.30, 0.12), grow)
	var base := at + Vector3(0.0, soil_y, 0.0)
	match plant:
		0:
			_blob(acc, base + Vector3(0.0, 0.24 + 0.04 * grow, 0.0), Vector3(0.27, 0.25, 0.27) * (0.95 + 0.15 * grow), leaf, grow)
		1:
			_cone_bush(acc, base, 0.24, 0.85 + 0.25 * grow, leaf, grow)
		2:
			acc.tube(base, base + Vector3(0.0, 0.62, 0.0), 0.016, FacadeStreet.K_PAINT, Color(0.24, 0.17, 0.11), 5)
			_blob(acc, base + Vector3(0.0, 0.80 + 0.06 * grow, 0.0), Vector3(0.24, 0.23, 0.24), leaf, grow)
			_blob(acc, base + Vector3(0.0, 0.05, 0.0), Vector3(0.18, 0.06, 0.18), leaf.darkened(0.15), grow + 0.5)
		_:
			_grass(acc, base, w, Color(0.36, 0.40, 0.18).lerp(Color(0.52, 0.48, 0.26), grow), grow)


## A tapered shell: a frustum of `sides` faces from radius r0 at the foot to r1 at `h`, its top
## open (the soil and a lip close it). Four sides: a square trough turned to the wall.
static func _frustum(acc: FacadeStreet.Acc, at: Vector3, w: Basis, r0: float, r1: float, h: float, sides: int, kind: int, col: Color) -> void:
	var square := sides == 4
	for k in sides:
		var t0 := TAU * float(k) / float(sides) + (PI * 0.25 if square else 0.0)
		var t1 := TAU * float(k + 1) / float(sides) + (PI * 0.25 if square else 0.0)
		var s := 1.4142 if square else 1.0
		var d0 := Vector3(cos(t0), 0.0, sin(t0)) * s
		var d1 := Vector3(cos(t1), 0.0, sin(t1)) * s
		var p0 := at + w * (d0 * r0)
		var p1 := at + w * (d1 * r0)
		var p2 := at + w * (d1 * r1) + Vector3(0.0, h, 0.0)
		var p3 := at + w * (d0 * r1) + Vector3(0.0, h, 0.0)
		var mid := w * ((d0 + d1) * 0.5).normalized()
		var nrm := (mid * h + Vector3(0.0, r0 - r1, 0.0)).normalized()
		acc.quad(p0, p1, p2, p3, nrm, kind, col, Vector2(float(k) * r0, 0.0), Vector2(r0 * 1.4, h))
	acc.pieces += 1


## A clipped mass of foliage: a lumpy ellipsoid (radii `r`), its normals left round.
static func _blob(acc: FacadeStreet.Acc, c: Vector3, r: Vector3, col: Color, seed01: float) -> void:
	var rings := 6
	var segs := 9
	var pts: Array[Vector3] = []
	var nrm: Array[Vector3] = []
	for i in rings + 1:
		var v := PI * float(i) / float(rings)
		for j in segs + 1:
			var u := TAU * float(j) / float(segs)
			var d := Vector3(sin(v) * cos(u), cos(v), sin(v) * sin(u))
			var bump := 1.0 + 0.07 * sin(u * 3.0 + seed01 * 9.0 + v * 2.0) * sin(v * 3.0 + seed01 * 4.0)
			if j == segs:
				bump = 1.0 + 0.07 * sin(seed01 * 9.0 + v * 2.0) * sin(v * 3.0 + seed01 * 4.0)
			pts.append(c + Vector3(d.x * r.x, d.y * r.y, d.z * r.z) * bump)
			nrm.append(Vector3(d.x / r.x, d.y / r.y, d.z / r.z).normalized())
	_grid(acc, pts, nrm, rings, segs, K_LEAF, col)


## A clipped cone (a topiary), on the soil at `base`.
static func _cone_bush(acc: FacadeStreet.Acc, base: Vector3, r: float, h: float, col: Color, seed01: float) -> void:
	var rings := 5
	var segs := 9
	var pts: Array[Vector3] = []
	var nrm: Array[Vector3] = []
	for i in rings + 1:
		var t := float(i) / float(rings)
		var rr := r * sqrt(maxf(1.0 - t, 0.0)) * (1.0 - t * 0.35)
		for j in segs + 1:
			var u := TAU * float(j) / float(segs)
			var d := Vector3(cos(u), 0.0, sin(u))
			var bump := 1.0 + 0.06 * sin(float(j % segs) * 2.1 + seed01 * 7.0 + t * 5.0)
			pts.append(base + Vector3(0.0, 0.03 + t * h, 0.0) + d * rr * bump)
			nrm.append((d * h + Vector3(0.0, r * 0.8, 0.0)).normalized())
	_grid(acc, pts, nrm, rings, segs, K_LEAF, col)


## A tuft of ornamental grass: blades arching out of the pot, both faces.
static func _grass(acc: FacadeStreet.Acc, base: Vector3, w: Basis, col: Color, seed01: float) -> void:
	var blades := 16
	for k in blades:
		var ang := TAU * (float(k) / float(blades) + seed01 * 0.37) + sin(float(k) * 2.3) * 0.3
		var dir := w * Vector3(cos(ang), 0.0, sin(ang))
		var hgt := 0.55 + 0.25 * fposmod(sin(float(k) * 12.9898 + seed01 * 7.0) * 43758.5453, 1.0)
		var lean := 0.10 + 0.18 * fposmod(sin(float(k) * 78.233 + seed01 * 3.0) * 12543.13, 1.0)
		var side := dir.cross(Vector3.UP).normalized() * 0.012
		var p0 := base + dir * 0.03
		var p1 := base + dir * (lean * 0.6) + Vector3(0.0, hgt * 0.65, 0.0)
		var p2 := base + dir * (lean * 1.6) + Vector3(0.0, hgt, 0.0)
		var nrm := dir.cross(side).normalized()
		if nrm.y < 0.0:
			nrm = -nrm
		var c2 := col.lightened(0.15)
		for s: float in [1.0, -1.0]:
			acc.quad(p0 - side, p0 + side, p1 + side * 0.7, p1 - side * 0.7, nrm * s, K_LEAF, col, Vector2.ZERO, Vector2(0.03, 0.4))
			acc.quad(p1 - side * 0.7, p1 + side * 0.7, p2, p2, nrm * s, K_LEAF, c2, Vector2.ZERO, Vector2(0.03, 0.4))
	acc.pieces += 1


## A grid of (rings + 1) x (segs + 1) points with their normals, as quads facing out.
static func _grid(acc: FacadeStreet.Acc, pts: Array[Vector3], nrm: Array[Vector3], rings: int, segs: int, kind: int, col: Color) -> void:
	var base := acc.verts.size()
	var c := Color(col.r, col.g, col.b, (float(kind) + 0.25) / 16.0)
	for i in rings + 1:
		for j in segs + 1:
			var k := i * (segs + 1) + j
			acc.verts.append(pts[k])
			acc.norms.append(nrm[k])
			acc.cols.append(c)
			acc.uvs.append(Vector2(float(j) / float(segs) * 1.6, float(i) / float(rings) * 0.9))
			acc.uv2s.append(Vector2.ZERO)
	for i in rings:
		for j in segs:
			var p0 := base + i * (segs + 1) + j
			var p1 := p0 + 1
			var p2 := p0 + segs + 1
			var p3 := p2 + 1
			var tri_n := (pts[p1 - base] - pts[p0 - base]).cross(pts[p2 - base] - pts[p0 - base])
			var out_n := nrm[p0 - base] + nrm[p3 - base]
			if tri_n.dot(out_n) > 0.0:
				acc.idx.append_array([p0, p2, p1, p1, p2, p3])
			else:
				acc.idx.append_array([p0, p1, p2, p1, p3, p2])
	acc.pieces += 1


## A sign hung on two chains from a scrolled iron bracket on the pier face (`at`, the bracket's
## wall plate): the board 0.56 x 0.40 m, turned square to the wall so both faces read from the
## pavement, its faces painted with a border and the trade's emblem.
static func _hanging_sign(acc: FacadeStreet.Acc, at: Vector3, w: Basis, paint: Color, emblem: int, seed01: float) -> void:
	var iron := Color(0.03, 0.03, 0.032)
	var reach := 0.82
	var x := w.x
	var z := w.z
	# Wall plate, arm, and the scroll stay under it.
	acc.box(Transform3D(w, at + z * 0.012), Vector3(0.10, 0.30, 0.024), FacadeStreet.K_IRON, iron)
	acc.box(Transform3D(w, at + Vector3(0.0, 0.10, 0.0) + z * (reach * 0.5 + 0.02)), Vector3(0.022, 0.03, reach), FacadeStreet.K_IRON, iron)
	acc.box(Transform3D(w, at + Vector3(0.0, 0.10, 0.0) + z * (reach + 0.03)), Vector3(0.045, 0.045, 0.045), FacadeStreet.K_IRON, iron)
	var prev := at + Vector3(0.0, -0.12, 0.0) + z * 0.02
	var steps := 5
	for k in range(1, steps + 1):
		# A quarter turn from the plate's foot up to the arm, then a small curl at the end.
		var t := float(k) / float(steps)
		var ang := t * PI * 0.5
		var p := at + Vector3(0.0, -0.12 + 0.22 * sin(ang), 0.0) + z * (0.02 + 0.52 * (1.0 - cos(ang)))
		acc.tube(prev, p, 0.009, FacadeStreet.K_IRON, iron, 4)
		prev = p
	var curl := at + Vector3(0.0, 0.10, 0.0) + z * 0.54
	for k in 5:
		var a0 := TAU * float(k) / 5.0
		var a1 := TAU * float(k + 1) / 5.0
		acc.tube(curl + Vector3(0.0, -0.045 + 0.04 * cos(a0), 0.0) + z * (0.06 * sin(a0)),
			curl + Vector3(0.0, -0.045 + 0.04 * cos(a1), 0.0) + z * (0.06 * sin(a1)), 0.008, FacadeStreet.K_IRON, iron, 4)
	# Two chains of links, alternately turned, from the arm to the board's top corners.
	var bw := 0.56
	var bh := 0.40
	var drop := 0.20 + 0.04 * seed01
	var top := at + Vector3(0.0, 0.085 - drop, 0.0)
	for s: float in [-1.0, 1.0]:
		var hook := at + Vector3(0.0, 0.085, 0.0) + z * (reach * 0.5 + 0.06 + s * (bw * 0.5 - 0.06))
		_chain(acc, hook, hook - Vector3(0.0, drop, 0.0), x, z, iron)
	# The board: painted faces either side, its edges, and two eye bolts.
	var bc := top + z * (reach * 0.5 + 0.06) + Vector3(0.0, -bh * 0.5, 0.0)
	var th := 0.032
	for s: float in [1.0, -1.0]:
		var f := bc + x * (th * 0.5 * s)
		var p0 := f + z * (-bw * 0.5 * s) + Vector3(0.0, -bh * 0.5, 0.0)
		var p1 := f + z * (bw * 0.5 * s) + Vector3(0.0, -bh * 0.5, 0.0)
		var p2 := f + z * (bw * 0.5 * s) + Vector3(0.0, bh * 0.5, 0.0)
		var p3 := f + z * (-bw * 0.5 * s) + Vector3(0.0, bh * 0.5, 0.0)
		acc.quad(p0, p1, p2, p3, x * s, K_SIGN, paint, Vector2.ZERO, Vector2(bw, bh))
		var last := acc.uv2s.size()
		for k in 4:
			acc.uv2s[last - 1 - k] = Vector2(0.0, float(emblem))
	acc.box(Transform3D(w, bc + Vector3(0.0, bh * 0.5 + 0.006, 0.0)), Vector3(th + 0.006, 0.012, bw + 0.006), FacadeStreet.K_PAINT, paint.darkened(0.3), 0.0, false)
	acc.box(Transform3D(w, bc - Vector3(0.0, bh * 0.5 + 0.006, 0.0)), Vector3(th + 0.006, 0.012, bw + 0.006), FacadeStreet.K_PAINT, paint.darkened(0.3), 0.0, false)
	for s: float in [-1.0, 1.0]:
		acc.box(Transform3D(w, bc + z * (s * (bw * 0.5 + 0.004))), Vector3(th + 0.006, bh + 0.024, 0.01), FacadeStreet.K_PAINT, paint.darkened(0.3), 0.0, false)
	acc.pieces += 1


## A sandwich board: two chalkboards 0.56 x 0.82 m in timber or black steel frames hinged at the
## top 0.92 m up, splayed, their faces along the wall so they read walking past.
static func _sandwich_board(acc: FacadeStreet.Acc, at: Vector3, w: Basis, look: float) -> void:
	var frame := Color(0.30, 0.20, 0.12) if look < 0.55 else Color(0.04, 0.04, 0.045)
	var kind := FacadeStreet.K_PAINT
	var hgt := 0.92
	var bw := 0.56
	var splay := 0.16
	for s: float in [1.0, -1.0]:
		# The board leans from the hinge (top, on the centre line) out to its foot.
		var foot := at + w.x * (s * hgt * sin(splay))
		var top := at + Vector3(0.0, hgt, 0.0)
		var up := (top - foot).normalized()
		var out := w.x * s * cos(splay) - Vector3(0.0, sin(splay), 0.0) * 0.0
		out = (out - up * out.dot(up)).normalized()
		var side := w.z
		var mid := (foot + top) * 0.5 + out * 0.012
		var bh := (top - foot).length()
		# Frame: four rails round the slate.
		var bx := Basis(side, up, out)
		acc.box(Transform3D(bx, mid), Vector3(bw, bh, 0.022), kind, frame)
		# The slate's face, inset in the frame.
		var f := mid + out * 0.0115
		var hx := bw * 0.5 - 0.035
		var hy := bh * 0.5 - 0.035
		acc.quad(f - side * hx - up * hy, f + side * hx - up * hy, f + side * hx + up * hy, f - side * hx + up * hy,
			out, K_SIGN, Color(0.07, 0.08, 0.08), Vector2.ZERO, Vector2(hx * 2.0, hy * 2.0))
		var last := acc.uv2s.size()
		for k in 4:
			acc.uv2s[last - 1 - k] = Vector2(look, 8.0)
	acc.pieces += 1


## A chain hanging from `a0` to `a1`: oval links 5 cm long, each turned a quarter from the last.
static func _chain(acc: FacadeStreet.Acc, a0: Vector3, a1: Vector3, x: Vector3, z: Vector3, col: Color) -> void:
	var length := a0.distance_to(a1)
	var links := maxi(int(length / 0.05), 2)
	var step := length / float(links)
	for k in links:
		var c := a0.lerp(a1, (float(k) + 0.5) / float(links))
		var side := x if k % 2 == 0 else z
		var hl := step * 0.62
		var hw := 0.014
		var pts: Array[Vector3] = [c + Vector3(0.0, hl, 0.0), c + side * hw, c - Vector3(0.0, hl, 0.0), c - side * hw]
		for i in 4:
			acc.tube(pts[i], pts[(i + 1) % 4], 0.0035, FacadeStreet.K_IRON, col, 3)


## A menu case on the pier face (`at` its centre on the face, 1.18 m up its foot at the bottom):
## a frame 0.38 x 0.52 m, 6 cm deep, the menu behind a glazed front, lit after dark.
static func _menu_case(acc: FacadeStreet.Acc, at: Vector3, w: Basis, lit: float, look: float) -> void:
	var frame := Color(0.04, 0.04, 0.045) if look < 0.6 else Color(0.48, 0.36, 0.16)
	var kind := FacadeStreet.K_PAINT if look < 0.6 else FacadeStreet.K_COPPER
	var cw := 0.38
	var chh := 0.52
	var c := at + Vector3(0.0, chh * 0.5, 0.0)
	acc.box(Transform3D(w, c + w.z * 0.03), Vector3(cw, chh, 0.06), kind, frame)
	# The menu itself, a hair proud of the frame's face (the glass is its gloss).
	var f := c + w.z * 0.0605
	var hx := cw * 0.5 - 0.025
	var hy := chh * 0.5 - 0.025
	acc.quad(f - w.x * hx - Vector3(0.0, hy, 0.0), f + w.x * hx - Vector3(0.0, hy, 0.0),
		f + w.x * hx + Vector3(0.0, hy, 0.0), f - w.x * hx + Vector3(0.0, hy, 0.0), w.z, K_PAPER,
		Color(0.93, 0.91, 0.85) if look < 0.8 else Color(0.10, 0.10, 0.10), Vector2.ZERO, Vector2(hx * 2.0, hy * 2.0), lit)
	# The case's top, a little cap over it.
	acc.box(Transform3D(w, c + Vector3(0.0, chh * 0.5 + 0.012, 0.0) + w.z * 0.035), Vector3(cw + 0.03, 0.024, 0.075), kind, frame)
