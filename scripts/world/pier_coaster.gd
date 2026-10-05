class_name PierCoaster
extends Node3D
## The pier park's steel coaster, the KELP CRACKER (PierPark): a closed track looping round the
## park platform - station, chain lift up the north side, a turning first drop round the west end,
## camelbacks down the south side, a banked turn and the brake run home - on a tube-spine steel
## structure, and a five-car train that runs it.
##
## THE TRACK is data: a rounded rectangle in the park's frame (`CENTRE`, `HALF`, `CORNER`), its
## height profile a table of (s, metres over the deck) eased between keys (`PROFILE`), banked in
## the turns by the speed it is taken at. `point(s)` / `frame(s)` are the whole interface.
##
## THE TRAIN is worked out from the clock, never integrated: `_schedule()` runs the ride once at
## build time - the tyres launch it out of the station, the chain takes it up at CHAIN_SPEED, then
## energy (gravity less rolling friction) to the brakes, which bring it into the station - into a
## table of (time, s); a ride is that table plus DWELL in the station. `lead_s(clock)` is a binary
## search, and each frame the five cars are placed along the track behind it (the only per-frame
## work: five transforms, and only while the park is built in detail). Riders scream on the drop
## (Sfx "scream", real CC0 takes) and the train rolls with the light rail's rolling loop.
##
## Shot, the track and the cars spark and ping like any steel (PierRideBody / the cars' bodies in
## "rail_vehicle") and the ride keeps running. You can stand on the track.

## Centre, half size and corner radius of the track's plan, in the park's frame (metres).
const CENTRE := Vector2(-130.0, 37.0)
const HALF := Vector2(55.0, 19.0)
const CORNER := 17.0
## Rail gauge (centre to centre) and the spine's depth below the rail plane, metres.
const GAUGE := 1.1
const SPINE_DROP := 0.55
## Height profile: (s metres along the track from the station's east end, metres of rail top over
## the deck). The track runs west along the north side from s 0.
const PROFILE: Array[Vector2] = [
	Vector2(0.0, 1.4), Vector2(21.0, 1.4), Vector2(26.0, 2.0), Vector2(58.0, 16.6), Vector2(63.0, 17.4),
	Vector2(68.0, 16.8), Vector2(90.0, 2.6), Vector2(98.0, 2.3), Vector2(116.0, 8.8), Vector2(126.0, 9.2),
	Vector2(146.0, 3.6), Vector2(160.0, 3.4), Vector2(176.0, 8.0), Vector2(188.0, 8.2), Vector2(206.0, 4.0),
	Vector2(226.0, 5.6), Vector2(240.0, 2.4), Vector2(252.0, 1.6), Vector2(266.8, 1.4)]
## Where the chain lift runs (s), and its speed (m/s).
const LIFT := Vector2(24.0, 62.0)
const CHAIN_SPEED := 3.4
## Where the drop begins (s): the riders scream from here.
const DROP_S := 66.0
## The brake run begins here (s) and brakes at this rate (m/s2) down to BRAKE_SPEED.
const BRAKE_S := 238.0
const BRAKE_DECEL := 5.5
const BRAKE_SPEED := 2.2
## Where the lead car stops in the station (s), and how long the train stands there (seconds).
const STOP_S := 17.0
const DWELL := 26.0
## Rolling and air friction as a slope: energy lost per metre, as metres of height.
const FRICTION := 0.016
## Cars in the train and the pitch between them (metres).
const CARS := 5
const CAR_PITCH := 2.35

const TRACK_RED := Color(0.72, 0.10, 0.08)
const SUPPORT := Color(0.86, 0.85, 0.80)
const CAR_COLORS: Array[Color] = [Color(0.06, 0.35, 0.55), Color(0.95, 0.70, 0.10)]

## The track's length (metres), worked out once.
static var length: float = 0.0
## The ride's table: time at each sample and the sample spacing.
static var _t_table: PackedFloat32Array = PackedFloat32Array()
static var _v_table: PackedFloat32Array = PackedFloat32Array()
const SAMPLE := 0.5
static var period: float = 0.0
static var _track_meshes: Dictionary = {}
static var _car_meshes: Array = []

