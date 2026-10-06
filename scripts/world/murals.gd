class_name Murals
extends RefCounted
## Los Angeles is a city of murals (VISUAL_ROADMAP #63): big painted scenes on blank walls,
## ghost signs fading off the old brick, painted crosswalks, painted signal cabinets. The Arts
## District's warehouses already carry their own abstract murals (Industrial, industrial_walls
## .gdshader) and StreetWear the tags and posters; this is the rest of the city, and nothing here
## lands where those do.
##
## What and where, all of it hash-seeded (seed + wall / bent / junction / prop), never a chunk,
## block or Building rng, so nothing a seed already builds moves:
##   * Walls nobody built windows into: the freeway's sound walls and the yards' and campus' tall
##     stucco, block and brick walls (YardFill's wall boxes, read off the chunk before it commits
##     them), the freeway columns (StreetWear's column frame) - big scenes, a whole wall run as ONE
##     design painted panel by panel between the pilasters.
##   * Buildings: every Building face is glazed by building.gdshader, so a mural can only go
##     where StreetWear._paintable() finds a band of plain wall right across a stretch of face -
##     usually the band between the storefront and the first windows. There: a GHOST SIGN (an
##     invented old advertisement, tools/make_murals.py's atlas) on the brick of the historic core
##     and the Arts District, and a painted FRIEZE of folk geometry elsewhere now and then; a full
##     mural where a band is tall enough (rare).
##   * Painted crosswalks: one rule per district from a hash (none, rainbow, folk geometry, waves,
##     flowers), and then about half of that district's signal and stop junctions.
##   * Painted signal cabinets: a small scene wrapped round all four sides, with the prop.
## Never within a place of worship's reach (StreetWear.WORSHIP_IDS + margin), never over glass,
## heights measured from the pavement.
##
## How it is drawn: one quad mesh on one shader (shaders/mural.gdshader paints every scene from
## the seed), ONE MultiMesh ("mural") per FULL chunk, transparent, no shadows, faded out by
## DRAW_DISTANCE. LOD chunks and the far city get nothing (a mural is a few pixels past the FULL
## ring). See the shader's header for the instance data.
##
## Static: CityChunk runs build() as a build step of a FULL chunk, after StreetWear; it queues its
## real work as the last step before the finish, after YardFill's deferred walls.

# --- Tunables (consts: never instanced) ----------------------------------------------------------

## Per CityPlan.District (DOWNTOWN, MIDTOWN, SUBURBS, INDUSTRIAL, CAMPUS, BEACHTOWN):
## odds a freeway column face toward a street is painted (both columns of a bent alike).
const PILLAR_ODDS := [0.22, 0.3, 0.2, 0.18, 0.25, 0.35]
## Odds a tall yard / campus / sound wall run carries a mural.
const WALL_ODDS := [0.45, 0.5, 0.35, 0.35, 0.55, 0.5]
## Odds a brick face with a clear band carries a ghost sign (historic core and Arts District),
## and any other masonry face there.
const GHOST_BRICK := 0.4
const GHOST_OTHER := 0.12
## Odds a face with a clear band carries a painted frieze, by district.
const FRIEZE_ODDS := [0.05, 0.1, 0.08, 0.03, 0.1, 0.14]
## Odds a signal cabinet is painted, by district.
const CABINET_ODDS := [0.5, 0.55, 0.4, 0.25, 0.55, 0.6]
## Of the junctions in a district whose rule paints crosswalks, how many are painted (by district).
const CROSSWALK_ODDS := [0.2, 0.35, 0.15, 0.0, 0.4, 0.4]
## Scene weights per district: coast, mountains, desert, botanical, folk, waves.
const SCENE_WEIGHTS := [
	[1.0, 2.0, 1.0, 2.0, 2.0, 1.0], [2.0, 2.0, 1.0, 3.0, 2.0, 1.0], [2.0, 2.0, 1.0, 2.0, 1.0, 1.0],
	[1.0, 1.0, 2.0, 1.0, 2.0, 1.0], [1.0, 2.0, 1.0, 2.0, 2.0, 1.0], [4.0, 1.0, 0.0, 2.0, 1.0, 3.0],
]
## Scenes that read in a tall narrow panel (a column face): coast (palms), botanical, folk, waves.
const TALL_SCENES := [0, 3, 4, 5]
## Smallest wall worth a mural (metres), and the tallest a painter's lift reaches here.
const MIN_WALL_LEN := 4.0
const MIN_WALL_H := 1.8
const MAX_MURAL_H := 9.0
## Ghost signs only on buildings up to this tall (the old core's warehouses, lofts and hotels),
## and not higher up the wall than this.
const GHOST_MAX_TOP := 45.0
const GHOST_MAX_V := 26.0
const MAX_SETBACK := 22.0
const CORNER_CLEAR := 2.0
## Most instances in one chunk.
const MAX_PER_CHUNK := 160
const DRAW_DISTANCE := 230.0

