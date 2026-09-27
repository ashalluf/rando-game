class_name FoliageLod
extends RefCounted
## LOD ladders for the downloaded trees (PropFactory._tree_mesh(), foliage_ladder_files()), the
## imported counterpart of the palms' hand-built ladder (PropFactory.PALM_LEVELS).
##
## What was wrong. Every scanned plant went through ImporterMesh.generate_lods(), whose LOD
## errors are the simplifier's quadric error with the normals weighed in, scaled by the mesh's
## size. On a surface made of thousands of separate little pieces - two-triangle leaf cards,
## five-triangle twigs - that number has little to do with how far the surface moved:
##   - the trunks and the jacaranda's twig cards reported 3-10 times their real departure (the
##     jacaranda's 30k-triangle twig surface said 5.2 m at its first LOD), so they never switched;
##   - the leaf cards reported 7-24 cm while the simplifier was DELETING cards: tree_a's first
##     leaf LOD kept 71 % of the leaf area and its last 0 %, which it took from ~85 m at 960 px -
##     canopies thinned with distance and then went bare.
## Measured (tools/foliage_lods.gd), no generated leaf LOD keeps its cover, and most trunk LODs
## are good far sooner than they said.
##
## What replaces it, per surface (the table in scripts/world/foliage_lod_table.gd, written by the
## tool): a ladder picked from two kinds of level, each with its MEASURED departure as its edge,
## so the renderer switches where the change is under a pixel (Viewport mesh_lod_threshold) by
## the same rule it applies to everything else:
##   - "gen": one of generate_lods()'s own levels (trunks, big limbs, the quiver's real leaves);
##   - "thin": a thinned copy of a surface made of many small pieces (leaf cards, twigs) - every
##     `stride`-th piece in a space-filling (Morton) order kept, so the kept ones are spread
##     evenly (the tool picks which of the stride's phases keeps the tone best), each grown about
##     its own centre so the level's textured cover - area times the atlas' cut-out - is exactly
##     level 0's, and slid back inside the surface's bounds if the growth took it out. The canopy
##     keeps its cover, tone and outline at every level; only the pieces get fewer and bigger,
##     which is the change a pixel cannot show once a piece is smaller than it. Big pieces
##     (limbs) are never thinned.
## All levels of a surface live in ONE vertex buffer (the thinned copies appended after the
## original vertices) with the coarser ones as its LODs, exactly like the palms: no node, draw
## or script is added, and level 0 is the untouched original, so up close nothing changes.

## Strides tried for a thinned level: keep 1 piece in 2, 4, ... The tool measures each and the
## table keeps the ones worth having.
const STRIDES := [2, 4, 8, 16, 32]
## A surface needs at least this many pieces to be thinned; fewer is a trunk or a limb system.
const MIN_PIECES := 200
## Pieces bigger than this many times the surface's median piece are structure (limbs, the
## trunk's own branches): they stay, unscaled, at every thinned level.
const BIG_PIECE := 3.0
## Morton grid resolution per axis (bits).
const MORTON_BITS := 10
## The shadow twin starts at the coarsest level whose departure, at the species' tallest street
## planting, is under this many metres - a shadow map cannot show it (the palms' twin starts at
## 0.22 m too, PropFactory.PALM_SHADOW_LEVEL).
const SHADOW_EDGE := 0.22
## The shadow twin's LOD bias against the tree's own (MultiMeshBatch.build()): it switches where
## its departure is under two pixels, not one. The sun is 0.9 degrees across (DirectionalLight3D
## light_angular_distance), so a crown 5-13 m up casts a 10-20 cm penumbra, on top of the soft
## shadow filter; the cars' and aircraft's shadow twins run at 0.3 (Vehicle.BODY_SHADOW_LOD_BIAS).
## Measured at the downtown bookmark: -0.42 M shadow triangles on top of the ladders (HANDOFF 9af).
const SHADOW_LOD_SCALE := 0.5
## Every surface of a ladder (and of its twin) ends with one more LOD at this edge: a copy of its
## last level (_counter_copy()), which the renderer can never pick. It draws nothing different;
## it is there for the renderer's triangle counter, which adds a surface WITH LODs once per draw
## call and one without once per instance (CLAUDE.md measurement trap 3). Without it, the twins'
## last levels - which have nothing coarser below them - counted forty trees where every other
## LOD'd batch (palms, props, the old tree meshes) counts one, and the HUD and GEO read +2.5 M
## triangles on the freeway bookmark for a change that removes 2.6 M.
const COUNTER_EDGE := 1.0e6


