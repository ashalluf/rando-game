class_name SkyDay
## The day sky (fleet wave 4, "sky-day-review"; docs/HANDOFF.md "The day sky"): how much of
## sky.gdshader's daytime look is on. A weight on the CLOCK, 0 at and before 09:00 and at and
## after 16:00, full from 10:00 to 15:00, so dawn, the golden hour, the sunset and the night are
## bit-identical (every day block in the shader is a branch on it or a gain that is 1.0 at 0).
## Under rain, a storm or the marine layer it fades out: those skies are the weather's.
##
## What the shader does with it: the blue comes down nearer the horizon and the pale band hugs it
## (the horizon colour itself is untouched, so the far land and the fog still meet it); the
## cirrus veil is broken into wisps and thinned; the sun's halo is tight and nearly white and the
## disc a bright half degree; the cumulus volume's lit sides near white, the shaded sides and the
## bases a cleaner blue-grey, far clouds hazed sooner and fewer fragments carpeting the horizon;
## the painted cumulus (web, low levels) a brighter lit side.
##
## SKY_DAY=0 in the environment is the A/B (the sky exactly as before at every hour).

## The clock hours the weight ramps in between and out between.
const RAMP_IN := Vector2(9.0, 10.0)
const RAMP_OUT := Vector2(15.0, 16.0)

static var enabled: bool = OS.get_environment("SKY_DAY") != "0"


## The weight for an hour and the weather: pure.
static func weight(hour: float, weather_darken: float = 0.0, marine: float = 0.0) -> float:
	if not enabled:
		return 0.0
	var h := fposmod(hour, 24.0)
	if h <= RAMP_IN.x or h >= RAMP_OUT.y:
		return 0.0
	var w := smoothstep(RAMP_IN.x, RAMP_IN.y, h) * (1.0 - smoothstep(RAMP_OUT.x, RAMP_OUT.y, h))
	w *= 1.0 - clampf(weather_darken * 1.6, 0.0, 1.0)
	w *= 1.0 - clampf(marine, 0.0, 1.0)
	return w


## Hands the weight to the sky material (DayNight._apply(), once a frame).
static func apply(sky: ShaderMaterial, hour: float, weather_darken: float, marine: float) -> void:
	if sky == null:
		return
	sky.set_shader_parameter("sky_day", weight(hour, weather_darken, marine))
