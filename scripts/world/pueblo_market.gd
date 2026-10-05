class_name PuebloMarket
extends RefCounted
## The marketplace lane's market, built in code at real size (PuebloLane lays it out): the puestos
## (timber stalls down the middle of the lane, back to back, each under a striped awning and hung
## with what it sells), their goods - folded and hanging sarapes, glazed and bare pottery, straw
## hats, leather, embroidered dresses, crepe-paper pinatas, candy in jars, silver - and the papel
## picado and bulb strings over the lane and the plaza.
##
## Everything goes into two accumulators (Acc): SOLID pieces on shaders/pueblo_market.gdshader
## (culled) and THIN ones seen from both sides on pueblo_market_thin.gdshader (papel picado,
## canvas, hanging cloth). What a face is rides in its vertex colour's alpha (K_*), its paint in
## the rgb (sRGB), a per-piece seed in UV2.x and its freedom in the wind in UV2.y; UV is metres on
## the face, or 0..1 over a paper flag (pueblo_market.gdshaderinc). Every roll is a hash of the
## seed it is handed, never an rng that lives longer than one piece.

## Kinds (pueblo_market.gdshaderinc): painted timber, natural timber, awning canvas, sarape, glazed
## pottery, terracotta, papel picado, bulb, wrought iron, straw, leather, embroidered cotton, glossy
## candy and toys, pinata crepe, lantern glass, silver.
enum { K_PAINT, K_WOOD, K_CANVAS, K_SARAPE, K_GLAZE, K_CLAY, K_PAPER, K_BULB, K_IRON, K_STRAW,
	K_LEATHER, K_EMBROID, K_GLOSSY, K_CREPE, K_GLOW, K_SILVER }

## What a stall sells.
enum Goods { SARAPES, POTTERY, PINATAS, HATS, DRESSES, CANDY, SILVER, LEATHER }
const GOODS_COUNT := 8

## A stall's size: frontage along the lane, depth into it, height to the eaves at the back (m).
const STALL_W := 2.4
const STALL_D := 1.9
const STALL_H := 2.55
## The awning's reach out over the aisle and its drop.
const AWNING_OUT := 0.85
const AWNING_DROP := 0.32
const COUNTER_H := 0.92
const COUNTER_D := 0.55

## Stall paint, sRGB: the blues, greens, reds and ochres the real puestos wear.
const STALL_PAINTS := [Color(0.12, 0.36, 0.55), Color(0.1, 0.45, 0.38), Color(0.62, 0.12, 0.1),
	Color(0.78, 0.55, 0.16), Color(0.36, 0.16, 0.3), Color(0.2, 0.42, 0.2), Color(0.86, 0.82, 0.72), Color(0.08, 0.22, 0.42)]
## Awning colours (the first stripe; the second is cream), sRGB.
const AWNING_COLORS := [Color(0.82, 0.1, 0.12), Color(0.1, 0.42, 0.22), Color(0.95, 0.5, 0.08),
	Color(0.12, 0.3, 0.7), Color(0.85, 0.18, 0.5), Color(0.92, 0.75, 0.12)]
## Papel picado, sRGB: the tissue colours.
const PAPER_COLORS := [Color(0.95, 0.15, 0.55), Color(0.99, 0.55, 0.08), Color(0.98, 0.85, 0.15),
	Color(0.35, 0.78, 0.2), Color(0.1, 0.7, 0.75), Color(0.18, 0.35, 0.9), Color(0.6, 0.25, 0.8),
	Color(0.92, 0.12, 0.12), Color(0.98, 0.97, 0.95)]
## A paper flag's size (m) and pitch along its string.
const FLAG_W := 0.32
const FLAG_H := 0.42
const FLAG_PITCH := 0.4

static var _solid_mat: ShaderMaterial
static var _thin_mat: ShaderMaterial


static func solid_material() -> ShaderMaterial:
	if _solid_mat == null:
		_solid_mat = ShaderMaterial.new()
		_solid_mat.shader = load("res://shaders/pueblo_market.gdshader")
	return _solid_mat


static func thin_material() -> ShaderMaterial:
	if _thin_mat == null:
		_thin_mat = ShaderMaterial.new()
		_thin_mat.shader = load("res://shaders/pueblo_market_thin.gdshader")
	return _thin_mat


## A hash of `parts` as 0..1.
static func h01(parts: Array) -> float:
	return float(hash(parts) & 0xffffff) / 16777216.0


# --- The accumulator ---------------------------------------------------------------------------------

