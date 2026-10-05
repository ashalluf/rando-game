class_name CemeteryKit
extends RefCounted
## The memorial park's small stonework, built in code at real size (Cemetery, CemeteryBuild): flat
## bronze-on-granite lawn markers (with and without a vase of flowers), upright headstones (a
## granite tablet with a rounded top, a gothic one, a slant marker, an old marble tablet, a marble
## cross), the older monuments (an obelisk, a column carrying an urn, a family monument on its
## base, a family plot's coping) - each ONE mesh on shaders/cemetery_stone.gdshader, the surface
## kind in the vertex alpha (Cemetery's shader header has the codes), UV in metres on each face
## from its centre, so the lettering and the plaque's border land where they belong.
##
## Every mesh stands on y 0 (the turf) facing +Z (its lettered face), origin on its foot's centre.

const K_POLISH := 0
const K_SAWN := 1
const K_MARBLE := 2
const K_BRONZE := 3
const K_ENGRAVED := 4
const K_FLOWERS := 5
const K_GLASS := 6
const K_IRON := 7
const K_PLAIN := 8

const MESHES := ["flat", "flat_vase", "tablet", "gothic", "slant", "marble", "cross", "obelisk", "column", "family", "coping"]

static var _cache: Dictionary = {}
static var _material: ShaderMaterial = null


static func material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = load("res://shaders/cemetery_stone.gdshader")
	return _material


## The vertex colour for a face of kind `k` (rgb white: the instance colour is the stone's).
static func kc(k: int, rgb: Color = Color.WHITE) -> Color:
	return Color(rgb.r, rgb.g, rgb.b, (float(k) + 0.5) / 16.0)


static func mesh(key: String) -> ArrayMesh:
	if _cache.has(key):
		return _cache[key]
	var g := Acc.new()
	match key:
		"flat":
			_flat(g, false)
		"flat_vase":
			_flat(g, true)
		"tablet":
			_tablet(g, 0.76, 0.72, 0.16, 0.30, false, K_ENGRAVED, K_POLISH, K_SAWN)
		"gothic":
			_tablet(g, 0.62, 0.82, 0.14, 0.34, true, K_ENGRAVED, K_POLISH, K_SAWN)
		"slant":
			_slant(g)
		"marble":
			_tablet(g, 0.56, 0.78, 0.08, 0.26, false, K_MARBLE, K_MARBLE, K_MARBLE, false)
		"cross":
			_cross(g)
		"obelisk":
			_obelisk(g)
		"column":
			_column(g)
		"family":
			_family(g)
		"coping":
			_coping(g)
	var m := g.commit(material())
	_cache[key] = m
	return m


# --- The pieces ---------------------------------------------------------------------------------

