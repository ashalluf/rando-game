class_name SchoolKit
extends RefCounted
## The schools' buildings and fittings (Schools lays them out), at real size, written straight
## into a chunk's ONE school mesh and drawn by shaders/school_walls.gdshader. Pure geometry: no
## rolls, no nodes.
##
## Vertex layout (IndustrialKit's, which the boxes go through): COLOR.rgb the paint (display
## numbers), COLOR.a the kind (K_*) in 32nds, UV metres in the face's frame (x along the face from
## its left corner seen from outside, y up from the foot), UV2 = (the face's height, a parameter).
## Walls are written face by face (wall()), so each face carries its own window layout in the
## parameter: style + 16 x the number of whole bays, with UV.x zero at the first bay (the bays are
## centred on the face and the margins either side stay blank).

const K_STUCCO := 0
const K_BRICK := 1
const K_CONCRETE := 2
const K_ROOF := 3
const K_STEEL := 4
const K_GLASS := 5
const K_DOOR := 6
const K_SIDING := 7
const K_SIGN := 8
const K_LETTER := 9
const K_LED := 10
const K_MURAL := 11
const K_METAL_ROOF := 12
const K_LAMP := 13
const K_FLAG := 14
const K_BOARD := 15
const K_CMU := 16
const K_TRIM := 17
const K_VENT := 18
const KIND_COUNT := 19

## Window layouts (the wall parameter's style), and the bay pitch of each (metres).
const W_BLANK := 0
const W_CLASS := 1
const W_CLASS_YARD := 2
const W_GYM := 3
const W_AUD := 4
const W_OFFICE := 5
const W_PORTABLE := 6
const PITCH := [3.0, 9.0, 9.0, 6.0, 7.0, 4.0, 4.0]

const WHITE := Color(0.92, 0.92, 0.90)
const GALV := Color(0.62, 0.64, 0.64)
const ROOF := Color(0.62, 0.62, 0.60)
const CONCRETE := Color(0.74, 0.73, 0.70)
const CMU := Color(0.70, 0.67, 0.62)
const DARK := Color(0.10, 0.10, 0.11)
const AMBER := Color(1.0, 0.62, 0.12)
const DOOR_PAINTS := [Color(0.16, 0.30, 0.48), Color(0.52, 0.12, 0.10), Color(0.14, 0.34, 0.24), Color(0.60, 0.46, 0.18)]

## Triangles written (the checks read it).
static var tris: int = 0


static func box(st: SurfaceTool, xf: Transform3D, size: Vector3, kind: int, paint: Color, param: float = 0.0, skip: int = 32) -> void:
	IndustrialKit.box(st, xf, size, kind, paint, param, skip)
	tris += 12


static func beam(st: SurfaceTool, a: Vector3, b: Vector3, w: float, h: float, kind: int, paint: Color) -> void:
	var d := b - a
	var len := d.length()
	if len < 0.001:
		return
	var z := d / len
	var up := Vector3.UP if absf(z.y) < 0.95 else Vector3.RIGHT
	var x := up.cross(z).normalized()
	var y := z.cross(x)
	box(st, Transform3D(Basis(x, y, z), (a + b) * 0.5), Vector3(w, h, len), kind, paint, 0.0, 0)


static func post(st: SurfaceTool, at: Vector3, r: float, h: float, kind: int, paint: Color, segs: int = 8) -> void:
	IndustrialKit.cyl(st, Transform3D(Basis(), at), r, h, kind, paint, segs, true)
	tris += segs * 3


static func _col(kind: int, paint: Color) -> Color:
	return Color(paint.r, paint.g, paint.b, (float(kind) + 0.5) / 32.0)


## One triangle facing `n` (the winding is fixed to face it, LandmarkGeo's rule).
static func tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, n: Vector3, kind: int, paint: Color, uva: Vector2, uvb: Vector2, uvc: Vector2, uv2: Vector2) -> void:
	var col := _col(kind, paint)
	var pts := [a, b, c]
	var uvs := [uva, uvb, uvc]
	# Godot's front faces are clockwise seen from the front: (b - a) x (c - a) points away from it.
	if (b - a).cross(c - a).dot(n) > 0.0:
		pts = [a, c, b]
		uvs = [uva, uvc, uvb]
	for i in 3:
		st.set_normal(n)
		st.set_color(col)
		st.set_uv(uvs[i])
		st.set_uv2(uv2)
		st.add_vertex(pts[i])
	tris += 1


static func quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, kind: int, paint: Color, uva: Vector2, uvb: Vector2, uvc: Vector2, uvd: Vector2, uv2: Vector2) -> void:
	tri(st, a, b, c, n, kind, paint, uva, uvb, uvc, uv2)
	tri(st, a, c, d, n, kind, paint, uva, uvc, uvd, uv2)


