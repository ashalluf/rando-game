class_name ReplicaBuilder
extends RefCounted
## Builds a chunk's share of a replica area (ReplicaAreas): the road with its kerbs, gutters,
## markings and pavements, the ocean-side walkway, seat wall, scrub verge, bluff-edge fence, the
## bluff face and the stairs down it, the roundabout, the beach car park, the side streets, the
## street furniture, the palms, the parked cars, and (through ReplicaHouses) the frontage houses
## and the seeded backfill houses on the rest of a replica block.
##
## Ownership, so nothing is built twice: a path segment belongs to the chunk its midpoint is in,
## a lot to the chunk its centre is in, a roundabout, stair or car park to the chunk its centre
## is in. Everything is seeded from the plan seed and the thing's own position or index, never
## from the chunk's rng, so the seeded block content around it does not move.
##
## Heights: the road and everything laid along it are built at the route's profile (`top`), which
## is exactly the ground the terrace gives the chunk (_gy() + ROAD_TOP) on the town part and the
## carved bed on the hill part. Batch instances go through the chunk's batch, which adds _gy()
## itself, so they are handed heights relative to it (`_rel()`).

# --- Tunables --------------------------------------------------------------------------------
# Static-only class, so the knobs are consts here at the top.

## Grey cobra-head street lamp: pole height, and the reach of its road and walkway arms.
const LAMP_HEIGHT := 9.4
const LAMP_ARM_ROAD := 2.9
const LAMP_ARM_WALK := 1.6
## Length of a parallel parking stall (the T marks are this far apart), and the share filled.
const STALL := 6.4
const PARK_ODDS := 0.72
## Share of the beach car park's nose-in stalls with a car in them.
const LOT_ODDS := 0.8
## Mexican fan palms: scale range (the palm mesh is 11-17 m at 1.0; these stand 16-26 m).
const PALM_SCALE := Vector2(1.25, 1.6)
## Median palms (on the planted median at the south end), metres apart.
const MEDIAN_PALM_STEP := 13.0
## Plants on the bluff face per metre of road, and in the verge strip.
const BLUFF_PLANTS := 1.3
const VERGE_PLANTS := 0.9
## Height of paint above the surface it lies on.
const PAINT_LIFT := 0.012
## Bluff-edge fence: post spacing, height.
const FENCE_STEP := 2.4
const FENCE_H := 1.05

const ASPHALT_TINT := Color(0.80, 0.80, 0.83)
const CONCRETE_TINT := Color(1.52, 1.51, 1.46)
const WHITE := Color(0.93, 0.93, 0.90)
const YELLOW := Color(0.95, 0.76, 0.18)

var chunk: CityChunk
var rep: ReplicaAreas
var plan: CityPlan
var full: bool = true
var role: int = 0
var area: Rect2
var _st := {}
var _col := PackedVector3Array()
var _body: StaticBody3D
var _lights: Array[Vector3] = []


## Adds the replica's build steps to a chunk. Called for every chunk the replica is near.
static func attach(c: CityChunk, chunk_role: int) -> Array[Callable]:
	var b := ReplicaBuilder.new()
	b.chunk = c
	b.plan = c.plan
	b.rep = c.plan.macro.replica
	b.full = c.level == CityChunk.Level.FULL
	b.role = chunk_role
	b.area = c.owned_rect()
	c._replica = b
	var steps: Array[Callable] = []
	if chunk_role == 1:
		steps.append_array(b._grid_steps())
	steps.append_array([b._road_step, b._features_step])
	if chunk_role == 1:
		steps.append(b._backfill_ground_step)
	steps.append(b._furniture_step)
	for lot in b._lots_here():
		steps.append(ReplicaHouses.build.bind(b, lot))
	if b.full:
		steps.append_array(b._car_steps())
		steps.append_array(b._walker_steps())
	steps.append(b._commit_step)
	return steps


## Whether a chunk's rect is anywhere near the replica at all (cheap).
static func wanted(c: CityChunk) -> bool:
	if c.plan.macro == null or c.plan.macro.replica == null:
		return false
	var r := c.owned_rect()
	var rep_: ReplicaAreas = c.plan.macro.replica
	for p: Vector2 in [r.get_center(), r.position, r.end, Vector2(r.position.x, r.end.y), Vector2(r.end.x, r.position.y)]:
		if not rep_.nearest(p, 240.0).is_empty():
			return true
	return false


## The lots this chunk builds: the frontage lots whose centre is in its area, and on a replica
## block its backfill (ReplicaAreas.block_lots(), which CityPlan.lots() hands every other tier).
func _lots_here() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var got: Variant = rep.block_lots(plan, chunk.ix, chunk.iz)
	if got != null:
		out.assign(got)
	return out


# --- Surfaces --------------------------------------------------------------------------------

func st(name: String) -> SurfaceTool:
	if not _st.has(name):
		var s := SurfaceTool.new()
		s.begin(Mesh.PRIMITIVE_TRIANGLES)
		_st[name] = s
	return _st[name]


## One triangle facing `up` (the side it is seen from), with a colour and planar UVs.
func tri(name: String, a: Vector3, b: Vector3, c: Vector3, col: Color, up: Vector3, collide: bool = false, uv_scale: float = 0.25) -> void:
	var s := st(name)
	if (b - a).cross(c - a).dot(up) > 0.0:
		var t := b
		b = c
		c = t
	for v: Vector3 in [a, b, c]:
		s.set_color(col)
		s.set_uv(Vector2(v.x, v.z) * uv_scale if absf(up.y) > 0.5 else Vector2(v.x + v.z, v.y) * uv_scale)
		s.add_vertex(v)
	if collide:
		_col.append_array(PackedVector3Array([a, b, c]))


func quad(name: String, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, up: Vector3, collide: bool = false) -> void:
	tri(name, a, b, c, col, up, collide)
	tri(name, a, c, d, col, up, collide)


## A box from its centre, half extents along three axes, into a surface (every face outward).
func box(name: String, c: Vector3, ax: Vector3, ay: Vector3, az: Vector3, col: Color, collide: bool = false) -> void:
	var p := [c - ax - ay - az, c + ax - ay - az, c + ax - ay + az, c - ax - ay + az,
		c - ax + ay - az, c + ax + ay - az, c + ax + ay + az, c - ax + ay + az]
	# Flat-shaded: a box's corners must not average their normals round the edge.
	st(name).set_smooth_group(-1)
	for f: Array in [[0, 1, 2, 3, -ay], [4, 5, 6, 7, ay], [0, 1, 5, 4, -az], [3, 2, 6, 7, az], [0, 3, 7, 4, -ax], [1, 2, 6, 5, ax]]:
		quad(name, p[f[0]], p[f[1]], p[f[2]], p[f[3]], col, f[4], collide)
	st(name).set_smooth_group(0)


## A world point on the route: sample `i`, `o` metres to its left, `y` above its road top.
func P(i: int, o: float, y: float) -> Vector3:
	var p: Vector2 = rep.pts[i] + ReplicaAreas.left_of(rep.dirs[i]) * o
	return Vector3(p.x, rep.top[i] + y, p.y)


## A band along segment i -> i+1 between lateral lines oa..ob (per end), flat at height y.
func band(name: String, i: int, oa0: float, ob0: float, oa1: float, ob1: float, y: float, col: Color, collide: bool = true) -> void:
	var j := i + 1
	quad(name, P(i, oa0, y), P(i, ob0, y), P(j, ob1, y), P(j, oa1, y), col, Vector3.UP, collide)


## A vertical face along segment i -> i+1 at lateral o (per end) from y0 to y1, facing `side`
## (+1 left, -1 right).
func wall(name: String, i: int, o0: float, o1: float, y0: float, y1: float, col: Color, side: float, collide: bool = true) -> void:
	var j := i + 1
	var n := Vector3(ReplicaAreas.left_of(rep.dirs[i]).x, 0.0, ReplicaAreas.left_of(rep.dirs[i]).y) * side
	quad(name, P(i, o0, y0), P(j, o1, y0), P(j, o1, y1), P(i, o0, y1), col, n, collide)


## Height relative to what the chunk's batch adds (its _gy), for batch instances.
func rel(p: Vector3) -> Vector3:
	return Vector3(p.x, p.y - chunk._gy(p.x, p.z), p.z)


func batch_add(key: String, mesh: Mesh, xform: Transform3D, col: Color = Color.WHITE, custom: Color = Color.BLACK) -> void:
	chunk._batch.add(key, mesh, Transform3D(xform.basis, rel(xform.origin)), col, custom)


## A basis with its X along `along` (horizontal), Y up, Z across.
static func yaw_basis(along: Vector2) -> Basis:
	var x := Vector3(along.x, 0.0, along.y).normalized()
	var z := x.cross(Vector3.UP).normalized() * -1.0
	return Basis(x, Vector3.UP, z)


static func hash01(key: Array) -> float:
	return float(absi(hash(key)) % 100003) / 100003.0


func _owned(i: int) -> bool:
	if i < 0 or i >= rep.pts.size() - 1:
		return false
	return area.has_point((rep.pts[i] + rep.pts[i + 1]) * 0.5)


func _near_ring(p: Vector2, extra: float) -> Dictionary:
	for ra in rep.roundabouts:
		if p.distance_to(ra.center) < float(ra.r_out) + extra:
			return ra
	return {}


func _mouth_at(s: float, pad: float) -> Dictionary:
	for m in rep.mouths(plan):
		if absf(s - float(m.s)) < float(m.width) * 0.5 + pad:
			return m
	return {}


# --- The road --------------------------------------------------------------------------------

func _road_step() -> void:
	for i in rep.pts.size() - 1:
		if _owned(i):
			_segment(i)
	if _owned(0):
		_north_end()
	for st_ in rep.streets:
		if st_.has("pts"):
			_street(st_)


