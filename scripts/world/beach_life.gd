class_name BeachLife
extends RefCounted
## A Los Angeles beach on a warm afternoon (2026-10-05, "the beach is empty of people - fill it").
## The sand, the surf and the piers were there; this puts people on them:
##
## * **Sunbathers** in groups of one to four on towels - on their backs, their fronts, hands behind
##   the head, sitting up, leaning back, in low beach chairs, standing about - under striped
##   umbrellas, with coolers, bags, boogie boards and the odd surfboard. Busiest by the waterline,
##   thinning toward the back of the beach; busiest mid-afternoon, a few left at sunset, nobody
##   at night (density()). Each is a static figure (BeachFigure: the camps' trick, posed once,
##   baked, a chunk's merged into one mesh) in swimwear (BeachGoer.swim_mesh()), woken into a live
##   BeachGoer when shot, knocked or near gunfire.
## * **The water**: swimmers treading water inside the break, surfers sitting on their boards past
##   it waiting for a set, one or two catching a wave and riding it in (BeachActivity), walkers with
##   boards under their arms going down to the water and back (BeachWalker).
## * **Volleyball**: a court (posts, net, boundary tapes) on some stretches, a two-on-two game going
##   on through the day (live BeachGoers, BeachActivity runs the rally and the ball).
## * **The bike path**: a concrete path along the back of the beach (path_x()) with its yellow
##   centre line, beach cruisers ridden along it (the legs solved onto the pedals, the crank
##   turning: BeachFigure.ride_meshes()) and skateboarders.
## * **The lifeguard tower** is a real one now (tower_mesh(): the raised blue cabin, deck, ramp),
##   turned to the sea, with a lifeguard in it through the day.
##
## Everything is placed from hashes of the seed and a WORLD cell (CELL_Z metres of shore) and the
## hour the chunk is built at - never the block's rng - so the beach is the same beach from any
## chunk and the block's own rolls (palms, the tower) do not move. plan_block() is pure (the smoke
## test asks it). LOD chunks draw the towels and umbrellas as dots of colour on the sand (build_lod)
## so the beach reads busy from the air.
##
## `BEACH_LIFE=0` in the environment turns all of it off (the A/B). force_hour pins the hour.

static var enabled: bool = OS.get_environment("BEACH_LIFE") != "0"
## The hour to build for (tests and stills); < 0 reads the city's clock (DayNight).
static var force_hour: float = -1.0

## Metres of shore per placement cell, and the across-the-beach bands (fraction of the beach's
## width from the waterline) a group may sit in. The swash runs to about 0.19.
const CELL_Z := 6.5
const BANDS := [0.21, 0.29, 0.37, 0.45, 0.53, 0.61, 0.69, 0.77]
## Odds of a band holding a group at full density, by how far up the beach it is: the waterline
## rows are taken first, the back thins out (shape()).
const PEAK_ODDS := 0.5
## Across fraction of the bike path's centre line, its width (m), its lift over the sand, and the
## spacing of its expansion joints (the shader's).
const PATH_AT := 0.86
const PATH_WIDTH := 3.6
const PATH_LIFT := 0.07
const PATH_STEP := 3.0
## Volleyball: odds a chunk's stretch has a court, its centre's across fraction, its size (m, the
## long side along the shore) and how far the sunbathers keep off it.
const COURT_ODDS := 0.5
const COURT_AT := 0.655
const COURT_SIZE := Vector2(8.0, 16.0)
const COURT_CLEAR := 3.0
## People in the water at full density, per chunk: swimmers inside the break, surfers outside it.
const SWIMMERS := 6
const SURFERS := 6
## Riders on the bike path per chunk at full density, and how many of them skate.
const RIDERS := 4
const SKATERS := 2
## Walkers on the sand (with a board under the arm, or strolling the waterline) per chunk.
const WALKERS := 4
## Landmarks whose ground is their own (the boardwalk's courts and walk, the piers): nothing here
## within this many metres of their anchor along the shore.
const KEEP_OFF := {"venice_boardwalk": 225.0, "manhattan_pier": 22.0, "redondo_pier": 80.0}
## How far the figures draw and their shadows reach (m).
const FIGURE_DRAW := 170.0
const FIGURE_SHADOW := 60.0
## Props: draw distance (m), and the LOD dots' (m).
const PROP_DRAW := 190.0
const DOT_DRAW := 1400.0

## Vertex-alpha codes (shaders/beach_props.gdshader reads round(alpha * 20)).
const A_PLAIN := 0.0
const A_PAINT := 0.05
const A_TOWEL := 0.10
const A_CANVAS := 0.15
const A_NET := 0.20
const A_BALL := 0.25
const A_BOARD := 0.30
const A_PATH := 0.35
const A_GLASS := 0.45
const A_TAPE := 0.50

## Towel and umbrella colours (sRGB): the first stripe from these, the second from CANVAS2 by the
## instance's custom alpha (the shader's copy; the smoke test checks it).
const TOWELS: Array[Color] = [
	Color(0.92, 0.25, 0.22), Color(0.14, 0.42, 0.78), Color(0.98, 0.78, 0.18), Color(0.12, 0.62, 0.58),
	Color(0.95, 0.5, 0.62), Color(0.96, 0.95, 0.9), Color(0.55, 0.32, 0.7), Color(0.98, 0.55, 0.15),
	Color(0.2, 0.22, 0.28), Color(0.45, 0.75, 0.3),
]
const CANVAS2: Array[Color] = [Color(0.97, 0.96, 0.92), Color(0.98, 0.84, 0.25), Color(0.1, 0.32, 0.6),
	Color(0.9, 0.2, 0.2), Color(0.2, 0.62, 0.55), Color(0.99, 0.62, 0.7)]
const COOLERS: Array[Color] = [Color(0.2, 0.42, 0.75), Color(0.85, 0.15, 0.15), Color(0.95, 0.95, 0.93), Color(0.25, 0.6, 0.35)]
const BOARDS: Array[Color] = [Color(0.96, 0.95, 0.9), Color(0.98, 0.84, 0.3), Color(0.35, 0.72, 0.85), Color(0.95, 0.45, 0.25), Color(0.25, 0.3, 0.75)]
const BIKES: Array[Color] = [Color(0.45, 0.78, 0.82), Color(0.9, 0.3, 0.32), Color(0.96, 0.92, 0.82), Color(0.2, 0.22, 0.25), Color(0.95, 0.72, 0.2), Color(0.55, 0.85, 0.55)]
## The lifeguard: which crowd rig and which suit (red trunks).
const LIFEGUARD_MODEL := 7
const LIFEGUARD_SUIT := 2
## The lifeguard tower's blue and its trim (sRGB).
const TOWER_BLUE := Color(0.42, 0.66, 0.86)
const TOWER_TRIM := Color(0.95, 0.95, 0.92)

## Poses a sunbather takes, as [weight, base pose, BEACH_POSES key, towel, chair].
const POSE_ODDS := [
	[0.27, RoughSleeper.Pose.LIE, "lie_back", true, false],
	[0.18, RoughSleeper.Pose.LIE, "lie_front", true, false],
	[0.10, RoughSleeper.Pose.LIE, "lie_back_relax", true, false],
	[0.11, RoughSleeper.Pose.SIT, "", true, false],
	[0.12, RoughSleeper.Pose.SIT, "sit_lean", true, false],
	[0.13, RoughSleeper.Pose.CHAIR, "beach_chair", false, true],
	[0.09, RoughSleeper.Pose.STAND, "", false, false],
]

static var _meshes: Dictionary = {}
static var _material: ShaderMaterial
static var _keep_off: Array = []


# --- When and how many --------------------------------------------------------------------------

## The hour a chunk is built for: force_hour, else the city's DayNight, else mid-afternoon.
static func hour_now(node: Node) -> float:
	if force_hour >= 0.0:
		return force_hour
	var tree := node.get_tree() if node and node.is_inside_tree() else (Engine.get_main_loop() as SceneTree)
	var scene := tree.current_scene if tree else null
	if scene:
		var dn := scene.get_node_or_null("DayNight")
		if dn and dn.get("hour") != null:
			return float(dn.get("hour"))
	return 15.0


## How full the beach is at `hour` (0 nobody .. 1 a summer mid-afternoon): a few early walkers and
## surfers, filling through the late morning, full from one to half past four, thinning toward
## sunset, a few left at dusk, nobody at night.
static func density(hour: float) -> float:
	var h := fposmod(hour, 24.0)
	if h < 6.5 or h > 20.5:
		return 0.0
	if h < 10.0:
		return lerpf(0.06, 0.4, smoothstep(6.5, 10.0, h))
	if h < 13.0:
		return lerpf(0.4, 1.0, smoothstep(10.0, 13.0, h))
	if h < 16.5:
		return 1.0
	if h < 18.5:
		return lerpf(1.0, 0.3, smoothstep(16.5, 18.5, h))
	return lerpf(0.3, 0.0, smoothstep(18.5, 20.5, h))


