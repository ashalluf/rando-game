class_name DecoBuild
extends RefCounted
## The geometry of the Wilshire deco buildings (DecoBoulevard plans them): zigzag-moderne towers,
## streamline-moderne corners, a deco theatre, deco apartments and Spanish courtyard apartments,
## built in code at real size into ONE chunk's meshes:
##
##   - the windowed walls on shaders/building.gdshader in its outline mode (`uv_facade`) with the
##     part numbers in the vertices (`part_attributes`, Building's CUSTOM0-3 layout), so the
##     windows keep the traced rooms, the lit offices at night, the storefronts and the glass
##     mirror every Building has. UV.x is metres along a face (each face a whole number of bays),
##     UV.y the face index (100+ blank wall). One surface per palette.
##   - everything else on shaders/deco_ornament.gdshader (`Orn`): piers, chevron spandrels,
##     friezes, finials and crowns (floodlit at night), glass block, speed lines, canopies, the
##     theatre's marquee and blade sign, neon names, clay roofs, tile and a fountain.
##
## Building frame: x along the street, y up from the pavement, +z toward the street; the front
## face is the plane z = 0, the building runs back to z = -d, x in -w/2..w/2. `xf` takes it into
## the chunk (DecoBoulevard.frame_xform()). Every roll is the plan's (DecoBoulevard), so nothing
## here draws a random number.

const ORN_SHADER := preload("res://shaders/deco_ornament.gdshader")

## Ornament kinds (shaders/deco_ornament.gdshader).
const STONE := 0
const GLAZE := 1
const CHEVRON := 2
const SUNBURST := 3
const ZIGZAG := 4
const FLUTE := 5
const METAL := 6
const GLASS_BLOCK := 7
const NEON := 8
const BULBS := 9
const ENAMEL := 10
const SOFFIT := 11
const CLAY := 12
const STUCCO := 13
const TILE := 14
const ROOF := 15
const READER := 16
const GRANITE := 17
const WATER := 18
const DARK := 19
const GILT := 20

## Storeys (metres): the shop floor, and every floor above it.
const GROUND_H := 4.6
const FLOOR_H := 3.5
## The window bay the walls are laid out on (PUNCHED windows: 54 % of a bay wide).
const BAY := 1.5
## A deco pier: its width and how far it stands proud of the wall; the corner and major piers.
const PIER_W := 0.62
const PIER_OUT := 0.34
const MAJOR_W := 1.05
const MAJOR_OUT := 0.52

static var _orn_mat: ShaderMaterial
static var _wall_mats: Dictionary = {}


# --- Accumulators ------------------------------------------------------------------------------

