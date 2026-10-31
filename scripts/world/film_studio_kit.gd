class_name FilmStudioKit
extends RefCounted
## The film studio lot's hardware (FilmStudio lays it out), code-built at real size into ONE
## SurfaceTool a chunk on shaders/film_studio.gdshader: what a face is rides in COLOR.a (K_*, in
## 32nds), its paint in COLOR.rgb (display numbers), UV metres in the face's frame and UV2 (height,
## a per-box parameter), written by IndustrialKit's box / cyl / cone writers and the quads, letters
## and emblems below. Everything is in a local frame handed in as `xf` (rotation and translation,
## never scale): +y up, and for a building its front toward +z unless said otherwise.
##
## Names and marks are invented: the studio is SUNSPIRE PICTURES, its mark a half sun rising
## behind a spire (emblem()), drawn here, never a real studio's.

const K_STUCCO := 0
const K_ROOF := 1
const K_DOOR := 2
const K_STEEL := 3
const K_GLASS := 4
const K_LAMP := 5
const K_BRICK := 6
const K_STONE := 7
const K_WOOD := 8
const K_CANVAS := 9
const K_SIGN := 10
const K_CONCRETE := 11
const K_GILT := 12
const K_RUBBER := 13
const K_CHROME := 14
const K_TRAILER := 15
const K_FELT := 16
## Ribbed metal siding (a stage clad in it rather than stucco).
const K_CORR := 17

const STUDIO_NAME := "SUNSPIRE PICTURES"
const SHORT_NAME := "SUNSPIRE"

## Stage stucco: the studio's beiges, and the painted number's colours.
const STAGE_PAINTS := [Color(0.86, 0.79, 0.66), Color(0.84, 0.76, 0.62), Color(0.88, 0.82, 0.71), Color(0.8, 0.73, 0.6)]
const NUMBER_PAINTS := [Color(0.36, 0.16, 0.12), Color(0.14, 0.13, 0.12), Color(0.2, 0.24, 0.3)]
const DOOR_PAINTS := [Color(0.62, 0.55, 0.45), Color(0.45, 0.42, 0.38), Color(0.55, 0.32, 0.22), Color(0.7, 0.66, 0.58)]
const TRIM := Color(0.24, 0.22, 0.2)
const GILT := Color(0.86, 0.68, 0.36)

static var _material: ShaderMaterial
## Triangles written since start (the probe reads it).
static var tris: int = 0


static func material() -> ShaderMaterial:
	if _material != null:
		return _material
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/film_studio.gdshader")
	mat.set_shader_parameter("concrete_tex", PropFactory.texture("concrete", "Color"))
	mat.set_shader_parameter("brick_tex", PropFactory.texture("brick_factory", "Color"))
	mat.set_shader_parameter("planks_tex", PropFactory.texture("planks", "Color"))
	_material = mat
	return mat


static func h01(parts: Array) -> float:
	return float(absi(hash(parts)) % 100003) / 100003.0


# --- Writers ----------------------------------------------------------------------------------

static func box(st: SurfaceTool, xf: Transform3D, size: Vector3, kind: int, paint: Color, param: float = 0.0, skip: int = 32) -> void:
	tris += 12
	IndustrialKit.box(st, xf, size, kind, paint, param, skip)


## An upright cylinder (axis +y in `xf`), `segs` sided, foot at xf's origin, with its top cap. Its
## own writer: IndustrialKit.cyl() winds the walls the other way round, so they cull from outside.
static func cyl(st: SurfaceTool, xf: Transform3D, r: float, h: float, kind: int, paint: Color, segs: int = 12, cap: bool = true) -> void:
	var circ := TAU * r
	var top := xf * Vector3(0.0, h, 0.0)
	var up := (xf.basis * Vector3.UP).normalized()
	for i in segs:
		var a0 := TAU * float(i) / float(segs)
		var a1 := TAU * float(i + 1) / float(segs)
		var d0 := Vector3(cos(a0), 0.0, sin(a0))
		var d1 := Vector3(cos(a1), 0.0, sin(a1))
		var p00 := xf * (d0 * r)
		var p10 := xf * (d1 * r)
		var p11 := xf * (d1 * r + Vector3(0.0, h, 0.0))
		var p01 := xf * (d0 * r + Vector3(0.0, h, 0.0))
		var mid := (xf.basis * ((d0 + d1) * 0.5)).normalized()
		var u0 := circ * float(i) / float(segs)
		var u1 := circ * float(i + 1) / float(segs)
		quad(st, p00, p10, p11, p01, mid, kind, paint, [Vector2(u0, 0.0), Vector2(u1, 0.0), Vector2(u1, h), Vector2(u0, h)], h)
		if cap:
			quad(st, top, p01, p11, p11, up, kind, paint, [Vector2(r, r), Vector2(r + d0.x * r, r + d0.z * r), Vector2(r + d1.x * r, r + d1.z * r), Vector2(r + d1.x * r, r + d1.z * r)], h)


## A cone from radius `r` at the foot to a point `h` above (a tank's roof), along xf's +y.
static func cone(st: SurfaceTool, xf: Transform3D, r: float, h: float, kind: int, paint: Color, segs: int = 12) -> void:
	var tip := xf * Vector3(0.0, h, 0.0)
	var slope := Vector2(h, r).normalized()
	for i in segs:
		var a0 := TAU * float(i) / float(segs)
		var a1 := TAU * float(i + 1) / float(segs)
		var am := (a0 + a1) * 0.5
		var p0 := xf * Vector3(cos(a0) * r, 0.0, sin(a0) * r)
		var p1 := xf * Vector3(cos(a1) * r, 0.0, sin(a1) * r)
		var n := (xf.basis * Vector3(cos(am) * slope.x, slope.y, sin(am) * slope.x)).normalized()
		var s0 := TAU * r * float(i) / float(segs)
		var s1 := TAU * r * float(i + 1) / float(segs)
		var sl := Vector2(h, r).length()
		quad(st, p0, p1, tip, tip, n, kind, paint, [Vector2(s0, 0.0), Vector2(s1, 0.0), Vector2((s0 + s1) * 0.5, sl), Vector2((s0 + s1) * 0.5, sl)], sl)


## A box from `a` to `b` (a strut, a rail, a ray), `w` x `t` in section; `up` steers its roll.
static func beam(st: SurfaceTool, a: Vector3, b: Vector3, w: float, t: float, kind: int, paint: Color, up: Vector3 = Vector3.UP) -> void:
	var d := b - a
	var l := d.length()
	if l < 0.01:
		return
	var z := d / l
	var x := up.cross(z)
	if x.length_squared() < 1e-6:
		x = Vector3.RIGHT.cross(z)
	x = x.normalized()
	var y := z.cross(x).normalized()
	box(st, Transform3D(Basis(x, y, z), (a + b) * 0.5), Vector3(w, t, l), kind, paint)


## A quad a-b-c-d (in order round it) facing `facing`, with its four UVs.
static func quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, facing: Vector3, kind: int, paint: Color,
		uvs: Array, h: float, param: float = 0.0) -> void:
	tris += 2
	var col := Color(paint.r, paint.g, paint.b, (float(kind) + 0.5) / 32.0)
	var pts := [a, b, c, d]
	var order := [0, 2, 1, 0, 3, 2] if (b - a).cross(c - a).dot(facing) > 0.0 else [0, 1, 2, 0, 2, 3]
	var n := facing.normalized()
	for k: int in order:
		st.set_normal(n)
		st.set_color(col)
		st.set_uv(uvs[k])
		st.set_uv2(Vector2(h, param))
		st.add_vertex(pts[k])


## Flat 2D triangles (a list of points, three a triangle) laid into the plane of `xf` (local x
## right, y up, facing +z), or bent round a vertical cylinder of radius `bend` about xf's origin
## (x becomes arc length, the face looking out).
static func flat2d(st: SurfaceTool, pts: PackedVector2Array, xf: Transform3D, kind: int, paint: Color, bend: float = 0.0) -> void:
	var col := Color(paint.r, paint.g, paint.b, (float(kind) + 0.5) / 32.0)
	for i in range(0, pts.size() - 2, 3):
		var w: Array[Vector3] = []
		var mid := (pts[i] + pts[i + 1] + pts[i + 2]) / 3.0
		for k in 3:
			var p := pts[i + k]
			if bend > 0.0:
				var a := p.x / bend
				w.append(xf * Vector3(sin(a) * bend, p.y, cos(a) * bend))
			else:
				w.append(xf * Vector3(p.x, p.y, 0.0))
		var facing := xf.basis * (Vector3(sin(mid.x / bend), 0.0, cos(mid.x / bend)) if bend > 0.0 else Vector3.BACK)
		var n := (w[1] - w[0]).cross(w[2] - w[0])
		if n.length_squared() < 1e-12:
			continue
		var order := [0, 2, 1] if n.dot(facing) > 0.0 else [0, 1, 2]
		tris += 1
		for k: int in order:
			st.set_normal(facing.normalized())
			st.set_color(col)
			st.set_uv(pts[i + k])
			st.set_uv2(Vector2(1.0, 0.0))
			st.add_vertex(w[k])


## Lettering as flat 2D triangles at cap height `height`, centred on the origin; its width in [1].
static func text2d(text: String, height: float) -> Array:
	var geo := FreewayKit.text_geo(text, height)
	var verts: PackedVector3Array = geo[0]
	var idx: PackedInt32Array = geo[1]
	var out := PackedVector2Array()
	for k in idx:
		out.append(Vector2(verts[k].x, verts[k].y))
	return [out, float(geo[2])]


## Lettering laid on a face: `xf` is the face's frame (+z out of it), the text centred on its origin.
static func letters(st: SurfaceTool, text: String, height: float, xf: Transform3D, kind: int, paint: Color, bend: float = 0.0) -> float:
	var t := text2d(text, height)
	flat2d(st, t[0], xf, kind, paint, bend)
	return t[1]


