class_name TrafficManager
extends Node3D
## Keeps cars driving the lanes around the player. Traffic cars are frozen (kinematic)
## Vehicles moved along road lines; they turn at intersections at random. Anything fast that
## hits one unfreezes it into a normal physics car that rolls to a stop. How many there are
## follows density_at(): packed downtown, thinning toward the edges, packed again on the
## streets around the airport, whose drop-off loop (MacroMap.terminal_loops) carries its own
## bumper-to-bumper crawl while the player is near the terminal.

## Cars around the player at density 1.0 (downtown core); density scales it down elsewhere.
@export var max_cars: int = 14
## Cars crawling the airport drop-off loop.
@export var max_loop_cars: int = 90
## Bumper-to-bumper spacing on the loop (meters, front to front).
@export var loop_gap: float = 7.5
## Loop crawl speed (m/s) with a clear road ahead.
@export var loop_speed: float = 5.0
## The loop is populated while the player is within this distance of the terminal curb (m).
@export var loop_active_distance: float = 650.0
## Traffic density kept at the far edges of the city (fraction of max_cars).
@export var edge_density: float = 0.2
## Downtown traffic drives slower than the suburbs (speed multiplier at density 1.0).
@export var dense_speed_factor: float = 0.6
## Spawn between these distances from the player (meters).
@export var spawn_min: float = 120.0
@export var spawn_max: float = 260.0
@export var despawn_distance: float = 380.0
@export var speed_range: Vector2 = Vector2(9.0, 15.0)
@export var turn_chance: float = 0.35
## Cars on the freeway decks, in total across every route near the player.
@export var max_freeway_cars: int = 70
## Front-to-front spacing of freeway traffic (meters). Freeway traffic is fast and spread out.
@export var freeway_gap: float = 34.0
## Freeway cruising speed (m/s) with a clear deck ahead. 26 m/s is about 60 mph.
@export var freeway_speed: float = 26.0
## Freeway traffic is only kept within this distance of the player, along the route (meters).
@export var freeway_range: float = 620.0
## New cars a spawn may BUILD per rendered frame (not per physics tick: a slow frame runs several
## ticks, and a per-tick cap let it build one in each). Building one is about 35 ms on a slow machine
## (body model, paint, wheels, lights), and the half-second upkeep used to build up to thirty-four
## in one tick - street, freeway and airport loop together - which was the worst hitch left in
## the game. Spawns now queue and run at most this many builds a frame; reusing a retired car from
## the pool is nearly free and does not count.
@export var builds_per_frame: int = 1
## Traffic cars that drive out of range are kept (out of the tree) for the next spawn instead of
## being freed and rebuilt. Same random cars, none of the building.
@export var pool_size: int = 60

@export_group("Street driving")
## Street cars follow the car in front with the Intelligent Driver Model: free-road acceleration
## and comfortable braking (m/s squared).
@export var accel: float = 2.4
@export var brake_comfort: float = 3.6
## The hardest a car ever brakes (m/s squared). The model can ask for more; the gap clamp in
## _drive_street() is what finally guarantees nobody drives into the car in front.
@export var brake_max: float = 9.0
## Bumper-to-bumper gap a queue stops at (m), and the time gap kept behind a moving car (s).
@export var min_gap: float = 2.2
@export var time_gap: float = 1.1
## A car's nose stops this far back from the crossing road's edge: the stop line (StreetDetail)
## is painted 3.3 m back, past the crosswalk.
@export var stop_line_back: float = 3.7
## Speed a car slows to for a turn at the middle of an intersection (m/s).
@export var turn_speed: float = 6.5
## How long a car stands at a stop sign before it goes (s).
@export var stop_sign_wait: float = 1.0
## An amber light is run only when stopping would need more than this share of brake_comfort.
@export var amber_margin: float = 1.25
## A siren this close behind a car on its carriageway makes it pull toward the kerb and stop (m),
## and how far over it pulls (m).
@export var siren_yield_distance: float = 40.0
@export var siren_shift: float = 1.2
## The player, or the player's car, standing in a lane: cars brake for it, up to this hard (m/s
## squared). A player who steps out in front of a car at speed still gets hit.
@export var player_brake: float = 6.0

var plan: CityPlan
var cars: Array[Vehicle] = []
## Cars on the airport drop-off loop (traffic dict holds "loop" and "t").
var loop_cars: Array[Vehicle] = []
## Cars on the freeway decks (traffic dict holds "fw", "t", "dir" and "lane").
var freeway_cars: Array[Vehicle] = []
var _player: Node3D
var _rng := RandomNumberGenerator.new()
var _timer: float = 0.0
var _loop_lengths: PackedFloat32Array = PackedFloat32Array()
var _pool: Array[Vehicle] = []
## Spawns waiting to run (see builds_per_frame): streets, airport loop, freeway. Rebuilt at every
## upkeep from the cars that exist then, so a queued spawn never fills a slot twice, and served in
## turn, so a street deficit cannot starve the freeway.
var _spawn_queues: Array = [[], [], []]
var _next_queue: int = 0
var _built_this_frame: int = 0
var _build_frame: int = -1
## Street cars placed by hand (tests, screenshots: place_car()): while this is on the upkeep
## neither sheds street cars nor spawns new ones, and street spawns already queued are dropped. A
## cap lowered with spawns still queued otherwise overshoots it and the shedding that follows
## takes the placed cars with the rest.
var staged: bool = false


func _ready() -> void:
	_rng.seed = 99


func _physics_process(delta: float) -> void:
	if plan == null:
		return
	if _player == null:
		_player = get_tree().get_first_node_in_group("player") as Node3D
		if _player == null:
			return
	# The one clock every signal in the city runs on (TrafficSignals): the heads' shader and the
	# cars below read the same value this tick.
	TrafficSignals.advance(delta)
	_timer += delta
	if _timer >= 0.5:
		_timer = 0.0
		for q: Array in _spawn_queues:
			q.clear()
		_maintain()
		_maintain_freeway()
	_run_spawns()
	_drive_streets(delta)
	_drive_loops(delta)
	_drive_freeway(delta)


