class_name LightRail
extends RefCounted
## THE CORAL LINE - the city's light rail (owner's brief, 2026-10-04: "a light rail line, like LA
## Metro's, with its own original name, colour and livery").
##
## One line, authored as a DATA TABLE (ROUTE, PORTAL, STATIONS, the speeds and the timetable
## below), never as placed nodes - the replica areas' rule. Where downtown is 1:1 (DowntownReal)
## it follows the real Flower St corridor: underground from 7th St (an underground terminus with
## street entrances), a portal ramp in the median south of 11th St, at grade down the middle of
## Flower past Pico and Venice, onto an aerial structure that climbs over the Santa Monica
## Freeway (the 10), curves west at the seeded boulevard that plays Exposition (the first wide
## street south of `ROUTE.turn.south_of`), crosses over the Harbor and Century freeways on the
## structure, comes down to grade and runs down the boulevard's median to the beach town. Past
## downtown everything is seeded: which street, its height, the crossing roads, the station names.
##
## Everything else asks this object: the chunks build the track, stations, catenary, viaduct and
## portal from `pieces_in()` (LightRailKit), the far city draws `far_mesh()`, the trains are placed
## from `trains_at(clock)` (LightRailSystem: nothing per train is ticked that can be worked out
## from the clock), TrafficManager keeps its cars to the outer lane of a rail street
## (`street_rail()`) and stops them at a closed crossing (`crossing_closed()`), the lots keep out
## of the structure (`blocks_rect()`), and the road slab and the horizon plane leave the portal's
## trench open (`cuts_in()`, `cut_rects()`).
##
## Names: the line, the agency and the livery are invented; station names are public street
## names (CLAUDE.md allows them), the seeded ones from CityPlan.road_name().

const LINE_NAME := "Coral Line"
const AGENCY := "Basin Metro"
const LINE_LETTER := "C"
## The line's colour (sRGB): signs, the trains' band, the station pylons.
const LINE_COLOR := Color(0.93, 0.40, 0.30)

enum Mode { TUNNEL, TRENCH, GRADE, AERIAL }

## The alignment. `avenue`: the pinned downtown avenue the line runs down (grid south, +Z);
## `north_end`: the end of the tail track beyond the underground terminus, a street and metres
## along the avenue from it; `turn`: the seeded boulevard it turns west onto - the first AXIS_Z road
## south of `south_of` at least `min_width` wide - and the curve's radius; `west_end`: the x of the
## tail track's end on that boulevard.
const ROUTE := {
	"avenue": "FLOWER ST",
	"north_end": ["7TH ST", -95.0],
	"turn": {"south_of": 2700.0, "min_width": 22.0, "radius": 28.0},
	"west_end": -282.0,
}
## The portal: the rail reaches the street `daylight` (a street, metres along the avenue from it),
## climbing out of the tunnel (rail `depth` under the street) at `grade`. The trench is the part
## of that climb whose roof would be above the street (rail less than MOUTH_DEPTH down).
const PORTAL := {"daylight": ["PICO BLVD", -170.0], "depth": 13.0, "grade": 0.045}
const MOUTH_DEPTH := 7.6
## Stations, in route order: `at` is a street and metres along the avenue from it (downtown),
## `x` a position on the seeded boulevard; `name` is fixed, else it is "<the street> / <the
## crossing road nearest>". `terminus`: a turn-back. Platform kind follows from where it stands
## (underground: island under the street, entrances on the pavements; at grade: an island in the
## median, slid to the middle of the nearest block long enough to hold it and its ramps clear of
## the crosswalks; aerial: an island on the structure, which is held level over it).
const STATIONS := [
	{"name": "7TH ST / FLOWER", "at": ["7TH ST", 48.0], "terminus": true},
	{"name": "PICO / FLOWER", "at": ["PICO BLVD", -70.0]},
	{"at": ["VENICE BLVD", 235.0]},
	{"x": 1985.0},
	{"x": 1010.0},
	{"x": 240.0},
	{"x": -318.0, "terminus": true},
]

