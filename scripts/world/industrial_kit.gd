class_name IndustrialKit
extends RefCounted
## The industrial district's geometry (Industrial lays it out): a box and a cylinder writer that
## give every face UV in metres in its own frame and say what the surface is in the vertex colour,
## so ONE material (shaders/industrial_walls.gdshader) draws tilt-up walls, roofs, dock doors,
## chain-link, corrugated sheds, trailers, boxcars, tanks and pallets; and the props that repeat
## (trailers, tractors, boxcars, tank cars, pallet loads, drums, dumpsters) as cached meshes for the
## chunk's MultiMesh batches. Everything here is pure geometry: no rolls, no nodes.
##
## Vertex layout (the contract with the shader):
##   COLOR.rgb  the paint as written (sRGB numbers; vertex colours arrive raw on both renderers)
##   COLOR.a    the kind (K_*), in 32nds
##   UV         metres in the face's own frame: x along the face from its left corner as seen from
##              outside, y up from the box's foot (a top face: x and z from the box's corner)
##   UV2        x the box's height, y a per-box parameter (a tilt-up wall's panel width, a mural's
##              width, a door's slat pitch)

# --- Kinds (COLOR.a in 32nds; mirrored in industrial_walls.gdshader) ----------------------------
const K_TILTUP := 0
const K_ROOF := 1
const K_BRICK := 2
const K_ROLLUP := 3
const K_RUBBER := 4
const K_STEEL := 5
const K_CHAIN := 6
const K_BARBED := 7
const K_GLASS := 8
const K_CORRUGATED := 9
const K_MURAL := 10
const K_LAMP := 11
const K_TRAILER := 12
const K_BOXCAR := 13
const K_TANK := 14
const K_CONCRETE := 15
const K_WOOD := 16
const K_WRAP := 17
const K_PLASTIC := 18
const K_GALV := 19
const K_SKYLIGHT := 20
const KIND_COUNT := 21

static var _material: ShaderMaterial
static var _cache: Dictionary = {}
## Record mode (place()): the props are written straight into a chunk's walls mesh, moved by
## `_xf` and painted by `_tint` (what a batch's instance transform and colour would do), so a
## chunk's trailers, rail cars, pallets and tanks cost no draw of their own.
static var _into: SurfaceTool = null
static var _xf: Transform3D = Transform3D()
static var _tint: Color = Color.WHITE


## Writes the prop `build` makes (a call of one of the mesh functions below) into `st`, placed by
## `xf` and tinted by `tint`, instead of returning a cached mesh.
static func place(st: SurfaceTool, xf: Transform3D, tint: Color, build: Callable) -> void:
	_into = st
	_xf = xf
	_tint = tint
	build.call()
	_into = null
	_xf = Transform3D()
	_tint = Color.WHITE


static func walls_material() -> ShaderMaterial:
	if _material != null:
		return _material
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/industrial_walls.gdshader")
	mat.set_shader_parameter("concrete_tex", PropFactory.texture("concrete", "Color"))
	mat.set_shader_parameter("cracked_tex", PropFactory.texture("concrete_cracked", "Color"))
	mat.set_shader_parameter("brick_tex", PropFactory.texture("brick_factory", "Color"))
	mat.set_shader_parameter("brick_nrm", PropFactory.texture("brick_factory", "NormalGL"))
	mat.set_shader_parameter("corrugated_tex", PropFactory.texture("metal_corrugated", "Color"))
	mat.set_shader_parameter("planks_tex", PropFactory.texture("planks", "Color"))
	_material = mat
	return mat


static func kind_color(kind: int, paint: Color) -> Color:
	return Color(paint.r * _tint.r, paint.g * _tint.g, paint.b * _tint.b, (float(kind) + 0.5) / 32.0)


# --- Writers ----------------------------------------------------------------------------------

## The six faces of a unit box: outward normal, then four corners counter-clockwise seen from
## outside (Godot's front faces are clockwise to the viewer, so each quad is laid 0-2-1, 0-3-2),
## in -0.5..0.5. The first corner is the face's bottom left seen from outside.
const FACES := [
	[Vector3(1, 0, 0), [Vector3(0.5, -0.5, 0.5), Vector3(0.5, -0.5, -0.5), Vector3(0.5, 0.5, -0.5), Vector3(0.5, 0.5, 0.5)]],
	[Vector3(-1, 0, 0), [Vector3(-0.5, -0.5, -0.5), Vector3(-0.5, -0.5, 0.5), Vector3(-0.5, 0.5, 0.5), Vector3(-0.5, 0.5, -0.5)]],
	[Vector3(0, 0, 1), [Vector3(-0.5, -0.5, 0.5), Vector3(0.5, -0.5, 0.5), Vector3(0.5, 0.5, 0.5), Vector3(-0.5, 0.5, 0.5)]],
	[Vector3(0, 0, -1), [Vector3(0.5, -0.5, -0.5), Vector3(-0.5, -0.5, -0.5), Vector3(-0.5, 0.5, -0.5), Vector3(0.5, 0.5, -0.5)]],
	[Vector3(0, 1, 0), [Vector3(-0.5, 0.5, 0.5), Vector3(0.5, 0.5, 0.5), Vector3(0.5, 0.5, -0.5), Vector3(-0.5, 0.5, -0.5)]],
	[Vector3(0, -1, 0), [Vector3(-0.5, -0.5, -0.5), Vector3(0.5, -0.5, -0.5), Vector3(0.5, -0.5, 0.5), Vector3(-0.5, -0.5, 0.5)]],
]


