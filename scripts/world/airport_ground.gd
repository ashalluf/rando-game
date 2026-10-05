class_name AirportGround
extends Node3D
## The airport's ground comes alive (2026-10-05, "taxiing jets, apron vehicles moving"). A child of
## AirTraffic (built in its _setup()), so it rides the origin shifts; everything it places is in
## its own frame, which is fixed to the world (AirTraffic is shifted with the city), so an idle
## truck never needs touching.
##
## THE GATES. Every stand (Airport.gates()) has a state - EMPTY, INBOUND (a landed jet is on its
## way), PARKED (a jet at the stand: the concourse's MultiMesh instance, or a live jet while the
## jet bridge docks), PUSHING (a departure backing out) - and three things drawn from it, all
## static (they must be right for copies built before this node exists, and for both the far
## and the near concourse): the parked jet's instance in every registered gate MultiMesh
## (register_gate_jets(), shown or collapsed, its livery in INSTANCE_CUSTOM.r), the stand's ground
## service set in its chunk's batch (register_gate_set(): the static trucks round a parked jet)
## and the jet bridge's extension (bridge_amount(), read by each JetBridge). A live jet and the
## instance it swaps with are the same model, transform and livery, so that swap is seamless and
## happens whenever it is due; the trucks of a gate set appear and go only while nobody is
## looking at the stand (watched(): in frustum within `watch_range`).
##
## THE JETS. A landed airliner (AmbientJet, TAXI phase) asks claim_arrival(): if a stand is free
## and its way is clear it is handed ground legs - off the runway on a lead-off into the west
## connector, across the departure runway when cleared ("cross"), up to the parallel taxiway, east
## along it and round the painted lead-in curve to the stop bar (Airport paints the same curve,
## lead_in_route()) - and docks (the bridge swings out, the engines spool down, the jet becomes the
## stand's instance). A departure (request_departure(), from AirTraffic's schedule) is the stand's
## instance turned back into a live jet: the bridge retracts, the beacons come on, the pushback
## tug backs it out onto the taxiway, disconnects, and the jet taxis east to the east connector,
## holds short of the departure runway, lines up when cleared ("lineup") and becomes an ordinary
## departure. One-way flow (runway west, taxiway east, gates, runway east) means no two jets ever
## meet head on; room_ahead() keeps them in single file and short of a flyable jet in the way.
## The runway they share has one owner at a time (_owner: a crossing arrival or a departure).
##
## THE VEHICLES (within `vehicle_range` of the player only): baggage trains (a tug and its carts,
## one MultiMesh each) looping the service road behind the tails on a schedule worked out from
## the clock, a live pushback tug per stand while its gate set is not shown, a follow-me car that
## leads each arrival from the taxiway to its stand, a fuel truck and a catering truck (its box
## rising on the scissor lift to the rear door) sent to parked jets whose static set lacks one,
## and the crash tender in its shed by the hangars.
##
## Every roll is a hash of the seed and the stand or vehicle (or the schedule's own rng): nothing
## the seed builds elsewhere moves.

enum G { EMPTY, INBOUND, PARKED, PUSHING }

@export_group("Turnaround")
## Seconds a jet stays at its stand before it may push back (a range: each stand rolls).
@export var turnaround_seconds: Vector2 = Vector2(150.0, 330.0)
## Seconds the jet bridge takes to swing out or back.
@export var bridge_seconds: float = 9.0
## Seconds the tug takes to disconnect after a pushback, and the start-up wait before it pushes.
@export var disconnect_seconds: float = 8.0
@export_group("Ground traffic")
## Most live jets on the ground at once (taxiing, pushing, docking).
@export var max_ground_jets: int = 5
## A stand counts as watched when it is in the camera's frustum within this distance (m).
@export var watch_range: float = 950.0
## A jet stopped by traffic this long is faded out (the safety valve against a deadlock).
@export var stuck_seconds: float = 75.0
@export_group("Vehicles")
## Live apron vehicles exist while the player is within this distance of the field's centre (m).
@export var vehicle_range: float = 1500.0
## Baggage trains looping the service road, their speed (m/s) and carts each.
@export var trains: int = 3
@export var train_speed: float = 6.0
@export var train_carts: int = 4
## Seconds between service missions (fuel, catering) to parked jets.
@export var mission_interval: float = 40.0

## Taxi geometry (m): the lead-off radius the paint uses between the taxiway and a connector, the
## runway exit, a stand's lead-in, the pushback turn, how far west of the lead-in the pushback ends,
## the turn onto the runway to line up.
const R_LEAD := 22.0
const R_EXIT := 30.0
const R_GATE := 25.0
const R_PUSH := 18.0
const PUSH_OUT := 46.0
const R_LINEUP := 15.0
## Sample spacing of a ground leg (m).
const LEG_STEP := 2.0
## Where the live pushback tug stands: under the nose (as in the gate set) and waiting, in the
## stand's frame (x along t, z along n from the nose).
const TUG_AT_NOSE := Vector3(0.15, 0.0, 2.2)
const TUG_WAITING := Vector3(6.0, 0.0, -1.0)
## Cart spacing in a train (m).
const CART_PITCH := 3.9

# --- Static state (shared by every copy of the concourse and each chunk's gate set) ----------

static var _for_map: int = 0
static var g_state: Array[int] = []
static var g_livery: Array[int] = []
static var g_jet_shown: Array[bool] = []
static var g_set_shown: Array[bool] = []
static var g_bridge: PackedFloat32Array = PackedFloat32Array()
static var g_bridge_to: PackedFloat32Array = PackedFloat32Array()
static var g_ready_at: PackedFloat32Array = PackedFloat32Array()
## Registered gate MultiMeshes: [node, PackedInt32Array of gate indices by instance, y0].
static var _jet_regs: Array = []
## Registered gate sets: [chunk, batch key, instance index, gate index, Transform3D].
static var _set_regs: Array = []
## The ground's own clock (s): the trains' schedule and the turnarounds run off it.
static var clock: float = 0.0


## Resets the stands for the game's map (AirportGround.setup(); a Rebuild makes a new MacroMap):
## every stand but the empty one parked, its livery and its turnaround rolled from the seed. The
## registrations stay (the far concourse registers before this runs); the freed ones are dropped.
static func ensure(macro: MacroMap) -> void:
	if macro == null:
		return
	var id := macro.get_instance_id()
	if id == _for_map and not g_state.is_empty():
		return
	_for_map = id
	clock = 0.0
	_init_state()
	for i in g_state.size():
		_apply_jet(i)
		_apply_set(i)


## The stands as at load (registration calls it too, before any AirportGround exists).
static func _init_state() -> void:
	g_state.clear()
	g_livery.clear()
	g_jet_shown.clear()
	g_set_shown.clear()
	var gs := Airport.gates()
	g_bridge.resize(gs.size())
	g_bridge_to.resize(gs.size())
	g_ready_at.resize(gs.size())
	for i in gs.size():
		var g: Dictionary = gs[i]
		var empty := bool(g.empty)
		g_state.append(G.EMPTY if empty else G.PARKED)
		g_livery.append(int(g.livery))
		g_jet_shown.append(not empty)
		# The empty stand's set is its waiting tug (AirportKit.gate_set(4)): always shown.
		g_set_shown.append(true)
		g_bridge[i] = 0.0 if empty else 1.0
		g_bridge_to[i] = g_bridge[i]
		g_ready_at[i] = float(hash([i, "ready"]) % 1000) / 1000.0 * 140.0 + 20.0


static func _ensure_state() -> void:
	if g_state.is_empty():
		_init_state()


static func gate_count() -> int:
	return g_state.size()


## How far the jet bridge of stand `i` is out to its jet's door (0 retracted, 1 docked).
static func bridge_amount(i: int) -> float:
	if i < 0 or i >= g_bridge.size():
		var gs := Airport.gates()
		return 0.0 if i >= 0 and i < gs.size() and bool(gs[i].empty) else 1.0
	return g_bridge[i]


## A concourse half's MultiMesh of parked jets: instance k is stand `gates[k]`.
static func register_gate_jets(node: MultiMeshInstance3D, gates: PackedInt32Array, y0: float, _macro: MacroMap) -> void:
	_ensure_state()
	_jet_regs.append([node, gates, y0])
	for k in gates.size():
		_apply_jet_instance(node, k, gates[k], y0)


## A stand's ground service set: instance `index` of the chunk's batch `key`.
static func register_gate_set(chunk: Node, key: String, index: int, gate: int, xform: Transform3D, _macro: MacroMap) -> void:
	_ensure_state()
	_set_regs.append([chunk, key, index, gate, xform, false])


static func _apply_jet_instance(node: MultiMeshInstance3D, k: int, gate: int, y0: float) -> void:
	if node == null or not is_instance_valid(node) or node.multimesh == null or k >= node.multimesh.instance_count:
		return
	var g: Dictionary = Airport.gates()[gate]
	var shown := gate < g_jet_shown.size() and g_jet_shown[gate]
	var xf := AirportTerminal.jet_transform(g.centre, g.yaw, y0) if shown else Transform3D(Basis().scaled(Vector3.ZERO), Vector3(0.0, -10000.0, 0.0))
	var custom := Color(float(g_livery[gate] if gate < g_livery.size() else g.livery) / 8.0, 0.0, 0.0, 1.0)
	for mm_node: MultiMeshInstance3D in _with_twin(node):
		if k < mm_node.multimesh.instance_count:
			mm_node.multimesh.set_instance_transform(k, xf)
			mm_node.multimesh.set_instance_custom_data(k, custom)


