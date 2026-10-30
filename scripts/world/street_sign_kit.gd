class_name StreetSignKit
extends RefCounted
## The street's signs as real geometry (StreetSigns places them): aluminium plates at their real
## sizes and thicknesses with rounded corners, the sheeting's border and legend raised a few
## millimetres off the face (the legend drawn with SignFont's strokes), mill-finish backs with
## their bolts, round galvanised posts with clamp bands, the flat-blade cap bracket that carries
## two street-name blades crossed at the top of a post, and the strap brackets that hang a sign
## on a signal's mast arm. Every assembly is ONE mesh with one material
## (`shaders/street_sign.gdshader`), its origin at the foot of its post on the pavement (or on
## the mast arm's axis), its main face toward +Z; cached by key, so a street's blades are one
## mesh wherever they stand.
##
## What a vertex is rides in its colour's alpha (kind / KIND_SCALE), its colour sRGB in the rgb:
## K_SHEET retroreflective sheeting (the face, its border and legend: lit back toward the camera's
## "headlights" at night), K_BACK the plates' bare aluminium, K_GALV the posts, K_HW clamps,
## bolts and brackets, K_INK a black legend (printed on, not reflective). UV is the face's own
## metres (sheeting texture, grime, wear).

const KIND_SCALE := 16.0
const K_SHEET := 1
const K_BACK := 2
const K_GALV := 3
const K_HW := 4
const K_INK := 5

## Plate thickness (0.08 in aluminium) and how far each layer of sheeting stands proud of the one
## under it. A few millimetres: nothing at sign scale, but well clear of the depth buffer's
## precision a street away (coplanar layers z-fight on the web's 24-bit depth).
const PLATE_T := 0.0032
const LAYER := 0.0016

## Post: 2-3/8 in round galvanised tube.
const POST_R := 0.030
const POST_SIDES := 12

## Colours (sRGB): MUTCD-ish sheeting tones.
const GREEN := Color(0.0, 0.40, 0.25)
const WHITE := Color(0.93, 0.93, 0.91)
const RED := Color(0.72, 0.06, 0.08)
const BLACK := Color(0.03, 0.03, 0.03)
const YGREEN := Color(0.70, 0.86, 0.10)
const ALU := Color(0.66, 0.67, 0.68)
const GALV := Color(0.60, 0.61, 0.60)
const STEEL := Color(0.30, 0.30, 0.31)

## Street-name blade (LA's flat blades): 9 in tall, 6 in capitals, the hundred-block number small
## at the left end. Mast-arm name signs: 18 in tall, 8 in capitals.
const BLADE_H := 0.23
const BLADE_CAP := 0.135
const BLADE_T := 0.005
const ARM_SIGN_H := 0.46
const ARM_SIGN_CAP := 0.2
## How far in front of the mast arm's axis an arm sign's face hangs (metres).
const ARM_STANDOFF := 0.17

static var _cache: Dictionary = {}
static var _material: ShaderMaterial


static func material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = load("res://shaders/street_sign.gdshader")
	return _material


# --- Geometry accumulator ----------------------------------------------------------------------

class Geo:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var uv := PackedVector2Array()
	## The frame everything is written in (a plate's face frame, a post's foot).
	var xf := Transform3D.IDENTITY

	## One triangle in the current frame, wound so its front faces `want` (frame space).
	func tri(a: Vector3, b: Vector3, d: Vector3, want: Vector3, col: Color, kind: int, ua := Vector2.ZERO, ub := Vector2.ZERO, ud := Vector2.ZERO) -> void:
		var wa := xf * a
		var wb := xf * b
		var wd := xf * d
		var ww := (xf.basis * want).normalized()
		var nn := (wd - wa).cross(wb - wa)
		if nn.length_squared() < 1e-14:
			return
		if nn.dot(ww) < 0.0:
			var t := wb
			wb = wd
			wd = t
			var tu := ub
			ub = ud
			ud = tu
		var cc := Color(col.r, col.g, col.b, float(kind) / KIND_SCALE)
		v.append_array([wa, wb, wd])
		n.append_array([ww, ww, ww])
		c.append_array([cc, cc, cc])
		uv.append_array([ua, ub, ud])

	func quad(a: Vector3, b: Vector3, d: Vector3, e: Vector3, want: Vector3, col: Color, kind: int) -> void:
		tri(a, b, d, want, col, kind, Vector2(a.x, a.y), Vector2(b.x, b.y), Vector2(d.x, d.y))
		tri(a, d, e, want, col, kind, Vector2(a.x, a.y), Vector2(d.x, d.y), Vector2(e.x, e.y))

	func mesh() -> ArrayMesh:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = v
		arrays[Mesh.ARRAY_NORMAL] = n
		arrays[Mesh.ARRAY_COLOR] = c
		arrays[Mesh.ARRAY_TEX_UV] = uv
		var m := ArrayMesh.new()
		if v.size() > 0:
			m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			m.surface_set_material(0, StreetSignKit.material())
		return m


# --- 2D shapes (counter-clockwise, metres, centred) ----------------------------------------------

static func rect_poly(w: float, h: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(-w * 0.5, -h * 0.5), Vector2(w * 0.5, -h * 0.5), Vector2(w * 0.5, h * 0.5), Vector2(-w * 0.5, h * 0.5)])