## A box of `size` placed by `xf` (its centre and turn; no scale) into `st`. `skip` is a bitmask of
## faces left out (FACES' order: 1 +x, 2 -x, 4 +z, 8 -z, 16 top, 32 bottom; the bottom is left out
## unless asked for).
static func box(st: SurfaceTool, xf: Transform3D, size: Vector3, kind: int, paint: Color, param: float = 0.0, skip: int = 32) -> void:
	xf = _xf * xf
	var col := kind_color(kind, paint)
	for f in 6:
		if skip & (1 << f):
			continue
		var fc: Array = FACES[f]
		var n: Vector3 = fc[0]
		var q: Array = fc[1]
		var pts: Array[Vector3] = []
		var uvs: Array[Vector2] = []
		for c: Vector3 in q:
			var p := c * size
			pts.append(xf * p)
			var uv: Vector2
			if absf(n.y) > 0.5:
				uv = Vector2(p.x + size.x * 0.5, p.z + size.z * 0.5)
			elif absf(n.x) > 0.5:
				uv = Vector2((p.z + size.z * 0.5) if n.x < 0.0 else (size.z * 0.5 - p.z), p.y + size.y * 0.5)
			else:
				uv = Vector2((p.x + size.x * 0.5) if n.z > 0.0 else (size.x * 0.5 - p.x), p.y + size.y * 0.5)
			uvs.append(uv)
		var wn := (xf.basis * n).normalized()
		for k: int in [0, 2, 1, 0, 3, 2]:
			st.set_normal(wn)
			st.set_color(col)
			st.set_uv(uvs[k])
			st.set_uv2(Vector2(size.y, param))
			st.add_vertex(pts[k])


## An upright cylinder (axis +y in `xf`), `segs` sided, foot at xf's origin, with its top cap.
static func cyl(st: SurfaceTool, xf: Transform3D, r: float, h: float, kind: int, paint: Color, segs: int = 12, cap: bool = true) -> void:
	xf = _xf * xf
	var col := kind_color(kind, paint)
	var circ := TAU * r
	for i in segs:
		var a0 := TAU * float(i) / float(segs)
		var a1 := TAU * float(i + 1) / float(segs)
		var d0 := Vector3(cos(a0), 0.0, sin(a0))
		var d1 := Vector3(cos(a1), 0.0, sin(a1))
		var p00 := xf * (d0 * r)
		var p10 := xf * (d1 * r)
		var p01 := xf * (d0 * r + Vector3(0.0, h, 0.0))
		var p11 := xf * (d1 * r + Vector3(0.0, h, 0.0))
		var n0 := (xf.basis * d0).normalized()
		var n1 := (xf.basis * d1).normalized()
		var u0 := circ * float(i) / float(segs)
		var u1 := circ * float(i + 1) / float(segs)
		# Counter-clockwise from outside: p00, p10, p11, p01 seen with +y up as the angle grows
		# toward -z... laid 0-2-1, 0-3-2 after checking the face really faces out.
		var quad := [p00, p10, p11, p01]
		var ns := [n0, n1, n1, n0]
		var uvs := [Vector2(u0, 0.0), Vector2(u1, 0.0), Vector2(u1, h), Vector2(u0, h)]
		var order := [0, 2, 1, 0, 3, 2]
		if ((p10 - p00).cross(p01 - p00)).dot(n0 + n1) > 0.0:
			order = [0, 1, 2, 0, 2, 3]
		for k: int in order:
			st.set_normal(ns[k])
			st.set_color(col)
			st.set_uv(uvs[k])
			st.set_uv2(Vector2(h, 0.0))
			st.add_vertex(quad[k])
		if cap:
			var top := xf * Vector3(0.0, h, 0.0)
			var up := (xf.basis * Vector3.UP).normalized()
			var tri := [top, p01, p11]
			if ((p01 - top).cross(p11 - top)).dot(up) > 0.0:
				tri = [top, p11, p01]
			for p: Vector3 in tri:
				var l := xf.affine_inverse() * p
				st.set_normal(up)
				st.set_color(col)
				st.set_uv(Vector2(l.x + r, l.z + r))
				st.set_uv2(Vector2(h, 0.0))
				st.add_vertex(p)


