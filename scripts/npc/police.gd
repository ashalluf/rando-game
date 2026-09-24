class_name Police
extends Node3D
## The wanted level and the police response (owner, 2026-09-24: "a police and star system").
## One node in the city scene, in the group "wanted". Other systems read `stars` (a plain int,
## 0-5) and listen to `stars_changed`; crimes come in through report_crime() and the static
## helpers below, which the crime sources call without holding a reference.
##
## Heat. Every crime that somebody sees or hears adds heat (pedestrians within
## `witness_radius`, or police within earshot or sight; with nobody about it counts for
## nothing). Stars follow heat UP through `star_heat`; they never fall with it.
##
## Losing them. Units look for the player a few times a second (a ray each, buildings block
## it). A crime or a sighting tells the police where the player is: that is `last_seen`, in
## true world coordinates. When no unit has had eyes on the player for `lose_seconds`, the stars
## flash for `flash_seconds` and drop one, then flash and drop the next, until they are gone or
## somebody sees the player again. Meanwhile units go where the player was, not where the player
## is: cruisers route to the search area round `last_seen`, which grows the longer the trail is
## cold, and officers on foot comb it.
##
## The response. `cruisers_per_star` / `officers_per_star` cap what is on the street, cruisers
## join out of sight along a street 170-240 m away (PoliceCar: kinematic on the lanes, real
## physics once they engage), stop near the player and the crew gets out (PoliceOfficer). From
## `roadblock_stars` roadblocks go up ahead of a player in a car; at `heavy_stars` every other
## unit is a tactical van with three officers carrying carbines. Cruisers are pooled; units that
## fall far behind, or that nobody has seen for a while, are recalled and replaced.
##
## Coordinates: `last_seen` and every `world_pos` argument are TRUE world positions
## (WorldState.to_world); the units themselves are ordinary nodes under this one and use scene
## positions like everything else.

signal stars_changed(stars: int)

## Off: crimes are ignored and nobody is sent (the smoke test's other checks run with it off).
@export var enabled: bool = true

@export_group("Heat")
## Heat needed for each star (index = stars). Stars rise when heat passes a threshold.
@export var star_heat: PackedFloat32Array = PackedFloat32Array([0.0, 1.0, 4.0, 9.0, 16.0, 26.0])
## Heat per crime, before the witness factor.
## A gunshot (the rifle raises about four reports a second while the trigger is held).
@export var heat_gunfire: float = 0.3
@export var heat_explosion: float = 2.5
## Knocking a pedestrian down (shot, run over, blown up, thrown into).
@export var heat_assault: float = 1.2
## An officer down. Always counts: the radio saw it.
@export var heat_cop_down: float = 4.5
## Shooting or blasting a car out of the traffic.
@export var heat_car_wreck: float = 0.6
## Shooting, blasting or stealing a police cruiser.
@export var heat_police_car: float = 1.6
## A crime a police unit sees or hears counts this much more.
@export var cop_witness_factor: float = 1.6
## Pedestrians within this many metres of a crime witness it.
@export var witness_radius: float = 40.0
## Police within this many metres hear gunfire and explosions.
@export var cop_hear_radius: float = 130.0
## Somebody knocked down within this many seconds of the player's gun or blast going off is the
## player's doing; otherwise only if the player (or their car) is right there.
@export var blame_seconds: float = 2.5

@export_group("Losing them")
## Seconds with no unit seeing the player before the stars start to flash and drop.
@export var lose_seconds: float = 12.0
## Seconds the stars flash before each one drops.
@export var flash_seconds: float = 3.5
## A sighting or a crime keeps the player "known" for this long (units aim, cruisers engage).
@export var known_seconds: float = 1.5
## The search area round the last sighting: starting radius, growth per second of cold trail,
## and its largest size (m).
@export var search_radius: float = 60.0
@export var search_growth: float = 4.0
@export var search_radius_max: float = 220.0
## How far a cruiser crew and an officer on foot can see the player, with a clear line (m).
@export var car_sight_range: float = 110.0
@export var officer_sight_range: float = 85.0
## Inside this range a unit notices the player whatever is in the way (m).
@export var sense_range: float = 14.0
## How often the units look for the player (seconds), and most sight rays per look.
@export var sight_interval: float = 0.25
@export var max_sight_rays: int = 6

