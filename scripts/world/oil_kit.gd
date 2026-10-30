class_name OilKit
extends RefCounted
## The oil field's hardware (OilField / OilFieldBuild), built in code at real size.
##
## THE PUMPJACK is one mesh (cached, near and far versions) on shaders/pumpjack.gdshader, which
## animates it: the vertex shader turns the crank, rocks the walking beam about the saddle bearing,
## stretches the pitman arms between the crank pins and the equalizer, and slides the bridle, the
## carrier bar and the polished rod up and down the horsehead's arc - phased per well from the
## instance's custom data, so a field of them costs nothing on the CPU. Its frame (metres, scale 1):
## +X toward the well, origin on the wellhead at the foot of the foundation; the saddle bearing at
## PIVOT, the crank shaft at CRANK; the horsehead's face an arc of radius FRONT round the pivot, so
## the wire rope always leaves it plumb over the wellhead.
##
## Vertex layout (the contract with the shader):
##   COLOR.rgb  paint as written (display numbers; white on the parts the instance paint colours)
##   COLOR.a    the kind (K_*), in 16ths
##   UV         metres in the face's own frame
##   UV2.x      the moving part: 0 still, 1 walking beam (with the horsehead and the equalizer),
##              2 crank (arms, counterweights, pins), 3 pitman arm (UV2.y = 0 at the crank pin ..
##              1 at the equalizer), 4 bridle (UV2.y = 0 at the carrier bar .. 1 where it leaves
##              the horsehead), 5 carrier bar and polished rod
##   INSTANCE_CUSTOM  r the crank's phase (0..1), g strokes per minute / 20 (0 = idle), b the
##              wear (0..1)
##   INSTANCE COLOR   the unit's paint
##
## Everything else (tanks, catwalks, the derrick, pipe racks, poles, fences, signs) is written
## through IndustrialKit's box / cylinder writers into the chunk's ONE walls mesh on
## IndustrialKit.walls_material(): its kinds already draw tank paint, painted and galvanised steel,
## chain-link, barbed wire, concrete, timber and lamps.

## The pumpjack's geometry (metres, scale 1): the saddle bearing, the crank shaft, the horsehead's
## arc radius (pivot to the wire), the tail (pivot to the equalizer), the crank radius (shaft to the
## wrist pin), where the carrier bar rides at mid-stroke.
const PIVOT := Vector2(-3.9, 6.3)
const CRANK := Vector2(-7.4, 2.45)
const FRONT := 3.9
const TAIL := 3.5
const CRANK_R := 1.15
const CARRIER_Y := 3.2
## Wellhead to the motor's end.
const LENGTH := 10.9

## Kinds (COLOR.a in 16ths; mirrored in pumpjack.gdshader).
const K_PAINT := 0
const K_PAINT_DARK := 1
const K_STEEL := 2
const K_CONCRETE := 3
const K_SAFETY := 4
const K_ROD := 5
const K_CABLE := 6
const K_PLAIN := 7
const K_WEIGHT := 8

## What LA's units are painted (display numbers): the field grey-green, sand, a faded blue, a
## dusty green, an old red, cream.
const PAINTS := [
	Color(0.52, 0.55, 0.50), Color(0.62, 0.57, 0.47), Color(0.36, 0.45, 0.55), Color(0.38, 0.46, 0.36),
	Color(0.56, 0.24, 0.18), Color(0.74, 0.71, 0.62), Color(0.47, 0.49, 0.47),
]
const TANK_PAINTS := [Color(0.60, 0.55, 0.44), Color(0.46, 0.48, 0.40), Color(0.72, 0.70, 0.64), Color(0.55, 0.56, 0.53)]
const RIG_RED := Color(0.66, 0.19, 0.12)
const RIG_CREAM := Color(0.82, 0.79, 0.70)
const GALV := Color(0.64, 0.65, 0.63)
const DARK := Color(0.16, 0.16, 0.17)
const SAFETY := Color(0.86, 0.68, 0.12)

static var _cache: Dictionary = {}
static var _material: ShaderMaterial

## The mesh being written (the pumpjack builders).
var _st: SurfaceTool
var _tag := 0
var _t := 0.0


static func material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = load("res://shaders/pumpjack.gdshader")
		_material.set_shader_parameter("pivot", PIVOT)
		_material.set_shader_parameter("crank", CRANK)
		_material.set_shader_parameter("front", FRONT)
		_material.set_shader_parameter("tail", TAIL)
		_material.set_shader_parameter("crank_r", CRANK_R)
		_material.set_shader_parameter("concrete_tex", PropFactory.texture("concrete", "Color"))
	return _material


## The beam angle (radians, +: horsehead up) at crank angle `phi`: the tail follows the wrist
## pin up and down (the shader's formula).
static func beam_angle(phi: float) -> float:
	return asin(clampf(-CRANK_R * sin(phi) / TAIL, -1.0, 1.0))


# --- The pumpjack ------------------------------------------------------------------------------

## The pumpjack, near (full detail, ~2.4k triangles) or far (a few boxes, the same moving parts).
static func pumpjack(far: bool = false) -> ArrayMesh:
	var key := "pumpjack_far" if far else "pumpjack"
	if _cache.has(key):
		return _cache[key]
	var k := OilKit.new()
	k._st = SurfaceTool.new()
	k._st.begin(Mesh.PRIMITIVE_TRIANGLES)
	k._st.set_smooth_group(-1)
	if far:
		k._build_far()
	else:
		k._build_near()
	k._st.set_material(material())
	var mesh := k._st.commit()
	# The beam swings, the crank turns: the bounds hold every pose.
	mesh.custom_aabb = AABB(Vector3(-LENGTH - 0.6, -0.5, -1.7), Vector3(LENGTH + 2.4, 9.6, 3.4))
	_cache[key] = mesh
	return mesh