## The park's clock this coaster reads (seconds); advanced in _process unless held.
static var clock: float = 0.0
## Hold the clock (stills): PIER_COASTER=<seconds into the ride>, or PIER_COASTER_S=<s> for the
## lead car at that point of the track, in the environment.
static var hold: float = -1.0

## The deck top in the park's frame (the track's heights are over it).
var deck_y: float = 6.4
var _cars: Array[Node3D] = []
var _last_s: float = 0.0
var _roll: AudioStreamPlayer3D
var _scream_left: int = 0
var _scream_next: float = 0.0
var detailed: bool = true


# --- The track as data ------------------------------------------------------------------------

static func _ensure() -> void:
	if length > 0.0:
		return
	var straight_x := 2.0 * (HALF.x - CORNER)
	var straight_z := 2.0 * (HALF.y - CORNER)
	length = 2.0 * straight_x + 2.0 * straight_z + TAU * CORNER
	_schedule()
	var env := OS.get_environment("PIER_COASTER")
	if env != "":
		hold = float(env)
	env = OS.get_environment("PIER_COASTER_S")
	if env != "":
		hold = clock_at_s(float(env))


## The plan point at s (park frame XZ) and its heading (unit XZ).
static func plan_at(s: float) -> Array:
	_ensure()
	s = fposmod(s, length)
	var sx := 2.0 * (HALF.x - CORNER)
	var sz := 2.0 * (HALF.y - CORNER)
	var arc := PI * 0.5 * CORNER
	var cx := HALF.x - CORNER
	var cz := HALF.y - CORNER
	# North straight, heading -x from the east end, at z = CENTRE.y - HALF.y.
	var legs: Array = [
		[Vector2(cx, -HALF.y), Vector2(-1, 0), sx],
		[Vector2(-cx, -cz), 0.0, arc],      # NW corner: centre, start angle
		[Vector2(-HALF.x, -cz), Vector2(0, 1), sz],
		[Vector2(-cx, cz), 1.0, arc],       # SW
		[Vector2(-cx, HALF.y), Vector2(1, 0), sx],
		[Vector2(cx, cz), 2.0, arc],        # SE
		[Vector2(HALF.x, cz), Vector2(0, -1), sz],
		[Vector2(cx, -cz), 3.0, arc],       # NE
	]
	for leg: Array in legs:
		var n: float = leg[2]
		if s <= n or leg == legs.back():
			if leg[1] is Vector2:
				var d: Vector2 = leg[1]
				return [CENTRE + (leg[0] as Vector2) + d * s, d]
			# Corners turn left (anticlockwise seen from above, +x right, +z down: a heading of
			# -x turns to +z). Angle measured from +x toward +z.
			var q: float = leg[1]
			var a0: float = [-PI * 0.5, PI, PI * 0.5, 0.0][int(q)]
			var a: float = a0 - s / CORNER
			var c: Vector2 = leg[0]
			var p := c + Vector2(cos(a), sin(a)) * CORNER
			var d2 := Vector2(sin(a), -cos(a))
			return [CENTRE + p, d2]
		s -= n
	return [CENTRE, Vector2(1, 0)]


## Rail-top height over the deck at s, eased between the profile's keys.
static func height_at(s: float) -> float:
	_ensure()
	s = fposmod(s, length)
	for i in range(1, PROFILE.size()):
		var b: Vector2 = PROFILE[i]
		if s <= b.x:
			var a: Vector2 = PROFILE[i - 1]
			var f := (s - a.x) / maxf(b.x - a.x, 1e-3)
			return lerpf(a.y, b.y, f * f * (3.0 - 2.0 * f))
	return PROFILE.back().y


## Curvature of the plan at s (1 / radius, 0 on a straight).
static func _curving(s: float) -> float:
	var a: Vector2 = plan_at(s - 1.0)[1]
	var b: Vector2 = plan_at(s + 1.0)[1]
	return absf(a.angle_to(b)) / 2.0


## The bank at s (radians, into the turn), from the speed the train takes it at.
static func bank_at(s: float) -> float:
	var k := 0.0
	for o: float in [-6.0, -3.0, 0.0, 3.0, 6.0]:
		k += _curving(s + o)
	k /= 5.0
	var v := speed_at(s)
	return clampf(atan(v * v * k / 9.81), 0.0, 1.05)