## One mesh in the making: flat arrays, appended a triangle at a time, flat or smooth normals.
class Acc:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	## The paint and kind of what is being added (set before each piece).
	var col := Color.WHITE
	var kind := 0
	var sd := 0.0

	func set_look(paint: Color, k: int, s: float = 0.0) -> void:
		col = Color(paint.r, paint.g, paint.b, (float(k) + 0.5) / 16.0)
		kind = k
		sd = s

	func tris() -> int:
		return v.size() / 3

	## One triangle facing `want`; per-corner normals when given, else flat. f* the wind freedom.
	func tri(a: Vector3, b: Vector3, cc: Vector3, want: Vector3, ua: Vector2, ub: Vector2, uc: Vector2,
			na := Vector3.ZERO, nb := Vector3.ZERO, nc := Vector3.ZERO, fa := 0.0, fb := 0.0, fc := 0.0) -> void:
		var fn := (cc - a).cross(b - a)
		if fn.length_squared() < 1e-14:
			return
		if fn.dot(want) < 0.0:
			var t := b
			b = cc
			cc = t
			var tu := ub
			ub = uc
			uc = tu
			var tn := nb
			nb = nc
			nc = tn
			var tf := fb
			fb = fc
			fc = tf
		var flat := fn.normalized()
		if flat.dot(want) < 0.0:
			flat = -flat
		v.append(a)
		v.append(b)
		v.append(cc)
		n.append(na if na != Vector3.ZERO else flat)
		n.append(nb if nb != Vector3.ZERO else flat)
		n.append(nc if nc != Vector3.ZERO else flat)
		c.append(col)
		c.append(col)
		c.append(col)
		uv.append(ua)
		uv.append(ub)
		uv.append(uc)
		uv2.append(Vector2(sd, fa))
		uv2.append(Vector2(sd, fb))
		uv2.append(Vector2(sd, fc))

	func quad(a: Vector3, b: Vector3, cc: Vector3, d: Vector3, want: Vector3, ua: Vector2, ub: Vector2, uc: Vector2, ud: Vector2,
			fa := 0.0, fb := 0.0, fc := 0.0, fd := 0.0) -> void:
		tri(a, b, cc, want, ua, ub, uc, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, fa, fb, fc)
		tri(a, cc, d, want, ua, uc, ud, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, fa, fc, fd)

	## A box `size` centred at `xf.origin`, turned by xf.basis (rotation only). UV metres on each face.
	func box(xf: Transform3D, size: Vector3, bottom := false) -> void:
		var h := size * 0.5
		for f: Array in [[0, 1.0], [0, -1.0], [2, 1.0], [2, -1.0], [1, 1.0], [1, -1.0]]:
			var ax: int = f[0]
			var sg: float = f[1]
			if ax == 1 and sg < 0.0 and not bottom:
				continue
			var nl := Vector3.ZERO
			nl[ax] = sg
			var ua := 2 if ax == 0 else 0
			var va := 2 if ax == 1 else 1
			var r := Vector3.ZERO
			r[ua] = h[ua]
			var u := Vector3.ZERO
			u[va] = h[va]
			var o := nl * h[ax]
			var p0 := xf * (o - r - u)
			var p1 := xf * (o + r - u)
			var p2 := xf * (o + r + u)
			var p3 := xf * (o - r + u)
			var w := size[ua]
			var hh := size[va]
			quad(p0, p1, p2, p3, xf.basis * nl, Vector2(0, 0), Vector2(w, 0), Vector2(w, hh), Vector2(0, hh))

	## A surface of revolution about xf's Y axis: `prof` is [radius, height] from bottom to top.
	## Smooth normals; u round the circumference in metres, v up the profile in metres.
	func lathe(xf: Transform3D, prof: Array, segs: int) -> void:
		var vlen := [0.0]
		for i in range(1, prof.size()):
			vlen.append(float(vlen[i - 1]) + (prof[i] as Vector2).distance_to(prof[i - 1]))
		for i in prof.size() - 1:
			var a: Vector2 = prof[i]
			var b: Vector2 = prof[i + 1]
			var d := b - a
			# The profile's outward normal in (r, y).
			var pn := Vector2(d.y, -d.x).normalized()
			for j in segs:
				var t0 := TAU * float(j) / float(segs)
				var t1 := TAU * float(j + 1) / float(segs)
				var c0 := Vector3(cos(t0), 0, sin(t0))
				var c1 := Vector3(cos(t1), 0, sin(t1))
				var q0 := xf * (c0 * a.x + Vector3.UP * a.y)
				var q1 := xf * (c1 * a.x + Vector3.UP * a.y)
				var q2 := xf * (c1 * b.x + Vector3.UP * b.y)
				var q3 := xf * (c0 * b.x + Vector3.UP * b.y)
				var n0 := (xf.basis * (c0 * pn.x + Vector3.UP * pn.y)).normalized()
				var n1 := (xf.basis * (c1 * pn.x + Vector3.UP * pn.y)).normalized()
				var want := (n0 + n1)
				if want.length_squared() < 1e-6:
					want = xf.basis * Vector3.UP * signf(pn.y + 1e-4)
				var u0 := t0 * maxf(a.x, b.x)
				var u1 := t1 * maxf(a.x, b.x)
				var va := float(vlen[i])
				var vb := float(vlen[i + 1])
				tri(q0, q1, q2, want, Vector2(u0, va), Vector2(u1, va), Vector2(u1, vb), n0, n1, n1)
				tri(q0, q2, q3, want, Vector2(u0, va), Vector2(u1, vb), Vector2(u0, vb), n0, n1, n0)

	## A hanging sheet (cloth, a flag): top edge from `p` along `ax` for `w` metres, hanging `hgt`
	## down `down`, facing `face`, in `rows` strips; free in the wind from `f_top` to `f_bot`.
	## UV: metres (u across, v up from the hem), or 0..1 with v down when `unit`.
	func sheet(p: Vector3, ax: Vector3, down: Vector3, w: float, hgt: float, face: Vector3, rows: int,
			f_top: float, f_bot: float, unit := false, billow := 0.0) -> void:
		for i in rows:
			var a0 := float(i) / float(rows)
			var a1 := float(i + 1) / float(rows)
			var b0 := face * billow * sin(a0 * PI)
			var b1 := face * billow * sin(a1 * PI)
			var l0 := p + down * hgt * a0 + b0
			var l1 := p + down * hgt * a1 + b1
			var r0 := l0 + ax * w
			var r1 := l1 + ax * w
			var f0 := lerpf(f_top, f_bot, a0)
			var f1 := lerpf(f_top, f_bot, a1)
			var ul0 := Vector2(0, a0) if unit else Vector2(0, hgt * (1.0 - a0))
			var ur0 := Vector2(1, a0) if unit else Vector2(w, hgt * (1.0 - a0))
			var ul1 := Vector2(0, a1) if unit else Vector2(0, hgt * (1.0 - a1))
			var ur1 := Vector2(1, a1) if unit else Vector2(w, hgt * (1.0 - a1))
			quad(l0, r0, r1, l1, face, ul0, ur0, ur1, ul1, f0, f0, f1, f1)

	func mesh(mat: Material) -> ArrayMesh:
		if v.is_empty():
			return null
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = v
		arr[Mesh.ARRAY_NORMAL] = n
		arr[Mesh.ARRAY_COLOR] = c
		arr[Mesh.ARRAY_TEX_UV] = uv
		arr[Mesh.ARRAY_TEX_UV2] = uv2
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		m.surface_set_material(0, mat)
		return m


