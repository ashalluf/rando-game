class_name RainDusk
extends RefCounted
## The rainy dusk (refcam `bus_stop_rain`: a Wilshire bus stop at 18:00 in rain; docs/HANDOFF.md
## "The bus stop in the rain"). Under a rain deck at sunset DayNight still painted the clear
## evening's colours: the clouds `dusk_cloud` orange (the weather only greyed them in a STORM), the
## horizon half `dusk`'s peach (weather_darken is 0.5 for rain), the fog pink-brown and the grade
## GOLDEN - and since the ambient IS the sky, every street, wall and face came out sepia (CCT 3,040 K
## at the bus stop). A deck of rain cloud hides the sun: an overcast dusk is a cool slate-blue
## sky with the city's warm lights in it, which is what the eye reads as "a rainy evening".
##
## The weight is the overcast (DayNight's weather_darken through the 1.6 ramp RainDay uses) times
## how much of the dusk / golden hour there is, never after dark (moonlight 1) or at midday
## (dusk and golden 0): noon rain and the rainy night stay bit for bit, and so does a clear dusk.
## RC5_BUS_STOP=0 in the environment is the A/B. Pure functions, pinned by
## tests/rc5_bus_stop_rain_checks.gd.

static var enabled: bool = OS.get_environment("RC5_BUS_STOP") != "0"

## The deck's own colour at dusk: a cool slate cloud (the cloud_color multiplier's target).
const CLOUD := Color(0.80, 0.84, 0.92)
## The sky's horizon and zenith are pulled to a slate blue-grey at their own brightness (the hue
## is what was wrong; the light level the exposure and the lamps were tuned to stays).
const SLATE := Color(0.86, 0.95, 1.12)
## How far each is taken there at full weight.
const SKY_PULL := 1.0
const FOG_PULL := 1.0
## The share of the GOLDEN grade the deck leaves (the grade's warm toe under a grey sky).
const GOLDEN_KEEP := 0.15


static func weight(weather_darken: float, dusk: float, golden: float, moonlight: float) -> float:
	if not enabled:
		return 0.0
	return clampf(weather_darken * 1.6, 0.0, 1.0) * clampf(maxf(dusk, golden), 0.0, 1.0) * clampf(1.0 - moonlight, 0.0, 1.0)


## `c` taken toward slate at its own luma, by `t`.
static func slate(c: Color, t: float) -> Color:
	if t <= 0.0:
		return c
	var l := c.r * 0.2126 + c.g * 0.7152 + c.b * 0.0722
	var s := Color(SLATE.r * l, SLATE.g * l, SLATE.b * l, c.a)
	return c.lerp(s, t)


static func sky(c: Color, w: float) -> Color:
	return slate(c, w * SKY_PULL)


static func fog(c: Color, w: float) -> Color:
	return slate(c, w * FOG_PULL)


static func cloud(c: Color, w: float) -> Color:
	return c if w <= 0.0 else c.lerp(CLOUD, w)


static func golden(g: float, w: float) -> float:
	return g * (1.0 - w * (1.0 - GOLDEN_KEEP))


## The wet road's mirror at a rainy dusk: the share of RainDay's day mirror (the canyon of daylit
## fronts) handed to the night's (the lit shop fronts, the lamps' streaks), as a lamp level.
## Under the deck at 18:00 the lamps are on and the fronts are lit, and a road mirroring grey
## daylit walls read as a dry, dull street.
const MIRROR_GAIN := 0.9


static func mirror_lamps(w: float) -> float:
	return clampf(w * MIRROR_GAIN, 0.0, 1.0)