static func _with_twin(node: MultiMeshInstance3D) -> Array[MultiMeshInstance3D]:
	var out: Array[MultiMeshInstance3D] = [node]
	if node.has_meta("shadow_twin"):
		var twin := node.get_meta("shadow_twin") as MultiMeshInstance3D
		if twin and is_instance_valid(twin) and twin.multimesh:
			out.append(twin)
	return out


## Pushes stand `i`'s parked jet (shown, livery) to every registered MultiMesh.
static func _apply_jet(i: int) -> void:
	var live: Array = []
	for reg: Array in _jet_regs:
		# Checked before it is typed: assigning a freed node to a typed variable is an error.
		if not is_instance_valid(reg[0]):
			continue
		var node: MultiMeshInstance3D = reg[0]
		live.append(reg)
		var gates: PackedInt32Array = reg[1]
		for k in gates.size():
			if gates[k] == i:
				_apply_jet_instance(node, k, i, float(reg[2]))
	_jet_regs = live


## Shows or collapses stand `i`'s gate set in every chunk that built it.
static func _apply_set(i: int) -> void:
	var live: Array = []
	for reg: Array in _set_regs:
		if not is_instance_valid(reg[0]):
			continue
		var chunk: Node = reg[0]
		live.append(reg)
		if int(reg[3]) != i:
			continue
		var nodes: Variant = chunk.get("_mm_nodes")
		if not (nodes is Dictionary):
			continue
		var node := (nodes as Dictionary).get(reg[1]) as MultiMeshInstance3D
		if node == null or not is_instance_valid(node):
			continue
		var xf: Transform3D = reg[4] if g_set_shown[i] else Transform3D(Basis().scaled(Vector3.ZERO), Vector3(0.0, -10000.0, 0.0))
		for mm_node: MultiMeshInstance3D in _with_twin(node):
			if int(reg[2]) < mm_node.multimesh.instance_count:
				mm_node.multimesh.set_instance_transform(int(reg[2]), xf)
		reg[5] = true
	_set_regs = live


## Applies the stands' sets to chunks that finished building since (a chunk registers its sets as
## it lays them out, but its batch nodes appear only at its finish step).
static func _apply_new_sets() -> void:
	for reg: Array in _set_regs:
		if bool(reg[5]) or not is_instance_valid(reg[0]):
			continue
		var nodes: Variant = (reg[0] as Node).get("_mm_nodes")
		if nodes is Dictionary and (nodes as Dictionary).has(reg[1]):
			_apply_set(int(reg[3]))


# --- Layout ------------------------------------------------------------------------------------

## Where a stand's lead-in line meets the taxiway centre line (world XZ).
static func gate_corner(macro: MacroMap, g: Dictionary) -> Vector2:
	var nose: Vector2 = g.nose
	var n: Vector2 = g.n
	return nose + n * ((macro.taxiway_z - nose.y) / maxf(n.y, 0.2))


## The painted lead-in: from the taxiway centre line, round a curve of R_GATE onto the stand's
## lead-in line, to the stop (the jet's centre at the stand's centre). Airport paints this very
## route, so the jets follow the paint.
static func lead_in_route(macro: MacroMap, g: Dictionary) -> AirRoute:
	var c := gate_corner(macro, g)
	var cxw: float = Airport.CONNECTOR_XS[0]
	var sx := maxf(c.x - 50.0, cxw + R_LEAD / 0.9 + 1.0)
	return AirRoute.from_waypoints(PackedVector2Array([Vector2(sx, macro.taxiway_z), c, g.centre]), PackedFloat32Array([0.0, R_GATE, 0.0]), "lead_in", LEG_STEP, 0.9)


## The top of the field's surface at world XZ `p` (runways, taxiways and the apron differ by a
## few centimetres; Airport's ground tops).
static func surface_at(macro: MacroMap, p: Vector2) -> float:
	var hw := macro.runway_width * 0.5
	for rz: float in macro.runway_zs:
		if absf(p.y - rz) < hw:
			return Airport.RUNWAY_TOP
	for cx: float in Airport.CONNECTOR_XS:
		if absf(p.x - cx) < Airport.CONNECTOR_WIDTH * 0.5 and p.y > macro.taxiway_z:
			return Airport.CONNECTOR_TOP
	if absf(p.y - macro.taxiway_z) < macro.taxiway_width * 0.5:
		return Airport.TAXI_TOP
	return macro.tarmac_top


## A point in a stand's frame (x along t, z along n from the nose) in world XZ, and the yaw that
## faces stand direction `d` (frame XZ).
static func stand_point(g: Dictionary, local: Vector3) -> Vector2:
	return (g.nose as Vector2) + (g.t as Vector2) * local.x + (g.n as Vector2) * local.z


static func stand_yaw(g: Dictionary, d: Vector2) -> float:
	var w := (g.t as Vector2) * d.x + (g.n as Vector2) * d.y
	return atan2(-w.x, -w.y)


## A ground leg: the route, driven forward or backward (`reverse`: the jet faces against its
## motion, a pushback), its top speed, whether it ends standing, what it must be cleared for at
## its start (`tag`) and how long it waits there first.
static func leg(r: AirRoute, vmax: float, stop: bool, reverse: bool = false, tag: String = "", wait: float = 0.0) -> Dictionary:
	return {"route": r, "vmax": vmax, "stop": stop, "reverse": reverse, "tag": tag, "wait": wait, "prof": PackedFloat32Array()}


## Fills every leg's speed profile, from the last back: the turns (`turn_accel` sideways), the
## stops, and each leg ending at the speed the next one starts at.
static func profile_legs(legs: Array, turn_accel: float, brake: float) -> void:
	var next_start := 0.0
	for k in range(legs.size() - 1, -1, -1):
		var lg: Dictionary = legs[k]
		var r: AirRoute = lg.route
		var n := r.xz.size()
		var prof := PackedFloat32Array()
		prof.resize(n)
		var vmax: float = lg.vmax
		for i in n:
			var tr := absf(r.turn[i])
			prof[i] = minf(vmax, sqrt(turn_accel / tr) if tr > 1e-5 else vmax)
		var end_v := 0.0 if bool(lg.stop) or k == legs.size() - 1 else next_start
		prof[n - 1] = minf(prof[n - 1], end_v)
		for i in range(n - 2, -1, -1):
			prof[i] = minf(prof[i], sqrt(prof[i + 1] * prof[i + 1] + 2.0 * brake * (r.dist[i + 1] - r.dist[i])))
		lg.prof = prof
		next_start = prof[0]
		# A leg that waits or must be cleared starts from standing: the one before stops for it.
		if float(lg.wait) > 0.0 or String(lg.tag) != "":
			next_start = 0.0


# --- The node ---------------------------------------------------------------------------------

var air: AirTraffic
var macro: MacroMap
## Live jets on the ground (taxiing in or out, pushing, docking) and the stand each belongs to.
var _jets: Array[AmbientJet] = []
var _jet_gate: Dictionary = {}
## Which jet holds the departure runway (a crossing arrival or a departure), and which runway
## that is: 27R (macro.departure_runway).
var _owner: AmbientJet = null
## Flyable jets standing on the field (TRUE world XZ, radius), rescanned every second.
var _flyables: Array = []
var _scan_left: float = 0.0
var _watch_left: float = 0.0
var _stuck: Dictionary = {}
var _rng := RandomNumberGenerator.new()
## Gates a departure was asked of whose set must first go (when nobody is looking).
var _want_clear: Dictionary = {}
var _near: bool = false
var _vehicles: Node3D
var _tugs: Dictionary = {}
var _train_tugs: MultiMeshInstance3D
var _train_carts: MultiMeshInstance3D
var _train_route: AirRoute
var _train_plan: Array = []
var _train_period: float = 1.0
var _follow: Mover
var _follow_jet: AmbientJet = null
var _follow_mode: int = 0
var _fuel: Mover
var _catering: Mover
var _catering_box: MeshInstance3D
var _catering_lift: MeshInstance3D
var _lift_h: float = -1.0
var _mission_left: float = 15.0
var _arff: Node3D
var _sounds: Array[AudioStreamPlayer3D] = []
## Stills: freeze the clock-driven vehicles where they stand.
var hold_vehicles: bool = false


func _ready() -> void:
	add_to_group("airport_ground")
	_rng.seed = 90210


func setup(traffic: AirTraffic) -> void:
	air = traffic
	macro = traffic.macro
	ensure(macro)
	_vehicles = Node3D.new()
	_vehicles.name = "ApronVehicles"
	add_child(_vehicles)
	_build_train_route()


func _physics_process(delta: float) -> void:
	advance(delta)


## One tick: the clock, the bridges, the stands' swaps, the runway's owner, the vehicles. Tests
## call it directly to run minutes of the field in a frame (and AmbientJet.advance() for the jets).
func advance(dt: float) -> void:
	if macro == null:
		return
	clock += dt
	for i in g_bridge.size():
		if g_bridge[i] != g_bridge_to[i]:
			g_bridge[i] = move_toward(g_bridge[i], g_bridge_to[i], dt / maxf(bridge_seconds, 0.1))
	_release_owner()
	_scan_left -= dt
	if _scan_left <= 0.0:
		_scan_left = 1.0
		_scan_flyables()
	_watch_left -= dt
	if _watch_left <= 0.0:
		_watch_left = 0.5
		_tend_stands()
	_tend_jets(dt)
	_tend_vehicles(dt)


