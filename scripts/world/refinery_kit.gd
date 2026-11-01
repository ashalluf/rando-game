class_name RefineryKit
extends RefCounted
## The oil refinery's hardware (Refinery lays it out), code-built at real size into ONE SurfaceTool
## a chunk (or a far piece) on shaders/refinery.gdshader: what a face is rides in COLOR.a (K_*, in
## 32nds), its paint in COLOR.rgb (display numbers), UV metres in the face's frame and UV2 (height,
## a per-piece parameter), written by FilmStudioKit's / IndustrialKit's box, cyl, cone and quad
## writers and the ones below. Everything is placed in world space (x, y, z) handed in.
##
## `detail` false is the far / LOD level: no handrails, ladders, small pipes or treads, fewer sides
## (it is what the far city and the night aerial see; a piece of it is a few thousand triangles).
##
## Every piece appends its lamps to `lights` as [Vector3 position, Color, size (m), kind] for the
## billboard light mesh (Refinery.lights_mesh(), shaders/aircraft_lights.gdshader).

const K_TANK := 0
const K_ALU := 1
const K_STEEL := 2
const K_GRATE := 3
const K_CONCRETE := 4
const K_EARTH := 5
const K_RAIL := 6
const K_LAMP := 7
const K_ROOF := 8
const K_PIPE := 9
const K_GLASS := 10
const K_CLAD := 11
const K_SIGN := 12
const K_LOUVRE := 13
const K_DARK := 14
const K_BANDS := 15
const K_HOT := 16
const K_GRAVEL := 17
const K_SPHERE := 18
const K_SOOT := 19

## Light kinds in aircraft_lights.gdshader: 4 a field light (lit with the lamps only), 2 a beacon.
const L_FIELD := 4
const L_BEACON := 2
const SODIUM := Color(1.0, 0.62, 0.28, 1.0)
const LED := Color(0.92, 0.95, 1.0, 1.0)
const HALIDE := Color(0.86, 1.0, 0.82, 1.0)
const RED := Color(1.0, 0.08, 0.04, 1.0)

const SAFETY := Color(0.86, 0.66, 0.12)
const GREY_STEEL := Color(0.5, 0.52, 0.52)
const GREEN_STEEL := Color(0.36, 0.44, 0.4)
const TANK_WHITE := Color(0.86, 0.86, 0.83)
const TANK_TAN := Color(0.8, 0.76, 0.66)
const CONCRETE := Color(0.72, 0.71, 0.68)
const EARTH := Color(0.58, 0.49, 0.36)
## The pipes' colours: aluminium-grey, product lines in browns and greens, steam silver, a few in
## safety yellow and fire-main red.
const PIPE_PAINTS := [Color(0.58, 0.58, 0.56), Color(0.5, 0.36, 0.24), Color(0.36, 0.42, 0.34), Color(0.72, 0.72, 0.7),
	Color(0.62, 0.6, 0.55), Color(0.28, 0.3, 0.32), Color(0.84, 0.66, 0.16), Color(0.6, 0.14, 0.1)]

static var _material: ShaderMaterial
## Triangles written since start (the probe reads it).
static var tris: int = 0


static func material() -> ShaderMaterial:
	if _material != null:
		return _material
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/refinery.gdshader")
	mat.set_shader_parameter("concrete_tex", PropFactory.texture("concrete", "Color"))
	mat.set_shader_parameter("dirt_tex", PropFactory.texture("hill_dirt", "Color"))
	_material = mat
	return mat


static func h01(parts: Array) -> float:
	return float(absi(hash(parts)) % 100003) / 100003.0


# --- Primitives ---------------------------------------------------------------------------------

static func box(st: SurfaceTool, xf: Transform3D, size: Vector3, kind: int, paint: Color, param: float = 0.0, skip: int = 32) -> void:
	tris += 12
	FilmStudioKit.box(st, xf, size, kind, paint, param, skip)


## An upright axis-aligned box, its foot at `foot`.
static func block(st: SurfaceTool, foot: Vector3, size: Vector3, kind: int, paint: Color, param: float = 0.0, skip: int = 0) -> void:
	box(st, Transform3D(Basis(), foot + Vector3(0.0, size.y * 0.5, 0.0)), size, kind, paint, param, skip)


## A beam from a to b, w x t in section.
static func beam(st: SurfaceTool, a: Vector3, b: Vector3, w: float, t: float, kind: int, paint: Color, up: Vector3 = Vector3.UP) -> void:
	tris += 12
	FilmStudioKit.beam(st, a, b, w, t, kind, paint, up)


## A vertex in the kit's encoding.
static func _v(st: SurfaceTool, p: Vector3, n: Vector3, col: Color, uv: Vector2, uv2: Vector2) -> void:
	st.set_normal(n)
	st.set_color(col)
	st.set_uv(uv)
	st.set_uv2(uv2)
	st.add_vertex(p)


static func _col(kind: int, paint: Color) -> Color:
	return Color(paint.r, paint.g, paint.b, (float(kind) + 0.5) / 32.0)


## A tube along any axis: from `a` to `b`, radius r, `segs` sides, outward faces, open ends unless
## `caps`. UV x round it (metres), y along it; UV2 (length, param).
static func tube(st: SurfaceTool, a: Vector3, b: Vector3, r: float, kind: int, paint: Color, segs: int = 8, caps: bool = false, param: float = 0.0, r_b: float = -1.0) -> void:
	var d := b - a
	var l := d.length()
	if l < 0.01:
		return
	if r_b < 0.0:
		r_b = r
	var y := d / l
	var x := Vector3.UP.cross(y) if absf(y.y) < 0.95 else Vector3.RIGHT.cross(y)
	x = x.normalized()
	var z := x.cross(y).normalized()
	var col := _col(kind, paint)
	var circ := TAU * maxf(r, r_b)
	var slope := (r - r_b) / l
	tris += segs * 2 + (segs * 2 if caps else 0)
	for i in segs:
		var a0 := TAU * float(i) / float(segs)
		var a1 := TAU * float(i + 1) / float(segs)
		var d0 := x * cos(a0) + z * sin(a0)
		var d1 := x * cos(a1) + z * sin(a1)
		var n0 := (d0 + y * slope).normalized()
		var n1 := (d1 + y * slope).normalized()
		var p00 := a + d0 * r
		var p10 := a + d1 * r
		var p01 := b + d0 * r_b
		var p11 := b + d1 * r_b
		var u0 := circ * float(i) / float(segs)
		var u1 := circ * float(i + 1) / float(segs)
		var uv2 := Vector2(l, param)
		# Outward winding: (p10 - p00) x (p01 - p00) must point along the normal.
		if (p10 - p00).cross(p01 - p00).dot(n0 + n1) > 0.0:
			_v(st, p00, n0, col, Vector2(u0, 0.0), uv2); _v(st, p11, n1, col, Vector2(u1, l), uv2); _v(st, p10, n1, col, Vector2(u1, 0.0), uv2)
			_v(st, p00, n0, col, Vector2(u0, 0.0), uv2); _v(st, p01, n0, col, Vector2(u0, l), uv2); _v(st, p11, n1, col, Vector2(u1, l), uv2)
		else:
			_v(st, p00, n0, col, Vector2(u0, 0.0), uv2); _v(st, p10, n1, col, Vector2(u1, 0.0), uv2); _v(st, p11, n1, col, Vector2(u1, l), uv2)
			_v(st, p00, n0, col, Vector2(u0, 0.0), uv2); _v(st, p11, n1, col, Vector2(u1, l), uv2); _v(st, p01, n0, col, Vector2(u0, l), uv2)
		if caps:
			for end: Array in [[a, -y, r, p00, p10], [b, y, r_b, p01, p11]]:
				var c: Vector3 = end[0]
				var n: Vector3 = end[1]
				var q0: Vector3 = end[3]
				var q1: Vector3 = end[4]
				var uvc := Vector2(maxf(r, r_b), maxf(r, r_b))
				if (q0 - c).cross(q1 - c).dot(n) < 0.0:
					_v(st, c, n, col, uvc, uv2); _v(st, q0, n, col, uvc + Vector2(cos(a0), sin(a0)) * float(end[2]), uv2); _v(st, q1, n, col, uvc + Vector2(cos(a1), sin(a1)) * float(end[2]), uv2)
				else:
					_v(st, c, n, col, uvc, uv2); _v(st, q1, n, col, uvc + Vector2(cos(a1), sin(a1)) * float(end[2]), uv2); _v(st, q0, n, col, uvc + Vector2(cos(a0), sin(a0)) * float(end[2]), uv2)


