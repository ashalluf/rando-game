class_name ConstructionKit
extends RefCounted
## The building sites' geometry (Construction lays it out): box, beam, cylinder, lattice and
## lettering writers that give every face UV in metres in its own frame and say what the surface
## is in the vertex colour, so ONE material (shaders/construction.gdshader) draws a whole site -
## concrete frame, formwork, rebar, netting, guardrails, hoarding, cabins, timber house frames,
## road works - and the tower crane, whose slewing parts the shader turns. Everything is at real
## size; pure geometry, no rolls, no nodes.
##
## Vertex layout (the contract with the shader; see its header):
##   COLOR.rgb  the paint as written (display numbers)   COLOR.a  the kind (K_*), in 32nds
##   UV         metres in the face's frame                UV2.x    the box's height or a parameter
##   UV2.y      the crane animation code (CODE_*)

# --- Kinds (COLOR.a in 32nds; mirrored in construction.gdshader's header) -----------------------
const K_CONCRETE := 0
const K_FORM := 1
const K_REBAR := 2
const K_STEEL := 3
const K_GALV := 4
const K_NET := 5
const K_LATTICE := 6
const K_HOARDING := 7
const K_LUMBER := 8
const K_OSB := 9
const K_WRAP := 10
const K_GLASS := 11
const K_LAMP := 12
const K_PLASTIC := 13
const K_CONE := 14
const K_DRUM := 15
const K_RUBBER := 16
const K_ARROW := 17
const K_PAINT := 18
const K_DIRT := 19
const K_GRAVEL := 20
const K_TEXT := 21
const K_PLATE := 22
const K_CABIN := 23
const K_SIGN := 24
const K_MAT := 25
const K_STRIP := 26
const K_CAB_GLASS := 27
const KIND_COUNT := 28

# --- Crane animation codes (UV2.y; the shader's vertex stage) -----------------------------------
const CODE_STATIC := 0
const CODE_SLEW := 1
const CODE_TROLLEY := 2
const CODE_HOOK := 3
const CODE_ROPE := 4

# --- The tower crane (a flat-top / hammerhead crane; real proportions) --------------------------
## The jib's underside over the slewing ring (mirrored as the shader's `jib_y`, checked).
const JIB_Y := 1.6
## Mast section (square, m), the jib's section (width, depth), the counter-jib's width.
const MAST_W := 2.0
const JIB_W := 1.3
const JIB_D := 1.7
const COUNTER_W := 2.4
## The cathead (the A-frame over the slewing ring the pendants hang from), its height over the jib.
const CATHEAD_H := 9.0
## Crane yellow, counterweight concrete, the cab's white.
const CRANE_PAINT := Color(0.93, 0.70, 0.08)
const CRANE_WHITE := Color(0.90, 0.90, 0.88)
const COUNTERWEIGHT := Color(0.62, 0.61, 0.58)
const LAMP_RED := Color(1.0, 0.12, 0.06)

const CONCRETE := Color(0.70, 0.69, 0.66)
const LUMBER := Color(0.86, 0.70, 0.48)
const OSB := Color(0.80, 0.64, 0.40)
const FORM_PAINTS := [Color(0.72, 0.56, 0.26), Color(0.56, 0.34, 0.18), Color(0.74, 0.64, 0.38)]
const NET_PAINTS := [Color(0.18, 0.34, 0.22), Color(0.95, 0.48, 0.10), Color(0.12, 0.22, 0.34)]
const RAIL_PAINT := Color(0.92, 0.78, 0.10)
const MACHINE_YELLOW := Color(0.94, 0.68, 0.06)

static var _material: ShaderMaterial
static var _crane_material: ShaderMaterial
## Triangles written since start (tests and the bench read it).
static var tris: int = 0


static func material() -> ShaderMaterial:
	if _material != null:
		return _material
	_material = ShaderMaterial.new()
	_material.shader = load("res://shaders/construction.gdshader")
	_material.set_shader_parameter("concrete_tex", PropFactory.texture("concrete", "Color"))
	_material.set_shader_parameter("planks_tex", PropFactory.texture("planks", "Color"))
	_material.set_shader_parameter("dirt_tex", PropFactory.texture("hill_dirt", "Color"))
	return _material


## The same shader with the crane's animation on (one material for every crane in the city: each
## takes its phase from where it stands).
static func crane_material() -> ShaderMaterial:
	if _crane_material != null:
		return _crane_material
	_crane_material = material().duplicate() as ShaderMaterial
	_crane_material.set_shader_parameter("crane", true)
	_crane_material.set_shader_parameter("jib_y", JIB_Y)
	return _crane_material


static func kind_color(kind: int, paint: Color) -> Color:
	return Color(paint.r, paint.g, paint.b, (float(kind) + 0.5) / 32.0)


static func new_st() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	return st


# --- Writers ------------------------------------------------------------------------------------

## The six faces of a unit box: outward normal, then four corners counter-clockwise seen from
## outside, laid 0-2-1, 0-3-2 (IndustrialKit's table: Godot's front faces are clockwise).
const FACES := [
	[Vector3(1, 0, 0), [Vector3(0.5, -0.5, 0.5), Vector3(0.5, -0.5, -0.5), Vector3(0.5, 0.5, -0.5), Vector3(0.5, 0.5, 0.5)]],
	[Vector3(-1, 0, 0), [Vector3(-0.5, -0.5, -0.5), Vector3(-0.5, -0.5, 0.5), Vector3(-0.5, 0.5, 0.5), Vector3(-0.5, 0.5, -0.5)]],
	[Vector3(0, 0, 1), [Vector3(-0.5, -0.5, 0.5), Vector3(0.5, -0.5, 0.5), Vector3(0.5, 0.5, 0.5), Vector3(-0.5, 0.5, 0.5)]],
	[Vector3(0, 0, -1), [Vector3(0.5, -0.5, -0.5), Vector3(-0.5, -0.5, -0.5), Vector3(-0.5, 0.5, -0.5), Vector3(0.5, 0.5, -0.5)]],
	[Vector3(0, 1, 0), [Vector3(-0.5, 0.5, 0.5), Vector3(0.5, 0.5, 0.5), Vector3(0.5, 0.5, -0.5), Vector3(-0.5, 0.5, -0.5)]],
	[Vector3(0, -1, 0), [Vector3(-0.5, -0.5, -0.5), Vector3(0.5, -0.5, -0.5), Vector3(0.5, -0.5, 0.5), Vector3(-0.5, -0.5, 0.5)]],
]