func _segment(i: int) -> void:
	var j := i + 1
	var a: Dictionary = rep.sec[i]
	var b: Dictionary = rep.sec[j]
	var s := (rep.run[i] + rep.run[j]) * 0.5
	var mid := (rep.pts[i] + rep.pts[j]) * 0.5
	var hill := s > rep.s_city_end
	var ring := _near_ring(mid, 7.0)
	var in_ring := not ring.is_empty()
	var concrete := Color.WHITE
	var asphalt := Color.WHITE
	if hill:
		band("asphalt", i, a.kerb_w, a.kerb_e, b.kerb_w, b.kerb_e, 0.0, asphalt)
		# Gravel shoulders easing into the cut, so the asphalt does not end in a knife edge.
		band("verge", i, a.kerb_w - 1.4, a.kerb_w, b.kerb_w - 1.4, b.kerb_w, -0.07, Color(0.9, 0.85, 0.7))
		band("verge", i, a.kerb_e, a.kerb_e + 1.4, b.kerb_e, b.kerb_e + 1.4, -0.07, Color(0.9, 0.85, 0.7))
		_paint_hill(i)
		return
	var raised := float(a.median_raised) + float(b.median_raised) > 1.0
	# Carriageway, gutters and kerbs.
	var mw := float(a.median)
	var mw1 := float(b.median)
	var gut := 0.45
	band("asphalt", i, a.kerb_w + gut, -mw, b.kerb_w + gut, -mw1, 0.0, asphalt)
	band("asphalt", i, mw, a.kerb_e - gut, mw1, b.kerb_e - gut, 0.0, asphalt)
	if raised:
		band("concrete", i, -mw, -mw + 0.2, -mw1, -mw1 + 0.2, 0.15, concrete)
		band("concrete", i, mw - 0.2, mw, mw1 - 0.2, mw1, 0.15, concrete)
		band("median", i, -mw + 0.2, mw - 0.2, -mw1 + 0.2, mw1 - 0.2, 0.17, Color.WHITE)
		wall("concrete", i, -mw, -mw1, 0.0, 0.15, concrete, -1.0)
		wall("concrete", i, mw, mw1, 0.0, 0.15, concrete, 1.0)
	else:
		band("asphalt", i, -mw, mw, -mw1, mw1, 0.0, asphalt)
	if in_ring:
		# Inside the roundabout the ring itself is the road; the leg only lays its carriageway,
		# which the ring's own asphalt covers.
		_paint_segment(i, true)
		return
	band("concrete", i, a.kerb_w, a.kerb_w + gut, b.kerb_w, b.kerb_w + gut, 0.0, concrete.darkened(0.08))
	band("concrete", i, a.kerb_e - gut, a.kerb_e, b.kerb_e - gut, b.kerb_e, 0.0, concrete.darkened(0.08))
	# West side: kerb, walkway, seat wall, verge (or the west lots), then the bluff.
	var coast := float(a.coast) > 0.5
	wall("concrete", i, a.kerb_w, b.kerb_w, 0.0, 0.15, concrete, 1.0)
	band("concrete", i, a.walk_w_edge, a.kerb_w, b.walk_w_edge, b.kerb_w, 0.15, concrete)
	var stair := _stair_near(s, 1.6)
	if float(a.west_lots) > 1.0:
		band("yard", i, a.edge, a.walk_w_edge, b.edge, b.walk_w_edge, 0.15, Color.WHITE)
	elif coast:
		var seat_o0: float = a.walk_w_edge
		var seat_o1: float = b.walk_w_edge
		if not stair:
			band("concrete", i, seat_o0 - 0.45, seat_o0, seat_o1 - 0.45, seat_o1, 0.62, concrete.darkened(0.05))
			wall("concrete", i, seat_o0, seat_o1, 0.15, 0.62, concrete.darkened(0.05), 1.0)
			wall("concrete", i, seat_o0 - 0.45, seat_o1 - 0.45, 0.2, 0.62, concrete.darkened(0.1), -1.0)
			band("verge", i, a.edge, seat_o0 - 0.45, b.edge, seat_o1 - 0.45, 0.2, Color.WHITE)
		else:
			band("concrete", i, a.edge, seat_o0, b.edge, seat_o1, 0.2, concrete)
	if coast:
		_bluff(i)
	# East side: kerb, pavement, the frontage ground and the alley behind it - cut, where a grid
	# street comes in, round its carriageway and its two pavements.
	var ms := _mouths_near(s, 12.0)
	var back0: float = a.walk_e_edge + float(a.east_lots)
	var back1: float = b.walk_e_edge + float(b.east_lots)
	var lots := float(a.east_lots) > 1.0
	var alley := lots and float(a.alley) > 0.5
	if ms.is_empty():
		wall("concrete", i, a.kerb_e, b.kerb_e, 0.0, 0.15, concrete, -1.0)
		band("concrete", i, a.kerb_e, a.walk_e_edge, b.kerb_e, b.walk_e_edge, 0.15, concrete)
		if lots:
			band("yard", i, a.walk_e_edge, back0, b.walk_e_edge, back1, 0.15, Color.WHITE)
			if alley:
				band("concrete", i, back0, a.east_back, back1, b.east_back, 0.04, concrete.darkened(0.12))
				wall("concrete", i, back0, back1, 0.04, 0.15, concrete, 1.0)
				wall("concrete", i, a.east_back, b.east_back, 0.04, 0.15, concrete, -1.0)
	else:
		var hf := _seg_height(i)
		var pave := _seg_poly(i, a.kerb_e, a.walk_e_edge, b.kerb_e, b.walk_e_edge)
		var yard := _seg_poly(i, a.walk_e_edge, back0, b.walk_e_edge, back1) if lots else PackedVector2Array()
		var lane := _seg_poly(i, back0, a.east_back, back1, b.east_back) if alley else PackedVector2Array()
		var pieces: Array = [[pave, "concrete", 0.15, concrete], [yard, "yard", 0.15, Color.WHITE], [lane, "concrete", 0.04, concrete.darkened(0.12)]]
		for m in ms:
			var r := _mouth_rects(m)
			var next: Array = []
			for pc: Array in pieces:
				var poly: PackedVector2Array = pc[0]
				if poly.is_empty():
					continue
				for q in Geometry2D.intersect_polygons(poly, r[0]):
					_poly_fill("asphalt", q, hf.bind(0.0), asphalt, true)
				for side_r: PackedVector2Array in [r[1], r[2]]:
					for q in Geometry2D.intersect_polygons(poly, side_r):
						_poly_fill("concrete", q, hf.bind(0.15), concrete, true)
				# The cutter spans the whole corridor, so no piece can come back with a hole in it.
				for q in Geometry2D.clip_polygons(poly, r[3]):
					next.append([q, pc[1], pc[2], pc[3]])
			pieces = next
			if (m.s as float) >= rep.run[i] and (m.s as float) < rep.run[j]:
				_mouth_kerbs(m)
		for pc: Array in pieces:
			_poly_fill(pc[1], pc[0], hf.bind(float(pc[2])), pc[3], true)
		# The Esplanade's kerb, broken for each street.
		var cuts: Array[PackedVector2Array] = []
		var wide: Array[PackedVector2Array] = []
		for m in ms:
			var r := _mouth_rects(m)
			cuts.append(r[0])
			wide.append(r[3])
		_wall_cut("concrete", i, a.kerb_e, b.kerb_e, 0.0, 0.15, concrete, -1.0, cuts)
		if alley:
			_wall_cut("concrete", i, back0, back1, 0.04, 0.15, concrete, 1.0, wide)
			_wall_cut("concrete", i, a.east_back, b.east_back, 0.04, 0.15, concrete, -1.0, wide)
	_paint_segment(i, false)


## The route's north end (Knob Hill): the carriageway stops at a kerb with a pavement across it,
## rather than at a raw edge.
func _north_end() -> void:
	var sd: Dictionary = rep.sec[0]
	var d: Vector2 = rep.dirs[0]
	var l := ReplicaAreas.left_of(d)
	var p0: Vector2 = rep.pts[0]
	var y: float = rep.top[0]
	var q := func(o: float, back: float, h: float) -> Vector3:
		var r := p0 + l * o - d * back
		return Vector3(r.x, y + h, r.y)
	var w0: float = float(sd.walk_w_edge)
	var w1: float = float(sd.walk_e_edge)
	quad("concrete", q.call(w0, 0.0, 0.15), q.call(w1, 0.0, 0.15), q.call(w1, 3.5, 0.15), q.call(w0, 3.5, 0.15), Color.WHITE, Vector3.UP, true)
	var dv := Vector3(d.x, 0.0, d.y)
	quad("concrete", q.call(float(sd.kerb_w), 0.0, 0.0), q.call(float(sd.kerb_e), 0.0, 0.0), q.call(float(sd.kerb_e), 0.0, 0.15), q.call(float(sd.kerb_w), 0.0, 0.15), Color.WHITE, dv, true)
	# Its back edge, down to whatever ground the seeded block beyond it has.
	quad("concrete", q.call(w0, 3.5, -0.6), q.call(w1, 3.5, -0.6), q.call(w1, 3.5, 0.15), q.call(w0, 3.5, 0.15), Color.WHITE, -dv, true)


## The bluff face down to the sand: rows from the edge to the toe, steep near the top and easing
## out onto the beach, roughened so it does not read as a ramp.
const BLUFF_ROWS := [0.0, 0.07, 0.2, 0.4, 0.62, 0.82, 0.94, 1.0]


func _bluff_point(i: int, f: float) -> Vector3:
	var sd: Dictionary = rep.sec[i]
	var edge: float = sd.edge
	var toe: float = sd.toe
	var s: float = rep.run[i]
	var n := hash01([int(s * 0.5), int(f * 20.0), "bluff"]) - 0.5
	var n2 := sin(s * 0.061 + f * 3.0) * 0.5 + sin(s * 0.023) * 0.5
	var o := lerpf(edge, toe, f) + (n * 1.4 + n2 * 1.8) * (4.0 * f * (1.0 - f))
	var top_y := rep.top[i] + 0.2
	var g := 1.0 - pow(1.0 - f, 1.8)
	var y := lerpf(top_y, 0.42, g)
	y += (n * 0.9 + n2 * 0.6) * (4.0 * f * (1.0 - f))
	var p: Vector2 = rep.pts[i] + ReplicaAreas.left_of(rep.dirs[i]) * o
	return Vector3(p.x, y, p.y)


func _bluff(i: int) -> void:
	var j := i + 1
	var by_lot := false
	for k in BLUFF_ROWS.size() - 1:
		var f0: float = BLUFF_ROWS[k]
		var f1: float = BLUFF_ROWS[k + 1]
		var col := Color(0.02, 0.0, 0.0, 1.0)
		var q := [_bluff_point(i, f0), _bluff_point(i, f1), _bluff_point(j, f1), _bluff_point(j, f0)]
		# Where the beach car park's platform is, its planted slope is the ground (_car_park()).
		var on_lot := false
		for v: Vector3 in q:
			if rep.car_park_level(Vector2(v.x, v.z)) > -INF:
				on_lot = true
		if on_lot:
			by_lot = true
			continue
		quad("bluff", q[0], q[1], q[2], q[3], col, Vector3.UP, true)
	if not full or by_lot:
		return
	# Scrub on the face and the fence along its edge.
	var sd: Dictionary = rep.sec[i]
	var length := rep.run[j] - rep.run[i]
	var plants := int(round(length * BLUFF_PLANTS))
	for k in plants:
		var h := hash([plan.seed, "bluffplant", i, k])
		var f := 0.06 + 0.84 * hash01([h, 1])
		var t := hash01([h, 2])
		var q := _bluff_point(i, f).lerp(_bluff_point(j, f), t)
		var roll := hash01([h, 3])
		var yaw := hash01([h, 4]) * TAU
		var sc := 0.8 + hash01([h, 5]) * 0.9
		if roll < 0.42:
			var v := h % 5
			batch_add("scrub_%d" % v, PropFactory.model_scrub(v), Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(sc, sc, sc) * 1.6), q - Vector3(0, 0.05, 0)), Color(1.0, 0.98, 0.9))
		elif roll < 0.7:
			var v := h % 4
			batch_add("shrub_%d" % v, PropFactory.model_shrub(v), Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(sc, sc, sc)), q - Vector3(0, 0.08, 0)), Color(0.95, 1.0, 0.85))
		elif roll < 0.85:
			# Ice plant stand-in: low flowering mats (orange and purple gazania).
			var v: int = [0, 3, 1][h % 3]
			batch_add("flower_%d" % v, PropFactory.model_flower(v), Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(sc, sc, sc) * 1.3), q))
		else:
			var v := h % 5
			batch_add("tuft_%d" % v, PropFactory.model_grass_tuft(v), Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(sc, sc, sc) * 2.2), q), Color(1.05, 0.95, 0.7))
	if float(sd.west_lots) > 1.0:
		return
	# The post-and-rail fence along the bluff edge, as a run of batched posts and rails.
	var s0 := rep.run[i]
	var s1 := rep.run[j]
	var k0 := ceili(s0 / FENCE_STEP)
	var k1 := floori(s1 / FENCE_STEP)
	for k in range(k0, k1 + 1):
		var sk := float(k) * FENCE_STEP
		if _stair_near(sk, 1.4):
			continue
		var at := rep.at_s(sk)
		var sdk: Dictionary = at[3]
		var p2: Vector2 = (at[0] as Vector2) + ReplicaAreas.left_of(at[1]) * (float(sdk.edge) + 0.35)
		var base := Vector3(p2.x, float(at[2]) + 0.2, p2.y)
		# The post mesh is centred on its origin.
		batch_add("fence_post", _fence_post(), Transform3D(Basis(), base + Vector3(0, FENCE_H * 0.5, 0)))
		var bas := yaw_basis(at[1])
		batch_add("fence_rail", _fence_rail(), Transform3D(bas, base + Vector3(0, FENCE_H - 0.1, 0)))
		batch_add("fence_rail", _fence_rail(), Transform3D(bas, base + Vector3(0, FENCE_H * 0.5, 0)))