## The ornament mesh of a chunk (one surface, one material).
class Orn:
	var xf := Transform3D()
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var t := PackedFloat32Array()
	var c := PackedColorArray()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()

	static func col(paint: Color, kind: int, flood: bool = false) -> Color:
		return Color(paint.r, paint.g, paint.b, (float(kind + (32 if flood else 0)) + 0.5) / 64.0)

	## A triangle facing `want` (its winding is fixed to suit), in building space.
	func tri(a: Vector3, b: Vector3, cc: Vector3, want: Vector3, colr: Color, ua: Vector2, ub: Vector2, uc: Vector2,
			u2: Vector2, tan: Vector3) -> void:
		var nn := (cc - a).cross(b - a)
		if nn.length_squared() < 1e-12:
			return
		if nn.dot(want) < 0.0:
			var tb := b
			b = cc
			cc = tb
			var tu := ub
			ub = uc
			uc = tu
		var wn := (xf.basis * want).normalized()
		var wt := (xf.basis * tan).normalized()
		for p: Vector3 in [a, b, cc]:
			v.append(xf * p)
			n.append(wn)
			t.append(wt.x)
			t.append(wt.y)
			t.append(wt.z)
			t.append(1.0)
			c.append(colr)
			uv2.append(u2)
		uv.append(ua)
		uv.append(ub)
		uv.append(uc)

	func quad(a: Vector3, b: Vector3, cc: Vector3, d: Vector3, want: Vector3, colr: Color, ua: Vector2, ub: Vector2,
			uc: Vector2, ud: Vector2, u2: Vector2, tan: Vector3) -> void:
		tri(a, b, cc, want, colr, ua, ub, uc, u2, tan)
		tri(a, cc, d, want, colr, ua, uc, ud, u2, tan)

	## A flat panel: lower-left corner `o`, `right` and `up` unit vectors, w x h metres, facing
	## right x up. UV is panel metres, UV2 the panel's size (the chevron and sunburst read it).
	func panel(o: Vector3, right: Vector3, up: Vector3, w: float, h: float, colr: Color, vbase: float = -1.0) -> void:
		var nn := up.cross(right).normalized() * -1.0
		nn = right.cross(up).normalized()
		var off := 0.0 if vbase < 0.0 else o.y - vbase
		quad(o, o + right * w, o + right * w + up * h, o + up * h, nn, colr,
			Vector2(0.0, off), Vector2(w, off), Vector2(w, h + off), Vector2(0.0, h + off), Vector2(w, h), right)

	## A box (building space): `b` turns it, `size` its full size. Side faces have UV (metres
	## along the face, metres above `vbase`), top and bottom (x, z). `panel_h` > 0 hands the side
	## faces a panel size (a frieze's height).
	func box(center: Vector3, size: Vector3, colr: Color, b: Basis = Basis(), vbase: float = 0.0, top: bool = true,
			bottom: bool = false, panel_h: float = 0.0) -> void:
		var h := size * 0.5
		var ax := b.x.normalized()
		var ay := b.y.normalized()
		var az := b.z.normalized()
		var pts := []
		for k in 8:
			var sx := 1.0 if k & 1 else -1.0
			var sy := 1.0 if k & 2 else -1.0
			var sz := 1.0 if k & 4 else -1.0
			pts.append(center + ax * (sx * h.x) + ay * (sy * h.y) + az * (sz * h.z))
		# Sides: +x, -x, +z, -z.
		var faces := [[1, 5, 7, 3, ax, -az, size.z], [4, 0, 2, 6, -ax, az, size.z], [5, 4, 6, 7, az, ax, size.x], [0, 1, 3, 2, -az, -ax, size.x]]
		for f: Array in faces:
			var p0: Vector3 = pts[f[0]]
			var p1: Vector3 = pts[f[1]]
			var p2: Vector3 = pts[f[2]]
			var p3: Vector3 = pts[f[3]]
			var l: float = f[6]
			var y0 := p0.y - vbase
			var y1 := p3.y - vbase
			quad(p0, p1, p2, p3, f[4], colr, Vector2(0.0, y0), Vector2(l, y0), Vector2(l, y1), Vector2(0.0, y1),
				Vector2(l, panel_h) if panel_h > 0.0 else Vector2.ZERO, f[5])
		if top:
			var q: Array = [pts[2], pts[3], pts[7], pts[6]]
			quad(q[0], q[1], q[2], q[3], ay, colr, Vector2((q[0] as Vector3).x, (q[0] as Vector3).z), Vector2((q[1] as Vector3).x, (q[1] as Vector3).z),
				Vector2((q[2] as Vector3).x, (q[2] as Vector3).z), Vector2((q[3] as Vector3).x, (q[3] as Vector3).z), Vector2.ZERO, ax)
		if bottom:
			var q: Array = [pts[0], pts[1], pts[5], pts[4]]
			quad(q[0], q[1], q[2], q[3], -ay, colr, Vector2((q[0] as Vector3).x, (q[0] as Vector3).z), Vector2((q[1] as Vector3).x, (q[1] as Vector3).z),
				Vector2((q[2] as Vector3).x, (q[2] as Vector3).z), Vector2((q[3] as Vector3).x, (q[3] as Vector3).z), Vector2.ZERO, ax)

	## An axis-aligned box from two corners (building space).
	func aabb(lo: Vector3, hi: Vector3, colr: Color, vbase: float = 0.0, top: bool = true, panel_h: float = 0.0) -> void:
		box((lo + hi) * 0.5, hi - lo, colr, Basis(), vbase, top, false, panel_h)

	## A band swept along a polyline of (x, z) points with outward normals `nrm` (per point): from
	## y0 to y1, `out` metres proud of the line. Its front and top; UV along the run.
	func band(pts: PackedVector2Array, nrm: PackedVector2Array, y0: float, y1: float, out: float, colr: Color,
			vbase: float = 0.0, panel_h: float = 0.0, top: bool = true, under: bool = false) -> void:
		var run := 0.0
		for i in pts.size() - 1:
			var a := pts[i] + nrm[i] * out
			var bb := pts[i + 1] + nrm[i + 1] * out
			var a0 := pts[i]
			var b0 := pts[i + 1]
			var seg := a.distance_to(bb)
			var mid := ((nrm[i] + nrm[i + 1]) * 0.5).normalized()
			var want := Vector3(mid.x, 0.0, mid.y)
			var tan := Vector3(bb.x - a.x, 0.0, bb.y - a.y).normalized()
			quad(Vector3(a.x, y0, a.y), Vector3(bb.x, y0, bb.y), Vector3(bb.x, y1, bb.y), Vector3(a.x, y1, a.y), want, colr,
				Vector2(run, y0 - vbase), Vector2(run + seg, y0 - vbase), Vector2(run + seg, y1 - vbase), Vector2(run, y1 - vbase),
				Vector2(seg, panel_h) if panel_h > 0.0 else Vector2.ZERO, tan)
			if top:
				quad(Vector3(a0.x, y1, a0.y), Vector3(b0.x, y1, b0.y), Vector3(bb.x, y1, bb.y), Vector3(a.x, y1, a.y), Vector3.UP, colr,
					Vector2(run, 0.0), Vector2(run + seg, 0.0), Vector2(run + seg, out), Vector2(run, out), Vector2.ZERO, tan)
			if under:
				quad(Vector3(a0.x, y0, a0.y), Vector3(b0.x, y0, b0.y), Vector3(bb.x, y0, bb.y), Vector3(a.x, y0, a.y), Vector3.DOWN, colr,
					Vector2(run, 0.0), Vector2(run + seg, 0.0), Vector2(run + seg, out), Vector2(run, out), Vector2.ZERO, tan)
			run += seg

	## A cylinder wall piece (outward), centre (x, z), radius r, angles a0..a1 (radians, 0 = +x,
	## measured toward +z), y0..y1. UV along the arc.
	func arc_wall(cx: Vector2, r: float, a0: float, a1: float, y0: float, y1: float, segs: int, colr: Color, vbase: float = 0.0) -> void:
		var run := 0.0
		for i in segs:
			var t0 := lerpf(a0, a1, float(i) / segs)
			var t1 := lerpf(a0, a1, float(i + 1) / segs)
			var p0 := cx + Vector2(cos(t0), sin(t0)) * r
			var p1 := cx + Vector2(cos(t1), sin(t1)) * r
			var seg := p0.distance_to(p1)
			var tm := (t0 + t1) * 0.5
			var want := Vector3(cos(tm), 0.0, sin(tm))
			var tan := Vector3(p1.x - p0.x, 0.0, p1.y - p0.y).normalized()
			quad(Vector3(p0.x, y0, p0.y), Vector3(p1.x, y0, p1.y), Vector3(p1.x, y1, p1.y), Vector3(p0.x, y1, p0.y), want, colr,
				Vector2(run, y0 - vbase), Vector2(run + seg, y0 - vbase), Vector2(run + seg, y1 - vbase), Vector2(run, y1 - vbase), Vector2.ZERO, tan)
			run += seg

	## A tapered four-sided spire from a base square of half size `r0` at y0 to `r1` at y1.
	func spire(cx: Vector2, r0: float, r1: float, y0: float, y1: float, colr: Color, vbase: float = 0.0) -> void:
		var corners := [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
		for i in 4:
			var ca: Vector2 = corners[i]
			var cb: Vector2 = corners[(i + 1) % 4]
			var a0 := Vector3(cx.x + ca.x * r0, y0, cx.y + ca.y * r0)
			var b0 := Vector3(cx.x + cb.x * r0, y0, cx.y + cb.y * r0)
			var b1 := Vector3(cx.x + cb.x * r1, y1, cx.y + cb.y * r1)
			var a1 := Vector3(cx.x + ca.x * r1, y1, cx.y + ca.y * r1)
			var mid := (ca + cb) * 0.5
			var want := Vector3(mid.x, (r0 - r1) / maxf(y1 - y0, 0.01), mid.y).normalized()
			quad(a0, b0, b1, a1, want, colr, Vector2(0, y0 - vbase), Vector2(r0 * 2.0, y0 - vbase), Vector2(r0 * 2.0, y1 - vbase), Vector2(0, y1 - vbase),
				Vector2.ZERO, (b0 - a0).normalized())
		if r1 > 0.01:
			var top := [Vector3(cx.x - r1, y1, cx.y - r1), Vector3(cx.x + r1, y1, cx.y - r1), Vector3(cx.x + r1, y1, cx.y + r1), Vector3(cx.x - r1, y1, cx.y + r1)]
			quad(top[0], top[1], top[2], top[3], Vector3.UP, colr, Vector2.ZERO, Vector2(1, 0), Vector2(1, 1), Vector2(0, 1), Vector2.ZERO, Vector3.RIGHT)

	## A gable roof (clay) over the rect x0..x1, z0..z1 with its ridge along `ridge_x` (true: the
	## ridge runs along x), eaves at `y`, `pitch` rise per run, `over` metres of overhang. The gable
	## ends are stucco triangles in `wall` paint.
	func gable(x0: float, x1: float, z0: float, z1: float, y: float, pitch: float, over: float, ridge_x: bool,
			roofc: Color, wallc: Color) -> void:
		var tile := Orn.col(roofc, DecoBuild.CLAY)
		var stucco := Orn.col(wallc, DecoBuild.STUCCO)
		if ridge_x:
			var zc := (z0 + z1) * 0.5
			var half := (z1 - z0) * 0.5
			var rise := half * pitch
			var ye := y - over * pitch
			for s: float in [-1.0, 1.0]:
				var ze := zc + s * (half + over)
				var a := Vector3(x0 - over, ye, ze)
				var b := Vector3(x1 + over, ye, ze)
				var cc := Vector3(x1 + over, y + rise, zc)
				var d := Vector3(x0 - over, y + rise, zc)
				var slope := sqrt((half + over) * (half + over) + (rise + over * pitch) * (rise + over * pitch))
				quad(a, b, cc, d, Vector3(0.0, 1.0, s * pitch).normalized(), tile, Vector2(x0, 0.0), Vector2(x1 + 2.0 * over, 0.0),
					Vector2(x1 + 2.0 * over, slope), Vector2(x0, slope), Vector2.ZERO, Vector3.RIGHT)
				# Under the eave.
				quad(Vector3(x0 - over, ye - 0.06, ze), Vector3(x1 + over, ye - 0.06, ze), Vector3(x1 + over, y - 0.06, zc + s * half),
					Vector3(x0 - over, y - 0.06, zc + s * half), Vector3(0.0, -1.0, 0.0), Orn.col(wallc * 0.8, DecoBuild.STUCCO),
					Vector2.ZERO, Vector2(1, 0), Vector2(1, 1), Vector2(0, 1), Vector2.ZERO, Vector3.RIGHT)
			for e: float in [x0, x1]:
				var sgn := -1.0 if e == x0 else 1.0
				tri(Vector3(e, y, z0), Vector3(e, y, z1), Vector3(e, y + rise, zc), Vector3(sgn, 0, 0), stucco,
					Vector2(z0, y), Vector2(z1, y), Vector2(zc, y + rise), Vector2.ZERO, Vector3(0, 0, -sgn))
		else:
			var xc := (x0 + x1) * 0.5
			var half := (x1 - x0) * 0.5
			var rise := half * pitch
			var ye := y - over * pitch
			for s: float in [-1.0, 1.0]:
				var xe := xc + s * (half + over)
				var a := Vector3(xe, ye, z0 - over)
				var b := Vector3(xe, ye, z1 + over)
				var cc := Vector3(xc, y + rise, z1 + over)
				var d := Vector3(xc, y + rise, z0 - over)
				var slope := sqrt((half + over) * (half + over) + (rise + over * pitch) * (rise + over * pitch))
				quad(a, b, cc, d, Vector3(s * pitch, 1.0, 0.0).normalized(), tile, Vector2(z0, 0.0), Vector2(z1 + 2.0 * over, 0.0),
					Vector2(z1 + 2.0 * over, slope), Vector2(z0, slope), Vector2.ZERO, Vector3.BACK)
				quad(Vector3(xe, ye - 0.06, z0 - over), Vector3(xe, ye - 0.06, z1 + over), Vector3(xc + s * half, y - 0.06, z1 + over),
					Vector3(xc + s * half, y - 0.06, z0 - over), Vector3(0.0, -1.0, 0.0), Orn.col(wallc * 0.8, DecoBuild.STUCCO),
					Vector2.ZERO, Vector2(1, 0), Vector2(1, 1), Vector2(0, 1), Vector2.ZERO, Vector3.BACK)
			for e: float in [z0, z1]:
				var sgn := -1.0 if e == z0 else 1.0
				tri(Vector3(x0, y, e), Vector3(x1, y, e), Vector3(xc, y + rise, e), Vector3(0, 0, sgn), stucco,
					Vector2(x0, y), Vector2(x1, y), Vector2(xc, y + rise), Vector2.ZERO, Vector3(sgn, 0, 0))

	## Letters (TextMesh geometry, flat) at `at` (building space) in the plane of `right` x `up`,
	## facing right x up, `height` the cap height.
	func text(s: String, at: Vector3, right: Vector3, up: Vector3, height: float, colr: Color) -> void:
		var geo: Array = DecoBuild.text_geo(s, height)
		var src: PackedVector3Array = geo[0]
		var idx: PackedInt32Array = geo[1]
		var nn := right.cross(up).normalized()
		for k in range(0, idx.size(), 3):
			var p := []
			for j in 3:
				var q: Vector3 = src[idx[k + j]]
				p.append(at + right * q.x + up * q.y + nn * 0.004)
			tri(p[0], p[1], p[2], nn, colr, Vector2(src[idx[k]].x, src[idx[k]].y), Vector2(src[idx[k + 1]].x, src[idx[k + 1]].y),
				Vector2(src[idx[k + 2]].x, src[idx[k + 2]].y), Vector2.ZERO, right)

	func commit() -> ArrayMesh:
		var mesh := ArrayMesh.new()
		if v.is_empty():
			return mesh
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = v
		arrays[Mesh.ARRAY_NORMAL] = n
		arrays[Mesh.ARRAY_TANGENT] = t
		arrays[Mesh.ARRAY_COLOR] = c
		arrays[Mesh.ARRAY_TEX_UV] = uv
		arrays[Mesh.ARRAY_TEX_UV2] = uv2
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return mesh

	func triangles() -> int:
		return v.size() / 3


## The windowed walls of a chunk's deco buildings in one palette: Building's vertex layout
## (CUSTOM0 position in the part + storefront flag, CUSTOM1 part size + base course height,
## CUSTOM2 the two pitches + floor height + shop-floor top (world y), CUSTOM3 base y (world) +
## crown start), the face's metres in UV.x and its index in UV.y.
class Walls:
	var xf := Transform3D()
	## World y of the building's pavement (base_y), and its parts' numbers.
	var base_y := 0.0
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var t := PackedFloat32Array()
	var uv := PackedVector2Array()
	var c0 := PackedFloat32Array()
	var c1 := PackedFloat32Array()
	var c2 := PackedFloat32Array()
	var c3 := PackedFloat32Array()

	## One straight wall face from a to b ((x, z), building space; u runs a -> b, the outward
	## normal is (d.z, -d.x), the building shader's own rule), y0..y1. `p`: shop (bool), ground
	## (shop floor's top, metres over the pavement), floor (storey height), base_h (base course),
	## bay (target bay width), face (index), blank (true: no windows), size (Vector3).
	func face(a: Vector2, b: Vector2, y0: float, y1: float, p: Dictionary) -> void:
		var d := b - a
		var len := d.length()
		if len < 0.05 or y1 - y0 < 0.05:
			return
		var dn := d / len
		var nrm := Vector3(dn.y, 0.0, -dn.x)
		var bays := maxi(1, roundi(len / float(p.get("bay", DecoBuild.BAY))))
		var pitch := len / float(bays)
		_quad([Vector3(a.x, y0, a.y), Vector3(b.x, y0, b.y), Vector3(b.x, y1, b.y), Vector3(a.x, y1, a.y)],
			[nrm, nrm, nrm, nrm], [0.0, len, len, 0.0], nrm, Vector3(dn.x, 0.0, dn.y), pitch, p)

	## A curved wall: centre (x, z), radius, angles a0 -> a1 (radians, 0 = +x toward +z; u runs
	## with the angle when a1 > a0), smooth normals.
	func arc(cx: Vector2, r: float, a0: float, a1: float, y0: float, y1: float, segs: int, p: Dictionary) -> void:
		var total := absf(a1 - a0) * r
		var bays := maxi(1, roundi(total / float(p.get("bay", DecoBuild.BAY))))
		var pitch := total / float(bays)
		var run := 0.0
		for i in segs:
			var t0 := lerpf(a0, a1, float(i) / segs)
			var t1 := lerpf(a0, a1, float(i + 1) / segs)
			var p0 := cx + Vector2(cos(t0), sin(t0)) * r
			var p1 := cx + Vector2(cos(t1), sin(t1)) * r
			var n0 := Vector3(cos(t0), 0.0, sin(t0))
			var n1 := Vector3(cos(t1), 0.0, sin(t1))
			var seg := p0.distance_to(p1)
			var dn := (p1 - p0).normalized()
			_quad([Vector3(p0.x, y0, p0.y), Vector3(p1.x, y0, p1.y), Vector3(p1.x, y1, p1.y), Vector3(p0.x, y1, p0.y)],
				[n0, n1, n1, n0], [run, run + seg, run + seg, run], (n0 + n1).normalized(), Vector3(dn.x, 0.0, dn.y), pitch, p)
			run += seg

	## A flat roof over an outline at height y (UV.x past the parapet ring's 0.5).
	func roof(outline: PackedVector2Array, y: float, p: Dictionary) -> void:
		var idx := Geometry2D.triangulate_polygon(outline)
		for k in range(0, idx.size(), 3):
			var a := outline[idx[k]]
			var b := outline[idx[k + 1]]
			var cc := outline[idx[k + 2]]
			var pa := Vector3(a.x, y, a.y)
			var pb := Vector3(b.x, y, b.y)
			var pc := Vector3(cc.x, y, cc.y)
			if (pc - pa).cross(pb - pa).y < 0.0:
				var tmp := pb
				pb = pc
				pc = tmp
			_tri3([pa, pb, pc], [Vector3.UP, Vector3.UP, Vector3.UP], [1.0, 1.0, 1.0], Vector3.RIGHT, 1.5, p, 0.0)

	func _quad(pts: Array, nrms: Array, us: Array, want: Vector3, tan: Vector3, pitch: float, p: Dictionary) -> void:
		var fid := float(p.get("face", 0)) + (100.0 if p.get("blank", false) else 0.0)
		for tri: Array in [[0, 1, 2], [0, 2, 3]]:
			var a: Vector3 = pts[tri[0]]
			var b: Vector3 = pts[tri[1]]
			var cc: Vector3 = pts[tri[2]]
			var order: Array = tri
			if (cc - a).cross(b - a).dot(want) < 0.0:
				order = [tri[0], tri[2], tri[1]]
			_tri3([pts[order[0]], pts[order[1]], pts[order[2]]], [nrms[order[0]], nrms[order[1]], nrms[order[2]]],
				[us[order[0]], us[order[1]], us[order[2]]], tan, pitch, p, fid)

	func _tri3(pts: Array, nrms: Array, us: Array, tan: Vector3, pitch: float, p: Dictionary, fid: float) -> void:
		var size: Vector3 = p.get("size", Vector3(20, 20, 20))
		var shop := 1.0 if p.get("shop", false) else 0.0
		var wt := (xf.basis * tan).normalized()
		for k in 3:
			var q: Vector3 = pts[k]
			v.append(xf * q)
			n.append((xf.basis * (nrms[k] as Vector3)).normalized())
			t.append_array(PackedFloat32Array([wt.x, wt.y, wt.z, 1.0]))
			uv.append(Vector2(float(us[k]), fid))
			c0.append_array(PackedFloat32Array([q.x, q.y, q.z, shop]))
			c1.append_array(PackedFloat32Array([size.x, size.y, size.z, float(p.get("base_h", 0.0))]))
			c2.append_array(PackedFloat32Array([pitch, pitch, float(p.get("floor", DecoBuild.FLOOR_H)), base_y + float(p.get("ground", DecoBuild.GROUND_H))]))
			c3.append_array(PackedFloat32Array([base_y, 100000.0, 0.0, 0.0]))

	func commit() -> ArrayMesh:
		var mesh := ArrayMesh.new()
		if v.is_empty():
			return mesh
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = v
		arrays[Mesh.ARRAY_NORMAL] = n
		arrays[Mesh.ARRAY_TANGENT] = t
		arrays[Mesh.ARRAY_TEX_UV] = uv
		arrays[Mesh.ARRAY_CUSTOM0] = c0
		arrays[Mesh.ARRAY_CUSTOM1] = c1
		arrays[Mesh.ARRAY_CUSTOM2] = c2
		arrays[Mesh.ARRAY_CUSTOM3] = c3
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, Building.PART_FORMAT)
		return mesh

	func triangles() -> int:
		return v.size() / 3