## An upright cylinder wall (no caps), its foot at `foot`; `inward` faces the inside (a tank's
## inner wall over its floating roof). UV x round it (metres), y up; UV2 (h, param).
static func shell(st: SurfaceTool, foot: Vector3, r: float, h: float, kind: int, paint: Color, segs: int, inward: bool = false, param: float = 0.0, uv2h: float = -1.0, y0: float = 0.0) -> void:
	var col := _col(kind, paint)
	var circ := TAU * r
	var uv2 := Vector2(uv2h if uv2h > 0.0 else h, param)
	tris += segs * 2
	for i in segs:
		var a0 := TAU * float(i) / float(segs)
		var a1 := TAU * float(i + 1) / float(segs)
		var d0 := Vector3(cos(a0), 0.0, sin(a0))
		var d1 := Vector3(cos(a1), 0.0, sin(a1))
		var p00 := foot + d0 * r
		var p10 := foot + d1 * r
		var p01 := p00 + Vector3(0.0, h, 0.0)
		var p11 := p10 + Vector3(0.0, h, 0.0)
		var n0 := -d0 if inward else d0
		var n1 := -d1 if inward else d1
		var u0 := circ * float(i) / float(segs)
		var u1 := circ * float(i + 1) / float(segs)
		# Godot's front faces wind clockwise as seen: (p00, p01, p11) is counter-clockwise from
		# outside, so the outer wall is p00, p11, p01.
		if inward:
			_v(st, p00, n0, col, Vector2(u0, y0), uv2); _v(st, p01, n0, col, Vector2(u0, y0 + h), uv2); _v(st, p11, n1, col, Vector2(u1, y0 + h), uv2)
			_v(st, p00, n0, col, Vector2(u0, y0), uv2); _v(st, p11, n1, col, Vector2(u1, y0 + h), uv2); _v(st, p10, n1, col, Vector2(u1, y0), uv2)
		else:
			_v(st, p00, n0, col, Vector2(u0, y0), uv2); _v(st, p11, n1, col, Vector2(u1, y0 + h), uv2); _v(st, p01, n0, col, Vector2(u0, y0 + h), uv2)
			_v(st, p00, n0, col, Vector2(u0, y0), uv2); _v(st, p10, n1, col, Vector2(u1, y0), uv2); _v(st, p11, n1, col, Vector2(u1, y0 + h), uv2)


## A flat disc (or annulus from r_in) facing up (or down), at `c`. UV = local xz + r, so a floating
## roof's shader knows its centre (UV2.x is the diameter).
static func disc(st: SurfaceTool, c: Vector3, r: float, kind: int, paint: Color, segs: int, up: bool = true, r_in: float = 0.0, param: float = 0.0) -> void:
	var col := _col(kind, paint)
	var n := Vector3.UP if up else Vector3.DOWN
	var uv2 := Vector2(r * 2.0, param)
	tris += segs * (2 if r_in > 0.0 else 1)
	for i in segs:
		var a0 := TAU * float(i) / float(segs)
		var a1 := TAU * float(i + 1) / float(segs)
		var d0 := Vector3(cos(a0), 0.0, sin(a0))
		var d1 := Vector3(cos(a1), 0.0, sin(a1))
		var o0 := c + d0 * r
		var o1 := c + d1 * r
		var i0 := c + d0 * r_in
		var i1 := c + d1 * r_in
		var uo0 := Vector2(d0.x, d0.z) * r + Vector2(r, r)
		var uo1 := Vector2(d1.x, d1.z) * r + Vector2(r, r)
		var ui0 := Vector2(d0.x, d0.z) * r_in + Vector2(r, r)
		var ui1 := Vector2(d1.x, d1.z) * r_in + Vector2(r, r)
		# (Godot's front faces wind clockwise as seen: from above that is i0, o0, o1.)
		if up:
			_v(st, i0, n, col, ui0, uv2); _v(st, o0, n, col, uo0, uv2); _v(st, o1, n, col, uo1, uv2)
			if r_in > 0.0:
				_v(st, i0, n, col, ui0, uv2); _v(st, o1, n, col, uo1, uv2); _v(st, i1, n, col, ui1, uv2)
		else:
			_v(st, i0, n, col, ui0, uv2); _v(st, o1, n, col, uo1, uv2); _v(st, o0, n, col, uo0, uv2)
			if r_in > 0.0:
				_v(st, i0, n, col, ui0, uv2); _v(st, i1, n, col, ui1, uv2); _v(st, o1, n, col, uo1, uv2)


## A cone roof (or a dome when `dome`) over a shell of radius r at height `c.y`.
static func roof_cone(st: SurfaceTool, c: Vector3, r: float, rise: float, kind: int, paint: Color, segs: int, dome: bool = false) -> void:
	var col := _col(kind, paint)
	var rings := 4 if dome else 1
	tris += segs * rings * 2
	for j in rings:
		var t0 := float(j) / float(rings)
		var t1 := float(j + 1) / float(rings)
		var r0 := r * (cos(t0 * PI * 0.5) if dome else 1.0 - t0)
		var r1 := r * (cos(t1 * PI * 0.5) if dome else 1.0 - t1)
		var y0 := rise * (sin(t0 * PI * 0.5) if dome else t0)
		var y1 := rise * (sin(t1 * PI * 0.5) if dome else t1)
		for i in segs:
			var a0 := TAU * float(i) / float(segs)
			var a1 := TAU * float(i + 1) / float(segs)
			var d0 := Vector3(cos(a0), 0.0, sin(a0))
			var d1 := Vector3(cos(a1), 0.0, sin(a1))
			var p00 := c + d0 * r0 + Vector3(0.0, y0, 0.0)
			var p10 := c + d1 * r0 + Vector3(0.0, y0, 0.0)
			var p01 := c + d0 * r1 + Vector3(0.0, y1, 0.0)
			var p11 := c + d1 * r1 + Vector3(0.0, y1, 0.0)
			var slope := Vector2(rise, r).normalized() if not dome else Vector2(cos((t0 + t1) * PI * 0.25), sin((t0 + t1) * PI * 0.25))
			var n0 := (d0 * slope.x + Vector3.UP * slope.y).normalized()
			var n1 := (d1 * slope.x + Vector3.UP * slope.y).normalized()
			var uv2 := Vector2(rise, 0.0)
			_v(st, p00, n0, col, Vector2(a0 * r, y0), uv2); _v(st, p11, n1, col, Vector2(a1 * r, y1), uv2); _v(st, p01, n0, col, Vector2(a0 * r, y1), uv2)
			if r1 > 0.001:
				_v(st, p00, n0, col, Vector2(a0 * r, y0), uv2); _v(st, p10, n1, col, Vector2(a1 * r, y0), uv2); _v(st, p11, n1, col, Vector2(a1 * r, y1), uv2)


