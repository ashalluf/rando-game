extends RefCounted
## The fire department and the ambulances (Emergency, EmergencyCar, EmergencyCrew, FireStation)
## for tests/smoke_test.gd. Loaded at run time (not named there), so it compiles after the
## autoloads. Checks: both units build as models with their warning lenses, glass and a crew in
## the cab, inside a build budget, and a hit hands one to physics; CarDamage puts a fire out
## (burning -> smoking, a wreck's flames gone, the wreck stays); the stations are pure (the same
## answer twice, one lot claimed in its block, a nearest station and a way out onto the street),
## a station's chunk builds the firehouse and its doors roll up; an engine staged at a burning
## wreck runs its hose and puts it out, the crew climbs back in and it leaves; an ambulance staged
## at a body kneels at it, brings the stretcher, takes the body and leaves; a unit sent from off
## the street drives the lanes with its siren (the traffic sees it) and pulls up at the kerb by the
## call; a firefighter knocked down is a body, not another call; the sounds exist.

var _t: Node
var _tree: SceneTree
var _city: Node3D
var _plan: CityPlan
var _traffic: TrafficManager
var _ws: Node
var _em: Emergency
var _made: Array = []


func run(t: Node, city: Node3D) -> void:
	_t = t
	_tree = t.get_tree()
	_city = city
	_plan = city.plan
	_traffic = city.get_node("Traffic") as TrafficManager
	_ws = _tree.root.get_node("/root/WorldState")
	_em = city.get_node_or_null("Emergency") as Emergency
	_check(_em != null, "the city has an Emergency node")
	if _em == null:
		return
	var player := _tree.get_first_node_in_group("player") as Player
	if player.is_driving():
		player.exit_vehicle()
	var home: Vector3 = _ws.to_world(player.global_position)
	_em.enabled = true
	# Calls are opened by hand here: the scan would send a second unit to the same scene.
	var scan_was := _em.scan_interval
	_em.scan_interval = 1e9
	_em._scan_t = 1e9
	_em.clear()

	await _builds(player)
	await _extinguish(player)
	_stations()
	await _station_chunk()
	_traffic.staged = true
	_clear_traffic()
	await _fire_call(player)
	_em.clear()
	await _down_call(player)
	_em.clear()
	await _dispatch(player)
	_em.clear()
	_sounds()

	for c in _made:
		if is_instance_valid(c):
			(c as Node).queue_free()
	_made.clear()
	_traffic.staged = false
	_em.enabled = false
	_em.scan_interval = scan_was
	_em._scan_t = 0.0
	player.global_position = _ws.to_local(home)
	player.velocity = Vector3.ZERO
	_city.update_streaming(true)
	await _ticks(5)


func _check(ok: bool, label: String) -> void:
	_t._check(ok, label)


func _ticks(n: int) -> void:
	for i in n:
		await _tree.physics_frame


func _clear_traffic() -> void:
	for c in _traffic.cars.duplicate():
		if is_instance_valid(c):
			_traffic._retire(c)
	_traffic.cars.clear()


## A point on the spawn junction's x road, `along` metres from the crossing, `lat` off its centre
## (true world).
func _road_point(along: float, lat: float) -> Vector3:
	var x := _plan.road_pos(CityPlan.AXIS_X, 0) + lat
	var z := _plan.road_pos(CityPlan.AXIS_Z, 0) + along
	return Vector3(x, _plan.height_at(Vector2(x, z)) + CityChunk.ROAD_TOP, z)


