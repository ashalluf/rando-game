class_name CoastTraffic
extends Node3D
## Cars on the coast highway (CoastHighway): two lanes each way under the bluffs, on past the
## stretch along the coast highway's strip toward the beach town. Kinematic like the city's traffic
## (Vehicle.traffic set, no VehicleWheel3D, placed every step), each keeping its distance to the
## car ahead in its lane, spawned out of the way ahead of and behind the player and pooled, the
## way ReplicaTraffic drives the replica's road. A car's place is its z (`s`), its direction (+1
## southbound, on the sea side: right-hand traffic) and its lane (0 by the median). Northbound cars
## stop in a queue at the slide's closure and are taken off once the player is away from it.

## Cars kept on each direction within reach of the player.
@export var cars_per_direction: int = 6
## Where new cars appear, metres of road from the player, and where they are taken off.
@export var spawn_min: float = 160.0
@export var spawn_max: float = 380.0
@export var despawn_distance: float = 470.0
## Cruising speed (45-55 mph), the room kept to the car ahead, and how hard cars speed up and brake.
@export var cruise: Vector2 = Vector2(19.0, 24.0)
@export var gap: float = 12.0
@export var accel: float = 2.4
@export var brake: float = 6.5
@export var pool_size: int = 8
@export var builds_per_frame: int = 1
## How far down the coast highway's strip past the stretch the cars drive.
const RUN_ON := CoastHighway.TRAFFIC_RUN_ON
## A car's origin over the asphalt before its own road_lift().
const LANE_LIFT := 0.55

var plan: CityPlan
var ch: CoastHighway
var cars: Array[Vehicle] = []
var _pool: Array[Vehicle] = []
var _player: Node3D
## True while a check stages cars: no spawning or taking off (TrafficManager.staged's role).
var staged: bool = false
var _rng := RandomNumberGenerator.new()
var _timer: float = 0.0
var _built_frame: int = -1
var _built: int = 0


## Off: COAST_HIGHWAY=0 (no stretch) or COAST_TRAFFIC=0.
static func enabled() -> bool:
	return OS.get_environment("COAST_TRAFFIC") != "0"


func _ready() -> void:
	_rng.seed = 7151
	if OS.has_feature("web"):
		cars_per_direction = 3


func _physics_process(delta: float) -> void:
	if ch == null or plan == null:
		return
	if _player == null:
		_player = get_tree().get_first_node_in_group("player") as Node3D
		if _player == null:
			return
	_timer += delta
	if _timer >= 0.5 and not staged:
		_timer = 0.0
		_maintain()
	_drive(delta)


func _exit_tree() -> void:
	for car in _pool:
		if is_instance_valid(car):
			car.free()
	_pool.clear()


# --- The lanes -------------------------------------------------------------------------------------

## The z range the cars drive: from the closure to past the stretch's south end.
func s_min() -> float:
	return ch.z_north + CoastHighway.CLOSURE + 4.0


func s_max() -> float:
	return ch.z_south + RUN_ON


## d of a lane's centre: southbound (+1) on the sea side of the median, lane 0 by it.
static func lane_d(dir: int, lane: int) -> float:
	return CoastHighway.CENTRE - float(dir) * (CoastHighway.MEDIAN * 0.5 + CoastHighway.LANE * (float(lane) + 0.5))


## The world point (true world) a car's origin sits at.
func lane_point(s: float, dir: int, lane: int) -> Vector3:
	var p := ch.at(lane_d(dir, lane), s)
	return Vector3(p.x, ch.road_y(s) + LANE_LIFT, p.y)


func _transform_at(s: float, dir: int, lane: int, lift: float) -> Transform3D:
	var p := lane_point(s, dir, lane)
	var q := lane_point(s + 1.5 * dir, dir, lane)
	var fwd := q - p
	if fwd.length_squared() < 0.0001:
		fwd = Vector3(0, 0, -1)
	return Transform3D(Basis.looking_at(fwd.normalized(), Vector3.UP), WorldState.to_local(p + Vector3.UP * (lift - LANE_LIFT)))


# --- Upkeep --------------------------------------------------------------------------------------

## The player's z when they are near the road (within 250 m of it), else NAN.
func _player_s() -> float:
	var pw := WorldState.to_world(_player.global_position)
	var z := pw.z
	if z < ch.z_north - 250.0 or z > s_max() + 250.0:
		return NAN
	var d := pw.x - ch.macro.coast_x(z) - CoastHighway.CENTRE
	if absf(d) > 250.0:
		return NAN
	return z