@export_group("Response")
## Most cruisers on the street at each star level (index = stars), and officers on foot.
@export var cruisers_per_star: PackedInt32Array = PackedInt32Array([0, 1, 2, 3, 4, 6])
@export var officers_per_star: PackedInt32Array = PackedInt32Array([0, 2, 4, 6, 8, 12])
## Seconds between cruisers joining, and before the first one after the stars appear.
@export var dispatch_interval: float = 2.5
@export var first_dispatch_delay: float = 1.0
## Cruisers join this far from the player along a street, out of sight when possible (m).
@export var spawn_min: float = 170.0
@export var spawn_max: float = 240.0
## Units past this distance from the player are gone (m).
@export var despawn_distance: float = 330.0
## Units past this distance that nobody has seen for a few seconds are recalled and replaced by
## fresh ones, so a cruiser stuck three blocks back does not hold a slot (m).
@export var recall_distance: float = 150.0
## A crew whose player got this far from their parked car gets back in and gives chase (m).
@export var reboard_distance: float = 60.0
## Retired cruisers kept for reuse (building one is a hitch; reusing one is nearly free).
@export var pool_size: int = 6
## Roadblocks: from this many stars, every `roadblock_interval` seconds, this far ahead of a
## player driving faster than `roadblock_speed` m/s.
@export var roadblock_stars: int = 4
@export var roadblock_interval: float = 20.0
@export var roadblock_distance: float = 110.0
@export var roadblock_speed: float = 8.0
## From this many stars every other unit is a tactical van (three officers with carbines).
@export var heavy_stars: int = 5
## Officers aim better at higher stars: accuracy multiplier at 1 star, plus this per star.
@export var accuracy_base: float = 0.75
@export var accuracy_per_star: float = 0.08
## The web build (and its weaker machines) gets this share of every cap.
@export var web_scale: float = 0.6

const MAX_STARS := 5
## Set around a knock the police themselves cause (their bullets, a cruiser's bumper), so a
## bystander they hit is not the player's crime.
static var innocent: bool = false

## The wanted level, 0-5. A plain property: the police helicopter reads it off this node.
var stars: int = 0
var heat: float = 0.0
## Seconds since a unit last had eyes on the player (or a crime said where they were).
var seen_time: float = 0.0
## True on the last look if any unit could see the player.
var seeing: bool = false
## The stars are flashing: the police have lost the player and a star is about to drop.
var flashing: bool = false
## Where the player was last seen, true world position.
var last_seen: Vector3 = Vector3.ZERO
var cruisers: Array[PoliceCar] = []
var officers: Array[PoliceOfficer] = []
var plan: CityPlan
var traffic: TrafficManager
## Units dispatched in total (the smoke test and the HUD read it).
var dispatched: int = 0

var _player: Player
var _pool: Array[PoliceCar] = []
var _rng := RandomNumberGenerator.new()
var _sight_t: float = 0.0
var _upkeep_t: float = 0.0
var _dispatch_t: float = 0.0
var _roadblock_t: float = 0.0
var _flash_left: float = 0.0
var _witness_cache: Dictionary = {}
var _last_fire_ms: int = -100000
## Knock-downs waiting for the next tick to be pinned on the player or not: [kind, local, ms].
var _pending_downs: Array = []
var _web: bool = false


func _ready() -> void:
	add_to_group("wanted")
	_rng.seed = 5150
	_web = OS.has_feature("web")


# --- Crimes ------------------------------------------------------------------------------------

## The Police node in the scene, or null (the test room has none).
static func find(tree: SceneTree) -> Police:
	if tree == null:
		return null
	return tree.get_first_node_in_group("wanted") as Police


## From Pedestrian.alarm(): a gunshot or a blast at `at` (scene position), heard by `witnesses`
## pedestrians within `radius`.
static func on_alarm(tree: SceneTree, at: Vector3, radius: float, witnesses: int, kind: String) -> void:
	if innocent:
		return
	var p := find(tree)
	if p:
		p._heard(at, radius, witnesses, kind)


## From Pedestrian.knock(): somebody went down. An officer is a much bigger deal. Only counted
## when it can be pinned on the player (_blame): a car rolling down a hill into a bus stop is not
## a crime anybody is wanted for.
static func person_down(ped: Node3D) -> void:
	if innocent or ped == null or not ped.is_inside_tree():
		return
	var p := find(ped.get_tree())
	if p:
		p.knocked_down("cop_down" if ped is PoliceOfficer else "assault", ped.global_position)


## Somebody went down at `local` (scene position): a `kind` crime if it turns out to be the
## player's doing. Decided on the next physics tick rather than now, because a gun knocks its
## target over BEFORE it raises the alarm that says it fired (Weapon.tick: _fire, then alarm).
func knocked_down(kind: String, local: Vector3) -> void:
	if innocent or not enabled:
		return
	if _pending_downs.size() < 64:
		_pending_downs.append([kind, local, Time.get_ticks_msec()])


func _resolve_downs() -> void:
	var pending := _pending_downs
	_pending_downs = []
	for d: Array in pending:
		if _blame(d[1], int(d[2])):
			report_crime(d[0], WorldState.to_world(d[1]), 1.0)


## From Vehicle.drop_out_of_traffic(): a car was shot or blasted out of the traffic.
static func car_hit(car: Node3D) -> void:
	if innocent or car == null or not car.is_inside_tree():
		return
	var p := find(car.get_tree())
	if p == null:
		return
	p.report_crime("police_car" if car is PoliceCar else "car_wreck", WorldState.to_world(car.global_position), 1.0)