func _part(tag: int, t: float = 0.0) -> void:
	_tag = tag
	_t = t


func _v(p: Vector3, n: Vector3, uv: Vector2, col: Color) -> void:
	_st.set_normal(n)
	_st.set_color(col)
	_st.set_uv(uv)
	var t := _t
	if _tag == 3:
		# The pitman: its own height along the rod (the shader rebuilds it between the moving ends).
		t = clampf((p.y - CRANK.y) / ((PIVOT.y - CRANK.y)), 0.0, 1.0)
	elif _tag == 4:
		t = clampf((p.y - CARRIER_Y) / (PIVOT.y - CARRIER_Y), 0.0, 1.0)
	_st.set_uv2(Vector2(float(_tag), t))
	_st.add_vertex(p)


static func _col(kind: int, paint: Color) -> Color:
	return Color(paint.r, paint.g, paint.b, (float(kind) + 0.5) / 16.0)


## A box with centre `c`, half sizes `h`, turned by `b` (orthonormal).
func _box(c: Vector3, size: Vector3, kind: int, paint: Color = Color.WHITE, b: Basis = Basis()) -> void:
	var col := _col(kind, paint)
	for f in 6:
		var fc: Array = IndustrialKit.FACES[f]
		var n: Vector3 = fc[0]
		var q: Array = fc[1]
		var pts: Array[Vector3] = []
		var uvs: Array[Vector2] = []
		for corner: Vector3 in q:
			var p := corner * size
			pts.append(c + b * p)
			var uv: Vector2
			if absf(n.y) > 0.5:
				uv = Vector2(p.x, p.z)
			elif absf(n.x) > 0.5:
				uv = Vector2(p.z, p.y)
			else:
				uv = Vector2(p.x, p.y)
			uvs.append(uv + Vector2(c.x + c.z, c.y))
		var wn := (b * n).normalized()
		for k: int in [0, 2, 1, 0, 3, 2]:
			_v(pts[k], wn, uvs[k], col)


## A box from `a` to `b` (its axis), `w` wide and `d` deep, its width across `side` (a hint).
func _strut(a: Vector3, b: Vector3, w: float, d: float, kind: int, paint: Color = Color.WHITE, side: Vector3 = Vector3(0, 0, 1)) -> void:
	var ax := b - a
	var len := ax.length()
	if len < 1e-4:
		return
	var y := ax / len
	var x := side.cross(y)
	if x.length_squared() < 1e-6:
		x = Vector3(1, 0, 0).cross(y)
	x = x.normalized()
	var z := x.cross(y).normalized()
	_box((a + b) * 0.5, Vector3(w, len, d), kind, paint, Basis(x, y, z))


## A cylinder from `a` to `b`, radius `r`, `segs` sided, capped.
func _cyl(a: Vector3, b: Vector3, r: float, segs: int, kind: int, paint: Color = Color.WHITE, caps: bool = true) -> void:
	var ax := b - a
	var len := ax.length()
	if len < 1e-4:
		return
	var y := ax / len
	var x := Vector3(0, 0, 1).cross(y)
	if x.length_squared() < 1e-4:
		x = Vector3(1, 0, 0).cross(y)
	x = x.normalized()
	var z := x.cross(y).normalized()
	var col := _col(kind, paint)
	for i in segs:
		var a0 := TAU * float(i) / float(segs)
		var a1 := TAU * float(i + 1) / float(segs)
		var d0 := x * cos(a0) + z * sin(a0)
		var d1 := x * cos(a1) + z * sin(a1)
		var p00 := a + d0 * r
		var p10 := a + d1 * r
		var p01 := b + d0 * r
		var p11 := b + d1 * r
		var u0 := r * a0
		var u1 := r * a1
		var quad := [p00, p10, p11, p01]
		var ns := [d0, d1, d1, d0]
		var uvs := [Vector2(u0, 0.0), Vector2(u1, 0.0), Vector2(u1, len), Vector2(u0, len)]
		var order := [0, 2, 1, 0, 3, 2]
		if ((p10 - p00).cross(p01 - p00)).dot(d0 + d1) > 0.0:
			order = [0, 1, 2, 0, 2, 3]
		for k: int in order:
			_v(quad[k], ns[k], uvs[k], col)
		if caps:
			for end in 2:
				var c := b if end == 1 else a
				var nn := y if end == 1 else -y
				var e0 := c + d0 * r
				var e1 := c + d1 * r
				var tri := [c, e0, e1]
				if ((e0 - c).cross(e1 - c)).dot(nn) > 0.0:
					tri = [c, e1, e0]
				for p: Vector3 in tri:
					_v(p, nn, Vector2(p.x, p.z) if absf(nn.y) > 0.5 else Vector2(p.x + p.z, p.y), col)


## A flat plate: the polygon `poly` (in the XY plane, any winding) extruded from z0 to z1.
func _prism(poly: PackedVector2Array, z0: float, z1: float, kind: int, paint: Color = Color.WHITE) -> void:
	var col := _col(kind, paint)
	if Geometry2D.is_polygon_clockwise(poly):
		poly = poly.duplicate()
		poly.reverse()
	var tris := Geometry2D.triangulate_polygon(poly)
	# Caps: +z (counter-clockwise in XY seen from +z is front-facing for Godot? Godot's front face
	# is clockwise to the viewer, so the +z cap takes the triangles reversed).
	for c in range(0, tris.size(), 3):
		for k: int in [0, 2, 1]:
			var p := poly[tris[c + k]]
			_v(Vector3(p.x, p.y, z1), Vector3(0, 0, 1), p, col)
		for k: int in [0, 1, 2]:
			var p := poly[tris[c + k]]
			_v(Vector3(p.x, p.y, z0), Vector3(0, 0, -1), p, col)
	var run := 0.0
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		var e := b - a
		# Outward for a counter-clockwise polygon: the edge turned clockwise.
		var n := Vector3(e.y, -e.x, 0.0).normalized()
		var q := [Vector3(a.x, a.y, z0), Vector3(b.x, b.y, z0), Vector3(b.x, b.y, z1), Vector3(a.x, a.y, z1)]
		var l := e.length()
		var uvs := [Vector2(run, z0), Vector2(run + l, z0), Vector2(run + l, z1), Vector2(run, z1)]
		run += l
		var order := [0, 2, 1, 0, 3, 2]
		if (((q[1] as Vector3) - (q[0] as Vector3)).cross((q[3] as Vector3) - (q[0] as Vector3))).dot(n) > 0.0:
			order = [0, 1, 2, 0, 2, 3]
		for k: int in order:
			_v(q[k], n, uvs[k], col)


