extends RefCounted
## Motorcycles (Motorcycle, tools/make_motorcycles.py) for tests/smoke_test.gd. Loaded at run time
## (not named there), so it compiles after the autoloads and can name Motorcycle, MotoRider and
## TrafficManager. On a deck high over the street, like the car checks. Checks: the three bodies
## build from their models (steer and wheel nodes, a far twin, two physics wheels, lamps); a
## parked bike stands on its side stand and goes to sleep; ridden, it accelerates, turns (the
## drawn lean into the turn, the body held upright), wheelies on boost and flies when it leaves
## the ground; random_car() never rolls one; a traffic bike carries its rider, posed on the seat
## with his hands on the grips, and a hit knocks him off as a ragdoll and drops the bike; the pool
## hands a bike back only for a bike; the player riding is the hero on the seat (HeroRide), and a
## crash throws him off and puts him back on his feet; a bike filters past a stopped queue between
## the lanes without touching it; the kerbs' swap is a pure hash.

var _t: Node
var _tree: SceneTree
var _city: Node3D
var _traffic: TrafficManager
var _ws: Node
var _deck: StaticBody3D
var _top: Vector3
var _bikes: Array = []


func run(t: Node, city: Node3D) -> void:
	_t = t
	_tree = t.get_tree()
	_city = city
	_traffic = city.get_node("Traffic") as TrafficManager
	_ws = _tree.root.get_node("/root/WorldState")
	var player := _tree.get_first_node_in_group("player") as Player
	if player.is_driving():
		player.exit_vehicle()
	var police: Node = city.get_node_or_null("Police")
	var police_was: Variant = police.get("enabled") if police else null
	if police:
		police.set("enabled", false)
	var home: Vector3 = _ws.to_world(player.global_position)
	_top = player.global_position + Vector3(0.0, 360.0, 0.0)
	_build_deck()
	player.global_position = _top + Vector3(0.0, 1.2, 70.0)
	player.velocity = Vector3.ZERO
	await _ticks(3)

	_tables()
	await _builds()
	await _parked()
	await _ride()
	await _traffic_rider()
	_pool()
	await _player_ride(player)
	_swap_hash()

	for b in _bikes:
		if is_instance_valid(b):
			b.queue_free()
	_bikes.clear()
	_deck.queue_free()
	if player.is_driving():
		player.exit_vehicle()
	player.set_physics_process(true)
	player.global_position = _ws.to_local(home)
	player.velocity = Vector3.ZERO
	await _filter()
	if police:
		police.set("enabled", police_was)
	await _ticks(3)


func _check(ok: bool, label: String) -> void:
	_t._check(ok, label)


func _ticks(n: int) -> void:
	for i in n:
		await _tree.physics_frame


func _build_deck() -> void:
	_deck = StaticBody3D.new()
	_deck.collision_layer = 1
	_deck.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400.0, 1.0, 240.0)
	shape.shape = box
	_deck.add_child(shape)
	_city.add_child(_deck)
	_deck.global_position = _top - Vector3(0.0, 0.5, 0.0)


func _bike(kind: int, at: Vector2, traffic: bool = false) -> Motorcycle:
	var m := Motorcycle.make(Motorcycle.TYPES[kind], 77 + kind)
	if traffic:
		m.traffic = {"axis": 0, "index": 0, "dir": -1, "lane": 0.0, "speed": 0.0}
		m.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		m.freeze = true
	m.position = _city.to_local(_top + Vector3(at.x, m.road_lift() if traffic else 0.5, at.y))
	_city.add_child(m)
	_bikes.append(m)
	return m


func _tables() -> void:
	var never := true
	for type: int in Motorcycle.TYPES:
		never = never and int(Vehicle.BODY_ODDS.get(type, -1)) == 0 and Motorcycle.is_moto(type)
	var rolled := 0
	for s in 600:
		var rng := RandomNumberGenerator.new()
		rng.seed = 7100 + s
		var car := Vehicle.random_car(rng)
		if Motorcycle.is_moto(car.body_type):
			rolled += 1
		car.free()
	_check(never and rolled == 0 and Motorcycle.DIMS.size() == 3 and Motorcycle.PHYS.size() == 3,
			"motorcycles are three body types random_car() never rolls (BODY_ODDS 0; rolled %d of 600)" % rolled)


