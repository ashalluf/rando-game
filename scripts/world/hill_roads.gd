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
## How far round a switchback's junction the earthwork check leaves to the parent road.
const JUNCTION_REACH := 48.0
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
	# 5. Switchback drives (roadmap #20): the canyon roads above walk straight up the front range
	#    and are trimmed to stubs, so the range's drives and estates come from roads that follow
	#    the contours instead. Their own rng, after everything else, so nothing above moves.
	_add_switchbacks(seed_value)
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
func _earthwork_ok(pts: PackedVector2Array, hs: PackedFloat32Array, i: int, half: float, uphill_only: bool, junction := Vector2.INF) -> int:
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
			# Round a branch's junction the parent road's own banks are the grading (a probe from
			# a drive just leaving a canyon road runs on across the canyon into its far wall).
			if q.distance_to(junction) < JUNCTION_REACH:
				continue
			var dh := _ground(q) - beds[n]
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
	if absf(_ground(pos) - h) > PAD_EARTHWORK:
		return false
	for a in 6:
		var e := BANK_REACH - BANK_FADE
		var q := pos + Vector2.from_angle(TAU * a / 6.0) * (PAD_RADIUS + e)
		var dh := _ground(q) - h
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


# --- Switchbacks -------------------------------------------------------------------------------
# A switchback drive climbs a slope along its contours at SB_GRADE, the way real hill roads do
# (the canyon roads above walk straight up the fall line, which no road can be graded into on the
# front range): it runs a leg across the slope, turns uphill through a hairpin of HAIRPIN_RADIUS,
# runs back the other way above itself, and so on, for as long as the banks either side of it can
# meet the ground (the same test the trim uses, `_earthwork_ok()`). Its bed is benched into the
# hillside by SB_BENCH of the fall across it, which is what lets a 1:1 cut and a 1:1.5 fill both
# daylight on ground a road laid on the surface could not be graded into. Drives grow off the
# roads already there and off each other, so a slope gets a network, not one road.

## Step along a leg, metres.
const SB_STEP := 15.0
## The grade a leg climbs at; MAX_GRADE is the most any step may take.
const SB_GRADE := 0.085
## The most a leg may turn in one step (radians): a 37 m radius at SB_STEP.
const SB_TURN := 0.4
## The share of the ground's fall across the road the bed is sunk into the slope by.
const SB_BENCH := 0.7
## The hairpin's centre-line radius and how many pieces it is drawn in.
const HAIRPIN_RADIUS := 13.0
const HAIRPIN_PIECES := 6
## A leg's run before it turns, metres (rolled per leg).
const SB_LEG_MIN := 110.0
const SB_LEG_MAX := 300.0
## The most steps a drive takes.
const SB_MAX_STEPS := 90
## Width of a switchback drive.
const SB_WIDTH := 9.0
## Shortest drive worth keeping (metres of road after the trim).
const SB_MIN_KEEP := 150.0
## How close a drive may come to another road's centre line (its parent: SB_CLEAR_PARENT), and
## to its own earlier legs.
const SB_CLEAR_OTHER := 34.0
const SB_CLEAR_PARENT := 24.0
const SB_CLEAR_SELF := 2.0 * HAIRPIN_RADIUS - 3.0
## Where drives may branch off a road, metres apart along it, and how many drives at most.
const SB_START_SPACING := 120.0
const SB_MAX_ROADS := 48
## The least slope (rise per metre) a hairpin is turned on: on flatter ground a drive only bends.
const SB_PIN_MIN_SLOPE := 0.12
## Only the front range and the pass get drives (the headland has its own lanes): north of here.
const SB_NORTH_OF := -700.0

var _sb_points: Dictionary = {}
## Every walk tried, kept or not (SB_DEBUG only), for tools/hill_road_probe.
var debug_walks: Array = []


## The surface a road is graded into: the mountains plus the relief, before any carving. The same
## as raw_height_at() + relief_at(), with the mountains sampled once.
func _ground(p: Vector2) -> float:
	if _gcache_on:
		return _ground_cached(p)
	var raw := _macro.raw_height_at(p)
	return raw + _macro._relief_at(p, raw)