const KEY := "mural"
const MODE_MURAL := 0
const MODE_GHOST := 1
const MODE_CROSSWALK := 2
const MODE_WRAP := 3
const MODE_FRIEZE := 4
## Substrates (what the paint is on), for the shader.
const SUB_STUCCO := 0
const SUB_CONCRETE := 1
const SUB_BRICK := 2
const SUB_BLOCK := 3
const SUB_ASPHALT := 4
const SUB_STEEL := 5
## Crosswalk patterns (the shader's scene for MODE_CROSSWALK).
const XWALK_RAINBOW := 0
const XWALK_FOLK := 1
const XWALK_WAVES := 2
const XWALK_FLOWERS := 3
const GHOST_CELLS := 16

## Off: build() adds nothing (MURALS=0 in the environment, the A/B).
static var enabled: bool = OS.get_environment("MURALS") != "0"
## The web reads no screen texture (as StreetWear).
static var full_detail: bool = not OS.has_feature("web")
## Keep every placement on the chunk's "mural_spots" meta ([mode, centre, normal, w, h]), for
## tools/murals/probe.gd (MURAL_DEBUG=1).
static var debug: bool = OS.get_environment("MURAL_DEBUG") == "1"

static var _mesh: ArrayMesh = null
static var _material: ShaderMaterial = null


# --- Entry ---------------------------------------------------------------------------------------

## A build step of a FULL chunk (after StreetWear): queues the work behind every deferred step
## (CityChunk._run_last), so YardFill's deferred walls are all there.
static func build(chunk: CityChunk) -> void:
	if not enabled or chunk.level != CityChunk.Level.FULL or chunk.capturing:
		return
	chunk._run_last(_work.bind(chunk))


static func _work(chunk: CityChunk) -> bool:
	paint(chunk)
	return true


## Everything for one chunk, at once (the tests call it on a built chunk's state too).
static func paint(chunk: CityChunk) -> void:
	var plan: CityPlan = chunk.plan
	var ctx := {"chunk": chunk, "count": 0, "points": [], "modes": {}, "blocked": StreetWear._worship_near(plan, chunk.owned_rect())}
	var block := plan.block(chunk.ix, chunk.iz)
	var district := int(block.district)
	if chunk.zone == MacroMap.Zone.CITY and not block.has("site"):
		if int(block.kind) == CityPlan.BlockKind.BUILDINGS:
			_buildings(ctx, block, district)
		_crosswalks(ctx, district)
		_cabinets(ctx, district)
	_yard_walls(ctx, district)
	_pillars(ctx)
	if int(ctx.count) > 0:
		chunk._batch.set_no_shadow(KEY)
		chunk._batch.set_draw_distance(KEY, DRAW_DISTANCE)
	chunk.set_meta("murals", PackedVector2Array(ctx.points))
	# How many of each MODE_*, for the smoke test (instance data reads back empty headless).
	chunk.set_meta("mural_modes", ctx.modes)


## The crosswalk pattern a district's junctions are painted in, or -1 for none: one rule per
## district from a hash of the seed, so some districts paint theirs and the rest keep them white.
static func crosswalk_rule(plan: CityPlan, district: int) -> int:
	var h := _h01([plan.seed, "mural_xwalk_rule", district])
	if h < 0.4 or district == CityPlan.District.INDUSTRIAL:
		return -1
	return mini(int((h - 0.4) / 0.6 * 4.0), 3)


## The custom data of one instance (see the shader header).
static func custom(mode: int, scene: int, seed01: float, b: float, substrate: int, wear: int) -> Color:
	return Color(float(mode * 16 + scene), snappedf(clampf(seed01, 0.0, 0.999), 0.001), b, float(substrate + 8 * clampi(wear, 0, 7)))


