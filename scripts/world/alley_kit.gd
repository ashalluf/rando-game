class_name AlleyKit
extends RefCounted
## The furniture of the city's service alleys (Alleys plans them): what stands along the backs of
## the buildings, built in code at real size and written into the chunk's ONE upright alley mesh
## through IndustrialKit's writers and material (K_* kinds: painted steel, galvanised, plastic,
## timber, concrete, rubber, chain-link, the lit lamp, the trailer skin, glass) - dumpsters with
## lids, fork pockets, casters and an invented hauler's stencil, grease bins, wheeled carts, steel
## back doors under caged bulkhead lamps, loading docks with steel stairs and a roll-up door, fire
## escapes with their drop ladders, condensers on wall brackets, gas meter manifolds, electrical
## panels and conduit, pallets, milk crates, an old mattress, chain-link gates at the mouths, a box
## van backed in - and the wooden power poles down the alley on StreetDetail's own batches.
##
## Every geometry function draws in its local frame: x along the wall (to the right seen from the
## alley), y up from the ground, z out of the wall toward the alley; dress() places it with
## IndustrialKit.place(). Every roll is a hash of the plan seed, the block, the run, the side and
## the face (Alleys._rng), never a chunk or block rng.

## Door, lamp and stencil colours (sRGB).
const DOOR_PAINT := [Color(0.42, 0.43, 0.43), Color(0.30, 0.22, 0.16), Color(0.46, 0.14, 0.11), Color(0.16, 0.30, 0.30), Color(0.17, 0.22, 0.38), Color(0.62, 0.60, 0.55)]
const CART_PAINT := [Color(0.10, 0.26, 0.55), Color(0.07, 0.07, 0.08), Color(0.13, 0.33, 0.15)]
const CRATE_PAINT := [Color(0.62, 0.10, 0.08), Color(0.10, 0.25, 0.55), Color(0.12, 0.40, 0.18), Color(0.85, 0.66, 0.10), Color(0.08, 0.08, 0.09)]
const LAMP_WARM := Color(1.0, 0.78, 0.48)
const LAMP_COOL := Color(0.86, 0.9, 1.0)
const WHITE_PAINT := Color(0.88, 0.88, 0.85)
const ESCAPE_PAINT := Color(0.09, 0.09, 0.09)
## Names on the delivery vans (invented).
const FLEETS := ["BASIN PRODUCE", "LOS FELIZ LINEN", "VALLEY BAKERY SUPPLY", "HARBOR SEAFOOD CO", "SUNSET RESTAURANT SUPPLY"]
const FLEET_PAINT := [Color(0.13, 0.36, 0.18), Color(0.12, 0.22, 0.45), Color(0.55, 0.30, 0.10), Color(0.08, 0.30, 0.38), Color(0.50, 0.11, 0.10)]
## Keep a lane this wide clear down the alley (metres): nothing on the ground intrudes past it.
const LANE := 3.0


# --- Writers ---------------------------------------------------------------------------------

static func _box(st: SurfaceTool, at: Vector3, size: Vector3, kind: int, paint: Color, param: float = 0.0, skip: int = 32) -> void:
	IndustrialKit.box(st, Transform3D(Basis(), at), size, kind, paint, param, skip)


static func _boxr(st: SurfaceTool, basis: Basis, at: Vector3, size: Vector3, kind: int, paint: Color, param: float = 0.0, skip: int = 32) -> void:
	IndustrialKit.box(st, Transform3D(basis, at), size, kind, paint, param, skip)


## A bar from a to b (a thin box `t` square).
static func _bar(st: SurfaceTool, a: Vector3, b: Vector3, t: float, kind: int, paint: Color) -> void:
	var d := b - a
	var l := d.length()
	if l < 0.001:
		return
	var y := d / l
	var x := Vector3.UP.cross(y)
	if x.length_squared() < 0.01:
		x = Vector3.RIGHT
	x = x.normalized()
	var z := x.cross(y).normalized()
	_boxr(st, Basis(x, y, z), (a + b) * 0.5, Vector3(t, l, t), kind, paint, 0.0, 0)


## Text drawn flat on the local plane z = `z`, facing +z, centred on (x, y), `cap` high: into the
## upright mesh as kind `kind` in `paint` (a stencil).
static func _text(st: SurfaceTool, text: String, at: Vector3, cap: float, kind: int, paint: Color, fit_w: float = 0.0, basis: Basis = Basis()) -> void:
	var geo := Alleys.text_geo(text, cap)
	if geo.is_empty():
		return
	var verts: PackedVector3Array = geo[0]
	if verts.is_empty():
		return
	var scale := 1.0
	if fit_w > 0.0:
		var wide := 0.0
		for v in verts:
			wide = maxf(wide, absf(v.x))
		scale = minf(1.0, fit_w * 0.5 / maxf(wide, 0.01))
	var xf := IndustrialKit._xf * Transform3D(basis, at)
	var n := (xf.basis * Vector3(0.0, 0.0, 1.0)).normalized()
	var col := IndustrialKit.kind_color(kind, paint)
	var idx = geo[1]
	var ids: PackedInt32Array = idx if idx != null else PackedInt32Array()
	if ids.is_empty():
		for k in verts.size():
			ids.append(k)
	var pts: Array[Vector3] = []
	for v in verts:
		pts.append(xf * Vector3(v.x * scale, v.y * scale, 0.0))
	for k in range(0, ids.size() - 2, 3):
		var a := pts[ids[k]]
		var b := pts[ids[k + 1]]
		var c := pts[ids[k + 2]]
		if (b - a).cross(c - a).dot(n) > 0.0:
			var t := b
			b = c
			c = t
		for p: Vector3 in [a, b, c]:
			st.set_normal(n)
			st.set_color(col)
			st.set_uv(Vector2(p.x + p.z, p.y))
			st.set_uv2(Vector2(cap, 0.0))
			st.add_vertex(p)
		IndustrialKit.tris += 1


# --- Props (local frame: x along the wall, y up, z out of the wall) ---------------------------

## A 3-yard front-load dumpster (1.83 x 1.12 x 1.22 m) standing against the wall: the body, its
## sloped front, the rim, two lids (one thrown open against the wall), the fork pockets, casters,
## and the hauler's name and number stencilled on the front.
static func dumpster(st: SurfaceTool, paint: Color, lid: Color, hauler: String, open: bool) -> void:
	var w := 1.83
	_box(st, Vector3(0.0, 0.66, 0.53), Vector3(w, 1.04, 0.92), IndustrialKit.K_STEEL, paint)
	_boxr(st, Basis(Vector3.RIGHT, -0.32), Vector3(0.0, 0.7, 1.06), Vector3(w, 1.08, 0.06), IndustrialKit.K_STEEL, paint)
	_box(st, Vector3(0.0, 1.19, 0.6), Vector3(w + 0.06, 0.06, 1.16), IndustrialKit.K_STEEL, paint * 0.85)
	for sx: float in [-1.0, 1.0]:
		_box(st, Vector3(sx * (w * 0.5 + 0.06), 0.88, 0.58), Vector3(0.12, 0.17, 0.92), IndustrialKit.K_STEEL, paint * 0.8)
		for z: float in [0.18, 0.92]:
			_box(st, Vector3(sx * 0.78, 0.115, z), Vector3(0.12, 0.03, 0.12), IndustrialKit.K_STEEL, Color(0.2, 0.2, 0.2))
			IndustrialKit.cyl(st, Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(sx * 0.78 - 0.03, 0.06, z)), 0.055, 0.06, IndustrialKit.K_RUBBER, Color(0.08, 0.08, 0.08), 8, true)
	# Lids: hinged at the back edge (z 0.05).
	for sx: float in [-0.46, 0.46]:
		var opened := open and sx > 0.0
		var b := Basis(Vector3.RIGHT, -1.75) if opened else Basis(Vector3.RIGHT, 0.02)
		var hinge := Vector3(sx, 1.24, 0.04)
		_boxr(st, b, hinge + b * Vector3(0.0, 0.0, 0.58), Vector3(0.88, 0.04, 1.16), IndustrialKit.K_PLASTIC, lid)
	# The stencil on the sloped front.
	var front := Basis(Vector3.RIGHT, -0.32)
	_text(st, hauler, Vector3(0.0, 0.86, 1.1) + front * Vector3(0.0, 0.0, 0.034), 0.11, IndustrialKit.K_PLASTIC, WHITE_PAINT, w - 0.25, front)
	_text(st, "(555) 01%02d" % (absi(hauler.hash()) % 90), Vector3(0.0, 0.66, 1.17) + front * Vector3(0.0, 0.0, 0.034), 0.075, IndustrialKit.K_PLASTIC, WHITE_PAINT, w - 0.4, front)


