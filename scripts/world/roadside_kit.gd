class_name RoadsideKit
extends RefCounted
## The roadside pads' hardware (Roadside): the geometry writer every pad draws with, and the
## pieces a pad repeats - fuel dispensers, vacuum stations, tyres, drive-thru menu boards and
## speaker posts, the air machine, the ice chest and the propane cage - built once in code at
## real size, each one MultiMesh a kind a chunk. Everything is on ONE shader,
## shaders/roadside.gdshader: what a face is rides in its vertex colour's alpha (K_* / 20), its
## roughness and metalness in UV2 (see the shader's header). Colours are authored sRGB.

const K_FIXED := 0
const K_STEEL := 1
const K_CONCRETE := 2
const K_STUCCO := 3
const K_ROOM := 4
const K_LIGHTBOX := 5
const K_SOFFIT := 6
const K_DIGIT := 7
const K_NEON := 8
const K_RUBBER := 9
const K_SCREEN := 10
const K_CLOTH := 11
const K_CHROME := 12
const K_GLASS := 13
const K_MENU := 14
const K_BULB := 15
const K_SIGNPAINT := 16
const K_ROLLUP := 17
const K_GLAZE := 18
const K_PAINT := 20

## Room kinds a shop window traces (the shader's rs_room()).
enum Room { STORE, DINER, BAY, DINING, TUNNEL, STAND }

const RM_PAINT := Vector2(0.55, 0.0)
const RM_MATTE := Vector2(0.85, 0.0)
const RM_STEEL := Vector2(0.35, 0.85)
const RM_PLASTIC := Vector2(0.4, 0.0)
const RM_RUBBER := Vector2(0.8, 0.0)

static var _material: ShaderMaterial
static var _meshes: Dictionary = {}


## A colour with a face code (K_*). Never alpha 1 unless the face is the instance's paint.
static func c(col: Color, k: int) -> Color:
	return Color(col.r, col.g, col.b, float(k) / 20.0)


## The instance's paint (a MultiMesh piece's brand colour, INSTANCE_CUSTOM.rgb).
static func paint() -> Color:
	return Color(1.0, 1.0, 1.0, 1.0)


static func material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = load("res://shaders/roadside.gdshader")
	return _material