## A signal cabinet's four faces in its own frame (0.78 x 1.44 x 0.52 m on a 0.12 m pad, door
## toward +z): [centre, normal, width, height] of the painted wrap on each.
static func cabinet_faces() -> Array:
	return [
		[Vector3(0.0, 0.86, 0.264), Vector3(0, 0, 1), 0.74, 1.3], [Vector3(0.0, 0.86, -0.264), Vector3(0, 0, -1), 0.74, 1.3],
		[Vector3(0.394, 0.86, 0.0), Vector3(1, 0, 0), 0.48, 1.3], [Vector3(-0.394, 0.86, 0.0), Vector3(-1, 0, 0), 0.48, 1.3],
	]


static func _h01(parts: Array) -> float:
	return float(absi(hash(parts)) % 100000) / 100000.0


static func _ok(ctx: Dictionary, p: Vector2) -> bool:
	if int(ctx.count) >= MAX_PER_CHUNK:
		return false
	for b: Array in ctx.blocked:
		if p.distance_to(b[0]) < float(b[1]):
			return false
	return true


static func _scene(district: int, h: float, tall: bool) -> int:
	var weights: Array = SCENE_WEIGHTS[clampi(district, 0, SCENE_WEIGHTS.size() - 1)]
	var total := 0.0
	for i in weights.size():
		if not tall or TALL_SCENES.has(i):
			total += float(weights[i])
	var x := h * total
	for i in weights.size():
		if tall and not TALL_SCENES.has(i):
			continue
		x -= float(weights[i])
		if x <= 0.0:
			return i
	return 3


## One instance: `center` chunk-local with its TRUE height (the batch adds the relief, so it is
## taken off here), `basis` (x the width, y the height, z the facing scaled by the width), the
## design's whole width (`design_w`), the piece's left edge in it, the age.
static func _put(ctx: Dictionary, mode: int, scene: int, center: Vector3, basis: Basis, seed01: float, offset: float, design_w: float,
		age: float, substrate: int, wear: int, color: Color = Color(0, 0, 0, 0)) -> int:
	if int(ctx.count) >= MAX_PER_CHUNK:
		return -1
	var chunk: CityChunk = ctx.chunk
	var at := center - Vector3(0.0, chunk._gy(center.x, center.z), 0.0)
	var col := color if mode == MODE_GHOST else Color(0.0, age, 0.0, 1.0)
	# The whole design's width rides the basis' normal column (see the shader header).
	basis.z = basis.z.normalized() * maxf(design_w, 0.05)
	var index := chunk._batch.add(KEY, mesh(), Transform3D(basis, at), col, custom(mode, scene, seed01, offset, substrate, wear))
	ctx.count = int(ctx.count) + 1
	(ctx.points as Array).append(Vector2(center.x, center.z))
	ctx.modes[mode] = int((ctx.modes as Dictionary).get(mode, 0)) + 1
	if debug:
		var spots: Array = chunk.get_meta("mural_spots", [])
		spots.append([mode, center, basis.z.normalized(), basis.x.length(), basis.y.length()])
		chunk.set_meta("mural_spots", spots)
	return index


## A wall quad facing `n` (horizontal, unit), `w` x `h`.
static func _wall_basis(n: Vector3, w: float, h: float) -> Basis:
	var right := Vector3.UP.cross(n).normalized()
	return Basis(right * w, Vector3.UP * h, n * w)


# --- Buildings: ghost signs, friezes ---------------------------------------------------------------

static func _buildings(ctx: Dictionary, block: Dictionary, district: int) -> void:
	var chunk: CityChunk = ctx.chunk
	var plan: CityPlan = chunk.plan
	var parts := StreetWear._ground_parts(chunk)
	if parts.is_empty():
		return
	var rect: Rect2 = block.rect
	var edges := CityChunk._sidewalk_edges(rect)
	for e in edges.size():
		var a: Vector2 = edges[e][0]
		var b: Vector2 = edges[e][1]
		var inward: Vector2 = edges[e][2]
		var length := a.distance_to(b)
		if length < 10.0:
			continue
		var dir := (b - a) / length
		var faces: Array = []
		for p: Dictionary in parts:
			var r: Rect2 = p.rect
			var depth: float
			if inward.y > 0.5:
				depth = r.position.y - a.y
			elif inward.y < -0.5:
				depth = a.y - r.end.y
			elif inward.x > 0.5:
				depth = r.position.x - a.x
			else:
				depth = a.x - r.end.x
			if depth < 0.2 or depth > MAX_SETBACK:
				continue
			var s0: float
			var s1: float
			if absf(dir.x) > 0.5:
				s0 = (r.position.x - a.x) * dir.x
				s1 = (r.end.x - a.x) * dir.x
			else:
				s0 = (r.position.y - a.y) * dir.y
				s1 = (r.end.y - a.y) * dir.y
			faces.append([depth, minf(s0, s1), maxf(s0, s1), p])
		faces.sort_custom(func(x: Array, y: Array) -> bool: return float(x[0]) < float(y[0]))
		var covered: Array = []
		for f: Array in faces:
			var lo := maxf(float(f[1]), CORNER_CLEAR)
			var hi := minf(float(f[2]), length - CORNER_CLEAR)
			for piece: Vector2 in StreetWear._subtract(Vector2(lo, hi), covered):
				if piece.y - piece.x > 4.0:
					_face_run(ctx, f[3], Vector3(-inward.x, 0.0, -inward.y), a, dir, float(f[0]), inward, piece, district)
			covered.append(Vector2(float(f[1]), float(f[2])))