func _builds() -> void:
	var ok := true
	var why := ""
	var worst := 0.0
	for k in 3:
		var t0 := Time.get_ticks_usec()
		var m := _bike(k, Vector2(-60.0 + k * 6.0, -60.0))
		worst = maxf(worst, float(Time.get_ticks_usec() - t0) / 1000.0)
		var far := 0
		for mm: MeshInstance3D in m._body_meshes:
			if String(mm.name).ends_with("_far"):
				far += 1
		var good := m._has_model and m._steer != null and m._wheel_f != null and m._wheel_r != null and far == 1 \
				and m.wheels.size() == 2 and m.get_node_or_null("Pose/BodyModel/NightLights") != null \
				and m._wheel_f.get_parent() == m._steer
		if not good:
			ok = false
			why += " %s(model %s steer %s wf %s wr %s far %d wheels %d)" % [m.display_name(), m._has_model, m._steer != null, m._wheel_f != null, m._wheel_r != null, far, m.wheels.size()]
	_check(ok, "each bike builds from its model: steer, both wheels (the front under the fork), a far twin, two physics wheels, lamps (%.1f ms worst)%s" % [worst, why])
	await _ticks(2)


func _parked() -> void:
	var bikes: Array = []
	for k in 3:
		bikes.append(_bike(k, Vector2(-20.0 + k * 5.0, -20.0)))
	await _ticks(150)
	var ok := true
	var why := ""
	for m: Motorcycle in bikes:
		var up := m.global_basis.y.y
		var touching := m.wheels[0].is_in_contact() and m.wheels[1].is_in_contact()
		if up < 0.97 or not touching or absf(m.lean - m.stand_lean) > 0.02 or m.fallen:
			ok = false
			why += " %s(up %.3f contact %s lean %.3f fallen %s)" % [m.display_name(), up, touching, m.lean, m.fallen]
	_check(ok, "a parked bike stands on both tyres, its body upright, drawn leaning on its side stand%s" % why)
	for m: Motorcycle in bikes:
		for i in 4:
			m.settle()
	await _ticks(2)
	var asleep := true
	for m: Motorcycle in bikes:
		asleep = asleep and PhysicsServer3D.body_get_state(m.get_rid(), PhysicsServer3D.BODY_STATE_SLEEPING)
	_check(asleep, "a parked bike goes to sleep (Vehicle.settle)")


func _ride() -> void:
	var m := _bike(0, Vector2(-120.0, 80.0))
	m.rotation.y = 0.0
	await _ticks(60)
	var dummy := Node3D.new()
	_city.add_child(dummy)
	m.driver = dummy
	Input.action_press("move_forward")
	await _ticks(180)
	var v := m.linear_velocity.dot(-m.global_basis.z)
	_check(v > 14.0 and m.global_basis.y.y > 0.97, "ridden, a bike gets going and stays upright (%.1f m/s after 3 s, up %.3f)" % [v, m.global_basis.y.y])
	var yaw0 := m.global_rotation.y
	Input.action_press("move_right")
	await _ticks(90)
	var turned := wrapf(m.global_rotation.y - yaw0, -PI, PI)
	_check(turned < -0.3 and m.lean < -0.2 and m.global_basis.y.y > 0.93,
			"steered right it turns right, the drawn bike leans into the turn and the body stays up (turned %.2f rad, lean %.2f, up %.3f)" % [turned, m.lean, m.global_basis.y.y])
	Input.action_release("move_right")
	m.linear_velocity = -m.global_basis.z * 8.0
	m.hold_crash_watch(3)
	Input.action_press("boost")
	await _ticks(40)
	var w := m.wheelie
	Input.action_release("boost")
	_check(w > 0.2, "boost lifts the front: a wheelie (%.2f rad)" % w)
	Input.action_release("move_forward")
	m.hold_crash_watch(6)
	m.global_position += Vector3.UP * 30.0
	m.linear_velocity = Vector3(0.0, 2.0, 0.0)
	await _ticks(30)
	_check(m.is_airborne() and m._was_airborne and m.gravity_scale < 1.0 and m.global_basis.y.y > 0.8,
			"in the air it flies like a car (Vehicle._fly: gravity %.2f, level %.2f)" % [m.gravity_scale, m.global_basis.y.y])
	m.driver = null
	dummy.queue_free()


