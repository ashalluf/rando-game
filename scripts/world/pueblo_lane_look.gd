class_name PuebloLaneLook
extends RefCounted
## The marketplace lane at eye level (refcam `pueblo_lane`, tools/refcams/cameras_w8.json;
## docs/HANDOFF.md "The marketplace lane at 12:30"). PuebloLane's lane was a long brick carpet with
## two walkers on it at lunch and a seller in one stall of four; the stalls were factory-new paint.
## This holds the numbers that fix that, behind one switch (`PUEBLO_LANE_LOOK=0` the A/B):
## - the lane's crowd by the hour the chunk is built at (`LANE_KEYS`: a market, quiet at night,
##   packed at lunch), the extra walkers spawned after the lane's own on their own seeded stream;
## - a seller in every `VENDOR_EVERY`-th stall (was 4);
## - the lane's brick a worn, browner clay (`BRICK_TINT`, `BRICK_WEAR`) rather than an orange sheet;
## - the pergola's timbers grained (the market's K_WOOD), not flat brown boxes;
## - weathered stall paint (pueblo_market.gdshaderinc `weather`: sun-faded, chipped to grey timber,
##   scuffed and dirty at the foot), 0 = the old paint bit for bit.

static func _static_init() -> void: LoadPulse.compiled()  # a boot frame: docs/HANDOFF.md "The boot compile"

static var enabled: bool = OS.get_environment("PUEBLO_LANE_LOOK") != "0"

## How many times the lane's own walkers (PuebloLane.crowds(), 18), hour by hour from midnight
## (25 keys). A market lane: the stalls open at ten, lunch is the crowd, it thins after dark.
const LANE_KEYS := [0.2, 0.15, 0.1, 0.1, 0.1, 0.1, 0.2, 0.35, 0.7, 1.2, 2.0, 3.0,
	4.4, 4.6, 4.0, 3.4, 3.0, 3.0, 3.2, 2.8, 2.0, 1.3, 0.7, 0.35, 0.2]
## The lane's base count (PuebloLane.crowds()' lane entry).
const LANE_BASE := 18
## At most this many walkers on the lane in all (its two aisles are ~3 m x 118 m each: one person to ~8 m2 of aisle).
const LANE_MOST := 84
## A seller in every this-many stalls.
const VENDOR_EVERY := 2
## The lane's brick: tint on the brick_red set and wear (PuebloLane._ground()).
const BRICK_TINT := Color(0.8, 0.7, 0.64)
const BRICK_WEAR := 0.55
## And how far toward grey (road.gdshader albedo_desat): the brick_red set is an orange photo.
const BRICK_DESAT := 0.32
## The stall paint's weathering (pueblo_market.gdshaderinc `weather`).
const PAINT_WEATHER := 1.0


static func hour_factor(hour: float) -> float:
	var h := fposmod(hour, 24.0)
	var i := floori(h)
	return lerpf(float(LANE_KEYS[i]), float(LANE_KEYS[i + 1]), h - float(i))


## Walkers to add to the lane's base at `hour` (never negative: the base is always spawned).
static func lane_extra(hour: float) -> int:
	if not enabled:
		return 0
	return clampi(roundi(float(LANE_BASE) * hour_factor(hour)), LANE_BASE, LANE_MOST) - LANE_BASE


static func vendor_every() -> int:
	return VENDOR_EVERY if enabled else 4


static func brick_tint() -> Color:
	return BRICK_TINT if enabled else Color(0.92, 0.8, 0.72)


static func brick_wear() -> float:
	return BRICK_WEAR if enabled else 0.25


## A pergola timber's colour, sRGB, from a 0..1 hash: weathered brown, some greyer, some darker.
static func timber(h: float) -> Color:
	return Color(0.4, 0.29, 0.2).lerp(Color(0.44, 0.38, 0.32), h * 0.7).darkened(0.12 * fposmod(h * 7.0, 1.0))


static func paint_weather() -> float:
	return PAINT_WEATHER if enabled else 0.0
