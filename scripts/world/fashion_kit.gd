class_name FashionKit
extends RefCounted
## The fashion district's goods (FashionDistrict), built in code at real size on ONE shader
## (shaders/fashion_goods.gdshader): rolling garment racks hung with shirts, dresses, jackets and
## jeans; slanted stands of fabric bolts and bins of tall fabric rolls; fibreglass mannequins
## dressed in the shop's stock; two-wheel hand trucks loaded with cartons; folding sale tables of
## folded stock; gridwall panels of hanging garments; and the market alley's stalls (a tube frame,
## a gridwall back hung with stock, a counter, a tarp roof) with the tarps, banners and bulb
## strings strung over it. Every mesh is built once and cached; a chunk places instances.
##
## Vertex data, the contract with the shader:
## * COLOR.rgb is the paint, sRGB (a garment's dye, a tarp's colour); COLOR.a the surface KIND
##   (K_*) as (kind + 0.5) / 16, so 8-bit vertex colours keep it.
## * UV is metres along the surface (u across, v down a garment / along a roll), so weaves,
##   patterns, cardboard flutes and tape land at real size.
## * UV2.x picks a fabric pattern or a variant (P_*); UV2.y is a fold parameter (0 at a
##   garment's shoulder, 1 at its hem) the shader shades the drape from.
## The garments' colours are worked out per mesh variant (STORIES): a rack is a colour story, so
## a street of racks reads as a shop's stock, not a random confetti.

enum { K_CLOTH, K_KNIT, K_DENIM, K_FABRIC, K_CHROME, K_CARDBOARD, K_CANVAS, K_FIBRE,
	K_WOOD, K_PLASTIC, K_PAPER, K_INK, K_BULB, K_RUBBER, K_GRID, K_PAINT }

## Fabric patterns (UV2.x for K_FABRIC and printed garments, as (p + 0.5) / 16).
enum { P_SOLID, P_STRIPE, P_PLAID, P_FLORAL, P_DOTS, P_SATIN, P_SEQUIN, P_LACE, P_CAMO, P_LEOPARD }

## Colour stories (sRGB): what one rack, table or stall of a shop carries.
const STORIES := [
	# Denim and neutrals.
	[Color(0.16, 0.22, 0.36), Color(0.27, 0.36, 0.52), Color(0.10, 0.12, 0.18), Color(0.85, 0.83, 0.78),
		Color(0.55, 0.48, 0.38), Color(0.12, 0.12, 0.13), Color(0.62, 0.66, 0.70)],
	# Bright summer.
	[Color(0.90, 0.30, 0.42), Color(0.98, 0.72, 0.18), Color(0.20, 0.62, 0.70), Color(0.95, 0.94, 0.90),
		Color(0.60, 0.80, 0.35), Color(0.92, 0.48, 0.20), Color(0.48, 0.32, 0.70)],
	# Black and white, formal.
	[Color(0.06, 0.06, 0.07), Color(0.94, 0.93, 0.90), Color(0.40, 0.40, 0.42), Color(0.55, 0.06, 0.10),
		Color(0.08, 0.10, 0.20), Color(0.80, 0.70, 0.52)],
	# Pastels.
	[Color(0.95, 0.78, 0.82), Color(0.74, 0.86, 0.92), Color(0.88, 0.92, 0.76), Color(0.96, 0.92, 0.80),
		Color(0.80, 0.74, 0.90), Color(0.98, 0.86, 0.72)],
	# Earth and olive.
	[Color(0.33, 0.35, 0.20), Color(0.52, 0.36, 0.22), Color(0.70, 0.60, 0.44), Color(0.22, 0.18, 0.14),
		Color(0.60, 0.30, 0.18), Color(0.82, 0.76, 0.62)],
	# Party: satins and sequins.
	[Color(0.75, 0.10, 0.25), Color(0.10, 0.20, 0.55), Color(0.85, 0.72, 0.40), Color(0.05, 0.05, 0.06),
		Color(0.85, 0.82, 0.88), Color(0.30, 0.55, 0.45)],
]
## Mesh variants of each kind (colour stories and layouts); FashionDistrict picks by hash.
const RACK_VARIANTS := 6
const BOLT_VARIANTS := 4
const ROLL_VARIANTS := 4
const MANNEQUIN_VARIANTS := 6
const TABLE_VARIANTS := 4
const WALL_VARIANTS := 4
const STALL_VARIANTS := 4
const TRUCK_VARIANTS := 3
## Hand-lettered price and trade signs (invented; Spanish and English as on the real streets).
const SIGNS := ["$5", "$10", "3 X $10", "$15", "WHOLESALE ONLY", "MAYOREO", "SALE", "OFERTA",
	"LIQUIDACION", "$2.99", "2 X $20", "PRECIOS DE FABRICA"]

static var _cache: Dictionary = {}
static var _material: ShaderMaterial = null
static var _text_cache: Dictionary = {}


# --- Geometry -------------------------------------------------------------------------------

## Packed arrays for one mesh; every helper writes triangles with their own normals.
class Geo:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()

	func vert(p: Vector3, nn: Vector3, col: Color, t: Vector2, t2: Vector2) -> void:
		v.append(p)
		n.append(nn)
		c.append(col)
		uv.append(t)
		uv2.append(t2)

	## A triangle, wound so its face looks along `want` (Godot's front: (c - a) x (b - a)).
	func tri(a: Vector3, b: Vector3, cc: Vector3, na: Vector3, nb: Vector3, nc: Vector3, col: Color,
			ta: Vector2, tb: Vector2, tc: Vector2, t2: Vector2, want: Vector3) -> void:
		if (cc - a).cross(b - a).dot(want) < 0.0:
			vert(a, na, col, ta, t2)
			vert(cc, nc, col, tc, t2)
			vert(b, nb, col, tb, t2)
		else:
			vert(a, na, col, ta, t2)
			vert(b, nb, col, tb, t2)
			vert(cc, nc, col, tc, t2)

	func flat_quad(p: Array, col: Color, t: Array, t2: Vector2, want: Vector3) -> void:
		var nn := ((p[2] as Vector3) - (p[0] as Vector3)).cross((p[1] as Vector3) - (p[0] as Vector3)).normalized()
		if nn.dot(want) < 0.0:
			nn = -nn
		tri(p[0], p[1], p[2], nn, nn, nn, col, t[0], t[1], t[2], t2, nn)
		tri(p[0], p[2], p[3], nn, nn, nn, col, t[0], t[2], t[3], t2, nn)

	## A box, centre `ctr`, half extents along the basis axes; uv in metres.
	func box(ctr: Vector3, size: Vector3, col: Color, b: Basis = Basis(), t2: Vector2 = Vector2.ZERO, skip_bottom: bool = true) -> void:
		var h := size * 0.5
		var ax := [b.x.normalized(), b.y.normalized(), b.z.normalized()]
		var ext := [h.x, h.y, h.z]
		for i in 3:
			for s: float in [-1.0, 1.0]:
				if skip_bottom and i == 1 and s < 0.0:
					continue
				var nn: Vector3 = (ax[i] as Vector3) * s
				var u: Vector3 = ax[(i + 1) % 3]
				var w: Vector3 = ax[(i + 2) % 3]
				var eu: float = ext[(i + 1) % 3]
				var ew: float = ext[(i + 2) % 3]
				var o: Vector3 = ctr + nn * float(ext[i])
				var q := [o - u * eu - w * ew, o + u * eu - w * ew, o + u * eu + w * ew, o - u * eu + w * ew]
				var tq := [Vector2(0, 0), Vector2(eu * 2.0, 0), Vector2(eu * 2.0, ew * 2.0), Vector2(0, ew * 2.0)]
				tri(q[0], q[1], q[2], nn, nn, nn, col, tq[0], tq[1], tq[2], t2, nn)
				tri(q[0], q[2], q[3], nn, nn, nn, col, tq[0], tq[2], tq[3], t2, nn)

	## A round tube from `a` to `b`, radius `r`, `segs` sides, open ends (smooth).
	func tube(a: Vector3, b: Vector3, r: float, segs: int, col: Color, t2: Vector2 = Vector2.ZERO, r_b: float = -1.0) -> void:
		var d := b - a
		var len := d.length()
		if len < 1e-5:
			return
		var ax := d / len
		var side := ax.cross(Vector3.UP if absf(ax.y) < 0.9 else Vector3.RIGHT).normalized()
		var up := side.cross(ax).normalized()
		var rb := r if r_b < 0.0 else r_b
		for i in segs:
			var a0 := TAU * float(i) / float(segs)
			var a1 := TAU * float(i + 1) / float(segs)
			var n0 := side * cos(a0) + up * sin(a0)
			var n1 := side * cos(a1) + up * sin(a1)
			var p00 := a + n0 * r
			var p01 := a + n1 * r
			var p10 := b + n0 * rb
			var p11 := b + n1 * rb
			var u0 := float(i) / float(segs) * TAU * r
			var u1 := float(i + 1) / float(segs) * TAU * r
			tri(p00, p10, p11, n0, n0, n1, col, Vector2(u0, 0), Vector2(u0, len), Vector2(u1, len), t2, (n0 + n1))
			tri(p00, p11, p01, n0, n1, n1, col, Vector2(u0, 0), Vector2(u1, len), Vector2(u1, 0), t2, (n0 + n1))

	## A disc cap at `ctr` facing `nn`.
	func disc(ctr: Vector3, nn: Vector3, r: float, segs: int, col: Color, t2: Vector2 = Vector2.ZERO) -> void:
		var side := nn.cross(Vector3.UP if absf(nn.y) < 0.9 else Vector3.RIGHT).normalized()
		var up := side.cross(nn).normalized()
		for i in segs:
			var a0 := TAU * float(i) / float(segs)
			var a1 := TAU * float(i + 1) / float(segs)
			var p0 := ctr + (side * cos(a0) + up * sin(a0)) * r
			var p1 := ctr + (side * cos(a1) + up * sin(a1)) * r
			tri(ctr, p0, p1, nn, nn, nn, col, Vector2(0.5, 0.5), Vector2(0.5 + cos(a0) * 0.5, 0.5 + sin(a0) * 0.5),
				Vector2(0.5 + cos(a1) * 0.5, 0.5 + sin(a1) * 0.5), t2, nn)

	## A smooth surface from a grid of points rows[j][i] (rows down, columns round); `closed` joins
	## the last column to the first. Normals from the grid, turned to face away from `centre_of`
	## (a callable p -> the point inside the surface at that height) when given.
	func sheet(rows: Array, closed: bool, col_at: Callable, uv_at: Callable, t2_at: Callable, outward: Callable) -> void:
		var nr := rows.size()
		var nc: int = (rows[0] as Array).size()
		var normals: Array = []
		for j in nr:
			var line: Array = []
			for i in nc:
				var p: Vector3 = rows[j][i]
				var pu: Vector3 = rows[j][(i + 1) % nc] if (closed or i + 1 < nc) else rows[j][i]
				var pd: Vector3 = rows[j][(i - 1 + nc) % nc] if (closed or i > 0) else rows[j][i]
				var pn: Vector3 = rows[mini(j + 1, nr - 1)][i]
				var pp: Vector3 = rows[maxi(j - 1, 0)][i]
				var nn := (pu - pd).cross(pn - pp)
				if nn.length_squared() < 1e-12:
					nn = outward.call(p)
				nn = nn.normalized()
				if nn.dot(outward.call(p)) < 0.0:
					nn = -nn
				line.append(nn)
			normals.append(line)
		var cols := nc if closed else nc - 1
		for j in nr - 1:
			for i in cols:
				var i1 := (i + 1) % nc
				var a: Vector3 = rows[j][i]
				var b: Vector3 = rows[j][i1]
				var cc: Vector3 = rows[j + 1][i1]
				var d: Vector3 = rows[j + 1][i]
				var col: Color = col_at.call(j, i)
				var t2: Vector2 = t2_at.call(j, i)
				var want: Vector3 = (normals[j][i] as Vector3) + (normals[j + 1][i1] as Vector3)
				tri(a, b, cc, normals[j][i], normals[j][i1], normals[j + 1][i1], col, uv_at.call(j, i), uv_at.call(j, i + 1), uv_at.call(j + 1, i + 1), t2, want)
				tri(a, cc, d, normals[j][i], normals[j + 1][i1], normals[j + 1][i], col, uv_at.call(j, i), uv_at.call(j + 1, i + 1), uv_at.call(j + 1, i), t2, want)

	func append_xf(g: Geo, xf: Transform3D) -> void:
		var nb := xf.basis.inverse().transposed()
		for k in g.v.size():
			v.append(xf * g.v[k])
			n.append((nb * g.n[k]).normalized())
			c.append(g.c[k])
			uv.append(g.uv[k])
			uv2.append(g.uv2[k])

	func commit() -> ArrayMesh:
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = v
		arr[Mesh.ARRAY_NORMAL] = n
		arr[Mesh.ARRAY_COLOR] = c
		arr[Mesh.ARRAY_TEX_UV] = uv
		arr[Mesh.ARRAY_TEX_UV2] = uv2
		var m := ArrayMesh.new()
		if v.is_empty():
			return m
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		m.surface_set_material(0, FashionKit.material())
		return m