## The studio's mark: a half sun rising behind a spire, `r` its radius, the disc's foot on y 0.
static func emblem(r: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var segs := 16
	# The half disc, with a gap round the spire.
	for i in segs:
		var a0 := PI * float(i) / float(segs)
		var a1 := PI * float(i + 1) / float(segs)
		out.append_array([Vector2.ZERO, Vector2(cos(a0), sin(a0)) * r * 0.55, Vector2(cos(a1), sin(a1)) * r * 0.55])
	# Eleven rays fanned above it.
	for k in 11:
		var a := PI * (float(k) + 1.0) / 12.0
		var dir := Vector2(cos(a), sin(a))
		var side := Vector2(-dir.y, dir.x)
		var w := r * (0.07 if k % 2 == 0 else 0.045)
		var r0 := r * 0.64
		var r1 := r * (1.0 if k % 2 == 0 else 0.84)
		out.append_array([dir * r0 + side * w, dir * r0 - side * w, dir * r1])
	# The spire: a tall slim needle from below the horizon line.
	out.append_array([Vector2(-r * 0.06, -r * 0.1), Vector2(r * 0.06, -r * 0.1), Vector2(0.0, r * 1.35)])
	# The horizon bar under it all.
	out.append_array([Vector2(-r * 1.05, -r * 0.04), Vector2(r * 1.05, -r * 0.04), Vector2(r * 1.05, -r * 0.13)])
	out.append_array([Vector2(-r * 1.05, -r * 0.04), Vector2(r * 1.05, -r * 0.13), Vector2(-r * 1.05, -r * 0.13)])
	return out


# --- Sound stage --------------------------------------------------------------------------------

## A sound stage, `size` (x across, y the wall height, z along the ridge), its floor centre at
## xf's origin. `doors` is [[side (+1 / -1: the +x / -x wall), z centre, width, height], ...];
## `seed` picks its paints and details. The painted number goes on both long walls and the gable.
static func stage(st: SurfaceTool, xf: Transform3D, size: Vector3, number: int, doors: Array, seed: int, rolling: bool) -> void:
	var W := size.x
	var H := size.y
	var L := size.z
	var paint: Color = STAGE_PAINTS[seed % STAGE_PAINTS.size()]
	var npaint: Color = NUMBER_PAINTS[(seed / 7) % NUMBER_PAINTS.size()]
	var dpaint: Color = DOOR_PAINTS[(seed / 3) % DOOR_PAINTS.size()]
	var T := 0.4
	var rise := W * 0.11
	# Two in five stages are clad in ribbed metal siding over a concrete wainscot; the rest stucco.
	var wk := K_CORR if (seed / 11) % 5 < 2 else K_STUCCO
	if wk == K_CORR:
		paint = paint.lerp(Color(0.8, 0.79, 0.74), 0.5)
	# Plinth.
	box(st, xf * Transform3D(Basis(), Vector3(0.0, 0.22, 0.0)), Vector3(W + 0.16, 0.44, L + 0.16), K_CONCRETE, Color(0.66, 0.64, 0.6))
	# Long walls, cut round the elephant doors.
	for side: float in [1.0, -1.0]:
		var cuts: Array = []
		for d: Array in doors:
			if float(d[0]) == side:
				cuts.append([float(d[1]) - float(d[2]) * 0.5, float(d[1]) + float(d[2]) * 0.5, float(d[3])])
		cuts.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
		var z := -L * 0.5
		var x := side * (W * 0.5 - T * 0.5)
		for c: Array in cuts + [[L * 0.5, L * 0.5, 0.0]]:
			var z0 := maxf(float(c[0]), z)
			if z0 - z > 0.05:
				box(st, xf * Transform3D(Basis(), Vector3(x, H * 0.5, (z + z0) * 0.5)), Vector3(T, H, z0 - z), wk, paint)
			var z1 := float(c[1])
			if z1 - z0 > 0.05:
				var dh := float(c[2])
				box(st, xf * Transform3D(Basis(), Vector3(x, (dh + H) * 0.5, (z0 + z1) * 0.5)), Vector3(T, H - dh, z1 - z0), wk, paint)
			z = maxf(z, z1)
		# Pilasters every ~6.5 m clear of the doors, the corner piers, the coping band.
		var n := maxi(2, int(round(L / 6.5)))
		for k in range(1, n):
			var pz := -L * 0.5 + L * float(k) / float(n)
			var clear := true
			for c: Array in cuts:
				if pz > float(c[0]) - 0.9 and pz < float(c[1]) + 0.9:
					clear = false
			if clear:
				box(st, xf * Transform3D(Basis(), Vector3(side * (W * 0.5 + 0.12), (H + 0.2) * 0.5, pz)), Vector3(0.3, H + 0.2, 0.75), K_STUCCO, paint)
				if k % 3 == 1:
					# A downspout beside it.
					box(st, xf * Transform3D(Basis(), Vector3(side * (W * 0.5 + 0.1), H * 0.5, pz + 0.6)), Vector3(0.14, H, 0.14), K_STEEL, paint * 0.8)
		box(st, xf * Transform3D(Basis(), Vector3(side * (W * 0.5 + 0.02), H + 0.25, 0.0)), Vector3(T + 0.5, 0.5, L + 0.5), K_STUCCO, paint * 0.93)
	for sz: float in [1.0, -1.0]:
		box(st, xf * Transform3D(Basis(), Vector3(0.0, H * 0.5, sz * (L * 0.5 - T * 0.5))), Vector3(W - 2.0 * T, H, T), wk, paint)
		for sx: float in [1.0, -1.0]:
			box(st, xf * Transform3D(Basis(), Vector3(sx * (W * 0.5 - 0.1), (H + 0.6) * 0.5, sz * (L * 0.5 - 0.1))), Vector3(1.3, H + 0.6, 1.3), K_STUCCO, paint * 0.97)
		# The gable: a triangle of wall to the ridge, its rakes capped.
		var g := xf.basis * Vector3(0.0, 0.0, sz)
		var p0 := xf * Vector3(-W * 0.5, H, sz * L * 0.5)
		var p1 := xf * Vector3(W * 0.5, H, sz * L * 0.5)
		var p2 := xf * Vector3(0.0, H + rise, sz * L * 0.5)
		quad(st, p0, p1, p2, p2, g, wk, paint, [Vector2(0.0, H), Vector2(W, H), Vector2(W * 0.5, H + rise), Vector2(W * 0.5, H + rise)], H + rise)
		var back := xf * Vector3(0.0, 0.0, -sz * 0.4)
		var q0 := p0 - (g * 0.4)
		var q1 := p1 - (g * 0.4)
		var q2 := p2 - (g * 0.4)
		quad(st, q0, q1, q2, q2, -g, wk, paint, [Vector2(0.0, H), Vector2(W, H), Vector2(W * 0.5, H + rise), Vector2(W * 0.5, H + rise)], H + rise)
		for s2: float in [-1.0, 1.0]:
			var e0 := xf * Vector3(s2 * (W * 0.5 + 0.25), H + 0.4, sz * (L * 0.5 + 0.05))
			var e1 := xf * Vector3(0.0, H + rise + 0.45, sz * (L * 0.5 + 0.05))
			beam(st, e0, e1, 0.7, 0.4, K_STUCCO, paint * 0.93, xf.basis * Vector3(0.0, 0.0, 1.0))
		# A personnel door with its canopy and lamp, off centre.
		var dx := W * 0.28 * (1.0 if seed % 2 == 0 else -1.0)
		box(st, xf * Transform3D(Basis(), Vector3(dx, 1.4, sz * (L * 0.5 + 0.02))), Vector3(1.1, 2.4, 0.1), K_STEEL, dpaint * 0.8)
		box(st, xf * Transform3D(Basis(), Vector3(dx, 3.0, sz * (L * 0.5 + 0.6))), Vector3(2.2, 0.12, 1.2), K_STEEL, Color(0.3, 0.3, 0.31))
		box(st, xf * Transform3D(Basis(), Vector3(dx, 2.82, sz * (L * 0.5 + 0.9))), Vector3(0.3, 0.1, 0.3), K_LAMP, Color(1.0, 0.86, 0.62))
	# The roof: two slopes of standing seam from the eaves to the ridge.
	for sx: float in [1.0, -1.0]:
		var a := xf * Vector3(sx * (W * 0.5 + 0.35), H + 0.45, -L * 0.5 - 0.35)
		var b := xf * Vector3(sx * (W * 0.5 + 0.35), H + 0.45, L * 0.5 + 0.35)
		var c := xf * Vector3(0.0, H + rise + 0.5, L * 0.5 + 0.35)
		var d := xf * Vector3(0.0, H + rise + 0.5, -L * 0.5 - 0.35)
		var slope := Vector2(W * 0.5 + 0.35, rise + 0.05).length()
		var up := xf.basis * Vector3(sx * (rise + 0.05), W * 0.5 + 0.35, 0.0).normalized()
		quad(st, a, b, c, d, up, K_ROOF, Color.WHITE, [Vector2(0.0, 0.0), Vector2(L + 0.7, 0.0), Vector2(L + 0.7, slope), Vector2(0.0, slope)], slope, float(seed % 97))
		# Under the eave (seen from the street close to).
		quad(st, a, b, b - xf.basis.y * 0.15, a - xf.basis.y * 0.15, xf.basis * Vector3(sx, 0.0, 0.0), K_STEEL, Color(0.5, 0.5, 0.5), [Vector2.ZERO, Vector2(L, 0.0), Vector2(L, 0.15), Vector2(0.0, 0.15)], 0.15)
	# Roof plant: a row of ventilators along the ridge.
	var nv := maxi(2, int(L / 14.0))
	for k in nv:
		var vz := -L * 0.5 + L * (float(k) + 0.5) / float(nv)
		cyl(st, xf * Transform3D(Basis(), Vector3(0.0, H + rise + 0.3, vz)), 0.45, 1.1, K_STEEL, Color(0.62, 0.63, 0.63), 10, true)
	# Package air handlers on steel platforms down the roof, each with its fans and a duct
	# into the roof - a stage is a huge, sealed, air-conditioned box.
	var nu_roof := 2 if L < 52.0 else 3
	for k in nu_roof:
		var rz := -L * 0.5 + L * (float(k) + 0.5) / float(nu_roof) + L * 0.08
		var sx := (1.0 if (seed + k) % 2 == 0 else -1.0)
		var rx := sx * W * 0.24
		var ry := H + 0.45 + (rise + 0.05) * (1.0 - absf(rx) / (W * 0.5 + 0.35))
		box(st, xf * Transform3D(Basis(), Vector3(rx, ry + 0.55, rz)), Vector3(3.6, 0.14, 2.8), K_STEEL, Color(0.34, 0.35, 0.36))
		for c: Vector2 in [Vector2(-1.6, -1.2), Vector2(1.6, -1.2), Vector2(-1.6, 1.2), Vector2(1.6, 1.2)]:
			box(st, xf * Transform3D(Basis(), Vector3(rx + c.x, ry + 0.2, rz + c.y)), Vector3(0.12, 0.9, 0.12), K_STEEL, Color(0.34, 0.35, 0.36))
		box(st, xf * Transform3D(Basis(), Vector3(rx, ry + 1.42, rz)), Vector3(3.2, 1.6, 2.4), K_STEEL, Color(0.78, 0.79, 0.78))
		for f in 2:
			cyl(st, xf * Transform3D(Basis(), Vector3(rx + (float(f) - 0.5) * 1.5, ry + 2.22, rz)), 0.55, 0.12, K_RUBBER, Color(0.1, 0.1, 0.1), 12, true)
		box(st, xf * Transform3D(Basis(), Vector3(rx - sx * 2.0, ry + 0.8, rz)), Vector3(1.2, 0.9, 1.0), K_STEEL, Color(0.7, 0.71, 0.7))
	if wk == K_CORR:
		# The concrete wainscot, stopped at every door.
		for side: float in [1.0, -1.0]:
			var spans: Array = []
			for d: Array in doors:
				if float(d[0]) == side:
					spans.append([float(d[1]) - float(d[2]) * 0.5 - 0.3, float(d[1]) + float(d[2]) * 0.5 + 0.3])
			spans.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
			var z := -L * 0.5
			for sp: Array in spans + [[L * 0.5, L * 0.5]]:
				var z0 := float(sp[0])
				if z0 - z > 0.1:
					box(st, xf * Transform3D(Basis(), Vector3(side * (W * 0.5 + 0.06), 0.65, (z + z0) * 0.5)), Vector3(0.12, 1.3, z0 - z), K_CONCRETE, Color(0.7, 0.69, 0.66))
				z = maxf(z, float(sp[1]))
	# The elephant doors.
	for d: Array in doors:
		_elephant_door(st, xf, float(d[0]), float(d[1]), float(d[2]), float(d[3]), W, H, dpaint, rolling and d == doors[0], seed, number)
	# The painted number: high on both long walls toward one end, and on each gable.
	var label := str(number)
	var nh := clampf(H * 0.3, 3.2, 5.6)
	var nz := L * 0.5 - maxf(5.5, nh * 0.9)
	if seed % 2 == 1:
		nz = -nz
	for side: float in [1.0, -1.0]:
		var face := Transform3D(Basis(Vector3(0.0, 0.0, -side), Vector3.UP, Vector3(side, 0.0, 0.0)), Vector3(side * (W * 0.5 + 0.015), H * 0.66, nz))
		letters(st, label, nh, xf * face, K_SIGN, npaint)
	for sz: float in [1.0, -1.0]:
		var face := Transform3D(Basis(Vector3(sz, 0.0, 0.0), Vector3.UP, Vector3(0.0, 0.0, sz)), Vector3(0.0, H * 0.62, sz * (L * 0.5 + 0.015)))
		letters(st, label, nh * 1.15, xf * face, K_SIGN, npaint)
		var sface := Transform3D(Basis(Vector3(sz, 0.0, 0.0), Vector3.UP, Vector3(0.0, 0.0, sz)), Vector3(0.0, H * 0.62 + nh * 0.85, sz * (L * 0.5 + 0.015)))
		letters(st, "STAGE", nh * 0.24, xf * sface, K_SIGN, npaint)
	# HVAC on the ground along the long wall with fewest doors, its ducts up into the wall.
	var side_h := 1.0
	var count_pos := 0
	for d: Array in doors:
		if float(d[0]) > 0.0:
			count_pos += 1
	if count_pos * 2 > doors.size():
		side_h = -1.0
	var nu := 2 if L < 50.0 else 3
	for k in nu:
		var uz := -L * 0.5 + L * (float(k) + 0.5) / float(nu)
		var ok := true
		for d: Array in doors:
			if float(d[0]) == side_h and absf(float(d[1]) - uz) < float(d[2]) * 0.5 + 3.5:
				ok = false
		if not ok:
			continue
		var ux := side_h * (W * 0.5 + 1.4)
		box(st, xf * Transform3D(Basis(), Vector3(ux, 0.95, uz)), Vector3(2.2, 1.6, 4.2), K_STEEL, Color(0.74, 0.75, 0.74))
		box(st, xf * Transform3D(Basis(), Vector3(ux, 0.12, uz)), Vector3(2.5, 0.24, 4.5), K_CONCRETE, Color(0.6, 0.6, 0.58))
		for f in 2:
			cyl(st, xf * Transform3D(Basis(), Vector3(ux, 1.75, uz + (float(f) - 0.5) * 2.0)), 0.7, 0.08, K_RUBBER, Color(0.08, 0.08, 0.09), 12, true)
		box(st, xf * Transform3D(Basis(), Vector3(side_h * (W * 0.5 + 0.55), H * 0.45 + 1.0, uz)), Vector3(0.9, H * 0.9 - 2.0, 1.2), K_STEEL, Color(0.7, 0.71, 0.7))
		box(st, xf * Transform3D(Basis(), Vector3(side_h * (W * 0.5 + 0.95), 1.9, uz)), Vector3(1.4, 0.9, 1.2), K_STEEL, Color(0.7, 0.71, 0.7))
	# A zig-zag steel stair up the far gable to the roof.
	_stair(st, xf, W, H, L, seed)


static func _elephant_door(st: SurfaceTool, xf: Transform3D, side: float, zc: float, w: float, dh: float, W: float, H: float, paint: Color, rolling: bool, seed: int, number: int) -> void:
	var out := Basis(Vector3(0.0, 0.0, -side), Vector3.UP, Vector3(side, 0.0, 0.0))
	var face := W * 0.5
	# The leaves, set back in the wall's depth, closed; two leaves on a narrow door, three wider.
	var leaves := 2 if w < 9.5 else 3
	var lw := w / float(leaves)
	var plane := face - 0.32
	box(st, xf * Transform3D(out, Vector3(side * plane, dh * 0.5, zc)), Vector3(w, dh, 0.16), K_DOOR, paint, lw, 32 | 16)
	# Each leaf's frame of stiffeners standing proud of its skin: stiles at its edges, rails at
	# the foot, the head and every 2.5 m, a diagonal brace, the hangers on the track above.
	for k in leaves:
		var lz := zc - w * 0.5 + lw * (float(k) + 0.5)
		for e: float in [-1.0, 1.0]:
			box(st, xf * Transform3D(Basis(), Vector3(side * (plane + 0.13), dh * 0.5, lz + e * (lw * 0.5 - 0.09))), Vector3(0.1, dh, 0.16), K_STEEL, paint * 0.88)
		var ry := 0.18
		while ry < dh:
			box(st, xf * Transform3D(Basis(), Vector3(side * (plane + 0.12), ry, lz)), Vector3(0.08, 0.14, lw - 0.3), K_STEEL, paint * 0.9)
			ry += 2.5
		box(st, xf * Transform3D(Basis(), Vector3(side * (plane + 0.12), dh - 0.12, lz)), Vector3(0.08, 0.16, lw - 0.3), K_STEEL, paint * 0.9)
		beam(st, xf * Vector3(side * (plane + 0.11), 0.3, lz - lw * 0.5 + 0.2), xf * Vector3(side * (plane + 0.11), minf(dh - 0.3, 2.5 * floor(dh / 2.5)), lz + lw * 0.5 - 0.2), 0.12, 0.06, K_STEEL, paint * 0.86, xf.basis * Vector3(side, 0.0, 0.0))
		for e: float in [-1.0, 1.0]:
			box(st, xf * Transform3D(Basis(), Vector3(side * (face + 0.12), dh + 0.32, lz + e * lw * 0.3)), Vector3(0.12, 0.4, 0.22), K_STEEL, Color(0.25, 0.25, 0.26))
		# Rollers in the guide at the foot.
		box(st, xf * Transform3D(Basis(), Vector3(side * (plane + 0.1), 0.06, lz)), Vector3(0.2, 0.12, lw - 0.1), K_STEEL, Color(0.2, 0.2, 0.21))
	# The reveal: the wall's returns into the opening and its head, so the door sits in depth.
	for s2: float in [-1.0, 1.0]:
		box(st, xf * Transform3D(Basis(), Vector3(side * (face - 0.2), dh * 0.5, zc + s2 * (w * 0.5 + 0.02))), Vector3(0.4, dh, 0.04), K_STUCCO, Color(0.7, 0.66, 0.58))
	# The jambs and the head: a steel frame.
	for s2: float in [-1.0, 1.0]:
		box(st, xf * Transform3D(Basis(), Vector3(side * (face + 0.05), dh * 0.5, zc + s2 * (w * 0.5 + 0.12))), Vector3(0.24, dh, 0.24), K_STEEL, TRIM)
		# Bollards guarding the jambs.
		cyl(st, xf * Transform3D(Basis(), Vector3(side * (face + 0.6), 0.0, zc + s2 * (w * 0.5 + 0.35))), 0.14, 1.1, K_STEEL, Color(0.86, 0.72, 0.12), 10, true)
	box(st, xf * Transform3D(Basis(), Vector3(side * (face + 0.05), dh + 0.12, zc)), Vector3(0.24, 0.24, w + 0.48), K_STEEL, TRIM)
	# The track the leaves slide on, on brackets, running past the opening to the side they stack.
	var dir := 1.0 if seed % 2 == 0 else -1.0
	box(st, xf * Transform3D(Basis(), Vector3(side * (face + 0.24), dh + 0.6, zc + dir * w * 0.5)), Vector3(0.22, 0.3, w * 2.0), K_STEEL, Color(0.3, 0.3, 0.3))
	var t0 := zc + dir * w * 0.5 - w
	var bz := t0
	while bz <= t0 + w * 2.0 + 0.01:
		box(st, xf * Transform3D(Basis(), Vector3(side * (face + 0.12), dh + 0.6, bz)), Vector3(0.24, 0.12, 0.12), K_STEEL, Color(0.3, 0.3, 0.3))
		bz += 1.5
	# A wicket door in one leaf, with its handle.
	box(st, xf * Transform3D(out, Vector3(side * (plane + 0.1), 1.15, zc - w * 0.25)), Vector3(1.0, 2.2, 0.06), K_STEEL, paint * 0.82)
	box(st, xf * Transform3D(Basis(), Vector3(side * (plane + 0.16), 1.1, zc - w * 0.25 + 0.35)), Vector3(0.06, 0.04, 0.16), K_CHROME, Color(0.7, 0.7, 0.7))
	# The red light over the door in its cage, the bell beside it, the warning sign under them.
	var rz := zc - w * 0.5 - 0.9
	box(st, xf * Transform3D(Basis(), Vector3(side * (face + 0.1), dh + 1.2, rz)), Vector3(0.2, 0.7, 0.7), K_STEEL, Color(0.12, 0.12, 0.12))
	cyl(st, xf * Transform3D(Basis(Vector3.FORWARD, PI * 0.5 * side), Vector3(side * (face + 0.2), dh + 1.2, rz)), 0.24, 0.34, K_LAMP, Color(1.0, 0.06, 0.03), 12, true)
	for k in 3:
		var a := TAU * float(k) / 3.0
		beam(st, xf * Vector3(side * (face + 0.2), dh + 1.2 + cos(a) * 0.27, rz + sin(a) * 0.27), xf * Vector3(side * (face + 0.56), dh + 1.2 + cos(a) * 0.2, rz + sin(a) * 0.2), 0.025, 0.025, K_STEEL, Color(0.1, 0.1, 0.1))
	if rolling:
		_lamp_flag(st, xf * Transform3D(Basis(), Vector3(side * (face + 0.38), dh + 1.2, rz)))
	cyl(st, xf * Transform3D(Basis(Vector3.FORWARD, PI * 0.5 * side), Vector3(side * face, dh + 1.2, rz - 0.9)), 0.2, 0.2, K_CHROME, Color(0.72, 0.62, 0.36), 12, true)
	var sign := Transform3D(out, Vector3(side * (face + 0.03), dh - 0.1, rz))
	box(st, xf * sign * Transform3D(Basis(), Vector3(0.0, 0.0, 0.0)), Vector3(1.5, 0.75, 0.03), K_STUCCO, Color(0.93, 0.92, 0.88))
	var face_xf := xf * sign * Transform3D(Basis(), Vector3(0.0, 0.12, 0.02))
	letters(st, "STAGE %d" % number, 0.16, face_xf, K_SIGN, Color(0.12, 0.12, 0.12))
	letters(st, "RED LIGHT: DO NOT ENTER", 0.075, face_xf * Transform3D(Basis(), Vector3(0.0, -0.22, 0.0)), K_SIGN, Color(0.75, 0.08, 0.05))
	# A work light at the head.
	box(st, xf * Transform3D(Basis(), Vector3(side * (face + 0.25), dh + 1.05, zc + 0.6)), Vector3(0.4, 0.22, 0.6), K_LAMP, Color(1.0, 0.88, 0.7))
	# A concrete apron in front.
	box(st, xf * Transform3D(Basis(), Vector3(side * (face + 1.6), 0.04, zc)), Vector3(3.2, 0.08, w + 1.0), K_CONCRETE, Color(0.72, 0.71, 0.68))


## A lit lens's halo cap (a slightly larger, always-lit disc) for a rolling stage's red light.
static func _lamp_flag(st: SurfaceTool, xf: Transform3D) -> void:
	box(st, xf, Vector3(0.04, 0.36, 0.36), K_LAMP, Color(1.0, 0.1, 0.05), 1.0)


static func _stair(st: SurfaceTool, xf: Transform3D, W: float, H: float, L: float, seed: int) -> void:
	var sz := 1.0 if seed % 4 < 2 else -1.0
	var gx := W * 0.5 - 4.0
	var flights := maxi(2, int(ceil(H / 4.2)))
	var rise := H / float(flights)
	var run := rise * 1.15
	var z0 := sz * (L * 0.5 + 1.0)
	var steel := Color(0.32, 0.33, 0.34)
	for f in flights:
		var y0 := rise * float(f)
		var y1 := y0 + rise
		var dirx := -1.0 if f % 2 == 0 else 1.0
		var xa := gx + (0.0 if f % 2 == 0 else -run)
		var xb := xa + dirx * run
		var a := xf * Vector3(xa, y0, z0)
		var b := xf * Vector3(xb, y1, z0)
		beam(st, a + xf.basis * Vector3(0.0, 0.1, 0.0), b + xf.basis * Vector3(0.0, 0.1, 0.0), 1.1, 0.18, K_STEEL, steel, xf.basis * Vector3(0.0, 0.0, 1.0))
		beam(st, a + xf.basis * Vector3(0.0, 1.05, sz * 0.5), b + xf.basis * Vector3(0.0, 1.05, sz * 0.5), 0.05, 0.05, K_STEEL, steel)
		var land := xf * Vector3(xb + dirx * 0.6, y1, z0)
		box(st, Transform3D(xf.basis, land), Vector3(1.4, 0.12, 1.1), K_STEEL, steel)
		beam(st, land, land - xf.basis * Vector3(0.0, y1, 0.0), 0.12, 0.12, K_STEEL, steel)
	box(st, xf * Transform3D(Basis(), Vector3(gx - run * 0.5, H + 0.7, z0 + sz * 0.4)), Vector3(run + 2.0, 0.05, 0.05), K_STEEL, steel)


# --- Water tower ----------------------------------------------------------------------------------

## The studio's water tower: a riveted steel tank on six legs with sway rods, a conical roof and a
## catwalk, the studio's mark and name painted round it. Foot at xf's origin.
static func water_tower(st: SurfaceTool, xf: Transform3D) -> void:
	var paint := Color(0.86, 0.85, 0.82)
	var leg_h := 24.0
	var r := 5.4
	var foot_r := 5.6
	var head_r := 4.4
	for k in 6:
		var a := TAU * float(k) / 6.0
		var foot := Vector3(cos(a), 0.0, sin(a)) * foot_r
		var head := Vector3(cos(a), 0.0, sin(a)) * head_r + Vector3(0.0, leg_h, 0.0)
		beam(st, xf * foot, xf * head, 0.42, 0.42, K_STEEL, paint * 0.92)
		cyl(st, xf * Transform3D(Basis(), foot), 0.6, 0.5, K_CONCRETE, Color(0.7, 0.69, 0.66), 8, true)
	for lvl in 4:
		var y := leg_h * (0.2 + 0.2 * lvl)
		var sp := lerpf(foot_r, head_r, y / leg_h)
		var y2 := leg_h * (0.2 + 0.2 * (lvl + 1))
		var sp2 := lerpf(foot_r, head_r, minf(y2, leg_h) / leg_h)
		for k in 6:
			var a0 := TAU * float(k) / 6.0
			var a1 := TAU * float(k + 1) / 6.0
			var p0 := Vector3(cos(a0), 0.0, sin(a0)) * sp + Vector3(0.0, y, 0.0)
			var p1 := Vector3(cos(a1), 0.0, sin(a1)) * sp + Vector3(0.0, y, 0.0)
			beam(st, xf * p0, xf * p1, 0.16, 0.2, K_STEEL, paint * 0.9)
			if lvl < 3:
				var q0 := Vector3(cos(a0), 0.0, sin(a0)) * sp2 + Vector3(0.0, y2, 0.0)
				var q1 := Vector3(cos(a1), 0.0, sin(a1)) * sp2 + Vector3(0.0, y2, 0.0)
				beam(st, xf * p0, xf * q1, 0.05, 0.05, K_STEEL, paint * 0.7)
				beam(st, xf * p1, xf * q0, 0.05, 0.05, K_STEEL, paint * 0.7)
	cyl(st, xf * Transform3D(Basis(), Vector3.ZERO), 0.55, leg_h, K_STEEL, paint * 0.9, 10, false)
	# The tank: a shallow cone bottom, the drum, the roof cone and its finial.
	cone(st, xf * Transform3D(Basis(Vector3.RIGHT, PI), Vector3(0.0, leg_h + 1.4, 0.0)), r, 1.4, K_CHROME, paint * 0.95, 28)
	var drum_h := 7.0
	cyl(st, xf * Transform3D(Basis(), Vector3(0.0, leg_h + 1.4, 0.0)), r, drum_h, K_STUCCO, paint, 32, false)
	cone(st, xf * Transform3D(Basis(), Vector3(0.0, leg_h + 1.4 + drum_h, 0.0)), r + 0.25, 2.6, K_ROOF, Color.WHITE, 28)
	cyl(st, xf * Transform3D(Basis(), Vector3(0.0, leg_h + 4.0 + drum_h, 0.0)), 0.18, 1.4, K_STEEL, paint, 8, true)
	cyl(st, xf * Transform3D(Basis(), Vector3(0.0, leg_h + 5.4 + drum_h, 0.0)), 0.32, 0.3, K_LAMP, Color(1.0, 0.1, 0.06), 8, true)
	# The catwalk with its rail and posts, a ladder up a leg.
	cyl(st, xf * Transform3D(Basis(), Vector3(0.0, leg_h + 1.3, 0.0)), r + 1.0, 0.1, K_STEEL, Color(0.3, 0.3, 0.3), 28, true)
	cyl(st, xf * Transform3D(Basis(), Vector3(0.0, leg_h + 2.35, 0.0)), r + 0.98, 0.06, K_STEEL, Color(0.3, 0.3, 0.3), 28, false)
	for k in 14:
		var a := TAU * float(k) / 14.0
		var p := Vector3(cos(a), 0.0, sin(a)) * (r + 0.95)
		box(st, xf * Transform3D(Basis(), p + Vector3(0.0, leg_h + 1.85, 0.0)), Vector3(0.05, 1.05, 0.05), K_STEEL, Color(0.3, 0.3, 0.3))
	var la := Vector3(foot_r + 0.5, 0.0, 0.0)
	var lb := Vector3(head_r + 1.0, leg_h + 1.3, 0.0)
	for s2: float in [-0.25, 0.25]:
		beam(st, xf * (la + Vector3(0.0, 0.0, s2)), xf * (lb + Vector3(0.0, 0.0, s2)), 0.05, 0.05, K_STEEL, Color(0.3, 0.3, 0.3))
	# The mark and the name round the drum, on two sides.
	var ink := Color(0.16, 0.2, 0.33)
	for side in 2:
		var turn := Transform3D(Basis(Vector3.UP, PI * float(side)), Vector3(0.0, leg_h + 1.4, 0.0))
		flat2d(st, _shift(emblem(1.8), Vector2(0.0, 3.6)), xf * turn, K_SIGN, ink, r + 0.03)
		var t := text2d(SHORT_NAME, 1.15)
		flat2d(st, _shift(t[0], Vector2(0.0, 2.4)), xf * turn, K_SIGN, ink, r + 0.03)
		var t2 := text2d("PICTURES", 0.6)
		flat2d(st, _shift(t2[0], Vector2(0.0, 1.35)), xf * turn, K_SIGN, ink, r + 0.03)


static func _shift(pts: PackedVector2Array, by: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(pts.size())
	for i in pts.size():
		out[i] = pts[i] + by
	return out


# --- The gate --------------------------------------------------------------------------------------

## The main gate, its centre on the wall line at xf's origin, the street toward +z: two pylons and
## the arch with the studio's name and mark, a guard booth on the island between the lanes, the
## barrier arms, the iron gates folded back. `w` the opening.
static func gate(st: SurfaceTool, xf: Transform3D, w: float) -> void:
	var paint := Color(0.9, 0.85, 0.74)
	var hw := w * 0.5
	for s: float in [-1.0, 1.0]:
		var px := s * (hw + 1.4)
		box(st, xf * Transform3D(Basis(), Vector3(px, 0.3, 0.0)), Vector3(3.2, 0.6, 3.2), K_STONE, Color(0.72, 0.66, 0.56))
		box(st, xf * Transform3D(Basis(), Vector3(px, 5.0, 0.0)), Vector3(2.8, 9.4, 2.8), K_STUCCO, paint)
		box(st, xf * Transform3D(Basis(), Vector3(px, 9.9, 0.0)), Vector3(3.3, 0.5, 3.3), K_STUCCO, paint * 0.95)
		box(st, xf * Transform3D(Basis(), Vector3(px, 10.5, 0.0)), Vector3(2.4, 0.7, 2.4), K_STUCCO, paint)
		# A lantern on each pylon's street face.
		box(st, xf * Transform3D(Basis(), Vector3(px, 4.2, 1.55)), Vector3(0.45, 0.8, 0.45), K_LAMP, Color(1.0, 0.85, 0.6))
		box(st, xf * Transform3D(Basis(), Vector3(px, 3.7, 1.5)), Vector3(0.12, 0.3, 0.3), K_STEEL, TRIM)
	# The arch: a band whose underside curves from the pylons up to the middle, its top level.
	var segs := 14
	var y_top := 9.6
	var y_spring := 7.0
	var crown := 8.3
	var depth := 1.8
	for i in segs:
		var t0 := float(i) / float(segs)
		var t1 := float(i + 1) / float(segs)
		var x0 := lerpf(-hw, hw, t0)
		var x1 := lerpf(-hw, hw, t1)
		var u0 := y_spring + (crown - y_spring) * sin(PI * t0)
		var u1 := y_spring + (crown - y_spring) * sin(PI * t1)
		for sz: float in [1.0, -1.0]:
			var zf := sz * depth * 0.5
			quad(st, xf * Vector3(x0, u0, zf), xf * Vector3(x1, u1, zf), xf * Vector3(x1, y_top, zf), xf * Vector3(x0, y_top, zf),
				xf.basis * Vector3(0.0, 0.0, sz), K_STUCCO, paint, [Vector2(x0, u0), Vector2(x1, u1), Vector2(x1, y_top), Vector2(x0, y_top)], y_top)
		var n := Vector3(-(u1 - u0), x1 - x0, 0.0).normalized() * -1.0
		quad(st, xf * Vector3(x0, u0, -depth * 0.5), xf * Vector3(x1, u1, -depth * 0.5), xf * Vector3(x1, u1, depth * 0.5), xf * Vector3(x0, u0, depth * 0.5),
			xf.basis * n, K_STUCCO, paint * 0.9, [Vector2(x0, 0.0), Vector2(x1, 0.0), Vector2(x1, depth), Vector2(x0, depth)], 1.0)
	box(st, xf * Transform3D(Basis(), Vector3(0.0, y_top + 0.18, 0.0)), Vector3(w + 0.4, 0.36, depth + 0.3), K_STUCCO, paint * 0.95)
	# The name across both faces of the arch in gilt letters; the mark rising over the middle.
	for sz: float in [1.0, -1.0]:
		var face := Transform3D(Basis(Vector3(sz, 0.0, 0.0), Vector3.UP, Vector3(0.0, 0.0, sz)), Vector3(0.0, (crown + y_top) * 0.5 + 0.05, sz * (depth * 0.5 + 0.03)))
		var t := text2d(STUDIO_NAME, 0.62)
		var scale := minf(1.0, (w - 1.0) / maxf(float(t[1]), 0.1))
		var pts: PackedVector2Array = t[0]
		if scale < 1.0:
			for i in pts.size():
				pts[i] *= scale
		flat2d(st, pts, xf * face, K_GILT, GILT)
		var eface := Transform3D(Basis(Vector3(sz, 0.0, 0.0), Vector3.UP, Vector3(0.0, 0.0, sz)), Vector3(0.0, y_top + 0.36, sz * 0.12))
		flat2d(st, emblem(1.7), xf * eface, K_GILT, GILT)
	# A plate behind the mark so it reads as one piece from the side.
	box(st, xf * Transform3D(Basis(), Vector3(0.0, y_top + 0.36 + 0.9, 0.0)), Vector3(0.6, 1.8, 0.2), K_STEEL, GILT * 0.8)
	# The island and the guard booth; a barrier arm each lane.
	box(st, xf * Transform3D(Basis(), Vector3(0.0, 0.09, 1.0)), Vector3(2.4, 0.18, 9.0), K_CONCRETE, Color(0.74, 0.73, 0.7))
	booth(st, xf * Transform3D(Basis(), Vector3(0.0, 0.18, 0.6)))
	for s: float in [-1.0, 1.0]:
		var bx := s * 1.3
		box(st, xf * Transform3D(Basis(), Vector3(bx, 0.7, 4.6)), Vector3(0.36, 1.2, 0.36), K_STEEL, Color(0.86, 0.75, 0.2))
		var arm_l := hw - 1.6
		box(st, xf * Transform3D(Basis(), Vector3(bx + s * arm_l * 0.5, 1.15, 4.6)), Vector3(arm_l, 0.11, 0.08), K_CANVAS, Color(0.82, 0.1, 0.08), 0.4)
	# The iron gates, folded back inside the wall.
	for s: float in [-1.0, 1.0]:
		var gx := s * (hw - 0.2)
		var leaf := hw - 1.3
		for k in int(leaf / 0.18):
			box(st, xf * Transform3D(Basis(), Vector3(gx, 1.35, -0.5 - 0.18 * float(k))), Vector3(0.035, 2.7, 0.035), K_STEEL, Color(0.08, 0.08, 0.09))
		for y: float in [0.25, 1.4, 2.6]:
			box(st, xf * Transform3D(Basis(), Vector3(gx, y, -0.5 - leaf * 0.5)), Vector3(0.06, 0.06, leaf), K_STEEL, Color(0.08, 0.08, 0.09))


## A guard booth (2.2 x 3.0, glass all round over a stucco base, a flat roof with an overhang),
## its foot at xf's origin, the window to the incoming lane on +x.
static func booth(st: SurfaceTool, xf: Transform3D) -> void:
	box(st, xf * Transform3D(Basis(), Vector3(0.0, 0.5, 0.0)), Vector3(2.0, 1.0, 2.8), K_STUCCO, Color(0.9, 0.85, 0.74))
	box(st, xf * Transform3D(Basis(), Vector3(0.0, 1.75, 0.0)), Vector3(1.9, 1.5, 2.7), K_GLASS, Color(0.3, 0.36, 0.38), 0.9)
	for c: Vector2 in [Vector2(-0.95, -1.35), Vector2(0.95, -1.35), Vector2(-0.95, 1.35), Vector2(0.95, 1.35)]:
		box(st, xf * Transform3D(Basis(), Vector3(c.x, 1.75, c.y)), Vector3(0.1, 1.5, 0.1), K_STEEL, TRIM)
	box(st, xf * Transform3D(Basis(), Vector3(0.0, 2.65, 0.0)), Vector3(2.0, 0.3, 2.8), K_STUCCO, Color(0.9, 0.85, 0.74))
	box(st, xf * Transform3D(Basis(), Vector3(0.0, 2.88, 0.0)), Vector3(3.0, 0.16, 3.8), K_FELT, Color(0.3, 0.29, 0.28))
	box(st, xf * Transform3D(Basis(), Vector3(0.0, 2.74, 0.0)), Vector3(0.5, 0.06, 0.5), K_LAMP, Color(1.0, 0.92, 0.78))


# --- The wall ----------------------------------------------------------------------------------------

## A run of the perimeter wall from `a` to `b` (world XZ, foot height `y`): stucco 3.4 m high with a
## coping, pilasters every PIER metres (on the run's own phase `phase`, so runs split across chunks
## line up), the inside face toward `inside`.
const WALL_H := 3.4
const WALL_T := 0.35
const PIER := 8.0


static func wall(st: SurfaceTool, a: Vector2, b: Vector2, y: float, phase: float) -> void:
	var l := a.distance_to(b)
	if l < 0.05:
		return
	var d := (b - a) / l
	var basis := Basis(Vector3(d.x, 0.0, d.y), Vector3.UP, Vector3(-d.y, 0.0, d.x))
	var m := (a + b) * 0.5
	var paint := Color(0.88, 0.83, 0.72)
	box(st, Transform3D(basis, Vector3(m.x, y + WALL_H * 0.5, m.y)), Vector3(l, WALL_H, WALL_T), K_STUCCO, paint)
	box(st, Transform3D(basis, Vector3(m.x, y + WALL_H + 0.08, m.y)), Vector3(l, 0.16, WALL_T + 0.16), K_CONCRETE, Color(0.78, 0.74, 0.66))
	var k0 := int(ceil(phase / PIER))
	var t := float(k0) * PIER - phase
	while t <= l + 0.001:
		var p := a + d * t
		box(st, Transform3D(basis, Vector3(p.x, y + (WALL_H + 0.35) * 0.5, p.y)), Vector3(0.6, WALL_H + 0.35, WALL_T + 0.3), K_STUCCO, paint * 0.96)
		box(st, Transform3D(basis, Vector3(p.x, y + WALL_H + 0.42, p.y)), Vector3(0.75, 0.14, WALL_T + 0.45), K_CONCRETE, Color(0.78, 0.74, 0.66))
		t += PIER


# --- The office block ------------------------------------------------------------------------------

## The studio's office block, its front toward +z, foot centre at xf's origin: `size` x storeys.
## A stucco frame - corner piers, a pier on every bay line, a spandrel band at every floor -
## standing in front of glass set back in it. The glass goes into `gst`, which wears
## curtain_glass (glass_material()): mullions, the sky mirrored, and the offices behind it traced
## in parallax (floors, light panels, the back wall), dim by day and lit after dark. A canopy over
## the entrance and the name over it.
static func offices(st: SurfaceTool, gst: SurfaceTool, xf: Transform3D, size: Vector3, storeys: int) -> void:
	var paint := Color(0.92, 0.88, 0.8)
	var W := size.x
	var D := size.z
	var H := size.y
	var fh := H / float(storeys)
	var inset := 0.45
	# The core: what is behind the glass and the roof.
	box(st, xf * Transform3D(Basis(), Vector3(0.0, H * 0.5, 0.0)), Vector3(W - inset * 2.0 - 0.1, H, D - inset * 2.0 - 0.1), K_STUCCO, paint * 0.9)
	box(st, xf * Transform3D(Basis(), Vector3(0.0, H + 0.45, 0.0)), Vector3(W + 0.3, 0.9, D + 0.3), K_STUCCO, paint * 0.95)
	for f in 4:
		var turn := Basis(Vector3.UP, PI * 0.5 * float(f))
		var face_w := W if f % 2 == 0 else D
		var face_d := D if f % 2 == 0 else W
		var bays := maxi(2, int(face_w / 3.6))
		var bw := face_w / float(bays)
		# The glass, set back `inset` in the frame, its UV metres along the face and world height.
		var gz := face_d * 0.5 - inset
		var gy0 := 0.55
		var gy1 := H - 0.15
		var a := xf * (turn * Vector3(-face_w * 0.5 + 0.3, gy0, gz))
		var b := xf * (turn * Vector3(face_w * 0.5 - 0.3, gy0, gz))
		var c := xf * (turn * Vector3(face_w * 0.5 - 0.3, gy1, gz))
		var d := xf * (turn * Vector3(-face_w * 0.5 + 0.3, gy1, gz))
		var n := xf.basis * (turn * Vector3(0.0, 0.0, 1.0))
		var u0 := 0.3
		var u1 := face_w - 0.3
		quad(gst, a, b, c, d, n, K_GLASS, Color.WHITE, [Vector2(u0, a.y), Vector2(u1, b.y), Vector2(u1, c.y), Vector2(u0, d.y)], H)
		# The frame: the base, a spandrel at every floor, the piers, the corners.
		var fz := face_d * 0.5 - 0.2
		box(st, xf * Transform3D(turn, turn * Vector3(0.0, 0.3, fz)), Vector3(face_w, 0.6, 0.4), K_STUCCO, paint * 0.94)
		for k in range(1, storeys + 1):
			var sy := fh * float(k)
			var hgt := 1.1 if k < storeys else 1.4
			box(st, xf * Transform3D(turn, turn * Vector3(0.0, sy - hgt * 0.5 + (0.0 if k < storeys else 0.15), fz + 0.02)), Vector3(face_w, hgt, 0.44), K_STUCCO, paint)
		for k in range(0, bays + 1):
			var px := -face_w * 0.5 + bw * float(k)
			var pw := 0.9 if k == 0 or k == bays else 0.42
			box(st, xf * Transform3D(turn, turn * Vector3(clampf(px, -face_w * 0.5 + pw * 0.5, face_w * 0.5 - pw * 0.5), H * 0.5, fz + 0.04)), Vector3(pw, H, 0.48), K_STUCCO, paint * 0.98)
	# The entrance: a canopy on posts and the name in gilt over it.
	box(st, xf * Transform3D(Basis(), Vector3(0.0, 3.4, D * 0.5 + 1.6)), Vector3(minf(13.0, W * 0.6), 0.3, 3.2), K_STUCCO, paint * 0.94)
	for s2: float in [-1.0, 1.0]:
		box(st, xf * Transform3D(Basis(), Vector3(s2 * minf(6.0, W * 0.28), 1.7, D * 0.5 + 2.9)), Vector3(0.25, 3.4, 0.25), K_STEEL, TRIM)
	box(st, xf * Transform3D(Basis(), Vector3(0.0, 3.2, D * 0.5 + 1.6)), Vector3(1.2, 0.06, 0.6), K_LAMP, Color(1.0, 0.9, 0.72))
	var face := Transform3D(Basis(), Vector3(0.0, fh + 0.2, D * 0.5 + 0.07))
	var t := text2d(STUDIO_NAME, 0.62)
	var scale := minf(1.0, (W - 2.0) / maxf(float(t[1]), 0.1))
	var pts: PackedVector2Array = t[0]
	for i2 in pts.size():
		pts[i2] *= scale
	flat2d(st, pts, xf * face, K_GILT, GILT)
	# Roof plant.
	box(st, xf * Transform3D(Basis(), Vector3(W * 0.2, H + 1.4, 0.0)), Vector3(3.0, 1.8, 2.4), K_STEEL, Color(0.72, 0.73, 0.72))
	box(st, xf * Transform3D(Basis(), Vector3(-W * 0.25, H + 1.6, -D * 0.15)), Vector3(4.0, 2.2, 3.0), K_STUCCO, paint * 0.9)


## The office glass (curtain_glass: traced offices behind mullions, lit after dark).
static func glass_material() -> ShaderMaterial:
	return LandmarkMats.glass("studio_offices", {"glass_tint": Color(0.2, 0.26, 0.28), "frame_color": Color(0.3, 0.3, 0.3),
		"grid": Vector2(1.2, 4.5), "storey": 4.5, "floor_y": 0.25, "room_depth": 7.0, "interior_day": 0.12, "interior_night": 1.3})


# --- The backlot's false fronts --------------------------------------------------------------------

## Facade styles on the New York street.
enum Facade { BROWNSTONE, TENEMENT, STOREFRONT, LIMESTONE, CORNER_BAR }

const SHOP_SIGNS := ["DELICATESSEN", "HARDWARE", "LAUNDRY", "PAWN", "BAKERY", "TAILOR", "DRUGS", "LUNCHEONETTE", "BOOKS", "SHOE REPAIR", "GROCERY", "BAR & GRILL"]


## One false front, `w` wide and `h` high, its foot at xf's origin and its face toward +z (the
## street), running along +x. Real windows (glass set behind the openings), cornice, stoop or
## shopfront, fire escapes; the back is plywood braced by raked struts down to sandbags.
static func facade(st: SurfaceTool, xf: Transform3D, w: float, h: float, style: int, seed: int) -> void:
	var T := 0.3
	var kind := K_BRICK
	var paint := Color(0.78, 0.5, 0.42)
	match style:
		Facade.BROWNSTONE:
			kind = K_STONE
			paint = Color(0.55, 0.38, 0.3)
		Facade.LIMESTONE:
			kind = K_STONE
			paint = Color(0.82, 0.78, 0.68)
		Facade.TENEMENT:
			paint = [Color(0.74, 0.44, 0.36), Color(0.62, 0.42, 0.36), Color(0.8, 0.62, 0.48)][seed % 3]
		Facade.CORNER_BAR:
			paint = Color(0.5, 0.32, 0.28)
		_:
			paint = [Color(0.78, 0.5, 0.42), Color(0.86, 0.74, 0.6), Color(0.6, 0.4, 0.34)][seed % 3]
	var shop := style == Facade.STOREFRONT or style == Facade.CORNER_BAR
	var g := 4.4 if shop else (1.6 if style == Facade.BROWNSTONE else 0.9)
	var fh := 3.3
	var floors := maxi(1, int((h - g - 1.2) / fh))
	var top := g + float(floors) * fh + 0.6
	var bays := maxi(2, int(w / 2.3))
	var bw := w / float(bays)
	var ww := minf(1.15, bw * 0.55)
	var wh := 1.9
	var trim := Color(0.86, 0.84, 0.78) if kind == K_BRICK else paint * 1.12
	# Ground storey: a stone base, or a shopfront.
	if shop:
		box(st, xf * Transform3D(Basis(), Vector3(w * 0.5, 0.35, T * 0.5)), Vector3(w, 0.7, T), K_STONE, Color(0.36, 0.34, 0.33), 0.0, 32 | 8)
		box(st, xf * Transform3D(Basis(), Vector3(w * 0.5, (0.7 + 3.2) * 0.5, -0.1)), Vector3(w - 1.0, 2.5, 0.06), K_GLASS, Color(0.32, 0.36, 0.36), 1.6)
		for k in 2:
			box(st, xf * Transform3D(Basis(), Vector3(0.25 + float(k) * (w - 0.5), g * 0.5, T * 0.5)), Vector3(0.5, g, T), kind, paint, 0.0, 32 | 8)
		box(st, xf * Transform3D(Basis(), Vector3(w * 0.5, (3.2 + g) * 0.5, T * 0.5)), Vector3(w, g - 3.2, T), K_STEEL, Color(0.14, 0.2, 0.16) if seed % 2 == 0 else Color(0.25, 0.12, 0.1), 0.0, 32 | 8)
		var sign: String = SHOP_SIGNS[seed % SHOP_SIGNS.size()]
		var tf := Transform3D(Basis(), Vector3(w * 0.5, (3.2 + g) * 0.5, T + 0.02))
		var t := text2d(sign, 0.55)
		var pts: PackedVector2Array = t[0]
		var sc := minf(1.0, (w - 1.2) / maxf(float(t[1]), 0.1))
		for i in pts.size():
			pts[i] *= sc
		flat2d(st, pts, xf * tf, K_SIGN, Color(0.92, 0.84, 0.6))
		# The awning, sloping out over the pavement.
		var aw := w - 0.8
		var ab := Basis(Vector3.RIGHT, -0.38)
		box(st, xf * Transform3D(ab, Vector3(w * 0.5, 3.15, T + 0.75)), Vector3(aw, 0.05, 1.7), K_CANVAS, [Color(0.15, 0.32, 0.2), Color(0.6, 0.12, 0.1), Color(0.18, 0.2, 0.36)][seed % 3], 0.3 if seed % 3 == 0 else 0.0)
		box(st, xf * Transform3D(Basis(), Vector3(w * 0.5, 2.75, T + 1.53)), Vector3(aw, 0.32, 0.03), K_CANVAS, [Color(0.15, 0.32, 0.2), Color(0.6, 0.12, 0.1), Color(0.18, 0.2, 0.36)][seed % 3])
		box(st, xf * Transform3D(Basis(), Vector3(w * 0.5, 1.2, -0.05)), Vector3(1.0, 2.3, 0.08), K_STEEL, Color(0.12, 0.12, 0.12))
	else:
		box(st, xf * Transform3D(Basis(), Vector3(w * 0.5, g * 0.5, T * 0.5)), Vector3(w, g, T), K_STONE, paint * 0.92 if kind == K_STONE else Color(0.66, 0.64, 0.58), 0.0, 32 | 8)
	# The upper storeys: sill strips, piers between the windows, the head strip.
	for f in floors:
		var y0 := g + fh * float(f)
		var sill := 0.9
		box(st, xf * Transform3D(Basis(), Vector3(w * 0.5, y0 + sill * 0.5, T * 0.5)), Vector3(w, sill, T), kind, paint, 0.0, 32 | 8)
		var head := fh - sill - wh
		box(st, xf * Transform3D(Basis(), Vector3(w * 0.5, y0 + sill + wh + head * 0.5, T * 0.5)), Vector3(w, head, T), kind, paint, 0.0, 32 | 8)
		for k in bays + 1:
			var x0 := 0.0 if k == 0 else bw * (float(k) - 0.5) + ww * 0.5
			var x1 := w if k == bays else bw * (float(k) + 0.5) - ww * 0.5
			if x1 - x0 > 0.02:
				box(st, xf * Transform3D(Basis(), Vector3((x0 + x1) * 0.5, y0 + sill + wh * 0.5, T * 0.5)), Vector3(x1 - x0, wh, T), kind, paint, 0.0, 32 | 8)
		for k in bays:
			var cx := bw * (float(k) + 0.5)
			box(st, xf * Transform3D(Basis(), Vector3(cx, y0 + sill + wh * 0.5, 0.08)), Vector3(ww, wh, 0.04), K_GLASS, Color(0.28, 0.3, 0.3), ww * 0.5)
			box(st, xf * Transform3D(Basis(), Vector3(cx, y0 + sill - 0.05, T + 0.05)), Vector3(ww + 0.24, 0.1, 0.12), K_STONE, trim)
			box(st, xf * Transform3D(Basis(), Vector3(cx, y0 + sill + wh + 0.14, T + 0.04)), Vector3(ww + 0.3, 0.28, 0.1), K_STONE, trim)
	# The parapet and the cornice.
	box(st, xf * Transform3D(Basis(), Vector3(w * 0.5, (g + fh * float(floors) + top) * 0.5, T * 0.5)), Vector3(w, top - g - fh * float(floors), T), kind, paint, 0.0, 32 | 8)
	box(st, xf * Transform3D(Basis(), Vector3(w * 0.5, top - 0.3, T + 0.3)), Vector3(w + 0.1, 0.55, 0.65), K_STEEL if style == Facade.TENEMENT else K_STONE, Color(0.42, 0.36, 0.3) if style == Facade.TENEMENT else trim)
	box(st, xf * Transform3D(Basis(), Vector3(w * 0.5, top - 0.7, T + 0.12)), Vector3(w, 0.18, 0.28), K_STONE, trim * 0.92)
	# A stoop to a raised door (brownstones), else a plain door in the base.
	if style == Facade.BROWNSTONE:
		var dx := bw * 0.5 if seed % 2 == 0 else w - bw * 0.5
		for s in 6:
			var sy := 0.27 * float(s + 1)
			box(st, xf * Transform3D(Basis(), Vector3(dx, sy * 0.5, T + 2.4 - 0.32 * float(s))), Vector3(1.8, sy, 0.32), K_STONE, paint * 0.9)
		box(st, xf * Transform3D(Basis(), Vector3(dx, g + 1.3, 0.1)), Vector3(1.2, 2.6, 0.08), K_STEEL, Color(0.24, 0.14, 0.1))
		for s2: float in [-1.0, 1.0]:
			beam(st, xf * Vector3(dx + s2 * 0.95, 1.0, T + 2.5), xf * Vector3(dx + s2 * 0.95, g + 0.95, T + 0.2), 0.04, 0.04, K_STEEL, Color(0.06, 0.06, 0.06))
	elif not shop:
		box(st, xf * Transform3D(Basis(), Vector3(w * 0.5, 1.25, 0.1)), Vector3(1.2, 2.5, 0.08), K_STEEL, Color(0.2, 0.16, 0.12))
	# Fire escapes on the tenements: a landing a storey, the ladders between, the drop ladder.
	if style == Facade.TENEMENT and floors >= 2:
		var fw := minf(w - 1.0, bw * 2.0 + 0.6)
		var fx := w * 0.5
		var iron := Color(0.07, 0.07, 0.08)
		for f in floors:
			var y := g + fh * float(f) + 0.85
			box(st, xf * Transform3D(Basis(), Vector3(fx, y, T + 0.6)), Vector3(fw, 0.06, 1.1), K_STEEL, iron)
			box(st, xf * Transform3D(Basis(), Vector3(fx, y + 0.95, T + 1.12)), Vector3(fw, 0.05, 0.05), K_STEEL, iron)
			box(st, xf * Transform3D(Basis(), Vector3(fx, y + 0.45, T + 1.12)), Vector3(fw, 0.03, 0.03), K_STEEL, iron)
			for s2: float in [-1.0, 1.0]:
				box(st, xf * Transform3D(Basis(), Vector3(fx + s2 * fw * 0.5, y + 0.48, T + 0.6)), Vector3(0.04, 0.95, 1.1), K_STEEL, iron)
			if f > 0:
				beam(st, xf * Vector3(fx - fw * 0.3, y - fh, T + 0.85), xf * Vector3(fx + fw * 0.1, y, T + 0.85), 0.5, 0.05, K_STEEL, iron, xf.basis.z)
		beam(st, xf * Vector3(fx - fw * 0.3, g + 0.85, T + 0.85), xf * Vector3(fx - fw * 0.3, 2.4, T + 0.85), 0.45, 0.04, K_STEEL, iron, xf.basis.z)
	# The back: one plywood skin and the bracing.
	box(st, xf * Transform3D(Basis(), Vector3(w * 0.5, top * 0.5, -0.02)), Vector3(w, top, 0.04), K_WOOD, Color(0.82, 0.72, 0.56), 1.0, 32 | 4 | 16)
	var raw := Color(0.86, 0.74, 0.55)
	var n := maxi(2, int(w / 3.2) + 1)
	for k in n:
		var bx := 0.3 + (w - 0.6) * float(k) / float(n - 1)
		var hi := top * 0.62
		var reach := top * 0.5
		beam(st, xf * Vector3(bx, hi, -0.1), xf * Vector3(bx, 0.08, -reach), 0.09, 0.19, K_WOOD, raw)
		beam(st, xf * Vector3(bx, top - 0.4, -0.1), xf * Vector3(bx, 0.08, -0.1), 0.09, 0.19, K_WOOD, raw)
		box(st, xf * Transform3D(Basis(), Vector3(bx, 0.15, -reach - 0.2)), Vector3(0.55, 0.3, 0.9), K_CANVAS, Color(0.55, 0.5, 0.4))
	for y: float in [top * 0.25, top * 0.55, top * 0.85]:
		box(st, xf * Transform3D(Basis(), Vector3(w * 0.5, y, -0.15)), Vector3(w, 0.19, 0.05), K_WOOD, raw)


# --- Vehicles and kit -----------------------------------------------------------------------------

static func _wheel(st: SurfaceTool, xf: Transform3D, at: Vector3, r: float, w: float) -> void:
	cyl(st, xf * Transform3D(Basis(Vector3.FORWARD, PI * 0.5), at - Vector3(w * 0.5, 0.0, 0.0)), r, w, K_RUBBER, Color(0.07, 0.07, 0.07), 12, false)
	cyl(st, xf * Transform3D(Basis(Vector3.FORWARD, PI * 0.5), at + Vector3(w * 0.5, 0.0, 0.0)), r * 0.6, 0.01, K_CHROME, Color(0.7, 0.7, 0.72), 10, true)
	cyl(st, xf * Transform3D(Basis(Vector3.FORWARD, -PI * 0.5), at - Vector3(w * 0.5, 0.0, 0.0)), r * 0.6, 0.01, K_CHROME, Color(0.7, 0.7, 0.72), 10, true)


## A production trailer (a star or makeup trailer, or a honeywagon with a row of doors), `length`
## long, nose toward +z, foot centre at xf's origin.
static func trailer(st: SurfaceTool, xf: Transform3D, length: float, honey: bool, band: int) -> void:
	var w := 2.55
	var fl := 1.05
	var bh := 2.9
	box(st, xf * Transform3D(Basis(), Vector3(0.0, fl + bh * 0.5, 0.0)), Vector3(w, bh, length), K_TRAILER, Color(0.95, 0.95, 0.93), float(band))
	box(st, xf * Transform3D(Basis(), Vector3(0.0, fl - 0.15, 0.0)), Vector3(w - 0.3, 0.3, length - 0.4), K_STEEL, Color(0.12, 0.12, 0.13))
	box(st, xf * Transform3D(Basis(), Vector3(0.0, fl + bh + 0.35, -length * 0.15)), Vector3(1.0, 0.5, 1.4), K_STEEL, Color(0.86, 0.86, 0.85))
	box(st, xf * Transform3D(Basis(), Vector3(0.0, fl + bh + 0.3, length * 0.25)), Vector3(0.9, 0.4, 1.2), K_STEEL, Color(0.86, 0.86, 0.85))
	# The doors and steps on the curb side (+x), windows along both sides.
	var doors := 4 if honey else 2
	for k in doors:
		var dz := -length * 0.5 + length * (float(k) + 0.5) / float(doors)
		box(st, xf * Transform3D(Basis(), Vector3(w * 0.5 + 0.02, fl + 1.0, dz)), Vector3(0.05, 2.0, 0.8), K_STEEL, Color(0.82, 0.82, 0.8))
		box(st, xf * Transform3D(Basis(), Vector3(w * 0.5 + 0.03, fl + 1.5, dz + 0.22)), Vector3(0.04, 0.6, 0.3), K_GLASS, Color(0.2, 0.22, 0.24), 0.3)
		for s in 3:
			box(st, xf * Transform3D(Basis(), Vector3(w * 0.5 + 0.35 + 0.28 * float(s), fl - 0.3 * float(s + 1) + 0.1, dz)), Vector3(0.3, 0.06, 0.8), K_STEEL, Color(0.3, 0.3, 0.3))
		box(st, xf * Transform3D(Basis(), Vector3(w * 0.5 + 0.06, fl + 2.25, dz)), Vector3(0.12, 0.08, 0.2), K_LAMP, Color(1.0, 0.9, 0.7))
	for s2: float in [-1.0, 1.0]:
		var nwin := int(length / 3.0)
		for k in nwin:
			var wz := -length * 0.5 + length * (float(k) + 0.5) / float(nwin)
			var skip := false
			if s2 > 0.0:
				for kd in doors:
					var dz := -length * 0.5 + length * (float(kd) + 0.5) / float(doors)
					if absf(dz - wz) < 1.0:
						skip = true
			if not skip:
				box(st, xf * Transform3D(Basis(), Vector3(s2 * (w * 0.5 + 0.02), fl + 1.9, wz)), Vector3(0.04, 0.7, 1.1), K_GLASS, Color(0.15, 0.17, 0.18), 0.55)
	# Axles, the hitch, the jacks.
	for az: float in [-length * 0.2, -length * 0.2 - 1.25]:
		for s2: float in [-1.0, 1.0]:
			_wheel(st, xf, Vector3(s2 * 1.0, 0.42, az), 0.42, 0.28)
	beam(st, xf * Vector3(0.0, 0.6, length * 0.5), xf * Vector3(0.0, 0.5, length * 0.5 + 1.5), 0.15, 0.15, K_STEEL, Color(0.12, 0.12, 0.12))
	box(st, xf * Transform3D(Basis(), Vector3(0.0, 0.3, length * 0.5 + 1.2)), Vector3(0.12, 0.6, 0.12), K_STEEL, Color(0.12, 0.12, 0.12))
	for s2: float in [-1.0, 1.0]:
		box(st, xf * Transform3D(Basis(), Vector3(s2 * 1.0, 0.45, length * 0.4)), Vector3(0.1, 0.9, 0.1), K_STEEL, Color(0.5, 0.5, 0.5))


## A five-ton grip or electric truck: cab-over, a box body with a roll-up door and a lift gate, nose
## toward +z.
static func truck(st: SurfaceTool, xf: Transform3D, band: int) -> void:
	var cab := Color(0.94, 0.94, 0.93)
	box(st, xf * Transform3D(Basis(), Vector3(0.0, 1.95, 3.6)), Vector3(2.3, 2.1, 1.9), K_STEEL, cab)
	box(st, xf * Transform3D(Basis(Vector3.RIGHT, -0.12), Vector3(0.0, 2.35, 4.53)), Vector3(2.1, 1.0, 0.06), K_GLASS, Color(0.15, 0.17, 0.19), 1.05)
	for s2: float in [-1.0, 1.0]:
		box(st, xf * Transform3D(Basis(), Vector3(s2 * 1.16, 2.4, 3.8)), Vector3(0.04, 0.8, 1.0), K_GLASS, Color(0.15, 0.17, 0.19), 1.0)
		box(st, xf * Transform3D(Basis(), Vector3(s2 * 1.35, 2.4, 4.3)), Vector3(0.08, 0.35, 0.2), K_CHROME, Color(0.2, 0.2, 0.2))
		box(st, xf * Transform3D(Basis(), Vector3(s2 * 0.85, 1.25, 4.56)), Vector3(0.3, 0.18, 0.06), K_LAMP, Color(1.0, 0.95, 0.85))
	box(st, xf * Transform3D(Basis(), Vector3(0.0, 0.75, 4.55)), Vector3(2.3, 0.35, 0.2), K_STEEL, Color(0.15, 0.15, 0.15))
	box(st, xf * Transform3D(Basis(), Vector3(0.0, 0.85, 0.0)), Vector3(1.0, 0.3, 9.0), K_STEEL, Color(0.1, 0.1, 0.1))
	box(st, xf * Transform3D(Basis(), Vector3(0.0, 2.75, -1.2)), Vector3(2.5, 3.2, 7.4), K_TRAILER, Color(0.95, 0.95, 0.93), float(band))
	box(st, xf * Transform3D(Basis(), Vector3(0.0, 2.6, -4.92)), Vector3(2.2, 2.9, 0.04), K_DOOR, Color(0.86, 0.86, 0.84), 1.1)
	box(st, xf * Transform3D(Basis(), Vector3(0.0, 1.0, -5.1)), Vector3(2.4, 0.12, 0.5), K_STEEL, Color(0.5, 0.5, 0.52))
	for s2: float in [-1.0, 1.0]:
		_wheel(st, xf, Vector3(s2 * 1.0, 0.5, 3.4), 0.5, 0.3)
		_wheel(st, xf, Vector3(s2 * 1.0, 0.5, -3.0), 0.5, 0.45)
		box(st, xf * Transform3D(Basis(), Vector3(s2 * 0.9, 1.15, -4.95)), Vector3(0.2, 0.15, 0.05), K_LAMP, Color(1.0, 0.1, 0.05))


## A golf cart (2.4 x 1.2), nose toward +z: a moulded body, a bench seat, a canopy on four posts, a
## windscreen, a utility bed on some.
static func golf_cart(st: SurfaceTool, xf: Transform3D, paint: Color, bed: bool) -> void:
	box(st, xf * Transform3D(Basis(), Vector3(0.0, 0.5, 0.15)), Vector3(1.2, 0.42, 2.3), K_CHROME, paint * 0.95)
	box(st, xf * Transform3D(Basis(), Vector3(0.0, 0.7, 0.95)), Vector3(1.18, 0.35, 0.6), K_CHROME, paint)
	box(st, xf * Transform3D(Basis(), Vector3(0.0, 0.84, -0.05)), Vector3(1.05, 0.14, 0.55), K_CANVAS, Color(0.3, 0.22, 0.16))
	box(st, xf * Transform3D(Basis(), Vector3(0.0, 1.1, -0.32)), Vector3(1.05, 0.5, 0.1), K_CANVAS, Color(0.3, 0.22, 0.16))
	for c: Vector2 in [Vector2(-0.52, 0.75), Vector2(0.52, 0.75), Vector2(-0.52, -0.45), Vector2(0.52, -0.45)]:
		box(st, xf * Transform3D(Basis(), Vector3(c.x, 1.45, c.y)), Vector3(0.04, 1.3, 0.04), K_STEEL, Color(0.15, 0.15, 0.16))
	box(st, xf * Transform3D(Basis(), Vector3(0.0, 2.12, 0.15)), Vector3(1.3, 0.06, 1.55), K_CHROME, paint)
	box(st, xf * Transform3D(Basis(Vector3.RIGHT, 0.1), Vector3(0.0, 1.55, 0.78)), Vector3(1.05, 0.9, 0.02), K_GLASS, Color(0.6, 0.65, 0.66), 2.0)
	box(st, xf * Transform3D(Basis(Vector3.RIGHT, -0.7), Vector3(-0.22, 1.05, 0.55)), Vector3(0.32, 0.03, 0.32), K_RUBBER, Color(0.08, 0.08, 0.08))
	if bed:
		box(st, xf * Transform3D(Basis(), Vector3(0.0, 0.95, -0.95)), Vector3(1.15, 0.3, 0.75), K_STEEL, Color(0.25, 0.25, 0.26))
	for c: Vector2 in [Vector2(-0.55, 0.85), Vector2(0.55, 0.85), Vector2(-0.55, -0.6), Vector2(0.55, -0.6)]:
		_wheel(st, xf, Vector3(c.x, 0.23, c.y), 0.23, 0.18)


## A cast-iron street lamp for the backlot's New York street: a fluted post on a base, a curved
## arm, a lantern. Foot at xf's origin, the arm toward +z.
static func ny_lamp(st: SurfaceTool, xf: Transform3D) -> void:
	var iron := Color(0.1, 0.16, 0.12)
	cyl(st, xf, 0.26, 0.9, K_STEEL, iron, 10, true)
	cyl(st, xf * Transform3D(Basis(), Vector3(0.0, 0.9, 0.0)), 0.11, 4.6, K_STEEL, iron, 10, false)
	cyl(st, xf * Transform3D(Basis(), Vector3(0.0, 5.5, 0.0)), 0.16, 0.2, K_STEEL, iron, 10, true)
	beam(st, xf * Vector3(0.0, 5.3, 0.0), xf * Vector3(0.0, 5.75, 0.8), 0.06, 0.06, K_STEEL, iron)
	beam(st, xf * Vector3(0.0, 5.75, 0.8), xf * Vector3(0.0, 5.65, 1.25), 0.06, 0.06, K_STEEL, iron)
	box(st, xf * Transform3D(Basis(), Vector3(0.0, 5.3, 1.25)), Vector3(0.36, 0.5, 0.36), K_LAMP, Color(1.0, 0.86, 0.6))
	cone(st, xf * Transform3D(Basis(), Vector3(0.0, 5.55, 1.25)), 0.32, 0.25, K_STEEL, iron, 8)


## Equipment by a stage door: wheeled carts (grip, electric), road cases, a light on a stand.
static func gear(st: SurfaceTool, xf: Transform3D, seed: int) -> void:
	var case_c := Color(0.12, 0.12, 0.13)
	for k in 3 + seed % 3:
		var o := Vector3(float(k) * 0.9 - 1.0, 0.0, float((seed / (k + 1)) % 3) * 0.2)
		var hh := 0.7 + 0.25 * float((seed + k) % 3)
		box(st, xf * Transform3D(Basis(), o + Vector3(0.0, hh * 0.5 + 0.1, 0.0)), Vector3(0.8, hh, 0.6), K_STEEL, case_c)
		box(st, xf * Transform3D(Basis(), o + Vector3(0.0, hh + 0.12, 0.0)), Vector3(0.82, 0.04, 0.62), K_CHROME, Color(0.6, 0.6, 0.62))
	# A cart of flags and stands.
	box(st, xf * Transform3D(Basis(), Vector3(2.4, 0.5, 0.0)), Vector3(0.9, 0.06, 1.8), K_STEEL, Color(0.3, 0.3, 0.3))
	for k in 5:
		box(st, xf * Transform3D(Basis(), Vector3(2.4 + (float(k) - 2.0) * 0.16, 1.4, 0.0)), Vector3(0.03, 1.8, 1.4), K_CANVAS, Color(0.06, 0.06, 0.06))
	# A light on a stand.
	var sx := Vector3(-2.2, 0.0, 0.3)
	for k in 3:
		var a := TAU * float(k) / 3.0
		beam(st, xf * (sx + Vector3(cos(a), 0.0, sin(a)) * 0.6), xf * (sx + Vector3(0.0, 1.0, 0.0)), 0.04, 0.04, K_STEEL, Color(0.6, 0.6, 0.62))
	box(st, xf * Transform3D(Basis(), sx + Vector3(0.0, 2.0, 0.0)), Vector3(0.05, 2.0, 0.05), K_STEEL, Color(0.6, 0.6, 0.62))
	box(st, xf * Transform3D(Basis(Vector3.RIGHT, 0.3), sx + Vector3(0.0, 3.1, 0.15)), Vector3(0.6, 0.55, 0.5), K_LAMP, Color(1.0, 0.92, 0.8))
