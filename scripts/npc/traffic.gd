class_name TrafficManager
extends Node3D
## Keeps a handful of cars driving the lanes around the player. Traffic cars are frozen
## (kinematic) Vehicles moved along road lines; they turn at intersections at random. Anything
## fast that hits one unfreezes it into a normal physics car that rolls to a stop.

@export var max_cars: int = 14
## Spawn between these distances from the player (meters).
@export var spawn_min: float = 120.0
@export var spawn_max: float = 260.0
@export var despawn_distance: float = 380.0
@export var speed_range: Vector2 = Vector2(9.0, 15.0)
@export var turn_chance: float = 0.35

var plan: CityPlan
var cars: Array[Vehicle] = []
var _player: Node3D
var _rng := RandomNumberGenerator.new()
var _timer: float = 0.0


func _ready() -> void:
	_rng.seed = 99


func _physics_process(delta: float) -> void:
	if plan == null:
		return
	if _player == null:
		_player = get_tree().get_first_node_in_group("player") as Node3D
		if _player == null:
			return
	_timer += delta
	if _timer >= 0.5:
		_timer = 0.0
		_maintain()
	for car in cars.duplicate():
		if not is_instance_valid(car) or not car.is_traffic():
			cars.erase(car)
			continue
		_drive(car, delta)


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
			car.queue_free()
	var tries := 0
	while cars.size() < max_cars and tries < 8 and PhysicsBudget.can_spawn():
		tries += 1
		_spawn_near(pw)


func _spawn_near(pw: Vector3) -> void:
	var axis := _rng.randi_range(0, 1)
	var center := plan.block_index_at(Vector2(pw.x, pw.z))
	var index := (center.x if axis == CityPlan.AXIS_X else center.y) + _rng.randi_range(-2, 3)
	var along := (pw.z if axis == CityPlan.AXIS_X else pw.x) + _rng.randf_range(spawn_min, spawn_max) * (1.0 if _rng.randf() < 0.5 else -1.0)
	var dir := 1 if _rng.randf() < 0.5 else -1
	var lane := _lane_offset(axis, index, dir)
	var pos2 := Vector2(plan.road_pos(axis, index) + lane, along) if axis == CityPlan.AXIS_X else Vector2(along, plan.road_pos(axis, index) + lane)
	if plan.zone_at(pos2) != MacroMap.Zone.CITY:
		return
	var car := Vehicle.random_car(_rng)
	car.traffic = {"axis": axis, "index": index, "dir": dir, "lane": lane, "speed": _rng.randf_range(speed_range.x, speed_range.y)}
	car.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	car.freeze = true
	car.position = WorldState.to_local(Vector3(pos2.x, 0.55, pos2.y))
	car.rotation.y = _heading(axis, dir)
	add_child(car)
	car.traffic_speed = car.traffic.speed
	cars.append(car)


## Right-hand traffic: the lane sits to the right of the direction of travel.
func _lane_offset(axis: int, index: int, dir: int) -> float:
	var width := plan.road_width(axis, index)
	var lanes := 2 if width > plan.street_width + 1.0 else 1
	var lane_w := width * 0.5 / (lanes + 0.5)
	var n := _rng.randi_range(1, lanes)
	var side := -dir if axis == CityPlan.AXIS_X else dir
	return side * lane_w * n


func _heading(axis: int, dir: int) -> float:
	var d := Vector3(0.0, 0.0, dir) if axis == CityPlan.AXIS_X else Vector3(dir, 0.0, 0.0)
	return atan2(-d.x, -d.z)


func _drive(car: Vehicle, delta: float) -> void:
	var t: Dictionary = car.traffic
	var axis: int = t.axis
	var dir: int = t.dir
	var speed: float = t.speed
	var wp := WorldState.to_world(car.global_position)
	var along := wp.z if axis == CityPlan.AXIS_X else wp.x
	var cross_axis := CityPlan.AXIS_Z if axis == CityPlan.AXIS_X else CityPlan.AXIS_X
	# Next crossing road in the direction of travel.
	var cross_index := plan._index_at(cross_axis, along) + (1 if dir > 0 else 0)
	var cross_pos := plan.road_pos(cross_axis, cross_index)
	var new_along := along + dir * speed * delta
	if (dir > 0 and new_along >= cross_pos) or (dir < 0 and new_along <= cross_pos):
		# Reached an intersection center: maybe turn.
		if _rng.randf() < turn_chance:
			var new_dir := 1 if _rng.randf() < 0.5 else -1
			var lane := _lane_offset(cross_axis, cross_index, new_dir)
			t.axis = cross_axis
			t.index = cross_index
			t.dir = new_dir
			t.lane = lane
			var road := plan.road_pos(cross_axis, cross_index)
			# Rebuild the world position on the new road, keeping the intersection's coordinate.
			var pos2 := Vector2(wp.x, road + lane) if cross_axis == CityPlan.AXIS_Z else Vector2(road + lane, wp.z)
			car.global_position = WorldState.to_local(Vector3(pos2.x, wp.y, pos2.y))
			car.rotation.y = _heading(cross_axis, new_dir)
			return
	var lane_pos: float = plan.road_pos(axis, t.index) + t.lane
	var new_wp := Vector3(lane_pos, wp.y, new_along) if axis == CityPlan.AXIS_X else Vector3(new_along, wp.y, lane_pos)
	car.global_position = WorldState.to_local(new_wp)
	car.rotation.y = _heading(axis, dir)
	car.rotation.x = 0.0
	car.rotation.z = 0.0