## A vertex colour with the kind in its alpha.
static func kc(col: Color, kind: int) -> Color:
	return Color(col.r, col.g, col.b, (float(kind) + 0.5) / 16.0)


## UV2 for a pattern and a fold parameter.
static func pat(p: int, fold: float = 0.0) -> Vector2:
	return Vector2((float(p) + 0.5) / 16.0, fold)


static func h01(parts: Array) -> float:
	return float(absi(hash(parts)) % 100003) / 100003.0


static func material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = load("res://shaders/fashion_goods.gdshader")
	return _material


# --- Garments -------------------------------------------------------------------------------

enum Cut { TEE, SHIRT, DRESS, GOWN, JACKET, JEANS, SKIRT, HOODIE }

## One garment hung on a hanger, its local frame: the hanger hook's top at the origin, shoulders
## across z (the rail runs along x), the body hanging down -y, thickness along x. `w` shoulder
## width, `len` length under the hanger, `col` its dye, `pattern` P_*.
static func garment(g: Geo, cut: int, col: Color, pattern: int, w: float, len: float, seed_value: int, flat: bool = false) -> void:
	var kind := K_CLOTH
	match cut:
		Cut.TEE, Cut.HOODIE:
			kind = K_KNIT
		Cut.JEANS:
			kind = K_DENIM
	if pattern != P_SOLID and kind == K_KNIT:
		kind = K_CLOTH
	var top := -0.07
	var segs := 6
	var rings := 5
	var thick := 0.035 if flat else 0.05
	if cut == Cut.JACKET or cut == Cut.HOODIE:
		thick = 0.075 if not flat else 0.05
	var rows: Array = []
	var phase := h01([seed_value, "fold"]) * TAU
	for j in rings + 1:
		var t := float(j) / float(rings)
		var y := top - 0.05 - t * len
		var half := w * 0.5
		match cut:
			Cut.DRESS:
				half = lerpf(w * 0.38, w * 0.62, smoothstep(0.25, 1.0, t)) if t > 0.15 else lerpf(w * 0.42, w * 0.36, t / 0.15)
			Cut.GOWN:
				half = lerpf(w * 0.34, w * 1.15, smoothstep(0.25, 1.0, t)) if t > 0.2 else w * 0.36
			Cut.SKIRT:
				half = lerpf(w * 0.40, w * 0.62, t)
			Cut.JEANS:
				half = lerpf(w * 0.48, w * 0.44, t)
			_:
				half = lerpf(w * 0.5, w * 0.46, t)
		# The shoulders slope from the neck down to the sleeve head.
		var line: Array = []
		for i in segs:
			var a := TAU * float(i) / float(segs)
			var zc := cos(a) * half
			var xc := sin(a) * thick * (1.0 + 0.6 * t * (1.0 if cut == Cut.GOWN else 0.3))
			# Vertical folds deepen toward the hem.
			var fold := sin(a * 3.0 + phase + t * 1.3) * 0.012 * t * (2.5 if cut == Cut.GOWN or cut == Cut.DRESS or cut == Cut.SKIRT else 1.0)
			xc += fold * signf(sin(a) + 0.001)
			var yy := y
			if j == 0:
				yy = top - 0.05 - absf(cos(a)) * 0.06
			line.append(Vector3(xc, yy, zc))
		rows.append(line)
	var paint := kc(col, kind)
	var pt := pattern
	g.sheet(rows, true, func(_j: int, _i: int) -> Color: return paint,
		func(j: int, i: int) -> Vector2: return Vector2(float(i) / float(segs) * w * 2.0, float(j) / float(rings) * len),
		func(j: int, _i: int) -> Vector2: return pat(pt, float(j) / float(rings)),
		func(p: Vector3) -> Vector3: return Vector3(p.x, 0.0, p.z) if absf(p.x) + absf(p.z) > 1e-4 else Vector3.RIGHT)
	# The shoulders' top: a ridge closing the loop at the neckline.
	var r0: Array = rows[0]
	var ctr := Vector3(0.0, top - 0.035, 0.0)
	for i in segs:
		var p0: Vector3 = r0[i]
		var p1: Vector3 = r0[(i + 1) % segs]
		g.tri(ctr, p0, p1, Vector3.UP, (p0 - ctr + Vector3.UP * 0.2).normalized(), (p1 - ctr + Vector3.UP * 0.2).normalized(), paint,
			Vector2(0, 0), Vector2(0.1, 0.05), Vector2(0.2, 0.05), pat(pt, 0.0), Vector3.UP)
	# The hem: closed underneath.
	var rl: Array = rows[rows.size() - 1]
	var hc := Vector3(0.0, (rl[0] as Vector3).y, 0.0)
	for i in segs:
		g.tri(hc, rl[i], rl[(i + 1) % segs], Vector3.DOWN, Vector3.DOWN, Vector3.DOWN, paint, Vector2.ZERO, Vector2(0.1, 0), Vector2(0, 0.1), pat(pt, 1.0), Vector3.DOWN)
	# Sleeves: shirts, tees, jackets, hoodies hang theirs down the sides.
	if cut in [Cut.TEE, Cut.SHIRT, Cut.JACKET, Cut.HOODIE]:
		var sl := 0.22 if cut == Cut.TEE else len * 0.86
		var sr := 0.055 if cut == Cut.TEE else 0.045
		for s: float in [-1.0, 1.0]:
			var a := Vector3(0.0, top - 0.10, s * w * 0.5)
			var b := a + Vector3(0.0, -sl, s * (0.03 if cut == Cut.TEE else 0.015))
			g.tube(a, b, sr, 6, paint, pat(pt, 0.5), sr * (1.1 if cut == Cut.TEE else 0.85))
			g.disc(b, Vector3.DOWN, sr * (1.1 if cut == Cut.TEE else 0.85), 6, paint, pat(pt, 1.0))
	if cut == Cut.JEANS:
		# The legs' split shows as a dark notch down the front.
		g.box(Vector3(0.0, top - 0.05 - len * 0.62, 0.0), Vector3(thick * 2.4, len * 0.7, 0.008), kc(col * 0.45, K_DENIM), Basis(), pat(P_SOLID, 0.8))
	if cut == Cut.HOODIE:
		g.tube(Vector3(0.0, top - 0.06, 0.0), Vector3(-thick * 1.2, top - 0.24, 0.0), 0.09, 7, paint, pat(pt, 0.2), 0.05)
	# The hanger: a hook and a shoulder bar.
	var wire := kc(Color(0.72, 0.73, 0.75), K_CHROME)
	g.tube(Vector3(0.0, 0.0, 0.0), Vector3(0.0, top - 0.02, 0.0), 0.004, 4, wire)
	var hanger := kc(Color(0.10, 0.10, 0.11), K_PLASTIC) if h01([seed_value, "hg"]) < 0.7 else kc(Color(0.55, 0.38, 0.22), K_WOOD)
	g.box(Vector3(0.0, top - 0.04, 0.0), Vector3(0.012, 0.018, w * 0.92), hanger, Basis())


