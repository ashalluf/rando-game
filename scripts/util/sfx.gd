extends Node
## Autoload: sound effects. Real CC0 samples from `assets/audio/` where they exist, with the old
## runtime synthesis as the fallback for anything missing, so the game never loses a sound.
## play() for one-shots at a position, loop_player() for engine / boost / weather loops the caller
## owns and pitches. Names with several samples pick a random take each time, never the take that
## name played last, so a rifle burst or a street of footsteps never repeats the same file twice
## in a row.
##
## Every sound, sample or synthesized, is normalised to `reference_loudness_db` before a call
## site's volume_db is added. Peak-normalised recordings are not equally loud - three takes of one
## gun landed 9.3 dB apart and a breaking prop landed 13 dB under the synth sound it replaced -
## so without this the mix is whatever the files happened to be mastered at.

## Overall trim on every sound, in dB. Turn the whole game's SFX up or down here, and only here:
## it sits on top of the normalisation, so moving it changes the level of everything and never the
## balance. +6 puts the one-shots within about 5 dB of the levels the synthesized build played at;
## the master bus limiter catches the transients that would otherwise overshoot at that level.
@export var master_volume_db: float = 6.0
## The level every sound is normalised to: the dB of its loudest 50 ms window. Samples are trimmed
## by the measured numbers in SAMPLE_LOUDNESS_DB, synthesized ones are measured at startup, so two
## takes of one gun, two different sounds, and a sample and the synth fallback it replaces all land
## at the same loudness and a call site's volume_db is the whole of the mix. Headroom: a sample's
## loudest transient lands at this level plus its crest factor plus master_volume_db, and the worst
## crest in the set is break_0's 18.6 dB, so -20 with the +6 master puts that one transient a few
## dB over full scale at point-blank range and everything else under it. The master bus limiter
## (_install_limiter) rounds those peaks off rather than letting the device clip them, so this
## pair sets the level and the limiter handles the overshoot.
@export var reference_loudness_db: float = -20.0
## Random pitch spread on each one-shot (0.06 = +/- 6%) so repeats never sound identical.
@export var pitch_variation: float = 0.06
## How far a one-shot can still be heard, in metres.
@export var max_distance: float = 220.0
## Loudness falloff scale for one-shots: bigger carries further before it fades.
@export var unit_size: float = 12.0
## How far a loop (engine, boost, rain) can still be heard, in metres.
@export var loop_max_distance: float = 120.0
## Loudness falloff scale for loops.
@export var loop_unit_size: float = 10.0
## One-shot players: this many sounds can overlap before the oldest is cut off. Read at startup.
@export var pool_size: int = 24
## Set false to ignore assets/audio/ and use the synthesized sounds instead (to A/B the samples).
@export var use_samples: bool = true

const MIX_RATE := 22050
const AUDIO_DIR := "res://assets/audio/"
## Window the loudness metric averages over. Short enough to read the body of an impact, long
## enough to ignore the single-sample transient that peak normalisation lines up.
const LOUDNESS_WINDOW := 0.05

## Real recordings, all CC0. Every name here also has a synthesized fallback below, so a missing
## or unimported file degrades to the old sound rather than to silence.
const SAMPLES := {
	"shot": ["shot_0.ogg", "shot_1.ogg", "shot_2.ogg"],
	# Three different pump guns (12 gauge, near the shooter) so no two blasts are the same
	# recording, and the pump being racked between them.
	"shotgun": ["shotgun_0.ogg", "shotgun_1.ogg", "shotgun_2.ogg"],
	"pump": ["pump_0.ogg"],
	"explosion": ["explosion_0.ogg", "explosion_1.ogg"],
	"rocket": ["rocket_0.ogg"],
	"break": ["break_0.ogg", "break_1.ogg", "break_2.ogg"],
	"glass": ["glass_0.ogg", "glass_1.ogg", "glass_2.ogg"],
	"crash": ["crash_0.ogg", "crash_1.ogg", "crash_2.ogg"],
	"land": ["land_0.ogg", "land_1.ogg"],
	"thud": ["thud_0.ogg", "thud_1.ogg"],
	"footstep": ["footstep_0.ogg", "footstep_1.ogg", "footstep_2.ogg",
		"footstep_3.ogg", "footstep_4.ogg", "footstep_5.ogg"],
	"horn": ["horn_0.ogg"],
	"engine_loop": ["engine_loop_0.ogg"],
	"boost_loop": ["boost_loop_0.ogg"],
	"rain": ["rain_0.ogg"],
	"wind": ["wind_0.ogg"],
	"ambience_city": ["ambience_city_0.ogg"],
	"thunder": ["thunder_0.ogg"],
	# Air traffic (scripts/world/air_traffic.gd): a real airliner take-off roar and a real police
	# helicopter overhead, each cut to a seamless loop.
	"jet_loop": ["jet_loop_0.ogg"],
	"rotor_loop": ["rotor_loop_0.ogg"],
	# People. Screams are five female takes and seven male yells from four different voices, so
	# a panicking street is a crowd and not one person on a loop; yelp is the pain grunt of
	# someone knocked down; gore is the wet crack of a limb coming off.
	"scream": ["scream_0.ogg", "scream_1.ogg", "scream_2.ogg", "scream_3.ogg", "scream_4.ogg",
		"scream_5.ogg", "scream_6.ogg", "scream_7.ogg", "scream_8.ogg", "scream_9.ogg",
		"scream_10.ogg", "scream_11.ogg"],
	"yelp": ["yelp_0.ogg", "yelp_1.ogg", "yelp_2.ogg", "yelp_3.ogg", "yelp_4.ogg", "yelp_5.ogg",
		"yelp_6.ogg"],
	"gore": ["gore_0.ogg", "gore_1.ogg", "gore_2.ogg", "gore_3.ogg", "gore_4.ogg", "gore_5.ogg",
		"gore_6.ogg"],
	# A real police wail recorded in the street (public domain): one cycle, looped.
	"siren": ["siren_0.ogg"],
}

