class_name FacadeStreet
extends RefCounted
## The street level up close (fleet wave 3, "facades-street"; the owner's bar: "make it look like
## GTA 6"). Standing on the pavement, the first two storeys of a Building are what the player sees
## most, and they read as a printed box: one even material, no hardware, the wall meeting the
## pavement in a clean line. Two halves:
##
## - shaders/facade_street.gdshaderinc, in building.gdshader on the wall's own UVs: the relief
##   (stucco grain and trowel, precast form-tie holes, the base course's V-joints, brick mortar
##   raked back), patched render, cracks off the window corners, the splash-back, damp, salt and
##   scuffs at the foot, grime and chips at the corners, a door in every ground floor without shops
##   (fs_door_col()) and the light of the lamps over doors and sign boards after dark.
## - This file: the hardware, built in code into ONE mesh a building (StreetDress, one draw, no
##   collision) on shaders/facade_street_props.gdshader: downpipes with hoppers and shoes, conduit
##   with meter and panel boxes, condensers on wall brackets with their line sets, window grilles,
##   the door's lamp and step, gooseneck lamps over sign boards, roll-down shutter housings and
##   guide rails, thresholds at shop doors.
##
## Every placement is a hash of the building's seed and the wall, never a Building rng: nothing a
## seed built before moves. Where the shader and this file must agree (the door's bay, its size,
## its lamp; which shops hang goosenecks) the roll is an INTEGER one, the same function on both
## sides (door_col(), lamp_kind(), lamp_lit(), Building.shop_byte() salts 46-47); checks in
## tests/facades_street_checks.gd hold the copies together.
##
## `FACADES_STREET=0` in the environment turns all of it off (the A/B): the walls draw exactly as
## before and no StreetDress is built.

static var enabled: bool = OS.get_environment("FACADES_STREET") != "0"

const SHADER := preload("res://shaders/facade_street_props.gdshader")
static var _material: ShaderMaterial

## How far the hardware draws (metres from the building's centre, plus half its footprint).
const PROPS_DISTANCE := 105.0

## Kinds (the props shader's vertex alpha x 16).
const K_PAINT := 0
const K_GALV := 1
const K_CONCRETE := 2
const K_LENS := 3
const K_FAN := 4
const K_GLASS := 5
const K_COPPER := 6
const K_RUBBER := 7
const K_IRON := 8
const K_STONE := 9

## Shares (of walls, shops or windows).
const PIPE_ODDS := 0.6
const GRILLE_ODDS := 0.45
const PANEL_ODDS := 0.5
const CONDENSER_ODDS := 0.4
## Shop rolls (Building.shop_byte(key, salt) < byte): a gooseneck over the board (the shader's
## fascia wash uses the same), a meter box on the pier after the shop.
const SALT_GOOSE := 46
const GOOSE_BYTE := 96
const SALT_METER := 47
const METER_BYTE := 80
## The door lamp's colours: the shader's (warm bulkhead and barn light, cool LED wall pack).
const LAMP_WARM := Color(1.0, 0.70, 0.40)
const LAMP_COOL := Color(0.85, 0.92, 1.0)

const PIPE_PAINTS := [Color(0.06, 0.06, 0.065), Color(0.86, 0.85, 0.80), Color(0.24, 0.26, 0.22)]
const BOX_PAINTS := [Color(0.62, 0.63, 0.60), Color(0.70, 0.70, 0.66), Color(0.45, 0.47, 0.46)]
const IRON_PAINTS := [Color(0.03, 0.03, 0.035), Color(0.80, 0.80, 0.76), Color(0.12, 0.18, 0.13)]
const LAMP_PAINTS := [Color(0.05, 0.05, 0.05), Color(0.08, 0.16, 0.11), Color(0.20, 0.14, 0.09)]


## The integer key of one wall of one part (the shader's fs_face_key()).
static func face_key(shader_seed: int, face_id: int, face_len: float) -> int:
	var sd := clampi(absi(shader_seed), 0, 999)
	var l := int(floor(face_len * 4.0 + 0.5)) & 4095
	return (sd * 8 + face_id) * 4096 + l


## The bay (counted along the shader's u) a ground floor without shops has its door in, or -1
## (the shader's fs_door_col()).
static func door_col(key: int, cols: int) -> int:
	if cols < 3:
		return -1
	if (Building.shop_hash(key, 90) >> 24) >= 160:
		return -1
	return 1 + Building.shop_hash(key, 91) % (cols - 2)


## How far up the door's threshold is (the shader's fs_door_sill()): on the plinth band of a masonry
## wall, at the pavement on a glass-finished one.
static func door_sill(finish: int) -> float:
	return 0.0 if finish == Building.Finish.GLASS else 0.64