## The clear horizontal bands of a face over the u range [u0, u1]: [[v0, v1], ...] in true
## heights, from `lo` up to `hi`. Above the storefront the windows repeat by column, so a row is
## clear when one column of it is (sampled finely) and the range's ends are.
static func _bands(part: Dictionary, face: int, u0: float, u1: float, lo: float, hi: float) -> Array:
	var along_x := face >= 2
	var pitch: float = part.pitch_x if along_x else part.pitch_z
	var mid := floorf((u0 + u1) * 0.5 / pitch) * pitch
	var out: Array = []
	var start := -1.0
	var v := lo
	while v <= hi:
		var clear := true
		for k in 21:
			var u := mid + pitch * float(k) / 20.0
			if u < u0 or u > u1:
				continue
			if not StreetWear._paintable(part, face, u, v):
				clear = false
				break
		if clear:
			clear = StreetWear._paintable(part, face, u0, v) and StreetWear._paintable(part, face, u1, v)
		if clear and start < 0.0:
			start = v
		elif not clear and start >= 0.0:
			out.append(Vector2(start, v - 0.1))
			start = -1.0
		v += 0.1
	if start >= 0.0:
		out.append(Vector2(start, hi))
	return out


## One visible stretch of one building face: maybe a ghost sign, a frieze or a mural in a clear
## band of it.
static func _face_run(ctx: Dictionary, part: Dictionary, n: Vector3, a: Vector2, dir: Vector2, depth: float, inward: Vector2,
		piece: Vector2, district: int) -> void:
	var chunk: CityChunk = ctx.chunk
	var plan: CityPlan = chunk.plan
	var bld: Building = part.building
	var face := StreetWear._face(part, n)
	var q0 := a + dir * piece.x + inward * depth
	var q1 := a + dir * piece.y + inward * depth
	var mid2 := (q0 + q1) * 0.5
	if not _ok(ctx, mid2):
		return
	var key := [plan.seed, "mural_face", int(mid2.x * 4.0), int(mid2.y * 4.0), face]
	var roll := _h01(key + ["roll"])
	var brick := bld.finish == Building.Finish.BRICK
	var glass := bld.finish == Building.Finish.GLASS
	var historic := (district == CityPlan.District.DOWNTOWN and plan.macro and plan.macro.skyline_boost(mid2) < 0.5) or Industrial.arts(plan, mid2)
	var ghost_odds := (GHOST_BRICK if brick else (0.0 if glass else GHOST_OTHER)) if historic else 0.0
	var frieze_odds := 0.0 if glass or part.warehouse else float(FRIEZE_ODDS[district])
	if roll >= ghost_odds + frieze_odds:
		return
	var ghost := roll < ghost_odds
	if ghost and float(part.top) - float(part.base) > GHOST_MAX_TOP:
		return
	var ground := maxf(float(part.base), CityChunk.SIDEWALK_TOP + chunk._gy(mid2.x, mid2.y))
	var p0 := Vector3(q0.x, 0.0, q0.y)
	var p1 := Vector3(q1.x, 0.0, q1.y)
	var ua := StreetWear._u_on_face(part, face, p0)
	var ub := StreetWear._u_on_face(part, face, p1)
	var u0 := minf(ua, ub) + 0.4
	var u1 := maxf(ua, ub) - 0.4
	if u1 - u0 < 4.0:
		return
	# Above the storefront (and its sign band), never higher than a sign painter's scaffold went.
	var lo := ground + 2.6
	if part.storefront:
		lo = maxf(lo, float(part.gfh) + 0.1)
	var hi := minf(float(part.top) - 0.6, ground + (GHOST_MAX_V if ghost else 14.0))
	if hi - lo < 1.0:
		return
	var bands := _bands(part, face, u0, u1, lo, hi)
	var best := Vector2.ZERO
	for bd: Vector2 in bands:
		var h := bd.y - bd.x
		# A ghost sign wants the highest band that holds one; a frieze the lowest.
		if h >= 0.9 and (best == Vector2.ZERO or (ghost and bd.x > best.x)):
			best = bd
	if best == Vector2.ZERO:
		return
	var bh := best.y - best.x
	var run := u1 - u0
	var right := Vector3.UP.cross(n)
	var age := 0.2 + 0.6 * _h01(key + ["age"])
	var at_u := func(u: float, v: float) -> Vector3:
		return StreetWear._face_point(part, face, u, v) + n * 0.012
	if ghost:
		var h := clampf(bh - 0.15, 0.8, 3.2)
		var w := h * 4.0
		if w > run - 0.5:
			w = run - 0.5
			h = w / 4.0
			if h < 0.7:
				return
		var uc := u0 + w * 0.5 + (run - w) * _h01(key + ["u"])
		var c: Vector3 = at_u.call(uc, best.x + bh * 0.5)
		# The wall's own colour for the patch a later tenant painted over part of it.
		var wall: Color = part.facade
		_put(ctx, MODE_GHOST, 0, c, _wall_basis(n, w, h), _h01(key + ["seed"]), float(absi(hash(key + ["cell"])) % GHOST_CELLS), w,
			0.0, SUB_BRICK if brick else SUB_STUCCO, 3, Color(wall.r, wall.g, wall.b, clampf(age + 0.2, 0.0, 1.0)))
		return
	if bh >= 2.8:
		# Tall enough for a scene.
		var h := minf(bh - 0.3, 6.0)
		var w := minf(run - 0.5, h * 4.0)
		var uc := u0 + w * 0.5 + (run - w) * _h01(key + ["u"])
		var c: Vector3 = at_u.call(uc, best.x + bh * 0.5)
		_put(ctx, MODE_MURAL, _scene(district, _h01(key + ["scene"]), w < h * 0.7), c, _wall_basis(n, w, h), _h01(key + ["seed"]), 0.0, w,
			age * 0.6, SUB_STUCCO, 2)
		return
	# A frieze: a folk band along the whole stretch.
	var h := minf(bh - 0.2, 1.3)
	var c: Vector3 = at_u.call((u0 + u1) * 0.5, best.x + bh * 0.5)
	_put(ctx, MODE_FRIEZE, 0, c, _wall_basis(n, run, h), _h01(key + ["seed"]), 0.0, run, age * 0.5, SUB_STUCCO, 1)