## A garment built in its own Geo then placed (garment() writes straight into `g`; this wraps it
## for a placement transform).
static func garment_at(g: Geo, xf: Transform3D, cut: int, col: Color, pattern: int, w: float, len: float, seed_value: int, flat: bool = false) -> void:
	var tmp := Geo.new()
	garment(tmp, cut, col, pattern, w, len, seed_value, flat)
	g.append_xf(tmp, xf)


## A cut and its size for slot `k` of a colour story (shirts, tees and dresses mostly).
static func pick_cut(seed_value: int, k: int, mix: int) -> Array:
	var r := h01([seed_value, "cut", k])
	var cut := Cut.SHIRT
	match mix:
		0:
			cut = Cut.JEANS if r < 0.45 else (Cut.TEE if r < 0.75 else (Cut.JACKET if r < 0.9 else Cut.SHIRT))
		1:
			cut = Cut.TEE if r < 0.4 else (Cut.DRESS if r < 0.7 else (Cut.SKIRT if r < 0.85 else Cut.SHIRT))
		2:
			cut = Cut.SHIRT if r < 0.4 else (Cut.DRESS if r < 0.65 else (Cut.JACKET if r < 0.9 else Cut.JEANS))
		3:
			cut = Cut.DRESS if r < 0.45 else (Cut.TEE if r < 0.75 else Cut.SKIRT)
		4:
			cut = Cut.JACKET if r < 0.35 else (Cut.HOODIE if r < 0.65 else (Cut.SHIRT if r < 0.85 else Cut.JEANS))
		_:
			cut = Cut.GOWN if r < 0.35 else (Cut.DRESS if r < 0.85 else Cut.SKIRT)
	var w := 0.42
	var len := 0.72
	match cut:
		Cut.TEE:
			w = 0.46
			len = 0.66
		Cut.SHIRT:
			w = 0.44
			len = 0.76
		Cut.DRESS:
			w = 0.38
			len = 1.0
		Cut.GOWN:
			w = 0.36
			len = 1.32
		Cut.JACKET:
			w = 0.48
			len = 0.70
		Cut.HOODIE:
			w = 0.50
			len = 0.68
		Cut.JEANS:
			w = 0.40
			len = 1.0
		Cut.SKIRT:
			w = 0.36
			len = 0.62
	w *= 0.94 + 0.12 * h01([seed_value, "w", k])
	len *= 0.94 + 0.12 * h01([seed_value, "l", k])
	var pattern := P_SOLID
	var pr := h01([seed_value, "pat", k])
	if cut == Cut.SHIRT and pr < 0.45:
		pattern = P_STRIPE if pr < 0.2 else P_PLAID
	elif (cut == Cut.DRESS or cut == Cut.SKIRT) and pr < 0.4:
		pattern = P_FLORAL if pr < 0.2 else (P_DOTS if pr < 0.3 else P_LEOPARD)
	elif cut == Cut.GOWN:
		pattern = P_SATIN if pr < 0.6 else P_SEQUIN
	elif cut == Cut.JACKET and pr < 0.15:
		pattern = P_CAMO
	return [cut, w, len, pattern]


# --- Racks ---------------------------------------------------------------------------------

## A rolling garment rack: chrome uprights on castors, a rail along x, `n` garments of one colour
## story. Length 1.5 m, rail at 1.62 m. Its local frame: centre of the foot on y 0, rail along x.
static func rack(variant: int) -> Geo:
	var key := "rack_%d" % variant
	if _cache.has(key):
		return _cache[key]
	var g := Geo.new()
	var chrome := kc(Color(0.78, 0.79, 0.81), K_CHROME)
	var rubber := kc(Color(0.08, 0.08, 0.08), K_RUBBER)
	var L := 1.5
	var rail_y := 1.62
	for sx: float in [-1.0, 1.0]:
		var x := sx * L * 0.5
		g.tube(Vector3(x, 0.09, 0.0), Vector3(x, rail_y, 0.0), 0.0125, 6, chrome)
		g.tube(Vector3(x, 0.09, -0.27), Vector3(x, 0.09, 0.27), 0.012, 6, chrome)
		for sz: float in [-1.0, 1.0]:
			# Castors: a swivel fork and a wheel.
			g.box(Vector3(x, 0.065, sz * 0.27), Vector3(0.03, 0.03, 0.03), chrome)
			g.tube(Vector3(x - 0.012, 0.035, sz * 0.27), Vector3(x + 0.012, 0.035, sz * 0.27), 0.033, 8, rubber)
	g.tube(Vector3(-L * 0.5 - 0.03, rail_y, 0.0), Vector3(L * 0.5 + 0.03, rail_y, 0.0), 0.014, 6, chrome)
	# A lower shelf bar.
	g.tube(Vector3(-L * 0.5, 0.25, 0.0), Vector3(L * 0.5, 0.25, 0.0), 0.01, 5, chrome)
	var story: Array = STORIES[variant % STORIES.size()]
	var mix := variant % 6
	var n := 12 + variant % 3
	for k in n:
		var x := -L * 0.5 + 0.08 + (L - 0.16) * (float(k) + 0.5) / float(n)
		var sp := pick_cut(variant * 101, k, mix)
		var col: Color = story[absi(hash([variant, k, "c"])) % story.size()]
		var yaw := (h01([variant, k, "yaw"]) - 0.5) * 0.25
		var xf := Transform3D(Basis(Vector3.UP, yaw), Vector3(x, rail_y + 0.06, 0.0))
		garment_at(g, xf, sp[0], col, sp[3], sp[1], minf(sp[2], 1.42), variant * 31 + k)
	# A cardboard price sign zip-tied to the upright.
	var sign_i := absi(hash([variant, "sign"])) % SIGNS.size()
	_card(g, Transform3D(Basis(), Vector3(L * 0.5 + 0.02, 1.25, 0.0)) * Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3.ZERO), SIGNS[sign_i], 0.42, 0.28, variant)
	_cache[key] = g
	return g


## A gridwall panel (0.6 m x 1.8 m) on two feet, hung with flat garments facing +z on hooks.
static func grid_wall(variant: int) -> Geo:
	var key := "wall_%d" % variant
	if _cache.has(key):
		return _cache[key]
	var g := Geo.new()
	var W := 1.2
	var H := 2.1
	_gridwall(g, Transform3D(Basis(), Vector3(0.0, 0.02, 0.0)), W, H)
	var chrome := kc(Color(0.75, 0.76, 0.78), K_CHROME)
	for sx: float in [-1.0, 1.0]:
		g.box(Vector3(sx * W * 0.5, 0.015, 0.0), Vector3(0.04, 0.03, 0.45), chrome)
	var story: Array = STORIES[(variant + 2) % STORIES.size()]
	var rows := 2
	for row in rows:
		for col_i in 2:
			var k := row * 2 + col_i
			var sp := pick_cut(variant * 57 + 3, k, (variant + 1) % 6)
			var cut: int = sp[0]
			if cut == Cut.GOWN:
				cut = Cut.DRESS
			var len := minf(float(sp[2]), 0.85)
			var col: Color = story[absi(hash([variant, k, "wc"])) % story.size()]
			var x := (float(col_i) - 0.5) * W * 0.5
			var y := H - 0.08 - float(row) * 1.0
			# A hook out of the wall, the garment turned to face the street.
			g.tube(Vector3(x, y, 0.0), Vector3(x, y, 0.16), 0.004, 4, chrome)
			garment_at(g, Transform3D(Basis(Vector3.UP, PI * 0.5).scaled(Vector3(1.0, 1.0, 0.9)), Vector3(x, y + 0.03, 0.12)), cut, col, sp[3], float(sp[1]) * 0.9, len, variant * 13 + k, true)
	_cache[key] = g
	return g


## A gridwall: a frame of 6 mm wire on a 76 mm square grid (the shader cuts the squares out of
## the K_GRID quad; the frame is real tube). In xf's xy plane, `w` wide, `h` tall, bottom at 0.
static func _gridwall(g: Geo, xf: Transform3D, w: float, h: float) -> void:
	var wire := kc(Color(0.20, 0.20, 0.21), K_GRID)
	var frame := kc(Color(0.20, 0.20, 0.21), K_PAINT)
	var q := [Vector3(-w * 0.5, 0.0, 0.0), Vector3(w * 0.5, 0.0, 0.0), Vector3(w * 0.5, h, 0.0), Vector3(-w * 0.5, h, 0.0)]
	var p: Array = []
	for v: Vector3 in q:
		p.append(xf * v)
	var nn := (xf.basis * Vector3.BACK).normalized()
	var t := [Vector2(0, h), Vector2(w, h), Vector2(w, 0), Vector2(0, 0)]
	g.flat_quad(p, wire, t, Vector2.ZERO, nn)
	g.flat_quad([p[1], p[0], p[3], p[2]], wire, [t[1], t[0], t[3], t[2]], Vector2.ZERO, -nn)
	g.tube(p[0], p[1], 0.008, 4, frame)
	g.tube(p[1], p[2], 0.008, 4, frame)
	g.tube(p[2], p[3], 0.008, 4, frame)
	g.tube(p[3], p[0], 0.008, 4, frame)