func _stair_near(s: float, half: float) -> bool:
	for ss in rep.data.get("stairs", []):
		if absf(s - float(ss)) < half + 1.0:
			return true
	return false


## Road markings along one segment: median double yellows, lane and edge lines, the parking T
## marks, and at a stop junction the stop lines and the crosswalk.
func _paint_segment(i: int, in_ring: bool) -> void:
	var j := i + 1
	var a: Dictionary = rep.sec[i]
	var b: Dictionary = rep.sec[j]
	var s0 := rep.run[i]
	var s1 := rep.run[j]
	var s := (s0 + s1) * 0.5
	var y := PAINT_LIFT
	var ring := _near_ring((rep.pts[i] + rep.pts[j]) * 0.5, 1.5)
	if not ring.is_empty():
		return
	var raised := float(a.median_raised) + float(b.median_raised) > 1.0
	var mw0 := float(a.median)
	var mw1 := float(b.median)
	if not raised:
		if mw0 > 0.5:
			for side: float in [-1.0, 1.0]:
				for off: float in [0.05, 0.25]:
					_line(i, side * (mw0 - off), side * (mw1 - off), 0.1, YELLOW, y)
		else:
			for off: float in [-0.1, 0.1]:
				_line(i, off, off, 0.1, YELLOW, y)
	var lanes := int(round((float(a.lanes) + float(b.lanes)) * 0.5))
	for side: float in [-1.0, 1.0]:
		for k in range(1, lanes):
			var o0 := side * (mw0 + float(a.lane_w) * k)
			var o1 := side * (mw1 + float(b.lane_w) * k)
			_line(i, o0, o1, 0.1, WHITE, y)
		var park0: float = a.park_w if side < 0.0 else a.park_e
		var park1: float = b.park_w if side < 0.0 else b.park_e
		if park0 > 0.5 and park1 > 0.5:
			var e0 := side * (mw0 + float(a.lane_w) * float(a.lanes))
			var e1 := side * (mw1 + float(b.lane_w) * float(b.lanes))
			_line(i, e0, e1, 0.12, WHITE, y)
			# T marks at the stall ends.
			var k0 := ceili(s0 / STALL)
			var k1 := floori(s1 / STALL)
			for k in range(k0, k1 + 1):
				var sk := float(k) * STALL
				if not _mouth_at(sk, 5.0).is_empty():
					continue
				var at := rep.at_s(sk)
				var sd: Dictionary = at[3]
				var edge := side * (float(sd.median) + float(sd.lane_w) * float(sd.lanes))
				var kerb: float = sd.kerb_w if side < 0.0 else sd.kerb_e
				_mark(at, edge, kerb - side * 0.35, 0.1, WHITE, y)
				_mark_along(at, edge, 0.35, 0.1, WHITE, y)
	var m := _mouth_at(s, 7.0)
	if not m.is_empty() and m.stop:
		_crossing(i, m)


## A continuous painted line along segment i at lateral o0 -> o1, `w` wide.
func _line(i: int, o0: float, o1: float, w: float, col: Color, y: float) -> void:
	band("paint", i, o0 - w * 0.5, o0 + w * 0.5, o1 - w * 0.5, o1 + w * 0.5, y, col, false)


## A mark straight across the road at a path point, from lateral oa to ob, `w` wide along the road.
func _mark(at: Array, oa: float, ob: float, w: float, col: Color, y: float) -> void:
	var p: Vector2 = at[0]
	var d: Vector2 = at[1]
	var l := ReplicaAreas.left_of(d)
	var h: float = float(at[2]) + y
	var c0 := p + l * oa
	var c1 := p + l * ob
	var dw := d * (w * 0.5)
	quad("paint", Vector3(c0.x - dw.x, h, c0.y - dw.y), Vector3(c1.x - dw.x, h, c1.y - dw.y),
		Vector3(c1.x + dw.x, h, c1.y + dw.y), Vector3(c0.x + dw.x, h, c0.y + dw.y), col, Vector3.UP)


## A short mark along the road at lateral o, `length` long.
func _mark_along(at: Array, o: float, length: float, w: float, col: Color, y: float) -> void:
	var p: Vector2 = at[0]
	var d: Vector2 = at[1]
	var l := ReplicaAreas.left_of(d)
	var h: float = float(at[2]) + y
	var c := p + l * o
	var dl := d * (length * 0.5)
	var lw := l * (w * 0.5)
	quad("paint", Vector3(c.x - dl.x - lw.x, h, c.y - dl.y - lw.y), Vector3(c.x + dl.x - lw.x, h, c.y + dl.y - lw.y),
		Vector3(c.x + dl.x + lw.x, h, c.y + dl.y + lw.y), Vector3(c.x - dl.x + lw.x, h, c.y - dl.y + lw.y), col, Vector3.UP)


## A stop junction: continental crosswalk across the route just south of the mouth, stop lines
## ahead of it both ways. Drawn once, by the segment the crossing's centre falls in.
func _crossing(i: int, m: Dictionary) -> void:
	var cs: float = float(m.s) + float(m.width) * 0.5 + 2.5
	if cs < rep.run[i] or cs >= rep.run[i + 1]:
		return
	var at := rep.at_s(cs)
	var sd: Dictionary = at[3]
	var y := PAINT_LIFT
	var o := float(sd.kerb_w) + 0.8
	while o < float(sd.kerb_e) - 0.8:
		# Bars along the road, 3 m long, 0.6 m wide, 1.2 m apart across it.
		_mark_along(at, o, 3.0, 0.6, WHITE, y)
		o += 1.2
	for side: float in [-1.0, 1.0]:
		var sat := rep.at_s(cs - side * 3.2)
		var sdd: Dictionary = sat[3]
		# Southbound traffic (west half) stops north of the crossing, northbound south of it.
		var oa := -float(sdd.median) if side > 0.0 else float(sdd.median)
		var ob: float = (float(sdd.kerb_w) + float(sdd.park_w)) if side > 0.0 else (float(sdd.kerb_e) - float(sdd.park_e))
		_mark(sat, oa, ob, 0.45, WHITE, y)


func _paint_hill(i: int) -> void:
	var a: Dictionary = rep.sec[i]
	var b: Dictionary = rep.sec[i + 1]
	for off: float in [-0.1, 0.1]:
		_line(i, off, off, 0.1, YELLOW, PAINT_LIFT)
	for side: float in [-1.0, 1.0]:
		var o0 := side * (float(a.median) + float(a.lane_w) + 0.1)
		var o1 := side * (float(b.median) + float(b.lane_w) + 0.1)
		_line(i, o0, o1, 0.12, WHITE, PAINT_LIFT)


## A side street the replica owns (Knob Hill Ave, Avenue I): carriageway, kerbs, pavements and a
## centre line, at the height of the ground under it so it meets the seeded grid it runs into.
func _street(st_: Dictionary) -> void:
	var sp: PackedVector2Array = st_.pts
	var sd: Dictionary = st_.section
	var d: Vector2 = st_.dir
	var l := ReplicaAreas.left_of(d)
	# Off the route's own kerb (not the ring), the street's first stretch crosses the frontage,
	# which the mouth lays (_segment()); the street itself starts at the back of it.
	var skip := 0.0
	if not st_.has("roundabout"):
		var at0 := rep.at_s(float(st_.def.s))
		var sd0: Dictionary = at0[3]
		skip = float(sd0.east_back) - float(sd0.kerb_e)
	for k in sp.size() - 1:
		var a0 := sp[k]
		var a1 := sp[k + 1]
		var d1 := a1.distance_to(sp[0])
		if d1 <= skip + 0.01:
			continue
		if a0.distance_to(sp[0]) < skip:
			a0 = sp[0] + (a1 - sp[0]).normalized() * skip
		var mid := (a0 + a1) * 0.5
		if not area.has_point(mid):
			continue
		var ring := _near_ring(mid, 0.0)
		var y0 := chunk._gy(a0.x, a0.y) + CityChunk.ROAD_TOP
		var y1 := chunk._gy(a1.x, a1.y) + CityChunk.ROAD_TOP
		var pt := func(q: Vector2, o: float, y: float) -> Vector3:
			var r := q + l * o
			return Vector3(r.x, y, r.y)
		quad("asphalt", pt.call(a0, sd.kerb_w, y0), pt.call(a0, sd.kerb_e, y0), pt.call(a1, sd.kerb_e, y1), pt.call(a1, sd.kerb_w, y1), Color.WHITE, Vector3.UP, true)
		if not ring.is_empty() or (skip <= 0.0 and mid.distance_to(sp[0]) < 14.0):
			continue
		for side: float in [-1.0, 1.0]:
			var kerb: float = sd.kerb_e if side > 0.0 else sd.kerb_w
			var edge: float = sd.walk_e_edge if side > 0.0 else sd.walk_w_edge
			quad("concrete", pt.call(a0, kerb, y0 + 0.15), pt.call(a0, edge, y0 + 0.15), pt.call(a1, edge, y1 + 0.15), pt.call(a1, kerb, y1 + 0.15), Color.WHITE, Vector3.UP, true)
			var n := Vector3(l.x, 0, l.y) * -side
			quad("concrete", pt.call(a0, kerb, y0), pt.call(a1, kerb, y1), pt.call(a1, kerb, y1 + 0.15), pt.call(a0, kerb, y0 + 0.15), Color.WHITE, n, true)
		for off: float in [-0.1, 0.1]:
			quad("paint", pt.call(a0, off - 0.05, y0 + PAINT_LIFT), pt.call(a0, off + 0.05, y0 + PAINT_LIFT), pt.call(a1, off + 0.05, y1 + PAINT_LIFT), pt.call(a1, off - 0.05, y1 + PAINT_LIFT), YELLOW, Vector3.UP)


# --- Features: the roundabout, the car park, the stairs --------------------------------------------

func _features_step() -> void:
	for ra in rep.roundabouts:
		if area.has_point(ra.center):
			_roundabout(ra)
	var cp: Dictionary = rep.data.get("car_park", {})
	if not cp.is_empty():
		var frame := _car_park_frame(cp)
		if area.has_point(frame.centre):
			_car_park(cp, frame)
	for ss in rep.data.get("stairs", []):
		var at := rep.at_s(float(ss))
		if area.has_point(at[0]):
			_stairs(at)


