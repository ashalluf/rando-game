class_name SkateParkLife
extends Node3D
## The people at THE PIT (SkatePark): skaters riding their lines and spectators round the edges.
## A child of the park's root, so its space is the park's own frame (+X inland, +Z up the beach).
##
## **Lines are worked out, never simulated.** Each line (lines()) is a closed loop of waypoints in
## the park's plan - round the pool high on its walls with an air over the coping and a grind on
## it, down the snake run weaving bank to bank and out over its tail, back and forth on the mini
## ramp with airs and kick turns at the lips, the street section (onto the ledge, the flat bar,
## over the funbox, a manual down the pad, kickflips off them), the stair set (a kickflip down the
## nine, back up the bank) - each segment ridden, ollied (an arc between its ends), kickflipped
## (the arc, the board rolled a turn about its own length under the rider) or ground (held at a
## rail's or a coping's height). sample() turns a line into a table at 30 Hz once: position on
## the real surface (SkatePark.surface_y(), the numbers the concrete is built from), the surface's
## up (smoothed), the way it goes, which pose, how far round the flip is. A skater plays its table
## from the clock with its own offset: nothing ticks but a lookup and a transform.
##
## **People are baked figures** (SkaterPerson posed once per pose, CampFigure._bake()): a skater
## is ONE MeshInstance3D swapped between four poses plus a board, a spectator one mesh. Each has a
## body on the npc layer (rounds, blasts, bumpers find it); hit - or near gunfire or a blast - it
## becomes a live SkaterPerson where it was, who takes the hit and runs, and a skater's board is
## thrown on as debris. Baking needs mesh data (none headless): there the figures draw nothing
## and everything else works. Baked a figure a frame, never more.

## The park's anchor (the boardwalk's), for the hashes.
var anchor := Vector2.ZERO
var _clock: float = 0.0
var _skaters: Array = []
var _spectators: Array = []
var _bake_queue: Array = []
var _alarm_ms: int = -1
var _blasts: int = -1
var _bail_queue: Array = []
var _bail_wait: float = 0.0

## SKATE_T=<seconds> sets the clock (stills), SKATE_HOLD=1 holds it.
static var hold: bool = OS.get_environment("SKATE_HOLD") == "1"
## Lines by name, sampled (sample()).
static var _tables: Dictionary = {}
static var _figures: Dictionary = {}
static var _boards: Dictionary = {}

const RATE := 30.0
## How far an alarm or a blast is heard (m, from the park's centre), and how many people one wakes.
const ALARM_REACH := 55.0
const WAKE_PER_ALARM := 5
## Crowd rigs that skate and watch (indices into Pedestrian.MODELS; the younger ones).
const MODELS := [0, 3, 7, 8, 11, 12, 14, 16, 20, 22]
const POSE_NAMES := ["ride", "crouch", "air", "grind"]
const P_RIDE := 0
const P_CROUCH := 1
const P_AIR := 2
const P_GRIND := 3
## Board deck colours (the graphic underneath; the top is grip).
const BOARD_PAINTS: Array[Color] = [Color(0.6, 0.05, 0.04), Color(0.05, 0.12, 0.42), Color(0.75, 0.55, 0.05),
	Color(0.08, 0.32, 0.12), Color(0.05, 0.05, 0.05), Color(0.82, 0.8, 0.76), Color(0.5, 0.12, 0.42)]
## Who rides what: [line, phase (s), speed scale].
const RIDERS := [["pool", 0.0, 1.0], ["pool", 5.2, 0.92], ["snake", 0.0, 1.0], ["mini", 0.0, 1.0],
	["street", 0.0, 1.0], ["street", 11.0, 0.95], ["stairs", 0.0, 1.0]]
## Spectators: [park-local XZ, y over the sand, yaw (the way they face, +Z = 0), pose].
const SPECTATORS := [
	[Vector2(-12.6, -0.25), SkatePark.H_HI, 0.0, "sit_edge"],
	[Vector2(-10.9, -0.25), SkatePark.H_HI, 0.0, "sit_edge"],
	[Vector2(-14.0, -0.25), SkatePark.H_HI, 0.0, "sit_edge"],
	[Vector2(13.2, -15.0), SkatePark.H_HI, -PI * 0.5, "fold"],
	[Vector2(5.0, -21.2), SkatePark.H_HI, PI, "watch"],
	[Vector2(14.0, 19.0), SkatePark.H_LO, -PI * 0.5, "fold"],
	[Vector2(14.2, 10.6), SkatePark.H_LO, -PI * 0.55, "watch"],
	[Vector2(-5.6, 20.6), SkatePark.H_LO, PI * 0.8, "watch"],
]


