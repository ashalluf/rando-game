class_name SkyAdMesh
extends RefCounted
## The aerial advertising's geometry, built in code at real size (SkyAds,
## docs/HANDOFF.md "Aerial advertising"): the FIZZLY blimp, the banner tow plane and a letter
## banner, each ONE ArrayMesh on shaders/sky_ads.gdshader (kind in COLOR.a / 16, paint sRGB in
## COLOR.rgb; the K_* codes are the shader's). Craft space: forward -Z, up +Y, metres.
##
## The blimp is the size of a real advertising airship: a 60 m envelope 15.4 m across, four
## fins in an X, an 11 m gondola under it with two ducted props on outriggers, the night sign
## (K_LED) along both flanks. The plane is a two-seat high-wing taildragger of the kind that
## tows banners along a beach: 10.7 m span, 6.9 m long, struts, big tyres, a tow hook. Meshes
## are cached; the banner is cached per text.

const K_PAINT := 0
const K_ENVELOPE := 1
const K_LETTER := 2
const K_LED := 3
const K_GLASS := 4
const K_DARK := 5
const K_METAL := 6
const K_PROP := 7
const K_CLOTH := 8
const K_ROPE := 9
const K_LAMP := 10

## The envelope: length, the biggest radius and where along it (share of the length).
const ENV_LENGTH := 60.0
const ENV_RADIUS := 7.7
const ENV_PEAK := 0.38
## The night sign on each flank: from / to (metres from the nose), centre angle above the
## horizontal (radians), height (m).
const LED_FROM := 14.0
const LED_TO := 44.0
const LED_ANGLE := -0.30
const LED_HEIGHT := 5.4
## Where the gondola hangs (its floor) and its length.
const GONDOLA_Y := -ENV_RADIUS - 2.2
const GONDOLA_LEN := 11.0
## Banner: height and the margin round its letters (m).
const BANNER_HEIGHT := 3.6
const BANNER_MARGIN := 3.0
const BANNER_LETTER := 2.6

static var _blimp: ArrayMesh
static var _plane: ArrayMesh
static var _banners: Dictionary = {}
static var _rope: ArrayMesh
static var _material: ShaderMaterial


static func material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = load("res://shaders/sky_ads.gdshader")
	return _material


## The envelope's radius at `u` metres from the nose: an ellipse ahead of the peak, a long
## taper behind it to a blunt tail.
static func env_radius(u: float) -> float:
	var t := clampf(u / ENV_LENGTH, 0.0, 1.0)
	if t < ENV_PEAK:
		var q := (ENV_PEAK - t) / ENV_PEAK
		return ENV_RADIUS * sqrt(maxf(1.0 - q * q, 0.0))
	var q2 := (t - ENV_PEAK) / (1.0 - ENV_PEAK)
	return ENV_RADIUS * pow(maxf(1.0 - pow(q2, 2.2), 0.0), 0.7) * (1.0 - 0.06 * q2) + 0.12 * q2


## A point on the envelope `u` metres from the nose at angle `a` round it (0 the top, PI/2 the
## +X flank), `lift` metres off the skin.
static func env_point(u: float, a: float, lift: float = 0.0) -> Vector3:
	var r := env_radius(u) + lift
	return Vector3(sin(a) * r, cos(a) * r, u - ENV_LENGTH * 0.5)


static func env_normal(u: float, a: float) -> Vector3:
	var dr := (env_radius(u + 0.05) - env_radius(maxf(u - 0.05, 0.0))) / (0.05 + minf(u, 0.05))
	return Vector3(sin(a), cos(a), -dr).normalized()


# --- The builder ------------------------------------------------------------------------------

