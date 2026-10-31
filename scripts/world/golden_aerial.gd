class_name GoldenAerial
## The golden-aerial review (fleet wave 4, `rc-golden-aerial`; docs/HANDOFF.md "The golden aerial"):
## the reference camera golden_aerial (downtown from the south-west, 140 m up, 17:12 clear) judged
## as an art director would, and the worst of what read fake fixed:
## - The far mountains were lit by a NOON sun at every hour: macro_ground's painted band (past
##   ~2.3 km, it lights itself) had a fixed cream `sun_color` at full strength, while the city and
##   the near hills took DayNight's real light (orange, half its energy at 17:12). So the ranges
##   behind downtown were pale cream, brighter than the city, and as flat as paper. `ground_light()`
##   hands the plane the sun's real colour and energy.
## - Their shadowed faces took the sky's HORIZON colour as fill (warm beige at golden hour), so the
##   shade was the same hue as the light and the ranges read as one beige. A slope's sky fill comes
##   mostly from above: at golden hour it now leans to the zenith's blue, so lit faces are warm and
##   shaded canyons cool, which is what reads as a low sun on a mountain.
## - The sky's mid deck (sky.gdshader, painted path and a thin veil next to the volume) was one
##   smooth fbm field cut by a threshold: one soft grey blob a quarter of the sky across. It is a
##   field of small cloudlets now (`mid_cells`), lit by the low sun like the cirrus.
## GOLDEN_AERIAL=0 in the environment is the A/B: every number as it was.

static var enabled: bool = OS.get_environment("GOLDEN_AERIAL") != "0"

## How far the shaded faces' sky fill goes to the zenith's colour at the height of golden hour
## (an upward-facing slope; a steep face sees more of the horizon and takes less).
const FILL_TOP := 0.75
## The zenith colour handed over at the horizon's brightness times this (the zenith is darker,
## but the fill is the whole upper sky, not the darkest point of it).
const FILL_TOP_LEVEL := 0.85
## The painted band's sun follows the real light's energy relative to noon's, never above it.
const SUN_GAIN_MIN := 0.25


static func _lum(c: Color) -> float:
	return c.r * 0.2126 + c.g * 0.7152 + c.b * 0.0722


## The horizon plane's painted light from DayNight's: the sun's colour (the light's, a Color like
## the uniform's default), its energy as a share of noon's, and the cool fill at golden hour.
## `sky_top` / `horizon` are the sky shader's colours (sRGB); `golden` is DayNight.golden.
static func ground_light(mat: ShaderMaterial, sun_color: Color, sun_energy: float, day_energy: float,
		sky_top: Color, horizon: Color, golden: float, night: float) -> void:
	if mat == null:
		return
	if not enabled:
		mat.set_shader_parameter("sun_color", Color(1.0, 0.955, 0.88))
		mat.set_shader_parameter("sun_gain", 1.0)
		mat.set_shader_parameter("fill_top_mix", 0.0)
		return
	# By night the plane dims itself (`dim`); keep the sun's colour and gain to the day's side.
	var day := 1.0 - clampf(night, 0.0, 1.0)
	mat.set_shader_parameter("sun_color", Color(1.0, 0.955, 0.88).lerp(sun_color, day))
	mat.set_shader_parameter("sun_gain", lerpf(1.0, clampf(sun_energy / maxf(day_energy, 0.001), SUN_GAIN_MIN, 1.0), day))
	var top := sky_top.srgb_to_linear()
	var hor := horizon.srgb_to_linear()
	var k := _lum(hor) / maxf(_lum(top), 0.001) * FILL_TOP_LEVEL
	mat.set_shader_parameter("fill_top", Vector3(top.r * k, top.g * k, top.b * k))
	mat.set_shader_parameter("fill_top_mix", FILL_TOP * clampf(golden, 0.0, 1.0) * day)


## The sky shader's switches.
static func sky(mat: ShaderMaterial) -> void:
	if mat:
		mat.set_shader_parameter("mid_cells", 1.0 if enabled else 0.0)
