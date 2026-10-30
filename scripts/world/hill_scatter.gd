class_name HillScatter
extends RefCounted
## The hills' planted volume (fleet wave 3, hill-planting-2, docs/HANDOFF.md "The hills' planted
## volume"): from the air, and walking a ridge, a chaparral stand painted on the ground read as a
## tan-and-olive sheet with a few specks on it. A real stand is thousands of shrubs, each a lit top
## and a shaded side. This puts that volume on the painted stands with a mesh a GPU barely notices:
##
##   * the SCATTER clump: three lumpy domes built in code (63 / 15 / 6 triangles on one vertex
##     buffer, measured edges), leaves drawn by `shaders/hill_scatter.gdshader` from world-space
##     noise (leaf clumps, dark pockets between them, dead twigs, the base in shade), seated on the
##     very stand field the terrain paints (HillPlanting.ground(), off the tile's own heights,
##     drains and rills), never on rock, cuts, roads, pads, creek beds or the reservoir;
##   * FULL hill chunks: a 4 m world grid of clumps between the code-built shrubs (HillShrub),
##     dithered in past FULL_FADE so up close the real shrubs carry the stand, drawn to FULL_DRAW;
##   * LOD hill chunks (the 7-block ring, which planted nothing): a 6 m grid of bigger clumps
##     (several shrubs each) out to LOD_DRAW - "the far shrub-scatter layer between the FULL chunks
##     and the painted ground"; past it the painted stands are the brush as before (HANDOFF 9au);
##   * oak CLUMPS in the hollows: an oak planted in a hollow (CityChunk._plant_hills, Skyline's far
##     tier) gets one or two companions a few metres off, as live oaks grow.
##
## No shadows (a stand's shade is the painted brush under it and each clump's own dark base); the
## mesh's LODs are switched by the renderer. Every roll is a hash of seed + world grid cell (no rng,
## nothing else moves); a chunk's state is the meta `hill_scatter`. HILL_PLANTING_2=0 in the
## environment is the A/B.

static var enabled: bool = OS.get_environment("HILL_PLANTING_2") != "0"

## World grid (metres) a FULL / LOD chunk tries a clump at, and the stand share a point needs.
const FULL_SPACING := 4.0
const LOD_SPACING := 6.0
const BRUSH_MIN := 0.55
## Clump scale (the mesh is CLUMP_W wide, CLUMP_H tall at 1): FULL clumps are a shrub or two,
## LOD clumps a knot of them.
const FULL_SCALE := Vector2(1.0, 1.6)
const LOD_SCALE := Vector2(1.9, 3.0)
const CLUMP_W := 3.4
const CLUMP_H := 1.9
## FULL clumps are dithered in between these camera distances (metres): nearer, the code-built
## shrubs and the shells are the stand. Drawn to (the batch's centre): FULL_DRAW, LOD_DRAW.
const FULL_FADE := Vector2(70.0, 100.0)
const FULL_DRAW := 300.0
const LOD_DRAW := 720.0
## Microseconds of planting a build step.
const STEP_BUDGET_US := 3500
## Oak clumps: the odds an oak in a hollow has companions, and how far off they stand.
const OAK_CLUMP_ODDS := 0.75
const OAK_CLUMP_REACH := Vector2(5.5, 9.5)

## LOD edges (metres of departure, scaled by the batch's biggest instance like the foliage
## ladders): the three domes become cones, then one mound.
const EDGES := [0.12, 0.36]

static var _mesh: ArrayMesh = null
static var _meshes: Dictionary = {}
static var _mats: Dictionary = {}


## Two floats 0..1 out of one integer hash.
static func _u(h: int, k: int) -> float:
	return float((h >> (k * 10)) & 1023) / 1023.0


