class_name MetroStation
extends RefCounted
## The Coral Line's underground terminus under Flower St at 7th (LightRail.STATIONS[0], the one
## TUNNEL station): what used to be two stair kiosks in the median over nothing is now a station.
## This is its PLAN and its registry; MetroBuild builds it into the chunk that owns the station
## (LightRailKit._entrances() hands it over), MetroRider waits in it.
##
## Everything is laid out in the station's own frame, worked out from the line alone (no roll):
##   u  metres along the line from the platform's centre (+u = the line's +s, grid south),
##   v  metres across it (+v = the line's right, LightRail.track_point's side +1),
##   h  metres above the street at the centre (`y0`).
## Two kiosks in the median at u = -+KIOSK_U, each a stair and a down escalator side by side into
## a CONCOURSE (floor CONC_FLOOR, ceiling CONC_CEIL) with ticket machines in the unpaid ends,
## fare gate lines at u = -+GATE_U and, in the paid middle, a stair and two escalators down onto
## the ISLAND platform (PLATFORM_WIDTH, wider than the street stations' 3 m: LightRail spreads the
## tracks round it), the trains on either side at the line's own rail height, the tunnel running
## on past each end into the dark (TUNNEL_U).
##
## The station is 13 m under the city's ground box (CityStreamer's GroundBody, top at 0), so the
## zone over it lets bodies through the box (MacArthur Park's lake's rule, `sink()`), the player's
## fall-through recovery asks `shelters()` before lifting him out, the road slab is cut over the
## stairwells (`cuts_in()`) and the horizon plane sinks under them (`cut_rect()`). LightRailSystem
## draws the trains in the tunnel while the player is down here (`wants_train()`).
##
## Names: BASIN METRO and the Coral Line are invented (LightRail); the exits are public street
## names. METRO_STATION=0 in the environment is the A/B (the old kiosks over nothing).

static var enabled: bool = OS.get_environment("METRO_STATION") != "0"

## The island platform's width (m); the tracks spread round it (LightRail._place_stations()).
const PLATFORM_WIDTH := 7.0
## Half the station box across (inside face of the walls).
const HALF_W := 7.0
## Levels (h, metres from the street).
const CONC_CEIL := -2.5
const CONC_FLOOR := -6.6
const PLAT_CEIL := -7.2
## The concourse's and the platform box's ends (-+u), the tunnel's dark end (-+u).
const CONC_U := 34.0
const BOX_U := 38.0
const TUNNEL_U := 110.0
## The kiosks: centre -+KIOSK_U, the stair's mouth at -+MOUTH_U (street level, outer end, facing
## the crossing), its foot RUN metres inward; the opening in the street over it, the shaft.
const KIOSK_U := 26.0
const KIOSK_HALF := 5.8
const MOUTH_U := 31.0
const RUN := 13.4
const SHAFT_IN := 20.9
const LANE_HALF := 1.62
## Fare gates at -+GATE_U across the concourse.
const GATE_U := 12.0
## The stair and the escalators down to the platform: an opening in the concourse floor
## (u -BANK_U..+BANK_U, v -+BANK_HALF), the bank running down toward +u.
const BANK_U := 5.8
const BANK_HALF := 2.35
## The lift between the levels (decorative glass shaft).
const LIFT_U := 9.5

static var _volumes: Array = []
## Someone (LightRailSystem's focus: the player) is in the station this tick.
static var showing := false


## The underground terminus of this line: the station dictionary, or {} (none, or switched off).
static func station_of(line: LightRail) -> Dictionary:
	if not enabled or line == null:
		return {}
	for st in line.stations:
		if int(st.mode) == LightRail.Mode.TUNNEL:
			return st
	return {}


