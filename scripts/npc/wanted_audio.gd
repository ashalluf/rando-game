class_name WantedAudio
extends Node
## What each wanted star sounds like (WantedEscalation): the sirens' mix and the police radio.
## A child of the Police node (attach(), from Police._ready), off under WANTED_ESCALATION=0 or
## WANTED_AUDIO=0.
##
## Sirens. Every cruiser carries one looping AudioStreamPlayer3D (PoliceCar); this node picks
## its voice four times a second: the wail on the way in, the yelp once it is within
## WantedEscalation.yelp_reach() of the player (from two stars; the reach grows with the stars),
## the agency trucks' own hi-lo two-tone at five, and the tactical vans' air horn in short blasts
## when they are close at four and five. So one star is one slow wail somewhere, and five is a
## wall of yelps, horns and two-tones closing in from every side.
##
## Radio. A police scanner heard over the mix (non-positional, quiet): each new star is
## announced by its own alert tone (one beep at one star up to the long warbling emergency tone
## at five), the stars clearing by a falling pair, and while wanted a garbled call - squelch,
## a voice-like burst of band-limited noise in syllables, a roger beep - comes every
## WantedEscalation.radio_gap() seconds, more and more often. No words, no real code.
## Everything is synthesised here once (no new audio files).

const MIX_RATE := 22050
## Radio level (dB, before Sfx.master_volume_db) and the siren voices' trims (dB).
const RADIO_DB := -15.0
const HILO_DB := -2.0
const YELP_DB := -1.0
## The vans' air horn: within this distance (m), every this many seconds.
const HORN_REACH := 85.0
const HORN_GAP := Vector2(4.5, 8.0)

static var enabled: bool = OS.get_environment("WANTED_AUDIO") != "0"
static var _streams: Dictionary = {}

var police: Node
var _radio: AudioStreamPlayer
var _tick: float = 0.0
var _radio_t: float = 2.0
var _last_stars: int = 0
var _horn_t: Dictionary = {}
var _rng := RandomNumberGenerator.new()
## What the radio played last (tests read it): "alert_<n>", "clear" or "call".
var last_radio: String = ""
## Voices picked on the last tick, by name (tests read it).
var voices: Dictionary = {}


static func attach(p: Node) -> WantedAudio:
	if not enabled or not WantedEscalation.enabled or p == null:
		return null
	var w := WantedAudio.new()
	w.name = "WantedAudio"
	w.police = p
	p.add_child(w)
	return w


func _ready() -> void:
	_rng.seed = 7731
	_radio = AudioStreamPlayer.new()
	_radio.name = "Radio"
	_radio.bus = Sfx.BUS_WORLD
	add_child(_radio)


func _process(delta: float) -> void:
	if police == null:
		return
	var stars: int = int(police.get("stars"))
	if stars != _last_stars:
		if stars > _last_stars:
			_play_radio("alert_%d" % stars)
			_radio_t = 2.5 + _rng.randf() * 2.0
		elif stars == 0:
			_play_radio("clear")
		_last_stars = stars
	if stars > 0:
		_radio_t -= delta
		if _radio_t <= 0.0:
			var gap := WantedEscalation.radio_gap(stars)
			_radio_t = gap * _rng.randf_range(0.7, 1.3)
			if not _radio.playing:
				_play_radio("call_%d" % (_rng.randi() % 6))
	_tick -= delta
	if _tick <= 0.0:
		_tick = 0.25
		_mix_sirens(stars)