## A regular octagon `w` across the flats, flats horizontal and vertical.
static func octagon(w: float) -> PackedVector2Array:
	var r := w * 0.5 / cos(PI / 8.0)
	var p := PackedVector2Array()
	for k in 8:
		var a := PI / 8.0 + k * PI / 4.0
		p.append(Vector2(cos(a), sin(a)) * r)
	return p


## An equilateral-ish triangle `w` wide and `h` tall, point down (the yield sign).
static func tri_down(w: float, h: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(0.0, -h * 0.5), Vector2(w * 0.5, h * 0.5), Vector2(-w * 0.5, h * 0.5)])


## The school sign's pentagon: a rectangle with a gable on top.
static func pentagon(w: float, h: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(-w * 0.5, -h * 0.5), Vector2(w * 0.5, -h * 0.5), Vector2(w * 0.5, h * 0.06), Vector2(0.0, h * 0.5), Vector2(-w * 0.5, h * 0.06)])


## A convex polygon moved `d` inward along every edge (negative d grows it).
static func inset(poly: PackedVector2Array, d: float) -> PackedVector2Array:
	var n := poly.size()
	var out := PackedVector2Array()
	for i in n:
		var p0 := poly[(i - 1 + n) % n]
		var p1 := poly[i]
		var p2 := poly[(i + 1) % n]
		var e0 := (p1 - p0).normalized()
		var e1 := (p2 - p1).normalized()
		var n0 := Vector2(-e0.y, e0.x)
		var n1 := Vector2(-e1.y, e1.x)
		var bis := (n0 + n1).normalized()
		out.append(p1 + bis * d / maxf(bis.dot(n0), 0.2))
	return out


## A convex polygon with every corner rounded to radius `r` (`seg` segments a corner), so an
## outline and its inset have the same number of points and can be joined as a ring.
static func rounded(poly: PackedVector2Array, r: float, seg: int = 4) -> PackedVector2Array:
	var n := poly.size()
	var out := PackedVector2Array()
	for i in n:
		var p0 := poly[(i - 1 + n) % n]
		var p1 := poly[i]
		var p2 := poly[(i + 1) % n]
		var e0 := (p1 - p0).normalized()
		var e1 := (p2 - p1).normalized()
		var n0 := Vector2(-e0.y, e0.x)
		var n1 := Vector2(-e1.y, e1.x)
		var bis := (n0 + n1).normalized()
		var centre := p1 + bis * r / maxf(bis.dot(n0), 0.2)
		var a0 := (-n0).angle()
		var a1 := (-n1).angle()
		if a1 < a0:
			a1 += TAU
		for k in seg + 1:
			var a := lerpf(a0, a1, float(k) / seg)
			out.append(centre + Vector2(cos(a), sin(a)) * r)
	return out


# --- Plates, rings, legends --------------------------------------------------------------------

## A plate of outline `poly` in the current frame's XY plane, its front at z = +t/2 in sheeting
## of `col`, its back and edge bare aluminium.
static func plate(g: Geo, poly: PackedVector2Array, col: Color, t: float = PLATE_T, back_col: Color = ALU, back_kind: int = K_BACK) -> void:
	var idx := Geometry2D.triangulate_polygon(poly)
	var zf := t * 0.5
	for i in range(0, idx.size(), 3):
		var a := poly[idx[i]]
		var b := poly[idx[i + 1]]
		var d := poly[idx[i + 2]]
		g.tri(Vector3(a.x, a.y, zf), Vector3(b.x, b.y, zf), Vector3(d.x, d.y, zf), Vector3.BACK, col, K_SHEET, a, b, d)
		g.tri(Vector3(a.x, a.y, -zf), Vector3(b.x, b.y, -zf), Vector3(d.x, d.y, -zf), Vector3.FORWARD, back_col, back_kind, a, b, d)
	var n := poly.size()
	for i in n:
		var a := poly[i]
		var b := poly[(i + 1) % n]
		var e := b - a
		var out := Vector3(e.y, -e.x, 0.0).normalized()
		g.quad(Vector3(a.x, a.y, zf), Vector3(b.x, b.y, zf), Vector3(b.x, b.y, -zf), Vector3(a.x, a.y, -zf), out, back_col, back_kind)


## A flat polygon of sheeting at height z on the face (a field of another colour, a filled shape).
static func fill(g: Geo, poly: PackedVector2Array, z: float, col: Color, kind: int = K_SHEET, facing: float = 1.0) -> void:
	var idx := Geometry2D.triangulate_polygon(poly)
	for i in range(0, idx.size(), 3):
		var a := poly[idx[i]]
		var b := poly[idx[i + 1]]
		var d := poly[idx[i + 2]]
		g.tri(Vector3(a.x, a.y, z), Vector3(b.x, b.y, z), Vector3(d.x, d.y, z), Vector3(0.0, 0.0, facing), col, kind, a, b, d)


## The band between two outlines of the same point count (a border), at height z.
static func ring(g: Geo, outer: PackedVector2Array, inner: PackedVector2Array, z: float, col: Color, facing: float = 1.0) -> void:
	var n := outer.size()
	for i in n:
		var j := (i + 1) % n
		g.quad(Vector3(outer[i].x, outer[i].y, z), Vector3(outer[j].x, outer[j].y, z), Vector3(inner[j].x, inner[j].y, z), Vector3(inner[i].x, inner[i].y, z), Vector3(0.0, 0.0, facing), col, K_SHEET)