## The geometry writer: a SurfaceTool and the frame its coordinates are in (a pad's frame: x along
## the street, -z toward it, y up from the pad's floor; or a piece's own frame).
class Pen:
	var st: SurfaceTool
	var xf: Transform3D
	var tris := 0

	func _init(surface: SurfaceTool, frame: Transform3D) -> void:
		st = surface
		xf = frame

	func at(p: Vector3) -> Vector3:
		return xf * p

	## A box (chamfered edges when `bevel` > 0) centred at `c` in the frame, turned by `rot`.
	func box(c: Vector3, size: Vector3, col: Color, rm: Vector2 = RM_PAINT, bevel: float = 0.0, rot: Basis = Basis()) -> void:
		StreetClutter._bbox(st, xf * Transform3D(rot, c), size, bevel, col, rm)
		tris += 44 if bevel > 0.0 else 12

	## A capped cylinder up the frame's y from `base` (along `rot`'s y).
	func cyl(base: Vector3, r0: float, r1: float, h: float, col: Color, rm: Vector2 = RM_PAINT, sides: int = 12, rot: Basis = Basis()) -> void:
		StreetClutter._cyl(st, xf * Transform3D(rot, base), r0, r1, h, col, rm, sides)
		tris += sides * 4

	func tube(path: Array, r: float, col: Color, rm: Vector2 = RM_RUBBER, sides: int = 6) -> void:
		var pts: Array = []
		for p: Vector3 in path:
			pts.append(xf * p)
		StreetClutter._tube(st, pts, r, sides, col, rm)
		tris += (path.size() - 1) * sides * 2

	func quad(a: Vector3, b: Vector3, cc: Vector3, d: Vector3, want: Vector3, col: Color, rm: Vector2 = RM_PAINT) -> void:
		StreetClutter._quad(st, xf * a, xf * b, xf * cc, xf * d, xf.basis * want, col, rm)
		tris += 2

	func tri(a: Vector3, b: Vector3, cc: Vector3, want: Vector3, col: Color, rm: Vector2 = RM_PAINT) -> void:
		StreetClutter._tri(st, xf * a, xf * b, xf * cc, xf.basis * want, col, rm)
		tris += 1

	## A face with its own UVs: corners `a b cc d` (any order round it), `uvs` theirs, UV2 `u2`,
	## turned to face `want`. What the shader prints on it (a window's room, a digit, a menu)
	## reads UV and UV2.
	func face(a: Vector3, b: Vector3, cc: Vector3, d: Vector3, uvs: Array, want: Vector3, col: Color, u2: Vector2) -> void:
		var p: Array[Vector3] = [xf * a, xf * b, xf * cc, xf * d]
		var w := (xf.basis * want).normalized()
		var n := ((p[2] - p[0]).cross(p[1] - p[0])).normalized()
		var flip := n.dot(w) < 0.0
		var order := [0, 1, 2, 0, 2, 3] if not flip else [0, 2, 1, 0, 3, 2]
		var nn := -n if flip else n
		for i: int in order:
			st.set_color(col)
			st.set_normal(nn)
			st.set_uv(uvs[i])
			st.set_uv2(u2)
			st.add_vertex(p[i])
		tris += 2

	## A shop window in the frame's plane facing `out` (a unit axis of the frame), centred on `c`
	## at the floor's height `floor_y`, `w` wide and from `sill` to `head` over the floor: the room
	## behind it is traced `depth` metres deep (RoadsideKit.Room).
	func window(c: Vector3, out: Vector3, w: float, floor_y: float, sill: float, head: float, depth: float, room: int) -> void:
		var along := Vector3.UP.cross(out).normalized()
		var lo := Vector3(c.x, floor_y + sill, c.z)
		var hi := Vector3(c.x, floor_y + head, c.z)
		face(lo - along * w * 0.5, lo + along * w * 0.5, hi + along * w * 0.5, hi - along * w * 0.5,
			[Vector2(0.0, sill), Vector2(w, sill), Vector2(w, head), Vector2(0.0, head)], out,
			RoadsideKit.c(Color(0.1, 0.12, 0.13), K_ROOM), Vector2(depth, float(room)))

	## Lettering (TextMesh outlines) on the plane through `c` facing `out`, at most `max_w` wide.
	func text(s: String, height: float, c: Vector3, out: Vector3, col: Color, max_w: float) -> void:
		var along := Vector3.UP.cross(out).normalized()
		var b := Basis(along, Vector3.UP, out.normalized())
		StreetVendors._text(st, s, height, xf * Transform3D(b, c), col, max_w)
		tris += s.length() * 40

	## An LED price: `digits` (a string like "489") in cells `cell` metres tall from `c` (the left
	## edge's centre) along the face facing `out`; a "." makes a small gap, a digit after
	## `small_from` is drawn at 60 % (the 9/10 of a cent).
	func price(digits: String, c: Vector3, out: Vector3, cell: float, col: Color, small_from: int = 99) -> void:
		var along := Vector3.UP.cross(out).normalized()
		var top := c.y + cell * 0.5
		var x := 0.0
		var i := 0
		for ch in digits:
			var o := c + along * x + out * 0.012
			if ch == ".":
				box(Vector3(o.x, top - cell * 0.92, o.z) + along * 0.05 * cell, Vector3(0.09, 0.09, 0.01) * cell, RoadsideKit.c(col, K_NEON), RM_PLASTIC)
				x += 0.2 * cell
				continue
			var s := cell * (0.6 if i >= small_from else 1.0)
			var w := s * 0.62
			var ul := Vector3(o.x, top, o.z)
			var ll := ul - Vector3(0.0, s, 0.0)
			face(ll, ll + along * w, ul + along * w, ul,
				[Vector2(0.0, 1.0), Vector2(1.0, 1.0), Vector2(1.0, 0.0), Vector2(0.0, 0.0)], out, RoadsideKit.c(col, K_DIGIT), Vector2(float(ch.to_int()), 0.0))
			x += w + s * 0.1
			i += 1


static func _begin() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


static func _finish(st: SurfaceTool, key: String) -> Mesh:
	var mesh := st.commit()
	mesh.surface_set_material(0, material())
	_meshes[key] = mesh
	return mesh


# --- The repeated pieces ---------------------------------------------------------------------
# Each in its own frame: origin on the ground (or the island) under its middle, its front -Z.