## A horizontal cylinder along local +z (a tank car's barrel, a fuel tank), centre at xf's origin.
static func cyl_z(st: SurfaceTool, xf: Transform3D, r: float, length: float, kind: int, paint: Color, segs: int = 12) -> void:
	cyl(st, xf * Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0.0, 0.0, -length * 0.5)), r, length, kind, paint, segs, true)
	cyl(st, xf * Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0.0, 0.0, length * 0.5)), r, 0.001, kind, paint, segs, true)


## A cone from radius `r` at the foot to a point `h` above (a tank's roof).
static func cone(st: SurfaceTool, xf: Transform3D, r: float, h: float, kind: int, paint: Color, segs: int = 12) -> void:
	xf = _xf * xf
	var col := kind_color(kind, paint)
	var tip := xf * Vector3(0.0, h, 0.0)
	var slope := Vector2(h, r).normalized()
	for i in segs:
		var a0 := TAU * float(i) / float(segs)
		var a1 := TAU * float(i + 1) / float(segs)
		var p0 := xf * Vector3(cos(a0) * r, 0.0, sin(a0) * r)
		var p1 := xf * Vector3(cos(a1) * r, 0.0, sin(a1) * r)
		var am := (a0 + a1) * 0.5
		var n := (xf.basis * Vector3(cos(am) * slope.x, slope.y, sin(am) * slope.x)).normalized()
		var tri := [p0, tip, p1]
		if ((tip - p0).cross(p1 - p0)).dot(n) > 0.0:
			tri = [p0, p1, tip]
		for p: Vector3 in tri:
			var l := xf.affine_inverse() * p
			st.set_normal(n)
			st.set_color(col)
			st.set_uv(Vector2(l.x + r, l.z + r))
			st.set_uv2(Vector2(h, 0.0))
			st.add_vertex(p)


static func _begin() -> SurfaceTool:
	if _into != null:
		return _into
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	return st


static func _commit(key: String, st: SurfaceTool, shadow: Array = []) -> Mesh:
	if _into != null:
		return null
	st.set_material(walls_material())
	var mesh := st.commit()
	_cache[key] = mesh
	# A box stand-in casts the shadow (a trailer's or a boxcar's detail is invisible in one).
	if not shadow.is_empty():
		var sh := _begin()
		for b: Array in shadow:
			box(sh, Transform3D(Basis(), b[1]), b[0], K_CONCRETE, Color.WHITE, 0.0, 32)
		sh.set_material(walls_material())
		PropFactory._shadow_proxies[mesh] = sh.commit()
	return mesh


static func _wheel(st: SurfaceTool, at: Vector3, r: float, w: float) -> void:
	# Along x (the axle), a 10-sided tyre with a pale hub face.
	# Basis(FORWARD, PI/2) takes the cylinder's +y to +x, -PI/2 to -x.
	cyl(st, Transform3D(Basis(Vector3.FORWARD, PI * 0.5), at - Vector3(w * 0.5, 0.0, 0.0)), r, w, K_RUBBER, Color(0.07, 0.07, 0.07), 10, false)
	cyl(st, Transform3D(Basis(Vector3.FORWARD, PI * 0.5), at + Vector3(w * 0.5, 0.0, 0.0)), r * 0.62, 0.006, K_STEEL, Color(0.55, 0.56, 0.57), 10, true)
	cyl(st, Transform3D(Basis(Vector3.FORWARD, -PI * 0.5), at - Vector3(w * 0.5, 0.0, 0.0)), r * 0.62, 0.006, K_STEEL, Color(0.55, 0.56, 0.57), 10, true)


# --- Props (local frame: +z forward, the foot at y 0, the middle at x 0) ---------------------