# --- Arrivals ---------------------------------------------------------------------------------

## A landed jet rolling out at taxi speed on the arrival runway: a free stand and a clear way give
## it ground legs to the stand (true); otherwise it rolls on to the runway end as before (false).
func claim_arrival(jet: AmbientJet) -> bool:
	if jet.kind != Aircraft.Kind.AIRLINER or _live_count() >= max_ground_jets:
		return false
	var cxw: float = Airport.CONNECTOR_XS[0]
	var here := Vector2(jet.world_pos.x, jet.world_pos.z)
	# Room for the turn off the runway (the exit's arc takes R_EXIT before the connector).
	if here.x < cxw + R_EXIT / 0.9 + 4.0:
		return false
	var free: Array[int] = []
	for i in g_state.size():
		if g_state[i] == G.EMPTY and not g_jet_shown[i]:
			free.append(i)
	if free.is_empty():
		return false
	var gi: int = free[jet._rng.randi() % free.size()]
	var legs := arrival_legs(here, gi, jet)
	if not _way_clear(legs):
		return false
	g_state[gi] = G.INBOUND
	g_livery[gi] = jet.livery if jet.livery >= 0 else g_livery[gi]
	_adopt(jet, gi)
	jet.engine_level = 0.3
	jet.start_ground(legs, _on_arrived)
	return true


## The arrival's legs from `here` (on the arrival runway, heading west) to stand `gi`: off the
## runway into the west connector, up to the hold short of the departure runway, across it when
## cleared, up to the taxiway and east along it, and in round the lead-in.
func arrival_legs(here: Vector2, gi: int, jet: AmbientJet) -> Array:
	var g: Dictionary = Airport.gates()[gi]
	var hw := macro.runway_width * 0.5
	var rz_dep: float = macro.runway_zs[macro.departure_runway]
	var rz_arr: float = macro.runway_zs[macro.arrival_runway]
	var cxw: float = Airport.CONNECTOR_XS[0]
	var tz := macro.taxiway_z
	var z_cross := rz_dep + hw + 3.5 + jet.length * 0.5
	var lead := lead_in_route(macro, g)
	var sx: float = lead.xz[0].x
	var a1 := AirRoute.from_waypoints(PackedVector2Array([here, Vector2(cxw, rz_arr), Vector2(cxw, z_cross)]), PackedFloat32Array([0.0, R_EXIT, 0.0]), "exit", LEG_STEP, 0.9)
	var a2 := AirRoute.from_waypoints(PackedVector2Array([Vector2(cxw, z_cross), Vector2(cxw, tz), Vector2(sx, tz)]), PackedFloat32Array([0.0, R_LEAD, 0.0]), "cross", LEG_STEP, 0.9)
	var legs := [
		leg(a1, maxf(jet.ground_speed, jet.speed), false),
		leg(a2, jet.ground_speed, false, false, "cross"),
		leg(lead, jet.ground_speed, true),
	]
	profile_legs(legs, jet.turn_accel, jet.ground_brake)
	return legs


func _on_arrived(jet: AmbientJet) -> void:
	var gi: int = _jet_gate.get(jet, -1)
	jet.park()
	if gi < 0:
		return
	g_state[gi] = G.PARKED
	g_set_shown[gi] = bool(Airport.gates()[gi].empty)
	_apply_set(gi)
	g_bridge_to[gi] = 1.0
	g_ready_at[gi] = clock + bridge_seconds + _rng.randf_range(turnaround_seconds.x, turnaround_seconds.y)
	jet.set_meta("dock_at", clock + bridge_seconds + 1.0)


# --- Departures -------------------------------------------------------------------------------

## A departure from a stand whose turnaround is done (true: a jet is pushing back). A stand whose
## trucks are still drawn round it is asked to clear them first (done when nobody looks), so it
## may take a few calls.
func request_departure() -> bool:
	if _live_count() >= max_ground_jets:
		return false
	var best := -1
	var best_ready := INF
	for i in g_state.size():
		if g_state[i] != G.PARKED or g_ready_at[i] > clock or g_bridge[i] < 0.999:
			continue
		if not _push_clear(i):
			continue
		if g_set_shown[i] and not bool(Airport.gates()[i].empty):
			_want_clear[i] = true
			continue
		if not _tug_ready(i):
			continue
		if g_ready_at[i] < best_ready:
			best_ready = g_ready_at[i]
			best = i
	if best < 0:
		return false
	push_back(best)
	return true


## Turns stand `gi`'s parked jet into a live one and starts its pushback.
func push_back(gi: int) -> AmbientJet:
	var g: Dictionary = Airport.gates()[gi]
	var jet: AmbientJet = null
	for j in _jets:
		if _jet_gate.get(j, -1) == gi and is_instance_valid(j):
			jet = j
	if jet == null:
		var c: Vector2 = g.centre
		jet = air.spawn_ground_jet(Aircraft.Kind.AIRLINER, g_livery[gi], Vector3(c.x, macro.tarmac_top, c.y), float(g.yaw))
		_adopt(jet, gi)
	g_state[gi] = G.PUSHING
	g_jet_shown[gi] = false
	_apply_jet(gi)
	g_bridge_to[gi] = 0.0
	jet.engine_level = 0.05
	var legs := departure_legs(gi, jet)
	jet.start_ground(legs, _on_lined_up)
	jet.set_ground_lights(true, false)
	jet.set_meta("push_started", clock)
	jet.set_meta("tug_gate", gi)
	return jet


## A departure's legs from stand `gi`: back out round the lead-in onto the taxiway (the tug
## pushing, after the bridge is in), wait while the tug disconnects, taxi east to the east
## connector and down it to the hold short, then line up when cleared.
func departure_legs(gi: int, jet: AmbientJet) -> Array:
	var g: Dictionary = Airport.gates()[gi]
	var hw := macro.runway_width * 0.5
	var rz_dep: float = macro.runway_zs[macro.departure_runway]
	var cxe: float = Airport.CONNECTOR_XS[Airport.CONNECTOR_XS.size() - 1]
	var tz := macro.taxiway_z
	var c := gate_corner(macro, g)
	var out := c - Vector2(PUSH_OUT, 0.0)
	var z_hold := rz_dep - hw - 21.0 - jet.length * 0.5
	var start: Vector2 = air.departure_start()
	var p1 := AirRoute.from_waypoints(PackedVector2Array([g.centre, c, out]), PackedFloat32Array([0.0, R_PUSH, 0.0]), "push", LEG_STEP, 0.9)
	var t1 := AirRoute.from_waypoints(PackedVector2Array([out, Vector2(cxe, tz), Vector2(cxe, z_hold)]), PackedFloat32Array([0.0, R_LEAD, 0.0]), "taxi_out", LEG_STEP, 0.9)
	var t2 := AirRoute.from_waypoints(PackedVector2Array([Vector2(cxe, z_hold), Vector2(cxe, rz_dep), start]), PackedFloat32Array([0.0, R_LINEUP, 0.0]), "lineup", LEG_STEP, 0.9)
	var legs := [
		leg(p1, jet.push_speed, true, true, "", bridge_seconds + 4.0),
		leg(t1, jet.ground_speed, true, false, "", disconnect_seconds),
		leg(t2, jet.ground_speed * 0.6, true, false, "lineup", 3.0),
	]
	profile_legs(legs, jet.turn_accel, jet.ground_brake)
	return legs


func _on_lined_up(jet: AmbientJet) -> void:
	_release_jet(jet)
	# From here it is an ordinary departure: its route starts where the line-up ended.
	jet.plan = AmbientJet.Plan.DEPARTURE
	jet.route = air.routes["departure_%d_%s" % [jet.kind, "left" if jet._rng.randf() < 0.5 else "right"]]
	jet.d = 0.0
	jet.speed = 0.0
	jet.phase = AmbientJet.Phase.LINEUP
	jet._hold_left = jet.hold_seconds
	jet.engine_level = 0.3


# --- Clearances -------------------------------------------------------------------------------

## Whether `jet` may start the leg tagged `tag` now ("cross": over the departure runway;
## "lineup": onto it). Granting makes it the runway's owner.
func may_enter(jet: AmbientJet, tag: String) -> bool:
	match tag:
		"cross", "lineup":
			if _owner != null and _owner != jet:
				return false
			if _departure_rolling(jet):
				return false
			_owner = jet
			return true
	return true


## True when the departure runway belongs to somebody other than `jet` (a lined-up departure that
## AirTraffic faded in waits on it).
func runway_held_for(jet: AmbientJet) -> bool:
	return _owner != null and _owner != jet


## A departure is on the runway (lined up, rolling, or still low over it) other than `except`.
func _departure_rolling(except: AmbientJet) -> bool:
	if air == null:
		return false
	for c in air.crafts():
		var j := c as AmbientJet
		if j == null or j == except or j.plan != AmbientJet.Plan.DEPARTURE:
			continue
		if j.phase == AmbientJet.Phase.LINEUP or j.phase == AmbientJet.Phase.ROLL:
			return true
		if j.phase == AmbientJet.Phase.AIRBORNE and j.d < float(j.route.marks.get("liftoff", 0.0)) + 350.0:
			return true
	return false


