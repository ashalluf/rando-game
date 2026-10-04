extends RefCounted
## Car lamps and headlights (Vehicle._tick_lights, PropFactory.vehicle_lights(), CarLights) for
## tests/smoke_test.gd. Loaded at run time (not named there), so it compiles after the autoloads
## and can name Vehicle, CarLights and PropFactory freely. On a platform 300 m over the street,
## like the car damage and cabin checks. Checks: a parked car's lamps are off and a traffic car's
## on, on the car_lights shader, cars doing the same thing sharing one material; the brake light
## comes on when a traffic car slows or stands and goes off when it drives on; the indicator is
## on the side the car will turn to (checked against the car's own right, not the formula); a U-turn
## is a left; a car knocked out of the traffic runs its hazards; the player's brake and reverse;
## broken headlamps take the headlight away; and CarLights gives the player's car a shadowed light,
## the nearest traffic cars a light each up to its budget and none past its reach, none by day.

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

	await _states()
	await _signals()
	await _player_lamps(player)
	await _headlights(player)

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


func _frames(n: int) -> void:
	for i in n:
		await _tree.process_frame


func _build_deck() -> void:
	_deck = StaticBody3D.new()
	_deck.collision_layer = 1
	_deck.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200.0, 1.0, 200.0)
	shape.shape = box
	_deck.add_child(shape)
	_city.add_child(_deck)
	_deck.global_position = _top - Vector3(0.0, 0.5, 0.0)


## A car `at` (x, z) on the deck; with `traffic` a kinematic street car heading along `forward`
## the way TrafficManager hands one out (the dictionary set before it enters the tree).
func _car(at: Vector2, traffic: bool = false, forward: Vector3 = Vector3.FORWARD, axis: int = 0, dir: int = 1) -> Vehicle:
	var car := Vehicle.new()
	car.setup(Vehicle.BodyType.SEDAN, Color(0.2, 0.3, 0.5), Vehicle.Addon.NONE)
	if traffic:
		car.traffic = {"axis": axis, "index": 0, "dir": dir, "lane": 0.0, "speed": 10.0}
		car.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		car.freeze = true
		car.traffic_speed = 10.0
	car.position = _city.to_local(_top + Vector3(at.x, 0.9 if not traffic else car.road_lift() + 0.05, at.y))
	car.rotation.y = atan2(-forward.x, -forward.z)
	_city.add_child(car)
	_cars.append(car)
	return car


static func lamps(car: Vehicle) -> MeshInstance3D:
	return car.get_node_or_null("NightLights") as MeshInstance3D


func _states() -> void:
	var parked := _car(Vector2(-30.0, 0.0))
	var a := _car(Vector2(-20.0, 0.0), true)
	var b := _car(Vector2(-10.0, 0.0), true)
	await _ticks(4)
	var la := lamps(a)
	var mat := la.material_override as ShaderMaterial if la else null
	_check(lamps(parked) != null and not lamps(parked).visible, "a parked car's lamps are off")
	_check(la != null and la.visible and mat != null and mat.shader.resource_path == "res://shaders/car_lights.gdshader",
			"a traffic car's lamps are on, on the car lamps shader")
	# Both cruising at the same speed with no turn: the same state, so one shared material, up to
	# the blink phase (which only matters while signalling, and is folded away when not).
	_check(not a.light_brake and a.light_signal == 0 and la.material_override == lamps(b).material_override,
			"cars doing the same thing share one lamp material")
	a.traffic_speed = 6.0 # 4 m/s gone in a tick: hard braking
	await _ticks(1)
	var braked := a.light_brake
	var bmat := la.material_override as ShaderMaterial
	_check(braked and bmat != mat and float(bmat.get_shader_parameter("brake")) > 0.5,
			"the brake light comes on when a traffic car slows (brake %s)" % braked)
	a.traffic_speed = 0.0
	await _ticks(30)
	_check(a.light_brake, "and stays on while it stands at the line")
	a.traffic_speed = 2.0
	await _ticks(2)
	a.traffic_speed = 3.0
	await _ticks(40)
	_check(not a.light_brake, "and goes off once it pulls away")
	# Out past PhysicsBudget's script radius the car's own step is off; the traffic, which places
	# it every tick, ticks its lamps instead (they used to freeze in whatever state they had).
	var traffic: Node = _city.get_node_or_null("Traffic")
	if traffic:
		# Synchronous, no frames between: PhysicsBudget switches a near car's script back on.
		a.set_script_active(false)
		var off := not a.is_physics_processing()
		a.traffic_speed = 8.0
		for i in 40:
			traffic.call("_place", a, a.global_position, a.rotation.y, 0.0)
		var cruising := a.light_brake
		a.traffic_speed = 0.0
		traffic.call("_place", a, a.global_position, a.rotation.y, 0.0)
		_check(off and not cruising and a.light_brake,
				"a traffic car past the script radius still lights its brakes (the traffic ticks its lamps)")
		a.set_script_active(true)

	b.drop_out_of_traffic()
	await _ticks(4)
	_check(b.light_signal == 2 and lamps(b).visible, "a car knocked out of the traffic runs its hazards (signal %d)" % b.light_signal)
	# Both headlamps shot out: no headlight for CarLights; tails and lamps still drawn.
	a._set_lamps_broken(3)
	_check(not a.has_headlights() and lamps(a).visible, "with both headlamps broken the car has no headlight, its tail lamps still glow")
	a._set_lamps_broken(15)
	_check(not lamps(a).visible, "with every lamp broken nothing is drawn")


