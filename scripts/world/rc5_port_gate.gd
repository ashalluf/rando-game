class_name RcPortGate
extends RefCounted
## The truck gate at eye level (wave 8 refcam `port_gate` in tools/refcams/cameras_w8.json,
## docs/HANDOFF.md "The port's truck gate at 10:00"). PortGate's pieces read as placeholders from
## the booths: grey boxes with black mirror glass for kiosks, plain white blocks for the radiation
## portal's detector panels, a flat slab of a canopy on bare posts, half the lanes empty. Here:
## - the booth: a stainless plinth, a glazed cab on corner posts and mullions whose glass shows a
##   lit cabin (port_steel part 15), an overhanging roof with a drip band, a roof AC unit, a door,
##   yellow kerb faces on the island and a driver pedestal (card reader, screen, intercom) at cab
##   height on each lane side;
## - a red-and-white boom barrier past every inbound lane's stop bar (its own batch);
## - the canopy's underside: steel beams over every column line, purlins, a coping and drip edge,
##   columns on striped crash plinths;
## - the portal's detector panels as louvred housings (port_steel S_HOUSE) on a hazard-striped
##   base with a status lamp;
## - painted lane arrows and island-nose hatching on the approach, the gate chunk paved in worn
##   asphalt (yard());
## - busier lanes at the hour: the trucks' odds 70 / 55 -> 92 / 82 % (the same hash; a 10:00 gate
##   is queued, not half empty).
## Every piece is code on PortKit's builder and steel shader; no roll elsewhere moves (the trucks
## are PortGate's own hash). RC5_PORT_GATE=0 is the A/B: PortGate exactly as before.

static func _static_init() -> void: LoadPulse.compiled()  # a boot frame: docs/HANDOFF.md "The boot compile"

static var enabled: bool = OS.get_environment("RC5_PORT_GATE") != "0"

const B := PortKit.Buf
## port_steel.gdshader part 15: a kiosk's glass with its lit cabin behind it.
const S_BOOTH_GLASS := 15.0
const WHITE := Color(0.86, 0.86, 0.84)
const STEEL := Color(0.66, 0.67, 0.67)
const RED := Color(0.72, 0.08, 0.06)
## Truck odds a slot (percent): the booth slot, the queue under the portal.
const ODDS := [92, 82, 78]
const OLD_ODDS := [70, 55, 0]
## The third slot: the queue backed up north of the portal (inbound only). Always a bobtail
## (a tractor coming in for an import box): a whole rig there ran 5 m past the gate's north edge
## into the street (into a road works' excavator, on the default seed).
const QUEUE_Z := -39.5
## The boom barrier: past the inbound stop bar, on the island west of its lane.
const BARRIER_Z := 7.4
const BARRIER_Y := 1.05
const ASPHALT_TINT := Color(0.95, 0.95, 0.95)


## The gate chunk's paving: worn asphalt lanes (the yard's cracked concrete slab, kept everywhere
## else, read as a dry lake bed across the whole foreground of the gate).
static func yard(plan: CityPlan, ix: int, iz: int, concrete: Material) -> Material:
	if not enabled or not PortLife.is_gate(plan, ix, iz):
		return concrete
	return PropFactory.road("asphalt_aerial", 9.0, ASPHALT_TINT, hash([plan.seed, ix, iz, "gate_asphalt"]), 0.0, 1.0)


static func odds(slot: int) -> int:
	return (ODDS if enabled else OLD_ODDS)[slot]


## The same truck's hash made a bobtail (PortGate._spawn_truck: (h / 100) % 5 == 0), its h % 100
## (the odds roll) kept.
static func bobtail(h: int) -> int:
	return h - ((h / 100) % 5) * 100


## The slots a lane has: the old two, a third in the queue while on.
static func slots() -> int:
	return 3 if enabled else 2


