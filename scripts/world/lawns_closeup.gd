class_name LawnsCloseup
extends RefCounted
## Lawns close up (2026-10-30, fleet wave 3 "lawns-closeup", docs/HANDOFF.md "Lawns close up"):
## ground planting at 1-30 m as a 2026 game draws it.
##   * ONE field for the lawn and its blades (shaders/lawn_field.gdshaderinc): the ground
##     (lawn.gdshader) and every blade (grass.gdshader) take watered / parched, clover, brown
##     spots, worn dirt, mower stripes and the morning's sprinklers from the same functions of
##     true world XZ and the lawn's own numbers, which each tuft carries in its instance data
##     (tuft_data()). A blade over a dry patch is straw and shorter, over clover low and bluer,
##     over a worn patch flattened into the dirt, and it has the colour of the ground under it -
##     so the blades shrink away into the lawn between 26 and 62 m (the shader) with no band, and
##     the grass cells stop drawing at GRASS_DISTANCE instead of 115 m (blades there were a tenth
##     of a pixel wide: aliasing, not grass).
##   * Blade-level variety: every blade its own height and shade, some tips burnt, some young and
##     blue-green; the fringe along a lawn's edge stands taller (uncut against the concrete). The
##     tuft is blade_mesh(): the same blades as PropFactory.grass_blade() from the same stream,
##     its UV.x the blade's place in the tuft, its normals per ring and its vertices indexed (2.4x
##     fewer vertex-shader runs for the same triangles).
##   * The lawn shader up close: clover trefoils, straw thatch in the dry patches, the edge along
##     the pavement (an edged soil line or overgrown grass lapping it, a hash of the lawn), the
##     sprinklers' wet throw in the morning, darker thatch between the blades near the camera.
##   * Grass parkways (parkway()): the planted strip between the kerb and the walk that every LA
##     suburban street has, on SUBURBS blocks, cut round the corners and the driveway aprons (the
##     very drives Kerbs cuts), ONE relief-following mesh a chunk with its own blades.
##   * Weeds where nobody mows: tufts and rosettes at the pavement's slab joints by the lawn and
##     along the foot of the yards' fences and walls (weeds()).
## Every roll is a hash of seed + place (the grass's own streams are unchanged). `LAWNS_CLOSEUP=0`
## in the environment is the A/B: the `lawns_closeup` global goes to 0 (both shaders take their
## old paths), the old tuft mesh, no parkways or weeds, grass_distance as it was.
## Checks: tests/lawns_closeup_checks.gd; stills tools/lawns_closeup/shots.sh; probe
## tools/lawns_closeup/probe.gd.

static var enabled: bool = OS.get_environment("LAWNS_CLOSEUP") != "0"

## How many more tufts a lawn gets with the pass on: the close-up tuft is mown and spread, so it
## takes more of them to make turf; paid for by the shorter GRASS_DISTANCE (the area drawn falls
## to 56 %; 1.4 x 0.56 keeps a lawn-heavy frame within a few per cent).
const DENSITY_GAIN := 1.4

## How far a grass cell keeps drawing (metres to its centre) with the close-up pass on. The
## blades are gone by grass.gdshader's fade_end (62 m) and a cell's farthest corner is 22.6 m
## from its centre, so nothing drawn is lost.
const GRASS_DISTANCE := 86.0
## grass.gdshader's fade (mirrored; the checks read the shader).
const FADE_START := 26.0
const FADE_END := 62.0
## The parkway: from the kerb line in, where the grass starts and ends (metres). The kerb's own
## top stays concrete (its paint, its numbers); the walk behind is the rest of the pavement.
const PARKWAY_FROM := 0.22
const PARKWAY_TO := 1.95
## Clear of each corner (the ramps, the crosswalks, the signal or stop pole) and of a drive's
## apron and flares either side (Kerbs.DR_FLARE plus a little).
const PARKWAY_CORNER := 5.4
const PARKWAY_DRIVE_PAD := 0.85
## Parkway pieces shorter than this are left as concrete (a sliver between two drives).
const PARKWAY_MIN := 2.4
## How densely the parkway grows blades, against a lawn's 1.0.
const PARKWAY_DENSITY := 0.75
## Districts with grass parkways.
const PARKWAY_DISTRICTS := [CityPlan.District.SUBURBS]
## The grid step of the parkway mesh along the kerb (metres): it follows the relief like the ring.
const PARKWAY_STEP := 2.0
## Weeds: per metre of pavement joint by a lawn, and per metre of fence or wall foot.
const WEED_JOINT_ODDS := 0.16
const WEED_FENCE_PER_M := 0.55
const WEED_DRAW := 45.0
const MAX_WEEDS := 900
## lf_sprinkler_hours() in the include (mirrored; the checks compare).
const SPRINKLER_ON := Vector2(4.6, 5.4)
const SPRINKLER_OFF := Vector2(8.2, 10.4)

