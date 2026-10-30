class_name ArroyoBuild
extends RefCounted
## A hill chunk's share of the dry creek beds (Arroyos is the network): its build steps.
##
## field_steps() go between the shells' keep-out and the terrain mesh (_mark_shell_ground ..
## _build_terrain): wait for the network, snap the lines through this tile into the gully floor
## (a few points a call), keep the points on natural ground (|height_at - raw_height_at| under
## NATURAL: no road bed, bank, pad or cut), find the culverts, and work out every tile vertex's
## distance to the bed (`bed`), which keeps the hill shells' grass out of the bed.
## build_steps() go after the planting: the bed (the tile's own triangles near a wash, subdivided
## and drawn again on shaders/arroyo_bed.gdshader, FULL and LOD), then at FULL only the cobbles and
## boulders, the willow and mule-fat thickets and sycamores on the banks, and the culverts.
## Every roll is a hash of the seed and the line point (never the chunk's or the block's rng), so
## nothing else a seed builds moves; HillPlanting's own planting only skips the bed (after its
## rolls, CityChunk._plant_hills()).

## Ground counts as natural (not carved) within this many metres of the raw mountains.
const NATURAL := 0.3
## Tile triangles are drawn again where a corner is within this of the bed (plus half a cell).
const BED_REACH := 1.6
## Subdivision of a FULL tile triangle for the bed (a 5 m quad into 1.25 m pieces), LOD.
const SUB_FULL := 4
const SUB_LOD := 2
## Per 4 m segment: cobble clusters, boulder odds on the bank, in the bed.
const COBBLES := Vector2i(2, 5)
const BOULDER_BANK := 0.32
const BOULDER_BED := 0.07
## Bank planting odds per segment side, scaled by the bed's width (1 at 6 m).
const WILLOW := 0.24
const MULEFAT := 0.55
const SYCAMORE := 0.06
## Caps a chunk.
const MAX_TREES := 30
const MAX_SHRUBS := 160
const MAX_COBBLES := 520
const MAX_CULVERTS := 3
## A culvert needs this much road over the toes, and the gap it bridges at most this long.
const CULVERT_MIN_FILL := 1.0
const CULVERT_MAX_RUN := 110.0

var ch: CityChunk
var net: Arroyos.Net
## Line point refs still to snap, and what has been worked out.
var _todo := PackedInt32Array()
var _started: bool = false
## Points through this tile: line -> [[pi, Vector2 snapped, width, natural]], in line order.
var _lines: Dictionary = {}
## Bed segments: [a, b, wa, wb, line, pi] (natural on both ends).
var segs: Array = []
## Segment indices by 16 m cell.
var _cells: Dictionary = {}
## Per tile vertex: metres to the bed's edge (negative inside), or INF.
var bed := PackedFloat32Array()
var culverts: Array = []
var _segs_done: bool = false

const CELL := 16.0
## Prints why each carved run did or did not get a culvert (tools/arroyos/culvert_probe).
static var debug: bool = false
## ARROYO_TRACE=1 prints every step as it starts and ends (stderr).
static var trace: bool = OS.get_environment("ARROYO_TRACE") == "1"


static func _make(ch: CityChunk) -> ArroyoBuild:
	var b: ArroyoBuild = ch.get_meta("arroyo_build") if ch.has_meta("arroyo_build") else null
	if b == null:
		b = ArroyoBuild.new()
		b.ch = ch
		ch.set_meta("arroyo_build", b)
	return b


## The steps between the shells' keep-out and the terrain mesh ([] when off or capturing).
static func field_steps(ch: CityChunk) -> Array[Callable]:
	if not Arroyos.enabled or ch.capturing or ch.plan.macro == null:
		return []
	var b := _make(ch)
	return [b._timed(b._field)]


## The steps after the planting (wrapped by the chunk so the batch adds no relief).
static func build_steps(ch: CityChunk) -> Array[Callable]:
	if not Arroyos.enabled or ch.capturing or ch.plan.macro == null:
		return []
	var b := _make(ch)
	if ch.level == CityChunk.Level.FULL:
		return [b._timed(b._bed_mesh), b._timed(b._stones), b._timed(b._banks), b._timed(b._culverts)]
	return [b._timed(b._bed_mesh)]