# --- A stall --------------------------------------------------------------------------------------------

## One puesto into `solid` / `thin`: `xf` is its frame (origin at the middle of its front on the
## ground, +Z out over the aisle, +X along the lane), `goods` what it sells, `s` its seed. `lod` 1
## leaves the goods' small pieces out (the far copy).
static func stall(solid: Acc, thin: Acc, xf: Transform3D, goods: int, s: int, lod: int = 0) -> void:
	var paint: Color = STALL_PAINTS[hash([s, "paint"]) % STALL_PAINTS.size()]
	var awn: Color = AWNING_COLORS[hash([s, "awning"]) % AWNING_COLORS.size()]
	var wood := Color(0.42, 0.29, 0.18)
	var hw := STALL_W * 0.5
	var b := xf.basis
	var at := func(p: Vector3) -> Transform3D:
		return Transform3D(b, xf * p)
	# The frame: four posts, a back wall, side panels, a counter with a timber top, a shelf.
	solid.set_look(paint, K_PAINT)
	for px: float in [-hw + 0.05, hw - 0.05]:
		for pz: float in [-0.05, -STALL_D + 0.05]:
			solid.box(at.call(Vector3(px, STALL_H * 0.5, pz)), Vector3(0.09, STALL_H, 0.09))
	solid.box(at.call(Vector3(0, STALL_H * 0.5, -STALL_D + 0.03)), Vector3(STALL_W - 0.1, STALL_H, 0.04))
	for px: float in [-hw + 0.03, hw - 0.03]:
		solid.box(at.call(Vector3(px, 0.55, -STALL_D * 0.5)), Vector3(0.04, 1.1, STALL_D - 0.1))
	solid.box(at.call(Vector3(0, COUNTER_H * 0.5, -COUNTER_D * 0.5 - 0.02)), Vector3(STALL_W - 0.2, COUNTER_H, COUNTER_D - 0.04))
	solid.set_look(wood, K_WOOD)
	solid.box(at.call(Vector3(0, COUNTER_H + 0.025, -COUNTER_D * 0.5)), Vector3(STALL_W - 0.12, 0.05, COUNTER_D + 0.06))
	solid.box(at.call(Vector3(0, 1.55, -STALL_D + 0.2)), Vector3(STALL_W - 0.2, 0.04, 0.32))
	# The roof: timber boards on a slope down to the front, a fascia board in the stall's paint.
	var front_y := STALL_H - 0.12
	var back_y := STALL_H + 0.12
	var roof_basis := Basis(Vector3.RIGHT, -atan2(back_y - front_y, STALL_D + 0.2))
	solid.box(Transform3D(b * roof_basis, xf * Vector3(0, (front_y + back_y) * 0.5 + 0.03, -STALL_D * 0.5 + 0.05)), Vector3(STALL_W + 0.2, 0.05, STALL_D + 0.35))
	solid.set_look(paint, K_PAINT)
	solid.box(at.call(Vector3(0, front_y - 0.1, 0.12)), Vector3(STALL_W + 0.2, 0.22, 0.03))
	# The awning: striped canvas out over the aisle on two iron arms, a scalloped valance.
	var a0 := xf * Vector3(-hw - 0.05, front_y - 0.18, 0.13)
	var a1 := xf * Vector3(hw + 0.05, front_y - 0.18, 0.13)
	var o0 := xf * Vector3(-hw - 0.05, front_y - 0.18 - AWNING_DROP, 0.13 + AWNING_OUT)
	var o1 := xf * Vector3(hw + 0.05, front_y - 0.18 - AWNING_DROP, 0.13 + AWNING_OUT)
	var up := b * Vector3(0, 1, AWNING_DROP / AWNING_OUT).normalized()
	thin.set_look(awn, K_CANVAS, h01([s, "awn"]))
	var aw := STALL_W + 0.1
	thin.quad(a0, a1, o1, o0, up, Vector2(0, AWNING_OUT), Vector2(aw, AWNING_OUT), Vector2(aw, 0), Vector2(0, 0), 0.02, 0.02, 0.12, 0.12)
	# Valance: a strip hanging from the front edge with a wavy hem (three rows, the last cut in tabs).
	var tabs := 8
	for t in tabs:
		var u0 := float(t) / float(tabs)
		var u1 := float(t + 1) / float(tabs)
		var pa := o0.lerp(o1, u0)
		var pb := o0.lerp(o1, u1)
		var drop := Vector3(0, -0.2, 0)
		var mid := (pa + pb) * 0.5 + Vector3(0, -0.28, 0)
		thin.quad(pa, pb, pb + drop, pa + drop, b * Vector3(0, 0, 1), Vector2(u0 * aw, 0.28), Vector2(u1 * aw, 0.28), Vector2(u1 * aw, 0.08), Vector2(u0 * aw, 0.08), 0.12, 0.12, 0.25, 0.25)
		thin.tri(pa + drop, pb + drop, mid, b * Vector3(0, 0, 1), Vector2(u0 * aw, 0.08), Vector2(u1 * aw, 0.08), Vector2((u0 + u1) * 0.5 * aw, 0.0), Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, 0.25, 0.25, 0.35)
	solid.set_look(Color(0.12, 0.12, 0.12), K_IRON)
	for px: float in [-hw, hw]:
		var p := xf * Vector3(px, front_y - 0.18 - AWNING_DROP * 0.5, 0.13 + AWNING_OUT * 0.5)
		solid.box(Transform3D(b * Basis(Vector3.RIGHT, atan2(AWNING_DROP, AWNING_OUT)), p), Vector3(0.025, 0.025, Vector2(AWNING_OUT, AWNING_DROP).length()))
	# A bare bulb under the awning on its flex.
	solid.set_look(Color(1.0, 0.78, 0.45), K_BULB, h01([s, "bulb"]))
	solid.lathe(at.call(Vector3(0, front_y - 0.42, 0.45)), [Vector2(0.0, -0.05), Vector2(0.03, -0.04), Vector2(0.035, 0.0), Vector2(0.015, 0.03), Vector2(0.012, 0.05)], 6)
	_goods(solid, thin, xf, goods, s, lod)


