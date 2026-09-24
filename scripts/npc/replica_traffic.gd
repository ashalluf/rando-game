class_name ReplicaTraffic
extends Node3D
## Cars on a replica area's own road (ReplicaAreas): both directions, in their lanes, round the
## roundabout anticlockwise the way right-hand traffic goes round one, and up into the hills.
## Kinematic like the city's traffic (Vehicle.traffic set, no VehicleWheel3D, placed every step
## from the route), each keeping its distance to the car ahead of it, spawned out of the way
## ahead of and behind the player and pooled. The grid traffic keeps out of the corridor
## (TrafficManager._replica_blocks()), so the two never meet.
##
## A car's position is its path distance `s` on the route, so every lane, the merge where two
## lanes become one and the ring all come from the same data the chunks build the road from.

## Cars kept on each direction within reach of the player.
@export var cars_per_direction: int = 7
## Where new cars appear, metres of road from the player, and where they are taken off.
@export var spawn_min: float = 130.0
@export var spawn_max: float = 380.0
@export var despawn_distance: float = 460.0
## Cruising speeds, m/s: the town streets (25-29 mph) and the hill road.
@export var town_speed: Vector2 = Vector2(10.5, 13.0)
@export var hill_speed: Vector2 = Vector2(13.0, 16.5)
## Round the roundabout: the circulating lane's radius and the speed held on it.
@export var ring_radius: float = 15.5
@export var ring_speed: float = 7.5
## Centre-to-centre room kept to the car ahead, and how hard cars speed up and brake (m/s^2).
@export var gap: float = 10.5
@export var accel: float = 2.2
@export var brake: float = 6.0
## Retired cars kept for reuse, and new builds allowed per frame (a car costs ~35 ms to build).
@export var pool_size: int = 10
@export var builds_per_frame: int = 1

var plan: CityPlan
var rep: ReplicaAreas
var cars: Array[Vehicle] = []
var _pool: Array[Vehicle] = []
var _player: Node3D
var _rng := RandomNumberGenerator.new()
var _timer: float = 0.0
var _built_frame: int = -1
var _built: int = 0


func _ready() -> void:
	_rng.seed = 173
	if OS.has_feature("web"):
		cars_per_direction = 4


func _physics_process(delta: float) -> void:
	if rep == null or plan == null:
		return
	if _player == null:
		_player = get_tree().get_first_node_in_group("player") as Node3D
		if _player == null:
			return
	_timer += delta
	if _timer >= 0.5:
		_timer = 0.0
		_maintain()
	_drive(delta)


func _exit_tree() -> void:
	for car in _pool:
		if is_instance_valid(car):
			car.free()
	_pool.clear()


# --- The lanes -------------------------------------------------------------------------------------

## Where a car at path distance `s` travelling `dir` (+1 with the path, south; -1 against it) in
## lane `lane` (0 nearest the centre) is: the world point its origin sits at. Right-hand traffic,
## so +1 drives the west half of the road.
func lane_point(s: float, dir: int, lane: int) -> Vector3:
	for ra in rep.roundabouts:
		var r := float(ra.r_out) + 1.0
		if absf(s - float(ra.s)) < r:
			return _ring_point(ra, s, dir, r)
	return _straight_point(s, dir, lane)


func _straight_point(s: float, dir: int, lane: int) -> Vector3:
	var at := rep.at_s(clampf(s, 0.0, rep.length))
	var sd: Dictionary = at[3]
	var lanes := maxf(1.0, float(sd.lanes))
	var o := (float(sd.median) + float(sd.lane_w) * (minf(float(lane), lanes - 1.0) + 0.5)) * -float(dir)
	var p: Vector2 = (at[0] as Vector2) + ReplicaAreas.left_of(at[1]) * o
	return Vector3(p.x, float(at[2]) + 0.55, p.y)


## On the ring: from the lane point where the approach meets it round anticlockwise (seen from
## above, north up) to where the exit leaves it, swinging in to the circulating lane between.
func _ring_point(ra: Dictionary, s: float, dir: int, r: float) -> Vector3:
	var c: Vector2 = ra.center
	var s_in := float(ra.s) - r * dir
	var s_out := float(ra.s) + r * dir
	var e := _straight_point(s_in, dir, 0)
	var x := _straight_point(s_out, dir, 0)
	var u := clampf((s - s_in) / (s_out - s_in), 0.0, 1.0)
	var te := atan2(e.z - c.y, e.x - c.x)
	var tx := atan2(x.z - c.y, x.x - c.x)
	# Anticlockwise on a north-up map is decreasing angle in (x, z).
	var sweep := fposmod(tx - te, TAU) - TAU
	var ang := te + sweep * u
	var re := Vector2(e.x, e.z).distance_to(c)
	var rx := Vector2(x.x, x.z).distance_to(c)
	var rad := lerpf(lerpf(re, rx, u), ring_radius, sin(PI * u))
	var top: float = rep.top[int(ra.index)] + 0.55
	return Vector3(c.x + cos(ang) * rad, top, c.y + sin(ang) * rad)


func _in_ring(s: float) -> bool:
	for ra in rep.roundabouts:
		if absf(s - float(ra.s)) < float(ra.r_out) + 1.0:
			return true
	return false