## Microseconds this chunk's arroyo steps took (meta "arroyo_usec"), the longest call in
## "arroyo_max_usec" (the checks print them).
func _timed(step: Callable) -> Callable:
	return func() -> Variant:
		var t0 := Time.get_ticks_usec()
		if trace:
			printerr("ARROYO step %s chunk (%d, %d) level %d" % [step.get_method(), ch.ix, ch.iz, ch.level])
		var done: Variant = step.call()
		if trace:
			printerr("ARROYO done %s %s" % [step.get_method(), done])
		var dt := Time.get_ticks_usec() - t0
		ch.set_meta("arroyo_usec", int(ch.get_meta("arroyo_usec", 0)) + dt)
		ch.set_meta("arroyo_max_usec", maxi(int(ch.get_meta("arroyo_max_usec", 0)), dt))
		return done


## Whether `p` (world XZ) lies within `margin` of a bed in this chunk (the planting asks).
static func in_bed(ch: CityChunk, p: Vector2, margin: float) -> bool:
	if not ch.has_meta("arroyo_build"):
		return false
	var b: ArroyoBuild = ch.get_meta("arroyo_build")
	if not b._segs_done:
		return false
	return b.bed_distance(p) < margin


## Metres from `p` to the nearest bed edge here (negative inside), INF when none is near.
func bed_distance(p: Vector2) -> float:
	var key := Vector2i(floori(p.x / CELL), floori(p.y / CELL))
	var best := INF
	var arr: Variant = _cells.get(key)
	if arr == null:
		return best
	for si: int in arr:
		var s: Array = segs[si]
		var a: Vector2 = s[0]
		var b: Vector2 = s[1]
		var ab := b - a
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		var d := p.distance_to(a + ab * t) - lerpf(s[2], s[3], t) * 0.5
		best = minf(best, d)
	return best


## The nearest segment's [distance to the edge, signed offset across, flow direction, half width,
## line] at `p`, or [] when no bed is in reach.
func bed_frame(p: Vector2) -> Array:
	var key := Vector2i(floori(p.x / CELL), floori(p.y / CELL))
	var arr: Variant = _cells.get(key)
	if arr == null:
		return []
	var best := INF
	var out: Array = []
	for si: int in arr:
		var s: Array = segs[si]
		var a: Vector2 = s[0]
		var b: Vector2 = s[1]
		var ab := b - a
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		var hw := lerpf(s[2], s[3], t) * 0.5
		var q := a + ab * t
		var d := p.distance_to(q) - hw
		if d < best:
			best = d
			var dir := ab.normalized()
			var nrm := Vector2(-dir.y, dir.x)
			out = [d, (p - q).dot(nrm), dir, hw, s[4]]
	return out


# --- The field ---------------------------------------------------------------------------------

func _field() -> bool:
	if not Arroyos.build_step(ch.plan):
		return false
	net = Arroyos.of(ch.plan)
	if net == null:
		_segs_done = true
		return true
	var area := ch.owned_rect()
	if not _started:
		_started = true
		# The points that can reach this tile's bed, and SNAP_SMOOTH more each way for the smoothing.
		_todo = Arroyos.refs_in(net, area, Arroyos.WIDTH_MAX + BED_REACH + 8.0)
	var t0 := Time.get_ticks_usec()
	while not _todo.is_empty():
		if Time.get_ticks_usec() - t0 > 2500:
			return false
		var r := _todo[_todo.size() - 1]
		_todo.resize(_todo.size() - 1)
		var li := r >> 16
		var pi := r & 0xffff
		var w: float = net.lines[li].w[pi]
		var p := Arroyos.snapped(net, li, pi)
		var h := ch.plan.height_at(p)
		var natural := w > 0.0 and h > 1.5 and Arroyos.natural(ch.plan, p, NATURAL)
		if natural and ch.plan.macro.reservoir and ch.plan.macro.reservoir.keep_clear(p, h):
			natural = false
		if natural and Ballpark.covers(p, 3.0):
			natural = false
		if not _lines.has(li):
			_lines[li] = []
		(_lines[li] as Array).append([pi, p, w, natural])
	_build_segments(area)
	_vertex_field(area)
	_segs_done = true
	return true


