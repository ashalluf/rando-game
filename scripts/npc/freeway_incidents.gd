class_name FreewayIncidents
extends Node3D
## The freeway's everyday incidents (fleet wave 2, "freeway-incidents"), worked out from a clock,
## never rolled live: every carriageway is cut into ZONE-long stretches, every stretch's time into
## PERIOD-long slots (phased per stretch), and a hash of seed + route + stretch + direction + slot
## says what happens in that slot (incident()):
##
##   STALL     a car breaks down: it coasts onto the outer shoulder and stops on its hazards, its
##             driver gets out and stands behind it on the phone; a BASIN HIGHWAY PATROL car
##             (FreewayPatrol, invented) rolls up the shoulder with its bar flashing and parks
##             behind it; a rollback tow truck (ServiceVehicles' TOW and its TowBed) comes up the
##             slow lane, pulls in ahead, tilts its bed, winches the car on and drives off with
##             it and the driver in the cab, the patrol car after it. Traffic moves over out of
##             the slow lane past the scene (or slows), and both carriageways slow to look.
##   TYRE      a truck tyre's shredded tread lies across a lane (FreewayIncidentKit.tread_mesh()).
##   MATTRESS  a mattress lies in a lane. For both, cars in that lane change lanes round it (a gap
##             check like TrafficAI's), or stop short of it and wait for one.
##   SLOW      a slowdown: a stretch of a carriageway where traffic crawls in waves that run
##             upstream, then clears.
##
## Changeable message signs (CMS) hang on some gantries (has_cms(), FreewayKit's gantry hook builds
## the cabinet at every level); near the player each gets its LED face, saying what is ahead on
## its carriageway (the nearest incident within CMS_LOOK), else travel times or a safety message.
##
## Hooks (one or two lines each): TrafficManager adds this node; _drive_freeway() calls drive() for
## every freeway car (the blocks and the slow zones, and the lane changes round them);
## _spawn_freeway_car() asks spawn_lane() for a lane with nothing in it; FreewayKit._sign_pair()
## asks has_cms(). Everything else is here. `FREEWAY_INCIDENTS=0` in the environment turns it off.
## Stills and checks force one: `FW_INCIDENT=stall|tyre|mattress|slow`, `FW_INCIDENT_T=<seconds
## into it>` (with FW_INCIDENT_HOLD=1 the clock stands still), placed on the route point nearest
## the player (`FW_INCIDENT_AT=<route>:<t>:<dir>` exactly).

enum Kind { NONE, STALL, TYRE, MATTRESS, SLOW }

static var enabled: bool = OS.get_environment("FREEWAY_INCIDENTS") != "0"

## A stretch of carriageway (m) and a slot of time (s): one roll each.
const ZONE := 1000.0
const PERIOD := 480.0
## What a slot rolls (cumulative shares; the rest is a quiet slot).
const ODDS := [[Kind.STALL, 0.2], [Kind.TYRE, 0.31], [Kind.MATTRESS, 0.38], [Kind.SLOW, 0.5]]
## Incidents keep this far from a route's ends and from any ramp on the route (m).
const END_KEEP := 300.0
const RAMP_KEEP := 150.0
## The stall's script (seconds from its start; the car coasts in over STALL_COAST before it).
const STALL_COAST := 11.0
const PATROL_DRIVE := 14.0
const TOW_DRIVE := 16.0
const BED_SECONDS := 6.0
const WINCH_SECONDS := 15.0
const LEAVE_DRIVE := 16.0
## Lengths along the shoulder (m): patrol behind the stall, the tow ahead of it.
const PATROL_GAP := 4.5
const TOW_GAP := 1.2
## How far the scene (vehicles, people, debris) is built from the player (m), and the faces.
const BUILD_REACH := 750.0
const CMS_REACH := 520.0
const CMS_LOOK := 4200.0
## A gantry carries a CMS on this share of its carriageways (has_cms()).
const CMS_SHARE := 0.34
## Traffic: soft blocks (the stall) cap the slow lane to this share of a car's speed, the look
## zones round a stall both ways to LOOK_CAP over LOOK_REACH, debris lanes either side to
## DEBRIS_LOOK; a slowdown's crawl runs from SLOW_MIN to SLOW_MAX of the speed.
const SOFT_CAP := 0.5
const LOOK_CAP := 0.72
const LOOK_REACH := 220.0
const DEBRIS_LOOK := 0.8
const SLOW_MIN := 0.22
const SLOW_MAX := 0.62
const SWERVE_SECONDS := 2.6

## The one clock (physics seconds since the city loaded, plus a seeded start).
static var clock: float = 0.0
static var hold: bool = OS.get_environment("FW_INCIDENT_HOLD") == "1"
## The live node (null when off).
static var current: FreewayIncidents
## Counts for the checks: "swerve", "stop", "spawn_moved", "built_<kind>", "tow_loaded", ...
static var counts: Dictionary = {}
static var _forced: Array = []

var plan: CityPlan
var tm: TrafficManager
## Incidents near the player: key -> {"inc": Dictionary, "scene": Dictionary}.
var _live: Dictionary = {}
## Per Vector2i(route, dir): blocks [{"a", "b", "lanes" (bitmask), "v", "hard", "cap", "kind"}]
## and zones [{"a", "b", "cap", "wave"}], rebuilt every physics tick.
var _blocks: Dictionary = {}
var _zones: Dictionary = {}
## CMS faces near the player: Vector3i(route, gantry index, side) -> {"mi", "mat", "msg"}.
var _cms: Dictionary = {}
var _survey := 0.0
var _player: Node3D


static func count(what: String) -> void:
	counts[what] = int(counts.get(what, 0)) + 1


static func h01(parts: Array) -> float:
	return float(absi(hash(parts)) % 100003) / 100003.0


# --- The schedule (pure) -----------------------------------------------------------------------------

## The slot `clock` is in for stretch (ri, zone, dir) and where in it (seconds).
static func slot_of(seed: int, ri: int, zone: int, dir: int, at_clock: float) -> Vector2:
	var phase := h01([seed, ri, zone, dir, "fwi_phase"]) * PERIOD
	var u := (at_clock + phase) / PERIOD
	return Vector2(floorf(u), (u - floorf(u)) * PERIOD)


