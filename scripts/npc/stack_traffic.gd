class_name StackTraffic
extends Node3D
## Cars on the four-level stack's connectors (FreewayStack), kinematic like the freeway's own
## traffic (Vehicle.traffic set, no VehicleWheel3D, placed every step). A connector's car runs by
## distance `s` along it, in one of its two lanes, keeping its distance to the car ahead.
##
## Where the main lines meet it, the traffic is handed over in both directions so cars really
## use the connectors: TrafficManager's freeway car nearing a connector's diverge in the same
## direction is taken off the main line now and then (`take_share`) and drifts across the open
## touch run into the connector's lane; at the far end the car drifts back across the merge onto
## the target's outer lane and is handed to TrafficManager as its freeway car. When there is no
## main-line car to take, one is spawned on the connector out of the player's way, and a car
## with nowhere to go at the end is retired. Only within `active_range` of the stack.

## Cars kept on each connector, and the speed they hold (m/s, about 45 mph).
@export var cars_per_link: int = 4
@export var speed_range: Vector2 = Vector2(18.5, 22.5)
## Centre-to-centre room kept to the car ahead, and how hard cars brake / speed up.
@export var gap: float = 17.0
@export var brake: float = 6.0
@export var accel: float = 2.0
## How often a main-line car nearing a diverge turns onto the connector.
@export var take_share: float = 0.45
## No new car appears within this of the player (it pops in).
@export var spawn_clear: float = 140.0
## The stack's traffic runs while the player is within this of it.
@export var active_range: float = 1100.0
@export var pool_size: int = 8

const LANE_LIFT := 0.0

var plan: CityPlan
var cars: Array[Vehicle] = []
var _pool: Array[Vehicle] = []
var _player: Node3D
var _rng := RandomNumberGenerator.new()
var _timer := 0.0
var _built_frame := -1


func _ready() -> void:
	_rng.seed = 4410
	if OS.has_feature("web"):
		cars_per_link = 2


func _stack() -> FreewayStack:
	if plan == null or plan.macro == null or plan.macro.freeway == null:
		return null
	return plan.macro.freeway.stack


func _traffic() -> Node:
	return get_parent().get_node_or_null("Traffic") if get_parent() else null


func _physics_process(delta: float) -> void:
	var st := _stack()
	if st == null:
		return
	if _player == null:
		_player = get_tree().get_first_node_in_group("player") as Node3D
		if _player == null:
			return
	_timer += delta
	if _timer >= 0.5:
		_timer = 0.0
		_maintain(st)
	_drive(st, delta)


func _exit_tree() -> void:
	for car in _pool:
		if is_instance_valid(car):
			car.free()
	_pool.clear()


func _player_xz() -> Vector2:
	var pw := WorldState.to_world(_player.global_position)
	return Vector2(pw.x, pw.z)


# --- Geometry -----------------------------------------------------------------------------------

## The connector's frame at distance s: [deck point, right (xz), bank, dir].
static func frame_at(l: Dictionary, s: float) -> Array:
	var run: PackedFloat32Array = l.run
	var n := run.size()
	s = clampf(s, 0.0, run[n - 1])
	var i := FreewayStack._seg_of(run, s)
	var j := mini(i + 1, n - 1)
	var f := clampf((s - run[i]) / maxf(run[j] - run[i], 0.001), 0.0, 1.0)
	var fa := FreewayStack.frame(l, i)
	var fb := FreewayStack.frame(l, j)
	var r := (fa[1] as Vector2).lerp(fb[1], f).normalized()
	return [(fa[0] as Vector3).lerp(fb[0], f), r, lerpf(fa[2], fb[2], f), Vector2(r.y, -r.x)]


## Lateral offset (m, + right of travel) of a car at s: its lane, drifting in from the main
## line's lane over the start touch run and out to the target's outer lane over the end one.
static func lane_offset(l: Dictionary, s: float, lane: int, u_in: float, u_out: float) -> float:
	var u := FreewayStack.LANE_LEFT + FreewayStack.LANE_W * (float(lane) + 0.5)
	var touch_a: float = l.touch_a
	var touch_b: float = l.touch_b
	var length: float = l.length
	if not is_nan(u_in) and s < touch_a + 24.0:
		u = lerpf(u_in, u, smoothstep(0.0, touch_a + 24.0, s))
	if not is_nan(u_out) and s > touch_b - 24.0:
		u = lerpf(u, u_out, smoothstep(touch_b - 24.0, length, s))
	return u