func _builds(player: Player) -> void:
	player.global_position = _ws.to_local(_road_point(-60.0, 0.0)) + Vector3.UP * 1.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for kind: int in [EmergencyCar.Kind.ENGINE, EmergencyCar.Kind.AMBULANCE]:
		var t0 := Time.get_ticks_usec()
		var car := EmergencyCar.make(kind, rng)
		car.position = _ws.to_local(_road_point(30.0 + 25.0 * kind, 0.0)) + Vector3.UP * car.road_lift()
		_city.add_child(car)
		_made.append(car)
		var ms := float(Time.get_ticks_usec() - t0) / 1000.0
		var lenses := car._lens_mats.size()
		var shapes := car.get_children().filter(func(n: Node) -> bool: return n is CollisionShape3D).size()
		var name: String = Vehicle.BODY_NAMES[car.body_type]
		_check(car._has_model and lenses >= 2 and car._wheel_rigs.size() >= 4 and shapes > 0,
				"a %s builds as its model with its warning lenses, truck wheels and collision (model %s, lens materials %d, wheel rigs %d)" % [name, car._has_model, lenses, car._wheel_rigs.size()])
		_check(car.cabin_seats() > 0 and car._glass_slots.size() > 0, "its crew sits behind its cabin glass (seats %d)" % car.cabin_seats())
		_check(ms < 400.0, "a %s builds inside the budget (%.1f ms)" % [name, ms])
		car.service = _em
		car.mode = EmergencyCar.Mode.ON_SCENE
		for i in 3:
			await _tree.process_frame
		var lit := 0.0
		if not car._lens_mats.is_empty():
			var v: Variant = car._lens_mats[0].get_shader_parameter("lights_on")
			lit = float(v) if v != null else 0.0
		_check(lit > 0.5, "its lights run on scene (%.1f)" % lit)
	var engine: EmergencyCar = _made[0]
	engine.take_hit(-1, 30.0, Vector3.FORWARD, engine.global_position + Vector3.UP, Vehicle.HIT_BULLET)
	await _ticks(3)
	_check(not engine.is_traffic() and not engine.freeze and engine.wheels.size() >= 4,
			"a round in a fire engine hands it to physics on its wheels (%d)" % engine.wheels.size())
	engine.service = null


func _extinguish(player: Player) -> void:
	var car := Vehicle.random_car(RandomNumberGenerator.new())
	car.position = _ws.to_local(_road_point(-20.0, 3.0)) + Vector3.UP * 0.6
	_city.add_child(car)
	_made.append(car)
	await _ticks(3)
	var dmg := car.damage_state()
	dmg._ignite(false)
	var burning := dmg.on_fire() and dmg.state == CarDamage.State.BURNING
	dmg.extinguish()
	_check(burning and not dmg.on_fire() and dmg.state == CarDamage.State.SMOKING and dmg.extinguished,
			"water puts a burning car out: it is left smoking (state %d)" % dmg.state)
	dmg.become_wreck()
	var held_burning := dmg.on_fire()
	dmg.hold_fire(60.0)
	dmg._wreck_t = dmg.wreck_fire_seconds - 0.1
	await _ticks(20)
	var still := dmg.on_fire()
	for i in 30:
		dmg.douse(0.3)
	_check(held_burning and still and not dmg.on_fire() and car.is_wreck(),
			"a wreck held burning for the engine stays alight, and the hose puts it out (the wreck stays)")


func _stations() -> void:
	var c := FireStation._cell_of(Vector2(0.0, 0.0))
	var found: Dictionary = {}
	var cells := 0
	for dx in range(-3, 4):
		for dz in range(-3, 4):
			var s := FireStation.for_cell(_plan, c + Vector2i(dx, dz))
			if not s.is_empty():
				cells += 1
				if found.is_empty():
					found = s
	_check(cells >= 3, "the city round the spawn has fire stations (%d in 49 cells)" % cells)
	if found.is_empty():
		return
	FireStation._cache.clear()
	var again := FireStation.for_cell(_plan, found.cell)
	_check(not again.is_empty() and int(again.lot.seed) == int(found.lot.seed) and again.number == found.number,
			"a station is worked out the same way twice (station %d)" % found.number)
	var claimed := 0
	for lot: Dictionary in _plan.lots(found.block.x, found.block.y):
		if FireStation.claims(_plan, found.block.x, found.block.y, lot):
			claimed += 1
	_check(claimed == 1, "its block gives up exactly one lot to it (%d)" % claimed)
	var near := FireStation.nearest(_plan, found.front + Vector2(40.0, 30.0), 700.0)
	var out := FireStation.exit_lane(_plan, found, found.front + Vector2(200.0, 0.0))
	_check(not near.is_empty() and not out.is_empty(), "a call near it finds it, and a way out onto the street")