## The door's width and height (the shader's fs_door_size()).
static func door_size(pitch: float, floor_h: float, sill: float) -> Vector2:
	return Vector2(clampf(pitch * 0.55, 0.92, 1.05), minf(2.22, floor_h - sill - 0.45))


## The lamp over a door: 0 a caged bulkhead, 1 a gooseneck barn light, 2 an LED wall pack.
static func lamp_kind(key: int) -> int:
	return Building.shop_hash(key, 93) % 3


static func lamp_lit(key: int) -> bool:
	return (Building.shop_hash(key, 98) >> 24) < 216


## Whether this wall of this part has a door the shader draws (its conditions, line for line).
static func door_wall(b: Building, face_id: int, bottom: float, storefront: float, pitch: float, floor_h: float, parking: bool) -> bool:
	return enabled and b.shape != Building.Shape.WAREHOUSE \
		and (b.window_style == Building.WindowStyle.PUNCHED or b.window_style == Building.WindowStyle.NARROW) \
		and storefront <= 0.0 and face_id != b.back_face and bottom < 0.01 and not parking \
		and pitch >= 1.4 and floor_h >= 3.0


## The door's bay on this wall (shader col), or -1.
static func door_for(b: Building, face_id: int, size_u: float, cols: int, bottom: float, storefront: float, pitch: float, floor_h: float, parking: bool = false) -> int:
	if not door_wall(b, face_id, bottom, storefront, pitch, floor_h, parking):
		return -1
	return door_col(face_key(b.seed % 1000, face_id, size_u), cols)


static func material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = SHADER
	return _material


## What a building's StreetDress is being built from.
class Acc:
	extends RefCounted
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var idx := PackedInt32Array()
	var pieces := 0

	## One quad, wound so its front faces `n` (Godot's front faces are clockwise).
	func quad(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, n: Vector3, kind: int, col: Color, uv0 := Vector2.ZERO, uv_size := Vector2.ONE, lit := 0.0) -> void:
		var base := verts.size()
		var c := Color(col.r, col.g, col.b, (float(kind) + 0.25) / 16.0)
		verts.append_array([p0, p1, p2, p3])
		for k in 4:
			norms.append(n)
			cols.append(c)
			uv2s.append(Vector2(lit, 0.0))
		uvs.append_array([uv0, uv0 + Vector2(uv_size.x, 0.0), uv0 + uv_size, uv0 + Vector2(0.0, uv_size.y)])
		if (p1 - p0).cross(p2 - p0).dot(n) > 0.0:
			idx.append_array([base, base + 2, base + 1, base, base + 3, base + 2])
		else:
			idx.append_array([base, base + 1, base + 2, base, base + 2, base + 3])

	## A box: `xf` places its centre and axes (columns scaled to the half size are NOT used: the
	## basis is a rotation, `size` the full size).
	func box(xf: Transform3D, size: Vector3, kind: int, col: Color, lit := 0.0, skip_back := true) -> void:
		var h := size * 0.5
		var b := xf.basis.orthonormalized()
		var o := xf.origin
		var ax := [b.x, b.y, b.z]
		var hs := [h.x, h.y, h.z]
		for i in 3:
			for s: float in [-1.0, 1.0]:
				if skip_back and i == 2 and s < 0.0:
					continue
				var n: Vector3 = ax[i] * s
				var u: Vector3 = ax[(i + 1) % 3]
				var v: Vector3 = ax[(i + 2) % 3]
				var hu: float = hs[(i + 1) % 3]
				var hv: float = hs[(i + 2) % 3]
				var c: Vector3 = o + n * float(hs[i])
				quad(c - u * hu - v * hv, c + u * hu - v * hv, c + u * hu + v * hv, c - u * hu + v * hv, n, kind, col,
					Vector2.ZERO, Vector2(hu * 2.0, hv * 2.0), lit)
		pieces += 1

	## A round tube from `a` to `b`, `segs` sides, open ends.
	func tube(a: Vector3, b: Vector3, r: float, kind: int, col: Color, segs := 6) -> void:
		var d := b - a
		var length := d.length()
		if length < 0.002:
			return
		var w := d / length
		var u := w.cross(Vector3.UP if absf(w.y) < 0.9 else Vector3.RIGHT).normalized()
		var v := w.cross(u)
		for k in segs:
			var t0 := TAU * float(k) / float(segs)
			var t1 := TAU * float(k + 1) / float(segs)
			var n0 := u * cos(t0) + v * sin(t0)
			var n1 := u * cos(t1) + v * sin(t1)
			var nm := (n0 + n1).normalized()
			quad(a + n0 * r, a + n1 * r, b + n1 * r, b + n0 * r, nm, kind, col, Vector2(float(k) * r, 0.0), Vector2(r, length))
		pieces += 1

	## A flat disc of `r` facing `n` at `c`.
	func disc(c: Vector3, n: Vector3, r: float, kind: int, col: Color, lit := 0.0, segs := 10) -> void:
		var u := n.cross(Vector3.UP if absf(n.y) < 0.9 else Vector3.RIGHT).normalized()
		var v := n.cross(u)
		for k in segs:
			var t0 := TAU * float(k) / float(segs)
			var t1 := TAU * float(k + 1) / float(segs)
			var p0 := c + (u * cos(t0) + v * sin(t0)) * r
			var p1 := c + (u * cos(t1) + v * sin(t1)) * r
			quad(c, p0, p1, c, n, kind, col, Vector2(0.5, 0.5), Vector2(0.0, 0.0), lit)
		pieces += 1


