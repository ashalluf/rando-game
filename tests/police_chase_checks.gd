extends RefCounted
## The police chase (PoliceChase, docs/HANDOFF.md "The police chase") for tests/smoke_test.gd.
## Loaded at run time, so it can name PoliceChase and PoliceCar. On a deck 300 m over the street
## (the night-look checks' way), with its own cars; the Police node is switched on for these checks
## only and its dispatch held off (no cruiser of its own joins), and everything is put back after.
## Checks: the switches; the box and PIT slots' geometry; the searchlight's lead; a stopped
## player's car boxed in by live cruisers; the PIT role and its assist (a spin, the grip let go and
## given back); a car over a spike strip goes flat and a police car does not; a roadblock lays a
## strip on the player's side; officers behind their open doors, then bounding forward one at a
## time; the radio's transmissions.

var _t: Node
var _tree: SceneTree
var _city: Node3D
var _deck: StaticBody3D
var _cars: Array = []
var _top: Vector3
var _police: Police
var _chase: PoliceChase
var _player: Player


func run(t: Node, city: Node3D) -> void:
	_t = t
	_tree = t.get_tree()
	_city = city
	var ws: Node = _tree.root.get_node("/root/WorldState")
	_player = _tree.get_first_node_in_group("player") as Player
	if _player.is_driving():
		_player.exit_vehicle()
	_police = city.get_node_or_null("Police") as Police
	_check(_police != null, "the city has a Police node")
	if _police == null:
		return
	_check(PoliceChase.enabled == (OS.get_environment("POLICE_CHASE") != "0"), "POLICE_CHASE=0 is the A/B switch")
	_chase = PoliceChase.instance()
	_check(_chase != null and _chase.get_parent() == _police and _chase.radio != null, "the chase node sits under the Police node with its radio")
	if _chase == null:
		return
	var saved := {}
	for key in ["enabled", "lose_seconds", "roadblock_stars", "accuracy_base", "cruisers_per_star"]:
		saved[key] = _police.get(key)
	var chase_saved := {"advance_after": _chase.advance_after}
	var health: Node = _player.get("health")
	var home: Vector3 = ws.to_world(_player.global_position)
	_police.clear()
	_police.lose_seconds = 1.0e6
	_police.roadblock_stars = 99
	# Rounds that never land: the checks are about where they stand, not about the player going down.
	_police.accuracy_base = 0.0
	# No cruiser of the Police node's own: only the ones these checks put down (spawn_cruiser).
	_police.cruisers_per_star = PackedInt32Array([0, 0, 0, 0, 0, 0])
	_police.enabled = true
	_top = _player.global_position + Vector3(0.0, 300.0, 0.0)
	_build_deck()
	_player.global_position = _top + Vector3(0.0, 1.2, 60.0)
	_player.velocity = Vector3.ZERO
	await _ticks(3)

	_geometry()
	await _box()
	await _pit()
	await _spikes()
	await _roadblock(ws, home)
	await _doors()
	await _radio()

	_police.clear()
	if _player.is_driving():
		var v := _player.vehicle
		_player.exit_vehicle()
		v.queue_free()
	# The cruisers went back to the Police node's pool with clear(); the plain cars are ours.
	for c in _cars:
		if is_instance_valid(c) and not (c is PoliceCar) and not c.is_queued_for_deletion():
			c.queue_free()
	_cars.clear()
	for s in _chase.strips:
		if is_instance_valid(s):
			s.queue_free()
	_chase.strips.clear()
	_deck.queue_free()
	for key in saved:
		_police.set(key, saved[key])
	_chase.advance_after = chase_saved.advance_after
	_player.global_position = ws.to_local(home)
	_player.velocity = Vector3.ZERO
	if health:
		health.set("health", health.get("max_health"))
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
	box.size = Vector3(260.0, 1.0, 260.0)
	shape.shape = box
	_deck.add_child(shape)
	_city.add_child(_deck)
	_deck.global_position = _top - Vector3(0.0, 0.5, 0.0)


## A plain sedan on the deck at (x, z) facing `yaw`, physical, nobody in it.
func _car(at: Vector2, yaw: float) -> Vehicle:
	var car := Vehicle.new()
	car.setup(Vehicle.BodyType.SEDAN, Color(0.5, 0.06, 0.05), Vehicle.Addon.NONE)
	car.setup_look(Vehicle.Finish.GLOSS)
	_city.add_child(car)
	car.global_transform = Transform3D(Basis(Vector3.UP, yaw), _top + Vector3(at.x, 0.9, at.y))
	_cars.append(car)
	return car