## The roundabout: circulating ring, mountable apron and planted central island, a kerbed
## pavement round the outside between the legs, splitter islands, yield lines.
func _roundabout(ra: Dictionary) -> void:
	var c: Vector2 = ra.center
	var r_out: float = ra.r_out
	var r_is: float = ra.r_island
	var top: float = rep.top[int(ra.index)]
	var n := 48
	var legs := _ring_legs(ra)
	for k in n:
		var a0 := TAU * k / n
		var a1 := TAU * (k + 1) / n
		var u0 := Vector2(cos(a0), sin(a0))
		var u1 := Vector2(cos(a1), sin(a1))
		var ring := func(r: float, u: Vector2, y: float) -> Vector3:
			return Vector3(c.x + u.x * r, top + y, c.y + u.y * r)
		# The ring a few millimetres over the legs' own carriageway, which runs underneath it.
		quad("asphalt", ring.call(r_is + 1.6, u0, 0.006), ring.call(r_out, u0, 0.006), ring.call(r_out, u1, 0.006), ring.call(r_is + 1.6, u1, 0.006), Color.WHITE, Vector3.UP, true)
		quad("concrete", ring.call(r_is, u0, 0.08), ring.call(r_is + 1.6, u0, 0.08), ring.call(r_is + 1.6, u1, 0.08), ring.call(r_is, u1, 0.08), Color(0.8, 0.72, 0.62), Vector3.UP, true)
		quad("concrete", ring.call(r_is, u0, 0.0), ring.call(r_is, u1, 0.0), ring.call(r_is, u1, 0.32), ring.call(r_is, u0, 0.32), Color.WHITE, Vector3(u0.x, 0, u0.y), true)
		quad("median", ring.call(0.0, u0, 0.34), ring.call(r_is, u0, 0.32), ring.call(r_is, u1, 0.32), ring.call(0.0, u1, 0.34), Color.WHITE, Vector3.UP, true)
		# Outside the ring, between the legs: kerb, pavement, a planted corner.
		var um := (u0 + u1).normalized()
		var outside := c + um * (r_out + 2.0)
		if _on_leg(outside, legs, 1.0):
			continue
		quad("concrete", ring.call(r_out, u0, 0.0), ring.call(r_out, u1, 0.0), ring.call(r_out, u1, 0.15), ring.call(r_out, u0, 0.15), Color.WHITE, Vector3(-u0.x, 0, -u0.y), true)
		quad("concrete", ring.call(r_out, u0, 0.15), ring.call(r_out + 3.5, u0, 0.15), ring.call(r_out + 3.5, u1, 0.15), ring.call(r_out, u1, 0.15), Color.WHITE, Vector3.UP, true)
		quad("median", ring.call(r_out + 3.5, u0, 0.22), ring.call(r_out + 12.0, u0, 0.22), ring.call(r_out + 12.0, u1, 0.22), ring.call(r_out + 3.5, u1, 0.22), Color.WHITE, Vector3.UP, true)
	# Yield lines ("shark teeth" as a dashed line) across each entry.
	for leg in legs:
		var d: Vector2 = leg.dir
		var l := ReplicaAreas.left_of(d)
		var p := c + d * (r_out + 0.8)
		for k in 6:
			var o := -float(leg.half) + 0.5 + k * (float(leg.half) - 1.0) / 5.0
			var q := p + l * o * -1.0
			var dl := l * 0.3
			var dd := d * 0.25
			var h := top + PAINT_LIFT
			quad("paint", Vector3(q.x - dl.x - dd.x, h, q.y - dl.y - dd.y), Vector3(q.x + dl.x - dd.x, h, q.y + dl.y - dd.y),
				Vector3(q.x + dl.x + dd.x, h, q.y + dl.y + dd.y), Vector3(q.x - dl.x + dd.x, h, q.y - dl.y + dd.y), WHITE, Vector3.UP)
	if not full:
		return
	# A palm and low planting on the island, the chevrons facing each entry.
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([plan.seed, "roundabout", int(c.x), int(c.y)])
	chunk._add_palm(rel(Vector3(c.x + 1.5, top + 0.34, c.y - 1.0)), rng, false)
	for k in 10:
		var a := rng.randf() * TAU
		var r := rng.randf_range(2.0, r_is - 1.5)
		var q := c + Vector2(cos(a), sin(a)) * r
		batch_add("bush_%d" % (k % 4), PropFactory.model_bush(k % 4), Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(q.x, top + 0.34, q.y)))
	for leg in legs:
		var d: Vector2 = leg.dir
		var at := c + d * (r_is - 0.8)
		ReplicaSigns.chevron(self, Vector3(at.x, top + 0.34, at.y), d, 2)


