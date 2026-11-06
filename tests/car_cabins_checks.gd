extends RefCounted
## Real car interiors and hinged doors (CarInteriors, CarInterior, CarInteriorKit, CarDoorSplit) for
## tests/smoke_test.gd. Loaded at run time, so it can name Vehicle and the cabin classes. On a deck
## 300 m over the city like the car cabin checks; it stages everything it needs (its own cars, the
## player put where it wants him) and waits on conditions, never on where an earlier check left him.
## Headless there is no mesh data, so the doors are the stand-in ones (cards, no skin): the split
## itself is checked on the real meshes by tools/car_cabins/split_probe.tscn.
## Checks: the door outlines are sane for every body; the wheel sits where the traced driver holds
## it; a parked car next to the player gets its cabin (see-through glass) and loses it once he walks
## off (back on its shared glass); traffic and wrecks never get one; getting in swings the door on
## his side open and shut and powers the dash; the wheel turns with the steering; getting out swings
## the door on the side he is put down; a hard crash tears the door off its side as debris and the
## car keeps the hole; CAR_CABINS off builds nothing.

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
	_put(player, _top + Vector3(0.0, 1.2, 40.0))
	await _ticks(3)

	_outlines()
	_wheel_matches_trace()
	await _parked_nearby(player)
	await _traffic_and_wrecks(player)
	await _get_in_and_out(player)
	await _crash_tears_door(player)
	await _switched_off(player)

	for c in _cars:
		if is_instance_valid(c):
			c.queue_free()
	for n in _tree.get_nodes_in_group("debris"):
		if n is RigidBody3D and String(n.name).begins_with("LostDoor"):
			n.queue_free()
	_deck.queue_free()
	_put(player, ws.to_local(home))
	if police:
		police.set("enabled", police_was)
	await _ticks(3)


func _check(ok: bool, label: String) -> void:
	_t._check(ok, label)


func _ticks(n: int) -> void:
	for i in n:
		await _tree.physics_frame


## Polls `cond` for up to `n` physics ticks.
func _until(cond: Callable, n: int) -> bool:
	for i in n:
		if cond.call():
			return true
		await _tree.physics_frame
	return cond.call()


func _put(player: Player, at: Vector3) -> void:
	player.global_position = at
	player.velocity = Vector3.ZERO


func _build_deck() -> void:
	_deck = StaticBody3D.new()
	_deck.collision_layer = 1
	_deck.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(140.0, 1.0, 140.0)
	shape.shape = box
	_deck.add_child(shape)
	_city.add_child(_deck)
	_deck.global_position = _top - Vector3(0.0, 0.5, 0.0)


func _car(x: float, type: int = 0, traffic: bool = false) -> Vehicle:
	var car := Vehicle.new()
	car.setup(type as Vehicle.BodyType, Color(0.5, 0.1, 0.1), Vehicle.Addon.NONE)
	if traffic:
		car.traffic = {"axis": 0, "index": 0, "dir": 1, "lane": 0.0, "speed": 0.0}
		car.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		car.freeze = true
	car.position = _city.to_local(_top + Vector3(x, 0.9 if not traffic else car.road_lift() + 0.05, 0.0))
	_city.add_child(car)
	_cars.append(car)
	return car


func _outlines() -> void:
	var bad := []
	for type: int in CarDoorSplit.DOORS.keys():
		var o := CarDoorSplit.lower_outline(type)
		var area := 0.0
		for i in o.size():
			var a := o[i]
			var b := o[(i + 1) % o.size()]
			area += a.x * b.y - b.x * a.y
		area = absf(area) * 0.5
		var front := CarDoorSplit.front_at(type, CarDoorSplit.sill_of(type) + 0.2)
		var length := front - CarDoorSplit.rear_of(type)
		if area < 0.5 or length < 0.8 or length > 1.6 or not Vehicle.BODY_MODELS.has(type):
			bad.append("%s area %.2f length %.2f" % [Vehicle.BODY_NAMES[type], area, length])
	_check(bad.is_empty() and CarDoorSplit.DOORS.size() >= 10, "every everyday body has a front door outline 0.8-1.6 m long %s" % [bad])
	# The van's outline round its front arch is closed and runs from the A-pillar to the B-pillar.
	var van := CarDoorSplit.van_outline()
	_check(van.size() > 10 and absf(van[0].y - van[van.size() - 1].y) < 0.01, "the van's cab door outline closes along its frame top")