## The weather's share: a grey day thins the beach, rain clears it.
static func weather_factor(node: Node) -> float:
	var tree := node.get_tree() if node and node.is_inside_tree() else (Engine.get_main_loop() as SceneTree)
	var scene := tree.current_scene if tree else null
	var w := scene.get_node_or_null("Weather") if scene else null
	if w == null or w.get("state") == null:
		return 1.0
	match int(w.get("state")):
		1:
			return 0.5
		2, 3:
			return 0.05
	return 1.0


## The share of a band's cells taken, by how far up the beach it is (0 waterline .. 1 the town):
## people take the front rows first.
static func shape(a: float) -> float:
	return 0.12 + 0.88 * exp(-pow((a - 0.27) / 0.24, 2.0))


static func _h(parts: Array) -> float:
	return float(absi(hash(parts)) % 1000003) / 1000003.0


static func _hi(parts: Array) -> int:
	return absi(hash(parts))


# --- Where -------------------------------------------------------------------------------------

## True where the beach is not this file's to fill: the replica's own coast (Malaga Cove and the
## Esplanade's sand under the bluff keeps its own furniture; people still come), the boardwalk,
## the piers. `with_people` asks only about people (the replica's beach has them).
static func kept_off(plan: CityPlan, z: float, with_people: bool = false) -> bool:
	if _keep_off.is_empty():
		for lm: Dictionary in Landmarks.all():
			if KEEP_OFF.has(String(lm.id)):
				_keep_off.append([(lm.anchor as Vector2).y, float(KEEP_OFF[String(lm.id)])])
		if _keep_off.is_empty():
			_keep_off.append([INF, 0.0])
	for k: Array in _keep_off:
		if absf(z - float(k[0])) < float(k[1]):
			return true
	if not with_people and plan.macro and plan.macro.replica:
		var cr: Vector2 = plan.macro.replica.coast_range()
		if z > cr.x - 60.0 and z < cr.y + 60.0:
			return true
	return false


## World x of the bike path's centre line at z, and its top.
static func path_x(plan: CityPlan, z: float) -> float:
	return plan.macro.coast_x(z) + plan.macro.beach_width_at(z) * PATH_AT


## The sand under (x, z) as the sand mesh draws it (CityChunk._build_sand(): straight runs between
## its rows - the berm crest, the backshore falling to the town), or the sea's surface seaward of
## the waterline. `chunk` may be any node; a chunk without a macro map answers `fallback`.
static func ground_at(chunk: Node, x: float, z: float, fallback: float = 0.3) -> float:
	var ch := chunk as CityChunk
	if ch == null or ch.plan == null or ch.plan.macro == null:
		return fallback
	return sand_y(ch, x, z)


static func sand_y(ch: CityChunk, x: float, z: float) -> float:
	var macro: MacroMap = ch.plan.macro
	var cx := macro.coast_x(z)
	var w := maxf(macro.beach_width_at(z), 1.0)
	var d := x - cx
	if d < 0.0:
		return 0.15
	if d < CityChunk.SAND_SWASH:
		return lerpf(CityChunk.SAND_EDGE, ch._sand_y(z, CityChunk.SAND_SWASH / w), d / CityChunk.SAND_SWASH)
	var berm := w * CityChunk.SAND_BERM_AT
	if d < berm:
		return lerpf(ch._sand_y(z, CityChunk.SAND_SWASH / w), ch._sand_y(z, CityChunk.SAND_BERM_AT), (d - CityChunk.SAND_SWASH) / maxf(berm - CityChunk.SAND_SWASH, 0.01))
	var inland := w + CityChunk.SAND_LIP
	return lerpf(ch._sand_y(z, CityChunk.SAND_BERM_AT), CityChunk.SAND_HIGH, clampf((d - berm) / maxf(inland - berm, 0.01), 0.0, 1.0))


## The court on the stretch z0..z1 (a world cell range), or {}: {centre: Vector2, yaw}.
static func court_in(plan: CityPlan, z0: float, z1: float) -> Dictionary:
	# One possible court every 4 cells of shore, decided by the cell, so a court is never split
	# between two chunks' plans.
	var first := ceili(z0 / (CELL_Z * 4.0))
	var last := floori(z1 / (CELL_Z * 4.0))
	for k in range(first, last + 1):
		var zc := (float(k) + 0.5) * CELL_Z * 4.0
		if zc - COURT_SIZE.y * 0.5 - 2.0 < z0 or zc + COURT_SIZE.y * 0.5 + 2.0 > z1:
			continue
		if _h([plan.seed, "beach_court", k]) >= COURT_ODDS or kept_off(plan, zc):
			continue
		if plan.macro.beach_width_at(zc) < 50.0:
			continue
		var x := plan.macro.coast_x(zc) + plan.macro.beach_width_at(zc) * COURT_AT
		# Turned with the shore, so the long side runs along it.
		var slope := (plan.macro.coast_x(zc + 2.0) - plan.macro.coast_x(zc - 2.0)) / 4.0
		return {"centre": Vector2(x, zc), "yaw": atan(slope), "k": k}
	return {}


## Everything a stretch of beach holds at `hour` (pure): `z0`..`z1` is the stretch of shore in
## world z, `obstacles` [Vector2 point, radius] it must keep clear of (palms, the tower). Returns
## {"people": [{at, yaw, pose, key, model, towel, chair, group}], "props": [{kind, at, yaw, ...}],
## "court": {}, "dens": float}. People are BeachLife's world-cell rolls; `dens` folds in the hour
## and the weather (the caller's).
static func plan_stretch(plan: CityPlan, z0: float, z1: float, dens: float, obstacles: Array = []) -> Dictionary:
	var out := {"people": [], "props": [], "court": {}, "dens": dens}
	if plan.macro == null:
		return out
	var court := court_in(plan, z0, z1)
	out.court = court
	if dens <= 0.0:
		return out
	var macro: MacroMap = plan.macro
	var first := ceili(z0 / CELL_Z)
	var last := floori((z1 - 0.01) / CELL_Z)
	var group := 0
	for cell in range(first, last + 1):
		var zc := (float(cell) + 0.5) * CELL_Z
		if zc < z0 + 1.5 or zc > z1 - 1.5 or kept_off(plan, zc, true):
			continue
		var cx := macro.coast_x(zc)
		var w := macro.beach_width_at(zc)
		var slope := (macro.coast_x(zc + 2.0) - macro.coast_x(zc - 2.0)) / 4.0
		# The shore's frame: `land` across the sand (inland), `along` the shore (+z).
		var land := Vector2(1.0, -slope).normalized()
		var along := Vector2(slope, 1.0).normalized()
		var sea_yaw := atan2(land.x, land.y)
		for b in BANDS.size():
			var a: float = BANDS[b]
			if w * a > w - 4.0:
				continue
			if _h([plan.seed, "beach_cell", cell, b]) >= PEAK_ODDS * dens * shape(a):
				continue
			var hb := _hi([plan.seed, "beach_group", cell, b])
			var jit := Vector2(_h([hb, 1]) - 0.5, _h([hb, 2]) - 0.5)
			var centre := Vector2(cx + w * a, zc) + land * jit.x * 2.5 + along * jit.y * 2.0
			var n := 1 + int(_h([hb, 3]) > 0.35) + int(_h([hb, 4]) > 0.62) + int(_h([hb, 5]) > 0.86)
			var span := float(n) * 1.15
			if not court.is_empty() and _near_court(court, centre, span * 0.5 + COURT_CLEAR):
				continue
			if not _clear_of(obstacles, centre, span * 0.5 + 1.2):
				continue
			var yaw := sea_yaw + (_h([hb, 6]) - 0.5) * 0.5
			var shaded := _h([hb, 7]) < 0.45
			for i in n:
				var hp := _hi([hb, "person", i])
				var at := centre + along * (float(i) - float(n - 1) * 0.5) * 1.15
				var pick := _h([hp, 0])
				var row: Array = POSE_ODDS[POSE_ODDS.size() - 1]
				for r: Array in POSE_ODDS:
					if pick < float(r[0]):
						row = r
						break
					pick -= float(r[0])
				var py := yaw + (_h([hp, 1]) - 0.5) * 0.3
				if int(row[1]) == RoughSleeper.Pose.STAND:
					# Standing by the towels, turned to the group.
					py = yaw + PI * 0.5 * (1.0 if i % 2 == 0 else -1.0) + (_h([hp, 1]) - 0.5)
					at += land * 0.4
				var person := {"at": at, "yaw": py, "pose": int(row[1]), "key": String(row[2]),
					"model": BeachGoer.BEACH_MODELS[_hi([hp, 2]) % BeachGoer.BEACH_MODELS.size()], "group": group}
				out.people.append(person)
				if bool(row[3]):
					# The towel under the body (lying: centred a little toward the feet, which point
					# to the sea).
					var tc := at - land * (0.1 if String(row[2]).begins_with("lie") else -0.15)
					out.props.append({"kind": "towel", "at": tc, "yaw": yaw + (_h([hp, 3]) - 0.5) * 0.12,
						"paint": TOWELS[_hi([hp, 4]) % TOWELS.size()], "pal": _hi([hp, 5]) % CANVAS2.size()})
				if bool(row[4]):
					out.props.append({"kind": "chair", "at": at, "yaw": py, "paint": TOWELS[_hi([hp, 4]) % TOWELS.size()], "pal": _hi([hp, 5]) % CANVAS2.size()})
				if _h([hp, 6]) < 0.4:
					out.props.append({"kind": "bag", "at": at + land * 1.25 + along * 0.35, "yaw": _h([hp, 7]) * TAU,
						"paint": TOWELS[_hi([hp, 8]) % TOWELS.size()], "pal": 0})
			var gc := centre
			if shaded:
				out.props.append({"kind": "umbrella", "at": gc + land * 1.15 + along * (_h([hb, 8]) - 0.5) * span * 0.6,
					"yaw": _h([hb, 9]) * TAU, "tilt": (_h([hb, 10]) - 0.5) * 0.25,
					"paint": TOWELS[_hi([hb, 11]) % TOWELS.size()], "pal": _hi([hb, 12]) % CANVAS2.size()})
			if _h([hb, 13]) < 0.38:
				out.props.append({"kind": "cooler", "at": gc + along * (span * 0.5 + 0.55) + land * 0.5, "yaw": yaw + (_h([hb, 14]) - 0.5),
					"paint": COOLERS[_hi([hb, 15]) % COOLERS.size()], "pal": 0})
			if _h([hb, 16]) < 0.17:
				out.props.append({"kind": "boogie", "at": gc - land * 1.4 + along * (_h([hb, 17]) - 0.5) * span, "yaw": yaw + PI * 0.5 + (_h([hb, 18]) - 0.5),
					"paint": BOARDS[_hi([hb, 19]) % BOARDS.size()], "pal": 0})
			if _h([hb, 20]) < 0.08:
				out.props.append({"kind": "surfboard", "at": gc - land * 1.8 - along * span * 0.4, "yaw": yaw + PI * 0.5,
					"paint": BOARDS[_hi([hb, 21]) % BOARDS.size()], "pal": 0})
			group += 1
	return out