## How many lanes each way at path distance s.
func _lanes_at(s: float) -> int:
	var sd: Dictionary = rep.at_s(clampf(s, 0.0, rep.length))[3]
	return maxi(1, int(round(float(sd.lanes))))


# --- Upkeep --------------------------------------------------------------------------------------

func _player_s() -> float:
	var pw := WorldState.to_world(_player.global_position)
	var hit := rep.nearest(Vector2(pw.x, pw.z), 250.0)
	if hit.is_empty():
		return NAN
	return hit.s


func _maintain() -> void:
	var ps := _player_s()
	for car in cars.duplicate():
		if not is_instance_valid(car) or not car.is_traffic():
			cars.erase(car)
			continue
		var s: float = car.traffic.s
		if is_nan(ps) or absf(s - ps) > despawn_distance or s <= 1.0 or s >= rep.length - 1.0:
			cars.erase(car)
			_retire(car)
	if is_nan(ps):
		return
	for dir: int in [1, -1]:
		var have := 0
		for car in cars:
			if int(car.traffic.dir) == dir:
				have += 1
		if have >= cars_per_direction:
			continue
		# One new car per direction per upkeep, on a lane with room for it.
		var s := ps + _rng.randf_range(spawn_min, spawn_max) * (1.0 if _rng.randf() < 0.5 else -1.0)
		if s < 20.0 or s > rep.length - 20.0 or _in_ring(s):
			continue
		var lane := _rng.randi_range(0, _lanes_at(s) - 1)
		var clear := true
		for car in cars:
			if int(car.traffic.dir) == dir and absf(float(car.traffic.s) - s) < 30.0:
				clear = false
				break
		if clear:
			_spawn(s, dir, lane)


func _spawn(s: float, dir: int, lane: int) -> void:
	if Engine.get_process_frames() != _built_frame:
		_built_frame = Engine.get_process_frames()
		_built = 0
	var car: Vehicle = null
	while not _pool.is_empty() and car == null:
		var c: Vehicle = _pool.pop_back()
		if is_instance_valid(c):
			car = c
	if car == null:
		if _built >= builds_per_frame or not PhysicsBudget.can_spawn():
			return
		_built += 1
		car = Vehicle.random_car(_rng)
	var hill := s > rep.s_city_end
	var cruise := _rng.randf_range(hill_speed.x, hill_speed.y) if hill else _rng.randf_range(town_speed.x, town_speed.y)
	car.traffic = {"replica": true, "s": s, "dir": dir, "lane": lane, "cruise": cruise, "speed": cruise}
	car.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	car.freeze = true
	# Its transform before it enters the tree: a kinematic body that appears at the origin and is
	# then moved reads the jump as velocity (see AirTraffic._place_before_entry()).
	car.transform = global_transform.affine_inverse() * _transform_at(s, dir, lane)
	if car.get_parent() == null:
		add_child(car)
	car.traffic_speed = cruise
	cars.append(car)


func _retire(car: Vehicle) -> void:
	if not is_instance_valid(car):
		return
	if car.is_traffic() and car.get_parent() == self and _pool.size() < pool_size:
		remove_child(car)
		_pool.append(car)
	else:
		car.queue_free()


# --- Driving -------------------------------------------------------------------------------------

func _transform_at(s: float, dir: int, lane: int) -> Transform3D:
	var p := lane_point(s, dir, lane)
	var q := lane_point(s + 1.5 * dir, dir, lane)
	var fwd := q - p
	if fwd.length_squared() < 0.0001:
		fwd = Vector3(0, 0, -1)
	return Transform3D(Basis.looking_at(fwd.normalized(), Vector3.UP), WorldState.to_local(p))


func _drive(delta: float) -> void:
	# Each car follows the nearest car ahead of it in its direction that shares its lane, or any
	# car ahead where the road is down to one lane.
	for car in cars:
		if not is_instance_valid(car) or not car.is_traffic() or not car.traffic.has("replica"):
			continue
		var t: Dictionary = car.traffic
		var s: float = t.s
		var dir: int = t.dir
		var lane: int = t.lane
		var ahead := INF
		for other in cars:
			if other == car or not is_instance_valid(other) or not other.is_traffic() or not other.traffic.has("replica"):
				continue
			var ot: Dictionary = other.traffic
			if int(ot.dir) != dir:
				continue
			var d := (float(ot.s) - s) * dir
			if d <= 0.0 or d >= ahead:
				continue
			if int(ot.lane) == lane or _lanes_at(s + d * 0.5 * dir) < 2 or _in_ring(float(ot.s)):
				ahead = d
		var want: float = t.cruise
		if _in_ring(s + 12.0 * dir):
			want = minf(want, ring_speed)
		var speed: float = t.speed
		# Brake to hold the gap at a two-second-ish headway, gently otherwise.
		var room := ahead - gap
		if room < speed * 1.4:
			want = minf(want, maxf(room / 1.4, 0.0))
		if want < speed:
			speed = maxf(want, speed - brake * delta)
		else:
			speed = minf(want, speed + accel * delta)
		s += speed * dir * delta
		if lane > 0 and _lanes_at(s) < 2:
			lane = 0
		t.s = s
		t.speed = speed
		t.lane = lane
		car.traffic_speed = speed
		car.global_transform = _transform_at(s, dir, lane)
