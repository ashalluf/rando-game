class_name FreightStock
extends RefCounted
## The freight line's rolling stock, built in code at real size (FreightRail.Car): the Arroyo
## Pacific's wide-cab six-axle road locomotive, and the cars - a 53 ft single well car (its
## containers are PortKit's, stacked by FreightRailSystem), a 30,000 gal tank car, a 60 ft
## high-cube boxcar, a three-bay covered hopper and a tri-level autorack. One ArrayMesh per type
## on freight_stock.gdshader, each a LOD ladder (PortKit.ladder: the near level and a mid one
## without the handrails, ladders, grabs and small hardware), so a MultiMesh draws any level of
## any car.
##
## Frame: origin on the rail tops at the car's middle, length along Z (the loco's cab end and a
## car's "B" end toward -Z), up +Y, metres. What a vertex is rides in UV2.x (P_*), the paint in
## the vertex colour (sRGB): P_PAINT multiplies the instance colour (each car its own paint),
## P_FIXED keeps its own (the locomotive's livery bands, lettering). The instance custom data is
## (paint * 16 + wear, seed, flags, number): flags 1 = this unit's cab-end lamps lit, 0.5 = its rear-end
## lamps lit; number the last three digits of the road number / 1000. Paint and wear share the
## first: paint index (PALETTE) * 16 + wear (0..15), an integer, exact in a half float. The instance
## colour stays white (Godot multiplies it into every vertex colour).

const P_PAINT := 0.0
const P_STEEL := 1.0
const P_BLACK := 2.0
const P_GLASS := 3.0
const P_HEAD := 4.0
const P_SAFETY := 5.0
const P_NUMBER := 6.0
const P_LETTER := 7.0
const P_GRILLE := 8.0
const P_WHEEL := 9.0
const P_TAPE := 10.0
const P_PERF := 11.0
const P_FIXED := 12.0
const P_DITCH := 13.0
const P_REAR := 14.0
const P_TANK := 15.0

## The Arroyo Pacific's livery (sRGB): red hood and cab, a sand band, grey roof, black frame.
const LOCO_RED := Color(0.55, 0.15, 0.09)
const LOCO_SAND := Color(0.86, 0.77, 0.56)
const LOCO_ROOF := Color(0.21, 0.21, 0.22)
const FRAME := Color(0.07, 0.07, 0.075)
const TRUCK := Color(0.09, 0.085, 0.08)
const SAFETY := Color(0.93, 0.74, 0.08)
const WHITE := Color(1.0, 1.0, 1.0)

## Every paint a car or a far box wears (sRGB), one table the shader mirrors (PALETTE in
## freight_stock.gdshader): the car paints, the locomotive's red, the container lines' colours.
const PALETTE := [
	Color(0.30, 0.17, 0.11), Color(0.12, 0.12, 0.13), Color(0.36, 0.33, 0.30), Color(0.42, 0.20, 0.12),
	Color(0.07, 0.07, 0.075), Color(0.72, 0.72, 0.70), Color(0.42, 0.17, 0.11), Color(0.45, 0.2, 0.12),
	Color(0.3, 0.33, 0.36), Color(0.55, 0.42, 0.18), Color(0.18, 0.26, 0.40), Color(0.33, 0.12, 0.10),
	Color(0.66, 0.65, 0.62), Color(0.78, 0.77, 0.74), Color(0.50, 0.44, 0.36), Color(0.36, 0.36, 0.38),
	Color(0.76, 0.76, 0.74), Color(0.25, 0.30, 0.38),
	Color(0.55, 0.15, 0.09),
	Color(0.10, 0.24, 0.47), Color(0.46, 0.13, 0.10), Color(0.12, 0.33, 0.22), Color(0.85, 0.43, 0.12),
	Color(0.70, 0.71, 0.70), Color(0.42, 0.16, 0.32), Color(0.62, 0.64, 0.66), Color(0.32, 0.34, 0.36), Color(0.88, 0.88, 0.85),
]
## The palette entries each car type picks from (FreightRail.Car); the loco's red; the far box of a
## container line `l` is entry LIVERY0 + l.
const PAINTS := {
	1: [0, 1, 2, 3],
	2: [4, 4, 5, 1],
	3: [6, 7, 8, 9, 10, 11],
	4: [12, 13, 14, 15],
	5: [16, 2, 0, 17],
}
const LOCO_PAINT := 18
const LIVERY0 := 19

static var _meshes: Dictionary = {}
static var _material: ShaderMaterial
static var _box_mesh: ArrayMesh


## The custom data of a car: its paint (from its type's list, by `look`) and wear, seed, lamps
## (-1 for a car), number.
static func custom(t: int, look: int, lamps: float = -1.0, number: float = -1.0, paint: int = -1) -> Color:
	var list: Array = PAINTS.get(t, [LOCO_PAINT])
	var p := paint if paint >= 0 else int(list[absi(look) % list.size()])
	var wear := (absi(look) >> 3) % 16
	var num := number if number >= 0.0 else float((absi(look) >> 2) % 1000) / 1000.0
	return Color(float(p * 16 + wear), float((absi(look) >> 9) % 997) / 997.0, lamps, num)


static func material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = load("res://shaders/freight_stock.gdshader")
	return _material


## The mesh of car type `t` (FreightRail.Car).
static func mesh(t: int) -> ArrayMesh:
	if _meshes.has(t):
		return _meshes[t]
	var levels: Array = []
	for lv in 2:
		var b := PortKit.Buf.new()
		match t:
			FreightRail.Car.LOCO:
				_loco(b, lv)
			FreightRail.Car.WELL:
				_well(b, lv)
			FreightRail.Car.TANK:
				_tank(b, lv)
			FreightRail.Car.BOX:
				_boxcar(b, lv)
			FreightRail.Car.HOPPER:
				_hopper(b, lv)
			_:
				_autorack(b, lv)
		levels.append(b)
	var m := PortKit.ladder(levels, [0.0, 0.12], material())
	_meshes[t] = m
	return m


## Triangles of type t's near level (the checks hold it to a budget).
static func triangles(t: int) -> int:
	var m := mesh(t)
	var arr := m.surface_get_arrays(0)
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	return idx.size() / 3


## Every mesh built (the loading screen's warm-up).
static func warm() -> void:
	for t in 6:
		mesh(t)
	far_box()


## The far stand-in: a unit box (bottom at 0) the far trains scale to each car's envelope.
static func far_box() -> ArrayMesh:
	if _box_mesh != null:
		return _box_mesh
	var b := PortKit.Buf.new()
	b.color = WHITE
	b.part = P_PAINT
	b.box(Vector3(-0.5, 0.0, -0.5), Vector3(0.5, 1.0, 0.5), 63 & ~8)
	var arr := b.arrays()
	_box_mesh = ArrayMesh.new()
	_box_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return _box_mesh


## Each type's envelope (width, height over the rail, length) for the far boxes and collision.
static func envelope(t: int) -> Vector3:
	match t:
		FreightRail.Car.LOCO:
			return Vector3(3.1, 4.7, 22.3)
		FreightRail.Car.WELL:
			return Vector3(2.9, 1.6, 21.6)
		FreightRail.Car.TANK:
			return Vector3(3.1, 4.4, 17.6)
		FreightRail.Car.BOX:
			return Vector3(3.2, 5.2, 18.8)
		FreightRail.Car.HOPPER:
			return Vector3(3.2, 4.6, 17.6)
	return Vector3(3.2, 5.7, 27.2)


# --- Shared parts --------------------------------------------------------------------------------

static func _paint(b: PortKit.Buf, col: Color, part: float, ao: float = 1.0) -> void:
	b.color = col
	b.part = part
	b.ao = ao