## What happens in slot `slot` of stretch (ri, zone, dir): {} for nothing, else {"kind", "ri",
## "dir", "zone", "slot", "t" (route metres), "start" / "end" (clock), "li" (debris lane), "len"
## (a slowdown's length), "seed", and the stall's timings "patrol" / "tow" (seconds from start)}.
static func incident(fw: Freeway, seed: int, ri: int, zone: int, dir: int, slot: int) -> Dictionary:
	if fw == null or ri < 0 or ri >= fw.routes.size():
		return {}
	var roll := h01([seed, ri, zone, dir, slot, "fwi_kind"])
	var kind := Kind.NONE
	for o: Array in ODDS:
		if roll < float(o[1]):
			kind = o[0]
			break
	if kind == Kind.NONE:
		return {}
	var total := fw.length_of(ri)
	var t := float(zone) * ZONE + 120.0 + h01([seed, ri, zone, dir, slot, "fwi_t"]) * (ZONE - 240.0)
	if t < END_KEEP or t > total - END_KEEP:
		return {}
	var s := absi(hash([seed, ri, zone, dir, slot, "fwi_seed"]))
	var inc := {"kind": kind, "ri": ri, "dir": dir, "zone": zone, "slot": slot, "t": t, "seed": s}
	var dur := 0.0
	match kind:
		Kind.STALL:
			var patrol := 18.0 + h01([s, 1]) * 40.0
			var tow := patrol + PATROL_DRIVE + 50.0 + h01([s, 2]) * 80.0
			inc.patrol = patrol
			inc.tow = tow
			dur = tow + TOW_DRIVE + BED_SECONDS * 2.0 + WINCH_SECONDS + 8.0 + LEAVE_DRIVE + 6.0
		Kind.TYRE, Kind.MATTRESS:
			dur = 110.0 + h01([s, 3]) * 170.0
			inc.li = s % Freeway.LANES
		Kind.SLOW:
			dur = 200.0 + h01([s, 4]) * 200.0
			inc.len = 500.0 + h01([s, 5]) * 700.0
	var lead := STALL_COAST if kind == Kind.STALL else 0.0
	var slack := PERIOD - dur - lead - 10.0
	var slot_start := float(slot) * PERIOD - h01([seed, ri, zone, dir, "fwi_phase"]) * PERIOD
	inc.start = slot_start + lead + h01([s, 6]) * maxf(slack, 0.0)
	inc.end = float(inc.start) + dur
	return inc


## True if an incident at route metres `t` would sit on something it must not: a ramp of the
## route, the four-level stack's touch runs or the deck under another one.
static func site_ok(fw: Freeway, ri: int, t: float, dir: int = 0) -> bool:
	var run: PackedFloat32Array = fw._runs[ri]
	for r in fw.ramps:
		# A ramp serves one carriageway: side +1 the +t traffic's off-ramps, -1 the -t's on-ramps.
		if int(r.route) == ri and (dir == 0 or float(r.side) * float(dir) > 0.0) and absf(run[int(r.index)] - t) < RAMP_KEEP:
			return false
	if fw.stack != null:
		var idx := int(t / Freeway.STEP)
		for k in range(idx - 12, idx + 13):
			if fw.stack.open_edges.has(Vector2i(ri, k)) or fw.stack.covered.has(Vector2i(ri, k)):
				return false
	return true


## Every incident running at `at_clock` on route `ri` whose stretch reaches [t0, t1].
static func running(fw: Freeway, seed: int, ri: int, t0: float, t1: float, at_clock: float) -> Array:
	var out := []
	for f: Dictionary in _forced:
		if int(f.ri) == ri and float(f.t) > t0 - ZONE and float(f.t) < t1 + ZONE and at_clock >= float(f.start) - STALL_COAST and at_clock < float(f.end):
			out.append(f)
	if not _forced.is_empty() and OS.get_environment("FW_INCIDENT_ONLY") == "1":
		return out
	var total := fw.length_of(ri)
	for zone in range(maxi(0, floori(t0 / ZONE)), mini(ceili(total / ZONE), floori(t1 / ZONE) + 1)):
		for dir: int in [1, -1]:
			var sl := slot_of(seed, ri, zone, dir, at_clock)
			var inc := incident(fw, seed, ri, zone, dir, int(sl.x))
			if inc.is_empty():
				continue
			var lead := STALL_COAST if int(inc.kind) == Kind.STALL else 0.0
			if at_clock < float(inc.start) - lead or at_clock >= float(inc.end):
				continue
			if not site_ok(fw, ri, float(inc.t), dir):
				continue
			out.append(inc)
	return out


static func key_of(inc: Dictionary) -> String:
	return "%d:%d:%d:%d:%d" % [int(inc.ri), int(inc.zone), int(inc.dir), int(inc.slot), int(inc.kind)]


## Forces an incident (stills, checks): `kind` at route `ri`, `t`, `dir`, `into` seconds into it
## at the current clock. Returns the incident.
static func force(fw: Freeway, ri: int, t: float, dir: int, kind: int, into: float, li: int = 2) -> Dictionary:
	var s := absi(hash([ri, int(t), dir, kind, "fwi_forced"]))
	var inc := {"kind": kind, "ri": ri, "dir": dir, "zone": -1 - _forced.size(), "slot": 0, "t": t, "seed": s, "li": li, "forced": true}
	var dur := 0.0
	match kind:
		Kind.STALL:
			inc.patrol = 25.0
			inc.tow = 25.0 + PATROL_DRIVE + 60.0
			dur = float(inc.tow) + TOW_DRIVE + BED_SECONDS * 2.0 + WINCH_SECONDS + 8.0 + LEAVE_DRIVE + 6.0
		Kind.TYRE, Kind.MATTRESS:
			dur = 3600.0
		Kind.SLOW:
			dur = 3600.0
			inc.len = 900.0
	inc.start = clock - into
	inc.end = float(inc.start) + dur
	_forced.append(inc)
	return inc


static func clear_forced() -> void:
	_forced.clear()


# --- Lanes and places ----------------------------------------------------------------------------------

static func lay(fw: Freeway, ri: int) -> Dictionary:
	return Freeway.lane_layout(float(fw.routes[ri].width))


## Metres from the route's centre line (signed: + the +t carriageway's side) of lane `li`, and of
## the outer shoulder's middle, for traffic driving `dir`.
static func lane_lat(fw: Freeway, ri: int, li: int, dir: int) -> float:
	var lo := lay(fw, ri)
	return (float(lo.inner) + float(lo.lane) * (float(li) + 0.5)) * float(dir)


static func shoulder_lat(fw: Freeway, ri: int, dir: int) -> float:
	var lo := lay(fw, ri)
	return (float(lo.edge) + float(lo.outer)) * 0.5 * float(dir)


## A transform (scene space) at route metres `t`, `lat` metres across, heading `dir`, `lift` up.
static func xform_at(fw: Freeway, ri: int, t: float, lat: float, dir: int, lift: float, yaw_extra: float = 0.0) -> Transform3D:
	var at: Array = fw.point_at(ri, t)
	var p: Vector3 = at[0]
	var d: Vector2 = at[1]
	var n := Vector2(-d.y, d.x)
	var heading := d * float(dir)
	var step := 2.5 * float(dir)
	var ahead: float = (fw.point_at(ri, t + step)[0] as Vector3).y
	var behind: float = (fw.point_at(ri, t - step)[0] as Vector3).y
	var basis := Basis.from_euler(Vector3(atan2(ahead - behind, 5.0), atan2(-heading.x, -heading.y) + yaw_extra, 0.0))
	return Transform3D(basis, WorldState.to_local(Vector3(p.x + n.x * lat, p.y + lift, p.z + n.y * lat)))


