extends RefCounted
## The city's acoustics (tests/smoke_test.gd loads this at run time, like ambience_checks.gd):
## the sample tables, the Echo bus, the acoustic spaces and their reverb, gunfire's echo taps, the
## footstep surfaces, and the new sources (the river, fountains, playgrounds, construction, the
## bus's diesel, the light rail's tunnel). Mixer state and pure functions only: the headless run
## has the Dummy audio driver.

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	await t.get_tree().process_frame
	var sfx: Node = t.get_tree().root.get_node("Sfx")
	var amb := city.get_node_or_null("Ambience") as Ambience
	_tables(sfx)
	_echo_bus()
	if amb == null:
		_t._check(false, "audio: the city has an Ambience node")
		return
	amb.frozen = true
	_spaces(amb)
	_echoes(amb)
	await _echo_plays(sfx)
	var plan: CityPlan = city.plan
	_sources(amb, plan)
	_footsteps(plan, city)
	amb.frozen = false


func _tables(sfx: Node) -> void:
	var bad: PackedStringArray = []
	for key: String in sfx.SAMPLES:
		if (sfx.SAMPLES[key] as Array).size() != (sfx.SAMPLE_LOUDNESS_DB.get(key, []) as Array).size():
			bad.append(key)
	_t._check(bad.is_empty(), "audio: every Sfx take has a loudness entry (%d names; off: %s)" % [sfx.SAMPLES.size(), ",".join(bad)])
	var not_real: PackedStringArray = []
	for key: String in ["footstep_concrete", "footstep_asphalt", "footstep_grass", "footstep_sand", "footstep_metal",
			"footstep_wood", "bus_door", "bus_chime", "bus_kneel", "diesel_idle", "rail_chime", "ball_dribble",
			"amb_river", "amb_fountain", "amb_playground", "construction"]:
		var got: Array = sfx.take(key)
		if got.is_empty() or not (got[0] is AudioStreamOggVorbis):
			not_real.append(key)
		elif (key in sfx.LOOPING or key in sfx.AMBIENCE_LOOPING) and not (got[0] as AudioStreamOggVorbis).loop:
			not_real.append(key + "(no loop)")
	_t._check(not_real.is_empty(), "audio: the new names load their CC0 recordings, loops looping (%s)" % ",".join(not_real))
	_t._check(sfx.has("rail_motor") and sfx.has("rail_hum") and Footsteps.SURFACES.all(func(s: String) -> bool: return sfx.has("footstep_" + s)),
		"audio: the train's motor and wire hum synthesize; every footstep surface has a sound")
	# Every file in assets/audio/ is shipped by a table: no stray downloads in the app.
	var named := {}
	for table: Dictionary in [sfx.SAMPLES, sfx.AMBIENCE_SAMPLES]:
		for key: String in table:
			for f: String in table[key]:
				named[f] = true
	var stray: PackedStringArray = []
	for f: String in DirAccess.get_files_at("res://assets/audio/"):
		if f.ends_with(".ogg") and not named.has(f):
			stray.append(f)
	_t._check(stray.is_empty(), "audio: every clip in assets/audio/ is named in Sfx (stray: %s)" % ",".join(stray))


func _echo_bus() -> void:
	var echo := AudioServer.get_bus_index(&"Echo")
	_t._check(echo > 0 and AudioServer.get_bus_send(echo) == &"Game"
		and AudioServer.get_bus_effect(echo, 0) is AudioEffectLowPassFilter
		and AudioServer.get_bus_effect(echo, 1) is AudioEffectReverb,
		"audio: the Echo bus (low-pass and tail) feeds Game")


func _scene(zone: int, walls: Array, extra: Dictionary = {}) -> Dictionary:
	var z := PackedFloat32Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	z[zone] = 1.0
	var s := {"zones": z, "urban": 0.8 if zone == MacroMap.Zone.CITY else 0.0, "altitude": 0.0,
		"walls": PackedFloat32Array(walls), "cover": 0.0, "canyon": 0.0, "tunnel": 0.0, "trench": 0.0, "channel": 0.0}
	for k: String in extra:
		s[k] = extra[k]
	return s


func _top(w: Dictionary) -> String:
	var best := ""
	var v := -1.0
	for k: String in w:
		if float(w[k]) > v:
			v = float(w[k])
			best = k
	return best