## The close-up tuft's blades: their height against the old tuft's, and the disc they spread over.
const MOWN := 0.75
const SPREAD := 0.24

static var _installed := false
static var _blade: Mesh
static var _weeds: Array = []


## Pushes the switch to the shaders (from PropFactory.lawn() and the first grass): the global is
## 1 in project.godot, so only "off" has to be said, and it is said before any lawn is drawn.
static func install() -> void:
	if _installed:
		return
	_installed = true
	RenderingServer.global_shader_parameter_set("lawns_closeup", 1.0 if enabled else 0.0)


## Turns the pass on or off at once (tests): the shaders now, the placement for chunks built next.
static func set_enabled(on: bool) -> void:
	enabled = on
	_installed = false
	install()


## Mirror of lf_sprinkler_hours(): how much of the morning's watering is on the grass at `h`.
static func sprinkler_hours(h: float) -> float:
	return smoothstep(SPRINKLER_ON.x, SPRINKLER_ON.y, h) * (1.0 - smoothstep(SPRINKLER_OFF.x, SPRINKLER_OFF.y, h))


## How far the chunk's grass cells draw: the close-up distance, or the chunk's own export when off.
static func grass_distance(old: float) -> float:
	return minf(old, GRASS_DISTANCE) if enabled else old


static func density_gain() -> float:
	return DENSITY_GAIN if enabled else 1.0


## What a lawn material says about its lawn, for its blades: [tint (sRGB), dryness, seed index,
## striped]. PropFactory.lawn() records the numbers as metas; anything else (a park's own ground,
## a civic lawn) gets a plain watered lawn.
static func lawn_look(mat: Material, fallback_seed: int) -> Array:
	if mat and mat.has_meta("lawn_seed_index"):
		return [mat.get_meta("lawn_tint"), float(mat.get_meta("lawn_dryness")), int(mat.get_meta("lawn_seed_index")), bool(mat.get_meta("lawn_striped"))]
	return [Color(0.86, 0.96, 0.74), 0.35, absi(fallback_seed) % 997, true]


## A tuft's instance custom data: the old phase in x, then the lawn (see grass.gdshader's header).
static func tuft_data(phase: float, look: Array, edge_m: float) -> Color:
	return Color(phase, clampf(float(look[1]), 0.0, 1.0), float(int(look[2]) % 997) / 1024.0,
		clampf(snappedf(edge_m, 1.0 / 32.0), 0.0, 15.0) + (16.0 if bool(look[3]) else 0.0))


## The tuft's colour: the lawn's tint (sRGB, which the shader takes as the lawn's uniform)
## times the tuft's own jitter (the old tint roll).
static func tuft_color(look: Array, jitter: Color) -> Color:
	var t: Color = look[0]
	return Color(t.r * jitter.r, t.g * jitter.g, t.b * jitter.b, 1.0)


## Metres from `p` to the nearest edge of `rect` (0 outside).
static func edge_distance(rect: Rect2, p: Vector2) -> float:
	return maxf(0.0, minf(minf(p.x - rect.position.x, rect.end.x - p.x), minf(p.y - rect.position.y, rect.end.y - p.y)))