## Track: centre spacing on plain line and how the tracks spread round an island platform
## (`PLATFORM_WIDTH` wide, its edge `PLATFORM_GAP` off the car side), over `SPREAD_RUN` metres.
const TRACK_HALF := 2.1
const PLATFORM_WIDTH := 3.0
const AERIAL_PLATFORM_WIDTH := 5.0
const PLATFORM_LENGTH := 64.0
const PLATFORM_HEIGHT := 0.92
const PLATFORM_GAP := 0.06
const CAR_HALF_WIDTH := 1.33
const SPREAD_RUN := 34.0
## The rail top over the street where it is embedded.
const TRACK_LIFT := 0.035
## The aerial structure: what it must clear over a freeway deck (rail above the deck top: the
## trucks' 5.1 m, the barrier, the structure's own depth) and its grade.
const AERIAL_CLEAR := 7.6
const MAX_GRADE := 0.058
## Overhead line: contact wire over the rail, the messenger above it, poles this far apart.
const CONTACT_HEIGHT := 5.65
const SYSTEM_HEIGHT := 1.05
const POLE_SPACING := 54.0
## Speed limits (m/s) and the timetable: accelerate, brake, dwell, turn round at a terminus,
## the headway the fleet is sized to.
const SPEED_TUNNEL := 17.0
const SPEED_TRENCH := 11.0
const SPEED_STREET_DOWNTOWN := 11.5
const SPEED_STREET := 15.5
const SPEED_AERIAL := 20.0
const CURVE_ACCEL := 0.9
const ACCEL := 1.0
const BRAKE := 1.15
const DWELL := 24.0
const TURNAROUND := 70.0
const TARGET_HEADWAY := 300.0
## Gates and signal pre-emption: closed this long before a train reaches a crossing and until
## this long after its rear has cleared it.
const GATE_LEAD := 20.0
const GATE_TRAIL := 2.5
## The consist: two double-ended articulated cars coupled (LightRailTrain): each car two
## sections on three bogies.
const CAR_LENGTH := 27.0
const COUPLER := 0.6
const CARS := 2
const TRAIN_LENGTH := CAR_LENGTH * CARS + COUPLER * (CARS - 1)

## Sample spacing along the route (m), and the cell size of the piece index.
const STEP := 2.0
const SEG := 4.0
const CELL := 160.0

## The resolved line (world XZ, true world).
var plan: CityPlan
var pts := PackedVector2Array()
var dirs := PackedVector2Array()
var run := PackedFloat32Array()
## Rail top (absolute y), the street under it, the half track spacing, the mode, per sample.
var rail := PackedFloat32Array()
var street := PackedFloat32Array()
var half := PackedFloat32Array()
var mode := PackedByteArray()
var length := 0.0
## Stations: {"name", "s" (centre), "pos", "mode", "terminus", "width" (platform), "y" (rail)}.
var stations: Array[Dictionary] = []
## At-grade crossings: {"node": Vector2i, "s", "pos": Vector2, "axis" (of the road crossed),
## "gates": bool, "width" (of the road crossed), "along" (axis of the line there)}.
var crossings: Array[Dictionary] = []
## Freeway crossings the structure goes over: {"s", "pos", "deck"}.
var flyovers: Array[Dictionary] = []
## The avenue and the boulevard: [axis, index] each, and the boulevard's z.
var avenue_x := 0.0
var avenue_index := 0
var boulevard_z := 0.0
var boulevard_index := 0
## The portal: s where the trench starts (the mouth) and where the rail reaches the street.
var mouth_s := 0.0
var daylight_s := 0.0
## Timetable: per direction (0 = outbound, s increasing; 1 = inbound) the trip as times and
## front positions, its length, and the phases; the fleet and the headway.
var trip_t: Array[PackedFloat32Array] = [PackedFloat32Array(), PackedFloat32Array()]
var trip_s: Array[PackedFloat32Array] = [PackedFloat32Array(), PackedFloat32Array()]
var trip_dwell: Array[PackedByteArray] = [PackedByteArray(), PackedByteArray()]
var trip_len := [0.0, 0.0]
var phase := [0.0, 0.0]
var fleet := 1
var headway := TARGET_HEADWAY
var _cells: Dictionary = {}

## The shared clock (seconds of service), advanced by LightRailSystem once a physics tick.
static var clock: float = 3600.0
## Crossings closed this tick (node -> true), worked out by LightRailSystem from the clock.
static var closed: Dictionary = {}
static var _cache: Dictionary = {}
## Off: no line anywhere (the A/B; RAIL=0 in the environment).
static var enabled: bool = OS.get_environment("RAIL") != "0"


## The line for this plan, resolved once (null with no macro map or the line off).
static func of(p: CityPlan) -> LightRail:
	if p == null or p.macro == null or not enabled:
		return null
	var key := p.get_instance_id()
	if not _cache.has(key):
		var lr := LightRail.new()
		lr._resolve(p)
		_cache[key] = lr
	return _cache[key]


