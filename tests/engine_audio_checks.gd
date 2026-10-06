extends RefCounted
## Engine audio (EngineAudio, scripts/vehicles/engine_audio.gd) for tests/smoke_test.gd. Loaded at
## run time, so it compiles after the autoloads. On a deck 300 m over the street, like the driving
## effects' checks. Checks: every body type has a profile and every profile's five loops, the
## turbo, the blow-off and the beeper are loaded with a loudness entry; the gearbox (pure) climbs
## through the gears at full throttle without passing the redline, shifts early on a light
## throttle, idles standing, revs freely in the air, coasts on the off-load loop; the layers are
## equal power; the node is made once; the player's car gets a voice and the Vehicle's own loop
## stays quiet; flooring it revs up and shifts; a running truck near the camera gets a diesel voice
## and beeps rolling backward; a car's horn is always its own take and pitch, trucks deeper.

var _t: Node
var _tree: SceneTree
var _city: Node3D
var _deck: StaticBody3D
var _cars: Array = []
var _top: Vector3


func run(t: Node, city: Node3D) -> void:
	_t = t
	_tree = t.get_tree()
	_city = city
	_pure()
	if not EngineAudio.enabled:
		_check(true, "EngineAudio is off (ENGINE_AUDIO=0): only the pure checks")
		return
	var ws: Node = _tree.root.get_node("/root/WorldState")
	var player := _tree.get_first_node_in_group("player") as Player
	if player.is_driving():
		player.exit_vehicle()
	var police: Node = city.get_node_or_null("Police")
	var police_was: Variant = police.get("enabled") if police else null
	if police:
		police.set("enabled", false)
	var home: Vector3 = ws.to_world(player.global_position)
	_top = player.global_position + Vector3(0.0, 300.0, 0.0)
	_build_deck()
	player.global_position = _top + Vector3(0.0, 1.2, 30.0)
	player.velocity = Vector3.ZERO
	await _ticks(3)

	var car := _car(Vehicle.BodyType.SEDAN, Vector2(0.0, 0.0))
	await _ticks(3)
	var ea := EngineAudio.instance()
	_check(ea != null and ea.is_inside_tree(), "EngineAudio is made by the first car")
	if ea != null:
		_check(_tree.root.get_children().filter(func(n: Node) -> bool: return n is EngineAudio).size() == 1, "and only once")
		await _player_car(player, car, ea)
		await _truck(player, ea)
		_horns(car)

	if player.is_driving():
		player.exit_vehicle()
	for c in _cars:
		if is_instance_valid(c):
			c.queue_free()
	_deck.queue_free()
	player.global_position = ws.to_local(home)
	player.velocity = Vector3.ZERO
	if police:
		police.set("enabled", police_was)
	await _ticks(3)