## The close-up tuft: PropFactory.grass_blade()'s blades from the same seeded stream and numbers,
## with UV.x the blade's place in the tuft (each blade its own height and shade in the shader),
## normals per ring (so a blade's segments share their vertices) and an index buffer.
static func blade_mesh() -> Mesh:
	if _blade:
		return _blade
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 90210
	var nb := PropFactory.GRASS_BLADES
	var ns := PropFactory.GRASS_SEGMENTS
	var base := 0
	for b in nb:
		var yaw := TAU * (float(b) / nb) + rng.randf_range(-0.30, 0.30)
		var dir := Vector3(sin(yaw), 0.0, cos(yaw))
		var side := Vector3(dir.z, 0.0, -dir.x)
		var height := PropFactory.GRASS_HEIGHT * rng.randf_range(0.42, 1.35)
		var width := PropFactory.GRASS_WIDTH * rng.randf_range(0.8, 1.2)
		var lean := rng.randf_range(0.24, 0.78) * height
		var root := dir * rng.randf_range(0.0, 0.055)
		var twist := rng.randf_range(-0.55, 0.55)
		# Mown and spread: the old tuft was ten blades from one point, a spiky clump on a flat
		# green; a lawn is turf, so the blades stand apart over a disc (a hash, not the stream:
		# every blade keeps its old shape) and at mowing height.
		height *= MOWN
		lean *= MOWN
		var ang := TAU * _h01([b, "spread_a"])
		root += Vector3(cos(ang), 0.0, sin(ang)) * SPREAD * sqrt(_h01([b, "spread_r"]))
		var u := (float(b) + 0.5) / float(nb)
		# Three vertices a ring (left edge, midrib, right edge) twice over: the two halves keep
		# their own normals, which is the crease.
		for half in 2:
			for seg in ns + 1:
				var t := float(seg) / ns
				var p := root + Vector3(0.0, height * t, 0.0) + dir * (lean * t * t)
				var tn := minf(t + 0.02, 1.0)
				var pn := root + Vector3(0.0, height * tn, 0.0) + dir * (lean * tn * tn)
				var tp := maxf(t - 0.02, 0.0)
				var pp := root + Vector3(0.0, height * tp, 0.0) + dir * (lean * tp * tp)
				var along := (pn - pp).normalized()
				var face := side.cross(along).normalized()
				var s := side.rotated(along, twist * t)
				var w := width * (1.0 - pow(t, 1.3) * 0.96)
				var c := p + face * (w * PropFactory.GRASS_CREASE)
				var sgn := -1.0 if half == 0 else 1.0
				var n := face.lerp(s * sgn, 0.34).normalized().lerp(Vector3.UP, 0.6).normalized()
				var edge := p + s * (w * sgn)
				for v: Vector3 in [edge, c]:
					st.set_normal(n)
					st.set_uv(Vector2(u, t))
					st.add_vertex(v)
			# Rings of two (edge, midrib): quads between consecutive rings, wound like the old
			# quads (left half a-b = edge-midrib, right half midrib-edge).
			for seg in ns:
				var e0 := base + seg * 2
				var m0 := e0 + 1
				var e1 := e0 + 2
				var m1 := e0 + 3
				if half == 0:
					for i: int in [e0, m0, m1, e0, m1, e1]:
						st.add_index(i)
				else:
					for i: int in [m0, e0, e1, m0, e1, m1]:
						st.add_index(i)
			base += (ns + 1) * 2
	var mesh := st.commit()
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/grass.gdshader")
	mat.set_shader_parameter("fade_start", FADE_START)
	mat.set_shader_parameter("fade_end", FADE_END)
	mesh.surface_set_material(0, mat)
	_blade = mesh
	return mesh


## The tuft a chunk plants: the close-up one, or the old one with the pass off.
static func tuft() -> Mesh:
	install()
	return blade_mesh() if enabled else PropFactory.grass_blade()


static func _h01(parts: Array) -> float:
	return float(absi(hash(parts)) % 100003) / 100003.0


## A parkway's lawn tint (sRGB multiplier on the grass texture, like CityChunk._lawn_color()'s),
## from a hash: watered, patchy or summer-dry, as the houses behind keep them.
static func parkway_tint(h: float, k: float) -> Color:
	if h < 0.3:
		return Color(lerpf(0.95, 1.1, k), lerpf(0.83, 0.93, k), lerpf(0.5, 0.6, k))
	if h < 0.6:
		return Color(lerpf(0.86, 0.98, k), lerpf(0.88, 0.97, k), lerpf(0.6, 0.7, k))
	return Color(lerpf(0.76, 0.9, k), lerpf(0.9, 1.0, k), lerpf(0.66, 0.78, k))