func _station_chunk() -> void:
	var c := FireStation._cell_of(Vector2(0.0, 0.0))
	var found: Dictionary = {}
	for r in 4:
		for dx in range(-r, r + 1):
			for dz in range(-r, r + 1):
				if found.is_empty():
					found = FireStation.for_cell(_plan, c + Vector2i(dx, dz))
	if found.is_empty():
		_check(false, "a fire station to build")
		return
	var chunk: CityChunk = _city._new_chunk(found.block, CityChunk.Level.FULL)
	chunk.build()
	var st: Node3D = null
	for n in chunk.get_children():
		if n.is_in_group("fire_station"):
			st = n
	var doors: Array = []
	if st:
		doors = st.get_children().filter(func(n: Node) -> bool: return String(n.name).begins_with("BayDoor"))
	_check(st != null and doors.size() == FireStation.BAYS and st.has_node("Body") and st.has_node("Building"),
			"its block's chunk builds the firehouse with %d bay doors and collision" % doors.size())
	if st:
		FireStation.open_door(_tree, found)
		await _ticks(int(FireStation.DOOR_TIME * 60.0) + 10)
		var up := (doors[0] as Node3D).position.y if not doors.is_empty() else 0.0
		_check(up > FireStation.BAY_DOOR.y * 0.8, "its bay doors roll up when a unit goes out (%.2f m)" % up)
	var lod := CityChunk.new()
	lod.plan = _plan
	lod.ix = found.block.x
	lod.iz = found.block.y
	lod.level = CityChunk.Level.LOD
	lod.style = _city.chunk_style()
	lod.capturing = true
	lod.build()
	var boxes: Dictionary = lod.captured.batch.get("lod_box", {"xforms": []})
	_check((boxes.xforms as Array).size() > 0, "the far city sees it too")
	chunk.queue_free()
	lod.free()


## A wreck burning on the street, an engine pulled up at the kerb: the hose goes on, the fire
## goes out, the crew climbs back in and the engine leaves.
func _fire_call(player: Player) -> void:
	var at := _road_point(-45.0, 5.0)
	player.global_position = _ws.to_local(_road_point(-80.0, -6.0)) + Vector3.UP * 1.0
	var car := Vehicle.random_car(RandomNumberGenerator.new())
	car.position = _ws.to_local(at) + Vector3.UP * 0.6
	_city.add_child(car)
	_made.append(car)
	await _ticks(10)
	car.damage_state().become_wreck()
	var inc := _em.open_call(Emergency.KIND_FIRE, _ws.to_world(car.global_position), car)
	var unit := _em.stage(EmergencyCar.Kind.ENGINE, inc)
	_check(unit != null and unit.mode == EmergencyCar.Mode.ON_SCENE and _em.crews.size() == 3,
			"an engine at a burning wreck pulls up at the kerb and its three firefighters get out (%d)" % _em.crews.size())
	if unit == null:
		return
	var kerb: float = (unit.global_position - (_ws.to_local(at) as Vector3)).length()
	_check(kerb > 6.0 and kerb < 40.0, "it stands off the fire (%.1f m)" % kerb)
	var hosed := false
	var out_at := -1
	var left := false
	for i in 60 * 40:
		await _tree.physics_frame
		for c in _em.crews:
			if is_instance_valid(c) and c._water != null and c._water.emitting and c._hose != null:
				hosed = true
		if out_at < 0 and not car._damage.on_fire():
			out_at = i
		if unit.mode == EmergencyCar.Mode.LEAVING:
			left = true
			break
	_check(hosed, "a firefighter lays a hose from the pump panel and puts water on it")
	_check(out_at >= 0 and car._damage.extinguished and car.is_wreck(), "the fire goes out (after %.1f s) and the wreck stays" % (out_at / 60.0))
	if not left:
		for c in _em.crews:
			if is_instance_valid(c):
				print("crew job %d task %d at %s dest %s door %s pose %s" % [c.job, c.task, c.global_position, c._dest, c._door(), c._pose])
	_check(left and unit.crew_aboard == unit.crew_alive, "the crew climbs back in and the engine leaves")