func _transform_at(car: Vehicle, st: FreewayStack) -> Transform3D:
	var t: Dictionary = car.traffic
	var l: Dictionary = st.links[int(t.link)]
	var s: float = t.s
	var p := _point(l, s, t)
	var q := _point(l, s + 2.0, t)
	var fwd := q - p
	if fwd.length_squared() < 0.0001:
		fwd = Vector3(0, 0, -1)
	return Transform3D(Basis.looking_at(fwd.normalized(), Vector3.UP),
		WorldState.to_local(p + Vector3.UP * car.road_lift()))


func _point(l: Dictionary, s: float, t: Dictionary) -> Vector3:
	var f := frame_at(l, s)
	var u := lane_offset(l, s, int(t.lane), float(t.u_in), float(t.u_out))
	var p := StackBuild.lat(f, u, 0.0)
	# A car just taken off the main line is still short of the connector's start.
	if s < 0.0:
		var d: Vector2 = f[3]
		p += Vector3(d.x, 0.0, d.y) * s
	return p


## Where the target's outer lane is, as an offset from the connector's centre line on its touch
## run (the target lies to the connector's left).
static func outer_lane_u(fw: Freeway, ri: int) -> float:
	var width := float(fw.routes[ri].width)
	var o0 := width * 0.5 + FreewayStack.LINK_WIDTH * 0.5
	return -(o0 - Freeway.lane_fraction(width, Freeway.LANES - 1) * width * 0.5)


# --- Upkeep ---------------------------------------------------------------------------------------

func _maintain(st: FreewayStack) -> void:
	var here := _player_xz()
	var active := here.distance_to(st.centre) < active_range
	for car in cars.duplicate():
		if not is_instance_valid(car) or not car.is_traffic() or not car.traffic.has("stack"):
			cars.erase(car)
			continue
		if not active:
			cars.erase(car)
			_retire(car)
	if not active:
		return
	var tm := _traffic()
	for k in st.links.size():
		var have := 0
		for car in cars:
			if int(car.traffic.link) == k:
				have += 1
		if have >= cars_per_link:
			continue
		if tm != null and _take_from_main(st, tm, k):
			continue
		# Nobody to take: one appears on the connector, away from the player.
		var l: Dictionary = st.links[k]
		var s := _rng.randf_range(float(l.taper_a), float(l.taper_b))
		var at: Vector3 = frame_at(l, s)[0]
		if Vector2(at.x, at.z).distance_to(here) < spawn_clear or not _room(k, s, 0):
			continue
		_spawn(st, k, s, _rng.randi() % 2, NAN)


## True if lane `lane` of connector k has room for a car at s.
func _room(k: int, s: float, lane: int) -> bool:
	for car in cars:
		if int(car.traffic.link) == k and absf(float(car.traffic.s) - s) < gap * 1.3:
			return false
	return true


## A main-line car of TrafficManager's in the diverge's reach, same direction: taken now and
## then. Returns true if one was taken.
func _take_from_main(st: FreewayStack, tm: Node, k: int) -> bool:
	if not ("freeway_cars" in tm):
		return false
	var l: Dictionary = st.links[k]
	var t0: float = (l.pt as PackedFloat32Array)[0]
	var ri: int = l.from
	var sg: int = l.from_sign
	for car: Vehicle in tm.freeway_cars:
		if not is_instance_valid(car) or not car.is_traffic() or car.get_parent() != tm:
			continue
		var t: Dictionary = car.traffic
		if int(t.get("fw", -1)) != ri or int(t.get("dir", 0)) != sg:
			continue
		# Within 18 m short of the diverge, coming toward it.
		var ahead := (t0 - float(t.t)) * sg
		if ahead < 0.0 or ahead > 18.0:
			continue
		if _rng.randf() > take_share or not _room(k, 0.0, 0) or BigVehicles.is_big(car.body_type):
			return false
		var width := float(plan.macro.freeway.routes[ri].width)
		var o0 := width * 0.5 + FreewayStack.LINK_WIDTH * 0.5
		var u_in := -(o0 - absf(float(t.lane)) * width * 0.5)
		(tm.freeway_cars as Array).erase(car)
		var keep := car.global_transform
		tm.remove_child(car)
		add_child(car)
		car.global_transform = keep
		var cruise := _rng.randf_range(speed_range.x, speed_range.y)
		car.traffic = {"stack": true, "link": k, "s": -ahead, "lane": _rng.randi() % 2, "u_in": u_in,
			"u_out": NAN, "speed": float(t.speed), "cruise": cruise}
		cars.append(car)
		return true
	return false