## The parkway pieces of a block (pure): [rect, edge index] for every run of an edge's strip clear
## of the corners and the drives. `drives` are YardFill's drive rects of the block's lots.
static func parkway_pieces(rect: Rect2, drives: Array) -> Array:
	var out: Array = []
	var edges := CityChunk._sidewalk_edges(rect)
	for e in edges.size():
		var a: Vector2 = edges[e][0]
		var b: Vector2 = edges[e][1]
		var inward: Vector2 = edges[e][2]
		var along_x := absf(b.x - a.x) > absf(b.y - a.y)
		var length := a.distance_to(b)
		# Blocked intervals along the edge (metres from a).
		var cuts: Array = [[0.0, PARKWAY_CORNER], [length - PARKWAY_CORNER, length]]
		for d: Rect2 in drives:
			if not _drive_meets(d, a, inward):
				continue
			var u0 := (d.position.x - a.x) if along_x else (d.position.y - a.y)
			var w := d.size.x if along_x else d.size.y
			cuts.append([u0 - PARKWAY_DRIVE_PAD, u0 + w + PARKWAY_DRIVE_PAD])
		cuts.sort_custom(func(p: Array, q: Array) -> bool: return float(p[0]) < float(q[0]))
		var t := 0.0
		for c: Array in cuts:
			if float(c[0]) - t >= PARKWAY_MIN:
				out.append([_strip_rect(a, b, inward, t, float(c[0])), e])
			t = maxf(t, float(c[1]))
		if length - t >= PARKWAY_MIN:
			out.append([_strip_rect(a, b, inward, t, length), e])
	return out


## Whether a drive rect reaches the street edge at `a` (its kerb end within the pavement).
static func _drive_meets(d: Rect2, a: Vector2, inward: Vector2) -> bool:
	var gap := 0.0
	if inward.y > 0.5:
		gap = d.position.y - a.y
	elif inward.y < -0.5:
		gap = a.y - d.end.y
	elif inward.x > 0.5:
		gap = d.position.x - a.x
	else:
		gap = a.x - d.end.x
	return gap < 4.0 + 1.5


static func _strip_rect(a: Vector2, b: Vector2, inward: Vector2, t0: float, t1: float) -> Rect2:
	var dir := (b - a).normalized()
	var p0 := a + dir * t0 + inward * PARKWAY_FROM
	var p1 := a + dir * t1 + inward * PARKWAY_TO
	return Rect2(Vector2(minf(p0.x, p1.x), minf(p0.y, p1.y)), (p1 - p0).abs())


## The block's step (CityChunk, after the lawn grass of a lawn block): the parkways, then the
## weeds once every deferred yard wall is down. FULL chunks only.
static func block_step(ch: CityChunk, rect: Rect2, district: int) -> void:
	if not enabled or ch.level != CityChunk.Level.FULL or ch.capturing:
		return
	if district in PARKWAY_DISTRICTS:
		parkway(ch, rect)
	ch._run_last(func() -> void: weeds(ch, rect, district))


## The block's drive rects (YardFill's plan of its lots, as Kerbs reads them).
static func _drives(ch: CityChunk) -> Array:
	var out: Array = []
	if ch._yard_lots.is_empty():
		return out
	var bp := YardFill.beach_block(ch.plan, ch.ix, ch.iz, ch._yard_lots)
	for lp: Dictionary in bp.lots:
		var d: Rect2 = lp.drive
		if d.size.x > 0.0 and not lp.walk_front:
			out.append(d)
	return out


## The parkway: a lawn strip between the kerb and the walk, a few centimetres proud of the
## pavement (soil sits over the concrete; it also covers the tree wells, so the street trees
## stand in the grass), one mesh a chunk on its own lawn, and its blades.
static func parkway(ch: CityChunk, rect: Rect2) -> void:
	var plan := ch.plan
	var pieces := _off_stops(plan, rect, parkway_pieces(rect, _drives(ch)))
	if pieces.is_empty():
		return
	var h := _h01([plan.seed, ch.ix, ch.iz, "parkway"])
	var tint := parkway_tint(h, _h01([plan.seed, ch.ix, ch.iz, "parkway_k"]))
	var mat := PropFactory.lawn(tint, hash([plan.seed, ch.ix, ch.iz, "parkway"]), 0.25 + 0.4 * _h01([plan.seed, ch.ix, ch.iz, "parkway_dry"]), 0.0)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for pc: Array in pieces:
		_strip_mesh(st, ch, pc[0])
	var mi := MeshInstance3D.new()
	mi.name = "Parkway"
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ch.add_child(mi)
	ch.set_meta("parkway_pieces", pieces.size())
	for pc: Array in pieces:
		var r: Rect2 = pc[0]
		ch._add_grass(r.grow(-0.05), PARKWAY_DENSITY, 0.0, [], mat, r)


