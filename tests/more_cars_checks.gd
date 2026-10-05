extends RefCounted
## The second wave of everyday car bodies (tools/make_more_cars.py: the hatchback, the full-size
## SUV, the minivan, the taxi, the beater) for tests/smoke_test.gd. Loaded at run time (not named
## there), so it compiles after the autoloads and can name Vehicle, CarCabin and TrafficManager.
## On a deck high over the street, like the car cabin checks. Checks: the roll table agrees with
## BODY_ODDS and only hands old rolls to new types in the slices it gives them (a seed's sedans
## stay sedans unless they were in the hatchbacks' slice); random_car() spends the caller's rng
## exactly as before; the new bodies turn up on a real street in about their shares; each builds
## as a model with its glass, a far twin, lamps and four wheels inside the traffic's build budget;
## kinematic traffic stands on its wheels; a hit hands it to physics and CarDamage; the pool hands
## one back; the taxi wears its lit sign, its company's lettering and carries a fare; the beater's
## paint carries its wear and the odd door's colour is not the car's own.

var _t: Node
var _tree: SceneTree
var _city: Node3D
var _traffic: TrafficManager
var _ws: Node
var _deck: StaticBody3D
var _top: Vector3
var _cars: Array = []

const NEW_TYPES := [Vehicle.BodyType.HATCHBACK, Vehicle.BodyType.SUV, Vehicle.BodyType.MINIVAN,
		Vehicle.BodyType.TAXI, Vehicle.BodyType.BEATER]
## The roll ranges every older type had before the second wave ([start, end), dict order).
const OLD_RANGES := {
	Vehicle.BodyType.SEDAN: [0, 250], Vehicle.BodyType.PICKUP: [250, 400],
	Vehicle.BodyType.VAN: [400, 515], Vehicle.BodyType.SPORTS: [515, 660],
	Vehicle.BodyType.SUPER: [660, 705], Vehicle.BodyType.SPIDER: [705, 730],
	Vehicle.BodyType.HYPER: [730, 760], Vehicle.BodyType.TRACK: [760, 780],
	Vehicle.BodyType.CROSSOVER: [780, 1000],
}


func run(t: Node, city: Node3D) -> void:
	_t = t
	_tree = t.get_tree()
	_city = city
	_traffic = city.get_node("Traffic") as TrafficManager
	_ws = _tree.root.get_node("/root/WorldState")
	_rolls()
	_rng_stream()
	var player := _tree.get_first_node_in_group("player") as Player
	if player.is_driving():
		player.exit_vehicle()
	var police: Node = city.get_node_or_null("Police")
	var police_was: Variant = police.get("enabled") if police else null
	if police:
		police.set("enabled", false)
	var home: Vector3 = _ws.to_world(player.global_position)
	_top = player.global_position + Vector3(0.0, 340.0, 0.0)
	_build_deck()
	player.global_position = _top + Vector3(0.0, 1.2, 60.0)
	player.velocity = Vector3.ZERO
	await _ticks(3)

	await _builds()
	await _traffic_stance()
	await _hit()
	_pool()
	await _taxi()
	await _beater()

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
	box.size = Vector3(200.0, 1.0, 120.0)
	shape.shape = box
	_deck.add_child(shape)
	_city.add_child(_deck)
	_deck.global_position = _top - Vector3(0.0, 0.5, 0.0)


func _car(type: int, at: Vector2, traffic: bool = false, color: Color = Color(0.2, 0.3, 0.5)) -> Vehicle:
	var car := Vehicle.new()
	car.setup(type as Vehicle.BodyType, color, Vehicle.Addon.NONE)
	if type == Vehicle.BodyType.TAXI:
		car.setup_look(Vehicle.Finish.GLOSS, Vehicle.Livery.TAXI, Vehicle.TAXI_TRIM)
	car.look_seed = 4242
	if traffic:
		car.traffic = {"axis": 0, "index": 0, "dir": -1, "lane": 0.0, "speed": 0.0}
		car.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		car.freeze = true
	car.position = _city.to_local(_top + Vector3(at.x, car.road_lift() if traffic else 0.9, at.y))
	_city.add_child(car)
	_cars.append(car)
	return car