static func _near_court(court: Dictionary, p: Vector2, pad: float) -> bool:
	var c: Vector2 = court.centre
	var local := (p - c).rotated(float(court.yaw))
	return absf(local.x) < COURT_SIZE.x * 0.5 + pad and absf(local.y) < COURT_SIZE.y * 0.5 + pad


static func _clear_of(obstacles: Array, p: Vector2, r: float) -> bool:
	for o: Array in obstacles:
		if (o[0] as Vector2).distance_to(p) < float(o[1]) + r:
			return false
	return true


## The swimmers, surfers, riders and walkers for a stretch (pure, like plan_stretch): each list a
## count, the hashes BeachActivity works from.
static func plan_activity(plan: CityPlan, z0: float, z1: float, dens: float) -> Dictionary:
	var k := floori((z0 + z1) * 0.5 / CELL_Z)
	var f := clampf(dens, 0.0, 1.0)
	var with_path := not kept_off(plan, (z0 + z1) * 0.5)
	return {
		"swimmers": roundi(SWIMMERS * f * _h([plan.seed, "swim", k]) * 1.4),
		"surfers": roundi(SURFERS * (0.3 + 0.7 * f) * (0.5 + 0.5 * _h([plan.seed, "surf", k]))) if dens > 0.0 else 0,
		"riders": roundi(RIDERS * f * (0.5 + 0.5 * _h([plan.seed, "ride", k]))) if with_path else 0,
		"skaters": roundi(SKATERS * f * _h([plan.seed, "skate", k])) if with_path else 0,
		"walkers": roundi(WALKERS * f * (0.4 + 0.6 * _h([plan.seed, "walk", k]))),
		"lifeguard": dens > 0.0,
	}


# --- Building a chunk ---------------------------------------------------------------------------

## A FULL beach chunk's life, called at the end of its _build_beach(): the stretch `z0`..`z1` of
## shore, `obstacles` its palms and tower ([point, radius]), `tower` the tower ({at, yaw} or {}).
## Lays the path and the props at once and queues the figures and the activity as steps of their
## own (CityChunk._run_or_defer), so no one step is long.
static func build(ch: CityChunk, z0: float, z1: float, obstacles: Array, tower: Dictionary) -> void:
	if not enabled or ch.plan == null or ch.plan.macro == null:
		return
	var plan := ch.plan
	var hour := hour_now(ch)
	var dens := density(hour) * weather_factor(ch)
	var stretch := plan_stretch(plan, z0, z1, dens, obstacles)
	ch.set_meta("beach_plan", stretch)
	if not kept_off(plan, (z0 + z1) * 0.5):
		_build_path(ch, z0, z1)
	_build_court(ch, stretch.court)
	_add_props(ch, stretch.props)
	var people: Array = stretch.people.duplicate()
	var h := fposmod(hour, 24.0)
	if not tower.is_empty() and dens > 0.0 and h >= 9.0 and h <= 19.5:
		# The lifeguard, on the deck at the rail watching the water, in the red trunks.
		var ty: float = tower.yaw
		var fwd := Vector2(-sin(ty), -cos(ty))
		var at: Vector2 = (tower.at as Vector2) + fwd * 0.75
		people.append({"at": at, "yaw": ty, "pose": RoughSleeper.Pose.STAND, "key": "", "model": LIFEGUARD_MODEL,
			"group": -1, "suit": LIFEGUARD_SUIT, "lift": float(tower.y) + TOWER_DECK_Y - sand_y(ch, at.x, at.y)})
	var activity := plan_activity(plan, z0, z1, dens)
	ch._run_or_defer(func() -> bool:
		_add_figures(ch, people, z0, z1)
		return true)
	ch._run_or_defer(func() -> bool:
		var act := BeachActivity.new()
		act.name = "BeachActivity"
		act.setup(ch, z0, z1, activity, stretch.court, tower, dens, hour)
		ch.add_child(act)
		return true)


## The batches of props: towels, umbrellas, chairs, coolers, bags, boards.
static func _add_props(ch: CityChunk, props: Array) -> void:
	for p: Dictionary in props:
		var at: Vector2 = p.at
		var y := sand_y(ch, at.x, at.y)
		var kind := String(p.kind)
		var basis := Basis(Vector3.UP, float(p.yaw))
		if p.has("tilt"):
			basis = basis * Basis(Vector3.RIGHT, float(p.tilt))
		var paint: Color = p.paint
		var custom := Color(paint.r, paint.g, paint.b, float(p.pal) / 8.0)
		ch._batch.add("beach_" + kind, prop_mesh(kind), Transform3D(basis, Vector3(at.x, y, at.y)), Color.WHITE, custom)
	for kind: String in ["towel", "umbrella", "chair", "cooler", "bag", "boogie", "surfboard"]:
		ch._batch.set_draw_distance("beach_" + kind, PROP_DRAW * (1.4 if kind == "umbrella" else 1.0))
		if kind in ["towel", "boogie", "surfboard", "bag"]:
			ch._batch.set_no_shadow("beach_" + kind)
		else:
			ch._batch.set_shadow_distance("beach_" + kind, 70.0)


## The figures: merged by material (CampFigureMesh), each with its BeachFigure body. A chunk's
## people use a few crowd rigs and each rig one suit, so the whole beach is a handful of draws.
static func _add_figures(ch: CityChunk, people: Array, z0: float, z1: float) -> void:
	if people.is_empty():
		return
	var plan := ch.plan
	var merged: BeachFigureMesh = null
	var ring := sand_ring(ch, z0, z1)
	for i in people.size():
		var p: Dictionary = people[i]
		var model: int = p.model
		var suit: int = p.get("suit", suit_of(plan, ch.ix, ch.iz, model))
		var seed_value := BeachGoer.seed_for(model, 0)
		var at: Vector2 = p.at
		var lift: float = p.get("lift", 0.025 if String(p.key).begins_with("lie") or int(p.pose) == RoughSleeper.Pose.SIT else 0.0)
		var fig := BeachFigure.new()
		fig.name = "BeachFigure_%d" % i
		fig.chunk = ch
		fig.pose = int(p.pose)
		fig.beach_pose = String(p.key)
		fig.suit = suit
		fig.seed_value = seed_value
		fig.home = at
		fig.yaw = float(p.yaw)
		fig.lift = lift
		fig.ring = ring
		fig.sidewalk = 4.0
		var xf := Transform3D(Basis(Vector3.UP, float(p.yaw)), Vector3(at.x, sand_y(ch, at.x, at.y) + lift, at.y))
		var mesh := BeachFigure.beach_mesh(seed_value, int(p.pose), String(p.key), suit, model)
		if mesh:
			if merged == null:
				merged = BeachFigureMesh.new()
				merged.name = "BeachFigureMesh"
				merged.draw_distance = FIGURE_DRAW
				merged.shadow_distance = FIGURE_SHADOW
			fig.figure_mesh = merged
			fig.figure_index = merged.add_figure(mesh, CampFigure.shadow_for(mesh), xf)
		fig.transform = xf
		ch.add_child(fig)
	if merged:
		ch.add_child(merged)


