class_name MeetKit
## The kerb at a lowrider meet (LowriderMeet._dress()): folding quad camp chairs and wheeled
## coolers, built in code at real size into one vertex-coloured SurfaceTool per meet. A chair
## faces -Z with its back toward +Z, its seat SEAT_Y over the ground (CrowdLife.SEAT_HEIGHT, so
## the crowd life's SIT lands on it); a cooler's lid is at about 0.45 m.

const SEAT_Y := 0.45
## Chair fabrics (sRGB): navy, black, red, forest, royal blue, grey, a faded camo olive.
const FABRICS := [Color(0.10, 0.13, 0.26), Color(0.06, 0.06, 0.07), Color(0.55, 0.08, 0.07),
	Color(0.10, 0.24, 0.14), Color(0.12, 0.22, 0.55), Color(0.32, 0.33, 0.35), Color(0.33, 0.33, 0.22)]
## Cooler bodies (sRGB): red, blue, white, teal; the lid is always white.
const COOLERS := [Color(0.70, 0.10, 0.08), Color(0.12, 0.28, 0.62), Color(0.86, 0.86, 0.84), Color(0.10, 0.48, 0.50)]
const FRAME := Color(0.08, 0.08, 0.09)
const LID := Color(0.90, 0.90, 0.88)
const HANDLE := Color(0.12, 0.12, 0.13)

static var _material: StandardMaterial3D


static func material() -> StandardMaterial3D:
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.vertex_color_use_as_albedo = true
		_material.vertex_color_is_srgb = true
		_material.roughness = 0.78
	return _material


## A box from `a` to `b` (its local corners) under `xf`, flat-shaded, outward faces.
static func box(st: SurfaceTool, xf: Transform3D, a: Vector3, b: Vector3, c: Color) -> void:
	var lo := Vector3(minf(a.x, b.x), minf(a.y, b.y), minf(a.z, b.z))
	var hi := Vector3(maxf(a.x, b.x), maxf(a.y, b.y), maxf(a.z, b.z))
	var faces := [
		[Vector3.RIGHT, [Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(hi.x, hi.y, hi.z), Vector3(hi.x, lo.y, hi.z)]],
		[Vector3.LEFT, [Vector3(lo.x, lo.y, hi.z), Vector3(lo.x, hi.y, hi.z), Vector3(lo.x, hi.y, lo.z), Vector3(lo.x, lo.y, lo.z)]],
		[Vector3.UP, [Vector3(lo.x, hi.y, lo.z), Vector3(lo.x, hi.y, hi.z), Vector3(hi.x, hi.y, hi.z), Vector3(hi.x, hi.y, lo.z)]],
		[Vector3.DOWN, [Vector3(lo.x, lo.y, hi.z), Vector3(lo.x, lo.y, lo.z), Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, lo.y, hi.z)]],
		[Vector3.BACK, [Vector3(hi.x, lo.y, hi.z), Vector3(hi.x, hi.y, hi.z), Vector3(lo.x, hi.y, hi.z), Vector3(lo.x, lo.y, hi.z)]],
		[Vector3.FORWARD, [Vector3(lo.x, lo.y, lo.z), Vector3(lo.x, hi.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(hi.x, lo.y, lo.z)]],
	]
	for f: Array in faces:
		quad(st, xf, f[1][0], f[1][1], f[1][2], f[1][3], f[0], c)


## A quad (two triangles) turned to face `n` (local), whatever the corners' order.
static func quad(st: SurfaceTool, xf: Transform3D, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, n: Vector3, c: Color) -> void:
	var w: Array[Vector3] = [xf * p0, xf * p1, xf * p2, xf * p3]
	var nw := (xf.basis * n).normalized()
	var face := (w[1] - w[0]).cross(w[2] - w[0])
	var order: Array = [0, 1, 2, 0, 2, 3] if face.dot(nw) < 0.0 else [0, 2, 1, 0, 3, 2]
	for i: int in order:
		st.set_color(c)
		st.set_normal(nw)
		st.add_vertex(w[i])