## A box of `size` placed by `xf` (centre and turn, no scale). `p` is UV2.x (negative: the box's
## height), `code` UV2.y; `skip` a bitmask of faces left out (1 +x, 2 -x, 4 +z, 8 -z, 16 top,
## 32 bottom; the bottom is left out unless asked for).
static func box(st: SurfaceTool, xf: Transform3D, size: Vector3, kind: int, paint: Color, p: float = -1.0, code: int = 0, skip: int = 32) -> void:
	var col := kind_color(kind, paint)
	var p2 := Vector2(size.y if p < 0.0 else p, float(code))
	for f in 6:
		if skip & (1 << f):
			continue
		tris += 2
		var fc: Array = FACES[f]
		var n: Vector3 = fc[0]
		var q: Array = fc[1]
		var pts: Array[Vector3] = []
		var uvs: Array[Vector2] = []
		for c: Vector3 in q:
			var pp := c * size
			pts.append(xf * pp)
			var uv: Vector2
			if absf(n.y) > 0.5:
				uv = Vector2(pp.x + size.x * 0.5, pp.z + size.z * 0.5)
			elif absf(n.x) > 0.5:
				uv = Vector2((pp.z + size.z * 0.5) if n.x < 0.0 else (size.z * 0.5 - pp.z), pp.y + size.y * 0.5)
			else:
				uv = Vector2((pp.x + size.x * 0.5) if n.z > 0.0 else (size.x * 0.5 - pp.x), pp.y + size.y * 0.5)
			uvs.append(uv)
		var wn := (xf.basis * n).normalized()
		for k: int in [0, 2, 1, 0, 3, 2]:
			st.set_normal(wn)
			st.set_color(col)
			st.set_uv(uvs[k])
			st.set_uv2(p2)
			st.add_vertex(pts[k])


## An axis-aligned box from its foot centre (`at` is the middle of its bottom face), turned by yaw.
static func box_at(st: SurfaceTool, at: Vector3, size: Vector3, yaw: float, kind: int, paint: Color, p: float = -1.0, code: int = 0, skip: int = 32) -> void:
	box(st, Transform3D(Basis(Vector3.UP, yaw), at + Vector3(0.0, size.y * 0.5, 0.0)), size, kind, paint, p, code, skip)


## A beam of section `sec` (width, depth) from `a` to `b`; `up` steers its roll.
static func beam(st: SurfaceTool, a: Vector3, b: Vector3, sec: Vector2, kind: int, paint: Color, code: int = 0, up: Vector3 = Vector3.UP) -> void:
	var d := b - a
	var len := d.length()
	if len < 1e-4:
		return
	var z := d / len
	var u := up
	if absf(z.dot(u)) > 0.98:
		u = Vector3.RIGHT if absf(z.x) < 0.9 else Vector3.FORWARD
	var x := u.cross(z).normalized()
	var y := z.cross(x).normalized()
	# The box's local y runs along the beam so its side faces' UV.x wraps round and UV.y runs along.
	box(st, Transform3D(Basis(x, z, -y), (a + b) * 0.5), Vector3(sec.x, len, sec.y), kind, paint, -1.0, code, 0)


## A cylinder or a cone frustum (axis +y of `xf`, foot at its origin), `segs` sided, radius r0 at
## the foot and r1 at the top, with its top cap. UV.x round it in metres, UV.y up it; UV2.x `p`
## (negative: the height).
static func cyl(st: SurfaceTool, xf: Transform3D, r0: float, r1: float, h: float, kind: int, paint: Color, segs: int = 10, cap: bool = true, p: float = -1.0, code: int = 0) -> void:
	var col := kind_color(kind, paint)
	var p2 := Vector2(h if p < 0.0 else p, float(code))
	var circ := TAU * maxf(r0, r1)
	var slope := (r0 - r1) / maxf(h, 1e-4)
	for i in segs:
		var a0 := TAU * float(i) / float(segs)
		var a1 := TAU * float(i + 1) / float(segs)
		var d0 := Vector3(cos(a0), 0.0, sin(a0))
		var d1 := Vector3(cos(a1), 0.0, sin(a1))
		var n0 := (xf.basis * (d0 + Vector3(0.0, slope, 0.0)).normalized()).normalized()
		var n1 := (xf.basis * (d1 + Vector3(0.0, slope, 0.0)).normalized()).normalized()
		var p00 := xf * (d0 * r0)
		var p10 := xf * (d1 * r0)
		var p01 := xf * (d0 * r1 + Vector3(0.0, h, 0.0))
		var p11 := xf * (d1 * r1 + Vector3(0.0, h, 0.0))
		var u0 := circ * float(i) / float(segs)
		var u1 := circ * float(i + 1) / float(segs)
		# Outward faces wind clockwise seen from outside: 00, 10, 01 then 10, 11, 01.
		_v(st, p00, n0, col, Vector2(u0, 0.0), p2)
		_v(st, p10, n1, col, Vector2(u1, 0.0), p2)
		_v(st, p01, n0, col, Vector2(u0, h), p2)
		_v(st, p10, n1, col, Vector2(u1, 0.0), p2)
		_v(st, p11, n1, col, Vector2(u1, h), p2)
		_v(st, p01, n0, col, Vector2(u0, h), p2)
		tris += 2
		if cap and r1 > 0.001:
			var up := (xf.basis * Vector3.UP).normalized()
			var c := xf * Vector3(0.0, h, 0.0)
			_v(st, c, up, col, Vector2(r1, h), p2)
			_v(st, p01, up, col, Vector2(u0, h), p2)
			_v(st, p11, up, col, Vector2(u1, h), p2)
			tris += 1