## The legs of a roundabout: the route coming in and going out, and its stubs: [{dir, half}].
func _ring_legs(ra: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var i := int(ra.index)
	var sd_in: Dictionary = rep.sec[maxi(i - 3, 0)]
	var sd_out: Dictionary = rep.sec[mini(i + 3, rep.sec.size() - 1)]
	out.append({"dir": -(ra.in_dir as Vector2), "half": maxf(-float(sd_in.kerb_w), float(sd_in.kerb_e))})
	out.append({"dir": ra.out_dir, "half": maxf(-float(sd_out.kerb_w), float(sd_out.kerb_e))})
	for st_ in rep.streets:
		if st_.get("roundabout", {}) == ra and st_.has("dir"):
			var sd: Dictionary = st_.section
			out.append({"dir": st_.dir, "half": maxf(-float(sd.kerb_w), float(sd.kerb_e))})
	return out


func _on_leg(p: Vector2, legs: Array[Dictionary], pad: float) -> bool:
	for ra in rep.roundabouts:
		var c: Vector2 = ra.center
		for leg in legs:
			var d: Vector2 = leg.dir
			var q := p - c
			var along := q.dot(d)
			if along > 0.0 and absf(q.dot(ReplicaAreas.left_of(d))) < float(leg.half) + pad:
				return true
	return false


## The beach car park's frame: origin at the tangent point `s`, `along` ahead, `lateral` left.
func _car_park_frame(cp: Dictionary) -> Dictionary:
	var at := rep.at_s(float(cp.s))
	var p: Vector2 = at[0]
	var d: Vector2 = at[1]
	var l := ReplicaAreas.left_of(d)
	var al: Array = cp.along
	var la: Array = cp.lateral
	var centre := p + d * ((float(al[0]) + float(al[1])) * 0.5) + l * ((float(la[0]) + float(la[1])) * 0.5)
	return {"p": p, "d": d, "l": l, "centre": centre}


func _car_park(cp: Dictionary, fr: Dictionary) -> void:
	var p: Vector2 = fr.p
	var d: Vector2 = fr.d
	var l: Vector2 = fr.l
	var al: Array = cp.along
	var la: Array = cp.lateral
	# Heights straight from the lot's own level (ReplicaAreas.car_park_level()), not through the
	# chunk's 3 m relief lattice: the platform ends in a sea wall, and interpolated across it the
	# lot's seaward edge drooped toward the sand.
	var pt := func(a: float, o: float, y: float) -> Vector3:
		var q := p + d * a + l * o
		var lv := rep.car_park_level(q)
		var g := (lv - CityChunk.SIDEWALK_TOP - 0.01) if lv > -INF else chunk._gy(q.x, q.y)
		return Vector3(q.x, g + y, q.y)
	var dv := Vector3(d.x, 0, d.y)
	var lv3 := Vector3(l.x, 0, l.y)
	var a := float(al[0])
	while a < float(al[1]) - 0.01:
		var a1 := minf(a + 10.0, float(al[1]))
		quad("asphalt", pt.call(a, la[0], 0.26), pt.call(a, la[1], 0.26), pt.call(a1, la[1], 0.26), pt.call(a1, la[0], 0.26), Color.WHITE, Vector3.UP, true)
		# The sea wall along the seaward side, from the sand up to a parapet over the lot.
		var cw := pt.call((a + a1) * 0.5, float(la[0]) - 0.25, 0.7) as Vector3
		box("concrete", cw, dv * ((a1 - a) * 0.5), Vector3(0, 0.45, 0), lv3 * 0.25, Color.WHITE, true)
		var w0: Vector3 = pt.call(a, float(la[0]) - 0.5, 0.26)
		var w1: Vector3 = pt.call(a1, float(la[0]) - 0.5, 0.26)
		quad("concrete", Vector3(w0.x, 0.2, w0.z), Vector3(w1.x, 0.2, w1.z), w1, w0, Color(0.9, 0.89, 0.86), -lv3, true)
		# The planted slope between the lot and the road, at the lot's level where it is flat and
		# on the road's own ground where that is higher.
		var e0 := _lot_lawn_end(p, d, l, a, float(la[1]))
		var e1 := _lot_lawn_end(p, d, l, a1, float(la[1]))
		if e0 > float(la[1]) + 0.5 or e1 > float(la[1]) + 0.5:
			var n := maxi(1, ceili(maxf(e0, e1) - float(la[1])) / 3)
			for k in n:
				var f0 := float(k) / n
				var f1 := float(k + 1) / n
				var qa := p + d * a + l * lerpf(float(la[1]), e0, f0)
				var qb := p + d * a + l * lerpf(float(la[1]), e0, f1)
				var qc := p + d * a1 + l * lerpf(float(la[1]), e1, f1)
				var qd := p + d * a1 + l * lerpf(float(la[1]), e1, f0)
				var h := func(q: Vector2) -> Vector3:
					return Vector3(q.x, chunk._gy(q.x, q.y) + CityChunk.SIDEWALK_TOP + 0.02, q.y)
				quad("median", h.call(qa), h.call(qb), h.call(qc), h.call(qd), Color.WHITE, Vector3.UP, true)
		a = a1
	# The lot's south end, where it stands over the sand.
	var s0: Vector3 = pt.call(float(al[1]), float(la[0]) - 0.5, 0.26)
	var s1: Vector3 = pt.call(float(al[1]), float(la[1]), 0.26)
	quad("concrete", Vector3(s0.x, 0.2, s0.z), Vector3(s1.x, 0.2, s1.z), s1, s0, Color(0.9, 0.89, 0.86), dv, true)
	# Nose-in stalls along the sea wall, facing the ocean.
	var sw: float = cp.stall_w
	var sdp: float = cp.stall_d
	var k := 0
	a = float(al[0]) + 3.0
	while a < float(al[1]) - 3.0:
		var o0: float = float(la[0])
		var o1: float = o0 + sdp
		var q0: Vector3 = pt.call(a, o0 + 0.3, 0.26 + PAINT_LIFT)
		var q1: Vector3 = pt.call(a, o1, 0.26 + PAINT_LIFT)
		var w := dv * 0.05
		quad("paint", q0 - w, q1 - w, q1 + w, q0 + w, WHITE, Vector3.UP)
		if full and hash01([plan.seed, "lotcar", k]) < LOT_ODDS and a + sw < float(al[1]) - 3.0:
			var cq: Vector3 = pt.call(a + sw * 0.5, o0 + sdp * 0.5 + 0.2, 0.26)
			_lot_cars.append([cq, atan2(l.x, l.y), hash([plan.seed, "lotcar", k])])
		a += sw
		k += 1
	if full:
		# A lamp and a chevron on the island between the lot and the road (the photo at the curve);
		# the curve bends left, so the chevron points left.
		var ia: Vector3 = pt.call(float(al[0]) + 40.0, float(la[1]) + 1.5, 0.3)
		_lamp(Vector3(ia.x, ia.y - 0.15, ia.z), -Vector2(l.x, l.y))
		ReplicaSigns.chevron(self, pt.call(float(al[0]) + 55.0, float(la[1]) + 1.2, 0.26), -d, 1, false)


## How far east of the lot (lateral, in its frame) the lot's own ground runs at distance a along it.
func _lot_lawn_end(p: Vector2, d: Vector2, l: Vector2, a: float, from: float) -> float:
	var o := from
	while o < from + 60.0:
		if rep.car_park_level(p + d * a + l * (o + 0.5)) == -INF:
			break
		o += 0.5
	return o


var _lot_cars: Array = []


## Concrete stairs from the walkway down the bluff face to the sand, with a landing across the
## verge, side walls and pipe handrails.
func _stairs(at: Array) -> void:
	var p: Vector2 = at[0]
	var d: Vector2 = at[1]
	var sd: Dictionary = at[3]
	var l := ReplicaAreas.left_of(d)
	var top_y: float = float(at[2]) + 0.2
	var edge: float = sd.edge
	var toe: float = sd.toe
	var bottom_y := 0.5
	var steps := maxi(4, ceili((top_y - bottom_y) / 0.175))
	var run := (edge - toe) / float(steps)
	var half := 1.1
	var dv := Vector3(d.x, 0, d.y)
	var lv := Vector3(l.x, 0, l.y)
	for k in steps:
		var o0 := edge - run * k
		var o1 := o0 - run
		var y0 := top_y - (top_y - bottom_y) * float(k) / steps
		var y1 := top_y - (top_y - bottom_y) * float(k + 1) / steps
		var c0 := p + l * o0
		var c1 := p + l * o1
		var t0 := Vector3(c0.x, y1, c0.y)
		var t1 := Vector3(c1.x, y1, c1.y)
		# Tread and riser.
		quad("concrete", t0 - dv * half, t0 + dv * half, t1 + dv * half, t1 - dv * half, Color.WHITE, Vector3.UP)
		quad("concrete", Vector3(c0.x, y0, c0.y) - dv * half, Vector3(c0.x, y0, c0.y) + dv * half, t0 + dv * half, t0 - dv * half, Color.WHITE, -lv)
	for side: float in [-1.0, 1.0]:
		# Side walls from the top to the sand, and a rail on posts.
		var a := p + l * edge + d * (side * (half + 0.12))
		var b := p + l * toe + d * (side * (half + 0.12))
		var mid := Vector3((a.x + b.x) * 0.5, (top_y + bottom_y) * 0.5, (a.y + b.y) * 0.5)
		var along := Vector3(b.x - a.x, bottom_y - top_y, b.y - a.y) * 0.5
		box("concrete", mid + Vector3(0, 0.15, 0), along, Vector3(0, 0.5, 0), dv * 0.12, Color(0.9, 0.9, 0.88))
		if full:
			for k in 5:
				var t := float(k) / 4.0
				var q := Vector3(lerpf(a.x, b.x, t), lerpf(top_y, bottom_y, t) + 0.55, lerpf(a.y, b.y, t))
				batch_add("stair_post", _stair_post(), Transform3D(Basis(), q))
			var rail_basis := Basis(Vector3(b.x - a.x, bottom_y - top_y, b.y - a.y), Vector3.UP, dv * 0.04).orthonormalized()
			rail_basis = Basis(rail_basis.x * Vector3(b.x - a.x, bottom_y - top_y, b.y - a.y).length(), rail_basis.y * 0.04, rail_basis.z * 0.04)
			batch_add("stair_rail", PropFactory.unit_box(), Transform3D(rail_basis, mid + Vector3(0, 1.0, 0)), Color(0.35, 0.36, 0.37))
	# A ramp the player can actually walk, under the steps.
	var ramp := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	var slope := Vector3(-l.x * (edge - toe), bottom_y - top_y, -l.y * (edge - toe))
	bx.size = Vector3(half * 2.0, 0.3, slope.length())
	ramp.shape = bx
	var fwd := slope.normalized()
	var up := dv.cross(fwd).normalized()
	if up.y < 0.0:
		up = -up
	var c := p + l * ((edge + toe) * 0.5)
	ramp.transform = Transform3D(Basis(dv, up, -fwd), Vector3(c.x, (top_y + bottom_y) * 0.5 - 0.15, c.y))
	_body_node().add_child(ramp)


# --- Polygons ------------------------------------------------------------------------------------
# Where the replica meets the seeded grid nothing may overlap or leave a gap, and the two do not
# share a lattice: the route runs at its own heading and the grid is axis-aligned. So those edges
# are cut exactly, as 2D polygons (Geometry2D), and laid at the height of whichever side owns them.

## A quad along segment i between lateral lines oa..ob at each end, as a 2D polygon.
func _seg_poly(i: int, oa0: float, ob0: float, oa1: float, ob1: float) -> PackedVector2Array:
	var j := i + 1
	var l0 := ReplicaAreas.left_of(rep.dirs[i])
	var l1 := ReplicaAreas.left_of(rep.dirs[j])
	return PackedVector2Array([rep.pts[i] + l0 * oa0, rep.pts[i] + l0 * ob0, rep.pts[j] + l1 * ob1, rep.pts[j] + l1 * oa1])


## Height along segment i (the route's cross-section is level): func(p, y) -> top here + y.
func _seg_height(i: int) -> Callable:
	var a: Vector2 = rep.pts[i]
	var d: Vector2 = rep.pts[i + 1] - a
	var len2 := maxf(d.length_squared(), 0.0001)
	var t0: float = rep.top[i]
	var t1: float = rep.top[i + 1]
	return func(p: Vector2, y: float) -> float:
		return lerpf(t0, t1, clampf((p - a).dot(d) / len2, 0.0, 1.0)) + y


## The chunk's own ground under p, plus y: for everything laid on the seeded side.
func _ground_height(p: Vector2, y: float) -> float:
	return chunk._gy(p.x, p.y) + y


## Fills a 2D polygon, flat side up, at hf(p) per vertex.
func _poly_fill(name: String, poly: PackedVector2Array, hf: Callable, col: Color, collide: bool) -> void:
	if poly.size() < 3:
		return
	var idx := Geometry2D.triangulate_polygon(poly)
	for k in range(0, idx.size(), 3):
		var a := poly[idx[k]]
		var b2 := poly[idx[k + 1]]
		var c := poly[idx[k + 2]]
		tri(name, Vector3(a.x, hf.call(a), a.y), Vector3(b2.x, hf.call(b2), b2.y), Vector3(c.x, hf.call(c), c.y), col, Vector3.UP, collide)


## The grid streets whose mouths reach the route within `pad` metres of path distance `s`.
func _mouths_near(s: float, pad: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for m in rep.mouths(plan):
		if absf(s - float(m.s)) < float(m.width) * 0.5 + plan.sidewalk_width + pad:
			out.append(m)
	return out


## A grid street's mouth as world-aligned rects, reaching well past the corridor on both sides:
## [carriageway, north pavement, south pavement, all three].
func _mouth_rects(m: Dictionary) -> Array[PackedVector2Array]:
	var c: Vector2 = m.origin
	var d: Vector2 = (m.dir as Vector2).normalized()
	var n := d.orthogonal()
	var hw: float = float(m.width) * 0.5
	var sw: float = m.sw
	var r := func(a: float, b: float) -> PackedVector2Array:
		return PackedVector2Array([c - d * 400.0 + n * a, c + d * 400.0 + n * a, c + d * 400.0 + n * b, c - d * 400.0 + n * b])
	var out: Array[PackedVector2Array] = [r.call(-hw, hw), r.call(-hw - sw, -hw), r.call(hw, hw + sw), r.call(-hw - sw, hw + sw)]
	return out


## Where lateral line `key` of the route crosses the world line z = zc, near path distance s.
func _line_at_z(key: String, zc: float, s: float) -> Vector3:
	var p := Vector2.ZERO
	var top := 0.0
	for it in 5:
		var at := rep.at_s(s)
		var sd: Dictionary = at[3]
		var d: Vector2 = at[1]
		p = (at[0] as Vector2) + ReplicaAreas.left_of(d) * float(sd[key])
		top = at[2]
		if absf(d.y) < 0.2 or absf(p.y - zc) < 0.005:
			break
		s += (zc - p.y) / d.y
	return Vector3(p.x, top, zc)


## The kerbs along a grid street's mouth, from the route's kerb to the back of the frontage.
func _mouth_kerbs(m: Dictionary) -> void:
	var hw: float = float(m.width) * 0.5
	var d: Vector2 = (m.dir as Vector2).normalized()
	var n := d.orthogonal()
	for side: float in [-1.0, 1.0]:
		var a := _edge_at_lateral(m, side * hw, "kerb_e")
		var e := _edge_at_lateral(m, side * hw, "east_back")
		quad("concrete", a, e, e + Vector3(0, 0.15, 0), a + Vector3(0, 0.15, 0), Color(0.92, 0.92, 0.92), Vector3(-n.x, 0.0, -n.y) * side, true)


## Where the mouth's edge line `off` metres to the side of its centre line crosses the route's
## lateral line `key`: solved along the edge line (secant steps on the offset nearest() reads).
func _edge_at_lateral(m: Dictionary, off: float, key: String) -> Vector3:
	var c: Vector2 = m.origin
	var d: Vector2 = (m.dir as Vector2).normalized()
	var base := c + d.orthogonal() * off
	var t := 0.0
	var p := base
	var top := 0.0
	for it in 8:
		p = base + d * t
		var hit := rep.nearest(p, 250.0)
		if hit.is_empty():
			break
		var sd: Dictionary = rep.sec[int(hit.i)]
		top = rep.at_s(float(hit.s))[2]
		var err := float(sd[key]) - float(hit.o)
		if absf(err) < 0.005:
			break
		# The street runs close to square off the route, so its offset grows about 1:1 with t.
		t += err / maxf(absf(d.dot(ReplicaAreas.left_of(rep.dirs[int(hit.i)]))), 0.3)
	return Vector3(p.x, top, p.y)


## A wall along segment i (see wall()) with the stretches inside any of the `cuts` polygons
## left out.
func _wall_cut(name: String, i: int, o0: float, o1: float, y0: float, y1: float, col: Color, side: float, cuts: Array[PackedVector2Array]) -> void:
	var j := i + 1
	var a := P(i, o0, 0.0)
	var b3 := P(j, o1, 0.0)
	var a2 := Vector2(a.x, a.z)
	var b2 := Vector2(b3.x, b3.z)
	var pieces: Array[PackedVector2Array] = [PackedVector2Array([a2, b2])]
	for c in cuts:
		var next: Array[PackedVector2Array] = []
		for pc in pieces:
			next.append_array(Geometry2D.clip_polyline_with_polygon(pc, c))
		pieces = next
	var n := Vector3(ReplicaAreas.left_of(rep.dirs[i]).x, 0.0, ReplicaAreas.left_of(rep.dirs[i]).y) * side
	var len2 := maxf(a2.distance_squared_to(b2), 0.0001)
	for pc in pieces:
		for k in pc.size() - 1:
			var t0 := clampf((pc[k] - a2).dot(b2 - a2) / len2, 0.0, 1.0)
			var t1 := clampf((pc[k + 1] - a2).dot(b2 - a2) / len2, 0.0, 1.0)
			if absf(t1 - t0) < 0.002:
				continue
			var p0 := a.lerp(b3, t0)
			var p1 := a.lerp(b3, t1)
			quad(name, p0 + Vector3(0, y0, 0), p1 + Vector3(0, y0, 0), p1 + Vector3(0, y1, 0), p0 + Vector3(0, y1, 0), col, n, true)


## The corridor's own pieces near p as polygons - exactly the strips ReplicaAreas.blocks_grid()
## tests: the route between consecutive samples, each roundabout, each side street.
func _corridor_polys(p: Vector2, reach: float) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	var hit := rep.nearest(p, 200.0)
	if not hit.is_empty():
		var i0 := int(hit.i)
		var span := int(ceil(reach / ReplicaAreas.STEP)) + 3
		for i in range(maxi(0, i0 - span), mini(rep.pts.size() - 1, i0 + span)):
			var a: Dictionary = rep.sec[i]
			var b2: Dictionary = rep.sec[i + 1]
			if rep.run[i] <= rep.s_city_end + 1.0:
				var w0: float = float(a.water) - 30.0 if float(a.coast) > 0.5 else float(a.walk_w_edge)
				var w1: float = float(b2.water) - 30.0 if float(b2.coast) > 0.5 else float(b2.walk_w_edge)
				out.append(_seg_poly(i, w0, a.east_back, w1, b2.east_back))
			else:
				out.append(_seg_poly(i, -float(a.kerb_e) - 3.0, float(a.kerb_e) + 3.0, -float(b2.kerb_e) - 3.0, float(b2.kerb_e) + 3.0))
			if i == 0:
				# The four metres past the north end the corridor also holds (the end's pavement).
				var d0 := rep.dirs[0]
				var l0 := ReplicaAreas.left_of(d0)
				var p0 := rep.pts[0]
				var w0: float = float(a.walk_w_edge)
				var w1: float = float(a.walk_e_edge)
				out.append(PackedVector2Array([p0 + l0 * w0 - d0 * 4.0, p0 + l0 * w1 - d0 * 4.0, p0 + l0 * w1, p0 + l0 * w0]))
	for ra in rep.roundabouts:
		var c: Vector2 = ra.center
		var r := float(ra.r_out) + 12.0
		if p.distance_to(c) < r + reach:
			var ring := PackedVector2Array()
			for k in 40:
				ring.append(c + Vector2(cos(TAU * k / 40.0), sin(TAU * k / 40.0)) * (r / cos(PI / 40.0)))
			out.append(ring)
	for st_ in rep.streets:
		if not st_.has("pts"):
			continue
		var sp: PackedVector2Array = st_.pts
		var half: float = float(st_.section.walk_e_edge)
		for k in sp.size() - 1:
			if Geometry2D.get_closest_point_to_segment(p, sp[k], sp[k + 1]).distance_to(p) > half + reach:
				continue
			var d := (sp[k + 1] - sp[k]).normalized()
			var n := d.orthogonal() * half
			out.append(PackedVector2Array([sp[k] - n - d * 0.01, sp[k + 1] - n + d * 0.01, sp[k + 1] + n + d * 0.01, sp[k] + n - d * 0.01]))
	return out


## `poly` with the corridor cut out of it.
func _clip_out(poly: PackedVector2Array) -> Array[PackedVector2Array]:
	var c := Vector2.ZERO
	var r := 0.0
	for q in poly:
		c += q
	c /= poly.size()
	for q in poly:
		r = maxf(r, q.distance_to(c))
	var result: Array[PackedVector2Array] = [poly]
	for cp in _corridor_polys(c, r):
		var next: Array[PackedVector2Array] = []
		for piece in result:
			var cut := Geometry2D.clip_polygons(piece, cp)
			if cut.size() > 1:
				# Two polygons back with one of the other winding is a hole: the cutter is inside
				# the piece, which the cells here are too small for. Keep the piece whole.
				var holes := false
				for q in cut:
					if Geometry2D.is_polygon_clockwise(q) != Geometry2D.is_polygon_clockwise(piece):
						holes = true
				if holes:
					next.append(piece)
					continue
			next.append_array(cut)
		result = next
		if result.is_empty():
			break
	return result


# --- The seeded grid on a replica block -----------------------------------------------------------

## A replica chunk still owns the grid roads on its +X and +Z sides and their junction: laid as
## the chunk would lay them (the same road look, relief and markings) but cut where the corridor
## is, so a street runs up to the frontage's back lane and stops, or on into a mouth.
func _grid_steps() -> Array[Callable]:
	var out: Array[Callable] = [_grid_road.bind(CityPlan.AXIS_X), _grid_road.bind(CityPlan.AXIS_Z), _grid_corner]
	return out


const GRID_PIECE := 6.0
var _mat_override := {}


func _grid_road(axis: int) -> void:
	var block := plan.block(chunk.ix, chunk.iz)
	var rect: Rect2 = block.rect
	var params: Dictionary = CityPlan.DISTRICTS[block.district]
	var index := (chunk.ix if axis == CityPlan.AXIS_X else chunk.iz) + 1
	var look := chunk._road_look(axis, index, params)
	var name := "grid_%d" % axis
	_mat_override[name] = look.material
	var c := plan.road_pos(axis, index)
	var w := plan.road_width(axis, index)
	var a0 := rect.position.y if axis == CityPlan.AXIS_X else rect.position.x
	var a1 := rect.end.y if axis == CityPlan.AXIS_X else rect.end.x
	var n := maxi(1, ceili((a1 - a0) / GRID_PIECE))
	var runs: Array[Vector2] = []
	var run_start := INF
	for k in n:
		var t0 := lerpf(a0, a1, float(k) / n)
		var t1 := lerpf(a0, a1, float(k + 1) / n)
		var piece := _axis_rect(axis, c, w, t0, t1)
		var mid := Vector2(c, (t0 + t1) * 0.5) if axis == CityPlan.AXIS_X else Vector2((t0 + t1) * 0.5, c)
		_grid_piece(name, piece, mid)
		var open := not rep.blocks_grid(mid, 1.5)
		if open and run_start == INF:
			run_start = t0
		if not open and run_start != INF:
			runs.append(Vector2(run_start, t0))
			run_start = INF
	if run_start != INF:
		runs.append(Vector2(run_start, a1))
	if full:
		for r in runs:
			chunk._mark_road(axis == CityPlan.AXIS_X, c, w, r.x, r.y, look)


func _grid_corner() -> void:
	var cx := plan.road_pos(CityPlan.AXIS_X, chunk.ix + 1)
	var wx := plan.road_width(CityPlan.AXIS_X, chunk.ix + 1)
	var cz := plan.road_pos(CityPlan.AXIS_Z, chunk.iz + 1)
	var wz := plan.road_width(CityPlan.AXIS_Z, chunk.iz + 1)
	var poly := PackedVector2Array([Vector2(cx - wx * 0.5, cz - wz * 0.5), Vector2(cx + wx * 0.5, cz - wz * 0.5), Vector2(cx + wx * 0.5, cz + wz * 0.5), Vector2(cx - wx * 0.5, cz + wz * 0.5)])
	_grid_piece("grid_%d" % CityPlan.AXIS_X, poly, Vector2(cx, cz))
	if full and not rep.blocks_grid(Vector2(cx, cz), wx + wz):
		chunk._build_intersection(plan.intersection(chunk.ix + 1, chunk.iz + 1))


func _axis_rect(axis: int, c: float, w: float, t0: float, t1: float) -> PackedVector2Array:
	if axis == CityPlan.AXIS_X:
		return PackedVector2Array([Vector2(c - w * 0.5, t0), Vector2(c + w * 0.5, t0), Vector2(c + w * 0.5, t1), Vector2(c - w * 0.5, t1)])
	return PackedVector2Array([Vector2(t0, c - w * 0.5), Vector2(t1, c - w * 0.5), Vector2(t1, c + w * 0.5), Vector2(t0, c + w * 0.5)])


## One piece of grid road: whole when the corridor is nowhere near it, cut when it is, with a kerb
## face along any cut edge that is not the mouth of a street running on.
func _grid_piece(name: String, poly: PackedVector2Array, mid: Vector2) -> void:
	var hf := _ground_height
	var r := 0.0
	for q in poly:
		r = maxf(r, q.distance_to(mid))
	if not rep.blocks_grid(mid, r + 2.0):
		_poly_fill(name, poly, hf.bind(CityChunk.ROAD_TOP), Color.WHITE, true)
		return
	for q in _clip_out(poly):
		_poly_fill(name, q, hf.bind(CityChunk.ROAD_TOP), Color.WHITE, true)
		_cut_kerbs(q, poly, CityChunk.ROAD_TOP, CityChunk.SIDEWALK_TOP, true)


## Kerb faces along the edges of `q` that the corridor cut (not on the outline of the `whole` it
## was cut from), from y0 up to y1 above the ground, facing into q. `skip_mouths` leaves out an
## edge whose far side is a mouth's carriageway, where the street runs on at the same level.
func _cut_kerbs(q: PackedVector2Array, whole: PackedVector2Array, y0: float, y1: float, skip_mouths: bool) -> void:
	var centre := Vector2.ZERO
	for v in q:
		centre += v
	centre /= q.size()
	for k in q.size():
		var a := q[k]
		var bq := q[(k + 1) % q.size()]
		if a.distance_to(bq) < 0.05:
			continue
		var m := (a + bq) * 0.5
		var on_outline := false
		for e in whole.size():
			var ea := whole[e]
			var eb := whole[(e + 1) % whole.size()]
			if Geometry2D.get_closest_point_to_segment(m, ea, eb).distance_to(m) < 0.02:
				on_outline = true
				break
		if on_outline:
			continue
		var n := (bq - a).orthogonal().normalized()
		if n.dot(centre - m) < 0.0:
			n = -n
		if skip_mouths and _in_mouth_road(m - n * 0.6):
			continue
		var ya := chunk._gy(a.x, a.y)
		var yb := chunk._gy(bq.x, bq.y)
		quad("concrete", Vector3(a.x, ya + y0, a.y), Vector3(bq.x, yb + y0, bq.y), Vector3(bq.x, yb + y1, bq.y), Vector3(a.x, ya + y1, a.y), Color(0.92, 0.92, 0.92), Vector3(n.x, 0.0, n.y), true)


func _in_mouth_road(p: Vector2) -> bool:
	for m in rep.mouths(plan):
		var d: Vector2 = (m.dir as Vector2).normalized()
		if absf((p - (m.origin as Vector2)).dot(d.orthogonal())) < float(m.width) * 0.5 - 0.05:
			var hit := rep.nearest(p, 200.0)
			if not hit.is_empty():
				var sd: Dictionary = rep.sec[int(hit.i)]
				var o: float = hit.o
				if o > float(sd.kerb_e) - 1.0 and o < float(sd.east_back) + 2.0:
					return true
	return false


# --- Backfill ground (replica blocks) ----------------------------------------------------------

## The part of a replica block the corridor leaves: pavement round the edge along the grid streets
## that bound it (with its kerb), yards inside, cut exactly where the corridor begins. A step that
## runs again until it is done, a row of cells at a time (see CityChunk.build_step()).
const BACKFILL_CELL := 4.0
var _bf_row: int = -1
var _bf_flags: Array = []


func _backfill_ground_step() -> bool:
	var b := plan.block(chunk.ix, chunk.iz)
	var rect: Rect2 = b.rect
	var nx := maxi(1, ceili(rect.size.x / BACKFILL_CELL))
	var nz := maxi(1, ceili(rect.size.y / BACKFILL_CELL))
	var vert := func(gx: int, gz: int) -> Vector2:
		return rect.position + Vector2(rect.size.x * gx / nx, rect.size.y * gz / nz)
	var flag_row := func(gz: int) -> PackedByteArray:
		var row := PackedByteArray()
		row.resize(nx + 1)
		for gx in nx + 1:
			row[gx] = 1 if rep.blocks_grid(vert.call(gx, gz), 0.0) else 0
		return row
	if _bf_row < 0:
		_bf_flags = [flag_row.call(0)]
		_bf_row = 0
		return false
	var gz := _bf_row
	_bf_flags.append(flag_row.call(gz + 1))
	var f0: PackedByteArray = _bf_flags[gz]
	var f1: PackedByteArray = _bf_flags[gz + 1]
	var sw: float = plan.sidewalk_width
	var hf := _ground_height
	for gx in nx:
		var n_in := int(f0[gx]) + int(f0[gx + 1]) + int(f1[gx]) + int(f1[gx + 1])
		if n_in == 4:
			continue
		var c0: Vector2 = vert.call(gx, gz)
		var c1: Vector2 = vert.call(gx + 1, gz + 1)
		var cell := PackedVector2Array([c0, Vector2(c1.x, c0.y), c1, Vector2(c0.x, c1.y)])
		var mid := (c0 + c1) * 0.5
		var edge := mid.x < rect.position.x + sw or mid.x > rect.end.x - sw or mid.y < rect.position.y + sw or mid.y > rect.end.y - sw
		var name := "walk" if edge else "yard"
		var pieces: Array[PackedVector2Array] = [cell]
		if n_in > 0 or rep.blocks_grid(mid, BACKFILL_CELL):
			pieces = _clip_out(cell)
		for q in pieces:
			_poly_fill(name, q, hf.bind(CityChunk.SIDEWALK_TOP), Color.WHITE, true)
		# The kerb, where the cell is on the block's edge.
		for e: Array in [[c0, Vector2(c1.x, c0.y), gz == 0], [Vector2(c1.x, c0.y), c1, gx == nx - 1], [c1, Vector2(c0.x, c1.y), gz == nz - 1], [Vector2(c0.x, c1.y), c0, gx == 0]]:
			if not e[2]:
				continue
			for q in pieces:
				_outline_kerb(q, e[0], e[1], mid)
	_bf_row += 1
	if _bf_row >= nz:
		_bf_flags.clear()
		return true
	return false


## The part of polygon q's outline that lies on the block edge a-b, as a kerb face from the road
## up to the pavement, facing away from `inside`.
func _outline_kerb(q: PackedVector2Array, a: Vector2, bq: Vector2, inside: Vector2) -> void:
	for k in q.size():
		var p0 := q[k]
		var p1 := q[(k + 1) % q.size()]
		if p0.distance_to(p1) < 0.05:
			continue
		if Geometry2D.get_closest_point_to_segment(p0, a, bq).distance_to(p0) > 0.02 or Geometry2D.get_closest_point_to_segment(p1, a, bq).distance_to(p1) > 0.02:
			continue
		var n := (p1 - p0).orthogonal().normalized()
		if n.dot(inside - (p0 + p1) * 0.5) > 0.0:
			n = -n
		var y0 := chunk._gy(p0.x, p0.y)
		var y1 := chunk._gy(p1.x, p1.y)
		quad("walk", Vector3(p0.x, y0 + CityChunk.ROAD_TOP, p0.y), Vector3(p1.x, y1 + CityChunk.ROAD_TOP, p1.y), Vector3(p1.x, y1 + CityChunk.SIDEWALK_TOP, p1.y), Vector3(p0.x, y0 + CityChunk.SIDEWALK_TOP, p0.y), Color.WHITE, Vector3(n.x, 0.0, n.y), true)


# --- Street furniture ----------------------------------------------------------------------------

func _furniture_step() -> void:
	var spacing: float = rep.data.get("lamp_spacing", 45.0)
	var lo := INF
	var hi := -INF
	for i in rep.pts.size() - 1:
		if _owned(i):
			lo = minf(lo, rep.run[i])
			hi = maxf(hi, rep.run[i + 1])
	if lo > hi:
		return
	# Lamps on the ocean-side kerb.
	var k0 := ceili((lo - 12.0) / spacing)
	var k1 := floori((hi - 12.0) / spacing)
	for k in range(k0, k1 + 1):
		var s := 12.0 + k * spacing
		if s < lo or s >= hi or s > rep.s_city_end:
			continue
		var at := rep.at_s(s)
		var sd: Dictionary = at[3]
		if float(sd.lamps) < 0.5 or not _near_ring(at[0], 10.0).is_empty() or _stair_near(s, 2.0):
			continue
		var p: Vector2 = (at[0] as Vector2) + ReplicaAreas.left_of(at[1]) * (float(sd.kerb_w) - 0.55)
		_lamp(Vector3(p.x, float(at[2]) + 0.15, p.y), ReplicaAreas.left_of(at[1]))
	# Palms in the east front yards, in the median where it is planted, and on the Paseo.
	var ps: float = rep.data.get("palm_spacing", 17.0)
	var q0 := floori(lo / ps) - 1
	var q1 := ceili(hi / ps) + 1
	for q in range(q0, q1 + 1):
		var h := hash([plan.seed, "yardpalm", q])
		var s := (float(q) + hash01([h, 0]) * 0.8) * ps
		if s < lo or s >= hi or s > rep.s_city_end - 10.0 or s < 20.0:
			continue
		if not _mouth_at(s, 3.0).is_empty():
			continue
		var at := rep.at_s(s)
		var sd: Dictionary = at[3]
		var l := ReplicaAreas.left_of(at[1])
		for side: float in [1.0, -1.0]:
			var lots: float = sd.east_lots if side > 0.0 else sd.west_lots
			if lots < 5.0 or (side < 0.0 and hash01([h, 7]) < 0.55):
				continue
			var o: float = (float(sd.walk_e_edge) + 0.8 + hash01([h, 1]) * 1.8) if side > 0.0 else (float(sd.walk_w_edge) - 0.8 - hash01([h, 1]) * 1.8)
			var pp: Vector2 = (at[0] as Vector2) + l * o
			_palm(Vector3(pp.x, float(at[2]) + 0.15, pp.y), h, -l * side)
			if hash01([h, 2]) < 0.22:
				# Two together, the way they get planted.
				var pp2 := pp + (at[1] as Vector2) * 2.6
				_palm(Vector3(pp2.x, float(at[2]) + 0.15, pp2.y), h + 17, -l * side)
	var m0 := floori(lo / MEDIAN_PALM_STEP)
	var m1 := ceili(hi / MEDIAN_PALM_STEP)
	for m in range(m0, m1 + 1):
		var s := float(m) * MEDIAN_PALM_STEP + 4.0
		if s < lo or s >= hi:
			continue
		var at := rep.at_s(s)
		var sd: Dictionary = at[3]
		if float(sd.median_raised) < 0.9 or float(sd.median) < 3.0 or not _near_ring(at[0], 6.0).is_empty():
			continue
		var pp: Vector2 = at[0]
		_palm(Vector3(pp.x, float(at[2]) + 0.17, pp.y), hash([plan.seed, "medianpalm", m]), Vector2.ZERO)
	if full:
		_verge_planting(lo, hi)
		ReplicaSigns.furniture(self, lo, hi)


func _palm(at: Vector3, h: int, lean: Vector2) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = h
	var s := rng.randf_range(PALM_SCALE.x, PALM_SCALE.y)
	var variant := rng.randi() % PropFactory.PALM_VARIANTS
	var yaw := rng.randf_range(0.0, TAU)
	if lean != Vector2.ZERO:
		yaw = atan2(lean.x, lean.y) - PropFactory.palm_lean(variant) + rng.randf_range(-0.5, 0.5)
	var tint := Color(rng.randf_range(0.9, 1.1), rng.randf_range(0.92, 1.08), rng.randf_range(0.86, 1.04))
	batch_add("palm_%d" % variant, PropFactory.palm(variant), Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(s, s, s)), at), tint)


