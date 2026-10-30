class_name Occluders
extends RefCounted
## Occluders for what hides the city besides its buildings (CityChunk._build_occluder() covers
## those): the hill terrain, the freeway decks, the river's banks and the sound walls along the
## freeway, one more OccluderInstance3D a chunk ("OccluderExtra"); and the mountains past the
## streamed chunks, one OccluderInstance3D under the streamer ("MountainOccluder", MountainOccluder).
##
## The rule is CityChunk's: an occluder never stands outside what it stands for, or whatever is
## behind the sliver is culled while it is in plain sight. Each one here lies INSIDE the solid it
## stands for, by construction:
##   * terrain: a coarse grid whose every vertex is the LOWEST fine sample of every coarse cell
##     round it, less TERRAIN_DROP. The drawn tile is linear between its fine samples, so it is
##     never under the lowest of them, and a coarse triangle is never over its highest vertex: the
##     whole sheet is under the ground. A camera above the ground then cannot see a point of it
##     without looking through the ground first.
##   * a freeway deck: a box inside the segment's own collision box (the box girder), pulled in
##     DECK_EDGE from each side and DECK_SKIN from its top and soffit, short of both joints.
##   * a river bank: the bank's slope pushed BANK_PUSH out into the earth and down, short of the
##     coping; nothing over a ramp's slot.
##   * a sound wall: a sheet in the panel's mid-plane, short of its ends and its cap.
## Small or flat pieces are left out: they cost the occlusion raster more than they hide.
##
## OCCLUDERS=0 in the environment builds none of it (the A/B). Godot's occlusion culling is a
## no-op on the web, so this costs nothing there.

static var enabled := OS.get_environment("OCCLUDERS") != "0"

## Target size of a terrain occluder cell (metres). A tile is ~100-150 m, so 4-6 cells a side.
const TERRAIN_CELL := 26.0
## Metres every terrain occluder vertex sits under the lowest ground of the cells round it (a
## mansion pool is a pit in its pad: the sheet stays under its floor).
const TERRAIN_DROP := 2.5
## A cell whose ground spans fewer metres than this is flat: under it hides only what is buried.
const TERRAIN_MIN_RELIEF := 4.0
## Deck: metres in from each edge (the barriers' feet and the cantilever's thin fascia), in from
## the asphalt and up from the soffit, and short of each end of the segment.
const DECK_EDGE := 1.0
const DECK_SKIN := 0.2
const DECK_END := 0.3
## River bank: metres into the earth (outward and down) from the concrete slope.
const BANK_PUSH := 0.5
## Banks lower than this (the mouth) are left out.
const BANK_MIN_DEPTH := 3.5
## Sound wall: metres short of each panel's end and of its top.
const WALL_END := 0.15
const WALL_TOP := 0.3
const WALL_MIN_HEIGHT := 3.5

## Triangles built, by kind, since the last reset (the checks read it).
static var stats := {"terrain": 0, "deck": 0, "bank": 0, "wall": 0}
## The last sound wall sheets built (the probe reads it to place a camera).
static var last_walls: Array = []


## Before the chunk's commits clear them: the sound wall panels YardFill laid.
static func collect(ch: CityChunk) -> void:
	if not enabled or ch.capturing or ch._yard_walls.is_empty():
		return
	var walls: Array = []
	for w: Array in ch._yard_walls:
		if int(w[2]) == YardFill.W_SOUND and float(w[4]) >= WALL_MIN_HEIGHT:
			walls.append([w[0], w[1]])
	if not walls.is_empty():
		ch.set_meta("occ_walls", walls)


## After CityChunk._build_occluder(): the chunk's extra occluder.
static func build(ch: CityChunk) -> void:
	if not enabled or ch.capturing:
		return
	var verts := PackedVector3Array()
	var idx := PackedInt32Array()
	_terrain(ch, verts, idx)
	_decks(ch, verts, idx)
	_banks(ch, verts, idx)
	_walls(ch, verts, idx)
	if ch.has_meta("occ_walls"):
		ch.remove_meta("occ_walls")
	if idx.is_empty():
		return
	var occ := ArrayOccluder3D.new()
	occ.set_arrays(verts, idx)
	var node := OccluderInstance3D.new()
	node.name = "OccluderExtra"
	node.occluder = occ
	ch.add_child(node)