## A flat lawn marker: a honed granite slab flush with the turf carrying a bronze plaque, and
## optionally a bronze vase at its head holding flowers.
static func _flat(g: Acc, vase: bool) -> void:
	g.box(Vector3(0.0, -0.04, 0.0), Vector3(0.70, 0.10, 0.40), [K_SAWN, K_SAWN, K_SAWN, K_SAWN, K_SAWN, -1], true)
	# The plaque: its top face lettered (UV from its centre: u along x, v along -z, i.e. read from
	# the foot of the grave).
	var top := 0.026
	var hx := 0.25
	var hz := 0.135
	var c := kc(K_BRONZE)
	g.quad(Vector3(-hx, top, hz), Vector3(hx, top, hz), Vector3(hx, top, -hz), Vector3(-hx, top, -hz), Vector3.UP,
		Vector2(-hx, -hz), Vector2(hx, -hz), Vector2(hx, hz), Vector2(-hx, hz), c)
	for s: Array in [[Vector3(0, 0, 1), hx, hz], [Vector3(0, 0, -1), hx, hz], [Vector3(1, 0, 0), hz, hx], [Vector3(-1, 0, 0), hz, hx]]:
		var n: Vector3 = s[0]
		var side := Vector3(n.z, 0.0, -n.x)
		var w: float = s[1]
		var o := n * float(s[2])
		var y0 := 0.008
		g.quad(o - side * w + Vector3(0, y0, 0), o + side * w + Vector3(0, y0, 0), o + side * w + Vector3(0, top, 0), o - side * w + Vector3(0, top, 0),
			n, Vector2(0.3, 0.3), Vector2(0.3, 0.3), Vector2(0.3, 0.3), Vector2(0.3, 0.3), c)
	if vase:
		var at := Vector3(0.0, 0.0, -0.13)
		g.lathe(at, [Vector2(0.045, 0.02), Vector2(0.055, 0.06), Vector2(0.04, 0.14), Vector2(0.05, 0.22), Vector2(0.058, 0.25)], 8, kc(K_BRONZE), false)
		# Flowers: a loose bunch of small blooms over the rim (the colour from INSTANCE_CUSTOM.a).
		var rng := RandomNumberGenerator.new()
		rng.seed = 4711
		for i in 9:
			var p := at + Vector3(rng.randf_range(-0.09, 0.09), 0.27 + rng.randf_range(0.0, 0.12), rng.randf_range(-0.08, 0.08))
			g.blob(p, rng.randf_range(0.028, 0.045), kc(K_FLOWERS))
		for i in 6:
			var p := at + Vector3(rng.randf_range(-0.07, 0.07), 0.24 + rng.randf_range(0.0, 0.06), rng.randf_range(-0.07, 0.07))
			g.blob(p, 0.035, kc(K_PLAIN, Color(0.16, 0.30, 0.10)))


## An upright tablet on its base: `w` wide, `h` tall to the top of the shoulders, `t` thick; a
## round (or pointed, `gothic`) top of radius w/2; the front face lettered.
static func _tablet(g: Acc, w: float, h: float, t: float, base_h: float, gothic: bool, front_k: int, back_k: int, side_k: int, base: bool = true) -> void:
	var y0 := 0.0
	if base:
		g.box(Vector3(0.0, base_h * 0.5 - 0.05, 0.0), Vector3(w + 0.22, base_h + 0.1, t + 0.22), [K_SAWN, K_SAWN, K_SAWN, K_SAWN, K_POLISH, -1])
		y0 = base_h
	# The outline (x, y) round the face, bottom edge first, counter-clockwise from the front.
	var outline := PackedVector2Array()
	var hw := w * 0.5
	outline.append(Vector2(-hw, 0.0))
	outline.append(Vector2(hw, 0.0))
	outline.append(Vector2(hw, h))
	var segs := 10
	if gothic:
		# An equilateral pointed arch, a little flattened: the right arc centred on the left
		# shoulder, then the left arc centred on the right one, meeting at the apex.
		for i in range(1, segs + 1):
			var ang := PI / 3.0 * float(i) / float(segs)
			outline.append(Vector2(-hw + w * cos(ang), h + w * sin(ang) * 0.6))
		for i in range(1, segs):
			var ang := PI * 2.0 / 3.0 + PI / 3.0 * float(i) / float(segs)
			outline.append(Vector2(hw + w * cos(ang), h + w * sin(ang) * 0.6))
	else:
		for i in range(1, segs):
			var a := PI * float(i) / float(segs)
			outline.append(Vector2(cos(a) * hw, h + sin(a) * hw * 0.55))
	outline.append(Vector2(-hw, h))
	g.extrude(outline, y0, t, front_k, back_k, side_k, h * 0.45)


