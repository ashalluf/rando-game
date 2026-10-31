class_name RainStreetNight
extends RefCounted
## The street_night reference camera's review (Flower at Olympic, 21:30, rain; docs/HANDOFF.md
## "The rainy night street, refcam review"): what read fake first in that frame, fixed in the
## systems that draw it, all in one place with the switch. RAIN_STREET_NIGHT=0 in the environment
## puts every one of them back exactly as it was (the A/B).
##
## - The street lamps' reflections in the wet road (NightAtmos' `atmos_glow_wet`, night_wet.gdshader)
##   were thin bars of constant colour from each pole's foot to the frame's bottom: glowing rods stood
##   on the asphalt. Now a soft column peaked at the mirror point, rippled into rows (`dress_wet()`).
## - The rain curtain (Weather's unshaded cylinder) drew the same pale blue streaks at midnight as at
##   noon: white scratches down every dark facade and the black sky. At night it takes the city's
##   sodium light and fades (`curtain_night_code()`, the shader's `night_look`).
## - The drops on the lens were pale flat discs (bokeh dust). Now they refract the frame behind them,
##   upside down and blurred, with a bright meniscus rim (`shaders/rain_lens.gdshader`).
## - The rain particles' own glow (their emission) is cut at night, so drops show where a light
##   catches them and not as an even pale field (`drop_glow()`).
## - Cars' head and tail lamps threw no reflection on the wet road: `WetCarGlints` lays one on the
##   nearest running cars.

static var enabled: bool = OS.get_environment("RAIN_STREET_NIGHT") != "0"

## The rain particles' emission (Weather's raindrop material) by day and at full lamp level.
const DROP_GLOW_DAY := 0.18
const DROP_GLOW_NIGHT := 0.12


## The streak shader's switch, set on NightAtmos' "wet" material when it is made.
static func dress_wet(mat: ShaderMaterial) -> void:
	if mat:
		mat.set_shader_parameter("look2", 1.0 if enabled else 0.0)


## The value baked into the rain curtain shader's `night_look` default (Weather and StormDrama's
## inner curtain share the shader, so both get it).
static func curtain_night_code() -> String:
	return "1.0" if enabled else "0.0"


## The raindrop material's emission at lamp level `lamp` (0 day .. 1 night).
static func drop_glow(lamp: float) -> float:
	if not enabled:
		return DROP_GLOW_DAY
	return lerpf(DROP_GLOW_DAY, DROP_GLOW_NIGHT, clampf(lamp, 0.0, 1.0))


## The lens drops' shader, or null for Weather's old inline one.
static func lens_shader() -> Shader:
	return load("res://shaders/rain_lens.gdshader") if enabled else null


## The overcast night sky: the city's sodium light on a low rain deck. At DayNight's numbers the
## zenith of a rainy night was 0.045 (all but black) over a lit band at the horizon, so the deck
## read as a clear black sky with a few lit wisps; a real one is a dull orange-brown lid all over.
## Its zenith colour x STORM_TOP_GAIN at night, the night glow x STORM_GLOW_GAIN, the cloud's own
## night light under full overcast OVERCAST_CLOUD (DayNight's 0.025).
const STORM_TOP_GAIN := 1.75
const STORM_GLOW_GAIN := 1.4
const OVERCAST_CLOUD := 0.042
const OVERCAST_CLOUD_OLD := 0.025


static func storm_top(top: Color, moonlight: float) -> Color:
	if not enabled:
		return top
	var k := lerpf(1.0, STORM_TOP_GAIN, clampf(moonlight, 0.0, 1.0))
	return Color(top.r * k, top.g * k, top.b * k, top.a)


static func storm_glow_gain() -> float:
	return STORM_GLOW_GAIN if enabled else 1.0


static func overcast_cloud_light() -> float:
	return OVERCAST_CLOUD if enabled else OVERCAST_CLOUD_OLD
