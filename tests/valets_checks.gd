extends RefCounted
## Valet stands (Valets, ValetKit, ValetStand, Valet), for tests/smoke_test.gd. Loaded at run
## time, not named there, so it compiles after the autoloads.
##
## Checks the hours (a restaurant's valets at dinner, not at 04:00; a hotel's round the clock),
## the kit's meshes (one surface each on the street vendors' shader, inside a triangle budget),
## then builds FULL chunks round downtown at 20:00 until one has an open stand and checks: every stand
## is at a hotel lobby or a restaurant, its podium on the pavement by the kerb, its zone clear of
## the block's corners; a kept zone has no parked car on it; the podium is a knockable body; a
## ValetStand is there with its valets planned; built with valets off it is the same block
## (buildings, props, trash cans) and its parked cars a superset. Then, staged (the traffic held,
## the stand in manual, the player hovering over it): a car placed upstream is driven to the
## drop-off on its hazards, its driver gets out, a valet runs to its door, gets in and it drives
## off as ordinary traffic; a car brought back with that valet at the wheel pulls in, the valet
## gets out and walks back to the podium, a guest comes out to it and it drives off.

var _t: Node
var _tree: SceneTree
var _ws: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	_tree = t.get_tree()
	_ws = _tree.root.get_node("/root/WorldState")
	_hours()
	_meshes()
	var plan: CityPlan = city.plan
	var found := _find(city, plan)
	_t._check(found.x != 99999, "a valet stand stands round downtown at 20:00 (block %s)" % str(found))
	if found.x != 99999:
		await _chunk(city, plan, found)
	Valets.force_hour = -1.0


func _hours() -> void:
	_t._check(not Valets.open_at(false, 4.0) and Valets.open_at(false, 19.5) and Valets.open_at(false, 12.5)
		and not Valets.open_at(false, 16.0) and Valets.open_at(true, 4.0) and Valets.open_at(true, 15.0),
		"valets work a restaurant's lunch and dinner, a hotel round the clock")
	_t._check(Valets.arrival_gap(true, 19.0).y < Valets.arrival_gap(true, 3.0).x and Valets.arrival_gap(false, 20.0).y <= Valets.arrival_gap(false, 13.0).y,
		"cars pull in more often in the evening than in the small hours")


func _meshes() -> void:
	var meshes: Array[Mesh] = [ValetKit.key_box(), ValetKit.cone(), ValetKit.umbrella_base()]
	for i in ValetKit.OPERATORS.size():
		meshes.append(ValetKit.podium(i))
	for i in ValetKit.RATES.size():
		meshes.append(ValetKit.sign(i))
	var ok := true
	var worst := 0
	for m in meshes:
		var tris := (m.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
		worst = maxi(worst, tris)
		ok = ok and m.get_surface_count() == 1 and m.surface_get_material(0) == StreetVendors.material() and tris > 100
	_t._check(ok, "every valet stand mesh is one surface on the street vendors' shader")
	_t._check(worst < 6000, "a valet stand mesh stays under 6k triangles (worst %d)" % worst)


## The first block round downtown whose FULL chunk builds an open stand at 20:00.
func _find(city: Node3D, plan: CityPlan) -> Vector2i:
	Valets.force_hour = 20.0
	var centre := plan.block_index_at(plan.macro.downtown_center if plan.macro else Vector2.ZERO)
	var tried := 0
	for r in 4:
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dz)) != r:
					continue
				var k := centre + Vector2i(dx, dz)
				var b := plan.block(k.x, k.y)
				if plan.zone_at((b.rect as Rect2).get_center()) != MacroMap.Zone.CITY or not Valets.wanted_block(b):
					continue
				var chunk: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
				chunk.build()
				var has := false
				for s: Dictionary in chunk.get_meta("valet_stands", []):
					has = has or bool(s.open)
				chunk.get_parent().remove_child(chunk)
				chunk.free()
				if has:
					return k
				tried += 1
				if tried > 24:
					return Vector2i(99999, 99999)
	return Vector2i(99999, 99999)