## The goods a stall sells, on its counter, its back wall and hanging from its awning and posts.
static func _goods(solid: Acc, thin: Acc, xf: Transform3D, goods: int, s: int, lod: int) -> void:
	var b := xf.basis
	var hw := STALL_W * 0.5
	var at := func(p: Vector3) -> Transform3D:
		return Transform3D(b, xf * p)
	var top := COUNTER_H + 0.05
	var front := b * Vector3(0, 0, 1)
	match goods:
		Goods.SARAPES:
			# Folded stacks on the counter, sarapes hung over the back wall and from the awning bar.
			for i in 4:
				var x := -hw + 0.3 + 0.6 * float(i)
				var y := top
				for j in 3 + int(_rr(s, "st", i) * 4.0):
					var th := 0.05 + 0.02 * _rr(s, "th", i * 10 + j)
					solid.set_look(Color(0.2, 0.08, 0.06), K_SARAPE, _rr(s, "pal", i * 10 + j))
					solid.box(at.call(Vector3(x + (_rr(s, "jx", i * 10 + j) - 0.5) * 0.04, y + th * 0.5, -0.28)), Vector3(0.5, th, 0.36))
					y += th
			for i in 3:
				thin.set_look(Color(0.15, 0.08, 0.05), K_SARAPE, _rr(s, "back", i))
				thin.sheet(xf * Vector3(-hw + 0.12 + 0.75 * float(i), 2.3, -STALL_D + 0.07), b * Vector3(1, 0, 0), Vector3.DOWN, 0.7, 1.35, front, 4, 0.0, 0.05)
			for i in 2:
				thin.set_look(Color(0.1, 0.06, 0.05), K_SARAPE, _rr(s, "hang", i))
				thin.sheet(xf * Vector3(-hw + 0.05 + (STALL_W - 0.85) * float(i), 2.2, 0.32), b * Vector3(1, 0, 0), Vector3.DOWN, 0.8, 1.3, front, 5, 0.05, 0.6, false, 0.04)
		Goods.POTTERY:
			for i in 7:
				var x := -hw + 0.22 + 0.32 * float(i)
				var glazed := _rr(s, "gl", i) < 0.65
				var hgt := 0.16 + 0.22 * _rr(s, "h", i)
				var rad := 0.07 + 0.06 * _rr(s, "r", i)
				solid.set_look(_pot_color(s, i, glazed), K_GLAZE if glazed else K_CLAY, _rr(s, "pat", i))
				solid.lathe(at.call(Vector3(x, top, -0.3 + (_rr(s, "z", i) - 0.5) * 0.15)), _pot_profile(rad, hgt, int(_rr(s, "shape", i) * 3.0)), 10 if lod == 0 else 6)
			# Plates on the back wall, in rows.
			for row in 2:
				for i in 4:
					solid.set_look(_pot_color(s, 20 + row * 4 + i, true), K_GLAZE, _rr(s, "plate", row * 4 + i))
					var pc := xf * Vector3(-hw + 0.35 + 0.57 * float(i), 1.85 + 0.38 * float(row), -STALL_D + 0.08)
					solid.lathe(Transform3D(b * Basis(Vector3.RIGHT, PI * 0.5), pc), [Vector2(0.0, 0.0), Vector2(0.15, 0.0), Vector2(0.16, 0.025), Vector2(0.0, 0.02)], 10 if lod == 0 else 6)
			# Big pots on the ground either side of the stall front.
			for side: float in [-1.0, 1.0]:
				solid.set_look(Color(0.66, 0.34, 0.2), K_CLAY, _rr(s, "big", int(side)))
				solid.lathe(at.call(Vector3(side * (hw + 0.25), 0.0, 0.25)), _pot_profile(0.24, 0.62, 1), 10 if lod == 0 else 6)
		Goods.PINATAS:
			# Star pinatas from the awning: a ball and seven cones with paper tassels.
			for i in 3:
				var c := xf * Vector3(-hw + 0.45 + 0.75 * float(i), 1.85 - 0.15 * _rr(s, "y", i), 0.55)
				_pinata_star(solid, thin, c, b, 0.22 + 0.06 * _rr(s, "sz", i), s * 7 + i, lod)
			# Toys and maracas on the counter.
			for i in 8:
				var x := -hw + 0.18 + 0.28 * float(i)
				solid.set_look(_dye(s, i), K_GLOSSY)
				if i % 2 == 0:
					solid.lathe(at.call(Vector3(x, top, -0.3)), [Vector2(0.0, 0.0), Vector2(0.012, 0.0), Vector2(0.012, 0.1), Vector2(0.045, 0.13), Vector2(0.05, 0.18), Vector2(0.035, 0.22), Vector2(0.0, 0.23)], 8)
				else:
					solid.box(at.call(Vector3(x, top + 0.06, -0.28)), Vector3(0.16, 0.12, 0.12))
			# More pinatas on the back wall, smaller.
			for i in 3:
				var c := xf * Vector3(-hw + 0.45 + 0.75 * float(i), 1.95, -STALL_D + 0.3)
				_pinata_star(solid, thin, c, b, 0.16, s * 7 + 20 + i, 1)
		Goods.HATS:
			# Sombreros on the back wall and stacked on the counter, belts hanging from the posts.
			for row in 2:
				for i in 3:
					var pc := xf * Vector3(-hw + 0.45 + 0.75 * float(i), 1.55 + 0.6 * float(row), -STALL_D + 0.2)
					solid.set_look(_straw(s, row * 3 + i), K_STRAW)
					solid.lathe(Transform3D(b * Basis(Vector3.RIGHT, PI * 0.42), pc), _sombrero(0.3), 12 if lod == 0 else 7)
			for i in 3:
				var pc := xf * Vector3(-hw + 0.45 + 0.75 * float(i), top, -0.3)
				for j in 3:
					solid.set_look(_straw(s, 10 + i * 3 + j), K_STRAW)
					solid.lathe(Transform3D(b, pc + Vector3.UP * 0.035 * float(j)), _sombrero(0.24), 12 if lod == 0 else 7)
			if lod == 0:
				for i in 6:
					solid.set_look(Color(0.32 + 0.2 * _rr(s, "lb", i), 0.18, 0.08), K_LEATHER)
					solid.box(at.call(Vector3(-hw - 0.08, 1.75 - 0.35 * _rr(s, "lh", i), 0.02 + 0.05 * float(i))), Vector3(0.012, 0.75, 0.035))
		Goods.DRESSES:
			# Embroidered dresses hung across the front and on the back wall, blouses folded.
			for i in 3:
				thin.set_look(_cotton(s, i), K_EMBROID, _rr(s, "d", i))
				_dress(thin, xf * Vector3(-hw + 0.4 + 0.8 * float(i), 2.25, 0.3), b, 1.15 + 0.15 * _rr(s, "dl", i), front)
			for i in 4:
				thin.set_look(_cotton(s, 10 + i), K_EMBROID, _rr(s, "bd", i))
				_dress(thin, xf * Vector3(-hw + 0.3 + 0.6 * float(i), 2.35, -STALL_D + 0.08), b, 0.95, front)
			for i in 4:
				solid.set_look(_cotton(s, 20 + i), K_EMBROID, _rr(s, "fold", i))
				solid.box(at.call(Vector3(-hw + 0.3 + 0.6 * float(i), top + 0.06, -0.3)), Vector3(0.38, 0.12, 0.3))
		Goods.CANDY:
			# Tiers of jars and boxes of sweets.
			for tier in 3:
				var y := top + 0.22 * float(tier)
				var z := -0.32 - 0.25 * float(tier)
				solid.set_look(Color(0.5, 0.32, 0.18), K_WOOD)
				solid.box(at.call(Vector3(0, y - 0.03, z)), Vector3(STALL_W - 0.25, 0.04, 0.24))
				for i in 7:
					var x := -hw + 0.25 + 0.32 * float(i)
					if (i + tier) % 2 == 0:
						solid.set_look(_dye(s, tier * 10 + i), K_GLOSSY)
						solid.lathe(at.call(Vector3(x, y - 0.01, z)), [Vector2(0.0, 0.0), Vector2(0.075, 0.0), Vector2(0.08, 0.15), Vector2(0.05, 0.17), Vector2(0.05, 0.2), Vector2(0.0, 0.2)], 8 if lod == 0 else 5)
					else:
						solid.set_look(_dye(s, 50 + tier * 10 + i), K_GLOSSY)
						solid.box(at.call(Vector3(x, y + 0.04, z)), Vector3(0.22, 0.09, 0.16))
		Goods.SILVER:
			# A glass-fronted case of silver on the counter, framed mirrors on the back wall.
			solid.set_look(Color(0.08, 0.06, 0.06), K_PAINT)
			solid.box(at.call(Vector3(0, top + 0.01, -0.3)), Vector3(STALL_W - 0.3, 0.02, 0.45))
			solid.set_look(Color(0.9, 0.9, 0.92), K_SILVER)
			if lod == 0:
				for i in 18:
					solid.box(at.call(Vector3(-hw + 0.25 + 0.11 * float(i), top + 0.03, -0.3 + 0.12 * (_rr(s, "sz", i) - 0.5))), Vector3(0.06, 0.012, 0.04 + 0.04 * _rr(s, "sl", i)))
			for i in 4:
				var pc := Vector3(-hw + 0.35 + 0.57 * float(i), 1.7 + 0.4 * float(i % 2), -STALL_D + 0.07)
				solid.set_look(Color(0.86, 0.86, 0.88), K_SILVER)
				solid.box(at.call(pc), Vector3(0.4, 0.5, 0.03))
				solid.set_look(_dye(s, 30 + i), K_GLOSSY)
				solid.box(at.call(pc + Vector3(0, 0, 0.018)), Vector3(0.3, 0.4, 0.01))
		Goods.LEATHER:
			# Bags and huaraches: bags on the back wall and the posts, sandals in rows on the counter.
			for i in 5:
				solid.set_look(Color(0.3 + 0.25 * _rr(s, "bg", i), 0.17 + 0.08 * _rr(s, "bg2", i), 0.08), K_LEATHER)
				solid.box(at.call(Vector3(-hw + 0.3 + 0.45 * float(i), 1.75 + 0.3 * float(i % 2), -STALL_D + 0.16)), Vector3(0.32, 0.3, 0.12))
				solid.box(at.call(Vector3(-hw + 0.3 + 0.45 * float(i), 1.98 + 0.3 * float(i % 2), -STALL_D + 0.16)), Vector3(0.26, 0.15, 0.015))
			if lod == 0:
				for row in 2:
					for i in 8:
						solid.set_look(Color(0.36, 0.2, 0.1) * (0.8 + 0.4 * _rr(s, "hu", row * 8 + i)), K_LEATHER)
						solid.box(at.call(Vector3(-hw + 0.2 + 0.27 * float(i), top + 0.015, -0.18 - 0.22 * float(row))), Vector3(0.1, 0.03, 0.25))
			for side: float in [-1.0, 1.0]:
				solid.set_look(Color(0.4, 0.23, 0.1), K_LEATHER)
				solid.box(at.call(Vector3(side * (hw + 0.1), 1.4, 0.0)), Vector3(0.05, 0.36, 0.3))