## The rail-plane centre at s (park frame, deck top at `deck`).
static func point(s: float, deck: float) -> Vector3:
	var p: Array = plan_at(s)
	var c: Vector2 = p[0]
	return Vector3(c.x, deck + height_at(s), c.y)


## The track's frame at s: z backward along the track (so -z is the way the train runs), y up
## through the rails (banked), x to the right.
static func frame(s: float, deck: float) -> Basis:
	var a := point(s - 0.6, deck)
	var b := point(s + 0.6, deck)
	var fwd := (b - a).normalized()
	var right := fwd.cross(Vector3.UP).normalized()
	var up := right.cross(fwd).normalized()
	# Bank into the turn (the turns are all to the left: right side up).
	var bank := bank_at(s)
	up = up.rotated(fwd, -bank)
	right = fwd.cross(up).normalized()
	return Basis(right, up, -fwd)


# --- The ride, worked out once ----------------------------------------------------------------

static func _schedule() -> void:
	var n := int(ceil(length / SAMPLE)) + 1
	_t_table.resize(n)
	_v_table.resize(n)
	var t := 0.0
	var v := 0.0
	var h_top := -1.0
	var s_top := 0.0
	var v_top := 0.0
	for i in n:
		var s := STOP_S + float(i) * SAMPLE
		var sl := fposmod(s, length)
		var h := height_at(sl)
		var nv := v
		var on_lift := sl >= LIFT.x and sl <= LIFT.y
		if i == 0:
			nv = 0.0
		elif s < STOP_S + 12.0:
			# The station's tyres push it out.
			nv = minf(sqrt(2.0 * 1.2 * (s - STOP_S)), 2.6)
		elif on_lift:
			nv = CHAIN_SPEED
			h_top = h
			s_top = s
			v_top = CHAIN_SPEED
		else:
			if h_top < 0.0:
				h_top = h
				s_top = s
				v_top = maxf(v, 2.0)
			var e := v_top * v_top + 2.0 * 9.81 * (h_top - h - FRICTION * (s - s_top))
			nv = sqrt(maxf(e, 1.0))
			if s - STOP_S >= BRAKE_S - STOP_S:
				var b2 := maxf(v * v - 2.0 * BRAKE_DECEL * SAMPLE, BRAKE_SPEED * BRAKE_SPEED)
				nv = minf(nv, sqrt(b2))
				h_top = h
				s_top = s
				v_top = nv
			# Into the station: the brakes bring it to a stand at STOP_S.
			var to_go := STOP_S + length - s
			if to_go < 7.0:
				nv = minf(nv, sqrt(maxf(2.0 * 0.9 * to_go, 0.0)))
		if i > 0:
			t += SAMPLE / maxf((v + nv) * 0.5, 0.25)
		v = nv
		_t_table[i] = t
		_v_table[i] = v
	period = t + DWELL


## The train's speed at s (m/s) on the way round (0 in the station).
static func speed_at(s: float) -> float:
	_ensure()
	if _v_table.is_empty():
		return 0.0
	var i := int(fposmod(s - STOP_S, length) / SAMPLE)
	return _v_table[clampi(i, 0, _v_table.size() - 1)]


## The lead car's s at `t` seconds (any clock): DWELL in the station, then the ride.
static func lead_s(t: float) -> float:
	_ensure()
	var tau := fposmod(t, period)
	if tau < DWELL:
		return STOP_S
	tau -= DWELL
	var lo := 0
	var hi := _t_table.size() - 1
	while hi - lo > 1:
		@warning_ignore("integer_division")
		var mid := (lo + hi) / 2
		if _t_table[mid] <= tau:
			lo = mid
		else:
			hi = mid
	var t0 := _t_table[lo]
	var t1 := _t_table[hi]
	var f := clampf((tau - t0) / maxf(t1 - t0, 1e-5), 0.0, 1.0)
	return fposmod(STOP_S + (float(lo) + f) * SAMPLE, length)


## Seconds into the ride when the lead car first reaches `s` (stills).
static func clock_at_s(s: float) -> float:
	_ensure()
	var i := int(fposmod(s - STOP_S, length) / SAMPLE)
	return DWELL + _t_table[clampi(i, 0, _t_table.size() - 1)]