# --- Fabric ---------------------------------------------------------------------------------

## A slanted wooden display of fabric bolts (board-wound, 0.62 x 0.24 x 0.07 m) in two tiers,
## their ends to the street (+z), with a bin of tall rolls behind. Footprint 1.3 x 0.9 m.
static func bolt_stand(variant: int) -> Geo:
	var key := "bolts_%d" % variant
	if _cache.has(key):
		return _cache[key]
	var g := Geo.new()
	var wood := kc(Color(0.46, 0.33, 0.21), K_WOOD)
	var W := 1.3
	# Two sloped shelves on a frame.
	for tier in 2:
		var y0 := 0.45 + float(tier) * 0.42
		var z0 := 0.3 - float(tier) * 0.28
		var tilt := Basis(Vector3.RIGHT, -0.42)
		g.box(Vector3(0.0, y0, z0), Vector3(W, 0.025, 0.36), wood, tilt, Vector2.ZERO, false)
		g.box(Vector3(0.0, y0 - 0.07, z0 + 0.18), Vector3(W, 0.06, 0.02), wood)
		var n := 7
		for k in n:
			var x := -W * 0.5 + (W) * (float(k) + 0.5) / float(n)
			var pr := h01([variant, tier, k, "bp"])
			var p := P_SOLID if pr < 0.4 else (P_FLORAL if pr < 0.55 else (P_STRIPE if pr < 0.65 else (P_PLAID if pr < 0.75 else (P_SATIN if pr < 0.85 else (P_LACE if pr < 0.93 else P_LEOPARD)))))
			var story: Array = STORIES[(variant + tier * 3 + k) % STORIES.size()]
			var col: Color = story[absi(hash([variant, tier, k])) % story.size()]
			var b := tilt * Basis(Vector3.UP, (h01([variant, tier, k, "y"]) - 0.5) * 0.06)
			_bolt(g, Transform3D(b, Vector3(x, y0 + 0.07, z0)), col, p, 0.155, 0.36)
	# Legs.
	for sx: float in [-1.0, 1.0]:
		g.box(Vector3(sx * (W * 0.5 - 0.03), 0.48, 0.2), Vector3(0.04, 0.96, 0.04), wood)
		g.box(Vector3(sx * (W * 0.5 - 0.03), 0.62, -0.28), Vector3(0.04, 1.24, 0.04), wood)
		g.box(Vector3(sx * (W * 0.5 - 0.03), 0.06, -0.04), Vector3(0.05, 0.05, 0.6), wood)
	# A bin of tall rolls behind (on cardboard tubes), leaning back against the wall.
	var bin := kc(Color(0.30, 0.31, 0.32), K_PAINT)
	g.box(Vector3(0.0, 0.25, -0.55), Vector3(W, 0.5, 0.36), bin)
	var nr := 6
	for k in nr:
		var x := -W * 0.5 + 0.12 + (W - 0.24) * (float(k) + 0.5) / float(nr)
		var story: Array = STORIES[(variant * 2 + k) % STORIES.size()]
		var col: Color = story[absi(hash([variant, k, "r"])) % story.size()]
		var pr := h01([variant, k, "rp"])
		var p := P_SOLID if pr < 0.5 else (P_FLORAL if pr < 0.65 else (P_STRIPE if pr < 0.75 else (P_SATIN if pr < 0.9 else P_PLAID)))
		var lean := Basis(Vector3.RIGHT, -0.12 - 0.08 * h01([variant, k, "ln"])) * Basis(Vector3.FORWARD, (h01([variant, k, "lz"]) - 0.5) * 0.15)
		_roll(g, Transform3D(lean, Vector3(x, 0.05, -0.55)), col, p, 0.06 + 0.035 * h01([variant, k, "rr"]), 1.55)
	_cache[key] = g
	return g


## Big rolls of fabric stood upright on the pavement, leaning on each other against the wall
## (the iconic textile shop front): 10-14 rolls, 1.5-1.65 m, in a 1.6 m run. Back at z 0.
static func roll_row(variant: int) -> Geo:
	var key := "rolls_%d" % variant
	if _cache.has(key):
		return _cache[key]
	var g := Geo.new()
	var n := 10 + variant % 5
	var x := -0.78
	var k := 0
	while x < 0.78 and k < n:
		var r := 0.055 + 0.04 * h01([variant, k, "rr"])
		x += r
		var story: Array = STORIES[(variant + k) % STORIES.size()]
		var col: Color = story[absi(hash([variant, k, "rc"])) % story.size()]
		var pr := h01([variant, k, "rp"])
		var p := P_SOLID if pr < 0.45 else (P_FLORAL if pr < 0.6 else (P_STRIPE if pr < 0.68 else (P_SATIN if pr < 0.8 else (P_LACE if pr < 0.88 else (P_PLAID if pr < 0.95 else P_SEQUIN)))))
		var row := float(k % 2)
		var lean := Basis(Vector3.RIGHT, -0.10 - 0.06 * h01([variant, k, "ln"])) * Basis(Vector3.FORWARD, (h01([variant, k, "lz"]) - 0.5) * 0.12)
		_roll(g, Transform3D(lean, Vector3(x, 0.0, 0.16 + row * 0.2)), col, p, r, 1.45 + 0.2 * h01([variant, k, "h"]))
		x += r + 0.005
		k += 1
	_cache[key] = g
	return g


## A fabric roll on a cardboard tube: a cylinder along xf's y from 0 to `len`, the ends showing
## the wound layers (UV2.y 2 on the end caps: the shader draws the spiral).
static func _roll(g: Geo, xf: Transform3D, col: Color, p: int, r: float, len: float) -> void:
	var paint := kc(col, K_FABRIC)
	var tmp := Geo.new()
	tmp.tube(Vector3.ZERO, Vector3(0.0, len, 0.0), r, 12, paint, pat(p, 0.5))
	# End caps: the layers (fold 2 tells the shader), the tube's hole.
	tmp.disc(Vector3(0.0, len, 0.0), Vector3.UP, r, 12, paint, pat(p, 2.0))
	tmp.tube(Vector3(0.0, len - 0.02, 0.0), Vector3(0.0, len + 0.012, 0.0), r * 0.32, 8, kc(Color(0.62, 0.48, 0.30), K_CARDBOARD))
	tmp.disc(Vector3(0.0, len + 0.012, 0.0), Vector3.UP, r * 0.24, 8, kc(Color(0.05, 0.04, 0.03), K_RUBBER))
	g.append_xf(tmp, xf)


## A board-wound bolt: a rounded slab, `w` wide, `len` long (along z), 0.07 thick; ends show the
## fold (UV2.y 2).
static func _bolt(g: Geo, xf: Transform3D, col: Color, p: int, w: float, len: float) -> void:
	var paint := kc(col, K_FABRIC)
	var tmp := Geo.new()
	var th := 0.07
	var segs := 10
	var rows: Array = []
	for j in 2:
		var z := (float(j) - 0.5) * len
		var line: Array = []
		for i in segs:
			var a := TAU * float(i) / float(segs)
			# A stadium: flat top and bottom, round sides.
			var ca := cos(a)
			var sa := sin(a)
			var xr := signf(ca) * minf(absf(ca) * 1.6, 1.0) * w * 0.5
			line.append(Vector3(xr, sa * th * 0.5, z))
		rows.append(line)
	tmp.sheet(rows, true, func(_j: int, _i: int) -> Color: return paint,
		func(j: int, i: int) -> Vector2: return Vector2(float(i) / float(segs) * (w * 2.0 + th), float(j) * len),
		func(_j: int, _i: int) -> Vector2: return pat(p, 0.5),
		func(q: Vector3) -> Vector3: return Vector3(q.x, q.y, 0.0))
	for j in 2:
		var line: Array = rows[j]
		var ctr := Vector3(0.0, 0.0, (float(j) - 0.5) * len)
		var nn := Vector3(0.0, 0.0, -1.0 if j == 0 else 1.0)
		for i in segs:
			tmp.tri(ctr, line[i], line[(i + 1) % segs], nn, nn, nn, paint, Vector2(0.5, 0.5),
				Vector2((line[i] as Vector3).x / w + 0.5, (line[i] as Vector3).y / th + 0.5),
				Vector2((line[(i + 1) % segs] as Vector3).x / w + 0.5, (line[(i + 1) % segs] as Vector3).y / th + 0.5), pat(p, 3.0), nn)
	g.append_xf(tmp, xf)


# --- Mannequins -----------------------------------------------------------------------------

