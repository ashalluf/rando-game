class_name Emergency
extends Node3D
## The fire department and the ambulances (2026-10-04: "a real city sends fire and medics").
## One node in the city scene, in the group "emergency", modelled on Police: it watches for what
## the player leaves behind, opens a call for it, sends a unit through the traffic with lights
## and siren, and the unit pulls up at the kerb nearest the scene and its crew does the job.
##
## Calls (`incidents`), looked for every `scan_interval` within `call_radius` of the player:
##   fire   a car burning or burnt out and still in flames (CarDamage's own lists): an engine,
##          whose crew runs a hose line from the pump panel and puts it out
##          (CarDamage.extinguish()); the wreck is held burning (CarDamage.hold_fire) until the
##          engine gets there or `hold_seconds` runs out, so there is a fire to put out.
##   blast  a big blast with no burning car at it (Explosion.blast_count): an engine stands by.
##   down   a body on the street (a Ragdoll, PhysicsBudget's debris): an ambulance, whose
##          paramedics kneel at it with a bag, bring the stretcher and take it away. The body is
##          kept (its debris clock held) while they work.
## Units come out of the nearest fire station within `station_reach` (FireStation: the bay door
## opens and the unit pulls out onto the street in front) or, with none in reach, join along a
## street `spawn_min`..`spawn_max` out of sight like the police. Caps `max_engines` /
## `max_ambulances`; units are pooled. Their crews are Pedestrians (EmergencyCrew): shot,
## knocked and ragdolled like anyone, which is a crime like anyone's (Police.person_down).
## When the job is done the crew climbs back in and the unit drives off; nobody seeing it, it
## goes back into the pool.
##
## Coordinates: incident positions are TRUE world positions (WorldState); the units and crews
## are ordinary nodes under this one with scene positions.

@export var enabled: bool = true
@export_group("Calls")
## How often the street is looked over for new calls (s), and how far from the player a call
## is taken (m).
@export var scan_interval: float = 1.0
@export var call_radius: float = 240.0
## Seconds from a call to a unit being sent (somebody has to phone it in).
@export var response_delay: float = 2.5
## A burning wreck with an engine on the way keeps burning this long at most (s).
@export var hold_seconds: float = 120.0
## A body is attended only if it is this fresh (s) when the call is taken.
@export var down_fresh: float = 25.0
## A blast this close to a fire call is that call (m).
@export var merge_radius: float = 25.0
## Seconds an engine stands by at a blast with nothing burning.
@export var stand_by_seconds: float = 14.0
## Seconds a crew lingers after the job before climbing back in.
@export var linger_seconds: float = 4.0
@export_group("Response")
@export var max_engines: int = 2
@export var max_ambulances: int = 2
@export var dispatch_interval: float = 1.2
## A station this close to a call sends its unit (m); farther, the unit comes in off the map.
@export var station_reach: float = 700.0
@export var spawn_min: float = 160.0
@export var spawn_max: float = 230.0
@export var despawn_distance: float = 330.0
@export var pool_size: int = 4
## An ambulance parked in a hospital's bay goes back into the pool after this long unseen (s).
@export var park_seconds: float = 45.0
## Web builds: fewer of everything.
@export var web_scale: float = 0.5

const KIND_FIRE := "fire"
const KIND_BLAST := "blast"
const KIND_DOWN := "down"

var incidents: Array[Dictionary] = []
var units: Array[EmergencyCar] = []
var crews: Array[EmergencyCrew] = []
var plan: CityPlan
var traffic: TrafficManager
## Units sent since the start (tests read it).
var dispatched: int = 0

var _player: Node3D
var _pool: Array[EmergencyCar] = []
var _rng := RandomNumberGenerator.new()
var _scan_t: float = 0.0
var _dispatch_t: float = 0.0
var _upkeep_t: float = 0.0
var _blasts_seen: int = 0
var _next_id: int = 1


## The Emergency node in the scene, or null.
static func find(tree: SceneTree) -> Emergency:
	if tree == null:
		return null
	return tree.get_first_node_in_group("emergency") as Emergency