## A rendering company's grease bin: a squat steel box with a sloped lid, a hasp, a stencil.
static func grease_bin(st: SurfaceTool, paint: Color) -> void:
	_box(st, Vector3(0.0, 0.47, 0.45), Vector3(1.15, 0.86, 0.8), IndustrialKit.K_STEEL, paint)
	_boxr(st, Basis(Vector3.RIGHT, 0.12), Vector3(0.0, 0.93, 0.45), Vector3(1.2, 0.04, 0.88), IndustrialKit.K_STEEL, paint * 0.9)
	_box(st, Vector3(0.0, 0.8, 0.86), Vector3(0.08, 0.12, 0.03), IndustrialKit.K_GALV, Color(0.7, 0.7, 0.68))
	for sx: float in [-0.45, 0.45]:
		IndustrialKit.cyl(st, Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(sx - 0.03, 0.045, 0.45)), 0.045, 0.06, IndustrialKit.K_RUBBER, Color(0.08, 0.08, 0.08), 8, true)
	_text(st, "INEDIBLE KITCHEN GREASE", Vector3(0.0, 0.6, 0.852), 0.06, IndustrialKit.K_PLASTIC, WHITE_PAINT, 1.05)
	_text(st, "NO DUMPING", Vector3(0.0, 0.45, 0.852), 0.06, IndustrialKit.K_PLASTIC, WHITE_PAINT, 1.05)


## A 96-gallon wheeled cart: body, lid, the handle at the back, two wheels.
static func cart(st: SurfaceTool, paint: Color, lid: Color) -> void:
	_box(st, Vector3(0.0, 0.53, 0.0), Vector3(0.6, 0.9, 0.68), IndustrialKit.K_PLASTIC, paint)
	_box(st, Vector3(0.0, 1.0, 0.02), Vector3(0.64, 0.05, 0.76), IndustrialKit.K_PLASTIC, lid)
	_box(st, Vector3(0.0, 0.94, -0.37), Vector3(0.56, 0.04, 0.05), IndustrialKit.K_PLASTIC, paint * 0.8)
	for sx: float in [-1.0, 1.0]:
		IndustrialKit.cyl(st, Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(sx * 0.3 - (0.06 if sx > 0.0 else 0.0), 0.13, -0.3)), 0.13, 0.06, IndustrialKit.K_RUBBER, Color(0.07, 0.07, 0.07), 10, true)


## A steel back door in its frame, a kick plate, a lever; the rear address on some.
static func back_door(st: SurfaceTool, paint: Color, address: String, stoop: bool) -> void:
	var base := 0.17 if stoop else 0.0
	if stoop:
		_box(st, Vector3(0.0, 0.085, 0.42), Vector3(1.5, 0.17, 0.84), IndustrialKit.K_CONCRETE, Color(0.72, 0.71, 0.68))
	_box(st, Vector3(0.0, base + 1.07, 0.02), Vector3(0.96, 2.13, 0.05), IndustrialKit.K_STEEL, paint, 0.0, 32 | 16)
	for sx: float in [-1.0, 1.0]:
		_box(st, Vector3(sx * 0.52, base + 1.1, 0.035), Vector3(0.07, 2.2, 0.07), IndustrialKit.K_STEEL, paint * 0.7)
	_box(st, Vector3(0.0, base + 2.23, 0.035), Vector3(1.11, 0.07, 0.07), IndustrialKit.K_STEEL, paint * 0.7)
	_box(st, Vector3(0.0, base + 0.16, 0.05), Vector3(0.9, 0.28, 0.012), IndustrialKit.K_GALV, Color(0.62, 0.62, 0.6))
	_box(st, Vector3(0.36, base + 1.0, 0.07), Vector3(0.13, 0.025, 0.04), IndustrialKit.K_GALV, Color(0.7, 0.7, 0.68))
	if address != "":
		_text(st, address, Vector3(0.0, base + 1.62, 0.047), 0.12, IndustrialKit.K_PLASTIC, WHITE_PAINT, 0.8)


## A caged bulkhead lamp at y over the ground, its conduit running up the wall.
static func lamp(st: SurfaceTool, y: float, tint: Color) -> void:
	_box(st, Vector3(0.0, y + 0.02, 0.06), Vector3(0.22, 0.2, 0.12), IndustrialKit.K_STEEL, Color(0.14, 0.14, 0.13))
	# The lens tilted out and down: its underside is the bright face (K_LAMP), so it looks into the
	# alley rather than at the ground under it.
	_boxr(st, Basis(Vector3.RIGHT, -PI * 0.25), Vector3(0.0, y - 0.02, 0.15), Vector3(0.17, 0.11, 0.1), IndustrialKit.K_LAMP, tint)
	for i in 3:
		var x := -0.07 + 0.07 * float(i)
		_box(st, Vector3(x, y, 0.2), Vector3(0.012, 0.16, 0.012), IndustrialKit.K_STEEL, Color(0.12, 0.12, 0.11))
	_box(st, Vector3(0.0, y + 0.075, 0.2), Vector3(0.18, 0.012, 0.012), IndustrialKit.K_STEEL, Color(0.12, 0.12, 0.11))
	_box(st, Vector3(0.0, y - 0.075, 0.2), Vector3(0.18, 0.012, 0.012), IndustrialKit.K_STEEL, Color(0.12, 0.12, 0.11))
	_box(st, Vector3(0.0, y + 0.75, 0.025), Vector3(0.025, 1.3, 0.025), IndustrialKit.K_GALV, Color(0.6, 0.6, 0.58))