## A sphere of radius r centred at c (latitude-longitude, `segs` round and segs / 2 up).
static func sphere(st: SurfaceTool, c: Vector3, r: float, kind: int, paint: Color, segs: int, param: float = 0.0) -> void:
	var col := _col(kind, paint)
	var rows := maxi(4, segs / 2)
	tris += segs * rows * 2
	var uv2 := Vector2(r * 2.0, param)
	for j in rows:
		var b0 := -PI * 0.5 + PI * float(j) / float(rows)
		var b1 := -PI * 0.5 + PI * float(j + 1) / float(rows)
		for i in segs:
			var a0 := TAU * float(i) / float(segs)
			var a1 := TAU * float(i + 1) / float(segs)
			var n00 := Vector3(cos(b0) * cos(a0), sin(b0), cos(b0) * sin(a0))
			var n10 := Vector3(cos(b0) * cos(a1), sin(b0), cos(b0) * sin(a1))
			var n01 := Vector3(cos(b1) * cos(a0), sin(b1), cos(b1) * sin(a0))
			var n11 := Vector3(cos(b1) * cos(a1), sin(b1), cos(b1) * sin(a1))
			var u0 := a0 * r
			var u1 := a1 * r
			var v0 := (b0 + PI * 0.5) * r
			var v1 := (b1 + PI * 0.5) * r
			_v(st, c + n00 * r, n00, col, Vector2(u0, v0), uv2); _v(st, c + n11 * r, n11, col, Vector2(u1, v1), uv2); _v(st, c + n01 * r, n01, col, Vector2(u0, v1), uv2)
			_v(st, c + n00 * r, n00, col, Vector2(u0, v0), uv2); _v(st, c + n10 * r, n10, col, Vector2(u1, v0), uv2); _v(st, c + n11 * r, n11, col, Vector2(u1, v1), uv2)


## A handrail run from a to b (feet at the deck), both faces, 1.1 m tall: the shader keeps the rails,
## posts and toe board.
static func rail(st: SurfaceTool, a: Vector3, b: Vector3, paint: Color = SAFETY) -> void:
	var l := a.distance_to(b)
	if l < 0.05:
		return
	var up := Vector3(0.0, 1.1, 0.0)
	var side := (b - a).cross(Vector3.UP).normalized()
	var col := _col(K_RAIL, paint)
	var uv2 := Vector2(1.1, 0.0)
	tris += 4
	for s: float in [1.0, -1.0]:
		var n := side * s
		var pts := [a, b, b + up, a + up]
		var uvs := [Vector2(0.0, 0.0), Vector2(l, 0.0), Vector2(l, 1.1), Vector2(0.0, 1.1)]
		var order := [0, 1, 2, 0, 2, 3] if (pts[1] - pts[0]).cross(pts[2] - pts[0]).dot(n) > 0.0 else [0, 2, 1, 0, 3, 2]
		for k: int in order:
			_v(st, pts[k], n, col, uvs[k], uv2)


## A ring of handrail at radius r round c (feet at c.y).
static func rail_ring(st: SurfaceTool, c: Vector3, r: float, segs: int, paint: Color = SAFETY, from_a: float = 0.0, to_a: float = TAU) -> void:
	for i in segs:
		var a0 := lerpf(from_a, to_a, float(i) / float(segs))
		var a1 := lerpf(from_a, to_a, float(i + 1) / float(segs))
		rail(st, c + Vector3(cos(a0), 0.0, sin(a0)) * r, c + Vector3(cos(a1), 0.0, sin(a1)) * r, paint)


## A grated circular platform round a vessel: annulus deck, its edge, a rail on the outside.
static func ring_deck(st: SurfaceTool, c: Vector3, r_in: float, r_out: float, segs: int, detail: bool, from_a: float = 0.0, to_a: float = TAU) -> void:
	var full := is_equal_approx(to_a - from_a, TAU)
	if full:
		disc(st, c, r_out, K_GRATE, GREY_STEEL, segs, true, r_in)
		disc(st, c - Vector3(0.0, 0.06, 0.0), r_out, K_GRATE, GREY_STEEL, segs, false, r_in)
		shell(st, c - Vector3(0.0, 0.12, 0.0), r_out, 0.12, K_STEEL, GREY_STEEL, segs)
	else:
		# A part ring as quads.
		var col := _col(K_GRATE, GREY_STEEL)
		for i in segs:
			var a0 := lerpf(from_a, to_a, float(i) / float(segs))
			var a1 := lerpf(from_a, to_a, float(i + 1) / float(segs))
			var d0 := Vector3(cos(a0), 0.0, sin(a0))
			var d1 := Vector3(cos(a1), 0.0, sin(a1))
			var q := [c + d0 * r_in, c + d1 * r_in, c + d1 * r_out, c + d0 * r_out]
			FilmStudioKit.quad(st, q[0], q[1], q[2], q[3], Vector3.UP, K_GRATE, GREY_STEEL, [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)], 0.1)
			FilmStudioKit.quad(st, q[0] - Vector3(0, 0.06, 0), q[1] - Vector3(0, 0.06, 0), q[2] - Vector3(0, 0.06, 0), q[3] - Vector3(0, 0.06, 0), Vector3.DOWN, K_GRATE, GREY_STEEL, [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)], 0.1)
			tris += 4
		col = col
	if detail:
		rail_ring(st, c, r_out - 0.05, maxi(6, segs / (1 if full else 2)), SAFETY, from_a, to_a)


## A caged ladder up the side of something, from a to a + (0, h, 0), facing out along `out`.
static func ladder(st: SurfaceTool, a: Vector3, h: float, out: Vector3) -> void:
	var side := out.cross(Vector3.UP).normalized()
	for s: float in [-0.22, 0.22]:
		beam(st, a + side * s, a + side * s + Vector3(0.0, h, 0.0), 0.05, 0.05, K_STEEL, SAFETY)
	# The cage: hoops every 1.5 m from 2.4 m up, five uprights.
	var y := 2.4
	while y < h:
		var c := a + out * 0.38 + Vector3(0.0, y, 0.0)
		for k in 6:
			var a0 := PI * float(k) / 6.0
			var a1 := PI * float(k + 1) / 6.0
			var p0 := c + (side * cos(a0) + out * sin(a0)) * 0.38
			var p1 := c + (side * cos(a1) + out * sin(a1)) * 0.38
			beam(st, p0, p1, 0.04, 0.04, K_STEEL, SAFETY)
		y += 1.5
	for k in 5:
		var a0 := PI * float(k) / 4.0
		var p := a + out * 0.38 + (side * cos(a0) + out * sin(a0)) * 0.38
		beam(st, p + Vector3(0.0, 2.4, 0.0), p + Vector3(0.0, h, 0.0), 0.035, 0.035, K_STEEL, SAFETY)


