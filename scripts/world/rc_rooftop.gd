class_name RcRooftop
extends RefCounted
## The rooftop refcam (wave 6, `rooftop_golden` in tools/refcams/cameras_w6.json: downtown from a
## tower's helipad at 17:45, looking over the skyline to the basin and the sea; docs/HANDOFF.md "The
## skyline from a tower's roof"). One switch for what that view found:
##   * LandmarkRoofs: the downtown towers' bare mechanical boxes clad as louvred penthouses and
##     their flat roofs dressed with plant (its own LANDMARK_ROOFS=0 as well);
##   * the offshore island against a low sun as the air draws it (`island_soft` in
##     shaders/offshore_island.gdshaderinc), not a hard dark brown strip.
## RC_ROOFTOP=0 is the A/B of all of it (the city exactly as before).

static var enabled := OS.get_environment("RC_ROOFTOP") != "0"


## The sky shader's `island_soft` (OffshoreIsland pushes it once).
static func island_soft() -> float:
	return 1.0 if enabled else 0.0