## A crime at `world_pos` (true world position). `kind` is one of gunfire, explosion, assault,
## cop_down, cop_hit, car_wreck, police_car (anything else counts as assault); `severity` scales
## its heat.
## It only counts if somebody saw or heard it.
func report_crime(kind: String, world_pos: Vector3, severity: float = 1.0) -> void:
	if not _can_report():
		return
	var local := WorldState.to_local(world_pos)
	var loud := kind == "gunfire" or kind == "explosion"
	var cops := _cops_near(local, cop_hear_radius if loud else officer_sight_range, not loud)
	var people := _count_witnesses(local, witness_radius)
	if kind == "cop_down" or kind == "cop_hit" or kind == "police_car":
		people = maxi(people, 1)
	_commit(kind, severity, people, cops)


## The player was seen (a unit that is not one of ours, such as the police helicopter).
## `world_pos` defaults to where the player is now.
func report_sighting(world_pos: Vector3 = Vector3.INF) -> void:
	if stars <= 0 or _player == null:
		return
	seen_time = 0.0
	flashing = false
	last_seen = player_world() if world_pos == Vector3.INF else world_pos


func _heard(at: Vector3, _radius: float, witnesses: int, kind: String) -> void:
	_last_fire_ms = Time.get_ticks_msec()
	if not _can_report():
		return
	var cops := _cops_near(at, cop_hear_radius, false)
	_commit(kind, 1.0, witnesses, cops)


## Whether somebody knocked down at `local` (scene position) is the player's doing: the player's
## gun or blast went off in the last `blame_seconds`, or the player's car (or the player) is right
## there. Physics knocks nobody caused - a car nudged at a chunk build, a bin rolling off a kerb -
## do not count.
func _blame(local: Vector3, at_ms: int) -> bool:
	_ensure_refs()
	if _player == null:
		return false
	if _last_fire_ms > at_ms - int(blame_seconds * 1000.0):
		return true
	if _player.is_driving():
		return _player.vehicle.global_position.distance_to(local) < 14.0
	return _player.global_position.distance_to(local) < 5.0


func _can_report() -> bool:
	if not enabled or innocent:
		return false
	_ensure_refs()
	return _player != null and not _player.is_downed()


func _commit(kind: String, severity: float, people: int, cops: int) -> void:
	if people <= 0 and cops <= 0:
		return
	var add := _heat_for(kind) * severity
	if cops > 0:
		add *= cop_witness_factor
	heat = minf(heat + add, star_heat[MAX_STARS] * 1.5)
	var was := stars
	var want := _stars_for_heat(heat)
	if want > stars:
		_set_stars(want)
	if stars > 0:
		# Somebody saw it: the police know where the player is.
		seen_time = 0.0
		flashing = false
		last_seen = player_world()
		if was == 0:
			_dispatch_t = first_dispatch_delay
			_roadblock_t = roadblock_interval * 0.5


func _heat_for(kind: String) -> float:
	match kind:
		"gunfire":
			return heat_gunfire
		"explosion":
			return heat_explosion
		"cop_down":
			return heat_cop_down
		"cop_hit":
			return heat_cop_down * 0.3
		"car_wreck":
			return heat_car_wreck
		"police_car":
			return heat_police_car
	return heat_assault


func _stars_for_heat(h: float) -> int:
	for s in range(MAX_STARS, 0, -1):
		if s < star_heat.size() and h >= star_heat[s]:
			return s
	return 0


func _set_stars(n: int) -> void:
	n = clampi(n, 0, MAX_STARS)
	if n == stars:
		return
	stars = n
	if n == 0:
		heat = 0.0
		flashing = false
	stars_changed.emit(stars)


## Pedestrians within `radius` of `local` (scene position), stopping at three. Cached per 20 m
## cell for a moment, so a rocket that knocks down twenty people scans the crowd once.
func _count_witnesses(local: Vector3, radius: float) -> int:
	var key := Vector2i(floori(local.x / 20.0), floori(local.z / 20.0))
	var now := Time.get_ticks_msec()
	var cached: Variant = _witness_cache.get(key)
	if cached != null and now - int(cached[0]) < 400:
		return int(cached[1])
	var n := 0
	var r2 := radius * radius
	for node in get_tree().get_nodes_in_group("pedestrian"):
		var p := node as Pedestrian
		if p == null or p._down or not p.is_inside_tree():
			continue
		if p.global_position.distance_squared_to(local) < r2:
			n += 1
			if n >= 3:
				break
	if _witness_cache.size() > 64:
		_witness_cache.clear()
	_witness_cache[key] = [now, n]
	return n