func _ready() -> void:
	add_to_group("emergency")
	_rng.seed = hash(["emergency", Time.get_ticks_usec()])
	_blasts_seen = Explosion.blast_count
	if OS.has_feature("web"):
		max_engines = maxi(1, int(round(max_engines * web_scale)))
		max_ambulances = maxi(1, int(round(max_ambulances * web_scale)))


func _ensure_refs() -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
	var city := get_parent()
	if plan == null and city and city.get("plan") != null:
		plan = city.plan
	if traffic == null and city:
		traffic = city.get_node_or_null("Traffic") as TrafficManager


func _exit_tree() -> void:
	for car in _pool:
		if is_instance_valid(car):
			car.free()
	_pool.clear()


func _physics_process(delta: float) -> void:
	if not enabled:
		return
	_ensure_refs()
	if _player == null or plan == null:
		return
	_scan_t -= delta
	if _scan_t <= 0.0:
		_scan_t = scan_interval
		_scan()
	_upkeep_t -= delta
	if _upkeep_t <= 0.0:
		_upkeep_t = 0.5
		_upkeep(0.5)
	_dispatch_t -= delta
	if _dispatch_t <= 0.0:
		_dispatch_t = dispatch_interval
		_dispatch()


# --- Calls -------------------------------------------------------------------------------------

## New calls: cars on fire, big blasts, bodies.
func _scan() -> void:
	var pp := _player.global_position
	# Cars burning, or burnt out with the fire still going.
	for list: Array in [CarDamage._burning, CarDamage._wrecks]:
		for item in list:
			var car: Vehicle = (item as CarDamage).car if item is CarDamage else item as Vehicle
			if car == null or not is_instance_valid(car) or not car.is_inside_tree() or car is EmergencyCar:
				continue
			var dmg := car._damage
			if dmg == null or not is_instance_valid(dmg) or not dmg.on_fire():
				continue
			if car.global_position.distance_to(pp) > call_radius or _incident_for(car) != null:
				continue
			var inc := _open(KIND_FIRE, car.global_position)
			inc.car = car
			dmg.hold_fire(hold_seconds)
	# A big blast: an engine to stand by unless a fire call covers it.
	if Explosion.blast_count != _blasts_seen:
		_blasts_seen = Explosion.blast_count
		var at := WorldState.to_local(Explosion.last_blast_world)
		if at.distance_to(pp) < call_radius and _near_call(at, merge_radius, KIND_FIRE) == null \
				and _near_call(at, merge_radius, KIND_BLAST) == null:
			_open(KIND_BLAST, at)
	# Bodies (Ragdoll roots are PhysicsBudget debris); not our own people.
	var now := Time.get_ticks_msec() / 1000.0
	for node in get_tree().get_nodes_in_group(PhysicsBudget.DEBRIS_GROUP):
		var doll := node as Ragdoll
		if doll == null or doll.is_queued_for_deletion() or doll.has_meta("responder") or doll.has_meta("attended"):
			continue
		if now - float(doll.get_meta("spawn_time", now)) > down_fresh or doll.bodies.is_empty():
			continue
		var at := (doll.bodies[0] as Node3D).global_position
		if at.distance_to(pp) > call_radius:
			continue
		doll.set_meta("attended", true)
		var inc := _open(KIND_DOWN, at)
		inc.doll = doll
		# Kept while the call is open (its debris clock re-started, and given time to be seen to).
		doll.set_meta("spawn_time", now)
		doll.set_meta("debris_life", hold_seconds)


func _open(kind: String, at: Vector3) -> Dictionary:
	var inc := {"id": _next_id, "kind": kind, "world": WorldState.to_world(at), "opened": Time.get_ticks_msec() / 1000.0,
		"car": null, "doll": null, "engine": null, "ambulance": null, "done": false, "done_t": 0.0,
		"on_scene_t": 0.0, "water": 0.0, "loaded": false}
	_next_id += 1
	incidents.append(inc)
	return inc


func _incident_for(car: Vehicle) -> Variant:
	for inc in incidents:
		if inc.car == car:
			return inc
	return null


func _near_call(at: Vector3, r: float, kind: String) -> Variant:
	var w := WorldState.to_world(at)
	for inc in incidents:
		if inc.kind == kind and (inc.world as Vector3).distance_to(w) < r:
			return inc
	return null