# --- Resolution ------------------------------------------------------------------------------

func _resolve(p: CityPlan) -> void:
	plan = p
	var av := DowntownReal.named(CityPlan.AXIS_X, ROUTE.avenue)
	avenue_x = float(av[0])
	avenue_index = plan.block_index_at(Vector2(avenue_x + 0.01, 0.0)).x
	var z0 := _street_z(ROUTE.north_end)
	# The boulevard: the first wide AXIS_Z road south of `south_of`.
	var iz := plan.block_index_at(Vector2(avenue_x, float(ROUTE.turn.south_of))).y + 1
	while plan.road_width(CityPlan.AXIS_Z, iz) < float(ROUTE.turn.min_width):
		iz += 1
	boulevard_index = iz
	boulevard_z = plan.road_pos(CityPlan.AXIS_Z, iz)
	var r := float(ROUTE.turn.radius)
	var x_end := float(ROUTE.west_end)
	# The centre line, sampled every STEP: south down the avenue, the curve, west.
	var poly := PackedVector2Array()
	var z := z0
	while z < boulevard_z - r:
		poly.append(Vector2(avenue_x, z))
		z += STEP
	var arc_len := r * PI * 0.5
	var n_arc := ceili(arc_len / STEP)
	var centre := Vector2(avenue_x - r, boulevard_z - r)
	for k in n_arc + 1:
		var a := PI * 0.5 * float(k) / n_arc
		poly.append(centre + Vector2(cos(a), sin(a)) * r)
	var x := avenue_x - r - STEP
	while x > x_end:
		poly.append(Vector2(x, boulevard_z))
		x -= STEP
	poly.append(Vector2(x_end, boulevard_z))
	pts = poly
	var n := pts.size()
	run.resize(n)
	dirs.resize(n)
	var acc := 0.0
	for i in n:
		if i > 0:
			acc += pts[i].distance_to(pts[i - 1])
		run[i] = acc
		var d := (pts[mini(i + 1, n - 1)] - pts[maxi(i - 1, 0)]).normalized()
		dirs[i] = d
	length = acc
	_profile()
	_place_stations()
	_find_crossings()
	_index()
	_timetable()


## World z of a [street, metres along the avenue] pair.
func _street_z(spec: Array) -> float:
	return float(DowntownReal.named(CityPlan.AXIS_Z, str(spec[0]))[0]) + float(spec[1])


## s of a world z on the avenue leg.
func _s_of_z(z: float) -> float:
	return z - pts[0].y


func _street_at(p: Vector2) -> float:
	return plan.macro.relief_at(p) + CityChunk.ROAD_TOP + TRACK_LIFT