## A two-axle freight truck centred at z (side frames, bolster, springs, bearings, wheelsets).
static func _truck(b: PortKit.Buf, z: float, lv: int) -> void:
	var wb := 0.889
	var r := 0.457
	_paint(b, TRUCK, P_STEEL, 0.6)
	for sx: float in [-1.0, 1.0]:
		var x := sx * 1.0
		# Side frame: top and bottom chords, the columns either side of the spring window.
		b.beam(Vector3(x, 0.78, z - 1.25), Vector3(x, 0.78, z + 1.25), 0.16, 0.14)
		b.beam(Vector3(x, 0.38, z - 0.55), Vector3(x, 0.38, z + 0.55), 0.16, 0.14)
		b.beam(Vector3(x, 0.78, z - 1.25), Vector3(x, 0.38, z - 0.55), 0.14, 0.16)
		b.beam(Vector3(x, 0.78, z + 1.25), Vector3(x, 0.38, z + 0.55), 0.14, 0.16)
		for e: float in [-1.0, 1.0]:
			b.box(Vector3(x - 0.08, 0.36, z + e * 0.42 - 0.06), Vector3(x + 0.08, 0.8, z + e * 0.42 + 0.06))
		# Journal bearings with their end caps.
		for e: float in [-1.0, 1.0]:
			_paint(b, Color(0.16, 0.15, 0.14), P_STEEL, 0.7)
			b.cyl(Vector3(x - 0.12, r, z + e * wb), Vector3(x + 0.12 * sx + 0.06 * sx, r, z + e * wb), 0.12, 8 if lv == 0 else 6, true)
			_paint(b, TRUCK, P_STEEL, 0.6)
		if lv == 0:
			# The spring nest in the window.
			_paint(b, Color(0.12, 0.11, 0.1), P_STEEL, 0.5)
			for k in 3:
				b.cyl(Vector3(x, 0.45, z - 0.2 + float(k) * 0.2), Vector3(x, 0.62, z - 0.2 + float(k) * 0.2), 0.07, 6)
			_paint(b, TRUCK, P_STEEL, 0.6)
	# Bolster across.
	b.box(Vector3(-1.05, 0.6, z - 0.2), Vector3(1.05, 0.78, z + 0.2))
	# Wheelsets.
	for e: float in [-1.0, 1.0]:
		_wheelset(b, z + e * wb, r, lv)


static func _wheelset(b: PortKit.Buf, z: float, r: float, lv: int) -> void:
	var sides := 16 if lv == 0 else 10
	for sx: float in [-1.0, 1.0]:
		_paint(b, Color(0.32, 0.30, 0.28), P_WHEEL, 0.7)
		b.cyl(Vector3(sx * 0.66, r, z), Vector3(sx * 0.80, r, z), r, sides, true)
		# Flange.
		_paint(b, Color(0.22, 0.2, 0.19), P_WHEEL, 0.6)
		b.cyl(Vector3(sx * 0.645, r, z), Vector3(sx * 0.66, r, z), r + 0.025, sides, false)
	_paint(b, Color(0.2, 0.19, 0.18), P_STEEL, 0.5)
	b.cyl(Vector3(-0.8, r, z), Vector3(0.8, r, z), 0.085, 6)


## A coupler and its draft gear sticking out of the end at z (sign: which end).
static func _coupler(b: PortKit.Buf, z: float, sign: float, y: float) -> void:
	_paint(b, Color(0.1, 0.1, 0.1), P_STEEL, 0.6)
	b.box(Vector3(-0.15, y - 0.12, z - (0.0 if sign > 0.0 else 0.55)), Vector3(0.15, y + 0.12, z + (0.55 if sign > 0.0 else 0.0)))
	b.box(Vector3(-0.22, y - 0.18, z + sign * 0.45 - 0.12), Vector3(0.22, y + 0.18, z + sign * 0.45 + 0.12))
	# Air hose hanging below.
	_paint(b, Color(0.03, 0.03, 0.03), P_BLACK, 0.6)
	b.beam(Vector3(0.3, y - 0.05, z + sign * 0.1), Vector3(0.35, y - 0.45, z + sign * 0.42), 0.06, 0.06)


## A ladder of `rungs` on a face at (x, z) facing `out`, from y0 up.
static func _ladder(b: PortKit.Buf, base: Vector3, out: Vector3, along: Vector3, y0: float, rungs: int, col: Color) -> void:
	_paint(b, col, P_SAFETY, 1.0)
	for e: float in [-0.22, 0.22]:
		var p := base + along * e + out * 0.06
		b.beam(Vector3(p.x, y0, p.z), Vector3(p.x, y0 + 0.4 * float(rungs), p.z), 0.04, 0.04)
	for k in rungs:
		var p := base + out * 0.08 + Vector3.UP * (y0 + 0.2 + 0.4 * float(k))
		b.beam(p - along * 0.22, p + along * 0.22, 0.025, 0.025, -1.0, -1.0, out)


## Retroreflective tape: a patch on a face, alternating yellow (conspicuity).
static func _tape(b: PortKit.Buf, c: Vector3, out: Vector3, along: Vector3) -> void:
	_paint(b, Color(0.95, 0.82, 0.18), P_TAPE, 1.0)
	var o := out * 0.012
	b.quad(c - along * 0.23 - Vector3.UP * 0.05 + o, c + along * 0.23 - Vector3.UP * 0.05 + o, c + along * 0.23 + Vector3.UP * 0.05 + o, c - along * 0.23 + Vector3.UP * 0.05 + o, out)


## Lettering from FreewayKit's TextMesh cache, laid on a face: centred at `at`, reading along
## `right` (with up +Y), facing `out`.
static func _letters(b: PortKit.Buf, text: String, height: float, at: Vector3, right: Vector3, out: Vector3, col: Color) -> void:
	var geo := FreewayKit.text_geo(text, height)
	var verts: PackedVector3Array = geo[0]
	var idx: PackedInt32Array = geo[1]
	_paint(b, col, P_LETTER, 1.0)
	var o := out * 0.012
	for k in range(0, idx.size() - 2, 3):
		var p0 := verts[idx[k]]
		var p1 := verts[idx[k + 1]]
		var p2 := verts[idx[k + 2]]
		var a := at + right * p0.x + Vector3.UP * p0.y + o
		var c := at + right * p1.x + Vector3.UP * p1.y + o
		var d := at + right * p2.x + Vector3.UP * p2.y + o
		var i0 := b._push(a, out)
		var i1 := b._push(c, out)
		var i2 := b._push(d, out)
		b._tri_idx(i0, i1, i2, out)


## A digit field (P_NUMBER) on a face: the shader draws the road number into it (UV 0..1 across
## and up), lit at night where it is a number board.
static func _number_field(b: PortKit.Buf, c: Vector3, right: Vector3, out: Vector3, w: float, h: float, col: Color) -> void:
	_paint(b, col, P_NUMBER, 1.0)
	var o := out * 0.013
	var i0 := b.v.size()
	b.quad(c - right * w * 0.5 - Vector3.UP * h * 0.5 + o, c + right * w * 0.5 - Vector3.UP * h * 0.5 + o,
		c + right * w * 0.5 + Vector3.UP * h * 0.5 + o, c - right * w * 0.5 + Vector3.UP * h * 0.5 + o, out)
	# The quad may have swapped b and d for its winding: set each vertex's UV from where it is
	# (x in heights from the field's centre, y 0..1 up it: the shader centres the digits).
	for i in range(i0, b.v.size()):
		var rel := b.v[i] - c
		b.uv[i] = Vector2(rel.dot(right) / h, rel.y / h + 0.5)


# --- The locomotive ------------------------------------------------------------------------------

