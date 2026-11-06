class_name SeaLifeMesh
extends RefCounted
## The meshes of the life in the water (SeaLife, scripts/world/sea_life.gd), all built in code at
## real size: a bottlenose dolphin (2.6 m), a California sea lion (1.9 m, lying on its belly), a
## brown pelican (2.1 m span, in flight with the head drawn back onto the shoulders), a grey whale
## (13 m), the harbour's navigation buoy (a 2.7 m float with a deck, a lattice tower, its lantern
## and radar reflector) and the spray (a stack of camera-facing quads the shader flies). Each
## animal has a NEAR and a FAR level (the same profile with fewer rings and sides).
##
## Frame: -Z forward (the nose), +Y up, +X the animal's right; metres. What a vertex is rides in
## COLOR.a as code / 16 (`P_*`, mirrored by shaders/sea_life.gdshader); COLOR.rgb is the LINEAR
## albedo. UV.x is the fraction of the body's length from the nose (0) to the tail (1), UV.y the
## part's own number (the pelican's span fraction from the shoulder, 0..1). Built once, cached.

const P_BODY := 0
const P_FIN := 1
const P_JAW := 2
const P_WING := 3
const P_BILL := 4
const P_PAINT := 5
const P_LAMP := 6
const P_DECK := 7
const P_METAL := 8
const P_EYE := 9

## Ring sides and length stations of the lofts per level (near, far).
const SIDES := [18, 7]
const STATIONS := [34, 9]

## The species' sizes the shader and SeaLife need (metres, in the mesh's frame).
const DOLPHIN_LEN := 2.6
const DOLPHIN_HINGE := 0.15 # z where the tail stock starts to beat
const SEA_LION_LEN := 1.9
const SEA_LION_NECK := -0.5 # z of the neck pivot (the head is -Z of it)
const SEA_LION_NECK_Y := 0.2
const PELICAN_SHOULDER := Vector3(0.1, 0.07, -0.12)
const PELICAN_WRIST := 0.55 # x of the wrist
const PELICAN_SPAN := 1.06 # x of the wing tip (half the span)
const WHALE_LEN := 13.0
const WHALE_HINGE := 2.5
const BUOY_DECK_Y := 0.62 # the deck over the float's waterline (y 0 is the waterline)
const BUOY_DECK_R := 1.38

static var _cache: Dictionary = {}


## The mesh of `name` ("dolphin", "sea_lion", "pelican", "whale", "buoy", "spray") at level 0 or 1.
static func mesh(name: String, level: int = 0) -> ArrayMesh:
	var key := "%s:%d" % [name, level]
	if _cache.has(key):
		return _cache[key]
	var g := Geo.new()
	match name:
		"dolphin":
			_dolphin(g, level)
		"sea_lion":
			_sea_lion(g, level)
		"pelican":
			_pelican(g, level)
		"whale":
			_whale(g, level)
		"buoy":
			_buoy(g, level)
		"spray":
			_spray(g)
	var m := g.commit(name != "spray")
	_cache[key] = m
	return m


static func triangles(m: ArrayMesh) -> int:
	var n := 0
	for s in m.get_surface_count():
		n += m.surface_get_array_index_len(s) / 3
	return n


## Builds every mesh (the loading screen; a few ms each).
static func warm() -> void:
	for name in ["dolphin", "sea_lion", "pelican", "whale", "buoy"]:
		mesh(name, 0)
		mesh(name, 1)
	mesh("spray", 0)


# --- the builder -------------------------------------------------------------------------------

class Geo:
	var v := PackedVector3Array()
	var c := PackedColorArray()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var idx := PackedInt32Array()

	func add(p: Vector3, col: Color, t: Vector2) -> int:
		v.append(p)
		c.append(col)
		uv.append(t)
		return v.size() - 1

	## A triangle facing away from `ref` (a point inside the part).
	func tri(a: int, b: int, d: int, ref: Vector3) -> void:
		var fn := (v[b] - v[a]).cross(v[d] - v[a])
		var cen := (v[a] + v[b] + v[d]) / 3.0
		if fn.dot(cen - ref) < 0.0:
			var t := b
			b = d
			d = t
		# Godot's front faces are CLOCKWISE seen from the front: stored the other way round.
		idx.append(a)
		idx.append(d)
		idx.append(b)

	func quad(a: int, b: int, d: int, e: int, ref: Vector3) -> void:
		tri(a, b, d, ref)
		tri(a, d, e, ref)

	## Normals: area-weighted over the triangles sharing a vertex (the lofts are indexed, so they
	## shade smooth; fins, boxes and caps have vertices of their own, so they shade flat-ish).
	func commit(lit: bool) -> ArrayMesh:
		var n := PackedVector3Array()
		n.resize(v.size())
		for i in range(0, idx.size(), 3):
			var a := idx[i]
			var b := idx[i + 1]
			var d := idx[i + 2]
			var fn := (v[d] - v[a]).cross(v[b] - v[a])
			n[a] += fn
			n[b] += fn
			n[d] += fn
		for i in n.size():
			n[i] = n[i].normalized() if n[i].length_squared() > 1e-14 else Vector3.UP
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = v
		arr[Mesh.ARRAY_NORMAL] = n
		arr[Mesh.ARRAY_COLOR] = c
		arr[Mesh.ARRAY_TEX_UV] = uv
		if uv2.size() == v.size():
			arr[Mesh.ARRAY_TEX_UV2] = uv2
		arr[Mesh.ARRAY_INDEX] = idx
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		if not lit:
			m.custom_aabb = AABB(Vector3(-6, -1, -6), Vector3(12, 14, 12))
		return m