## A wall face from `a` to `b` (its foot, seen from outside left to right), `h` tall, facing out
## along (b - a) x up... i.e. to the right-hand side of a -> b seen from above, turned toward
## `out`. Windows by `style`: as many whole bays of PITCH[style] as fit, centred.
static func wall(st: SurfaceTool, a: Vector3, b: Vector3, h: float, out: Vector3, kind: int, paint: Color, style: int, y0: float = 0.0) -> void:
	var len := Vector2(b.x - a.x, b.z - a.z).length()
	if len < 0.05:
		return
	var pitch: float = PITCH[style]
	var bays := int(floor((len - 0.6) / pitch)) if style != W_BLANK else 0
	if style == W_PORTABLE:
		bays = mini(bays, 3)
	var margin := (len - float(bays) * pitch) * 0.5
	var up := Vector3(0.0, h, 0.0)
	var param := float(style) + 16.0 * float(bays)
	quad(st, a, b, b + up, a + up, out.normalized(), kind, paint,
		Vector2(-margin, y0), Vector2(len - margin, y0), Vector2(len - margin, y0 + h), Vector2(-margin, y0 + h), Vector2(y0 + h, param))


## The four walls of a box building (`xf` at the middle of its foot, x along `len`, z across
## `depth`), each face its own window layout: styles = [+z, -z, +x, -x].
static func walls4(st: SurfaceTool, xf: Transform3D, len: float, depth: float, h: float, kind: int, paint: Color, styles: Array) -> void:
	var hx := len * 0.5
	var hz := depth * 0.5
	var c := [xf * Vector3(-hx, 0.0, -hz), xf * Vector3(hx, 0.0, -hz), xf * Vector3(hx, 0.0, hz), xf * Vector3(-hx, 0.0, hz)]
	var bz := xf.basis.z.normalized()
	var bx := xf.basis.x.normalized()
	# +z face, seen from outside (+z) left to right runs +x to -x... from c[2] to c[3]? Seen from
	# +z looking toward -z, +x is on the right: left is -x. So a = c[3], b = c[2].
	wall(st, c[3], c[2], h, bz, kind, paint, int(styles[0]))
	wall(st, c[1], c[0], h, -bz, kind, paint, int(styles[1]))
	wall(st, c[2], c[1], h, bx, kind, paint, int(styles[2]))
	wall(st, c[0], c[3], h, -bx, kind, paint, int(styles[3]))


## A flat roof over a box: the membrane inside a coped parapet, rooftop units, roof hatches.
static func flat_roof(st: SurfaceTool, xf: Transform3D, len: float, depth: float, h: float, kind: int, paint: Color, trim: Color, parapet: float = 0.7) -> void:
	box(st, xf * Transform3D(Basis(), Vector3(0.0, h - 0.02, 0.0)), Vector3(len - 0.4, 0.06, depth - 0.4), K_ROOF, ROOF, 0.0, 47)
	for s: float in [-1.0, 1.0]:
		box(st, xf * Transform3D(Basis(), Vector3(0.0, h + parapet * 0.5, s * (depth * 0.5 - 0.12))), Vector3(len, parapet, 0.24), kind, paint, 0.0, 32)
		box(st, xf * Transform3D(Basis(), Vector3(s * (len * 0.5 - 0.12), h + parapet * 0.5, 0.0)), Vector3(0.24, parapet, depth - 0.48), kind, paint, 0.0, 32)
		box(st, xf * Transform3D(Basis(), Vector3(0.0, h + parapet + 0.04, s * (depth * 0.5 - 0.12))), Vector3(len + 0.08, 0.08, 0.34), K_TRIM, trim)
		box(st, xf * Transform3D(Basis(), Vector3(s * (len * 0.5 - 0.12), h + parapet + 0.04, 0.0)), Vector3(0.34, 0.08, depth), K_TRIM, trim)
	var units := maxi(1, int(len / 16.0))
	for i in units:
		var x := -len * 0.5 + len * (float(i) + 0.5) / float(units)
		var z := depth * (0.15 if i % 2 == 0 else -0.12)
		box(st, xf * Transform3D(Basis(), Vector3(x, h + 0.7, z)), Vector3(2.4, 1.3, 1.7), K_STEEL, Color(0.80, 0.80, 0.78))
		box(st, xf * Transform3D(Basis(), Vector3(x + 0.4, h + 1.36, z)), Vector3(0.9, 0.04, 0.9), K_VENT, Color(0.35, 0.36, 0.37))
		# A duct down into the roof.
		box(st, xf * Transform3D(Basis(), Vector3(x - 1.6, h + 0.35, z)), Vector3(0.9, 0.6, 0.6), K_STEEL, Color(0.74, 0.75, 0.74))


