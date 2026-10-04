class_name Surf
extends RefCounted
## The breaking surf in GDScript: the same model as shaders/surf.gdshaderinc (read its header
## for what it is), for the three things that cannot run on the GPU. Weather works out the two
## globals the shaders read from the weather (`params()`), CityChunk places the spray along the
## break line, and the smoke test checks the envelope (no surf on the sand, the biggest face at
## the break, a storm far bigger than a calm day). The functions mirror their GLSL namesakes line
## for line; change one, change both (tests/surf_checks.gd compares them on sample points).

## The surf at wave_scale 1 (a clear day: two- to three-foot South Bay surf): face height and
## crest spacing in metres, period in seconds, break distance offshore in metres, run-up of the
## swash up the sand in metres, lip throw as a share of the face, how many periods a swash lasts.
const HEIGHT := 0.9
const LENGTH := 24.0
const PERIOD := 8.0
const BREAK := 38.0
const RUNUP := 12.0
const LIP := 0.6
const SWASH_PERIODS := 1.3
## GLSL surf_wave_gain(): a wave's height share runs from H_LO to H_LO + H_SPAN.
const H_LO := 0.62
const H_SPAN := 0.68


## The two globals for a sea of `wave_scale` (Weather's: 1 clear, 1.8 overcast, 3.2 rain, 6 storm):
## [surf_shape, surf_extra]. Bigger seas are taller, longer, slower, break further out, run
## further up the sand and have a wider surf zone; `gain` scales the height alone (Weather's
## surf_gain export).
static func params(wave_scale: float, gain: float = 1.0) -> Array[Vector4]:
	var f := clampf(wave_scale, 0.3, 7.0)
	var height := HEIGHT * (0.55 + 0.45 * f) * maxf(gain, 0.0)
	var rel := maxf(height / HEIGHT, 0.05)
	var length := LENGTH * (1.0 + 0.10 * (f - 1.0))
	var period := PERIOD * (1.0 + 0.09 * (f - 1.0))
	var brk := BREAK * pow(rel, 0.85)
	var runup := RUNUP * pow(rel, 0.6)
	var zone := brk * 2.4 + 25.0
	return [Vector4(height, length, period, brk), Vector4(runup, LIP, zone, SWASH_PERIODS)]


## GLSL surf_envelope(): [envelope, sig, steep] for a wave of gain g at s metres offshore.
static func envelope(shape: Vector4, extra: Vector4, s: float, g: float) -> Vector3:
	var brk := maxf(shape.w * pow(g, 0.8), 2.0)
	var sig := s / brk
	var start := maxf(extra.z, brk * 1.4)
	var steep := 1.0 - smoothstep(1.0, 1.9, sig)
	var rise := 1.0 - smoothstep(1.0, start / brk, sig)
	var unbroken := rise * rise * (0.55 + 0.45 * steep)
	var bore := 0.5 * sqrt(maxf(sig, 0.0)) + 0.5 * smoothstep(0.80, 1.0, sig)
	var env := unbroken if sig >= 1.0 else bore
	return Vector3(env * smoothstep(0.0, 4.0, s), sig, steep)


## The height of the biggest face of a wave of gain g, metres, at s metres offshore (the crest,
## profile 1, less the held mean level): what the ocean mesh is lifted by there at most.
static func crest_height(shape: Vector4, extra: Vector4, s: float, g: float) -> float:
	var e := envelope(shape, extra, s, g)
	var m := envelope(shape, extra, s, 1.0)
	return shape.x * (g * e.x - 0.22 * m.x)


## Metres offshore the mean wave breaks at, for placing the spray.
static func break_distance(shape: Vector4) -> float:
	return shape.w
