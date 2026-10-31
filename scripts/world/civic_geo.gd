class_name CivicGeo
extends RefCounted
## Geometry for the civic buildings (CivicKit), written in the SITE'S FRAME: u along the street,
## y up, v in from the site's street edge. A frame point maps to the building node's local space
## as x = sx * (u - L/2), z = -v (+Z toward the street), so a site on any side of its block is the
## same code. One SurfaceTool per material key; every triangle is turned to face the normal it is
## given (PoliceStation.Geo's rule), so mirroring by sx can never flip a face.
##
## Walls are cut round their openings (rectangular, or arched with a semicircular head) with real
## reveals, a sill and a head or an arch soffit, and the glass set back in the opening carries the
## pane's own UV (metres from its lower corner), its size in UV2 and a random in COLOR.a, which
## shaders/civic_glass.gdshader traces the room behind with.

var L := 0.0
var sx := 1.0
var _st: Dictionary = {}
## Keys whose vertices carry a colour (roof tiles: white; breeze block: the paint).
var colors: Dictionary = {}
## A random per pane (salted by the building's seed).
var seed_value := 0
var _pane := 0
var tris := 0


func _init(length: float, mirror: float, seed_v: int) -> void:
	L = length
	sx = mirror
	seed_value = seed_v


func P(u: float, y: float, v: float) -> Vector3:
	return Vector3(sx * (u - L * 0.5), y, -v)


## A frame direction (du, dy, dv) in local space.
func D(d: Vector3) -> Vector3:
	return Vector3(sx * d.x, d.y, -d.z)


func _tool(key: String) -> SurfaceTool:
	if not _st.has(key):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_st[key] = st
	return _st[key]


func has(key: String) -> bool:
	return _st.has(key)


# --- Triangles ------------------------------------------------------------------------------------

## A triangle of local points facing local normal `n`, UV by the face's plane in metres.
func tri_l(key: String, n: Vector3, a: Vector3, b: Vector3, c: Vector3) -> void:
	if (b - a).cross(c - a).dot(n) > 0.0:
		var t := b
		b = c
		c = t
	var st := _tool(key)
	var col: Variant = colors.get(key, null)
	for p: Vector3 in [a, b, c]:
		st.set_normal(n)
		if col != null:
			st.set_color(col)
		var uv := Vector2(p.x * absf(n.z) + p.z * absf(n.x), p.y) if absf(n.y) < 0.5 else Vector2(p.x, p.z)
		st.set_uv(uv)
		st.add_vertex(p)
	tris += 1


## A triangle with explicit UVs (frame points, frame normal).
func tri_uv(key: String, n: Vector3, a: Vector3, b: Vector3, c: Vector3, ua: Vector2, ub: Vector2, uc: Vector2) -> void:
	var la := P(a.x, a.y, a.z)
	var lb := P(b.x, b.y, b.z)
	var lc := P(c.x, c.y, c.z)
	var ln := D(n).normalized()
	if (lb - la).cross(lc - la).dot(ln) > 0.0:
		var t := lb
		lb = lc
		lc = t
		var tu := ub
		ub = uc
		uc = tu
	var st := _tool(key)
	var col: Color = colors.get(key, Color.WHITE)
	for k in 3:
		st.set_normal(ln)
		st.set_color(col)
		st.set_uv([ua, ub, uc][k])
		st.add_vertex([la, lb, lc][k])
	tris += 1


