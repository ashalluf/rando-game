class_name StreetWear
extends RefCounted
## Street-level wear (owner's roadmap, wave 6): the layer a Los Angeles street actually wears at
## eye level. Spray-painted tags - handstyles, bubble throw-ups, blocky roller letters - on the
## ground-floor walls, the bulkheads under the shop windows, the shop piers and the freeway
## columns, and the grey and beige buff-out rectangles where somebody painted over them (often
## with a fresh tag on top); wheat-paste posters pasted in rows and layered, the old ones torn;
## stickers on the lamp posts, signal poles, utility poles and signal cabinets, and flyers stapled
## round the wooden poles.
##
## All of it is ORIGINAL art, drawn by tools/make_street_wear.py into two atlases
## (assets/textures/street_wear/): abstract letterform scribbles (no real tag, crew or symbol),
## invented gigs, club nights, lost pets and hand bills, invented little emblems.
##
## How it is drawn: one strip mesh on one material (shaders/street_wear.gdshader), so a chunk's
## wear is ONE MultiMesh draw ("wear"), no shadows, faded out past DRAW_DISTANCE, FULL chunks only.
## Each instance is a quad a few millimetres proud of what it lies on, or bent round a pole by the
## vertex shader; see the shader header for the instance data. Transparent, drawn in instance
## order, so what is added later lies on top.
##
## Where: the walls come from the chunk's Building nodes - every ground-floor part face that is
## the first wall seen from the kerb of one of the block's four streets - and the window, door and
## sign-band layout is worked out exactly as shaders/building.gdshader draws it (its uniforms are
## read back off the part's material), so paint never lands on glass. Stickers ride the props they
## are on (hidden with them when the prop breaks). Freeway columns are found the way
## CityChunk._build_freeway() places them. How much: TAGS_PER_M and friends per CityPlan.District
## (most in INDUSTRIAL and DOWNTOWN, little in SUBURBS and CAMPUS), more on side streets than on
## avenues, and some streets far more than others. Never near a place of worship (WORSHIP_IDS).
##
## Seeding: nothing here touches the block's RandomNumberGenerator; every roll is a generator
## hashed from the seed and the block, face or prop. Same seed, same walls.
##
## Static: CityChunk runs build() as one build step of a FULL chunk.

# --- Tunables --------------------------------------------------------------------------------
# Never instanced (every entry point is static), so the knobs are consts here at the top.

## Tags per metre of visible ground-floor wall, by CityPlan.District
## (DOWNTOWN, MIDTOWN, SUBURBS, INDUSTRIAL, CAMPUS, BEACHTOWN).
const TAGS_PER_M := [0.055, 0.022, 0.004, 0.08, 0.006, 0.02]
## Wheat-paste poster runs per metre of wall.
const POSTERS_PER_M := [0.018, 0.008, 0.0008, 0.012, 0.004, 0.007]
## Stickers per pole (lamp, signal, utility) and per signal cabinet, on average.
const STICKERS_PER_POLE := [4.5, 2.2, 0.35, 3.0, 1.2, 2.2]
## Chance a freeway column face carries paint, by the district under it.
const PILLAR_ODDS := [0.8, 0.55, 0.3, 0.85, 0.35, 0.5]
## How a street's width scales it: side streets get the most, avenues less.
const SIDE_STREET := 1.6
const AVENUE := 0.7
## Share of tags that have been buffed over (a paint patch on top, sometimes re-tagged).
const BUFF_SHARE := 0.4
## Share of throw-ups (bubble letters) among the tags on a wall, and of roller letters.
const THROWUP_SHARE := 0.3
const ROLLER_SHARE := 0.08
## Metres of wall kept clear at each end of a block face (the corners).
const CORNER_CLEAR := 2.5
## How far behind the kerb a wall still counts as street frontage.
const MAX_SETBACK := 22.0
## Highest a hand reaches with a can (metres above the pavement).
const REACH := 2.7
## Most wear instances in one chunk.
const MAX_PER_CHUNK := 360
const DRAW_DISTANCE := 120.0
## Places of worship (Landmarks ids): nothing within their radius plus this margin.
const WORSHIP_IDS := ["masjid_omar"]
const WORSHIP_MARGIN := 40.0

const KEY := "wear"
const MODE_TAG := 0
const MODE_BUFF := 1
const MODE_POSTER := 2
const MODE_STICKER := 3
## Atlas cells (tools/make_street_wear.py): tags 0-7 handstyles, 8-13 throw-ups, 14-15 rollers;
## 16 posters; 32 stickers.
const HANDSTYLES := 8
const THROWUPS := Vector2i(8, 14)
const ROLLERS := Vector2i(14, 16)
const POSTERS := 16
const STICKERS := 32