## The roll table: its slices sum to BODY_ODDS, every older type keeps the start of its old
## range, and a roll moves to another type only into a new one.
func _rolls() -> void:
	var counts := {}
	var last := 0
	var ordered := true
	for row: Array in Vehicle.ROLL_MAP:
		var end: int = row[0]
		ordered = ordered and end > last
		counts[row[1]] = int(counts.get(row[1], 0)) + end - last
		last = end
	var match_odds := ordered and last == 1000
	for type: int in Vehicle.BODY_ODDS:
		match_odds = match_odds and int(counts.get(type, 0)) == int(Vehicle.BODY_ODDS[type])
	_check(match_odds, "Vehicle.ROLL_MAP covers 0-999 in order and gives every type its BODY_ODDS share")
	var moved_to_old := 0
	var kept := 0
	var moved := 0
	for roll in 1000:
		var old_type := -1
		for type: int in OLD_RANGES:
			if roll >= int(OLD_RANGES[type][0]) and roll < int(OLD_RANGES[type][1]):
				old_type = type
		var now := Vehicle._body_for_roll(roll)
		if now == old_type:
			kept += 1
		elif NEW_TYPES.has(now):
			moved += 1
		else:
			moved_to_old += 1
	_check(moved_to_old == 0 and moved == 240 and kept == 760,
			"a roll keeps its old body type unless a new body took its slice (kept %d, to new types %d, to another old type %d)" % [kept, moved, moved_to_old])


## random_car() draws exactly what it always drew from the caller's rng (one body roll, the
## add-on's one or two, one paint): what a seed builds after it does not move.
func _rng_stream() -> void:
	var same := true
	var taxis := 0
	var beaters := 0
	var made := {}
	for s in 400:
		var a := RandomNumberGenerator.new()
		a.seed = 9000 + s
		var b := RandomNumberGenerator.new()
		b.seed = 9000 + s
		var car := Vehicle.random_car(a)
		b.randi_range(0, 999)
		if b.randf() < 0.35:
			b.randi_range(1, Vehicle.Addon.size() - 1)
		b.randi()
		same = same and a.state == b.state
		made[car.body_type] = int(made.get(car.body_type, 0)) + 1
		if car.body_type == Vehicle.BodyType.TAXI:
			taxis += 1
			same = same and car.livery == Vehicle.Livery.TAXI
		if car.body_type == Vehicle.BodyType.BEATER:
			beaters += 1
			same = same and Vehicle.BEATER_PAINTS.has(car.paint) and car.livery == Vehicle.Livery.NONE
		car.free()
	var all_new := true
	for type: int in NEW_TYPES:
		all_new = all_new and int(made.get(type, 0)) > 0
	_check(same and all_new, "random_car() spends the caller's rng exactly as before and rolls every new body (taxis %d, beaters %d of 400; %s)" % [taxis, beaters, made])


func _builds() -> void:
	var worst := 0.0
	var ok := true
	var why := ""
	var x := -80.0
	for type: int in NEW_TYPES:
		_car(type, Vector2(x, -40.0))
		var t0 := Time.get_ticks_usec()
		var car := _car(type, Vector2(x, 0.0))
		worst = maxf(worst, float(Time.get_ticks_usec() - t0) / 1000.0)
		x += 9.0
		var far := 0
		for m: MeshInstance3D in car._body_meshes:
			if String(m.name).ends_with("_far"):
				far += 1
		var good := car._has_model and car._wheel_rigs.size() == 4 and car.wheels.size() == 4 \
				and car.get_node_or_null("NightLights") != null and not car._glass_slots.is_empty() and far > 0 \
				and car.cabin_glass() != null
		if not good:
			ok = false
			why += " %s(model %s rigs %d glass %d far %d)" % [Vehicle.BODY_NAMES[type], car._has_model, car._wheel_rigs.size(), car._glass_slots.size(), far]
	await _ticks(30)
	_check(ok, "the hatchback, SUV, minivan, taxi and beater build as models with their glass, a far twin, lamps and four wheels%s" % why)
	_check(worst < 80.0, "each builds inside the traffic's build budget (worst %.1f ms warm)" % worst)
	# Parked: on their springs, upright, at rest, close to where traffic stands them.
	var stance := ""
	var good_stance := true
	for i in range(1, _cars.size(), 2):
		var car: Vehicle = _cars[i]
		var lift := car.global_position.y - (_top.y)
		var want := car.road_lift()
		if absf(lift - want) > 0.06 or car.global_basis.y.dot(Vector3.UP) < 0.99:
			good_stance = false
		stance += " %s %.3f/%.3f" % [Vehicle.BODY_NAMES[car.body_type], lift, want]
	_check(good_stance, "parked, each sits on its springs within 6 cm of where traffic stands it (body over road vs road_lift:%s)" % stance)


func _traffic_stance() -> void:
	var car := _car(Vehicle.BodyType.SUV, Vector2(40.0, 30.0), true)
	await _ticks(3)
	_check(car.is_traffic() and car.freeze and car.wheels.is_empty() and (car.cabin_seats() & 1) == 1,
			"a traffic SUV is kinematic with no physics wheels and a driver at the wheel")