## The station's frame: {"o": Vector2 centre, "d": Vector2 along +u, "r": Vector2 along +v,
## "y0": street, "rail": rail height h, "plat": platform top h, "s": the centre's s}.
static func frame(line: LightRail) -> Dictionary:
	var st := station_of(line)
	if st.is_empty():
		return {}
	var smp := line.sample(float(st.s))
	var d: Vector2 = smp.dir
	var y0: float = smp.street
	var rail: float = float(smp.y) - y0
	return {"o": smp.pos, "d": d, "r": Vector2(-d.y, d.x), "y0": y0, "rail": rail,
		"plat": rail + LightRail.PLATFORM_HEIGHT, "s": float(st.s), "name": str(st.name), "st": st}


## A station point (u, h, v) in TRUE world.
static func to_world(f: Dictionary, p: Vector3) -> Vector3:
	var q: Vector2 = (f.o as Vector2) + (f.d as Vector2) * p.x + (f.r as Vector2) * p.z
	return Vector3(q.x, float(f.y0) + p.y, q.y)


## A TRUE world point in the frame (u, h, v).
static func to_frame(f: Dictionary, w: Vector3) -> Vector3:
	var rel := Vector2(w.x, w.z) - (f.o as Vector2)
	return Vector3(rel.dot(f.d), w.y - float(f.y0), rel.dot(f.r))


## The street openings over the two stairs, in the frame: [u0, u1, v0, v1] each.
static func openings() -> Array:
	var out := []
	for k: float in [-1.0, 1.0]:
		var a := k * (MOUTH_U + 0.15)
		var b := k * (SHAFT_IN + 0.05)
		out.append([minf(a, b), maxf(a, b), -LANE_HALF - 0.1, LANE_HALF + 0.1])
	return out


## The world rects of the openings that cut `r` (CityChunk._road_slab(): the road is laid round
## them), FULL chunks only.
static func cuts_in(plan: CityPlan, r: Rect2) -> Array[Rect2]:
	var out: Array[Rect2] = []
	var f := frame(LightRail.of(plan))
	if f.is_empty():
		return out
	for o: Array in openings():
		var a := to_world(f, Vector3(o[0], 0.0, o[2]))
		var b := to_world(f, Vector3(o[1], 0.0, o[3]))
		var rr := Rect2(Vector2(minf(a.x, b.x), minf(a.z, b.z)), Vector2(absf(a.x - b.x), absf(a.z - b.z)))
		if rr.intersects(r):
			out.append(rr)
	return out


## The horizon plane's second cut (macro_ground.gdshader cut_rect2): both kiosks' openings.
static func cut_rect(line: LightRail) -> Rect2:
	var f := frame(line)
	if f.is_empty():
		return Rect2()
	var a := to_world(f, Vector3(-MOUTH_U - 0.5, 0.0, -LANE_HALF - 0.5))
	var b := to_world(f, Vector3(MOUTH_U + 0.5, 0.0, LANE_HALF + 0.5))
	return Rect2(Vector2(minf(a.x, b.x), minf(a.z, b.z)), Vector2(absf(a.x - b.x), absf(a.z - b.z)))


## The volumes a body may be in, in the frame: [u0, u1, h0, h1, v0, v1] each (the platform box
## with the tunnel, the concourse, the two stairwells up to a little over the street).
static func volumes(f: Dictionary) -> Array:
	var tr := float(f.rail) - 1.2
	var out := [[-TUNNEL_U, TUNNEL_U, tr, PLAT_CEIL + 0.1, -HALF_W - 0.2, HALF_W + 0.2],
		[-CONC_U - 0.2, CONC_U + 0.2, CONC_FLOOR - 0.6, CONC_CEIL, -HALF_W - 0.2, HALF_W + 0.2]]
	for o: Array in openings():
		out.append([float(o[0]) - 0.2, float(o[1]) + 0.2, CONC_CEIL - 0.5, 3.0, float(o[2]) - 0.2, float(o[3]) + 0.2])
	return out


## Registered by the build while the station's chunk is in the tree (true world frame + volumes).
static func register(f: Dictionary) -> void:
	_volumes.append(f)


static func unregister(f: Dictionary) -> void:
	_volumes.erase(f)


static func built() -> bool:
	return not _volumes.is_empty()