## While the switchbacks are laid out, the ground is read off a GCACHE_STEP lattice of exact
## samples, bilinearly: a walk asks for the same few hectares hundreds of times over, and an exact
## sample costs 20-40 us. Off for everything else, so the other roads are profiled as they were.
const GCACHE_STEP := 12.0
var _gcache_on := false
var _gcache: Dictionary = {}
var _n_cached := 0
var _n_steps := 0


func _ground_node(key: Vector2i) -> Vector2:
	var h: Variant = _gcache.get(key)
	if h == null:
		var p := Vector2(key) * GCACHE_STEP
		var raw := _macro.raw_height_at(p)
		h = Vector2(raw, raw + _macro._relief_at(p, raw))
		_gcache[key] = h
	return h


## (raw, ground) at `p` off the lattice.
func _ground_cached2(p: Vector2) -> Vector2:
	var f := p / GCACHE_STEP
	var k := Vector2i(floori(f.x), floori(f.y))
	var t := f - Vector2(k)
	var a := _ground_node(k).lerp(_ground_node(k + Vector2i(1, 0)), t.x)
	var b := _ground_node(k + Vector2i(0, 1)).lerp(_ground_node(k + Vector2i(1, 1)), t.x)
	return a.lerp(b, t.y)


func _ground_cached(p: Vector2) -> float:
	return _ground_cached2(p).y


## The surface's gradient at `p`, over 6 m.
func _ground_grad(p: Vector2) -> Vector2:
	var d := 6.0
	return Vector2(_ground(p + Vector2(d, 0.0)) - _ground(p - Vector2(d, 0.0)),
		_ground(p + Vector2(0.0, d)) - _ground(p - Vector2(0.0, d))) / (2.0 * d)


## The ground at `q` if it is hill a drive may run on (MacroMap.zone_at()'s HILLS test, with the
## mountains sampled once), else NAN.
func _sb_hill_ground(q: Vector2) -> float:
	if _gcache_on:
		var rg := _ground_cached2(q)
		if rg.x <= 3.0 or q.x < _macro.coast_x(q.y) or _macro.in_bay(q):
			return NAN
		return rg.y
	var raw := _macro.raw_height_at(q)
	if raw <= 3.0 or q.x < _macro.coast_x(q.y) or _macro.in_bay(q):
		return NAN
	return raw + _macro._relief_at(q, raw)


func _sb_index_road(pts: PackedVector2Array, road_index: int) -> void:
	for i in pts.size():
		var n := 1 if i == pts.size() - 1 else maxi(1, int(pts[i].distance_to(pts[i + 1]) / 10.0))
		for k in n:
			var q := pts[i] if k == 0 else pts[i].lerp(pts[i + 1], float(k) / n)
			var key := Vector2i(floori(q.x / 60.0), floori(q.y / 60.0))
			if not _sb_points.has(key):
				_sb_points[key] = []
			_sb_points[key].append(Vector3(q.x, q.y, road_index))


## Whether `q` is within `clear` of a road other than `skip` (or `clear_skip` of `skip`).
var _t_near := 0
func _sb_near_roads(q: Vector2, clear: float, skip: int = -2, clear_skip: float = 0.0) -> bool:
	var t0 := Time.get_ticks_usec()
	var r := _sb_near_roads_(q, clear, skip, clear_skip)
	_t_near += Time.get_ticks_usec() - t0
	return r


func _sb_near_roads_(q: Vector2, clear: float, skip: int = -2, clear_skip: float = 0.0) -> bool:
	var c := Vector2i(floori(q.x / 60.0), floori(q.y / 60.0))
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var key := c + Vector2i(dx, dz)
			if not _sb_points.has(key):
				continue
			for v: Vector3 in _sb_points[key]:
				var d := q.distance_to(Vector2(v.x, v.y))
				if d < (clear_skip if int(v.z) == skip else clear):
					return true
	return false


## The walk's own points so far, by 30 m cell: {cell: [index, ...]}.
var _walk_cells: Dictionary = {}


func _walk_add(pts: PackedVector2Array, i: int) -> void:
	var key := Vector2i(floori(pts[i].x / 30.0), floori(pts[i].y / 30.0))
	if not _walk_cells.has(key):
		_walk_cells[key] = []
	_walk_cells[key].append(i)