# --- Yard, campus and sound walls --------------------------------------------------------------------

## The tall walls YardFill laid in this chunk (ch._yard_walls: [size, centre, kind, paint, h],
## axis-aligned boxes, true heights), grouped into runs along one line; a run that wins its roll
## is ONE design painted panel by panel on the side the public sees.
static func _yard_walls(ctx: Dictionary, district: int) -> void:
	var chunk: CityChunk = ctx.chunk
	var plan: CityPlan = chunk.plan
	if chunk._yard_walls.is_empty():
		return
	var kinds := [YardFill.W_STUCCO, YardFill.W_SOUND, YardFill.W_CONCRETE, YardFill.W_BRICK]
	# Runs: key (axis, line) -> panels [lo, hi, centre, size, kind].
	var runs := {}
	for w: Array in chunk._yard_walls:
		var kind := int(w[2])
		if not kinds.has(kind) or float(w[4]) < MIN_WALL_H:
			continue
		var s: Vector3 = w[0]
		var c: Vector3 = w[1]
		var along_x := s.x > s.z
		var long := s.x if along_x else s.z
		if long < 1.5:
			continue
		var line := c.z if along_x else c.x
		var k := Vector3i(1 if along_x else 0, roundi(line * 4.0), kind)
		if not runs.has(k):
			runs[k] = []
		var lo := (c.x if along_x else c.z) - long * 0.5
		(runs[k] as Array).append([lo, lo + long, c, s, float(w[4])])
	var rect: Rect2 = plan.block(chunk.ix, chunk.iz).rect
	var corridor := _corridor_cells(chunk)
	for k: Vector3i in runs:
		var panels: Array = runs[k]
		panels.sort_custom(func(x: Array, y: Array) -> bool: return float(x[0]) < float(y[0]))
		# Split where the run breaks.
		var group: Array = []
		for i in panels.size() + 1:
			var p: Array = panels[i] if i < panels.size() else []
			if i < panels.size() and (group.is_empty() or float(p[0]) - float(group.back()[1]) < 1.2):
				group.append(p)
				continue
			if not group.is_empty():
				_wall_run(ctx, group, k, rect, corridor, district)
			group = [p] if i < panels.size() else []


