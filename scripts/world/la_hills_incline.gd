class_name LaHillsIncline
extends Node3D
## PALOMA FLIGHT: a short funicular up Bunker Hill's east face (LaHills), the form of the hill's
## famous little incline railway but its own (invented name, teal and cream cars, a steel trestle on
## concrete piers, an arched gateway on Hill St, a canopy at the top on Olive St). It runs mid-block
## between 3rd and 4th St, in the Olive - Hill block, from the back of Hill St's pavement to the back
## of Olive St's; a public stairway climbs beside it. Two counterbalanced cars on parallel tracks,
## worked out from the clock (one up while the other comes down, a dwell at each end).
##
## The lots the strip crosses are claimed in CityChunk._build_lot() AFTER every roll and claim
## (claims()); they become a paved plaza, and the first of them builds the incline (FULL chunks; an
## LOD chunk and the far city get the paving). `LA_HILLS=0` leaves it out with the hills.

const NAME := "PALOMA FLIGHT"
## The strip: its half width round the track's centre line (track, stairs, a margin).
const HALF := 11.0
## Where the centre line runs, as a share of the way from 3rd St to 4th St.
const AT_SHARE := 0.52
## How far the lots either side stand off the strip, and the shallowest piece of a lot built on (m).
const PIECE_GAP := 1.0
const PIECE_MIN := 14.0
## Tracks either side of the centre line, the stairway's centre line.
const TRACK_OFF := 1.15
const STAIR_OFF := 6.2
## Cars: horizontal length, height, width.
const CAR_L := 7.2
const CAR_H := 2.7
const CAR_W := 2.1
## The timetable: a dwell at each end and the ride between (seconds).
const DWELL := 14.0
const RIDE := 22.0
const PAINT_A := Color(0.10, 0.40, 0.38)
const PAINT_B := Color(0.55, 0.16, 0.10)
const CREAM := Color(0.92, 0.88, 0.76)
const STEEL := Color(0.13, 0.13, 0.14)
const CONCRETE := Color(0.82, 0.80, 0.76)

var _a := Vector3.ZERO
var _b := Vector3.ZERO
## The rail line (local to the node) and the distance along it at each point.
var _path := PackedVector3Array()
var _dist := PackedFloat32Array()
var _cars: Array[Node3D] = []


## The incline's strip in world XZ and its ends, or {} (no hills, or the grid not there).
static func site(plan: CityPlan) -> Dictionary:
	if not LaHills.enabled or plan == null or plan.macro == null or plan.macro.la_hills == null:
		return {}
	if plan.has_meta("la_hills_incline"):
		return plan.get_meta("la_hills_incline")
	var res := {}
	var hill := DowntownReal.named(CityPlan.AXIS_X, "HILL ST")
	var olive := DowntownReal.named(CityPlan.AXIS_X, "OLIVE ST")
	var third := DowntownReal.named(CityPlan.AXIS_Z, "3RD ST")
	var fourth := DowntownReal.named(CityPlan.AXIS_Z, "4TH ST")
	if not (hill.is_empty() or olive.is_empty() or third.is_empty() or fourth.is_empty()):
		var hx := float(hill[0]) - float(hill[1]) * 0.5 - plan.sidewalk_width
		var ox := float(olive[0]) + float(olive[1]) * 0.5 + plan.sidewalk_width
		var z0 := float(third[0]) + float(third[1]) * 0.5 + plan.sidewalk_width
		var z1 := float(fourth[0]) - float(fourth[1]) * 0.5 - plan.sidewalk_width
		var z := lerpf(z0, z1, AT_SHARE)
		res = {"z": z, "x_bot": hx - 3.0, "x_top": ox + 3.0,
			"rect": Rect2(ox, z - HALF, hx - ox, HALF * 2.0)}
	plan.set_meta("la_hills_incline", res)
	return res


## True for a lot the strip crosses (CityChunk._build_lot(), after every roll and claim).
static func claims(plan: CityPlan, lot: Dictionary) -> bool:
	var s := site(plan)
	if s.is_empty():
		return false
	var half: Vector2 = (lot.size as Vector2) * 0.5
	var r := Rect2((lot.center as Vector2) - half, half * 2.0)
	return r.intersects(s.rect)