## Each turn on both road axes and both directions: the indicator must be on the side of the car
## (its own +X is its right) the turn goes to.
func _signals() -> void:
	var wrong := 0
	var tried := 0
	var x := 0.0
	for axis in [0, 1]:
		for dir in [-1, 1]:
			var fwd := Vector3(0.0, 0.0, dir) if axis == 0 else Vector3(dir, 0.0, 0.0)
			var car := _car(Vector2(x, 20.0), true, fwd, axis, dir)
			x += 8.0
			await _ticks(1)
			for turn in [-1, 1]:
				car.traffic.turn = turn
				car.traffic.to_c = 20.0
				await _ticks(1)
				var after := Vector3(float(turn), 0.0, 0.0) if axis == 0 else Vector3(0.0, 0.0, float(turn))
				var want := 1 if after.dot(car.global_basis.x) > 0.0 else -1
				tried += 1
				if car.light_signal != want:
					wrong += 1
			car.traffic.turn = 2
			await _ticks(1)
			if car.light_signal != -1:
				wrong += 1
			car.traffic.turn = 1
			car.traffic.to_c = 200.0
			await _ticks(1)
			if car.light_signal != 0:
				wrong += 1
	_check(tried == 8 and wrong == 0, "indicators blink on the side of the turn, a U-turn left, nothing far from the junction (%d wrong)" % wrong)


func _player_lamps(player: Player) -> void:
	var car := _car(Vector2(0.0, -10.0))
	await _ticks(3)
	car.driver = player
	await _ticks(1)
	_check(lamps(car).visible, "the player's car has its lamps on")
	car.brake = car.brake_force
	car.engine_force = 0.0
	car._tick_lights(1.0 / 60.0)
	_check(car.light_brake and not car.light_reverse, "the player's brake lights the brake lamps")
	car.brake = 0.0
	car.engine_force = car.reverse_power
	car._tick_lights(1.0)
	_check(car.light_reverse and not car.light_brake, "reversing lights the reversing lamps")
	car.engine_force = 0.0
	car.driver = null
	await _ticks(2)
	_check(not lamps(car).visible, "and the car he leaves goes dark")


func _headlights(player: Player) -> void:
	# Only this test's cars near the camera.
	for c in _cars:
		if is_instance_valid(c):
			c.queue_free()
	_cars.clear()
	await _ticks(2)
	var was_force := CarLights.force
	var was_budget := CarLights.budget
	var was_lamp := CarLights.lamp_override
	CarLights.force = true
	CarLights.lamp_override = 1.0
	CarLights.budget = 3
	CarLights.player_light = true
	CarLights.player_shadow = true
	var cam := _tree.root.get_camera_3d()
	CarLights.ensure(player)
	await _frames(2)
	var mgr := CarLights.instance()
	_check(mgr != null, "CarLights is made")
	if mgr == null or cam == null:
		CarLights.force = was_force
		return
	var eye := cam.global_position
	# Five traffic cars near the camera, one far past the reach.
	var near: Array = []
	for i in 5:
		var at := eye + Vector3(-12.0 + i * 6.0, 0.0, -14.0)
		near.append(_car(Vector2(at.x - _top.x, at.z - _top.z), true))
	var far_pos := eye + Vector3(0.0, 0.0, -mgr.reach - 30.0)
	var far := _car(Vector2(far_pos.x - _top.x, far_pos.z - _top.z), true)
	var mine := _car(Vector2(eye.x - _top.x + 4.0, eye.z - _top.z + 4.0))
	await _ticks(2)
	mine.driver = player
	player.vehicle = mine
	await _frames(40)
	var lit := 0
	var far_lit := false
	for slot: Array in mgr._slots:
		if slot[1] != null and (slot[0] as SpotLight3D).visible:
			lit += 1
			if slot[1] == far:
				far_lit = true
	_check(lit == 3 and not far_lit, "the nearest traffic cars get a headlight up to the budget (%d of 3), none past the reach" % lit)
	var ps: SpotLight3D = mgr._player_spot
	_check(ps.visible and ps.shadow_enabled and ps.light_energy > 0.0 and ps.light_projector != null,
			"the player's car gets a shadowed headlight with the low-beam cookie")
	var ahead := -ps.global_basis.z
	var car_fwd := -mine.global_basis.z
	_check(ahead.dot(car_fwd) > 0.95 and ahead.y < 0.0, "the headlight points down the road ahead of the car, dipped")
	_check(CarLights.active_count == 4, "CarLights counts the lights it draws (%d)" % CarLights.active_count)
	# By day nothing.
	CarLights.lamp_override = 0.0
	await _frames(4)
	_check(CarLights.active_count == 0 and not ps.visible, "by day no car light is on (%d)" % CarLights.active_count)
	mine.driver = null
	player.vehicle = null
	CarLights.lamp_override = was_lamp
	CarLights.budget = was_budget
	CarLights.force = was_force