## The clump: three domes of radius ~1 m round the middle, as one ArrayMesh with LODs.
static func mesh() -> ArrayMesh:
	if _mesh:
		return _mesh
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var lobes := [[Vector2(-0.55, 0.25), 1.05, 1.0], [Vector2(0.6, 0.15), 0.95, 0.85], [Vector2(0.05, -0.62), 0.85, 0.72]]
	# Level 0: each lobe a base ring (buried), a shoulder ring and an apex, 7 segments.
	var l0 := PackedInt32Array()
	for lb: Array in lobes:
		_dome(verts, norms, cols, l0, lb[0], lb[1], lb[2], 7, true)
	var l1 := PackedInt32Array()
	for lb: Array in lobes:
		_dome(verts, norms, cols, l1, lb[0], lb[1], lb[2], 5, false)
	var l2 := PackedInt32Array()
	_dome(verts, norms, cols, l2, Vector2(0.03, 0.0), 1.55, 0.95, 6, false)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = l0
	var m := ArrayMesh.new()
	# HILL_SCATTER_LEVEL=n (measurement only): that level alone, no LODs, so the renderer's counter
	# counts every instance (measurement trap 3: a LOD'd batch counts as ONE instance in GEO).
	var forced := OS.get_environment("HILL_SCATTER_LEVEL")
	if forced != "":
		arrays[Mesh.ARRAY_INDEX] = [l0, l1, l2][clampi(int(forced), 0, 2)]
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		_mesh = m
		return m
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {float(EDGES[0]): l1, float(EDGES[1]): l2})
	m.set_meta("foliage_ladder", true)
	_mesh = m
	return m


## The clump wearing the "full" (fades in near the camera) or "lod" material.
static func mesh_for(kind: String) -> ArrayMesh:
	if _meshes.has(kind):
		return _meshes[kind]
	var m := mesh().duplicate() as ArrayMesh
	m.surface_set_material(0, material(kind))
	m.set_meta("foliage_ladder", true)
	_meshes[kind] = m
	return m


## A dome at `c` (XZ, metres at scale 1 x CLUMP_W / 3.4), radius `r`, height `h` (x CLUMP_H / 1.9),
## `segs` round; with `shoulder` a ring at 60 % height, else a cone to the apex (its normals still
## a dome's). Vertex colour R is the light reaching it (dark at the base).
static func _dome(verts: PackedVector3Array, norms: PackedVector3Array, cols: PackedColorArray, idx: PackedInt32Array,
		c: Vector2, r: float, h: float, segs: int, shoulder: bool) -> void:
	var sx := CLUMP_W / 3.4
	var sy := CLUMP_H / 1.9
	var centre := Vector3(c.x * sx, 0.0, c.y * sx)
	var rings: Array = [[-0.18, 1.0, 0.15]]
	if shoulder:
		rings.append([0.6, 0.82, 0.75])
	var base := verts.size()
	for ring: Array in rings:
		for s in segs:
			var a := TAU * (float(s) + 0.37 * float(ring.size())) / float(segs)
			# Lumpy outline: each segment in or out a little.
			var lump := 1.0 + 0.13 * sin(a * 3.0 + c.x * 5.0) + 0.07 * cos(a * 5.0 + c.y * 7.0)
			var rr := r * float(ring[1]) * lump * sx
			var y := h * float(ring[0]) * sy
			var p := centre + Vector3(cos(a) * rr, y, sin(a) * rr)
			verts.append(p)
			# The dome's normal: out from a centre under the ground, so the shoulder lights as a curve.
			norms.append(((p - (centre + Vector3(0.0, -0.45 * h * sy, 0.0))) * Vector3(1.0, 1.6, 1.0)).normalized())
			cols.append(Color(float(ring[2]), 0.0, 0.0, 1.0))
	var apex := verts.size()
	verts.append(centre + Vector3(0.0, h * sy, 0.0))
	norms.append(Vector3.UP)
	cols.append(Color(1.0, 0.0, 0.0, 1.0))
	var nr := rings.size()
	for k in nr:
		for s in segs:
			var a0 := base + k * segs + s
			var a1 := base + k * segs + (s + 1) % segs
			if k + 1 < nr:
				var b0 := a0 + segs
				var b1 := a1 + segs
				_tri(verts, idx, a0, a1, b1, centre)
				_tri(verts, idx, a0, b1, b0, centre)
			else:
				_tri(verts, idx, a0, a1, apex, centre)


## One triangle, wound to face away from the dome's axis (Godot's front faces are clockwise).
static func _tri(verts: PackedVector3Array, idx: PackedInt32Array, a: int, b: int, c: int, centre: Vector3) -> void:
	var pa := verts[a]
	var pb := verts[b]
	var pc := verts[c]
	var want := (pa + pb + pc) / 3.0 - (centre + Vector3(0.0, -0.5, 0.0))
	if (pc - pa).cross(pb - pa).dot(want) < 0.0:
		idx.append_array([a, c, b])
	else:
		idx.append_array([a, b, c])


## The shared materials: "full" fades in near the camera, "lod" does not.
static func material(kind: String) -> ShaderMaterial:
	if _mats.has(kind):
		return _mats[kind]
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/hill_scatter.gdshader")
	if kind == "full":
		m.set_shader_parameter("near_fade", FULL_FADE)
	_mats[kind] = m
	return m