static func _col(rgb: Color, part: int) -> Color:
	return Color(rgb.r, rgb.g, rgb.b, float(part) / 16.0)


## Catmull-Rom through keys [[t, a, b, c, ...], ...] at t (each value column interpolated).
static func _keys(keys: Array, t: float) -> Array:
	var n := keys.size()
	var i := 0
	while i < n - 2 and float(keys[i + 1][0]) < t:
		i += 1
	var k1: Array = keys[i]
	var k2: Array = keys[i + 1]
	var k0: Array = keys[maxi(i - 1, 0)]
	var k3: Array = keys[mini(i + 2, n - 1)]
	var u := clampf((t - float(k1[0])) / maxf(float(k2[0]) - float(k1[0]), 1e-5), 0.0, 1.0)
	var out := []
	for j in range(1, k1.size()):
		var p0 := float(k0[j])
		var p1 := float(k1[j])
		var p2 := float(k2[j])
		var p3 := float(k3[j])
		var u2 := u * u
		var u3 := u2 * u
		var val := 0.5 * (2.0 * p1 + (p2 - p0) * u + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * u2 + (3.0 * p1 - p0 - 3.0 * p2 + p3) * u3)
		# Never overshoot below zero for a radius (the columns after cy are radii).
		out.append(val if j == 1 else maxf(val, 0.002))
	return out


## A closed loft along -Z..+Z: keys [[t, cy, rx, ry]] with t 0 at z0 (the nose) to 1 at z0 + len,
## stations rings of `sides` vertices (angle 0 on top, going round through the right side), both
## ends closed by a point. `paint(t, ang)` gives each vertex's albedo; `part(t, ang)` its code.
## `squash` (optional: [[t, top, bottom]]) makes a section flatter on top or under (a belly).
static func _loft(g: Geo, keys: Array, z0: float, length: float, stations: int, sides: int, paint: Callable, part: Callable, spacing: Callable = Callable()) -> void:
	var rings: Array = []
	for s in stations + 1:
		var tt := float(s) / float(stations)
		var t: float = spacing.call(tt) if spacing.is_valid() else tt
		var k := _keys(keys, t)
		var cy: float = k[0]
		var rx: float = k[1]
		var ry: float = k[2]
		var ring: Array = []
		var z := z0 + t * length
		if s == 0 or s == stations:
			ring.append(g.add(Vector3(0.0, cy, z), _col(paint.call(t, 0.0), part.call(t, 0.0)), Vector2(t, 0.0)))
		else:
			for j in sides:
				var ang := TAU * float(j) / float(sides)
				# Sections are superellipses a little squarer than an ellipse (a body, not a pipe).
				var sx := sin(ang)
				var sy := cos(ang)
				var px := signf(sx) * pow(absf(sx), 0.85) * rx
				var py := signf(sy) * pow(absf(sy), 0.9) * ry
				ring.append(g.add(Vector3(px, cy + py, z), _col(paint.call(t, ang), part.call(t, ang)), Vector2(t, 0.0)))
		rings.append(ring)
	for s in stations:
		var a: Array = rings[s]
		var b: Array = rings[s + 1]
		var ca := _ring_centre(g, a)
		var cb := _ring_centre(g, b)
		if a.size() == 1:
			for j in sides:
				g.tri(a[0], b[(j + 1) % sides], b[j], cb)
		elif b.size() == 1:
			for j in sides:
				g.tri(a[j], a[(j + 1) % sides], b[0], ca)
		else:
			var ref := (ca + cb) * 0.5
			for j in sides:
				var j2 := (j + 1) % sides
				g.quad(a[j], a[j2], b[j2], b[j], ref)