## The booth on its island (PortLifeKit.booth_mesh(), island frame: lanes along Z, x across).
static func booth(b: B, lv: int) -> void:
	var hw := PortLifeKit.GATE_ISLAND_W * 0.5
	# The island: a concrete top on yellow kerb faces, the hazard band at both noses.
	b.color = Color(0.66, 0.65, 0.62)
	b.part = PortKit.S_PAINT
	b.box(Vector3(-hw, 0.17, -8.6), Vector3(hw, 0.2, 8.6), 4)
	b.color = PortKit.YELLOW
	b.box(Vector3(-hw, 0.0, -8.6), Vector3(hw, 0.17, 8.6), 1 | 2)
	b.part = PortKit.S_STRIPE
	for z: float in [-9.0, 9.0]:
		var s := signf(z)
		b.box(Vector3(-hw - 0.01, 0.0, minf(z, z - s * 0.4)), Vector3(hw + 0.01, 0.2, maxf(z, z - s * 0.4)), 1 | 2 | 4 | (16 if s > 0.0 else 32))
	# The kiosk: a stainless plinth, glass on posts, a roof that overhangs.
	b.part = PortKit.S_PAINT
	b.color = STEEL
	b.box(Vector3(-0.85, 0.2, -1.6), Vector3(0.85, 1.0, 1.6))
	b.color = PortKit.DARK
	b.box(Vector3(-0.87, 0.2, -1.62), Vector3(0.87, 0.32, 1.62), 1 | 2 | 16 | 32)
	b.part = S_BOOTH_GLASS
	b.color = Color(1, 1, 1)
	b.box(Vector3(-0.8, 1.0, -1.55), Vector3(0.8, 2.6, 1.55), 1 | 2 | 16 | 32)
	b.part = PortKit.S_PAINT
	b.color = Color(0.22, 0.23, 0.24)
	for x: float in [-0.85, 0.85]:
		for z: float in [-1.6, 1.6]:
			b.box(Vector3(x - 0.06, 1.0, z - 0.06), Vector3(x + 0.06, 2.6, z + 0.06))
		if lv == 0:
			for z: float in [-0.53, 0.53]:
				b.box(Vector3(x - 0.035, 1.0, z - 0.03), Vector3(x + 0.035, 2.6, z + 0.03), 1 | 2 | 16 | 32)
			# The sill and the transom bar.
			b.box(Vector3(x - 0.05, 1.0, -1.6), Vector3(x + 0.05, 1.07, 1.6), 1 | 2 | 4)
	# The door on the +Z end: a dark leaf with a window, a step.
	b.color = Color(0.3, 0.32, 0.33)
	b.box(Vector3(-0.42, 0.2, 1.6), Vector3(0.42, 2.45, 1.64), 16)
	b.color = Color(0.5, 0.5, 0.5)
	b.box(Vector3(-0.55, 0.2, 1.6), Vector3(0.55, 0.38, 1.95), 4 | 16 | 1 | 2)
	# The roof: a white cap overhanging the glass, a dark drip band, an AC unit, a mast lamp.
	b.color = WHITE
	b.box(Vector3(-1.05, 2.6, -1.85), Vector3(1.05, 2.86, 1.85))
	b.color = Color(0.05, 0.3, 0.34)
	b.box(Vector3(-1.07, 2.62, -1.87), Vector3(1.07, 2.74, 1.87), 1 | 2 | 16 | 32)
	if lv <= 1:
		b.color = Color(0.74, 0.74, 0.72)
		b.part = PortKit.S_HOUSE
		b.box(Vector3(-0.45, 2.86, -0.9), Vector3(0.45, 3.35, 0.3))
		b.part = PortKit.S_PAINT
		b.color = PortKit.DARK
		b.cyl(Vector3(0.0, 3.35, -0.3), Vector3(0.0, 3.37, -0.3), 0.3, 10 if lv == 0 else 6, true)
	# Bollards at the noses (taller, with a reflective band), the camera / lane-light post.
	for z: float in [-8.3, -6.7, 6.7, 8.3]:
		b.color = PortKit.YELLOW
		b.part = PortKit.S_PAINT
		b.cyl(Vector3(0.0, 0.2, z), Vector3(0.0, 1.25, z), 0.16, 10 if lv == 0 else 6, true)
		if lv <= 1:
			b.color = Color(0.1, 0.1, 0.1)
			b.cyl(Vector3(0.0, 0.95, z), Vector3(0.0, 1.05, z), 0.165, 10 if lv == 0 else 6, false)
	b.color = PortKit.GREY
	b.part = PortKit.S_PAINT
	b.box(Vector3(-0.07, 0.2, -5.1), Vector3(0.07, 3.1, -4.95))
	if lv <= 1:
		b.color = PortKit.DARK
		b.box(Vector3(-0.17, 2.3, -5.25), Vector3(0.17, 2.95, -4.85))
		b.part = 13.0
		b.box(Vector3(-0.12, 2.75, -5.27), Vector3(0.12, 2.9, -5.25), 32)
		b.part = PortKit.S_LAMP
		b.box(Vector3(-0.08, 2.42, -5.27), Vector3(0.08, 2.55, -5.25), 32)
	# The driver pedestals: on each lane side, at a cab window's height, ahead of the booth.
	b.part = PortKit.S_PAINT
	for sx: float in [-1.0, 1.0]:
		var x := sx * 0.62
		b.color = STEEL
		b.box(Vector3(x - 0.14, 0.2, 2.85), Vector3(x + 0.14, 1.85, 3.15))
		b.color = Color(0.2, 0.21, 0.22)
		b.box(Vector3(x - 0.24, 1.85, 2.75), Vector3(x + 0.24, 2.65, 3.25))
		if lv <= 1:
			b.part = PortKit.S_GLASS
			var fx := x + sx * 0.241
			b.quad(Vector3(fx, 2.15, 2.85), Vector3(fx, 2.15, 3.15), Vector3(fx, 2.5, 3.15), Vector3(fx, 2.5, 2.85), Vector3(sx, 0, 0))
			b.part = PortKit.S_LAMP
			b.quad(Vector3(fx + sx * 0.002, 1.95, 2.9), Vector3(fx + sx * 0.002, 1.95, 3.1), Vector3(fx + sx * 0.002, 2.05, 3.1), Vector3(fx + sx * 0.002, 2.05, 2.9), Vector3(sx, 0, 0))
			b.part = PortKit.S_PAINT


