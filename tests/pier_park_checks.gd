extends RefCounted
## The pier park (PierPark, FerrisWheel, PierCoaster, PierCarousel, PierGoer) for
## tests/smoke_test.gd. Loaded at run time, so it compiles after the autoloads. Checks: every ride,
## building, stand, booth and table stands on a deck and clear of every other; the coaster's track
## stays on the platform, clear of the wheel, the carousel and the buildings, its supports clear
## of the crowd's walks; its ride table runs once round (station, lift, drop, brakes, station) at
## sane speeds; the walk graph is connected, on the decks and never through anything; the queues
## and benches are clear; the wheel's bottom gondola clears its platform. In the city: the pier
## chunk builds the park (wheel, coaster with a five-car train on its track, carousel), the deck,
## the track and the wheel are solid, a round sparks off the wheel and the train as metal and
## both keep going, the train follows the clock, the crowd is on the deck and the queues and
## benches are the chunk's crowd-life spots; the far copy has the wheel.

var _t: Node
var _tree: SceneTree


func run(t: Node, city: Node3D) -> void:
	_t = t
	_tree = t.get_tree()
	_layout()
	_coaster()
	_walks()
	await _in_city(city)


func _check(ok: bool, label: String) -> void:
	_t._check(ok, "pier park: " + label)


## On a deck, with `margin` metres of deck all round (the decks join, so a point near a join is
## on two).
func _on_deck(p: Vector2, margin: float = 0.0) -> bool:
	for o: Vector2 in [Vector2.ZERO, Vector2(margin, 0.0), Vector2(-margin, 0.0), Vector2(0.0, margin), Vector2(0.0, -margin)]:
		var any := false
		for r: Rect2 in [PierPark.MAIN, PierPark.NORTH, PierPark.SOUTH]:
			any = any or r.has_point(p + o)
		if not any:
			return false
	return true


## Footprints of everything that stands on the deck (park frame), [name, Rect2].
func _obstacles() -> Array:
	var out: Array = []
	var w := PierPark.WHEEL_AT
	out.append(["wheel", Rect2(w.x - FerrisWheel.LEG_SPREAD_X - 0.6, w.y - FerrisWheel.LEG_FOOT_Z - 0.6,
		(FerrisWheel.LEG_SPREAD_X + 0.6) * 2.0, (FerrisWheel.LEG_FOOT_Z + 0.6) * 2.0)])
	var c := PierPark.CAROUSEL_AT
	var f := PierPark.CAROUSEL_FENCE
	out.append(["carousel", Rect2(c.x - f, c.y - f, f * 2.0, f * 2.0)])
	out.append(["arcade", PierPark.ARCADE])
	out.append(["bumper", PierPark.BUMPER])
	for s: Array in PierPark.STANDS:
		var yaw: float = s[2]
		var half := Vector2(2.2, 1.8) if absf(sin(yaw)) < 0.5 else Vector2(1.8, 2.2)
		out.append([s[3], Rect2(Vector2(s[0], s[1]) - half, half * 2.0)])
	for b: Array in PierPark.BOOTHS:
		out.append([b[1], Rect2(float(b[0]) - 2.15, PierPark.BOOTH_Z - 1.7, 4.3, 3.4)])
	for tb: Vector2 in PierPark.TABLES:
		out.append(["table", Rect2(tb - Vector2(1.0, 1.0), Vector2(2.0, 2.0))])
	return out


func _layout() -> void:
	var obs := _obstacles()
	var off_deck := ""
	var overlap := ""
	for i in obs.size():
		var r: Rect2 = obs[i][1]
		for corner: Vector2 in [r.position, r.end, Vector2(r.position.x, r.end.y), Vector2(r.end.x, r.position.y)]:
			if not _on_deck(corner):
				off_deck += " " + str(obs[i][0])
				break
		for j in range(i + 1, obs.size()):
			if r.intersects(obs[j][1]):
				overlap += " %s/%s" % [obs[i][0], obs[j][0]]
	_check(off_deck == "", "everything stands on a deck%s" % off_deck)
	_check(overlap == "", "nothing stands in anything else%s" % overlap)
	var bottom := FerrisWheel.HUB_H - FerrisWheel.RADIUS - 3.0
	_check(bottom > FerrisWheel.PLATFORM_H + 0.1, "the wheel's lowest gondola clears its platform (%.2f m)" % bottom)