## The pieces less the stretches beside a bus stop (its shelter and bench stand on the walk, the
## riders wait at the kerb: paved, as a real stop is), sampled a metre at a time.
static func _off_stops(plan: CityPlan, rect: Rect2, pieces: Array) -> Array:
	var edges := CityChunk._sidewalk_edges(rect)
	var out: Array = []
	for pc: Array in pieces:
		var r: Rect2 = pc[0]
		var inward: Vector2 = edges[int(pc[1])][2]
		var along_x := r.size.x >= r.size.y
		var length := r.size.x if along_x else r.size.y
		var run_from := 0.0
		var t := 0.0
		while t <= length:
			var c := r.get_center()
			var q := Vector2(r.position.x + t, c.y) if along_x else Vector2(c.x, r.position.y + t)
			var blocked := BigVehicles.in_stop_zone(plan, q - inward * 2.5)
			if blocked or t + 1.0 > length:
				var end := t if blocked else length
				if end - run_from >= PARKWAY_MIN:
					var nr := Rect2(r.position.x + run_from, r.position.y, end - run_from, r.size.y) if along_x \
						else Rect2(r.position.x, r.position.y + run_from, r.size.x, end - run_from)
					out.append([nr, pc[1]])
				run_from = t + 1.0
			t += 1.0
	return out


## How far the parkway's top stands over the pavement (it covers Kerbs' root heaves, 4.5 cm at
## most).
const PARKWAY_LIFT := 0.05


## One parkway piece into `st`: a relief-following grid along its long side, UV 0..1 across its
## rect (the lawn shader finds its edges from it), and a skirt down into the pavement round it.
static func _strip_mesh(st: SurfaceTool, ch: CityChunk, r: Rect2) -> void:
	var top := CityChunk.SIDEWALK_TOP + PARKWAY_LIFT
	var along_x := r.size.x >= r.size.y
	var length := r.size.x if along_x else r.size.y
	var n := maxi(1, ceili(length / PARKWAY_STEP))
	var pts: Array = []
	for i in n + 1:
		var row: Array = []
		for j in 3:
			var u := float(i) / n if along_x else float(j) / 2.0
			var v := float(j) / 2.0 if along_x else float(i) / n
			var x := r.position.x + r.size.x * u
			var z := r.position.y + r.size.y * v
			row.append([Vector3(x, top + ch._gy(x, z), z), Vector2(u, v)])
		pts.append(row)
	for i in n:
		for j in 2:
			var a: Array = pts[i][j]
			var b: Array = pts[i + 1][j]
			var c: Array = pts[i][j + 1]
			var d: Array = pts[i + 1][j + 1]
			_quad_up(st, a, b, d, c)
	# The skirt: the soil's edge, 8 cm down into the concrete on every side.
	var corners := [Vector2(r.position.x, r.position.y), Vector2(r.end.x, r.position.y), Vector2(r.end.x, r.end.y), Vector2(r.position.x, r.end.y)]
	for k in 4:
		var p0: Vector2 = corners[k]
		var p1: Vector2 = corners[(k + 1) % 4]
		var seg := maxi(1, ceili(p0.distance_to(p1) / PARKWAY_STEP))
		for i in seg:
			var q0 := p0.lerp(p1, float(i) / seg)
			var q1 := p0.lerp(p1, float(i + 1) / seg)
			var y0 := top + ch._gy(q0.x, q0.y)
			var y1 := top + ch._gy(q1.x, q1.y)
			var out := Vector3(q1.y - q0.y, 0.0, q0.x - q1.x).normalized()
			# Outward from the rect: flip toward away from its centre.
			var mid := (q0 + q1) * 0.5
			if Vector2(out.x, out.z).dot(mid - r.get_center()) < 0.0:
				out = -out
			var uv := Vector2(clampf((mid.x - r.position.x) / r.size.x, 0.0, 1.0), clampf((mid.y - r.position.y) / r.size.y, 0.0, 1.0))
			var v := [Vector3(q0.x, y0, q0.y), Vector3(q1.x, y1, q1.y), Vector3(q1.x, y1 - 0.13, q1.y), Vector3(q0.x, y0 - 0.13, q0.y)]
			# RcSuburb: the soil edge slopes out at 45 degrees (the visible 5 cm a bevel lit by the
			# sky), not a vertical lawn-textured wall that read as the dark edge of a carpet tile.
			var face := out
			if RcSuburb.enabled:
				v[2] += out * 0.13
				v[3] += out * 0.13
				face = (out + Vector3.UP).normalized()
				# Its UV inside the rect: the lawn shader paints the edge's soil line on the top's
				# rim, and the bevel reads as the turf rolling over (the edge UV drew it dark).
				uv = Vector2(0.5, 0.5)
			var tri := [0, 1, 2, 0, 2, 3]
			# Winding toward `out` (Godot's front faces are clockwise seen from the front).
			var nrm: Vector3 = (v[1] - v[0]).cross(v[2] - v[0])
			if nrm.dot(out) > 0.0:
				tri = [0, 2, 1, 0, 3, 2]
			for t: int in tri:
				st.set_normal(face)
				st.set_tangent(Plane(1.0, 0.0, 0.0, 1.0))
				st.set_uv(uv)
				st.add_vertex(v[t])