## Which piece every triangle and vertex of an indexed surface belongs to: triangles that share
## a vertex, or a vertex POSITION (so a twig split along a UV seam is still one twig).
## Returns {"count", "tri": PackedInt32Array, "vert": PackedInt32Array}.
static func pieces(vx: PackedVector3Array, ix: PackedInt32Array) -> Dictionary:
	var n := vx.size()
	var parent := PackedInt32Array()
	parent.resize(n)
	for i in n:
		parent[i] = i
	var by_pos := {}
	for i in n:
		var v := vx[i]
		if by_pos.has(v):
			_union(parent, i, by_pos[v])
		else:
			by_pos[v] = i
	for t in range(0, ix.size(), 3):
		_union(parent, ix[t], ix[t + 1])
		_union(parent, ix[t], ix[t + 2])
	var label := PackedInt32Array()
	label.resize(n)
	label.fill(-1)
	var vert := PackedInt32Array()
	vert.resize(n)
	var count := 0
	for i in n:
		var r := _find(parent, i)
		if label[r] < 0:
			label[r] = count
			count += 1
		vert[i] = label[r]
	var tri := PackedInt32Array()
	tri.resize(ix.size() / 3)
	for t in tri.size():
		tri[t] = vert[ix[t * 3]]
	return {"count": count, "tri": tri, "vert": vert}


static func _find(parent: PackedInt32Array, i: int) -> int:
	var r := i
	while parent[r] != r:
		r = parent[r]
	while parent[i] != r:
		var up := parent[i]
		parent[i] = r
		i = up
	return r


static func _union(parent: PackedInt32Array, a: int, b: int) -> void:
	var ra := _find(parent, a)
	var rb := _find(parent, b)
	if ra != rb:
		parent[maxi(ra, rb)] = mini(ra, rb)


## Per-piece area, area centroid and size, the thinnable set, and the pieces' Morton ranks.
## Returns {} when the surface has too few pieces to thin.
static func analyse(vx: PackedVector3Array, ix: PackedInt32Array) -> Dictionary:
	var info := pieces(vx, ix)
	var count: int = info.count
	if count < MIN_PIECES:
		return {}
	var tri: PackedInt32Array = info.tri
	var area := PackedFloat64Array()
	area.resize(count)
	var centre := PackedVector3Array()
	centre.resize(count)
	var lo := PackedVector3Array()
	lo.resize(count)
	var hi := PackedVector3Array()
	hi.resize(count)
	var seen := PackedByteArray()
	seen.resize(count)
	for t in tri.size():
		var a := vx[ix[t * 3]]
		var b := vx[ix[t * 3 + 1]]
		var c := vx[ix[t * 3 + 2]]
		var k := tri[t]
		var w := 0.5 * (b - a).cross(c - a).length()
		area[k] += w
		centre[k] += (a + b + c) * (w / 3.0)
		var tlo := a.min(b).min(c)
		var thi := a.max(b).max(c)
		if seen[k] == 0:
			seen[k] = 1
			lo[k] = tlo
			hi[k] = thi
		else:
			lo[k] = lo[k].min(tlo)
			hi[k] = hi[k].max(thi)
	var tris_in := PackedInt32Array()
	tris_in.resize(count)
	for t in tri.size():
		tris_in[tri[t]] += 1
	var cards := 0
	for k in count:
		if tris_in[k] == 2:
			cards += 1
	var diag := PackedFloat32Array()
	diag.resize(count)
	var box := AABB(vx[0], Vector3.ZERO)
	var whole := AABB(lo[0], hi[0] - lo[0])
	for k in count:
		centre[k] = centre[k] / area[k] if area[k] > 0.0 else (lo[k] + hi[k]) * 0.5
		diag[k] = (hi[k] - lo[k]).length()
		box = box.expand(centre[k])
		whole = whole.expand(lo[k]).expand(hi[k])
	var sorted := diag.duplicate()
	sorted.sort()
	var big := float(sorted[count / 2]) * BIG_PIECE
	# Morton order of the thinnable pieces' centres, so every stride-th one is spread evenly
	# through the crown and each coarser level keeps a subset of the finer one's pieces.
	var keys: Array = []
	var span := box.size.max(Vector3(1e-4, 1e-4, 1e-4))
	var cells := float((1 << MORTON_BITS) - 1)
	for k in count:
		if diag[k] > big:
			continue
		var q := ((centre[k] - box.position) / span * cells).round()
		keys.append([_morton(int(q.x), int(q.y), int(q.z)), k])
	keys.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0] or (x[0] == y[0] and x[1] < y[1]))
	var rank := PackedInt32Array()
	rank.resize(count)
	rank.fill(-1)
	for r in keys.size():
		rank[keys[r][1]] = r
	info.merge({"area": area, "centre": centre, "lo": lo, "hi": hi, "whole": whole, "diag": diag,
		"rank": rank, "thinnable": keys.size(), "cards": cards})
	return info


