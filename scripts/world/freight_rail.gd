class_name FreightRail
extends RefCounted
## THE HARBOR SUBDIVISION - the freight main from the port up the Alameda corridor to the yard
## (owner's brief, 2026-10-05: "freight rail - the corridor from the port north through the
## industrial district ... and along the LA River").
##
## One line, authored as a DATA TABLE (ROUTE and the numbers below), never as placed nodes - the
## light rail's rule (LightRail). It runs down the middle of ALAMEDA ST (a pinned real street that
## runs the whole map: the real corridor follows it from the harbor to downtown), north to south:
##
##   yard    the invented railroad's intermodal yard east of Alameda in the industrial district
##           (FreightYard): Alameda itself and the cross streets east of it are closed between
##           the yard's two junctions, the main tracks run up the old roadway to a buffer stop;
##   trench  the corridor's real form: a double track in a concrete trench down the median, ten
##           metres under the street, every cross street carried over it on a deck where it is
##           deep enough, the cross streets on its two ramps cut off at Alameda (a severed
##           junction; real ramps do the same);
##   grade   a stretch at street level down the median where every cross street is a gated level
##           crossing (RailGate, bells, TrafficManager stops at the stop line);
##   tunnel  a ramp down to a portal, and from it a covered way on to the port's on-dock terminal:
##           nothing of it is drawn past the portal, and trains there are drawn by nobody.
##
## The trains are worked out from one clock (`clock`), never ticked: trip n leaves the port at
## n * headway, climbs out of the tunnel with its head-end locomotives leading, runs up the east
## track to the yard, stands for DWELL_YARD (a crew change), then runs back with its distributed
## power unit (the locomotives at the rear) leading: wrong-road on the east track as far as the
## crossover past where its rear stood, over to the west track and down into the tunnel. Every
## train is long enough (60-120 cars, MAX_LEN) that the crossover is a long way from the yard, so
## the headway is worked out from how long a trip holds the east track (`headway`). Nothing a
## train stands on while it waits is a level crossing (the at-grade stretch begins past the
## longest train), so no gate stays down for a crew change.
##
## Names: the railroad, its marks and its livery are invented (ARROYO PACIFIC, reporting mark
## APXR); street names are the plan's.

const RAILROAD := "ARROYO PACIFIC"
const MARK := "APXR"

enum Mode { YARD, TRENCH, GRADE, TUNNEL }
## How a cross street meets the line: inside the yard (closed), carried over the trench on a deck,
## severed at Alameda (a ramp), a gated level crossing, or over the covered way (nothing to do).
enum Junction { YARD, BRIDGE, CLOSED, CROSSING, COVERED }
enum Car { LOCO, WELL, TANK, BOX, HOPPER, AUTORACK }

## The alignment. `avenue`: the pinned street the line runs down (along +Z, grid south);
## `yard`: the z of its north and south junctions (snapped to the nearest AXIS_Z roads: the yard
## is the blocks between them east of the avenue, the avenue's roadway between them, and the buffer
## stop just south of the north one); `grade_run`: the length of the at-grade stretch, which starts
## at the first mid-block past where the longest train standing at the yard ends.
const ROUTE := {
	"avenue": "ALAMEDA ST",
	"yard": [2300.0, 2790.0],
	"grade_run": 640.0,
}
## The yard's east edge: the next pinned avenue east (the yard is the whole block between them).
const YARD_EAST := "VIGNES ST"

## Track: centre spacing (half), the rail top over the street at grade and over a deck's ballast.
const TRACK_HALF := 2.3
const RAIL_ABOVE := 0.2
const GAUGE := 1.435
## Rail top over the trench floor (ballast 0.3, ties 0.18, rail 0.172).
const TRACK_DEPTH := 0.65
## In the yard the track stands on the yard's ground (a pavement's height over the road, as
## Industrial lays its yards): the rail top this far over the street.
const YARD_ABOVE := 0.85
## The trench: inside faces this far out from the centre line, walls this thick; the rail top this
## far under the street where it is deep, under a deck at least CLEAR_UNDER (a double stack is
## 6.15 m over the rail, the deck 0.9 m), grades on the ramps and in the deep part.
const TRENCH_HALF := 4.95
const TRENCH_WALL := 0.45
const TRENCH_DEPTH := 9.4
const CLEAR_UNDER := 7.6
const RAMP_GRADE := 0.03
const DEEP_GRADE := 0.02
## The covered way: rail this far under the street, its lid from where the rail is MOUTH_DEPTH down.
const TUNNEL_DEPTH := 11.5
const MOUTH_DEPTH := 8.6
## Where the cross street is cut off at a severed junction: this far out from the avenue's kerbs.
const SEVER_REACH := 4.0