## A chasing cruiser on the deck, its crew aboard.
func _cruiser(at: Vector2, yaw: float, kind: String = "pursue") -> PoliceCar:
	var car := _police.spawn_cruiser(WorldState.to_world(_top + Vector3(at.x, 0.9, at.y)), yaw, kind)
	car.mode = PoliceCar.Mode.PURSUE if kind == "pursue" else car.mode
	_cars.append(car)
	return car


func _drive(car: Vehicle) -> void:
	if _player.is_driving():
		_player.exit_vehicle()
	_player.enter_vehicle(car)


func _geometry() -> void:
	var frame := [Vector3.ZERO, Vector3.FORWARD, Vector3.RIGHT, 2.47, 0.92, 0.0]
	var slots := PoliceChase.box_slots(frame, 2.47, 0.92, 0.7)
	var apart := true
	for k in slots.size():
		var p: Vector3 = slots[k]
		var along := absf(p.dot(Vector3.FORWARD))
		var across := absf(p.dot(Vector3.RIGHT))
		apart = apart and (along > 2.47 * 2.0 or across > 0.92 * 2.0)
		for j in range(k + 1, slots.size()):
			apart = apart and p.distance_to(slots[j]) > 3.0
	_check(slots.size() == 4 and apart, "the four box slots stand clear of the car and of each other")
	var pit := PoliceChase.pit_slot(frame, 1.0, 2.47, 0.92, 0.55)
	var nose := pit + Vector3.FORWARD * 2.47
	_check(absf(nose.dot(Vector3.FORWARD) + 2.47 * 0.55) < 0.01 and pit.dot(Vector3.RIGHT) > 1.84,
		"a PIT car lines its front bumper up with the car's rear wheel, alongside it (%s)" % str(pit))
	var p := Vector3(100.0, 0.0, 50.0)
	var wob := Vector3(2.0, 0.0, 1.0)
	_check(PoliceChase.spot_target(p, wob) == p + wob, "on foot the searchlight hunts round the player as before")


## A stopped player's car with three cruisers coming at it: they stop round it, two or more.
func _box() -> void:
	var mine := _car(Vector2(0.0, 0.0), 0.0)
	await _ticks(10)
	_drive(mine)
	_police.set_wanted(2)
	var a := _cruiser(Vector2(-4.0, 34.0), 0.0)
	var b := _cruiser(Vector2(5.0, -36.0), PI)
	var c := _cruiser(Vector2(32.0, 3.0), PI * 0.5)
	var boxed := 0
	var roles_seen := {}
	var worst_gap := INF
	for i in 1200:
		await _tree.physics_frame
		if i % 20 == 0:
			_police.report_sighting()
		for car: PoliceCar in [a, b, c]:
			var r: Dictionary = _chase.roles.get(car.get_instance_id(), {})
			if not r.is_empty():
				roles_seen[int(r.role)] = true
		boxed = 0
		for car: PoliceCar in [a, b, c]:
			if is_instance_valid(car) and car.mode != PoliceCar.Mode.PURSUE:
				var d := car.global_position.distance_to(mine.global_position)
				worst_gap = minf(worst_gap, d)
				if d < 7.5:
					boxed += 1
		if boxed >= 2 and _chase.boxes > 0:
			break
	_check(roles_seen.has(PoliceChase.Role.BOX), "cruisers near a stopped car take box roles (%s)" % str(roles_seen.keys()))
	_check(boxed >= 2 and _chase.boxes > 0, "the cruisers box the stopped car in (%d round it, %d box-ins)" % [boxed, _chase.boxes])
	_check(worst_gap > 2.0, "no boxing cruiser ends up inside the car (nearest %.1f m)" % worst_gap)
	_police.clear()
	_player.exit_vehicle()
	_player.global_position = _top + Vector3(0.0, 1.2, 60.0)
	mine.queue_free()
	await _ticks(3)