static func _acc(b: Building) -> Acc:
	if not b.has_meta("fs_acc"):
		b.set_meta("fs_acc", Acc.new())
	return b.get_meta("fs_acc")


## 0..1 from the building's seed and anything else.
static func _h(b: Building, tag: String, a: int = 0, c: int = 0) -> float:
	return float(absi(hash([b.seed, "facade_street", tag, a, c])) % 100003) / 100003.0


## Whether the point is inside another part of the building (a face against a taller wing).
static func _inside_part(b: Building, p: Vector3) -> bool:
	for part in b.parts:
		var c: Vector3 = part.center
		var h: Vector3 = (part.size as Vector3) * 0.5
		if absf(p.x - c.x) < h.x and absf(p.y - c.y) < h.y and absf(p.z - c.z) < h.z:
			return true
	return false


## One wall of one part, called from Building._add_facade_details() with what it knows of it.
## `covered`: the storefront wears awnings or a canopy (no shutter housings under them);
## `busy`: a fire escape or balconies hang on this wall (no downpipe at its end).
static func face(b: Building, face_index: int, fc: Vector3, a: Vector3, n: Vector3, size_u: float, cols: int,
		pitch: float, cut: float, bottom: float, storefront: float, floor_h: float, rows: int, top: float,
		shops: bool, span: float, covered: bool, busy: bool, masonry: bool) -> void:
	if not enabled or b.shape == Building.Shape.WAREHOUSE or bottom > 0.01:
		return
	var face_id := face_index + 1
	# A wall standing against another wing of the building gets nothing.
	if _inside_part(b, fc + n * 0.6 + Vector3(0.0, bottom + 1.5, 0.0)):
		return
	var acc := _acc(b)
	var fkey := (face_index * 7919 + roundi(fc.x * 10.0)) * 104729 + roundi(fc.z * 10.0)
	var skip := 1 if cut > 0.0 else 0
	var half := size_u * 0.5 - cut
	var rect: Array = Building.WINDOW_RECTS[b.window_style]
	var cy: float = rect[1]
	var hx: float = rect[2]
	var hy: float = rect[3]
	var punched := b.window_style == Building.WindowStyle.PUNCHED or b.window_style == Building.WindowStyle.NARROW
	var dcol := door_for(b, face_id, size_u, cols, bottom, storefront, pitch, floor_h)
	var dkey := face_key(b.seed % 1000, face_id, size_u)

	# --- The door's lamp and step -----------------------------------------------------------
	if dcol >= 0:
		var along := size_u * 0.5 - (float(dcol) + 0.5) * pitch
		var sill := door_sill(b.finish)
		var ds := door_size(pitch, floor_h, sill)
		var at := fc + a * along + Vector3(0.0, bottom, 0.0)
		_step(acc, at, a, n, ds.x + 0.5, sill)
		_door_lamp(acc, at + Vector3(0.0, sill + ds.y + 0.42, 0.0), a, n, lamp_kind(dkey), lamp_lit(dkey),
			LAMP_PAINTS[absi(hash([b.seed, "fs lamp paint", fkey])) % LAMP_PAINTS.size()])

	# --- Grilles over the ground-floor windows of a wall without shops ----------------------
	if storefront <= 0.0 and punched and face_id != b.back_face and _h(b, "grille", fkey) < GRILLE_ODDS:
		var iron: Color = IRON_PAINTS[absi(hash([b.seed, "fs iron", fkey])) % IRON_PAINTS.size()]
		var w := 2.0 * hx * pitch + 0.10
		var h := 2.0 * hy * floor_h + 0.10
		var residential := masonry and b.window_style != Building.WindowStyle.CURTAIN
		var ac_ok := b._kit != null and b.window_style == Building.WindowStyle.PUNCHED and residential and w - 0.10 >= 0.8
		for col in range(skip, cols - skip):
			if col == dcol:
				continue
			# The kit's window AC on this sill (Building's own roll, its column counted the other way).
			var kcol := cols - 1 - col
			if ac_ok and b._kit_hash("ac", (face_index * 1009 + kcol) * 997 + 0) < b.kit_ac_chance:
				continue
			var at := fc + a * (size_u * 0.5 - (float(col) + 0.5) * pitch) + Vector3(0.0, bottom + cy * floor_h, 0.0)
			_grille(acc, at, a, n, w, h, iron)

	# --- A downpipe at one end of the wall --------------------------------------------------
	if not busy and size_u >= 5.0 and top - bottom <= 24.0 and _h(b, "pipe", fkey) < PIPE_ODDS:
		var side := 1.0 if _h(b, "pipe side", fkey) < 0.5 else -1.0
		var along := side * (half - 0.34)
		var paint_k := absi(hash([b.seed, "fs pipe paint"])) % 4
		var paint: Color = b.facade_color.darkened(0.12) if paint_k == 3 else PIPE_PAINTS[paint_k]
		var kind := K_GALV if paint_k == 0 and _h(b, "galv") < 0.5 else K_PAINT
		var y0 := bottom + (storefront + 0.32 if shops else (0.72 if masonry else 0.12))
		var y1 := top - (0.95 if masonry else 0.25)
		if y1 - y0 > 2.0:
			_downpipe(acc, fc + a * along, a, n, y0, y1, shops, _h(b, "pipe square") < 0.35, kind, paint)

	# --- Conduit and meters -----------------------------------------------------------------
	var box_paint: Color = BOX_PAINTS[absi(hash([b.seed, "fs box"])) % BOX_PAINTS.size()]
	if shops and storefront > 0.0 and span >= 1.0:
		# On the piers between shops: a meter box with conduit up to the band over the shopfront.
		var span_i := maxi(int(span + 0.5), 1)
		var runs := int(float(cols) / float(span_i))
		for run in range(0, runs - 1):
			var key := b.shop_key(face_id, run)
			if Building.shop_byte(key, SALT_METER) >= METER_BYTE:
				continue
			var pu := size_u * 0.5 - float((run + 1) * span_i) * pitch
			if absf(pu) > half - 0.4:
				continue
			_meter_on_pier(acc, fc + a * pu + Vector3(0.0, bottom, 0.0), a, n, storefront, box_paint,
				0.49 if b._kit != null and ShopfrontKit.enabled else 0.40)
	elif storefront <= 0.0 and punched and face_id != b.back_face and _h(b, "panel", fkey) < PANEL_ODDS:
		# On the wall between two ground-floor windows, clear of the door.
		var pier := pitch * (1.0 - 2.0 * hx)
		if pier >= 0.7 and cols >= 2:
			var k := 1 + absi(hash([b.seed, "fs panel col", fkey])) % maxi(cols - 1, 1)
			if k - 1 != dcol and k != dcol and k > skip and k < cols - skip:
				var at := fc + a * (size_u * 0.5 - float(k) * pitch) + Vector3(0.0, bottom, 0.0)
				_panel_cluster(acc, at, a, n, minf(pier - 0.12, 0.6), floor_h, box_paint)

	# --- A condenser on wall brackets on the wall between two windows of the first storey ----
	if punched and face_id != b.back_face and cols >= 3 and pitch * (1.0 - 2.0 * hx) >= 0.98 and floor_h >= 2.9 \
			and _h(b, "condenser", fkey) < CONDENSER_ODDS:
		var k := 1 + skip + absi(hash([b.seed, "fs condenser col", fkey])) % maxi(cols - 1 - 2 * skip, 1)
		if k - 1 != dcol and k != dcol:
			var at := fc + a * (size_u * 0.5 - float(k) * pitch) + Vector3(0.0, bottom + storefront + floor_h * 0.80, 0.0)
			_condenser(acc, at, a, n)

	# --- The storefront: goosenecks over the boards, shutter housings, thresholds -----------
	if shops and storefront > 0.0 and span >= 1.0:
		var span_i := maxi(int(span + 0.5), 1)
		var runs := int(float(cols) / float(span_i))
		var shop_w := float(span_i) * pitch
		for run in runs:
			var key := b.shop_key(face_id, run)
			var lobby := Building.shop_is_lobby(key, run, runs, maxf(b.height, top - bottom))
			var u0 := float(run * span_i) * pitch
			if not lobby and Building.shop_byte(key, SALT_GOOSE) < GOOSE_BYTE and shop_w >= 2.6:
				var lxs: Array = [0.25, 0.75] if shop_w > 6.0 else [0.5]
				for lx: float in lxs:
					var along := size_u * 0.5 - (u0 + lx * shop_w)
					if absf(along) < half - 0.3:
						_gooseneck(acc, fc + a * along + Vector3(0.0, bottom + 0.93 * storefront, 0.0), a, n,
							LAMP_PAINTS[Building.shop_byte(key, 48) % LAMP_PAINTS.size()])
			# A roll-down shutter's housing and rails (the shader pulls it at night on these shops).
			if not covered and not lobby and Building.shop_byte(key, 8) < 140 and Building.shop_byte(key, 26) >= 90:
				var lo := maxf(size_u * 0.5 - (u0 + shop_w), -half) + 0.30
				var hi := minf(size_u * 0.5 - u0, half) - 0.30
				if hi - lo > 1.2:
					_shutter_housing(acc, fc + a * ((lo + hi) * 0.5) + Vector3(0.0, bottom, 0.0), a, n, hi - lo, storefront)
			# The threshold at the shop's door, unless it is a recessed entry (the shader traces that).
			var door_i := ShopfrontKit.door_index(key, span_i)
			var dc := run * span_i + door_i
			# Not on masonry: its plinth band runs across the door's foot.
			if not masonry and not ShopfrontKit.recessed(key) and dc >= skip and dc < cols - skip:
				var along := size_u * 0.5 - (float(dc) + 0.5) * pitch
				acc.box(Transform3D(Basis(a, Vector3.UP, n), fc + a * along + Vector3(0.0, bottom + 0.018, 0.0) + n * 0.17),
					Vector3(2.0 * ShopfrontKit.GLASS_HALF * pitch, 0.036, 0.34), K_STONE,
					[Color(0.55, 0.53, 0.50), Color(0.30, 0.31, 0.32), Color(0.62, 0.50, 0.40)][Building.shop_byte(key, 49) % 3])


