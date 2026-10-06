extends RefCounted
## Lowriders (Lowrider, LowriderMeet, MeetGoer), for tests/smoke_test.gd. Loaded at run time, not
## named there, so it compiles after the autoloads.
##
## Checks the tables (both bodies in every per-type table, never rolled), the wire wheel's
## budgets, the two bodies built on a deck high over the street (model, glass, far twin, four wire
## wheels, the custom paint), the hydraulics (a hop takes the nose and its wheels off the road and
## comes back down, a three-wheel lifts one front wheel with the rear across from it laid, a car
## knocked physical lays its body back at rest), where the meets are (pure, on boulevards in
## their districts, only on weekend nights), the meet's chunk (its row of lowriders, the crowd, no
## parked car in the row, and the block otherwise the same block with the meets off) and the
## traffic's cruisers (a share in the right districts, none elsewhere, slower).

var _t: Node
var _tree: SceneTree
var _city: Node3D
var _deck: StaticBody3D
var _top: Vector3
var _cars: Array = []


func run(t: Node, city: Node3D) -> void:
	_t = t
	_tree = t.get_tree()
	_city = city
	var plan: CityPlan = city.plan
	_tables()
	_wheels()
	var ws: Node = _tree.root.get_node("/root/WorldState")
	var player := _tree.get_first_node_in_group("player") as Node3D
	if player.call("is_driving"):
		player.call("exit_vehicle")
	var home: Vector3 = ws.to_world(player.global_position)
	_top = player.global_position + Vector3(0.0, 360.0, 0.0)
	_build_deck()
	player.global_position = _top + Vector3(0.0, 1.2, 40.0)
	player.velocity = Vector3.ZERO
	await _ticks(3)
	await _builds()
	await _hydraulics()
	for c in _cars:
		if is_instance_valid(c):
			c.queue_free()
	_cars.clear()
	_deck.queue_free()
	player.global_position = ws.to_local(home)
	player.velocity = Vector3.ZERO
	await _ticks(2)
	_where(plan)
	_cruisers(plan)
	await _meet_chunk(city, plan)


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
	box.size = Vector3(120.0, 1.0, 80.0)
	shape.shape = box
	_deck.add_child(shape)
	_city.add_child(_deck)
	_deck.global_position = _top - Vector3(0.0, 0.5, 0.0)


func _tables() -> void:
	var ok := true
	for type: int in [Lowrider.HARDTOP, Lowrider.COUPE]:
		ok = ok and Vehicle.BODY_MODELS.has(type) and ResourceLoader.exists(Vehicle.BODY_MODELS[type])
		ok = ok and int(Vehicle.BODY_ODDS.get(type, -1)) == 0 and Vehicle.WHEEL_POSE.has(type) \
			and bool((Vehicle.WHEEL_POSE[type] as Dictionary).get("wire", false)) and Lowrider.DIMS.has(type) \
			and Lowrider.PAINT_PLACES.has(type)
		ok = ok and Vehicle.BODY_NAMES.size() > type
	var never := true
	for roll in 1000:
		never = never and not Lowrider.is_lowrider(Vehicle._body_for_roll(roll))
	_check(ok and never, "both lowrider bodies are in every per-type table, and random_car() never rolls one")
	var hours_ok := LowriderMeet.is_on(21.0, 6) and LowriderMeet.is_on(0.5, 0) and LowriderMeet.is_on(19.0, 5) \
		and not LowriderMeet.is_on(13.0, 6) and not LowriderMeet.is_on(21.0, 2) and not LowriderMeet.is_on(0.5, 2)
	_check(LowriderMeet.force or hours_ok, "meets run on Friday, Saturday and Sunday nights only (past midnight too)")


func _wheels() -> void:
	var near := Lowrider.wire_wheel(0.292, 0.16, true, 0)
	var far := Lowrider.wire_wheel(0.292, 0.16, false, 2)
	var tn := _tris(near)
	var tf := _tris(far)
	var box := near.get_aabb()
	_check(tn > 2000 and tn < 9000 and tf > 100 and tf < 1600 and box.size.y < 0.6 and box.size.y > 0.55,
		"a wire wheel is a 72-spoke near mesh and a light far one (%d / %d triangles, %.2f m across)" % [tn, tf, box.size.y])