## A run of stairs from a (bottom) to b (top): two stringers, treads (detail), rails both sides.
static func stair(st: SurfaceTool, a: Vector3, b: Vector3, w: float, detail: bool, paint: Color = SAFETY) -> void:
	var run := Vector3(b.x - a.x, 0.0, b.z - a.z)
	var dir := run.normalized()
	var side := dir.cross(Vector3.UP).normalized()
	for s: float in [-0.5, 0.5]:
		beam(st, a + side * w * s, b + side * w * s, 0.06, 0.25, K_STEEL, paint, side)
	if not detail:
		var mid := (a + b) * 0.5
		var l := a.distance_to(b)
		var xf := Transform3D(Basis(side, (b - a).normalized().cross(side).normalized() * -1.0, (b - a).normalized()), mid)
		box(st, xf, Vector3(w, 0.05, l), K_GRATE, GREY_STEEL)
		return
	var n := maxi(2, int((b.y - a.y) / 0.19))
	for i in n:
		var p := a.lerp(b, (float(i) + 0.5) / float(n))
		box(st, Transform3D(Basis(Vector3.UP, atan2(dir.x, dir.z)), p), Vector3(w, 0.04, 0.26), K_GRATE, GREY_STEEL)
	for s: float in [-0.5, 0.5]:
		rail(st, a + side * w * s, b + side * w * s, paint)


# --- Pieces -------------------------------------------------------------------------------------

## A floating-roof crude tank: diameter `D`, shell `H`, the roof floating `fill` (0..1) of the way
## up, inside its berm cell. A spiral stair up the shell to the rim walkway and a gauger's
## platform, a rolling ladder down to the roof, the wind girder, foam chambers round the rim.
static func floating_tank(st: SurfaceTool, c: Vector3, D: float, H: float, fill: float, seed: int, paint: Color, detail: bool, lights: Array) -> void:
	var r := D * 0.5
	var segs := 56 if detail else 28
	var param := float(seed % 97) / 9.7
	# A concrete ring wall under the shell.
	shell(st, c - Vector3(0.0, 0.3, 0.0), r + 0.4, 0.6, K_CONCRETE, CONCRETE, segs)
	disc(st, c + Vector3(0.0, 0.3, 0.0), r + 0.4, K_CONCRETE, CONCRETE, segs, true, r)
	shell(st, c, r, H, K_TANK, paint, segs, false, param)
	# The roof and the inner wall above it.
	var roof_y := clampf(lerpf(2.5, H - 1.8, fill), 2.5, H - 1.2)
	disc(st, c + Vector3(0.0, roof_y, 0.0), r - 0.2, K_ROOF, Color.WHITE, segs, true, 0.0, param)
	shell(st, c + Vector3(0.0, roof_y, 0.0), r - 0.02, H - roof_y, K_TANK, paint * 0.82, segs, true, param, H, roof_y)
	# The rim: a walkway ring outside the top and the wind girder 1 m below it.
	ring_deck(st, c + Vector3(0.0, H, 0.0), r, r + 0.85, segs, detail)
	ring_deck(st, c + Vector3(0.0, H - 1.6, 0.0), r, r + 0.75, segs, false)
	# The spiral stair: a quarter of the way round from the foot to the rim.
	var a0 := TAU * h01([seed, "stair"])
	var turns := clampf(H / (r * 1.2), 0.18, 0.4)
	var steps := 10 if detail else 4
	var prev := Vector3.ZERO
	for i in steps + 1:
		var t := float(i) / float(steps)
		var a := a0 + t * turns * TAU
		var p := c + Vector3(cos(a) * (r + 0.6), t * H, sin(a) * (r + 0.6))
		if i > 0:
			stair(st, prev, p, 0.9, detail)
		prev = p
	var top_a := a0 + turns * TAU
	var top := c + Vector3(cos(top_a) * (r + 0.6), H, sin(top_a) * (r + 0.6))
	# The gauger's platform at the stair head, and the rolling ladder down to the roof.
	var inward := Vector3(-cos(top_a), 0.0, -sin(top_a))
	block(st, top + inward * 0.4 + Vector3(0.0, 0.0, 0.0), Vector3(2.2, 0.08, 2.2), K_GRATE, GREY_STEEL)
	if detail:
		var foot_l := c + inward * 0.0 + Vector3(0.0, roof_y + 0.2, 0.0) + (top - c) * Vector3(0.35, 0.0, 0.35)
		beam(st, top + inward * 0.6 + Vector3(0.0, 0.1, 0.0), foot_l, 0.9, 0.12, K_STEEL, GREY_STEEL)
		tube(st, top + Vector3(0.0, 0.0, 0.0), top + Vector3(0.0, 2.6, 0.0), 0.08, K_STEEL, GREY_STEEL, 6)
		# Foam chambers every 15 m round the rim.
		var n := maxi(4, int(TAU * r / 15.0))
		for k in n:
			var a := TAU * float(k) / float(n)
			var p := c + Vector3(cos(a) * (r + 0.3), H - 0.9, sin(a) * (r + 0.3))
			tube(st, p, p + Vector3(0.0, 0.8, 0.0), 0.22, K_PIPE, Color(0.62, 0.14, 0.1), 6, true)
		# A product nozzle and valve at the foot.
		var na := a0 + PI
		var np := c + Vector3(cos(na) * r, 1.2, sin(na) * r)
		tube(st, np, np + Vector3(cos(na), 0.0, sin(na)) * 3.0, 0.45, K_PIPE, PIPE_PAINTS[seed % 4], 10, true)
	# Lights: a lamp at the stair head and two on the rim.
	lights.append([top + Vector3(0.0, 2.7, 0.0), SODIUM, 1.4, L_FIELD])
	lights.append([c + Vector3(cos(top_a + PI) * (r + 0.6), H + 1.6, sin(top_a + PI) * (r + 0.6)), SODIUM, 1.2, L_FIELD])
	lights.append([c + Vector3(cos(top_a + PI * 0.5) * (r + 0.6), H + 1.6, sin(top_a + PI * 0.5) * (r + 0.6)), LED, 1.0, L_FIELD])


## A fixed cone-roof tank (products, asphalt): shell, a shallow cone roof with a rail round its
## edge, a straight stair up the side.
static func cone_tank(st: SurfaceTool, c: Vector3, D: float, H: float, seed: int, paint: Color, detail: bool, lights: Array) -> void:
	var r := D * 0.5
	var segs := 40 if detail else 20
	var param := float(seed % 97) / 9.7
	shell(st, c - Vector3(0.0, 0.3, 0.0), r + 0.3, 0.6, K_CONCRETE, CONCRETE, segs)
	shell(st, c, r, H, K_TANK, paint, segs, false, param)
	var dome := seed % 3 == 0
	roof_cone(st, c + Vector3(0.0, H, 0.0), r + 0.15, r * (0.18 if dome else 0.1), K_TANK, paint * 0.9, segs, dome)
	if detail:
		rail_ring(st, c + Vector3(0.0, H + 0.05, 0.0), r - 0.2, 16)
	var a := TAU * h01([seed, "cone_stair"])
	var out := Vector3(cos(a), 0.0, sin(a))
	var side := out.cross(Vector3.UP)
	var base := c + out * (r + 0.6) - side * (H * 0.9)
	stair(st, base, c + out * (r + 0.6) + Vector3(0.0, H, 0.0), 0.8, detail)
	lights.append([c + out * (r + 0.3) + Vector3(0.0, H + 1.4, 0.0), SODIUM, 1.2, L_FIELD])