## Loudest-50 ms level of every take above, in dB, in the same order, measured off the committed
## .ogg files. play() trims each take by `reference_loudness_db` minus its entry. These are
## measurements, not taste: re-measure a file if you replace it (mean square over a sliding 50 ms
## window, take the loudest window, 10*log10). Anything missing here is left untrimmed.
const SAMPLE_LOUDNESS_DB := {
	"shot": [-18.35, -12.10, -21.41],
	"shotgun": [-15.23, -15.21, -15.60],
	"pump": [-8.43],
	"explosion": [-18.02, -13.49],
	"rocket": [-12.17],
	"break": [-23.08, -21.79, -17.18],
	"glass": [-17.59, -21.24, -15.11],
	"crash": [-19.14, -21.64, -21.22],
	"land": [-13.06, -14.97],
	"thud": [-12.01, -10.20],
	"footstep": [-21.59, -23.16, -21.67, -22.83, -22.63, -24.13],
	"horn": [-14.04],
	"engine_loop": [-16.39],
	"boost_loop": [-15.45],
	"rain": [-20.06],
	"wind": [-16.11],
	"ambience_city": [-18.05],
	"thunder": [-10.47],
	"jet_loop": [-11.89],
	"rotor_loop": [-11.66],
	"scream": [-14.30, -13.93, -13.99, -14.16, -13.98, -14.02, -14.10, -14.14, -14.00, -14.01,
		-13.95, -13.96],
	"yelp": [-13.93, -13.96, -13.96, -14.10, -14.21, -14.11, -14.01],
	"gore": [-11.97, -13.00, -13.86, -12.48, -14.75, -12.11, -11.95],
	"siren": [-7.74],
}

## Sample names that have to loop. Set on the stream in code rather than in the .import file, so
## an .import regenerated by the editor can never silently drop the loop flag.
const LOOPING := ["engine_loop", "boost_loop", "rain", "wind", "ambience_city", "skid", "siren",
	"jet_loop", "rotor_loop"]

## The city's ambience (scripts/util/ambience.gd), all CC0 (sources in docs/ASSETS.md). Kept apart
## from SAMPLES only so the two lists read separately; both ship and both load the same way.
## Beds (amb_*) are 22-30 s seamless loops; the rest are one-shots the Ambience node drops round
## the listener. Every name here also has a synthesized fallback (_build_ambience_synth), built
## only when its files do not load: they are long, and startup should not pay for them twice.
const AMBIENCE_SAMPLES := {
	"amb_city": ["amb_city_0.ogg"],
	"amb_city_far": ["amb_city_far_0.ogg"],
	"amb_crowd": ["amb_crowd_0.ogg"],
	"amb_birds": ["amb_birds_0.ogg"],
	"amb_crickets": ["amb_crickets_0.ogg"],
	"amb_gale": ["amb_gale_0.ogg"],
	"amb_rain_heavy": ["amb_rain_heavy_0.ogg"],
	"amb_rain_roof": ["amb_rain_roof_0.ogg"],
	"amb_rain_car": ["amb_rain_car_0.ogg"],
	"amb_freeway": ["amb_freeway_0.ogg"],
	"amb_surf": ["amb_surf_0.ogg"],
	"amb_airport": ["amb_airport_0.ogg"],
	"amb_port": ["amb_port_0.ogg"],
	"car_roll": ["car_roll_0.ogg"],
	"car_pass": ["car_pass_0.ogg", "car_pass_1.ogg", "car_pass_2.ogg", "car_pass_3.ogg"],
	"car_pass_wet": ["car_pass_wet_0.ogg"],
	"horn_far": ["horn_far_0.ogg", "horn_far_1.ogg", "horn_far_2.ogg", "horn_far_3.ogg", "horn_far_4.ogg"],
	"siren_far": ["siren_far_0.ogg", "siren_far_1.ogg"],
	"dog": ["dog_0.ogg", "dog_1.ogg", "dog_2.ogg", "dog_3.ogg"],
	"bus_hiss": ["bus_hiss_0.ogg", "bus_hiss_1.ogg", "bus_hiss_2.ogg"],
	"gull": ["gull_0.ogg", "gull_1.ogg", "gull_2.ogg", "gull_3.ogg", "gull_4.ogg"],
	"coyote": ["coyote_0.ogg", "coyote_1.ogg", "coyote_2.ogg"],
	"ship_horn": ["ship_horn_0.ogg", "ship_horn_1.ogg", "ship_horn_2.ogg"],
	"crane": ["crane_0.ogg", "crane_1.ogg", "crane_2.ogg", "crane_3.ogg"],
}