## Tag colours (sRGB): black and silver most, then the brights.
const TAG_COLORS := [
	Color(0.05, 0.05, 0.06), Color(0.05, 0.05, 0.06), Color(0.05, 0.05, 0.06), Color(0.72, 0.73, 0.75),
	Color(0.72, 0.73, 0.75), Color(0.9, 0.9, 0.88), Color(0.66, 0.08, 0.07), Color(0.1, 0.18, 0.55),
	Color(0.85, 0.3, 0.58), Color(0.08, 0.34, 0.16), Color(0.88, 0.7, 0.1), Color(0.4, 0.66, 0.86),
]
## Throw-up fills (sRGB): chrome silver above all, white, and a few loud ones.
const FILL_COLORS := [
	Color(0.74, 0.75, 0.78), Color(0.74, 0.75, 0.78), Color(0.74, 0.75, 0.78), Color(0.92, 0.92, 0.9),
	Color(0.95, 0.82, 0.2), Color(0.45, 0.72, 0.92), Color(0.9, 0.45, 0.7), Color(0.9, 0.42, 0.1),
]
## Palette indices (the shader's PALETTE) for throw-up outlines: black mostly.
const OUTLINE_PAL := [0, 0, 0, 0, 3, 4, 8, 5]
## Buff paint: the colours building owners and the city roll over tags with.
const BUFF_COLORS := [
	Color(0.55, 0.54, 0.52), Color(0.62, 0.6, 0.56), Color(0.7, 0.65, 0.56), Color(0.48, 0.47, 0.46),
	Color(0.76, 0.72, 0.64), Color(0.58, 0.52, 0.46),
]

## Off: build() adds nothing (the "before" side of an A/B; STREET_WEAR=0 in the environment).
static var enabled: bool = OS.get_environment("STREET_WEAR") != "0"

static var _mesh: ArrayMesh = null
static var _material: ShaderMaterial = null


# --- Entry -------------------------------------------------------------------------------------

## The wear of one FULL chunk, as one build step: after everything it lies on is built.
static func build(chunk: CityChunk) -> void:
	if not enabled or chunk.level != CityChunk.Level.FULL or chunk.capturing:
		return
	var plan: CityPlan = chunk.plan
	var ctx := {"chunk": chunk, "count": 0, "points": [], "blocked": _worship_near(plan, chunk.owned_rect())}
	var block := plan.block(chunk.ix, chunk.iz)
	var district := int(block.district)
	if chunk.zone == MacroMap.Zone.CITY and not block.has("site"):
		var rect: Rect2 = block.rect
		var edges := CityChunk._sidewalk_edges(rect)
		if int(block.kind) == CityPlan.BlockKind.BUILDINGS:
			_walls(ctx, edges, district)
		_props(ctx, edges, district)
	_utility_poles(ctx, district)
	_pillars(ctx)
	if int(ctx.count) > 0:
		chunk._batch.set_no_shadow(KEY)
		chunk._batch.set_draw_distance(KEY, DRAW_DISTANCE)
	chunk.set_meta("street_wear", PackedVector2Array(ctx.points))


## Whether anything may be painted at `p` (chunk-local, which is true world XZ): not within a
## place of worship's radius plus WORSHIP_MARGIN.
static func allowed(p: Vector2) -> bool:
	for lm in Landmarks.all():
		if WORSHIP_IDS.has(lm.id) and p.distance_to(lm.anchor) < float(lm.radius) + WORSHIP_MARGIN:
			return false
	return true


static func _worship_near(_plan: CityPlan, rect: Rect2) -> Array:
	var out: Array = []
	for lm in Landmarks.all():
		if WORSHIP_IDS.has(lm.id):
			var r := float(lm.radius) + WORSHIP_MARGIN
			if rect.grow(r).has_point(lm.anchor):
				out.append([lm.anchor, r])
	return out


static func _ok(ctx: Dictionary, p: Vector2) -> bool:
	if int(ctx.count) >= MAX_PER_CHUNK:
		return false
	for b: Array in ctx.blocked:
		if p.distance_to(b[0]) < float(b[1]):
			return false
	return true


## One wear instance. `center` is chunk-local with its TRUE height (the batch adds the relief,
## so it is taken off here); `right` and `normal` are unit and horizontal-ish, `w` / `h` metres.
static func _put(ctx: Dictionary, mode: int, cell: int, center: Vector3, right: Vector3, normal: Vector3, w: float, h: float,
		color: Color, age: float, pal: int, tear: int, seed01: float, bend: float = 0.0, roll: float = 0.0) -> int:
	var chunk: CityChunk = ctx.chunk
	var up := Vector3.UP
	if roll != 0.0:
		right = right.rotated(normal, roll)
		up = up.rotated(normal, roll)
	var basis := Basis(right * w, up * h, normal * w)
	var at := center - Vector3(0.0, chunk._gy(center.x, center.z), 0.0)
	var custom := Color(float(mode * 100 + cell), seed01, bend, float(pal + 16 * clampi(tear, 0, 7)))
	var index := chunk._batch.add(KEY, mesh(), Transform3D(basis, at), Color(color.r, color.g, color.b, clampf(age, 0.0, 1.0)), custom)
	ctx.count = int(ctx.count) + 1
	(ctx.points as Array).append(Vector2(center.x, center.z))
	return index


static func _rng_for(parts: Array) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(parts)
	return rng


static func _hash01(parts: Array) -> float:
	return float(absi(hash(parts)) % 100000) / 100000.0


## How much a street is tagged: its width class, and a per-street roll (some streets are covered,
## the next is clean).
static func _street_factor(plan: CityPlan, axis: int, index: int) -> float:
	var f := AVENUE if plan.road_width(axis, index) > plan.street_width + 1.0 else SIDE_STREET
	return f * (0.3 + 1.5 * _hash01([plan.seed, "wear_street", axis, index]))


static func _poisson(rng: RandomNumberGenerator, mean: float) -> int:
	var n := int(mean)
	if rng.randf() < mean - float(n):
		n += 1
	return n


# --- Walls -------------------------------------------------------------------------------------

