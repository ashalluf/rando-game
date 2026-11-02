class_name CanyonRoad
## The hill roads as canyon roads (fleet wave 5, `rc2-canyon-road`; docs/HANDOFF.md "The canyon
## road refcam"). `CityChunk._build_hill_roads()` hands its segments here: the strip is built
## again with a gravel shoulder past each edge and the lateral position in its UVs, so
## `shaders/canyon_road.gdshader` can draw the worn double yellow, the edge lines, the tyre tracks,
## oil, crack sealant, patches, and the asphalt crumbling into the shoulder; and on the FILL side
## of the road (where the ground drops away past the edge) a metal-beam guardrail on timber posts
## (`shaders/canyon_guardrail.gdshader`), kept off driveways and junctions, with buried ends.
## Everything is a pure function of the segments and the plan's ground: no roll, nothing else moves.
## `CANYON_ROAD=0` in the environment is the A/B (the plain asphalt strip, no rail).

static var _on: int = -1


static func on() -> bool:
	if _on < 0:
		_on = 0 if OS.get_environment("CANYON_ROAD") == "0" else 1
	return _on == 1


## The gravel shoulder's width past each edge of the asphalt, metres.
const SHOULDER := 1.1
## The strip's lift over the carved ground (as the old strip; the beach's sand slab is at 0.2).
const LIFT := 0.26
## The shoulder's outer edge sits this much lower, so it meets the bank rather than standing on it.
const SHOULDER_DROP := 0.12
## Piece length along a segment, metres (the old strip's).
const PIECE := 6.0

## The guardrail: where the ground GUARD_REACH past the edge stands GUARD_DROP under the road.
const GUARD_REACH := 4.5
const GUARD_DROP := 1.6
## The beam's face, metres out past the asphalt's edge, and its top and bottom over the ground.
const RAIL_OUT := 0.55
const RAIL_TOP := 0.79
const RAIL_BOTTOM := 0.48
## Posts every 6 ft 3 in.
const POST_SPACING := 1.905
## No rail within this of another road's centre line (plus its half width) or an estate's drive.
const JUNCTION_CLEAR := 5.0
const DRIVE_CLEAR := 9.0
## The roads that get the treatment: everything a hill chunk draws (fire roads, pads and drives
## are not drawn). Width under this keeps its plain strip (a lane too narrow for two).
const MIN_WIDTH := 5.0

## COLOR.a of the guardrail's parts.
const K_STEEL := 0.0
const K_TIMBER := 0.5
const K_REFLECTOR := 1.0

## The hill boulders `_scatter_hills()` lays (two scans, uniformly at random): sat on the slope
## 15 % sunk they read as pale eggs set out on a lawn. Gathered by RcHills.cluster()'s field (a
## boulder where it is under ROCK_GAP is left out) and bedded: squashed to ROCK_SQUASH of their
## height and sunk ROCK_SINK of it more, so they read as rock breaking through the soil.
const ROCK_GAP := 0.42
const ROCK_SQUASH := 0.78
const ROCK_SINK := 0.3
## The scans' standing heights at scale 1 (the collision box heights _scatter_hills uses).
const ROCK_HEIGHT := [0.8, 1.8]

static var _road_mat: ShaderMaterial
static var _rail_mat: ShaderMaterial


static func road_material() -> ShaderMaterial:
	if _road_mat == null:
		_road_mat = ShaderMaterial.new()
		_road_mat.shader = load("res://shaders/canyon_road.gdshader")
		_road_mat.set_shader_parameter("albedo_tex", PropFactory.texture("asphalt", "Color"))
		_road_mat.set_shader_parameter("normal_tex", PropFactory.texture("asphalt", "NormalGL"))
		_road_mat.set_shader_parameter("rough_tex", PropFactory.texture("asphalt", "Roughness"))
	return _road_mat


static func rail_material() -> ShaderMaterial:
	if _rail_mat == null:
		_rail_mat = ShaderMaterial.new()
		_rail_mat.shader = load("res://shaders/canyon_guardrail.gdshader")
	return _rail_mat