## A full-height fibreglass mannequin on a glass-foot stand, dressed. Variants: 0/3 a woman in a
## dress, 1/4 a woman in jeans and a top, 2/5 a man in a shirt and trousers; 0-2 white gloss,
## 3-5 matte black. Faces +z, feet at y 0.
static func mannequin(variant: int) -> Geo:
	var key := "manq_%d" % variant
	if _cache.has(key):
		return _cache[key]
	var g := Geo.new()
	var dark := variant >= 3
	var skin := kc(Color(0.08, 0.08, 0.09) if dark else Color(0.90, 0.89, 0.86), K_FIBRE)
	var kind := variant % 3
	var male := kind == 2
	var story: Array = STORIES[(variant * 2 + 1) % STORIES.size()]
	var c_top: Color = story[absi(hash([variant, "top"])) % story.size()]
	var c_bot: Color = story[absi(hash([variant, "bot"])) % story.size()]
	if kind == 1:
		c_bot = STORIES[0][absi(hash([variant, "j"])) % 3]
	var top := kc(c_top, K_CLOTH if kind != 1 else K_KNIT)
	var bot := kc(c_bot, K_DENIM if kind == 1 else K_CLOTH)
	var scale := 1.0 if not male else 1.07
	# Torso: a loft of ellipses from the hips to the neck (radii x across, z front-back).
	var torso := [
		[0.92, 0.17, 0.11], [0.98, 0.165, 0.105], [1.06, 0.135, 0.095], [1.14, 0.13, 0.09],
		[1.24, 0.155 if not male else 0.16, 0.11 if not male else 0.1], [1.33, 0.17, 0.1], [1.40, 0.19 if male else 0.17, 0.09], [1.44, 0.07, 0.055], [1.50, 0.05, 0.05]]
	var segs := 10
	var rows: Array = []
	for t: Array in torso:
		var line: Array = []
		for i in segs:
			var a := TAU * float(i) / float(segs)
			line.append(Vector3(cos(a) * float(t[1]), float(t[0]), sin(a) * float(t[2])) * scale)
		rows.append(line)
	var n_rows := rows.size()
	var row_cols: Array = []
	for j in n_rows:
		row_cols.append(skin if j >= n_rows - 2 else (top if kind == 0 or j >= 2 else bot))
	g.sheet(rows, true, func(j: int, _i: int) -> Color: return row_cols[j],
		func(j: int, i: int) -> Vector2: return Vector2(float(i) / float(segs) * 1.0, float(j) * 0.08),
		func(j: int, _i: int) -> Vector2: return pat(P_SOLID if kind != 0 else (P_FLORAL if variant == 0 else P_SOLID), 1.0 - float(j) / float(n_rows)),
		func(p: Vector3) -> Vector3: return Vector3(p.x, 0.0, p.z))
	# Head: an egg, faceless (the mannequin style), on the neck.
	var head := Geo.new()
	var hr: Array = []
	for j in 7:
		var phi := PI * float(j) / 6.0
		var line: Array = []
		for i in 10:
			var a := TAU * float(i) / 10.0
			var rr := sin(phi)
			line.append(Vector3(cos(a) * rr * 0.075, -cos(phi) * 0.115, sin(a) * rr * 0.09 + (0.01 if sin(a) > 0.0 else 0.0) * rr))
		hr.append(line)
	head.sheet(hr, true, func(_j: int, _i: int) -> Color: return skin, func(j: int, i: int) -> Vector2: return Vector2(i, j) * 0.05,
		func(_j: int, _i: int) -> Vector2: return Vector2.ZERO, func(p: Vector3) -> Vector3: return p)
	g.append_xf(head, Transform3D(Basis(), Vector3(0.0, 1.62, 0.01) * scale))
	# Arms: upper and fore arm tubes, a little bent, hands as flattened boxes.
	for s: float in [-1.0, 1.0]:
		var sh := Vector3(s * 0.185, 1.40, 0.0) * scale
		var el := Vector3(s * 0.23, 1.12, -0.02) * scale
		var wr := Vector3(s * 0.25, 0.86, 0.05) * scale
		var sleeve := top if (kind != 0 or variant % 2 == 1) else skin
		g.tube(sh, el, 0.045 * scale, 8, sleeve, pat(P_SOLID, 0.3), 0.038 * scale)
		g.tube(el, wr, 0.036 * scale, 8, skin if kind == 1 else sleeve, pat(P_SOLID, 0.6), 0.028 * scale)
		g.disc(sh, (sh - el).normalized(), 0.045 * scale, 8, sleeve)
		g.box(wr + Vector3(0.0, -0.07, 0.0) * scale, Vector3(0.025, 0.14, 0.07) * scale, skin, Basis(Vector3.FORWARD, s * 0.1))
	# Legs, or a dress's skirt over them.
	if kind == 0:
		var sk: Array = []
		for j in 5:
			var t := float(j) / 4.0
			var y := lerpf(0.94, 0.42, t)
			var line: Array = []
			for i in segs:
				var a := TAU * float(i) / float(segs)
				var r := lerpf(0.17, 0.27, t) + sin(a * 4.0 + 0.7) * 0.012 * t
				line.append(Vector3(cos(a) * r, y, sin(a) * r * 0.85) * scale)
			sk.append(line)
		g.sheet(sk, true, func(_j: int, _i: int) -> Color: return top,
			func(j: int, i: int) -> Vector2: return Vector2(float(i) / float(segs) * 1.4, float(j) * 0.13),
			func(j: int, _i: int) -> Vector2: return pat(P_FLORAL if variant == 0 else P_SOLID, 0.5 + float(j) * 0.12),
			func(p: Vector3) -> Vector3: return Vector3(p.x, 0.0, p.z))
		var hem: Array = sk[4]
		var hc := Vector3(0.0, (hem[0] as Vector3).y, 0.0)
		for i in segs:
			g.tri(hc, hem[i], hem[(i + 1) % segs], Vector3.DOWN, Vector3.DOWN, Vector3.DOWN, top, Vector2.ZERO, Vector2(0.1, 0), Vector2(0, 0.1), pat(P_SOLID, 1.0), Vector3.DOWN)
	for s: float in [-1.0, 1.0]:
		var hip := Vector3(s * 0.085, 0.93, 0.0) * scale
		var knee := Vector3(s * 0.09, 0.50, 0.01) * scale
		var ank := Vector3(s * 0.085, 0.09, 0.0) * scale
		var leg := skin if kind == 0 else bot
		g.tube(hip, knee, 0.075 * scale, 8, leg, pat(P_SOLID, 0.7), 0.052 * scale)
		g.tube(knee, ank, 0.052 * scale, 8, leg, pat(P_SOLID, 0.9), 0.038 * scale)
		g.box(ank + Vector3(0.0, -0.045, 0.05) * scale, Vector3(0.08, 0.07, 0.24) * scale, skin if kind == 0 else kc(Color(0.08, 0.07, 0.07), K_PLASTIC))
	# The stand: a rod from a heel into a round glass foot.
	var steel := kc(Color(0.8, 0.8, 0.82), K_CHROME)
	g.tube(Vector3(0.06, 0.0, -0.06), Vector3(0.06, 0.06, -0.06), 0.008, 5, steel)
	var foot := kc(Color(0.55, 0.62, 0.62), K_PLASTIC)
	g.tube(Vector3(0.0, 0.0, 0.0), Vector3(0.0, 0.012, 0.0), 0.2, 16, foot)
	g.disc(Vector3(0.0, 0.012, 0.0), Vector3.UP, 0.2, 16, foot)
	_cache[key] = g
	return g


# --- Hand trucks, cartons, tables -----------------------------------------------------------

## A two-wheel hand truck stood upright, loaded with cartons (and now and then garment bags on top),
## its nose plate at z 0 facing +z.
static func hand_truck(variant: int) -> Geo:
	var key := "truck_%d" % variant
	if _cache.has(key):
		return _cache[key]
	var g := Geo.new()
	var frame := kc([Color(0.75, 0.12, 0.10), Color(0.16, 0.18, 0.20), Color(0.86, 0.66, 0.12)][variant % 3], K_PAINT)
	var tilt := Basis(Vector3.RIGHT, -0.18)
	var tmp := Geo.new()
	for sx: float in [-1.0, 1.0]:
		tmp.tube(Vector3(sx * 0.2, 0.04, -0.05), Vector3(sx * 0.18, 1.22, -0.05), 0.012, 6, frame)
	tmp.tube(Vector3(-0.18, 1.22, -0.05), Vector3(-0.12, 1.32, -0.08), 0.012, 5, frame)
	tmp.tube(Vector3(0.18, 1.22, -0.05), Vector3(0.12, 1.32, -0.08), 0.012, 5, frame)
	tmp.tube(Vector3(-0.12, 1.32, -0.08), Vector3(0.12, 1.32, -0.08), 0.014, 6, kc(Color(0.06, 0.06, 0.06), K_RUBBER))
	for y: float in [0.4, 0.75, 1.05]:
		tmp.tube(Vector3(-0.2, y, -0.05), Vector3(0.2, y, -0.05), 0.008, 5, frame)
	tmp.box(Vector3(0.0, 0.01, 0.08), Vector3(0.38, 0.012, 0.2), kc(Color(0.6, 0.6, 0.62), K_CHROME))
	# Cartons stacked on the nose plate.
	var y := 0.02
	var k := 0
	while y < 1.0:
		var h := 0.24 + 0.14 * h01([variant, k, "bh"])
		var w := 0.36 + 0.08 * h01([variant, k, "bw"])
		_carton(tmp, Vector3((h01([variant, k, "bx"]) - 0.5) * 0.04, y, 0.08), Vector3(w, h, 0.3 + 0.06 * h01([variant, k, "bd"])), variant * 7 + k)
		y += h
		k += 1
	g.append_xf(tmp, Transform3D(tilt, Vector3(0.0, 0.0, 0.0)))
	# The wheels sit behind the frame's foot, on the ground.
	var rubber := kc(Color(0.06, 0.06, 0.06), K_RUBBER)
	for sx: float in [-1.0, 1.0]:
		var c := Vector3(sx * 0.26, 0.125, -0.1)
		g.tube(c - Vector3(0.035, 0, 0), c + Vector3(0.035, 0, 0), 0.125, 14, rubber)
		g.disc(c + Vector3(sx * 0.035, 0, 0), Vector3(sx, 0, 0), 0.125, 14, rubber)
		g.disc(c + Vector3(sx * 0.037, 0, 0), Vector3(sx, 0, 0), 0.06, 10, kc(Color(0.7, 0.7, 0.72), K_CHROME))
	g.tube(Vector3(-0.3, 0.125, -0.1), Vector3(0.3, 0.125, -0.1), 0.01, 5, kc(Color(0.6, 0.6, 0.6), K_CHROME))
	_cache[key] = g
	return g


