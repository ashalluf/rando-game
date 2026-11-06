class_name ServiceSounds
extends RefCounted
## The service vehicles' sounds, synthesised once and cached (no recordings shipped): the
## garbage truck's hydraulic whine and the bang of a cart tipped into the hopper, the sweeper's
## brushes, the tow truck's winch, and the ice-cream truck's chime tune - an ORIGINAL melody
## (written here, below), played on a music-box timbre through a small tinny loudspeaker. They play
## on the World bus (Sfx.bus_for) through the vehicle's own AudioStreamPlayer3D.

const RATE := 22050

## The chime: (MIDI note, length in eighths); 0 is a rest. Two eight-bar phrases in 6/8, an
## arpeggio up and a stepwise answer down, then the same climbing a third higher - written for
## this game, not taken from any tune.
const TUNE := [
	[76, 1], [79, 1], [84, 1], [83, 1], [79, 1], [76, 1],
	[77, 1], [81, 1], [86, 1], [84, 1], [81, 1], [77, 1],
	[79, 1], [76, 1], [72, 1], [74, 1], [77, 1], [83, 1],
	[84, 3], [0, 3],
	[81, 1], [84, 1], [88, 1], [86, 1], [83, 1], [79, 1],
	[84, 1], [81, 1], [77, 1], [79, 1], [76, 1], [72, 1],
	[77, 1], [74, 1], [71, 1], [67, 1], [71, 1], [74, 1],
	[72, 3], [0, 3],
]
const EIGHTH := 0.19
const TUNE_GAP := 1.4

static var _cache: Dictionary = {}


static func stream(name: String) -> AudioStreamWAV:
	if _cache.has(name):
		return _cache[name]
	var s: AudioStreamWAV = null
	match name:
		"chime":
			s = _wav(_chime(), true)
		"hydraulic":
			s = _wav(_hydraulic(1.0), true)
		"bang":
			s = _wav(_bang(0.7), false)
		"brush":
			s = _wav(_brush(2.0), true)
		"winch":
			s = _wav(_winch(1.0), true)
	_cache[name] = s
	return s


## An AudioStreamPlayer3D on `parent` for `name`, on the World bus (not playing yet).
static func player(parent: Node3D, name: String, volume_db: float, max_distance: float) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.name = "Sound_" + name
	p.stream = stream(name)
	p.volume_db = volume_db
	p.unit_size = 6.0
	p.max_distance = max_distance
	p.attenuation_filter_cutoff_hz = 6000.0
	var sfx := parent.get_node_or_null("/root/Sfx")
	if sfx != null and sfx.has_method("bus_for"):
		p.bus = sfx.bus_for(name)
	parent.add_child(p)
	return p


static func _wav(samples: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
	var peak := 0.001
	for v in samples:
		peak = maxf(peak, absf(v))
	var g := 0.85 / peak
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, clampi(roundi(samples[i] * g * 32767.0), -32768, 32767))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = samples.size()
	return w


static func _midi(n: int) -> float:
	return 440.0 * pow(2.0, float(n - 69) / 12.0)


## The tune on a music box (a sine with an octave and an inharmonic tine partial, each decaying at
## its own rate), then through a loudspeaker horn: band-limited and a little overdriven.
static func _chime() -> PackedFloat32Array:
	var total := 0.0
	for n: Array in TUNE:
		total += float(n[1]) * EIGHTH
	var count := int((total + TUNE_GAP) * RATE)
	var out := PackedFloat32Array()
	out.resize(count)
	var t0 := 0.0
	var ring := int(0.9 * RATE)
	for n: Array in TUNE:
		var note: int = n[0]
		if note > 0:
			var f := _midi(note)
			var start := int(t0 * RATE)
			for i in mini(ring, count - start):
				var t := float(i) / RATE
				var w := TAU * f * t
				var v := sin(w) * exp(-t * 3.2) + 0.35 * sin(2.0 * w) * exp(-t * 6.0) + 0.18 * sin(5.4 * w) * exp(-t * 14.0)
				v *= minf(t * 400.0, 1.0)
				out[start + i] += v
		t0 += float(n[1]) * EIGHTH
	# The horn: a high-pass (no bass from a 6-inch speaker), soft clipping, a low-pass.
	var hp := 0.0
	var prev := 0.0
	var lp := 0.0
	for i in count:
		var x := out[i]
		hp = 0.93 * (hp + x - prev)
		prev = x
		var y := tanh(hp * 1.8)
		lp += (y - lp) * 0.55
		out[i] = lp
	return out


## A hydraulic pump under load: a buzz at the pump's piston rate over a whine, a little hiss.
static func _hydraulic(seconds: float) -> PackedFloat32Array:
	var n := int(seconds * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 911
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		var saw := fposmod(t * 120.0, 1.0) * 2.0 - 1.0
		var whine := sin(TAU * 660.0 * t) * 0.25 + sin(TAU * 1320.0 * t) * 0.08
		var ripple := 0.65 + 0.35 * sin(TAU * 24.0 * t)
		lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.3
		out[i] = (saw * 0.6 * ripple + whine + lp * 0.15)
	return out


## A cart tipped against the hopper's edge: a hollow plastic bang over a steel thump.
static func _bang(seconds: float) -> PackedFloat32Array:
	var n := int(seconds * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.25
		var thump := sin(TAU * 62.0 * t) * exp(-t * 9.0)
		var hollow := sin(TAU * 190.0 * t + sin(TAU * 7.0 * t)) * exp(-t * 16.0) * 0.6
		var clank := (sin(TAU * 830.0 * t) + sin(TAU * 1460.0 * t) * 0.6) * exp(-t * 22.0) * 0.35
		out[i] = thump + hollow + clank + lp * exp(-t * 12.0) * 0.8
	return out


## Brushes on asphalt: band-limited hiss pulsing with the bristles, a rumble under it.
static func _brush(seconds: float) -> PackedFloat32Array:
	var n := int(seconds * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 314
	var a := 0.0
	var b := 0.0
	var r := 0.0
	for i in n:
		var t := float(i) / RATE
		var x := rng.randf_range(-1.0, 1.0)
		a += (x - a) * 0.6
		b += (a - b) * 0.12
		var hiss := a - b
		r += (x - r) * 0.01
		var pulse := 0.7 + 0.3 * sin(TAU * 9.0 * t)
		out[i] = hiss * pulse * 0.8 + r * 2.5 + sin(TAU * 45.0 * t) * 0.1
	return out


## A winch drawing in: a geared whine over a motor's hum.
static func _winch(seconds: float) -> PackedFloat32Array:
	var n := int(seconds * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		out[i] = sin(TAU * 410.0 * t) * 0.3 + sin(TAU * 820.0 * t) * 0.12 + (fposmod(t * 100.0, 1.0) - 0.5) * 0.5 * (0.7 + 0.3 * sin(TAU * 31.0 * t))
	return out