# --- Materials ---------------------------------------------------------------------------------

static func ornament_material() -> ShaderMaterial:
	if _orn_mat == null:
		_orn_mat = ShaderMaterial.new()
		_orn_mat.shader = ORN_SHADER
	return _orn_mat


## The walls' material for a palette (DecoBoulevard.PALETTES), shared by every deco building in
## the city that wears it: building.gdshader in outline mode with the part numbers in the vertices.
static func wall_material(pal: Dictionary) -> ShaderMaterial:
	var key: String = pal.key
	if _wall_mats.has(key):
		return _wall_mats[key]
	var mat := ShaderMaterial.new()
	mat.shader = Building.SHADER
	mat.set_shader_parameter("part_attributes", true)
	mat.set_shader_parameter("uv_facade", true)
	mat.set_shader_parameter("facade_color", pal.wall)
	mat.set_shader_parameter("accent_color", pal.frame)
	mat.set_shader_parameter("facade_finish", int(pal.get("finish", Building.Finish.FLAT)))
	mat.set_shader_parameter("window_style", int(pal.get("windows", Building.WindowStyle.PUNCHED)))
	mat.set_shader_parameter("window_tint", pal.tint)
	mat.set_shader_parameter("lit_color", Color(1.0, 0.86, 0.62))
	mat.set_shader_parameter("lit_ratio", float(pal.get("lit", 0.35)))
	mat.set_shader_parameter("seed", float(absi(hash(key)) % 1000))
	mat.set_shader_parameter("roof_style", 0)
	mat.set_shader_parameter("base_color", pal.get("base", Color(0.10, 0.10, 0.11)))
	mat.set_shader_parameter("shop_span", Vector4(3.0, 3.0, 3.0, 3.0))
	mat.set_shader_parameter("tower_height", float(pal.get("tower", 0.0)))
	mat.set_shader_parameter("window_recess", 0.32)
	Building._apply_wall_texture(mat, int(pal.get("finish", Building.Finish.FLAT)), false, pal.get("wall_set", []), float(pal.get("weathering", 0.35)))
	_wall_mats[key] = mat
	return mat