## A multi-product fuel dispenser, 1.15 x 0.5 x 2.3 m: stainless base, painted side columns in the
## brand's colour (the instance paint), a screen and keypad on both faces, three lit grade buttons,
## three nozzles in their holsters a side on hoses looping from the crown, the lit crown on top.
static func dispenser() -> Mesh:
	if _meshes.has("disp"):
		return _meshes["disp"]
	var st := _begin()
	var p := Pen.new(st, Transform3D())
	var steel := c(Color(0.7, 0.71, 0.72), K_STEEL)
	var dark := c(Color(0.1, 0.1, 0.11), K_FIXED)
	var white := c(Color(0.9, 0.9, 0.88), K_FIXED)
	p.box(Vector3(0.0, 0.06, 0.0), Vector3(1.2, 0.12, 0.58), c(Color(0.25, 0.25, 0.26), K_FIXED), RM_MATTE, 0.02)
	p.box(Vector3(0.0, 0.55, 0.0), Vector3(1.0, 0.86, 0.46), steel, RM_STEEL, 0.015)
	# Door seams and louvres on the base.
	for z: float in [-0.232, 0.232]:
		p.box(Vector3(0.0, 0.55, z), Vector3(0.012, 0.8, 0.006), dark, RM_MATTE)
		for k in 4:
			p.box(Vector3(-0.25, 0.25 + k * 0.05, z), Vector3(0.3, 0.012, 0.006), dark, RM_MATTE)
			p.box(Vector3(0.25, 0.25 + k * 0.05, z), Vector3(0.3, 0.012, 0.006), dark, RM_MATTE)
	for x: float in [-0.52, 0.52]:
		p.box(Vector3(x, 1.08, 0.0), Vector3(0.14, 1.95, 0.5), paint(), RM_PAINT, 0.02)
	p.box(Vector3(0.0, 1.42, 0.0), Vector3(0.92, 0.88, 0.4), white, RM_PLASTIC, 0.01)
	for side: float in [-1.0, 1.0]:
		var z := side * 0.205
		var out := Vector3(0.0, 0.0, side)
		# Screen bezel and screen.
		p.box(Vector3(0.0, 1.6, z), Vector3(0.48, 0.36, 0.02), dark, RM_PLASTIC)
		p.face(Vector3(-0.2, 1.46, z + side * 0.011), Vector3(0.2, 1.46, z + side * 0.011), Vector3(0.2, 1.74, z + side * 0.011), Vector3(-0.2, 1.74, z + side * 0.011),
			[Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)], out, c(Color(0.1, 0.1, 0.1), K_SCREEN), Vector2(0.1, 0.0))
		# Keypad and card reader.
		p.box(Vector3(-0.2, 1.3, z + side * 0.03), Vector3(0.2, 0.16, 0.06), steel, RM_STEEL, 0.008)
		p.box(Vector3(0.18, 1.3, z + side * 0.035), Vector3(0.12, 0.14, 0.07), dark, RM_PLASTIC, 0.008)
		for k in 9:
			p.box(Vector3(-0.26 + (k % 3) * 0.06, 1.33 - (k / 3) * 0.04, z + side * 0.062), Vector3(0.04, 0.025, 0.008), c(Color(0.75, 0.76, 0.78), K_STEEL), RM_STEEL)
		# Three grade buttons: lit plastic over the nozzles.
		var grades := [Color(0.95, 0.85, 0.2), Color(0.25, 0.75, 0.3), Color(0.95, 0.95, 0.95)]
		for k in 3:
			p.box(Vector3(-0.3 + k * 0.3, 1.1, z + side * 0.015), Vector3(0.22, 0.08, 0.02), c(grades[k], K_LIGHTBOX), RM_PLASTIC)
		# Brand panel (instance paint) with a lit band at the head.
		p.box(Vector3(0.0, 1.9, z), Vector3(0.92, 0.14, 0.02), paint(), RM_PAINT)
		# Nozzles in their holsters, the hoses looping down from the crown.
		for k in 3:
			var hx := -0.32 + k * 0.32
			var hz := z + side * 0.07
			p.box(Vector3(hx, 0.98, hz), Vector3(0.12, 0.1, 0.08), dark, RM_PLASTIC)
			p.box(Vector3(hx, 1.02, hz + side * 0.05), Vector3(0.06, 0.18, 0.05), c(grades[k].darkened(0.35), K_FIXED), RM_PLASTIC, 0.01)
			p.tube([Vector3(hx, 1.02, hz + side * 0.07), Vector3(hx, 0.96, hz + side * 0.16), Vector3(hx, 0.86, hz + side * 0.18)], 0.012, c(Color(0.72, 0.73, 0.75), K_STEEL), RM_STEEL, 5)
			var top := Vector3(hx * 1.2, 2.1, z + side * 0.02)
			var path := []
			for j in 9:
				var t := float(j) / 8.0
				var lo := Vector3(hx, 1.08, hz + side * 0.03)
				var q := top.lerp(lo, t)
				q.z += side * sin(t * PI) * 0.22
				q.y -= sin(t * PI) * 0.55
				path.append(q)
			p.tube(path, 0.017, c(Color(0.05, 0.05, 0.05), K_FIXED), RM_RUBBER, 5)
	# The crown: a lit box with the brand stripe round its foot.
	p.box(Vector3(0.0, 2.17, 0.0), Vector3(1.22, 0.24, 0.52), c(Color(0.96, 0.96, 0.95), K_LIGHTBOX), RM_PLASTIC, 0.015)
	p.box(Vector3(0.0, 2.035, 0.0), Vector3(1.23, 0.05, 0.53), paint(), RM_PAINT)
	p.box(Vector3(0.0, 2.3, 0.0), Vector3(1.24, 0.03, 0.54), c(Color(0.3, 0.3, 0.32), K_FIXED), RM_PAINT)
	return _finish(st, "disp")