static func _quad(verts: PackedVector3Array, idx: PackedInt32Array, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	var o := verts.size()
	verts.append_array(PackedVector3Array([a, b, c, d]))
	idx.append_array(PackedInt32Array([o, o + 1, o + 2, o, o + 2, o + 3]))


# --- Terrain -------------------------------------------------------------------------------------

## The hill tile's ground as a coarse sheet under it (see the header for why it is under).
static func _terrain(ch: CityChunk, verts: PackedVector3Array, idx: PackedInt32Array) -> void:
	var g: Dictionary = ch._terrain_grid
	if g.is_empty():
		return
	var heights: PackedFloat32Array = g.heights
	var n: int = g.n
	var area: Rect2 = g.area
	var m := clampi(ceili(maxf(area.size.x, area.size.y) / TERRAIN_CELL), 1, n)
	var cells := terrain_cells(heights, n, m)
	var lo: PackedFloat32Array = cells[0]
	var hi: PackedFloat32Array = cells[1]
	var vh := terrain_vertices(lo, m)
	for cj in m:
		for ci in m:
			var c := cj * m + ci
			if hi[c] - lo[c] < TERRAIN_MIN_RELIEF:
				continue
			var x0 := area.position.x + area.size.x * ci / m
			var x1 := area.position.x + area.size.x * (ci + 1) / m
			var z0 := area.position.y + area.size.y * cj / m
			var z1 := area.position.y + area.size.y * (cj + 1) / m
			_quad(verts, idx,
				Vector3(x0, vh[cj * (m + 1) + ci], z0), Vector3(x1, vh[cj * (m + 1) + ci + 1], z0),
				Vector3(x1, vh[(cj + 1) * (m + 1) + ci + 1], z1), Vector3(x0, vh[(cj + 1) * (m + 1) + ci], z1))
			stats.terrain += 2


## The fine grid's lowest and highest sample in each of m x m coarse cells (edges included):
## [lo, hi], m * m each.
static func terrain_cells(heights: PackedFloat32Array, n: int, m: int) -> Array:
	var lo := PackedFloat32Array()
	var hi := PackedFloat32Array()
	lo.resize(m * m)
	hi.resize(m * m)
	for cj in m:
		var j0 := cj * n / m
		# Rounded out, so the fine samples cover the whole coarse cell.
		var j1 := mini(n, ((cj + 1) * n + m - 1) / m)
		for ci in m:
			var i0 := ci * n / m
			var i1 := mini(n, ((ci + 1) * n + m - 1) / m)
			var a := INF
			var b := -INF
			for j in range(j0, j1 + 1):
				for i in range(i0, i1 + 1):
					var h := heights[j * (n + 1) + i]
					a = minf(a, h)
					b = maxf(b, h)
			lo[cj * m + ci] = a
			hi[cj * m + ci] = b
	return [lo, hi]


## Each coarse vertex: the lowest of the (up to four) cells it is a corner of, less TERRAIN_DROP.
static func terrain_vertices(lo: PackedFloat32Array, m: int) -> PackedFloat32Array:
	var vh := PackedFloat32Array()
	vh.resize((m + 1) * (m + 1))
	for vj in m + 1:
		for vi in m + 1:
			var h := INF
			for cj in [vj - 1, vj]:
				for ci in [vi - 1, vi]:
					if cj >= 0 and cj < m and ci >= 0 and ci < m:
						h = minf(h, lo[cj * m + ci])
			vh[vj * (m + 1) + vi] = h - TERRAIN_DROP
	return vh


# --- Freeway decks -------------------------------------------------------------------------------

## A box inside each deck segment this chunk builds (the segments it builds collision for).
static func _decks(ch: CityChunk, verts: PackedVector3Array, idx: PackedInt32Array) -> void:
	var segs := ch._freeway_segments()
	if segs.is_empty():
		return
	var area := ch.owned_rect()
	for seg in segs:
		if seg.has("link"):
			continue
		var a: Vector2 = seg.a
		var b: Vector2 = seg.b
		var len := a.distance_to(b)
		if len < 2.0 * DECK_END + 1.0 or not area.has_point(a.lerp(b, 0.5)):
			continue
		var box := deck_box(seg)
		_box(verts, idx, box[0], box[1])
		stats.deck += 12


## The occluder box of one deck segment: [Basis (axes scaled to half extents), centre] in the
## chunk's (true world) space, inside the collision box CityChunk._build_freeway() gives it.
static func deck_box(seg: Dictionary) -> Array:
	var a: Vector2 = seg.a
	var b: Vector2 = seg.b
	var ha: float = seg.ha
	var hb: float = seg.hb
	var len := a.distance_to(b)
	var dir := (b - a) / len
	var nrm := Vector2(-dir.y, dir.x)
	var fwd := Vector3(b.x - a.x, hb - ha, b.y - a.y).normalized()
	var right := Vector3(nrm.x, 0.0, nrm.y)
	var up := right.cross(fwd).normalized()
	var t := Freeway.DECK_THICKNESS
	var mid := a.lerp(b, 0.5)
	var centre := Vector3(mid.x, (ha + hb) * 0.5 - t * 0.5, mid.y)
	var half := Vector3(float(seg.width) * 0.5 - DECK_EDGE, t * 0.5 - DECK_SKIN, len * 0.5 - DECK_END)
	return [Basis(right * half.x, up * half.y, fwd * half.z), centre]


## A box's six faces (unit cube corners through `basis`, about `centre`).
static func _box(verts: PackedVector3Array, idx: PackedInt32Array, basis: Basis, centre: Vector3) -> void:
	var o := verts.size()
	for y: float in [-1.0, 1.0]:
		for c: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			verts.append(centre + basis * Vector3(c.x, y, c.y))
	for f: Array in [[0, 1, 5, 4], [1, 2, 6, 5], [2, 3, 7, 6], [3, 0, 4, 7], [4, 5, 6, 7], [0, 3, 2, 1]]:
		idx.append_array(PackedInt32Array([o + f[0], o + f[1], o + f[2], o + f[0], o + f[2], o + f[3]]))


# --- River banks ---------------------------------------------------------------------------------

## The two banks of each centre-line segment this chunk builds (RiverBuild._channel_step()'s
## rule: the segment's midpoint in the chunk's area), pushed into the earth.
static func _banks(ch: CityChunk, verts: PackedVector3Array, idx: PackedInt32Array) -> void:
	if ch._river_build == null or ch.plan.macro == null or ch.plan.macro.river == null:
		return
	var rv: LaRiver = ch.plan.macro.river
	var area := ch.owned_rect()
	var ir := rv.index_range(area, LaRiver.BED_HALF_S + LaRiver.DEPTH_S * LaRiver.SLOPE + LaRiver.CORRIDOR + 6.0)
	var ramps := rv.ramps(ch.plan)
	for i in range(ir.x, ir.y):
		if not area.has_point(rv.pts[i].lerp(rv.pts[i + 1], 0.5)):
			continue
		var s0 := rv.run[i]
		var s1 := rv.run[i + 1]
		for side: float in [-1.0, 1.0]:
			var q := bank_quad(rv, s0, s1, side, ramps)
			if q.is_empty():
				continue
			_quad(verts, idx, q[0], q[1], q[2], q[3])
			stats.bank += 2


## One bank between s0 and s1 on `side` (+1 west, -1 east) as four points (toe s0, toe s1, top s1,
## top s0), or [] where it is too low or a ramp cuts it.
static func bank_quad(rv: LaRiver, s0: float, s1: float, side: float, ramps: Array) -> Array:
	if rv.depth(s0) < BANK_MIN_DEPTH or rv.depth(s1) < BANK_MIN_DEPTH:
		return []
	for r: Dictionary in ramps:
		if float(r.side) != side:
			continue
		var r0 := minf(float(r.s0), float(r.s1)) - 2.0
		var r1 := maxf(float(r.s0), float(r.s1)) + 2.0
		if s1 > r0 and s0 < r1:
			return []
	var out: Array = []
	for e: Array in [[s0, false], [s1, false], [s1, true], [s0, true]]:
		var s: float = e[0]
		var top: bool = e[1]
		var o := (rv.top_half(s) if top else rv.bed_half(s)) + BANK_PUSH
		var p := rv.point(s, side * o)
		var y := (rv.top_at(s) if top else rv.toe_at(s)) - BANK_PUSH
		out.append(Vector3(p.x, y, p.y))
	return out


# --- Sound walls ---------------------------------------------------------------------------------

static func _walls(ch: CityChunk, verts: PackedVector3Array, idx: PackedInt32Array) -> void:
	if not ch.has_meta("occ_walls"):
		return
	for w: Array in ch.get_meta("occ_walls"):
		var q := wall_quad(w[0], w[1])
		if q.is_empty():
			continue
		_quad(verts, idx, q[0], q[1], q[2], q[3])
		stats.wall += 2
		last_walls.append(q)


## A panel's sheet (box size, box centre) in its mid-plane, or [] for a short one.
static func wall_quad(size: Vector3, c: Vector3) -> Array:
	var along_x := size.x >= size.z
	var half := (size.x if along_x else size.z) * 0.5 - WALL_END
	if half < 1.0:
		return []
	var ax := Vector3(half, 0.0, 0.0) if along_x else Vector3(0.0, 0.0, half)
	var y0 := c.y - size.y * 0.5 + 0.05
	var y1 := c.y + size.y * 0.5 - WALL_TOP
	var p := Vector3(c.x, 0.0, c.z)
	return [p - ax + Vector3(0, y0, 0), p + ax + Vector3(0, y0, 0), p + ax + Vector3(0, y1, 0), p - ax + Vector3(0, y1, 0)]
