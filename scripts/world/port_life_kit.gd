class_name PortLifeKit
extends RefCounted
## The terminal's moving machines and its gate, built in code at real size on PortKit's builder
## (PortKit.Buf) and its steel shader (shaders/port_steel.gdshader: vertex colour, the finish in
## UV2.x - 11 an amber beacon, 12 a head / work lamp, 13 a red tail lamp - and UV in metres).
## PortLife (scripts/world/port_life.gd) runs them; CityChunk builds the gate (PortLife.build_gate).
##
## Every vehicle's frame: +X forward (its direction of travel), +Y up, origin on the ground at its
## centre (a chassis' origin is its centre too, so a box on it sits at CHASSIS_BED).

const B := PortKit.Buf

# --- Straddle carrier (a 1-over-2 machine: 9.6 m long, 4.9 m wide, 14.6 m tall) ---------------
const SC_LEN := 9.6
const SC_HALF_W := 2.45
## Inside clear width between the two side frames (a 2.44 m box with room to spare).
const SC_INNER := 1.55
const SC_TOP := 13.4
## The spreader's underside when it carries a box low for travel, and drawn up empty.
const SC_CARRY_Y := 3.35
const SC_EMPTY_Y := 10.6
const SC_RIDE_Y := 0.9

# --- Terminal tractor (yard truck) and its 40 ft skeletal chassis ----------------------------
const TT_LEN := 5.9
## The fifth wheel's centre ahead of / behind the tractor's centre: the chassis' kingpin rides it.
const TT_FIFTH_X := -1.55
const CHASSIS_LEN := 12.6
## The box sits on the chassis' twist locks at this height (its underside).
const CHASSIS_BED := 1.42
## The chassis' centre behind the kingpin.
const CHASSIS_KINGPIN := 5.3

# --- The gate --------------------------------------------------------------------------------
const GATE_LANE_W := 4.6
const GATE_ISLAND_W := 2.2
const CANOPY_Y := 7.2

const STEEL_EDGES := [0.0, 0.25, 0.9]

static var _cache: Dictionary = {}


static func _mesh(key: String, build: Callable, edges: Array = STEEL_EDGES) -> ArrayMesh:
	if _cache.has(key):
		return _cache[key]
	var levels: Array = []
	for lv in edges.size():
		var b := PortKit.Buf.new()
		build.call(b, lv)
		levels.append(b)
	var mesh := PortKit.ladder(levels, edges, PortKit.steel_material())
	_cache[key] = mesh
	return mesh


## Builds every mesh here (the loading screen; PortKit.warm() calls it).
static func warm() -> void:
	straddle_mesh()
	tractor_mesh()
	chassis_mesh()
	booth_mesh()
	canopy_mesh(PortGate.LANES)
	portal_mesh(PortGate.LANES)
	office_mesh()


## A wheel on the ground at (x, z): tyre with a painted rim, its axis along Z.
static func _wheel(b: B, lv: int, x: float, z: float, r: float, w: float) -> void:
	var sides := 12 if lv == 0 else (8 if lv == 1 else 6)
	b.color = PortKit.BLACK
	b.part = PortKit.S_RUBBER
	b.cyl(Vector3(x, r, z - w * 0.5), Vector3(x, r, z + w * 0.5), r, sides, lv <= 1)
	if lv == 0:
		b.color = PortKit.GREY
		b.part = PortKit.S_PAINT
		var s := 1.0 if z > 0.0 else -1.0
		b.cyl(Vector3(x, r, z + s * w * 0.5), Vector3(x, r, z + s * (w * 0.5 + 0.03)), r * 0.55, 8, true)


# --- Straddle carrier ------------------------------------------------------------------------

static func straddle_mesh() -> ArrayMesh:
	return _mesh("straddle", _straddle)