func _spaces(amb: Ambience) -> void:
	var I := INF
	var cases := {
		"alley": _scene(MacroMap.Zone.CITY, [3.0, 3.5, I, 4.0, 3.0, 3.5, I, 4.0]),
		"canyon": _scene(MacroMap.Zone.CITY, [12.0, 20.0, I, 20.0, 12.0, 20.0, I, 20.0], {"canyon": 1.0}),
		"street": _scene(MacroMap.Zone.CITY, [14.0, 20.0, I, 20.0, 16.0, 22.0, I, 22.0]),
		"underpass": _scene(MacroMap.Zone.CITY, [I, I, 25.0, I, I, I, I, I], {"cover": 1.0, "ceiling": 9.0}),
		"garage": _scene(MacroMap.Zone.CITY, [8.0, 10.0, 6.0, 9.0, 7.0, 12.0, 8.0, 10.0], {"cover": 1.0, "ceiling": 2.8}),
		"tunnel": _scene(MacroMap.Zone.CITY, [3.0, I, I, I, 3.0, I, I, I], {"tunnel": 1.0, "cover": 1.0, "ceiling": 3.0}),
		"trench": _scene(MacroMap.Zone.CITY, [3.0, I, I, I, 3.0, I, I, I], {"tunnel": 1.0}),
		"channel": _scene(MacroMap.Zone.CITY, [I, I, I, I, I, I, I, I], {"channel": 1.0}),
		"beach": _scene(MacroMap.Zone.BEACH, [I, I, I, I, I, I, I, I]),
		"hills": _scene(MacroMap.Zone.HILLS, [I, I, I, I, I, I, I, I]),
	}
	var wrong: PackedStringArray = []
	var wet := {}
	for want: String in cases:
		var w := amb.space_for(cases[want])
		var sum := 0.0
		for k: String in w:
			sum += float(w[k])
		var expect := "channel" if want == "trench" else want
		if _top(w) != expect or absf(sum - 1.0) > 0.01:
			wrong.append("%s->%s(%.2f)" % [want, _top(w), sum])
		wet[want] = float(amb.reverb_for(w).wet)
	_t._check(wrong.is_empty(), "audio: the probe tells the spaces apart: alley, canyon, street, underpass, car park, tunnel, the rail's open trench, river channel, beach, hills (%s)" % ",".join(wrong))
	_t._check(wet.tunnel > wet.underpass and wet.underpass > wet.canyon and wet.canyon > wet.street and wet.street > wet.beach and wet.alley > wet.street,
		"audio: the reverb follows the space (tunnel %.2f, under a deck %.2f, canyon %.2f, alley %.2f, street %.2f, beach %.3f)" % [wet.tunnel, wet.underpass, wet.canyon, wet.alley, wet.street, wet.beach])
	# The bus reverb moves to the space's preset.
	amb.space = {"tunnel": 1.0}
	for i in 60:
		amb.step(0.1)
	var verb := AudioServer.get_bus_effect(AudioServer.get_bus_index(&"World"), 0) as AudioEffectReverb
	var t_wet := verb.wet
	var t_room := verb.room_size
	amb.space = {"open": 1.0}
	for i in 60:
		amb.step(0.1)
	_t._check(t_wet > 0.38 and t_room > 0.85 and verb.wet < 0.06, "audio: walking into the tunnel swells the World reverb (wet %.2f, room %.2f), out again it dries (%.2f)" % [t_wet, t_room, verb.wet])


func _echoes(amb: Ambience) -> void:
	var I := INF
	var street := _scene(MacroMap.Zone.CITY, [10.0, 14.0, I, 14.0, 12.0, 15.0, I, 15.0], {"canyon": 1.0})
	var p := amb.echo_for(street, amb.space_for(street))
	var taps: Array = p.get("taps", [])
	var first := 99.0
	for tp: Array in taps:
		first = minf(first, float(tp[0]))
	_t._check(taps.size() >= 3 and absf(first - 20.0 / 343.0) < 0.005,
		"audio: downtown a shot slaps back off the facades (%d taps, first %.0f ms = 10 m away)" % [taps.size(), first * 1000.0])
	var hills := _scene(MacroMap.Zone.HILLS, [I, I, I, I, I, I, I, I])
	var h := amb.echo_for(hills, amb.space_for(hills))
	var last := 0.0
	for tp: Array in h.get("taps", []):
		last = maxf(last, float(tp[0]))
	_t._check((h.get("taps", []) as Array).size() >= 4 and last > 2.0 and float(h.get("cutoff", 9000.0)) < 2000.0,
		"audio: in the hills a shot rolls away for %.1f s, dull (%.0f Hz)" % [last, float(h.get("cutoff", 0.0))])
	var beach := _scene(MacroMap.Zone.BEACH, [I, I, I, I, I, I, I, I])
	var b := amb.echo_for(beach, amb.space_for(beach))
	_t._check(b.is_empty(), "audio: on the open beach a shot does not echo")
	var under := _scene(MacroMap.Zone.CITY, [I, I, 25.0, I, I, I, I, I], {"cover": 1.0, "ceiling": 9.0})
	var u := amb.echo_for(under, amb.space_for(under))
	var close := 0
	for tp: Array in u.get("taps", []):
		if float(tp[0]) < 0.12:
			close += 1
	_t._check(close >= 3, "audio: under a deck a shot comes back in a tight cluster (%d taps under 120 ms)" % close)


