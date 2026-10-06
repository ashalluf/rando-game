class_name HourGrade
extends RefCounted
## The look LUT, tuned per hour and weather (GAME_PLAN G4). The city Environment's
## `adjustment_color_correction` is the contrast curve AgX expects after it (CLAUDE.md, the Look
## note); it used to be one curve for every hour. Now DayNight hands this, every frame, the same
## numbers it lights the city with (golden, dusk, the sun's elevation, the slow night ramp, the
## weather hooks), and the curve and the saturation are a blend of a handful of LOOKS:
##   DAY       crisp: a firmer S through the mids, clean blacks, neutral whites.
##   GOLDEN    warm and rich: warm mids and highlights, a touch more saturation.
##   BLUE      the blue hour: cool mids and shadows, the lamps' warm highlights kept.
##   NIGHT     deep blacks and no lavender: the toe pulled down (red and blue more than green,
##             which is what turned every night shadow lavender), the sodium highlights warm.
##   MARINE    June gloom: greyer, flatter, cooler.
##   OVERCAST  rain and storm by day: a little greyer and cooler.
##   SANTA_ANA the wind's clear day: crisper and a little warmer.
## Each look is a per-channel curve laid over the scene's OWN gradient (its tscn values stay the
## base, so a tweak there still moves every hour): mid gamma, a shadow gain (multiplies the toe,
## so blacks deepen without clipping), an S-curve mix around mid grey and a highlight tint that
## leaves white white. The gradient is rebuilt only when the blend moves (`EPSILON`), which at the
## game's 48-minute day is every few seconds, a 33-point Gradient and a 256-texel upload.
## HOUR_GRADE=0 in the environment keeps the old single curve (the A/B). GRADE_RAW=1 is a tool for
## measuring: an identity curve and saturation 1, so a still is the tonemapper's own output.
##
## Photo mode swaps the Environment's curve and saturation for its filters; while the curve on
## the Environment is not ours, this writes nothing.

enum Look { DAY, GOLDEN, BLUE, NIGHT, MARINE, OVERCAST, SANTA_ANA }

## Per look: saturation, contrast (S-curve mix, negative flattens), mid gamma per channel (>1
## darkens that channel's mids), shadow gain per channel (-0.3 takes 30 % off the deepest
## values, fading out by the mids as (1 - v)^5), highlight tint per channel (added around 3/4 up, white stays white).
const LOOKS := {
	Look.DAY: {"sat": 1.30, "contrast": 0.22, "gamma": Vector3(1.0, 1.0, 1.0),
		"shadow": Vector3(-0.18, -0.18, -0.15), "high": Vector3(0.01, 0.005, -0.01)},
	Look.GOLDEN: {"sat": 1.36, "contrast": 0.16, "gamma": Vector3(0.98, 0.96, 1.1),
		"shadow": Vector3(-0.12, -0.16, -0.24), "high": Vector3(0.04, 0.025, -0.05)},
	Look.BLUE: {"sat": 1.24, "contrast": 0.10, "gamma": Vector3(1.22, 1.0, 0.97),
		"shadow": Vector3(-0.3, -0.18, -0.02), "high": Vector3(0.03, 0.01, -0.02)},
	Look.NIGHT: {"sat": 1.16, "contrast": 0.12, "gamma": Vector3(1.02, 0.99, 1.03),
		"shadow": Vector3(-0.52, -0.5, -0.54), "high": Vector3(0.03, 0.01, -0.03)},
	Look.MARINE: {"sat": 1.04, "contrast": -0.04, "gamma": Vector3(1.02, 1.0, 0.97),
		"shadow": Vector3(-0.06, -0.06, -0.03), "high": Vector3(-0.01, 0.0, 0.012)},
	Look.OVERCAST: {"sat": 1.14, "contrast": 0.08, "gamma": Vector3(1.01, 1.0, 0.985),
		"shadow": Vector3(-0.14, -0.14, -0.12), "high": Vector3(0.0, 0.0, 0.005)},
	Look.SANTA_ANA: {"sat": 1.34, "contrast": 0.24, "gamma": Vector3(0.98, 0.99, 1.04),
		"shadow": Vector3(-0.18, -0.18, -0.18), "high": Vector3(0.015, 0.005, -0.015)},
}
## Points in the rebuilt gradient (the texture is 256 texels; 33 points is under a texel apart
## in what they can move).
const POINTS := 33
## Where the base gradient and our texture are kept on the Environment.
const META_BASE := &"hour_grade_base"
const META_TEX := &"hour_grade_tex"
## How far the blended numbers must move before the gradient is rebuilt.
const EPSILON := 0.0015

## Off (HOUR_GRADE=0): the scene's single curve is left alone.
static var enabled: bool = OS.get_environment("HOUR_GRADE") != "0"
## GRADE_RAW=1: identity curve, saturation 1 (measurement only).
static var raw: bool = OS.get_environment("GRADE_RAW") == "1"

var _env: Environment
var _tex: GradientTexture1D
var _base: Gradient
var _last: PackedFloat32Array = PackedFloat32Array()
var _sat_set: float = -1.0
## The blended look in use (for tests and probes).
var current: Dictionary = {}