## A slant marker: a wedge, its sloped face lettered toward the foot.
static func _slant(g: Acc) -> void:
	g.box(Vector3(0.0, 0.05, 0.0), Vector3(0.95, 0.20, 0.55), [K_SAWN, K_SAWN, K_SAWN, K_SAWN, K_POLISH, -1])
	var w := 0.38
	var y0 := 0.15
	var hb := 0.42
	var hf := 0.22
	var zb := -0.16
	var zf := 0.16
	var a := Vector3(-w, y0 + hf, zf)
	var b := Vector3(w, y0 + hf, zf)
	var c := Vector3(w, y0 + hb, zb)
	var d := Vector3(-w, y0 + hb, zb)
	var slope_n := (b - a).cross(d - a).normalized()
	if slope_n.y < 0.0:
		slope_n = -slope_n
	var sl := a.distance_to(d)
	g.quad(a, b, c, d, slope_n, Vector2(-w, -sl * 0.5), Vector2(w, -sl * 0.5), Vector2(w, sl * 0.5), Vector2(-w, sl * 0.5), kc(K_ENGRAVED))
	var kf := kc(K_SAWN)
	g.quad(Vector3(-w, y0, zf), Vector3(w, y0, zf), b, a, Vector3(0, 0, 1), Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1), kf)
	g.quad(Vector3(-w, y0, zb), Vector3(w, y0, zb), c, d, Vector3(0, 0, -1), Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1), kc(K_POLISH))
	for sx: float in [-1.0, 1.0]:
		g.quad(Vector3(sx * w, y0, zf), Vector3(sx * w, y0 + hf, zf), Vector3(sx * w, y0 + hb, zb), Vector3(sx * w, y0, zb), Vector3(sx, 0, 0),
			Vector2(0, 0), Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), kf)


## A marble cross on a stepped base.
static func _cross(g: Acc) -> void:
	var mk := [K_MARBLE, K_MARBLE, K_MARBLE, K_MARBLE, K_MARBLE, -1]
	g.box(Vector3(0.0, 0.1, 0.0), Vector3(0.75, 0.3, 0.5), mk)
	g.box(Vector3(0.0, 0.33, 0.0), Vector3(0.55, 0.16, 0.36), mk)
	g.box(Vector3(0.0, 0.41 + 0.6, 0.0), Vector3(0.14, 1.2, 0.12), mk)
	g.box(Vector3(0.0, 0.41 + 0.86, 0.0), Vector3(0.62, 0.13, 0.12), mk)


## An obelisk: plinth, die with the family's name, a tapering shaft and a pyramidion. 3.4 m.
static func _obelisk(g: Acc) -> void:
	g.box(Vector3(0.0, 0.1, 0.0), Vector3(1.3, 0.3, 1.3), [K_SAWN, K_SAWN, K_SAWN, K_SAWN, K_POLISH, -1])
	g.box(Vector3(0.0, 0.33, 0.0), Vector3(1.0, 0.16, 1.0), [K_POLISH, K_POLISH, K_POLISH, K_POLISH, K_POLISH, -1])
	g.box(Vector3(0.0, 0.41 + 0.4, 0.0), Vector3(0.8, 0.8, 0.8), [K_ENGRAVED, K_POLISH, K_POLISH, K_POLISH, K_POLISH, -1])
	g.frustum(Vector3(0.0, 1.21, 0.0), Vector2(0.56, 0.56), Vector2(0.36, 0.36), 1.9, K_POLISH)
	g.frustum(Vector3(0.0, 3.11, 0.0), Vector2(0.36, 0.36), Vector2(0.0, 0.0), 0.3, K_POLISH)


## A column broken off or carrying a draped urn, on a die. 2.7 m. Marble.
static func _column(g: Acc) -> void:
	var mk := [K_MARBLE, K_MARBLE, K_MARBLE, K_MARBLE, K_MARBLE, -1]
	g.box(Vector3(0.0, 0.1, 0.0), Vector3(1.0, 0.3, 1.0), mk)
	g.box(Vector3(0.0, 0.25 + 0.35, 0.0), Vector3(0.7, 0.7, 0.7), mk)
	g.box(Vector3(0.0, 0.95 + 0.04, 0.0), Vector3(0.82, 0.08, 0.82), mk)
	g.lathe(Vector3(0.0, 1.03, 0.0), [Vector2(0.24, 0.0), Vector2(0.24, 0.06), Vector2(0.2, 0.1), Vector2(0.19, 1.2), Vector2(0.23, 1.26), Vector2(0.23, 1.3)], 14, kc(K_MARBLE), true)
	g.lathe(Vector3(0.0, 2.33, 0.0), [Vector2(0.08, 0.0), Vector2(0.06, 0.06), Vector2(0.16, 0.16), Vector2(0.19, 0.3), Vector2(0.12, 0.42), Vector2(0.08, 0.46), Vector2(0.1, 0.5), Vector2(0.0, 0.56)], 12, kc(K_MARBLE), true)