## Where a call is now (scene position): the burning car or the body where they are now.
func scene_point(inc: Dictionary) -> Vector3:
	if inc.kind == KIND_FIRE and is_instance_valid(inc.car):
		return (inc.car as Vehicle).global_position
	if inc.kind == KIND_DOWN and is_instance_valid(inc.doll) and not (inc.doll as Ragdoll).bodies.is_empty():
		# The body's middle (the hips), not its origin: a lying ragdoll's origin is its feet, and a
		# medic sent beside the feet of a body that lay toward him was stopped by its box short of
		# them (the kneel test missed by 9 cm in a full suite run).
		return (inc.doll as Ragdoll)._pelvis()
	return WorldState.to_local(inc.world)


## True while a fire call's car still burns.
func still_burning(inc: Dictionary) -> bool:
	if not is_instance_valid(inc.car):
		return false
	var dmg: CarDamage = (inc.car as Vehicle)._damage
	return dmg != null and is_instance_valid(dmg) and dmg.on_fire()


## Water on a fire call's car from the hose (s of spray): CarDamage puts it out past its need.
func water_on(inc: Dictionary, seconds: float) -> void:
	inc.water = float(inc.water) + seconds
	if not is_instance_valid(inc.car):
		return
	var dmg: CarDamage = (inc.car as Vehicle)._damage
	if dmg != null and is_instance_valid(dmg):
		dmg.douse(seconds)


# --- Units -------------------------------------------------------------------------------------

func _cap(kind: EmergencyCar.Kind) -> int:
	return max_engines if kind == EmergencyCar.Kind.ENGINE else max_ambulances


func _count(kind: EmergencyCar.Kind) -> int:
	var n := 0
	for u in units:
		if is_instance_valid(u) and u.kind == kind:
			n += 1
	return n


## Sends a unit to each call that needs one and has none, inside the caps.
func _dispatch() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	for inc in incidents:
		if inc.done or now - float(inc.opened) < response_delay:
			continue
		var want := EmergencyCar.Kind.AMBULANCE if inc.kind == KIND_DOWN else EmergencyCar.Kind.ENGINE
		var slot := "ambulance" if want == EmergencyCar.Kind.AMBULANCE else "engine"
		if inc[slot] != null and is_instance_valid(inc[slot]):
			continue
		if _count(want) >= _cap(want) or not PhysicsBudget.make_room(1):
			continue
		var car := send(want, inc)
		if car != null:
			inc[slot] = car
			return # one a tick


## Sends a unit of `kind` to `inc` now: out of the nearest station, else along a street out of
## sight. Returns it, or null when there was nowhere to bring it in.
func send(kind: EmergencyCar.Kind, inc: Dictionary) -> EmergencyCar:
	_ensure_refs()
	var w: Vector3 = inc.world
	var goal := Vector2(w.x, w.z)
	var start: Array = []
	var station := FireStation.nearest(plan, goal, station_reach)
	if not station.is_empty():
		start = FireStation.exit_lane(plan, station, goal)
	if start.is_empty():
		start = _street_start(goal)
	if start.is_empty():
		return null
	var car := _take(kind)
	car.service = self
	car.incident = inc
	car.station = station if not station.is_empty() and start.size() > 4 else {}
	car.goal = goal
	car.begin_drive(plan, start[0], start[1], start[2], 6.0 if not car.station.is_empty() else car.call_speed * 0.8)
	var p: Vector2 = start[3]
	var lane: float = car.traffic.lane
	if int(start[0]) == CityPlan.AXIS_X:
		p.x += lane
	else:
		p.y += lane
	var h := traffic._relief(p) if traffic else (plan.macro.relief_at(p) if plan.macro else 0.0)
	_enter_at(car, Transform3D(Basis(Vector3.UP, EmergencyCar.heading(start[0], start[2])),
			WorldState.to_local(Vector3(p.x, h + CityChunk.ROAD_TOP + car.road_lift(), p.y))))
	units.append(car)
	dispatched += 1
	if not car.station.is_empty():
		FireStation.open_door(get_tree(), car.station)
	return car