static func _spread(v: int) -> int:
	var x := v & 0x3ff
	x = (x | (x << 16)) & 0x30000ff
	x = (x | (x << 8)) & 0x300f00f
	x = (x | (x << 4)) & 0x30c30c3
	x = (x | (x << 2)) & 0x9249249
	return x


static func _morton(x: int, y: int, z: int) -> int:
	return _spread(x) | (_spread(y) << 1) | (_spread(z) << 2)


## Which thinnable pieces a level keeps: those whose Morton rank is `phase` modulo `stride`
## (1 kept, 2 a big piece kept as it is, 0 dropped).
static func kept(info: Dictionary, stride: int, phase: int) -> PackedByteArray:
	var rank: PackedInt32Array = info.rank
	var keep := PackedByteArray()
	keep.resize(int(info.count))
	for k in keep.size():
		if rank[k] < 0:
			keep[k] = 2
		elif rank[k] % stride == phase:
			keep[k] = 1
	return keep


## One thinned level of a surface: the pieces kept(stride, phase) picks, each grown about its
## centre by `grow` (the tool works it out so the level's textured cover is level 0's; 0 grows
## by area instead) and then slid back inside the surface's own bounds if the growth took it
## out (at a 1-in-32 level a piece grows 5.7 times, and the crown's outline must not), plus every
## big piece as it is. Returns {"arrays": the level's vertices (the same slots as `arrays`, INDEX
## null), "index": PackedInt32Array into them, "grow"} - or {} if nothing would be removed.
static func thin(arrays: Array, info: Dictionary, stride: int, phase: int = 0, grow: float = 0.0) -> Dictionary:
	var vx: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var ix: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var area: PackedFloat64Array = info.area
	var centre: PackedVector3Array = info.centre
	var lo: PackedVector3Array = info.lo
	var hi: PackedVector3Array = info.hi
	var whole: AABB = info.whole
	var keep := kept(info, stride, phase)
	var total := 0.0
	var kept_area := 0.0
	for k in keep.size():
		if info.rank[k] >= 0:
			total += area[k]
			if keep[k] == 1:
				kept_area += area[k]
	if kept_area <= 0.0 or kept_area >= total:
		return {}
	if grow <= 0.0:
		grow = sqrt(total / kept_area)
	# Each kept piece's slide back inside the bounds, from its grown box.
	var slide := PackedVector3Array()
	slide.resize(keep.size())
	for k in keep.size():
		if keep[k] != 1:
			continue
		var glo := centre[k] + (lo[k] - centre[k]) * grow
		var ghi := centre[k] + (hi[k] - centre[k]) * grow
		slide[k] = (whole.position - glo).max(Vector3.ZERO) - (ghi - whole.end).max(Vector3.ZERO)
	var vcomp: PackedInt32Array = info.vert
	var n := vx.size()
	var remap := PackedInt32Array()
	remap.resize(n)
	remap.fill(-1)
	var picked := PackedInt32Array()
	for i in n:
		if keep[vcomp[i]] != 0:
			remap[i] = picked.size()
			picked.append(i)
	var out: Array = []
	out.resize(Mesh.ARRAY_MAX)
	for slot in Mesh.ARRAY_MAX:
		if slot == Mesh.ARRAY_INDEX or arrays[slot] == null:
			continue
		out[slot] = _gather(arrays[slot], picked, n)
	var moved: PackedVector3Array = out[Mesh.ARRAY_VERTEX]
	for j in picked.size():
		var k := vcomp[picked[j]]
		if keep[k] == 1:
			moved[j] = centre[k] + (moved[j] - centre[k]) * grow + slide[k]
	out[Mesh.ARRAY_VERTEX] = moved
	var idx := PackedInt32Array()
	for t in range(0, ix.size(), 3):
		if keep[vcomp[ix[t]]] != 0:
			idx.append(remap[ix[t]])
			idx.append(remap[ix[t + 1]])
			idx.append(remap[ix[t + 2]])
	return {"arrays": out, "index": idx, "grow": grow}