## Police units within `radius` of `local`; with `need_sight`, only ones with a clear line.
func _cops_near(local: Vector3, radius: float, need_sight: bool) -> int:
	var n := 0
	var rays := 0
	var r2 := radius * radius
	for car in cruisers:
		if not is_instance_valid(car) or car.crew_aboard <= 0:
			continue
		if car.global_position.distance_squared_to(local) > r2:
			continue
		if need_sight:
			if rays >= 3:
				continue
			rays += 1
			if not _clear_line(car.global_position + Vector3.UP * 1.3, local + Vector3.UP * 1.0):
				continue
		n += 1
	for o in officers:
		if not is_instance_valid(o) or o._down:
			continue
		if o.global_position.distance_squared_to(local) > r2:
			continue
		if need_sight:
			if rays >= 3:
				continue
			rays += 1
			if not _clear_line(o.global_position + Vector3.UP * 1.6, local + Vector3.UP * 1.0):
				continue
		n += 1
	return n


func _clear_line(from: Vector3, to: Vector3) -> bool:
	var space := get_world_3d().direct_space_state
	if space == null:
		return false
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, 1))
	return hit.is_empty() or (hit.position as Vector3).distance_to(to) < 1.2


# --- Control -------------------------------------------------------------------------------------

## Sets the wanted level outright (debug, screenshots, tests): heat to that star's threshold,
## the player known where they stand.
func set_wanted(n: int) -> void:
	_ensure_refs()
	n = clampi(n, 0, MAX_STARS)
	heat = star_heat[n] if n < star_heat.size() else heat
	seen_time = 0.0
	flashing = false
	if _player:
		last_seen = player_world()
	if n > 0 and stars == 0:
		_dispatch_t = 0.0
		_roadblock_t = roadblock_interval * 0.5
	_set_stars(n)


## Stars gone and every unit off the street at once (the player went down).
func clear() -> void:
	_set_stars(0)
	heat = 0.0
	seen_time = 0.0
	flashing = false
	for car in cruisers.duplicate():
		_retire_car(car)
	for o in officers.duplicate():
		_retire_officer(o)
	cruisers.clear()
	officers.clear()
	innocent = false


# --- Queries (units, HUD, minimap) --------------------------------------------------------------

func player_node() -> Player:
	return _player


## A unit (or a crime) placed the player within the last `known_seconds`.
func player_known() -> bool:
	return stars > 0 and seen_time < known_seconds and _player != null and not _player.is_downed()


func player_world() -> Vector3:
	return WorldState.to_world(_player.global_position) if _player else Vector3.ZERO


func player_driving() -> bool:
	return _player != null and _player.is_driving()


func player_vehicle() -> Vehicle:
	return _player.vehicle if _player and _player.is_driving() else null


## Where to shoot and look: the player's chest, or the car they are in.
func player_aim_point() -> Vector3:
	if _player == null:
		return Vector3.ZERO
	if _player.is_driving():
		return _player.vehicle.global_position + Vector3.UP * 0.8
	return _player.global_position + Vector3.UP * 1.1


func player_velocity() -> Vector3:
	if _player == null:
		return Vector3.ZERO
	return _player.vehicle.linear_velocity if _player.is_driving() else _player.velocity


## The search area's centre (scene position) and radius, and whether it is on (the minimap
## draws it once the trail has gone cold for a moment).
func search_center() -> Vector3:
	return WorldState.to_local(last_seen)


func search_radius_now() -> float:
	return clampf(search_radius + search_growth * maxf(seen_time - known_seconds, 0.0), search_radius, search_radius_max)


func show_search_area() -> bool:
	return stars > 0 and seen_time > known_seconds


## A spot to search (true world XZ): somewhere in the search area.
func random_search_point() -> Vector2:
	var a := _rng.randf() * TAU
	var r := sqrt(_rng.randf()) * search_radius_now() * 0.8
	return Vector2(last_seen.x, last_seen.z) + Vector2(cos(a), sin(a)) * r


## Where a chasing cruiser drives: the player (a car ahead of where it is), the last sighting,
## or its own goal when it is leaving.
func pursuit_target(car: PoliceCar) -> Vector3:
	if car.mode == PoliceCar.Mode.LEAVING or not player_known():
		var g := car.goal
		if car.mode != PoliceCar.Mode.LEAVING:
			g = Vector2(last_seen.x, last_seen.z)
		var local := WorldState.to_local(Vector3(g.x, 0.0, g.y))
		local.y = car.global_position.y
		return local
	var p := player_aim_point()
	if player_driving():
		p += player_velocity() * car.ram_lead
	return p


## How well officers shoot at the current wanted level.
func accuracy_scale() -> float:
	return accuracy_base + accuracy_per_star * float(maxi(stars - 1, 0))


## Officers never shoot a player who is down, or once the stars are gone.
func can_shoot() -> bool:
	return stars > 0 and _player != null and not _player.is_downed()