## A loading dock `w` wide, `h` high, `d` deep, a steel stair down one end (`stair_side` -1 / +1)
## with its handrail, rubber bumpers, the roll-up door in the wall over it and its hood.
static func dock(st: SurfaceTool, w: float, h: float, d: float, stair_side: float, door_paint: Color) -> void:
	_box(st, Vector3(0.0, h * 0.5, d * 0.5), Vector3(w, h, d), IndustrialKit.K_CONCRETE, Color(0.7, 0.69, 0.66))
	_box(st, Vector3(0.0, h - 0.03, d - 0.03), Vector3(w, 0.07, 0.07), IndustrialKit.K_GALV, Color(0.55, 0.55, 0.53))
	for sx: float in [-0.32, 0.32]:
		_box(st, Vector3(sx * w, h - 0.28, d + 0.06), Vector3(0.26, 0.3, 0.12), IndustrialKit.K_RUBBER, Color(0.06, 0.06, 0.06))
	# The stair, along the wall off one end: treads, two stringers, a rail.
	var n := maxi(2, ceili(h / 0.19))
	var rise := h / float(n)
	var run := 0.28
	var x0 := stair_side * w * 0.5
	for k in n - 1:
		var x := x0 + stair_side * run * (float(k) + 0.5)
		var y := h - rise * float(k + 1)
		_box(st, Vector3(x, y - 0.02, d * 0.5), Vector3(run, 0.04, minf(d - 0.2, 1.0)), IndustrialKit.K_STEEL, Color(0.3, 0.3, 0.29))
	var foot := x0 + stair_side * run * float(n - 1)
	for zz: float in [d * 0.5 - 0.5, d * 0.5 + 0.5]:
		_bar(st, Vector3(x0, h, zz), Vector3(foot, 0.0, zz), 0.05, IndustrialKit.K_STEEL, Color(0.25, 0.25, 0.24))
	var rz := d * 0.5 + 0.52
	_bar(st, Vector3(x0, h + 0.95, rz), Vector3(foot, 0.95, rz), 0.035, IndustrialKit.K_STEEL, Color(0.75, 0.6, 0.1))
	_bar(st, Vector3(x0, h, rz), Vector3(x0, h + 0.95, rz), 0.035, IndustrialKit.K_STEEL, Color(0.75, 0.6, 0.1))
	_bar(st, Vector3(foot, 0.0, rz), Vector3(foot, 0.95, rz), 0.035, IndustrialKit.K_STEEL, Color(0.75, 0.6, 0.1))
	# The rail along the dock's open end.
	_bar(st, Vector3(-x0, h, d - 0.05), Vector3(-x0, h + 0.95, d - 0.05), 0.035, IndustrialKit.K_STEEL, Color(0.75, 0.6, 0.1))
	_bar(st, Vector3(-x0, h + 0.95, 0.05), Vector3(-x0, h + 0.95, d - 0.05), 0.035, IndustrialKit.K_STEEL, Color(0.75, 0.6, 0.1))
	# The roll-up door over it and its hood.
	var dw := minf(w - 0.6, 3.0)
	_box(st, Vector3(0.0, h + 1.35, 0.03), Vector3(dw, 2.7, 0.06), IndustrialKit.K_ROLLUP, door_paint, 0.085, 32 | 16)
	_box(st, Vector3(0.0, h + 2.86, 0.18), Vector3(dw + 0.3, 0.36, 0.34), IndustrialKit.K_STEEL, door_paint * 0.8)
	_text(st, "DO NOT BLOCK", Vector3(0.0, h + 0.8, 0.065), 0.16, IndustrialKit.K_PLASTIC, Color(0.75, 0.12, 0.08), dw - 0.4)


## A fire escape `w` wide: a landing at each height in `levels` (local y), stairs between them, a
## railing, brackets back to the wall, and the counterweighted drop ladder under the lowest
## landing, hanging to `ladder_foot` over the ground.
static func fire_escape(st: SurfaceTool, w: float, levels: Array, ladder_foot: float) -> void:
	var d := 0.95
	var p := ESCAPE_PAINT
	for i in levels.size():
		var y: float = levels[i]
		_box(st, Vector3(0.0, y - 0.03, d * 0.5 + 0.05), Vector3(w, 0.05, d), IndustrialKit.K_STEEL, p * 1.4)
		_box(st, Vector3(0.0, y + 0.08, d + 0.04), Vector3(w, 0.16, 0.012), IndustrialKit.K_STEEL, p)
		_bar(st, Vector3(-w * 0.5, y + 1.0, d + 0.04), Vector3(w * 0.5, y + 1.0, d + 0.04), 0.035, IndustrialKit.K_STEEL, p)
		_bar(st, Vector3(-w * 0.5, y + 0.5, d + 0.04), Vector3(w * 0.5, y + 0.5, d + 0.04), 0.02, IndustrialKit.K_STEEL, p)
		for x: float in [-w * 0.5, 0.0, w * 0.5]:
			_bar(st, Vector3(x, y, d + 0.04), Vector3(x, y + 1.0, d + 0.04), 0.03, IndustrialKit.K_STEEL, p)
		for x: float in [-w * 0.5, w * 0.5]:
			_bar(st, Vector3(x, y + 1.0, 0.05), Vector3(x, y + 1.0, d + 0.04), 0.03, IndustrialKit.K_STEEL, p)
			_bar(st, Vector3(x * 0.92, y - 0.05, d), Vector3(x * 0.92, y - 0.75, 0.05), 0.04, IndustrialKit.K_STEEL, p)
		# The stair up to the next landing, rising along the wall.
		if i + 1 < levels.size():
			var y2: float = levels[i + 1]
			var xa := -w * 0.5 + 0.3
			var xb := w * 0.5 - 0.35
			var n := maxi(4, int((y2 - y) / 0.22))
			for zz: float in [0.42, 0.98]:
				_bar(st, Vector3(xa, y, zz), Vector3(xb, y2, zz), 0.05, IndustrialKit.K_STEEL, p)
			for k in n:
				var t := (float(k) + 0.5) / float(n)
				_box(st, Vector3(lerpf(xa, xb, t), lerpf(y, y2, t), 0.7), Vector3(0.2, 0.025, 0.54), IndustrialKit.K_STEEL, p * 1.3)
			_bar(st, Vector3(xa, y + 0.9, 1.0), Vector3(xb, y2 + 0.9, 1.0), 0.03, IndustrialKit.K_STEEL, p)
	if levels.is_empty():
		return
	# The drop ladder: two rails and rungs under the lowest landing, by its outer edge.
	var y0: float = levels[0]
	var lx := w * 0.5 - 0.45
	for sx: float in [-0.22, 0.22]:
		_bar(st, Vector3(lx + sx, ladder_foot, d - 0.08), Vector3(lx + sx, y0 + 0.9, d - 0.08), 0.03, IndustrialKit.K_STEEL, p)
	var r := ladder_foot + 0.15
	while r < y0 - 0.1:
		_bar(st, Vector3(lx - 0.22, r, d - 0.08), Vector3(lx + 0.22, r, d - 0.08), 0.02, IndustrialKit.K_STEEL, p)
		r += 0.3
	# Its counterweight arm.
	_bar(st, Vector3(lx, y0 + 0.9, d - 0.08), Vector3(lx - 0.6, y0 + 1.2, d - 0.08), 0.04, IndustrialKit.K_STEEL, p)


## A split-system condenser on two wall brackets at y, its line set running down the wall.
static func condenser(st: SurfaceTool, y: float, drop: float) -> void:
	_box(st, Vector3(0.0, y + 0.3, 0.24), Vector3(0.84, 0.6, 0.32), IndustrialKit.K_GALV, Color(0.78, 0.78, 0.75))
	IndustrialKit.cyl(st, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(-0.1, y + 0.3, 0.4)), 0.22, 0.012, IndustrialKit.K_STEEL, Color(0.12, 0.12, 0.12), 14, true)
	_box(st, Vector3(0.28, y + 0.3, 0.405), Vector3(0.16, 0.5, 0.01), IndustrialKit.K_STEEL, Color(0.4, 0.4, 0.38))
	for sx: float in [-0.3, 0.3]:
		_box(st, Vector3(sx, y - 0.02, 0.22), Vector3(0.04, 0.04, 0.44), IndustrialKit.K_STEEL, Color(0.2, 0.2, 0.2))
		_bar(st, Vector3(sx, y - 0.02, 0.4), Vector3(sx, y - 0.4, 0.02), 0.035, IndustrialKit.K_STEEL, Color(0.2, 0.2, 0.2))
	_box(st, Vector3(0.36, y + 0.3 - drop * 0.5, 0.03), Vector3(0.05, drop + 0.6, 0.05), IndustrialKit.K_STEEL, Color(0.08, 0.08, 0.08))


## A ground-mounted condenser on its pad.
static func condenser_ground(st: SurfaceTool) -> void:
	_box(st, Vector3(0.0, 0.05, 0.5), Vector3(1.0, 0.1, 0.85), IndustrialKit.K_CONCRETE, Color(0.7, 0.69, 0.66))
	_box(st, Vector3(0.0, 0.52, 0.5), Vector3(0.82, 0.84, 0.76), IndustrialKit.K_GALV, Color(0.62, 0.63, 0.6))
	IndustrialKit.cyl(st, Transform3D(Basis(), Vector3(0.0, 0.94, 0.5)), 0.3, 0.02, IndustrialKit.K_STEEL, Color(0.1, 0.1, 0.1), 14, true)


