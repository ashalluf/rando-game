extends RefCounted
## Outdoor dining parklets (Parklets, ParkletKit, ParkletDiner), for tests/smoke_test.gd. Loaded
## at run time, not named there, so it compiles after the autoloads.
##
## Checks the hours (nobody at 04:00, dinner busier than the afternoon), the kit's meshes (one
## surface each on the parklet shader, inside a triangle budget), then builds FULL chunks round
## downtown at 13:00 until one has a parklet and checks: every parklet stands in the parking lane
## in front of a cafe or restaurant on the block's +x / +z face, clear of the corners and of each
## other; the deck is a batch on the parklet shader with its own collision; no parked car stands
## on its stretch; a diner sits in a chair (seated clip, hips at the chair, out of the deck's
## collision) and a waiter stands at a table; a bistro set tips over and stays gone; the same block
## at 21:00 furls its umbrellas; and built with parklets off it is the same block (buildings,
## props, trash cans), its parked cars a superset of the ones built with them on.

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	_hours()
	_meshes()
	var plan: CityPlan = city.plan
	var found := _find(city, plan)
	_t._check(found.x != 99999, "a parklet stands round downtown at 13:00 (block %s)" % str(found))
	if found.x != 99999:
		_chunk(city, plan, found)
	Parklets.force_hour = -1.0


func _hours() -> void:
	var cafe := Building.ShopRoom.CAFE
	var rest := Building.ShopRoom.RESTAURANT
	_t._check(Parklets.busy(cafe, 4.0) == 0.0 and Parklets.busy(rest, 4.0) == 0.0 and Parklets.busy(cafe, 9.0) > 0.3
		and Parklets.busy(rest, 20.0) > Parklets.busy(rest, 16.0) and Parklets.busy(rest, 9.0) == 0.0,
		"parklets fill by the hour (nobody at 04:00, cafes at breakfast, restaurants busiest at dinner)")
	_t._check(Parklets.evening(21.0) and Parklets.evening(2.0) and not Parklets.evening(13.0), "the parklets' evening runs 19:00 to 06:00")


func _meshes() -> void:
	var meshes: Array[Mesh] = [ParkletKit.umbrella(true), ParkletKit.umbrella(false)]
	for l: float in ParkletKit.LENGTHS:
		meshes.append(ParkletKit.deck(l))
	for k in 8:
		meshes.append(ParkletKit.bistro_set(k & 4 != 0, k & 2 != 0, k & 1 != 0))
	var ok := true
	var worst := 0
	for m in meshes:
		var tris := 0
		for s in m.get_surface_count():
			tris += (m.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
		worst = maxi(worst, tris)
		ok = ok and m.get_surface_count() == 1 and m.surface_get_material(0) == ParkletKit.material() and tris > 100
	_t._check(ok, "every parklet mesh is one surface on the parklet shader")
	_t._check(worst < 16000, "a parklet mesh stays under 16k triangles (worst %d)" % worst)


## The first block round downtown whose FULL chunk builds a parklet at 13:00.
func _find(city: Node3D, plan: CityPlan) -> Vector2i:
	Parklets.force_hour = 13.0
	var centre := plan.block_index_at(plan.macro.downtown_center if plan.macro else Vector2.ZERO)
	var tried := 0
	for r in 4:
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dz)) != r:
					continue
				var k := centre + Vector2i(dx, dz)
				var b := plan.block(k.x, k.y)
				if plan.zone_at((b.rect as Rect2).get_center()) != MacroMap.Zone.CITY:
					continue
				if not Parklets.wanted_block(b):
					continue
				var chunk: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
				chunk.build()
				var has := not (chunk.get_meta("parklets", []) as Array).is_empty()
				chunk.get_parent().remove_child(chunk)
				chunk.free()
				if has:
					return k
				tried += 1
				if tried > 14:
					return Vector2i(99999, 99999)
	return Vector2i(99999, 99999)


