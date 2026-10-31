class_name SunsetReview
## The sunset on the coast, judged on the `sunset` reference camera (fleet wave 4, `rc-sunset`;
## docs/HANDOFF.md "The sunset on the Esplanade"): the Esplanade looking south down the coast at
## 17:51, the sun on the horizon over the sea to the right, and the same view at 18:36. What gave
## it away (opengl3, main after the golden-hour review):
## - The whole sky was one salmon sheet. DayNight's dusk horizon colour (peach) was painted all the
##   way round the sky, and the violet "earth's shadow" twilight band stood ten degrees up at 80 %
##   while the sun was still two degrees UP - so looking south, 90 degrees off the sun, the sky from
##   the horizon to the top of the frame was mauve-pink. A real sky there is pale blue over a warm
##   low haze, with the clouds lit pink. Now the dusk horizon colour cools toward a slate-lilac of
##   the same brightness round the side away from the sun (sky.gdshader `dusk_away`), and the old
##   twilight band waits for the sun to be down (`band_gain()`; the sunset model's own earth's
##   shadow already rises opposite the sun at the right time).
## - At 18:36 the land was brighter and more orange than the sky above it: the depth fog's colour
##   followed `moonlight` (half way at 18:36) while the sky followed GoldenHour's faster twilight
##   ramp, so every kilometre of air between the camera and the headland was lit orange-brown at a
##   dusk that was already purple. The fog now goes to night on the faster of the two
##   (`fog_night()`), and its dusk colour is a cooler rose-grey (`DUSK_FOG`) - the orange toward the
##   sun is fog_sun_scatter's job.
## - The street lamps' pools lay on the road with the sun still up: a lamp switching on at sunset is
##   not seen against daylight. The lamps' own LIGHT (the OmniLight3Ds) follows the lamp level
##   squared on the way in (`light_level()`); the heads, windows and signs keep `lamp_factor`.
##
## - Past the FULL ring the Esplanade's bluff face is ReplicaBuilder's far ground in ONE colour (a
##   tan the low red sun turned into a clay wedge under the houses); up close it is planted. The far
##   face is mottled now, scrub and ice plant over dirt, per vertex (`bluff_far()`).
##
## SUNSET_REVIEW=0 in the environment is the A/B: every function hands back what DayNight did.

static var enabled: bool = OS.get_environment("SUNSET_REVIEW") != "0"

## sky.gdshader's `dusk_away` at full dusk and its tint (linear, times the horizon's luminance).
const DUSK_AWAY := 1.0
const DUSK_AWAY_TINT := Vector3(0.80, 0.89, 1.24)
## The sun elevations (sine) the old twilight band fades in between: none with the sun clearly up,
## all of it a couple of degrees under the horizon.
const BAND_IN := Vector2(0.06, -0.03)
## The dusk fog colour (DayNight `dusk_fog` was (0.72, 0.45, 0.33): orange in every direction).
const DUSK_FOG := Color(0.66, 0.53, 0.50)


## sky.gdshader's `dusk_away` for this frame: with the dusk's own weight on the horizon.
static func dusk_away(dusk_rim: float) -> float:
	if not enabled:
		return 0.0
	return DUSK_AWAY * clampf(dusk_rim, 0.0, 1.0)


## The twilight band's gain (DayNight hands `1 - sun_high` when off).
static func band_gain(elevation: float, sun_high: float) -> float:
	if not enabled:
		return 1.0 - sun_high
	return smoothstep(BAND_IN.x, BAND_IN.y, elevation)


## How far the depth fog's colour is toward the night's: the faster of the light's ramp and the
## sky's (GoldenHour.sky_night()).
static func fog_night(moonlight: float, sky_night: float) -> float:
	if not enabled:
		return moonlight
	return maxf(moonlight, sky_night)


## The dusk fog colour DayNight lerps to.
static func dusk_fog(old: Color) -> Color:
	return DUSK_FOG if enabled else old


## The street lamps' lights' level from the lamp level (0..1).
static func light_level(lamp: float) -> float:
	if not enabled:
		return lamp
	return lamp * lamp


## The `lamp_ease` global: how far light_pool.gdshader's pools come in on the square of the lamp
## level. Not in bad weather, where the lamps light a dark noon at weather_darken x 0.85.
static func pool_ease(weather_darken: float) -> float:
	if not enabled:
		return 0.0
	return 1.0 - clampf(weather_darken * 1.6, 0.0, 1.0)


## The bluff face's far colour (linear, alpha 0 like ReplicaBuilder.FAR_COLORS) at a vertex: dark
## olive scrub and greener ice plant over the old dirt tan, in patches of about ten metres.
const BLUFF_SCRUB := Color(0.070, 0.085, 0.045, 0.0)
const BLUFF_ICE := Color(0.090, 0.120, 0.050, 0.0)
const BLUFF_DIRT := Color(0.22, 0.19, 0.12, 0.0)


static func bluff_far(p: Vector3, seed_value: int) -> Color:
	var c := Vector2i(int(floor(p.x / 9.0)), int(floor(p.z / 9.0)))
	var h := float(hash([seed_value, c.x, c.y, "bluff_far"]) % 1000) / 999.0
	var k := float(hash([seed_value, int(floor(p.x / 3.0)), int(floor(p.z / 3.0)), "bluff_fine"]) % 1000) / 999.0
	var plant := BLUFF_SCRUB.lerp(BLUFF_ICE, k)
	# About two thirds planted; the rest bare dirt, a little darker than the old flat tan.
	return plant if h < 0.68 else BLUFF_DIRT.lerp(plant, 0.35 * k)