## A pressure sphere (LPG / butane) on its legs: the shell, eight to ten columns braced in pairs,
## the stair to the top platform, a valve set underneath.
static func pressure_sphere(st: SurfaceTool, c: Vector3, R: float, seed: int, detail: bool, lights: Array) -> void:
	var centre := c + Vector3(0.0, R + 2.2, 0.0)
	sphere(st, centre, R, K_SPHERE, Color(0.88, 0.88, 0.85), 32 if detail else 16, float(seed % 31))
	var n := 8 if R < 8.0 else 10
	for k in n:
		var a := TAU * float(k) / float(n)
		var p := Vector3(cos(a), 0.0, sin(a)) * R * 0.96
		block(st, c + p - Vector3(0.0, 0.3, 0.0), Vector3(1.4, 0.8, 1.4), K_CONCRETE, CONCRETE)
		tube(st, c + p, centre + p * 1.0 + Vector3(0.0, 0.2, 0.0), 0.38, K_CONCRETE if detail else K_STEEL, Color(0.6, 0.6, 0.58) if detail else GREY_STEEL, 8 if detail else 6)
		if detail:
			var q := Vector3(cos(a + TAU / float(n)), 0.0, sin(a + TAU / float(n))) * R * 0.96
			beam(st, c + p + Vector3(0.0, 0.6, 0.0), c + q + Vector3(0.0, R + 1.6, 0.0), 0.06, 0.06, K_STEEL, GREY_STEEL)
	ring_deck(st, centre + Vector3(0.0, R * 0.98, 0.0), 0.0, 2.6, 12, detail)
	var a := TAU * h01([seed, "sph"])
	var out := Vector3(cos(a), 0.0, sin(a))
	var side := out.cross(Vector3.UP)
	# A stair up a straight run over the side, landing on the top platform.
	var foot := c + out * (R + 2.5) - side * (R * 1.2)
	var head := centre + out * 2.4 + Vector3(0.0, R * 0.98, 0.0)
	stair(st, foot, head, 0.8, detail)
	tube(st, c + Vector3(0.0, 0.0, 0.0), centre - Vector3(0.0, R, 0.0), 0.3, K_PIPE, PIPE_PAINTS[0], 8)
	lights.append([centre + Vector3(0.0, R + 1.5, 0.0), SODIUM, 1.3, L_FIELD])
	lights.append([c + Vector3(0.0, 1.8, 0.0) + out * R, SODIUM, 1.0, L_FIELD])


## An earth berm (dike) round a rect at ground y: `h` high, sloped both sides.
static func berm(st: SurfaceTool, r: Rect2, y: float, h: float, gaps: Array = []) -> void:
	var top_w := 1.2
	var slope := h * 1.4
	var pts := [Vector2(r.position.x, r.position.y), Vector2(r.end.x, r.position.y), Vector2(r.end.x, r.end.y), Vector2(r.position.x, r.end.y)]
	var centre := r.get_center()
	for k in 4:
		var a: Vector2 = pts[k]
		var b: Vector2 = pts[(k + 1) % 4]
		var dir := (b - a).normalized()
		var out := Vector2(dir.y, -dir.x)
		if out.dot(a - centre) < 0.0:
			out = -out
		var o3 := Vector3(out.x, 0.0, out.y)
		var a3 := Vector3(a.x, y, a.y)
		var b3 := Vector3(b.x, y, b.y)
		# Inner foot, inner top, outer top, outer foot (the corners mitred by extending past them).
		var ext := Vector3(dir.x, 0.0, dir.y) * (slope + top_w)
		var in_f := [a3 - o3 * slope - ext * 0.0, b3 - o3 * slope]
		var in_t := [a3 + Vector3(0.0, h, 0.0), b3 + Vector3(0.0, h, 0.0)]
		var out_t := [a3 + o3 * top_w + Vector3(0.0, h, 0.0), b3 + o3 * top_w + Vector3(0.0, h, 0.0)]
		var out_f := [a3 + o3 * (top_w + slope) - ext, b3 + o3 * (top_w + slope) + ext]
		var l := a.distance_to(b)
		var n_in := (Vector3(0.0, slope, 0.0) - o3 * h).normalized()
		var n_out := (Vector3(0.0, slope, 0.0) + o3 * h).normalized()
		FilmStudioKit.quad(st, in_f[0], in_f[1], in_t[1], in_t[0], n_in, K_EARTH, EARTH, [Vector2(0, 0), Vector2(l, 0), Vector2(l, h), Vector2(0, h)], h)
		FilmStudioKit.quad(st, in_t[0], in_t[1], out_t[1], out_t[0], Vector3.UP, K_EARTH, EARTH, [Vector2(0, 0), Vector2(l, 0), Vector2(l, top_w), Vector2(0, top_w)], h)
		FilmStudioKit.quad(st, out_t[0], out_t[1], out_f[1], out_f[0], n_out, K_EARTH, EARTH, [Vector2(0, h), Vector2(l, h), Vector2(l + 2.0, 0), Vector2(-2.0, 0)], h)
		tris += 6


## A process column (a distillation tower, a stripper, a splitter): a concrete skirt, the
## aluminium-jacketed shell, a head, platforms with rails every 7-9 m, a caged ladder, two vertical
## lines up the side and a davit at the top.
static func column(st: SurfaceTool, foot: Vector3, r: float, h: float, seed: int, detail: bool, lights: Array) -> void:
	var segs := 20 if detail else 10
	shell(st, foot, r + 0.15, 3.2, K_CONCRETE, CONCRETE, segs)
	disc(st, foot + Vector3(0.0, 3.2, 0.0), r + 0.15, K_CONCRETE, CONCRETE, segs, true, r)
	shell(st, foot + Vector3(0.0, 3.2, 0.0), r, h - 3.2, K_ALU, Color.WHITE, segs, false, TAU * r / 4.0)
	roof_cone(st, foot + Vector3(0.0, h, 0.0), r, r * 0.45, K_ALU, Color.WHITE, segs, true)
	var a0 := TAU * h01([seed, "col"])
	var out := Vector3(cos(a0), 0.0, sin(a0))
	var pitch := lerpf(7.0, 9.0, h01([seed, "pitch"]))
	var y := 8.0
	while y < h - 1.0:
		var arc := PI * (1.1 if detail else 2.0)
		ring_deck(st, foot + Vector3(0.0, y, 0.0), r, r + 1.2, 12 if detail else 8, detail, a0 - arc * 0.5, a0 + arc * 0.5)
		lights.append([foot + Vector3(0.0, y + 2.4, 0.0) + out * (r + 1.0), SODIUM if int(y) % 3 != 0 else LED, 1.6, L_FIELD])
		y += pitch
	ring_deck(st, foot + Vector3(0.0, h - 0.1, 0.0), r, r + 1.1, 16 if detail else 10, detail)
	lights.append([foot + Vector3(0.0, h + r * 0.45 + 1.8, 0.0), RED, 1.0, L_FIELD])
	if detail:
		ladder(st, foot + out * (r + 0.55) + Vector3(0.0, 3.2, 0.0), h - 3.0, out)
		var side := out.cross(Vector3.UP)
		for s: float in [1.0, -1.0]:
			var p := foot + (out.rotated(Vector3.UP, s * 0.9)) * (r + 0.55)
			tube(st, p + Vector3(0.0, 2.0, 0.0), p + Vector3(0.0, h - 2.0, 0.0), 0.2 + 0.1 * float(seed % 3), K_ALU, Color.WHITE, 8)
		# The overhead vapour line over the top and down to the rack.
		var top := foot + Vector3(0.0, h + r * 0.4, 0.0)
		var bend := top - out * (r + 1.6) + Vector3(0.0, 1.2, 0.0)
		tube(st, top, bend, 0.35, K_ALU, Color.WHITE, 8)
		tube(st, bend, foot - out * (r + 1.6) + Vector3(0.0, 9.0, 0.0), 0.35, K_ALU, Color.WHITE, 8)
		# The davit.
		var d := foot + Vector3(0.0, h + r * 0.45, 0.0) + side * (r * 0.4)
		beam(st, d, d + Vector3(0.0, 3.0, 0.0), 0.15, 0.15, K_STEEL, SAFETY)
		beam(st, d + Vector3(0.0, 3.0, 0.0), d + Vector3(0.0, 3.0, 0.0) + out * 2.2, 0.12, 0.12, K_STEEL, SAFETY)


