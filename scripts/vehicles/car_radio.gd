class_name CarRadio
extends Node
## The player's car radio: four invented stations, each a loop of CC0 / public-domain tracks and
## its own synthesised ident (assets/audio/radio/, built by tools/radio/make_radio.py; sources in
## docs/ASSETS.md), tuned with `radio_next` / `radio_prev` (Q / pad d-pad right and left) or the
## mouse wheel while driving, with a station card on the HUD (RadioHud).
##
## The stations are ON AIR whether anybody listens or not: each has its own clock running round its
## playlist (ident, track, ident, track, ...), started at a hash of the station, so tuning in lands
## in the middle of a song, and coming back to a station later finds it further on, as the radio
## does. While a station plays its clock follows the stream's own position, and the next segment
## starts when the clock passes the end of the one playing.
##
## Which station a car is on is a hash of the car (police cruisers and emergency units come on with
## the radio off: they have their own); a station the player picks stays with that car (meta
## `radio_station`). Tuning plays a short burst of static, the music fades in and out on entering
## and leaving the car, and a wreck's radio is dead.
##
## Sound: one non-positional AudioStreamPlayer on the `Radio` bus, which sends to `Game`, so the
## slow-motion and blast muffles act on the music like on everything else (and
## AudioServer.playback_speed_scale slows it with the wheel). The bus is a car speaker: a high-pass
## at `speaker_low_hz`, a low-pass at `speaker_high_hz` (FM stops at 15 kHz) and a gentle
## compressor. Web builds skip bus effects and play the plain mix.
##
## One instance under the tree root, made by the first Vehicle (ensure()), like EngineAudio.
## `CAR_RADIO=0` in the environment turns it off (the A/B: no node, no HUD card).

## Off with CAR_RADIO=0.
static var enabled: bool = OS.get_environment("CAR_RADIO") != "0"
static var _inst: CarRadio

const DIR := "res://assets/audio/radio/"
const BUS := &"Radio"
const OFF := -1

## The four stations. Names, slogans, track titles and artists are invented (the real sources and
## their authors are credited in docs/ASSETS.md). `tracks`: [file, title, artist].
const STATIONS := [
	{"id": "velvet", "name": "VELVET HOUR", "freq": "88.3", "genre": "Classical",
		"slogan": "Classical for the long way home", "color": Color(0.78, 0.62, 1.0),
		"tracks": [["velvet_0", "Waltz in D-flat Major", "Mirela Ostrova"],
			["velvet_1", "Waltz in G-flat Major", "Mirela Ostrova"],
			["velvet_2", "Aria da Capo", "Henrik Saalberg"]]},
	{"id": "palm", "name": "PALM STATIC", "freq": "97.1", "genre": "Lo-fi beats",
		"slogan": "Beats to idle in traffic to", "color": Color(1.0, 0.62, 0.5),
		"tracks": [["palm_0", "Window Seat", "kelpwave"],
			["palm_1", "Cat Cafe Afternoon", "Lune Parade"],
			["palm_2", "Second Cup", "Lune Parade"]]},
	{"id": "neon", "name": "NEON FREEWAY", "freq": "104.5", "genre": "Synth",
		"slogan": "Chrome, synths and the long night drive", "color": Color(0.36, 0.9, 1.0),
		"tracks": [["neon_0", "Sodium Lights", "VXN Drive"],
			["neon_1", "Moonlight Overdrive", "Chrome Arcade"],
			["neon_2", "Red Line Rush", "Chrome Arcade"]]},
	{"id": "tiki", "name": "TIKI SUNSET", "freq": "92.7", "genre": "Lounge",
		"slogan": "Exotica and bossa till the sun goes down", "color": Color(1.0, 0.78, 0.32),
		"tracks": [["tiki_0", "Lagoon Lanterns", "The Kona Swizzle Trio"],
			["tiki_1", "Gone to the Pier", "Marlin Martini"],
			["tiki_2", "Late August Swells", "Sal & the Sandbars"]]},
]

## Music level, dB (the tracks are levelled to -17 LUFS by make_radio.py).
@export var radio_db: float = -9.0
## Fade in on entering a car / out on leaving it (s).
@export var fade_in: float = 0.8
@export var fade_out: float = 0.35
## The tuning burst: its level (dB) and how long the music waits behind it (s).
@export var static_db: float = -16.0
@export var tune_delay: float = 0.16
## The car speaker on the Radio bus.
@export var speaker_low_hz: float = 70.0
@export var speaker_high_hz: float = 14000.0
## How long the station card stays up after a tune or a new song (real s).
@export var card_seconds: float = 4.0

## The tuned station (OFF when the radio is off or nobody is driving).
var station: int = OFF
## The car whose radio this is (the player's), or null.
var car: Vehicle
## Real seconds since the card was last asked for (RadioHud fades it by this).
var card_age: float = 1e9
## What the card shows: "tune" (station changed / entered) or "song" (a new song started).
var card_kind: String = "tune"
## Tunes since load (the checks).
var tunes: int = 0

