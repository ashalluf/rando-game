extends RefCounted
## Ambience checks for tests/smoke_test.gd, loaded at run time (like air_traffic_checks.gd) so it
## compiles after the autoloads and can name Ambience, MacroMap and CityPlan freely.
##
## The headless run uses the Dummy audio driver, which plays nothing, so these check the MIXER:
## which layers the mix wants and how loud, for a place, an hour and the weather; that the fades
## are fades; that the ducks and the enclosure filters move the buses; and that the buses, the
## routing and every sound the mix asks for (recording or synthesized fallback) really exist.
## All of it is maths on the pure functions or a few steps of the easing - well under a second.

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	await t.get_tree().process_frame
	var amb := city.get_node_or_null("Ambience") as Ambience
	t._check(amb != null, "the city has an Ambience node")
	if amb == null:
		return
	var sfx: Node = t.get_tree().root.get_node("Sfx")
	_buses(sfx)
	_sounds(sfx)
	amb.frozen = true
	var macro: MacroMap = city.plan.macro
	_places(amb, macro)
	_fades(amb)
	_ducks(amb)
	_live(amb, city)
	amb.frozen = false


func _buses(sfx: Node) -> void:
	var game := AudioServer.get_bus_index(&"Game")
	var world := AudioServer.get_bus_index(&"World")
	var ambb := AudioServer.get_bus_index(&"Ambience")
	_t._check(game > 0 and world > game and ambb > game
		and AudioServer.get_bus_send(world) == &"Game" and AudioServer.get_bus_send(ambb) == &"Game"
		and AudioServer.get_bus_send(game) == &"Master",
		"audio buses: World and Ambience feed Game, Game feeds Master")
	if game < 0 or world < 0 or ambb < 0:
		return
	var comp := AudioServer.get_bus_effect(ambb, 1) as AudioEffectCompressor
	_t._check(AudioServer.get_bus_effect(world, 0) is AudioEffectReverb
		and AudioServer.get_bus_effect(ambb, 0) is AudioEffectLowPassFilter
		and comp != null and comp.sidechain == &"World"
		and AudioServer.get_bus_effect(game, 0) is AudioEffectLowPassFilter
		and AudioServer.get_bus_effect(0, AudioServer.get_bus_effect_count(0) - 1) is AudioEffectHardLimiter,
		"bus effects: street reverb on World, enclosure low-pass and a ducker keyed on World on Ambience, a muffle on Game, the limiter on Master")
	_t._check(sfx.bus_for("shot") == &"World" and sfx.bus_for("explosion") == &"World"
		and sfx.bus_for("thunder") == &"Ambience" and sfx.bus_for("rain") == &"Ambience"
		and sfx.bus_for("gull") == &"Ambience",
		"gunfire and blasts play on World; thunder, rain and the ambience on Ambience")


func _sounds(sfx: Node) -> void:
	var missing: PackedStringArray = []
	var wanted: Array = ["car_roll", "car_pass", "car_pass_wet"]
	for layer: String in Ambience.LAYERS:
		wanted.append(Ambience.LAYERS[layer].sound)
	for kind: String in Ambience.ONE_SHOTS:
		wanted.append(Ambience.ONE_SHOTS[kind].sound)
	for sound: String in wanted:
		if not sfx.has(sound):
			missing.append(sound)
	_t._check(missing.is_empty(), "every ambience layer and one-shot has a sound (missing: %s)" % ",".join(missing))
	# The recordings loaded (not just the fallback), and the beds loop: the flag is set in code.
	var not_real: PackedStringArray = []
	for key: String in sfx.AMBIENCE_SAMPLES:
		var got: Array = sfx.take(key)
		if got.is_empty() or not (got[0] is AudioStreamOggVorbis):
			not_real.append(key)
		elif key in sfx.AMBIENCE_LOOPING and not (got[0] as AudioStreamOggVorbis).loop:
			not_real.append(key + "(no loop)")
	_t._check(not_real.is_empty(), "all %d ambience names load their CC0 recordings, beds looping (%s)" % [sfx.AMBIENCE_SAMPLES.size(), ",".join(not_real)])
	var counts_ok := true
	for key: String in sfx.AMBIENCE_SAMPLES:
		if (sfx.AMBIENCE_SAMPLES[key] as Array).size() != (sfx.AMBIENCE_LOUDNESS_DB.get(key, []) as Array).size():
			counts_ok = false
	_t._check(counts_ok, "every ambience take has a loudness entry")
	# The synthesized fallbacks build and are not silent (what plays if a file goes missing).
	var t0 := Time.get_ticks_msec()
	var silent: PackedStringArray = []
	for key: String in ["amb_surf", "amb_crowd", "amb_crickets", "dog", "ship_horn", "car_pass"]:
		var buf: PackedFloat32Array = sfx.ambience_synth(key)
		var peak := 0.0
		for i in range(0, buf.size(), 7):
			peak = maxf(peak, absf(buf[i]))
		if buf.size() < 2000 or peak < 0.02:
			silent.append(key)
	_t._check(silent.is_empty(), "ambience fallbacks synthesize sound (%s silent; %d ms)" % [",".join(silent), Time.get_ticks_msec() - t0])