func _traffic_rider() -> void:
	var m := _bike(1, Vector2(40.0, 40.0), true)
	m.traffic_speed = 0.0
	await _ticks(20)
	var r := m._rider
	var ok := r != null and is_instance_valid(r) and r.is_inside_tree()
	var seat_err := INF
	var grip_err := INF
	if ok and r._sk != null:
		var sk: Skeleton3D = r._sk
		var hips := sk.global_transform * sk.get_bone_global_pose(sk.find_bone("Hips"))
		var seat: Vector3 = m.rider_frame().global_transform * (m.geo().seat as Vector3)
		seat_err = hips.origin.distance_to(seat + Vector3.UP * 0.1)
		var hand := sk.global_transform * sk.get_bone_global_pose(sk.find_bone("RightHand"))
		var g: Vector3 = m.geo().grip
		grip_err = hand.origin.distance_to(m.rider_frame().global_transform * g)
	_check(ok and seat_err < 0.3 and grip_err < 0.2,
			"a traffic bike carries its rider, hips on the seat and a hand on the grip (seat %.2f m, grip %.2f m)" % [seat_err, grip_err])
	m.drop_out_of_traffic(Vector3(0.0, 0.0, 2000.0))
	await _ticks(30)
	var dolls := 0
	for n in _city.find_children("*", "Ragdoll", true, false):
		if (n as Node3D).global_position.distance_to(m.global_position) < 12.0:
			dolls += 1
	_check(m._rider == null and m.fallen and dolls > 0 and not m.is_traffic(),
			"knocked out of the traffic, its rider comes off as a ragdoll and the bike goes down (dolls %d, fallen %s)" % [dolls, m.fallen])


func _pool() -> void:
	var m := Motorcycle.make(Motorcycle.TYPES[2], 5)
	m.traffic = {"axis": 0, "index": 0, "dir": 1, "lane": 0.0, "speed": 0.0}
	_traffic._pool.append(m)
	var plain := _traffic._new_car(-1)
	var plain_moto := plain is Motorcycle
	if plain != m:
		_traffic._pool.erase(plain)
		plain.free()
	var back := _traffic._new_car(Motorcycle.TYPES[2])
	_check(not plain_moto and back == m, "the pool hands a bike back only for a bike")
	if is_instance_valid(back) and back.get_parent() == null:
		back.free()


func _player_ride(player: Player) -> void:
	var m := _bike(0, Vector2(80.0, -60.0))
	await _ticks(40)
	player.global_position = m.global_position + Vector3(1.5, 0.5, 0.0)
	player.enter_vehicle(m)
	await _ticks(20)
	var avatar := player.avatar
	var ride: Node = avatar.get("_skeleton").get_node_or_null("HeroRide") if avatar and avatar.get("_skeleton") else null
	var seat_err := INF
	if ride != null:
		var sk: Skeleton3D = avatar.get("_skeleton")
		var hips := sk.global_transform * sk.get_bone_global_pose(sk.find_bone("Hips"))
		seat_err = hips.origin.distance_to(m.rider_frame().global_transform * (m.geo().seat as Vector3) + Vector3.UP * 0.1)
	_check(player.is_driving() and player.visible and ride != null and seat_err < 0.3,
			"the player on a bike is the hero, seen, on its seat (HeroRide; %.2f m)" % seat_err)
	m.linear_velocity = -m.global_basis.z * 15.0
	m.throw_rider(Vector3.UP * 2.0)
	await _ticks(4)
	var thrown := not player.is_driving() and not player.visual.visible and _tree.root.find_child("MotoThrow", true, false) != null
	var waited := 0
	while not player.is_physics_processing() and waited < 400:
		await _ticks(1)
		waited += 1
	_check(thrown and player.is_physics_processing() and player.visual.visible and m.fallen,
			"a crash throws the hero off as a ragdoll and he gets up again (%d ticks)" % waited)


## Motorcycle.parked_swap is a pure hash of the seed and the spot: the same stall swaps the same.
func _swap_hash() -> void:
	var plan: CityPlan = _city.get("plan")
	var holder := Node3D.new()
	_city.add_child(holder)
	var fake := _FakeChunk.new()
	fake.plan = plan
	var swapped := 0
	var same := true
	for i in 300:
		var spot := [Vector3(float(i) * 8.0 + 2000.0, 0.4, 37.0), 0.0, 1.0]
		var a := Vehicle.new()
		a.position = spot[0]
		var b := Vehicle.new()
		b.position = spot[0]
		var ra := Motorcycle.parked_swap(fake, a, spot, holder)
		var rb := Motorcycle.parked_swap(fake, b, spot, holder)
		same = same and (ra is Motorcycle) == (rb is Motorcycle) and ra.body_type == rb.body_type
		if ra is Motorcycle:
			swapped += 1
		for x in [ra, rb]:
			if is_instance_valid(x):
				x.free()
	for c in holder.get_children():
		c.free()
	holder.queue_free()
	_check(same and swapped > 3 and swapped < 90, "the kerbs' swap to motorcycles is a pure hash of the stall (%d of 300 stalls)" % swapped)