## A coin vacuum station: a painted canister with a domed top and a lit price cap, a pole with an
## arched boom and two hoses hanging from it.
static func vacuum() -> Mesh:
	if _meshes.has("vac"):
		return _meshes["vac"]
	var st := _begin()
	var p := Pen.new(st, Transform3D())
	p.box(Vector3(0.0, 0.05, 0.0), Vector3(0.9, 0.1, 0.9), c(Color(0.55, 0.55, 0.53), K_CONCRETE), RM_MATTE)
	p.cyl(Vector3(0.0, 0.1, 0.0), 0.34, 0.32, 1.0, paint(), RM_PAINT, 16)
	p.cyl(Vector3(0.0, 1.1, 0.0), 0.33, 0.12, 0.18, c(Color(0.75, 0.76, 0.78), K_STEEL), RM_STEEL, 16)
	p.box(Vector3(0.0, 0.85, -0.33), Vector3(0.26, 0.3, 0.06), c(Color(0.95, 0.95, 0.9), K_LIGHTBOX), RM_PLASTIC, 0.01)
	p.box(Vector3(0.0, 0.62, -0.335), Vector3(0.14, 0.1, 0.05), c(Color(0.1, 0.1, 0.1), K_FIXED), RM_PLASTIC)
	# Pole and the arched boom over the stall either side.
	p.cyl(Vector3(0.0, 1.25, 0.0), 0.06, 0.06, 2.3, c(Color(0.92, 0.92, 0.9), K_FIXED), RM_PAINT, 10)
	var arch := []
	for j in 13:
		var t := float(j) / 12.0
		arch.append(Vector3(lerpf(-2.2, 2.2, t), 3.55 + sin(t * PI) * 0.0 - pow(abs(t - 0.5) * 2.0, 2.0) * 0.55, 0.0))
	p.tube(arch, 0.055, c(Color(0.92, 0.92, 0.9), K_FIXED), RM_PAINT, 8)
	p.box(Vector3(0.0, 3.7, 0.0), Vector3(0.5, 0.36, 0.14), c(Color(0.95, 0.95, 0.92), K_LIGHTBOX), RM_PLASTIC, 0.01)
	for s: float in [-1.0, 1.0]:
		var hose := []
		for j in 10:
			var t := float(j) / 9.0
			var x := s * lerpf(2.1, 1.0, t)
			hose.append(Vector3(x, lerpf(3.0, 0.55, t) - sin(t * PI) * 0.35, -0.2 * sin(t * PI * 0.5)))
		p.tube(hose, 0.03, c(Color(0.08, 0.08, 0.09), K_FIXED), RM_RUBBER, 6)
		p.cyl(Vector3(s * 2.1, 3.0, 0.0), 0.04, 0.04, 0.3, c(Color(0.5, 0.5, 0.52), K_STEEL), RM_STEEL, 8)
		p.box(Vector3(s * 1.0, 0.45, -0.22), Vector3(0.06, 0.2, 0.06), c(Color(0.1, 0.1, 0.1), K_FIXED), RM_PLASTIC)
	return _finish(st, "vac")