func _run_spawns() -> void:
	if Engine.get_process_frames() != _build_frame:
		_build_frame = Engine.get_process_frames()
		_built_this_frame = 0
	var waiting := 0
	for q: Array in _spawn_queues:
		waiting += q.size()
	if staged and not _spawn_queues[0].is_empty():
		waiting -= _spawn_queues[0].size()
		_spawn_queues[0].clear()
	if waiting == 0 or _built_this_frame >= builds_per_frame:
		return
	if not PhysicsBudget.can_spawn():
		for q: Array in _spawn_queues:
			q.clear()
		return
	var ran := 0
	while waiting > 0 and _built_this_frame < builds_per_frame and ran < 8:
		var q: Array = _spawn_queues[_next_queue]
		_next_queue = (_next_queue + 1) % _spawn_queues.size()
		if q.is_empty():
			continue
		(q.pop_front() as Callable).call()
		waiting -= 1
		ran += 1


## A car for a spawn: a retired one from the pool when there is one, else a new build (counted
## against builds_per_frame).
func _new_car() -> Vehicle:
	while not _pool.is_empty():
		var car: Vehicle = _pool.pop_back()
		if is_instance_valid(car):
			return car
	_built_this_frame += 1
	return Vehicle.random_car(_rng)


## Takes a traffic car off the road: into the pool if there is room, freed otherwise.
func _retire(car: Vehicle) -> void:
	if not is_instance_valid(car):
		return
	if car.is_traffic() and car.get_parent() == self and _pool.size() < pool_size:
		remove_child(car)
		_pool.append(car)
	else:
		car.queue_free()


func _exit_tree() -> void:
	for car in _pool:
		if is_instance_valid(car):
			car.free()
	_pool.clear()


## How busy the streets are here, 0..1: the downtown core is 1.0, the far edges edge_density,
## and the streets around the airport terminal are jammed as well.
func density_at(pos: Vector2) -> float:
	var macro: MacroMap = plan.macro
	if macro == null:
		return 1.0
	var dd := pos.distance_to(macro.downtown_center)
	var d := lerpf(edge_density, 1.0, smoothstep(macro.midtown_radius * 1.6, macro.downtown_radius * 0.5, dd))
	var curb: Rect2 = macro.terminal_curb
	var to_curb := (pos - pos.clamp(curb.position, curb.end)).length()
	d = maxf(d, lerpf(1.0, edge_density, smoothstep(140.0, 480.0, to_curb)))
	return d


func _maintain() -> void:
	var pw := WorldState.to_world(_player.global_position)
	for car in cars.duplicate():
		if not is_instance_valid(car):
			cars.erase(car)
			continue
		var wp := WorldState.to_world(car.global_position)
		var zone := plan.zone_at(Vector2(wp.x, wp.z))
		if wp.distance_to(pw) > despawn_distance or (zone != MacroMap.Zone.CITY and zone != MacroMap.Zone.BEACH):
			cars.erase(car)
			_retire(car)
		else:
			_turn_back_from_replica(car)
	var density := density_at(Vector2(pw.x, pw.z))
	var want := roundi(max_cars * density)
	# Too many (a lower quality level or a quieter district): shed the farthest ones.
	if staged:
		want = cars.size()
	elif cars.size() > want + 4:
		cars.sort_custom(func(a: Vehicle, b: Vehicle) -> bool: return a.global_position.distance_squared_to(_player.global_position) > b.global_position.distance_squared_to(_player.global_position))
		while cars.size() > want:
			var far: Vehicle = cars.pop_front()
			_retire(far)
	while loop_cars.size() > max_loop_cars:
		var extra: Vehicle = loop_cars.pop_back()
		_retire(extra)
	for i in mini(want - cars.size(), 12):
		_spawn_queues[0].append(_spawn_near.bind(pw, density))
	_maintain_loops(pw)


func _spawn_near(pw: Vector3, density: float = 1.0) -> void:
	var axis := _rng.randi_range(0, 1)
	var center := plan.block_index_at(Vector2(pw.x, pw.z))
	var index := (center.x if axis == CityPlan.AXIS_X else center.y) + _rng.randi_range(-2, 3)
	# Dense traffic spawns closer, so the jam is visible from the sidewalk.
	var near := lerpf(spawn_min, spawn_min * 0.5, density)
	var along := (pw.z if axis == CityPlan.AXIS_X else pw.x) + _rng.randf_range(near, spawn_max) * (1.0 if _rng.randf() < 0.5 else -1.0)
	var dir := 1 if _rng.randf() < 0.5 else -1
	var lane := _lane_offset(axis, index, dir)
	var pos2 := Vector2(plan.road_pos(axis, index) + lane, along) if axis == CityPlan.AXIS_X else Vector2(along, plan.road_pos(axis, index) + lane)
	# Open where it stands AND just ahead: a car put down inside a crossing, past its centre, next
	# checks the crossing after, and drove straight on into a road closed by a landmark's site.
	if plan.zone_at(pos2) != MacroMap.Zone.CITY or _replica_blocks(pos2, 6.0) or not plan.road_open(axis, index, along) or not plan.road_open(axis, index, along + dir * 15.0):
		return
	# Never inside a car already in that lane: the queue keeps cars apart, it cannot pull apart
	# two that start inside each other.
	if not _lane_clear(axis, index, dir, lane, along, SPAWN_CLEARANCE):
		return
	var car := _new_car()
	var speed := _rng.randf_range(speed_range.x, speed_range.y) * lerpf(1.0, dense_speed_factor, density)
	car.traffic = {"axis": axis, "index": index, "dir": dir, "lane": lane, "speed": speed, "v": speed * 0.8, "half": car_half_length(car)}
	car.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	car.freeze = true
	# Placed where it belongs before it enters the tree (_enter_at()).
	_enter_at(car, WorldState.to_local(Vector3(pos2.x, 0.55 + _relief(pos2), pos2.y)), _heading(axis, dir), 0.0)
	car.traffic_speed = car.traffic.speed
	cars.append(car)


