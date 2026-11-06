extends RefCounted
## The car radio (CarRadio, scripts/vehicles/car_radio.gd; RadioHud, scripts/ui/radio_hud.gd) for
## tests/smoke_test.gd. Loaded at run time, so it compiles after the autoloads. Staged on its own
## deck 300 m over the street (nothing of the city's traffic, crowd or police near it).
## Checks: four stations with original names, three tracks and an ident each, every file loading
## with a length; the dial's order (four stations, OFF, round again); the loop arithmetic; a car's
## station is a hash of the car and cruisers come on with the radio off; the files stay small;
## the Radio bus sends to Game (the slow-motion muffle); entering a car tunes its station, plays
## it on the Radio bus and raises the card; Q (radio_next), the mouse wheel and step() move the
## dial without touching the weapons, the car keeps what was picked; every station stays on air;
## a station's music moves on to the next segment at the end of one; leaving the car fades it out.

var _t: Node
var _tree: SceneTree
var _city: Node3D
var _deck: StaticBody3D
var _cars: Array = []
var _top: Vector3

## The radio's files may not grow past this (MB): it ships in a macOS app and a web page.
const BUDGET_MB := 8.0


func run(t: Node, city: Node3D) -> void:
	_t = t
	_tree = t.get_tree()
	_city = city
	_pure()
	if not CarRadio.enabled:
		_check(true, "CarRadio is off (CAR_RADIO=0): only the pure checks")
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
	player.global_position = _top + Vector3(0.0, 1.2, 20.0)
	player.velocity = Vector3.ZERO
	await _ticks(3)

	var car := _car(Vehicle.BodyType.SEDAN, Vector2(0.0, 0.0))
	await _ticks(3)
	var radio := CarRadio.instance()
	_check(radio != null and radio.is_inside_tree(), "CarRadio is made by the first car")
	if radio != null:
		_check(_tree.root.get_children().filter(func(n: Node) -> bool: return n is CarRadio).size() == 1, "and only once")
		_bus()
		await _drive(player, car, radio)

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
	var st: Array = CarRadio.STATIONS
	_check(st.size() == 4, "four radio stations (%d)" % st.size())
	var ids := {}
	var names := {}
	var bad := PackedStringArray()
	for s: Dictionary in st:
		ids[s.id] = true
		names[s.name] = true
		if s.tracks.size() != 3:
			bad.append("%s: %d tracks" % [s.id, s.tracks.size()])
		for tr: Array in s.tracks:
			var a := _stream(tr[0])
			if a == null or a.get_length() < 30.0:
				bad.append(tr[0])
		var ident := _stream("ident_" + s.id)
		if ident == null or ident.get_length() < 2.0 or ident.get_length() > 8.0:
			bad.append("ident_" + s.id)
	var stat := _stream("static")
	if stat == null:
		bad.append("static")
	_check(ids.size() == 4 and names.size() == 4, "the stations' ids and names are distinct")
	_check(bad.is_empty(), "every station has three tracks over 30 s and an ident of 2-8 s, and the static loads (%s)" % ",".join(bad))
	# The dial: 0 -> 1 -> 2 -> 3 -> OFF -> 0, and back.
	var seq: Array = []
	var s := 0
	for i in 5:
		s = CarRadio.step_from(s, 1)
		seq.append(s)
	_check(seq == [1, 2, 3, CarRadio.OFF, 0], "next walks the four stations, then OFF, then round (%s)" % str(seq))
	_check(CarRadio.step_from(0, -1) == CarRadio.OFF and CarRadio.step_from(CarRadio.OFF, -1) == 3, "previous goes the other way")
	# The loop.
	var at: Array = CarRadio.segment_at([5.0, 100.0, 5.0, 90.0], 107.0)
	var wrap: Array = CarRadio.segment_at([5.0, 100.0, 5.0, 90.0], 203.0)
	_check(at[0] == 2 and absf(float(at[1]) - 2.0) < 1e-6 and wrap[0] == 0 and absf(float(wrap[1]) - 3.0) < 1e-6,
		"segment_at finds the segment and the time in it, and wraps the loop")
	var offs := []
	for i in st.size():
		offs.append(CarRadio.start_offset(i, 400.0))
	_check(offs.all(func(o: float) -> bool: return o >= 0.0 and o < 400.0) and CarRadio.start_offset(1, 400.0) == offs[1],
		"each station starts its loop at a hash of the station")
	# Files stay small.
	var bytes := 0
	for f: String in DirAccess.get_files_at(CarRadio.DIR):
		if f.ends_with(".ogg"):
			var fa := FileAccess.open(CarRadio.DIR + f, FileAccess.READ)
			if fa:
				bytes += fa.get_length()
	# Exported builds keep only the imported copies; the source files are what the repo carries.
	_check(bytes == 0 or bytes < int(BUDGET_MB * 1048576.0), "the radio's files are under %.0f MB (%.2f MB)" % [BUDGET_MB, bytes / 1048576.0])


func _bus() -> void:
	var idx := AudioServer.get_bus_index(CarRadio.BUS)
	_check(idx >= 0 and AudioServer.get_bus_send(idx) == &"Game", "the Radio bus sends to Game (muffled by slow motion with everything else)")
	var hp := false
	var lp := false
	if idx >= 0:
		for i in AudioServer.get_bus_effect_count(idx):
			var e := AudioServer.get_bus_effect(idx, i)
			hp = hp or e is AudioEffectHighPassFilter
			lp = lp or e is AudioEffectLowPassFilter
	_check(hp and lp, "and sounds like a car speaker (a high-pass and a low-pass)")