## The ground-floor faces a street sees: for each of the block's four kerbs, every Building part
## face turned to it, cut down to the stretches nothing nearer the kerb hides.
static func _walls(ctx: Dictionary, edges: Array, district: int) -> void:
	var chunk: CityChunk = ctx.chunk
	var plan: CityPlan = chunk.plan
	var parts := _ground_parts(chunk)
	if parts.is_empty():
		return
	var roads := [[CityPlan.AXIS_Z, chunk.iz], [CityPlan.AXIS_Z, chunk.iz + 1], [CityPlan.AXIS_X, chunk.ix], [CityPlan.AXIS_X, chunk.ix + 1]]
	for e in edges.size():
		var a: Vector2 = edges[e][0]
		var b: Vector2 = edges[e][1]
		var inward: Vector2 = edges[e][2]
		var length := a.distance_to(b)
		if length < 10.0:
			continue
		var dir := (b - a) / length
		var street := _street_factor(plan, roads[e][0], roads[e][1])
		# Each part's face toward this kerb: [depth, s0, s1, part].
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
			for piece: Vector2 in _subtract(Vector2(lo, hi), covered):
				if piece.y - piece.x > 1.2:
					_wall_run(ctx, f[3], Vector3(-inward.x, 0.0, -inward.y), a, dir, float(f[0]), inward, piece, district, street, e)
			covered.append(Vector2(float(f[1]), float(f[2])))


## The interval `iv` less every interval in `cut`.
static func _subtract(iv: Vector2, cut: Array) -> Array:
	var out: Array = [iv] if iv.y > iv.x else []
	for c: Vector2 in cut:
		var next: Array = []
		for p: Vector2 in out:
			if c.y <= p.x or c.x >= p.y:
				next.append(p)
				continue
			if c.x > p.x:
				next.append(Vector2(p.x, c.x))
			if c.y < p.y:
				next.append(Vector2(c.y, p.y))
		out = next
	return out


## Every ground-floor part of the chunk's (unturned) buildings, with what its shader draws.
static func _ground_parts(chunk: CityChunk) -> Array:
	var out: Array = []
	for c in chunk.get_children():
		var bld := c as Building
		if bld == null or absf(bld.rotation.y) > 0.001:
			continue
		for n in bld.get_children():
			var mi := n as MeshInstance3D
			if mi == null or not (mi.material_override is ShaderMaterial):
				continue
			var mat := mi.material_override as ShaderMaterial
			if mat.shader != Building.SHADER:
				continue
			var size: Vector3 = mat.get_shader_parameter("part_size")
			if mi.position.y - size.y * 0.5 > 0.05 or size.y < 2.5:
				continue
			var center := bld.position + mi.position
			out.append({
				"building": bld,
				"rect": Rect2(Vector2(center.x, center.z) - Vector2(size.x, size.z) * 0.5, Vector2(size.x, size.z)),
				"center": center,
				"size": size,
				"base": bld.position.y + mi.position.y - size.y * 0.5,
				"top": bld.position.y + mi.position.y + size.y * 0.5,
				"pitch_x": float(mat.get_shader_parameter("window_pitch_x")),
				"pitch_z": float(mat.get_shader_parameter("window_pitch_z")),
				"floor_h": float(mat.get_shader_parameter("floor_height")),
				"gfh": float(mat.get_shader_parameter("ground_floor_height")),
				"storefront": bool(mat.get_shader_parameter("has_storefront")),
				"style": int(bld.window_style),
				"spans": mat.get_shader_parameter("shop_span") as Vector4,
				"seed": float(mat.get_shader_parameter("seed")),
				"boxy": mi.mesh is BoxMesh,
				"warehouse": bld.shape == Building.Shape.WAREHOUSE,
				"facade": bld.facade_color,
			})
	return out