## A covered walkway along a face: square steel posts every 4.5 m, a flat metal canopy with a
## fascia in the trim colour, a concrete walk under it. `a` to `b` at the wall's foot, `w` deep
## toward `out`.
static func walkway(st: SurfaceTool, a: Vector3, b: Vector3, out: Vector3, w: float, h: float, trim: Color) -> void:
	var len := a.distance_to(b)
	if len < 1.0:
		return
	var n := maxi(1, int(len / 4.5))
	for i in n + 1:
		var p := a.lerp(b, float(i) / float(n)) + out * (w - 0.2)
		box(st, Transform3D(Basis(), p + Vector3(0.0, h * 0.5, 0.0)), Vector3(0.14, h, 0.14), K_STEEL, Color(0.90, 0.90, 0.88))
	var mid := (a + b) * 0.5 + out * (w * 0.5) + Vector3(0.0, h + 0.09, 0.0)
	var x := (b - a).normalized()
	var basis := Basis(x, Vector3.UP, x.cross(Vector3.UP)).orthonormalized()
	box(st, Transform3D(basis, mid), Vector3(len + 0.3, 0.18, w), K_METAL_ROOF, Color(0.86, 0.86, 0.84), 1.0)
	box(st, Transform3D(basis, mid + out * (w * 0.5) + Vector3(0.0, -0.08, 0.0)), Vector3(len + 0.3, 0.42, 0.06), K_TRIM, trim)


## A door leaf proud of a wall (`xf` at the middle of its foot on the wall, z out): frame, a
## vision panel, a kick plate - the panel's glass is the shader's.
static func door(st: SurfaceTool, xf: Transform3D, w: float, h: float, paint: Color) -> void:
	box(st, xf * Transform3D(Basis(), Vector3(0.0, h * 0.5 + 0.02, 0.04)), Vector3(w + 0.16, h + 0.08, 0.06), K_TRIM, Color(0.84, 0.84, 0.82))
	box(st, xf * Transform3D(Basis(), Vector3(0.0, h * 0.5, 0.08)), Vector3(w, h, 0.05), K_DOOR, paint, w)


## Letters: `text` on a plane at `xf` (x along the line, y up, z out of the face), `height` tall,
## centred, written as flat triangles of `kind`.
static func letters(st: SurfaceTool, text: String, xf: Transform3D, height: float, kind: int, paint: Color, param: float = 0.0) -> float:
	var geo: Array = FreewayKit.text_geo(text, height)
	var verts: PackedVector3Array = geo[0]
	var idx: PackedInt32Array = geo[1]
	var n := xf.basis.z.normalized()
	var i := 0
	while i + 2 < idx.size():
		var a := verts[idx[i]]
		var b := verts[idx[i + 1]]
		var c := verts[idx[i + 2]]
		tri(st, xf * a, xf * b, xf * c, n, kind, paint, Vector2(a.x, a.y), Vector2(b.x, b.y), Vector2(c.x, c.y), Vector2(height, param))
		i += 3
	return float(geo[2])


# --- Buildings ------------------------------------------------------------------------------------

## A classroom wing: `xf` at the middle of its foot, x along it, +z its yard face (doors and the
## walkway), -z the street face (ribbons of windows). Stucco or brick, a coped parapet, rooftop
## units; the end walls blank (the yard end of a side wing is left primed for a mural: `mural`).
static func classroom(st: SurfaceTool, xf: Transform3D, len: float, depth: float, storeys: int, paint: Color, brick: bool, trim: Color, mural: bool, door_paint: Color) -> void:
	var h := float(storeys) * Schools.STOREY + 0.4
	var kind := K_BRICK if brick else K_STUCCO
	walls4(st, xf, len, depth, h, kind, paint, [W_CLASS_YARD, W_CLASS, W_BLANK, W_BLANK])
	flat_roof(st, xf, len, depth, h, kind, paint, trim)
	# A plinth band and, on brick, a painted fascia band at the roof (the 1960s look).
	box(st, xf * Transform3D(Basis(), Vector3(0.0, 0.15, 0.0)), Vector3(len + 0.06, 0.3, depth + 0.06), K_CONCRETE, CONCRETE, 0.0, 48)
	if brick:
		box(st, xf * Transform3D(Basis(), Vector3(0.0, h + 0.35, 0.0)), Vector3(len + 0.1, 0.7, depth + 0.1), K_TRIM, trim, 0.0, 48)
	# Doors on the yard face, one a classroom bay (the shader's bays start at the face's margin).
	var pitch: float = PITCH[W_CLASS_YARD]
	var bays := int(floor((len - 0.6) / pitch))
	var margin := (len - float(bays) * pitch) * 0.5
	for k in bays:
		var x := -len * 0.5 + margin + float(k) * pitch + 1.2
		door(st, xf * Transform3D(Basis(), Vector3(x, 0.0, depth * 0.5)), 1.0, 2.2, door_paint)
		if storeys > 1:
			door(st, xf * Transform3D(Basis(), Vector3(x, Schools.STOREY, depth * 0.5)), 1.0, 2.2, door_paint)
	# The upper floor's balcony walk and its rail (the yard side).
	if storeys > 1:
		var bal := xf * Transform3D(Basis(), Vector3(0.0, Schools.STOREY - 0.1, depth * 0.5 + Schools.WALKWAY * 0.5))
		box(st, bal, Vector3(len, 0.24, Schools.WALKWAY), K_CONCRETE, CONCRETE)
		box(st, xf * Transform3D(Basis(), Vector3(0.0, Schools.STOREY + 0.98, depth * 0.5 + Schools.WALKWAY - 0.05)), Vector3(len, 0.06, 0.06), K_STEEL, trim)
		var n := maxi(2, int(len / 1.2))
		for i in n + 1:
			var x := -len * 0.5 + len * float(i) / float(n)
			box(st, xf * Transform3D(Basis(), Vector3(x, Schools.STOREY + 0.5, depth * 0.5 + Schools.WALKWAY - 0.05)), Vector3(0.025, 0.96, 0.025), K_STEEL, trim)
		# A stair at one end.
		var sx := len * 0.5 + 0.9
		for i in 12:
			box(st, xf * Transform3D(Basis(), Vector3(sx, 0.17 + 0.33 * float(i), depth * 0.5 - 0.3 - 0.28 * float(i))), Vector3(1.4, 0.06, 0.3), K_CONCRETE, CONCRETE)
		beam(st, xf * Vector3(sx - 0.7, 1.0, depth * 0.5), xf * Vector3(sx - 0.7, Schools.STOREY + 1.0, depth * 0.5 - 3.3), 0.05, 0.05, K_STEEL, trim)
		beam(st, xf * Vector3(sx + 0.7, 1.0, depth * 0.5), xf * Vector3(sx + 0.7, Schools.STOREY + 1.0, depth * 0.5 - 3.3), 0.05, 0.05, K_STEEL, trim)
	# A primed panel on the yard end for a mural (the murals pass paints these).
	if mural:
		box(st, xf * Transform3D(Basis(), Vector3(len * 0.5 + 0.03, h * 0.45, 0.0)), Vector3(0.04, h * 0.7, depth - 1.6), K_MURAL, Color(0.93, 0.92, 0.88))
	# Downspouts at the ends.
	for s: float in [-1.0, 1.0]:
		box(st, xf * Transform3D(Basis(), Vector3(s * (len * 0.5 - 0.3), h * 0.5, -depth * 0.5 - 0.08)), Vector3(0.1, h, 0.1), K_STEEL, trim)