## True world point on the deck at (t, lat).
static func deck_point(fw: Freeway, ri: int, t: float, lat: float) -> Vector3:
	var at: Array = fw.point_at(ri, t)
	var p: Vector3 = at[0]
	var d: Vector2 = at[1]
	return Vector3(p.x - d.y * lat, p.y, p.z + d.x * lat)


## Distance left to stop for a vehicle braking at `decel` (m/s2) to a stop `tau` seconds from now
## that cruised at `v0` before it started braking.
static func _stopping(tau: float, v0: float, decel: float) -> float:
	var brake := v0 / decel
	if tau <= 0.0:
		return 0.0
	if tau <= brake:
		return 0.5 * decel * tau * tau
	return 0.5 * decel * brake * brake + v0 * (tau - brake)


## Distance gone `tau` seconds after starting from rest, accelerating at `acc` up to `v1`.
static func _going(tau: float, v1: float, acc: float) -> float:
	if tau <= 0.0:
		return 0.0
	var ramp := v1 / acc
	if tau <= ramp:
		return 0.5 * acc * tau * tau
	return 0.5 * acc * ramp * ramp + v1 * (tau - ramp)


# --- The stall's script (pure: where everything is `e` seconds into it) -------------------------------

## {"car": [s, lat_k, v, way], "patrol": [...], "tow": [...], "bed": 0..1, "winch": 0..1, "loaded": bool,
## "driver": bool (standing out), "patrol_lights": bool} with s the metres along the carriageway
## from the stall's spot (+ ahead), lat_k 0 in the slow lane .. 1 on the shoulder, v m/s, way 1
## coming in, -1 going, 0 standing; a
## missing entry is not there. Lengths from the vehicles' own halves (`halves` [car, patrol, tow]).
static func stall_pose(inc: Dictionary, e: float, halves: Array) -> Dictionary:
	var out := {}
	var hc := float(halves[0])
	var hp := float(halves[1])
	var ht := float(halves[2])
	var patrol_at := float(inc.patrol)
	var tow_at := float(inc.tow)
	var tow_stop := tow_at + TOW_DRIVE
	var bed_down := tow_stop + 1.0
	var winch := bed_down + BED_SECONDS
	var bed_up := winch + WINCH_SECONDS
	var leave := bed_up + BED_SECONDS + 4.0
	var patrol_leave := leave + 6.0
	# The car: coasting in from the slow lane over STALL_COAST.
	if e < 0.0:
		var tau := -e
		var s := -_stopping(tau, 22.0, 2.0)
		out.car = [s, clampf(1.0 - (-s) / 55.0, 0.0, 1.0), minf(22.0, 2.0 * tau), 1]
	elif e < leave + LEAVE_DRIVE:
		# From `leave` it rides the bed (placed off the tow's deck, not from this entry).
		out.car = [0.0, 1.0, 0.0, 0]
	out.driver = e > 6.0 and e < bed_up
	out.hazard = true
	out.handover = e >= leave + LEAVE_DRIVE
	out.patrol_handover = e >= patrol_leave + LEAVE_DRIVE
	# The patrol car: up the shoulder from 260 m back, lights going, parks behind.
	var p_stop := -(hc + PATROL_GAP + hp)
	if e >= patrol_at and e < patrol_leave + LEAVE_DRIVE:
		if e < patrol_at + PATROL_DRIVE:
			var tau := patrol_at + PATROL_DRIVE - e
			out.patrol = [p_stop - _stopping(tau, 25.0, 2.6), 1.0, minf(25.0, 2.6 * tau), 1]
		elif e < patrol_leave:
			out.patrol = [p_stop, 1.0, 0.0, 0]
		else:
			var go := e - patrol_leave
			var s := _going(go, 24.0, 2.2)
			out.patrol = [p_stop + s, clampf(1.0 - (s - 20.0) / 70.0, 0.0, 1.0), minf(24.0, 2.2 * go), -1]
		out.patrol_lights = e < patrol_leave + 3.0
	# The tow truck: up the slow lane from 280 m back, onto the shoulder past the car, stops ahead
	# of it; the bed, the winch, back up; off along the shoulder and into the slow lane.
	var t_stop := hc + TOW_GAP + ht
	if e >= tow_at and e < leave + LEAVE_DRIVE:
		if e < tow_stop:
			var tau := tow_stop - e
			var s := t_stop - _stopping(tau, 20.0, 1.8)
			out.tow = [s, clampf(1.0 - (t_stop - s) / 70.0, 0.0, 1.0), minf(20.0, 1.8 * tau), 1]
		elif e < leave:
			out.tow = [t_stop, 1.0, 0.0, 0]
		else:
			var go := e - leave
			var s := _going(go, 22.0, 1.6)
			out.tow = [t_stop + s, clampf(1.0 - (s - 25.0) / 80.0, 0.0, 1.0), minf(22.0, 1.6 * go), -1]
		var bed := 0.0
		if e >= bed_down and e < winch:
			bed = (e - bed_down) / BED_SECONDS
		elif e >= winch and e < bed_up:
			bed = 1.0
		elif e >= bed_up and e < bed_up + BED_SECONDS:
			bed = 1.0 - (e - bed_up) / BED_SECONDS
		out.bed = bed
		out.winch = clampf((e - winch) / WINCH_SECONDS, 0.0, 1.0)
		out.loaded = e >= winch
	return out


# --- The node -----------------------------------------------------------------------------------------

func _ready() -> void:
	current = self
	name = "FreewayIncidents"
	process_physics_priority = 10
	if clock == 0.0 and plan != null:
		clock = h01([plan.seed, "fwi_clock"]) * PERIOD * 4.0


func _exit_tree() -> void:
	if current == self:
		current = null


func _fw() -> Freeway:
	if plan == null or plan.macro == null:
		return null
	return plan.macro.freeway


func _physics_process(delta: float) -> void:
	if not enabled:
		return
	if not hold:
		clock += delta
	var fw := _fw()
	if fw == null or fw.routes.is_empty():
		return
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
		if _player == null:
			return
	_maybe_force(fw)
	_shot_sequence()
	_survey -= delta
	if _survey <= 0.0:
		_survey = 0.5
		_update_live(fw)
		_update_cms(fw)
	_blocks.clear()
	_zones.clear()
	for k in _live:
		_tick_incident(fw, _live[k], delta)


var _force_done := false


