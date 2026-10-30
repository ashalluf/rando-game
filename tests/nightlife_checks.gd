extends RefCounted
## Night life (NightLife, NightLifeKit, NightGoer, NightPickups, SkyBeam), for tests/smoke_test.gd.
## Loaded at run time, not named there, so it compiles after the autoloads.
##
## Checks the hours (no line by day, a club's longest round midnight, a bar's shorter), the kit's
## meshes (one surface each on the night-life shader, inside a triangle budget), then builds FULL
## chunks round downtown at 22:30 (every candidate shop a venue) until one has a venue, and checks:
## every venue stands at an open restaurant's or a tower lobby's door, its line along the wall on
## the pavement between the wall and the rope, inside the block and clear of its corners, venues
## apart; the entrance is a batch on the shader with its sign and light; the line is people
## (NightGoer QUEUE) standing in their places with a bouncer at the door; the door lets the head
## in and the line shuffles up; who went in comes back out to the tail; a taxi called to the door
## double-parks on its hazards, somebody from inside walks out and gets in, and it drives on; the
## same block by day has no line and no rope; and built with night life off the block is the same
## (buildings, props, parked cars). Then a Broadway palace's premiere (forced): the carpet, fans
## behind the barriers, four sweeping searchlights; and its LOD chunk keeps the beams alone.
## Everything it needs is staged here (the hour, the odds, the player over the block, the traffic
## held), and put back after.

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
	NightLife.force_hour = 22.5
	NightLife.force_odds = 1.0
	NightLife.force_night = 3
	var found := _find(city, plan)
	_t._check(found.x != 99999, "nightlife: a venue stands round downtown at 22:30 (block %s)" % str(found))
	if found.x != 99999:
		await _chunk(city, plan, found)
		_same_without(city, found)
	await _premiere(city, plan)
	NightLife.force_hour = -1.0
	NightLife.force_odds = -1.0
	NightLife.force_night = -1
	NightLife.force_events = OS.get_environment("NIGHTLIFE_PREMIERE") == "1"


func _hours() -> void:
	var club := NightLife.Kind.CLUB
	var bar := NightLife.Kind.BAR
	var k := 12345
	_t._check(NightLife.queue_size(club, 14.0, k) == 0 and NightLife.queue_size(bar, 13.0, k) == 0 and NightLife.queue_size(club, 4.0, k) == 0,
		"nightlife: no line by day or at dawn")
	_t._check(NightLife.queue_size(club, 24.0, k) > NightLife.queue_size(club, 21.8, k) and NightLife.queue_size(club, 0.5, k) >= 6,
		"nightlife: a club's line is longest round midnight (%d at 00:00, %d at 21:48)" % [NightLife.queue_size(club, 24.0, k), NightLife.queue_size(club, 21.8, k)])
	_t._check(NightLife.queue_size(bar, 23.0, k) < NightLife.queue_size(club, 23.0, k) and NightLife.queue_size(bar, 23.0, k) > 0,
		"nightlife: a bar's line is shorter than a club's")
	_t._check(NightLife.open_at(club, 1.0) and not NightLife.open_at(club, 12.0) and NightLife.open_at(bar, 19.0) and not NightLife.open_at(bar, 3.5),
		"nightlife: clubs open late into the night, bars from the evening")
	_t._check(NightLife.night_hour(1.0) == 25.0 and NightLife.night_hour(22.0) == 22.0, "nightlife: a night is one clock (01:00 is 25)")


