extends RefCounted
## Car glass and the people behind it (scripts/vehicles/car_cabin.gd) for tests/smoke_test.gd.
## Loaded at run time (not named there), so it compiles after the autoloads and can name Vehicle,
## CarCabin, CarDamage and PoliceCar freely. On a platform 300 m over the street, like the car
## damage checks. Checks: every glass-slot body wears the cabin glass - the body type's one shared
## material while nobody is inside, the car's own copy of it (same shader) while somebody is; a
## parked car is empty and a traffic car has somebody at the wheel (its glass's occupant uniforms
## say so), who stays when a hit knocks it out of the traffic and moves onto the damage glass, and
## who gets out when it catches fire; the player at the wheel is the player and the car he leaves
## goes back to the shared glass; a cruiser seats its crew until they are out; privacy glass is
## darker than a saloon's rear glass; and the traffic and parked cars in the city agree.

var _t: Node
var _tree: SceneTree
var _city: Node3D
var _deck: StaticBody3D
var _cars: Array = []
var _top: Vector3


func run(t: Node, city: Node3D) -> void:
	_t = t
	_tree = t.get_tree()
	_city = city
	var ws: Node = _tree.root.get_node("/root/WorldState")
	var player := _tree.get_first_node_in_group("player") as Player
	if player.is_driving():
		player.exit_vehicle()
	var police: Node = city.get_node_or_null("Police")
	var police_was: Variant = police.get("enabled") if police else null
	if police:
		police.set("enabled", false)
	var home: Vector3 = ws.to_world(player.global_position)
	_top = player.global_position + Vector3(0.0, 300.0, 0.0)
	_build_deck()
	player.global_position = _top + Vector3(0.0, 1.2, 34.0)
	player.velocity = Vector3.ZERO
	await _ticks(3)

	_city_cars()
	await _parked_and_shared()
	await _traffic_driver()
	await _player_at_wheel(player)
	await _cruiser_crew()
	_tints()

	for c in _cars:
		if is_instance_valid(c):
			c.queue_free()
	_deck.queue_free()
	player.global_position = ws.to_local(home)
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
	box.size = Vector3(120.0, 1.0, 120.0)
	shape.shape = box
	_deck.add_child(shape)
	_city.add_child(_deck)
	_deck.global_position = _top - Vector3(0.0, 0.5, 0.0)


## A car of `type` at `x` metres along the deck; `traffic` true makes it a kinematic street car
## the way TrafficManager hands one out (the dictionary set before it enters the tree).
func _car(x: float, type: int = 0, traffic: bool = false) -> Vehicle:
	var car := Vehicle.new()
	car.setup(type as Vehicle.BodyType, Color(0.2, 0.3, 0.5), Vehicle.Addon.NONE)
	if traffic:
		car.traffic = {"axis": 0, "index": 0, "dir": 1, "lane": 0.0, "speed": 0.0}
		car.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		car.freeze = true
	car.position = _city.to_local(_top + Vector3(x, 0.9 if not traffic else car.road_lift() + 0.05, 0.0))
	_city.add_child(car)
	_cars.append(car)
	return car


## The glass slot's material on the car's first near body mesh, or null.
static func glass_of(car: Vehicle) -> Material:
	for m in car._body_meshes:
		if not is_instance_valid(m) or String(m.name).ends_with("_far") or m.mesh == null:
			continue
		for si in m.mesh.get_surface_count():
			var src := m.mesh.surface_get_material(si)
			if src != null and String(src.resource_name) == "glass":
				return m.get_surface_override_material(si)
	return null


## The seats the car's glass shows (occupant_top.a on whatever glass it wears), -1 with no glass.
static func seats_of(car: Vehicle) -> int:
	if car._glass_slots.is_empty():
		return -1
	return CarCabin.seats_of(car.cabin_glass())


func _top_of(car: Vehicle) -> Vector4:
	var m := car.cabin_glass() as ShaderMaterial
	var v: Variant = m.get_shader_parameter("occupant_top") if m else null
	return v if v is Vector4 else Vector4.ZERO