func _ready() -> void:
	var env := OS.get_environment("SKATE_T")
	if env != "":
		_clock = env.to_float()
	for i in RIDERS.size():
		var r: Array = RIDERS[i]
		var sk := Skater.new()
		sk.name = "Skater%d" % i
		sk.life = self
		sk.line = r[0]
		sk.phase = r[1]
		sk.pace = r[2]
		var h := _h(i)
		sk.model = int(MODELS[h % MODELS.size()])
		sk.seed_value = BeachGoer.seed_for(sk.model, 300 + i)
		sk.goofy = (h >> 5) % 3 == 0
		sk.paint = BOARD_PAINTS[(h >> 9) % BOARD_PAINTS.size()]
		add_child(sk)
		_skaters.append(sk)
		for p: String in POSE_NAMES:
			_bake_queue.append([sk.seed_value, p])
	for i in SPECTATORS.size():
		var s: Array = SPECTATORS[i]
		var sp := Spectator.new()
		sp.name = "Spectator%d" % i
		sp.life = self
		var h := _h(100 + i)
		sp.model = int(MODELS[(h >> 3) % MODELS.size()])
		sp.seed_value = BeachGoer.seed_for(sp.model, 400 + i)
		sp.pose_key = s[3]
		sp.position = Vector3((s[0] as Vector2).x, float(s[1]), (s[0] as Vector2).y)
		sp.rotation.y = float(s[2])
		add_child(sp)
		_spectators.append(sp)
		_bake_queue.append([sp.seed_value, sp.pose_key])
	_alarm_ms = Pedestrian._last_alarm_ms
	_blasts = Explosion.blast_count
	_place_all()


func _h(k: int) -> int:
	return absi(hash([int(anchor.x), int(anchor.y), k, "skate_park"]))


func _physics_process(delta: float) -> void:
	if not hold:
		_clock += delta
	# One figure baked a frame (each is tens of milliseconds).
	if not _bake_queue.is_empty():
		var job: Array = _bake_queue.pop_front()
		figure(int(job[0]), String(job[1]))
		for s in _skaters + _spectators:
			if is_instance_valid(s):
				s.refresh()
	_place_all()
	_listen(delta)


func _place_all() -> void:
	for s in _skaters:
		if is_instance_valid(s):
			s.place(_clock)


func clock() -> float:
	return _clock


func set_clock(t: float) -> void:
	_clock = t
	_place_all()


## Gunfire or a blast near the park: the nearest people wake and run, the rest a few at a time.
func _listen(delta: float) -> void:
	var centre := global_position
	var heard := false
	if Pedestrian._last_alarm_ms != _alarm_ms:
		_alarm_ms = Pedestrian._last_alarm_ms
		if Pedestrian._last_alarm_at != Vector3.INF and Pedestrian._last_alarm_at.distance_to(centre) < ALARM_REACH:
			heard = true
	if Explosion.blast_count != _blasts:
		_blasts = Explosion.blast_count
		heard = true
	if heard:
		var near: Array = []
		for n in _skaters + _spectators:
			if is_instance_valid(n) and not n.gone:
				near.append([(n as Node3D).global_position.distance_squared_to(Pedestrian._last_alarm_at if Pedestrian._last_alarm_at != Vector3.INF else centre), n])
		near.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
		for i in mini(WAKE_PER_ALARM, near.size()):
			if not _bail_queue.has(near[i][1]):
				_bail_queue.append(near[i][1])
	_bail_wait -= delta
	if not _bail_queue.is_empty() and _bail_wait <= 0.0:
		var n: Node = _bail_queue.pop_front()
		_bail_wait = 0.12
		if is_instance_valid(n):
			n.wake(Vector3.ZERO)


## How many skaters and spectators are still figures (the checks).
func figures_left() -> int:
	var n := 0
	for s in _skaters + _spectators:
		if is_instance_valid(s) and not s.gone:
			n += 1
	return n


func skaters() -> Array:
	return _skaters


func spectators() -> Array:
	return _spectators


## The live person a figure becomes at `xf` (in this node's space): a SkaterPerson under the chunk,
## in the pose's place, who takes the round or the knock.
func spawn_person(seed_value: int, xf: Transform3D) -> SkaterPerson:
	var holder := get_parent().get_parent() as Node3D
	if holder == null:
		return null
	var root := get_parent() as Node3D
	var at := root.transform * xf.origin
	var park_rect := Rect2(root.position.x - SkatePark.HALF_W - 6.0, root.position.z - SkatePark.HALF_L - 6.0,
		SkatePark.HALF_W * 2.0 + 20.0, SkatePark.HALF_L * 2.0 + 12.0)
	var ped := SkaterPerson.new()
	var fwd := -(root.basis * xf.basis).z
	ped.setup_sleeper(park_rect, 4.0, seed_value, RoughSleeper.Pose.STAND, Vector2(at.x, at.z), atan2(-fwd.x, -fwd.z))
	ped.park_origin = root.position
	ped.position = at
	if holder.has_method("_take_crowd_room"):
		holder._take_crowd_room()
	holder.add_child(ped)
	return ped


# --- Figures ---------------------------------------------------------------------------------------