## A ground quad facing up from four [position, uv] corners in order round it.
static func _quad_up(st: SurfaceTool, a: Array, b: Array, c: Array, d: Array) -> void:
	var tri := [a, b, c, a, c, d]
	var n: Vector3 = ((b[0] as Vector3) - (a[0] as Vector3)).cross((c[0] as Vector3) - (a[0] as Vector3))
	if n.y > 0.0:
		tri = [a, c, b, a, d, c]
	for p: Array in tri:
		st.set_normal(Vector3.UP)
		st.set_tangent(Plane(1.0, 0.0, 0.0, 1.0))
		st.set_uv(p[1])
		st.add_vertex(p[0])


# --- Weeds ----------------------------------------------------------------------------------------

## A weed's mesh, code-built at real size: 0 a splayed tuft of crabgrass / wild grass, 1 a
## dandelion-like rosette of toothed leaves with a flower on a stalk, 2 the rosette alone. Vertex
## colour is the part (linear: leaf, paler leaf, flower), UV.y its height up the plant.
static func weed_mesh(kind: int) -> Mesh:
	if _weeds.size() > kind and _weeds[kind]:
		return _weeds[kind]
	while _weeds.size() <= kind:
		_weeds.append(null)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4410 + kind
	if kind == 0:
		for b in 9:
			var yaw := TAU * b / 9.0 + rng.randf_range(-0.3, 0.3)
			var dir := Vector3(sin(yaw), 0.0, cos(yaw))
			var side := Vector3(dir.z, 0.0, -dir.x)
			var hgt := rng.randf_range(0.08, 0.22)
			var reach := rng.randf_range(0.06, 0.2)
			var w := rng.randf_range(0.007, 0.012)
			var col := Color(0.16, 0.24, 0.06) if b % 3 else Color(0.24, 0.27, 0.08)
			_blade_strip(st, dir, side, hgt, reach, w, col)
	else:
		for l in 8:
			var yaw := TAU * l / 8.0 + rng.randf_range(-0.2, 0.2)
			var dir := Vector3(sin(yaw), 0.0, cos(yaw))
			var side := Vector3(dir.z, 0.0, -dir.x)
			var length := rng.randf_range(0.09, 0.17)
			var col := Color(0.09, 0.19, 0.05) if l % 2 else Color(0.12, 0.23, 0.07)
			var segs := 5
			for s in segs:
				var t0 := float(s) / segs
				var t1 := float(s + 1) / segs
				# Toothed: the leaf's width swells and pinches along it.
				var w0 := length * 0.16 * sin(PI * t0) * (0.75 + 0.25 * cos(t0 * 17.0))
				var w1 := length * 0.16 * sin(PI * t1) * (0.75 + 0.25 * cos(t1 * 17.0))
				var p0 := dir * (length * t0) + Vector3(0.0, 0.01 + 0.025 * t0, 0.0)
				var p1 := dir * (length * t1) + Vector3(0.0, 0.01 + 0.025 * t1, 0.0)
				var q := [p0 - side * w0, p0 + side * w0, p1 + side * w1, p1 - side * w1]
				for i: int in [0, 2, 1, 0, 3, 2]:
					st.set_color(col)
					st.set_normal(Vector3.UP.lerp(dir, 0.2).normalized())
					st.set_uv(Vector2(0.5, 0.15 * (t0 if i < 2 else t1)))
					st.add_vertex(q[i])
		if kind == 1:
			# The stalk and the flower head.
			var hgt := 0.2
			var stalk := Color(0.2, 0.3, 0.1)
			_blade_strip(st, Vector3(0.0, 0.0, 1.0), Vector3(1.0, 0.0, 0.0), hgt, 0.03, 0.003, stalk)
			var c := Vector3(0.0, hgt, 0.03)
			var yellow := Color(0.92, 0.62, 0.02)
			for k in 10:
				var a0 := TAU * k / 10.0
				var a1 := TAU * (k + 1) / 10.0
				for v: Vector3 in [c + Vector3(0.0, 0.006, 0.0), c + Vector3(cos(a1), 0.0, sin(a1)) * 0.02, c + Vector3(cos(a0), 0.0, sin(a0)) * 0.02]:
					st.set_color(yellow)
					st.set_normal(Vector3.UP)
					st.set_uv(Vector2(0.5, 1.0))
					st.add_vertex(v)
	var mesh := st.commit()
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/lawn_weed.gdshader")
	mesh.surface_set_material(0, mat)
	_weeds[kind] = mesh
	return mesh