## Grid cars keep out of a replica area's corridor (ReplicaAreas.blocks_grid()): the grid's own
## roads stop at its edge, and the replica's road carries its own traffic (ReplicaTraffic).
func _replica_blocks(p: Vector2, pad: float) -> bool:
	var rep: ReplicaAreas = plan.macro.replica if plan.macro else null
	return rep != null and rep.blocks_grid(p, pad)


## A grid car about to drive into the corridor turns round in the street instead (checked every
## upkeep, half a second apart, so it looks well ahead of itself).
func _turn_back_from_replica(car: Vehicle) -> void:
	var t: Dictionary = car.traffic
	if not t.has("axis") or plan.macro == null or plan.macro.replica == null:
		return
	var wp := WorldState.to_world(car.global_position)
	var ahead := Vector2(0.0, float(t.dir)) if int(t.axis) == CityPlan.AXIS_X else Vector2(float(t.dir), 0.0)
	if not _replica_blocks(Vector2(wp.x, wp.z) + ahead * 16.0, 1.0):
		return
	var new_dir := -int(t.dir)
	var lane := _lane_offset(t.axis, t.index, new_dir)
	t.dir = new_dir
	t.lane = lane
	var road := plan.road_pos(t.axis, t.index)
	var pos2 := Vector2(road + lane, wp.z) if int(t.axis) == CityPlan.AXIS_X else Vector2(wp.x, road + lane)
	_place(car, WorldState.to_local(Vector3(pos2.x, wp.y, pos2.y)), _heading(t.axis, new_dir), 0.0)


## Adds a car to the tree already standing at scene position `pos`, facing `yaw`, nose pitched by
## `pitch`. The transform is written in this node's own space BEFORE add_child(): this node is
## shifted with the rest of the world at every origin re-centre, so a scene position written as
## the car's local position lands one offset away (after the first re-centre every new street car
## spawned a kilometre off along its road and was retired at once); and a kinematic body that
## enters the tree in one place and is then moved takes that jump as its velocity for a step, the
## aircraft trap in CLAUDE.md.
func _enter_at(car: Vehicle, pos: Vector3, yaw: float, pitch: float) -> void:
	car.transform = global_transform.affine_inverse() * Transform3D(Basis.from_euler(Vector3(pitch, yaw, 0.0)), pos)
	add_child(car)


## Metres of lane either side of a new car that have to be empty before it spawns there.
const SPAWN_CLEARANCE := 14.0


## A street car put exactly here (tests and screenshots): on road (axis, index) driving `dir`, in
## lane `lane_n` (0 = beside the centre line), `along` metres along the road (true world), at
## `speed`. `turns` false keeps it straight on through every junction.
func place_car(axis: int, index: int, dir: int, lane_n: int, along: float, speed: float, turns: bool = true) -> Vehicle:
	var width := plan.road_width(axis, index)
	var lanes := 2 if width > plan.street_width + 1.0 else 1
	var side := -dir if axis == CityPlan.AXIS_X else dir
	var lane := side * CityPlan.lane_center(width, lanes, clampi(lane_n, 0, lanes - 1))
	var pos2 := Vector2(plan.road_pos(axis, index) + lane, along) if axis == CityPlan.AXIS_X else Vector2(along, plan.road_pos(axis, index) + lane)
	var car := _new_car()
	car.traffic = {"axis": axis, "index": index, "dir": dir, "lane": lane, "speed": speed, "v": speed, "half": car_half_length(car)}
	if not turns:
		car.traffic.no_turns = true
	car.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	car.freeze = true
	_enter_at(car, WorldState.to_local(Vector3(pos2.x, 0.55 + _relief(pos2), pos2.y)), _heading(axis, dir), 0.0)
	car.traffic_speed = speed
	cars.append(car)
	return car


## Half a car's length (m): what the queue measures its gaps between.
static func car_half_length(car: Vehicle) -> float:
	return float(car._dims().length) * 0.5


## True when nothing in lane (axis, index, dir, lane) is within `clear` metres of `along`.
func _lane_clear(axis: int, index: int, dir: int, lane: float, along: float, clear: float) -> bool:
	var key := lane_key(axis, index, dir, lane)
	for other in cars:
		if not is_instance_valid(other) or not other.is_traffic() or not other.is_inside_tree():
			continue
		var t: Dictionary = other.traffic
		if not t.has("axis") or lane_key(int(t.axis), int(t.index), int(t.dir), float(t.lane)) != key:
			continue
		var wp := WorldState.to_world(other.global_position)
		if absf((wp.z if axis == CityPlan.AXIS_X else wp.x) - along) < clear:
			return false
	return true


## Right-hand traffic: the lane sits to the right of the direction of travel.
func _lane_offset(axis: int, index: int, dir: int) -> float:
	var width := plan.road_width(axis, index)
	var lanes := 2 if width > plan.street_width + 1.0 else 1
	var n := _rng.randi_range(1, lanes)
	var side := -dir if axis == CityPlan.AXIS_X else dir
	return side * CityPlan.lane_center(width, lanes, n - 1)


func _heading(axis: int, dir: int) -> float:
	var d := Vector3(0.0, 0.0, dir) if axis == CityPlan.AXIS_X else Vector3(dir, 0.0, 0.0)
	return atan2(-d.x, -d.z)


## One carriageway lane of one road: road, axis, direction and which lane, as one int.
static func lane_key(axis: int, index: int, dir: int, lane: float) -> int:
	return (((index + 100000) * 2 + axis) * 2 + (1 if dir > 0 else 0)) * 64 + clampi(roundi(absf(lane) * 4.0), 0, 63)


# --- Street traffic ---------------------------------------------------------------------------
#
# Cars on the city grid follow the car in front (the Intelligent Driver Model) and treat
# everything else they must stop for as one more car in front of them, standing still: the stop
# line at a red or an amber they can stop for (TrafficSignals, worked out from the shared clock),
# a stop sign until they have stood at it, a crosswalk somebody is on (Pedestrian.crosswalk_busy),
# the player's car in their lane. On top of the model, a hard clamp: a car's nose never moves
# past the thing in front of it, so a queue can bunch up but never overlaps. All of it is maths
# on positions the cars already have - no queries, no areas, no per-signal timers.