## A fin: a flat outline (points in the fin's own (a, b) plane, metres) at `origin`, spanned by
## the unit axes `ax` and `bx`, `thick` metres through at its root thinning to an edge at its
## rim, drawn both sides with a bevelled edge. `taper` points (b direction 0..1) are thick at the
## root line b = 0. Faces flat-ish: each side's vertices are its own.
static func _fin(g: Geo, outline: PackedVector2Array, origin: Vector3, ax: Vector3, bx: Vector3, thick: float, col: Color, part: int, t_along: float = 0.5, span_uv: bool = false) -> void:
	var nrm := ax.cross(bx).normalized()
	var tris := Geometry2D.triangulate_polygon(outline)
	if tris.is_empty():
		return
	var maxb := 0.001
	for p in outline:
		maxb = maxf(maxb, absf(p.y))
	for side: float in [1.0, -1.0]:
		var base := g.v.size()
		for p in outline:
			var th := thick * 0.5 * (1.0 - clampf(absf(p.y) / maxb, 0.0, 1.0) * 0.85)
			var w := origin + ax * p.x + bx * p.y + nrm * th * side
			g.add(w, _col(col, part), Vector2(t_along, (p.x if span_uv else 0.0)))
		for i in range(0, tris.size(), 3):
			var cen := (g.v[base + tris[i]] + g.v[base + tris[i + 1]] + g.v[base + tris[i + 2]]) / 3.0
			g.tri(base + tris[i], base + tris[i + 1], base + tris[i + 2], cen - nrm * side)
	# The rim, joining the two faces round the outline.
	var n := outline.size()
	var top := g.v.size() - 2 * n
	var mid := Vector2.ZERO
	for p in outline:
		mid += p
	mid /= float(n)
	var fc := origin + ax * mid.x + bx * mid.y
	for i in n:
		var i2 := (i + 1) % n
		g.quad(top + i, top + n + i, top + n + i2, top + i2, fc)


## An upright cylinder (or a cone when r1 differs from r0) from y0 to y1 at centre c (XZ).
static func _cyl(g: Geo, c: Vector3, r0: float, r1: float, y0: float, y1: float, sides: int, col: Color, part: int, caps: bool = true) -> void:
	var base := g.v.size()
	for j in sides + 1:
		var a := TAU * float(j) / float(sides)
		var d := Vector3(sin(a), 0.0, cos(a))
		g.add(c + d * r0 + Vector3(0, y0, 0), _col(col, part), Vector2(float(j) / float(sides), 0.0))
		g.add(c + d * r1 + Vector3(0, y1, 0), _col(col, part), Vector2(float(j) / float(sides), 1.0))
	var ref := c + Vector3(0, (y0 + y1) * 0.5, 0)
	for j in sides:
		var a0 := base + j * 2
		g.quad(a0, a0 + 1, a0 + 3, a0 + 2, ref)
	if caps:
		for yy: float in [y0, y1]:
			var rr := r0 if yy == y0 else r1
			if rr < 0.001:
				continue
			var ctr := g.add(c + Vector3(0, yy, 0), _col(col, part), Vector2(0.5, 0.5))
			var ring := g.v.size()
			for j in sides:
				var a := TAU * float(j) / float(sides)
				g.add(c + Vector3(sin(a) * rr, yy, cos(a) * rr), _col(col, part), Vector2(0.5, 0.5))
			for j in sides:
				g.tri(ctr, ring + j, ring + (j + 1) % sides, ref)


## A straight round bar from a to b (a tube of `sides` sides, no caps).
static func _bar(g: Geo, a: Vector3, b: Vector3, r: float, sides: int, col: Color, part: int) -> void:
	var ax := (b - a).normalized()
	var u := ax.cross(Vector3.UP if absf(ax.y) < 0.9 else Vector3.RIGHT).normalized()
	var w := ax.cross(u)
	var base := g.v.size()
	for j in sides:
		var ang := TAU * float(j) / float(sides)
		var d := (u * cos(ang) + w * sin(ang)) * r
		g.add(a + d, _col(col, part), Vector2(0.0, 0.0))
		g.add(b + d, _col(col, part), Vector2(1.0, 0.0))
	for j in sides:
		var j2 := (j + 1) % sides
		g.quad(base + j * 2, base + j2 * 2, base + j2 * 2 + 1, base + j * 2 + 1, (a + b) * 0.5)


## A box from its centre, half size and basis (flat faces).
static func _box(g: Geo, c: Vector3, h: Vector3, basis: Basis, col: Color, part: int) -> void:
	var faces := [
		[Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)], [Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0)],
		[Vector3(0, 1, 0), Vector3(0, 0, 1), Vector3(1, 0, 0)], [Vector3(0, -1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)],
		[Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 1, 0)], [Vector3(0, 0, -1), Vector3(0, 1, 0), Vector3(1, 0, 0)],
	]
	for f in faces:
		var n: Vector3 = f[0]
		var a: Vector3 = f[1]
		var b: Vector3 = f[2]
		var base := g.v.size()
		for k: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			var p := Vector3(n.x * h.x, n.y * h.y, n.z * h.z) + Vector3(a.x * h.x, a.y * h.y, a.z * h.z) * k.x + Vector3(b.x * h.x, b.y * h.y, b.z * h.z) * k.y
			g.add(c + basis * p, _col(col, part), Vector2(0.5, 0.5))
		g.quad(base, base + 1, base + 2, base + 3, c)