## Every officer's RID, so their shots pass through each other.
func officer_rids() -> Array[RID]:
	var out: Array[RID] = []
	for o in officers:
		if is_instance_valid(o):
			out.append(o.get_rid())
	return out


func units_alive() -> int:
	var n := officers.size()
	for car in cruisers:
		if is_instance_valid(car):
			n += 1
	return n


## Most cruisers / officers allowed right now.
func cruiser_cap() -> int:
	return _cap(cruisers_per_star)


func officer_cap() -> int:
	return _cap(officers_per_star)


func _cap(table: PackedInt32Array) -> int:
	if table.is_empty():
		return 0
	var n := table[clampi(stars, 0, table.size() - 1)]
	if _web and n > 0:
		n = maxi(1, roundi(float(n) * web_scale))
	return n


# --- Units -----------------------------------------------------------------------------------

## The player hit by a police bullet (or a cruiser), from `from` (scene position).
func hit_player(amount: float, from: Vector3) -> void:
	if _player and not _player.is_downed():
		_player.take_damage(amount, from, "bullet")


## A cruiser has stopped: its crew gets out beside it, as many as the officer cap allows.
func deploy_crew(car: PoliceCar) -> void:
	if not is_instance_valid(car) or stars <= 0 or not enabled:
		return
	var cap := officer_cap()
	var count := car.crew_aboard
	for i in count:
		if officers.size() >= cap:
			break
		var o := PoliceOfficer.new()
		o.setup_officer(self, car, car.crew_alive - car.crew_aboard, car.heavy, _rng.randi())
		var spot := _door_spot(car, i)
		add_child(o)
		o.global_position = spot
		officers.append(o)
		car.crew_aboard -= 1


## A clear spot beside the car for an officer to stand: the doors first, then behind and in front.
func _door_spot(car: PoliceCar, i: int) -> Vector3:
	var base := car.global_position - Vector3.UP * 0.42
	var side := car.global_basis.x
	side.y = 0.0
	side = side.normalized() if side.length() > 0.1 else Vector3.RIGHT
	var fwd := -car.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.1 else Vector3.FORWARD
	var s := -1.0 if i % 2 == 0 else 1.0
	var candidates: Array[Vector3] = [
		base + side * (1.8 * s) + fwd * (0.4 - 0.9 * float(i >> 1)),
		base - side * (1.8 * s),
		base - fwd * 3.4 + side * (0.6 * s),
		base + fwd * 3.4 + side * (0.6 * s),
	]
	var space := get_world_3d().direct_space_state
	if space == null:
		return candidates[0]
	var shape := CapsuleShape3D.new()
	shape.radius = 0.32
	shape.height = 1.7
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = shape
	params.collision_mask = 1 | 4
	params.exclude = [car.get_rid()]
	for c in candidates:
		params.transform = Transform3D(Basis(), c + Vector3.UP * 0.95)
		if space.intersect_shape(params, 1).is_empty():
			return c
	return candidates[0] + Vector3.UP * 0.3


## An officer is back in the car. With the whole crew in, the car chases again (or leaves).
func board(o: PoliceOfficer, car: PoliceCar) -> void:
	officers.erase(o)
	o.queue_free()
	if not is_instance_valid(car):
		return
	car.crew_aboard += 1
	if car.crew_aboard >= car.crew_alive:
		if stars > 0:
			car.resume_pursuit()
		else:
			car.recall_crew = false
			car.mode = PoliceCar.Mode.LEAVING
			car.goal = _away_point()


func officer_down(o: PoliceOfficer) -> void:
	officers.erase(o)
	if is_instance_valid(o.car):
		o.car.crew_alive = maxi(o.car.crew_alive - 1, 0)


## The player got into a cruiser: it is theirs now. Anyone still in it gets out first.
func cruiser_stolen(car: PoliceCar) -> void:
	if car.crew_aboard > 0 and stars > 0:
		deploy_crew(car)
	# Whoever was still inside is out; the car is nobody's cruiser any more and never drives
	# itself again, even after the player leaves it.
	car.crew_aboard = 0
	car.crew_alive = 0
	car.mode = PoliceCar.Mode.PARKED
	cruisers.erase(car)
	report_crime("police_car", WorldState.to_world(car.global_position), 1.0)


## A cruiser on the street right now (tests, screenshots, roadblocks): at `world_pos` facing
## `yaw`, either chasing ("pursue") or stopped with its crew out ("parked").
func spawn_cruiser(world_pos: Vector3, yaw: float, kind: String = "parked", is_heavy: bool = false) -> PoliceCar:
	_ensure_refs()
	var car := _take_car(is_heavy)
	car.police = self
	car._plan = plan
	car.goal = Vector2(world_pos.x, world_pos.z)
	_enter_at(car, Transform3D(Basis(Vector3.UP, yaw), WorldState.to_local(world_pos)))
	car.traffic_speed = 0.0
	car.go_physical()
	cruisers.append(car)
	dispatched += 1
	if kind == "parked" or kind == "roadblock":
		car.roadblock = kind == "roadblock"
		car.mode = PoliceCar.Mode.PARKED
		car.brake = car.parking_brake
		deploy_crew(car)
	return car


