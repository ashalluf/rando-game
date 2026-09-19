extends Node
## Autoload: sound effects synthesized at startup (no audio files). play() for one-shots at a
## position, loop_player() for engine / boost loops the caller owns and pitches.

const MIX_RATE := 22050
const POOL_SIZE := 20

var _streams: Dictionary = {}
var _pool: Array[AudioStreamPlayer3D] = []
var _next: int = 0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 1
	_streams["shot"] = _wav(_noise_burst(0.10, 40.0, 0.9, 0.35))
	_streams["rocket"] = _wav(_noise_burst(0.35, 9.0, 0.7, 0.08))
	_streams["explosion"] = _wav(_noise_burst(1.3, 3.5, 1.0, 0.03))
	_streams["grab"] = _wav(_sweep(0.22, 220.0, 900.0, 0.5))
	_streams["launch"] = _wav(_sweep(0.25, 900.0, 200.0, 0.7))
	_streams["jump"] = _wav(_sweep(0.16, 320.0, 640.0, 0.45))
	_streams["land"] = _wav(_thud(0.12, 90.0, 0.7))
	_streams["thud"] = _wav(_thud(0.18, 70.0, 0.9))
	_streams["break"] = _wav(_noise_burst(0.28, 14.0, 0.8, 0.2))
	_streams["yelp"] = _wav(_yelp(0.4))
	_streams["click"] = _wav(_sweep(0.05, 1200.0, 900.0, 0.4))
	_streams["boost_loop"] = _wav(_boost_loop(0.6), true)
	_streams["engine_loop"] = _wav(_engine_loop(0.4), true)
	for i in POOL_SIZE:
		var p := AudioStreamPlayer3D.new()
		p.max_distance = 220.0
		p.unit_size = 12.0
		add_child(p)
		_pool.append(p)


func has(name: String) -> bool:
	return _streams.has(name)


func play(name: String, at: Vector3, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if not _streams.has(name):
		return
	var p := _pool[_next]
	_next = (_next + 1) % POOL_SIZE
	p.stop()
	p.stream = _streams[name]
	p.global_position = at
	p.volume_db = volume_db
	p.pitch_scale = pitch * _rng.randf_range(0.94, 1.06)
	p.play()


## A looping player for the caller to parent and control.
func loop_player(name: String, volume_db: float = -6.0) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.stream = _streams.get(name)
	p.volume_db = volume_db
	p.max_distance = 120.0
	p.unit_size = 10.0
	return p


# --- Synthesis ---------------------------------------------------------------------------

func _wav(samples: PackedFloat32Array, looping: bool = false) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		var v := int(clampf(samples[i], -1.0, 1.0) * 32767.0)
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