## A corrugated carton, base centre `at`, packing tape across its top and down its ends.
static func _carton(g: Geo, at: Vector3, s: Vector3, seed_value: int) -> void:
	var tone := 0.85 + 0.2 * h01([seed_value, "ct"])
	var col := kc(Color(0.62, 0.47, 0.30) * tone, K_CARDBOARD)
	if h01([seed_value, "white"]) < 0.15:
		col = kc(Color(0.86, 0.84, 0.80), K_CARDBOARD)
	g.box(at + Vector3(0.0, s.y * 0.5, 0.0), s, col, Basis(), Vector2(h01([seed_value, "tape"]), 0.0))


## A stack of cartons (a delivery waiting at the door), 2-5 high, footprint ~0.9 x 0.6 m.
static func carton_stack(variant: int) -> Geo:
	var key := "cartons_%d" % variant
	if _cache.has(key):
		return _cache[key]
	var g := Geo.new()
	for col_i in 2:
		var y := 0.0
		var n := 2 + absi(hash([variant, col_i, "n"])) % 3
		for k in n:
			var h := 0.28 + 0.16 * h01([variant, col_i, k, "h"])
			var w := 0.4 + 0.1 * h01([variant, col_i, k, "w"])
			var d := 0.4 + 0.15 * h01([variant, col_i, k, "d"])
			var yaw := (h01([variant, col_i, k, "y"]) - 0.5) * 0.18
			var tmp := Geo.new()
			_carton(tmp, Vector3.ZERO, Vector3(w, h, d), variant * 13 + col_i * 5 + k)
			g.append_xf(tmp, Transform3D(Basis(Vector3.UP, yaw), Vector3((float(col_i) - 0.5) * 0.5, y, 0.0)))
			y += h
	# A clear garment bag of folded stock slumped on top now and then.
	if variant % 2 == 0:
		g.box(Vector3(0.1, 1.0, 0.05), Vector3(0.6, 0.12, 0.42), kc(Color(0.78, 0.80, 0.82), K_PLASTIC), Basis(Vector3.FORWARD, 0.06), Vector2.ZERO)
	_cache[key] = g
	return g


## A folding sale table of folded stock: stacks of folded tees and jeans (thin slabs in a colour
## story), a plastic bin of socks, a hand-lettered price card. 1.8 x 0.76 m, long side along x.
static func sale_table(variant: int) -> Geo:
	var key := "table_%d" % variant
	if _cache.has(key):
		return _cache[key]
	var g := Geo.new()
	var top := kc(Color(0.88, 0.87, 0.84), K_PLASTIC)
	var leg := kc(Color(0.26, 0.26, 0.28), K_PAINT)
	g.box(Vector3(0.0, 0.735, 0.0), Vector3(1.8, 0.04, 0.76), top, Basis(), Vector2.ZERO, false)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			g.tube(Vector3(sx * 0.82, 0.0, sz * 0.31), Vector3(sx * 0.8, 0.715, sz * 0.3), 0.012, 5, leg)
	var story: Array = STORIES[variant % STORIES.size()]
	var nx := 4
	var nz := 2
	for i in nx:
		for j in nz:
			var x := -0.9 + 0.15 + (1.8 - 0.3) * (float(i) + 0.5) / float(nx)
			var z := (float(j) - 0.5) * 0.36
			if i == nx - 1 and j == 0 and variant % 2 == 0:
				# A bin of socks.
				g.box(Vector3(x, 0.84, z), Vector3(0.34, 0.17, 0.3), kc(Color(0.15, 0.35, 0.65), K_PLASTIC))
				for k in 6:
					var sc: Color = story[absi(hash([variant, k, "sock"])) % story.size()]
					g.box(Vector3(x + (h01([variant, k, "sx"]) - 0.5) * 0.24, 0.93, z + (h01([variant, k, "sz"]) - 0.5) * 0.2), Vector3(0.08, 0.04, 0.1), kc(sc, K_KNIT), Basis(Vector3.UP, h01([variant, k]) * 3.0))
				continue
			var y := 0.755
			var n := 3 + absi(hash([variant, i, j, "n"])) % 6
			var denim := h01([variant, i, j, "dn"]) < 0.35
			var col: Color = (STORIES[0][absi(hash([variant, i, j])) % 3]) if denim else story[absi(hash([variant, i, j, "c"])) % story.size()]
			for k in n:
				var th := 0.035 if not denim else 0.045
				var yaw := (h01([variant, i, j, k, "fy"]) - 0.5) * 0.12
				var c := col.lerp(story[absi(hash([variant, i, j, k])) % story.size()], 0.0 if h01([variant, i, j, k, "mix"]) < 0.7 else 1.0)
				var b := Basis(Vector3.UP, yaw)
				g.box(Vector3(x, y + th * 0.5, z), Vector3(0.3, th, 0.26), kc(c, K_DENIM if denim else K_KNIT), b, pat(P_SOLID, 4.0))
				y += th
	_card(g, Transform3D(Basis(Vector3.RIGHT, -0.3), Vector3(0.0, 0.9, 0.36)), SIGNS[absi(hash([variant, "tsign"])) % SIGNS.size()], 0.5, 0.3, variant)
	_cache[key] = g
	return g


## A hand-lettered cardboard sign: a card `w` x `h` centred at xf's origin in its xy plane, the
## lettering on its +z face.
static func _card(g: Geo, xf: Transform3D, text: String, w: float, h: float, seed_value: int) -> void:
	var paper := kc(Color(0.94, 0.90, 0.80) if h01([seed_value, "card"]) < 0.6 else Color(0.98, 0.86, 0.20), K_PAPER)
	var tmp := Geo.new()
	tmp.box(Vector3.ZERO, Vector3(w, h, 0.006), paper, Basis(), Vector2.ZERO, false)
	var ink := kc(Color(0.75, 0.05, 0.05) if h01([seed_value, "ink"]) < 0.5 else Color(0.04, 0.04, 0.05), K_INK)
	_text(tmp, text, Transform3D(Basis(), Vector3(0.0, 0.0, 0.0045)), h * 0.42, w * 0.86, ink)
	g.append_xf(tmp, xf)


## Lettering (TextMesh outlines) into `g`, centred at xf's origin in its xy plane, facing +z.
static func _text(g: Geo, text: String, xf: Transform3D, height: float, max_w: float, col: Color) -> void:
	var key := "%s|%.3f" % [text, height]
	var geo: Array
	if _text_cache.has(key):
		geo = _text_cache[key]
	else:
		var tm := TextMesh.new()
		tm.text = text
		tm.font_size = 32
		tm.pixel_size = height / 32.0 * 1.4
		tm.depth = 0.0
		tm.curve_step = 6.0
		tm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tm.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		var arr := tm.get_mesh_arrays()
		var verts := PackedVector3Array()
		var idx := PackedInt32Array()
		if arr.size() > 0 and arr[Mesh.ARRAY_VERTEX] != null:
			verts = arr[Mesh.ARRAY_VERTEX]
			var ids = arr[Mesh.ARRAY_INDEX]
			if ids == null or (ids as PackedInt32Array).is_empty():
				for k in verts.size():
					idx.append(k)
			else:
				idx = ids
		var lo := INF
		var hi := -INF
		for v in verts:
			lo = minf(lo, v.x)
			hi = maxf(hi, v.x)
		geo = [verts, idx, maxf(hi - lo, 0.0)]
		_text_cache[key] = geo
	var verts: PackedVector3Array = geo[0]
	var idx: PackedInt32Array = geo[1]
	var squeeze := minf(1.0, max_w / maxf(float(geo[2]), 0.001))
	var nn := xf.basis.z.normalized()
	for k in range(0, idx.size() - 2, 3):
		var a := xf * (verts[idx[k]] * Vector3(squeeze, 1.0, 0.0))
		var b := xf * (verts[idx[k + 1]] * Vector3(squeeze, 1.0, 0.0))
		var c := xf * (verts[idx[k + 2]] * Vector3(squeeze, 1.0, 0.0))
		g.tri(a, b, c, nn, nn, nn, col, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, nn)


# --- The market alley -----------------------------------------------------------------------

