class_name HillRoads
extends RefCounted
## Seeded roads through the hills: a winding boulevard along the hill foot, canyon roads
## climbing north, mansion loops branching off them, and a rim drive around the peninsula.
## Each road has a smoothed height profile (grade-limited) and the terrain is carved flat to it,
## with cut/fill shoulders, so cars can actually drive up. Mansion pads are flat spots the same
## way. All coordinates are true world XZ.

## Max road grade (rise per meter of run).
const MAX_GRADE := 0.11
## Shoulder width on each side of a road where terrain blends back to its natural height.
const SHOULDER := 14.0
const PAD_RADIUS := 17.0
const PAD_SHOULDER := 12.0
const CELL := 120.0

## Roads: {"name", "points": PackedVector2Array, "heights": PackedFloat32Array, "width": float,
## "mansions": bool}
var roads: Array[Dictionary] = []
## Mansion lots: {"pos": Vector2, "height": float, "yaw": float, "seed": int, "road": int}
var mansions: Array[Dictionary] = []

var _macro: MacroMap
var _cells: Dictionary = {}
var _pad_cells: Dictionary = {}


func build(macro: MacroMap, seed_value: int) -> void:
	_macro = macro
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 7 + 13
	roads.clear()
	mansions.clear()
	# 1. The boulevard along the hill foot, west (beach) to east.
	var pts := PackedVector2Array()
	var x := macro.coast_x(macro.hills_start_z - 60.0) + macro.beach_width + 10.0
	while x < 1100.0:
		pts.append(Vector2(x, macro.hills_start_z - 60.0 + 90.0 * sin(x / 260.0) + 35.0 * sin(x / 97.0 + 1.3)))
		x += 30.0
	_add_road("Sunset Drive", pts, 16.0, false)
	# 2. Canyon roads climbing north from the boulevard, with mansion loops off each one.
	for start_x: float in [-520.0, -140.0, 260.0, 680.0]:
		var canyon := _walk(Vector2(start_x, _boulevard_z(start_x)), -PI * 0.5, 26, rng, 0.35)
		var ci := _add_road("Canyon %d" % roads.size(), canyon, 12.0, false)
		for frac: float in [0.4, 0.72]:
			var i := int(canyon.size() * frac)
			# Branch east or west, tilted a little uphill or down.
			var tilt := rng.randf_range(-PI * 0.25, PI * 0.25)
			var heading := (0.0 if rng.randf() < 0.5 else PI) + tilt
			var loop := _walk(canyon[i], heading, 9, rng, 0.5)
			var li := _add_road("Estates %d" % roads.size(), loop, 10.0, true)
			_place_mansions(li, rng)
		if ci >= 0 and rng.randf() < 0.5:
			_place_mansions(ci, rng)
	# 3. Rim drive around the peninsula.
	var rim := PackedVector2Array()
	var r := macro.peninsula_radius * 0.6
	for i in 36:
		var a := TAU * i / 36
		rim.append(macro.peninsula_center + Vector2(cos(a), sin(a)) * (r + 25.0 * sin(a * 3.0)))
	rim.append(rim[0])
	var ri := _add_road("Rim Drive", rim, 12.0, true)
	_place_mansions(ri, rng)
	_index()


func _boulevard_z(x: float) -> float:
	return _macro.hills_start_z - 60.0 + 90.0 * sin(x / 260.0) + 35.0 * sin(x / 97.0 + 1.3)


## A smooth random walk of `steps` 30 m segments from `from` heading `heading` (radians, 0 = +X).
func _walk(from: Vector2, heading: float, steps: int, rng: RandomNumberGenerator, wiggle: float) -> PackedVector2Array:
	var pts := PackedVector2Array([from])
	var p := from
	var h := heading
	var turn := 0.0
	for i in steps:
		turn = clampf(turn + rng.randf_range(-wiggle, wiggle) * 0.5, -wiggle, wiggle)
		h += turn * 0.5
		p += Vector2(cos(h), sin(h)) * 30.0
		pts.append(p)
	return pts


func _add_road(road_name: String, pts: PackedVector2Array, width: float, mansions_allowed: bool) -> int:
	if pts.size() < 2:
		return -1
	var raw := PackedFloat32Array()
	for p in pts:
		raw.append(_macro.raw_height_at(p))
	var heights := _smooth(raw)
	heights = _limit_grade(heights, pts)
	roads.append({"name": road_name, "points": pts, "heights": heights, "width": width, "mansions": mansions_allowed})
	return roads.size() - 1


func _smooth(h: PackedFloat32Array) -> PackedFloat32Array:
	var out := h.duplicate()
	for pass_i in 2:
		var src := out.duplicate()
		for i in src.size():
			var sum := 0.0
			var n := 0
			for k in range(-2, 3):
				var j := i + k
				if j >= 0 and j < src.size():
					sum += src[j]
					n += 1
			out[i] = sum / n
	return out


func _limit_grade(h: PackedFloat32Array, pts: PackedVector2Array) -> PackedFloat32Array:
	var out := h.duplicate()
	for i in range(1, out.size()):
		var run := pts[i].distance_to(pts[i - 1])
		out[i] = clampf(out[i], out[i - 1] - MAX_GRADE * run, out[i - 1] + MAX_GRADE * run)
	for i in range(out.size() - 2, -1, -1):
		var run := pts[i].distance_to(pts[i + 1])
		out[i] = clampf(out[i], out[i + 1] - MAX_GRADE * run, out[i + 1] + MAX_GRADE * run)
	return out