## An open steel structure: columns on a `bay` grid, beams round each of `levels` decks every
## `lh` metres, grated decks with handrails, X bracing on its ends, fireproofed column feet, a stair
## tower at one corner, drums and exchangers on the decks. `foot` its south-west corner on the
## ground; `size` (x, z).
static func structure(st: SurfaceTool, foot: Vector3, size: Vector2, levels: int, lh: float, seed: int, paint: Color, detail: bool, lights: Array) -> void:
	var nx := maxi(1, int(round(size.x / 6.5)))
	var nz := maxi(1, int(round(size.y / 6.5)))
	var bx := size.x / float(nx)
	var bz := size.y / float(nz)
	var top := float(levels) * lh
	var cw := 0.36 if detail else 0.5
	for i in nx + 1:
		for j in nz + 1:
			var p := foot + Vector3(bx * float(i), 0.0, bz * float(j))
			if detail:
				block(st, p - Vector3(0.0, 0.2, 0.0), Vector3(0.7, lh + 0.2, 0.7), K_CONCRETE, CONCRETE)
				block(st, p + Vector3(0.0, lh, 0.0), Vector3(cw, top - lh + 1.2, cw), K_STEEL, paint)
			else:
				block(st, p, Vector3(cw, top + 1.2, cw), K_STEEL, paint)
	for lv in levels:
		var y := lh * float(lv + 1)
		var deck_y := foot.y + y
		# Beams along the bays' edges.
		for j in nz + 1:
			beam(st, foot + Vector3(0.0, y - 0.25, bz * float(j)), foot + Vector3(size.x, y - 0.25, bz * float(j)), 0.25, 0.45, K_STEEL, paint)
		for i in nx + 1:
			beam(st, foot + Vector3(bx * float(i), y - 0.25, 0.0), foot + Vector3(bx * float(i), y - 0.25, size.y), 0.25, 0.45, K_STEEL, paint)
		# The deck: a full deck on most levels, a part one (open to the level below) on some.
		var part := (seed + lv) % 3 == 1 and lv > 0
		var dz := size.y * (0.55 if part else 1.0)
		block(st, Vector3(foot.x + size.x * 0.5, deck_y - 0.05, foot.z + dz * 0.5), Vector3(size.x, 0.05, dz), K_GRATE, GREY_STEEL)
		if detail:
			var c0 := Vector3(foot.x, deck_y, foot.z)
			rail(st, c0, c0 + Vector3(size.x, 0.0, 0.0))
			rail(st, c0 + Vector3(0.0, 0.0, dz), c0 + Vector3(size.x, 0.0, dz))
			rail(st, c0, c0 + Vector3(0.0, 0.0, dz))
			rail(st, c0 + Vector3(size.x, 0.0, 0.0), c0 + Vector3(size.x, 0.0, dz))
			# Equipment: a horizontal drum or a pair of exchangers on the deck.
			var k := h01([seed, lv, "eq"])
			var ep := c0 + Vector3(size.x * (0.25 + 0.5 * k), 0.0, dz * 0.5)
			if k < 0.5:
				var dr := minf(1.6, lh * 0.32)
				tube(st, ep + Vector3(-bx * 0.7, dr + 0.6, 0.0), ep + Vector3(bx * 0.7, dr + 0.6, 0.0), dr, K_TANK, TANK_WHITE, 14, true)
				for s: float in [-0.5, 0.5]:
					block(st, ep + Vector3(bx * s, 0.0, 0.0), Vector3(0.4, 0.6 + dr * 0.4, dr * 1.6), K_CONCRETE, CONCRETE)
			else:
				for s: float in [-0.9, 0.9]:
					var q := ep + Vector3(0.0, 1.0, s)
					tube(st, q - Vector3(bx * 0.8, 0.0, 0.0), q + Vector3(bx * 0.8, 0.0, 0.0), 0.5, K_PIPE, PIPE_PAINTS[(seed + lv) % 6], 12, true)
			# Vertical lines from deck to deck.
			for m in 2:
				var vp := foot + Vector3(bx * (float(m) + 0.5), 0.0, -0.4)
				tube(st, vp + Vector3(0.0, y - lh, 0.0), vp + Vector3(0.0, y + 0.8, 0.0), 0.16, K_PIPE, PIPE_PAINTS[(seed + m + lv) % PIPE_PAINTS.size()], 6)
		# Lamps along the deck edges, one a bay or so: these are the "city of lights".
		for i in nx:
			for side: float in [0.0, 1.0]:
				var lp := foot + Vector3(bx * (float(i) + 0.5), y + 2.6, dz * side + (0.3 if side < 0.5 else -0.3))
				var cc := SODIUM if (i + lv + int(side)) % 4 != 0 else LED
				lights.append([lp, cc, 1.7, L_FIELD])
				if detail:
					block(st, lp - Vector3(0.0, 0.2, 0.0), Vector3(0.35, 0.18, 0.35), K_LAMP, Color.WHITE, 0.0 if cc == SODIUM else 1.0)
	# X bracing on the two short ends.
	for lv in levels:
		var y0 := lh * float(lv)
		var y1 := y0 + lh
		for zside: float in [0.0, size.y]:
			beam(st, foot + Vector3(0.0, y0, zside), foot + Vector3(bx, y1, zside), 0.16, 0.16, K_STEEL, paint)
			if detail:
				beam(st, foot + Vector3(bx, y0, zside), foot + Vector3(0.0, y1, zside), 0.16, 0.16, K_STEEL, paint)
	# The stair tower outside the south-west corner, a flight each level.
	var sx := foot + Vector3(-3.2, 0.0, 0.4)
	for k in 4:
		var q := sx + Vector3(2.8 * float(k % 2), 0.0, 4.8 * float(k / 2))
		block(st, q, Vector3(0.22, top + 1.2, 0.22), K_STEEL, SAFETY)
	for lv in levels:
		var y0 := lh * float(lv)
		var y1 := y0 + lh
		var flip := lv % 2 == 1
		var a := sx + Vector3(0.7 if not flip else 2.1, y0, 0.5 if not flip else 4.3)
		var b := sx + Vector3(0.7 if not flip else 2.1, y1, 4.3 if not flip else 0.5)
		stair(st, a, b, 0.9, detail)
		block(st, sx + Vector3(1.4, y1 - 0.06, 4.3 if not flip else 0.5), Vector3(2.8, 0.06, 1.2), K_GRATE, GREY_STEEL)
	lights.append([foot + Vector3(-1.8, top + 2.0, 2.4), SODIUM, 1.2, L_FIELD])