## The baked figure of person `seed_value` (a crowd rig) holding `pose` (SkaterPerson.POSES_SKATE),
## feet at the origin, the board's axis along x; null without mesh data (or not baked yet).
static func figure(seed_value: int, pose: String) -> Mesh:
	var key := "%d|%s" % [seed_value, pose]
	if _figures.has(key):
		return _figures[key]
	_figures[key] = null
	var host := BeachFigure._bake_parent()
	if host == null:
		return null
	var ped := SkaterPerson.new()
	ped.setup_sleeper(Rect2(0.0, 0.0, 10.0, 10.0), 2.0, seed_value, RoughSleeper.Pose.STAND, Vector2.ZERO, 0.0)
	ped.skate_pose = pose
	host.add_child(ped)
	if ped._visual:
		ped._visual.scale = Vector3.ONE
		ped._visual.position = Vector3.ZERO
	BeachFigure._refresh(ped)
	var mesh := CampFigure._bake(ped, Pedestrian.mid_triangles)
	BeachFigure._drop(ped)
	_figures[key] = mesh
	return mesh


## The board: a 8 1/4" deck with its kicks and grip, trucks, wheels; the wheels' bottoms at y 0,
## the deck's top at BOARD_TOP, along x. Built once, on SkatePark's material.
const BOARD_TOP := 0.105

static func board_mesh(paint: Color = Color(0.6, 0.05, 0.04)) -> ArrayMesh:
	var bkey := paint.to_html()
	if _boards.has(bkey):
		return _boards[bkey]
	var g := SkatePark.Geo.new(true)
	var half := 0.4
	var w := 0.105
	var n := 12
	var top := PackedFloat32Array()
	var xs := PackedFloat32Array()
	for i in n + 1:
		var x := lerpf(-half, half, float(i) / float(n))
		var k := maxf(absf(x) - 0.26, 0.0) / 0.14
		xs.append(x)
		top.append(BOARD_TOP + 0.055 * k * k)
	for i in n:
		var x0 := xs[i]
		var x1 := xs[i + 1]
		var y0 := top[i]
		var y1 := top[i + 1]
		var ww0 := w * (1.0 - 0.35 * pow(maxf(absf(x0) - 0.3, 0.0) / 0.1, 2.0))
		var ww1 := w * (1.0 - 0.35 * pow(maxf(absf(x1) - 0.3, 0.0) / 0.1, 2.0))
		var nrm := Vector3(-(y1 - y0), x1 - x0, 0.0).normalized()
		g.quad(Vector3(x0, y0, -ww0), Vector3(x1, y1, -ww1), Vector3(x1, y1, ww1), Vector3(x0, y0, ww0), nrm, SkatePark.K_GRIP)
		g.quad(Vector3(x0, y0 - 0.013, -ww0), Vector3(x1, y1 - 0.013, -ww1), Vector3(x1, y1 - 0.013, ww1), Vector3(x0, y0 - 0.013, ww0), -nrm, SkatePark.K_PAINT, paint)
		for s: float in [-1.0, 1.0]:
			g.quad(Vector3(x0, y0, s * ww0), Vector3(x1, y1, s * ww1), Vector3(x1, y1 - 0.013, s * ww1), Vector3(x0, y0 - 0.013, s * ww0), Vector3(0.0, 0.0, s), SkatePark.K_WOOD)
	for s: float in [-1.0, 1.0]:
		var e := s * half
		var y := top[0 if s < 0.0 else n]
		g.quad(Vector3(e, y, -w * 0.65), Vector3(e, y, w * 0.65), Vector3(e, y - 0.013, w * 0.65), Vector3(e, y - 0.013, -w * 0.65), Vector3(s, 0.0, 0.0), SkatePark.K_WOOD)
	for tx: float in [-0.23, 0.23]:
		var steel := Color(0.62, 0.63, 0.64)
		g.quad(Vector3(tx - 0.04, BOARD_TOP - 0.016, -0.04), Vector3(tx + 0.04, BOARD_TOP - 0.016, -0.04), Vector3(tx + 0.04, BOARD_TOP - 0.016, 0.04), Vector3(tx - 0.04, BOARD_TOP - 0.016, 0.04), Vector3.DOWN, SkatePark.K_STEEL, steel)
		g.tube(Vector3(tx, BOARD_TOP - 0.016, 0.0), Vector3(tx, 0.03, 0.0), 0.012, 6, SkatePark.K_STEEL, steel)
		g.tube(Vector3(tx, 0.028, -0.105), Vector3(tx, 0.028, 0.105), 0.011, 6, SkatePark.K_STEEL, steel)
		for z: float in [-0.085, 0.085]:
			_wheel(g, Vector3(tx, 0.028, z), 0.028, 0.03)
	_boards[bkey] = g.commit(SkatePark.material())
	return _boards[bkey]