## [transform, extra sink in metres] for a hill boulder at `p` (variant `v`, scale `sc`, its
## transform as rolled), or [] to leave it out. Off (CANYON_ROAD=0): the transform as it was.
static func bed_rock(p: Vector2, v: int, sc: float, xf: Transform3D) -> Array:
	if not on():
		return [xf, 0.0]
	# Its own offset in the field, so the rocks do not gather where the shrub thickets do.
	if RcHills.cluster(p * 1.3 + Vector2(311.0, -97.0)) < ROCK_GAP:
		return []
	var sink: float = float(ROCK_HEIGHT[v]) * sc * ROCK_SINK
	var b := xf.basis * Basis.from_scale(Vector3(1.0, ROCK_SQUASH, 1.0))
	return [Transform3D(b, xf.origin - Vector3(0.0, sink, 0.0)), sink]


## True when the ground past the edge at `edge` (a point on the asphalt's edge, `out` the unit
## direction away from the road, `h` the road's height there) drops away: the fill side.
static func needs_rail(plan: CityPlan, edge: Vector2, out: Vector2, h: float) -> bool:
	var g1 := plan.height_at(edge + out * GUARD_REACH)
	var g2 := plan.height_at(edge + out * (GUARD_REACH + 3.0))
	return h - minf(g1, g2) > GUARD_DROP


## Builds the chunk's hill roads (the drawn segments in `segs`) into `ch`: the road strip with its
## shoulders, and the guardrail runs. Returns true when it built them (the caller then skips its
## own strip); false when off.
static func build(ch: CityChunk, segs: Array[Dictionary]) -> bool:
	if not on():
		return false
	var plan: CityPlan = ch.plan
	var area: Rect2 = ch.owned_rect()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var plain := SurfaceTool.new()
	plain.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rail := SurfaceTool.new()
	rail.begin(Mesh.PRIMITIVE_TRIANGLES)
	var quads := 0
	var plain_quads := 0
	var rails := 0
	var drives: Array[Vector2] = []
	if plan.macro and plan.macro.hill_roads:
		for m: Dictionary in plan.macro.hill_roads.mansions_in(area.grow(60.0)):
			drives.append(m.get("drive_from", m.pos))
	var drawn: Array[Dictionary] = []
	for seg in segs:
		if seg.get("draw", true) and not seg.get("drive", false):
			drawn.append(seg)
	for seg in drawn:
		var a: Vector2 = seg.a
		var b: Vector2 = seg.b
		var seg_len := a.distance_to(b)
		if seg_len < 0.5:
			continue
		var pieces := maxi(1, ceili(seg_len / PIECE))
		var dir := (b - a) / seg_len
		var half: float = seg.width * 0.5
		var na: Vector2 = seg.get("na", Vector2(-dir.y, dir.x))
		var nb: Vector2 = seg.get("nb", Vector2(-dir.y, dir.x))
		var wide: bool = seg.width >= MIN_WIDTH
		var outer := half + SHOULDER
		var prev := []
		var prev_rail := [false, false]
		for k in pieces:
			var t0 := float(k) / pieces
			var t1 := float(k + 1) / pieces
			var c0 := a.lerp(b, t0)
			var c1 := a.lerp(b, t1)
			if not area.has_point(c0.lerp(c1, 0.5)):
				prev = []
				prev_rail = [false, false]
				continue
			var n0 := na.lerp(nb, t0)
			var n1 := na.lerp(nb, t1)
			var r0: Array = prev if not prev.is_empty() else _row(plan, c0, n0, half, outer if wide else half)
			var r1 := _row(plan, c1, n1, half, outer if wide else half)
			prev = r1
			if not wide:
				_strip_plain(plain, r0, r1)
				plain_quads += 1
				continue
			_strip(st, r0, r1, half, outer, t0 * seg_len, t1 * seg_len)
			quads += 1
			# The rail, side by side: -1 the left (n), +1 the right.
			for s in 2:
				var sg := 1.0 if s == 0 else -1.0
				var e0 := c0 + n0 * half * sg
				var e1 := c1 + n1 * half * sg
				var em := (e0 + e1) * 0.5
				var out := ((n0 + n1) * 0.5).normalized() * sg
				var ei := 1 if s == 0 else 2
				var hm := ((r0[ei] as Vector3).y + (r1[ei] as Vector3).y) * 0.5 - LIFT
				var want := needs_rail(plan, em, out, hm) and _clear(em + out * RAIL_OUT, seg, drawn, drives)
				if want:
					var p0 := e0 + n0 * RAIL_OUT * sg
					var p1 := e1 + n1 * RAIL_OUT * sg
					# The rail stands on the shoulder: the carved ground there, at the shoulder's lift.
					var g0 := plan.height_at(p0) + LIFT - SHOULDER_DROP * 0.5
					var g1 := plan.height_at(p1) + LIFT - SHOULDER_DROP * 0.5
					# The run's ends dip into the ground (a buried end), where the piece before
					# (or after) needs none.
					var start_end: bool = not prev_rail[s] and k > 0 and not _wants(plan, a.lerp(b, float(k - 1) / pieces), a.lerp(b, float(k) / pieces), na.lerp(nb, float(k - 1) / pieces), n0, half, sg, seg, drawn, drives)
					var end_end: bool = k + 1 < pieces and not _wants(plan, c1, a.lerp(b, float(k + 2) / pieces), n1, na.lerp(nb, float(k + 2) / pieces), half, sg, seg, drawn, drives)
					_rail_piece(rail, p0, p1, g0, g1, out, t0 * seg_len, start_end, end_end)
					rails += 1
				prev_rail[s] = want
	if quads > 0:
		st.generate_normals()
		st.generate_tangents()
		var mesh := MeshInstance3D.new()
		mesh.name = "HillRoad"
		mesh.mesh = st.commit()
		mesh.material_override = road_material()
		ch.add_child(mesh)
	if plain_quads > 0:
		plain.generate_normals()
		var pm := MeshInstance3D.new()
		pm.name = "HillRoadPlain"
		pm.mesh = plain.commit()
		pm.material_override = PropFactory.pbr("asphalt", 7.0, Color(0.79, 0.79, 0.81))
		ch.add_child(pm)
	if rails > 0 and ch.level == CityChunk.Level.FULL:
		rail.generate_normals()
		var rm := MeshInstance3D.new()
		rm.name = "HillGuardrail"
		rm.mesh = rail.commit()
		rm.material_override = rail_material()
		rm.visibility_range_end = 260.0
		ch.add_child(rm)
	return true


