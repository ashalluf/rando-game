extends RefCounted
## The third wave of everyday car bodies (Cars3, tools/make_cars_3.py: the EV hatch, the luxury
## sedan, the compact SUV, the work truck, the coupe) for tests/smoke_test.gd. Loaded at run time
## (not named there), so it compiles after the autoloads and can name Vehicle, Cars3 and CarCabin.
## Stages its own deck high over wherever the player stands and puts everything back. Checks: the
## roll table gives each new body its share only out of the ends of older ranges (every roll keeps
## the type the second wave gave it unless a new body took it) and `CARS_3=0` hands every slice
## back exactly; random_car() spends the caller's rng as before and rolls all five; each builds as
## a model with its glass, a far twin, lamps and four wheels inside the traffic's build budget and
## stands on its wheels where traffic stands it; kinematic traffic carries a driver; a hit hands it
## to physics and CarDamage; privacy glass, engine voices and the work truck's fleet paint.

var _t: Node
var _tree: SceneTree
var _city: Node3D
var _ws: Node
var _deck: StaticBody3D
var _top: Vector3
var _cars: Array = []

## The roll table as the second wave left it ([end, type]); the third wave may only hand a roll
## to one of its own types.
const WAVE2_MAP := [
	[210, Vehicle.BodyType.SEDAN], [250, Vehicle.BodyType.HATCHBACK],
	[370, Vehicle.BodyType.PICKUP], [400, Vehicle.BodyType.SUV],
	[475, Vehicle.BodyType.VAN], [515, Vehicle.BodyType.MINIVAN],
	[600, Vehicle.BodyType.SPORTS], [630, Vehicle.BodyType.SUV], [660, Vehicle.BodyType.HATCHBACK],
	[690, Vehicle.BodyType.SUPER], [705, Vehicle.BodyType.BEATER],
	[720, Vehicle.BodyType.SPIDER], [730, Vehicle.BodyType.MINIVAN],
	[750, Vehicle.BodyType.HYPER], [760, Vehicle.BodyType.BEATER],
	[775, Vehicle.BodyType.TRACK], [780, Vehicle.BodyType.MINIVAN],
	[970, Vehicle.BodyType.CROSSOVER], [990, Vehicle.BodyType.SUV], [1000, Vehicle.BodyType.BEATER],
]


func run(t: Node, city: Node3D) -> void:
	_t = t
	_tree = t.get_tree()
	_city = city
	_ws = _tree.root.get_node("/root/WorldState")
	_rolls()
	_switch()
	_rng_stream()
	_tables()
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
	player.global_position = _top + Vector3(0.0, 1.2, 60.0)
	player.velocity = Vector3.ZERO
	await _ticks(3)

	await _builds()
	await _traffic()

	for c in _cars:
		if is_instance_valid(c):
			c.queue_free()
	_cars.clear()
	_deck.queue_free()
	player.global_position = _ws.to_local(home)
	player.velocity = Vector3.ZERO
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
	box.size = Vector3(160.0, 1.0, 120.0)
	shape.shape = box
	_deck.add_child(shape)
	_city.add_child(_deck)
	_deck.global_position = _top - Vector3(0.0, 0.5, 0.0)


func _car(type: int, at: Vector2, traffic: bool = false) -> Vehicle:
	var car := Vehicle.new()
	car.setup(type as Vehicle.BodyType, Color(0.35, 0.38, 0.42), Vehicle.Addon.NONE)
	car.look_seed = 5151
	if traffic:
		car.traffic = {"axis": 0, "index": 0, "dir": -1, "lane": 0.0, "speed": 0.0}
		car.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		car.freeze = true
	car.position = _city.to_local(_top + Vector3(at.x, car.road_lift() if traffic else 0.9, at.y))
	_city.add_child(car)
	_cars.append(car)
	return car


static func _wave2(roll: int) -> int:
	for row: Array in WAVE2_MAP:
		if roll < int(row[0]):
			return int(row[1])
	return -1


func _rolls() -> void:
	# The fourth wave (Cars4) takes slices of its own: this file checks the third wave's table.
	var c4 := Cars4.enabled
	Cars4.enabled = false
	_rolls_3()
	Cars4.enabled = c4