static func _wheel(g: SkatePark.Geo, c: Vector3, r: float, wdt: float) -> void:
	var sides := 12
	for k in sides:
		var a0 := TAU * float(k) / float(sides)
		var a1 := TAU * float(k + 1) / float(sides)
		var d0 := Vector3(cos(a0), sin(a0), 0.0)
		var d1 := Vector3(cos(a1), sin(a1), 0.0)
		var hz := Vector3(0.0, 0.0, wdt * 0.5)
		g.quad_n([c + d0 * r - hz, c + d1 * r - hz, c + d1 * r + hz, c + d0 * r + hz], [d0, d1, d1, d0], SkatePark.K_WHEEL)
		for s: float in [-1.0, 1.0]:
			g.tri(c + hz * s, c + d0 * r + hz * s, c + d1 * r + hz * s, Vector3(0.0, 0.0, s), SkatePark.K_WHEEL)


# --- Lines ---------------------------------------------------------------------------------------

## The lines' waypoints: [park-local XZ, speed (m/s) of the segment from it, event, height].
## Events: "" ride, "ollie" (an arc of `height` from this point to the next), "flip" (the same
## with a kickflip), "grind" (held `height` over the surface: a rail, a coping), "turn" (an air
## turned round: the way it goes swings half a turn).
static func lines() -> Dictionary:
	var out := {}
	out["pool"] = _pool_line()
	out["snake"] = _snake_line()
	out["mini"] = _mini_line()
	out["street"] = [
		[Vector2(7.7, 19.0), 4.5, "", 0.0], [Vector2(7.25, 17.2), 4.6, "", 0.0], [Vector2(6.95, 16.4), 4.6, "ollie", 0.5],
		[Vector2(6.8, 15.2), 4.4, "grind", 0.0], [Vector2(6.8, 6.3), 4.4, "ollie", 0.25], [Vector2(6.85, 4.7), 4.6, "", 0.0],
		[Vector2(7.7, 3.95), 4.4, "", 0.0], [Vector2(9.1, 4.1), 4.4, "", 0.0], [Vector2(10.1, 4.9), 4.6, "ollie", 0.55],
		[Vector2(10.2, 6.25), 4.4, "grind", 0.39], [Vector2(10.2, 12.95), 4.6, "flip", 0.55], [Vector2(10.45, 14.6), 4.8, "", 0.0],
		[Vector2(10.6, 15.0), 4.4, "", 0.0], [Vector2(10.6, 17.6), 4.6, "flip", 0.45], [Vector2(10.6, 20.4), 4.4, "", 0.0],
		[Vector2(9.4, 21.2), 4.0, "", 0.0], [Vector2(6.0, 21.25), 4.2, "", 0.0], [Vector2(3.6, 20.3), 4.2, "", 0.0],
		[Vector2(3.5, 17.0), 4.4, "", 0.0], [Vector2(3.5, 14.5), 4.2, "ollie", 0.45], [Vector2(3.5, 13.0), 3.8, "", 0.0],
		[Vector2(3.5, 6.8), 4.2, "flip", 0.5], [Vector2(3.55, 4.9), 4.2, "", 0.0], [Vector2(4.5, 4.4), 4.0, "", 0.0],
		[Vector2(5.4, 5.6), 4.0, "", 0.0], [Vector2(5.5, 12.0), 4.2, "", 0.0], [Vector2(5.6, 18.0), 3.2, "", 0.0],
		[Vector2(6.4, 19.9), 3.0, "", 0.0],
	]
	out["stairs"] = [
		[Vector2(12.4, 4.3), 3.8, "", 0.0], [Vector2(12.6, 2.6), 3.4, "", 0.0], [Vector2(12.5, 0.6), 3.2, "", 0.0],
		[Vector2(11.0, -1.9), 4.0, "", 0.0], [Vector2(6.0, -1.9), 4.4, "", 0.0], [Vector2(0.6, -1.8), 4.0, "", 0.0],
		[Vector2(-1.6, -3.4), 3.6, "", 0.0], [Vector2(-1.7, -8.5), 3.0, "", 0.0], [Vector2(-1.3, -10.6), 2.6, "", 0.0],
		[Vector2(-1.0, -8.5), 3.6, "", 0.0], [Vector2(-1.0, -4.0), 4.6, "", 0.0], [Vector2(0.6, -1.4), 5.4, "", 0.0],
		[Vector2(2.4, -0.25), 5.6, "flip", 0.7], [Vector2(2.2, 4.7), 5.0, "", 0.0], [Vector2(2.5, 5.4), 4.6, "", 0.0],
		[Vector2(3.6, 5.3), 4.6, "", 0.0], [Vector2(5.6, 4.95), 4.6, "", 0.0], [Vector2(8.6, 4.55), 4.4, "", 0.0],
		[Vector2(11.2, 5.3), 3.8, "", 0.0],
	]
	return out