static func _tris(m: Mesh) -> int:
	var n := 0
	for s in m.get_surface_count():
		var arr := m.surface_get_arrays(s)
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		n += idx.size() / 3 if idx.size() > 0 else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return n


func _car(type: int, at: Vector2, look: int) -> Vehicle:
	var car := Lowrider.make(type, look)
	car.traffic = {"axis": 0, "index": 0, "dir": 1, "lane": 0.0, "speed": 0.0, "v": 0.0, "half": 2.7, "rear": 2.7, "parked": true}
	car.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	car.freeze = true
	car.position = _city.to_local(_top + Vector3(at.x, car.road_lift(), at.y))
	_city.add_child(car)
	_cars.append(car)
	return car


func _builds() -> void:
	var ok := true
	var why := ""
	var worst := 0.0
	var x := -12.0
	for type: int in [Lowrider.HARDTOP, Lowrider.COUPE]:
		var t0 := Time.get_ticks_usec()
		var car := _car(type, Vector2(x, 0.0), 77 + type)
		worst = maxf(worst, float(Time.get_ticks_usec() - t0) / 1000.0)
		x += 8.0
		var far := 0
		for m: MeshInstance3D in car._body_meshes:
			if String(m.name).ends_with("_far"):
				far += 1
		var paint_ok := false
		for m: MeshInstance3D in car._body_meshes:
			for si in m.mesh.get_surface_count():
				var sm := m.get_surface_override_material(si) as ShaderMaterial
				if sm != null and sm.get_shader_parameter("custom") != null and float(sm.get_shader_parameter("custom")) > 0.5 \
						and sm.get_shader_parameter("pin_side") is Vector4 and (sm.get_shader_parameter("pin_side") as Vector4).x > 0.5:
					paint_ok = true
		var wire := car._wheel_rigs.size() == 4 and (car._wheel_rigs[0][1] as MeshInstance3D).mesh == Lowrider.wire_wheel(0.292, 0.16, true, _gold_of(car))
		var good := car._has_model and far > 0 and not car._glass_slots.is_empty() and paint_ok and wire \
			and car.get_node_or_null("Hydraulics") != null and car.wheels.is_empty()
		if not good:
			ok = false
			why += " %s(model %s far %d glass %d paint %s wire %s)" % [Vehicle.BODY_NAMES[type], car._has_model, far, car._glass_slots.size(), paint_ok, wire]
	_check(ok, "both lowriders build as a model with glass, a far twin, wire wheels, hydraulics and the custom paint%s" % why)
	_check(worst < 400.0, "a lowrider builds in %.0f ms (under 400)" % worst)
	await _ticks(2)


static func _gold_of(car: Vehicle) -> int:
	var roll := absi(hash([car.look_seed, 6])) % 1000
	if roll < int(Lowrider.GOLD_HUB_SHARE * 1000.0):
		return 1
	if roll < int((Lowrider.GOLD_HUB_SHARE + Lowrider.GOLD_SPOKE_SHARE) * 1000.0):
		return 2
	return 0