## The city as the smoke test left it: every street car with a glass slot has somebody in it,
## every parked one nobody, and the cars of a body type share one glass material.
func _city_cars() -> void:
	var traffic_in := 0
	var traffic_n := 0
	var parked_empty := 0
	var parked_n := 0
	var wrong_glass := 0
	var mats := {}
	var split := 0
	for n in _tree.get_nodes_in_group("vehicle"):
		var car := n as Vehicle
		if car == null or car is Aircraft or car._glass_meshes.is_empty() or car._damage != null or car.driver != null:
			continue
		var g := glass_of(car) as ShaderMaterial
		if g == null or g.shader != CarCabin.GLASS_SHADER or car._glass_shared == null:
			wrong_glass += 1
			continue
		if not mats.has(car.body_type):
			mats[car.body_type] = car._glass_shared
		elif mats[car.body_type] != car._glass_shared:
			split += 1
		# Nobody inside: the shared glass itself; somebody: the car's own copy.
		if (seats_of(car) == 0) != (g == car._glass_shared):
			split += 1
		if car is PoliceCar:
			continue
		if car.is_traffic():
			traffic_n += 1
			if (seats_of(car) & 1) != 0:
				traffic_in += 1
		elif not car._npc_driver:
			parked_n += 1
			if seats_of(car) == 0:
				parked_empty += 1
	_check(wrong_glass == 0 and split == 0 and mats.size() > 0,
			"every glass-slot car in the city wears the cabin glass: its body's shared one when empty, a copy when not (%d body types, %d wrong, %d split)" % [mats.size(), wrong_glass, split])
	_check(traffic_in == traffic_n and parked_empty == parked_n and parked_n > 0,
			"street cars have a driver (%d/%d), parked cars are empty (%d/%d)" % [traffic_in, traffic_n, parked_empty, parked_n])


func _parked_and_shared() -> void:
	var a := _car(-24.0, Vehicle.BodyType.SEDAN)
	var b := _car(-17.0, Vehicle.BodyType.SEDAN)
	var c := _car(-10.0, Vehicle.BodyType.CROSSOVER)
	await _ticks(10)
	var ga := glass_of(a) as ShaderMaterial
	_check(ga != null and ga.shader == CarCabin.GLASS_SHADER and glass_of(b) == ga and ga == a._glass_shared and glass_of(c) != ga and glass_of(c) != null,
			"the glass slot of a parked car wears its body type's one shared cabin glass")
	_check(seats_of(a) == 0 and a.cabin_seats() == 0, "a parked car is empty (seats %d)" % seats_of(a))
	var twin_ok := false
	for tw in a._body_shadows:
		if is_instance_valid(tw):
			for si in tw.mesh.get_surface_count():
				if tw.get_surface_override_material(si) == ga:
					twin_ok = true
	_check(twin_ok or a._body_shadows.is_empty(), "the shadow twin carries the same glass")