## The suit a crowd rig wears on chunk (ix, iz): one per rig per chunk (one material each).
static func suit_of(plan: CityPlan, ix: int, iz: int, model: int) -> int:
	return _hi([plan.seed, "beach_suit", ix, iz, model]) % BeachGoer.SUITS.size()


## The dry sand of a stretch, where its people walk and run (a pedestrian's `ring`).
static func sand_ring(ch: CityChunk, z0: float, z1: float) -> Rect2:
	var macro: MacroMap = ch.plan.macro
	var zc := (z0 + z1) * 0.5
	var cx := macro.coast_x(zc)
	var w := macro.beach_width_at(zc)
	return Rect2(cx + w * 0.2, z0 + 1.0, w * 0.62, maxf(z1 - z0 - 2.0, 1.0))


## A LOD chunk's beach from a distance: a dot of colour for every towel and umbrella (pure plan,
## the same towels the FULL chunk lays), drawn flat with no shadow.
static func build_lod(ch: CityChunk, z0: float, z1: float) -> void:
	if not enabled or ch.plan == null or ch.plan.macro == null:
		return
	var dens := density(hour_now(ch)) * weather_factor(ch)
	var stretch := plan_stretch(ch.plan, z0, z1, dens)
	for p: Dictionary in stretch.props:
		var kind := String(p.kind)
		if kind != "towel" and kind != "umbrella":
			continue
		var at: Vector2 = p.at
		var y := sand_y(ch, at.x, at.y)
		var paint: Color = p.paint
		var custom := Color(paint.r, paint.g, paint.b, float(p.pal) / 8.0)
		var xf := Transform3D(Basis(Vector3.UP, float(p.yaw)), Vector3(at.x, y + (2.05 if kind == "umbrella" else 0.03), at.y))
		ch._batch.add("beach_dot_" + kind, dot_mesh(kind), xf, Color.WHITE, custom)
	for kind: String in ["towel", "umbrella"]:
		ch._batch.set_no_shadow("beach_dot_" + kind)
		ch._batch.set_draw_distance("beach_dot_" + kind, DOT_DRAW)
	if not kept_off(ch.plan, (z0 + z1) * 0.5):
		_build_path(ch, z0, z1)
	if not stretch.court.is_empty():
		_build_court(ch, stretch.court, true)


# --- The bike path ------------------------------------------------------------------------------

## The path along the back of the beach over z0..z1: a concrete strip on the sand (one mesh, the
## centre line and the joints in the shader), with a low sand-swept edge either side.
static func _build_path(ch: CityChunk, z0: float, z1: float) -> void:
	var macro: MacroMap = ch.plan.macro
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var steps := maxi(2, ceili((z1 - z0) / PATH_STEP))
	var prev: Array = []
	var half := PATH_WIDTH * 0.5
	var col := Color(0.78, 0.76, 0.72, A_PATH)
	for i in steps + 1:
		var z := lerpf(z0, z1, float(i) / steps)
		var x := path_x(ch.plan, z)
		var slope := (path_x(ch.plan, z + 1.0) - path_x(ch.plan, z - 1.0)) * 0.5
		var right := Vector2(1.0, -slope).normalized()
		var row: Array = []
		# Edge down into the sand, the slab's top across, the other edge.
		for k in 4:
			var off: float = [-half - 0.12, -half, half, half + 0.12][k]
			var p := Vector2(x, z) + right * off
			var y := sand_y(ch, p.x, p.y)
			var top := y + (PATH_LIFT if k == 1 or k == 2 else -0.04)
			row.append([Vector3(p.x, top, p.y), off])
		if i > 0:
			for k in 3:
				var a: Array = prev[k]
				var b: Array = prev[k + 1]
				var c: Array = row[k + 1]
				var d: Array = row[k]
				var tri := [[a, i - 1], [b, i - 1], [c, i], [a, i - 1], [c, i], [d, i]]
				var n := (((c[0] as Vector3) - (a[0] as Vector3)).cross((b[0] as Vector3) - (a[0] as Vector3))).normalized()
				if n.y < 0.0:
					tri = [[a, i - 1], [c, i], [b, i - 1], [a, i - 1], [d, i], [c, i]]
					n = -n
				for v: Array in tri:
					var vert: Array = v[0]
					var along := lerpf(z0, z1, float(v[1]) / steps)
					st.set_color(col)
					st.set_normal(n)
					st.set_uv(Vector2(along, float(vert[1])))
					st.set_uv2(Vector2(0.85, 0.0))
					st.add_vertex(vert[0])
		prev = row
	var mesh := st.commit()
	if mesh.get_surface_count() == 0:
		return
	var mi := MeshInstance3D.new()
	mi.name = "BikePath"
	mi.mesh = mesh
	mi.material_override = material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ch.add_child(mi)


# --- The court ----------------------------------------------------------------------------------

## Posts, net and boundary tapes of a court (one batch instance each), at FULL; the tapes alone at
## LOD (`flat`).
static func _build_court(ch: CityChunk, court: Dictionary, flat: bool = false) -> void:
	if court.is_empty():
		return
	var c: Vector2 = court.centre
	var y := sand_y(ch, c.x, c.y)
	var xf := Transform3D(Basis(Vector3.UP, float(court.yaw)), Vector3(c.x, y, c.y))
	ch._batch.add("beach_court_lines", prop_mesh("court_lines"), xf)
	ch._batch.set_no_shadow("beach_court_lines")
	if flat:
		return
	ch._batch.add("beach_net", prop_mesh("net"), xf)
	ch._batch.set_shadow_distance("beach_net", 60.0)


# --- Meshes -------------------------------------------------------------------------------------

static func material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = load("res://shaders/beach_props.gdshader")
	return _material


static func prop_mesh(kind: String) -> Mesh:
	if _meshes.has(kind):
		return _meshes[kind]
	var st := StreetClutter._begin()
	match kind:
		"towel":
			_towel(st)
		"umbrella":
			_umbrella(st)
		"chair":
			_chair(st)
		"cooler":
			_cooler(st)
		"bag":
			_bag(st)
		"boogie":
			_board(st, 1.05, 0.52, 0.055, A_BOARD, false)
		"surfboard":
			_board(st, 2.4, 0.56, 0.07, A_BOARD, true)
		"net":
			_net(st)
		"court_lines":
			_court_lines(st)
		"tower":
			_tower(st)
		"ball":
			StreetVendors._sphere(st, Vector3.ZERO, 0.105, Color(0.96, 0.95, 0.9, A_BALL), Vector2(0.55, 0.0), 12)
	return _finish(st, kind)


static func _finish(st: SurfaceTool, key: String) -> Mesh:
	st.generate_tangents()
	var mesh := st.commit()
	mesh.surface_set_material(0, material())
	_meshes[key] = mesh
	return mesh


## A dot of colour for the LOD chunks: a towel's flat rectangle, an umbrella's disc.
static func dot_mesh(kind: String) -> Mesh:
	var key := "dot_" + kind
	if _meshes.has(key):
		return _meshes[key]
	var st := StreetClutter._begin()
	var col := Color(1.0, 1.0, 1.0, A_PAINT)
	var rm := Vector2(0.9, 0.0)
	if kind == "umbrella":
		var r := 1.05
		for i in 8:
			var a0 := TAU * float(i) / 8.0
			var a1 := TAU * float(i + 1) / 8.0
			StreetClutter._tri(st, Vector3(0.0, 0.35, 0.0), Vector3(cos(a0) * r, 0.0, sin(a0) * r), Vector3(cos(a1) * r, 0.0, sin(a1) * r), Vector3.UP, Color(1.0, 1.0, 1.0, A_CANVAS), rm)
	else:
		StreetClutter._quad(st, Vector3(-0.9, 0.0, -0.45), Vector3(0.9, 0.0, -0.45), Vector3(0.9, 0.0, 0.45), Vector3(-0.9, 0.0, 0.45), Vector3.UP, col, rm)
	return _finish(st, key)