func _build_segments(area: Rect2) -> void:
	var grown := area.grow(Arroyos.WIDTH_MAX + BED_REACH + 6.0)
	for li: int in _lines:
		var pts: Array = _lines[li]
		pts.sort_custom(func(x: Array, y: Array) -> bool: return int(x[0]) < int(y[0]))
		for k in pts.size() - 1:
			var p0: Array = pts[k]
			var p1: Array = pts[k + 1]
			if int(p1[0]) != int(p0[0]) + 1 or not p0[3] or not p1[3]:
				continue
			var a: Vector2 = p0[1]
			var b: Vector2 = p1[1]
			if not grown.has_point((a + b) * 0.5):
				continue
			var si := segs.size()
			segs.append([a, b, p0[2], p1[2], li, int(p0[0])])
			var r := maxf(p0[2], p1[2]) * 0.5 + BED_REACH + 4.0
			var lo := Vector2(minf(a.x, b.x), minf(a.y, b.y)) - Vector2.ONE * r
			var hi := Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + Vector2.ONE * r
			for cx in range(floori(lo.x / CELL), floori(hi.x / CELL) + 1):
				for cz in range(floori(lo.y / CELL), floori(hi.y / CELL) + 1):
					var key := Vector2i(cx, cz)
					if not _cells.has(key):
						_cells[key] = []
					(_cells[key] as Array).append(si)
		_find_culverts(li, pts, area)


## Every tile vertex's distance to the bed; the hill shells keep their grass out of it.
func _vertex_field(area: Rect2) -> void:
	var n: int = ch._tile_n
	if n <= 0:
		return
	bed.resize((n + 1) * (n + 1))
	for j in n + 1:
		for i in n + 1:
			var p := Vector2(area.position.x + area.size.x * i / n, area.position.y + area.size.y * j / n)
			bed[j * (n + 1) + i] = bed_distance(p)
	if not ch._shell_clear.is_empty() and ch._shell_clear.size() == bed.size():
		for k in bed.size():
			if bed[k] < CityChunk.SHELL_CLEAR_SPAN:
				ch._shell_clear[k] = minf(ch._shell_clear[k], bed[k] - 0.4)


# --- Culverts ----------------------------------------------------------------------------------

## A run of carved points between two natural ones where a drawn hill road crosses: a culvert
## under the road, its inlet at the upstream toe and its outlet at the downstream one (the line
## runs head to foot, so in point order).
func _find_culverts(li: int, pts: Array, area: Rect2) -> void:
	var k := 0
	while k < pts.size():
		var p: Array = pts[k]
		if p[3] or k == 0:
			k += 1
			continue
		var start := k - 1
		var end := k
		while end < pts.size() and not pts[end][3]:
			end += 1
		k = end
		if end >= pts.size() or not pts[start][3]:
			continue
		if int(pts[end][0]) - int(pts[start][0]) != end - start:
			continue
		var a: Vector2 = pts[start][1]
		var b: Vector2 = pts[end][1]
		var mid := (a + b) * 0.5
		var road := _crossing_road(pts, start, end)
		if debug:
			print("RUN line %d %d..%d %.0f m at %s in area %s road %s" % [li, pts[start][0], pts[end][0], a.distance_to(b), mid.round(), area.has_point(mid), not road.is_empty()])
		if a.distance_to(b) > CULVERT_MAX_RUN or not area.has_point(mid) or road.is_empty():
			continue
		var ia := _toe(pts[start][1], pts[start + 1][1])
		var ib := _toe(pts[end][1], pts[end - 1][1])
		var top := ch.plan.height_at(road.at)
		var ha := ch.plan.height_at(ia)
		var hb := ch.plan.height_at(ib)
		if debug:
			print("  fill %.1f over toes %.1f %.1f" % [top - maxf(ha, hb), ha, hb])
		# The road over the outlet's toe (it crosses the gully on fill below the road). Benched into
		# a slope it is in cut above the road: the inlet is a drop inlet in the uphill ditch, at the
		# road's shoulder, not up at the cut's top.
		if top - hb < CULVERT_MIN_FILL:
			continue
		if top - ha < CULVERT_MIN_FILL:
			var rd: Vector2 = (road.b - road.a).normalized()
			var across := Vector2(-rd.y, rd.x)
			var up := (a - b).normalized()
			if across.dot(up) < 0.0:
				across = -across
			ia = road.at + across * (float(road.width) * 0.5 + 1.6)
			# Its pipe's invert a little under the ditch, the headwall standing out of it.
			ha = ch.plan.height_at(ia) - 0.35
		culverts.append({"inlet": ia, "outlet": ib, "ha": ha, "hb": hb, "width": maxf(pts[start][2], pts[end][2]), "line": li, "pi": int(pts[start][0]), "road": road})