## Round the pool, high on its walls: two pumps a lap, a frontside air over the coping, a grind
## along it.
static func _pool_line() -> Array:
	var rim := SkatePark.pool_rim(56)
	var inward := SkatePark._inward(rim)
	var n := rim.size()
	var rt := SkatePark.POOL_RT
	var out: Array = []
	for i in n:
		var u := float(i) / float(n)
		# How far in from the rim (m): high on the walls, two pumps a lap.
		var d := rt * (0.42 + 0.16 * cos(u * TAU * 2.0))
		var ev := ""
		var h := 0.0
		var spd := 5.2
		match i:
			10:
				d = 0.3
				ev = "ollie"
				h = 1.9
			11:
				d = 0.32
			33:
				d = 0.3
				ev = "ollie"
				h = 0.3
			34, 35, 36:
				d = -0.02
				ev = "grind"
				h = SkatePark.CAP_H
				spd = 4.4
			37:
				d = -0.02
				ev = "ollie"
				h = 0.2
			38:
				d = 0.4
		out.append([rim[i] + inward[i] * d, spd, ev, h])
	return out


## Down the snake run weaving bank to bank, up its tail and out onto the deck, back up the deck
## to the head and in again.
static func _snake_line() -> Array:
	var out: Array = []
	var z0 := SkatePark.SNAKE_Z0
	var z1 := SkatePark.SNAKE_Z1
	out.append([Vector2(-3.6, -17.4), 4.2, "", 0.0])
	out.append([Vector2(-5.0, -17.8), 4.6, "ollie", 0.25])
	var steps := 5
	for k in steps:
		var z := lerpf(z0 + 0.8, z1 - 0.6, float(k) / float(steps - 1))
		var side := 1.0 if k % 2 == 0 else -1.0
		var x := SkatePark.snake_x(z) + side * 1.75
		out.append([Vector2(x, z), 5.2 + 0.2 * float(k), "", 0.0])
	# Up the tail and out over its lip onto the deck.
	var tail := Vector2(SkatePark.snake_x(z1), z1)
	out.append([tail + Vector2(0.4, 1.55), 3.4, "ollie", 0.55])
	out.append([tail + Vector2(1.6, 3.5), 3.6, "", 0.0])
	out.append([Vector2(-4.4, -1.3), 4.0, "", 0.0])
	out.append([Vector2(-3.6, -4.0), 4.2, "", 0.0])
	out.append([Vector2(-3.6, -12.0), 4.2, "", 0.0])
	out.append([Vector2(-3.4, -16.0), 4.0, "", 0.0])
	return out


## Back and forth on the mini ramp: a kick turn at one lip, an air turned round at the other.
static func _mini_line() -> Array:
	var x := (SkatePark.MINI_X0 + SkatePark.MINI_X1) * 0.5 + 0.4
	var zc := SkatePark.MINI_ZC
	var e := SkatePark.MINI_FLAT * 0.5 + SkatePark.mini_reach()
	return [
		[Vector2(x, zc - e + 0.25), 0.2, "turn", 0.75], [Vector2(x + 0.15, zc - e + 0.3), 3.2, "", 0.0],
		[Vector2(x + 0.2, zc - 1.0), 5.2, "", 0.0], [Vector2(x + 0.1, zc + 1.0), 4.6, "", 0.0],
		[Vector2(x, zc + e - 0.3), 0.2, "turn", 0.5], [Vector2(x - 0.15, zc + e - 0.35), 3.2, "", 0.0],
		[Vector2(x - 0.2, zc + 1.0), 5.2, "", 0.0], [Vector2(x - 0.1, zc - 1.0), 4.6, "", 0.0],
	]