## The vertical profile: the tunnel and the portal ramp by the table, the street everywhere else,
## and the aerial structure where the line crosses a freeway deck - the upper envelope of
## MAX_GRADE cones from every point the structure must clear, so it is grade-limited by
## construction, then eased.
func _profile() -> void:
	var n := pts.size()
	street.resize(n)
	rail.resize(n)
	mode.resize(n)
	half.resize(n)
	for i in n:
		street[i] = _street_at(pts[i])
		half[i] = TRACK_HALF
	daylight_s = _s_of_z(_street_z(PORTAL.daylight))
	var depth := float(PORTAL.depth)
	var g := float(PORTAL.grade)
	var ramp0 := daylight_s - depth / g
	mouth_s = daylight_s - MOUTH_DEPTH / g
	# Freeway decks the line passes under at grade: what the structure must clear.
	var req_s := PackedFloat32Array()
	var req_h := PackedFloat32Array()
	var fw: Freeway = plan.macro.freeway
	if fw != null:
		for i in n - 1:
			if run[i] < daylight_s:
				continue
			var a := pts[i]
			var b := pts[i + 1]
			for seg in fw.segments_in(Rect2(a, Vector2.ZERO).expand(b).grow(1.0)):
				var t := Freeway._segments_cross(a, b, seg.a, seg.b)
				if t < 0.0:
					continue
				var hit := a.lerp(b, t)
				var sa: Vector2 = seg.a
				var sb: Vector2 = seg.b
				var u := clampf((hit - sa).dot(sb - sa) / maxf((sb - sa).length_squared(), 0.001), 0.0, 1.0)
				var deck := lerpf(float(seg.ha), float(seg.hb), u)
				var s_hit := lerpf(run[i], run[i + 1], t)
				# The whole deck width has to be cleared, however obliquely it is crossed.
				var sin_a := absf((b - a).normalized().cross((sb - sa).normalized()))
				var reach := float(seg.width) * 0.5 / maxf(sin_a, 0.3) + 4.0
				for off: float in [-reach, 0.0, reach]:
					req_s.append(s_hit + off)
					req_h.append(deck + AERIAL_CLEAR)
				flyovers.append({"s": s_hit, "pos": hit, "deck": deck})
	var cone := PackedFloat32Array()
	cone.resize(n)
	for i in n:
		var c := -INF
		for k in req_s.size():
			c = maxf(c, req_h[k] - MAX_GRADE * absf(run[i] - req_s[k]))
		cone[i] = c
	# An aerial station is level: the most the cones ask for over its platform, held flat across it.
	for st: Dictionary in STATIONS:
		var s_c := _spec_s(st)
		var i0 := _index_at_s(s_c - PLATFORM_LENGTH * 0.5 - 6.0)
		var i1 := _index_at_s(s_c + PLATFORM_LENGTH * 0.5 + 6.0)
		var top := -INF
		for i in range(i0, i1 + 1):
			top = maxf(top, cone[i])
		if top > street[_index_at_s(s_c)] + 4.0:
			for i in n:
				var dd := maxf(absf(run[i] - s_c) - PLATFORM_LENGTH * 0.5 - 6.0, 0.0)
				cone[i] = maxf(cone[i], top - MAX_GRADE * dd)
	for i in n:
		var s := run[i]
		if s < ramp0:
			rail[i] = street[i] - depth
			mode[i] = Mode.TUNNEL
		elif s < daylight_s:
			rail[i] = street[i] - (daylight_s - s) * g
			mode[i] = Mode.TUNNEL if s < mouth_s else Mode.TRENCH
		else:
			rail[i] = street[i]
			mode[i] = Mode.GRADE
			if cone[i] > street[i]:
				rail[i] = cone[i]
	# Ease the structure's grade breaks (a vertical curve over ~40 m) without letting it dip under
	# the street or under what it must clear.
	var eased := rail.duplicate()
	for pass_i in 3:
		for i in range(1, n - 1):
			if run[i] > daylight_s + 4.0:
				eased[i] = (rail[i - 1] + rail[i] * 2.0 + rail[i + 1]) * 0.25
		for i in n:
			if run[i] > daylight_s + 4.0:
				rail[i] = maxf(eased[i], maxf(street[i], cone[i] - 0.4))
	for i in n:
		if mode[i] == Mode.GRADE and rail[i] > street[i] + 0.3:
			mode[i] = Mode.AERIAL


func _s_of_x(x: float) -> float:
	# The boulevard leg runs west from the end of the curve.
	var r := float(ROUTE.turn.radius)
	var s_curve_end := (boulevard_z - r) - pts[0].y + r * PI * 0.5
	return s_curve_end + (avenue_x - r - x)


func _index_at_s(s: float) -> int:
	return clampi(roundi(s / STEP), 0, pts.size() - 1) if pts.size() > 0 else 0


## Samples whose run is nearest `s` (binary search: the curve's samples are not exactly STEP apart).
func index_at(s: float) -> int:
	var lo := 0
	var hi := run.size() - 1
	while hi - lo > 1:
		var mid := (lo + hi) >> 1
		if run[mid] <= s:
			lo = mid
		else:
			hi = mid
	return lo


## The s a STATIONS entry asks for (before an at-grade one is slid into its block).
func _spec_s(spec: Dictionary) -> float:
	return _s_of_z(_street_z(spec.at)) if spec.has("at") else _s_of_x(float(spec.x))


## An at-grade platform has to stand between two crossings, with room for its ramps, and out of
## the portal's spread: `s` clamped into the nearest block (on the line's own street) that holds it.
func _fit_in_block(s: float) -> float:
	var axis := CityPlan.AXIS_Z if s < _s_of_x(avenue_x - float(ROUTE.turn.radius)) else CityPlan.AXIS_X
	var p: Vector2 = sample(s).pos
	var k := plan.block_index_at(p)[axis]
	var best := s
	var best_d := INF
	var need := PLATFORM_LENGTH * 0.5 + RAMP_RUN + 1.0
	for dk in range(-4, 5):
		var i := k + dk
		var a := plan.road_pos(axis, i) + plan.road_width(axis, i) * 0.5 + 4.0
		var b := plan.road_pos(axis, i + 1) - plan.road_width(axis, i + 1) * 0.5 - 4.0
		var sa := _s_of_z(a) if axis == CityPlan.AXIS_Z else _s_of_x(a)
		var sb := _s_of_z(b) if axis == CityPlan.AXIS_Z else _s_of_x(b)
		var lo := minf(sa, sb) + need
		var hi := maxf(sa, sb) - need
		lo = maxf(lo, daylight_s + SPREAD_RUN + PLATFORM_LENGTH * 0.5)
		if hi < lo:
			continue
		var cs := clampf(s, lo, hi)
		if absf(cs - s) < best_d:
			best_d = absf(cs - s)
			best = cs
	return best