static func _straddle(b: B, lv: int) -> void:
	var hl := SC_LEN * 0.5
	var zi := SC_INNER
	var zo := SC_HALF_W
	for side: float in [-1.0, 1.0]:
		var z0 := side * zi
		var z1 := side * zo
		var zc := (z0 + z1) * 0.5
		# The sill beam, hazard-striped ends, the wheels under it (four a side, all steered).
		b.color = Color(0.86, 0.86, 0.83)
		b.part = PortKit.S_PAINT
		b.box(Vector3(-hl, 0.95, minf(z0, z1)), Vector3(hl, 1.75, maxf(z0, z1)))
		b.color = PortKit.YELLOW
		b.part = PortKit.S_STRIPE
		for ex: float in [-1.0, 1.0]:
			b.box(Vector3(ex * hl - 0.18, 0.95, minf(z0, z1) - 0.01), Vector3(ex * hl + 0.18, 1.75, maxf(z0, z1) + 0.01))
		for wx: float in [-3.4, -1.15, 1.15, 3.4]:
			_wheel(b, lv, wx, zc, 0.62, 0.42)
		# Two leg frames rising from the sill, braced, to the top beam.
		b.color = Color(0.86, 0.86, 0.83)
		b.part = PortKit.S_PAINT
		for lxs: float in [-1.0, 1.0]:
			var x := lxs * (hl - 0.55)
			b.beam(Vector3(x, 1.75, zc), Vector3(x * 0.96, SC_TOP - 1.2, zc), 0.75, 0.62, 0.62, 0.55, Vector3.BACK, false)
		if lv <= 1:
			b.color = PortKit.GREY
			b.beam(Vector3(-hl + 0.9, 2.2, zc), Vector3(hl - 0.9, SC_TOP - 3.4, zc), 0.22, 0.22, -1.0, -1.0, Vector3.BACK)
			b.beam(Vector3(hl - 0.9, 2.2, zc), Vector3(-hl + 0.9, SC_TOP - 3.4, zc), 0.22, 0.22, -1.0, -1.0, Vector3.BACK)
		# The top beam along each side.
		b.color = Color(0.86, 0.86, 0.83)
		b.part = PortKit.S_PAINT
		b.box(Vector3(-hl + 0.1, SC_TOP - 1.2, minf(z0, z1)), Vector3(hl - 0.1, SC_TOP - 0.1, maxf(z0, z1)))
	# Cross girders over the gap at both ends, the hoist machinery between them.
	b.color = Color(0.86, 0.86, 0.83)
	for ex: float in [-1.0, 1.0]:
		b.box(Vector3(ex * (hl - 0.6) - 0.45, SC_TOP - 1.0, -zo), Vector3(ex * (hl - 0.6) + 0.45, SC_TOP, zo))
	b.color = PortKit.GREY
	b.box(Vector3(-2.6, SC_TOP - 0.6, -1.1), Vector3(2.6, SC_TOP + 0.5, 1.1))
	# The engine and cooling pack on top, louvred.
	b.color = Color(0.86, 0.86, 0.83)
	b.part = PortKit.S_HOUSE
	b.box(Vector3(-hl + 0.3, SC_TOP, -zo + 0.1), Vector3(-0.6, SC_TOP + 1.3, -0.4))
	# The cab: high on the front of the right-hand frame, glazed all round, the driver facing the
	# way it drives.
	b.color = Color(0.86, 0.86, 0.83)
	b.part = PortKit.S_PAINT
	var cz0 := zi - 0.05
	var cz1 := zo + 0.35
	b.box(Vector3(hl - 2.5, SC_TOP - 3.8, cz0), Vector3(hl + 0.25, SC_TOP - 3.5, cz1))
	b.box(Vector3(hl - 2.5, SC_TOP - 1.25, cz0), Vector3(hl + 0.25, SC_TOP - 1.05, cz1))
	b.color = Color(0.2, 0.24, 0.28)
	b.part = PortKit.S_GLASS
	b.box(Vector3(hl - 2.45, SC_TOP - 3.5, cz0 + 0.05), Vector3(hl + 0.2, SC_TOP - 1.25, cz1 - 0.05), 1 | 2 | 16 | 32)
	# Lamps: an amber beacon on the cab roof and one at the back, work lights at the corners, head
	# and tail lamps on the sills.
	b.color = PortKit.YELLOW
	b.part = 11.0
	b.box(Vector3(hl - 1.4, SC_TOP - 1.05, cz1 - 0.6), Vector3(hl - 1.1, SC_TOP - 0.7, cz1 - 0.3))
	b.box(Vector3(-hl + 0.6, SC_TOP + 1.3, -zo + 0.5), Vector3(-hl + 0.9, SC_TOP + 1.65, -zo + 0.8))
	b.color = PortKit.GREY
	b.part = 12.0
	for ex: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			b.box(Vector3(ex * (hl - 0.5) - 0.18, SC_TOP - 1.45, sz * (zo - 0.3) - 0.18), Vector3(ex * (hl - 0.5) + 0.18, SC_TOP - 1.2, sz * (zo - 0.3) + 0.18))
	for sz: float in [-1.0, 1.0]:
		b.part = 12.0
		b.box(Vector3(hl, 1.25, sz * (zo - 0.25) - 0.15), Vector3(hl + 0.04, 1.45, sz * (zo - 0.25) + 0.15))
		b.part = 13.0
		b.box(Vector3(-hl - 0.04, 1.25, sz * (zo - 0.25) - 0.15), Vector3(-hl, 1.45, sz * (zo - 0.25) + 0.15))
	if lv == 0:
		# A ladder up the back leg to the cab walkway, and a walkway along the right top beam.
		b.color = PortKit.YELLOW
		b.part = PortKit.S_PAINT
		for lz: float in [zo + 0.05, zo + 0.5]:
			b.box(Vector3(-hl + 0.2, 1.75, lz - 0.03), Vector3(-hl + 0.26, SC_TOP - 1.2, lz + 0.03))
		var y := 2.1
		while y < SC_TOP - 1.4:
			b.box(Vector3(-hl + 0.2, y, zo + 0.05), Vector3(-hl + 0.26, y + 0.04, zo + 0.5))
			y += 0.32
		b.part = PortKit.S_GRATE
		b.color = PortKit.GREY
		b.box(Vector3(-hl + 0.1, SC_TOP - 1.2, zo), Vector3(hl - 2.5, SC_TOP - 1.08, zo + 0.7))


