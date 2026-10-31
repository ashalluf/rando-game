extends RefCounted
## The five stars as distinct (WantedEscalation, WantedAudio, WantedTicker, TacticalHelmet) for
## tests/smoke_test.gd. Loaded at run time, so it can name the police classes. The Police node
## stays off except for one direct dispatch at five stars; every unit placed here is taken off
## again, and nothing leans on where an earlier check left the city.
##
## Checks: the switch; the table (caps rise with every star, roadblocks at three, vans at four,
## the agency at five) and the Police node wearing it; which unit each dispatch sends; the
## helicopters per star and the gunship's slot; the agency's truck (a box truck in olive drab,
## lettered, a guard and roof lockers, four aboard) and its trooper (field drab, a carbine, a
## helmet fitted to the head); AirTraffic flying three over the player at five, one armed; the
## siren mix (the trucks' hi-lo, the yelp close in, the wail far out) and the radio's tones; the
## line under the stars; a real dispatch at five stars sending a truck.

var _t: Node
var _tree: SceneTree


func run(t: Node, city: Node3D) -> void:
	_t = t
	_tree = t.get_tree()
	_check(WantedEscalation.enabled == (OS.get_environment("WANTED_ESCALATION") != "0"),
			"WANTED_ESCALATION=0 is the A/B switch (enabled %s)" % WantedEscalation.enabled)
	if not WantedEscalation.enabled:
		return
	var police: Node = city.get_node_or_null("Police")
	if police == null:
		_check(false, "the city has a Police node for the escalation")
		return
	_table(police)
	await _agency_truck(city, police)
	await _helicopters(city)
	await _audio(city, police)
	await _dispatch(police)
	police.call("clear")
	police.set("enabled", false)
	await _ticks(2)


func _check(ok: bool, label: String) -> void:
	_t._check(ok, label)


func _ticks(n: int) -> void:
	for i in n:
		await _tree.physics_frame


func _frames(n: int) -> void:
	for i in n:
		await _tree.process_frame


func _table(police: Node) -> void:
	var rising := true
	for s in range(1, 6):
		rising = rising and WantedEscalation.CRUISERS[s] > WantedEscalation.CRUISERS[s - 1] \
				and WantedEscalation.OFFICERS[s] > WantedEscalation.OFFICERS[s - 1] \
				and WantedEscalation.RADIO_GAP[s] < (WantedEscalation.RADIO_GAP[s - 1] if s > 1 else 999.0)
	_check(rising, "every star brings more cruisers, more officers and a busier radio (%s / %s)" % [str(WantedEscalation.CRUISERS), str(WantedEscalation.OFFICERS)])
	var caps_ok := true
	var was: int = int(police.get("stars"))
	for s in 6:
		police.set("stars", s)
		if not OS.has_feature("web"):
			caps_ok = caps_ok and int(police.call("cruiser_cap")) == WantedEscalation.CRUISERS[s] \
					and int(police.call("officer_cap")) == WantedEscalation.OFFICERS[s]
	police.set("stars", was)
	_check(caps_ok and int(police.get("roadblock_stars")) == 3 and int(police.get("heavy_stars")) == 4,
			"the Police node wears the table: its caps per star, roadblocks from three, vans from four")
	var kinds := {}
	for s in range(1, 6):
		var seen := {}
		for n in 8:
			seen[WantedEscalation.unit_for(s, n)] = int(seen.get(WantedEscalation.unit_for(s, n), 0)) + 1
		kinds[s] = seen
	var U := WantedEscalation.Unit
	_check(kinds[1].keys() == [U.CRUISER] and kinds[3].keys() == [U.CRUISER]
			and int(kinds[4].get(U.VAN, 0)) == 4 and not kinds[4].has(U.TRUCK)
			and int(kinds[5].get(U.TRUCK, 0)) == 4 and kinds[5].has(U.VAN) and kinds[5].has(U.CRUISER),
			"one to three stars send cruisers, four every other a tactical van, five the agency's trucks half the time (%s)" % str(kinds))
	var helis: Array = []
	for s in 6:
		helis.append(WantedEscalation.helicopters(s, 3))
	_check(helis == [0, 0, 0, 1, 2, 3] and WantedEscalation.is_gunship_slot(5, 2) and not WantedEscalation.is_gunship_slot(5, 1)
			and not WantedEscalation.is_gunship_slot(4, 2),
			"the helicopter at three stars, a second at four, the gunship as the third at five (%s)" % str(helis))
	var calls := {}
	for s in range(1, 6):
		calls[WantedEscalation.call_for(s)] = true
	_check(calls.size() == 5 and WantedEscalation.call_for(5).contains(WantedEscalation.AGENCY), "each star has its own line under the stars, five names the agency")