## The ramp down from an at-grade platform to the crosswalk (1:12 for its height).
const RAMP_RUN := 11.0


func _place_stations() -> void:
	for spec: Dictionary in STATIONS:
		var s := _spec_s(spec)
		if mode[index_at(s)] == Mode.GRADE:
			s = _fit_in_block(s)
		var pos: Vector2 = sample(s).pos
		var nm := ""
		if spec.has("name"):
			nm = str(spec.name)
		elif absf(pos.x - avenue_x) < 0.5:
			var k := plan.block_index_at(pos)
			var iz := k.y if absf(plan.road_pos(CityPlan.AXIS_Z, k.y) - pos.y) < absf(plan.road_pos(CityPlan.AXIS_Z, k.y + 1) - pos.y) else k.y + 1
			nm = "%s / %s" % [_short(plan.road_name(CityPlan.AXIS_Z, iz)), _short(plan.road_name(CityPlan.AXIS_X, avenue_index))]
		else:
			var k := plan.block_index_at(pos)
			var ix := k.x if absf(plan.road_pos(CityPlan.AXIS_X, k.x) - pos.x) < absf(plan.road_pos(CityPlan.AXIS_X, k.x + 1) - pos.x) else k.x + 1
			nm = "%s / %s" % [_short(plan.road_name(CityPlan.AXIS_Z, boulevard_index)), _short(plan.road_name(CityPlan.AXIS_X, ix))]
		var smp := sample(s)
		var m: int = smp.mode
		stations.append({
			"name": nm, "s": s, "pos": smp.pos, "mode": m, "terminus": spec.get("terminus", false),
			"width": AERIAL_PLATFORM_WIDTH if m == Mode.AERIAL else PLATFORM_WIDTH, "y": smp.y,
		})
	# Spread the tracks round each island platform.
	for st in stations:
		var w: float = st.width
		var want := w * 0.5 + PLATFORM_GAP + CAR_HALF_WIDTH
		for i in pts.size():
			var d := absf(run[i] - float(st.s)) - PLATFORM_LENGTH * 0.5 - 3.0
			if d < SPREAD_RUN:
				var t := clampf(1.0 - d / SPREAD_RUN, 0.0, 1.0)
				t = t * t * (3.0 - 2.0 * t)
				half[i] = maxf(half[i], lerpf(TRACK_HALF, want, t))


## "RIVER BLVD" -> "RIVER": station names keep the street, not its suffix.
static func _short(road: String) -> String:
	for suf: String in [" BLVD", " AVE", " ST"]:
		if road.ends_with(suf):
			return road.substr(0, road.length() - suf.length())
	return road


## The road crossings the line makes at grade: every junction on the avenue between daylight and
## the structure, and on the boulevard past it. Gates outside downtown; signal pre-emption inside.
func _find_crossings() -> void:
	for i in pts.size() - 1:
		if mode[i] != Mode.GRADE or mode[i + 1] != Mode.GRADE:
			continue
		var a := pts[i]
		var b := pts[i + 1]
		if absf(a.x - b.x) < 0.01:
			# On the avenue: crossing AXIS_Z roads.
			var k0 := plan.block_index_at(a).y
			var k1 := plan.block_index_at(b).y
			if k1 != k0:
				var road_z := plan.road_pos(CityPlan.AXIS_Z, k1)
				_add_crossing(Vector2i(avenue_index, k1), Vector2(avenue_x, road_z), CityPlan.AXIS_Z, plan.road_width(CityPlan.AXIS_Z, k1))
		elif absf(a.y - b.y) < 0.01:
			var k0 := plan.block_index_at(a).x
			var k1 := plan.block_index_at(b).x
			if k1 != k0:
				var road_x := plan.road_pos(CityPlan.AXIS_X, k0)
				_add_crossing(Vector2i(k0, boulevard_index), Vector2(road_x, boulevard_z), CityPlan.AXIS_X, plan.road_width(CityPlan.AXIS_X, k0))


