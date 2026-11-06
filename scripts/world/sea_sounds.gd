class_name SeaSounds
extends RefCounted
## The sounds of the life in the water (SeaLife), synthesised once and cached (no recordings
## shipped, like ServiceSounds): a sea lion's bark - a hoarse, honking "ork", a pulsed voice with
## its throat's formants and breath rasp over it -, a splash (a burst of water noise with the
## bubbles' plinks in it), a pelican's plunge (a thump and a heavier splash), a dolphin's puff of
## breath and a whale's blow (a long low roar of breath, heard across the water).

const RATE := 22050

static var _cache: Dictionary = {}


static func stream(name: String) -> AudioStreamWAV:
	if _cache.has(name):
		return _cache[name]
	var s: PackedFloat32Array
	match name:
		"bark":
			s = _bark(0.34)
		"plunge":
			s = _splash(1.0, 1.6, 0.45)
		"puff":
			s = _breath(0.32, 2600.0, 0.5)
		"blow":
			s = _breath(1.9, 700.0, 1.0)
		_:
			s = _splash(0.6, 1.0, 0.0)
	var w := ServiceSounds._wav(s, false)
	_cache[name] = w
	return w


## "Ork": a glottal pulse train (a sawtooth's harmonics weighted by two formants) falling from
## 330 to 240 Hz, a quick attack and a rough decay, the rasp as noise gated by the pulses.
static func _bark(seconds: float) -> PackedFloat32Array:
	var n := int(seconds * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7331
	var ph := 0.0
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		var u := t / seconds
		var f0 := lerpf(330.0, 240.0, u) * (1.0 + 0.04 * sin(t * 60.0))
		ph += f0 / RATE
		var v := 0.0
		for h in range(1, 14):
			var f := f0 * float(h)
			var form := exp(-pow((f - 650.0) / 260.0, 2.0)) + 0.7 * exp(-pow((f - 1250.0) / 320.0, 2.0)) + 0.25 * exp(-pow((f - 2500.0) / 500.0, 2.0))
			v += sin(TAU * ph * float(h)) * form / float(h) * 3.0
		var pulse := pow(0.5 + 0.5 * sin(TAU * ph), 3.0)
		lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.35
		v += lp * pulse * 0.9
		var env := smoothstep(0.0, 0.025, t) * pow(1.0 - u, 1.4)
		out[i] = v * env
	return out


## A splash: a burst of noise, darker as it goes, with bubble plinks (rising sines that ring
## off) scattered through it; `thump` adds a low hit at the start (a body going in).
static func _splash(seconds: float, size: float, thump: float) -> PackedFloat32Array:
	var n := int(seconds * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4711 + int(size * 10.0)
	var lp := 0.0
	var lp2 := 0.0
	for i in n:
		var t := float(i) / RATE
		var u := t / seconds
		var cut := lerpf(0.55, 0.12, u)
		lp += (rng.randf_range(-1.0, 1.0) - lp) * cut
		lp2 += (lp - lp2) * 0.5
		var env := smoothstep(0.0, 0.01, t) * exp(-t * 4.5 / size)
		out[i] = lp2 * env * 1.4
		if thump > 0.0:
			out[i] += sin(TAU * 70.0 * t * (1.0 - 0.4 * u)) * exp(-t * 14.0) * thump
	# Bubbles: short rising tones.
	for b in int(14.0 * size):
		var at := rng.randf_range(0.03, seconds * 0.8)
		var f := rng.randf_range(500.0, 1500.0)
		var dur := rng.randf_range(0.02, 0.06)
		var amp := rng.randf_range(0.08, 0.25) * exp(-at * 3.0)
		var i0 := int(at * RATE)
		for k in int(dur * RATE):
			if i0 + k >= n:
				break
			var tk := float(k) / RATE
			out[i0 + k] += sin(TAU * f * tk * (1.0 + tk * 12.0)) * exp(-tk / dur * 3.0) * amp
	return out


## Breath out through a blowhole: noise through a resonance at `centre` Hz, a fast rise and a
## long fall; `rumble` mixes in the low roar of a big animal.
static func _breath(seconds: float, centre: float, rumble: float) -> PackedFloat32Array:
	var n := int(seconds * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 2024
	# A two-pole resonator on the noise.
	var r := 0.97
	var w := TAU * centre / RATE
	var a1 := 2.0 * r * cos(w)
	var a2 := -r * r
	var y1 := 0.0
	var y2 := 0.0
	var low := 0.0
	for i in n:
		var t := float(i) / RATE
		var u := t / seconds
		var x := rng.randf_range(-1.0, 1.0)
		var y := x * (1.0 - r) * 4.0 + a1 * y1 + a2 * y2
		y2 = y1
		y1 = y
		low += (x - low) * 0.02
		var env := smoothstep(0.0, 0.06, t) * pow(1.0 - u, 1.8)
		out[i] = (y * 0.8 + x * 0.12 + low * rumble * 3.0) * env
	return out