## Trains. Lengths over the couplers and truck centre half-spacings, metres, per Car.
const CAR_LEN := [22.6, 21.9, 18.0, 19.2, 18.0, 27.6]
const TRUCK_HALF := [7.0, 7.7, 6.1, 6.7, 6.0, 9.8]
## The longest train (cars are dropped off the end to fit), the shortest.
const MAX_LEN := 1850.0
const MIN_CARS := 60
const MAX_CARS := 120
## Speeds (m/s): the yard, the trench, the street, the covered way; the crossover, accel, brake.
const SPEED_YARD := 6.7
const SPEED_TRENCH := 16.7
const SPEED_GRADE := 15.6
const SPEED_TUNNEL := 15.0
const SPEED_CROSSOVER := 15.6
const ACCEL := 0.16
const BRAKE := 0.22
## The crew change at the yard (s), the stop short of the buffer (m), the crossover's length.
const DWELL_YARD := 150.0
const BUFFER := 8.0
const XO_LEN := 120.0
## A trip starts (and ends) this far inside the covered way, past the portal (the whole train).
const HIDE_IN := 40.0
## The fewest seconds between trips (the line's own occupancy sets more when it needs it): at
## 18 minutes a busy crossing is down about a third of the time.
const MIN_HEADWAY := 1080.0
## Gates: down this long before the leading end reaches a crossing, up this long after the rear.
const GATE_LEAD := 22.0
const GATE_TRAIL := 3.0

const STEP := 2.0

var plan: CityPlan
var avenue_x := 0.0
var avenue_index := 0
var avenue_width := 24.0
var east_x := 0.0
var east_index := 0
## s = 0 at the buffer stop, increasing south (z = z0 + s; the line is the avenue's centre line).
var z0 := 0.0
var length := 0.0
var rail := PackedFloat32Array()
var street := PackedFloat32Array()
var mode := PackedByteArray()
## The yard's north and south junction indices (AXIS_Z roads) and its rect (world XZ).
var yard_n := 0
var yard_s := 0
var yard_rect := Rect2()
## s of: the yard's south edge (the north ramp starts), the at-grade stretch's two ends, the
## tunnel's mouth (the lid starts), where a hidden trip starts/ends, the crossover's start.
var s_yard_end := 0.0
var s_grade0 := 0.0
var s_grade1 := 0.0
var s_mouth := 0.0
var s_hide := 0.0
var s_xo := 0.0
## Every AXIS_Z road the line meets: {"k", "z", "w", "s", "kind" (Junction), "node" (Vector2i)}.
var junctions: Array[Dictionary] = []
var _junction_kind: Dictionary = {}
## The level crossings (Junction.CROSSING), LightRail's shape: {"node", "s", "pos", "axis",
## "width", "gates"}.
var crossings: Array[Dictionary] = []
## Timetable: per length class, the two trips as times at every metre of end A's travel.
var _trips: Dictionary = {}
var headway := 900.0

## The shared clock (seconds of service), advanced by FreightRailSystem once a physics tick.
static var clock: float = 5400.0
## Crossings closed this tick (node -> axis of the road stopped), worked out by FreightRailSystem.
static var closed: Dictionary = {}
static var _cache: Dictionary = {}
static var _resolving: bool = false
## Off: no freight line anywhere (the A/B; FREIGHT=0 in the environment).
static var enabled: bool = OS.get_environment("FREIGHT") != "0"


## The line for this plan, resolved once (null with no macro map, the line off, or while it is
## being resolved - CityPlan asks it about roads, and resolving asks CityPlan about roads).
static func of(p: CityPlan) -> FreightRail:
	if p == null or p.macro == null or not enabled or _resolving:
		return null
	var key := p.get_instance_id()
	if not _cache.has(key):
		_resolving = true
		var fr := FreightRail.new()
		var ok := fr._resolve(p)
		_resolving = false
		_cache[key] = fr if ok else null
	return _cache[key]


# --- The corridor's land ---------------------------------------------------------------------

## The land along the corridor and under the yard is held level at TERRACE_LEVEL (relief metres):
## the trench's floor then sits over the city's ground plane (CityStreamer's GroundBody, top y 0,
## under the whole map) everywhere it is open, its depth is the same all the way, and the trains
## climb no 6 % swell of the rolling relief at grade. MacroMap._relief_at() folds it in as it does
## the river's (LaRiver.terrace()), so every chunk's _gy() already follows it. Pure: no plan needed
## (the corridor's x from DowntownReal, its z range from ROUTE, both known before any plan is).
const TERRACE_LEVEL := 10.7
## Full weight within CORE of the avenue's centre line (and over the yard), fading to the natural
## relief over FADE; full along z over TERRACE_Z, fading over FADE at each end.
const TERRACE_CORE := 36.0
const TERRACE_FADE := 170.0
const TERRACE_Z := [2230.0, 5470.0]
static var _tx := NAN
static var _tex := 0.0