func _hit() -> void:
	var ok := true
	var why := ""
	var x := -70.0
	for type: int in NEW_TYPES:
		var car := _car(type, Vector2(x, 40.0), true)
		x += 10.0
		await _ticks(2)
		var ride := float(car._dims().ride)
		var at: Vector3 = car.global_transform * Vector3(1.3, ride + (car._model_top_y - ride) * 0.45, 0.4)
		car.take_hit(-1, 12.0, -car.global_basis.x, at, Vehicle.HIT_BULLET)
		await _ticks(12)
		if car.is_traffic() or car.freeze or car.wheels.size() != 4 or car._damage == null:
			ok = false
			why += " %s" % Vehicle.BODY_NAMES[type]
	_check(ok, "a round into each new body in traffic hands it to physics on four wheels and to CarDamage%s" % why)


func _pool() -> void:
	var car := Vehicle.new()
	car.setup(Vehicle.BodyType.MINIVAN, Color(0.4, 0.4, 0.4), Vehicle.Addon.NONE)
	car.traffic = {"axis": 0, "index": 0, "dir": 1, "lane": 0.0, "speed": 0.0}
	car.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	car.freeze = true
	_traffic.add_child(car)
	_traffic._retire(car)
	var back := _traffic._new_car()
	_check(back == car, "the pool hands a retired minivan back as an ordinary street car")
	if is_instance_valid(back):
		_traffic._retire(back)


func _taxi() -> void:
	var car := _car(Vehicle.BodyType.TAXI, Vector2(30.0, -30.0), true, Vehicle.TAXI_PAINT)
	# A traffic seed that rolls a fare (most do).
	var seed := 0
	for s in 50:
		if absi(hash([s, 61])) % 1000 < int(Vehicle.TAXI_FARE_SHARE * 1000.0):
			seed = s
			break
	car._occupant_seed = seed
	car._update_occupant(true)
	await _ticks(3)
	var sign_ok := false
	for m: MeshInstance3D in car._body_meshes:
		for si in m.mesh.get_surface_count():
			var src := m.mesh.surface_get_material(si)
			if src != null and String(src.resource_name) == "taxi_sign":
				var mat := m.get_surface_override_material(si) as ShaderMaterial
				sign_ok = mat != null and mat.shader == Vehicle.TAXI_SIGN_SHADER
	var letters := car.find_children("Lettering", "MeshInstance3D", false, false).size()
	_check(sign_ok, "the taxi wears its lit roof sign (taxi_sign slot on shaders/taxi_sign.gdshader)")
	_check(letters == 4 or OS.has_feature("web"), "the taxi carries BASIN CAB and its fleet number on both sides (%d)" % letters)
	_check(car.cabin_seats() == 5 and CarCabin.seats_of(car.cabin_glass()) == 5 and car.get_node_or_null("LiveryProp") == null,
			"a traffic taxi has its cabbie up front and a fare on the back seat (seats %d), and no box sign" % car.cabin_seats())


func _beater() -> void:
	var car := _car(Vehicle.BodyType.BEATER, Vector2(50.0, -30.0), false, Vehicle.BEATER_PAINTS[0])
	await _ticks(2)
	var paint: ShaderMaterial = null
	for m: MeshInstance3D in car._body_meshes:
		for si in m.mesh.get_surface_count():
			var src := m.mesh.surface_get_material(si)
			if src != null and String(src.resource_name).begins_with("paint"):
				paint = m.get_surface_override_material(si) as ShaderMaterial
	var door: Variant = paint.get_shader_parameter("wear_door_color") if paint else null
	_check(paint != null and float(paint.get_shader_parameter("wear")) == 1.0 and door is Color
			and not (door as Color).is_equal_approx(car.paint) and paint.get_shader_parameter("wear_door") == Vehicle.BEATER_DOOR,
			"the beater's paint carries its wear: another car's door, the primer patch, the faded coat")
	var plain := _car(Vehicle.BodyType.SEDAN, Vector2(60.0, -30.0))
	await _ticks(2)
	var pm: ShaderMaterial = null
	for m: MeshInstance3D in plain._body_meshes:
		for si in m.mesh.get_surface_count():
			var src := m.mesh.surface_get_material(si)
			if src != null and String(src.resource_name).begins_with("paint"):
				pm = m.get_surface_override_material(si) as ShaderMaterial
	_check(pm != null and float(pm.get_shader_parameter("wear")) == 0.0, "and no other car's paint wears anything")