func _spawn(st: FreewayStack, k: int, s: float, lane: int, u_in: float) -> void:
	if Engine.get_process_frames() == _built_frame:
		return
	var car: Vehicle = null
	while not _pool.is_empty() and car == null:
		var c: Vehicle = _pool.pop_back()
		if is_instance_valid(c):
			car = c
	if car == null:
		if not PhysicsBudget.can_spawn():
			return
		_built_frame = Engine.get_process_frames()
		car = Vehicle.random_car(_rng)
	var cruise := _rng.randf_range(speed_range.x, speed_range.y)
	car.traffic = {"stack": true, "link": k, "s": s, "lane": lane, "u_in": u_in, "u_out": NAN,
		"speed": cruise, "cruise": cruise}
	car.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	car.freeze = true
	# Its transform before it enters the tree (AirTraffic._place_before_entry()).
	car.transform = global_transform.affine_inverse() * _transform_at(car, st)
	if car.get_parent() == null:
		add_child(car)
	car.traffic_speed = cruise
	cars.append(car)


## A car at the end of its connector: onto the target's outer lane as TrafficManager's freeway
## car, or retired if there is no TrafficManager to take it.
func _hand_over(st: FreewayStack, car: Vehicle) -> void:
	cars.erase(car)
	var tm := _traffic()
	var l: Dictionary = st.links[int(car.traffic.link)]
	if tm == null or not ("freeway_cars" in tm) or not tm.has_method("car_half_length"):
		_retire(car)
		return
	var fw := plan.macro.freeway
	var ri: int = l.to
	var sg: int = l.to_sign
	var pt: PackedFloat32Array = l.pt
	var width := float(fw.routes[ri].width)
	var keep := car.global_transform
	var speed: float = car.traffic.speed
	remove_child(car)
	tm.add_child(car)
	car.global_transform = keep
	car.traffic = {"fw": ri, "t": pt[pt.size() - 1], "dir": sg,
		"lane": Freeway.lane_fraction(width, Freeway.LANES - 1) * float(sg),
		"speed": maxf(speed, float(tm.get("freeway_speed")) * 0.95), "half": tm.car_half_length(car), "rear": tm.car_rear_length(car)}
	car.traffic_speed = car.traffic.speed
	(tm.freeway_cars as Array).append(car)


func _retire(car: Vehicle) -> void:
	if not is_instance_valid(car):
		return
	if car.is_traffic() and car.get_parent() == self and _pool.size() < pool_size:
		remove_child(car)
		_pool.append(car)
	else:
		car.queue_free()


# --- Driving --------------------------------------------------------------------------------------

func _drive(st: FreewayStack, delta: float) -> void:
	for car in cars.duplicate():
		if not is_instance_valid(car) or not car.is_traffic() or not car.traffic.has("stack"):
			cars.erase(car)
			continue
		var t: Dictionary = car.traffic
		var k: int = t.link
		var l: Dictionary = st.links[k]
		var s: float = t.s
		var ahead := INF
		for other in cars:
			if other == car or not is_instance_valid(other) or not other.traffic.has("stack"):
				continue
			if int(other.traffic.link) != k:
				continue
			var d := float(other.traffic.s) - s
			if d > 0.0 and d < ahead:
				ahead = d
		var want: float = t.cruise
		var speed: float = t.speed
		var room := ahead - gap
		if room < speed * 1.5:
			want = minf(want, maxf(room / 1.5, 0.0))
		if want < speed:
			speed = maxf(want, speed - brake * delta)
		else:
			speed = minf(want, speed + accel * delta)
		s += speed * delta
		t.s = s
		t.speed = speed
		car.traffic_speed = speed
		if is_nan(float(t.u_out)) and s > float(l.touch_b) - 30.0:
			t.u_out = outer_lane_u(plan.macro.freeway, int(l.to))
		if s >= float(l.length):
			_hand_over(st, car)
			continue
		car.global_transform = _transform_at(car, st)