## A bank of `n` gas meters on a yellow manifold.
static func gas_meters(st: SurfaceTool, n: int) -> void:
	var yellow := Color(0.82, 0.65, 0.12)
	var wide := 0.42 * float(n)
	IndustrialKit.cyl(st, Transform3D(Basis(), Vector3(-wide * 0.5 - 0.1, 0.0, 0.1)), 0.035, 0.5, IndustrialKit.K_STEEL, yellow, 8, true)
	_box(st, Vector3(-0.05, 0.47, 0.1), Vector3(wide + 0.15, 0.06, 0.06), IndustrialKit.K_STEEL, yellow)
	for i in n:
		var x := -wide * 0.5 + 0.21 + 0.42 * float(i)
		IndustrialKit.cyl(st, Transform3D(Basis(), Vector3(x, 0.5, 0.1)), 0.025, 0.2, IndustrialKit.K_STEEL, yellow, 6, false)
		_box(st, Vector3(x, 0.86, 0.13), Vector3(0.3, 0.32, 0.2), IndustrialKit.K_GALV, Color(0.6, 0.6, 0.57))
		IndustrialKit.cyl(st, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(x, 0.9, 0.235)), 0.06, 0.01, IndustrialKit.K_STEEL, Color(0.85, 0.85, 0.8), 10, true)
		IndustrialKit.cyl(st, Transform3D(Basis(), Vector3(x, 1.02, 0.1)), 0.025, 0.4, IndustrialKit.K_STEEL, Color(0.5, 0.5, 0.48), 6, false)


## An electrical panel and meter with its conduit up the wall.
static func panel(st: SurfaceTool, tall: float) -> void:
	_box(st, Vector3(0.0, 1.45, 0.13), Vector3(0.7, 1.05, 0.26), IndustrialKit.K_GALV, Color(0.58, 0.59, 0.57))
	_box(st, Vector3(0.0, 1.45, 0.265), Vector3(0.6, 0.9, 0.01), IndustrialKit.K_STEEL, Color(0.5, 0.51, 0.49))
	IndustrialKit.cyl(st, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0.55, 1.5, 0.12)), 0.1, 0.12, IndustrialKit.K_GALV, Color(0.6, 0.6, 0.58), 12, true)
	_box(st, Vector3(-0.2, 1.97 + tall * 0.5, 0.05), Vector3(0.06, tall, 0.06), IndustrialKit.K_GALV, Color(0.62, 0.62, 0.6))
	_box(st, Vector3(0.15, 1.97 + tall * 0.4, 0.05), Vector3(0.04, tall * 0.8, 0.04), IndustrialKit.K_GALV, Color(0.62, 0.62, 0.6))
	_text(st, "DANGER  HIGH VOLTAGE", Vector3(0.0, 1.72, 0.272), 0.04, IndustrialKit.K_PLASTIC, Color(0.85, 0.15, 0.1), 0.55)


## Stacks of milk crates.
static func crates(st: SurfaceTool, rng: RandomNumberGenerator) -> void:
	for k in rng.randi_range(1, 3):
		var x := -0.4 + 0.38 * float(k)
		var paint: Color = CRATE_PAINT[rng.randi() % CRATE_PAINT.size()]
		var n := rng.randi_range(1, 5)
		for i in n:
			var yaw := rng.randf_range(-0.12, 0.12)
			_boxr(st, Basis(Vector3.UP, yaw), Vector3(x, 0.14 + 0.285 * float(i), 0.22), Vector3(0.33, 0.27, 0.33), IndustrialKit.K_PLASTIC, paint)
			_boxr(st, Basis(Vector3.UP, yaw), Vector3(x, 0.24 + 0.285 * float(i), 0.22), Vector3(0.34, 0.04, 0.34), IndustrialKit.K_PLASTIC, paint * 0.75)


## An old mattress leaning on the wall.
static func mattress(st: SurfaceTool, paint: Color) -> void:
	_boxr(st, Basis(Vector3.RIGHT, -0.22), Vector3(0.0, 0.93, 0.33), Vector3(1.4, 1.9, 0.2), IndustrialKit.K_RUBBER, paint)


## A chain-link gate leaf `l` long, swung open along the alley's edge: post, pipe frame, the mesh,
## barbed wire on top when `wire`.
static func gate_leaf(st: SurfaceTool, l: float, wire: bool) -> void:
	var galv := Color(0.62, 0.63, 0.61)
	IndustrialKit.cyl(st, Transform3D(Basis(), Vector3(0.0, 0.0, 0.0)), 0.05, 2.15, IndustrialKit.K_GALV, galv, 8, true)
	_box(st, Vector3(l * 0.5, 1.9, 0.0), Vector3(l, 0.045, 0.045), IndustrialKit.K_GALV, galv)
	_box(st, Vector3(l * 0.5, 0.08, 0.0), Vector3(l, 0.045, 0.045), IndustrialKit.K_GALV, galv)
	_box(st, Vector3(l - 0.03, 0.99, 0.0), Vector3(0.045, 1.86, 0.045), IndustrialKit.K_GALV, galv)
	_box(st, Vector3(0.05, 0.99, 0.0), Vector3(0.045, 1.86, 0.045), IndustrialKit.K_GALV, galv)
	_box(st, Vector3(l * 0.5, 0.99, 0.0), Vector3(l - 0.1, 1.8, 0.008), IndustrialKit.K_CHAIN, galv, 0.0, 16 | 32)
	if wire:
		_box(st, Vector3(l * 0.5, 2.1, 0.0), Vector3(l, 0.36, 0.006), IndustrialKit.K_BARBED, galv, 0.0, 16 | 32)


## A box van (a cutaway with a 4.3 m box), nose at +z, x across: backed into the alley.
static func box_van(st: SurfaceTool, paint: Color, fleet: String) -> void:
	var white := Color(0.86, 0.86, 0.84)
	var bl := 4.3
	var bz := -1.0
	# The box: aluminium sides with posts (the trailer skin), its rear doors, roof.
	_box(st, Vector3(0.0, 0.85 + 1.25, bz), Vector3(2.34, 2.5, bl), IndustrialKit.K_TRAILER, white, bl, 4 | 8 | 32 | 16)
	_box(st, Vector3(0.0, 0.85 + 1.25, bz), Vector3(2.34, 2.5, bl), IndustrialKit.K_TRAILER, white, 0.0, 1 | 2 | 4 | 8 | 32)
	_box(st, Vector3(0.0, 0.85 + 1.25, bz - bl * 0.5 + 0.01), Vector3(2.34, 2.5, 0.02), IndustrialKit.K_TRAILER, white, -1.0, 1 | 2 | 4 | 16 | 32)
	_box(st, Vector3(0.0, 0.85 + 1.25, bz + bl * 0.5 - 0.01), Vector3(2.34, 2.5, 0.02), IndustrialKit.K_TRAILER, white, 0.0, 1 | 2 | 8 | 16 | 32)
	_box(st, Vector3(0.0, 0.7, bz), Vector3(1.1, 0.25, bl - 0.2), IndustrialKit.K_STEEL, Color(0.1, 0.1, 0.1))
	_box(st, Vector3(0.0, 0.55, bz - bl * 0.5 - 0.1), Vector3(2.2, 0.16, 0.2), IndustrialKit.K_STEEL, Color(0.15, 0.15, 0.15))
	# The cab: lower body, glasshouse, hood, bumper, grille, mirrors.
	var cz := bz + bl * 0.5 + 0.95
	_box(st, Vector3(0.0, 1.05, cz), Vector3(2.08, 1.1, 1.9), IndustrialKit.K_STEEL, paint)
	_box(st, Vector3(0.0, 2.0, cz - 0.25), Vector3(2.0, 0.8, 1.35), IndustrialKit.K_STEEL, white)
	_boxr(st, Basis(Vector3.RIGHT, -0.45), Vector3(0.0, 1.98, cz + 0.5), Vector3(1.86, 0.78, 0.04), IndustrialKit.K_GLASS, Color(0.4, 0.45, 0.48), 0.93)
	for sx: float in [-1.0, 1.0]:
		_box(st, Vector3(sx * 1.005, 2.0, cz - 0.15), Vector3(0.02, 0.6, 0.9), IndustrialKit.K_GLASS, Color(0.4, 0.45, 0.48), 0.9)
		_box(st, Vector3(sx * 1.2, 1.9, cz + 0.6), Vector3(0.06, 0.3, 0.16), IndustrialKit.K_STEEL, Color(0.1, 0.1, 0.1))
	_box(st, Vector3(0.0, 1.05, cz + 0.97), Vector3(1.2, 0.5, 0.05), IndustrialKit.K_STEEL, Color(0.12, 0.12, 0.12))
	_box(st, Vector3(0.0, 0.62, cz + 1.0), Vector3(2.1, 0.22, 0.14), IndustrialKit.K_STEEL, Color(0.2, 0.2, 0.2))
	for sx: float in [-0.8, 0.8]:
		_box(st, Vector3(sx, 1.18, cz + 0.96), Vector3(0.28, 0.16, 0.04), IndustrialKit.K_GLASS, Color(0.8, 0.8, 0.78), 0.3)
	# Wheels: the front under the cab, a dual pair at the back of the box.
	for z: float in [cz + 0.15, bz - 0.9]:
		for sx: float in [-1.0, 1.0]:
			IndustrialKit._wheel(st, Vector3(sx * 0.9, 0.4, z), 0.4, 0.28)
	# The fleet's name down both sides.
	for sx: float in [-1.0, 1.0]:
		var b := Basis(Vector3.UP, sx * PI * 0.5)
		_text(st, fleet, Vector3(sx * 1.18, 2.35, bz), 0.32, IndustrialKit.K_PLASTIC, paint, bl - 0.6, b)
		_text(st, "(555) 0142", Vector3(sx * 1.18, 1.75, bz), 0.16, IndustrialKit.K_PLASTIC, Color(0.15, 0.15, 0.15), bl - 1.2, b)