static func _v(st: SurfaceTool, p: Vector3, n: Vector3, col: Color, uv: Vector2, uv2: Vector2) -> void:
	st.set_normal(n)
	st.set_color(col)
	st.set_uv(uv)
	st.set_uv2(uv2)
	st.add_vertex(p)


## A flat quad a-b-c-d (counter-clockwise seen from the side it faces), UV metres from a along
## a->b and a->d.
static func quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, kind: int, paint: Color, p: float = 0.0, code: int = 0) -> void:
	var col := kind_color(kind, paint)
	var n := (b - a).cross(d - a).normalized()
	var ex := (b - a).normalized()
	var ey := (d - a).normalized()
	var p2 := Vector2(p, float(code))
	var uv := func(q: Vector3) -> Vector2: return Vector2((q - a).dot(ex), (q - a).dot(ey))
	for q: Vector3 in [a, c, b, a, d, c]:
		_v(st, q, n, col, uv.call(q), p2)
	tris += 2


## A square-section lattice (a crane mast, a hoist mast) along +y of `xf` from 0 to `length`,
## `w` across: four cut-out lattice faces (UV.x across 0..w, UV.y along, UV2.x = w) and four
## corner chords as real angles so it has depth up close.
static func lattice(st: SurfaceTool, xf: Transform3D, length: float, w: float, paint: Color, code: int = 0, chords: bool = true) -> void:
	lattice_rect(st, xf, length, Vector2(w, w), paint, code, chords)


## A lattice of a rectangular section (`sec` x along local x, y along local z) along +y.
static func lattice_rect(st: SurfaceTool, xf: Transform3D, length: float, sec: Vector2, paint: Color, code: int = 0, chords: bool = true) -> void:
	var col := kind_color(K_LATTICE, paint)
	var hx := sec.x * 0.5
	var hz := sec.y * 0.5
	# Faces: +x, -x, +z, -z, each as (corner a, across direction, width, normal).
	var faces := [
		[Vector3(hx, 0.0, hz), Vector3(0, 0, -1), sec.y, Vector3(1, 0, 0)],
		[Vector3(-hx, 0.0, -hz), Vector3(0, 0, 1), sec.y, Vector3(-1, 0, 0)],
		[Vector3(-hx, 0.0, hz), Vector3(1, 0, 0), sec.x, Vector3(0, 0, 1)],
		[Vector3(hx, 0.0, -hz), Vector3(-1, 0, 0), sec.x, Vector3(0, 0, -1)],
	]
	for f: Array in faces:
		var a: Vector3 = f[0]
		var across: Vector3 = f[1]
		var w: float = f[2]
		var n: Vector3 = (xf.basis * (f[3] as Vector3)).normalized()
		var p2 := Vector2(w, float(code))
		var c0 := xf * a
		var c1 := xf * (a + across * w)
		var c2 := xf * (a + across * w + Vector3(0.0, length, 0.0))
		var c3 := xf * (a + Vector3(0.0, length, 0.0))
		_v(st, c0, n, col, Vector2(0.0, 0.0), p2)
		_v(st, c2, n, col, Vector2(w, length), p2)
		_v(st, c1, n, col, Vector2(w, 0.0), p2)
		_v(st, c0, n, col, Vector2(0.0, 0.0), p2)
		_v(st, c3, n, col, Vector2(0.0, length), p2)
		_v(st, c2, n, col, Vector2(w, length), p2)
		tris += 2
	if chords:
		var t := clampf(minf(sec.x, sec.y) * 0.07, 0.06, 0.16)
		for cx: float in [-1.0, 1.0]:
			for cz: float in [-1.0, 1.0]:
				var foot := Vector3(cx * (hx - t * 0.5), 0.0, cz * (hz - t * 0.5))
				box(st, xf * Transform3D(Basis(), foot + Vector3(0.0, length * 0.5, 0.0)), Vector3(t, length, t), K_STEEL, paint, -1.0, code, 48)


## Lettering (TextMesh geometry, FreewayKit's cache) laid flat in the plane of `xf` (letters
## along +x, up +y, facing +z), `height` the cap height.
static func text(st: SurfaceTool, s: String, height: float, xf: Transform3D, paint: Color, kind: int = K_TEXT) -> float:
	var geo: Array = FreewayKit.text_geo(s, height)
	var verts: PackedVector3Array = geo[0]
	var idx: PackedInt32Array = geo[1]
	var col := kind_color(kind, paint)
	var n := (xf.basis * Vector3.BACK).normalized()
	var p2 := Vector2(0.0, 0.0)
	var i := 0
	while i + 2 < idx.size():
		var a := verts[idx[i]]
		var b := verts[idx[i + 1]]
		var c := verts[idx[i + 2]]
		# Front faces wind clockwise to the viewer looking down -z at the letters.
		var cr := (b - a).cross(c - a)
		if cr.z > 0.0:
			var tmp := b
			b = c
			c = tmp
		for q: Vector3 in [a, b, c]:
			_v(st, xf * q, n, col, Vector2(q.x, q.y), p2)
		tris += 1
		i += 3
	return float(geo[2])