func _echo_plays(sfx: Node) -> void:
	sfx.set_echo({"taps": [[0.05, -6.0, Vector3.LEFT], [0.12, -10.0, Vector3.RIGHT]], "cutoff": 4000.0, "room": 0.5})
	var before: int = sfx.echoes_played
	var cam := _t.get_viewport().get_camera_3d()
	var at: Vector3 = cam.global_position if cam else Vector3.ZERO
	sfx.play("shot", at + Vector3(0.0, 0.0, -3.0))
	var queued: int = (sfx._echo_queue as Array).size()
	sfx.play("thud", at) # not an echo name
	var queued2: int = (sfx._echo_queue as Array).size()
	await _t.get_tree().create_timer(0.4).timeout
	await _t.get_tree().process_frame
	_t._check(queued >= 2 and queued2 == queued and sfx.echoes_played >= before + 2,
		"audio: a rifle shot queues its echoes and they play on the Echo bus (%d queued, %d played)" % [queued, sfx.echoes_played - before])
	var far: int = sfx.echo("shot", sfx.take("shot")[0], -6.0, 1.0, 900.0)
	_t._check(far == 0, "audio: a shot a kilometre off does not echo for the listener")
	sfx.set_echo({})


func _sources(amb: Ambience, plan: CityPlan) -> void:
	var macro := plan.macro
	var clear := {"rain": 0.0, "storm": 0.0, "waves": 1.0}
	# The river: down in the channel the trickle is close; up on the bank, a whisper.
	var rv: LaRiver = macro.river
	if rv != null and rv.length > 0.0:
		var s0 := rv.length * 0.3
		var at: Array = rv.at(s0)
		var p: Vector2 = at[0]
		var down := amb.scene_at(Vector3(p.x, rv.water_at(s0) + 1.7, p.y), macro, plan)
		var side: Vector2 = Vector2(-(at[1] as Vector2).y, (at[1] as Vector2).x)
		var bank_p := p + side * (rv.top_half(s0) + 3.0)
		var bank := amb.scene_at(Vector3(bank_p.x, rv.top_at(s0) + 1.7, bank_p.y), macro, plan)
		var lv := amb.levels_for(down, 12.0, 0.0, clear)
		_t._check(down.channel > 0.8 and lv.river > 0.8 and bank.river < down.river * 0.6 and bank.channel < 0.2,
			"audio: in the river's channel the water trickles (%.2f), from the bank it is faint (%.2f)" % [lv.river, bank.river])
		var sp := amb.space_for(down)
		_t._check(_top(sp) == "channel" or float(sp.get("channel", 0.0)) > 0.4, "audio: the river's channel is its own space (%.2f)" % float(sp.get("channel", 0.0)))
	# A plaza's fountain and a rec park's playground, found from the plan.
	var plaza := Vector2.INF
	var kids := Vector2.INF
	var dt: Vector2 = macro.downtown_center
	var bi := plan.block_index_at(dt)
	for r in range(0, 40):
		for dx in range(-r, r + 1):
			for dz in [-r, r]:
				for pair: Vector2i in [Vector2i(dx, dz), Vector2i(dz, dx)]:
					var b := plan.block(bi.x + pair.x, bi.y + pair.y)
					if plaza == Vector2.INF and int(b.kind) == CityPlan.BlockKind.PLAZA:
						plaza = (b.rect as Rect2).get_center()
					if kids == Vector2.INF and String(b.get("grounds", "")) != "":
						for f: Dictionary in Parks.plan_for(plan, bi.x + pair.x, bi.y + pair.y).get("fac", []):
							if f.t == "playground":
								kids = f.c
		if plaza != Vector2.INF and kids != Vector2.INF:
			break
	if plaza != Vector2.INF:
		var s := amb.scene_at(Vector3(plaza.x + 10.0, macro.height_at(plaza) + 1.7, plaza.y), macro, plan)
		var lv := amb.levels_for(s, 12.0, 0.0, clear)
		_t._check(lv.fountain > 0.6, "audio: a plaza fountain splashes (%.2f at 10 m)" % lv.fountain)
	else:
		_t._check(false, "audio: found a plaza to listen at")
	if kids != Vector2.INF:
		var s := amb.scene_at(Vector3(kids.x + 20.0, macro.height_at(kids) + 1.7, kids.y), macro, plan)
		var day := amb.levels_for(s, 11.0, 0.0, clear)
		var night := amb.levels_for(s, 23.0, 1.0, clear)
		_t._check(day.playground > 0.5 and night.playground == 0.0,
			"audio: kids at a playground by day (%.2f), quiet at night (%.2f)" % [day.playground, night.playground])
	else:
		_t._check(false, "audio: found a playground to listen at")
	# Construction in working hours downtown.
	var down_s := amb.scene_at(Vector3(dt.x, 2.0, dt.y), macro, plan)
	var noon := amb.rates_for(down_s, 11.0, 0.0, clear)
	var late := amb.rates_for(down_s, 22.0, 1.0, clear)
	_t._check(noon.construction > 0.5 and late.construction == 0.0,
		"audio: construction downtown in working hours (%.1f/min), none at night" % noon.construction)
	# The light rail's tunnel: a listener down at the rails is in the tunnel.
	var lr := LightRail.of(plan)
	if lr != null:
		var found := -1
		for i in lr.mode.size() - 1:
			if lr.mode[i] == LightRail.Mode.TUNNEL:
				found = i
				break
		if found >= 0:
			var p := lr.pts[found + 1]
			var s := amb.scene_at(Vector3(p.x, float(lr.rail[found + 1]) + 1.7, p.y), macro, plan)
			_t._check(float(s.tunnel) > 0.8, "audio: down at the light rail's rails under Flower is the tunnel (%.2f)" % float(s.tunnel))
	_t._check(not amb._diesel.is_empty(), "audio: buses and trucks idle on the diesel loop in the traffic voices")