## The drawn hill road the points start..end cross (its crossing point), or {}.
func _crossing_road(pts: Array, start: int, end: int) -> Dictionary:
	var hr := ch.plan.macro.hill_roads
	if hr == null:
		return {}
	var a: Vector2 = pts[start][1]
	var b: Vector2 = pts[end][1]
	var box := Rect2(Vector2(minf(a.x, b.x), minf(a.y, b.y)), (b - a).abs()).grow(4.0)
	for seg: Dictionary in hr.segments_in(box):
		if not seg.draw:
			continue
		for k in range(start, end):
			var x: Variant = Geometry2D.segment_intersects_segment(pts[k][1], pts[k + 1][1], seg.a, seg.b)
			if x != null:
				return {"at": x, "a": seg.a, "b": seg.b, "width": seg.width}
	return {}


## Where the natural ground ends between a natural point and the carved one after it.
func _toe(nat: Vector2, carved: Vector2) -> Vector2:
	var lo := 0.0
	var hi := 1.0
	for it in 6:
		var m := (lo + hi) * 0.5
		var q := nat.lerp(carved, m)
		if Arroyos.natural(ch.plan, q, NATURAL):
			lo = m
		else:
			hi = m
	return nat.lerp(carved, lo)


# --- The bed -----------------------------------------------------------------------------------

func _tile_h(i: int, j: int) -> float:
	var n: int = ch._tile_n
	return ch._tile_heights[j * (n + 1) + i]


func _tile_normal(i: int, j: int, cell: Vector2) -> Vector3:
	var n: int = ch._tile_n
	var hl := _tile_h(maxi(i - 1, 0), j)
	var hr := _tile_h(mini(i + 1, n), j)
	var hd := _tile_h(i, maxi(j - 1, 0))
	var hu := _tile_h(i, mini(j + 1, n))
	var dx := (hr - hl) / (cell.x * float(mini(i + 1, n) - maxi(i - 1, 0)))
	var dz := (hu - hd) / (cell.y * float(mini(j + 1, n) - maxi(j - 1, 0)))
	return Vector3(-dx, 1.0, -dz).normalized()


static var _bed_material: ShaderMaterial = null


static func bed_material() -> ShaderMaterial:
	if _bed_material == null:
		var m := ShaderMaterial.new()
		m.shader = load("res://shaders/arroyo_bed.gdshader")
		m.set_shader_parameter("sand_albedo", PropFactory.texture("sand", "Color"))
		m.set_shader_parameter("sand_normal", PropFactory.texture("sand", "NormalGL"))
		m.set_shader_parameter("gravel_albedo", PropFactory.texture("hill_dirt", "Color"))
		m.set_shader_parameter("gravel_normal", PropFactory.texture("hill_dirt", "NormalGL"))
		_bed_material = m
	return _bed_material