func _drive(player: Player, car: Vehicle, radio: CarRadio) -> void:
	var expect := CarRadio.default_for(car)
	_check(expect == CarRadio.default_for(car) and expect >= 0 and expect < 4, "a car's station is a hash of the car (%d)" % expect)
	var cop := Vehicle.new()
	cop.add_to_group("police_car")
	_check(CarRadio.default_for(cop) == CarRadio.OFF, "a cruiser comes on with the radio off")
	cop.free()
	_check(radio.car == null and not radio.playing(), "on foot the radio is silent")

	var tunes0 := radio.tunes
	player.enter_vehicle(car)
	var ok := await _until(func() -> bool: return radio.car == car and radio.playing(), 90)
	_check(ok and radio.station == expect, "entering the car tunes its station and plays (station %d, playing %s)" % [radio.station, str(radio.playing())])
	_check(radio.tunes > tunes0 and radio.card_kind == "tune" and radio.card_age < 3.0, "and asks for the station card")
	var music: AudioStreamPlayer = radio.get_node_or_null("Music")
	_check(music != null and music.bus == CarRadio.BUS, "the music plays on the Radio bus")
	var np := radio.now_playing()
	_check(not np.is_empty() and String(np.title) != "" and String(np.artist) != "", "now_playing() names the song on air (%s)" % str(np.get("title", "")))
	var hud: Node = _tree.root.find_child("RadioHud", true, false)
	if hud != null:
		var shown := await _until(func() -> bool: return hud.showing(), 30)
		_check(shown, "the HUD's station card comes up")
	else:
		_check(true, "no HUD in this scene (the card is not checked)")

	# The dial: step(), Q and the wheel; the weapons do not change.
	var wm: Node = player.get("weapon_manager")
	var gun: Variant = wm.get("current") if wm else null
	var s0 := radio.station
	radio.step(1)
	_check(radio.station == CarRadio.step_from(s0, 1) and int(car.get_meta("radio_station", -9)) == radio.station,
		"step() moves the dial and the car keeps the pick")
	var s1 := radio.station
	Input.action_press("radio_next")
	await _frames(3)
	Input.action_release("radio_next")
	await _frames(2)
	_check(radio.station == CarRadio.step_from(s1, 1), "Q (radio_next) moves the dial (%d -> %d)" % [s1, radio.station])
	var s2 := radio.station
	Input.action_press("prev_weapon")
	await _frames(3)
	Input.action_release("prev_weapon")
	await _frames(2)
	_check(radio.station == CarRadio.step_from(s2, -1), "the mouse wheel moves it back (%d -> %d)" % [s2, radio.station])
	_check(wm == null or wm.get("current") == gun, "and the wheel does not change the gun while driving")
	# Make sure a station is on for the rest.
	if radio.station == CarRadio.OFF:
		radio.step(1)
	await _until(func() -> bool: return radio.playing(), 60)
	var on := radio.station

	# Every station stays on air: another station's clock moves on while this one plays.
	var other := (on + 1) % 4
	var c0 := radio.clock_of(other)
	await _frames(20)
	var moved := fposmod(radio.clock_of(other) - c0, radio.loop_length(other))
	_check(moved > 0.05 and moved < 5.0, "a station nobody listens to stays on air (%.2f s on)" % moved)

	# The end of a segment: put the clock past the first segment's end and the next one plays.
	var lens := radio.lengths_of(on)
	radio._clock[on] = float(lens[0]) + 1.0
	radio._music.stop()
	var next_ok := await _until(func() -> bool: return radio._seg == 1 and radio.playing(), 60)
	_check(next_ok, "past the end of a segment the next one plays (segment %d)" % radio._seg)

	# Out of the car: the music fades away; back in, the car still has the station picked.
	player.exit_vehicle()
	var quiet := await _until(func() -> bool: return radio.car == null and not radio.playing(), 120)
	_check(quiet, "leaving the car fades the radio out")
	player.enter_vehicle(car)
	await _until(func() -> bool: return radio.car == car, 60)
	_check(radio.station == on, "back in, the car is on the station picked (%d)" % radio.station)
	player.exit_vehicle()
	await _ticks(5)


func _stream(file: String) -> AudioStream:
	var p := CarRadio.DIR + file + ".ogg"
	return load(p) as AudioStream if ResourceLoader.exists(p) else null


func _car(type: Vehicle.BodyType, at: Vector2) -> Vehicle:
	var car := Vehicle.new()
	car.setup(type, Color(0.1, 0.2, 0.6), Vehicle.Addon.NONE)
	car.position = _city.to_local(_top + Vector3(at.x, 1.2, at.y))
	_city.add_child(car)
	_cars.append(car)
	return car


func _build_deck() -> void:
	_deck = StaticBody3D.new()
	_deck.collision_layer = 1
	_deck.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200.0, 1.0, 200.0)
	shape.shape = box
	_deck.add_child(shape)
	_city.add_child(_deck)
	_deck.global_position = _top - Vector3(0.0, 0.5, 0.0)


func _until(cond: Callable, max_frames: int) -> bool:
	for i in max_frames:
		if cond.call():
			return true
		await _tree.process_frame
	return cond.call()


func _ticks(n: int) -> void:
	for i in n:
		await _tree.physics_frame


func _frames(n: int) -> void:
	for i in n:
		await _tree.process_frame


func _check(ok: bool, label: String) -> void:
	_t._check(ok, label)