## (level, weight) of the corridor's terrace at world XZ `pos`.
static func terrace(pos: Vector2) -> Vector2:
	if not enabled:
		return Vector2.ZERO
	if is_nan(_tx):
		var av := DowntownReal.named(CityPlan.AXIS_X, str(ROUTE.avenue))
		var ea := DowntownReal.named(CityPlan.AXIS_X, YARD_EAST)
		_tx = float(av[0]) if not av.is_empty() else 0.0
		_tex = float(ea[0]) if not ea.is_empty() else _tx + 500.0
	var z0t: float = TERRACE_Z[0]
	var z1t: float = TERRACE_Z[1]
	if pos.y < z0t - TERRACE_FADE or pos.y > z1t + TERRACE_FADE:
		return Vector2.ZERO
	var dx := absf(pos.x - _tx) - TERRACE_CORE
	# Over the yard the core runs east to the yard's east avenue.
	var yz0: float = float(ROUTE.yard[0]) - 30.0
	var yz1: float = float(ROUTE.yard[1]) + 30.0
	if pos.y > yz0 - TERRACE_FADE and pos.y < yz1 + TERRACE_FADE and pos.x > _tx:
		var yard_w := 1.0 - smoothstep(0.0, TERRACE_FADE, maxf(yz0 - pos.y, pos.y - yz1))
		var dy := pos.x - _tex - 12.0
		dx = minf(dx, lerpf(dx, dy, yard_w))
	if dx > TERRACE_FADE:
		return Vector2.ZERO
	var w := 1.0 - smoothstep(0.0, TERRACE_FADE, dx)
	w *= 1.0 - smoothstep(0.0, TERRACE_FADE, maxf(z0t - pos.y, pos.y - z1t))
	return Vector2(TERRACE_LEVEL, w)


# --- Resolution ------------------------------------------------------------------------------

func _resolve(p: CityPlan) -> bool:
	plan = p
	var av := DowntownReal.named(CityPlan.AXIS_X, str(ROUTE.avenue))
	if av.is_empty():
		return false
	avenue_x = float(av[0])
	avenue_index = plan._nearest_road(CityPlan.AXIS_X, avenue_x)
	avenue_width = plan.road_width(CityPlan.AXIS_X, avenue_index)
	var ea := DowntownReal.named(CityPlan.AXIS_X, YARD_EAST)
	east_x = float(ea[0]) if not ea.is_empty() else avenue_x + 500.0
	east_index = plan._nearest_road(CityPlan.AXIS_X, east_x)
	# The yard is the one block between the two avenues (yard_block(), road_open()).
	if east_index != avenue_index + 1:
		return false
	yard_n = plan._nearest_road(CityPlan.AXIS_Z, float(ROUTE.yard[0]))
	yard_s = plan._nearest_road(CityPlan.AXIS_Z, float(ROUTE.yard[1]))
	if yard_s <= yard_n + 1:
		return false
	var zn := plan.road_pos(CityPlan.AXIS_Z, yard_n) + plan.road_width(CityPlan.AXIS_Z, yard_n) * 0.5
	var zs := plan.road_pos(CityPlan.AXIS_Z, yard_s) - plan.road_width(CityPlan.AXIS_Z, yard_s) * 0.5
	z0 = zn + 14.0
	yard_rect = Rect2(avenue_x - avenue_width * 0.5, zn, (east_x - plan.road_width(CityPlan.AXIS_X, east_index) * 0.5) - (avenue_x - avenue_width * 0.5), zs - zn)
	s_yard_end = zs - z0
	# The at-grade stretch: from the first mid-block past the longest train standing at the yard
	# (and the crossover behind it), GRADE_RUN long, both ends mid-block.
	s_grade0 = _mid_block_after(BUFFER + MAX_LEN + XO_LEN + 40.0)
	s_grade1 = _mid_block_after(s_grade0 + float(ROUTE.grade_run))
	s_mouth = s_grade1 + (MOUTH_DEPTH + RAIL_ABOVE) / RAMP_GRADE
	s_hide = s_mouth + HIDE_IN
	s_xo = s_grade0 - XO_LEN - 20.0
	length = s_hide + MAX_LEN + 60.0
	_profile()
	_find_junctions()
	_timetable()
	return true


