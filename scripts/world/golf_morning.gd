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