## The canopy (PortLifeKit.canopy_mesh()): the old slab and fascia, steel under it, columns on
## crash plinths.
static func canopy(b: B, lv: int, lanes: int) -> void:
	var hw := PortLifeKit.gate_width(lanes) * 0.5
	var hz := 7.0
	var cy := PortLifeKit.CANOPY_Y
	# The deck and its fascia.
	b.color = Color(0.9, 0.9, 0.88)
	b.part = PortKit.S_PAINT
	b.box(Vector3(-hw - 0.5, cy + 0.25, -hz), Vector3(hw + 0.5, cy + 1.4, hz), 1 | 2 | 4 | 16 | 32)
	b.color = Color(0.8, 0.81, 0.82)
	b.part = PortKit.S_RIBBED
	b.box(Vector3(-hw - 0.45, cy + 0.25, -hz + 0.05), Vector3(hw + 0.45, cy + 0.26, hz - 0.05), 8)
	b.part = PortKit.S_PAINT
	b.color = Color(0.04, 0.33, 0.37)
	b.box(Vector3(-hw - 0.55, cy + 0.55, -hz - 0.05), Vector3(hw + 0.55, cy + 1.05, hz + 0.05), 1 | 2 | 16 | 32)
	b.color = Color(0.3, 0.31, 0.32)
	b.box(Vector3(-hw - 0.58, cy + 1.4, -hz - 0.08), Vector3(hw + 0.58, cy + 1.5, hz + 0.08))
	b.color = Color(0.82, 0.82, 0.8)
	b.box(Vector3(-hw - 0.56, cy + 0.2, -hz - 0.06), Vector3(hw + 0.56, cy + 0.3, hz + 0.06), 1 | 2 | 8 | 16 | 32)
	# Steel: a beam over each column line, purlins across them.
	b.color = Color(0.46, 0.48, 0.5)
	for i in lanes + 1:
		var x := -hw + PortLifeKit.GATE_ISLAND_W * 0.5 + i * (PortLifeKit.GATE_LANE_W + PortLifeKit.GATE_ISLAND_W)
		b.box(Vector3(x - 0.16, cy - 0.45, -hz + 0.2), Vector3(x + 0.16, cy + 0.25, hz - 0.2), 1 | 2 | 8 | 16 | 32)
	if lv <= 1:
		var z := -hz + 0.6
		while z < hz - 0.3:
			b.box(Vector3(-hw - 0.3, cy + 0.05, z - 0.06), Vector3(hw + 0.3, cy + 0.25, z + 0.06), 8 | 16 | 32)
			z += 1.6
	# Columns: a steel post with a cap plate on a striped concrete crash plinth.
	for i in lanes + 1:
		var x := -hw + PortLifeKit.GATE_ISLAND_W * 0.5 + i * (PortLifeKit.GATE_LANE_W + PortLifeKit.GATE_ISLAND_W)
		for z: float in [-hz + 1.2, hz - 1.2]:
			b.color = Color(0.4, 0.42, 0.44)
			b.part = PortKit.S_PAINT
			b.box(Vector3(x - 0.2, 1.2, z - 0.2), Vector3(x + 0.2, cy - 0.45, z + 0.2), 1 | 2 | 16 | 32)
			b.box(Vector3(x - 0.32, cy - 0.6, z - 0.32), Vector3(x + 0.32, cy - 0.45, z + 0.32))
			b.part = PortKit.S_STRIPE
			b.color = PortKit.YELLOW
			b.box(Vector3(x - 0.38, 0.18, z - 0.38), Vector3(x + 0.38, 1.2, z + 0.38), 1 | 2 | 4 | 16 | 32)
	# The lane lamps: the old fittings under the purlins.
	b.part = PortKit.S_LAMP
	var nl := 2 if lv == 0 else 1
	for i in lanes:
		var x := -hw + PortLifeKit.GATE_ISLAND_W + PortLifeKit.GATE_LANE_W * 0.5 + i * (PortLifeKit.GATE_LANE_W + PortLifeKit.GATE_ISLAND_W)
		for k in nl:
			var z := 0.0 if nl == 1 else (-3.0 + 6.0 * k)
			b.box(Vector3(x - 0.6, cy - 0.12, z - 0.3), Vector3(x + 0.6, cy + 0.05, z + 0.3))