class Geo:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var idx := PackedInt32Array()

	func vert(p: Vector3, nrm: Vector3, kind: int, col: Color, t: Vector2 = Vector2.ZERO, t2: Vector2 = Vector2.ZERO) -> int:
		v.append(p)
		n.append(nrm)
		c.append(Color(col.r, col.g, col.b, (float(kind) + 0.25) / 16.0))
		uv.append(t)
		uv2.append(t2)
		return v.size() - 1

	## A triangle of existing vertices, wound so it faces `want` (Godot's front face is the one
	## whose (c - a) x (b - a) points out: FreewayKit.tri()).
	func tri(a: int, b: int, cc: int, want: Vector3) -> void:
		var fn := (v[cc] - v[a]).cross(v[b] - v[a])
		if fn.dot(want) < 0.0:
			idx.append_array([a, cc, b])
		else:
			idx.append_array([a, b, cc])

	func quad(a: int, b: int, cc: int, d: int, want: Vector3) -> void:
		tri(a, b, cc, want)
		tri(a, cc, d, want)

	## A flat triangle with its own vertices.
	func ftri(a: Vector3, b: Vector3, cc: Vector3, want: Vector3, kind: int, col: Color, t2: Vector2 = Vector2.ZERO) -> void:
		var nn := (cc - a).cross(b - a)
		if nn.length_squared() < 1e-12:
			return
		nn = nn.normalized()
		if nn.dot(want) < 0.0:
			nn = -nn
		var i0 := vert(a, nn, kind, col, Vector2.ZERO, t2)
		var i1 := vert(b, nn, kind, col, Vector2.ZERO, t2)
		var i2 := vert(cc, nn, kind, col, Vector2.ZERO, t2)
		tri(i0, i1, i2, nn)

	func fquad(a: Vector3, b: Vector3, cc: Vector3, d: Vector3, want: Vector3, kind: int, col: Color, uvs: PackedVector2Array = PackedVector2Array(), t2: Vector2 = Vector2.ZERO) -> void:
		var nn := (cc - a).cross(b - a)
		if nn.length_squared() < 1e-12:
			nn = want
		nn = nn.normalized()
		if nn.dot(want) < 0.0:
			nn = -nn
		var u4 := uvs if uvs.size() == 4 else PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
		var i0 := vert(a, nn, kind, col, u4[0], t2)
		var i1 := vert(b, nn, kind, col, u4[1], t2)
		var i2 := vert(cc, nn, kind, col, u4[2], t2)
		var i3 := vert(d, nn, kind, col, u4[3], t2)
		quad(i0, i1, i2, i3, nn)

	## A box in a frame (centre, half sizes along the basis axes), flat shaded.
	func box(xf: Transform3D, half: Vector3, kind: int, col: Color) -> void:
		var b := xf.basis
		var o := xf.origin
		for ax in 3:
			for sgn: float in [-1.0, 1.0]:
				var nrm: Vector3 = b[ax] * sgn
				var a1: Vector3 = b[(ax + 1) % 3] * half[(ax + 1) % 3]
				var a2: Vector3 = b[(ax + 2) % 3] * half[(ax + 2) % 3]
				var cc: Vector3 = o + nrm * half[ax]
				fquad(cc - a1 - a2, cc + a1 - a2, cc + a1 + a2, cc - a1 + a2, nrm.normalized(), kind, col)

	## A round tube from `a` to `b`, radii ra / rb, `sides` facets, smooth, open ends.
	func tube(a: Vector3, b: Vector3, ra: float, rb: float, sides: int, kind: int, col: Color, caps: bool = false, inward: bool = false) -> void:
		var ax := (b - a)
		if ax.length() < 1e-4:
			return
		var d := ax.normalized()
		var side := d.cross(Vector3.UP)
		if side.length() < 0.1:
			side = d.cross(Vector3.RIGHT)
		side = side.normalized()
		var up := side.cross(d).normalized()
		var base := v.size()
		for i in sides + 1:
			var ang := TAU * float(i) / float(sides)
			var rad := side * cos(ang) + up * sin(ang)
			var rn := -rad if inward else rad
			vert(a + rad * ra, rn, kind, col, Vector2(float(i) / sides, 0.0))
			vert(b + rad * rb, rn, kind, col, Vector2(float(i) / sides, ax.length()))
		for i in sides:
			var p := base + i * 2
			var mid := (a + b) * 0.5
			var out := (v[p] + v[p + 3]) * 0.5 - mid
			var want := out - d * out.dot(d)
			quad(p, p + 2, p + 3, p + 1, -want if inward else want)
		if caps:
			for end in 2:
				var ctr := a if end == 0 else b
				var nn := -d if end == 0 else d
				var r := ra if end == 0 else rb
				var ci := vert(ctr, nn, kind, col)
				var ring := []
				for i in sides:
					var ang := TAU * float(i) / float(sides)
					ring.append(vert(ctr + (side * cos(ang) + up * sin(ang)) * r, nn, kind, col))
				for i in sides:
					tri(ci, ring[i], ring[(i + 1) % sides], nn)

	## A lofted body through rings: `rings` is an Array of [z, centre y, half width, half
	## height, squareness 2..6] along the body; `sides` points a ring.
	func loft(rings: Array, sides: int, kind: int, col: Color) -> void:
		var base := v.size()
		var count := rings.size()
		for r: Array in rings:
			var z: float = r[0]
			var cy: float = r[1]
			var hw: float = r[2]
			var hh: float = r[3]
			var e: float = r[4]
			for i in sides + 1:
				var ang := TAU * float(i) / float(sides)
				var ca := cos(ang)
				var sa := sin(ang)
				# A superellipse: squarer for a bigger e.
				var x := signf(ca) * pow(absf(ca), 2.0 / e) * hw
				var y := signf(sa) * pow(absf(sa), 2.0 / e) * hh
				var nrm := Vector3(signf(ca) * pow(absf(ca), 2.0 - 2.0 / e) / maxf(hw, 0.01), signf(sa) * pow(absf(sa), 2.0 - 2.0 / e) / maxf(hh, 0.01), 0.0).normalized()
				vert(Vector3(x, cy + y, z), nrm, kind, col, Vector2(float(i) / sides, z))
		# Normals get the taper's tilt from the neighbouring rings.
		for k in count:
			for i in sides + 1:
				var p := base + k * (sides + 1) + i
				var prev := base + maxi(k - 1, 0) * (sides + 1) + i
				var next := base + mini(k + 1, count - 1) * (sides + 1) + i
				var along := v[next] - v[prev]
				var around := v[base + k * (sides + 1) + (i + 1) % sides] - v[base + k * (sides + 1) + (i + sides - 1) % sides]
				var nn := along.cross(around).normalized()
				if nn.dot(n[p]) < 0.0:
					nn = -nn
				if along.length() > 0.001 and around.length() > 0.001:
					n[p] = nn
		for k in count - 1:
			for i in sides:
				var a := base + k * (sides + 1) + i
				var b := a + sides + 1
				quad(a, a + 1, b + 1, b, n[a] + n[b + 1])
		# Caps at both ends.
		for end in 2:
			var k := 0 if end == 0 else count - 1
			var r: Array = rings[k]
			var nn := Vector3(0, 0, -1) if end == 0 else Vector3(0, 0, 1)
			var ci := vert(Vector3(0.0, r[1], r[0]), nn, kind, col)
			for i in sides:
				tri(ci, base + k * (sides + 1) + i, base + k * (sides + 1) + i + 1, nn)

	## A thick flat plate from a polygon in a plane: `pts` in (a, b) of axes `ea`, `eb` from
	## `o`, `thick` along the normal, edges and both faces.
	func plate(o: Vector3, ea: Vector3, eb: Vector3, pts: PackedVector2Array, thick: float, kind: int, col: Color) -> void:
		var nrm := ea.cross(eb).normalized()
		var top := PackedVector3Array()
		var bot := PackedVector3Array()
		for p in pts:
			var w := o + ea * p.x + eb * p.y
			top.append(w + nrm * thick * 0.5)
			bot.append(w - nrm * thick * 0.5)
		var tris := Geometry2D.triangulate_polygon(pts)
		for f in [1.0, -1.0]:
			var face := top if f > 0.0 else bot
			for t in range(0, tris.size(), 3):
				ftri(face[tris[t]], face[tris[t + 1]], face[tris[t + 2]], nrm * f, kind, col)
		var ctr := Vector2.ZERO
		for p in pts:
			ctr += p
		ctr /= float(pts.size())
		for i in pts.size():
			var j := (i + 1) % pts.size()
			var mid := (pts[i] + pts[j]) * 0.5 - ctr
			fquad(top[i], top[j], bot[j], bot[i], ea * mid.x + eb * mid.y, kind, col)

	## Text laid by `place` (a Callable taking a Vector2 in metres of text, centred, and
	## returning [position, normal]), `height` metres tall.
	func text(s: String, height: float, place: Callable, kind: int, col: Color, t2: Vector2 = Vector2.ZERO) -> float:
		var geo := FreewayKit.text_geo(s, height)
		var verts: PackedVector3Array = geo[0]
		var ids: PackedInt32Array = geo[1]
		for t in range(0, ids.size() - 2, 3):
			var pa: Array = place.call(Vector2(verts[ids[t]].x, verts[ids[t]].y))
			var pb: Array = place.call(Vector2(verts[ids[t + 1]].x, verts[ids[t + 1]].y))
			var pc: Array = place.call(Vector2(verts[ids[t + 2]].x, verts[ids[t + 2]].y))
			var want: Vector3 = pa[1]
			var a := vert(pa[0], want, kind, col, Vector2.ZERO, pa[2] if pa.size() > 2 else t2)
			var b := vert(pb[0], pb[1], kind, col, Vector2.ZERO, pb[2] if pb.size() > 2 else t2)
			var cc := vert(pc[0], pc[1], kind, col, Vector2.ZERO, pc[2] if pc.size() > 2 else t2)
			tri(a, b, cc, want)
		return geo[2]

	func commit() -> ArrayMesh:
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = v
		arr[Mesh.ARRAY_NORMAL] = n
		arr[Mesh.ARRAY_COLOR] = c
		arr[Mesh.ARRAY_TEX_UV] = uv
		arr[Mesh.ARRAY_TEX_UV2] = uv2
		arr[Mesh.ARRAY_INDEX] = idx
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		m.surface_set_material(0, SkyAdMesh.material())
		return m

	func triangles() -> int:
		return idx.size() / 3