## The agency's truck and a trooper out of it, on a deck high over the street.
func _agency_truck(city: Node3D, police: Node) -> void:
	var player := _tree.get_first_node_in_group("player") as Node3D
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var truck := PoliceCar.make(false, rng, true)
	truck.position = player.global_position + Vector3(0.0, 320.0, 0.0)
	city.add_child(truck)
	await _ticks(2)
	var gear := truck.get_node_or_null("AgencyGear") as MeshInstance3D
	var paint_ok := false
	var paint_seen := Color.BLACK
	for mi in truck.find_children("*", "MeshInstance3D", true, false):
		for si in (mi as MeshInstance3D).get_surface_override_material_count():
			var m := (mi as MeshInstance3D).get_surface_override_material(si) as ShaderMaterial
			if m and m.get_shader_parameter("stripe_mode") != null and int(m.get_shader_parameter("stripe_mode")) != 5:
				var c: Variant = m.get_shader_parameter("paint")
				var col := Color(c.x, c.y, c.z) if c is Vector3 else (c as Color if c is Color else Color.BLACK)
				if c != null:
					paint_seen = col
				if col.g > col.b and col.g >= col.r and col.v < 0.4 and col.v > 0.05:
					paint_ok = true
	var lettered := OS.has_feature("web") or _text_meshes(truck) >= 2
	_check(truck.body_type == Vehicle.BodyType.BOX_TRUCK and truck.agency and truck.crew_aboard == 4 and truck.crew_alive == 4
			and String(truck.get_meta("fleet", "")) == WantedEscalation.AGENCY,
			"the agency's unit is a box truck with four aboard, its fleet the invented %s" % WantedEscalation.AGENCY)
	_check(paint_ok and lettered and gear != null and gear.mesh != null and truck.get_node_or_null("LightBar") != null,
			"the truck is olive drab, lettered both sides, with a grille guard, roof lockers and a light bar (paint %s %s, lettered %s, gear %s)" % [paint_ok, paint_seen, lettered, gear != null])
	_check(truck.mass > 4000.0, "the truck keeps a truck's mass (%.0f kg), not a cruiser's" % truck.mass)
	# A trooper: field drab, a carbine, the helmet.
	var o := PoliceOfficer.new()
	o.setup_officer(police as Police, truck, 0, false, 4321)
	# Read straight after it enters the tree (_ready builds the body): a trooper hanging over
	# nothing is gone a tick or two later.
	o.position = truck.position + Vector3(2.5, 0.0, 0.0)
	city.add_child(o)
	var drab := false
	for mi in o.find_children("*", "MeshInstance3D", true, false):
		var ov := (mi as MeshInstance3D).material_override as ShaderMaterial
		if ov and ov.get_shader_parameter("cloth_hue") != null and absf(float(ov.get_shader_parameter("cloth_hue")) - TacticalHelmet.FIELD_TOP.h) < 0.02:
			drab = true
	var helmet := o.find_child("Helmet", true, false) as MeshInstance3D
	var gun := o.get("_gun") as PoliceGun
	_check(o.agency and o.heavy and drab and gun != null and gun.carbine,
			"a trooper wears field drab and carries a carbine (drab %s)" % drab)
	_check(helmet != null and helmet.mesh != null and o.find_child("Hat", true, false) == null,
			"a trooper wears the ballistic helmet, not the peaked cap")
	if is_instance_valid(o):
		o.queue_free()
	truck.queue_free()
	# The helmet itself, from the rig's measured head: a full shell the size of a helmet.
	var rig := "res://assets/models/crowd_a.glb"
	var arrays := TacticalHelmet.build_surface(CrowdHat.head_for(rig), true).commit_to_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var box := AABB(verts[0], Vector3.ZERO)
	for v in verts:
		box = box.expand(v)
	_check(verts.size() > 2000 and box.size.x > 0.18 and box.size.x < 0.32 and box.size.z > 0.20 and box.size.z < 0.36,
			"the helmet is a shell round the head (%d vertices, %.2f x %.2f x %.2f m)" % [verts.size(), box.size.x, box.size.y, box.size.z])
	await _ticks(2)