## A 53-foot dry van (16.15 m, 2.6 m wide, 4.1 m tall, floor at 1.22 m): the box with its posts and
## rear doors drawn by the shader (K_TRAILER), the nose at +z, tandem axles at the rear, landing
## gear, side skirts on some, the rear frame and bumper. `kind` 0 a plain van, 1 skirted, 2 a 40 ft
## reefer (a refrigeration unit on the nose).
static func trailer(kind: int = 0) -> Mesh:
	var key := "trailer_%d" % kind
	if _into == null and _cache.has(key):
		return _cache[key]
	var st := _begin()
	var length := 16.15 if kind != 2 else 12.2
	var w := 2.59
	var floor_y := 1.22
	var top := 4.1
	var hl := length * 0.5
	var white := Color(1.0, 1.0, 1.0)
	var dark := Color(0.09, 0.09, 0.1)
	var steel := Color(0.32, 0.33, 0.34)
	# The box (paint multiplied by the instance colour; the rear face is the doors).
	box(st, Transform3D(Basis(), Vector3(0.0, (floor_y + top) * 0.5, 0.0)), Vector3(w, top - floor_y, length), K_TRAILER, white, length, 32)
	# The underside rails and cross members (one dark slab), the rear frame and bumper.
	box(st, Transform3D(Basis(), Vector3(0.0, floor_y - 0.12, 0.0)), Vector3(w - 0.1, 0.24, length - 0.1), K_STEEL, dark)
	box(st, Transform3D(Basis(), Vector3(0.0, 0.62, -hl + 0.12)), Vector3(w - 0.3, 0.12, 0.12), K_STEEL, Color(0.6, 0.12, 0.08))
	for sx: float in [-1.0, 1.0]:
		box(st, Transform3D(Basis(), Vector3(sx * (w * 0.5 - 0.3), 0.92, -hl + 0.12)), Vector3(0.1, 0.6, 0.1), K_STEEL, dark)
	# Tandem axles at the rear (sliding, 1.8 m from the doors), duals each side.
	for az: float in [-hl + 1.9, -hl + 3.15]:
		for sx: float in [-1.0, 1.0]:
			_wheel(st, Vector3(sx * (w * 0.5 - 0.62), 0.51, az), 0.51, 0.55)
		box(st, Transform3D(Basis(), Vector3(0.0, 0.51, az)), Vector3(w - 0.4, 0.14, 0.14), K_STEEL, dark)
	# Suspension hangers to the floor.
	box(st, Transform3D(Basis(), Vector3(0.0, 0.85, -hl + 2.5)), Vector3(w - 0.6, 0.5, 2.6), K_STEEL, dark, 0.0, 32 | 16)
	# Mud flaps behind the rear wheels.
	for sx: float in [-1.0, 1.0]:
		box(st, Transform3D(Basis(), Vector3(sx * (w * 0.5 - 0.6), 0.55, -hl + 1.2)), Vector3(0.6, 0.6, 0.02), K_RUBBER, dark)
	# Landing gear, two legs and a crank, 3 m behind the nose.
	for sx: float in [-1.0, 1.0]:
		box(st, Transform3D(Basis(), Vector3(sx * 0.72, 0.55, hl - 3.2)), Vector3(0.12, 1.1, 0.12), K_STEEL, steel)
		box(st, Transform3D(Basis(), Vector3(sx * 0.72, 0.03, hl - 3.2)), Vector3(0.3, 0.06, 0.3), K_STEEL, steel)
	box(st, Transform3D(Basis(), Vector3(0.0, 0.9, hl - 3.2)), Vector3(1.44, 0.08, 0.08), K_STEEL, steel)
	# The kingpin plate up front.
	box(st, Transform3D(Basis(), Vector3(0.0, floor_y - 0.2, hl - 1.2)), Vector3(w - 0.3, 0.08, 2.0), K_STEEL, dark)
	if kind == 1:
		# Aerodynamic side skirts between the landing gear and the axles.
		for sx: float in [-1.0, 1.0]:
			box(st, Transform3D(Basis(), Vector3(sx * (w * 0.5 - 0.02), 0.78, 0.6)), Vector3(0.03, 0.8, 8.2), K_STEEL, Color(0.82, 0.82, 0.8))
	if kind == 2:
		# The refrigeration unit on the nose, louvred grey.
		box(st, Transform3D(Basis(), Vector3(0.0, top - 1.05, hl + 0.3)), Vector3(2.1, 1.7, 0.6), K_CORRUGATED, Color(0.72, 0.73, 0.72))
	var mesh := _commit(key, st, [[Vector3(w, top - floor_y + 0.1, length), Vector3(0.0, (floor_y + top) * 0.5 - 0.05, 0.0)],
		[Vector3(w - 0.2, 0.9, 2.8), Vector3(0.0, 0.5, -hl + 2.5)]])
	return mesh