static var _text_cache: Dictionary = {}

## A string's flat letters: [vertices (x right, y up, centred), indices], cached.
static func text_geo(s: String, height: float) -> Array:
	var key := "%s_%.2f" % [s, height]
	if _text_cache.has(key):
		return _text_cache[key]
	var tm := TextMesh.new()
	tm.text = s
	tm.font_size = 48
	tm.pixel_size = height / 48.0
	tm.depth = 0.0
	tm.curve_step = 2.5
	tm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tm.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var arr := tm.get_mesh_arrays()
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX] if arr.size() > 0 and arr[Mesh.ARRAY_VERTEX] != null else PackedVector3Array()
	var idx: PackedInt32Array = PackedInt32Array()
	if arr.size() > Mesh.ARRAY_INDEX and arr[Mesh.ARRAY_INDEX] != null:
		idx = arr[Mesh.ARRAY_INDEX]
	else:
		for k in verts.size():
			idx.append(k)
	var geo := [verts, idx]
	_text_cache[key] = geo
	return geo


## The width of a string's letters at a cap height (metres), for fitting.
static func text_width(s: String, height: float) -> float:
	var verts: PackedVector3Array = text_geo(s, height)[0]
	if verts.is_empty():
		return 0.0
	var lo := INF
	var hi := -INF
	for q in verts:
		lo = minf(lo, q.x)
		hi = maxf(hi, q.x)
	return hi - lo