## The tile's triangles near a bed, cut finer, drawn again on the bed shader. The pieces lie in
## the tile's own triangles (barycentric), so they sit exactly on the ground drawn.
func _bed_mesh() -> void:
	if segs.is_empty() or ch._tile_heights.is_empty():
		return
	var area := ch.owned_rect()
	var n: int = ch._tile_n
	var cell := area.size / float(n)
	var sub := SUB_FULL if ch.level == CityChunk.Level.FULL else SUB_LOD
	var reach := BED_REACH + cell.length() * 0.5
	if bed.is_empty():
		_vertex_field(area)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tris := 0
	for j in n:
		for i in n:
			var k := j * (n + 1) + i
			if minf(minf(bed[k], bed[k + 1]), minf(bed[k + n + 1], bed[k + n + 2])) > reach:
				continue
			var corner := func(ci: int, cj: int) -> Array:
				return [Vector3(area.position.x + cell.x * ci, _tile_h(ci, cj), area.position.y + cell.y * cj), _tile_normal(ci, cj, cell)]
			var a: Array = corner.call(i, j)
			var b: Array = corner.call(i + 1, j)
			var c: Array = corner.call(i, j + 1)
			var d: Array = corner.call(i + 1, j + 1)
			# The terrain's own split: (a, b, c) and (b, d, c).
			tris += _sub_tri(st, a, b, c, sub)
			tris += _sub_tri(st, b, d, c, sub)
	if tris == 0:
		return
	var mi := MeshInstance3D.new()
	mi.name = "ArroyoBed"
	mi.mesh = st.commit()
	mi.material_override = bed_material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ch.add_child(mi)
	ch.set_meta("arroyo_bed_tris", tris)


func _sub_tri(st: SurfaceTool, a: Array, b: Array, c: Array, m: int) -> int:
	# Barycentric grid of m x m small triangles.
	var verts: Array = []
	for r in m + 1:
		var row: Array = []
		for q in m + 1 - r:
			var u := float(q) / m
			var v := float(r) / m
			var pos: Vector3 = a[0] * (1.0 - u - v) + b[0] * u + c[0] * v
			var nrm: Vector3 = (a[1] * (1.0 - u - v) + b[1] * u + c[1] * v).normalized()
			var f := bed_frame(Vector2(pos.x, pos.z))
			if f.is_empty():
				row.append(null)
			else:
				row.append([pos, nrm, f])
		verts.append(row)
	var count := 0
	for r in m:
		for q in m - r:
			count += _emit(st, verts[r][q], verts[r][q + 1], verts[r + 1][q])
			if q < m - r - 1:
				count += _emit(st, verts[r][q + 1], verts[r + 1][q + 1], verts[r + 1][q])
	return count


func _emit(st: SurfaceTool, va: Variant, vb: Variant, vc: Variant) -> int:
	if va == null or vb == null or vc == null:
		return 0
	# Wholly outside the bed's ragged edge: nothing to draw.
	if float(va[2][0]) > BED_REACH and float(vb[2][0]) > BED_REACH and float(vc[2][0]) > BED_REACH:
		return 0
	# Clockwise seen from above (the terrain's winding: a, b, c with b east of a, c south).
	for v: Array in [va, vb, vc]:
		var f: Array = v[2]
		var dir: Vector2 = f[2]
		var lh := float(hash([ch.plan.seed, int(f[4])]) & 1023) / 1023.0
		st.set_color(Color(dir.x * 0.5 + 0.5, dir.y * 0.5 + 0.5, lh, 1.0))
		st.set_uv(Vector2(f[0], f[3]))
		st.set_uv2(Vector2(f[1], 0.0))
		st.set_normal(v[1])
		st.add_vertex(v[0])
	return 1


# --- Stones ------------------------------------------------------------------------------------

func _h01(parts: Array) -> float:
	return float(hash(parts) & 0xffffff) / float(0xffffff)