## Levels of the takes above, in the same order. One-shots use the SAMPLE_LOUDNESS_DB metric (the
## loudest 50 ms window). The beds are steady by construction and every one of them is cut to a
## long-term RMS of -22 dB, which is what is recorded for them: one laugh in the crowd walla sits
## 12 dB over its bed, and trimming the whole bed by that laugh would bury it.
const AMBIENCE_LOUDNESS_DB := {
	"amb_city": [-22.0], "amb_city_far": [-22.0], "amb_crowd": [-22.0], "amb_birds": [-22.0],
	"amb_crickets": [-22.0], "amb_gale": [-22.0], "amb_rain_heavy": [-22.0], "amb_rain_roof": [-22.0],
	"amb_rain_car": [-22.0], "amb_freeway": [-22.0], "amb_surf": [-22.0], "amb_airport": [-22.0],
	"amb_port": [-22.0], "car_roll": [-22.0],
	"car_pass": [-5.41, -12.15, -8.77, -12.83],
	"car_pass_wet": [-11.31],
	"horn_far": [-10.57, -9.55, -6.67, -7.34, -9.53],
	"siren_far": [-8.65, -10.72],
	"dog": [-6.75, -7.10, -7.46, -10.99],
	"bus_hiss": [-13.77, -11.75, -12.24],
	"gull": [-9.86, -9.25, -10.56, -10.07, -11.66],
	"coyote": [-6.57, -10.93, -9.84],
	"ship_horn": [-8.19, -12.66, -7.08],
	"crane": [-10.25, -11.37, -10.90, -4.51],
}

## Ambience names that loop (set in code, like LOOPING).
const AMBIENCE_LOOPING := ["amb_city", "amb_city_far", "amb_crowd", "amb_birds", "amb_crickets",
	"amb_gale", "amb_rain_heavy", "amb_rain_roof", "amb_rain_car", "amb_freeway", "amb_surf",
	"amb_airport", "amb_port", "car_roll"]

## Bus names (built by _install_buses). Everything a thing in the world makes goes to World;
## the weather and the city's ambience go to Ambience; Game holds both.
const BUS_GAME := &"Game"
const BUS_WORLD := &"World"
const BUS_AMBIENCE := &"Ambience"
## Older Sfx names that are ambience rather than events in the world.
const AMBIENT_NAMES := ["rain", "wind", "ambience_city", "thunder"]

var _streams: Dictionary = {}
var _gains: Dictionary = {} # name -> per-take trim in dB, parallel to _streams
var _last_take: Dictionary = {} # name -> index played last, so a take never repeats back to back
var _pool: Array[AudioStreamPlayer3D] = []
var _next: int = 0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 1
	_install_limiter()
	_install_buses()
	_build_synth()
	if use_samples:
		_load_samples()
	_build_ambience_synth()
	for i in maxi(pool_size, 1):
		var p := AudioStreamPlayer3D.new()
		p.max_distance = max_distance
		p.unit_size = unit_size
		p.bus = BUS_WORLD
		add_child(p)
		_pool.append(p)


## A hard limiter across the whole master bus.
##
## Everything is normalised to `reference_loudness_db` by its loudest 50 ms *window*, which is the
## right thing to level a mix by - but a window is not a peak. The sharpest recording in the set
## (break_0) carries 18.6 dB between its window level and its single loudest sample, so at
## point-blank range that one transient lands a few dB over full scale and the output device
## clamps it into a square edge. That is the one flaw left in the loudness pass, and backing the
## master off far enough to bury it would cost about 5 dB across the entire game for the sake of a
## handful of sub-millisecond spikes.
##
## A limiter is the answer the flaw actually asks for: it does nothing at all until a peak reaches
## the ceiling and then rounds that peak off instead of clipping it, so the level stays where it
## was tuned and a crate breaking in your face stops crunching. This is also what keeps the game
## safe when the chaos stacks up - eight explosions, a dozen cars and the rain sum well past unity
## no matter how carefully each one is levelled.
##
## Built in code rather than in a bus layout resource, because a .tres bus layout has to be made
## in the editor and the owner cannot open it.
func _install_limiter() -> void:
	for i in AudioServer.get_bus_effect_count(0):
		if AudioServer.get_bus_effect(0, i) is AudioEffectHardLimiter:
			return
	var lim := AudioEffectHardLimiter.new()
	# Just under full scale, so the converter never sees a sample at the rail.
	lim.ceiling_db = -0.5
	# Only the peaks: nothing below this is touched at all.
	lim.pre_gain_db = 0.0
	AudioServer.add_bus_effect(0, lim)


## Effect slots on the buses below, for set_filter() / set_reverb() and the smoke test.
const GAME_MUFFLE := 0 # Game: low-pass while time is slowed, and after a blast close by
const WORLD_REVERB := 0 # World: street-canyon reverb
const AMBIENCE_ENCLOSE := 0 # Ambience: low-pass when shut in (a car, a covered street)
const AMBIENCE_DUCK := 1 # Ambience: compressor keyed on World, so gunfire pushes the city down