# --- The blimp --------------------------------------------------------------------------------

## The FIZZLY blimp (cached).
static func blimp() -> ArrayMesh:
	if _blimp == null:
		_blimp = _build_blimp().commit()
	return _blimp


static func _build_blimp() -> Geo:
	var g := Geo.new()
	var white := Color(0.92, 0.92, 0.9)
	var orange := Color(0.95, 0.40, 0.10)
	var red := Color(0.80, 0.12, 0.08)
	var grey := Color(0.55, 0.56, 0.58)
	# The envelope: rings denser at the nose and the tail.
	var rings := 64
	var sides := 48
	var base := g.v.size()
	var us := PackedFloat32Array()
	for k in rings + 1:
		var t := float(k) / rings
		us.append(ENV_LENGTH * (0.5 - 0.5 * cos(t * PI)) * 0.985 + 0.004 * ENV_LENGTH)
	for u in us:
		for i in sides + 1:
			var a := TAU * float(i) / sides
			g.vert(env_point(u, a), env_normal(u, a), K_ENVELOPE, white, Vector2(u, float(i) / sides))
	for k in rings:
		for i in sides:
			var p := base + k * (sides + 1) + i
			var q := p + sides + 1
			g.quad(p, p + 1, q + 1, q, g.n[p] + g.n[q + 1])
	# Close the nose and the tail.
	for end in 2:
		var tip := Vector3(0, 0, -ENV_LENGTH * 0.5) if end == 0 else Vector3(0, 0, ENV_LENGTH * 0.5)
		var nn := Vector3(0, 0, -1) if end == 0 else Vector3(0, 0, 1)
		var ci := g.vert(tip, nn, K_ENVELOPE, white, Vector2(0.0 if end == 0 else ENV_LENGTH, 0.0))
		var row := 0 if end == 0 else rings
		for i in sides:
			g.tri(ci, base + row * (sides + 1) + i, base + row * (sides + 1) + i + 1, nn)
	# The night sign, a hair off the skin on both flanks, read front to back from either side.
	for side: float in [1.0, -1.0]:
		var cols := 40
		var rows := 8
		var a0 := PI * 0.5 - LED_ANGLE
		var span := LED_HEIGHT / env_radius((LED_FROM + LED_TO) * 0.5)
		var lb := g.v.size()
		for k in cols + 1:
			var u := lerpf(LED_FROM, LED_TO, float(k) / cols)
			for j in rows + 1:
				var a := a0 + span * (0.5 - float(j) / rows)
				var p := env_point(u, a, 0.12)
				p.x *= side
				var nn := env_normal(u, a)
				nn.x *= side
				# u reads left to right as seen from this flank: on +X the nose is to the right.
				var ru := float(k) / cols if side < 0.0 else 1.0 - float(k) / cols
				g.vert(p, nn, K_LED, Color.BLACK, Vector2(ru, float(j) / rows))
		for k in cols:
			for j in rows:
				var p := lb + k * (rows + 1) + j
				g.quad(p, p + 1, p + rows + 2, p + rows + 1, g.n[p])
		# The sign's frame, a narrow dark band round it.
		for edge: float in [-1.0, 1.0]:
			var fb := g.v.size()
			for k in cols + 1:
				var u := lerpf(LED_FROM - 0.3, LED_TO + 0.3, float(k) / cols)
				for j in 2:
					var a := a0 + edge * (span * 0.5 + 0.03 + 0.05 * j)
					var p := env_point(u, a, 0.11)
					p.x *= side
					var nn := env_normal(u, a)
					nn.x *= side
					g.vert(p, nn, K_DARK, Color(0.08, 0.08, 0.09))
			for k in cols:
				var p := fb + k * 2
				g.quad(p, p + 1, p + 3, p + 2, g.n[p])
	# The name, big on both flanks above the sign, and the line under the swoosh.
	for side: float in [1.0, -1.0]:
		var name_place := func(q: Vector2) -> Array:
			var u := 29.0 + (q.x if side < 0.0 else -q.x)
			var a := PI * 0.5 - 0.62 - q.y / env_radius(u)
			var p := env_point(u, a, 0.18)
			p.x *= side
			var nn := env_normal(u, a)
			nn.x *= side
			return [p, nn]
		g.text("FIZZLY", 6.2, name_place, K_LETTER, red)
		var line_place := func(q: Vector2) -> Array:
			var u := 50.0 + (q.x if side < 0.0 else -q.x)
			var a := PI * 0.5 + 0.55 - q.y / env_radius(u)
			var p := env_point(u, a, 0.18)
			p.x *= side
			var nn := env_normal(u, a)
			nn.x *= side
			return [p, nn]
		g.text("Taste the Loud.", 1.5, line_place, K_LETTER, Color(0.98, 0.95, 0.88))
	# Four fins in an X, orange with a white tip band and a darker control surface.
	for k in 4:
		var a := PI * 0.25 + PI * 0.5 * k
		var dir := Vector3(sin(a), cos(a), 0.0)
		var u0 := 45.5
		var u1 := 57.8
		var root0 := env_point(u0, a, -0.3)
		var root1 := env_point(u1, a, -0.3)
		var span_len := 5.4
		var o := Vector3(0, 0, 0)
		var ea := Vector3(0, 0, 1)
		var eb := dir
		var r0 := Vector2(root0.z, Vector2(root0.x, root0.y).length())
		var r1 := Vector2(root1.z, Vector2(root1.x, root1.y).length())
		var tip_r := r0.y + span_len
		var fin := PackedVector2Array([r0, r1 + Vector2(0.4, 0.0), Vector2(r1.x + 0.6, tip_r - 0.4), Vector2(r0.x + 5.0, tip_r)])
		g.plate(o, ea, eb, fin, 0.42, K_PAINT, orange)
		# The control surface along the trailing edge and the white tip.
		var cs := PackedVector2Array([Vector2(r1.x - 1.7, r0.y + 0.9), Vector2(r1.x + 0.35, r1.y + 0.9), Vector2(r1.x + 0.55, tip_r - 0.7), Vector2(r1.x - 1.4, tip_r - 0.55)])
		g.plate(o, ea, eb, cs, 0.46, K_PAINT, red)
		var tipb := PackedVector2Array([Vector2(r0.x + 4.9, tip_r - 0.75), Vector2(r1.x + 0.58, tip_r - 0.75), Vector2(r1.x + 0.6, tip_r - 0.4), Vector2(r0.x + 5.0, tip_r)])
		g.plate(o, ea, eb, tipb, 0.47, K_PAINT, white)
	# The gondola: a lofted car with a glazed front, under the envelope's peak.
	var gz0 := -ENV_LENGTH * 0.5 + 17.0
	var gy := GONDOLA_Y + 1.25
	var grings := [
		[gz0 - 0.05, gy + 0.15, 0.35, 0.35, 2.2],
		[gz0 + 0.3, gy + 0.05, 1.0, 0.95, 2.6],
		[gz0 + 1.2, gy, 1.28, 1.2, 3.4],
		[gz0 + 3.0, gy, 1.35, 1.25, 4.0],
		[gz0 + GONDOLA_LEN - 2.5, gy + 0.05, 1.3, 1.2, 4.0],
		[gz0 + GONDOLA_LEN - 0.8, gy + 0.25, 1.0, 0.9, 3.0],
		[gz0 + GONDOLA_LEN, gy + 0.5, 0.45, 0.45, 2.4],
	]
	g.loft(grings, 28, K_PAINT, white)
	# Windows: the wraparound front and a row down each side.
	for side: float in [1.0, -1.0]:
		var x := 1.37 * side
		for w in 5:
			var z0 := gz0 + 1.6 + w * 1.25
			g.fquad(Vector3(x, gy - 0.05, z0), Vector3(x, gy - 0.05, z0 + 0.95), Vector3(x, gy + 0.75, z0 + 0.95), Vector3(x, gy + 0.75, z0), Vector3(side, 0, 0), K_GLASS, Color.BLACK)
		g.fquad(Vector3(0.95 * side, gy - 0.1, gz0 + 0.3), Vector3(1.3 * side, gy - 0.1, gz0 + 1.25), Vector3(1.32 * side, gy + 0.8, gz0 + 1.25), Vector3(0.9 * side, gy + 0.7, gz0 + 0.32), Vector3(side, 0, -0.7), K_GLASS, Color.BLACK)
		# The orange stripe down the car.
		g.fquad(Vector3(x * 1.006, gy - 0.55, gz0 + 1.3), Vector3(x * 1.006, gy - 0.55, gz0 + GONDOLA_LEN - 2.0), Vector3(x * 1.006, gy - 0.3, gz0 + GONDOLA_LEN - 2.0), Vector3(x * 1.006, gy - 0.3, gz0 + 1.3), Vector3(side, 0, 0), K_PAINT, orange)
	g.fquad(Vector3(-0.95, gy - 0.1, gz0 + 0.31), Vector3(0.95, gy - 0.1, gz0 + 0.31), Vector3(0.9, gy + 0.7, gz0 + 0.33), Vector3(-0.9, gy + 0.7, gz0 + 0.33), Vector3(0, 0, -1), K_GLASS, Color.BLACK)
	# Struts and the fairing between the car and the envelope.
	for side: float in [1.0, -1.0]:
		for zz: float in [gz0 + 2.0, gz0 + GONDOLA_LEN - 2.5]:
			g.tube(Vector3(0.9 * side, gy + 1.15, zz), Vector3(1.6 * side, -ENV_RADIUS + 0.6, zz + 0.3), 0.07, 0.07, 6, K_METAL, grey)
	g.loft([
		[gz0 + 1.0, gy + 1.05, 0.9, 0.12, 2.0],
		[gz0 + 3.0, gy + 1.25, 1.1, 0.25, 2.5],
		[gz0 + GONDOLA_LEN - 2.0, gy + 1.25, 1.0, 0.25, 2.5],
		[gz0 + GONDOLA_LEN - 0.5, gy + 1.0, 0.6, 0.12, 2.0],
	], 16, K_PAINT, white)
	# The engines: two ducted props on outriggers at the back of the car.
	var ez := gz0 + GONDOLA_LEN - 1.6
	for side: float in [1.0, -1.0]:
		var ex := 3.5 * side
		var ey := gy + 0.35
		g.box(Transform3D(Basis(), Vector3(2.35 * side, ey, ez + 0.2)), Vector3(1.0, 0.09, 0.32), K_METAL, grey)
		# The nacelle.
		g.loft([
			[ez - 1.4, ey, 0.1, 0.1, 2.0],
			[ez - 1.0, ey, 0.32, 0.32, 2.0],
			[ez + 0.3, ey, 0.36, 0.36, 2.0],
			[ez + 0.6, ey, 0.18, 0.18, 2.0],
		], 14, K_PAINT, white)
		# The duct: an inner and an outer skin.
		var dz0 := ez + 0.1
		var dz1 := ez + 1.15
		var c0 := Vector3(ex, ey, dz0)
		var c1 := Vector3(ex, ey, dz1)
		g.tube(c0, c1, 1.18, 1.12, 24, K_PAINT, orange)
		g.tube(c0, c1, 1.1, 1.06, 24, K_DARK, Color(0.1, 0.1, 0.11), false, true)
		# The lips.
		g.tube(Vector3(ex, ey, dz0 - 0.03), Vector3(ex, ey, dz0 + 0.02), 1.1, 1.2, 24, K_METAL, grey)
		g.tube(Vector3(ex, ey, dz1 - 0.02), Vector3(ex, ey, dz1 + 0.03), 1.12, 1.06, 24, K_METAL, grey)
		# Stator vanes and the hub, then the blurred prop.
		for vane in 4:
			var va := TAU * vane / 4.0 + 0.4
			g.box(Transform3D(Basis(Vector3(0, 0, 1), va), Vector3(ex, ey, dz1 - 0.2) + Vector3(cos(va), sin(va), 0.0) * 0.6), Vector3(0.5, 0.025, 0.12), K_METAL, grey)
		g.tube(Vector3(ex, ey, dz0 + 0.25), Vector3(ex, ey, dz1 - 0.05), 0.18, 0.12, 10, K_METAL, grey, true)
		for f: float in [-1.0, 1.0]:
			var pz := dz0 + 0.45 + f * 0.01
			var b := g.v.size()
			for cc in 4:
				var cuv := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)][cc] as Vector2
				g.vert(Vector3(ex + (cuv.x - 0.5) * 2.1, ey + (cuv.y - 0.5) * 2.1, pz), Vector3(0, 0, f), K_PROP, Color.BLACK, cuv)
			g.quad(b, b + 1, b + 2, b + 3, Vector3(0, 0, f))
	# Landing wheel, the nose mooring cone, an antenna, the tail cone.
	g.tube(Vector3(-0.2, GONDOLA_Y - 0.45, gz0 + 6.0), Vector3(0.2, GONDOLA_Y - 0.45, gz0 + 6.0), 0.42, 0.42, 14, K_DARK, Color(0.05, 0.05, 0.05), true)
	g.box(Transform3D(Basis(), Vector3(0, GONDOLA_Y - 0.05, gz0 + 6.0)), Vector3(0.12, 0.35, 0.12), K_METAL, grey)
	g.tube(Vector3(0, 0, -ENV_LENGTH * 0.5 - 0.6), Vector3(0, 0, -ENV_LENGTH * 0.5 + 0.4), 0.12, 0.5, 10, K_METAL, grey, true)
	g.tube(Vector3(0, gy + 0.6, gz0 + 4.0), Vector3(0, GONDOLA_Y - 0.9, gz0 + 4.0), 0.02, 0.02, 4, K_DARK, Color.BLACK)
	return g