# --- The tower crane ------------------------------------------------------------------------------

## A flat-top tower crane in its own space: origin at the slewing ring's top on the mast's axis,
## the mast hanging `mast_h` below it to the foot (static), and on top the slewing unit - the
## turntable, the cab, the cathead and pendants, the jib along +x (`jib` m), the counter-jib along
## -x (`counter` m) with its counterweights and winch, the trolley, the hook and its ropes, the red
## aviation lights - all of it turned by the shader. `drop` is the hook's longest drop (m).
static func crane_mesh(mast_h: float, jib: float, counter: float, drop: float) -> ArrayMesh:
	var st := new_st()
	var y := CRANE_PAINT
	# The mast: lattice sections from the foot up to the ring, on a concrete base block.
	lattice(st, Transform3D(Basis(), Vector3(0.0, -mast_h, 0.0)), mast_h - 0.6, MAST_W, y)
	box_at(st, Vector3(0.0, -mast_h - 0.6, 0.0), Vector3(MAST_W + 3.2, 1.0, MAST_W + 3.2), 0.0, K_CONCRETE, CONCRETE)
	# The climbing frame / top section and the slewing ring (static part of the ring).
	box_at(st, Vector3(0.0, -0.6, 0.0), Vector3(MAST_W + 0.3, 0.6, MAST_W + 0.3), 0.0, K_STEEL, y)
	# --- Slewing unit ---
	var s := CODE_SLEW
	box_at(st, Vector3(0.0, 0.0, 0.0), Vector3(MAST_W + 0.6, JIB_Y, MAST_W + 0.6), 0.0, K_STEEL, y, -1.0, s)
	# Walkway round the turntable.
	box_at(st, Vector3(0.0, JIB_Y - 0.12, 0.0), Vector3(MAST_W + 2.0, 0.08, MAST_W + 2.0), 0.0, K_GALV, y, -1.0, s)
	# The cab on the jib side, offset to -z, glazed on its front and sides.
	var cab := Vector3(MAST_W * 0.5 + 0.9, JIB_Y - 2.3, -(MAST_W * 0.5 + 0.5))
	box_at(st, cab, Vector3(1.8, 2.2, 1.4), 0.0, K_PAINT, CRANE_WHITE, -1.0, s)
	box_at(st, cab + Vector3(0.56, 0.75, 0.0), Vector3(0.72, 1.2, 1.44), 0.0, K_CAB_GLASS, Color.WHITE, -1.0, s, 32)
	box_at(st, cab + Vector3(-0.1, 0.8, -0.71), Vector3(1.4, 1.0, 0.04), 0.0, K_CAB_GLASS, Color.WHITE, -1.0, s, 32)
	# The cathead: an A-frame of four legs to a point CATHEAD_H over the jib, pendants down to the
	# jib at two thirds and to the counter-jib's end.
	var top := Vector3(0.0, JIB_Y + JIB_D + CATHEAD_H, 0.0)
	for cx: float in [-0.8, 0.8]:
		for cz: float in [-0.8, 0.8]:
			beam(st, Vector3(cx, JIB_Y + JIB_D, cz), top + Vector3(cx * 0.15, 0.0, cz * 0.15), Vector2(0.22, 0.22), K_STEEL, y, s)
	box_at(st, top + Vector3(0.0, -0.2, 0.0), Vector3(0.6, 0.6, 0.6), 0.0, K_STEEL, y, -1.0, s)
	var jt := Vector3(jib * 0.66, JIB_Y + JIB_D, 0.0)
	var ct := Vector3(-counter + 1.0, JIB_Y + 0.9, 0.0)
	for z: float in [-0.35, 0.35]:
		beam(st, top + Vector3(0.0, 0.0, z), jt + Vector3(0.0, 0.0, z * 1.4), Vector2(0.07, 0.07), K_STEEL, Color(0.25, 0.25, 0.25), s)
		beam(st, top + Vector3(0.0, 0.0, z), ct + Vector3(0.0, 0.0, z * 2.0), Vector2(0.07, 0.07), K_STEEL, Color(0.25, 0.25, 0.25), s)
	# The jib: a lattice of the jib's section along +x, its tip with an end frame.
	var jib_xf := Transform3D(Basis(Vector3(0, -1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)), Vector3(MAST_W * 0.5 + 0.3, JIB_Y + JIB_D * 0.5, 0.0))
	lattice_rect(st, jib_xf, jib - MAST_W * 0.5 - 0.3, Vector2(JIB_D, JIB_W), y, s)
	# A catwalk along the jib's bottom chords.
	box_at(st, Vector3(jib * 0.5 + 0.6, JIB_Y - 0.05, 0.0), Vector3(jib - 1.2, 0.05, 0.5), 0.0, K_GALV, y, -1.0, s)
	# The counter-jib: a deck with rails, the counterweight slabs at its end, the hoist winch.
	var cl := counter
	box_at(st, Vector3(-cl * 0.5 - MAST_W * 0.3, JIB_Y + 0.2, 0.0), Vector3(cl, 0.5, COUNTER_W), 0.0, K_STEEL, y, -1.0, s)
	for z: float in [-COUNTER_W * 0.5, COUNTER_W * 0.5]:
		box_at(st, Vector3(-cl * 0.5 - MAST_W * 0.3, JIB_Y + 1.25, z), Vector3(cl, 0.06, 0.06), 0.0, K_STEEL, y, -1.0, s)
		var px := -MAST_W * 0.3 - 1.0
		while px > -cl - MAST_W * 0.3:
			box_at(st, Vector3(px, JIB_Y + 0.7, z), Vector3(0.06, 0.58, 0.06), 0.0, K_STEEL, y, -1.0, s)
			px -= 2.0
	var nweights := 4
	for i in nweights:
		var x := -cl - MAST_W * 0.3 + 0.6 + float(i) * 0.95
		box_at(st, Vector3(x, JIB_Y - 2.6, 0.0), Vector3(0.85, 3.0, COUNTER_W - 0.2), 0.0, K_CONCRETE, COUNTERWEIGHT, -1.0, s)
	box_at(st, Vector3(-cl * 0.45, JIB_Y + 0.45, 0.0), Vector3(2.0, 1.2, 1.6), 0.0, K_PAINT, Color(0.2, 0.22, 0.24), -1.0, s)
	box_at(st, Vector3(-cl * 0.72, JIB_Y + 0.45, 0.4), Vector3(1.4, 1.1, 1.0), 0.0, K_PAINT, CRANE_WHITE, -1.0, s)
	# Lights: on the jib's tip, the counter-jib's end and the cathead's top (red, steady).
	box_at(st, Vector3(jib - 0.2, JIB_Y + JIB_D, 0.0), Vector3(0.25, 0.25, 0.25), 0.0, K_LAMP, LAMP_RED, -1.0, s)
	box_at(st, Vector3(-cl - MAST_W * 0.3, JIB_Y + 0.6, 0.0), Vector3(0.25, 0.25, 0.25), 0.0, K_LAMP, LAMP_RED, -1.0, s)
	box_at(st, top + Vector3(0.0, 0.1, 0.0), Vector3(0.28, 0.28, 0.28), 0.0, K_LAMP, LAMP_RED, -1.0, s)
	# --- The trolley rig: built at x = 0 and moved out along the jib by the shader ---
	var pk := floorf(jib) * 1000.0 + floorf(clampf(drop, 4.5, 999.0))
	_box_p(st, Vector3(0.0, JIB_Y - 0.55, 0.0), Vector3(1.6, 0.5, JIB_W + 0.2), K_STEEL, y, pk, CODE_TROLLEY)
	# Ropes: built hanging 1 m from the trolley, stretched to the drop.
	for z: float in [-0.16, 0.16]:
		_box_p(st, Vector3(0.0, JIB_Y - 1.05, z), Vector3(0.035, 1.0, 0.035), K_GALV, Color.WHITE, pk, CODE_ROPE)
	# The hook block, 1 m under the trolley before the drop.
	_box_p(st, Vector3(0.0, JIB_Y - 1.95, 0.0), Vector3(0.5, 0.9, 0.42), K_PAINT, y, pk, CODE_HOOK)
	_box_p(st, Vector3(0.0, JIB_Y - 2.35, 0.0), Vector3(0.12, 0.36, 0.1), K_STEEL, Color(0.15, 0.15, 0.15), pk, CODE_HOOK)
	return st.commit()