func _sb_near_self(q: Vector2, pts: PackedVector2Array, skip_last: int) -> bool:
	var c := Vector2i(floori(q.x / 30.0), floori(q.y / 30.0))
	var last := pts.size() - skip_last
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var key := c + Vector2i(dx, dz)
			if _walk_cells.has(key):
				for i: int in _walk_cells[key]:
					if i < last and q.distance_to(pts[i]) < SB_CLEAR_SELF:
						return true
	return false


## `_earthwork_ok()` for one point of a road being walked: the bed `bed` at `q`, the road running
## along `dir`, the ground there `g`. Cheaper (no half-way spot) and asked before the point is
## taken, so the walk turns away from ground it could not grade instead of being trimmed there.
func _sb_daylight(q: Vector2, dir: Vector2, bed: float, g: float, half: float) -> bool:
	if absf(g - bed) > MAX_EARTHWORK:
		return false
	var nor := dir.orthogonal()
	for side: float in [-1.0, 1.0]:
		var dh := _ground(q + nor * side * (half + DAYLIGHT_AT)) - bed
		if dh > CUT_BANK * DAYLIGHT_AT + EARTHWORK_SLACK or -dh > FILL_BANK * DAYLIGHT_AT + EARTHWORK_SLACK:
			return false
	return true


## One switchback drive from `start` (on road `parent`, whose bed there is `z0`), leaving it
## toward `out`, then running along the slope leg by leg, climbing. Returns {"points",
## "heights", "hairpins"}, the whole walk (the trim comes after).
func _walk_switchback(start: Vector2, z0: float, out: Vector2, parent: int, rng: RandomNumberGenerator, straight_on: bool = false) -> Dictionary:
	var half := SB_WIDTH * 0.5
	var pts := PackedVector2Array([start])
	var hs := PackedFloat32Array([z0])
	_walk_cells.clear()
	_walk_add(pts, 0)
	var hairpins := 0
	var p := start
	var z := z0
	# Which way along the slope: across the fall line, on the side `out` leans to (a coin if it
	# leans neither way). The drive leaves its parent at 40 degrees to that, climbing - or, going
	# on from the end of a road (`straight_on`), straight on.
	var grad := _ground_grad(start + out * 25.0)
	var along := grad.orthogonal().normalized()
	if along == Vector2.ZERO or grad.length() < SB_PIN_MIN_SLOPE:
		along = out if straight_on else out.orthogonal()
	if along.dot(out) < -0.2 or (absf(along.dot(out)) <= 0.2 and rng.randf() < 0.5):
		along = -along
	var lead := out if straight_on else (along * 0.77 + out * 0.64).normalized()
	for k in 2:
		var q := p + lead * SB_STEP
		var g := _sb_hill_ground(q)
		if is_nan(g) or _sb_near_roads(q, SB_CLEAR_OTHER, parent, 0.0 if k == 0 else SB_CLEAR_PARENT * 0.5):
			return {"points": pts, "heights": hs, "hairpins": 0}
		var gmax := JUNCTION_GRADE * SB_STEP
		z = clampf(g, z - gmax, z + gmax)
		p = q
		pts.append(p)
		hs.append(z)
		_walk_add(pts, pts.size() - 1)
	var heading := along.angle()
	var leg := 0.0
	var leg_target := rng.randf_range(SB_LEG_MIN, SB_LEG_MAX)
	var steps := 0
	var gmax := MAX_GRADE * SB_STEP
	while steps < SB_MAX_STEPS:
		steps += 1
		_n_steps += 1
		var want := z + SB_GRADE * SB_STEP
		var fall_grad := _ground_grad(p)
		# Candidates: [score, point, bed, heading].
		var cands: Array = []
		for k in range(-6, 7):
			var th := heading + k * SB_TURN * 0.25
			var dir := Vector2.from_angle(th)
			var q := p + dir * SB_STEP
			if _sb_near_self(q, pts, 4) or _sb_near_roads(q, SB_CLEAR_OTHER, parent, SB_CLEAR_PARENT if pts.size() > 3 else 0.0):
				continue
			var g := _sb_hill_ground(q)
			if is_nan(g):
				continue
			var fall := absf(fall_grad.dot(dir.orthogonal()))
			var bed := clampf(g - SB_BENCH * fall * half, z - gmax, z + gmax)
			cands.append([absf(g - SB_BENCH * fall * half - want) + 0.4 * absf(k), q, bed, th, g])
		cands.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
		var took: Array = []
		for c: Array in cands:
			if _sb_daylight(c[1], Vector2.from_angle(c[3]), c[2], c[4], half):
				took = c
				break
		# On a slope a leg turns back above itself when it has run its length (or can go no
		# further); on flat ground there is nothing to climb, so it only turns when it must.
		var sloped := fall_grad.length() >= SB_PIN_MIN_SLOPE
		if took.is_empty() or (leg >= leg_target and sloped):
			var pin := _hairpin(pts, p, heading, z, parent) if sloped else {}
			if not pin.is_empty():
				for i in (pin.points as PackedVector2Array).size():
					pts.append(pin.points[i])
					hs.append(pin.heights[i])
					_walk_add(pts, pts.size() - 1)
				p = pts[pts.size() - 1]
				z = hs[hs.size() - 1]
				heading = pin.heading
				hairpins += 1
				leg = 0.0
				leg_target = rng.randf_range(SB_LEG_MIN, SB_LEG_MAX)
				continue
			if took.is_empty():
				break
			# No room to turn here: run on a little and try again.
			leg_target = leg + SB_STEP * 2.0
		p = took[1]
		z = took[2]
		heading = took[3]
		pts.append(p)
		hs.append(z)
		_walk_add(pts, pts.size() - 1)
		leg += SB_STEP
	return {"points": pts, "heights": hs, "hairpins": hairpins}