static func _wants(plan: CityPlan, c0: Vector2, c1: Vector2, n0: Vector2, n1: Vector2, half: float, sg: float, seg: Dictionary, drawn: Array[Dictionary], drives: Array[Vector2]) -> bool:
	var em := (c0 + n0 * half * sg + c1 + n1 * half * sg) * 0.5
	var out := ((n0 + n1) * 0.5).normalized() * sg
	var h := (plan.height_at(c0 + n0 * half * sg) + plan.height_at(c1 + n1 * half * sg)) * 0.5
	return needs_rail(plan, em, out, h) and _clear(em + out * RAIL_OUT, seg, drawn, drives)


## Clear of every other drawn road (a junction) and of every estate's driveway mouth.
static func _clear(p: Vector2, seg: Dictionary, drawn: Array[Dictionary], drives: Array[Vector2]) -> bool:
	for d in drives:
		if p.distance_to(d) < DRIVE_CLEAR:
			return false
	for o in drawn:
		if o == seg:
			continue
		var oa: Vector2 = o.a
		var ob: Vector2 = o.b
		var q := Geometry2D.get_closest_point_to_segment(p, oa, ob)
		if p.distance_to(q) < float(o.width) * 0.5 + JUNCTION_CLEAR:
			# A neighbour of this segment on the same road continues it: its centre line runs
			# through this segment's end, so it is not a junction.
			if (oa.distance_to(seg.a) < 0.01 or oa.distance_to(seg.b) < 0.01 or ob.distance_to(seg.a) < 0.01 or ob.distance_to(seg.b) < 0.01) and is_equal_approx(float(o.width), float(seg.width)):
				continue
			return false
	return true