## A family monument: a wide polished die with the family name on a rock-pitched base.
static func _family(g: Acc) -> void:
	g.box(Vector3(0.0, 0.12, 0.0), Vector3(2.1, 0.34, 0.75), [K_SAWN, K_SAWN, K_SAWN, K_SAWN, K_SAWN, -1])
	g.box(Vector3(0.0, 0.29 + 0.5, 0.0), Vector3(1.7, 1.0, 0.4), [K_ENGRAVED, K_POLISH, K_SAWN, K_SAWN, K_POLISH, -1])
	# A shallow serpentine cap.
	g.frustum(Vector3(0.0, 1.29, 0.0), Vector2(1.7, 0.4), Vector2(1.3, 0.28), 0.18, K_POLISH)


## A family plot's coping: a low granite kerb round a 3.6 x 2.8 m plot, corner posts, the name
## on a step at the front.
static func _coping(g: Acc) -> void:
	var sk := [K_SAWN, K_SAWN, K_SAWN, K_SAWN, K_POLISH, -1]
	var hx := 1.8
	var hz := 1.4
	g.box(Vector3(0.0, 0.05, hz), Vector3(hx * 2.0, 0.2, 0.2), sk)
	g.box(Vector3(0.0, 0.05, -hz), Vector3(hx * 2.0, 0.2, 0.2), sk)
	g.box(Vector3(hx, 0.05, 0.0), Vector3(0.2, 0.2, hz * 2.0), sk)
	g.box(Vector3(-hx, 0.05, 0.0), Vector3(0.2, 0.2, hz * 2.0), sk)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			g.box(Vector3(sx * hx, 0.22, sz * hz), Vector3(0.3, 0.55, 0.3), [K_POLISH, K_POLISH, K_POLISH, K_POLISH, K_POLISH, -1])
			g.frustum(Vector3(sx * hx, 0.495, sz * hz), Vector2(0.3, 0.3), Vector2(0.0, 0.0), 0.12, K_POLISH)
	g.box(Vector3(0.0, 0.1, hz + 0.1), Vector3(1.2, 0.22, 0.25), [K_ENGRAVED, K_SAWN, K_SAWN, K_SAWN, K_POLISH, -1])


## An Italian cypress of unit height (scale it to the tree's height): a short trunk and a lumpy
## flame of foliage up to a point, its widest a third of the way up, radius 0.085 of the height.
## Rings of 14 round 26 rows, each vertex pushed out or in by a hash of its row and column (clumps
## a metre or so across on a 10 m tree), smooth normals. On shaders/cemetery_cypress.gdshader.
static var _cypress: ArrayMesh = null
static var _cypress_far: ArrayMesh = null


