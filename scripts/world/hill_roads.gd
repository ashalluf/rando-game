class_name HillRoads
extends RefCounted
## Seeded roads through the hills: a winding boulevard along the hill foot, canyon roads
## climbing north, mansion loops branching off them, and a rim drive around the peninsula.
## Each road has a smoothed height profile (grade-limited) and the terrain is carved flat to it,
## with cut/fill shoulders, so cars can actually drive up. Mansion pads are flat spots the same
## way. All coordinates are true world XZ.

## Max road grade (rise per meter of run).
const MAX_GRADE := 0.11
## A branch leaves the road it joins on a steeper ramp, for its first JUNCTION_RUN metres, so it
## can meet that road's height and still reach its own: held to MAX_GRADE from the junction, a
## canyon road leaving the boulevard at the foot of the range fell behind the rising ground at
## once, and not pinned at all it started 11 m above the boulevard (a step in the ground).
const JUNCTION_GRADE := 0.2
const JUNCTION_RUN := 150.0
## The coast highway: the one road that runs the whole length of the shore, from the cliffs in
## the north, down across the flat beach towns, and up onto the headland in the south. It is the
## most recognisable road on a coast like this, so it is laid out along the shoreline itself
## rather than by the random walk the canyon roads use - holding a fixed distance in from the
## water is what makes it read as a coast road from the air.
const COAST_WIDTH := 17.0
## How far inland of the waterline it sits. MacroMap.beach_width is the sand, so this keeps the
## whole carriageway on the land side of it without letting it wander into the city grid, whose
## streets it would otherwise cross at a random angle every block.
const COAST_INSET := 46.0
## Sampling step along the shore. Short enough that the bends read as curves rather than as a
## chain of straights, which on the northern cliffs is the entire character of the road.
const COAST_STEP := 26.0
## Where the coast highway leaves the shore (z): short of the Redondo pier, whose own car park
## and the Esplanade replica take the coast from there.
const PCH_END_Z := 1380.0
## Shoulder width on each side of a road where terrain blends back to its natural height. A
## shallow cut or fill (under about ten metres) is this soft roll; a deeper one is a bank.
const SHOULDER := 14.0
const PAD_RADIUS := 17.0
const PAD_SHOULDER := 12.0
## The deepest a mansion pad may be cut or filled at its centre.
const PAD_EARTHWORK := 24.0
const CELL := 120.0
## Cut and fill banks: the steepest the carved ground may rise from a road's edge (or a pad's
## rim) back to the natural slope, in metres of height per metre out. 1:1 for a cut, 1:1.5 for a
## fill, the slopes real hill roads are graded to. With only SHOULDER to blend over, a road 60 m
## below the hillside got a 60 m wall 14 m wide - sheer cliffs with the road at their feet.
const CUT_BANK := 1.0
const FILL_BANK := 0.67
## How far out from a road's edge the banks may run. A road is only kept where the ground meets
## its banks well inside this (`_earthwork_ok()`); the last BANK_FADE hands a bank that still
## has not met the ground back to it, so the edge of the reach is never a step.
const BANK_REACH := 46.0
const BANK_FADE := 8.0
## Where the earthwork check looks, metres out from a road's edge on both sides: the banks must
## have met the ground by here, so a cut face is at most 36 m tall and a fill 24 m.
const DAYLIGHT_AT := 36.0
## The deepest a road bed may lie below the ground (or stand above it) on its centre line.
const MAX_EARTHWORK := 30.0
## Slack on the check, metres.
const EARTHWORK_SLACK := 3.0
## How far the boulevard may be slid downhill, off ground it cannot be graded into.
const FOOT_SLIDE_MAX := 240.0
const FOOT_SLIDE_STEP := 12.0