func _chunk(city: Node3D, plan: CityPlan, k: Vector2i) -> void:
	Parklets.force_hour = 13.0
	var chunk: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
	chunk.build()
	var rect: Rect2 = plan.block(k.x, k.y).rect
	var parklets: Array = chunk.get_meta("parklets", [])
	# In the lane, at a cafe or restaurant.
	var placed := true
	for pk: Dictionary in parklets:
		var c: Vector2 = pk.c
		var room := int(pk.room)
		var on_kerb := absf(c.y - rect.end.y) < 0.01 if int(pk.face) == 1 else absf(c.x - rect.end.x) < 0.01
		var along := c.x - rect.position.x if int(pk.face) == 1 else c.y - rect.position.y
		var span := rect.size.x if int(pk.face) == 1 else rect.size.y
		placed = placed and on_kerb and (room == Building.ShopRoom.CAFE or room == Building.ShopRoom.RESTAURANT) \
			and along - float(pk.length) * 0.5 >= Parklets.CORNER_KEEP - 0.01 and span - along - float(pk.length) * 0.5 >= Parklets.CORNER_KEEP - 0.01
		for other: Dictionary in parklets:
			if other != pk and (other.c as Vector2).distance_to(c) < (float(other.length) + float(pk.length)) * 0.5:
				placed = false
	_t._check(not parklets.is_empty() and placed, "parklets stand on the kerb line before cafes and restaurants, clear of the corners and each other (%d)" % parklets.size())
	var deck: MultiMeshInstance3D = null
	for c in chunk.get_children():
		if c is MultiMeshInstance3D and String(c.name).begins_with("Batch_" + Parklets.K_DECK):
			deck = c
	_t._check(deck != null and deck.multimesh.mesh.surface_get_material(0) == ParkletKit.material(), "the decks are a batch on the parklet shader")
	var body := chunk.get_node_or_null("Parklets") as StaticBody3D
	_t._check(body != null and body.get_children().filter(func(n: Node) -> bool: return n is CollisionShape3D).size() == 4 * parklets.size() and body.collision_layer == 1 and body.collision_mask == 0,
		"each deck has its collision (deck, planters, two screens) on the world layer, mask 0")
	var blocked := 0
	for car in chunk.get("_cars"):
		if is_instance_valid(car):
			var p: Vector3 = WorldState.to_world((car as Node3D).position) if (car as Node).get_parent() != chunk else (car as Node3D).position
			if Parklets.blocks_parking(chunk, p):
				blocked += 1
	_t._check(blocked == 0, "no parked car stands on a parklet's stretch of kerb (%d)" % blocked)
	# A diner and a waiter (made here: the city's crowd cap may already be spent by the streamed city).
	var people: Array = chunk.get_meta("parklet_people", [])
	var diner: Dictionary = {}
	var waiter: Dictionary = {}
	for s: Dictionary in people:
		if String(s.kind) == "diner" and diner.is_empty():
			diner = s
		if String(s.kind) == "waiter" and waiter.is_empty():
			waiter = s
	_t._check(not diner.is_empty(), "somebody is dining at a parklet at 13:00 (%d people planned)" % people.size())
	if not diner.is_empty():
		var ped := ParkletDiner.new()
		ped.setup_diner(diner.rect, int(diner.seed), diner.seat, float(diner.yaw), diner.mate)
		var at: Vector2 = diner.seat
		ped.position = Vector3(at.x, chunk.ground_y(at.x, at.y) + 0.1, at.y)
		chunk.add_child(ped)
		var hips := Vector2(ped.position.x, ped.position.z)
		var face := Vector2(-sin(float(diner.yaw)), -cos(float(diner.yaw)))
		_t._check(ped._act == CrowdLife.Act.SIT and ped._life_clip == CrowdLife.SIT and ped.collision_mask == 0
			and (hips - at).dot(face) > 0.0 and hips.distance_to(at) < 0.8,
			"a diner sits in a chair on the seated clip, out of the deck's collision")
		ped.queue_free()
	if not waiter.is_empty():
		var w := ParkletDiner.new()
		w.setup_waiter(waiter.rect, int(waiter.seed), waiter.door, waiter.tables, waiter.out)
		chunk.add_child(w)
		var here := Vector2(w.position.x, w.position.z)
		var near_table := false
		for tb: Vector2 in waiter.tables:
			near_table = near_table or here.distance_to(tb) < 1.2
		_t._check(w._act == CrowdLife.Act.STAND and near_table, "a waiter starts at a table, taking an order")
		w.queue_free()
	# A set tips over and stays gone.
	var item: EncampmentItem = null
	for c in chunk.get_children():
		if c is EncampmentItem and String(c.name).begins_with("Parklet_"):
			item = c
	_t._check(item != null, "the bistro sets are knockable bodies")
	var sig := _signature(chunk)
	var cars := _cars(chunk)
	if item != null:
		var id := item.item_id
		item.knock(Vector3(3.0, 2.0, 0.0))
		_t._check(WorldState.is_destroyed(chunk.key, id), "a knocked bistro set is remembered as gone")
	chunk.get_parent().remove_child(chunk)
	chunk.free()
	# At night the umbrellas are furled.
	Parklets.force_hour = 21.0
	var night: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
	night.build()
	var open_n := night.get_node_or_null("Batch_" + Parklets.K_UMBRELLA + "1")
	_t._check(open_n == null, "no umbrella stands open at 21:00")
	night.get_parent().remove_child(night)
	night.free()
	# Off, the same block.
	Parklets.enabled = false
	var bare: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
	bare.build()
	Parklets.enabled = true
	var bare_cars := _cars(bare)
	var superset := true
	for c: String in cars:
		superset = superset and bare_cars.has(c)
	_t._check(_signature(bare) == sig and superset and bare_cars.size() >= cars.size(),
		"the parklets roll nothing from the block: built without them it is the same block (%d cars, %d without)" % [cars.size(), bare_cars.size()])
	bare.get_parent().remove_child(bare)
	bare.free()
	Parklets.force_hour = -1.0


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