func _pure() -> void:
	var missing := PackedStringArray()
	for t in Vehicle.BodyType.values():
		if not EngineAudio.PROFILES.has(EngineAudio.profile_for_type(t)):
			missing.append(Vehicle.BodyType.keys()[t])
	_check(missing.is_empty(), "every body type has an engine profile (%s)" % ",".join(missing))
	_check(EngineAudio.profile_for_type(Vehicle.BodyType.SEMI) == "diesel" and EngineAudio.profile_for_type(Vehicle.BodyType.BUS) == "bus"
			and EngineAudio.profile_for_type(Vehicle.BodyType.HYPER) == "v12" and EngineAudio.profile_for_type(Vehicle.BodyType.SEDAN) == "four",
			"semis are diesels, buses buses, hypercars V12s, sedans fours")
	var unloaded := PackedStringArray()
	var names: Array = ["eng_turbo", "eng_blowoff", "eng_beeper"]
	for p: String in EngineAudio.PROFILES:
		for l: String in EngineAudio.LAYERS:
			names.append("eng_%s_%s" % [p, l])
	for n: String in names:
		if not Sfx.SAMPLES.has(n) or not Sfx.SAMPLE_LOUDNESS_DB.has(n) or not ResourceLoader.exists(Sfx.AUDIO_DIR + Sfx.SAMPLES[n][0]):
			unloaded.append(n)
		elif n != "eng_blowoff" and not (n in Sfx.LOOPING):
			unloaded.append(n + "(loop)")
	_check(unloaded.is_empty(), "every engine loop, the turbo, blow-off and beeper ship with a loudness and loop flag (%s)" % ",".join(unloaded))
	var t: Array = Sfx.take("eng_v8_mid")
	_check(not t.is_empty() and t[0] is AudioStreamOggVorbis and (t[0] as AudioStreamOggVorbis).loop, "an engine loop loads as a looping Ogg")

	for name: String in EngineAudio.PROFILES:
		var prof: Dictionary = EngineAudio.PROFILES[name]
		var st := EngineAudio.new_state(prof)
		var v := 0.0
		var top_rpm := 0.0
		var max_gear := 0
		for i in 1200:
			EngineAudio.step_engine(st, prof, v, 1.0, false, false, 1.0 / 60.0)
			v = minf(v + float(prof.top) / 12.0 / 60.0, float(prof.top))
			top_rpm = maxf(top_rpm, float(st.rpm))
			max_gear = maxi(max_gear, int(st.gear))
		_check(top_rpm <= float(prof.redline) + 0.5 and max_gear == int(prof.gears) - 1,
				"%s: full throttle reaches top gear (%d of %d) and never passes the redline (%d of %d rpm)" % [
				name, max_gear + 1, int(prof.gears), int(top_rpm), int(prof.redline)])
		# A light throttle shifts sooner.
		var light := EngineAudio.new_state(prof)
		var full := EngineAudio.new_state(prof)
		var speed := float(prof.first) * 0.75
		for i in 120:
			EngineAudio.step_engine(light, prof, speed, 0.3, false, false, 1.0 / 60.0)
			EngineAudio.step_engine(full, prof, speed, 1.0, false, false, 1.0 / 60.0)
		_check(int(light.gear) > int(full.gear) or (int(light.gear) == int(full.gear) and float(light.rpm) < float(full.rpm)),
				"%s: a light throttle is in a higher gear or lower revs than a full one at the same speed" % name)
		var rest := EngineAudio.new_state(prof)
		var air := EngineAudio.new_state(prof)
		for i in 180:
			EngineAudio.step_engine(rest, prof, 0.0, 0.0, false, false, 1.0 / 60.0)
			EngineAudio.step_engine(air, prof, 30.0, 0.0, true, true, 1.0 / 60.0)
		_check(absf(float(rest.rpm) - float(prof.rpm[0])) < 30.0 and float(air.rpm) > float(prof.redline) * 0.9,
				"%s: idles standing (%d rpm), revs out on boost in the air (%d)" % [name, int(rest.rpm), int(air.rpm)])
		var worst := 0.0
		for r in range(int(prof.rpm[0]), int(prof.redline), 97):
			for load: float in [0.0, 0.4, 1.0]:
				var g := EngineAudio.layer_gains(prof, float(r), load)
				var e := 0.0
				for x in g:
					e += x * x
				worst = maxf(worst, absf(e - 1.0))
		_check(worst < 0.02, "%s: the layer crossfade is equal power everywhere (worst %.3f)" % [name, worst])
	var coast := EngineAudio.layer_gains(EngineAudio.PROFILES.four, 3500.0, 0.0)
	_check(coast[4] > 0.95, "off the throttle above idle the coasting loop carries it")