static func _rr(s: int, k: String, i: int) -> float:
	return h01([s, k, i])


static func _dye(s: int, i: int) -> Color:
	return PAPER_COLORS[hash([s, "dye", i]) % PAPER_COLORS.size()]


static func _pot_color(s: int, i: int, glazed: bool) -> Color:
	if not glazed:
		return Color(0.68, 0.36, 0.22)
	var g := [Color(0.12, 0.3, 0.62), Color(0.9, 0.86, 0.74), Color(0.15, 0.5, 0.42), Color(0.78, 0.48, 0.12), Color(0.55, 0.12, 0.1)]
	return g[hash([s, "pot", i]) % g.size()]


static func _straw(s: int, i: int) -> Color:
	var t := h01([s, "straw", i])
	return Color(0.82, 0.68, 0.42).lerp(Color(0.6, 0.45, 0.26), t)


static func _cotton(s: int, i: int) -> Color:
	var g := [Color(0.95, 0.94, 0.9), Color(0.95, 0.94, 0.9), Color(0.08, 0.08, 0.1), Color(0.86, 0.2, 0.35), Color(0.2, 0.45, 0.8)]
	return g[hash([s, "cotton", i]) % g.size()]


## A pot's profile [r, y]: a jug, a squat olla, or a vase.
static func _pot_profile(rad: float, hgt: float, shape: int) -> Array:
	match shape:
		0:
			return [Vector2(0.0, 0.0), Vector2(rad * 0.7, 0.0), Vector2(rad, hgt * 0.35), Vector2(rad * 0.85, hgt * 0.7), Vector2(rad * 0.4, hgt * 0.85), Vector2(rad * 0.45, hgt), Vector2(rad * 0.35, hgt)]
		1:
			return [Vector2(0.0, 0.0), Vector2(rad * 0.6, 0.0), Vector2(rad, hgt * 0.45), Vector2(rad * 0.75, hgt * 0.85), Vector2(rad * 0.6, hgt * 0.9), Vector2(rad * 0.7, hgt), Vector2(rad * 0.55, hgt)]
	return [Vector2(0.0, 0.0), Vector2(rad * 0.5, 0.0), Vector2(rad * 0.8, hgt * 0.3), Vector2(rad * 0.45, hgt * 0.7), Vector2(rad * 0.7, hgt), Vector2(rad * 0.6, hgt)]


