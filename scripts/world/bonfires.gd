class_name Bonfires
extends RefCounted
## Beach bonfire rings (2026-10-30, "beach bonfire rings at night"): the form of the concrete fire
## rings Los Angeles' southern beaches set in a row along the sand - a squat open cylinder of
## precast concrete, a little over a metre across and knee high, sooted black inside and over the
## rim, ash and charred stubs in the bottom - spaced along the beach above the tide line, between
## the berm and the bike path.
##
## * **By day** they stand empty: the ring, the ash, the burnt stubs of last night's logs.
## * **After dusk** some are lit (lit_window(): each ring's night has its own start and end, a
##   hash of the seed, the ring and the night): a stack of fresh logs burning in the ring
##   (BonfireFire: CarDamage's flame material and ramps at a camp-fire's size, embers riding up,
##   pale wood smoke, the coals glowing under the logs, a flickering warm OmniLight on the sand and
##   the people - desktop only - and an additive pool of firelight on the sand on every renderer,
##   the crackle), and a small group sits round each one (BonfireFigure: the beach's baked
##   figures, but in street clothes - sitting on a blanket, leaning back on their hands, in a low
##   beach chair, a couple standing - all turned to the fire), with a cooler and a bundle of
##   firewood beside the ring. No fires in rain, a storm or a Santa Ana (a red-flag night).
## * **From the air** a LOD chunk lays the pool of each lit fire, so a night flight along the
##   coast shows the row of orange points down the beach.
##
## Everything is a hash of the seed and a WORLD cell of shore (RING_CELL metres; the night from
## DayNight.day_count) - never the block's rng - so a ring is the same ring from any chunk, and
## the block's own rolls (palms, the tower) and BeachLife's people do not move (BeachLife's
## sunbathers only keep clear of a ring, as of a palm). rings_in() and group() are pure.
##
## `BONFIRES=0` in the environment turns all of it off (the A/B); force_hour / force_lit pin it
## for tests and stills.

static var enabled: bool = OS.get_environment("BONFIRES") != "0"
## The hour to plan for (< 0 reads DayNight, like BeachLife.hour_now()).
static var force_hour: float = -1.0
## 1 lights every ring, 0 none, -1 the hashes decide (tests and stills: BONFIRE_LIT=1).
static var force_lit: int = int(OS.get_environment("BONFIRE_LIT")) if OS.get_environment("BONFIRE_LIT") != "" else -1

## Metres of shore per ring slot, the odds a slot has a ring, and where across the beach (fraction
## of its width from the waterline: above the tide line and the swash, clear of the bike path at
## BeachLife.PATH_AT).
const RING_CELL := 24.0
const RING_ODDS := 0.78
const RING_AT := Vector2(0.58, 0.7)
## A beach narrower than this (m) has no rings (the replica's coast under the bluff, the coves).
const MIN_WIDTH := 46.0
## The ring: outer radius, wall thickness, height over the sand, how deep it is set in, and the
## ash bed's height inside (m). Precast rings run about 1.2 m across and 0.6 m tall.
const RING_R := 0.61
const RING_WALL := 0.11
const RING_H := 0.62
const RING_SINK := 0.3
const ASH_Y := 0.17
## Clearance the sunbathers and the palms keep from a ring's centre (m), and the room a lit ring's
## group takes.
const RING_CLEAR := 1.4
const GROUP_CLEAR := 3.4
## Odds a ring is lit on a given night, and the window: lit from START, out by END (hours; past
## midnight is 24+).
const LIT_ODDS := 0.62
const START := Vector2(18.4, 20.2)
const END := Vector2(22.3, 24.6)
## How many sit round a lit ring, and how far from its centre (m).
const GROUP := Vector2i(2, 6)
const SEAT_R := Vector2(1.7, 2.15)
## The crowd rigs a bonfire's people are (street clothes: the windbreaker, the cardigan, the
## hoodie, the polo and four more), and the poses as [weight, base pose, BEACH_POSES key, blanket,
## chair].
const MODELS := [0, 3, 4, 7, 12, 13, 14, 16]
const POSES := [
	[0.3, RoughSleeper.Pose.SIT, "", true, false],
	[0.24, RoughSleeper.Pose.SIT, "sit_lean", true, false],
	[0.3, RoughSleeper.Pose.CHAIR, "beach_chair", false, true],
	[0.16, RoughSleeper.Pose.STAND, "", false, false],
]
## Draw distances (m): the ring, the fire's particles, the people, the pool.
const RING_DRAW := 260.0
const FIGURE_DRAW := 170.0
const FIGURE_SHADOW := 50.0
const LOD_POOL_DRAW := 2600.0
## The pool of firelight on the sand: its colour (sRGB), strength and size (m across).
const POOL_TINT := Color(1.0, 0.52, 0.2)
const POOL_STRENGTH := 1.5
const POOL_SIZE := 15.0
const LOD_POOL_SIZE := 22.0