## A box (foot centre `at`) with UV2.x = `p` whatever its height.
static func _box_p(st: SurfaceTool, at: Vector3, size: Vector3, kind: int, paint: Color, p: float, code: int) -> void:
	box(st, Transform3D(Basis(), at + Vector3(0.0, size.y * 0.5, 0.0)), size, kind, paint, p, code)


## The crane's far copy (the LOD chunks and the far city): the mast as a mast drawn at least a
## pixel wide, the jib and counter-jib as thin boxes at their rest heading, the counterweight, and
## red beacons on the jib's tip and the cathead. [[Transform3D (unit box), Color, Color custom]]
## in the crane's own space (origin at the ring).
static func crane_far_boxes(mast_h: float, jib: float, counter: float, yaw: float) -> Array:
	var out := []
	var flag := FarBuilding.PLANT_FLAG
	var keep := Color(float(FarBuilding.Plant.UNIT), 1.0, 0.0, flag)
	var mast := Color(float(FarBuilding.Plant.MAST), 1.0, 0.0, flag)
	var beacon := Color(float(FarBuilding.Plant.BEACON_MAST), 1.0, 0.0, flag)
	var b := Basis(Vector3.UP, yaw)
	out.append([Transform3D(Basis().scaled(Vector3(MAST_W, mast_h, MAST_W)), Vector3(0.0, -mast_h * 0.5, 0.0)), CRANE_PAINT, mast])
	out.append([Transform3D(b * Basis().scaled(Vector3(jib, JIB_D, JIB_W)), b * Vector3(jib * 0.5, JIB_Y + JIB_D * 0.5, 0.0)), CRANE_PAINT, keep])
	out.append([Transform3D(b * Basis().scaled(Vector3(counter, 0.6, COUNTER_W)), b * Vector3(-counter * 0.5, JIB_Y + 0.4, 0.0)), CRANE_PAINT, keep])
	out.append([Transform3D(b * Basis().scaled(Vector3(3.6, 3.0, COUNTER_W)), b * Vector3(-counter + 2.0, JIB_Y - 1.1, 0.0)), COUNTERWEIGHT, keep])
	out.append([Transform3D(Basis().scaled(Vector3(0.5, CATHEAD_H, 0.5)), Vector3(0.0, JIB_Y + JIB_D + CATHEAD_H * 0.5, 0.0)), CRANE_PAINT, beacon])
	out.append([Transform3D(b * Basis().scaled(Vector3(0.3, 1.0, 0.3)), b * Vector3(jib - 0.3, JIB_Y + JIB_D + 0.5, 0.0)), CRANE_PAINT, beacon])
	return out


# --- Props written into a site's mesh (`xf` places them; foot at the origin, front +z) -----------

## A traffic cone, 0.71 m (28 in) with its square base.
static func cone(st: SurfaceTool, xf: Transform3D) -> void:
	box(st, xf * Transform3D(Basis(), Vector3(0.0, 0.02, 0.0)), Vector3(0.38, 0.04, 0.38), K_RUBBER, Color.BLACK, -1.0, 0, 32)
	cyl(st, xf * Transform3D(Basis(), Vector3(0.0, 0.04, 0.0)), 0.15, 0.03, 0.67, K_CONE, Color.WHITE, 8, true, 0.67)