## The paint on one visible stretch of one wall: `piece` is the stretch in metres along the kerb
## (`a` + `dir` * s), the wall `depth` metres in from it, `n` its outward normal.
static func _wall_run(ctx: Dictionary, part: Dictionary, n: Vector3, a: Vector2, dir: Vector2, depth: float, inward: Vector2,
		piece: Vector2, district: int, street: float, edge: int) -> void:
	var chunk: CityChunk = ctx.chunk
	var plan: CityPlan = chunk.plan
	var rng := _rng_for([plan.seed, "wear_wall", chunk.ix, chunk.iz, edge, int(piece.x * 10.0), int(depth * 10.0)])
	var face := _face(part, n)
	var run := piece.y - piece.x
	var factor := street
	if part.warehouse:
		factor *= 1.8
	elif part.storefront:
		factor *= 0.8
	var right := Vector3.UP.cross(n)
	# From a point along the kerb to the wall face's (u, world point).
	var at_s := func(s: float, v: float) -> Vector3:
		var q := a + dir * s + inward * depth
		return Vector3(q.x, v, q.y) + n * 0.012
	var u_of := func(p: Vector3) -> float:
		return _u_on_face(part, face, p)
	# Tags, some buffed over, some tagged again on the buff.
	var tags := _poisson(rng, run * float(TAGS_PER_M[district]) * factor * rng.randf_range(0.5, 1.5))
	for i in tags:
		var roll := rng.randf()
		var kind := 0 if roll > THROWUP_SHARE + ROLLER_SHARE else (1 if roll > ROLLER_SHARE else 2)
		if kind == 2 and not (part.warehouse or district == CityPlan.District.INDUSTRIAL):
			kind = 1
		var w := rng.randf_range(0.7, 1.5) if kind == 0 else (rng.randf_range(1.2, 2.3) if kind == 1 else rng.randf_range(2.0, 3.6))
		var spot := _find_spot(rng, part, face, at_s, u_of, piece, w, w * 0.5, part.base + 0.2, part.base + REACH)
		if spot.is_empty():
			continue
		var c: Vector3 = spot[0]
		w = spot[1]
		if not _ok(ctx, Vector2(c.x, c.z)):
			return
		var h := w * 0.5
		var age := rng.randf() * rng.randf()
		if kind == 0:
			_put(ctx, MODE_TAG, rng.randi() % HANDSTYLES, c, right, n, w, h, TAG_COLORS[rng.randi() % TAG_COLORS.size()], age, 0, 0, rng.randf())
		elif kind == 1:
			_put(ctx, MODE_TAG, rng.randi_range(THROWUPS.x, THROWUPS.y - 1), c, right, n, w, h, FILL_COLORS[rng.randi() % FILL_COLORS.size()], age, OUTLINE_PAL[rng.randi() % OUTLINE_PAL.size()], 0, rng.randf())
		else:
			_put(ctx, MODE_TAG, rng.randi_range(ROLLERS.x, ROLLERS.y - 1), c, right, n, w, h, TAG_COLORS[rng.randi() % TAG_COLORS.size()], age, 0, 0, rng.randf())
		if rng.randf() < BUFF_SHARE:
			# The buff: over the tag, a size up, in a paint that nearly matches the wall.
			var bw := w * rng.randf_range(1.05, 1.3)
			var bh := h * rng.randf_range(1.1, 1.6)
			var off := Vector3(0.0, rng.randf_range(-0.08, 0.08), 0.0) + right * rng.randf_range(-0.1, 0.1)
			var paint: Color = (part.facade as Color).lerp(BUFF_COLORS[rng.randi() % BUFF_COLORS.size()], rng.randf_range(0.35, 0.8))
			var bc: Vector3 = c + off + n * 0.002
			if _rect_clear(part, face, u_of, bc, right, bw, bh):
				_put(ctx, MODE_BUFF, 0, bc, right, n, bw, bh, paint, 0.0, 0, 0, rng.randf())
				if rng.randf() < 0.35:
					var tw := minf(bw * 0.8, rng.randf_range(0.6, 1.1))
					_put(ctx, MODE_TAG, rng.randi() % HANDSTYLES, bc + n * 0.002 + right * rng.randf_range(-0.1, 0.1), right, n, tw, tw * 0.5, TAG_COLORS[rng.randi() % TAG_COLORS.size()], 0.0, 0, 0, rng.randf())
	# Wheat-paste: on the shop piers, or a run on a bare stretch of wall.
	var posters := _poisson(rng, run * float(POSTERS_PER_M[district]) * factor * rng.randf_range(0.5, 1.5))
	var piers: Array = _piers(part, face) if part.storefront else []
	for i in posters:
		if not piers.is_empty() and rng.randf() < 0.7:
			var pu: float = piers[rng.randi() % piers.size()]
			var p := _face_point(part, face, pu, 0.0)
			var s := (Vector2(p.x, p.z) - a).dot(dir)
			if s < piece.x or s > piece.y:
				continue
			var bottom: float = float(part.base) + rng.randf_range(0.8, 1.2)
			_paste(ctx, rng, Vector3(p.x, 0.0, p.z) + n * 0.395, right, n, 1, rng.randi_range(1, 3), bottom, 0.44, part.base + (part.gfh - part.base) * 0.6)
		else:
			var cols := rng.randi_range(1, 4)
			var pw := 0.46
			var rows := 1 + int(rng.randf() < 0.3)
			var spot := _find_spot(rng, part, face, at_s, u_of, piece, pw * cols + 0.1, 0.62 * rows + 0.1, part.base + 0.7, part.base + 2.6)
			if spot.is_empty():
				continue
			var c: Vector3 = spot[0]
			cols = maxi(1, int((float(spot[1]) - 0.1) / pw))
			_paste(ctx, rng, Vector3(c.x, 0.0, c.z), right, n, cols, rows, c.y - (0.62 * rows) * 0.5, pw, 99.0)


## A wheat-paste run: an older torn layer, then a grid of `cols` x `rows` posters (often one
## poster repeated along the row), their bottom edge at `bottom`, centred on `center` (x, z).
static func _paste(ctx: Dictionary, rng: RandomNumberGenerator, center: Vector3, right: Vector3, n: Vector3, cols: int, rows: int,
		bottom: float, pw: float, top_limit: float) -> void:
	var ph := pw * 1.5
	if bottom + ph * rows > top_limit:
		rows = maxi(1, int((top_limit - bottom) / ph))
		if bottom + ph > top_limit:
			return
	if not _ok(ctx, Vector2(center.x, center.z)):
		return
	var width := pw * cols
	# The layer under: two or three old posters, torn half away.
	for k in rng.randi_range(1, 3):
		var off := right * rng.randf_range(-width * 0.4, width * 0.4) + Vector3(0.0, rng.randf_range(-0.1, 0.25), 0.0)
		var c := center + off + Vector3(0.0, bottom + ph * 0.5, 0.0)
		_put(ctx, MODE_POSTER, rng.randi() % POSTERS, c, right, n, pw, ph, Color.WHITE, rng.randf_range(0.4, 0.9), 0, rng.randi_range(3, 7), rng.randf(), 0.0, rng.randf_range(-0.03, 0.03))
	var repeat := rng.randf() < 0.6
	var cell := rng.randi() % POSTERS
	var age := rng.randf() * 0.5
	for r in rows:
		for k in cols:
			var c := center + right * ((float(k) - float(cols - 1) * 0.5) * pw * 1.01) + Vector3(0.0, bottom + ph * (float(r) + 0.5) * 1.01, 0.0) + n * 0.003
			var which := cell if repeat else rng.randi() % POSTERS
			var tear := 0 if rng.randf() < 0.55 else rng.randi_range(1, 5)
			_put(ctx, MODE_POSTER, which, c, right, n, pw, ph, Color.WHITE, age + rng.randf() * 0.15, 0, tear, rng.randf(), 0.0, rng.randf_range(-0.012, 0.012))