## A cross-section of the strip at centre `c`: the outer shoulder, the asphalt's edge, centre,
## edge and outer shoulder, each on the carved ground (the asphalt LIFT over it, the shoulder's
## outer edge SHOULDER_DROP under that).
static func _row(plan: CityPlan, c: Vector2, n: Vector2, half: float, outer: float) -> Array:
	var el := plan.height_at(c + n * half) + LIFT
	var er := plan.height_at(c - n * half) + LIFT
	var row := []
	row.append(Vector3(c.x + n.x * outer, plan.height_at(c + n * outer) + LIFT - SHOULDER_DROP, c.y + n.y * outer))
	row.append(Vector3(c.x + n.x * half, el, c.y + n.y * half))
	row.append(Vector3(c.x - n.x * half, er, c.y - n.y * half))
	row.append(Vector3(c.x - n.x * outer, plan.height_at(c - n * outer) + LIFT - SHOULDER_DROP, c.y - n.y * outer))
	return row


static func _strip_plain(st: SurfaceTool, r0: Array, r1: Array) -> void:
	# The old strip: from the right edge (row index 2) to the left (1).
	var v0: Vector3 = r0[2]
	var v1: Vector3 = r0[1]
	var v2: Vector3 = r1[1]
	var v3: Vector3 = r1[2]
	for v in [v0, v2, v1, v0, v3, v2]:
		st.add_vertex(v)


## One piece of strip from row r0 to r1: shoulder, asphalt (split at the centre line), shoulder.
## UV.x is metres across from the centre (positive toward the left edge, n), UV.y metres along,
## UV2 = (half width, outer half width).
static func _strip(st: SurfaceTool, r0: Array, r1: Array, half: float, outer: float, s0: float, s1: float) -> void:
	var m0: Vector3 = ((r0[1] as Vector3) + (r0[2] as Vector3)) * 0.5
	var m1: Vector3 = ((r1[1] as Vector3) + (r1[2] as Vector3)) * 0.5
	var cols0 := [r0[0], r0[1], m0, r0[2], r0[3]]
	var cols1 := [r1[0], r1[1], m1, r1[2], r1[3]]
	var xs := [outer, half, 0.0, -half, -outer]
	var uv2 := Vector2(half, outer)
	for j in 4:
		var q := [[cols0[j], xs[j], s0], [cols1[j], xs[j], s1], [cols1[j + 1], xs[j + 1], s1], [cols0[j + 1], xs[j + 1], s0]]
		# Two triangles, wound to face up: the old strip's v0, v2, v1 / v0, v3, v2 (v0 its right
		# edge at the piece's start, v1 the left, v2 the left at its end, v3 the right) are q3, q1,
		# q0 / q3, q2, q1 here (the columns run left to right).
		for idx in [3, 1, 0, 3, 2, 1]:
			var e: Array = q[idx]
			st.set_uv(Vector2(e[1], e[2]))
			st.set_uv2(uv2)
			st.add_vertex(e[0])