## Positions found from the map itself, so a retune of MacroMap moves them with it.
func _find(macro: MacroMap, want: Callable, xs: Array, zs: Array) -> Vector3:
	for z in zs:
		for x in xs:
			if want.call(Vector2(x, z)):
				return Vector3(x, 2.0, z)
	return Vector3.INF


func _places(amb: Ambience, macro: MacroMap) -> void:
	_t._check(amb.district_density.size() == CityPlan.District.size(), "Ambience.district_density has one entry per district (%d/%d)" % [amb.district_density.size(), CityPlan.District.size()])
	var clear := {"rain": 0.0, "storm": 0.0, "waves": 1.0}
	var rain := {"rain": 1.0, "storm": 0.0, "waves": 3.2}
	var storm := {"rain": 1.0, "storm": 1.0, "waves": 6.0}
	var dt: Vector2 = macro.downtown_center
	var downtown := amb.scene_at(Vector3(dt.x, 2.0, dt.y), macro)
	var noon := amb.levels_for(downtown, 12.0, 0.0, clear)
	var night := amb.levels_for(downtown, 1.0, 1.0, clear)
	var noon_r := amb.rates_for(downtown, 12.0, 0.0, clear)
	_t._check(noon.city > 0.8 and noon.city > noon.birds * 3.0 and noon.crickets < 0.02 and noon.surf < 0.02 and noon_r.horn > 3.0 and noon_r.gull == 0.0,
		"downtown at noon is the city's roar and horns (city %.2f, birds %.2f, horns %.1f/min)" % [noon.city, noon.birds, noon_r.horn])
	_t._check(night.city < noon.city * 0.6 and night.city_far > noon.city_far and night.birds == 0.0,
		"downtown at night the near roar thins and the far traffic carries (city %.2f -> %.2f, far %.2f -> %.2f)" % [noon.city, night.city, noon.city_far, night.city_far])
	var wet := amb.levels_for(downtown, 12.0, 0.0, rain)
	_t._check(wet.rain > 0.9 and wet.rain_heavy > 0.9 and wet.rain_roof == 0.0, "rain on the open street: rain %.2f, downpour %.2f" % [wet.rain, wet.rain_heavy])
	var covered := downtown.duplicate()
	covered["cover"] = 1.0
	var under := amb.levels_for(covered, 12.0, 0.0, rain)
	var car := downtown.duplicate()
	car["in_car"] = 1.0
	var inside := amb.levels_for(car, 12.0, 0.0, rain)
	_t._check(under.rain_roof > 0.9 and under.rain < 0.3 and inside.rain_car > 0.9 and inside.rain_roof == 0.0,
		"under cover the rain is on the roof (%.2f, open %.2f); in a car it is on the car (%.2f)" % [under.rain_roof, under.rain, inside.rain_car])
	var high := amb.scene_at(Vector3(dt.x, 420.0, dt.y), macro)
	var air := amb.levels_for(high, 12.0, 0.0, clear)
	_t._check(high.altitude > 0.99 and air.city < noon.city * 0.5 and air.traffic < 0.05 and air.wind > noon.wind and air.gale > 0.3,
		"400 m over downtown the street falls away and the wind takes over (city %.2f, wind %.2f, gale %.2f)" % [air.city, air.wind, air.gale])
	var gale := amb.levels_for(downtown, 12.0, 0.0, storm)
	_t._check(gale.gale > 0.6 and gale.birds < 0.2, "a storm brings the gale in and the birds down (gale %.2f)" % gale.gale)
	# The beach.
	var shore := Vector3.INF
	for z in [-300.0, -100.0, 100.0, 300.0]:
		var x := macro.coast_x(z) + macro.beach_width * 0.5
		if macro.zone_at(Vector2(x, z)) == MacroMap.Zone.BEACH:
			shore = Vector3(x, 2.0, z)
			break
	_t._check(shore != Vector3.INF, "found a beach to listen at")
	if shore != Vector3.INF:
		var s := amb.scene_at(shore, macro)
		var lv := amb.levels_for(s, 12.0, 0.0, clear)
		var r := amb.rates_for(s, 12.0, 0.0, clear)
		var rs := amb.rates_for(s, 12.0, 0.0, storm)
		var at: Vector3 = s.surf_at
		_t._check(lv.surf > 0.7 and r.gull > 2.0 and rs.gull == 0.0 and at.x < shore.x,
			"the beach has surf from the west (%.2f) and gulls by day (%.1f/min), none in a storm" % [lv.surf, r.gull])
		var big := amb.levels_for(s, 12.0, 0.0, storm)
		_t._check(big.surf > lv.surf, "storm waves make the surf louder (%.2f -> %.2f)" % [lv.surf, big.surf])
	# The hills, deep in them.
	var hill := _find(macro, func(p: Vector2) -> bool: return macro.zone_at(p) == MacroMap.Zone.HILLS and macro.raw_height_at(p) > 200.0,
		[-600.0, -200.0, 200.0, 600.0, 1000.0, 1400.0], [-1200.0, -1300.0, -1400.0])
	_t._check(hill != Vector3.INF, "found hills to listen in")
	if hill != Vector3.INF:
		hill.y = macro.height_at(Vector2(hill.x, hill.z)) + 2.0
		var s := amb.scene_at(hill, macro)
		var day := amb.levels_for(s, 12.0, 0.0, clear)
		var dark := amb.levels_for(s, 1.0, 1.0, clear)
		var rd := amb.rates_for(s, 12.0, 0.0, clear)
		var rn := amb.rates_for(s, 1.0, 1.0, clear)
		_t._check(day.birds > 0.3 and day.crickets == 0.0 and rd.coyote == 0.0 and dark.crickets > 0.4 and dark.birds == 0.0 and rn.coyote > 0.3,
			"the hills: birds by day (%.2f), crickets (%.2f) and coyotes (%.1f/min) at night" % [day.birds, dark.crickets, rn.coyote])
		_t._check(day.wind > noon.wind and day.city < noon.city, "the hills are windier and quieter than downtown (wind %.2f vs %.2f)" % [day.wind, noon.wind])
		var wet_night := amb.levels_for(s, 1.0, 1.0, rain)
		_t._check(wet_night.crickets == 0.0, "crickets stop in the rain")
	# The suburbs: dogs, birds, a thin city.
	var sub := _find(macro, func(p: Vector2) -> bool: return macro.zone_at(p) == MacroMap.Zone.CITY and macro.district_at(p) == CityPlan.District.SUBURBS,
		[1300.0, 1500.0, 1700.0, -1100.0], [-400.0, 0.0, 400.0])
	if sub != Vector3.INF:
		var s := amb.scene_at(sub, macro)
		var lv := amb.levels_for(s, 12.0, 0.0, clear)
		var r := amb.rates_for(s, 12.0, 0.0, clear)
		_t._check(lv.city < noon.city * 0.6 and lv.birds > noon.birds and r.dog > noon_r.dog,
			"the suburbs: a thinner city (%.2f), more birds (%.2f) and dogs (%.1f/min)" % [lv.city, lv.birds, r.dog])
	# The airfield and the port.
	var field := amb.scene_at(Vector3(macro.airport_rect.get_center().x, 2.0, macro.airport_rect.get_center().y), macro)
	var port := amb.scene_at(Vector3(macro.port_rect.get_center().x, 2.0, macro.port_rect.get_center().y), macro)
	var fl := amb.levels_for(field, 12.0, 0.0, clear)
	var pl := amb.levels_for(port, 12.0, 0.0, clear)
	var pr := amb.rates_for(port, 12.0, 0.0, clear)
	_t._check(fl.airport > 0.8 and noon.airport < 0.1, "the airfield rumbles (%.2f; downtown %.2f)" % [fl.airport, noon.airport])
	_t._check(pl.port > 0.8 and pr.ship_horn > 0.3 and pr.crane > 1.0 and noon_r.ship_horn < 0.1,
		"the port: hum %.2f, ship horns %.1f/min, cranes %.1f/min" % [pl.port, pr.ship_horn, pr.crane])
	# On a freeway deck.
	var fw: Freeway = macro.freeway
	if fw and fw.routes.size() > 0:
		var p: Array = fw.point_at(0, fw.length_of(0) * 0.5)
		var deck: Vector3 = p[0]
		var s := amb.scene_at(deck + Vector3.UP * 1.5, macro)
		var aside := amb.scene_at(deck + Vector3(0.0, 1.5, 0.0) + Vector3(p[1].y, 0.0, -p[1].x) * 300.0, macro)
		_t._check(s.freeway > 0.9 and aside.freeway < s.freeway, "the freeway roars on its deck (%.2f) and fades off it (%.2f at 300 m)" % [s.freeway, aside.freeway])