func _meshes() -> void:
	var meshes: Array = NightLifeKit.warm()
	meshes.append(NightLifeKit.rope_line(5, 1, 0))
	meshes.append(NightLifeKit.premiere(4.0, NightLife.CARPET_W))
	var ok := true
	var worst := 0
	for m: Mesh in meshes:
		var tris := 0
		for s in m.get_surface_count():
			tris += (m.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
		worst = maxi(worst, tris)
		ok = ok and m.get_surface_count() == 1 and m.surface_get_material(0) == NightLifeKit.material() and tris > 50
	_t._check(ok, "nightlife: every kit mesh is one surface on the night-life shader")
	_t._check(worst < 12000, "nightlife: a kit mesh stays under 12k triangles (worst %d)" % worst)


## The first block round downtown whose FULL chunk builds a venue.
func _find(city: Node3D, plan: CityPlan) -> Vector2i:
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
				var chunk: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
				if not NightLife.wanted_block(chunk, b):
					chunk.get_parent().remove_child(chunk)
					chunk.free()
					continue
				chunk.build()
				var has := not (chunk.get_meta("nightlife", []) as Array).is_empty()
				chunk.get_parent().remove_child(chunk)
				chunk.free()
				if has:
					return k
				tried += 1
				if tried > 14:
					return Vector2i(99999, 99999)
	return Vector2i(99999, 99999)


func _goers(chunk: Node, role: int) -> Array:
	var out: Array = []
	for n in chunk.get_children():
		if n is NightGoer and (n as NightGoer).role == role:
			out.append(n)
	return out


func _chunk(city: Node3D, plan: CityPlan, k: Vector2i) -> void:
	var chunk: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
	chunk.build()
	var block := plan.block(k.x, k.y)
	var rect: Rect2 = block.rect
	var venues: Array = chunk.get_meta("nightlife", [])
	# Where the venues stand.
	var placed := true
	var apart := true
	for i in venues.size():
		var v: Dictionary = venues[i]
		var door: Vector2 = v.door
		var out: Vector2 = v.out
		var along: Vector2 = v.along
		placed = placed and rect.grow(0.5).has_point(door) and float(v.kerb) >= NightLife.MIN_PAVE and float(v.kerb) <= NightLife.FRONT_REACH
		placed = placed and absf(along.dot(out)) < 0.01 and float(v.run) >= NightLife.MIN_RUN
		for s in NightLife.line_room(v):
			var spot: Vector2 = NightLife.slot_spot(v, s)[0]
			var o := (spot - door).dot(out)
			placed = placed and rect.has_point(spot) and o > 0.2 and o < NightLifeKit.ROPE_OUT - 0.3
		for j in range(i + 1, venues.size()):
			apart = apart and door.distance_to((venues[j] as Dictionary).door) >= NightLife.MIN_APART
	_t._check(placed, "nightlife: every venue's line stands on the pavement between the wall and the rope, inside its block")
	_t._check(apart and venues.size() <= NightLife.MAX_PER_BLOCK, "nightlife: venues keep apart (%d on the block)" % venues.size())
	var keys := _batch_keys(chunk)
	var entrances := 0
	var ropes := 0
	for key: String in keys:
		if key.begins_with("nl_club_") or key == "nl_bar":
			entrances += 1
		if key.begins_with("nl_rope_"):
			ropes += 1
	_t._check(entrances >= 1 and ropes >= 1, "nightlife: the entrances and the ropes are batches (%d, %d)" % [entrances, ropes])
	var holder := chunk.get_node_or_null("NightLife")
	var signs := 0
	if holder:
		for n in holder.get_children():
			if String(n.name).contains("NightSign"):
				signs += 1
	_t._check(signs >= 1, "nightlife: each venue carries its lit name (%d signs)" % signs)
	# The people.
	var queue := _goers(chunk, NightGoer.Role.QUEUE)
	var bouncers := _goers(chunk, NightGoer.Role.BOUNCER)
	_t._check(queue.size() >= 3 and bouncers.size() >= 1, "nightlife: a line of people and a bouncer at the door (%d, %d)" % [queue.size(), bouncers.size()])
	if queue.is_empty():
		_free(chunk)
		return
	var v: Dictionary = (queue[0] as NightGoer).venue
	var members: Array = v.members
	var in_place := true
	for i in members.size():
		var g := members[i] as NightGoer
		var spot: Vector2 = NightLife.slot_spot(v, i)[0]
		in_place = in_place and g.home.distance_to(spot) < 0.05 and Vector2(g.position.x, g.position.z).distance_to(spot) < 0.1
	_t._check(in_place, "nightlife: the line stands in its places, in order")
	# Stage: the player over the venue (everyone within the life range), the traffic held.
	var player := _tree.get_first_node_in_group("player") as Player
	if player.is_driving():
		player.exit_vehicle()
	var home: Vector3 = _ws.to_world(player.global_position)
	player.set_physics_process(false)
	var door: Vector2 = v.door
	player.global_position = _ws.to_local(Vector3(door.x, chunk.ground_y(door.x, door.y) + 14.0, door.y))
	player.velocity = Vector3.ZERO
	var traffic := city.get_node("Traffic") as TrafficManager
	var was_staged := traffic.staged
	traffic.staged = true
	for c in traffic.cars.duplicate():
		if is_instance_valid(c):
			traffic._retire(c)
	traffic.cars.clear()
	# The door lets the head in; the line shuffles up.
	var head := members[0] as NightGoer
	var second := members[1] as NightGoer if members.size() > 1 else null
	v.admit_ms = 0
	v.open = true
	var went := false
	for f in 600:
		await _tree.physics_frame
		if head.state == NightGoer.State.INSIDE:
			went = true
			break
	_t._check(went and not head.visible and head.collision_layer == 0 and (v.inside as Array).has(head),
		"nightlife: the door lets the head of the line in (out of sight inside)")
	_t._check(second == null or ((v.members as Array).find(second) == 0 and second._act_spot.distance_to(NightLife.slot_spot(v, 0)[0]) < 0.05),
		"nightlife: the line shuffles up a place")
	# A taxi called to the door double-parks on its hazards, the one inside comes out and gets in.
	v.admit_ms = Pedestrian._life_now_ms() + 600000
	var road: Array = v.road
	var axis := int(road[0])
	var index := int(road[1])
	var dir := int(road[2])
	var lanes := TrafficAI.lanes_of(plan, axis, index)
	var car := traffic.place_car(axis, index, dir, lanes - 1, float(road[3]) - float(dir) * 42.0, 7.0, false)
	_t._check(NightPickups.pick_car(traffic, v) == null, "nightlife: a placed (staged) car is never taken for a pickup on its own")
	NightPickups.call_car(car, v, 30.0)
	var stood := false
	var walked := false
	var boarded := false
	var left := false
	for f in 1500:
		await _tree.physics_frame
		NightPickups.tick(v)
		if not is_instance_valid(car):
			break
		var tt: Dictionary = car.traffic
		if float(tt.get("v", 1.0)) < 0.3 and int(tt.get("sig", 0)) == 2 and tt.has("dp_at"):
			stood = true
		if head.state == NightGoer.State.TO_CAR and head.visible:
			walked = true
		if head.state == NightGoer.State.IN_CAR:
			boarded = true
		if boarded and not tt.has("dp_at"):
			left = true
			break
	_t._check(stood, "nightlife: the called car double-parks at the door on its hazards")
	_t._check(walked and boarded, "nightlife: somebody comes out of the door and gets into it (walked %s, in %s)" % [str(walked), str(boarded)])
	_t._check(left, "nightlife: with the fare in, the car drives on")
	if is_instance_valid(car):
		var stop: float = float(road[3])
		var at: float = float(car.traffic.get("along", stop))
		_t._check(absf(at - stop) < 9.0 or float(car.traffic.get("v", 0.0)) > 0.5, "nightlife: it stood at the door (%.1f m from it)" % absf(at - stop))
	# Back round the corner to the tail after a while.
	if head.state == NightGoer.State.INSIDE:
		head._until = 0.0
		for f in 30:
			await _tree.physics_frame
		_t._check(head.visible and head.state == NightGoer.State.LINE and (v.members as Array).back() == head,
			"nightlife: who went in comes back out to the line's tail")
	else:
		_t._check(false, "nightlife: the fare is back inside once the car has gone (state %d)" % head.state)
	for c in traffic.cars.duplicate():
		if is_instance_valid(c):
			traffic._retire(c)
	traffic.cars.clear()
	traffic.staged = was_staged
	player.global_position = _ws.to_local(home)
	player.set_physics_process(true)
	_free(chunk)
	# By day: no line, no rope, the entrance dark.
	NightLife.force_hour = 13.0
	var day: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
	day.build()
	var day_ropes := 0
	for key: String in _batch_keys(day):
		if key.begins_with("nl_rope_"):
			day_ropes += 1
	var lit := false
	for dv: Dictionary in day.get_meta("nightlife", []):
		lit = lit or bool(dv.open) and int(dv.kind) == NightLife.Kind.CLUB
	_t._check(_goers(day, NightGoer.Role.QUEUE).is_empty() and day_ropes == 0 and not lit, "nightlife: by day no line, no rope, the clubs closed")
	_free(day)
	NightLife.force_hour = 22.5


## Built with night life off, the block is the same: its buildings, its props, its parked cars.
func _same_without(city: Node3D, k: Vector2i) -> void:
	var on: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
	on.build()
	var a := _signature(on)
	_free(on)
	NightLife.enabled = false
	var off: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
	off.build()
	var b := _signature(off)
	_free(off)
	NightLife.enabled = true
	_t._check(a == b, "nightlife: the block builds the same with it off (buildings, props, parked cars: %s vs %s)" % [str(a), str(b)])


func _signature(chunk: CityChunk) -> Array:
	var buildings := 0
	for n in chunk.get_children():
		if n is Building:
			buildings += 1
	var ids: Array = []
	for r: Dictionary in chunk.prop_records:
		ids.append(String(r.get("id", "")))
	return [buildings, chunk.prop_records.size(), hash(ids), chunk._cars.size()]


## A Broadway palace's premiere, forced: the carpet, the fans, four searchlights that sweep; its
## LOD chunk keeps the beams alone.
func _premiere(city: Node3D, plan: CityPlan) -> void:
	var palaces := Broadway.palaces(plan)
	_t._check(not palaces.is_empty(), "nightlife: Broadway has its palaces")
	if palaces.is_empty():
		return
	NightLife.force_events = true
	var p: Dictionary = palaces[0]
	var k: Vector2i = p.block
	var chunk: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
	chunk.build()
	var carpet := false
	for key: String in _batch_keys(chunk):
		carpet = carpet or key.begins_with("nl_premiere_")
	var fans := _goers(chunk, NightGoer.Role.FAN)
	var beams := _beams(chunk)
	var palaces_here := 1
	_t._check(carpet and fans.size() >= 4, "nightlife: a premiere's red carpet and fans behind the barriers (%d fans)" % fans.size())
	_t._check(beams.size() == 4 * palaces_here, "nightlife: four searchlights at the premiere's kerb (one premiere a block) (%d)" % beams.size())
	if not beams.is_empty():
		var b := beams[0] as SkyBeam
		b.pose(10.0)
		var d0 := b.direction()
		b.pose(13.5)
		var d1 := b.direction()
		var up := rad_to_deg(asin(clampf(d1.y, -1.0, 1.0)))
		_t._check(d0.distance_to(d1) > 0.02 and up >= b.elevation.x - 0.5 and up <= b.elevation.y + 0.5,
			"nightlife: a searchlight sweeps the sky (%.0f degrees up)" % up)
	_free(chunk)
	var lod: CityChunk = city._new_chunk(k, CityChunk.Level.LOD)
	lod.build()
	var lod_beams := _beams(lod)
	var headless := true
	for b in lod_beams:
		headless = headless and not (b as SkyBeam).with_head
	_t._check(lod_beams.size() == 4 * palaces_here and headless and _goers(lod, NightGoer.Role.FAN).is_empty(),
		"nightlife: from an LOD chunk only the beams (%d)" % lod_beams.size())
	_free(lod)
	NightLife.force_events = false


## The keys of the chunk's built batches (its Batch_<key> nodes).
func _batch_keys(chunk: Node) -> Array:
	var out: Array = []
	for n in chunk.get_children():
		if n is MultiMeshInstance3D and String(n.name).begins_with("Batch_"):
			out.append(String(n.name).trim_prefix("Batch_"))
	return out


func _beams(chunk: Node) -> Array:
	var out: Array = []
	var holder := chunk.get_node_or_null("NightLife")
	if holder:
		for n in holder.get_children():
			if n is SkyBeam:
				out.append(n)
	return out


func _free(chunk: Node) -> void:
	if chunk.get_parent():
		chunk.get_parent().remove_child(chunk)
	chunk.free()