## A tyre (0.66 m across, 0.22 m wide) on its side, centred over the origin: tread and sidewalls.
static func tyre() -> Mesh:
	if _meshes.has("tyre"):
		return _meshes["tyre"]
	var st := _begin()
	var p := Pen.new(st, Transform3D())
	var rub := c(Color(0.05, 0.05, 0.055), K_RUBBER)
	var side := c(Color(0.06, 0.06, 0.065), K_FIXED)
	var n := 20
	var ro := 0.33
	var rs := 0.31
	var ri := 0.2
	var hw := 0.11
	for i in n:
		var a0 := TAU * i / n
		var a1 := TAU * (i + 1) / n
		var d0 := Vector3(cos(a0), 0.0, sin(a0))
		var d1 := Vector3(cos(a1), 0.0, sin(a1))
		var u0 := float(i) / n
		var u1 := float(i + 1) / n
		# Tread: a band with rounded shoulders, the sidewalls down to the bead.
		var prof := [[ri + 0.02, -hw], [rs, -hw], [ro, -hw * 0.75], [ro, hw * 0.75], [rs, hw], [ri + 0.02, hw]]
		for k in prof.size() - 1:
			var a: Array = prof[k]
			var b: Array = prof[k + 1]
			var pa0 := d0 * float(a[0]) + Vector3(0.0, float(a[1]), 0.0)
			var pa1 := d1 * float(a[0]) + Vector3(0.0, float(a[1]), 0.0)
			var pb0 := d0 * float(b[0]) + Vector3(0.0, float(b[1]), 0.0)
			var pb1 := d1 * float(b[0]) + Vector3(0.0, float(b[1]), 0.0)
			var mid := (pa0 + pa1 + pb0 + pb1) * 0.25
			var want := mid - (d0 + d1).normalized() * (ri + ro) * 0.5
			p.face(pa0, pa1, pb1, pb0, [Vector2(u0, 0.0), Vector2(u1, 0.0), Vector2(u1, 1.0), Vector2(u0, 1.0)], want, rub if k == 2 else side, RM_RUBBER)
	return _finish(st, "tyre")


## A drive-thru menu board: two posts, a lit printed face 2.6 x 1.5 m under a hood, a small
## preview panel at the side. Faces -Z.
static func menu_board() -> Mesh:
	if _meshes.has("menu"):
		return _meshes["menu"]
	var st := _begin()
	var p := Pen.new(st, Transform3D())
	var frame := c(Color(0.16, 0.16, 0.17), K_FIXED)
	p.box(Vector3(0.0, 0.15, 0.0), Vector3(3.0, 0.3, 0.6), c(Color(0.55, 0.55, 0.53), K_CONCRETE), RM_MATTE)
	for x: float in [-1.2, 1.2]:
		p.box(Vector3(x, 1.0, 0.12), Vector3(0.14, 1.7, 0.14), frame, RM_PAINT)
	p.box(Vector3(0.0, 1.85, 0.08), Vector3(2.9, 1.7, 0.22), frame, RM_PAINT, 0.02)
	p.face(Vector3(-1.3, 1.1, -0.035), Vector3(1.3, 1.1, -0.035), Vector3(1.3, 2.6, -0.035), Vector3(-1.3, 2.6, -0.035),
		[Vector2(0, 1), Vector2(2, 1), Vector2(2, 0), Vector2(0, 0)], Vector3.BACK * -1.0, c(Color(0.9, 0.9, 0.9), K_MENU), Vector2(0.0, 0.0))
	p.box(Vector3(0.0, 2.78, -0.15), Vector3(3.0, 0.08, 0.6), frame, RM_PAINT)
	p.box(Vector3(0.0, 2.72, -0.42), Vector3(2.8, 0.04, 0.06), c(Color(1.0, 0.95, 0.85), K_NEON), RM_PLASTIC)
	p.box(Vector3(0.0, 2.95, 0.08), Vector3(2.9, 0.34, 0.24), paint(), RM_PAINT, 0.01)
	return _finish(st, "menu")