## The loading screen: the mesh and both materials.
static func warm() -> Array:
	mesh_for("full")
	mesh_for("lod")
	return [material("full"), material("lod")]


## The build step for a hill chunk (FULL or LOD), after _plant_hills; returns true when done.
static func step(ch: CityChunk) -> bool:
	if not enabled or ch.capturing or ch.plan.macro == null:
		return true
	var full: bool = ch.level == CityChunk.Level.FULL
	var spacing := FULL_SPACING if full else LOD_SPACING
	var area: Rect2 = ch.owned_rect()
	var gx0 := int(floor(area.position.x / spacing))
	var gz0 := int(floor(area.position.y / spacing))
	var gx1 := int(ceil(area.end.x / spacing))
	var gz1 := int(ceil(area.end.y / spacing))
	if not ch.has_meta("hill_scatter"):
		ch.set_meta("hill_scatter", {"row": gz0, "count": 0, "tried": 0, "points": [],
			"segs": ch._hill_segments(), "pads": ch.plan.macro.hill_roads.mansions_in(area.grow(HillRoads.PAD_RADIUS + 6.0)) if ch.plan.macro.hill_roads else []})
	var st: Dictionary = ch.get_meta("hill_scatter")
	var key := "hill_scatter_full" if full else "hill_scatter_lod"
	var m := mesh_for("full" if full else "lod")
	var sc := FULL_SCALE if full else LOD_SCALE
	var t0 := Time.get_ticks_usec()
	var seed: int = ch.plan.seed
	while int(st.row) < gz1:
		var j: int = st.row
		for i in range(gx0, gx1):
			var h0 := hash([seed, "hill_scatter", spacing, i, j])
			var p := Vector2((float(i) + 0.15 + 0.7 * _u(h0, 0)) * spacing, (float(j) + 0.15 + 0.7 * _u(h0, 1)) * spacing)
			if not area.has_point(p):
				continue
			st.tried = int(st.tried) + 1
			var at: Variant = _spot(ch, p, st, full)
			if at == null:
				continue
			var a := at as Array
			var y: float = a[0]
			var grad: Vector2 = a[1]
			var slope: float = a[2]
			var s := lerpf(sc.x, sc.y, _u(h0, 2))
			var up := Vector3(-grad.x, 1.0, -grad.y).normalized().lerp(Vector3.UP, 0.55).normalized()
			var basis := Basis(Quaternion(Vector3.UP, up)) * Basis(Vector3.UP, TAU * float((h0 >> 21) & 255) / 256.0)
			# Wider than tall, and pressed into the slope at its downhill side.
			basis = basis.scaled(Vector3(s * 1.1, s * lerpf(0.8, 1.15, _u(h0, 1)), s))
			ch._batch.add(key, m, Transform3D(basis, Vector3(p.x, y - 0.1 - slope * 1.4 * s, p.y)), Color.WHITE,
				Color(_u(h0, 0), _u(h0, 2), float(full), 0.0))
			st.count = int(st.count) + 1
			if (st.points as Array).size() < 4000:
				(st.points as Array).append(p)
		st.row = j + 1
		if Time.get_ticks_usec() - t0 > STEP_BUDGET_US:
			st.usec = int(st.get("usec", 0)) + Time.get_ticks_usec() - t0
			st.steps = int(st.get("steps", 0)) + 1
			return false
	st.usec = int(st.get("usec", 0)) + Time.get_ticks_usec() - t0
	st.steps = int(st.get("steps", 0)) + 1
	ch._batch.set_no_shadow(key)
	ch._batch.set_draw_distance(key, FULL_DRAW if full else LOD_DRAW)
	ch.set_meta("hill_scatter_done", {"count": st.count, "tried": st.tried, "points": st.points, "level": ch.level,
		"usec": st.usec, "steps": st.steps})
	ch.remove_meta("hill_scatter")
	return true