## Builds the building's StreetDress from what face() gathered: one mesh, one draw, no collision.
static func commit(b: Building) -> void:
	if not b.has_meta("fs_acc"):
		return
	var acc: Acc = b.get_meta("fs_acc")
	b.remove_meta("fs_acc")
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
	mi.name = "StreetDress"
	mi.mesh = mesh
	mi.material_override = material()
	mi.visibility_range_end = PROPS_DISTANCE + b.footprint.length() * 0.5
	mi.visibility_range_end_margin = 10.0
	mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	b.add_child(mi)


# --- The pieces (all in the wall's frame: `a` along it, `n` out of it, `at` on the face) ------

## The steps up to a door whose threshold is `sill` over the pavement (one step at the pavement when
## it is 0): treads 30 cm deep, the top one level with the threshold, each with a steel nosing.
static func _step(acc: Acc, at: Vector3, a: Vector3, n: Vector3, width: float, sill: float) -> void:
	var w := Basis(a, Vector3.UP, n)
	var steps := maxi(ceili(sill / 0.17), 1)
	var rise := maxf(sill, 0.15) / float(steps)
	for k in steps:
		# Step k from the top: its tread at sill - k * rise, reaching (k + 1) treads out from the wall.
		var top := maxf(sill, 0.15) - float(k) * rise
		var depth := 0.30 * float(k + 1) + 0.12
		acc.box(Transform3D(w, at + Vector3(0.0, top * 0.5, 0.0) + n * (depth * 0.5)), Vector3(width + 0.1 * float(k), top, depth), K_CONCRETE, Color(0.55, 0.54, 0.51))
		acc.box(Transform3D(w, at + Vector3(0.0, top - 0.002, 0.0) + n * (depth - 0.015)), Vector3(width + 0.1 * float(k), 0.006, 0.03), K_GALV, Color.WHITE)