## A conventional tractor (sleeper cab, long hood, nose at +z), 7.4 m, its fifth wheel at the
## rear. `with_sleeper` false is a day cab (6.2 m). Paint is the instance colour.
static func tractor(with_sleeper: bool = true) -> Mesh:
	var key := "tractor_%s" % with_sleeper
	if _into == null and _cache.has(key):
		return _cache[key]
	var st := _begin()
	var white := Color(1.0, 1.0, 1.0)
	var dark := Color(0.08, 0.08, 0.09)
	var chrome := Color(0.75, 0.76, 0.78)
	var glass := Color(0.06, 0.07, 0.08)
	var length := 7.4 if with_sleeper else 6.2
	var hl := length * 0.5
	var w := 2.5
	# Frame rails.
	box(st, Transform3D(Basis(), Vector3(0.0, 0.85, 0.0)), Vector3(0.9, 0.3, length - 0.3), K_STEEL, dark)
	# Hood: a long box tapering to the grille (two boxes), the grille and bumper.
	var hood0 := hl - 2.6
	box(st, Transform3D(Basis(), Vector3(0.0, 1.55, hood0 + 1.25)), Vector3(w - 0.35, 1.1, 2.5), K_STEEL, white)
	box(st, Transform3D(Basis(Vector3.RIGHT, -0.18), Vector3(0.0, 2.08, hood0 + 1.2)), Vector3(w - 0.55, 0.12, 2.5), K_STEEL, white)
	box(st, Transform3D(Basis(), Vector3(0.0, 1.5, hl - 0.03)), Vector3(1.2, 1.0, 0.06), K_STEEL, chrome)
	box(st, Transform3D(Basis(), Vector3(0.0, 0.72, hl - 0.05)), Vector3(w, 0.32, 0.25), K_STEEL, chrome)
	# Front wheels under the hood, fenders.
	for sx: float in [-1.0, 1.0]:
		_wheel(st, Vector3(sx * (w * 0.5 - 0.3), 0.52, hood0 + 1.3), 0.52, 0.3)
		box(st, Transform3D(Basis(), Vector3(sx * (w * 0.5 - 0.15), 1.1, hood0 + 1.3)), Vector3(0.32, 0.12, 1.3), K_STEEL, white)
	# Cab: windscreen sloped, side glass, the cab box, the sleeper behind it.
	var cab0 := hood0 - 1.9
	box(st, Transform3D(Basis(), Vector3(0.0, 2.05, cab0 + 0.95)), Vector3(w, 2.1, 1.9), K_STEEL, white)
	box(st, Transform3D(Basis(Vector3.RIGHT, -0.28), Vector3(0.0, 2.55, hood0 - 0.05)), Vector3(w - 0.2, 0.9, 0.05), K_GLASS, glass)
	for sx: float in [-1.0, 1.0]:
		box(st, Transform3D(Basis(), Vector3(sx * (w * 0.5 + 0.005), 2.55, cab0 + 1.1)), Vector3(0.01, 0.75, 1.2), K_GLASS, glass)
		# Mirrors on arms.
		box(st, Transform3D(Basis(), Vector3(sx * (w * 0.5 + 0.3), 2.5, hood0 - 0.1)), Vector3(0.05, 0.45, 0.2), K_STEEL, chrome)
		# Steps and fuel tanks under the cab.
		cyl_z(st, Transform3D(Basis(), Vector3(sx * 0.95, 0.85, cab0 + 0.6)), 0.33, 1.3, K_STEEL, chrome, 10)
	if with_sleeper:
		box(st, Transform3D(Basis(), Vector3(0.0, 2.25, cab0 - 0.65)), Vector3(w, 2.5, 1.3), K_STEEL, white)
		# Roof fairing.
		box(st, Transform3D(Basis(Vector3.RIGHT, 0.3), Vector3(0.0, 3.55, cab0 + 0.3)), Vector3(w - 0.1, 0.25, 1.6), K_STEEL, white)
	# Exhaust stacks behind the cab.
	var back := cab0 - (1.3 if with_sleeper else 0.0)
	for sx: float in [-1.0, 1.0]:
		cyl(st, Transform3D(Basis(), Vector3(sx * 1.1, 1.0, back - 0.1)), 0.08, 3.3, K_GALV, chrome, 8, true)
	# Drive tandem and fifth wheel.
	for az: float in [-hl + 0.75, -hl + 2.0]:
		for sx: float in [-1.0, 1.0]:
			_wheel(st, Vector3(sx * (w * 0.5 - 0.6), 0.52, az), 0.52, 0.55)
	box(st, Transform3D(Basis(), Vector3(0.0, 1.12, -hl + 1.35)), Vector3(1.2, 0.12, 1.2), K_STEEL, dark)
	for sx: float in [-1.0, 1.0]:
		box(st, Transform3D(Basis(), Vector3(sx * (w * 0.5 - 0.3), 1.0, -hl + 1.35)), Vector3(0.6, 0.06, 2.4), K_STEEL, dark)
	return _commit(key, st, [[Vector3(w, 2.6, 2.6 if not with_sleeper else 3.9), Vector3(0.0, 2.0, cab0 + (0.95 if not with_sleeper else 0.3))],
		[Vector3(w - 0.4, 1.2, 2.5), Vector3(0.0, 1.5, hood0 + 1.25)]])