## The road locomotive: 22.3 m over the anticlimbers, 3.1 m wide, 4.7 m high; a wide safety cab
## at -Z, the long hood behind it with the dynamic brake blister, the radiator section and its
## fans at the rear; two three-axle trucks, the fuel tank between them; walkways, handrails, steps
## and pilots at both ends.
static func _loco(b: PortKit.Buf, lv: int) -> void:
	var hl := 10.6
	var deck := 1.78
	# Frame: the deck plate, its black side sill, the pilots.
	_paint(b, FRAME, P_FIXED, 0.8)
	b.box(Vector3(-1.55, deck - 0.22, -hl), Vector3(1.55, deck, hl))
	b.box(Vector3(-1.56, 1.25, -hl), Vector3(1.56, deck - 0.22, hl), 63 & ~4)
	for e: float in [-1.0, 1.0]:
		var ze := e * hl
		# Pilot: a sloped plate down to the snowplow, the anticlimber over it.
		_paint(b, FRAME, P_FIXED, 0.8)
		# The pilot sheet between the corner step wells (open at the corners so the steps show),
		# the wells' inner walls behind it.
		b.quad(Vector3(-0.95, 1.25, ze), Vector3(0.95, 1.25, ze), Vector3(0.95, 0.3, ze + e * 0.35), Vector3(-0.95, 0.3, ze + e * 0.35), Vector3(0, -0.3, e).normalized())
		for sx: float in [-1.0, 1.0]:
			b.quad(Vector3(sx * 0.95, 1.25, ze), Vector3(sx * 0.95, 0.3, ze + e * 0.35), Vector3(sx * 0.95, 0.3, ze - e * 0.9), Vector3(sx * 0.95, 1.25, ze - e * 0.9), Vector3(sx, 0, 0))
			b.quad(Vector3(sx * 0.95, 1.25, ze - e * 0.9), Vector3(sx * 1.56, 1.25, ze - e * 0.9), Vector3(sx * 1.56, 0.3, ze - e * 0.9), Vector3(sx * 0.95, 0.3, ze - e * 0.9), Vector3(0, 0, e))
		if lv == 0:
			# Air hoses and MU cables hanging off the pilot either side of the coupler.
			_paint(b, Color(0.03, 0.03, 0.03), P_BLACK, 0.7)
			for hx: float in [-0.55, -0.4, 0.4, 0.55]:
				b.beam(Vector3(hx, 1.05, ze + e * 0.08), Vector3(hx * 1.05, 0.62, ze + e * 0.32), 0.05, 0.05)
			# The white reflective strip along the pilot's top edge.
			_paint(b, Color(0.9, 0.9, 0.88), P_TAPE, 1.0)
			b.quad(Vector3(-0.95, 1.12, ze + e * 0.03), Vector3(0.95, 1.12, ze + e * 0.03), Vector3(0.95, 1.2, ze + e * 0.01), Vector3(-0.95, 1.2, ze + e * 0.01), Vector3(0, 0, e))
		b.box(Vector3(-1.45, deck - 0.12, ze + (0.0 if e > 0.0 else -0.18)), Vector3(1.45, deck + 0.04, ze + (0.18 if e > 0.0 else 0.0)))
		# The snowplow wedge.
		_paint(b, FRAME, P_FIXED, 0.7)
		b.quad(Vector3(-1.45, 0.14, ze + e * 0.42), Vector3(0.0, 0.14, ze + e * 0.75), Vector3(0.0, 0.55, ze + e * 0.5), Vector3(-1.45, 0.55, ze + e * 0.32), Vector3(-0.3, 0.2, e).normalized())
		b.quad(Vector3(0.0, 0.14, ze + e * 0.75), Vector3(1.45, 0.14, ze + e * 0.42), Vector3(1.45, 0.55, ze + e * 0.32), Vector3(0.0, 0.55, ze + e * 0.5), Vector3(0.3, 0.2, e).normalized())
		_coupler(b, ze, e, 0.87)
		# Steps at the four corners: three treads, yellow edged.
		for sx: float in [-1.0, 1.0]:
			_paint(b, Color(0.12, 0.12, 0.12), P_STEEL, 0.7)
			for k in 3:
				var y := 0.42 + float(k) * 0.42
				b.box(Vector3(sx * 1.25 - 0.3, y - 0.03, ze - e * 0.95 - 0.33), Vector3(sx * 1.25 + 0.3, y + 0.03, ze - e * 0.95 + 0.33))
				_paint(b, SAFETY, P_SAFETY, 0.8)
				b.box(Vector3(sx * 1.25 - 0.3, y + 0.03, ze - e * 0.95 - 0.33 + (0.6 if e < 0.0 else 0.0)), Vector3(sx * 1.25 + 0.3, y + 0.04, ze - e * 0.95 - 0.27 + (0.6 if e < 0.0 else 0.0)))
				_paint(b, Color(0.12, 0.12, 0.12), P_STEEL, 0.7)
			if lv == 0:
				# Ditch lights at the front pilot corners; the rear's reflector.
				if e < 0.0:
					_paint(b, Color(0.1, 0.1, 0.1), P_STEEL, 0.8)
					b.box(Vector3(sx * 1.2 - 0.12, deck + 0.02, ze - 0.05), Vector3(sx * 1.2 + 0.12, deck + 0.26, ze + 0.12))
					_paint(b, Color(1.0, 0.96, 0.85), P_DITCH, 1.0)
					b.cyl(Vector3(sx * 1.2, deck + 0.14, ze - 0.02), Vector3(sx * 1.2, deck + 0.14, ze - 0.07), 0.09, 10, true)
				# Handrail stanchions and the rail along the end platform.
				_paint(b, SAFETY, P_SAFETY, 1.0)
				b.beam(Vector3(sx * 1.48, deck, ze - e * 0.15), Vector3(sx * 1.48, deck + 1.05, ze - e * 0.15), 0.045, 0.045)
	# Handrails along the walkways (near level).
	if lv == 0:
		_paint(b, SAFETY, P_SAFETY, 1.0)
		for sx: float in [-1.0, 1.0]:
			var z := -5.4
			while z <= 9.9:
				b.beam(Vector3(sx * 1.5, deck, z), Vector3(sx * 1.5, deck + 1.0, z), 0.04, 0.04)
				z += 1.7
			b.beam(Vector3(sx * 1.5, deck + 1.0, -5.4), Vector3(sx * 1.5, deck + 1.0, 9.9), 0.035, 0.035)
			b.beam(Vector3(sx * 1.5, deck + 0.55, -5.4), Vector3(sx * 1.5, deck + 0.55, 9.9), 0.03, 0.03)
		# Across both ends.
		for e: float in [-1.0, 1.0]:
			b.beam(Vector3(-1.48, deck + 1.0, e * (hl - 0.15)), Vector3(1.48, deck + 1.0, e * (hl - 0.15)), 0.035, 0.035)
	# Trucks.
	for e: float in [-1.0, 1.0]:
		_loco_truck(b, e * float(FreightRail.TRUCK_HALF[FreightRail.Car.LOCO]), lv)
	# Fuel tank between the trucks.
	_paint(b, FRAME, P_FIXED, 0.55)
	b.box(Vector3(-1.32, 0.62, -3.9), Vector3(1.32, 1.25, 3.9))
	b.box(Vector3(-1.1, 0.42, -3.7), Vector3(1.1, 0.62, 3.7))
	if lv == 0:
		_paint(b, Color(0.82, 0.82, 0.8), P_FIXED, 0.8)
		for sx: float in [-1.0, 1.0]:
			b.cyl(Vector3(sx * 1.32, 1.05, -1.0), Vector3(sx * 1.36, 1.05, -1.0), 0.09, 8, true)
		# Air reservoirs under the frame, behind the tank.
		_paint(b, Color(0.1, 0.1, 0.1), P_STEEL, 0.5)
		for e: float in [-1.0, 1.0]:
			b.cyl(Vector3(-0.9, 1.1, e * 4.6), Vector3(0.9, 1.1, e * 4.6), 0.22, 10, true)

	# The nose (short hood) and the cab.
	var cab0 := -8.55
	var cab1 := -5.55
	_paint(b, LOCO_RED, P_FIXED, 1.0)
	# Nose: its sides, its top sloping down to the front, its front face.
	var nz0 := -hl + 0.2
	b.box(Vector3(-1.2, deck, nz0), Vector3(1.2, 2.95, cab0), 1 | 2 | 32)
	b.quad(Vector3(-1.2, 2.95, nz0), Vector3(1.2, 2.95, nz0), Vector3(1.2, 3.35, cab0), Vector3(-1.2, 3.35, cab0), Vector3(0, 1, -0.3).normalized())
	b.quad(Vector3(-1.2, 2.95, nz0), Vector3(-1.2, 3.35, cab0), Vector3(-1.2, 2.95, cab0), Vector3(-1.2, 2.95, nz0), Vector3.LEFT)
	b.quad(Vector3(1.2, 2.95, nz0), Vector3(1.2, 2.95, cab0), Vector3(1.2, 3.35, cab0), Vector3(1.2, 2.95, nz0), Vector3.RIGHT)
	# The sand chevron on the nose front and the door in it.
	_paint(b, LOCO_SAND, P_FIXED, 1.0)
	for sx: float in [-1.0, 1.0]:
		b.quad(Vector3(sx * 0.0, 1.95, nz0 - 0.012), Vector3(sx * 1.2, 2.55, nz0 - 0.012), Vector3(sx * 1.2, 2.85, nz0 - 0.012), Vector3(sx * 0.0, 2.25, nz0 - 0.012), Vector3.FORWARD)
	_paint(b, Color(0.2, 0.06, 0.04), P_FIXED, 0.8)
	b.box(Vector3(-0.32, deck + 0.05, nz0 - 0.02), Vector3(0.32, 2.5, nz0 + 0.01), 32)
	if lv == 0:
		_paint(b, Color(0.7, 0.7, 0.68), P_STEEL, 0.9)
		b.box(Vector3(0.2, 1.95, nz0 - 0.05), Vector3(0.26, 2.15, nz0 - 0.01), 32 | 1 | 2)
	# Headlights in a black housing on the nose face, over the door.
	_paint(b, Color(0.06, 0.06, 0.06), P_STEEL, 0.9)
	b.box(Vector3(-0.42, 2.56, nz0 - 0.08), Vector3(0.42, 2.9, nz0))
	_paint(b, Color(1.0, 0.97, 0.88), P_HEAD, 1.0)
	for sx: float in [-0.2, 0.2]:
		b.cyl(Vector3(sx, 2.73, nz0 - 0.08), Vector3(sx, 2.73, nz0 - 0.11), 0.11, 14, true)
	# The cab box.
	_paint(b, LOCO_RED, P_FIXED, 1.0)
	b.box(Vector3(-1.55, deck, cab0), Vector3(1.55, 4.55, cab1), 1 | 2 | 16)
	b.quad(Vector3(-1.55, 3.35, cab0), Vector3(1.55, 3.35, cab0), Vector3(1.55, 2.95, cab0), Vector3(-1.55, 2.95, cab0), Vector3.FORWARD)
	b.box(Vector3(-1.55, deck, cab0), Vector3(-1.2, 2.95, cab0 + 0.01), 32)
	b.box(Vector3(1.2, deck, cab0), Vector3(1.55, 2.95, cab0 + 0.01), 32)
	# The windscreen wall (leaning back), two panes and the post between.
	var wz0 := cab0
	var wz1 := cab0 + 0.22
	_paint(b, LOCO_RED, P_FIXED, 1.0)
	b.quad(Vector3(-1.55, 3.35, wz0), Vector3(1.55, 3.35, wz0), Vector3(1.55, 4.55, wz1), Vector3(-1.55, 4.55, wz1), Vector3(0, 0.18, -1).normalized())
	_paint(b, Color(0.05, 0.06, 0.07), P_GLASS, 1.0)
	for sx: float in [-1.0, 1.0]:
		var x0 := sx * 0.08
		var x1 := sx * 1.32
		b.quad(Vector3(x0, 3.5, wz0 + 0.03 - 0.012), Vector3(x1, 3.5, wz0 + 0.03 - 0.012), Vector3(x1, 4.3, wz0 + 0.17 - 0.012), Vector3(x0, 4.3, wz0 + 0.17 - 0.012), Vector3(0, 0.18, -1).normalized())
	# Cab roof, a little arched.
	_paint(b, LOCO_ROOF, P_FIXED, 1.0)
	b.quad(Vector3(-1.55, 4.55, wz1), Vector3(0.0, 4.72, wz1), Vector3(0.0, 4.72, cab1), Vector3(-1.55, 4.55, cab1), Vector3(-0.1, 1, 0).normalized())
	b.quad(Vector3(0.0, 4.72, wz1), Vector3(1.55, 4.55, wz1), Vector3(1.55, 4.55, cab1), Vector3(0.0, 4.72, cab1), Vector3(0.1, 1, 0).normalized())
	b.quad(Vector3(-1.55, 4.55, wz1), Vector3(1.55, 4.55, wz1), Vector3(0.0, 4.72, wz1), Vector3(-1.55, 4.55, wz1), Vector3.FORWARD)
	b.quad(Vector3(-1.55, 4.55, cab1), Vector3(0.0, 4.72, cab1), Vector3(1.55, 4.55, cab1), Vector3(-1.55, 4.55, cab1), Vector3.BACK)
	# Side windows (sliding and fixed), the cab doors are at the back of the cab on the walkway.
	_paint(b, Color(0.05, 0.06, 0.07), P_GLASS, 1.0)
	for sx: float in [-1.0, 1.0]:
		var x := sx * 1.562
		b.quad(Vector3(x, 3.4, cab0 + 0.35), Vector3(x, 3.4, cab0 + 1.35), Vector3(x, 4.25, cab0 + 1.35), Vector3(x, 4.25, cab0 + 0.35), Vector3(sx, 0, 0))
		b.quad(Vector3(x, 3.4, cab0 + 1.5), Vector3(x, 3.4, cab0 + 2.45), Vector3(x, 4.25, cab0 + 2.45), Vector3(x, 4.25, cab0 + 1.5), Vector3(sx, 0, 0))
		if lv == 0:
			# Mirrors on arms by the front windows.
			_paint(b, Color(0.08, 0.08, 0.08), P_STEEL, 0.9)
			b.box(Vector3(x + sx * 0.02, 3.95, cab0 + 0.25), Vector3(x + sx * 0.28, 4.2, cab0 + 0.3))
			_paint(b, Color(0.05, 0.06, 0.07), P_GLASS, 1.0)
		# The road number on the cab side (the shader's digits).
		_number_field(b, Vector3(x, 2.65, cab0 + 1.5), Vector3(0, 0, -sx), Vector3(sx, 0, 0), 1.6, 0.42, LOCO_SAND)
	# Number boards on the cab front corners, lit.
	for sx: float in [-1.0, 1.0]:
		_paint(b, Color(0.08, 0.08, 0.08), P_STEEL, 0.9)
		b.box(Vector3(sx * 1.2 - 0.28, 4.32, wz1 - 0.06), Vector3(sx * 1.2 + 0.28, 4.52, wz1 + 0.04))
		_number_field(b, Vector3(sx * 1.2, 4.42, wz1 - 0.06), Vector3(-1, 0, 0), Vector3(0, 0, -1), 0.5, 0.16, Color(0.95, 0.95, 0.9))
	# Horn and antennas on the cab roof.
	if lv == 0:
		_paint(b, Color(0.12, 0.12, 0.12), P_STEEL, 0.9)
		b.box(Vector3(-0.1, 4.72, cab0 + 1.8), Vector3(0.1, 4.82, cab0 + 2.0))
		for k in 3:
			b.cyl(Vector3(-0.15 + float(k) * 0.15, 4.85, cab0 + 1.9), Vector3(-0.15 + float(k) * 0.15, 4.85, cab0 + 1.9 - 0.25 - 0.08 * float(k)), 0.045, 6, true, 0.075)
		b.cyl(Vector3(0.7, 4.65, cab1 - 0.5), Vector3(0.7, 5.05, cab1 - 0.5), 0.02, 4)

	# The long hood: from the cab back to the radiators.
	var h0 := cab1
	var rad0 := 6.4
	var h1 := hl - 0.25
	var hw := 1.18
	var top := 4.42
	_paint(b, LOCO_RED, P_FIXED, 1.0)
	b.box(Vector3(-hw, deck, h0), Vector3(hw, top - 0.15, rad0), 1 | 2)
	# The hood's rounded top edge (a chamfer) and roof.
	for sx: float in [-1.0, 1.0]:
		b.quad(Vector3(sx * hw, top - 0.15, h0), Vector3(sx * (hw - 0.15), top, h0), Vector3(sx * (hw - 0.15), top, rad0), Vector3(sx * hw, top - 0.15, rad0), Vector3(sx, 1, 0).normalized())
	_paint(b, LOCO_ROOF, P_FIXED, 1.0)
	b.quad(Vector3(-hw + 0.15, top, h0), Vector3(hw - 0.15, top, h0), Vector3(hw - 0.15, top, rad0), Vector3(-hw + 0.15, top, rad0), Vector3.UP)
	# The sand band along the hood, the railroad's name in red on it.
	_paint(b, LOCO_SAND, P_FIXED, 1.0)
	for sx: float in [-1.0, 1.0]:
		var x := sx * (hw + 0.006)
		b.quad(Vector3(x, 2.55, h0 + 0.3), Vector3(x, 2.55, rad0), Vector3(x, 3.35, rad0), Vector3(x, 3.35, h0 + 0.3), Vector3(sx, 0, 0))
		_letters(b, FreightRail.RAILROAD, 0.5, Vector3(x, 2.95, (h0 + rad0) * 0.5 + 0.4), Vector3(0, 0, -sx), Vector3(sx, 0, 0), LOCO_RED)
		# Access doors along the hood: a dark seam between each pair, a latch on each.
		if lv == 0:
			var z := h0 + 0.6
			while z < rad0 - 0.5:
				_paint(b, Color(0.08, 0.03, 0.02), P_FIXED, 0.8)
				b.quad(Vector3(x + sx * 0.008, deck + 0.12, z - 0.015), Vector3(x + sx * 0.008, deck + 0.12, z + 0.015), Vector3(x + sx * 0.008, 2.5, z + 0.015), Vector3(x + sx * 0.008, 2.5, z - 0.015), Vector3(sx, 0, 0))
				_paint(b, Color(0.12, 0.12, 0.12), P_STEEL, 0.9)
				b.box(Vector3(x - 0.02, 1.95, z + 0.45), Vector3(x + 0.02, 2.02, z + 0.62), 1 | 2 | 4)
				z += 1.1
			_paint(b, LOCO_SAND, P_FIXED, 1.0)
		# Air intake louvres behind the cab.
		_paint(b, Color(0.05, 0.05, 0.05), P_GRILLE, 0.8)
		b.quad(Vector3(x + sx * 0.008, 3.45, h0 + 0.3), Vector3(x + sx * 0.008, 3.45, h0 + 2.2), Vector3(x + sx * 0.008, 4.15, h0 + 2.2), Vector3(x + sx * 0.008, 4.15, h0 + 0.3), Vector3(sx, 0, 0))
		_paint(b, LOCO_SAND, P_FIXED, 1.0)
	# The dynamic brake blister: a hump over the hood with grilles on its sides.
	_paint(b, LOCO_RED, P_FIXED, 1.0)
	b.box(Vector3(-hw + 0.1, top, -3.6), Vector3(hw - 0.1, top + 0.32, -0.9), 4 | 16 | 32)
	_paint(b, Color(0.06, 0.06, 0.06), P_GRILLE, 0.85)
	for sx: float in [-1.0, 1.0]:
		b.quad(Vector3(sx * (hw - 0.1), top, -3.5), Vector3(sx * (hw - 0.1), top, -1.0), Vector3(sx * (hw - 0.1), top + 0.3, -1.0), Vector3(sx * (hw - 0.1), top + 0.3, -3.5), Vector3(sx, 0, 0))
	b.quad(Vector3(-0.8, top + 0.321, -3.3), Vector3(0.8, top + 0.321, -3.3), Vector3(0.8, top + 0.321, -1.2), Vector3(-0.8, top + 0.321, -1.2), Vector3.UP)
	# Exhaust stacks.
	_paint(b, Color(0.05, 0.05, 0.05), P_STEEL, 0.6)
	for k in 2:
		b.box(Vector3(-0.25, top, 1.0 + float(k) * 0.8), Vector3(0.25, top + 0.18, 1.5 + float(k) * 0.8))
	# The radiator section: wider, taller, angled radiator wings, fans on top.
	_paint(b, LOCO_RED, P_FIXED, 1.0)
	var rw := 1.5
	var rt := 4.62
	b.box(Vector3(-rw, deck, rad0), Vector3(rw, 3.3, h1), 1 | 2 | 16 | 32)
	b.box(Vector3(-hw, 3.3, rad0), Vector3(hw, rt, h1), 16 | 32)
	for sx: float in [-1.0, 1.0]:
		# The radiator wing: a red frame round a dark grille, angled in toward the roof.
		_paint(b, LOCO_RED, P_FIXED, 1.0)
		b.quad(Vector3(sx * rw, 3.3, rad0), Vector3(sx * rw, 3.3, h1), Vector3(sx * hw, rt, h1), Vector3(sx * hw, rt, rad0), Vector3(sx, 0.5, 0).normalized())
		_paint(b, Color(0.17, 0.17, 0.17), P_GRILLE, 0.85)
		var o := Vector3(sx, 0.5, 0).normalized() * 0.012
		var f := 0.12
		b.quad(Vector3(sx * lerpf(rw, hw, f), lerpf(3.3, rt, f), rad0 + 0.2) + o, Vector3(sx * lerpf(rw, hw, f), lerpf(3.3, rt, f), h1 - 0.2) + o,
			Vector3(sx * lerpf(rw, hw, 1.0 - f), lerpf(3.3, rt, 1.0 - f), h1 - 0.2) + o, Vector3(sx * lerpf(rw, hw, 1.0 - f), lerpf(3.3, rt, 1.0 - f), rad0 + 0.2) + o, Vector3(sx, 0.5, 0).normalized())
	_paint(b, LOCO_ROOF, P_FIXED, 1.0)
	b.quad(Vector3(-hw, rt, rad0), Vector3(hw, rt, rad0), Vector3(hw, rt, h1), Vector3(-hw, rt, h1), Vector3.UP)
	_paint(b, Color(0.05, 0.05, 0.05), P_GRILLE, 0.9)
	for k in 2:
		var zc := rad0 + 1.1 + float(k) * 1.75
		b.cyl(Vector3(0, rt, zc), Vector3(0, rt + 0.05, zc), 0.78, 16 if lv == 0 else 8, true)
	# The rear: end wall, number boards, headlight, a ladder up the radiators.
	_paint(b, LOCO_RED, P_FIXED, 1.0)
	b.quad(Vector3(-rw, deck, h1), Vector3(rw, deck, h1), Vector3(rw, 3.3, h1), Vector3(-rw, 3.3, h1), Vector3.BACK)
	b.quad(Vector3(-hw, 3.3, h1), Vector3(hw, 3.3, h1), Vector3(hw, rt, h1), Vector3(-hw, rt, h1), Vector3.BACK)
	_paint(b, Color(1.0, 0.97, 0.88), P_REAR, 1.0)
	for sx: float in [-0.18, 0.18]:
		b.cyl(Vector3(sx, 4.25, h1), Vector3(sx, 4.25, h1 + 0.04), 0.09, 12, true)
	for sx: float in [-1.0, 1.0]:
		_number_field(b, Vector3(sx * 0.8, 4.3, h1 + 0.01), Vector3(1, 0, 0), Vector3(0, 0, 1), 0.5, 0.16, Color(0.95, 0.95, 0.9))
	if lv == 0:
		_ladder(b, Vector3(1.0, 0.0, h1), Vector3(0, 0, 1), Vector3(1, 0, 0), deck, 6, SAFETY)
		for sx: float in [-1.0, 1.0]:
			_tape(b, Vector3(sx * 1.4, 1.4, -hl - 0.01), Vector3(0, 0, -1), Vector3(1, 0, 0))
			_tape(b, Vector3(sx * 1.4, 1.4, hl + 0.01), Vector3(0, 0, 1), Vector3(1, 0, 0))