var _music: AudioStreamPlayer
var _static: AudioStreamPlayer
## Per station: [AudioStream, length, start, is_track, track index] per segment, and the loop length.
var _segs: Array = []
var _len: PackedFloat64Array = PackedFloat64Array()
## Per station: seconds into its loop.
var _clock: PackedFloat64Array = PackedFloat64Array()
var _seg: int = -1 # segment the music player holds (of `station`)
var _hold: float = 0.0 # music waits behind the static (s)
var _level: float = 0.0 # 0..1 fade


## Makes the one instance, the first time a car enters the tree.
static func ensure(from: Node) -> void:
	if not enabled or (_inst != null and is_instance_valid(_inst)):
		return
	var tree := from.get_tree()
	if tree == null:
		return
	_inst = CarRadio.new()
	_inst.name = "CarRadio"
	tree.root.add_child.call_deferred(_inst)


static func instance() -> CarRadio:
	return _inst if _inst != null and is_instance_valid(_inst) else null


## The station a car comes on with: a hash of the car; cruisers and emergency units are off.
static func default_for(c: Vehicle) -> int:
	if c == null:
		return OFF
	if c.is_in_group("police_car") or c.is_in_group("emergency_unit"):
		return OFF
	var key: int = c.look_seed if c.look_seed != 0 else int(c.body_type) * 7919 + 13
	return absi(hash([key, "car_radio"])) % STATIONS.size()


## The dial after `s` going `dir` (+1 / -1): the four stations, then off, round again.
static func step_from(s: int, dir: int) -> int:
	var n := STATIONS.size() + 1 # the last slot is OFF
	var i := (s if s >= 0 else STATIONS.size()) + (1 if dir >= 0 else -1)
	i = posmod(i, n)
	return OFF if i == STATIONS.size() else i


## Where a station's loop starts at load: a hash of the station, so it is on air mid-song.
static func start_offset(s: int, loop_len: float) -> float:
	if loop_len <= 0.0:
		return 0.0
	return float(absi(hash([STATIONS[s].id, "car_radio_clock"])) % 100000) / 100000.0 * loop_len


## [segment index, seconds into it] for a time `t` in a loop of segment lengths `lengths`.
static func segment_at(lengths: Array, t: float) -> Array:
	var total := 0.0
	for l: float in lengths:
		total += l
	if total <= 0.0:
		return [0, 0.0]
	t = fposmod(t, total)
	var acc := 0.0
	for i in lengths.size():
		if t < acc + lengths[i]:
			return [i, t - acc]
		acc += lengths[i]
	return [lengths.size() - 1, 0.0]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_install_bus()
	_music = AudioStreamPlayer.new()
	_music.name = "Music"
	_music.bus = BUS
	add_child(_music)
	_static = AudioStreamPlayer.new()
	_static.name = "Static"
	_static.bus = BUS
	_static.volume_db = static_db
	var st := _load("static")
	if st:
		_static.stream = st
	add_child(_static)
	_build_playlists()


func _exit_tree() -> void:
	if _inst == self:
		_inst = null


func _install_bus() -> void:
	var idx := AudioServer.get_bus_index(BUS)
	if idx < 0:
		AudioServer.add_bus()
		idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, BUS)
	var send := &"Game" if AudioServer.get_bus_index(&"Game") >= 0 else &"Master"
	AudioServer.set_bus_send(idx, send)
	if AudioServer.get_bus_effect_count(idx) == 0:
		var lo := AudioEffectHighPassFilter.new()
		lo.cutoff_hz = speaker_low_hz
		AudioServer.add_bus_effect(idx, lo)
		var hi := AudioEffectLowPassFilter.new()
		hi.cutoff_hz = speaker_high_hz
		AudioServer.add_bus_effect(idx, hi)
		var comp := AudioEffectCompressor.new()
		comp.threshold = -14.0
		comp.ratio = 2.5
		comp.attack_us = 8000.0
		comp.release_ms = 250.0
		AudioServer.add_bus_effect(idx, comp)


func _load(file: String) -> AudioStream:
	var path := DIR + file + ".ogg"
	if not ResourceLoader.exists(path):
		return null
	return ResourceLoader.load(path) as AudioStream


func _build_playlists() -> void:
	_segs.clear()
	_len.resize(STATIONS.size())
	_clock.resize(STATIONS.size())
	for s in STATIONS.size():
		var st: Dictionary = STATIONS[s]
		var ident := _load("ident_" + st.id)
		var segs: Array = []
		var at := 0.0
		for k in st.tracks.size():
			if ident:
				segs.append([ident, ident.get_length(), at, false, k])
				at += ident.get_length()
			var tr := _load(st.tracks[k][0])
			if tr == null:
				continue
			if tr is AudioStreamOggVorbis:
				(tr as AudioStreamOggVorbis).loop = false
			segs.append([tr, tr.get_length(), at, true, k])
			at += tr.get_length()
		_segs.append(segs)
		_len[s] = at
		_clock[s] = start_offset(s, at)


