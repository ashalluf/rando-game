class_name MarineMorning
extends RefCounted
## June gloom at street level (refcam `marine_morning`, tools/refcams/cameras_w5.json: the beach
## town at 08:00 under the marine layer). Three things the deck alone did not give the street:
##
## - DAMP: under the deck overnight and in the morning the mist and the odd drizzle leave the
##   streets damp - darker asphalt, a faint sheen, the kerbs and puddle hollows holding it longest.
##   Weather takes `damp()` as a floor under its wetness target and, with no rain falling, dries
##   it the uneven way (the `road_drying` look), never the even film of a shower.
## - MIST: near the coast in the morning the air under the deck is thick: the end of a street
##   toward the sand goes soft and the sea's horizon is lost in grey. `mist()` is extra depth-fog
##   density, faded out inland over COAST_REACH.
## - THE DECK'S UNDERSIDE: stratocumulus seen from under it is cells and rolls, darker where it
##   is thick and lighter in the thin gaps, brighter toward the sun; the old underside varied by
##   ~3 grey levels and read as a flat painted ceiling. marine_layer.gdshader's `look` (this
##   file's LOOK) switches its new underside on.
##
## Pure functions of the hour, the weather and the place (Weather and the checks call them).
## `MARINE_MORNING=0` in the environment turns all three off (the A/B).

static var enabled: bool = OS.get_environment("MARINE_MORNING") != "0"

## Road wetness the mist leaves under a full deck (0..1, Weather's `wetness` scale; a shower is
## 0.84 and soaks; 0.3 is a damp, darkened street with water only in the low spots).
const DAMP := 0.3
## Extra depth fog under the deck at the coast in the morning (Godot fog density; the marine
## layer's own haze is Weather.marine_fog 0.00022). 0.001 with it puts e^-1 at ~0.8 km at the beach (about the visibility of a gloomy morning).
const MIST := 0.001
## The mist fades out between these distances inland of the coast line (m).
const COAST_NEAR := 900.0
const COAST_REACH := 3200.0
## How unevenly the damp lies (Weather's `road_drying` while only the mist wets the street): 0
## is a shower's even film, 1 the ragged patches of a street drying after rain, which with a thin
## damp read as hard-edged oil stains. Between: the film is even, mottled at its edges.
const DRYING := 0.0
## marine_layer.gdshader `look` while on (1 = the cellular underside).
const LOOK := 1.0


## How much of the morning's damp and mist the hour carries (0..1): all night and through the
## morning, gone once the deck has thinned by late morning; back as the evening bank comes ashore.
static func morning(hour: float) -> float:
	var h := fposmod(hour, 24.0)
	if h < 12.0:
		return 1.0 - smoothstep(10.0, 11.5, h)
	return smoothstep(20.5, 23.0, h)


## The street wetness floor under the deck (`here`: Weather.marine_here, 0..1).
static func damp(here: float, hour: float) -> float:
	if not enabled:
		return 0.0
	return DAMP * clampf(here, 0.0, 1.0) * morning(hour)


## Extra fog density at a camera `inland` metres east of the coast line.
static func mist(here: float, hour: float, inland: float) -> float:
	if not enabled:
		return 0.0
	var coast := 1.0 - smoothstep(COAST_NEAR, COAST_REACH, inland)
	return MIST * clampf(here, 0.0, 1.0) * morning(hour) * coast


## The deck shader's look switch.
static func deck_look() -> float:
	return LOOK if enabled else 0.0