# --- Dressing (Alleys.block_step defers these on FULL chunks) ---------------------------------

## A world point of the alley's frame: `s` along it, `a` across (true world XZ, the chunk's space).
static func _wp(along_x: bool, s: float, a: float) -> Vector2:
	return Vector2(s, a) if along_x else Vector2(a, s)


## The transform of a prop against a wall: at along `s`, across `a` (the wall face), `z_off` out
## of it toward the alley, standing on the alley's ground; x along the wall, z out of it.
static func _xf(ch: CityChunk, along_x: bool, s: float, a: float, out: Vector3, z_off: float, lift: float = 0.0) -> Transform3D:
	var p := _wp(along_x, s, a) + Vector2(out.x, out.z) * z_off
	var y := CityChunk.SIDEWALK_TOP + Alleys.LIFT + ch._gy(p.x, p.y) + lift
	return Transform3D(Basis(Vector3.UP, atan2(out.x, out.z)), Vector3(p.x, y, p.y))


## While dress() decides, the writes it would make: [SurfaceTool, Transform3D, Callable, bind st].
## Written afterwards a few at a time (time-sliced build steps): a long alley's props are tens of
## thousands of SurfaceTool calls, 40-90 ms in one step.
static var _queue: Array = []
static var _queuing: bool = false


## Writes `build` (a geometry function above, bound to its arguments but the SurfaceTool) at `xf`.
static func _put(st: SurfaceTool, xf: Transform3D, build: Callable, with_st: bool = true) -> void:
	if _queuing:
		_queue.append([st, xf, build, with_st])
		return
	IndustrialKit.place(st, xf, Color.WHITE, build.bind(st) if with_st else build)


## Counts a prop of `kind` on the chunk (meta "alley_props", for the checks and the probes).
static func _count(ch: CityChunk, kind: String) -> void:
	var c: Dictionary = ch.get_meta("alley_props", {})
	c[kind] = int(c.get(kind, 0)) + 1
	ch.set_meta("alley_props", c)


## A collision box `size` centred at `local` in the prop's frame `xf`.
static func _collide(ch: CityChunk, xf: Transform3D, local: Vector3, size: Vector3) -> void:
	ch._add_shape(size, xf * local, atan2(xf.basis.z.x, xf.basis.z.z))


static func _free(taken: Array, a: float, b: float) -> bool:
	for t: Vector2 in taken:
		if b > t.x and a < t.y:
			return false
	return true


## Where the power poles of a run stand: [[s, across, side]] - one side of the alley, every
## POLE_SPACING metres on a phase hashed per block; none for the alleys that bury their lines.
static func pole_spots(ch: CityChunk, sp: Dictionary, r: Dictionary) -> Array:
	var out: Array = []
	var plan: CityPlan = ch.plan
	if Alleys._h01([plan.seed, sp.bx, sp.bz, "alley_poles"]) >= Alleys.POLE_ODDS:
		return out
	var side := -1.0 if Alleys._h01([plan.seed, sp.bx, sp.bz, "alley_pole_side"]) < 0.5 else 1.0
	var a := float(r.c) + side * (float(r.w) * 0.5 - 0.32)
	var phase := Alleys._h01([plan.seed, sp.bx, sp.bz, "alley_pole_phase"]) * Alleys.POLE_SPACING
	var s0: float = r.s0
	var s1: float = r.s1
	var k := ceili((s0 + 5.0 - phase) / Alleys.POLE_SPACING)
	while phase + float(k) * Alleys.POLE_SPACING < s1 - 5.0:
		out.append([phase + float(k) * Alleys.POLE_SPACING, a, side])
		k += 1
	return out


## One run's furniture: gates at its mouths, a van backed in, and along each side's back walls
## the doors, lamps, docks, fire escapes, bins, carts, meters, condensers and clutter.
static func dress(ch: CityChunk, sp: Dictionary, r: Dictionary, idx: int) -> void:
	# A fashion district block's market alley is stalls, not the service alley (FashionDistrict).
	if FashionDistrict.dress_market(ch, sp, r, idx):
		return
	_queuing = true
	_queue = []
	var t0 := Time.get_ticks_usec()
	_dress(ch, sp, r, idx)
	if OS.get_environment("ALLEY_TIME") == "1":
		print("ALLEY_DRESS decide %.1f ms, %d writes" % [float(Time.get_ticks_usec() - t0) / 1000.0, _queue.size()])
	_queuing = false
	var jobs: Array[Callable] = []
	for w: Array in _queue:
		var build: Callable = w[2]
		if w[0] == null:
			jobs.append(build)
		else:
			jobs.append(IndustrialKit.place.bind(w[0], w[1], Color.WHITE, build.bind(w[0]) if w[3] else build))
	_queue = []
	YardFill._defer(ch, jobs)