func _player_car(player: Player, car: Vehicle, ea: EngineAudio) -> void:
	player.enter_vehicle(car)
	await _ticks(20)
	var v: Variant = _voice_of(ea, car)
	_check(v != null and v.profile == "four", "the player's sedan has a voice with the four")
	_check(car._engine_sound == null or not car._engine_sound.playing, "and the Vehicle's own engine loop stays quiet")
	if v == null:
		return
	var idle_playing: bool = v._players[0].playing
	_check(idle_playing and absf(float(v.st.rpm) - 800.0) < 120.0, "standing: the idle loop plays at idle (%d rpm)" % int(v.st.rpm))
	Input.action_press("move_forward")
	Input.action_press("boost")
	var rpm_max := 0.0
	var shifts0 := int(v.st.shifts)
	for i in 150:
		await _tree.physics_frame
		rpm_max = maxf(rpm_max, float(v.st.rpm))
	Input.action_release("move_forward")
	Input.action_release("boost")
	_check(rpm_max > 3500.0 and int(v.st.shifts) > shifts0, "flooring it revs up (%d rpm) and shifts (%d)" % [int(rpm_max), int(v.st.shifts) - shifts0])
	var high_played: bool = v._players[2].playing or v._players[3].playing
	_check(high_played or float(v.st.rpm) < 3000.0, "the upper loops take over as it revs")
	player.exit_vehicle()
	await _ticks(15)
	_check(_voice_of(ea, car) == null, "an empty parked car has no engine")
	# Back by the start, so the camera is near the truck that comes next.
	player.global_position = _top + Vector3(0.0, 1.2, 30.0)
	player.velocity = Vector3.ZERO
	await _ticks(10)


func _truck(player: Player, ea: EngineAudio) -> void:
	var truck := _car(Vehicle.BodyType.BOX_TRUCK, Vector2(8.0, 25.0))
	await _ticks(5)
	# Somebody in the cab (a car alarm also counts as running; here the hazards stand in).
	truck.alarm_left = 30.0
	for i in 20:
		await _tree.physics_frame
	var v: Variant = _voice_of(ea, truck)
	_check(v != null and v.profile == "diesel", "a running box truck by the camera gets a diesel voice")
	if v != null:
		var beeped := false
		for i in 40:
			truck.linear_velocity = truck.global_basis.z * 2.5 # backing up (+Z is the tail)
			await _tree.physics_frame
			beeped = beeped or (v.beeping and v._beeper.playing)
		_check(beeped, "and its reversing alarm sounds rolling backward")
		_check(EngineAudio.voiced(truck), "a voiced truck tells Ambience to drop its diesel loop")
	truck.alarm_left = 0.0


func _horns(car: Vehicle) -> void:
	var a := EngineAudio.horn_spec(car, false)
	var b := EngineAudio.horn_spec(car, false)
	_check(a == b, "a car's horn is always the same take and pitch")
	var truck := _car(Vehicle.BodyType.BOX_TRUCK, Vector2(-10.0, 40.0))
	_check(float(EngineAudio.horn_spec(truck, false)[2]) < float(a[2]), "a truck's horn is deeper than a car's")
	var semi := _car(Vehicle.BodyType.SEMI, Vector2(-20.0, 40.0))
	_check(String(EngineAudio.horn_spec(semi, false)[0]) == "fire_horn", "a semi blows the air horn")
	_check(EngineAudio.horn(car), "horn() plays")
	var takes := {}
	for i in 12:
		var c := Vehicle.new()
		c.look_seed = 1000 + i * 7919
		takes[str(EngineAudio.horn_spec(c, false))] = true
		c.free()
	_check(takes.size() >= 4, "cars do not all share one horn (%d kinds in 12)" % takes.size())


func _voice_of(ea: EngineAudio, car: Vehicle) -> Variant:
	for v in ea._voices:
		if v.car == car:
			return v
	return null


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
	box.size = Vector3(400.0, 1.0, 400.0)
	shape.shape = box
	_deck.add_child(shape)
	_city.add_child(_deck)
	_deck.global_position = _top - Vector3(0.0, 0.5, 0.0)


func _car(type: Vehicle.BodyType, at: Vector2) -> Vehicle:
	var car: Vehicle
	if BigVehicles.is_big(type):
		car = BigVehicles.make(type, 3)
	else:
		car = Vehicle.new()
		car.setup(type, Color(0.6, 0.1, 0.1), Vehicle.Addon.NONE)
	car.position = _city.to_local(_top + Vector3(at.x, 1.2, at.y))
	_city.add_child(car)
	_cars.append(car)
	return car