## The office: one storey, a glazed front with a canopy over the entry, the school's name in
## standing letters on the parapet.
static func office(st: SurfaceTool, xf: Transform3D, len: float, depth: float, paint: Color, brick: bool, trim: Color, name: String) -> void:
	var h := Schools.STOREY + 0.4
	var kind := K_BRICK if brick else K_STUCCO
	walls4(st, xf, len, depth, h, kind, paint, [W_CLASS_YARD, W_OFFICE, W_BLANK, W_BLANK])
	flat_roof(st, xf, len, depth, h, kind, paint, trim, 1.4)
	box(st, xf * Transform3D(Basis(), Vector3(0.0, 0.15, 0.0)), Vector3(len + 0.06, 0.3, depth + 0.06), K_CONCRETE, CONCRETE, 0.0, 48)
	# The entry canopy on two round columns.
	var c := xf * Transform3D(Basis(), Vector3(len * 0.25, 3.25, -depth * 0.5 - 1.6))
	box(st, c, Vector3(6.0, 0.3, 3.2), K_METAL_ROOF, Color(0.86, 0.86, 0.84), 1.0)
	box(st, c * Transform3D(Basis(), Vector3(0.0, 0.0, -1.6)), Vector3(6.0, 0.5, 0.06), K_TRIM, trim)
	for s: float in [-1.0, 1.0]:
		post(st, xf * Vector3(len * 0.25 + s * 2.6, 0.0, -depth * 0.5 - 2.9), 0.12, 3.15, K_TRIM, WHITE)
	door(st, xf * Transform3D(Basis(Vector3.UP, PI), Vector3(len * 0.25, 0.0, -depth * 0.5)), 1.8, 2.3, Color(0.30, 0.34, 0.38))
	# The name over the glazing, standing letters on the parapet face.
	var lh := clampf(len / float(maxi(name.length(), 1)) * 1.1, 0.35, 0.62)
	letters(st, name, xf * Transform3D(Basis(Vector3.UP, PI), Vector3(0.0, h + 0.62, -depth * 0.5 - 0.04)), lh, K_LETTER, trim.lightened(0.1))


## The gym: a tall box with high clerestory windows, a low-pitched standing-seam roof, the mascot
## painted big on the front ("HOME OF THE ...").
static func gym(st: SurfaceTool, xf: Transform3D, len: float, depth: float, paint: Color, brick: bool, trim: Color, mascot: String) -> void:
	var h := Schools.GYM_H
	var kind := K_BRICK if brick else K_STUCCO
	walls4(st, xf, len, depth, h, kind, paint, [W_GYM, W_GYM, W_BLANK, W_BLANK])
	_gable_roof(st, xf, len, depth, h, 2.6, paint, kind)
	box(st, xf * Transform3D(Basis(), Vector3(0.0, 0.2, 0.0)), Vector3(len + 0.06, 0.4, depth + 0.06), K_CONCRETE, CONCRETE, 0.0, 48)
	# A band of the school colour under the eaves, the mascot over the doors on the end (+x).
	for s: float in [-1.0, 1.0]:
		box(st, xf * Transform3D(Basis(), Vector3(0.0, h - 0.5, s * (depth * 0.5 + 0.03))), Vector3(len, 0.8, 0.06), K_TRIM, trim)
	var front := xf * Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(len * 0.5 + 0.06, 0.0, 0.0))
	letters(st, "HOME OF THE", front * Transform3D(Basis(), Vector3(0.0, h - 2.6, 0.0)), 0.9, K_LETTER, trim)
	letters(st, mascot, front * Transform3D(Basis(), Vector3(0.0, h - 4.6, 0.0)), 1.6, K_LETTER, trim)
	for s: float in [-1.0, 1.0]:
		door(st, front * Transform3D(Basis(), Vector3(s * 3.0, 0.0, 0.0)), 1.9, 2.4, Color(0.70, 0.71, 0.72))
	var cz := xf * Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(len * 0.5 + 1.4, 3.2, 0.0))
	box(st, cz, Vector3(9.0, 0.25, 2.8), K_METAL_ROOF, Color(0.86, 0.86, 0.84), 1.0)