func _rolls_3() -> void:
	var counts := {}
	var last := 0
	var ordered := true
	for row: Array in Vehicle.ROLL_MAP:
		ordered = ordered and int(row[0]) > last
		var owner := Cars4.row_type(row)
		counts[owner] = int(counts.get(owner, 0)) + int(row[0]) - last
		last = int(row[0])
	var shares := ordered and last == 1000
	for type: int in Cars3.TYPES:
		shares = shares and int(Vehicle.BODY_ODDS.get(type, 0)) > 0 \
				and int(counts.get(type, 0)) == int(Vehicle.BODY_ODDS[type])
	_check(shares, "the EV hatch, luxury sedan, compact SUV, work truck and coupe each have a ROLL_MAP share equal to BODY_ODDS (%s)"
			% [Cars3.TYPES.map(func(t: int) -> int: return int(counts.get(t, 0)))])
	# Every roll keeps its second-wave type unless one of the five took it; every row the five
	# took names the type that had it; and every older type's range still starts where it did.
	var kept := 0
	var taken := 0
	var stray := 0
	var named := true
	var wave2_starts := {}
	var now_starts := {}
	for roll in 1000:
		var before := _wave2(roll)
		var now := int(Vehicle._body_for_roll(roll))
		if not wave2_starts.has(before):
			wave2_starts[before] = roll
		if not now_starts.has(now):
			now_starts[now] = roll
		if now == before:
			kept += 1
		elif Cars3.is_cars_3(now):
			taken += 1
		else:
			stray += 1
	for row: Array in Vehicle.ROLL_MAP:
		if row.size() > 3:
			continue
		if row.size() > 2:
			named = named and Cars3.is_cars_3(int(row[1])) and not Cars3.is_cars_3(int(row[2]))
			named = named and _wave2(int(row[0]) - 1) == int(row[2])
		else:
			named = named and not Cars3.is_cars_3(int(row[1]))
	var starts := true
	for type: int in wave2_starts:
		starts = starts and int(now_starts.get(type, -1)) == int(wave2_starts[type])
	_check(stray == 0 and taken == 165 and kept == 835 and named and starts,
			"a roll keeps its second-wave body unless a new one took it, and every old range keeps its start (kept %d, taken %d, elsewhere %d, rows name their old owner %s, starts %s)"
			% [kept, taken, stray, named, starts])


## CARS_3=0: every slice goes back to whoever had it, for all 1000 rolls.
func _switch() -> void:
	var c4 := Cars4.enabled
	Cars4.enabled = false
	var was := Cars3.enabled
	Cars3.enabled = false
	var same := 0
	for roll in 1000:
		if int(Vehicle._body_for_roll(roll)) == _wave2(roll):
			same += 1
	var none := true
	for s in 300:
		var rng := RandomNumberGenerator.new()
		rng.seed = 7100 + s
		var car := Vehicle.random_car(rng)
		none = none and not Cars3.is_cars_3(car.body_type)
		car.free()
	Cars3.enabled = was
	Cars4.enabled = c4
	_check(same == 1000 and none, "CARS_3=0 rolls exactly the second wave's table (%d of 1000) and never a new body" % same)


func _rng_stream() -> void:
	var same := true
	var made := {}
	var fleet := 0
	var trucks := 0
	var n := 3000
	for s in n:
		var a := RandomNumberGenerator.new()
		a.seed = 41000 + s
		var b := RandomNumberGenerator.new()
		b.seed = 41000 + s
		var car := Vehicle.random_car(a)
		b.randi_range(0, 999)
		if b.randf() < 0.35:
			b.randi_range(1, Vehicle.Addon.size() - 1)
		b.randi()
		same = same and a.state == b.state
		made[car.body_type] = int(made.get(car.body_type, 0)) + 1
		if car.body_type == Vehicle.BodyType.WORK_TRUCK:
			trucks += 1
			if Cars3.WORK_FLEET_PAINTS.has(car.paint):
				fleet += 1
		car.free()
	var near := true
	var why := ""
	for type: int in Cars3.TYPES:
		var want := float(Vehicle.BODY_ODDS[type]) / 1000.0 * n
		var got := int(made.get(type, 0))
		near = near and absf(got - want) < want * 0.45 + 6.0
		why += " %s %d/%.0f" % [Vehicle.BODY_NAMES[type], got, want]
	_check(same and near, "random_car() spends the caller's rng exactly as before and rolls the five in about their shares (%s)" % why)
	_check(trucks > 0 and fleet > trucks * 0.3 and fleet < trucks,
			"most work trucks wear a fleet colour, not all (%d of %d)" % [fleet, trucks])


