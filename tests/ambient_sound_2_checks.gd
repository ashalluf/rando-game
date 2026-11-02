extends RefCounted
## The street's sound at eye level (StreetSounds, Ambience's leaves and far-sea beds, the traffic's
## wet hiss; tests/smoke_test.gd loads this at run time like ambience_checks.gd). The headless run
## has the Dummy audio driver, so these check the tables, the pure functions (levels_for() and
## rates_for() are pure: same answer twice, inputs untouched), what each new source wants where,
## and that the hooks count the sounds they ask for.

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	await t.get_tree().process_frame
	var sfx: Node = t.get_tree().root.get_node("Sfx")
	var amb := city.get_node_or_null("Ambience") as Ambience
	_tables(sfx)
	_pure_street()
	if amb == null:
		_t._check(false, "street sound: the city has an Ambience node")
		return
	amb.frozen = true
	_purity(amb, city.plan.macro)
	_beds(amb, city.plan.macro)
	await _events(amb)
	amb.frozen = false


func _tables(sfx: Node) -> void:
	var bad: PackedStringArray = []
	for key: String in ["shop_bell", "car_door", "car_door_open", "air_brake", "footstep_heels", "tyre_gravel", "tyre_wet",
			"amb_leaves", "amb_sea_far"]:
		var got: Array = sfx.take(key)
		if got.is_empty() or not (got[0] is AudioStreamOggVorbis):
			bad.append(key)
			continue
		var loops: bool = key in sfx.LOOPING or key in sfx.AMBIENCE_LOOPING
		var want_loop := key.begins_with("tyre_") or key.begins_with("amb_")
		if loops != want_loop or (want_loop and not (got[0] as AudioStreamOggVorbis).loop):
			bad.append(key + "(loop)")
		var table: Dictionary = sfx.SAMPLES if sfx.SAMPLES.has(key) else sfx.AMBIENCE_SAMPLES
		var levels: Dictionary = sfx.SAMPLE_LOUDNESS_DB if sfx.SAMPLES.has(key) else sfx.AMBIENCE_LOUDNESS_DB
		if (table[key] as Array).size() != (levels.get(key, []) as Array).size():
			bad.append(key + "(loudness)")
	_t._check(bad.is_empty(), "street sound: the new names load their CC0 takes, loops loop, every take has its loudness (%s)" % ",".join(bad))
	_t._check(sfx.bus_for("shop_bell") == &"World" and sfx.bus_for("tyre_wet") == &"World" and sfx.bus_for("amb_leaves") == &"Ambience"
		and sfx.bus_for("amb_sea_far") == &"Ambience",
		"street sound: bells, doors, steps and tyres play on World; the leaves and the far sea on Ambience")