## Roads: {"name", "points": PackedVector2Array, "heights": PackedFloat32Array, "width": float,
## "mansions": bool, "planned_points": the whole walk, of which `points` is the part kept}
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
		pts.append(Vector2(x, _boulevard_z(x)))
		x += 30.0
	_add_road("Sunset Drive", _slide_off_the_range(pts, 16.0), 16.0, false)
	# 2. Canyon roads climbing north from the boulevard, with mansion loops off each one. A
	#    canyon walks straight up a range far steeper than a road can climb, so each one (and each
	#    loop off it) is kept only as far as it can be graded (`_add_road()`): past that it would sit
	#    at the bottom of a trench hundreds of metres deep. The walks, the branch points and the
	#    mansion rolls are all made as before, so the rng stream - and every estate on the
	#    headland after it - is unchanged.
	for start_x: float in [-520.0, -140.0, 260.0, 680.0]:
		var canyon := _walk(Vector2(start_x, _boulevard_z_on_road(start_x)), -PI * 0.5, 26, rng, 0.35)
		var ci := _add_road("Canyon %d" % roads.size(), canyon, 12.0, false, _height_on(0, canyon[0]), true)
		for frac: float in [0.4, 0.72]:
			var i := int(canyon.size() * frac)
			# Branch east or west, tilted a little uphill or down.
			var tilt := rng.randf_range(-PI * 0.25, PI * 0.25)
			var heading := (0.0 if rng.randf() < 0.5 else PI) + tilt
			var loop := _walk(canyon[i], heading, 9, rng, 0.5)
			# A loop starts at the canyon road's own height where it branches (it used to take
			# the hillside's, and stood up to 200 m above the road it leaves), and does not exist
			# if the canyon road never gets that far.
			var li := _add_road("Estates %d" % roads.size(), loop, 10.0, true, _kept_height(ci, i), true)
			_place_mansions(li, rng)
		if ci >= 0 and rng.randf() < 0.5:
			_place_mansions(ci, rng)
	# 3. The replica's hill route (Palos Verdes Blvd and Drive West), carved at its own authored
	#    profile. The replica draws its own road; this road is here for the carving, the scatter's
	#    keep-out and the estates along it. Then the ring road round the headland, which picks it
	#    up where the replica stops, and the estate lanes climbing off both.
	_add_replica_route(macro, rng)
	var rim := PackedVector2Array()
	var ax: Array = macro._headland_axes()
	for i in 49:
		var a := TAU * i / 48
		var k := RIM_RADIUS + 0.035 * sin(a * 3.0 + 0.7)
		rim.append(macro.peninsula_center + (ax[0] as Vector2) * (cos(a) * macro.peninsula_axes.x * k)
			+ (ax[1] as Vector2) * (sin(a) * macro.peninsula_axes.y * k))
	var ri := _add_road("Palos Verdes Dr", rim, 12.0, true)
	_place_mansions(ri, rng)
	# Estate lanes up the north face, the reason the slopes seen from the Esplanade are covered in
	# houses. Each climbs off the ring road toward the crest line.
	for k in ESTATE_LANES:
		var t := float(k) / float(ESTATE_LANES)
		var at: Vector2 = rim[int(t * 48.0) % 48]
		var up: Vector2 = (macro.peninsula_center - at).normalized()
		var lane := _walk(at, atan2(up.y, up.x) + rng.randf_range(-0.5, 0.5), 7, rng, 0.45)
		var li := _add_road("Estates %d" % roads.size(), lane, 9.0, true, _kept_height(ri, int(t * 48.0) % 48), true)
		_place_mansions(li, rng)
	# 4. The coast highway, last so that its height profile is smoothed against a shoreline the
	#    other roads have already settled against.
	_add_coast_highway(macro)
	_index()


## How far out the headland's ring road runs, as a share of the ellipse (1 is the shore), and how
## many estate lanes climb off it.
const RIM_RADIUS := 0.62
const ESTATE_LANES := 12