static func _door_lamp(acc: Acc, at: Vector3, a: Vector3, n: Vector3, kind: int, lit: bool, paint: Color) -> void:
	var w := Basis(a, Vector3.UP, n)
	var lamp_col := LAMP_COOL if kind == 2 else LAMP_WARM
	var l := 1.0 if lit else 0.0
	if kind == 0:
		# A caged bulkhead: a back plate, the oval lens, three bars over it.
		acc.box(Transform3D(w, at + n * 0.015), Vector3(0.26, 0.16, 0.03), K_PAINT, paint)
		acc.box(Transform3D(w, at + n * 0.06), Vector3(0.2, 0.11, 0.06), K_LENS, lamp_col, l)
		for k in 3:
			var y := (float(k) - 1.0) * 0.04
			acc.box(Transform3D(w, at + n * 0.095 + Vector3(0.0, y, 0.0)), Vector3(0.22, 0.008, 0.012), K_PAINT, paint)
	elif kind == 1:
		# A gooseneck barn light: a wall plate, the arm out and over, the shade looking down.
		acc.disc(at + n * 0.012, n, 0.07, K_PAINT, paint)
		var p0 := at + n * 0.01
		var p1 := at + n * 0.12 + Vector3(0.0, 0.10, 0.0)
		var p2 := at + n * 0.28 + Vector3(0.0, 0.12, 0.0)
		acc.tube(p0, p1, 0.013, K_PAINT, paint)
		acc.tube(p1, p2, 0.013, K_PAINT, paint)
		_shade(acc, at + n * 0.32 + Vector3(0.0, 0.02, 0.0), 0.14, 0.10, paint, lamp_col, l)
	else:
		# An LED wall pack: a sloped box with its lens on the underside.
		acc.box(Transform3D(w, at + n * 0.08), Vector3(0.30, 0.20, 0.16), K_PAINT, Color(0.16, 0.13, 0.10))
		acc.quad(at + n * 0.02 + a * -0.13 + Vector3(0.0, -0.101, 0.0), at + n * 0.02 + a * 0.13 + Vector3(0.0, -0.101, 0.0),
			at + n * 0.15 + a * 0.13 + Vector3(0.0, -0.101, 0.0), at + n * 0.15 + a * -0.13 + Vector3(0.0, -0.101, 0.0),
			Vector3.DOWN, K_LENS, lamp_col, Vector2.ZERO, Vector2.ONE, l)