## A narrow arched blade or stalk from the origin: `hgt` up, its tip `reach` out along `dir`.
static func _blade_strip(st: SurfaceTool, dir: Vector3, side: Vector3, hgt: float, reach: float, w: float, col: Color) -> void:
	var segs := 3
	for s in segs:
		var t0 := float(s) / segs
		var t1 := float(s + 1) / segs
		var p0 := Vector3(0.0, hgt * sin(t0 * PI * 0.5), 0.0) + dir * (reach * t0 * t0)
		var p1 := Vector3(0.0, hgt * sin(t1 * PI * 0.5), 0.0) + dir * (reach * t1 * t1)
		var w0 := w * (1.0 - t0 * 0.9)
		var w1 := w * (1.0 - t1 * 0.9)
		var q := [p0 - side * w0, p0 + side * w0, p1 + side * w1, p1 - side * w1]
		for i: int in [0, 2, 1, 0, 3, 2]:
			st.set_color(col)
			st.set_normal(Vector3.UP.lerp(dir, 0.35).normalized())
			st.set_uv(Vector2(0.5, t0 if i < 2 else t1))
			st.add_vertex(q[i])


## Weeds where nobody mows (pure placement off the block, then into the chunk's batch): in the
## pavement's slab joints and along the seams by a lawn or parkway, and along the foot of the
## yards' fences and walls. Every roll a hash of seed + spot.
static func weeds(ch: CityChunk, rect: Rect2, district: int) -> void:
	var spots := weed_spots(ch, rect, district)
	var keys := {}
	for w: Array in spots:
		var kind := int(w[1])
		var key := "lawn_weed_%d" % kind
		keys[key] = true
		var at: Vector2 = w[0]
		var sc: float = w[2]
		var basis := Basis(Vector3.UP, float(w[3])).scaled(Vector3(sc, sc * float(w[4]), sc))
		ch._batch.add(key, weed_mesh(kind), Transform3D(basis, Vector3(at.x, float(w[5]), at.y)), Color.WHITE, Color(float(w[6]), 0.0, 0.0, 0.0))
	for key: String in keys:
		ch._batch.set_no_shadow(key)
		ch._batch.set_draw_distance(key, WEED_DRAW)
	ch.set_meta("lawn_weeds", spots.size())