## A surface's outline: along each axis, where the first and the last 1 % of its area lie
## ([low, high]; each triangle's area shared between its corners, binned to 1/4096 of its span),
## so one stray twig at the tip of a limb does not move it the way it moves a bounding box.
static func outline(vx: PackedVector3Array, ix: PackedInt32Array) -> Array:
	const BINS := 4096
	var box := AABB(vx[ix[0]], Vector3.ZERO)
	for i in ix:
		box = box.expand(vx[i])
	var lo := box.position
	var hi := box.end
	for axis in 3:
		var span := maxf(box.size[axis], 1e-6)
		var bins := PackedFloat64Array()
		bins.resize(BINS)
		var total := 0.0
		for t in range(0, ix.size(), 3):
			var a := vx[ix[t]]
			var b := vx[ix[t + 1]]
			var c := vx[ix[t + 2]]
			var w := (b - a).cross(c - a).length() / 6.0
			total += 3.0 * w
			for v: Vector3 in [a, b, c]:
				bins[clampi(int((v[axis] - box.position[axis]) / span * BINS), 0, BINS - 1)] += w
		var run := 0.0
		var first := -1
		var last := BINS - 1
		for k in BINS:
			run += bins[k]
			if first < 0 and run >= total * 0.01:
				first = k
			if run >= total * 0.99:
				last = k
				break
		lo[axis] = box.position[axis] + span * float(maxi(first, 0)) / BINS
		hi[axis] = box.position[axis] + span * float(last + 1) / BINS
	return [lo, hi]


## How far one outline (outline()) moved from another, in metres: the biggest shift of any side.
static func outline_drift(a: Array, b: Array) -> float:
	var d_lo: Vector3 = ((a[0] as Vector3) - (b[0] as Vector3)).abs()
	var d_hi: Vector3 = ((a[1] as Vector3) - (b[1] as Vector3)).abs()
	return maxf(d_lo[d_lo.max_axis_index()], d_hi[d_hi.max_axis_index()])


## How much of a texel is leaf rather than the black it was photographed on: the cut-out
## foliage_tex.gdshader draws, in the sRGB numbers of the source JPG (its Compatibility band).
static func cutout(c: Color) -> float:
	return smoothstep(0.07, 0.17, maxf(c.r, maxf(c.g, c.b)))


## Each piece's textured cover (area times the cut-out at each triangle's UV centre) and the
## colour summed over that cover, from the surface's source albedo image. The tool picks each
## thinned level's phase and growth from these; the smoke test measures levels the same way.
static func piece_cover(arrays: Array, info: Dictionary, img: Image) -> Dictionary:
	var vx: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var ix: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
	var tri: PackedInt32Array = info.tri
	var cover := PackedFloat64Array()
	cover.resize(int(info.count))
	var tone := PackedColorArray()
	tone.resize(int(info.count))
	var w := img.get_width() if img else 1
	var h := img.get_height() if img else 1
	for t in tri.size():
		var a := vx[ix[t * 3]]
		var b := vx[ix[t * 3 + 1]]
		var c := vx[ix[t * 3 + 2]]
		var col := Color.WHITE
		if img and not uv.is_empty():
			var m := (uv[ix[t * 3]] + uv[ix[t * 3 + 1]] + uv[ix[t * 3 + 2]]) / 3.0
			col = img.get_pixel(posmod(int(m.x * w), w), posmod(int(m.y * h), h))
		var k := 0.5 * (b - a).cross(c - a).length() * cutout(col)
		cover[tri[t]] += k
		tone[tri[t]] += col * k
	return {"cover": cover, "tone": tone}


## `src` (one vertex attribute array of `n` vertices) restricted to the vertices in `picked`.
static func _gather(src: Variant, picked: PackedInt32Array, n: int) -> Variant:
	var out: Variant = src.duplicate()
	var stride: int = src.size() / maxi(n, 1)
	out.resize(picked.size() * stride)
	for j in picked.size():
		var i := picked[j]
		for c in stride:
			out[j * stride + c] = src[i * stride + c]
	return out