## Line `name` as a table at RATE Hz: {"pos", "up", "fwd": PackedVector3Array, "pose":
## PackedByteArray, "flip": PackedFloat32Array (-1, or 0..1 round the flip), "length": seconds}.
static func sample(name: String) -> Dictionary:
	if _tables.has(name):
		return _tables[name]
	var wps: Array = lines()[name]
	var n := wps.size()
	# Dense points along each segment: Catmull-Rom where ridden, straight where in the air.
	var pts: Array = []
	for i in n:
		var a: Array = wps[i]
		var b: Array = wps[(i + 1) % n]
		var p0: Vector2 = wps[(i - 1 + n) % n][0]
		var p1: Vector2 = a[0]
		var p2: Vector2 = b[0]
		var p3: Vector2 = wps[(i + 2) % n][0]
		var ev: String = a[2]
		# Next to an air or a grind the curve runs straight in and out: pulled toward a point on
		# the coping, a curve overshoots up the vert.
		var flying := ["ollie", "flip", "turn", "grind"]
		if String(b[2]) in flying:
			p3 = p2 * 2.0 - p1
		if String(wps[(i - 1 + n) % n][2]) in flying:
			p0 = p1 * 2.0 - p2
		var seg := maxi(4, int(p1.distance_to(p2) / 0.12))
		for k in seg:
			var f := float(k) / float(seg)
			var p: Vector2
			if ev in ["ollie", "flip", "turn", "grind"]:
				p = p1.lerp(p2, f)
			else:
				p = _catmull(p0, p1, p2, p3, f)
			pts.append([p, i, f])
	# Walk them at each segment's speed into time samples.
	var pos := PackedVector3Array()
	var ups := PackedVector3Array()
	var fwd := PackedVector3Array()
	var pose := PackedByteArray()
	var flip := PackedFloat32Array()
	var segs := PackedInt32Array()
	var seg_y0 := {}
	var seg_y1 := {}
	var seg_speed := {}
	var seg_h := {}
	for i in n:
		var a: Array = wps[i]
		var b: Array = wps[(i + 1) % n]
		var prev: Array = wps[(i - 1 + n) % n]
		var nxt: Array = wps[(i + 1) % n]
		var h0 := float(a[3]) if String(a[2]) == "grind" else (float(prev[3]) if String(prev[2]) == "grind" else 0.0)
		var h1 := float(a[3]) if String(a[2]) == "grind" else (float(nxt[3]) if String(nxt[2]) == "grind" else 0.0)
		seg_y0[i] = SkatePark.surface_y(a[0]) + h0
		seg_y1[i] = SkatePark.surface_y(b[0]) + h1
		# An air clears whatever is under its chord (a lip, a ledge's edge) by a hand at least, and
		# takes the time a body takes to rise to its top and fall back past where it lands.
		seg_h[i] = float(a[3])
		if String(a[2]) in ["ollie", "flip", "turn"]:
			var y0: float = seg_y0[i]
			var y1: float = seg_y1[i]
			for q in range(1, 20):
				var fq := float(q) / 20.0
				var under := SkatePark.surface_y((a[0] as Vector2).lerp(b[0], fq)) + 0.08 - lerpf(y0, y1, fq)
				seg_h[i] = maxf(float(seg_h[i]), under / (4.0 * fq * (1.0 - fq)))
			var top := maxf(y0, y1) + float(seg_h[i])
			var t_air := sqrt(2.0 * (top - y0) / 9.8) + sqrt(2.0 * (top - y1) / 9.8)
			var dist := (a[0] as Vector2).distance_to(b[0])
			seg_speed[i] = minf(float(a[1]), dist / maxf(t_air, 0.05))
		else:
			seg_speed[i] = float(a[1])
	var dt := 1.0 / RATE
	var m := pts.size()
	var j := 0
	var guard := 0
	# Time samples: advance along the dense points at the current segment's speed.
	var dist_total := 0.0
	var cum := PackedFloat32Array()
	for k in m + 1:
		cum.append(dist_total)
		var pa: Vector2 = pts[k % m][0]
		var pb: Vector2 = pts[(k + 1) % m][0]
		dist_total += pa.distance_to(pb)
	var seg_counts := {}
	for q in m:
		seg_counts[int(pts[q][1])] = int(seg_counts.get(int(pts[q][1]), 0)) + 1
	var s := 0.0
	while j < m and guard < 100000:
		guard += 1
		var seg_i: int = pts[j][1]
		var f_lo: float = pts[j][2]
		var w: Array = wps[seg_i]
		var spd: float = seg_speed[seg_i]
		var ev: String = w[2]
		var h: float = seg_h[seg_i]
		var local_f := (s - cum[j]) / maxf(cum[j + 1] - cum[j], 0.0001)
		var p: Vector2 = (pts[j][0] as Vector2).lerp(pts[(j + 1) % m][0], local_f)
		var f := f_lo + local_f / maxf(float(seg_counts.get(seg_i, 1)), 1.0)
		var y := SkatePark.surface_y(p)
		var pk := P_RIDE
		var fl := -1.0
		if ev == "grind":
			# Held on the rail or the coping: its two ends' heights (a chord of a curved coping
			# dips inside the rim, where the surface is the pool's wall).
			y = lerpf(float(seg_y0[seg_i]), float(seg_y1[seg_i]), f)
			pk = P_GRIND
		elif ev in ["ollie", "flip", "turn"]:
			y = lerpf(float(seg_y0[seg_i]), float(seg_y1[seg_i]), f) + 4.0 * h * f * (1.0 - f)
			y = maxf(y, SkatePark.surface_y(p))
			pk = P_AIR
			if ev == "flip":
				fl = clampf((f - 0.12) / 0.6, 0.0, 1.0)
		pos.append(Vector3(p.x, y, p.y))
		segs.append(seg_i)
		pose.append(pk)
		flip.append(fl)
		ups.append(Vector3.UP if pk != P_RIDE else _surface_up(p))
		# Ridden, the pace is along the surface: slower across the plan where it climbs a wall.
		var step := spd * dt
		if not ev in ["ollie", "flip", "turn", "grind"]:
			var q0: Vector2 = pts[j][0]
			var q1: Vector2 = pts[(j + 1) % m][0]
			var run := maxf(q0.distance_to(q1), 0.02)
			var rise := SkatePark.surface_y(q1) - SkatePark.surface_y(q0)
			step /= sqrt(1.0 + (rise / run) * (rise / run))
		s += step
		var seg_before := int(pts[j][1])
		while j < m and s >= cum[j + 1]:
			j += 1
			# A new segment starts at its own start: a long stride must not carry a rider through
			# the first part of a short air.
			if j < m and int(pts[j][1]) != seg_before:
				s = cum[j]
				break
	# The way it goes, from the positions; turned through the air on a "turn" (and kept level).
	var count := pos.size()
	for k in count:
		var d := pos[(k + 1) % count] - pos[(k - 1 + count) % count]
		d.y *= 0.0
		fwd.append(d.normalized() if d.length() > 0.001 else Vector3.RIGHT)
	# Smooth the ups (the vert-to-flat corners of the profile turn them sharply).
	var sm := PackedVector3Array()
	sm.resize(count)
	for k in count:
		var u := Vector3.ZERO
		for o in range(-4, 5):
			u += ups[(k + o + count) % count]
		sm[k] = u.normalized()
	# Crouch where the wall is steep, and for a beat after every landing.
	for k in count:
		if pose[k] == P_RIDE:
			if sm[k].y < 0.8:
				pose[k] = P_CROUCH
			for back in range(1, 9):
				if pose[(k - back + count) % count] == P_AIR:
					pose[k] = P_CROUCH
					break
	# A turned air: swing the way it goes round the up axis across the air.
	var k0 := 0
	while k0 < count:
		if pose[k0] == P_AIR and k0 > 0 and pose[k0 - 1] != P_AIR:
			var k1 := k0
			while k1 < count and pose[k1] == P_AIR:
				k1 += 1
			var a := fwd[maxi(k0 - 2, 0)]
			var b := fwd[mini(k1 + 1, count - 1)]
			var ang := atan2(a.cross(b).y, a.dot(b))
			for q in range(k0, k1):
				var ff := float(q - k0 + 1) / float(k1 - k0 + 1)
				fwd[q] = a.rotated(Vector3.UP, ang * ff)
			k0 = k1
		k0 += 1
	var out := {"pos": pos, "up": sm, "fwd": fwd, "pose": pose, "flip": flip, "seg": segs, "length": float(count) / RATE}
	_tables[name] = out
	return out


