class_name NightAerial
extends RefCounted
## The night aerial review (refcam `night_aerial`, tools/refcams/cameras_w5.json; docs/HANDOFF.md
## "The night aerial review"): downtown and the basin from 350 m at 22:30. What gave the frame away,
## fixed in shaders that were already running, behind the `night_aerial` global:
## - FLOODLIT MASONRY (window_lights.gdshaderinc tower_wash()): 60 % of masonry buildings over
##   22 m were uplit warm from the foot, and on brick and render that is a saturated orange-red box;
##   from the air the basin was dotted with glowing embers. Now a third of those (salt 113,
##   FLOOD_KEEP) keep their floods, a fifth of the masonry in all, and the light is a cooler white.
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