## The blimp's nav lights, as AmbientCraft._build_lights() takes them.
static func blimp_light_specs() -> Array:
	var red := Color(1.0, 0.10, 0.06, 1.0)
	var green := Color(0.15, 1.0, 0.35, 1.0)
	var white := Color(1.0, 0.98, 0.92, 1.0)
	var tip_a := env_point(51.5, PI * 0.75, 6.0)
	return [
		[Vector3(-1.4, GONDOLA_Y + 0.6, -ENV_LENGTH * 0.5 + 17.3), red, 0.5, AmbientCraft.LightKind.STEADY, Vector3.ZERO],
		[Vector3(1.4, GONDOLA_Y + 0.6, -ENV_LENGTH * 0.5 + 17.3), green, 0.5, AmbientCraft.LightKind.STEADY, Vector3.ZERO],
		[Vector3(0.0, 0.3, ENV_LENGTH * 0.5 + 0.2), white, 0.6, AmbientCraft.LightKind.STEADY, Vector3.ZERO],
		[Vector3(0.0, ENV_RADIUS + 0.1, -2.0), red, 0.8, AmbientCraft.LightKind.BEACON, Vector3.ZERO],
		[Vector3(0.0, GONDOLA_Y - 0.2, -ENV_LENGTH * 0.5 + 22.0), red, 0.7, AmbientCraft.LightKind.BEACON, Vector3.ZERO],
		[Vector3(tip_a.x, tip_a.y, tip_a.z), white, 0.9, AmbientCraft.LightKind.STROBE, Vector3.ZERO],
		[Vector3(-tip_a.x, tip_a.y, tip_a.z), white, 0.9, AmbientCraft.LightKind.STROBE, Vector3.ZERO],
	]