var _police: Police
## Cruisers running with sirens this tick: [axis, index, dir, along] each.
var _sirens: Array = []
## The player (or the player's car) this tick: [true world position, lateral reach, half length,
## hard], or empty.
var _player_block: Array = []


func _drive_streets(delta: float) -> void:
	if cars.is_empty():
		return
	var groups := {}
	for car in cars.duplicate():
		if not is_instance_valid(car) or not car.is_traffic() or not car.is_inside_tree():
			cars.erase(car)
			continue
		var t: Dictionary = car.traffic
		var wp := WorldState.to_world(car.global_position)
		t.along = wp.z if int(t.axis) == CityPlan.AXIS_X else wp.x
		t.wp = wp
		# A car on a closed stretch (a landmark's site, CityPlan.road_open) has no business there
		# and no way on: back to the pool. Nothing the driving does puts one there - turns are
		# forced off closed roads before the crossing - but a car moved by anything else (an
		# origin shift from outside the physics tick, a placement) would otherwise drive on
		# through MacArthur Park's lake. Inside a crossing and short of it always reads open.
		if not plan.road_open(int(t.axis), int(t.index), float(t.along)):
			cars.erase(car)
			_retire(car)
			continue
		var key := lane_key(int(t.axis), int(t.index), int(t.dir), float(t.lane))
		if not groups.has(key):
			groups[key] = []
		(groups[key] as Array).append(car)
	_sirens = _siren_list()
	_player_block = _player_in_lanes()
	for key in groups:
		var group: Array = groups[key]
		var dir := float(group[0].traffic.dir)
		if group.size() > 1:
			group.sort_custom(func(a: Vehicle, b: Vehicle) -> bool: return float(a.traffic.along) * dir < float(b.traffic.along) * dir)
		for k in group.size():
			_drive_street(group[k], group[k + 1] if k + 1 < group.size() else null, delta, groups)