## A gable roof of standing-seam metal over a box (ridge along x), with the gable ends closed.
static func _gable_roof(st: SurfaceTool, xf: Transform3D, len: float, depth: float, h: float, rise: float, paint: Color, kind: int) -> void:
	var o := 0.5
	var hx := len * 0.5 + o
	var hz := depth * 0.5 + o
	var drop := rise * o / (depth * 0.5)
	var e0 := xf * Vector3(-hx, h - drop, -hz)
	var e1 := xf * Vector3(hx, h - drop, -hz)
	var r0 := xf * Vector3(-hx, h + rise, 0.0)
	var r1 := xf * Vector3(hx, h + rise, 0.0)
	var f0 := xf * Vector3(-hx, h - drop, hz)
	var f1 := xf * Vector3(hx, h - drop, hz)
	var slope := Vector2(hz, rise + drop).length()
	var n0 := xf.basis * Vector3(0.0, hz, -(rise + drop)).normalized()
	var n1 := xf.basis * Vector3(0.0, hz, rise + drop).normalized()
	var uv2 := Vector2(slope, 0.0)
	quad(st, e0, e1, r1, r0, n0.normalized(), K_METAL_ROOF, ROOF, Vector2(0, 0), Vector2(len, 0), Vector2(len, slope), Vector2(0, slope), uv2)
	quad(st, f1, f0, r0, r1, n1.normalized(), K_METAL_ROOF, ROOF, Vector2(0, 0), Vector2(len, 0), Vector2(len, slope), Vector2(0, slope), uv2)
	# Gable ends (the wall's own finish).
	for s: float in [-1.0, 1.0]:
		var a := xf * Vector3(s * len * 0.5, h, -depth * 0.5)
		var b := xf * Vector3(s * len * 0.5, h, depth * 0.5)
		var c := xf * Vector3(s * len * 0.5, h + rise, 0.0)
		tri(st, a, b, c, (xf.basis.x * s).normalized(), kind, paint, Vector2(0, h), Vector2(depth, h), Vector2(depth * 0.5, h + rise), Vector2(h + rise, 0.0))
	# A fascia board along the eaves.
	for s: float in [-1.0, 1.0]:
		box(st, xf * Transform3D(Basis(), Vector3(0.0, h - drop - 0.1, s * hz)), Vector3(len + o * 2.0, 0.3, 0.05), K_TRIM, WHITE)


## The auditorium: a blank-walled box with tall slot windows, a glazed lobby and canopy on the
## street, the fly tower rising over the stage at the back, the school's name on the tower.
static func auditorium(st: SurfaceTool, xf: Transform3D, len: float, depth: float, paint: Color, brick: bool, trim: Color, name: String) -> void:
	var kind := K_BRICK if brick else K_STUCCO
	var h := Schools.AUD_H
	walls4(st, xf, len, depth, h, kind, paint, [W_BLANK, W_AUD, W_AUD, W_AUD])
	flat_roof(st, xf, len, depth, h, kind, paint, trim, 0.9)
	box(st, xf * Transform3D(Basis(), Vector3(0.0, 0.15, 0.0)), Vector3(len + 0.06, 0.3, depth + 0.06), K_CONCRETE, CONCRETE, 0.0, 48)
	# The fly tower over the back third.
	var fd := minf(13.0, depth * 0.36)
	var fx := xf * Transform3D(Basis(), Vector3(0.0, 0.0, depth * 0.5 - fd * 0.5 - 0.6))
	walls4(st, fx * Transform3D(Basis(), Vector3(0.0, h, 0.0)), len - 2.0, fd, Schools.FLY_H - h, kind, paint, [W_BLANK, W_BLANK, W_BLANK, W_BLANK])
	flat_roof(st, fx, len - 2.0, fd, Schools.FLY_H, kind, paint, trim, 0.6)
	# The lobby: a glass box in front with a deep canopy.
	var lob := xf * Transform3D(Basis(), Vector3(0.0, 0.0, -depth * 0.5 - 2.2))
	box(st, lob * Transform3D(Basis(), Vector3(0.0, 2.1, 0.0)), Vector3(len * 0.6, 4.2, 4.4), K_GLASS, Color(0.3, 0.34, 0.38), 0.0, 32)
	box(st, lob * Transform3D(Basis(), Vector3(0.0, 4.35, -0.8)), Vector3(len * 0.8, 0.3, 6.2), K_METAL_ROOF, Color(0.86, 0.86, 0.84), 1.0)
	box(st, lob * Transform3D(Basis(), Vector3(0.0, 4.2, -3.9)), Vector3(len * 0.8, 0.6, 0.06), K_TRIM, trim)
	for s: float in [-1.0, 0.0, 1.0]:
		post(st, xf * Vector3(s * len * 0.36, 0.0, -depth * 0.5 - 5.6), 0.13, 4.2, K_TRIM, WHITE)
	# The name across the tower's street face.
	var lh := clampf((len - 4.0) / float(maxi(name.length(), 1)) * 1.15, 0.5, 1.3)
	letters(st, name, fx * Transform3D(Basis(Vector3.UP, PI), Vector3(0.0, Schools.FLY_H - 2.4, -fd * 0.5 - 0.04)), lh, K_LETTER, trim.lightened(0.15))
	letters(st, "AUDITORIUM", fx * Transform3D(Basis(Vector3.UP, PI), Vector3(0.0, Schools.FLY_H - 2.4 - lh * 1.4, -fd * 0.5 - 0.04)), lh * 0.6, K_LETTER, trim.lightened(0.15))


