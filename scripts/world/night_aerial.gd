class_name NightAerial
extends RefCounted
## The night aerial review (refcam `night_aerial`, tools/refcams/cameras_w5.json; docs/HANDOFF.md
## "The night aerial review"): downtown and the basin from 350 m at 22:30. What gave the frame away,
## fixed in shaders that were already running, behind the `night_aerial` global:
## - FLOODLIT MASONRY (window_lights.gdshaderinc tower_wash()): 60 % of masonry buildings over
##   22 m were uplit warm from the foot, and on brick and render that is a saturated orange-red box;
##   from the air the basin was dotted with glowing embers. Now a third of those (salt 113,
##   FLOOD_KEEP) keep their floods, a fifth of the masonry in all, and the light is a cooler white.
## - THE FREEWAY AS A CREAM SLAB (far_traffic.gdshaderinc ft_mean_shape()): an LOD deck 400-900 m
##   below drew each lane's light mean evenly over the whole lane and bloomed for a river kilometres
##   off. Where a pixel still spans less than a car cell, the mean is drawn as its cars (each cell
##   taken lit along its car, held to the lamps' line across the lane, the total kept) and the bloom
##   eases in with distance (FT_NEAR_BLOOM .. FT_BLOOM_FULL).
## - THE FREEWAY'S POOLS (light_pool.gdshader, display_add pools): a hard rim and a white disc per
##   light standard down the deck; the rim is eased in and they dim for a camera in the air.
## - FAR SEARCHLIGHTS (searchlight_beam.gdshader, the helicopters'; nightlife_beam.gdshader from the
##   air): a shaft a kilometre or two off drew as a solid white wedge (its alpha runs far over 1 and
##   was hard-clamped); far off it now saturates softly and fades to `far_gain` / `beam_far_gain`.
## `NIGHT_AERIAL=0` in the environment turns it off (the A/B): the global goes to 0 and every
## shader is as it was. tests/rc2_night_aerial_checks.gd holds the copies below equal.

static var enabled: bool = OS.get_environment("NIGHT_AERIAL") != "0"

## tower_wash(): of the masonry NightSkyline.FLOOD_SHARE floods, the share kept (salt 113).
const FLOOD_KEEP := 0.33
## tower_wash(): the floods' strength (was 1.5).
const FLOOD_GAIN := 1.1


## Pushes the switch to the shaders (DayNight._ready()).
static func install() -> void:
	RenderingServer.global_shader_parameter_set("night_aerial", 1.0 if enabled else 0.0)


## Turns the pass on or off at once (tests, stills).
static func set_enabled(on: bool) -> void:
	enabled = on
	install()


## True when masonry building `b_seed` (% 1000) is floodlit at night (tower_wash()'s rolls).
static func floodlit(b_seed: int) -> bool:
	var s := clampi(b_seed, 0, 999)
	if NightSkyline.roll(s, 68) >= NightSkyline.FLOOD_SHARE:
		return false
	return not enabled or NightSkyline.roll(s, 113) < FLOOD_KEEP


## far_traffic.gdshaderinc's mean shape: the bloom's share at a couple of metres a pixel, where it is
## full, and the pixel sizes (metres) over which the car cells fade out.
const NEAR_BLOOM := 0.5
const BLOOM_FULL := 8.0
const CELLS_FROM := 5.0
const CELLS_GONE := 13.0


## ft_mean_shape()'s along term averaged over a lane: 1 for any share taken (the total is kept).
## Pure, for the checks: `cells` cells at share `lvl` over many roads (a seed per 32), rolled like the shader's.
static func mean_along(lvl: float, seed: float, cells: int = 3200) -> float:
	var total := 0.0
	for c in cells:
		var key := Vector3(float(c % 32), 0.0, seed + float(c >> 5))
		if NightFlight.ft_hash(key) < lvl:
			total += 14.0 / (4.6 * lvl) * 4.6
	return total / (14.0 * float(cells))