## The straddle's spreader: sts_spreader_mesh() (the same twistlock frame at a smaller scale is
## not worth a mesh of its own).

# --- Terminal tractor ------------------------------------------------------------------------

static func tractor_mesh() -> ArrayMesh:
	return _mesh("tractor", _tractor)


static func _tractor(b: B, lv: int) -> void:
	var hl := TT_LEN * 0.5
	var paint := Color(0.86, 0.62, 0.08)
	# Frame rails, the low deck behind the cab with the lifting fifth wheel.
	b.color = PortKit.DARK
	b.part = PortKit.S_PAINT
	for sz: float in [-0.5, 0.5]:
		b.box(Vector3(-hl, 0.7, sz - 0.12), Vector3(hl - 0.2, 1.0, sz + 0.12))
	b.color = PortKit.GREY
	b.box(Vector3(TT_FIFTH_X - 0.8, 1.0, -0.8), Vector3(TT_FIFTH_X + 0.8, 1.22, 0.8))
	b.color = PortKit.DARK
	b.box(Vector3(-hl - 0.1, 0.55, -1.2), Vector3(-hl + 0.2, 0.95, 1.2))
	# Front axle and the drive tandem's duals.
	_wheel(b, lv, hl - 1.1, -1.05, 0.55, 0.32)
	_wheel(b, lv, hl - 1.1, 1.05, 0.55, 0.32)
	for sz: float in [-1.0, 1.0]:
		_wheel(b, lv, TT_FIFTH_X, sz * 0.92, 0.55, 0.3)
		_wheel(b, lv, TT_FIFTH_X, sz * 1.24, 0.55, 0.3)
	# Mudguards over them.
	b.color = paint
	b.part = PortKit.S_PAINT
	for sz: float in [-1.0, 1.0]:
		b.box(Vector3(TT_FIFTH_X - 0.75, 1.15, minf(sz * 0.72, sz * 1.42)), Vector3(TT_FIFTH_X + 0.75, 1.22, maxf(sz * 0.72, sz * 1.42)))
	# The engine hood beside the cab and the one-seat cab on the left, set forward.
	b.box(Vector3(hl - 2.3, 0.95, 0.05), Vector3(hl, 2.2, 1.25))
	b.box(Vector3(hl - 2.3, 0.95, -1.3), Vector3(hl - 0.1, 1.35, 0.05))
	b.box(Vector3(hl - 2.3, 2.7, -1.3), Vector3(hl - 0.1, 2.85, 0.05))
	b.box(Vector3(hl - 0.15, 2.85, -1.32), Vector3(hl + 0.05, 2.95, 0.07))
	b.color = Color(0.2, 0.24, 0.28)
	b.part = PortKit.S_GLASS
	b.box(Vector3(hl - 2.25, 1.35, -1.25), Vector3(hl - 0.15, 2.7, 0.0), 1 | 2 | 16 | 32)
	b.color = PortKit.DARK
	b.part = PortKit.S_PAINT
	b.cyl(Vector3(hl - 2.1, 2.2, 0.9), Vector3(hl - 2.1, 3.3, 0.9), 0.07, 6)
	# Grille, lamps, beacon.
	b.color = PortKit.BLACK
	b.box(Vector3(hl, 1.1, 0.2), Vector3(hl + 0.03, 2.0, 1.1), 1)
	b.color = PortKit.GREY
	b.part = 12.0
	for sz: float in [-1.15, 1.1]:
		b.box(Vector3(hl - 0.1, 1.05, sz - 0.12), Vector3(hl + 0.04, 1.22, sz + 0.12))
	b.part = 13.0
	for sz: float in [-1.0, 1.0]:
		b.box(Vector3(-hl - 0.13, 0.6, sz * 1.05 - 0.1), Vector3(-hl - 0.09, 0.78, sz * 1.05 + 0.1))
	b.color = PortKit.YELLOW
	b.part = 11.0
	b.box(Vector3(hl - 1.3, 2.95, -0.75), Vector3(hl - 1.0, 3.25, -0.45))
	if lv == 0:
		b.color = PortKit.GREY
		b.part = PortKit.S_PAINT
		b.box(Vector3(hl - 1.7, 0.45, -1.42), Vector3(hl - 1.2, 0.5, -1.3))
		b.box(Vector3(hl - 0.2, 2.2, -1.5), Vector3(hl - 0.1, 2.5, -1.4))