func _release_owner() -> void:
	if _owner == null:
		return
	if not is_instance_valid(_owner) or _owner.done or _owner.life != AmbientCraft.Life.FLYING:
		_owner = null
		return
	var rz_dep: float = macro.runway_zs[macro.departure_runway]
	var hw := macro.runway_width * 0.5
	if _owner.phase == AmbientJet.Phase.GROUND:
		var lg := _owner.ground_leg_data()
		# A crossing arrival lets go once its tail is clear of the runway's north edge.
		if String(lg.get("tag", "")) == "cross" and _owner.d > 0.0 and _owner.world_pos.z < rz_dep - hw - _owner.length * 0.5 - 3.0:
			_owner = null
		elif String(lg.get("tag", "")) != "cross" and String(lg.get("tag", "")) != "lineup":
			_owner = null
	elif _owner.plan == AmbientJet.Plan.DEPARTURE and _owner.phase == AmbientJet.Phase.AIRBORNE and _owner.d > float(_owner.route.marks.get("liftoff", 0.0)) + 350.0:
		_owner = null


## Whether AirTraffic may fade a departure in at the line-up point now.
func lineup_free() -> bool:
	if _owner != null:
		return false
	for j in _jets:
		if is_instance_valid(j) and String(j.ground_leg_data().get("tag", "")) == "lineup" and j.d > 0.0:
			return false
	return true


## Free distance ahead of `jet` along its legs before it would close on another jet, a flyable
## jet standing on the field, or a leg it is not yet cleared into (m; INF when clear).
func room_ahead(jet: AmbientJet) -> float:
	var legs := jet.ground_legs
	var li := jet.ground_leg
	if li >= legs.size():
		return INF
	var room := INF
	var lg: Dictionary = legs[li]
	var r: AirRoute = lg.route
	# The next leg must be cleared before the jet is on it.
	if li + 1 < legs.size():
		var nxt: Dictionary = legs[li + 1]
		var tag: String = nxt.get("tag", "")
		if tag != "" and _clearance_blocked(jet, tag):
			room = r.length - jet.d
	var mine := jet.length * 0.5 + 3.0
	var s := jet.d
	var k := li
	var ahead := 0.0
	var step := 8.0
	while ahead < 80.0:
		s += step
		ahead += step
		var cur: Dictionary = legs[k]
		var cr: AirRoute = cur.route
		if s > cr.length:
			if bool(cur.stop) or k + 1 >= legs.size():
				break
			s -= cr.length
			k += 1
			cr = (legs[k] as Dictionary).route
			if s > cr.length:
				break
		var q: Vector2 = cr.xz[cr.index_at(s)]
		for o in _jets:
			if o == jet or not is_instance_valid(o) or o.phase == AmbientJet.Phase.PARKED:
				continue
			var op := Vector2(o.world_pos.x, o.world_pos.z)
			if q.distance_to(op) < mine + o.length * 0.5 + 3.0:
				room = minf(room, maxf(ahead - step, 0.0))
		# A flyable jet is measured in the frame of the path: ahead of or behind the jet's own
		# length, or beside it within its half span (a circle the jet's length round every path
		# point would have stopped the departures turning into the east connector 20 m short of
		# the player's jet parked at the taxiway's end).
		var qd := cr.yaw[cr.index_at(s)]
		var dir := Vector2(-sin(qd), -cos(qd))
		for f: Array in _flyables:
			var rel: Vector2 = (f[0] as Vector2) - q
			var along := absf(rel.dot(dir))
			var across := absf(rel.x * dir.y - rel.y * dir.x)
			if along < jet.length * 0.5 + float(f[1]) and across < jet.wingspan * 0.5 + float(f[1]) * 0.6:
				room = minf(room, maxf(ahead - step, 0.0))
		if room < INF:
			break
	return room


func _clearance_blocked(jet: AmbientJet, tag: String) -> bool:
	match tag:
		"cross", "lineup":
			return (_owner != null and _owner != jet) or _departure_rolling(jet)
	return false


## Whether a whole set of legs is clear of the flyable jets standing on the field.
func _way_clear(legs: Array) -> bool:
	if _flyables.is_empty():
		return true
	for lg: Dictionary in legs:
		var r: AirRoute = lg.route
		var i := 0
		while i < r.xz.size():
			for f: Array in _flyables:
				if r.xz[i].distance_to(f[0]) < 24.0 + float(f[1]):
					return false
			i += 3
	return true


## Whether stand `gi` may push back now: nothing moving near its lead-in or coming up the
## taxiway toward it, and its way out clear of flyable jets.
func _push_clear(gi: int) -> bool:
	var g: Dictionary = Airport.gates()[gi]
	var c := gate_corner(macro, g)
	for j in _jets:
		if not is_instance_valid(j) or j.phase == AmbientJet.Phase.PARKED:
			continue
		var p := Vector2(j.world_pos.x, j.world_pos.z)
		if p.distance_to(c) < 280.0 and p.x < c.x + 40.0:
			return false
		if p.distance_to(c) < 70.0:
			return false
	var out := c - Vector2(PUSH_OUT + 25.0, 0.0)
	for f: Array in _flyables:
		var fp: Vector2 = f[0]
		if Geometry2D.get_closest_point_to_segment(fp, c, out).distance_to(fp) < 24.0 + float(f[1]):
			return false
		if Geometry2D.get_closest_point_to_segment(fp, c, g.centre).distance_to(fp) < 24.0 + float(f[1]):
			return false
	return true


# --- Bookkeeping ------------------------------------------------------------------------------

func _adopt(jet: AmbientJet, gi: int) -> void:
	if not _jets.has(jet):
		_jets.append(jet)
	_jet_gate[jet] = gi
	jet.finished.connect(_on_jet_finished, CONNECT_ONE_SHOT)


func _release_jet(jet: AmbientJet) -> void:
	_jets.erase(jet)
	_jet_gate.erase(jet)
	_stuck.erase(jet)


func _on_jet_finished(jet: AmbientCraft) -> void:
	var gi: int = _jet_gate.get(jet, -1)
	_release_jet(jet as AmbientJet)
	if gi >= 0 and (g_state[gi] == G.INBOUND or (g_state[gi] == G.PARKED and not g_jet_shown[gi])):
		# Gone before it docked (shot down, faded out stuck): the stand is free again.
		g_state[gi] = G.EMPTY
		g_bridge_to[gi] = 0.0


func _live_count() -> int:
	var n := 0
	for j in _jets:
		if is_instance_valid(j) and not j.done:
			n += 1
	return n


## Live ground jets (tests, stills).
func ground_jets() -> Array[AmbientJet]:
	var out: Array[AmbientJet] = []
	for j in _jets:
		if is_instance_valid(j) and not j.done:
			out.append(j)
	return out


func gate_of(jet: AmbientJet) -> int:
	return _jet_gate.get(jet, -1)


func _tend_jets(dt: float) -> void:
	for j: AmbientJet in _jets.duplicate():
		if not is_instance_valid(j) or j.done:
			_release_jet(j)
			continue
		var gi: int = _jet_gate.get(j, -1)
		match j.phase:
			AmbientJet.Phase.PARKED:
				# Docked: once the bridge is on, the jet becomes the stand's instance.
				if gi >= 0 and j.has_meta("dock_at") and clock >= float(j.get_meta("dock_at")) and g_state[gi] == G.PARKED:
					g_jet_shown[gi] = true
					g_livery[gi] = j.livery
					_apply_jet(gi)
					_release_jet(j)
					j.remove()
					continue
			AmbientJet.Phase.GROUND:
				var lg := j.ground_leg_data()
				if bool(lg.get("reverse", false)):
					# Engines start during the push.
					j.engine_level = move_toward(j.engine_level, 0.3, dt / 30.0)
				else:
					j.engine_level = maxf(j.engine_level, 0.3)
				if gi >= 0 and g_state[gi] == G.PUSHING and lg.get("route") and (lg.route as AirRoute).name == "taxi_out":
					# Off the stand and the tug gone: free for the next arrival.
					g_state[gi] = G.EMPTY
					_jet_gate[j] = -1
				# The safety valve: a jet held by traffic for ever fades out.
				if j.speed < 0.05 and j.ground_wait <= 0.0:
					_stuck[j] = float(_stuck.get(j, 0.0)) + dt
					if float(_stuck[j]) > stuck_seconds and not j.fading_out:
						j.fading_out = true
				else:
					_stuck.erase(j)


## Every half second: the gate sets that may change (nobody looking), the trucks' tug at a stand.
func _tend_stands() -> void:
	_apply_new_sets()
	for i in g_state.size():
		var g: Dictionary = Airport.gates()[i]
		if bool(g.empty):
			continue
		var want_shown := g_state[i] == G.PARKED and g_jet_shown[i] and not _want_clear.has(i) and g_bridge[i] > 0.999
		if want_shown != g_set_shown[i] and not watched(g.centre):
			g_set_shown[i] = want_shown
			_want_clear.erase(i)
			_apply_set(i)


## Whether world XZ `p` is in the camera's view within `watch_range` (anything there changing
## would be seen).
func watched(p: Vector2) -> bool:
	var vp := get_viewport()
	var cam := vp.get_camera_3d() if vp else null
	if cam == null:
		return false
	var at := WorldState.to_local(Vector3(p.x, macro.tarmac_top + 3.0, p.y))
	if cam.global_position.distance_to(at) > watch_range:
		return false
	for o: Vector3 in [Vector3.ZERO, Vector3(22.0, 0.0, 0.0), Vector3(-22.0, 0.0, 0.0), Vector3(0.0, 0.0, 22.0), Vector3(0.0, 0.0, -22.0)]:
		if cam.is_position_in_frustum(at + o):
			return true
	return false