## A channelising drum: 0.9 m tall, orange and white bands, on its black tyre-rubber base.
static func drum(st: SurfaceTool, xf: Transform3D) -> void:
	cyl(st, xf, 0.36, 0.36, 0.08, K_RUBBER, Color.BLACK, 10, true)
	cyl(st, xf * Transform3D(Basis(), Vector3(0.0, 0.08, 0.0)), 0.29, 0.26, 0.9, K_DRUM, Color.WHITE, 10, true, 0.9)


## A Type III barricade: two posts on feet, three striped rails (orange / white sheeting).
static func barricade(st: SurfaceTool, xf: Transform3D, w: float = 2.4) -> void:
	for sx: float in [-w * 0.42, w * 0.42]:
		box(st, xf * Transform3D(Basis(), Vector3(sx, 0.75, 0.0)), Vector3(0.08, 1.5, 0.08), K_GALV, Color.WHITE)
		box(st, xf * Transform3D(Basis(), Vector3(sx, 0.03, 0.0)), Vector3(0.1, 0.06, 0.9), K_GALV, Color.WHITE)
	for ry: float in [0.55, 0.95, 1.35]:
		box(st, xf * Transform3D(Basis(), Vector3(0.0, ry, 0.05)), Vector3(w, 0.2, 0.03), K_SIGN, Color(0.98, 0.42, 0.06))
		var x := -w * 0.5 + 0.15
		while x < w * 0.5 - 0.1:
			box(st, xf * Transform3D(Basis(Vector3.BACK, 0.8), Vector3(x, ry, 0.068)), Vector3(0.09, 0.26, 0.004), K_SIGN, Color(0.95, 0.95, 0.93), -1.0, 0, 48)
			x += 0.3


## An arrow board trailer: a two-wheel trailer with a drawbar, a mast and a 2.4 x 1.2 m LED panel
## facing +z (oncoming traffic), its solar panel on top.
static func arrow_board(st: SurfaceTool, xf: Transform3D) -> void:
	var w := Color(0.92, 0.66, 0.08)
	box(st, xf * Transform3D(Basis(), Vector3(0.0, 0.62, 0.0)), Vector3(1.5, 0.5, 2.0), K_PAINT, w)
	beam(st, xf * Vector3(0.0, 0.5, -1.0), xf * Vector3(0.0, 0.45, -2.2), Vector2(0.08, 0.08), K_PAINT, w)
	for sx: float in [-0.85, 0.85]:
		cyl(st, xf * Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(sx + (0.1 if sx > 0.0 else -0.1), 0.32, 0.0)), 0.32, 0.32, 0.2, K_RUBBER, Color.BLACK, 10, true)
	box(st, xf * Transform3D(Basis(), Vector3(0.0, 0.12, -2.1)), Vector3(0.1, 0.24, 0.1), K_GALV, Color.WHITE)
	box(st, xf * Transform3D(Basis(), Vector3(0.0, 1.9, -0.2)), Vector3(0.14, 2.1, 0.14), K_GALV, Color.WHITE)
	# The panel: a housing, the LED face on its front (UV in metres across, 2.4 x 1.2).
	box(st, xf * Transform3D(Basis(), Vector3(0.0, 3.0, -0.1)), Vector3(2.5, 1.3, 0.16), K_PAINT, Color(0.08, 0.08, 0.08))
	quad(st, xf * Vector3(-1.2, 2.4, 0.0), xf * Vector3(1.2, 2.4, 0.0), xf * Vector3(1.2, 3.6, 0.0), xf * Vector3(-1.2, 3.6, 0.0), K_ARROW, Color.WHITE)
	box(st, xf * Transform3D(Basis(Vector3.RIGHT, -0.5), Vector3(0.0, 3.85, -0.3)), Vector3(1.4, 0.04, 0.9), K_CAB_GLASS, Color.WHITE)


## A steel trench plate, `size` (x, z) metres, 25 mm thick, its edge ramped with asphalt patch.
static func trench_plate(st: SurfaceTool, xf: Transform3D, size: Vector2) -> void:
	box(st, xf * Transform3D(Basis(), Vector3(0.0, 0.0125, 0.0)), Vector3(size.x, 0.025, size.y), K_PLATE, Color.WHITE, -1.0, 0, 32)