## A street 160-230 m from the call, out of the camera's view where it can be: [axis, index,
## dir, point (true world XZ)], or [].
func _street_start(goal: Vector2) -> Array:
	if plan.zone_at(goal) != MacroMap.Zone.CITY and plan.zone_at(goal) != MacroMap.Zone.BEACH:
		return []
	var cam := get_viewport().get_camera_3d()
	var center := plan.block_index_at(goal)
	for attempt in 14:
		var axis := _rng.randi_range(0, 1)
		var index := (center.x if axis == CityPlan.AXIS_X else center.y) + _rng.randi_range(-2, 2)
		var along0 := goal.y if axis == CityPlan.AXIS_X else goal.x
		var along := along0 + (-1.0 if _rng.randf() < 0.5 else 1.0) * _rng.randf_range(spawn_min, spawn_max)
		var road := plan.road_pos(axis, index)
		var p2 := Vector2(road, along) if axis == CityPlan.AXIS_X else Vector2(along, road)
		if plan.zone_at(p2) != MacroMap.Zone.CITY or not plan.road_open(axis, index, along):
			continue
		var local := WorldState.to_local(Vector3(p2.x, 0.0, p2.y))
		if attempt < 9 and cam and cam.is_position_in_frustum(local) and cam.global_position.distance_to(local) < 420.0:
			continue
		return [axis, index, 1 if along0 > along else -1, p2]
	return []


func _take(kind: EmergencyCar.Kind) -> EmergencyCar:
	for i in range(_pool.size() - 1, -1, -1):
		var c: EmergencyCar = _pool[i]
		if not is_instance_valid(c):
			_pool.remove_at(i)
			continue
		if c.kind == kind:
			_pool.remove_at(i)
			return c
	return EmergencyCar.make(kind, _rng)


func _enter_at(car: EmergencyCar, xf: Transform3D) -> void:
	if car.get_parent() == null:
		car.transform = global_transform.affine_inverse() * xf
		add_child(car)
	else:
		car.global_transform = xf


## A unit pulled up at the scene: its crew gets out and goes to work.
func unit_arrived(car: EmergencyCar) -> void:
	var inc := car.incident
	if inc.is_empty():
		car.leave(_away_point(car))
		return
	inc.on_scene_t = Time.get_ticks_msec() / 1000.0
	deploy_crew(car)


func deploy_crew(car: EmergencyCar) -> void:
	var n := car.crew_aboard
	for i in n:
		var c := EmergencyCrew.new()
		var role := EmergencyCrew.Role.FIRE if car.kind == EmergencyCar.Kind.ENGINE else EmergencyCrew.Role.MEDIC
		c.setup_crew(self, car, role, i, _rng.randi())
		var spot := _door_spot(car, i)
		add_child(c)
		c.global_position = spot
		crews.append(c)
		car.crew_aboard -= 1


## Beside the cab doors, then along the kerb side.
func _door_spot(car: EmergencyCar, i: int) -> Vector3:
	var base := car.global_position - Vector3.UP * car.road_lift()
	var side := car.global_basis.x
	side.y = 0.0
	side = side.normalized()
	var fwd := -car.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var half := float(car._dims().width) * 0.5 + 0.6
	var length := float(car._dims().length)
	var spots: Array[Vector3] = [
		base + side * half + fwd * (length * 0.32),
		base - side * half + fwd * (length * 0.32),
		base + side * half + fwd * (length * 0.12),
		base - side * half + fwd * (length * 0.12),
	]
	return _on_surface(spots[i % spots.size()]) + Vector3.UP * 0.05


## `p` brought down (or up) onto the world-layer surface under it: a door spot is worked out at
## road height, and the kerb side's is on the pavement - since Kerbs, a trimesh ring a kerb higher
## that a body put just under it falls straight through, five metres down to the GroundBody where
## the street stands on relief (the stretcher medic of the paramedic check, on every branch).
func _on_surface(p: Vector3) -> Vector3:
	if not is_inside_tree():
		return p
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 1.5, p - Vector3.UP * 1.0, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return hit.position if not hit.is_empty() else p


