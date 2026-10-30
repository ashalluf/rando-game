class_name SunsetSky
## The sunset sky (fleet wave 3, "sunset-clouds"): how much of sky.gdshader's sunset model is on.
## It is a weight on the sun's elevation alone, ramping in from about 19 degrees up, full through
## the sunset and the first minutes after it, and out again by about 13 degrees under, so noon and
## the night are untouched (the shader skips every block it adds at 0). Under overcast, rain or
## the marine layer there is no sunset to light. DayNight calls `apply()` once a frame.
##
## What the shader does with it (docs/HANDOFF.md, "The Los Angeles sunset"): every cloud sample,
## the painted deck and the cirrus are lit by the sun as it reaches THAT point - reddened by the
## air along the path (sun_through()) and dark once the earth stands between them - so the
## cumulus bases glow from below after the street's sunset while the tops go violet, the cirrus
## keep their afterglow minutes longer, the rays fan wide in the sun's own red, and opposite the
## sun the earth's shadow rises with the Belt of Venus over it.
##
## SUNSET_CLOUDS=0 in the environment is the A/B (the sky exactly as before).

## Sun elevations (sine) the weight ramps in between (high, full) and out between (full, gone).
const RAMP_IN := Vector2(0.33, 0.17)
const RAMP_OUT := Vector2(-0.10, -0.23)
## The crepuscular rays while the sunset is on (sky.gdshader `sunset_rays`).
const RAYS := 0.45

## sun_through()'s optical depths a unit air mass (Rayleigh, aerosol): the shader's numbers, which
## tests/sunset_clouds_checks.gd reads back out of sky.gdshader.
const TAU_RAYLEIGH := Vector3(0.032, 0.074, 0.180)
const TAU_AEROSOL := Vector3(0.085, 0.115, 0.150)
const EARTH_R := 6371.0

static var enabled: bool = OS.get_environment("SUNSET_CLOUDS") != "0"


## The weight for a sun elevation (sine of the arc) and the weather: pure.
static func weight(elevation: float, weather_darken: float = 0.0, marine: float = 0.0) -> float:
	if not enabled:
		return 0.0
	var w := smoothstep(RAMP_IN.x, RAMP_IN.y, elevation) * smoothstep(RAMP_OUT.y, RAMP_OUT.x, elevation)
	w *= 1.0 - clampf(weather_darken * 1.5, 0.0, 1.0)
	w *= 1.0 - 0.8 * clampf(marine, 0.0, 1.0)
	return w


## Hands the weight to the sky material.
static func apply(sky: ShaderMaterial, elevation: float, weather_darken: float, marine: float) -> void:
	if sky == null:
		return
	sky.set_shader_parameter("sunset", weight(elevation, weather_darken, marine))
	sky.set_shader_parameter("sunset_rays", RAYS * (1.0 - clampf(weather_darken, 0.0, 1.0) * 0.6))


## sky.gdshader's sun_through() in GDScript: the low sun as it reaches a point `h` km up at local
## elevation `el` (sine). Returns Color(r, g, b normalised to red, a = brightness, 0 in the
## earth's shadow). Change one, change both.
static func sun_through(el: float, h: float, aerosol: float = 1.0) -> Color:
	h = maxf(h, 0.0)
	var er := exp(-h / 8.0)
	var ea := exp(-h / 1.4)
	var ht := h if el >= 0.0 else h - el * el * EARTH_R * 0.5
	var mr: float
	var ma: float
	if el >= 0.0:
		mr = er / (el + 0.03)
		ma = ea / (el + 0.05)
	else:
		var htc := maxf(ht, 0.0)
		mr = (2.0 * exp(-htc / 8.0) - er) / 0.03
		ma = (2.0 * exp(-htc / 1.4) - ea) / 0.05
	var tau := TAU_RAYLEIGH * mr + TAU_AEROSOL * aerosol * ma
	var tr := Vector3(exp(-tau.x), exp(-tau.y), exp(-tau.z))
	var m := maxf(tr.x, 1e-4)
	var lit := smoothstep(-0.2, 0.3, ht)
	return Color(tr.x / m, tr.y / m, tr.z / m, lit * lerpf(0.45, 1.0, smoothstep(0.0, 0.35, m)))