## A beach towel lying on the sand: 1.8 x 0.9 m, its long side along local x (the instance is
## turned so x runs up the beach), a little rumpled, the ends' fringe.
static func _towel(st: SurfaceTool) -> void:
	var col := Color(1.0, 1.0, 1.0, A_TOWEL)
	var rm := Vector2(0.95, 0.0)
	var nx := 8
	var nz := 4
	var grid: Array = []
	for i in nx + 1:
		var row: Array = []
		for j in nz + 1:
			var x := lerpf(-0.9, 0.9, float(i) / nx)
			var z := lerpf(-0.45, 0.45, float(j) / nz)
			# Rumples: a few centimetres, and the corners lifting where a foot kicked them.
			var y := 0.012 + 0.012 * sin(x * 7.1 + z * 3.3) * cos(z * 5.7 - x * 2.1)
			if (i == 0 or i == nx) and (j == 0 or j == nz):
				y += 0.015
			row.append(Vector3(x, y, z))
		grid.append(row)
	for i in nx:
		for j in nz:
			StreetClutter._quad(st, grid[i][j], grid[i + 1][j], grid[i + 1][j + 1], grid[i][j + 1], Vector3.UP, col, rm)
	# The edge, so it is not paper-thin from the side.
	for i in nx:
		for j: int in [0, nz]:
			var a: Vector3 = grid[i][j]
			var b: Vector3 = grid[i + 1][j]
			var out := Vector3(0.0, 0.0, -1.0 if j == 0 else 1.0)
			StreetClutter._quad(st, a, b, b - Vector3(0.0, 0.014, 0.0), a - Vector3(0.0, 0.014, 0.0), out, col, rm)


## A beach umbrella: a pole driven into the sand at a lean, eight canvas panels sagging between
## their ribs, a flap at the top. The instance's tilt leans the whole thing.
static func _umbrella(st: SurfaceTool) -> void:
	var canvas := Color(1.0, 1.0, 1.0, A_CANVAS)
	var rm := Vector2(0.85, 0.0)
	var pole := Color(0.86, 0.86, 0.84, A_PLAIN)
	StreetClutter._tube(st, [Vector3(0.0, -0.35, 0.0), Vector3(0.0, 2.25, 0.0)], 0.018, 8, pole, Vector2(0.35, 0.8))
	var apex := Vector3(0.0, 2.32, 0.0)
	var radius := 1.05
	var rim_y := 1.98
	var panels := 8
	var segs := 4
	for p in panels:
		var a0 := TAU * float(p) / panels
		var a1 := TAU * float(p + 1) / panels
		var am := (a0 + a1) * 0.5
		var rows: Array = []
		for s in segs + 1:
			var f := float(s) / segs
			var y := lerpf(apex.y, rim_y, f) - sin(f * PI) * 0.035
			var r := radius * f
			rows.append([Vector3(cos(a0) * r, y, sin(a0) * r), Vector3(cos(am) * r * 0.97, y - 0.045 * f, sin(am) * r * 0.97), Vector3(cos(a1) * r, y, sin(a1) * r)])
		for s in segs:
			var r0: Array = rows[s]
			var r1: Array = rows[s + 1]
			for k in 2:
				var up := Vector3(cos(am), 2.0, sin(am))
				StreetClutter._quad(st, r0[k], r0[k + 1], r1[k + 1], r1[k], up, canvas, rm)
				StreetClutter._quad(st, r0[k], r0[k + 1], r1[k + 1], r1[k], -up, canvas, rm)
		var tip := Vector3(cos(a0) * radius, rim_y - 0.01, sin(a0) * radius)
		StreetClutter._tube(st, [apex + Vector3(0.0, -0.02, 0.0), tip], 0.006, 4, pole, Vector2(0.35, 0.8))
		StreetClutter._tube(st, [Vector3(0.0, 1.8, 0.0), apex.lerp(tip, 0.5) + Vector3(0.0, -0.02, 0.0)], 0.004, 4, pole, Vector2(0.35, 0.8))
	# The vent flap over the apex.
	for p in panels:
		var a0 := TAU * float(p) / panels
		var a1 := TAU * float(p + 1) / panels
		StreetClutter._tri(st, apex + Vector3(0.0, 0.1, 0.0), Vector3(cos(a0) * 0.2, apex.y + 0.04, sin(a0) * 0.2), Vector3(cos(a1) * 0.2, apex.y + 0.04, sin(a1) * 0.2), Vector3.UP, canvas, rm)


## A low beach chair: an aluminium frame, a seat 0.28 m up, a striped sling seat and back leaning
## back; faces -z (the instance's yaw is the sitter's).
static func _chair(st: SurfaceTool) -> void:
	var metal := Color(0.82, 0.83, 0.85, A_PLAIN)
	var mrm := Vector2(0.3, 0.9)
	var cloth := Color(1.0, 1.0, 1.0, A_TOWEL)
	var crm := Vector2(0.9, 0.0)
	var w := 0.29
	for sx: float in [-w, w]:
		# Front legs to the seat's front, the seat rail, the back post leaning back, the arm.
		StreetClutter._tube(st, [Vector3(sx, 0.0, -0.32), Vector3(sx, 0.24, -0.3), Vector3(sx, 0.2, 0.12), Vector3(sx, 0.86, 0.42)], 0.012, 6, metal, mrm)
		StreetClutter._tube(st, [Vector3(sx, 0.0, 0.2), Vector3(sx, 0.2, 0.12)], 0.012, 6, metal, mrm)
		StreetClutter._tube(st, [Vector3(sx, 0.2, -0.28), Vector3(sx, 0.44, -0.22), Vector3(sx, 0.47, 0.12), Vector3(sx, 0.52, 0.22)], 0.01, 6, metal, mrm)
	StreetClutter._tube(st, [Vector3(-w, 0.86, 0.42), Vector3(w, 0.86, 0.42)], 0.01, 6, metal, mrm)
	StreetClutter._tube(st, [Vector3(-w, 0.24, -0.3), Vector3(w, 0.24, -0.3)], 0.01, 6, metal, mrm)
	# The sling: the seat sagging between the rails, then the back.
	var seat := [Vector3(-w, 0.235, -0.3), Vector3(w, 0.235, -0.3), Vector3(w, 0.15, -0.08), Vector3(-w, 0.15, -0.08)]
	StreetClutter._quad(st, seat[0], seat[1], seat[2], seat[3], Vector3.UP, cloth, crm)
	StreetClutter._quad(st, seat[0], seat[1], seat[2], seat[3], Vector3.DOWN, cloth, crm)
	var seat2 := [Vector3(-w, 0.15, -0.08), Vector3(w, 0.15, -0.08), Vector3(w, 0.2, 0.12), Vector3(-w, 0.2, 0.12)]
	StreetClutter._quad(st, seat2[0], seat2[1], seat2[2], seat2[3], Vector3.UP, cloth, crm)
	StreetClutter._quad(st, seat2[0], seat2[1], seat2[2], seat2[3], Vector3.DOWN, cloth, crm)
	var back := [Vector3(-w, 0.22, 0.13), Vector3(w, 0.22, 0.13), Vector3(w, 0.84, 0.39), Vector3(-w, 0.84, 0.39)]
	StreetClutter._quad(st, back[0], back[1], back[2], back[3], Vector3(0.0, 0.4, -1.0), cloth, crm)
	StreetClutter._quad(st, back[0], back[1], back[2], back[3], Vector3(0.0, -0.4, 1.0), cloth, crm)


## A hard cooler: the body in the instance's colour, a white lid, a handle either end.
static func _cooler(st: SurfaceTool) -> void:
	var body := Color(1.0, 1.0, 1.0, A_PAINT)
	var lid := Color(0.95, 0.95, 0.93, A_PLAIN)
	var rm := Vector2(0.45, 0.0)
	StreetClutter._bbox(st, Transform3D(Basis(), Vector3(0.0, 0.17, 0.0)), Vector3(0.62, 0.32, 0.38), 0.03, body, rm)
	StreetClutter._bbox(st, Transform3D(Basis(), Vector3(0.0, 0.355, 0.0)), Vector3(0.64, 0.06, 0.4), 0.02, lid, rm)
	for sx: float in [-0.33, 0.33]:
		StreetClutter._bbox(st, Transform3D(Basis(), Vector3(sx, 0.27, 0.0)), Vector3(0.04, 0.03, 0.18), 0.008, Color(0.2, 0.2, 0.22, A_PLAIN), rm)