## A place on the wall for a w x h rectangle between v_lo and v_hi (world heights) on the kerb
## stretch `piece`, clear of every window, door and sign band: [centre, width] or [] after a few
## tries (each smaller than the last).
static func _find_spot(rng: RandomNumberGenerator, part: Dictionary, face: int, at_s: Callable, u_of: Callable, piece: Vector2,
		w: float, h: float, v_lo: float, v_hi: float) -> Array:
	var right := Vector3.UP.cross(_normal(face))
	for attempt in 7:
		var ww := w * pow(0.85, attempt)
		var hh := h * pow(0.85, attempt)
		if piece.y - piece.x < ww + 0.2 or v_hi - v_lo < hh:
			continue
		var s := rng.randf_range(piece.x + ww * 0.5 + 0.1, piece.y - ww * 0.5 - 0.1)
		var v := rng.randf_range(v_lo + hh * 0.5, v_hi - hh * 0.5)
		if rng.randf() < 0.6:
			# Most tags sit low, at the height of an arm swinging a can.
			v = minf(v, v_lo + hh * 0.5 + rng.randf_range(0.0, 0.9))
		var c: Vector3 = at_s.call(s, v)
		if _rect_clear(part, face, u_of, c, right, ww, hh):
			return [c, ww]
	return []


## True when every sample of the w x h rectangle centred on `c` is paintable wall.
static func _rect_clear(part: Dictionary, face: int, u_of: Callable, c: Vector3, right: Vector3, w: float, h: float) -> bool:
	for i in 5:
		for j in 4:
			var p := c + right * ((float(i) / 4.0 - 0.5) * w) + Vector3(0.0, (float(j) / 3.0 - 0.5) * h, 0.0)
			if not _paintable(part, face, u_of.call(p), p.y):
				return false
	return true


# --- The wall as building.gdshader draws it -----------------------------------------------------

## Face index 0..3 (+X, -X, +Z, -Z), which is the shader's face_id - 1.
static func _face(_part: Dictionary, n: Vector3) -> int:
	if n.x > 0.5:
		return 0
	if n.x < -0.5:
		return 1
	return 2 if n.z > 0.5 else 3


static func _normal(face: int) -> Vector3:
	return [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)][face]


## The shader's `u` along a face for a world point on it.
static func _u_on_face(part: Dictionary, face: int, p: Vector3) -> float:
	var size: Vector3 = part.size
	var l: Vector3 = p - (part.center as Vector3)
	match face:
		0: return l.z + size.z * 0.5
		1: return -l.z + size.z * 0.5
		2: return -l.x + size.x * 0.5
		_: return l.x + size.x * 0.5


## The world point on a face at shader `u` and height `v`.
static func _face_point(part: Dictionary, face: int, u: float, v: float) -> Vector3:
	var size: Vector3 = part.size
	var c: Vector3 = part.center
	match face:
		0: return Vector3(c.x + size.x * 0.5, v, c.z + u - size.z * 0.5)
		1: return Vector3(c.x - size.x * 0.5, v, c.z + size.z * 0.5 - u)
		2: return Vector3(c.x + size.x * 0.5 - u, v, c.z + size.z * 0.5)
		_: return Vector3(c.x + u - size.x * 0.5, v, c.z - size.z * 0.5)


## Where along a storefront face the piers between shops stand (Building._add_facade_details:
## a pier every `shop_span` bays, measured from the same end as the shader's u).
static func _piers(part: Dictionary, face: int) -> Array:
	var along_x := face >= 2
	var size_u: float = (part.size as Vector3).x if along_x else (part.size as Vector3).z
	var pitch: float = part.pitch_x if along_x else part.pitch_z
	var cols := maxi(1, roundi(size_u / pitch))
	var span: float = maxf((part.spans as Vector4)[face], 1.0)
	var cut: float = 0.0 if part.boxy else pitch
	var out: Array = []
	var k := 0
	while float(k) * span <= float(cols) + 0.01:
		var u := minf(float(k) * span, float(cols)) * pitch
		if u > cut + 0.4 and u < size_u - cut - 0.4:
			out.append(u)
		k += 1
	return out


## float32 arithmetic, so hash21 below comes out as the GPU computes it.
static func _f(x: float) -> float:
	var a := PackedFloat32Array([x])
	return a[0]


static func _fract(x: float) -> float:
	return _f(x - floorf(x))


## building.gdshader's hash21, in float32.
static func _hash21(p: Vector2) -> float:
	var x := _fract(_f(p.x * _f(123.34)))
	var y := _fract(_f(p.y * _f(456.21)))
	var d := _f(_f(x * _f(x + _f(45.32))) + _f(y * _f(y + _f(45.32))))
	x = _f(x + d)
	y = _f(y + d)
	return _fract(_f(x * y))


