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
	"scream": [-14.30, -13.93, -13.99, -14.16, -13.98, -14.02, -14.10, -14.14, -14.00, -14.01,
		-13.95, -13.96],
	"yelp": [-13.93, -13.96, -13.96, -14.10, -14.21, -14.11, -14.01],
	"gore": [-11.97, -13.00, -13.86, -12.48, -14.75, -12.11, -11.95],
	"siren": [-7.74],
}

## Sample names that have to loop. Set on the stream in code rather than in the .import file, so
## an .import regenerated by the editor can never silently drop the loop flag.
const LOOPING := ["engine_loop", "boost_loop", "rain", "wind", "ambience_city", "skid", "siren"]

var _streams: Dictionary = {}
var _gains: Dictionary = {} # name -> per-take trim in dB, parallel to _streams
var _last_take: Dictionary = {} # name -> index played last, so a take never repeats back to back
var _pool: Array[AudioStreamPlayer3D] = []
var _next: int = 0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 1
	_install_limiter()
	_build_synth()
	if use_samples:
		_load_samples()
	for i in maxi(pool_size, 1):
		var p := AudioStreamPlayer3D.new()
		p.max_distance = max_distance
		p.unit_size = unit_size
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
	for key: String in SAMPLES:
		var takes: Array[AudioStream] = []
		var gains: Array[float] = []
		var names: Array = SAMPLES[key]
		var loudness: Array = SAMPLE_LOUDNESS_DB.get(key, [])
		for i in names.size():
			var file_name: String = names[i]
			var path := AUDIO_DIR + file_name
			if not ResourceLoader.exists(path):
				continue
			var stream := ResourceLoader.load(path) as AudioStream
			if stream == null:
				continue
			if key in LOOPING:
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