func _footsteps(plan: CityPlan, city: Node3D) -> void:
	var macro := plan.macro
	var dt: Vector2 = macro.downtown_center
	var bi := plan.block_index_at(dt)
	var b := plan.block(bi.x, bi.y)
	var r: Rect2 = b.rect
	var road := Vector2(r.position.x - 3.0, r.get_center().y)
	var walk := Vector2(r.position.x + plan.sidewalk_width * 0.5, r.get_center().y)
	var got := [Footsteps.surface_at(plan, road, 0.3, null), Footsteps.surface_at(plan, walk, 0.5, null)]
	_t._check(got[0] == "asphalt" and got[1] == "concrete", "audio: footsteps on the road are asphalt, on the pavement concrete (%s, %s)" % got)
	var shore := Vector2.INF
	for z in [-300.0, -100.0, 100.0, 300.0]:
		var p := Vector2(macro.coast_x(z) + macro.beach_width * 0.5, z)
		if macro.zone_at(p) == MacroMap.Zone.BEACH:
			shore = p
			break
	if shore != Vector2.INF:
		_t._check(Footsteps.surface_at(plan, shore, macro.height_at(shore) + 0.05, null) == "sand", "audio: footsteps on the beach are sand")
	var pier := Vector2.INF
	for lm: Dictionary in Landmarks.all():
		if String(lm.id) == "pier":
			pier = lm.anchor
	if pier != Vector2.INF:
		var on := Footsteps.surface_at(plan, pier, 6.0, null)
		_t._check(on == "wood", "audio: footsteps on the pier are wood (%s)" % on)
	var park := Vector2.INF
	for dx in range(-12, 13):
		for dz in range(-12, 13):
			var pb := plan.block(bi.x + dx, bi.y + dz)
			if park == Vector2.INF and int(pb.kind) == CityPlan.BlockKind.PARK and String(pb.get("grounds", "")) == "" and not pb.has("site"):
				park = (pb.rect as Rect2).get_center()
	if park != Vector2.INF:
		var on := Footsteps.surface_at(plan, park, macro.height_at(park) + 0.3, null)
		_t._check(on == "grass", "audio: footsteps in a park are grass (%s)" % on)
	var car := VehicleBody3D.new()
	_t._check(Footsteps.surface_at(plan, dt, 2.0, car) == "metal", "audio: footsteps on a car roof are metal")
	car.free()
	var player := city.get_tree().get_first_node_in_group("player")
	_t._check(player != null and _footstep_nodes(player) == 1, "audio: the player carries a Footsteps node")

func _footstep_nodes(player: Node) -> int:
	var n := 0
	for c in player.get_children():
		if c is Footsteps:
			n += 1
	return n