## Vertex-alpha codes (shaders/bonfire.gdshader reads round(alpha * 8)).
const K_CONCRETE := 0
const K_ASH := 1
const K_CHAR := 2
const K_LOG := 3
const K_BARK := 4
const K_CUT := 5

static var _meshes: Dictionary = {}
static var _materials: Dictionary = {}


# --- Where and when ----------------------------------------------------------------------------

static func _h(parts: Array) -> float:
	return float(absi(hash(parts)) % 1000003) / 1000003.0


static func _hi(parts: Array) -> int:
	return absi(hash(parts))


## The rings whose slots' centres lie in z0..z1 (pure, world-anchored: two neighbours split the
## shore between them): [{at: Vector2, yaw, k, land: Vector2 (inland across the shore)}].
static func rings_in(plan: CityPlan, z0: float, z1: float) -> Array:
	var out: Array = []
	if plan == null or plan.macro == null:
		return out
	var macro: MacroMap = plan.macro
	var courts := BeachLife.courts_in(plan, z0 - 30.0, z1 + 30.0)
	for k in range(floori(z0 / RING_CELL) - 1, floori(z1 / RING_CELL) + 2):
		var zc := (float(k) + 0.5) * RING_CELL
		if zc < z0 or zc >= z1:
			continue
		if _h([plan.seed, "bonfire_ring", k]) >= RING_ODDS or BeachLife.kept_off(plan, zc):
			continue
		var w := macro.beach_width_at(zc)
		if w < MIN_WIDTH:
			continue
		var a := lerpf(RING_AT.x, RING_AT.y, _h([plan.seed, "bonfire_at", k]))
		var dz := (_h([plan.seed, "bonfire_dz", k]) - 0.5) * RING_CELL * 0.45
		var z := zc + dz
		var cx := macro.coast_x(z)
		var at := Vector2(cx + w * a, z)
		# Clear of the bike path's edge by the group's room.
		if BeachLife.path_x(plan, z) - BeachLife.PATH_WIDTH * 0.5 - at.x < GROUP_CLEAR + 0.6:
			continue
		var on_court := false
		for c: Dictionary in courts:
			on_court = on_court or BeachLife._near_court(c, at, GROUP_CLEAR + 1.0)
		if on_court:
			continue
		var slope := (macro.coast_x(z + 2.0) - macro.coast_x(z - 2.0)) / 4.0
		var land := Vector2(1.0, -slope).normalized()
		out.append({"at": at, "yaw": _h([plan.seed, "bonfire_yaw", k]) * TAU, "k": k, "land": land})
	return out


## The night `hour` (0..24, on day `day`) belongs to, and the hour counted from that night's
## evening (past midnight is 24+): [night, hour].
static func night_of(hour: float, day: int) -> Array:
	var h := fposmod(hour, 24.0)
	if h < 6.0:
		return [day - 1, h + 24.0]
	return [day, h]