# --- Building ---------------------------------------------------------------------------------

## The track, its supports and the station, standing on the park deck (park frame: `parent` is
## the park node). Returns the coaster node, which runs the train when `detailed`.
static func build(parent: Node3D, deck: float, detailed_build: bool) -> PierCoaster:
	_ensure()
	var node := PierCoaster.new()
	node.name = "Coaster"
	node.deck_y = deck
	node.detailed = detailed_build
	parent.add_child(node)
	var key := "near" if detailed_build else "far"
	if not _track_meshes.has(key):
		_track_meshes[key] = _track_mesh(deck, detailed_build)
	var mi := MeshInstance3D.new()
	mi.name = "Track"
	mi.mesh = _track_meshes[key]
	if not detailed_build:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(mi)
	if detailed_build:
		node._add_body()
		node._add_train()
	return node


static func _track_mesh(deck: float, detailed_build: bool) -> ArrayMesh:
	var g := PierMesh.new()
	g.use("t", PierMesh.material("park"))
	g.slot("t")
	var step := 1.0 if detailed_build else 4.0
	var n := int(length / step)
	var rails: Array[PackedVector3Array] = [PackedVector3Array(), PackedVector3Array(), PackedVector3Array()]
	for i in n:
		var s := float(i) * step
		var p := point(s, deck)
		var b := frame(s, deck)
		rails[0].append(p - b.x * GAUGE * 0.5)
		rails[1].append(p + b.x * GAUGE * 0.5)
		rails[2].append(p - b.y * SPINE_DROP)
	g.kind = PierMesh.K_METAL
	if detailed_build:
		g.sweep(rails[0], 0.055, TRACK_RED.lightened(0.1), 6, true)
		g.sweep(rails[1], 0.055, TRACK_RED.lightened(0.1), 6, true)
	g.kind = PierMesh.K_PAINT
	g.sweep(rails[2], 0.21 if detailed_build else 0.5, TRACK_RED, 8 if detailed_build else 4, true)
	if detailed_build:
		# Ties: a C-frame every 1.2 m from the spine out to each rail.
		var s := 0.0
		while s < length:
			var p := point(s, deck)
			var b := frame(s, deck)
			var spine := p - b.y * SPINE_DROP
			for side: float in [-1.0, 1.0]:
				var r := p + b.x * side * GAUGE * 0.5
				g.tube(spine, r - b.y * 0.06, 0.045, 0.045, TRACK_RED, 4)
			s += 1.2
		# The chain up the lift and its catwalk with a hand rail on the outside.
		g.kind = PierMesh.K_RUBBER
		var lift_pts := PackedVector3Array()
		s = LIFT.x
		while s <= LIFT.y:
			lift_pts.append(point(s, deck) - frame(s, deck).y * 0.08)
			s += 1.0
		g.sweep(lift_pts, 0.06, Color(0.1, 0.1, 0.1), 4)
		g.kind = PierMesh.K_METAL
		s = LIFT.x + 2.0
		var rail_pts := PackedVector3Array()
		while s <= LIFT.y + 2.0:
			var p := point(s, deck)
			var b := frame(s, deck)
			var walk := p + b.x * -1.35 - b.y * 0.35
			g.box(Transform3D(b, walk), Vector3(0.7, 0.05, 1.0), SUPPORT)
			rail_pts.append(walk + b.x * -0.35 + Vector3.UP * 1.0)
			if int(s) % 2 == 0:
				g.tube(walk + b.x * -0.35, walk + b.x * -0.35 + Vector3.UP * 1.0, 0.025, 0.025, SUPPORT, 4)
			s += 1.0
		g.sweep(rail_pts, 0.03, SUPPORT, 4)
	# Supports: a column (two splayed and braced where the track is high) every few metres.
	g.kind = PierMesh.K_PAINT
	var sides := 8 if detailed_build else 4
	for sp: Array in supports(deck):
		var spine: Vector3 = sp[0]
		var feet: Array = sp[1]
		var h := spine.y - deck
		if feet.size() == 1:
			var foot: Vector3 = feet[0]
			g.tube(foot, spine, 0.16 if h < 2.0 else 0.24, 0.16 if h < 2.0 else 0.2, SUPPORT, sides)
			if detailed_build and h >= 2.0:
				g.abox(foot + Vector3(0, 0.1, 0), Vector3(0.8, 0.2, 0.8), Color(0.6, 0.6, 0.6))
		else:
			var fa: Vector3 = feet[0]
			var fb: Vector3 = feet[1]
			g.tube(fa, spine, 0.24, 0.18, SUPPORT, sides)
			g.tube(fb, spine, 0.24, 0.18, SUPPORT, sides)
			if detailed_build:
				for f: float in [0.35, 0.65]:
					g.tube(fa.lerp(spine, f), fb.lerp(spine, f), 0.08, 0.08, SUPPORT, 5)
				g.tube(fa.lerp(spine, 0.35), fb.lerp(spine, 0.65), 0.06, 0.06, SUPPORT, 4)
				g.abox(fa + Vector3(0, 0.1, 0), Vector3(0.8, 0.2, 0.8), Color(0.6, 0.6, 0.6))
				g.abox(fb + Vector3(0, 0.1, 0), Vector3(0.8, 0.2, 0.8), Color(0.6, 0.6, 0.6))
	if detailed_build:
		_station(g, deck)
	return g.build_mesh()