## FW_INCIDENT=...: one incident forced where the player is (or at FW_INCIDENT_AT), once.
func _maybe_force(fw: Freeway) -> void:
	if _force_done:
		return
	_force_done = true
	var what := OS.get_environment("FW_INCIDENT")
	if what == "":
		return
	# Several at once: FW_INCIDENT="mattress,tyre", FW_INCIDENT_AT="3:1904:1;3:1000:-1",
	# FW_INCIDENT_LANE="2,1" (each list in step; a missing entry takes the first's).
	var kinds := {"stall": Kind.STALL, "tyre": Kind.TYRE, "mattress": Kind.MATTRESS, "slow": Kind.SLOW}
	var into := OS.get_environment("FW_INCIDENT_T").to_float() if OS.get_environment("FW_INCIDENT_T") != "" else 30.0
	var whats := what.split(",", false)
	var ats := OS.get_environment("FW_INCIDENT_AT").split(";", false)
	var lanes := OS.get_environment("FW_INCIDENT_LANE").split(",", false)
	for n in whats.size():
		var w := whats[n]
		if not kinds.has(w):
			continue
		var at := (ats[mini(n, ats.size() - 1)] if not ats.is_empty() else "").split(":", false)
		var ri := 0
		var t := 0.0
		var dir := 1
		if at.size() >= 3:
			ri = at[0].to_int()
			t = at[1].to_float()
			dir = at[2].to_int()
		else:
			var pw := WorldState.to_world(_player.global_position)
			var best := INF
			for r in fw.routes.size():
				var near: Array = fw.nearest_on(r, Vector2(pw.x, pw.z))
				if float(near[1]) < best:
					best = float(near[1])
					ri = r
					t = float(near[0])
		var li := lanes[mini(n, lanes.size() - 1)].to_int() if not lanes.is_empty() else 2
		force(fw, ri, t, dir, kinds[w], into, li)
		print("FW_INCIDENT %s route %d t %.1f dir %d into %.1f" % [w, ri, t, dir, into])
	_update_live(fw)


var _shot_k := 0


## FW_INCIDENT_TIMES="t1,t2,...": tools/glshot/still_shot.gd's SHOTS take the forced incidents at
## those seconds into them, one a shot (it tells which shot it is on through an Engine meta).
func _shot_sequence() -> void:
	if _forced.is_empty() or not Engine.has_meta("still_shot_index"):
		return
	var k := int(Engine.get_meta("still_shot_index"))
	if k == _shot_k:
		return
	_shot_k = k
	var times := OS.get_environment("FW_INCIDENT_TIMES").split(",", false)
	if k < 1 or k > times.size():
		return
	for inc: Dictionary in _forced:
		var dur := float(inc.end) - float(inc.start)
		inc.start = clock - times[k - 1].to_float()
		inc.end = float(inc.start) + dur
	print("FW_INCIDENT shot %d at %s s" % [k, times[k - 1]])


## Which incidents run near the player now: build the new ones' scenes, drop the ones gone.
func _update_live(fw: Freeway) -> void:
	var pw := WorldState.to_world(_player.global_position)
	var here := Vector2(pw.x, pw.z)
	var reach := (tm.freeway_range if tm else 620.0) * 1.4
	var seen := {}
	for ri in fw.routes.size():
		var near: Array = fw.nearest_on(ri, here)
		if float(near[1]) > reach + 200.0:
			continue
		var t := float(near[0])
		for inc: Dictionary in running(fw, plan.seed, ri, t - reach, t + reach, clock):
			var k := key_of(inc)
			seen[k] = true
			if not _live.has(k):
				_live[k] = {"inc": inc, "scene": {}}
	for k in _live.keys():
		var entry: Dictionary = _live[k]
		var inc: Dictionary = entry.inc
		var gone := not seen.has(k)
		var p := deck_point(fw, int(inc.ri), float(inc.t), 0.0)
		var near_enough := Vector2(p.x, p.z).distance_to(here) < BUILD_REACH
		if gone or not near_enough:
			_clear_scene(entry)
		if gone:
			_live.erase(k)
		elif near_enough and entry.scene.is_empty():
			_build_scene(fw, entry)


func _build_scene(fw: Freeway, entry: Dictionary) -> void:
	var inc: Dictionary = entry.inc
	var sc: Dictionary = entry.scene
	sc.built = true
	match int(inc.kind):
		Kind.TYRE:
			var root := Node3D.new()
			root.name = "TyreDebris"
			add_child(root)
			var n := 2 + int(inc.seed) % 4
			for k in n:
				var mi := MeshInstance3D.new()
				mi.mesh = FreewayIncidentKit.tread_mesh(absi(hash([inc.seed, k])) % 6)
				mi.visibility_range_end = 260.0
				mi.set_meta("off", Vector3((h01([inc.seed, k, "x"]) - 0.5) * 2.4, 0.0, (h01([inc.seed, k, "z"]) - 0.5) * 14.0))
				mi.set_meta("yaw", h01([inc.seed, k, "yaw"]) * TAU)
				root.add_child(mi)
			sc.debris = root
			count("built_tyre")
		Kind.MATTRESS:
			var root := Node3D.new()
			root.name = "Mattress"
			add_child(root)
			var mi := MeshInstance3D.new()
			mi.mesh = FreewayIncidentKit.mattress_mesh(int(inc.seed) % 3)
			mi.visibility_range_end = 320.0
			mi.set_meta("off", Vector3((h01([inc.seed, "mx"]) - 0.5) * 0.8, 0.0, 0.0))
			mi.set_meta("yaw", (h01([inc.seed, "myaw"]) - 0.5) * 1.4)
			root.add_child(mi)
			sc.debris = root
			count("built_mattress")
		Kind.STALL:
			var rng := RandomNumberGenerator.new()
			rng.seed = int(inc.seed)
			var car := Vehicle.random_car(rng)
			car.traffic = {"fw_incident": true}
			car.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
			car.freeze = true
			_enter(fw, car, inc, -400.0)
			# Nobody in it: the driver is out on the shoulder. Hazards from the alarm path's flag.
			car._npc_driver = false
			car._update_occupant()
			car.alarm_left = 1.0e9
			sc.car = car
			var patrol := FreewayPatrol.make(int(inc.seed))
			_enter(fw, patrol, inc, -600.0)
			sc.patrol = patrol
			var tow := BigVehicles.make(ServiceVehicles.TOW, int(inc.seed) % 9973)
			tow.traffic = {"fw_incident": true}
			tow.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
			tow.freeze = true
			_enter(fw, tow, inc, -800.0)
			sc.tow = tow
			count("built_stall")
	_place_scene(fw, entry)