func _coaster() -> void:
	PierCoaster._ensure()
	var obs := _obstacles()
	var off := 0
	var hits := ""
	var low := 0
	var s := 0.0
	while s < PierCoaster.length:
		var p: Vector2 = PierCoaster.plan_at(s)[0]
		if not PierPark.SOUTH.grow(-1.0).has_point(p):
			off += 1
		for o: Array in obs:
			if (o[1] as Rect2).grow(0.6).has_point(p) and not hits.contains(str(o[0])):
				hits += " " + str(o[0])
		if PierCoaster.height_at(s) < 1.2:
			low += 1
		s += 1.0
	_check(off == 0, "the coaster's track stays on the park platform (%d m off)" % off)
	_check(hits == "", "the coaster's track is clear of the rides and buildings%s" % hits)
	_check(low == 0, "the track never sits on the deck")
	var lead := PierCoaster.lead_s(PierCoaster.DWELL * 0.5)
	_check(absf(lead - PierCoaster.STOP_S) < 0.01, "the train stands in the station while it loads")
	_check(PierCoaster.period > 50.0 and PierCoaster.period < 130.0, "a ride takes %.0f s" % PierCoaster.period)
	var top := 0.0
	var stalled := 0
	s = PierCoaster.STOP_S + 6.0
	while s < PierCoaster.STOP_S + PierCoaster.length - 3.0:
		var v := PierCoaster.speed_at(s)
		top = maxf(top, v)
		if v < 0.5:
			stalled += 1
		s += 1.0
	_check(top > 12.0 and top < 26.0 and stalled == 0, "the train runs the circuit without stalling (top %.1f m/s)" % top)
	var on_drop := PierCoaster.lead_s(PierCoaster.clock_at_s(80.0))
	_check(absf(on_drop - 80.0) < 1.0, "the clock puts the train on the drop when asked (s %.1f)" % on_drop)
	var f := PierCoaster.frame(30.0, PierPark.DECK_TOP)
	var up_ok := f.y.y > 0.5 and absf(f.x.y) < 0.6
	_check(up_ok, "the track's frame stands up on the lift")