# --- the dolphin -------------------------------------------------------------------------------

## A bottlenose: a short thick beak, the melon over it, the body deepest a third back, the tail
## stock flattened side to side, flukes swept back, a falcate dorsal fin and two pectorals.
## Countershaded: a dark grey cape over a mid-grey flank and a pale belly.
static func _dolphin(g: Geo, level: int) -> void:
	var L := DOLPHIN_LEN
	var z0 := -L * 0.5
	var keys := [
		[0.0, -0.02, 0.012, 0.012], [0.035, -0.03, 0.035, 0.03], [0.07, -0.03, 0.05, 0.042],
		[0.095, -0.005, 0.075, 0.08], [0.14, 0.03, 0.13, 0.145], [0.22, 0.035, 0.18, 0.2],
		[0.36, 0.02, 0.215, 0.235], [0.5, 0.01, 0.2, 0.215], [0.63, 0.005, 0.14, 0.17],
		[0.76, 0.0, 0.075, 0.12], [0.87, 0.0, 0.045, 0.075], [0.95, 0.0, 0.03, 0.04], [1.0, 0.0, 0.01, 0.012],
	]
	var cape := Color(0.055, 0.062, 0.072)
	var flank := Color(0.16, 0.17, 0.185)
	var belly := Color(0.5, 0.48, 0.48)
	var paint := func(t: float, ang: float) -> Color:
		var up := cos(ang) # 1 on top, -1 under
		# The cape dips down the flank behind the dorsal fin, as a bottlenose's does.
		var cape_line := 0.55 - 0.25 * smoothstep(0.3, 0.6, t) + 0.15 * smoothstep(0.75, 1.0, t)
		var c := flank.lerp(cape, smoothstep(cape_line - 0.25, cape_line + 0.15, up))
		c = c.lerp(belly, smoothstep(-0.35, -0.75, up) * (1.0 - 0.5 * smoothstep(0.7, 0.95, t)))
		if t < 0.07:
			c = c.lerp(Color(0.13, 0.13, 0.14), 0.5) # the beak a little paler on top
		return c
	var part := func(_t: float, _a: float) -> int:
		return P_BODY
	# Rings bunch at the beak and the melon, where the shape changes fastest.
	var spacing := func(u: float) -> float:
		return u - 0.08 * sin(u * PI) * (1.0 - u)
	_loft(g, keys, z0, L, STATIONS[level], SIDES[level] + 2, paint, part, spacing)
	var thick := 0.03 if level == 0 else 0.0
	# The dorsal fin: falcate, its tip swept back over the tail stock (in the YZ plane).
	var dorsal := PackedVector2Array([Vector2(-0.2, 0.0), Vector2(-0.08, 0.13), Vector2(0.06, 0.25), Vector2(0.17, 0.31),
		Vector2(0.15, 0.26), Vector2(0.11, 0.16), Vector2(0.14, 0.05), Vector2(0.18, 0.0)])
	_fin(g, dorsal, Vector3(0, 0.2, z0 + L * 0.47), Vector3(0, 0, 1), Vector3(0, 1, 0), maxf(thick, 0.004) * 1.3, cape, P_FIN, 0.47)
	# The flukes: horizontal, swept back, notched at the middle.
	for s: float in [1.0, -1.0]:
		var fl := PackedVector2Array([Vector2(-0.07, 0.0), Vector2(0.02, 0.16), Vector2(0.13, 0.31), Vector2(0.2, 0.34),
			Vector2(0.15, 0.24), Vector2(0.1, 0.1), Vector2(0.11, 0.015)])
		if s < 0.0:
			fl.reverse()
		_fin(g, fl, Vector3(0, 0.0, z0 + L * 0.955), Vector3(0, 0, 1), Vector3(s, 0, 0), maxf(thick, 0.004), cape.lerp(flank, 0.3), P_FIN, 0.98)
		# The pectoral fins: down, out and back from behind the head.
		var pec := PackedVector2Array([Vector2(-0.06, 0.0), Vector2(0.02, 0.13), Vector2(0.12, 0.26), Vector2(0.15, 0.25), Vector2(0.09, 0.1), Vector2(0.07, 0.0)])
		if s < 0.0:
			pec.reverse()
		_fin(g, pec, Vector3(s * 0.13, -0.09, z0 + L * 0.2), Vector3(0, 0, 1), Vector3(s * 0.75, -0.66, 0).normalized(), maxf(thick, 0.004), flank, P_FIN, 0.2)


# --- the sea lion ------------------------------------------------------------------------------

