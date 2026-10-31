class_name PierPark
extends RefCounted
## RANDO PIER and its amusement park, GULLWING PARK (Landmarks "pier"): a Santa Monica-style FORM -
## a long timber pier off the beach with a wide platform of rides on its south side - entirely
## original: every name, ride, sign and game here is invented.
##
##   build(anchor, parent, statics, plan, detailed)   the whole pier, near (in its chunk) or far
##   people_steps(anchor, chunk)                       the crowd, one build step a person
##
## THE PARK'S FRAME: a node at (anchor.x, 0, anchor.y); x runs out to sea (negative), z south.
## Three decks at DECK_Y: the pier itself (MAIN, 280 x 24 m), a strip on its north side for the
## arcade, the bumper cars and the games (NORTH), and the park platform on its south side (SOUTH)
## that the coaster loops round, with the Ferris wheel in the loop's middle and the carousel beside
## it. Every position is a constant in this frame (the tables below), so the near and far copies
## and the crowd's walk graph agree; the checks hold the pieces apart (no ride in another, nothing
## in a walkway).
##
## WHAT RUNS: the wheel (FerrisWheel) and the carousel (PierCarousel) and the bumper cars turn in
## the vertex shader (pier_park.gdshader) from TIME, the coaster's train (PierCoaster) is placed
## from a clock-driven table each frame. Lights after dark follow lamp_factor: the wheel's chasing
## LEDs, bulbs on every arch, sign, canopy and string, neon names, lit windows, light pools on the
## deck, a few real lamp_light omnis.
##
## People: PierGoers (the crowd's own rigs and life, under the crowd cap) walk the WALK graph, sit
## on the benches (CrowdLife seats) and queue at the rides, stands and booths (the chunk's
## "vendor_queue" spots, which the life layer's _plan_queue() fills).

const PARK_NAME := "GULLWING PARK"
## Centre height of the deck slabs (LandmarkBeachPiers.DECK_Y: the three piers agree) and their
## thickness; the walking surface is DECK_TOP.
const DECK_Y := 6.0
const DECK_T := 0.8
const DECK_TOP := DECK_Y + DECK_T * 0.5
const PILE_FOOT := -3.0

## The decks, park frame (x, z, size x, size z).
const MAIN := Rect2(-280.0, -12.0, 280.0, 24.0)
const NORTH := Rect2(-160.0, -32.0, 98.0, 20.0)
const SOUTH := Rect2(-205.0, 12.0, 140.0, 50.0)
## The rail round the edge (the shore end is open onto the ramp).
const OUTLINE: Array[Vector2] = [Vector2(0, -12), Vector2(-62, -12), Vector2(-62, -32), Vector2(-160, -32),
	Vector2(-160, -12), Vector2(-280, -12), Vector2(-280, 12), Vector2(-205, 12), Vector2(-205, 62),
	Vector2(-65, 62), Vector2(-65, 12), Vector2(0, 12)]

## Rides and buildings (park frame XZ).
const WHEEL_AT := Vector2(-150.0, 37.0)
const CAROUSEL_AT := Vector2(-108.0, 40.0)
const CAROUSEL_FENCE := 10.8
const ARCADE := Rect2(-100.0, -30.0, 34.0, 16.0)
const BUMPER := Rect2(-134.0, -31.0, 28.0, 17.0)
const ARCH_X := -60.0
const ENTRY_ARCH_X := -6.0
## Lamps down both edges of the pier (Weather.pier_light_lines() mirrors them in the sea): from
## LAMP_FROM out, LAMP_STEP apart, LAMP_COUNT a side, at z +-LAMP_Z.
const LAMP_FROM := -20.0
const LAMP_STEP := 26.0
const LAMP_COUNT := 10
const LAMP_Z := 11.4

## Food stands: [x, z, yaw the serving window faces, name, kind] (kind picks the giant prop on the
## roof).
const STANDS: Array = [
	[-26.0, -9.6, PI, "SALT & SPUD", "fries"],
	[-38.0, 9.6, 0.0, "PINK FOG CANDY", "candy"],
	[-52.0, -9.6, PI, "STICK SHACK", "corndog"],
	[-186.0, -9.6, PI, "SQUEEZE PLAY", "lemon"],
	[-201.5, 47.0, -PI * 0.5, "FUNNEL CLOUD", "funnel"],
]
## Game booths along the north strip: [x, name, prize colour].
const BOOTHS: Array = [
	[-156.0, "RING TOSS", Color(0.85, 0.2, 0.3)],
	[-151.5, "HOOP SHOT", Color(0.95, 0.6, 0.1)],
	[-147.0, "BALLOON DARTS", Color(0.3, 0.55, 0.9)],
	[-142.5, "WATER RACE", Color(0.2, 0.7, 0.45)],
	[-138.0, "BOTTLE DROP", Color(0.7, 0.3, 0.8)],
]
const BOOTH_Z := -15.6
## Picnic tables under umbrellas at the west end of the platform.
const TABLES: Array[Vector2] = [Vector2(-198.0, 22.0), Vector2(-198.0, 31.0), Vector2(-186.0, 57.5), Vector2(-199.5, 56.5)]

## The crowd's walk graph (park frame XZ) and its edges: the promenade, the way under the
## coaster's lift into the loop, round the wheel and the carousel, the food court, the coaster
## queue. Nothing on an edge passes through a ride, a building or a stand (checked).
const WALK_NODES: Array[Vector2] = [
	Vector2(-4, 0), Vector2(-25, 1), Vector2(-45, -1), Vector2(-62, 0), Vector2(-80, -4), Vector2(-100, 2),
	Vector2(-120, -4), Vector2(-137.8, 4), Vector2(-150, -3), Vector2(-170, 2), Vector2(-195, 0), Vector2(-225, -2),
	Vector2(-255, 2), Vector2(-272, 0), Vector2(-137.8, 18), Vector2(-137.8, 25), Vector2(-158, 25), Vector2(-112, 25),
	Vector2(-128, 46), Vector2(-150, 48), Vector2(-94, 28), Vector2(-192, 17), Vector2(-191, 38), Vector2(-192, 52),
	Vector2(-82, 14), Vector2(-70, 9)]
const WALK_EDGES: Array[Vector2i] = [
	Vector2i(0, 1), Vector2i(1, 2), Vector2i(2, 3), Vector2i(3, 4), Vector2i(4, 5), Vector2i(5, 6), Vector2i(6, 7),
	Vector2i(7, 8), Vector2i(8, 9), Vector2i(9, 10), Vector2i(10, 11), Vector2i(11, 12), Vector2i(12, 13),
	Vector2i(7, 14), Vector2i(14, 15), Vector2i(15, 16), Vector2i(15, 17), Vector2i(15, 18), Vector2i(18, 19),
	Vector2i(17, 20), Vector2i(10, 21), Vector2i(21, 22), Vector2i(22, 23), Vector2i(5, 24), Vector2i(24, 25),
	Vector2i(3, 25), Vector2i(9, 21)]
## The walk nodes of the midway, where most of the crowd starts.
const MIDWAY: Array[int] = [3, 4, 5, 6, 7, 8, 15, 17, 18, 20, 24]
## How many people the park asks for (the crowd cap has the last word).
const PEOPLE := 48

const WHITE := Color(0.93, 0.92, 0.88)
const TIMBER := Color(0.22, 0.17, 0.12)
const RAIL := Color(0.90, 0.89, 0.84)

static var _cache: Dictionary = {}


# --- Walk graph -------------------------------------------------------------------------------

static func walk_node(origin: Vector2, i: int) -> Vector2:
	return origin + WALK_NODES[i]