static func _dress(ch: CityChunk, sp: Dictionary, r: Dictionary, idx: int) -> void:
	var plan: CityPlan = ch.plan
	var along_x: bool = sp.along_x
	var s0: float = r.s0
	var s1: float = r.s1
	var c: float = r.c
	var hw: float = float(r.w) * 0.5
	var st := Alleys.walls(ch)
	var state := Alleys._state(ch)
	var across := Vector3(0.0, 0.0, 1.0) if along_x else Vector3(1.0, 0.0, 0.0)
	var along := Vector3(1.0, 0.0, 0.0) if along_x else Vector3(0.0, 0.0, 1.0)
	var taken := {-1: [], 1: []}
	for pole: Array in pole_spots(ch, sp, r):
		(taken[int(pole[2])] as Array).append(Vector2(float(pole[0]) - 0.6, float(pole[0]) + 0.6))
	var rng := Alleys._rng(plan, [sp.bx, sp.bz, "run", idx])
	# Gates at the mouths, swung open against the alley's sides.
	for end: int in [0, 1]:
		var reaches: bool = r.m0 if end == 0 else r.m1
		if not reaches or rng.randf() >= Alleys.GATE_ODDS:
			continue
		var sm := s0 + 0.15 if end == 0 else s1 - 0.15
		var dir := along * (1.0 if end == 0 else -1.0)
		var wire := rng.randf() < 0.5
		for side: float in [-1.0, 1.0]:
			var hinge := _wp(along_x, sm, c + side * (hw - 0.06))
			var y := CityChunk.SIDEWALK_TOP + Alleys.LIFT + ch._gy(hinge.x, hinge.y)
			var xf := Transform3D(Basis(dir, Vector3.UP, dir.cross(Vector3.UP)), Vector3(hinge.x, y, hinge.y))
			_put(st, xf, gate_leaf.bind(minf(hw, 3.0), wire))
			_count(ch, "gate")
			(taken[int(side)] as Array).append(Vector2(minf(sm, sm + dir.dot(along) * hw) - 0.2, maxf(sm, sm + dir.dot(along) * hw) + 0.2))
	# A delivery van backed in from a mouth, along one side (one a chunk at most).
	if not state.has("van") and r.w >= 5.6 and s1 - s0 >= 28.0 and rng.randf() < 0.45:
		state["van"] = true
		var end := 0 if (r.m0 and (not r.m1 or rng.randf() < 0.5)) else 1
		if (r.m0 if end == 0 else r.m1):
			var side := -1.0 if rng.randf() < 0.5 else 1.0
			var sv := (s0 + 7.0) if end == 0 else (s1 - 7.0)
			var nose := along * (-1.0 if end == 0 else 1.0)
			var p := _wp(along_x, sv, c + side * (hw - 1.17 - 0.25))
			var y := CityChunk.SIDEWALK_TOP + Alleys.LIFT + ch._gy(p.x, p.y)
			var xf := Transform3D(Basis(Vector3.UP, atan2(nose.x, nose.z)), Vector3(p.x, y, p.y))
			var pick := rng.randi() % FLEETS.size()
			_put(st, xf, box_van.bind(FLEET_PAINT[pick], FLEETS[pick]))
			_count(ch, "van")
			_collide(ch, xf, Vector3(0.0, 1.7, 0.0), Vector3(2.34, 3.3, 7.2))
			(taken[int(side)] as Array).append(Vector2(sv - 4.2, sv + 4.2))
	# The back walls along each side.
	var parts := StreetWear._ground_parts(ch)
	for side_i: int in [-1, 1]:
		var side := float(side_i)
		var edge := c + side * hw
		var faces: Array = []
		for p: Dictionary in parts:
			var rr: Rect2 = p.rect
			var f0 := rr.position.x if along_x else rr.position.y
			var f1 := rr.end.x if along_x else rr.end.y
			var face: float
			if side < 0.0:
				face = rr.end.y if along_x else rr.end.x
			else:
				face = rr.position.y if along_x else rr.position.x
			var gap := side * (face - edge)
			if gap < -0.05 or gap > 16.0:
				continue
			var u0 := maxf(f0, s0 + 0.6)
			var u1 := minf(f1, s1 - 0.6)
			if u1 - u0 < 2.0:
				continue
			faces.append([gap, u0, u1, face, p])
		faces.sort_custom(func(x: Array, y: Array) -> bool: return float(x[0]) < float(y[0]))
		var covered: Array = []
		for f: Array in faces:
			for piece: Vector2 in StreetWear._subtract(Vector2(float(f[1]), float(f[2])), covered):
				if piece.y - piece.x >= 2.0:
					_face(ch, st, sp, r, side, float(f[3]), maxf(float(f[0]), 0.0), piece, f[4], taken[side_i], idx)
			covered.append(Vector2(float(f[1]), float(f[2])))