## The locomotive's three-axle truck centred at z: a cast side frame with its spring pockets,
## three wheelsets, a traction motor over each axle, brake cylinders, sand boxes.
static func _loco_truck(b: PortKit.Buf, z: float, lv: int) -> void:
	var r := 0.53
	var wb := 1.95
	_paint(b, TRUCK, P_STEEL, 0.6)
	for sx: float in [-1.0, 1.0]:
		var x := sx * 1.08
		b.box(Vector3(x - 0.1, 0.62, z - 2.75), Vector3(x + 0.1, 1.05, z + 2.75))
		for k in 3:
			var az := z + float(k - 1) * wb
			# Pedestals down round each axle box, the box itself.
			b.box(Vector3(x - 0.11, 0.36, az - 0.32), Vector3(x + 0.11, 0.66, az + 0.32))
			_paint(b, Color(0.14, 0.13, 0.12), P_STEEL, 0.6)
			b.cyl(Vector3(x - 0.12, r, az), Vector3(x + sx * 0.18, r, az), 0.15, 8, true)
			_paint(b, TRUCK, P_STEEL, 0.6)
		if lv == 0:
			# Coil springs between the frame and the boxes, brake cylinders between the wheels.
			_paint(b, Color(0.12, 0.11, 0.1), P_STEEL, 0.5)
			for k in 3:
				var az := z + float(k - 1) * wb
				for e: float in [-0.22, 0.22]:
					b.cyl(Vector3(x, 0.66, az + e), Vector3(x, 0.98, az + e), 0.09, 8)
			_paint(b, Color(0.1, 0.1, 0.1), P_STEEL, 0.6)
			for k in 2:
				var bz := z + (float(k) - 0.5) * wb
				b.cyl(Vector3(x, 0.92, bz), Vector3(x + sx * 0.35, 0.92, bz), 0.12, 8, true)
			# Sand box at the outer end.
			_paint(b, TRUCK, P_STEEL, 0.6)
			b.box(Vector3(x - 0.15, 0.8, z - 2.75 - 0.35), Vector3(x + 0.15, 1.15, z - 2.75))
			b.box(Vector3(x - 0.15, 0.8, z + 2.75), Vector3(x + 0.15, 1.15, z + 2.75 + 0.35))
			_paint(b, TRUCK, P_STEEL, 0.6)
	# Traction motors over the axles (dark masses between the wheels), the bolster.
	_paint(b, Color(0.08, 0.08, 0.08), P_STEEL, 0.4)
	for k in 3:
		var az := z + float(k - 1) * wb
		b.box(Vector3(-0.55, 0.3, az - 0.5), Vector3(0.55, 1.05, az + 0.3))
	b.box(Vector3(-1.05, 1.0, z - 0.4), Vector3(1.05, 1.22, z + 0.4))
	for k in 3:
		_wheelset_big(b, z + float(k - 1) * wb, r, lv)