## The portal's detector panels (PortLifeKit.portal_mesh(), on each post): a louvred housing on a
## hazard-striped base, a cap and a status lamp. Called in place of the old white block.
static func detector(b: B, lv: int, x: float) -> void:
	b.part = PortKit.S_STRIPE
	b.color = PortKit.YELLOW
	b.box(Vector3(x - 0.5, 0.18, -0.55), Vector3(x + 0.5, 0.75, 0.55), 1 | 2 | 4 | 16 | 32)
	b.part = PortKit.S_HOUSE
	b.color = Color(0.7, 0.71, 0.68)
	b.box(Vector3(x - 0.45, 0.75, -0.5), Vector3(x + 0.45, 4.1, 0.5), 1 | 2 | 16 | 32)
	b.part = PortKit.S_PAINT
	b.color = Color(0.3, 0.31, 0.32)
	b.box(Vector3(x - 0.5, 4.1, -0.55), Vector3(x + 0.5, 4.25, 0.55))
	if lv == 0:
		b.color = Color(0.2, 0.21, 0.22)
		for sx: float in [-1.0, 1.0]:
			b.box(Vector3(x + sx * 0.455 - 0.01, 2.1, -0.2), Vector3(x + sx * 0.455 + 0.01, 2.5, 0.2), 1 | 2)
		b.part = 13.0
		b.box(Vector3(x - 0.08, 4.25, -0.08), Vector3(x + 0.08, 4.4, 0.08))


## A boom barrier: its cabinet at the origin, the arm along +X across a lane, down.
static func barrier_mesh() -> ArrayMesh:
	return PortLifeKit._mesh("gate_barrier", _barrier)