## One piece of rail from p0 to p1 (the beam's face, ground heights g0 / g1, `out` away from the
## road): the W-beam, a post (with its blockout) at each post station in the piece, and where a
## run starts or ends here the beam bent down into the ground over the piece.
static func _rail_piece(st: SurfaceTool, p0: Vector2, p1: Vector2, g0: float, g1: float, out: Vector2, s0: float, start_end: bool, end_end: bool) -> void:
	var length := p0.distance_to(p1)
	if length < 0.05:
		return
	var dir := (p1 - p0) / length
	var o3 := Vector3(out.x, 0.0, out.y)
	# The W-beam's section (metres out from the face, metres up from the beam's bottom): two
	# ridges toward the road, a valley between, the flanges turned back.
	var prof := [Vector2(0.06, 0.0), Vector2(0.0, 0.04), Vector2(0.0, 0.11), Vector2(0.05, 0.155), Vector2(0.0, 0.20), Vector2(0.0, 0.27), Vector2(0.06, 0.31)]
	var steps := maxi(1, ceili(length / 1.0))
	for i in steps:
		var ta := float(i) / steps
		var tb := float(i + 1) / steps
		var pa := p0.lerp(p1, ta)
		var pb := p0.lerp(p1, tb)
		var ga := lerpf(g0, g1, ta)
		var gb := lerpf(g0, g1, tb)
		# Buried ends: the beam's bottom falls from RAIL_BOTTOM to under the ground over the piece.
		var da := 0.0
		var db := 0.0
		if start_end:
			da += (1.0 - ta) * (RAIL_TOP + 0.05)
			db += (1.0 - tb) * (RAIL_TOP + 0.05)
		if end_end:
			da += ta * (RAIL_TOP + 0.05)
			db += tb * (RAIL_TOP + 0.05)
		var ba := ga + RAIL_BOTTOM - da
		var bb := gb + RAIL_BOTTOM - db
		var sa := s0 + ta * length
		var sb := s0 + tb * length
		for j in prof.size() - 1:
			var u0: Vector2 = prof[j]
			var u1: Vector2 = prof[j + 1]
			var a0 := Vector3(pa.x, ba + u0.y, pa.y) + o3 * u0.x
			var a1 := Vector3(pa.x, ba + u1.y, pa.y) + o3 * u1.x
			var b0 := Vector3(pb.x, bb + u0.y, pb.y) + o3 * u0.x
			var b1 := Vector3(pb.x, bb + u1.y, pb.y) + o3 * u1.x
			_quad(st, a0, b0, b1, a1, K_STEEL, sa, sb, u0.y + RAIL_BOTTOM, u1.y + RAIL_BOTTOM)
	# Posts: at every multiple of POST_SPACING along the run (true world distance off the piece's
	# start, so a run's posts are evenly spaced across pieces).
	var first := ceilf(s0 / POST_SPACING) * POST_SPACING
	var s := first
	while s < s0 + length - 0.01:
		var t := (s - s0) / length
		var buried := (start_end and t < 0.55) or (end_end and t > 0.45)
		if not buried:
			var p := p0.lerp(p1, t)
			var g := lerpf(g0, g1, t)
			# The blockout behind the beam, then the post behind it, both timber.
			_box(st, Vector3(p.x, g + RAIL_BOTTOM + 0.15, p.y) + o3 * 0.17, dir, out, Vector3(0.15, 0.36, 0.2), K_TIMBER)
			_box(st, Vector3(p.x, g + 0.2, p.y) + o3 * 0.37, dir, out, Vector3(0.15, 1.2, 0.2), K_TIMBER)
			if int(roundf(s / POST_SPACING)) % 8 == 0:
				# A reflector tab on the beam's top.
				_box(st, Vector3(p.x, g + RAIL_TOP + 0.04, p.y) + o3 * 0.02, dir, out, Vector3(0.08, 0.08, 0.01), K_REFLECTOR)
		s += POST_SPACING


static func _quad(st: SurfaceTool, a0: Vector3, b0: Vector3, b1: Vector3, a1: Vector3, kind: float, sa: float, sb: float, ya: float, yb: float) -> void:
	var c := Color(1, 1, 1, kind)
	var verts := [[a0, Vector2(sa, ya)], [b0, Vector2(sb, ya)], [b1, Vector2(sb, yb)], [a0, Vector2(sa, ya)], [b1, Vector2(sb, yb)], [a1, Vector2(sa, yb)]]
	for e: Array in verts:
		st.set_color(c)
		st.set_uv(e[1])
		st.add_vertex(e[0])


## A box centred at `c`, its x along `dir`, z along `out`, size (along, up, out).
static func _box(st: SurfaceTool, c: Vector3, dir: Vector2, out: Vector2, size: Vector3, kind: float) -> void:
	var ax := Vector3(dir.x, 0.0, dir.y) * size.x * 0.5
	var ay := Vector3(0.0, size.y * 0.5, 0.0)
	var az := Vector3(out.x, 0.0, out.y) * size.z * 0.5
	var corners := []
	for i in 8:
		corners.append(c + ax * (1.0 if i & 1 else -1.0) + ay * (1.0 if i & 2 else -1.0) + az * (1.0 if i & 4 else -1.0))
	var faces := [[0, 1, 3, 2], [4, 6, 7, 5], [0, 4, 5, 1], [2, 3, 7, 6], [0, 2, 6, 4], [1, 5, 7, 3]]
	for f: Array in faces:
		_quad(st, corners[f[0]], corners[f[1]], corners[f[2]], corners[f[3]], kind, 0.0, size.x, 0.0, size.y)