func _take_car(is_heavy: bool) -> PoliceCar:
	for i in range(_pool.size() - 1, -1, -1):
		var c: PoliceCar = _pool[i]
		if not is_instance_valid(c):
			_pool.remove_at(i)
			continue
		if c.heavy == is_heavy:
			_pool.remove_at(i)
			return c
	return PoliceCar.make(is_heavy, _rng)


func _retire_car(c: Variant) -> void:
	cruisers.erase(c)
	if not is_instance_valid(c):
		return
	var car: PoliceCar = c
	for o in officers.duplicate():
		if is_instance_valid(o) and o.car == car:
			_retire_officer(o)
	if car.driver != null:
		return # the player's now
	if car.get_parent() == self and _pool.size() < pool_size and not car.is_queued_for_deletion():
		car.strip_for_pool()
		remove_child(car)
		_pool.append(car)
	else:
		car.queue_free()


func _retire_officer(o: Variant) -> void:
	officers.erase(o)
	if is_instance_valid(o) and not (o as Node).is_queued_for_deletion():
		(o as Node).queue_free()


func _exit_tree() -> void:
	for car in _pool:
		if is_instance_valid(car):
			car.free()
	_pool.clear()


# --- The loop --------------------------------------------------------------------------------------

func _ensure_refs() -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Player
	if plan == null:
		var city := get_parent()
		if city and city.get("plan") != null:
			plan = city.plan
	if traffic == null:
		var city2 := get_parent()
		if city2:
			traffic = city2.get_node_or_null("Traffic") as TrafficManager


func _physics_process(delta: float) -> void:
	if not _pending_downs.is_empty():
		_resolve_downs()
	if stars == 0 and cruisers.is_empty() and officers.is_empty():
		return
	_ensure_refs()
	if _player == null:
		return
	if stars > 0:
		seen_time += delta
		_sight_t -= delta
		if _sight_t <= 0.0:
			_sight_t = sight_interval
			seeing = _look_for_player()
			if seeing:
				report_sighting()
		_update_losing(delta)
	_upkeep_t -= delta
	if _upkeep_t <= 0.0:
		_upkeep_t = 0.5
		_upkeep()


## The stars flash once the trail is cold, and drop one at a time.
func _update_losing(delta: float) -> void:
	if seen_time <= lose_seconds:
		flashing = false
		return
	if not flashing:
		flashing = true
		_flash_left = flash_seconds
	_flash_left -= delta
	if _flash_left <= 0.0:
		_flash_left = flash_seconds
		_set_stars(stars - 1)
		if stars > 0:
			heat = star_heat[stars]
		else:
			flashing = false


## One look round by every unit that could see the player, nearest first in list order, at most
## `max_sight_rays` rays.
func _look_for_player() -> bool:
	if not can_shoot():
		return false
	var target := player_aim_point()
	var rays := 0
	for car in cruisers:
		if not is_instance_valid(car) or car.crew_aboard <= 0 or car.driver != null:
			continue
		var r := _sight(car.global_position + Vector3.UP * 1.3, target, car_sight_range, rays)
		if r > 0:
			return true
		if r == 0:
			rays += 1
	for o in officers:
		if not is_instance_valid(o) or o._down:
			continue
		var r := _sight(o.global_position + Vector3.UP * 1.6, target, officer_sight_range, rays)
		if r > 0:
			return true
		if r == 0:
			rays += 1
	return false


## 1 sees the player, 0 looked and did not, -1 too far to try (no ray spent).
func _sight(from: Vector3, to: Vector3, reach: float, rays: int) -> int:
	var d := from.distance_to(to)
	if d > reach:
		return -1
	if d < sense_range:
		return 1
	if rays >= max_sight_rays:
		return -1
	return 1 if _clear_line(from, to) else 0