## Loop length of a station (s).
func loop_length(s: int) -> float:
	return _len[s] if s >= 0 and s < _len.size() else 0.0


## Seconds into station `s`'s loop.
func clock_of(s: int) -> float:
	return _clock[s] if s >= 0 and s < _clock.size() else 0.0


## Segment lengths of station `s`.
func lengths_of(s: int) -> Array:
	var out: Array = []
	if s >= 0 and s < _segs.size():
		for seg: Array in _segs[s]:
			out.append(seg[1])
	return out


## Tunes to `s` (OFF switches off). Shows the card and plays the static.
func tune(s: int) -> void:
	if s == station:
		return
	station = s
	tunes += 1
	_seg = -1
	_music.stop()
	_hold = tune_delay
	if _static.stream and _level > 0.01:
		_static.play()
	_show("tune")
	if car != null and is_instance_valid(car):
		car.set_meta("radio_station", s)


## Moves the dial one step (+1 next, -1 previous).
func step(dir: int) -> void:
	tune(step_from(station, dir))


## The song on air now, or the next one while an ident plays: {title, artist, upcoming}.
func now_playing() -> Dictionary:
	if station < 0 or station >= _segs.size() or _segs[station].is_empty():
		return {}
	var segs: Array = _segs[station]
	var at: Array = segment_at(lengths_of(station), _clock[station])
	var seg: Array = segs[at[0]]
	var k: int = seg[4]
	var tr: Array = STATIONS[station].tracks[k]
	return {"title": tr[1], "artist": tr[2], "upcoming": not seg[3]}


## True while music is coming out of the radio.
func playing() -> bool:
	return _music != null and _music.playing


func _show(kind: String) -> void:
	card_kind = kind
	card_age = 0.0


func _player_car() -> Vehicle:
	var p := get_tree().get_first_node_in_group("player")
	if p == null or not p.has_method("is_driving") or not p.is_driving():
		return null
	var c: Variant = p.get("vehicle")
	if c == null or not is_instance_valid(c) or c is Aircraft or not (c as Node).is_inside_tree():
		return null
	if (c as Vehicle).has_method("is_wreck") and (c as Vehicle).is_wreck():
		return null
	return c as Vehicle


func _process(delta: float) -> void:
	# Real time (the wheel and the downed card slow the game clock); the stations run at the audio's
	# own rate, which the wheel slows too.
	var real := minf(delta / maxf(Engine.time_scale, 0.05), 0.25)
	var adt := real * AudioServer.playback_speed_scale
	card_age += real
	var mine := _player_car()
	if mine != car:
		car = mine
		if car != null:
			var s: int = int(car.get_meta("radio_station", default_for(car)))
			station = -2 # force the tune (and its card) even onto the same station
			tune(s)
			_level = 0.0
	if car != null:
		if Input.is_action_just_pressed("radio_next") or Input.is_action_just_pressed("next_weapon"):
			step(1)
		elif Input.is_action_just_pressed("radio_prev") or Input.is_action_just_pressed("prev_weapon"):
			step(-1)
	# Every station stays on air.
	for s in _clock.size():
		if _len[s] <= 0.0:
			continue
		if s == station and _music.playing and _seg >= 0:
			var pos := _music.get_playback_position()
			if pos > 0.0:
				_clock[s] = float(_segs[s][_seg][2]) + pos
				continue
		_clock[s] = fposmod(_clock[s] + adt, _len[s])
	var on: bool = car != null and station >= 0 and station < _segs.size() and not _segs[station].is_empty()
	_level = move_toward(_level, 1.0 if on else 0.0, real / maxf(fade_in if on else fade_out, 0.01))
	if not on:
		if _level <= 0.0 and _music.playing:
			_music.stop()
			_seg = -1
		_music.volume_db = radio_db + linear_to_db(maxf(_level, 0.0001))
		return
	_music.volume_db = radio_db + linear_to_db(maxf(_level, 0.0001))
	if _hold > 0.0:
		_hold -= real
		return
	var at: Array = segment_at(lengths_of(station), _clock[station])
	var restart: bool = not _music.playing and float(at[1]) < float(_segs[station][at[0]][1]) - 0.3
	if at[0] != _seg or restart:
		var seg: Array = _segs[station][at[0]]
		var was := _seg
		_seg = at[0]
		_music.stream = seg[0]
		_music.play(float(at[1]))
		if was >= 0 and seg[3]:
			_show("song")