## The flyable jets (Aircraft, the player's) standing on the field: obstacles the ground traffic
## keeps clear of, and never pushed by it (a collision exception with every live jet).
func _scan_flyables() -> void:
	_flyables.clear()
	if air == null or air._player == null:
		return
	var pw := air.player_world()
	var centre := macro.airport_rect.get_center()
	if Vector2(pw.x, pw.z).distance_to(centre) > 2500.0:
		return
	var rect := macro.airport_rect.grow(30.0)
	for n in get_tree().get_nodes_in_group("vehicle"):
		var a := n as Aircraft
		if a == null or not is_instance_valid(a):
			continue
		var w := WorldState.to_world(a.global_position)
		if not rect.has_point(Vector2(w.x, w.z)) or w.y > 8.0:
			continue
		_flyables.append([Vector2(w.x, w.z), 20.0 if a.kind == Aircraft.Kind.AIRLINER else 10.0])
		for j in _jets:
			if is_instance_valid(j):
				j.add_collision_exception_with(a)


## Takes every live ground jet away and puts the stands back as at load (tests, stills).
func clear() -> void:
	for j: AmbientJet in _jets.duplicate():
		if is_instance_valid(j):
			j.remove()
	_jets.clear()
	_jet_gate.clear()
	_stuck.clear()
	_want_clear.clear()
	_owner = null
	_follow_jet = null
	_follow_mode = 0
	var gs := Airport.gates()
	for i in gs.size():
		var empty := bool(gs[i].empty)
		g_state[i] = G.EMPTY if empty else G.PARKED
		g_jet_shown[i] = not empty
		g_set_shown[i] = true
		g_bridge[i] = 0.0 if empty else 1.0
		g_bridge_to[i] = g_bridge[i]
		g_ready_at[i] = clock + 30.0
		_apply_jet(i)
		_apply_set(i)


## The departure runway's owner (tests).
func runway_owner() -> AmbientJet:
	return _owner


func surface_y(p: Vector2) -> float:
	return surface_at(macro, p)


# --- Apron vehicles ---------------------------------------------------------------------------

## A vehicle that follows a program of moves and waits worked out from the clock: each step
## {route, reverse, t0, t1, len, v} or {t0, t1, pos, yaw}; pose_at(t) puts the node there.
class Mover extends RefCounted:
	var node: Node3D
	var steps: Array = []
	var home: Vector3
	var home_yaw: float = 0.0
	var moving: bool = false

	func busy(t: float) -> bool:
		return not steps.is_empty() and t < float(steps[steps.size() - 1].t1)

	func end_time() -> float:
		return float(steps[steps.size() - 1].t1) if not steps.is_empty() else 0.0

	## Appends a drive along `r` (forward, or backing along it) starting when the last step ends.
	func drive(r: AirRoute, v: float, reverse: bool = false, accel: float = 1.2) -> void:
		var t0 := end_time() if not steps.is_empty() else AirportGround.clock
		var dur := AirportGround.trap_time(r.length, v, accel)
		steps.append({"route": r, "reverse": reverse, "t0": t0, "t1": t0 + dur, "len": r.length, "v": v, "a": accel})

	## Appends a wait where the last move ended (or at `pos`/`yaw` when nothing has moved).
	func wait(seconds: float, tag: String = "") -> void:
		var t0 := end_time() if not steps.is_empty() else AirportGround.clock
		steps.append({"t0": t0, "t1": t0 + seconds, "tag": tag})

	## World pose {pos (Vector2), yaw, tag, tau} at clock `t`.
	func pose_at(t: float) -> Dictionary:
		if steps.is_empty() or t >= end_time():
			var last := _end_pose()
			last["tag"] = "home" if steps.is_empty() else ""
			return last
		for st: Dictionary in steps:
			if t < float(st.t1):
				var tau := maxf(t - float(st.t0), 0.0)
				if st.has("route"):
					var r: AirRoute = st.route
					var s := AirportGround.trap_s(float(st.len), float(st.v), float(st.a), tau)
					var smp := r.sample(s)
					return {"pos": Vector2(smp.pos.x, smp.pos.z), "yaw": float(smp.yaw) + (PI if bool(st.reverse) else 0.0), "tag": "", "tau": tau, "moving": true}
				var p := _pose_before(st)
				p["tag"] = st.get("tag", "")
				p["tau"] = tau
				p["moving"] = false
				return p
		return _end_pose()

	func _pose_before(target: Dictionary) -> Dictionary:
		var out := {"pos": Vector2(home.x, home.z), "yaw": home_yaw}
		for st: Dictionary in steps:
			if st == target:
				break
			if st.has("route"):
				var r: AirRoute = st.route
				var smp := r.sample(r.length)
				out = {"pos": Vector2(smp.pos.x, smp.pos.z), "yaw": float(smp.yaw) + (PI if bool(st.reverse) else 0.0)}
		return out

	func _end_pose() -> Dictionary:
		var p := _pose_before({})
		p["moving"] = false
		return p


## Duration of a drive of `length` at top speed `v` with `a` up and down (a trapezoid).
static func trap_time(length: float, v: float, a: float) -> float:
	if length <= 0.0:
		return 0.0
	if length < v * v / a:
		return 2.0 * sqrt(length / a)
	return length / v + v / a


## Distance covered `tau` seconds into that drive.
static func trap_s(length: float, v: float, a: float, tau: float) -> float:
	var total := trap_time(length, v, a)
	if tau >= total:
		return length
	var vp := minf(v, sqrt(length * a))
	var ta := vp / a
	if tau < ta:
		return 0.5 * a * tau * tau
	var tc := total - 2.0 * ta
	if tau < ta + tc:
		return 0.5 * a * ta * ta + vp * (tau - ta)
	var td := total - tau
	return length - 0.5 * a * td * td


## World XZ (and a y) in this node's frame.
func _loc(p: Vector2, y: float = -1.0) -> Vector3:
	var yy := y if y >= 0.0 else surface_at(macro, p)
	return to_local(WorldState.to_local(Vector3(p.x, yy, p.y)))


func _place(node: Node3D, p: Vector2, yaw: float, y: float = -1.0) -> void:
	node.transform = Transform3D(Basis(Vector3.UP, yaw), _loc(p, y))


func _tend_vehicles(dt: float) -> void:
	var near := false
	if air and air._player:
		var pw := air.player_world()
		near = Vector2(pw.x, pw.z).distance_to(macro.airport_rect.get_center()) < vehicle_range
	if near != _near:
		_near = near
		if near:
			_build_vehicles()
		_vehicles.visible = near
		for snd in _sounds:
			snd.stop()
	if not near:
		return
	_tend_tugs()
	if not hold_vehicles:
		_tend_trains()
	_tend_follow()
	_tend_missions(dt)
	_tend_sound()


func _build_vehicles() -> void:
	if _train_tugs != null:
		return
	_train_tugs = _mm_node("TrainTugs", AirportKit.vehicle("baggage_tug"), trains)
	_train_carts = _mm_node("TrainCarts", AirportKit.vehicle("cart"), trains * train_carts)
	for k in trains * train_carts:
		var tint: Color = AirportKit.CART_TINTS[hash([k, "cart"]) % AirportKit.CART_TINTS.size()]
		_train_carts.multimesh.set_instance_custom_data(k, Color(tint.r, tint.g, tint.b, 1.0))
	_follow = Mover.new()
	_follow.node = _mesh_node("FollowMe", ApronKit.follow_me())
	var fw := follow_home()
	_follow.home = Vector3(fw.x, 0.0, fw.y)
	_follow.home_yaw = follow_home_yaw()
	_fuel = Mover.new()
	_fuel.node = _mesh_node("FuelTruck", AirportKit.vehicle("fuel_truck"))
	var fd := depot(true)
	_fuel.home = Vector3(fd.x, 0.0, fd.y)
	_fuel.home_yaw = depot_yaw(true)
	_catering = Mover.new()
	_catering.node = _mesh_node("CateringTruck", ApronKit.catering_base())
	_catering_box = MeshInstance3D.new()
	_catering_box.mesh = ApronKit.catering_box()
	_catering_box.name = "Box"
	_catering.node.add_child(_catering_box)
	_catering_lift = MeshInstance3D.new()
	_catering_lift.name = "Lift"
	_catering.node.add_child(_catering_lift)
	_set_lift(0.0)
	var cd := depot(false)
	_catering.home = Vector3(cd.x, 0.0, cd.y)
	_catering.home_yaw = depot_yaw(false)
	for m: Mover in [_follow, _fuel, _catering]:
		_place(m.node, Vector2(m.home.x, m.home.z), m.home_yaw)
	_build_arff()
	for k in 2:
		var snd := Sfx.loop_player("engine_loop", -6.0)
		snd.max_distance = 90.0
		snd.unit_size = 6.0
		snd.name = "VehicleSound%d" % k
		_vehicles.add_child(snd)
		_sounds.append(snd)