func _drive_street(car: Vehicle, leader: Vehicle, delta: float, groups: Dictionary) -> void:
	var t: Dictionary = car.traffic
	var axis: int = t.axis
	var dir: int = t.dir
	var index: int = t.index
	var along: float = t.along
	var half: float = t.get("half", 2.4)
	var v: float = t.get("v", float(t.speed))
	var v0: float = t.speed
	var cross_axis := CityPlan.AXIS_Z if axis == CityPlan.AXIS_X else CityPlan.AXIS_X
	# Next crossing road in the direction of travel, and the one just crossed.
	var cross_index := plan._index_at(cross_axis, along) + (1 if dir > 0 else 0)
	var cross_pos := plan.road_pos(cross_axis, cross_index)
	var node := Vector2i(index, cross_index) if axis == CityPlan.AXIS_X else Vector2i(cross_index, index)
	var cw := plan.road_width(cross_axis, cross_index)
	var to_centre := (cross_pos - along) * float(dir)
	# Where the nose has to stop for this intersection: > 0 while it is still short of the line.
	var to_line := to_centre - cw * 0.5 - stop_line_back - half
	if t.get("node", Vector2i(-999999, -999999)) != node:
		# A new intersection coming up: roll the turn once, forget the last one's lights.
		t.node = node
		t.turn = 0
		# Where the road ahead is closed (a landmark's site, CityPlan.road_open) the car has to
		# turn, onto an arm that is open, or come back the way it came (turn 2). Each arm is
		# looked at just past the other road's carriageway: inside the crossing it always reads open.
		var lane_here: float = plan.road_pos(axis, index)
		var past_cross := cw * 0.5 + 3.0
		var past_here := plan.road_width(axis, index) * 0.5 + 3.0
		var ahead_open := plan.road_open(axis, index, cross_pos + dir * past_cross)
		# Remembered so a blocked turn knows whether going straight on is allowed at all.
		t.forced = not ahead_open
		if not ahead_open or (_rng.randf() < turn_chance and not t.has("no_turns")):
			var nd := 1 if _rng.randf() < 0.5 else -1
			if not plan.road_open(cross_axis, cross_index, lane_here + nd * past_here):
				nd = -nd
			if plan.road_open(cross_axis, cross_index, lane_here + nd * past_here):
				t.turn = nd
			elif not ahead_open:
				t.turn = 2
		t.amber_go = false
		t.sign_ok = false
		t.sign_t = 0.0
	# Slow for the turn: never faster than a turn_speed arrival at the centre allows.
	if int(t.turn) != 0 and to_centre > 0.0:
		v0 = minf(v0, sqrt(turn_speed * turn_speed + 2.0 * brake_comfort * to_centre))
	var acc := maxf(accel * (1.0 - pow(v / maxf(v0, 0.1), 4.0)), -brake_comfort)
	# Most the nose may move this tick before it touches something, and how much slack is left
	# before the nearest thing standing still ahead.
	var room := INF
	var still := INF
	if leader != null:
		var lt: Dictionary = leader.traffic
		var gap: float = (float(lt.along) - along) * dir - half - float(lt.get("half", 2.4))
		var lead_v := float(lt.get("v", 0.0))
		acc = minf(acc, _idm(v, v0, gap, lead_v, min_gap))
		room = minf(room, gap - 0.4)
		if lead_v < 0.3:
			still = minf(still, gap - min_gap)
	if to_line > -0.6 and (_must_stop(t, node, axis, to_line, v, delta) or Pedestrian.crosswalk_busy(node, axis, -dir)):
		acc = minf(acc, _idm(v, v0, to_line, 0.0, 0.3))
		room = minf(room, to_line + 0.3)
		still = minf(still, to_line - 0.3)
	# Somebody on the crosswalk on the far side of this intersection: wait in the box, short of it.
	var to_far := to_centre + cw * 0.5 + 0.15 - half
	if to_far > -0.4 and to_far < 40.0 and Pedestrian.crosswalk_busy(node, axis, dir):
		acc = minf(acc, _idm(v, v0, to_far, 0.0, 0.2))
		room = minf(room, to_far + 0.2)
		still = minf(still, to_far - 0.2)
	# And the far crosswalk of the intersection just crossed, until the nose is over it.
	var prev_index := cross_index - dir
	var prev_pos := plan.road_pos(cross_axis, prev_index)
	var to_prev_far := (prev_pos - along) * float(dir) + plan.road_width(cross_axis, prev_index) * 0.5 + 0.15 - half
	if to_prev_far > -0.4:
		var pnode := Vector2i(index, prev_index) if axis == CityPlan.AXIS_X else Vector2i(prev_index, index)
		if Pedestrian.crosswalk_busy(pnode, axis, dir):
			acc = minf(acc, _idm(v, v0, to_prev_far, 0.0, 0.2))
			room = minf(room, to_prev_far + 0.2)
			still = minf(still, to_prev_far - 0.2)
	# The player, on foot or in a car, standing in this lane ahead.
	if not _player_block.is_empty():
		var rel: Vector3 = (_player_block[0] as Vector3) - (t.wp as Vector3)
		var ahead := (rel.z if axis == CityPlan.AXIS_X else rel.x) * float(dir)
		var lateral := absf(rel.x if axis == CityPlan.AXIS_X else rel.z)
		if ahead > 0.0 and ahead < 45.0 and absf(rel.y) < 3.0 and lateral < float(_player_block[1]):
			var pgap := ahead - half - float(_player_block[2])
			acc = minf(acc, maxf(_idm(v, v0, pgap, 0.0, min_gap), -player_brake))
			if _player_block[3]:
				room = minf(room, pgap - 0.4)
	# A siren behind on this carriageway: pull toward the kerb and stop until it has gone by.
	for s: Array in _sirens:
		if int(s[0]) == axis and int(s[1]) == index and int(s[2]) == dir:
			var behind := (along - float(s[3])) * float(dir)
			if behind > 0.0 and behind < siren_yield_distance:
				t.yield_t = 1.2
	var yielding: float = t.get("yield_t", 0.0)
	if yielding > 0.0:
		t.yield_t = yielding - delta
		acc = minf(acc, -minf(brake_comfort, v * 1.5))
	t.shift = move_toward(float(t.get("shift", 0.0)), siren_shift if yielding > 0.0 else 0.0, delta * (1.4 if yielding > 0.0 else 0.7))
	acc = maxf(acc, -brake_max)
	var nv := maxf(v + acc * delta, 0.0)
	# Closed up on something standing still: stand still too. The model on its own creeps the
	# last few centimetres toward its gap for ever, and a queue that never quite stops reads as
	# cars that cannot make up their minds.
	if v < 0.8 and still < 1.2:
		nv = 0.0
	var step := nv * delta
	if step > room:
		step = maxf(room, 0.0)
		nv = minf(nv, step / delta)
	var new_along := along + float(dir) * step
	t.v = nv
	car.traffic_speed = nv
	var wp: Vector3 = t.wp
	if int(t.turn) == 2 and to_centre > 0.0 and step >= to_centre:
		# A dead end both ways: back the way it came, on the other carriageway, a little short of
		# the crossing so it is not reached again at once - once that carriageway has room there.
		# It used to be dropped in unasked, so two cars U-turning back to back landed one inside
		# the other (CI 279: a -3.8 m gap).
		var back_lane := _lane_offset(axis, index, -dir)
		var at := cross_pos - dir * 0.5
		var back_key := lane_key(axis, index, -dir, back_lane)
		if _group_clear(groups, back_key, at, half + 4.4):
			t.dir = -dir
			t.lane = back_lane
			t.turn = 0
			t.node = Vector2i(-999999, -999999)
			t.along = at
			_join_group(groups, back_key, car)
			var back := Vector2(plan.road_pos(axis, index) + t.lane, at) if axis == CityPlan.AXIS_X else Vector2(at, plan.road_pos(axis, index) + t.lane)
			_place(car, WorldState.to_local(Vector3(back.x, 0.55 + _relief(back), back.y)), _heading(axis, -dir), 0.0)
			return
		new_along = along + float(dir) * maxf(to_centre - 0.05, 0.0)
		t.v = 0.0
		car.traffic_speed = 0.0
	elif int(t.turn) != 0 and to_centre > 0.0 and step >= to_centre:
		# At the centre of the intersection: onto the cross street, if its lane has room here.
		var new_dir: int = t.turn
		var lane := _lane_offset(cross_axis, cross_index, new_dir)
		var at_along := wp.x if cross_axis == CityPlan.AXIS_Z else wp.z
		var new_key := lane_key(cross_axis, cross_index, new_dir, lane)
		if _group_clear(groups, new_key, at_along, half + 4.4):
			# Counted in its new lane at once: `groups` is built at the start of the tick, and a
			# second car turning into the same lane in the same tick saw it empty.
			t.along = at_along
			_join_group(groups, new_key, car)
			t.axis = cross_axis
			t.index = cross_index
			t.dir = new_dir
			t.lane = lane
			t.turn = 0
			t.node = Vector2i(-999999, -999999)
			var road := plan.road_pos(cross_axis, cross_index)
			# Rebuild the world position on the new road, keeping the intersection's coordinate.
			var pos2 := Vector2(wp.x, road + lane) if cross_axis == CityPlan.AXIS_Z else Vector2(road + lane, wp.z)
			_place(car, WorldState.to_local(Vector3(pos2.x, 0.55 + _relief(pos2), pos2.y)), _heading(cross_axis, new_dir), 0.0)
			return
		if t.get("forced", false):
			# The road ahead is closed and the lane it must turn into is taken: wait at the centre
			# of the crossing until it clears. This used to drop the turn and drive straight on,
			# so whenever a car had to turn off a closed road at a busy corner - MacArthur Park's
			# streets - it went straight into it, and on down the closed road through the lake.
			new_along = along + float(dir) * maxf(to_centre - 0.05, 0.0)
			t.v = 0.0
			car.traffic_speed = 0.0
		else:
			t.turn = 0
	var lane_pos: float = plan.road_pos(axis, index) + float(t.lane) + signf(float(t.lane)) * float(t.shift)
	var new_wp := Vector3(lane_pos, wp.y, new_along) if axis == CityPlan.AXIS_X else Vector3(new_along, wp.y, lane_pos)
	# Follow the city's rolling ground and pitch the nose along the slope ahead.
	var here := _relief(Vector2(new_wp.x, new_wp.z))
	var forward := Vector3(0.0, 0.0, dir) if axis == CityPlan.AXIS_X else Vector3(dir, 0.0, 0.0)
	var ahead_h := _relief(Vector2(new_wp.x + forward.x * 4.0, new_wp.z + forward.z * 4.0))
	new_wp.y = 0.55 + here
	_place(car, WorldState.to_local(new_wp), _heading(axis, dir), atan2(ahead_h - here, 4.0))