## Ring `k`'s fire on `night`: Vector2(start, end) in evening hours, or Vector2.ZERO if it is not
## lit that night.
static func lit_window(plan: CityPlan, k: int, night: int) -> Vector2:
	if force_lit == 0:
		return Vector2.ZERO
	if force_lit == 1:
		return Vector2(START.x - 1.0, 30.0)
	if _h([plan.seed, "bonfire_lit", k, night]) >= LIT_ODDS:
		return Vector2.ZERO
	var s := lerpf(START.x, START.y, _h([plan.seed, "bonfire_start", k, night]))
	var e := lerpf(END.x, END.y, _h([plan.seed, "bonfire_end", k, night]))
	return Vector2(s, e)


## Whether ring `k` burns at `hour` on `day` in `weather` (a Weather.State; -1 unknown).
static func lit_at(plan: CityPlan, k: int, hour: float, day: int, weather: int = -1) -> bool:
	if weather == Weather.State.RAIN or weather == Weather.State.STORM or weather == Weather.State.SANTA_ANA:
		return false
	var n := night_of(hour, day)
	var win := lit_window(plan, k, int(n[0]))
	return win != Vector2.ZERO and float(n[1]) >= win.x and float(n[1]) < win.y


## The hour, the day and the weather a node sees: [hour, day, weather state or -1].
static func clock(node: Node) -> Array:
	var hour := force_hour if force_hour >= 0.0 else BeachLife.hour_now(node)
	var day := 0
	var weather := -1
	var tree := node.get_tree() if node and node.is_inside_tree() else (Engine.get_main_loop() as SceneTree)
	var scene := tree.current_scene if tree else null
	if scene:
		var dn := scene.get_node_or_null("DayNight")
		if dn and dn.get("day_count") != null:
			day = int(dn.get("day_count"))
		var w := scene.get_node_or_null("Weather")
		if w and w.get("state") != null:
			weather = int(w.get("state"))
	return [hour, day, weather]


## Who sits round lit ring `ring` on `night` (pure): [{at, yaw, pose, key, model, blanket, chair}].
## Spread round the fire with a gap on the sea side (people sit facing the water past the flames)
## and turned to its middle.
static func group(plan: CityPlan, ring: Dictionary, night: int) -> Array:
	var out: Array = []
	var k: int = ring.k
	var hg := _hi([plan.seed, "bonfire_group", k, night])
	var n := GROUP.x + int(_h([hg, 0]) * float(GROUP.y - GROUP.x + 1) * 0.999)
	var centre: Vector2 = ring.at
	# The arc they sit on: most of the circle, its open side toward the sea (-land).
	var land: Vector2 = ring.land
	var sea := atan2(-land.y, -land.x)
	var gap := lerpf(0.55, 1.4, _h([hg, 1]))
	var arc := TAU - gap
	for i in n:
		var hp := _hi([hg, "p", i])
		var t := (float(i) + 0.5 + (_h([hp, 0]) - 0.5) * 0.5) / float(n)
		var ang := sea + gap * 0.5 + arc * t
		var pick := _h([hp, 1])
		var row: Array = POSES[POSES.size() - 1]
		for r: Array in POSES:
			if pick < float(r[0]):
				row = r
				break
			pick -= float(r[0])
		var r_seat := lerpf(SEAT_R.x, SEAT_R.y, _h([hp, 2]))
		if int(row[1]) == RoughSleeper.Pose.STAND:
			r_seat += 0.35
		var dir := Vector2(cos(ang), sin(ang))
		var at := centre + dir * r_seat
		var to_fire := -dir
		# Facing is -Z: yaw for direction d is atan2(-d.x, -d.z).
		var yaw := atan2(-to_fire.x, -to_fire.y) + (_h([hp, 3]) - 0.5) * 0.35
		var model: int = MODELS[_hi([hp, 4]) % MODELS.size()]
		out.append({"at": at, "yaw": yaw, "pose": int(row[1]), "key": String(row[2]), "model": model,
			"blanket": bool(row[3]), "chair": bool(row[4]), "paint": BeachLife.TOWELS[_hi([hp, 5]) % BeachLife.TOWELS.size()],
			"pal": _hi([hp, 6]) % BeachLife.CANVAS2.size()})
	return out


# --- Building a chunk ---------------------------------------------------------------------------