## The track's supports: [spine point, [feet on the deck]] - one column where the track is low, a
## splayed and braced pair across it where it is high. The checks keep the crowd's walks off them.
static func supports(deck: float) -> Array:
	_ensure()
	var out: Array = []
	var ss := 3.0
	while ss < length:
		var h := height_at(ss)
		var p := point(ss, deck)
		var b := frame(ss, deck)
		var spine := p - b.y * SPINE_DROP
		var foot := Vector3(spine.x, deck, spine.z)
		if h < 8.0:
			out.append([spine, [foot]])
		else:
			var side := Vector3(b.x.x, 0.0, b.x.z).normalized()
			var spread := 0.12 * h
			out.append([spine, [foot + side * spread, foot - side * spread]])
		ss += 4.0 if h < 8.0 else 5.0
	return out


## The station: a raised loading platform along the track with a canopy, the name board, the
## exit stair and gates.
static func _station(g: PierMesh, deck: float) -> void:
	var a: Vector2 = plan_at(1.0)[0]
	var b: Vector2 = plan_at(21.0)[0]
	var cx := (a.x + b.x) * 0.5
	var z := a.y
	var top := deck + 1.4 - 0.75
	g.kind = PierMesh.K_BOARDS
	# Platforms either side of the track.
	for side: float in [-1.0, 1.0]:
		g.abox(Vector3(cx, (deck + top) * 0.5, z + side * 2.2), Vector3(22.0, top - deck, 2.6), Color(0.52, 0.40, 0.28))
	# Canopy on posts, a coral sign band with the ride's name both ways.
	g.kind = PierMesh.K_PAINT
	for x in [cx - 10.0, cx - 3.3, cx + 3.3, cx + 10.0]:
		for side: float in [-1.0, 1.0]:
			g.tube(Vector3(x, top, z + side * 3.3), Vector3(x, top + 3.6, z + side * 3.3), 0.1, 0.1, SUPPORT, 8)
	g.kind = PierMesh.K_CANVAS
	g.abox(Vector3(cx, top + 3.75, z), Vector3(23.0, 0.3, 7.6), Color(0.85, 0.15, 0.12))
	g.kind = PierMesh.K_PAINT
	g.abox(Vector3(cx, top + 4.4, z - 3.6), Vector3(12.0, 1.0, 0.25), Color(0.05, 0.25, 0.42))
	g.kind = PierMesh.K_NEON
	g.letters("KELP CRACKER", 0.62, Transform3D(Basis(Vector3.UP, PI), Vector3(cx, top + 4.4, z - 3.74)), Color(1.0, 0.85, 0.25), 11.0)
	# Gates along the platform edge and a rail round the outside.
	g.kind = PierMesh.K_METAL
	for side: float in [-1.0, 1.0]:
		g.tube(Vector3(cx - 11.0, top + 1.0, z + side * 3.45), Vector3(cx + 11.0, top + 1.0, z + side * 3.45), 0.035, 0.035, SUPPORT, 6)
	var x := cx - 9.0
	while x < cx + 10.0:
		g.abox(Vector3(x, top + 0.5, z - 1.05), Vector3(1.2, 0.9, 0.05), Color(0.75, 0.75, 0.72))
		x += 2.35
	# Steps up from the deck at the east end.
	for k in 4:
		var h := (top - deck) * float(k + 1) / 5.0
		g.kind = PierMesh.K_BOARDS
		g.abox(Vector3(cx + 11.0 + 0.3 * float(4 - k), deck + h * 0.5, z - 2.2), Vector3(0.3, h, 2.2), Color(0.52, 0.40, 0.28))