## True when a TRUE world point is inside the station (stairwells included). Player's
## fall-through recovery asks this before lifting him out from under the street.
static func shelters(w: Vector3) -> bool:
	for f: Dictionary in _volumes:
		var p := to_frame(f, w)
		for b: Array in volumes(f):
			if p.x >= b[0] and p.x <= b[1] and p.y >= b[2] and p.y <= b[3] and p.z >= b[4] and p.z <= b[5]:
				return true
	return false


## LightRailSystem: draw this train although it is in the tunnel? While someone (the focus) is in
## the station, every train with any part inside the drawn tunnel is.
static func wants_train(line: LightRail, st: Dictionary, focus: Vector3) -> bool:
	if _volumes.is_empty() or not (showing or shelters(focus)):
		return false
	var f := frame(line)
	if f.is_empty():
		return false
	var front := float(st.s) - float(f.s)
	var rear := front - float(st.dir) * LightRail.TRAIN_LENGTH
	return maxf(front, rear) > -TUNNEL_U and minf(front, rear) < TUNNEL_U


## LightRailTrain: draw a section centred at `s` although it is in the tunnel? While someone is
## in the station, along the tunnel it draws.
static func draws(line: LightRail, s: float) -> bool:
	if not showing or _volumes.is_empty():
		return false
	var f := frame(line)
	return not f.is_empty() and absf(s - float(f.s)) < TUNNEL_U


## Where alighting riders walk to (TRUE world XZ): the foot of the bank up to the concourse.
static func exit_point(line: LightRail) -> Vector2:
	var f := frame(line)
	var w := to_world(f, Vector3(BANK_U + 2.0, 0.0, 0.0))
	return Vector2(w.x, w.z)


## Lets a body through the city's ground box while it is in the station (or stops letting it): a
## collision exception per pair, nothing else changes (the lake's rule). One zone, so one enter
## and one exit per body: `inside` is a set.
static func sink(zone: Area3D, body: Node3D, on: bool, inside: Dictionary) -> void:
	if not (body is PhysicsBody3D) or not zone.is_inside_tree():
		return
	var city := zone.get_tree().get_first_node_in_group("city")
	var ground := city.get_node_or_null("GroundBody") as PhysicsBody3D if city else null
	if ground == null:
		return
	var id := body.get_instance_id()
	if on:
		if inside.has(id):
			return
		inside[id] = body
		PhysicsServer3D.body_add_collision_exception((body as PhysicsBody3D).get_rid(), ground.get_rid())
	else:
		if not inside.has(id):
			return
		inside.erase(id)
		if is_instance_valid(body):
			PhysicsServer3D.body_remove_collision_exception((body as PhysicsBody3D).get_rid(), ground.get_rid())


## Lets `body` through the ground box at once (a teleport into the station: the zone only sees
## it after the next physics step, and a body stood inside the box for a step is thrown out of
## it). The zone's exit takes the exception away again as usual.
static func admit(body: PhysicsBody3D) -> void:
	for f: Dictionary in _volumes:
		if f.has("zone") and is_instance_valid(f.zone):
			sink(f.zone, body, true, f.inside)


## The exits' street names: [north kiosk, south kiosk].
static func exit_names(line: LightRail) -> Array:
	var f := frame(line)
	var plan := line.plan
	var out := []
	for k: float in [-1.0, 1.0]:
		var w := to_world(f, Vector3(k * MOUTH_U, 0.0, 0.0))
		var bk := plan.block_index_at(Vector2(w.x, w.z))
		var best := ""
		var bd := INF
		for iz in [bk.y, bk.y + 1]:
			var dz := absf(plan.road_pos(CityPlan.AXIS_Z, iz) - w.z)
			# The crossing the mouth faces: the one on its own side.
			if signf(plan.road_pos(CityPlan.AXIS_Z, iz) - w.z) != signf(k * (f.d as Vector2).y) and dz > 1.0:
				continue
			if dz < bd:
				bd = dz
				best = plan.road_name(CityPlan.AXIS_Z, iz)
		out.append(best)
	return out