## Picks each cruiser's siren voice (see the class comment).
func _mix_sirens(stars: int) -> void:
	voices.clear()
	var player := police.call("player_node") as Node3D
	var pp := player.global_position if player else Vector3.INF
	var reach := WantedEscalation.yelp_reach(stars)
	var now := Time.get_ticks_msec() / 1000.0
	for c in police.get("cruisers"):
		if not is_instance_valid(c):
			continue
		var car := c as PoliceCar
		var base: float = car.siren_volume_db
		var d := car.global_position.distance_to(pp) if player else INF
		var voice := "wail"
		if car.agency:
			voice = "hilo"
		elif reach > 0.0 and d < reach:
			voice = "yelp"
		voices[voice] = int(voices.get(voice, 0)) + 1
		var m: float = Sfx.master_volume_db
		match voice:
			"hilo":
				car.set_siren_voice(stream("hilo"), base + m + HILO_DB)
			"yelp":
				var y: Array = Sfx.take_at("siren_yelp", 0)
				if not y.is_empty():
					car.set_siren_voice(y[0], base + float(y[1]) + YELP_DB)
			_:
				var w: Array = Sfx.take_at("siren", 0)
				if not w.is_empty():
					car.set_siren_voice(w[0], base + float(w[1]))
		# The tactical units' air horn, in blasts, close in.
		if (car.heavy or car.agency) and stars >= WantedEscalation.VAN_STARS and d < HORN_REACH and car.siren_running():
			var id := car.get_instance_id()
			if now >= float(_horn_t.get(id, 0.0)):
				_horn_t[id] = now + _rng.randf_range(HORN_GAP.x, HORN_GAP.y)
				Sfx.play("fire_horn", car.global_position + Vector3.UP * 2.0, -2.0, 0.92 if car.agency else 1.05)
				voices["horn"] = int(voices.get("horn", 0)) + 1


func _play_radio(key: String) -> void:
	var s := stream(key)
	if s == null:
		return
	_radio.stream = s
	_radio.volume_db = RADIO_DB + Sfx.master_volume_db
	_radio.play()
	last_radio = key.get_slice("_", 0) if key.begins_with("call") else key


# --- Synthesis -------------------------------------------------------------------------------

## One of the synthesised streams by key, made on first use and kept: "hilo", "alert_1".."5",
## "clear", "call_0".."5".
static func stream(key: String) -> AudioStream:
	if _streams.has(key):
		return _streams[key]
	var data := PackedFloat32Array()
	var loop := false
	if key == "hilo":
		data = hilo(2.2)
		loop = true
	elif key == "clear":
		data = tones([[880.0, 0.16], [0.0, 0.06], [660.0, 0.22]])
	elif key.begins_with("alert_"):
		data = alert(int(key.get_slice("_", 1)))
	elif key.begins_with("call_"):
		data = radio_call(int(key.get_slice("_", 1)))
	else:
		return null
	var s := wav(data, loop)
	_streams[key] = s
	return s