## A fast car with a cruiser behind it: the cruiser gets the PIT; the assist spins the car and
## gives its grip back after.
func _pit() -> void:
	var mine := _car(Vector2(-40.0, 80.0), 0.0)
	await _ticks(10)
	_drive(mine)
	_police.set_wanted(2)
	var cop := _cruiser(Vector2(-37.0, 93.0), 0.0)
	await _ticks(2)
	mine.linear_velocity = Vector3.FORWARD * 18.0
	cop.linear_velocity = Vector3.FORWARD * 18.0
	mine.hold_crash_watch(3)
	cop.hold_crash_watch(3)
	await _ticks(2)
	_chase._pit_cool = 0.0
	_chase._assign()
	var r: Dictionary = _chase.roles.get(cop.get_instance_id(), {})
	_check(int(r.get("role", -1)) == PoliceChase.Role.PIT and float(r.get("side", 0.0)) > 0.0,
		"the cruiser behind a fast car gets the PIT, on its own side (%s)" % str(r))
	var grip := []
	for w in mine.wheels:
		grip.append(w.wheel_friction_slip)
	var pits := _chase.pits
	_chase.pit_assist(cop, mine, 1.0)
	await _ticks(1)
	var spin := mine.angular_velocity.y
	var slipped := true
	for i in mine.wheels.size():
		if not mine.wheels[i].use_as_steering and mine.wheels[i].wheel_friction_slip > float(grip[i]) * 0.5:
			slipped = false
	# The cruiser on the car's right pushes its rear left, so the nose swings right: negative yaw.
	_check(_chase.pits == pits + 1 and spin < -1.2, "the PIT's contact spins the car away from the cruiser (yaw %.2f rad/s)" % spin)
	_check(slipped, "the car's rear tyres let go for the slide (the fronts slip less)")
	await _ticks(int(_chase.pit_slip_seconds * 60.0) + 10)
	var back := true
	for i in mine.wheels.size():
		back = back and is_equal_approx(mine.wheels[i].wheel_friction_slip, float(grip[i]))
	_check(back, "and get their grip back after it")
	_police.clear()
	_player.exit_vehicle()
	_player.global_position = _top + Vector3(0.0, 1.2, 60.0)
	mine.queue_free()
	await _ticks(3)


## A car rolled over a strip goes flat and squats; a police car over it does not.
func _spikes() -> void:
	var strip := ChaseSpikeStrip.new()
	strip.length = 7.0
	_chase.add_strip(strip, _top + Vector3(40.0, 0.0, 0.0), 0.0)
	await _ticks(60)
	var link := ChaseSpikeStrip.link_mesh()
	_check(strip.get_node("Links").multimesh.instance_count >= 20 and link.get_faces().size() / 3 > 90,
		"the strip is a lattice of spiked links (%d links, %d triangles a link)" % [strip.get_node("Links").multimesh.instance_count, link.get_faces().size() / 3])
	# Put across it a few steps at a time (the sweep sees each wheel cross between two ticks); a
	# car driven over it is tools/police_chase/strip_probe.tscn (on a deck up here the car digs
	# into the thin static box at speed, so the drive is checked there, not here).
	var car := _car(Vector2(40.0, 4.0), 0.0)
	await _ticks(20)
	var radius := car.wheels[0].wheel_radius
	var flats := 0
	for z in [3.0, 2.0, 1.0, 0.2, -0.6, -1.4, -2.2, -3.0, -3.8]:
		car.global_position.z = _top.z + float(z)
		await _ticks(4)
		flats = ChaseFlatTyres.flats(car)
	_check(flats >= 2 and strip.punctured >= 2, "a car over the strip gets flat tyres (%d flat)" % flats)
	_check(car.wheels[0].wheel_radius < radius - 0.05 or car.wheels[2].wheel_radius < radius - 0.05,
		"a flat wheel rides lower on its rim (%.3f -> %.3f m)" % [radius, car.wheels[0].wheel_radius])
	# A cruiser put across the same strip afterwards, a few steps a side (the sweep sees it cross).
	var cop := _cruiser(Vector2(42.0, -3.0), PI, "parked")
	cop.mode = PoliceCar.Mode.PARKED
	await _ticks(20)
	for z in [-1.5, -0.6, 0.3, 1.2, 2.1, 3.0]:
		cop.global_position.z = _top.z + float(z)
		await _ticks(4)
	_check(strip._watch.has(cop.get_instance_id()) and ChaseFlatTyres.flats(cop) == 0, "the police's own car crosses its strip and is not punctured")
	car.queue_free()
	_player.global_position = _top + Vector3(0.0, 1.2, 60.0)
	strip.queue_free()
	await _ticks(3)