func _add_crossing(node: Vector2i, pos: Vector2, axis: int, width: float) -> void:
	for c in crossings:
		if c.node == node:
			return
	var s := nearest_s(pos)
	if mode[index_at(s)] != Mode.GRADE:
		return
	if plan.zone_at(pos) != MacroMap.Zone.CITY:
		return
	crossings.append({"node": node, "s": s, "pos": pos, "axis": axis, "width": width,
		"gates": not DowntownReal.in_extent(pos), "along": CityPlan.AXIS_X if axis == CityPlan.AXIS_Z else CityPlan.AXIS_Z})


## s of the nearest centre-line sample to a world XZ.
func nearest_s(pos: Vector2) -> float:
	var best := INF
	var bs := 0.0
	for c: Vector2i in [Vector2i(floori(pos.x / CELL), floori(pos.y / CELL))]:
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				for i: int in _cells.get(c + Vector2i(dx, dz), []):
					var d := pts[i].distance_squared_to(pos)
					if d < best:
						best = d
						bs = run[i]
	if best == INF:
		for i in pts.size():
			var d := pts[i].distance_squared_to(pos)
			if d < best:
				best = d
				bs = run[i]
	return bs


func _index() -> void:
	_cells.clear()
	for i in pts.size():
		var c := Vector2i(floori(pts[i].x / CELL), floori(pts[i].y / CELL))
		if not _cells.has(c):
			_cells[c] = []
		(_cells[c] as Array).append(i)


# --- Queries ---------------------------------------------------------------------------------

## The line at `s`: {"pos": Vector2, "y": rail top, "street", "dir": Vector2, "half", "mode"}.
func sample(s: float) -> Dictionary:
	s = clampf(s, 0.0, length)
	var i := index_at(s)
	var j := mini(i + 1, pts.size() - 1)
	var span := maxf(run[j] - run[i], 0.0001)
	var t := clampf((s - run[i]) / span, 0.0, 1.0)
	return {
		"pos": pts[i].lerp(pts[j], t),
		"y": lerpf(rail[i], rail[j], t),
		"street": lerpf(street[i], street[j], t),
		"dir": dirs[i].lerp(dirs[j], t).normalized(),
		"half": lerpf(half[i], half[j], t),
		"mode": mode[i] if t < 0.5 else mode[j],
	}


## A point on track `side` (-1 left of the direction of increasing s, +1 right) at `s`, world.
func track_point(s: float, side: int) -> Vector3:
	var smp := sample(s)
	var d: Vector2 = smp.dir
	var right := Vector2(-d.y, d.x)
	var p: Vector2 = (smp.pos as Vector2) + right * float(side) * float(smp.half)
	return Vector3(p.x, float(smp.y), p.y)


## Sample indices whose segment to the next sample has its midpoint inside `rect` (each segment
## is built by exactly one chunk).
func indices_in(rect: Rect2) -> PackedInt32Array:
	var out := PackedInt32Array()
	var g := rect.grow(STEP * 2.0)
	for cx in range(floori(g.position.x / CELL), floori(g.end.x / CELL) + 1):
		for cz in range(floori(g.position.y / CELL), floori(g.end.y / CELL) + 1):
			for i: int in _cells.get(Vector2i(cx, cz), []):
				if i + 1 >= pts.size():
					continue
				if rect.has_point((pts[i] + pts[i + 1]) * 0.5):
					out.append(i)
	out.sort()
	return out


## True when the road (axis, index) carries the line at grade or on the structure anywhere, so
## its traffic keeps to the outer lane (TrafficManager._lane_offset()).
func street_rail(axis: int, index: int) -> bool:
	if axis == CityPlan.AXIS_X:
		return index == avenue_index
	return index == boulevard_index


## The trench's holes in the road slab (world rects), for CityChunk._build_roads().
func cut_rects() -> Array[Rect2]:
	var out: Array[Rect2] = []
	var a := sample(mouth_s)
	var b := sample(daylight_s)
	var hw := TRACK_HALF + TRENCH_HALF_EXTRA
	var p0: Vector2 = a.pos
	var p1: Vector2 = b.pos
	out.append(Rect2(Vector2(minf(p0.x, p1.x) - hw, minf(p0.y, p1.y)), Vector2(absf(p1.x - p0.x) + hw * 2.0, absf(p1.y - p0.y))))
	return out

## How far the trench's inside faces stand out past the track centre lines.
const TRENCH_HALF_EXTRA := 2.15


func cuts_in(rect: Rect2) -> Array[Rect2]:
	var out: Array[Rect2] = []
	for r in cut_rects():
		if r.intersects(rect):
			out.append(r)
	return out