func _chunk(city: Node3D, plan: CityPlan, k: Vector2i) -> void:
	Valets.force_hour = 20.0
	var chunk: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
	chunk.build()
	var rect: Rect2 = plan.block(k.x, k.y).rect
	var stands: Array = chunk.get_meta("valet_stands", [])
	var placed := true
	for s: Dictionary in stands:
		var room := int(s.room)
		var pod: Vector2 = s.podium
		var z: Vector2 = s.zone
		var xrun := bool(s.xrun)
		var r0 := rect.position.x if xrun else rect.position.y
		var r1 := rect.end.x if xrun else rect.end.y
		var to_kerb := absf((pod.y if xrun else pod.x) - float(s.kerb))
		placed = placed and (room == Building.ShopRoom.LOBBY or room == Building.ShopRoom.RESTAURANT) and bool(s.hotel) == (room == Building.ShopRoom.LOBBY) \
			and rect.has_point(pod) and absf(to_kerb - Valets.PODIUM_IN) < 0.01 \
			and z.x >= r0 + Valets.CORNER_KEEP - 0.01 and z.y <= r1 - Valets.CORNER_KEEP + 0.01
	_t._check(not stands.is_empty() and placed, "valet stands are at hotel lobbies and restaurants, the podium by the kerb, the zone clear of the corners (%d)" % stands.size())
	var nodes := chunk.get_children().filter(func(n: Node) -> bool: return n is ValetStand)
	var open := stands.filter(func(s: Dictionary) -> bool: return bool(s.open))
	_t._check(nodes.size() == open.size(), "an open stand has its ValetStand (%d of %d)" % [nodes.size(), open.size()])
	var people: Array = chunk.get_meta("valet_people", [])
	var want := 0
	for s: Dictionary in open:
		want += int(s.valets)
	_t._check(people.size() == want and want >= 2, "each open stand plans its valets (%d)" % people.size())
	var podium: EncampmentItem = null
	for c in chunk.get_children():
		if c is EncampmentItem and String(c.name).begins_with("Valet_") and String(c.name).ends_with("_podium"):
			podium = c
	_t._check(podium != null and chunk.get_node_or_null("Batch_" + Valets.K_PODIUM + str(int((stands[0] as Dictionary).op))) != null,
		"the podium is a batch instance and a knockable body")
	var blocked := 0
	for car in chunk.get("_cars"):
		if is_instance_valid(car):
			var p: Vector3 = WorldState.to_world((car as Node3D).position) if (car as Node).get_parent() != chunk else (car as Node3D).position
			if Valets.blocks_parking(chunk, p):
				blocked += 1
	_t._check(blocked == 0, "no parked car stands in a valet zone (%d)" % blocked)
	var sig := _signature(chunk)
	var cars := _cars(chunk)
	# Off, the same block.
	chunk.get_parent().remove_child(chunk)
	chunk.free()
	Valets.enabled = false
	var bare: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
	bare.build()
	Valets.enabled = true
	var bare_cars := _cars(bare)
	var superset := true
	for c: String in cars:
		superset = superset and bare_cars.has(c)
	_t._check(_signature(bare) == sig and superset and bare_cars.size() >= cars.size(),
		"the valets roll nothing from the block: built without them it is the same block (%d cars, %d without)" % [cars.size(), bare_cars.size()])
	bare.get_parent().remove_child(bare)
	bare.free()
	await _live(city, plan, k)