## Puts a vehicle into the tree already placed (the aircraft trap: a kinematic body that enters
## at the origin and jumps away has moved at hundreds of km/s for a step).
func _enter(fw: Freeway, car: Vehicle, inc: Dictionary, s: float) -> void:
	var dir := int(inc.dir)
	car.transform = global_transform.affine_inverse() * xform_at(fw, int(inc.ri), float(inc.t) + s * float(dir), shoulder_lat(fw, int(inc.ri), dir), dir, 0.6)
	add_child(car)
	car.visible = false


func _clear_scene(entry: Dictionary) -> void:
	var sc: Dictionary = entry.scene
	for k in ["debris", "car", "patrol", "tow", "driver"]:
		var n: Variant = sc.get(k)
		if n != null and is_instance_valid(n) and _owned(n as Node):
			(n as Node).queue_free()
	sc.clear()


## A vehicle is ours while it is still our traffic: a hit knocks a car out of it (go_physical),
## and from then on it is a car like any other.
func _owned(n: Node) -> bool:
	if n is Vehicle:
		return (n as Vehicle).traffic.has("fw_incident")
	return true


func _tick_incident(fw: Freeway, entry: Dictionary, delta: float) -> void:
	var inc: Dictionary = entry.inc
	var ri := int(inc.ri)
	var dir := int(inc.dir)
	var key := Vector2i(ri, dir)
	var t := float(inc.t)
	match int(inc.kind):
		Kind.TYRE, Kind.MATTRESS:
			var li := int(inc.li)
			var half := 9.0 if int(inc.kind) == Kind.TYRE else 2.0
			_add_block(key, {"a": t - half, "b": t + half, "lanes": 1 << li, "v": 0.0, "hard": true, "kind": "debris"})
			# The lanes either side slow a little to look.
			_add_zone(key, {"a": t - 60.0, "b": t + 20.0, "cap": DEBRIS_LOOK, "wave": false, "lanes": ((1 << (li + 1)) | (1 << maxi(li - 1, 0))) & ~(1 << li)})
		Kind.SLOW:
			var a := t if dir > 0 else t - float(inc.len)
			_add_zone(key, {"a": a, "b": a + float(inc.len), "cap": SLOW_MAX, "wave": true, "lanes": 15})
	if int(inc.kind) == Kind.STALL:
		_tick_stall(fw, entry, delta)
	_place_scene(fw, entry)


func _tick_stall(fw: Freeway, entry: Dictionary, _delta: float) -> void:
	var inc: Dictionary = entry.inc
	var sc: Dictionary = entry.scene
	var ri := int(inc.ri)
	var dir := int(inc.dir)
	var t := float(inc.t)
	var key := Vector2i(ri, dir)
	var e := clock - float(inc.start)
	var pose := stall_pose(inc, e, _halves(sc))
	entry.pose = pose
	_handover(fw, entry, pose)
	var slow := Freeway.LANES - 1
	var any_on_shoulder := false
	for who in ["car", "patrol", "tow"]:
		if not pose.has(who):
			continue
		var p: Array = pose[who]
		var s := float(p[0])
		var half := float(_halves(sc)[["car", "patrol", "tow"].find(who)])
		var at := t + s * float(dir)
		var a := at - half - 1.0
		var b := at + half + 1.0
		if float(p[1]) < 0.75:
			# In (or half in) the slow lane: a moving block the lane follows.
			_add_block(key, {"a": a, "b": b, "lanes": 1 << slow, "v": float(p[2]), "hard": true, "kind": "vehicle"})
		else:
			any_on_shoulder = true
			_add_block(key, {"a": a - 25.0, "b": b + 8.0, "lanes": 1 << slow, "v": 0.0, "hard": false, "cap": SOFT_CAP, "kind": "move_over"})
	if any_on_shoulder:
		# Both carriageways slow to look.
		_add_zone(key, {"a": t - LOOK_REACH, "b": t + 40.0, "cap": LOOK_CAP, "wave": false, "lanes": 15})
		_add_zone(Vector2i(ri, -dir), {"a": t - LOOK_REACH * 0.6, "b": t + LOOK_REACH * 0.6, "cap": LOOK_CAP + 0.1, "wave": false, "lanes": 15})


## The tow (with the car on its bed) and the patrol car, once their script has them driving down
## the slow lane, become the traffic's own freeway cars: they drive on with everyone else and are
## retired like them, out of the player's range, the car with the tow.
func _handover(fw: Freeway, entry: Dictionary, pose: Dictionary) -> void:
	if tm == null:
		return
	var inc: Dictionary = entry.inc
	var sc: Dictionary = entry.scene
	for who in ["tow", "patrol"]:
		if not bool(pose.get("handover" if who == "tow" else "patrol_handover", false)) or entry.has("handed_" + who):
			continue
		entry["handed_" + who] = true
		var v: Variant = sc.get(who)
		if v == null or not is_instance_valid(v) or not _owned(v):
			continue
		var car := v as Vehicle
		var last: Dictionary = entry.get("last_" + who, {})
		if last.is_empty():
			continue
		if who == "tow":
			var load: Variant = sc.get("car")
			if load != null and is_instance_valid(load) and _owned(load):
				(load as Vehicle).traffic = {"towed": true}
				(load as Node).reparent(car)
		var width := float(fw.routes[int(inc.ri)].width)
		var li := Freeway.LANES - 1
		car.traffic = {"fw": int(inc.ri), "t": float(last.t), "dir": int(inc.dir), "lane": Freeway.lane_fraction(width, li) * float(inc.dir),
			"li": li, "speed": float(last.v), "v": float(last.v), "half": TrafficManager.car_half_length(car), "rear": TrafficManager.car_rear_length(car)}
		TrafficAI.fw_setup(car, fw, true)
		car.traffic.erase("placed")
		car.traffic.erase("exit")
		car.traffic.home = li
		car.traffic_speed = float(last.v)
		if car is FreewayPatrol:
			(car as FreewayPatrol).lights_on = false
		tm.freeway_cars.append(car)
		count("handover_" + who)


func _halves(sc: Dictionary) -> Array:
	var out := []
	for k in ["car", "patrol", "tow"]:
		var v: Variant = sc.get(k)
		out.append(TrafficManager.car_half_length(v) if v != null and is_instance_valid(v) else 2.4)
	return out


func _add_block(key: Vector2i, b: Dictionary) -> void:
	if not _blocks.has(key):
		_blocks[key] = []
	(_blocks[key] as Array).append(b)


func _add_zone(key: Vector2i, z: Dictionary) -> void:
	if not _zones.has(key):
		_zones[key] = []
	(_zones[key] as Array).append(z)


