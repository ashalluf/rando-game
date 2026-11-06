class_name RainDay
extends RefCounted
## The rainy day (refcam `rain_day`: Wilshire in midtown at 14:00 in rain; docs/HANDOFF.md "The rainy
## day"). Daylight rain was the clear day with a grey sky painted over it: the sun still threw crisp
## shadows of every pole and palm across a sunlit pavement, so the street read as a sunny afternoon
## with rain drawn on the lens. Under a rain deck there is no direct sun at all - the light is the
## whole grey sky, soft and from above - and the eye reads "wet" by what the ground mirrors.
##
## Every number is here with the switch: RAIN_DAY=0 in the environment puts each one back as it was
## (the A/B). Read by DayNight (the sun, its shadows, the sky fill), SkyBeam (no searchlights by day)
## and Weather (the lens drops by day). Pure functions of the weather and the light, so the checks
## (tests/rc2_rain_day_checks.gd) pin them without a city.

static var enabled: bool = OS.get_environment("RAIN_DAY") != "0"

## How overcast the daylight is: DayNight's weather_darken through the same 1.6 ramp the sky's
## cloud cover uses (overcast 0.4, rain 0.8, a storm 1), and nothing after dark (the night's rain
## look is RainStreetNight's and stays bit for bit).
static func overcast(weather_darken: float, moonlight: float) -> float:
	if not enabled:
		return 0.0
	return clampf(weather_darken * 1.6, 0.0, 1.0) * clampf(1.0 - moonlight, 0.0, 1.0)


## The sun's key under the deck, a share of what DayNight gave it: rain leaves 0.3 of it (with the
## old 0.75 x darken cut on top, a twelfth of the clear sun) - it still models the facades a little,
## the way a thin spot in the deck does.
const SUN_CUT := 0.7
## The shadows' opacity: under rain they are the soft contact darkening a diffuse sky leaves, not a
## pole's outline across the pavement.
const SHADOW_CUT := 0.8
## The sky fill, raised for the light the sun gave up (the ambient is the sky's own grey radiance,
## so the shadows keep its colour). Godot ignores ambient_light_energy while the sky contribution is
## 1.0 (GiTuning, HIGH): there the fill is the sky's radiance and SDFGI's, and the player camera's
## auto exposure makes up the rest of the sun the deck took.
const AMBIENT_GAIN := 0.9


static func sun_gain(weather_darken: float, moonlight: float) -> float:
	return 1.0 - SUN_CUT * overcast(weather_darken, moonlight)


static func shadow_gain(weather_darken: float, moonlight: float) -> float:
	return 1.0 - SHADOW_CUT * overcast(weather_darken, moonlight)


static func ambient_gain(weather_darken: float, moonlight: float) -> float:
	return 1.0 + AMBIENT_GAIN * overcast(weather_darken, moonlight)


## The sky's rain deck by day (sky.gdshader `rain_deck`): rain and a storm (weather_darken 0.5 and
## over), not plain overcast (0.25), and nothing at night.
static func rain_deck(weather_darken: float, moonlight: float) -> float:
	if not enabled:
		return 0.0
	return smoothstep(0.25, 0.5, weather_darken) * clampf(1.0 - moonlight, 0.0, 1.0)


## The lamp level a thing that only burns AFTER DARK should see (a premiere's searchlight): the
## lamps' own night level, not the weather's share that DayNight adds so the street lamps and car
## lamps come on under a storm at noon. DayNight writes `night_lamp` each frame.
static var night_lamp: float = 0.0


static func after_dark_lamp(lamp_now: float) -> float:
	return night_lamp if enabled else lamp_now


## The daylight weight of the wet road's day mirror (shaders/rain_day_mirror.gdshaderinc, the
## `rain_day` shader global): 1 by day, 0 once the lamps' own night level is up (so the night's
## mirror, RainStreetNight's and WetRoadMirror's, is bit for bit what it was), 0 with RAIN_DAY=0.
static func day_weight(night_lamps: float) -> float:
	return clampf(1.0 - night_lamps, 0.0, 1.0) if enabled else 0.0


static var _pushed: float = -1.0


## DayNight's one call a frame: the after-dark lamp level and the road's day weight.
static func publish(night_lamps: float) -> void:
	night_lamp = night_lamps
	var w := day_weight(night_lamps)
	if absf(w - _pushed) > 0.0005 or (w == 0.0 and _pushed != 0.0):
		_pushed = w
		RenderingServer.global_shader_parameter_set("rain_day", w)


## Tyre spray (TyreSpray's exports, set once in its _ready()): cars throw it out to SPRAY_REACH m
## (55 was half a block: a boulevard's spray down the street was never drawn), at its fullest from
## a city street's speed (24 m/s was freeway speed), each puff a thicker veil. The six emitters
## still go to the fastest cars, nearest first.
const SPRAY_REACH := 95.0
const SPRAY_FULL_SPEED := 16.0
const SPRAY_ALPHA := 0.6


## The lens drops by day: refracting the bright, even sky behind them they read as grey dust
## discs over the whole frame (a camera in the rain by day gets a few, at the edges). A share of
## Weather's lens_rain, by how much daylight there is (1 at night: RainStreetNight's look).
const LENS_DAY := 0.35


static func lens_gain(daylight: float) -> float:
	if not enabled:
		return 1.0
	return lerpf(1.0, LENS_DAY, clampf(daylight, 0.0, 1.0))