static func jitter(i: int) -> float:
	var p: Vector2 = WALK_NODES[i]
	return 2.2 if absf(p.y) < 10.0 else 1.2


static func neighbours(i: int) -> Array[int]:
	var out: Array[int] = []
	for e: Vector2i in WALK_EDGES:
		if e.x == i:
			out.append(e.y)
		elif e.y == i:
			out.append(e.x)
	return out


static func nearest_node(origin: Vector2, p: Vector2) -> int:
	var best := -1
	var best_d := INF
	for i in WALK_NODES.size():
		var d := (origin + WALK_NODES[i]).distance_squared_to(p)
		if d < best_d:
			best_d = d
			best = i
	return best


## The graph nodes to walk through from `from` to `to` (world XZ), breadth first; empty when both
## are nearest the same node.
static func route(origin: Vector2, from: Vector2, to: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	var a := nearest_node(origin, from)
	var b := nearest_node(origin, to)
	if a < 0 or b < 0 or a == b:
		return out
	var prev := {a: -1}
	var queue: Array[int] = [a]
	while not queue.is_empty():
		var n: int = queue.pop_front()
		if n == b:
			break
		for m in neighbours(n):
			if not prev.has(m):
				prev[m] = n
				queue.append(m)
	if not prev.has(b):
		return out
	var path: Array[int] = []
	var c := b
	while c != -1:
		path.push_front(c)
		c = prev[c]
	# Skip the first node when we are already past it toward the second (no doubling back).
	for k in path.size():
		if k == 0 and path.size() > 1:
			var p0 := origin + WALK_NODES[path[0]]
			var p1 := origin + WALK_NODES[path[1]]
			if from.distance_to(p1) < p0.distance_to(p1):
				continue
		out.append(origin + WALK_NODES[path[k]])
	return out


## Where people queue (park frame): [p, facing yaw] - at the wheel, the coaster, the carousel,
## the bumper cars, each food stand and each game booth.
static func queue_spots() -> Array:
	var out: Array = []
	for i in 5:
		out.append([Vector2(-149.6, 27.4 + float(i) * 0.8), PI])
		out.append([Vector2(-150.9, 27.8 + float(i) * 0.8), PI])
	for i in 7:
		out.append([Vector2(-88.0 + float(i) * 0.85, 13.7), PI * 0.5])
	for i in 5:
		out.append([Vector2(-94.2 + float(i) * 0.85, 39.6), PI * 0.5])
	for i in 4:
		out.append([Vector2(-110.0 + float(i) * 0.9, -11.6), 0.0])
	for s: Array in STANDS:
		var yaw: float = s[2]
		var face := Vector2(-sin(yaw), -cos(yaw))
		var front := Vector2(s[0], s[1]) + face * 2.6
		var side := Vector2(face.y, -face.x)
		for k in 3:
			var p := front + face * (float(k) * 0.9) + side * (0.3 if k % 2 == 0 else -0.3)
			out.append([p, yaw + PI])
	for b: Array in BOOTHS:
		out.append([Vector2(float(b[0]) - 0.6, BOOTH_Z + 2.6), PI])
		out.append([Vector2(float(b[0]) + 0.7, BOOTH_Z + 3.1), PI])
	return out


## Benches (park frame centre, yaw facing the way a sitter looks).
static func benches() -> Array:
	var out: Array = []
	var x := -168.0
	while x > -276.0:
		out.append([Vector2(x, -10.9), PI])
		if x < -210.0:
			out.append([Vector2(x - 6.0, 10.9), 0.0])
		x -= 14.0
	for bx: float in [-14.0, -31.0, -44.0]:
		out.append([Vector2(bx, 10.9), 0.0])
	for bx: float in [-17.0, -33.0]:
		out.append([Vector2(bx, -10.9), PI])
	out.append([Vector2(-126.0, 27.0), PI])
	out.append([Vector2(-140.0, 52.0), 0.0])
	return out


# --- Build ------------------------------------------------------------------------------------

## Builds the detailed meshes on the loading screen (the pier, the wheel, the coaster, the
## carousel, the bumper cars and the train are ~0.4 s of GDScript), so the chunk that streams the
## pier in does not stall on them. Returns no materials: they are .gdshader files the loading
## screen already compiles.
static func warm() -> Array:
	if not _cache.has("near"):
		_cache["near"] = _static_mesh(true)
	if not FerrisWheel._meshes.has("near"):
		FerrisWheel._meshes["near"] = FerrisWheel._meshes_for(true)
	PierCoaster._ensure()
	if not PierCoaster._track_meshes.has("near"):
		PierCoaster._track_meshes["near"] = PierCoaster._track_mesh(DECK_TOP, true)
	if PierCoaster._car_meshes.is_empty():
		PierCoaster._car_meshes = [PierCoaster._car_mesh(true), PierCoaster._car_mesh(false)]
	if not PierCarousel._meshes.has("near"):
		PierCarousel._meshes["near"] = PierCarousel._meshes_for(true)
	return []


static func build(anchor: Vector2, parent: Node3D, _statics: StaticBody3D, _plan: CityPlan, detailed: bool) -> void:
	var park := Node3D.new()
	park.name = "PierPark"
	park.position = Vector3(anchor.x, 0.0, anchor.y)
	parent.add_child(park)
	var key := "near" if detailed else "far"
	if not _cache.has(key):
		_cache[key] = _static_mesh(detailed)
	for i in 2:
		var mi := MeshInstance3D.new()
		mi.name = ["Pier", "PierDetail"][i]
		mi.mesh = _cache[key][i]
		# The detail (piles, rails, lamps, bulbs, strings, lettering, prizes) casts nothing: every
		# shadow cascade paid for it and a bulb's shadow is nobody's. Nor does the far copy.
		if i == 1 or not detailed:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		park.add_child(mi)
	if detailed:
		var pk := "pools"
		if not _cache.has(pk):
			_cache[pk] = _pool_mesh()
		var pools := MeshInstance3D.new()
		pools.name = "LightPools"
		pools.mesh = _cache[pk]
		pools.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		park.add_child(pools)
		_bumper_cars(park)
	# The wheel stands straight under the parent so it is found where it always was (the chunk's
	# own child, CityStreamer's far holder's), at its world point.
	FerrisWheel.build(Vector3(anchor.x + WHEEL_AT.x, DECK_TOP, anchor.y + WHEEL_AT.y), parent, detailed)
	PierCoaster.build(park, DECK_TOP, detailed)
	PierCarousel.build(park, Vector3(CAROUSEL_AT.x, DECK_TOP, CAROUSEL_AT.y), detailed)
	if not detailed:
		return
	_add_body(park)
	_add_lights(park)
	# The chunk's crowd-life spots: the queues and the benches, in the chunk's own (world) space.
	if parent is CityChunk:
		var queue: Array = parent.get_meta("vendor_queue", [])
		for q: Array in queue_spots():
			queue.append({"p": anchor + (q[0] as Vector2), "yaw": float(q[1]), "taken": null, "record": null})
		parent.set_meta("vendor_queue", queue)
		for b: Array in benches():
			var p: Vector2 = anchor + (b[0] as Vector2)
			CrowdLife.add_seat(parent, Vector3(p.x, DECK_TOP, p.y), float(b[1]))


## The crowd: one build step a person (a rig is a few milliseconds), in the crowd cap.
static func people_steps(anchor: Vector2, chunk: CityChunk) -> Array[Callable]:
	var steps: Array[Callable] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([chunk.plan.seed if chunk.plan else 0, "pier_park_people"])
	for i in PEOPLE:
		# Two in three start on the midway (the arch out to the games, and inside the loop).
		var node := rng.randi() % WALK_NODES.size()
		if rng.randf() < 0.66:
			node = MIDWAY[rng.randi() % MIDWAY.size()]
		steps.append(_spawn_goer.bind(chunk, anchor, node, rng.randi()))
	return steps


static func _spawn_goer(chunk: CityChunk, anchor: Vector2, node: int, seed_value: int) -> void:
	if not chunk._take_crowd_room():
		return
	var goer := PierGoer.new()
	goer.setup_park(anchor, DECK_TOP, node, seed_value)
	var j := jitter(node)
	var h := hash([seed_value, "at"])
	var off := Vector2(float(posmod(h, 1000)) / 1000.0 - 0.5, float(posmod(h >> 10, 1000)) / 1000.0 - 0.5) * 2.0 * j
	var p := walk_node(anchor, node) + off
	goer.position = Vector3(p.x, DECK_TOP + 0.1, p.y)
	chunk.add_child(goer)


# --- The pier and the midway: one static mesh -------------------------------------------------

## [the mesh that casts, the detail that does not].
static func _static_mesh(detailed: bool) -> Array:
	var g := PierMesh.new()
	g.use("deck", PropFactory.pbr("planks", 2.4, Color(0.78, 0.70, 0.62)))
	g.use("p", PierMesh.material("park"))
	g.use("d", PierMesh.material("park"))
	g.light_slot = "d"
	_decks(g, detailed)
	_dbg(g, "_decks")
	g.slot("d")
	_piles(g, detailed)
	_dbg(g, "_piles")
	_rails(g, detailed)
	_dbg(g, "_rails")
	g.slot("p")
	_ramp(g, detailed)
	_dbg(g, "_ramp")
	_arch(g, ENTRY_ARCH_X, 11.0, Landmarks.PIER_NAME, Color(0.10, 0.32, 0.55), Color(1.0, 0.85, 0.3), detailed)
	_arch(g, ARCH_X, 11.0, PARK_NAME, Color(0.72, 0.12, 0.16), Color(1.0, 0.92, 0.75), detailed)
	_arcade(g, detailed)
	_dbg(g, "_arcade")
	_bumper_hall(g, detailed)
	_dbg(g, "_bumper_hall")
	g.slot("d")
	_lamps(g, detailed)
	_dbg(g, "_lamps")
	_wheel_queue(g, detailed)
	if detailed:
		for b: Array in benches():
			_bench(g, b[0], b[1])
		for t: Vector2 in TABLES:
			_table(g, t)
		_strings(g)
		g.slot("p")
		for s: Array in STANDS:
			_stand(g, s)
		for b: Array in BOOTHS:
			_booth(g, b)
	_dbg(g, "_strings")
	return [g.build_mesh(["deck", "p"]), g.build_mesh(["d"])]


static func _dbg(g: PierMesh, what: String) -> void:
	if OS.get_environment("PIER_DEBUG") != "":
		print("PIER %s %d" % [what, g.triangles])


static func _decks(g: PierMesh, detailed: bool) -> void:
	for r: Rect2 in [MAIN, NORTH, SOUTH]:
		var c := r.get_center()
		g.slot("deck")
		g.kind = PierMesh.K_PAINT
		g.abox(Vector3(c.x, DECK_Y, c.y), Vector3(r.size.x, DECK_T, r.size.y), Color.WHITE, 0.0, false)
		g.slot("p")
		# The fascia board round each deck's edge and the stringers under it.
		g.kind = PierMesh.K_BOARDS
		g.abox(Vector3(c.x, DECK_Y - DECK_T * 0.5 - 0.25, c.y), Vector3(r.size.x - 0.4, 0.5, r.size.y - 0.4), TIMBER.lightened(0.15), 0.0, true)
		if detailed:
			var z := r.position.y + 3.0
			while z < r.end.y - 1.0:
				g.abox(Vector3(c.x, DECK_Y - DECK_T * 0.5 - 0.7, z), Vector3(r.size.x - 1.0, 0.45, 0.35), TIMBER)
				z += 6.0


static func _piles(g: PierMesh, detailed: bool) -> void:
	var step := 8.0 if detailed else 24.0
	var bottom := DECK_Y - DECK_T * 0.5 - 0.9
	for r: Rect2 in [MAIN, NORTH, SOUTH]:
		var x := r.end.x - 4.0
		while x > r.position.x + 1.0:
			var row: Array[Vector3] = []
			var z := r.position.y + 2.0
			var zstep := 6.0 if detailed else r.size.y - 4.0
			while z <= r.end.y - 1.9:
				var foot := Vector3(x, PILE_FOOT, z)
				g.kind = PierMesh.K_PAINT
				g.tube(foot, Vector3(x, bottom, z), 0.4, 0.36, TIMBER, 6 if detailed else 4)
				row.append(Vector3(x, 0.0, z))
				z += zstep
			if detailed:
				# The bent: a cap beam across the row and X bracing between the piles.
				g.abox(Vector3(x, bottom + 0.25, r.get_center().y), Vector3(0.45, 0.5, r.size.y - 2.0), TIMBER)
				for k in row.size() - 1:
					var a: Vector3 = row[k]
					var b: Vector3 = row[k + 1]
					g.beam(Vector3(a.x, 0.8, a.z), Vector3(b.x, bottom - 0.4, b.z), 0.12, 0.25, TIMBER, Vector3.RIGHT)
					g.beam(Vector3(b.x, 0.8, b.z), Vector3(a.x, bottom - 0.4, a.z), 0.12, 0.25, TIMBER, Vector3.RIGHT)
			x -= step


static func _rails(g: PierMesh, detailed: bool) -> void:
	var top := DECK_TOP + 1.1
	for i in OUTLINE.size() - 1:
		var a: Vector2 = OUTLINE[i]
		var b: Vector2 = OUTLINE[i + 1]
		var length := a.distance_to(b)
		var d := (b - a) / length
		var yaw := atan2(-d.x, -d.y)
		var c := (a + b) * 0.5
		g.kind = PierMesh.K_PAINT
		g.abox(Vector3(c.x, top, c.y), Vector3(0.14, 0.09, length), RAIL, yaw)
		if not detailed:
			continue
		g.abox(Vector3(c.x, top - 0.37, c.y), Vector3(0.06, 0.06, length), RAIL, yaw)
		g.abox(Vector3(c.x, top - 0.74, c.y), Vector3(0.06, 0.06, length), RAIL, yaw)
		g.abox(Vector3(c.x, DECK_TOP + 0.12, c.y), Vector3(0.08, 0.08, length), RAIL, yaw)
		var n := int(length / 2.4)
		for k in n + 1:
			var p := a + d * (length * float(k) / float(maxi(n, 1)))
			g.abox(Vector3(p.x, (DECK_TOP + top) * 0.5, p.y), Vector3(0.11, top - DECK_TOP, 0.11), RAIL, yaw)


static func _ramp(g: PierMesh, detailed: bool) -> void:
	# From the deck at the shore end down to the sand, 34 m at about 1:5.5.
	var run := 34.0
	var a := Vector3(0.0, DECK_TOP, 0.0)
	var b := Vector3(run, 0.15, 0.0)
	var d := (b - a)
	var mid := (a + b) * 0.5
	var basis := Basis(Vector3.BACK, atan2(d.y, d.x))
	g.slot("deck")
	g.box(Transform3D(basis, mid - basis.y * 0.3), Vector3(d.length(), 0.6, 10.0), Color.WHITE)
	g.slot("p")
	g.kind = PierMesh.K_PAINT
	for zs: float in [-1.0, 1.0]:
		g.box(Transform3D(basis, mid + basis.y * 1.1 + Vector3(0, 0, zs * 4.95)), Vector3(d.length(), 0.09, 0.14), RAIL)
		if detailed:
			var k := 0.0
			while k <= 1.0:
				var p := a.lerp(b, k) + Vector3(0, 0.55, zs * 4.95)
				g.abox(p, Vector3(0.11, 1.1, 0.11), RAIL)
				k += 1.0 / 14.0
	# Piers under the ramp.
	for k in [0.25, 0.5, 0.75]:
		var p := a.lerp(b, k)
		for zs: float in [-1.0, 1.0]:
			g.tube(Vector3(p.x, -1.0, zs * 3.5), Vector3(p.x, p.y - 0.6, zs * 3.5), 0.35, 0.35, TIMBER, 6)


## An entrance arch over the deck at `x`: two lit pylons and a curved beam with the name in neon
## on a board, bulbs along the curve.
static func _arch(g: PierMesh, x: float, half: float, name_text: String, col: Color, letters: Color, detailed: bool) -> void:
	var top := DECK_TOP + 8.0
	g.kind = PierMesh.K_PAINT
	for zs: float in [-1.0, 1.0]:
		g.box(Transform3D(Basis(), Vector3(x, DECK_TOP + 4.0, zs * half)), Vector3(1.1, 8.0, 1.1), col, 0.12)
		g.box(Transform3D(Basis(), Vector3(x, top + 0.6, zs * half)), Vector3(1.4, 0.5, 1.4), WHITE, 0.1)
		if detailed:
			g.kind = PierMesh.K_GOLD
			g.ellipsoid(Transform3D(Basis(), Vector3(x, top + 1.2, zs * half)), Vector3(0.4, 0.5, 0.4), Color.WHITE, 8, 5)
			g.kind = PierMesh.K_BULB
			for k in 12:
				g.anim = float(k) * 0.7
				for xs: float in [-1.0, 1.0]:
					g.ellipsoid(Transform3D(Basis(), Vector3(x + xs * 0.58, DECK_TOP + 1.0 + float(k) * 0.6, zs * half)), Vector3(0.06, 0.06, 0.06), Color(1.0, 0.85, 0.55), 4, 2)
			g.anim = 0.0
			g.kind = PierMesh.K_PAINT
	# The curved beam.
	var pts := PackedVector3Array()
	for k in 17:
		var t := float(k) / 16.0
		var z := lerpf(-half, half, t)
		pts.append(Vector3(x, top + 1.6 * sin(t * PI), z))
	g.sweep(pts, 0.28, col, 8 if detailed else 4)
	# The name board hung under the curve.
	g.kind = PierMesh.K_SIGN
	g.box(Transform3D(Basis(), Vector3(x, top - 0.1, 0.0)), Vector3(0.3, 1.5, half * 1.5), Color(0.06, 0.08, 0.14))
	if detailed:
		g.kind = PierMesh.K_NEON
		for xs: float in [-1.0, 1.0]:
			var xf := Transform3D(Basis(Vector3.UP, xs * PI * 0.5), Vector3(x + xs * 0.17, top - 0.1, 0.0))
			g.letters(name_text, 0.95, xf, letters, half * 1.4)
		g.kind = PierMesh.K_BULB
		for k in pts.size():
			g.anim = float(k)
			for xs: float in [-1.0, 1.0]:
				g.ellipsoid(Transform3D(Basis(), pts[k] + Vector3(xs * 0.3, 0.2, 0)), Vector3(0.07, 0.07, 0.07), Color(1.0, 0.85, 0.55), 4, 2)
		g.anim = 0.0


## The arcade: a long timber hall on the north strip, its front a wall of lit glass under a
## striped canopy, a tall sign board on the parapet with the name in neon and a frame of chasing
## bulbs.
static func _arcade(g: PierMesh, detailed: bool) -> void:
	var r := ARCADE
	var c := r.get_center()
	var h := 7.0
	var front := r.end.y
	g.kind = PierMesh.K_BOARDS
	g.abox(Vector3(c.x, DECK_TOP + h * 0.5, c.y - 0.3), Vector3(r.size.x, h, r.size.y - 0.6), Color(0.35, 0.62, 0.66))
	g.kind = PierMesh.K_PAINT
	g.abox(Vector3(c.x, DECK_TOP + h + 0.3, c.y), Vector3(r.size.x + 0.4, 0.6, r.size.y + 0.2), WHITE)
	# Sign board on the front parapet.
	g.kind = PierMesh.K_SIGN
	g.abox(Vector3(c.x, DECK_TOP + h + 2.0, front - 0.2), Vector3(r.size.x * 0.75, 2.6, 0.3), Color(0.05, 0.08, 0.20))
	g.kind = PierMesh.K_WINDOW
	# The glazed front: four bays of glass glowing in arcade colours, piers between them.
	var bays := 4
	var bw := r.size.x / float(bays)
	var glows: Array[Color] = [Color(0.9, 0.3, 0.8), Color(0.3, 0.7, 1.0), Color(1.0, 0.6, 0.2), Color(0.4, 1.0, 0.7)]
	for k in bays:
		var x := r.position.x + bw * (float(k) + 0.5)
		g.kind = PierMesh.K_WINDOW
		g.abox(Vector3(x, DECK_TOP + 2.2, front - 0.25), Vector3(bw - 1.0, 4.0, 0.1), glows[k % glows.size()])
		g.kind = PierMesh.K_PAINT
		g.abox(Vector3(r.position.x + bw * float(k), DECK_TOP + 2.2, front - 0.2), Vector3(1.0, 4.4, 0.4), WHITE)
	g.abox(Vector3(r.end.x, DECK_TOP + 2.2, front - 0.2), Vector3(1.0, 4.4, 0.4), WHITE)
	g.abox(Vector3(c.x, DECK_TOP + 4.6, front - 0.2), Vector3(r.size.x, 0.6, 0.45), WHITE)
	# The canopy over the doors.
	g.kind = PierMesh.K_CANVAS
	g.box(Transform3D(Basis(Vector3.RIGHT, 0.35), Vector3(c.x, DECK_TOP + 4.2, front + 1.0)), Vector3(r.size.x - 2.0, 0.06, 2.4), Color(0.1, 0.45, 0.65))
	if not detailed:
		return
	g.kind = PierMesh.K_NEON
	var xf := Transform3D(Basis(), Vector3(c.x, DECK_TOP + h + 2.45, front - 0.03))
	g.letters("TOKEN TIDE", 1.1, xf, Color(1.0, 0.35, 0.75), r.size.x * 0.68)
	xf.origin.y -= 1.05
	g.letters("ARCADE", 0.7, xf, Color(0.35, 0.95, 1.0), r.size.x * 0.4)
	g.kind = PierMesh.K_BULB
	var w := r.size.x * 0.75
	var k := 0
	for t in 41:
		var u := float(t) / 40.0
		for y: float in [DECK_TOP + h + 0.75, DECK_TOP + h + 3.25]:
			g.anim = float(k)
			g.ellipsoid(Transform3D(Basis(), Vector3(c.x - w * 0.5 + w * u, y, front - 0.02)), Vector3(0.07, 0.07, 0.05), Color(1.0, 0.8, 0.5), 4, 2)
			k += 1
	g.anim = 0.0
	# Doors: dark openings in the middle two bays.
	g.kind = PierMesh.K_RUBBER
	for k2 in [1, 2]:
		var x := r.position.x + bw * (float(k2) + 0.5)
		g.abox(Vector3(x, DECK_TOP + 1.2, front - 0.18), Vector3(2.6, 2.4, 0.04), Color.BLACK)


## The bumper-car hall: an open-sided pavilion on steel columns, a red roof with a striped
## valance, a pick-up grid under the roof, a steel floor ringed with rubber bumpers. The cars run
## in their own mesh (`_bumper_cars`).
static func _bumper_hall(g: PierMesh, detailed: bool) -> void:
	var r := BUMPER
	var c := r.get_center()
	var eave := DECK_TOP + 5.2
	g.kind = PierMesh.K_PAINT
	# Roof: a low gable over the eaves.
	var ridge := eave + 2.2
	for zs: float in [-1.0, 1.0]:
		var a := Vector3(r.position.x - 0.6, eave, c.y + zs * (r.size.y * 0.5 + 0.6))
		var b := Vector3(r.end.x + 0.6, eave, c.y + zs * (r.size.y * 0.5 + 0.6))
		var a2 := Vector3(r.position.x - 0.6, ridge, c.y)
		var b2 := Vector3(r.end.x + 0.6, ridge, c.y)
		var n := Vector3(0, r.size.y * 0.5, zs * 2.2).normalized()
		g.quad(a, b, b2, a2, n, Vector2(0, 0), Vector2(r.size.x, 0), Vector2(r.size.x, 9), Vector2(0, 9), Color(0.68, 0.12, 0.10))
		g.quad(a, b, b2, a2, -n, Vector2(0, 0), Vector2(r.size.x, 0), Vector2(r.size.x, 9), Vector2(0, 9), Color(0.3, 0.3, 0.3))
	for xs: float in [-1.0, 1.0]:
		var x := c.x + xs * (r.size.x * 0.5 + 0.6)
		g.tri(Vector3(x, eave, r.position.y - 0.6), Vector3(x, eave, r.end.y + 0.6), Vector3(x, ridge, c.y), Vector3(xs, 0, 0),
			Vector2.ZERO, Vector2(18, 0), Vector2(9, 2), WHITE)
	# Valance round the eaves.
	g.kind = PierMesh.K_CANVAS
	g.abox(Vector3(c.x, eave - 0.35, r.position.y - 0.55), Vector3(r.size.x + 1.2, 0.7, 0.05), Color(0.95, 0.75, 0.1))
	g.abox(Vector3(c.x, eave - 0.35, r.end.y + 0.55), Vector3(r.size.x + 1.2, 0.7, 0.05), Color(0.95, 0.75, 0.1))
	for xs: float in [-1.0, 1.0]:
		g.abox(Vector3(c.x + xs * (r.size.x * 0.5 + 0.55), eave - 0.35, c.y), Vector3(0.05, 0.7, r.size.y + 1.2), Color(0.95, 0.75, 0.1))
	# Columns.
	g.kind = PierMesh.K_PAINT
	for k in 5:
		var x := r.position.x + r.size.x * float(k) / 4.0
		for z: float in [r.position.y, r.end.y]:
			g.tube(Vector3(x, DECK_TOP, z), Vector3(x, eave, z), 0.14, 0.14, WHITE, 8 if detailed else 4)
	# Floor and bumper ring.
	g.kind = PierMesh.K_METAL
	g.abox(Vector3(c.x, DECK_TOP + 0.08, c.y), Vector3(r.size.x - 2.0, 0.16, r.size.y - 2.0), Color(0.45, 0.46, 0.48))
	if not detailed:
		return
	g.kind = PierMesh.K_RUBBER
	var fx := r.size.x * 0.5 - 1.2
	var fz := r.size.y * 0.5 - 1.2
	for zs: float in [-1.0, 1.0]:
		g.abox(Vector3(c.x, DECK_TOP + 0.5, c.y + zs * fz), Vector3(fx * 2.0, 0.6, 0.35), Color.BLACK)
	for xs: float in [-1.0, 1.0]:
		g.abox(Vector3(c.x + xs * fx, DECK_TOP + 0.5, c.y + 1.5), Vector3(0.35, 0.6, fz * 2.0 - 3.0), Color.BLACK)
	# Pick-up grid under the roof.
	g.kind = PierMesh.K_METAL
	var gx := r.position.x + 1.5
	while gx < r.end.x - 1.0:
		g.abox(Vector3(gx, DECK_TOP + 4.6, c.y), Vector3(0.05, 0.05, r.size.y - 2.4), Color(0.3, 0.3, 0.3))
		gx += 0.9
	var gz := r.position.y + 1.5
	while gz < r.end.y - 1.0:
		g.abox(Vector3(c.x, DECK_TOP + 4.62, gz), Vector3(r.size.x - 2.4, 0.05, 0.05), Color(0.3, 0.3, 0.3))
		gz += 0.9
	# The name on the front gable's beam and bulbs along the eaves.
	g.kind = PierMesh.K_SIGN
	g.abox(Vector3(c.x, eave + 0.8, r.end.y + 0.7), Vector3(11.0, 1.3, 0.2), Color(0.95, 0.75, 0.1))
	g.kind = PierMesh.K_NEON
	g.letters("BUMPER BAY", 0.85, Transform3D(Basis(), Vector3(c.x, eave + 0.8, r.end.y + 0.82)), Color(0.9, 0.1, 0.12), 10.0)
	g.kind = PierMesh.K_BULB
	var x := r.position.x
	var k := 0
	while x <= r.end.x:
		g.anim = float(k)
		g.ellipsoid(Transform3D(Basis(), Vector3(x, eave - 0.75, r.end.y + 0.58)), Vector3(0.06, 0.06, 0.06), Color(1.0, 0.85, 0.5), 4, 2)
		x += 0.7
		k += 1
	g.anim = 0.0


static func _bumper_cars(park: Node3D) -> void:
	var r := BUMPER
	var c := r.get_center()
	var hub := Vector3(c.x, DECK_TOP + 0.16, c.y)
	var key := "bumper_cars"
	if not _cache.has(key):
		var g := PierMesh.new()
		var half := Vector2(r.size.x * 0.5 - 1.6, r.size.y * 0.5 - 1.6)
		g.use("b", PierMesh.material("bumper", 3, {"hub": Vector3.ZERO, "floor_half": half}))
		g.slot("b")
		var cols: Array[Color] = [Color(0.85, 0.1, 0.1), Color(0.1, 0.35, 0.85), Color(0.95, 0.75, 0.1), Color(0.1, 0.65, 0.35), Color(0.9, 0.4, 0.1), Color(0.6, 0.2, 0.7)]
		for k in 10:
			g.anim = float(k + 1)
			var col: Color = cols[k % cols.size()]
			g.kind = PierMesh.K_PAINT
			g.box(Transform3D(Basis(), Vector3(0, 0.38, 0)), Vector3(1.9, 0.42, 1.25), col, 0.35)
			g.box(Transform3D(Basis(), Vector3(-0.25, 0.75, 0)), Vector3(0.7, 0.5, 1.0), col.darkened(0.2), 0.15)
			g.kind = PierMesh.K_RUBBER
			var ring := PackedVector3Array()
			for t in 16:
				var a := TAU * float(t) / 16.0
				ring.append(Vector3(cos(a) * 1.08, 0.22, sin(a) * 0.75))
			g.sweep(ring, 0.14, Color.BLACK, 5, true)
			g.ellipsoid(Transform3D(Basis(Vector3.BACK, 0.5), Vector3(0.45, 0.82, 0)), Vector3(0.2, 0.03, 0.2), Color.BLACK, 8, 3)
			g.kind = PierMesh.K_METAL
			g.tube(Vector3(-0.8, 0.6, 0), Vector3(-0.8, 4.3, 0), 0.025, 0.025, Color(0.7, 0.7, 0.7), 4)
			g.kind = PierMesh.K_BULB
			g.ellipsoid(Transform3D(Basis(), Vector3(-0.8, 4.35, 0)), Vector3(0.05, 0.05, 0.05), Color(0.6, 0.8, 1.0), 4, 2)
		_cache[key] = g.build_mesh()
	var mi := MeshInstance3D.new()
	mi.name = "BumperCars"
	mi.mesh = _cache[key]
	mi.position = hub
	park.add_child(mi)


## A food stand: a timber kiosk with its serving window under a striped awning, the name on a lit
## board on the roof, and the giant thing it sells on top.
static func _stand(g: PierMesh, s: Array) -> void:
	var at := Vector2(s[0], s[1])
	var yaw: float = s[2]
	var b := Basis(Vector3.UP, yaw)
	var o := Vector3(at.x, DECK_TOP, at.y)
	var xf := func(p: Vector3) -> Transform3D:
		return Transform3D(b, o + b * p)
	var kind: String = s[4]
	var body := {"fries": Color(0.85, 0.15, 0.12), "candy": Color(0.95, 0.55, 0.75), "corndog": Color(0.95, 0.70, 0.15),
		"lemon": Color(0.98, 0.88, 0.25), "funnel": Color(0.35, 0.65, 0.85)}.get(kind, WHITE) as Color
	g.kind = PierMesh.K_BOARDS
	g.box(xf.call(Vector3(0, 1.4, 0.3)), Vector3(4.0, 2.8, 2.6), body)
	g.kind = PierMesh.K_PAINT
	g.box(xf.call(Vector3(0, 2.95, 0.3)), Vector3(4.3, 0.3, 2.9), WHITE)
	g.box(xf.call(Vector3(0, 1.05, -1.1)), Vector3(3.6, 0.08, 0.5), WHITE)
	g.kind = PierMesh.K_WINDOW
	g.box(xf.call(Vector3(0, 1.75, -1.0)), Vector3(3.0, 1.2, 0.05), Color(1.0, 0.8, 0.55))
	g.kind = PierMesh.K_CANVAS
	g.box(Transform3D(b * Basis(Vector3.RIGHT, -0.4), o + b * Vector3(0, 2.55, -1.55)), Vector3(4.1, 0.05, 1.3), body)
	g.kind = PierMesh.K_SIGN
	g.box(xf.call(Vector3(0, 3.6, -0.6)), Vector3(4.0, 1.0, 0.15), Color(0.98, 0.96, 0.9))
	g.kind = PierMesh.K_PAINT
	var name_xf: Transform3D = xf.call(Vector3(0, 3.6, -0.69))
	name_xf.basis = name_xf.basis * Basis(Vector3.UP, PI)
	g.letters(s[3], 0.42, name_xf, body.darkened(0.45), 3.7)
	# The thing it sells, two metres tall on the roof.
	var top := Vector3(0.0, 3.1, 0.6)
	match kind:
		"fries":
			g.kind = PierMesh.K_PAINT
			g.box(xf.call(top + Vector3(0, 0.6, 0)), Vector3(1.1, 1.2, 0.8), Color(0.85, 0.12, 0.1), 0.15)
			for k in 9:
				var dx := float(k % 3 - 1) * 0.28
				var dz := float(int(k / 3.0) - 1) * 0.2
				var tilt := Basis(Vector3.BACK, dx * 0.6) * Basis(Vector3.RIGHT, dz * 0.8)
				g.box(Transform3D(b * tilt, o + b * (top + Vector3(dx, 1.5, dz))), Vector3(0.14, 1.1, 0.14), Color(0.98, 0.82, 0.35))
		"candy":
			g.kind = PierMesh.K_PAINT
			g.tube(o + b * (top + Vector3(0, 0, 0)), o + b * (top + Vector3(0, 1.0, 0)), 0.05, 0.12, WHITE, 6)
			g.ellipsoid(xf.call(top + Vector3(0, 1.55, 0)), Vector3(0.75, 0.65, 0.75), Color(0.98, 0.65, 0.82), 10, 7)
		"corndog":
			g.kind = PierMesh.K_PAINT
			g.tube(o + b * top, o + b * (top + Vector3(0, 0.8, 0)), 0.06, 0.06, Color(0.85, 0.75, 0.55), 6)
			g.ellipsoid(xf.call(top + Vector3(0, 1.55, 0)), Vector3(0.32, 0.8, 0.32), Color(0.78, 0.48, 0.15), 10, 7)
		"lemon":
			g.kind = PierMesh.K_PAINT
			g.ellipsoid(xf.call(top + Vector3(0, 0.8, 0)), Vector3(0.9, 0.7, 0.7), Color(0.98, 0.88, 0.2), 12, 8)
		_:
			g.kind = PierMesh.K_PAINT
			g.tube(o + b * (top + Vector3(0, 0.4, 0)), o + b * (top + Vector3(0, 0.75, 0)), 0.85, 0.85, Color(0.88, 0.70, 0.40), 14, true)
			g.ellipsoid(xf.call(top + Vector3(0, 0.82, 0)), Vector3(0.8, 0.1, 0.8), Color(0.98, 0.97, 0.95), 12, 4)
	# A row of bulbs along the awning's edge.
	g.kind = PierMesh.K_BULB
	for k in 9:
		g.anim = float(k)
		g.ellipsoid(xf.call(Vector3(-1.9 + float(k) * 0.475, 2.2, -2.15)), Vector3(0.05, 0.05, 0.05), Color(1.0, 0.85, 0.55), 4, 2)
	g.anim = 0.0


## A game booth: an open front over a counter, the prizes stacked on shelves up the back wall,
## the big ones hung from the top, a striped awning with bulbs, the game's name on a board.
static func _booth(g: PierMesh, bt: Array) -> void:
	var x: float = bt[0]
	var prize: Color = bt[2]
	var z := BOOTH_Z
	var w := 4.3
	g.kind = PierMesh.K_BOARDS
	g.abox(Vector3(x, DECK_TOP + 1.6, z - 1.6), Vector3(w, 3.2, 0.12), Color(0.95, 0.9, 0.78))
	for xs: float in [-1.0, 1.0]:
		g.abox(Vector3(x + xs * (w * 0.5 - 0.05), DECK_TOP + 1.6, z), Vector3(0.1, 3.2, 3.2), prize.darkened(0.15))
	g.kind = PierMesh.K_PAINT
	g.abox(Vector3(x, DECK_TOP + 0.5, z + 1.45), Vector3(w - 0.2, 1.0, 0.3), prize)
	g.abox(Vector3(x, DECK_TOP + 1.03, z + 1.45), Vector3(w - 0.1, 0.06, 0.45), WHITE)
	# Shelves of prizes: plush animals in the booth's colour and its neighbours'.
	var cols: Array[Color] = [prize, prize.lightened(0.3), Color(0.95, 0.85, 0.3), Color(0.4, 0.75, 0.95), Color(0.95, 0.5, 0.6)]
	for row in 3:
		var y := DECK_TOP + 1.2 + float(row) * 0.6
		g.kind = PierMesh.K_BOARDS
		g.abox(Vector3(x, y, z - 1.35), Vector3(w - 0.3, 0.05, 0.45), Color(0.9, 0.88, 0.8))
		g.kind = PierMesh.K_PAINT
		for k in 6:
			var px := x - w * 0.5 + 0.55 + float(k) * 0.64
			var col: Color = cols[(k + row) % cols.size()]
			g.ellipsoid(Transform3D(Basis(), Vector3(px, y + 0.2, z - 1.3)), Vector3(0.2, 0.18, 0.16), col, 6, 4)
			g.ellipsoid(Transform3D(Basis(), Vector3(px, y + 0.44, z - 1.28)), Vector3(0.13, 0.12, 0.12), col, 6, 4)
	for k in 3:
		var px := x - 1.2 + float(k) * 1.2
		g.ellipsoid(Transform3D(Basis(), Vector3(px, DECK_TOP + 2.9, z - 0.9)), Vector3(0.32, 0.4, 0.28), cols[(k + 2) % cols.size()], 8, 5)
		g.ellipsoid(Transform3D(Basis(), Vector3(px, DECK_TOP + 3.38, z - 0.88)), Vector3(0.22, 0.2, 0.2), cols[(k + 2) % cols.size()], 8, 5)
	g.kind = PierMesh.K_CANVAS
	g.box(Transform3D(Basis(Vector3.RIGHT, 0.3), Vector3(x, DECK_TOP + 3.35, z + 0.2)), Vector3(w + 0.2, 0.06, 3.6), prize)
	g.kind = PierMesh.K_SIGN
	g.abox(Vector3(x, DECK_TOP + 4.15, z + 1.0), Vector3(w - 0.4, 0.7, 0.1), Color(0.98, 0.95, 0.85))
	g.kind = PierMesh.K_PAINT
	g.letters(bt[1], 0.36, Transform3D(Basis(), Vector3(x, DECK_TOP + 4.15, z + 1.06)), prize.darkened(0.4), w - 0.7)
	g.kind = PierMesh.K_BULB
	for k in 8:
		g.anim = float(k)
		g.ellipsoid(Transform3D(Basis(), Vector3(x - w * 0.5 + 0.25 + float(k) * 0.55, DECK_TOP + 2.88, z + 1.92)), Vector3(0.05, 0.05, 0.05), Color(1.0, 0.85, 0.55), 4, 2)
	g.anim = 0.0


static func _bench(g: PierMesh, at: Vector2, yaw: float) -> void:
	var b := Basis(Vector3.UP, yaw)
	var o := Vector3(at.x, DECK_TOP, at.y)
	g.kind = PierMesh.K_BOARDS
	for k in 4:
		g.box(Transform3D(b, o + b * Vector3(0, 0.45, -0.18 + float(k) * 0.12)), Vector3(1.8, 0.04, 0.1), Color(0.55, 0.40, 0.26))
	for k in 3:
		g.box(Transform3D(b * Basis(Vector3.RIGHT, -0.2), o + b * Vector3(0, 0.62 + float(k) * 0.13, 0.27)), Vector3(1.8, 0.1, 0.035), Color(0.55, 0.40, 0.26))
	g.kind = PierMesh.K_METAL
	for xs: float in [-0.75, 0.75]:
		g.box(Transform3D(b, o + b * Vector3(xs, 0.22, 0.0)), Vector3(0.06, 0.44, 0.5), Color(0.15, 0.15, 0.15))
		g.box(Transform3D(b * Basis(Vector3.RIGHT, -0.2), o + b * Vector3(xs, 0.7, 0.26)), Vector3(0.05, 0.45, 0.05), Color(0.15, 0.15, 0.15))


static func _table(g: PierMesh, at: Vector2) -> void:
	var o := Vector3(at.x, DECK_TOP, at.y)
	g.kind = PierMesh.K_BOARDS
	g.abox(o + Vector3(0, 0.74, 0), Vector3(1.8, 0.05, 0.8), Color(0.6, 0.45, 0.3))
	for zs: float in [-1.0, 1.0]:
		g.abox(o + Vector3(0, 0.45, zs * 0.7), Vector3(1.8, 0.05, 0.3), Color(0.6, 0.45, 0.3))
	g.kind = PierMesh.K_METAL
	g.abox(o + Vector3(0, 0.37, 0), Vector3(1.2, 0.05, 1.5), Color(0.2, 0.2, 0.2))
	g.tube(o, o + Vector3(0, 2.4, 0), 0.03, 0.03, Color(0.8, 0.8, 0.8), 5)
	g.kind = PierMesh.K_CANVAS
	g.cone(o, 1.4, 2.1, 0.05, 2.55, 8, Color(0.1, 0.5, 0.6))
	g.cone(o, 1.4, 2.1, 0.05, 2.55, 8, Color(0.1, 0.5, 0.6), true)


## Double-globe lamp posts down both edges of the pier.
static func _lamps(g: PierMesh, detailed: bool) -> void:
	for i in LAMP_COUNT:
		var x := LAMP_FROM - float(i) * LAMP_STEP
		for zs: float in [-1.0, 1.0]:
			var o := Vector3(x, DECK_TOP, zs * LAMP_Z)
			g.kind = PierMesh.K_PAINT
			g.tube(o, o + Vector3(0, 5.0, 0), 0.09, 0.06, Color(0.12, 0.2, 0.25), 8 if detailed else 4)
			if detailed:
				g.tube(o, o + Vector3(0, 0.6, 0), 0.16, 0.12, Color(0.12, 0.2, 0.25), 8)
				g.beam(o + Vector3(-0.55, 5.0, 0), o + Vector3(0.55, 5.0, 0), 0.06, 0.06, Color(0.12, 0.2, 0.25))
			g.kind = PierMesh.K_BULB
			for xs: float in [-0.55, 0.55]:
				g.ellipsoid(Transform3D(Basis(), o + Vector3(xs, 5.35, 0)), Vector3(0.24, 0.3, 0.24), Color(1.0, 0.9, 0.7), 8 if detailed else 4, 5 if detailed else 3)


## Strings of bulbs swagged across the pier between the lamps, and over the food court.
static func _strings(g: PierMesh) -> void:
	var spans: Array = []
	for i in range(2, LAMP_COUNT):
		var x := LAMP_FROM - float(i) * LAMP_STEP
		spans.append([Vector3(x, DECK_TOP + 5.0, -LAMP_Z), Vector3(x - LAMP_STEP * 0.5, DECK_TOP + 5.0, LAMP_Z)])
		spans.append([Vector3(x - LAMP_STEP * 0.5, DECK_TOP + 5.0, LAMP_Z), Vector3(x - LAMP_STEP, DECK_TOP + 5.0, -LAMP_Z)])
	spans.append([Vector3(-203.0, DECK_TOP + 4.5, 16.0), Vector3(-203.0, DECK_TOP + 4.5, 58.0)])
	var palette: Array[Color] = [Color(1.0, 0.85, 0.55), Color(1.0, 0.4, 0.35), Color(0.45, 0.8, 1.0), Color(0.6, 1.0, 0.5), Color(1.0, 0.8, 0.3)]
	var n := 0
	for sp: Array in spans:
		var a: Vector3 = sp[0]
		var b: Vector3 = sp[1]
		var length := a.distance_to(b)
		var sag := length * 0.05
		var pts := PackedVector3Array()
		var steps := int(length / 0.8)
		for k in steps + 1:
			var t := float(k) / float(steps)
			pts.append(a.lerp(b, t) - Vector3(0, sag * 4.0 * t * (1.0 - t), 0))
		g.kind = PierMesh.K_RUBBER
		g.sweep(pts, 0.012, Color.BLACK, 3)
		g.kind = PierMesh.K_BULB
		for k in range(1, pts.size() - 1):
			g.anim = float(n)
			n += 1
			g.ellipsoid(Transform3D(Basis(), pts[k] - Vector3(0, 0.08, 0)), Vector3(0.05, 0.065, 0.05), palette[k % palette.size()], 4, 2)
	g.anim = 0.0
	# The poles at the food court's ends.
	g.kind = PierMesh.K_PAINT
	for z: float in [16.0, 58.0]:
		g.tube(Vector3(-203.0, DECK_TOP, z), Vector3(-203.0, DECK_TOP + 4.8, z), 0.07, 0.06, Color(0.12, 0.2, 0.25), 6)


## The wheel's queue: switchback rails in front of its platform.
static func _wheel_queue(g: PierMesh, detailed: bool) -> void:
	if not detailed:
		return
	g.kind = PierMesh.K_METAL
	var x0 := WHEEL_AT.x
	for xs: float in [-2.0, -0.3, 1.4]:
		var a := Vector3(x0 + xs, DECK_TOP + 1.0, WHEEL_AT.y - 10.5)
		var b := Vector3(x0 + xs, DECK_TOP + 1.0, WHEEL_AT.y - 4.8)
		g.tube(a, b, 0.03, 0.03, Color(0.8, 0.8, 0.8), 6)
		for k in 4:
			var p := a.lerp(b, float(k) / 3.0)
			g.tube(Vector3(p.x, DECK_TOP, p.z), p, 0.03, 0.03, Color(0.8, 0.8, 0.8), 6)


# --- Light pools, real lights, collision -------------------------------------------------------

## The deck's light pools: centre brightness and how fast they fall off toward the rim.
const POOL_STRENGTH := 0.75
const POOL_FALLOFF := 2.2


static func _pool_mesh() -> ArrayMesh:
	var v := PackedVector3Array()
	var uv := PackedVector2Array()
	var col := PackedColorArray()
	var add := func(c: Vector3, r: float, tint: Color) -> void:
		var corners := [Vector3(-r, 0, -r), Vector3(r, 0, -r), Vector3(r, 0, r), Vector3(-r, 0, r)]
		var uvs := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
		for k: int in [0, 1, 2, 0, 2, 3]:
			v.append(c + (corners[k] as Vector3))
			uv.append(uvs[k])
			col.append(tint)
	for i in LAMP_COUNT:
		var x := LAMP_FROM - float(i) * LAMP_STEP
		for zs: float in [-1.0, 1.0]:
			add.call(Vector3(x, DECK_TOP + 0.03, zs * (LAMP_Z - 1.5)), 7.0, Color(1.0, 0.85, 0.6))
	add.call(Vector3(ARCADE.get_center().x, DECK_TOP + 0.03, ARCADE.end.y + 4.0), 14.0, Color(0.95, 0.72, 1.0))
	add.call(Vector3(BUMPER.get_center().x, DECK_TOP + 0.03, BUMPER.get_center().y), 13.0, Color(1.0, 0.85, 0.6))
	add.call(Vector3(CAROUSEL_AT.x, DECK_TOP + 0.03, CAROUSEL_AT.y), 15.0, Color(1.0, 0.8, 0.5))
	add.call(Vector3(WHEEL_AT.x, DECK_TOP + 0.03, WHEEL_AT.y), 16.0, Color(0.88, 0.78, 1.0))
	for s: Array in STANDS:
		add.call(Vector3(s[0], DECK_TOP + 0.03, s[1]), 5.0, Color(1.0, 0.85, 0.6))
	for b: Array in BOOTHS:
		add.call(Vector3(b[0], DECK_TOP + 0.03, BOOTH_Z + 2.0), 3.5, Color(1.0, 0.85, 0.6))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_COLOR] = col
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	# Its own copy of the street lamps' pool material: these pools are 7-16 m across and
	# overlap, and at the lamps' strength (1.6) with their falloff they drew as flat, clipped
	# discs on Forward+ (auto exposure opens up over the dark deck): the arcade's a solid magenta
	# ellipse. Dimmer, and falling off toward the rim, they read as light on the boards.
	var mat := PropFactory.light_pool_material().duplicate() as ShaderMaterial
	mat.set_shader_parameter("strength", POOL_STRENGTH)
	mat.set_shader_parameter("falloff", POOL_FALLOFF)
	mesh.surface_set_material(0, mat)
	return mesh