## The wheel the kit builds stands where car_cabin.gdshaderinc puts the one the traced driver holds.
func _wheel_matches_trace() -> void:
	var data := {"cabin_lo": Vector3(-0.7, 0.4, -1.4), "cabin_hi": Vector3(0.7, 1.3, 1.0), "belt_y": 0.95,
		"side_top": 1.3, "seat_z": Vector2(-0.1, 0.8), "driver_side": -1.0, "rear_seats": true, "panes": []}
	var L := CarInteriorKit.layout(data)
	var xf := CarInteriorKit.wheel_frame(L)
	# The trace's own numbers (cabin_view()).
	var cx := 0.0
	var half_w := 0.7
	var sx := cx - (half_w + 0.03) * 0.5
	var dash_rear := -1.4 + 0.42
	var zw := lerpf(-0.1 - 0.7, dash_rear + 0.22, 0.5)
	zw = dash_rear + maxf(zw - dash_rear, 0.12)
	var want := Vector3(sx, 0.95 - 0.05, zw)
	var src := FileAccess.get_file_as_string("res://shaders/car_cabin.gdshaderinc")
	_check(xf.origin.distance_to(want) < 1e-4 and xf.basis.z.dot(Vector3(0.0, 0.42, 0.91).normalized()) > 0.9999
			and src.contains("float wr = %.3f;" % CarInteriorKit.WHEEL_R),
			"the steering wheel sits where the traced driver's hands are (%s, want %s)" % [xf.origin, want])


func _parked_nearby(player: Player) -> void:
	var car := _car(0.0, Vehicle.BodyType.SEDAN)
	await _ticks(10)
	_put(player, car.global_position + car.global_basis.x * 3.0 + Vector3.UP * 0.5)
	var got := await _until(func() -> bool: return CarInteriors.rig_of(car) != null, 120)
	var rig := CarInteriors.rig_of(car)
	var g := car.cabin_glass() as ShaderMaterial
	_check(got and rig.cabin != null and rig.cabin.mesh != null and rig.cabin.mesh.get_surface_count() == 1
			and rig.doors.size() == 2 and rig.wheel != null,
			"a parked car next to the player gets its cabin, two doors and a wheel")
	_check(g != null and g.shader == CarInterior.GLASS_OPEN_SHADER, "its glass turns see-through (car_glass_open)")
	_check(rig != null and rig.get_parent() is MeshInstance3D and not String(rig.get_parent().name).ends_with("_far"),
			"the cabin hangs off the near body mesh")
	_put(player, car.global_position + Vector3(30.0, 0.5, 30.0))
	var gone := await _until(func() -> bool: return CarInteriors.rig_of(car) == null, 120)
	await _ticks(2)
	_check(gone and car.cabin_glass() == car._glass_shared and car.cabin_glass_override == null,
			"walking off takes it away again: back on the body type's shared glass")
	# The scheme is a hash of the car, so the same car is the same inside.
	_check(CarInterior.scheme_for(car) == CarInterior.scheme_for(car) and CarInterior.scheme_for(car) < CarInterior.SCHEMES.size(),
			"the interior scheme is a stable hash of the car")


func _traffic_and_wrecks(player: Player) -> void:
	var street := _car(14.0, Vehicle.BodyType.CROSSOVER, true)
	var wreck := _car(22.0, Vehicle.BodyType.HATCHBACK)
	await _ticks(10)
	wreck.damage_state().stage("wreck")
	await _ticks(5)
	_put(player, (street.global_position + wreck.global_position) * 0.5 + Vector3(0.0, 0.5, 2.5))
	await _ticks(30)
	_check(CarInteriors.rig_of(street) == null, "a traffic car keeps the traced cabin")
	_check(CarInteriors.rig_of(wreck) == null, "a burnt-out wreck gets no cabin")
	_put(player, _top + Vector3(0.0, 1.2, 40.0))
	street.queue_free()
	wreck.queue_free()
	await _ticks(3)


