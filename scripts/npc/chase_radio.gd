class_name ChaseRadio
extends Node
## Police radio chatter during a chase (PoliceChase): a transmission is the key-up chirp, a burst
## of a voice through a radio - band-limited to 300-3,000 Hz, clipped and hissy - and the
## squelch tail as the key comes up. There is no CC0 recording of dispatch speech to use, so
## the voice is synthesised: syllables of a glottal pulse train (a male voice at 100-140 Hz with
## jitter and a falling contour) through two formant resonators per syllable, with a fricative
## burst on some, at a talking rate. It reads as a garbled officer on the radio, not as words.
## Never a real agency's call signs or codes (there are no words at all).
##
## say(kind) queues one transmission for an event; the length of the babble depends on the kind
## (a new pursuit is a long call, a PIT a short one), at most one at a time, with a gap after each.
## Played only while the player is wanted, non-positional on the World bus, quiet. The streams
## are built once, a few on first use (~30 ms each). `POLICE_RADIO=0` turns it off.

static var enabled: bool = OS.get_environment("POLICE_RADIO") != "0"

## Loudness (dB), the quiet between transmissions (s) and how long a queued call keeps (s).
@export var volume_db: float = -15.0
@export var gap_seconds: float = 2.2
@export var stale_seconds: float = 4.0

const RATE := 16000
## Babble length per kind (s). Unknown kinds are short calls.
const LENGTHS := {"pursuit": 2.4, "pit": 1.3, "pit_done": 0.9, "box": 1.4, "boxed": 1.8, "spikes": 1.7,
	"advance": 0.8, "shots": 1.5, "down": 2.0, "lost": 1.9}
const VARIANTS := 6

## Transmissions played (the checks read it).
var played: int = 0
var last_kind: String = ""
var _player: AudioStreamPlayer
var _queue: Array = []
var _quiet: float = 0.0
var _count: int = 0
var _streams: Dictionary = {}


func _ready() -> void:
	_player = AudioStreamPlayer.new()
	_player.name = "Speaker"
	_player.volume_db = volume_db
	_player.bus = &"World" if AudioServer.get_bus_index(&"World") >= 0 else &"Master"
	add_child(_player)


## Asks for a transmission about `kind`. Dropped if one about the same thing is already waiting.
func say(kind: String) -> void:
	if not enabled:
		return
	for q in _queue:
		if q[0] == kind:
			return
	_queue.append([kind, Time.get_ticks_msec()])


func _process(delta: float) -> void:
	if _player.playing:
		return
	_quiet -= delta
	if _quiet > 0.0 or _queue.is_empty():
		return
	var q: Array = _queue.pop_front()
	if Time.get_ticks_msec() - int(q[1]) > int(stale_seconds * 1000.0):
		return
	var p := get_parent() as PoliceChase
	if p == null or p.police == null or p.police.stars <= 0:
		_queue.clear()
		return
	var kind: String = q[0]
	_player.stream = stream_for(kind, _count)
	_count += 1
	_player.play()
	played += 1
	last_kind = kind
	_quiet = gap_seconds


## A transmission for `kind`, variant `n` (cached: VARIANTS per length).
func stream_for(kind: String, n: int) -> AudioStreamWAV:
	var secs: float = LENGTHS.get(kind, 1.2)
	var key := "%.1f:%d" % [secs, n % VARIANTS]
	if _streams.has(key):
		return _streams[key]
	var s := transmission(secs, hash([key, "chase_radio"]))
	_streams[key] = s
	return s