## A pipe rack along a run from a to b at ground y: T bents every `bay` metres, `levels` tiers of
## pipes, a fin-fan air cooler bank over the top on `fans`. Pipes laid as long tubes bay to bay.
static func pipe_rack(st: SurfaceTool, a: Vector3, b: Vector3, width: float, levels: int, seed: int, fans: bool, detail: bool, lights: Array) -> void:
	var run := b - a
	var l := Vector2(run.x, run.z).length()
	if l < 2.0:
		return
	var dir := Vector3(run.x, 0.0, run.z) / l
	var side := dir.cross(Vector3.UP).normalized()
	var bay := 6.0
	var n := maxi(1, int(round(l / bay)))
	var lv_h := 1.9
	var base_h := 5.5
	var top := base_h + lv_h * float(levels - 1)
	for i in n + 1:
		var p := a + dir * (l * float(i) / float(n))
		for s: float in [-0.5, 0.5]:
			var q := p + side * width * s
			if detail:
				block(st, q - Vector3(0.0, 0.2, 0.0), Vector3(0.6, 2.4, 0.6), K_CONCRETE, CONCRETE)
				block(st, q + Vector3(0.0, 2.2, 0.0), Vector3(0.3, top - 1.7, 0.3), K_STEEL, GREY_STEEL)
			else:
				block(st, q, Vector3(0.45, top + 0.5, 0.45), K_STEEL, GREY_STEEL)
		for lv in levels:
			var y := base_h + lv_h * float(lv)
			beam(st, p - side * width * 0.5 + Vector3(0.0, y, 0.0), p + side * width * 0.5 + Vector3(0.0, y, 0.0), 0.25, 0.3, K_STEEL, GREY_STEEL, dir)
		if i % 2 == 0:
			lights.append([p + side * width * 0.5 + Vector3(0.0, top + 0.6, 0.0), SODIUM, 1.0, L_FIELD])
	# Longitudinal ties at the top on the far level.
	for s: float in [-0.5, 0.5]:
		beam(st, a + side * width * s + Vector3(0.0, top, 0.0), b + side * width * s + Vector3(0.0, top, 0.0), 0.2, 0.3, K_STEEL, GREY_STEEL)
	# The pipes: per tier, a row across the width, their sizes and colours by hash.
	for lv in levels:
		var y := base_h + lv_h * float(lv) + 0.15
		var x := -width * 0.5 + 0.35
		var k := 0
		while x < width * 0.5 - 0.3:
			var rr := lerpf(0.09, 0.42, pow(h01([seed, lv, k]), 1.8))
			if not detail and rr < 0.22:
				x += rr * 2.0 + 0.2
				k += 1
				continue
			var paint: Color = PIPE_PAINTS[int(h01([seed, lv, k, "c"]) * PIPE_PAINTS.size()) % PIPE_PAINTS.size()]
			var kind := K_ALU if paint == PIPE_PAINTS[3] else K_PIPE
			var off := side * (x + rr) + Vector3(0.0, y + rr, 0.0)
			tube(st, a + off, b + off, rr, kind, paint, (8 if rr > 0.2 else 6) if detail else 6)
			x += rr * 2.0 + 0.16
			k += 1
	if fans:
		# A fin-fan bank: plenum boxes with a fan ring each over the rack, a walkway along its side.
		var fy := top + 0.6
		var nf := maxi(1, int(l / 7.0))
		for i in nf:
			var p := a + dir * (l * (float(i) + 0.5) / float(nf)) + Vector3(0.0, fy, 0.0)
			box(st, Transform3D(Basis(side, Vector3.UP, dir), p + Vector3(0.0, 1.0, 0.0)), Vector3(width, 2.0, l / float(nf) - 0.3), K_CLAD, Color(0.62, 0.62, 0.6))
			box(st, Transform3D(Basis(side, Vector3.UP, dir), p + Vector3(0.0, 2.15, 0.0)), Vector3(width, 0.3, l / float(nf) - 0.3), K_DARK, Color(0.3, 0.3, 0.3))
			for s: float in [-0.25, 0.25]:
				shell(st, p + side * width * s + Vector3(0.0, 2.0, 0.0), minf(width * 0.22, 2.6), 0.9, K_STEEL, GREY_STEEL, 12 if detail else 8)
				disc(st, p + side * width * s + Vector3(0.0, 2.6, 0.0), minf(width * 0.22, 2.6), K_DARK, Color(0.25, 0.25, 0.25), 12 if detail else 8)
		if detail:
			rail(st, a + side * (width * 0.5 + 0.8) + Vector3(0.0, fy, 0.0), b + side * (width * 0.5 + 0.8) + Vector3(0.0, fy, 0.0))
			beam(st, a + side * (width * 0.5 + 0.4) + Vector3(0.0, fy - 0.05, 0.0), b + side * (width * 0.5 + 0.4) + Vector3(0.0, fy - 0.05, 0.0), 0.9, 0.06, K_GRATE, GREY_STEEL)


## A fired heater: a box firebox on legs with peep doors, a convection section over it, the stack.
static func heater(st: SurfaceTool, foot: Vector3, size: Vector3, stack_h: float, seed: int, detail: bool, lights: Array) -> void:
	for i in 2:
		for j in 2:
			var p := foot + Vector3((float(i) - 0.5) * (size.x - 1.0), 0.0, (float(j) - 0.5) * (size.z - 1.0))
			block(st, p, Vector3(0.6, 3.0, 0.6), K_CONCRETE, CONCRETE)
	block(st, foot + Vector3(0.0, 3.0, 0.0), size, K_HOT, Color(0.42, 0.4, 0.38), 0.0)
	var conv := Vector3(size.x * 0.75, size.y * 0.45, size.z * 0.65)
	block(st, foot + Vector3(0.0, 3.0 + size.y, 0.0), conv, K_STEEL, Color(0.38, 0.37, 0.35))
	var sr := minf(size.x, size.z) * 0.16 + 0.6
	tube(st, foot + Vector3(0.0, 3.0 + size.y + conv.y, 0.0), foot + Vector3(0.0, stack_h - 4.0, 0.0), sr, K_STEEL, Color(0.5, 0.5, 0.48), 12 if detail else 8, false, 0.0, sr * 0.92)
	tube(st, foot + Vector3(0.0, stack_h - 4.0, 0.0), foot + Vector3(0.0, stack_h, 0.0), sr * 0.92, K_SOOT, Color(0.1, 0.1, 0.1), 12 if detail else 8)
	ring_deck(st, foot + Vector3(0.0, stack_h - 6.0, 0.0), sr * 0.95, sr + 1.0, 10, detail)
	if detail:
		for s: float in [-1.0, 1.0]:
			var y := 3.0 + size.y * 0.45
			var c0 := foot + Vector3(-size.x * 0.5, y, s * (size.z * 0.5 + 1.0))
			block(st, foot + Vector3(0.0, y - 0.05, s * (size.z * 0.5 + 0.6)), Vector3(size.x, 0.05, 1.2), K_GRATE, GREY_STEEL)
			rail(st, c0, c0 + Vector3(size.x, 0.0, 0.0))
		ladder(st, foot + Vector3(sr + 0.5, 3.0 + size.y + conv.y, 0.0), stack_h - 6.0 - (3.0 + size.y + conv.y), Vector3.RIGHT)
	lights.append([foot + Vector3(0.0, stack_h + 0.8, 0.0), RED, 1.2, L_FIELD])
	lights.append([foot + Vector3(size.x * 0.5 + 0.5, 3.0 + size.y * 0.45 + 2.2, 0.0), SODIUM, 1.1, L_FIELD])