## A body on the pavement, an ambulance at the kerb: a paramedic kneels at it, the other brings the
## stretcher, they take it away and leave.
func _down_call(player: Player) -> void:
	var at := _road_point(40.0, _plan.road_width(CityPlan.AXIS_X, 0) * 0.5 + 2.0)
	player.global_position = _ws.to_local(_road_point(70.0, -6.0)) + Vector3.UP * 1.0
	var ped := Pedestrian.new()
	ped.setup(Rect2(at.x - 1.0, at.z - 1.0, 2.0, 2.0), 1.0, 99)
	ped.position = _ws.to_local(at) + Vector3.UP * 0.3
	_city.add_child(ped)
	await _ticks(5)
	ped.knock(Vector3(0.0, 1.0, 0.5))
	var doll: Ragdoll = ped._doll
	await _ticks(60)
	_check(doll != null and is_instance_valid(doll), "somebody knocked down is a body on the street")
	if doll == null or not is_instance_valid(doll):
		return
	var inc := _em.open_call(Emergency.KIND_DOWN, _ws.to_world(doll.bodies[0].global_position), null, doll)
	var unit := _em.stage(EmergencyCar.Kind.AMBULANCE, inc)
	_check(unit != null and _em.crews.size() == 2, "an ambulance pulls up and two paramedics get out (%d)" % _em.crews.size())
	if unit == null:
		return
	var knelt := false
	var cot := false
	var left := false
	for i in 60 * 45:
		await _tree.physics_frame
		for c in _em.crews:
			if is_instance_valid(c):
				knelt = knelt or c._pose == "kneel"
				cot = cot or c._stretcher != null
		if unit.mode == EmergencyCar.Mode.LEAVING:
			left = true
			break
	if not left:
		for c in _em.crews:
			if is_instance_valid(c):
				print("medic job %d task %d at %s dest %s pose %s stretcher %s work %.1f" % [c.job, c.task, c.global_position, c._dest, c._pose, c._stretcher != null, c._work_t])
		print("doll at ", doll.bodies[0].global_position if is_instance_valid(doll) else Vector3.ZERO, " unit ", unit.global_position)
	_check(knelt, "a paramedic kneels at the body with the bag")
	_check(cot and inc.loaded and not is_instance_valid(doll), "the other brings the stretcher and they take the body")
	_check(left, "they climb back in and the ambulance leaves")


## A unit sent from off the street: on the lanes with its siren (the traffic sees it), and at the
## kerb by the call.
func _dispatch(player: Player) -> void:
	var at := _road_point(-30.0, 0.0)
	player.global_position = _ws.to_local(_road_point(-30.0, -8.0)) + Vector3.UP * 1.0
	var reach := _em.station_reach
	_em.station_reach = 0.0
	var inc := _em.open_call(Emergency.KIND_BLAST, at)
	var unit := _em.send(EmergencyCar.Kind.ENGINE, inc)
	_em.station_reach = reach
	_check(unit != null, "an engine can be sent along a street out of sight")
	if unit == null:
		return
	inc.engine = unit
	await _ticks(10)
	var heard := false
	for s: Array in _traffic._siren_list():
		heard = heard or (int(s[0]) == int(unit.traffic.axis) and int(s[1]) == int(unit.traffic.index))
	_check(unit.siren_running() and heard, "on its way it runs its siren and the traffic sees it")
	var arrived := false
	for i in 60 * 50:
		await _tree.physics_frame
		if unit.mode == EmergencyCar.Mode.ON_SCENE:
			arrived = true
			break
	var at_l: Vector3 = _ws.to_local(at)
	var d := Vector2(unit.global_position.x - at_l.x, unit.global_position.z - at_l.z).length()
	_check(arrived and d < 45.0, "it drives the streets to the call and pulls up at the kerb (%.1f m off, %s)" % [d, arrived])
	if arrived:
		await _ticks(10)
		var crew: EmergencyCrew = null
		for c in _em.crews:
			if is_instance_valid(c):
				crew = c
		if crew:
			var parent := crew.get_parent()
			var before := parent.get_child_count()
			crew.knock(Vector3(0.0, 2.0, 4.0))
			await _ticks(2)
			var doll: Node = null
			for k in range(before - 1, parent.get_child_count()):
				if parent.get_child(k) is Ragdoll:
					doll = parent.get_child(k)
			_check(doll != null and doll.has_meta("responder") and not _em.crews.has(crew),
					"a firefighter knocked down is a body like anyone's, not another call")


func _sounds() -> void:
	var sfx: Node = _tree.root.get_node("/root/Sfx")
	var takes: Dictionary = sfx.get("_streams")
	_check(takes.has("siren_yelp") and takes.has("fire_horn"), "the yelp and the air horn are loaded")