## The replica's route where it leaves the town for the hills: carved into the terrain at the
## profile ReplicaAreas authored and fitted, flat across its width, with estates along it.
func _add_replica_route(macro: MacroMap, rng: RandomNumberGenerator) -> void:
	var rep: ReplicaAreas = macro.replica
	if rep == null:
		return
	var i0 := rep._index_of_s(maxf(rep.s_city_end - 120.0, 0.0))
	var pts := PackedVector2Array()
	var hs := PackedFloat32Array()
	var step := 3
	var i := i0
	while i < rep.pts.size():
		pts.append(rep.pts[i])
		hs.append(rep.top[i] - ReplicaAreas.ROAD_TOP)
		i += step
	if pts.size() < 2:
		return
	var sd: Dictionary = rep.sec[rep.pts.size() - 1]
	var width: float = (float(sd.kerb_e) - float(sd.kerb_w)) + 2.0
	roads.append({"name": "Palos Verdes Dr W", "points": pts, "heights": hs, "width": width, "mansions": true, "draw": false,
		"planned_points": pts})
	_place_mansions(roads.size() - 1, rng)


## The coast highway, from the cliffs in the north to the headland in the south, holding
## COAST_INSET in from the waterline the whole way. Its shape is the shoreline's: MacroMap
## bends the coast with a long sine and bulges it around the headland, and the road inherits
## both, which is why it comes out curving rather than straight.
func _add_coast_highway(macro: MacroMap) -> void:
	var pts := PackedVector2Array()
	# Start up in the northern cliffs, where the shelf carries it, and run down the coast to the
	# Redondo pier. The real road turns inland there, and south of it the coast is the Esplanade
	# replica's (ReplicaAreas), which lays its own road along the bluff.
	var z := macro.shelf_full_z - 420.0
	var end_z := PCH_END_Z
	while z < end_z:
		pts.append(Vector2(macro.coast_x(z) + COAST_INSET, z))
		z += COAST_STEP
	_add_road("Pacific Coast Highway", pts, COAST_WIDTH, false)


func _boulevard_z(x: float) -> float:
	return _macro.hills_start_z - 60.0 + 90.0 * sin(x / 260.0) + 35.0 * sin(x / 97.0 + 1.3)


## Where the boulevard as built crosses `x` (it has been slid off the range in places).
func _boulevard_z_on_road(x: float) -> float:
	var pts: PackedVector2Array = roads[0].points
	for i in pts.size() - 1:
		if x >= pts[i].x and x <= pts[i + 1].x:
			return lerpf(pts[i].y, pts[i + 1].y, (x - pts[i].x) / maxf(pts[i + 1].x - pts[i].x, 0.001))
	return _boulevard_z(x)


## The boulevard's line, slid downhill (south) wherever the range rises too steeply beside it to
## be graded into: its sine swings it up to 180 m into the front range, and where it did the
## road was cut 40 m into a spur and then, held to its grade on the way down, carried on a 60 m
## embankment across the flat for half a kilometre. A point that fails `_earthwork_ok()` on its
## uphill side moves FOOT_SLIDE_STEP south and the profile is taken again, until it passes.
func _slide_off_the_range(pts: PackedVector2Array, width: float) -> PackedVector2Array:
	var out := pts.duplicate()
	var slid := PackedFloat32Array()
	slid.resize(out.size())
	for pass_i in int(FOOT_SLIDE_MAX / FOOT_SLIDE_STEP):
		var heights := _limit_grade(_smooth(_surface_profile(out)), out)
		var moved := false
		var push := PackedFloat32Array()
		push.resize(out.size())
		for i in out.size():
			if slid[i] < FOOT_SLIDE_MAX and _earthwork_ok(out, heights, i, width * 0.5, true) < 0:
				push[i] = FOOT_SLIDE_STEP
				moved = true
		if not moved:
			break
		# Take the neighbours along a little, so the line bends rather than kinks.
		for i in out.size():
			var p := push[i]
			if i > 0:
				p = maxf(p, push[i - 1] * 0.5)
			if i < out.size() - 1:
				p = maxf(p, push[i + 1] * 0.5)
			p = minf(p, FOOT_SLIDE_MAX - slid[i])
			out[i].y += p
			slid[i] += p
	return out


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