## True when a world rect comes within `margin` of the structure (or the trench), so a lot there
## stays empty (CityChunk._lot_under_freeway()). At grade the line is inside its road.
func blocks_rect(rect: Rect2, margin: float) -> bool:
	var g := rect.grow(margin + 6.0)
	for cx in range(floori(g.position.x / CELL), floori(g.end.x / CELL) + 1):
		for cz in range(floori(g.position.y / CELL), floori(g.end.y / CELL) + 1):
			for i: int in _cells.get(Vector2i(cx, cz), []):
				if mode[i] != Mode.AERIAL:
					continue
				if rect.grow(margin + half[i] + 2.4).has_point(pts[i]):
					return true
	return false


# --- Timetable -------------------------------------------------------------------------------

## The speed limit at sample i: by where the track is, and round the curve.
func _limit(i: int) -> float:
	var v := SPEED_STREET
	match mode[i]:
		Mode.TUNNEL:
			v = SPEED_TUNNEL
		Mode.TRENCH:
			v = SPEED_TRENCH
		Mode.AERIAL:
			v = SPEED_AERIAL
		_:
			v = SPEED_STREET_DOWNTOWN if DowntownReal.in_extent(pts[i]) else SPEED_STREET
	# Curvature from the turn of the direction over the neighbouring samples.
	if i > 0 and i < pts.size() - 1:
		var turn := absf(dirs[i - 1].angle_to(dirs[i + 1]))
		var ds := run[i + 1] - run[i - 1]
		if turn > 0.001:
			var radius := ds / turn
			v = minf(v, sqrt(CURVE_ACCEL * radius))
	return v


## Each direction's trip from terminus to terminus as times against front positions, from the
## speed limits (a forward pass that accelerates and a backward one that brakes, the usual
## velocity profile) and a dwell at every station; then the fleet that fills the round trip at
## about TARGET_HEADWAY, and the two directions' phases so that a train that arrives at a terminus
## is the train that leaves it again TURNAROUND later (the cars are double-ended).
func _timetable() -> void:
	var n := pts.size()
	var vlim := PackedFloat32Array()
	vlim.resize(n)
	for i in n:
		vlim[i] = _limit(i)
	for d in 2:
		var sign := 1.0 if d == 0 else -1.0
		# Stops: the front stands half a train past each platform centre in the direction of travel.
		var stops: Array[float] = []
		for st in stations:
			stops.append(float(st.s) + sign * TRAIN_LENGTH * 0.5)
		if d == 1:
			stops.reverse()
		var ts := PackedFloat32Array()
		var ss := PackedFloat32Array()
		var dw := PackedByteArray()
		var t := 0.0
		for k in stops.size() - 1:
			var a := stops[k]
			var b := stops[k + 1]
			# The dwell (the first stop's is the turn-round at the terminus).
			ts.append(t)
			ss.append(a)
			dw.append(1)
			t += TURNAROUND if k == 0 else DWELL
			# The hop, on a 1 m grid.
			var hop := absf(b - a)
			var m := maxi(ceili(hop), 2)
			var v := PackedFloat32Array()
			v.resize(m + 1)
			for j in m + 1:
				var s := a + sign * hop * float(j) / m
				# What the train's whole length is on: the limit is the least over front to rear.
				var lim := INF
				for q in 4:
					var sq := s - sign * TRAIN_LENGTH * float(q) / 3.0
					lim = minf(lim, vlim[_index_at_s(clampf(sq, 0.0, length))])
				v[j] = lim
			v[0] = 0.0
			v[m] = 0.0
			var ds := hop / m
			for j in range(1, m + 1):
				v[j] = minf(v[j], sqrt(v[j - 1] * v[j - 1] + 2.0 * ACCEL * ds))
			for j in range(m - 1, -1, -1):
				v[j] = minf(v[j], sqrt(v[j + 1] * v[j + 1] + 2.0 * BRAKE * ds))
			for j in range(1, m + 1):
				var vm := maxf((v[j - 1] + v[j]) * 0.5, 0.05)
				t += ds / vm
				ts.append(t)
				ss.append(a + sign * hop * float(j) / m)
				dw.append(1 if j == m else 0)
		trip_t[d] = ts
		trip_s[d] = ss
		trip_dwell[d] = dw
		trip_len[d] = t
	var cycle: float = trip_len[0] + trip_len[1]
	fleet = maxi(roundi(cycle / TARGET_HEADWAY), 1)
	headway = cycle / fleet
	phase[0] = 0.0
	phase[1] = fposmod(float(trip_len[0]), headway)