## A sombrero's profile [r, y], `rad` the brim's radius: crown, then the upturned brim.
static func _sombrero(rad: float) -> Array:
	return [Vector2(0.0, 0.22), Vector2(rad * 0.18, 0.21), Vector2(rad * 0.3, 0.12), Vector2(rad * 0.33, 0.03),
		Vector2(rad * 0.7, 0.0), Vector2(rad * 0.95, 0.035), Vector2(rad, 0.06), Vector2(rad * 0.97, 0.07), Vector2(rad * 0.7, 0.02), Vector2(rad * 0.34, 0.045), Vector2(0.0, 0.05)]


## A star pinata: a ball with seven cones and a tassel of crepe at each tip, hanging on a cord.
static func _pinata_star(solid: Acc, thin: Acc, c: Vector3, b: Basis, rad: float, s: int, lod: int) -> void:
	solid.set_look(_dye(s, 0), K_CREPE, h01([s, "pin"]))
	solid.lathe(Transform3D(b, c - Vector3.UP * rad * 0.9), [Vector2(0.0, 0.0), Vector2(rad * 0.7, rad * 0.35), Vector2(rad * 0.9, rad * 0.9), Vector2(rad * 0.7, rad * 1.45), Vector2(0.0, rad * 1.8)], 8 if lod == 0 else 5)
	var dirs := [Vector3(0, 1, 0), Vector3(1, 0.3, 0), Vector3(-1, 0.3, 0), Vector3(0.5, -0.8, 0.3), Vector3(-0.5, -0.8, 0.3), Vector3(0, 0.2, 1), Vector3(0.0, -0.2, -1)]
	for i in dirs.size():
		var d: Vector3 = b * (dirs[i] as Vector3).normalized()
		var up := Vector3.UP if absf(d.y) < 0.95 else Vector3.RIGHT
		var bas := Basis.looking_at(d, up) * Basis(Vector3.RIGHT, -PI * 0.5)
		solid.set_look(_dye(s, i + 1), K_CREPE, h01([s, "cone", i]))
		solid.lathe(Transform3D(bas, c + d * rad * 0.6), [Vector2(rad * 0.32, 0.0), Vector2(0.0, rad * 1.5)], 6 if lod == 0 else 4)
		if lod == 0 and i > 0:
			thin.set_look(_dye(s, i + 4), K_CREPE, h01([s, "tas", i]))
			var tip := c + d * rad * 2.05
			thin.sheet(tip - b * Vector3(0.04, 0, 0), b * Vector3(1, 0, 0), Vector3.DOWN, 0.08, 0.3, b * Vector3(0, 0, 1), 2, 0.2, 0.9)
	solid.set_look(Color(0.2, 0.2, 0.2), K_IRON)
	solid.box(Transform3D(b, c + Vector3.UP * (rad * 1.0 + 0.3)), Vector3(0.008, 0.6, 0.008))