## Adds a road, profiled from the ground under it (smoothed, grade-limited). `start_height`
## pins its first point to the road it branches off (NAN: free). With `trim` it is kept only from
## its start to the last point its banks can meet the ground from (`_earthwork_ok()`), and
## profiled again over just that part, since a mountain the road never reaches should not lift
## the start of it: before, the grade limiter carried the range's height back down every canyon
## road and started it 30 m in the air. A trimmed road can be empty (fewer than two points:
## nothing carved or drawn), and a branch whose start is NAN (its junction was trimmed away) is.
## The entry always stays, so road indices and names do not move, and `planned_points` keeps the
## whole walk, which the mansion rolls follow so they draw the rng the same way however much of
## the road is kept.
func _add_road(road_name: String, pts: PackedVector2Array, width: float, mansions_allowed: bool, start_height: float = NAN, trim: bool = false) -> int:
	if pts.size() < 2:
		return -1
	var keep := pts.size()
	var heights := _profile(pts, start_height)
	if trim:
		if is_nan(start_height):
			keep = 0
		while keep >= 2:
			var fail := -1
			var kept_pts := pts.slice(0, keep)
			for i in keep:
				if _earthwork_ok(kept_pts, heights, i, width * 0.5, false) != 0:
					fail = i
					break
			if fail < 0:
				break
			keep = fail
			if keep >= 2:
				heights = _profile(pts.slice(0, keep), start_height)
		if keep < 2:
			keep = 0
	roads.append({"name": road_name, "points": pts.slice(0, keep), "heights": heights.slice(0, keep), "width": width,
		"mansions": mansions_allowed, "planned_points": pts})
	return roads.size() - 1


## A smoothed, grade-limited profile of the ground under `pts`, pinned at its start to
## `start_height` unless that is NAN (and ramped from there, see JUNCTION_GRADE). The relief
## runs up the lower slopes now, so a profile taken from the bare mountain would sit below its
## own hillside: it is taken from the surface.
func _profile(pts: PackedVector2Array, start_height: float) -> PackedFloat32Array:
	var heights := _limit_grade(_smooth(_surface_profile(pts)), pts)
	if not is_nan(start_height):
		heights[0] = start_height
		var run := 0.0
		for i in range(1, heights.size()):
			var step := pts[i].distance_to(pts[i - 1])
			run += step
			var g := (JUNCTION_GRADE if run <= JUNCTION_RUN else MAX_GRADE) * step
			heights[i] = clampf(heights[i], heights[i - 1] - g, heights[i - 1] + g)
	return heights


func _surface_profile(pts: PackedVector2Array) -> PackedFloat32Array:
	var raw := PackedFloat32Array()
	for p in pts:
		raw.append(_macro.raw_height_at(p) + _macro.relief_at(p))
	return raw


## A kept road's bed height at its point `i`, or NAN if that point was trimmed away.
func _kept_height(road_index: int, i: int) -> float:
	if road_index < 0:
		return NAN
	var hs: PackedFloat32Array = roads[road_index].heights
	return hs[i] if i < hs.size() else NAN


## A road's bed height where it passes closest to `pos`.
func _height_on(road_index: int, pos: Vector2) -> float:
	var pts: PackedVector2Array = roads[road_index].points
	var hs: PackedFloat32Array = roads[road_index].heights
	var best := INF
	var h := NAN
	for i in pts.size() - 1:
		var ab := pts[i + 1] - pts[i]
		var t := clampf((pos - pts[i]).dot(ab) / maxf(ab.length_squared(), 0.001), 0.0, 1.0)
		var d := pos.distance_to(pts[i] + ab * t)
		if d < best:
			best = d
			h = lerpf(hs[i], hs[i + 1], t)
	return h