func _hydraulics() -> void:
	var car: Vehicle = _cars[0]
	var h: Node = car.get_node("Hydraulics")
	var body := car.get_node("BodyModel") as Node3D
	h.set("mode", Lowrider.Hydraulics.Mode.PARKED)
	h.call("advance", 1.0)
	var rest_y := body.position.y
	var rig_y := float(car._wheel_rigs[0][5])
	h.call("perform", "hop")
	var peak := 0.0
	var wheel_up := 0.0
	var rear_low := 1.0
	for i in 90:
		h.call("advance", 1.0 / 60.0)
		var hs: PackedFloat32Array = h.call("heights")
		peak = maxf(peak, hs[0])
		rear_low = minf(rear_low, hs[2])
		wheel_up = maxf(wheel_up, (car._wheel_rigs[0][0] as Node3D).position.y - rig_y)
	var hops := int(h.get("hops_done"))
	_check(peak > 0.45 and wheel_up > 0.15 and rear_low < 0.05 and hops >= 1,
		"a hop throws the nose up %.2f m and its wheels %.2f m off the road while the rear squats (%d hops)" % [peak, wheel_up, hops])
	h.call("advance", 30.0)
	var hs2: PackedFloat32Array = h.call("heights")
	_check(String(h.call("routine")) == "" and absf(hs2[0] - float(h.get("laid"))) < 0.03 \
		and absf((car._wheel_rigs[0][0] as Node3D).position.y - rig_y) < 0.005,
		"after the hops the car comes back down laid out on its wheels (front %.3f)" % hs2[0])
	h.call("perform", "three", 1.0)
	h.call("advance", 2.0)
	var hs3: PackedFloat32Array = h.call("heights")
	var lifted := (car._wheel_rigs[1][0] as Node3D).position.y - float(car._wheel_rigs[1][5])
	var other := (car._wheel_rigs[0][0] as Node3D).position.y - float(car._wheel_rigs[0][5])
	_check(hs3[1] > float(h.get("stroke")) + 0.1 and lifted > 0.1 and other < 0.01 and hs3[2] < hs3[3] + 0.001 and hs3[2] <= hs3[0],
		"a three-wheel lifts one front wheel %.2f m off the road with the rear across from it laid down" % lifted)
	_check(absf(body.rotation.z) > 0.05 and absf(body.rotation.x) > 0.02, "the body rolls and pitches with the corners (roll %.2f, pitch %.2f rad)" % [body.rotation.z, body.rotation.x])
	# Knocked out of its row the car is a physics car: the body lies back at rest.
	car.drop_out_of_traffic()
	await _ticks(3)
	await _tree.process_frame
	await _tree.process_frame
	_check(body.transform.is_equal_approx(Transform3D.IDENTITY) and absf(body.position.y - rest_y) < 0.2,
		"a lowrider knocked physical lays its body back at rest")


func _where(plan: CityPlan) -> void:
	LowriderMeet.reset()
	var found := []
	for cx in range(-3, 4):
		for cz in range(-3, 4):
			var m := LowriderMeet.decide(plan, Vector2i(cx, cz))
			if not m.is_empty():
				found.append(m)
	var ok := not found.is_empty()
	var why := ""
	for m: Dictionary in found:
		var b := plan.block((m.owner as Vector2i).x, (m.owner as Vector2i).y)
		var width := plan.road_width(int(m.axis), int(m.index))
		var good := width >= LowriderMeet.MIN_WIDTH and int(b.district) in LowriderMeet.DISTRICTS \
			and int(m.cars) >= 3 and float(m.hi) - float(m.lo) >= LowriderMeet.MIN_LEN \
			and plan.road_open(int(m.axis), int(m.index), (float(m.lo) + float(m.hi)) * 0.5)
		if not good:
			ok = false
			why += " %s" % str(m.owner)
	# Pure: decided again from nothing, the same meets.
	LowriderMeet.reset()
	var again := 0
	for m: Dictionary in found:
		var m2 := LowriderMeet.decide(plan, m.cell)
		if not m2.is_empty() and m2.owner == m.owner and int(m2.side) == int(m.side) and int(m2.cars) == int(m.cars):
			again += 1
	_check(ok and again == found.size(), "%d meets round the middle of the map, each on an open boulevard in its districts, decided the same way twice%s" % [found.size(), why])


func _cruisers(plan: CityPlan) -> void:
	var on := 0
	var off := 0
	var wrong := 0
	var n := 4000
	LowriderMeet.force_hour = 21.0
	LowriderMeet.force_day = 6
	for i in n:
		var p := Vector2(float(i % 80) * 97.0 - 3900.0, float(i / 80) * 131.0 - 3300.0)
		var k := LowriderMeet.traffic_kind(_city, plan, p, float(i) / float(n))
		var d := int(plan.district_at(p))
		if k >= 0:
			on += 1
			if not (d in LowriderMeet.DISTRICTS):
				wrong += 1
	LowriderMeet.force_day = 2
	LowriderMeet.force_hour = 13.0
	for i in n:
		var p := Vector2(float(i % 80) * 97.0 - 3900.0, float(i / 80) * 131.0 - 3300.0)
		if LowriderMeet.traffic_kind(_city, plan, p, float(i) / float(n)) >= 0:
			off += 1
	LowriderMeet.force_hour = -1.0
	LowriderMeet.force_day = -1
	_check(on > 0 and wrong == 0 and off < on, "lowriders cruise in the traffic of their districts only, more on a meet night (%d on a Saturday night, %d on a Tuesday noon, of %d)" % [on, off, n])