## A FULL beach chunk's rings, called from CityChunk._build_beach() BEFORE BeachLife.build():
## `obstacles` are its palms and tower ([point, radius]); a ring that would stand in one is not
## built, and every ring built is added to them, so BeachLife's sunbathers keep clear of it.
static func build(ch: CityChunk, z0: float, z1: float, obstacles: Array) -> void:
	if not enabled or ch.plan == null or ch.plan.macro == null:
		return
	var plan := ch.plan
	var c := clock(ch)
	var hour: float = c[0]
	var day: int = c[1]
	var weather: int = c[2]
	var n := night_of(hour, day)
	var built: Array = []
	for ring: Dictionary in rings_in(plan, z0, z1):
		var at: Vector2 = ring.at
		if not BeachLife._clear_of(obstacles, at, GROUP_CLEAR):
			continue
		built.append(ring)
	ch.set_meta("bonfires", built)
	var people_all: Array = []
	for ring: Dictionary in built:
		var at: Vector2 = ring.at
		var y := BeachLife.sand_y(ch, at.x, at.y)
		var xf := Transform3D(Basis(Vector3.UP, float(ring.yaw)), Vector3(at.x, y, at.y))
		ch._batch.add("bonfire_ring", ring_mesh(), xf)
		ch._add_shape(Vector3(RING_R * 1.8, RING_H + RING_SINK, RING_R * 1.8), Vector3(at.x, y + (RING_H - RING_SINK) * 0.5, at.y), float(ring.yaw))
		obstacles.append([at, RING_CLEAR])
		var lit := lit_at(plan, int(ring.k), hour, day, weather)
		var fire := BonfireFire.new()
		fire.name = "Bonfire_%d" % int(ring.k)
		fire.ring_k = int(ring.k)
		fire.plan = plan
		fire.position = Vector3(at.x, y, at.y)
		ch.add_child(fire)
		if not lit:
			continue
		# A lit ring has its people, their chairs and blankets, a cooler and the firewood.
		obstacles.append([at, GROUP_CLEAR])
		var hr := _hi([plan.seed, "bonfire_kit", int(ring.k), int(n[0])])
		for p: Dictionary in group(plan, ring, int(n[0])):
			people_all.append(p)
			var pa: Vector2 = p.at
			var custom := Color((p.paint as Color).r, (p.paint as Color).g, (p.paint as Color).b, float(p.pal) / 8.0)
			if p.blanket:
				var tc := pa - (pa - at).normalized() * 0.15
				ch._batch.add("beach_towel", BeachLife.prop_mesh("towel"), Transform3D(Basis(Vector3.UP, float(p.yaw) + PI * 0.5),
					Vector3(tc.x, BeachLife.sand_y(ch, tc.x, tc.y), tc.y)), Color.WHITE, custom)
			if p.chair:
				ch._batch.add("beach_chair", BeachLife.prop_mesh("chair"), Transform3D(Basis(Vector3.UP, float(p.yaw)),
					Vector3(pa.x, BeachLife.sand_y(ch, pa.x, pa.y), pa.y)), Color.WHITE, custom)
		var land: Vector2 = ring.land
		var away := Vector2(-land.y, land.x)
		if _h([hr, 0]) < 0.7:
			var cp := at + land * (SEAT_R.y + 0.9) + away * (_h([hr, 1]) - 0.5) * 2.0
			var cc: Color = BeachLife.COOLERS[_hi([hr, 2]) % BeachLife.COOLERS.size()]
			ch._batch.add("beach_cooler", BeachLife.prop_mesh("cooler"), Transform3D(Basis(Vector3.UP, _h([hr, 3]) * TAU),
				Vector3(cp.x, BeachLife.sand_y(ch, cp.x, cp.y), cp.y)), Color.WHITE, Color(cc.r, cc.g, cc.b, 0.0))
		var wp := at + Vector2(cos(_h([hr, 4]) * TAU), sin(_h([hr, 4]) * TAU)) * (RING_R + 0.55)
		ch._batch.add("bonfire_wood", wood_mesh(), Transform3D(Basis(Vector3.UP, _h([hr, 5]) * TAU),
			Vector3(wp.x, BeachLife.sand_y(ch, wp.x, wp.y), wp.y)))
	ch._batch.set_draw_distance("bonfire_ring", RING_DRAW)
	ch._batch.set_shadow_distance("bonfire_ring", 60.0)
	ch._batch.set_draw_distance("bonfire_wood", 120.0)
	ch._batch.set_no_shadow("bonfire_wood")
	if not people_all.is_empty():
		ch._run_or_defer(func() -> bool:
			_add_figures(ch, people_all)
			return true)