## Puts everything of an incident where the clock says it is.
func _place_scene(fw: Freeway, entry: Dictionary) -> void:
	var inc: Dictionary = entry.inc
	var sc: Dictionary = entry.scene
	if sc.is_empty():
		return
	var ri := int(inc.ri)
	var dir := int(inc.dir)
	var t := float(inc.t)
	var root: Variant = sc.get("debris")
	if root != null and is_instance_valid(root):
		var li := int(inc.li)
		var lat := lane_lat(fw, ri, li, dir)
		for mi in (root as Node3D).get_children():
			var off: Vector3 = mi.get_meta("off")
			(mi as Node3D).global_transform = xform_at(fw, ri, t + off.z * float(dir), lat + off.x * float(dir), dir, 0.0, float(mi.get_meta("yaw")))
	if int(inc.kind) != Kind.STALL:
		return
	var pose: Dictionary = entry.get("pose", stall_pose(inc, clock - float(inc.start), _halves(sc)))
	var slow := Freeway.LANES - 1
	var lane_l := lane_lat(fw, ri, slow, dir)
	var shoulder_l := shoulder_lat(fw, ri, dir)
	var tow: Variant = sc.get("tow")
	var bed: ServiceVehicles.TowBed = null
	if tow != null and is_instance_valid(tow) and _owned(tow):
		bed = ServiceVehicles.gear_of(tow) as ServiceVehicles.TowBed
	for who in ["patrol", "tow", "car"]:
		var v: Variant = sc.get(who)
		if v == null or not is_instance_valid(v) or not _owned(v):
			continue
		var car := v as Vehicle
		if not pose.has(who):
			car.visible = false
			car.collision_layer = 0
			continue
		var p: Array = pose[who]
		var s := float(p[0])
		var k := float(p[1])
		var lat := lerpf(lane_l, shoulder_l, k)
		# Nosed toward the shoulder (on the driver's right) coming in, away from it going out.
		var way := int(p[3])
		var yaw := 0.0
		if k > 0.0 and k < 1.0 and float(p[2]) > 1.0:
			yaw = -0.06 * float(way)
		var xf := xform_at(fw, ri, t + s * float(dir), lat, dir, car.road_lift(), yaw)
		if who == "car" and bool(pose.get("loaded", false)) and bed != null:
			# Winched up the bed: from where it stood to the bed's foot, then up to its home.
			var u := float(pose.get("winch", 0.0))
			var lift := Transform3D(Basis(), Vector3(0.0, car.road_lift(), 0.0))
			var foot: Transform3D = bed.deck(3.2) * lift
			var home: Transform3D = bed.deck(0.0) * lift
			if u < 0.45:
				var a := ServiceVehicles._ease(u / 0.45)
				xf = Transform3D(xf.basis.orthonormalized().slerp(foot.basis.orthonormalized(), a), xf.origin.lerp(foot.origin, a))
			else:
				xf = foot.interpolate_with(home, ServiceVehicles._ease((u - 0.45) / 0.55))
			if not entry.get("counted_load", false) and u >= 1.0:
				entry.counted_load = true
				count("tow_loaded")
		car.global_transform = xf
		car.visible = true
		entry["last_" + who] = {"t": t + s * float(dir), "v": float(p[2])}
		car.collision_layer = 4 if not (who == "car" and bool(pose.get("loaded", false))) else 0
		car.traffic_speed = maxf(float(p[2]), 0.31 if who == "car" else 0.0)
		# Indicators: toward the shoulder coming in, away from it going out.
		var sig := 0
		if k > 0.02 and k < 0.98 and way != 0:
			sig = way
		car.traffic.sig = sig
		car.traffic.hazard = who == "car" and s >= -0.5
		if who == "patrol":
			(car as FreewayPatrol).lights_on = bool(pose.get("patrol_lights", false))
		if who == "tow" and bed != null:
			bed.pose(float(pose.get("bed", 0.0)))
			if bed.winch:
				var winching := float(pose.get("winch", 0.0)) > 0.0 and float(pose.get("winch", 0.0)) < 1.0
				if winching and not bed.winch.playing:
					bed.winch.play()
				elif not winching and bed.winch.playing:
					bed.winch.stop()
	_place_driver(fw, entry, pose, shoulder_l)


## The driver: out behind the car by the barrier, on the phone, while the car stands there.
func _place_driver(fw: Freeway, entry: Dictionary, pose: Dictionary, shoulder_l: float) -> void:
	var inc: Dictionary = entry.inc
	var sc: Dictionary = entry.scene
	var want := bool(pose.get("driver", false))
	var d: Variant = sc.get("driver")
	if want and (d == null or not is_instance_valid(d)):
		if d != null:
			return
		var ri := int(inc.ri)
		var dir := int(inc.dir)
		var half := float(_halves(sc)[0])
		var lo := lay(fw, ri)
		var lat := (float(lo.outer) - 0.45) * float(dir)
		var tt := float(inc.t) - (half + 1.6) * float(dir)
		var wp := deck_point(fw, ri, tt, lat)
		var m := FreewayMotorist.new()
		var at: Array = fw.point_at(ri, tt)
		var hd: Vector2 = at[1]
		# Facing back down the road, the way the help will come, a little out toward the lanes.
		var yaw := atan2(-hd.x * float(dir), -hd.y * float(dir)) + 0.5 * float(dir)
		m.setup_motorist(Vector2(wp.x, wp.z), yaw, wp.y + 0.05, int(inc.seed))
		var local := global_transform.affine_inverse() * WorldState.to_local(wp)
		m.position = local + Vector3(0.0, 0.05, 0.0)
		# Its parent's space must be true world space for a Pedestrian (its ring is): ours is
		# the traffic node's, which the streamer shifts with every chunk.
		m.home = Vector2(local.x, local.z)
		m.deck_y = local.y + 0.05
		add_child(m)
		sc.driver = m
		count("built_driver")
	elif not want and d != null and is_instance_valid(d) and not (d as Pedestrian)._down:
		(d as Node).queue_free()
		sc.driver = null


# --- Driving (TrafficManager._drive_freeway's hook) -----------------------------------------------------