static func _corridor_cells(chunk: CityChunk) -> Array:
	if chunk._yard_corridor.is_empty():
		return []
	return YardFill.corridor_block(chunk.plan, chunk.ix, chunk.iz, chunk._yard_corridor).cells


static func _wall_run(ctx: Dictionary, group: Array, k: Vector3i, rect: Rect2, corridor: Array, district: int) -> void:
	var chunk: CityChunk = ctx.chunk
	var plan: CityPlan = chunk.plan
	var along_x := k.x == 1
	var lo: float = group[0][0]
	var hi: float = group.back()[1]
	var total := hi - lo
	if total < MIN_WALL_LEN:
		return
	var c0: Vector3 = group[0][2]
	var s0: Vector3 = group[0][3]
	var line := c0.z if along_x else c0.x
	var mid2 := Vector2((lo + hi) * 0.5, line) if along_x else Vector2(line, (lo + hi) * 0.5)
	if not _ok(ctx, mid2):
		return
	var key := [plan.seed, "mural_wall", k.x, k.y, k.z, roundi(lo * 2.0)]
	if _h01(key) >= float(WALL_ODDS[district]):
		return
	# The side the public sees: a sound wall's right of way; any other wall's street side (the
	# side nearer the block's edge).
	var n2 := Vector2(0, 1) if along_x else Vector2(1, 0)
	var half := (s0.z if along_x else s0.x) * 0.5
	var probe_a := mid2 + n2 * (half + 1.0)
	var probe_b := mid2 - n2 * (half + 1.0)
	var side := 1.0
	if k.z == YardFill.W_SOUND and not corridor.is_empty():
		var in_a := false
		for r: Rect2 in corridor:
			if r.has_point(probe_a):
				in_a = true
		side = 1.0 if in_a else -1.0
	else:
		var inner := rect.grow(-CityChunk.SIDEWALK_TOP)
		var da := minf(minf(probe_a.x - inner.position.x, inner.end.x - probe_a.x), minf(probe_a.y - inner.position.y, inner.end.y - probe_a.y))
		var db := minf(minf(probe_b.x - inner.position.x, inner.end.x - probe_b.x), minf(probe_b.y - inner.position.y, inner.end.y - probe_b.y))
		side = 1.0 if da < db else -1.0
	var n := Vector3(n2.x, 0.0, n2.y) * side
	var right := Vector3.UP.cross(n)
	var sub := SUB_BLOCK if k.z == YardFill.W_SOUND else (SUB_BRICK if k.z == YardFill.W_BRICK else (SUB_CONCRETE if k.z == YardFill.W_CONCRETE else SUB_STUCCO))
	# One design over the whole run: u runs along `right`, so the run's start is the end `right`
	# points away from.
	var r_along := right.x if along_x else right.z
	var hgt := 1e9
	for p: Array in group:
		hgt = minf(hgt, float(p[4]))
	var h := minf(hgt - 0.45, MAX_MURAL_H)
	if h < 1.2:
		return
	var tall := total < h * 0.7
	var scene := _scene(district, _h01(key + ["scene"]), tall)
	var seed01 := _h01(key + ["seed"])
	var age := 0.1 + 0.6 * _h01(key + ["age"])
	var wear := int(_h01(key + ["wear"]) * 5.0)
	for p: Array in group:
		var c: Vector3 = p[2]
		var s: Vector3 = p[3]
		# Between the pilasters (a sound wall's panels butt into them at both ends).
		var inset := 0.3 if k.z == YardFill.W_SOUND else 0.12
		var a0 := float(p[0]) + inset
		var a1 := float(p[1]) - inset
		if a1 - a0 < 0.6:
			continue
		var bottom := c.y - s.y * 0.5 + (s.y - float(p[4])) + 0.25
		var cm := (a0 + a1) * 0.5
		var centre := Vector3(cm, bottom + h * 0.5, line) if along_x else Vector3(line, bottom + h * 0.5, cm)
		centre += n * ((s.z if along_x else s.x) * 0.5 + 0.012)
		var offset := (a0 - lo) if r_along > 0.0 else (hi - a1)
		_put(ctx, MODE_MURAL, scene, centre, _wall_basis(n, a1 - a0, h), seed01, offset, total, age, sub, wear)