## A crew member back in their unit. With all of them in, it leaves.
func board(c: EmergencyCrew, car: EmergencyCar) -> void:
	crews.erase(c)
	c.queue_free()
	if not is_instance_valid(car):
		return
	car.crew_aboard += 1
	if car.crew_aboard >= car.crew_alive:
		_finish(car)


func crew_down(c: EmergencyCrew) -> void:
	crews.erase(c)
	if is_instance_valid(c.car):
		c.car.crew_alive = maxi(c.car.crew_alive - 1, 0)
		if c.car.crew_alive > 0 and c.car.crew_aboard >= c.car.crew_alive and c.car.mode == EmergencyCar.Mode.ON_SCENE:
			_finish(c.car)


## The unit's job is over (or it has nobody left to do it): it leaves; the call closes with it.
func _finish(car: EmergencyCar) -> void:
	var inc := car.incident
	if not inc.is_empty():
		var slot := "engine" if car.kind == EmergencyCar.Kind.ENGINE else "ambulance"
		if inc.get(slot) == car:
			inc[slot] = null
		inc.done = true
		_release(inc)
	# An ambulance with a patient aboard takes them to the nearest hospital (Hospital).
	if car.kind == EmergencyCar.Kind.AMBULANCE and bool(inc.get("loaded", false)):
		var wp := WorldState.to_world(car.global_position)
		var lay := Hospital.nearest(plan, Vector2(wp.x, wp.z))
		if not lay.is_empty():
			car.to_hospital(lay)
			return
	car.leave(_away_point(car))


func _release(inc: Dictionary) -> void:
	if inc.kind == KIND_FIRE and is_instance_valid(inc.car):
		var dmg: CarDamage = (inc.car as Vehicle)._damage
		if dmg != null and is_instance_valid(dmg):
			dmg.hold_fire(0.0)


func unit_lost(car: EmergencyCar) -> void:
	units.erase(car)
	for c in crews:
		if is_instance_valid(c) and c.car == car:
			c.car = null
	var inc := car.incident
	if not inc.is_empty():
		for slot in ["engine", "ambulance"]:
			if inc.get(slot) == car:
				inc[slot] = null


func unit_stolen(car: EmergencyCar) -> void:
	unit_lost(car)
	car.crew_aboard = 0
	car.crew_alive = 0
	car.mode = EmergencyCar.Mode.LEAVING
	var p := Police.find(get_tree())
	if p:
		p.report_crime("police_car", WorldState.to_world(car.global_position), 1.0)


func _away_point(car: EmergencyCar) -> Vector2:
	var wp := WorldState.to_world(car.global_position)
	if not car.station.is_empty():
		var s: Vector2 = car.station.front
		if s.distance_to(Vector2(wp.x, wp.z)) < station_reach * 1.5:
			return s
	var a := _rng.randf() * TAU
	return Vector2(wp.x, wp.z) + Vector2(cos(a), sin(a)) * 450.0


# --- Upkeep ------------------------------------------------------------------------------------