func _init(env: Environment) -> void:
	_env = env
	if env == null:
		return
	# A reloaded city (the pause menu's Rebuild, a test's second city) gets the SAME Environment
	# resource, already wearing the grade: the base and the texture live on the Environment, so a
	# second HourGrade shares them instead of grading the graded curve again.
	if env.has_meta(META_TEX) and env.has_meta(META_BASE):
		_tex = env.get_meta(META_TEX)
		_base = env.get_meta(META_BASE)
		env.adjustment_color_correction = _tex
		return
	var tex := env.adjustment_color_correction as GradientTexture1D
	if tex == null or tex.gradient == null:
		return
	# Our own texture over a copy of the scene's gradient, which stays the base.
	_base = tex.gradient.duplicate() as Gradient
	_tex = GradientTexture1D.new()
	_tex.width = tex.width
	_tex.gradient = _base.duplicate() as Gradient
	env.set_meta(META_BASE, _base)
	env.set_meta(META_TEX, _tex)
	env.adjustment_color_correction = _tex


func is_active() -> bool:
	return enabled and _tex != null


## The weights DayNight's numbers give each look, in blend order. Pure, for the checks.
## elevation: the sun's (sine of the arc), golden / moonlight / weather as DayNight has them.
static func weights(elevation: float, golden: float, weather_darken: float, marine: float, santa_ana: float) -> Dictionary:
	# The blue hour: the sun just under the horizon (civil twilight, about 1 to 8 degrees down),
	# before the night proper. Night takes over from about 7 degrees down.
	var blue := smoothstep(0.0, -0.05, elevation) * (1.0 - smoothstep(-0.10, -0.20, elevation))
	var night := smoothstep(-0.10, -0.26, elevation)
	return {
		Look.GOLDEN: golden * (1.0 - blue),
		Look.BLUE: blue,
		Look.NIGHT: night,
		Look.OVERCAST: clampf(weather_darken * 1.4, 0.0, 1.0) * (1.0 - 0.6 * night),
		Look.MARINE: marine * (1.0 - 0.5 * night),
		Look.SANTA_ANA: santa_ana * (1.0 - night),
	}


## The blended look for these weights: DAY, then each look lerped in by its weight in order.
static func blend(w: Dictionary) -> Dictionary:
	var out: Dictionary = (LOOKS[Look.DAY] as Dictionary).duplicate()
	for look in [Look.GOLDEN, Look.BLUE, Look.NIGHT, Look.OVERCAST, Look.MARINE, Look.SANTA_ANA]:
		var t: float = clampf(float(w.get(look, 0.0)), 0.0, 1.0)
		if t <= 0.0:
			continue
		var l: Dictionary = LOOKS[look]
		out["sat"] = lerpf(out["sat"], l["sat"], t)
		out["contrast"] = lerpf(out["contrast"], l["contrast"], t)
		for key in ["gamma", "shadow", "high"]:
			out[key] = (out[key] as Vector3).lerp(l[key], t)
	return out


## One channel of the curve: the base gradient's value `b` through the look's numbers.
static func channel(b: float, gamma: float, shadow: float, contrast: float, high: float) -> float:
	var v := pow(clampf(b, 0.0, 1.0), gamma)
	var s := 1.0 - v
	v *= 1.0 + shadow * s * s * s * s * s
	if contrast >= 0.0:
		v = lerpf(v, v * v * (3.0 - 2.0 * v), contrast)
	else:
		v = lerpf(v, 0.5, -contrast * 0.5)
	v += high * v * v * v * (1.0 - v) * 4.0
	return clampf(v, 0.0, 1.0)


## Builds the gradient for a look over `base`.
static func gradient_for(base: Gradient, look: Dictionary, identity: bool = false) -> Gradient:
	var g := Gradient.new()
	var offsets := PackedFloat32Array()
	var colors := PackedColorArray()
	var gamma: Vector3 = look["gamma"]
	var shadow: Vector3 = look["shadow"]
	var high: Vector3 = look["high"]
	var contrast: float = look["contrast"]
	for i in POINTS:
		var x := float(i) / float(POINTS - 1)
		offsets.append(x)
		if identity:
			colors.append(Color(x, x, x))
			continue
		var c := base.sample(x) if base else Color(x, x, x)
		colors.append(Color(channel(c.r, gamma.x, shadow.x, contrast, high.x),
			channel(c.g, gamma.y, shadow.y, contrast, high.y),
			channel(c.b, gamma.z, shadow.z, contrast, high.z)))
	g.offsets = offsets
	g.colors = colors
	return g


## Called by DayNight every frame with its numbers. Rebuilds only when the look moved.
func update(elevation: float, golden: float, weather_darken: float, marine: float, santa_ana: float) -> void:
	if not is_active():
		return
	if _env.adjustment_color_correction != _tex:
		return # photo mode's filter is on
	var look := blend(weights(elevation, golden, weather_darken, marine, santa_ana))
	var key := PackedFloat32Array([look["sat"], look["contrast"]])
	for k in ["gamma", "shadow", "high"]:
		var v: Vector3 = look[k]
		key.append_array([v.x, v.y, v.z])
	# Something else set the saturation (photo mode leaving puts its snapshot back): set ours again.
	if _last.size() == key.size() and is_equal_approx(_env.adjustment_saturation, _sat_set):
		var moved := 0.0
		for i in key.size():
			moved = maxf(moved, absf(key[i] - _last[i]))
		if moved < EPSILON:
			return
	_last = key
	current = look
	_sat_set = 1.0 if raw else float(look["sat"])
	# A saturation already within EPSILON of ours (photo mode leaving puts its snapshot back) is
	# kept as it is: the same look, and whoever set it reads back exactly what they wrote.
	if absf(_env.adjustment_saturation - _sat_set) < EPSILON:
		_sat_set = _env.adjustment_saturation
	else:
		_env.adjustment_saturation = _sat_set
	_tex.gradient = gradient_for(_base, look, raw)