## Whether the ground round point `i` of a road can be graded to it: the bed within
## MAX_EARTHWORK of the ground on the centre line, and CUT_BANK / FILL_BANK banks from its edges
## that have met the natural slope by DAYLIGHT_AT (also checked half way to the next point).
## 0 if so, -1 if a cut is too deep, +1 if a fill is. `uphill_only` looks only at cuts - the
## boulevard's slide fixes those.
func _earthwork_ok(pts: PackedVector2Array, hs: PackedFloat32Array, i: int, half: float, uphill_only: bool) -> int:
	var j := mini(i + 1, pts.size() - 1)
	var k := maxi(i - 1, 0)
	var dir := (pts[j] - pts[k]).normalized()
	var nor := Vector2(-dir.y, dir.x)
	var spots: Array[Vector2] = [pts[i]]
	var beds: Array[float] = [hs[i]]
	if j != i:
		spots.append(pts[i].lerp(pts[j], 0.5))
		beds.append(lerpf(hs[i], hs[j], 0.5))
	# Probe directions: the centre line, both sides, and - at an end, where the ground round the
	# end of the road is graded to it all the way round - straight on past the end.
	var outs: Array[Vector2] = [Vector2.ZERO, nor, -nor]
	if i == pts.size() - 1:
		outs.append(dir)
	if i == 0:
		outs.append(-dir)
	for n in spots.size():
		for out: Vector2 in outs:
			var e := 0.0 if out == Vector2.ZERO else DAYLIGHT_AT
			var q: Vector2 = spots[n] + out * (half + e)
			var dh := _macro.raw_height_at(q) + _macro.relief_at(q) - beds[n]
			var cut_limit := MAX_EARTHWORK if e == 0.0 else CUT_BANK * e + EARTHWORK_SLACK
			var fill_limit := MAX_EARTHWORK if e == 0.0 else FILL_BANK * e + EARTHWORK_SLACK
			if dh > cut_limit:
				return -1
			if not uphill_only and -dh > fill_limit:
				return 1
	return 0


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


## Whether a mansion pad at `pos`, levelled at `h`, can be graded into the ground: its centre
## within a storey or so, and banks from its rim that meet the ground inside the probes.
func _pad_ok(pos: Vector2, h: float) -> bool:
	if absf(_macro.raw_height_at(pos) + _macro.relief_at(pos) - h) > PAD_EARTHWORK:
		return false
	for a in 6:
		var e := BANK_REACH - BANK_FADE
		var q := pos + Vector2.from_angle(TAU * a / 6.0) * (PAD_RADIUS + e)
		var dh := _macro.raw_height_at(q) + _macro.relief_at(q) - h
		if dh > CUT_BANK * e + EARTHWORK_SLACK or -dh > FILL_BANK * e + EARTHWORK_SLACK:
			return false
	return true


func _place_mansions(road_index: int, rng: RandomNumberGenerator) -> void:
	if road_index < 0:
		return
	var road: Dictionary = roads[road_index]
	var pts: PackedVector2Array = road.planned_points
	var heights: PackedFloat32Array = road.heights
	var kept := heights.size()
	var width: float = road.width
	var along := 20.0
	var i := 0
	while i < pts.size() - 1:
		var seg := pts[i + 1] - pts[i]
		var seg_len := seg.length()
		if along < seg_len:
			var t := along / seg_len
			var p := pts[i].lerp(pts[i + 1], t)
			var h := lerpf(heights[i], heights[i + 1], t) if i + 1 < kept else 0.0
			var normal := Vector2(-seg.y, seg.x).normalized()
			for side: float in [-1.0, 1.0]:
				if rng.randf() < 0.75:
					var pos := p + normal * side * (width * 0.5 + PAD_RADIUS + 4.0)
					if _macro.raw_height_at(pos) > 3.0 and _macro.zone_at(pos) == MacroMap.Zone.HILLS:
						# The seed is drawn whether or not the lot is kept, so the rolls after it
						# do not move: a lot on a stretch of road that was trimmed, or on ground
						# its pad cannot be graded into, is simply not built.
						var lot_seed := rng.randi()
						if i + 1 < kept and _pad_ok(pos, h):
							mansions.append({"pos": pos, "height": h, "yaw": atan2(-normal.x * side, -normal.y * side), "seed": lot_seed, "road": road_index})
			along += rng.randf_range(44.0, 60.0)
		else:
			along -= seg_len
			i += 1