## Strokes (polylines in face metres) drawn as ribbons `pen` wide at height z, mitred at their
## joints (a mitre longer than twice the pen is cut back), square at their ends.
static func strokes(g: Geo, lines: Array, pen: float, z: float, col: Color, kind: int = K_SHEET, facing: float = 1.0) -> void:
	var hw := pen * 0.5
	var want := Vector3(0.0, 0.0, facing)
	for line: PackedVector2Array in lines:
		var pts := line
		var closed := pts.size() > 2 and pts[0].distance_to(pts[pts.size() - 1]) < 0.0005
		if closed:
			pts = pts.slice(0, pts.size() - 1)
		var m := pts.size()
		if m < 2:
			# A dot (a full stop): a square pen mark.
			if m == 1:
				var p := pts[0]
				g.quad(Vector3(p.x - hw, p.y - hw, z), Vector3(p.x + hw, p.y - hw, z), Vector3(p.x + hw, p.y + hw, z), Vector3(p.x - hw, p.y + hw, z), want, col, kind)
			continue
		var left := PackedVector2Array()
		var right := PackedVector2Array()
		for i in m:
			var has_prev := closed or i > 0
			var has_next := closed or i < m - 1
			var d0 := (pts[i] - pts[(i - 1 + m) % m]).normalized() if has_prev else Vector2.ZERO
			var d1 := (pts[(i + 1) % m] - pts[i]).normalized() if has_next else Vector2.ZERO
			var p := pts[i]
			if not has_prev:
				d0 = d1
			if not has_next:
				d1 = d0
			var n0 := Vector2(-d0.y, d0.x)
			var n1 := Vector2(-d1.y, d1.x)
			var bis := n0 + n1
			if bis.length_squared() < 1e-6:
				bis = n0
			bis = bis.normalized()
			var len_m := hw / maxf(bis.dot(n0), 0.5)
			# A pen's square terminals: the ends run on by a third of the pen, so a stroke
			# meeting another reads as joined and an I's foot sits on the baseline.
			if not has_prev and i == 0:
				p -= d1 * hw * 0.35
			if not has_next and i == m - 1:
				p += d0 * hw * 0.35
			left.append(p + bis * len_m)
			right.append(p - bis * len_m)
		var segs := m if closed else m - 1
		for i in segs:
			var j := (i + 1) % m
			g.quad(Vector3(left[i].x, left[i].y, z), Vector3(left[j].x, left[j].y, z), Vector3(right[j].x, right[j].y, z), Vector3(right[i].x, right[i].y, z), want, col, kind)


## `text` laid out at cap height `cap` (pen cap / 6.5), centred on (cx, cy) with its baseline at
## cy - cap / 2, squeezed sideways to fit `max_w`. Mirrored for a back face (facing -1), so it
## reads from behind.
static func text(g: Geo, s: String, cap: float, cx: float, cy: float, max_w: float, z: float, col: Color, facing: float = 1.0, kind: int = K_SHEET) -> float:
	var pen := cap / 6.5
	var lay := SignFont.layout(s, cap, pen)
	var w: float = lay[1]
	var squeeze := minf(1.0, max_w / maxf(w, 0.001))
	var x0 := cx - w * squeeze * 0.5
	var lines: Array = []
	for line: PackedVector2Array in lay[0]:
		var p := PackedVector2Array()
		for v in line:
			var x := x0 + v.x * squeeze
			if facing < 0.0:
				x = 2.0 * cx - x
			p.append(Vector2(x, cy - cap * 0.5 + v.y))
		lines.append(p)
	strokes(g, lines, pen * lerpf(1.0, squeeze, 0.4), z, col, kind, facing)
	return w * squeeze


## The front (and, for a two-sided sign, the back) of a sheeted face: plate, border, legend
## callback. `legend` is called with (g, z, facing) for each sheeted side.
static func face(g: Geo, poly: PackedVector2Array, field: Color, border: Color, border_in: float, border_w: float, legend: Callable, two_sided: bool = false, t: float = PLATE_T) -> void:
	if two_sided:
		plate(g, poly, field, t, field, K_SHEET)
	else:
		plate(g, poly, field, t)
	for side: float in ([1.0, -1.0] if two_sided else [1.0]):
		var z := t * 0.5 * side
		if border_w > 0.0:
			var outer := inset(poly, border_in)
			var inner := inset(poly, border_in + border_w)
			ring(g, outer, inner, z + LAYER * side, border, side)
		if legend.is_valid():
			legend.call(g, z + LAYER * 2.0 * side, side)


# --- Hardware ----------------------------------------------------------------------------------