## A dress hanging from `p` (the shoulders' middle): a yoke and a flared skirt in two sheets.
static func _dress(thin: Acc, p: Vector3, b: Basis, length: float, face: Vector3) -> void:
	var ax := b * Vector3(1, 0, 0)
	var top_w := 0.34
	var hem_w := 0.62
	var rows := 4
	for i in rows:
		var a0 := float(i) / float(rows)
		var a1 := float(i + 1) / float(rows)
		var w0 := lerpf(top_w, hem_w, a0 * a0)
		var w1 := lerpf(top_w, hem_w, a1 * a1)
		var y0 := p - Vector3.UP * length * a0
		var y1 := p - Vector3.UP * length * a1
		var v0 := length * (1.0 - a0)
		var v1 := length * (1.0 - a1)
		thin.quad(y0 - ax * w0 * 0.5, y0 + ax * w0 * 0.5, y1 + ax * w1 * 0.5, y1 - ax * w1 * 0.5, face,
			Vector2(0, v0 / length), Vector2(w0, v0 / length), Vector2(w1, v1 / length), Vector2(0, v1 / length),
			a0 * 0.4, a0 * 0.4, a1 * 0.5, a1 * 0.5)


# --- Strings overhead -------------------------------------------------------------------------------

## A string of papel picado from `a` to `b` sagging `sag` metres in the middle; the flags' colours
## and cut patterns by hash of `s`. Returns the number of flags.
static func picado(thin: Acc, solid: Acc, a: Vector3, b: Vector3, sag: float, s: int) -> int:
	var d := b - a
	var length := Vector2(d.x, d.z).length()
	var n := maxi(2, int(length / FLAG_PITCH))
	var across := Vector3(d.x, 0, d.z).normalized()
	var face := across.cross(Vector3.UP).normalized()
	var flags := 0
	var prev := a
	for i in n:
		var t0 := (float(i) + 0.5 - FLAG_W / FLAG_PITCH * 0.5) / float(n)
		var t1 := (float(i) + 0.5 + FLAG_W / FLAG_PITCH * 0.5) / float(n)
		var p0 := a.lerp(b, t0) + Vector3.DOWN * sag * 4.0 * t0 * (1.0 - t0)
		var p1 := a.lerp(b, t1) + Vector3.DOWN * sag * 4.0 * t1 * (1.0 - t1)
		var pick := h01([s, "flag", i])
		var col: Color = PAPER_COLORS[hash([s, "fc", i]) % PAPER_COLORS.size()]
		thin.set_look(col, K_PAPER, pick)
		var l1 := p0 + Vector3.DOWN * FLAG_H
		var r1 := p1 + Vector3.DOWN * FLAG_H
		thin.quad(p0, p1, r1, l1, face, Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1), 0.08, 0.08, 1.0, 1.0)
		flags += 1
	# The string: thin segments.
	solid.set_look(Color(0.85, 0.82, 0.75), K_PAINT)
	var segs := maxi(4, int(length / 2.0))
	for i in segs:
		var t0 := float(i) / float(segs)
		var t1 := float(i + 1) / float(segs)
		var p0 := a.lerp(b, t0) + Vector3.DOWN * sag * 4.0 * t0 * (1.0 - t0)
		var p1 := a.lerp(b, t1) + Vector3.DOWN * sag * 4.0 * t1 * (1.0 - t1)
		var mid := (p0 + p1) * 0.5
		var dir := (p1 - p0)
		if dir.length() < 0.01:
			continue
		var bas := Basis.looking_at(dir.normalized(), Vector3.UP if absf(dir.normalized().y) < 0.99 else Vector3.RIGHT)
		solid.box(Transform3D(bas, mid), Vector3(0.008, 0.008, dir.length()))
	return flags