## A roadblock on a real road lays its strip on the player's side, across the carriageway.
func _roadblock(ws: Node, home: Vector3) -> void:
	var plan := _police.plan
	if plan == null:
		_check(false, "the police have a city plan")
		return
	var index := plan._index_at(CityPlan.AXIS_X, home.x)
	var road := plan.road_pos(CityPlan.AXIS_X, index)
	var mid := Vector2(road, home.z + 60.0)
	var strip := PoliceChase.roadblock(_police, mid, CityPlan.AXIS_X, index, 1.0)
	_check(strip != null, "a roadblock lays a spike strip")
	if strip == null:
		return
	var w: Vector3 = ws.to_world(strip.global_position)
	var width := plan.road_width(CityPlan.AXIS_X, index)
	_check(absf(w.x - road) < 0.5 and w.z < mid.y - 10.0 and w.z > mid.y - 20.0 and absf(strip.length - (width - 1.2)) < 0.1,
		"the strip lies across the road on the player's side of the cruisers (%.1f m short, %.1f of %.1f m)" % [mid.y - w.z, strip.length, width])
	strip.queue_free()
	await _ticks(2)


## Officers out of a parked cruiser with the player ahead: behind their open doors, then forward
## by bounds, never both of a car at once.
func _doors() -> void:
	_police.set_wanted(2)
	_player.global_position = _top + Vector3(-60.0, 1.2, -30.0)
	_chase.advance_after = 2.0
	var cop := _cruiser(Vector2(-60.0, -2.0), 0.0, "parked")
	cop.mode = PoliceCar.Mode.PARKED
	await _ticks(2)
	if cop.crew_aboard > 0:
		_police.deploy_crew(cop)
	var crew: Array = []
	for o in _police.officers:
		if is_instance_valid(o) and (o as PoliceOfficer).car == cop:
			crew.append(o)
	_check(crew.size() >= 2, "the crew gets out (%d)" % crew.size())
	if crew.size() < 2:
		return
	var at_door := false
	var opened := false
	var both_moving := false
	var advanced := 0.0
	var start_d := {}
	for i in 900:
		await _tree.physics_frame
		if i % 20 == 0:
			_police.report_sighting()
		var moving := 0
		for o: PoliceOfficer in crew:
			if not is_instance_valid(o):
				continue
			var b: Dictionary = _chase._bounds.get(o.get_instance_id(), {})
			if b.is_empty():
				continue
			if int(b.phase) == 1:
				moving += 1
			var d_player := o.global_position.distance_to(_player.global_position)
			if not start_d.has(o) and int(b.phase) == 0:
				var spot := PoliceChase.door_spot(cop, float(b.side))
				if Vector2(o.global_position.x - spot.x, o.global_position.z - spot.z).length() < 1.3:
					at_door = true
					start_d[o] = d_player
			if start_d.has(o):
				advanced = maxf(advanced, float(start_d[o]) - d_player)
		both_moving = both_moving or moving >= 2
		var rig := CarInteriors.rig_of(cop)
		if rig != null:
			for d: Dictionary in rig.doors:
				if float(d.open) > 0.8:
					opened = true
		if at_door and opened and advanced > 3.0:
			break
	_check(_chase.door_cars.has(cop.get_instance_id()), "the cruiser's doors are open for its crew")
	_check(opened, "a door rig swings the front door open and holds it there")
	_check(at_door, "an officer takes cover behind the open door")
	_check(advanced > 3.0, "then bounds forward toward the player (%.1f m)" % advanced)
	_check(not both_moving, "only one officer of a car moves at a time while the other covers")
	_police.clear()
	await _ticks(45)
	var shut := true
	var rig := CarInteriors.rig_of(cop) if is_instance_valid(cop) else null
	if rig != null:
		for d: Dictionary in rig.doors:
			shut = shut and not bool(d.get("chase_open", false))
	_check(shut and _chase.door_cars.is_empty(), "with the stars gone the doors are let go")


func _radio() -> void:
	var radio := _chase.radio
	var w := radio.stream_for("pursuit", 0)
	_check(w != null and w.get_length() > 2.4 and w.get_length() < 3.2 and w.mix_rate == ChaseRadio.RATE,
		"a pursuit call is a couple of seconds of radio (%.2f s)" % (w.get_length() if w else 0.0))
	_check(radio.stream_for("pursuit", 0) == w and radio.stream_for("pursuit", 1) != w, "transmissions are built once a variant")
	_police.set_wanted(1)
	radio._queue.clear()
	radio._player.stop()
	var before := radio.played
	radio._quiet = 0.0
	radio.say("spikes")
	radio.say("spikes")
	for i in 120:
		await _tree.process_frame
		if radio.played > before:
			break
	await _ticks(10)
	_check(radio.played == before + 1 and radio.last_kind == "spikes", "an event goes out on the radio once (%d played, last %s)" % [radio.played - before, radio.last_kind])
	radio._player.stop()
	radio._quiet = 0.0
	_police.clear()
	radio.say("pit")
	for i in 10:
		await _tree.process_frame
	_check(radio.played == before + 1, "no chatter once the stars are gone")