## A hairpin off the end `p` of a leg running along `heading` at bed `z`: a half circle turning
## uphill, its bed rising round it at SB_GRADE. Empty if the ground round it cannot be graded to
## it or it runs into a road.
func _hairpin(pts: PackedVector2Array, p: Vector2, heading: float, z: float, parent: int) -> Dictionary:
	var dir := Vector2.from_angle(heading)
	var grad := _ground_grad(p)
	var left := dir.orthogonal()
	var side := 1.0 if left.dot(grad) > 0.0 else -1.0
	var centre := p + left * side * HAIRPIN_RADIUS
	if _sb_near_roads(centre, SB_CLEAR_OTHER - 6.0, parent, SB_CLEAR_PARENT if pts.size() > 3 else 0.0):
		return {}
	var out_pts := PackedVector2Array()
	var out_hs := PackedFloat32Array()
	var a0 := (p - centre).angle()
	var piece := PI * HAIRPIN_RADIUS / HAIRPIN_PIECES
	var zz := z
	for k in range(1, HAIRPIN_PIECES + 1):
		var a := a0 + side * PI * k / HAIRPIN_PIECES
		var q := centre + Vector2.from_angle(a) * HAIRPIN_RADIUS
		var g := _sb_hill_ground(q)
		if is_nan(g):
			return {}
		zz += SB_GRADE * piece
		var tangent := Vector2.from_angle(a + side * PI * 0.5)
		if not _sb_daylight(q, tangent, zz, g, SB_WIDTH * 0.5):
			return {}
		out_pts.append(q)
		out_hs.append(zz)
	return {"points": out_pts, "heights": out_hs, "heading": heading + PI}


## Adds a road whose bed is already laid (`hs`), smoothed and grade-limited, kept from its start
## only as far as `_earthwork_ok()` passes everywhere on it. Returns its index, or -1 if less
## than `min_keep` metres of it could be kept (nothing is added then).
func _add_laid_road(road_name: String, pts: PackedVector2Array, hs: PackedFloat32Array, width: float, min_keep: float) -> int:
	if pts.size() < 3:
		return -1
	var z0 := hs[0]
	var heights := _limit_grade(_smooth(hs), pts)
	# The junction stays on its parent's bed, and the lead-in ramps off it.
	heights[0] = z0
	for i in range(1, heights.size()):
		var g := (JUNCTION_GRADE if i <= 2 else MAX_GRADE) * pts[i].distance_to(pts[i - 1])
		heights[i] = clampf(heights[i], heights[i - 1] - g, heights[i - 1] + g)
	var keep := pts.size()
	# The junction itself is on the parent's bed (graded with the parent).
	for i in range(1, pts.size()):
		var e := _earthwork_ok(pts, heights, i, width * 0.5, false, pts[0])
		if e != 0:
			if OS.get_environment("SB_DEBUG") != "":
				print("  trim at %d of %d: %d (bed %.1f walked %.1f ground %.1f)" % [i, pts.size(), e, heights[i], hs[i], _ground(pts[i])])
			keep = i
			break
	var kept := pts.slice(0, keep)
	var length := 0.0
	for i in kept.size() - 1:
		length += kept[i].distance_to(kept[i + 1])
	if keep < 3 or length < min_keep:
		return -1
	roads.append({"name": road_name, "points": kept, "heights": heights.slice(0, keep), "width": width,
		"mansions": true, "planned_points": kept, "switchback": true})
	_sb_index_road(kept, roads.size() - 1)
	return roads.size() - 1