func _meet_chunk(city: Node3D, plan: CityPlan) -> void:
	var meet := {}
	for cx in range(-3, 4):
		for cz in range(-3, 4):
			var m := LowriderMeet.decide(plan, Vector2i(cx, cz))
			if not m.is_empty():
				meet = m
				break
		if not meet.is_empty():
			break
	if meet.is_empty():
		_check(false, "a meet to build")
		return
	var k: Vector2i = meet.owner
	LowriderMeet.force_hour = 21.5
	LowriderMeet.force_day = 6
	var chunk: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
	chunk.build()
	var row := 0
	var parked_in_row := 0
	for car in chunk.get("_cars"):
		if not is_instance_valid(car):
			continue
		var p: Vector3 = WorldState.to_world((car as Node3D).position) if (car as Node).get_parent() != chunk else (car as Node3D).position
		if Lowrider.is_lowrider((car as Vehicle).body_type) and car.has_meta("lowrider_meet"):
			row += 1
		elif LowriderMeet.blocks_parking(chunk, p):
			parked_in_row += 1
	var goers := 0
	for c in chunk.get_children():
		if c is MeetGoer:
			goers += 1
	_check(row >= 3 and row <= int(meet.cars) and parked_in_row == 0,
		"a meet night parks a row of %d lowriders at its kerb and no other car in it (%d)" % [row, parked_in_row])
	# The crowd (made here too: the city's crowd cap may already be spent by the streamed city).
	var spots := LowriderMeet.people_spots(plan, meet, LowriderMeet.layout(meet))
	var stands := false
	if not spots.is_empty():
		var sp: Array = spots[0]
		var ped := MeetGoer.new()
		var at: Vector2 = sp[0]
		ped.setup_goer(plan.block(k.x, k.y).rect, int(sp[2]), at, float(sp[1]), int(meet.axis))
		ped.position = Vector3(at.x, chunk.ground_y(at.x, at.y) + 0.05, at.y)
		chunk.add_child(ped)
		stands = ped._act == CrowdLife.Act.STAND and Vector2(ped.position.x, ped.position.z).distance_to(at) < 0.05
		var kerb := float(meet.centre) + float(meet.side) * float(meet.width) * 0.5
		var across := at.x if int(meet.axis) == CityPlan.AXIS_X else at.y
		stands = stands and (across - kerb) * float(meet.side) > 0.5
	_check(spots.size() >= 6 and stands, "the meet's crowd stands on the pavement by the cars (%d spots, %d spawned in the cap)" % [spots.size(), goers])
	var sig := _signature(chunk)
	_free_chunk(chunk)
	LowriderMeet.force_day = 2
	LowriderMeet.force_hour = 13.0
	var quiet: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
	quiet.build()
	var lows := 0
	for car in quiet.get("_cars"):
		if is_instance_valid(car) and car.has_meta("lowrider_meet"):
			lows += 1
	_check(lows == 0 and _signature(quiet) == sig, "on a Tuesday noon the kerb is ordinary and the block is the same block (rolls untouched)")
	_free_chunk(quiet)
	LowriderMeet.force_hour = -1.0
	LowriderMeet.force_day = -1


func _free_chunk(chunk: CityChunk) -> void:
	for car in chunk.get("_cars"):
		if is_instance_valid(car):
			(car as Node).get_parent().remove_child(car)
			(car as Node).free()
	(chunk.get("_cars") as Array).clear()
	chunk.get_parent().remove_child(chunk)
	chunk.free()


## Buildings, props and trash cans by position.
func _signature(chunk: CityChunk) -> Array:
	var out: Array = []
	for c in chunk.get_children():
		if c is Building or c is TrashCan:
			var p: Vector3 = (c as Node3D).position
			out.append("%s %.2f %.2f" % [c.get_class(), p.x, p.z])
	for r in chunk.prop_records:
		out.append("%s %.2f %.2f" % [r.kind, (r.position as Vector3).x, (r.position as Vector3).z])
	out.sort()
	return out