static func _wheelset_big(b: PortKit.Buf, z: float, r: float, lv: int) -> void:
	var sides := 18 if lv == 0 else 10
	for sx: float in [-1.0, 1.0]:
		_paint(b, Color(0.30, 0.28, 0.26), P_WHEEL, 0.7)
		b.cyl(Vector3(sx * 0.66, r, z), Vector3(sx * 0.80, r, z), r, sides, true)
		_paint(b, Color(0.2, 0.19, 0.18), P_WHEEL, 0.6)
		b.cyl(Vector3(sx * 0.645, r, z), Vector3(sx * 0.66, r, z), r + 0.025, sides, false)
	_paint(b, Color(0.2, 0.19, 0.18), P_STEEL, 0.5)
	b.cyl(Vector3(-0.8, r, z), Vector3(0.8, r, z), 0.1, 6)


# --- The cars --------------------------------------------------------------------------------------

## Reporting marks and capacity stencils on both sides of a car, at height y.
static func _marks(b: PortKit.Buf, hw: float, y: float, z: float, h: float) -> void:
	for sx: float in [-1.0, 1.0]:
		var x := sx * (hw + 0.006)
		_letters(b, FreightRail.MARK, h, Vector3(x, y, z), Vector3(0, 0, -sx), Vector3(sx, 0, 0), Color(0.92, 0.92, 0.88))
		_number_field(b, Vector3(x, y - h * 1.35, z), Vector3(0, 0, -sx), Vector3(sx, 0, 0), h * 3.6, h * 0.95, Color(0.92, 0.92, 0.88))