## The speaker post: a pedestal with an order screen and a speaker grille under a small canopy.
static func speaker_post() -> Mesh:
	if _meshes.has("spk"):
		return _meshes["spk"]
	var st := _begin()
	var p := Pen.new(st, Transform3D())
	var dark := c(Color(0.14, 0.14, 0.15), K_FIXED)
	p.box(Vector3(0.0, 0.08, 0.0), Vector3(0.7, 0.16, 0.5), c(Color(0.55, 0.55, 0.53), K_CONCRETE), RM_MATTE)
	p.box(Vector3(0.0, 0.85, 0.0), Vector3(0.5, 1.4, 0.32), paint(), RM_PAINT, 0.03)
	p.box(Vector3(0.0, 1.3, -0.165), Vector3(0.4, 0.36, 0.02), dark, RM_PLASTIC)
	p.face(Vector3(-0.17, 1.17, -0.177), Vector3(0.17, 1.17, -0.177), Vector3(0.17, 1.44, -0.177), Vector3(-0.17, 1.44, -0.177),
		[Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)], Vector3(0, 0, -1), c(Color(0.1, 0.1, 0.1), K_SCREEN), Vector2(0.1, 0.0))
	for k in 5:
		p.box(Vector3(0.0, 0.8 + k * 0.035, -0.168), Vector3(0.24, 0.012, 0.01), dark, RM_PLASTIC)
	p.box(Vector3(0.0, 1.62, -0.05), Vector3(0.62, 0.05, 0.52), dark, RM_PAINT)
	return _finish(st, "spk")


## The air and water machine: a red cabinet on a post, a coin slot and a lit price, a coiled
## hose on a hook either side.
static func air_machine() -> Mesh:
	if _meshes.has("air"):
		return _meshes["air"]
	var st := _begin()
	var p := Pen.new(st, Transform3D())
	var red := c(Color(0.72, 0.08, 0.06), K_FIXED)
	p.box(Vector3(0.0, 0.05, 0.0), Vector3(0.7, 0.1, 0.6), c(Color(0.55, 0.55, 0.53), K_CONCRETE), RM_MATTE)
	p.cyl(Vector3(0.0, 0.1, 0.0), 0.06, 0.06, 0.8, c(Color(0.6, 0.6, 0.62), K_STEEL), RM_STEEL, 10)
	p.box(Vector3(0.0, 1.25, 0.0), Vector3(0.5, 0.75, 0.32), red, RM_PAINT, 0.02)
	p.box(Vector3(0.0, 1.45, -0.165), Vector3(0.36, 0.2, 0.01), c(Color(0.95, 0.95, 0.9), K_LIGHTBOX), RM_PLASTIC)
	p.text("AIR  WATER", 0.06, Vector3(0.0, 1.45, -0.172), Vector3(0, 0, -1), c(Color(0.7, 0.05, 0.05), K_LIGHTBOX), 0.33)
	p.box(Vector3(0.0, 1.17, -0.17), Vector3(0.08, 0.12, 0.02), c(Color(0.65, 0.65, 0.67), K_STEEL), RM_STEEL)
	p.price("150", Vector3(-0.11, 1.03, -0.172), Vector3(0, 0, -1), 0.06, Color(1.0, 0.2, 0.1))
	for s: float in [-1.0, 1.0]:
		var coil := []
		for j in 25:
			var a := TAU * j / 24.0
			coil.append(Vector3(s * (0.27 + 0.02 * float(j) / 24.0), 1.1 + sin(a) * 0.17, cos(a) * 0.17))
		p.tube(coil, 0.014, c(Color(0.06, 0.06, 0.06), K_FIXED), RM_RUBBER, 5)
		p.box(Vector3(s * 0.27, 1.28, 0.0), Vector3(0.05, 0.04, 0.05), c(Color(0.6, 0.6, 0.62), K_STEEL), RM_STEEL)
	return _finish(st, "air")