## The Intelligent Driver Model's acceleration toward something `gap` metres ahead of the nose
## moving at `lead_v`, stopping `stop_gap` short of it.
func _idm(v: float, v0: float, gap: float, lead_v: float, stop_gap: float) -> float:
	var want := stop_gap + maxf(0.0, v * time_gap + v * (v - lead_v) / (2.0 * sqrt(accel * brake_comfort)))
	var free := 1.0 - pow(v / maxf(v0, 0.1), 4.0)
	return accel * (free - pow(want / maxf(gap, 0.05), 2.0))


## Whether a car has to stop at `node`'s line: a red, an amber it can stop for in time, or a stop
## sign it has not yet stood at. Police cruisers never ask (they drive their own lanes).
func _must_stop(t: Dictionary, node: Vector2i, axis: int, to_line: float, v: float, delta: float) -> bool:
	var kind: int = plan.intersection(node.x, node.y).kind
	if kind == CityPlan.Intersection.SIGNALS:
		if t.get("amber_go", false):
			return false
		match TrafficSignals.light(plan, node.x, node.y, axis):
			TrafficSignals.Light.RED:
				return true
			TrafficSignals.Light.AMBER:
				if to_line > v * v / (2.0 * brake_comfort * amber_margin):
					return true
				# Too close to stop: through it, and no changing its mind half way.
				t.amber_go = true
		return false
	if kind == CityPlan.Intersection.STOP_SIGNS:
		if t.get("sign_ok", false):
			return false
		if to_line < 1.2 and v < 0.5:
			t.sign_t = float(t.get("sign_t", 0.0)) + delta
			if float(t.sign_t) >= stop_sign_wait:
				t.sign_ok = true
				return false
		return true
	return false


## Counts `car` in lane group `key` for the rest of this tick (it has just entered that lane).
func _join_group(groups: Dictionary, key: int, car: Vehicle) -> void:
	if not groups.has(key):
		groups[key] = []
	(groups[key] as Array).append(car)


## True when no car of lane group `key` is within `clear` metres of `along` (this tick's groups).
func _group_clear(groups: Dictionary, key: int, along: float, clear: float) -> bool:
	for other in groups.get(key, []):
		if absf(float((other as Vehicle).traffic.along) - along) < clear:
			return false
	return true


## Police cruisers on the lanes with their sirens going.
func _siren_list() -> Array:
	var out: Array = []
	if _police == null or not is_instance_valid(_police):
		_police = get_tree().get_first_node_in_group("wanted") as Police
	if _police == null or _police.stars <= 0:
		return out
	for c in _police.cruisers:
		if is_instance_valid(c) and c.is_traffic() and c.is_inside_tree() and c.siren_running() and c.traffic.has("axis"):
			var wp := WorldState.to_world(c.global_position)
			out.append([int(c.traffic.axis), int(c.traffic.index), int(c.traffic.dir), wp.z if int(c.traffic.axis) == CityPlan.AXIS_X else wp.x])
	return out


## The player as something in the road: [true world position, how far to the side of a lane
## still counts, half its length, whether cars must never touch it]. A car is solid (cars queue
## behind it); a person on foot is braked for but can still be hit.
func _player_in_lanes() -> Array:
	var p := _player as Player
	if p == null or not p.is_inside_tree():
		return []
	if p.is_driving() and is_instance_valid(p.vehicle):
		return [WorldState.to_world(p.vehicle.global_position), 2.1, 2.4, true]
	return [WorldState.to_world(p.global_position), 1.4, 0.4, false]


## MacroMap.relief_at through the same lattice and bilinear blend CityChunk._gy() lays the roads
## with, so a car sits on the asphalt that is actually drawn - and reads cached samples instead of
## evaluating the mountain noise twice per car per step, which was most of the traffic's cost.
var _relief_cache: Dictionary = {}


func _relief(p: Vector2) -> float:
	var fx := p.x / CityChunk.RELIEF_STEP
	var fz := p.y / CityChunk.RELIEF_STEP
	var i := floori(fx)
	var j := floori(fz)
	var tx := fx - float(i)
	var tz := fz - float(j)
	return lerpf(
		lerpf(_relief_sample(i, j), _relief_sample(i + 1, j), tx),
		lerpf(_relief_sample(i, j + 1), _relief_sample(i + 1, j + 1), tx), tz)


func _relief_sample(i: int, j: int) -> float:
	var key := Vector2i(i, j)
	var cached: Variant = _relief_cache.get(key)
	if cached != null:
		return cached
	# Lanes are fixed lines, so this stays small; the cap only stops a long drive growing it.
	if _relief_cache.size() > 40000:
		_relief_cache.clear()
	var h := plan.macro.relief_at(Vector2(i * CityChunk.RELIEF_STEP, j * CityChunk.RELIEF_STEP))
	_relief_cache[key] = h
	return h