func _fades(amb: Ambience) -> void:
	var sfx: Node = _t.get_tree().root.get_node("Sfx")
	for layer: String in amb.gains:
		amb.gains[layer] = 0.0
		amb.levels[layer] = 0.0
	amb.levels["city"] = 1.0
	amb.step(0.1)
	var one: float = amb.gains.city
	for i in 40:
		amb.step(0.1)
	var four: float = amb.gains.city
	_t._check(one > 0.0 and one < 0.15 and four > 0.75, "beds crossfade instead of snapping (%.2f after 0.1 s, %.2f after 4 s)" % [one, four])
	var bed: Node = amb.get_node("Bed_city")
	_t._check(bed.get("playing") and bed.get("bus") == &"Ambience", "a bed with a level plays on the Ambience bus")
	amb.levels["city"] = 0.0
	for i in 200:
		amb.step(0.1)
	_t._check(not bed.get("playing"), "a bed that fades out stops playing (costs nothing)")
	# A take the bed reports as playing carries the sample's trim and the layer level.
	_t._check(sfx.take("amb_city").size() == 2, "Sfx.take() hands out a stream and its trim")


func _ducks(amb: Ambience) -> void:
	var eye := Vector3(0.0, 2.0, 0.0)
	amb.scene = {"in_car": 0.0, "cover": 0.0, "canyon": 0.0}
	for i in 40:
		amb.step(0.1)
	var open_cut := amb.game_cutoff
	amb.notify_blast(eye + Vector3(8.0, 0.0, 0.0), eye)
	amb.step(0.05)
	var duck_now := amb.duck_db
	var cut_now := amb.game_cutoff
	var game := AudioServer.get_bus_index(&"Game")
	var muffled := AudioServer.is_bus_effect_enabled(game, 0)
	for i in 40:
		amb.step(0.1)
	_t._check(open_cut >= 19000.0 and duck_now < -8.0 and cut_now < 3000.0 and muffled and amb.duck_db > -0.5 and amb.game_cutoff >= 19000.0 and not AudioServer.is_bus_effect_enabled(game, 0),
		"a blast close by ducks the ambience (%.1f dB) and muffles the game (%.0f Hz), then recovers" % [duck_now, cut_now])
	amb.notify_blast(eye + Vector3(500.0, 0.0, 0.0), eye)
	amb.step(0.05)
	_t._check(amb.duck_db > -0.5, "a blast far away does not duck anything")
	# The weapon wheel slows the audio; the mix muffles and dips with it.
	AudioServer.playback_speed_scale = 0.4
	for i in 20:
		amb.step(0.1)
	var slow_cut := amb.game_cutoff
	var slow_duck := amb.duck_db
	AudioServer.playback_speed_scale = 1.0
	for i in 30:
		amb.step(0.1)
	_t._check(slow_cut < 2000.0 and slow_duck < -3.0 and amb.game_cutoff >= 19000.0 and amb.duck_db > -0.5,
		"slow motion muffles the game (%.0f Hz) and dips the ambience (%.1f dB), and lets go after" % [slow_cut, slow_duck])
	# Shut in: a car low-passes the ambience; a street canyon grows the World reverb.
	amb.scene = {"in_car": 1.0, "cover": 0.0, "canyon": 0.0}
	for i in 20:
		amb.step(0.1)
	var car_cut := amb.ambience_cutoff
	var ambb := AudioServer.get_bus_index(&"Ambience")
	var car_on := AudioServer.is_bus_effect_enabled(ambb, 0)
	amb.scene = {"in_car": 0.0, "cover": 0.0, "canyon": 1.0}
	for i in 100:
		amb.step(0.1)
	var world := AudioServer.get_bus_index(&"World")
	var verb := AudioServer.get_bus_effect(world, 0) as AudioEffectReverb
	var canyon_wet := verb.wet
	amb.scene = {"in_car": 0.0, "cover": 0.0, "canyon": 0.0}
	for i in 100:
		amb.step(0.1)
	_t._check(car_cut < 2000.0 and car_on and amb.ambience_cutoff >= 19000.0 and not AudioServer.is_bus_effect_enabled(ambb, 0),
		"inside a car the city is low-passed (%.0f Hz), and opens up again outside" % car_cut)
	_t._check(canyon_wet > 0.2 and verb.wet < 0.08, "a street canyon grows the reverb (wet %.2f, open %.2f)" % [canyon_wet, verb.wet])