## An upright cylinder (radius r, y0..y1) at (x, z) in the current frame.
static func cylinder(g: Geo, x: float, z: float, r: float, y0: float, y1: float, col: Color, kind: int, sides: int = POST_SIDES, cap: bool = true) -> void:
	for i in sides:
		var a0 := TAU * i / sides
		var a1 := TAU * (i + 1) / sides
		var p0 := Vector3(x + cos(a0) * r, 0.0, z + sin(a0) * r)
		var p1 := Vector3(x + cos(a1) * r, 0.0, z + sin(a1) * r)
		var out := Vector3(cos((a0 + a1) * 0.5), 0.0, sin((a0 + a1) * 0.5))
		var ua := Vector2(r * a0, y0)
		var ub := Vector2(r * a1, y0)
		g.tri(Vector3(p0.x, y0, p0.z), Vector3(p1.x, y0, p1.z), Vector3(p1.x, y1, p1.z), out, col, kind, ua, ub, Vector2(r * a1, y1))
		g.tri(Vector3(p0.x, y0, p0.z), Vector3(p1.x, y1, p1.z), Vector3(p0.x, y1, p0.z), out, col, kind, ua, Vector2(r * a1, y1), Vector2(r * a0, y1))
		if cap:
			g.tri(Vector3(x, y1, z), Vector3(p0.x, y1, p0.z), Vector3(p1.x, y1, p1.z), Vector3.UP, col, kind)


## A box centred on `c` (current frame) with half extents `h`.
static func box(g: Geo, c: Vector3, h: Vector3, col: Color, kind: int) -> void:
	var faces := [
		[Vector3.RIGHT, Vector3.UP, Vector3.BACK], [Vector3.LEFT, Vector3.UP, Vector3.FORWARD],
		[Vector3.UP, Vector3.BACK, Vector3.RIGHT], [Vector3.DOWN, Vector3.FORWARD, Vector3.RIGHT],
		[Vector3.BACK, Vector3.UP, Vector3.LEFT], [Vector3.FORWARD, Vector3.UP, Vector3.RIGHT],
	]
	for f: Array in faces:
		var nrm: Vector3 = f[0]
		var u: Vector3 = f[1]
		var w: Vector3 = f[2]
		var fc := c + nrm * h
		var uu := u * h
		var ww := w * h
		g.quad(fc - uu - ww, fc - uu + ww, fc + uu + ww, fc + uu - ww, nrm, col, kind)


## The post, from the pavement to `top`: a sleeve at the foot (the anchor it is bolted into).
static func post(g: Geo, top: float) -> void:
	g.xf = Transform3D.IDENTITY
	cylinder(g, 0.0, 0.0, POST_R + 0.008, 0.0, 0.10, GALV.darkened(0.2), K_GALV, POST_SIDES, true)
	cylinder(g, 0.0, 0.0, POST_R, 0.10, top, GALV, K_GALV)


## A sign mounted on the post's +Z side with its centre at height `y`: two clamp bands, the
## bracket, then the plate (callback `build` writes it in the plate's own frame, centred, face +Z).
## `half_h` is the plate's half height (the bands go a little inside its top and bottom).
static func mount(g: Geo, y: float, half_h: float, build: Callable, yaw: float = 0.0) -> void:
	var basis := Basis(Vector3.UP, yaw)
	g.xf = Transform3D(basis, Vector3.ZERO)
	for k: float in [-0.6, 0.6]:
		var by := y + half_h * k
		cylinder(g, 0.0, 0.0, POST_R + 0.005, by - 0.02, by + 0.02, STEEL, K_HW, 10, false)
		box(g, Vector3(0.0, by, POST_R + 0.008), Vector3(0.022, 0.018, 0.008), STEEL, K_HW)
	g.xf = Transform3D(basis, Vector3(0.0, y, POST_R + 0.016 + PLATE_T * 0.5))
	build.call(g)
	# Bolt heads on the face where the bands hold it (sheeting-coloured caps, as real ones are).
	g.xf = Transform3D.IDENTITY


# --- Sign faces (each in its plate's own frame, centred, face +Z) ---------------------------------

static func _stop_face(g: Geo) -> void:
	var w := 0.762
	var o := rounded(octagon(w - 0.004), 0.02, 3)
	face(g, o, RED, WHITE, 0.012, 0.02, func(gg: Geo, z: float, s: float) -> void:
		text(gg, "STOP", 0.25, 0.0, 0.0, 0.56, z, WHITE, s))
	_bolts(g, 0.762 * 0.5 - 0.06)


static func _all_way_face(g: Geo) -> void:
	var o := rounded(rect_poly(0.46, 0.15), 0.015, 3)
	face(g, o, RED, WHITE, 0.006, 0.008, func(gg: Geo, z: float, s: float) -> void:
		text(gg, "ALL WAY", 0.075, 0.0, 0.0, 0.38, z, WHITE, s))


static func _yield_face(g: Geo) -> void:
	var tri := rounded(tri_down(0.914, 0.792), 0.03, 3)
	plate(g, tri, RED)
	var z := PLATE_T * 0.5
	var field := rounded(inset(tri_down(0.914, 0.792), 0.12), 0.012, 3)
	fill(g, field, z + LAYER, WHITE)
	text(g, "YIELD", 0.1, 0.0, 0.2, 0.34, z + LAYER * 2.0, RED)
	_bolts(g, 0.2)


static func _speed_face(g: Geo, mph: int) -> void:
	var o := rounded(rect_poly(0.61, 0.76), 0.035, 3)
	face(g, o, WHITE, BLACK, 0.012, 0.016, func(gg: Geo, z: float, s: float) -> void:
		text(gg, "SPEED", 0.1, 0.0, 0.25, 0.45, z, BLACK, s, K_INK)
		text(gg, "LIMIT", 0.1, 0.0, 0.1, 0.45, z, BLACK, s, K_INK)
		text(gg, str(mph), 0.26, 0.0, -0.15, 0.48, z, BLACK, s, K_INK))
	_bolts(g, 0.3)