## A thin strut from `a` to `b` (local) of square section `t`.
static func strut(st: SurfaceTool, xf: Transform3D, a: Vector3, b: Vector3, t: float, c: Color) -> void:
	var d := b - a
	var l := d.length()
	if l < 0.001:
		return
	var y := d / l
	var x := y.cross(Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	var z := x.cross(y)
	var bx := Transform3D(Basis(x, y, z), a)
	box(st, xf * bx, Vector3(-t * 0.5, 0.0, -t * 0.5), Vector3(t * 0.5, l, t * 0.5), c)


## A folding quad camp chair: crossed tube legs at the sides, front and back, a sagging seat,
## a reclined back, arm straps with a cup holder ring on the right.
static func chair(st: SurfaceTool, xf: Transform3D, fabric: Color) -> void:
	var w := 0.27
	var d := 0.24
	var t := 0.018
	# The legs: four uprights from the feet to the seat rails, crossed at the sides and the back.
	var feet := [Vector3(-w, 0.0, -d), Vector3(w, 0.0, -d), Vector3(-w, 0.0, d), Vector3(w, 0.0, d)]
	for f: Vector3 in feet:
		strut(st, xf, f, f + Vector3(0.0, SEAT_Y + 0.02, 0.0), t, FRAME)
	for sx: float in [-w, w]:
		strut(st, xf, Vector3(sx, 0.02, -d), Vector3(sx, SEAT_Y - 0.04, d), t, FRAME)
		strut(st, xf, Vector3(sx, 0.02, d), Vector3(sx, SEAT_Y - 0.04, -d), t, FRAME)
	strut(st, xf, Vector3(-w, 0.02, d), Vector3(w, SEAT_Y - 0.04, d), t, FRAME)
	strut(st, xf, Vector3(w, 0.02, d), Vector3(-w, SEAT_Y - 0.04, d), t, FRAME)
	# The seat: three strips sagging to the middle.
	var sag := [0.0, -0.035, 0.0]
	for i in 2:
		var x0 := lerpf(-w, w, float(i) / 2.0)
		var x1 := lerpf(-w, w, float(i + 1) / 2.0)
		var y0 := SEAT_Y + float(sag[i])
		var y1 := SEAT_Y + float(sag[i + 1])
		quad(st, xf, Vector3(x0, y0, -d), Vector3(x1, y1, -d), Vector3(x1, y1 - 0.02, d), Vector3(x0, y0 - 0.02, d), Vector3.UP, fabric)
		quad(st, xf, Vector3(x0, y0 - 0.01, -d), Vector3(x1, y1 - 0.01, -d), Vector3(x1, y1 - 0.03, d), Vector3(x0, y0 - 0.03, d), Vector3.DOWN, fabric * 0.7)
	# The back: two uprights leaning back and the panel between them, both faces.
	var top := Vector3(0.0, SEAT_Y + 0.52, d + 0.14)
	for sx: float in [-w, w]:
		strut(st, xf, Vector3(sx, SEAT_Y - 0.02, d), Vector3(sx, top.y, top.z), t, FRAME)
	var b0 := Vector3(-w, SEAT_Y + 0.03, d + 0.01)
	var b1 := Vector3(w, SEAT_Y + 0.03, d + 0.01)
	var b2 := Vector3(w, top.y - 0.02, top.z - 0.004)
	var b3 := Vector3(-w, top.y - 0.02, top.z - 0.004)
	var lean := (b3 - b0).cross(b1 - b0).normalized()
	quad(st, xf, b0, b1, b2, b3, -lean if lean.z > 0.0 else lean, fabric)
	quad(st, xf, b0 + Vector3(0, 0, 0.008), b1 + Vector3(0, 0, 0.008), b2 + Vector3(0, 0, 0.008), b3 + Vector3(0, 0, 0.008),
		lean if lean.z > 0.0 else -lean, fabric * 0.75)
	# Arms: a strap over a tube on each side, the cup holder ring on the right.
	for sx: float in [-w, w]:
		strut(st, xf, Vector3(sx, SEAT_Y + 0.17, -d + 0.02), Vector3(sx, SEAT_Y + 0.20, d + 0.06), t, FRAME)
		box(st, xf, Vector3(sx - 0.035, SEAT_Y + 0.185, -d + 0.03), Vector3(sx + 0.035, SEAT_Y + 0.2, d + 0.03), fabric * 0.85)
	var ring := Vector3(w + 0.07, SEAT_Y + 0.17, -d + 0.07)
	box(st, xf, ring + Vector3(-0.045, -0.06, -0.045), ring + Vector3(0.045, 0.0, 0.045), fabric * 0.8)


## A wheeled picnic cooler: a body in its colour, a white lid with a hinge line, end handles,
## two wheels at the back and the tow handle folded down.
static func cooler(st: SurfaceTool, xf: Transform3D, body: Color) -> void:
	var w := 0.30
	var d := 0.20
	var h := 0.38
	box(st, xf, Vector3(-w, 0.04, -d), Vector3(w, h, d), body)
	box(st, xf, Vector3(-w - 0.012, h, -d - 0.012), Vector3(w + 0.012, h + 0.07, d + 0.012), LID)
	box(st, xf, Vector3(-w * 0.4, h + 0.07, -d * 0.35), Vector3(w * 0.4, h + 0.085, d * 0.35), LID * 0.92)
	for sx: float in [-1.0, 1.0]:
		box(st, xf, Vector3(sx * w, h - 0.12, -0.06), Vector3(sx * (w + 0.03), h - 0.08, 0.06), HANDLE)
		box(st, xf, Vector3(sx * (w - 0.02) - 0.03, 0.0, d - 0.08), Vector3(sx * (w - 0.02) + 0.03, 0.12, d + 0.04), HANDLE)
	box(st, xf, Vector3(-w * 0.6, 0.12, d), Vector3(w * 0.6, 0.15, d + 0.03), HANDLE)