## Twice a second: recall what fell behind, give orders, send more.
func _upkeep() -> void:
	var pp := _player.global_position
	var cam := get_viewport().get_camera_3d()
	for c in cruisers.duplicate():
		if not is_instance_valid(c):
			cruisers.erase(c)
			continue
		var car: PoliceCar = c
		if car.driver != null:
			cruisers.erase(car)
			continue
		var d := car.global_position.distance_to(pp)
		var on_screen := cam != null and d < 320.0 and cam.is_position_in_frustum(car.global_position)
		car.unseen_time = 0.0 if on_screen else car.unseen_time + 0.5
		var crew_out := car.crew_aboard < car.crew_alive
		var retire := d > despawn_distance
		if not retire and not crew_out and car.mode != PoliceCar.Mode.DISPATCH and d > recall_distance and car.unseen_time > 3.0:
			retire = true
		if not retire and stars == 0 and not crew_out and car.unseen_time > 2.0:
			retire = true
		if not retire and car.crew_alive <= 0 and d > 90.0 and car.unseen_time > 4.0:
			retire = true
		if not retire and car.roadblock and d > roadblock_distance * 1.6 and car.unseen_time > 3.0:
			retire = true
		if retire:
			_retire_car(car)
			continue
		if car.mode == PoliceCar.Mode.DISPATCH:
			car.goal = _goal_for(car)
		if crew_out and not car.roadblock and (stars == 0 or (player_known() and d > reboard_distance)):
			car.recall_crew = true
	for oc in officers.duplicate():
		if not is_instance_valid(oc) or (oc as PoliceOfficer)._down:
			officers.erase(oc)
			continue
		var o: PoliceOfficer = oc
		var d := o.global_position.distance_to(pp)
		var on_screen := cam != null and d < 250.0 and cam.is_position_in_frustum(o.global_position)
		o.unseen_time = 0.0 if on_screen else o.unseen_time + 0.5
		var car_gone := o.car == null or not is_instance_valid(o.car) or o.car.driver != null
		if d > despawn_distance or (d > recall_distance and o.unseen_time > 4.0) or (stars == 0 and car_gone and o.unseen_time > 2.0):
			_retire_officer(o)
	if stars <= 0 or not enabled:
		return
	_dispatch_t -= 0.5
	# Every cruiser still on the street counts against the cap, leaving or crewless ones too:
	# counted only while crewed and not leaving, one more could be sent while an empty one was
	# still standing there, and five stars put seven on the street against a cap of six.
	# Roadblocks are their own budget.
	var active := 0
	for car in cruisers:
		if not car.roadblock:
			active += 1
	# make_room, not can_spawn: after a big fight the budget is full of debris (gibs, shells,
	# wreckage), and waiting for room meant no police came at all until it timed out. Debris
	# is short-lived by definition; the oldest goes so the cruiser can.
	if active < cruiser_cap() and _dispatch_t <= 0.0 and PhysicsBudget.make_room(1):
		_dispatch_t = dispatch_interval
		_dispatch()
	if stars >= roadblock_stars:
		_roadblock_t -= 0.5
		if _roadblock_t <= 0.0 and player_driving():
			_roadblock_t = roadblock_interval
			_place_roadblock()


## A dispatching cruiser's goal (true world XZ): the player when known, else a spot in the
## search area, picked again once it gets there.
func _goal_for(car: PoliceCar) -> Vector2:
	var pw := player_world()
	if player_known():
		return Vector2(pw.x, pw.z)
	var wp := WorldState.to_world(car.global_position)
	var here := Vector2(wp.x, wp.z)
	var center := Vector2(last_seen.x, last_seen.z)
	if car.goal.distance_to(center) > search_radius_now() or here.distance_to(car.goal) < 25.0:
		return random_search_point()
	return car.goal


## A far point to drive off to once the stars are gone.
func _away_point() -> Vector2:
	var pw := player_world()
	var a := _rng.randf() * TAU
	return Vector2(pw.x, pw.z) + Vector2(cos(a), sin(a)) * 400.0


## A cruiser joins the chase: along a street near the player's block, spawn_min..spawn_max out
## along it, out of the camera's view when it can be, heading toward the player.
func _dispatch() -> void:
	if plan == null:
		return
	var pw := player_world()
	var xz := Vector2(pw.x, pw.z)
	var zone := plan.zone_at(xz)
	if zone != MacroMap.Zone.CITY and zone != MacroMap.Zone.BEACH:
		return
	var cam := get_viewport().get_camera_3d()
	var center := plan.block_index_at(xz)
	var pick: Array = []
	for attempt in 12:
		var axis := _rng.randi_range(0, 1)
		var index := (center.x if axis == CityPlan.AXIS_X else center.y) + _rng.randi_range(-2, 2)
		var along0 := pw.z if axis == CityPlan.AXIS_X else pw.x
		var along := along0 + (-1.0 if _rng.randf() < 0.5 else 1.0) * _rng.randf_range(spawn_min, spawn_max)
		var road := plan.road_pos(axis, index)
		var p2 := Vector2(road, along) if axis == CityPlan.AXIS_X else Vector2(along, road)
		if plan.zone_at(p2) != MacroMap.Zone.CITY or not plan.road_open(axis, index, along):
			continue
		var local := WorldState.to_local(Vector3(p2.x, pw.y, p2.y))
		if attempt < 8 and cam and cam.is_position_in_frustum(local) and cam.global_position.distance_to(local) < 400.0:
			continue
		pick = [axis, index, 1 if along0 > along else -1, p2]
		break
	if pick.is_empty():
		return
	var heavy := stars >= heavy_stars and dispatched % 2 == 1
	var car := _take_car(heavy)
	car.police = self
	car.begin_dispatch(plan, pick[0], pick[1], pick[2], car.dispatch_speed * 0.85)
	car.goal = xz
	var p: Vector2 = pick[3]
	var lane: float = car.traffic.lane
	if int(pick[0]) == CityPlan.AXIS_X:
		p.x += lane
	else:
		p.y += lane
	var h := traffic._relief(p) if traffic else (plan.macro.relief_at(p) if plan.macro else 0.0)
	_enter_at(car, Transform3D(Basis(Vector3.UP, car._heading(pick[0], pick[2])), WorldState.to_local(Vector3(p.x, 0.55 + h, p.y))))
	cruisers.append(car)
	dispatched += 1