## A mechanical-draft cooling tower: a concrete basin, louvred walls, the fan deck with a fan stack
## a cell, rails; `cells` along x. Returns the stacks' tops (for the steam).
static func cooling_tower(st: SurfaceTool, foot: Vector3, cells: int, cell: float, depth: float, h: float, detail: bool, lights: Array) -> Array:
	var w := cell * float(cells)
	block(st, foot + Vector3(0.0, -0.2, 0.0), Vector3(w + 2.0, 1.4, depth + 2.0), K_CONCRETE, CONCRETE)
	block(st, foot + Vector3(0.0, 1.2, 0.0), Vector3(w, h - 1.2, depth), K_LOUVRE, Color(0.5, 0.53, 0.52))
	block(st, foot + Vector3(0.0, h, 0.0), Vector3(w + 0.4, 0.3, depth + 0.4), K_STEEL, Color(0.45, 0.47, 0.46))
	var tops: Array = []
	var fr := minf(cell, depth) * 0.36
	for i in cells:
		var c := foot + Vector3(-w * 0.5 + cell * (float(i) + 0.5), h + 0.3, 0.0)
		shell(st, c, fr, 3.4, K_CLAD, Color(0.58, 0.6, 0.58), 20 if detail else 10)
		shell(st, c, fr - 0.1, 3.4, K_DARK, Color(0.2, 0.2, 0.2), 20 if detail else 10, true)
		disc(st, c + Vector3(0.0, 1.6, 0.0), fr - 0.1, K_DARK, Color(0.12, 0.12, 0.12), 12)
		tops.append(c + Vector3(0.0, 3.4, 0.0))
		lights.append([c + Vector3(fr + 0.6, 1.4, depth * 0.4), SODIUM, 1.0, L_FIELD])
	if detail:
		var c0 := foot + Vector3(-w * 0.5, h + 0.3, -depth * 0.5)
		rail(st, c0, c0 + Vector3(w, 0.0, 0.0))
		rail(st, c0 + Vector3(0.0, 0.0, depth), c0 + Vector3(w, 0.0, depth))
		stair(st, foot + Vector3(w * 0.5 + 1.2, 0.0, -depth * 0.5 + 0.5), foot + Vector3(w * 0.5 + 1.2, h + 0.3, depth * 0.5 - 0.5), 0.9, detail)
	return tops


## A flare stack: a riser in red and white bands inside a three-legged lattice derrick, the tip
## sooted, a platform under it, red aviation lights. Returns the tip's position (the flame).
static func flare(st: SurfaceTool, foot: Vector3, h: float, seed: int, detail: bool, lights: Array) -> Vector3:
	var rr := 0.9
	block(st, foot - Vector3(0.0, 0.3, 0.0), Vector3(14.0, 0.8, 14.0), K_CONCRETE, CONCRETE)
	tube(st, foot, foot + Vector3(0.0, h - 3.0, 0.0), rr, K_BANDS, Color.WHITE, 12 if detail else 8, false, 7.0)
	tube(st, foot + Vector3(0.0, h - 3.0, 0.0), foot + Vector3(0.0, h, 0.0), rr * 1.15, K_SOOT, Color.WHITE, 12 if detail else 8)
	# The derrick: three legs from a 12 m triangle at the foot to a 3 m one under the tip, braced.
	var legs: Array = []
	for k in 3:
		var a := TAU * float(k) / 3.0 + 0.4
		legs.append(Vector2(cos(a), sin(a)))
	var levels := int(h / 8.0)
	for k in 3:
		var d0: Vector2 = legs[k]
		var d1: Vector2 = legs[(k + 1) % 3]
		var b0 := foot + Vector3(d0.x, 0.0, d0.y) * 6.5
		var t0 := foot + Vector3(d0.x, 0.0, d0.y) * 1.8 + Vector3(0.0, h - 4.0, 0.0)
		tube(st, b0, t0, 0.32, K_BANDS, Color.WHITE, 6, false, 7.0)
		for lv in levels:
			var f0 := float(lv) / float(levels)
			var f1 := float(lv + 1) / float(levels)
			var p0 := b0.lerp(t0, f0)
			var p1 := b0.lerp(t0, f1)
			var b1 := foot + Vector3(d1.x, 0.0, d1.y) * 6.5
			var t1 := foot + Vector3(d1.x, 0.0, d1.y) * 1.8 + Vector3(0.0, h - 4.0, 0.0)
			var q0 := b1.lerp(t1, f0)
			var q1 := b1.lerp(t1, f1)
			beam(st, p1, q1, 0.12, 0.12, K_STEEL, Color(0.82, 0.8, 0.77))
			if detail or lv % 2 == 0:
				beam(st, p0, q1, 0.1, 0.1, K_STEEL, Color(0.82, 0.8, 0.77))
	ring_deck(st, foot + Vector3(0.0, h - 4.0, 0.0), rr, 3.0, 12, detail)
	if detail:
		ladder(st, foot + Vector3(rr + 0.5, 1.0, 0.0), h - 5.0, Vector3.RIGHT)
	for lv in [0.33, 0.66, 1.0]:
		var y := (h - 4.0) * float(lv) + 1.0
		for k in 3:
			var d: Vector2 = legs[k]
			var p := foot + Vector3(d.x, 0.0, d.y) * lerpf(6.5, 1.8, float(lv)) + Vector3(0.0, y, 0.0)
			lights.append([p, RED, 1.6, L_FIELD])
	return foot + Vector3(0.0, h, 0.0)


## A low building (control room, lab, warehouse, gatehouse): ribbed siding, a glass band, a flat
## roof with a parapet and units. `size` x, y, z; the glass on the +z face (and -z when `both`).
static func building(st: SurfaceTool, foot: Vector3, size: Vector3, paint: Color, glass: bool, both: bool, detail: bool, lights: Array) -> void:
	block(st, foot, size, K_CLAD, paint)
	block(st, foot + Vector3(0.0, size.y, 0.0), Vector3(size.x + 0.2, 0.5, size.z + 0.2), K_STEEL, paint * 0.8)
	if glass:
		var gh := minf(size.y * 0.42, 2.0)
		var nfl := maxi(1, int(size.y / 3.8))
		for f in nfl:
			for s: float in ([1.0, -1.0] if both else [1.0]):
				var gy := foot.y + 1.2 + 3.8 * float(f)
				box(st, Transform3D(Basis(), Vector3(foot.x, gy + gh * 0.5, foot.z + s * (size.z * 0.5 + 0.03))), Vector3(size.x - 1.0, gh, 0.06), K_GLASS, Color.WHITE, 1.5)
	if detail:
		for k in 2:
			block(st, foot + Vector3((float(k) - 0.5) * size.x * 0.4, size.y + 0.5, 0.0), Vector3(2.4, 1.4, 1.8), K_CLAD, Color(0.7, 0.7, 0.68))
	lights.append([foot + Vector3(0.0, size.y - 0.6, size.z * 0.5 + 0.5), LED, 1.0, L_FIELD])
	lights.append([foot + Vector3(size.x * 0.5 - 0.5, size.y - 0.6, size.z * 0.5 + 0.5), SODIUM, 0.9, L_FIELD])


## A high-mast floodlight: a tapered pole and a ring of lamps; the lights only (the pole is cheap).
static func mast(st: SurfaceTool, foot: Vector3, h: float, detail: bool, lights: Array) -> void:
	tube(st, foot, foot + Vector3(0.0, h, 0.0), 0.35, K_STEEL, Color(0.6, 0.61, 0.6), 8 if detail else 5, false, 0.0, 0.18)
	var ring := foot + Vector3(0.0, h, 0.0)
	if detail:
		shell(st, ring - Vector3(0.0, 0.4, 0.0), 1.2, 0.4, K_STEEL, Color(0.5, 0.5, 0.5), 10)
	for k in 6:
		var a := TAU * float(k) / 6.0
		var p := ring + Vector3(cos(a) * 1.2, -0.5, sin(a) * 1.2)
		if detail:
			block(st, p, Vector3(0.6, 0.35, 0.6), K_LAMP, Color.WHITE, 0.0)
		lights.append([p, SODIUM, 2.4, L_FIELD])