# --- Freeway columns ---------------------------------------------------------------------------------

## The columns this chunk builds (StreetWear._pillars' frame: a bent every PILLAR_SPACING, two
## 1.6 m columns square to the route): a tall panel up the faces toward the streets alongside.
static func _pillars(ctx: Dictionary) -> void:
	var chunk: CityChunk = ctx.chunk
	var plan: CityPlan = chunk.plan
	var segs := chunk._freeway_segments()
	if segs.is_empty():
		return
	var area := chunk.owned_rect()
	var every := int(round(Freeway.PILLAR_SPACING / Freeway.STEP))
	for seg in segs:
		var a: Vector2 = seg.a
		var b: Vector2 = seg.b
		if a.distance_to(b) < 0.5 or not area.has_point(a.lerp(b, 0.5)) or int(seg.index) % every != 0:
			continue
		var ground := plan.height_at(a)
		var cap: float = float(seg.ha) - Freeway.DECK_THICKNESS - 0.1
		if cap - ground < 3.5:
			continue
		var district := int(plan.macro.district_at(a)) if plan.macro else 0
		var key := [plan.seed, "mural_bent", int(a.x * 10.0), int(a.y * 10.0)]
		if _h01(key) >= float(PILLAR_ODDS[clampi(district, 0, PILLAR_ODDS.size() - 1)]):
			continue
		if not _ok(ctx, a):
			continue
		var dir := (b - a).normalized()
		var nrm := Vector2(-dir.y, dir.x)
		var h := minf(cap - ground - 0.9, MAX_MURAL_H)
		var scene := _scene(district, _h01(key + ["scene"]), true)
		var seed01 := _h01(key + ["seed"])
		var age := 0.15 + 0.5 * _h01(key + ["age"])
		for side: float in [-1.0, 1.0]:
			var e := nrm * (float(seg.width) * 0.26) * side
			var p := Vector3(a.x + e.x, ground, a.y + e.y)
			# The two faces along the route (the streets beside the freeway see them).
			for f: float in [-1.0, 1.0]:
				var n := Vector3(dir.x, 0.0, dir.y) * f
				var c := p + n * 0.812 + Vector3(0.0, 0.5 + h * 0.5, 0.0)
				_put(ctx, MODE_MURAL, scene, c, _wall_basis(n, 1.5, h), seed01, 0.0, 1.5, age, SUB_CONCRETE, 2)


# --- Crosswalks ----------------------------------------------------------------------------------------

## The junction this chunk builds (ix + 1, iz + 1), if its district's rule paints crosswalks and
## it wins its roll: each of its four crosswalks painted, in strips that follow the relief.
static func _crosswalks(ctx: Dictionary, district: int) -> void:
	var chunk: CityChunk = ctx.chunk
	var plan: CityPlan = chunk.plan
	var rule := crosswalk_rule(plan, district)
	if rule < 0 or plan.junction_closed(chunk.ix + 1, chunk.iz + 1):
		return
	var inter := plan.intersection(chunk.ix + 1, chunk.iz + 1)
	var kind := int(inter.kind)
	if kind == CityPlan.Intersection.PLAIN or kind == CityPlan.Intersection.ROUNDABOUT:
		return
	var pos: Vector2 = inter.pos
	var size: Vector2 = inter.size
	if _h01([plan.seed, "mural_xwalk", chunk.ix + 1, chunk.iz + 1]) >= float(CROSSWALK_ODDS[district]) or not _ok(ctx, pos):
		return
	var seed01 := _h01([plan.seed, "mural_xwalk_seed", district])
	var age := 0.2 + 0.5 * _h01([plan.seed, "mural_xwalk_age", chunk.ix, chunk.iz])
	for side: float in [-1.0, 1.0]:
		# Across the x road (runs along x), at z = pos.y +- ...
		var z := pos.y + side * (size.y * 0.5 + 1.8)
		_crosswalk(ctx, Vector2(pos.x - size.x * 0.5, z), Vector2(1, 0), size.x, rule, seed01, age)
		var x := pos.x + side * (size.x * 0.5 + 1.8)
		_crosswalk(ctx, Vector2(x, pos.y - size.y * 0.5), Vector2(0, 1), size.y, rule, seed01, age)