## The drawn ground under `p` (the tile's own triangles).
func ground(p: Vector2) -> float:
	var area := ch.owned_rect()
	var n: int = ch._tile_n
	if ch._tile_heights.is_empty():
		return ch.plan.height_at(p)
	var u := (p.x - area.position.x) / area.size.x * n
	var v := (p.y - area.position.y) / area.size.y * n
	if u < 0.0 or v < 0.0 or u > n or v > n:
		return ch.plan.height_at(p)
	var i := mini(int(u), n - 1)
	var j := mini(int(v), n - 1)
	var fu := u - i
	var fv := v - j
	var a := _tile_h(i, j)
	var b := _tile_h(i + 1, j)
	var c := _tile_h(i, j + 1)
	var d := _tile_h(i + 1, j + 1)
	if fu + fv <= 1.0:
		return a + (b - a) * fu + (c - a) * fv
	return d + (c - d) * (1.0 - fu) + (b - d) * (1.0 - fv)


func _owned(p: Vector2) -> bool:
	return ch.owned_rect().has_point(p)


func _stones() -> void:
	var batch: MultiMeshBatch = ch._batch
	var cobbles := 0
	for s: Array in segs:
		var a: Vector2 = s[0]
		var b: Vector2 = s[1]
		var mid := (a + b) * 0.5
		if not _owned(mid):
			continue
		var li: int = s[4]
		var pi: int = s[5]
		var seed := ch.plan.seed
		var dir := (b - a).normalized()
		var nrm := Vector2(-dir.y, dir.x)
		var hw := (float(s[2]) + float(s[3])) * 0.25
		var count := COBBLES.x + int(_h01([seed, li, pi, "ac"]) * (COBBLES.y - COBBLES.x + 1))
		for k in count:
			if cobbles >= MAX_COBBLES:
				break
			var t := _h01([seed, li, pi, k, "at"])
			var o := (_h01([seed, li, pi, k, "ao"]) - 0.5) * 2.0 * hw * 0.95
			var p := a.lerp(b, t) + nrm * o
			var size := lerpf(0.14, 0.42, pow(_h01([seed, li, pi, k, "as"]), 2.0))
			var v := int(_h01([seed, li, pi, k, "av"]) * 3.0) % 3
			var yaw := _h01([seed, li, pi, k, "ay"]) * TAU
			var tone := _h01([seed, li, pi, k, "at2"])
			var y := ground(p) - size * 0.3
			var xf := Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(size, size * 0.7, size * 0.85)), Vector3(p.x, y, p.y))
			batch.add("arroyo_cobble_%d" % v, ArroyoKit.pebble(v), xf, ArroyoKit.stone_tint(tone))
			cobbles += 1
		# Boulders: the bank's foot, now and then out in the bed.
		for side in [-1.0, 1.0]:
			if _h01([seed, li, pi, side, "ab"]) < BOULDER_BANK:
				_boulder(a.lerp(b, _h01([seed, li, pi, side, "abt"])) + nrm * side * (hw + lerpf(-0.2, 0.9, _h01([seed, li, pi, side, "abo"]))),
					[seed, li, pi, side])
		if _h01([seed, li, pi, "abb"]) < BOULDER_BED:
			_boulder(mid + nrm * (_h01([seed, li, pi, "abbo"]) - 0.5) * hw, [seed, li, pi, "bed"])
	ch.set_meta("arroyo_cobbles", cobbles)
	for v in 3:
		batch.set_no_shadow("arroyo_cobble_%d" % v)
		batch.set_draw_distance("arroyo_cobble_%d" % v, 90.0)