class _FakeChunk:
	extends Node
	var plan: CityPlan
	var _cars: Array = []


## A bike threading a stopped queue between the lanes, on a real two-lane street.
func _filter() -> void:
	var plan: CityPlan = _city.get("plan")
	var player := _tree.get_first_node_in_group("player") as Player
	var pw: Vector3 = _ws.to_world(player.global_position)
	var bi := plan.block_index_at(Vector2(pw.x, pw.z))
	var axis := CityPlan.AXIS_X
	var index := -99999
	for d in [0, 1, -1, 2, -2, 3, -3, 4, -4]:
		if plan.road_width(axis, bi.x + d) > plan.street_width + 1.0 and plan.road_open(axis, bi.x + d, pw.z):
			index = bi.x + d
			break
	if index == -99999:
		_check(true, "lane filtering: no two-lane road near (skipped)")
		return
	var was_staged := _traffic.staged
	_traffic.staged = true
	var dir := 1
	var cross := CityPlan.AXIS_Z
	var k := plan._index_at(cross, pw.z + 60.0) + 1
	var node := Vector2i(index, k)
	TrafficSignals.force(plan, node.x, node.y, axis, TrafficSignals.Light.RED, 1.0)
	for c in _traffic.cars.duplicate():
		if is_instance_valid(c) and int(c.traffic.get("axis", -1)) == axis and int(c.traffic.get("index", -99999)) == index:
			_traffic.cars.erase(c)
			_traffic._retire(c)
	var line := plan.road_pos(cross, k) - float(dir) * (plan.road_width(cross, k) * 0.5 + _traffic.stop_line_back)
	var queue: Array = []
	var nose := line - 1.0
	for j in 4:
		var car := _traffic.place_car(axis, index, dir, 0, nose, 0.0, false)
		car.traffic.v = 0.0
		car.traffic_speed = 0.0
		var along := nose - float(car.traffic.half)
		_put(car, axis, index, along)
		queue.append(car)
		nose = along - float(car.traffic.rear) - 2.4
	var bike := _traffic.place_car(axis, index, dir, 0, nose - 30.0, 6.0, false, Motorcycle.TYPES[0])
	_put(bike, axis, index, nose - 30.0)
	var closest := INF
	var filtered := false
	for i in 420:
		await _ticks(1)
		if not is_instance_valid(bike):
			break
		TrafficSignals.force(plan, node.x, node.y, axis, TrafficSignals.Light.RED, 1.0)
		var bp: Vector3 = _ws.to_world(bike.global_position)
		for c: Vehicle in queue:
			if not is_instance_valid(c):
				continue
			var cp: Vector3 = _ws.to_world(c.global_position)
			var dz := absf(bp.z - cp.z)
			if dz < float(c.traffic.half) + 1.0:
				closest = minf(closest, absf(bp.x - cp.x))
		if bp.z > _ws.to_world((queue[queue.size() - 1] as Vehicle).global_position).z + 2.0:
			filtered = true
	_check(filtered and closest > 1.15, "a bike filters past a stopped queue between the lanes, clear of every car (closest %.2f m sideways)" % closest)
	for c in queue + [bike]:
		if is_instance_valid(c):
			_traffic.cars.erase(c)
			_traffic._retire(c)
	_traffic.staged = was_staged


func _put(car: Vehicle, axis: int, index: int, along: float) -> void:
	var plan: CityPlan = _city.get("plan")
	var lane: float = car.traffic.lane
	var p2 := Vector2(plan.road_pos(axis, index) + lane, along) if axis == 0 else Vector2(along, plan.road_pos(axis, index) + lane)
	car.global_position = _ws.to_local(Vector3(p2.x, 0.1 + car.road_lift() + _traffic._relief(p2), p2.y))
	car.traffic.along = along