func _mm_node(node_name: String, mesh: Mesh, count: int) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = count
	for k in count:
		mm.set_instance_color(k, Color.WHITE)
		mm.set_instance_custom_data(k, Color.BLACK)
	var node := MultiMeshInstance3D.new()
	node.name = node_name
	node.multimesh = mm
	node.visibility_range_end = 700.0
	# The instances roam the whole apron: bounds that cover it, in this node's frame.
	var lo := _loc(macro.airport_rect.position, 0.0)
	var hi := _loc(macro.airport_rect.end, 0.0)
	node.custom_aabb = AABB(Vector3(minf(lo.x, hi.x), -5.0, minf(lo.z, hi.z)), Vector3(absf(hi.x - lo.x), 20.0, absf(hi.z - lo.z)))
	_vehicles.add_child(node)
	return node


func _mesh_node(node_name: String, mesh: Mesh) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.visibility_range_end = 700.0
	_vehicles.add_child(mi)
	return mi


# --- Baggage trains ---------------------------------------------------------------------------

## The service road behind the tails as a closed loop: eastbound in its inner lane, round a
## turnaround beyond the east end of the concourse, westbound in the outer lane, round the west
## one. Built once; the trains run on it by the clock.
func _build_train_route() -> void:
	var rf := Airport.apron_face()
	var inner := 49.25
	var outer := 53.75
	var a_end := 0.205
	var pts := PackedVector2Array()
	var radii := PackedFloat32Array()
	var n := 40
	for k in n + 1:
		var a := lerpf(-a_end, a_end, float(k) / float(n))
		pts.append(Airport.arc_point(a, rf + inner))
		radii.append(0.0)
	# The east turnaround: out past the lane's end and round, back into the outer lane.
	for q: Vector2 in [Vector2(12.0, -2.5), Vector2(21.0, 2.25), Vector2(12.0, 7.0)]:
		pts.append(_arc_offset(a_end, rf + inner, q))
		radii.append(5.0)
	for k in n + 1:
		var a := lerpf(a_end, -a_end, float(k) / float(n))
		pts.append(Airport.arc_point(a, rf + outer))
		radii.append(0.0)
	for q: Vector2 in [Vector2(-12.0, 7.0), Vector2(-21.0, 2.25), Vector2(-12.0, -2.5)]:
		pts.append(_arc_offset(-a_end, rf + inner, q))
		radii.append(5.0)
	pts.append(pts[0])
	radii.append(0.0)
	radii[0] = 0.0
	_train_route = AirRoute.from_waypoints(pts, radii, "service_road", LEG_STEP, 0.45)
	# Each loop the train stops behind two stands to load (the same stops for every train, so
	# trains spaced a period apart never meet).
	_train_plan = []
	var stops: Array[float] = []
	for gi: int in [2, 6]:
		var ga: float = Airport.gates()[gi].a
		stops.append(_train_route.nearest(Airport.arc_point(ga, rf + inner)))
	stops.sort()
	var s := 0.0
	var t := 0.0
	for st: float in stops:
		var move := trap_time(st - s, train_speed, 1.0)
		_train_plan.append([t, t + move, s, st])
		t += move + 14.0
		s = st
	var last := trap_time(_train_route.length - s, train_speed, 1.0)
	_train_plan.append([t, t + last, s, _train_route.length])
	_train_period = t + last


## A point offset `q` (x along the arc's tangent, y outward) from arc angle `a` at radius `r`.
static func _arc_offset(a: float, r: float, q: Vector2) -> Vector2:
	return Airport.arc_point(a, r) + Airport.arc_tangent(a) * q.x + Airport.arc_normal(a) * q.y


## Distance along the service road loop of train `k` at clock `t`.
func train_s(k: int, t: float) -> float:
	var tt := fposmod(t + float(k) * _train_period / float(maxi(trains, 1)), _train_period)
	for seg: Array in _train_plan:
		if tt < float(seg[1]):
			return float(seg[2]) + trap_s(float(seg[3]) - float(seg[2]), train_speed, 1.0, maxf(tt - float(seg[0]), 0.0))
		if tt < float(seg[1]) + 14.0:
			return float(seg[3])
	return 0.0


func _tend_trains() -> void:
	if _train_tugs == null:
		return
	var length := _train_route.length
	for k in trains:
		var s := train_s(k, clock)
		_train_tugs.multimesh.set_instance_transform(k, _route_xf(_train_route, s))
		for c in train_carts:
			var cs := fposmod(s - CART_PITCH * (float(c) + 1.0) - 0.6, length)
			_train_carts.multimesh.set_instance_transform(k * train_carts + c, _route_xf(_train_route, cs))


func _route_xf(r: AirRoute, s: float) -> Transform3D:
	var smp := r.sample(s)
	var p: Vector3 = smp.pos
	return Transform3D(Basis(Vector3.UP, float(smp.yaw)), _loc(Vector2(p.x, p.z), macro.tarmac_top))


# --- Pushback tugs ----------------------------------------------------------------------------

## A stand's live tug: shown while its gate set is not (the set has its own), under the nose of
## a parked jet ready to push, attached while it pushes, then back to its waiting spot beside the
## stand.
func _tend_tugs() -> void:
	var gs := Airport.gates()
	for i in gs.size():
		var g: Dictionary = gs[i]
		var show := not g_set_shown[i]
		var tug: Dictionary = _tugs.get(i, {})
		if not show:
			if not tug.is_empty():
				(tug.node as Node3D).visible = false
			continue
		if tug.is_empty():
			var mi := _mesh_node("Tug%d" % i, AirportKit.vehicle("pushback"))
			var m := Mover.new()
			m.node = mi
			var w := stand_point(g, TUG_WAITING)
			m.home = Vector3(w.x, 0.0, w.y)
			m.home_yaw = stand_yaw(g, Vector2(0.0, -1.0))
			tug = {"node": mi, "mover": m, "mode": "wait"}
			_tugs[i] = tug
			_place(mi, w, m.home_yaw)
		var node: Node3D = tug.node
		node.visible = true
		var mover: Mover = tug.mover
		var jet := _pushing_jet(i)
		if tug.mode != "returning" and jet != null and jet.phase == AmbientJet.Phase.GROUND and (jet.ground_leg == 0 or (jet.ground_leg == 1 and jet.ground_wait > 0.0)):
			# Under the nose, facing the tail: pushing, then disconnecting.
			var fwd := Vector2(-sin(jet.yaw), -cos(jet.yaw))
			var nose := Vector2(jet.world_pos.x, jet.world_pos.z) + fwd * (jet.length * 0.5 - TUG_AT_NOSE.z)
			_place(node, nose, jet.yaw + PI)
			tug.mode = "pushing"
			if jet.ground_leg == 1 and jet.ground_wait < disconnect_seconds - 2.0:
				_tug_home(tug, i, nose, jet.yaw + PI)
			continue
		if tug.mode == "returning":
			var pose := mover.pose_at(clock)
			_place(node, pose.pos, pose.yaw)
			if not mover.busy(clock):
				tug.mode = "wait"
			continue
		if g_state[i] == G.PARKED and g_bridge[i] > 0.999 and tug.mode == "wait" and not watched(g.centre):
			# Ready for the departure: under the nose, where the gate set has its own tug.
			tug.mode = "nose"
		var at := stand_point(g, TUG_AT_NOSE) if tug.mode == "nose" else Vector2(mover.home.x, mover.home.z)
		var yaw := stand_yaw(g, Vector2(0.0, 1.0)) if tug.mode == "nose" else mover.home_yaw
		_place(node, at, yaw)


func _tug_ready(i: int) -> bool:
	if g_set_shown[i]:
		return false
	var tug: Dictionary = _tugs.get(i, {})
	# Far from the field nobody sees the tug: any stand will do.
	return not _near or tug.is_empty() or tug.mode == "nose" or not watched(Airport.gates()[i].centre)


func _pushing_jet(i: int) -> AmbientJet:
	for j in _jets:
		if is_instance_valid(j) and _jet_gate.get(j, -2) == i and g_state[i] == G.PUSHING:
			return j
	# The stand frees itself once the jet is taxiing; the tug still rides the disconnect.
	for j in _jets:
		if is_instance_valid(j) and j.has_meta("tug_gate") and int(j.get_meta("tug_gate")) == i:
			return j
	return null


## The tug backs off the nose wheel, turns and drives back to its waiting spot beside the stand.
func _tug_home(tug: Dictionary, i: int, from: Vector2, yaw: float) -> void:
	var g: Dictionary = Airport.gates()[i]
	var m: Mover = tug.mover
	var back_dir := -Vector2(-sin(yaw), -cos(yaw))
	var b := from + back_dir * 7.0
	var w := Vector2(m.home.x, m.home.z)
	var c := gate_corner(macro, g)
	m.steps.clear()
	m.home = Vector3(w.x, 0.0, w.y)
	m.drive(AirRoute.from_waypoints(PackedVector2Array([from, b]), PackedFloat32Array([0.0, 0.0]), "tug_back", LEG_STEP), 2.0, true)
	var fwd := Vector2(-sin(yaw), -cos(yaw))
	var p1 := b + fwd * 4.0 + Vector2(0.0, -1.5)
	var p2 := Vector2(p1.x, macro.taxiway_z - 14.0)
	var p3 := stand_point(g, Vector3(TUG_WAITING.x, 0.0, 12.0))
	m.drive(AirRoute.from_waypoints(PackedVector2Array([b, p1, p2, p3, w]), PackedFloat32Array([0.0, 3.5, 6.0, 4.0, 0.0]), "tug_home", LEG_STEP, 0.6), 4.0)
	var _c := c
	tug.mode = "returning"


# --- Follow-me ----------------------------------------------------------------------------------