func _pure_street() -> void:
	var walk := StreetSounds.step_interval(1.4)
	var run := StreetSounds.step_interval(4.0)
	_t._check(walk > 0.42 and walk < 0.6 and run < walk and run > 0.25 and StreetSounds.step_interval(0.0) == INF,
		"street sound: a walker steps ~2 a second (%.2f s), a runner faster (%.2f s), nobody standing still" % [walk, run])
	_t._check(StreetSounds.step_sound("concrete", true) == "footstep_heels" and StreetSounds.step_sound("grass", true) == "footstep_grass"
		and StreetSounds.step_sound("asphalt", false) == "footstep_asphalt"
		and StreetSounds.step_db(1.4, "grass") < StreetSounds.step_db(1.4, "concrete") and StreetSounds.step_db(4.0, "concrete") > StreetSounds.step_db(1.4, "concrete"),
		"street sound: heels click on hard ground only; soft ground is quieter, running louder")
	_t._check(StreetSounds.tyre_kind("grass", 0.0) == "gravel" and StreetSounds.tyre_kind("sand", 1.0) == "gravel"
		and StreetSounds.tyre_kind("asphalt", 0.8) == "wet" and StreetSounds.tyre_kind("concrete", 0.1) == ""
		and StreetSounds.tyre_kind("asphalt", 0.0) == "",
		"street sound: tyres crunch off the tarmac, hiss on a wet road, leave a dry one to the engine")
	_t._check(StreetSounds.tyre_db("gravel", 0.2) < -60.0 and StreetSounds.tyre_db("gravel", 25.0) > StreetSounds.tyre_db("gravel", 6.0)
		and StreetSounds.tyre_db("wet", 6.0) < StreetSounds.tyre_db("gravel", 6.0) and StreetSounds.tyre_db("", 20.0) < -60.0,
		"street sound: the tyre loop is silent standing, grows with speed, the wet hiss quieter at a crawl")
	# Air brakes: rolling, then standing, hisses once; not again inside the cooldown.
	var rec: Array = [Vector3.ZERO, 0.0, -100000]
	var hissed := 0
	for i in 8:
		if StreetSounds.brake_step(rec, 8.0, 0.25, 1000 + i * 250, 12.0):
			hissed += 1
	var first := StreetSounds.brake_step(rec, 0.0, 0.25, 3200, 12.0)
	for i in 8:
		StreetSounds.brake_step(rec, 8.0, 0.25, 3500 + i * 250, 12.0)
	var again := StreetSounds.brake_step(rec, 0.0, 0.25, 6000, 12.0)
	var short_roll: Array = [Vector3.ZERO, 0.0, -100000]
	StreetSounds.brake_step(short_roll, 8.0, 0.25, 0, 12.0)
	var creep := StreetSounds.brake_step(short_roll, 0.0, 0.25, 250, 12.0)
	_t._check(hissed == 0 and first and not again and not creep,
		"street sound: a bus or truck's air brakes set once as it stops (%s), not again within the cooldown (%s), not after a creep (%s)" % [first, again, creep])


func _purity(amb: Ambience, macro: MacroMap) -> void:
	var dt: Vector2 = macro.downtown_center
	var s := amb.scene_at(Vector3(dt.x, 2.0, dt.y), macro)
	var wx := {"rain": 0.4, "storm": 0.0, "waves": 1.5, "wind": 0.6, "wet": 0.5}
	var s0 := s.duplicate(true)
	var w0 := wx.duplicate(true)
	var a := amb.levels_for(s, 18.0, 0.3, wx)
	var b := amb.levels_for(s, 18.0, 0.3, wx)
	var ra := amb.rates_for(s, 18.0, 0.3, wx)
	var rb := amb.rates_for(s, 18.0, 0.3, wx)
	_t._check(a == b and ra == rb and str(s) == str(s0) and wx == w0,
		"street sound: levels_for() and rates_for() are pure (same answer twice, the scene and weather untouched)")
	var missing: PackedStringArray = []
	for layer: String in Ambience.LAYERS:
		if not a.has(layer):
			missing.append(layer)
	for kind: String in Ambience.ONE_SHOTS:
		if not ra.has(kind):
			missing.append(kind)
	_t._check(missing.is_empty(), "street sound: levels_for() has every layer and rates_for() every one-shot (missing %s)" % ",".join(missing))


func _scene(green: float, urban: float) -> Dictionary:
	var z := PackedFloat32Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	z[MacroMap.Zone.CITY] = 1.0
	return {"zones": z, "urban": urban, "green": green, "far_city": 1.0, "altitude": 0.0, "ridge": 0.0,
		"canyon": 0.0, "cover": 0.0, "in_car": 0.0, "crowd": 0.0, "panic": 0.0, "cars": 0,
		"surf": 0.0, "freeway": 0.0, "airport": 0.0, "port": 0.0, "sea_far": 0.0}


