extends RefCounted
## The crowd in the rain (RainCrowd, RainGear) for tests/smoke_test.gd: who carries what is rolled
## from the seed; dry, nobody holds anything and the pace is the walk's; in the rain the umbrella
## carriers open theirs over their heads, held up in the hand, the hooded pull the hood up over
## the hair, everyone walks faster; a walker with no cover finds the bus shelter's bench, or a
## doorway; under a downpour some go indoors (hidden, no collision) and come back out once it
## eases; when it stops the umbrellas fold; nobody out of the camera's range takes part; the
## meshes stay inside their budgets. Loaded at run time like the other crowd checks.

var _t: Node
var _tree: SceneTree


func run(t: Node, city: Node3D) -> void:
	_t = t
	_tree = t.get_tree()
	_check(RainCrowd.enabled, "the rain crowd is on (RAIN_CROWD=0 is the A/B)")
	# Crowd life is a static switch other code can leave off (a golfer once did); it is what
	# this checks, so it is on for the checks and put back after.
	var life_was := Pedestrian.life_enabled
	Pedestrian.life_enabled = true
	_check_meshes()
	var chunk: Node3D = city.chunks.get(Vector2i(0, 0))
	_check(chunk != null, "the spawn block's chunk is loaded for the rain crowd checks")
	if chunk == null:
		Pedestrian.life_enabled = life_was
		return
	await _check_behaviour(city, chunk)
	RainCrowd.forced = -1.0
	Pedestrian.life_enabled = life_was


func _check_meshes() -> void:
	var open := RainGear.umbrella(RainGear.Kind.STICK, RainGear.OPEN_STEPS - 1)
	var shut := RainGear.umbrella(RainGear.Kind.STICK, 0)
	var tris := open.surface_get_array_index_len(0) / 3
	_check(tris > 800 and tris < 2600, "an open umbrella is a real model inside its budget (%d triangles)" % tris)
	var oa := open.get_aabb()
	var sa := shut.get_aabb()
	_check(oa.size.x > 0.9 and oa.size.x < 1.25, "an open stick umbrella spans a metre (%.2f m)" % oa.size.x)
	_check(sa.size.x < 0.2, "a furled one is no wider than its folds (%.2f m)" % sa.size.x)
	_check(oa.end.y > RainGear.apex_height(RainGear.Kind.STICK) - 0.05 and oa.position.y < 0.0,
		"the canopy is up the shaft and the handle below the grip (%.2f .. %.2f m)" % [oa.position.y, oa.end.y])
	var hood := RainGear.hood(Pedestrian.MODELS[0])
	var htris := hood.surface_get_array_index_len(0) / 3
	_check(htris > 500 and htris < 2200, "a hood is fitted inside its budget (%d triangles)" % htris)
	var h := CrowdHat.head_for(Pedestrian.MODELS[0])
	var ha := hood.get_aabb()
	_check(ha.end.y > h.top + 0.005 and ha.end.y < h.top + 0.08, "the hood sits over the crown (top %.3f, crown %.3f)" % [ha.end.y, h.top])
	_check(RainGear.canopy_material(3) == RainGear.canopy_material(3 + RainGear.CANOPY_COLORS.size()),
		"umbrella colourways share their materials")