func _boulder(p: Vector2, key: Array) -> void:
	if not _owned(p) or ch._near_hill_road(p, ch._hill_segments(), 2.0):
		return
	var v := 0 if _h01(key + ["v"]) < 0.6 else 1
	var sc := lerpf(0.28, 0.75, pow(_h01(key + ["s"]), 1.6))
	var yaw := _h01(key + ["y"]) * TAU
	var tilt := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, (_h01(key + ["t"]) - 0.5) * 0.4)
	var y := ground(p)
	ch._batch.add("rock_%d" % v, PropFactory.model_rock(v), Transform3D(tilt.scaled(Vector3(sc, sc, sc)), Vector3(p.x, y - 0.25 * sc, p.y)))
	var size := (Vector3(2.4, 0.8, 1.2) if v == 0 else Vector3(2.4, 1.8, 2.4)) * sc
	if size.y > 0.5:
		ch._add_shape(size, Vector3(p.x, y + size.y * 0.5 - 0.25 * sc, p.y), yaw)
	var nb: int = ch.get_meta("arroyo_boulders", 0)
	ch.set_meta("arroyo_boulders", nb + 1)


# --- Banks -------------------------------------------------------------------------------------

func _banks() -> void:
	var trees := 0
	var shrubs := 0
	var segs_here := ch._hill_segments()
	var chap := PropFactory.model_chaparral()
	var chap_h := PropFactory.chaparral_height()
	var at_list: Array = []
	for s: Array in segs:
		var a: Vector2 = s[0]
		var b: Vector2 = s[1]
		if not _owned((a + b) * 0.5):
			continue
		var li: int = s[4]
		var pi: int = s[5]
		var seed := ch.plan.seed
		var dir := (b - a).normalized()
		var nrm := Vector2(-dir.y, dir.x)
		var hw := (float(s[2]) + float(s[3])) * 0.25
		var wide := clampf(hw / 3.0, 0.4, 1.4)
		for side: float in [-1.0, 1.0]:
			var roll := _h01([seed, li, pi, side, "bk"])
			var t := _h01([seed, li, pi, side, "bt"])
			var yaw := _h01([seed, li, pi, side, "by"]) * TAU
			var size := _h01([seed, li, pi, side, "bs"])
			if roll < SYCAMORE * wide and trees < MAX_TREES:
				var p := a.lerp(b, t) + nrm * side * (hw + lerpf(3.0, 6.0, size))
				if _bank_ok(p, segs_here, 3.5):
					var sc := LaTrees.scale_for(LaTrees.Species.SYCAMORE, lerpf(10.0, 16.0, size))
					var v := absi(hash([seed, li, "sv"])) % LaTrees.VARIANTS
					LaTrees._add(ch, LaTrees.Species.SYCAMORE, v, Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(sc, sc, sc)), Vector3(p.x, ground(p) - 0.15, p.y)), Color(1, 1, 1))
					trees += 1
					at_list.append([p, "sycamore"])
			elif roll < (SYCAMORE + WILLOW) * wide and trees < MAX_TREES:
				# Arroyo willow: a thicket of grey-green lance leaves (the olive's leaves and pale
				# undersides, greener and taller, in a clump of two or three).
				var base := a.lerp(b, t) + nrm * side * (hw + lerpf(0.8, 2.6, size))
				for k in 1 + int(_h01([seed, li, pi, side, "bn"]) * 2.5):
					var p := base + Vector2(_h01([seed, li, pi, side, k, "wx"]) - 0.5, _h01([seed, li, pi, side, k, "wz"]) - 0.5) * 3.0
					if not _bank_ok(p, segs_here, 1.2) or trees >= MAX_TREES:
						continue
					var sc := LaTrees.scale_for(LaTrees.Species.OLIVE, lerpf(4.0, 7.0, _h01([seed, li, pi, side, k, "wh"])))
					var xf := Transform3D(Basis(Vector3.UP, yaw + k * 2.1).scaled(Vector3(sc * 0.8, sc * 1.15, sc * 0.8)), Vector3(p.x, ground(p) - 0.1, p.y))
					LaTrees._add(ch, LaTrees.Species.OLIVE, absi(hash([seed, li, "wv"])) % LaTrees.VARIANTS, xf, WILLOW_TINT)
					trees += 1
					at_list.append([p, "willow"])
			elif roll < (SYCAMORE + WILLOW + MULEFAT) * wide and shrubs < MAX_SHRUBS:
				# Mule fat: bright green shrubs crowding the bank's foot.
				# A clump of one to three along the bank's foot.
				for k in 1 + int(_h01([seed, li, pi, side, "mn"]) * 2.99):
					var p := a.lerp(b, fposmod(t + k * 0.37, 1.0)) + nrm * side * (hw + lerpf(0.2, 2.2, _h01([seed, li, pi, side, k, "mo"])))
					if shrubs >= MAX_SHRUBS or not _bank_ok(p, segs_here, 0.2):
						continue
					var sc := lerpf(1.3, 2.6, _h01([seed, li, pi, side, k, "ms"])) / chap_h
					ch._batch.add("hill_chaparral", chap, Transform3D(Basis(Vector3.UP, yaw + k * 1.9).scaled(Vector3(sc * 1.25, sc, sc * 1.25)), Vector3(p.x, ground(p) - 0.15, p.y)),
						Color(1.5, 1.95, 1.05), Color(_h01([seed, li, pi, side, k, "m1"]) * 0.3, _h01([seed, li, pi, side, k, "m2"]), 0.9, 0.0))
					shrubs += 1
					at_list.append([p, "mulefat"])
	ch.set_meta("arroyo_banks", at_list)