## The bus layout, in code for the same reason as the limiter (a .tres layout needs the editor):
##   Master (limiter) <- Game (muffle) <- World (reverb)
##                                     <- Ambience (enclosure low-pass, ducking compressor)
## The Ambience node moves the filters and the reverb; nothing else needs to know the buses exist.
## On the web build (sample playback) bus effects are skipped by the engine and the plain mix
## plays, which is the right way for this to degrade.
func _install_buses() -> void:
	var game := _ensure_bus(BUS_GAME, &"Master")
	var world := _ensure_bus(BUS_WORLD, BUS_GAME)
	var amb := _ensure_bus(BUS_AMBIENCE, BUS_GAME)
	if AudioServer.get_bus_effect_count(game) == 0:
		var muffle := AudioEffectLowPassFilter.new()
		muffle.cutoff_hz = 20000.0
		AudioServer.add_bus_effect(game, muffle)
		AudioServer.set_bus_effect_enabled(game, GAME_MUFFLE, false)
	if AudioServer.get_bus_effect_count(world) == 0:
		var verb := AudioEffectReverb.new()
		verb.room_size = 0.4
		verb.damping = 0.55
		verb.spread = 0.9
		verb.hipass = 0.25 # no bass smear: a street echoes the crack, not the thump
		verb.dry = 1.0
		verb.wet = 0.04
		verb.predelay_msec = 30.0
		verb.predelay_feedback = 0.3
		AudioServer.add_bus_effect(world, verb)
	if AudioServer.get_bus_effect_count(amb) == 0:
		var enclose := AudioEffectLowPassFilter.new()
		enclose.cutoff_hz = 20000.0
		AudioServer.add_bus_effect(amb, enclose)
		AudioServer.set_bus_effect_enabled(amb, AMBIENCE_ENCLOSE, false)
		var duck := AudioEffectCompressor.new()
		duck.threshold = -26.0
		duck.ratio = 4.0
		duck.attack_us = 2000.0
		duck.release_ms = 900.0
		duck.gain = 0.0
		duck.sidechain = BUS_WORLD
		AudioServer.add_bus_effect(amb, duck)


func _ensure_bus(bus_name: StringName, send: StringName) -> int:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		AudioServer.add_bus()
		idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_send(idx, send)
	return idx