## LA's red-on-white no-parking plate, with the arrow toward the junction it guards.
static func _no_parking_face(g: Geo) -> void:
	var o := rounded(rect_poly(0.305, 0.457), 0.02, 3)
	face(g, o, WHITE, RED, 0.008, 0.01, func(gg: Geo, z: float, s: float) -> void:
		text(gg, "NO", 0.06, 0.0, 0.165, 0.24, z, RED, s)
		text(gg, "PARKING", 0.045, 0.0, 0.085, 0.25, z, RED, s)
		text(gg, "ANY TIME", 0.04, 0.0, 0.015, 0.25, z, RED, s)
		_arrow(gg, Vector2(0.0, -0.07), Vector2(1.0, 0.0), 0.2, 0.022, z, RED, s)
		text(gg, "TOW-AWAY", 0.032, 0.0, -0.15, 0.24, z, RED, s), true)
	_bolts(g, 0.17)


## The school-crossing pentagon (fluorescent yellow-green): two walking figures.
static func _school_face(g: Geo) -> void:
	var p := pentagon(0.762, 0.762)
	face(g, rounded(p, 0.03, 3), YGREEN, BLACK, 0.012, 0.016, func(gg: Geo, z: float, s: float) -> void:
		_figure(gg, Vector2(-0.09 * s, -0.06), 0.36, z, s, 0.0)
		_figure(gg, Vector2(0.1 * s, -0.09), 0.30, z, s, 1.0))
	_bolts(g, 0.28)


static func _school_speed_face(g: Geo) -> void:
	var o := rounded(rect_poly(0.61, 1.0), 0.03, 3)
	face(g, o, WHITE, BLACK, 0.012, 0.014, func(gg: Geo, z: float, s: float) -> void:
		fill(gg, _offset(rounded(rect_poly(0.55, 0.17), 0.012, 3), Vector2(0.0, 0.385)), z, YGREEN, K_SHEET, s)
		text(gg, "SCHOOL", 0.1, 0.0, 0.385, 0.46, z + LAYER, BLACK, s, K_INK)
		text(gg, "SPEED", 0.075, 0.0, 0.215, 0.45, z, BLACK, s, K_INK)
		text(gg, "LIMIT", 0.075, 0.0, 0.11, 0.45, z, BLACK, s, K_INK)
		text(gg, "25", 0.2, 0.0, -0.08, 0.45, z, BLACK, s, K_INK)
		text(gg, "WHEN CHILDREN", 0.045, 0.0, -0.285, 0.5, z, BLACK, s, K_INK)
		text(gg, "ARE PRESENT", 0.045, 0.0, -0.375, 0.5, z, BLACK, s, K_INK))
	_bolts(g, 0.42)


## Lane-use control for a two-lane approach: left lane turns left, right lane straight.
static func _lanes_face(g: Geo) -> void:
	var o := rounded(rect_poly(0.76, 0.76), 0.035, 3)
	face(g, o, WHITE, BLACK, 0.012, 0.016, func(gg: Geo, z: float, s: float) -> void:
		# The left lane's arrow: up, then bending left.
		var lx := -0.17
		var bend := PackedVector2Array([Vector2(lx + 0.06, -0.26), Vector2(lx + 0.06, 0.0)])
		for k in range(1, 7):
			var a := deg_to_rad(90.0 * k / 6.0)
			bend.append(Vector2(lx + 0.06 - 0.12 + cos(a) * 0.12, 0.0 + sin(a) * 0.12))
		bend.append(Vector2(lx - 0.1, 0.12))
		strokes(gg, [bend], 0.05, z, BLACK, K_INK, s)
		_head(gg, Vector2(lx - 0.1, 0.12), Vector2(-1.0, 0.0), 0.11, z, BLACK, s)
		strokes(gg, [PackedVector2Array([Vector2(0.17, -0.26), Vector2(0.17, 0.12)])], 0.05, z, BLACK, K_INK, s)
		_head(gg, Vector2(0.17, 0.12), Vector2(0.0, 1.0), 0.11, z, BLACK, s)
		text(gg, "ONLY", 0.06, lx, -0.3, 0.2, z, BLACK, s, K_INK))


static func _no_turn_red_face(g: Geo) -> void:
	var o := rounded(rect_poly(0.61, 0.76), 0.03, 3)
	face(g, o, WHITE, BLACK, 0.012, 0.016, func(gg: Geo, z: float, s: float) -> void:
		text(gg, "NO", 0.1, 0.0, 0.25, 0.45, z, BLACK, s, K_INK)
		text(gg, "TURN", 0.1, 0.0, 0.08, 0.45, z, BLACK, s, K_INK)
		text(gg, "ON", 0.1, 0.0, -0.09, 0.45, z, BLACK, s, K_INK)
		text(gg, "RED", 0.12, 0.0, -0.26, 0.45, z, RED, s))


