class_name BrushFireLook
extends RefCounted
## The brush fire on a Santa Ana evening, as the brush_fire refcam judged it (docs/HANDOFF.md "The
## brush fire on a Santa Ana evening"). SantaAnaFx and DayNight ask this for the numbers; with
## BRUSH_FIRE_LOOK=0 every answer is the old one (the A/B).
##
## - The column: denser, darker brown-grey smoke lit by the fire from below and the twilight from
##   above, wide at its foot and laid over hard by the wind into a long PALL that drifts out over
##   the basin (a second emitter, flat puffs a kilometre up): from the city the sky downwind of a
##   ridge fire is brown, not a clean dusk.
## - The fire line: tongues along a curve that falls away down both flanks of the crest (the
##   ridge is a summit, never a ruler line), broken into runs, with a smouldering burnt band under
##   them; the card stands lower so the hill in front hides its foot.
## - The sky at dusk and night: the horizon a dusty amber-brown, the zenith muddied, the depth fog
##   brown (the smoke the whole basin is breathing).
## - The litter: bigger, more of it, and ash flakes in the air.

static var enabled: bool = OS.get_environment("BRUSH_FIRE_LOOK") != "0"

## The column (SantaAnaFx._build_plume when enabled).
const PLUME_PUFFS := 150
const PLUME_SIZE := Vector2(180.0, 520.0)
const PLUME_RISE := Vector2(7.0, 12.0)
## How hard the wind lays the column over (m/s2 along SANTA_ANA_DIR; the old 0.55).
const PLUME_LEAN := 1.25
## Smoke colour (linear) and how dark the thick cores are.
const SMOKE_COL := Vector3(0.17, 0.15, 0.135)
const CORE_SHADE := 0.45
## The fire's light on the column: it reaches this far up (m; the old 210).
const GLOW_FALL := 240.0
const GLOW_COL := Vector3(0.40, 0.12, 0.025)

## The pall: flat puffs drifting downwind a kilometre up.
const PALL_PUFFS := 46
const PALL_LIFE := 160.0
const PALL_HEIGHT := Vector2(650.0, 1050.0)
const PALL_SIZE := Vector2(700.0, 1500.0)
const PALL_SPEED := Vector2(9.0, 14.0)
const PALL_OPACITY := 0.42

## The fire card (SantaAnaFx._build_glow / drive when enabled): width, height, how far under the
## site its foot stands, and the flank fall in card heights at its ends.
const FIRE_WIDTH := 640.0
const GLOW_HEIGHT := 300.0
const FOOT_DROP := 70.0
const FLANK_FALL := 0.42
## The line's crest stands this far under the site (m): the drawn ridge is lower than the
## real one out there, and a line just behind the crest reads as a fire over the ridge.
const LINE_SINK := 40.0

## The sky's smoke at dusk and after dark (DayNight; Colours as DayNight hands its own over).
const SMOKE_RIM := Color(0.66, 0.40, 0.22)
const SMOKE_RIM_NIGHT := Color(0.20, 0.10, 0.05)
const SMOKE_TOP := Color(0.13, 0.12, 0.17)
const RIM_MIX := 0.6
const TOP_MIX := 0.4
const SMOKE_FOG := Color(0.55, 0.36, 0.24)
const SMOKE_FOG_NIGHT := Color(0.16, 0.09, 0.05)
const FOG_MIX := 0.55

## Litter: amount and size (the old 90 and 0.08-0.22 m).
const LITTER_AMOUNT := 160
const LITTER_SIZE := Vector2(0.11, 0.26)
## Ash flakes in the air round the player.
const ASH_AMOUNT := 120


## How much of the sky's smoke shows: none by day (the wind cleared the basin), all of it from
## dusk on, a little less in a deep night (the glow on the pall is what is left then).
static func sky_weight(santa_ana: float, dusk: float, moonlight: float) -> float:
	if not enabled or santa_ana <= 0.0:
		return 0.0
	return santa_ana * smoothstep(0.05, 0.6, dusk) * (1.0 - 0.3 * moonlight)


## The sky's zenith and horizon with the smoke in them: [top, rim].
static func sky(top: Color, rim: Color, santa_ana: float, dusk: float, moonlight: float) -> Array:
	var w := sky_weight(santa_ana, dusk, moonlight)
	if w <= 0.0:
		return [top, rim]
	return [top.lerp(SMOKE_TOP, TOP_MIX * w), rim.lerp(SMOKE_RIM.lerp(SMOKE_RIM_NIGHT, moonlight), RIM_MIX * w)]


## The depth fog's colour with the smoke in it.
static func fog(col: Color, santa_ana: float, dusk: float, moonlight: float) -> Color:
	var w := sky_weight(santa_ana, dusk, moonlight)
	if w <= 0.0:
		return col
	return col.lerp(SMOKE_FOG.lerp(SMOKE_FOG_NIGHT, moonlight), FOG_MIX * w)