## The speed freeway car `car` may do this tick past the incidents on its carriageway, given the
## `speed` its own following left it; starts a lane change out of a blocked lane when there is room
## (TrafficAI's groups), else it slows or stops short. Suppresses TrafficAI's own lane thinking
## near a block, so its keep-right never steers a car back into one.
static func drive(tm: TrafficManager, fw: Freeway, car: Vehicle, speed: float, groups: Dictionary, delta: float) -> float:
	var n := current
	if n == null or not enabled:
		return speed
	var tt: Dictionary = car.traffic
	var key := Vector2i(int(tt.fw), int(tt.dir))
	var blocks: Array = n._blocks.get(key, [])
	var zones: Array = n._zones.get(key, [])
	if blocks.is_empty() and zones.is_empty():
		return speed
	var dir := int(tt.dir)
	var at := float(tt.t)
	var li := TrafficAI.fw_lane(fw, tt)
	var src := int(tt.get("lc_src", li))
	var half := float(tt.get("half", 2.4))
	var cruise := float(tt.speed)
	var lim := speed
	var hold_ai := false
	for z: Dictionary in zones:
		if not (int(z.lanes) & (1 << li)):
			continue
		var cap := float(z.cap)
		if bool(z.wave):
			var ph := (at * float(dir)) / 170.0 + clock / 26.0
			cap = lerpf(SLOW_MIN, SLOW_MAX, 0.5 + 0.5 * sin(ph * TAU))
		var into := 0.0
		var near := float(z.a) if dir > 0 else float(z.b)
		var far := float(z.b) if dir > 0 else float(z.a)
		var d_in := (at - near) * float(dir)
		var d_out := (far - at) * float(dir)
		if d_in >= 0.0 and d_out >= 0.0:
			into = 1.0
		elif d_in < 0.0 and d_in > -150.0:
			into = 1.0 + d_in / 150.0
		elif d_out < 0.0 and d_out > -60.0:
			into = 1.0 + d_out / 60.0
		if into > 0.0:
			lim = minf(lim, cruise * lerpf(1.0, cap, into))
	for b: Dictionary in blocks:
		var mine := (int(b.lanes) & (1 << li)) != 0
		var was := (int(b.lanes) & (1 << src)) != 0 and src != li
		if not mine and not was:
			continue
		var near := float(b.a) if dir > 0 else float(b.b)
		var far := float(b.b) if dir > 0 else float(b.a)
		var d := (near - at) * float(dir) - half
		var past := (at - far) * float(dir) - half
		if past > 0.0 or d > 300.0:
			continue
		hold_ai = true
		if bool(b.hard):
			if d > -0.5:
				lim = minf(lim, maxf(0.0, (d - 4.0) * 1.1) + float(b.v))
			else:
				# Alongside it (spawned there, or it pulled in beside): keep its pace.
				lim = minf(lim, float(b.v))
		else:
			var cap := cruise * float(b.cap)
			lim = minf(lim, lerpf(cap, cruise, clampf(d / 160.0, 0.0, 1.0)) if d > 0.0 else cap)
		if mine and d < 240.0 and not tt.has("lc_from") and TrafficAI.enabled:
			_swerve(tm, fw, car, li, n, key, groups, at)
	if hold_ai and tt.has("li"):
		tt.lc_next = maxf(float(tt.get("lc_next", 0.0)), TrafficAI.FW_THINK_SECONDS)
		# An exit can wait for the next ramp: it would only steer it back into the block.
		if tt.has("exit"):
			tt.erase("exit")
	if lim < speed - 0.5 and lim < 0.5:
		if not tt.get("fwi_stopped", false):
			tt.fwi_stopped = true
			count("stop")
	elif tt.get("fwi_stopped", false):
		tt.erase("fwi_stopped")
	return lim


static func _blocked(n: FreewayIncidents, key: Vector2i, lane: int, at: float, dir: int, reach: float) -> bool:
	for b: Dictionary in n._blocks.get(key, []):
		if not (int(b.lanes) & (1 << lane)):
			continue
		var near := float(b.a) if dir > 0 else float(b.b)
		var far := float(b.b) if dir > 0 else float(b.a)
		if (near - at) * float(dir) < reach and (at - far) * float(dir) < 6.0:
			return true
	return false


## Into the lane beside, away from the shoulder first, if it is clear of blocks and has a gap.
static func _swerve(tm: TrafficManager, fw: Freeway, car: Vehicle, li: int, n: FreewayIncidents, key: Vector2i, groups: Dictionary, at: float) -> void:
	var tt: Dictionary = car.traffic
	var dir := int(tt.dir)
	var v := float(tt.get("v", tt.speed))
	for want in [li - 1, li + 1]:
		if want < 0 or want >= Freeway.LANES:
			continue
		if _blocked(n, key, want, at, dir, 260.0):
			continue
		if not TrafficAI.fw_gap_ok(tm, groups, Vector3(float(tt.fw), float(dir), float(want)), car, at, dir, v):
			continue
		var width := float(fw.routes[int(tt.fw)].width)
		tt.lc_from = float(tt.lane)
		tt.lc_to = Freeway.lane_fraction(width, want) * float(dir)
		tt.lc_p = 0.0
		tt.lc_dur = SWERVE_SECONDS
		tt.lc_src = li
		tt.li = want
		tt.lane = tt.lc_to
		tt.sig = 1 if want > li else -1
		count("swerve")
		TrafficAI.count("fw_incident")
		return


## A lane for a freeway car spawned at route metres `t` heading `dir` (TrafficManager's spawns):
## `li` unless a block covers it near there, then the nearest lane that is clear.
static func spawn_lane(ri: int, t: float, dir: int, li: int) -> int:
	var n := current
	if n == null or not enabled:
		return li
	var key := Vector2i(ri, dir)
	if not _blocked(n, key, li, t - 80.0 * float(dir), dir, 160.0):
		return li
	for k in [1, -1, 2, -2, 3, -3]:
		var w: int = li + k
		if w >= 0 and w < Freeway.LANES and not _blocked(n, key, w, t - 80.0 * float(dir), dir, 160.0):
			count("spawn_moved")
			return w
	return li


# --- Changeable message signs -------------------------------------------------------------------------

## Whether the gantry at segment `idx` of route `ri` carries a CMS on side `side` (the
## carriageway driving `side`): pure, a hash. FreewayKit asks it and builds the cabinet.
static func has_cms(seed: int, ri: int, idx: int, side: float) -> bool:
	if not enabled:
		return false
	return h01([seed, ri, idx, int(side), "fwi_cms"]) < CMS_SHARE


## The board B frame on a gantry (FreewayKit._gantry / _sign_pair), scene space, for the
## carriageway on `side`: the CMS cabinet's frame.
static func cms_frame(fw: Freeway, ri: int, idx: int, side: float) -> Transform3D:
	var route: Dictionary = fw.routes[ri]
	var pts: PackedVector2Array = route.points
	var a: Vector2 = pts[idx]
	var b: Vector2 = pts[mini(idx + 1, pts.size() - 1)]
	var dir := (b - a).normalized()
	var nrm := Vector2(-dir.y, dir.x)
	var d3 := Vector3(dir.x, 0.0, dir.y)
	var n3 := Vector3(nrm.x, 0.0, nrm.y)
	var a3 := Vector3(a.x, float((route.heights as PackedFloat32Array)[idx]), a.y)
	var lo := Freeway.lane_layout(float(route.width))
	var face3 := -d3 * side
	var right := n3 * side
	var face_at := a3 + face3 * (FreewayKit.GANTRY_DEPTH * 0.5 + 0.12)
	var ub := float(lo.inner) + float(lo.lane) * 3.0
	var origin := face_at + right * ub + Vector3(0.0, FreewayKit.SIGN_BOTTOM, 0.0)
	return Transform3D(Basis(right, Vector3.UP, face3), origin)