## Sets a bus's low-pass (the Game muffle or the Ambience enclosure). 20 kHz or more switches it
## off rather than running a filter that does nothing.
func set_filter(bus_name: StringName, cutoff_hz: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0 or AudioServer.get_bus_effect_count(idx) == 0:
		return
	var fx := AudioServer.get_bus_effect(idx, 0) as AudioEffectLowPassFilter
	if fx == null:
		return
	var on := cutoff_hz < 19000.0
	fx.cutoff_hz = clampf(cutoff_hz, 20.0, 20000.0)
	if AudioServer.is_bus_effect_enabled(idx, 0) != on:
		AudioServer.set_bus_effect_enabled(idx, 0, on)


## The World bus reverb: wet level, room size (0..1) and pre-delay (ms).
func set_reverb(wet: float, room: float, predelay_msec: float) -> void:
	var idx := AudioServer.get_bus_index(BUS_WORLD)
	if idx < 0 or AudioServer.get_bus_effect_count(idx) <= WORLD_REVERB:
		return
	var verb := AudioServer.get_bus_effect(idx, WORLD_REVERB) as AudioEffectReverb
	if verb == null:
		return
	verb.wet = clampf(wet, 0.0, 1.0)
	verb.room_size = clampf(room, 0.0, 1.0)
	verb.predelay_msec = clampf(predelay_msec, 20.0, 500.0)


## Which bus a name plays on: the weather and the ambience on Ambience, everything else on World.
func bus_for(name: String) -> StringName:
	if AMBIENCE_SAMPLES.has(name) or name in AMBIENT_NAMES:
		return BUS_AMBIENCE
	return BUS_WORLD


## One take of `name` for a caller that owns its own player (the Ambience node): [stream, trim in
## dB, master_volume_db included], never the take this name played last. Empty if there is none.
func take(name: String) -> Array:
	var takes: Array = _streams.get(name, [])
	if takes.is_empty():
		return []
	var idx := _pick(name, takes.size())
	return [takes[idx], master_volume_db + _trim_db(name, idx)]


func has(name: String) -> bool:
	var takes: Array = _streams.get(name, [])
	return not takes.is_empty()


func play(name: String, at: Vector3, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	var takes: Array = _streams.get(name, [])
	if takes.is_empty() or _pool.is_empty():
		return
	var idx := _pick(name, takes.size())
	var p := _pool[_next]
	_next = (_next + 1) % _pool.size()
	p.stop()
	p.stream = takes[idx]
	p.global_position = at
	p.volume_db = volume_db + master_volume_db + _trim_db(name, idx)
	p.pitch_scale = pitch * _rng.randf_range(1.0 - pitch_variation, 1.0 + pitch_variation)
	p.bus = bus_for(name)
	p.play()


## A looping player for the caller to parent and control.
func loop_player(name: String, volume_db: float = -6.0) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	var takes: Array = _streams.get(name, [])
	var trim := 0.0
	if not takes.is_empty():
		p.stream = takes[0]
		trim = _trim_db(name, 0)
	p.volume_db = volume_db + master_volume_db + trim
	p.max_distance = loop_max_distance
	p.unit_size = loop_unit_size
	p.bus = bus_for(name)
	return p


## Index of a random take, uniform over every take but the one this name played last.
func _pick(key: String, count: int) -> int:
	if count <= 1:
		return 0
	var last: int = _last_take.get(key, -1)
	var idx := _rng.randi() % count
	if idx == last:
		idx = (last + 1 + _rng.randi() % (count - 1)) % count
	_last_take[key] = idx
	return idx


## The normalisation trim for one take, in dB. Zero for anything with no measurement behind it.
func _trim_db(key: String, idx: int) -> float:
	var gains: Array = _gains.get(key, [])
	if idx < 0 or idx >= gains.size():
		return 0.0
	return gains[idx]


# --- Samples -----------------------------------------------------------------------------

func _load_samples() -> void:
	_load_table(SAMPLES, SAMPLE_LOUDNESS_DB, LOOPING)
	_load_table(AMBIENCE_SAMPLES, AMBIENCE_LOUDNESS_DB, AMBIENCE_LOOPING)


func _load_table(table: Dictionary, levels: Dictionary, looping: Array) -> void:
	for key: String in table:
		var takes: Array[AudioStream] = []
		var gains: Array[float] = []
		var names: Array = table[key]
		var loudness: Array = levels.get(key, [])
		for i in names.size():
			var file_name: String = names[i]
			var path := AUDIO_DIR + file_name
			if not ResourceLoader.exists(path):
				continue
			var stream := ResourceLoader.load(path) as AudioStream
			if stream == null:
				continue
			if key in looping:
				_set_looping(stream)
			takes.append(stream)
			var measured: float = loudness[i] if i < loudness.size() else reference_loudness_db
			gains.append(reference_loudness_db - measured)
		if not takes.is_empty():
			_streams[key] = takes # real takes replace the synthesized fallback
			_gains[key] = gains


func _set_looping(stream: AudioStream) -> void:
	if stream is AudioStreamOggVorbis:
		var ogg := stream as AudioStreamOggVorbis
		ogg.loop = true
		ogg.loop_offset = 0.0


# --- Synthesis (fallback) ----------------------------------------------------------------

func _build_synth() -> void:
	_put("shot", _noise_burst(0.10, 40.0, 0.9, 0.35))
	_put("shotgun", _noise_burst(0.32, 13.0, 1.0, 0.12))
	_put("pump", _noise_burst(0.07, 60.0, 0.6, 0.7))
	_put("rocket", _noise_burst(0.35, 9.0, 0.7, 0.08))
	_put("explosion", _noise_burst(1.3, 3.5, 1.0, 0.03))
	_put("jump", _sweep(0.16, 320.0, 640.0, 0.45))
	_put("land", _thud(0.12, 90.0, 0.7))
	_put("thud", _thud(0.18, 70.0, 0.9))
	_put("footstep", _thud(0.07, 140.0, 0.4))
	_put("break", _noise_burst(0.28, 14.0, 0.8, 0.2))
	_put("glass", _noise_burst(0.34, 11.0, 0.7, 0.75))
	_put("crash", _noise_burst(0.45, 8.0, 1.0, 0.15))
	_put("horn", _horn(0.5))
	_put("yelp", _yelp(0.4))
	_put("scream", _yelp(1.1))
	_put("gore", _noise_burst(0.3, 16.0, 0.8, 0.05))
	_put("click", _sweep(0.05, 1200.0, 900.0, 0.4))
	_put("boost_loop", _boost_loop(0.6), true)
	_put("engine_loop", _engine_loop(0.4), true)
	_put("skid", _skid_loop(0.5), true)
	_put("rain", _rain_loop(1.5), true)
	_put("wind", _wind_loop(2.0), true)
	_put("ambience_city", _city_loop(2.0), true)
	_put("thunder", _thunder(3.2))
	_put("siren", _siren_wail(4.0), true)
	_put("jet_loop", _jet_loop(1.6), true)
	_put("rotor_loop", _rotor_loop(1.2), true)


func _put(key: String, samples: PackedFloat32Array, looping: bool = false) -> void:
	var takes: Array[AudioStream] = [_wav(samples, looping, _synth_gain(samples))]
	_streams[key] = takes
	_gains[key] = [0.0] # baked into the buffer instead, so there is nothing left to trim


## Linear gain that lands a generated buffer on reference_loudness_db. Applied before the 16-bit
## clamp in _wav(), so the bursts that used to be written clipped flat come out intact.
func _synth_gain(samples: PackedFloat32Array) -> float:
	var loud := _loudness_db(samples)
	if loud <= -119.0:
		return 1.0
	return db_to_linear(clampf(reference_loudness_db - loud, -60.0, 24.0))


## Loudest 50 ms window of a buffer, in dB: the same metric SAMPLE_LOUDNESS_DB is measured with.
func _loudness_db(samples: PackedFloat32Array) -> float:
	var n := samples.size()
	if n == 0:
		return -120.0
	var w := mini(int(LOUDNESS_WINDOW * MIX_RATE), n)
	var sum := 0.0
	for i in w:
		sum += samples[i] * samples[i]
	var best := sum
	for i in range(w, n):
		sum += samples[i] * samples[i] - samples[i - w] * samples[i - w]
		best = maxf(best, sum)
	return 10.0 * log(maxf(best / float(w), 1e-12)) / log(10.0)


func _wav(samples: PackedFloat32Array, looping: bool = false, gain: float = 1.0) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		var v := int(clampf(samples[i] * gain, -1.0, 1.0) * 32767.0)
		bytes.encode_s16(i * 2, v)
	wav.data = bytes
	if looping:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = samples.size()
	return wav


func _noise_burst(seconds: float, decay: float, gain: float, smooth: float) -> PackedFloat32Array:
	var n := int(seconds * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var last := 0.0
	for i in n:
		var t := float(i) / MIX_RATE
		var white := _rng.randf_range(-1.0, 1.0)
		last = lerpf(last, white, smooth) # low-pass: smaller smooth = deeper rumble
		out[i] = last * exp(-decay * t) * gain * 3.0
	return out


func _sweep(seconds: float, f0: float, f1: float, gain: float) -> PackedFloat32Array:
	var n := int(seconds * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / n
		var f := lerpf(f0, f1, t)
		phase += TAU * f / MIX_RATE
		var env := sin(t * PI)
		out[i] = sin(phase) * env * gain
	return out


func _thud(seconds: float, f: float, gain: float) -> PackedFloat32Array:
	var n := int(seconds * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / MIX_RATE
		out[i] = sin(TAU * f * t * (1.0 - t * 2.0)) * exp(-18.0 * t) * gain
	return out


func _yelp(seconds: float) -> PackedFloat32Array:
	var n := int(seconds * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / n
		var f := lerpf(750.0, 280.0, t * t) * (1.0 + 0.06 * sin(t * 60.0))
		phase += TAU * f / MIX_RATE
		var env := minf(t * 12.0, 1.0) * (1.0 - t)
		out[i] = (sin(phase) * 0.7 + sin(phase * 2.0) * 0.3) * env * 0.6
	return out


## Two detuned tones a major third apart, which is roughly what a car horn is.
func _horn(seconds: float) -> PackedFloat32Array:
	var n := int(seconds * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / MIX_RATE
		var env := minf(t * 60.0, 1.0) * minf((seconds - t) * 40.0, 1.0)
		var a := sin(TAU * 440.0 * t)
		var b := sin(TAU * 554.0 * t)
		var buzz := sin(TAU * 880.0 * t) * 0.2 + sin(TAU * 1108.0 * t) * 0.15
		out[i] = (a * 0.4 + b * 0.35 + buzz) * env * 0.6
	return out


func _boost_loop(seconds: float) -> PackedFloat32Array:
	var n := int(seconds * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var last := 0.0
	for i in n:
		var t := float(i) / MIX_RATE
		last = lerpf(last, _rng.randf_range(-1.0, 1.0), 0.12)
		out[i] = last * 0.5 + sin(TAU * 110.0 * t) * 0.15 + sin(TAU * 220.0 * t) * 0.08
	return out


func _engine_loop(seconds: float) -> PackedFloat32Array:
	var n := int(seconds * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / MIX_RATE
		var saw := fmod(t * 55.0, 1.0) * 2.0 - 1.0
		out[i] = saw * 0.25 + sin(TAU * 110.0 * t) * 0.2 + sin(TAU * 165.0 * t) * 0.08
	return out


## Tyre skid: band-limited noise with a resonant squeal riding on top. No CC0 recording of a
## skid was found, so this one has no sample behind it.
func _skid_loop(seconds: float) -> PackedFloat32Array:
	var n := int(seconds * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var last := 0.0
	var band := 0.0
	for i in n:
		var t := float(i) / MIX_RATE
		last = lerpf(last, _rng.randf_range(-1.0, 1.0), 0.6)
		band = lerpf(band, last, 0.25) # a second pole: leaves a narrow noise band
		var squeal := sin(TAU * (1250.0 + 90.0 * sin(TAU * 7.0 * t)) * t)
		out[i] = (last - band) * 0.8 + squeal * 0.18
	return out


## Steady hiss of rain: low-passed white noise with a slow flutter.
func _rain_loop(seconds: float) -> PackedFloat32Array:
	var n := int(seconds * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var last := 0.0
	for i in n:
		var t := float(i) / MIX_RATE
		last = lerpf(last, _rng.randf_range(-1.0, 1.0), 0.45)
		out[i] = last * 0.35 * (0.85 + 0.15 * sin(TAU * 0.7 * t))
	return out


## Wind: deeper than rain and gustier, so the level breathes over a few seconds.
func _wind_loop(seconds: float) -> PackedFloat32Array:
	var n := int(seconds * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var last := 0.0
	for i in n:
		var t := float(i) / MIX_RATE
		last = lerpf(last, _rng.randf_range(-1.0, 1.0), 0.06)
		var gust := 0.7 + 0.3 * sin(TAU * t / seconds) # one whole gust per loop, so it seams
		out[i] = last * 2.2 * gust
	return out


## Distant traffic: a low rumble with a slow swell, enough to keep a street from sounding dead.
func _city_loop(seconds: float) -> PackedFloat32Array:
	var n := int(seconds * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var last := 0.0
	for i in n:
		var t := float(i) / MIX_RATE
		last = lerpf(last, _rng.randf_range(-1.0, 1.0), 0.03)
		var swell := 0.75 + 0.25 * sin(TAU * t / seconds)
		out[i] = last * 3.0 * swell + sin(TAU * 62.0 * t) * 0.03
	return out


## A police wail: one slow sweep up and back down, exactly one loop long. Electronic sirens
## drive a horn with something close to a square wave, so it is the odd harmonics with a
## little soft clipping, and the whole sweep is scaled so the waveform's phase closes on itself
## at the loop point (no click where it wraps).
func _siren_wail(seconds: float) -> PackedFloat32Array:
	var n := int(seconds * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var lo := 680.0
	var hi := 1480.0
	var total := 0.0
	for i in n:
		var t := float(i) / float(n)
		total += TAU * (lo + (hi - lo) * (0.5 - 0.5 * cos(TAU * t))) / MIX_RATE
	var fix := (roundf(total / TAU) * TAU) / total
	var phase := 0.0
	for i in n:
		var t := float(i) / float(n)
		phase += TAU * (lo + (hi - lo) * (0.5 - 0.5 * cos(TAU * t))) * fix / MIX_RATE
		var s := sin(phase) + 0.30 * sin(3.0 * phase) + 0.15 * sin(5.0 * phase) + 0.06 * sin(2.0 * phase)
		out[i] = tanh(s * 1.4) * 0.5
	return out


## Thunder: a deep rumble that cracks first, then rolls off.
func _thunder(seconds: float) -> PackedFloat32Array:
	var n := int(seconds * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var last := 0.0
	for i in n:
		var t := float(i) / MIX_RATE
		last = lerpf(last, _rng.randf_range(-1.0, 1.0), 0.02 + 0.2 * exp(-8.0 * t))
		var env := exp(-1.4 * t) * (1.0 + 0.5 * sin(TAU * 2.3 * t) * exp(-t))
		out[i] = clampf(last * 6.0 * env, -1.0, 1.0)
	return out


## Jet roar fallback: deep broadband noise with a turbine whine on top. Loops seamlessly because
## the whine's frequency is a whole number of cycles over the buffer.
func _jet_loop(seconds: float) -> PackedFloat32Array:
	var n := int(seconds * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var low := 0.0
	var mid := 0.0
	var whine_hz := roundf(1850.0 * seconds) / seconds
	for i in n:
		var t := float(i) / MIX_RATE
		var white := _rng.randf_range(-1.0, 1.0)
		low = lerpf(low, white, 0.03)
		mid = lerpf(mid, white, 0.25)
		out[i] = low * 2.4 + (mid - low) * 0.5 + sin(TAU * whine_hz * t) * 0.035
	return out


## Rotor chop fallback: a low thump per blade pass over a turbine hiss. The blade rate is a whole
## number of passes per buffer so the loop has no seam.
func _rotor_loop(seconds: float) -> PackedFloat32Array:
	var n := int(seconds * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var hiss := 0.0
	var pass_hz := roundf(19.5 * seconds) / seconds
	for i in n:
		var t := float(i) / MIX_RATE
		var ph := fmod(t * pass_hz, 1.0)
		var thump := exp(-ph * 9.0) * sin(TAU * 70.0 * ph / pass_hz)
		hiss = lerpf(hiss, _rng.randf_range(-1.0, 1.0), 0.35)
		out[i] = thump * 0.8 + hiss * 0.12 * (0.7 + 0.3 * exp(-ph * 5.0))
	return out


# --- Ambience fallbacks ------------------------------------------------------------------

## Synthesized stand-ins for the ambience, built only for the names whose recordings did not load
## (all of them with use_samples off). Short loops of shaped noise and tones: enough that a missing
## file is heard as roughly the right thing - a roar, a wash of surf, a chirp - not as silence.
func _build_ambience_synth() -> void:
	for key: String in AMBIENCE_SAMPLES:
		if not _streams.has(key):
			_put(key, ambience_synth(key), key in AMBIENCE_LOOPING)


## The synthesized fallback for one ambience name (public so the smoke test can check each one).
func ambience_synth(key: String) -> PackedFloat32Array:
	match key:
		"amb_city": return _bed(3.0, 0.05, 2.2, 0.0, 0.0)
		"amb_city_far": return _bed(3.0, 0.02, 3.0, 0.0, 0.0)
		"amb_freeway": return _bed(2.0, 0.14, 1.4, 0.0, 0.0)
		"amb_airport": return _bed(3.0, 0.03, 2.6, 1650.0, 0.03)
		"amb_port": return _bed(3.0, 0.02, 2.8, 100.0, 0.08)
		"amb_crowd": return _babble(3.0)
		"amb_birds": return _chirps(4.0, 9, 2600.0, 4800.0)
		"amb_crickets": return _crickets(2.0)
		"amb_gale": return _wind_loop(3.0)
		"amb_rain_heavy": return _bed(2.0, 0.7, 0.45, 0.0, 0.0)
		"amb_rain_roof": return _drips(2.0, 60)
		"amb_rain_car": return _drips(2.0, 90)
		"amb_surf": return _surf(7.0)
		"car_roll": return _bed(1.0, 0.08, 1.6, 55.0, 0.12)
		"car_pass", "car_pass_wet": return _pass_by(2.8)
		"horn_far": return _horn(0.45)
		"siren_far": return _siren_wail(4.0)
		"dog": return _bark(0.9)
		"bus_hiss": return _noise_burst(1.1, 2.5, 0.6, 0.8)
		"gull": return _chirps(1.2, 3, 1400.0, 2200.0)
		"coyote": return _howl(2.2)
		"ship_horn": return _ship_horn(3.5)
		"crane": return _clank(1.2)
	return _bed(1.0, 0.05, 1.0, 0.0, 0.0)


## A bed of low-passed noise with an optional steady tone (a turbine whine, a quay's hum). The
## tone's frequency is rounded to whole cycles over the buffer, so the loop has no seam.
func _bed(seconds: float, smooth: float, gain: float, tone_hz: float, tone: float) -> PackedFloat32Array:
	var n := int(seconds * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var hz := roundf(tone_hz * seconds) / seconds
	var last := 0.0
	for i in n:
		var t := float(i) / MIX_RATE
		last = lerpf(last, _rng.randf_range(-1.0, 1.0), smooth)
		out[i] = last * gain * (0.85 + 0.15 * sin(TAU * t / seconds)) + sin(TAU * hz * t) * tone
	return out


## Crowd walla: a few "voices", each a band of noise opened and closed at a syllable rate.
func _babble(seconds: float) -> PackedFloat32Array:
	var n := int(seconds * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for v in 4:
		var rate := _rng.randf_range(3.0, 6.0)
		var phase := _rng.randf() * TAU
		var smooth := _rng.randf_range(0.12, 0.3)
		var low := 0.0
		var band := 0.0
		for i in n:
			var t := float(i) / MIX_RATE
			low = lerpf(low, _rng.randf_range(-1.0, 1.0), smooth)
			band = lerpf(band, low, 0.08)
			var syllable := maxf(0.0, sin(TAU * rate * t + phase + 1.3 * sin(TAU * 0.7 * t)))
			out[i] += (low - band) * syllable * 0.5
	return out


## Short tonal sweeps scattered through the buffer: birdsong, or a gull's cry when lower.
func _chirps(seconds: float, count: int, f_lo: float, f_hi: float) -> PackedFloat32Array:
	var n := int(seconds * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for c in count:
		var start := int(_rng.randf_range(0.0, maxf(seconds - 0.35, 0.01)) * MIX_RATE)
		var length := int(_rng.randf_range(0.06, 0.3) * MIX_RATE)
		var f0 := _rng.randf_range(f_lo, f_hi)
		var f1 := f0 * _rng.randf_range(0.6, 1.5)
		var phase := 0.0
		for k in length:
			var u := float(k) / float(length)
			phase += TAU * lerpf(f0, f1, u) * (1.0 + 0.04 * sin(u * 60.0)) / MIX_RATE
			if start + k < n:
				out[start + k] += sin(phase) * sin(u * PI) * 0.5
	return out


## Field crickets: a 4.4 kHz carrier gated into triple pulses, twice a second.
func _crickets(seconds: float) -> PackedFloat32Array:
	var n := int(seconds * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / MIX_RATE
		var cycle := fmod(t, 0.5)
		var gate := 0.0
		for p in 3:
			var at := 0.05 + 0.045 * p
			if cycle > at and cycle < at + 0.025:
				gate = sin((cycle - at) / 0.025 * PI)
		out[i] = sin(TAU * 4400.0 * t) * gate * 0.4
	return out


## Surf: a wash of noise that swells and breaks once per buffer, brighter as it breaks.
func _surf(seconds: float) -> PackedFloat32Array:
	var n := int(seconds * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var low := 0.0
	var high := 0.0
	for i in n:
		var u := float(i) / float(n)
		var swell := pow(0.5 - 0.5 * cos(TAU * u), 3.0)
		var white := _rng.randf_range(-1.0, 1.0)
		low = lerpf(low, white, 0.04)
		high = lerpf(high, white, 0.5)
		out[i] = low * (0.8 + 1.8 * swell) + high * 0.35 * swell
	return out


## Rain on something hard: a steady hiss with sharp drops scattered over it.
func _drips(seconds: float, per_second: int) -> PackedFloat32Array:
	var out := _rain_loop(seconds)
	var n := out.size()
	for d in int(seconds * per_second):
		var at := _rng.randi() % n
		var f := _rng.randf_range(1800.0, 4200.0)
		for k in 220:
			if at + k >= n:
				break
			out[at + k] += sin(TAU * f * float(k) / MIX_RATE) * exp(-float(k) / 40.0) * 0.5
	return out


## A car going by: noise that swells to a peak at 1.2 s and falls away duller, as the Doppler does.
func _pass_by(seconds: float) -> PackedFloat32Array:
	var n := int(seconds * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var last := 0.0
	for i in n:
		var t := float(i) / MIX_RATE
		var env := exp(-pow((t - 1.2) / 0.45, 2.0))
		last = lerpf(last, _rng.randf_range(-1.0, 1.0), 0.35 if t < 1.2 else 0.12)
		out[i] = last * env * 1.5
	return out


## A dog: two short barks, a pitched growl under a burst of breath noise.
func _bark(seconds: float) -> PackedFloat32Array:
	var n := int(seconds * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for b in 2:
		var start := int((0.05 + 0.4 * b) * MIX_RATE)
		var length := int(0.16 * MIX_RATE)
		var phase := 0.0
		for k in length:
			var u := float(k) / float(length)
			phase += TAU * lerpf(520.0, 330.0, u) / MIX_RATE
			var tone := sin(phase) + 0.5 * sin(phase * 2.0) + 0.3 * sin(phase * 3.0)
			if start + k < n:
				out[start + k] = (tone * 0.6 + _rng.randf_range(-0.4, 0.4)) * sin(u * PI) * 0.6
	return out


## A coyote: a yip rising into a long wavering howl.
func _howl(seconds: float) -> PackedFloat32Array:
	var n := int(seconds * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / MIX_RATE
		var u := t / seconds
		var f := lerpf(700.0, 1250.0, smoothstep(0.0, 0.3, u)) * (1.0 + 0.03 * sin(TAU * 5.5 * t))
		phase += TAU * f / MIX_RATE
		var env := smoothstep(0.0, 0.15, u) * (1.0 - smoothstep(0.7, 1.0, u))
		out[i] = (sin(phase) + 0.25 * sin(phase * 2.0)) * env * 0.5
	return out


## A ship's horn: a low fundamental with strong harmonics, a slow attack and a long release.
func _ship_horn(seconds: float) -> PackedFloat32Array:
	var n := int(seconds * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / MIX_RATE
		var env := minf(t / 0.25, 1.0) * minf((seconds - t) / 0.8, 1.0)
		var s := sin(TAU * 98.0 * t) + 0.7 * sin(TAU * 196.0 * t) + 0.45 * sin(TAU * 294.0 * t) + 0.2 * sin(TAU * 392.0 * t)
		out[i] = tanh(s * 0.8) * env * 0.6
	return out


## A steel clank: a few inharmonic partials struck at once and left to ring.
func _clank(seconds: float) -> PackedFloat32Array:
	var n := int(seconds * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / MIX_RATE
		var s := sin(TAU * 310.0 * t) * exp(-4.0 * t) + 0.6 * sin(TAU * 827.0 * t) * exp(-6.0 * t)
		s += 0.4 * sin(TAU * 1523.0 * t) * exp(-9.0 * t) + 0.25 * sin(TAU * 2410.0 * t) * exp(-14.0 * t)
		out[i] = s * 0.4 + _rng.randf_range(-1.0, 1.0) * exp(-60.0 * t) * 0.5
	return out