## A portable classroom: on concrete blocks behind a skirt, T1-11 siding, small windows, a door at
## one end of the long side (+z), a wall-mounted heat pump, a low metal roof with an overhang, and
## a ramp with rails along the +z side down to the yard. `xf` at the middle of its foot.
static func portable(st: SurfaceTool, xf: Transform3D, paint: Color, trim: Color, door_paint: Color, number: int) -> void:
	var L := Schools.PORTABLE.x
	var W := Schools.PORTABLE.y
	var r := Schools.PORTABLE_RISE
	var h := 3.0
	# The skirt round the blocks.
	box(st, xf * Transform3D(Basis(), Vector3(0.0, r * 0.5, 0.0)), Vector3(L - 0.2, r, W - 0.2), K_SIDING, paint.darkened(0.12), 0.0, 48)
	var body := xf * Transform3D(Basis(), Vector3(0.0, r, 0.0))
	walls4(st, body, L, W, h, K_SIDING, paint, [W_PORTABLE, W_PORTABLE, W_BLANK, W_BLANK])
	# Roof: a shallow mono-slope deck with an overhang, its fascia in the trim colour.
	box(st, body * Transform3D(Basis(), Vector3(0.0, h + 0.12, 0.0)), Vector3(L + 0.5, 0.2, W + 0.6), K_METAL_ROOF, Color(0.80, 0.80, 0.78), 1.0)
	box(st, body * Transform3D(Basis(), Vector3(0.0, h + 0.06, 0.0)), Vector3(L + 0.56, 0.26, W + 0.66), K_TRIM, trim, 0.0, 48)
	# Corner trim boards.
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			box(st, body * Transform3D(Basis(), Vector3(sx * (L * 0.5 - 0.04), h * 0.5, sz * (W * 0.5 - 0.04))), Vector3(0.12, h, 0.12), K_TRIM, trim)
	# The heat pump on the end wall (-x) and its louvres.
	var hp := body * Transform3D(Basis(), Vector3(-L * 0.5 - 0.42, 1.2, 0.0))
	box(st, hp, Vector3(0.8, 2.2, 1.05), K_STEEL, Color(0.84, 0.82, 0.76))
	box(st, hp * Transform3D(Basis(), Vector3(-0.41, -0.3, 0.0)), Vector3(0.02, 1.0, 0.8), K_VENT, Color(0.4, 0.4, 0.4))
	# Door near the +x end of the +z side, its landing and the ramp along the side.
	var dx := L * 0.5 - 1.4
	door(st, body * Transform3D(Basis(), Vector3(dx, 0.0, W * 0.5)), 0.95, 2.1, door_paint)
	box(st, body * Transform3D(Basis(), Vector3(dx, -0.04, W * 0.5 + 0.8)), Vector3(1.9, 0.08, 1.6), K_TRIM, Color(0.55, 0.55, 0.53))
	var rl := r * 12.0
	var zr := W * 0.5 + 0.25 + Schools.RAMP_W * 0.5
	var a := xf * Vector3(dx - 0.95, r - 0.04, zr)
	var b := xf * Vector3(dx - 0.95 - rl, 0.03, zr)
	var d := b - a
	var len := d.length()
	var along := d / len
	var zb := xf.basis.z.normalized()
	var basis := Basis(along, zb.cross(along).normalized(), zb)
	box(st, Transform3D(basis, (a + b) * 0.5), Vector3(len, 0.08, Schools.RAMP_W), K_TRIM, Color(0.55, 0.55, 0.53))
	for s: float in [-1.0, 1.0]:
		var off := xf.basis.z.normalized() * (s * Schools.RAMP_W * 0.5)
		beam(st, a + off + Vector3(0, 0.9, 0), b + off + Vector3(0, 0.9, 0), 0.045, 0.045, K_STEEL, Color(0.86, 0.86, 0.84))
		for i in 4:
			var p := a.lerp(b, float(i) / 3.0) + off
			box(st, Transform3D(Basis(), p + Vector3(0.0, 0.45, 0.0)), Vector3(0.05, 0.9, 0.05), K_STEEL, Color(0.86, 0.86, 0.84))
	# The room number by the door.
	letters(st, "%d" % number, body * Transform3D(Basis(), Vector3(dx, 2.45, W * 0.5 + 0.02)), 0.28, K_LETTER, DARK)