## The people round the fires: merged into one mesh by material (CampFigureMesh), each with its
## BonfireFigure body (collision, and the live person it wakes into).
static func _add_figures(ch: CityChunk, people: Array) -> void:
	var merged: BeachFigureMesh = null
	var zs := Vector2(INF, -INF)
	for p: Dictionary in people:
		zs = Vector2(minf(zs.x, (p.at as Vector2).y), maxf(zs.y, (p.at as Vector2).y))
	var ring := BeachLife.sand_ring(ch, zs.x - 20.0, zs.y + 20.0)
	for i in people.size():
		var p: Dictionary = people[i]
		var model: int = p.model
		var seed_value := BeachGoer.seed_for(model, 7)
		var at: Vector2 = p.at
		var lift := 0.025 if int(p.pose) == RoughSleeper.Pose.SIT else 0.0
		var fig := BonfireFigure.new()
		fig.name = "BonfireFigure_%d" % i
		fig.chunk = ch
		fig.pose = int(p.pose)
		fig.beach_pose = String(p.key)
		fig.model = model
		fig.seed_value = seed_value
		fig.home = at
		fig.yaw = float(p.yaw)
		fig.lift = lift
		fig.ring = ring
		fig.sidewalk = 4.0
		var xf := Transform3D(Basis(Vector3.UP, float(p.yaw)), Vector3(at.x, BeachLife.sand_y(ch, at.x, at.y) + lift, at.y))
		var mesh := BonfireFigure.bonfire_mesh(seed_value, int(p.pose), String(p.key), model)
		if mesh:
			if merged == null:
				merged = BeachFigureMesh.new()
				merged.name = "BonfireFigureMesh"
				merged.draw_distance = FIGURE_DRAW
				merged.shadow_distance = FIGURE_SHADOW
			fig.figure_mesh = merged
			fig.figure_index = merged.add_figure(mesh, CampFigure.shadow_for(mesh), xf)
		fig.transform = xf
		ch.add_child(fig)
	if merged:
		ch.add_child(merged)


## A LOD chunk's rings from a distance: the pool of firelight of every ring lit at the build hour,
## so the coast at night is a row of orange points. Nothing by day.
static func build_lod(ch: CityChunk, z0: float, z1: float) -> void:
	if not enabled or ch.plan == null or ch.plan.macro == null:
		return
	var c := clock(ch)
	var count := 0
	for ring: Dictionary in rings_in(ch.plan, z0, z1):
		if not lit_at(ch.plan, int(ring.k), c[0], c[1], c[2]):
			continue
		var at: Vector2 = ring.at
		var y := BeachLife.sand_y(ch, at.x, at.y) + 0.08
		var xf := Transform3D(Basis(Vector3.RIGHT, -PI * 0.5).scaled(Vector3(LOD_POOL_SIZE, LOD_POOL_SIZE, 1.0)), Vector3(at.x, y, at.y))
		ch._batch.add("bonfire_lod_pool", pool_mesh(), xf)
		count += 1
	if count > 0:
		ch._batch.set_no_shadow("bonfire_lod_pool")
		ch._batch.set_draw_distance("bonfire_lod_pool", LOD_POOL_DRAW)


# --- Meshes ------------------------------------------------------------------------------------

## The firelight's additive pool on the sand (light_pool.gdshader, lamp_factor-gated).
static func pool_mesh() -> Mesh:
	return PropFactory.light_pool(POOL_TINT, POOL_STRENGTH, 1.7)