## AirTraffic at five stars: three police helicopters over the player, the third armed.
func _helicopters(city: Node3D) -> void:
	var air: Node = city.get_node_or_null("AirTraffic")
	if air == null:
		_check(true, "no AirTraffic in this city: the gunship is not checked")
		return
	var before: Array = air.call("helicopters", Helicopter.Role.POLICE)
	var was := int(air.get("forced_stars"))
	air.set("forced_stars", 5)
	air.set("stars", 5)
	for i in 4:
		air.set("_police_respawn_left", 0.0)
		air.call("_order_police", 0.1)
	var pursuing := 0
	var armed := 0
	var pods := false
	var wide := false
	for h: Helicopter in air.call("helicopters", Helicopter.Role.POLICE):
		if h.task == "pursuit":
			pursuing += 1
		if h.has_meta("gunship"):
			armed += 1
			pods = h.find_child("GunshipPods", true, false) != null
			wide = is_equal_approx(h.searchlight_angle, WantedEscalation.GUNSHIP_LIGHT_ANGLE)
	_check(pursuing == 3 and armed == 1 and pods and wide,
			"five stars put three helicopters over the player, one a gunship with pods and the wide light (%d, %d armed)" % [pursuing, armed])
	air.set("forced_stars", 3)
	air.set("stars", 3)
	air.call("_order_police", 0.1)
	var at_three := 0
	for h: Helicopter in air.call("helicopters", Helicopter.Role.POLICE):
		if h.task == "pursuit":
			at_three += 1
	_check(at_three == 1, "three stars keep one helicopter on the player (%d)" % at_three)
	for h: Helicopter in air.call("helicopters", Helicopter.Role.POLICE):
		if not before.has(h):
			h.remove()
	air.set("forced_stars", was)
	await _ticks(2)