## A beach tote slumped on the sand, a rolled towel sticking out of it.
static func _bag(st: SurfaceTool) -> void:
	var cloth := Color(1.0, 1.0, 1.0, A_PAINT)
	StreetVendors._ellipsoid(st, Vector3(0.0, 0.13, 0.0), Vector3(0.24, 0.15, 0.12), Basis(Vector3.FORWARD, 0.15), cloth, Vector2(0.9, 0.0), 8, 4)
	StreetClutter._tube(st, [Vector3(-0.12, 0.22, 0.0), Vector3(-0.05, 0.36, 0.0), Vector3(0.05, 0.36, 0.0), Vector3(0.12, 0.22, 0.0)], 0.012, 4, Color(0.3, 0.22, 0.15, A_PLAIN), Vector2(0.8, 0.0))
	StreetVendors._ellipsoid(st, Vector3(0.05, 0.27, 0.02), Vector3(0.06, 0.1, 0.06), Basis(Vector3.FORWARD, -0.4), Color(0.95, 0.94, 0.9, A_PLAIN), Vector2(0.95, 0.0), 6, 3)


## A board lying on its deck's outline: `length` along x, rounded nose, a pulled-in tail, a
## domed deck; `fins` on a surfboard (it lies deck up, so they show only from low).
static func _board(st: SurfaceTool, length: float, width: float, thick: float, code: float, fins: bool) -> void:
	var col := Color(1.0, 1.0, 1.0, code)
	var rm := Vector2(0.35, 0.0)
	var n := 10
	var outline: Array = []
	for i in n + 1:
		var t := float(i) / n
		var x := lerpf(-length * 0.5, length * 0.5, t)
		var hw := width * 0.5 * (sin(PI * pow(t, 0.8)) * 0.88 + 0.12) if fins else width * 0.5 * (0.84 + 0.16 * sin(PI * t))
		outline.append([x, maxf(hw, 0.02)])
	for i in n:
		var a: Array = outline[i]
		var b: Array = outline[i + 1]
		var top_a := Vector3(float(a[0]), thick, 0.0)
		var top_b := Vector3(float(b[0]), thick, 0.0)
		for s: float in [-1.0, 1.0]:
			var ea := Vector3(float(a[0]), thick * 0.45, float(a[1]) * s)
			var eb := Vector3(float(b[0]), thick * 0.45, float(b[1]) * s)
			var ba := Vector3(float(a[0]), 0.004, float(a[1]) * s * 0.85)
			var bb := Vector3(float(b[0]), 0.004, float(b[1]) * s * 0.85)
			StreetClutter._quad(st, top_a, top_b, eb, ea, Vector3(0.0, 1.0, s * 0.3), col, rm)
			StreetClutter._quad(st, ea, eb, bb, ba, Vector3(0.0, -0.2, s), col, rm)
			StreetClutter._quad(st, ba, bb, Vector3(float(b[0]), 0.004, 0.0), Vector3(float(a[0]), 0.004, 0.0), Vector3.DOWN, col, rm)
	if fins:
		var fx := -length * 0.5 + 0.18
		StreetClutter._tri(st, Vector3(fx, 0.004, 0.0), Vector3(fx + 0.11, 0.004, 0.0), Vector3(fx + 0.02, -0.11, 0.0), Vector3.FORWARD, Color(0.15, 0.15, 0.17, A_PLAIN), rm)
		StreetClutter._tri(st, Vector3(fx, 0.004, 0.0), Vector3(fx + 0.11, 0.004, 0.0), Vector3(fx + 0.02, -0.11, 0.0), Vector3.BACK, Color(0.15, 0.15, 0.17, A_PLAIN), rm)


## A beach volleyball net between two posts: the court's long side runs along local z, the net
## across it at z 0 (local x), 2.43 m to its top band, the posts 1 m outside the court; the cables
## down to stakes in the sand.
static func _net(st: SurfaceTool) -> void:
	var post := Color(0.9, 0.9, 0.88, A_PLAIN)
	var prm := Vector2(0.4, 0.6)
	var half := COURT_SIZE.x * 0.5 + 0.9
	var top := 2.43
	for sx: float in [-half, half]:
		StreetClutter._cyl(st, Transform3D(Basis(), Vector3(sx, -0.6, 0.0)), 0.05, 0.05, top + 0.85, post, prm, 10)
		# Guy line to a stake.
		StreetClutter._tube(st, [Vector3(sx, top + 0.15, 0.0), Vector3(sx + signf(sx) * 1.6, 0.02, 0.0)], 0.006, 3, Color(0.85, 0.85, 0.8, A_PLAIN), Vector2(0.7, 0.0))
		# A padded sleeve on the post.
		StreetClutter._cyl(st, Transform3D(Basis(), Vector3(sx, 0.2, 0.0)), 0.075, 0.075, 1.4, Color(0.15, 0.3, 0.65, A_PLAIN), Vector2(0.75, 0.0), 10)
	# The mesh: one double-sided quad (cut out in the shader), the top and bottom bands.
	var net := Color(0.08, 0.08, 0.09, A_NET)
	var a := Vector3(-half + 0.05, top - 1.0, 0.0)
	var b := Vector3(half - 0.05, top - 1.0, 0.0)
	var c := Vector3(half - 0.05, top - 0.07, 0.0)
	var d := Vector3(-half + 0.05, top - 0.07, 0.0)
	for want: Vector3 in [Vector3.BACK, Vector3.FORWARD]:
		for tri: Array in [[a, b, c], [a, c, d]]:
			var cr := ((tri[2] as Vector3) - (tri[0] as Vector3)).cross((tri[1] as Vector3) - (tri[0] as Vector3))
			var order: Array = tri if cr.dot(want) >= 0.0 else [tri[0], tri[2], tri[1]]
			for p: Vector3 in order:
				StreetClutter._vtx(st, p, want, Vector2(p.x + half, top - p.y), net, Vector2(0.9, 0.0))
	var band := Color(0.92, 0.92, 0.9, A_PLAIN)
	StreetClutter._bbox(st, Transform3D(Basis(), Vector3(0.0, top - 0.035, 0.0)), Vector3(half * 2.0 - 0.1, 0.07, 0.012), 0.004, band, Vector2(0.7, 0.0))
	StreetClutter._bbox(st, Transform3D(Basis(), Vector3(0.0, top - 1.0, 0.0)), Vector3(half * 2.0 - 0.1, 0.04, 0.01), 0.004, band, Vector2(0.7, 0.0))
	# The antennas, red and white.
	for sx: float in [-COURT_SIZE.x * 0.5, COURT_SIZE.x * 0.5]:
		StreetClutter._cyl(st, Transform3D(Basis(), Vector3(sx, top - 1.0, 0.0)), 0.006, 0.006, 1.8, Color(0.92, 0.2, 0.2, A_PLAIN), Vector2(0.4, 0.0), 4)


## The court's boundary: blue tape pinned flat on the sand, 5 cm wide.
static func _court_lines(st: SurfaceTool) -> void:
	var tape := Color(0.12, 0.3, 0.72, A_TAPE)
	var hx := COURT_SIZE.x * 0.5
	var hz := COURT_SIZE.y * 0.5
	var w := 0.05
	var y := 0.025
	for s: float in [-1.0, 1.0]:
		StreetClutter._quad(st, Vector3(-hx - w, y, s * hz - w), Vector3(hx + w, y, s * hz - w), Vector3(hx + w, y, s * hz + w), Vector3(-hx - w, y, s * hz + w), Vector3.UP, tape, Vector2(0.8, 0.0))
		StreetClutter._quad(st, Vector3(s * hx - w, y, -hz), Vector3(s * hx + w, y, -hz), Vector3(s * hx + w, y, hz), Vector3(s * hx - w, y, hz), Vector3.UP, tape, Vector2(0.8, 0.0))