## A California sea lion lying on its belly (y 0 is the surface it lies on): the dog-like head
## with its snout and tiny ears, the long neck, the barrel of a body tapering to the hips, the
## big fore flippers splayed out flat beside the chest and the hind flippers trailing behind.
## The lower jaw is its own part (the shader opens it to bark).
static func _sea_lion(g: Geo, level: int) -> void:
	var L := SEA_LION_LEN
	var z0 := -L * 0.5
	var keys := [
		[0.0, 0.2, 0.012, 0.014], [0.025, 0.2, 0.035, 0.036], [0.06, 0.205, 0.05, 0.05],
		[0.1, 0.215, 0.075, 0.075], [0.14, 0.215, 0.085, 0.082], [0.2, 0.2, 0.08, 0.085],
		[0.27, 0.19, 0.13, 0.13], [0.36, 0.175, 0.2, 0.17], [0.48, 0.165, 0.22, 0.165],
		[0.62, 0.14, 0.18, 0.14], [0.76, 0.1, 0.11, 0.095], [0.88, 0.07, 0.06, 0.055], [1.0, 0.05, 0.015, 0.015],
	]
	var fur := Color(0.21, 0.14, 0.085)
	var under := Color(0.13, 0.085, 0.05)
	var muzzle := Color(0.1, 0.075, 0.055)
	var paint := func(t: float, ang: float) -> Color:
		var up := cos(ang)
		var c := fur.lerp(under, smoothstep(0.1, -0.6, up))
		if t < 0.06:
			c = c.lerp(muzzle, 0.7)
		return c
	var part := func(t: float, ang: float) -> int:
		# The lower jaw: the under half of the snout.
		return P_JAW if t < 0.105 and cos(ang) < -0.15 else P_BODY
	_loft(g, keys, z0, L, STATIONS[level], SIDES[level] + 2, paint, part)
	var thick := 0.025
	for s: float in [1.0, -1.0]:
		# Fore flippers: long, flat on the ground, splayed out and back from the chest.
		var fore := PackedVector2Array([Vector2(0.0, -0.06), Vector2(0.15, -0.08), Vector2(0.3, -0.04), Vector2(0.36, 0.04),
			Vector2(0.32, 0.09), Vector2(0.16, 0.07), Vector2(0.0, 0.07)])
		_fin(g, fore, Vector3(s * 0.14, 0.03, z0 + L * 0.34), Vector3(s, 0, 0.8).normalized(), Vector3(0, 0, 1), thick, under.lerp(Color(0.06, 0.045, 0.035), 0.6), P_FIN, 0.34)
		# Hind flippers: trailing back and a little out, flat.
		var hind := PackedVector2Array([Vector2(0.0, -0.045), Vector2(0.15, -0.06), Vector2(0.3, -0.07), Vector2(0.34, 0.0),
			Vector2(0.3, 0.07), Vector2(0.15, 0.05), Vector2(0.0, 0.045)])
		_fin(g, hind, Vector3(s * 0.04, 0.035, z0 + L * 0.93), Vector3(s * 0.25, 0, 1).normalized(), Vector3(1, 0, -s * 0.25).normalized(), thick * 0.8, under.lerp(Color(0.06, 0.045, 0.035), 0.6), P_FIN, 0.95)
		if level == 0:
			# The little ear flaps.
			_fin(g, PackedVector2Array([Vector2(0, 0), Vector2(0.012, 0.03), Vector2(0.03, 0.0)]), Vector3(s * 0.065, 0.275, z0 + L * 0.13), Vector3(0, 0, 1), Vector3(s * 0.4, 0.9, 0).normalized(), 0.006, fur, P_BODY, 0.13)


static func _ring_centre(g: Geo, ring: Array) -> Vector3:
	var c := Vector3.ZERO
	for i in ring:
		c += g.v[i]
	return c / float(ring.size())