## One wall face's stretch `piece` (along) on side `side`, `gap` metres behind the alley's edge.
static func _face(ch: CityChunk, st: SurfaceTool, sp: Dictionary, r: Dictionary, side: float, face: float, gap: float, piece: Vector2,
		part: Dictionary, taken: Array, idx: int) -> void:
	var plan: CityPlan = ch.plan
	var along_x: bool = sp.along_x
	var state := Alleys._state(ch)
	var hw: float = float(r.w) * 0.5
	var out := (Vector3(0.0, 0.0, 1.0) if along_x else Vector3(1.0, 0.0, 0.0)) * -side
	var right := Vector3.UP.cross(out)
	# Local x runs along +s or -s.
	var xs := right.dot(Vector3(1.0, 0.0, 0.0) if along_x else Vector3(0.0, 0.0, 1.0))
	var rng := Alleys._rng(plan, [sp.bx, sp.bz, "face", idx, int(side), int(piece.x * 10.0)])
	var avail := gap + maxf(0.0, (2.0 * hw - LANE) * 0.5)
	var L := piece.y - piece.x
	var mid_p := _wp(along_x, (piece.x + piece.y) * 0.5, face)
	var ground_y := CityChunk.SIDEWALK_TOP + Alleys.LIFT + ch._gy(mid_p.x, mid_p.y)
	var height := float(part.top) - ground_y
	var wall_taken: Array = []
	# A slot of `w` along the face for something `depth` deep (0 for a wall fitting): a free s, or NAN.
	var slot := func(w: float, depth: float, wall: bool) -> float:
		if depth > avail or L < w + 0.4:
			return NAN
		for attempt in 8:
			var s := rng.randf_range(piece.x + w * 0.5 + 0.2, piece.y - w * 0.5 - 0.2)
			var list: Array = wall_taken if wall else taken
			if _free(list, s - w * 0.5, s + w * 0.5):
				list.append(Vector2(s - w * 0.5, s + w * 0.5))
				return s
		return NAN
	# A fire escape over the alley.
	if height >= 11.0 and L >= 4.0 and rng.randf() < Alleys.FIRE_ESCAPE_ODDS:
		var s := float(slot.call(3.0, 0.0, true))
		if not is_nan(s):
			var fh := maxf(float(part.floor_h), 3.0)
			var first := maxf(float(part.gfh) - ground_y, 3.6)
			var levels: Array = []
			var y := first
			while y < height - 1.6 and levels.size() < 7:
				levels.append(y)
				y += fh
			if levels.size() >= 1:
				_put(st, _xf(ch, along_x, s, face, out, 0.0), fire_escape.bind(2.8, levels, 2.4))
				_count(ch, "escape")
	# Back doors: steel doors, some at a loading dock; each under a caged lamp.
	var doors := clampi(int(L / 11.0) + (1 if rng.randf() < 0.5 else 0), 1, 4)
	var door_at: Array[float] = []
	for k in doors:
		if L >= 9.0 and avail >= 1.9 and rng.randf() < Alleys.DOCK_ODDS:
			var stair := -1.0 if rng.randf() < 0.5 else 1.0
			var s := float(slot.call(5.2, 1.85, false))
			if is_nan(s):
				continue
			wall_taken.append(Vector2(s - 2.0, s + 2.0))
			var ds := s - stair * xs * 0.7
			var xf := _xf(ch, along_x, ds, face, out, 0.0)
			_put(st, xf, dock.bind(3.4, 1.15, 1.85, stair, DOOR_PAINT[rng.randi() % DOOR_PAINT.size()]))
			_count(ch, "dock")
			_collide(ch, xf, Vector3(0.0, 0.58, 0.93), Vector3(3.4, 1.15, 1.85))
			_lamp_at(ch, st, along_x, ds + 2.0 * xs, face, out, 3.9, rng)
			door_at.append(ds)
			continue
		var s := float(slot.call(1.7, 0.0, true))
		if is_nan(s):
			continue
		var stoop := avail >= 0.9 and rng.randf() < 0.45
		# The doorway is kept clear on the ground too.
		taken.append(Vector2(s - 0.8, s + 0.8))
		var addr := ""
		if rng.randf() < 0.45:
			addr = "%d" % (100 + (absi(hash([plan.seed, sp.bx, sp.bz, int(s)])) % 89) * 10 + (2 if side > 0.0 else 1))
		_put(st, _xf(ch, along_x, s, face, out, 0.0), back_door.bind(DOOR_PAINT[rng.randi() % DOOR_PAINT.size()], addr, stoop))
		_count(ch, "door")
		if stoop:
			_collide(ch, _xf(ch, along_x, s, face, out, 0.0), Vector3(0.0, 0.085, 0.42), Vector3(1.5, 0.17, 0.84))
		_lamp_at(ch, st, along_x, s, face, out, 2.62 + (0.17 if stoop else 0.0), rng)
		door_at.append(s)
		# A cook on a smoke break by the door (a couple a chunk at most, in the crowd cap): made in a
		# build step of its own, a rig is tens of milliseconds.
		if int(state.get("cooks", 0)) < Alleys.MAX_COOKS and rng.randf() < Alleys.COOK_ODDS:
			state["cooks"] = int(state.get("cooks", 0)) + 1
			var cs := s + xs * (1.1 if rng.randf() < 0.5 else -1.1)
			var at := _wp(along_x, cs, face) + Vector2(out.x, out.z) * 0.7
			var look := out.rotated(Vector3.UP, rng.randf_range(-0.9, 0.9))
			var seed_value := absi(hash([plan.seed, sp.bx, sp.bz, "cook", int(cs)]))
			_queue.append([null, Transform3D(), spawn_cook.bind(ch, sp.rect, seed_value, at, atan2(-look.x, -look.z)), false])
	# Along the foot of the wall, a walk: every few metres the next thing a back of house puts
	# out - a dumpster, a row of carts, a grease bin, pallets, crates, a condenser on its pad, the
	# gas meters, now and then an old mattress - or nothing, where it fits beside what is there.
	var hauler := absi(hash([plan.seed, sp.bx, sp.bz, "hauler"])) % Alleys.HAULERS.size()
	var s := piece.x + rng.randf_range(0.4, 3.0)
	var guard := 0
	while s < piece.y - 0.8 and guard < 40:
		guard += 1
		var roll := rng.randf()
		var w := 1.0
		var depth := 0.0
		var kind := ""
		var n := 1
		if roll < 0.24:
			kind = "dumpster"
			w = 2.1
			depth = 1.25
		elif roll < 0.36:
			kind = "carts"
			n = rng.randi_range(2, 3)
			w = 0.72 * float(n)
			depth = 0.85
		elif roll < 0.5:
			kind = "grease"
			w = 1.4
			depth = 0.95
		elif roll < 0.59:
			kind = "pallets"
			w = 1.4
			depth = 1.1
		elif roll < 0.68:
			kind = "crates"
			w = 1.2
			depth = 0.45
		elif roll < 0.74:
			kind = "condenser"
			w = 1.1
			depth = 0.98
		elif roll < 0.81:
			kind = "meters"
			n = rng.randi_range(1, 4)
			w = 0.42 * float(n) + 0.3
			depth = 0.3
		elif roll < 0.835:
			kind = "mattress"
			w = 1.6
			depth = 0.65
		var c := s + w * 0.5
		if kind == "" or c + w * 0.5 > piece.y - 0.2 or depth > avail or not _free(taken, c - w * 0.5, c + w * 0.5):
			s += rng.randf_range(1.5, 4.0)
			continue
		taken.append(Vector2(c - w * 0.5, c + w * 0.5))
		match kind:
			"dumpster":
				var pick := hauler if rng.randf() < 0.75 else rng.randi() % Alleys.HAULERS.size()
				var lid := Color(0.06, 0.06, 0.06) if rng.randf() < 0.6 else Color(0.12, 0.3, 0.14)
				var xf := _xf(ch, along_x, c, face, out, 0.06)
				xf.basis = xf.basis * Basis(Vector3.UP, rng.randf_range(-0.06, 0.06))
				_put(st, xf, dumpster.bind(Alleys.HAULER_PAINT[pick], lid, Alleys.HAULERS[pick], rng.randf() < 0.3))
				_count(ch, "dumpster")
				_collide(ch, xf, Vector3(0.0, 0.66, 0.56), Vector3(1.9, 1.25, 1.1))
			"carts":
				for i in n:
					var cs := c + (float(i) - float(n - 1) * 0.5) * 0.72
					var body: Color = CART_PAINT[rng.randi() % CART_PAINT.size()]
					var xf := _xf(ch, along_x, cs, face, out, 0.42)
					xf.basis = xf.basis * Basis(Vector3.UP, rng.randf_range(-0.15, 0.15) + (PI if rng.randf() < 0.2 else 0.0))
					_put(st, xf, cart.bind(body, body * 0.8 if rng.randf() < 0.6 else Color(0.25, 0.25, 0.25)))
					_count(ch, "cart")
			"grease":
				var xf := _xf(ch, along_x, c, face, out, 0.05)
				_put(st, xf, grease_bin.bind(Color(0.16, 0.16, 0.17) if rng.randf() < 0.6 else Color(0.32, 0.3, 0.27)))
				_count(ch, "grease")
				_collide(ch, xf, Vector3(0.0, 0.47, 0.45), Vector3(1.15, 0.95, 0.85))
			"pallets":
				var xf := _xf(ch, along_x, c, face, out, 0.55)
				xf.basis = xf.basis * Basis(Vector3.UP, rng.randf_range(-0.2, 0.2))
				_put(st, xf, IndustrialKit.pallets.bind(0 if rng.randf() < 0.7 else 3), false)
				_count(ch, "pallets")
				_collide(ch, xf, Vector3(0.0, 0.5, 0.0), Vector3(1.2, 1.0, 1.0))
			"crates":
				_put(st, _xf(ch, along_x, c, face, out, 0.02), crates.bind(rng))
				_count(ch, "crates")
			"condenser":
				var xf := _xf(ch, along_x, c, face, out, 0.0)
				_put(st, xf, condenser_ground)
				_count(ch, "condenser")
				_collide(ch, xf, Vector3(0.0, 0.5, 0.5), Vector3(0.85, 1.0, 0.8))
			"meters":
				_put(st, _xf(ch, along_x, c, face, out, 0.0), gas_meters.bind(n))
				_count(ch, "meters")
			"mattress":
				var tones := [Color(0.78, 0.76, 0.7), Color(0.72, 0.66, 0.58), Color(0.62, 0.66, 0.7)]
				_put(st, _xf(ch, along_x, c, face, out, 0.0), mattress.bind(tones[rng.randi() % tones.size()]))
				_count(ch, "mattress")
		s = c + w * 0.5 + rng.randf_range(0.6, 4.5)
	# On the wall: gas meters, an electrical panel, condensers on brackets.
	if rng.randf() < 0.6:
		var sp_at := float(slot.call(0.9, 0.0, true))
		if not is_nan(sp_at):
			_put(st, _xf(ch, along_x, sp_at, face, out, 0.0), panel.bind(clampf(height - 2.5, 0.5, 2.5)))
			_count(ch, "panel")
	var n_ac := rng.randi_range(0, 3) if height > 5.0 else 0
	for k in n_ac:
		var s_ac := rng.randf_range(piece.x + 0.6, piece.y - 0.6)
		var y := rng.randf_range(2.9, minf(height - 1.2, 9.0))
		if y < 2.9:
			continue
		_put(st, _xf(ch, along_x, s_ac, face, out, 0.0), condenser.bind(y, rng.randf_range(0.5, 2.0)))
		_count(ch, "condenser")


## The cook by a back door, if the crowd cap has room for one more person.
static func spawn_cook(ch: CityChunk, rect: Rect2, seed_value: int, at: Vector2, yaw: float) -> void:
	if not ch._take_crowd_room():
		return
	var cook := AlleyCook.new()
	cook.setup_vendor(rect, seed_value, at, yaw, false, 0.0)
	cook.position = Vector3(at.x, ch.ground_y(at.x, at.y) + Alleys.LIFT + 0.05, at.y)
	ch.add_child(cook)
	_count(ch, "cook")