## End sills, couplers, brake wheel and the trucks of a car with trucks at +-th and its ends at
## +-hl, the underframe's deck at `deck`.
static func _car_base(b: PortKit.Buf, hl: float, th: float, deck: float, lv: int) -> void:
	_paint(b, Color(0.1, 0.095, 0.09), P_STEEL, 0.55)
	# Centre sill under the car, end sills.
	b.box(Vector3(-0.3, deck - 0.45, -hl + 0.2), Vector3(0.3, deck - 0.05, hl - 0.2))
	for e: float in [-1.0, 1.0]:
		b.box(Vector3(-1.45, deck - 0.3, e * hl - 0.15), Vector3(1.45, deck, e * hl + 0.15))
		_coupler(b, e * hl, e, 0.87)
		_truck(b, e * th, lv)
		if lv == 0:
			# Sill steps and grab irons at the corners.
			_paint(b, Color(0.1, 0.095, 0.09), P_STEEL, 0.6)
			for sx: float in [-1.0, 1.0]:
				b.beam(Vector3(sx * 1.42, deck - 0.3, e * (hl - 0.35)), Vector3(sx * 1.42, deck - 0.75, e * (hl - 0.35)), 0.04, 0.04)
				b.beam(Vector3(sx * 1.42, deck - 0.75, e * (hl - 0.55)), Vector3(sx * 1.42, deck - 0.75, e * (hl - 0.15)), 0.04, 0.04)


## The 53 ft single well car: two deep side girders with the well between (its floor 0.35 m over
## the rails, the containers sit in it), bulkheads over the trucks.
static func _well(b: PortKit.Buf, lv: int) -> void:
	var hl := 10.65
	var th := float(FreightRail.TRUCK_HALF[FreightRail.Car.WELL])
	var hw := 1.42
	for sx: float in [-1.0, 1.0]:
		_paint(b, WHITE, P_PAINT, 1.0)
		var x := sx * hw
		# The side girder: deep between the trucks (its bottom low in the well), its top a rail.
		b.box(Vector3(x - (0.0 if sx > 0.0 else 0.12), 0.32, -hl + 2.8), Vector3(x + (0.12 if sx > 0.0 else 0.0), 1.55, hl - 2.8))
		b.box(Vector3(x - (0.0 if sx > 0.0 else 0.12), 1.0, -hl), Vector3(x + (0.12 if sx > 0.0 else 0.0), 1.6, hl))
		# Stiffeners down the girder.
		if lv == 0:
			var z := -hl + 3.2
			while z < hl - 3.0:
				b.box(Vector3(x + sx * 0.12 - 0.03, 0.4, z - 0.05), Vector3(x + sx * 0.12 + 0.03, 1.5, z + 0.05))
				z += 1.4
		_tape(b, Vector3(x + sx * 0.13, 1.35, -4.0), Vector3(sx, 0, 0), Vector3(0, 0, 1))
		_tape(b, Vector3(x + sx * 0.13, 1.35, 4.0), Vector3(sx, 0, 0), Vector3(0, 0, 1))
	# The well floor (cross bearers) and the ends over the trucks.
	_paint(b, Color(0.12, 0.11, 0.1), P_STEEL, 0.4)
	var z2 := -hl + 2.9
	while z2 < hl - 2.8:
		b.box(Vector3(-hw, 0.3, z2), Vector3(hw, 0.38, z2 + 0.3))
		z2 += 1.25
	_paint(b, WHITE, P_PAINT, 1.0)
	for e: float in [-1.0, 1.0]:
		var za := e * hl
		var zb := e * (hl - 2.8)
		b.box(Vector3(-hw, 1.0, minf(za, zb)), Vector3(hw, 1.6, maxf(za, zb)))
		# A low bulkhead at the well's end.
		b.box(Vector3(-hw, 1.6, e * (hl - 2.8) - 0.12), Vector3(hw, 2.1, e * (hl - 2.8) + 0.12))
	_car_base(b, hl, th, 1.0, lv)
	_marks(b, hw + 0.12, 1.33, -6.0, 0.18)