func _get_in_and_out(player: Player) -> void:
	var car := _car(-16.0, Vehicle.BodyType.PICKUP)
	await _ticks(10)
	# From the car's right (+x): that door swings.
	_put(player, car.global_position + car.global_basis.x * 2.4 + Vector3.UP * 0.4)
	await _ticks(2)
	player.enter_vehicle(car)
	# The cabin may still be building on a worker thread: the door swings once it is up.
	await _until(func() -> bool: return CarInteriors.rig_of(car) != null, 120)
	var rig := CarInteriors.rig_of(car)
	var opened := await _until(func() -> bool: return rig != null and is_instance_valid(rig) and rig.door_open(1.0) > 0.9, 90)
	var why := "rig %s valid %s, car valid %s, rig_of %s, driving %s, time scale %.3f" % [rig != null, rig != null and is_instance_valid(rig),
			is_instance_valid(car), CarInteriors.rig_of(car) != null if is_instance_valid(car) else false,
			player.vehicle == car, Engine.time_scale]
	_check(rig != null and is_instance_valid(rig) and opened and rig.door_open(-1.0) < 0.01, "getting in from the right swings the right door open (and only it) (%s)" % why)
	if rig == null or not is_instance_valid(rig):
		rig = CarInteriors.rig_of(car)
	if rig == null:
		_check(false, "and shuts it behind him (no rig)")
		player.exit_vehicle()
		car.queue_free()
		return
	var shut := await _until(func() -> bool: return is_instance_valid(rig) and rig.door_open(1.0) < 0.001 and not rig.busy(), 180)
	_check(shut, "and shuts it behind him")
	_check(float(rig._mat.get_shader_parameter("powered")) == 1.0 and CarCabin.seats_of(car.cabin_glass()) == 1,
			"the dash lights up and he is seated in the glass (seats %d)" % CarCabin.seats_of(car.cabin_glass()))
	# The wheel turns with the steering: 15 turns of it per turn of the road wheels.
	car.steering = 0.2
	rig.tick(0.0)
	var rest := rig._wheel_xf.basis
	var now := rig.wheel.transform.basis
	var turned := (rest.inverse() * now).get_euler().z
	_check(absf(absf(turned) - 0.2 * CarInterior.STEER_RATIO) < 0.02,
			"the steering wheel turns with the steering (%.2f rad)" % turned)
	car.steering = 0.0
	player.exit_vehicle()
	var out_side := 1.0 if car.to_local(player.global_position).x >= 0.0 else -1.0
	var swung := await _until(func() -> bool: return rig.door_open(out_side) > 0.5, 90)
	_check(swung, "getting out swings the door on the side he is put down")
	_put(player, _top + Vector3(0.0, 1.2, 40.0))
	await _until(func() -> bool: return CarInteriors.rig_of(car) == null, 120)
	# (Getting out on this deck can throw the car: the cabin checks see the same crash. A car that
	# lost a door in it keeps its cabin, rightly.)
	var thrown := car._damage != null and car._damage.hits_taken > 0
	var kept := CarInteriors.rig_of(car)
	_check((kept == null and car.cabin_glass() == car._glass_shared) or (thrown and kept != null and kept.has_lost_door()),
			"once he is gone the pickup is back to the traced cabin (or keeps it for a door its crash tore off: %s)" % thrown)
	car.queue_free()


func _crash_tears_door(player: Player) -> void:
	var car := _car(30.0, Vehicle.BodyType.SEDAN)
	await _ticks(10)
	_put(player, car.global_position - car.global_basis.x * 2.4 + Vector3.UP * 0.4)
	await _ticks(2)
	player.enter_vehicle(car)
	await _until(func() -> bool: return CarInteriors.rig_of(car) != null, 120)
	var rig := CarInteriors.rig_of(car)
	await _until(func() -> bool: return rig != null and not rig.busy(), 240)
	var before := _lost_doors()
	# A side impact on the left at 20 m/s over the crash threshold.
	var at := car.global_position - car.global_basis.x * 1.0 + Vector3.UP * 0.6
	car.take_hit(0, 20.0, car.global_basis.x, at, Vehicle.HIT_CRASH)
	await _ticks(3)
	var lost := []
	for n in _lost_doors():
		if not before.has(n):
			lost.append(n)
	_check(rig.door(-1.0).get("lost", false) and not rig.door(1.0).get("lost", true) and lost.size() == 1,
			"a hard crash on the left tears the left door off as debris (%d new, left lost %s, right lost %s)" % [lost.size(),
			rig.door(-1.0).get("lost", "?"), rig.door(1.0).get("lost", "?")])
	var flying := lost.back() as RigidBody3D if not lost.is_empty() else null
	_check(flying != null and flying.get_child_count() >= 2 and flying.is_in_group("debris") and flying.has_meta("debris_life"),
			"the torn-off door is a debris body carrying its card")
	# A light knock tears nothing.
	car.take_hit(0, 2.0, -car.global_basis.x, car.global_position + car.global_basis.x + Vector3.UP * 0.6, Vehicle.HIT_CRASH)
	await _ticks(2)
	_check(not rig.door(1.0).get("lost", true), "a light knock leaves the other door on")
	player.exit_vehicle()
	_put(player, _top + Vector3(0.0, 1.2, 40.0))
	await _ticks(30)
	_check(CarInteriors.rig_of(car) != null and rig.has_lost_door(), "a car missing a door keeps its cabin (the hole stays)")
	car.queue_free()
	await _ticks(2)


func _lost_doors() -> Array:
	var out := []
	for n in _tree.get_nodes_in_group("debris"):
		if n is RigidBody3D and String(n.name).begins_with("LostDoor"):
			out.append(n)
	return out


func _switched_off(player: Player) -> void:
	CarInteriors.enabled = false
	var car := _car(-30.0, Vehicle.BodyType.SUV)
	await _ticks(10)
	_put(player, car.global_position + car.global_basis.x * 2.4 + Vector3.UP * 0.4)
	await _ticks(2)
	player.enter_vehicle(car)
	await _ticks(20)
	_check(CarInteriors.rig_of(car) == null and car.cabin_glass() != null and (car.cabin_glass() as ShaderMaterial).shader == CarCabin.GLASS_SHADER,
			"CAR_CABINS off: the player's car keeps the traced cabin")
	player.exit_vehicle()
	CarInteriors.enabled = true
	_put(player, _top + Vector3(0.0, 1.2, 40.0))
	await _ticks(3)
