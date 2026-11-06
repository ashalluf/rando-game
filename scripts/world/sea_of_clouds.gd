class_name SeaOfClouds
extends RefCounted
## The marine layer seen from ABOVE (refcam `sea_of_clouds`, tools/refcams/cameras_w8.json: the
## east range at 08:30 looking west over the deck). What the deck's top did not give the view:
##
## - A THINNER DECK INLAND: the morning deck's top was one flat sheet at LaWeather.DECK_TOP (520 m)
##   everywhere, which buried every tower (262-335 m) and the whole front range (crest ~380 m): from
##   the hills there was nothing but a white plain. A real June gloom deck is deepest at the coast
##   and thins inland toward where it is burning off, so its top falls: `top_at()` holds COAST_TOP
##   within NEAR of the coast and falls to INLAND_TOP by FAR inland, in the morning only (`morning()`:
##   the afternoon bank offshore and the evening fog bank keep their heights). The underside stays
##   at DECK_BASE (the street views under the deck - marine_morning, cemetery_dawn - are untouched).
##   The crowns of downtown and the front range's crests stand out of it as islands.
## - A SOFT SHORE: the deck plane met every hillside and tower in a ruler-hard line (the depth test).
##   marine_layer.gdshader's top fades its alpha by how far the scene behind it is (`soft_shore`
##   metres), so stratus laps up a slope and wraps a tower's foot.
## - A CLOUD TOP WITH RELIEF: the top was lit as low noise rolls (0.4 + 0.6 n.l, unshaded) - a flat
##   white plain from 600 m. The new top (`top_look`) is stratocumulus cells: domed billows each lit
##   on its sun side and shaded in the troughs, a silver sheen toward the sun, finer lumps near.
## - THE FAR SEA: the deck planes faded out over 5.2-7.6 km, so past that the city under the deck
##   showed through as grey ground. Looking out over the basin the deck now runs to the camera's far
##   haze (`FAR_RADIUS`).
##
## `SEA_OF_CLOUDS=0` in the environment turns it all off (the A/B).

static var enabled: bool = OS.get_environment("SEA_OF_CLOUDS") != "0"

## The deck's top at the coast in the morning (m): a typical June gloom inversion (~1,400 ft). The
## overnight and evening decks keep LaWeather's heights.
const COAST_TOP := 430.0
## The deck's top well inland on a burning-off morning (true world metres). Downtown's crowns
## (the 310 m round tower, the 335 m sail) and the front range's crests (~380 m) stand out of it.
const INLAND_TOP := 282.0
## The top is COAST_TOP within NEAR of the coast line and INLAND_TOP from FAR inland (m).
const NEAR := 600.0
const FAR := 3600.0
## Metres of scene depth behind the deck's top over which it thins out against what it meets.
const SOFT_SHORE := 55.0
## Radius of the deck planes while on (m): the camera draws to 12 km.
const FAR_RADIUS := 12000.0


## How much of the inland thinning the hour carries (0..1): the overnight deck is deep, it thins
## from dawn and is gone with the burn-off.
static func morning(hour: float) -> float:
	if not enabled:
		return 0.0
	var h := fposmod(hour, 24.0)
	return smoothstep(4.0, 7.0, h) * (1.0 - smoothstep(LaWeather.BURN_END - 1.5, LaWeather.BURN_END, h))


## The deck's top at true world x (m) at `hour`, the coast line at `coast_x`; `top` the hour's
## top (LaWeather.deck_heights().y). Mirrored in marine_layer.gdshader top_y().
static func top_at(coast_x: float, hour: float, x: float, top: float) -> float:
	var m := morning(hour)
	if m <= 0.0:
		return top
	var inland := smoothstep(NEAR, FAR, x - coast_x)
	return lerpf(top, minf(top, lerpf(COAST_TOP, INLAND_TOP, inland)), m)


## marine_layer.gdshader `top_look` (1 the billowed top and the soft shore).
static func look() -> float:
	return 1.0 if enabled else 0.0