## One car: a tub with a rounded nose (the lead car's is longer), two rows of seats with tall
## head rests, lap bars, the wheel carriers under the rails. Car frame: -z forward, origin at the
## rail plane under its middle.
static func _car_mesh(lead: bool) -> ArrayMesh:
	var g := PierMesh.new()
	g.use("c", PierMesh.material("park"))
	g.slot("c")
	var body: Color = CAR_COLORS[0]
	var trim: Color = CAR_COLORS[1]
	var floor_y := 0.32
	g.kind = PierMesh.K_PAINT
	# Floor pan and the sides.
	g.box(Transform3D(Basis(), Vector3(0, floor_y, 0)), Vector3(1.45, 0.12, 2.05), body, 0.2)
	for side: float in [-1.0, 1.0]:
		g.box(Transform3D(Basis(), Vector3(side * 0.69, floor_y + 0.38, 0.0)), Vector3(0.08, 0.7, 2.0), body, 0.02)
	g.box(Transform3D(Basis(), Vector3(0, floor_y + 0.33, 0.98)), Vector3(1.42, 0.6, 0.08), body, 0.02)
	# The nose: a lead car's sweeps forward and up into a cowl.
	if lead:
		g.ellipsoid(Transform3D(Basis(), Vector3(0, floor_y + 0.32, -1.0)), Vector3(0.72, 0.42, 0.75), body, 12, 7)
		g.kind = PierMesh.K_GOLD
		g.ellipsoid(Transform3D(Basis(), Vector3(0, floor_y + 0.36, -1.72)), Vector3(0.12, 0.12, 0.06), trim, 6, 4)
		g.kind = PierMesh.K_PAINT
	else:
		g.box(Transform3D(Basis(), Vector3(0, floor_y + 0.33, -0.98)), Vector3(1.42, 0.6, 0.08), body, 0.02)
	# A trim stripe down each side.
	for side: float in [-1.0, 1.0]:
		g.abox(Vector3(side * 0.735, floor_y + 0.52, 0.0), Vector3(0.012, 0.09, 1.96), trim)
	# Two rows of seats: cushion, back with a head rest, and a lap bar.
	for row: float in [-0.45, 0.48]:
		g.kind = PierMesh.K_RUBBER
		g.box(Transform3D(Basis(), Vector3(0, floor_y + 0.28, row + 0.05)), Vector3(1.25, 0.14, 0.5), Color(0.05, 0.05, 0.05), 0.05)
		g.box(Transform3D(Basis(Vector3.RIGHT, -0.18), Vector3(0, floor_y + 0.62, row + 0.33)), Vector3(1.25, 0.62, 0.12), Color(0.05, 0.05, 0.05), 0.04)
		g.kind = PierMesh.K_PAINT
		for side: float in [-0.32, 0.32]:
			g.box(Transform3D(Basis(Vector3.RIGHT, -0.18), Vector3(side, floor_y + 1.02, row + 0.4)), Vector3(0.38, 0.32, 0.1), body.darkened(0.2), 0.04)
		g.kind = PierMesh.K_CHROME
		var bar := PackedVector3Array([Vector3(-0.66, floor_y + 0.5, row - 0.05), Vector3(-0.5, floor_y + 0.62, row - 0.2),
			Vector3(0.5, floor_y + 0.62, row - 0.2), Vector3(0.66, floor_y + 0.5, row - 0.05)])
		g.sweep(bar, 0.025, Color(0.8, 0.8, 0.8), 5)
	# Wheel carriers: a block under each end with the road wheels on the rails.
	g.kind = PierMesh.K_METAL
	for zz: float in [-0.65, 0.65]:
		g.abox(Vector3(0, 0.12, zz), Vector3(GAUGE + 0.16, 0.14, 0.35), Color(0.35, 0.35, 0.35))
		for side: float in [-1.0, 1.0]:
			g.kind = PierMesh.K_RUBBER
			g.tube(Vector3(side * GAUGE * 0.5 - 0.06, 0.09, zz), Vector3(side * GAUGE * 0.5 + 0.06, 0.09, zz), 0.09, 0.09, Color(0.1, 0.1, 0.1), 8, true)
			g.kind = PierMesh.K_METAL
	return g.build_mesh()