static func cypress(far: bool = false) -> ArrayMesh:
	if far and _cypress_far != null:
		return _cypress_far
	if not far and _cypress != null:
		return _cypress
	var segs := 8 if far else 14
	var rows := 10 if far else 26
	var g := Acc.new()
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/cemetery_cypress.gdshader")
	var bark := Color(0, 0, 0, 1)
	var leaf := Color(1, 0, 0, 1)
	g.lathe(Vector3.ZERO, [Vector2(0.012, 0.0), Vector2(0.010, 0.06)], 6, bark, false)
	var ring := func(j: int) -> Array:
		var t := float(j) / float(rows)
		var y := 0.04 + 0.96 * t
		var prof := pow(sin(PI * clampf(t * 0.92 + 0.04, 0.0, 1.0)), 0.75) * (1.0 - 0.35 * t)
		var out: Array = []
		for i in segs:
			var a := TAU * float(i) / float(segs)
			var lump := 1.0 + 0.22 * (float(absi(hash([j, i, 77])) % 1000) / 1000.0 - 0.5) * 2.0
			var r := 0.085 * prof * (lump if j > 0 and j < rows else 1.0)
			out.append(Vector3(cos(a) * r, y, sin(a) * r))
		return out
	var rings: Array = []
	for j in rows + 1:
		rings.append(ring.call(j))
	for j in rows:
		var r0: Array = rings[j]
		var r1: Array = rings[j + 1]
		for i in segs:
			var a: Vector3 = r0[i]
			var b: Vector3 = r0[(i + 1) % segs]
			var c: Vector3 = r1[(i + 1) % segs]
			var d: Vector3 = r1[i]
			var na := Vector3(a.x, 0.25, a.z).normalized()
			var nb := Vector3(b.x, 0.25, b.z).normalized()
			var nc := Vector3(c.x, 0.25, c.z).normalized()
			var nd := Vector3(d.x, 0.25, d.z).normalized()
			var want := Vector3((a.x + b.x) * 0.5, 0.0, (a.z + b.z) * 0.5)
			g.tri(a, b, c, want, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, leaf, na, nb, nc)
			g.tri(a, c, d, want, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, leaf, na, nc, nd)
	var m := g.commit(mat)
	if far:
		_cypress_far = m
	else:
		_cypress = m
	return m


# --- Geometry accumulator ---------------------------------------------------------------------