## A conical shade opening downward at `c` (its rim), `r` wide, `h` tall, and its lens.
static func _shade(acc: Acc, c: Vector3, r: float, h: float, paint: Color, lamp_col: Color, lit: float) -> void:
	var segs := 10
	var apex := c + Vector3(0.0, h, 0.0)
	for k in segs:
		var t0 := TAU * float(k) / float(segs)
		var t1 := TAU * float(k + 1) / float(segs)
		var d0 := Vector3(cos(t0), 0.0, sin(t0))
		var d1 := Vector3(cos(t1), 0.0, sin(t1))
		var p0 := c + d0 * r
		var p1 := c + d1 * r
		var nm := ((d0 + d1).normalized() * h + Vector3(0.0, r, 0.0)).normalized()
		acc.quad(apex, p0, p1, apex, nm, K_PAINT, paint, Vector2.ZERO, Vector2(r, h))
		# The inside, seen from below.
		acc.quad(apex, p1, p0, apex, -nm, K_PAINT, paint.lightened(0.5), Vector2.ZERO, Vector2(r, h))
	acc.disc(c + Vector3(0.0, 0.02, 0.0), Vector3.DOWN, r * 0.5, K_LENS, lamp_col, lit)


static func _grille(acc: Acc, at: Vector3, a: Vector3, n: Vector3, w: float, h: float, iron: Color) -> void:
	var b := Basis(a, Vector3.UP, n)
	var z := n * 0.12
	# The frame: four flat bars, with tabs back to the wall at the corners.
	acc.box(Transform3D(b, at + z + Vector3(0.0, h * 0.5, 0.0)), Vector3(w, 0.03, 0.012), K_IRON, iron)
	acc.box(Transform3D(b, at + z - Vector3(0.0, h * 0.5, 0.0)), Vector3(w, 0.03, 0.012), K_IRON, iron)
	acc.box(Transform3D(b, at + z + a * (w * 0.5)), Vector3(0.03, h, 0.012), K_IRON, iron)
	acc.box(Transform3D(b, at + z - a * (w * 0.5)), Vector3(0.03, h, 0.012), K_IRON, iron)
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			acc.box(Transform3D(b, at + n * 0.06 + a * (sx * w * 0.5) + Vector3(0.0, sy * h * 0.5, 0.0)), Vector3(0.03, 0.03, 0.12), K_IRON, iron, 0.0, false)
	# Bars every 11 cm, two flats across them.
	var bars := maxi(int(w / 0.11), 2)
	for k in range(1, bars):
		var x := -w * 0.5 + w * float(k) / float(bars)
		acc.tube(at + z + a * x + Vector3(0.0, -h * 0.5, 0.0), at + z + a * x + Vector3(0.0, h * 0.5, 0.0), 0.007, K_IRON, iron, 4)
	for f: float in [-1.0 / 6.0, 1.0 / 6.0]:
		acc.box(Transform3D(b, at + z + Vector3(0.0, h * f, 0.0) + n * 0.002), Vector3(w, 0.028, 0.008), K_IRON, iron)