## The tank car: a 3 m barrel with dished heads, its walkway platform and manway on top, a
## ladder each side, the stub sills over the trucks.
static func _tank(b: PortKit.Buf, lv: int) -> void:
	var hl := 8.8
	var th := float(FreightRail.TRUCK_HALF[FreightRail.Car.TANK])
	var r := 1.5
	var cy := 2.75
	var sides := 22 if lv == 0 else 12
	_paint(b, WHITE, P_TANK, 1.0)
	b.cyl(Vector3(0, cy, -hl + 1.0), Vector3(0, cy, hl - 1.0), r, sides)
	# Dished heads: a short cone and a cap each end.
	for e: float in [-1.0, 1.0]:
		b.cyl(Vector3(0, cy, e * (hl - 1.0)), Vector3(0, cy, e * (hl - 0.55)), r, sides, false, r * 0.82)
		b.cyl(Vector3(0, cy, e * (hl - 0.55)), Vector3(0, cy, e * (hl - 0.42)), r * 0.82, sides, true, r * 0.5)
	# Stub sills and the bolsters under the barrel.
	_paint(b, Color(0.1, 0.095, 0.09), P_STEEL, 0.5)
	for e: float in [-1.0, 1.0]:
		b.box(Vector3(-0.35, 0.95, e * th - 1.0), Vector3(0.35, 1.4, e * (hl + 0.0)))
		b.box(Vector3(-1.2, 1.15, e * th - 0.25), Vector3(1.2, 1.45, e * th + 0.25))
	# Manway, platform and its railing on top; a ladder up each side.
	_paint(b, Color(0.12, 0.12, 0.12), P_STEEL, 0.9)
	b.cyl(Vector3(0, cy + r - 0.05, 0), Vector3(0, cy + r + 0.35, 0), 0.38, 12 if lv == 0 else 8, true)
	b.box(Vector3(-1.0, cy + r - 0.02, -0.9), Vector3(1.0, cy + r + 0.03, 0.9))
	if lv == 0:
		_paint(b, SAFETY, P_SAFETY, 1.0)
		for sx: float in [-1.0, 1.0]:
			for ez: float in [-0.85, 0.85]:
				b.beam(Vector3(sx * 0.95, cy + r, ez), Vector3(sx * 0.95, cy + r + 0.9, ez), 0.035, 0.035)
			b.beam(Vector3(sx * 0.95, cy + r + 0.9, -0.85), Vector3(sx * 0.95, cy + r + 0.9, 0.85), 0.03, 0.03)
			_ladder(b, Vector3(sx * (r + 0.05), 0.0, 0.0), Vector3(sx, 0, 0), Vector3(0, 0, 1), 1.0, 6, SAFETY)
		# The safety stencil band and the hazmat placard frames at the ends.
		_paint(b, Color(0.9, 0.9, 0.88), P_FIXED, 1.0)
		for e: float in [-1.0, 1.0]:
			b.box(Vector3(-0.3, 1.45, e * (hl - 0.2) - 0.02), Vector3(0.3, 1.85, e * (hl - 0.2) + 0.02))
	_car_base(b, hl, th, 1.25, lv)
	_marks(b, r, 2.2, -4.5, 0.2)


## The 60 ft high-cube boxcar: posts and a fluted roof, a 12 ft sliding door with its tracks, end
## ribs, ladders at the corners.
static func _boxcar(b: PortKit.Buf, lv: int) -> void:
	var hl := 9.35
	var th := float(FreightRail.TRUCK_HALF[FreightRail.Car.BOX])
	var hw := 1.6
	var floor_y := 1.25
	var top := 5.1
	_paint(b, WHITE, P_PAINT, 1.0)
	b.box(Vector3(-hw, floor_y, -hl + 0.15), Vector3(hw, top - 0.12, hl - 0.15), 1 | 2 | 16 | 32)
	# Roof: a low gable with its eaves.
	b.quad(Vector3(-hw, top - 0.12, -hl + 0.15), Vector3(0.0, top, -hl + 0.15), Vector3(0.0, top, hl - 0.15), Vector3(-hw, top - 0.12, hl - 0.15), Vector3(-0.07, 1, 0).normalized())
	b.quad(Vector3(0.0, top, -hl + 0.15), Vector3(hw, top - 0.12, -hl + 0.15), Vector3(hw, top - 0.12, hl - 0.15), Vector3(0.0, top, hl - 0.15), Vector3(0.07, 1, 0).normalized())
	for e: float in [-1.0, 1.0]:
		b.quad(Vector3(-hw, top - 0.12, e * (hl - 0.15)), Vector3(0.0, top, e * (hl - 0.15)), Vector3(hw, top - 0.12, e * (hl - 0.15)), Vector3(-hw, top - 0.12, e * (hl - 0.15)), Vector3(0, 0, e))
	# Exterior posts down the sides (not over the door), the side sill, the roof's flutes.
	for sx: float in [-1.0, 1.0]:
		var x := sx * hw
		var z := -hl + 0.7
		while z < hl - 0.5:
			if absf(z) > 2.2:
				b.box(Vector3(x - (0.07 if sx < 0.0 else 0.0), floor_y + 0.15, z - 0.06), Vector3(x + (0.07 if sx > 0.0 else 0.0), top - 0.2, z + 0.06), 1 | 2 | 16 | 32)
			z += 0.98 if lv == 0 else 1.96
		b.box(Vector3(x - (0.09 if sx < 0.0 else 0.0), floor_y - 0.05, -hl + 0.15), Vector3(x + (0.09 if sx > 0.0 else 0.0), floor_y + 0.15, hl - 0.15))
		# The sliding door (12 ft) and its top and bottom tracks.
		var dx := x + sx * 0.08
		b.box(Vector3(dx - (0.06 if sx < 0.0 else 0.0), floor_y + 0.1, -1.85), Vector3(dx + (0.06 if sx > 0.0 else 0.0), top - 0.3, 1.85))
		_paint(b, Color(0.1, 0.1, 0.1), P_STEEL, 0.8)
		b.box(Vector3(dx - (0.1 if sx < 0.0 else 0.0), top - 0.32, -2.2), Vector3(dx + (0.1 if sx > 0.0 else 0.0), top - 0.22, 4.0))
		b.box(Vector3(dx - (0.1 if sx < 0.0 else 0.0), floor_y + 0.05, -2.2), Vector3(dx + (0.1 if sx > 0.0 else 0.0), floor_y + 0.15, 4.0))
		if lv == 0:
			# Door handles and locking bars.
			for k in 2:
				b.beam(Vector3(dx + sx * 0.08, floor_y + 0.8, -1.4 + float(k) * 2.6), Vector3(dx + sx * 0.08, top - 0.8, -1.4 + float(k) * 2.6), 0.04, 0.04)
		_tape(b, Vector3(x + sx * 0.08, floor_y + 0.45, -6.0), Vector3(sx, 0, 0), Vector3(0, 0, 1))
		_tape(b, Vector3(x + sx * 0.08, floor_y + 0.45, 6.0), Vector3(sx, 0, 0), Vector3(0, 0, 1))
		_paint(b, WHITE, P_PAINT, 1.0)
	if lv == 0:
		# End ribs and the ladders up the corners.
		for e: float in [-1.0, 1.0]:
			for k in 6:
				var y := floor_y + 0.4 + float(k) * 0.6
				b.box(Vector3(-hw + 0.1, y - 0.05, e * (hl - 0.15) - (0.0 if e > 0.0 else 0.05)), Vector3(hw - 0.1, y + 0.05, e * (hl - 0.15) + (0.05 if e > 0.0 else 0.0)))
			_ladder(b, Vector3(-hw + 0.35, 0.0, e * (hl - 0.15)), Vector3(0, 0, e), Vector3(1, 0, 0), floor_y + 0.2, 8, WHITE)
			_paint(b, Color(0.1, 0.1, 0.1), P_STEEL, 0.8)
			# The brake wheel on its staff at the B end.
			if e < 0.0:
				b.cyl(Vector3(hw - 0.5, floor_y + 2.8, -hl - 0.05), Vector3(hw - 0.5, floor_y + 2.8, -hl - 0.12), 0.3, 12, true)
			_paint(b, WHITE, P_PAINT, 1.0)
	_car_base(b, hl, th, floor_y, lv)
	_marks(b, hw + 0.08, top - 1.0, -6.4, 0.22)