## The marquee sign by the entry: a brick base, a cabinet in the school colour with the name on
## both faces, an LED message board under it. `xf` at the middle of its foot, x along it.
static func marquee(st: SurfaceTool, xf: Transform3D, name: String, kind_line: String, message: String, colour: Color, brick_paint: Color) -> void:
	var w := 3.6
	box(st, xf * Transform3D(Basis(), Vector3(0.0, 0.5, 0.0)), Vector3(w + 0.6, 1.0, 0.9), K_BRICK, brick_paint)
	box(st, xf * Transform3D(Basis(), Vector3(0.0, 1.04, 0.0)), Vector3(w + 0.75, 0.08, 1.0), K_CONCRETE, CONCRETE)
	var cab := xf * Transform3D(Basis(), Vector3(0.0, 2.05, 0.0))
	box(st, cab, Vector3(w, 1.9, 0.36), K_SIGN, colour)
	box(st, cab * Transform3D(Basis(), Vector3(0.0, 1.0, 0.0)), Vector3(w + 0.1, 0.1, 0.42), K_TRIM, WHITE)
	box(st, cab * Transform3D(Basis(), Vector3(0.0, -0.98, 0.0)), Vector3(w + 0.1, 0.06, 0.42), K_TRIM, WHITE)
	for s: float in [-1.0, 1.0]:
		var face := cab * Transform3D(Basis(Vector3.UP, 0.0 if s > 0.0 else PI), Vector3(0.0, 0.0, 0.0)) * Transform3D(Basis(), Vector3(0.0, 0.0, 0.19))
		var lh := clampf((w - 0.4) / float(maxi(name.length(), 1)) * 1.5, 0.16, 0.32)
		letters(st, name, face * Transform3D(Basis(), Vector3(0.0, 0.62, 0.0)), lh, K_LETTER, WHITE)
		letters(st, kind_line, face * Transform3D(Basis(), Vector3(0.0, 0.62 - lh * 1.25, 0.0)), lh * 0.62, K_LETTER, WHITE)
		# The LED board's dark face, and its message.
		box(st, face * Transform3D(Basis(), Vector3(0.0, -0.42, 0.005)), Vector3(w - 0.3, 0.72, 0.01), K_LED, DARK, 0.0, 48)
		var mh := clampf((w - 0.6) / float(maxi(message.length(), 1)) * 1.45, 0.12, 0.3)
		letters(st, message, face * Transform3D(Basis(), Vector3(0.0, -0.42, 0.012)), mh, K_LED, AMBER, 1.0)


## A flagpole with the flag out (it waves in the shader): `at` its foot.
static func flagpole(st: SurfaceTool, at: Vector3, h: float, toward: Vector3) -> void:
	box(st, Transform3D(Basis(), at + Vector3(0.0, 0.15, 0.0)), Vector3(1.0, 0.3, 1.0), K_CONCRETE, CONCRETE)
	IndustrialKit.cyl(st, Transform3D(Basis(), at + Vector3(0.0, 0.3, 0.0)), 0.075, h, K_STEEL, Color(0.82, 0.83, 0.84), 10, true)
	tris += 30
	box(st, Transform3D(Basis(), at + Vector3(0.0, h + 0.38, 0.0)), Vector3(0.16, 0.16, 0.16), K_TRIM, Color(0.85, 0.72, 0.30))
	var x := toward.normalized()
	var fw := 1.83
	var fh := 0.96
	var top := at + Vector3(0.0, h + 0.2, 0.0)
	var a := top - Vector3(0.0, fh, 0.0)
	var b := a + x * fw
	var c := top + x * fw
	var n := x.cross(Vector3.UP).normalized()
	# Two sided (the waving card is seen from both sides).
	quad(st, a, b, c, top, n, K_FLAG, WHITE, Vector2(0, 0), Vector2(fw, 0), Vector2(fw, fh), Vector2(0, fh), Vector2(fh, 0.0))
	quad(st, b, a, top, c, -n, K_FLAG, WHITE, Vector2(fw, 0), Vector2(0, 0), Vector2(0, fh), Vector2(fw, fh), Vector2(fh, 1.0))