## The shared material for the ring, the stubs and the firewood (`hot` the burning stack's copy:
## its coals glow).
static func material(hot: bool = false) -> ShaderMaterial:
	var key := "hot" if hot else "cold"
	if _materials.has(key):
		return _materials[key]
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/bonfire.gdshader")
	m.set_shader_parameter("heat", 1.0 if hot else 0.0)
	_materials[key] = m
	return m


static func _begin() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


static func _finish(st: SurfaceTool, key: String, hot: bool = false) -> Mesh:
	st.generate_tangents()
	var mesh := st.commit()
	mesh.surface_set_material(0, material(hot))
	_meshes[key] = mesh
	return mesh


## One triangle, wound to face `want` (the normal written flat). UV in metres (u along, v up).
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, want: Vector3, kind: int, uv := [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO], n := [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]) -> void:
	var cr := (b - a).cross(c - a)
	if cr.length_squared() < 1e-14:
		return
	var col := Color(1.0, 1.0, 1.0, float(kind) / 8.0)
	var verts := [a, b, c]
	var uvs: Array = uv
	var ns: Array = n
	if cr.dot(want) > 0.0:
		verts = [a, c, b]
		uvs = [uv[0], uv[2], uv[1]]
		ns = [n[0], n[2], n[1]]
	var flat := cr.normalized() * signf(cr.dot(want))
	for i in 3:
		st.set_color(col)
		st.set_uv(uvs[i])
		st.set_uv2(Vector2((verts[i] as Vector3).y, 0.0))
		var nn: Vector3 = ns[i]
		st.set_normal(nn if nn != Vector3.ZERO else flat)
		st.add_vertex(verts[i])


## A surface of revolution about +Y from a profile [(r, y)], `sides` round, smooth across the turn.
static func _lathe(st: SurfaceTool, prof: Array, sides: int, kind: int) -> void:
	for i in prof.size() - 1:
		var p0: Vector2 = prof[i]
		var p1: Vector2 = prof[i + 1]
		var seg := Vector2(p1.x - p0.x, p1.y - p0.y)
		# The profile's own normal in (r, y): the profiles run up the outside, in over the top and
		# down the inside, so (dy, -dr) is always the face's outside.
		var pn := Vector2(seg.y, -seg.x).normalized()
		var vlen := seg.length()
		for s in sides:
			var a0 := TAU * float(s) / float(sides)
			var a1 := TAU * float(s + 1) / float(sides)
			var d0 := Vector3(cos(a0), 0.0, sin(a0))
			var d1 := Vector3(cos(a1), 0.0, sin(a1))
			var v00 := d0 * p0.x + Vector3.UP * p0.y
			var v01 := d1 * p0.x + Vector3.UP * p0.y
			var v10 := d0 * p1.x + Vector3.UP * p1.y
			var v11 := d1 * p1.x + Vector3.UP * p1.y
			var n0 := (d0 * pn.x + Vector3.UP * pn.y).normalized()
			var n1 := (d1 * pn.x + Vector3.UP * pn.y).normalized()
			var u0 := a0 * maxf(p0.x, 0.05)
			var u1 := a1 * maxf(p0.x, 0.05)
			var want := (d0 + d1).normalized() * pn.x + Vector3.UP * pn.y
			_tri(st, v00, v01, v11, want, kind, [Vector2(u0, p0.y), Vector2(u1, p0.y), Vector2(u1, p0.y + vlen)], [n0, n1, n1])
			_tri(st, v00, v11, v10, want, kind, [Vector2(u0, p0.y), Vector2(u1, p0.y + vlen), Vector2(u0, p0.y + vlen)], [n0, n1, n0])