func _upkeep(step: float) -> void:
	var pp := _player.global_position
	var cam := get_viewport().get_camera_3d()
	var now := Time.get_ticks_msec() / 1000.0
	# Calls: closed when there is nothing left to do and nobody is on them.
	for inc in incidents.duplicate():
		var gone := false
		match String(inc.kind):
			KIND_FIRE:
				gone = not is_instance_valid(inc.car) or (not still_burning(inc) and inc.engine == null)
			KIND_DOWN:
				gone = (not is_instance_valid(inc.doll) or (inc.doll as Node).is_queued_for_deletion()) and inc.ambulance == null and not inc.loaded
			KIND_BLAST:
				gone = inc.done and inc.engine == null
		var far := WorldState.to_local(inc.world).distance_to(pp) > despawn_distance and inc.engine == null and inc.ambulance == null
		if gone or far or (inc.done and inc.engine == null and inc.ambulance == null):
			_release(inc)
			incidents.erase(inc)
			continue
		# A blast with nothing burning: the engine stands by, then goes.
		if inc.kind == KIND_BLAST and float(inc.on_scene_t) > 0.0 and now - float(inc.on_scene_t) > stand_by_seconds:
			inc.done = true
	for u in units.duplicate():
		if not is_instance_valid(u):
			units.erase(u)
			continue
		var car: EmergencyCar = u
		if car.driver != null:
			units.erase(car)
			continue
		var d := car.global_position.distance_to(pp)
		var on_screen := cam != null and d < 320.0 and cam.is_position_in_frustum(car.global_position)
		car.unseen_time = 0.0 if on_screen else car.unseen_time + step
		var crew_out := car.crew_aboard < car.crew_alive
		var retire := d > despawn_distance
		if not retire and car.mode == EmergencyCar.Mode.LEAVING and car.unseen_time > 3.0:
			retire = true
		if not retire and car.crew_alive <= 0 and car.unseen_time > 4.0:
			retire = true
		if not retire and (car.mode == EmergencyCar.Mode.DISPATCH or car.mode == EmergencyCar.Mode.ON_SCENE) and not crew_out and car.incident.get("done", false):
			car.leave(_away_point(car))
		# Parked in a hospital's bay: back to the pool once it has stood a while unseen.
		if car.mode == EmergencyCar.Mode.PARKED:
			car.parked_t += step
			if car.parked_t > park_seconds and car.unseen_time > 3.0:
				retire = true
		if retire:
			_retire(car)
	for cc in crews.duplicate():
		if not is_instance_valid(cc) or (cc as EmergencyCrew)._down:
			crews.erase(cc)
			continue
		var c: EmergencyCrew = cc
		var d := c.global_position.distance_to(pp)
		var on_screen := cam != null and d < 250.0 and cam.is_position_in_frustum(c.global_position)
		c.unseen_time = 0.0 if on_screen else c.unseen_time + step
		var car_gone := c.car == null or not is_instance_valid(c.car) or c.car.driver != null
		if d > despawn_distance or (car_gone and c.unseen_time > 3.0):
			crews.erase(c)
			c.queue_free()


func _retire(car: EmergencyCar) -> void:
	units.erase(car)
	for c in crews.duplicate():
		if is_instance_valid(c) and c.car == car:
			crews.erase(c)
			c.queue_free()
	var inc := car.incident
	if not inc.is_empty():
		for slot in ["engine", "ambulance"]:
			if inc.get(slot) == car:
				inc[slot] = null
	if not is_instance_valid(car) or car.driver != null:
		return
	if car.get_parent() == self and _pool.size() < pool_size and not car.is_queued_for_deletion() and not car.is_wreck():
		car.strip_for_pool()
		remove_child(car)
		_pool.append(car)
	else:
		car.queue_free()


## Everything off the street at once (tests, a rebuild).
func clear() -> void:
	for car in units.duplicate():
		_retire(car)
	for c in crews:
		if is_instance_valid(c):
			c.queue_free()
	crews.clear()
	for inc in incidents:
		_release(inc)
	incidents.clear()


# --- Staging -------------------------------------------------------------------------------------

## A unit already pulled up at `inc` with its crew out (tests and stills: a software frame takes
## seconds, and a unit driving in from 200 m would take hundreds of them). `along` is the kerb
## stretch StreetRoute picks, the same place a unit on a call pulls up.
func stage(kind: EmergencyCar.Kind, inc: Dictionary) -> EmergencyCar:
	_ensure_refs()
	var w: Vector3 = inc.world
	var car := _take(kind)
	car.service = self
	car.incident = inc
	car._plan = plan
	var stand := car.engine_stand_off if kind == EmergencyCar.Kind.ENGINE else car.ambulance_stand_off
	var dest := StreetRoute.kerb_stop(plan, Vector2(w.x, w.z), stand)
	if dest.is_empty():
		_pool.append(car)
		return null
	car.begin_drive(plan, int(dest.axis), int(dest.index), int(dest.dir), 0.0)
	var road := plan.road_pos(int(dest.axis), int(dest.index)) + float(dest.lateral)
	var along := float(dest.along)
	var p := Vector2(road, along) if int(dest.axis) == CityPlan.AXIS_X else Vector2(along, road)
	var h := traffic._relief(p) if traffic else 0.0
	_enter_at(car, Transform3D(Basis(Vector3.UP, EmergencyCar.heading(int(dest.axis), int(dest.dir))),
			WorldState.to_local(Vector3(p.x, h + CityChunk.ROAD_TOP + car.road_lift(), p.y))))
	units.append(car)
	dispatched += 1
	inc[("engine" if kind == EmergencyCar.Kind.ENGINE else "ambulance")] = car
	car.traffic.lane = float(dest.lateral)
	car.mode = EmergencyCar.Mode.ON_SCENE
	unit_arrived(car)
	return car