func _tables() -> void:
	var ok := true
	for type: int in Cars3.TYPES:
		ok = ok and Vehicle.BODY_MODELS.has(type) and Vehicle.WHEEL_POSE.has(type) and Cars3.DIMS.has(type) \
				and ResourceLoader.exists(String(Vehicle.BODY_MODELS[type]))
		var d: Dictionary = Cars3.DIMS[type]
		var w: Dictionary = Vehicle.WHEEL_POSE[type]
		# The generated wheel's hub sits on the road: hub height = road + the model's tyre radius.
		ok = ok and absf(float(w.y) - float(w.r) - float(d.road)) < 0.004
	_check(ok, "each new body has its model, WHEEL_POSE row and _dims, and its wheel stands on the road it is stood on")
	_check(CarCabin.PRIVACY_BODIES.has(Vehicle.BodyType.COMPACT_SUV) and CarCabin.PRIVACY_BODIES.has(Vehicle.BodyType.WORK_TRUCK),
			"the compact SUV and the work truck have privacy glass behind the front seats")
	_check(EngineAudio.profile_for_type(Vehicle.BodyType.WORK_TRUCK) == "v8" and EngineAudio.profile_for_type(Vehicle.BodyType.COUPE) == "v8"
			and EngineAudio.profile_for_type(Vehicle.BodyType.LUX_SEDAN) == "four",
			"the work truck and the coupe have the V8's voice, the rest the four")


func _builds() -> void:
	var worst := 0.0
	var ok := true
	var why := ""
	var x := -60.0
	for type: int in Cars3.TYPES:
		_car(type, Vector2(x, -40.0))
		var t0 := Time.get_ticks_usec()
		var car := _car(type, Vector2(x, 0.0))
		worst = maxf(worst, float(Time.get_ticks_usec() - t0) / 1000.0)
		x += 11.0
		var far := 0
		var tris := 0
		for m: MeshInstance3D in car._body_meshes:
			if String(m.name).ends_with("_far"):
				far += 1
		var good := car._has_model and car._wheel_rigs.size() == 4 and car.wheels.size() == 4 \
				and car.get_node_or_null("NightLights") != null and not car._glass_slots.is_empty() and far > 0 \
				and car.cabin_glass() != null
		if not good:
			ok = false
			why += " %s(model %s rigs %d glass %d far %d)" % [Vehicle.BODY_NAMES[type], car._has_model,
					car._wheel_rigs.size(), car._glass_slots.size(), far]
	await _ticks(150)
	_check(ok, "the five build as models with their glass, a far twin, lamps and four wheels%s" % why)
	_check(worst < 80.0, "each builds inside the traffic's build budget (worst %.1f ms warm)" % worst)
	var stance := ""
	var good_stance := true
	for i in range(1, _cars.size(), 2):
		var car: Vehicle = _cars[i]
		var ys: Array[float] = []
		for w: VehicleWheel3D in car.wheels:
			if w.is_in_contact():
				ys.append((car.global_transform.affine_inverse() * w.get_contact_point()).y)
		var road := -car.road_lift()
		var at := 9.0
		if ys.size() == 4:
			at = (ys[0] + ys[1] + ys[2] + ys[3]) * 0.25
		if absf(at - road) > 0.04 or car.global_basis.y.dot(Vector3.UP) < 0.99:
			good_stance = false
		stance += " %s %.3f/%.3f" % [Vehicle.BODY_NAMES[car.body_type], at, road]
	_check(good_stance, "parked, each stands on four wheels within 4 cm of where traffic stands it (%s)" % stance)


func _traffic() -> void:
	var ok := true
	var hit_ok := true
	var why := ""
	var x := -55.0
	var cars: Array = []
	for type: int in Cars3.TYPES:
		cars.append(_car(type, Vector2(x, 40.0), true))
		x += 11.0
	await _ticks(3)
	for car: Vehicle in cars:
		ok = ok and car.is_traffic() and car.freeze and car.wheels.is_empty() and (car.cabin_seats() & 1) == 1
	_check(ok, "in traffic each new body is kinematic with no physics wheels and a driver at the wheel")
	for car: Vehicle in cars:
		var ride := float(car._dims().ride)
		var at: Vector3 = car.global_transform * Vector3(1.3, ride + (car._model_top_y - ride) * 0.45, 0.3)
		car.take_hit(-1, 12.0, -car.global_basis.x, at, Vehicle.HIT_BULLET)
	await _ticks(12)
	for car: Vehicle in cars:
		if car.is_traffic() or car.freeze or car.wheels.size() != 4 or car._damage == null:
			hit_ok = false
			why += " %s" % Vehicle.BODY_NAMES[car.body_type]
	_check(hit_ok, "a round into each in traffic hands it to physics on four wheels and to CarDamage%s" % why)