func _check_behaviour(city: Node3D, chunk: Node3D) -> void:
	var plan: CityPlan = city.plan
	var rect: Rect2 = plan.block(0, 0).rect
	var z := rect.position.y + 2.0
	var x0 := rect.position.x + 8.0
	RainCrowd.forced = 0.0
	var peds: Array[Pedestrian] = []
	for i in 6:
		var p := Pedestrian.new()
		p.setup(rect, plan.sidewalk_width, 9100 + i * 37)
		p.pause_chance = 0.0
		p.cross_chance = 0.0
		p.jogger_share = Vector2.ZERO
		p.dog_share = Vector2.ZERO
		p.life_spawn_chance = 0.0
		p.life_chance = 0.0
		p.life_range = 100000.0
		var at := Vector2(x0 + float(i) * 2.0, z)
		p.position = Vector3(at.x, chunk.ground_y(at.x, at.y) + 0.1, at.y)
		chunk.add_child(p)
		peds.append(p)
	await _ticks(40)
	var with_rain := peds.filter(func(p): return (p as Pedestrian).rain != null)
	_check(with_rain.size() == peds.size(), "every plain walker near the player has a rain state (%d of %d)" % [with_rain.size(), peds.size()])
	if with_rain.size() < 3:
		_free(peds)
		return
	# Same seed, same umbrella.
	var twin := Pedestrian.new()
	twin.setup(rect, plan.sidewalk_width, 9100)
	twin.position = peds[0].position
	chunk.add_child(twin)
	await _ticks(2)
	_check(twin.rain != null and twin.rain.gear == peds[0].rain.gear and twin.rain.pick == peds[0].rain.pick
		and twin.rain.react == peds[0].rain.react, "who carries what in the rain is rolled from the seed")
	twin.free()
	# Give the test its cast: an umbrella, a hood, nothing.
	var brolly := peds[0]
	var hooded := peds[1]
	var bare := peds[2]
	brolly.rain.gear = RainCrowd.Gear.UMBRELLA
	peds[5].rain.gear = RainCrowd.Gear.UMBRELLA
	hooded.rain.gear = RainCrowd.Gear.HOOD
	bare.rain.gear = RainCrowd.Gear.NONE
	bare.rain.leave_roll = 1.0
	for p in peds:
		p.rain.react = 0.2
	# Dry.
	await _ticks(10)
	_check(brolly.rain._umbrella == null or not brolly.rain._umbrella.visible, "dry, nobody holds an umbrella")
	_check(is_equal_approx(bare.rain.pace(false), 1.0), "dry, everyone walks at their own pace")
	# Rain.
	RainCrowd.forced = 0.7
	await _ticks(70)
	var u := brolly.rain._umbrella
	_check(u != null and u.visible and brolly.rain.open >= 1.0, "in the rain the umbrella goes up (open %.2f)" % brolly.rain.open)
	if u != null:
		var sk := brolly._head_skel
		var head := (sk.global_transform * sk.get_bone_global_pose(sk.find_bone("Head"))).origin
		var canopy_top := u.global_transform * Vector3(0.0, RainGear.apex_height(brolly.rain.kind), 0.0)
		_check(canopy_top.y > head.y + 0.2 and Vector2(canopy_top.x - head.x, canopy_top.z - head.z).length() < 0.35,
			"the canopy is held over the head (%.2f m up, %.2f m off)" % [canopy_top.y - head.y, Vector2(canopy_top.x - head.x, canopy_top.z - head.z).length()])
		var hand := (sk.global_transform * sk.get_bone_global_pose(sk.find_bone(brolly.rain.hand))).origin
		_check(hand.distance_to(u.global_position) < 0.2, "the umbrella is in the hand (%.2f m)" % hand.distance_to(u.global_position))
	_check(hooded.rain._hood_mi != null and hooded.rain._hood_mi.visible and hooded.rain.hood >= 1.0, "the hooded pull their hoods up")
	var hair_shown := 0
	for mi in hooded._meshes:
		if is_instance_valid(mi) and Pedestrian.is_hair(mi) and mi.visible:
			hair_shown += 1
	_check(hair_shown == 0, "the hair is under the hood (%d cards shown)" % hair_shown)
	_check(bare.rain.pace(false) > 1.25 and brolly.rain.pace(false) > 1.0, "everyone hurries in the rain (%.2f bare, %.2f under an umbrella)" % [bare.rain.pace(false), brolly.rain.pace(false)])
	_check(bare._posture_pitch < -0.3, "with nothing over the head, the head goes down")
	# Knocked down with it open: the umbrella is let go and tumbles off as debris.
	var dropper := peds[5]
	if dropper.rain._umbrella != null and dropper.rain._umbrella.visible:
		var before := _tree.get_nodes_in_group(PhysicsBudget.DEBRIS_GROUP).filter(func(n): return n.name.begins_with("DroppedUmbrella")).size()
		dropper.knock(Vector3(0.0, 2.0, 3.0))
		await _ticks(3)
		var after := _tree.get_nodes_in_group(PhysicsBudget.DEBRIS_GROUP).filter(func(n): return n.name.begins_with("DroppedUmbrella")).size()
		_check(after > before, "a walker knocked down lets go of the umbrella (%d dropped)" % (after - before))
	# Shelter: a bus stop's bench nearby is taken first.
	var stop := Vector3(x0 + 4.0, chunk.ground_y(x0 + 4.0, z + 1.5), z + 1.5)
	CrowdLife.add_seat(chunk, stop, 0.0, {"kind": "bus_stop", "dead": false})
	RainCrowd.forced = 0.95
	bare._end_act(true)
	_check(bare.rain._plan_bus_shelter(false) and bare._act == CrowdLife.Act.SIT and RainCrowd._bus_seat(bare._seat),
		"a walker with nothing over the head heads for the bus shelter's bench")
	await _ticks(160)
	_check(bare._act == CrowdLife.Act.SIT and bare.rain.sheltering, "and sits it out there")
	# Under a downpour some go in (hidden, no collision) and come back out when it eases.
	var goer := peds[3]
	goer.rain.gear = RainCrowd.Gear.NONE
	goer.rain.leave_roll = 0.0
	goer._end_act(true)
	goer.rain.settle_now()
	_check(goer.rain.inside and not goer.visible and goer.collision_layer == 0, "under a downpour some walkers go indoors")
	RainCrowd.forced = 0.0
	await _ticks(90)
	_check(not goer.rain.inside and goer.visible and goer.collision_layer != 0, "they come back out when it eases")
	_check(not bare.rain.sheltering and bare._act != CrowdLife.Act.SIT, "the sheltering step back out")
	_check(brolly.rain.open <= 0.0 and brolly.rain._umbrella.visible, "the umbrella folds and is carried furled")
	_check(hooded.rain.hood <= 0.0 and not hooded.rain._hood_mi.visible, "the hood goes down")
	hair_shown = 0
	for mi in hooded._meshes:
		if is_instance_valid(mi) and Pedestrian.is_hair(mi) and mi.visible:
			hair_shown += 1
	_check(hair_shown > 0 or hooded._draw_tier >= 2 or hooded.rain._hair_hidden.is_empty(), "the hair comes back out")
	_check(is_equal_approx(bare.rain.pace(false), 1.0) and not bare.rain._pitch_set and bare._posture_pitch == bare.rain._pitch0,
		"dry again, the walk and the head are their own")
	# Out of the camera's range nobody takes part.
	var far := Pedestrian.new()
	far.setup(rect, plan.sidewalk_width, 9400)
	far.position = peds[4].position
	far.life_range = 0.5
	chunk.add_child(far)
	RainCrowd.forced = 0.9
	await _ticks(40)
	_check(far.rain == null or ((far.rain._umbrella == null or not far.rain._umbrella.visible) and not far.rain.inside
		and is_equal_approx(far.rain.pace(false), 1.0)), "a walker out of the camera's range walks on as in the dry")
	RainCrowd.forced = -1.0
	far.queue_free()
	_free(peds)
	var seats: Array = chunk.get_meta("life_seats", [])
	chunk.set_meta("life_seats", seats.filter(func(s): return (s.p as Vector2).distance_to(Vector2(stop.x, stop.z)) > 1.0))
	await _ticks(2)


func _free(peds: Array) -> void:
	for p in peds:
		if is_instance_valid(p):
			p.queue_free()


func _check(ok: bool, label: String) -> void:
	_t._check(ok, label)


func _ticks(n: int) -> void:
	for i in n:
		await _tree.physics_frame