## A 50-foot boxcar (15.9 m over the couplers, 3.2 m wide, 4.7 m over the rail) on two trucks;
## the ribbed sides, the sliding door and the reporting marks are the shader's (K_BOXCAR, UV2.y =
## the body length). Paint is the instance colour. Rail top at y 0.
static func boxcar() -> Mesh:
	if _into == null and _cache.has("boxcar"):
		return _cache["boxcar"]
	var st := _begin()
	var length := 15.2
	var hl := length * 0.5
	var w := 3.2
	var dark := Color(0.1, 0.09, 0.09)
	box(st, Transform3D(Basis(), Vector3(0.0, 2.95, 0.0)), Vector3(w, 3.5, length), K_BOXCAR, Color(1.0, 1.0, 1.0), length, 32)
	# Underframe, the end platforms and couplers.
	box(st, Transform3D(Basis(), Vector3(0.0, 1.05, 0.0)), Vector3(w - 0.4, 0.3, length + 0.4), K_STEEL, dark)
	for e: float in [-1.0, 1.0]:
		box(st, Transform3D(Basis(), Vector3(0.0, 0.95, e * (hl + 0.55))), Vector3(0.3, 0.25, 0.7), K_STEEL, dark)
		# Ladders up the corners.
		for sx: float in [-1.0, 1.0]:
			box(st, Transform3D(Basis(), Vector3(sx * (w * 0.5 - 0.15), 2.6, e * (hl + 0.04))), Vector3(0.3, 2.8, 0.04), K_STEEL, Color(0.75, 0.62, 0.15))
		_truck(st, e * (hl - 2.4))
	# The roof walk.
	box(st, Transform3D(Basis(), Vector3(0.0, 4.75, 0.0)), Vector3(0.5, 0.06, length - 0.4), K_STEEL, dark)
	return _commit("boxcar", st, [[Vector3(w, 3.6, length), Vector3(0.0, 2.95, 0.0)]])


## A tank car (17.4 m, a 3 m barrel), black with a walkway and a dome.
static func tank_car() -> Mesh:
	if _into == null and _cache.has("tank_car"):
		return _cache["tank_car"]
	var st := _begin()
	var length := 16.2
	var hl := length * 0.5
	var r := 1.5
	var dark := Color(0.1, 0.09, 0.09)
	cyl_z(st, Transform3D(Basis(), Vector3(0.0, 2.75, 0.0)), r, length, K_TANK, Color(1.0, 1.0, 1.0), 16)
	# Rounded heads: a short cone each end.
	for e: float in [-1.0, 1.0]:
		cone(st, Transform3D(Basis(Vector3.RIGHT, e * PI * 0.5), Vector3(0.0, 2.75, e * hl)), r, 0.6, K_TANK, Color(1.0, 1.0, 1.0), 16)
		box(st, Transform3D(Basis(), Vector3(0.0, 1.05, e * (hl + 0.4))), Vector3(1.2, 0.3, 1.2), K_STEEL, dark)
		box(st, Transform3D(Basis(), Vector3(0.0, 0.95, e * (hl + 1.1))), Vector3(0.3, 0.25, 0.5), K_STEEL, dark)
		_truck(st, e * (hl - 1.8))
	# Dome and its platform.
	cyl(st, Transform3D(Basis(), Vector3(0.0, 4.15, 0.0)), 0.45, 0.35, K_STEEL, dark, 10, true)
	box(st, Transform3D(Basis(), Vector3(0.0, 4.15, 0.0)), Vector3(2.0, 0.05, 1.8), K_STEEL, dark)
	box(st, Transform3D(Basis(), Vector3(0.0, 1.15, 0.0)), Vector3(0.6, 0.3, length - 1.5), K_STEEL, dark)
	return _commit("tank_car", st, [[Vector3(3.0, 3.0, length + 0.6), Vector3(0.0, 2.75, 0.0)]])


## A three-piece freight truck (bogie) at z: side frames, a bolster, four wheels on 1.75 m.
static func _truck(st: SurfaceTool, z: float) -> void:
	var dark := Color(0.12, 0.1, 0.09)
	for sx: float in [-1.0, 1.0]:
		box(st, Transform3D(Basis(), Vector3(sx * 0.82, 0.55, z)), Vector3(0.18, 0.45, 2.6), K_STEEL, dark)
		for dz: float in [-0.87, 0.87]:
			cyl(st, Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(sx * 0.72 - 0.07, 0.46, z + dz)), 0.46, 0.14, K_STEEL, Color(0.2, 0.17, 0.15), 10, true)
	box(st, Transform3D(Basis(), Vector3(0.0, 0.75, z)), Vector3(1.6, 0.3, 0.4), K_STEEL, dark)