static func wav(samples: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = MIX_RATE
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	w.data = bytes
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = samples.size()
	return w


## The agency's two-tone: a hard switch between two pitches a fourth apart, twice a second, on a
## horn-driver wave (odd harmonics, soft clipped); a whole number of cycles of each tone a loop.
static func hilo(seconds: float) -> PackedFloat32Array:
	var n := int(seconds * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var hi := 1100.0
	var lo := 825.0
	var half := maxi(int(float(n) / 4.0), 1)
	var phase := 0.0
	for i in n:
		var f := hi if int(float(i) / float(half)) % 2 == 0 else lo
		phase += TAU * f / MIX_RATE
		var s := sin(phase) + 0.32 * sin(3.0 * phase) + 0.16 * sin(5.0 * phase)
		# A short glide at each switch (the driver does not change pitch instantly).
		var k := i % half
		var edge := minf(float(k) / 160.0, 1.0)
		out[i] = tanh(s * 1.5) * 0.48 * (0.85 + 0.15 * edge)
	return out


## A sequence of [frequency, seconds] tones (0 = a gap), with soft edges.
static func tones(seq: Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for t: Array in seq:
		var f: float = t[0]
		var n := int(float(t[1]) * MIX_RATE)
		for i in n:
			var env := minf(minf(float(i) / 120.0, float(n - i) / 220.0), 1.0)
			out.append(sin(TAU * f * float(i) / MIX_RATE) * 0.42 * env if f > 0.0 else 0.0)
	return out


## The dispatch alert for a level: one beep at one star, two at two, a rising triple at three,
## a long two-tone at four, and the emergency warble at five.
static func alert(stars: int) -> PackedFloat32Array:
	match stars:
		1:
			return tones([[1050.0, 0.22]])
		2:
			return tones([[1050.0, 0.16], [0.0, 0.08], [1050.0, 0.16]])
		3:
			return tones([[880.0, 0.13], [0.0, 0.05], [1050.0, 0.13], [0.0, 0.05], [1320.0, 0.20]])
		4:
			return tones([[1000.0, 0.45], [1450.0, 0.45], [1000.0, 0.45]])
	var out := PackedFloat32Array()
	var n := int(2.2 * MIX_RATE)
	var phase := 0.0
	for i in n:
		var t := float(i) / MIX_RATE
		var f := 1150.0 + 330.0 * sin(TAU * 7.0 * t)
		phase += TAU * f / MIX_RATE
		var env := minf(minf(t / 0.02, (2.2 - t) / 0.08), 1.0)
		out.append(sin(phase) * 0.4 * env)
	return out


## A garbled call: a squelch click, `seconds` of syllables (noise through two moving resonances,
## a voice's formants, gated in bursts), a roger beep, the squelch tail. Seeded by `variant`.
static func radio_call(variant: int) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9100 + variant
	var out := PackedFloat32Array()
	# The squelch opening: a click and a burst of hiss.
	for i in int(0.06 * MIX_RATE):
		out.append(rng.randf_range(-1.0, 1.0) * 0.35 * exp(-float(i) / 300.0))
	var seconds := rng.randf_range(0.9, 2.1)
	var n := int(seconds * MIX_RATE)
	# Two band-pass resonators (state variable filters) on the noise: the formants.
	var lp1 := 0.0
	var bp1 := 0.0
	var lp2 := 0.0
	var bp2 := 0.0
	var syl_left := 0
	var syl_len := 1
	var gap := false
	var f1 := 600.0
	var f2 := 1500.0
	var pitch_phase := 0.0
	for i in n:
		if syl_left <= 0:
			gap = rng.randf() < 0.22
			syl_len = int(rng.randf_range(0.07, 0.19) * MIX_RATE) if not gap else int(rng.randf_range(0.03, 0.11) * MIX_RATE)
			syl_left = syl_len
			f1 = rng.randf_range(380.0, 820.0)
			f2 = rng.randf_range(1100.0, 2300.0)
		syl_left -= 1
		var k := 1.0 - float(syl_left) / float(syl_len)
		var env := 0.0 if gap else sin(PI * k)
		# A voiced buzz under the noise (a pitch near 120 Hz) gives the formants something to ring.
		pitch_phase += TAU * 118.0 / MIX_RATE
		var src := rng.randf_range(-1.0, 1.0) * 0.55 + (fposmod(pitch_phase, TAU) / TAU - 0.5) * 0.9
		var c1 := 2.0 * sin(PI * f1 / MIX_RATE)
		var c2 := 2.0 * sin(PI * f2 / MIX_RATE)
		lp1 += c1 * bp1
		bp1 += c1 * (src - lp1 - 0.25 * bp1)
		lp2 += c2 * bp2
		bp2 += c2 * (src - lp2 - 0.3 * bp2)
		var v := (bp1 * 0.6 + bp2 * 0.45) * env
		# Radio: hard clipped, a little hiss always.
		out.append(clampf(v * 0.9, -0.5, 0.5) + rng.randf_range(-1.0, 1.0) * 0.03)
	# The roger beep and the squelch tail.
	out.append_array(tones([[0.0, 0.03], [1650.0 if variant % 2 == 0 else 1250.0, 0.09]]))
	for i in int(0.12 * MIX_RATE):
		out.append(rng.randf_range(-1.0, 1.0) * 0.25 * exp(-float(i) / 700.0))
	return out