static func _downpipe(acc: Acc, at: Vector3, a: Vector3, n: Vector3, y0: float, y1: float, to_wall: bool, square: bool, kind: int, paint: Color) -> void:
	var b := Basis(a, Vector3.UP, n)
	var off := 0.075
	var r := 0.045
	var top := at + Vector3(0.0, y1, 0.0) + n * off
	var foot := at + Vector3(0.0, y0, 0.0) + n * off
	if square:
		acc.box(Transform3D(b, (top + foot) * 0.5), Vector3(0.10, y1 - y0, 0.075), kind, paint)
	else:
		acc.tube(foot, top, r, kind, paint, 8)
	# The hopper head at the top, and the scupper through the wall into it.
	acc.box(Transform3D(b, top + Vector3(0.0, 0.14, 0.0) + n * 0.02), Vector3(0.30, 0.24, 0.22), kind, paint)
	acc.box(Transform3D(b, top + Vector3(0.0, 0.30, 0.0) - n * 0.02), Vector3(0.14, 0.08, 0.18), kind, paint)
	# Brackets every 1.8 m.
	var y := y0 + 0.4
	while y < y1 - 0.2:
		acc.box(Transform3D(b, at + Vector3(0.0, y, 0.0) + n * 0.04), Vector3(0.14, 0.035, 0.08), kind, paint)
		y += 1.8
	if to_wall:
		# Over a shopfront the pipe turns back into the wall above the band.
		acc.tube(foot, at + Vector3(0.0, y0 - 0.12, 0.0) + n * 0.005, r, kind, paint, 8)
	else:
		# A shoe kicking the water out over the pavement.
		var tip := foot + n * 0.16 + Vector3(0.0, -0.12, 0.0)
		acc.tube(foot, tip, r, kind, paint, 8)


static func _meter_on_pier(acc: Acc, at: Vector3, a: Vector3, n: Vector3, storefront: float, paint: Color, face: float) -> void:
	var b := Basis(a, Vector3.UP, n)
	acc.box(Transform3D(b, at + Vector3(0.0, 1.42, 0.0) + n * (face + 0.07)), Vector3(0.34, 0.50, 0.14), K_PAINT, paint)
	acc.disc(at + Vector3(0.0, 1.48, 0.0) + n * (face + 0.15), n, 0.065, K_GLASS, Color.BLACK)
	# Conduit up to the band over the shopfront, and down into the pavement.
	var c := at + n * (face + 0.03) + a * 0.10
	acc.tube(c + Vector3(0.0, 1.67, 0.0), c + Vector3(0.0, storefront - 0.15, 0.0), 0.014, K_GALV, Color.WHITE)
	acc.tube(c + Vector3(0.0, 0.0, 0.0), c + Vector3(0.0, 1.17, 0.0), 0.016, K_GALV, Color.WHITE)


static func _panel_cluster(acc: Acc, at: Vector3, a: Vector3, n: Vector3, width: float, floor_h: float, paint: Color) -> void:
	var b := Basis(a, Vector3.UP, n)
	var w := maxf(width, 0.4)
	# A main panel and a meter box beside it, a junction box higher up.
	acc.box(Transform3D(b, at + Vector3(0.0, 1.30, 0.0) + n * 0.09 - a * (w * 0.22)), Vector3(w * 0.52, 0.72, 0.18), K_PAINT, paint)
	acc.box(Transform3D(b, at + Vector3(0.0, 1.38, 0.0) + n * 0.07 + a * (w * 0.28)), Vector3(w * 0.36, 0.42, 0.14), K_PAINT, paint.darkened(0.08))
	acc.disc(at + Vector3(0.0, 1.43, 0.0) + n * 0.15 + a * (w * 0.28), n, 0.06, K_GLASS, Color.BLACK)
	var jb := at + Vector3(0.0, minf(floor_h - 0.25, 3.2), 0.0)
	acc.box(Transform3D(b, jb + n * 0.05), Vector3(0.16, 0.16, 0.10), K_PAINT, paint)
	# Conduit: from the panel up to the junction box and on into the wall, and down to the ground.
	var c := at + n * 0.035 - a * (w * 0.22)
	acc.tube(c + Vector3(0.0, 1.66, 0.0), Vector3(c.x, jb.y - 0.08, c.z), 0.014, K_GALV, Color.WHITE)
	acc.tube(Vector3(c.x, jb.y - 0.08, c.z), jb + n * 0.035 - a * 0.08, 0.014, K_GALV, Color.WHITE)
	acc.tube(c + Vector3(0.0, 0.0, 0.0), c + Vector3(0.0, 0.94, 0.0), 0.02, K_GALV, Color.WHITE)
	acc.tube(jb + n * 0.035 + a * 0.08, jb + n * 0.035 + a * 0.6 + Vector3(0.0, 0.05, 0.0), 0.011, K_RUBBER, Color.BLACK)