# --- Pieces ------------------------------------------------------------------------------------

## The outline (x, z) of a w x d rect at front z = zf in the walls' order (u along the outward
## tangent): front-right, front-left, back-left, back-right. A face list [a, b, face index].
static func rect_faces(x0: float, x1: float, z0: float, z1: float) -> Array:
	return [[Vector2(x1, z1), Vector2(x0, z1), 0], [Vector2(x0, z1), Vector2(x0, z0), 1],
		[Vector2(x0, z0), Vector2(x1, z0), 2], [Vector2(x1, z0), Vector2(x1, z1), 3]]


static func rect_outline(x0: float, x1: float, z0: float, z1: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(x0, z0), Vector2(x1, z0), Vector2(x1, z1), Vector2(x0, z1)])


## A tier's walls (four faces, y0..y1) and its roof.
static func tier(w: Walls, x0: float, x1: float, z0: float, z1: float, y0: float, y1: float, p: Dictionary, roof: bool = true,
		skip: Array = []) -> void:
	var size := Vector3(x1 - x0, y1 - y0, z1 - z0)
	for f: Array in rect_faces(x0, x1, z0, z1):
		if skip.has(f[2]):
			continue
		var q := p.duplicate()
		q.face = f[2]
		q.size = size
		w.face(f[0], f[1], y0, y1, q)
	if roof:
		w.roof(rect_outline(x0, x1, z0, z1), y1, p)