## Whether the shader draws plain wall at (u, v) on this face: not glass, not a door, not the
## shop sign band, not a cut corner. Margins keep paint off the window frames and surrounds.
static func _paintable(part: Dictionary, face: int, u: float, v: float) -> bool:
	var along_x := face >= 2
	var size_u: float = (part.size as Vector3).x if along_x else (part.size as Vector3).z
	var pitch: float = part.pitch_x if along_x else part.pitch_z
	var cut: float = 0.0 if part.boxy else pitch
	if u < cut + 0.15 or u > size_u - cut - 0.15 or v < float(part.base) + 0.06 or v > float(part.top) - 0.5:
		return false
	var col := floorf(u / pitch)
	var fu := u / pitch - col
	var mu := 0.14 / pitch
	if part.storefront and v < float(part.gfh):
		var fv := v / float(part.gfh)
		if fv > 0.72:
			return false
		var face_id := float(face + 1)
		var span: float = maxf((part.spans as Vector4)[face], 1.0)
		var shop_id := floorf(col / span)
		var shop_seed := _hash21(Vector2(_f(shop_id * 1.7) + float(part.seed), _f(face_id * 13.0) + float(part.seed)))
		var door := absf(col - (shop_id * span + floorf(shop_seed * span))) < 0.5
		var low := 0.05 if door else 0.15
		# Door bays count as glass to the pavement whatever the hash says, a hair either way.
		if door:
			low = 0.0
		var mv := 0.1 / float(part.gfh)
		if fv > low - mv and absf(fu - 0.5) < 0.44 + mu:
			return false
		# Not across a pier between shops (it stands in front of the wall).
		var su := u / (span * pitch)
		if absf(su - roundf(su)) * span * pitch < 0.35:
			return false
		return true
	var fh: float = part.floor_h
	var vv := v - float(part.gfh)
	var fv2 := vv / fh - floorf(vv / fh)
	var mv2 := 0.16 / fh
	match int(part.style):
		0:
			return not (absf(fu - 0.5) < 0.27 + mu and absf(fv2 - 0.52) < 0.25 + mv2)
		1:
			return not (absf(fv2 - 0.55) < 0.27 + mv2)
		2:
			return false
		_:
			return not (absf(fu - 0.5) < 0.16 + mu and absf(fv2 - 0.5) < 0.40 + mv2)


# --- Poles, cabinets, freeway columns ----------------------------------------------------------

## Stickers and flyers on the lamp posts and signal poles, stickers and a tag on the signal
## cabinets. Each is added to its prop's record, so it goes when the prop is knocked down.
static func _props(ctx: Dictionary, edges: Array, district: int) -> void:
	var chunk: CityChunk = ctx.chunk
	var plan: CityPlan = chunk.plan
	var data: Dictionary = chunk._batch.data()
	var mean := float(STICKERS_PER_POLE[district])
	for r: Dictionary in chunk.prop_records:
		var kind := String(r.kind)
		if kind != "lamp" and kind != "signal" and kind != "signal_cabinet":
			continue
		var pos: Vector3 = r.position
		var p2 := Vector2(pos.x, pos.z)
		if not _ok(ctx, p2):
			continue
		var rng := _rng_for([plan.seed, "wear_prop", int(pos.x * 10.0), int(pos.z * 10.0)])
		var added: Array = []
		if kind == "signal_cabinet":
			var inst: Array = r.instances[0]
			var xf: Transform3D = (data[inst[0]].xforms as Array)[inst[1]]
			added = _cabinet(ctx, rng, pos, xf.basis.orthonormalized(), mean)
		else:
			var radius := func(y: float) -> float:
				return 0.098 - 0.0152 * y if kind == "lamp" else 0.168 - 0.05 * (y - 0.44) / 7.1
			added = _pole(ctx, rng, pos, radius, mean * rng.randf_range(0.4, 1.6), kind == "lamp")
		for index: int in added:
			(r.instances as Array).append([KEY, index])


## Stickers (and now and then a flyer or a small tag) round a pole whose foot is at `foot` (true
## height) and whose radius at a height above the foot is `radius`.
static func _pole(ctx: Dictionary, rng: RandomNumberGenerator, foot: Vector3, radius: Callable, mean: float, flyers: bool) -> Array:
	var out: Array = []
	var n := _poisson(rng, mean)
	for i in n:
		var y := rng.randf_range(0.9, 2.1)
		var r: float = radius.call(y) + 0.002
		var ang := rng.randf() * TAU
		var nrm := Vector3(sin(ang), 0.0, cos(ang))
		var right := Vector3.UP.cross(nrm)
		var w := rng.randf_range(0.07, 0.12)
		var c := foot + Vector3(0.0, y, 0.0) + nrm * r
		out.append(_put(ctx, MODE_STICKER, rng.randi() % STICKERS, c, right, nrm, w, w, Color.WHITE, rng.randf() * 0.8, 0,
			0 if rng.randf() < 0.7 else rng.randi_range(2, 6), rng.randf(), w / r, rng.randf_range(-0.5, 0.5)))
	if flyers and rng.randf() < 0.25 * mean:
		var y := rng.randf_range(1.3, 1.7)
		var r: float = radius.call(y) + 0.004
		var ang := rng.randf() * TAU
		var nrm := Vector3(sin(ang), 0.0, cos(ang))
		var w := 0.2
		out.append(_put(ctx, MODE_POSTER, rng.randi() % POSTERS, foot + Vector3(0.0, y, 0.0) + nrm * r, Vector3.UP.cross(nrm), nrm, w, w * 1.5,
			Color.WHITE, rng.randf() * 0.7, 0, rng.randi_range(0, 5), rng.randf(), w / r))
	return out