## The follow-me car's spot on the apron at the taxiway's west end, and its heading there.
func follow_home() -> Vector2:
	return Vector2(Airport.CONNECTOR_XS[0] + 32.0, macro.taxiway_z - 27.0)


func follow_home_yaw() -> float:
	# Facing south-west, the way it pulls out toward the taxiway (and arrives back home).
	return atan2(0.7, -0.7)


## Leads each arrival up the taxiway: it pulls out onto the taxiway as the jet comes off the
## connector, holds `FOLLOW_LEAD` ahead of it along the jet's own legs, peels off past the stand's
## lead-in and drives home along the service road.
const FOLLOW_LEAD := 55.0


func _tend_follow() -> void:
	if _follow == null:
		return
	match _follow_mode:
		0:
			# Waiting: the next jet coming up the west connector.
			for j in _jets:
				if is_instance_valid(j) and j.phase == AmbientJet.Phase.GROUND and String(j.ground_leg_data().get("tag", "")) == "cross" and j.d > 0.0:
					_follow_jet = j
					_follow_mode = 1
					var join := _follow_join(j)
					_follow.steps.clear()
					var h := Vector2(_follow.home.x, _follow.home.z)
					_follow.drive(AirRoute.from_waypoints(PackedVector2Array([h, Vector2(join.x - 14.0, join.y - 10.0), join, join + Vector2(6.0, 0.0)]), PackedFloat32Array([0.0, 6.0, 6.0, 0.0]), "follow_out", LEG_STEP, 0.6), 5.0)
					break
			var pose := _follow.pose_at(clock)
			_place(_follow.node, pose.pos, pose.yaw)
		1:
			# Pulled out, waiting at the join for its jet to come up behind it, then leading.
			if _follow_jet == null or not is_instance_valid(_follow_jet) or _follow_jet.done or _follow_jet.phase != AmbientJet.Phase.GROUND:
				_follow_back()
				return
			var j := _follow_jet
			var lead_s := _lead_point(j, FOLLOW_LEAD)
			if lead_s.is_empty():
				var pose := _follow.pose_at(clock)
				_place(_follow.node, pose.pos, pose.yaw)
				return
			if lead_s.get("peel", false):
				_follow_peel(lead_s.pos, lead_s.yaw)
				return
			var pose2 := _follow.pose_at(clock)
			var p: Vector2 = lead_s.pos
			# Only once the jet has caught up with the car does the car take its lead.
			if _follow.busy(clock) or p.x < pose2.pos.x - 0.5:
				_place(_follow.node, pose2.pos, pose2.yaw)
				return
			_place(_follow.node, p, lead_s.yaw)
		2:
			var pose := _follow.pose_at(clock)
			_place(_follow.node, pose.pos, pose.yaw)
			if not _follow.busy(clock):
				_follow_mode = 0


## Where the follow-me joins the taxiway: just past the lead-off curve from the west connector.
func _follow_join(_j: AmbientJet) -> Vector2:
	return Vector2(Airport.CONNECTOR_XS[0] + R_LEAD + 2.0, macro.taxiway_z)


## The point `ahead` metres along the jet's legs past its own position, while it is on the
## taxiway part of its way ({} before, peel = true once that point would turn into the stand).
func _lead_point(j: AmbientJet, ahead: float) -> Dictionary:
	var legs := j.ground_legs
	var k := j.ground_leg
	var s := j.d + ahead
	while k < legs.size():
		var r: AirRoute = (legs[k] as Dictionary).route
		if s <= r.length:
			var smp := r.sample(s)
			var p: Vector3 = smp.pos
			if r.name == "lead_in":
				# Past the straight bit of the lead-in, the car would turn into the stand.
				if absf(p.z - macro.taxiway_z) > 0.6:
					return {"pos": Vector2(p.x, p.z), "yaw": float(smp.yaw), "peel": true}
			if absf(p.z - macro.taxiway_z) > 0.6:
				return {}
			return {"pos": Vector2(p.x, p.z), "yaw": float(smp.yaw)}
		s -= r.length
		k += 1
	return {}


## Peels off: on east along the taxiway, up through the gap east of the stand, home west along
## the service road.
func _follow_peel(_at: Vector2, _yaw: float) -> void:
	var pose := _follow.pose_at(clock)
	var from: Vector2 = pose.pos
	_follow_mode = 2
	_follow.steps.clear()
	var rf := Airport.apron_face()
	var a_here := Airport.angle_at_x(from.x + 30.0, rf + 53.75)
	var up := Airport.arc_point(a_here, rf + 53.75)
	var pts := PackedVector2Array([from, Vector2(from.x + 22.0, from.y), up])
	var radii := PackedFloat32Array([0.0, 8.0])
	var a_home := Airport.angle_at_x(_follow.home.x + 10.0, rf + 53.75)
	var steps := 8
	for k in range(1, steps + 1):
		pts.append(Airport.arc_point(lerpf(a_here, a_home, float(k) / float(steps)), rf + 53.75))
		radii.append(0.0)
	radii[2] = 7.0
	pts.append(Vector2(_follow.home.x, _follow.home.z))
	radii.append(0.0)
	_follow.drive(AirRoute.from_waypoints(pts, radii, "follow_home", LEG_STEP, 0.6), 8.0)
	_follow_jet = null


func _follow_back() -> void:
	_follow_jet = null
	var pose := _follow.pose_at(clock)
	_follow_mode = 2
	_follow.steps.clear()
	_follow.drive(AirRoute.from_waypoints(PackedVector2Array([pose.pos, Vector2(_follow.home.x, _follow.home.z)]), PackedFloat32Array([0.0, 0.0]), "follow_back", LEG_STEP), 5.0)


# --- Fuel and catering --------------------------------------------------------------------------

## The trucks' depots, beside the equipment staging at each end of the concourse (east: the fuel
## truck, west: the catering truck), and their heading there.
func depot(east: bool) -> Vector2:
	var a := (Airport.CONCOURSE_ARC + 0.026) * (1.0 if east else -1.0)
	return Airport.arc_point(a, Airport.apron_face() + 36.0)


func depot_yaw(east: bool) -> float:
	var a := (Airport.CONCOURSE_ARC + 0.026) * (1.0 if east else -1.0)
	var n := Airport.arc_normal(a)
	return atan2(n.x, n.y)


## Every `mission_interval`: an idle truck goes to a parked jet whose own gate set has no such
## truck, while the jet's turnaround has time for it.
func _tend_missions(dt: float) -> void:
	_tend_catering_lift()
	for m: Mover in [_fuel, _catering]:
		var pose := m.pose_at(clock)
		_place(m.node, pose.pos, pose.yaw)
	_mission_left -= dt
	if _mission_left > 0.0:
		return
	_mission_left = mission_interval
	var catering := _rng.randf() < 0.5
	var m: Mover = _catering if catering else _fuel
	if m.busy(clock):
		return
	var picks: Array[int] = []
	for i in g_state.size():
		var g: Dictionary = Airport.gates()[i]
		if g_state[i] != G.PARKED or g_bridge[i] < 0.999 or bool(g.empty):
			continue
		var svc: int = g.service
		var has := (svc & 1) != 0 if catering else (svc & 2) != 0
		if has and g_set_shown[i]:
			continue
		if g_ready_at[i] - clock < 130.0:
			continue
		picks.append(i)
	if picks.is_empty():
		return
	var gi: int = picks[_rng.randi() % picks.size()]
	if catering:
		_send_catering(gi)
	else:
		_send_fuel(gi)
	# The departure waits for the truck to be gone.
	g_ready_at[gi] = maxf(g_ready_at[gi], m.end_time() + 5.0)


## A route along the service road from world `from` (near the depot) to just behind stand `gi` at
## stand side `side`, in the lane that runs that way (inner eastbound, outer westbound).
func _road_to(from: Vector2, gi: int, side: float, east: bool) -> PackedVector2Array:
	var g: Dictionary = Airport.gates()[gi]
	var rf := Airport.apron_face()
	var lane := rf + (49.25 if east else 53.75)
	var a0 := Airport.angle_at_x(from.x, lane)
	var target_a := float(g.a) + side / lane
	var pts := PackedVector2Array([from])
	var steps := maxi(2, int(absf(target_a - a0) * lane / 12.0))
	for k in range(1, steps + 1):
		pts.append(Airport.arc_point(lerpf(a0, target_a, float(k) / float(steps)), lane))
	return pts


func _send_fuel(gi: int) -> void:
	var g: Dictionary = Airport.gates()[gi]
	var m := _fuel
	m.steps.clear()
	var home := Vector2(m.home.x, m.home.z)
	var a_dep := Airport.CONCOURSE_ARC + 0.026
	var out := home + Airport.arc_normal(a_dep) * 12.0
	# Backs out of the depot, then west along the outer lane to the stand, in under the right wing.
	m.drive(AirRoute.from_waypoints(PackedVector2Array([home, out]), PackedFloat32Array([0.0, 0.0]), "fuel_back", LEG_STEP), 2.5, true)
	var pts := _road_to(out - Airport.arc_normal(a_dep) * 3.0 - Airport.arc_tangent(a_dep) * 9.0, gi, 12.8, false)
	pts.insert(0, out)
	pts.append(stand_point(g, Vector3(12.8, 0.0, 30.0)))
	pts.append(stand_point(g, Vector3(12.8, 0.0, 17.0)))
	m.drive(AirRoute.from_waypoints(pts, _radii(pts.size(), 6.0), "fuel_in", LEG_STEP, 0.6), 6.0)
	m.wait(70.0, "fuelling")
	# On forward, out through the gap east of the stand, east along the inner lane, home.
	var back := PackedVector2Array([stand_point(g, Vector3(12.8, 0.0, 17.0)), stand_point(g, Vector3(12.8, 0.0, 8.0)), stand_point(g, Vector3(20.0, 0.0, 8.0)), stand_point(g, Vector3(20.0, 0.0, 43.75))])
	var rf := Airport.apron_face()
	var a0 := Airport.angle_at_x(back[3].x, rf + 49.25) + 0.015
	var a1 := Airport.CONCOURSE_ARC + 0.012
	var steps := maxi(2, int((a1 - a0) * rf / 12.0))
	for k in range(1, steps + 1):
		back.append(Airport.arc_point(lerpf(a0, a1, float(k) / float(steps)), rf + 49.25))
	back.append(home)
	m.drive(AirRoute.from_waypoints(back, _radii(back.size(), 5.0), "fuel_out", LEG_STEP, 0.6), 6.0)


