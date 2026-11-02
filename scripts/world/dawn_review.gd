class_name DawnReview
## The dawn review (fleet wave 4, `dawn-review`; docs/HANDOFF.md "The dawn review"): 05:00-08:30
## judged on the refcams' street, golden aerial, hills and beach views at 06:15, 07:00 and 08:00
## (tools/dawn_review/cameras.json through refcams) and tuned. Until now the morning was the
## evening played backwards: every ramp DayNight runs is a function of the sun's elevation alone,
## so a sunrise wore the sunset's smoggy orange, the GOLDEN grade's red mids and the dusk fog's
## orange haze, and the street lamps burned until the sun was seven degrees up. A Los Angeles
## dawn is the other way round: the air is cleanest of the day (the smog builds through it), the
## light is a cooler, pinker gold, the haze lying in the basin is cool and grey-blue, and the
## street lamps' photocells switch them off before the sunrise.
##
## Everything here is a weight on the MORNING (`weight()`: 0 from noon on, 0 with the sun more
## than ~21 degrees down or ~38 up), so noon, the afternoon, the evening and the night are
## bit-identical; DayNight asks it at each place a number is handed out. DAWN_REVIEW=0 in the
## environment is the A/B (every hook returns its input).

static var enabled: bool = OS.get_environment("DAWN_REVIEW") != "0"

## Sun elevations (sine of the arc) the dawn weight ramps in between (x none, y full) and out
## between (z full, w none): from ~21 degrees down (05:20) to full by ~10 down (05:37), whole
## through the sunrise, gone by ~38 degrees up (08:30).
const RAMP := Vector4(-0.36, -0.18, 0.30, 0.62)

## The sun's colour low over a clean morning basin: still gold, less red than the evening's
## (1, 0.6, 0.35), with more blue in it - a 5-degree sunrise reads pink-gold, not orange.
const SUN := Color(1.0, 0.66, 0.46)
## The twilight sky at dawn: the zenith a clearer, cooler blue than the dusk's, the horizon a
## pale rose-peach, not the evening's orange.
const SKY_TOP := Color(0.09, 0.21, 0.54)
const HORIZON := Color(1.0, 0.66, 0.52)
## The clouds' lit and shadow side at dawn: pink-gold over a cool lilac grey.
const CLOUD := Color(1.0, 0.78, 0.66)
const CLOUD_SHADOW := Color(0.46, 0.40, 0.54)
## The haze in the basin at dawn: a rose-grey morning mist, not the dusk's orange or the
## smog's brown (a cold grey-blue one drained the whole 06:15 frame to 0.2 saturation). And how much of the golden-hour smog a morning keeps (DayNight.smog_morning is
## already 0.45 of the evening's): what is left of yesterday's, hugging the horizon.
const FOG := Color(0.68, 0.60, 0.60)
const SMOG := 0.6
## Morning haze: depth fog thickened by this with the sun low (dew and the night's cool air
## lying in the basin), easing out as the sun climbs (`FOG_EASE`, elevations: full, gone).
const MIST := 1.15
const FOG_EASE := Vector2(0.06, 0.30)
## The grade: the GOLDEN look's share at dawn (its red mids and warm highlights belong to the
## evening), and the BLUE hour's cool look reaching a little past the sunrise.
const GOLDEN_GRADE := 0.7
## The street lamps' photocells switch off at a higher light than they switch on at (the
## hysteresis every photocontrol has), so at dawn they go out before the sunrise: the lamp level
## falls from 1 at x to 0 at y (elevations: ~4.6 degrees down, 05:42, to ~0.6 up, 06:02), where
## the evening's ramp (night_factor) runs from 3 down to 7 up.
const LAMPS_OFF := Vector2(-0.08, 0.01)


## How much of the dawn there is: 0 from noon on and outside RAMP. Pure.
static func weight(hour: float, elevation: float) -> float:
	if not enabled or hour >= 12.0:
		return 0.0
	return smoothstep(RAMP.x, RAMP.y, elevation) * (1.0 - smoothstep(RAMP.z, RAMP.w, elevation))


## A colour DayNight hands out, taken toward its dawn value by the weight.
static func color(c: Color, dawn: Color, w: float) -> Color:
	if w <= 0.0:
		return c
	return c.lerp(dawn, w)


## The smog the sky and the far land are given (DayNight's `smog`, already times smog_morning).
static func smog(s: float, w: float) -> float:
	if w <= 0.0:
		return s
	return s * lerpf(1.0, SMOG, w)


## The depth fog's gain: the morning mist with the sun low.
static func fog_gain(gain: float, w: float, elevation: float) -> float:
	if w <= 0.0:
		return gain
	return gain * lerpf(1.0, MIST, w * (1.0 - smoothstep(FOG_EASE.x, FOG_EASE.y, elevation)))


## The golden weight HourGrade is given.
static func golden_grade(golden: float, w: float) -> float:
	if w <= 0.0:
		return golden
	return golden * lerpf(1.0, GOLDEN_GRADE, w)


## The street lamps' level at dawn: off before the sunrise. night_factor otherwise.
static func lamp_factor(night_factor: float, hour: float, elevation: float) -> float:
	if not enabled or hour >= 12.0 or elevation < LAMPS_OFF.x - 0.05:
		return night_factor
	return minf(night_factor, 1.0 - smoothstep(LAMPS_OFF.x, LAMPS_OFF.y, elevation))