## The lifeguard tower the way Los Angeles County builds them: a cabin raised on four posts, the
## blue walls with a white band, windows all round, a deck in front with a rail, a sloping roof,
## and a ramp down the back. Faces -z (the sea, once turned); the deck floor is DECK_Y up.
const TOWER_DECK_Y := 2.35
static func _tower(st: SurfaceTool) -> void:
	var blue := Color(TOWER_BLUE.r, TOWER_BLUE.g, TOWER_BLUE.b, A_PLAIN)
	var trim := Color(TOWER_TRIM.r, TOWER_TRIM.g, TOWER_TRIM.b, A_PLAIN)
	var wood := Color(0.62, 0.6, 0.56, A_PLAIN)
	var glass := Color(0.25, 0.32, 0.36, A_GLASS)
	var rm := Vector2(0.6, 0.0)
	var dy := TOWER_DECK_Y
	# Posts and braces.
	for px: float in [-1.35, 1.35]:
		for pz: float in [-1.1, 1.9]:
			StreetClutter._bbox(st, Transform3D(Basis(), Vector3(px, dy * 0.5 - 0.3, pz)), Vector3(0.2, dy + 0.6, 0.2), 0.02, wood, rm)
		StreetClutter._tube(st, [Vector3(px, 0.3, -1.1), Vector3(px, dy - 0.2, 1.9)], 0.05, 4, wood, rm)
	for pz: float in [-1.1, 1.9]:
		StreetClutter._tube(st, [Vector3(-1.35, 0.3, pz), Vector3(1.35, dy - 0.2, pz)], 0.05, 4, wood, rm)
	# The deck (in front and under the cabin).
	StreetClutter._bbox(st, Transform3D(Basis(), Vector3(0.0, dy - 0.06, 0.2)), Vector3(3.1, 0.12, 3.4), 0.02, trim, rm)
	# The cabin: walls round a window band.
	var cz := 0.85
	var cd := 2.0
	var cw := 2.7
	var sill := dy + 0.95
	var head := dy + 1.85
	StreetClutter._bbox(st, Transform3D(Basis(), Vector3(0.0, dy + 0.475, cz)), Vector3(cw, 0.95, cd), 0.02, blue, rm)
	StreetClutter._bbox(st, Transform3D(Basis(), Vector3(0.0, (sill + head) * 0.5, cz)), Vector3(cw - 0.08, head - sill, cd - 0.08), 0.0, glass, Vector2(0.06, 0.0))
	for px: float in [-cw * 0.5 + 0.06, cw * 0.5 - 0.06]:
		for pz: float in [cz - cd * 0.5 + 0.06, cz + cd * 0.5 - 0.06]:
			StreetClutter._bbox(st, Transform3D(Basis(), Vector3(px, (sill + head) * 0.5, pz)), Vector3(0.12, head - sill, 0.12), 0.01, trim, rm)
	StreetClutter._bbox(st, Transform3D(Basis(), Vector3(0.0, head + 0.12, cz)), Vector3(cw, 0.24, cd), 0.02, trim, rm)
	StreetClutter._bbox(st, Transform3D(Basis(), Vector3(0.0, dy + 0.98, cz)), Vector3(cw + 0.02, 0.08, cd + 0.02), 0.01, trim, rm)
	# The roof: a low hip over the cabin and the front of the deck.
	var r0 := head + 0.24
	var corners := [Vector3(-1.65, r0, -0.55), Vector3(1.65, r0, -0.55), Vector3(1.65, r0, 2.15), Vector3(-1.65, r0, 2.15)]
	var ridge_a := Vector3(-0.6, r0 + 0.45, cz)
	var ridge_b := Vector3(0.6, r0 + 0.45, cz)
	StreetClutter._quad(st, corners[0], corners[1], ridge_b, ridge_a, Vector3(0.0, 1.0, -0.5), blue, rm)
	StreetClutter._quad(st, corners[2], corners[3], ridge_a, ridge_b, Vector3(0.0, 1.0, 0.5), blue, rm)
	StreetClutter._tri(st, corners[0], corners[3], ridge_a, Vector3(-0.5, 1.0, 0.0), blue, rm)
	StreetClutter._tri(st, corners[1], corners[2], ridge_b, Vector3(0.5, 1.0, 0.0), blue, rm)
	for k in 4:
		StreetClutter._quad(st, corners[k], corners[(k + 1) % 4], (corners[(k + 1) % 4] as Vector3) - Vector3(0.0, 0.08, 0.0), (corners[k] as Vector3) - Vector3(0.0, 0.08, 0.0), ((corners[k] as Vector3) + (corners[(k + 1) % 4] as Vector3)) * Vector3(1.0, 0.0, 1.0) - Vector3(0.0, 0.0, cz * 2.0), trim, rm)
	StreetClutter._quad(st, corners[0], corners[1], corners[2], corners[3], Vector3.DOWN, trim, rm)
	# The rail round the front of the deck.
	var ry := dy + 0.95
	var rail := [Vector3(-1.5, ry, -1.4), Vector3(1.5, ry, -1.4)]
	StreetClutter._tube(st, [Vector3(-1.5, ry, -0.1), rail[0], rail[1], Vector3(1.5, ry, -0.1)], 0.03, 6, trim, rm)
	for k in 7:
		var x := lerpf(-1.5, 1.5, float(k) / 6.0)
		StreetClutter._tube(st, [Vector3(x, dy, -1.4), Vector3(x, ry, -1.4)], 0.02, 4, trim, rm)
	for sx: float in [-1.5, 1.5]:
		StreetClutter._tube(st, [Vector3(sx, dy, -0.75), Vector3(sx, ry, -0.75)], 0.02, 4, trim, rm)
	# The ramp down the back and its rails.
	var top_z := 1.9
	var foot_z := 5.6
	StreetClutter._quad(st, Vector3(-0.55, dy - 0.02, top_z), Vector3(0.55, dy - 0.02, top_z), Vector3(0.55, 0.05, foot_z), Vector3(-0.55, 0.05, foot_z), Vector3(0.0, 1.0, 0.6), trim, rm)
	StreetClutter._quad(st, Vector3(-0.55, dy - 0.12, top_z), Vector3(0.55, dy - 0.12, top_z), Vector3(0.55, -0.05, foot_z), Vector3(-0.55, -0.05, foot_z), Vector3(0.0, -1.0, -0.6), wood, rm)
	for sx: float in [-0.6, 0.6]:
		StreetClutter._tube(st, [Vector3(sx, dy + 0.9, top_z), Vector3(sx, 0.95, foot_z)], 0.025, 5, trim, rm)
		StreetClutter._tube(st, [Vector3(sx, 0.0, foot_z), Vector3(sx, 0.95, foot_z)], 0.03, 5, trim, rm)
		StreetClutter._tube(st, [Vector3(sx, dy * 0.5, (top_z + foot_z) * 0.5), Vector3(sx, dy * 0.5 + 0.92, (top_z + foot_z) * 0.5)], 0.025, 5, trim, rm)
	# The tower's number board under the front window.
	StreetClutter._bbox(st, Transform3D(Basis(), Vector3(0.0, dy + 0.55, cz - cd * 0.5 - 0.02)), Vector3(0.8, 0.4, 0.03), 0.005, trim, rm)


static func tower_mesh() -> Mesh:
	return prop_mesh("tower")