class Acc:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var uv := PackedVector2Array()
	var col := PackedColorArray()

	## One triangle facing `want`: the winding is fixed to match (LandmarkGeo's rule).
	func tri(a: Vector3, b: Vector3, c: Vector3, want: Vector3, ua: Vector2, ub: Vector2, uc: Vector2, color: Color,
			na: Vector3 = Vector3.ZERO, nb: Vector3 = Vector3.ZERO, nc: Vector3 = Vector3.ZERO) -> void:
		var flat := (c - a).cross(b - a)
		if flat.length_squared() < 1e-14:
			return
		if flat.dot(want) < 0.0:
			var t := b
			b = c
			c = t
			var tu := ub
			ub = uc
			uc = tu
			var tn := nb
			nb = nc
			nc = tn
			flat = -flat
		if na == Vector3.ZERO:
			na = flat.normalized()
			nb = na
			nc = na
		v.append_array([a, b, c])
		n.append_array([na, nb, nc])
		uv.append_array([ua, ub, uc])
		col.append_array([color, color, color])

	func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, want: Vector3, ua: Vector2, ub: Vector2, uc: Vector2, ud: Vector2, color: Color) -> void:
		tri(a, b, c, want, ua, ub, uc, color)
		tri(a, c, d, want, ua, uc, ud, color)

	## An axis-aligned box: kinds per face [+Z, -Z, +X, -X, top, bottom], -1 skips the face. UV
	## metres from each face's centre (u across, v up; the top's u along x, v along -z).
	func box(c: Vector3, s: Vector3, kinds: Array, skip_bottom: bool = true) -> void:
		var h := s * 0.5
		var faces := [[Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 1, 0), h.x, h.y, h.z],
			[Vector3(0, 0, -1), Vector3(-1, 0, 0), Vector3(0, 1, 0), h.x, h.y, h.z],
			[Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0), h.z, h.y, h.x],
			[Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0), h.z, h.y, h.x],
			[Vector3(0, 1, 0), Vector3(1, 0, 0), Vector3(0, 0, -1), h.x, h.z, h.y],
			[Vector3(0, -1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1), h.x, h.z, h.y]]
		for i in 6:
			var k: int = kinds[i] if i < kinds.size() else -1
			if k < 0 or (i == 5 and skip_bottom):
				continue
			var f: Array = faces[i]
			var nn: Vector3 = f[0]
			var ru: Vector3 = f[1]
			var rv: Vector3 = f[2]
			var wu: float = f[3]
			var wv: float = f[4]
			var o: Vector3 = c + nn * float(f[5])
			quad(o - ru * wu - rv * wv, o + ru * wu - rv * wv, o + ru * wu + rv * wv, o - ru * wu + rv * wv, nn,
				Vector2(-wu, -wv), Vector2(wu, -wv), Vector2(wu, wv), Vector2(-wu, wv), CemeteryKit.kc(k))

	## An outline in the XY plane (counter-clockwise, its bottom edge first along y = 0) extruded
	## `t` thick about z = 0, standing on y0: front (+Z), back, the rim. `v_mid` is the outline's
	## height the lettering centres on.
	func extrude(outline: PackedVector2Array, y0: float, t: float, kf: int, kb: int, ks: int, v_mid: float) -> void:
		var idx := Geometry2D.triangulate_polygon(outline)
		for side: float in [1.0, -1.0]:
			var k := kf if side > 0.0 else kb
			for i in range(0, idx.size(), 3):
				var a := outline[idx[i]]
				var b := outline[idx[i + 1]]
				var c := outline[idx[i + 2]]
				tri(Vector3(a.x, y0 + a.y, side * t * 0.5), Vector3(b.x, y0 + b.y, side * t * 0.5), Vector3(c.x, y0 + c.y, side * t * 0.5),
					Vector3(0, 0, side), Vector2(a.x * side, a.y - v_mid), Vector2(b.x * side, b.y - v_mid), Vector2(c.x * side, c.y - v_mid), CemeteryKit.kc(k))
		var cc := Vector2.ZERO
		for p in outline:
			cc += p
		cc /= float(outline.size())
		for i in outline.size():
			var a := outline[i]
			var b := outline[(i + 1) % outline.size()]
			var mid := (a + b) * 0.5
			var out := Vector3(mid.x - cc.x, mid.y - cc.y, 0.0)
			var e := b - a
			var nrm := Vector3(e.y, -e.x, 0.0).normalized()
			if nrm.dot(out) < 0.0:
				nrm = -nrm
			quad(Vector3(a.x, y0 + a.y, t * 0.5), Vector3(b.x, y0 + b.y, t * 0.5), Vector3(b.x, y0 + b.y, -t * 0.5), Vector3(a.x, y0 + a.y, -t * 0.5), nrm,
				Vector2(0, 0), Vector2(e.length(), 0), Vector2(e.length(), t), Vector2(0, t), CemeteryKit.kc(ks))

	## A tapering square shaft (or a pyramid when `top` is zero) from `base` up `h`.
	func frustum(base: Vector3, bot: Vector2, top: Vector2, h: float, k: int) -> void:
		var hb := bot * 0.5
		var ht := top * 0.5
		var corners := [Vector2(-1, 1), Vector2(1, 1), Vector2(1, -1), Vector2(-1, -1)]
		for i in 4:
			var c0: Vector2 = corners[i]
			var c1: Vector2 = corners[(i + 1) % 4]
			var a := base + Vector3(c0.x * hb.x, 0.0, c0.y * hb.y)
			var b := base + Vector3(c1.x * hb.x, 0.0, c1.y * hb.y)
			var c := base + Vector3(c1.x * ht.x, h, c1.y * ht.y)
			var d := base + Vector3(c0.x * ht.x, h, c0.y * ht.y)
			var mid := (c0 + c1) * 0.5
			var want := Vector3(mid.x, 0.3, mid.y)
			var w := a.distance_to(b) * 0.5
			var wt := d.distance_to(c) * 0.5
			# The die's lettering centres a third up the face.
			quad(a, b, c, d, want, Vector2(-w, -h * 0.33), Vector2(w, -h * 0.33), Vector2(wt, h * 0.67), Vector2(-wt, h * 0.67), CemeteryKit.kc(k))
		if top.x > 0.0:
			var y := base.y + h
			quad(base + Vector3(-ht.x, h, ht.y), base + Vector3(ht.x, h, ht.y), base + Vector3(ht.x, h, -ht.y), base + Vector3(-ht.x, h, -ht.y), Vector3.UP,
				Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1), CemeteryKit.kc(k))

	## A surface of revolution about the vertical through `base`: profile (radius, height) bottom up.
	func lathe(base: Vector3, profile: Array, segs: int, color: Color, cap_top: bool) -> void:
		for j in profile.size() - 1:
			var p0: Vector2 = profile[j]
			var p1: Vector2 = profile[j + 1]
			var slope := Vector2(p1.y - p0.y, -(p1.x - p0.x)).normalized()
			for i in segs:
				var a0 := TAU * float(i) / float(segs)
				var a1 := TAU * float(i + 1) / float(segs)
				var d0 := Vector3(cos(a0), 0.0, sin(a0))
				var d1 := Vector3(cos(a1), 0.0, sin(a1))
				var q0 := base + d0 * p0.x + Vector3(0, p0.y, 0)
				var q1 := base + d1 * p0.x + Vector3(0, p0.y, 0)
				var q2 := base + d1 * p1.x + Vector3(0, p1.y, 0)
				var q3 := base + d0 * p1.x + Vector3(0, p1.y, 0)
				var n0 := (d0 * slope.x + Vector3(0, slope.y, 0)).normalized()
				var n1 := (d1 * slope.x + Vector3(0, slope.y, 0)).normalized()
				var want := (d0 + d1) * 0.5 * slope.x + Vector3(0, slope.y, 0)
				var u0 := float(i) / float(segs)
				var u1 := float(i + 1) / float(segs)
				tri(q0, q1, q2, want, Vector2(u0, p0.y), Vector2(u1, p0.y), Vector2(u1, p1.y), color, n0, n1, n1)
				tri(q0, q2, q3, want, Vector2(u0, p0.y), Vector2(u1, p1.y), Vector2(u0, p1.y), color, n0, n1, n0)
		var last: Vector2 = profile[profile.size() - 1]
		if cap_top and last.x > 0.001:
			for i in segs:
				var a0 := TAU * float(i) / float(segs)
				var a1 := TAU * float(i + 1) / float(segs)
				var y := Vector3(0, last.y, 0)
				tri(base + y, base + y + Vector3(cos(a0), 0, sin(a0)) * last.x, base + y + Vector3(cos(a1), 0, sin(a1)) * last.x, Vector3.UP,
					Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, color)

	## A small octahedron (a bloom, a leaf), smooth-normalled.
	func blob(c: Vector3, r: float, color: Color) -> void:
		var ax := [Vector3(r, 0, 0), Vector3(0, r * 0.8, 0), Vector3(0, 0, r), Vector3(-r, 0, 0), Vector3(0, -r * 0.6, 0), Vector3(0, 0, -r)]
		var tris := [[0, 1, 2], [2, 1, 3], [3, 1, 5], [5, 1, 0], [0, 2, 4], [2, 3, 4], [3, 5, 4], [5, 0, 4]]
		for t: Array in tris:
			var a: Vector3 = ax[t[0]]
			var b: Vector3 = ax[t[1]]
			var d: Vector3 = ax[t[2]]
			tri(c + a, c + b, c + d, (a + b + d), Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, color, a.normalized(), b.normalized(), d.normalized())

	func commit(mat: Material) -> ArrayMesh:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = v
		arrays[Mesh.ARRAY_NORMAL] = n
		arrays[Mesh.ARRAY_TEX_UV] = uv
		arrays[Mesh.ARRAY_COLOR] = col
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		m.surface_set_material(0, mat)
		return m