static func cms_width(fw: Freeway, ri: int) -> float:
	var lo := lay(fw, ri)
	return minf(float(lo.lane) * 2.0 - 0.3, 6.4)


## What the CMS on gantry `idx` of route `ri`, carriageway `side`, says now: [page a, page b].
func cms_message(fw: Freeway, ri: int, idx: int, side: int) -> Array:
	var at := float(fw._runs[ri][idx])
	var best := {}
	var best_d := INF
	for inc: Dictionary in running(fw, plan.seed, ri, at - CMS_LOOK, at + CMS_LOOK, clock):
		if int(inc.dir) != side:
			continue
		var d := (float(inc.t) - at) * float(side)
		if d < 150.0 or d > CMS_LOOK or d >= best_d:
			continue
		best_d = d
		best = inc
	if not best.is_empty():
		var miles := best_d / 1609.0
		var dist := "%d MILES AHEAD" % roundi(miles) if miles >= 1.5 else ("1 MILE AHEAD" if miles >= 0.75 else "AHEAD")
		match int(best.kind):
			Kind.STALL:
				return [["STALLED VEHICLE", "RIGHT SHOULDER", dist], ["MOVE OVER", "OR SLOW DOWN", ""]]
			Kind.TYRE:
				return [["DEBRIS ON ROADWAY", "LANE %d" % (int(best.li) + 1), dist], ["USE CAUTION", "", ""]]
			Kind.MATTRESS:
				return [["OBJECT IN ROAD", "LANE %d BLOCKED" % (int(best.li) + 1), dist], ["USE CAUTION", "SECURE YOUR LOAD", ""]]
			Kind.SLOW:
				return [["SLOW TRAFFIC", dist, ""], ["EXPECT DELAYS", "", ""]]
	# Nothing ahead: travel times to two of the carriageway's destinations, or a safety message.
	var h := absi(hash([plan.seed, ri, idx, side, int(clock / 900.0), "fwi_psa"]))
	if h % 3 != 0:
		var dests := FreewayKit.DESTINATIONS
		var fits := []
		for d: String in dests:
			if d.length() <= FreewayIncidentKit.CMS_CHARS - 7:
				fits.append(d)
		var d1: String = fits[h % fits.size()]
		var d2: String = fits[(h / 7) % fits.size()]
		if d2 == d1:
			d2 = fits[(h / 7 + 1) % fits.size()]
		var m1 := 4 + (h / 13) % 9
		var m2 := m1 + 5 + (h / 17) % 12
		return [[_fit(d1.to_upper(), m1), _fit(d2.to_upper(), m2), ""], []]
	var psa := [
		[["BUCKLE UP", "EVERY TRIP", "EVERY TIME"], []],
		[["LOOK TWICE", "FOR", "MOTORCYCLES"], []],
		[["PHONE DOWN", "EYES ON", "THE ROAD"], []],
		[["REPORT DRUNK", "DRIVERS", "CALL 911"], []],
		[["CHECK YOUR TIRES", "BEFORE", "LONG TRIPS"], []],
		[["SLOW DOWN", "SAVE A LIFE", ""], []],
	]
	return psa[(h / 3) % psa.size()]


static func _fit(dest: String, minutes: int) -> String:
	var tail := " %d MIN" % minutes
	var room := FreewayIncidentKit.CMS_CHARS - tail.length()
	if dest.length() > room:
		dest = dest.substr(0, room).strip_edges()
	return dest + tail


## The CMS faces near the player: built for every CMS gantry within CMS_REACH, messages refreshed.
func _update_cms(fw: Freeway) -> void:
	var pw := WorldState.to_world(_player.global_position)
	var here := Vector2(pw.x, pw.z)
	var seen := {}
	var every := int(round(Freeway.GANTRY_SPACING / Freeway.STEP))
	for ri in fw.routes.size():
		var near: Array = fw.nearest_on(ri, here)
		if float(near[1]) > CMS_REACH:
			continue
		var pts: PackedVector2Array = fw.routes[ri].points
		var i0 := maxi(0, int((float(near[0]) - CMS_REACH) / Freeway.STEP))
		var i1 := mini(pts.size() - 2, int((float(near[0]) + CMS_REACH) / Freeway.STEP) + 1)
		var idx := int(ceil(float(i0) / every)) * every
		while idx <= i1:
			if pts[idx].distance_to(here) < CMS_REACH and not _gantry_skipped(fw, ri, idx):
				for side: int in [1, -1]:
					if not has_cms(plan.seed, ri, idx, float(side)):
						continue
					if _exit_board(fw, ri, idx, float(side)):
						continue
					var k := Vector3i(ri, idx, side)
					seen[k] = true
					var msg := cms_message(fw, ri, idx, side)
					if not _cms.has(k):
						var mi := MeshInstance3D.new()
						mi.name = "CmsFace"
						mi.mesh = FreewayIncidentKit.face_mesh()
						mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
						mi.visibility_range_end = CMS_REACH + 60.0
						var mat := FreewayIncidentKit.cms_material(msg[0], msg[1])
						mi.material_override = mat
						add_child(mi)
						_cms[k] = {"mi": mi, "mat": mat, "msg": msg, "w": cms_width(fw, ri)}
						count("cms_face")
					var c: Dictionary = _cms[k]
					if c.msg != msg:
						FreewayIncidentKit.set_message(c.mat, msg[0], msg[1])
						c.msg = msg
					var frame := cms_frame(fw, ri, idx, float(side))
					frame.origin = WorldState.to_local(frame.origin)
					(c.mi as Node3D).global_transform = FreewayIncidentKit.cms_face_xform(frame, float(c.w))
			idx += every
	for k in _cms.keys():
		if not seen.has(k):
			var c: Dictionary = _cms[k]
			if is_instance_valid(c.mi):
				(c.mi as Node).queue_free()
			_cms.erase(k)


## FreewayKit skips a gantry under the four-level stack's decks.
func _gantry_skipped(fw: Freeway, ri: int, idx: int) -> bool:
	return fw.stack != null and fw.stack.covered.has(Vector2i(ri, idx))


## FreewayKit puts an exit sign where an exit is near on that side (its _next_exit()); then
## there is no CMS.
func _exit_board(fw: Freeway, ri: int, idx: int, side: float) -> bool:
	if side < 0.0:
		return false
	var best := -1
	for r: Dictionary in fw.ramps:
		if int(r.route) != ri or float(r.side) < 0.0 or int(r.index) <= idx:
			continue
		if best < 0 or int(r.index) < best:
			best = int(r.index)
	return best >= 0 and float(best - idx) * Freeway.STEP <= 1500.0
