class_name ChaseCamReview
extends RefCounted
## The chase_cam reference camera's review (tools/refcams/cameras_w5.json; docs/HANDOFF.md "The
## chase camera's street"): what read fake first from behind the wheel of the player's own car on
## a downtown avenue at 16:00, fixed where it is made.
##
## - The carriageway, half the frame from a chase camera, was one even sheet of tarmac: no wheel
##   tracks, no oil down the lanes, no grit at the kerb. road.gdshader's `lane_wear`
##   (shaders/road_lane_wear.gdshaderinc) on the asphalt sets' street materials.
##
## CHASE_CAM_REVIEW=0 in the environment puts every one of them back as it was (the A/B).

static var enabled: bool = OS.get_environment("CHASE_CAM_REVIEW") != "0"

## Lane wear strength per texture set (carriageway asphalt only; never paving or pavements).
const LANE_WEAR := {"asphalt": 1.0, "asphalt_aerial": 1.0}


## road.gdshader `lane_wear` for a road material: the carriageway's sets at full wear, nothing on
## a jointed surface (pavements, plazas) or a lightly worn one (car parks, yards keep `wear` < 1).
static func lane_wear(set_key: String, joints: float, wear: float) -> float:
	if not enabled or joints > 0.01 or wear < 0.99:
		return 0.0
	return float(LANE_WEAR.get(set_key, 0.0))