## Puts a cruiser at scene transform `xf`: written in this node's space before a new or pooled
## car enters the tree, so it never enters at the origin and jumps (a kinematic body takes that
## jump as its velocity for a step - the aircraft trap in CLAUDE.md), and set directly on one
## that is already in it.
func _enter_at(car: PoliceCar, xf: Transform3D) -> void:
	if car.get_parent() == null:
		car.transform = global_transform.affine_inverse() * xf
		add_child(car)
	else:
		car.global_transform = xf


## Two cruisers parked across the street ahead of a player driving along it, crews out behind.
func _place_roadblock() -> void:
	if plan == null:
		return
	var v := player_velocity()
	var flat := Vector2(v.x, v.z)
	if flat.length() < roadblock_speed:
		return
	var pw := player_world()
	# Driving along Z means driving on an AXIS_X road (x is fixed), and the other way round.
	var axis := CityPlan.AXIS_X if absf(flat.y) > absf(flat.x) else CityPlan.AXIS_Z
	var coord := pw.x if axis == CityPlan.AXIS_X else pw.z
	var index := plan._index_at(axis, coord)
	if absf(coord - plan.road_pos(axis, index + 1)) < absf(coord - plan.road_pos(axis, index)):
		index += 1
	var road := plan.road_pos(axis, index)
	var width := plan.road_width(axis, index)
	if absf(coord - road) > width * 0.6:
		return
	var travel := signf(flat.y if axis == CityPlan.AXIS_X else flat.x)
	var along := (pw.z if axis == CityPlan.AXIS_X else pw.x) + travel * roadblock_distance
	var mid := Vector2(road, along) if axis == CityPlan.AXIS_X else Vector2(along, road)
	if plan.zone_at(mid) != MacroMap.Zone.CITY or not plan.road_open(axis, index, along):
		return
	# Across the road: the cars' length runs across the carriageway.
	var yaw := PI * 0.5 if axis == CityPlan.AXIS_X else 0.0
	for k in 2:
		# Nose to tail across the carriageway: a car's length apart, or they spawn inside each other.
		var lat := (float(k) - 0.5) * 5.4
		var at := mid + (Vector2(lat, 0.0) if axis == CityPlan.AXIS_X else Vector2(0.0, lat))
		var h := traffic._relief(at) if traffic else 0.0
		spawn_cruiser(Vector3(at.x, 0.9 + h, at.y), yaw + (PI if k == 1 else 0.0), "roadblock")


# --- Screenshots --------------------------------------------------------------------------------

## Puts a wanted level and its units in front of the camera at once, for tools/glshot/still_shot.gd
## (STARS=n, POLICE=pursuit|standoff): a software frame takes seconds, and waiting for cruisers
## to drive in from 200 m would take hundreds of them. "pursuit" is cruisers bearing down the
## street at the player; "standoff" is cruisers stopped across the street with their crews out.
func stage_for_shot(n_stars: int, scene: String) -> void:
	_ensure_refs()
	set_wanted(n_stars)
	if _player == null or plan == null:
		return
	var cam := get_viewport().get_camera_3d()
	var fwd := -cam.global_basis.z if cam else Vector3.FORWARD
	fwd.y = 0.0
	fwd = fwd.normalized()
	var pw := player_world()
	var count := clampi(n_stars, 1, 3)
	for i in count:
		var dist := (20.0 + 9.0 * float(i)) if scene == "pursuit" else (14.0 + 3.0 * float(i))
		var side := (float(i % 2) - 0.5) * (7.0 if scene == "pursuit" else 9.0)
		var right := fwd.cross(Vector3.UP)
		var at := pw + fwd * dist + right * side
		var h := traffic._relief(Vector2(at.x, at.z)) if traffic else 0.0
		at.y = 0.9 + h
		# Facing the player for a chase, broadside across the street for a standoff.
		var yaw := atan2(fwd.x, fwd.z) if scene == "pursuit" else atan2(-fwd.x, -fwd.z) + PI * 0.5 + 0.35 * float(i)
		var car := spawn_cruiser(at, yaw, "pursue" if scene == "pursuit" else "parked", n_stars >= heavy_stars and i == 1)
		if scene == "pursuit":
			car.linear_velocity = -car.global_basis.z * 14.0