## Branch points every SB_START_SPACING along road `ri` (from `from` metres in), north of
## SB_NORTH_OF: [road, point, bed, normal].
func _sb_starts(ri: int, from: float) -> Array:
	var out: Array = []
	var road: Dictionary = roads[ri]
	var pts: PackedVector2Array = road.points
	var hs: PackedFloat32Array = road.heights
	var run := 0.0
	var next := from
	for i in pts.size() - 1:
		var seg := pts[i].distance_to(pts[i + 1])
		while next < run + seg:
			var t := (next - run) / seg
			var at := pts[i].lerp(pts[i + 1], t)
			if at.y < SB_NORTH_OF:
				out.append([ri, at, lerpf(hs[i], hs[i + 1], t), (pts[i + 1] - pts[i]).normalized().orthogonal()])
			next += SB_START_SPACING
		run += seg
	return out


func _add_switchbacks(seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 31 + 977
	_sb_points.clear()
	for ri in roads.size():
		_sb_index_road(roads[ri].points, ri)
	_add_north_foot_drive()
	_gcache_on = true
	var queue: Array = []
	for ri in roads.size():
		var road: Dictionary = roads[ri]
		if road.get("draw", true) and road.name != "Pacific Coast Highway":
			queue.append_array(_sb_ends(ri))
			queue.append_array(_sb_starts(ri, 60.0))
	var added := 0
	var debug := OS.get_environment("SB_DEBUG") != ""
	var t_walk := 0
	var t_lay := 0
	while not queue.is_empty() and added < SB_MAX_ROADS:
		var s: Array = queue.pop_front()
		var ri: int = s[0]
		var at: Vector2 = s[1]
		var nor: Vector2 = s[3]
		var straight_on: bool = s.size() == 5 or (s.size() == 6 and s[4])
		var out := nor
		if not straight_on:
			# Leave on the uphill side first; the downhill side is tried after, as its own start.
			var grad := _ground_grad(at + nor * 20.0) + _ground_grad(at - nor * 20.0)
			out = nor if grad.dot(nor) > 0.0 else -nor
			if s.size() == 4:
				queue.append([ri, at, s[2], -out, false, true])
			elif s.size() == 6:
				out = nor
		if is_nan(_sb_hill_ground(at + out * 25.0)) or _sb_near_roads(at + out * 30.0, SB_CLEAR_OTHER, ri, 0.0 if straight_on else SB_CLEAR_PARENT):
			continue
		var t0 := Time.get_ticks_usec()
		var walk := _walk_switchback(at, s[2], out, ri, rng, straight_on)
		var t1 := Time.get_ticks_usec()
		var li := _add_laid_road("Switchback %d" % roads.size(), walk.points, walk.heights, SB_WIDTH, SB_MIN_KEEP)
		t_walk += t1 - t0
		t_lay += Time.get_ticks_usec() - t1
		if debug:
			debug_walks.append(walk.points)
			print("SBTRY road %d at %s: walk %d pts %d pins -> %s" % [ri, at, (walk.points as PackedVector2Array).size(), walk.hairpins,
				"kept %d" % (roads[li].points as PackedVector2Array).size() if li >= 0 else "dropped"])
		if li < 0:
			continue
		var kept: PackedVector2Array = roads[li].points
		var pins := 0
		# Hairpins kept: count the half turns in what was kept.
		for i in range(1, kept.size() - 1):
			if (kept[i] - kept[i - 1]).normalized().dot((kept[i + 1] - kept[i]).normalized()) < 0.9:
				pins += 1
		roads[li].hairpins = int(round(pins / float(HAIRPIN_PIECES - 1)))
		added += 1
		queue.append_array(_sb_ends(li))
		queue.append_array(_sb_starts(li, 90.0))
	_gcache_on = false
	if debug:
		print("SBTIME walk %d ms, lay %d ms, near %d ms, %d ground nodes, %d cached reads, %d steps" % [t_walk / 1000, t_lay / 1000, _t_near / 1000, _gcache.size(), _n_cached, _n_steps])
	_gcache.clear()


## A road's far end, to go on from: [road, end point, bed, heading, true]. Only a road that ends
## on the hills (a dead end up a slope), north of SB_NORTH_OF.
func _sb_ends(ri: int) -> Array:
	var pts: PackedVector2Array = roads[ri].points
	var hs: PackedFloat32Array = roads[ri].heights
	if pts.size() < 2:
		return []
	var n := pts.size()
	var at := pts[n - 1]
	if at.y >= SB_NORTH_OF or is_nan(_sb_hill_ground(at)):
		return []
	return [[ri, at, hs[n - 1], (at - pts[n - 2]).normalized(), true]]


## The valley side's foot drive: along the foot of the front range's inland flank, from the pass
## west, where the range comes down onto the valley floor - the gentle ground the north side's
## estates stand on. Its line is where the mountains rise NORTH_FOOT_RISE out of the valley, so
## it follows the range's own outline; it is kept in the runs its banks can be graded along.
const NORTH_FOOT_RISE := 22.0
const NORTH_FOOT_FROM_X := -950.0
const NORTH_FOOT_TO_X := 760.0


func _add_north_foot_drive() -> void:
	var pts := PackedVector2Array()
	var x := NORTH_FOOT_TO_X
	while x > NORTH_FOOT_FROM_X:
		# Walk south from the valley floor until the mountain has risen far enough.
		var z := _macro.valley_to_z - 300.0
		var found := NAN
		while z < _macro.hills_full_z:
			if _macro.raw_height_at(Vector2(x, z)) > NORTH_FOOT_RISE:
				found = z
				break
			z += 8.0
		if not is_nan(found):
			pts.append(Vector2(x, found))
		x -= 30.0
	if pts.size() < 4:
		return
	# Smooth the line: the outline is ragged where gullies come down.
	for pass_i in 3:
		var src := pts.duplicate()
		for i in range(1, pts.size() - 1):
			pts[i].y = (src[i - 1].y + 2.0 * src[i].y + src[i + 1].y) * 0.25
	var heights := _profile(pts, NAN)
	_add_runs("Valley Vista Dr", pts, heights, 12.0, 300.0)


## Adds the stretches of `pts` whose banks can be graded (`_earthwork_ok()`), each at least
## `min_run` metres, as roads of their own.
func _add_runs(road_name: String, pts: PackedVector2Array, heights: PackedFloat32Array, width: float, min_run: float) -> void:
	var ok := PackedByteArray()
	ok.resize(pts.size())
	for i in pts.size():
		ok[i] = 1 if _earthwork_ok(pts, heights, i, width * 0.5, false) == 0 else 0
	var i := 0
	while i < pts.size():
		if ok[i] == 0:
			i += 1
			continue
		var j := i
		while j + 1 < pts.size() and ok[j + 1] == 1:
			j += 1
		var run := pts.slice(i, j + 1)
		var length := 0.0
		for k in run.size() - 1:
			length += run[k].distance_to(run[k + 1])
		if length >= min_run:
			# The ends of a run are checked again as ends, straight on past them.
			var hs := heights.slice(i, j + 1)
			while run.size() >= 2 and _earthwork_ok(run, hs, run.size() - 1, width * 0.5, false) != 0:
				run = run.slice(0, run.size() - 1)
				hs = hs.slice(0, hs.size() - 1)
			while run.size() >= 2 and _earthwork_ok(run, hs, 0, width * 0.5, false) != 0:
				run = run.slice(1)
				hs = hs.slice(1)
			if run.size() >= 4:
				roads.append({"name": road_name, "points": run, "heights": hs, "width": width, "mansions": true,
					"planned_points": run, "switchback": true})
				_sb_index_road(run, roads.size() - 1)
		i = j + 1
