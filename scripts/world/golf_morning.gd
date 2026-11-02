class_name GolfMorning
extends RefCounted
## The golf course in the morning (wave 6, refcam `golf_morning` in tools/refcams/cameras_w6.json,
## docs/HANDOFF.md "The golf course at 08:30"). The switch for what that view found reads fake:
## shaders/golf_turf.gdshader's tee divots (real scars in worn rows, not 33 cm squares), the dew on
## the turf in the early hours, and the rest listed in the HANDOFF section. `GOLF_MORNING=0` in the
## environment is the A/B: the `golf_morning` shader global goes to 0 and every branch it gates
## draws the course as it was.

static var enabled: bool = OS.get_environment("GOLF_MORNING") != "0"


## Pushes the switch to the shaders (GolfBuild.turf_material(), the first course chunk).
static func install() -> void:
	RenderingServer.global_shader_parameter_set("golf_morning", 1.0 if enabled else 0.0)


## Turns it on or off at once (tests).
static func set_enabled(on: bool) -> void:
	enabled = on
	install()


# --- Mirrors of shaders/golf_turf.gdshader (the checks hold the two together) --------------------

## dew_amount(): how much dew lies on the course at hour `h` (0..1): all night and at dawn, burnt
## off between DEW_GONE.x and DEW_GONE.y, back from DEW_BACK.x to DEW_BACK.y in the evening.
const DEW_GONE := Vector2(8.6, 10.6)
const DEW_BACK := Vector2(20.0, 23.5)


static func dew(h: float) -> float:
	return (1.0 - smoothstep(DEW_GONE.x, DEW_GONE.y, h)) * (1.0 if h >= 3.0 else 0.0) + smoothstep(DEW_BACK.x, DEW_BACK.y, h)


## A tee marker as the real ones are (golf_morning): a painted ball the size of a grapefruit, a
## little sunk into the turf - stacked rings of ParkKit's posts, rounder than the tin-can cylinder it
## replaces, a few dozen triangles.
const BALL_RINGS := [[0.030, 0.000, 0.018], [0.052, 0.018, 0.022], [0.064, 0.040, 0.036], [0.058, 0.076, 0.024], [0.042, 0.100, 0.018], [0.020, 0.118, 0.010]]


static func tee_ball(w: SurfaceTool, at: Vector3, color: Color) -> void:
	for r: Array in BALL_RINGS:
		ParkKit.post(w, at + Vector3(0.0, float(r[1]), 0.0), float(r[0]), float(r[2]), ParkKit.K_PLASTIC, color, 12)