const WILLOW_TINT := Color(0.86, 1.12, 0.8)


func _bank_ok(p: Vector2, roads: Array[Dictionary], bed_margin: float) -> bool:
	if not _owned(p) or ch._near_hill_road(p, roads, 2.5):
		return false
	if bed_distance(p) < bed_margin:
		return false
	var h := ground(p)
	return h > 1.5 and Arroyos.natural(ch.plan, p, 1.0)


# --- Culverts ----------------------------------------------------------------------------------

func _culverts() -> void:
	var made := 0
	for c: Dictionary in culverts:
		if made >= MAX_CULVERTS:
			break
		var inlet: Vector2 = c.inlet
		var outlet: Vector2 = c.outlet
		var axis := (outlet - inlet).normalized()
		var w: float = c.width
		var r := 0.45 if w < 3.5 else (0.6 if w < 5.5 else 0.75)
		var pipes := 2 if w > 6.5 else 1
		var mesh := ArroyoKit.culvert_mesh(r, pipes)
		for end: int in 2:
			var at: Vector2 = inlet if end == 0 else outlet
			# Facing away from the road: out of the bank toward its own reach of the wash.
			var out := -axis if end == 0 else axis
			var y: float = (c.ha if end == 0 else c.hb) - 0.05
			var basis := Basis(Vector3.UP, atan2(out.x, out.y))
			var mi := MeshInstance3D.new()
			mi.name = "Culvert"
			mi.mesh = mesh
			mi.transform = Transform3D(basis, Vector3(at.x, y, at.y) - basis * Vector3(0, 0, 0.4))
			ch.add_child(mi)
			var span := ArroyoKit.headwall_width(r, pipes)
			ch._add_shape(Vector3(span, 2.0 * r + 0.6, 0.35), Vector3(at.x, y + r, at.y) - basis * Vector3(0, 0, 0.55), atan2(out.x, out.y))
			# Rip-rap below the outlet, a few stones by the inlet.
			for k in (7 if end == 1 else 3):
				var q := at + out * lerpf(0.8, 3.2, _h01([ch.plan.seed, c.line, c.pi, end, k, "rx"])) + Vector2(out.y, -out.x) * (_h01([ch.plan.seed, c.line, c.pi, end, k, "rz"]) - 0.5) * span
				var sz := lerpf(0.35, 0.7, _h01([ch.plan.seed, c.line, c.pi, end, k, "rs"]))
				ch._batch.add("arroyo_cobble_%d" % (k % 3), ArroyoKit.pebble(k % 3),
					Transform3D(Basis(Vector3.UP, k * 1.7).scaled(Vector3(sz, sz * 0.75, sz)), Vector3(q.x, ground(q) - sz * 0.25, q.y)), ArroyoKit.stone_tint(0.3 + k * 0.1))
		made += 1
	ch.set_meta("arroyo_culverts", made)