## Pallet loads, `kind` 0 a stack of empty pallets, 1 a stretch-wrapped load, 2 a two-high double
## of wrapped loads, 3 cardboard cartons on a pallet. 1.2 x 1.0 m.
static func pallets(kind: int) -> Mesh:
	var key := "pallets_%d" % kind
	if _into == null and _cache.has(key):
		return _cache[key]
	var st := _begin()
	var wood := Color(0.62, 0.5, 0.36)
	match kind:
		0:
			box(st, Transform3D(Basis(), Vector3(0.0, 0.72, 0.0)), Vector3(1.2, 1.44, 1.0), K_WOOD, wood, 0.144)
		1:
			box(st, Transform3D(Basis(), Vector3(0.0, 0.07, 0.0)), Vector3(1.2, 0.144, 1.0), K_WOOD, wood, 0.144)
			box(st, Transform3D(Basis(), Vector3(0.0, 0.144 + 0.6, 0.0)), Vector3(1.18, 1.2, 0.98), K_WRAP, Color(0.86, 0.87, 0.88))
		2:
			for lvl in 2:
				var y := float(lvl) * 1.3
				box(st, Transform3D(Basis(), Vector3(0.0, y + 0.07, 0.0)), Vector3(1.2, 0.144, 1.0), K_WOOD, wood, 0.144)
				box(st, Transform3D(Basis(), Vector3(0.0, y + 0.144 + 0.55, 0.0)), Vector3(1.18, 1.1, 0.98), K_WRAP, Color(0.8, 0.82, 0.84))
		_:
			box(st, Transform3D(Basis(), Vector3(0.0, 0.07, 0.0)), Vector3(1.2, 0.144, 1.0), K_WOOD, wood, 0.144)
			box(st, Transform3D(Basis(), Vector3(0.0, 0.144 + 0.5, 0.0)), Vector3(1.16, 1.0, 0.96), K_WOOD, Color(0.66, 0.52, 0.36), 0.0)
	return _commit(key, st)


## A cluster of four 55-gallon drums on a pallet (paint the instance colour: blue, black, grey).
static func drums() -> Mesh:
	if _into == null and _cache.has("drums"):
		return _cache["drums"]
	var st := _begin()
	box(st, Transform3D(Basis(), Vector3(0.0, 0.07, 0.0)), Vector3(1.2, 0.144, 1.2), K_WOOD, Color(0.55, 0.45, 0.33), 0.144)
	for dx: float in [-0.3, 0.3]:
		for dz: float in [-0.3, 0.3]:
			cyl(st, Transform3D(Basis(), Vector3(dx, 0.144, dz)), 0.29, 0.88, K_PLASTIC, Color(1.0, 1.0, 1.0), 10, true)
	return _commit("drums", st)


## A front-load dumpster (3 yd, 1.8 x 1.2 m) or, `big`, a 30-yard roll-off (6.7 x 2.4 x 1.8 m).
static func bin(big: bool) -> Mesh:
	var key := "bin_%s" % big
	if _into == null and _cache.has(key):
		return _cache[key]
	var st := _begin()
	if big:
		box(st, Transform3D(Basis(), Vector3(0.0, 1.05, 0.0)), Vector3(2.4, 1.8, 6.7), K_STEEL, Color(1.0, 1.0, 1.0), 0.0, 32 | 16)
		box(st, Transform3D(Basis(), Vector3(0.0, 1.75, 0.0)), Vector3(2.2, 0.06, 6.5), K_CONCRETE, Color(0.45, 0.42, 0.38))
		for sx: float in [-1.0, 1.0]:
			box(st, Transform3D(Basis(), Vector3(sx * 1.0, 0.08, 0.0)), Vector3(0.18, 0.16, 6.9), K_STEEL, Color(0.15, 0.15, 0.15))
	else:
		box(st, Transform3D(Basis(), Vector3(0.0, 0.62, 0.0)), Vector3(1.8, 1.1, 1.2), K_STEEL, Color(1.0, 1.0, 1.0))
		box(st, Transform3D(Basis(Vector3.RIGHT, -0.1), Vector3(0.0, 1.22, 0.0)), Vector3(1.84, 0.05, 1.3), K_PLASTIC, Color(0.1, 0.1, 0.1))
	return _commit(key, st)