## s of the middle of the block past `s_min` along the avenue (between the junction before it and
## the one after).
func _mid_block_after(s_min: float) -> float:
	var z := z0 + s_min
	var k := plan._index_at(CityPlan.AXIS_Z, z)
	var a := plan.road_pos(CityPlan.AXIS_Z, k) + plan.road_width(CityPlan.AXIS_Z, k) * 0.5
	var b := plan.road_pos(CityPlan.AXIS_Z, k + 1) - plan.road_width(CityPlan.AXIS_Z, k + 1) * 0.5
	var mid := (a + b) * 0.5
	if mid < z:
		a = plan.road_pos(CityPlan.AXIS_Z, k + 1) + plan.road_width(CityPlan.AXIS_Z, k + 1) * 0.5
		b = plan.road_pos(CityPlan.AXIS_Z, k + 2) - plan.road_width(CityPlan.AXIS_Z, k + 2) * 0.5
		mid = (a + b) * 0.5
	return mid - z0


func _street_at(z: float) -> float:
	return plan.macro.relief_at(Vector2(avenue_x, z)) + CityChunk.ROAD_TOP


## The vertical profile: the street (and RAIL_ABOVE) in the yard and the at-grade stretch; in the
## trench and the covered way the lower envelope of DEEP_GRADE cones under the street less the
## depth (so it never comes nearer the street than that and is grade-limited by construction),
## met by RAMP_GRADE ramps from the stretches at grade, never over the street.
func _profile() -> void:
	var n := int(ceil(length / STEP)) + 1
	rail.resize(n)
	street.resize(n)
	mode.resize(n)
	for i in n:
		street[i] = _street_at(z0 + float(i) * STEP)
	var deep := PackedFloat32Array()
	deep.resize(n)
	for i in n:
		var s := float(i) * STEP
		deep[i] = street[i] - (TUNNEL_DEPTH if s > s_grade1 else TRENCH_DEPTH)
	# Lower envelope of upward cones: a forward and a backward pass.
	var env := deep.duplicate()
	for i in range(1, n):
		env[i] = minf(env[i], env[i - 1] + DEEP_GRADE * STEP)
	for i in range(n - 2, -1, -1):
		env[i] = minf(env[i], env[i + 1] + DEEP_GRADE * STEP)
	var y_a := _street_at(z0 + s_yard_end) + YARD_ABOVE
	var y_b := _street_at(z0 + s_grade0) + RAIL_ABOVE
	var y_c := _street_at(z0 + s_grade1) + RAIL_ABOVE
	for i in n:
		var s := float(i) * STEP
		var top := street[i] + RAIL_ABOVE
		var y := top
		var m := Mode.GRADE
		if s <= s_yard_end:
			m = Mode.YARD
			top = street[i] + YARD_ABOVE
			y = top
		elif s < s_grade0:
			y = maxf(env[i], maxf(y_a - RAMP_GRADE * (s - s_yard_end), y_b - RAMP_GRADE * (s_grade0 - s)))
			m = Mode.TRENCH
			top = street[i] + YARD_ABOVE
		elif s > s_grade1:
			y = maxf(env[i], y_c - RAMP_GRADE * (s - s_grade1))
			m = Mode.TUNNEL if s >= s_mouth else Mode.TRENCH
		rail[i] = minf(y, top)
		mode[i] = m


## Every AXIS_Z road crossing the avenue from the yard's north junction to the far end of the
## covered way, and how it meets the line.
func _find_junctions() -> void:
	var k := yard_n + 1
	while true:
		var z := plan.road_pos(CityPlan.AXIS_Z, k)
		var w := plan.road_width(CityPlan.AXIS_Z, k)
		var s := z - z0
		if s > s_mouth + 400.0:
			break
		var kind := Junction.COVERED
		if k < yard_s:
			kind = Junction.YARD
		elif k == yard_s:
			# The yard's south street: road_open() severs it at the avenue whatever its width.
			kind = Junction.CLOSED
		else:
			# Worst over the junction's width (and a margin either side).
			var lo := INF
			var hi := -INF
			var t := s - w * 0.5 - 1.0
			while t <= s + w * 0.5 + 1.0:
				var drop := street_at(t) + RAIL_ABOVE - rail_at(t)
				lo = minf(lo, drop)
				hi = maxf(hi, drop)
				t += 1.0
			if s > s_mouth + w * 0.5 + 2.0:
				kind = Junction.COVERED
			elif hi < 0.05:
				kind = Junction.CROSSING
			elif lo >= CLEAR_UNDER + RAIL_ABOVE:
				kind = Junction.BRIDGE
			else:
				kind = Junction.CLOSED
		var node := Vector2i(avenue_index, k)
		junctions.append({"k": k, "z": z, "w": w, "s": s, "kind": kind, "node": node})
		_junction_kind[k] = kind
		if kind == Junction.CROSSING:
			crossings.append({"node": node, "s": s, "pos": Vector2(avenue_x, z), "axis": CityPlan.AXIS_Z,
				"width": w, "gates": true, "along": CityPlan.AXIS_X, "k": k})
		k += 1


# --- Queries ---------------------------------------------------------------------------------