## The ice chest: a white insulated box with lit ICE lettering, its lid's handles and a drain.
static func ice_chest() -> Mesh:
	if _meshes.has("ice"):
		return _meshes["ice"]
	var st := _begin()
	var p := Pen.new(st, Transform3D())
	var white := c(Color(0.92, 0.93, 0.94), K_FIXED)
	p.box(Vector3(0.0, 0.62, 0.0), Vector3(1.8, 1.24, 0.82), white, RM_PLASTIC, 0.03)
	for x: float in [-0.45, 0.45]:
		p.box(Vector3(x, 1.0, -0.42), Vector3(0.86, 0.36, 0.02), c(Color(0.88, 0.9, 0.93), K_FIXED), RM_PLASTIC)
		p.box(Vector3(x, 1.22, -0.43), Vector3(0.3, 0.04, 0.05), c(Color(0.6, 0.6, 0.62), K_STEEL), RM_STEEL)
	p.box(Vector3(0.0, 0.55, -0.415), Vector3(1.4, 0.4, 0.02), c(Color(0.15, 0.45, 0.85), K_LIGHTBOX), RM_PLASTIC)
	p.text("ICE", 0.32, Vector3(0.0, 0.55, -0.427), Vector3(0, 0, -1), c(Color(0.97, 0.98, 1.0), K_LIGHTBOX), 1.2)
	p.box(Vector3(0.0, 0.04, 0.0), Vector3(1.85, 0.08, 0.85), c(Color(0.3, 0.3, 0.32), K_FIXED), RM_MATTE)
	return _finish(st, "ice")


## The propane exchange cage: a steel mesh cage with a padlocked door and rows of tanks inside.
static func propane_cage() -> Mesh:
	if _meshes.has("propane"):
		return _meshes["propane"]
	var st := _begin()
	var p := Pen.new(st, Transform3D())
	var frame := c(Color(0.55, 0.57, 0.58), K_STEEL)
	var w := 1.3
	var d := 0.75
	var h := 1.6
	for x: float in [-w * 0.5, w * 0.5]:
		for z: float in [-d * 0.5, d * 0.5]:
			p.box(Vector3(x, h * 0.5, z), Vector3(0.04, h, 0.04), frame, RM_STEEL)
	for y: float in [0.05, h * 0.5, h - 0.02]:
		p.box(Vector3(0.0, y, -d * 0.5), Vector3(w, 0.03, 0.03), frame, RM_STEEL)
		p.box(Vector3(0.0, y, d * 0.5), Vector3(w, 0.03, 0.03), frame, RM_STEEL)
		p.box(Vector3(-w * 0.5, y, 0.0), Vector3(0.03, 0.03, d), frame, RM_STEEL)
		p.box(Vector3(w * 0.5, y, 0.0), Vector3(0.03, 0.03, d), frame, RM_STEEL)
	# The mesh: thin bars on each face (a grid you can see the tanks through).
	for k in 11:
		var x := -w * 0.5 + w * k / 10.0
		p.box(Vector3(x, h * 0.5, -d * 0.5), Vector3(0.008, h, 0.008), frame, RM_STEEL)
		p.box(Vector3(x, h * 0.5, d * 0.5), Vector3(0.008, h, 0.008), frame, RM_STEEL)
	for k in 13:
		var y := 0.05 + (h - 0.07) * k / 12.0
		p.box(Vector3(0.0, y, -d * 0.5), Vector3(w, 0.008, 0.008), frame, RM_STEEL)
	p.box(Vector3(0.0, 0.79, 0.0), Vector3(w - 0.04, 0.025, d - 0.04), frame, RM_STEEL)
	p.box(Vector3(0.0, h + 0.01, 0.0), Vector3(w + 0.04, 0.03, d + 0.04), frame, RM_STEEL)
	for row in 2:
		for k in 4:
			var tx := -0.45 + k * 0.3
			var ty := 0.07 + row * 0.75
			p.cyl(Vector3(tx, ty, 0.0), 0.14, 0.14, 0.48, c(Color(0.92, 0.92, 0.9) if (k + row) % 3 != 0 else Color(0.25, 0.45, 0.75), K_FIXED), RM_PAINT, 10)
			p.cyl(Vector3(tx, ty + 0.48, 0.0), 0.14, 0.07, 0.07, c(Color(0.9, 0.9, 0.88), K_FIXED), RM_PAINT, 10)
			p.cyl(Vector3(tx, ty + 0.55, 0.0), 0.05, 0.05, 0.08, c(Color(0.6, 0.6, 0.62), K_STEEL), RM_STEEL, 6)
	p.box(Vector3(0.0, 1.3, -d * 0.5 - 0.02), Vector3(0.7, 0.2, 0.01), c(Color(0.95, 0.95, 0.92), K_FIXED), RM_PLASTIC)
	p.text("PROPANE", 0.1, Vector3(0.0, 1.3, -d * 0.5 - 0.027), Vector3(0, 0, -1), c(Color(0.1, 0.25, 0.6), K_FIXED), 0.62)
	return _finish(st, "propane")