func _place_mansions(road_index: int, rng: RandomNumberGenerator) -> void:
	if road_index < 0:
		return
	var road: Dictionary = roads[road_index]
	var pts: PackedVector2Array = road.points
	var heights: PackedFloat32Array = road.heights
	var width: float = road.width
	var along := 20.0
	var i := 0
	while i < pts.size() - 1:
		var seg := pts[i + 1] - pts[i]
		var seg_len := seg.length()
		if along < seg_len:
			var t := along / seg_len
			var p := pts[i].lerp(pts[i + 1], t)
			var h := lerpf(heights[i], heights[i + 1], t)
			var normal := Vector2(-seg.y, seg.x).normalized()
			for side: float in [-1.0, 1.0]:
				if rng.randf() < 0.75:
					var pos := p + normal * side * (width * 0.5 + PAD_RADIUS + 4.0)
					if _macro.raw_height_at(pos) > 3.0 and _macro.zone_at(pos) == MacroMap.Zone.HILLS:
						mansions.append({"pos": pos, "height": h, "yaw": atan2(-normal.x * side, -normal.y * side), "seed": rng.randi(), "road": road_index})
			along += rng.randf_range(44.0, 60.0)
		else:
			along -= seg_len
			i += 1


func _index() -> void:
	_cells.clear()
	_pad_cells.clear()
	for ri in roads.size():
		var pts: PackedVector2Array = roads[ri].points
		var reach: float = roads[ri].width * 0.5 + SHOULDER
		for si in pts.size() - 1:
			var a := pts[si]
			var b := pts[si + 1]
			var lo := Vector2(minf(a.x, b.x), minf(a.y, b.y)) - Vector2.ONE * reach
			var hi := Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + Vector2.ONE * reach
			for cx in range(floori(lo.x / CELL), floori(hi.x / CELL) + 1):
				for cz in range(floori(lo.y / CELL), floori(hi.y / CELL) + 1):
					var key := Vector2i(cx, cz)
					if not _cells.has(key):
						_cells[key] = []
					_cells[key].append(Vector2i(ri, si))
	for mi in mansions.size():
		var pos: Vector2 = mansions[mi].pos
		var reach := PAD_RADIUS + PAD_SHOULDER
		for cx in range(floori((pos.x - reach) / CELL), floori((pos.x + reach) / CELL) + 1):
			for cz in range(floori((pos.y - reach) / CELL), floori((pos.y + reach) / CELL) + 1):
				var key := Vector2i(cx, cz)
				if not _pad_cells.has(key):
					_pad_cells[key] = []
				_pad_cells[key].append(mi)


## Terrain height at `pos` after carving roads and pads into the raw height `raw`.
func carve(pos: Vector2, raw: float) -> float:
	var key := Vector2i(floori(pos.x / CELL), floori(pos.y / CELL))
	var best_d := INF
	var best_h := raw
	var best_flat := 0.0
	var best_shoulder := SHOULDER
	if _cells.has(key):
		for ref in _cells[key]:
			var road: Dictionary = roads[ref.x]
			var pts: PackedVector2Array = road.points
			var a := pts[ref.y]
			var b := pts[ref.y + 1]
			var ab := b - a
			var t := clampf((pos - a).dot(ab) / maxf(ab.length_squared(), 0.001), 0.0, 1.0)
			var d := pos.distance_to(a + ab * t)
			var half: float = road.width * 0.5
			if d - half < best_d - best_flat:
				best_d = d
				best_flat = half
				best_h = lerpf(road.heights[ref.y], road.heights[ref.y + 1], t)
				best_shoulder = SHOULDER
	if _pad_cells.has(key):
		for mi in _pad_cells[key]:
			var d: float = pos.distance_to(mansions[mi].pos)
			if d - PAD_RADIUS < best_d - best_flat:
				best_d = d
				best_flat = PAD_RADIUS
				best_h = mansions[mi].height
				best_shoulder = PAD_SHOULDER
	if best_d == INF:
		return raw
	var blend := smoothstep(best_flat, best_flat + best_shoulder, best_d)
	return lerpf(best_h, raw, blend)


## Road segments touching a world rect (grown by the road width): [{"a", "b", "ha", "hb", "width"}].
func segments_in(rect: Rect2) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var seen := {}
	var grown := rect.grow(CELL)
	for cx in range(floori(grown.position.x / CELL), floori(grown.end.x / CELL) + 1):
		for cz in range(floori(grown.position.y / CELL), floori(grown.end.y / CELL) + 1):
			var key := Vector2i(cx, cz)
			if not _cells.has(key):
				continue
			for ref in _cells[key]:
				if seen.has(ref):
					continue
				seen[ref] = true
				var road: Dictionary = roads[ref.x]
				var a: Vector2 = road.points[ref.y]
				var b: Vector2 = road.points[ref.y + 1]
				var seg_rect := Rect2(Vector2(minf(a.x, b.x), minf(a.y, b.y)), (b - a).abs()).grow(road.width)
				if seg_rect.intersects(rect):
					out.append({"a": a, "b": b, "ha": road.heights[ref.y], "hb": road.heights[ref.y + 1], "width": road.width})
	return out


func mansions_in(rect: Rect2) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for m in mansions:
		if rect.has_point(m.pos):
			out.append(m)
	return out