func _beds(amb: Ambience, macro: MacroMap) -> void:
	var calm := {"rain": 0.0, "storm": 0.0, "waves": 1.0, "wind": 0.25}
	var windy := {"rain": 0.0, "storm": 0.0, "waves": 1.0, "wind": 0.9}
	var suburb := _scene(0.85, 0.25)
	var core := _scene(0.05, 1.0)
	var l_sub := amb.levels_for(suburb, 14.0, 0.0, calm)
	var l_win := amb.levels_for(suburb, 14.0, 0.0, windy)
	var l_core := amb.levels_for(core, 14.0, 0.0, calm)
	var car := suburb.duplicate()
	car["in_car"] = 1.0
	var l_car := amb.levels_for(car, 14.0, 0.0, windy)
	_t._check(l_sub.leaves > 0.25 and l_win.leaves > l_sub.leaves * 1.5 and l_core.leaves < 0.1 and l_car.leaves < l_win.leaves * 0.4,
		"street sound: leaves rustle on a leafy street (%.2f), more in the wind (%.2f), hardly downtown (%.2f) or in a car (%.2f)" % [l_sub.leaves, l_win.leaves, l_core.leaves, l_car.leaves])
	# The sea from afar: a point ~900 m inland of the coast vs downtown.
	var inland := Vector3.INF
	for z in [-300.0, -100.0, 100.0, 300.0, 600.0]:
		var p := Vector2(macro.coast_x(z) + 900.0, z)
		if macro.zone_at(p) == MacroMap.Zone.CITY:
			inland = Vector3(p.x, 2.0, p.y)
			break
	_t._check(inland != Vector3.INF, "street sound: found a street ~900 m inland of the beach")
	if inland == Vector3.INF:
		return
	var near_s := amb.scene_at(inland, macro)
	var dt: Vector2 = macro.downtown_center
	var far_s := amb.scene_at(Vector3(dt.x, 2.0, dt.y), macro)
	var n_night := amb.levels_for(near_s, 2.0, 1.0, calm)
	var n_noon := amb.levels_for(near_s, 13.0, 0.0, calm)
	var d_night := amb.levels_for(far_s, 2.0, 1.0, calm)
	var at: Vector3 = near_s.get("sea_far_at", Vector3.INF)
	_t._check(n_night.sea_far > 0.15 and n_night.sea_far >= n_noon.sea_far and d_night.sea_far < 0.02 and at != Vector3.INF and at.x < inland.x,
		"street sound: the sea is heard ~900 m inland (%.2f at night, %.2f at noon), from the west, not downtown (%.2f)" % [n_night.sea_far, n_noon.sea_far, d_night.sea_far])
	# The A/B: off, the new beds are silent.
	StreetSounds.enabled = false
	var off := amb.levels_for(near_s, 2.0, 1.0, windy)
	StreetSounds.enabled = true
	_t._check(off.leaves == 0.0 and off.sea_far == 0.0, "street sound: AMBIENT_SOUND_2=0 silences the new beds")


func _events(amb: Ambience) -> void:
	var node := amb.get_node_or_null("StreetSounds") as StreetSounds
	_t._check(node != null, "street sound: Ambience made its StreetSounds node")
	if node == null:
		return
	var cam := amb.get_viewport().get_camera_3d()
	var eye := cam.global_position if cam else Vector3.ZERO
	var c0: Dictionary = StreetSounds.counts.duplicate()
	StreetSounds.shop_door(eye + Vector3(4.0, -1.5, 3.0))
	StreetSounds.shop_door(eye + Vector3(node.event_reach + 60.0, 0.0, 0.0))
	var door := Node3D.new()
	amb.get_parent().add_child(door)
	door.global_position = eye + Vector3(-3.0, -1.0, 2.0)
	StreetSounds.car_door_moved(door, 0.0, 0.1)  # starts to open
	StreetSounds.car_door_moved(door, 0.5, 0.6)  # swinging: nothing
	StreetSounds.car_door_moved(door, 0.1, 0.0)  # shut
	door.queue_free()
	await amb.get_tree().process_frame
	var bells := int(StreetSounds.counts.bell) - int(c0.bell)
	var doors := int(StreetSounds.counts.door) - int(c0.door)
	_t._check(bells == 1 and doors == 2,
		"street sound: a shop door rings its bell near the listener and not 100 m off (%d), a car door sounds opening and shutting (%d)" % [bells, doors])
	# A far bark comes from a real dog when one is in earshot.
	var dog := Node3D.new()
	dog.add_to_group("dog")
	amb.get_parent().add_child(dog)
	dog.global_position = eye + Vector3(2.0, 0.0, 0.0)
	var heard := StreetSounds.dog_at(amb.get_tree(), eye, 240.0)
	dog.queue_free()
	_t._check(heard != Vector3.INF and heard.distance_to(eye) < 3.0,
		"street sound: Ambience's far bark comes from a real dog in earshot (%.1f m off)" % (heard.distance_to(eye) if heard != Vector3.INF else -1.0))