## Coastal scrub and ice plant in the verge between the seat wall and the bluff edge.
func _verge_planting(lo: float, hi: float) -> void:
	var n := int((hi - lo) * VERGE_PLANTS)
	for k in n:
		var h := hash([plan.seed, "verge", int(lo), k])
		var s := lo + (hi - lo) * hash01([h, 0])
		var at := rep.at_s(s)
		var sd: Dictionary = at[3]
		if float(sd.coast) < 0.5 or float(sd.west_lots) > 1.0 or _stair_near(s, 1.5):
			continue
		var o := lerpf(float(sd.edge) + 0.5, float(sd.walk_w_edge) - 0.9, hash01([h, 1]))
		var pp: Vector2 = (at[0] as Vector2) + ReplicaAreas.left_of(at[1]) * o
		if _in_car_park(pp):
			continue
		var q := Vector3(pp.x, float(at[2]) + 0.2, pp.y)
		var roll := hash01([h, 2])
		var yaw := hash01([h, 3]) * TAU
		var sc := 0.8 + hash01([h, 4]) * 0.7
		if roll < 0.35:
			var v := h % 4
			batch_add("shrub_%d" % v, PropFactory.model_shrub(v), Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(sc, sc, sc)), q), Color(0.95, 1.0, 0.85))
		elif roll < 0.62:
			var v: int = [0, 3, 1, 2][h % 4]
			batch_add("flower_%d" % v, PropFactory.model_flower(v), Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(sc, sc, sc) * 1.4), q))
		elif roll < 0.85:
			var v := h % 5
			batch_add("scrub_%d" % v, PropFactory.model_scrub(v), Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(sc, sc, sc) * 1.5), q), Color(1.0, 0.98, 0.9))
		else:
			var v := h % 2
			batch_add("gclump_%d" % v, PropFactory.model_grass_clump(v), Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(sc, sc, sc)), q))


