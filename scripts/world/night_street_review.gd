class_name NightStreetReview
extends RefCounted
## The night street review's numbers (docs/HANDOFF.md "The night street at eye level", 2026-10-30),
## in one place with the switch: NIGHT_STREET_REVIEW=0 in the environment puts the moon, the lamps'
## pools and ranges, the mirrored sky and the wet lamp reflections back as they were (the A/B; the
## road shader's mirrored windows are uniforms, see road.gdshader `mirror_window*` / `mirror_sky`).
## Read by DayNight, StreetLamps, BroadwayStreet and NightAtmos; tests/night_street_review_checks.gd
## pins them.

static var enabled: bool = OS.get_environment("NIGHT_STREET_REVIEW") != "0"

## The moon's key (DayNight.night_sun_energy). 0.3 through night_exposure 2.3 was ~45 % of the
## noon sun's key: every street evenly blue with crisp tree and wire shadows, the lamps' pools lost.
const MOON := 0.09
const MOON_OLD := 0.3
## StreetLamps' pools and omni ranges, scaled: at the model's own numbers a lamp lit the pavement
## under it and left the carriageway between lamps black.
const POOL_SCALE := 1.3
const RANGE_SCALE := 1.25
## Broadway's lanterns' real light, as a share of DayNight's lamp level (their low globes stand a
## couple of metres off pale shop fronts).
const BROADWAY_LIGHT := 0.6


static func moon() -> float:
	return MOON if enabled else MOON_OLD


static func pool_scale() -> float:
	return POOL_SCALE if enabled else 1.0


static func range_scale() -> float:
	return RANGE_SCALE if enabled else 1.0


static func broadway_light() -> float:
	return BROADWAY_LIGHT if enabled else 1.0


## The share of the rain's 35 % cut of the ambient fill (DayNight) still made at night: a rainy
## night street came out half as bright as a clear one (pavement p50 15 against 31), where a real
## one is lit by its own sodium light off the cloud base.
const RAIN_NIGHT_CUT := 0.25


static func rain_night_cut() -> float:
	return RAIN_NIGHT_CUT if enabled else 1.0


## The horizon colour the mirrors read (sky_tint): what the sky draws there, rain and overcast
## included. Old (off): the clear sky's horizon under any weather - a rainy night's puddles, sea and
## glass mirrored a navy sky under a brown sodium cloud base.
static func sky_tint(clear_horizon: Color, storm_horizon: Color, weather_darken: float) -> Color:
	return clear_horizon.lerp(storm_horizon, clampf(weather_darken, 0.0, 1.0)) if enabled else clear_horizon