func _f(arr: PackedFloat32Array, s: float) -> float:
	var x := clampf(s / STEP, 0.0, float(arr.size() - 1))
	var i := mini(int(x), arr.size() - 2)
	return lerpf(arr[i], arr[i + 1], x - float(i))


func rail_at(s: float) -> float:
	return _f(rail, s)


func street_at(s: float) -> float:
	return _f(street, s)


func mode_at(s: float) -> int:
	return mode[clampi(roundi(s / STEP), 0, mode.size() - 1)]


func s_of_z(z: float) -> float:
	return z - z0


## World XZ of the point `off` metres to the line's right (west: the right of travel south) at s.
func point(s: float, off: float) -> Vector2:
	return Vector2(avenue_x - off, z0 + s)


## A point on the rail centre line of track `off`, at the rail top (true world).
func track_point(s: float, off: float) -> Vector3:
	return Vector3(avenue_x - off, rail_at(s), z0 + s)


## The junction kind of AXIS_Z road k where it meets the avenue (-1: not on the line).
func junction_kind(k: int) -> int:
	return int(_junction_kind.get(k, -1))


## True for chunk (ix, iz) whose block is the yard (CityPlan.lots() is empty there; CityChunk builds
## the yard instead of the seeded block).
func yard_block(ix: int, iz: int) -> bool:
	return ix == avenue_index and iz >= yard_n and iz < yard_s


## CityPlan.road_open()'s question: false on the avenue's roadway through the yard, on the cross
## streets east of the avenue inside the yard, and on the mouth of every cross street the line
## severs (the yard's south junction, the ramps).
func road_open(axis: int, index: int, along: float) -> bool:
	if axis == CityPlan.AXIS_X:
		if index != avenue_index:
			return true
		return not (along > yard_rect.position.y and along < yard_rect.end.y)
	var kind := junction_kind(index)
	if kind < 0:
		return true
	var hw := avenue_width * 0.5
	if kind == Junction.YARD:
		if along > avenue_x - hw - SEVER_REACH and along < east_x - plan.road_width(CityPlan.AXIS_X, east_index) * 0.5:
			return false
		return true
	if kind == Junction.CLOSED or index == yard_s:
		return absf(along - avenue_x) > hw + SEVER_REACH
	return true


## Whether a parking spot (or a stall line) at world XZ `p` is on a road the yard has closed.
static func keeps_clear(p_plan: CityPlan, p: Vector2) -> bool:
	var f := of(p_plan)
	return f != null and f.yard_rect.grow(2.0).has_point(p)


## True when the road (axis, index) carries the line down its median, so its traffic keeps to
## the outer lane (TrafficManager._lane_offset()).
func street_rail(axis: int, index: int) -> bool:
	return axis == CityPlan.AXIS_X and index == avenue_index


## The open trench's holes in the road (world rects), for CityChunk._road_slab(): the line from
## the yard's south edge to the mouth, less every junction square the trench passes under on a deck.
func cut_rects() -> Array[Rect2]:
	var out: Array[Rect2] = []
	var hw := TRENCH_HALF + TRENCH_WALL
	var a := s_yard_end
	var spans: Array = []
	for j in junctions:
		if int(j.kind) == Junction.BRIDGE:
			spans.append([float(j.s) - float(j.w) * 0.5, float(j.s) + float(j.w) * 0.5])
	var cuts: Array = [[s_yard_end, s_grade0], [s_grade1, s_mouth]]
	for c: Array in cuts:
		var lo: float = c[0]
		var hi: float = c[1]
		var pieces: Array = [[lo, hi]]
		for sp: Array in spans:
			var next: Array = []
			for pc: Array in pieces:
				if sp[1] <= pc[0] or sp[0] >= pc[1]:
					next.append(pc)
					continue
				if sp[0] > pc[0]:
					next.append([pc[0], sp[0]])
				if sp[1] < pc[1]:
					next.append([sp[1], pc[1]])
			pieces = next
		for pc: Array in pieces:
			if pc[1] - pc[0] > 0.2:
				out.append(Rect2(avenue_x - hw, z0 + float(pc[0]), hw * 2.0, float(pc[1]) - float(pc[0])))
	return out


## The one rect round the whole open cut (the horizon plane sinks under it).
func cut_bounds() -> Rect2:
	var hw := TRENCH_HALF + TRENCH_WALL
	return Rect2(avenue_x - hw, z0 + s_yard_end, hw * 2.0, s_mouth - s_yard_end)


func cuts_in(rect: Rect2) -> Array[Rect2]:
	var out: Array[Rect2] = []
	if not cut_bounds().intersects(rect):
		return out
	for r in cut_rects():
		if r.intersects(rect):
			out.append(r)
	return out


# --- Consists --------------------------------------------------------------------------------