## The weeds' spots: [at, kind, scale, yaw, height scale, base y (before the batch's relief),
## dryness].
static func weed_spots(ch: CityChunk, rect: Rect2, district: int) -> Array:
	var out: Array = []
	var plan := ch.plan
	var joint := 1.5
	if ch.has_meta("kerbs"):
		var mat: Material = (ch.get_meta("kerbs") as Dictionary).get("mat")
		if mat is ShaderMaterial:
			var j: Variant = (mat as ShaderMaterial).get_shader_parameter("joint_spacing")
			if j != null and float(j) > 0.3:
				joint = float(j)
	var lawn_block := bool(CityPlan.DISTRICTS[district].get("lawn", false))
	# The joints across the walk and the seams along it: by a lawn (the back of the walk on a
	# lawn block) and by the parkway (its kerb-side edge, where there is one).
	var parkway := district in PARKWAY_DISTRICTS
	if lawn_block or parkway:
		for e in CityChunk._sidewalk_edges(rect):
			var a: Vector2 = e[0]
			var b: Vector2 = e[1]
			var inward: Vector2 = e[2]
			var dir := (b - a).normalized()
			var length := a.distance_to(b)
			var vs: Array = []
			if lawn_block:
				vs.append(plan.sidewalk_width - 0.03)
			if parkway:
				vs.append(PARKWAY_TO + 0.03)
			# Along the seams.
			var t := 1.5
			while t < length - 1.5 and out.size() < MAX_WEEDS:
				for v: float in vs:
					var p := a + dir * t + inward * v
					var h := _h01([plan.seed, int(roundf(p.x * 4.0)), int(roundf(p.y * 4.0)), "seam_weed"])
					if h < 0.22:
						out.append(_weed(plan, p, h, CityChunk.SIDEWALK_TOP + 0.005))
				t += 0.9
			# In the joints across the walk (world-aligned, as road.gdshader draws them).
			var w0 := PARKWAY_TO if parkway else 0.3
			var w1 := plan.sidewalk_width - 0.1
			var along := a.x if absf(dir.x) > 0.5 else a.y
			var k0 := ceili(along / joint)
			var k1 := floori((along + length) / joint)
			for k in range(k0, k1 + 1):
				var u := float(k) * joint - along
				if u < 2.0 or u > length - 2.0 or out.size() >= MAX_WEEDS:
					continue
				if _h01([plan.seed, k, int(roundf(a.x)), int(roundf(a.y)), "joint"]) > WEED_JOINT_ODDS * 4.0:
					continue
				var v := lerpf(w0, w1, _h01([plan.seed, k, int(roundf(a.y)), "joint_v"]))
				var p := a + dir * u + inward * v
				out.append(_weed(plan, p, _h01([plan.seed, k, "jw"]), CityChunk.SIDEWALK_TOP + 0.002))
	# Along the foot of the yards' fences and walls.
	for wall: Array in ch._yard_walls:
		var size: Vector3 = wall[0]
		var c: Vector3 = wall[1]
		if float(wall[4]) < 0.4 or minf(size.x, size.z) > 0.5 or out.size() >= MAX_WEEDS:
			continue
		var along_x := size.x > size.z
		var length := size.x if along_x else size.z
		var n := int(length * WEED_FENCE_PER_M)
		for i in n:
			var key := [plan.seed, int(roundf(c.x * 10.0)), int(roundf(c.z * 10.0)), i]
			var t := (_h01(key + ["t"]) - 0.5) * length
			var side := (0.5 * minf(size.x, size.z) + 0.05) * (1.0 if _h01(key + ["s"]) < 0.5 else -1.0)
			var p := Vector2(c.x + t, c.z + side) if along_x else Vector2(c.x + side, c.z + t)
			if not rect.has_point(p):
				continue
			var y := c.y - size.y * 0.5 + 0.04 - ch._gy(p.x, p.y)
			var wd := _weed(plan, p, _h01(key + ["k"]), y)
			# Fence-line grass grows tall where the mower cannot reach.
			wd[4] = float(wd[4]) * 1.6
			out.append(wd)
			if out.size() >= MAX_WEEDS:
				break
	return out


static func _weed(plan: CityPlan, p: Vector2, h: float, y: float) -> Array:
	var key := [plan.seed, int(roundf(p.x * 8.0)), int(roundf(p.y * 8.0))]
	var kind := 0 if h < 0.55 else (1 if h < 0.75 else 2)
	return [p, kind, 0.7 + 0.7 * _h01(key + ["sc"]), TAU * _h01(key + ["yaw"]), 0.8 + 0.5 * _h01(key + ["hs"]), y, _h01(key + ["dry"])]