## One market stall, 2.4 m along the alley (x) by 1.5 m deep (its back at z 0, the aisle at +z):
## a square-tube frame, a gridwall back hung with two rows of stock, a garment rack or a counter
## of folded stock in front, a tarp roof sloping down to the aisle, a hand-lettered sign, a stool.
static func stall(variant: int) -> Geo:
	var key := "stall_%d" % variant
	if _cache.has(key):
		return _cache[key]
	var g := Geo.new()
	var W := 2.4
	var D := 1.5
	var steel := kc(Color(0.30, 0.31, 0.33), K_PAINT)
	var tarp_c: Color = [Color(0.12, 0.30, 0.62), Color(0.85, 0.85, 0.82), Color(0.15, 0.42, 0.22), Color(0.80, 0.28, 0.12),
		Color(0.62, 0.10, 0.12), Color(0.85, 0.66, 0.14)][variant % 6]
	# Posts and the roof frame (back 2.55 m, front 2.25 m).
	for sx: float in [-1.0, 1.0]:
		g.box(Vector3(sx * W * 0.5, 1.275, 0.03), Vector3(0.04, 2.55, 0.04), steel)
		g.box(Vector3(sx * W * 0.5, 1.125, D), Vector3(0.04, 2.25, 0.04), steel)
		g.box(Vector3(sx * W * 0.5, 2.4, D * 0.5), Vector3(0.035, 0.035, D), steel, Basis(Vector3.RIGHT, atan2(0.3, D)))
	g.box(Vector3(0.0, 2.55, 0.03), Vector3(W, 0.035, 0.035), steel)
	g.box(Vector3(0.0, 2.25, D), Vector3(W, 0.035, 0.035), steel)
	# The tarp roof, sagging between the frame and hanging over the front as a valance.
	var tarp := kc(tarp_c, K_CANVAS)
	var rows: Array = []
	var nx := 6
	var nz := 4
	for j in nz + 1:
		var t := float(j) / float(nz)
		var line: Array = []
		for i in nx + 1:
			var s := float(i) / float(nx)
			var sag := sin(s * PI) * sin(t * PI) * 0.05
			line.append(Vector3((s - 0.5) * (W + 0.1), lerpf(2.6, 2.3, t) - sag, lerpf(-0.02, D + 0.08, t)))
		rows.append(line)
	g.sheet(rows, false, func(_j: int, _i: int) -> Color: return tarp,
		func(j: int, i: int) -> Vector2: return Vector2(float(i) / float(nx) * W, float(j) / float(nz) * D),
		func(_j: int, _i: int) -> Vector2: return pat(P_SOLID, 0.0),
		func(_p: Vector3) -> Vector3: return Vector3.UP)
	# The underside (a tarp is seen from below in an alley).
	var under: Array = []
	for line: Array in rows:
		var l2: Array = line.duplicate()
		l2.reverse()
		under.append(l2)
	g.sheet(under, false, func(_j: int, _i: int) -> Color: return kc(tarp_c * 0.85, K_CANVAS),
		func(j: int, i: int) -> Vector2: return Vector2(float(i) / float(nx) * W, float(j) / float(nz) * D),
		func(_j: int, _i: int) -> Vector2: return pat(P_SOLID, 0.0),
		func(_p: Vector3) -> Vector3: return Vector3.DOWN)
	var val := [Vector3(-W * 0.5 - 0.05, 2.3, D + 0.08), Vector3(W * 0.5 + 0.05, 2.3, D + 0.08), Vector3(W * 0.5 + 0.05, 2.08, D + 0.1), Vector3(-W * 0.5 - 0.05, 2.08, D + 0.1)]
	g.flat_quad(val, tarp, [Vector2(0, 0), Vector2(W, 0), Vector2(W, 0.22), Vector2(0, 0.22)], Vector2.ZERO, Vector3.BACK)
	g.flat_quad([val[1], val[0], val[3], val[2]], tarp, [Vector2(W, 0), Vector2(0, 0), Vector2(0, 0.22), Vector2(W, 0.22)], Vector2.ZERO, Vector3.FORWARD)
	# The back: two gridwall panels hung with stock.
	var story: Array = STORIES[(variant * 5 + 1) % STORIES.size()]
	_gridwall(g, Transform3D(Basis(), Vector3(-W * 0.25, 0.05, 0.06)), W * 0.5 - 0.04, 2.35)
	_gridwall(g, Transform3D(Basis(), Vector3(W * 0.25, 0.05, 0.06)), W * 0.5 - 0.04, 2.35)
	var chrome := kc(Color(0.75, 0.76, 0.78), K_CHROME)
	for row in 2:
		for k in 4:
			var x := -W * 0.5 + 0.3 + (W - 0.6) * float(k) / 3.0
			var y := 2.32 - float(row) * 1.05
			var sp := pick_cut(variant * 77 + row, k, (variant + row) % 6)
			var cut: int = sp[0]
			if cut == Cut.GOWN:
				cut = Cut.DRESS
			var col: Color = story[absi(hash([variant, row, k, "sc"])) % story.size()]
			g.tube(Vector3(x, y, 0.06), Vector3(x, y, 0.2), 0.004, 4, chrome)
			garment_at(g, Transform3D(Basis(Vector3.UP, PI * 0.5).scaled(Vector3(1.0, 1.0, 0.9)), Vector3(x, y + 0.03, 0.16)), cut, col, sp[3], float(sp[1]) * 0.86, minf(float(sp[2]), 0.92), variant * 19 + row * 5 + k, true)
	# Front: a short rail of hanging stock, or a counter of folded stock.
	if variant % 2 == 0:
		var rail_y := 1.75
		g.tube(Vector3(-W * 0.5 + 0.05, rail_y, D - 0.15), Vector3(W * 0.5 - 0.05, rail_y, D - 0.15), 0.013, 6, chrome)
		var n := 12
		for k in n:
			var x := -W * 0.5 + 0.15 + (W - 0.3) * (float(k) + 0.5) / float(n)
			var sp := pick_cut(variant * 41, k, (variant + 3) % 6)
			var col: Color = story[absi(hash([variant, k, "fc"])) % story.size()]
			garment_at(g, Transform3D(Basis(Vector3.UP, (h01([variant, k, "fy"]) - 0.5) * 0.3), Vector3(x, rail_y + 0.06, D - 0.15)), sp[0], col, sp[3], sp[1], minf(float(sp[2]), 1.25), variant * 23 + k)
	else:
		g.box(Vector3(0.0, 0.42, D - 0.35), Vector3(W - 0.2, 0.84, 0.5), kc(Color(0.82, 0.80, 0.76), K_PLASTIC))
		for k in 6:
			var x := -W * 0.5 + 0.3 + (W - 0.6) * float(k) / 5.0
			var y := 0.86
			var n := 2 + absi(hash([variant, k, "cn"])) % 5
			var col: Color = story[absi(hash([variant, k, "cc"])) % story.size()]
			for q in n:
				g.box(Vector3(x, y + 0.02, D - 0.35), Vector3(0.28, 0.04, 0.3), kc(col.lerp(story[(k + q) % story.size()], 0.0 if q % 3 else 1.0), K_KNIT), Basis(Vector3.UP, (h01([variant, k, q]) - 0.5) * 0.1), pat(P_SOLID, 4.0))
				y += 0.04
	# The sign over the front.
	_card(g, Transform3D(Basis(), Vector3(0.0, 2.0, D + 0.12)), SIGNS[absi(hash([variant, "ssign"])) % SIGNS.size()], 0.8, 0.26, variant + 9)
	# A stool for the seller.
	var stool := kc(Color(0.15, 0.15, 0.16), K_PLASTIC)
	g.box(Vector3(W * 0.36, 0.45, 0.45), Vector3(0.32, 0.03, 0.32), stool)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			g.tube(Vector3(W * 0.36 + sx * 0.13, 0.0, 0.45 + sz * 0.13), Vector3(W * 0.36 + sx * 0.12, 0.44, 0.45 + sz * 0.12), 0.01, 4, stool)
	_cache[key] = g
	return g


## A tarp strung across the alley overhead: `span` metres across x, `len` along z, sagging, its
## corners tied off (both faces). Height of its edges at y 0 (the placement lifts it).
static func overhead_tarp(variant: int, span: float, len: float) -> ArrayMesh:
	var key := "tarp_%d_%.1f_%.1f" % [variant, span, len]
	if _cache.has(key):
		return _cache[key]
	var g := Geo.new()
	var tarp_c: Color = [Color(0.12, 0.30, 0.62), Color(0.88, 0.88, 0.86), Color(0.70, 0.18, 0.12), Color(0.18, 0.40, 0.25),
		Color(0.90, 0.55, 0.12), Color(0.35, 0.36, 0.40)][variant % 6]
	var nx := 8
	var nz := 4
	var rows: Array = []
	for j in nz + 1:
		var t := float(j) / float(nz)
		var line: Array = []
		for i in nx + 1:
			var s := float(i) / float(nx)
			var sag := sin(s * PI) * (0.35 + 0.15 * sin(t * PI))
			line.append(Vector3((s - 0.5) * span, -sag, (t - 0.5) * len))
		rows.append(line)
	for face: float in [1.0, -1.0]:
		var rr: Array = rows if face > 0.0 else []
		if face < 0.0:
			for line: Array in rows:
				var l2: Array = line.duplicate()
				l2.reverse()
				rr.append(l2)
		var col := kc(tarp_c * (1.0 if face > 0.0 else 0.8), K_CANVAS)
		var up := Vector3.UP * face
		g.sheet(rr, false, func(_j: int, _i: int) -> Color: return col,
			func(j: int, i: int) -> Vector2: return Vector2(float(i) / float(nx) * span, float(j) / float(nz) * len),
			func(_j: int, _i: int) -> Vector2: return pat(P_SOLID, 0.0),
			func(_p: Vector3) -> Vector3: return up)
	# Ropes to the walls at the four corners.
	var rope := kc(Color(0.75, 0.70, 0.55), K_CANVAS)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var a := Vector3(sx * span * 0.5, 0.0, sz * len * 0.5)
			g.tube(a, a + Vector3(sx * 0.4, 0.25, 0.0), 0.006, 3, rope)
	var m := g.commit()
	_cache[key] = m
	return m