static func chassis_mesh() -> ArrayMesh:
	return _mesh("chassis", _chassis)


## A 40 ft skeletal chassis, centred: two main beams with a gooseneck at the front, crossmembers,
## twist locks at the corners, landing legs, a tandem of duals at the back, lamps and a bumper.
static func _chassis(b: B, lv: int) -> void:
	var hl := CHASSIS_LEN * 0.5
	var top := CHASSIS_BED
	b.color = PortKit.DARK
	b.part = PortKit.S_PAINT
	for sz: float in [-0.5, 0.5]:
		b.box(Vector3(-hl, top - 0.42, sz - 0.08), Vector3(hl - 2.6, top, sz + 0.08))
		# The gooseneck drops at the front onto the fifth wheel.
		b.box(Vector3(hl - 2.6, top - 0.22, sz - 0.08), Vector3(hl, top, sz + 0.08))
	for k in (8 if lv == 0 else 4):
		var x := lerpf(-hl + 0.3, hl - 0.3, float(k) / float((8 if lv == 0 else 4) - 1))
		b.box(Vector3(x - 0.06, top - 0.22, -1.2), Vector3(x + 0.06, top - 0.04, 1.2))
	b.box(Vector3(-hl, top - 0.3, -1.22), Vector3(-hl + 0.25, top, 1.22))
	b.box(Vector3(hl - 0.25, top - 0.22, -1.22), Vector3(hl, top, 1.22))
	if lv <= 1:
		b.color = PortKit.YELLOW
		for ex: float in [-1.0, 1.0]:
			for sz: float in [-1.0, 1.0]:
				b.box(Vector3(ex * (hl - 0.12) - 0.1, top - 0.02, sz * 1.15 - 0.1), Vector3(ex * (hl - 0.12) + 0.1, top + 0.03, sz * 1.15 + 0.1))
	# Landing legs.
	b.color = PortKit.GREY
	for sz: float in [-0.95, 0.95]:
		b.box(Vector3(hl - 3.4, 0.25, sz - 0.08), Vector3(hl - 3.25, top - 0.42, sz + 0.08))
	# Tandem axle near the back.
	for ax: float in [-hl + 1.1, -hl + 2.4]:
		for sz: float in [-1.0, 1.0]:
			_wheel(b, lv, ax, sz * 0.82, 0.5, 0.28)
			_wheel(b, lv, ax, sz * 1.12, 0.5, 0.28)
	# Rear bumper, lamps.
	b.color = PortKit.DARK
	b.part = PortKit.S_PAINT
	b.box(Vector3(-hl - 0.05, 0.5, -1.15), Vector3(-hl + 0.08, 0.7, 1.15))
	b.color = PortKit.GREY
	b.part = 13.0
	for sz: float in [-1.0, 1.0]:
		b.box(Vector3(-hl - 0.09, top - 0.4, sz * 1.0 - 0.12), Vector3(-hl - 0.05, top - 0.22, sz * 1.0 + 0.12))