static func _offset(poly: PackedVector2Array, d: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in poly:
		out.append(p + d)
	return out


## An arrow along `dir` (unit, face space) centred on `c`, `length` long, shaft `pen` wide.
static func _arrow(g: Geo, c: Vector2, dir: Vector2, length: float, pen: float, z: float, col: Color, facing: float) -> void:
	var a := c - dir * length * 0.5
	var b := c + dir * (length * 0.5 - pen * 1.6)
	strokes(g, [PackedVector2Array([a, b])], pen, z, col, K_SHEET, facing)
	_head(g, b, dir, pen * 3.2, z, col, facing)


## A filled arrowhead with its base centre at `at`, pointing along `dir`.
static func _head(g: Geo, at: Vector2, dir: Vector2, size: float, z: float, col: Color, facing: float) -> void:
	var side := Vector2(-dir.y, dir.x)
	var tip := at + dir * size * 0.9
	var poly := PackedVector2Array([at + side * size * 0.5, at - side * size * 0.5, tip])
	if (poly[1] - poly[0]).cross(poly[2] - poly[0]) < 0.0:
		poly = PackedVector2Array([poly[1], poly[0], poly[2]])
	var kind := K_INK if col == BLACK else K_SHEET
	fill(g, poly, z, col, kind, facing)


## A walking figure `h` tall with its feet at `foot` (face metres): head, body, arms and legs as
## heavy strokes, the symbol's silhouette.
static func _figure(g: Geo, foot: Vector2, h: float, z: float, facing: float, phase: float) -> void:
	var s := facing
	var hip := foot + Vector2(0.0, h * 0.45)
	var neck := foot + Vector2(0.02 * s * h, h * 0.8)
	var pen := h * 0.13
	var stride := 0.17 + 0.04 * phase
	strokes(g, [PackedVector2Array([hip, neck])], pen * 1.25, z, BLACK, K_INK, facing)
	strokes(g, [PackedVector2Array([foot + Vector2(-stride * h * s, 0.0), hip + Vector2(0.0, -0.02), foot + Vector2(stride * h * s * 0.8, 0.02 * h)])], pen, z, BLACK, K_INK, facing)
	strokes(g, [PackedVector2Array([neck + Vector2(-0.16 * h * s, -0.3 * h), neck + Vector2(0.0, -0.04 * h), neck + Vector2(0.17 * h * s, -0.26 * h)])], pen * 0.8, z, BLACK, K_INK, facing)
	var head := PackedVector2Array()
	var hc := neck + Vector2(0.0, h * 0.12)
	for k in 12:
		var a := TAU * k / 12.0
		head.append(hc + Vector2(cos(a), sin(a)) * h * 0.085)
	fill(g, head, z, BLACK, K_INK, facing)


## Bolt heads: two, above and below the centre, on the face.
static func _bolts(g: Geo, dy: float) -> void:
	for y: float in [dy, -dy]:
		cylinder_z(g, Vector2(0.0, y), 0.009, PLATE_T * 0.5, PLATE_T * 0.5 + 0.004, ALU, K_HW)


## A short cylinder along +Z (a bolt head) on the face at `c`.
static func cylinder_z(g: Geo, c: Vector2, r: float, z0: float, z1: float, col: Color, kind: int) -> void:
	var sides := 6
	for i in sides:
		var a0 := TAU * i / sides
		var a1 := TAU * (i + 1) / sides
		var p0 := c + Vector2(cos(a0), sin(a0)) * r
		var p1 := c + Vector2(cos(a1), sin(a1)) * r
		g.tri(Vector3(c.x, c.y, z1), Vector3(p0.x, p0.y, z1), Vector3(p1.x, p1.y, z1), Vector3.BACK, col, kind)
		var out := Vector3(cos((a0 + a1) * 0.5), sin((a0 + a1) * 0.5), 0.0)
		g.quad(Vector3(p0.x, p0.y, z0), Vector3(p1.x, p1.y, z0), Vector3(p1.x, p1.y, z1), Vector3(p0.x, p0.y, z1), out, col, kind)


# --- Street-name blades --------------------------------------------------------------------------

## Splits a street name into the name and LA's short suffix ("VISTA BLVD" -> ["VISTA", "BL"]).
static func split_name(s: String) -> Array:
	var up := s.to_upper().strip_edges()
	var sfx := {"BLVD": "BL", "AVE": "AV", "ST": "ST", "DR": "DR", "RD": "RD", "PL": "PL", "WAY": "WY", "LN": "LN", "CT": "CT", "PKWY": "PY"}
	var cut := up.rfind(" ")
	if cut > 0:
		var last := up.substr(cut + 1)
		if sfx.has(last):
			return [up.substr(0, cut), sfx[last]]
	return [up, ""]


## A blade's length for a name (metres), clamped to what LA's blades come in.
static func blade_length(name: String, cap: float = BLADE_CAP) -> float:
	var parts := split_name(name)
	var w: float = SignFont.layout(parts[0], cap, cap / 6.5)[1]
	if parts[1] != "":
		w += cap * 0.25 + SignFont.layout(parts[1], cap * 0.6, cap * 0.6 / 6.5)[1]
	return clampf(w + cap * 2.4, 0.75, 1.7)


## A two-sided name blade along the frame's X: green, white border, the name and its suffix, the
## block number small at the left end, both faces (each reading the right way).
static func blade(g: Geo, name: String, number: String, h: float = BLADE_H, cap: float = BLADE_CAP, t: float = BLADE_T) -> float:
	var parts := split_name(name)
	var length := blade_length(name, cap)
	var o := rounded(rect_poly(length, h), h * 0.12, 3)
	face(g, o, GREEN, WHITE, h * 0.04, h * 0.045, func(gg: Geo, z: float, s: float) -> void:
		var num_w := cap * 1.1
		var room := length - num_w - cap * 0.9
		var main_w: float = SignFont.layout(parts[0], cap, cap / 6.5)[1]
		var sfx_cap := cap * 0.6
		var sfx_w: float = 0.0 if parts[1] == "" else SignFont.layout(parts[1], sfx_cap, sfx_cap / 6.5)[1] + cap * 0.25
		var total := main_w + sfx_w
		var sq := minf(1.0, room / maxf(total, 0.001))
		var left := -length * 0.5 + num_w + cap * 0.35 + (room - total * sq) * 0.5
		var mx := left + main_w * sq * 0.5
		text(gg, parts[0], cap, mx * s, -h * 0.02, main_w * sq, z, WHITE, s)
		if parts[1] != "":
			var sx := left + main_w * sq + sfx_w * sq * 0.5 + cap * 0.125 * sq
			text(gg, parts[1], sfx_cap, sx * s, -h * 0.02 + (cap - sfx_cap) * 0.5, sfx_w * sq, z, WHITE, s)
		if number != "":
			var nx := -length * 0.5 + cap * 0.3 + num_w * 0.5
			text(gg, number, cap * 0.36, nx * s, h * 0.18, num_w * 0.9, z, WHITE, s)
		, true, t)
	return length


## Two blades crossed on a flat-blade cap bracket at the top of a post (or a pole of radius
## `pole_r` whose top is at `top`): the lower blade along X names the road that runs along X
## (`name_z`, an AXIS_Z road), the upper along Z the road that runs along Z (`name_x`).
static func crossed_blades(g: Geo, top: float, pole_r: float, name_x: String, num_x: String, name_z: String, num_z: String) -> void:
	g.xf = Transform3D.IDENTITY
	# The cast cap bracket: a collar over the post top, two slotted fins, a dome.
	cylinder(g, 0.0, 0.0, pole_r + 0.012, top - 0.07, top + 0.56, ALU.darkened(0.15), K_HW, 12, true)
	var y0 := top + 0.03 + BLADE_H * 0.5
	var y1 := y0 + BLADE_H + 0.05
	g.xf = Transform3D(Basis(), Vector3(0.0, y0, 0.0))
	blade(g, name_z, num_z)
	g.xf = Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(0.0, y1, 0.0))
	blade(g, name_x, num_x)
	g.xf = Transform3D.IDENTITY