## Opens a call by hand (tests and stills): `kind` at true world `world`, about `car` or `doll`.
func open_call(kind: String, world: Vector3, car: Vehicle = null, doll: Ragdoll = null) -> Dictionary:
	var inc := _open(kind, WorldState.to_local(world))
	inc.car = car
	inc.doll = doll
	if car != null and car._damage != null:
		car._damage.hold_fire(hold_seconds)
	if doll != null:
		doll.set_meta("attended", true)
		doll.set_meta("spawn_time", Time.get_ticks_msec() / 1000.0)
		doll.set_meta("debris_life", hold_seconds)
	return inc


## A scene for tools/glshot/still_shot.gd (EMERGENCY=fire|hose|medic|station): staged in front
## of the camera `cam` and posed at once (a software frame takes seconds; a unit driving in and
## a crew walking up would take hundreds of them). fire: a wreck burning on the kerb ahead, an
## engine pulled up at it with its hose on, an ambulance at a body on the pavement behind it;
## hose: the same, framed on the nozzle; medic: a paramedic kneeling at a body, the stretcher
## coming; station: the nearest firehouse with its doors up. Returns the EYE ("x,y,z,yaw,pitch",
## true world) that frames it, or "".
func stage_for_shot(scene: String, cam: Camera3D) -> String:
	_ensure_refs()
	enabled = true
	var cw := WorldState.to_world(cam.global_position)
	var fwd := -cam.global_basis.z
	var fwd2 := Vector2(fwd.x, fwd.z).normalized()
	if scene == "station":
		var s := FireStation.nearest(plan, Vector2(cw.x, cw.z), 4000.0)
		if s.is_empty():
			return ""
		FireStation.open_door(get_tree(), s)
		var f: Dictionary = s.frame
		var out2: Vector2 = -(f.n as Vector2)
		var a2: Vector2 = f.a
		var front: Vector2 = s.front
		var e2 := front + out2 * 3.0 - a2 * 8.0
		var target := front - out2 * 15.0
		var gy := plan.height_at(e2)
		return _eye_at(Vector3(e2.x, gy + 1.7, e2.y), Vector3(target.x, plan.height_at(target) + 4.0, target.y))
	var goal := Vector2(cw.x, cw.z) + fwd2 * 30.0
	var kerb := StreetRoute.kerb_stop(plan, goal, 0.0)
	if kerb.is_empty():
		return ""
	var axis := int(kerb.axis)
	var road := plan.road_pos(axis, int(kerb.index))
	var lat := float(kerb.lateral)
	var along := float(kerb.along)
	var along_v := Vector2(0.0, 1.0) if axis == CityPlan.AXIS_X else Vector2(1.0, 0.0)
	var across := Vector2(1.0, 0.0) if axis == CityPlan.AXIS_X else Vector2(0.0, 1.0)
	var kerb_side := signf(lat) if lat != 0.0 else 1.0
	var width := plan.road_width(axis, int(kerb.index))
	var p_at := func(al: float, la: float) -> Vector2:
		return along_v * al + across * (road + la)
	var wreck_xz: Vector2 = p_at.call(along, lat)
	var body_xz: Vector2 = p_at.call(along - float(kerb.dir) * 22.0, kerb_side * (width * 0.5 + 1.6))
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var car := Vehicle.random_car(rng)
	var wh := plan.height_at(wreck_xz)
	var yaw := EmergencyCar.heading(axis, int(kerb.dir))
	car.transform = global_transform.affine_inverse() * Transform3D(Basis(Vector3.UP, yaw + 0.25), WorldState.to_local(Vector3(wreck_xz.x, wh + 0.9, wreck_xz.y)))
	add_child(car)
	var doll: Ragdoll = null
	if scene != "hose":
		var ped := Pedestrian.new()
		ped.setup(Rect2(body_xz.x - 1.0, body_xz.y - 1.0, 2.0, 2.0), 1.0, 1234)
		ped.position = to_local(WorldState.to_local(Vector3(body_xz.x, plan.height_at(body_xz) + CityChunk.SIDEWALK_TOP + 0.2, body_xz.y)))
		add_child(ped)
		ped.knock(Vector3(0.0, 0.5, 0.5))
		doll = ped._doll
	await get_tree().physics_frame
	await get_tree().physics_frame
	if scene != "medic":
		var dmg := car.damage_state()
		dmg.douse_seconds = 600.0
		dmg._staged = true
		dmg.become_wreck()
		var inc := open_call(KIND_FIRE, WorldState.to_world(car.global_position), car)
		stage(EmergencyCar.Kind.ENGINE, inc)
	if doll != null and is_instance_valid(doll):
		var inc2 := open_call(KIND_DOWN, WorldState.to_world(doll.bodies[0].global_position), null, doll)
		stage(EmergencyCar.Kind.AMBULANCE, inc2)
	# The crews straight to their places.
	for k in 3:
		for c in crews:
			if not is_instance_valid(c):
				continue
			c._think()
			if c.job == EmergencyCrew.Job.STRETCHER and c._stretcher == null and doll != null and is_instance_valid(doll):
				# On its way in: across the body from the one kneeling, the cot's foot a metre short.
				c._take_stretcher()
				c._set_pose("push")
				var b: Vector3 = doll.bodies[0].global_position
				var kneel := b
				for o in crews:
					if is_instance_valid(o) and o.job == EmergencyCrew.Job.PATIENT:
						kneel = o.global_position
				var away := (b - kneel).slide(Vector3.UP)
				away = away.normalized() if away.length() > 0.1 else Vector3.RIGHT
				var at := b + away * 4.3
				c.global_position = Vector3(at.x, c.global_position.y, at.z)
				c._visual.rotation.y = atan2(away.x, away.z)
				c._dest = c.global_position
			elif c._dest != Vector3.INF and c._pose != "kneel" and c._stretcher == null:
				c.global_position = c._dest + Vector3.UP * 0.05
	var wl := WorldState.to_local(Vector3(wreck_xz.x, wh, wreck_xz.y))
	match scene:
		"hose":
			for c in crews:
				if is_instance_valid(c) and c.job == EmergencyCrew.Job.NOZZLE:
					var n := c.global_position
					var side := (wl - n).cross(Vector3.UP).normalized()
					var mid := n.lerp(wl, 0.45)
					return _eye_at(WorldState.to_world(mid + side * 7.5 + Vector3.UP * 1.7), WorldState.to_world(mid + Vector3.UP * 1.2))
		"medic":
			if doll and is_instance_valid(doll):
				var b: Vector3 = doll.bodies[0].global_position
				var e := b + Vector3((across * -kerb_side).x, 0.0, (across * -kerb_side).y) * 3.0 + Vector3(along_v.x, 0.0, along_v.y) * 3.5 + Vector3.UP * 1.6
				return _eye_at(WorldState.to_world(e), WorldState.to_world(b + Vector3.UP * 0.4))
	# The whole scene from across the street.
	var centre := wreck_xz.lerp(body_xz, 0.4)
	var e2 := centre - across * kerb_side * (width * 0.5 + 3.0) + along_v * float(kerb.dir) * 16.0
	return _eye_at(Vector3(e2.x, plan.height_at(e2) + 2.2, e2.y), Vector3(centre.x, plan.height_at(centre) + 1.4, centre.y))


static func _eye_at(e: Vector3, look_at: Vector3) -> String:
	var d := look_at - e
	var yaw := rad_to_deg(atan2(-d.x, -d.z))
	var pitch := rad_to_deg(atan2(d.y, Vector2(d.x, d.z).length()))
	return "%.2f,%.2f,%.2f,%.2f,%.2f" % [e.x, e.y, e.z, yaw, pitch]