## The island's service stand: a trash can with a squeegee bucket and a paper-towel dispenser.
static func service_stand() -> Mesh:
	if _meshes.has("stand"):
		return _meshes["stand"]
	var st := _begin()
	var p := Pen.new(st, Transform3D())
	p.cyl(Vector3(0.0, 0.0, 0.0), 0.26, 0.27, 0.95, paint(), RM_PAINT, 14)
	p.cyl(Vector3(0.0, 0.95, 0.0), 0.28, 0.24, 0.1, c(Color(0.2, 0.2, 0.21), K_FIXED), RM_PLASTIC, 14)
	p.box(Vector3(0.0, 1.0, -0.25), Vector3(0.36, 0.4, 0.04), c(Color(0.2, 0.2, 0.21), K_FIXED), RM_PLASTIC)
	p.cyl(Vector3(0.0, 1.05, -0.38), 0.12, 0.13, 0.26, c(Color(0.15, 0.35, 0.75), K_FIXED), RM_PLASTIC, 10)
	p.box(Vector3(0.03, 1.38, -0.38), Vector3(0.03, 0.42, 0.03), c(Color(0.1, 0.1, 0.1), K_FIXED), RM_PLASTIC, 0.0, Basis(Vector3.BACK, 0.15))
	p.box(Vector3(0.06, 1.56, -0.38), Vector3(0.28, 0.06, 0.05), c(Color(0.1, 0.1, 0.1), K_FIXED), RM_PLASTIC)
	p.box(Vector3(0.0, 1.45, -0.27), Vector3(0.3, 0.32, 0.18), c(Color(0.9, 0.9, 0.9), K_FIXED), RM_PLASTIC, 0.02)
	return _finish(st, "stand")


## A two-post lift with a car on its arms (the car is drawn by the car batch): posts, carriages,
## arms, the overhead beam.
static func lift() -> Mesh:
	if _meshes.has("lift"):
		return _meshes["lift"]
	var st := _begin()
	var p := Pen.new(st, Transform3D())
	var blue := c(Color(0.12, 0.3, 0.62), K_FIXED)
	for x: float in [-1.55, 1.55]:
		p.box(Vector3(x, 0.03, 0.0), Vector3(0.6, 0.06, 0.6), c(Color(0.3, 0.3, 0.3), K_STEEL), RM_STEEL)
		p.box(Vector3(x, 1.9, 0.0), Vector3(0.32, 3.8, 0.3), blue, RM_PAINT, 0.02)
		p.box(Vector3(x * 0.9, 1.45, 0.0), Vector3(0.25, 0.45, 0.4), c(Color(0.75, 0.6, 0.1), K_FIXED), RM_PAINT)
		for z: float in [-0.9, 0.9]:
			p.box(Vector3(x * 0.6, 1.3, z * 0.5), Vector3(0.12, 0.08, 1.0), c(Color(0.75, 0.6, 0.1), K_FIXED), RM_PAINT, 0.0, Basis(Vector3.UP, -signf(x) * signf(z) * 0.4))
	p.box(Vector3(0.0, 3.85, 0.0), Vector3(3.5, 0.18, 0.22), blue, RM_PAINT)
	p.tube([Vector3(-1.55, 3.6, 0.1), Vector3(-1.2, 3.75, 0.12), Vector3(1.2, 3.75, 0.12), Vector3(1.55, 3.6, 0.1)], 0.02, c(Color(0.08, 0.08, 0.08), K_FIXED), RM_RUBBER, 4)
	return _finish(st, "lift")


## Builds every piece once (the loading screen), so the first roadside pad does not stall.
static func warm() -> Array:
	dispenser()
	vacuum()
	tyre()
	menu_board()
	speaker_post()
	air_machine()
	ice_chest()
	propane_cage()
	service_stand()
	lift()
	return [material()]