## Puts a traffic car at `pos` facing `yaw`, nose pitched by `pitch`, in ONE transform write.
## Setting the position and then each rotation separately was four writes a car a step, and each
## one pushes a transform change down every child the car has - body, glass, lights, twelve wheel
## and caliper meshes - to the renderer and the physics server. Same result, a quarter of the work.
func _place(car: Vehicle, pos: Vector3, yaw: float, pitch: float) -> void:
	car.global_transform = Transform3D(Basis.from_euler(Vector3(pitch, yaw, 0.0)), pos)


# --- Airport drop-off loop -----------------------------------------------------------------

func _loop_length(points: PackedVector2Array) -> float:
	var total := 0.0
	for i in points.size():
		total += points[i].distance_to(points[(i + 1) % points.size()])
	return total


## Position and direction at distance `t` along the closed polyline.
func _loop_point(points: PackedVector2Array, t: float) -> Array:
	var total := _loop_length(points)
	t = fposmod(t, total)
	for i in points.size():
		var a := points[i]
		var b := points[(i + 1) % points.size()]
		var seg := a.distance_to(b)
		if t <= seg:
			return [a.lerp(b, t / seg), (b - a) / seg]
		t -= seg
	return [points[0], Vector2(1.0, 0.0)]


func _maintain_loops(pw: Vector3) -> void:
	var macro: MacroMap = plan.macro
	if macro == null:
		return
	for car in loop_cars.duplicate():
		if not is_instance_valid(car) or not car.is_traffic():
			loop_cars.erase(car)
	var curb: Rect2 = macro.terminal_curb
	var near := Vector2(pw.x, pw.z).distance_to(curb.get_center()) < loop_active_distance
	if not near:
		for car in loop_cars:
			_retire(car)
		loop_cars.clear()
		return
	if loop_cars.size() >= max_loop_cars or not PhysicsBudget.can_spawn():
		return
	if _loop_lengths.is_empty():
		for loop: PackedVector2Array in macro.terminal_loops:
			_loop_lengths.append(_loop_length(loop))
	# Fill every loop evenly, a few cars per maintenance tick, at free slots only.
	var added := 0
	var loops: int = macro.terminal_loops.size()
	for i in loops:
		var per_loop := max_loop_cars / loops
		var slots := int(_loop_lengths[i] / loop_gap)
		per_loop = mini(per_loop, slots)
		var taken := {}
		for car in loop_cars:
			if car.traffic.loop == i:
				taken[int(car.traffic.t / loop_gap)] = true
		for slot in slots:
			if taken.size() >= per_loop or added >= 12:
				break
			if taken.has(slot):
				continue
			_spawn_queues[1].append(_spawn_loop_car.bind(i, slot * loop_gap))
			taken[slot] = true
			added += 1


func _spawn_loop_car(loop_index: int, t: float) -> void:
	var macro: MacroMap = plan.macro
	var loop: PackedVector2Array = macro.terminal_loops[loop_index]
	var at := _loop_point(loop, t)
	var pos2: Vector2 = at[0]
	var dir2: Vector2 = at[1]
	var car := _new_car()
	car.traffic = {"loop": loop_index, "t": t, "speed": loop_speed * _rng.randf_range(0.85, 1.1)}
	car.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	car.freeze = true
	_enter_at(car, WorldState.to_local(Vector3(pos2.x, 0.55 + macro.dropoff_top, pos2.y)), atan2(-dir2.x, -dir2.y), 0.0)
	car.traffic_speed = car.traffic.speed
	loop_cars.append(car)


## Bumper-to-bumper crawl: each car closes up to the one ahead and stops short of it.
func _drive_loops(delta: float) -> void:
	if loop_cars.is_empty():
		return
	var macro: MacroMap = plan.macro
	var by_loop := {}
	for car in loop_cars.duplicate():
		if not is_instance_valid(car) or not car.is_traffic():
			loop_cars.erase(car)
			continue
		var i: int = car.traffic.loop
		if not by_loop.has(i):
			by_loop[i] = []
		(by_loop[i] as Array).append(car)
	for i in by_loop:
		var group: Array = by_loop[i]
		group.sort_custom(func(a: Vehicle, b: Vehicle) -> bool: return a.traffic.t < b.traffic.t)
		var loop: PackedVector2Array = macro.terminal_loops[i]
		var total: float = _loop_lengths[i] if i < _loop_lengths.size() else _loop_length(loop)
		for k in group.size():
			var car: Vehicle = group[k]
			var ahead: Vehicle = group[(k + 1) % group.size()]
			var gap: float = fposmod(ahead.traffic.t - car.traffic.t, total) if ahead != car else total
			var speed: float = minf(car.traffic.speed, maxf(0.0, (gap - loop_gap * 0.75) * 1.5))
			car.traffic.t = fposmod(car.traffic.t + speed * delta, total)
			car.traffic_speed = speed
			var at := _loop_point(loop, car.traffic.t)
			var pos2: Vector2 = at[0]
			var dir2: Vector2 = at[1]
			_place(car, WorldState.to_local(Vector3(pos2.x, 0.55 + macro.dropoff_top, pos2.y)), atan2(-dir2.x, -dir2.y), 0.0)


# --- Freeway traffic ------------------------------------------------------------------------
#
# The decks are open polylines with a height profile, not the flat closed loops the airport
# drop-off uses, so cars carry a signed direction and are recycled when they reach an end
# rather than wrapping. Everything is driven by distance along the route (Freeway.point_at),
# because the route's points are a fixed step along the drawn curve and not along the ground.

## Middle of each lane, as a fraction of the deck half-width, per direction. Two lanes each way
## with the median between them.
const FW_LANES := [0.28, 0.62]


func _freeway() -> Freeway:
	if plan == null or plan.macro == null:
		return null
	return plan.macro.freeway