## A log from `a` to `b`, radius `r`: `sides` round, bark (or char) round it, cut faces at the ends.
static func _log(st: SurfaceTool, a: Vector3, b: Vector3, r: float, sides: int, kind: int, end_kind: int) -> void:
	var ax := (b - a).normalized()
	var side := ax.cross(Vector3.UP)
	if side.length_squared() < 1e-4:
		side = ax.cross(Vector3.RIGHT)
	side = side.normalized()
	var up := side.cross(ax).normalized()
	var length := a.distance_to(b)
	for s in sides:
		var a0 := TAU * float(s) / float(sides)
		var a1 := TAU * float(s + 1) / float(sides)
		# A little out of round, like a split or a knotty branch.
		var r0 := r * (1.0 + 0.12 * sin(a0 * 3.0 + length * 7.0))
		var r1 := r * (1.0 + 0.12 * sin(a1 * 3.0 + length * 7.0))
		var d0 := side * cos(a0) + up * sin(a0)
		var d1 := side * cos(a1) + up * sin(a1)
		_tri(st, a + d0 * r0, a + d1 * r1, b + d1 * r1, d0 + d1, kind,
			[Vector2(a0 * r, 0.0), Vector2(a1 * r, 0.0), Vector2(a1 * r, length)], [d0, d1, d1])
		_tri(st, a + d0 * r0, b + d1 * r1, b + d0 * r0, d0 + d1, kind,
			[Vector2(a0 * r, 0.0), Vector2(a1 * r, length), Vector2(a0 * r, length)], [d0, d1, d0])
		_tri(st, a, a + d0 * r0, a + d1 * r1, -ax, end_kind, [Vector2(0.5, 0.5), Vector2(0.5 + cos(a0) * 0.5, 0.5 + sin(a0) * 0.5), Vector2(0.5 + cos(a1) * 0.5, 0.5 + sin(a1) * 0.5)])
		_tri(st, b, b + d1 * r1, b + d0 * r0, ax, end_kind, [Vector2(0.5, 0.5), Vector2(0.5 + cos(a1) * 0.5, 0.5 + sin(a1) * 0.5), Vector2(0.5 + cos(a0) * 0.5, 0.5 + sin(a0) * 0.5)])


## The ring with its ash bed and last night's charred stubs (origin on the sand at its centre).
static func ring_mesh() -> Mesh:
	if _meshes.has("ring"):
		return _meshes["ring"]
	var st := _begin()
	var ro := RING_R
	var ri := RING_R - RING_WALL
	var sides := 28
	# The outer wall from under the sand up to a rounded rim (a precast ring's arris is eased),
	# over the top and down the inside to the ash.
	var bev := 0.025
	_lathe(st, [Vector2(ro + 0.01, -RING_SINK), Vector2(ro, RING_H - bev), Vector2(ro - bev * 0.3, RING_H - bev * 0.3), Vector2(ro - bev, RING_H)], sides, K_CONCRETE)
	_lathe(st, [Vector2(ro - bev, RING_H), Vector2(ri + bev, RING_H)], sides, K_CONCRETE)
	_lathe(st, [Vector2(ri + bev, RING_H), Vector2(ri + bev * 0.3, RING_H - bev * 0.3), Vector2(ri, RING_H - bev), Vector2(ri - 0.004, ASH_Y - 0.04)], sides, K_CONCRETE)
	# The ash bed: a shallow mound, highest a little off centre where the fire sat.
	var rings := 4
	for j in rings:
		var t0 := float(j) / float(rings)
		var t1 := float(j + 1) / float(rings)
		var ra := ri * t0
		var rb := ri * t1
		var ya := ASH_Y + 0.06 * (1.0 - t0 * t0)
		var yb := ASH_Y + 0.06 * (1.0 - t1 * t1)
		for s in sides:
			var a0 := TAU * float(s) / float(sides)
			var a1 := TAU * float(s + 1) / float(sides)
			var p00 := Vector3(cos(a0) * ra, ya, sin(a0) * ra)
			var p01 := Vector3(cos(a1) * ra, ya, sin(a1) * ra)
			var p10 := Vector3(cos(a0) * rb, yb, sin(a0) * rb)
			var p11 := Vector3(cos(a1) * rb, yb, sin(a1) * rb)
			_tri(st, p00, p10, p11, Vector3.UP, K_ASH, [Vector2(p00.x, p00.z), Vector2(p10.x, p10.z), Vector2(p11.x, p11.z)])
			if j > 0:
				_tri(st, p00, p11, p01, Vector3.UP, K_ASH, [Vector2(p00.x, p00.z), Vector2(p11.x, p11.z), Vector2(p01.x, p01.z)])
	# Burnt stubs half sunk in the ash.
	var stubs := [[Vector3(-0.26, ASH_Y + 0.05, -0.08), Vector3(0.12, ASH_Y + 0.08, 0.1), 0.045],
		[Vector3(0.05, ASH_Y + 0.05, -0.3), Vector3(0.2, ASH_Y + 0.07, 0.05), 0.04],
		[Vector3(-0.12, ASH_Y + 0.06, 0.28), Vector3(0.1, ASH_Y + 0.05, -0.02), 0.035],
		[Vector3(0.28, ASH_Y + 0.04, 0.14), Vector3(0.05, ASH_Y + 0.09, 0.2), 0.03]]
	for s: Array in stubs:
		_log(st, s[0], s[1], float(s[2]), 7, K_CHAR, K_CHAR)
	return _finish(st, "ring")