func _walks() -> void:
	var nodes := PierPark.WALK_NODES
	var bad_nodes := ""
	for i in nodes.size():
		if not _on_deck(nodes[i], 1.0):
			bad_nodes += " %d" % i
	_check(bad_nodes == "", "the walk graph's nodes are on the decks%s" % bad_nodes)
	# Connected.
	var seen := {0: true}
	var queue: Array[int] = [0]
	while not queue.is_empty():
		var n: int = queue.pop_front()
		for m in PierPark.neighbours(n):
			if not seen.has(m):
				seen[m] = true
				queue.append(m)
	_check(seen.size() == nodes.size(), "every walk node can be reached (%d of %d)" % [seen.size(), nodes.size()])
	# No walk through anything: sample every edge against the footprints and the coaster's feet.
	var obs := _obstacles()
	var feet: Array[Vector2] = []
	for sp: Array in PierCoaster.supports(PierPark.DECK_TOP):
		for ft: Vector3 in sp[1]:
			feet.append(Vector2(ft.x, ft.z))
	# Where the track runs low (under 2.6 m) the whole run is a wall.
	var s := 0.0
	while s < PierCoaster.length:
		if PierCoaster.height_at(s) < 2.6:
			feet.append(PierCoaster.plan_at(s)[0])
		s += 1.0
	var through := ""
	for e: Vector2i in PierPark.WALK_EDGES:
		var a: Vector2 = nodes[e.x]
		var b: Vector2 = nodes[e.y]
		for k in 41:
			var q := a.lerp(b, float(k) / 40.0)
			for o: Array in obs:
				if (o[1] as Rect2).grow(0.3).has_point(q):
					through += " %d-%d:%s" % [e.x, e.y, o[0]]
					break
			if not _on_deck(q, 0.4):
				through += " %d-%d:edge" % [e.x, e.y]
		var close := 99.0
		for ft: Vector2 in feet:
			close = minf(close, Geometry2D.get_closest_point_to_segment(ft, a, b).distance_to(ft))
		if close < 0.6:
			through += " %d-%d:coaster" % [e.x, e.y]
	_check(through == "", "no walk passes through a ride, a stand or the coaster's feet%s" % through)
	var blocked := ""
	for q: Array in PierPark.queue_spots():
		var p: Vector2 = q[0]
		if not _on_deck(p, 0.4):
			blocked += " off(%.0f,%.0f)" % [p.x, p.y]
		for o: Array in obs:
			if (o[1] as Rect2).has_point(p):
				blocked += " %s(%.0f,%.0f)" % [o[0], p.x, p.y]
	_check(blocked == "", "the queues stand on the deck, outside what they queue for%s" % blocked)