## Points of an arc round `c` (XY), radius `r`, from angle `a0` to `a1` (degrees).
static func _arc(c: Vector2, r: float, a0: float, a1: float, n: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in n + 1:
		var a := deg_to_rad(lerpf(a0, a1, float(i) / float(n)))
		out.append(c + Vector2(cos(a), sin(a)) * r)
	return out


func _build_near() -> void:
	var px := PIVOT.x
	var py := PIVOT.y
	# --- Still: the foundation, the base, the Samson post, the gearbox, the motor, the wellhead.
	_part(0)
	_box(Vector3(-5.9, -0.05, 0.0), Vector3(9.8, 0.6, 2.6), K_CONCRETE, Color(0.58, 0.57, 0.54))
	# Two I-beam rails of the base and their cross members.
	for z: float in [-0.62, 0.62]:
		_box(Vector3(-6.0, 0.29, z), Vector3(9.0, 0.08, 0.3), K_PAINT_DARK)
		_box(Vector3(-6.0, 0.5, z), Vector3(9.0, 0.34, 0.05), K_PAINT_DARK)
		_box(Vector3(-6.0, 0.71, z), Vector3(9.0, 0.08, 0.3), K_PAINT_DARK)
	for x: float in [-10.2, -8.6, -6.6, -4.4, -1.8]:
		_box(Vector3(x, 0.5, 0.0), Vector3(0.22, 0.36, 1.24), K_PAINT_DARK)
	# Samson post: two front legs and two rear braces up to the saddle, cross bracing between.
	var top_f := Vector3(px + 0.05, py - 0.28, 0.0)
	for s: float in [-1.0, 1.0]:
		_strut(Vector3(-2.35, 0.75, 0.6 * s), top_f + Vector3(0.0, 0.0, 0.2 * s), 0.24, 0.24, K_PAINT)
		_strut(Vector3(-5.55, 0.75, 0.56 * s), top_f + Vector3(-0.18, -0.15, 0.18 * s), 0.2, 0.2, K_PAINT)
	for y: float in [2.2, 3.9]:
		var f := inverse_lerp(0.75, py - 0.28, y)
		var xf := lerpf(-2.35, px + 0.05, f)
		var zf := lerpf(0.6, 0.2, f)
		_box(Vector3(xf, y, 0.0), Vector3(0.14, 0.14, zf * 2.0), K_PAINT)
		var xr := lerpf(-5.55, px - 0.13, f)
		_strut(Vector3(xf, y, 0.0), Vector3(xr, y - 0.1, 0.0), 0.12, 0.12, K_PAINT)
	# Ladder up the front-left leg's face and a small landing round the saddle.
	var lad_a := Vector3(-2.15, 0.75, -0.95)
	var lad_b := Vector3(px + 0.45, py - 0.6, -0.55)
	for s: float in [-0.2, 0.2]:
		_strut(lad_a + Vector3(0, 0, s), lad_b + Vector3(0, 0, s), 0.05, 0.05, K_SAFETY, SAFETY)
	for i in 14:
		var f := (float(i) + 0.5) / 14.0
		var p := lad_a.lerp(lad_b, f)
		_box(p, Vector3(0.035, 0.035, 0.4), K_SAFETY, SAFETY)
	_box(Vector3(px + 0.1, py - 0.52, 0.0), Vector3(1.2, 0.05, 1.5), K_STEEL, GALV)
	for s: float in [-1.0, 1.0]:
		_box(Vector3(px + 0.1, py - 0.02, 0.74 * s), Vector3(1.2, 0.04, 0.04), K_SAFETY, SAFETY)
		_box(Vector3(px + 0.68, py - 0.27, 0.74 * s), Vector3(0.04, 0.5, 0.04), K_SAFETY, SAFETY)
		_box(Vector3(px - 0.48, py - 0.27, 0.74 * s), Vector3(0.04, 0.5, 0.04), K_SAFETY, SAFETY)
	# The saddle bearing (still: the beam rocks on it).
	_box(Vector3(px, py - 0.12, 0.0), Vector3(0.62, 0.3, 0.5), K_PAINT_DARK)
	_cyl(Vector3(px, py, -0.34), Vector3(px, py, 0.34), 0.17, 10, K_STEEL, DARK)
	# The gearbox on its stand, the crank shaft through it.
	_box(Vector3(CRANK.x, 0.98, 0.0), Vector3(1.9, 0.48, 1.3), K_PAINT_DARK)
	_box(Vector3(CRANK.x - 0.05, 1.72, 0.0), Vector3(1.55, 1.0, 1.15), K_PAINT)
	_box(Vector3(CRANK.x - 0.05, 2.24, 0.0), Vector3(1.62, 0.06, 1.22), K_PAINT_DARK)
	_cyl(Vector3(CRANK.x, CRANK.y, -0.6), Vector3(CRANK.x, CRANK.y, 0.6), 0.48, 14, K_PAINT)
	_cyl(Vector3(CRANK.x, CRANK.y, -1.22), Vector3(CRANK.x, CRANK.y, 1.22), 0.15, 10, K_STEEL, DARK)
	# The brake drum and its lever.
	_cyl(Vector3(CRANK.x - 0.85, 1.62, -0.72), Vector3(CRANK.x - 0.85, 1.62, -0.42), 0.32, 12, K_STEEL, DARK)
	_strut(Vector3(CRANK.x - 1.2, 0.8, -0.72), Vector3(CRANK.x - 1.6, 2.2, -0.72), 0.06, 0.06, K_SAFETY, SAFETY)
	# The motor on its slide rails, the sheaves and the belt guard down the left side.
	_box(Vector3(-9.75, 0.86, 0.0), Vector3(1.2, 0.2, 1.0), K_PAINT_DARK)
	# The motor: a finned frame between two end bells, its fan cowl, feet and terminal box.
	var mc := Vector3(-9.75, 1.36, 0.0)
	var motor := Color(0.28, 0.34, 0.36)
	_cyl(mc + Vector3(0, 0, -0.42), mc + Vector3(0, 0, 0.3), 0.34, 14, K_PLAIN, motor)
	for i in 10:
		var a := TAU * (float(i) + 0.5) / 10.0
		if sin(a) < -0.5:
			continue
		var d := Vector3(cos(a), sin(a), 0.0)
		_box(mc + d * 0.37, Vector3(0.06, 0.06, 0.62), K_PLAIN, motor * 0.92, Basis(Vector3(0, 0, 1), a))
	_cyl(mc + Vector3(0, 0, 0.3), mc + Vector3(0, 0, 0.38), 0.37, 14, K_PLAIN, motor * 0.85)
	_cyl(mc + Vector3(0, 0, -0.62), mc + Vector3(0, 0, -0.42), 0.36, 14, K_PLAIN, Color(0.2, 0.22, 0.23))
	for s: float in [-1.0, 1.0]:
		_box(mc + Vector3(0.22 * s, -0.34, -0.06), Vector3(0.16, 0.12, 0.62), K_PLAIN, motor * 0.8)
	_box(mc + Vector3(0, 0.42, -0.05), Vector3(0.3, 0.2, 0.28), K_PLAIN, Color(0.24, 0.28, 0.3))
	_cyl(mc + Vector3(0, 0.52, -0.05), mc + Vector3(0.0, 0.52, -0.05) + Vector3(-0.9, -0.2, 0.0), 0.03, 6, K_STEEL, GALV)
	_box(Vector3(-8.75, 1.45, 0.7), Vector3(2.5, 1.25, 0.18), K_PAINT_DARK)
	_cyl(Vector3(-9.75, 1.36, 0.36), Vector3(-9.75, 1.36, 0.58), 0.2, 10, K_STEEL, DARK)
	# The wellhead: casing, flanges, the flow tee with its valves, the stuffing box, the flowline.
	_cyl(Vector3(0, -0.3, 0), Vector3(0, 0.55, 0), 0.19, 12, K_PLAIN, Color(0.42, 0.4, 0.37))
	_cyl(Vector3(0, 0.55, 0), Vector3(0, 0.66, 0), 0.31, 12, K_PLAIN, Color(0.36, 0.34, 0.32))
	_cyl(Vector3(0, 0.66, 0), Vector3(0, 1.32, 0), 0.12, 10, K_PLAIN, Color(0.42, 0.4, 0.37))
	_cyl(Vector3(0, 0.95, 0), Vector3(0, 1.03, 0), 0.22, 10, K_PLAIN, Color(0.36, 0.34, 0.32))
	_cyl(Vector3(0, 1.32, 0), Vector3(0, 1.62, 0), 0.1, 10, K_STEEL, DARK)
	_cyl(Vector3(0, 1.12, -0.12), Vector3(0, 1.12, -0.95), 0.07, 8, K_PLAIN, Color(0.42, 0.4, 0.37))
	_box(Vector3(0, 1.12, -0.5), Vector3(0.2, 0.26, 0.2), K_PLAIN, Color(0.3, 0.32, 0.34))
	_cyl(Vector3(0, 1.38, -0.5), Vector3(0, 1.44, -0.5), 0.17, 10, K_PLAIN, Color(0.62, 0.12, 0.08), false)
	_box(Vector3(0, 0.8, 0.28), Vector3(0.2, 0.24, 0.2), K_PLAIN, Color(0.3, 0.32, 0.34))
	_cyl(Vector3(0.15, 0.8, 0.28), Vector3(0.22, 0.8, 0.28), 0.15, 10, K_PLAIN, Color(0.62, 0.12, 0.08), false)
	_cyl(Vector3(0, 1.28, 0.1), Vector3(0, 1.28, 0.24), 0.05, 8, K_PLAIN, Color(0.85, 0.85, 0.82))
	_cyl(Vector3(0, 1.12, -0.95), Vector3(0, 0.25, -0.95), 0.07, 8, K_PLAIN, Color(0.42, 0.4, 0.37))
	_cyl(Vector3(0, 0.25, -0.95), Vector3(2.2, 0.25, -0.95), 0.07, 8, K_PLAIN, Color(0.42, 0.4, 0.37))
	# A pipe guard round the wellhead.
	for c: Vector2 in [Vector2(0.75, 0.75), Vector2(0.75, -0.75), Vector2(-0.75, 0.75), Vector2(-0.75, -0.75)]:
		_cyl(Vector3(c.x, -0.1, c.y), Vector3(c.x, 1.0, c.y), 0.05, 6, K_SAFETY, SAFETY)
	for e: Array in [[Vector2(0.75, 0.75), Vector2(0.75, -0.75)], [Vector2(-0.75, 0.75), Vector2(0.75, 0.75)], [Vector2(-0.75, -0.75), Vector2(0.75, -0.75)]]:
		var a: Vector2 = e[0]
		var b: Vector2 = e[1]
		_cyl(Vector3(a.x, 0.95, a.y), Vector3(b.x, 0.95, b.y), 0.04, 6, K_SAFETY, SAFETY, false)
	# --- The walking beam, the horsehead and the equalizer (rock about the pivot).
	_part(1)
	var beam_y := py + 0.42
	var x_tail := px - TAIL - 0.35
	var x_head := px + FRONT - 1.05
	_box(Vector3((x_tail + x_head) * 0.5, beam_y, 0.0), Vector3(x_head - x_tail, 0.56, 0.1), K_PAINT)
	_box(Vector3((x_tail + x_head) * 0.5, beam_y + 0.31, 0.0), Vector3(x_head - x_tail, 0.06, 0.34), K_PAINT)
	_box(Vector3((x_tail + x_head) * 0.5, beam_y - 0.31, 0.0), Vector3(x_head - x_tail, 0.06, 0.34), K_PAINT)
	for x: float in [x_tail + 0.2, px - 1.6, px - 0.25, px + 0.25, px + 1.6, x_head - 0.15]:
		_box(Vector3(x, beam_y, 0.0), Vector3(0.05, 0.56, 0.32), K_PAINT)
	# The beam's bearing housing on the saddle.
	_box(Vector3(px, py + 0.1, 0.0), Vector3(0.5, 0.16, 0.42), K_PAINT_DARK)
	# The horsehead: side plates following the arc, the curved face the wire rope rides on.
	var face := _arc(PIVOT, FRONT, -17.0, 18.0, 14)
	var back := _arc(PIVOT, FRONT - 1.25, 16.0, -11.0, 6)
	var poly := PackedVector2Array()
	poly.append_array(face)
	poly.append(Vector2(x_head - 0.1, beam_y + 0.34))
	poly.append_array(back)
	poly.append(Vector2(x_head - 0.1, beam_y - 0.34))
	_prism(poly, -0.34, 0.34, K_PAINT)
	# The wire guide on the face (a darker band) and the stiffening ribs on the sides.
	var face_in := _arc(PIVOT, FRONT + 0.02, -17.0, 18.0, 14)
	for i in face_in.size() - 1:
		var a := face_in[i]
		var b := face_in[i + 1]
		_strut(Vector3(a.x, a.y, 0.0), Vector3(b.x, b.y, 0.0), 0.04, 0.5, K_PAINT_DARK)
	for s: float in [-0.36, 0.36]:
		_strut(Vector3(face[3].x - 0.05, face[3].y, s), Vector3(x_head, beam_y - 0.1, s), 0.06, 0.03, K_PAINT_DARK)
		_strut(Vector3(face[11].x - 0.05, face[11].y, s), Vector3(x_head, beam_y + 0.1, s), 0.06, 0.03, K_PAINT_DARK)
	# The equalizer across the tail and its bearing.
	_box(Vector3(px - TAIL, py + 0.04, 0.0), Vector3(0.32, 0.3, 2.2), K_PAINT)
	_box(Vector3(px - TAIL, beam_y, 0.0), Vector3(0.6, 0.5, 0.42), K_PAINT_DARK)
	# --- The crank: two arms, their counterweights, the wrist pins (turn about the shaft).
	_part(2)
	for s: float in [-1.0, 1.0]:
		var z0 := 0.72 * s
		var z1 := 0.92 * s
		var arm := PackedVector2Array([
			CRANK + Vector2(-0.35, -0.42), CRANK + Vector2(CRANK_R + 0.22, -0.2), CRANK + Vector2(CRANK_R + 0.22, 0.2), CRANK + Vector2(-0.35, 0.42)])
		_prism(arm, minf(z0, z1), maxf(z0, z1), K_PAINT_DARK)
		# The counterweights: two cast blocks a side, faced with the warning stripe.
		var wz0 := 0.94 * s
		var wz1 := 1.16 * s
		var wt := PackedVector2Array()
		for p: Vector2 in _arc(Vector2.ZERO, 1.05, -40.0, 40.0, 6):
			wt.append(CRANK + Vector2(p.x * 1.0 + 0.05, p.y))
		for p: Vector2 in _arc(Vector2.ZERO, 0.38, 40.0, -40.0, 3):
			wt.append(CRANK + p)
		_prism(wt, minf(wz0, wz1), maxf(wz0, wz1), K_WEIGHT)
		_cyl(Vector3(CRANK.x + CRANK_R, CRANK.y, 0.62 * s), Vector3(CRANK.x + CRANK_R, CRANK.y, 1.0 * s), 0.1, 8, K_STEEL, DARK)
		_cyl(Vector3(CRANK.x, CRANK.y, 0.88 * s), Vector3(CRANK.x, CRANK.y, 0.95 * s), 0.3, 12, K_STEEL, DARK, false)
	# --- The pitman arms, from the wrist pins to the equalizer's ends.
	_part(3)
	for s: float in [-1.0, 1.0]:
		var a := Vector3(CRANK.x + CRANK_R, CRANK.y, 0.98 * s)
		var b := Vector3(px - TAIL, py, 0.98 * s)
		_strut(a, b, 0.16, 0.12, K_PAINT)
		_strut(a + Vector3(0, 0.0, 0), a + Vector3(0, 0.3, 0), 0.26, 0.14, K_PAINT_DARK)
	# --- The bridle: two wire ropes down from the horsehead.
	_part(4)
	for s: float in [-0.11, 0.11]:
		_box(Vector3(0.0, (CARRIER_Y + py) * 0.5, s), Vector3(0.035, py - CARRIER_Y, 0.035), K_CABLE, Color(0.3, 0.3, 0.3))
	# --- The carrier bar, the rod clamp and the polished rod (slide with the wire).
	_part(5)
	_box(Vector3(0.0, CARRIER_Y, 0.0), Vector3(0.16, 0.12, 0.42), K_STEEL, DARK)
	_box(Vector3(0.0, CARRIER_Y + 0.14, 0.0), Vector3(0.12, 0.16, 0.12), K_STEEL, DARK)
	_cyl(Vector3(0.0, 0.25, 0.0), Vector3(0.0, CARRIER_Y + 0.3, 0.0), 0.032, 8, K_ROD, Color(0.85, 0.85, 0.85))
	_part(0)


## The far pumpjack: post, beam, head, crank and weights, pitman, gearbox, motor, base - a few
## boxes each, the same moving parts.
func _build_far() -> void:
	var px := PIVOT.x
	var py := PIVOT.y
	_part(0)
	_box(Vector3(-5.9, 0.3, 0.0), Vector3(9.8, 0.7, 1.8), K_PAINT_DARK)
	_strut(Vector3(-2.4, 0.7, 0.0), Vector3(px, py, 0.0), 0.5, 1.0, K_PAINT)
	_strut(Vector3(-5.5, 0.7, 0.0), Vector3(px - 0.1, py - 0.1, 0.0), 0.3, 0.8, K_PAINT)
	_box(Vector3(CRANK.x, 1.6, 0.0), Vector3(1.6, 1.6, 1.2), K_PAINT)
	_box(Vector3(-9.6, 1.2, 0.0), Vector3(1.0, 0.9, 0.9), K_PLAIN, Color(0.28, 0.34, 0.36))
	_box(Vector3(0.0, 0.7, 0.0), Vector3(0.4, 1.4, 0.4), K_PLAIN, Color(0.4, 0.38, 0.36))
	_part(1)
	_box(Vector3((px - TAIL + px + FRONT - 1.0) * 0.5, py + 0.42, 0.0), Vector3(FRONT + TAIL - 0.6, 0.66, 0.36), K_PAINT)
	var face := _arc(PIVOT, FRONT, -17.0, 18.0, 4)
	var poly := PackedVector2Array()
	poly.append_array(face)
	poly.append_array(_arc(PIVOT, FRONT - 1.25, 16.0, -11.0, 2))
	_prism(poly, -0.34, 0.34, K_PAINT)
	_part(2)
	for s: float in [-1.0, 1.0]:
		_box(Vector3(CRANK.x + 0.5, CRANK.y, 1.0 * s), Vector3(2.0, 0.9, 0.3), K_WEIGHT)
	_part(3)
	_strut(Vector3(CRANK.x + CRANK_R, CRANK.y, 0.0), Vector3(px - TAIL, py, 0.0), 0.2, 2.0, K_PAINT)
	_part(4)
	_box(Vector3(0.0, (CARRIER_Y + py) * 0.5, 0.0), Vector3(0.06, py - CARRIER_Y, 0.25), K_CABLE, Color(0.3, 0.3, 0.3))
	_part(5)
	_box(Vector3(0.0, CARRIER_Y - 0.6, 0.0), Vector3(0.12, 1.3, 0.42), K_STEEL, DARK)
	_part(0)


# --- Field hardware (IndustrialKit writers into a chunk's walls mesh) --------------------------------

## A box from `a` to `b` (its axis), `w` wide across `side` and `d` deep, through IndustrialKit.
static func strut(st: SurfaceTool, a: Vector3, b: Vector3, w: float, d: float, kind: int, paint: Color, side: Vector3 = Vector3.UP) -> void:
	var ax := b - a
	var len := ax.length()
	if len < 1e-3:
		return
	var z := ax / len
	var x := side.cross(z)
	if x.length_squared() < 1e-6:
		x = Vector3(1, 0, 0).cross(z)
		if x.length_squared() < 1e-6:
			x = Vector3(0, 1, 0).cross(z)
	x = x.normalized()
	var y := z.cross(x).normalized()
	IndustrialKit.box(st, Transform3D(Basis(x, y, z), (a + b) * 0.5), Vector3(w, d, len), kind, paint, 0.0, 0)


## A pipe from `a` to `b` (an upright-cylinder writer turned onto the axis).
static func pipe(st: SurfaceTool, a: Vector3, b: Vector3, r: float, paint: Color, segs: int = 8, kind: int = IndustrialKit.K_STEEL) -> void:
	var ax := b - a
	var len := ax.length()
	if len < 1e-3:
		return
	var y := ax / len
	var x := Vector3(0, 0, 1).cross(y)
	if x.length_squared() < 1e-4:
		x = Vector3(1, 0, 0).cross(y)
	x = x.normalized()
	var z := x.cross(y).normalized()
	IndustrialKit.cyl(st, Transform3D(Basis(x, y, z), a), r, len, kind, paint, segs, false)


## A vertical storage tank: shell, cone roof, a ring of stiffener, the thief hatch, a ladder up its
## side (base centre `at`, facing `out` for the ladder).
static func tank(st: SurfaceTool, at: Vector3, r: float, h: float, paint: Color, out: Vector3) -> void:
	IndustrialKit.cyl(st, Transform3D(Basis(), at), r, h, IndustrialKit.K_TANK, paint, 20, false)
	IndustrialKit.cone(st, Transform3D(Basis(), at + Vector3(0, h, 0)), r + 0.06, r * 0.18, IndustrialKit.K_TANK, paint * 0.92, 20)
	IndustrialKit.cyl(st, Transform3D(Basis(), at + Vector3(0, h - 0.12, 0)), r + 0.05, 0.12, IndustrialKit.K_STEEL, paint * 0.8, 20, false)
	IndustrialKit.box(st, Transform3D(Basis(), at + Vector3(r * 0.4, h + r * 0.12, 0)), Vector3(0.5, 0.3, 0.5), IndustrialKit.K_STEEL, paint * 0.7)
	var side := out.cross(Vector3.UP).normalized()
	var foot := at + out * (r + 0.25)
	for s: float in [-0.22, 0.22]:
		strut(st, foot + side * s, foot + side * s + Vector3(0, h + 0.9, 0), 0.05, 0.05, IndustrialKit.K_GALV, GALV, out)
	var rungs := int(h / 0.32)
	for i in rungs:
		IndustrialKit.box(st, Transform3D(Basis(side, Vector3.UP, side.cross(Vector3.UP)), foot + Vector3(0, 0.3 + float(i) * 0.32, 0)), Vector3(0.44, 0.03, 0.03), IndustrialKit.K_GALV, GALV, 0.0, 0)
	# Safety cage hoops.
	for i in int(h / 1.2):
		var y := 2.4 + float(i) * 1.2
		if y > h + 0.6:
			break
		for s: float in [-1.0, 1.0]:
			strut(st, foot + side * 0.3 * s + Vector3(0, y, 0), foot + side * 0.3 * s + out * 0.7 + Vector3(0, y, 0), 0.03, 0.03, IndustrialKit.K_GALV, GALV)
		strut(st, foot + out * 0.7 + side * 0.3 + Vector3(0, y, 0), foot + out * 0.7 - side * 0.3 + Vector3(0, y, 0), 0.03, 0.03, IndustrialKit.K_GALV, GALV)


## A railing along `a`..`b` (both at walking level): posts every ~1.8 m, top and mid rails.
static func railing(st: SurfaceTool, a: Vector3, b: Vector3, paint: Color = SAFETY) -> void:
	var len := a.distance_to(b)
	var n := maxi(1, ceili(len / 1.8))
	for i in n + 1:
		var p := a.lerp(b, float(i) / float(n))
		strut(st, p, p + Vector3(0, 1.07, 0), 0.04, 0.04, IndustrialKit.K_STEEL, paint)
	strut(st, a + Vector3(0, 1.07, 0), b + Vector3(0, 1.07, 0), 0.045, 0.045, IndustrialKit.K_STEEL, paint)
	strut(st, a + Vector3(0, 0.55, 0), b + Vector3(0, 0.55, 0), 0.035, 0.035, IndustrialKit.K_STEEL, paint)


## A drilling rig's mast: a tapering four-leg lattice from a `base` square at `at` up `h`, the
## crown block on top, the travelling block and the kelly hanging inside. `face` is the V-door side.
static func derrick(st: SurfaceTool, at: Vector3, base: float, h: float, paint: Color, face: Vector3) -> void:
	var side := face.cross(Vector3.UP).normalized()
	var top := base * 0.24
	var corners := [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
	var leg := func(c: Vector2, y: float) -> Vector3:
		var w := lerpf(base, top, y / h) * 0.5
		return at + side * c.x * w + face * c.y * w + Vector3(0, y, 0)
	for c: Vector2 in corners:
		strut(st, leg.call(c, 0.0), leg.call(c, h), 0.22, 0.22, IndustrialKit.K_STEEL, paint, face)
	var levels := 12
	for l in levels:
		var y0 := h * float(l) / float(levels)
		var y1 := h * float(l + 1) / float(levels)
		for k in 4:
			var a: Vector2 = corners[k]
			var b: Vector2 = corners[(k + 1) % 4]
			# The V-door face is open low down (pipe goes in through it).
			if k == 2 and l < 3:
				continue
			strut(st, leg.call(a, y1), leg.call(b, y1), 0.1, 0.1, IndustrialKit.K_STEEL, paint, Vector3.UP)
			strut(st, leg.call(a, y0), leg.call(b, y1), 0.07, 0.07, IndustrialKit.K_STEEL, paint, Vector3.UP)
	# The crown block, the monkey board, the travelling block and its lines.
	IndustrialKit.box(st, Transform3D(Basis(), at + Vector3(0, h + 0.5, 0)), Vector3(top + 0.8, 1.0, top + 0.8), IndustrialKit.K_STEEL, paint * 0.8)
	IndustrialKit.box(st, Transform3D(Basis(), at + Vector3(0, h * 0.68, 0) + face * (lerpf(base, top, 0.68) * 0.5 + 0.6)), Vector3(lerpf(base, top, 0.68) + 0.4, 0.15, 1.2), IndustrialKit.K_GALV, GALV)
	var block_y := h * 0.45
	IndustrialKit.box(st, Transform3D(Basis(), at + Vector3(0, block_y, 0)), Vector3(0.9, 1.8, 0.7), IndustrialKit.K_STEEL, SAFETY)
	for s: float in [-0.25, 0.0, 0.25]:
		strut(st, at + Vector3(s, block_y + 0.9, 0), at + Vector3(s, h, 0), 0.03, 0.03, IndustrialKit.K_STEEL, DARK)
	strut(st, at + Vector3(0, block_y - 0.9, 0), at + Vector3(0, 1.0, 0), 0.14, 0.14, IndustrialKit.K_STEEL, DARK)


## A chain-link fence along `a`..`b` (feet on the ground, `h` high), its posts every 3 m with a
## barbed-wire top on arms. The posts and the top follow the ground through `ground` (x, z) -> y.
static func fence(st: SurfaceTool, a: Vector2, b: Vector2, h: float, ground: Callable, barbed: bool = true) -> void:
	var len := a.distance_to(b)
	if len < 0.5:
		return
	var n := maxi(1, ceili(len / 3.0))
	var dir := (b - a) / len
	var nrm := Vector3(-dir.y, 0.0, dir.x)
	for i in n:
		var p0 := a.lerp(b, float(i) / float(n))
		var p1 := a.lerp(b, float(i + 1) / float(n))
		var y0: float = ground.call(p0.x, p0.y)
		var y1: float = ground.call(p1.x, p1.y)
		var seg := p0.distance_to(p1)
		var m := (p0 + p1) * 0.5
		var ym := (y0 + y1) * 0.5
		# The mesh panel, tilted with the ground along it.
		var xa := Vector3(p1.x - p0.x, y1 - y0, p1.y - p0.y).normalized()
		var basis := Basis(xa, Vector3.UP, xa.cross(Vector3.UP).normalized())
		IndustrialKit.box(st, Transform3D(basis, Vector3(m.x, ym + h * 0.5, m.y)), Vector3(seg, h, 0.02), IndustrialKit.K_CHAIN, GALV, 0.0, 16 | 32)
		IndustrialKit.cyl(st, Transform3D(Basis(), Vector3(p0.x, y0 - 0.1, p0.y)), 0.035, h + (0.55 if barbed else 0.1), IndustrialKit.K_GALV, GALV, 6, false)
		strut(st, Vector3(p0.x, y0 + h, p0.y), Vector3(p1.x, y1 + h, p1.y), 0.04, 0.04, IndustrialKit.K_GALV, GALV)
		if barbed:
			var arm := nrm * 0.0 + Vector3(0, 0.45, 0)
			IndustrialKit.box(st, Transform3D(basis, Vector3(m.x, ym + h + 0.25, m.y) + arm * 0.0), Vector3(seg, 0.42, 0.02), IndustrialKit.K_BARBED, Color(0.5, 0.5, 0.5), 0.0, 16 | 32)
	var ye: float = ground.call(b.x, b.y)
	IndustrialKit.cyl(st, Transform3D(Basis(), Vector3(b.x, ye - 0.1, b.y)), 0.045, h + (0.55 if barbed else 0.1), IndustrialKit.K_GALV, GALV, 6, false)


## A warning sign on two posts: the operator's board (white, a red DANGER band, black lines), its
## face toward `face` (unit XZ), its foot at `at`.
static func sign(st: SurfaceTool, at: Vector3, face: Vector2, lines: Array, w: float = 1.5, board_h: float = 1.0, post_h: float = 1.1) -> void:
	var n := Vector3(face.x, 0.0, face.y).normalized()
	var x := Vector3.UP.cross(n).normalized()
	var basis := Basis(x, Vector3.UP, n)
	var c := at + Vector3(0, post_h + board_h * 0.5, 0)
	for s: float in [-0.38, 0.38]:
		IndustrialKit.cyl(st, Transform3D(Basis(), at + x * s * w - n * 0.04), 0.035, post_h + board_h - 0.05, IndustrialKit.K_GALV, GALV, 6, false)
	IndustrialKit.box(st, Transform3D(basis, c), Vector3(w, board_h, 0.03), IndustrialKit.K_STEEL, Color(0.9, 0.9, 0.86), 0.0, 0)
	IndustrialKit.box(st, Transform3D(basis, c + Vector3(0, board_h * 0.33, 0) + n * 0.018), Vector3(w * 0.94, board_h * 0.26, 0.005), IndustrialKit.K_STEEL, Color(0.72, 0.1, 0.08), 0.0, 0)
	text(st, "DANGER", Transform3D(basis, c + Vector3(0, board_h * 0.33, 0) + n * 0.024), board_h * 0.16, Color(0.95, 0.95, 0.92), w * 0.85)
	for i in lines.size():
		var y := board_h * (0.07 - 0.2 * float(i))
		text(st, String(lines[i]), Transform3D(basis, c + Vector3(0, y, 0) + n * 0.02), board_h * 0.1, Color(0.08, 0.08, 0.08), w * 0.9)


## Lettering (FreewayKit.text_geo, flat, facing the basis' +Z) written into `st` as painted steel,
## shrunk to `max_w` metres wide.
static func text(st: SurfaceTool, s: String, xf: Transform3D, height: float, paint: Color, max_w: float = 100.0) -> void:
	var geo := FreewayKit.text_geo(s, height)
	var verts: PackedVector3Array = geo[0]
	var idx: PackedInt32Array = geo[1]
	var wdt: float = geo[2]
	var k := minf(1.0, max_w / maxf(wdt, 0.01))
	var n := (xf.basis * Vector3(0, 0, 1)).normalized()
	var col := IndustrialKit.kind_color(IndustrialKit.K_STEEL, paint)
	for i in idx.size():
		var v := verts[idx[i]]
		st.set_normal(n)
		st.set_color(col)
		st.set_uv(Vector2(v.x, v.y))
		st.set_uv2(Vector2(1.0, 0.0))
		st.add_vertex(xf * Vector3(v.x * k, v.y, 0.0))


## A wooden utility pole with a crossarm (three insulators) at `at`, the arm across `across`.
static func pole(st: SurfaceTool, at: Vector3, h: float, across: Vector3) -> void:
	IndustrialKit.cyl(st, Transform3D(Basis(), at), 0.15, h, IndustrialKit.K_WOOD, Color(0.42, 0.33, 0.24), 8, true)
	var x := across.normalized()
	var top := at + Vector3(0, h - 0.5, 0)
	strut(st, top - x * 1.2, top + x * 1.2, 0.1, 0.12, IndustrialKit.K_WOOD, Color(0.4, 0.31, 0.22), Vector3.UP)
	for s: float in [-1.0, 0.0, 1.0]:
		IndustrialKit.cyl(st, Transform3D(Basis(), top + x * s * 1.0 + Vector3(0, 0.06, 0)), 0.05, 0.2, IndustrialKit.K_PLASTIC, Color(0.55, 0.6, 0.58), 6, true)
	# A transformer can on some poles is placed by the caller.


## A sagging wire from `a` to `b` (insulator tops), `sag` metres at mid-span, in `n` pieces.
static func wire(st: SurfaceTool, a: Vector3, b: Vector3, sag: float, n: int = 6) -> void:
	var prev := a
	for i in range(1, n + 1):
		var t := float(i) / float(n)
		var p := a.lerp(b, t) - Vector3(0, sag * 4.0 * t * (1.0 - t), 0)
		strut(st, prev, p, 0.022, 0.022, IndustrialKit.K_STEEL, DARK)
		prev = p