## A string of bulbs from `a` to `b` sagging `sag`, one every `pitch` metres. Returns their number.
static func bulbs(solid: Acc, a: Vector3, b: Vector3, sag: float, pitch: float, s: int) -> int:
	var d := b - a
	var length := d.length()
	var n := maxi(2, int(length / pitch))
	solid.set_look(Color(0.08, 0.08, 0.08), K_IRON)
	var segs := maxi(4, int(length / 2.0))
	for i in segs:
		var t0 := float(i) / float(segs)
		var t1 := float(i + 1) / float(segs)
		var p0 := a.lerp(b, t0) + Vector3.DOWN * sag * 4.0 * t0 * (1.0 - t0)
		var p1 := a.lerp(b, t1) + Vector3.DOWN * sag * 4.0 * t1 * (1.0 - t1)
		var dir := p1 - p0
		if dir.length() < 0.01:
			continue
		solid.box(Transform3D(Basis.looking_at(dir.normalized(), Vector3.UP if absf(dir.normalized().y) < 0.99 else Vector3.RIGHT), (p0 + p1) * 0.5), Vector3(0.01, 0.01, dir.length()))
	for i in n:
		var t := (float(i) + 0.5) / float(n)
		var p := a.lerp(b, t) + Vector3.DOWN * (sag * 4.0 * t * (1.0 - t) + 0.07)
		solid.set_look(Color(1.0, 0.76, 0.42), K_BULB, h01([s, "b", i]))
		solid.lathe(Transform3D(Basis(), p), [Vector2(0.0, -0.05), Vector2(0.028, -0.035), Vector2(0.03, 0.0), Vector2(0.012, 0.035), Vector2(0.0, 0.04)], 5)
	return n


## A wall lantern: an iron bracket and a glazed lantern lit after dark, on a wall facing `out`.
static func lantern(solid: Acc, at: Vector3, out: Vector3) -> void:
	var bas := Basis.looking_at(-out, Vector3.UP)
	solid.set_look(Color(0.07, 0.07, 0.07), K_IRON)
	solid.box(Transform3D(bas, at + out * 0.2 + Vector3.UP * 0.3), Vector3(0.03, 0.03, 0.4))
	solid.box(Transform3D(bas, at + out * 0.38 + Vector3.UP * 0.22), Vector3(0.24, 0.03, 0.24))
	solid.box(Transform3D(bas, at + out * 0.38 - Vector3.UP * 0.12), Vector3(0.2, 0.03, 0.2))
	solid.lathe(Transform3D(bas, at + out * 0.38 + Vector3.UP * 0.23), [Vector2(0.15, 0.0), Vector2(0.0, 0.12)], 4)
	solid.set_look(Color(1.0, 0.8, 0.5), K_GLOW)
	solid.box(Transform3D(bas, at + out * 0.38 + Vector3.UP * 0.05), Vector3(0.17, 0.3, 0.17))