func _index() -> void:
	_cells.clear()
	_pad_cells.clear()
	for ri in roads.size():
		var pts: PackedVector2Array = roads[ri].points
		var reach: float = roads[ri].width * 0.5 + BANK_REACH
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
		var reach := PAD_RADIUS + BANK_REACH
		for cx in range(floori((pos.x - reach) / CELL), floori((pos.x + reach) / CELL) + 1):
			for cz in range(floori((pos.y - reach) / CELL), floori((pos.y + reach) / CELL) + 1):
				var key := Vector2i(cx, cz)
				if not _pad_cells.has(key):
					_pad_cells[key] = []
				_pad_cells[key].append(mi)


## Terrain height at `pos` after carving roads and pads into the raw height `raw`.
##
## The nearest road or pad sets the bed; the ground rolls off it over SHOULDER where the cut or
## fill is shallow and climbs a CUT_BANK / FILL_BANK bank where it is deep, until it meets the
## natural slope. Every other bed within reach clamps the ground to its own banks first, so where
## two roads pass close their banks meet instead of one road's shoulder standing over the other.
func carve(pos: Vector2, raw: float) -> float:
	var key := Vector2i(floori(pos.x / CELL), floori(pos.y / CELL))
	var has_roads := _cells.has(key)
	var has_pads := _pad_cells.has(key)
	if not has_roads and not has_pads:
		return raw
	# Beds in reach: distance out from the flat (<= 0 on it), bed height, shoulder.
	var outs := PackedFloat32Array()
	var beds := PackedFloat32Array()
	var shoulders := PackedFloat32Array()
	var best := -1
	if has_roads:
		for ref in _cells[key]:
			var road: Dictionary = roads[ref.x]
			var pts: PackedVector2Array = road.points
			if ref.y + 1 >= pts.size():
				continue
			var a := pts[ref.y]
			var b := pts[ref.y + 1]
			var ab := b - a
			var t := clampf((pos - a).dot(ab) / maxf(ab.length_squared(), 0.001), 0.0, 1.0)
			var e: float = pos.distance_to(a + ab * t) - road.width * 0.5
			if e >= BANK_REACH:
				continue
			if best < 0 or e < outs[best]:
				best = outs.size()
			outs.append(e)
			beds.append(lerpf(road.heights[ref.y], road.heights[ref.y + 1], t))
			shoulders.append(SHOULDER)
	if has_pads:
		for mi in _pad_cells[key]:
			var e: float = pos.distance_to(mansions[mi].pos) - PAD_RADIUS
			if e >= BANK_REACH:
				continue
			if best < 0 or e < outs[best]:
				best = outs.size()
			outs.append(e)
			beds.append(mansions[mi].height)
			shoulders.append(PAD_SHOULDER)
	if best < 0:
		return raw
	var h := raw
	for i in outs.size():
		if i != best:
			h = _bank(h, beds[i], outs[i], 0.0)
	return _bank(h, beds[best], outs[best], shoulders[best])


## Ground at height `h`, `e` metres out from a bed at `bed`, pulled onto the bed's banks. With a
## `shoulder` the shallow part rolls off smoothly as it always did (which is the gentler of the
## two for anything under about ten metres); without one it is a plain clamp to the banks.
static func _bank(h: float, bed: float, e: float, shoulder: float) -> float:
	if e <= 0.0:
		return bed
	var dh := h - bed
	var reach := (CUT_BANK if dh > 0.0 else FILL_BANK) * e
	var off := minf(absf(dh), reach)
	if shoulder > 0.0:
		off = minf(off, absf(dh) * smoothstep(0.0, shoulder, e))
	# Hand back to the ground at the end of the reach, where no bank may stand.
	off = lerpf(off, absf(dh), smoothstep(BANK_REACH - BANK_FADE, BANK_REACH, e))
	return bed + signf(dh) * off


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
					out.append({"a": a, "b": b, "ha": road.heights[ref.y], "hb": road.heights[ref.y + 1], "width": road.width,
						"draw": road.get("draw", true)})
	return out


func mansions_in(rect: Rect2) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for m in mansions:
		if rect.has_point(m.pos):
			out.append(m)
	return out