## What a lot crossed by the strip keeps either side of it: the lot cut along z at the strip's edges
## (each piece at least PIECE_MIN deep, its cell cut the same way, its seed a hash of the lot's), so
## the towers and mid-rises stand on the terrace and step down the face beside the incline. PURE.
static func pieces(plan: CityPlan, lot: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var s := site(plan)
	if s.is_empty():
		return out
	var band: Rect2 = s.rect
	var half: Vector2 = (lot.size as Vector2) * 0.5
	var c: Vector2 = lot.center
	var cell: Rect2 = lot.get("cell", Rect2(c - half, half * 2.0))
	var spans := [[c.y - half.y, band.position.y - PIECE_GAP], [band.end.y + PIECE_GAP, c.y + half.y]]
	for k in spans.size():
		var z0: float = spans[k][0]
		var z1: float = spans[k][1]
		if z1 - z0 < PIECE_MIN:
			continue
		var p := lot.duplicate()
		p.center = Vector2(c.x, (z0 + z1) * 0.5)
		p.size = Vector2(half.x * 2.0, z1 - z0)
		var cz0 := cell.position.y if k == 0 else band.end.y
		var cz1 := band.position.y if k == 0 else cell.end.y
		p.cell = Rect2(cell.position.x, cz0, cell.size.x, maxf(cz1 - cz0, 0.0))
		p.seed = absi(hash([int(lot.seed), "paloma_piece", k]))
		p.parking = false
		out.append(p)
	return out


## A claimed lot: its share of the strip is a planted bank either side of the incline and the
## stairway, the first one in the chunk builds the incline; it returns what is left of the lot
## either side (pieces()), which CityChunk._build_lot() builds as ordinary lots.
static func build_lot(ch: CityChunk, lot: Dictionary) -> Array[Dictionary]:
	var half: Vector2 = (lot.size as Vector2) * 0.5
	var c: Vector2 = lot.center
	var s := site(ch.plan)
	var band: Rect2 = s.rect
	var x0 := maxf(c.x - half.x, band.position.x)
	var x1 := minf(c.x + half.x, band.end.x)
	var z0 := maxf(c.y - half.y, band.position.y - PIECE_GAP)
	var z1 := minf(c.y + half.y, band.end.y + PIECE_GAP)
	if x1 > x0 and z1 > z0:
		ch._add_slab(Vector3((x0 + x1) * 0.5, CityChunk.SIDEWALK_TOP * 0.5, (z0 + z1) * 0.5), Vector3(x1 - x0, CityChunk.SIDEWALK_TOP, z1 - z0),
			Color(0.36, 0.45, 0.24), true, PropFactory.lawn(Color(0.42, 0.50, 0.27), 4402, 0.4, 0.0))
	var rest := pieces(ch.plan, lot)
	# The part of the lot the cut left too shallow to build on is planted with the strip.
	for k in 2:
		var lz0 := c.y - half.y if k == 0 else band.end.y + PIECE_GAP
		var lz1 := band.position.y - PIECE_GAP if k == 0 else c.y + half.y
		if lz1 - lz0 <= 0.0 or lz1 - lz0 >= PIECE_MIN:
			continue
		ch._add_slab(Vector3(c.x, CityChunk.SIDEWALK_TOP * 0.5, (lz0 + lz1) * 0.5), Vector3(half.x * 2.0, CityChunk.SIDEWALK_TOP, lz1 - lz0),
			Color(0.36, 0.45, 0.24), true, PropFactory.lawn(Color(0.42, 0.50, 0.27), 4402, 0.4, 0.0))
	if ch.capturing or ch.level != CityChunk.Level.FULL:
		return rest
	# A row of trees along each edge of the strip, off the incline and the stairs.
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([ch.plan.seed, "paloma_knoll", int(lot.seed)])
	for zz: float in [band.position.y + 2.2, band.end.y - 2.0]:
		var x := x0 + 5.0
		while x < x1 - 3.0:
			ch._add_tree(Vector3(x + rng.randf_range(-1.0, 1.0), CityChunk.SIDEWALK_TOP, zz), rng)
			x += rng.randf_range(9.0, 13.0)
	if ch.has_meta("paloma_flight"):
		return rest
	ch.set_meta("paloma_flight", true)
	var node := LaHillsIncline.new()
	node.name = "PalomaFlight"
	ch.add_child(node)
	node._build(ch, site(ch.plan))
	return rest


func _ground(ch: CityChunk, x: float, z: float) -> float:
	return ch._gy(x, z) + CityChunk.SIDEWALK_TOP


func _build(ch: CityChunk, s: Dictionary) -> void:
	var z: float = s.z
	var xb: float = s.x_bot
	var xt: float = s.x_top
	var o := Vector3((xb + xt) * 0.5, 0.0, z)
	position = o
	# The rail line follows the hill, smoothed: a metre over the ground, never under 0.7 m, so the
	# track hugs the scarp rather than standing off it on a straight chord.
	var n := 48
	var ys := PackedFloat32Array()
	var gs := PackedFloat32Array()
	for i in n + 1:
		var x := lerpf(xb, xt, float(i) / float(n))
		gs.append(_ground(ch, x, z))
		ys.append(gs[i] + 1.0)
	for pass_i in 6:
		var sm := ys.duplicate()
		for i in range(1, n):
			sm[i] = maxf((ys[i - 1] + ys[i] * 2.0 + ys[i + 1]) * 0.25, gs[i] + 0.7)
		ys = sm
	_path = PackedVector3Array()
	_dist = PackedFloat32Array()
	for i in n + 1:
		_path.append(Vector3(lerpf(xb, xt, float(i) / float(n)), ys[i], z) - o)
		_dist.append(0.0 if i == 0 else _dist[i - 1] + _path[i].distance_to(_path[i - 1]))
	_a = _path[0]
	_b = _path[n]
	var g := LandmarkGeo.new()
	g.use("fb", FootbridgeKit.material())
	var length: float = _dist[n]
	# The trestle, segment by segment: two plate girders under each track, rails, sleepers, the
	# deck plate between the tracks; piers down to the ground every few segments.
	for i in n:
		var a := _path[i]
		var b := _path[i + 1]
		var along := (b - a).normalized()
		var deck_up := Vector3(-along.y, along.x, 0.0)
		for t: float in [-TRACK_OFF, TRACK_OFF]:
			var off := Vector3(0, 0, t)
			for side: float in [-0.5, 0.5]:
				_beam(g, a + off + Vector3(0, -0.45, side), b + off + Vector3(0, -0.45, side), 0.12, 0.7, STEEL, FootbridgeKit.K_PAINT)
			for rail: float in [-0.45, 0.45]:
				_beam(g, a + off + Vector3(0, 0.06, rail), b + off + Vector3(0, 0.06, rail), 0.07, 0.12, Color(0.6, 0.6, 0.6), 2)
			var sn := maxi(int(a.distance_to(b) / 0.65), 1)
			for k in sn:
				var p := a.lerp(b, (float(k) + 0.5) / float(sn)) + off
				g.box("fb", p, Vector3(0.22, 0.14, 1.5), FootbridgeKit.kc(Color(0.25, 0.2, 0.16), FootbridgeKit.K_PAINT), Basis(Vector3(0, 0, 1), atan2(along.y, along.x)))
		_beam(g, a + Vector3(0, -0.2, 0), b + Vector3(0, -0.2, 0), 4.6, 0.12, STEEL, FootbridgeKit.K_PAINT, deck_up)
		if i > 0 and i % 4 == 0:
			var gw := gs[i] - 0.3
			var top := a.y - 0.8
			if top - gw > 0.3:
				g.box("fb", Vector3(a.x, (top + gw) * 0.5, 0.0), Vector3(0.8, top - gw, 4.2), FootbridgeKit.kc(CONCRETE, FootbridgeKit.K_CONCRETE))
	# The gateway on Hill St: two piers, an arched lintel, the name, lanterns; and a canopy at the top.
	_gateway(g, ch, _a + Vector3(1.5, 0, 0), o)
	_canopy(g, _b + Vector3(-1.0, 0, 0))
	var mi := g.commit(self, "Structure", true, 420.0)
	# The stairs beside it, down the south side.
	var sg := LandmarkGeo.new()
	sg.use("fb", FootbridgeKit.material())
	LaHillsBuild._flight(sg, ch, true, z + STAIR_OFF, xt - 2.0, xb + 1.0, o)
	sg.commit(self, "Stairs", true, 260.0)
	# Collision: the trestle (one box along it) and the gateway's piers.
	var body := StaticBody3D.new()
	body.name = "Body"
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	for i in range(0, n, 4):
		var a := _path[i]
		var b := _path[mini(i + 4, n)]
		var along := (b - a).normalized()
		var basis := Basis(Vector3(0, 0, 1).cross(along).normalized(), along, Vector3(0, 0, 1))
		LandmarkGeo.shape_box(body, (a + b) * 0.5 + Vector3(0, -0.2, 0), Vector3(0.6, a.distance_to(b), 4.6), basis)
	# The name over the gateway.
	var tm := TextMesh.new()
	tm.text = NAME
	tm.font_size = 52
	tm.pixel_size = 0.012
	tm.depth = 0.04
	var label := MeshInstance3D.new()
	label.mesh = tm
	label.material_override = PropFactory.material(CREAM, 0.6)
	label.position = Vector3(_a.x + 1.5 + 0.38, _ground(ch, _a.x + 1.5 + o.x, z) + 4.5, 0.0)
	label.rotation = Vector3(0.0, PI * 0.5, 0.0)
	label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(label)
	# The two cars.
	for k in 2:
		var car := MeshInstance3D.new()
		car.name = "Car%d" % k
		car.mesh = _car_mesh(PAINT_A if k == 0 else PAINT_B, 0.0)
		add_child(car)
		_cars.append(car)
	_place(0.0)
	if mi == null:
		push_warning("PalomaFlight: no structure")


func _gateway(g: LandmarkGeo, ch: CityChunk, at: Vector3, o: Vector3) -> void:
	var gy := _ground(ch, at.x + o.x, at.z + o.z)
	for side: float in [-1.0, 1.0]:
		g.box("fb", Vector3(at.x, gy + 2.6, side * 2.9), Vector3(0.9, 5.2, 0.9), FootbridgeKit.kc(CREAM, FootbridgeKit.K_CONCRETE))
		g.box("fb", Vector3(at.x, gy + 5.5, side * 2.9), Vector3(0.5, 0.6, 0.5), FootbridgeKit.kc(CREAM, FootbridgeKit.K_LAMP))
	g.box("fb", Vector3(at.x, gy + 4.5, 0.0), Vector3(0.7, 0.9, 6.7), FootbridgeKit.kc(PAINT_B, FootbridgeKit.K_PAINT))
	g.box("fb", Vector3(at.x, gy + 5.05, 0.0), Vector3(0.9, 0.2, 7.0), FootbridgeKit.kc(CREAM, FootbridgeKit.K_CONCRETE))


func _canopy(g: LandmarkGeo, at: Vector3) -> void:
	for dx: float in [-2.5, 2.5]:
		for dz: float in [-2.6, 2.6]:
			g.box("fb", at + Vector3(dx, 1.4, dz), Vector3(0.18, 3.0, 0.18), FootbridgeKit.kc(STEEL, FootbridgeKit.K_PAINT))
	g.box("fb", at + Vector3(0, 3.0, 0), Vector3(6.4, 0.22, 6.4), FootbridgeKit.kc(PAINT_A, FootbridgeKit.K_PAINT))
	g.box("fb", at + Vector3(0, 2.84, 0), Vector3(4.0, 0.06, 0.3), FootbridgeKit.kc(CREAM, FootbridgeKit.K_LAMP))


## A car whose floor and roof follow the incline (`slope` rise over run along +x), its end walls
## upright: a body in the paint, a cream window band with dark glass, a cream roof, a dark bogie.
func _car_mesh(paint: Color, slope: float) -> Mesh:
	var g := LandmarkGeo.new()
	g.use("fb", FootbridgeKit.material())
	var hl := CAR_L * 0.5
	var hw := CAR_W * 0.5
	var bands := [[0.0, 1.15, paint, FootbridgeKit.K_PAINT], [1.15, 2.2, Color(1, 1, 1), FootbridgeKit.K_DARK],
		[2.2, 2.45, CREAM, FootbridgeKit.K_PAINT], [2.45, CAR_H, paint, FootbridgeKit.K_PAINT]]
	for band: Array in bands:
		var y0: float = band[0]
		var y1: float = band[1]
		var col := FootbridgeKit.kc(band[2], int(band[3]))
		for side: float in [-1.0, 1.0]:
			var a := Vector3(-hl, -hl * slope + y0, side * hw)
			var b := Vector3(hl, hl * slope + y0, side * hw)
			var c := Vector3(hl, hl * slope + y1, side * hw)
			var d := Vector3(-hl, -hl * slope + y1, side * hw)
			g.quad("fb", a, b, c, d, Vector3(0, 0, side), Vector2(0, y0), Vector2(CAR_L, y0), Vector2(CAR_L, y1), Vector2(0, y1), col)
		for end: float in [-1.0, 1.0]:
			var x := end * hl
			var y := x * slope
			g.quad("fb", Vector3(x, y + y0, -hw), Vector3(x, y + y0, hw), Vector3(x, y + y1, hw), Vector3(x, y + y1, -hw),
				Vector3(end, 0, 0), Vector2(0, y0), Vector2(CAR_W, y0), Vector2(CAR_W, y1), Vector2(0, y1), col)
	# Roof and floor.
	var roof := FootbridgeKit.kc(CREAM, FootbridgeKit.K_PAINT)
	g.quad("fb", Vector3(-hl - 0.1, -hl * slope + CAR_H, -hw - 0.1), Vector3(hl + 0.1, hl * slope + CAR_H, -hw - 0.1),
		Vector3(hl + 0.1, hl * slope + CAR_H, hw + 0.1), Vector3(-hl - 0.1, -hl * slope + CAR_H, hw + 0.1), Vector3.UP,
		Vector2.ZERO, Vector2(CAR_L, 0), Vector2(CAR_L, CAR_W), Vector2(0, CAR_W), roof)
	g.quad("fb", Vector3(-hl, -hl * slope, -hw), Vector3(hl, hl * slope, -hw), Vector3(hl, hl * slope, hw), Vector3(-hl, -hl * slope, hw), Vector3.DOWN,
		Vector2.ZERO, Vector2(CAR_L, 0), Vector2(CAR_L, CAR_W), Vector2(0, CAR_W), FootbridgeKit.kc(STEEL, FootbridgeKit.K_PAINT))
	# Bogies.
	for end: float in [-0.6, 0.6]:
		var x := end * hl
		g.box("fb", Vector3(x, x * slope - 0.2, 0.0), Vector3(1.2, 0.4, 1.3), FootbridgeKit.kc(STEEL, FootbridgeKit.K_PAINT))
	var holder := Node3D.new()
	var mi := g.commit(holder, "m")
	var mesh: Mesh = mi.mesh if mi else null
	holder.free()
	return mesh


## Where the cars are at `t` seconds: car 0 at u (0 the bottom), car 1 at 1 - u.
static func ride_u(t: float) -> float:
	var period := 2.0 * (DWELL + RIDE)
	var q := fposmod(t, period)
	if q < DWELL:
		return 0.0
	q -= DWELL
	if q < RIDE:
		return smoothstep(0.0, 1.0, q / RIDE)
	q -= RIDE
	if q < DWELL:
		return 1.0
	return 1.0 - smoothstep(0.0, 1.0, (q - DWELL) / RIDE)


func _place(t: float) -> void:
	var u := ride_u(t)
	for k in _cars.size():
		var uk := u if k == 0 else 1.0 - u
		var d := lerpf(0.06, 0.94, uk) * _dist[_dist.size() - 1]
		var i := 0
		while i < _dist.size() - 2 and _dist[i + 1] < d:
			i += 1
		var f := (d - _dist[i]) / maxf(_dist[i + 1] - _dist[i], 0.001)
		var p := _path[i].lerp(_path[i + 1], f)
		var along := (_path[mini(i + 2, _path.size() - 1)] - _path[maxi(i - 1, 0)]).normalized()
		_cars[k].position = p + Vector3(0, 0.45, -TRACK_OFF if k == 0 else TRACK_OFF)
		# The car body stays upright on the incline: its floor tilts with the track, its walls do not
		# (the mesh is built level, so only the floor line is sheared by the pitch).
		_cars[k].transform.basis = Basis(Vector3(1, along.y / maxf(absf(along.x), 0.05) * signf(along.x), 0), Vector3.UP, Vector3(0, 0, 1))


func _process(_delta: float) -> void:
	_place(float(Time.get_ticks_msec()) / 1000.0)


static func _beam(g: LandmarkGeo, a: Vector3, b: Vector3, w: float, h: float, col: Color, kind: int, up := Vector3.UP) -> void:
	var zz := b - a
	var length := zz.length()
	if length < 0.01:
		return
	zz /= length
	var x := up.cross(zz)
	if x.length_squared() < 1e-6:
		x = Vector3.RIGHT.cross(zz)
	x = x.normalized()
	var y := zz.cross(x).normalized()
	g.box("fb", (a + b) * 0.5, Vector3(w, h, length), FootbridgeKit.kc(col, kind), Basis(x, y, zz))