# --- The tow plane ----------------------------------------------------------------------------

## The banner tow plane (cached): one mesh for the fleet, yellow with a red flash, as one
## operator's banner fleet usually is.
static func plane() -> ArrayMesh:
	if _plane == null:
		_plane = _build_plane().commit()
	return _plane


## Where the tow hook is (the rope's front end), plane space.
const TOW_HOOK := Vector3(0.0, 0.05, 3.85)


static func _build_plane() -> Geo:
	var g := Geo.new()
	var yellow := Color(0.98, 0.78, 0.12)
	var red := Color(0.78, 0.10, 0.07)
	var black := Color(0.04, 0.04, 0.04)
	var grey := Color(0.6, 0.6, 0.62)
	# Fuselage, nose (-Z) to tail post.
	g.loft([
		[-3.05, 0.25, 0.12, 0.12, 2.0],
		[-2.95, 0.25, 0.38, 0.40, 2.2],
		[-2.3, 0.28, 0.42, 0.46, 2.6],
		[-1.6, 0.35, 0.40, 0.62, 3.2],
		[-0.6, 0.38, 0.39, 0.66, 3.4],
		[0.3, 0.36, 0.37, 0.6, 3.2],
		[1.4, 0.32, 0.28, 0.42, 3.0],
		[2.6, 0.30, 0.17, 0.27, 2.6],
		[3.75, 0.30, 0.06, 0.16, 2.2],
	], 18, K_PAINT, yellow)
	# The red flash down the side and the cowl's black front.
	for side: float in [1.0, -1.0]:
		g.fquad(Vector3(0.405 * side, 0.18, -2.4), Vector3(0.40 * side, 0.18, 0.4), Vector3(0.38 * side, 0.28, 0.4), Vector3(0.415 * side, 0.30, -2.4), Vector3(side, 0, 0), K_PAINT, red)
		g.fquad(Vector3(0.36 * side, 0.20, 0.4), Vector3(0.18 * side, 0.26, 2.7), Vector3(0.18 * side, 0.32, 2.7), Vector3(0.36 * side, 0.31, 0.4), Vector3(side, 0, 0), K_PAINT, red)
		# Side windows.
		g.fquad(Vector3(0.40 * side, 0.55, -1.25), Vector3(0.40 * side, 0.55, 0.3), Vector3(0.38 * side, 0.92, 0.3), Vector3(0.39 * side, 0.94, -1.2), Vector3(side, 0, 0), K_GLASS, black)
	# Windshield.
	g.fquad(Vector3(-0.36, 0.62, -1.62), Vector3(0.36, 0.62, -1.62), Vector3(0.33, 0.98, -1.25), Vector3(-0.33, 0.98, -1.25), Vector3(0, 0.6, -1), K_GLASS, black)
	# The wing: high, on top of the cabin, a rounded leading edge.
	var wy := 1.02
	var le := -1.55
	var chord := 1.6
	var foil := PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.06, 0.07), Vector2(0.3, 0.11), Vector2(0.8, 0.09), Vector2(chord, 0.0), Vector2(0.8, -0.015), Vector2(0.25, -0.02), Vector2(0.05, -0.02)])
	for side: float in [1.0, -1.0]:
		var span := 5.35
		var steps := 6
		var wb := g.v.size()
		for s in steps + 1:
			var x := side * (0.2 + (span - 0.2) * float(s) / steps)
			for p in foil:
				var nn := Vector3(0, signf(p.y - 0.03) if absf(p.y - 0.03) > 0.02 else 0.0, -1.0 if p.x < 0.1 else 0.0)
				if nn.length() < 0.01:
					nn = Vector3(0, 1, 0)
				g.vert(Vector3(x, wy + p.y, le + p.x), nn.normalized(), K_PAINT, yellow)
		var fc := foil.size()
		for s in steps:
			for i in fc:
				var a := wb + s * fc + i
				var b := wb + s * fc + (i + 1) % fc
				var mid := (g.v[a] + g.v[b]) * 0.5 - Vector3(g.v[a].x, wy + 0.04, le + 0.6)
				g.quad(a, b, b + fc, a + fc, Vector3(0, mid.y, mid.z * 0.4))
		# The tip cap.
		var tip := PackedVector2Array()
		for p in foil:
			tip.append(Vector2(p.x, p.y))
		var tris := Geometry2D.triangulate_polygon(tip)
		for t in range(0, tris.size(), 3):
			var pa := Vector3(side * span, wy + tip[tris[t]].y, le + tip[tris[t]].x)
			var pb := Vector3(side * span, wy + tip[tris[t + 1]].y, le + tip[tris[t + 1]].x)
			var pc := Vector3(side * span, wy + tip[tris[t + 2]].y, le + tip[tris[t + 2]].x)
			g.ftri(pa, pb, pc, Vector3(side, 0, 0), K_PAINT, red)
		# Struts: a V from the lower fuselage to the wing.
		g.tube(Vector3(0.36 * side, -0.05, -1.3), Vector3(3.1 * side, wy - 0.02, le + 0.25), 0.035, 0.035, 6, K_PAINT, yellow)
		g.tube(Vector3(0.36 * side, -0.05, -0.9), Vector3(3.1 * side, wy - 0.02, le + 1.2), 0.035, 0.035, 6, K_PAINT, yellow)
		# Main gear: a leg and a fat tyre.
		var wheel := Vector3(1.0 * side, -0.72, -1.45)
		g.tube(Vector3(0.3 * side, -0.1, -1.5), wheel + Vector3(-0.08 * side, 0.1, 0), 0.04, 0.04, 6, K_METAL, grey)
		g.tube(wheel - Vector3(0.14, 0, 0), wheel + Vector3(0.14, 0, 0), 0.36, 0.36, 16, K_DARK, black, true)
		g.tube(wheel - Vector3(0.16, 0, 0), wheel + Vector3(0.16, 0, 0), 0.12, 0.12, 10, K_METAL, grey, true)
	# The tail: stabiliser, fin and rudder.
	var stab := PackedVector2Array([Vector2(-1.7, 2.75), Vector2(1.7, 2.75), Vector2(1.55, 3.6), Vector2(-1.55, 3.6)])
	g.plate(Vector3(0, 0.32, 0), Vector3(1, 0, 0), Vector3(0, 0, 1), stab, 0.06, K_PAINT, yellow)
	var fin := PackedVector2Array([Vector2(2.7, 0.35), Vector2(3.8, 0.3), Vector2(3.85, 1.35), Vector2(3.45, 1.4)])
	g.plate(Vector3.ZERO, Vector3(0, 0, 1), Vector3(0, 1, 0), fin, 0.06, K_PAINT, red)
	# Tail wheel and the tow hook.
	g.tube(Vector3(0, 0.15, 3.6), Vector3(0, -0.12, 3.75), 0.02, 0.02, 4, K_METAL, grey)
	g.tube(Vector3(-0.04, -0.15, 3.78), Vector3(0.04, -0.15, 3.78), 0.09, 0.09, 8, K_DARK, black, true)
	g.box(Transform3D(Basis(), TOW_HOOK), Vector3(0.04, 0.04, 0.06), K_METAL, grey)
	# The spinner and the blurred prop.
	g.tube(Vector3(0, 0.25, -3.05), Vector3(0, 0.25, -3.32), 0.14, 0.03, 10, K_PAINT, red, true)
	for f: float in [-1.0, 1.0]:
		var b := g.v.size()
		for cc in 4:
			var cuv := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)][cc] as Vector2
			g.vert(Vector3((cuv.x - 0.5) * 1.9, 0.25 + (cuv.y - 0.5) * 1.9, -3.18 + f * 0.005), Vector3(0, 0, -f), K_PROP, Color.BLACK, cuv)
		g.quad(b, b + 1, b + 2, b + 3, Vector3(0, 0, -f))
	# Wing-tip lamps' lenses.
	g.box(Transform3D(Basis(), Vector3(-5.36, wy + 0.04, le + 0.2)), Vector3(0.03, 0.05, 0.1), K_LAMP, Color(1.0, 0.1, 0.06))
	g.box(Transform3D(Basis(), Vector3(5.36, wy + 0.04, le + 0.2)), Vector3(0.03, 0.05, 0.1), K_LAMP, Color(0.15, 1.0, 0.35))
	return g