static func _barrier(b: B, lv: int) -> void:
	b.part = PortKit.S_PAINT
	b.color = PortKit.YELLOW
	b.box(Vector3(-0.2, 0.2, -0.17), Vector3(0.2, 1.15, 0.17))
	b.color = PortKit.DARK
	b.box(Vector3(-0.22, 1.15, -0.19), Vector3(0.22, 1.22, 0.19))
	var arm := PortLifeKit.GATE_LANE_W + 0.2
	var seg := 0.5
	var n := int(ceil(arm / seg))
	for k in n:
		b.color = RED if k % 2 == 0 else Color(0.92, 0.92, 0.9)
		var x0 := 0.2 + k * seg
		var x1 := minf(0.2 + (k + 1) * seg, 0.2 + arm)
		b.box(Vector3(x0, BARRIER_Y - 0.06, -0.05), Vector3(x1, BARRIER_Y + 0.06, 0.05), 4 | 8 | 16 | 32 | (1 if k == n - 1 else 0))
	if lv == 0:
		b.color = PortKit.DARK
		b.box(Vector3(0.2 + arm - 0.1, 0.2, -0.04), Vector3(0.2 + arm - 0.04, BARRIER_Y - 0.06, 0.04))
		b.box(Vector3(0.2 + arm - 0.25, 0.2, -0.12), Vector3(0.2 + arm + 0.11, 0.25, 0.12))
		b.part = 13.0
		b.box(Vector3(-0.08, 1.22, -0.08), Vector3(0.08, 1.32, 0.08))


## PortGate.build()'s extra pieces at FULL: a barrier past each inbound lane's stop bar, arrows
## and island-nose hatching on the approach.
static func build(ch: CityChunk, area: Rect2) -> void:
	if not enabled:
		return
	var y := CityChunk.PORT_YARD_TOP
	var cz := area.position.y + PortGate.CANOPY_Z
	var hw := PortLifeKit.gate_width(PortGate.LANES) * 0.5
	var cx := area.get_center().x
	for i in PortGate.LANES:
		var lx := PortGate.lane_x(area, i)
		var outbound := i < PortGate.OUT_LANES
		var island := lx - PortLifeKit.GATE_LANE_W * 0.5 - PortLifeKit.GATE_ISLAND_W * 0.5
		if outbound:
			# Outbound: the arm on the island east of the lane, swinging west, before the street.
			ch._batch.add("port_gate_barrier", barrier_mesh(), Transform3D(Basis(Vector3.UP, PI), Vector3(island + PortLifeKit.GATE_LANE_W + PortLifeKit.GATE_ISLAND_W, y, cz - BARRIER_Z)))
		else:
			ch._batch.add("port_gate_barrier", barrier_mesh(), Transform3D(Basis(), Vector3(island, y, cz + BARRIER_Z)))
		# A lane arrow on the approach, the way the lane runs.
		var dir := -1.0 if outbound else 1.0
		var az := area.position.y + 14.0
		var tip := Vector2(lx, az + dir * 2.4)
		ch._port_line(Vector2(lx, az - dir * 2.4), tip, 0.3, CityChunk.PORT_PAINT_WHITE)
		for s: float in [-1.0, 1.0]:
			ch._port_line(tip, tip + Vector2(s * 0.85, -dir * 1.3), 0.3, CityChunk.PORT_PAINT_WHITE)
	# Chevron hatching ahead of each island's north nose (the trucks' side), yellow.
	for i in PortGate.LANES + 1:
		var ix := cx - hw + PortLifeKit.GATE_ISLAND_W * 0.5 + i * (PortLifeKit.GATE_LANE_W + PortLifeKit.GATE_ISLAND_W)
		var nz := cz - 9.0
		ch._port_line(Vector2(ix - 1.1, nz - 0.05), Vector2(ix, nz - 4.5), 0.18, CityChunk.PORT_PAINT_YELLOW)
		ch._port_line(Vector2(ix + 1.1, nz - 0.05), Vector2(ix, nz - 4.5), 0.18, CityChunk.PORT_PAINT_YELLOW)
		for k in 3:
			var t := 0.25 + 0.25 * k
			var zk := nz - 4.5 * t
			ch._port_line(Vector2(ix - 1.1 * (1.0 - t), zk + 0.6), Vector2(ix + 1.1 * (1.0 - t), zk - 0.6), 0.14, CityChunk.PORT_PAINT_YELLOW)