## Inner body for a car: shot, it sparks; it keeps going.
class CarBody extends AnimatableBody3D:
	var hits := 0

	func _init() -> void:
		collision_layer = 1
		collision_mask = 0
		sync_to_physics = false
		add_to_group("rail_vehicle")
		add_to_group("pier_ride")

	func take_hit(_shape: int = -1, _damage: float = 0.0, _dir: Vector3 = Vector3.ZERO, _at: Vector3 = Vector3.ZERO, _kind: int = 0) -> void:
		hits += 1


func _add_body() -> void:
	var body := PierRideBody.new()
	body.name = "TrackBody"
	add_child(body)
	# The spine and the rails' bed as boxes a few metres long (you can walk the track).
	var s := 0.0
	while s < length:
		var a := point(s, deck_y)
		var b := point(s + 3.0, deck_y)
		var f := frame(s + 1.5, deck_y)
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(GAUGE + 0.2, 0.5, a.distance_to(b) + 0.05)
		cs.shape = bs
		cs.transform = Transform3D(f, (a + b) * 0.5 - f.y * 0.25)
		body.add_child(cs)
		s += 3.0


func _add_train() -> void:
	if _car_meshes.is_empty():
		_car_meshes = [_car_mesh(true), _car_mesh(false)]
	var s0 := lead_s(_now())
	for i in CARS:
		var car := CarBody.new()
		car.name = "Car%d" % i
		var s := s0 - float(i) * CAR_PITCH
		car.transform = Transform3D(frame(s, deck_y), point(s, deck_y))
		var mi := MeshInstance3D.new()
		mi.mesh = _car_meshes[0 if i == 0 else 1]
		car.add_child(mi)
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(1.5, 1.1, 2.1)
		cs.shape = bs
		cs.position = Vector3(0, 0.75, 0)
		car.add_child(cs)
		add_child(car)
		_cars.append(car)
	_last_s = s0
	var sfx := get_node_or_null("/root/Sfx")
	if sfx and sfx.has_method("loop_player"):
		_roll = sfx.loop_player("rail_roll", -4.0)
		_cars[0].add_child(_roll)


func _now() -> float:
	return hold if hold >= 0.0 else clock


func _process(delta: float) -> void:
	if hold < 0.0:
		clock += delta
	if _cars.is_empty():
		return
	var s0 := lead_s(_now())
	for i in _cars.size():
		var s := s0 - float(i) * CAR_PITCH
		_cars[i].transform = Transform3D(frame(s, deck_y), point(s, deck_y))
	var v := speed_at(s0)
	if _roll:
		if v > 0.5 and not _roll.playing:
			_roll.play()
		elif v <= 0.5 and _roll.playing:
			_roll.stop()
		_roll.pitch_scale = clampf(0.6 + v / 14.0, 0.6, 1.8)
		_roll.volume_db = linear_to_db(clampf(v / 12.0, 0.05, 1.0)) - 2.0
	# Over the top and down: a few riders scream, staggered.
	var crossed := _last_s < DROP_S and s0 >= DROP_S and s0 - _last_s < 20.0
	_last_s = s0
	if crossed:
		_scream_left = 3
		_scream_next = 0.0
	if _scream_left > 0:
		_scream_next -= delta
		if _scream_next <= 0.0:
			var sfx := get_node_or_null("/root/Sfx")
			if sfx and sfx.has_method("play"):
				var car: Node3D = _cars[mini(3 - _scream_left, _cars.size() - 1)]
				sfx.play("scream", car.global_position, -2.0, 1.05)
			_scream_left -= 1
			_scream_next = 0.35
