class_name GoldenHour
## The golden-hour review (fleet wave 3, `golden-hour-review`; docs/HANDOFF.md "The golden hour
## review"): 17:00-19:30 judged on six views x six half hours (tools/golden_hour, refcams with its
## own table) and tuned - no new system, only which ramp an existing colour follows and the numbers
## DayNight already exports. What the strips showed on main (opengl3; numbers in the HANDOFF):
## - The sky went to its NIGHT colours on `night_factor`, which is 1 three degrees after sunset
##   (18:11): from there the whole sky was night while its horizon still glowed, and everything that
##   mirrors or is lit by it (`sky_tint`: the sea, the wet sand, glass; the cubemap's ambient)
##   went black with it - the beach toward the afterglow was 25-45 % crushed at 18:30-19:30. The
##   sky now darkens on its own twilight ramp (`sky_night()`: civil to nautical dusk, ~18:01-18:50).
## - At the sunset itself the whole frame was red: the violet earth's-shadow band sat 17 degrees up
##   at full strength over a magenta zenith, so the ambient (the sky) was red and the shadows as red
##   as the light; then the GOLDEN grade pushed red into the mids on top (hills: 73 % of the pixels
##   orange, saturation 0.80). The zenith holds blue, the band hugs the horizon, and the GOLDEN
##   look eases while the light itself is red (`golden_grade()`).
## - The sun falls to its night energy at the sunset, but the exposure followed the slow moonlight
##   ramp: 18:00 was the darkest frame of the evening (street ground median 16 against 37 at 18:30).
##   The exposure now starts its way to the night's as the light falls (`exposure_mix()`).
## - The light handed from the sunset to the moon too blue: 18:30 brown, 19:00 teal hills.
## - The golden-hour smog lid flattened the ranges and the far city to one beige (17:30 aerial).
##
## GOLDEN_HOUR_REVIEW=0 in the environment is the A/B: DayNight takes its old numbers back
## (`restore()`), the sky darkens on night_factor and the grade is as it was.

static var enabled: bool = OS.get_environment("GOLDEN_HOUR_REVIEW") != "0"

## The sun elevations (sine of the arc) the sky's night colours ramp in between: from just under
## the horizon to about 12.5 degrees down (nautical dusk). night_factor (0.117 .. -0.05) stays the
## switch for the lamps and the windows.
const SKY_NIGHT := Vector2(0.03, -0.22)
## The GOLDEN look's share left at the sunset (the sun on the horizon), easing back to all of it
## by GRADE_EASE's upper elevation: the scene is already as red as the light.
const SUNSET_GRADE := 0.45
const GRADE_EASE := Vector2(-0.02, 0.12)

## The exposure's early ramp: this share of the way to the night exposure by the sunset (from
## EXPOSURE_EASE's upper elevation, ~17:25, to its lower, ~18:05), handing over to the slow
## moonlight ramp once that passes it, so the frame's brightness falls monotonically.
const SUNSET_EXPOSURE := 0.5
const EXPOSURE_EASE := Vector2(0.15, -0.02)

## DayNight's numbers before the review, put back with GOLDEN_HOUR_REVIEW=0.
const OLD := {
	"dusk_sky_top": Color(0.16, 0.18, 0.42),
	"dusk_horizon": Color(1.0, 0.55, 0.3),
	"sunset_band": Color(0.46, 0.26, 0.52),
	"twilight_band_height": Vector2(0.30, 0.16),
	"night_sun_color": Color(0.62, 0.72, 1.0),
	"golden_fog_gain": 1.45,
	"ground_smog": 0.7,
}


## How far into its night colours the sky is: its own twilight ramp, or night_factor when off.
static func sky_night(elevation: float, night_factor: float) -> float:
	if not enabled:
		return night_factor
	return smoothstep(SKY_NIGHT.x, SKY_NIGHT.y, elevation)


## What HourGrade multiplies the GOLDEN look's weight by.
static func golden_grade(elevation: float) -> float:
	if not enabled:
		return 1.0
	return lerpf(SUNSET_GRADE, 1.0, smoothstep(GRADE_EASE.x, GRADE_EASE.y, elevation))


## How far DayNight's exposure is from the day's toward the night's: moonlight, or the early
## ramp while that is larger.
static func exposure_mix(elevation: float, moonlight: float) -> float:
	if not enabled:
		return moonlight
	return maxf(moonlight, SUNSET_EXPOSURE * smoothstep(EXPOSURE_EASE.x, EXPOSURE_EASE.y, elevation))


## Called by DayNight._ready(): with the review off, its old numbers.
static func restore(day: Node) -> void:
	if enabled or day == null:
		return
	for key: String in OLD:
		day.set(key, OLD[key])