## A stepped finial on a pier top: `steps` boxes, each narrower and shorter, from y.
static func finial(o: Orn, cx: float, cz: float, wx: float, wz: float, y: float, steps: int, step_h: float, colr: Color, vbase: float) -> float:
	var top := y
	for s in steps:
		var k := 1.0 - 0.24 * float(s)
		var h := step_h * (1.0 - 0.12 * float(s))
		o.aabb(Vector3(cx - wx * 0.5 * k, top, cz - wz * 0.5 * k), Vector3(cx + wx * 0.5 * k, top + h, cz + wz * 0.5 * k), colr, vbase)
		top += h
	return top


## Piers along one wall face, at every bay line from u 0 to the face's length: [a, b] its ends
## ((x, z), the walls' order), y0..y1, then a finial each. Majors (`major_every`, and both ends)
## are wider, prouder and climb higher. Returns nothing; writes into `o`.
static func piers(o: Orn, a: Vector2, b: Vector2, y0: float, y1: float, pier: Color, major: Color, major_every: int,
		finial_h: float, vbase: float, bay: float = BAY, skip_ends: bool = false) -> void:
	var d := b - a
	var len := d.length()
	var dn := d / len
	var out := Vector2(dn.y, -dn.x)
	var bays := maxi(1, roundi(len / bay))
	var pitch := len / float(bays)
	for k in bays + 1:
		var is_end := k == 0 or k == bays
		if skip_ends and is_end:
			continue
		var is_major := is_end or (major_every > 0 and k % major_every == 0)
		var pw := MAJOR_W if is_major else PIER_W
		var po := MAJOR_OUT if is_major else PIER_OUT
		var at := a + dn * (pitch * float(k))
		# The end piers sit inside the corner, not past it.
		if k == 0:
			at += dn * (pw * 0.5 - 0.01)
		elif k == bays:
			at -= dn * (pw * 0.5 - 0.01)
		var c := at + out * (po * 0.5)
		var b3 := Basis(Vector3(dn.x, 0.0, dn.y), Vector3.UP, Vector3(out.x, 0.0, out.y))
		var colr := major if is_major else pier
		o.box(Vector3(c.x, (y0 + y1) * 0.5, c.y), Vector3(pw, y1 - y0, po), colr, b3, vbase)
		var fh := finial_h * (1.6 if is_major else 1.0)
		if fh > 0.05:
			var top := y1
			for s in 3:
				var kk := 1.0 - 0.22 * float(s + 1)
				var hh := fh / 3.0
				o.box(Vector3(c.x, top + hh * 0.5, c.y), Vector3(pw * kk, hh, po * kk), colr, b3, vbase)
				top += hh