## Whether a clump stands at `p`: [ground y, gradient, slope] or null. The stand field off the
## tile's own heights (what the terrain draws), as _plant_hills reads it.
static func _spot(ch: CityChunk, p: Vector2, st: Dictionary, full: bool) -> Variant:
	if ch._near_hill_road(p, st.segs, 3.5) or ch._near_pad(p, st.pads, 6.0):
		return null
	var h: float = ch._terrain_height(p)
	if h < 1.5:
		return null
	var macro: MacroMap = ch.plan.macro
	if macro.reservoir and macro.reservoir.keep_clear(p, h):
		return null
	if ArroyoBuild.in_bed(ch, p, 1.2):
		return null
	var e := 2.0 if full else 3.0
	var grad := Vector2(ch._terrain_height(p + Vector2(e, 0.0)) - ch._terrain_height(p - Vector2(e, 0.0)),
		ch._terrain_height(p + Vector2(0.0, e)) - ch._terrain_height(p - Vector2(0.0, e))) / (2.0 * e)
	var g := HillPlanting.ground(p, grad, full, ch._terrain_height(p, "drains"), ch._terrain_rill(p) if full else INF)
	if float(g.rocky) > 0.3 or float(g.bare) > 0.4 or float(g.brush) < BRUSH_MIN:
		return null
	return [h, grad, float(g.slope)]


## Companions for an oak just planted in a hollow at `at` (CityChunk._plant_hills): up to two more
## of the same batch a few metres off, on the tile's ground, kept off roads, pads and beds. Hashes
## of the oak's place only (the planting's row stream is untouched). Returns how many.
static func oak_clump(ch: CityChunk, key: String, oak_mesh: Mesh, at: Vector3, s: float, tint: Color, variety: Color, segs: Array[Dictionary], pads: Array[Dictionary]) -> int:
	if not enabled:
		return 0
	var h0 := hash([ch.plan.seed, "oak_clump", int(at.x * 4.0), int(at.z * 4.0)])
	if _u(h0, 0) > OAK_CLUMP_ODDS:
		return 0
	var n := 1 + int(_u(h0, 1) > 0.45)
	var made := 0
	for k in n:
		var hk := hash([h0, k])
		var a := TAU * (float(k) / float(n) + 0.3 * _u(hk, 0))
		var d := lerpf(OAK_CLUMP_REACH.x, OAK_CLUMP_REACH.y, _u(hk, 1))
		var p := Vector2(at.x, at.z) + Vector2(cos(a), sin(a)) * d
		if not ch.owned_rect().has_point(p) or ch._near_hill_road(p, segs, 3.0) or ch._near_pad(p, pads, 5.0):
			continue
		if ArroyoBuild.in_bed(ch, p, 0.6):
			continue
		var y: float = ch._terrain_height(p)
		if y < 1.5 or absf(y - at.y) > d * 0.5:
			continue
		var ks := s * lerpf(0.7, 1.0, _u(hk, 2))
		ch._batch.add(key, oak_mesh, Transform3D(Basis(Vector3.UP, TAU * _u(hk, 2)).scaled(Vector3(ks, ks, ks)), Vector3(p.x, y - 0.1, p.y)), tint, variety)
		made += 1
	return made


## The far tier's oak clumps (Skyline._add_hills): a far oak in a hollow gets one or two smaller
## canopy blobs beside it, on the block's lattice heights. Hashes of the oak's place only.
static func far_oak_clump(seed: int, p: Vector2, r: float, th: float, col: Color, rect: Rect2, lat: Dictionary, height: Callable,
		veg: Array, veg_colors: Array, veg_custom: Array) -> int:
	var h0 := hash([seed, "far_oak_clump", int(p.x), int(p.y)])
	if _u(h0, 0) > OAK_CLUMP_ODDS:
		return 0
	var n := 1 + int(_u(h0, 1) > 0.45)
	var made := 0
	for k in n:
		var hk := hash([h0, k])
		var a := TAU * (float(k) / float(n) + 0.3 * _u(hk, 0))
		var q := p + Vector2(cos(a), sin(a)) * r * lerpf(1.3, 1.9, _u(hk, 1))
		if not rect.has_point(q):
			continue
		var s := lerpf(0.65, 0.9, _u(hk, 2))
		var gy: float = height.call(lat, q)
		# Never under the far tier's least oak (a lower blob there reads as the brush mounds it dropped).
		var tc := maxf(th * s, Skyline.HILL_OAK_HEIGHT.x)
		veg.append(Transform3D(Basis(Vector3.UP, TAU * _u(hk, 2)).scaled(Vector3(r * s, tc, r * s * 0.85)), Vector3(q.x, gy + tc * 0.3, q.y)))
		veg_colors.append(col * Color(0.92, 0.95, 0.92, 1.0))
		veg_custom.append(Color(0.0, 0.0, 0.0, 0.0))
		made += 1
	return made