func _in_city(city: Node3D) -> void:
	var plan: CityPlan = city.plan
	if plan == null or plan.macro == null:
		return
	var anchor := Vector2.ZERO
	for lm in Landmarks.all():
		if lm.id == "pier":
			anchor = lm.anchor
	var player := _tree.get_first_node_in_group("player") as CharacterBody3D
	var ws: Node = _tree.root.get_node("/root/WorldState")
	var home: Vector3 = ws.to_world(player.global_position)
	player.global_position = ws.to_local(Vector3(anchor.x - 30.0, PierPark.DECK_TOP + 1.0, anchor.y))
	player.velocity = Vector3.ZERO
	city.update_streaming(true)
	await _tree.physics_frame
	await _tree.physics_frame
	var chunk: Node3D = city.chunks.get(plan.block_index_at(anchor))
	_check(chunk != null and chunk.built_landmarks.has("pier"), "the pier chunk builds the park")
	if chunk == null:
		return
	var park: Node3D = chunk.get_node_or_null("PierPark")
	var wheel: Node3D = null
	for c in chunk.get_children():
		if c is FerrisWheel:
			wheel = c
	var coaster: Node3D = park.get_node_or_null("Coaster") if park else null
	var carousel: Node3D = park.get_node_or_null("Carousel") if park else null
	_check(park != null and wheel != null and coaster != null and carousel != null, "the park has its wheel, coaster and carousel")
	if park == null or wheel == null or coaster == null:
		return
	var cars: Array = []
	for c in coaster.get_children():
		if c.has_method("take_hit") and c is AnimatableBody3D:
			cars.append(c)
	_check(cars.size() == PierCoaster.CARS, "the coaster runs a %d-car train" % cars.size())
	# The train follows the clock: put it on the drop and look.
	var hold_was := PierCoaster.hold
	PierCoaster.hold = PierCoaster.clock_at_s(80.0)
	# process_frame fires before the nodes' _process: two of them to see the cars placed.
	await _tree.process_frame
	await _tree.process_frame
	if not cars.is_empty():
		var want := PierCoaster.point(80.0, PierPark.DECK_TOP) + Vector3(anchor.x, 0.0, anchor.y)
		var got: Vector3 = ws.to_world((cars[0] as Node3D).global_position)
		_check(got.distance_to(want) < 0.2, "the lead car is on the track where the clock says (%.2f m off)" % got.distance_to(want))
	PierCoaster.hold = PierCoaster.clock_at_s(150.0)
	await _tree.process_frame
	await _tree.process_frame
	if not cars.is_empty():
		var want2 := PierCoaster.point(150.0, PierPark.DECK_TOP) + Vector3(anchor.x, 0.0, anchor.y)
		_check(ws.to_world((cars[0] as Node3D).global_position).distance_to(want2) < 0.2, "and moves on with it")
	PierCoaster.hold = hold_was
	# Solid: the deck, the track and the wheel's platform, by rays from above.
	var space := player.get_world_3d().direct_space_state
	var ray := func(at: Vector2, from_y: float) -> Dictionary:
		var w := Vector3(anchor.x + at.x, from_y, anchor.y + at.y)
		var q := PhysicsRayQueryParameters3D.create(ws.to_local(w), ws.to_local(w - Vector3(0, from_y + 5.0, 0)), 1)
		q.exclude = [player.get_rid()]
		return space.intersect_ray(q)
	var deck: Dictionary = ray.call(Vector2(-200.0, 30.0), 30.0)
	_check(not deck.is_empty() and absf(ws.to_world(deck.position).y - PierPark.DECK_TOP) < 0.05, "the park platform is solid at the deck")
	var lift: Vector2 = PierCoaster.plan_at(50.0)[0]
	var track: Dictionary = ray.call(lift, 40.0)
	_check(not track.is_empty() and track.collider.is_in_group("pier_ride"), "the coaster's lift is solid steel")
	var plat: Dictionary = ray.call(PierPark.WHEEL_AT + Vector2(3.0, 0.0), 40.0)
	_check(not plat.is_empty() and ws.to_world(plat.position).y > PierPark.DECK_TOP + 0.3, "the wheel's platform is solid")
	# Shot: metal, and they keep running.
	var body: Node = wheel.get_node_or_null("WheelBody")
	_check(body != null and WeaponFX.classify(body, Vector3.ZERO, Vector3.UP) == WeaponFX.Surface.METAL, "a round off the wheel sparks as metal")
	if body:
		body.take_hit(-1, 50.0, Vector3.FORWARD)
		_check(is_instance_valid(body) and int(body.get("hits")) == 1 and is_instance_valid(wheel), "the wheel takes the hit and keeps turning")
	if not cars.is_empty():
		_check(WeaponFX.classify(cars[0], Vector3.ZERO, Vector3.UP) == WeaponFX.Surface.METAL, "a round off the train sparks as metal")
		cars[0].take_hit(-1, 50.0, Vector3.FORWARD)
		_check(is_instance_valid(cars[0]), "the train keeps running when shot")
	# The crowd and its spots.
	var goers := 0
	var on_deck := 0
	for g in _tree.get_nodes_in_group("pier_goer"):
		if g.get_parent() == chunk:
			goers += 1
			var y: float = ws.to_world((g as Node3D).global_position).y
			if absf(y - PierPark.DECK_TOP) < 0.6:
				on_deck += 1
	_check(goers > 0 and on_deck == goers, "people on the pier's deck (%d of %d)" % [on_deck, goers])
	var spots: Array = chunk.get_meta("vendor_queue", [])
	var seats: Array = chunk.get_meta("life_seats", [])
	_check(spots.size() >= PierPark.queue_spots().size() and seats.size() >= PierPark.benches().size(), "the queues and benches are the chunk's crowd-life spots")
	var route := PierPark.route(anchor, anchor + PierPark.WALK_NODES[0], anchor + PierPark.WALK_NODES[19])
	_check(route.size() >= 5, "a walk from the pier's foot to the wheel goes by the graph (%d stops)" % route.size())
	var far: Node = city.get_node_or_null("FarLandmark_pier")
	var far_wheel := false
	if far:
		for c in far.get_children():
			far_wheel = far_wheel or c is FerrisWheel
	_check(far_wheel, "the far pier carries the wheel (the skyline's silhouette and lights)")
	player.global_position = ws.to_local(home)
	player.velocity = Vector3.ZERO
	city.update_streaming(true)