## Spandrel panels between the windows of a face: in every bay, between each row's window head
## and the next row's sill (PUNCHED: the glass is 0.27..0.77 of a storey), `out` proud.
static func spandrels(o: Orn, a: Vector2, b: Vector2, ground_y: float, floor_h: float, rows: int, colr: Color,
		pier_w: float, kind_h: float = 0.0, bay: float = BAY) -> void:
	var d := b - a
	var len := d.length()
	var dn := d / len
	var out := Vector2(dn.y, -dn.x)
	var bays := maxi(1, roundi(len / bay))
	var pitch := len / float(bays)
	var pw := pitch - pier_w - 0.06
	if pw < 0.3:
		return
	var right := Vector3(dn.x, 0.0, dn.y)
	for k in bays:
		var c := a + dn * (pitch * (float(k) + 0.5)) + out * 0.025
		for r in rows:
			var y0 := ground_y + (float(r) + 0.77) * floor_h + 0.02
			var y1 := ground_y + (float(r) + 1.27) * floor_h - 0.02
			if kind_h > 0.0:
				y1 = minf(y1, y0 + kind_h)
			o.panel(Vector3(c.x, y0, c.y) - right * (pw * 0.5), right, Vector3.UP, pw, y1 - y0, colr)


## A polyline of (x, z) and outward normals round an outline's faces from `faces` (a, b pairs),
## for bands (speed lines, friezes, copings).
static func run_of(faces: Array) -> Array:
	var pts := PackedVector2Array()
	var nrm := PackedVector2Array()
	for f: Array in faces:
		var a: Vector2 = f[0]
		var b: Vector2 = f[1]
		var d := (b - a).normalized()
		var on := Vector2(d.y, -d.x)
		pts.append(a)
		nrm.append(on)
		pts.append(b)
		nrm.append(on)
	return [pts, nrm]
