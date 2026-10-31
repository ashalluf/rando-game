class_name StreetNoonReview
extends RefCounted
## The street_noon reference camera's review (docs/HANDOFF.md, "The street at noon"): what read
## fake first at eye level on Flower at Olympic at noon, fixed where it is made.
##
## - The asphalt: Asphalt033 is a photo of brown-grey tarmac (HSV saturation 0.17, the aerial set
##   0.06). On Forward+ the grade's saturation took it to a dirt-road brown under the noon sun (the
##   Compatibility stills hide it). road.gdshader / road_patch.gdshader take `albedo_desat` toward
##   the texture's own luminance before the tint, set here per texture set (`desat()`).
## - Lane lines on a light-rail street where the line runs underground: Flower carries the Coral
##   Line end to end, so RoadHardware kept every marker and Botts' dot off it - even over the
##   tunnel, where the street is an ordinary four-lane road. `rail_surface_near()` says where the
##   line is really in the street (trench, grade, structure), and only there are they kept off.
## - The centre line of a road with two lanes each way: a single dashed yellow is a two-lane
##   street's; a four-lane one is a double yellow (`double_yellow()`).
## - Pavers: the square-slab photo's grout is gravel and moss (bright olive lines at noon), and the
##   anti-repeat fetch, turned 37 degrees, drew a ghost of the slab grid across the slabs.
##   `variant_mode()` keeps the second fetch on the grid; `desat()` greys the moss.
## - Bike lanes: shaders/bike_lane.gdshader's `grime` (dirt along the kerb, tyre polish, aggregate
##   in the paint), set by Micromobility's material when this is on.
##
## STREET_NOON=0 in the environment puts every one of them back as it was (the A/B).

static var enabled: bool = OS.get_environment("STREET_NOON") != "0"

## How far toward its own luminance an asphalt texture is taken (0 = the photo as it is).
const DESAT := {"asphalt": 0.65, "asphalt_aerial": 0.45, "pavers": 0.55}
## road.gdshader `variant_mode` per texture set: the square pavers turn by a quarter, the
## running-bond setts mirror (their grid lands on itself); everything else keeps the rotation.
const VARIANT_MODE := {"pavers": 1, "paving": 2}
## Each line of a double yellow stands this far off the centre (m): the dash box is 16 cm wide.
const DOUBLE_YELLOW_OFFSET := 0.14
## Bike lane paint wear (bike_lane.gdshader `grime`).
const BIKE_GRIME := 1.0
## How near (m) the line has to come out of its tunnel for the street's middle to stay unmarked.
const RAIL_REACH := 14.0


## `albedo_desat` for a road material on texture set `set_key`.
static func desat(set_key: String) -> float:
	if not enabled:
		return 0.0
	return float(DESAT.get(set_key, 0.0))


## `variant_mode` for a road material on texture set `set_key`.
static func variant_mode(set_key: String) -> int:
	if not enabled:
		return 0
	return int(VARIANT_MODE.get(set_key, 0))


## True when the light rail stands in the street (anything but its tunnel) within RAIL_REACH of
## `p` (true world XZ), or when its underground station opens through the street there.
static func rail_surface_near(plan: CityPlan, p: Vector2) -> bool:
	var rail := LightRail.of(plan)
	if rail == null:
		return false
	var r := Rect2(p - Vector2(RAIL_REACH, RAIL_REACH), Vector2(RAIL_REACH, RAIL_REACH) * 2.0)
	for i in rail.indices_in(r):
		if i < rail.mode.size() and rail.mode[i] != LightRail.Mode.TUNNEL:
			return true
	if not MetroStation.cuts_in(plan, r.grow(6.0)).is_empty():
		return true
	return false


## Whether RoadHardware may mark the middle of a light-rail street at `p`: only over the tunnel.
static func marks_rail_street(plan: CityPlan, p: Vector2) -> bool:
	return enabled and not rail_surface_near(plan, p)


## A road `width` wide carries two lanes each way (TrafficManager's rule), so its centre is a
## double yellow, not a two-lane street's dashes.
static func double_yellow(width: float, street_width: float) -> bool:
	return enabled and width > street_width + 1.0