## A stand at work, staged: a car in, a valet off in it, the car back, the guest away in it.
func _live(city: Node3D, plan: CityPlan, k: Vector2i) -> void:
	var traffic := city.get_node("Traffic") as TrafficManager
	var player := _tree.get_first_node_in_group("player") as Player
	if player.is_driving():
		player.exit_vehicle()
	var home: Vector3 = _ws.to_world(player.global_position)
	traffic.staged = true
	_clear_traffic(traffic)
	var chunk: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
	chunk.build()
	# A stand with its own kept zone if the block has one, else a double-parked one.
	var stand: ValetStand = null
	for n in chunk.get_children():
		if n is ValetStand and (stand == null or (bool(stand.s.double) and not bool((n as ValetStand).s.double))):
			stand = n
	_t._check(stand != null, "valets: a stand is at work in the chunk")
	if stand == null:
		_end_live(city, traffic, player, home, chunk)
		return
	stand.manual = true
	var s: Dictionary = stand.s
	for v: Variant in stand.valets.duplicate():
		if is_instance_valid(v):
			(v as Node).queue_free()
	stand.valets.clear()
	for i in 2:
		stand.add_valet(chunk, i, hash([plan.seed, "valet_check", i]))
	var pod: Vector2 = s.podium
	player.set_physics_process(false)
	player.global_position = _ws.to_local(Vector3(pod.x, chunk.ground_y(pod.x, pod.y) + 12.0, pod.y))
	player.velocity = Vector3.ZERO
	await _ticks(10)
	var lanes := int(s.lanes)
	var tdir := int(s.tdir)
	var along := float(s.stop_s) - float(tdir) * 45.0
	var car: Vehicle = traffic.place_car(int(s.axis), int(s.index), tdir, lanes - 1, along, 8.0, false)
	stand.take(car, false)
	var hazard := false
	var stopped := false
	var gone_valet: Valet = null
	for i in 3600:
		await _tree.physics_frame
		if not is_instance_valid(car):
			break
		hazard = hazard or bool(car.traffic.get("hazard", false))
		stopped = stopped or stand.front == car
		if stand.served >= 1:
			break
	for a: Array in stand.away:
		gone_valet = a[0]
	_t._check(stopped and hazard, "valets: a car called in stops at the drop-off on its hazards")
	_t._check(stand.served == 1 and gone_valet != null and gone_valet.hidden and not gone_valet.visible and gone_valet.collision_layer == 0,
		"valets: its driver gets out, a valet runs to its door and gets in (served %d)" % stand.served)
	var t_pull := 0
	for i in 600:
		await _tree.physics_frame
		t_pull = i
		if is_instance_valid(car) and not car.traffic.has("valet") and float(car.traffic.get("v", 0.0)) > 1.0:
			break
	_t._check(is_instance_valid(car) and car.is_traffic() and not car.traffic.has("valet") and not car.traffic.get("hazard", false) and float(car.traffic.get("v", 0.0)) > 1.0 and car._npc_driver,
		"valets: the car pulls away as ordinary traffic, the valet at the wheel")
	# The car back with that valet in it.
	if gone_valet != null:
		stand.away.clear()
		var back: Vehicle = traffic.place_car(int(s.axis), int(s.index), tdir, lanes - 1, float(s.stop_s) - float(tdir) * 45.0, 8.0, false)
		stand.take(back, true, gone_valet)
		var out_again := false
		for i in 3600:
			await _tree.physics_frame
			out_again = out_again or (stand.returned >= 1 and not gone_valet.hidden)
			if out_again and stand.front == null:
				break
		_t._check(out_again, "valets: a car brought back pulls in and its valet gets out")
		var at_podium := false
		for i in 1200:
			await _tree.physics_frame
			if gone_valet.free_for_job():
				at_podium = true
				break
		var vs := "freed"
		if is_instance_valid(gone_valet):
			var gv: Valet = gone_valet
			vs = "%.1f m from home, hidden %s, down %s, job %d/%d, stage %s, act %s, panic %.1f, errand %s, in tree %s" % [
				Vector2(gv.position.x, gv.position.z).distance_to(gv.home), gv.hidden, gv.get("_down"),
				int(gv.get("_job_k")), (gv.get("_job") as Array).size(), gv.get("_stage"), gv.get("_act"),
				float(gv.get("_panic_left")), not gv.errand.is_empty(), gv.is_inside_tree()]
		_t._check(at_podium, "valets: the valet walks back to the podium" + ("" if at_podium else " (%s)" % vs))
		_t._check(is_instance_valid(back) and not back.traffic.has("valet") and back._npc_driver, "valets: the car brought back drives off with its guest")
	_end_live(city, traffic, player, home, chunk)


func _end_live(city: Node3D, traffic: TrafficManager, player: Player, home: Vector3, chunk: CityChunk) -> void:
	_clear_traffic(traffic)
	traffic.staged = false
	if is_instance_valid(chunk):
		chunk.get_parent().remove_child(chunk)
		chunk.free()
	player.set_physics_process(true)
	player.global_position = _ws.to_local(home)
	player.velocity = Vector3.ZERO
	city.update_streaming(true)
	await _ticks(5)


func _clear_traffic(traffic: TrafficManager) -> void:
	for c in traffic.cars.duplicate():
		if is_instance_valid(c):
			traffic._retire(c)
	traffic.cars.clear()


func _ticks(n: int) -> void:
	for i in n:
		await _tree.physics_frame


## Buildings, props, trash cans, by position.
func _signature(chunk: CityChunk) -> Array:
	var out: Array = []
	for c in chunk.get_children():
		if c is Building or c is TrashCan:
			var p: Vector3 = (c as Node3D).position
			out.append("%s %.2f %.2f" % [c.get_class(), p.x, p.z])
	for r in chunk.prop_records:
		out.append("%s %s %.2f %.2f" % [r.id, r.kind, (r.position as Vector3).x, (r.position as Vector3).z])
	out.sort()
	return out


## The parked cars' body types and spots.
func _cars(chunk: CityChunk) -> Array:
	var out: Array = []
	for car in chunk.get("_cars"):
		if is_instance_valid(car):
			var p: Vector3 = (car as Node3D).position
			out.append("%d %.1f %.1f" % [int((car as Vehicle).body_type), p.x, p.z])
	return out