func _send_catering(gi: int) -> void:
	var g: Dictionary = Airport.gates()[gi]
	var m := _catering
	m.steps.clear()
	var home := Vector2(m.home.x, m.home.z)
	var a_dep := -(Airport.CONCOURSE_ARC + 0.026)
	var out := home + Airport.arc_normal(a_dep) * 12.0
	# Backs out of the depot, east along the inner lane, in beside the rear fuselage, a left turn
	# to face the rear door.
	m.drive(AirRoute.from_waypoints(PackedVector2Array([home, out]), PackedFloat32Array([0.0, 0.0]), "catering_back_out", LEG_STEP), 2.5, true)
	var pts := _road_to(out - Airport.arc_normal(a_dep) * 3.0 + Airport.arc_tangent(a_dep) * 9.0, gi, 11.0, true)
	pts.insert(0, out)
	pts.append(stand_point(g, Vector3(11.0, 0.0, 29.0)))
	pts.append(stand_point(g, Vector3(4.6, 0.0, 29.0)))
	var radii := _radii(pts.size(), 6.0)
	radii[radii.size() - 2] = 5.0
	m.drive(AirRoute.from_waypoints(pts, radii, "catering_in", LEG_STEP, 0.6), 5.0)
	m.wait(6.0, "raise")
	m.wait(28.0, "up")
	m.wait(6.0, "lower")
	# Backs away from the door, round to face the service road, out and west home.
	m.drive(AirRoute.from_waypoints(PackedVector2Array([stand_point(g, Vector3(4.6, 0.0, 29.0)), stand_point(g, Vector3(11.0, 0.0, 29.0)), stand_point(g, Vector3(11.0, 0.0, 21.0))]), PackedFloat32Array([0.0, 5.0, 0.0]), "catering_back", LEG_STEP, 0.9), 2.0, true)
	var rf := Airport.apron_face()
	var back := PackedVector2Array([stand_point(g, Vector3(11.0, 0.0, 21.0)), stand_point(g, Vector3(11.0, 0.0, 48.25))])
	var a0 := Airport.angle_at_x(back[1].x, rf + 53.75) - 0.012
	var a1 := -(Airport.CONCOURSE_ARC + 0.012)
	var steps := maxi(2, int(absf(a1 - a0) * rf / 12.0))
	for k in range(1, steps + 1):
		back.append(Airport.arc_point(lerpf(a0, a1, float(k) / float(steps)), rf + 53.75))
	back.append(home)
	m.drive(AirRoute.from_waypoints(back, _radii(back.size(), 5.0), "catering_out", LEG_STEP, 0.6), 6.0)


static func _radii(n: int, r: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		out[i] = r if i > 0 and i < n - 1 else 0.0
	return out


## The catering box on its scissor: down while it drives, up to the rear door's sill (4.4 m to the
## box floor) while it serves.
func _tend_catering_lift() -> void:
	var pose := _catering.pose_at(clock)
	var tag: String = pose.get("tag", "")
	var tau: float = pose.get("tau", 0.0)
	var h := 0.25
	match tag:
		"raise":
			h = lerpf(0.25, 3.3, smoothstep(0.0, 6.0, tau))
		"up":
			h = 3.3
		"lower":
			h = lerpf(3.3, 0.25, smoothstep(0.0, 6.0, tau))
	_set_lift(h)


func _set_lift(h: float) -> void:
	if absf(h - _lift_h) < 0.015:
		return
	_lift_h = h
	_catering_box.position = Vector3(0.0, 1.12 + h, -0.8)
	_catering_lift.mesh = ApronKit.scissor(h)


## The lift height now (tests, stills).
func catering_lift() -> float:
	return _lift_h


# --- The crash tender ---------------------------------------------------------------------------

## Where the crash tender's shed stands (world XZ): on the apron north of the hangars, its open
## front to the taxiway (south).
const ARFF_AT := Vector2(52.0, 712.0)


func _build_arff() -> void:
	_arff = Node3D.new()
	_arff.name = "CrashTender"
	_vehicles.add_child(_arff)
	_place(_arff, ARFF_AT, PI, macro.tarmac_top)
	var shed := MeshInstance3D.new()
	shed.name = "Shed"
	shed.mesh = ApronKit.arff_station()
	_arff.add_child(shed)
	for k in 2:
		var truck := MeshInstance3D.new()
		truck.name = "Tender%d" % k
		truck.mesh = ApronKit.arff()
		# Nose out of the open front (the shed's -Z), one in each bay.
		truck.position = Vector3(-4.0 + 8.0 * float(k), 0.0, -1.5)
		_arff.add_child(truck)


# --- Sound --------------------------------------------------------------------------------------

## The two nearest moving vehicles carry an engine loop.
func _tend_sound() -> void:
	var cam := get_viewport().get_camera_3d() if get_viewport() else null
	if cam == null or _sounds.is_empty():
		return
	var spots: Array = []
	if _train_tugs:
		for k in trains:
			spots.append(_train_tugs.to_global(_train_tugs.multimesh.get_instance_transform(k).origin))
	for m: Mover in [_follow, _fuel, _catering]:
		if m and m.busy(clock):
			spots.append(m.node.global_position)
	spots.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.distance_squared_to(cam.global_position) < b.distance_squared_to(cam.global_position))
	for k in _sounds.size():
		var snd := _sounds[k]
		if k < spots.size() and (spots[k] as Vector3).distance_to(cam.global_position) < snd.max_distance:
			snd.global_position = spots[k]
			if not snd.playing:
				snd.play(_rng.randf() * 0.3)
		elif snd.playing:
			snd.stop()


# --- Stills and tests -------------------------------------------------------------------------

## Stages the field for a screenshot: "taxi" (an arrival on the taxiway `along` metres into its
## way from the west connector), "pushback" (stand `gate` pushing back, `along` seconds in),
## "apron" (the vehicles: the catering truck up at a stand's door, the fuel truck under a wing,
## the trains where the clock has them). Returns the jet it placed (or null).
func stage(kind: String, gate: int, along: float) -> AmbientJet:
	clear()
	_near = false
	_tend_vehicles(0.0)
	match kind:
		"taxi":
			var gi := clampi(gate, 0, g_state.size() - 1)
			g_state[gi] = G.EMPTY
			g_jet_shown[gi] = false
			g_set_shown[gi] = false
			g_bridge[gi] = 0.0
			g_bridge_to[gi] = 0.0
			_apply_jet(gi)
			_apply_set(gi)
			var cxw: float = Airport.CONNECTOR_XS[0]
			var start := Vector2(cxw + 120.0, macro.runway_zs[macro.arrival_runway])
			var jet := air.spawn_ground_jet(Aircraft.Kind.AIRLINER, int(hash([gi, "stage"]) % Airport.LIVERIES), Vector3(start.x, Airport.RUNWAY_TOP, start.y), PI * 0.5)
			jet.speed = jet.ground_speed
			var legs := arrival_legs(start, gi, jet)
			g_state[gi] = G.INBOUND
			_adopt(jet, gi)
			jet.engine_level = 0.3
			jet.start_ground(legs, _on_arrived)
			_owner = jet
			_fast_forward(jet, along)
			return jet
		"pushback":
			var gi := clampi(gate, 0, g_state.size() - 1)
			g_set_shown[gi] = false
			_apply_set(gi)
			g_ready_at[gi] = clock
			var jet := push_back(gi)
			_fast_forward(jet, along)
			return jet
		"apron":
			# The clock set so that, `along` seconds on, the first train has just stopped behind
			# stand 13 (its first stop) while the catering truck is up at stand 12's door.
			clock = float(_train_plan[0][1]) + 5.0 - along
			for k in 2:
				var gi := 1 + k * 4
				g_set_shown[gi] = false
				_apply_set(gi)
				g_ready_at[gi] = clock + 600.0
			_send_catering(1)
			_send_fuel(5)
			run_vehicles(along)
			return null
	return null


## Runs `jet` (and the field) forward by `seconds` of game time at once.
func _fast_forward(jet: AmbientJet, seconds: float) -> void:
	var t := 0.0
	while t < seconds and is_instance_valid(jet) and not jet.done:
		var dt := minf(0.1, seconds - t)
		advance(dt)
		jet.advance(dt)
		t += dt


## Runs the clock-driven vehicles to `seconds` of mission time (stills: the catering truck up).
func run_vehicles(seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		clock += 0.25
		_tend_vehicles(0.25)
		t += 0.25
