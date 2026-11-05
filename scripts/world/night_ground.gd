class_name NightGround
extends RefCounted
## The night ground (wave 8, rc5-gas-station-night; docs/HANDOFF.md "The gas station at 23:30").
## At 23:30 the city's streets read lit nearly like day: pale, even asphalt and pavements with no
## pool under a lamp and no dark between (lead review). Measured with refcams NIGHT_AB (the frame
## again with each source off): the street lamps' OmniLights, their additive pools and the moon
## each put an even wash on the road, because the city stands a lamp every 24 m on BOTH kerbs
## (staggered: one every 12 m) and each omni reached 2.4 x its height with a d^-1.5 falloff - every
## point of the street sat inside two or three lamps' light. And on Compatibility (the web, every
## opengl3 still) the pool was added at full strength on top of the omni, where Forward+ adds only
## `street_forward` 0.4 of it (the omni already lights the road there).
##
## The fix, at the source and the same everywhere a street lamp stands:
## * the omni falls off as a point source does, d^-FALLOFF (2.0), reaching REACH_PER_HEIGHT (2.0) x
##   its height. NightLamps.tune_light()'s gain normalises by h^attenuation, so the light UNDER each
##   head is unchanged; only the road between lamps darkens (about a third at 1.7 h);
## * on Compatibility a street lamp's pool takes POOL_COMPAT (0.45) of its strength
##   (light_pool.gdshader `street_compat`), as Forward+ takes street_forward.
##
## `NIGHT_GROUND=0` is the A/B (NightLamps' numbers and the full compat pool, as before).

static var enabled: bool = OS.get_environment("NIGHT_GROUND") != "0"

const FALLOFF := 2.0
const REACH_PER_HEIGHT := 2.0
const POOL_COMPAT := 0.45


static func falloff(old: float) -> float:
	return FALLOFF if enabled else old


static func reach_per_height(old: float) -> float:
	return REACH_PER_HEIGHT if enabled else old


static func pool_compat() -> float:
	return POOL_COMPAT if enabled else 1.0