static func _crosswalk(ctx: Dictionary, start: Vector2, along: Vector2, length: float, rule: int, seed01: float, age: float) -> void:
	var chunk: CityChunk = ctx.chunk
	var depth := 3.3
	var pieces := maxi(1, ceili(length / 4.0))
	var each := length / float(pieces)
	var ax := Vector3(along.x, 0.0, along.y)
	# x along the crossing, y across it, z up: x cross y must be up.
	var ay := Vector3(0.0, 0.0, -1.0) if along.x > 0.5 else Vector3(1.0, 0.0, 0.0)
	for i in pieces:
		var m := start + along * (each * (float(i) + 0.5))
		var gx := (chunk._gy(m.x + 1.0, m.y) - chunk._gy(m.x - 1.0, m.y)) * 0.5
		var gz := (chunk._gy(m.x, m.y + 1.0) - chunk._gy(m.x, m.y - 1.0)) * 0.5
		var up := Vector3(-gx, 1.0, -gz).normalized()
		var bx := (ax - up * ax.dot(up)).normalized()
		var by := up.cross(bx)
		if by.dot(ay) < 0.0:
			by = -by
		var centre := Vector3(m.x, CityChunk.ROAD_TOP + 0.03 + chunk._gy(m.x, m.y), m.y)
		_put(ctx, MODE_CROSSWALK, rule, centre, Basis(bx * (each + 0.01), by * depth, up * each), seed01, each * float(i), length,
			age, SUB_ASPHALT, 0)


# --- Signal cabinets -------------------------------------------------------------------------------------

static func _cabinets(ctx: Dictionary, district: int) -> void:
	var chunk: CityChunk = ctx.chunk
	var plan: CityPlan = chunk.plan
	var data: Dictionary = chunk._batch.data()
	for r: Dictionary in chunk.prop_records:
		if String(r.kind) != "signal_cabinet":
			continue
		var pos: Vector3 = r.position
		var key := [plan.seed, "mural_cabinet", int(pos.x * 10.0), int(pos.z * 10.0)]
		if _h01(key) >= float(CABINET_ODDS[district]) or not _ok(ctx, Vector2(pos.x, pos.z)):
			continue
		var inst: Array = r.instances[0]
		var xf: Transform3D = (data[inst[0]].xforms as Array)[inst[1]]
		var basis := xf.basis.orthonormalized()
		var scene := _scene(district, _h01(key + ["scene"]), true)
		var seed01 := _h01(key + ["seed"])
		var age := 0.3 * _h01(key + ["age"])
		var foot := pos
		for f: Array in cabinet_faces():
			var n: Vector3 = basis * (f[1] as Vector3)
			var index := _put(ctx, MODE_WRAP, scene, foot + basis * (f[0] as Vector3), _wall_basis(n, float(f[2]), float(f[3])), seed01, 0.0,
				float(f[2]), age, SUB_STEEL, 0)
			if index >= 0:
				(r.instances as Array).append([KEY, index])


# --- Mesh and material -------------------------------------------------------------------------------------

## The quad every instance is: x -0.5..0.5, y -0.5..0.5, facing +Z, UV 0..1 with v down.
static func mesh() -> Mesh:
	if _mesh:
		return _mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var quad := [Vector2(-0.5, -0.5), Vector2(0.5, 0.5), Vector2(0.5, -0.5), Vector2(-0.5, -0.5), Vector2(-0.5, 0.5), Vector2(0.5, 0.5)]
	for q: Vector2 in quad:
		st.set_color(Color.WHITE)
		st.set_normal(Vector3(0, 0, 1))
		st.set_tangent(Plane(1, 0, 0, 1))
		st.set_uv(Vector2(q.x + 0.5, 0.5 - q.y))
		st.add_vertex(Vector3(q.x, q.y, 0.0))
	st.index()
	st.set_material(material())
	_mesh = st.commit()
	_mesh.custom_aabb = AABB(Vector3(-0.55, -0.55, -0.1), Vector3(1.1, 1.1, 0.2))
	return _mesh


static func material() -> ShaderMaterial:
	if _material:
		return _material
	_material = ShaderMaterial.new()
	_material.shader = load("res://shaders/mural.gdshader")
	_material.set_shader_parameter("ghost_atlas", load("res://assets/textures/murals/ghost_signs.png"))
	_material.set_shader_parameter("use_screen", full_detail)
	_material.set_shader_parameter("fade_end", DRAW_DISTANCE)
	# Drawn before the street wear in the transparent pass, so tags lie on top of the paint.
	_material.render_priority = -1
	return _material