## A frame quad (a, b, c, d in order round it) facing frame normal `n`.
func quad(key: String, n: Vector3, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	var ln := D(n).normalized()
	var la := P(a.x, a.y, a.z)
	var lb := P(b.x, b.y, b.z)
	var lc := P(c.x, c.y, c.z)
	var ld := P(d.x, d.y, d.z)
	tri_l(key, ln, la, lb, lc)
	tri_l(key, ln, la, lc, ld)


## A box from frame extents.
func box(key: String, u0: float, u1: float, y0: float, y1: float, v0: float, v1: float) -> void:
	if u1 < u0:
		var t := u0
		u0 = u1
		u1 = t
	if v1 < v0:
		var t2 := v0
		v0 = v1
		v1 = t2
	var c := P((u0 + u1) * 0.5, (y0 + y1) * 0.5, (v0 + v1) * 0.5)
	obox(key, Transform3D(Basis.from_scale(Vector3(u1 - u0, y1 - y0, v1 - v0)), c))


## A unit cube through `xf` (local space).
func obox(key: String, xf: Transform3D) -> void:
	var nb := xf.basis.inverse().transposed()
	var faces := [
		[Vector3.RIGHT, Vector3(0.5, -0.5, -0.5), Vector3(0.5, 0.5, -0.5), Vector3(0.5, 0.5, 0.5), Vector3(0.5, -0.5, 0.5)],
		[Vector3.LEFT, Vector3(-0.5, -0.5, 0.5), Vector3(-0.5, 0.5, 0.5), Vector3(-0.5, 0.5, -0.5), Vector3(-0.5, -0.5, -0.5)],
		[Vector3.UP, Vector3(-0.5, 0.5, -0.5), Vector3(-0.5, 0.5, 0.5), Vector3(0.5, 0.5, 0.5), Vector3(0.5, 0.5, -0.5)],
		[Vector3.DOWN, Vector3(-0.5, -0.5, 0.5), Vector3(-0.5, -0.5, -0.5), Vector3(0.5, -0.5, -0.5), Vector3(0.5, -0.5, 0.5)],
		[Vector3.BACK, Vector3(0.5, -0.5, 0.5), Vector3(0.5, 0.5, 0.5), Vector3(-0.5, 0.5, 0.5), Vector3(-0.5, -0.5, 0.5)],
		[Vector3.FORWARD, Vector3(-0.5, -0.5, -0.5), Vector3(-0.5, 0.5, -0.5), Vector3(0.5, 0.5, -0.5), Vector3(0.5, -0.5, -0.5)],
	]
	for f: Array in faces:
		var n: Vector3 = (nb * (f[0] as Vector3)).normalized()
		var q := [xf * (f[1] as Vector3), xf * (f[2] as Vector3), xf * (f[3] as Vector3), xf * (f[4] as Vector3)]
		tri_l(key, n, q[0], q[1], q[2])
		tri_l(key, n, q[0], q[2], q[3])


## A square bar of side `w` between frame points.
func beam(key: String, a: Vector3, b: Vector3, w: float) -> void:
	var la := P(a.x, a.y, a.z)
	var lb := P(b.x, b.y, b.z)
	var d := lb - la
	var len := d.length()
	if len < 0.001:
		return
	var y := d / len
	var x := y.cross(Vector3.UP if absf(y.y) < 0.95 else Vector3.RIGHT).normalized()
	var z := x.cross(y).normalized()
	obox(key, Transform3D(Basis(x * w, y * len, z * w), (la + lb) * 0.5))


## An upright cylinder (frame base point), radius r, height h, `seg` sides, capped on top.
func cyl(key: String, base: Vector3, r: float, h: float, seg: int = 10, r_top: float = -1.0) -> void:
	var b := P(base.x, base.y, base.z)
	var rt := r if r_top < 0.0 else r_top
	for i in seg:
		var a0 := TAU * float(i) / float(seg)
		var a1 := TAU * float(i + 1) / float(seg)
		var d0 := Vector3(cos(a0), 0.0, sin(a0))
		var d1 := Vector3(cos(a1), 0.0, sin(a1))
		var n := Vector3(cos((a0 + a1) * 0.5), (r - rt) / maxf(h, 0.01), sin((a0 + a1) * 0.5)).normalized()
		var p0 := b + d0 * r
		var p1 := b + d1 * r
		var q0 := b + d0 * rt + Vector3(0.0, h, 0.0)
		var q1 := b + d1 * rt + Vector3(0.0, h, 0.0)
		tri_l(key, n, p0, p1, q1)
		tri_l(key, n, p0, q1, q0)
		tri_l(key, Vector3.UP, b + Vector3(0.0, h, 0.0), q0, q1)


## A horizontal cylinder along frame u from (u0, y, v) to (u1, y, v), radius r; `half` keeps only
## the upper half (a rounded top).
func hcyl(key: String, u0: float, u1: float, y: float, v: float, r: float, seg: int = 10, half: bool = false) -> void:
	var n_seg := seg
	var a_end := PI if half else TAU
	for i in n_seg:
		var a0 := a_end * float(i) / float(n_seg)
		var a1 := a_end * float(i + 1) / float(n_seg)
		# Angle measured from +v (toward the back) up over the top to -v.
		var o0 := Vector3(0.0, sin(a0), cos(a0)) * r
		var o1 := Vector3(0.0, sin(a1), cos(a1)) * r
		var n := Vector3(0.0, sin((a0 + a1) * 0.5), cos((a0 + a1) * 0.5))
		quad(key, n, Vector3(u0, y, v) + o0, Vector3(u1, y, v) + o0, Vector3(u1, y, v) + o1, Vector3(u0, y, v) + o1)
	# End caps (a fan).
	for e: Array in [[u0, Vector3(-1, 0, 0)], [u1, Vector3(1, 0, 0)]]:
		var eu: float = e[0]
		for i in n_seg:
			var a0 := a_end * float(i) / float(n_seg)
			var a1 := a_end * float(i + 1) / float(n_seg)
			var c := Vector3(eu, y, v)
			var la := P(c.x, c.y, c.z)
			var lb := P(eu, y + sin(a0) * r, v + cos(a0) * r)
			var lc := P(eu, y + sin(a1) * r, v + cos(a1) * r)
			tri_l(key, D(e[1]).normalized(), la, lb, lc)


# --- Walls with openings --------------------------------------------------------------------------

## A wall face: `o` the frame point at a = 0, y = 0; `t` the frame direction of +a; `n` its
## outward frame normal. From a = a0..a1, y = y0..y1. `openings`: dictionaries {a0, a1, y0, y1,
## "arch": bool (y1 is the crown, the spring is y1 - width/2), "glass": key or "" (none), "depth":
## setback of the glass / the reveal's depth, "through": bool (a reveal the whole `depth` and no
## glass: an arcade)}. `reveal` is the reveal's material key.
func wall(key: String, o: Vector3, t: Vector3, n: Vector3, a0: float, a1: float, y0: float, y1: float, openings: Array = [], reveal: String = "") -> void:
	var as_: Array[float] = [a0, a1]
	var ys: Array[float] = [y0, y1]
	for op: Dictionary in openings:
		as_.append(float(op.a0))
		as_.append(float(op.a1))
		ys.append(float(op.y0))
		ys.append(_spring(op))
		ys.append(float(op.y1))
	as_.sort()
	ys.sort()
	var A := _uniq(as_)
	var Y := _uniq(ys)
	var W := func(a: float, y: float) -> Vector3:
		return o + t * a + Vector3(0.0, y, 0.0)
	for i in A.size() - 1:
		var ca0: float = A[i]
		var ca1: float = A[i + 1]
		if ca1 <= a0 + 0.001 or ca0 >= a1 - 0.001:
			continue
		for j in Y.size() - 1:
			var cy0: float = Y[j]
			var cy1: float = Y[j + 1]
			if cy1 <= y0 + 0.001 or cy0 >= y1 - 0.001:
				continue
			var mid := Vector2((ca0 + ca1) * 0.5, (cy0 + cy1) * 0.5)
			var skip := false
			for op: Dictionary in openings:
				if mid.x > float(op.a0) and mid.x < float(op.a1) and mid.y > float(op.y0) and mid.y < float(op.y1):
					skip = true
					break
			if skip:
				continue
			quad(key, n, W.call(ca0, cy0), W.call(ca1, cy0), W.call(ca1, cy1), W.call(ca0, cy1))
	for op: Dictionary in openings:
		_opening(key, o, t, n, op, reveal if reveal != "" else key)


func _spring(op: Dictionary) -> float:
	if bool(op.get("arch", false)):
		return float(op.y1) - (float(op.a1) - float(op.a0)) * 0.5
	return float(op.y1)


func _uniq(a: Array[float]) -> Array[float]:
	var out: Array[float] = []
	for x in a:
		if out.is_empty() or x - out.back() > 0.002:
			out.append(x)
	return out


## The arc of an arched opening: points from the left spring over the crown to the right.
func _arc(op: Dictionary, segs: int) -> Array[Vector2]:
	var r := (float(op.a1) - float(op.a0)) * 0.5
	var cx := float(op.a0) + r
	var cy := _spring(op)
	var out: Array[Vector2] = []
	for k in segs + 1:
		var ang := PI - PI * float(k) / float(segs)
		out.append(Vector2(cx + cos(ang) * r, cy + sin(ang) * r))
	return out


func _opening(key: String, o: Vector3, t: Vector3, n: Vector3, op: Dictionary, reveal: String) -> void:
	var dep := float(op.get("depth", 0.2))
	var oa0 := float(op.a0)
	var oa1 := float(op.a1)
	var oy0 := float(op.y0)
	var oy1 := float(op.y1)
	var sp := _spring(op)
	var arch := bool(op.get("arch", false))
	var W := func(a: float, y: float, d: float) -> Vector3:
		return o + t * a + Vector3(0.0, y, 0.0) - n * d
	# Arch spandrels: the head band between the arc and the opening's rect corners.
	var segs := 10
	var arc: Array[Vector2] = []
	if arch:
		arc = _arc(op, segs)
	if arch:
		var mid := segs / 2
		for k in segs:
			var p0: Vector2 = arc[k]
			var p1: Vector2 = arc[k + 1]
			var corner := Vector2(oa0, oy1) if k < mid else Vector2(oa1, oy1)
			quad_tri(key, n, W.call(corner.x, corner.y, 0.0), W.call(p0.x, p0.y, 0.0), W.call(p1.x, p1.y, 0.0))
	# Reveals: the jambs, the sill, the head or the arch soffit.
	quad(reveal, t, W.call(oa0, oy0, 0.0), W.call(oa0, sp, 0.0), W.call(oa0, sp, dep), W.call(oa0, oy0, dep))
	quad(reveal, -t, W.call(oa1, oy0, 0.0), W.call(oa1, sp, 0.0), W.call(oa1, sp, dep), W.call(oa1, oy0, dep))
	if oy0 > 0.02:
		quad(reveal, Vector3.UP, W.call(oa0, oy0, 0.0), W.call(oa1, oy0, 0.0), W.call(oa1, oy0, dep), W.call(oa0, oy0, dep))
	if arch:
		var cx := (oa0 + oa1) * 0.5
		for k in segs:
			var p0: Vector2 = arc[k]
			var p1: Vector2 = arc[k + 1]
			var m := (p0 + p1) * 0.5
			var inward := (Vector2(cx, sp) - m).normalized()
			var nn := t * inward.x + Vector3(0.0, inward.y, 0.0)
			quad(reveal, nn, W.call(p0.x, p0.y, 0.0), W.call(p1.x, p1.y, 0.0), W.call(p1.x, p1.y, dep), W.call(p0.x, p0.y, dep))
	else:
		quad(reveal, Vector3.DOWN, W.call(oa0, oy1, 0.0), W.call(oa1, oy1, 0.0), W.call(oa1, oy1, dep), W.call(oa0, oy1, dep))
	var gk := String(op.get("glass", ""))
	if gk == "" or bool(op.get("through", false)):
		return
	# The glass, set back `dep` in the opening.
	_pane += 1
	var rnd := float(absi(hash([seed_value, _pane])) % 1000) / 1000.0
	var w := oa1 - oa0
	var h := oy1 - oy0
	var rect_top := sp
	var gcol := Color(clampf((oy0 - float(op.get("floor", 0.0))) / 4.0, 0.0, 1.0), clampf(float(op.get("room_h", 3.4)) / 8.0, 0.0, 1.0), 0.0, rnd)
	_glass_quad(gk, n, W.call(oa0, oy0, dep), W.call(oa1, oy0, dep), W.call(oa1, rect_top, dep), W.call(oa0, rect_top, dep),
		[Vector2(0, 0), Vector2(w, 0), Vector2(w, rect_top - oy0), Vector2(0, rect_top - oy0)], Vector2(w, h), gcol)
	if arch:
		var cx2 := (oa0 + oa1) * 0.5
		for k in segs:
			var p0: Vector2 = arc[k]
			var p1: Vector2 = arc[k + 1]
			_glass_tri(gk, n, W.call(cx2, sp, dep), W.call(p0.x, p0.y, dep), W.call(p1.x, p1.y, dep),
				[Vector2(cx2 - oa0, sp - oy0), Vector2(p0.x - oa0, p0.y - oy0), Vector2(p1.x - oa0, p1.y - oy0)], Vector2(w, h), gcol)


## A frame triangle facing frame normal `n` (no explicit UV).
func quad_tri(key: String, n: Vector3, a: Vector3, b: Vector3, c: Vector3) -> void:
	tri_l(key, D(n).normalized(), P(a.x, a.y, a.z), P(b.x, b.y, b.z), P(c.x, c.y, c.z))


func _glass_quad(key: String, n: Vector3, a: Vector3, b: Vector3, c: Vector3, d: Vector3, uv: Array, size: Vector2, col: Color) -> void:
	_glass_tri(key, n, a, b, c, [uv[0], uv[1], uv[2]], size, col)
	_glass_tri(key, n, a, c, d, [uv[0], uv[2], uv[3]], size, col)


func _glass_tri(key: String, n: Vector3, a: Vector3, b: Vector3, c: Vector3, uv: Array, size: Vector2, col: Color) -> void:
	var ln := D(n).normalized()
	var pts := [P(a.x, a.y, a.z), P(b.x, b.y, b.z), P(c.x, c.y, c.z)]
	var uvs := [uv[0], uv[1], uv[2]]
	if ((pts[1] as Vector3) - (pts[0] as Vector3)).cross((pts[2] as Vector3) - (pts[0] as Vector3)).dot(ln) > 0.0:
		pts = [pts[0], pts[2], pts[1]]
		uvs = [uvs[0], uvs[2], uvs[1]]
	var st := _tool(key)
	# The pane's own +a direction in local space (the shader's tangent): the wall's t.
	for k in 3:
		st.set_normal(ln)
		st.set_color(col)
		st.set_uv(uvs[k])
		st.set_uv2(size)
		st.add_vertex(pts[k])
	tris += 1


## Muntins: a grid of thin bars `w` wide in front of the glass of a (rect or arched) opening.
func muntins(key: String, o: Vector3, t: Vector3, n: Vector3, op: Dictionary, cols: int, rows: int, w: float = 0.045) -> void:
	var dep := float(op.get("depth", 0.2)) - 0.03
	var oa0 := float(op.a0)
	var oa1 := float(op.a1)
	var oy0 := float(op.y0)
	var sp := _spring(op)
	var arch := bool(op.get("arch", false))
	var r := (oa1 - oa0) * 0.5
	var cx := oa0 + r
	for i in range(1, cols):
		var a := lerpf(oa0, oa1, float(i) / float(cols))
		var top := sp
		if arch:
			top = sp + sqrt(maxf(r * r - (a - cx) * (a - cx), 0.0))
		var p := o + t * a - n * dep
		beam(key, p + Vector3(0.0, oy0, 0.0), p + Vector3(0.0, top, 0.0), w)
	for j in range(1, rows):
		var y := lerpf(oy0, sp, float(j) / float(rows))
		beam(key, o + t * oa0 + Vector3(0.0, y, 0.0) - n * dep, o + t * oa1 + Vector3(0.0, y, 0.0) - n * dep, w)
	if arch:
		beam(key, o + t * oa0 + Vector3(0.0, sp, 0.0) - n * dep, o + t * oa1 + Vector3(0.0, sp, 0.0) - n * dep, w)


# --- Roofs -----------------------------------------------------------------------------------------

## A hip roof over the frame rect (u0..u1, v0..v1) from eave height `y`, `pitch` rise per run,
## `eave` overhang: four slopes in `key` (UV in metres along the eave and up the slope), the soffit
## underneath in `soffit`, a fascia. Returns the ridge height.
func hip(key: String, soffit: String, u0: float, u1: float, v0: float, v1: float, y: float, pitch: float, eave: float) -> float:
	var e0 := Vector2(u0 - eave, v0 - eave)
	var e1 := Vector2(u1 + eave, v1 + eave)
	var w := e1.x - e0.x
	var d := e1.y - e0.y
	var run := minf(w, d) * 0.5
	var ry := y - eave * pitch + run * pitch
	var ey := y - eave * pitch
	var r0: Vector3
	var r1: Vector3
	if w >= d:
		r0 = Vector3(e0.x + run, ry, (e0.y + e1.y) * 0.5)
		r1 = Vector3(e1.x - run, ry, (e0.y + e1.y) * 0.5)
	else:
		r0 = Vector3((e0.x + e1.x) * 0.5, ry, e0.y + run)
		r1 = Vector3((e0.x + e1.x) * 0.5, ry, e1.y - run)
	var c00 := Vector3(e0.x, ey, e0.y)
	var c10 := Vector3(e1.x, ey, e0.y)
	var c11 := Vector3(e1.x, ey, e1.y)
	var c01 := Vector3(e0.x, ey, e1.y)
	var slope := sqrt(1.0 + pitch * pitch)
	# The four faces: front (v0), right (u1), back (v1), left (u0).
	var faces: Array
	if w >= d:
		faces = [[[c00, c10, r1, r0], Vector3(0, 1, -pitch)], [[c10, c11, r1], Vector3(pitch, 1, 0)],
			[[c11, c01, r0, r1], Vector3(0, 1, pitch)], [[c01, c00, r0], Vector3(-pitch, 1, 0)]]
	else:
		faces = [[[c00, c10, r0], Vector3(0, 1, -pitch)], [[c10, c11, r1, r0], Vector3(pitch, 1, 0)],
			[[c11, c01, r1], Vector3(0, 1, pitch)], [[c01, c00, r0, r1], Vector3(-pitch, 1, 0)]]
	for f: Array in faces:
		var pts: Array = f[0]
		var nn: Vector3 = (f[1] as Vector3).normalized()
		var a: Vector3 = pts[0]
		var along: Vector3 = (pts[1] as Vector3) - a
		along.y = 0.0
		var ad := along.normalized()
		var uv := func(p: Vector3) -> Vector2:
			return Vector2((p - a).dot(ad), (p.y - ey) * slope / maxf(pitch, 0.01))
		tri_uv(key, nn, pts[0], pts[1], pts[2], uv.call(pts[0]), uv.call(pts[1]), uv.call(pts[2]))
		if pts.size() == 4:
			tri_uv(key, nn, pts[0], pts[2], pts[3], uv.call(pts[0]), uv.call(pts[2]), uv.call(pts[3]))
	# Soffit and fascia.
	if soffit != "":
		quad(soffit, Vector3.DOWN, c00, c10, c11, c01)
		for edge: Array in [[c00, c10, Vector3(0, 0, -1)], [c10, c11, Vector3(1, 0, 0)], [c11, c01, Vector3(0, 0, 1)], [c01, c00, Vector3(-1, 0, 0)]]:
			var p0: Vector3 = edge[0]
			var p1: Vector3 = edge[1]
			quad(soffit, edge[2], p0, p1, p1 + Vector3(0, 0.18, 0), p0 + Vector3(0, 0.18, 0))
	return ry


## A gable roof over the frame rect with its ridge along u (`along_u`) or v, slopes in `key`,
## the gable triangles in `wall_key` (flush with the walls), soffit under the eaves.
func gable(key: String, wall_key: String, soffit: String, u0: float, u1: float, v0: float, v1: float, y: float, pitch: float, eave: float, along_u: bool) -> float:
	var slope := sqrt(1.0 + pitch * pitch)
	if along_u:
		var vm := (v0 + v1) * 0.5
		var run := (v1 - v0) * 0.5 + eave
		var ry := y + (v1 - v0) * 0.5 * pitch
		var ey := y - eave * pitch
		var g0 := u0 - eave * 0.6
		var g1 := u1 + eave * 0.6
		for s: float in [-1.0, 1.0]:
			var ve := vm + s * run
			var nn := Vector3(0, 1, s * pitch).normalized()
			var a := Vector3(g0, ey, ve)
			var b := Vector3(g1, ey, ve)
			var c := Vector3(g1, ry, vm)
			var d := Vector3(g0, ry, vm)
			tri_uv(key, nn, a, b, c, Vector2(0, 0), Vector2(g1 - g0, 0), Vector2(g1 - g0, run * slope))
			tri_uv(key, nn, a, c, d, Vector2(0, 0), Vector2(g1 - g0, run * slope), Vector2(0, run * slope))
			if soffit != "":
				quad(soffit, Vector3.DOWN, Vector3(g0, ey, ve), Vector3(g1, ey, ve), Vector3(g1, y, vm + s * (v1 - v0) * 0.5), Vector3(g0, y, vm + s * (v1 - v0) * 0.5))
		for e: Array in [[u0, -1.0], [u1, 1.0]]:
			var eu: float = e[0]
			quad_tri(wall_key, Vector3(e[1], 0, 0), Vector3(eu, y, v0), Vector3(eu, y, v1), Vector3(eu, ry, vm))
		return ry
	var um := (u0 + u1) * 0.5
	var run2 := (u1 - u0) * 0.5 + eave
	var ry2 := y + (u1 - u0) * 0.5 * pitch
	var ey2 := y - eave * pitch
	var h0 := v0 - eave * 0.6
	var h1 := v1 + eave * 0.6
	for s: float in [-1.0, 1.0]:
		var ue := um + s * run2
		var nn := Vector3(s * pitch, 1, 0).normalized()
		var a := Vector3(ue, ey2, h0)
		var b := Vector3(ue, ey2, h1)
		var c := Vector3(um, ry2, h1)
		var d := Vector3(um, ry2, h0)
		tri_uv(key, nn, a, b, c, Vector2(0, 0), Vector2(h1 - h0, 0), Vector2(h1 - h0, run2 * slope))
		tri_uv(key, nn, a, c, d, Vector2(0, 0), Vector2(h1 - h0, run2 * slope), Vector2(0, run2 * slope))
		if soffit != "":
			quad(soffit, Vector3.DOWN, Vector3(ue, ey2, h0), Vector3(ue, ey2, h1), Vector3(um + s * (u1 - u0) * 0.5, y, h1), Vector3(um + s * (u1 - u0) * 0.5, y, h0))
	for e: Array in [[v0, -1.0], [v1, 1.0]]:
		var ev: float = e[0]
		quad_tri(wall_key, Vector3(0, 0, e[1]), Vector3(u0, y, ev), Vector3(u1, y, ev), Vector3(um, ry2, ev))
	return ry2


## Rafter tails under an eave along frame u at height y, from u0 to u1 at v (sticking out by `out`
## toward -v when `dir` is -1, +v when 1), every `step`.
func rafters(key: String, u0: float, u1: float, y: float, v: float, out: float, dir: float, step: float = 0.75) -> void:
	var u := u0 + step * 0.5
	while u < u1:
		box(key, u - 0.06, u + 0.06, y - 0.2, y, v, v + dir * out)
		u += step


func commit(material_of: Callable) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	for key: String in _st:
		var st: SurfaceTool = _st[key]
		st.commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, material_of.call(key))
	return mesh