# --- Assemblies (cached meshes) ----------------------------------------------------------------

## Post height that puts a sign's bottom at 7 ft over the pavement (urban), with room above.
const SIGN_BOTTOM := 2.13


static func _cached(key: String, build: Callable) -> ArrayMesh:
	if _cache.has(key):
		return _cache[key]
	# Street names are many: let the cache start over now and then (meshes in use stay alive in
	# their batches).
	if _cache.size() > 1500:
		_cache.clear()
	var g := Geo.new()
	build.call(g)
	var m := g.mesh()
	m.set_meta("ss_key", key)
	_cache[key] = m
	return m


## A post with the name blades on top (a corner of an unsigned junction).
static func name_post(name_x: String, num_x: String, name_z: String, num_z: String) -> ArrayMesh:
	return _cached("np|%s|%s|%s|%s" % [name_x, num_x, name_z, num_z], func(g: Geo) -> void:
		post(g, 2.9)
		crossed_blades(g, 2.9, POST_R, name_x, num_x, name_z, num_z))


## A stop sign with its ALL WAY plaque on a post; with names, the blades on top too.
static func stop_post(names: Array = []) -> ArrayMesh:
	var key := "stop" if names.is_empty() else "stop|%s|%s|%s|%s" % names
	return _cached(key, func(g: Geo) -> void:
		var top := 2.95 if names.is_empty() else 3.15
		post(g, top)
		mount(g, SIGN_BOTTOM + 0.381 + 0.2, 0.36, _stop_face)
		mount(g, SIGN_BOTTOM + 0.08, 0.06, _all_way_face)
		if not names.is_empty():
			crossed_blades(g, top, POST_R, names[0], names[1], names[2], names[3]))


static func yield_post() -> ArrayMesh:
	return _cached("yield", func(g: Geo) -> void:
		post(g, 3.05)
		mount(g, SIGN_BOTTOM + 0.4, 0.3, _yield_face))


static func speed_post(mph: int) -> ArrayMesh:
	return _cached("speed%d" % mph, func(g: Geo) -> void:
		post(g, 3.0)
		mount(g, SIGN_BOTTOM + 0.38, 0.33, _speed_face.bind(mph)))


static func no_parking_post() -> ArrayMesh:
	return _cached("nopark", func(g: Geo) -> void:
		post(g, 2.75)
		mount(g, SIGN_BOTTOM + 0.23, 0.2, _no_parking_face))