## The signal controller cabinet (0.78 x 1.44 x 0.52 m on a 0.12 m pad, door toward local +z).
static func _cabinet(ctx: Dictionary, rng: RandomNumberGenerator, foot: Vector3, basis: Basis, mean: float) -> Array:
	var out: Array = []
	# Faces: [centre offset in the cabinet's frame, normal, width].
	var faces := [
		[Vector3(0.0, 0.84, 0.262), Vector3(0, 0, 1), 0.78], [Vector3(0.0, 0.84, -0.262), Vector3(0, 0, -1), 0.78],
		[Vector3(0.392, 0.84, 0.0), Vector3(1, 0, 0), 0.52], [Vector3(-0.392, 0.84, 0.0), Vector3(-1, 0, 0), 0.52],
	]
	for i in _poisson(rng, mean * 1.5):
		var f: Array = faces[rng.randi() % faces.size()]
		var nrm: Vector3 = basis * (f[1] as Vector3)
		var right := Vector3.UP.cross(nrm)
		var w := rng.randf_range(0.07, 0.13)
		var along := rng.randf_range(-0.5, 0.5) * (float(f[2]) - w - 0.04)
		var c := foot + basis * (f[0] as Vector3) + right * along + Vector3(0.0, rng.randf_range(-0.5, 0.6), 0.0) + nrm * 0.004
		out.append(_put(ctx, MODE_STICKER, rng.randi() % STICKERS, c, right, nrm, w, w, Color.WHITE, rng.randf() * 0.7, 0,
			0 if rng.randf() < 0.7 else rng.randi_range(2, 6), rng.randf(), 0.0, rng.randf_range(-0.4, 0.4)))
	if rng.randf() < mean * 0.15:
		var f: Array = faces[2 + rng.randi() % 2]
		var nrm: Vector3 = basis * (f[1] as Vector3)
		var w := 0.46
		out.append(_put(ctx, MODE_TAG, rng.randi() % HANDSTYLES, foot + basis * (f[0] as Vector3) + Vector3(0.0, rng.randf_range(-0.2, 0.3), 0.0) + nrm * 0.006,
			Vector3.UP.cross(nrm), nrm, w, w * 0.5, TAG_COLORS[rng.randi() % TAG_COLORS.size()], rng.randf() * 0.5, 0, 0, rng.randf()))
	return out


## Flyers stapled round the wooden utility poles (StreetDetail's "upole" batch), layered, and
## stickers. The poles are not props, so these stay with them.
static func _utility_poles(ctx: Dictionary, district: int) -> void:
	var chunk: CityChunk = ctx.chunk
	var data: Dictionary = chunk._batch.data()
	if not data.has("upole"):
		return
	var mean := float(STICKERS_PER_POLE[district])
	for xf: Transform3D in data["upole"].xforms:
		var foot := Vector3(xf.origin.x, xf.origin.y - StreetDetail.POLE_HEIGHT * 0.5, xf.origin.z)
		if not _ok(ctx, Vector2(foot.x, foot.z)):
			continue
		var rng := _rng_for([chunk.plan.seed, "wear_upole", int(foot.x * 10.0), int(foot.z * 10.0)])
		var radius := func(y: float) -> float: return 0.16 - 0.03 * y / StreetDetail.POLE_HEIGHT
		_pole(ctx, rng, foot, radius, mean * 0.6, false)
		# Layers of flyers, the oldest torn to scraps.
		var layers := _poisson(rng, mean * 0.5)
		var ang := rng.randf() * TAU
		for k in layers:
			var y := rng.randf_range(1.2, 1.9)
			var r: float = radius.call(y) + 0.003 + 0.002 * k
			var a := ang + rng.randf_range(-0.6, 0.6)
			var nrm := Vector3(sin(a), 0.0, cos(a))
			var w := rng.randf_range(0.2, 0.28)
			_put(ctx, MODE_POSTER, rng.randi() % POSTERS, foot + Vector3(0.0, y, 0.0) + nrm * r, Vector3.UP.cross(nrm), nrm, w, w * 1.45,
				Color.WHITE, rng.randf() * 0.9, 0, 0 if k == layers - 1 and rng.randf() < 0.5 else rng.randi_range(2, 7), rng.randf(), w / r, rng.randf_range(-0.06, 0.06))
		if rng.randf() < 0.3:
			var y := rng.randf_range(1.6, 2.4)
			var r: float = radius.call(y) + 0.01
			var a := rng.randf() * TAU
			var nrm := Vector3(sin(a), 0.0, cos(a))
			var w := 0.4
			_put(ctx, MODE_TAG, rng.randi() % HANDSTYLES, foot + Vector3(0.0, y, 0.0) + nrm * r, Vector3.UP.cross(nrm), nrm, w, w * 0.5,
				TAG_COLORS[rng.randi() % TAG_COLORS.size()], rng.randf() * 0.5, 0, 0, rng.randf(), w / r)