# --- The gate --------------------------------------------------------------------------------

## A gate booth on its island, its long axis along Z (the lanes run along Z): a kiosk with glass
## on the lane sides, a roof, a kerb and bollards at the ends.
static func booth_mesh() -> ArrayMesh:
	return _mesh("booth", _booth)


static func _booth(b: B, lv: int) -> void:
	var hw := GATE_ISLAND_W * 0.5
	b.color = Color(0.62, 0.61, 0.58)
	b.part = PortKit.S_PAINT
	b.box(Vector3(-hw, 0.0, -9.0), Vector3(hw, 0.18, 9.0))
	b.color = PortKit.YELLOW
	b.part = PortKit.S_STRIPE
	b.box(Vector3(-hw - 0.01, 0.0, -9.01), Vector3(hw + 0.01, 0.18, -8.6), 1 | 2 | 32 | 4)
	# The kiosk.
	b.color = Color(0.82, 0.82, 0.8)
	b.part = PortKit.S_PAINT
	b.box(Vector3(-0.85, 0.18, -1.6), Vector3(0.85, 1.05, 1.6))
	b.box(Vector3(-0.95, 2.75, -1.75), Vector3(0.95, 3.0, 1.75))
	b.color = Color(0.2, 0.24, 0.28)
	b.part = PortKit.S_GLASS
	b.box(Vector3(-0.85, 1.05, -1.6), Vector3(0.85, 2.75, 1.6), 1 | 2 | 16 | 32)
	# Bollards at the island's nose and a camera / intercom post.
	b.color = PortKit.YELLOW
	b.part = PortKit.S_PAINT
	for z: float in [-8.4, -6.6, 6.8]:
		b.cyl(Vector3(0.0, 0.18, z), Vector3(0.0, 1.2, z), 0.17, 8 if lv == 0 else 6, true)
	b.color = PortKit.GREY
	b.box(Vector3(-0.08, 0.18, -3.2), Vector3(0.08, 1.9, -3.0))
	b.box(Vector3(-0.25, 1.3, -3.25), Vector3(0.25, 1.75, -2.95))
	if lv <= 1:
		# Lane lights on the island: green on the lead post.
		b.part = 13.0
		b.box(Vector3(-0.15, 2.0, -5.1), Vector3(0.15, 2.3, -4.9))


## The canopy over `lanes` lanes and their islands (centred, lanes along Z): columns on the
## islands, a deep fascia, floodlights under it.
static func canopy_mesh(lanes: int) -> ArrayMesh:
	return _mesh("canopy_%d" % lanes, _canopy.bind(lanes))


static func gate_width(lanes: int) -> float:
	return lanes * GATE_LANE_W + (lanes + 1) * GATE_ISLAND_W


static func _canopy(b: B, lv: int, lanes: int) -> void:
	var hw := gate_width(lanes) * 0.5
	var hz := 7.0
	b.color = Color(0.9, 0.9, 0.88)
	b.part = PortKit.S_PAINT
	b.box(Vector3(-hw - 0.5, CANOPY_Y, -hz), Vector3(hw + 0.5, CANOPY_Y + 1.4, hz))
	b.color = Color(0.04, 0.33, 0.37)
	b.box(Vector3(-hw - 0.55, CANOPY_Y + 0.5, -hz - 0.05), Vector3(hw + 0.55, CANOPY_Y + 1.0, hz + 0.05), 1 | 2 | 16 | 32)
	b.color = PortKit.GREY
	for i in lanes + 1:
		var x := -hw + GATE_ISLAND_W * 0.5 + i * (GATE_LANE_W + GATE_ISLAND_W)
		for z: float in [-hz + 1.2, hz - 1.2]:
			b.box(Vector3(x - 0.25, 0.18, z - 0.25), Vector3(x + 0.25, CANOPY_Y, z + 0.25))
	b.part = PortKit.S_LAMP
	var nl := 2 if lv == 0 else 1
	for i in lanes:
		var x := -hw + GATE_ISLAND_W + GATE_LANE_W * 0.5 + i * (GATE_LANE_W + GATE_ISLAND_W)
		for k in nl:
			var z := 0.0 if nl == 1 else (-3.0 + 6.0 * k)
			b.box(Vector3(x - 0.6, CANOPY_Y - 0.12, z - 0.3), Vector3(x + 0.6, CANOPY_Y, z + 0.3))