## Tonight's fire: a stack of fresh logs leant together in the ring over a bed of coals (origin on
## the ring's centre at the sand; drawn by BonfireFire on the hot material).
static func stack_mesh() -> Mesh:
	if _meshes.has("stack"):
		return _meshes["stack"]
	var st := _begin()
	var base_y := ASH_Y + 0.05
	# Coals: a few fat chunks in a ring on the ash.
	for i in 9:
		var a := TAU * float(i) / 9.0 + 0.3
		var r := 0.12 + 0.13 * float(i % 3) / 2.0
		var c := Vector3(cos(a) * r, base_y + 0.02, sin(a) * r)
		_log(st, c - Vector3(cos(a + 1.2), 0.0, sin(a + 1.2)) * 0.06, c + Vector3(cos(a + 1.2), 0.01, sin(a + 1.2)) * 0.06, 0.035, 6, K_CHAR, K_CHAR)
	# A teepee of split logs: their feet round the coals, their tops leant together over the middle.
	var n := 7
	for i in n:
		var a := TAU * float(i) / float(n) + 0.17 * float(i % 2)
		var foot := Vector3(cos(a) * 0.36, base_y, sin(a) * 0.36)
		var top := Vector3(cos(a + 0.6) * 0.05, base_y + 0.62 + 0.06 * float(i % 3), sin(a + 0.6) * 0.05)
		_log(st, foot, top, 0.042 + 0.012 * float(i % 3), 7, K_LOG, K_CUT)
	# Two cross logs under it, burning through.
	_log(st, Vector3(-0.34, base_y + 0.04, -0.06), Vector3(0.33, base_y + 0.06, 0.08), 0.05, 7, K_LOG, K_CUT)
	_log(st, Vector3(-0.05, base_y + 0.09, -0.33), Vector3(0.08, base_y + 0.08, 0.32), 0.046, 7, K_LOG, K_CUT)
	return _finish(st, "stack", true)


## A bundle of firewood on the sand beside a lit ring (bought at the store: split logs, cut ends).
static func wood_mesh() -> Mesh:
	if _meshes.has("wood"):
		return _meshes["wood"]
	var st := _begin()
	var rows := [[Vector3(-0.2, 0.06, 0.0), 3], [Vector3(-0.2, 0.17, 0.05), 2], [Vector3(-0.2, 0.27, 0.0), 1]]
	for row: Array in rows:
		var o: Vector3 = row[0]
		var cnt: int = row[1]
		for i in cnt:
			var off := Vector3(0.0, 0.0, (float(i) - float(cnt - 1) * 0.5) * 0.115)
			var tw := 0.03 * sin(float(i) * 2.1 + o.y * 9.0)
			_log(st, o + off + Vector3(0.0, 0.0, tw), o + off + Vector3(0.42, 0.0, -tw), 0.055, 6, K_BARK, K_CUT)
	return _finish(st, "wood")


## What the loading screen builds (meshes, materials) so the first beach at night does not stall.
static func warm() -> void:
	if not enabled:
		return
	ring_mesh()
	stack_mesh()
	wood_mesh()
	pool_mesh()
	material(false)
	material(true)