func _in_car_park(p: Vector2) -> bool:
	var cp: Dictionary = rep.data.get("car_park", {})
	if cp.is_empty():
		return false
	var fr := _car_park_frame(cp)
	var q: Vector2 = p - (fr.p as Vector2)
	var a := q.dot(fr.d)
	var o := q.dot(fr.l)
	return a > float(cp.along[0]) - 2.0 and a < float(cp.along[1]) + 2.0 and o > float(cp.lateral[0]) - 1.0 and o < float(cp.lateral[1]) + 1.0


## A grey double-arm cobra lamp at `at` (the pavement), its long arm reaching toward `road`.
## Breakable like every street lamp (CityChunk._add_prop), with its light pools and, near the
## player, a real light under each head.
func _lamp(at: Vector3, road: Vector2) -> void:
	var bas := yaw_basis(road)
	var rv := Vector3(road.x, 0, road.y).normalized()
	var head_r := at + rv * LAMP_ARM_ROAD + Vector3(0, LAMP_HEIGHT + 0.25, 0)
	var head_w := at - rv * LAMP_ARM_WALK + Vector3(0, LAMP_HEIGHT - 0.35, 0)
	if not full:
		batch_add("cobra_lamp", ReplicaSigns.cobra_lamp(), Transform3D(bas, at), Color(0.55, 0.56, 0.57))
		return
	var face_basis := bas * Basis(Vector3.RIGHT, PI * 0.5)
	var pool_r := Vector3(head_r.x, at.y - 0.13, head_r.z)
	var pool_w := Vector3(head_w.x, at.y + 0.01, head_w.z)
	var pool_basis := Basis(Vector3.RIGHT, -PI * 0.5).scaled(Vector3(15.0, 1.0, 15.0))
	var pool_basis_w := Basis(Vector3.RIGHT, -PI * 0.5).scaled(Vector3(10.0, 1.0, 10.0))
	# Every instance relative to the ground under its own origin (the batch adds that back); the
	# shape relative to the ground under the column (_add_prop adds that one).
	var base := rel(at)
	chunk._add_prop("lamp", base, Color(0.55, 0.56, 0.57), [
		["cobra_lamp", ReplicaSigns.cobra_lamp(), Transform3D(bas, base), Color(0.55, 0.56, 0.57)],
		["cobra_lens", PropFactory.lamp_face(Color(1.0, 0.86, 0.62), 1.4), Transform3D(face_basis.scaled(Vector3(0.55, 1.0, 0.28)), rel(head_r - Vector3(0, 0.12, 0)))],
		["cobra_lens", PropFactory.lamp_face(Color(1.0, 0.86, 0.62), 1.4), Transform3D(face_basis.scaled(Vector3(0.55, 1.0, 0.28)), rel(head_w - Vector3(0, 0.12, 0)))],
		["lamp_pool", PropFactory.light_pool(), Transform3D(pool_basis, rel(pool_r + Vector3(0, 0.06, 0)))],
		["lamp_pool", PropFactory.light_pool(), Transform3D(pool_basis_w, rel(pool_w + Vector3(0, 0.06, 0)))],
	], [[Vector3(0.35, LAMP_HEIGHT, 0.35), base + Vector3(0, LAMP_HEIGHT * 0.5, 0), 0.0]])
	chunk._batch.set_no_shadow("lamp_pool")
	chunk._batch.set_no_shadow("cobra_lens")
	_lights.append(head_r - Vector3(0, 0.6, 0))