## Trip n's train: {"kind" (0 stack, 1 manifest, 2 autorack), "cars": [{"type", "len", "c" (centre's
## distance from end A), "flip" (faces +s), "look" (a hash), ...}], "len"}. End A is the north end
## (the head-end locomotives, leading north); end B the distributed power unit.
func consist(n: int) -> Dictionary:
	if _consists.has(n):
		return _consists[n]
	var h := absi(hash([plan.seed, "freight", n]))
	var roll := float(h % 1000) / 1000.0
	var kind := 0 if roll < 0.5 else (1 if roll < 0.85 else 2)
	var cars: Array = []
	var head := 3 if (h >> 10) % 3 != 0 else 4
	var dpu := 1 if (h >> 12) % 4 != 0 else 2
	var want := MIN_CARS + (h >> 14) % (MAX_CARS - MIN_CARS + 1)
	var types: Array = []
	for i in want:
		var hh := absi(hash([plan.seed, "freight_car", n, i]))
		var r := float(hh % 1000) / 1000.0
		var t := Car.WELL
		match kind:
			0:
				t = Car.WELL
			1:
				t = Car.TANK if r < 0.3 else (Car.BOX if r < 0.58 else (Car.HOPPER if r < 0.86 else Car.AUTORACK))
				# Manifest blocks: a car's type usually repeats the one before it.
				if i > 0 and (hh >> 11) % 10 < 6:
					t = types[i - 1]
			2:
				t = Car.AUTORACK if r < 0.82 else Car.BOX
		types.append(t)
	var total := float(head + dpu) * float(CAR_LEN[Car.LOCO])
	var kept: Array = []
	for t in types:
		if total + float(CAR_LEN[t]) > MAX_LEN:
			break
		kept.append(t)
		total += float(CAR_LEN[t])
	var order: Array = []
	for i in head:
		order.append([Car.LOCO, false])
	for t in kept:
		order.append([t, false])
	for i in dpu:
		order.append([Car.LOCO, true])
	var c := 0.0
	for i in order.size():
		var t: int = order[i][0]
		var l: float = CAR_LEN[t]
		var hh := absi(hash([plan.seed, "freight_look", n, i]))
		var flip: bool = order[i][1]
		if t != Car.LOCO:
			flip = (hh >> 3) % 2 == 0
		cars.append({"type": t, "len": l, "c": c + l * 0.5, "flip": flip, "look": hh, "loco_no": 4100 + (hh % 890) if t == Car.LOCO else 0})
		c += l
	var out := {"kind": kind, "cars": cars, "len": c, "n": n}
	_consists[n] = out
	if _consists.size() > 16:
		for old: int in _consists.keys():
			if absi(old - n) > 4:
				_consists.erase(old)
	return out

var _consists: Dictionary = {}


# --- Timetable -------------------------------------------------------------------------------

## The speed limit with the front at s (by where the line is).
func _limit_at(s: float) -> float:
	if s < s_yard_end + 60.0:
		return SPEED_YARD
	var m := mode_at(s)
	match m:
		Mode.TRENCH:
			return SPEED_TRENCH
		Mode.TUNNEL:
			return SPEED_TUNNEL
	return SPEED_GRADE


## Both trips for a train `len` long (rounded up to 50 m), worked out once: a forward accelerate
## and a backward brake pass on a 1 m grid of end A's position, the limit the least over the
## train's whole length; the southbound one also no faster than SPEED_CROSSOVER over the crossover.
## {"nb": times (index i: end A at s_hide - i), "sb": times (index i: end A at BUFFER + i), "T_nb",
## "T_sb", "len"}.
func trips_for(train_len: float) -> Dictionary:
	var cls := int(ceil(train_len / 50.0)) * 50
	if _trips.has(cls):
		return _trips[cls]
	var L := float(cls)
	var a0 := BUFFER
	var a1 := s_hide
	var m := int(ceil(a1 - a0)) + 1
	# The limit at each metre of the line, then the least over [sA, sA + L].
	var span := int(ceil(a1 + L - a0)) + 2
	var lim := PackedFloat32Array()
	lim.resize(span)
	for i in span:
		lim[i] = _limit_at(a0 + float(i))
	var win := _window_min(lim, int(L))
	var out := {"len": L}
	for dir in 2:
		var v := PackedFloat32Array()
		v.resize(m)
		for j in m:
			# j counts metres from the trip's start: nb starts at a1, sb at a0.
			var sA := a1 - float(j) if dir == 0 else a0 + float(j)
			var w := win[clampi(int(sA - a0), 0, win.size() - 1)]
			if dir == 1:
				# Over the crossover (the leading end B and everything behind it).
				var sB := sA + L
				if sB > s_xo - 5.0 and sA < s_xo + XO_LEN + 5.0:
					w = minf(w, SPEED_CROSSOVER)
			v[j] = w
		v[0] = 0.0
		v[m - 1] = 0.0
		for j in range(1, m):
			v[j] = minf(v[j], sqrt(v[j - 1] * v[j - 1] + 2.0 * ACCEL))
		for j in range(m - 2, -1, -1):
			v[j] = minf(v[j], sqrt(v[j + 1] * v[j + 1] + 2.0 * BRAKE))
		var t := PackedFloat32Array()
		t.resize(m)
		t[0] = 0.0
		for j in range(1, m):
			t[j] = t[j - 1] + 1.0 / maxf((v[j - 1] + v[j]) * 0.5, 0.05)
		out["nb" if dir == 0 else "sb"] = t
		out["T_nb" if dir == 0 else "T_sb"] = t[m - 1]
	_trips[cls] = out
	return out