static func _surface_up(p: Vector2) -> Vector3:
	var e := 0.18
	var dx := (SkatePark.surface_y(p + Vector2(e, 0.0)) - SkatePark.surface_y(p - Vector2(e, 0.0))) / (2.0 * e)
	var dz := (SkatePark.surface_y(p + Vector2(0.0, e)) - SkatePark.surface_y(p - Vector2(0.0, e))) / (2.0 * e)
	# A step (a wall's edge, a kerb) is not a slope: ride it level.
	if absf(dx) > 3.0 or absf(dz) > 3.0:
		return Vector3.UP
	return Vector3(-dx, 1.0, -dz).normalized()


static func _catmull(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)


## Where line `name` puts a rider at time `t` (s): the transform (board frame: x the way it goes,
## y the surface's up), the pose, the flip.
static func at(name: String, t: float) -> Array:
	var tb := sample(name)
	var count: int = (tb.pos as PackedVector3Array).size()
	var ft := fposmod(t, float(tb.length)) * RATE
	var k := int(ft) % count
	var k1 := (k + 1) % count
	var f := ft - floorf(ft)
	var p: Vector3 = (tb.pos[k] as Vector3).lerp(tb.pos[k1], f)
	var up: Vector3 = (tb.up[k] as Vector3).lerp(tb.up[k1], f).normalized()
	var fw: Vector3 = (tb.fwd[k] as Vector3).lerp(tb.fwd[k1], f)
	fw = (fw - up * fw.dot(up)).normalized()
	if fw.length() < 0.5:
		fw = Vector3.RIGHT
	var z := fw.cross(up).normalized()
	return [Transform3D(Basis(fw, up, z), p), int(tb.pose[k]), float(tb.flip[k])]


# --- The people -----------------------------------------------------------------------------------