## The freeway columns this chunk builds (the same test as CityChunk._build_freeway: a segment
## belongs to the chunk its midpoint is in, a bent every PILLAR_SPACING, 1.6 x 1.6 m columns at
## +-0.26 of the deck width): big tags, buffs in unmatched grey, and posters, on their faces.
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
		var dir := (b - a).normalized()
		var nrm := Vector2(-dir.y, dir.x)
		var district := int(plan.macro.district_at(a)) if plan.macro else 0
		var odds := float(PILLAR_ODDS[clampi(district, 0, PILLAR_ODDS.size() - 1)])
		for side: float in [-1.0, 1.0]:
			var e := nrm * (float(seg.width) * 0.26) * side
			var p := Vector3(a.x + e.x, ground, a.y + e.y)
			if not _ok(ctx, Vector2(p.x, p.z)):
				continue
			var rng := _rng_for([plan.seed, "wear_pillar", int(p.x * 10.0), int(p.z * 10.0)])
			var w3 := Vector3(nrm.x, 0.0, nrm.y) * 0.8
			var corners := [p - Vector3(0.8, 0, 0) - w3, p - Vector3(0.8, 0, 0) + w3, p + Vector3(0.8, 0, 0) + w3, p + Vector3(0.8, 0, 0) - w3]
			for i in 4:
				if rng.randf() > odds:
					continue
				var c0: Vector3 = corners[i]
				var c1: Vector3 = corners[(i + 1) % 4]
				var along := c1 - c0
				var fw := along.length()
				var right := along / fw
				var out := Vector3(right.z, 0.0, -right.x)
				var mid := (c0 + c1) * 0.5
				if out.dot(mid - p) < 0.0:
					out = -out
					right = -right
				mid += out * 0.012
				var kind := rng.randf()
				var w := minf(fw - 0.12, rng.randf_range(1.0, 1.5))
				var cell := rng.randi_range(THROWUPS.x, ROLLERS.y - 1) if kind < 0.45 else rng.randi() % HANDSTYLES
				var fill: Color = FILL_COLORS[rng.randi() % FILL_COLORS.size()] if cell >= THROWUPS.x and cell < THROWUPS.y else TAG_COLORS[rng.randi() % TAG_COLORS.size()]
				var c := mid + Vector3(0.0, rng.randf_range(0.5, 1.8) + w * 0.25, 0.0)
				var concrete := Color(0.58, 0.57, 0.55)
				if rng.randf() < 0.45:
					# Buffed before: an old grey patch, and the new tag on it.
					var bw := minf(fw - 0.06, w * 1.2)
					_put(ctx, MODE_BUFF, 0, c + Vector3(0.0, rng.randf_range(-0.1, 0.2), 0.0), right, out, bw, rng.randf_range(0.9, 2.2),
						concrete.lerp(BUFF_COLORS[rng.randi() % BUFF_COLORS.size()], rng.randf_range(0.4, 0.9)), 0.0, 0, 0, rng.randf())
				if rng.randf() < 0.85:
					_put(ctx, MODE_TAG, cell, c + out * 0.003, right, out, w, w * 0.5, fill, rng.randf() * 0.6, OUTLINE_PAL[rng.randi() % OUTLINE_PAL.size()], 0, rng.randf())
				if rng.randf() < 0.25:
					var pw := 0.44
					var cols := 1 if fw < 1.2 else rng.randi_range(1, 3)
					_paste(ctx, rng, Vector3(mid.x, 0.0, mid.z) + out * 0.006, right, out, cols, 1, ground + rng.randf_range(0.9, 1.3), pw, ground + 3.0)


# --- Mesh and material -------------------------------------------------------------------------

## The one strip every instance is: x -0.5..0.5 in STRIP_COLUMNS columns (so it can bend round a
## pole), y -0.5..0.5, facing +Z, UV 0..1 with v down.
const STRIP_COLUMNS := 8


static func mesh() -> Mesh:
	if _mesh:
		return _mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in STRIP_COLUMNS:
		var x0 := float(i) / STRIP_COLUMNS - 0.5
		var x1 := float(i + 1) / STRIP_COLUMNS - 0.5
		# Clockwise seen from +Z: Godot's front face.
		var quad := [Vector2(x0, -0.5), Vector2(x1, 0.5), Vector2(x1, -0.5), Vector2(x0, -0.5), Vector2(x0, 0.5), Vector2(x1, 0.5)]
		for q: Vector2 in quad:
			st.set_color(Color.WHITE)
			st.set_normal(Vector3(0, 0, 1))
			st.set_tangent(Plane(1, 0, 0, 1))
			st.set_uv(Vector2(q.x + 0.5, 0.5 - q.y))
			st.add_vertex(Vector3(q.x, q.y, 0.0))
	st.index()
	st.set_material(material())
	_mesh = st.commit()
	# Instances bend out to a whole turn round a pole: keep the bounds generous.
	_mesh.custom_aabb = AABB(Vector3(-0.6, -0.6, -1.2), Vector3(1.2, 1.2, 1.4))
	return _mesh


static func material() -> ShaderMaterial:
	if _material:
		return _material
	_material = ShaderMaterial.new()
	_material.shader = load("res://shaders/street_wear.gdshader")
	_material.set_shader_parameter("tag_atlas", load("res://assets/textures/street_wear/street_wear_tags.png"))
	_material.set_shader_parameter("paper_atlas", load("res://assets/textures/street_wear/street_wear_paper.png"))
	_material.set_shader_parameter("use_screen", true)
	return _material
