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

## sun_through()'s palette (sine of the sun's elevation at the point -> linear colour) and the
## exaggerated earth radius its shadow line climbs on: sky.gdshader's numbers, which
## tests/sunset_clouds_checks.gd reads back out of the shader.
const PALETTE_E: Array[float] = [0.30, 0.15, 0.06, 0.0, -0.05, -0.10, -0.16]
const PALETTE_C: Array[Vector3] = [Vector3(1.0, 0.66, 0.36), Vector3(1.0, 0.48, 0.18), Vector3(1.0, 0.34, 0.10),
	Vector3(1.0, 0.27, 0.13), Vector3(1.0, 0.26, 0.20), Vector3(0.95, 0.18, 0.38), Vector3(0.78, 0.16, 0.52)]
## The dawn's palette at the same stops (sky.gdshader DAWN_PAL_C, mixed in by the `dawn` uniform,
## DawnReview): a cooler, pinker gold through the clean morning air.
const DAWN_PAL_C: Array[Vector3] = [Vector3(1.0, 0.72, 0.50), Vector3(1.0, 0.58, 0.40), Vector3(1.0, 0.46, 0.36),
	Vector3(1.0, 0.40, 0.38), Vector3(0.98, 0.36, 0.46), Vector3(0.90, 0.30, 0.56), Vector3(0.74, 0.28, 0.66)]
const SHADOW_R := 200.0
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
## elevation `el` (sine). Returns Color(r, g, b linear, a = brightness, 0 in the earth's shadow).
## Change one, change both.
static func sun_through(el: float, h: float, dawn: float = 0.0) -> Color:
	h = maxf(h, 0.0)
	var c: Vector3 = PALETTE_C[0]
	var d: Vector3 = DAWN_PAL_C[0]
	for i in range(1, PALETTE_E.size()):
		var k := clampf((PALETTE_E[i - 1] - el) / (PALETTE_E[i - 1] - PALETTE_E[i]), 0.0, 1.0)
		c = c.lerp(PALETTE_C[i], k)
		d = d.lerp(DAWN_PAL_C[i], k)
	if dawn > 0.0:
		c = c.lerp(d, dawn)
	var elr := minf(el + 0.01, 0.0)
	var htr := h - elr * elr * SHADOW_R * 0.5
	var lit := smoothstep(-0.4, 0.5, htr)
	return Color(c.x, c.y, c.z, lit * lerpf(0.7, 1.0, smoothstep(-0.12, 0.1, el)))