## A vertical storage tank (a fuel or water tank on a ring wall): `r` m radius, `h` tall, a cone
## roof, a caged ladder.
static func storage_tank(r: float, h: float) -> Mesh:
	var key := "tank_%.1f_%.1f" % [r, h]
	if _into == null and _cache.has(key):
		return _cache[key]
	var st := _begin()
	cyl(st, Transform3D(Basis(), Vector3(0.0, 0.0, 0.0)), r + 0.15, 0.3, K_CONCRETE, Color(0.7, 0.69, 0.66), 18, true)
	cyl(st, Transform3D(Basis(), Vector3(0.0, 0.3, 0.0)), r, h, K_TANK, Color(1.0, 1.0, 1.0), 18, false)
	cone(st, Transform3D(Basis(), Vector3(0.0, h + 0.3, 0.0)), r + 0.05, r * 0.2, K_TANK, Color(1.0, 1.0, 1.0), 18)
	# The ladder up the side with its cage, and the handrail at the top.
	box(st, Transform3D(Basis(), Vector3(r + 0.25, (h + 0.3) * 0.5 + 0.3, 0.0)), Vector3(0.06, h, 0.5), K_GALV, Color(0.7, 0.71, 0.72))
	box(st, Transform3D(Basis(), Vector3(r + 0.6, h * 0.6 + 0.5, 0.0)), Vector3(0.6, h * 0.75, 0.7), K_CHAIN, Color(0.72, 0.73, 0.74), 0.0, 32 | 16 | 2)
	return _commit(key, st, [[Vector3(r * 1.9, h + 0.3, r * 1.9), Vector3(0.0, (h + 0.3) * 0.5, 0.0)]])


## An elevated steel water tower: four raked legs with cross bracing, a cylindrical tank with a
## cone roof and a catwalk round its waist. ~28 m to the top.
static func water_tower() -> Mesh:
	if _into == null and _cache.has("water_tower"):
		return _cache["water_tower"]
	var st := _begin()
	var paint := Color(0.86, 0.86, 0.84)
	var leg_h := 20.0
	var r := 4.2
	var spread_foot := 4.5
	var spread_top := 3.0
	for k in 4:
		var a := TAU * (float(k) + 0.5) / 4.0
		var foot := Vector3(cos(a), 0.0, sin(a)) * spread_foot
		var head := Vector3(cos(a), 0.0, sin(a)) * spread_top + Vector3(0.0, leg_h, 0.0)
		var axis := (head - foot).normalized()
		var b := Basis(Vector3.UP.cross(axis).normalized(), Vector3.UP.angle_to(axis)) if absf(axis.y) < 0.9999 else Basis()
		cyl(st, Transform3D(b, foot), 0.22, (head - foot).length(), K_STEEL, paint, 8, false)
		cyl(st, Transform3D(Basis(), foot), 0.5, 0.4, K_CONCRETE, Color(0.7, 0.7, 0.68), 8, true)
	# Struts between the legs at three levels, crossed rods in each bay.
	for lvl in 3:
		var y := leg_h * (0.25 + 0.25 * lvl)
		var sp := lerpf(spread_foot, spread_top, y / leg_h)
		for k in 4:
			var a0 := TAU * (float(k) + 0.5) / 4.0
			var a1 := TAU * (float(k) + 1.5) / 4.0
			var p0 := Vector3(cos(a0), 0.0, sin(a0)) * sp
			var p1 := Vector3(cos(a1), 0.0, sin(a1)) * sp
			var mid := (p0 + p1) * 0.5 + Vector3(0.0, y, 0.0)
			var d := p1 - p0
			box(st, Transform3D(Basis(Vector3.UP, atan2(-d.x, -d.z)), mid), Vector3(0.12, 0.12, d.length()), K_STEEL, paint)
	# Riser pipe down the middle.
	cyl(st, Transform3D(Basis(), Vector3(0.0, 0.0, 0.0)), 0.45, leg_h, K_STEEL, paint, 10, false)
	# The tank: a cone bottom, the barrel, the cone roof with a finial.
	cone(st, Transform3D(Basis(Vector3.RIGHT, PI), Vector3(0.0, leg_h + 1.8, 0.0)), r, 1.8, K_TANK, paint, 20)
	cyl(st, Transform3D(Basis(), Vector3(0.0, leg_h + 1.8, 0.0)), r, 5.5, K_TANK, paint, 20, false)
	cone(st, Transform3D(Basis(), Vector3(0.0, leg_h + 7.3, 0.0)), r + 0.15, 1.9, K_TANK, paint, 20)
	cyl(st, Transform3D(Basis(), Vector3(0.0, leg_h + 9.1, 0.0)), 0.15, 0.9, K_STEEL, paint, 8, true)
	# The catwalk and its rail.
	cyl(st, Transform3D(Basis(), Vector3(0.0, leg_h + 1.75, 0.0)), r + 0.8, 0.08, K_STEEL, Color(0.25, 0.25, 0.26), 20, true)
	cyl(st, Transform3D(Basis(), Vector3(0.0, leg_h + 1.85, 0.0)), r + 0.78, 1.05, K_CHAIN, Color(0.6, 0.6, 0.6), 20, false)
	return _commit("water_tower", st, [[Vector3(r * 1.8, 9.0, r * 1.8), Vector3(0.0, leg_h + 4.5, 0.0)], [Vector3(6.0, leg_h, 0.6), Vector3(0.0, leg_h * 0.5, 0.0)]])