static func _condenser(acc: Acc, at: Vector3, a: Vector3, n: Vector3) -> void:
	var b := Basis(a, Vector3.UP, n)
	var out := 0.06
	var body := at + n * (out + 0.16)
	acc.box(Transform3D(b, body), Vector3(0.80, 0.58, 0.30), K_PAINT, Color(0.82, 0.82, 0.78))
	# The fan grille on its front.
	var g := body + n * 0.152 + a * 0.08
	acc.quad(g - a * 0.24 - Vector3(0.0, 0.24, 0.0), g + a * 0.24 - Vector3(0.0, 0.24, 0.0),
		g + a * 0.24 + Vector3(0.0, 0.24, 0.0), g - a * 0.24 + Vector3(0.0, 0.24, 0.0), n, K_FAN, Color(0.5, 0.5, 0.5))
	# Two angle brackets under it, and their braces back to the wall.
	for sx: float in [-0.3, 0.3]:
		var base := at + a * sx + Vector3(0.0, -0.30, 0.0)
		acc.box(Transform3D(b, base + n * 0.22), Vector3(0.04, 0.04, 0.44), K_GALV, Color.WHITE)
		acc.tube(base + n * 0.38, at + a * sx + Vector3(0.0, -0.62, 0.0) + n * 0.01, 0.012, K_GALV, Color.WHITE, 4)
	# The line set: two copper pipes in black insulation, down and into the wall.
	var s := body - a * 0.40 + Vector3(0.0, -0.12, 0.0)
	acc.tube(s, s - a * 0.06, 0.012, K_COPPER, Color.WHITE)
	acc.tube(s - a * 0.06, s - a * 0.06 + Vector3(0.0, -0.4, 0.0), 0.016, K_RUBBER, Color.BLACK)
	acc.tube(s - a * 0.06 + Vector3(0.0, -0.4, 0.0), at - a * 0.46 + Vector3(0.0, -0.52, 0.0), 0.016, K_RUBBER, Color.BLACK)


static func _gooseneck(acc: Acc, at: Vector3, a: Vector3, n: Vector3, paint: Color) -> void:
	# From a plate just over the board, up and out over it, the shade looking down at it.
	var p0 := at + Vector3(0.0, 0.10, 0.0) + n * 0.01
	acc.disc(p0 + n * 0.005, n, 0.05, K_PAINT, paint)
	var p1 := at + Vector3(0.0, 0.32, 0.0) + n * 0.18
	var p2 := at + Vector3(0.0, 0.38, 0.0) + n * 0.42
	var p3 := at + Vector3(0.0, 0.30, 0.0) + n * 0.58
	acc.tube(p0, p1, 0.012, K_PAINT, paint)
	acc.tube(p1, p2, 0.012, K_PAINT, paint)
	acc.tube(p2, p3, 0.012, K_PAINT, paint)
	_shade(acc, p3 + Vector3(0.0, -0.12, 0.0), 0.13, 0.11, paint, LAMP_WARM, 1.0)


static func _shutter_housing(acc: Acc, at: Vector3, a: Vector3, n: Vector3, width: float, storefront: float) -> void:
	var b := Basis(a, Vector3.UP, n)
	var y := storefront * ShopfrontKit.GLASS_TOP + 0.10
	var steel := Color(0.48, 0.49, 0.49)
	acc.box(Transform3D(b, at + Vector3(0.0, y, 0.0) + n * 0.13), Vector3(width, 0.22, 0.26), K_GALV, steel)
	# The guide rails down either side, to the pavement.
	for s: float in [-0.5, 0.5]:
		acc.box(Transform3D(b, at + a * (width * s) + Vector3(0.0, y * 0.5, 0.0) + n * 0.035), Vector3(0.05, y, 0.07), K_GALV, steel)
	# The lock box at the foot of the middle.
	acc.box(Transform3D(b, at + Vector3(0.0, 0.10, 0.0) + n * 0.04), Vector3(0.12, 0.08, 0.06), K_PAINT, Color(0.08, 0.08, 0.08))