## The school zone assembly: the crossing pentagon over the SCHOOL / SPEED LIMIT 25 plate.
static func school_post() -> ArrayMesh:
	return _cached("school", func(g: Geo) -> void:
		post(g, 3.95)
		mount(g, SIGN_BOTTOM + 0.5, 0.45, _school_speed_face)
		mount(g, SIGN_BOTTOM + 1.42, 0.33, _school_face))


## The cast cap bracket and two blades for the top of a signal pole (radius 0.1 at its top).
static func pole_top_blades(name_x: String, num_x: String, name_z: String, num_z: String) -> ArrayMesh:
	return _cached("pt|%s|%s|%s|%s" % [name_x, num_x, name_z, num_z], func(g: Geo) -> void:
		crossed_blades(g, PropFactory.SIGNAL_POLE_HEIGHT, 0.1, name_x, num_x, name_z, num_z))


## A sign hung on a mast arm: origin on the arm's axis, the arm along X, the face toward +Z and
## its centre `drop` below the axis; two strap brackets round the arm (radius `arm_r`).
static func _arm_mount(g: Geo, w: float, h: float, drop: float, arm_r: float, build: Callable) -> void:
	g.xf = Transform3D.IDENTITY
	for sx: float in [-w * 0.3, w * 0.3]:
		# A band round the arm (a short 10-sided tube along X) and a strap down to the sign.
		for i in 10:
			var a0 := TAU * i / 10.0
			var a1 := TAU * (i + 1) / 10.0
			var p0 := Vector3(0.0, sin(a0), cos(a0)) * (arm_r + 0.006)
			var p1 := Vector3(0.0, sin(a1), cos(a1)) * (arm_r + 0.006)
			var out := Vector3(0.0, sin((a0 + a1) * 0.5), cos((a0 + a1) * 0.5))
			g.quad(p0 + Vector3(sx - 0.025, 0, 0), p1 + Vector3(sx - 0.025, 0, 0), p1 + Vector3(sx + 0.025, 0, 0), p0 + Vector3(sx + 0.025, 0, 0), out, STEEL, K_HW)
		var z_strap := ARM_STANDOFF - PLATE_T - 0.01
		# The strap: from the sign's back up over the arm's front to its crown.
		var y0 := -drop - h * 0.42
		var y1 := arm_r * 0.85
		box(g, Vector3(sx, (y0 + y1) * 0.5, z_strap), Vector3(0.025, (y1 - y0) * 0.5, 0.008), STEEL, K_HW)
		box(g, Vector3(sx, y1, (z_strap + 0.0) * 0.5), Vector3(0.025, 0.008, z_strap * 0.5), STEEL, K_HW)
	g.xf = Transform3D(Basis(), Vector3(0.0, -drop, ARM_STANDOFF))
	build.call(g)
	g.xf = Transform3D.IDENTITY


## The mast arm's street-name sign: one-sided (its back is bare aluminium), naming the street the
## approach crosses.
static func arm_name(name: String, number: String) -> ArrayMesh:
	return _cached("an|%s|%s" % [name, number], func(g: Geo) -> void:
		var length := clampf(blade_length(name, ARM_SIGN_CAP) * 1.05, 1.5, 2.9)
		_arm_mount(g, length, ARM_SIGN_H, 0.05, 0.1, func(gg: Geo) -> void:
			var parts := split_name(name)
			var o := rounded(rect_poly(length, ARM_SIGN_H), 0.05, 3)
			face(gg, o, GREEN, WHITE, 0.015, 0.02, func(g2: Geo, z: float, s: float) -> void:
				var cap := ARM_SIGN_CAP
				var main_w: float = SignFont.layout(parts[0], cap, cap / 6.5)[1]
				var sfx_cap := cap * 0.6
				var sfx_w: float = 0.0 if parts[1] == "" else SignFont.layout(parts[1], sfx_cap, sfx_cap / 6.5)[1] + cap * 0.25
				var num_w := cap * 1.0
				var room := length - num_w - cap * 0.8
				var sq := minf(1.0, room / maxf(main_w + sfx_w, 0.001))
				var left := -length * 0.5 + num_w + cap * 0.3 + (room - (main_w + sfx_w) * sq) * 0.5
				text(g2, parts[0], cap, left + main_w * sq * 0.5, -0.01, main_w * sq, z, WHITE, s)
				if parts[1] != "":
					text(g2, parts[1], sfx_cap, left + main_w * sq + cap * 0.125 + sfx_w * sq * 0.5, -0.01 + (cap - sfx_cap) * 0.5, sfx_w * sq, z, WHITE, s)
				text(g2, number, cap * 0.36, -length * 0.5 + cap * 0.25 + num_w * 0.5, 0.1, num_w * 0.9, z, WHITE, s))
			_bolts(gg, ARM_SIGN_H * 0.3)))


static func arm_lanes() -> ArrayMesh:
	return _cached("arm_lanes", func(g: Geo) -> void:
		_arm_mount(g, 0.76, 0.76, 0.2, 0.09, _lanes_face))


static func arm_no_turn_red() -> ArrayMesh:
	return _cached("arm_ntor", func(g: Geo) -> void:
		_arm_mount(g, 0.61, 0.76, 0.2, 0.1, _no_turn_red_face))


## Triangles in a mesh (tests and the probe).
static func triangles(m: Mesh) -> int:
	var t := 0
	for s in m.get_surface_count():
		t += (m.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return t
