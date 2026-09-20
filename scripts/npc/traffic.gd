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

var plan: CityPlan
var cars: Array[Vehicle] = []
## Cars on the airport drop-off loop (traffic dict holds "loop" and "t").
var loop_cars: Array[Vehicle] = []
var _player: Node3D
var _rng := RandomNumberGenerator.new()
var _timer: float = 0.0
var _loop_lengths: PackedFloat32Array = PackedFloat32Array()


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
	_drive_loops(delta)


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
			car.queue_free()
	var density := density_at(Vector2(pw.x, pw.z))
	var want := roundi(max_cars * density)
	var tries := 0
	while cars.size() < want and tries < 12 and PhysicsBudget.can_spawn():
		tries += 1
		_spawn_near(pw, density)
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
	if plan.zone_at(pos2) != MacroMap.Zone.CITY:
		return
	var car := Vehicle.random_car(_rng)
	var speed := _rng.randf_range(speed_range.x, speed_range.y) * lerpf(1.0, dense_speed_factor, density)
	car.traffic = {"axis": axis, "index": index, "dir": dir, "lane": lane, "speed": speed}
	car.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	car.freeze = true
	car.position = WorldState.to_local(Vector3(pos2.x, 0.55 + plan.macro.relief_at(pos2), pos2.y))
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
	# Follow the city's rolling ground and pitch the nose along the slope ahead.
	var here := plan.macro.relief_at(Vector2(new_wp.x, new_wp.z))
	var forward := Vector3(0.0, 0.0, dir) if axis == CityPlan.AXIS_X else Vector3(dir, 0.0, 0.0)
	var ahead := plan.macro.relief_at(Vector2(new_wp.x + forward.x * 4.0, new_wp.z + forward.z * 4.0))
	new_wp.y = 0.55 + here
	car.global_position = WorldState.to_local(new_wp)
	car.rotation.y = _heading(axis, dir)
	car.rotation.x = atan2(ahead - here, 4.0)
	car.rotation.z = 0.0


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
			car.queue_free()
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
			_spawn_loop_car(i, slot * loop_gap)
			taken[slot] = true
			added += 1


func _spawn_loop_car(loop_index: int, t: float) -> void:
	var loop: PackedVector2Array = plan.macro.terminal_loops[loop_index]
	var at := _loop_point(loop, t)
	var pos2: Vector2 = at[0]
	var dir2: Vector2 = at[1]
	var car := Vehicle.random_car(_rng)
	car.traffic = {"loop": loop_index, "t": t, "speed": loop_speed * _rng.randf_range(0.85, 1.1)}
	car.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	car.freeze = true
	car.position = WorldState.to_local(Vector3(pos2.x, 0.55 + 0.16, pos2.y))
	car.rotation.y = atan2(-dir2.x, -dir2.y)
	add_child(car)
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
			car.global_position = WorldState.to_local(Vector3(pos2.x, 0.55 + 0.16, pos2.y))
			car.rotation = Vector3(0.0, atan2(-dir2.x, -dir2.y), 0.0)