## Builds the ladder mesh for one scanned plant from `im` (its merged surfaces, LODs already
## generated) and its table entry (FoliageLodTable.TABLE[file]): per surface, the levels the
## tool picked, their vertices appended after the original ones and their indices as LODs at
## their measured edges. Returns [mesh, shadow_mesh or null], or [] when the table does not match
## this model (a re-exported model or another engine's simplifier) - the caller then keeps the
## generated LODs, and the smoke test says so. `planted` is the biggest scale the species is
## planted at in the streets (PropFactory.foliage_planted_scale()), for the shadow twin's start.
static func build(im: ImporterMesh, entry: Dictionary, planted: float = 1.0) -> Array:
	var surfaces: Array = entry.get("surfaces", [])
	if surfaces.size() != im.get_surface_count():
		return []
	var mesh := ArrayMesh.new()
	var shadow := ArrayMesh.new()
	var shadow_saves := false
	for s in im.get_surface_count():
		var spec: Dictionary = surfaces[s]
		var arrays := im.get_surface_arrays(s)
		var base: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		if base.size() / 3 != int(spec.tris):
			return []
		var levels: Array = spec.levels
		var info := {}
		var level_idx: Array = []
		var appended: Array = arrays.duplicate()
		var offset: int = (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		for lv: Array in levels:
			var kind: String = lv[0]
			var idx := PackedInt32Array()
			if kind == "gen":
				var l: int = lv[1]
				if l >= im.get_surface_lod_count(s):
					return []
				idx = im.get_surface_lod_indices(s, l)
			else:
				if info.is_empty():
					info = analyse(arrays[Mesh.ARRAY_VERTEX], base)
					if info.is_empty():
						return []
				var th := thin(arrays, info, int(lv[1]), int(lv[4]), float(lv[5]))
				if th.is_empty():
					return []
				idx = (th.index as PackedInt32Array).duplicate()
				for i in idx.size():
					idx[i] += offset
				var add: Array = th.arrays
				for slot in Mesh.ARRAY_MAX:
					if slot == Mesh.ARRAY_INDEX or appended[slot] == null:
						continue
					appended[slot] = appended[slot] + add[slot]
				offset += (add[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
			if idx.size() / 3 != int(lv[2]):
				return []
			level_idx.append(idx)
		var lods := {}
		for i in levels.size():
			lods[float(levels[i][3])] = level_idx[i]
		lods[COUNTER_EDGE] = _counter_copy(level_idx[-1] if not level_idx.is_empty() else base)
		appended[Mesh.ARRAY_INDEX] = base
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, appended, [], lods)
		mesh.surface_set_material(mesh.get_surface_count() - 1, im.get_surface_material(s))
		mesh.surface_set_name(mesh.get_surface_count() - 1, im.get_surface_name(s))
		# The shadow twin: the same buffer, starting at the level the table names (the coarsest
		# whose departure a shadow map cannot show), the coarser ones still its LODs.
		var first := shadow_level(levels, planted)
		var shadow_arrays: Array = appended.duplicate()
		var shadow_lods := {}
		if first >= 0:
			shadow_arrays[Mesh.ARRAY_INDEX] = level_idx[first]
			for i in range(first + 1, levels.size()):
				shadow_lods[float(levels[i][3])] = level_idx[i]
			shadow_lods[COUNTER_EDGE] = _counter_copy(level_idx[-1])
			shadow_saves = true
		else:
			shadow_lods = lods
		shadow.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, shadow_arrays, [], shadow_lods)
		shadow.surface_set_material(shadow.get_surface_count() - 1, im.get_surface_material(s))
	return [mesh, shadow if shadow_saves else null]


## The counter's copy of a level (COUNTER_EDGE): one triangle short, because the renderer drops a
## LOD with as many indices as the surface itself (a twin that starts at its last level).
static func _counter_copy(idx: PackedInt32Array) -> PackedInt32Array:
	return idx.slice(0, maxi(idx.size() - 3, 3))


## The level a surface's shadow twin starts at (see SHADOW_EDGE), or -1 for its full detail.
static func shadow_level(levels: Array, planted: float) -> int:
	var first := -1
	for i in levels.size():
		if float(levels[i][3]) * planted <= SHADOW_EDGE:
			first = i
	return first