## The siren mix, the radio's tones and the line under the stars.
func _audio(city: Node3D, police: Node) -> void:
	var audio := police.get_node_or_null("WantedAudio") as WantedAudio
	if not WantedAudio.enabled:
		_check(audio == null, "WANTED_AUDIO=0 leaves the radio and the siren mix out")
		return
	_check(audio != null, "the Police node carries the siren mix and the radio (WantedAudio)")
	if audio == null:
		return
	var hilo := WantedAudio.stream("hilo") as AudioStreamWAV
	var lengths: Array = []
	for s in range(1, 6):
		var a := WantedAudio.stream("alert_%d" % s) as AudioStreamWAV
		lengths.append(a.data.size() if a else 0)
	var call := WantedAudio.stream("call_3") as AudioStreamWAV
	var secs := float(call.data.size()) / 2.0 / WantedAudio.MIX_RATE if call else 0.0
	_check(hilo != null and hilo.loop_mode == AudioStreamWAV.LOOP_FORWARD and lengths[4] > lengths[3] and lengths[3] > lengths[0] and lengths[0] > 0
			and secs > 0.9 and secs < 2.8,
			"the hi-lo loops, each star's alert tone is its own and grows, a call is a second or two (%s, %.1f s)" % [str(lengths), secs])
	# Three units by the player: a truck and a cruiser close, a cruiser far out.
	police.call("_ensure_refs")
	var player := _tree.get_first_node_in_group("player") as Node3D
	var rng := RandomNumberGenerator.new()
	rng.seed = 91
	var units: Array = []
	for spec: Array in [[true, 30.0], [false, 40.0], [false, 260.0]]:
		var car := PoliceCar.make(false, rng, spec[0])
		car.position = player.global_position + Vector3(float(spec[1]), 1.0, 0.0)
		city.add_child(car)
		units.append(car)
	await _ticks(2)
	var list: Array = police.get("cruisers")
	list.append_array(units)
	police.set("stars", 5)
	audio._mix_sirens(5)
	var truck_voice: AudioStream = (units[0] as PoliceCar).siren_player().stream
	var v := audio.voices.duplicate()
	_check(truck_voice == WantedAudio.stream("hilo") and int(v.get("hilo", 0)) == 1 and int(v.get("yelp", 0)) == 1 and int(v.get("wail", 0)) == 1,
			"five stars: the truck plays its hi-lo, the cruiser close in the yelp, the one far out the wail (%s)" % str(v))
	police.set("stars", 2)
	audio._mix_sirens(2)
	_check(int(audio.voices.get("yelp", 0)) == 1 and int(audio.voices.get("hilo", 0)) == 1,
			"two stars: the yelp only well inside the close range (%s)" % str(audio.voices))
	for car in units:
		list.erase(car)
		car.queue_free()
	police.set("stars", 0)
	audio._last_stars = 0
	# The radio and the line under the stars announce a new level.
	police.call("set_wanted", 4)
	await _frames(3)
	var ticker: Node = city.get_node_or_null("DebugHud/WantedHud/WantedTicker")
	_check(audio.last_radio == "alert_4", "a new star is announced on the radio by its own tone (%s)" % audio.last_radio)
	_check(ticker != null and String(ticker.get("shown")) == WantedEscalation.call_for(4),
			"the line under the stars names what the star brings (%s)" % (String(ticker.get("shown")) if ticker else "no ticker"))
	police.call("clear")
	await _frames(2)
	_check(audio.last_radio == "clear", "the stars clearing are on the radio too (%s)" % audio.last_radio)


## A real dispatch at five stars sends one of the agency's trucks.
func _dispatch(police: Node) -> void:
	police.call("clear")
	police.set("enabled", true)
	police.call("set_wanted", 5)
	var sent_truck := false
	for attempt in 16:
		# The pattern's truck slots: 0 and 2 of every four.
		police.set("dispatched", 4 * attempt)
		police.call("_dispatch")
		for c in police.get("cruisers"):
			if is_instance_valid(c) and (c as PoliceCar).agency:
				sent_truck = true
		if sent_truck:
			break
	await _ticks(3)
	var ok := false
	for c in police.get("cruisers"):
		if is_instance_valid(c) and (c as PoliceCar).agency and (c as PoliceCar).body_type == Vehicle.BodyType.BOX_TRUCK:
			ok = true
	_check(sent_truck and ok, "a dispatch at five stars sends one of the agency's trucks onto the street")
	police.call("clear")
	police.set("enabled", false)


## Lettering on a vehicle: its MeshInstance3Ds wearing a TextMesh (a second sibling of one name is
## renamed by the tree, so they are counted by what they draw).
func _text_meshes(car: Node) -> int:
	var n := 0
	for mi in car.find_children("*", "MeshInstance3D", true, false):
		if (mi as MeshInstance3D).mesh is TextMesh:
			n += 1
	return n