## The scoreboard behind an end zone: two steel legs, the board (HOME / GUEST, the clock, the
## quarter), the mascot over it. `xf` at the middle of its foot, z toward the field.
static func scoreboard(st: SurfaceTool, xf: Transform3D, colour: Color, mascot: String) -> void:
	var w := 9.0
	var y0 := 4.0
	for s: float in [-1.0, 1.0]:
		post(st, xf * Vector3(s * 3.0, 0.0, -0.3), 0.18, y0 + 3.6, K_STEEL, Color(0.32, 0.33, 0.34))
	var board := xf * Transform3D(Basis(), Vector3(0.0, y0 + 1.6, 0.0))
	box(st, board, Vector3(w, 3.2, 0.5), K_BOARD, DARK)
	box(st, board * Transform3D(Basis(), Vector3(0.0, 2.15, 0.0)), Vector3(w, 1.1, 0.4), K_SIGN, colour)
	var face := board * Transform3D(Basis(), Vector3(0.0, 0.0, 0.26))
	letters(st, mascot, board * Transform3D(Basis(), Vector3(0.0, 2.15, 0.21)), 0.62, K_LETTER, WHITE)
	letters(st, "HOME", face * Transform3D(Basis(), Vector3(-3.0, 1.05, 0.0)), 0.42, K_LETTER, WHITE)
	letters(st, "GUEST", face * Transform3D(Basis(), Vector3(3.0, 1.05, 0.0)), 0.42, K_LETTER, WHITE)
	letters(st, "21", face * Transform3D(Basis(), Vector3(-3.0, 0.0, 0.0)), 1.0, K_LED, AMBER, 1.0)
	letters(st, "14", face * Transform3D(Basis(), Vector3(3.0, 0.0, 0.0)), 1.0, K_LED, AMBER, 1.0)
	letters(st, "12:00", face * Transform3D(Basis(), Vector3(0.0, 0.25, 0.0)), 0.7, K_LED, Color(1.0, 0.25, 0.12), 1.0)
	letters(st, "QTR 3", face * Transform3D(Basis(), Vector3(0.0, -0.9, 0.0)), 0.36, K_LED, AMBER, 1.0)


## A stadium light standard: a tapered steel pole `h` high, a crossarm and `heads` luminaires in
## rows aimed at `aim`; the lenses glow after dark on a game night (`lit`).
static func light_standard(st: SurfaceTool, at: Vector3, aim: Vector2, h: float, heads: int, lit: bool) -> void:
	post(st, at, 0.32, 1.0, K_CONCRETE, CONCRETE, 10)
	post(st, at + Vector3(0.0, 1.0, 0.0), 0.24, h * 0.55, K_STEEL, GALV, 10)
	post(st, at + Vector3(0.0, 1.0 + h * 0.55, 0.0), 0.17, h * 0.45 - 1.0, K_STEEL, GALV, 10)
	var dir := aim - Vector2(at.x, at.z)
	if dir.length() < 0.1:
		dir = Vector2(1.0, 0.0)
	dir = dir.normalized()
	var x := Vector3(-dir.y, 0.0, dir.x)
	var fwd := Vector3(dir.x, 0.0, dir.y)
	var cols := mini(heads, 5)
	var rows := ceili(float(heads) / float(cols))
	var w := float(cols) * 0.8
	for r in rows:
		beam(st, at + Vector3(0.0, h - 0.4 + 0.9 * float(r), 0.0) - x * w * 0.5 + fwd * 0.2, at + Vector3(0.0, h - 0.4 + 0.9 * float(r), 0.0) + x * w * 0.5 + fwd * 0.2, 0.12, 0.12, K_STEEL, GALV)
	var basis := Basis(x, deg_to_rad(-30.0)) * Basis(x, Vector3.UP, -fwd).orthonormalized()
	var k := 0
	for r in rows:
		for c in cols:
			if k >= heads:
				break
			var p := at + Vector3(0.0, h - 0.1 + 0.9 * float(r), 0.0) + x * (-w * 0.5 + 0.4 + 0.8 * float(c)) + fwd * 0.45
			box(st, Transform3D(basis, p), Vector3(0.66, 0.62, 0.3), K_STEEL, Color(0.30, 0.31, 0.32))
			box(st, Transform3D(basis, p + basis.z * -0.16), Vector3(0.56, 0.52, 0.01), K_LAMP, Color(1.0, 0.97, 0.92), 0.0 if lit else 1.0, 0)
			k += 1
	# The electrical cabinet at the foot.
	box(st, Transform3D(Basis(x, Vector3.UP, x.cross(Vector3.UP)), at + Vector3(0.0, 0.7, 0.0) - fwd * 0.6), Vector3(0.7, 1.4, 0.4), K_STEEL, Color(0.62, 0.64, 0.62))


## A lunch table with its attached benches (the steel-frame school kind), `xf` at its middle.
static func lunch_table(st: SurfaceTool, xf: Transform3D, paint: Color) -> void:
	box(st, xf * Transform3D(Basis(), Vector3(0.0, 0.74, 0.0)), Vector3(2.4, 0.05, 0.76), K_STEEL, paint)
	for s: float in [-1.0, 1.0]:
		box(st, xf * Transform3D(Basis(), Vector3(0.0, 0.44, s * 0.68)), Vector3(2.4, 0.04, 0.3), K_STEEL, paint)
		box(st, xf * Transform3D(Basis(), Vector3(s * 0.95, 0.37, 0.0)), Vector3(0.06, 0.74, 1.6), K_STEEL, Color(0.34, 0.35, 0.36))