func _maintain_freeway() -> void:
	var fw := _freeway()
	if fw == null or fw.routes.is_empty():
		return
	var pw := WorldState.to_world(_player.global_position)
	var here := Vector2(pw.x, pw.z)
	for car in freeway_cars.duplicate():
		if not is_instance_valid(car) or not car.is_traffic():
			freeway_cars.erase(car)
			continue
		# Off the end of its route, or the player has left it behind.
		var ri: int = car.traffic.fw
		var t: float = car.traffic.t
		if t <= 0.0 or t >= fw.length_of(ri) or absf(t - _fw_anchor(ri, here)) > freeway_range * 1.35:
			freeway_cars.erase(car)
			_retire(car)
	if freeway_cars.size() >= max_freeway_cars or not PhysicsBudget.can_spawn():
		return
	# Which routes are close enough to bother with, and where along each the player is.
	var live: Array[Vector2i] = []
	for ri in fw.routes.size():
		var near: Array = fw.nearest_on(ri, here)
		if float(near[1]) < freeway_range:
			live.append(Vector2i(ri, int(near[0])))
	if live.is_empty():
		return
	var per_route := maxi(1, max_freeway_cars / live.size())
	var added := 0
	for entry in live:
		var ri: int = entry.x
		var anchor := float(entry.y)
		var total := fw.length_of(ri)
		var on_route := 0
		var taken := {}
		for car in freeway_cars:
			if car.traffic.fw == ri:
				on_route += 1
				taken[Vector2i(int(car.traffic.t / freeway_gap), int(car.traffic.dir))] = true
		var lo := maxf(0.0, anchor - freeway_range)
		var hi := minf(total, anchor + freeway_range)
		var slot := int(lo / freeway_gap)
		while on_route < per_route and added < 10 and float(slot) * freeway_gap < hi:
			var t := float(slot) * freeway_gap
			for dir: int in [1, -1]:
				if on_route >= per_route or added >= 10:
					break
				var key := Vector2i(slot, dir)
				if taken.has(key) or _rng.randf() < 0.35:
					continue
				_spawn_queues[2].append(_spawn_freeway_car.bind(ri, t, dir))
				taken[key] = true
				on_route += 1
				added += 1
			slot += 1


## Where along route `ri` the player is, in metres. Cheap enough at the 0.5 s maintenance tick.
func _fw_anchor(ri: int, here: Vector2) -> float:
	var fw := _freeway()
	if fw == null:
		return 0.0
	return float(fw.nearest_on(ri, here)[0])


func _spawn_freeway_car(ri: int, t: float, dir: int) -> void:
	var fw := _freeway()
	var lane: float = FW_LANES[_rng.randi() % FW_LANES.size()] * float(dir)
	var car := _new_car()
	car.traffic = {
		"fw": ri, "t": t, "dir": dir, "lane": lane,
		"speed": freeway_speed * _rng.randf_range(0.88, 1.12),
	}
	car.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	car.freeze = true
	# Placed in this node's space, then into the tree: writing global_position on a node outside
	# the tree had nothing to resolve it against (Godot logged an error 253 times a run and the
	# car was placed relative to nothing), and placing it after add_child() is the aircraft trap
	# (see _enter_at()).
	car.transform = global_transform.affine_inverse() * _freeway_xform(car, fw)
	add_child(car)
	car.traffic_speed = car.traffic.speed
	freeway_cars.append(car)


## Put a car where its own (route, t, lane, dir) say it should be, on top of the deck.
func _place_freeway_car(car: Vehicle, fw: Freeway) -> void:
	car.global_transform = _freeway_xform(car, fw)


## Where _place_freeway_car() puts a car, as a scene-space transform.
func _freeway_xform(car: Vehicle, fw: Freeway) -> Transform3D:
	var at: Array = fw.point_at(car.traffic.fw, car.traffic.t)
	var p: Vector3 = at[0]
	var d: Vector2 = at[1]
	var half: float = float(fw.routes[car.traffic.fw].width) * 0.5
	var nrm := Vector2(-d.y, d.x) * (float(car.traffic.lane) * half)
	var heading: Vector2 = d * float(car.traffic.dir)
	# Nose up the grade. Placed level, a car on a sloped deck sank its front or back wheels into
	# it, and its headlight beam - flat in the car's own frame - cut into the asphalt along a
	# hard line a few metres ahead.
	var step := 2.5 * float(car.traffic.dir)
	var ahead: float = (fw.point_at(car.traffic.fw, car.traffic.t + step)[0] as Vector3).y
	var behind: float = (fw.point_at(car.traffic.fw, car.traffic.t - step)[0] as Vector3).y
	return Transform3D(Basis.from_euler(Vector3(atan2(ahead - behind, 5.0), atan2(-heading.x, -heading.y), 0.0)), WorldState.to_local(Vector3(p.x + nrm.x, p.y + 0.71, p.z + nrm.y)))


## Cruise, closing up on whatever is ahead in the same lane and direction.
func _drive_freeway(delta: float) -> void:
	if freeway_cars.is_empty():
		return
	var fw := _freeway()
	if fw == null:
		return
	# Group by route, direction and lane, so a car only follows the one actually in front of it.
	var groups := {}
	for car in freeway_cars.duplicate():
		if not is_instance_valid(car) or not car.is_traffic():
			freeway_cars.erase(car)
			continue
		var key := Vector3(float(car.traffic.fw), float(car.traffic.dir), float(car.traffic.lane))
		if not groups.has(key):
			groups[key] = []
		(groups[key] as Array).append(car)
	for key in groups:
		var group: Array = groups[key]
		var dir: int = int((key as Vector3).y)
		# Sort by how far along each car is in its own direction of travel.
		group.sort_custom(func(a: Vehicle, b: Vehicle) -> bool:
			return (a.traffic.t < b.traffic.t) if dir > 0 else (a.traffic.t > b.traffic.t))
		for k in group.size():
			var car: Vehicle = group[k]
			var speed: float = car.traffic.speed
			if k + 1 < group.size():
				var ahead: Vehicle = group[k + 1]
				var gap: float = absf(float(ahead.traffic.t) - float(car.traffic.t))
				speed = minf(speed, maxf(0.0, (gap - freeway_gap * 0.6) * 1.4))
			car.traffic.t = float(car.traffic.t) + float(dir) * speed * delta
			car.traffic_speed = speed
			_place_freeway_car(car, fw)