## One transmission: chirp, `seconds` of voice, squelch tail. `seed_value` picks the syllables.
static func transmission(seconds: float, seed_value: int) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var out := PackedFloat32Array()
	# Key-up: a short two-tone chirp.
	_tone(out, 0.045, 1350.0, 0.22)
	_tone(out, 0.03, 1900.0, 0.16)
	_silence(out, 0.05)
	var voice := _voice(seconds, rng)
	out.append_array(voice)
	# Key-down: the squelch tail, a hiss that cuts off.
	var tail := int(0.13 * RATE)
	for i in tail:
		var e := 1.0 - float(i) / float(tail)
		out.append((rng.randf() * 2.0 - 1.0) * 0.28 * e)
	# The radio: band-pass 300-3000 Hz, then a soft clip and a floor of hiss.
	out = _bandpass(out, 300.0, 3000.0)
	var peak := 0.0001
	for v in out:
		peak = maxf(peak, absf(v))
	for i in out.size():
		var x := out[i] / peak * 1.6
		out[i] = x / (1.0 + absf(x)) * 1.25 + (rng.randf() * 2.0 - 1.0) * 0.03
	# The clip's harmonics and the hiss go through the speaker's own top end too.
	out = _bandpass(out, 250.0, 3200.0)
	peak = 0.0001
	for v in out:
		peak = maxf(peak, absf(v))
	var bytes := PackedByteArray()
	bytes.resize(out.size() * 2)
	for i in out.size():
		bytes.encode_s16(i * 2, int(clampf(out[i] / peak * 0.9, -1.0, 1.0) * 30000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = bytes
	return wav


## Vowel formants (F1, F2) a syllable picks from.
const VOWELS := [Vector2(730, 1090), Vector2(530, 1840), Vector2(270, 2290), Vector2(570, 840), Vector2(300, 870),
	Vector2(660, 1720), Vector2(440, 1020), Vector2(490, 1350)]


static func _voice(seconds: float, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var total := int(seconds * RATE)
	var f0 := rng.randf_range(100.0, 140.0)
	var phase := 0.0
	while out.size() < total:
		# A syllable: 70-190 ms voiced, sometimes a fricative onset, then a short gap.
		var syl := int(rng.randf_range(0.07, 0.19) * RATE)
		var v: Vector2 = VOWELS[rng.randi() % VOWELS.size()]
		var v2: Vector2 = VOWELS[rng.randi() % VOWELS.size()]
		if rng.randf() < 0.4:
			var fr := int(rng.randf_range(0.02, 0.05) * RATE)
			var prev := 0.0
			for i in fr:
				var n := rng.randf() * 2.0 - 1.0
				# A crude high-pass: what is left of white noise after its own low end.
				out.append((n - prev) * 0.35)
				prev = n
		var y1 := [0.0, 0.0]
		var y2 := [0.0, 0.0]
		var progress := float(out.size()) / float(total)
		for i in syl:
			var u := float(i) / float(syl)
			var pitch := f0 * (1.0 - 0.18 * progress) * (1.0 + 0.04 * sin(u * PI)) * (1.0 + rng.randf_range(-0.02, 0.02))
			phase += pitch / float(RATE)
			var pulse := 0.0
			if phase >= 1.0:
				phase -= 1.0
				pulse = 1.0
			var f := v.lerp(v2, u)
			var a := sin(u * PI)
			var s1 := _reso(pulse, f.x, 90.0, y1)
			var s2 := _reso(pulse, f.y, 120.0, y2)
			out.append((s1 + s2 * 0.6) * a * 0.08)
		_silence(out, rng.randf_range(0.015, 0.06) if rng.randf() < 0.8 else rng.randf_range(0.12, 0.22))
	out.resize(total)
	return out


## A two-pole resonator at `freq` with bandwidth `bw` (Hz); `y` holds its last two outputs.
static func _reso(x: float, freq: float, bw: float, y: Array) -> float:
	var r := exp(-PI * bw / float(RATE))
	var c := 2.0 * r * cos(TAU * freq / float(RATE))
	var out := x + c * float(y[0]) - r * r * float(y[1])
	y[1] = y[0]
	y[0] = out
	return out


static func _tone(out: PackedFloat32Array, seconds: float, freq: float, gain: float) -> void:
	var n := int(seconds * RATE)
	for i in n:
		var e := minf(1.0, minf(float(i), float(n - i)) / 80.0)
		out.append(sin(TAU * freq * float(i) / float(RATE)) * gain * e)


static func _silence(out: PackedFloat32Array, seconds: float) -> void:
	for i in int(seconds * RATE):
		out.append(0.0)


## One-pole high-pass at `lo` then two one-pole low-passes at `hi`.
static func _bandpass(x: PackedFloat32Array, lo: float, hi: float) -> PackedFloat32Array:
	var dt := 1.0 / float(RATE)
	var rc_lo := 1.0 / (TAU * lo)
	var a_hp := rc_lo / (rc_lo + dt)
	var rc_hi := 1.0 / (TAU * hi)
	var a_lp := dt / (rc_hi + dt)
	var out := PackedFloat32Array()
	out.resize(x.size())
	var hp := 0.0
	var prev := 0.0
	var l1 := 0.0
	var l2 := 0.0
	for i in x.size():
		hp = a_hp * (hp + x[i] - prev)
		prev = x[i]
		l1 += a_lp * (hp - l1)
		l2 += a_lp * (l1 - l2)
		out[i] = l2
	return out