## A compact excavator (5-tonne class, ~6 m long with its arm out): rubber tracks, the turning
## upper with its counterweight and a glazed cab, the boom, the stick and the bucket dug in at
## `dig` (0 raised .. 1 down to the ground); the dozer blade at the front. Front +z.
static func excavator(st: SurfaceTool, xf: Transform3D, swing: float, dig: float) -> void:
	var yv := MACHINE_YELLOW
	var dark := Color(0.12, 0.12, 0.13)
	for sx: float in [-0.8, 0.8]:
		box(st, xf * Transform3D(Basis(), Vector3(sx, 0.28, 0.0)), Vector3(0.42, 0.56, 2.3), K_RUBBER, Color.BLACK)
		for zz: float in [-0.95, 0.95]:
			cyl(st, xf * Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(sx + 0.22, 0.28, zz)), 0.26, 0.26, 0.44, K_RUBBER, Color.BLACK, 10, false)
		box(st, xf * Transform3D(Basis(), Vector3(sx * 0.62, 0.32, 0.0)), Vector3(0.3, 0.3, 1.8), K_PAINT, dark)
	# The dozer blade.
	box(st, xf * Transform3D(Basis(), Vector3(0.0, 0.25, 1.45)), Vector3(1.9, 0.45, 0.12), K_PAINT, yv)
	# The upper, turned by `swing`.
	var up := xf * Transform3D(Basis(Vector3.UP, swing), Vector3(0.0, 0.62, 0.0))
	cyl(st, up, 0.6, 0.6, 0.1, K_PAINT, dark, 12, true)
	box(st, up * Transform3D(Basis(), Vector3(0.0, 0.5, -0.15)), Vector3(1.55, 0.8, 1.9), K_PAINT, yv)
	box(st, up * Transform3D(Basis(), Vector3(0.0, 0.45, -1.15)), Vector3(1.6, 0.7, 0.35), K_PAINT, Color(0.2, 0.2, 0.2))
	# The cab: a frame with glass on all four sides and a roof.
	var cab := up * Transform3D(Basis(), Vector3(-0.32, 1.55, 0.25))
	box(st, cab, Vector3(0.9, 1.3, 1.1), K_CAB_GLASS, Color.WHITE)
	box(st, cab * Transform3D(Basis(), Vector3(0.0, 0.68, 0.0)), Vector3(0.96, 0.06, 1.16), K_PAINT, yv)
	for cx: float in [-0.46, 0.46]:
		for cz: float in [-0.56, 0.56]:
			box(st, cab * Transform3D(Basis(), Vector3(cx, 0.0, cz)), Vector3(0.05, 1.3, 0.05), K_PAINT, dark)
	# Boom (two segments: a dog-leg), stick and bucket, in the upper's x = 0.35 plane.
	var bx := 0.38
	var pivot := Vector3(bx, 0.75, 0.75)
	var b_ang := lerpf(0.95, 0.55, dig)
	var knee := pivot + Vector3(0.0, sin(b_ang) * 1.6, cos(b_ang) * 1.6)
	var tip := knee + Vector3(0.0, sin(b_ang - 0.75) * 1.2, cos(b_ang - 0.75) * 1.2)
	var s_ang := lerpf(-0.6, -1.45, dig)
	var stick := tip + Vector3(0.0, sin(s_ang) * 1.5, cos(s_ang) * 1.5)
	beam(st, up * pivot, up * knee, Vector2(0.2, 0.32), K_PAINT, yv)
	beam(st, up * knee, up * tip, Vector2(0.2, 0.3), K_PAINT, yv)
	beam(st, up * tip, up * stick, Vector2(0.16, 0.24), K_PAINT, yv)
	beam(st, up * (pivot + Vector3(0.0, 0.0, 0.2)), up * (knee + Vector3(0.0, -0.2, 0.0)), Vector2(0.09, 0.09), K_GALV, Color.WHITE)
	# The bucket: a wedge of three plates and its teeth.
	var bk := up * Transform3D(Basis(Vector3.RIGHT, s_ang - 0.4), stick)
	box(st, bk * Transform3D(Basis(), Vector3(0.0, -0.15, 0.12)), Vector3(0.55, 0.06, 0.45), K_PAINT, dark)
	box(st, bk * Transform3D(Basis(), Vector3(0.0, 0.05, 0.32)), Vector3(0.55, 0.42, 0.06), K_PAINT, dark)
	for sx: float in [-0.28, 0.28]:
		box(st, bk * Transform3D(Basis(), Vector3(sx, 0.0, 0.15)), Vector3(0.04, 0.36, 0.42), K_PAINT, dark)


## A roll-off skip (a 20-yard dumpster): tapered steel box, ribs, its load of debris.
static func skip(st: SurfaceTool, xf: Transform3D, paint: Color, load: float = 0.6) -> void:
	box(st, xf * Transform3D(Basis(), Vector3(0.0, 0.85, 0.0)), Vector3(2.35, 1.4, 6.0), K_PAINT, paint)
	box(st, xf * Transform3D(Basis(), Vector3(0.0, 0.08, 0.0)), Vector3(1.6, 0.16, 6.0), K_PAINT, Color(0.1, 0.1, 0.1))
	var z := -2.6
	while z <= 2.65:
		for sx: float in [-1.2, 1.2]:
			box(st, xf * Transform3D(Basis(), Vector3(sx, 0.85, z)), Vector3(0.06, 1.4, 0.12), K_PAINT, paint)
		z += 1.3
	# The load: broken board and offcuts heaped in it.
	box(st, xf * Transform3D(Basis(), Vector3(0.0, 0.2 + 1.3 * load, 0.0)), Vector3(2.2, 0.12, 5.8), K_DIRT, Color(0.7, 0.66, 0.6), -1.0, 0, 32)
	for i in 6:
		var a := float(i) * 1.7
		box(st, xf * Transform3D(Basis(Vector3.UP, a).rotated(Vector3.RIGHT, 0.4), Vector3(sin(a) * 0.6, 0.3 + 1.3 * load, -2.2 + float(i) * 0.85)), Vector3(0.2, 0.04, 1.4), K_LUMBER, LUMBER)


## A portable toilet: moulded plastic shell, its door with a vent and the roof's skylight dome.
static func toilet(st: SurfaceTool, xf: Transform3D, paint: Color) -> void:
	box(st, xf * Transform3D(Basis(), Vector3(0.0, 0.06, 0.0)), Vector3(1.16, 0.12, 1.16), K_PLASTIC, Color(0.25, 0.25, 0.25))
	box(st, xf * Transform3D(Basis(), Vector3(0.0, 1.17, 0.0)), Vector3(1.1, 2.1, 1.1), K_PLASTIC, paint)
	box(st, xf * Transform3D(Basis(), Vector3(0.0, 2.3, 0.0)), Vector3(1.16, 0.16, 1.16), K_PLASTIC, Color(0.92, 0.92, 0.9))
	box(st, xf * Transform3D(Basis(), Vector3(0.0, 1.1, 0.56)), Vector3(0.78, 1.85, 0.03), K_PLASTIC, paint.darkened(0.12))
	box(st, xf * Transform3D(Basis(), Vector3(0.0, 1.75, 0.58)), Vector3(0.5, 0.18, 0.02), K_PAINT, Color(0.12, 0.12, 0.12))
	box(st, xf * Transform3D(Basis(), Vector3(0.3, 1.1, 0.59)), Vector3(0.06, 0.14, 0.04), K_PAINT, Color(0.2, 0.2, 0.2))