func _live(amb: Ambience, city: Node3D) -> void:
	var cam := amb.get_viewport().get_camera_3d()
	var eye: Vector3 = cam.global_position if cam else Vector3.ZERO
	var t0 := Time.get_ticks_usec()
	amb._survey(eye)
	var cost := float(Time.get_ticks_usec() - t0) / 1000.0
	_t._check(amb.scene.has("canyon") and amb.levels.has("city") and amb.rates.has("horn"), "the live survey fills the scene, levels and rates")
	_t._check(cost < 25.0, "one survey is cheap (%.2f ms)" % cost)
	var before: int = amb.fired.get("horn", 0)
	amb.fire("horn", eye, WorldState.to_world(eye))
	var playing := 0
	for v in amb.find_children("Shot_*", "AudioStreamPlayer3D", false, false):
		if (v as AudioStreamPlayer3D).playing and (v as AudioStreamPlayer3D).bus == &"Ambience":
			playing += 1
	_t._check(amb.fired.get("horn", 0) == before + 1 and playing >= 1, "a one-shot plays from the pool on the Ambience bus")
	# Traffic voices follow real cars from TrafficManager's lists.
	var traffic := city.get_node_or_null("Traffic")
	var n_cars: int = (traffic.get("cars") as Array).size() if traffic else 0
	if n_cars > 0:
		var keep := amb.car_hear_distance
		amb.car_hear_distance = 100000.0
		amb._assign_traffic(eye)
		amb.car_hear_distance = keep
		var following := 0
		for c in amb._car_of:
			if c != null:
				following += 1
		_t._check(following >= 1, "traffic voices follow the nearest cars (%d of %d)" % [following, amb._car_of.size()])