func _traffic_driver() -> void:
	var car := _car(0.0, Vehicle.BodyType.SEDAN, true)
	await _ticks(5)
	var g := glass_of(car) as ShaderMaterial
	_check((seats_of(car) & 1) != 0 and (car.cabin_seats() & 1) != 0 and _top_of(car).w >= 1.0
			and g != null and g != car._glass_shared and g.shader == CarCabin.GLASS_SHADER
			and CarCabin.seats_of(car._glass_shared) == 0,
			"a traffic car has a driver in its cabin, on its own copy of the glass (seats %d; the shared glass stays empty)" % seats_of(car))
	car.drop_out_of_traffic()
	await _ticks(5)
	_check((seats_of(car) & 1) != 0, "the driver stays at the wheel when a hit knocks the car out of traffic")
	# A round through the side glass: the damage glass takes over, the seat carries over.
	var ride := float(car._dims().ride)
	var at: Vector3 = car.global_transform * Vector3(1.2, ride + (car._model_top_y - ride) * 0.8, -0.3)
	car.take_hit(-1, 10.0, -car.global_basis.x, at, Vehicle.HIT_BULLET)
	await _tree.process_frame
	var dmg := car._damage
	var g2 := glass_of(car) as ShaderMaterial
	_check(dmg != null and g2 != null and g2 != g and g2.shader == CarDamage.GLASS_DAMAGE_SHADER and (seats_of(car) & 1) != 0,
			"the driver moves onto the damage glass with the first hit")
	var tints_ok := false
	var nn: Variant = g2.get_shader_parameter("pane_n") if g2 else null
	if nn is PackedVector4Array and not (nn as PackedVector4Array).is_empty():
		tints_ok = true
		for i in (nn as PackedVector4Array).size():
			if not is_equal_approx((nn as PackedVector4Array)[i].w, float(dmg._panes[i][4])):
				tints_ok = false
	_check(tints_ok, "the damage glass lets the cabin through the panes still in, at the intact glass's tints")
	var cap := CarDamage.max_burning
	CarDamage.max_burning = 99
	if dmg != null:
		dmg._ignite(false)
		dmg._fuse = 1e6
	CarDamage.max_burning = cap
	await _tree.process_frame
	_check(dmg != null and dmg.state == CarDamage.State.BURNING and seats_of(car) == 0 and car.cabin_seats() == 0,
			"nobody stays in a burning car")


func _player_at_wheel(player: Player) -> void:
	var car := _car(12.0, Vehicle.BodyType.PICKUP)
	await _ticks(20)
	player.global_position = car.global_position + car.global_basis.x * 2.5
	player.enter_vehicle(car)
	await _ticks(2)
	var top := _top_of(car)
	var want := CarCabin.PLAYER_TOP.srgb_to_linear()
	_check(seats_of(car) == 1 and absf(top.x - want.r) < 1e-4 and absf(top.z - want.b) < 1e-4,
			"the player at the wheel is the one in the cabin (seats %d)" % seats_of(car))
	player.exit_vehicle()
	await _ticks(2)
	_check(seats_of(car) == 0 and glass_of(car) == car._glass_shared,
			"the car the player leaves is empty, back on the shared glass")
	player.global_position = _top + Vector3(0.0, 1.2, 34.0)
	player.velocity = Vector3.ZERO


func _cruiser_crew() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var cop := PoliceCar.make(false, rng)
	cop.set("police", null)
	cop.position = _city.to_local(_top + Vector3(24.0, cop.road_lift() + 0.05, 10.0))
	_city.add_child(cop)
	_cars.append(cop)
	await _ticks(5)
	_check(seats_of(cop) == 3, "a cruiser seats its two officers (seats %d)" % seats_of(cop))
	cop.crew_aboard = 1
	var one := seats_of(cop)
	cop.crew_aboard = 0
	_check(one == 1 and seats_of(cop) == 0, "the crew leaves the cabin as it gets out (%d, then %d)" % [one, seats_of(cop)])


## The tints: the windscreen clearest, privacy glass behind a crossover's front seats darker than
## a saloon's rear side glass, no cabin through a lamp.
func _tints() -> void:
	var sedan: Dictionary = CarCabin._cache.get(Vehicle.BodyType.SEDAN, {})
	var cross: Dictionary = CarCabin._cache.get(Vehicle.BodyType.CROSSOVER, {})
	var ok := not sedan.is_empty() and not cross.is_empty()
	var screen_t := 0.0
	var lamp_t := 0.0
	if ok:
		ok = (cross.side_t as Vector2).y < (sedan.side_t as Vector2).y and (sedan.side_t as Vector2).y <= (sedan.side_t as Vector2).x
		for p: Array in sedan.panes:
			if int(p[3]) == CarCabin.KIND_SCREEN:
				screen_t = p[4]
			elif int(p[3]) == CarCabin.KIND_LAMP:
				lamp_t = maxf(lamp_t, p[4])
	_check(ok and screen_t > (sedan.side_t as Vector2).x and lamp_t == 0.0,
			"the windscreen is clearest (%.2f), privacy glass darker than a saloon's rear (%s vs %s), lamps opaque" % [
				screen_t, str(cross.get("side_t", "?")), str(sedan.get("side_t", "?"))])