## The bike a rider is baked on (BeachFigure.ride_meshes()): a beach cruiser built round `fit`
## (BeachGoer.ride_pose(): the saddle, bottom bracket, pedals and grips in the rider's space,
## metres, forward -z) in `paint` (BIKES). Vertex-coloured: it is drawn as part of a plain mesh.
static func bike_mesh(fit: Dictionary, paint: int) -> ArrayMesh:
	var st := StreetClutter._begin()
	var pc: Color = BIKES[posmod(paint, BIKES.size())]
	var frame := Color(pc.r, pc.g, pc.b, A_PLAIN)
	var frm := Vector2(0.32, 0.25)
	var chrome := Color(0.78, 0.79, 0.8, A_PLAIN)
	var crm := Vector2(0.18, 0.95)
	var black := Color(0.05, 0.05, 0.055, A_PLAIN)
	var rubber := Vector2(0.85, 0.0)
	var bb: Vector3 = fit.bb
	var saddle: Vector3 = fit.saddle
	var gl: Vector3 = fit.grip_l
	var gr: Vector3 = fit.grip_r
	var wheel_r := 0.33
	var rear := Vector3(bb.x, wheel_r, bb.z + 0.47)
	var front := Vector3(bb.x, wheel_r, bb.z - 0.68)
	# Wheels: tyre, rim, hub, spokes.
	for axle: Vector3 in [rear, front]:
		_wheel(st, axle, wheel_r, black, chrome, rubber, crm)
		# Fenders over the top of each wheel, in the frame colour.
		var pts: Array = []
		for k in 9:
			var a := lerpf(-0.15, PI + 0.15, float(k) / 8.0) + (0.4 if axle == rear else -0.3)
			pts.append(axle + Vector3(0.0, sin(a), cos(a)) * (wheel_r + 0.04))
		for k in 8:
			var a: Vector3 = pts[k]
			var b: Vector3 = pts[k + 1]
			var out := ((a + b) * 0.5 - axle).normalized()
			StreetClutter._quad(st, a + Vector3(-0.035, 0.0, 0.0), b + Vector3(-0.035, 0.0, 0.0), b + Vector3(0.035, 0.0, 0.0), a + Vector3(0.035, 0.0, 0.0), out, frame, frm)
			StreetClutter._quad(st, a + Vector3(-0.035, 0.0, 0.0), b + Vector3(-0.035, 0.0, 0.0), b + Vector3(0.035, 0.0, 0.0), a + Vector3(0.035, 0.0, 0.0), -out, frame, frm)
	# The frame: a cruiser's curved top tubes, the seat tube, chain- and seat-stays, the fork.
	var seat_top := saddle + Vector3(0.0, -0.07, 0.04)
	var head_bot := front + Vector3(0.0, 0.38, 0.13)
	var head_top := head_bot + Vector3(0.0, 0.2, 0.07)
	StreetClutter._tube(st, [bb, seat_top], 0.019, 8, frame, frm)
	StreetClutter._tube(st, [bb, bb.lerp(head_bot, 0.5) + Vector3(0.0, -0.04, 0.0), head_bot], 0.022, 8, frame, frm)
	var tt0 := bb.lerp(seat_top, 0.72)
	StreetClutter._tube(st, [tt0, tt0.lerp(head_top, 0.45) + Vector3(0.0, -0.09, 0.0), head_top], 0.017, 8, frame, frm)
	StreetClutter._tube(st, [head_bot, head_top], 0.025, 8, frame, frm)
	for sx: float in [-0.055, 0.055]:
		StreetClutter._tube(st, [bb + Vector3(sx * 0.6, 0.0, 0.0), rear + Vector3(sx, 0.0, 0.0)], 0.011, 6, frame, frm)
		StreetClutter._tube(st, [seat_top + Vector3(sx * 0.4, -0.04, 0.0), rear + Vector3(sx, 0.0, 0.0)], 0.01, 6, frame, frm)
		StreetClutter._tube(st, [head_bot + Vector3(sx * 0.6, 0.0, 0.0), front + Vector3(sx, 0.0, -0.03)], 0.012, 6, frame, frm)
	# Seat post, saddle (a wide sprung cruiser saddle), springs.
	StreetClutter._tube(st, [seat_top, saddle + Vector3(0.0, -0.035, 0.0)], 0.013, 6, chrome, crm)
	StreetVendors._ellipsoid(st, saddle + Vector3(0.0, -0.005, 0.03), Vector3(0.12, 0.035, 0.15), Basis(), Color(0.32, 0.2, 0.12, A_PLAIN), Vector2(0.55, 0.0), 8, 4)
	# Stem and the swept-back bars to the grips.
	var bar_c := (gl + gr) * 0.5 + Vector3(0.0, -0.03, -0.17)
	StreetClutter._tube(st, [head_top, head_top + Vector3(0.0, 0.07, 0.0), bar_c], 0.013, 6, chrome, crm)
	StreetClutter._tube(st, [gl, gl + Vector3(-0.03, -0.02, -0.12), bar_c, gr + Vector3(0.03, -0.02, -0.12), gr], 0.011, 6, chrome, crm)
	for g: Vector3 in [gl, gr]:
		var side := signf(g.x - bar_c.x)
		StreetClutter._tube(st, [g + Vector3(-side * 0.02, 0.0, 0.0), g + Vector3(side * 0.08, 0.0, 0.02)], 0.017, 6, black, rubber)
	# Cranks, chainring and pedals at this frame's angle.
	var pl: Vector3 = fit.pedal_l
	var pr: Vector3 = fit.pedal_r
	StreetClutter._tube(st, [bb + Vector3(pl.x - bb.x, 0.0, 0.0) * 0.6, Vector3(bb.x + (pl.x - bb.x) * 0.6, pl.y, pl.z)], 0.012, 5, chrome, crm)
	StreetClutter._tube(st, [bb + Vector3(pr.x - bb.x, 0.0, 0.0) * 0.6, Vector3(bb.x + (pr.x - bb.x) * 0.6, pr.y, pr.z)], 0.012, 5, chrome, crm)
	var ring_x := bb.x + (pr.x - bb.x) * 0.45
	StreetVendors._cylx(st, Vector3(ring_x, bb.y, bb.z), 1.0, 0.095, 0.006, chrome, crm, 14)
	for p: Vector3 in [pl, pr]:
		StreetClutter._bbox(st, Transform3D(Basis(), p), Vector3(0.1, 0.022, 0.07), 0.005, black, rubber)
	# The chain, top and bottom runs to the rear cog.
	var cx := ring_x
	StreetClutter._tube(st, [Vector3(cx, bb.y + 0.095, bb.z), Vector3(cx, rear.y + 0.04, rear.z)], 0.004, 3, black, Vector2(0.6, 0.6))
	StreetClutter._tube(st, [Vector3(cx, bb.y - 0.095, bb.z), Vector3(cx, rear.y - 0.04, rear.z)], 0.004, 3, black, Vector2(0.6, 0.6))
	st.generate_tangents()
	var mesh := st.commit()
	mesh.surface_set_material(0, material())
	return mesh


## A skateboard under a skater's feet (its deck's top at y 0, the wheels 0.1 m below; long side on
## x), vertex-coloured for a plain mesh.
static func skateboard_mesh() -> ArrayMesh:
	if _meshes.has("skateboard"):
		return _meshes["skateboard"]
	var st := StreetClutter._begin()
	var deck := Color(0.12, 0.12, 0.13, A_PLAIN)
	var wood := Color(0.55, 0.4, 0.26, A_PLAIN)
	var metal := Color(0.7, 0.71, 0.72, A_PLAIN)
	var wheel := Color(0.93, 0.88, 0.62, A_PLAIN)
	StreetClutter._bbox(st, Transform3D(Basis(), Vector3(0.0, -0.006, 0.0)), Vector3(0.8, 0.012, 0.21), 0.006, deck, Vector2(0.9, 0.0))
	StreetClutter._bbox(st, Transform3D(Basis(), Vector3(0.0, -0.016, 0.0)), Vector3(0.78, 0.008, 0.2), 0.003, wood, Vector2(0.7, 0.0))
	for tx: float in [-0.27, 0.27]:
		StreetClutter._bbox(st, Transform3D(Basis(), Vector3(tx, -0.04, 0.0)), Vector3(0.05, 0.04, 0.16), 0.006, metal, Vector2(0.3, 0.9))
		for tz: float in [-0.085, 0.085]:
			StreetVendors._cylx(st, Vector3(tx, -0.07, tz), signf(tz), 0.027, 0.032, wheel, Vector2(0.5, 0.0), 8)
	st.generate_tangents()
	var mesh := st.commit()
	mesh.surface_set_material(0, material())
	_meshes["skateboard"] = mesh
	return mesh


static func _wheel(st: SurfaceTool, axle: Vector3, r: float, tyre: Color, rim: Color, trm: Vector2, rrm: Vector2) -> void:
	var seg := 18
	for k in seg:
		var a0 := TAU * float(k) / seg
		var a1 := TAU * float(k + 1) / seg
		var d0 := Vector3(0.0, sin(a0), cos(a0))
		var d1 := Vector3(0.0, sin(a1), cos(a1))
		# Tyre: an outer band and two sidewalls.
		var w := 0.028
		StreetClutter._smooth_quad(st, axle + d0 * r + Vector3(-w, 0.0, 0.0), axle + d1 * r + Vector3(-w, 0.0, 0.0), axle + d1 * r + Vector3(w, 0.0, 0.0), axle + d0 * r + Vector3(w, 0.0, 0.0), d0, d1, d1, d0, tyre, trm)
		for sx: float in [-w, w]:
			var n := Vector3(signf(sx), 0.0, 0.0)
			StreetClutter._quad(st, axle + d0 * r + Vector3(sx, 0.0, 0.0), axle + d1 * r + Vector3(sx, 0.0, 0.0), axle + d1 * (r - 0.045) + Vector3(sx * 0.8, 0.0, 0.0), axle + d0 * (r - 0.045) + Vector3(sx * 0.8, 0.0, 0.0), n, tyre, trm)
			StreetClutter._quad(st, axle + d0 * (r - 0.045) + Vector3(sx * 0.8, 0.0, 0.0), axle + d1 * (r - 0.045) + Vector3(sx * 0.8, 0.0, 0.0), axle + d1 * (r - 0.06) + Vector3(sx * 0.6, 0.0, 0.0), axle + d0 * (r - 0.06) + Vector3(sx * 0.6, 0.0, 0.0), n, rim, rrm)
	# Spokes (in pairs that cross) and the hub.
	for k in 16:
		var a := TAU * float(k) / 16.0
		var side := -0.02 if k % 2 == 0 else 0.02
		var tip := axle + Vector3(0.0, sin(a), cos(a)) * (r - 0.055)
		var a2 := a + 0.35 * (1.0 if k % 2 == 0 else -1.0)
		StreetClutter._tube(st, [axle + Vector3(side, sin(a2) * 0.03, cos(a2) * 0.03), tip], 0.0018, 3, rim, rrm)
	StreetVendors._cylx(st, axle + Vector3(-0.04, 0.0, 0.0), 1.0, 0.025, 0.08, rim, rrm, 8)


## Builds the meshes once (the loading screen) and hands back the material to draw once through a
## MultiMesh.
static func warm() -> Array:
	if not enabled:
		return []
	for kind: String in ["towel", "umbrella", "chair", "cooler", "bag", "boogie", "surfboard", "net", "court_lines", "tower", "ball"]:
		prop_mesh(kind)
	dot_mesh("towel")
	dot_mesh("umbrella")
	return [material()]