func _maintain() -> void:
	var ps := _player_s()
	var close := s_min()
	for car in cars.duplicate():
		if not is_instance_valid(car) or not car.is_traffic() or not car.traffic.has("coast"):
			cars.erase(car)
			continue
		var s: float = car.traffic.s
		var gone := is_nan(ps) or absf(s - ps) > despawn_distance or s >= s_max() - 1.0
		# A northbound car at the closure leaves once the player is away from it.
		if int(car.traffic.dir) < 0 and s <= close + 30.0 and (is_nan(ps) or absf(ps - close) > 150.0):
			gone = true
		if gone:
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
		var s := ps + _rng.randf_range(spawn_min, spawn_max) * (1.0 if _rng.randf() < 0.5 else -1.0)
		if s < close + 40.0 or s > s_max() - 20.0:
			continue
		var lane := _rng.randi_range(0, 1)
		var clear := true
		for car in cars:
			if int(car.traffic.dir) == dir and absf(float(car.traffic.s) - s) < 35.0:
				clear = false
				break
		if clear:
			spawn(s, dir, lane)


## `force` skips the per-frame build cap and the physics budget (the checks use it).
func spawn(s: float, dir: int, lane: int, force: bool = false) -> Vehicle:
	if Engine.get_process_frames() != _built_frame:
		_built_frame = Engine.get_process_frames()
		_built = 0
	var car: Vehicle = null
	while not _pool.is_empty() and car == null:
		var c: Vehicle = _pool.pop_back()
		if is_instance_valid(c):
			car = c
	if car == null:
		if not force and (_built >= builds_per_frame or not PhysicsBudget.can_spawn()):
			return null
		_built += 1
		car = Vehicle.random_car(_rng)
	var v := _rng.randf_range(cruise.x, cruise.y)
	car.traffic = {"coast": true, "s": s, "dir": dir, "lane": lane, "cruise": v, "speed": v}
	car.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	car.freeze = true
	# Its transform before it enters the tree (AirTraffic._place_before_entry()).
	car.transform = global_transform.affine_inverse() * _transform_at(s, dir, lane, car.road_lift())
	if car.get_parent() == null:
		add_child(car)
	car.traffic_speed = v
	cars.append(car)
	return car


func _retire(car: Vehicle) -> void:
	if not is_instance_valid(car):
		return
	if car.is_traffic() and car.get_parent() == self and _pool.size() < pool_size:
		remove_child(car)
		_pool.append(car)
	else:
		car.queue_free()


# --- Driving -------------------------------------------------------------------------------------

func _drive(delta: float) -> void:
	var close := s_min()
	for car in cars:
		if not is_instance_valid(car) or not car.is_traffic() or not car.traffic.has("coast"):
			continue
		var t: Dictionary = car.traffic
		var s: float = t.s
		var dir: int = t.dir
		var lane: int = t.lane
		var ahead := INF
		for other in cars:
			if other == car or not is_instance_valid(other) or not other.is_traffic() or not other.traffic.has("coast"):
				continue
			var ot: Dictionary = other.traffic
			if int(ot.dir) != dir or int(ot.lane) != lane:
				continue
			var d := (float(ot.s) - s) * dir
			if d > 0.0 and d < ahead:
				ahead = d
		# Northbound, the closure is a car standing in every lane.
		if dir < 0:
			ahead = minf(ahead, s - close + gap - 3.0)
		var want: float = t.cruise
		var speed: float = t.speed
		# The speed it can still stop from in the room it has, held at a headway in traffic.
		var room := ahead - gap
		want = minf(want, sqrt(maxf(0.0, 2.0 * brake * 0.7 * room)))
		if room < speed * 1.6:
			want = minf(want, maxf(room / 1.6, 0.0))
		if want < speed:
			speed = maxf(want, speed - brake * delta)
		else:
			speed = minf(want, speed + accel * delta)
		s += speed * dir * delta
		# Never through the closure's k-rails.
		if dir < 0 and s < close:
			s = close
			speed = 0.0
		t.s = s
		t.speed = speed
		car.traffic_speed = speed
		car.global_transform = _transform_at(s, dir, lane, car.road_lift())