## A site cabin (an office trailer: 2.4 x 6.0 x 2.6 m), its windows along the front (+z).
static func cabin(st: SurfaceTool, xf: Transform3D, paint: Color = Color(0.92, 0.92, 0.89)) -> void:
	box(st, xf * Transform3D(Basis(), Vector3(0.0, 1.38, 0.0)), Vector3(6.0, 2.6, 2.4), K_CABIN, paint, 2.0, 0, 32 | 16)
	box(st, xf * Transform3D(Basis(), Vector3(0.0, 2.72, 0.0)), Vector3(6.1, 0.08, 2.5), K_PAINT, Color(0.55, 0.55, 0.55), -1.0, 0, 32)
	box(st, xf * Transform3D(Basis(), Vector3(0.0, 0.04, 0.0)), Vector3(6.0, 0.08, 2.4), K_PAINT, Color(0.2, 0.2, 0.2))
	for sx: float in [-2.7, 2.7]:
		for sz: float in [-1.0, 1.0]:
			box(st, xf * Transform3D(Basis(), Vector3(sx, 0.04, sz)), Vector3(0.3, 0.08, 0.3), K_GALV, Color.WHITE)


## A stack of lumber (a strapped unit of 2x4s, 1.2 x 0.75 x `len` m) on two bearers.
static func lumber_stack(st: SurfaceTool, xf: Transform3D, len: float = 4.9) -> void:
	for sz: float in [-len * 0.35, len * 0.35]:
		box(st, xf * Transform3D(Basis(), Vector3(0.0, 0.05, sz)), Vector3(1.3, 0.1, 0.1), K_LUMBER, LUMBER.darkened(0.2))
	box(st, xf * Transform3D(Basis(), Vector3(0.0, 0.48, 0.0)), Vector3(1.2, 0.75, len), K_LUMBER, LUMBER)
	for sz: float in [-len * 0.25, len * 0.25]:
		box(st, xf * Transform3D(Basis(), Vector3(0.0, 0.48, sz)), Vector3(1.22, 0.77, 0.03), K_STEEL, Color(0.1, 0.1, 0.12), -1.0, 0, 32)


## A bundle of rebar (12 m bars, strapped) on bearers.
static func rebar_bundle(st: SurfaceTool, xf: Transform3D) -> void:
	for sz: float in [-4.0, 0.0, 4.0]:
		box(st, xf * Transform3D(Basis(), Vector3(0.0, 0.06, sz)), Vector3(1.0, 0.12, 0.12), K_LUMBER, LUMBER.darkened(0.25))
	for i in 3:
		box(st, xf * Transform3D(Basis(), Vector3((float(i) - 1.0) * 0.32, 0.2, 0.0)), Vector3(0.26, 0.16, 11.5), K_REBAR, Color.WHITE)


## A stack of formwork panels (1.2 x 2.4 m sheets on a pallet).
static func form_stack(st: SurfaceTool, xf: Transform3D, paint: Color) -> void:
	box(st, xf * Transform3D(Basis(), Vector3(0.0, 0.07, 0.0)), Vector3(1.3, 0.14, 2.5), K_LUMBER, LUMBER.darkened(0.2))
	box(st, xf * Transform3D(Basis(), Vector3(0.0, 0.45, 0.0)), Vector3(1.22, 0.62, 2.44), K_FORM, paint)


## The flagger's STOP / SLOW paddle (in a hand's frame: the pole along +y), as its own mesh.
static func paddle_mesh() -> ArrayMesh:
	var st := new_st()
	box(st, Transform3D(Basis(), Vector3(0.0, 0.9, 0.0)), Vector3(0.025, 1.8, 0.025), K_PAINT, Color(0.85, 0.85, 0.82))
	# An octagon of radius 0.23 m at the top, red on one face, orange on the other.
	var c := Vector3(0.0, 1.95, 0.0)
	for side: float in [1.0, -1.0]:
		var col := Color(0.82, 0.05, 0.04) if side > 0.0 else Color(0.98, 0.45, 0.05)
		for i in 8:
			var a0 := TAU * (float(i) + 0.5) / 8.0
			var a1 := TAU * (float(i) + 1.5) / 8.0
			var p0 := c + Vector3(cos(a0) * 0.23, sin(a0) * 0.23, side * 0.006)
			var p1 := c + Vector3(cos(a1) * 0.23, sin(a1) * 0.23, side * 0.006)
			var pc := c + Vector3(0.0, 0.0, side * 0.006)
			var n := Vector3(0.0, 0.0, side)
			var col4 := kind_color(K_SIGN, col)
			var tri := [pc, p0, p1] if side < 0.0 else [pc, p1, p0]
			for q: Vector3 in tri:
				_v(st, q, n, col4, Vector2(q.x, q.y), Vector2.ZERO)
		text(st, "STOP" if side > 0.0 else "SLOW", 0.075, Transform3D(Basis(Vector3.UP, 0.0 if side > 0.0 else PI), c + Vector3(0.0, 0.0, side * 0.009)), Color(0.96, 0.96, 0.94) if side > 0.0 else Color(0.04, 0.04, 0.04), K_SIGN)
	return st.commit()