## Where a trip in direction `d` is `tau` seconds after it began: {"s", "v", "dwell", "doors"}.
func trip_state(d: int, tau: float) -> Dictionary:
	var ts: PackedFloat32Array = trip_t[d]
	var ss: PackedFloat32Array = trip_s[d]
	var lo := 0
	var hi := ts.size() - 1
	while hi - lo > 1:
		var mid := (lo + hi) >> 1
		if ts[mid] <= tau:
			lo = mid
		else:
			hi = mid
	var span := maxf(ts[hi] - ts[lo], 0.0001)
	var f := clampf((tau - ts[lo]) / span, 0.0, 1.0)
	var s := lerpf(ss[lo], ss[hi], f)
	var v := absf(ss[hi] - ss[lo]) / span
	var dwell := absf(ss[hi] - ss[lo]) < 0.001 and trip_dwell[d][lo] == 1
	var doors := 0.0
	if dwell:
		var since := tau - ts[lo]
		var left := ts[hi] - tau
		doors = clampf(minf((since - 1.5) / 2.0, (left - 4.0) / 2.5), 0.0, 1.0)
	return {"s": s, "v": v if not dwell else 0.0, "dwell": dwell, "doors": doors}


## Every train in service at clock `t`: {"id" (a stable vehicle number), "dir" (+1 outbound, -1
## inbound), "s" (the front), "v", "dwell", "doors", "tau"}.
func trains_at(t: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for d in 2:
		var tl: float = trip_len[d]
		var ph: float = phase[d]
		var n_hi := floori((t - ph) / headway)
		var n_lo := floori((t - ph - tl) / headway) + 1
		for n in range(n_lo, n_hi + 1):
			var tau := t - ph - float(n) * headway
			if tau < 0.0 or tau >= tl:
				continue
			var st := trip_state(d, tau)
			st.dir = 1 if d == 0 else -1
			st.tau = tau
			# The vehicle: outbound trip n is car set n mod fleet; its inbound trip is the one that
			# starts when it arrives (phase[1] + m * headway = n * headway + trip_len[0]).
			var k := n if d == 0 else n + roundi((float(phase[1]) - float(trip_len[0])) / headway)
			st.id = posmod(k, fleet)
			out.append(st)
	return out


## The time a trip in direction d reaches front position `s` (seconds after it began), or -1.
func trip_time_at(d: int, s: float) -> float:
	var ss: PackedFloat32Array = trip_s[d]
	var ts: PackedFloat32Array = trip_t[d]
	var sign := 1.0 if d == 0 else -1.0
	if (s - ss[0]) * sign < 0.0 or (s - ss[ss.size() - 1]) * sign > 0.0:
		return -1.0
	var lo := 0
	var hi := ss.size() - 1
	while hi - lo > 1:
		var mid := (lo + hi) >> 1
		if (ss[mid] - s) * sign <= 0.0:
			lo = mid
		else:
			hi = mid
	var span := ss[hi] - ss[lo]
	if absf(span) < 0.0001:
		return ts[lo]
	return lerpf(ts[lo], ts[hi], clampf((s - ss[lo]) / span, 0.0, 1.0))


## Whether crossing `c` is closed at clock `t`: some train due within GATE_LEAD, or on it.
func crossing_state(c: Dictionary, t: float) -> bool:
	var s_c: float = c.s
	for d in 2:
		var sign := 1.0 if d == 0 else -1.0
		var t_in := trip_time_at(d, s_c)
		var t_out := trip_time_at(d, s_c + sign * TRAIN_LENGTH)
		if t_in < 0.0:
			continue
		if t_out < 0.0:
			t_out = t_in + 30.0
		var tl: float = trip_len[d]
		var ph: float = phase[d]
		# Trips whose window [t_in - lead, t_out + trail] contains t.
		var n_hi := floori((t - ph - t_in + GATE_LEAD) / headway)
		var n_lo := floori((t - ph - t_out - GATE_TRAIL) / headway)
		for n in range(n_lo, n_hi + 1):
			var tau := t - ph - float(n) * headway
			if tau >= t_in - GATE_LEAD and tau <= t_out + GATE_TRAIL and tau >= 0.0 and tau < tl:
				return true
	return false


## TrafficManager's question: is the line closing the junction `node` to traffic on `axis`?
static func crossing_closed(node: Vector2i, axis: int) -> bool:
	if closed.is_empty():
		return false
	return closed.get(node, -1) == axis