## Sliding minimum of `a` over windows [i, i + w].
static func _window_min(a: PackedFloat32Array, w: int) -> PackedFloat32Array:
	var n := a.size()
	var out := PackedFloat32Array()
	out.resize(n)
	var dq: Array[int] = []
	for i in range(n - 1, -1, -1):
		while not dq.is_empty() and a[dq[dq.size() - 1]] >= a[i]:
			dq.pop_back()
		dq.append(i)
		while dq[0] > i + w:
			dq.pop_front()
		out[i] = a[dq[0]]
	return out


## The headway: how long one trip holds the east track between the crossover and the yard (the
## longest train), plus a margin; then nothing ever meets on it.
func _timetable() -> void:
	var tr := trips_for(MAX_LEN)
	var t_nb_xo := _time_in(tr.nb, s_hide - s_xo)
	var t_sb_xo := _time_in(tr.sb, (s_xo + XO_LEN) - BUFFER)
	var hold := (float(tr.T_nb) - t_nb_xo) + DWELL_YARD + t_sb_xo
	headway = maxf(ceilf((hold + 90.0) / 30.0) * 30.0, MIN_HEADWAY)


func _time_in(times: PackedFloat32Array, j: float) -> float:
	var i := clampi(int(j), 0, times.size() - 2)
	return lerpf(times[i], times[i + 1], clampf(j - float(i), 0.0, 1.0))


## Where trip n is at clock t: {"n", "phase" (0 northbound, 1 at the yard, 2 southbound), "sA" (end
## A's s), "v", "dir" (-1 north, +1 south, 0 standing), "len", "consist"}, or {} before it starts
## and after it ends.
func train_state(n: int, t: float) -> Dictionary:
	var tau := t - float(n) * headway
	if tau < 0.0:
		return {}
	var c := consist(n)
	var tr := trips_for(float(c.len))
	var T_nb: float = tr.T_nb
	var T_sb: float = tr.T_sb
	var out := {"n": n, "len": float(c.len), "consist": c}
	if tau < T_nb:
		var j := _index_of_time(tr.nb, tau)
		out.phase = 0
		out.sA = s_hide - j.x
		out.v = j.y
		out.dir = -1
	elif tau < T_nb + DWELL_YARD:
		out.phase = 1
		out.sA = BUFFER
		out.v = 0.0
		out.dir = 0
	elif tau < T_nb + DWELL_YARD + T_sb:
		var j := _index_of_time(tr.sb, tau - T_nb - DWELL_YARD)
		out.phase = 2
		out.sA = BUFFER + j.x
		out.v = j.y
		out.dir = 1
	else:
		return {}
	return out


## (metres into the trip, speed) at time tau of a trip's time table.
func _index_of_time(times: PackedFloat32Array, tau: float) -> Vector2:
	var lo := 0
	var hi := times.size() - 1
	if tau >= times[hi]:
		return Vector2(float(hi), 0.0)
	while hi - lo > 1:
		var mid := (lo + hi) >> 1
		if times[mid] <= tau:
			lo = mid
		else:
			hi = mid
	var dt := maxf(times[hi] - times[lo], 0.0001)
	return Vector2(float(lo) + (tau - times[lo]) / dt, 1.0 / dt)