## The OCR / radiation portal over the lanes: a truss frame on posts with camera heads aimed down
## each lane and a lit sign band.
static func portal_mesh(lanes: int) -> ArrayMesh:
	return _mesh("portal_%d" % lanes, _portal.bind(lanes))


static func _portal(b: B, lv: int, lanes: int) -> void:
	var hw := gate_width(lanes) * 0.5
	var y0 := 6.0
	b.color = PortKit.GREY
	b.part = PortKit.S_PAINT
	for i in lanes + 1:
		var x := -hw + GATE_ISLAND_W * 0.5 + i * (GATE_LANE_W + GATE_ISLAND_W)
		b.box(Vector3(x - 0.2, 0.18, -0.2), Vector3(x + 0.2, y0, 0.2))
		if lv <= 1:
			# A radiation detector panel on each post.
			b.color = Color(0.85, 0.85, 0.82)
			b.box(Vector3(x - 0.45, 0.6, -0.5), Vector3(x + 0.45, 4.2, 0.5))
			b.color = PortKit.GREY
	for y: float in [y0, y0 + 1.1]:
		b.box(Vector3(-hw - 0.3, y, -0.12), Vector3(hw + 0.3, y + 0.16, 0.12))
	if lv <= 1:
		var x := -hw
		while x < hw - 0.5:
			b.beam(Vector3(x, y0 + 0.16, 0.0), Vector3(x + 1.1, y0 + 1.1, 0.0), 0.08, 0.08)
			x += 1.1
	b.color = PortKit.DARK
	for i in lanes:
		var x := -hw + GATE_ISLAND_W + GATE_LANE_W * 0.5 + i * (GATE_LANE_W + GATE_ISLAND_W)
		b.box(Vector3(x - 0.2, y0 - 0.4, -0.5), Vector3(x + 0.2, y0, -0.1))
		b.part = 12.0
		b.box(Vector3(x - 0.6, y0 - 0.25, -0.35), Vector3(x - 0.3, y0 - 0.05, -0.15))
		b.part = PortKit.S_PAINT
	# The lane sign band: dark with a lit edge (the lane numbers are TextMesh, PortLife.build_gate).
	b.color = Color(0.05, 0.2, 0.25)
	b.box(Vector3(-hw, y0 + 1.3, -0.15), Vector3(hw, y0 + 2.3, 0.15))


## The gate's office: a two-storey clad block with a band of windows each floor (lit at night),
## a roof plant box and an entrance canopy. Centred, `w` along X, `d` along Z, front +Z.
static func office_mesh() -> ArrayMesh:
	return _mesh("gate_office", _office)


static func _office(b: B, lv: int) -> void:
	var hw := 11.0
	var hd := 6.0
	var h := 7.6
	b.color = Color(0.82, 0.81, 0.77)
	b.part = PortKit.S_HOUSE
	b.box(Vector3(-hw, 0.0, -hd), Vector3(hw, h, hd), 1 | 2 | 16 | 32)
	b.color = Color(0.86, 0.85, 0.82)
	b.part = PortKit.S_WINDOWS
	for z: float in [-hd - 0.02, hd + 0.02]:
		b.quad(Vector3(-hw + 0.8, 0.8, z), Vector3(hw - 0.8, 0.8, z), Vector3(hw - 0.8, h - 0.6, z), Vector3(-hw + 0.8, h - 0.6, z), Vector3(0.0, 0.0, signf(z)))
	b.color = Color(0.5, 0.5, 0.49)
	b.part = PortKit.S_PAINT
	b.box(Vector3(-hw - 0.15, h, -hd - 0.15), Vector3(hw + 0.15, h + 0.6, hd + 0.15))
	if lv <= 1:
		b.color = PortKit.GREY
		b.part = PortKit.S_HOUSE
		b.box(Vector3(-4.0, h + 0.6, -2.5), Vector3(3.0, h + 2.2, 2.0))
		b.color = Color(0.04, 0.33, 0.37)
		b.part = PortKit.S_PAINT
		b.box(Vector3(-2.5, 2.9, hd), Vector3(2.5, 3.2, hd + 2.2))
		b.color = PortKit.GREY
		for x: float in [-2.3, 2.3]:
			b.box(Vector3(x - 0.08, 0.0, hd + 2.0), Vector3(x + 0.08, 2.9, hd + 2.16))