static func _mirror_x(pts: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(pts.size() - 1, -1, -1):
		out.append(Vector2(pts[i].x, pts[i].y))
	return out


# --- the pelican -------------------------------------------------------------------------------

## A brown pelican in flight: the head pulled back onto the shoulders with the long bill laid on
## the breast and the pouch slung under it, a deep body, broad wings straight out (arm and hand,
## the primaries fingered at the tip), a short tail. Grey-brown back, silver-grey coverts, dark
## flight feathers, a white-and-yellow head with the chestnut hind neck of the breeding season.
static func _pelican(g: Geo, level: int) -> void:
	var body := Color(0.085, 0.075, 0.068)
	var belly := Color(0.06, 0.055, 0.05)
	var neck_c := Color(0.075, 0.035, 0.018)
	var head := Color(0.62, 0.55, 0.36)
	var coverts := Color(0.19, 0.185, 0.175)
	var flight := Color(0.028, 0.026, 0.025)
	var bill := Color(0.3, 0.22, 0.17)
	var pouch := Color(0.07, 0.07, 0.05)
	# The body and the neck as one loft from the crown back to the tail.
	var keys := [
		[0.0, 0.16, 0.01, 0.01], [0.05, 0.17, 0.045, 0.05], [0.12, 0.15, 0.055, 0.06],
		[0.2, 0.09, 0.075, 0.09], [0.32, 0.05, 0.12, 0.12], [0.5, 0.04, 0.13, 0.125],
		[0.68, 0.045, 0.1, 0.1], [0.84, 0.06, 0.06, 0.05], [1.0, 0.07, 0.01, 0.01],
	]
	var paint := func(t: float, ang: float) -> Color:
		var up := cos(ang)
		if t < 0.13:
			return head
		if t < 0.24:
			return neck_c.lerp(head, smoothstep(0.0, -0.8, up) * 0.7)
		return body.lerp(belly, smoothstep(0.0, -0.7, up))
	var part := func(_t: float, _a: float) -> int:
		return P_BODY
	_loft(g, keys, -0.36, 0.9, STATIONS[level], SIDES[level], paint, part)
	# The bill: a long flat blade from the face forward and down along the breast, hooked at the
	# tip; the pouch slung under it.
	var bl := [[0.0, 0.0, 0.032, 0.022], [0.3, -0.015, 0.03, 0.016], [0.7, -0.035, 0.022, 0.012], [0.92, -0.05, 0.018, 0.012], [1.0, -0.07, 0.006, 0.01]]
	var bill_paint := func(t: float, _a: float) -> Color:
		return bill.lerp(Color(0.45, 0.2, 0.1), smoothstep(0.85, 1.0, t))
	var bill_part := func(_t: float, _a: float) -> int:
		return P_BILL
	var gb := g.v.size()
	_loft(g, bl, 0.0, -0.36, maxi(STATIONS[level] / 3, 4), maxi(SIDES[level] - 4, 4), bill_paint, bill_part)
	_place(g, gb, Transform3D(Basis(Vector3.RIGHT, -0.3), Vector3(0, 0.165, -0.33)))
	if level == 0:
		var pk := [[0.0, -0.01, 0.01, 0.01], [0.3, -0.035, 0.026, 0.035], [0.75, -0.02, 0.018, 0.02], [1.0, 0.0, 0.006, 0.006]]
		var pouch_paint := func(_t: float, _a: float) -> Color:
			return pouch
		var pb := g.v.size()
		_loft(g, pk, 0.0, -0.3, 6, 6, pouch_paint, bill_part)
		_place(g, pb, Transform3D(Basis(Vector3.RIGHT, -0.3), Vector3(0, 0.15, -0.35)))
	# The wings: the arm from the shoulder to the wrist, the hand to the tip; coverts grey over
	# the dark flight feathers (the trailing half of the chord). UV.y the span fraction.
	var sh := PELICAN_SHOULDER
	for s: float in [1.0, -1.0]:
		var arm := PackedVector2Array()
		# Leading edge (z negative is forward) out to the tip, then the trailing edge back.
		var lead := [Vector2(sh.x, -0.13), Vector2(0.3, -0.15), Vector2(PELICAN_WRIST, -0.14), Vector2(0.78, -0.11), Vector2(0.95, -0.07), Vector2(PELICAN_SPAN, -0.02)]
		var trail := [Vector2(PELICAN_SPAN, 0.02), Vector2(0.97, 0.1), Vector2(0.84, 0.13), Vector2(0.7, 0.16), Vector2(PELICAN_WRIST, 0.2), Vector2(0.32, 0.22), Vector2(sh.x, 0.2)]
		if level == 0:
			# Fingered primaries: five slots in the trailing edge of the hand.
			trail = [Vector2(PELICAN_SPAN, 0.02), Vector2(1.0, 0.06), Vector2(1.035, 0.07), Vector2(0.98, 0.1), Vector2(1.0, 0.115),
				Vector2(0.93, 0.13), Vector2(0.94, 0.15), Vector2(0.86, 0.15), Vector2(0.85, 0.17), Vector2(0.76, 0.17),
				Vector2(PELICAN_WRIST, 0.2), Vector2(0.42, 0.22), Vector2(0.32, 0.22), Vector2(sh.x, 0.2)]
		for p in lead:
			arm.append(p)
		for p in trail:
			arm.append(p)
		# Two layers: the coverts (front half) a little above the flight feathers (the whole wing).
		_wing(g, arm, s, sh, flight, 0.0, 0.012 if level == 0 else 0.006)
		if level == 0:
			var cov := PackedVector2Array([Vector2(sh.x, -0.125), Vector2(0.3, -0.145), Vector2(PELICAN_WRIST, -0.135), Vector2(0.78, -0.105),
				Vector2(0.9, -0.075), Vector2(0.85, -0.02), Vector2(0.7, 0.02), Vector2(PELICAN_WRIST, 0.05), Vector2(0.3, 0.06), Vector2(sh.x, 0.06)])
			_wing(g, cov, s, sh, coverts, 0.009, 0.006)
	# The tail: a short dark fan.
	var tail := PackedVector2Array([Vector2(-0.05, 0.0), Vector2(-0.09, 0.17), Vector2(0.0, 0.2), Vector2(0.09, 0.17), Vector2(0.05, 0.0)])
	_fin(g, tail, Vector3(0, 0.07, 0.42), Vector3(1, 0, 0), Vector3(0, 0, 1), 0.01, flight, P_FIN, 0.95)


## One wing layer: the outline in (x, z) at the shoulder's height, `lift` over it, mirrored to
## the left for s = -1; UV.y the span fraction (0 shoulder, 1 tip) for the shader's flap.
static func _wing(g: Geo, outline: PackedVector2Array, s: float, sh: Vector3, col: Color, lift: float, thick: float) -> void:
	var pts := PackedVector2Array()
	for p in outline:
		pts.append(p)
	var tris := Geometry2D.triangulate_polygon(pts)
	for side: float in [1.0, -1.0]:
		var base := g.v.size()
		for p in pts:
			var span := clampf((p.x - sh.x) / (PELICAN_SPAN - sh.x), 0.0, 1.0)
			# A gentle camber: the wing arches up over its chord, droops a little to the tip.
			var arch := 0.012 * sin(clampf((p.y + 0.15) / 0.37, 0.0, 1.0) * PI) - 0.03 * span * span
			var w := Vector3(p.x * s, sh.y + lift + arch + side * thick * 0.5 * (1.0 - 0.7 * span), p.y)
			g.add(w, _col(col, P_WING), Vector2(0.4, span))
		for i in range(0, tris.size(), 3):
			var cen := (g.v[base + tris[i]] + g.v[base + tris[i + 1]] + g.v[base + tris[i + 2]]) / 3.0
			g.tri(base + tris[i], base + tris[i + 1], base + tris[i + 2], cen - Vector3.UP * side)


## Moves vertices from `from` on by `xf` (a part built in its own frame).
static func _place(g: Geo, from: int, xf: Transform3D) -> void:
	for i in range(from, g.v.size()):
		g.v[i] = xf * g.v[i]


# --- the whale ---------------------------------------------------------------------------------

## A grey whale: a narrow head sloping down from the blowholes, the long back with the low hump
## and the knuckles along the tail stock instead of a dorsal fin, broad pointed flukes, paddle
## flippers. Mottled grey (the shader paints the barnacle and scar patches).
static func _whale(g: Geo, level: int) -> void:
	var L := WHALE_LEN
	var z0 := -L * 0.5
	var keys := [
		[0.0, -0.3, 0.06, 0.06], [0.04, -0.15, 0.35, 0.3], [0.1, 0.1, 0.65, 0.6], [0.2, 0.2, 1.1, 1.0],
		[0.35, 0.15, 1.4, 1.3], [0.5, 0.1, 1.3, 1.25], [0.62, 0.15, 1.0, 1.05], [0.72, 0.12, 0.62, 0.8],
		[0.84, 0.05, 0.32, 0.45], [0.93, 0.0, 0.16, 0.2], [1.0, 0.0, 0.05, 0.06],
	]
	var top := Color(0.075, 0.08, 0.085)
	var under := Color(0.11, 0.115, 0.12)
	var paint := func(_t: float, ang: float) -> Color:
		return top.lerp(under, smoothstep(0.2, -0.7, cos(ang)))
	var part := func(_t: float, _a: float) -> int:
		return P_BODY
	_loft(g, keys, z0, L, STATIONS[level] + 6, SIDES[level] + 4, paint, part)
	for s: float in [1.0, -1.0]:
		var fl := PackedVector2Array([Vector2(-0.6, 0.0), Vector2(-0.1, 0.9), Vector2(0.6, 1.7), Vector2(1.0, 1.8),
			Vector2(0.75, 1.2), Vector2(0.5, 0.45), Vector2(0.55, 0.06)])
		if s < 0.0:
			fl.reverse()
		_fin(g, fl, Vector3(0, 0.0, z0 + L * 0.95), Vector3(0, 0, 1), Vector3(s, 0, 0), 0.18, top, P_FIN, 0.98)
		var pec := PackedVector2Array([Vector2(-0.3, 0.0), Vector2(0.0, 0.9), Vector2(0.4, 1.4), Vector2(0.55, 1.3), Vector2(0.4, 0.5), Vector2(0.35, 0.0)])
		if s < 0.0:
			pec.reverse()
		_fin(g, pec, Vector3(s * 0.8, -0.6, z0 + L * 0.27), Vector3(0, 0, 1), Vector3(s * 0.6, -0.8, 0).normalized(), 0.15, top, P_FIN, 0.27)


# --- the buoy ----------------------------------------------------------------------------------

## A harbour navigation buoy at real size (y 0 its waterline): a steel float 2.7 m across with a
## fendered rim, a flat deck the sea lions haul out on, a four-legged lattice tower with its
## bracing up to a lantern 3.6 m over the water, an octahedral radar reflector in the tower and a
## ballast tube under the float. Red paint (the colour is the instance's), galvanised steel.
static func _buoy(g: Geo, level: int) -> void:
	var paint := Color(0.36, 0.025, 0.02)
	var steel := Color(0.3, 0.3, 0.29)
	var dark := Color(0.03, 0.03, 0.03)
	var sides := 24 if level == 0 else 10
	var dy := BUOY_DECK_Y
	_cyl(g, Vector3.ZERO, 1.3, 1.3, -0.55, dy - 0.04, sides, paint, P_PAINT, false)
	_cyl(g, Vector3.ZERO, 1.3, 0.55, -0.55, -0.95, sides, paint, P_PAINT, false)
	_cyl(g, Vector3.ZERO, 0.22, 0.22, -2.6, -0.9, maxi(sides / 2, 6), dark, P_METAL, true)
	# The deck plate (guano and all) with a raised rim.
	_cyl(g, Vector3.ZERO, BUOY_DECK_R, BUOY_DECK_R, dy - 0.04, dy, sides, steel, P_DECK, true)
	_cyl(g, Vector3.ZERO, BUOY_DECK_R + 0.06, BUOY_DECK_R + 0.06, dy - 0.04, dy + 0.06, sides, paint, P_PAINT, false)
	# The rubbing fender round the float's shoulder.
	_cyl(g, Vector3.ZERO, 1.38, 1.38, dy - 0.32, dy - 0.14, sides, dark, P_METAL, false)
	# The tower: four legs from the deck to the lantern platform, X bracing between them.
	var foot := 0.62
	var head := 0.24
	var top_y := dy + 2.75
	var legs: Array = []
	for k in 4:
		var a := TAU * (float(k) + 0.5) / 4.0
		var d := Vector3(sin(a), 0, cos(a))
		legs.append([d * foot + Vector3(0, dy, 0), d * head + Vector3(0, top_y, 0)])
		_bar(g, legs[k][0], legs[k][1], 0.045, 6 if level == 0 else 4, paint, P_PAINT)
	if level == 0:
		for k in 4:
			var a0: Array = legs[k]
			var a1: Array = legs[(k + 1) % 4]
			for band in 3:
				var u0 := float(band) / 3.0
				var u1 := float(band + 1) / 3.0
				var p00: Vector3 = (a0[0] as Vector3).lerp(a0[1], u0)
				var p01: Vector3 = (a0[0] as Vector3).lerp(a0[1], u1)
				var p10: Vector3 = (a1[0] as Vector3).lerp(a1[1], u0)
				var p11: Vector3 = (a1[0] as Vector3).lerp(a1[1], u1)
				_bar(g, p00, p11, 0.02, 4, paint, P_PAINT)
				_bar(g, p10, p01, 0.02, 4, paint, P_PAINT)
				_bar(g, p01, p11, 0.025, 4, paint, P_PAINT)
		# The radar reflector: three crossed square plates in the tower.
		var rc := Vector3(0, dy + 1.7, 0)
		for ax in [Basis(), Basis(Vector3.RIGHT, PI * 0.5), Basis(Vector3.FORWARD, PI * 0.5)]:
			_box(g, rc, Vector3(0.24, 0.24, 0.004), (ax as Basis) * Basis(Vector3.UP, PI * 0.25), steel, P_METAL)
	# The platform and the lantern (lens lit by the shader), with its sun valve and a cap.
	_cyl(g, Vector3.ZERO, head + 0.12, head + 0.12, top_y, top_y + 0.05, sides / 2, paint, P_PAINT, true)
	_cyl(g, Vector3.ZERO, 0.11, 0.11, top_y + 0.05, top_y + 0.32, sides / 2, Color(0.5, 0.6, 0.5), P_LAMP, false)
	_cyl(g, Vector3.ZERO, 0.13, 0.04, top_y + 0.32, top_y + 0.42, sides / 2, dark, P_METAL, true)


# --- the spray ---------------------------------------------------------------------------------

## The spray: 14 quads, each a clump the shader flies from the origin (a splash) or stacks into
## a column (a whale's blow). UV the corner (-1..1); UV2.x the clump's seed, UV2.y its index / 16,
## so the shader gives each its own direction, size and timing (not the vertex colour: a
## MultiMesh without instance colours hands the shader a zero COLOR on Compatibility).
static func _spray(g: Geo) -> void:
	for i in 14:
		var seed := fposmod(sin(float(i) * 12.9898) * 43758.5453, 1.0)
		var base := g.v.size()
		for k: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			g.add(Vector3.ZERO, Color(1, 1, 1, 1), k)
			g.uv2.append(Vector2(seed, float(i) / 16.0))
		g.quad(base, base + 1, base + 2, base + 3, Vector3(0, 0, -1))