## Every trip on the line (visible or in the covered way) at clock t.
func trains_at(t: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var longest := trips_for(MAX_LEN)
	var span := float(longest.T_nb) + DWELL_YARD + float(longest.T_sb)
	var n_hi := floori(t / headway)
	var n_lo := floori((t - span) / headway)
	for n in range(n_lo, n_hi + 1):
		var st := train_state(n, t)
		if not st.is_empty():
			out.append(st)
	return out


## Track offset (to the line's right, west +) under a point `s` of a train in state `st`: the east
## track northbound and standing, the east track southbound until the crossover and the west after.
func offset_at(st: Dictionary, s: float) -> float:
	if int(st.phase) < 2:
		return -TRACK_HALF
	return crossover_offset(s)


static func smooth01(x: float) -> float:
	var t := clampf(x, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


func crossover_offset(s: float) -> float:
	return lerpf(-TRACK_HALF, TRACK_HALF, smooth01((s - s_xo) / XO_LEN))


## Whether every metre of a train in state st is past the portal (drawn by nobody).
func hidden(st: Dictionary) -> bool:
	return float(st.sA) > s_mouth + 6.0


## Time (into trip n) at which end A is at sA on its northbound (dir 0) or southbound (dir 1) trip.
func _trip_time(tr: Dictionary, dir: int, sA: float) -> float:
	if dir == 0:
		return _time_in(tr.nb, s_hide - sA)
	return float(tr.T_nb) + DWELL_YARD + _time_in(tr.sb, sA - BUFFER)


## The windows (clock time) during which crossing c is closed by trip n: [[t0, t1], ...].
func _windows(c: Dictionary, n: int) -> Array:
	var cn := consist(n)
	var L: float = cn.len
	var tr := trips_for(L)
	var base := float(n) * headway
	var s_c: float = c.s
	var out: Array = []
	# Northbound: end A leads (arrives when sA = s_c), end B clears (sA = s_c - L).
	if s_c - L > BUFFER and s_c < s_hide:
		out.append([base + _trip_time(tr, 0, s_c) - GATE_LEAD, base + _trip_time(tr, 0, maxf(s_c - L, BUFFER)) + GATE_TRAIL])
	# Southbound: end B leads (sA + L = s_c), end A clears (sA = s_c).
	if s_c - L > BUFFER and s_c < s_hide:
		out.append([base + _trip_time(tr, 1, s_c - L) - GATE_LEAD, base + _trip_time(tr, 1, s_c) + GATE_TRAIL])
	return out


## How long crossing c has been closed at clock t (> 0), or minus how long it has been open
## (capped at 120): LightRail.crossing_phase()'s contract, so RailGate.pose_at() works it out.
func crossing_phase(c: Dictionary, t: float) -> float:
	var longest := trips_for(MAX_LEN)
	var span := float(longest.T_nb) + DWELL_YARD + float(longest.T_sb) + GATE_LEAD + GATE_TRAIL
	var spans: Array = []
	for n in range(floori((t - span - 130.0) / headway), floori(t / headway) + 1):
		spans.append_array(_windows(c, n))
	spans.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	var open_since := t - 120.0
	for sp: Array in spans:
		if t >= float(sp[0]) and t <= float(sp[1]):
			return maxf(t - float(sp[0]), 0.001)
		if float(sp[1]) < t:
			open_since = maxf(open_since, float(sp[1]))
	return -(t - open_since)


## The trip nearest clock `near` (at least 1), of consist kind `kind` when it is 0..2 (stills:
## FREIGHT_KIND in the environment picks the kind for every clock_at_* below).
func trip_near(near: float, kind: int = -2) -> int:
	if kind == -2:
		var env := OS.get_environment("FREIGHT_KIND")
		kind = env.to_int() if env != "" else -1
	var n0 := maxi(roundi(near / headway), 1)
	if kind < 0:
		return n0
	for k in 40:
		for n: int in [n0 + k, n0 - k]:
			if n >= 1 and int(consist(n).kind) == kind:
				return n
	return n0


## A clock (near `near`) at which trip n's leading end is `before` seconds short of crossing k
## (dir 0 northbound, 1 southbound): for stills and the checks.
func clock_at_crossing(k: int, dir: int, before: float = 6.0, near: float = 5400.0) -> float:
	var n := trip_near(near)
	var c: Dictionary = crossings[clampi(k, 0, crossings.size() - 1)]
	var tr := trips_for(float(consist(n).len))
	var sA := float(c.s) if dir == 0 else float(c.s) - float(consist(n).len)
	return float(n) * headway + _trip_time(tr, dir, sA) - before


## A clock (near `near`) at which some trip's leading end is at s, `before` seconds early.
func clock_at_s(s: float, dir: int, before: float = 0.0, near: float = 5400.0) -> float:
	var n := trip_near(near)
	var tr := trips_for(float(consist(n).len))
	var sA := s if dir == 0 else s - float(consist(n).len)
	return float(n) * headway + _trip_time(tr, dir, sA) - before


## A clock at which trip n (near `near`) stands at the yard (`into` seconds into the dwell).
func clock_at_yard(into: float = 40.0, near: float = 5400.0) -> float:
	var n := trip_near(near)
	var tr := trips_for(float(consist(n).len))
	return float(n) * headway + float(tr.T_nb) + into


## TrafficManager's question: is the line closing junction `node` to traffic on `axis`?
static func crossing_closed(node: Vector2i, axis: int) -> bool:
	if closed.is_empty():
		return false
	return closed.get(node, -1) == axis