## A caged lamp on the wall at `y` over the ground, its light pool on the alley, and now and then a
## real light (the street lamps' group: DayNight drives it, Quality turns it off).
static func _lamp_at(ch: CityChunk, st: SurfaceTool, along_x: bool, s: float, face: float, out: Vector3, y: float, rng: RandomNumberGenerator) -> void:
	var state := Alleys._state(ch)
	if int(state.lamps) >= Alleys.MAX_LAMPS:
		return
	state.lamps = int(state.lamps) + 1
	var warm := rng.randf() < 0.65
	_put(st, _xf(ch, along_x, s, face, out, 0.0), lamp.bind(y, LAMP_WARM if warm else LAMP_COOL))
	_count(ch, "lamp")
	var p := _wp(along_x, s, face) + Vector2(out.x, out.z) * 1.6
	var pool := Transform3D(Basis(Vector3.RIGHT, -PI * 0.5).scaled(Vector3(7.5, 1.0, 7.5)), Vector3(p.x, CityChunk.SIDEWALK_TOP + Alleys.LIFT + 0.1, p.y))
	ch._batch.add("alley_pool", PropFactory.light_pool(Color(1.0, 0.82, 0.58), 0.85, 1.7), pool)
	if int(state.lights) < Alleys.MAX_LIGHTS and rng.randf() < 0.5:
		state.lights = int(state.lights) + 1
		var light := OmniLight3D.new()
		var lp := _wp(along_x, s, face) + Vector2(out.x, out.z) * 0.45
		light.position = Vector3(lp.x, CityChunk.SIDEWALK_TOP + Alleys.LIFT + y - 0.15 + ch._gy(lp.x, lp.y), lp.y)
		light.omni_range = 7.5
		light.omni_attenuation = 1.5
		# The district's lamp light (NightCity: its sodium or LED patch), like every street lamp.
		light.light_color = NightCity.lamp_light(Vector2(lp.x, lp.y))
		light.light_energy = 0.0
		light.shadow_enabled = false
		light.distance_fade_enabled = true
		light.distance_fade_begin = 40.0
		light.distance_fade_length = 12.0
		light.add_to_group("lamp_light")
		ch.add_child(light)


## The alley's power line: wooden poles on StreetDetail's batches, spans between them, guys at the
## ends, transformers, service drops across to the walls.
static func poles(ch: CityChunk, sp: Dictionary, rs: Array) -> void:
	var plan: CityPlan = ch.plan
	var along_x: bool = sp.along_x
	var batch: MultiMeshBatch = ch._batch
	var top: float = CityChunk.SIDEWALK_TOP
	var yaw := PI * 0.5 if along_x else 0.0
	var arm := Vector3(0.0, 0.0, 1.0) if along_x else Vector3(1.0, 0.0, 0.0)
	var run_dir := Vector3(1.0, 0.0, 0.0) if along_x else Vector3(0.0, 0.0, 1.0)
	var parts := StreetWear._ground_parts(ch)
	var any := false
	for r: Dictionary in rs:
		var spots := pole_spots(ch, sp, r)
		var points: Array[Vector3] = []
		for spot: Array in spots:
			var q := _wp(along_x, float(spot[0]), float(spot[1]))
			var p := Vector3(q.x, top, q.y)
			points.append(p)
			any = true
			batch.add("upole", PropFactory.upole(), Transform3D(Basis(Vector3.UP, yaw), p + Vector3(0.0, StreetDetail.POLE_HEIGHT * 0.5, 0.0)))
			_count(ch, "pole")
			batch.add("crossarm", PropFactory.crossarm(), Transform3D(Basis(Vector3.UP, yaw), p + Vector3(0.0, StreetDetail.POWER_ARM_HEIGHT, 0.0)))
			batch.add("crossarm", PropFactory.crossarm(), Transform3D(Basis(Vector3.UP, yaw).scaled_local(Vector3(0.62, 1.0, 1.0)), p + Vector3(0.0, StreetDetail.TELCO_ARM_HEIGHT, 0.0)))
			for i in 3:
				batch.add("insulator", StreetDetail._insulator_mesh(), Transform3D(Basis(), p + arm * (i - 1) * 0.72 + Vector3(0.0, StreetDetail.POWER_ARM_HEIGHT + 0.14, 0.0)))
			if Alleys._h01([plan.seed, "alley_xfmr", int(p.x), int(p.z)]) < 0.4:
				batch.add("transformer", StreetDetail._transformer_mesh(), Transform3D(Basis(), p + arm * 0.5 + Vector3(0.0, StreetDetail.POWER_ARM_HEIGHT - 1.0, 0.0)))
			ch._add_shape(Vector3(0.36, StreetDetail.POLE_HEIGHT, 0.36), p + Vector3(0.0, StreetDetail.POLE_HEIGHT * 0.5 + ch._gy(p.x, p.z), 0.0), yaw)
			# A service drop across to the wall on the far side.
			if Alleys._h01([plan.seed, "alley_drop", int(p.x), int(p.z)]) < 0.6:
				var side := float(spot[2])
				var best := INF
				for pd: Dictionary in parts:
					var rr: Rect2 = pd.rect
					var lo := rr.position.x if along_x else rr.position.y
					var hi := rr.end.x if along_x else rr.end.y
					var s: float = spot[0]
					if s < lo or s > hi:
						continue
					var face := (rr.position.y if along_x else rr.position.x) if side < 0.0 else (rr.end.y if along_x else rr.end.x)
					var d := (face - float(spot[1])) * -side
					if d > 0.5 and d < best and d < 12.0:
						best = d
				if best < INF:
					var wall := p + arm * -side * (best + 0.3)
					StreetDetail._catenary(batch, StreetDetail._lift(ch, p, StreetDetail.TELCO_ARM_HEIGHT), StreetDetail._lift(ch, wall, StreetDetail.SERVICE_DROP_HEIGHT + 1.2), 0.45)
		for i in points.size() - 1:
			StreetDetail._span(ch, points[i], points[i + 1], arm)
		if not points.is_empty():
			StreetDetail._guy(ch, points[0], -run_dir)
			StreetDetail._guy(ch, points[points.size() - 1], run_dir)
	if any:
		batch.set_no_shadow("cable")
		batch.set_draw_distance("cable", StreetDetail.CABLE_DRAW_DISTANCE)
		batch.set_draw_distance("insulator", StreetDetail.POLE_FITTING_DRAW_DISTANCE)


## StreetWear's tags, posters and grime on the alley's walls: the alley's centre line handed to it
## as a kerb on each side.
static func wear(ch: CityChunk, sp: Dictionary, rs: Array) -> void:
	if not StreetWear.enabled:
		return
	var plan: CityPlan = ch.plan
	var along_x: bool = sp.along_x
	# One cap for the chunk's wear, the street's and the alley's together.
	var before: PackedVector2Array = ch.get_meta("street_wear", PackedVector2Array())
	var ctx := {"chunk": ch, "count": before.size(), "points": [], "modes": {}, "blocked": StreetWear._worship_near(plan, ch.owned_rect())}
	var edges: Array = []
	for r: Dictionary in rs:
		var a := _wp(along_x, float(r.s0), float(r.c))
		var b := _wp(along_x, float(r.s1), float(r.c))
		var inv := Vector2(0.0, 1.0) if along_x else Vector2(1.0, 0.0)
		edges.append([a, b, -inv])
		edges.append([a, b, inv])
	if edges.size() > 4:
		edges.resize(4)
	StreetWear._walls(ctx, edges, int(sp.district))
	if int(ctx.count) > 0:
		ch._batch.set_no_shadow(StreetWear.KEY)
		ch._batch.set_draw_distance(StreetWear.KEY, StreetWear.DRAW_DISTANCE)
	ch.set_meta("alley_wear", (ctx.points as Array).size())
	# Counted with the street's own (StreetWear.build() ran first: its step is before the deferred
	# ones), so the chunk's tally is the batch's.
	var pts: PackedVector2Array = ch.get_meta("street_wear", PackedVector2Array())
	pts.append_array(PackedVector2Array(ctx.points))
	ch.set_meta("street_wear", pts)
	var modes: Dictionary = ch.get_meta("street_wear_modes", {})
	for m: int in ctx.modes:
		modes[m] = int(modes.get(m, 0)) + int(ctx.modes[m])
	ch.set_meta("street_wear_modes", modes)