## A string of bulbs across the alley: a sagging wire `span` long along x with a bulb every 0.6 m
## (K_BULB, lit after dark).
static func bulb_string(span: float) -> ArrayMesh:
	var key := "bulbs_%.1f" % span
	if _cache.has(key):
		return _cache[key]
	var g := Geo.new()
	var wire := kc(Color(0.05, 0.05, 0.05), K_RUBBER)
	var bulb := kc(Color(1.0, 0.86, 0.6), K_BULB)
	var n := maxi(2, int(span / 0.6))
	var prev := Vector3(-span * 0.5, 0.0, 0.0)
	for k in n + 1:
		var s := float(k) / float(n)
		var p := Vector3((s - 0.5) * span, -sin(s * PI) * 0.45, 0.0)
		if k > 0:
			g.tube(prev, p, 0.004, 3, wire)
		if k > 0 and k < n:
			g.tube(p, p + Vector3(0, -0.06, 0), 0.012, 5, wire)
			# The bulb: a small double cone (octahedral globe).
			var c := p + Vector3(0.0, -0.1, 0.0)
			for i in 6:
				var a0 := TAU * float(i) / 6.0
				var a1 := TAU * float(i + 1) / 6.0
				var q0 := c + Vector3(cos(a0), 0.0, sin(a0)) * 0.035
				var q1 := c + Vector3(cos(a1), 0.0, sin(a1)) * 0.035
				for e: float in [1.0, -1.0]:
					var tip := c + Vector3(0.0, 0.045 * e, 0.0)
					var nn := (q0 + q1 - c * 2.0).normalized() + Vector3.UP * e * 0.5
					g.tri(tip, q0, q1, nn.normalized(), nn.normalized(), nn.normalized(), bulb, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, nn)
		prev = p
	var m := g.commit()
	_cache[key] = m
	return m


## A vinyl banner (the trade's big street banners): `w` x `h`, both faces lettered, its top edge at
## y 0, in the xy plane. Colours by variant.
static func banner(variant: int, text: String, w: float, h: float) -> ArrayMesh:
	var key := "banner_%d_%s_%.1f" % [variant, text, w]
	if _cache.has(key):
		return _cache[key]
	var g := Geo.new()
	var cols := [[Color(0.80, 0.08, 0.08), Color(0.98, 0.96, 0.90)], [Color(0.98, 0.84, 0.10), Color(0.08, 0.08, 0.10)],
		[Color(0.98, 0.97, 0.94), Color(0.05, 0.25, 0.65)], [Color(0.06, 0.06, 0.08), Color(0.98, 0.82, 0.20)]]
	var pc: Array = cols[variant % cols.size()]
	var bg := kc(pc[0], K_CANVAS)
	var ink := kc(pc[1], K_INK)
	var q := [Vector3(-w * 0.5, 0.0, 0.0), Vector3(w * 0.5, 0.0, 0.0), Vector3(w * 0.5, -h, 0.0), Vector3(-w * 0.5, -h, 0.0)]
	g.flat_quad(q, bg, [Vector2(0, 0), Vector2(w, 0), Vector2(w, h), Vector2(0, h)], Vector2.ZERO, Vector3.BACK)
	g.flat_quad([q[1], q[0], q[3], q[2]], bg, [Vector2(w, 0), Vector2(0, 0), Vector2(0, h), Vector2(w, h)], Vector2.ZERO, Vector3.FORWARD)
	_text(g, text, Transform3D(Basis(), Vector3(0.0, -h * 0.5, 0.004)), h * 0.5, w * 0.9, ink)
	_text(g, text, Transform3D(Basis(Vector3.UP, PI), Vector3(0.0, -h * 0.5, -0.004)), h * 0.5, w * 0.9, ink)
	for sx: float in [-1.0, 1.0]:
		g.disc(Vector3(sx * (w * 0.5 - 0.06), -0.06, 0.003), Vector3.BACK, 0.015, 6, kc(Color(0.7, 0.7, 0.7), K_CHROME))
	var m := g.commit()
	_cache[key] = m
	return m


## A frontage SET: one shop's goods out on the pavement, ~6 m along x (the shop front at z 0,
## the street at +z), composed from the pieces above by a theme (clothes, fabric, bridal and party,
## denim, a mix), so a face of the street is a handful of draws however long it is. Returns
## {"mesh", "boxes": [[size, centre]] (collision, set space), "length"}.
const SET_VARIANTS := 10
const SET_THEMES := ["clothes", "fabric", "party", "denim", "mix", "clothes", "fabric", "mix", "party", "denim"]


static func frontage(variant: int) -> Dictionary:
	var key := "set_%d" % variant
	if _cache.has(key):
		return _cache[key]
	var g := Geo.new()
	var boxes: Array = []
	var theme: String = SET_THEMES[variant % SET_THEMES.size()]
	var plan: Array = []
	match theme:
		"clothes":
			plan = ["wall", "rack", "manq", "rack", "table"]
		"fabric":
			plan = ["rolls", "bolts", "rolls", "truck"]
		"party":
			plan = ["manq3", "rack_party", "wall"]
		"denim":
			plan = ["table_denim", "rack_denim", "manq_jeans", "cartons"]
		_:
			plan = ["rack", "rolls", "manq", "table", "truck"]
	# A shop's order of things is shuffled a little by the variant.
	if variant >= 5 and plan.size() > 2:
		var a: String = plan[0]
		plan[0] = plan[1]
		plan[1] = a
	var x := 0.0
	for k in plan.size():
		var item: String = plan[k]
		var v := absi(hash([variant, k, item]))
		var w := 1.0
		match item:
			"wall":
				w = 1.25
				g.append_xf(grid_wall(v % WALL_VARIANTS), Transform3D(Basis(Vector3.RIGHT, -0.08), Vector3(x + w * 0.5, 0.0, 0.22)))
				boxes.append([Vector3(1.2, 2.1, 0.4), Vector3(x + w * 0.5, 1.05, 0.25)])
			"rack", "rack_party", "rack_denim":
				w = 1.65
				var rv := v % RACK_VARIANTS
				if item == "rack_party":
					rv = 5
				elif item == "rack_denim":
					rv = 0
				g.append_xf(rack(rv), Transform3D(Basis(Vector3.UP, (h01([variant, k, "ry"]) - 0.5) * 0.12), Vector3(x + w * 0.5, 0.0, 0.5)))
				boxes.append([Vector3(1.6, 1.75, 0.6), Vector3(x + w * 0.5, 0.88, 0.5)])
			"manq", "manq_jeans", "manq3":
				var n := 3 if item == "manq3" else 2
				w = 0.8 * float(n) + 0.1
				for q in n:
					var mv := (v + q) % MANNEQUIN_VARIANTS
					if item == "manq_jeans":
						mv = 1 + 3 * (q % 2)
					elif item == "manq3":
						mv = [0, 3, 0][q]
					var yaw := (h01([variant, k, q, "my"]) - 0.5) * 0.7
					g.append_xf(mannequin(mv), Transform3D(Basis(Vector3.UP, yaw), Vector3(x + 0.45 + 0.8 * float(q), 0.0, 0.55)))
					boxes.append([Vector3(0.45, 1.75, 0.45), Vector3(x + 0.45 + 0.8 * float(q), 0.88, 0.55)])
			"table", "table_denim":
				w = 1.9
				var tv := v % TABLE_VARIANTS
				if item == "table_denim":
					tv = 0
				g.append_xf(sale_table(tv), Transform3D(Basis(), Vector3(x + w * 0.5, 0.0, 0.55)))
				boxes.append([Vector3(1.8, 0.95, 0.76), Vector3(x + w * 0.5, 0.48, 0.55)])
			"rolls":
				w = 1.7
				g.append_xf(roll_row(v % ROLL_VARIANTS), Transform3D(Basis(), Vector3(x + w * 0.5, 0.0, 0.05)))
				boxes.append([Vector3(1.6, 1.6, 0.6), Vector3(x + w * 0.5, 0.8, 0.35)])
			"bolts":
				w = 1.45
				g.append_xf(bolt_stand(v % BOLT_VARIANTS), Transform3D(Basis(), Vector3(x + w * 0.5, 0.0, 0.8)))
				boxes.append([Vector3(1.35, 1.3, 1.25), Vector3(x + w * 0.5, 0.65, 0.65)])
			"truck":
				w = 0.8
				g.append_xf(hand_truck(v % TRUCK_VARIANTS), Transform3D(Basis(Vector3.UP, (h01([variant, k, "ty"]) - 0.5) * 0.5), Vector3(x + w * 0.5, 0.0, 0.45)))
				boxes.append([Vector3(0.6, 1.3, 0.5), Vector3(x + w * 0.5, 0.65, 0.4)])
			"cartons":
				w = 1.2
				g.append_xf(carton_stack(v % TRUCK_VARIANTS), Transform3D(Basis(), Vector3(x + w * 0.5, 0.0, 0.4)))
				boxes.append([Vector3(1.1, 1.1, 0.55), Vector3(x + w * 0.5, 0.55, 0.4)])
		x += w + 0.15
	# Centre the set on x 0.
	var out := Geo.new()
	out.append_xf(g, Transform3D(Basis(), Vector3(-x * 0.5, 0.0, 0.0)))
	for b: Array in boxes:
		b[1] = (b[1] as Vector3) - Vector3(x * 0.5, 0.0, 0.0)
	var res := {"mesh": out.commit(), "boxes": boxes, "length": x, "tris": out.v.size() / 3}
	_cache[key] = res
	return res


## A market stall's mesh (cached).
static func stall_mesh(variant: int) -> ArrayMesh:
	var key := "stall_mesh_%d" % variant
	if not _cache.has(key):
		_cache[key] = stall(variant).commit()
	return _cache[key]


## Every mesh built once (the loading screen), so the first district street does not stall; the
## material to draw once through a MultiMesh.
static func warm() -> Array:
	for v in SET_VARIANTS:
		frontage(v)
	for v in STALL_VARIANTS:
		stall_mesh(v)
	for v in 6:
		overhead_tarp(v, 6.6, 4.0)
	bulb_string(6.6)
	return [material()]


## Triangles in a mesh (probes and checks).
static func tris(m: Mesh) -> int:
	var t := 0
	for s in m.get_surface_count():
		t += (m.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return t