# --- Parked cars -------------------------------------------------------------------------------

func _car_steps() -> Array[Callable]:
	var steps: Array[Callable] = []
	var lo := INF
	var hi := -INF
	for i in rep.pts.size() - 1:
		if _owned(i):
			lo = minf(lo, rep.run[i])
			hi = maxf(hi, rep.run[i + 1])
	if lo <= hi:
		var k0 := ceili(lo / STALL)
		var k1 := floori(hi / STALL)
		for k in range(k0, k1):
			var s := (float(k) + 0.5) * STALL
			if s < lo or s >= hi or s > rep.s_city_end:
				continue
			for side: float in [-1.0, 1.0]:
				var h := hash([plan.seed, "kerbcar", k, int(side)])
				if hash01([h, 0]) > PARK_ODDS or not _mouth_at(s, 6.0).is_empty():
					continue
				if ReplicaHouses.driveway_near(self, s, side):
					continue
				var at := rep.at_s(s)
				var sd: Dictionary = at[3]
				var park: float = sd.park_e if side > 0.0 else sd.park_w
				if park < 2.0:
					continue
				var kerb: float = sd.kerb_e if side > 0.0 else sd.kerb_w
				var o := kerb - side * (park * 0.5)
				var pp: Vector2 = (at[0] as Vector2) + ReplicaAreas.left_of(at[1]) * o
				# Right-hand parking: the west kerb faces south with the traffic, the east north.
				var d: Vector2 = (at[1] as Vector2) * (-side)
				steps.append(_park.bind(Vector3(pp.x, float(at[2]), pp.y), atan2(-d.x, -d.y), h))
	for car in _lot_cars:
		steps.append(_park.bind(car[0], car[1], car[2]))
	return steps


func _park(at: Vector3, yaw: float, h: int) -> void:
	if not PhysicsBudget.can_spawn():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = h
	var car := Vehicle.random_car(rng)
	var holder: Node = chunk.get_parent() if chunk.get_parent() else chunk
	var p := at + Vector3(0.0, 0.55, 0.0)
	car.position = WorldState.to_local(p) if holder != chunk else p
	car.rotation.y = yaw + (rng.randf_range(-0.03, 0.03))
	holder.add_child(car)
	car.visible = chunk.visible
	chunk._cars.append(car)


# --- People -----------------------------------------------------------------------------------

## People on the replica's pavements: a slot every WALKER_SPACING metres of each, most of them
## filled, within the city's crowd cap (CityChunk._take_crowd_room()). One build step each.
const WALKER_SPACING := 26.0
const WALKER_ODDS := 0.6


func _walker_steps() -> Array[Callable]:
	var steps: Array[Callable] = []
	var lo := INF
	var hi := -INF
	for i in rep.pts.size() - 1:
		if _owned(i) and rep.run[i + 1] <= rep.s_city_end:
			lo = minf(lo, rep.run[i])
			hi = maxf(hi, rep.run[i + 1])
	if lo > hi:
		return steps
	var n := int((hi - lo) / WALKER_SPACING)
	for side: float in [-1.0, 1.0]:
		for k in n:
			var h := hash([plan.seed, "walker", int(lo), int(side), k])
			if hash01([h, 0]) > WALKER_ODDS:
				continue
			steps.append(_spawn_walker.bind(lo, hi, side, h))
	return steps


func _spawn_walker(lo: float, hi: float, side: float, h: int) -> void:
	var sd: Dictionary = rep.at_s((lo + hi) * 0.5)[3]
	if side < 0.0 and float(sd.coast) < 0.5:
		return
	if not chunk._take_crowd_room():
		return
	var ped := ReplicaWalker.new()
	ped.rep = rep
	ped.s_lo = lo
	ped.s_hi = hi
	ped.side = side
	ped.setup(Rect2(), 3.0, h)
	var start := ped._random_ring_point(3.0)
	ped.position = Vector3(start.x, chunk._gy(start.x, start.y) + CityChunk.SIDEWALK_TOP + 0.1, start.y)
	chunk.add_child(ped)


# --- Commit ------------------------------------------------------------------------------------

func _body_node() -> StaticBody3D:
	if _body == null:
		_body = StaticBody3D.new()
		_body.name = "ReplicaBody"
		_body.collision_layer = 1
		_body.collision_mask = 0
		chunk.add_child(_body)
	return _body


static var _mats := {}


static func material(name: String) -> Material:
	if _mats.has(name):
		return _mats[name]
	var m: Material
	match name:
		"asphalt":
			m = PropFactory.road("asphalt", 7.0, ASPHALT_TINT, 7331, 0.0, 0.9)
		"concrete", "walk":
			m = PropFactory.road("sidewalk", 3.0, CONCRETE_TINT, 7332, 1.6, 0.45)
		"paint":
			m = PropFactory.road_paint_material()
		"verge":
			m = PropFactory.lawn(Color(1.0, 0.86, 0.58), 8121, 0.75, 0.0)
		"median", "yard":
			m = PropFactory.lawn(Color(0.86, 0.92, 0.66), 8122, 0.4, 2.6)
		"bluff":
			m = PropFactory.terrain_material()
		_:
			m = ReplicaHouses.material(name)
	_mats[name] = m
	return m


func _commit_step() -> void:
	if full:
		for name: String in _st:
			var s: SurfaceTool = _st[name]
			s.generate_normals()
			if name == "glass":
				s.generate_tangents()
			var mesh := s.commit()
			if mesh.get_surface_count() == 0:
				continue
			var mi := MeshInstance3D.new()
			mi.name = "Replica_" + name
			mi.mesh = mesh
			mi.material_override = _mat_override.get(name, material(name))
			# Paint, glass and the flat ground surfaces are all at or near the surface under
			# them: their shadows would only be cascade fill.
			if name in NO_SHADOW:
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			chunk.add_child(mi)
		for p in _lights:
			var light := OmniLight3D.new()
			light.position = p
			light.omni_range = 14.0
			light.omni_attenuation = 1.3
			light.light_color = Color(1.0, 0.86, 0.62)
			light.light_energy = 0.0
			light.shadow_enabled = false
			light.distance_fade_enabled = true
			light.distance_fade_begin = 55.0
			light.distance_fade_length = 15.0
			light.add_to_group("lamp_light")
			chunk.add_child(light)
	else:
		_commit_far()
	if not _col.is_empty():
		var shape := CollisionShape3D.new()
		var cps := ConcavePolygonShape3D.new()
		cps.set_faces(_col)
		shape.shape = cps
		_body_node().add_child(shape)
	_st.clear()
	_col = PackedVector3Array()


## Surfaces that never cast a shadow.
const NO_SHADOW := ["paint", "glass", "asphalt", "grid_0", "grid_1", "yard", "median", "verge", "h_drive", "h_rail"]

## Far chunks: every ground surface into the chunk's single merged ground mesh, coloured by what
## it is (linear, like CityChunk._add_ground_grid(); alpha 0, no street glow).
const FAR_COLORS := {
	"asphalt": Color(0.075, 0.075, 0.08, 0.0), "grid_0": Color(0.075, 0.075, 0.08, 0.0), "grid_1": Color(0.075, 0.075, 0.08, 0.0),
	"concrete": Color(0.40, 0.39, 0.37, 0.0), "walk": Color(0.40, 0.39, 0.37, 0.0),
	"paint": Color(0.6, 0.6, 0.55, 0.0), "verge": Color(0.20, 0.18, 0.09, 0.0), "median": Color(0.10, 0.16, 0.05, 0.0),
	"yard": Color(0.12, 0.17, 0.07, 0.0), "bluff": Color(0.22, 0.19, 0.12, 0.0),
}


func _commit_far() -> void:
	for name: String in _st:
		var s: SurfaceTool = _st[name]
		s.generate_normals()
		var mesh := s.commit()
		if mesh.get_surface_count() == 0:
			continue
		if FAR_COLORS.has(name):
			# append_from() ignores set_color(), so the colour goes into the appended mesh itself.
			var arrays := mesh.surface_get_arrays(0)
			var n := (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
			var cols := PackedColorArray()
			cols.resize(n)
			cols.fill(FAR_COLORS[name])
			arrays[Mesh.ARRAY_COLOR] = cols
			var tinted := ArrayMesh.new()
			tinted.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			if chunk._far_ground == null:
				chunk._far_ground = SurfaceTool.new()
				chunk._far_ground.begin(Mesh.PRIMITIVE_TRIANGLES)
			chunk._far_ground.append_from(tinted, 0, Transform3D.IDENTITY)
			chunk._far_ground_any = true
		else:
			var mi := MeshInstance3D.new()
			mi.name = "Replica_" + name
			mi.mesh = mesh
			mi.material_override = _mat_override.get(name, material(name))
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			chunk.add_child(mi)


# --- Small meshes ------------------------------------------------------------------------------

static var _meshes := {}


## A fence post, centred on its origin.
static func _fence_post() -> Mesh:
	if not _meshes.has("fence_post"):
		_meshes["fence_post"] = PropFactory.box("replica_fence_post", Vector3(0.12, FENCE_H, 0.12), Color(0.52, 0.44, 0.34))
	return _meshes["fence_post"]


static func _fence_rail() -> Mesh:
	if not _meshes.has("fence_rail"):
		_meshes["fence_rail"] = PropFactory.box("replica_fence_rail", Vector3(FENCE_STEP + 0.05, 0.09, 0.06), Color(0.55, 0.47, 0.37))
	return _meshes["fence_rail"]


static func _stair_post() -> Mesh:
	return PropFactory.cylinder("replica_stair_post", 0.03, 1.0, Color(0.35, 0.36, 0.37), -1.0, 8)