## A skater on a line: a figure and a board under a body on the npc layer.
class Skater extends AnimatableBody3D:
	var life: SkateParkLife
	var line: String = "pool"
	var phase: float = 0.0
	var pace: float = 1.0
	var model: int = 0
	var seed_value: int = 0
	var goofy: bool = false
	var paint := Color.WHITE
	var gone: bool = false
	var pose: int = 0
	var _fig: MeshInstance3D
	var _board: MeshInstance3D
	var _fig_holder: Node3D

	func _init() -> void:
		collision_layer = 8
		collision_mask = 0
		sync_to_physics = false

	func _ready() -> void:
		_fig_holder = Node3D.new()
		_fig_holder.position = Vector3(0.0, SkateParkLife.BOARD_TOP, 0.0)
		add_child(_fig_holder)
		_fig = MeshInstance3D.new()
		_fig.name = "Rider"
		_fig.visibility_range_end = 170.0
		# The figure was baked side-on (the board's axis along its x): goofy riders face the other way.
		if goofy:
			_fig.rotation.y = PI
		_fig_holder.add_child(_fig)
		_board = MeshInstance3D.new()
		_board.name = "Board"
		_board.mesh = SkateParkLife.board_mesh(paint)
		_board.visibility_range_end = 120.0
		add_child(_board)
		var cs := CollisionShape3D.new()
		var cap := CapsuleShape3D.new()
		cap.radius = 0.3
		cap.height = 1.7
		cs.shape = cap
		cs.position = Vector3(0.0, 0.95, 0.0)
		add_child(cs)
		refresh()

	func refresh() -> void:
		if _fig:
			_fig.mesh = SkateParkLife.figure_cached(seed_value, SkateParkLife.POSE_NAMES[pose])

	func place(clock: float) -> void:
		if gone:
			return
		var r := SkateParkLife.at(line, clock * pace + phase)
		var xf: Transform3D = r[0]
		transform = xf
		var p: int = r[1]
		if p != pose:
			pose = p
			refresh()
		var fl: float = r[2]
		if fl >= 0.0:
			# The kickflip: the board rolls a turn about its own length and rises to the feet.
			var e := fl * fl * (3.0 - 2.0 * fl)
			_board.transform = Transform3D(Basis(Vector3.RIGHT, e * TAU), Vector3(0.0, 0.18 * sin(fl * PI), 0.0))
			_fig_holder.position.y = SkateParkLife.BOARD_TOP + 0.2 * sin(fl * PI)
		else:
			_board.transform = Transform3D.IDENTITY
			_fig_holder.position.y = SkateParkLife.BOARD_TOP

	func shot(at: Vector3, hit_dir: Vector3, impulse: Vector3, strength: float = 1.0) -> void:
		var p := wake(impulse)
		if p:
			p.shot(at, hit_dir, impulse, strength)

	func knock(impulse: Vector3, gibs: int = 0) -> void:
		var p := wake(impulse)
		if p:
			p.knock(impulse, gibs)

	func take_hit(_shape_index: int, _damage: float, hit_dir: Vector3 = Vector3.UP) -> void:
		knock(hit_dir.normalized() * 4.0 + Vector3.UP)

	## Off the board: the live person where they rode, the board thrown on.
	func wake(impulse: Vector3) -> SkaterPerson:
		if gone or life == null:
			return null
		gone = true
		collision_layer = 0
		var xf := transform
		var flat := xf
		flat.basis = Basis(Vector3.UP, atan2(-xf.basis.z.x, -xf.basis.z.z))
		var ped := life.spawn_person(seed_value, flat)
		var holder := life.get_parent().get_parent()
		if holder != null:
			var root := life.get_parent() as Node3D
			var board_xf := root.transform * xf
			var along := board_xf.basis.x * 4.0
			EncampmentItem.throw(holder, SkateParkLife.board_mesh(paint), Vector3(0.8, 0.11, 0.21), 0.05, 3.5, Color.WHITE, Color(0.0, 0.0, 0.0, 0.0), board_xf, impulse * 0.3 + along + Vector3(0.0, 1.0, 0.0))
		queue_free()
		return ped


## A spectator: one baked figure under a body on the npc layer.
class Spectator extends StaticBody3D:
	var life: SkateParkLife
	var model: int = 0
	var seed_value: int = 0
	var pose_key: String = "watch"
	var gone: bool = false
	var _fig: MeshInstance3D

	func _init() -> void:
		collision_layer = 8
		collision_mask = 0

	func _ready() -> void:
		_fig = MeshInstance3D.new()
		_fig.name = "Figure"
		_fig.visibility_range_end = 150.0
		add_child(_fig)
		var cs := CollisionShape3D.new()
		var cap := CapsuleShape3D.new()
		cap.radius = 0.3
		cap.height = 1.2 if pose_key == "sit_edge" else 1.75
		cs.shape = cap
		cs.position = Vector3(0.0, 0.6 if pose_key == "sit_edge" else 0.9, 0.0)
		add_child(cs)
		refresh()

	func refresh() -> void:
		if _fig:
			_fig.mesh = SkateParkLife.figure_cached(seed_value, pose_key)

	func shot(at: Vector3, hit_dir: Vector3, impulse: Vector3, strength: float = 1.0) -> void:
		var p := wake(impulse)
		if p:
			p.shot(at, hit_dir, impulse, strength)

	func knock(impulse: Vector3, gibs: int = 0) -> void:
		var p := wake(impulse)
		if p:
			p.knock(impulse, gibs)

	func take_hit(_shape_index: int, _damage: float, hit_dir: Vector3 = Vector3.UP) -> void:
		knock(hit_dir.normalized() * 4.0 + Vector3.UP)

	func wake(_impulse: Vector3) -> SkaterPerson:
		if gone or life == null:
			return null
		gone = true
		collision_layer = 0
		var xf := transform
		if pose_key == "sit_edge":
			# Up off the edge onto the deck behind it.
			xf.origin += xf.basis.z * 0.6
		var ped := life.spawn_person(seed_value, xf)
		queue_free()
		return ped


## A baked figure if there is one (never bakes: SkateParkLife bakes them a frame at a time).
static func figure_cached(seed_value: int, pose: String) -> Mesh:
	return _figures.get("%d|%s" % [seed_value, pose])