static func _add_lights(park: Node3D) -> void:
	var spots: Array = [[Vector3(-83.0, DECK_TOP + 4.0, -9.0), 20.0], [Vector3(-120.0, DECK_TOP + 4.0, -22.0), 18.0],
		[CAROUSEL_AT, 18.0], [Vector3(WHEEL_AT.x, DECK_TOP + 6.0, WHEEL_AT.y - 8.0), 22.0],
		[Vector3(-196.0, DECK_TOP + 4.0, 38.0), 18.0], [Vector3(-35.0, DECK_TOP + 5.0, 0.0), 22.0]]
	for sp: Array in spots:
		var at: Variant = sp[0]
		var light := OmniLight3D.new()
		light.position = Vector3(at.x, DECK_TOP + 4.5, at.y) if at is Vector2 else at
		light.omni_range = float(sp[1])
		light.omni_attenuation = 1.2
		light.light_color = Color(1.0, 0.86, 0.7)
		light.light_energy = 0.0
		light.shadow_enabled = false
		light.distance_fade_enabled = true
		light.distance_fade_begin = 90.0
		light.distance_fade_length = 25.0
		light.add_to_group("lamp_light")
		park.add_child(light)


## The pier's collision: the decks and the ramp you walk on, the buildings' boxes, the carousel's
## base. (The wheel and the coaster carry their own PierRideBody.)
static func _add_body(park: Node3D) -> void:
	var body := StaticBody3D.new()
	body.name = "PierBody"
	body.collision_layer = 1
	body.collision_mask = 0
	park.add_child(body)
	var add := func(c: Vector3, size: Vector3, basis: Basis = Basis()) -> void:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		cs.shape = bs
		cs.transform = Transform3D(basis, c)
		body.add_child(cs)
	for r: Rect2 in [MAIN, NORTH, SOUTH]:
		var c := r.get_center()
		add.call(Vector3(c.x, DECK_Y, c.y), Vector3(r.size.x, DECK_T, r.size.y))
	var run := 34.0
	var d := Vector3(run, 0.15 - DECK_TOP, 0.0)
	var basis := Basis(Vector3.BACK, atan2(d.y, d.x))
	add.call(Vector3(run * 0.5, (DECK_TOP + 0.15) * 0.5, 0.0) - basis.y * 0.3, Vector3(d.length(), 0.6, 10.0), basis)
	# Rails (waist high: you can lean on them, and jump over).
	for i in OUTLINE.size() - 1:
		var a: Vector2 = OUTLINE[i]
		var b: Vector2 = OUTLINE[i + 1]
		var mid := (a + b) * 0.5
		var len := a.distance_to(b)
		var dir := (b - a) / len
		add.call(Vector3(mid.x, DECK_TOP + 0.55, mid.y), Vector3(0.15, 1.1, len), Basis(Vector3.UP, atan2(-dir.x, -dir.y)))
	add.call(Vector3(ARCADE.get_center().x, DECK_TOP + 4.0, ARCADE.get_center().y), Vector3(ARCADE.size.x, 8.0, ARCADE.size.y))
	var bc := BUMPER.get_center()
	add.call(Vector3(bc.x, DECK_TOP + 6.2, bc.y), Vector3(BUMPER.size.x + 1.2, 2.0, BUMPER.size.y + 1.2))
	for s: Array in STANDS:
		var b := Basis(Vector3.UP, float(s[2]))
		add.call(Vector3(s[0], DECK_TOP + 1.5, s[1]) + b * Vector3(0, 0, 0.3), Vector3(4.0, 3.0, 2.6), b)
	for bt: Array in BOOTHS:
		add.call(Vector3(bt[0], DECK_TOP + 1.6, BOOTH_Z - 1.6), Vector3(4.3, 3.2, 0.3))
		add.call(Vector3(bt[0], DECK_TOP + 0.5, BOOTH_Z + 1.45), Vector3(4.2, 1.0, 0.3))
	var cyl := CollisionShape3D.new()
	var cs := CylinderShape3D.new()
	cs.radius = PierCarousel.R_PLATFORM + 0.6
	cs.height = 0.6
	cyl.shape = cs
	cyl.position = Vector3(CAROUSEL_AT.x, DECK_TOP + 0.25, CAROUSEL_AT.y)
	body.add_child(cyl)