## The three-bay covered hopper: slope-sided body over three discharge hoppers, a trough hatch
## down the roof, sloped end sheets with a platform each end.
static func _hopper(b: PortKit.Buf, lv: int) -> void:
	var hl := 8.8
	var th := float(FreightRail.TRUCK_HALF[FreightRail.Car.HOPPER])
	var hw := 1.6
	var top := 4.55
	var belt := 2.4
	_paint(b, WHITE, P_PAINT, 1.0)
	# Upper body: straight sides, the roof.
	b.box(Vector3(-hw, belt, -hl + 1.2), Vector3(hw, top, hl - 1.2), 1 | 2 | 4)
	# The sloped end sheets down to the end platforms.
	for e: float in [-1.0, 1.0]:
		var z0 := e * (hl - 1.2)
		var z1 := e * (hl - 0.3)
		b.quad(Vector3(-hw, top, z0), Vector3(hw, top, z0), Vector3(hw, 1.7, z1), Vector3(-hw, 1.7, z1), Vector3(0, 0.7, e).normalized())
		for sx: float in [-1.0, 1.0]:
			b.quad(Vector3(sx * hw, top, z0), Vector3(sx * hw, belt, z0), Vector3(sx * hw, 1.7, z1), Vector3(sx * hw, 1.7, z1), Vector3(sx, 0, 0))
			b.quad(Vector3(sx * hw, belt, z0), Vector3(sx * hw, 1.7, z1), Vector3(sx * hw, 1.7, z1), Vector3(sx * hw, belt, z0), Vector3(sx, 0, 0))
	# Three hopper bays: inverted pyramids under the belt, an outlet gate under each.
	for k in 3:
		var zc := (float(k) - 1.0) * 4.6
		var a := Vector3(-hw, belt, zc - 2.2)
		var bb := Vector3(hw, belt, zc - 2.2)
		var c := Vector3(hw, belt, zc + 2.2)
		var d := Vector3(-hw, belt, zc + 2.2)
		var o := 0.95
		var lo := Vector3(-0.45, o, zc - 0.5)
		var lo2 := Vector3(0.45, o, zc - 0.5)
		var lo3 := Vector3(0.45, o, zc + 0.5)
		var lo4 := Vector3(-0.45, o, zc + 0.5)
		b.quad(a, bb, lo2, lo, Vector3(0, -0.5, -1).normalized())
		b.quad(bb, c, lo3, lo2, Vector3(1, -0.5, 0).normalized())
		b.quad(c, d, lo4, lo3, Vector3(0, -0.5, 1).normalized())
		b.quad(d, a, lo, lo4, Vector3(-1, -0.5, 0).normalized())
		_paint(b, Color(0.1, 0.1, 0.1), P_STEEL, 0.6)
		b.box(Vector3(-0.5, 0.75, zc - 0.55), Vector3(0.5, 0.95, zc + 0.55))
		_paint(b, WHITE, P_PAINT, 1.0)
	# Side posts (vertical stiffeners) and the top chord.
	if lv == 0:
		for sx: float in [-1.0, 1.0]:
			var z := -hl + 1.5
			while z < hl - 1.3:
				b.box(Vector3(sx * hw - (0.05 if sx < 0.0 else 0.0), belt - 0.1, z - 0.05), Vector3(sx * hw + (0.05 if sx > 0.0 else 0.0), top - 0.05, z + 0.05), 1 | 2 | 16 | 32)
				z += 1.25
	# The roof's trough hatch.
	_paint(b, Color(0.82, 0.82, 0.8), P_FIXED, 1.0)
	b.box(Vector3(-0.38, top, -hl + 1.4), Vector3(0.38, top + 0.14, hl - 1.4))
	# Centre sill and the trucks.
	_car_base(b, hl, th, 1.2, lv)
	for sx: float in [-1.0, 1.0]:
		_tape(b, Vector3(sx * (hw + 0.01), belt + 0.3, -5.5), Vector3(sx, 0, 0), Vector3(0, 0, 1))
		_tape(b, Vector3(sx * (hw + 0.01), belt + 0.3, 5.5), Vector3(sx, 0, 0), Vector3(0, 0, 1))
		if lv == 0:
			for e: float in [-1.0, 1.0]:
				_ladder(b, Vector3(sx * (hw - 0.45), 0.0, e * (hl - 0.3)), Vector3(0, 0, e), Vector3(1, 0, 0), 1.4, 7, WHITE)
	_marks(b, hw, top - 0.7, -5.0, 0.2)


## The tri-level autorack: a tall flat car carrying a perforated steel enclosure (the shader's
## punched panels), a roof, the end doors.
static func _autorack(b: PortKit.Buf, lv: int) -> void:
	var hl := 13.6
	var th := float(FreightRail.TRUCK_HALF[FreightRail.Car.AUTORACK])
	var hw := 1.6
	var deck := 1.25
	var top := 5.85
	# The flat car's side sill (its paint), then the enclosure.
	_paint(b, Color(0.12, 0.11, 0.1), P_STEEL, 0.7)
	b.box(Vector3(-hw - 0.05, deck - 0.3, -hl + 0.2), Vector3(hw + 0.05, deck + 0.12, hl - 0.2))
	_paint(b, WHITE, P_PERF, 1.0)
	b.box(Vector3(-hw, deck + 0.12, -hl + 0.35), Vector3(hw, top - 0.1, hl - 0.35), 1 | 2)
	_paint(b, WHITE, P_PAINT, 1.0)
	# Posts between the side panels (every 1.9 m), the roof.
	for sx: float in [-1.0, 1.0]:
		var z := -hl + 0.35
		while z <= hl - 0.3:
			b.box(Vector3(sx * hw - (0.08 if sx < 0.0 else 0.0), deck + 0.12, z - 0.06), Vector3(sx * hw + (0.08 if sx > 0.0 else 0.0), top - 0.05, z + 0.06), 1 | 2 | 16 | 32)
			z += 1.9 if lv == 0 else 3.8
		b.box(Vector3(sx * hw - (0.09 if sx < 0.0 else 0.0), top - 0.45, -hl + 0.35), Vector3(sx * hw + (0.09 if sx > 0.0 else 0.0), top - 0.1, hl - 0.35), 1 | 2)
	b.quad(Vector3(-hw - 0.05, top - 0.1, -hl + 0.3), Vector3(0.0, top, -hl + 0.3), Vector3(0.0, top, hl - 0.3), Vector3(-hw - 0.05, top - 0.1, hl - 0.3), Vector3(-0.05, 1, 0).normalized())
	b.quad(Vector3(0.0, top, -hl + 0.3), Vector3(hw + 0.05, top - 0.1, -hl + 0.3), Vector3(hw + 0.05, top - 0.1, hl - 0.3), Vector3(0.0, top, hl - 0.3), Vector3(0.05, 1, 0).normalized())
	# The end doors (two leaves, panelled).
	for e: float in [-1.0, 1.0]:
		b.quad(Vector3(-hw, deck + 0.12, e * (hl - 0.3)), Vector3(hw, deck + 0.12, e * (hl - 0.3)), Vector3(hw, top - 0.1, e * (hl - 0.3)), Vector3(-hw, top - 0.1, e * (hl - 0.3)), Vector3(0, 0, e))
		if lv == 0:
			_paint(b, Color(0.1, 0.1, 0.1), P_STEEL, 0.8)
			b.box(Vector3(-0.03, deck + 0.12, e * (hl - 0.3) - 0.03), Vector3(0.03, top - 0.1, e * (hl - 0.3) + 0.03))
			_paint(b, WHITE, P_PAINT, 1.0)
	_car_base(b, hl, th, deck, lv)
	_marks(b, hw + 0.1, deck + 0.7, -9.0, 0.22)