static func plane_light_specs() -> Array:
	var red := Color(1.0, 0.10, 0.06, 1.0)
	var green := Color(0.15, 1.0, 0.35, 1.0)
	var white := Color(1.0, 0.98, 0.92, 1.0)
	return [
		[Vector3(-5.4, 1.06, -1.35), red, 0.3, AmbientCraft.LightKind.STEADY, Vector3.ZERO],
		[Vector3(5.4, 1.06, -1.35), green, 0.3, AmbientCraft.LightKind.STEADY, Vector3.ZERO],
		[Vector3(-5.4, 1.08, -1.3), white, 0.5, AmbientCraft.LightKind.STROBE, Vector3.ZERO],
		[Vector3(5.4, 1.08, -1.3), white, 0.5, AmbientCraft.LightKind.STROBE, Vector3.ZERO],
		[Vector3(0.0, 1.42, 3.5), red, 0.35, AmbientCraft.LightKind.BEACON, Vector3.ZERO],
	]


# --- The banner -------------------------------------------------------------------------------

## A letter banner for `text` (cached): white cloth BANNER_HEIGHT tall, the letters in `ink`
## on both faces (each reads left to right from its own side), the lead pole at z 0 with its
## weight at the bottom, a red streamer off the tail. It lies in its local YZ plane trailing
## along +Z; UV2 = (metres from the lead pole, 1) so the shader flutters it.
static func banner(text: String, ink: Color) -> ArrayMesh:
	var key := "%s|%s" % [text, ink.to_html()]
	if _banners.has(key):
		return _banners[key]
	var g := Geo.new()
	var cloth := Color(0.93, 0.93, 0.9)
	var width: float = FreewayKit.text_geo(text, BANNER_LETTER)[2]
	var length := width + BANNER_MARGIN * 2.0
	var h := BANNER_HEIGHT
	var cols := maxi(8, ceili(length / 1.2))
	for side: float in [1.0, -1.0]:
		var b := g.v.size()
		for k in cols + 1:
			var z := 0.3 + length * float(k) / cols
			for j in 2:
				var y := h * (float(j) - 0.5)
				g.vert(Vector3(0.004 * side, y, z), Vector3(side, 0, 0), K_CLOTH, cloth, Vector2(z / length, float(j)), Vector2(z, 1.0))
		for k in cols:
			var p := b + k * 2
			g.quad(p, p + 1, p + 3, p + 2, Vector3(side, 0, 0))
		var zc := 0.3 + length * 0.5
		var place := func(q: Vector2) -> Array:
			var z := zc + (q.x if side < 0.0 else -q.x)
			return [Vector3(0.02 * side, q.y, z), Vector3(side, 0, 0), Vector2(z, 1.0)]
		g.text(text, BANNER_LETTER, place, K_LETTER, ink)
	# The lead pole, its weight and the bridle; the streamer off the tail.
	g.tube(Vector3(0, -h * 0.5 - 0.35, 0.15), Vector3(0, h * 0.5 + 0.2, 0.15), 0.04, 0.04, 6, K_METAL, Color(0.5, 0.5, 0.52), true)
	g.tube(Vector3(0, -h * 0.5 - 0.6, 0.15), Vector3(0, -h * 0.5 - 0.3, 0.15), 0.11, 0.11, 8, K_DARK, Color(0.1, 0.1, 0.1), true)
	var sb := g.v.size()
	for k in 7:
		var z := 0.3 + length + float(k) * 0.8
		for j in 2:
			var y := lerpf(-0.25, 0.25, float(j)) + h * 0.3
			for side: float in [1.0, -1.0]:
				g.vert(Vector3(0.004 * side, y, z), Vector3(side, 0, 0), K_CLOTH, Color(0.85, 0.12, 0.08), Vector2.ZERO, Vector2(z, 1.0))
	for k in 6:
		for side in 2:
			var p := sb + k * 4 + side
			var nrm := Vector3(1 if side == 0 else -1, 0, 0)
			g.quad(p, p + 2, p + 6, p + 4, nrm)
	var m := g.commit()
	m.set_meta("length", length + 5.6)
	_banners[key] = m
	return m


## A unit tow rope: 1 m along +Z, 1.5 cm thick (scaled along z to its length).
static func rope() -> ArrayMesh:
	if _rope == null:
		var g := Geo.new()
		g.tube(Vector3.ZERO, Vector3(0, 0, 1), 0.015, 0.015, 5, K_ROPE, Color(0.85, 0.82, 0.72))
		_rope = g.commit()
	return _rope


## Triangle counts (checks, the HANDOFF).
static func triangle_counts() -> Dictionary:
	return {"blimp": _build_blimp().triangles(), "plane": _build_plane().triangles()}
